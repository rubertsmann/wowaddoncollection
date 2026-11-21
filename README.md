# wowaddons

World of Warcraft **Forever** addons, one folder per addon. Each folder has its own README, CHANGELOG, tests
(`luajit tests/run.lua`, run inside the folder) and `tools/package.ps1` / `tools/deploy.ps1`.

| Folder | Addon | Latest release (tag) |
|---|---|---|
| [`professionshare/`](professionshare/README.md) | ProfessionShare (until 0.7.3: TalentShare): guild professions, recipes and crafting order board | `talentshare/v0.7.3` (new tags: `professionshare/v*`) |
| [`guildgames/`](guildgames/README.md) | GuildGames: coin flip, slot machine and Survivor with guild leaderboards | `guildgames/v0.1.0` |
| [`libguildsync/`](libguildsync/README.md) | LibGuildSync-1.0: shared guild sync library, embedded by ProfessionShare and GuildGames | `libguildsync/minor-1` |
| [`fpvcigarette/`](fpvcigarette/README.md) | FPV Cigarette: first-person cigarette overlay, dancer window | `fpvcigarette/v0.2.0` |
| [`foreverbetteruiplus/`](foreverbetteruiplus/README.md) | ForeverBetterUIPlus | not released yet |

ProfessionShare and GuildGames embed `libguildsync/LibGuildSync`: their `tools/deploy.ps1` links it into `Libs/` (the link is
git-ignored) and `tools/package.ps1` copies the real files into the release zip.

Until 0.7.1 this repository held only TalentShare (its history is kept; the files moved into `talentshare/`, renamed to
`professionshare/` with the addon on 2026-11-21).
Tags of the other addons are prefixed with their folder name.
