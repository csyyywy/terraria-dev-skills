<#
  tml.ps1 —— tModLoader 无头测试驱动（tmlkit）

  一条命令跑完：隔离 lab -> 起服/客 -> 等心跳 -> 投命令 -> 收 [TEST] -> 收截图 -> 收工。
  设计要点（都是实测/IL 证据换来的，别随手改）：
   1) 空专用服务器不 tick（IL: DedServ_PostModLoad 里 if (Netplay.HasClients) Game.Update）。
      模组侧用假 ISocket 把 HasClients 顶成 true —— 零窗口、零 GPU、零第二进程。
   2) 端口避开 Windows 保留段 7491-7990（netsh interface ipv4 show excludedportrange）。
   3) 按 PID 收尸，绝不按进程名匹配。
   4) 每个 lab 有自己的 -tmlsavedirectory / -modpath，绝不动玩家自己的存档与模组。

  安装目录解析顺序：-TmlDir > 环境变量 TML_DIR > <KIT>\_inst\steamapps\common\tModLoader（隔离副本）。
  副本由 -SourceInstall 指定源目录一次性复制；副本必须位于 ...\steamapps\common\tModLoader 之下。

  用法：
    pwsh -File tml.ps1 -Lab smoke -ModDir ..\MyMod -Commands 'ping;count npc' -Expect world_loaded
    pwsh -File tml.ps1 -Lab l2 -ModDir ..\MyMod -Client -Player <角色名> -Commands 'c:shot a'
#>
[CmdletBinding()]
param(
	[string]$TmlDir    = '',        # 空 = 按下方顺序解析
	[switch]$UseSteamInstall,       # 用源安装目录而不是隔离副本
	[string]$SourceInstall = '',    # 隔离副本的源目录（首次复制用）
	[string]$DotNet    = 'dotnet',
	[string]$Lab       = 'smoke',
	[string]$ModDir    = '',
	[string]$Tmod      = '',
	[string]$ModName   = '',
	[int]$Port         = 8000,
	[int]$TimeoutSec   = 240,
	[string[]]$Commands = @(),
	[string[]]$Expect   = @(),
	[switch]$Client,
	[string]$Player    = 'TestPlayer',   # 客户端角色名，须已存在于存档目录
	[string]$World     = '',
	[switch]$Fresh,
	[switch]$KeepMods,
	[switch]$God,          # 测试角色：完全免疫（伤害不进来）
	[switch]$NoKb,         # 测试角色：免疫击退
	[int]$LockHp     = 0,  # 测试角色：锁血到指定值（>0 生效）
	[switch]$KeepAlive,   # 测试角色：受伤流程照跑，血量还原（测受伤特效又不死）
	[switch]$PlanOnly,
	[switch]$LegacyBridge,   # 旧桥兼容：把服务端命令再写一份 in/commands.txt（示例 SelfTestSystem 那类桥读它）
	[switch]$MinimizeClient, # 客户端起来后最小化窗口（无人值守/不想抢焦点时用；key 注入不依赖焦点）
	[string]$BuildTxt = '',            # 依赖清单来源；空则依次试 -ModDir/-ProjectPath/同目录
	[string[]]$ExtraMods = @(),       # 额外依赖：.tmod 路径或目录（可多次传）
	[string]$WorkshopContent = '',    # 工坊内容目录；空 = 自动推导 <steamapps>\workshop\content\1281930
	[bool]$IsolatedWorkshop = $true,  # 把 -steamworkshopfolder 指到 lab 里的空目录：跳过创意工坊扫描（慢且与玩家环境耦合）
	[bool]$Mute = $true,        # 默认静音：音频设备用 dummy，音量归零（不打扰其他程序）
	[switch]$UseClientSaveDir,  # 客户端用独立存档目录（默认共用；共用是实测能起来的配置）
	[switch]$AllowStaleTmod,   # 允许跑 age>30min 的 .tmod（默认直接失败，防止拿旧包下结论）
	[int]$MaxWaitSec = 30,      # 全局等待预算：脚本内任何等待都不会超过它（超了就返回 starting）
	[int]$WorldGenSec = 300,   # 世界生成预算：首次进新 lab 会现生成世界，几十秒到几分钟都正常
	[switch]$Reuse,            # 复用同 lab 已在运行的会话（默认会先停掉它）
	[switch]$Detach,
	[switch]$StopSession,       # 只停掉该 lab 已常驻的会话
	[bool]$LegacyEnv = $true   # 同时导出 MOD_TESTDIR 与 <ModName>_TESTDIR（旧桥迁移用；稳定后可 -LegacyEnv:$false）
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

# pwsh -File 把 "a,b,c" 当**一个**字符串传进来，不按逗号拆，这里自己拆。
$Expect = @($Expect | ForEach-Object { $_ -split ',' } | Where-Object { $_ -and $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })
$sw = [Diagnostics.Stopwatch]::StartNew()
function Log($m) { Write-Host ('[{0,5}s] {1}' -f [int]$sw.Elapsed.TotalSeconds, $m) }

# 会话落盘（tml.ps1 里曾有三处调用 Save-Session 但**从没定义过**，
# 一旦走到"服务器没心跳 / 超时"分支就抛 CommandNotFound，把整个启动流程打断。
# 这里补上唯一定义，三处调用都走它。）
function Save-Session {
    try {
        $sess = [PSCustomObject]@{
            lab = $script:Lab; labRoot = $script:LabRoot; port = $script:Port;
            serverPid = if ($script:serverProc) { $script:serverProc.Id } else { 0 };
            clientPid = if ($script:clientProc) { $script:clientProc.Id } else { 0 };
            startedAt = (Get-Date).ToString('o'); client = [bool]$script:Client
        }
        $sess | ConvertTo-Json | Set-Content (Join-Path $script:LabRoot '.session.json') -Encoding utf8
        Log ('session saved -> ' + (Join-Path $script:LabRoot '.session.json'))
    } catch { Log ('session save failed: ' + $_.Exception.Message) }
}

function Test-PortFree([int]$p) {
	# 用 netstat 判定：tML 绑 0.0.0.0 且 Windows 允许地址复用，纯 bind 测试会误判为空闲
	$hit = (& netstat -ano -p TCP | Select-String -SimpleMatch (":" + $p)) 2>$null
	if ($hit) { return $false }
	try {
		$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $p)
		$l.Start(); $l.Stop(); return $true
	} catch { return $false }
}

function Select-FreePort([int]$want) {
	for ($i = 0; $i -lt 60; $i++) {
		$candidate = $want + $i
		if ($candidate -ge 7491 -and $candidate -le 7990) { continue }
		if (Test-PortFree $candidate) {
			if ($i -gt 0) { Log ("port {0} 被占用，改用 {1}" -f $want, $candidate) }
			return $candidate
		}
	}
	throw "从 $want 起找不到空闲端口（试了 60 个）"
}


# 工作目录默认放在用户目录，避免把 labs/_build 写进技能仓库
$KitRoot = if ($env:TMLKIT_HOME) { $env:TMLKIT_HOME } else { Join-Path $env:USERPROFILE '.tmlkit' }
New-Item -ItemType Directory -Force -Path $KitRoot | Out-Null
$BuildRoot = Join-Path $KitRoot '_build'
if (-not $SourceInstall -and $env:TML_STEAM_DIR) { $SourceInstall = $env:TML_STEAM_DIR }
$SteamTml = $SourceInstall
# 副本必须放在 ...\steamapps\common\tModLoader 这种路径下：tML 用"CWD 是否在 /steamapps/"判定 Steam，
# 放到别的路径会走另一条检测分支，客户端会卡在 mod 发现阶段（实测两次）。
$CopyTml  = Join-Path $KitRoot '_inst\steamapps\common\tModLoader'

if (-not $TmlDir -and $env:TML_DIR) { $TmlDir = $env:TML_DIR }
if (-not $TmlDir) {
	if ($UseSteamInstall) {
		if (-not $SteamTml) { throw '用 -UseSteamInstall 时需给 -SourceInstall 或环境变量 TML_STEAM_DIR' }
		$TmlDir = $SteamTml
	}
	else {
		if (-not (Test-Path (Join-Path $CopyTml 'tModLoader.dll'))) {
			if (-not $SteamTml) {
				throw "没有隔离副本，也没有源安装目录。给 -SourceInstall <TML_DIR> 或环境变量 TML_STEAM_DIR，或直接 -TmlDir <TML_DIR>。"
			}
			Log "首次使用：把 tModLoader 复制到隔离目录（约 270MB，一次性）"
			New-Item -ItemType Directory -Force -Path $CopyTml | Out-Null
			Copy-Item (Join-Path $SteamTml '*') $CopyTml -Recurse -Force -ErrorAction SilentlyContinue
		}
		$TmlDir = $CopyTml
	}
}
if ($PlanOnly -and -not $TmlDir) { $TmlDir = '<TML_DIR>' }
if (-not $PlanOnly -and -not (Test-Path (Join-Path $TmlDir 'tModLoader.dll'))) { throw "找不到 tModLoader: $TmlDir（-PlanOnly 不需要真实安装）" }
$LabRoot = Join-Path (Join-Path $KitRoot 'labs') $Lab

# 沙盒必须自带完整 config.json：缺字段时 tML 走"首次运行"流程，停在 Select Language 界面，
# 模组枚举永远不开始（实测：缺配置 40s+ 不动，补上后 10s 进入 Finding Mods）。
$cfgTemplate = Join-Path (Join-Path $PSScriptRoot '..\config') 'client-config.json'
$InDir   = Join-Path $LabRoot 'in'
$OutDir  = Join-Path $LabRoot 'out'
$ModsDir = Join-Path $LabRoot 'mods'
$SaveDir = Join-Path $LabRoot 'saves'
if (Test-Path $cfgTemplate) {
	New-Item -ItemType Directory -Force -Path $SaveDir | Out-Null
	$cfgTarget = Join-Path $SaveDir 'config.json'
	$wantRes = if ($Resolution) { $Resolution } else { $null }
	$needPatch = (-not (Test-Path $cfgTarget)) -or $wantRes
	if ($needPatch) {
		# 每次都从模板重建：保证分辨率等模板改动对已有 lab 也生效
		Copy-Item $cfgTemplate $cfgTarget -Force
		if ($wantRes) {
			if ($wantRes -notmatch '^(\d{3,5})x(\d{3,5})$') { throw "-Resolution 格式应为 WxH，例如 1920x1080（收到：$wantRes）" }
			$rw = $Matches[1]; $rh = $Matches[2]
			$cfg = Get-Content $cfgTarget -Raw
			$cfg = $cfg -replace '"DisplayWidth":\s*\d+', ('"DisplayWidth": ' + $rw)
			$cfg = $cfg -replace '"DisplayHeight":\s*\d+', ('"DisplayHeight": ' + $rh)
			Set-Content $cfgTarget $cfg -Encoding utf8
			Log ("client resolution -> $rw x $rh")
		}
	}
}
$WorldsDir = Join-Path $SaveDir 'Worlds'

if ($Fresh -and (Test-Path $LabRoot)) {
	Get-ChildItem $LabRoot -Recurse -File -ErrorAction SilentlyContinue |
		Where-Object { $_.Extension -ne '.wld' -and $_.Extension -ne '.twld' } |
		Remove-Item -Force -ErrorAction SilentlyContinue
}
foreach ($d in @($InDir, $OutDir, $ModsDir, $WorldsDir, (Join-Path $SaveDir 'Players'))) {
	New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $InDir  -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# ── 1. 拿到 .tmod ───────────────────────────────────────────
if (-not $Tmod) {
	if (-not $ModDir) { throw '需要 -ModDir <模组源码目录> 或 -Tmod <.tmod 路径>' }
	$ModDir = (Resolve-Path $ModDir).Path
	Log "build $ModDir"
	# ★ 把打包目录指到 kit 自己的 _build 里：不往玩家的 Mods 目录写东西，
	#   玩家正开着游戏时也不会因为 .tmod 被占用而构建失败（TML003）。
	if (-not (Test-Path $BuildRoot)) { New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null }
	& $DotNet build $ModDir -v q --nologo ("-p:ExtraBuildModFlags=-tmlsavedirectory `"$BuildRoot`"") | Out-Null
	if ($LASTEXITCODE -ne 0) { throw 'dotnet build 失败（看上面的 TML 错误）' }
	# tML 的 BuildMod 目标把 .tmod 打进 tModLoader 的 Mods 目录（名字 = 源码目录名），
	# 不是 bin/ 下。两处都找一遍。
	$projName = Split-Path -Leaf $ModDir
	foreach ($cand in @(
		(Join-Path (Join-Path $BuildRoot 'Mods') ($projName + '.tmod')),
		(Join-Path $ModDir 'bin\Debug\net8.0\' + $projName + '.tmod')
	)) {
		if (Test-Path $cand) { $Tmod = $cand; break }
	}
	if (-not $Tmod) { throw "找不到 $ModDir 编出来的 .tmod（$BuildRoot\Mods 里没有）" }
}
if (-not $PlanOnly -and -not (Test-Path $Tmod)) { throw "找不到 $Tmod" }
if (-not $ModName) { $ModName = [IO.Path]::GetFileNameWithoutExtension($Tmod) }

# ★ 同 lab 已有会话时必须先停：否则旧服务端继续持有旧 .tmod（复制会失败/不生效），
#   而 -Detach 又秒返回，表现就是“重建了包但截图还是老样子”。
$sessFile = Join-Path $LabRoot '.session.json'
if ((Test-Path $sessFile) -and -not $Reuse) {
	try {
		$old = Get-Content $sessFile -Raw | ConvertFrom-Json
		Log ('found running session (server=' + $old.serverPid + ' client=' + $old.clientPid + ') -> stopping it')
		foreach ($procId in @($old.serverPid, $old.clientPid)) {
			if ($procId -and $procId -ne 0) { & taskkill /F /T /PID $procId 2>$null | Out-Null }
		}
		Start-Sleep -Milliseconds 800
		# 等 .tmod 句柄真的释放（最多 5s）
		$tmodFiles = @(Get-ChildItem $ModsDir -Filter '*.tmod' -ErrorAction SilentlyContinue)
		for ($k = 0; $k -lt 10; $k++) {
			$locked = $false
			foreach ($f in $tmodFiles) {
				try { $fs = [IO.File]::Open($f.FullName, 'Open', 'ReadWrite', 'None'); $fs.Close() } catch { $locked = $true }
			}
			if (-not $locked) { break }
			Start-Sleep -Milliseconds 500
		}
		Remove-Item $sessFile -Force -ErrorAction SilentlyContinue
		Get-ChildItem $InDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
		Log 'previous session stopped; .tmod handles released'
	} catch { Log ('stop old session failed: ' + $_.Exception.Message) }
}

if ($PlanOnly) {
	Log '--- PLAN ONLY（不创建目录、不复制文件、不启动进程）---'
	Log "lab        : $LabRoot"
	Log "install    : $TmlDir"
	Log "mod        : $ModName  <-  $Tmod"
	Log "lab mods   : $ModsDir"
	Log "lab saves  : $SaveDir"
	Log "port       : $Port"
	Log "env        : TMLKIT_ROOT=$LabRoot"
	Log "commands   : $($Commands -join ' | ')"
	Log "expect     : $($Expect -join ',')"
	Log "processes  : server=1 client=$(if ($Client) { 1 } else { 0 })"
	Log ("server cmd : " + $DotNet + ' "' + $TmlDir + '\tModLoader.dll" -server -config "' + (Join-Path $LabRoot 'serverconfig.txt') + '" -tmlsavedirectory "' + $SaveDir + '" -modpath "' + $ModsDir + '"')
	exit 0
}

if (-not $KeepMods) { Get-ChildItem $ModsDir -Filter '*.tmod' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
Copy-Item $Tmod (Join-Path $ModsDir "$ModName.tmod") -Force
$tmodInfo = Get-Item $Tmod
$sha = (Get-FileHash $Tmod -Algorithm SHA256).Hash.Substring(0, 12).ToLower()
$ageMin = [Math]::Round(((Get-Date) - $tmodInfo.LastWriteTime).TotalMinutes, 1)
Log ("mod: {0} <- {1}" -f $ModName, $Tmod)
Log ("tmod: mtime={0:yyyy-MM-dd HH:mm:ss} size={1} sha12={2} age={3}min" -f $tmodInfo.LastWriteTime, $tmodInfo.Length, $sha, $ageMin)
if ($ageMin -gt 30) {
	$msg = ("这个 .tmod 已经 {0} 分钟没更新（mtime={1:HH:mm:ss}）：多半是打包没成功（句柄被占用时 tML 打印 Packaging 却不落盘），跑下去等于拿旧包下结论" -f $ageMin, $tmodInfo.LastWriteTime)
	if ($AllowStaleTmod) { Log ("WARN " + $msg + "（-AllowStaleTmod 已放行）") }
	else { throw ($msg + "。确认打包成功后重跑；确有需要加 -AllowStaleTmod") }
}

# ── 1b. 依赖（modReferences）：不补就会 ModSortingException: Missing mod ──
$refs = @()
$buildTxt = if ($BuildTxt) { $BuildTxt }
	elseif ($ModDir -and (Test-Path (Join-Path $ModDir 'build.txt'))) { Join-Path $ModDir 'build.txt' }
	elseif ($ProjectPath -and (Test-Path (Join-Path (Split-Path -Parent $ProjectPath) 'build.txt'))) { Join-Path (Split-Path -Parent $ProjectPath) 'build.txt' }
	else {
		# 只给了 .tmod 时：同目录找 build.txt，其次从 .tmod 里读（tML 会把 build.txt 打进包）
		$sibling = Join-Path (Split-Path -Parent $Tmod) 'build.txt'
		if (Test-Path $sibling) { $sibling } else { '' }
	}
if ($buildTxt -and (Test-Path $buildTxt)) {
	$line = (Get-Content $buildTxt -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*modReferences\s*=' } | Select-Object -First 1)
	if ($line) { $refs = @(($line -split '=', 2)[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}
if (-not $WorkshopContent) {
	$cand = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $TmlDir)))) 'workshop\content\1281930'
	if (Test-Path $cand) { $WorkshopContent = $cand }
}
$sources = @()
foreach ($m in $ExtraMods) { if ($m) { $sources += $m } }
$playerMods = Join-Path $env:USERPROFILE 'Documents\My Games\Terraria\tModLoader\Mods'
if (Test-Path $playerMods) { $sources += $playerMods }
if ($WorkshopContent -and (Test-Path $WorkshopContent)) { $sources += $WorkshopContent }

$missing = @()
foreach ($dep in $refs) {
	if ($dep -eq $ModName) { continue }
	if (Test-Path (Join-Path $ModsDir ($dep + '.tmod'))) { continue }
	$found = $null
	foreach ($src in $sources) {
		if (Test-Path $src -PathType Leaf) { continue }
		$hit = Get-ChildItem $src -Filter ($dep + '.tmod') -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($hit) { $found = $hit.FullName; break }
	}
	if ($found) { Copy-Item $found (Join-Path $ModsDir ($dep + '.tmod')) -Force; Log ("dep: {0} <- {1}" -f $dep, $found) }
	else { $missing += $dep }
}
if ($missing.Count -gt 0) {
	throw ('缺少依赖模组：' + ($missing -join ', ') + '。已查：-ExtraMods / 玩家 Mods / 工坊(' + $WorkshopContent + ')。' +
		' 处理：加 -ExtraMods <路径>，或把依赖装进玩家 Mods，或确认工坊里确实有。')
}

$enabledMods = @($ModName) + @($refs | Where-Object { $_ -and $_ -ne $ModName })
Set-Content (Join-Path $ModsDir 'enabled.json') (ConvertTo-Json -InputObject $enabledMods -Compress) -Encoding utf8
Log ('enable: ' + ($enabledMods -join ','))

# ── 2. 世界 ─────────────────────────────────────────────────
$autoCreate = $false
if ($World) {
	if (-not (Test-Path $World)) { throw "世界不存在: $World" }
	Copy-Item $World (Join-Path $WorldsDir 'lab.wld') -Force
	$twld = [IO.Path]::ChangeExtension($World, '.twld')
	if (Test-Path $twld) { Copy-Item $twld (Join-Path $WorldsDir 'lab.twld') -Force }
}
elseif (Test-Path (Join-Path $WorldsDir 'lab.wld')) {
	Log 'reuse lab world'
}
else {
	# 不借玩家现成世界：别人的存档往往带模组依赖，lab 里只装一个模组会直接加载失败。
	# 自己生成一个小的，第一次慢（~40s），之后缓存在 lab 里反复用。
	$autoCreate = $true
	Log 'fresh lab -> autocreate small world'
}

$cfg = @(
	# 端口必须在这里定下来：serverconfig.txt 是服务端唯一读取端口的地方
	$Port = Select-FreePort $Port
	"world=$(Join-Path $WorldsDir 'lab.wld')",
	'worldname=lab',
	'maxplayers=4',
	"port=$Port",
	'upnp=0',
	'difficulty=0'
)
if ($autoCreate) { $cfg += 'autocreate=1' }
$cfg | Set-Content (Join-Path $LabRoot 'serverconfig.txt') -Encoding utf8

if ($Client) {
	# tML 客户端硬要求 Steam 在跑（否则弹 Fatal Error 并卡住对话框）
	if (@(Get-Process steam, steamwebhelper -ErrorAction SilentlyContinue).Count -eq 0) {
		throw 'Steam 没有运行：tML 客户端启动时会弹 Fatal Error 卡住。请先启动 Steam 并登录；只跑服务端（L1）可以不启动。'
	}
	# 同一份安装里再起一个客户端是有代价的：日志目录、Steam 检测、窗口焦点都会打架。
	# 研究笔记里这条还是"未验证风险"，这里至少先把它说出来。
	$foreign = Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" -ErrorAction SilentlyContinue |
		Where-Object { $_.CommandLine -match 'tModLoader\.dll' -and -not $_.CommandLine.Contains($LabRoot) -and $_.CommandLine -notmatch 'terrariasteamclient' }
	if ($foreign) {
		Log "WARN 检测到另一个 tModLoader 实例（可能是你自己在玩）: pid=$($foreign.ProcessId -join ',')"
		Log 'WARN 客户端模式可能与它抢 Steam/焦点/日志；要稳定截图测试，请先关掉游戏'
	}
	# ★ -modpath 只在 LoadServerParameters 里被读，客户端不认。
	#   客户端永远从 <存档目录>\Mods 加载，所以这里镜像一份过去。

	# （模组镜像放到下面独立存档目录建好之后再做）
	$srcPlayers = Join-Path $env:USERPROFILE 'Documents\My Games\Terraria\tModLoader\Players'
	$plr = Join-Path $srcPlayers "$Player.plr"
	if (-not (Test-Path $plr)) {
		$cand = Get-ChildItem $srcPlayers -Filter '*.plr' -ErrorAction SilentlyContinue | Select-Object -First 1
		if (-not $cand) { throw '没有可用的角色文件，先在游戏里建一个角色再跑 -Client' }
		$Player = $cand.BaseName
	}
	foreach ($ext in @('.plr', '.tplr')) {
		$f = Join-Path $srcPlayers ($Player + $ext)
		if (Test-Path $f) { Copy-Item $f (Join-Path $SaveDir ('Players\' + $Player + $ext)) -Force }
	}
	Log "client character: $Player"
	# 客户端必须用**独立**的 saves：与服务器共用同一个目录时，服务器占着 Mods 里的 .tmod，
	# 客户端会读不到模组（现象：client.log 停在 MonoMod hook，桥永不 arm）
	$script:CliSaveDir = Join-Path $LabRoot 'saves-client'
	New-Item -ItemType Directory -Force -Path $CliSaveDir | Out-Null
	foreach ($sub2 in 'Worlds','Players','Mods') {
		$src = Join-Path $SaveDir $sub2
		if (Test-Path $src) { Copy-Item $src (Join-Path $CliSaveDir $sub2) -Recurse -Force -ErrorAction SilentlyContinue }
	}
	# 角色文件必须先就位：-skipselect 找不到角色就会停在菜单，永远不会 inworld
	$script:cliModsDir = Join-Path $CliSaveDir 'Mods'
	# 两个可能被客户端使用的存档目录都放一份：共用 saves 时缺 .tmod 会变成"从服务器下载模组"然后掉线
	foreach ($dir in @((Join-Path $SaveDir 'Mods'), $cliModsDir)) {
		New-Item -ItemType Directory -Force -Path $dir | Out-Null
		Copy-Item (Join-Path $ModsDir '*.tmod') $dir -Force -ErrorAction SilentlyContinue
		Copy-Item (Join-Path $ModsDir 'enabled.json') $dir -Force -ErrorAction SilentlyContinue
	}
}

# ── 3. 起进程 ───────────────────────────────────────────────


function Start-Game([string]$CmdArgs, [string]$Tag, [string]$BootLog = '') {
	# ★ 绝不给子进程接 stdout/stderr 管道：tML 日志量极大，管道写满就会卡在
	#   log4net -> ConsolePal.WindowsConsoleStream.Write 上，整个主线程停住
	#   （现象就是"卡在 Finding Mods"，实测抓到过栈）。不重定向，让它写自己的日志文件。
	$env:TMLKIT_ROOT = $LabRoot
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $DotNet
	$psi.Arguments = $CmdArgs
	$psi.WorkingDirectory = $TmlDir
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$psi.RedirectStandardOutput = $false
	$psi.RedirectStandardError = $false
	$psi.EnvironmentVariables['TMLKIT_ROOT'] = $LabRoot
	if ($Mute) {
		# 双重保险：SDL 用 dummy 声卡（根本不打开设备），桥再把音量归零
		$psi.EnvironmentVariables['SDL_AUDIODRIVER'] = 'dummy'
		$psi.EnvironmentVariables['TMLKIT_MUTE'] = '1'
	}
	if ($LegacyEnv) {
		# 旧桥迁移：新桥统一读 TMLKIT_ROOT；这两个名字保留一版，已有模组不用改代码
		$psi.EnvironmentVariables['MOD_TESTDIR'] = $LabRoot
		if ($ModName) { $psi.EnvironmentVariables[$ModName + '_TESTDIR'] = $LabRoot }
	}
	if ($Detach) {
		# 常驻子进程必须脱离本进程的 stdout：否则它会一直持有管道，调用方永远等不到 EOF
		$env:TMLKIT_ROOT = $LabRoot
		if ($Mute) { $env:SDL_AUDIODRIVER = 'dummy'; $env:TMLKIT_MUTE = '1' }
		if ($LegacyEnv) { $env:MOD_TESTDIR = $LabRoot; if ($ModName) { Set-Item -Path ("env:" + $ModName + "_TESTDIR") -Value $LabRoot } }
		$dp = Start-Process -FilePath $DotNet -ArgumentList $CmdArgs -WorkingDirectory $TmlDir -PassThru -WindowStyle Hidden
		Log "$Tag pid=$($dp.Id) (detached)"
		return $dp
	}
	if ($BootLog) {
		# ★ 用 cmd 的 >> 做 OS 级文件重定向：不经过任何管道，
		#   模组没加载/进程卡死时也能从第一行输出开始看（boot-log.ps1 读它）。
		$line = '""{0}" {1} >> "{2}" 2>&1"' -f $DotNet, $CmdArgs, $BootLog
		$bp = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $line) -WorkingDirectory $TmlDir -PassThru -WindowStyle Hidden
		Log "$Tag pid=$($bp.Id) boot-log=$BootLog"
		return $bp
	}
	# ★ 没有 boot 日志时也必须脱离调用方 stdout：否则子进程活得比调用方久，调用方永远等不到 EOF
	$p = Start-Process -FilePath $DotNet -ArgumentList $CmdArgs -WorkingDirectory $TmlDir -PassThru -WindowStyle Hidden
	Log "$Tag pid=$($p.Id)"
	return $p
}

function Wait-Port([int]$Port, $Proc, [int]$Seconds) {
	# 心跳只能证明模组起来了，不能证明端口在听；世界还在生成时客户端连过来会白跑一趟。
	$deadline = (Get-Date).AddSeconds($Seconds)
	while ((Get-Date) -lt $deadline) {
		if ($Proc.HasExited) {
			# 端口被占时 tML 只会静默退出，这里翻译一下，避免误判成模组问题
			$srvLog = Join-Path (Join-Path $TmlDir "tModLoader-Logs") "server.log"
			if ((Test-Path $srvLog) -and (Select-String -Path $srvLog -Pattern "只允许使用一次|Address already in use" -Quiet -ErrorAction SilentlyContinue)) {
				throw "端口 $Port 被占用（tML bind 失败后退出）：换一个 -Port 或先停掉旧会话"
			}
			throw "服务器提前退出 code=$($Proc.ExitCode)"
		}
		try {
			$c = New-Object System.Net.Sockets.TcpClient
			$iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
			if ($iar.AsyncWaitHandle.WaitOne(500) -and $c.Connected) { $c.Close(); return $true }
			$c.Close()
		} catch { }
		Start-Sleep -Milliseconds 500
	}
	return $false
}

function Get-BeatSummary([string]$side) {
	$f = Join-Path $OutDir ("heartbeat-$side.txt")
	if (-not (Test-Path $f)) { return 'no-heartbeat' }
	$kv = @{}
	foreach ($line in Get-Content $f -ErrorAction SilentlyContinue) {
		if ($line -match '^(\w+)=(.*)$') { $kv[$Matches[1]] = $Matches[2] }
	}
	return ('tick={0} net={1} world={2} fps={3}' -f $kv['tick'], $kv['net'], $kv['world'], $kv['fps'])
}

function Show-Progress([string]$phase) {
	Log ("[$phase] server[{0}] client[{1}]" -f (Get-BeatSummary 'server'), (Get-BeatSummary 'client'))
}

function Dump-OnFailure([string]$why) {
	Log "--- 失败诊断（$why）---"
	Show-Progress 'at-failure'
	foreach ($side in @('server','client')) {
		$lg = Join-Path $OutDir ("log-$side.txt")
		if (Test-Path $lg) { Log "--- log-$side.txt 尾部 20 行 ---"; Get-Content $lg -Tail 20 | ForEach-Object { Log "  $side| $_" } }
	}
	# 客户端起不来时最有用的证据在 tML 自己的日志里：看它有没有走到 Finding Mods
	# 模组没加载时，唯一能看到的就是进程自己的输出（OS 级重定向落盘）
	foreach ($b in @('boot-server.log','boot-client.log')) {
		$bp = Join-Path $OutDir $b
		if (Test-Path $bp) {
			Log ('--- ' + $b + ' 尾部 15 行 ---')
			Get-Content $bp -Tail 15 | ForEach-Object { Log ('  boot| ' + $_) }
		}
	}

$tlog = Join-Path (Join-Path $TmlDir 'tModLoader-Logs') 'client.log'
	if (Test-Path $tlog) {
		Log '--- tML client.log 尾部 15 行 ---'
		Get-Content $tlog -Tail 15 | ForEach-Object { Log "  tml| $_" }
		if (-not (Select-String -Path $tlog -Pattern 'Finding Mods' -Quiet -ErrorAction SilentlyContinue)) {
			Log '=> 客户端始终没有执行到 Finding Mods：卡在模组枚举之前，通常是 Steam/音频/图形初始化被别的实例占住。'
			Log '   处理：退出 Steam 与所有 tModLoader 实例后重试；或改用 -TmlDir 指向隔离副本。'
		}
	}

	foreach ($side in @('server','client')) {
		$rf = Join-Path $OutDir ("result-$side.txt")
		if (Test-Path $rf) { Log "--- result-$side.txt ---"; Get-Content $rf | ForEach-Object { Log "  $side| $_" } }
	}
}

function Wait-Beat([string]$Path, $Proc, [int]$Tries, [string]$What) {
	for ($i = 0; $i -lt $Tries; $i++) {
		Start-Sleep -Milliseconds 500
		if ($Proc.HasExited) { throw "$What 提前退出 code=$($Proc.ExitCode)" }
		if ($i % 10 -eq 9) { Show-Progress $What }
		if (Test-Path $Path) {
			$txt = Get-Content $Path -Raw -ErrorAction SilentlyContinue
			if ($txt -match 'ms=(\d+)') {
				$age = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$Matches[1]
				if ($age -lt 3000) { return $true }
			}
		}
	}
	return $false
}

# 起之前先清掉"上一次被打断留下的本 lab 进程"：只认命令行里带这个 lab 绝对路径的，
# 绝不按进程名匹配（研究里那条血教训：按名字匹配会杀掉玩家自己的游戏）。
$stale = Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" -ErrorAction SilentlyContinue |
	Where-Object { $_.CommandLine -and $_.CommandLine.Contains($LabRoot) -and $_.CommandLine -match 'tModLoader.dll' }
foreach ($s in $stale) { Log "reap stale lab pid=$($s.ProcessId)"; try { Stop-Process -Id $s.ProcessId -Force -ErrorAction Stop } catch { } }

$serverProc = $null; $clientProc = $null
Log "mode: Client=$Client Port=$Port"

# ★ 命令文件必须在启动之前写好：桥的 OnWorldLoad 只跑一次，世界载入后再写就来不及了。
	$lines = @()
	# 就绪信号统一由 s:ping 产出（桥会写 [TEST] ping PASS），避免 Expect 里点 ping 却没人发
	if ($Client) {
		# L2 有真客户端：先撤掉 L1 的假连接，否则服务器会把真连接判为失效并踢掉（实测 0.3s Connection lost）
		$lines += 's:link off'
	}
	if ($Client) {
		# 客户端先进世界再执行后面的命令：菜单里 LocalPlayer 还没 active，改血/受伤都会白做
		$lines += 'c:waitfor inworld'
		# 测试角色预设：省得每次手打一串
		if ($God)       { $lines += 'c:god on' }
		if ($NoKb)      { $lines += 'c:kb on' }
		if ($LockHp -gt 0) { $lines += ('c:lockhp ' + $LockHp) }
		if ($KeepAlive) { $lines += 'c:keepalive on' }
		if ($lines.Count -gt 0) { Log ('test-player preset: ' + ($lines -join ' | ')) }
	$lines = @('s:ping') + $lines
	}
	foreach ($c in $Commands) {
		if (-not $c) { continue }
		foreach ($part in ($c -split ';')) {
			if ($part -and $part.Trim().Length -gt 0) { $lines += $part.Trim() }
		}
	}
	if ($lines.Count -gt 0) {
		# 服务端和客户端各收一份：无前缀 = 两边都跑，s: 只给服务端，c: 只给客户端
		$srvLines = @(); $cliLines = @()
		foreach ($l in $lines) {
			if ($l.StartsWith('c:')) { $cliLines += $l }
			elseif ($l.StartsWith('s:')) { $srvLines += $l }
			else { $srvLines += $l; $cliLines += $l }
		}
		if ($srvLines.Count -gt 0) {
			Set-Content (Join-Path $InDir 'cmd-server.txt') ($srvLines -join "`r`n") -Encoding utf8
			# 旧桥兼容（-LegacyBridge）：同一批服务端命令再写一份 commands.txt
			if ($LegacyBridge) { Set-Content (Join-Path $InDir 'commands.txt') ($srvLines -join "`r`n") -Encoding utf8 }
		}
		if ($Client -and $cliLines.Count -gt 0) { Set-Content (Join-Path $InDir 'cmd-client.txt') ($cliLines -join "`r`n") -Encoding utf8 }
		Log ('cmds: ' + ($lines -join ' | '))
	}


try {
	$wsArg = ''
	if ($IsolatedWorkshop) {
		$wsDir = Join-Path $LabRoot 'workshop'
		New-Item -ItemType Directory -Force -Path $wsDir | Out-Null
		$wsArg = (' -steamworkshopfolder "{0}"' -f $wsDir)
		Log "workshop isolated -> $wsDir"
	}
	$Port = Select-FreePort $Port
	$srvArgs = ('"{0}\tModLoader.dll" -server -config "{1}" -tmlsavedirectory "{2}" -modpath "{3}"{4}' -f $TmlDir, (Join-Path $LabRoot 'serverconfig.txt'), $SaveDir, $ModsDir, $wsArg)
	$serverProc = Start-Game $srvArgs 'server' (Join-Path $OutDir 'boot-server.log')

	# 启动期快失败：不等心跳，直接盯进程自己的输出（模组没加载也有话说）
	$bootPath = Join-Path $OutDir 'boot-server.log'
	# 日志基线：server.log / boot-server.log 都是追加写，只看本次启动之后的增量，
	# 否则会把上一轮的错误当成本轮失败（实测把 4 秒失败误判成历史错误）。
	$tmlLogPath = Join-Path (Join-Path $TmlDir 'tModLoader-Logs') 'server.log'
	$tmlBase = if (Test-Path $tmlLogPath) { (Get-Item $tmlLogPath).Length } else { 0 }
	$bootBase = if (Test-Path $bootPath) { (Get-Item $bootPath).Length } else { 0 }

	function Read-NewText([string]$path, [int64]$base) {
		if (-not (Test-Path $path)) { return '' }
		try {
			$f = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
			try {
				if ($f.Length -le $base) { return '' }
				[void]$f.Seek($base, 'Begin')
				$sr = New-Object IO.StreamReader($f)
				$txt = $sr.ReadToEnd()
				$sr.Dispose()
				return $txt
			} finally { $f.Dispose() }
		} catch { return '' }
	}

	$bootPatterns = 'Missing mod|ModSortingException|Disabling Mod|Unable to access Steam Workshop|Select Language|Fatal Error|Please ensure Steam is logged in|只允许使用一次|Address already in use|Failed to load'
	$bootDeadline = (Get-Date).AddSeconds([Math]::Min(120, [Math]::Max(10, $MaxWaitSec)))
	$bootHit = $null
	while ((Get-Date) -lt $bootDeadline) {
		if ($serverProc.HasExited) { break }
		$beatFile = Join-Path $OutDir 'heartbeat-server.txt'
		if (Test-Path $beatFile) {
			$btxt = Get-Content $beatFile -Raw -ErrorAction SilentlyContinue
			if ($btxt -match 'ms=(\d+)' -and (([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$Matches[1]) -lt 3000)) { break }
		}
		$newBoot = Read-NewText $bootPath $bootBase
		if ($newBoot -and ($newBoot -match $bootPatterns)) {
			$line1 = ($newBoot -split "`n" | Where-Object { $_ -match $bootPatterns } | Select-Object -First 1)
			$bootHit = $line1.Trim(); break
		}
		# ★ 模组加载失败（命名空间/依赖/编译错误）只写进 tML 自己的 server.log，
		#   不看这里就只能等到超时，且症状是无心跳。
		$newTml = Read-NewText $tmlLogPath $tmlBase
		$pat2 = 'An error occurred while loading|Namespace and Folder name do not match|Disabling Mod:|Missing mod:|Strong reference'
		if ($newTml -and ($newTml -match $pat2)) {
			$line2 = ($newTml -split "`n" | Where-Object { $_ -match $pat2 } | Select-Object -First 1)
			$bootHit = ('tML: ' + $line2.Trim()); break
		}
		Start-Sleep -Milliseconds 400
	}
	if ($bootHit) {
		Log ('启动期失败信号：' + $bootHit)
		if (Test-Path $bootPath) { Get-Content $bootPath -Tail 20 | ForEach-Object { Log ('  boot| ' + $_) } }
		throw ('server 启动失败：' + $bootHit)
	}

	$beatFileS = Join-Path $OutDir 'heartbeat-server.txt'
	$swReady = [Diagnostics.Stopwatch]::StartNew()
	$swGen = [Diagnostics.Stopwatch]::StartNew()
	$generating = $false
	$serverReady = $false
	while ($true) {
		if ($serverProc.HasExited) { break }
		if (Test-Path $beatFileS) {
			$bt = Get-Content $beatFileS -Raw -ErrorAction SilentlyContinue
			if ($bt -match 'ms=(\d+)' -and (([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$Matches[1]) -lt 3000)) { $serverReady = $true; break }
		}
		# 生成世界是合法耗时：看到进度行就继续等，直到 WorldGenSec
		if (Test-Path $bootPath) {
			$genHit = Select-String -Path $bootPath -Pattern 'Generating world|Settling liquids|Adding grass|Placing|Gemstones|Bushes' -ErrorAction SilentlyContinue | Select-Object -Last 1
			if ($genHit) {
				$generating = $true
				if ($swGen.Elapsed.TotalSeconds -gt $WorldGenSec) { break }
				if (($swGen.Elapsed.TotalSeconds % 10) -lt 0.5) { Log ('世界生成中… ' + [int]$swGen.Elapsed.TotalSeconds + 's：' + $genHit.Line.Trim()) }
				Start-Sleep -Milliseconds 500
				continue
			}
		}
		if ($swReady.Elapsed.TotalSeconds -gt ([Math]::Max(4, $MaxWaitSec * 2))) { break }
		Start-Sleep -Milliseconds 400
	}
	if (-not $serverReady) {
		if ($Detach) {
			Save-Session
			Log ('still starting after ' + $MaxWaitSec + 's（服务器还没心跳）：会话已保存，用 session.ps1 -Action Poll/Wait 再查')
			exit 0
		}
		# 最常见的真因：模组里根本没编进桥（csproj 没包含 resources/bridge/*.cs），
		# 表现就是永远没有心跳。这里直接把结论说出来，省一轮盲猜。
		try {
			Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
			$zip = [IO.Compression.ZipFile]::OpenRead($Tmod)
			$dll = $zip.Entries | Where-Object { $_.Name -like '*.dll' } | Select-Object -First 1
			if ($dll) {
				$ms = New-Object IO.MemoryStream
				$dll.Open().CopyTo($ms)
				$ascii = [Text.Encoding]::ASCII.GetString($ms.ToArray())
				if ($ascii -notmatch 'TmlKit') {
					Log 'HINT: 这个 .tmod 里没有 TmlKit 桥 → 模组永远不会写心跳。'
					Log 'HINT: 用 scripts/add-bridge.ps1 -Csproj <你的.csproj> 加上引用后重建，再跑一次。'
				}
			}
			$zip.Dispose()
		} catch { }

		if ($generating) { Log ('世界生成超过 ' + $WorldGenSec + 's 仍未完成：加大 -WorldGenSec，或先手动生成一次世界再跑') }
		throw '等不到服务器心跳'
	}
	Log 'server heartbeat alive'

	if (-not (Wait-Port $Port $serverProc ([Math]::Max(5, $MaxWaitSec)))) {
		if ($Detach) {
			Save-Session
			Log ('still starting after ' + $MaxWaitSec + 's（端口还没听）：会话已保存，用 session.ps1 -Action Poll/Wait 再查')
			exit 0
		}
		throw "端口 $Port 一直没在听（世界还没载入完？）"
	}
	Log 'server port listening'
	Start-Sleep -Milliseconds 800

	if ($Client) {
		# 客户端也必须用 lab 的存档目录和模组目录，否则会去读玩家自己的档案
		$cliArgs = ('"{0}\tModLoader.dll" -join 127.0.0.1 -port {1} -player "{2}" -skipselect -tmlsavedirectory "{3}" -modpath "{4}"{5}' -f $TmlDir, $Port, $Player, $(if ($UseClientSaveDir) { $CliSaveDir } else { $SaveDir }), $ModsDir, $wsArg)
		$clientProc = Start-Game $cliArgs 'client' (Join-Path $OutDir 'boot-client.log')
		# 客户端启动期快失败：模态框（Steam 工坊/语言/Fatal）会让它永远不加载世界
		$cboot = Join-Path $OutDir 'boot-client.log'
		$clogFile = Join-Path (Join-Path $TmlDir 'tModLoader-Logs') 'client.log'
		$cpat = 'Unable to access Steam Workshop|Select Language|Fatal Error|Please ensure Steam is logged in|Missing mod|ModSortingException|Disabling Mod'
		$cdl = (Get-Date).AddSeconds([Math]::Min(90, [Math]::Max(10, $MaxWaitSec)))
		$chit = $null
		while ((Get-Date) -lt $cdl) {
			if ($clientProc.HasExited) { break }
			$cbf = Join-Path $OutDir 'heartbeat-client.txt'
			if (Test-Path $cbf) {
				$ct = Get-Content $cbf -Raw -ErrorAction SilentlyContinue
				if ($ct -match 'ms=(\d+)' -and (([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$Matches[1]) -lt 3000)) { break }
			}
			foreach ($f in @($cboot, $clogFile)) {
				if ($f -and (Test-Path $f)) {
					$h = Select-String -Path $f -Pattern $cpat -ErrorAction SilentlyContinue | Select-Object -First 1
					if ($h) { $chit = ($h.Filename + ': ' + $h.Line.Trim()); break }
				}
			}
			if ($chit) { break }
			Start-Sleep -Milliseconds 400
		}
		if ($chit) {
			Log ('客户端启动期失败信号：' + $chit)
			# 先把屏幕拍下来再失败：模态框长什么样对排查很关键
			try {
				$winui = Join-Path $PSScriptRoot 'win-ui.ps1'
				$cap = Join-Path $OutDir 'client-failure.png'
				$null = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile','-File',$winui,'-Action','Shot','-NoFocus','-Out',$cap) -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
				if (Test-Path $cap) { Log ('失败截图：' + $cap) }
			} catch { }
			if (Test-Path $cboot) { Get-Content $cboot -Tail 15 | ForEach-Object { Log ('  boot| ' + $_) } }
			throw ('client 启动失败：' + $chit)
		}

		if (-not (Wait-Beat (Join-Path $OutDir 'heartbeat-client.txt') $clientProc ([Math]::Max(4, $MaxWaitSec * 2)) '客户端')) {
			if ($Detach) {
				Save-Session
				Log ('still starting after ' + $MaxWaitSec + 's（客户端还没心跳）：会话已保存，用 session.ps1 -Action Poll/Wait 再查')
				exit 0
			}
			throw '等不到客户端心跳'
		}
		Log 'client heartbeat alive'
		if ($MinimizeClient) {
			# 客户端建窗那一下会抢焦点，之后还可能自己复原；盯 4 秒反复压下去（SW_MINIMIZE 不激活窗口）
			Add-Type -Name W -Namespace TmlKit -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c); [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);' -ErrorAction SilentlyContinue
			$mw = [Diagnostics.Stopwatch]::StartNew()
			$pressed = 0
			while ($mw.Elapsed.TotalSeconds -lt 4) {
				$clientProc.Refresh()
				$h = $clientProc.MainWindowHandle
				if ($h -ne [IntPtr]::Zero -and -not [TmlKit.W]::IsIconic($h)) {
					[void][TmlKit.W]::ShowWindow($h, 6)   # 6 = SW_MINIMIZE，不抢焦点
					$pressed++
				}
				$sleepMs = if ($mw.Elapsed.TotalSeconds -lt 1.5) { 100 } else { 300 }
				Start-Sleep -Milliseconds $sleepMs
			}
			if ($pressed -gt 0) { Log ('client window minimized x' + $pressed + '（key 走进程内注入，不需要焦点）') }
		}
	}

	# 只跑服务端/客户端、不投命令时（-Detach 或纯启动验证）立刻返回，别等满超时
	$needWait = ($lines.Count -gt 0) -or ($Expect.Count -gt 0)
	# ★ 统一预算：这里绝不能用 -TimeoutSec 裸奔（默认 240 会把硬上限架空）
	$needWait = ($lines.Count -gt 0) -or ($Expect.Count -gt 0)
	$budget = if ($Expect.Count -gt 0) { [Math]::Min($TimeoutSec, [Math]::Max(5, $MaxWaitSec)) } else { 0 }
	$deadline = (Get-Date).AddSeconds($budget)
	do {
		if (-not $needWait -or $budget -le 0) { break }
		if (-not $needWait) { break }
		Start-Sleep -Milliseconds 500
		if ($serverProc.HasExited -and (-not $Client -or $clientProc.HasExited)) { break }
		if ($Expect.Count -gt 0) {
			$names = @()
			Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^results?(-[a-z]+)?\.txt$' } | ForEach-Object {
				$names += (Select-String -Path $_.FullName -Pattern '^\[TEST\] (\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
			}
			$missingNow = @($Expect | Where-Object { $_ -notin $names })
			if ($missingNow.Count -eq 0) { break }
		}
	} while ((Get-Date) -lt $deadline)

	# 命令里有 shot 的话，等图落地再收工 —— 否则截图请求刚排队就被收尸了。
	$shotWant = @($lines | Where-Object { $_ -match 'shot\s' }).Count
	if ($shotWant -gt 0) {
		$shotDeadline = (Get-Date).AddSeconds([Math]::Min(20, [Math]::Max(5, $MaxWaitSec)))
		while ((Get-Date) -lt $shotDeadline) {
			$have = @(Get-ChildItem $OutDir -Filter '*.png' -ErrorAction SilentlyContinue).Count
			if ($have -ge $shotWant) { break }
			Start-Sleep -Milliseconds 300
		}
		Log ("shots: {0}/{1}" -f @(Get-ChildItem $OutDir -Filter '*.png' -ErrorAction SilentlyContinue).Count, $shotWant)
	}
}
catch {
	Dump-OnFailure $_.Exception.Message
	throw
}
finally {
	if ($Detach) {
		# 常驻模式：什么都不杀，只把会话信息落盘
		Save-Session
	}
	else {
	try {
		if ($serverProc -and -not $serverProc.HasExited) { Set-Content (Join-Path $InDir 'cmd-server.txt') 'exit' -Encoding utf8 }
		Start-Sleep -Seconds 2
	} catch { }
	try {
		if ($Client -and $clientProc -and -not $clientProc.HasExited) { Set-Content (Join-Path $InDir 'cmd-client.txt') 'exit' -Encoding utf8 }
		Start-Sleep -Seconds 1
	} catch { }
	# 关键：exit 只是用来让当前进程优雅退出；退出后必须清掉，否则下一轮客户端在 Load 就读到它
	Start-Sleep -Milliseconds 500
	Get-ChildItem $InDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

	foreach ($p in @($serverProc, $clientProc)) {
		if ($p -and -not $p.HasExited) {
			Log "kill pid=$($p.Id)"
			try { $p.Kill() } catch { }
			$p.WaitForExit(5000) | Out-Null
		}
	}
	}
}

# ── 4. 汇总 ─────────────────────────────────────────────────
$results = @()
Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^results?(-[a-z]+)?\.txt$' } | ForEach-Object {
	$side = $_.BaseName -replace '^result-', ''
	Select-String -Path $_.FullName -Pattern '^\[TEST\] (\S+) (PASS|FAIL)\s*(.*)$' | ForEach-Object {
		$results += [PSCustomObject]@{
			Side = $side; Case = $_.Matches[0].Groups[1].Value
			Status = $_.Matches[0].Groups[2].Value; Detail = $_.Matches[0].Groups[3].Value
		}
	}
}
$pass = @($results | Where-Object { $_.Status -eq 'PASS' })
$fail = @($results | Where-Object { $_.Status -eq 'FAIL' })
$names = @($results | ForEach-Object { $_.Case })
$missing = @($Expect | Where-Object { $_ -notin $names })
$shots = @(Get-ChildItem $OutDir -Filter '*.png' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

$missText = '-'
if ($missing.Count -gt 0) { $missText = ($missing -join ',') }
Log ("RESULT: PASS={0} FAIL={1} MISSING={2} SHOTS={3}" -f $pass.Count, $fail.Count, $missText, $shots.Count)
foreach ($r in $results) { Log ("  [{0}] {1}/{2} :: {3}" -f $r.Status, $r.Side, $r.Case, $r.Detail) }
foreach ($s in $shots) { Log ("  shot: {0}" -f $s) }

$okAll = ($fail.Count -eq 0 -and $missing.Count -eq 0 -and $results.Count -gt 0)
[PSCustomObject]@{
	Ok = $okAll; Pass = $pass.Count; Fail = $fail.Count
	Missing = $missing; LabRoot = $LabRoot; Shots = $shots
	ElapsedSec = [int]$sw.Elapsed.TotalSeconds
} | Format-List | Out-Host

if (-not $okAll) { exit 1 } else { exit 0 }
