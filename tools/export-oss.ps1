<#
.SYNOPSIS
  导出一份可公开的干净副本（只含技能内容，不含本仓库其它私有项目与历史）。

.DESCRIPTION
  父仓库里还有个人模组工程等私有内容，直接把整库推上去会连带泄露。
  这个脚本把 .dsh/skills 下的技能复制到 -Out 指定的新目录，并：
    - 校验没有本机绝对路径 / 个人标识残留
    - 生成独立仓库所需的 README / LICENSE / NOTICE
    - 可选：git init + 首次提交

.EXAMPLE
  .\export-oss.ps1 -Out D:\oss\terraria-headless-test -Init
#>
[CmdletBinding()]
param(
	[string]$Out = (Join-Path $PWD 'oss-export'),
	[string[]]$Skills = @('terraria-headless-test', 'terraria-mod-dev', 'terraria-mod-ui', 'silky-ui-framework', 'terraria-ai-textures'),
	[string]$Remote = '',
	[switch]$Init
)

$ErrorActionPreference = 'Stop'
$skillsRoot = Split-Path -Parent $PSScriptRoot          # <repo>/.dsh/skills
$repo = Split-Path -Parent (Split-Path -Parent $skillsRoot)   # repo 根
$src = $skillsRoot
if (-not (Test-Path $src)) { throw "找不到技能目录：$src" }

if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

foreach ($s in $Skills) {
	$from = Join-Path $src $s
	if (-not (Test-Path $from)) { Write-Host ("跳过（不存在）：" + $s); continue }
	Copy-Item $from (Join-Path $Out $s) -Recurse -Force
	Write-Host ("copied " + $s)
}
foreach ($f in @('README.md', 'LICENSE', 'NOTICE.md')) {
	$p = Join-Path $src $f
	if (Test-Path $p) { Copy-Item $p (Join-Path $Out $f) -Force }
}

# 泄露检查
$bad = @()
$patterns = @('C:\\Users\\', 'E:\\SteamLibrary', 'D:\\ai\\', 'ClientUUID": "(?!00000000)')
Get-ChildItem $Out -Recurse -File | Where-Object { $_.Extension -match '^\.(md|ps1|cs|json|txt)$' } | ForEach-Object {
	$text = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
	foreach ($pat in $patterns) {
		if ($text -match $pat) { $bad += ($_.FullName + '  <= ' + $pat) }
	}
}
if ($bad.Count -gt 0) {
	Write-Host '发现疑似本机路径/标识，已中止：' -ForegroundColor Red
	$bad | ForEach-Object { Write-Host ('  ' + $_) }
	exit 2
}
Write-Host '隐私检查通过：无本机绝对路径、无未置零的 ClientUUID' -ForegroundColor Green

$gitignore = @"
labs/
*.log
*.partial
.session.json
out/
"@
Set-Content (Join-Path $Out '.gitignore') $gitignore -Encoding utf8

if ($Init) {
	Push-Location $Out
	try {
		git init --quiet
		git add -A
		git -c user.name='oss-export' -c user.email='oss@local' commit --quiet -m 'chore: 导出可公开技能集合'
		if ($Remote) { git remote add origin $Remote; git branch -M main }
		Write-Host ('已初始化独立仓库：' + $Out)
		if ($Remote) { Write-Host ('remote: ' + $Remote + '（未 push，确认无误后 git push -u origin main）') }
	} finally { Pop-Location }
}

Write-Host ('导出完成：' + $Out)
