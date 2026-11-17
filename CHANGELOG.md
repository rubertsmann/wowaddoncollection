# Changelog

## Unreleased
- **Games tab** (feature 014, protocol 2.3, schema 4): an animated coin flip. Enter a stake in gold, silver and copper (1c to 100 000g), pick heads or tails,
  flip; the coin is tossed and spins before it lands. Every member's wins and losses (gold amounts) appear on a guild
  leaderboard (this week / all time), with the 15 latest flips and last week's winner. For fun only: no gold changes
  hands, the addon never reads or moves gold. 2.2 members keep syncing everything else. Dev build: `/tsd anim` (animation
  probe), `/tsd anim speed <x>`, `/tsd game sim <n>`; offline: `luajit tools/coinflip.lua`.
- Internal: duplicated helpers merged into one copy each (`Util.Count/SortedKeys/Wipe/Refill/SanitizeMap/Me/ChatSafe`,
  `Store.Knows/RecipeCount`); the safer variant won where copies differed (feature 012). No player-visible change.
- Internal: `Core/` grouped into layer folders `Base`, `Debug`, `Data`, `Net`, `Game`, `View` (see README "Develop").
  Load order unchanged. Dev setups: re-run `tools/deploy.ps1` and restart the game.
- Internal (feature 013): every code name written in full words (`docs/coding-conventions.md`), LuaLS type annotations
  on every module function and shared table shape, files `Util.lua` / `Comm.lua` / `Diag.lua` renamed to `Utility.lua` /
  `Communication.lua` / `Diagnostics.lua`. Wire fields, SavedVariables keys and slash commands are unchanged.
- Logging: one helper, `Core/Base/Log.lua` (`Log.Error/Warning/Information/Debug/Exception/Protected`), with one line
  format `time LEVEL [area] message :: key=value`. Errors that were swallowed before (failed saved-data migration,
  failing event handlers, refused sends, failed whispers, profession window reads) are now logged with their details;
  `/ts debug` and the `/ts export` report show the log.
- Fixed: `Utility.ResetRealmAliases` (used by the tests) assigned globals instead of resetting the first-name index.

## 0.5.0
Player-facing notes (English/Deutsch): `RELEASE_NOTES.md`. Protocol 2.2 and schema 3 unchanged.

- Orders tab: **Craft** button: the first click opens the order's profession with the recipe selected, the next click
  crafts the ordered quantity (feature 009).
- Recipes, Orders and Available tabs: hovering a row's icon shows the recipe or item; clicking it opens a whisper with
  the link already typed in (crafter, requester/claimer, owner). Clicking a crafter in the recipe details also inserts the link.
- Notifications (feature 010): a new order for one of your professions, or someone claiming/finishing your order, shows
  a red number on the minimap button and the Orders tab, a letter icon, a chat line and a sound; optional screen message
  and taskbar flash. Everything can be switched in the new options panel (**Options** button, `/ts options`, game
  settings > AddOns).
- Recipes tab (feature 011): the profession button is now a dropdown, a new **Category** menu filters by what a recipe
  makes (head, chest, food, ... with checkboxes), and the search takes free text that also matches the item's effect and
  stats (e.g. "Beweglichkeit").

## 0.4.2
Player-facing notes (English/Deutsch): `RELEASE_NOTES.md`.

- **Fix (cause of "recipes still do not sync" in 0.4.1, from a live export):** one Forever guild spans several realms
  (`CAMWOW EU4 Realm 1/3/5 PvE`, `CAMWOW EU5 Realm 3 PvE`), while the roster and chat senders carry no realm. Every client
  appended its own realm, so a member was `Drakk Nuk-...Realm5` on one client and `Drakk Nuk-...Realm3` on another:
  requests were ignored as "name mismatch". Where names carry no realm (surnames, or a roster without realm suffixes) the
  realm is no longer part of a player's identity (`Util.RealmFree`); stored keys from other realms are moved on load.
- Members still on 0.4.0 on another realm: a whispered answer carries my record under the name they asked with, and
  requests to them add their first name in their realm (learned from their own requests).
- Name check: new row "realm in player names".
- **Fix (UI broken after switching versions until `/ts clean confirm`):** on the first login with another version than
  the saved data, everything other members sent is dropped once and fetched again (`Store.ResetPeerData`): characters,
  offers, catalog entries of their recipes, hidden items, the trace. Kept: my own character record, my offers, the
  catalog entries of my recipes, all orders, UI settings. `db.version` remembers the version.

## 0.4.1
Player-facing notes (English/Deutsch): `RELEASE_NOTES.md` (also the GitHub release text).

- **Sync diagnostics (feature 008):** new **Debug** tab lists every sync message sent and received with what happened to it and why (filters All / Incoming / Outgoing / System / Problems, live status line, Send HELLO, Clear). **`/ts export`** (or the tab button) opens a copyable diagnostic report (identity sources, transport state, records held, orders with the source of their name, network trace, debug log) for the addon author. New `/ts trace [n] [problems]`, `/ts ident`, `/ts debug [n]`; `/ts comm` shows send failures. A one-time chat warning appears when the character name does not match the guild roster.
- **Fix:** addon whispers to a same-realm player now always use the character name, also when the client's `Ambiguate` returns `Name-Realm` unchanged (the 0.3.2 "no player named ... online" failure could persist for background sync whispers and the realm suffix stayed visible in lists).
- **Fix:** sync no longer starts before `PLAYER_LOGIN` and reads the character name at use time; an alt could otherwise answer and advertise as the previously played character (SavedVariables are account-wide).
- **Fix (confirmed cause of "recipes and recipe items do not sync"):** on WoW Forever characters have a surname ("Drakk Nuk"). The addon called you only "Drakk", while the guild roster and all messages say "Drakk Nuk", so requests for your data were never answered, your data was refused, and your own messages were taken for another player. Your name is now first name + surname; data saved by 0.4.0 under the first name is moved automatically. Members still on 0.4.0 keep exchanging recipes and items with 0.4.1 (requests also carry their old first-name form).
- **Fix:** player names are compared and stored in one canonical form, whatever spelling of the realm the guild roster, the chat events or the own client use; the server's spelling of the own realm is learned from the roster and from the own guild messages. Stored data is converted automatically.
- **Sync no longer depends on whispers alone:** a request that gets no answer within 45 s is repeated on the guild channel and answered there (protocol **2.2**, additive); one answer serves every member that was behind. Every client also sends a HELLO every 15 minutes, so missed changes are found.
- Orders carry the recipe name, so they show the right name even before the recipe data of a crafter has arrived.
- Analysis of the 0.4.0 report "orders sync, recipes and recipe items do not": `review/sync-0.4.0-diagnosis.md`.
- Retry rule: a pull that got no answer after three tries is started again by the member's next HELLO after 60 s (as in 0.4.0); a 10-minute lock in a draft made the 30-member soak test fail about once in 100 runs.
- Wire protocol **2.2** (additive: `via` on WANT/WANTO, optional `name`/`loc` on orders; 2.1 clients keep syncing and show a one-time "newer version" notice). SavedVariables schema (3) unchanged (new additive key `trace`; names re-keyed in place).

## 0.4.0
- **Available tab (feature 007):** tradeable recipe items (item class Recipe) in bags, bank, reagent bank, mail, guild bank (per tab) and own auctions are listed automatically for the whole guild, with owner, locations, profession and age. Anyone can call **dibs**; all dibs are visible (oldest first) and each player removes only their own by pressing the button again. "Remove from my list" hides an offer locally; it returns when its owner's list changes. Handing items over stays manual. `/ts offers` shows what the scan sees. See `features/007-recipe-items-board/doc.md`.
- Wire protocol **2.1** (additive: optional HELLO field `orev`, new messages `WANTO`/`OFFERS`; 0.3.x clients ignore them and keep syncing everything else). SavedVariables **schema 3** (new `offers`, `hidden`; schema 2 data kept).
- `/ts clean` also removes offers.

## 0.3.2
- **Whisper fix:** same-realm players are now whispered by character name only. The `Name-Realm` form made the game answer "no player named … is online", for the whisper buttons and for the addon's own background whispers (sync requests and replies). Other realms keep `Name-Realm`.
- Lists show same-realm characters without the realm suffix (crafters, order requester and claimers).
- Clicking your own character in the crafter list no longer tries to whisper you.
- Wire protocol (2.0) and SavedVariables schema (2) unchanged.

## 0.3.1
- **Build flag:** one definition in `Core/Init.lua` (`ns.BUILD`, TOC `## X-Build: dev` or a folder name containing "dev"); the comms prefix, SavedVariables, frame names and slash commands of the dev build are all derived from it, so a dev build and the live addon never share data or addon messages. `tools/deploy.ps1` and `tools/package.ps1` now verify the generated dev TOC and the shipped live TOC; a TOC that saves a different global than the build uses is reported.
- Dev client no longer fails with a chain of nil-index errors when its generated TOC is stale: one message names the missing modules and the fix (`tools/deploy.ps1`, then restart the game).
- Tests: build-flag and TOC-invariant tests, stale dev TOC detection.
- Wire protocol (2.0) and SavedVariables schema (2) unchanged.

## 0.3.0
- **Protocol 2.0 (breaking, intentional):** every chunk header now carries `major.minor`, so incompatible versions are detected before anything is buffered and the player gets ONE notice (newer / older version in the guild). Same major with a different minor still syncs. 0.1/0.2 builds cannot sync with 0.3. See `docs/protocol.md`.
- **Inbound gate:** only `GUILD` messages and whispers from guild-roster members are processed; non-guild players can no longer request your recipes or inject data.
- **Strict input validation:** all peer and saved data is rebuilt by allow-list copy (finite numbers, bounded ids and timestamps, UTF-8 strings without control characters, safe icons); catalog entries are accepted only for recipes the sender knows.
- **Display safety:** peer text (notes, names) is escaped so `|c`/`|T`/`|H` codes show as literal text.
- **SavedVariables schema 2:** persisted data is re-validated on load; data written by a NEWER addon is left untouched (session runs unsaved, one notice) instead of being overwritten.
- One version source (TOC; read at runtime); release workflow now triggers on `v*` tags, checks the tag against the TOC version and scopes the CurseForge token to the packager step.
- Packaging: `tools/package.ps1` writes forward-slash zip entries (Windows PowerShell's `Compress-Archive` wrote backslashes) and verifies the zip.
- Docs: `docs/protocol.md`, `docs/vendored-libs.md`. Details: `features/006-hardening-and-version-compatibility/doc.md`.

## 0.2.0 (never released on its own; included in 0.3.0)
- Localization: UI in English/German, profession/recipe names resolved per viewer (mixed-language guilds merge), case/accent-insensitive search, UTF-8-safe order notes (fixes requests with long multi-byte notes doing nothing). See `features/002-localization-layer/doc.md`.
- Profession icons in the Recipes tab: one click per profession (a secure button, like the macro `/cast <profession>`) reads its recipes instead of cycling through the pages of the profession menu; new recipes are picked up automatically. See `features/005-profession-scan-buttons/doc.md`. (An automatic scan was tried and removed: the game blocks addons from opening professions.)
- `/ts clean confirm` wipes all locally stored data (cached guild data, recipes, orders). See `features/004-clean-command/doc.md`.
- Dev builds install side by side as `TalentShare-Dev` (own data, prefix and `/tsd`). See `features/001-dev-live-coexistence/doc.md`.
- Wire format and SavedVariables schema unchanged (additive fields only): interoperates with 0.1.0.

## 0.1.0
- First version: profession/recipe sharing over the guild addon channel, recipe browser, shared order board.
