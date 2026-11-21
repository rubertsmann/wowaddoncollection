# Localization

Status: draft | Since version: 0.2.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Each player sees TalentShare in their own language: window text is translated (English and German today), and profession, recipe and reagent names always come from the player's own game client. A guild with German, English and other clients sees one consistent list instead of mixed-language duplicates. Search ignores case and accents ("kursch" finds "Kürschnerei").

## How to use
- Nothing to do: the UI follows the game client language; untranslated languages show English.
- Testing another language: `/ts locale deDE` (or `enUS`), then `/reload`; `/ts locale auto` resets. Dev build: `/tsd locale ...`.
- `/ts i18n` prints what the client reports (profession ids, spell name vs window recipe name) for debugging.
- Adding a language: copy `Locales/deDE.lua` to `Locales/<code>.lua`, translate the values (keep the `{placeholders}`), add the file to `TalentShare.toc`. `luajit tests/run.lua` checks key completeness and placeholders. `tools/package.ps1` already ships the whole `Locales` folder.

## How it works
- Identity is an ID: professions by skill line id (`entry.id`, from `GetProfessionInfo`), recipes by recipe id. Records also carry a name snapshot plus `loc` (language of that snapshot) for fallback only. Old (0.1.0) records without ids are matched by name through the name tables.
- Display names are computed by `Core/Names.lua` on the viewer's client: own client name, then matching-language snapshot, then the static table (`Locales/*.lua`), then English, then the snapshot.
- UI text: `ns.L[<English text>]`; `ns.Locale.Fmt("{n} ...", vars)` for placeholders; `ns.Locale.Plural(n, one, many)`.
- Text utilities in `Core/Util.lua`: `IsValidUtf8`, `TruncateUtf8`, `Fold`, `SearchKey`.
- Order notes: max 80 bytes, cut on a character boundary; peers reject malformed UTF-8.
- Wire format and SavedVariables schema are unchanged (only optional fields were added), so 0.2.0 and 0.1.0 clients interoperate.

## Localization notes
Not translated on purpose: debug slash command output and the addon title. The addon never stores translated game names of its own making; profession ids other than 165/185/393 in `Locales/*.lua` come from memory and are only a fallback.

## Limits and known issues
- Only enUS and deDE ship; other clients get English UI text (game names are still in their own language).
- CJK text is matched byte-wise and sorted by byte value.
- Peer-supplied text (notes, names) is not yet escaped for `|` codes (separate finding in `review/`).
- Layout with long translations is untested in game.

## Changelog line
- Localization: UI in English/German, profession/recipe names resolved per viewer (mixed-language guilds merge), case/accent-insensitive search, UTF-8-safe order notes (fixes requests with long multi-byte notes doing nothing).
