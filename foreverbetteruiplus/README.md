# Forever Better UI Plus

Fades the default UI: one global opacity for everything, or a separate opacity per element. An element goes back
to full opacity while the mouse is over it, and in Edit Mode.

## Use
`/fbui` opens the options window. It has a global slider, the fade time, "full opacity in combat", and one row per
element. The first button on each row cycles through **Global** (uses the global slider), **Custom** (its own slider)
and **Off** (the addon leaves it alone). The second button sets the element's combat behavior: **Global** (follows the
checkbox), **Full** (fully visible in combat) or **Faded** (keeps its opacity in combat). The window can also be opened from Options > AddOns > Forever Better UI Plus.

| Command | Effect |
|---|---|
| `/fbui global 40` | global opacity 40% (`0.4` and `40%` work too) |
| `/fbui set minimap 20` / `global` / `off` | one element: own value / back to global / not touched |
| `/fbui list` | every element with its mode, opacity, and whether its frame was found |
| `/fbui combat` | toggle full opacity in combat for all elements set to global (default: stays faded) |
| `/fbui combat target full` / `faded` / `global` | one element in combat: fully visible / keeps its opacity / follows the global switch |
| `/fbui fade 0.3` | fade time in seconds (default 0.2) |
| `/fbui disable` / `enable` | stop (everything back to full opacity) / resume |
| `/fbui editmode` | list all Edit Mode settings and mark the ones the Edit Mode dialog has no control for |
| `/fbui reset`, `/fbui debug`, `/fbui log [n]`, `/fbui clearlog` | reset settings / debug log |

Elements (`/fbui list` shows their keys): action bars 1–8, stance bar, pet bar, player/target/focus/pet frames, cast bar,
minimap, buffs, debuffs, objective tracker, micro menu, bags bar, XP/reputation bars, the four cooldown viewers, chat.

## How it works
- **Saved settings:** `ForeverBetterUIPlusDB` (account-wide):
  `{ global = 0.6, fadeSeconds = 0.2, combatFull = false, elements = { minimap = 0.2, chat = "off" },
  combat = { target = true, minimap = false }, log = {...} }`.
  An element missing from `elements` uses `global`; one missing from `combat` uses `combatFull`.
- **Fading:** one `OnUpdate` (`Fader.lua`). It checks hover every 0.05 s with `frame:IsMouseOver()` instead of hooking
  `OnEnter`/`OnLeave`. That way action buttons keep their own scripts, the mouse over a child button also counts,
  and no taint is added. `SetAlpha` is called only when the frame's alpha differs, so values that Blizzard code resets
  get applied again.
- **Frames:** `Elements.lua` maps each element to the retail global frame names. A name that doesn't exist on the
  client is skipped, and the lookup runs again every 2 s because some frames (cooldown viewers) are created late.
- **Edit Mode:** while Edit Mode is open, everything is shown at full opacity. `/fbui editmode` compares
  `Enum.EditMode*Setting` with `EditModeSettingDisplayInfoManager` and flags settings that have no control in the
  Edit Mode dialog ("hidden" settings). The full list goes to the log (`/fbui log 200` or the SavedVariables file).

## Dev
- `luajit tests/run.lua`: offline tests for `Logic.lua` and `Elements.lua`.
- `powershell tools/deploy.ps1`: links this folder into the Forever AddOns folder as `ForeverBetterUIPlus`.
- `powershell tools/package.ps1`: builds `dist/ForeverBetterUIPlus-<version>.zip`.
