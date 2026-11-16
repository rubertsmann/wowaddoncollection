# Profession scan buttons

Status: draft | Since version: 0.2.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The game only shows a profession's recipes while that profession's window is open, and addons are not allowed to open it. The Recipes tab therefore shows one small icon per profession of your character. One click on an icon opens that profession (exactly like the macro `/cast Kochkunst`), TalentShare reads the recipes as the window loads, and the number on the icon changes from a red 0 to the number of stored recipes.

## How to use
- Open `/ts` (dev: `/tsd`), look at the top right of the Recipes tab, and click each profession icon once. You do not have to cycle through the pages of the profession menu.
- Red 0 = not read yet, green number = recipes stored. Hover for details. While all of them are still 0, a pulsing "CLICK HERE ->" label points at the icons.
- New recipes you learn later are picked up automatically; you only need the icons again after `/ts clean`.
- Without the addon the same thing works with a macro: `/cast <profession name>`.

## How it works
Each icon is a `SecureActionButtonTemplate` (`type=macro`, `macrotext="/cast <profession>"`). A real mouse click on a secure button may run a protected action; addon code may not (the first version called `C_TradeSkillUI.OpenTradeSkill`, which the game blocks: nothing opened and "Interface-Aktion auf Grund eines Addons fehlgeschlagen" appeared). The scan itself is unchanged: profession window events trigger `Scanner.Refresh`. The buttons' appearance and attributes are only changed outside combat.

## Localization
The button uses the profession name your own client reports; tooltip texts are translated (English, German).

## Limits and known issues
- One click per profession (a click can only trigger one protected action).
- The profession window stays open after reading; close it yourself.
- Up to 5 icons (the game allows at most 2 primary + 3 secondary professions).
- Whether `/cast <profession>` and the secure button open the window on WoW Forever is verified in game (see verify.md).

## Changelog line
- Profession icons in the Recipes tab: one click per profession reads its recipes (replaces cycling through the pages).
