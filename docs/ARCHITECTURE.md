# Architecture

`pwmod` is a thin CLI over a PowerShell module. The module is **catalog-driven**:
a declarative JSON catalog describes each mod (what it is, where it goes, where to
get the files) and the engine turns that into concrete filesystem actions.

## Repository layout

```
src/PalModMan.psm1      Everything: config, discovery, catalog, lifecycle, adapters
catalog/mods.json       Mod recipes (committed)
catalog/installed.json  What is installed on THIS machine (git-ignored)
config.json             User settings: game path, Nexus key, vendor dir (gitignored)
vendor/                 Payload files you provide / downloads land here (gitignored)
bin/pwmod.ps1           CLI front-end
tests/                  Pester tests
docs/                   This documentation
legacy/                 Original one-click installer (reference, superseded)
```

## Game layout assumptions

UE4SS (RE-UE4SS build) is injected through a DWM API proxy DLL that loads with the
game process. The tool works against this Steam layout:

```
<GamePath>/Pal/Binaries/Win64/dwmapi.dll         UE4SS loader proxy
<GamePath>/Pal/Binaries/Win64/ue4ss/UE4SS.dll   UE4SS runtime
<GamePath>/Pal/Binaries/Win64/ue4ss/Mods/       Lua mods (folder per mod)
<GamePath>/Pal/Binaries/Win64/ue4ss/Mods/mods.txt  Load list:  name : 0|1
<GamePath>/Pal/Content/Paks/~mods/               .pak mods
```

Each mod in the catalog declares a `type` that maps to a deploy target:

| type            | deploys to                                    |
|-----------------|-----------------------------------------------|
| `ue4ss-loader`  | loader proxy + `ue4ss/` runtime               |
| `ue4ss-lua`     | `ue4ss/Mods/<loadOrder name>/`                |
| `pak`           | `Pal/Content/Paks/~mods/*.pak`                |
| `config`        | *(reserved, not yet implemented)*             |

## Data flow

1. `pwmod <command>` calls into the module.
2. `Get-PalworldLayout` resolves the game path (config → registry → Steam files)
   and computes the target directories.
3. `Install-PalMod` looks up a catalog recipe by id, calls `Resolve-ModSource`
   (see below) to obtain payload files, then deploys them per `type`.
4. Deployment updates `mods.txt` for Lua mods via `Set-ModsTxtEntries`, and records
   what it deployed in `catalog/installed.json`.
5. `Uninstall-PalMod` reverses the deployment and drops the manifest entry.

## Source resolution (`Resolve-ModSource`)

Every recipe declares a `source`. The adapter yields filesystem items for the mod.

| `source.kind` | behaviour                                                              |
|---------------|------------------------------------------------------------------------|
| `file`        | a single file in `vendor/` (or a zip/7z that is expanded once)         |
| `folder`      | an unpacked folder in `vendor/`                                        |
| `nexus`       | download via the Nexus v1 API (needs `nexusApiKey`) once, then cache    |
| `workshop`    | the Steam Workshop item folder on disk (no network)                    |

A user can override a recipe's source at install time:
`pwmod install <id> -SourceOverride <path|nexus:<mod>:<file>|workshop:<item>>`.

### Nexus

A free API key is stored as `config.json#nexusApiKey` (`pwmod set-key`). Downloads
go through the v1 API download-link endpoint and are cached in `vendor/`. This is
how *arbitrary* Nexus mods are supported: `nexus:<modId>:<fileId>`.

### Steam Workshop

The scanner reads `SteamApps/workshop/content/1623730/` and also supports multiple
library folders via `libraryfolders.vdf`. It reads each item's `Info.json` for name
and version. Workshop items are used directly from the Steam cache (no download).

## `mods.txt` handling

`mods.txt` is the load list for UE4SS. Each non-built-in Lua mod needs a line
`<loadOrder name> : 1`. The module:

- preserves existing/unknown lines and the UE4SS header comments,
- writes `1`/`0` for the mod's load-order name,
- never reorders built-in keybind entries.

## Installed-state manifest

`catalog/installed.json` (gitignored) records, per mod id, the payload origin so
that `doctor` can verify deployment and `remove` can clean up exactly what it placed.
It is machine-local — different machines can have different sets enabled.

## Health check

`Invoke-PalDoctor` verifies:

- the loader proxy `dwmapi.dll` exists,
- the UE4SS runtime `UE4SS.dll` exists,
- `mods.txt` exists,
- every installed catalog mod's deployed files are present,
- the manual-vs-Workshop UE4SS conflict is not present.

## Testing & CI

- Pester tests in `tests/` only touch a temporary sandbox in `vendor/`; the real
  game install is never written to.
- GitHub Actions (`.github/workflows/ci.yml`) parses every PowerShell file and runs
  the Pester suite on `windows-latest`.