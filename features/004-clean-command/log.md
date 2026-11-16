# 004 Clean command: log

Append only. Newest entry at the bottom. The last entry must say what to do next.

## 2026-11-16 10:31 | BUILD | clean command
- Did: user asked "add /tsd clean that removes everything from the local store". Added `Store.Counts`/`Store.Clean` (in place) and `ns.Slash.clean` with a `confirm` step; test in tests/test_core.lua; slash presence in tests/test_load.lua
- Result: preferences, schema and `me` are kept; the order board keeps working because tables are emptied in place
- Evidence: `luajit tests/run.lua` -> 60 passed, 0 failed (59 before)
- Next: user runs `/tsd clean`, then `/tsd clean confirm` in game and checks the window is empty afterwards
