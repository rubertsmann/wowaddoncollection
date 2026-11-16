# Hardening and version compatibility

Status: verifying (offline proven; in-game and two-client checks open) | Since version: 0.3.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)
Full rules: `docs/protocol.md`.

## What it does
TalentShare now only talks to compatible versions and only to your guild. If a guild member runs a newer or older, incompatible version you get one chat notice instead of silent failure. Data received from other players (or loaded from a saved file) is checked field by field, and text from other players can no longer inject colours, textures or links into the window.

## How to use
- Nothing to configure. `/ts version` shows the addon version, `protocol <major>.<minor>` and `schema`. `/ts comm` shows `rejected` (messages dropped by the guild gate or for a foreign protocol), `roster` and `incompatible peers`.
- A notice you may see (once per kind per session): "A guild member runs a newer/older TalentShare that cannot sync with this version" or "...newer TalentShare with extra features" (still compatible).
- "Saved data was written by a newer TalentShare and is left untouched": you installed an older addon over newer data. Update the addon; nothing is saved this session and the file is not overwritten.

## How it works
- **Messages:** chunk header is now `major.minor|id|idx|total|part` (protocol 2.0). Payload `v` = major. Majors must match; minors may differ (additive-only rule).
- **Gate:** `Core/Guard.lua`: `GUILD` accepted; `WHISPER` only from the cached guild roster (fail closed); every other channel rejected. Runs first in `Comm.OnAddonMessage`.
- **Validation:** `Store.SanitizeChar`, `Store.SanitizeCatalogEntry`, `Orders.Sanitize` rebuild records by allow-list copy; `Util.IsFinite/SafeInt/CleanString/IsSafeName/Esc` are the building blocks; the parser rejects `inf`/`nan`; timestamps must be within `[0, now + 1 day]` (no upper bound while the clock reads below 1e9, so an unsynced clock cannot delete saved data). A SNAP may only carry catalog entries for recipes the sender knows.
- **Display:** `Core/Model.lua` escapes `|` in every peer-originated string; `Debug.Log` escapes too.
- **Stored data:** `Store.SCHEMA = 2`; `Store.Migrate` runs stepwise (`1 -> 2` re-validates persisted data); newer schema -> original table handed back untouched, throwaway DB for the session (`ns.db.readonly`).
- **Versions:** TOC `## Version` is the single source (read via addon metadata, literal fallback pinned by a test); `release.yml` refuses a tag that does not match.
- **Modules:** `Core/Init.lua` (constants), `Core/Util.lua`, `Core/Codec.lua` (header, compat, limits), `Core/Guard.lua`, `Core/Comm.lua`, `Core/Sync.lua`, `Core/Store.lua`, `Core/Orders.lua`, `Core/Model.lua`, `Core/Events.lua`.

## Localization
Four new notices (`Comm.lua`, `Events.lua`) go through `ns.L` with German translations in `Locales/deDE.lua`. No display text is stored or sent.

## Limits and known issues
- 0.1.x/0.2.x clients cannot sync with 0.3 and cannot be told why (they cannot read the new header); 0.3 clients notice them from the legacy header and print the "older version" notice.
- Right after login the roster may not be loaded yet; whispers arriving in that window are dropped and re-requested by the next HELLO (reasoned, not observed in game).
- Guild members are still trusted: any member can change any order (accepted, README "Trust model").
- Inflate output of an accepted guild message is not size-limited by LibDeflate (only checked afterwards against `MAX_RAW`).
- Not done (see spec Non-goals): SHA-pinning of GitHub actions, stripping the LibDeflate CLI section, a flag for the debug log. The vendored libraries are not yet verified byte-identical to upstream (`docs/vendored-libs.md`).

## Changelog line
- Protocol 2.0 with version in the chunk header and compatibility notices; inbound guild gate; strict validation of peer and saved data; escaped peer text; SavedVariables schema 2 with downgrade guard; one version source; release workflow tag check.
