# 051 Daily casino win cap and smaller Survivor payouts: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 22:34 | PLAN | Feature created
- Did: scaffolded `features/051-daily-casino-win-cap-and-smaller-survivor-payouts/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 22:34 | PLAN | Measured Survivor payouts, spec written
- Did: read every money path (Wallet, Games, Slots, Survivor, Runner, Arena, AzeCaught, Items); ran a throwaway seeded simulation of Survivor endless runs (bot picks card 1 / last / 2) through the offline harness, file removed afterwards; wrote spec.md (R1-R9, T1-T7, RF1-RF6, Q1-Q5)
- Result: bots survive 60 s ~52%, 90 s ~17%, 120 s ~5%, 180 s+ 1-2% (those never die; one reached the 15 min sim limit); endless at 64x gave +3.35x stake per run on average. Found that one bad entry makes a peer reject the whole record (Core/Data/Games.lua sanitizeRecord), so smaller Survivor wins go into a new `tower` section
- Evidence: `SIM first 60s=52% 90s=18% 120s=6% 180s=1% 240s=1% 300s=1% 360s=1%`; `SIM last 60s=55% 90s=18% 120s=5% 180s=1% ...`; `SIM mid 60s=50% 90s=15% 120s=4% 180s=3% 240s=2% 300s=2% 360s=2%`; baseline `luajit tests/run.lua` -> `218 passed, 0 failed`
- Next: user answers Q1-Q5 in spec.md, then T1

## 2026-11-27 22:34 | NOTE | Correction to the previous entry
- Did: checked the function name cited above
- Result: the record check is `Games.Sanitize` (Core/Data/Games.lua:243), not `sanitizeRecord`
- Evidence: `function Games.Sanitize(gameRecord)`
- Next: user answers Q1-Q5 in spec.md, then T1

## 2026-11-27 22:34 | DECISION | Q1-Q4 answered, spec reworked
- Did: recorded the user's answers in spec.md "Decisions"; reworked R1-R10, design, tasks T1-T8, RF1-RF7
- Result: limit 500g net per day; no refusal at the limit (wins above it are not paid, booked as a wallet `cap` entry while the record keeps the real result); free play and 1c stay; Survivor 105/110/120/140%, endless max 130%; coin and slots blocked while a Survivor run is pending; old survivor leaderboard hidden (default, not asked)
- Evidence: spec.md Decisions section
- Next: T1 (Games: tower kind and per-kind minimum win net), tests first in tests/test_daily_cap.lua

## 2026-11-28 00:02 | BUILD | T1-T4 records, wallet limit, games, Survivor percent payouts
- Did: Core/Data/Games.lua (kind `field`s, game survivor -> field `tower` with minimumWinNet 1, old field as `legacySurvivor`, `Games.STORED`, `RunRefusal`, Flip/RecordPlay book through the wallet and return `paid`, stake 0 = free flip); Core/Data/Wallet.lua (DAILY_WIN_CAP 500g, CasinoDay, WinRemaining, BookCasino with `cap` ledger entries, casinoDay sanitize); Core/Minigames/Slots.lua (free spin, `paid`); Core/Minigames/Survivor.lua (pct targets 105/110/120/140, EndlessPercent 105 +5/min to 130, WinNet min 1c, pending `pct`, 0.13 `factor` converted, free runs); updated existing tests (stake 0 is no longer a refusal, `.survivor` -> `.tower`, new payouts); new tests/test_daily_cap.lua
- Result: green
- Evidence: `luajit tests/run.lua` -> `231 passed, 0 failed`
- Next: T5 difficulty ramp

## 2026-11-28 00:02 | DEVIATION | Net limit formula
- Did: remaining = max(0, CAP - todayNet) instead of CAP - max(0, todayNet) (spec R2 updated)
- Result: a loss earlier in the day can be won back plus 500g, so the day's gain is +500g at most (the user's "+500 per day")
- Evidence: DC "a loss first raises what may be won back the same day"
- Next: T5

## 2026-11-28 00:02 | BUILD | T5 frenzy so every run ends
- Did: Survivor.Frenzy: from 4:00 monster health and damage x FRENZY_GROWTH per minute; test SV "survivor frenzy: every run ends; 200 seeded runs with three card strategies, none past 8:00"
- Result: growth 1.8 failed (one run, strategy "second" seed 86, lasted 537 s with thorns 5/deflect 3/barrier 3/leech); growth 2.5 passes. Survival rates up to 4:00 unchanged (frenzy starts there)
- Evidence: diagnostic sim (throwaway, removed): `SIM long second 86 537 ...`, `SIM rate second 60s=50.5% 90s=15.5% 120s=4.5% 180s=3.0% 240s=2.5% ...`; then `232 passed, 0 failed`
- Next: T6 UI

## 2026-11-28 00:02 | BUILD | T6 UI and locales, T7 protocol and docs
- Did: Model.PercentText / WinText / WinLimitText, `run` refusal text; GamesTab (header limit line right of the pool, free/cut texts, stake text "or 0 for free play"); SlotMachine and SurvivorArena (paid amounts, free texts, x1.05 labels, new hints); deDE strings (decimal comma), obsolete keys removed; `/gg caught wallet` prints the limit and old survivor net; PROTOCOL_MINOR 9 (Init.lua, tests/run.lua, test_load); docs/protocol.md, README, CHANGELOG Unreleased
- Result: green
- Evidence: `luajit tests/run.lua` -> `232 passed, 0 failed`
- Next: T8 in game

## 2026-11-28 00:02 | DEVIATION | R10 without a pre-play warning; RELEASE_NOTES left to the release
- Did: R10 is the header line plus the result text; no warning before a play whose win would be cut, no extra cash-out hint in endless mode; RELEASE_NOTES are written by the release skill, not drafted here
- Result: spec R10, T7 and Decisions updated
- Evidence: spec.md
- Next: T8 in game

## 2026-11-28 00:02 | BLOCKED | In-game check (T8) needs the user
- Did: wrote the in-game checklist in verify.md; spec status verifying, INDEX row updated
- Result: every requirement OFFLINE; R10 layout and a real 0.13 peer (RF2-real) NOT-VERIFIED
- Evidence: verify.md
- Next: user runs the verify.md in-game checklist (deploy with tools/deploy.ps1), reports screenshots/results; then commit if asked, and release 0.14.0 (protocol 1.9) when the checklist passes

## 2026-11-28 00:41 | DECISION | Limit as a hover on the pool, warnings on the stake (user)
- Did: user asked to "move the gold win left into the gold amount as a hover information with detailed information how and why also show warnings on the betting amount"; R10 rewritten in spec.md
- Result: the header limit line is gone; the pool amount has a tooltip; every stake row gets a "!" warning with a tooltip
- Evidence: spec.md R10
- Next: build it

## 2026-11-28 00:41 | BUILD | Pool tooltip and stake warnings
- Did: Core/View/Model.lua (PoolTooltip: balance breakdown + daily limit: won today, not paid today from the day's `cap` entries, left, reset time, why; StakeWarning per game: free play note, more than the pool error, limit reached / smallest win cut warning, big win cut note; CutToday; WinLimitText removed); UI/GamesTab.lua (balanceHover frame over the pool, ShowLinesTooltip, CreateStakeRow takes a warning source, "!" button right of the boxes, boxes tinted, re-checked on typing and on every balance refresh); SlotMachine and SurvivorArena pass their game (Survivor: target percent, endless 105..130%, re-checked on a target pick); deDE strings; tests: DC "stake warning: ...", UI "games ui: the pool's hover explains the daily win limit; ..."
- Result: green
- Evidence: `luajit tests/run.lua` -> `236 passed, 0 failed`
- Next: in-game check (verify.md checklist updated), commit when the user asks
