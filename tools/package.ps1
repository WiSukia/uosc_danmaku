param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'dist' }
$stagePath = Join-Path $repoRoot ('build\package-' + [Guid]::NewGuid().ToString('N'))
$scriptPath = Join-Path $stagePath 'scripts\uosc_danmaku'
New-Item -ItemType Directory -Path $scriptPath -Force | Out-Null
foreach ($fileName in @('main.lua','LICENSE','UoscInputBridge.cs')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $fileName) -Destination $scriptPath
}
foreach ($folderName in @('apis','dicts','modules')) {
    $destinationPath = Join-Path $scriptPath $folderName
    New-Item -ItemType Directory -Path $destinationPath | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $repoRoot $folderName) -Filter '*.lua' -File | Copy-Item -Destination $destinationPath
}
& (Join-Path $PSScriptRoot 'build-helper.ps1') -OutputPath (Join-Path $scriptPath 'UoscInputBridge.exe') | Out-Null
foreach ($folderName in @('compat','examples','docs','tools')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $folderName) -Destination $stagePath -Recurse
}
foreach ($fileName in @('README.md','CHANGELOG.md','LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $fileName) -Destination $stagePath
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$zipPath = Join-Path $OutputDirectory 'uosc_danmaku-v2.1.0-wisukia.2-windows.zip'
if (Test-Path -LiteralPath $zipPath) { throw '目标 ZIP 已存在，请选择新的输出目录。' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stagePath, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
$digest = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'), "$digest  $([IO.Path]::GetFileName($zipPath))`n", [Text.UTF8Encoding]::new($false))
Write-Output "已生成：$zipPath"
Write-Output "SHA-256：$digest"
