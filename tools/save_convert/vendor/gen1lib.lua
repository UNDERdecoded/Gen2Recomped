-- gen1lib.lua
--
-- Shared library for converting Pokemon Generation 1 (Red/Blue/Yellow)
-- save files between their native binary format and JSON.
--
-- Scope: International (non-Japanese) 32768-byte (0x8000) save files only.
-- Logic ported from PKHeX.Core:
--   PKHeX.Core/Saves/SAV1.cs, SAV1Offsets.cs
--   PKHeX.Core/PKM/PK1.cs, GBPKM.cs, GBPKML.cs
--   PKHeX.Core/PKM/Strings/StringConverter1.cs
--   PKHeX.Core/PKM/Util/Conversion/SpeciesConverter.cs
--   PKHeX.Core/Saves/Storage/PokeList1.cs
--
-- Requires Lua 5.3+ (native bitwise operators, floor division, utf8 library).

local M = {}

------------------------------------------------------------------------
-- Layout constants (International save layout only)
------------------------------------------------------------------------

M.SIZE_SAVE = 0x8000

M.OFS = {
    OT                = 0x2598,
    DexCaught         = 0x25A3,
    DexSeen           = 0x25B6,
    Items             = 0x25C9,
    Money             = 0x25F3,
    Rival             = 0x25F6,
    Options           = 0x2601,
    Badges            = 0x2602,
    TID16             = 0x2605,
    PikaFriendship    = 0x271C,
    PikaBeachScore    = 0x2741,
    PrinterBrightness = 0x2744,
    PCItems           = 0x27E6,
    CurrentBoxIndex   = 0x284C,
    HallOfFameCount   = 0x284E,
    Coin              = 0x2850,
    ObjectSpawnFlags  = 0x2852,
    EventWork         = 0x289C,
    Starter           = 0x29C3,
    EventFlag         = 0x29F3,
    PlayTime          = 0x2CED,
    Daycare           = 0x2CF4,
    Party             = 0x2F2C,
    CurrentBox        = 0x30C0,
    ChecksumOfs       = 0x3523,
}

M.BOX_COUNT = 12
M.BOX_SLOT_COUNT = 20
M.STRING_LENGTH = 11 -- OT name / rival name / nickname raw buffer length (incl. terminator)
M.SIZE_STORED = 33   -- boxed PK1 struct size
M.SIZE_PARTY = 44    -- party PK1 struct size

M.SIZE_BOX_LIST = ((M.STRING_LENGTH * 2) + M.SIZE_STORED + 1) * M.BOX_SLOT_COUNT + 2
M.SIZE_PARTY_LIST = ((M.STRING_LENGTH * 2) + M.SIZE_PARTY + 1) * 6 + 2

-- Non-current boxes live in two banked arrays at 0x4000 (boxes 1-6) and
-- 0x6000 (boxes 7-12). Whichever box is "current" is instead read from/
-- written to M.OFS.CurrentBox, and mirrored back into its normal slot here
-- on save (SAV1.cs Initialize()/GetFinalData()).
function M.box_bank_offset(boxIndexZero)
    local half = M.BOX_COUNT // 2
    if boxIndexZero < half then
        return 0x4000 + boxIndexZero * M.SIZE_BOX_LIST
    else
        return 0x6000 + (boxIndexZero - half) * M.SIZE_BOX_LIST
    end
end

------------------------------------------------------------------------
-- Byte buffer helpers
-- `buf` is a plain Lua array of integers 0-255, 1-indexed, where
-- buf[fileOffset + 1] holds the byte at `fileOffset`.
------------------------------------------------------------------------

local function get(buf, ofs) return buf[ofs + 1] end
local function set(buf, ofs, v) buf[ofs + 1] = v & 0xFF end

local function read_u16be(buf, ofs) return (get(buf, ofs) << 8) | get(buf, ofs + 1) end
local function write_u16be(buf, ofs, v)
    set(buf, ofs, (v >> 8) & 0xFF)
    set(buf, ofs + 1, v & 0xFF)
end

local function read_u24be(buf, ofs)
    return (get(buf, ofs) << 16) | (get(buf, ofs + 1) << 8) | get(buf, ofs + 2)
end
local function write_u24be(buf, ofs, v)
    set(buf, ofs, (v >> 16) & 0xFF)
    set(buf, ofs + 1, (v >> 8) & 0xFF)
    set(buf, ofs + 2, v & 0xFF)
end

-- n-byte binary-coded decimal (two decimal digits per byte).
local function bcd_read(buf, ofs, n, littleEndian)
    local bytes = {}
    for i = 0, n - 1 do bytes[i + 1] = get(buf, ofs + i) end
    if littleEndian then
        local rev = {}
        for i = 1, n do rev[i] = bytes[n - i + 1] end
        bytes = rev
    end
    local v = 0
    for _, b in ipairs(bytes) do
        v = v * 100 + ((b >> 4) * 10) + (b & 0xF)
    end
    return v
end

local function bcd_write(buf, ofs, n, littleEndian, value)
    local bytes = {}
    local v = value
    for i = n, 1, -1 do
        local d = v % 100
        v = (v - d) // 100
        bytes[i] = ((d // 10) << 4) | (d % 10)
    end
    if littleEndian then
        local rev = {}
        for i = 1, n do rev[i] = bytes[n - i + 1] end
        bytes = rev
    end
    for i = 0, n - 1 do set(buf, ofs + i, bytes[i + 1]) end
end

------------------------------------------------------------------------
-- Species: Gen 1 internal index <-> National Dex ID
-- (PKHeX.Core/PKM/Util/Conversion/SpeciesConverter.cs, Table1*)
------------------------------------------------------------------------

-- index (1-based) = National Dex ID + 1; value = Gen1 internal species byte
local NAT_TO_INTERNAL = {
0x00, 0x99, 0x09, 0x9A, 0xB0, 0xB2, 0xB4, 0xB1, 0xB3, 0x1C, 0x7B, 0x7C, 0x7D, 0x70, 0x71, 0x72,
0x24, 0x96, 0x97, 0xA5, 0xA6, 0x05, 0x23, 0x6C, 0x2D, 0x54, 0x55, 0x60, 0x61, 0x0F, 0xA8, 0x10,
0x03, 0xA7, 0x07, 0x04, 0x8E, 0x52, 0x53, 0x64, 0x65, 0x6B, 0x82, 0xB9, 0xBA, 0xBB, 0x6D, 0x2E,
0x41, 0x77, 0x3B, 0x76, 0x4D, 0x90, 0x2F, 0x80, 0x39, 0x75, 0x21, 0x14, 0x47, 0x6E, 0x6F, 0x94,
0x26, 0x95, 0x6A, 0x29, 0x7E, 0xBC, 0xBD, 0xBE, 0x18, 0x9B, 0xA9, 0x27, 0x31, 0xA3, 0xA4, 0x25,
0x08, 0xAD, 0x36, 0x40, 0x46, 0x74, 0x3A, 0x78, 0x0D, 0x88, 0x17, 0x8B, 0x19, 0x93, 0x0E, 0x22,
0x30, 0x81, 0x4E, 0x8A, 0x06, 0x8D, 0x0C, 0x0A, 0x11, 0x91, 0x2B, 0x2C, 0x0B, 0x37, 0x8F, 0x12,
0x01, 0x28, 0x1E, 0x02, 0x5C, 0x5D, 0x9D, 0x9E, 0x1B, 0x98, 0x2A, 0x1A, 0x48, 0x35, 0x33, 0x1D,
0x3C, 0x85, 0x16, 0x13, 0x4C, 0x66, 0x69, 0x68, 0x67, 0xAA, 0x62, 0x63, 0x5A, 0x5B, 0xAB, 0x84,
0x4A, 0x4B, 0x49, 0x58, 0x59, 0x42, 0x83, 0x15,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
}

-- index (1-based) = Gen1 internal species byte + 1; value = National Dex ID
local INTERNAL_TO_NAT = {
0x00, 0x70, 0x73, 0x20, 0x23, 0x15, 0x64, 0x22, 0x50, 0x02, 0x67, 0x6C, 0x66, 0x58, 0x5E, 0x1D,
0x1F, 0x68, 0x6F, 0x83, 0x3B, 0x97, 0x82, 0x5A, 0x48, 0x5C, 0x7B, 0x78, 0x09, 0x7F, 0x72, 0x00,
0x00, 0x3A, 0x5F, 0x16, 0x10, 0x4F, 0x40, 0x4B, 0x71, 0x43, 0x7A, 0x6A, 0x6B, 0x18, 0x2F, 0x36,
0x60, 0x4C, 0x00, 0x7E, 0x00, 0x7D, 0x52, 0x6D, 0x00, 0x38, 0x56, 0x32, 0x80, 0x00, 0x00, 0x00,
0x53, 0x30, 0x95, 0x00, 0x00, 0x00, 0x54, 0x3C, 0x7C, 0x92, 0x90, 0x91, 0x84, 0x34, 0x62, 0x00,
0x00, 0x00, 0x25, 0x26, 0x19, 0x1A, 0x00, 0x00, 0x93, 0x94, 0x8C, 0x8D, 0x74, 0x75, 0x00, 0x00,
0x1B, 0x1C, 0x8A, 0x8B, 0x27, 0x28, 0x85, 0x88, 0x87, 0x86, 0x42, 0x29, 0x17, 0x2E, 0x3D, 0x3E,
0x0D, 0x0E, 0x0F, 0x00, 0x55, 0x39, 0x33, 0x31, 0x57, 0x00, 0x00, 0x0A, 0x0B, 0x0C, 0x44, 0x00,
0x37, 0x61, 0x2A, 0x96, 0x8F, 0x81, 0x00, 0x00, 0x59, 0x00, 0x63, 0x5B, 0x00, 0x65, 0x24, 0x6E,
0x35, 0x69, 0x00, 0x5D, 0x3F, 0x41, 0x11, 0x12, 0x79, 0x01, 0x03, 0x49, 0x00, 0x76, 0x77, 0x00,
0x00, 0x00, 0x00, 0x4D, 0x4E, 0x13, 0x14, 0x21, 0x1E, 0x4A, 0x89, 0x8E, 0x00, 0x51, 0x00, 0x00,
0x04, 0x07, 0x05, 0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x2B, 0x2C, 0x2D, 0x45, 0x46, 0x47, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
}

function M.national_to_internal(species)
    return NAT_TO_INTERNAL[species + 1] or 0
end

function M.internal_to_national(raw)
    return INTERNAL_TO_NAT[raw + 1] or 0
end

------------------------------------------------------------------------
-- Species names (English, National Dex 1-151; PKHeX.Core Resources/text/other/en/text_Species_en.txt)
-- Informational only ("species_name" in JSON) -- ignored when converting back to a save.
------------------------------------------------------------------------

M.SPECIES_NAMES = {
    [1] = "Bulbasaur", [2] = "Ivysaur", [3] = "Venusaur", [4] = "Charmander",
    [5] = "Charmeleon", [6] = "Charizard", [7] = "Squirtle", [8] = "Wartortle",
    [9] = "Blastoise", [10] = "Caterpie", [11] = "Metapod", [12] = "Butterfree",
    [13] = "Weedle", [14] = "Kakuna", [15] = "Beedrill", [16] = "Pidgey",
    [17] = "Pidgeotto", [18] = "Pidgeot", [19] = "Rattata", [20] = "Raticate",
    [21] = "Spearow", [22] = "Fearow", [23] = "Ekans", [24] = "Arbok",
    [25] = "Pikachu", [26] = "Raichu", [27] = "Sandshrew", [28] = "Sandslash",
    [29] = "Nidoran\u{2640}", [30] = "Nidorina", [31] = "Nidoqueen", [32] = "Nidoran\u{2642}",
    [33] = "Nidorino", [34] = "Nidoking", [35] = "Clefairy", [36] = "Clefable",
    [37] = "Vulpix", [38] = "Ninetales", [39] = "Jigglypuff", [40] = "Wigglytuff",
    [41] = "Zubat", [42] = "Golbat", [43] = "Oddish", [44] = "Gloom",
    [45] = "Vileplume", [46] = "Paras", [47] = "Parasect", [48] = "Venonat",
    [49] = "Venomoth", [50] = "Diglett", [51] = "Dugtrio", [52] = "Meowth",
    [53] = "Persian", [54] = "Psyduck", [55] = "Golduck", [56] = "Mankey",
    [57] = "Primeape", [58] = "Growlithe", [59] = "Arcanine", [60] = "Poliwag",
    [61] = "Poliwhirl", [62] = "Poliwrath", [63] = "Abra", [64] = "Kadabra",
    [65] = "Alakazam", [66] = "Machop", [67] = "Machoke", [68] = "Machamp",
    [69] = "Bellsprout", [70] = "Weepinbell", [71] = "Victreebel", [72] = "Tentacool",
    [73] = "Tentacruel", [74] = "Geodude", [75] = "Graveler", [76] = "Golem",
    [77] = "Ponyta", [78] = "Rapidash", [79] = "Slowpoke", [80] = "Slowbro",
    [81] = "Magnemite", [82] = "Magneton", [83] = "Farfetch\u{2019}d", [84] = "Doduo",
    [85] = "Dodrio", [86] = "Seel", [87] = "Dewgong", [88] = "Grimer",
    [89] = "Muk", [90] = "Shellder", [91] = "Cloyster", [92] = "Gastly",
    [93] = "Haunter", [94] = "Gengar", [95] = "Onix", [96] = "Drowzee",
    [97] = "Hypno", [98] = "Krabby", [99] = "Kingler", [100] = "Voltorb",
    [101] = "Electrode", [102] = "Exeggcute", [103] = "Exeggutor", [104] = "Cubone",
    [105] = "Marowak", [106] = "Hitmonlee", [107] = "Hitmonchan", [108] = "Lickitung",
    [109] = "Koffing", [110] = "Weezing", [111] = "Rhyhorn", [112] = "Rhydon",
    [113] = "Chansey", [114] = "Tangela", [115] = "Kangaskhan", [116] = "Horsea",
    [117] = "Seadra", [118] = "Goldeen", [119] = "Seaking", [120] = "Staryu",
    [121] = "Starmie", [122] = "Mr. Mime", [123] = "Scyther", [124] = "Jynx",
    [125] = "Electabuzz", [126] = "Magmar", [127] = "Pinsir", [128] = "Tauros",
    [129] = "Magikarp", [130] = "Gyarados", [131] = "Lapras", [132] = "Ditto",
    [133] = "Eevee", [134] = "Vaporeon", [135] = "Jolteon", [136] = "Flareon",
    [137] = "Porygon", [138] = "Omanyte", [139] = "Omastar", [140] = "Kabuto",
    [141] = "Kabutops", [142] = "Aerodactyl", [143] = "Snorlax", [144] = "Articuno",
    [145] = "Zapdos", [146] = "Moltres", [147] = "Dratini", [148] = "Dragonair",
    [149] = "Dragonite", [150] = "Mewtwo", [151] = "Mew",
}

------------------------------------------------------------------------
-- Gen 1 text encoding, international/English table
-- (PKHeX.Core/PKM/Strings/StringConverter1.cs, TableEN)
-- `false` marks a byte that decodes to the string terminator (NUL).
------------------------------------------------------------------------

local TABLE_EN = {
    -- 0x00-0x0F
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    -- 0x10-0x1F
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    -- 0x20-0x2F
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    -- 0x30-0x3F
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    -- 0x40-0x4F
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    -- 0x50-0x5F (0x50 terminator, 0x5D in-game-trade marker)
    false, false, false, false, false, false, false, false, false, false, false, false, false, "*", false, false,
    -- 0x60-0x6F
    false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
    -- 0x70-0x7F
    "@", "#", "\u{201C}", "\u{201D}", false, "\u{2026}", false, false, false, "\u{250C}", "\u{2500}", "\u{2510}", "\u{2502}", "\u{2514}", "\u{2518}", " ",
    -- 0x80-0x8F
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
    -- 0x90-0x9F
    "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "(", ")", ":", ";", "[", "]",
    -- 0xA0-0xAF
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p",
    -- 0xB0-0xBF
    "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "\u{E0}", "\u{E8}", "\u{E9}", "\u{F9}", "\u{C0}", "\u{C1}",
    -- 0xC0-0xCF
    "\u{C4}", "\u{D6}", "\u{DC}", "\u{E4}", "\u{F6}", "\u{FC}", "\u{C8}", "\u{C9}", "\u{CC}", "\u{CD}", "\u{D1}", "\u{D2}", "\u{D3}", "\u{D9}", "\u{DA}", "\u{E1}",
    -- 0xD0-0xDF
    "\u{EC}", "\u{ED}", "\u{F1}", "\u{F2}", "\u{F3}", "\u{FA}", "\u{BA}", false, false, false, false, false, false, false, "\u{2190}", "'",
    -- 0xE0-0xEF
    "\u{2019}", "{", "}", "-", false, false, "?", "!", "\u{2024}", "&", "%", "\u{2192}", "\u{25B7}", "\u{25B6}", "\u{25BC}", "\u{2642}",
    -- 0xF0-0xFF
    "\u{A5}", "\u{D7}", ".", "/", ",", "\u{2640}", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
}

local CHAR_TO_BYTE = {}
for b = 0, 255 do
    local c = TABLE_EN[b + 1]
    if c then CHAR_TO_BYTE[c] = b end
end

-- Decodes a fixed-length Gen 1 string buffer into a Lua (UTF-8) string.
function M.decode_string(buf, ofs, bufLen)
    if get(buf, ofs) == 0x5D then return "*" end -- in-game trade OT placeholder
    local out = {}
    for i = 0, bufLen - 1 do
        local c = TABLE_EN[get(buf, ofs + i) + 1]
        if not c then break end
        out[#out + 1] = c
    end
    return table.concat(out)
end

-- Encodes a Lua (UTF-8) string into a fixed-length Gen 1 string buffer,
-- padding the remainder with the 0x50 terminator byte.
function M.encode_string(buf, ofs, bufLen, str)
    for i = 0, bufLen - 1 do set(buf, ofs + i, 0x50) end
    str = str or ""
    if str == "" then return end
    if str == "*" then
        set(buf, ofs, 0x5D)
        if bufLen > 1 then set(buf, ofs + 1, 0x50) end
        return
    end
    local i = 0
    for _, cp in utf8.codes(str) do
        if i >= bufLen then break end
        local ch = utf8.char(cp)
        local b = CHAR_TO_BYTE[ch]
        if not b then
            error(string.format("character %q is not representable in the Gen 1 international character set", ch))
        end
        set(buf, ofs + i, b)
        i = i + 1
    end
    if i < bufLen then set(buf, ofs + i, 0x50) end
end

------------------------------------------------------------------------
-- PK1 struct (PKHeX.Core/PKM/PK1.cs, GBPKM.cs)
-- Offsets below are relative to the start of the 33/44-byte struct.
------------------------------------------------------------------------

local function parse_pk1_body(buf, ofs, isParty)
    local speciesInternal = get(buf, ofs + 0x00)
    local dv16 = read_u16be(buf, ofs + 0x1B)
    local ivAtk = (dv16 >> 12) & 0xF
    local ivDef = (dv16 >> 8) & 0xF
    local ivSpe = (dv16 >> 4) & 0xF
    local ivSpc = dv16 & 0xF
    local ivHp = ((ivAtk & 1) << 3) | ((ivDef & 1) << 2) | ((ivSpe & 1) << 1) | (ivSpc & 1)

    local pp1b, pp2b, pp3b, pp4b = get(buf, ofs + 0x1D), get(buf, ofs + 0x1E), get(buf, ofs + 0x1F), get(buf, ofs + 0x20)
    local species = M.internal_to_national(speciesInternal)

    local pairs_ = {
        { "species", species },
        { "species_name", M.SPECIES_NAMES[species] },
        { "nickname", "" }, -- filled in by parse_mon_list; placeholder keeps the key ordered here
        { "level", isParty and get(buf, ofs + 0x21) or get(buf, ofs + 0x03) },
        { "ot_name", "" }, -- filled in by parse_mon_list
        { "ot_id", read_u16be(buf, ofs + 0x0C) },
        { "current_hp", read_u16be(buf, ofs + 0x01) },
        { "status_condition", get(buf, ofs + 0x04) },
        { "type1", get(buf, ofs + 0x05) },
        { "type2", get(buf, ofs + 0x06) },
        { "catch_rate", get(buf, ofs + 0x07) },
        { "moves", { get(buf, ofs + 0x08), get(buf, ofs + 0x09), get(buf, ofs + 0x0A), get(buf, ofs + 0x0B) } },
        { "pp", { pp1b & 0x3F, pp2b & 0x3F, pp3b & 0x3F, pp4b & 0x3F } },
        { "pp_ups", { (pp1b >> 6) & 0x3, (pp2b >> 6) & 0x3, (pp3b >> 6) & 0x3, (pp4b >> 6) & 0x3 } },
        { "exp", read_u24be(buf, ofs + 0x0E) },
        { "evs", M.omap({
            { "hp", read_u16be(buf, ofs + 0x11) }, { "atk", read_u16be(buf, ofs + 0x13) },
            { "def", read_u16be(buf, ofs + 0x15) }, { "spe", read_u16be(buf, ofs + 0x17) },
            { "spc", read_u16be(buf, ofs + 0x19) },
        }) },
        { "ivs", M.omap({
            { "atk", ivAtk }, { "def", ivDef }, { "spe", ivSpe }, { "spc", ivSpc }, { "hp", ivHp },
        }) },
    }

    if isParty then
        pairs_[#pairs_ + 1] = { "stats", M.omap({
            { "hp_max", read_u16be(buf, ofs + 0x22) }, { "atk", read_u16be(buf, ofs + 0x24) },
            { "def", read_u16be(buf, ofs + 0x26) }, { "spe", read_u16be(buf, ofs + 0x28) },
            { "spc", read_u16be(buf, ofs + 0x2A) },
        }) }
    end
    return M.omap(pairs_)
end

local function write_pk1_body(buf, ofs, sizeBody, isParty, mon)
    for i = 0, sizeBody - 1 do set(buf, ofs + i, 0) end
    set(buf, ofs + 0x00, M.national_to_internal(mon.species))
    write_u16be(buf, ofs + 0x01, mon.current_hp or 0)
    set(buf, ofs + 0x03, mon.level or 1)
    set(buf, ofs + 0x04, mon.status_condition or 0)
    set(buf, ofs + 0x05, mon.type1 or 0)
    set(buf, ofs + 0x06, mon.type2 or 0)
    set(buf, ofs + 0x07, mon.catch_rate or 0)
    local moves = mon.moves or {0, 0, 0, 0}
    set(buf, ofs + 0x08, moves[1] or 0)
    set(buf, ofs + 0x09, moves[2] or 0)
    set(buf, ofs + 0x0A, moves[3] or 0)
    set(buf, ofs + 0x0B, moves[4] or 0)
    write_u16be(buf, ofs + 0x0C, mon.ot_id or 0)
    write_u24be(buf, ofs + 0x0E, mon.exp or 0)
    local evs = mon.evs or {}
    write_u16be(buf, ofs + 0x11, evs.hp or 0)
    write_u16be(buf, ofs + 0x13, evs.atk or 0)
    write_u16be(buf, ofs + 0x15, evs.def or 0)
    write_u16be(buf, ofs + 0x17, evs.spe or 0)
    write_u16be(buf, ofs + 0x19, evs.spc or 0)
    local ivs = mon.ivs or {}
    local dv16 = ((ivs.atk or 0) & 0xF) << 12 | ((ivs.def or 0) & 0xF) << 8 | ((ivs.spe or 0) & 0xF) << 4 | ((ivs.spc or 0) & 0xF)
    write_u16be(buf, ofs + 0x1B, dv16)
    local pp = mon.pp or {0, 0, 0, 0}
    local ppUps = mon.pp_ups or {0, 0, 0, 0}
    set(buf, ofs + 0x1D, ((ppUps[1] or 0) & 0x3) << 6 | ((pp[1] or 0) & 0x3F))
    set(buf, ofs + 0x1E, ((ppUps[2] or 0) & 0x3) << 6 | ((pp[2] or 0) & 0x3F))
    set(buf, ofs + 0x1F, ((ppUps[3] or 0) & 0x3) << 6 | ((pp[3] or 0) & 0x3F))
    set(buf, ofs + 0x20, ((ppUps[4] or 0) & 0x3) << 6 | ((pp[4] or 0) & 0x3F))

    if isParty then
        set(buf, ofs + 0x21, mon.level or 1)
        local stats = mon.stats or {}
        write_u16be(buf, ofs + 0x22, stats.hp_max or 0)
        write_u16be(buf, ofs + 0x24, stats.atk or 0)
        write_u16be(buf, ofs + 0x26, stats.def or 0)
        write_u16be(buf, ofs + 0x28, stats.spe or 0)
        write_u16be(buf, ofs + 0x2A, stats.spc or 0)
    end
end

------------------------------------------------------------------------
-- Packed box/party lists (PKHeX.Core/Saves/Storage/PokeList1.cs)
--   u8               count of occupied slots
--   u8[capacity+1]   per-slot species marker (0xFF = empty); last byte always 0xFF
--   pk1[capacity]    PK1 struct data (no strings), `sizeBody` bytes each
--   str[capacity]    Original Trainer name table, STRING_LENGTH bytes each
--   str[capacity]    Nickname table, STRING_LENGTH bytes each
------------------------------------------------------------------------

local function parse_mon_list(buf, absBase, capacity, sizeBody, isParty)
    local count = get(buf, absBase)
    if count > capacity then count = capacity end
    local start = 1 + (capacity + 1)
    local bodyBase = absBase + start
    local otBase = bodyBase + sizeBody * capacity
    local nickBase = otBase + capacity * M.STRING_LENGTH

    local list = {}
    for i = 0, count - 1 do
        local mon = parse_pk1_body(buf, bodyBase + sizeBody * i, isParty)
        mon.ot_name = M.decode_string(buf, otBase + M.STRING_LENGTH * i, M.STRING_LENGTH)
        mon.nickname = M.decode_string(buf, nickBase + M.STRING_LENGTH * i, M.STRING_LENGTH)
        list[#list + 1] = mon
    end
    return list
end

local function write_mon_list(buf, absBase, capacity, sizeBody, isParty, monList)
    local count = #monList
    if count > capacity then
        error(string.format("list has %d Pokemon, but capacity is only %d", count, capacity))
    end
    set(buf, absBase, count)

    local start = 1 + (capacity + 1)
    for i = 0, capacity - 1 do
        local mon = monList[i + 1]
        set(buf, absBase + 1 + i, mon and M.national_to_internal(mon.species) or 0xFF)
    end
    set(buf, absBase + 1 + capacity, 0xFF) -- list terminator, always present

    local bodyBase = absBase + start
    local otBase = bodyBase + sizeBody * capacity
    local nickBase = otBase + capacity * M.STRING_LENGTH

    -- Only touch bytes for occupied slots (i < count). Slots beyond `count`
    -- are inert as far as the game is concerned (the marker byte above
    -- already flags them 0xFF/empty), so their body/name bytes are left
    -- exactly as they were in the original save instead of being normalized.
    for i = 0, count - 1 do
        local mon = monList[i + 1]
        local bodyOfs = bodyBase + sizeBody * i
        local otOfs = otBase + M.STRING_LENGTH * i
        local nickOfs = nickBase + M.STRING_LENGTH * i
        write_pk1_body(buf, bodyOfs, sizeBody, isParty, mon)
        M.encode_string(buf, otOfs, M.STRING_LENGTH, mon.ot_name)
        M.encode_string(buf, nickOfs, M.STRING_LENGTH, mon.nickname)
    end
end

------------------------------------------------------------------------
-- Checksum (SAV1.cs: GetRBYChecksum / SetChecksums)
-- One's complement of the byte-sum over [OFS.OT, OFS.ChecksumOfs).
------------------------------------------------------------------------

local function compute_checksum(buf)
    local sum = 0
    for i = M.OFS.OT, M.OFS.ChecksumOfs - 1 do
        sum = sum + get(buf, i)
    end
    return (255 - (sum % 256)) & 0xFF
end

------------------------------------------------------------------------
-- Bytes <-> Lua string, base64
------------------------------------------------------------------------

function M.bytes_to_string(buf, len)
    len = len or #buf
    local chars = {}
    for i = 1, len do chars[i] = string.char(buf[i] & 0xFF) end
    return table.concat(chars)
end

function M.string_to_bytes(s)
    local buf = {}
    for i = 1, #s do buf[i] = string.byte(s, i) end
    return buf
end

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_REV = {}
for idx = 1, #B64_CHARS do B64_REV[B64_CHARS:sub(idx, idx)] = idx - 1 end

function M.base64_encode(data)
    local out = {}
    local len = #data
    local i = 1
    while i <= len do
        local b1 = string.byte(data, i)
        local b2 = string.byte(data, i + 1)
        local b3 = string.byte(data, i + 2)
        local n = b1 << 16
        if b2 then n = n | (b2 << 8) end
        if b3 then n = n | b3 end
        out[#out + 1] = B64_CHARS:sub((n >> 18 & 0x3F) + 1, (n >> 18 & 0x3F) + 1)
        out[#out + 1] = B64_CHARS:sub((n >> 12 & 0x3F) + 1, (n >> 12 & 0x3F) + 1)
        out[#out + 1] = b2 and B64_CHARS:sub((n >> 6 & 0x3F) + 1, (n >> 6 & 0x3F) + 1) or "="
        out[#out + 1] = b3 and B64_CHARS:sub((n & 0x3F) + 1, (n & 0x3F) + 1) or "="
        i = i + 3
    end
    return table.concat(out)
end

function M.base64_decode(s)
    s = s:gsub("[^A-Za-z0-9+/=]", "")
    local out = {}
    local i = 1
    local len = #s
    while i <= len do
        local c1 = B64_REV[s:sub(i, i)]
        local c2 = B64_REV[s:sub(i + 1, i + 1)]
        local s3, s4 = s:sub(i + 2, i + 2), s:sub(i + 3, i + 3)
        local c3, c4 = B64_REV[s3], B64_REV[s4]
        local n = (c1 << 18) | (c2 << 12) | ((c3 or 0) << 6) | (c4 or 0)
        out[#out + 1] = string.char((n >> 16) & 0xFF)
        if s3 ~= "=" and s3 ~= "" then out[#out + 1] = string.char((n >> 8) & 0xFF) end
        if s4 ~= "=" and s4 ~= "" then out[#out + 1] = string.char(n & 0xFF) end
        i = i + 4
    end
    return table.concat(out)
end

------------------------------------------------------------------------
-- Minimal pure-Lua JSON codec (no external dependencies).
-- M.omap(list) builds an object that encodes with a fixed, readable key
-- order instead of falling back to alphabetical sorting.
------------------------------------------------------------------------

local ORDER_KEY = "__order__"

function M.omap(pairsList)
    local t = { [ORDER_KEY] = {} }
    for _, kv in ipairs(pairsList) do
        t[kv[1]] = kv[2]
        table.insert(t[ORDER_KEY], kv[1])
    end
    return t
end

local function escape_str(s)
    local out = {}
    for i = 1, #s do
        local b = string.byte(s, i)
        if b == 34 then out[#out + 1] = '\\"'
        elseif b == 92 then out[#out + 1] = "\\\\"
        elseif b == 8 then out[#out + 1] = "\\b"
        elseif b == 9 then out[#out + 1] = "\\t"
        elseif b == 10 then out[#out + 1] = "\\n"
        elseif b == 12 then out[#out + 1] = "\\f"
        elseif b == 13 then out[#out + 1] = "\\r"
        elseif b < 0x20 then out[#out + 1] = string.format("\\u%04x", b)
        else out[#out + 1] = s:sub(i, i)
        end
    end
    return table.concat(out)
end

local function array_len(t)
    local n = 0
    for k, _ in pairs(t) do
        if k == ORDER_KEY then goto continue end
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then return nil end
        if k > n then n = k end
        ::continue::
    end
    for i = 1, n do if t[i] == nil then return nil end end
    return n
end

local function encode_value(value, ind)
    local t = type(value)
    if value == nil then return "null" end
    if t == "boolean" then return tostring(value) end
    if t == "number" then
        if value == math.floor(value) and math.abs(value) < 1e15 then
            return string.format("%d", value)
        end
        return tostring(value)
    end
    if t == "string" then return '"' .. escape_str(value) .. '"' end
    if t == "table" then
        local nextIndent = ind .. "  "
        if value[ORDER_KEY] then
            local keys = value[ORDER_KEY]
            if #keys == 0 then return "{}" end
            local parts = {}
            for _, k in ipairs(keys) do
                parts[#parts + 1] = nextIndent .. '"' .. escape_str(k) .. '": ' .. encode_value(value[k], nextIndent)
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
        end
        if next(value) == nil then return "[]" end
        local n = array_len(value)
        if n then
            local parts = {}
            for i = 1, n do parts[#parts + 1] = nextIndent .. encode_value(value[i], nextIndent) end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "]"
        end
        local keys = {}
        for k, _ in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = nextIndent .. '"' .. escape_str(tostring(k)) .. '": ' .. encode_value(value[k], nextIndent)
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
    end
    error("cannot JSON-encode a value of type " .. t)
end

function M.json_encode(value)
    return encode_value(value, "")
end

local function skip_ws(s, i)
    while i <= #s do
        local c = s:sub(i, i)
        if c == " " or c == "\t" or c == "\n" or c == "\r" then i = i + 1 else break end
    end
    return i
end

local parse_value

local function parse_string(s, i)
    i = i + 1 -- opening quote
    local out = {}
    while true do
        local c = s:sub(i, i)
        if c == "" then error("unterminated string in JSON input") end
        if c == '"' then i = i + 1; break end
        if c == "\\" then
            local e = s:sub(i + 1, i + 1)
            if e == '"' then out[#out + 1] = '"'; i = i + 2
            elseif e == "\\" then out[#out + 1] = "\\"; i = i + 2
            elseif e == "/" then out[#out + 1] = "/"; i = i + 2
            elseif e == "b" then out[#out + 1] = string.char(8); i = i + 2
            elseif e == "f" then out[#out + 1] = string.char(12); i = i + 2
            elseif e == "n" then out[#out + 1] = string.char(10); i = i + 2
            elseif e == "r" then out[#out + 1] = string.char(13); i = i + 2
            elseif e == "t" then out[#out + 1] = string.char(9); i = i + 2
            elseif e == "u" then
                local cp = tonumber(s:sub(i + 2, i + 5), 16)
                i = i + 6
                if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i, i + 1) == "\\u" then
                    local cp2 = tonumber(s:sub(i + 2, i + 5), 16)
                    if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (cp2 - 0xDC00)
                        i = i + 6
                    end
                end
                out[#out + 1] = utf8.char(cp)
            else
                error("invalid escape sequence in JSON string: \\" .. e)
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out), i
end

local function parse_number(s, i)
    local j = i
    if s:sub(j, j) == "-" then j = j + 1 end
    while s:sub(j, j):match("%d") do j = j + 1 end
    if s:sub(j, j) == "." then
        j = j + 1
        while s:sub(j, j):match("%d") do j = j + 1 end
    end
    if s:sub(j, j) == "e" or s:sub(j, j) == "E" then
        j = j + 1
        if s:sub(j, j) == "+" or s:sub(j, j) == "-" then j = j + 1 end
        while s:sub(j, j):match("%d") do j = j + 1 end
    end
    return tonumber(s:sub(i, j - 1)), j
end

parse_value = function(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == '"' then return parse_string(s, i) end
    if c == "{" then
        i = skip_ws(s, i + 1)
        local t = {}
        if s:sub(i, i) == "}" then return t, i + 1 end
        while true do
            i = skip_ws(s, i)
            if s:sub(i, i) ~= '"' then error("expected string key in JSON object at position " .. i) end
            local key, ni = parse_string(s, i)
            i = skip_ws(s, ni)
            if s:sub(i, i) ~= ":" then error("expected ':' in JSON object at position " .. i) end
            local val, ni2 = parse_value(s, i + 1)
            t[key] = val
            i = skip_ws(s, ni2)
            local cc = s:sub(i, i)
            if cc == "," then i = i + 1
            elseif cc == "}" then i = i + 1; break
            else error("expected ',' or '}' in JSON object at position " .. i) end
        end
        return t, i
    end
    if c == "[" then
        i = skip_ws(s, i + 1)
        local t = {}
        if s:sub(i, i) == "]" then return t, i + 1 end
        local n = 0
        while true do
            local val, ni = parse_value(s, i)
            n = n + 1
            t[n] = val
            i = skip_ws(s, ni)
            local cc = s:sub(i, i)
            if cc == "," then i = i + 1
            elseif cc == "]" then i = i + 1; break
            else error("expected ',' or ']' in JSON array at position " .. i) end
        end
        return t, i
    end
    if s:sub(i, i + 3) == "true" then return true, i + 4 end
    if s:sub(i, i + 4) == "false" then return false, i + 5 end
    if s:sub(i, i + 3) == "null" then return nil, i + 4 end
    local num, ni = parse_number(s, i)
    if num == nil then error("invalid JSON at position " .. i .. ": " .. s:sub(i, i + 10)) end
    return num, ni
end

function M.json_decode(s)
    return (parse_value(s, 1))
end

------------------------------------------------------------------------
-- Top-level save <-> table conversion
------------------------------------------------------------------------

local function is_yellow(buf)
    local starter = get(buf, M.OFS.Starter)
    if starter ~= 0 then return starter == 0x54 end -- 0x54 = internal species ID for Pikachu
    return get(buf, M.OFS.PikaFriendship) ~= 0
end

-- Quick structural sanity check equivalent to SaveUtil's HasListAt/IsListValidG12.
function M.looks_like_gen1_international_save(buf)
    if #buf ~= M.SIZE_SAVE then return false end
    local function has_list_at(ofs, maxCount)
        local count = get(buf, ofs)
        return count <= maxCount and get(buf, ofs + 1 + count) == 0xFF
    end
    return has_list_at(M.OFS.Party, 6) and has_list_at(M.OFS.CurrentBox, M.BOX_SLOT_COUNT)
end

-- Parses a raw 32768-byte Gen 1 save (as a byte array) into a JSON-friendly table.
function M.parse_save(buf)
    if not M.looks_like_gen1_international_save(buf) then
        error("this does not look like an international Gen 1 (Red/Blue/Yellow) save file (expected a 32768-byte file with valid party/box list headers)")
    end

    local currentBoxZero = get(buf, M.OFS.CurrentBoxIndex) & 0x7F
    local boxesInitialized = (get(buf, M.OFS.CurrentBoxIndex) & 0x80) ~= 0

    local playTimeOfs = M.OFS.PlayTime
    local trainer = M.omap({
        { "name", M.decode_string(buf, M.OFS.OT, M.STRING_LENGTH) },
        { "id", read_u16be(buf, M.OFS.TID16) },
        { "rival_name", M.decode_string(buf, M.OFS.Rival, M.STRING_LENGTH) },
        { "money", bcd_read(buf, M.OFS.Money, 3, false) },
        { "coins", bcd_read(buf, M.OFS.Coin, 2, false) },
        { "badges", get(buf, M.OFS.Badges) },
        { "options", get(buf, M.OFS.Options) },
        { "starter", get(buf, M.OFS.Starter) },
        { "pikachu_friendship", get(buf, M.OFS.PikaFriendship) },
        { "pikachu_beach_score", bcd_read(buf, M.OFS.PikaBeachScore, 2, true) },
        { "play_time", M.omap({
            { "hours", get(buf, playTimeOfs) },
            { "minutes", get(buf, playTimeOfs + 2) },
            { "seconds", get(buf, playTimeOfs + 3) },
            { "frames", get(buf, playTimeOfs + 4) },
            { "maxed_out", get(buf, playTimeOfs + 1) ~= 0 },
        }) },
    })

    local boxes = {}
    for boxIndexZero = 0, M.BOX_COUNT - 1 do
        local absBase = (boxIndexZero == currentBoxZero) and M.OFS.CurrentBox or M.box_bank_offset(boxIndexZero)
        boxes[#boxes + 1] = M.omap({
            { "box", boxIndexZero + 1 },
            { "pokemon", parse_mon_list(buf, absBase, M.BOX_SLOT_COUNT, M.SIZE_STORED, false) },
        })
    end

    return M.omap({
        { "format", "gen1" },
        { "region", "international" },
        { "version_guess", is_yellow(buf) and "yellow" or "red_blue" },
        { "trainer", trainer },
        { "current_box", currentBoxZero + 1 },
        { "boxes_initialized", boxesInitialized },
        { "party", parse_mon_list(buf, M.OFS.Party, 6, M.SIZE_PARTY, true) },
        { "boxes", boxes },
        { "raw_base64", M.base64_encode(M.bytes_to_string(buf)) },
    })
end

-- Builds a raw 32768-byte Gen 1 save (as a byte array) from a JSON-decoded table.
-- `data.raw_base64` (as produced by parse_save) is required and used as the base
-- buffer, so that anything not modeled above (items, Pokedex flags, event flags,
-- Hall of Fame, etc.) survives the round trip unmodified.
function M.build_save(data)
    if not data.raw_base64 or data.raw_base64 == "" then
        error("JSON is missing required field 'raw_base64' (the original save's base data)")
    end
    local buf = M.string_to_bytes(M.base64_decode(data.raw_base64))
    if #buf ~= M.SIZE_SAVE then
        error(string.format("decoded raw_base64 is %d bytes, expected %d", #buf, M.SIZE_SAVE))
    end

    local trainer = data.trainer or {}
    M.encode_string(buf, M.OFS.OT, M.STRING_LENGTH, trainer.name)
    write_u16be(buf, M.OFS.TID16, trainer.id or 0)
    M.encode_string(buf, M.OFS.Rival, M.STRING_LENGTH, trainer.rival_name)
    bcd_write(buf, M.OFS.Money, 3, false, trainer.money or 0)
    bcd_write(buf, M.OFS.Coin, 2, false, trainer.coins or 0)
    set(buf, M.OFS.Badges, trainer.badges or 0)
    set(buf, M.OFS.Options, trainer.options or 0)
    set(buf, M.OFS.Starter, trainer.starter or 0)
    set(buf, M.OFS.PikaFriendship, trainer.pikachu_friendship or 0)
    bcd_write(buf, M.OFS.PikaBeachScore, 2, true, trainer.pikachu_beach_score or 0)

    local playTime = trainer.play_time or {}
    set(buf, M.OFS.PlayTime, playTime.hours or 0)
    set(buf, M.OFS.PlayTime + 1, playTime.maxed_out and 1 or 0)
    set(buf, M.OFS.PlayTime + 2, playTime.minutes or 0)
    set(buf, M.OFS.PlayTime + 3, playTime.seconds or 0)
    set(buf, M.OFS.PlayTime + 4, playTime.frames or 0)

    write_mon_list(buf, M.OFS.Party, 6, M.SIZE_PARTY, true, data.party or {})

    local currentBoxZero = (data.current_box or 1) - 1
    if currentBoxZero < 0 or currentBoxZero >= M.BOX_COUNT then
        error("current_box must be between 1 and " .. M.BOX_COUNT)
    end

    local boxes = data.boxes or {}
    for boxIndexZero = 0, M.BOX_COUNT - 1 do
        local boxEntry = boxes[boxIndexZero + 1]
        local pokemon = boxEntry and boxEntry.pokemon or {}
        local absBase = M.box_bank_offset(boxIndexZero)
        write_mon_list(buf, absBase, M.BOX_SLOT_COUNT, M.SIZE_STORED, false, pokemon)
    end

    -- Mirror the current box's freshly-written bytes into the "live" buffer
    -- (SAV1.cs GetFinalData()), and mark boxes as initialized.
    local curBankOfs = M.box_bank_offset(currentBoxZero)
    for i = 0, M.SIZE_BOX_LIST - 1 do
        set(buf, M.OFS.CurrentBox + i, get(buf, curBankOfs + i))
    end
    set(buf, M.OFS.CurrentBoxIndex, (currentBoxZero & 0x7F) | 0x80)

    set(buf, M.OFS.ChecksumOfs, compute_checksum(buf))

    return M.bytes_to_string(buf, M.SIZE_SAVE)
end

return M
