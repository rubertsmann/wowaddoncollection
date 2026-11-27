# 044 Auctionator buy list from orders: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 10:20 | PLAN | Feature created
- Did: scaffolded `features/044-auctionator-buy-list-from-orders/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 10:31 | PLAN | Spec written from the user's answers
- Did: read Auctionator 354 on the Forever install (`Source/API/v1/ShoppingLists.lua`, `Source/Search/Advanced.lua`, `Source/Shopping/ImportExport.lua`); filled spec.md (R1-R8, T1-T5, RF1-RF5)
- Result: design = per-row checkboxes, direct `Auctionator.API.v1.CreateShoppingList` call, full/subtract option, error modal with copy text; controls hidden without Auctionator
- Evidence: user answers recorded under spec.md "Decisions"
- Next: T1 `Core/Data/BuyList.lua` + `tests/test_buy_list.lua`

## 2026-11-27 10:58 | BUILD | T1-T4 buy list, Auctionator bridge, TOC, Orders tab UI
- Did: `Core/Data/BuyList.lua` (new, pure), `Core/Game/Auctionator.lua` (new, pcall-wrapped public API v1), `tests/test_buy_list.lua` (12 tests, written first), `tests/run.lua` (harness loads BuyList), `ProfessionShare.toc` (`OptionalDeps: Auctionator`, two files), `UI/Window.lua` (row tick boxes, `Auctionator buy list (n)` button, `Subtract what I have` option in `db.ui.buyListSubtract`, chat report, `UI.ShowCopyDialog` generalised from `UI.ShowExport`), `Locales/deDE.lua` (13 strings), `tests/test_load.lua` (render pass with an Auctionator stub)
- Result: all offline tests pass; dev TOC regenerated with `tools/deploy.ps1`
- Evidence: `luajit tests/run.lua` -> `350 passed, 0 failed`; comment audit: no findings in the new files
- Next: T5 docs

## 2026-11-27 11:02 | DEVIATION | Locale keys without quotes or newlines
- Did: list name in messages shown without quotes; the error hint is two `Text` keys joined by a newline
- Result: `tests/test_locale_files.lua` reads keys literally from source, so escaped `\"` / `\n` never matched deDE
- Evidence: suite failure before the change: `untranslated in deDE: ... (UI/Window.lua)`
- Next: continue T5

## 2026-11-27 11:05 | DOC | T5 docs and verify matrix
- Did: doc.md, verify.md (R1-R8, RF1-RF5, in-game checklist), README (Orders tab + code layout), CHANGELOG (Unreleased), docs/status.md, INDEX status `verifying`
- Result: every requirement is OFFLINE at the logic level; UI look and the real Auctionator call are NOT-VERIFIED
- Evidence: `features/044-auctionator-buy-list-from-orders/verify.md`
- Next: user runs the in-game checklist in verify.md (dev build `/psd`, Auctionator enabled, `/console scriptErrors 1`) and reports results/screenshots; then set rows to IN-GAME and status `done`

## 2026-11-27 10:33 | NOTE | Correction: entry times
- Did: checked the system clock (`date` -> 2026-11-27 10:33)
- Result: the times of the four entries above (10:31, 10:58, 11:02, 11:05) were estimated, not read from the clock; all of that work happened between 10:20 and 10:33. Their content is unchanged.
- Evidence: `date "+%Y-%m-%d %H:%M"` -> `2026-11-27 10:33`
- Next: (see the next entry)

## 2026-11-27 10:33 | DECISION | Start Auctionator's search directly
- Did: user asked whether Auctionator can be opened right away; answer: the AH window opens only through an auctioneer, but `API.v1.MultiSearchAdvanced` starts a Shopping-tab search while the AH is open. User: "do it" (both: search at once at the AH, and when the AH next opens)
- Result: R9, R10, RF6, T6-T8 added to spec.md; search-on-open defaults to on
- Evidence: Auctionator `Source/API/v1/MultiSearch.lua`, `Source_LegacyAH/Core/Mixin.lua` (ShowDefaultTab on AUCTION_HOUSE_SHOW, again next frame)
- Next: T6

## 2026-11-27 10:33 | BUILD | T6-T8 search at the AH and on the next opening
- Did: `Core/Game/Auctionator.lua` (`IsAuctionHouseOpen`, `Search`, pending search), `tests/test_buy_list.lua` (+4 tests, written first), `UI/Window.lua` (export handler searches or leaves a waiting search), `Core/Game/Events.lua` (`AUCTION_HOUSE_SHOW` runs it 1 s later), `UI/Alerts.lua` (settings section Auctionator), `Locales/deDE.lua` (+9 strings), `tests/test_load.lua` (settings page with an Auctionator stub); docs, verify.md rows R9, R10, RF6
- Result: all offline tests pass; no comment-audit findings in the changed files
- Evidence: `luajit tests/run.lua` -> `354 passed, 0 failed`
- Next: user runs the in-game checklist in verify.md (dev build `/psd`, Auctionator enabled, `/console scriptErrors 1`), including the three new auction house steps; then set rows to IN-GAME and status `done`

## 2026-11-27 10:39 | BUILD | Clear ticks after a successful export
- Did: `UI/Window.lua` `exportBuyList`: when the Auctionator list was created, `buyListTicks` is emptied and the Orders tab refreshed; after a failure or with nothing to buy the ticks stay. spec R1 + decision, verify checklist step, doc.md
- Result: suite green; the clearing itself is UI-only (the load test's stubs cannot click), checked in game
- Evidence: `luajit tests/run.lua` -> `354 passed, 0 failed`
- Next: user runs the in-game checklist in verify.md (incl. the new tick-clearing step); then set rows to IN-GAME and status `done`

## 2026-11-27 10:50 | BUILD | CurseForge: Auctionator as optional dependency
- Did: `tools/curseforge.json` gets `relations: [{ slug: auctionator, type: optionalDependency }]`; `../tools/upload-curseforge.ps1` validates `relations` (slug format, the five CurseForge relation types), prints them and sends them as `metadata.relations.projects` with every upload; `.pkgmeta` `optional-dependencies: auctionator` for the inactive GitHub packager workflow
- Result: dry runs OK; the relation is attached per uploaded file, so it appears with the next CurseForge upload
- Evidence: `upload-curseforge.ps1 -Addon professionshare -DryRun` -> `relations: auctionator (optionalDependency)`, `dry run: nothing uploaded`, exit 0; guildgames -> `relations: none`, exit 0
- Next: user runs the in-game checklist in verify.md; the relation is checked on the CurseForge Relations tab after the next release upload

## 2026-11-27 11:31 | DEVIATION | Tick boxes always shown (feature 045)
- Did: the Orders tab tick boxes now serve the mail queue too (feature 045), so they are shown with or without Auctionator; the buy-list controls stay Auctionator-only
- Result: R2 "without Auctionator nothing changes" now holds for the buy-list button and option only
- Evidence: `UI/Window.lua` order row fill; `features/045-mail-order-items/spec.md` decisions
- Next: unchanged (in-game checklist in verify.md)

## 2026-11-27 12:46 | DEVIATION | Reworked by feature 046
- Did: feature 046 replaced the tick boxes and top/bottom controls: buy list per order via a row icon and dialog, collected until the next auction house visit; mail queue via row icons, filled on click from a list next to the inbox (no fill on open or after a send), Done/Delete per mail
- Result: this feature's UI requirements are superseded where 046 says so; the logic (Auctionator API use, mail filling) is unchanged
- Evidence: `features/046-order-row-actions-and-mailbox-queue-list/spec.md`
- Next: verify through 046's in-game checklist

## 2026-11-27 13:28 | VERIFY | In-game confirmation by the user
- Did: user ran the dev build after feature 046 and reported "looks fine and works as expected"; recorded in verify.md ("In-game result")
- Result: open rows count as IN-GAME on the user's report; status `done`
- Evidence: user report in the session (no file evidence)
- Next: release (see the release commit)
