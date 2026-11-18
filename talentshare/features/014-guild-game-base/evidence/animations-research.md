# Animation study (feature 014)

Date: 2026-11-17 · Status: desk research only, **nothing below is verified on the Forever client yet**.
Labels: `DOC` = documented on warcraft.wiki.gg; `COMMUNITY` = forum/library claims; `ASSUMED` = general WoW UI knowledge,
not sourced; every `COMMUNITY`/`ASSUMED` row is a probe question in section 6.

## 1. Client baseline
- Forever = build **1.60.1 (69913)**, listed next to retail 12.1.5 (69848), Mists 5.5.4, TBC 2.5.6, Vanilla 1.15.9 on every
  API page (`DOC`). Build numbers say Forever runs the current engine, so the modern UI API is likely present (`ASSUMED`, probe P1).
- Fonts in `_forever_/Fonts` are `.slug` files (Slug renderer), not TTF: a local preview must substitute fonts.
- No Blizzard UI code/art exported locally yet. `ExportInterfaceFiles code` / `ExportInterfaceFiles art` at the **login screen
  console** (start with `-console`, press `~`) writes `BlizzardInterfaceCode/` and `BlizzardInterfaceArt/` (`COMMUNITY`, wiki:
  "Viewing Blizzard's interface code"). Gives the exact FrameXML for this client (hundreds of real animation examples) and art for a preview.
- Installed addons on this machine use animations only lightly (Auctionator: `Rotation` in XML, LibDBIcon: `Alpha`), which at
  least proves those two types run on Forever.

## 2. Built-in system: AnimationGroup (`DOC`)
- `region:CreateAnimationGroup()` -> `group:CreateAnimation(type)`. Documented types: `Animation` (empty, timing/OnUpdate only),
  `Alpha`, `Scale`, `Translation`, `Rotation`, `Path`, `ControlPoints`; `FlipBook` documented separately (methods from 10.0.0).
  `VertexColor`, `TextureCoordTranslation`, `LineScale`, `LineTranslation` exist in retail (`ASSUMED`, probe P1).
- The animation acts on the group's parent region, or on a target (`SetTarget`, `SetTargetKey`, `SetChildKey`): one group on a
  card frame can drive the card, its icon and its glow together.
- Group: `Play([reverse, offset])`, `Pause`, `Stop`, `Restart`, `Finish` (stop at end of current loop), `SetLooping("NONE"|"REPEAT"|"BOUNCE")`,
  `SetAnimationSpeedMultiplier` (global slow motion: useful for debugging), `SetToFinalAlpha`, `GetProgress`,
  scripts `OnPlay`, `OnFinished(self, requested)`, `OnLoop(self, loopState)`, `OnStop`, `OnPause`, `OnUpdate`.
- Animation: `SetDuration`, `SetStartDelay`, `SetEndDelay`, `SetOrder` (same order = parallel, ascending = sequence),
  `SetSmoothing("NONE"|"IN"|"OUT"|"IN_OUT")` (`OUT_IN` = alias of `IN_OUT`), `SetSmoothProgress`.
  Only 4 easings: anything else (back, elastic, bounce) needs chaining several animations or OnUpdate.
- Alpha: `SetFromAlpha`/`SetToAlpha`. Scale: `SetScaleFrom`/`SetScaleTo`, `SetOrigin(point, x, y)` (origin semantics not documented).
  Translation: `SetOffset(x, y)`. Rotation: `SetDegrees`/`SetRadians`, `SetOrigin`.
  FlipBook: `SetFlipBookRows`, `SetFlipBookColumns`, `SetFlipBookFrames`, `SetFlipBookFrameWidth/Height` (sprite sheet on a texture).
- PlayerModel: "all animations involving moving a PlayerModel will fail silently"; only Alpha affects it (`DOC`).

## 3. Known pitfalls
| # | Pitfall | Source | Consequence for our design |
|---|---|---|---|
| K1 | Translation moves only the rendered image; the anchor stays, the frame jumps back when the group ends | `ASSUMED` + LibAnimate notes on snapping | Re-anchor in `OnFinished` (or animate a child, keep the parent fixed) |
| K2 | The mouse hit rect does not follow Translation/Scale | `ASSUMED` | Never require clicks on a moving element; disable input during moves |
| K3 | Alpha reverts at the end unless `SetToFinalAlpha(true)` | `ASSUMED` | Always set it in fade helpers, or set the final alpha in `OnFinished` |
| K4 | Alpha animation conflicts with `SetAlpha()` calls on frames with children at the same time | `COMMUNITY` (wowinterface) | One owner for alpha per frame: the helper |
| K5 | Font strings scale poorly (blurry/jumpy text) | `COMMUNITY` | Scale card frames briefly only; no text-scaling effects |
| K6 | "Long-standing bugs with alpha persistence and Translation offset semantics" | `COMMUNITY` (LibAnimate README, details not given) | Probe P3/P4 decides built-in vs LibAnimate |
| K7 | Restarting a running group (double click) | `ASSUMED` | Helper: `Stop()` + reset, or ignore while `IsPlaying()` |
| K8 | Dragging inside a scaled parent needs coordinates converted with the effective scale | `COMMUNITY` | Only relevant if a later game drags pieces |

## 4. Alternatives
- **OnUpdate** (one shared driver frame, our own tweening): full control (any easing, real position change, hit rect follows
  since we call `SetPoint`), cost = Lua per rendered frame for every animating element; run the driver only while something animates.
- **LibAnimate** (MIT, LibStub, Forever 16001 listed): 77 presets (animate.css style), keyframes for translate/scale/alpha, cubic-bezier
  easing, queues, `UpdateAnchor`/`SlideAnchor`. Built on OnUpdate. Candidate if P3/P4 fail; vendored like LibDeflate.
- **Hybrid (planned default):** built-in groups for fire-and-forget visual effects (flip, pulse, glow, fade); OnUpdate tween
  for anything that ends somewhere else (moving a card to a new slot) so the real anchor and hit rect move.

## 5. Recipes for game feel (to prototype in the preview, then confirm in game)
| Effect | Recipe |
|---|---|
| Card/tile flip | Scale X 1 -> 0 (order 1, `IN`, 0.12 s), swap texture in the first animation's `OnFinished`, Scale X 0 -> 1 (order 2, `OUT`) |
| Press feedback | Scale 1 -> 0.92 -> 1 (`BOUNCE` once or two orders), 0.08 s each |
| Pulse / "your turn" | Alpha 0.4 -> 1 on an ADD-blend glow texture, `BOUNCE`, 0.6 s |
| Shake (invalid move) | 4 Translation steps +-4 px, 0.04 s each, in sequence |
| Staggered reveal | same group template per tile, `SetStartDelay(i * 0.03)` |
| Celebration | FlipBook sparkle sheet (if P1 confirms) or a few textures with Translation + Alpha in parallel |
| Arc movement | `Path` with control points, or OnUpdate on a bezier |

## 6. Probe questions (to answer with `/ts anim` in the dev build, task T7)
| ID | Question | How the probe shows it |
|---|---|---|
| P1 | Which types does `CreateAnimation` accept on 16001 (incl. FlipBook, VertexColor, TextureCoordTranslation, Path, ControlPoints)? | `pcall` each, print ok/error |
| P2 | Do `SetSmoothing` values and `SetLooping` types behave as documented? | play each on a test square, record |
| P3 | Translation end state: does the region jump back? Does the hit rect move (OnEnter during/after)? | print `GetCenter()` + OnEnter log before/after |
| P4 | Alpha end state with and without `SetToFinalAlpha(true)`; with a parallel `SetAlpha` on the parent | print `GetAlpha()` after OnFinished |
| P5 | Scale origin semantics (`SetOrigin("BOTTOMLEFT", 0, 0)` vs default) and text sharpness while scaling | screenshot |
| P6 | Restart while playing (double trigger) | print state, screenshot |
| P7 | Cost: 25 tiles flipping at once, and 25 OnUpdate tweens | `debugprofilestop()` around frames / FPS before and after |
| P8 | Rotation on a Frame vs a Texture | screenshot |

Every answer goes into `docs/api-findings.md` (client facts) and fixes the local preview's behaviour (it must reproduce the
measured semantics, not the assumed ones).

## Sources
- https://warcraft.wiki.gg/wiki/UIOBJECT_AnimationGroup, https://warcraft.wiki.gg/wiki/UIOBJECT_Animation,
  https://warcraft.wiki.gg/wiki/API:AnimationGroup_CreateAnimation, https://warcraft.wiki.gg/wiki/UIOBJECT_Scale,
  https://warcraft.wiki.gg/wiki/UIOBJECT_Translation, https://warcraft.wiki.gg/wiki/API:Animation_SetSmoothing,
  https://warcraft.wiki.gg/wiki/API:AnimationGroup_SetLooping, https://warcraft.wiki.gg/wiki/UIOBJECT_FlipBook
- https://warcraft.wiki.gg/wiki/Viewing_Blizzard%27s_interface_code
- https://github.com/Xerrion/LibAnimate-1.0, https://www.curseforge.com/wow/addons/libanimate
- https://wowinterface.com/forums/showthread.php?p=206931 (AnimationGroup caveats)
- https://addonstudio.org/wiki/WoW:Using_OnUpdate_correctly
