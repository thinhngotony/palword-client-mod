# Usage

## Invoking the CLI

From PowerShell or `cmd`:

```powershell
pwsh .\bin\pwmod.ps1 <command> [args] [switches]
```

Switches:

| switch | meaning                        |
|--------|--------------------------------|
| `-d`   | dry run (`-WhatIf`) — no writes|
| `-f`   | force                         |

`bin/pwmod.bat` passes arguments through from `cmd` for convenience.

## Commands

### `list`
Shows every catalog mod with its installed/enabled state.

```powershell
pwmod list
```

### `status <id>`
Detailed view of one mod (deployed files, load-order name, enabled state).

```powershell
pwmod status palminimap
```

### `install <id> [source]`
Installs a catalog mod. The optional `source` overrides the catalog's source:

```powershell
pwmod install palminimap                     # from vendor/, per catalog
pwmod install ue4ss -d                       # dry run first
pwmod install betternightlight -SourceOverride "D:\downloads\BNLrelease_P.pak"
pwmod install somenexusmod -SourceOverride "nexus:12345:67890"
pwmod install someworkshop -SourceOverride "workshop:3625223587"
```

The `nexus:` form downloads via the Nexus API (requires an API key, see below).
The `workshop:` form uses the item already present in the Steam Workshop cache.

### `nexus <modId>:<fileId>`
Download and install **any** Nexus mod with one command — no catalog entry needed.
The archive is fetched from Nexus, its layout is auto-detected (`.pak` vs UE4SS-Lua),
and a local catalog entry is registered so it can be enabled, disabled, or removed
like any other mod.

```powershell
pwmod set-key  <your-nexus-api-key>      # once
pwmod nexus 2341:7613                    # installs Nexus mod 2341, file 7613
pwmod nexus 12345:67890 -f              # force re-import/re-install
```

The resulting entry gets id `nexus_<modId>_<fileId>` (see `pwmod list`).

### `remove <id>`
Uninstalls a mod and removes it from the load list.

### `enable <id>` / `disable <id>`
Toggles the mod's line in `mods.txt` without touching its files.

### `doctor`
Health-check: loader present, runtime present, `mods.txt` present, deployed files
intact, no manual-vs-Workshop UE4SS conflict.

### `backup [dir]` / `restore [dir]`
Snapshots the loader proxy, the `ue4ss/` runtime, and the `~mods/` pak folder into
`<GamePath>/PalMods_Backup_<timestamp>` (or a folder of your choice). `restore`
with no argument restores the newest backup found under the game directory.

### `vendor [path]`
With no argument, prints the vendor directory (where payload files live) and its
contents. With a path, imports an archive or folder into `vendor/` and prints a
ready-to-paste catalog skeleton for it.

### `workshop`
Lists Steam Workshop items for Palworld found on this machine (client or server).

### `set-path <dir>`
Remembers the Palworld install folder. Use it if auto-detection can't find the game.

```powershell
pwmod set-path "D:\SteamLibrary\steamapps\common\Palworld"
```

### `set-key <key>`
Saves a Nexus Mods API key (used for `nexus:` downloads). Get a key at
https://next.nexusmods.com/settings/api-tokens.

## Providing mod payloads (`vendor/`)

The catalog recipes reference payloads that are **not** distributed with the repo.
For the bundled catalog entries, drop the files in `vendor/`:

```
vendor/ue4ss/                       (extracted UE4SS distribution root)
    dwmapi.dll
    ue4ss/UE4SS.dll
    ue4ss/Mods/...
vendor/PalMiniMap/                  (the unpacked PalMiniMap mod folder)
vendor/DungeonBossRespawnMapTimer/  (the unpacked DungeonBoss mod folder)
vendor/BNLrelease_P.pak             (the Better Night Light pak)
```

A recipe can also point at a single archive instead of a folder — change
`"kind": "folder"` to `"kind": "file"` and set `"file"` to the archive name.

## Adding a new mod

1. Place the payload in `vendor/` (or use `vendor <path>` to import).
2. Add a recipe to `catalog/mods.json`:

```json
{
  "id": "mysillymod",
  "name": "My Silly Mod",
  "version": "1.0.0",
  "type": "pak",                  // "pak" | "ue4ss-lua" | "ue4ss-loader"
  "side": "client",
  "requires": ["ue4ss"],          // ids that must be installed first
  "source": { "kind": "file", "file": "mysillymod.pak" },
  "files": [],
  "loadOrder": []                 // e.g. ["MySillyMod"] for Lua mods
}
```

3. `pwmod install mysillymod`.

For *ad-hoc* mods you don't want to catalog, use `-SourceOverride` directly.

## One-click scripts

- `bin\Install-Mods.bat` — installs the four bundled catalog mods and runs `doctor`.
- `bin\Uninstall-Mods.bat` — removes all four, returning to a clean baseline.

## Troubleshooting

**`Palworld not found. Use "pwmod set-path"`** — auto-detection failed; set the path
manually.

**`No source files for '<id>'`** — the payload isn't in `vendor/` (or the archive is
missing). Drop it there or pass `-SourceOverride`.

**`No Nexus API key configured`** — `pwmod set-key <key>` before using `nexus:`.

**Doctor reports a duplicate UE4SS** — both a manual UE4SS and a Workshop-delivered
UE4SS core are present, which can crash the game on launch. Keep only one
(remove the manual one with `pwmod remove ue4ss`, or unsubscribe the Workshop item).

**A Lua mod doesn't load** — check `status <id>` → `EnabledInModsTxt` is `True`, and
that the mod folder in `ue4ss/Mods/` is named exactly like its `loadOrder` entry.