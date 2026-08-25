<#
  build.ps1 - Build a mod with the SDK-capable dotnet (the PATH dotnet may be a runtime-only copy).
  Usage: powershell -ExecutionPolicy Bypass -File build.ps1 [-ModName MyMod] [-Config Debug] [-SkipPack]
  NOTE: compile-only (-SkipPack) must also pass TargetFramework; only -p:BuildMod=false breaks the build.
#>
param(
    [string]$ModName = "MyMod",
    [ValidateSet("Debug","Release")] [string]$Config = "Debug",
    [switch]$SkipPack
)

$ErrorActionPreference = "Stop"

# 受限 shell 环境可能剥离这些 Windows 特殊目录环境变量，导致 NuGet restore 报
# "NuGet.targets(745,5): error : Value cannot be null. (Parameter 'path1')"
# （NuGetEnvironment.GetFolderPath 读 PROGRAMFILES(X86)/PROGRAMDATA 等拼路径，缺则 null）。
# 补回即可（已设则原样保留）。
$env:HOME        = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$env:APPDATA     = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $env:USERPROFILE 'AppData\Roaming' }
$env:LOCALAPPDATA= if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
$env:PROGRAMDATA = if ($env:PROGRAMDATA) { $env:PROGRAMDATA } else { 'C:\ProgramData' }
$env:ALLUSERSPROFILE = if ($env:ALLUSERSPROFILE) { $env:ALLUSERSPROFILE } else { 'C:\ProgramData' }
$env:PROGRAMFILES = if ($env:PROGRAMFILES) { $env:PROGRAMFILES } else { 'C:\Program Files' }
if (-not ${env:PROGRAMFILES(X86)}) { ${env:PROGRAMFILES(X86)} = 'C:\Program Files (x86)' }
$env:ComSpec     = if ($env:ComSpec) { $env:ComSpec } else { Join-Path $env:windir 'system32\cmd.exe' }

$dotnet = $null
foreach ($cand in @("$env:USERPROFILE\.dotnet\dotnet.exe", "C:\Program Files (x86)\dotnet\dotnet.exe")) {
    if (Test-Path $cand) { $dotnet = $cand; break }
}
if (-not $dotnet) { $dotnet = "dotnet" }

# 默认从脚本位置向上 5 级找工作区（<workspace>\skills\terraria-mod-dev\resources\scripts），
# 也支持 -ModName 与放在别处的工作区（可把工程路径写进 $proj 或 cd 到工作区）。
$ws = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..') -ErrorAction SilentlyContinue)
$proj = if ($ws) { Join-Path $ws.Path "$ModName\$ModName.csproj" } else { Join-Path (Get-Location) "$ModName\$ModName.csproj" }
if (-not (Test-Path $proj)) { Write-Error "Project not found: $proj"; exit 1 }

$args = @("build", $proj, "-c", $Config)
if ($SkipPack) { $args += @("-p:BuildMod=false", "-p:TargetFramework=net8.0") }

Write-Host "==> & $dotnet $($args -join ' ')"
& $dotnet @args
exit $LASTEXITCODE