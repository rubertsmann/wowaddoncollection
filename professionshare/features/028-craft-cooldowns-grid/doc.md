# Craft cooldowns grid

Status: verifying (built and proven offline) | Since version: 1.4.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The Misc Items tab gets a **Cooldowns** mode: a grid of the timegated crafts (all transmutes as one tile, Mooncloth,
the Salt Shaker), each tile the size of an action button. A tile shows the cooldown sweep and time left of the best
crafter in the guild. A badge shows how many crafters are ready, and the tile glows while someone online can craft it
now. Clicking a tile whispers that crafter with the craft's link already in the chat box.

## How to use
- UI: `/ps` -> Misc Items -> dropdown "Cooldowns".
  - Hover a tile to see every crafter: online dot, time left, exact ready time, when it was last updated.
  - Left-click whispers the best online crafter. Right-click lets you choose a crafter.
  - The button "One tile per crafter" switches to one tile per crafter and craft.
  - The search box filters by craft or member.
- Commands: `/ps cd` shows what the game reports for my cooldowns, what was taken and what is stored. With a
  profession window open it also lists that window's cooldown recipes and their ids. `/ps cd scan` also updates my
  record.
- Dev build: Dev tools -> Members -> "Crafters: cooldowns in every state", Triggers -> "A cooldown ends in 20 s",
  Probes -> "Craft cooldowns (/ps cd)", Cleanup -> "Remove all fake data".

## How it works
- Data (SavedVariables):
  - `cds[name] = { name, rev, c = { [groupKey] = readyAt }, e = { [groupKey] = true }, seen }`, schema 9.
  - Ready times are in this client's server time. A ready time of 0 means ready. `e` marks an estimate. `seen` is
    when the record arrived, or when my own was last read.
- Messages: `HELLO.crev`, `WANTC`, `CDS {cds, at}` (protocol 2.8; see docs/protocol.md section 16). The answer carries
  the sender's server time `at`. The receiver keeps the time left and adds it to its own clock.
- Reading my own cooldowns (`Api.ReadCraftCooldowns`):
  - The profession window comes first (`C_TradeSkillUI.GetRecipeCooldown` / `GetTradeSkillCooldown`), then the spell
    cooldown, then the item cooldown (Salt Shaker).
  - A "ready" answer from a spell is believed only after the first `SPELL_UPDATE_COOLDOWN` since login, or after 20 s.
  - A group without a usable answer keeps its stored value.
  - A cast of a group spell with no cooldown reported uses the group's fallback duration, marked as an estimate.
- Modules:
  - `Core/Data/CraftCooldowns.lua`: groups, record, validation, clock conversion.
  - `Core/Game/Api.lua`: reading from the game. `Core/Game/Events.lua`: when to read, `/ps cd`.
  - `Core/View/Model.lua`: tiles, crafter states, the whisper target, time formats.
  - `UI/CooldownGrid.lua`: the grid. `UI/Window.lua`: the mode. `UI/DevProbe.lua`: fake data.

## Localization
Only group keys and numbers travel. Craft names come from the viewer's client: the recipe's spell name or the crafted
item's name, and "Transmute" from the addon's translation. Profession names come from Names. All UI texts go through
`Text` (enUS + deDE).

## Limits and known issues
- Only the Classic / Forever cooldowns in `CraftCooldowns.GROUPS`. Their recipe ids, spell ids and durations are not
  confirmed in game yet (`/ps cd`).
- A crafter without the addon, or on a version before 1.4.0, shows as "no cooldown data yet" (`?`). So does a crafter
  whose client could not read the cooldown.
- The time left is as exact as the transit delay of the answer (seconds). A long wait in the send queue adds to it.
- The sweep length uses the group's known duration, because the game does not tell other clients when the cooldown
  started.

## Changelog line
- New Cooldowns mode in Misc Items: grid of timegated crafts with cooldown sweep, ready glow, crafter tooltip and click-to-whisper (protocol 2.8, schema 9).
