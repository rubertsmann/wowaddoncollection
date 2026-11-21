---
name: review-professionshare
description: Review the ProfessionShare WoW addon (guild recipe/orders sharing) for security, protocol/version compatibility, data migration, cross-cutting gaps and leaked credentials. Use when asked to review, audit or check this project or a change to it, or to refresh the files in review/.
---

# Reviewing ProfessionShare

Read `review/*.md` first: they hold the standing findings. Update them instead of starting over; mark a finding fixed (with the commit) rather than deleting it. Do not report a known item as new.

## Project in one paragraph
A Lua 5.1 addon for **WoW Forever** (interface `16001`, Mainline-style API, modern `C_TradeSkillUI`). Each guild member scans their own professions/recipes/reagents, stores peers' data in SavedVariables (`ProfessionShareDB`) and syncs over the hidden addon-message channel (prefix `PShare`), plus a shared crafting-order board. No backend, no network access, no secrets by design.

## Trust model (decided, do not re-litigate)
- **Guild members are trusted.** Order forgery/tampering by a guild member is accepted (README "Trust model").
- **Not trusted:** non-guild players (WHISPER addon messages work for anyone), accidentally malformed data, and any peer text shown in the UI.
- A peer may only author its **own** character record (`SNAP.char.name == sender`); keep it that way.

## Layout and load order (`ProfessionShare.toc`)
`Libs/LibStub`, `Libs/LibDeflate` (vendored copy from the Spoken addon, see `docs/vendored-libs.md`) -> `Core/Base/Init` (identity, `addon.PROTOCOL_MAJOR/MINOR`, version from TOC metadata) -> `Utility` (names, UTF-8, untrusted-input helpers) -> `Log` (the one logging helper) -> `Locale`/`Locales` -> `Store` (SV schema, migration, allow-list sanitizers) -> `Names` -> `Api` (WoW adapter) -> `Scanner` -> `Codec` (serializer, deflate, chunk header, limits) -> `Guard` (inbound gate, incompatibility notices) -> `Orders` -> `Offers` (recipe-item offers and dibs, feature 007) -> `Sync` (pure protocol state machine) -> `Model` (UI view-models, escapes peer text) -> `Communication` (chunking, pacing, reassembly, gate) -> `Events` -> `UI/Window`. Check the real order in `ProfessionShare.toc`.

**Pure modules** (testable offline, no WoW calls): Utility, Log, Store, Orders, Codec, Guard, Sync, Model, Names, Locale (Communication is loaded by the test harness with stubs). **Needs the game client:** Api, Scanner, Events, Communication, UI. Keep new logic in the pure modules where possible.

## Wire protocol facts
- Messages: `HELLO {rev, login?, odig, orev?}`, `WANT {names}`, `SNAP {char, catalog}`, `OPUSH {orders}`, `ORDER {order}`, and since protocol 2.1 `WANTO {names}`, `OFFERS {offers}` (feature 007, `Core/Data/Offers.lua`; unknown types and fields are ignored by 2.0 peers). Protocol is 2.1, `Store.SCHEMA=3`. All carry `v = addon.PROTOCOL` and string `t`; `Sync` dispatches via `self["_on" .. msg.t]`.
- Transport: Codec serialize -> `CompressDeflate` -> `EncodeForWoWAddonChannel` -> chunks of `Codec.CHUNK`=225 bytes with header `major.minor|id|idx|total|part` (`Codec.MAX_PARTS`=200, queue cap 600, token bucket 5 burst / 0.9 per s). Ids carry a per-session salt. Reassembly key `sender:id`, 60 s expiry. Legacy 0.1/0.2 header `id|idx|total|part` is recognised as "older client".
- Limits in Codec: `MAX_ENCODED = CHUNK * MAX_PARTS` (one definition), `MAX_RAW=200000`, depth 8, 20000 table items. Parser rejects non-finite numbers.
- Version handling (0.3.0): major must match exactly, minor may differ (`Codec.Compat`); version is read from the chunk header before buffering; one notice per kind per session. `Store.SCHEMA=2` with `Store.Migrate` and a downgrade guard (newer saved data is never overwritten). Rules: `docs/protocol.md`.
- Inbound gate: `Guard.Accept(channel, sender, roster)`: GUILD, or WHISPER from a cached-roster member; fail closed.
- Build flag (0.3.1): `addon.BUILD` / `addon.IS_DEVELOPMENT_BUILD` are set ONLY by `Core/Base/Init.lua` (it passes the three words `ProfessionShare`, `PShare`, `ps` to LibGuildSync `Addon.Setup`, which derives every name; since LibGuildSync MINOR 2) (TOC `## X-Build: dev`, written by `tools/deploy.ps1` into the generated `ProfessionShare-Dev.toc`, or a folder name containing "dev"). Prefix `PShare`/`PShareDev`, SavedVariables, frames and slash commands derive from it; `tests/test_build_flag.lua` forbids hard-coded identity elsewhere. The dev TOC is generated and goes stale: re-run deploy.ps1 and RESTART the game after any TOC change; an installed live folder is only loaded after a restart.
- Whisper targets (0.3.2): same-realm players are addressed by character name only (`Utility.WhisperTarget` / `ShortName`, uses the game's `Ambiguate`); the `Name-Realm` form is answered with "no player named ... online". Applies to chat whispers AND addon whispers (`Communication` pump).
- Sanitizers: `Store.SanitizeChar`, `Store.SanitizeCatalogEntry`, `Orders.Sanitize` (allow-list copies); `Model` escapes `|` in every peer string.

## Review checklist
1. **Secrets:** grep the tree and `git log -p --all` for tokens/keys (`ghp_`, `AKIA`, `BEGIN .*PRIVATE`, `CF_API`, `webhook`). Secrets must appear only as `${{ secrets.* }}`. Check untracked files (`git status`), esp. `screens-debug/` (screenshots show character/realm) and `dist/`.
2. **Inbound gate:** every path from `CHAT_MSG_ADDON` must pass `Guard.Accept` before touching state or replying (`Communication.OnAddonMessage`). A new message type or channel must not bypass it.
3. **Input validation:** all network data goes through an allow-list sanitizer that copies known fields (type, length, finite and range checks). Flag any place that stores a raw peer table (`Store.PutChar`, `PutCatalog`) or an unvalidated field.
4. **Display:** every peer string reaching `SetText`/`format` must escape `|` (colour/texture/hyperlink codes). `SetHyperlink`/`SetTexture` arguments built from peer data must be validated.
5. **Version compatibility:** any change to message shape, chunk header, serializer or compression needs a `PROTOCOL` decision; any change to stored shape needs a `SCHEMA` bump plus migration. Verify old and new clients cannot misparse each other and that mismatches are surfaced to the user.
6. **Persistence:** SavedVariables are untrusted on load (hand-edited, older/newer addon). Check `Store.Init` handling.
7. **Resource bounds (defence in depth):** buffers, queue, pending lists, table sizes. Not a security finding by itself unless it enables more than slowdown.
8. **CI/release:** actions pinned to SHAs, token scoped to the step that needs it, tag filter `v*`, version from one source, `.pkgmeta` ignores `tests dev eval docs tools dist review .claude screens-debug .github`.
9. **Vendored libs:** version/provenance recorded, local modifications diffed.
10. **WoW specifics:** the only secure frames are the profession buttons (`SecureActionButtonTemplate`, macro `/cast <profession>` built by `Model.CastMacro` from the player's OWN spellbook names, never from peer data); every protected change (`SetAttribute`, `Show`/`Hide` of those buttons) must be guarded by `Api.InCombat()` and re-applied after combat; the rest of the window uses plain frames; events registered with `pcall` for unknown ones; no calls to protected APIs; timers use `C_Timer`.
11. **Tests:** each fixed finding has a regression test in `tests/`; adversarial cases exist (non-guild sender, inf/NaN, bad catalog fields, escape sequences, foreign protocol).

## Commands
```
export PATH="$PATH:$(cygpath "$LOCALAPPDATA")/Programs/LuaJIT/bin"   # Git Bash on Windows
luajit tests/run.lua          # offline suite, run from repo root; expect "N passed, 0 failed"
powershell tools/deploy.ps1   # junction into _forever_/Interface/AddOns (-WithProbe for dev/ProfessionShareProbe)
powershell tools/package.ps1  # builds dist/ProfessionShare-<version>.zip (whitelist: toc, Core, UI, Libs, README)
```
In game: `/ps version|scan|dump|comm|hello|chars|debug`, `/console scriptErrors 1`. Anything touching Api/Scanner/Events/Communication/UI is only verified by running the game; say so when it was not.

## Output rules
- Write to `review/<topic>.md`: findings with severity, file:line, impact, concrete fix; plus a priority table. Be honest about what was verified vs only read.
- Respect the trust model above: do not file guild-member tampering as a vulnerability.
- Do not change code during a review unless asked; recommend.
- Never include real tokens, character names or realm names from screenshots in committed files.

## Known references
`README.md` (trust model), `docs/api-findings.md` (verified client APIs), `docs/status.md` (verification state), `eval/plan.md` (original plan and risks), `review/` (standing findings).
