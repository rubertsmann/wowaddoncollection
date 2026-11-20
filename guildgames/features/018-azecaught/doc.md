# AZEcaught

Status: built, verifying | Since version: next (protocol 1.1, schema 2) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Every hostile NPC you fight goes into your collection. Throw the rope at a weak one and kill it within 3 seconds for a
chance to catch it. One caught NPC becomes your companion: a 3D model that needs water, food, petting and sleep in play
time. Care earns hearts and neglect costs them, and a companion left without food or water for too long dies. The guild
sees everyone's companion ranked by level, and the weekly rank pays money into the shared money pool. That pool also
limits every casino stake.

## How to use
- UI: `/gg` -> the beast-taming icon in the game switch -> Companion / Collection / Guild. The balance is next to the
  game switch. The rope icon appears right of a hostile nameplate at <= 35% health.
- Key binding: Options > Key Bindings > AddOns > "AZEcaught: throw rope at target".
- Commands: `/gg catch [mouseover|focus]`, `/gg caught`, `/gg notify on|off`; diagnostics
  `/gg caught state|log [n] [filter]|wallet|chance|collection|verbose on|off|notify on|off|export|probe`; dev build also
  `add|time <min>|give <gold>|force|need <name> <0-100>|week`.

## How it works
- Modules:
  - `Core/AzeCaught.lua` (pure): rules, journal, sanitizers.
  - `Core/Wallet.lua` (pure): money pool + ledger.
  - `Core/Catcher.lua` (client): found NPCs from threat lists, death watch of thrown GUIDs (unit events + poll, no
    combat log: forbidden on this client), nameplate icon, ticker, publishing, payout, commands.
  - `Core/Api.lua`: unit reads, every value through `Api.NotSecret`.
  - `UI/AzeCaughtPanel.lua`: the views.
  - `UI/GamesTab.lua`: switch + balance.
  - `UI/Window.lua`: minimap badge/tooltip.
  - `Bindings.xml`.
- Data: `db.caught` (schema 2), shapes in [docs/protocol.md](../../docs/protocol.md) section 3.
- Messages: no new message; my game record gains the optional `caught` section (protocol 1.1, additive).
- Time: a 1 s ticker adds `GetTime()` deltas (clamped to 5 s) to `activeSeconds`. Needs only change while logged in.
- Debugging:
  - Every step writes a line to `db.caught.journal` (`/gg caught log`), with all values: throws, rolls with every
    factor and the random value, care before/after, hearts with the reason, zone changes, money movements with the
    balance after, payouts with the ranking, model loads and emotes, sanitize drops.
  - Warnings and errors are mirrored to `/gg debug`.
  - A state snapshot is written every 5 min.
  - `/gg caught export` gives one line from which the state can be rebuilt offline.

## Localization
UI strings go through `Text[...]` (German in `Locales/deDE.lua`). NPC names come from the game client in the player's
language and are sent as is (bounded, escaped on display). Journal and diagnostics are English.

## Limits and known issues
- No combat log on this client: an NPC only counts as found once it has you on its threat list, and a death is only
  seen while some unit (nameplate, target, soft target, mouseover, focus) still shows it. A kill out of sight in the
  3 s window is journaled as "no death was seen" and gets no roll.
- Secret values in combat/instances: hidden health -> icon on the target only and the worst-case chance; hidden names
  and levels are filled in by a later sighting.
- Not yet run in the game client.
  - S1: whether `PlayerModel:GetDisplayInfo()` works on 16001; the fallback is `SetCreature(npcId)`, which needs the
    creature to be cached.
  - S2: the emote animation ids are guesses with fallbacks.
  - S3: the nameplate icon in combat.
- Results are self-reported (members can cheat; accepted).
- A player whose past casino losses exceed 20g starts below 0 and can't bet until catches or payouts bring the balance up.
- The weekly payout uses the records this client holds. A member whose record never arrived does not count.
- The dev and live builds both define the `AZECAUGHT_THROW` binding (the last loaded wins).

## Changelog line
- New game AZEcaught (catch NPCs, raise a companion, guild ranking with weekly pay) and a money pool shared by all games.
