# ============================================================
# check-hjson.ps1 - 本地化 hjson 语法校验（防"模组被禁用"事故）
#
# 背景：Hjson 对「值以 { 开头 / 多行字符串未加引号」极敏感，一个
# 语法错误就会让模组加载失败并被自动禁用。
# 本脚本用真实 Hjson 解析器（NuGet Hjson）逐文件解析，出错即非零退出。
#
# 用法: powershell -File check-hjson.ps1 -Dir <Localization 目录> [-DotNet <dotnet>]
#      -Dir 省略时默认 <当前目录>\Localization
# ============================================================
param(
    [string]$Dir = '',
    [string]$DotNet = 'dotnet'
)
$ErrorActionPreference = 'Stop'
if (-not $Dir) { $Dir = Join-Path (Get-Location) 'Localization' }
if (-not (Test-Path $Dir)) { throw "Localization dir not found: $Dir (pass -Dir <path>)" }

$files = Get-ChildItem $Dir -Filter '*.hjson'
if ($files.Count -eq 0) { throw "no .hjson under $Dir" }

# 临时 .NET 校验项目（Hjson NuGet）
$tmp = Join-Path $env:TEMP ("hjson-check-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>disable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup><PackageReference Include="Hjson" Version="3.0.0" /></ItemGroup>
</Project>
'@ | Set-Content (Join-Path $tmp 'check.csproj')
@'
using System;
using System.IO;
class P {
  static int Main(string[] a) {
    int bad = 0;
    foreach (var f in a) {
      try { Hjson.HjsonValue.Parse(File.ReadAllText(f)); Console.WriteLine("OK   " + Path.GetFileName(f)); }
      catch (Exception e) { bad++; Console.WriteLine("FAIL " + Path.GetFileName(f) + " : " + e.Message); }
    }
    return bad;
  }
}
'@ | Set-Content (Join-Path $tmp 'Program.cs')

& $DotNet run --project (Join-Path $tmp 'check.csproj') -- $($files.FullName) 2>&1 | Where-Object { $_ -match '^(OK|FAIL)' }
$code = $LASTEXITCODE
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($code -ne 0) { throw "hjson validation FAILED" }
Write-Host "hjson validation PASS ($($files.Count) files)"
exit 0
