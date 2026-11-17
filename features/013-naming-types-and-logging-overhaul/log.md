# 013 Naming types and logging overhaul: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-17 11:33 | PLAN | Feature created
- Did: scaffolded `features/013-naming-types-and-logging-overhaul/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-17 11:35 | BUILD | T1-T6 complete
- Did: global renames with a token renamer (Util->Utility, Comm->Communication, Diag->Diagnostics, L->Text, Esc->Escape, Canon->CanonicalName, SafeInt->SafeInteger, Fold->FoldCase, StripControl->StripControlCharacters, Fmt->Format, Sys->System, Recanon->CanonicalizeStoredNames, SetUI->SetInterfaceLanguage, ProfKey->ProfessionKey, LocLabel->LocationLabel, IsLoc->IsLocation, LocIndex->LocationIndex, GetChar/PutChar/ListChars/SanitizeChar/ValidateChar -> ...Character(s), ValidateProfessionMeta->ValidateProfessionMetadata, Compat->Compatibility, IdentityInfo/ItemCategoryInfo/GetPlayerInfo -> ...Information, PROTO_*->PROTOCOL_*, SVNAME->SAVED_VARIABLES_NAME, IS_DEV->IS_DEVELOPMENT_BUILD, FRAME->FRAME_PREFIX, SLASH/Slash->SLASH_COMMANDS/SlashCommands, env->environment, rand->random, stats->statistics, wantedO->wantedOffers, CanonOrder->CanonicalOrder, GIVE_UP_RESET/KINDS -> GIVE_UP_RESET_SECONDS/RECORD_KINDS, Trace.MAX->MAXIMUM_ENTRIES, Codec CHUNK/MAX_PARTS/MAX_ENCODED -> CHUNK_BYTES/MAXIMUM_PARTS/MAXIMUM_ENCODED_BYTES, Guard.MAX_SEEN->MAXIMUM_SEEN, ItemText.MAX_TRIES->MAXIMUM_TRIES, Notify.THROTTLE->THROTTLE_SECONDS, Offers.LOC_ORDER->LOCATION_ORDER); file renames; new Core/Base/Log.lua; every Core/ and UI/ file rewritten (names, annotations, Log calls); test harness renamed (harness, addon, equal, character); docs
- Result: no short names left except the documented exceptions (ok, me, _G, os, UI); ns.Debug.Log and Util.ReportError removed. Found and fixed: Utility.ResetRealmAliases assigned globals (firstIndex/firstSig were declared after it)
- Evidence: `luajit tests/run.lua` -> `209 passed, 0 failed` (baseline 204; one debug-log test replaced by 6 test_log tests)
- Next: user runs tools/deploy.ps1, restarts the game and works through the in-game checklist in verify.md

## 2026-11-17 11:50 | DEVIATION | module existence guards removed (user question "why so many ifs?")
- Did: removed 25 `if addon.X then` / `addon.X and addon.X.Y` checks for modules the TOC and tests/run.lua always load before the code runs (Store, Sync, Diagnostics, Api, Init, Events, Alerts, Window); kept only the Api check in Utility.Me (offline tests run it without Api). Rule written to docs/coding-conventions.md "Module guards"
- Result: a broken load order now fails loudly (and is reported by Events' "not loaded" check / test_load) instead of silently skipping work
- Evidence: `luajit tests/run.lua` -> `209 passed, 0 failed`
- Next: unchanged: in-game checklist in verify.md
