---
name: update-faction-hints
description: Update the static faction hint data of ProfessionShare (Core/Data/FactionHints.lua: which factions the Reputation list tracks, their ids, and what each standing unlocks) from the wiki and the game. Use after a WoW Forever patch, when a guild member reports a wrong or missing reputation hint, or when asked to add a faction, add item ids to the hints, or "refresh the reputation hints".
---

# Updating the faction hints

`Core/Data/FactionHints.lua` is **static data written by hand**: the game tells an addon a faction's name and a player's
standing, but not what a standing unlocks. This skill keeps that file correct. It touches only that file (plus the
CHANGELOG line and the tests' expectations if a faction is added or removed). Nothing in it is sent to other players, so
changing hints needs **no protocol or schema change**.

## What the file holds
- `FactionHints.CHECKED`: the date the hints were last compared with the sources (`YYYY-MM-DD`). Bump it at the end.
- `FactionHints.SOURCE`: where the hints come from.
- `FactionHints.FACTIONS`: one entry per tracked faction: `id` (faction id), `name` (English fallback), `group`
  (`raid` | `vendor` | `city` | `cartel` | `pvp`), `icon`, `hints` = `{ standing, en, de, items? }` ascending by standing
  (1 Hated, 2 Hostile, 3 Unfriendly, 4 Neutral, 5 Friendly, 6 Honored, 7 Revered, 8 Exalted).
- A faction **only** in this list is scanned, sent and shown. Removing a faction drops its standings from every record
  on the next scan (and peers' records skip unknown ids), so remove only factions that no longer exist.

## Procedure
1. **Baseline.** From `professionshare/`: `luajit tests/run.lua` (LuaJIT at `%LOCALAPPDATA%\Programs\LuaJIT\bin`).
   Note the summary line.
2. **Collect the sources** (read the pages; never write hints from memory):
   - https://warcraft.wiki.gg/wiki/Classic_reputation_rewards
   - each faction's own page on warcraft.wiki.gg (for example `Thorium_Brotherhood`, `Timbermaw_Hold_(faction)`,
     `Cenarion_Circle`, `Argent_Dawn`, `Hydraxian_Waterlords`, `Zandalar_Tribe`, `Brood_of_Nozdormu`,
     `Wintersaber_Trainers`), and https://warcraft.wiki.gg/wiki/FactionID for ids.
   - Patch notes of the Forever patch that prompted the update, if the user names one.
   Wiki pages describe several game versions. Keep only what is true for **Classic Era (1.x)**; skip Season of
   Discovery, TBC+ and retail-only rewards, and statements like "removed from the game" that refer to later expansions.
   A page that comes back truncated is **not** a source for the part that is missing: fetch that section again or
   leave the hint as it is and say so.
3. **Compare** every faction entry with the sources and write a short table for the user: faction, standing,
   current hint, what the source says, proposed change (add / change / remove / keep). Flag anything uncertain.
   Ask the user before removing a faction or rewriting more than a handful of hints.
4. **Edit the file.** Rules:
   - One hint per standing that unlocks something worth knowing (the single biggest benefit), short, no colour codes,
     no `|` character (the tests reject it).
   - Always both languages: `en` and `de`. German game terms follow the German client (Wohlwollend, Respektvoll,
     Ehrfürchtig; item and NPC names as the German client spells them). If unsure of a German item name, describe it
     instead of guessing a proper name.
   - `items`: add item ids only after the user checked them in game (step 5). A wrong id shows a wrong item.
   - Keep `hints` ascending by standing and faction ids unique.
5. **In-game check (user).** Ask the user to run, in the dev build: `/psd rep`. It prints every listed faction as
   `id English name (client name): standing`. A `?` as client name means the id is wrong or unknown on Forever. For
   item ids: `/dump GetItemInfo(<id>)` (or shift-click the item into chat) must show the intended item. Record the
   output (no real character names) in the feature log if this update is part of a feature.
6. **Bump `CHECKED`** to today's date (get it from the system, do not guess) and update `SOURCE` if sources changed.
7. **Tests.** `luajit tests/run.lua`: `tests/test_reputation.lua` checks the file's shape (unique ids, ascending
   standings, both languages, known groups, item ids are numbers). If a test names a removed faction, update the test.
   Paste the summary line in your report.
8. **Record.** Add a line under the next version in `CHANGELOG.md` ("Reputation hints updated for <patch>").
   Commit only when the user asks (`chore(professionshare): update faction hints`).

## Report to the user
The comparison table (what changed and why, with the source URL per change), what is still unverified (ids not checked
in game, hints from a truncated page), and the test summary line.
