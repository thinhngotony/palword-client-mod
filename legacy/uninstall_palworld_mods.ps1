# =============================================================
#  Palworld - One-click UNINSTALLER for the mod pack
#  Removes:
#    1. UE4SS loader + runtime  (Pal\Binaries\Win64)
#    2. PalMiniMap + DungeonBossRespawnMapTimer + built-ins
#    3. Better Night Light pak  (Pal\Content\Paks\~mods)
#
#  Optionally restores the files from the latest backup the
#  installer created (PalMods_Backup_<date>), so anything that
#  was there before this mod pack comes back.
#
#  Usage:
#    .\uninstall_palworld_mods.ps1
#    .\uninstall_palworld_mods.ps1 -PalworldPath "D:\Games\Palworld"
#    .\uninstall_palworld_mods.ps1 -SkipRestore -Yes
# =============================================================

[CmdletBinding()]
param(
    [string]$PalworldPath = "",
    [switch]$SkipRestore,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Info  { param([string]$m) Write-Host "    $m" -ForegroundColor Gray }

# -------------------------------------------------------------
# 1. Administrator elevation (needed to delete from Program Files).
# -------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host 'Requesting administrator privileges...' -ForegroundColor Yellow
    $reArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($PalworldPath) { $reArgs += ' -PalworldPath "' + $PalworldPath + '"' }
    if ($SkipRestore)  { $reArgs += ' -SkipRestore' }
    if ($Yes)          { $reArgs += ' -Yes' }
    try {
        Start-Process powershell -Verb RunAs -ArgumentList $reArgs -Wait
    } catch {
        Write-Host 'Could not elevate. Run this script as Administrator manually.' -ForegroundColor Red
        Read-Host 'Press Enter to exit'
        exit 1
    }
    exit 0
}

# -------------------------------------------------------------
# 2. Find the Palworld install path (same logic as the installer).
# -------------------------------------------------------------
function Test-Palworld {
    param([string]$p)
    return $p -and (Test-Path -LiteralPath (Join-Path $p 'Pal\Binaries\Win64\Palworld-Win64-Shipping.exe'))
}

function Find-Palworld {
    param([string]$Preferred)

    if (Test-Palworld $Preferred) { return $Preferred }

    $reg = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1623730',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1623730',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1623730'
    )
    foreach ($k in $reg) {
        if (Test-Path $k) {
            try { $loc = (Get-ItemProperty -Path $k).InstallLocation } catch { $loc = $null }
            if (Test-Palworld $loc) { return $loc }
        }
    }

    $def = Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\Palworld'
    if (Test-Palworld $def) { return $def }

    $roots = @()
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    $roots += (Join-Path $env:ProgramFiles 'Steam')
    $roots += (Join-Path $env:ProgramW6432 'Steam')
    $valve = @(
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKCU:\SOFTWARE\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )
    foreach ($vk in $valve) {
        if (Test-Path $vk) {
            try { $sp = (Get-ItemProperty -Path $vk).SteamPath } catch { $sp = $null }
            if ($sp) { $roots += $sp }
        }
    }
    $roots = @($roots | Where-Object { $_ } | Select-Object -Unique)

    foreach ($r in $roots) {
        $c = Join-Path $r 'steamapps\common\Palworld'
        if (Test-Palworld $c) { return $c }
    }

    $paths = @()
    foreach ($r in $roots) {
        $v = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (Test-Path $v) {
            Get-Content -LiteralPath $v | ForEach-Object {
                if ($_ -match '^\s*"path"\s+"(.+)"\s*$') { $paths += $matches[1] -replace '\\\\', '\' }
            }
        }
    }
    foreach ($pp in ($paths | Select-Object -Unique)) {
        $c = Join-Path $pp 'steamapps\common\Palworld'
        if (Test-Palworld $c) { return $c }
    }
    return $null
}

function Prompt-ForPalworldPath {
    while ($true) {
        Write-Host ''
        Write-Host 'Enter the full path to your Palworld folder' -ForegroundColor Yellow
        Write-Host '  (the folder that contains  Pal\Binaries\Win64\Palworld-Win64-Shipping.exe )' -ForegroundColor Gray
        Write-Host '  Example:  D:\SteamLibrary\steamapps\common\Palworld' -ForegroundColor Gray
        Write-Host '  (press Enter with no text to quit)' -ForegroundColor Gray
        $entry = Read-Host 'Path'
        if (-not $entry) { return $null }
        $entry = $entry.Trim().Trim('"').TrimEnd('\')
        if (Test-Palworld $entry) { return $entry }
        Write-Host "That path does not contain Palworld. Check it and try again." -ForegroundColor Red
    }
}

$game = Find-Palworld -Preferred $PalworldPath
if (-not $game) {
    if (-not $Yes) { $game = Prompt-ForPalworldPath }
    if (-not $game) {
        Write-Host 'Palworld was not found. You can also pass it explicitly with:' -ForegroundColor Red
        Write-Host '    .\uninstall_palworld_mods.ps1 -PalworldPath "C:\...\steamapps\common\Palworld"' -ForegroundColor Gray
        Read-Host 'Press Enter to exit'
        exit 1
    }
}

$win      = Join-Path $game 'Pal\Binaries\Win64'
$ue       = Join-Path $win 'ue4ss'
$dwmapi   = Join-Path $win 'dwmapi.dll'
$modsPaks = Join-Path $game 'Pal\Content\Paks\~mods'

Write-Step "Palworld found at:`n      $game"

# -------------------------------------------------------------
# 3. Make sure the game is not running.
# -------------------------------------------------------------
if (Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
    Write-Host 'Palworld is currently RUNNING. Close it before uninstalling.' -ForegroundColor Red
    Read-Host 'Press Enter once you have closed the game'
    if (Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
        Write-Host 'Still running - aborting.' -ForegroundColor Red
        exit 1
    }
}

# -------------------------------------------------------------
# 4. Find the newest backup for an optional restore.
# -------------------------------------------------------------
$backup = Get-ChildItem -LiteralPath $game -Directory -Filter 'PalMods_Backup_*' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

# -------------------------------------------------------------
# 5. Confirm plan.
# -------------------------------------------------------------
Write-Step 'This will remove:'
Write-Info "  $dwmapi"
Write-Info "  $ue          (whole folder: UE4SS + all mods)"
Write-Info "  $modsPaks"
if ($backup -and -not $SkipRestore) {
    Write-Info "`n  Latest backup available to restore: $($backup.Name)"
}
if (-not $Yes) {
    $r = Read-Host "`nType Y to continue (or N to abort)"
    if ($r -notmatch '^[Yy]') { Write-Host 'Aborted - nothing changed.' -ForegroundColor Yellow; exit 0 }
}

# -------------------------------------------------------------
# 6. Delete the mod files.
# -------------------------------------------------------------
Write-Step 'Removing mod files'
$removed = @()
if (Test-Path -LiteralPath $dwmapi) { Remove-Item -LiteralPath $dwmapi -Force; $removed += 'dwmapi.dll' }
if (Test-Path -LiteralPath $ue)     { Remove-Item -LiteralPath $ue -Recurse -Force; $removed += 'ue4ss' }
if (Test-Path -LiteralPath $modsPaks) { Remove-Item -LiteralPath $modsPaks -Recurse -Force; $removed += '~mods' }
if ($removed.Count -eq 0) {
    Write-Info 'Nothing to remove - the mod pack was not installed.'
} else {
    Write-Info ('Removed: ' + ($removed -join ', '))
}

# -------------------------------------------------------------
# 7. Optional restore from backup.
# -------------------------------------------------------------
$restored = $null
if ($backup -and -not $SkipRestore) {
    if (-not $Yes) {
        $r = Read-Host "`nRestore the pre-mod files from backup `"$($backup.Name)`"? (Y/N)"
    } else {
        $r = 'Y'
    }
    if ($r -match '^[Yy]') {
        Write-Step 'Restoring from backup'
        New-Item -ItemType Directory -Force -Path $win | Out-Null
        if (Test-Path -LiteralPath (Join-Path $backup.FullName 'dwmapi.dll')) {
            Copy-Item -LiteralPath (Join-Path $backup.FullName 'dwmapi.dll') -Destination $win -Force
        }
        if (Test-Path -LiteralPath (Join-Path $backup.FullName 'Mods')) {
            Copy-Item -LiteralPath (Join-Path $backup.FullName 'Mods') -Destination $win -Recurse -Force
        }
        if (Test-Path -LiteralPath (Join-Path $backup.FullName '~mods')) {
            New-Item -ItemType Directory -Force -Path (Join-Path $game 'Pal\Content\Paks') | Out-Null
            Copy-Item -LiteralPath (Join-Path $backup.FullName '~mods') -Destination (Join-Path $game 'Pal\Content\Paks') -Recurse -Force
        }
        $restored = $backup.FullName
    }
}

# -------------------------------------------------------------
# 8. Done.
# -------------------------------------------------------------
Write-Host ''
Write-Host '============================================' -ForegroundColor Green
Write-Host '  UNINSTALL COMPLETE' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green
Write-Host "  Game  : $game"
if ($restored) { Write-Host "  Restored from: $restored" }
elseif ($backup) { Write-Host "  Backup kept at : $($backup.FullName)" }
Write-Host '  Palworld now runs completely unmodded.'
Write-Host ''
Read-Host 'Press Enter to close'
