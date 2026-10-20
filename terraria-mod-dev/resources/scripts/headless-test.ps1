# ============================================================
# headless-test.ps1 - tModLoader 无头构建验证 / 服务器自检
#
# 用法:
#   默认（不传 -ValidateOnly 即为 $true）只做「构建验证」：dotnet build 成功即算通过，
#   不启动服务器、不生成世界、不跑用例。
#   显式传 -ValidateOnly:$false 才走完整服务器自检：
#     build -> 沙盒 -> 无头服务器 -> 指令文件桥 -> 断言 results -> 优雅退出。
#
# 注意：Windows 下无法通过管道向服务器喂命令（控制台 API 限制），
# 全部交互走 in/commands.txt + out/results.txt 文件桥。
# ============================================================
[CmdletBinding()]
param(
    [string]$TmlDir  = $env:TML_DIR,      # tModLoader 安装目录；也可用环境变量 TML_DIR
    # 必须指向带 SDK 的 dotnet：`dotnet --list-sdks` 能看到 9.x
    [string]$DotNet  = 'dotnet',
    [string]$ProjectPath,                 # csproj to build (optional if -TmodPath given)
    [string]$TmodPath,                    # prebuilt .tmod (optional alternative)
    [string[]]$BuildProps = @(),           # 额外 build 参数；csproj 用属性导入 targets 时传 @('-p:MyTMLPath=<TML_DIR>')
    [Parameter(Mandatory)][string]$ModName,
    [switch]$ValidateOnly = $true,        # 默认：只验证构建，不起服务器
    [string[]]$Commands    = @('ping'),
    [string[]]$ExpectCases = @('ping'),   # case names expected inside results.txt
    [int]$TimeoutSec       = 240,
    [int]$Port             = 0,           # 0 = random 7700-7999
    [string]$WorkRoot      = ''           # sandbox root (default: temp)
)

$ErrorActionPreference = 'Stop'
$sw = [Diagnostics.Stopwatch]::StartNew()
function Log($m) { Write-Host ('[{0,4}s] {1}' -f [int]$sw.Elapsed.TotalSeconds, $m) }

if ($DotNet -eq 'dotnet') {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw "dotnet not found in PATH" }
} elseif (-not (Test-Path $DotNet)) { throw "dotnet not found: $DotNet" }
if (-not $TmlDir) { throw "pass -TmlDir <tModLoader install dir> or set env TML_DIR" }
if (-not (Test-Path "$TmlDir\tModLoader.dll")) { throw "tModLoader.dll not found under $TmlDir" }
if ($Port -eq 0) { $Port = Get-Random -Minimum 7700 -Maximum 7999 }
if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ("tml-headless-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }

# --- 1. build (optional) ---------------------------------------------------
if ($ProjectPath) {
    Log "building $ProjectPath ..."
    # 若 csproj 通过属性导入 tMLMod.targets（如 <Import Project="$(MyTMLPath)\tMLMod.targets" />），
    # 用 -BuildProps "-p:MyTMLPath=$TmlDir" 把 tML 目录传进去。
    # ValidateOnly：只编译不打包（-p:BuildMod=false，无需关游戏；打包被文件锁挡住时交给发布流程）
    $pkg = if ($ValidateOnly) { '-p:BuildMod=false' } else { '' }
    $buildArgs = @('build', $ProjectPath, '-c', 'Debug') + $BuildProps
    if ($pkg) { $buildArgs += $pkg }
    & $DotNet @buildArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "build failed (exit $LASTEXITCODE)" }
}

# --- 1b. validate-only mode: build success = pass ---------------------------
if ($ValidateOnly) {
    if (-not $ProjectPath) { throw "-ValidateOnly needs -ProjectPath (there is nothing to build)" }
    # 附加 hjson 语法校验（真实 Hjson 解析器）：hjson malformed 会导致模组被禁用
    $hjsonScript = Join-Path $PSScriptRoot 'check-hjson.ps1'
    $locDir = Join-Path (Split-Path $ProjectPath) 'Localization'
    if ((Test-Path $hjsonScript) -and (Test-Path $locDir)) {
        Log "validating hjson localization files ..."
        & $hjsonScript -Dir $locDir -DotNet $DotNet 2>&1 | ForEach-Object { Log $_ }
        if ($LASTEXITCODE -ne 0) { throw "hjson validation failed" }
    }
    Log "VALIDATE-ONLY: build + hjson -> PASS"
    [PSCustomObject]@{ Ok = $true; Mode = 'validate-only'; ElapsedSec = [int]$sw.Elapsed.TotalSeconds } | Format-List | Out-Host
    exit 0
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

# 世界缓存：只生成一次，之后所有运行复用（校验模组加载根本不需要每次重建世界）。
# 若缓存缺失，先从旧沙盒捡一个现成的（避免第一次也生成）。
$worldCacheDir = Join-Path $env:TEMP 'tml-headless-worlds'
New-Item -ItemType Directory -Force -Path $worldCacheDir | Out-Null
$worldFile = Join-Path $worldCacheDir 'test.wld'
if (-not (Test-Path $worldFile)) {
    $old = Get-ChildItem (Join-Path $env:TEMP 'tml-headless-*') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'saves\Worlds\test.wld' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($old) {
        Copy-Item $old $worldFile -Force
        $oldTwld = [IO.Path]::ChangeExtension($old, '.twld')
        if (Test-Path $oldTwld) { Copy-Item $oldTwld ([IO.Path]::ChangeExtension($worldFile, '.twld')) -Force }
        Log "reused cached world from previous sandbox"
    }
}

$cfgFile   = Join-Path $WorkRoot 'serverconfig.txt'
$cmdFile   = Join-Path $WorkRoot 'in\commands.txt'
$resFile   = Join-Path $outDir 'results.txt'

$cfg = @(
    "world=$worldFile"
    "worldname=headless-test"
    "maxplayers=1"
    "port=$Port"
)
if (-not (Test-Path $worldFile)) { $cfg += 'autocreate=1' }  # 仅缓存缺失时生成一次
$cfg | Set-Content -Encoding utf8 $cfgFile

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
$psi.EnvironmentVariables['MOD_TESTDIR'] = $WorkRoot   # bridge root for SelfTestSystem

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
    # stdout 在重定向模式下不可靠（"句柄无效"后部分控制台输出只进日志不进 stdout）。
    # 以文件桥为准：results.txt 出现 "[TEST] ping PASS/FAIL" 即世界已就绪（PostUpdateWorld 在跑）。
    # 生成一个小世界通常约 5~10 秒，1 秒轮询足够；总超时由 TimeoutSec 兜底。
    $ready = $false
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Seconds 1
        if ($p.HasExited) { break }
        if ($script:OutLines -contains 'Server started') { $ready = $true; Log 'server READY (stdout)'; break }
        if ((Test-Path $resFile) -and (Select-String -Path $resFile -Pattern '\[TEST\] ping (PASS|FAIL)' -Quiet)) {
            $ready = $true; Log 'server READY (file bridge)'; break
        }
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
