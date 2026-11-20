# 018 AZEcaught: spec

- Status: verifying
- Created: 2026-11-20
- Target version: GuildGames 0.2.0 (protocol 1.1, schema 2)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
AZEcaught: catch hostile NPCs you kill in the open world and raise one of them as a 3D companion that needs food,
water, petting and sleep (counted in play time). The care is paid from the GuildGames money pool, and the guild ranks
everyone's current companion. The weekly rank pays money back into the pool.

## Requirements
Catching
- R1: Every hostile NPC you fight (it has you on its threat list: target, nameplate or `UNIT_THREAT_LIST_UPDATE`; the
  combat log is FORBIDDEN for addons on this client, see Decisions) is added to the collection as **found**:
  NPC id, name, highest level seen, classification, display id when known.
- R2: When a hostile NPC is at or below `THROW_HEALTH` (35%) health, a catch icon appears on its nameplate (and on the
  target frame when there is no nameplate). The icon is the "rope throw". It can also be triggered with the
  **AZEcaught: throw rope** keybind or `/gg catch` (works in macros, e.g. `/target X` + `/gg catch`). The throw is
  bookkeeping only: no spell, no item, no target change.
- R3: A throw is armed for `CATCH_WINDOW` = 3 s. If that NPC is seen dead inside the window (`UnitIsDead` on whatever
  unit shows its GUID: `UNIT_HEALTH` plus a 0.2 s `UnitTokenFromGUID` poll while a throw is armed), one catch roll is
  made. Health hidden by the client (a secret in combat/instances): the icon follows the target and the roll uses
  `THROW_HEALTH` (worst case); a hidden level counts as the player's level. Only one roll per GUID, and the throw cooldown is 3 s.
- R4: Catch chance = `BASE` x `healthFactor(h)` x `difficulty`, capped at `MAXIMUM_CHANCE`.
  - `healthFactor(h) = 1 - ln(1 + 99h) / ln(100)` (h = health fraction at the throw, 0..1): 1.0 at 0 HP, ~0.48 at 10%,
    ~0.26 at 30%, ~0.23 at 35%. This is logarithmic and rises sharply near 0 HP.
  - `difficulty` = rarity factor (normal 1.0, elite 0.6, rare 0.5, rare elite 0.35, world boss 0.15) x level factor
    (`clamp(1 - 0.05 * (npcLevel - playerLevel), 0.25, 1.25)`).
  - Starting values: `BASE` 0.15, `MAXIMUM_CHANCE` 0.25. The numbers are tunable constants pinned by tests.
- R4a: The **first catch roll** a character ever makes always succeeds (`db.caught.firstCatchDone`, user 2026-11-20).
  `/ggd caught add` does not use it up.
- R5: A successful catch marks the collection entry **caught** (a caught count when caught more than once) and pays a
  catch reward into the money pool: `CATCH_REWARD` (2g) x `1 / difficulty` (harder catch, bigger reward).
- R6: The collection is a scrollable list of every found NPC, caught ones first. Not-caught entries are greyed out. Each
  row shows name, level, rarity, times caught and a small model preview on hover.

Companion
- R7: Exactly one caught NPC can be the **active companion**. Selecting another one starts it fresh (needs full,
  hearts 0, streaks 0). If the outgoing companion has **negative hearts, it runs away**: it loses its caught mark and
  stays in the list as found.
- R8: The companion is shown as a 3D model (`DressUpModel:SetDisplayInfo(displayId)`, fallback
  `SetCreature(npcId)`; same approach as fpvcigarette's Dancer). It plays idle and emote animations, and right-drag
  turns it.
- R9: Four needs, each a bar 0..100 with threshold marks (**ok** above 50, **needy** 25-50, **critical** below 25).
  The interval is the care schedule: full to needy takes the interval, full to empty twice that.
  - hunger: needy after `FOOD_INTERVAL` (2 h)
  - thirst: needy after `WATER_INTERVAL` (1 h)
  - affection: needy after `PET_INTERVAL` (2 h)
  - energy: needy after `AWAKE_INTERVAL` (4 h awake); sleeping for `SLEEP_DURATION` (1 h) refills it. Hunger, thirst and
    affection fall at half speed while it sleeps, and it can't eat or drink while asleep.
- R10: Needs only change during **active time** (while you are logged in). Logging out freezes everything. Elapsed time
  is counted by the addon (a 1 s ticker on `GetTime()` deltas, stored in seconds), not from wall-clock differences
  between sessions.
- R11: Care actions are plain buttons:
  - Feed: costs `FOOD_PRICE` (50s) from the pool and fills hunger.
  - Water: costs `WATER_PRICE` (25s) and fills thirst.
  - Pet: free, fills affection.
  - Sleep / Wake: free; the companion sleeps for at least `SLEEP_DURATION` of active time, or until you wake it.
  Each action plays a short particle effect (reuse `UI/Animate.lua`) and an emote animation on the model when the client
  has one. A paid action is refused when the pool is short.
- R12: Hearts (red heart icon + counter):
  - +1 for each need cared for while it was needy (25-50).
  - +2 when it was ok but due within 10 minutes.
  - -1 for every `NEGLECT_STEP` (10 min) of active time with any need critical, so the counter can go negative.
  A **fed streak** (consecutive feedings before hunger went critical) and a **care streak** are shown next to it. The
  care streak counts **at most one care action per hour** of play time (`CARE_STREAK_GAP`, user 2026-11-20). A
  need reaching 0 resets its streak.
- R13: Death: if hunger or thirst stays at 0 for `STARVE_TIME` (2 h of active time), the companion dies. It loses its
  caught mark (it stays found), the active slot is emptied, and a chat line says so.
- R14: The minimap button shows a badge (icon tint + count) when a need is needy or critical. Its tooltip lists each
  need's bar, the time until it is due, and the schedule ("water every 1 h, food every 2 h, sleep 1 h every 4 h"). A
  setting (checkbox in the AZEcaught panel, `/gg notify on|off`) turns the badge and the chat reminders off.

Money pool
- R15: One **money pool** (balance, in copper) shared by every GuildGames game:
  - balance = `STARTING_GRANT` (20g) + the all-time net of coin + slots + survivor + catch rewards + weekly payouts -
    care spending.
  - The balance is shown in the window header on every game panel.
- R18: **Stakes are limited by the balance** in every casino game (coin flip, slots, survivor): a stake above the
  balance is refused with a new refusal `"funds"` and a message, and the stake box can't go above it. A survivor stake
  is booked at the start (as today), so it counts against the balance right away. A player whose balance is 0 or below
  can't bet until a catch or a weekly payout tops it up. Existing players keep their history, so a player with a big
  past loss can start below 0.

Guild
- R16: An **AZEcaught** game tab in GuildGames (an icon in the game switch like the other games) with three views:
  **Companion** (model, bars, hearts, care buttons), **Collection** (R6) and **Guild**.
  - Guild view: a scrollable list of every guild member's current companion (model on hover/selection, name, level,
    rarity, hearts, need bars), sorted as a leaderboard by companion level.
  - Companion level = `npcLevel + RARITY_BONUS[classification] + hearts` (normal 0, elite +5, rare +10, rare elite +15,
    world boss +25). Negative hearts lower it. Only current companions are ranked.
- R17: Weekly payout: when the ISO week changes (the first time the client runs in the new week), you are paid into
  your own pool according to your place in last week's ranking: 1st 500g, 2nd 300g, 3rd 150g, any other member with a
  companion 25g. The ranking uses each member's **peak companion level of that week**, stored per week in the record, so
  being offline at the week change does not matter. Payout runs once per week (stored key). Last week's winner is shown
  like in the other games.

Stats, collection and UI additions (user, 2026-11-20)
- R21: **Hover info panel** (reworked 2026-11-20 after "convoluted"): hovering the companion model (or the collection
  preview) shows a tooltip-style panel BESIDE the model, so the companion stays visible:
  - header: name in its rarity colour; "Level 36 · Elite · Beast (Wolf)" (no "Normal")
  - values: only the values the game told (health, power, gender), and one line counting the hidden ones
  - needs: care icon, interval, and "(more often)"/"(less often)" coloured against the normal schedule; "never" grey
  - thresholds in one line; traits as short sentences
- R22: **Needs from stats**: every found NPC keeps its readable stats (`st`: creature type id/name, family, max health,
  power type/max, gender). Its need intervals and thresholds come from them (`AzeCaught.Profile`):
  - creature type factors: beast, dragonkin, demon, elemental, giant, undead/mechanical (never thirsty), critter,
    aberration
  - power type: mana, rage (thresholds +5), focus, energy
  - rarity: thresholds +3/+3/+5/+8
  - unknown stats: the base schedule. Bars show the companion's own threshold marks; a need it never has shows "never".
- R23: **Collection sections**:
  - **Caught**: at most `MAXIMUM_CAUGHT` = 10, duplicates count. A full list refuses the throw (and a kill after the
    list filled gets no roll); a companion that dies or runs away frees a place.
  - **Seen**: every fought enemy with its highest level, highest first; at most `MAXIMUM_SEEN` = 100 uncaught, the one
    seen longest ago makes room.
  - A click only selects a row. The **Make companion** button opens a confirm dialog "Stats will be reset" (plus the
    run-away warning for negative hearts).
- R24: **Rope icon**: round, above the nameplate (not over the level), gold ring while armed.
  - Its glow grows and turns from red (just below 35% health, the worst chance) to green (near 0 HP); yellow when the
    health is hidden (`ThrowQuality`/`QualityColor`).
  - **One throw per enemy** (`thrown`, kept 10 min).
  - The icon can be turned off, moved and resized: Options > AddOns > GuildGames AZEcaught, or
    `/gg caught icon on|off|x|y|size|reset`. Clamped and journaled; the key binding still works when it is off.
  - A throw plays in two parts that never need the target's screen position (the client hides it from addons: see
    below): the rope leaves the player (screen centre, 42% height) on an arc up and away and fades; then the lasso
    tightens and bursts ON the target, in a 1x1 pin frame anchored to its nameplate (one anchor, like the rope icon),
    18 px below the plate. The pin lets go of the plate 0.9 s later. No nameplate or a refused anchor: the landing
    plays where the rope faded ("front").
    - What the client refuses (journal 2026-11-20): world positions of enemies (`UnitPosition`: hidden), range
      checks against enemies in combat, measuring a nameplate ("Can't measure restricted regions ... Lua Taint") and a
      line ending on one ("Line:SetEndPoint(): Not allowed to depend on NamePlate1"). The camera-projection version
      (ProjectToScreen/ThrowGeometry) therefore always landed in the middle and was removed (user 2026-11-20).
    - Each effect journals `throw.effect` with mode (nameplate | front) and why; the dev build also prints it in chat.
- R25: **Care buttons**: icons with the price below. They are greyed out while unusable (`AzeCaught.CareAvailability`,
  the reason in the tooltip; petting a full companion counts as not needed) and locked for 1.5 s after a click (a
  cooldown sweep shows it).
- R26: The model returns to its idle pose (sleep pose while asleep) 2.5 s after an action, after every model load and
  whenever the menu shows.
- R27: **Combat stats** (user 2026-11-20, display only): every found NPC shows Attack, Defense and Speed in the hover
  info panel ("Combat" group). Calculated, never stored or sent (`AzeCaught.CombatStats(npcId, entry)`):
  (10 + 2 x level) x rarity (normal 1, elite 1.5, rare 1.4, rare elite 1.8, world boss 3) x creature type weight
  (attack/defense/speed: beast 1.1/0.9/1.3, demon 1.3/0.9/1.0, undead 1.0/1.3/0.7, mechanical 0.9/1.4/0.8, others 1)
  x a fixed +-15% spread per stat from a hash of the NPC id (Park-Miller, no bit library). The same NPC shows the same
  numbers to everyone; a formula change applies to every NPC at once. Not used by any game rule yet.
  - Each stat shows its number and a bar (red attack, blue defense, green speed). A full bar is the base of a normal
    level-60 NPC (`COMBAT_REFERENCE_LEVEL`, `CombatScale()` = 130); a stronger NPC shows a full gold bar.

Debugging (user, 2026-11-20: "anything can be actually debugged with hard manual and automatic logs")
- R19: Automatic logs. Every AZEcaught step writes one structured line (LibGuildSync Log format
  `LEVEL [caught.<area>] message :: key=value ...`) to a **dedicated journal** `db.caught.journal` (newest 400 lines,
  so combat noise can't push casino lines out of `/gg debug`). WARNING and ERROR lines also go to the main log.
  Logged steps and the values each line carries:
  - throw: guid, npc, hp%
  - roll: chance and each factor, the random value, the result
  - first found
  - catch, reward
  - select / switch / run-away / death, with the full state
  - every care action: before/after bars, cost, balance
  - every threshold crossing, with the need and its new zone
  - every heart change and its reason
  - neglect steps, starve timer
  - tick clamps (RF2)
  - pool movements: ledger entries carry the reason and the balance after
  - funds refusals
  - weekly payout: week, rank, peak, amount, or why nothing was paid
  - model load result: display id / npc fallback / failure
  - sanitize drops of peer `caught` sections
  - every caught Lua error, through `Log.Protected`
  A state snapshot line every 5 min of active time makes the decay reconstructable.
- R20: Manual debugging, `/gg caught <sub>` (English, diagnostic):
  - `state`: every stored and derived value of the companion
  - `log [n] [filter]`: the journal, with a text filter
  - `wallet`: balance breakdown + the last ledger entries
  - `chance`: catch-chance breakdown for the current target
  - `collection`: counts + the last found
  - `verbose on|off`: echo every journal line to chat live
  - `probe`: spikes S1-S3
  - `export`: the state as one copyable line
  - `dump [unit]`: everything the client tells about a unit (default target); the same dump is taken at every throw and
    logged on a catch (`catch.dump`), user 2026-11-20
  Dev build only: `time <minutes>` (fast-forward active time), `give <gold>`, `catch` (force the next roll),
  `need <name> <0-100>`, `week` (simulate the week change).
  The pure modules take their clock and random function as parameters, so every bug report can be replayed offline from
  `export` + journal.

## Non-goals
- No real spell, item, gold or target manipulation. Addons can't cast or catch.
- No needs while logged out (decided 2026-11-20, "at the moment").
- No cap on a balance carried over from existing history (a past big loss can start a player below 0; see R18).
- No cheat protection beyond shape/bounds validation: members can cheat (decided 2026-11-20).
- No own 3D assets: only the game's creature displays.
- No trading or gifting companions between players.

## Design
- Files
  - `Core/AzeCaught.lua` (new, pure): constants; catch chance; collection; companion state machine (`Tick(state, dt)`,
    `Care(state, action, pool)`, `Select`, death/run-away); hearts and streaks; companion level; weekly payout.
    Clock-free: active time is passed in.
  - `Core/Wallet.lua` (new, pure): pool balance = casino net (from `Games` totals) + ledger
    `{ earned, spent, payouts }`; `Wallet.Spend` / `Earn`.
  - `Core/Games.lua` (changed): `Games.ORDER` gains `"caught"`; `refusal()` gains `"funds"` (stake > balance, R18) for
    `Flip`, `RecordPlay` and the survivor start. Sanitizer for the record's new `caught` section.
  - `Core/Api.lua` (changed): the only WoW calls: nameplate unit/GUID, `UnitHealth`/`Max`, `UnitClassification`,
    `UnitLevel`, `CombatLogGetCurrentEventInfo`, NPC id from GUID.
  - `Core/Catcher.lua` (new, client): CLEU listener (found + kill), throw arming, nameplate icon pool
    (`NAME_PLATE_UNIT_ADDED/REMOVED`, `UNIT_HEALTH`), display-id capture via a hidden `DressUpModel:SetUnit(unit)` +
    `GetDisplayInfo()`.
  - `Core/Events.lua`, `Core/Init.lua` (changed): 1 s active-time ticker, `/gg catch`, `/gg notify`, binding globals.
  - `Bindings.xml` (new): `AZECAUGHT_THROW` -> `addon.Catcher.Throw()` (a non-secure binding, OK because it only does
    bookkeeping).
  - `UI/AzeCaughtPanel.lua` (new): the three views, model, bars with threshold ticks, heart counter, buttons, effects.
  - `UI/GamesTab.lua`, `UI/Window.lua` (changed): game icon/label, pool in the header, minimap badge + tooltip.
  - `Core/Model.lua` (changed): guild companion rows, collection rows (escape peer text).
  - `Locales/enUS.lua`, `deDE.lua`: new strings.
- Data shape (SavedVariables, schema 2)
  - `db.caught = { collection = { [npcId] = { n, lvl, cls, disp, seen, caught } }, active = CompanionState|nil,
    activeSeconds, ledger = { earned, spent, payouts }, paidWeek, notify = true }`
  - CompanionState = `{ npc, lvl, cls, disp, since(activeSeconds), hunger, thirst, affection, energy, asleepUntil,
    hearts, fedStreak, careStreak, starve, neglect }`
  - Bounds: collection at most 2000 entries; names at most 48 bytes, UTF-8 safe.
- Message shape: the GameRecord gains an optional section `caught = { c = {npc, lvl, cls, disp, n, hearts, hunger,
  thirst, affection, energy, asleep}, weeks = { [periodKey] = peakLevel } }`, (no `wallet` field: the balance stays local; DEVIATION 2026-11-20).
  - Old 1.0 peers drop unknown keys in `Games.Sanitize` (allow-list copy), so the change is additive: protocol 1.1.
  - Peers show the model from `disp` (fallback `npc`).
- Pure logic lives in AzeCaught, Wallet, Games, Model. WoW calls only in Api, Catcher, Events and UI.
- Spikes (in-game, before building on them):
  - S1: does 16001 have `DressUpModel:GetDisplayInfo()` after `SetUnit(nameplateN)`? If not, use `SetCreature(npcId)`
    only, which needs the creature cached.
  - S2: animation ids for eat/drink/sleep/pet on creature models (idle 0, eat ~61; probe with `/ggd anim`).
  - S3: can a plain button be shown on a nameplate and clicked in combat without taint? (Fallback: show the icon
    without a click and use the keybind/macro.)

## Tasks
- [~] T1 (S): (probe built as /gg caught probe; needs the user in game) Spikes S1-S3 as a dev probe (`/ggd caught probe`), with results in log.md. Verify: user runs it in game
  (BLOCKED until then; T2-T7 can go ahead offline).
- [x] T2 (M): `Core/AzeCaught.lua` catch math (healthFactor, difficulty, chance cap, one roll per GUID, 3 s window) +
  collection add/merge. Verify: `tests/test_azecaught.lua` catch cases.
- [x] T3 (L): companion state machine: needs decay by active time, sleep, care actions, hearts/streaks, starve death,
  run-away on switch, select/reset. Verify: test_azecaught companion cases (simulated hours).
- [x] T4 (M): `Core/Wallet.lua` pool + ledger, spend refusal, catch reward, weekly payout (once per week, ranking by
  peak level). Verify: `tests/test_wallet.lua`.
- [x] T5 (M): schema 2 migration + `caught` section sanitizer + protocol 1.1, plus a mixed 1.0/1.1 record test. Verify:
  test_store_and_locale, test_games_sync.
- [x] T6 (S): Model rows: guild companion leaderboard (companion level order, ties by name), collection rows, escaped
  names. Verify: test_games_model.
- [~] T7 (M): (built; in-game check open) `Core/Catcher.lua` + Api: CLEU found/kill, throw arming, nameplate icon, `/gg catch`, `Bindings.xml`.
  Verify: test_load stubs + in-game.
- [~] T8 (L): (built; in-game check open) `UI/AzeCaughtPanel.lua`: Companion/Collection/Guild views, model, threshold bars, heart, buttons, effects,
  emotes. Verify: test_games_ui + in-game screenshots.
- [~] T9 (S): (built; in-game check open) header pool display, minimap badge + schedule tooltip + notify toggle. Verify: test_games_ui + in-game.
- [x] T11 (M): R18 stake limit: `"funds"` refusal in Games (coin, slots, survivor start) with the balance in the message
  (the boxes are NOT clamped: DEVIATION, the refusal text is enough); was: stake boxes clamp to the
  balance; message. Verify: test_coinflip / test_slots / test_survivor funds cases + in-game.
- [x] T12 (M): R19/R20: `Core/AzeCaught.lua` journal (a LibGuildSync Log instance on `db.caught.journal`, WARN/ERROR
  mirrored to the main log), `/gg caught` commands, dev cheats, snapshot line. Verify: test_azecaught "journal" cases
  (each step writes its line, verbose echo, filter).
- [x] T10 (S): locales enUS/deDE, README, CHANGELOG, protocol.md, doc.md. Verify: locale key test.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: Kill credit for a GUID that was never thrown at, or a second death event for the same GUID -> no roll, one roll
   at most. Pinned by: T2.
2. RF2: Huge `dt` (client hang, laptop sleep while logged in; `GetTime()` jump) -> clamp each tick to 5 s, so 8 h
   asleep in a loading screen doesn't kill the companion. Pinned by: T3.
3. RF3: Pool short for food while hungry -> refusal message; the companion still decays (it can die). No negative
   spending. Pinned by: T3/T4.
4. RF4: Peer record with a huge `hearts`, a bad `disp`, a name with `|` codes, or 10 000 weeks -> clamped or dropped,
   escaped, and no model error (pcall around `SetDisplayInfo`). Pinned by: T5/T6.
5. RF5: Week change while offline for 3 weeks -> paid once, for the last completed week only (or not at all when that
   week isn't in the record). Pinned by: T4.
6. RF6: Balance exactly equal to the stake / one copper short / negative from history -> allowed / refused / refused,
   and a refused play changes nothing (no rev bump, no record). Pinned by: T11.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: additive 1.0 -> 1.1 (`PROTOCOL_MINOR = 1`). Old peers drop the `caught` key in the
  allow-list copy.
- [x] Stored data: `Store.SCHEMA` 1 -> 2. The migration adds an empty `db.caught`; downgrade guard unchanged.
- [x] Trust model: unchanged (members are trusted and can cheat); peer `caught` section bounded (level 1..200,
  hearts -100000..100000, bars 0..100, ids positive integers < 2^31, week keys validated); names escaped.
- [x] Localization: NPC names come from the client (shown as is, escaped). Only ids and numbers are stored/sent, apart
  from the NPC name (bounded). UI text goes through `L`.
- [x] Load order: Wallet after Games, AzeCaught after Wallet, Catcher after Api; `Bindings.xml` is loaded by the client
  automatically (not in the TOC); UI panel after GamesTab.
- [x] Packaging: `tools/package.ps1` must include `Bindings.xml` (check its file list).
- [x] Tests: new `tests/test_azecaught.lua`, `tests/test_wallet.lua`; adversarial: RF1-RF5.
- [x] Docs: README (game + money pool), CHANGELOG 0.2.0, docs/protocol.md 1.1, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-20 Q1 throw: a clickable nameplate icon, a custom keybind, and a macro-able command.
- 2026-11-20 Q2 chance: logarithmic in remaining health (higher near 0 HP), scaled by difficulty (elite / rare
  "silver" / raid boss / higher level). The R4 formula and numbers are Claude's proposal.
- 2026-11-20 Q3 collection: every hostile NPC you fought is listed (found); caught ones are marked.
- 2026-11-20 Q4 offline: needs run only during active (logged-in) time, for now.
- 2026-11-20 Q5 neglect: hearts go down; hungry (or thirsty) too long -> it dies and is removed from caught.
- 2026-11-20 Q6 care: plain buttons; food and water are bought from the casino money pool, petting and sleep are free;
  a catch pays a small reward; a particle effect and an emote (if available) per action.
- 2026-11-20 Q7 level: rarity + hearts + NPC level, current companion only.
- 2026-11-20 Q8 switching: allowed and resets; switching away from a companion with low (negative) hearts makes it run
  away.
- 2026-11-20 Q9 trust: members can cheat; accepted.
- 2026-11-20 Q10 money: AZEcaught is how you earn more money; weekly payout by leaderboard place.
- 2026-11-20 3D models: fpvcigarette's method (`DressUpModel` + `SetDisplayInfo(CreatureDisplayInfo id)`; addons
  can't load their own models).
- 2026-11-20 Name: the game is called **AZEcaught** (feature folder renamed to 018-azecaught).
- 2026-11-20 Claude: "low hearts" for running away = hearts < 0.
- 2026-11-20 User: the care streak (Pflegeserie) counts at most one care action per hour. Claude: play time (like the
  needs), any action counts, the fed streak and hearts are not limited.
- 2026-11-20 User: hover overlay with all known info; intervals and thresholds generated from the stats. Claude: the
  trait table in R22 (proposal, tunable in Core/AzeCaught.lua TYPE_TRAITS / POWER_TRAITS / RARITY_PICKY).
- 2026-11-20 User: collection sections caught (max 10) and seen (limited, highest level); switching via a button with a
  "Stats will be reset" confirm. Claude: duplicates count toward 10, seen limit 100 uncaught (oldest makes room),
  full -> throw refused.
- 2026-11-20 User: rope icon higher (it covered the level), round, with a throw effect from the player to the target.
  Claude: addons cannot place 3D effects in the world, so the effect is drawn on the screen.
- 2026-11-20 User: care buttons as icons, greyed out when unusable, small click cooldown. Claude: 1.5 s; petting at
  >= 95% is "not needed" like feeding (it was allowed before and let the care streak be farmed).
- 2026-11-20 Client fact (in-game block): this client (World of Warcraft Retail x86_64 1.60.1.70959, Forever) forbids
  addons the combat log: registering COMBAT_LOG_EVENT_UNFILTERED shows "reserved for the Blizzard UI" at load. It also
  hands out secret values (issecretvalue) in combat/instances. AZEcaught now reads units only (Spoken_Bosses' pattern),
  every read through Api.NotSecret. tests/test_load.lua forbids the combat log in any file and pins secret handling.

- 2026-11-20 OQ1: AZEcaught is the game tab's name inside GuildGames; the addon keeps its name.
- 2026-11-20 OQ2: "you cannot input more than you actually have": the balance limits every casino stake (R18).
- 2026-11-20 OQ3: starting grant 20g.

## Open questions
- OQ4: Spikes S1-S3 (display id capture, emote animation ids, nameplate click in combat). (needs: game)
