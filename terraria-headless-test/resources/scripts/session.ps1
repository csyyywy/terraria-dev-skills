
<#
.SYNOPSIS
  热会话控制：下发命令 / 跑 suite / 查状态 / 停止。

.DESCRIPTION
  先用 tml.ps1 -Detach 起一个常驻会话，之后所有用例都走这里，
  省掉每次 15-25 秒的启动开销（实测单条 0.6-1.6 秒）。

.EXAMPLE
  .\session.ps1 -Action Run   -Lab gems -Commands 'c:ui gems;c:wait 20;c:shot gems'
  .\session.ps1 -Action Suite -Lab gems -Suite .\suites\gems.json
  .\session.ps1 -Action Status -Lab gems
  .\session.ps1 -Action Stop   -Lab gems
#>
[CmdletBinding(PositionalBinding = $false)]
param(
	[ValidateSet('Run', 'Suite', 'Status', 'Stop', 'Wait', 'Poll', 'AttachClient')][string]$Action = 'Status',
	[Parameter(Mandatory)][string]$Lab,
	[string[]]$Commands = @(),
	[string[]]$Expect = @(),
	[string[]]$ExpectLog = @(),   # 按桥日志子串断言（动词/界面动作用它）
	[string]$Suite = '',
	[string]$Recipe = '',
	[string[]]$Args = @(),   # recipe 参数：page=demo 形式
	[int]$TimeoutSec = 30,   # 硬上限：任何等待都不该超过 30s
	[int]$SettleSec = 1,
	[int]$CaseTimeoutSec = 40,
	[switch]$StopOnFail,
	[string]$KitRoot = ''
)

$ErrorActionPreference = 'Stop'
$sw = [Diagnostics.Stopwatch]::StartNew()
function Log($m) { Write-Host ('[{0,5:0.0}s] {1}' -f $sw.Elapsed.TotalSeconds, $m) }

$Kit = if ($KitRoot) { $KitRoot } elseif ($env:TMLKIT_HOME) { $env:TMLKIT_HOME } else { Join-Path $env:USERPROFILE '.tmlkit' }
$LabRoot = Join-Path (Join-Path $Kit 'labs') $Lab
$InDir = Join-Path $LabRoot 'in'
$OutDir = Join-Path $LabRoot 'out'
$SessionFile = Join-Path $LabRoot '.session.json'

if (-not (Test-Path $SessionFile)) {
	if ($Action -eq 'Wait') {
		# -Detach -NoWait 是后台助手在起，会话文件会晚几秒出现：这里等它
		$sw2 = [Diagnostics.Stopwatch]::StartNew()
		while (-not (Test-Path $SessionFile) -and $sw2.Elapsed.TotalSeconds -lt $TimeoutSec) { Start-Sleep -Milliseconds 300 }
		if (-not (Test-Path $SessionFile)) { throw ('等了 ' + $TimeoutSec + 's 仍没有会话文件：' + $SessionFile + '（助手可能已经失败，查 <lab>/out 或重开）') }
	}
	else { throw "没有常驻会话：$SessionFile 不存在（先用 tml.ps1 -Detach 起一个）" }
}
$sess = Get-Content $SessionFile -Raw | ConvertFrom-Json

function Test-Alive($id) {
	if (-not $id) { return $false }
	try { return [bool](Get-Process -Id $id -ErrorAction Stop) } catch { return $false }
}
$srvAlive = Test-Alive $sess.serverPid
$cliAlive = Test-Alive $sess.clientPid

# ---------- Status ----------
if ($Action -eq 'Status') {
	[PSCustomObject]@{
		Lab = $sess.lab; Port = $sess.port; Client = $sess.client
		ServerPid = $sess.serverPid; ServerAlive = $srvAlive
		ClientPid = $sess.clientPid; ClientAlive = $cliAlive
		StartedAt = $sess.startedAt
		ServerBeat = ((Get-Content (Join-Path $OutDir 'heartbeat-server.txt') -ErrorAction SilentlyContinue | Select-Object -First 3) -join ' ')
		ClientBeat = ((Get-Content (Join-Path $OutDir 'heartbeat-client.txt') -ErrorAction SilentlyContinue | Select-Object -First 3) -join ' ')
	} | Format-List | Out-String | Write-Host
	exit 0
}

# ---------- AttachClient（-NoWait 的后台助手） ----------
if ($Action -eq 'AttachClient') {
	function LogTo($m) {
		$line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m)
		Write-Host $line
		try { Add-Content (Join-Path $OutDir 'attach-client.log') $line -Encoding utf8 } catch { }
	}
	$port = [int]$sess.port
	LogTo ('waiting port ' + $port + ' ...')
	$deadline = (Get-Date).AddSeconds($TimeoutSec)
	$ready = $false
	while ((Get-Date) -lt $deadline) {
		if (-not (Test-Alive $sess.serverPid)) { LogTo 'server 进程已退出，放弃起客户端'; exit 2 }
		try {
			$c = New-Object System.Net.Sockets.TcpClient
			$c.Connect('127.0.0.1', $port); $c.Close(); $ready = $true; break
		} catch { Start-Sleep -Milliseconds 500 }
	}
	if (-not $ready) { LogTo ('端口 ' + $port + ' 一直没在听，放弃'); exit 2 }
	LogTo ('port ready -> starting client (player=' + $sess.player + ')')

	$env:TMLKIT_ROOT = $sess.labRoot
	$env:SDL_AUDIODRIVER = 'dummy'
	$env:TMLKIT_MUTE = '1'
	$env:MOD_TESTDIR = $sess.labRoot
	if ($sess.player) { }
	$args = ('"{0}\tModLoader.dll" -join 127.0.0.1 -port {1} -player "{2}" -skipselect -tmlsavedirectory "{3}" -modpath "{4}" -steamworkshopfolder "{5}"' -f $sess.tmlDir, $port, $sess.player, $sess.saves, $sess.mods, $sess.workshop)
	$cp = Start-Process -FilePath 'dotnet' -ArgumentList $args -WorkingDirectory $sess.tmlDir -PassThru -WindowStyle Hidden
	LogTo ('client pid=' + $cp.Id)

	$sess.clientPid = $cp.Id
	$sess | ConvertTo-Json | Set-Content $SessionFile -Encoding utf8
	LogTo 'session updated (clientPid)'
	exit 0
}

# ---------- Poll（永不阻塞，供调用方当廉价探针） ----------
if ($Action -eq 'Poll') {
	$beat = Join-Path $OutDir 'heartbeat-server.txt'
	$srvReady = $false; $tick = '?'
	if (Test-Path $beat) {
		$txt = Get-Content $beat -Raw -ErrorAction SilentlyContinue
		if ($txt -match 'ms=(\d+)') {
			if (([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$Matches[1]) -lt 3000) { $srvReady = $true }
		}
		if ($txt -match 'tick=(\d+)') { $tick = $Matches[1] }
	}
	$cliReady = $false
	if ($sess.client -and $sess.clientPid) {
		$cb = Join-Path $OutDir 'heartbeat-client.txt'
		if (Test-Path $cb) {
			$ct = Get-Content $cb -Raw -ErrorAction SilentlyContinue
			if ($ct -match 'ms=(\d+)' -and (([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$Matches[1]) -lt 3000)) { $cliReady = $true }
		}
	}
	$ready = $srvReady -and ((-not $sess.client) -or $cliReady)
	Write-Host ('POLL lab={0} server={1} client={2} tick={3} port={4}' -f $sess.lab, $(if ($srvReady) { 'ready' } else { 'starting' }), $(if ($sess.client) { $(if ($cliReady) { 'ready' } else { 'starting' }) } else { 'n/a' }), $tick, $sess.port)
	if ($ready) { exit 0 } else { exit 1 }
}

# ---------- Wait ----------
if ($Action -eq 'Wait') {
	# 显式等待就绪（配合 tml.ps1 -Detach -NoWait 使用）：只等到心跳新鲜，不做别的
	$beat = Join-Path $OutDir 'heartbeat-server.txt'
	$deadline = (Get-Date).AddSeconds($TimeoutSec)
	$lastPrint = Get-Date
	while ((Get-Date) -lt $deadline) {
		if (-not (Test-Alive $sess.serverPid)) { throw ('服务端进程已退出（pid=' + $sess.serverPid + '）') }
		if (Test-Path $beat) {
			$txt = Get-Content $beat -Raw -ErrorAction SilentlyContinue
			if ($txt -match 'ms=(\d+)') {
				$age = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$Matches[1]
				if ($age -lt 3000) {
					$tick = if ($txt -match 'tick=(\d+)') { $Matches[1] } else { '?' }
					Log ('server ready: tick=' + $tick + ' port=' + $sess.port)
					if ($sess.client -and $sess.clientPid) {
						# 客户端也要就绪才算 ready：它要在载入模组/世界之后才会写心跳
						$cb = Join-Path $OutDir 'heartbeat-client.txt'
						Log 'waiting for client heartbeat ...'
						while ((Get-Date) -lt $deadline) {
							if (-not (Test-Alive $sess.clientPid)) { throw ('客户端进程已退出（pid=' + $sess.clientPid + '）') }
							if (Test-Path $cb) {
								$ctxt = Get-Content $cb -Raw -ErrorAction SilentlyContinue
								if ($ctxt -match 'ms=(\d+)') {
									$cage = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$Matches[1]
									if ($cage -lt 3000) {
										Log ('ready: client heartbeat ok (' + (($ctxt | Select-String 'tick=\d+' | Select-Object -First 1) -replace '\s+', ' ') + ')')
										exit 0
									}
								}
							}
							if (((Get-Date) - $lastPrint).TotalSeconds -ge 5) { $lastPrint = Get-Date; Log 'waiting for client heartbeat ...' }
							Start-Sleep -Milliseconds 400
						}
						throw ('客户端 ' + $TimeoutSec + 's 内没写出心跳：看 out/log-client.txt 与 tML 的 client.log')
					}
					exit 0
				}
			}
		}
		if (((Get-Date) - $lastPrint).TotalSeconds -ge 5) { $lastPrint = Get-Date; Log 'waiting for heartbeat ...' }
		Start-Sleep -Milliseconds 400
	}
	throw ('等待超时（' + $TimeoutSec + 's）：心跳没出现，用 -Action Status 看进程，或看 out/log-server.txt')
}

# ---------- Stop ----------
if ($Action -eq 'Stop') {
	$targets = @()
	if ($srvAlive) { $targets += 'cmd-server.txt' }
	if ($cliAlive) { $targets += 'cmd-client.txt' }
	foreach ($f in $targets) { Set-Content (Join-Path $InDir $f) 'exit' -Encoding utf8 }
	if ($targets.Count -gt 0) { Log ('exit requested: ' + ($targets -join ', ')); Start-Sleep -Seconds 3 }
	foreach ($id in @($sess.serverPid, $sess.clientPid)) {
		if (Test-Alive $id) { try { Stop-Process -Id $id -Force; Log "killed $id" } catch { } }
	}
	Get-ChildItem $InDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
	Remove-Item $SessionFile -Force -ErrorAction SilentlyContinue
	Log 'session stopped'

	# 句柄校验：.tmod 还被占用时，下一次打包会“静默不更新”，表现为“改了代码用例却说 no such test”
	Start-Sleep -Milliseconds 800
	$locked = @()
	Get-ChildItem (Join-Path $LabRoot 'mods') -Filter '*.tmod' -ErrorAction SilentlyContinue | ForEach-Object {
		try {
			$fs2 = [System.IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None')
			$fs2.Close()
		} catch { $locked += $_.Name }
	}
	if ($locked.Count -gt 0) {
		Log ('WARN 这些 .tmod 仍被占用（打包可能不更新）：' + ($locked -join ', '))
		Log '  处理：确认 tModLoader/游戏已退出；必要时等 1-2 秒再构建'
	}
	else { Log 'handles released: lab mods/*.tmod 未被占用' }
	exit 0
}

if (-not $srvAlive) { throw "会话的服务端进程（pid=$($sess.serverPid)）已不存在，请用 tml.ps1 -Detach 重开" }

# ---------- 结果读取（按文件偏移，只认新增行） ----------
$script:Offsets = @{}
$script:LogOffsets = @{}
function Reset-LogOffsets {
	$script:LogOffsets = @{}
	Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^log-([a-z]+)\.txt$' } |
		ForEach-Object { $script:LogOffsets[$_.FullName] = @(Get-Content $_.FullName -ErrorAction SilentlyContinue).Count }
}
function Read-NewLogLines {
	$new = @()
	Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^log-([a-z]+)\.txt$' } |
		ForEach-Object {
			$skip = if ($script:LogOffsets.ContainsKey($_.FullName)) { $script:LogOffsets[$_.FullName] } else { 0 }
			$lines = @(Get-Content $_.FullName -ErrorAction SilentlyContinue)
			if ($lines.Count -gt $skip) { $new += $lines[$skip..($lines.Count - 1)] }
			$script:LogOffsets[$_.FullName] = $lines.Count
		}
	return $new
}

function Reset-Offsets {
	# 用例之间互不污染：结果文件直接清空（桥用 AppendAllText 写，文件丢了会重建）
	$script:Offsets = @{}
	Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -match '^results?(-[a-z]+)?\.txt$' } |
		ForEach-Object {
			try { Set-Content $_.FullName '' -Encoding utf8 } catch { }
			$script:Offsets[$_.FullName] = 0
		}
}
function Read-NewLines {
	$new = @()
	Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -match '^results?(-[a-z]+)?\.txt$' } |
		ForEach-Object {
			$skip = if ($script:Offsets.ContainsKey($_.FullName)) { $script:Offsets[$_.FullName] } else { 0 }
			$lines = @(Get-Content $_.FullName -ErrorAction SilentlyContinue)
			if ($lines.Count -gt $skip) { $new += $lines[$skip..($lines.Count - 1)] }
			$script:Offsets[$_.FullName] = $lines.Count
		}
	return $new
}

# ---------- 单个用例 ----------
$RecipeDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'recipes'
function Expand-Recipe {
	param([string]$Name, [hashtable]$Values = @{})
	if (-not $Name) { return @() }
	$file = Join-Path $RecipeDir ($Name + '.json')
	if (-not (Test-Path $file)) {
		$available = @(Get-ChildItem $RecipeDir -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
		throw ("未知 recipe '{0}'；可用：{1}" -f $Name, ($available -join ', '))
	}
	$def = Get-Content $file -Raw | ConvertFrom-Json
	foreach ($req in @($def.params)) {
		if (-not $Values.ContainsKey($req)) { throw ("recipe '{0}' 缺少参数 {1}" -f $Name, $req) }
	}
	$out = @()
	foreach ($c in @($def.commands)) {
		$line = $c
		foreach ($k in $Values.Keys) { $line = $line.Replace('{' + $k + '}', [string]$Values[$k]) }
		$out += $line
	}
	return $out
}

function Get-ImageStats([string]$Path) {
	# 采样统计：尺寸 / 非均匀比例 / 颜色种类，用来判定“界面是不是空的”
	Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
	$bmp = [System.Drawing.Bitmap]::FromFile($Path)
	try {
		$w = $bmp.Width; $h = $bmp.Height
		$step = [Math]::Max(1, [int]($w / 80))
		$colors = @{}; $samples = 0
		for ($yy = 0; $yy -lt $h; $yy += $step) {
			for ($xx = 0; $xx -lt $w; $xx += $step) {
				$c = $bmp.GetPixel($xx, $yy)
				$key = ('{0},{1},{2}' -f $c.R, $c.G, $c.B)
				$colors[$key] = 1 + ($colors[$key] | ForEach-Object { $_ } )
				$samples++
			}
		}
		$distinct = $colors.Keys.Count
		$top = ($colors.Values | Measure-Object -Maximum).Maximum
		$nonUniform = [Math]::Round(1 - ($top / [double]$samples), 3)
		return [PSCustomObject]@{ Width = $w; Height = $h; Distinct = $distinct; NonUniform = $nonUniform }
	} finally { $bmp.Dispose() }
}

function Invoke-Case {
	param([string[]]$CaseCommands, [string[]]$CaseExpect, [string[]]$CaseExpectLog = @(), [int]$Timeout = 0, [string]$Name = 'case')

	$srvLines = @(); $cliLines = @()
	foreach ($c in $CaseCommands) {
		if (-not $c) { continue }
		foreach ($part in ($c -split ';')) {
			$p = $part.Trim(); if (-not $p) { continue }
			if ($p.StartsWith('c:')) { $cliLines += $p.Substring(2).Trim() }
			elseif ($p.StartsWith('s:')) { $srvLines += $p.Substring(2).Trim() }
			else { $srvLines += $p }
		}
	}
	if ($CaseExpect -contains 'ping' -and ($srvLines -notcontains 'ping')) { $srvLines = @('ping') + $srvLines }

	Reset-Offsets
	Reset-LogOffsets
	if ($srvLines.Count -gt 0) { Set-Content (Join-Path $InDir 'cmd-server.txt') ($srvLines -join "`r`n") -Encoding utf8 }
	if ($cliLines.Count -gt 0) {
		if (-not (Test-Alive $sess.clientPid)) { throw "用例 '$Name' 需要客户端，但会话里没有客户端进程" }
		Set-Content (Join-Path $InDir 'cmd-client.txt') ($cliLines -join "`r`n") -Encoding utf8
	}

	$caseSw = [Diagnostics.Stopwatch]::StartNew()
	$wanted = @(@($CaseExpect) + @($CaseExpectLog) | Where-Object { $_ -and $_.ToString().Trim() })
	$pending = [System.Collections.Generic.HashSet[string]]::new([string[]]$wanted)
	$seen = @()
	$limit = if ($Timeout -gt 0) { $Timeout } else { $CaseTimeoutSec }
	if ($pending.Count -eq 0) {
		Start-Sleep -Milliseconds ($SettleSec * 1000)
	} else {
		$deadline = (Get-Date).AddSeconds($limit)
		while ((Get-Date) -lt $deadline) {
			Start-Sleep -Milliseconds 120
			foreach ($line in (Read-NewLines)) {
				if ($line -match '^\[TEST\] (\S+) (PASS|FAIL)\s*(.*)$') {
					$seen += [PSCustomObject]@{ Case = $Matches[1]; Status = $Matches[2]; Detail = $Matches[3] }
					[void]$pending.Remove($Matches[1])
				}
			}
			foreach ($line in (Read-NewLogLines)) {
				foreach ($wanted in @($CaseExpectLog)) {
					if ($wanted -and $line -like ('*' + $wanted + '*')) {
						$seen += [PSCustomObject]@{ Case = $wanted; Status = 'PASS'; Detail = 'log hit' }
						[void]$pending.Remove($wanted)
					}
				}
			}
			if ($pending.Count -eq 0) { break }
		}
	}
	# 收尾排空：最后一批行可能落在循环退出之后
	Start-Sleep -Milliseconds 250
	foreach ($line in (Read-NewLines)) {
		if ($line -match '^\[TEST\] (\S+) (PASS|FAIL)\s*(.*)$') {
			$seen += [PSCustomObject]@{ Case = $Matches[1]; Status = $Matches[2]; Detail = $Matches[3] }
			[void]$pending.Remove($Matches[1])
		}
	}
	foreach ($line in (Read-NewLogLines)) {
		foreach ($w in @($CaseExpectLog)) {
			if ($w -and $line -like ('*' + $w + '*')) {
				$seen += [PSCustomObject]@{ Case = $w; Status = 'PASS'; Detail = 'log hit' }
				[void]$pending.Remove($w)
			}
		}
	}
	$caseSw.Stop()

	$fail = @($seen | Where-Object { $_.Status -eq 'FAIL' })
	$pass = @($seen | Where-Object { $_.Status -eq 'PASS' })
	$status = if ($fail.Count -gt 0) { 'FAIL' } elseif ($pending.Count -gt 0) { 'MISSING' } else { 'PASS' }
	return [PSCustomObject]@{
		Name = $Name; Status = $status
		Pass = $pass.Count; Fail = $fail.Count
		Missing = @($pending); Seconds = [math]::Round($caseSw.Elapsed.TotalSeconds, 2)
		Rows = $seen
	}
}

# ---------- Action: Run ----------
if ($Action -eq 'Run') {
	if ($Recipe) {
		$values = @{}
		foreach ($kv in $Args) {
			if (-not $kv) { continue }
			$parts = $kv -split '=', 2
			if ($parts.Count -eq 2) { $values[$parts[0].Trim()] = $parts[1].Trim() }
		}
		$Commands = @(Expand-Recipe -Name $Recipe -Values $values)
		Log ('recipe ' + $Recipe + ' -> ' + ($Commands -join ' | '))
	}
	$r = Invoke-Case -CaseCommands $Commands -CaseExpect $Expect -CaseExpectLog $ExpectLog -Timeout $TimeoutSec -Name 'run'
	foreach ($row in $r.Rows) { Log ("  [{0}] {1} :: {2}" -f $row.Status, $row.Case, $row.Detail) }
	Log ("RESULT: PASS={0} FAIL={1} MISSING={2} ({3}s)" -f $r.Pass, $r.Fail, ($r.Missing -join ','), $r.Seconds)
	if ($r.Status -ne 'PASS') { exit 1 }
	exit 0
}

# ---------- Action: Suite ----------
if ($Action -eq 'Suite') {
	if (-not $Suite -or -not (Test-Path $Suite)) { throw "suite 文件不存在：$Suite" }
	$def = Get-Content $Suite -Raw | ConvertFrom-Json
	if (-not $def.cases) { throw "suite 缺少 cases：$Suite" }

	Log ("suite: {0}  ({1} cases)" -f $def.name, @($def.cases).Count)
	$results = @()
	foreach ($c in $def.cases) {
		$cmds = @(if ($c.recipe) {
			$vals = @{}
			if ($c.args) { foreach ($prop in $c.args.PSObject.Properties) { $vals[$prop.Name] = $prop.Value } }
			Expand-Recipe -Name $c.recipe -Values $vals
		} else { @($c.commands) })
		if ($c.shot -and -not (@($cmds) -match '^\s*c:shot\b')) { $cmds += ('c:shot ' + $c.shot) }
		if ($c.reset) { $cmds = @('c:playerreset') + $cmds }
		$exp = @($c.expect)
		$expLog = @($c.expectLog)
		$to = if ($c.timeout) { [int]$c.timeout } else { $CaseTimeoutSec }
		$r = Invoke-Case -CaseCommands $cmds -CaseExpect $exp -CaseExpectLog $expLog -Timeout $to -Name $c.name
		if ($c.shot) {
			$shotPath = Join-Path $OutDir ($c.shot + '.png')
			$shotDeadline = (Get-Date).AddSeconds(5)
			while ((Get-Date) -lt $shotDeadline -and -not (Test-Path $shotPath)) { Start-Sleep -Milliseconds 150 }
			if (Test-Path $shotPath) {
				$st = Get-ImageStats $shotPath
				$r.Rows += [PSCustomObject]@{ Case = ('shot:' + $c.shot); Status = 'PASS'; Detail = ((Get-Item $shotPath).Length.ToString() + ' bytes, ' + $st.Width + 'x' + $st.Height) }
				$r.Rows += [PSCustomObject]@{ Case = ('shotstat:' + $c.shot); Status = 'PASS'; Detail = ('distinct=' + $st.Distinct + ' nonUniform=' + $st.NonUniform) }
			} else {
				$r.Rows += [PSCustomObject]@{ Case = ('shot:' + $c.shot); Status = 'FAIL'; Detail = '截图文件没有生成' }
				$r.Status = 'FAIL'
			}
		}
		$results += $r
		$color = switch ($r.Status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
		Write-Host ('  [{0,-7}] {1,-28} {2,5:0.00}s  pass={3} fail={4} missing={5}' -f $r.Status, $r.Name, $r.Seconds, $r.Pass, $r.Fail, ($r.Missing -join ',')) -ForegroundColor $color
		foreach ($row in $r.Rows) { Log ('     ' + $row.Status + ' ' + $row.Case + ' :: ' + $row.Detail) }
		if ($StopOnFail -and $r.Status -ne 'PASS') { Log 'StopOnFail: 中止后续用例'; break }
	}
	$bad = @($results | Where-Object { $_.Status -ne 'PASS' })
	Log ('SUITE {0}: {1}/{2} 通过，用时 {3:0.0}s' -f $def.name, (@($results | Where-Object { $_.Status -eq 'PASS' }).Count), $results.Count, $sw.Elapsed.TotalSeconds)
	if ($bad.Count -gt 0) { exit 1 }
	exit 0
}
