#!/usr/bin/env pwsh
# =====================================================================
# pwmod.ps1 - Palworld client mod manager CLI
#   Front-end for src/PalModMan.psm1.
#
# Usage: pwmod <command> [args] [switches]
#   help | h                         Show this help
#   list                             List catalog mods + state
#   status <id>                      Detail on one mod
#   install <id> [src] [-f]          Install a mod (src: path | nexus:modId:fileId | workshop:itemId)
#   remove <id>                      Uninstall a mod
#   enable <id> / disable <id>       Toggle a mod in mods.txt
#   doctor                           Health-check the install
#   backup [dir]                     Snapshot loader + installed mods
#   restore [dir]                    Restore a snapshot
#   vendor [path]                    Show/import into the vendor dir
#   workshop                         List Steam Workshop Palworld items
#   set-path <dir>                   Remember the game install folder
#   set-key <key>                    Remember a Nexus Mods API key
#
# Switches: -d (dry run / what-if), -f (force)
# =====================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$cmd = '',
    [Parameter(Position = 1)][string]$arg1 = '',
    [Parameter(Position = 2)][string]$arg2 = '',
    [switch]$f,
    [switch]$d
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\src\PalModMan.psm1'
Import-Module $module -Force

function Show-Help {
    @'
Palworld client mod manager (pwmod)
------------------------------------
list                     List catalog mods with installed/enabled state
status <id>              Detail on one mod
install <id> [src] [-f]  Install a mod. src = path | nexus:<modId>:<fileId> | workshop:<itemId>
remove <id>              Uninstall a mod
enable <id>|disable <id> Toggle a mod on/off in mods.txt
doctor                   Health-check the install setup
backup [dir]             Snapshot loader + installed mods
restore [dir]            Restore a snapshot
vendor [path]            Show vendor dir; "vendor <path>" imports an archive/folder
workshop                 List Steam Workshop Palworld items
set-path <dir>           Remember the game install folder
set-key  <key>           Remember a Nexus API key (for downloads)
help                     This help

Switches: -d (dry run / what-if), -f (force)
Examples:
  pwmod list
  pwmod install palminimap
  pwmod install ue4ss -d
  pwmod set-path "C:\Steam\steamapps\common\Palworld"
  pwmod workshop
'@
    exit 0
}

switch ($cmd.ToLower()) {
    { $_ -in @('', 'help', 'h') } { Show-Help }

    'vendor' {
        if ($arg1) { Import-PalModArchive -Path $arg1 -WhatIf:$d }
        else {
            $v = Get-PalVendorDir
            "Vendor dir: $v"
            Get-ChildItem -LiteralPath $v | Select-Object Name
        }
    }
    'set-path' {
        if (-not $arg1) { throw 'set-path needs a path' }
        Set-PalConfig -PalworldPath $arg1
        "Game path set to: $arg1"
    }
    'set-key' {
        if (-not $arg1) { throw 'set-key needs a key' }
        Set-PalConfig -NexusApiKey $arg1
        "Nexus API key saved."
    }
    'list'     { Get-PalMod | Format-Table Id, Name, Version, Type, Source, Requires, Installed, Enabled -AutoSize }
    'status'   { if (-not $arg1) { throw 'status needs an id' }; Get-PalModStatus -Id $arg1 | Format-List }
    'install'  { if (-not $arg1) { throw 'install needs an id' }; Install-PalMod -Id $arg1 -SourceOverride $arg2 -Force:$f -WhatIf:$d }
    'remove'   { if (-not $arg1) { throw 'remove needs an id' }; Uninstall-PalMod -Id $arg1 -WhatIf:$d }
    'enable'   { if (-not $arg1) { throw 'enable needs an id' }; Enable-PalMod -Id $arg1 -WhatIf:$d }
    'disable'  { if (-not $arg1) { throw 'disable needs an id' }; Disable-PalMod -Id $arg1 -WhatIf:$d }
    'doctor'   { $r = Invoke-PalDoctor; $r | Format-List; if ($r.Healthy) { 'HEALTHY' } else { 'ISSUES FOUND' } }
    'backup'   { Backup-PalMods -WhatIf:$d | Format-List }
    'restore'  { Restore-PalMods -BackupPath $arg1 -WhatIf:$d }
    'workshop' { Invoke-PalWorkshopAction }
    default    { Show-Help }
}