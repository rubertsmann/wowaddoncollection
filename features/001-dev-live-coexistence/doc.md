# Dev and live side by side

Status: draft | Since version: 0.2.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The working copy of the repo runs as its own addon, **TalentShare (dev)**, next to the released **TalentShare** in one WoW install, so you can regression-test the dev build against the live one.

## How to use
- Install/refresh the dev build: `powershell tools/deploy.ps1` (junction `AddOns\TalentShare-Dev` -> repo; `/reload` after editing files).
- Install the live build for comparison: `powershell tools/package.ps1`, then `powershell tools/deploy.ps1 -InstallLive` (or install from CurseForge). A real `TalentShare` folder is never overwritten without `-Force`.
- Live: `/ts`, dev: `/tsd`.

## How it works
| | live | dev |
|---|---|---|
| addon folder | `TalentShare` | `TalentShare-Dev` |
| title / version | TalentShare / `0.2.0` | TalentShare (dev) / `0.2.0-dev` |
| SavedVariables | `TalentShareDB` | `TalentShareDevDB` |
| addon-message prefix | `TShare` | `TShareDev` |
| slash | `/ts`, `/talentshare` | `/tsd`, `/talentsharedev` |
| frames | `TalentShareFrame`, `TalentShareMinimapButton` | `TalentShareDev...` |

`Core/Init.lua` derives all of this from the folder name; `TalentShare-Dev.toc` is generated from `TalentShare.toc` by the deploy script and is git/package-ignored.

## Limits and known issues
- Dev and live do not exchange data (different prefix). Test cross-version sync with two live-prefix builds.
- The existing `TalentShareDB` (from the old junction setup) now belongs to the live addon; the dev addon starts empty and fills on first scan.

## Changelog line
- Dev builds install side by side as `TalentShare-Dev` (own data, prefix and `/tsd`).
