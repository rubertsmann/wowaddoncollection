local _, addon = ...

-- Night elf NPC appearances (CreatureDisplayInfo IDs with baked textures, scale 1, with hair), classic-era tables
-- from wago.tools: CreatureDisplayInfoExtra.DisplayRaceID = 4. The first 40 per sex; /cig dance next cycles them.
addon.Displays = {
    female = {
        1543, 1682, 1700, 1702, 1707, 1714, 1716, 1717, 1719, 1721, 1723, 1727,
        1730, 1733, 1750, 1914, 1915, 1916, 1937, 1957, 1982, 2034, 2035, 2053,
        2054, 2055, 2058, 2068, 2182, 2183, 2196, 2198, 2199, 2201, 2202, 2203,
        2205, 2206, 2207, 2208,
    },
    male = {
        1285, 1527, 1528, 1701, 1703, 1704, 1706, 1709, 1712, 1718, 1722, 1725,
        1729, 1732, 1770, 1771, 1854, 1895, 1896, 1898, 1899, 1931, 1945, 1983,
        2060, 2061, 2062, 2063, 2064, 2065, 2066, 2067, 2241, 2242, 2243, 2244,
        2245, 2246, 2247, 2248,
    },
}
