# Implementation status (updated 2026-11-28, after release 1.8.0 and the status review)

Per-feature state lives in `features/INDEX.md`; what is proven and what is open lives in each feature's `verify.md`.
This page is the short overview, not a second copy.

**Released:** up to 1.8.0. Every feature up to 050 is `done` (001, 004, 005 as obsolete) or `abandoned` (003).
Most closed at the user's status review on 2026-11-28 from live use, not from the step-by-step checklists.
014 moved to GuildGames with 015.

**Planned:** 054 party/raid portrait key icon (still wanted? open question in its spec).

**Bugs:** `bugs/INDEX.md` (B003: the cooldowns grid is sometimes confusing; what exactly is open).

Never run: two real members syncing over a full evening (the original soak test).

## Publishing

* CurseForge project (slug `guild-talentshare`), files uploaded **manually** from `dist/ProfessionShare-<version>.zip`
  (`TalentShare-*.zip` up to 0.7.3), built by `tools/package.ps1`: https://legacy.curseforge.com/wow/addons/guild-talentshare
* GitHub: https://github.com/rubertsmann/wowaddoncollection
* The automated release (`.github/workflows/release.yml`) is NOT active: it needs `## X-Curse-Project-ID` in the TOC and
  the repo secret `CF_API_TOKEN`, and it does not fetch LibGuildSync.

## Design differences from the original plan (`eval/plan.md`, historical)

* No AceComm / LibSerialize / ChatThrottleLib. Messages are chunked at 225 bytes with header `id|idx|total|`; sends are
  paced (now through LibGuildSync).
* Sync is pull-based: HELLO carries my record revision; peers `WANT` my snapshot when theirs is older.
