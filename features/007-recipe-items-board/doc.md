# Recipe items board

Status: verifying (offline proven, in-game checks pending) | Since version: 0.4.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The **Available** tab lists every tradeable recipe item (patterns, plans, formulas, e.g. "Recipe: Savory Deviate Delight") that guild members hold, so players know what exists before they sell it elsewhere. Anyone can call **dibs** on an item; all dibs are shown with who and when. The owner decides and hands the item over by hand.

## How to use
- Nothing to set up: your own bags are read automatically; the bank, reagent bank, mailbox, guild bank (the tab you are looking at) and your auctions are read while their window is open, and their last state is kept afterwards.
- Tab **Available**: search item, owner or profession; "Only my professions"; click a row to see the dibs; hover for the item tooltip.
- **Dibs** calls dibs, the same button (now "Remove dibs") takes yours back. Only you can remove your own dib; the owner cannot. You cannot call dibs on your own items.
- **Remove from my list** hides the offer for you only. It returns when its owner's list changes (for example they loot or move something).
- **Whisper owner** opens a whisper to the owner.
- `/ts offers` shows what the scan can see on your client and what your offers record holds; `/ts offers scan` forces a scan.

## How it works
- Data (SavedVariables, schema 3): `offers[name] = { name, rev, items = { [itemID] = { [loc] = count } }, dibs = { ["Owner:itemID"] = { on, t } } }`, `hidden["Owner:itemID"] = ownerRev`.
- A character's record holds both the items they offer and the dibs THEY placed; only they write it, so nobody can set or remove somebody else's dib. The tab combines all records.
- Messages (protocol 2.1, additive): `HELLO.orev`, `WANTO`, `OFFERS` (see `docs/protocol.md` section 6).
- Modules: `Core/Offers.lua` (pure model), `Core/Api.lua` (`Api.ScanItems`, `Api.ItemClass`), `Core/Events.lua` (events, debounced scan, `/ts offers`), `Core/Model.lua` (`BuildOfferRows`), `UI/Window.lua` (tab).
- Only item class Recipe that is not soulbound is offered. Item names, icons and professions are resolved by each viewer's own client; ids the client does not know or that are not recipes are not shown.

## Localization
Only item ids, counts and location keys are stored and sent. All tab texts are English with German translations; item and profession names follow the viewer's game client.

## Limits and known issues
- Mail, auctions and the guild bank are "last seen" snapshots: a sold auction or a taken item stays listed until you visit that window again.
- The guild bank is read per tab (the tab you have open); two members scanning the same guild bank both list its items.
- The required profession skill of a recipe is not shown (not readable); the profession is derived from the item's type.
- Up to 300 items and 200 dibs per character; guild members are trusted (README trust model).
- 0.3.x clients ignore offers and dibs but keep syncing everything else.
- The client APIs for bank / mail / guild bank / auction scanning are not yet verified on WoW Forever (see verify.md).

## Changelog line
- Available tab: tradeable recipe items of all guild members (bags, bank, mail, guild bank, auctions) with dibs.
