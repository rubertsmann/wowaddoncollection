# Notification scope dropdown and profession level scope

Status: built, in-game check open | Since version: next release | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Settings -> Order notifications -> "Tell me about" is a dropdown with every choice, and has a new one: orders for
recipes your profession rank is high enough for, even if you do not know the recipe yet.

## How to use
`/ps options` -> Order notifications -> Tell me about: Orders for recipes I know / Orders I have the profession level
for / Orders for my professions / All orders. The hint below says what the choice means.

## How it works
- `Notify.RecipeRanks(store, recipeID)`: the recipe's rank per profession: the catalog's `minSkill` if known, else the
  lowest rank among the guild members who know the recipe (they learned it at that rank or lower).
- Scope "level": known recipe, or my rank in that profession >= that rank. No rank data -> not news.
- Stored in `db.ui.notify.scope` ("known", "level", "profession", "all"); protocol and schema unchanged.

## Limits and known issues
- The rank is an estimate from the guild: a recipe learnable at 50 but only known by members at 150 shows up only at 150.

## Changelog line
- Settings: "Tell me about" is a dropdown; new choice "Orders I have the profession level for".
