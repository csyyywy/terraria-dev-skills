<#
.SYNOPSIS
  把 ci/workflows/*.yml 安装到 .github/workflows/ 并提交。

.DESCRIPTION
  GitHub 规定：带 workflow 权限的 token 才能推送 .github/workflows 下的文件。
  如果你当前的凭据没有该权限（推送会报 "refusing to allow an OAuth App to create or update workflow"），
  就用这个脚本在**有权限的环境**里安装，或直接在网页上新建这两个文件（内容完全相同）。

.EXAMPLE
  .\install-workflows.ps1                 # 只复制到工作区
  .\install-workflows.ps1 -Commit -Push   # 复制 + 提交 + 推送
#>
[CmdletBinding()]
param(
	[switch]$Commit,
	[switch]$Push,
	[string]$Remote = 'origin',
	[string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo 'ci/workflows'
$dst = Join-Path $repo '.github/workflows'
if (-not (Test-Path $src)) { throw "找不到 $src" }
New-Item -ItemType Directory -Force -Path $dst | Out-Null

Get-ChildItem $src -Filter *.yml | ForEach-Object {
	Copy-Item $_.FullName (Join-Path $dst $_.Name) -Force
	Write-Host ("安装 " + $_.Name)
}

if ($Commit) {
	Push-Location $repo
	try {
		git add .github/workflows
		git commit -m 'ci: 安装 GitHub Actions 工作流' --quiet
		Write-Host '已提交'
		if ($Push) {
			git push $Remote $Branch
			Write-Host ('已推送到 ' + $Remote + '/' + $Branch)
		}
	} finally { Pop-Location }
}
