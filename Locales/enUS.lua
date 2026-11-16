local ADDON, ns = ...

-- English is the source language of every UI string (the key is the text), so only game data lives here.
-- Profession names by skill line id. Verified on Forever (probe): 165, 185, 393. The remaining classic skill line ids
-- are from memory and only serve as a fallback after the names the game client itself reports.
ns.Locale.Register("enUS", {
    professions = {
        [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
        [182] = "Herbalism", [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning",
        [197] = "Tailoring", [185] = "Cooking", [129] = "First Aid", [356] = "Fishing",
        [755] = "Jewelcrafting", [773] = "Inscription", [794] = "Archaeology",
    },
})
