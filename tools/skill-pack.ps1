<#
.SYNOPSIS
  可选技能包开关：在 skills/ 与 skills/optional/ 之间移动，控制是否被模型自动发现。

.DESCRIPTION
  DSH 只扫描 skills/ 下一层的 SKILL.md。放在 optional/ 里的技能不会进入技能目录，
  因此不会被自动选择；需要时用 -Enable 启用，用完 -Disable 收起。

.EXAMPLE
  .\skill-pack.ps1 -List
  .\skill-pack.ps1 -Name silky-ui-framework -Enable
  .\skill-pack.ps1 -Name silky-ui-framework -Disable
  .\skill-pack.ps1 -Name silky-ui-framework -Enable -Sync     # 同时同步到安装目录
#>
[CmdletBinding(PositionalBinding = $false)]
param(
	[string]$Name = '',
	[switch]$Enable,
	[switch]$Disable,
	[switch]$List,
	[string]$Sync = ''
)

$ErrorActionPreference = 'Stop'
$skillsRoot = Split-Path -Parent $PSScriptRoot
$optional = Join-Path $skillsRoot 'optional'
if (-not (Test-Path $optional)) { New-Item -ItemType Directory -Path $optional | Out-Null }

if ($List -or -not $Name) {
	$on = @(Get-ChildItem $skillsRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | Select-Object -ExpandProperty Name)
	$off = @(Get-ChildItem $optional -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | Select-Object -ExpandProperty Name)
	Write-Host '启用（会被自动发现）:' (($on -join ', '))
	Write-Host '可选（默认不可见）  :' (($off -join ', '))
	exit 0
}

$active = Join-Path $skillsRoot $Name
$packed = Join-Path $optional $Name

if ($Enable) {
	if (Test-Path $packed) { Move-Item $packed $active; Write-Host ("启用：" + $Name) }
	elseif (Test-Path $active) { Write-Host ("已经是启用状态：" + $Name) }
	else { throw "找不到技能：$Name" }
}
elseif ($Disable) {
	if (Test-Path $active) { Move-Item $active $packed; Write-Host ("收起：" + $Name) }
	elseif (Test-Path $packed) { Write-Host ("已经是收起状态：" + $Name) }
	else { throw "找不到技能：$Name" }
}
else { throw '需要 -Enable 或 -Disable（或 -List）' }

if ($Sync) {
	$target = Join-Path $Sync $Name
	if (Test-Path $target) { Remove-Item $target -Recurse -Force }
	$from = if ($Enable) { $active } else { Join-Path $optional $Name }
	Copy-Item $from $target -Recurse -Force
	Write-Host ("已同步到：" + $target)
}
