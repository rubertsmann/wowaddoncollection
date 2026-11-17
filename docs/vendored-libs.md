# Vendored libraries

Both libraries are copied verbatim into `Libs/` and shipped in the package. Keep this file current when one is updated.

| Library | Version | Upstream | Licence | Used for |
|---|---|---|---|---|
| LibDeflate | 1.0.2-release (file header) | https://github.com/SafeteeWoW/LibDeflate (author Haoqian He) | zlib (`Libs/LibDeflate/LICENSE.txt`) | `Core/Net/Codec.lua`: DEFLATE compression and `EncodeForWoWAddonChannel` |
| LibStub | MINOR 2 | WoWAce / CurseForge standard copy | public domain (file header) | resolving LibDeflate (`LibStub:GetLibrary`) |

## Provenance
- Source: copied from the installed **Spoken** addon on the development machine (2026-11-16), not downloaded from upstream.
- SHA-256 of the files as shipped (re-check after any update, and compare with the upstream release when online):

```
76f2114e527c2be1ac5cf768a68084946a3e19f63592834640020b7c9b5a450f  Libs/LibDeflate/LibDeflate.lua
26401bc42c26d1d1b6f7ad9410aa464edcbe4d32d74ebadeeecd8c0110236f7d  Libs/LibStub/LibStub.lua
acbecf8578f4febb766a1dd0217336e2e7ec19e66d13c907e38b01b1b727d7df  Libs/LibDeflate/LICENSE.txt
```

- No local modification is known. The comment `-- Modified by LibDeflate: ... loadstring() lua api is no longer used` at
  `LibDeflate.lua:2956` is **upstream's** note about code it adapted from another library, not an edit made here.
  (An earlier review draft misread it as a local change.)
- **Not yet verified:** that the file is byte-identical to upstream 1.0.2-release (needs network access; `git diff --no-index`
  against the upstream file, or compare hashes).

## Notes
- `LibDeflate.lua` contains a command-line section (uses `io.open`, near line 3419). It never runs inside WoW (no `io`).
  It is left in so the file stays identical to upstream; stripping it would make updates harder to verify.
- `LibDeflate:DecompressDeflate` has no output limit, so a small compressed message can inflate to a large buffer. Mitigations
  in this addon: only guild messages are processed (`Core/Net/Guard.lua`), the encoded size is capped at
  `Codec.MAX_ENCODED`, and the raw size after inflate is rejected above `MAX_RAW` (checked after inflating).
- Update procedure: replace the files from the upstream release, update the versions and hashes above, run
  `luajit tests/run.lua`, then bump nothing else unless the wire output changed (a change in compression output that old
  clients cannot read is a **major** protocol bump, see `docs/protocol.md`).
