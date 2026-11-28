# 028 Craft cooldowns grid: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 310 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 331 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | "Cooldowns" in the Misc Items dropdown, grid instead of table, mode saved | test_load; used in the live 1.4.1 and dev builds | IN-GAME | user report 2026-11-24 ("the features are working as expected"); live log `cooldownGrid.whisper` 13:21 | pass | 2026-11-24 |
| R2 | one tile per craft, transmutes one tile; switch to one per crafter | test_craft_cooldowns_model; dev fake crafters | IN-GAME | dev log `devProbe.check key=cooldowns ok=true` 12:12, whispers from transmute, mooncloth, saltshaker tiles; user report 2026-11-24 ("the features are working as expected") | pass | 2026-11-24 |
| R3 | static group data, ids marked unverified | test_craft_cooldowns "groups well formed"; live data | IN-GAME (17187 only) / NOT-VERIFIED (rest) | live SavedVariables: a real guild member's synced recipes contain 17187 (Transmute: Arcanite), so the classic id is the Forever recipe id; other ids and the durations still need `/ps cd` with an alchemist/tailor | partial | 2026-11-24 |
| R4 | crafters = recipe knowers + record holders; no crafter -> dimmed, not clickable | test_craft_cooldowns_model; live | IN-GAME | live: the member with 17187 appears on the Transmute tile (no 1.4 record yet, so "?") and was whispered (log 13:21, 13:22) | pass | 2026-11-24 |
| R5 | owner reads own cooldowns (spell, window, item, cast fallback), keeps the old value on no answer | test_craft_cooldowns "update bumps rev only on real changes", "a seen cast sets the estimate"; the game APIs: checklist 1-2 | OFFLINE (logic) / NOT-VERIFIED (APIs) | | open | |
| R6 | send stamp `at`, receiver converts to its clock | test_craft_cooldowns "two peers 2 h apart see the same time left", "FromWire keeps the time left..." | OFFLINE | | pass | 2026-11-24 |
| R7 | states ready / cooling / unknown / estimated; offline greyed | test_craft_cooldowns_model; dev fake crafters (every state) | IN-GAME | user report 2026-11-24 ("the features are working as expected") after the dev fake data | pass | 2026-11-24 |
| R8 | best crafter, sweep, timer, badge, profession border | test_craft_cooldowns_model; dev fake crafters | IN-GAME | user report 2026-11-24 ("the features are working as expected") | pass | 2026-11-24 |
| R9 | tooltip contents | dev fake crafters | IN-GAME | user report 2026-11-24 ("the features are working as expected") | pass | 2026-11-24 |
| R10 | click whispers best with link, right-click menu, never myself | test_craft_cooldowns_model; live and dev clicks | IN-GAME | live log `cooldownGrid.whisper group=transmute` x2; dev x4; user report 2026-11-24 ("the features are working as expected") | pass | 2026-11-24 |
| R11 | effects (desaturate, sweep, flash + shine, glow, hover), no animation while hidden | dev fake crafters | IN-GAME (look) / READ-ONLY (no animation while hidden) | user report 2026-11-24 ("the features are working as expected") | pass (look) | 2026-11-24 |
| R12 | debug: /ps cd, fake crafters, 20 s cooldown, clear | test_load; dev build | IN-GAME (fake crafters) / NOT-VERIFIED (/ps cd output, 20 s trigger) | dev log `devProbe.check key=cooldowns ok=true` | partial | 2026-11-24 |
| R13 | older peers ignore crev / WANTC / CDS | test_craft_cooldowns "a 1.3-style peer ignores crev and WANTC..." | OFFLINE | live: 1.3.0 and 1.0.2 members still sync recipes ("char: up to date", "cds: peer has none"), no warnings after 12:51 | pass | 2026-11-24 |
| RF1 | garbage `at`, far-future ready times, 500 groups, unknown key | test_craft_cooldowns "sanitize rejects malformed...", "FromWire keeps the time left..." | OFFLINE | | pass | 2026-11-24 |
| RF2 | a 0 reading at login must not flip a cooling value to ready | logic in Api.ReadCraftCooldowns (`cooldownState.trusted`) + "no answer: the value stays" test; the login order of events: checklist 2 | READ-ONLY / OFFLINE (keep-value part) | | open | |
| RF3 | clocks hours apart | test_craft_cooldowns two-peer test with 7200 s skew | OFFLINE | | pass | 2026-11-24 |
| RF4 | unlearned / left the guild -> gone, pruned | test_craft_cooldowns "version reset drops peers' records, clean and prune remove them", "update ... the group goes" | OFFLINE | | pass | 2026-11-24 |
| RF5 | grid open for hours: ticker only while shown, pooled tiles | UI/CooldownGrid.lua OnShow/OnHide ticker, tile pool; checklist 6 | READ-ONLY | | open | |
| ALL | user's status review | user, live use | IN-GAME | user: "works but confusing sometimes" | pass | 2026-11-28 |

## In-game checklist (things only the user can do)
The dev build is deployed (`tools/deploy.ps1` ran; restart the game, `/reload` does not re-read the TOC). Dev commands start
with `/psd`, the live build uses `/ps`. `/console scriptErrors 1` first.
- [ ] 1. With an alchemist or tailor: open the profession window, then `/psd cd`. Expected: a "window recipe <id> ... -> transmute/mooncloth" line
  for each cooldown recipe (if it says NOT IN ANY GROUP, send me the id), "known yes", and a taken value. Send the output.
- [ ] 2. Relog with a running cooldown, wait 30 s WITHOUT opening the profession, then `/psd cd`. Expected: "spell <n>s"
  (tells whether GetSpellCooldown reports tradeskill cooldowns) and the stored value still cooling.
- [x] 3. Dev tools -> Members -> "Crafters: cooldowns in every state", then Misc Items -> Cooldowns. Expected: Transmute
  glowing with badge 1/3 and a "?", Mooncloth with a sweep and about 3h, Salt Shaker with an orange timer that runs
  out after 50 s and flashes. Screenshot please; then "One tile per crafter".
- [x] 4. Hover each tile: crafter lines with online dot, time left, ready time, "updated ... ago"; click hint.
- [x] 5. Left-click a ready tile: the whisper to the fake member opens with the craft link in the box. Right-click: menu with
  the crafters, offline ones disabled.
- [ ] 6. Triggers -> "A cooldown ends in 20 s": watch the tile flash and start glowing. Close and reopen the window (no Lua
  errors, the glow comes back).
- [ ] 7. MULTI-CLIENT: two members with 1.4.0 dev/live builds; one crafts a timegated recipe; the other sees the timer
  within a minute, with the same time left.

Still open after the user's check on 2026-11-24: 1-2 (needs an alchemist or tailor with a real cooldown: own reading,
ids, durations, RF2), 6 (20 s trigger, reopen), 7 (a second member on 1.4.x who knows a timegated recipe).
Update 2026-11-24 17:57: three members are on 1.4.1 (live SavedVariables). Their HELLO carries the cooldown field and the
answer is "cds: peer has none", which is right: none of them knows a transmute, Mooncloth or the Salt Shaker, so `cds`
stays empty. The handshake between 1.4.1 clients runs without warnings; the timer sync itself (7) is still unseen.

## Accepted gaps
- Checklist items not run one by one: closed at the user's status review (2026-11-28, "works but confusing sometimes"). The confusing part is tracked as bug B003.
