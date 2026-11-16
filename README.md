# TalentShare

A World of Warcraft **Forever** addon for guilds: it records each character's professions, skill ranks, known recipes
and reagents, shares them with online guild members (cached locally, so offline members stay visible), and adds a
shared crafting-order board.

* **Recipes tab** – filter by profession, search recipe or reagent names, see reagents (with how many you have), see
  who can craft it (click to whisper), request it.
* **Orders tab** – guild-wide board: requests, "I'll craft it" claims, done/cancel; everyone sees who claimed what.
  **Craft** opens the order's profession with the recipe selected, a second click crafts the ordered quantity.
* Hover a recipe icon in any list to see the recipe; click it to whisper the crafter/requester with the link typed in.
* **Notifications** – new orders for your professions (and claims/completions of your own orders) show as a number on the
  minimap button, plus a sound and a chat line; screen message and taskbar flash optional. `/ts options` to configure.
* **Find recipes by what they make** – profession dropdown, category checkboxes (head, chest, food, ...) and a free-text
  search that also matches item effects and stats ("intellect", "agility").
* **Available tab** – tradeable recipe items (patterns, plans, formulas such as "Recipe: Savory Deviate Delight") that
  guild members hold in bags, bank, reagent bank, mail, guild bank or auctions, listed automatically so nobody sells
  them elsewhere unknowingly. Anyone can call **dibs** (several players can; all are listed, oldest first; press again
  to take yours back); the owner decides and hands the item over manually. "Remove from my list" hides an offer
  locally until its owner's list changes.
* No server. Data travels over hidden guild addon messages (prefix `TShare`) and is stored in the `TalentShareDB`
  SavedVariable.

## Download

CurseForge (manual uploads for now): https://legacy.curseforge.com/wow/addons/guild-talentshare
(screenshots: https://legacy.curseforge.com/wow/addons/guild-talentshare/screenshots)
Source: https://github.com/rubertsmann/talentshare-ordering-system

## Install (manual)

Run `powershell tools/package.ps1`, unzip `dist/TalentShare-<version>.zip` into
`World of Warcraft\_forever_\Interface\AddOns\`. For development: `powershell tools/deploy.ps1` links the repo as a
separate **TalentShare-Dev** addon (own data, prefix and `/tsd`), so it runs next to the live `TalentShare`;
`powershell tools/deploy.ps1 -InstallLive` also installs the newest `dist` zip as the live addon.
Re-run `tools/deploy.ps1` after every change to `TalentShare.toc` (the dev TOC is a generated copy) and restart the game.

## Use

`/ts` (or the minimap button) opens the window. Click each profession icon at the top right of the Recipes tab once so the recipes are read.
`/ts offers` (what the item scan sees; `/ts offers scan` forces a scan), `/ts scan`, `/ts dump`, `/ts chars`, `/ts comm`, `/ts hello`, `/ts debug [n]`, `/ts version`,
`/ts export` (diagnostic report to copy for the addon author; also the **Debug** tab), `/ts trace [n] [problems]`, `/ts ident`,
`/ts locale <code>|auto` (UI language, then `/reload`), `/ts i18n` (what the client reports),
profession icons at the top right of the Recipes tab (one click opens that profession and reads its recipes),
`/ts clean` then `/ts clean confirm` (deletes everything stored locally). In the dev build use `/tsd`.
The UI is available in English and German; profession and recipe names always follow your own game client.

## Develop

* Offline tests (pure logic): install LuaJIT (`winget install DEVCOM.LuaJIT`), then `luajit tests/run.lua`.
* `dev/TalentShareProbe` (`tools/deploy.ps1 -WithProbe`, `/tsp`, `/reload`) records which APIs exist on the client into
  `WTF\...\SavedVariables\TalentShareProbeDB.lua`.
* Architecture and task breakdown: `eval/plan.md`. Verification status: `docs/status.md`.
* New work is planned, logged, verified and documented per feature under `features/` (see `features/INDEX.md` and
  `.claude/skills/feature-workflow/SKILL.md`).

## Trust model

Any guild member running the addon can create/claim/close orders and can only publish **their own** character record
(and their own offers and dibs: nobody can set or remove another player's dib).
There is no authentication beyond guild membership, but nothing from outside the guild is processed: only guild
messages and whispers from guild-roster members are accepted, and all received data is validated before it is stored or shown.

## Compatibility

Everyone in the guild should run the same TalentShare **major** protocol (shown by `/ts version`, e.g. `protocol 2.0`).
A different minor still syncs; a different major does not, and you get a one-time notice that a guild member runs a newer or
older version. Saved data written by a newer addon is never overwritten by an older one. Rules and history: `docs/protocol.md`.
