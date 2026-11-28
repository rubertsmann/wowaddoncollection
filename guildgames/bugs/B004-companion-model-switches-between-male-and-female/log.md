# B004 Companion model switches between male and female: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <REPORT|TRIAGE|REPRO|HYPOTHESIS|ROOTCAUSE|FIX|TEST|VERIFY|BLOCKED|CLOSED|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-28 13:03 | REPORT | Bug created
- Did: scaffolded `bugs/B004-companion-model-switches-between-male-and-female/` from the templates
- Result: bug.md has an empty report
- Evidence: n/a
- Next: fill the Report section from the user's words, then hunt (code path, journal, offline repro)

## 2026-11-28 13:05 | ROOTCAUSE | disp is always 0; SetCreature picks a look per load
- Did: added the read-only probe `/ggd caught gender` (Api.GenderProbe); the user ran it on several NPCs and on a male and a female of NPC 1564
- Result: GetDisplayInfo is 0 after SetUnit, real after SetCreature; NPC 1564 loaded 4462 (female) and 4461 (male); the unit's model file differs by gender
- Evidence: evidence/gender-probe.md
- Next: failing test for the catch keeping the caught creature's look

## 2026-11-28 13:06 | REPRO | offline: a male catch gets the female look
- Did: tests/test_roster.lua "each catch keeps the look ..." and "a companion without a look gets one once ..."
- Result: FAIL "the caught male keeps the male look: expected 4461, got 4462"; FAIL "attempt to call field 'WithoutDisplay'"
- Evidence: luajit tests/run.lua -> 237 passed, 2 failed
- Next: fix in AzeCaught (throw/recordCatch/sanitizer) and Catcher (capture, migration)

## 2026-11-28 13:09 | FIX | catch keeps the caught look; old companions get one stable look
- Did: Core/Game/Catcher.lua (CaptureDisplay fallback, CreatureDisplay, FillDisplays, /ggd caught look), Core/Minigames/AzeCaught.lua (throw display, recordCatch, sanitizeCompanion, SetDisplay, WithoutDisplay, PickDisplay), Core/Minigames/Arena.lua (fighter look), UI/CompanionModel.lua (temporary model.load log), CHANGELOG
- Result: offline green; the load sanitizer used to overwrite the companion's look with the collection's on every login (fixed too)
- Evidence: luajit tests/run.lua -> 240 passed, 0 failed
- Next: in-game (user): /reload, wait 10 s, check an old companion stays the same; catch a male and a female of NPC 1564; then read found.display / catch / model.load / companion.display.fill from the dev SavedVariables

## 2026-11-28 13:14 | VERIFY | old companions got one look; the display path draws; no errors
- Did: the user reloaded twice and opened the pet view; read the dev SavedVariables journal
- Result: all 6 companions without a look got one at login (FillDisplays, tries=1 each); the pet view loaded by display id with a model file; nameplate capture matched the unit's model; the user: "stays the same"; no ERROR/WARNING since 13:11
- Evidence: "companion.display.fill ... display=2562 npc=1562 tries=1 uid=u6"; "model.load ... display=2562 file=1000764 method=display npc=1562 ok=true"; "found.display ... display=4657 file=917116 matched=true npc=2547 own=false tries=1"
- Next: user catches a male and a female of one NPC (e.g. 1564); check catch display and found.display matched/tries (a reload pick on the same frame is still unproven: every match so far took 1 try)

## 2026-11-28 13:27 | VERIFY | a female and a male of NPC 1564 keep their own look
- Did: the user added a female and a male Bloodsail Warlock (NPC 1564) with /ggd caught add (now gives the companion the target's look, like recordCatch)
- Result: u8 female 4462, u9 male 4461 while the collection holds 4462; reloading the hidden model does pick again (tries=2 for 1564, tries=3 for 4505 before the match); no ERROR/WARNING
- Evidence: "found.display ... display=4461 file=1011653 matched=true npc=1564 own=false tries=1 unit=target"; "dev.add ... display=4461 ... npc=1564 npcDisplay=4462 uid=u9"; "found.display ... display=2557 file=1011653 matched=true npc=4505 own=false tries=3"
- Next: optional real catch (/ggd caught force + throw + kill) for the throw path; then remove the temporary DEBUG lines (model.load, found.display details), close as fixed, commit when asked

## 2026-11-28 13:33 | FIX | the collection's caught view showed the NPC's look for every companion
- Did: the user: "in the caught view they are both female". Core/View/Model.lua BuildRosterRows took `entry.disp` (the collection's); UI/AzeCaughtPanel.lua preview tracked only the NPC id. Rows now carry the companion's own look, the preview follows the hovered/selected companion (`previewUid`)
- Result: FAIL before "the caught row shows the male: expected 4461, got 4462"; after: 240 passed, 0 failed
- Evidence: luajit tests/run.lua
- Next: user /reload, hover and select u8 and u9 in Collection > Caught: one female, one male

## 2026-11-28 13:45 | NOTE | gender in the companion tooltip (user request)
- Did: the user: "also display their gender on the hover view". The collection entry remembers UnitSex per look (`sx = { [display] = 2|3 }`, at most 8, sanitized on load); AzeCaught.CompanionSex reads the companion's; nameplates read the look again while a companion of that NPC has a look without a known gender (WantsLook); Panel.ShowCompanionTooltip adds "Gender: male|female"; the preview's info panel uses the companion's gender
- Result: offline green; companions added before this have no gender until a creature with their look is seen (a nameplate or target of that NPC)
- Evidence: luajit tests/run.lua -> 241 passed, 0 failed ("a companion's gender is the one its look was seen with")
- Next: user /reload, target a female and a male Bloodsail Warlock once, then hover u8 and u9 in Collection > Caught (look + gender line)

## 2026-11-28 13:50 | NOTE | released in 0.16.0
- Did: removed the temporary `model.load` journal line; release 0.16.0 (the user: "clean release commit push")
- Result: shipped before the in-game re-check of the Caught view and the gender line
- Evidence: luajit tests/run.lua -> 241 passed, 0 failed
- Next: user checks Collection > Caught (u8 female, u9 male, gender line after a sighting), then close as fixed
