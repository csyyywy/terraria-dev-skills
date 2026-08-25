# ============================================================
# headless-test.ps1 - Automated tModLoader headless server test
#
# Flow: (optional) build -> sandbox setup -> non-interactive server
#       start -> command-file bridge -> assert results -> graceful stop.
#
# Requires: dotnet SDK, tModLoader install, target mod containing a
#           SelfTestSystem bridge (see examples/SelfTestCommand.cs,
#           doc: resources/13-headless-testing.md).
#
# NOTE (verified 2026-02): piping commands to server stdin does NOT work on
#       Windows (console API input; log shows "handle invalid"). All mod
#       interaction goes through the command/result FILE bridge instead.
# ============================================================
[CmdletBinding()]
param(
    [string]$TmlDir  = '',          # 留空自动探测常见安装位置（或显式传入）
    [string]$DotNet  = '',          # 留空自动探测带 SDK 的 dotnet（或显式传入）
    [string]$ProjectPath,                 # csproj to build (optional if -TmodPath given)
    [string]$TmodPath,                    # prebuilt .tmod (optional alternative)
    [Parameter(Mandatory)][string]$ModName,
    [string[]]$Commands    = @('ping'),
    [string[]]$ExpectCases = @('ping'),   # case names expected inside results.txt
    [int]$TimeoutSec       = 240,
    [int]$Port             = 0,           # 0 = random 7700-7999
    [string]$WorkRoot      = ''           # sandbox root (default: temp)
)

$ErrorActionPreference = 'Stop'
$sw = [Diagnostics.Stopwatch]::StartNew()
function Log($m) { Write-Host ('[{0,4}s] {1}' -f [int]$sw.Elapsed.TotalSeconds, $m) }

if (-not $DotNet) {
    foreach ($cand in @((Join-Path $env:USERPROFILE '.dotnet\dotnet.exe'), 'C:\Program Files (x86)\dotnet\dotnet.exe')) {
        if (Test-Path $cand) { $DotNet = $cand; break }
    }
}
if (-not $DotNet) { $DotNet = 'dotnet' }
if ($DotNet -ne 'dotnet' -and -not (Test-Path $DotNet)) { throw "dotnet not found: $DotNet" }
if (-not $TmlDir) {
    foreach ($cand in @((Join-Path $env:ProgramFiles 'Steam\steamapps\common\tModLoader'),
                        (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\tModLoader'))) {
        if (Test-Path "$cand\tModLoader.dll") { $TmlDir = $cand; break }
    }
}
if (-not (Test-Path "$TmlDir\tModLoader.dll")) { throw "tModLoader.dll not found under $TmlDir (pass -TmlDir)" }
if ($Port -eq 0) { $Port = Get-Random -Minimum 7700 -Maximum 7999 }
if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ("tml-headless-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }

# --- 1. build (optional) ---------------------------------------------------
if ($ProjectPath) {
    Log "building $ProjectPath ..."
    & $DotNet build $ProjectPath -c Debug | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "build failed (exit $LASTEXITCODE)" }
}

# --- 2. locate .tmod -------------------------------------------------------
$tmod = $TmodPath
if (-not $tmod) {
    $dirs = @(
        (Join-Path $env:USERPROFILE "Documents\My Games\Terraria\tModLoader\Mods"),
        (Join-Path $TmlDir "Mods")
    )
    $exact = $dirs | ForEach-Object { Join-Path $_ "$ModName.tmod" } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exact) { $tmod = $exact }
    else {
        $tmod = $dirs | ForEach-Object { Get-ChildItem $_ -Filter '*.tmod' -ErrorAction SilentlyContinue } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}
if (-not $tmod -or -not (Test-Path $tmod)) { throw ".tmod for '$ModName' not found (build first?)" }
Log "using tmod: $tmod"

# --- 3. sandbox ------------------------------------------------------------
$saves  = Join-Path $WorkRoot 'saves'
$mods   = Join-Path $WorkRoot 'mods'
$outDir = Join-Path $WorkRoot 'out'
foreach ($d in @((Join-Path $saves 'Worlds'), $mods, (Join-Path $WorkRoot 'in'), $outDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Copy-Item $tmod $mods -Force
Set-Content (Join-Path $mods 'enabled.json') ('["' + $ModName + '"]') -Encoding utf8

$worldFile = Join-Path $saves 'Worlds\test.wld'
$cfgFile   = Join-Path $WorkRoot 'serverconfig.txt'
$cmdFile   = Join-Path $WorkRoot 'in\commands.txt'
$resFile   = Join-Path $outDir 'results.txt'

@(
    "world=$worldFile"
    "autocreate=1"
    "worldname=headless-test"
    "maxplayers=1"
    "port=$Port"
) | Set-Content -Encoding utf8 $cfgFile

Set-Content -Encoding utf8 -Path $resFile -Value ''
Set-Content -Encoding utf8 -Path $cmdFile  -Value (($Commands -join "`r`n") + "`r`n")

# --- 4. launch (direct process; stdout/stderr collected via events) --------
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $DotNet
$psi.Arguments              = '"{0}\tModLoader.dll" -server -config "{1}" -tmlsavedirectory "{2}" -modpath "{3}"' -f `
                                $TmlDir, $cfgFile, $saves, $mods
$psi.WorkingDirectory       = $TmlDir
$psi.UseShellExecute        = $false
$psi.CreateNoWindow         = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.EnvironmentVariables['TML_SELFTEST_DIR'] = $WorkRoot   # bridge root for SelfTestSystem

$script:OutLines = [System.Collections.Generic.List[string]]::new()
$p = [System.Diagnostics.Process]::Start($psi)
Register-ObjectEvent -InputObject $p -EventName OutputDataReceived -MessageData $script:OutLines -Action {
    if ($EventArgs.Data) { $Event.MessageData.Add($EventArgs.Data) }
} | Out-Null
Register-ObjectEvent -InputObject $p -EventName ErrorDataReceived -MessageData $script:OutLines -Action {
    if ($EventArgs.Data) { $Event.MessageData.Add($EventArgs.Data) }
} | Out-Null
$p.BeginOutputReadLine()
$p.BeginErrorReadLine()
Log "server pid=$($p.Id) port=$Port workroot=$WorkRoot"

function Stop-Server([string]$reason) {
    try {
        if (-not $p.HasExited) {
            Add-Content -Encoding utf8 -Path $cmdFile -Value '#exit'
            Log "sent #exit ($reason); waiting graceful stop ..."
            if (-not $p.WaitForExit(20000)) { Log "graceful stop timed out -> Kill"; $p.Kill() }
        }
    } catch { try { $p.Kill() } catch {} }
    Set-Content -Encoding utf8 -Path (Join-Path $outDir 'server-stdout.log') -Value ($script:OutLines -join "`r`n")
}

$gracefulExit = $false
try {
    # --- 5. wait for ready marker -----------------------------------------
    $ready = $false
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Seconds 2
        if ($p.HasExited) { break }
        if ($script:OutLines -contains 'Server started') { $ready = $true; Log 'server READY'; break }
    }
    if (-not $ready) { throw "server not ready within ${TimeoutSec}s (see logs under $outDir)" }

    # --- 6. wait for expected cases in results.txt ------------------------
    $pending = [System.Collections.Generic.HashSet[string]]::new([string[]]$ExpectCases)
    $results = @()
    while ($pending.Count -gt 0 -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Seconds 2
        if ($p.HasExited) { break }
        if (Test-Path $resFile) {
            $results = Select-String -Path $resFile -Pattern '\[TEST\] (.+?) (PASS|FAIL)(?: (.*))?$' |
                ForEach-Object { @{
                    Case   = $_.Matches[0].Groups[1].Value
                    Status = $_.Matches[0].Groups[2].Value
                    Detail = $_.Matches[0].Groups[3].Value
                } }
            foreach ($r in $results) { [void]$pending.Remove($r.Case) }
        }
    }

    # --- 7. summary --------------------------------------------------------
    $pass = @($results | Where-Object { $_.Status -eq 'PASS' })
    $fail = @($results | Where-Object { $_.Status -eq 'FAIL' })
    Log ("RESULT: PASS={0} FAIL={1} MISSING={2}" -f $pass.Count, $fail.Count, ($pending -join ','))
    foreach ($f in $fail) { Log ("FAIL: {0} :: {1}" -f $f.Case, $f.Detail) }
    foreach ($m in @($pending)) { Log "MISSING CASE: $m" }

    Stop-Server 'done'
    $gracefulExit = $p.HasExited

    $ok = ($fail.Count -eq 0 -and $pending.Count -eq 0)
    [PSCustomObject]@{
        Ok = $ok; Pass = $pass.Count; Fail = $fail.Count; Missing = @($pending)
        GracefulExit = $gracefulExit; WorkRoot = $WorkRoot; ElapsedSec = [int]$sw.Elapsed.TotalSeconds
    } | Format-List | Out-Host

    if (-not $ok) { exit 1 } else { exit 0 }
}
catch {
    Stop-Server "error: $($_.Exception.Message)"
    throw
}
finally {
    if (-not $gracefulExit) { Stop-Server 'finally-cleanup' }
    Log "artifacts: workroot=$WorkRoot"
}
