<#
  unlink-mod.ps1 - Remove the ModSources junction (does NOT delete source).
  Usage: powershell -ExecutionPolicy Bypass -File unlink-mod.ps1 [-ModName MyMod]
#>
param(
    [string]$ModName = "MyMod",
    [string]$TerrariaDocs = "$env:USERPROFILE\Documents\My Games\Terraria"
)

$ErrorActionPreference = "Stop"
$link = Join-Path $TerrariaDocs "tModLoader\ModSources\$ModName"

if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.LinkType -eq "Junction") {
        Remove-Item $link -Force
        Write-Host "Removed junction: $link"
    } else {
        Write-Warning "$link is not a junction; skipped."
    }
} else {
    Write-Host "Link does not exist: $link"
}
