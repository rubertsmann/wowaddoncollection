# TalentShare

A World of Warcraft **Forever** addon for guilds: it records each character's professions, skill ranks, known recipes
and reagents, shares them with online guild members (cached locally, so offline members stay visible), and adds a
shared crafting-order board.

* **Recipes tab** – filter by profession, search recipe or reagent names, see reagents (with how many you have), see
  who can craft it (click to whisper), request it.
* **Orders tab** – guild-wide board: requests, "I'll craft it" claims, done/cancel; everyone sees who claimed what.
* No server. Data travels over hidden guild addon messages (prefix `TShare`) and is stored in the `TalentShareDB`
  SavedVariable.

## Install (manual)

Run `powershell tools/package.ps1`, unzip `dist/TalentShare-<version>.zip` into
`World of Warcraft\_forever_\Interface\AddOns\`. For development: `powershell tools/deploy.ps1` links the repo instead.

## Use

`/ts` (or the minimap button) opens the window. Open each profession once so recipes are scanned.
`/ts scan`, `/ts dump`, `/ts chars`, `/ts comm`, `/ts hello`, `/ts debug`, `/ts version`.

## Develop

* Offline tests (pure logic): install LuaJIT (`winget install DEVCOM.LuaJIT`), then `luajit tests/run.lua`.
* `dev/TalentShareProbe` (`tools/deploy.ps1 -WithProbe`, `/tsp`, `/reload`) records which APIs exist on the client into
  `WTF\...\SavedVariables\TalentShareProbeDB.lua`.
* Architecture and task breakdown: `eval/plan.md`. Verification status: `docs/status.md`.

## Trust model

Any guild member running the addon can create/claim/close orders and can only publish **their own** character record.
There is no authentication beyond guild membership.
