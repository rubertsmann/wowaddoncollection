# 017 Enchant effect text

## What it does
Recipes that make no item, such as enchants, now show what they do: the effect text appears in green in the recipe
icon's tooltip and as a line under the recipe title in the detail panel. The Recipes search also finds them by it
(e.g. "agility" / "Beweglichkeit").

## How it works
- The recipe id of an enchant on Forever is its classic spell id (13419 = Enchant Cloak - Minor Agility). Each client
  reads the text itself, in its own language: `Api.SpellDescription`, else the hidden tooltip of `spell:<id>`, else of
  `enchant:<id>` (`Api.HyperlinkTooltipLines`). Found texts are cached for the session.
- Nothing is stored or sent; no protocol or schema change. One debug log line per recipe records what each source
  returned (`window.effectProbe`; `/ts debug`, `/ts export`).

## Dev testing
Dev build: Debug tab -> **Fake enchanter** (or `/tsd fakeenchanter`) adds an in-memory "Fake Enchanter" with six
enchants. `Store.keptNames` keeps it from the guild-roster prune; it is gone after a version change or `/tsd clean`.

## Limits
- A spell the client has not loaded yet shows no text on the first hover (the load is requested; the next hover works).
- Recipes whose id is not a known spell show no effect.

## Verification
[verify.md](verify.md): confirmed in game by the user; search proven offline.
