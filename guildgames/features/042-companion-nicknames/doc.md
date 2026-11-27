# 042 Companion nicknames: documentation

## What it does
- Every companion in your roster can be given a nickname once, with up to 24 characters. It is shown wherever that companion is
  shown: the pet view, the companion panel, the roster, the minimap tooltip, chat lines, the team picker and the arena.
- Guild members see the nickname in the guild list and in fights. Hovering over it in fights shows the species name.
- Every companion caught from 0.12.0 on remembers when and where it was caught. Only you see this.

## How to use it
- In Collection > Caught, select a companion and press **Rename** (shown only while it has no nickname). Type the name and
  press the tick (or Enter); the cross (or Escape) cancels.
- Clicking the active companion's name in the companion view, or `/gg caught name <text>`, does the same for the active companion.
- Once named, a companion keeps the name: the Rename button disappears and a second name is refused.
- Dev build: `/ggd caught unname` takes the nickname of the selected (else the active) companion away again.
- To see the catch origin, hover over the companion's name, a roster row (Collection > Caught) or a row in the team picker.

## How it works
- Stored: `GuildGamesDB.caught.roster[uid].info = { nick?, at?, map? }`. The nickname and the catch facts sit together
  per companion. `at` is server time, and `map` is the uiMapID from `C_Map.GetBestMapForUnit("player")` at the throw or
  trap. The zone name is looked up with `C_Map.GetMapInfo(map).name` only when shown, so it follows the client language.
- Sent: `nk` in the caught section's `c` and in every arena fighter (see `docs/protocol.md`, "Companion nicknames").
  `at`/`map` are never sent.
- Ids are the reference: my companions are addressed by `uid` and a peer's by `npc` id. The nickname never takes part in
  lookups, team picks, fight ids or fight math. Fight history rows store the NPC ids (`mi`/`ti`) and nicknames
  (`mk`/`tk`) of both first fighters next to the old name text.
- Cleaning: input loses control characters and `|`, and spaces are collapsed and trimmed (`AzeCaught.NormalizeNickname`).
  Saved and peer values must already be in that form (`AzeCaught.CleanNickname`), or the field is dropped alone.

## Limits and known issues
- Companions caught before 0.12.0 (and restored ones) have no catch time or place. They show "Caught: before this was recorded".
- In fights, the hover shows the species only: fighters carry no uid, and the origin stays local.
- No word filter: the guild is the trust boundary.
- An older build (0.11.x) drops `info` when it loads the saved data, so nicknames and origins are lost on a downgrade.

## Localization
- 9 new strings (deDE added). The date format is a translatable string (`%Y-%m-%d` / `%d.%m.%Y`).

## Verification
See [verify.md](verify.md). The offline suite passes (215/0); the in-game and two-client rows are open.
