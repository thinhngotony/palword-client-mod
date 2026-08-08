# =====================================================================
# PalModMan.Tests.ps1 - Pester tests for src/PalModMan.psm1
# Run:  Invoke-Pester .\tests -Output Detailed
# Exercises only the exported public API against a temporary sandbox.
# =====================================================================

$script:modulePath = (Resolve-Path (Join-Path $PSScriptRoot '..\src\PalModMan.psm1')).Path
Import-Module $script:modulePath -Force

$global:TestRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$global:TestVendor  = Join-Path $global:TestRoot 'vendor'
$global:TestSandbox = Join-Path $global:TestVendor '_testsandbox'
$global:TestConfig  = Join-Path $global:TestRoot 'config.json'
$global:FixturePath = Join-Path $global:TestVendor '_fixture_mod'

BeforeAll {
    # Lua-mod sample payload (source only; installed via -SourceOverride).
    if (Test-Path -LiteralPath $global:FixturePath) { Remove-Item -LiteralPath $global:FixturePath -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Join-Path $global:FixturePath 'Scripts') | Out-Null
    Set-Content -LiteralPath (Join-Path $global:FixturePath 'Scripts\main.lua') -Value '-- test' -Encoding ascii
}

AfterAll {
    Remove-Item -LiteralPath $global:TestSandbox -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $global:FixturePath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $global:TestConfig -Force -ErrorAction SilentlyContinue
    Remove-Module PalModMan -Force -ErrorAction SilentlyContinue
}

Describe 'Catalog & listing' {
    BeforeAll {
        if (Test-Path -LiteralPath $global:TestSandbox) { Remove-Item -LiteralPath $global:TestSandbox -Recurse -Force }
        $win = Join-Path $global:TestSandbox 'Pal\Binaries\Win64'
        New-Item -ItemType Directory -Force -Path (Join-Path $win 'ue4ss\Mods') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $global:TestSandbox 'Pal\Content\Paks') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $win 'Palworld-Win64-Shipping.exe') | Out-Null
        Set-PalConfig -PalworldPath $global:TestSandbox
    }

    It 'lists the bundled mods via the public API' {
        $rows = @(Get-PalMod)
        $rows.Count | Should -BeGreaterThan 0
        ($rows.id -contains 'palminimap') | Should -BeTrue
    }

    It 'reports detail on a known mod' {
        $s = Get-PalModStatus -Id 'palminimap'
        $s.Name | Should -Be 'PalMiniMap'
        $s.Type | Should -Be 'ue4ss-lua'
    }
}

Describe 'Config defaults' {
    It 'exposes path/key/vendor fields' {
        $c = Get-PalConfig
        ($c.PSObject.Properties.Name -contains 'palworldPath') | Should -BeTrue
        ($c.PSObject.Properties.Name -contains 'nexusApiKey') | Should -BeTrue
    }
}

Describe 'Enable / Disable toggling' {
    BeforeEach {
        if (Test-Path -LiteralPath $global:TestSandbox) { Remove-Item -LiteralPath $global:TestSandbox -Recurse -Force }
        $win = Join-Path $global:TestSandbox 'Pal\Binaries\Win64'
        New-Item -ItemType Directory -Force -Path (Join-Path $win 'ue4ss\Mods') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $global:TestSandbox 'Pal\Content\Paks') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $win 'Palworld-Win64-Shipping.exe') | Out-Null
        Set-PalConfig -PalworldPath $global:TestSandbox
    }

    It 'enables and disables a mod in the load list' {
        Disable-PalMod -Id 'palminimap'
        (Get-PalModStatus -Id 'palminimap').EnabledInModsTxt | Should -BeFalse

        Enable-PalMod -Id 'palminimap'
        (Get-PalModStatus -Id 'palminimap').EnabledInModsTxt | Should -BeTrue
    }
}

Describe 'Lua mod install/remove' {
    BeforeEach {
        if (Test-Path -LiteralPath $global:TestSandbox) { Remove-Item -LiteralPath $global:TestSandbox -Recurse -Force }
        $win = Join-Path $global:TestSandbox 'Pal\Binaries\Win64'
        New-Item -ItemType Directory -Force -Path (Join-Path $win 'ue4ss\Mods') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $global:TestSandbox 'Pal\Content\Paks') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $win 'Palworld-Win64-Shipping.exe') | Out-Null
        Set-PalConfig -PalworldPath $global:TestSandbox
    }

    It 'installs and removes a ue4ss-lua mod end to end' {
        Install-PalMod -Id 'palminimap' -SourceOverride $global:FixturePath
        $layout = Get-PalworldLayout
        (Test-Path -LiteralPath (Join-Path $layout.ModsDir 'PalMiniMap\Scripts\main.lua')) | Should -BeTrue
        (Get-PalModStatus -Id 'palminimap').Installed | Should -BeTrue

        Uninstall-PalMod -Id 'palminimap'
        (Get-PalModStatus -Id 'palminimap').Installed | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $layout.ModsDir 'PalMiniMap')) | Should -BeFalse
    }
}

Describe 'Pak install/remove' {
    BeforeEach {
        if (Test-Path -LiteralPath $global:TestSandbox) { Remove-Item -LiteralPath $global:TestSandbox -Recurse -Force }
        $win = Join-Path $global:TestSandbox 'Pal\Binaries\Win64'
        New-Item -ItemType Directory -Force -Path (Join-Path $win 'ue4ss\Mods') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $global:TestSandbox 'Pal\Content\Paks') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $win 'Palworld-Win64-Shipping.exe') | Out-Null
        Set-PalConfig -PalworldPath $global:TestSandbox
    }

    It 'deploys a pak into ~mods and removes it' {
        $pak = Join-Path $global:TestVendor '_fixture.pak'
        Set-Content -LiteralPath $pak -Value 'PAK' -Encoding ascii
        try {
            Install-PalMod -Id 'betternightlight' -SourceOverride $pak
            $layout = Get-PalworldLayout
            (Test-Path -LiteralPath (Join-Path $layout.PaksMods '_fixture.pak')) | Should -BeTrue

            Uninstall-PalMod -Id 'betternightlight'
            (Test-Path -LiteralPath (Join-Path $layout.PaksMods '_fixture.pak')) | Should -BeFalse
        } finally {
            Remove-Item -LiteralPath $pak -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Doctor' {
    BeforeEach {
        if (Test-Path -LiteralPath $global:TestSandbox) { Remove-Item -LiteralPath $global:TestSandbox -Recurse -Force }
        $win = Join-Path $global:TestSandbox 'Pal\Binaries\Win64'
        New-Item -ItemType Directory -Force -Path (Join-Path $win 'ue4ss\Mods') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $global:TestSandbox 'Pal\Content\Paks') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $win 'Palworld-Win64-Shipping.exe') | Out-Null
        Set-PalConfig -PalworldPath $global:TestSandbox
    }

    It 'returns a status object with Healthy and Issues' {
        $r = Invoke-PalDoctor
        ($r.PSObject.Properties.Name -contains 'Healthy') | Should -BeTrue
        ($r.PSObject.Properties.Name -contains 'Issues') | Should -BeTrue
    }
}