# Recipe drop alerts

Status: done | Since version: 1.4.0 (unreleased) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
When a tradeable recipe drops into your bags, guild members with the addon who can learn it now are told (chat line
and/or the minimap news icon). You see who answered when you hover the recipe: up to 3 members with their current skill,
green = can learn it now, red = their skill is too low, "..." when more answered.

## How to use
- Nothing to do: loot a recipe. A chat line says it dropped; hover it (or the item in your bags).
- A member's drop you can learn: chat line with the looter's name (click it to whisper), minimap icon; hover the minimap
  button to see the drops; opening the window clears the icon.
- `/ps drops` shows the switches; `/ps drops share|chat|icon on|off` sets one. `share` off: your drops are not announced
  and you do not answer. (A grouped settings page follows in 029.)

## How it works
- Messages (protocol 2.7, docs/protocol.md section 15): `DROP {item}` on GUILD, `DROPA {item, s, r}` whispered back.
- Data: settings in `ui.drops`; drops, answers and alerts in memory for the session.
- Modules: `Core/Data/RecipeDrops.lua` (pure: settings, message checks, my drops and answers, alerts),
  `Core/Data/RecipeCheck.lua` (tooltip reading, decision; feature 026), `Core/Game/Drops.lua` (loot line -> bags ->
  announce; incoming drop -> own tooltip -> answer/alert; tooltip and chat-hover hooks; `/ps drops`),
  `Core/Net/Sync.lua` (handlers), `UI/Window.lua` (`UI.SetDropNotice`), `UI/DevProbe.lua` (dev triggers).

## Localization
Only ids, a status letter and a skill number travel. The tooltip is read with the client's own strings; all addon texts
are English with German translations.

## Limits and known issues
- Only members online with this version answer; offline members are not listed.
- Bind-on-pickup recipes and recipes without a profession requirement are not announced.
- A member's stored skill is as fresh as their last profession scan.

## Verification
See [verify.md](verify.md).
