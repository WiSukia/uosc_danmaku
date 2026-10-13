param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$helperSource = Join-Path $repoRoot 'UoscInputBridge.cs'
if (-not (Test-Path -LiteralPath $helperSource)) { $helperSource = Join-Path $repoRoot 'scripts\uosc_danmaku\UoscInputBridge.cs' }
if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path $helperSource -Parent) 'UoscInputBridge.exe' }
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compilerPath)) {
    $compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $compilerPath)) { throw '需要 Windows .NET Framework 4.x C# 编译器。' }
& $compilerPath /nologo /target:winexe /optimize+ "/out:$OutputPath" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll $helperSource
if ($LASTEXITCODE -ne 0) { throw '输入助手编译失败。' }
Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256
