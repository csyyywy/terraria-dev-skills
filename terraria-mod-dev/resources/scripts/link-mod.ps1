<#
  link-mod.ps1 - 把工作区的模组工程以 junction 方式链接进 tModLoader 的 ModSources。

  用法:
    powershell -ExecutionPolicy Bypass -File link-mod.ps1 -ModName <Mod> [-Workspace <目录>] [-TerrariaDocs <Terraria 存档目录>]

  -Workspace 省略时取当前目录；-TerrariaDocs 省略时取 %USERPROFILE%\Documents\My Games\Terraria。
  幂等：已存在的 junction 只报告、不覆盖。
#>
param(
    [Parameter(Mandatory)] [string]$ModName,
    [string]$Workspace = (Get-Location).Path,
    [string]$TerrariaDocs = "$env:USERPROFILE\Documents\My Games\Terraria"
)

$ErrorActionPreference = "Stop"
$modSources = Join-Path $TerrariaDocs "tModLoader\ModSources"
$src = Join-Path $Workspace $ModName
$link = Join-Path $modSources $ModName

if (-not (Test-Path $src)) { Write-Error "Source dir not found: $src"; exit 1 }
if (-not (Test-Path $modSources)) { New-Item -ItemType Directory -Force -Path $modSources | Out-Null }

if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.LinkType -eq "Junction") {
        Write-Host "Junction exists: $link -> $($item.Target)"
    } else {
        Write-Warning "$link exists but is not a junction; handle manually."
    }
} else {
    New-Item -ItemType Junction -Path $link -Target $src | Out-Null
    Write-Host "Created junction: $link -> $src"
}

cmd /c dir $modSources
