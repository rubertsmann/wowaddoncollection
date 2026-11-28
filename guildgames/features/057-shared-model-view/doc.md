# 057 Shared model view: documentation

## What it does
Nothing new for the player: every 3D creature (the companion view and the pet view, the collection and guild previews,
the arena replay, the team dialog, Companion Dash, the Survivor tower) is drawn by one module, `UI/ModelView.lua`, so
they all load, frame and animate the same way and a fix in one place reaches all of them.

## Interface (for code)
`ModelView.New(parent, options)` -> view. Options (`---@class ModelViewOptions` in the file): `width`, `height`,
`preset` (`portrait`), `frameType`, `pad`, `camera`, `facing`, `idle`, `companion`, `turn`, `zoom`, `zoomMemory`,
`fallback`, `afterLoad`, `area`. The view's functions are called with a dot:

| Function | Does |
|---|---|
| `Show(creature)` | loads `{ npc, disp }` (display id, else NPC id) once; nil clears; companion views switch the pose when it falls asleep / wakes |
| `Forget()` / `Reload(reason)` | load again on the next Show / now, plus idle and a late re-frame (a panel shows) |
| `Play(key, { restart, back })` | an `ANIMATION` key or id list; `back`: idle after that many seconds; a newer call voids the timer |
| `Emote(key, reason)` | Play + back to idle after `EMOTE_SECONDS`, busy meanwhile |
| `Idle(reason)` | the resting pose (asleep for a sleeping companion) |
| `Die()` / `Revive()` | the death once then lying; nothing plays until revived or another creature is shown |
| `Face(radians)`, `Zoom(delta)`, `LookFrom(position, target)` | facing, wheel zoom (per NPC, session), custom camera |
| `Tick(now)` | companion views: an ambient emote now and then (`ModelView.ForceAmbient` from `/ggd caught emote`) |
| `Frame()`, `Refresh()`, `ModelView.RefreshAll()` | framing again (after a load, a show, the window scale) |
| `IsRendered()`, `FitDistance()`, `Has(id)`, `SetFallbackIcon(icon, mirror)` | what the client drew / fitted / has |

`view.frame` is the model frame (anchor it, give it to Animate). Journal: `caught.model.<area>` (`/gg caught log 20 model`);
`quietPoses` journals the loads only. `Capabilities()` lists the model methods the client has (`/gg caught model`).
A view lives for the session (its frame does): make it once per place.

## Limits
- The hidden models that read a unit's look (`Catcher.CaptureDisplay`, `Api.GenderProbe`) are not views: never shown.
- `UI/DevProbe.lua` probes call the raw client API on purpose (dev build only).

## Verification
See [verify.md](verify.md).
