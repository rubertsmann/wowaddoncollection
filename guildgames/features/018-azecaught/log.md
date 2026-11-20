# 018 AZEcaught: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-20 17:01 | PLAN | Feature created
- Did: scaffolded `features/018-tamagotchi-companion/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-20 17:01 | PLAN | open questions
- Did: feature-workflow skill copied from talentshare/.claude/skills to the wowaddons root (.claude/skills, ids now unique across addons); scaffolded 018 in guildgames; draft R1-R10 in spec.md from the user's request.
- Result: 10 open questions asked in chat: (1) catch trigger/protected-click, (2) catch odds and what drives them, (3) collection seen vs caught + dupes, (4) needs schedule while offline/logged out, (5) neglect consequences, (6) care actions UX, (7) companion level formula, (8) switching/reset abuse, (9) sync + trust, (10) fun extras / stakes.
- Evidence: n/a (planning)
- Next: record the answers under spec.md Decisions, then write Design, Tasks and the cross-cutting checklist.

## 2026-11-20 17:14 | DECISION | answers to the 10 questions, name AZEcaught
- Did: recorded the user's 10 answers under spec.md Decisions; renamed the folder 018-tamagotchi-companion -> 018-azecaught (INDEX.md updated); read fpvcigarette/Dancer.lua for the 3D model method (DressUpModel + SetDisplayInfo); wrote R1-R17, design (Core/AzeCaught.lua, Core/Wallet.lua, Core/Catcher.lua, UI/AzeCaughtPanel.lua, Bindings.xml), T1-T10, RF1-RF5, the cross-cutting checklist (protocol 1.1 additive, schema 2).
- Result: plan complete except OQ1-OQ3 (name scope, pool limiting casino stakes, starting balance) and in-game spikes S1-S3.
- Evidence: spec.md
- Next: get OQ1-OQ3 from the user, then T2 (tests first: tests/test_azecaught.lua).

## 2026-11-20 17:17 | DECISION | OQ1-OQ3 answered
- Did: spec.md: AZEcaught = game tab inside GuildGames; new R18 (balance limits every casino stake, refusal "funds"), T11, RF6; starting grant 20g in R15.
- Result: plan complete; only the in-game spikes S1-S3 (OQ4) remain open, and they block T7/T8 only.
- Evidence: spec.md Decisions
- Next: T2 (tests first: tests/test_azecaught.lua catch math), then T3, T4, T11, T5, T6 offline; T1 probe for the user.

## 2026-11-20 17:20 | DECISION | hard manual + automatic logs, start implementation
- Did: user asked that everything be debuggable with hard manual and automatic logs and to start implementing; added R19 (journal + mirrored warnings/errors, every step logged with its values, 5-min snapshot) and R20 (/gg caught state|log|wallet|chance|collection|verbose|probe|export + dev cheats), T12. Funds check (R18) goes into play starts only (Flip, Slots.Spin, Survivor.Begin), never into RecordPlay, so a settle can never be refused.
- Result: Phase 2 starts.
- Evidence: spec.md R19, R20, T12
- Next: T2/T3/T4/T12 in Core/AzeCaught.lua + Core/Wallet.lua, tests first.

## 2026-11-20 17:28 | BUILD | T2-T5, T11, journal part of T12 (pure modules)
- Did: new guildgames/Core/AzeCaught.lua (journal on db.caught.journal, catch math, collection, throw/roll, companion state machine, care, hearts/streaks, death, run-away, record section + sanitizer, weekly payout, persisted-state sanitizer, export line) and guildgames/Core/Wallet.lua (pool = 20g grant + casino net - pending survivor stake + ledger). Games: optional "caught" record section (bad section dropped alone), Games.SetSection, refusal "funds" via Refusal(name, stake, checkFunds) in Flip / Slots.Spin / Survivor.Begin only (never in RecordPlay, so settles always book). Store.SCHEMA 2 (+ migration 1->2), PROTOCOL_MINOR 1. TOC + generated dev TOC + tests/run.lua list the two files. New tests/test_azecaught.lua (21 cases), tests/test_wallet.lua (4); existing tests updated for schema 2 / minor 1 / the stake limit.
- Result: two bugs found by the tests and fixed: SanitizeSection skipped nil checks (pairs skips nils) so 1e12 hearts passed; spec numbers of the health curve were wrong for 1+9h -> switched to 1 - ln(1+99h)/ln(100) (0.48 at 10%, 0.26 at 30%), spec R4 updated.
- Evidence: luajit tests/run.lua -> "94 passed, 0 failed"
- Next: T6 Model rows (guild companion leaderboard, collection rows), then T7 Core/Catcher.lua + /gg caught commands (T12), T8 UI.

## 2026-11-20 17:40 | BUILD | T6-T10, T12 client side, docs
- Did: Model rows (BuildCompanionRows, BuildCollectionRows, CompanionWinner); Core/Api.lua unit/combat-log reads; new Core/Catcher.lua (combat log found/death, nameplate rope icon, throw via icon / AZECAUGHT_THROW binding / /gg catch, 1 s active-time ticker, publish, reminders, weekly payout, /gg caught state|log|wallet|chance|collection|verbose|notify|export|probe + dev add|time|give|force|need|week); new Bindings.xml; new UI/AzeCaughtPanel.lua (Companion/Collection/Guild views, DressUpModel per fpvcigarette, threshold bars, heart counter, care buttons with Burst/FloatText/emotes, run-away confirm); GamesTab: AZEcaught in the switch, balance in the header, "funds" text; Window: minimap badge + schedule tooltip; 77 German strings; TOC + dev TOC; tools/package.ps1 ships and checks Bindings.xml; README, CHANGELOG (Unreleased), docs/protocol.md 1.1, doc.md, verify.md.
- Result: need timing corrected to the user's schedule (interval = full to NEEDY, so water every 1 h, not 30 min; spec R9 updated); zone tolerance for float drift. test_load now drives the panel, every /gg caught command (live + dev), ticker and tooltip and fails on any ERROR log line.
- Evidence: luajit tests/run.lua -> "95 passed, 0 failed"
- Next: user runs the in-game checklist in verify.md (deploy.ps1 + game restart first). Results of S1-S3 decide follow-ups.

## 2026-11-20 17:40 | DEVIATION | packaging check overwrote the 0.1.0 zip; no wallet field on the wire
- Did: ran tools/package.ps1 to check Bindings.xml ships; it wrote dist/GuildGames-0.1.0.zip over the released zip (TOC still 0.1.0, dist/ is gitignored). Rebuilt it from HEAD (guildgames/ and libguildsync/ unchanged since the 0.1.0 merge) in a temporary worktree and copied it back (38 files, no AZEcaught files). Memory note added: never package unreleased work.
- Result: 0.1.0 zip restored with the 0.1.0 content (byte-identical not guaranteed: zip timestamps). The balance is NOT sent in the record (spec design said "wallet"); not needed by any requirement.
- Evidence: zip listing 38 entries without Wallet/AzeCaught/Bindings
- Next: in-game checklist (see entry above).

## 2026-11-20 18:17 | BLOCKED | in game: "GuildGames-Dev was blocked: the function is reserved for the Blizzard UI"
- Did: user reported the client's ADDON_ACTION_FORBIDDEN dialog. Checked evidence on disk: SavedVariables GuildGames-Dev.lua last written 2026-11-19 23:35 (game still running, nothing saved yet), Logs/taint.log is from 2026-11-16 (taintLog off). Bytecode check: no accidental global writes (no GSET) in Core/ or UI/; only _G.GuildGamesAzeCaughtThrow and the two BINDING_* labels. Static reading found no direct call of a protected function. Added instrumentation instead of a guessed fix: Core/Events.lua logs ADDON_ACTION_FORBIDDEN / ADDON_ACTION_BLOCKED for this addon (function name, combat state, debugstack, last 3 journal steps) to the journal + /gg debug.
- Result: root cause unknown until the function name is known. Hypotheses to check against it: (a) the rope icon anchored to a nameplate / clicked in combat (S3), (b) PlayerModel:SetUnit on a nameplate unit (S1 capture), (c) the key binding path.
- Evidence: luajit tests/run.lua -> "95 passed, 0 failed"
- Next: user: /console taintLog 1, /reload, reproduce, note WHEN it appears, /reload again; then I read Logs/taint.log and the SavedVariables (/ggd debug 10).

## 2026-11-20 18:26 | BUILD | root cause: combat log is forbidden on this client; unit watching instead
- Did: evidence: client is "World of Warcraft Retail x86_64 1.60.1.70959" (Logs/gx.log); no installed addon uses the combat log; Spoken/OpenMap/Spoken_Bosses guard issecretvalue and Spoken_Bosses watches deaths via UNIT_HEALTH + UnitIsDead + UnitTokenFromGUID. Core/Catcher.lua registered COMBAT_LOG_EVENT_UNFILTERED at file load = the instant "reserved for the Blizzard UI" block (pcall cannot stop it; the Events.lua logger loaded later and the log was not loaded yet). Fix: removed the combat log (Api.CombatLogEvent, Catcher.OnCombatLog); found = threat list (UNIT_THREAT_LIST_UPDATE, target); death = CheckDeath on UNIT_HEALTH + PollThrows (0.2 s, UnitTokenFromGUID) for armed throws, "no death was seen" journaled; Api reads every unit value through Api.NotSecret (hidden -> nil); Throw with hidden health rolls at THROW_HEALTH, hidden level counts as the player's level (bug found by the new test: a hidden level was 1 = easier). Blocked-action logging moved into Core/Init.lua (first file) with an in-memory buffer flushed after ADDON_LOADED and an immediate chat line naming the function.
- Result: tests first failed (combat log scan, secret snapshot, hidden-health throw), now pass. No protected calls remain (client globals listed from bytecode).
- Evidence: luajit tests/run.lua -> "98 passed, 0 failed"
- Next: user /reload in game (no new files, no deploy needed); expect no dialog. If any block remains, chat names the function; then in-game checklist in verify.md.

## 2026-11-20 18:50 | DECISION | care streak at most once per hour
- Did: user: "Pflegeserie should only be limited to one action per hour". Core/AzeCaught.lua: CARE_STREAK_GAP = 3600 s of play time; companion.streakAt = active seconds of the last counted action (persisted, sanitized); Care journals streakCounted and streakIn; Describe (/gg caught state, export) shows streakIn. Fed streak and hearts unchanged. Test first: tests/test_azecaught.lua "the care streak grows at most once per hour of play time" (failed 3 vs 1, now passes); the old care test now expects 1.
- Result: spec R12 + Decisions, README, CHANGELOG updated.
- Evidence: luajit tests/run.lua -> "99 passed, 0 failed"
- Next: in game: /reload, then the verify.md checklist.

## 2026-11-20 18:55 | BUILD | catch dump: all unit information into the journal
- Did: user asked for a helper log with all available information when catching. Core/Api.lua Api.UnitDump(unit): ~40 reads (name, levels, classification, creature type/family, race, sex, faction, reaction, class, health/max, power type/power/max, attack/threat/combat/dead/tap/boss flags, armor, attack power, damage, speed, resistance, UnitStat 1-5 as base/effective/buff/debuff, zone, subzone, map id, player level); each value as text or "secret"/"missing"/"error"/"nil". Core/Catcher.lua: dump taken at the throw (the dead unit is often gone), logged as caught.catch.dump with chance/roll/reward on a catch, released after 60 s; /gg caught dump [unit]; /ggd caught add logs it too. Tests first (test_load: dump values incl. secret/missing/error; catch dump line), both failed, now pass.
- Result: README, spec R20 updated.
- Evidence: luajit tests/run.lua -> "100 passed, 0 failed"
- Next: in game: /reload, /ggd caught dump on a hostile NPC, catch one, /ggd caught log 1 catch.dump; the "missing"/"secret" values tell which real stats this client offers for NPCs.

## 2026-11-20 18:58 | DECISION | the first catch always succeeds
- Did: user: "make the first catch successful as an extra rule". Core/AzeCaught.lua OnDeath: while db.caught.firstCatchDone is not set, the roll is a catch (result.first, journal first=true); the flag is set on any successful catch, persisted and sanitized (true or nil). /ggd caught add does not set it. Chat adds "(Your first catch always succeeds.)" (deDE added); /gg caught state shows firstCatchDone. Test first: "the very first catch roll succeeds, later rolls use the chance" (failed, now passes); fresh() in the tests marks it used so the other rolls stay deterministic.
- Result: spec R4a, README, CHANGELOG updated. In the user's dev data the flag is unset (only dev add so far), so the next real catch roll succeeds.
- Evidence: luajit tests/run.lua -> "101 passed, 0 failed"
- Next: user /reload, throw at an NPC and kill it within 3 s -> caught + catch.dump in the journal.

## 2026-11-20 19:00 | BUILD | the model returns to idle after an action and when the menu shows
- Did: user: "the model always goes into idle animation after an action and when the menu shows". Causes: the action emote was never ended (looping emotes stayed), and the model reload on show is asynchronous (an animation set before the load finishes is lost; no OnModelLoaded handler). UI/AzeCaughtPanel.lua: Panel.PrepareModel (OnModelLoaded -> idle), Panel.IdleOfCompanion (sleep animation while asleep, else stand 0), Panel.ShowIdle (on show + 0.3 s later for clients without OnModelLoaded), a 2.5 s "back to idle" timer after each action with a token so a newer action or the menu showing voids older timers (tokens in a weak table, not on the frame). Previews idle on load too. Test first in test_load (fake model records animations; timers run by hand): emote -> idle, loaded -> idle, shown -> idle, asleep -> sleep animation, stale timer ignored.
- Evidence: luajit tests/run.lua -> "101 passed, 0 failed"
- Next: user request: hover overlay with the known NPC information + need intervals and thresholds generated from the stats.

## 2026-11-20 19:12 | BUILD | stats -> needs, hover overlay, collection sections, rope icon + throw effect, icon care buttons
- Did: five user requests while building (2026-11-20), each test-first:
  (1) stats: Api.UnitStats (type id/name, family, max health, power type/max, gender; secrets skipped), stored per found NPC (entry.st, merged, sanitized); AzeCaught.Profile/ProfileOf/ZoneOf/DecayPerSecond(need, companion): intervals and thresholds from type/power/rarity; Care/Tick/badge/tooltip/bars use the companion's profile; a never-needed need shows "never". Bug found by a test: a reload rebuilt zones with the default thresholds (fixed: ZoneOf in the sanitizer).
  (2) hover overlay (UI/AzeCaughtPanel.lua createInfoOverlay/attachInfoOverlay) over the companion model and the collection preview; lines from Model.BuildNpcInfoLines.
  (3) collection: Caught (MAXIMUM_CAUGHT 10, duplicates count, throw refused when full, no roll when it filled before the kill) and Seen (all, highest level first; MAXIMUM_SEEN 100 uncaught, oldest makes room); a row click selects; Make companion -> confirm dialog "Stats will be reset" (+ run-away warning).
  (4) rope icon: round (circle mask), above the plate, gold ring when armed; Catcher.PlayRopeEffect: screen-space rope on Animate.ArcPoint from the player to the target plate, burst + ring on landing.
  (5) care buttons: icons + price, greyed out via AzeCaught.CareAvailability (agrees with Care; petting at >= 95% now refused as not needed), 1.5 s click cooldown with a sweep; button state kept off the frames.
  45 German strings added, 5 unused removed.
- Result: spec R21-R26 + Decisions, README, CHANGELOG updated. The trait table is a proposal (tunable constants).
- Evidence: luajit tests/run.lua -> "110 passed, 0 failed"
- Next: user /reload and checks in game: icon position/roundness, throw effect, overlay text (which stats are "unknown" on this client), care icons (S2-style: do the icon paths exist on this client?), the switch dialog; /ggd caught log 30 after.

## 2026-11-20 19:27 | BUILD | throw effect aims at the enemy, one throw per enemy, chance glow, icon options, clearer info panel
- Did: (1) user: the rope effect always flew to the front. No effect line was saved yet (throws after the last save), so evidence first: screenPoint now returns why a position is unreadable (noRegion/error/hidden/notLaidOut) and the effect journals mode + reasons. Since the client lets frames ATTACH to plates (the icon works) but likely hides their positions, the effect tries the plate, then our icon, then draws a Line attached to the plate (the game places it), burst/ring anchored to the plate; "front" only without a plate. Test: hidden plate position -> mode=anchored.
  (2) one throw per enemy: AzeCaught.thrown (10 min), refusal "thrown" + chat text. (3) glow: ThrowQuality (0 at 35% HP, 1 at 0 HP, follows the health factor) and QualityColor red->yellow->green, glow size grows; yellow when health is hidden. (4) options: UI/AzeCaughtOptions.lua (new file, TOC + dev TOC) registered via Settings.RegisterCanvasLayoutCategory (fallback InterfaceOptions_AddCategory): show toggle, -/+ for x, y, size, reset, preview; /gg caught icon ...; settings in db.caught.icon, clamped, sanitized, journaled. (5) info panel rework: Model.BuildNpcInfo (header, known values only + hidden count, needs with trend vs normal, thresholds, traits) shown in GameTooltip beside the model; reviewed as rendered German text three times (fixed "1 Std. 0 Min.", lowercase threshold line, vague "Elite: wählerisch", "1 weitere Werte" plural, "Normal" noise).
- Result: all tests first or alongside; German strings added, unused removed.
- Evidence: luajit tests/run.lua -> "113 passed, 0 failed"
- Next: user: deploy is NOT needed for code, but a new file was added -> run powershell tools/deploy.ps1 and RESTART the game (the dev TOC was updated by hand already; a restart is required for new TOC files). Then throw at an NPC and /ggd caught log 5 throw.effect.

## 2026-11-20 19:31 | BLOCKED | "the effect doesn't work anymore": evidence needed from the new code
- Did: read SavedVariables (saved 19:29): it only holds the previous session (old code): every effect to=1084,535 = the old "front" fallback (plate position unreadable), confirming the first cause; no "mode=" line exists, so the new code's path is unknown. Suspect: the new "anchored" path (a Line attached to the plate) does not render on this client, so nothing is visible. Added /ggd caught effect [unit]: plays the effect at the target without a throw and prints mode, plate, line, fromWhy, toWhy (Catcher.lastEffect; also journaled).
- Evidence: luajit tests/run.lua -> "113 passed, 0 failed"
- Next: user: /reload, target an enemy with its nameplate visible, /ggd caught effect -> paste the chat line (or /reload and I read the journal). Then fix the path the evidence points to.

## 2026-11-20 20:50 | BUILD | rope effect: frame ladder instead of a Line on the plate
- Did: Core/Catcher.lua PlayRopeEffect: the "anchored" mode no longer uses a Line. A root frame spans from the screen corner to the plate centre; 63 empty bisection frames give points k/64 of the way; the rope tip/segments anchor to those with the player share + arc lift as offsets; burst/ring land on a frame at the plate. A refused anchor falls back to "front" with the reason. tests/test_load.lua: the stub client refuses lines/textures that depend on the plate (only frames may), as the client does.
- Result: root cause from the journal (20:45, 20:46 via /ggd caught effect): "Line:SetEndPoint()(): Not allowed to depend on NamePlate1" - every throw since the previous change failed, so nothing was drawn. Test was red with that exact error before the fix.
- Evidence: luajit tests/run.lua -> "113 passed, 0 failed"
- Next: user: /reload, throw (or /ggd caught effect at a target) -> rope should arc to the enemy plate; journal line throw.effect mode=anchored to=plate (frame ladder). Then IN-GAME row for R24 in verify.md.

## 2026-11-20 20:54 | BUILD | rope effect: character to character
- Did: Core/Catcher.lua PlayRopeEffect (user: "straight line again - estimate the characters position ... not the name plate"): start = estimated player character (screen centre x, 0.40 height; no player plate); end = enemy body BODY_DROP 45 below its plate centre. Only a 1x1 "pin" frame (parent UIParent, one anchor, like the rope icon) depends on the plate; the ladder root hangs from the pin. Dev build prints "rope effect: front (<reason>)" at once when it falls back.
- Result: the 20:50 save holds only old-code throws (Line error); the new-code throw that drew the straight line was not saved, so why it fell back to "front" is still unknown - the dev chat line now shows it without a reload.
- Evidence: luajit tests/run.lua -> "113 passed, 0 failed" (asserts from=character estimate, to=enemy body (frame ladder), no line/texture depends on the plate)
- Next: user: /reload, throw; if a chat line "rope effect: front (...)" appears, paste it. Else judge the arc in game (tune CHARACTER_HEIGHT / BODY_DROP).

## 2026-11-20 20:59 | BUILD | rope effect: projected by camera geometry
- Did: user: "still only in front ... the target position should be trigonometrically calculated and scale accordingly like its getting distance". Journal 20:51-20:54 showed plates are restricted regions: "NamePlate1:GetCenter(): Can't measure restricted regions ... Lua Taint: GuildGames-Dev", the icon too ("Button:GetCenter"), and the ladder anchor was refused ("ladder Int..."). Removed all plate measuring/anchoring from the effect (screenPoint, ladder, pin). New: Core/AzeCaught.lua `AzeCaught.CAMERA` + `ProjectToScreen(view, distance, bearing)` (pinhole camera, pure); Core/Api.lua `Api.ThrowGeometry(unit)` (UnitPosition+facing -> CheckInteractDistance out of combat -> 6 yd guess; secret-safe, reasons); Core/Catcher.lua `PlayRopeEffect` projects both bodies, scales tip/rope/burst/ring by depth, journals every input and prints them in the dev build.
- Result: the effect no longer touches nameplates; the landing point moves up and shrinks with distance and sideways with the bearing (when positions are known).
- Evidence: luajit tests/run.lua -> "114 passed, 0 failed" (new: projection test in test_azecaught; test_load: a plate stub that refuses every measure/anchor is never touched, ThrowGeometry position/bearing/combat cases)
- Next: user: /reload, throw at a near and a far enemy; paste the "rope effect: ..." chat lines and say where it landed vs the enemy -> tune AzeCaught.CAMERA (pitch, FOV, focus) and the guesses.

## 2026-11-20 21:10 | BUILD | dev command: /ggd caught reset [all]
- Did: user: "dev only ggd caught reset add that". Core/AzeCaught.lua `AzeCaught.Reset(withWallet)` (pure): clears collection, active companion, active time, peaks, paidWeek, firstCatchDone and the runtime throw tables; keeps icon/notify/verbose settings and the journal (a dev.reset line marks the cut); `all` also clears the ledger (casino results are guild game records and stay). Core/Catcher.lua developmentCommands.reset (dev build only; refuses when the saved data is read-only; also clears Catcher.noted/dumps, fires CAUGHT_CHANGED).
- Evidence: luajit tests/run.lua -> "115 passed, 0 failed" (new: reset test in test_azecaught)
- Next: user: /reload, /ggd caught reset -> collection empty, companion gone, icon settings unchanged.

## 2026-11-20 21:25 | BUILD | R27 combat stats (Attack / Defense / Speed)
- Did: user: "Defense / Attack / Speed calculation - according to elite / level / undead, or wild and from a calculated hash"; only for the info panel for now. Design approved ("do it"): hash of the NPC id (not the type id: all beasts share type 1). Core/AzeCaught.lua `CombatStats` + COMBAT_* constants (pure, not stored); Core/Model.lua BuildNpcInfo `info.combat`; UI/AzeCaughtPanel.lua "Combat" group above Needs; deDE: Kampfwerte, Angriff, Verteidigung, Tempo. Spec R27.
- Evidence: luajit tests/run.lua -> "116 passed, 0 failed" (tests written first and red: stable per NPC, >10 distinct values over ids 1-200, within +-15%, level/elite/world boss order, undead tougher+slower, beast faster, bad input sane; info.combat in the NPC info test)
- Next: user: /reload, hover a companion / collection preview -> Combat group; tune COMBAT_* if the numbers feel off.

## 2026-11-20 21:35 | BUILD | R27 combat stats as bars
- Did: user: "show the attack as bars e.g. something with level 60 as the base max - and then e.g. 30% of that in a bar chart". Core/AzeCaught.lua COMBAT_REFERENCE_LEVEL = 60, `CombatScale()` (130 = normal level-60 base); Core/Model.lua info.combat gets fill (capped at 1) and over; UI/AzeCaughtPanel.lua `Panel.StatBar`: number then an 80x8 inline-texture bar (WHITE8X8 with vertex colour; red/blue/green, gold when over), right-aligned so the bars line up.
- Evidence: luajit tests/run.lua -> "116 passed, 0 failed" (red first: CombatScale missing; level 15 ~30%, world boss capped + over; test_load draws the panel)
- Next: user: /reload, hover -> check the bars render (inline texture colour) and line up.

## 2026-11-21 00:15 | BUILD | rope effect: lasso lands on the nameplate, no position guessing
- Did: user (after the 019 refactor, in game): "it still lands just in the middle of the screen ... could be an unsolvable limit to prevent some kind of automation". Journal: every throw "bearing=0 distance=6.0 source=melee guess why=position hidden; interact skipped in combat" -> the client hides the enemy's position, so the projection always aimed straight ahead. User: "do it" (proposal). Core/Game/Catcher.lua PlayRopeEffect: flight from the player up and away (fades), landing (lasso ring 70->18, burst, gold ring) in a 1x1 pin frame anchored to the target's nameplate with ONE SetPoint (the pattern the rope icon already uses in game); fallback "front" when there is no plate or the anchor is refused; the pin lets go of the plate after 0.9 s. Removed AzeCaught.CAMERA/ProjectToScreen, Api.ThrowGeometry and their tests. Spec R24 and CHANGELOG updated.
- Result: the landing should appear on the real enemy; nothing measures a plate or draws a line to it.
- Evidence: luajit tests/run.lua -> "120 passed, 0 failed" (test_load: red first "expected nameplate, got projected"; stub plate refuses every measure and line; exactly one frame anchored to it; no plate -> front "no nameplate"; refused anchor -> front with the reason; the projection test was removed with the code)
- Next: user: /reload (no new file, no restart needed), throw at an enemy -> chat "rope effect: nameplate", the lasso closes on the enemy. If chat says "front (...)", paste it.

## 2026-11-21 00:30 | BUILD | rope effect: wind-up on the player, then the lasso on the target (no trail)
- Did: user: "the trails can be just removed - create the effect that first is a cool animation on the player and then after a short amount on the enemy". Core/Game/Catcher.lua PlayRopeEffect: no rope trail or flying tip; a player pin (screen centre, 42% height) plays the wind-up (rope ring 110->26, rising sparks, then a gold ring flashing out); ROPE_DELAY 0.35 s later the target pin (anchored to the nameplate, as before) plays the lasso (ring 80->18), burst and gold ring. Fallback "front": the lasso plays above the player. Removed ROPE_SEGMENTS/ROPE_RISE and UI/Animate.lua ArcPoint (no user left) with its test lines. Spec R24, CHANGELOG.
- Evidence: luajit tests/run.lua -> "120 passed, 0 failed" (test_load: still nothing measured, exactly one frame anchored to the plate, front fallbacks with their reasons)
- Next: user: /reload, throw -> wind-up on the character, then the lasso on the enemy; chat "rope effect: nameplate". Tune ROPE_DELAY / LANDING_DROP / sizes by feel.

## 2026-11-21 00:45 | VERIFY | throw effect seen in game
- Did: user threw the rope after /reload: "looks fine" -> verify.md row R24-effect IN-GAME.
- Next: remaining in-game checks (verify.md R2, R6, R8, R9 bars, R11 effects, R14, R16 needs a second player, R20 output).

## 2026-11-20 22:41 | DECISION | rope rework: lean chance, ring, arrow, fail effects (10 questions)
- Did: user: "make the catch mechanic more lean e.g. at 10% life the catch chance is 90% - with a slight malus to elite and rare mob. The icon should display the current state - going from red to green outline according to the catch chance. The icon disappearing when getting killed too slow with a small burst particle effect. Also the first catch mechanic show a glowing red arrow for the first time. Display a particle effect when it escaped or was killed too slow - ask me 10 questions". Answers in spec.md Decisions (Q1-Q10).
- Next: build.

## 2026-11-20 22:41 | BUILD | rope rework built
- Did: Core/Minigames/AzeCaught.lua: Chance(health, classification) linear 20% -> 90% (35% -> 10% health), flat below, rarity malus in points, MINIMUM_CHANCE 5%, no level; HealthFactor/Difficulty/BASE_CHANCE/MAXIMUM_CHANCE/RARITY_FACTOR removed (RARITY_MALUS is the classification set now); Reward(chance) by risk; ThrowQuality(health, classification) -> quality, best; EndLateThrows (window end = too slow, counts as rolled); NeedsThrowHint + db.caught.throwHintDone (sanitized, reset). Core/Game/Catcher.lua: StyleIcon (ring by chance, gold glow armed, pulsing glow + one MAP_PING at the best moment, tooltip chance, red bobbing arrow + one chat line), PollThrows ends late throws -> OnTooSlow, OnDeath escape -> PlayFailEffect("escape"), late -> OnTooSlow; effect pins shared (effectPins/placeOnPlate/releaseLater, one anchor each); /gg caught chance prints the new breakdown + reward; dev `effect [throw|escape|snap]`, `hint`. Locales/deDE.lua: 3 keys, "died too late" removed. README, CHANGELOG, spec R3a/R4/R5/R24/R24a/R24b, verify rows.
- Evidence: luajit tests/run.lua -> "122 passed, 0 failed" (new/changed: chance curve, rarity malus + reward, throw quality, EndLateThrows, throw hint; test_load: fail effects never measure the stub plate (nameplate/front), StyleIcon ping once + arrow until first throw; each new load assertion checked by breaking it once)
- Next: user: /reload (no new file), fight an enemy below 35%: ring colour, pulse + ping at 10%, tooltip chance; `/ggd caught hint` for the arrow; `/ggd caught effect escape|snap` and a real too-slow throw. Arrow texture UI-MicroStream-Red is unverified on this client (fallback: scroll-down arrow tinted red).

## 2026-11-20 22:50 | BUILD | /ggd reset did not reset the first catch
- Did: user: "ggd reset doesnt seem to reset first catch". SavedVariables GuildGames-Dev.lua (saved 22:42): no `caught.command` and no `dev.reset` journal line, firstCatchDone=true -> the reset never ran: `/ggd reset` is not a command (only `/ggd caught reset`), the dispatcher just listed the words. Core/Game/Catcher.lua: dev build registers `/ggd reset` as `/ggd caught reset`; the reset also clears the session ping/hint flags and says "the next catch is guaranteed again, the arrow shows until the next throw". The journal also showed the old formula (base=0.15): the rework was not loaded yet in that session.
- Evidence: luajit tests/run.lua -> "122 passed, 0 failed" (test_load: /ggd reset clears firstCatchDone and throwHintDone in the dev build; the live build has no reset)
- Next: user: /reload, `/ggd reset`, `/gg caught state` -> firstCatchDone false; throw -> arrow, then a guaranteed catch.

## 2026-11-20 22:58 | BUILD | model camera: whole body visible, mouse-wheel zoom
- Did: user: "the zoom level is sometimes too far in and the complete 3D model is not visible". UI/AzeCaughtPanel.lua set no camera at all (the client's per-model default, close-up for some creatures). New `Panel.FitCamera` after every load (showModel, OnModelLoaded, the 0.3 s late show): SetPortraitZoom(0), SetPosition(0,0,0), SetCamDistanceScale(1.35), each guarded; `Panel.ZoomModel` on the mouse wheel (0.6..4, per NPC, session only). The model load journal line carries camera/portrait/distance.
- Evidence: luajit tests/run.lua -> "122 passed, 0 failed" (test_load: fit calls, wheel limits, per-NPC memory, client without the calls)
- Next: user: /reload, open companion + collection previews with a large NPC; if still cut off, scroll the wheel and tell me the comfortable number (then MODEL_CAMERA_DISTANCE becomes that), or paste `/gg caught log 5 model`.

## 2026-11-20 23:05 | BUILD | catch-mode icon and shake before the snap
- Did: user: "camera works better - for the emblem we need another icon instead of the rope once it is in active catch mode, as well as the icon starting to shake violently shortly before breaking". Core/Game/Catcher.lua: StyleIcon swaps the picture to CATCH_ICON (Interface\Icons\Ability_Ensnare, a net; rope as fallback) while armed and back after (set once per change); the icon's OnUpdate shakes picture, ring and glow by random offsets of `ShakeAmplitude(remaining)` (0 until 1 s left, then 1 -> 5 px, quadratic); the button's nameplate anchor is never touched. Spec R24, CHANGELOG.
- Evidence: luajit tests/run.lua -> "122 passed, 0 failed" (test_load: net while armed, rope after, texture set once; amplitude 0 at >= 1 s, rising, 5 at the end; shake back in place)
- Next: user: /reload, throw and wait: net icon, shaking in the last second, then the snap. Say if the net icon does not exist on this client (it falls back to the rope) or the shake is too weak/strong.

## 2026-11-20 23:10 | BUILD | no limit on caught NPCs
- Did: user: "remove the limit on caught". Removed AzeCaught.MAXIMUM_CAUGHT (10): the "full" throw refusal, the "no roll: the caught list filled up" check, its chat text (enUS/deDE key removed), the dev `add` check; the section header reads "Caught (n)" (new key, deDE "Gefangen ({n})"); Model sections drop caughtLimit. MAXIMUM_COLLECTION 2000 stays as a bound against corrupt saved data only. Spec R23, README, CHANGELOG.
- Evidence: luajit tests/run.lua -> "122 passed, 0 failed" (test_azecaught: 100 caught, a throw and a forced roll still work, 101 after a reload; the old limit test was replaced)
- Next: user: /reload, catch more than 10.
