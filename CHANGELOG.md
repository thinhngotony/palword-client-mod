# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Manifest-driven mod manager core (`src/PalModMan.psm1`): `install`, `remove`,
  `enable`, `disable`, `list`, `status`, `doctor`, `backup`, `restore`.
- Catalog model (`catalog/mods.json`): declarative install recipes with
  source adapters (local file, archive, folder, Nexus, Steam Workshop).
- Import adapter with automatic layout detection (pak, UE4SS Lua tree,
  `Pal/...` zip, Workshop `Info.json` package).
- Nexus Mods API downloader (opt-in via user API key; files fetched at install
  time, never redistributed).
- Steam Workshop scanner for app 1623730 (client + Windows dedicated server),
  including duplicate-UE4SS conflict detection.
- CLI entry point (`pwmod.ps1`) with subcommands and `-WhatIf` support.
- `nexus <modId>:<fileId>` subcommand (and `install nexus:...`) to download and
  install any Nexus mod, with automatic pak/Lua layout detection and a git-ignored
  local catalog overlay (`catalog/*.local.json`).
- Pester test suite and GitHub Actions CI.
- Documentation: `README.md`, `docs/ARCHITECTURE.md`, `docs/USAGE.md`.

### Removed
- Bundled third-party mod payloads from source control (now fetched at install
  time). The original one-click installer lives on as `legacy/`.

## Legacy

The `legacy/` folder contains the original self-contained one-click installer
(UE4SS + PalMiniMap + DungeonBossRespawnMapTimer + Better Night Light).
It still works but is superseded by the catalog-driven manager.
