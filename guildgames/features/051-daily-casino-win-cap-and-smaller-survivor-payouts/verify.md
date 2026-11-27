# 051 Daily casino win cap and smaller Survivor payouts: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> `218 passed, 0 failed`
Result after work:    `luajit tests/run.lua` -> `236 passed, 0 failed`

Test file abbreviations: DC = tests/test_daily_cap.lua, SV = tests/test_survivor.lua, UI = tests/test_games_ui.lua.

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | 500g net per UTC day for coin, slots, survivor | DC "a win above the limit left pays the rest only..." | OFFLINE | `232 passed, 0 failed` | pass | 2026-11-28 |
| R2 | playing goes on, a win above the limit pays the rest only, losses cost the stake | DC "playing goes on at the limit..." | OFFLINE | same run | pass | 2026-11-28 |
| R3 | record keeps the real result, wallet books a `cap` entry | DC "a win above the limit left..." (record won 1200g, pool +500g, `cap` -700g) | OFFLINE | same run | pass | 2026-11-28 |
| R4 | shared across games, a loss makes room (net) | DC "the limit is shared by coin, slots and survivor", "a loss first raises what may be won back" | OFFLINE | same run | pass | 2026-11-28 |
| R5 | Survivor 105/110/120/140%, endless 105% +5%/min up to 130%, min net 1c | SV "targets pay 105 to 140 percent...", "survivor endless: 105% at 1:00..." | OFFLINE | same run | pass | 2026-11-28 |
| R6 | `tower` field, old `survivor` kept as history in the pool | DC "tower section: a survivor win nets 1c..stake; the old survivor field..." | OFFLINE | same run | pass | 2026-11-28 |
| R7 | coin/slots refuse `run` while a stake is pending; reload settles with the limit; 0.13 `factor` converted | DC "run refusal...", SV "survivor endless: never ends by time..." (factor 64 -> 130%, 4 -> 110%, 65 rejected) | OFFLINE | same run | pass | 2026-11-28 |
| R8 | free play (stake 0) stores nothing in all three games | DC "free play: stake 0 draws a result and stores nothing in every game" | OFFLINE | same run | pass | 2026-11-28 |
| R9 | no run past 8:00 (200 seeded runs x 3 strategies) | SV "survivor frenzy: every run ends..." | OFFLINE | same run | pass | 2026-11-28 |
| R10 | UI: pool hover, stake warnings, cut-win text, run refusal text, percent labels, free play texts; enUS + deDE | DC "stake warning: ...", UI "the pool's hover ...", UI tests (dropdown "1:30 x1.1", endless cash out pays 105%), locale test (every key in deDE), DC "percent text" | OFFLINE | same run | pass (layout not seen) | 2026-11-28 |
| R10-layout | the pool hover and the stake "!" (position right of the copper box, colours, tooltip text) look right | in-game screenshot | NOT-VERIFIED | needs the user | | |
| RF1 | jackpot far above the limit: record full win, pool +remaining, one `cap` entry | DC "a win above the limit left..." + "the limit is shared..." (slots) | OFFLINE | same run | pass | 2026-11-28 |
| RF2 | a 1.8 peer keeps an updated record (drops `tower`) | DC "tower section: a peer that does not know the field..." (emulated: field list without `tower`) | OFFLINE | same run; emulation, not the 0.13 code | pass | 2026-11-28 |
| RF2-real | a real 0.13 client lists an updated player | second client on 0.13 | NOT-VERIFIED | needs the user and a second member | | |
| RF3 | reload mid-run settles with the settle day's limit | DC "a new UTC day starts a new limit..." (run begun before midnight) | OFFLINE | same run | pass | 2026-11-28 |
| RF4 | 0.13 pending `factor = 64` pays 130%, not 64x | SV "survivor endless: never ends by time..." | OFFLINE | same run | pass | 2026-11-28 |
| RF5 | 1c stake at 105% nets 1c | SV "targets pay 105 to 140 percent..." (`WinNet(1, 105) = 1`) | OFFLINE | same run | pass | 2026-11-28 |
| RF6 | day change resets once | DC "a new UTC day starts a new limit..." | OFFLINE | same run | pass | 2026-11-28 |
| RF7 | ledger pruning never changes the balance | DC "the cap total lives in ledger.spent..." | OFFLINE | same run | pass | 2026-11-28 |

## In-game checklist (things only the user can do)
- [ ] `/gg`, hover the pool amount: tooltip with the breakdown, "Daily win limit", won today, left, the reset time and why.
- [ ] Type a stake the limit would cut (e.g. 600g on the coin flip): an orange "!" right of the copper box and orange digits; hover it for the reason. 0: grey "!" (free play). More than the pool: red.
- [ ] `/ggd` give yourself gold if needed, flip 600g and win (retry until a win): result says "You won 600g, paid 500g (daily win limit)."; header shows "Daily win limit reached"; `/gg caught wallet` shows a `cap` line of -100g.
- [ ] Clear the stake boxes (0) and flip / spin / start Survivor: "Free play: ..." texts, balance unchanged.
- [ ] Survivor dropdown shows "1:00 x1.05 ... 3:00 x1.4"; the endless hint reads "Endless: x1.05 at 1:00, then 5% more every minute (up to x1.3)...".
- [ ] German client (`/gg locale deDE`): percent labels use a comma (x1,05).
- [ ] A guild member still on 0.13 still sees you in the guild lists after you played a Survivor run on this version.

## Accepted gaps
- none yet
