
<#
.SYNOPSIS
  并行跑多个 suite：每个 suite 独立 lab + 独立端口，互不干扰。

.DESCRIPTION
  每个 suite 会：起常驻会话（-Detach）→ 跑 suite → 停会话，全程在子进程里完成。
  L1（无客户端）可任意并行；L2 受 Steam/显卡限制，默认强制串行。

.EXAMPLE
  .\suites.ps1 -Suite .\suites\demo-l1.json,.\suites\demo-l1.json -Parallel 2 `
      -ModName MyMod -Tmod <tmod> -TmlDir <TML_DIR> -Port 8100
#>
[CmdletBinding(PositionalBinding = $false)]
param(
	[string[]]$Suite = @(),
	[int]$Parallel = 2,
	[string]$ModName = '',
	[string]$Tmod = '',
	[string]$TmlDir = '',
	[string]$ProjectPath = '',
	[int]$Port = 8100,
	[string]$LabPrefix = 'par',
	[switch]$Client,
	[string]$Player = 'TestPlayer',
	[switch]$Keep,
	[string]$KitRoot = '',
	[switch]$Worker,
	[string]$WorkerLab = '',
	[int]$WorkerPort = 0,
	[string]$WorkerSuite = '',
	[string]$WorkerLog = ''
)

$ErrorActionPreference = 'Stop'
# pwsh -File 把 'a,b' 当一个字符串传进来，自己拆
$Suite = @($Suite | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sw = [Diagnostics.Stopwatch]::StartNew()
function Log($m) { Write-Host ('[{0,6:0.0}s] {1}' -f $sw.Elapsed.TotalSeconds, $m) }

# ---------- 工作进程：起会话 → 跑 suite → 停会话 ----------
if ($Worker) {
	try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
	$tml = Join-Path $here 'tml.ps1'
	$ses = Join-Path $here 'session.ps1'
	$detachArgs = @(
		'-NoProfile', '-File', $tml,
		'-Lab', $WorkerLab, '-ModName', $ModName, '-TmlDir', $TmlDir, '-Port', $WorkerPort,
		'-Commands', 'ping', '-Expect', 'ping', '-TimeoutSec', '90', '-Detach'
	)
	if ($Tmod) { $detachArgs += @('-Tmod', $Tmod) } else { $detachArgs += @('-ProjectPath', $ProjectPath) }
	if ($Client) { $detachArgs += @('-Client', '-Player', $Player, '-MinimizeClient') }
	if ($KitRoot) { $detachArgs += @('-KitRoot', $KitRoot) }

	Log "[$WorkerLab] starting session on port $WorkerPort"
	$p = Start-Process -FilePath 'pwsh' -ArgumentList $detachArgs -PassThru -Wait -WindowStyle Hidden
	if ($p.ExitCode -ne 0) { Log "[$WorkerLab] session start FAILED (exit=$($p.ExitCode))"; exit 2 }

	$suiteArgs = @('-NoProfile', '-File', $ses, '-Action', 'Suite', '-Lab', $WorkerLab, '-Suite', $WorkerSuite)
	if ($KitRoot) { $suiteArgs += @('-KitRoot', $KitRoot) }
	Log "[$WorkerLab] running suite $WorkerSuite"
	& pwsh @suiteArgs
	$suiteExit = $LASTEXITCODE

	if (-not $Keep) {
		$stopArgs = @('-NoProfile', '-File', $ses, '-Action', 'Stop', '-Lab', $WorkerLab)
		if ($KitRoot) { $stopArgs += @('-KitRoot', $KitRoot) }
		& pwsh @stopArgs | Out-Null
	}
	exit $suiteExit
}

# ---------- 编排 ----------
if ($Suite.Count -eq 0) { throw '至少给一个 -Suite' }
foreach ($s in $Suite) { if (-not (Test-Path $s)) { throw "suite 不存在：$s" } }
if (-not $Tmod -and -not $ProjectPath) { throw '需要 -Tmod 或 -ProjectPath' }
if (-not $TmlDir) { throw '需要 -TmlDir' }

$effective = $Parallel
if ($Client -and $Parallel -gt 1) {
	Log 'WARN 带客户端并行会抢 Steam/显卡/焦点，强制串行'
	$effective = 1
}

$Kit = if ($KitRoot) { $KitRoot } elseif ($env:TMLKIT_HOME) { $env:TMLKIT_HOME } else { Join-Path $env:USERPROFILE '.tmlkit' }
$logsDir = Join-Path (Join-Path $Kit 'logs') ('par-' + (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

Log ("suites={0} parallel={1} portBase={2}" -f $Suite.Count, $effective, $Port)

$queue = [System.Collections.Generic.Queue[object]]::new()
for ($i = 0; $i -lt $Suite.Count; $i++) {
	$name = [IO.Path]::GetFileNameWithoutExtension($Suite[$i])
	$queue.Enqueue([PSCustomObject]@{ Index = $i; Suite = (Resolve-Path $Suite[$i]).Path; Lab = ('{0}-{1}-{2}' -f $LabPrefix, $name, $i); Port = ($Port + $i) })
}

$running = @()
$results = @()
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
	while ($running.Count -lt $effective -and $queue.Count -gt 0) {
		$job = $queue.Dequeue()
		$log = Join-Path $logsDir ($job.Lab + '.log')
		$args2 = @(
			'-NoProfile', '-File', (Join-Path $here 'suites.ps1'),
			'-Worker', '-WorkerLab', $job.Lab, '-WorkerPort', $job.Port, '-WorkerSuite', $job.Suite,
			'-ModName', $ModName, '-TmlDir', $TmlDir, '-Port', $Port
		)
		if ($Tmod) { $args2 += @('-Tmod', $Tmod) }
		if ($ProjectPath) { $args2 += @('-ProjectPath', $ProjectPath) }
		if ($Client) { $args2 += @('-Client', '-Player', $Player) }
		if ($Keep) { $args2 += '-Keep' }
		if ($KitRoot) { $args2 += @('-KitRoot', $KitRoot) }
		$proc = Start-Process -FilePath 'pwsh' -ArgumentList $args2 -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + '.err') -WindowStyle Hidden
		$running += [PSCustomObject]@{ Job = $job; Proc = $proc; Log = $log; Started = (Get-Date) }
		Log ("started {0} (port {1})" -f $job.Lab, $job.Port)
	}
	Start-Sleep -Milliseconds 400
	$done = @($running | Where-Object { $_.Proc.HasExited })
	foreach ($d in $done) {
		$running = @($running | Where-Object { $_.Proc.Id -ne $d.Proc.Id })
		$exit = $d.Proc.ExitCode
		$summary = (Select-String -Path $d.Log -Pattern 'SUITE ' -Encoding utf8 -ErrorAction SilentlyContinue | Select-Object -Last 1).Line
		if (-not $summary) { $summary = (Get-Content $d.Log -Tail 2 -Encoding utf8 -ErrorAction SilentlyContinue) -join ' | ' }
		$results += [PSCustomObject]@{ Lab = $d.Job.Lab; Exit = $exit; Seconds = [math]::Round(((Get-Date) - $d.Started).TotalSeconds, 1); Summary = $summary.Trim(); Log = $d.Log }
		Log ("finished {0} exit={1} {2}s" -f $d.Job.Lab, $exit, [math]::Round(((Get-Date) - $d.Started).TotalSeconds, 1))
	}
}

Write-Host ''
Write-Host '=== 并行结果 ==='
$results | Sort-Object Lab | Format-Table Lab, Exit, Seconds, Summary -AutoSize | Out-String -Width 200 | Write-Host
$bad = @($results | Where-Object { $_.Exit -ne 0 })
Log ('logs: ' + $logsDir)
Log ('PARALLEL: {0}/{1} 通过，墙钟 {2:0.0}s' -f ($results.Count - $bad.Count), $results.Count, $sw.Elapsed.TotalSeconds)
if ($bad.Count -gt 0) { exit 1 }
exit 0
