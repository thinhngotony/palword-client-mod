# =====================================================================
# build-dist.ps1 - build a distributable one-click zip for a new client
#   Excludes per-machine state (config.json, catalog/installed.json,
#   *.local.json) and repo cruft so the bundle starts clean on any PC.
#   Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File bin\build-dist.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

$out = Join-Path $root 'dist\palworld-client-mods.zip'

$excludeLeaf = @('config.json', 'installed.json', '.gitignore', 'CHANGELOG.md', 'LICENSE')
$excludeLeafRegex = '\.local\.json$'

function Test-ExcludedPath {
    param([string]$Rel)
    $rel = $Rel.TrimEnd('\')
    if ($rel -match '^\.git($|\\)') { return $true }
    if ($rel -match '^\.github($|\\)') { return $true }
    if ($rel -match '^docs($|\\)') { return $true }
    if ($rel -match '^tests($|\\)') { return $true }
    if ($rel -eq 'dist') { return $true }
    if ($rel -like 'dist\*') { return $true }
    if ($rel -match '^legacy($|\\)') { return $true }
    if ($rel -like '_stage*') { return $true }
    if ($rel -like 'vendor\_stage*') { return $true }
    if ($rel -eq 'vendor\_testsandbox') { return $true }
    if ($rel -like 'vendor\_testsandbox\*') { return $true }
    if ($rel -like '*.log') { return $true }
    $leaf = Split-Path -Leaf $rel
    if ($leaf -in $excludeLeaf) { return $true }
    if ($leaf -match $excludeLeafRegex) { return $true }
    return $false
}

$items = @(Get-ChildItem -Path $root -Recurse -Force | Where-Object {
    $rel = $_.FullName.Substring($root.Length).TrimStart('\')
    -not (Test-ExcludedPath -Rel $rel)
})

if (-not (Test-Path -LiteralPath (Split-Path -Parent $out))) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
}
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($out, [System.IO.Compression.ZipArchiveMode]::Create)

$count = 0
foreach ($f in $items) {
    $rel = $f.FullName.Substring($root.Length).TrimStart('\')
    if ($f.PSIsContainer) {
        $entryName = $rel.TrimEnd('\') + '\'
        $null = $zip.CreateEntry($entryName)
        $count++
    } else {
        $entryName = $rel
        $e = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $estream = $e.Open()
        try {
            $fstream = [System.IO.File]::OpenRead($f.FullName)
            try { $fstream.CopyTo($estream) } finally { $fstream.Dispose() }
        } finally { $estream.Dispose() }
        $count++
    }
}
$zip.Dispose()

$sizeMB = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host "Built $out ($count entries, $sizeMB MB)"