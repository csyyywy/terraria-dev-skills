<#
.SYNOPSIS
  40 秒判定这台机器现在能不能起 tModLoader 客户端并进入模组枚举。

.DESCRIPTION
  不加载任何模组、不连服务器、不涉及被测模组：只回答一个问题——
  tML 客户端能不能走到日志里的 "Finding Mods..."。
  走不到就说明环境侧（Steam / 图形 / 音频 / 残留实例）有问题，与模组和技能无关。

.EXAMPLE
  .\preflight-client.ps1 -TmlDir <TML_DIR>
#>
[CmdletBinding(PositionalBinding = $false)]
param(
	[Parameter(Mandatory)][string]$TmlDir,
	[string]$DotNet = 'dotnet',
	[int]$WaitSec = 40
)

$ErrorActionPreference = 'Stop'
# Steam 必须在跑：tML 客户端启动时会校验，缺了会弹 Fatal Error 模态框并把进程卡住
$steam = @(Get-Process steam, steamwebhelper -ErrorAction SilentlyContinue)
if ($steam.Count -eq 0) {
	Write-Host 'PREFLIGHT FAIL: Steam 没有运行' -ForegroundColor Red
	Write-Host '  tML 客户端启动时要求 Steam 已登录，否则弹 "Please ensure Steam is logged in and running." 并卡在对话框。'
	Write-Host '  处理：启动 Steam 并登录后重跑本检查。-Server 模式（L1）不需要 Steam。'
	exit 2
}

$lab = Join-Path ([IO.Path]::GetTempPath()) ('tml-preflight-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $lab 'saves\Mods'), (Join-Path $lab 'mods'), (Join-Path $lab 'workshop') | Out-Null
# 没有 config.json 时 tML 会停在 Select Language 界面，永远进不了模组枚举（本次排查的真凶）
$tpl = Join-Path $PSScriptRoot '..\config\client-config.json'
$cfg = Join-Path $lab 'saves\config.json'
if (Test-Path $tpl) { Copy-Item $tpl $cfg -Force }
else { '{"Language":"en-US"}' | Set-Content $cfg -Encoding utf8 }
$log = Join-Path $TmlDir 'tModLoader-Logs\client.log'
$stamp = if (Test-Path $log) { (Get-Item $log).LastWriteTime } else { [datetime]::MinValue }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $DotNet
$psi.Arguments = ('"{0}\tModLoader.dll" -tmlsavedirectory "{1}\saves" -modpath "{1}\mods" -steamworkshopfolder "{1}\workshop"' -f $TmlDir, $lab)
$psi.WorkingDirectory = $TmlDir
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError = $false
$p = [System.Diagnostics.Process]::Start($psi)
Write-Host ("preflight: client pid={0}, 等待 {1}s ..." -f $p.Id, $WaitSec)

$ok = $false
$deadline = (Get-Date).AddSeconds($WaitSec)
while ((Get-Date) -lt $deadline) {
	Start-Sleep -Milliseconds 500
	if ($p.HasExited) { break }
	if ((Test-Path $log) -and (Get-Item $log).LastWriteTime -gt $stamp) {
		if (Select-String -Path $log -Pattern 'Finding Mods' -Quiet -ErrorAction SilentlyContinue) { $ok = $true; break }
	}
}

$tail = @()
if (Test-Path $log) { $tail = Get-Content $log -Tail 8 }
if (-not $p.HasExited) { try { $p.Kill() } catch { } }
Remove-Item $lab -Recurse -Force -ErrorAction SilentlyContinue

if ($ok) {
	Write-Host 'PREFLIGHT PASS: 客户端能进入模组枚举，环境正常' -ForegroundColor Green
	exit 0
}

Write-Host 'PREFLIGHT FAIL: 客户端没走到 Finding Mods（卡在模组枚举之前）' -ForegroundColor Red
Write-Host '  client.log 尾部：'
$tail | ForEach-Object { Write-Host "    $_" }
Write-Host '  处理顺序：'
Write-Host '    1) 退出 Steam 与所有 tModLoader 实例后重试（最常见）'
Write-Host '    2) 关掉占用显卡/声卡独占的程序（录屏、虚拟声卡）'
Write-Host '    3) 仍不行则重启机器——这类卡死与模组无关'
exit 1