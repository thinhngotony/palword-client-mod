# =============================================================
#  Palworld - One-click client mod installer (UE4SS + mods)
#  Installs:
#    1. UE4SS loader + runtime (RE-UE4SS "3035 260719" 3.0.5)
#    2. PalMiniMap                    (Lua / UE4SS)
#    3. DungeonBossRespawnMapTimer    (Lua / UE4SS)
#    4. Better Night Light            (pak mod)
#
#  Usage:
#    .\install_palworld_mods.ps1                     # auto-detects path
#    .\install_palworld_mods.ps1 -PalworldPath "D:\Games\Palworld"
#    .\install_palworld_mods.ps1 -SkipBackup -Yes    # no prompts/backup
#
#  The payload sits in the "payload" folder beside this script.
# =============================================================

[CmdletBinding()]
param(
    [string]$PalworldPath = "",
    [switch]$SkipBackup,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$payload = Join-Path $PSScriptRoot 'payload'

function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Info  { param([string]$m) Write-Host "    $m" -ForegroundColor Gray }

# -------------------------------------------------------------
# 1. Make sure we are running as Administrator (needed to write
#    into Program Files).
# -------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host 'Requesting administrator privileges...' -ForegroundColor Yellow
    $reArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($PalworldPath) { $reArgs += ' -PalworldPath "' + $PalworldPath + '"' }
    if ($SkipBackup)   { $reArgs += ' -SkipBackup' }
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
# 2. Sanity checks on the bundled payload.
# -------------------------------------------------------------
$need = @(
    (Join-Path $payload 'Win64\dwmapi.dll'),
    (Join-Path $payload 'Win64\ue4ss\UE4SS.dll'),
    (Join-Path $payload 'Paks\BNLrelease_P.pak')
)
foreach ($n in $need) {
    if (-not (Test-Path -LiteralPath $n)) {
        Write-Host "Missing bundled file: $n" -ForegroundColor Red
        Read-Host 'Press Enter to exit'
        exit 1
    }
}

# -------------------------------------------------------------
# 3. Find the Palworld install path.
# -------------------------------------------------------------
function Test-Palworld {
    param([string]$p)
    return $p -and (Test-Path -LiteralPath (Join-Path $p 'Pal\Binaries\Win64\Palworld-Win64-Shipping.exe'))
}

function Find-Palworld {
    param([string]$Preferred)

    if (Test-Palworld $Preferred) { return $Preferred }

    # Steam uninstall registry entries for app 1623730 (Palworld)
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

    # Candidates for the Steam installation folder itself
    $roots = @()
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    $roots += (Join-Path $env:ProgramFiles 'Steam')
    $roots += (Join-Path $env:ProgramW6432 'Steam')

    # Steam's own install path, as recorded by Steam in the registry.
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

    # Direct check in each Steam root.
    foreach ($r in $roots) {
        $c = Join-Path $r 'steamapps\common\Palworld'
        if (Test-Palworld $c) { return $c }
    }

    # Scan every Steam library via libraryfolders.vdf.
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

# Ask the user to type a path, retrying until it is valid (or blank = quit).
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
        Write-Host '    .\install_palworld_mods.ps1 -PalworldPath "C:\...\steamapps\common\Palworld"' -ForegroundColor Gray
        Read-Host 'Press Enter to exit'
        exit 1
    }
}

$win  = Join-Path $game 'Pal\Binaries\Win64'
$ue   = Join-Path $win 'ue4ss'
$mods = Join-Path $ue 'Mods'
$paks = Join-Path $game 'Pal\Content\Paks'
$modsPaks = Join-Path $paks '~mods'

Write-Step "Palworld found at:`n      $game"

# -------------------------------------------------------------
# 4. Make sure the game is not running.
# -------------------------------------------------------------
if (Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
    Write-Host 'Palworld is currently RUNNING. Close it before installing.' -ForegroundColor Red
    Read-Host 'Press Enter once you have closed the game'
    if (Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
        Write-Host 'Still running - aborting.' -ForegroundColor Red
        exit 1
    }
}

# -------------------------------------------------------------
# 5. Confirm plan.
# -------------------------------------------------------------
Write-Step 'This will install / update:'
Write-Info '  UE4SS loader  ->  Pal\Binaries\Win64'
Write-Info '  PalMiniMap     ->  ue4ss\Mods'
Write-Info '  DungeonBoss... ->  ue4ss\Mods'
Write-Info '  Better N.Light ->  Pal\Content\Paks\~mods'
Write-Info '  mods.txt       ->  enables the mods'
if (-not $Yes) {
    $r = Read-Host "`nType Y to continue (or N to abort)"
    if ($r -notmatch '^[Yy]') { Write-Host 'Aborted - nothing changed.' -ForegroundColor Yellow; exit 0 }
}

# -------------------------------------------------------------
# 6. Back up anything we are about to touch.
# -------------------------------------------------------------
$backedUp = $null
if (-not $SkipBackup) {
    $backedUp = Join-Path $game ("PalMods_Backup_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Force -Path $backedUp | Out-Null
    if (Test-Path -LiteralPath (Join-Path $win 'dwmapi.dll'))   { Copy-Item -LiteralPath (Join-Path $win 'dwmapi.dll') -Destination $backedUp }
    if (Test-Path -LiteralPath $mods)   { Copy-Item -LiteralPath $mods -Destination $backedUp -Recurse -Force }
    if (Test-Path -LiteralPath $modsPaks) { Copy-Item -LiteralPath $modsPaks -Destination $backedUp -Recurse -Force }
    Write-Info "Backup saved: $backedUp"
}

# -------------------------------------------------------------
# 7. Install UE4SS loader + runtime.
# -------------------------------------------------------------
Write-Step 'Installing UE4SS loader + runtime'
New-Item -ItemType Directory -Force -Path $ue | Out-Null
Copy-Item -LiteralPath (Join-Path $payload 'Win64\dwmapi.dll') -Destination $win -Force
Copy-Item -LiteralPath (Join-Path $payload 'Win64\ue4ss\UE4SS.dll') -Destination $ue -Force
Copy-Item -LiteralPath (Join-Path $payload 'Win64\ue4ss\MemberVariableLayout.ini') -Destination $ue -Force
if (-not (Test-Path -LiteralPath (Join-Path $ue 'UE4SS-settings.ini'))) {
    Copy-Item -LiteralPath (Join-Path $payload 'Win64\ue4ss\UE4SS-settings.ini') -Destination $ue -Force
    Write-Info 'UE4SS-settings.ini created (defaults)'
} else {
    Write-Info 'Kept existing UE4SS-settings.ini'
}
Copy-Item -LiteralPath (Join-Path $payload 'Win64\ue4ss\LICENSE') -Destination $ue -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------
# 8. Copy the full Mods tree (built-ins + the two Lua mods).
# -------------------------------------------------------------
Write-Step 'Installing mods (PalMiniMap, DungeonBossRespawnMapTimer)'
New-Item -ItemType Directory -Force -Path $mods | Out-Null
Copy-Item -LiteralPath (Join-Path $payload 'Win64\ue4ss\Mods') -Destination $ue -Recurse -Force

# -------------------------------------------------------------
# 9. (Re)write the controlling load list mods.txt.
#    We merge: keep any user mods, but enforce ours = enabled.
# -------------------------------------------------------------
Write-Step 'Writing mods.txt (enabling the mods)'
$promote = @('PalMiniMap', 'DungeonBossRespawnMapTimer', 'BPML_GenericFunctions', 'BPModLoaderMod')
$modsTxt = Join-Path $mods 'mods.txt'

if (Test-Path -LiteralPath $modsTxt) {
    $lines = Get-Content -LiteralPath $modsTxt
    foreach ($name in $promote) {
        $hit = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match ("^\s*" + [regex]::Escape($name) + "\s*:")) {
                $lines[$i] = $name + ' : 1'
                $hit = $true
            }
        }
        if (-not $hit) { $lines += ($name + ' : 1') }
    }
    Set-Content -LiteralPath $modsTxt -Value $lines -Encoding UTF8
} else {
    $txt = @(
        'CheatManagerEnablerMod : 0',
        'ConsoleCommandsMod : 0',
        'ConsoleEnablerMod : 0',
        'SplitScreenMod : 0',
        'LineTraceMod : 0',
        'BPML_GenericFunctions : 1',
        'BPModLoaderMod : 1',
        'PalMiniMap : 1',
        'DungeonBossRespawnMapTimer : 1',
        '; Only Built-In UE4SS Mods above this line.',
        '',
        '; Built-in keybinds, do not move up!',
        'Keybinds : 1'
    )
    Set-Content -LiteralPath $modsTxt -Value $txt -Encoding UTF8
}
Write-Info 'PalMiniMap and DungeonBossRespawnMapTimer are now enabled.'

# -------------------------------------------------------------
# 10. Better Night Light pak mod.
# -------------------------------------------------------------
Write-Step 'Installing Better Night Light (pak)'
New-Item -ItemType Directory -Force -Path $modsPaks | Out-Null
Copy-Item -LiteralPath (Join-Path $payload 'Paks\BNLrelease_P.pak') -Destination $modsPaks -Force

# -------------------------------------------------------------
# 11. Done.
# -------------------------------------------------------------
Write-Host ''
Write-Host '============================================' -ForegroundColor Green
Write-Host '  INSTALLATION COMPLETE' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green
Write-Host "  Game  : $game"
if ($backedUp) { Write-Host "  Backup: $backedUp" }
Write-Host ''
Write-Host '  Next steps:'
Write-Host '   1. Launch Palworld (UE4SS console appearing is normal).'
Write-Host '   2. PalMiniMap:  F5 settings / F4 move&resize / F2 corner / F3 show-hide'
Write-Host '   3. DungeonBoss timer shows a countdown on a fixed-dungeon'
Write-Host '      boss icon while it respawns.'
Write-Host '   4. Better Night Light= brighter nights automatically.'
Write-Host ''
Read-Host 'Press Enter to close'