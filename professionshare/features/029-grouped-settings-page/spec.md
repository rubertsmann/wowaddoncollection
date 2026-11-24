# 029 Grouped settings page: spec

- Status: done
- Created: 2026-11-24
- Target version: 1.4.0 (UI + local settings; protocol and schema unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
One settings page (Interface -> AddOns -> ProfessionShare, `/ps options`, the window's Options button) with every switch
of the addon, grouped by feature.

## Requirements
- R1: Sections in this order: General (minimap button shown), Order notifications (the existing switches, sound, scope,
  test button), Recipe drops (share, chat, icon; feature 027), Recipe list (columns, sort).
- R2: Every control shows the stored value when the page opens and after every click.
- R3: The page scrolls (it is taller than the settings area); the plain-window fallback keeps working.
- R4: Hiding the minimap button is stored in `ui.minimapIcon.hide` (LibDBIcon's own field) and takes effect at once.

## Non-goals
- No new sharing switches for keys, reputation or offers (those features have no off switch; a later feature if wanted).

## Design
- `UI/Alerts.lua` (changed): `buildOptionsPanel` rebuilt with a layout cursor, `addSection`, `addCheck` and a list of
  refreshers, inside a `UIPanelScrollFrameTemplate` scroll frame.
- `UI/Window.lua` (changed): `UI.MinimapButtonShown`, `UI.SetMinimapButtonShown`.
- `Locales/deDE.lua`: section titles and new labels; "Notifications" replaced by "Settings" / "Order notifications".
- Data shape: none new (`ui.notify`, `ui.drops`, `ui.minimapIcon`, recipe table settings).

## Tasks
- [x] T1 (M): page rebuilt with sections and scroll. Verify: test_load builds and opens it.
- [x] T2 (S): minimap button switch. Verify: test_load.
- [ ] T3: in game: look, scroll, every switch. Verify: IN-GAME.

## Review Focus
1. RF1: a minimap button hidden at login and shown from the page has no number badge until /reload (the badge is
   attached when the button is created). Accepted limit, documented.
2. RF2: a setting changed with `/ps drops` while the page is open -> shown after reopening (OnShow refresh).

## Cross-cutting checklist
- [x] Protocol: unchanged.
- [x] Stored data: unchanged.
- [x] Trust model: n/a (no peer data).
- [x] Localization: every label through `Text[]` with deDE.
- [x] Load order: unchanged.
- [x] Packaging: unchanged.
- [x] Tests: test_load (page builds, opens, minimap switch).
- [x] Docs: README, CHANGELOG, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-24: "make it configurable in the addon's settings, all functions toggleable in a grouped view" (user, question 9: yes).
- 2026-11-24: one scrolling page with sections, not sub-categories (claude: the old client's interface options have no reliable sub-pages).
