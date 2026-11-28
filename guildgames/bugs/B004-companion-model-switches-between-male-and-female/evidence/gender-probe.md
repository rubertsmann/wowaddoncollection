# /ggd caught gender results (dev client, 2026-11-28 12:46-13:00)

Source: `caught.dev.gender` journal lines in the dev SavedVariables. Each probe was read twice (at once and after 1 s);
both reads were the same every time.

| NPC | UnitSex | unit display (SetUnit) | unit model file | npc display (SetCreature) | npc model file |
|---|---|---|---|---|---|
| 1150 | 1 | 0 | 123324 | 1039 | 123324 |
| 1108 | 2 | 0 | 124263 | 843 | 124263 |
| 1096 (x4) | 2 | 0 | 119376 | 7197 | 119376 |
| 921 | 2 | 0 | 119376 | 7198 | 119376 |
| 1564 female | 3 | 0 | 1000764 | 4462 | 1000764 |
| 1564 male | 2 | 0 | 1011653 | 4461 | 1011653 |

Findings:
- `GetDisplayInfo()` is 0 after `SetUnit` on every unit, but a real id after `SetCreature(npc)`.
- One NPC id loaded two different looks (1564: 4462 female, 4461 male): `SetCreature` picks a look per load.
- The unit's own model file is readable and differs by gender (1000764 vs 1011653), so it identifies the look.
