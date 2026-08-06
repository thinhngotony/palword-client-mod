# =====================================================================
# PalModMan.psm1 - Palworld client mod manager (manifest-driven)
#
# Catalog-driven install/remove/enable/disable plus source adapters:
#   local file, archive, folder, Nexus Mods API, Steam Workshop.
#
# Layout under the game root:
#   Pal\Binaries\Win64\dwmapi.dll        (UE4SS loader proxy)
#   Pal\Binaries\Win64\ue4ss\            (UE4SS runtime + mods)
#   Pal\Binaries\Win64\ue4ss\Mods\       (built-ins + Lua mods)
#   Pal\Binaries\Win64\ue4ss\Mods\mods.txt (load list)
#   Pal\Content\Paks\~mods\              (pak mods)
# =====================================================================

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# --- paths -----------------------------------------------------------
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:CatalogFile = Join-Path $script:RepoRoot 'catalog\mods.json'
$script:InstalledFile = Join-Path $script:RepoRoot 'catalog\installed.json'
$script:ConfigFile = Join-Path $script:RepoRoot 'config.json'
$script:DefaultVendor = Join-Path $script:RepoRoot 'vendor'
$script:AppId = 1623730

function Get-AppIdForLayout { return $script:AppId }

# --- tiny json helpers ------------------------------------------------
function Read-JsonData {
    param([string]$Path, [object]$Default = @{})
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $Default }
    try {
        $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($null -eq $obj) { return $Default }
        return $obj
    } catch { return $Default }
}

function Write-JsonData {
    param([string]$Path, [object]$Data)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Data | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

# --- configuration ---------------------------------------------------
function Get-PalConfig {
    $file = $script:ConfigFile
    $cfg = if (Test-Path -LiteralPath $file) {
        try { Get-Content -LiteralPath $file -Raw | ConvertFrom-Json } catch { [pscustomobject]@{} }
    } else { [pscustomobject]@{} }
    if ($null -eq $cfg) { $cfg = [pscustomobject]@{} }
    $have = @($cfg.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($prop in @('palworldPath', 'nexusApiKey', 'vendorDir')) {
        if (-not ($have -contains $prop)) {
            $cfg | Add-Member -NotePropertyName $prop -NotePropertyValue '' -Force
            $have += $prop
        }
    }
    return $cfg
}

function Set-PalConfig {
    param(
        [string]$PalworldPath = '',
        [string]$NexusApiKey = '',
        [string]$VendorDir = ''
    )
    $c = Get-PalConfig
    if ($PalworldPath) { $c.palworldPath = $PalworldPath }
    if ($NexusApiKey)  { $c.nexusApiKey = $NexusApiKey }
    if ($VendorDir)    { $c.vendorDir = $VendorDir }
    Write-JsonData -Path $script:ConfigFile -Data $c
}

function Get-PalVendorDir {
    $cfg = Get-PalConfig
    if ($cfg.vendorDir -and (Test-Path -LiteralPath $cfg.vendorDir)) { return $cfg.vendorDir }
    if (-not (Test-Path -LiteralPath $script:DefaultVendor)) { New-Item -ItemType Directory -Force -Path $script:DefaultVendor | Out-Null }
    return $script:DefaultVendor
}

# --- game detection ----------------------------------------------------
function Test-PalworldPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'Pal\Binaries\Win64\Palworld-Win64-Shipping.exe'))
}

function Get-SteamRoots {
    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(
        (Join-Path ${env:ProgramFiles(x86)} 'Steam'),
        (Join-Path $env:ProgramFiles 'Steam'),
        (Join-Path $env:ProgramW6432 'Steam')
    )) { if ($p) { $roots.Add($p) } }
    foreach ($vk in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKCU:\SOFTWARE\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        if (Test-Path -LiteralPath $vk) {
            try { $sp = (Get-ItemProperty -Path $vk -ErrorAction SilentlyContinue).SteamPath } catch { $sp = $null }
            if ($sp) { $roots.Add([string]$sp) }
        }
    }
    return @($roots | Sort-Object -Unique)
}

function Get-PalworldPath {
    param([string]$Preferred = '')
    $cfg = Get-PalConfig
    foreach ($cand in @($cfg.palworldPath, $Preferred)) {
        if (Test-PalworldPath $cand) { return $cand }
    }
    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1623730',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1623730',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1623730'
    )) {
        if (Test-Path -LiteralPath $key) {
            try { $loc = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).InstallLocation } catch { $loc = $null }
            if (Test-PalworldPath $loc) { return $loc }
        }
    }
    foreach ($root in Get-SteamRoots) {
        $c = Join-Path $root 'steamapps\common\Palworld'
        if (Test-PalworldPath $c) { return $c }
        $v = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $v) {
            Get-Content -LiteralPath $v | ForEach-Object {
                if ($_ -match '^\s*"path"\s+"(.+)"\s*$') {
                    $lib = Join-Path ($matches[1] -replace '\\\\', '\') 'steamapps\common\Palworld'
                    if (Test-PalworldPath $lib) { return $lib }
                }
            }
        }
    }
    return $null
}

function Get-PalworldLayout {
    param([string]$GamePath = (Get-PalworldPath))
    if (-not $GamePath) { throw 'Palworld not found. Use "pwmod set-path <folder>" or -Path <folder>.' }
    $win = Join-Path $GamePath 'Pal\Binaries\Win64'
    $ue  = Join-Path $win 'ue4ss'
    $mods = Join-Path $ue 'Mods'
    $paksMods = Join-Path $GamePath 'Pal\Content\Paks\~mods'
    return [pscustomobject]@{
        GamePath = $GamePath
        Win64 = $win
        Ue4ss = $ue
        ModsDir = $mods
        Ue4ssModsTxt = Join-Path $mods 'mods.txt'
        Paks = Join-Path $GamePath 'Pal\Content\Paks'
        PaksMods = $paksMods
        ServerMods = Join-Path $GamePath 'Mods'
        ServerModsWorkshop = Join-Path $GamePath 'Mods\Workshop'
        ServerPalModSettings = Join-Path $GamePath 'Mods\PalModSettings.ini'
    }
}

# --- mods.txt management ---------------------------------------------
function Get-ModsTxt {
    param($Layout)
    if (Test-Path -LiteralPath $Layout.Ue4ssModsTxt) {
        return @(Get-Content -LiteralPath $Layout.Ue4ssModsTxt)
    }
    return @()
}

function Write-ModsTxt {
    param($Layout, [string[]]$Lines)
    if (-not (Test-Path -LiteralPath $Layout.ModsDir)) { New-Item -ItemType Directory -Force -Path $Layout.ModsDir | Out-Null }
    $Lines | Set-Content -LiteralPath $Layout.Ue4ssModsTxt -Encoding UTF8
}

function Set-ModsTxtEntries {
    # Ensures each mod name is present with the given on/off state, merging
    # with any existing lines. This build of UE4SS treats mods.txt as the
    # controlling load list.
    param(
        $Layout,
        [string[]]$Names,
        [bool]$Enabled,
        [switch]$Remove
    )
    $lines = @(Get-ModsTxt -Layout $Layout)
    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $pattern = '^\s*' + [regex]::Escape($name) + '\s*:'
        $found = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $pattern) {
                if ($Remove) { $lines[$i] = '' }
                else { $lines[$i] = "$name : $(if ($Enabled) { '1' } else { '0' })" }
                $found = $true
            }
        }
        if (-not $found -and -not $Remove) { $lines += "$name : $(if ($Enabled) { '1' } else { '0' })" }
    }
    if ($Remove) { $lines = @($lines | Where-Object { $_ -and $_ -notmatch '^\s*$' }) }
    Write-ModsTxt -Layout $Layout -Lines $lines
}

function Get-ModsTxtState {
    # Returns name -> enabled hashtable from mods.txt.
    param($Layout)
    $state = @{}
    foreach ($line in @(Get-ModsTxt -Layout $Layout)) {
        if ($line -match '^\s*([^:\s][^:]*?)\s*:\s*(\d)\s*$') {
            $state[$matches[1].Trim()] = ($matches[2] -eq '1')
        }
    }
    return $state
}

# --- catalog ----------------------------------------------------------
function Get-PalLocalOverlay {
    # Parse a local catalog overlay file that may be a bare array, a {mods:[...]}
    # object, or a single mod entry. Returns a list of mod entries.
    param([string]$Path)
    $o = Read-JsonData -Path $Path -Default @()
    if ($o -is [System.Array]) { return @($o) }
    if ($o.PSObject.Properties['mods']) { return @($o.mods) }
    if ($o.id) { return @($o) }
    return @()
}

function Get-PalCatalog {
    # Base catalog (catalog/mods.json) merged with any local overlays
    # (catalog/*.local.json). Local entries override base entries by id.
    $cat = Read-JsonData -Path $script:CatalogFile -Default @{ mods = @() }
    $mods = if ($cat -is [System.Array]) { @($cat) }
            elseif ($cat.PSObject.Properties['mods']) { @($cat.mods) }
            else { @() }
    foreach ($f in @(Get-ChildItem -LiteralPath (Split-Path -Parent $script:CatalogFile) -Filter '*.local.json' -File -ErrorAction SilentlyContinue)) {
        foreach ($lm in @(Get-PalLocalOverlay -Path $f.FullName)) {
            if ($lm.id) { $mods = @($mods | Where-Object { $_.id -ne $lm.id }) + @($lm) }
        }
    }
    return $mods
}

function Get-PalCatalogMod {
    param([string]$Id)
    foreach ($m in @(Get-PalCatalog)) {
        if ($m.id -eq $Id) { return $m }
    }
    return $null
}

# --- installed-state manifest ----------------------------------------
function Get-InstalledManifest {
    $m = Read-JsonData -Path $script:InstalledFile -Default @{}
    if ($m -is [System.Collections.Hashtable] -or $m -is [pscustomobject]) { return $m }
    return @{}
}

function Add-InstalledManifestEntry {
    param([string]$Id, [string[]]$Files)
    $m = @{}
    if (Test-Path -LiteralPath $script:InstalledFile) {
        $existing = Read-JsonData -Path $script:InstalledFile -Default @{}
        foreach ($p in $existing.PSObject.Properties) { $m[$p.Name] = $p.Value }
    }
    $m[$Id] = @{ version = ''; files = @($Files) }
    Write-JsonData -Path $script:InstalledFile -Data $m
}

function Remove-InstalledManifestEntry {
    param([string]$Id)
    $m = @{}
    if (Test-Path -LiteralPath $script:InstalledFile) {
        $existing = Read-JsonData -Path $script:InstalledFile -Default @{}
        foreach ($p in $existing.PSObject.Properties) {
            if ($p.Name -ne $Id) { $m[$p.Name] = $p.Value }
        }
    }
    Write-JsonData -Path $script:InstalledFile -Data $m
}

# --- filesystem helpers ------------------------------------------------
function Copy-PalTree {
    # Merge-tree copy: files land in Destination as files; a source folder's
    # contents are merged INTO the destination folder (safe when it exists).
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Destination)) { New-Item -ItemType Directory -Force -Path $Destination | Out-Null }
    $src = Get-Item -LiteralPath $Source
    if (-not $src.PSIsContainer) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return
    }
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

function Expand-PalArchive {
    param([string]$Archive, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Destination)) { New-Item -ItemType Directory -Force -Path $Destination | Out-Null }
    try {
        Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force -ErrorAction Stop
    } catch {
        # Fallback for exotic archives via .NET
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
    }
}

# --- mod lifecycle ----------------------------------------------------
function Get-PalMod {
    # List all mods known to the catalog, with installed/enabled state.
    $layout = Get-PalworldLayout
    $state = Get-ModsTxtState -Layout $layout
    $manifest = Get-InstalledManifest
    foreach ($m in @(Get-PalCatalog)) {
        $primary = @($m.loadOrder)[0]
        [pscustomobject]@{
            Id = $m.id
            Name = $m.name
            Version = $m.version
            Type = $m.type
            Side = $m.side
            Source = $m.source.kind
            Requires = @($m.requires) -join ', '
            Installed = ($null -ne $manifest.PSObject.Properties[$m.id])
            Enabled = if ($primary) { if ($state.ContainsKey($primary)) { $state[$primary] } else { $false } } else { $null }
        }
    }
}

function Get-PalModStatus {
    # Diagnostics summary of a single mod.
    param([string]$Id)
    $m = Get-PalCatalogMod -Id $Id
    if (-not $m) { throw "Unknown mod id '$Id'. See 'pwmod list'." }
    $layout = Get-PalworldLayout
    $state = Get-ModsTxtState -Layout $layout
    $primary = @($m.loadOrder)[0]
    $installed = Get-InstalledManifest
    $hasManifest = ($null -ne $installed.PSObject.Properties[$m.id])
    [pscustomobject]@{
        Id = $m.id
        Name = $m.name
        Version = $m.version
        Type = $m.type
        Source = $m.source.kind
        Requires = @($m.requires) -join ', '
        Installed = $hasManifest
        DeployedFiles = if ($hasManifest) { @($installed.$($m.id).files).Count } else { 0 }
        LoadOrder = $primary
        EnabledInModsTxt = if ($primary) { if ($state.ContainsKey($primary)) { $state[$primary] } else { $null } } else { $null }
    }
}

function Install-PalMod {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$SourceOverride = '',   # path to a local file/zip/folder, or nexus:<id>:<fileId>, or workshop:<id>
        [switch]$Force,
        [switch]$WhatIf
    )
    $m = Get-PalCatalogMod -Id $Id
    if (-not $m) { throw "Unknown mod id '$Id'. See 'pwmod list'." }
    $layout = Get-PalworldLayout

    # Resolve a local source for the mod's payload.
    $localFiles = Resolve-ModSource -Mod $m -SourceOverride $SourceOverride
    if (-not $localFiles -and -not $WhatIf) { throw "No source files for '$Id'. Drop the archive in $(Get-PalVendorDir) or pass -SourceOverride." }

    $actions = @()
    switch ($m.type) {
        'ue4ss-loader' {
            # Copy loader + ue4ss runtime into Win64.
            $actions += "copy loader/runtime -> $($layout.Win64) / $($layout.Ue4ss)"
            if (-not $WhatIf) {
                foreach ($f in $localFiles) {
                    if ($f.PSIsContainer) {
                        foreach ($child in @(Get-ChildItem -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue)) {
                            $dest = $layout.Win64
                            if ($child.Name -eq 'ue4ss') { $dest = $layout.Ue4ss }
                            Copy-PalTree -Source $child.FullName -Destination $dest
                        }
                    } else {
                        Copy-PalTree -Source $f.FullName -Destination $layout.Win64
                    }
                }
            }
        }
        'ue4ss-lua' {
            # Deploy a Lua mod into ue4ss\Mods\<loadOrder name>.
            $dirName = if (@($m.loadOrder)[0]) { @($m.loadOrder)[0] } else { $m.id }
            $destRoot = Join-Path $layout.ModsDir $dirName
            $actions += "copy Lua mod -> $destRoot"
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
                foreach ($f in $localFiles) {
                    Copy-PalTree -Source $f.FullName -Destination $destRoot
                }
            }
        }
        'pak' {
            $actions += "copy pak -> $($layout.PaksMods)"
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Force -Path $layout.PaksMods | Out-Null
                foreach ($f in $localFiles) {
                    if ($f.PSIsContainer) {
                        foreach ($c in @(Get-ChildItem -LiteralPath $f.FullName -File -Filter *.pak -ErrorAction SilentlyContinue)) {
                            Copy-Item -LiteralPath $c.FullName -Destination $layout.PaksMods -Force
                        }
                    } else {
                        Copy-Item -LiteralPath $f.FullName -Destination $layout.PaksMods -Force
                    }
                }
            }
        }
        'config' {
            # Placeholder: config-type mods edit game config; see docs.
            throw "Type 'config' is not implemented yet for '$Id'."
        }
        default {
            throw "Unsupported mod type '$($m.type)' for '$Id'."
        }
    }

    if (-not $WhatIf) {
        Set-ModsTxtEntries -Layout $layout -Names @($m.loadOrder) -Enabled $true
        Add-InstalledManifestEntry -Id $Id -Files @($localFiles | ForEach-Object { $_.FullName })
        Write-Host "Installed '$Id'."
    } else {
        $actions
    }
}

function Uninstall-PalMod {
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$WhatIf
    )
    $m = Get-PalCatalogMod -Id $Id
    if (-not $m) { throw "Unknown mod id '$Id'." }
    $layout = Get-PalworldLayout
    $manifest = Get-InstalledManifest

    switch ($m.type) {
        'ue4ss-lua' {
            $dirName = if (@($m.loadOrder)[0]) { @($m.loadOrder)[0] } else { $m.id }
            $dest = Join-Path $layout.ModsDir $dirName
            if (-not $WhatIf) {
                if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
                Remove-InstalledManifestEntry -Id $Id
            }
            Write-Host "Removed '$Id' (ue4ss-lua)."
        }
        'pak' {
            # Remove paks we recorded as installed.
            if (-not $WhatIf) {
                $entry = $manifest.PSObject.Properties[$Id]
                if ($entry) {
                    foreach ($leaf in @($entry.Value.files | ForEach-Object { Split-Path -Leaf $_ })) {
                        $p = Join-Path $layout.PaksMods $leaf
                        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
                    }
                }
                Remove-InstalledManifestEntry -Id $Id
            }
            Write-Host "Removed '$Id' (pak)."
        }
        'ue4ss-loader' {
            # Remove only the loader proxy; leave the runtime+mods intact.
            if (-not $WhatIf) {
                $dwm = Join-Path $layout.Win64 'dwmapi.dll'
                if (Test-Path -LiteralPath $dwm) { Remove-Item -LiteralPath $dwm -Force }
                Remove-InstalledManifestEntry -Id $Id
            }
            Write-Host "Removed '$Id' (loader)."
        }
        default {
            throw "Unsupported mod type '$($m.type)' for '$Id'."
        }
    }
    if (-not $WhatIf) {
        Set-ModsTxtEntries -Layout $layout -Names @($m.loadOrder) -Remove
    }
}

function Enable-PalMod {
    param([Parameter(Mandatory)][string]$Id, [switch]$WhatIf)
    $m = Get-PalCatalogMod -Id $Id
    if (-not $m) { throw "Unknown mod id '$Id'." }
    $layout = Get-PalworldLayout
    if (-not $WhatIf) { Set-ModsTxtEntries -Layout $layout -Names @($m.loadOrder) -Enabled $true }
    Write-Host "Enabled '$Id'."
}

function Disable-PalMod {
    param([Parameter(Mandatory)][string]$Id, [switch]$WhatIf)
    $m = Get-PalCatalogMod -Id $Id
    if (-not $m) { throw "Unknown mod id '$Id'." }
    $layout = Get-PalworldLayout
    if (-not $WhatIf) { Set-ModsTxtEntries -Layout $layout -Names @($m.loadOrder) -Enabled $false }
    Write-Host "Disabled '$Id'."
}

# --- backup / restore --------------------------------------------------
function Backup-PalMods {
    param([switch]$WhatIf)
    $layout = Get-PalworldLayout
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dest = Join-Path $layout.GamePath "PalMods_Backup_$stamp"
    $items = @()
    foreach ($p in @((Join-Path $layout.Win64 'dwmapi.dll'), $layout.Ue4ss, $layout.PaksMods)) {
        if (Test-Path -LiteralPath $p) { $items += $p }
    }
    if (-not $WhatIf) {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($p in $items) { Copy-Item -LiteralPath $p -Destination $dest -Recurse -Force }
    }
    [pscustomobject]@{ BackupPath = $dest; Items = @($items | ForEach-Object { Split-Path -Leaf $_ }) }
}

function Restore-PalMods {
    param([string]$BackupPath = '', [switch]$WhatIf)
    $layout = Get-PalworldLayout
    if (-not $BackupPath) {
        $b = @(Get-ChildItem -LiteralPath $layout.GamePath -Directory -Filter 'PalMods_Backup_*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if (-not $b) { throw 'No backup folder found under the game directory.' }
        $BackupPath = $b[0].FullName
    }
    if (-not $WhatIf) {
        if (Test-Path -LiteralPath (Join-Path $BackupPath 'dwmapi.dll')) { Copy-Item -LiteralPath (Join-Path $BackupPath 'dwmapi.dll') -Destination $layout.Win64 -Force }
        if (Test-Path -LiteralPath (Join-Path $BackupPath 'ue4ss')) { Copy-PalTree -Source (Join-Path $BackupPath 'ue4ss') -Destination $layout.Win64 }
        if (Test-Path -LiteralPath (Join-Path $BackupPath '~mods')) { Copy-PalTree -Source (Join-Path $BackupPath '~mods') -Destination $layout.Paks }
    }
    Write-Host "Restored from $BackupPath"
}

# --- doctor ------------------------------------------------------------
function Invoke-PalDoctor {
    $layout = Get-PalworldLayout
    $issues = [System.Collections.Generic.List[string]]::new()
    $ok = [System.Collections.Generic.List[string]]::new()

    if (Test-Path -LiteralPath (Join-Path $layout.Win64 'dwmapi.dll')) { $ok.Add('UE4SS loader present (dwmapi.dll)') }
    else { $issues.Add('UE4SS loader missing (dwmapi.dll). Run "pwmod install ue4ss".') }

    if (Test-Path -LiteralPath (Join-Path $layout.Ue4ss 'UE4SS.dll')) { $ok.Add('UE4SS runtime present') }
    else { $issues.Add('UE4SS runtime missing. Run "pwmod install ue4ss".') }

    if (Test-Path -LiteralPath $layout.Ue4ssModsTxt) { $ok.Add('mods.txt exists') }
    else { $issues.Add('mods.txt missing - no mods are loadable.') }

    # Duplicate UE4SS hazard with Workshop-delivered core.
    $dup = Test-PalDuplicateUe4ss -Layout $layout
    if ($dup) { $issues.Add($dup) }

    # Verify installed catalog mods are intact.
    $manifest = Get-InstalledManifest
    foreach ($prop in $manifest.PSObject.Properties) {
        $m = Get-PalCatalogMod -Id $prop.Name
        if ($m) {
            $missing = @()
            switch ($m.type) {
                'ue4ss-lua' {
                    $dirName = if (@($m.loadOrder)[0]) { @($m.loadOrder)[0] } else { $m.id }
                    $d = Join-Path $layout.ModsDir $dirName
                    if (-not (Test-Path -LiteralPath $d)) { $missing += $d }
                }
                'pak' {
                    foreach ($leaf in @($prop.Value.files | ForEach-Object { Split-Path -Leaf $_ })) {
                        if (-not (Test-Path -LiteralPath (Join-Path $layout.PaksMods $leaf))) { $missing += $leaf }
                    }
                }
            }
            if ($missing) { $issues.Add("Mod '$($prop.Name)' is missing deployed files: $($missing -join ', ')") }
            else { $ok.Add("Mod '$($prop.Name)' deployed files intact") }
        }
    }

    return [pscustomobject]@{
        GamePath = $layout.GamePath
        Ok = @($ok)
        Issues = @($issues)
        Healthy = ($issues.Count -eq 0)
    }
}

# --- source adapters --------------------------------------------------
function Expand-SingleSource {
    # Normalise a local file/folder into deployable items (expands archives once).
    param([string]$Path, [string]$TempBase)
    $item = Get-Item -LiteralPath $Path
    if (-not $item.PSIsContainer) {
        if ($item.Extension -eq '.zip' -or $item.Extension -eq '.7z') {
            $stage = Join-Path $TempBase (Split-Path -Leaf $item.BaseName)
            if (-not (Test-Path -LiteralPath $stage)) { New-Item -ItemType Directory -Force -Path $stage | Out-Null }
            Expand-PalArchive -Archive $item.FullName -Destination $stage
            $top = @(Get-ChildItem -LiteralPath $stage -Force)
            if ($top.Count -eq 1) { return @($top[0]) }
            return @($top)
        }
        return @($item)
    }
    return @($item)
}

function Resolve-ModSource {
    # Returns an array of filesystem items (FileInfo/DirectoryInfo) that make
    # up a mod's payload, or $null if none is available.
    param($Mod, [string]$SourceOverride = '')
    $vendor = Get-PalVendorDir
    $tmpBase = Join-Path $vendor '_stage'

    if ($SourceOverride) {
        if ($SourceOverride -notmatch '^(nexus|workshop):' -and (Test-Path -LiteralPath $SourceOverride)) {
            return @(Expand-SingleSource -Path (Resolve-Path -LiteralPath $SourceOverride).Path -TempBase $tmpBase)
        }
        if ($SourceOverride -match '^nexus:(\d+):(\d+)$') {
            $out = Join-Path $vendor "nexus_$($matches[1])_$($matches[2]).zip"
            Download-Nexus -NexusModId $matches[1] -NexusFileId $matches[2] -OutFile $out
            return @(Expand-SingleSource -Path $out -TempBase $tmpBase)
        }
        if ($SourceOverride -match '^workshop:(\d+)$') {
            $dir = Get-PalWorkshopModDir -ItemId $matches[1]
            if ($dir) { return @(Get-Item -LiteralPath $dir) }
            return $null
        }
        throw "Unrecognised source override '$SourceOverride'."
    }

    switch ($Mod.source.kind) {
        'file' {
            $p = Join-Path $vendor $Mod.source.file
            if (Test-Path -LiteralPath $p) { return @(Expand-SingleSource -Path $p -TempBase $tmpBase) }
        }
        'folder' {
            $p = Join-Path $vendor $Mod.source.file
            if (Test-Path -LiteralPath $p) { return @(Get-Item -LiteralPath $p) }
        }
        'nexus' {
            if ($Mod.source.file) {
                $p = Join-Path $vendor $Mod.source.file
                if (Test-Path -LiteralPath $p) { return @(Expand-SingleSource -Path $p -TempBase $tmpBase) }
            }
            if ($Mod.source.nexusModId -and $Mod.source.nexusFileId) {
                $out = Join-Path $vendor "nexus_$($Mod.source.nexusModId)_$($Mod.source.nexusFileId).zip"
                if (-not (Test-Path -LiteralPath $out)) { Download-Nexus -NexusModId $Mod.source.nexusModId -NexusFileId $Mod.source.nexusFileId -OutFile $out }
                return @(Expand-SingleSource -Path $out -TempBase $tmpBase)
            }
        }
        'workshop' {
            $dir = Get-PalWorkshopModDir -ItemId $Mod.source.workshopId
            if ($dir) { return @(Get-Item -LiteralPath $dir) }
        }
    }
    return $null
}

function Download-Nexus {
    # Downloads a specific Nexus <modid>:<fileid> via the Nexus v1 API.
    # Requires the user's Nexus API key in config. Result is written to OutFile.
    param(
        [Parameter(Mandatory)][string]$NexusModId,
        [Parameter(Mandatory)][string]$NexusFileId,
        [Parameter(Mandatory)][string]$OutFile
    )
    $cfg = Get-PalConfig
    if (-not $cfg.nexusApiKey) {
        throw 'No Nexus API key configured. Get one (Nexus mods API) and run: pwmod set nexus-api-key <key>'
    }
    $headers = @{ apikey = $cfg.nexusApiKey }
    $url = "https://api.nexusmods.com/v1/games/palworld/mods/$NexusModId/files/$NexusFileId/download_link"
    $links = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    $link = @($links)[0].CDN
    if (-not $link) { $link = @($links)[0].URI }
    if (-not $link) { throw "Nexus returned no download link for $NexusModId/$NexusFileId" }
    Invoke-WebRequest -Uri $link -Headers $headers -OutFile $OutFile
    Write-Host "Downloaded $OutFile"
    return $OutFile
}

# --- arbitrary Nexus mod install ----------------------------------------
function Get-PalNexusLocalFile {
    return Join-Path (Split-Path -Parent $script:CatalogFile) 'nexus.local.json'
}

function Get-PalPayloadAnalysis {
    # Inspect an extracted payload root and guess what it is.
    # Returns Type ('pak'|'ue4ss-lua'), a suggested folder/name, and the
    # extracted root to deploy from.
    param([string]$Root)
    $paks = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter *.pak -File -ErrorAction SilentlyContinue)
    $luaRoots = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Directory -Filter Scripts -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'main.lua') }
    )
    if ($paks.Count -gt 0) {
        # Whole-pak archives (e.g. Pal/Content/Paks/... or bare .pak).
        $pakRoot = Split-Path -Parent $paks[0].FullName
        $name = [System.IO.Path]::GetFileNameWithoutExtension($paks[0].Name)
        return [pscustomobject]@{ Type = 'pak'; Name = $name; Root = $Root; PakFiles = @($paks | ForEach-Object { $_.FullName }) }
    }
    if ($luaRoots.Count -gt 0) {
        $modDir = Split-Path -Parent $luaRoots[0].FullName
        $name = Split-Path -Leaf $modDir
        return [pscustomobject]@{ Type = 'ue4ss-lua'; Name = $name; Root = $Root; PakFiles = @() }
    }
    # Unknown layout; default to pak (most common for client mods).
    return [pscustomobject]@{ Type = 'pak'; Name = 'nexusmod'; Root = $Root; PakFiles = @($paks | ForEach-Object { $_.FullName }) }
}

function Install-NexusMod {
    # Download and install ANY Nexus mod:  Install-NexusMod -NexusSpec 'nexus:<modId>:<fileId>'
    # Auto-detects pak vs UE4SS-Lua from the archive contents and registers a
    # local catalog entry (catalog/nexus.local.json, gitignored) so it can be
    # enabled/disabled/removed like any other mod.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$NexusSpec,
        [string]$Type = '',        # optional override: pak | ue4ss-lua
        [string]$Name = '',         # optional display name
        [switch]$WhatIf,
        [switch]$Force
    )
    if ($NexusSpec -notmatch '^nexus:(\d+):(\d+)$') { throw "Expected 'nexus:<modId>:<fileId>', got '$NexusSpec'." }
    $nx = $matches[1]; $nf = $matches[2]
    $id = "nexus_${nx}_${nf}"

    $existing = Get-PalCatalogMod -Id $id
    if ($existing -and -not $Force) { throw "Nexus mod '$id' is already catalogued. Use -Force to re-import." }

    $vendor = Get-PalVendorDir
    $zip = Join-Path $vendor "nexus_${nx}_${nf}.zip"
    $stage = Join-Path $vendor "_nexus_${nx}_${nf}"

    if ($WhatIf) {
        Write-Host "WhatIf: would download nexus:${nx}:${nf} to $zip, analyse, and install as '$id'."
        return
    }

    if (-not (Test-Path -LiteralPath $zip)) {
        Download-Nexus -NexusModId $nx -NexusFileId $nf -OutFile $zip
    } else {
        Write-Host "Using cached $zip"
    }

    # Extract (idempotent per stage).
    if (-not (Test-Path -LiteralPath $stage)) {
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Expand-PalArchive -Archive $zip -Destination $stage
    }
    $analysis = Get-PalPayloadAnalysis -Root $stage
    $detectedType = if ($Type) { $Type } else { $analysis.Type }
    if ($detectedType -notin @('pak', 'ue4ss-lua')) { throw "Unsupported detected type '$detectedType'." }
    $loadName = if ($Name) { $Name } else { $analysis.Name }
    $loadOrder = if ($detectedType -eq 'ue4ss-lua') { @($loadName) } else { @() }

    # The stage root itself is the payload source (folder kind).
    $rel = "_nexus_${nx}_${nf}"
    $entry = [ordered]@{
        id = $id
        name = $loadName
        version = 'nexus-download'
        type = $detectedType
        side = 'client'
        requires = if ($detectedType -eq 'ue4ss-lua') { @('ue4ss') } else { @() }
        source = [ordered]@{ kind = 'folder'; file = $rel }
        files = @()
        loadOrder = $loadOrder
        nexus = [ordered]@{ modId = $nx; fileId = $nf }
    }

    # Persist overlay catalog.
    $localFile = Get-PalNexusLocalFile
    $overlay = @(Get-PalLocalOverlay -Path $localFile)
    $overlay = @($overlay | Where-Object { $_.id -ne $id }) + @($entry)
    Write-JsonData -Path $localFile -Data $overlay

    Install-PalMod -Id $id
    Write-Host "Installed Nexus mod as '$id'. Manage it like any catalog mod (enable/disable/remove)."
}

# --- Steam Workshop ----------------------------------------------------
function Get-PalSteamWorkshopContentDir {
    $appId = Get-AppIdForLayout
    foreach ($root in Get-SteamRoots) {
        $v = Join-Path $root "steamapps\workshop\content\$appId"
        if (Test-Path -LiteralPath $v) { return $v }
        $vf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vf) {
            Get-Content -LiteralPath $vf | ForEach-Object {
                if ($_ -match '^\s*"path"\s+"(.+)"\s*$') {
                    $lib = Join-Path ($matches[1].Replace('\\\\', '\')) "steamapps\workshop\content\$appId"
                    if (Test-Path -LiteralPath $lib) { return $lib }
                }
            }
        }
    }
    return $null
}

function Get-PalWorkshopModProps {
    param([string]$DirPath)
    $info = Join-Path $DirPath 'Info.json'
    if (Test-Path -LiteralPath $info) {
        $d = Read-JsonData -Path $info -Default @{}
        return [pscustomobject]@{
            ItemId = Split-Path -Leaf $DirPath
            Path = $DirPath
            Name = if ($d.ModName) { $d.ModName } elseif ($d.Name) { $d.Name } else { '(unknown)' }
            Version = if ($d.Version) { $d.Version } else { '' }
            PackageName = if ($d.PackageName) { $d.PackageName } else { '' }
            HasInfo = $true
        }
    }
    return [pscustomobject]@{ ItemId = Split-Path -Leaf $DirPath; Path = $DirPath; Name = '(no Info.json)'; Version = ''; PackageName = ''; HasInfo = $false }
}

function Get-PalWorkshopMods {
    $dir = Get-PalSteamWorkshopContentDir
    if (-not $dir) { return @() }
    $out = @()
    foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)) {
        $out += Get-PalWorkshopModProps -DirPath $d.FullName
    }
    return $out
}

function Get-PalWorkshopModDir {
    param([string]$ItemId)
    $dir = Get-PalSteamWorkshopContentDir
    if (-not $dir) { return $null }
    $p = Join-Path $dir $ItemId
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

function Test-PalDuplicateUe4ss {
    # The manual-vs-Workshop UE4SS collision hazard.
    param($Layout)
    $manual = Test-Path -LiteralPath (Join-Path $Layout.Ue4ss 'UE4SS.dll')
    $wsHasUe4ss = $false
    $wsDir = Get-PalSteamWorkshopContentDir
    if ($wsDir) {
        foreach ($d in @(Get-ChildItem -LiteralPath $wsDir -Directory -ErrorAction SilentlyContinue)) {
            $info = Join-Path $d.FullName 'Info.json'
            if (Test-Path -LiteralPath $info) {
                $j = Read-JsonData -Path $info
                if (($j.ModName -match 'ue4ss') -or ($j.Name -match 'ue4ss')) { $wsHasUe4ss = $true }
            }
        }
    }
    if ($manual -and $wsHasUe4ss) {
        return 'Manual UE4SS runtime AND a Workshop-delivered UE4SS core are both present. This can crash on startup - keep only one.'
    }
    return $null
}

# --- CLI entry point ----------------------------------------------------
function Invoke-PalModAction {
    param(
        [Parameter(Mandatory)][string]$Mode,
        [string]$Id,
        [string]$Path,
        [string]$SourceOverride,
        [switch]$Force,
        [switch]$WhatIf
    )
    switch ($Mode) {
        'list'    { Get-PalMod | Format-Table Id, Name, Version, Type, Source, Requires, Installed, Enabled -AutoSize }
        'status'  { if (-not $Id) { throw 'status needs a mod id' }; Get-PalModStatus $Id | Format-List }
        'install' { if (-not $Id) { throw 'install needs a mod id' }; Install-PalMod -Id $Id -SourceOverride $SourceOverride -Force:$Force -WhatIf:$WhatIf }
        'remove'  { if (-not $Id) { throw 'remove needs a mod id' }; Uninstall-PalMod -Id $Id -WhatIf:$WhatIf }
        'enable'  { if (-not $Id) { throw 'enable needs a mod id' }; Enable-PalMod -Id $Id -WhatIf:$WhatIf }
        'disable' { if (-not $Id) { throw 'disable needs a mod id' }; Disable-PalMod -Id $Id -WhatIf:$WhatIf }
        'doctor'  { Invoke-PalDoctor | Format-List }
        'backup'  { Backup-PalMods -WhatIf:$WhatIf | Format-List }
        'restore' { Restore-PalMods -WhatIf:$WhatIf }
        'import'  { Import-PalModArchive -Path $Path -WhatIf:$WhatIf }
        'workshop'{ Invoke-PalWorkshopAction }
        default   { throw "Unknown command '$Mode'." }
    }
}

function Invoke-PalWorkshopAction {
    $mods = Get-PalWorkshopMods
    if ($mods.Count -eq 0) { Write-Host 'No Steam Workshop items found for Palworld here.'; return }
    $mods | Format-Table ItemId, Name, Version, PackageName -AutoSize
}

function Import-PalModArchive {
    # Import an external archive/folder into vendor/ and print a catalog
    # skeleton the user can paste into catalog/mods.json. This is the bridge
    # for ad-hoc mods that have no catalog entry yet.
    param([string]$Path, [switch]$WhatIf)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { throw 'Provide a path to the archive or folder.' }
    $item = Get-Item -LiteralPath $Path
    if ($WhatIf) { Write-Host "Would import $($item.FullName)"; return }
    $dest = Join-Path (Get-PalVendorDir) (Split-Path -Leaf $Path)
    if ($item.PSIsContainer) {
        Copy-PalTree -Source $Path -Destination $dest
    } else {
        Copy-Item -LiteralPath $Path -Destination $dest -Force
    }
    Write-Host "Copied to vendor: $dest"
    Write-Host 'Add a catalog entry in catalog/mods.json, e.g.:'
    Write-Host @"
  { "id": "somename", "name": "My Mod", "version": "1.0.0",
    "type": "pak", "side": "client", "requires": [],
    "source": { "kind": "file", "file": "$(Split-Path -Leaf $Path)" },
    "files": [], "loadOrder": [] }
"@
    Write-Host 'See docs/ARCHITECTURE.md for the schema.'
}

# --- export public surface -----------------------------------------------
Export-ModuleMember -Function @(
    'Set-PalConfig', 'Get-PalConfig', 'Get-PalVendorDir', 'Get-PalworldPath', 'Get-PalworldLayout',
    'Get-PalMod', 'Get-PalCatalogMod', 'Get-PalModStatus',
    'Install-PalMod', 'Uninstall-PalMod', 'Enable-PalMod', 'Disable-PalMod',
    'Backup-PalMods', 'Restore-PalMods', 'Invoke-PalDoctor',
    'Get-PalWorkshopMods', 'Test-PalDuplicateUe4ss', 'Invoke-PalWorkshopAction',
    'Invoke-PalModAction', 'Import-PalModArchive', 'Install-NexusMod'
)

