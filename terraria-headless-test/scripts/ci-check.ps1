<#
.SYNOPSIS
  仓库自检：语法 / JSON / 文档引用 / 隐私扫描。CI 与本地共用同一份逻辑。

.DESCRIPTION
  不依赖 tModLoader 与游戏，任何 Windows/Linux 机器上都能跑。
  任何一项失败 → exit 1（CI 会红）。

.EXAMPLE
  .\scripts\ci-check.ps1
  .\scripts\ci-check.ps1 -Skill terraria-headless-test
#>
[CmdletBinding()]
param(
	[string]$SkillRoot = ''   # 指定要检查的技能目录；空 = 从脚本位置推断
)

$ErrorActionPreference = 'Stop'
$skillRoot = if ($SkillRoot) { (Resolve-Path $SkillRoot).Path } else { Split-Path -Parent $PSScriptRoot }
# 本地布局：<repo>/.dsh/skills/<skill>/scripts；仓库布局：<repo>/<skill>/scripts
while ((Split-Path -Parent $skillRoot) -and -not (Test-Path (Join-Path $skillRoot 'SKILL.md'))) { $skillRoot = Split-Path -Parent $skillRoot }
$repoRoot = Split-Path -Parent $skillRoot
Write-Host ('检查技能：' + $skillRoot)
$fail = 0
function Fail($msg) { Write-Host ("  FAIL  " + $msg) -ForegroundColor Red; $script:fail++ }
function Ok($msg) { Write-Host ("  ok    " + $msg) -ForegroundColor DarkGray }

Write-Host '== 1. PowerShell 语法 =='
$psFiles = @(Get-ChildItem $skillRoot -Filter *.ps1 -Recurse -File)
foreach ($f in $psFiles) {
	$errs = $null
	$null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
	if ($errs -and $errs.Count -gt 0) { Fail ($f.Name + ' 第 ' + $errs[0].Extent.StartLineNumber + ' 行：' + $errs[0].Message) }
}
if ($fail -eq 0) { Ok ($psFiles.Count.ToString() + ' 个脚本解析通过') }

Write-Host '== 2. JSON 结构 =='
$jsonFiles = @(Get-ChildItem $skillRoot -Filter *.json -Recurse -File)
foreach ($f in $jsonFiles) {
	try { $null = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { Fail ($f.Name + ' JSON 无效：' + $_.Exception.Message) }
}
if ($jsonFiles.Count -gt 0) { Ok ($jsonFiles.Count.ToString() + ' 个 JSON 可解析') }

Write-Host '== 3. SKILL.md frontmatter =='
$skillMd = Join-Path $skillRoot 'SKILL.md'
if (-not (Test-Path $skillMd)) { Fail '缺少 SKILL.md' }
else {
	$head = (Get-Content $skillMd -Raw)
	if ($head -notmatch '(?m)^name:\s*\S+') { Fail 'frontmatter 缺少 name' }
	if ($head -notmatch '(?m)^description:\s*\S+') { Fail 'frontmatter 缺少 description' }
	if ($head -notmatch '(?m)^---\s*$') { Fail 'frontmatter 未闭合（---）' }
}

Write-Host '== 4. 文档里引用的文件是否存在 =='
$mdFiles = @(Get-ChildItem $skillRoot -Filter *.md -Recurse -File)
$checked = 0
foreach ($md in $mdFiles) {
	$text = Get-Content $md.FullName -Raw
	# 只检查反引号里、看起来是相对路径的条目
	foreach ($m in [regex]::Matches($text, '`([A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-/]+\.(md|json|ps1|cs|png))`')) {
		# 只校验仓库自有目录；Content/、Layout/ 等是“用户项目/上游框架”的示例路径，跳过
		if ($m.Groups[1].Value -notmatch '^(resources|scripts|docs|optional|tools|examples|\.github)/') { continue }
		$rel = $m.Groups[1].Value -replace '/', [IO.Path]::DirectorySeparatorChar
		$checked++
		$candidates = @(
			(Join-Path $skillRoot $rel),
			(Join-Path $md.Directory.FullName $rel),
			(Join-Path $repoRoot $rel)
		)
		if (-not ($candidates | Where-Object { Test-Path $_ })) {
			Fail ($md.Name + ' 引用了不存在的文件：' + $m.Groups[1].Value)
		}
	}
}
Ok ('检查了 ' + $checked + ' 条路径引用')

Write-Host '== 5. 隐私扫描（本机路径 / 未置零标识）=='
$patterns = @{
	'本机用户目录' = 'C:\\Users\\[A-Za-z0-9]'
	'Steam 库路径' = 'E:\\SteamLibrary'
	'作者工作目录' = 'D:\\ai\\'
}
$privacyHits = 0
foreach ($f in @(Get-ChildItem $skillRoot -Recurse -File | Where-Object { $_.Extension -match '^\.(md|ps1|cs|json|txt)$' })) {
	$text = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
	if (-not $text) { continue }
	foreach ($k in $patterns.Keys) {
		if ($text -match $patterns[$k]) { Fail ($f.Name + ' 含' + $k); $privacyHits++ }
	}
	if ($f.Extension -eq '.json' -and $text -match '"ClientUUID"\s*:\s*"(?!00000000-0000-0000-0000-000000000000)[0-9a-fA-F-]{36}"') {
		Fail ($f.Name + ' 的 ClientUUID 未置零'); $privacyHits++
	}
}
if ($privacyHits -eq 0) { Ok '无本机路径、无未置零 ClientUUID' }

if (-not (Test-Path (Join-Path $skillRoot 'resources/scripts/tml.ps1'))) {
	Write-Host '== 6. -PlanOnly 冒烟：本技能无驱动脚本，跳过 =='
	Write-Host ''
	if ($fail -gt 0) { Write-Host ($fail.ToString() + ' 项失败') -ForegroundColor Red; exit 1 }
	Write-Host '全部检查通过' -ForegroundColor Green
	exit 0
}

Write-Host '== 6. -PlanOnly 冒烟（不启动任何进程）=='
try {
	$out = & pwsh -NoProfile -File (Join-Path $skillRoot 'resources/scripts/tml.ps1') -Lab ci -ModName CiMod -Tmod 'CiMod.tmod' -TmlDir '/tmp/tml' -Commands 'ping' -Expect ping -PlanOnly 2>&1
	if ($LASTEXITCODE -ne 0) { Fail ('-PlanOnly 退出码 ' + $LASTEXITCODE) }
	elseif (-not ($out -match 'tModLoader.dll')) { Fail '-PlanOnly 没有输出预期命令行' }
	else { Ok '-PlanOnly 正常输出计划' }
} catch { Fail ('-PlanOnly 抛异常：' + $_.Exception.Message) }

Write-Host ''
if ($fail -gt 0) { Write-Host ($fail.ToString() + ' 项失败') -ForegroundColor Red; exit 1 }
Write-Host '全部检查通过' -ForegroundColor Green
exit 0
