# Grouped settings page

Status: done | Since version: 1.4.0 (unreleased) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
One settings page with every switch of ProfessionShare, grouped by feature: General (minimap button), Order
notifications, Recipe drops, Recipe list. The page scrolls.

## How to use
Interface -> AddOns -> ProfessionShare, `/ps options`, or the Options button in the window.

## How it works
`UI/Alerts.lua` `buildOptionsPanel`: a layout cursor with `addSection` / `addCheck`; every control registers a refresher
that runs when the page is shown and after every click. Settings live where they did (`ui.notify`, `ui.drops`,
`ui.minimapIcon.hide`, recipe table settings). `UI.SetMinimapButtonShown` uses LibDBIcon's Show/Hide.

## Limits and known issues
- A minimap button hidden at login gets its number badge only after /reload once shown again.

## Verification
See [verify.md](verify.md).
