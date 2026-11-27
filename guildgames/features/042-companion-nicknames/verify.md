# 042 Companion nicknames: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 198 passed, 0 failed (with the uncommitted 041 work in the tree)
Result after work:    `luajit tests/run.lua` -> 217 passed, 0 failed

Test names below are from `tests/test_nickname.lua` unless marked.

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | 1-24 characters, cleaned, empty clears | "input is trimmed...", "24 characters, counted as characters not bytes", "set and clear..." | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| R2 | survives reload / sanitizer, gone with release | "the load-time sanitizer keeps nickname and origin...", "two companions with the same nickname..." | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| R3 | nickname shown locally (pet view, panel, roster, confirm, chat) | roster rows test (Model); UI sites switched (grep: no raw `companion.n` display left except the species preview and dev output) | READ-ONLY | `Core/View/Model.lua`, `UI/*.lua` | needs in-game | 2026-11-27 |
| R3a | fights: nickname, species on hover | `TeamDialog.AddFighterName`, replay `nameHover`, team line | READ-ONLY | `UI/TeamDialog.lua`, `UI/ArenaView.lua` | needs in-game | 2026-11-27 |
| R3b | ids are the reference | "two companions with the same nickname stay apart...", fight history test, `test_arena.lua` settle asserts `mi`/`ti` | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| R4 | once-only rule (named, empty refused; dev clear) | "only once; a second name or an empty one is refused...", "the dev clear frees it again..." | OFFLINE | suite 217/0 | pass | 2026-11-27 |
| R4 | Rename button, box with tick and cross, name click, `/gg caught name` | `Panel.RefreshRosterRename` and friends, `Panel.BuildRename`, `commands.name` | NOT-VERIFIED | | needs in-game | |
| R5 | guild sees `nk`, cleaned on receipt | "guild section: ... nk ...", "arena: a fighter carries nk ...", "guild rows: a peer's nickname shows ..." | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| R5 | ...between two real clients | | NOT-VERIFIED | | needs two guild members | |
| R6 | roster sort by shown name, ties by uid | "roster order uses the shown name, ties by uid" | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| R7 | catch time + map stamped (throw and trap) | "catch origin: time and map...", "a trap catch records it too", "companions from before ... have none" | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| R8 | origin text in tooltips | "origin text: date and zone, date only, or not recorded" (Model); tooltips not run | OFFLINE (text) / NOT-VERIFIED (UI) | suite 215/0 | partly | 2026-11-27 |
| RF1 | peer `nk` with escapes / 500 bytes | "guild section ... bad nk is dropped alone", "arena ... peer's bad nk" | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| RF2 | UTF-8 safe length | "24 characters, counted as characters not bytes" (umlauts, 4-byte emoji) | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| RF3 | sanitizer must carry `info` | "the load-time sanitizer keeps nickname and origin..." | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| RF4 | edit box releases the keyboard | `EndRename` on Enter/Escape/focus lost; `OnHide` clears focus | READ-ONLY | `UI/AzeCaughtPanel.lua` | needs in-game | |
| RF5 | `nk` never changes the fight | "arena: ... the fight ignores it" (same winner and event count) | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| RF6 | same nickname twice | "two companions with the same nickname stay apart" | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| RF7 | no map -> catch still works | "an unknown map still catches; the time is kept" | OFFLINE | suite 215/0 | pass | 2026-11-27 |
| RF8 | map call allowed in combat | `Api.PlayerMapID` through `read` (pcall, secret check) | NOT-VERIFIED | | needs in-game catch in combat | |

## In-game checklist (things only the user can do)
- [ ] `/console scriptErrors 1`, `/reload`. Catch an NPC in the open world (in combat). Expected: no error and no "reserved for the Blizzard UI" dialog. `/gg caught log 5` shows the catch.
- [ ] Open the companion view and hover over the name. Expected: "Caught <today> in <zone>" (zone in the client's language) and "Click to give it a nickname."
- [ ] Click the name, type `Rex`, press Enter. Expected: the name line, pet view tooltip, minimap tooltip and chat say Rex, and hover shows the species. Press Escape on a second try: nothing changes, and you can move your character again.
- [ ] Collection > Caught: select a companion without a nickname. Expected: **Rename** above **Make companion**, Release below that. Click it: a text box with a tick and a cross takes its place. Cross: back to the button. Tick with an empty box: "Type a nickname first." in red, and the box stays open. Type `Fang`, tick: chat line, the row shows Fang, and the button is gone for that companion (still there for an unnamed one).
- [ ] Select another companion while the box is open: the box closes.
- [ ] `/gg caught name Max` on a named companion: "It already has its nickname: a companion is named once." 25 characters are refused with a message.
- [ ] Dev: `/ggd caught unname` frees the selected companion's name; the Rename button comes back.
- [ ] `/reload`: the nickname and origin are still there. A companion caught before this build says "Caught: before this was recorded".
- [ ] Dev build: `/ggd caught arena dummy`, start a fight. Expected: the team picker rows, the cards and the replay show the nicknames ("Dummy 1..3" for the dummy), and hover shows the species.
- [ ] With a second guild member on the same build: their guild list and fight cards show your nickname.

## Accepted gaps
- none yet
