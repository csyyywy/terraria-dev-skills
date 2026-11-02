<#
.SYNOPSIS
  给模组工程加上 headless 桥的编译引用（一行命令，不用手写相对路径）。

.DESCRIPTION
  桥是 4 个 .cs 文件（DevBridge / DevBridgeShot / DevPlayer / HeadlessLink），
  可以 vendored 进你的模组。手写 <Compile Include="..."> 时很容易把相对路径算错，
  后果是模组里没有桥 → 测试侧只看到"等不到心跳"，很难定位。

.EXAMPLE
  .\add-bridge.ps1 -Csproj ..\MyMod\MyMod.csproj
  .\add-bridge.ps1 -Csproj ..\MyMod\MyMod.csproj -Check    # 只检查有没有
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory)][string]$Csproj,
	[switch]$Check
)

$ErrorActionPreference = 'Stop'
$csprojPath = (Resolve-Path $Csproj).Path
$projDir = Split-Path -Parent $csprojPath
$bridgeDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'resources/bridge'
if (-not (Test-Path $bridgeDir)) { $bridgeDir = Join-Path $PSScriptRoot '../resources/bridge' }
$bridgeDir = (Resolve-Path $bridgeDir).Path

$text = Get-Content $csprojPath -Raw
$already = $text -match 'resources\\bridge\\\*\.cs|resources/bridge/\*\.cs'

if ($Check) {
	if ($already) { Write-Host '已包含桥引用'; exit 0 }
	Write-Host '未包含桥引用：模组里不会有 DevBridge，测试侧会报“等不到心跳”'; exit 1
}

if ($already) { Write-Host '已经包含桥引用，无需改动'; exit 0 }

# 用相对路径（可移植），分隔符按 csproj 习惯用反斜杠
$rel = [IO.Path]::GetRelativePath($projDir, $bridgeDir) -replace '/', '\'
$snippet = @"
  <ItemGroup>
    <Compile Include="$rel\*.cs" Link="Bridge\%(Filename)%(Extension)" />
  </ItemGroup>
"@

if ($text -match '</Project>') {
	$text = $text -replace '</Project>', ($snippet + "`r`n</Project>")
} else { throw "不是有效的 csproj（没有 </Project>）：$csprojPath" }

Set-Content -Path $csprojPath -Value $text -Encoding utf8
Write-Host ('已写入桥引用：' + $rel + '\*.cs')
Write-Host '重新构建模组后再跑测试。'
