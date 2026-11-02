# ============================================================
# headless-test.ps1 — tModLoader 无头构建验证 / 服务端自检
#
#   -Mode Validate  构建（可只编译）+ hjson 校验，不启动服务器（默认）
#   -Mode Server    构建 → 隔离沙盒 → 无头服务器 → 指令文件桥 → 断言 → 收工
#   -PlanOnly       只打印将要执行的命令行与配置，不启动任何东西
#
# 设计要点（每条都由实测或源码验证，改动前请先复现）：
#   1. 就绪必须自证：只认 results.txt 里的 [TEST] ping PASS，不认 stdout 的 Server started。
#   2. world= 指向不存在的文件时，服务器打印 "Load failed! No backup found." 后卡在
#      Console.ReadKey()，永远不会 Listening —— 所以只在缓存世界可用时才写 world=。
#   3. 服务器进程不要接 stdout 管道；这里用文件重定向。
#   4. 桥的环境变量名有两种约定，两个都设：MOD_TESTDIR 与 <ModName>_TESTDIR。
#   5. 端口不要用 7491-7990：Windows 常把这段保留给 Hyper-V / WSL。
# ============================================================
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('Validate', 'Server')]
    [string]$Mode = 'Validate',

    # 兼容旧参数：-ValidateOnly / -ValidateOnly:$false（已弃用，映射到 -Mode）
    [switch]$ValidateOnly,

    [string]$TmlDir  = $env:TML_DIR,
    [string]$DotNet  = 'dotnet',
    [string]$ProjectPath,
    [string]$TmodPath,
    [string[]]$BuildProps = @(),
    [Parameter(Mandatory)][string]$ModName,

    [string[]]$Commands    = @('ping'),
    [string[]]$ExpectCases = @('ping'),
    [int]$TimeoutSec       = 240,
    [int]$BridgeGraceSec   = 45,
    [int]$SettleSec        = 3,           # 期望用例齐了之后再等几秒，收尾阶段的 FAIL 也算数
    [bool]$FailOnAnyFail   = $true,       # 结果里有任何 FAIL 就判失败（默认开；-FailOnAnyFail:$false 只看期望用例）
    [int]$Port             = 0,
    [string]$WorkRoot      = '',
    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
# pwsh -File 把 "a,b" 当作**一个**字符串传进来；不拆开就会整行写进 commands.txt
$Commands    = @($Commands    | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$ExpectCases = @($ExpectCases | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$sw = [Diagnostics.Stopwatch]::StartNew()
function Log($m) { Write-Host ('[{0,4}s] {1}' -f [int]$sw.Elapsed.TotalSeconds, $m) }

if ($PSBoundParameters.ContainsKey("ValidateOnly")) {
    $Mode = if ($ValidateOnly) { 'Validate' } else { 'Server' }
    Log "WARN -ValidateOnly 已弃用，请用 -Mode Validate|Server（本次按 -Mode $Mode 处理）"
}

# ---- 1. 启动前一次性校验 -------------------------------------------------
$problems = @()
if (-not $TmlDir) { $problems += "缺少 -TmlDir（或环境变量 TML_DIR）" }
elseif (-not (Test-Path (Join-Path $TmlDir "tModLoader.dll"))) { $problems += "tModLoader.dll 不存在：$TmlDir" }

if ($DotNet -eq "dotnet") {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { $problems += "PATH 里没有 dotnet" }
} elseif (-not (Test-Path $DotNet)) { $problems += "dotnet 不存在：$DotNet" }

if ($ProjectPath -and -not (Test-Path $ProjectPath)) { $problems += "csproj 不存在：$ProjectPath" }
if ($TmodPath -and -not (Test-Path $TmodPath)) { $problems += ".tmod 不存在：$TmodPath" }
if (-not $ProjectPath -and -not $TmodPath) { $problems += "至少需要 -ProjectPath 或 -TmodPath" }

if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "  x $_" }
    throw "参数校验失败（$($problems.Count) 项）"
}

# ---- 2. 端口 -------------------------------------------------------------
function Test-PortFree([int]$p) {
    try {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
        $l.Start(); $l.Stop(); return $true
    } catch { return $false }
}
if ($Port -eq 0) {
    $candidates = @(8123) + (8000..8099) + (9000..9099)
    $Port = $candidates | Where-Object { Test-PortFree $_ } | Select-Object -First 1
    if (-not $Port) { throw "找不到空闲端口" }
} elseif (-not (Test-PortFree $Port)) {
    throw "端口 $Port 已被占用"
}

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ("tml-headless-" + [guid]::NewGuid().ToString("N").Substring(0, 8)) }
Log "mode=$Mode mod=$ModName port=$Port workroot=$WorkRoot"

# ---- 3. 构建 -------------------------------------------------------------
if ($ProjectPath) {
    Log "building $ProjectPath ..."
    # BuildMod=false 时 tMLMod.targets 不再设置 TargetFramework，必须自己补，否则 NETSDK1013
    $packDir = Join-Path $WorkRoot "_pack"   # 打包到临时目录：不写玩家 Mods，游戏开着也不会 TML003
    # 自动带上 TMLDir 属性：csproj 用 <Import Project="$(TMLDir)	MLMod.targets" /> 时不用再手动传，
    # 也避免用户写 -BuildProps '-p:TMLDir=...' 被 PowerShell 当成参数名解析。
    $buildArgs = @("build", $ProjectPath, "-c", "Debug", "-p:TMLDir=$TmlDir",
                   "-p:ExtraBuildModFlags=-tmlsavedirectory $packDir") + $BuildProps
    $buildLog = & $DotNet @buildArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $buildLog | Select-Object -Last 15 | ForEach-Object { Log "  build| $_" }
        throw "build failed (exit $LASTEXITCODE)"
    }
    $built = Join-Path (Join-Path $packDir "Mods") "$ModName.tmod"
    if (Test-Path $built) { $TmodPath = $built; Log "built: $built" }
}

if ($Mode -eq "Validate") {
    if (-not $ProjectPath) { throw "-Mode Validate 需要 -ProjectPath" }
    $hjsonScript = Join-Path $PSScriptRoot "check-hjson.ps1"
    $locDir = Join-Path (Split-Path $ProjectPath) "Localization"
    if ((Test-Path $hjsonScript) -and (Test-Path $locDir)) {
        Log "validating hjson ..."
        & $hjsonScript -Dir $locDir -DotNet $DotNet 2>&1 | ForEach-Object { Log $_ }
        if ($LASTEXITCODE -ne 0) { throw "hjson validation failed" }
    }
    Log "VALIDATE: build + hjson -> PASS"
    [PSCustomObject]@{ Ok = $true; Mode = $Mode; ElapsedSec = [int]$sw.Elapsed.TotalSeconds } | Format-List | Out-Host
    exit 0
}

# ---- 4. 定位 .tmod -------------------------------------------------------
function Resolve-Tmod([string]$Path, [string]$Name) {
    if ($Path) { if (Test-Path $Path) { return (Resolve-Path $Path).Path } else { throw ".tmod 不存在：$Path" } }
    $dirs = @(
        (Join-Path (Join-Path $env:USERPROFILE "Documents\My Games\Terraria\tModLoader") "Mods"),
        (Join-Path $TmlDir "Mods")
    )
    $exact = $dirs | ForEach-Object { Join-Path $_ "$Name.tmod" } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exact) { return (Resolve-Path $exact).Path }
    throw "找不到 $Name.tmod（先构建，或显式给 -TmodPath）"
}
$tmod = Resolve-Tmod -Path $TmodPath -Name $ModName
Log "tmod: $tmod"

# ---- 5. 依赖模组（build.txt 的 modReferences）----------------------------
$depNames = @()
if ($ProjectPath) {
    $buildTxt = Join-Path (Split-Path $ProjectPath) "build.txt"
    if (Test-Path $buildTxt) {
        foreach ($line in Get-Content $buildTxt) {
            if ($line -match "^\s*modReferences\s*=\s*(.+)$") {
                $depNames += ($Matches[1] -split ",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }
        }
    }
}
$depNames = @($depNames | Select-Object -Unique)
$depFiles = @()
foreach ($d in $depNames) {
    $cand = @(
        (Join-Path $TmlDir "Mods\$d.tmod"),
        (Join-Path (Join-Path $env:USERPROFILE "Documents\My Games\Terraria\tModLoader\Mods") "$d.tmod")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($cand) { $depFiles += $cand } else { Log "WARN 依赖 $d 未找到，服务器可能回退到安装目录的 Mods" }
}
if ($depNames.Count -gt 0) { Log ("deps: " + ($depNames -join ", ")) }

# ---- 6. 沙盒 -------------------------------------------------------------
$saves  = Join-Path $WorkRoot "saves"
$mods   = Join-Path $WorkRoot "mods"
$outDir = Join-Path $WorkRoot "out"
$inDir  = Join-Path $WorkRoot "in"
$worlds = Join-Path $saves "Worlds"
foreach ($d in @($worlds, $mods, $inDir, $outDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

Copy-Item $tmod $mods -Force
foreach ($dep in $depFiles) { Copy-Item $dep $mods -Force }
$enabled = @($ModName) + $depNames
Set-Content (Join-Path $mods "enabled.json") (ConvertTo-Json $enabled -Compress) -Encoding utf8

# ---- 7. 世界：缓存按模组集合隔离；只在文件可用时才写 world= ----------------
$sha = [System.Security.Cryptography.SHA256]::Create()
$keyParts = @()
foreach ($f in (@($tmod) + $depFiles)) { $fi = Get-Item $f; $keyParts += ($fi.Name + ":" + $fi.Length) }
$keyText = ($ModName + "|" + ($keyParts -join "|"))
$hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($keyText))).Replace("-", "").Substring(0, 12).ToLower()
$worldCacheDir = Join-Path (Join-Path $env:TEMP "tml-headless-worlds") ($ModName + "_" + $hash)
New-Item -ItemType Directory -Force -Path $worldCacheDir | Out-Null
$worldCache = Join-Path $worldCacheDir "world.wld"
$worldName  = "headless_" + $hash

function Test-WorldUsable([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    if ((Get-Item $path).Length -le 1MB) { return $false }
    # 被 kill 的运行会留下截断/清零的世界，大小照样过 1MB；读一下版本号（int32）兜底
    try {
        $fs = [IO.File]::OpenRead($path)
        $buf = New-Object byte[] 4
        $null = $fs.Read($buf, 0, 4)
        $fs.Close()
        $ver = [BitConverter]::ToInt32($buf, 0)
        return ($ver -ge 100 -and $ver -le 400)
    } catch { return $false }
}

# 只写 world=<路径>：worldpath= 不会设置 worldPathName，服务器照样进 Choose World 交互态。
# world= 指向不存在的文件 + autocreate=1 会自动建世界（实测 15s / 2.9MB）；
# 文件已存在时 autocreate 被忽略，正常加载（实测不会重建）。
$useCache = Test-WorldUsable $worldCache
$sandboxWorld = Join-Path $worlds "world.wld"
if ($useCache) {
    Copy-Item $worldCache $sandboxWorld -Force
    $twld = [IO.Path]::ChangeExtension($worldCache, ".twld")
    if (Test-Path $twld) { Copy-Item $twld (Join-Path $worlds "world.twld") -Force }
    Log "world: cache hit"
} else {
    Log "world: 首次生成（小世界实测约 15 秒；大世界或首次加载模组更久）"
}
$cfg = @(
    "world=$sandboxWorld"
    "worldname=$worldName"
    "autocreate=1"
)
$cfg += @("maxplayers=1", "port=$Port", "upnp=0", "difficulty=0")

$cfgFile = Join-Path $WorkRoot "serverconfig.txt"
$cmdFile = Join-Path $inDir "commands.txt"
$resFile = Join-Path $outDir "results.txt"
$stdout  = Join-Path $outDir "server-stdout.log"
$stderr  = Join-Path $outDir "server-stderr.log"

$cfg | Set-Content $cfgFile -Encoding utf8
Set-Content $resFile "" -Encoding utf8

# ping 必须先跑：它既是就绪信号也是桥的自证
if ($Commands -notcontains "ping") { $Commands = @("ping") + $Commands }
if ($ExpectCases -notcontains "ping") { $ExpectCases = @("ping") + $ExpectCases }
$lines = @($Commands)
Set-Content $cmdFile (($lines -join [Environment]::NewLine) + [Environment]::NewLine) -Encoding utf8

$serverArgs = ('"{0}\tModLoader.dll" -server -config "{1}" -tmlsavedirectory "{2}" -modpath "{3}"' -f $TmlDir, $cfgFile, $saves, $mods)

# ---- 8. PlanOnly ---------------------------------------------------------
if ($PlanOnly) {
    Log "--- PLAN ONLY ---"
    Log "exe : $DotNet"
    Log "args: $serverArgs"
    Log "cwd : $TmlDir"
    Log "env : MOD_TESTDIR=$WorkRoot ; ($ModName)_TESTDIR=$WorkRoot"
    $cfg | ForEach-Object { Log "  cfg| $_" }
    Log ("mods: " + ($enabled -join ", "))
    Log ("cases: " + ($ExpectCases -join ", "))
    exit 0
}

# ---- 9. 清理同沙盒的残留进程（按命令行特征，不按进程名）------------------
$stale = Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($WorkRoot) }
foreach ($s in $stale) { Log "清理残留 pid=$($s.ProcessId)"; try { Stop-Process -Id $s.ProcessId -Force -ErrorAction Stop } catch {} }

# ---- 10. 启动 ------------------------------------------------------------
$env:MOD_TESTDIR = $WorkRoot
Set-Item -Path ("env:" + $ModName + "_TESTDIR") -Value $WorkRoot

$p = Start-Process -FilePath $DotNet -ArgumentList $serverArgs -WorkingDirectory $TmlDir -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
Log "server pid=$($p.Id) port=$Port"

function Dump-Diagnostics([string]$why) {
    Log "--- 诊断（$why）---"
    Get-Content $cfgFile -ErrorAction SilentlyContinue | ForEach-Object { Log "  cfg| $_" }
    $w = Join-Path $worlds "world.wld"
    Log ("world: exists=" + (Test-Path $w) + " size=" + $(if (Test-Path $w) { (Get-Item $w).Length } else { 0 }))
    Log ("results: " + $(if (Test-Path $resFile) { (Get-Item $resFile).Length } else { "missing" }) + " bytes")
    Log "--- results.txt 全文 ---"
    if (Test-Path $resFile) { Get-Content $resFile -ErrorAction SilentlyContinue | ForEach-Object { Log "  res| $_" } }
    else { Log "  (没有 results.txt)" }
    Log "--- server.log 尾部 20 行 ---"
    $srvLogPath = Join-Path (Join-Path $TmlDir "tModLoader-Logs") "server.log"
    if (Test-Path $srvLogPath) { Get-Content $srvLogPath -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Log "  srv| $_" } }
    else { Log "  (没有 $srvLogPath)" }
    Log "--- stdout 尾部 25 行 ---"
    Get-Content $stdout -Tail 25 -ErrorAction SilentlyContinue | ForEach-Object { Log "  out| $_" }
    $log = Join-Path (Join-Path $TmlDir "tModLoader-Logs") "server.log"
    if (Test-Path $log) {
        Select-String -Path $log -Pattern "ERROR|error occurred|Missing|Sandboxing|disabled" -ErrorAction SilentlyContinue |
            Select-Object -Last 12 | ForEach-Object { Log "  log| $($_.Line)" }
    } else { Log "  (没有 $log)" }
}

function Stop-Server([string]$reason) {
    try {
        if (-not $p.HasExited) {
            Add-Content -Encoding utf8 -Path $cmdFile -Value "#exit"
            Log "sent #exit ($reason)"
            # 无客户端时世界不 tick，#exit 可能永远读不到；沙盒进程直接 Kill 即可，别在这里等 20 秒
            if (-not $p.WaitForExit(5000)) { Log "5s 内未退出（无客户端时属于正常）-> Kill"; $p.Kill(); $p.WaitForExit(5000) | Out-Null }
        }
    } catch { try { $p.Kill() } catch {} }
}

$failReason = $null
try {
    # ---- 11. 就绪 = 桥自证（[TEST] ping），不是 stdout 文本 ----------------
    $ready = $false
    $listeningAt = $null
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Milliseconds 500
        if (Test-Path $stdout) {
            $bad = Select-String -Path $stdout -Pattern "Load failed|Choose World|Missing mod|An error occurred" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($bad) { $failReason = "服务器报错：" + $bad.Line.Trim(); break }
        }
        if ($p.HasExited) { $failReason = "服务器提前退出 (exit=$($p.ExitCode))"; break }

        if (Test-Path $stdout) {
            if (-not $listeningAt -and (Select-String -Path $stdout -Pattern "Listening on port" -Quiet -ErrorAction SilentlyContinue)) {
                $listeningAt = $sw.Elapsed.TotalSeconds
                Log "server listening at ${listeningAt}s; waiting for bridge ping ..."
            }
        }

        if ((Test-Path $resFile) -and (Select-String -Path $resFile -Pattern "^\[TEST\] ping (PASS|FAIL)" -Quiet -ErrorAction SilentlyContinue)) {
            $ready = $true; break
        }

        if ($listeningAt -and ($sw.Elapsed.TotalSeconds - $listeningAt) -gt $BridgeGraceSec) {
            $failReason = "服务器已就绪但桥无响应（${BridgeGraceSec}s 内没有 [TEST] ping）"
            break
        }
    }

    if (-not $ready -and -not $failReason) { $failReason = "超时（${TimeoutSec}s）仍无 [TEST] ping" }
    if ($failReason) {
        Dump-Diagnostics $failReason
        # 桥"已启用但从不泵"是最容易误判的一种：直接把原因和改法说出来
        if ($failReason -match "桥无响应") {
            $srvLog = Join-Path (Join-Path $TmlDir "tModLoader-Logs") "server.log"
            $bridgeLines = @()
            if (Test-Path $srvLog) {
                $bridgeLines = Select-String -Path $srvLog -Pattern "SelfTest|桥已启用|bridge" -ErrorAction SilentlyContinue | Select-Object -Last 3
            }
            if ($bridgeLines.Count -gt 0) {
                Log "模组侧的桥日志："
                $bridgeLines | ForEach-Object { Log ("  bridge| " + $_.Line) }
            }
            Log "=> 桥没有产出 [TEST] ping。无客户端时世界不 tick（DedServ_PostModLoad: if (Netplay.HasClients) Game.Update），"
            Log "   每帧钩子（PostUpdateWorld / PostUpdateEverything）不会被调用。"
            Log "   改法：纯数据用例放到 ModSystem.OnWorldLoad；需要 tick 的行为测试用技能 terraria-headless-test。"
        }
        if ($useCache -and ($failReason -match "Load failed|提前退出|报错")) {
            Remove-Item $worldCache -Force -ErrorAction SilentlyContinue
            Remove-Item ([IO.Path]::ChangeExtension($worldCache, ".twld")) -Force -ErrorAction SilentlyContinue
            Log "已删除不可用的世界缓存：$worldCache（下次会重新生成）"
        }
        throw $failReason
    }
    Log "server READY (bridge ping)"

    # ---- 12. 等其余用例 ---------------------------------------------------
    $pending = [System.Collections.Generic.HashSet[string]]::new([string[]]$ExpectCases)
    $results = @()
    while ($pending.Count -gt 0 -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Milliseconds 700
        if ($p.HasExited) { break }
        if (Test-Path $resFile) {
            $results = Select-String -Path $resFile -Pattern "^\[TEST\] (\S+) (PASS|FAIL)\s*(.*)$" -ErrorAction SilentlyContinue |
                ForEach-Object { @{ Case = $_.Matches[0].Groups[1].Value; Status = $_.Matches[0].Groups[2].Value; Detail = $_.Matches[0].Groups[3].Value } }
            foreach ($r in $results) { [void]$pending.Remove($r.Case) }
        }
    }

    # 期望用例齐了不等于跑完了：再等 SettleSec 收尾，避免漏掉之后才写进 results.txt 的 FAIL
    $settleDeadline = (Get-Date).AddSeconds($SettleSec)
    while ((Get-Date) -lt $settleDeadline) {
        Start-Sleep -Milliseconds 300
        if ($p.HasExited) { break }
    }
    if (Test-Path $resFile) {
        $results = Select-String -Path $resFile -Pattern "^\[TEST\] (\S+) (PASS|FAIL)\s*(.*)$" -ErrorAction SilentlyContinue |
            ForEach-Object { @{ Case = $_.Matches[0].Groups[1].Value; Status = $_.Matches[0].Groups[2].Value; Detail = $_.Matches[0].Groups[3].Value } }
    }

    $pass = @($results | Where-Object { $_.Status -eq "PASS" })
    $failed = @($results | Where-Object { $_.Status -eq "FAIL" })
    Log ("RESULT: PASS={0} FAIL={1} MISSING={2}" -f $pass.Count, $failed.Count, ($pending -join ","))
    foreach ($f in $failed) { Log ("FAIL: {0} :: {1}" -f $f.Case, $f.Detail) }
    foreach ($m in @($pending)) { Log "MISSING CASE: $m" }

    $unexpected = @($failed | Where-Object { $ExpectCases -notcontains $_.Case })
    foreach ($u in $unexpected) { Log ("UNEXPECTED FAIL: {0} :: {1}" -f $u.Case, $u.Detail) }

    # 默认"任何 FAIL 都算失败"；-FailOnAnyFail:$false 时只判定 ExpectCases 里的用例
    $failOk = if ($FailOnAnyFail) { $failed.Count -eq 0 } else { @($failed | Where-Object { $ExpectCases -contains $_.Case }).Count -eq 0 }
    $ok = ($failOk -and $pending.Count -eq 0)

    if (-not $ok) { Dump-Diagnostics ("存在失败用例：FAIL=" + $failed.Count + " MISSING=" + $pending.Count) }
    Stop-Server "done"
    [PSCustomObject]@{
        Ok = $ok; Mode = $Mode; Pass = $pass.Count; Fail = $failed.Count; Missing = @($pending)
        WorkRoot = $WorkRoot; Port = $Port; ElapsedSec = [int]$sw.Elapsed.TotalSeconds
    } | Format-List | Out-Host
    exit ([int](-not $ok))
}
catch {
    Dump-Diagnostics $_.Exception.Message
    Stop-Server "error"
    throw
}
finally {
    if ($p -and -not $p.HasExited) { Stop-Server "finally" }
    $produced = Join-Path $worlds "world.wld"
    if (-not $useCache -and (Test-WorldUsable $produced)) {
        Copy-Item $produced $worldCache -Force
        $tw = [IO.Path]::ChangeExtension($produced, ".twld")
        if (Test-Path $tw) { Copy-Item $tw ([IO.Path]::ChangeExtension($worldCache, ".twld")) -Force }
        Log "world cache saved: $worldCache"
    }
    Log "artifacts: $WorkRoot"
}
