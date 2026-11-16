# Changelog

## 0.2.0 (unreleased)
- Localization: UI in English/German, profession/recipe names resolved per viewer (mixed-language guilds merge), case/accent-insensitive search, UTF-8-safe order notes (fixes requests with long multi-byte notes doing nothing). See `features/002-localization-layer/doc.md`.
- Automatic profession scan: one click (or automatically on first open) reads all your professions instead of opening each page by hand; new recipes are picked up automatically. See `features/003-auto-profession-scan/doc.md`.
- `/ts clean confirm` wipes all locally stored data (cached guild data, recipes, orders). See `features/004-clean-command/doc.md`.
- Dev builds install side by side as `TalentShare-Dev` (own data, prefix and `/tsd`). See `features/001-dev-live-coexistence/doc.md`.
- Wire format and SavedVariables schema unchanged (additive fields only): interoperates with 0.1.0.

## 0.1.0
- First version: profession/recipe sharing over the guild addon channel, recipe browser, shared order board.
