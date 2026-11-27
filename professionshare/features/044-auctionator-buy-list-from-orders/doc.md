# Auctionator buy list from orders

Status: built, in-game check open | Since version: next release | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
When Auctionator is installed, the Orders tab gets a tick box per order and an **Auctionator buy list (n)** button. One
click puts every reagent the ticked orders need (reagent count x ordered quantity, summed per item) on an Auctionator
shopping list. At the auction house, Auctionator's Shopping tab then searches for all of them at once. Without
Auctionator, nothing on the tab changes.

## How to use
- UI: Orders tab -> tick any orders (yours, other members', claimed or not) -> **Auctionator buy list (n)**. After a list was created, the ticks are cleared.
  Tick **Subtract what I have** to buy only what your bags and bank are missing (remembered between sessions).
- **At the auction house:** the button creates the list and Auctionator's Shopping tab starts searching the items
  right away.
- **Elsewhere:** the list is created and the search waits. About a second after you next talk to an auctioneer,
  the Shopping tab searches the items (once). Turn this off on the settings page (`/ps options` -> **Auctionator** ->
  **Search the buy list when I open the auction house**); then the list just waits in Shopping -> **ProfessionShare
  buy list** (German client: "ProfessionShare Einkaufsliste"). Every export replaces that list and any waiting search.
- Addons cannot open the auction house themselves; the game opens it only through an auctioneer.
- The search runs on Auctionator's temporary list "ProfessionShare (temporary)". The named list stays for later.
- If Auctionator refuses the list: a window shows the error and the list as import text. Copy it (Ctrl+A, Ctrl+C) and
  paste it in Auctionator: Shopping -> Import.
- Commands: none.

## How it works
- Data (SavedVariables): `db.ui.buyListSubtract` (true or absent), `db.ui.buyListSearchOnOpen` (false or absent = on).
  Ticks and a waiting search are kept for the session only.
- Search: `Auctionator.API.v1.MultiSearchAdvanced` (public API; needs the AH open). The waiting search is started from
  `AUCTION_HOUSE_SHOW` (`Core/Game/Events.lua`) 1 s later, because Auctionator itself switches to its default tab when
  the auction house opens (once at once and once a frame later).
- Messages: no change; nothing is sent.
- Modules:
  - `Core/Data/BuyList.lua` (pure): sums the reagents from the shared recipe catalog, applies the subtract mode, cleans
    names (`;`, `^` and `"` removed), builds search terms and import text.
  - `Core/Game/Auctionator.lua`: the only file that touches Auctionator. It uses only the public API
    (`Auctionator.API.v1.ConvertToSearchString`, `CreateShoppingList`) with `pcall` and has its own search-term format
    as a fallback.
  - `UI/Window.lua`: tick boxes, button, option, chat report, error window (`UI.ShowCopyDialog`).
  - TOC: `## OptionalDeps: Auctionator`, so Auctionator loads first when it is installed.
- Each item becomes one exact search term with a quantity:
  `"Copper Bar";;;;;;;;;;;#;;6`.

## Localization
Labels and the list name go through `Text` (German in `Locales/deDE.lua`). Item names come from the client
(`Api.ItemName`), so the list uses the viewer's language, which Auctionator needs for searching. The scanned reagent
name is the fallback.

## Limits and known issues
- A reagent is only known if someone who knows the recipe has shared their scan. Orders without reagent data are
  counted in chat.
- Items whose names the client has not loaded yet are left out and counted in chat. Clicking again a moment later
  usually works.
- No sub-reagents: bars are bought as bars, not as ore.
- Bags and bank only; mail, reagent bank and guild bank are not counted in subtract mode.
- Whether Auctionator on Forever shows the quantity (e.g. "0/6") is not checked yet (see verify.md).

## Changelog line
- Orders tab (with Auctionator): tick orders -> Auctionator buy list of their reagents, optional subtract-what-I-have,
  copy fallback on error; searched at once at the auction house, or when it next opens.
