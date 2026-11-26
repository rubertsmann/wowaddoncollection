# Roster move survives early journal lines, restore codes for lost companions

Status: done | Since version: 0.11.2 (restore command dev-only from 0.11.3) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
- Updating from 0.10.x or older keeps every catch and the active companion. 0.11.0 and 0.11.1 lost them when a guild
  member's outdated arena or companion section was dropped during the same load.
- A companion already lost can come back: support builds a restore code from the player's pre-update backup
  (`WTF/Account/<account>/SavedVariables/GuildGames.lua.bak` with `["schema"] = 2`). In 0.11.2 the player typed
  `/gg caught restore <code>` once; from 0.11.3 the command exists only in the dev build (`/ggd caught restore <code>`),
  because the code format is public and a live command made forged trained companions one chat line away. Another
  affected player needs a build with the command back in the live table.

## How it works
- The 2 -> 3 migration sets `db.caught.moveRoster`; `AzeCaught.SanitizePersisted` moves the old data when it is set
  and clears it.
- Code: `GGR1;npc;lvl;cls;hearts;fedStreak;careStreak;hunger;thirst;affection;energy;xp;w;l;atk;def;spd;vit;name`
  (`AzeCaught.RestoreCode(companion, entry)`). `AzeCaught.Restore` validates it with the saved-data sanitizer, adds a
  new roster companion (new uid), counts it in the collection (recreating the entry if needed), makes it active and
  sets `db.caught.restoredAt` (one restore per character).
- Building a code offline: load the backup's `GuildGamesDB` in the test harness, `Store.Init` it with this build and
  call `AzeCaught.RestoreCode` on the moved companion.

## Limits
- Without a pre-update backup nothing can be restored (the catch counts are no longer in the saved file).
- Needs are rounded to whole numbers; a sleeping companion comes back awake.
