# 030 Compact pet view: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-24 18:46 | PLAN | Feature created
- Did: scaffolded `features/030-compact-pet-view/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-24 18:48 | PLAN | spec written from 10 user answers
- Did: features/030-compact-pet-view/spec.md: goal, R1-R11, design (UI/PetView.lua, Model helpers, shared Panel.Care), T1-T8, RF1-RF5, checklist, decisions
- Result: plan ready; protocol and schema unchanged
- Evidence: user answers recorded under Decisions
- Next: wait for the user's OK on the plan, then T1 (Model helpers + tests/test_pet_view.lua)

## 2026-11-24 20:41 | BUILD | T1-T8 built
- Did: Core/View/Model.lua (pet view helpers), tests/test_pet_view.lua, UI/PetView.lua (new), UI/AzeCaughtPanel.lua (Care and ClickCare take a target, shared cooldown), UI/Window.lua (SetMode, ShowFull, start mode, switch icon), UI/GamesTab.lua, UI/AzeCaughtOptions.lua (Minimal view section), Locales/deDE.lua, Core/Game/Catcher.lua (ShowFull, dev hearts), GuildGames.toc, tests/test_load.lua, README, CHANGELOG
- Result: offline green; the sim renders the view and the switch with 0 Lua errors
- Evidence: luajit tests/run.lua -> 146 passed, 0 failed; <wow-ui-sim>/petview.webp, petview-full.webp
- Next: user runs the verify.md in-game checklist 1-8 with the dev build (restart the game first)

## 2026-11-24 20:41 | DEVIATION | outline as dots, model not clipped
- Did: spec R3 and Decisions updated: a model frame cannot be masked, and two masked discs drew as one solid disc in the sim, so the outline and the rings are rings of dots
- Result: the spec matches the code
- Evidence: petview.webp before and after
- Next: in-game checklist

## 2026-11-24 20:51 | DEVIATION | smooth circles: shipped textures and a standing sweep
- Did: user saw low-res, jagged circles (3 px dot rings). New UI/Textures/Disc.tga, Ring.tga, RingThin.tga (256 px, white, anti-aliased alpha, made by a script); the outline, discs and ring tracks use them; the gauge share is a Cooldown sweep with the ring texture as swipe, reversed, standing still (duration 1e6 s); Model.GaugeRing/RingSegments replaced by Model.GaugeShare
- Result: offline green; sim renders the textures smooth at 3x; the sim does not draw cooldown swipes, so partial rings need the game
- Evidence: luajit tests/run.lua -> 145 passed, 0 failed; <wow-ui-sim>/petview.webp
- Next: user restarts the game (new texture files) and checks the rings at 20/45/80%

## 2026-11-24 21:04 | DEVIATION | ring fill from a texture of 64 drawn arcs
- Did: user: partial rings did not show in game, only the full green one (the standing Cooldown sweep draws nothing there). A half-ring rotate-and-clip version rendered wrong in the sim and could not be checked. Now UI/Textures/RingArcs.tga (512 px, 8 x 8 cells, cell n = n/64 of the ring, anti-aliased) and SetTexCoord pick the cell: Model.RingArc, Model.ArcTexCoord; the Cooldown and the clipping are gone
- Result: offline green; the sim shows 80/45/20/100% correctly (clockwise from 12 o clock, zone colours)
- Evidence: luajit tests/run.lua -> 146 passed, 0 failed; <wow-ui-sim>/petview.webp
- Next: user restarts the game (new texture file) and checks the rings

## 2026-11-24 21:06 | BUILD | tooltips hide at once
- Did: user: tooltips linger. UI/PetView.lua: the view remembers its tooltip owner; its OnUpdate hides the tooltip as soon as the mouse is off the owner (a button disabled under the mouse gets no OnLeave, so the game faded it slowly); OnHide hides it too; only our own tooltip is hidden
- Result: offline green
- Evidence: luajit tests/run.lua -> 146 passed, 0 failed
- Next: user checks in game (/reload is enough)

## 2026-11-24 21:28 | BUILD | random idle emotes
- Did: user: random emotes every few minutes instead of idling. Model.IDLE_EMOTES, IdleEmoteDelay (90-240 s), ShuffledIdleEmotes; AzeCaughtPanel.EmoteThenIdle (shared with care) and MaybeIdleEmote (awake, shown, not busy; only animations the model has); called from the pet view and the companion panel refresh; dev /ggd caught emote; README, CHANGELOG
- Result: offline green
- Evidence: luajit tests/run.lua -> 147 passed, 0 failed
- Next: user checks in game (/reload is enough): /ggd caught emote
