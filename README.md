# Palworld Client Mod Manager (pwmod)

A catalog-driven, PowerShell-based mod manager for **Palworld** client-side mods.
It installs, removes, enables, and disables mods for UE4SS (Lua) and `.pak` (packed)
mods, and can fetch mods directly from **Nexus Mods** and **Steam Workshop** at
install time — nothing third-party is bundled or committed to this repository.

## Why this exists

The original project was a one-click installer that shipped UE4SS + PalMiniMap +
DungeonBossRespawnMapTimer + Better Night Light inside the repo. It worked, but it
was a static snapshot: adding a new mod meant editing scripts, and third-party files
were being redistributed.

This rewrite is **manifest-driven**. A JSON catalog describes what to install and
*where to get it*; the engine resolves a source (local archive, folder, Nexus, or
Workshop), deploys it to the right place, and keeps track of what it did. The old
installer is preserved as a working reference in [`legacy/`](legacy/).

## Features

- `install` / `remove` / `enable` / `disable` / `list` / `status` / `doctor`
- Source adapters: local file, `.zip`/`.7z` archive, folder, **Nexus Mods API**, **Steam Workshop**
- `backup` / `restore` snapshots of your loader + installed mods
- `doctor` health checks, including the classic *manual-vs-Workshop UE4SS* conflict
- `-WhatIf` dry-runs everywhere
- Pester test suite + GitHub Actions CI

## Quick start

```powershell
# Clone / copy the repo, then:
pwsh .\bin\pwmod.ps1 list          # see catalog mods and their state
pwsh .\bin\pwmod.ps1 doctor        # confirm the game is found + loadable

# One-click install of the bundled catalog mods (needs payloads in vendor\):
.\bin\Install-Mods.bat

# Manage individual mods:
pwsh .\bin\pwmod.ps1 install palminimap
pwsh .\bin\pwmod.ps1 install betternightlight --source "C:\path\to\BNLrelease_P.pak"
pwsh .\bin\pwmod.ps1 disable dungeonbosstimer
pwsh .\bin\pwmod.ps1 remove ue4ss
```

See [docs/USAGE.md](docs/USAGE.md) for the full reference and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it works.

## Layout

```
catalog/mods.json      Install recipes (the catalog)
catalog/installed.json Local, machine-specific state (git-ignored)
src/PalModMan.psm1     Engine module (all commands)
bin/pwmod.ps1          CLI entry point
bin/*.bat              Double-click convenience launchers
vendor/                Your payload archives/folders (git-ignored)
tests/                 Pester tests
legacy/                Original one-click installer (reference)
```

## Requirements

- Windows 10/11, PowerShell 5.1+ (pwsh recommended)
- Palworld installed via Steam
- Optional: a free [Nexus Mods API key](https://next.nexusmods.com/settings/api-tokens) for automatic Nexus downloads

## Legal / safety

Third-party mods are fetched at install time from their official distribution
channels (Nexus, Steam Workshop, or a file you place in `vendor/`). They are
**not** redistributed by this project. See `LICENSE`.

---

*For the earlier one-click version, see `legacy/`.*
