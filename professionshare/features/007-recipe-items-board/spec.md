# 007 Recipe items board: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.4.0 (released; protocol 2.1 additive, schema 3)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A new "Available" tab lists the tradeable recipe ITEMS (patterns, plans, formulas; item class Recipe, e.g. item 6661) that guild members hold, so players see them before selling them elsewhere, and anyone can call dibs; every dib is visible, the owner decides manually, and pressing the button again removes the dib.

## Requirements
- R1: The addon scans my tradeable (not bound) recipe items in: bags, bank, reagent bank, mailbox, guild bank (per tab), own auctions. Locations that cannot be read right now (bank closed...) keep their last known state.
- R2: My offer list is shared over the guild channel (additive protocol 2.1). Offers are listed automatically (no opt-in, no switch in v1).
- R3: The "Available" tab lists the offers of all guild members: item (tooltip), owner, locations with counts, number of dibs, age. Search, "only my professions" filter.
- R4: A Dibs button toggles MY dib on the selected offer; several players may dib the same item; all dibs are shown with who and when (oldest first). Only the dibbing player can remove their own dib (the owner cannot).
- R5: Anyone can remove an offer from their own list (local only). It reappears when the owner's record changes and syncs again; my dib on it is kept.
- R6: When the owner no longer has the item the offer disappears everywhere with the next sync, and my own stale dib is dropped automatically. Handing the item over is fully manual (no assign function).
- R7: Strict validation of everything received (allow-list), peer text escaped, `/ts clean` also clears offers.

## Non-goals
- No trade/mail automation, no "give to X" function, no owner opt-in, no learned-recipe check, no required-skill check (not readable), no de-duplication of the same guild bank scanned by two members.

## Decisions (user answers, 2026-11-16)
- Q1 recipe ITEMS like item 6661 (class Recipe). Q2 tradeable only (not soulbound). Q3 all locations (bags, bank, reagent bank, mail, guild bank, auctions) so players know before selling elsewhere. Q4 listed automatically, trading optional. Q5 multiple dibs, owner decides manually. Q6 only the dibbing player removes their dib. Q7 removal is local only. Q8 fully manual. Q9 additive protocol, Q10 UI as proposed.
- Design choices (mine): one record per character `{name, rev, items = {[itemID] = {[loc] = n}}, dibs = {["Owner:itemID"] = {on, t}}}`, last writer wins by `rev`, only the author writes it, so "only I can remove my dib" is enforced by construction. Sync = HELLO gets optional `orev`; new messages `WANTO` (pull) and `OFFERS` (record). Locations: `bag bank reagent mail auction gbank1..gbank8` replaced independently, so scanning one place never wipes another. Local removal: `db.hidden[key] = ownerRev`, void when the owner's rev changes.
- Protocol 2.0 -> 2.1 (new optional HELLO field + two new message types; 0.3.x clients ignore both). Schema 2 -> 3 (new `offers`, `hidden` tables; migration is additive). Version 0.4.0 when released.

## Design
- `Core/Offers.lua` (new, pure): `Sanitize`, `Update(me, scans, now)`, `ToggleDib`, `Maintain` (drop my dibs on vanished offers), `Hide`, `List`, `Put/Get`.
- `Core/Api.lua`: `Api.ScanItems()` (all WoW container/mail/bank/auction calls, pcall-protected, returns only locations readable now), `Api.ItemClass(itemID)` (class/subclass/icon without loading), `Api.open` flags.
- `Core/Sync.lua`: `orev` in HELLO, `_onWANTO`, `_onOFFERS`. `Core/Comm.lua`: WANTO jumps the queue. `Core/Store.lua`: schema 3, `offers`, `hidden`, Clean/Counts/Prune. `Core/Model.lua`: `BuildOfferRows`. `Core/Events.lua`: item events -> debounced scan -> `OFFERS_CHANGED` -> HELLO. `UI/Window.lua`: third tab. `Locales/deDE.lua`. TOC (both) gets `Core\Offers.lua`.
- `/ts offers` prints API availability, open flags and my per-location counts (doubles as the in-game probe); `/ts offers scan` forces a scan.

## Tasks
- [x] T1 (M): `Core/Offers.lua` + Store schema 3 + tests (`tests/test_offers.lua`). Verify: offline.
- [x] T2 (S): Sync `orev`/WANTO/OFFERS, protocol 2.1, Comm queue priority, tests with the in-memory bus.
- [x] T3 (M): `Api.ScanItems`/`ItemClass`, Events glue, `/ts offers`.
- [x] T4 (M): `Model.BuildOfferRows`, UI tab, locale strings (en/de).
- [x] T5 (S): TOC, load tests, docs (protocol.md, README, CHANGELOG, status, doc.md), verify.md.
- [ ] T6 (S): in-game verification by the user (`/ts offers`, bags/bank/mail, two clients).

## Review Focus (failure modes a happy-path test would miss)
1. RF1: bank/mail/guild bank/auction not open or unreadable -> that location keeps its previous state (no wipe). Pinned by: T1 test "update keeps locations that were not scanned".
2. RF2: item class unknown (nil) or not a recipe -> not listed, no error. Pinned by: T4 model test.
3. RF3: garbage / oversized / forged OFFERS (name != sender, owner dibbing own item, bad keys, inf/nan, huge tables) -> dropped whole. Pinned by: T1/T2 tests.
4. RF4: dib toggled twice, offered item vanished while dibs exist, two dibbers -> consistent on all clients, order by time. Pinned by: T1, T2 tests.
5. RF5: local removal followed by sync -> item returns when the owner's rev changes, dib kept; `/ts clean` clears everything. Pinned by: T1 tests.

## Cross-cutting checklist
- [x] Protocol: additive minor bump 2.0 -> 2.1 (HELLO optional `orev`, new types WANTO, OFFERS); 0.3.x ignores them.
- [x] Stored data: `Store.SCHEMA` 2 -> 3, `MIGRATIONS[2]` no-op (tables created by `fresh`), re-validation on every load.
- [x] Trust model: `Offers.Sanitize` allow-list, record author must equal sender, dib keys validated, display escaped in Model.
- [x] Localization: only item ids/counts/loc keys stored and sent; all texts via `ns.L` + deDE.
- [x] Load order: `Core\Offers.lua` after `Core\Orders.lua` (needs Store, Util).
- [x] Packaging: no new files outside Core/; `.pkgmeta` unchanged.
- [x] Tests: tests/test_offers.lua, test_offers_model.lua, test_items_api.lua.
- [x] Docs: README, CHANGELOG, docs/protocol.md, docs/status.md, doc.md.

## Open questions
- Client APIs for container/bank/mail/guild bank/auction scanning are unverified on Forever (needs: game, `/ts offers`).
- Auction and mail are "last seen" snapshots: a sold auction stays listed until the next visit (accepted, documented).
