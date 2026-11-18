# wowaddons

World of Warcraft **Forever** addons, one folder per addon. Each folder has its own README, CHANGELOG, tests
(`luajit tests/run.lua`, run inside the folder) and `tools/package.ps1` / `tools/deploy.ps1`.

| Folder | Addon | Latest release (tag) |
|---|---|---|
| [`talentshare/`](talentshare/README.md) | TalentShare: guild professions, recipes and crafting order board | `talentshare/v0.7.1` (also `v0.7.1`) |
| [`guildgames/`](guildgames/README.md) | GuildGames: coin flip, slot machine and Survivor with guild leaderboards | `guildgames/v0.1.0` |
| [`libguildsync/`](libguildsync/README.md) | LibGuildSync-1.0: shared guild sync library, embedded by TalentShare and GuildGames | `libguildsync/minor-1` |
| [`fpvcigarette/`](fpvcigarette/README.md) | FPV Cigarette: first-person cigarette overlay, dancer window | `fpvcigarette/v0.2.0` |
| [`foreverbetteruiplus/`](foreverbetteruiplus/README.md) | ForeverBetterUIPlus | not released yet |

TalentShare and GuildGames embed `libguildsync/LibGuildSync`: their `tools/deploy.ps1` links it into `Libs/` (the link is
git-ignored) and `tools/package.ps1` copies the real files into the release zip.

Until 0.7.1 this repository held only TalentShare (its history is kept; the files moved into `talentshare/`).
Tags of the other addons are prefixed with their folder name.
