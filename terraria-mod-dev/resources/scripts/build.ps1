<#
  build.ps1 - 用带 SDK 的 dotnet 构建模组（PATH 上的 dotnet 可能只是运行时）。

  用法:
    powershell -ExecutionPolicy Bypass -File build.ps1 -ProjectPath <csproj> [-Config Debug] [-SkipPack]

  -SkipPack 只编译不打包：必须同时传 TargetFramework，只传 -p:BuildMod=false 会报 NETSDK1013（脚本已处理）。
#>
param(
    [Parameter(Mandatory)] [string]$ProjectPath,
    [ValidateSet("Debug","Release")] [string]$Config = "Debug",
    [switch]$SkipPack
)

$ErrorActionPreference = "Stop"

# 受限沙箱可能剥离这些 Windows 目录环境变量，导致 NuGet restore 报
# "NuGet.targets(745,5): error : Value cannot be null. (Parameter 'path1')"
# （NuGetEnvironment.GetFolderPath 读 PROGRAMFILES(X86)/PROGRAMDATA 等拼路径，缺则为 null）。
# 已设置则原样保留，缺失才补默认值。
$env:HOME        = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$env:APPDATA     = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $env:USERPROFILE 'AppData\Roaming' }
$env:LOCALAPPDATA= if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
$env:PROGRAMDATA = if ($env:PROGRAMDATA) { $env:PROGRAMDATA } else { 'C:\ProgramData' }
$env:ALLUSERSPROFILE = if ($env:ALLUSERSPROFILE) { $env:ALLUSERSPROFILE } else { 'C:\ProgramData' }
$env:PROGRAMFILES = if ($env:PROGRAMFILES) { $env:PROGRAMFILES } else { 'C:\Program Files' }
if (-not ${env:PROGRAMFILES(X86)}) { ${env:PROGRAMFILES(X86)} = 'C:\Program Files (x86)' }
$env:ComSpec     = if ($env:ComSpec) { $env:ComSpec } else { Join-Path $env:windir 'system32\cmd.exe' }

# dotnet 解析：优先标准安装位置（含 SDK），回退 PATH。
# 前提：`dotnet --list-sdks` 必须能看到 9.x，否则编译 C# preview 语法的依赖库会失败。
$dotnet = $null
$candidates = @((Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'), 'dotnet')
foreach ($cand in $candidates) {
    if ($cand -eq 'dotnet') { $dotnet = 'dotnet'; break }
    if (Test-Path $cand) { $dotnet = $cand; break }
}

if (-not (Test-Path $ProjectPath)) { Write-Error "Project not found: $ProjectPath"; exit 1 }

$buildArgs = @("build", $ProjectPath, "-c", $Config)
if ($SkipPack) { $buildArgs += @("-p:BuildMod=false", "-p:TargetFramework=net8.0") }

Write-Host "==> & $dotnet $($buildArgs -join ' ')"
& $dotnet @buildArgs
exit $LASTEXITCODE
