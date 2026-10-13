param([Parameter(Mandatory=$true)][string]$MpvConfigDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$compatDirectory = Join-Path $repoRoot 'compat\uosc-5.13.0'
$targetPath = Join-Path $MpvConfigDirectory 'scripts\uosc\elements\Menu.lua'
$hashes = Get-Content -LiteralPath (Join-Path $compatDirectory 'hashes.json') -Raw | ConvertFrom-Json
function Get-NormalizedHash([string]$FilePath) {
    $content = [IO.File]::ReadAllText($FilePath).Replace("`r`n", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($content)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
$currentHash = Get-NormalizedHash $targetPath
if ($currentHash -eq $hashes.patched) { Write-Output '中文输入兼容补丁已安装。'; return }
if ($currentHash -ne $hashes.original) { throw 'Menu.lua 不是未修改的 uosc 5.13.0，已停止以保护现有改动。请手动合并 native-input.patch。' }
$backupPath = $targetPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff') + '-native-input'
Copy-Item -LiteralPath $targetPath -Destination $backupPath
Copy-Item -LiteralPath (Join-Path $compatDirectory 'Menu.lua') -Destination $targetPath
if ((Get-NormalizedHash $targetPath) -ne $hashes.patched) {
    Copy-Item -LiteralPath $backupPath -Destination $targetPath
    throw '补丁回读失败，已恢复备份。'
}
Write-Output "补丁已安装。备份：$backupPath"
