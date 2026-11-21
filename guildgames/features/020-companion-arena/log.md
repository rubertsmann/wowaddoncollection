# 020 Companion arena: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-21 01:43 | PLAN | Feature created
- Did: scaffolded `features/020-companion-arena/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-21 01:58 | BUILD | arena built (T1-T5)
- Did: user: "using the skill create a fully new async battle system for the companion - use the stats system and level system and make them trainable - keep track of wins and loss - let them bet - let them bet against who is winning let the person who has been requested accept or decline the fight. Implement depth but fully hands off auto battler", then "dont stop till the fighting system is fully implement" (decisions in spec.md). New Core/Minigames/Arena.lua (fighter, training, levels, deterministic battle with 9 abilities, odds, record section + sanitizer, challenge/answer/bet/settle, persistence), UI/ArenaView.lua (Fighter and Fights pages, replay with models, health bars, floating damage, shakes, burst). Core/Data/Games.lua: SetSection("arena"), arena dropped alone. Core/Game/Catcher.lua: ArenaTick every 5 s (training done, settlement, chat notices), PublishArena, /gg arena. UI/AzeCaughtPanel.lua: 4th tab, Challenge box + arena W/L in the Guild view, Panel.CreateModel/ShowModel shared. Init: protocol 1.2. TOC: Arena.lua, ArenaView.lua. deDE: 98 keys. Balance pass (see Decisions). Docs: doc.md, verify.md, protocol.md, README, CHANGELOG, INDEX. Ran deploy.ps1 (dev TOC).
- Result: built; offline verified; needs the game and a second player.
- Evidence: luajit tests/run.lua -> "133 passed, 0 failed" (new tests/test_arena.lua: 7 tests; test_load drives the arena view: train, accept, watch, steps, tick + settlement)
- Next: user: restart the game (TOC changed), run the in-game checklist in verify.md; then a fight with a guild member on this build (MULTI-CLIENT row).

## 2026-11-21 02:01 | BLOCKED | in-game and two-player verification
- Did: everything that can run offline is built and tested (afe97cb). The remaining verify.md rows (R9-R11 look in game, MC two real players) need the WoW client and a second guild member; Claude cannot start or drive the game. The requested PC sleep timer was refused by the permission check (not worked around).
- Result: waiting on the user.
- Evidence: luajit tests/run.lua -> "133 passed, 0 failed"
- Next: user: restart the game, run the in-game checklist in verify.md (/ggd arena, train, challenge a guild member on this build, accept, bet, watch); report or /reload so the journal (arena.* lines) can be read from SavedVariables.

## 2026-11-21 06:53 | DEVIATION | guild view fight rework (challenge modal) and dev dummy (R10, R12)
- Did: user feedback: the guild view's wager box, Challenge button and status overlapped. `UI/AzeCaughtPanel.lua`: a click selects a pet (selected highlight), one fight icon on the preview model (only for another member's pet, pulses in), `Panel.SelectGuildRow`, `Panel.Challenge` opens the modal; the old box/button are gone. `UI/ArenaView.lua`: `BuildChallenge`/`OpenChallenge`/`ShowChallengeStep`/`ChallengeNext`/`ChallengeBack`/`ReadWager`/`SetWager` (matchup, wager presets + custom, confirm, sent; step track; shake on a refusal). `Core/Minigames/Arena.lua`: `DummyRecord`, `DummyRespond`, `DummyChallenge`; Settle no longer refunds a settled fight. `Core/Game/Catcher.lua`: dev `/ggd arena dummy [off]`, `/ggd arena request [gold]` (also under `/ggd caught`), the dummy answers on the arena tick. 18 deDE keys; the unused "Challenge" key removed. Tests: dummy flow + refund guard (test_arena), modal steps and the fight icon (test_load; the widget stub now keeps text).
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "134 passed, 0 failed"
- Next: user: /reload (no TOC change), `/ggd arena dummy`, AZEcaught > Guild: click the dummy, the fight icon, go through the modal; `/ggd arena request 1` and accept under Arena > Fights; watch after 5 minutes. Then the in-game rows in verify.md.

## 2026-11-21 07:20 | BUILD | one fight at a time, Stop a challenge, dummy button (R13, R12)
- Did: `Core/Minigames/Arena.lua`: `Arena.Busy`; Challenge refuses "busy"/"theybusy", Answer(accept) refuses "busy"; `Arena.Withdraw` (`ch.wd`, sanitized, an answer counts only before it; state "withdrawn"); Settle refunds the challenger and a late accepter once, and takes a refund back when an earlier accept turns up; the dummy ignores stopped challenges; `MAXIMUM_OPEN` removed. `UI/ArenaView.lua`: Accept/Decline/Stop buttons in each fight row, Stop in the details, "stopped" state, refusal texts, the challenge modal checks busy at step 1, dev button "[dev] Dummy challenges me" (`Catcher.DevArenaRequest`). docs/protocol.md, doc.md, spec.md (R13), 5 deDE keys (+1 removed).
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload; Arena > Fights: "[dev] Dummy challenges me", Accept in the row; challenge the dummy from the Guild view, Stop it in Fights; then the in-game rows in verify.md.

## 2026-11-21 07:35 | BUILD | tick / X icons instead of Accept/Decline and Yes/No
- Did: user: "replace annehmen oder ablehnen with X or tick icons on the whole addon". `UI/Window.lua`: `Widgets.CreateIconButton(parent, "accept"|"decline", size, tooltip, onClick)` (ReadyCheck tick / X, hover tint, grey when disabled, the word in the tooltip). Used for the arena row and detail Accept/Decline and the companion switch Yes/No (`UI/AzeCaughtPanel.lua`); those were the only accept/decline buttons in GuildGames.
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload and look at the icons (Arena > Fights with "[dev] Dummy challenges me"; Collection > Make companion).

## 2026-11-21 07:50 | BUILD | dev icon tools: dummy challenge and fight now
- Did: user: "replace the dev dummy challenge me with a button icon that indicates debug add - also add a button to reduce the timer there for the anticipated fight". `UI/Window.lua`: icon kinds "debug" (wrench) and "skip" (stopwatch) with a "dev" tag; `UI/ArenaView.lua`: both icons bottom left of the Fights page (dev build only, tooltips). `Core/Minigames/Arena.lua`: `Arena.SkipDummyWait` / `Arena.skipped` (memory only, only fights with the dummy: decided now). `Core/Game/Catcher.lua`: `/ggd arena skip`, `Catcher.DevArenaSkip`.
- Result: offline suite green.
- Evidence: luajit tests/run.lua (see the commit)
- Next: user: /reload; Arena > Fights: wrench, tick, stopwatch, Watch.

## 2026-11-21 08:05 | BUILD | replay model animations: attack, hurt, death
- Did: user: "for the animated fight - on each damage play the attack or getting hurt animation - and play the dead animation once at 0 hp". `UI/ArenaView.lua`: `ArenaView.ANIMATION` (AnimationData ids: attack 16-19, ability cast 52/51, hurt 9/8, critical 10, dodge 20/11, stun 14, ready 26/0, death 1, dead 6; the first the model has), `PlayAnimation` (back to ready after 0.45 s, newest wins), `PlayDeath` (once per replay, then lying), per-model state in a weak side table; Step: attacker attacks/casts, target flinches or dies at 0 health, DoT flinch, dodge, stun; Skip/finish: a knocked-out loser dies too. test_load: the models act, death once, a dead model stays dead.
- Result: offline suite green; the ids are the standard client ids, NOT-VERIFIED in game per creature model.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload; dummy fight (wrench, tick, stopwatch), Watch: check the attack/hurt/death look; report models that stand still (journal model.* lines).

## 2026-11-21 07:30 | BUILD | the Guild list moved into the Arena
- Did: user: "move the gilde tab into arena next to fights". `UI/AzeCaughtPanel.lua`: top views Companion, Collection, Arena; the guild list is built into `ArenaView.widgets.guildPage` (shifted below the page buttons, 10 rows); `Panel.RefreshGuild`; `SelectView("guild")` (old saved setting) opens Arena > Guild. `UI/ArenaView.lua`: pages Fighter, Fights, Guild; the 0.5 s tick skips the Guild page. GamesTab pointer text + deDE.
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload; Arena > Guild: list, preview, fight icon, challenge modal; then the in-game rows in verify.md.

## 2026-11-21 07:33 | BUILD | Guild is the first Arena page
- Did: user: "make gilde the first tab of the three". `UI/ArenaView.lua`: pages Guild, Fighter, Fights; the Arena opens on Guild by default.
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload; check the Arena page order; then the in-game rows in verify.md.

## 2026-11-21 07:37 | BUILD | Guild page: stat badges, name on top, no bottom note
- Did: user: "remove the text from the bottom of the gilde screen ... only displaying icons + numbers for the stats - display the name ... on the top of the model". `UI/AzeCaughtPanel.lua`: the pay note is gone (its text is now the Level badge's tooltip); `Panel.BuildStatBadges` / `Panel.GuildStats`: 8 badges (level with rarity edge, hearts, arena wins, losses, food, water, petting, energy; asleep: "Zz", greyed) with tooltips, fading in on a new pet; the pet's name (rarity colour) above the model. 3 deDE keys.
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload; Arena > Guild: click another pet, check badges, tooltips, the name and the fight icon placement.

## 2026-11-21 07:42 | BUILD | fight icon below the badges; need bars with icons
- Did: user: "bellow the stat bar - also adjust the begleiter tab ... only icons ... instead of the text futter wasser streicheln energie". `UI/AzeCaughtPanel.lua`: the Guild page's fight icon is centered below the stat badges; the Companion view's need bars show the care icon (food, water, petting, sleep) instead of the name (name in the tooltip), the bar is wider (BAR_WIDTH 170 -> 210).
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload; check the Companion bars and the Guild page fight icon.

## 2026-11-21 07:47 | BUILD | fight replay overlay: opaque, owners at the bottom, only Close
- Did: user: "make the semi transparent background fully opaque - display the owner name on the bottom ... Remove the überspringen button and center the schließen button". `UI/ArenaView.lua` buildReplay/Watch: background alpha 1; the owner names moved from behind the pet names to the bottom of each side (`part.owner`, above the floor line); Skip button removed (deDE "Skip" removed); Close centered. `ArenaView.FinishReplay` stays (the replay's own end and tests).
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload; watch a fight: check the overlay.

## 2026-11-21 07:54 | BUILD | long pet names fit the UI
- Did: user: "long pet names also sometimes break the ui either dynamically scale the text size or limit it". `UI/Window.lua` `Widgets.FitText` (one line, the font shrinks to a minimum of 70-85 %, the rest is cut by the width); `Core/Base/Utility.lua` `Utility.ShortText` (UTF-8 character limit with "…") for names inside multi-line texts. Used for: Companion name line, Collection rows and preview, Guild preview name, Arena fighter name, replay names and winner line, challenge matchup texts. Tests: test_store_and_locale (ShortText), test_load (FitText sizes).
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "137 passed, 0 failed"
- Next: user: /reload; look at a pet with a long name in each view.

## 2026-11-21 08:00 | BUILD | train icon, level line fits
- Did: user: "replace the trainieren text button with a icon - also dynamically scale the Arenastufe x and XP to fit the same line". `UI/Window.lua` icon kind "train" (Spell_Nature_Strength, gold); `UI/ArenaView.lua` stat rows use it (the full cost tooltip stays); the "Arena level x  a/b XP" line uses Widgets.FitText (down to 65 %).
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "137 passed, 0 failed"
- Next: user: /reload; Arena > Fighter.

## 2026-11-21 08:06 | BUILD | arena guide arrow (once)
- Did: user: "similar to the first catch arrow display a arrow on arena -> then on the first non you pet and then next to the fight button and then never display it again". `UI/AzeCaughtPanel.lua`: `Panel.GuideStep/AdvanceGuide/GuideTarget/UpdateGuide`, a bobbing red arrow (UI-MicroStream-Red, rotated for left/right): above the Arena tab -> (above the Guild page button if another page is open) -> right of the first visible guild row that is not mine -> left of the fight icon; steps end on: opening the Arena, clicking another member's pet, opening the challenge from the fight icon; then `ui.arenaGuide = "done"` (UI settings, per character). Only with a companion. `Panel.Refresh` split into `RefreshView` + `UpdateGuide`; ArenaView.Refresh updates it too.
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "137 passed, 0 failed"
- Next: user: /reload; follow the arrow once; check its position at each step.

## 2026-11-21 08:11 | BUILD | busy-message wording; Accept greyed out while my fight is planned
- Did: user: "remove the hint ability to stop accepted fights": the busy text is now "One fight at a time: wait until your current fight is over." (+deDE). User: "grey out the accept button on the fights tab when there is a active planned fight": `UI/ArenaView.lua` RefreshFights sets `state.busy` (Arena.Busy, outgoing: an open fight or my waiting challenge); the row tick and the detail Accept are disabled (grey) and their tooltip is the busy text.
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "137 passed, 0 failed"
- Next: user: /reload; with a planned fight, have the dummy challenge you: the tick is grey.

## 2026-11-21 08:14 | BUILD | no Accept/Decline below the fight details
- Did: user: "when you highlight a fight request in the bottom left there is a accept and deny button remove that". `UI/ArenaView.lua`: the detail acceptButton/declineButton are gone; Accept/Decline stay in the fight's row. test_load checks they are not built.
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "137 passed, 0 failed"
- Next: user: /reload; Arena > Fights: select a request.


## 2026-11-21 08:19 | NOTE | release 0.3.0
- Did: version 0.3.0 in GuildGames.toc, Init.lua fallback and CHANGELOG (protocol 1.2, schema 2); tag guildgames/v0.3.0; dist zip via tools/package.ps1.
- Result: released on request (user 2026-11-21: "commit and push everything - and create a new version").
- Evidence: luajit tests/run.lua -> 137 passed, 0 failed
- Next: in-game check of the Arena UI (guide arrow, badges, icons, replay layout); nothing of it is verified in the client yet.
