
<#
.SYNOPSIS
  读启动日志：不依赖模组桥，从进程第一行输出开始看。

.DESCRIPTION
  驱动会把 server/client 的 stdout+stderr 用 OS 级重定向写到
  <lab>/out/boot-server.log、boot-client.log。
  这个脚本用来查看/跟踪/过滤它们——模组没加载、桥没起来时尤其有用。

.EXAMPLE
  .\boot-log.ps1 -Lab gems -Side server -Tail 30
  .\boot-log.ps1 -Lab gems -Side client -Follow
  .\boot-log.ps1 -Lab gems -Only errors
#>
[CmdletBinding(PositionalBinding = $false)]
param(
	[Parameter(Mandatory)][string]$Lab,
	[ValidateSet('server', 'client')][string]$Side = 'server',
	[int]$Tail = 40,
	[switch]$Follow,
	[ValidateSet('all', 'errors', 'milestones')][string]$Only = 'all',
	[string]$KitRoot = ''
)

$ErrorActionPreference = 'Stop'
$Kit = if ($KitRoot) { $KitRoot } elseif ($env:TMLKIT_HOME) { $env:TMLKIT_HOME } else { Join-Path $env:USERPROFILE '.tmlkit' }
$labRoot = Join-Path (Join-Path $Kit 'labs') $Lab
$file = Join-Path (Join-Path $labRoot 'out') ('boot-' + $Side + '.log')

if (-not (Test-Path $file)) {
	Write-Host ("没有 boot 日志：{0}" -f $file)
	Write-Host '可能原因：① 这一轮不是新版驱动起的 ② 进程还没写第一行 ③ lab 名写错'
	exit 2
}

$patterns = @{
	all = '.'
	errors = 'error|exception|fatal|failed|could not|missing|refused|denied|unhandled|只允许使用一次|异常|失败'
	milestones = 'Starting tModLoader|Loading Mods|Finding Mods|Mod Load Completed|Loading World|Listening on port|Server started|Entering world|Sandboxing'
}

if ($Follow) {
	Write-Host ("following {0} ... (Ctrl+C 退出)" -f $file)
	Get-Content $file -Tail $Tail -Wait | Select-String -Pattern $patterns[$Only] | ForEach-Object { $_.Line }
	exit 0
}

$lines = Get-Content $file -ErrorAction SilentlyContinue
if ($Only -eq 'all') {
	$lines | Select-Object -Last $Tail
} else {
	$hits = $lines | Select-String -Pattern $patterns[$Only]
	if (-not $hits) { Write-Host ('（{0} 里没有匹配 {1} 的行）' -f $file, $Only) }
	else { $hits | Select-Object -Last $Tail | ForEach-Object { $_.Line } }
}
Write-Host ''
Write-Host ("file: {0}  行数: {1}" -f $file, $lines.Count)
