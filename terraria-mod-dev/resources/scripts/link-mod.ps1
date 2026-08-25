<#
  link-mod.ps1 - Link a workspace mod project into tModLoader ModSources (junction).
  Usage: powershell -ExecutionPolicy Bypass -File link-mod.ps1 [-ModName MyMod] [-Workspace <WORKSPACE>]
  Idempotent: an existing junction is detected and reported, never overwritten.
#>
param(
    [string]$ModName = "MyMod",
    [string]$Workspace = '',
    [string]$TerrariaDocs = "$env:USERPROFILE\Documents\My Games\Terraria"
)

$ErrorActionPreference = "Stop"
if (-not $Workspace) {
    # 默认：脚本向上 5 级（<workspace>\skills\terraria-mod-dev\resources\scripts）
    $ws = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..') -ErrorAction SilentlyContinue
    if ($ws) { $Workspace = $ws.Path }
}
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
