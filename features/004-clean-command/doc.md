# Clean command

Status: draft | Since version: 0.2.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Deletes everything TalentShare has stored locally: cached guild characters and their recipes, the recipe catalog, orders, learned profession names and the debug log.

## How to use
- `/ts clean` (dev build: `/tsd clean`): shows what would be deleted.
- `/ts clean confirm`: deletes it. This cannot be undone.
- Afterwards reopen the window: your professions are scanned again automatically, and online guild members are asked to send their data again.
- Kept: UI preferences (minimap position, UI language, autoscan setting).

## How it works
`Store.Clean()` empties the SavedVariables tables in place, so the order board and the sync object keep working. Offline members and orders that nobody online has anymore are gone for good.

## Limits and known issues
- Only the local copy is removed; guild members keep their own copies and may send orders back.
- If a scan trigger fires before your professions are read again, an empty record of you can be published (same as a fresh install). Reopen the window right after cleaning.

## Changelog line
- `/ts clean confirm` wipes all locally stored data.
