local LuaWriter = require("src.import.LuaWriter")
local Rom = require("src.import.Rom")
local ImageWriter = require("src.import.ImageWriter")
local Logger = require("src.core.Logger")
local Gen2ScriptOps = require("src.import.Gen2ScriptOps")

local RomExtractorGen2 = {}
RomExtractorGen2.__index = RomExtractorGen2

local STAGE_COUNT = 16

local INTRO_TEXT_FALLBACKS = {
  _OakSpeechText1 = "Hello there!\nWelcome to the\vworld of POKeMON!\fMy name is OAK!\nPeople call me\vthe POKeMON PROF!",
  _OakSpeechText2A = "This world is\ninhabited by\vcreatures called\vPOKeMON!",
  _OakSpeechText2B = "\fFor some people,\nPOKeMON are\vpets. Others use\vthem for fights.\fMyself...\fI study POKeMON\nas a profession.",
  _OakSpeechText3 = "{PLAYER}!\fYour very own\nPOKeMON legend is\vabout to unfold!\fA world of dreams\nand adventures\vwith POKeMON\vawaits! Let's go!",
  _IntroducePlayerText = "First, what is\nyour name?",
  _IntroduceRivalText = "This is my grand-\nson. He's been\vyour rival since\vyou were a baby.\f...Erm, what is\nhis name again?",
  _YourNameIsText = "Right! So your\nname is {PLAYER}!",
  _HisNameIsText = "That's right! I\nremember now! His\vname is {RIVAL}!",
}

local STUB_TEXT_FALLBACKS = {
  TEXT_PLAYERS_HOUSE2_F_OBJ_001 = "A game console is connected.\nTime to begin your journey.",
  TEXT_PLAYERS_HOUSE2_F_OBJ_002 = "It's your PC.\nBetter get going downstairs.",
  TEXT_PLAYERS_HOUSE2_F_OBJ_003 = "A tidy bookshelf full of notes.",
  TEXT_PLAYERS_HOUSE2_F_OBJ_004 = "A radio is playing a cheerful tune.",
  TEXT_PLAYERS_HOUSE2_F_BG_001 = "A memo reminds you to visit ELM.",
  TEXT_PLAYERS_HOUSE2_F_BG_002 = "A note says: pack your BAG first.",
  TEXT_PLAYERS_HOUSE2_F_BG_003 = "It is neatly organized.",
  TEXT_PLAYERS_HOUSE2_F_BG_004 = "A small decoration sits here.",
}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
  return out
end

local function gen2TilesetRows(symbols)
  local rows = {}
  for name, location in pairs(symbols or {}) do
    if type(name) == "string" and name:match("^Tileset.+Meta$")
        and type(location) == "table" then
      local family = name:sub(#"Tileset" + 1, -#"Meta" - 1)
      if family ~= "" and not family:match("^Unused") then
        rows[#rows + 1] = { tonumber(location[1]), tonumber(location[2]), family }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a[1] == b[1] then return a[2] < b[2] end
    return a[1] < b[1]
  end)
  return rows
end

-- Gen2 world-structure layout, verified against the pokegold ROM.
local GEN2_MAP_GROUP_COUNT = 26
local GEN2_MAP_HEADER_BYTES = 9      -- attrBank, tileset, environment, attrPtr, location, music, flags, fishGroup
local GEN2_CONNECTION_BYTES = 12
local GEN2_TILESET_ENTRY_BYTES = 15
-- map_attributes: border, height, width, dba blocks, dba scripts, dw events, connection flags
local GEN2_ATTR_CONNECTION_FLAGS = 11
local GEN2_ATTR_EVENTS_BANK = 6
local GEN2_ATTR_EVENTS_POINTER = 9
local GEN2_WARP_EVENT_BYTES = 5
local GEN2_COORD_EVENT_BYTES = 8
local GEN2_BG_EVENT_BYTES = 5
local GEN2_BG_EVENT_ITEM = 7    -- hidden item: the trailing bytes are not a pointer
local GEN2_OBJECT_EVENT_BYTES = 13
local GEN2_EVENT_COORD_BIAS = 4
-- object_event byte 7 packs a palette override in the high nybble and the
-- object's kind in the low one; an ITEMBALL's "script" is really `db item, qty`
local GEN2_OBJECT_KIND_MASK = 0x0F
local GEN2_OBJECT_KIND_ITEMBALL = 1
local GEN2_OBJECT_KIND_TRAINER = 2
local GEN2_EVENT_FLAG_NONE = 0xFFFF
local GEN2_TIME_OF_DAY_ANY = 0xFF
-- ItemAttributes row: dw price, then effect/param/property/pocket/menu bytes
local GEN2_ITEM_ATTR_BYTES = 7

-- TMHMMoves (4:$5A66) is a flat `db` list of 50 TM moves followed by 7 HM
-- moves (data/moves/tmhm_moves.asm); GetTMHMMove indexes it to turn a TM/HM
-- item into the move it teaches.  Which species may learn machine number n
-- lives in the 8-byte bitfield closing every 32-byte BaseData row (bit
-- (n-1)%8 of byte (n-1)/8), which is what CanLearnTMHMMove tests.
local GEN2_TM_COUNT, GEN2_HM_COUNT = 50, 7
local GEN2_BASE_TMHM_FIRST = 25  -- 1-based index of the first flag byte
-- item_data_constants.asm pockets are `const_def 1`: ITEM 1, KEY_ITEM 2,
-- BALL 3, TM_HM 4.  Reading KEY_ITEM as 1 flagged all 162 ordinary items
-- untossable.
local GEN2_POCKET_KEY_ITEM = 2

-- The engine's item behaviour tables are keyed by Gen1's name-derived ids
-- (POTION, POKE_BALL, TM_01); Gen2 items are ITEM_nnn, so carry the same
-- key alongside so ItemEffects can resolve one to the other.
local function gen2ItemKey(name)
  if type(name) ~= "string" then return nil end
  local key = name:gsub("\195\169", "e"):upper()
  key = key:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  key = key:gsub("^(TM)(%d+)$", "%1_%2"):gsub("^(HM)(%d+)$", "%1_%2")
  return key ~= "" and key or nil
end

-- writetext $4C, jumptextfaceplayer $51 and jumptext $52 all take a 2 byte
-- text pointer; farwritetext $4B takes `dw address, db bank`.  $52 was listed
-- as the far form, so every signpost read its own pointer as an address in
-- whatever bank byte followed and printed a fragment of an unrelated line.
local GEN2_SCRIPT_TEXT_OPS = { [0x4C] = true, [0x51] = true, [0x52] = true }
local GEN2_SCRIPT_OP_FAR_TEXT = 0x4B   -- dw address, db bank
local GEN2_SCRIPT_OP_JUMPSTD = 0x0C    -- db index into StdScripts
local GEN2_SCRIPT_OP_SPECIAL = 0x0F    -- dw SpecialsPointers index
local GEN2_SCRIPT_OP_FRUITTREE = 0x9A  -- db tree id, indexes FruitTreeItems
local GEN2_SCRIPT_OP_SETEVENT = 0x33   -- dw event number
local GEN2_SCRIPT_OP_POKEMART = 0x93   -- db dialog type, dw index into Marts

-- SpecialsPointers indices the Kanto post-game chain and related Johto
-- specials rely on.  Detecting these in an object script lets the extractor
-- mark the NPC so runtime / debugging can see Move Deleter, Magnet Train,
-- Bill's grandfather, the radio lottery, and Snorlax without reading bytecode.
-- Indices match pret/pokegold data/events/special_pointers.asm (Gold/Silver).
local GEN2_KANTO_SPECIAL_MARKERS = {
  [0x21] = "move_deleter",       -- MoveDeletion
  [0x23] = "magnet_train",       -- MagnetTrain
  [0x4C] = "bills_grandfather",  -- BillsGrandfather (Route 25 stone gifts)
  [0x51] = "lucky_number",       -- CheckForLuckyNumberWinners
  [0x52] = "lucky_number",       -- CheckLuckyNumberShowFlag
  [0x53] = "lucky_number",       -- ResetLuckyNumberShowFlag
  [0x54] = "lucky_number",       -- PrintTodaysLuckyNumber
  [0x55] = "select_apricorn",    -- SelectApricornForKurt (already handled via special)
  [0x56] = "name_rater",         -- NameRater
  [0x5F] = "snorlax_awake",      -- SnorlaxAwake (Route 12 / 16)
}
local GEN2_STD_POKECENTER_NURSE = 0x00 -- StdScripts[0] = PokecenterNurseScript
local GEN2_MART_TYPE_MAX = 3           -- MARTTYPE_STANDARD..MARTTYPE_PHARMACY
local GEN2_SCRIPT_SCAN_BYTES = 32
local GEN2_FRUIT_TREE_COUNT = 30
local GEN2_CONNECTION_DIRS = {
  { "north", 0x08 }, { "south", 0x04 }, { "west", 0x02 }, { "east", 0x01 },
}

local function signedByte(value)
  return value >= 128 and value - 256 or value
end

local GEN2_OVERWORLD_SPRITE_BYTES = 6
local GEN2_SPRITE_WALK_BYTES = 384      -- 24 tiles: 6 frames of 16x16
local GEN2_SPRITE_KIND_BYTES = {
  [1] = 384,   -- walking
  [2] = 192,   -- standing (3 frames)
  [3] = 64,    -- still: items, boulders, trees
}

-- EvosAttacks evolution records are variable width; the method byte picks it
local GEN2_EVO_LENGTHS = { [1] = 3, [2] = 3, [3] = 3, [4] = 3, [5] = 4 }
local GEN2_EVOLVE_LEVEL, GEN2_EVOLVE_ITEM, GEN2_EVOLVE_TRADE = 1, 2, 3
local GEN2_EVOLVE_HAPPINESS, GEN2_EVOLVE_STAT = 4, 5
local GEN2_EVO_TIMES = { [2] = "MORNDAY", [3] = "NITE" }  -- 1 = TR_ANYTIME
local GEN2_EVO_STATS = { [1] = "ATK_LT_DEF", [2] = "ATK_GT_DEF", [3] = "ATK_EQ_DEF" }
local GEN2_GROWTH_RATES = {
  [0] = "MEDIUM_FAST", [1] = "SLIGHTLY_FAST", [2] = "SLIGHTLY_SLOW",
  [3] = "MEDIUM_SLOW", [4] = "FAST", [5] = "SLOW",
}
local GEN2_BASE_PIC_DIMS = 18       -- 1-based: dn frontpic width, height
local GEN2_BASE_GROWTH_RATE = 23
local GEN2_COLL_TALL_GRASS = 0x14
-- CheckCounterTile (00:173D): only $90 and $98 are talked across
local GEN2_COUNTER_CLASSES = { 0x90, 0x98 }

-- The Johto player is "Chris" in the ROM but SPRITE_RED throughout this
-- codebase, and the Kanto Red row would collide with it.
--
-- Additional explicit ids pin the critical Kanto post-game / story NPCs so
-- they never fall back to SPRITE_GRAMPS (or a still-tree sheet) if a
-- *SpriteGFX symbol is missing or renamed.  Indices match pret/pokegold
-- constants/sprite_constants.asm.  Gen2Recomped assets use SPRITE_SILVER
-- for the rival (pret renamed the constant SPRITE_RIVAL; same index $04).
local GEN2_SPRITE_ID_OVERRIDES = {
  -- Player / rival / legendaries-as-NPCs
  [0x01] = "SPRITE_RED",
  [0x02] = "SPRITE_RED_BIKE",
  [0x04] = "SPRITE_SILVER",        -- RivalSpriteGFX; engine expects SILVER
  [0x06] = "SPRITE_RED_KANTO",     -- Kanto Red (Mt. Silver)
  [0x07] = "SPRITE_BLUE",          -- Viridian Gym post-game
  [0x08] = "SPRITE_BILL",
  -- Kanto gym leaders (post-game re-matches + Misty date/gym)
  [0x0A] = "SPRITE_JANINE",
  [0x0D] = "SPRITE_BLAINE",
  [0x1A] = "SPRITE_BROCK",
  [0x1D] = "SPRITE_MISTY",         -- Cerulean Gym + Route 25 date
  [0x53] = "SPRITE_SURF",          -- player surfing sheet (not POKE_BALL $54)
  [0x1F] = "SPRITE_SURGE",
  [0x20] = "SPRITE_ERIKA",
  [0x21] = "SPRITE_KOGA",
  [0x22] = "SPRITE_SABRINA",
  -- Common Kanto story NPCs
  [0x23] = "SPRITE_COOLTRAINER_M", -- Misty's date on Route 25
  [0x24] = "SPRITE_COOLTRAINER_F",
  [0x2B] = "SPRITE_SUPER_NERD",    -- Power Plant / Machine Part
  [0x2F] = "SPRITE_GRAMPS",        -- Bill's grandfather (Route 25)
  [0x31] = "SPRITE_SWIMMER_GUY",
  [0x32] = "SPRITE_SWIMMER_GIRL",
  [0x33] = "SPRITE_BIG_SNORLAX",   -- Route 12 / 16
  [0x35] = "SPRITE_ROCKET",        -- Cerulean Gym grunt + residual Rockets
  [0x36] = "SPRITE_ROCKET_GIRL",
  [0x48] = "SPRITE_GYM_GUIDE",
  -- Still / scenery (must NOT be reused for walking NPCs)
  [0x54] = "SPRITE_POKE_BALL",
  [0x59] = "SPRITE_ROCK",
  [0x5A] = "SPRITE_BOULDER",
  [0x5D] = "SPRITE_FRUIT_TREE",
  -- Mon / special sheets
  [0x9F] = "SPRITE_SNORLAX",
  -- Variable-sprite constants used as direct ids on some maps
  [0xF4] = "SPRITE_WEIRD_TREE",    -- Sudowoodo pre-reveal
  [0xF5] = "SPRITE_SILVER",        -- SPRITE_OLIVINE_RIVAL slot
  [0xF6] = "SPRITE_ROCKET",        -- SPRITE_AZALEA_ROCKET slot
  [0xFB] = "SPRITE_COPYCAT",
  [0xFC] = "SPRITE_JANINE",        -- Janine impersonator
}

-- GetMonSprite (05:$42CB) splits an object_event sprite byte four ways: below
-- $80 it is an OverworldSprites row, $80..$DF it is SPRITE_POKEMON plus an
-- index into SpriteMons and the object walks around as that species' party
-- menu icon, $E0/$E1 are the two day-care mons, and $F0 and up index
-- wVariableSprites.  Everything from $80 up used to miss the sprite table and
-- fall back to SPRITE_GRAMPS, so the Lake of Rage Gyarados, the Burned Tower
-- beasts, Ho-Oh and Lugia all stood there as an old man.
local GEN2_SPRITE_POKEMON = 0x80
local GEN2_SPRITE_BREED_1 = 0xE0
local GEN2_SPRITE_BREED_2 = 0xE1
local GEN2_SPRITE_VARS = 0xF0
local GEN2_SPRITE_MONS_COUNT = 35

local function gen2MonSpriteId(species)
  return string.format("SPRITE_MON_%03d", species)
end

-- "CooltrainerM" -> "SPRITE_COOLTRAINER_M"
-- pret renamed SilverSpriteGFX -> RivalSpriteGFX; Gen2Recomped assets and
-- object rows still key off SPRITE_SILVER, so force that alias here.
local function gen2SpriteConstant(base)
  if type(base) == "string" then
    local lower = base:lower()
    if lower == "rival" or lower == "silver" then
      return "SPRITE_SILVER"
    end
    if lower == "chris" then
      return "SPRITE_RED"
    end
    if lower == "chrisbike" or lower == "chris_bike" then
      return "SPRITE_RED_BIKE"
    end
  end
  local parts = {}
  for word in base:gmatch("%u%l*%d*") do parts[#parts + 1] = word:upper() end
  if #parts == 0 then parts[1] = tostring(base):upper() end
  return "SPRITE_" .. table.concat(parts, "_")
end

-- Standard Gen2 text encoding (pokegold charmap.asm).  The scaffold charmap
-- table is a placeholder that spells every code back as "{BYTE:xx}", so this
-- is what actually renders ROM dialogue and name tables.
local GEN2_CHARMAP = {}
do
  for i = 0, 25 do
    GEN2_CHARMAP[0x80 + i] = string.char(65 + i)  -- A-Z
    GEN2_CHARMAP[0xA0 + i] = string.char(97 + i)  -- a-z
  end
  for i = 0, 9 do GEN2_CHARMAP[0xF6 + i] = tostring(i) end
  local specials = {
    [0x00] = "",             -- the `text` opener
    [0x4A] = "<PKMN>",  [0x52] = "<PLAYER>", [0x53] = "<RIVAL>",
    [0x54] = "POK\xc3\xa9",  -- combined POKé glyph
    [0x56] = "\xe2\x80\xa6\xe2\x80\xa6", [0x59] = "<TARGET>",
    [0x5A] = "<USER>",  [0x5B] = "<PC>",     [0x5C] = "TM",
    [0x5D] = "<TRAINER>", [0x5E] = "ROCKET",
    [0x75] = "\xe2\x80\xa6",  -- ellipsis
    [0x7F] = " ",
    [0x9A] = "(", [0x9B] = ")", [0x9C] = ":", [0x9D] = ";",
    [0x9E] = "[", [0x9F] = "]",
    [0xD0] = "'d", [0xD1] = "'l", [0xD2] = "'m", [0xD3] = "'r",
    [0xD4] = "'s", [0xD5] = "'t", [0xD6] = "'v",
    [0xE0] = "'", [0xE1] = "PK", [0xE2] = "MN", [0xE3] = "-",
    [0xE6] = "?", [0xE7] = "!", [0xE8] = ".", [0xE9] = "&",
    [0xEA] = "\xc3\xa9", [0xEF] = "\xe2\x99\x82",
    [0xF0] = "\xc2\xa5", [0xF1] = "x", [0xF2] = ".", [0xF3] = "/",
    [0xF4] = ",", [0xF5] = "\xe2\x99\x80",
  }
  for code, glyph in pairs(specials) do GEN2_CHARMAP[code] = glyph end
end


local function gen2DecodeString(bytes, maxLen)
  local out = {}
  for i = 1, math.min(#bytes, maxLen or 14) do
    local b = bytes[i]
    if b == 0x50 then break end
    local c = GEN2_CHARMAP[b]
    if c then out[#out + 1] = c end
  end
  local s = table.concat(out)
  if s:match("^%s*$") then return nil end
  return s
end

local function gen2ReadVarNames(rom, sym, count)
  if not (rom and sym) then return {} end
  local names = {}; local bank = sym.bank; local addr = sym.address
  for i = 1, count do
    local ok, chunk = pcall(function() return rom:bytes(bank, addr, 16) end)
    if not ok or type(chunk) ~= "table" then break end
    local endIdx = 1
    while endIdx <= #chunk and chunk[endIdx] ~= 0x50 do endIdx = endIdx + 1 end
    endIdx = endIdx - 1
    local raw = {}; for j = 1, endIdx do raw[j] = chunk[j] end
    local name = gen2DecodeString(raw, endIdx)
    if name then names[i] = name end
    addr = addr + endIdx + 1
    if addr >= 0x8000 then bank = bank + 1; addr = addr - 0x4000 end
  end
  return names
end

local function gen2ReadFixedNames(rom, sym, count, entrySize)
  entrySize = entrySize or 10
  if not (rom and sym) then return {} end
  local names = {}
  for i = 1, count do
    local ok, raw = pcall(function()
      return rom:bytes(sym.bank, sym.address + (i - 1) * entrySize, entrySize)
    end)
    if ok and type(raw) == "table" then
      local name = gen2DecodeString(raw, entrySize)
      if name then names[i] = name end
    end
  end
  return names
end
local GEN2_BG_PALETTE_BANK = 2
local GEN2_BG_PALETTE_ADDR = 0x775e
local GEN2_PALETTE_OUTDOOR = { "JOHTO", "KANTO", "JOHTOMODERN", "PLATEAU", "PARK" }
local GEN2_PALETTE_CAVE    = { "CAVERN", "RUIN", "DUNGEON", "WHIRLPOOL", "ICEROOM", "FACILITY" }

local function gen2PaletteSetIndex(tilesetId)
  local family = (tilesetId:match("^Tileset(.+)$") or tilesetId):upper()
  for _, f in ipairs(GEN2_PALETTE_CAVE) do if f == family then return 2 end end
  return 0
end

function RomExtractorGen2.new(romData, version, manifest, progress)
  return setmetatable({
    rom = type(romData) == "string" and Rom.new(romData) or nil,
    version = version,
    manifest = manifest,
    symbols = manifest.symbols or {},
    progress = progress,
    stage = 0,
    sourceDir = "data/generated_gen2_" .. version,
  }, RomExtractorGen2)
end

function RomExtractorGen2:symbol(name)
  local location = self.symbols[name]
  if type(location) ~= "table" then return nil end
  local bank, address = tonumber(location[1]), tonumber(location[2])
  if not (bank and address) then return nil end
  return { bank = bank, address = address, name = name }
end

-- `callasm`/`memcallasm` name a routine, not a script: the runtime can only
-- act on the handful it knows (HasRockSmash, TryStrengthOW, ...), and a raw
-- "03:4F7F" is version-specific.  Resolve the pair back to its pret label so
-- the lowered IR carries a name Gen2ScriptVM can match on.
function RomExtractorGen2:gen2AsmName(bank, address)
  if not self._asmNames then
    local names = {}
    for name, location in pairs(self.symbols or {}) do
      if type(location) == "table" then
        local b, a = tonumber(location[1]), tonumber(location[2])
        -- prefer the top-level label over its `.local` children
        if b and a and not (names[b * 65536 + a] or name:find(".", 1, true)) then
          names[b * 65536 + a] = name
        end
      end
    end
    self._asmNames = names
  end
  return self._asmNames[bank * 65536 + address]
end

function RomExtractorGen2:beginStage(name)
  self.stage = self.stage + 1
  if self.progress then self.progress(self.stage - 1, STAGE_COUNT, name, 0, 1) end
end

function RomExtractorGen2:tick(name, current, total)
  if self.progress then
    self.progress(self.stage - 1 + current / total, STAGE_COUNT,
      name, current, total)
  end
end

function RomExtractorGen2:write(name, value)
  LuaWriter.write("data/generated/" .. name .. ".lua", value)
end

function RomExtractorGen2:saveImage(image, relative)
  ImageWriter.save(image, "assets/generated/" .. relative)
end

-- constants is mutated in place by extractMoves (moveOrder switches from the
-- The badge set, in TRAINER CARD order.  `bit` is the wJohtoBadges /
-- wKantoBadges bit the ROM stores it in, which is NOT the display order:
-- FlyFunction checks engine flag 31 for STORMBADGE and StrengthFunction 28
-- for PLAINBADGE, so Mineral sits on bit 4 and Storm on bit 5 while the card
-- draws Storm first (TrainerCard_JohtoBadgesOAM's x columns).  The bit also
-- picks the badge's 2x2 tile group out of BadgeGFX / BadgeGFX2.
local GEN2_BADGES = {
  { id = "ZEPHYRBADGE",  bit = 0 }, { id = "HIVEBADGE",     bit = 1 },
  { id = "PLAINBADGE",   bit = 2 }, { id = "FOGBADGE",      bit = 3 },
  { id = "STORMBADGE",   bit = 5 }, { id = "MINERALBADGE",  bit = 4 },
  { id = "GLACIERBADGE", bit = 6 }, { id = "RISINGBADGE",   bit = 7 },
  { id = "BOULDERBADGE", bit = 0, kanto = true },
  { id = "CASCADEBADGE", bit = 1, kanto = true },
  { id = "THUNDERBADGE", bit = 2, kanto = true },
  { id = "RAINBOWBADGE", bit = 3, kanto = true },
  { id = "SOULBADGE",    bit = 4, kanto = true },
  { id = "MARSHBADGE",   bit = 5, kanto = true },
  { id = "VOLCANOBADGE", bit = 6, kanto = true },
  { id = "EARTHBADGE",   bit = 7, kanto = true },
}

-- scaffold's MOVE_nnn placeholders to real ids), so every stage has to share
-- one table rather than re-reading the scaffold copy.
function RomExtractorGen2:constants()
  if not self._constants then
    self._constants = self:readSourceTable("constants")
    local badges = {}
    for i, entry in ipairs(GEN2_BADGES) do
      badges[i] = { id = entry.id, bit = entry.bit, kanto = entry.kanto }
    end
    self._constants.badges = badges
    -- The badge each field move is gated on, read off the `ld de, <engine
    -- flag>` ahead of each CheckEngineFlag call: FlashFunction 03:$48F1 $1A,
    -- TryCutOW 03:$519B $1B, TryStrengthOW 03:$4D84 $1C, TrySurfOW $1D,
    -- FlyFunction.TryFly 03:$4A71 $1F, TryWhirlpoolOW 03:$4E4A $20 and
    -- TryWaterfallOW 03:$4B68 $21.  Engine flags $1A-$21 are the Johto
    -- badges in wJohtoBadges bit order (Gen2ScriptVM's ENGINE_FLAG_NAMES).
    -- Without this the Gen1 table gated Gen2 Surf on the SOULBADGE, which
    -- Johto never awards, so no field move was ever usable.
    self._constants.hmBadges = {
      FLASH = { badge = "ZEPHYRBADGE" },
      CUT = { badge = "HIVEBADGE" },
      STRENGTH = { badge = "PLAINBADGE" },
      SURF = { badge = "FOGBADGE" },
      FLY = { badge = "STORMBADGE" },
      WHIRLPOOL = { badge = "GLACIERBADGE" },
      WATERFALL = { badge = "RISINGBADGE" },
    }
    -- ROCK_SMASH is deliberately absent: it is TM08, not an HM, and both
    -- HasRockSmash and TryRockSmashFromMenu check only CheckPartyMove.
    self._constants.regionalOrder = self:gen2RegionalDexOrder()
  end
  -- constants() is reached before the ROM is open on some paths (the
  -- scaffold read), so the dex listing is retried until it lands.
  if not (self._constants.regionalOrder or self._regionalDexTried) then
    self._constants.regionalOrder = self:gen2RegionalDexOrder()
    self._regionalDexTried = self.rom ~= nil
  end
  return self._constants
end

-- The Johto dex listing.  Pokedex_OrderMonsByMode reads wCurrentDexMode and
-- jumps: mode 0 (.NewMode, the one a new game starts in) copies 251 bytes
-- from NewPokedexOrder into wPokedexOrder, and mode 1 (.OldMode) just counts
-- 1..251 -- so the NATIONAL numbering the port was showing is Generation 2's
-- *second* mode, the one you switch to, not the dex you are handed.  #001 is
-- CHIKORITA, and BULBASAUR does not appear until #226.
function RomExtractorGen2:gen2RegionalDexOrder()
  local sym = self:symbol("NewPokedexOrder")
  if not (sym and self.rom) then return nil end
  local species = self._constants.speciesOrder or {}
  if #species == 0 then return nil end
  local out
  pcall(function()
    local raw = self.rom:bytes(sym.bank, sym.address, #species)
    local list = {}
    for i = 1, #raw do
      local id = species[raw[i]]
      if not id then return end
      list[i] = id
    end
    out = list
  end)
  return out
end

function RomExtractorGen2:readSourceTable(name)
  -- Priority: Python setup output (version-subdir) → scaffold → shared generated (last resort)
  local candidates = {
    self.version .. "/data/generated/" .. name .. ".lua",
    self.sourceDir .. "/" .. name .. ".lua",
    "data/generated/" .. name .. ".lua",
  }
  for _, path in ipairs(candidates) do
    local chunk = love.filesystem.load(path)
    if chunk then
      local ok, value = pcall(chunk)
      if ok and type(value) == "table" then return value end
    end
  end
  -- Committed, not built locally, so a missing one means a broken checkout.
  error(("could not load source table: %s\n"
         .. "%s/ ships with the repo -- restore it from git, or rebuild with:\n"
         .. "  python tools/build_rom_data.py --version %s --rom \"<%s rom>.gbc\""
         .. " --out %s --only constants --only charmap --only moves"
         .. " --only items --only text --only maps")
        :format(name, self.sourceDir, self.version, self.version, self.sourceDir))
end

function RomExtractorGen2:copyAsset(src, dst)
  local data, readError = love.filesystem.read(src)
  if not data then error("could not read " .. src .. ": " .. tostring(readError)) end
  self:writeAsset(dst, data)
end

function RomExtractorGen2:writeAsset(dst, data)
  local CacheFs = require("src.import.CacheFs")
  local ok, writeError = CacheFs.write(dst, data)
  if not ok then error("could not write " .. dst .. ": " .. tostring(writeError)) end
end

function RomExtractorGen2:textGlyph(charmap, value)
  local glyph = charmap and charmap[tostring(value)] or nil
  -- the scaffold charmap spells unknown codes back as their own "{BYTE:xx}"
  -- placeholder; fall back to the real Gen2 encoding for those
  if type(glyph) ~= "string" or glyph:match("^{BYTE:") then
    glyph = GEN2_CHARMAP[value]
  end
  if type(glyph) ~= "string" then
    return ("{BYTE:%02X}"):format(value)
  end
  if glyph:sub(1, 1) == "<" and glyph:sub(-1) == ">" then
    return "{" .. glyph:sub(2, -2) .. "}"
  end
  return glyph
end

local function titleizeWords(key)
  local text = tostring(key or "")
    :gsub("^TEXT_", "")
    :gsub("[_%.]", " ")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
    :lower()
  if text == "" then return "..." end
  text = text:gsub("(%a)([%w']*)", function(a, b)
    return a:upper() .. b
  end)
  return text .. "."
end

local function inferTilesetId(mapId, label)
  local name = tostring(mapId or label or ""):upper()
  local function has(token)
    return name:find(token, 1, true) ~= nil
  end

  if has("PLAYERSHOUSE2F") or has("PLAYERS_HOUSE2_F") or has("PLAYERS_HOUSE2F") then
    return "TilesetPlayersRoom"
  end
  if has("PLAYERS_HOUSE") or has("ELMS_LAB") or has("OAKS_LAB") or has("LAB") then
    return has("LAB") and "TilesetLab" or "TilesetPlayersHouse"
  end

  if has("POKECENTER") then return "TilesetPokecenter" end
  if has("MART") then return "TilesetMart" end
  if has("GATE") then return "TilesetGate" end
  if has("HOUSE") then return "TilesetHouse" end
  if has("MANSION") then return "TilesetMansion" end
  if has("CAFE") then return "TilesetHouse" end
  if has("TRAIN_STATION") or has("MAGNET_TRAIN") then return "TilesetTrainStation" end
  if has("UNDERGROUND") then return "TilesetUnderground" end
  if has("GAME_CORNER") then return "TilesetGameCorner" end
  if has("RADIO_TOWER") then return "TilesetRadioTower" end
  if has("RUINS_OF_ALPH") then return "TilesetRuinsOfAlph" end
  if has("ICE_PATH") then return "TilesetIcePath" end
  if has("FACILITY") then return "TilesetFacility" end
  if has("PARK") then return "TilesetPark" end
  if has("FOREST") then return "TilesetForest" end
  if has("PORT") then return "TilesetPort" end
  if has("CHAMPIONS_ROOM") then return "TilesetChampionsRoom" end
  if has("ELITE_FOUR_ROOM") then return "TilesetChampionsRoom" end
  if has("TOWER") then return "TilesetTower" end
  if has("LIGHTHOUSE") then return "TilesetLighthouse" end
  if has("CAVE") then return "TilesetCave" end

  if has("PALLET") or has("VIRIDIAN") or has("PEWTER") or has("CERULEAN")
      or has("VERMILION") or has("LAVENDER") or has("FUCHSIA")
      or has("SAFFRON") or has("CELADON") or has("CINNABAR")
      or has("INDIGO") or has("ROUTE") or has("BILLS") or has("POWER_PLANT") then
    return "TilesetKanto"
  end

  return "TilesetJohto"
end


local function lz3Flip(byte)
  local value = 0
  for bit = 0, 7 do
    if math.floor(byte / (2 ^ bit)) % 2 ~= 0 then
      value = value + 2 ^ (7 - bit)
    end
  end
  return value
end


local function decompressLz3(raw)
  local out = {}
  local index = 1
  while index <= #raw do
    local byte = raw[index]
    if not byte or byte == 0xFF then break end

    local cmd, length
    if math.floor(byte / 32) == 7 then
      -- long form: command in bits 4-2, 10-bit length across this byte and the next
      local nextByte = raw[index + 1]
      if not nextByte then break end
      cmd = math.floor(byte / 4) % 8
      length = (byte % 4) * 256 + nextByte + 1
      index = index + 2
    else
      cmd = math.floor(byte / 32)
      length = byte % 32 + 1
      index = index + 1
    end

    if cmd == 0 then
      for i = 0, length - 1 do out[#out + 1] = raw[index + i] or 0 end
      index = index + length
    elseif cmd == 1 then
      local v = raw[index]; if not v then break end
      index = index + 1
      for _ = 1, length do out[#out + 1] = v end
    elseif cmd == 2 then
      local a, b = raw[index], raw[index + 1]
      if not a or not b then break end
      index = index + 2
      for i = 0, length - 1 do out[#out + 1] = (i % 2 == 0) and a or b end
    elseif cmd == 3 then
      for _ = 1, length do out[#out + 1] = 0 end
    elseif cmd == 4 or cmd == 5 or cmd == 6 then
      -- offset: high bit set = 7-bit offset back from the end, else 2-byte big-endian absolute
      local hi = raw[index]; if not hi then break end
      local offset
      if hi >= 0x80 then
        offset = #out - (hi % 128) - 1
        index = index + 1
      else
        local lo = raw[index + 1]; if not lo then break end
        offset = hi * 256 + lo
        index = index + 2
      end
      for i = 0, length - 1 do
        local src = (cmd == 6) and (offset - i) or (offset + i)
        local v = (src >= 0 and src < #out) and out[src + 1] or 0
        out[#out + 1] = (cmd == 5) and lz3Flip(v) or v
      end
    else
      break
    end
  end
  return out
end


-- One tile as 64 palette indices, row major (the 2bpp planes are
-- interleaved low/high per row).
local function gen2TilePixels(raw, offset)
  local pixels = {}
  for y = 0, 7 do
    local low = raw[offset + y * 2 + 1] or 0
    local high = raw[offset + y * 2 + 2] or 0
    for x = 0, 7 do
      local divisor = 2 ^ (7 - x)
      pixels[y * 8 + x + 1] =
        math.floor(high / divisor) % 2 * 2 + math.floor(low / divisor) % 2
    end
  end
  return pixels
end

-- 0-indexed tile table, so a VRAM tile id indexes it directly
local function gen2SplitTiles(raw)
  local tiles = {}
  for index = 0, math.floor(#raw / 16) - 1 do
    tiles[index] = gen2TilePixels(raw, index * 16)
  end
  return tiles
end

local function gen2DrawTile(image, tile, px, py, pal)
  if not tile then return end
  for y = 0, 7 do
    for x = 0, 7 do
      local color = pal[tile[y * 8 + x + 1] + 1]
      image:setPixel(px + x, py + y, color[1], color[2], color[3], 1)
    end
  end
end

-- The intro scenes have no CGB palette table of their own (each
-- Intro_Load*Palette poke is a mon palette); these are the shades the
-- water and grass scenes read as on hardware.
local GEN2_INTRO_WATER_PAL = {
  { 1, 1, 1 }, { 0.53, 0.71, 1 }, { 0.16, 0.31, 0.78 }, { 0, 0, 0 },
}
local GEN2_INTRO_GRASS_PAL = {
  { 1, 1, 1 }, { 0.63, 0.90, 0.47 }, { 0.20, 0.55, 0.24 }, { 0, 0, 0 },
}


local function inferTilesetDimensions(byteCount)
  for _, width in ipairs({ 128, 64, 32, 16 }) do
    local tilesWide = width / 8
    if byteCount % (tilesWide * 16) == 0 then
      local height = byteCount * 4 / width
      if height > 0 and height % 8 == 0 then
        return width, height
      end
    end
  end
  -- Round up to the nearest tile boundary (multiples of 8 pixels)
  local rawH = byteCount * 4 / 128
  return 128, math.max(8, math.ceil(rawH / 8) * 8)
end

local function fallbackForStub(mapId, key)
  local direct = STUB_TEXT_FALLBACKS[key]
  if direct then return direct end
  if key and key:find("_OBJ_", 1, true) then
    return "You examine the object.\n" .. titleizeWords(mapId)
  end
  if key and key:find("_BG_", 1, true) then
    return "You read the sign.\n" .. titleizeWords(mapId)
  end
  return titleizeWords(key or mapId)
end

-- $50 closes a literal run, not the whole text: these commands splice a live
-- WRAM value in and the stream carries on afterwards.  A $50 followed by
-- anything else really is the end (the next text body starts with $00).
RomExtractorGen2.GEN2_TEXT_SPLICE = {
  [0x01] = 2,  -- text_ram   dw
  [0x02] = 3,  -- text_bcd   dw, db
  [0x03] = 2,  -- text_move  dw
  [0x09] = 3,  -- text_decimal dw, db
}

-- WRAM address -> symbol, for naming the buffers text_ram splices in.
function RomExtractorGen2:gen2RamName(address)
  local names = self._ramNames
  if not names then
    names = {}
    for name, location in pairs(self.symbols or {}) do
      if type(name) == "string" and type(location) == "table"
         and tonumber(location[1]) == 0 then
        local at = tonumber(location[2])
        -- several symbols share one address; the shortest name is the
        -- buffer itself rather than a field inside it
        if at and (not names[at] or #name < #names[at]
                   or (#name == #names[at] and name < names[at])) then
          names[at] = name
        end
      end
    end
    self._ramNames = names
  end
  return names[address]
end

-- second return is how many bytes were consumed, terminator included, so a
-- caller that knows another string follows can pick it up.  `script` reads a
-- dialogue body, where $50 only ends the current literal run -- stopping
-- there truncated every line with a name spliced into the middle of it (the
-- NAME RATER, the Bug Contest results, "Obtained <item>!").
--
-- The byte budget is a runaway guard, not a real limit: a long multi-page
-- speech (OAK's POKeDEX explanation at MrPokemonsHouse) runs past 512 bytes
-- and used to come out cut mid-word -- "It automatically\nr".  The genuine
-- end is the bank window, so stop there and leave the budget generous.
local GEN2_TEXT_MAX_BYTES = 4096

function RomExtractorGen2:decodeGen2TextAt(bank, address, charmap, script, depth)
  local out = {}
  local offset = 0
  -- keep the three-byte lookaheads ($50 peek, TX_FAR pointer) inside the
  -- window too, so running off the end returns what was read instead of
  -- asserting in Rom.offset
  local limit = (bank == 0 and 0x4000 or 0x8000) - address - 3
  while offset < GEN2_TEXT_MAX_BYTES and offset < limit do
    local value = self.rom:byte(bank, address + offset)
    local splice = script and RomExtractorGen2.GEN2_TEXT_SPLICE[value]
    if value == 0x50 then
      if not (script and RomExtractorGen2.GEN2_TEXT_SPLICE[
                self.rom:byte(bank, address + offset + 1)]) then
        return table.concat(out), offset + 1
      end
    elseif value == 0x16 then
      -- TX_FAR (`db TX_FAR, dw target, db bank`).  The block holding it is
      -- usually nothing BUT this and a $50, with the dialogue itself in
      -- another bank -- which is how every field move's prompt came out as
      -- "{BYTE:16}" followed by three of its own pointer bytes read as
      -- letters.  Print the far body in its place and carry on.
      local target = self.rom:word(bank, address + offset + 1)
      local far = self.rom:byte(bank, address + offset + 3)
      if (depth or 0) < 3 and self:gen2InRom(far, target) then
        out[#out + 1] = (self:decodeGen2TextAt(far, target, charmap, script,
                                               (depth or 0) + 1))
      end
      offset = offset + 3
    elseif value == 0x14 then
      -- TX_STRINGBUFFER `db <index>`: the buffer the ROM filled before it
      -- opened the box -- a nickname, an item, a move name.  The port keeps
      -- one stringBuffer, so every index lands on the token text_ram's
      -- wStringBuffer1 already resolves (TextBox.TOKENS.RAM).
      out[#out + 1] = "{RAM:wStringBuffer1}"
      offset = offset + 1
    elseif value == 0x0C then
      out[#out + 1] = ("."):rep(self.rom:byte(bank, address + offset + 1))
      offset = offset + 1
    elseif value == 0x04 then
      offset = offset + 4  -- TX_BOX: dw, db, db
    elseif value == 0x08 then
      return table.concat(out), offset + 1  -- TX_START_ASM: not followable
    elseif value == 0x05 or value == 0x06 or value == 0x07 or value == 0x0A
           or value == 0x0D or value == 0x15
           or (value >= 0x0E and value <= 0x13) or value == 0x0B then
      -- prompts, pauses, scrolls and jingles: control only, no glyph
    elseif splice then
      local at = self.rom:word(bank, address + offset + 1)
      out[#out + 1] = "{RAM:" .. (self:gen2RamName(at)
                                  or string.format("%04X", at)) .. "}"
      offset = offset + splice
    elseif value == 0x00 then
      -- TX_START: opens another literal run, prints nothing itself
    elseif value == 0x4E or value == 0x4F then
      out[#out + 1] = "\n"
    elseif value == 0x51 then
      out[#out + 1] = "\f"
    elseif value == 0x55 then
      out[#out + 1] = "\v"
    elseif value == 0x57 or value == 0x58 then
      return table.concat(out), offset + 1
    else
      out[#out + 1] = self:textGlyph(charmap, value)
    end
    offset = offset + 1
  end
  return table.concat(out), offset
end


function RomExtractorGen2:extractTextFromRom()
  self:beginStage("Gen2 text (ROM)")
  local texts = self:readSourceTable("text")
  if not self.rom then
    for key, fallback in pairs(INTRO_TEXT_FALLBACKS) do
      local raw = texts[key]
      if type(raw) ~= "string" or raw == "" or raw:match("^%{GEN2_TEXT:") then
        texts[key] = fallback
      end
    end
    self:write("text", texts)
    self:tick("Gen2 text (ROM)", 1, 1)
    return
  end

  local charmap = self:readSourceTable("charmap")
  local keys = {}
  for key in pairs(texts) do keys[#keys + 1] = key end
  table.sort(keys)

  for index, key in ipairs(keys) do
    local raw = texts[key]
    if type(raw) == "string" then
      local bankHex, addrHex = raw:match("^%{GEN2_TEXT:([0-9A-Fa-f]+):([0-9A-Fa-f]+):[^}]+%}$")
      if bankHex and addrHex then
        local bank = tonumber(bankHex, 16)
        local addr = tonumber(addrHex, 16)
        if bank and addr then
          local ok, decoded = pcall(function()
            return self:decodeGen2TextAt(bank, addr, charmap, true)
          end)
          if ok and type(decoded) == "string" and decoded ~= "" then
            texts[key] = decoded
          end
        end
      end
    end
    self:tick("Gen2 text (ROM)", index, #keys)
  end

  for key, fallback in pairs(INTRO_TEXT_FALLBACKS) do
    local raw = texts[key]
    if type(raw) ~= "string" or raw == "" or raw:match("^%{GEN2_TEXT:") then
      texts[key] = fallback
    end
  end

  -- Dialogue recovered by following each map object's script pointer
  for key, location in pairs(self._gen2ScriptTexts or {}) do
    local ok, decoded = pcall(function()
      return self:decodeGen2TextAt(location.bank, location.address, charmap, true)
    end)
    if ok and type(decoded) == "string" and decoded ~= "" then
      texts[key] = decoded
    end
  end

  for key, raw in pairs(texts) do
    if type(raw) == "string" then
      local mapId, stubKey = raw:match("^%{GEN2_TEXT_STUB:([^:}]+):([^}]+)%}$")
      if mapId and stubKey then
        texts[key] = fallbackForStub(mapId, stubKey)
      elseif raw:match("^%{GEN2_TEXT:[^}]+%}$") then
        texts[key] = titleizeWords(key)
      end
    end
  end

  -- kept live for gen2DexEntries, which appends the dex descriptions and
  -- rewrites the file after extractPokemon has run
  self._gen2Texts = texts
  self:write("text", texts)
end

local function writeGeneratedTilesetPlaceholder(path)
  local image = love.image.newImageData(128, 128)
  for ty = 0, 15 do
    for tx = 0, 15 do
      local tile = ty * 16 + tx
      local base = 0.30 + ((tile % 6) * 0.035)
      local r = base
      local g = base
      local b = base
      for py = 0, 7 do
        for px = 0, 7 do
          local edge = (px == 0 or py == 0 or px == 7 or py == 7)
          local shade = edge and 0.82 or 1.0
          image:setPixel(tx * 8 + px, ty * 8 + py, r * shade, g * shade, b * shade, 1)
        end
      end
    end
  end
  ImageWriter.save(image, path)
end

local function writeGeneratedSpritePlaceholder(path)
  local image = love.image.newImageData(16, 96)
  image:mapPixel(function() return 0, 0, 0, 0 end)
  for frame = 0, 5 do
    local y0 = frame * 16
    local bodyR = (frame % 2 == 0) and 0.18 or 0.28
    local bodyG = 0.6
    local bodyB = 0.9
    for y = y0 + 3, y0 + 14 do
      for x = 5, 10 do
        image:setPixel(x, y, bodyR, bodyG, bodyB, 1)
      end
    end
    for y = y0 + 1, y0 + 4 do
      for x = 6, 9 do
        image:setPixel(x, y, 0.95, 0.88, 0.7, 1)
      end
    end
    image:setPixel(6, y0 + 2, 0, 0, 0, 1)
    image:setPixel(9, y0 + 2, 0, 0, 0, 1)
  end
  ImageWriter.save(image, path)
end

local function le16(v)
  return string.char(v % 256, math.floor(v / 256) % 256)
end

local function le32(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

local function toneWav(seconds, hz, amp)
  local sampleRate = 22050
  local frames = math.max(1, math.floor(sampleRate * seconds))
  local chunks = {}
  for i = 0, frames - 1 do
    local sample = 0
    if hz and hz > 0 then
      sample = math.floor(math.sin(2 * math.pi * hz * (i / sampleRate))
        * (amp or 0.25) * 32767)
    end
    if sample < 0 then sample = sample + 65536 end
    chunks[#chunks + 1] = string.char(sample % 256, math.floor(sample / 256))
  end
  local pcm = table.concat(chunks)
  local byteRate = sampleRate * 2
  local blockAlign = 2
  return "RIFF" .. le32(36 + #pcm) .. "WAVE"
    .. "fmt " .. le32(16) .. le16(1) .. le16(1) .. le32(sampleRate)
    .. le32(byteRate) .. le16(blockAlign) .. le16(16)
    .. "data" .. le32(#pcm) .. pcm
end

function RomExtractorGen2:extractScaffoldCore()
  self:beginStage("Gen2 scaffold core")
  local names = {
    "constants", "charmap", "moves", "items", "maps",
    "text", "text_pointers", "trainer_headers",
  }
  for i, name in ipairs(names) do
    local data = name == "constants" and self:constants()
      or self:readSourceTable(name)
    -- Augment items and moves with real names from ROM
    if name == "items" and self.rom then
      local sym = self:symbol("ItemNames")
      local romNames = gen2ReadVarNames(self.rom, sym, 300)
      -- ItemAttributes rows are 7 bytes and open with a little-endian price
      -- (engine/items/item_effects.asm GetItemPrice).  Without it every mart
      -- shelf priced at 0 and BUY handed the stock out for free.
      local attrs = self:symbol("ItemAttributes")
      for id, entry in pairs(data) do
        if type(entry) == "table" and type(entry.index) == "number" then
          local n = romNames[entry.index]
          if n then entry.name = n; entry.source = "ROM:ItemNames[" .. entry.index .. "]" end
          if attrs then
            local row = attrs.address + (entry.index - 1) * GEN2_ITEM_ATTR_BYTES
            local ok, price = pcall(function() return self.rom:word(attrs.bank, row) end)
            if ok and type(price) == "number" then entry.price = price end
            local okp, pocket = pcall(function()
              return self.rom:byte(attrs.bank, row + 5)
            end)
            if okp then
              entry.keyItem = pocket == GEN2_POCKET_KEY_ITEM or nil
              -- the pack's four pages (constants/item_data_constants.asm):
              -- ITEM, KEY_ITEM, BALL, TM_HM
              entry.pocket = ({ [1] = "ITEM", [2] = "KEY_ITEM",
                                [3] = "BALL", [4] = "TM_HM" })[pocket]
            end
            -- the property byte holds CANT_SELECT (1<<6) and CANT_TOSS
            -- (1<<7); Pack.ItemBallsKey_LoadSubmenu builds USE/GIVE/TOSS/
            -- SEL/QUIT out of them, so SEL is offered when the bit is CLEAR
            local okr, prop = pcall(function()
              return self.rom:byte(attrs.bank, row + 4)
            end)
            if okr and type(prop) == "number" then
              entry.registerable = math.floor(prop / 64) % 2 == 0 or nil
              entry.cantToss = math.floor(prop / 128) % 2 == 1 or nil
            end
          end
          entry.key = gen2ItemKey(entry.name)
          -- TM01..TM50 / HM01..HM07 carry the move they teach so
          -- ItemEffects can run the learn flow (GetTMHMMove)
          local kind, number = tostring(entry.key):match("^([TH]M)_(%d+)$")
          if kind then
            local slot = tonumber(number)
              + (kind == "HM" and GEN2_TM_COUNT or 0)
            entry.machine = self:gen2Machines()[slot]
          end
        end
      end
    elseif name == "moves" and self.rom then
      local sym = self:symbol("MoveNames")
      local romNames = gen2ReadVarNames(self.rom, sym, 300)
      for id, entry in pairs(data) do
        if type(entry) == "table" and type(entry.index) == "number" then
          local n = romNames[entry.index]
          if n then entry.name = n; entry.source = "ROM:MoveNames[" .. entry.index .. "]" end
        end
      end
    end
    self:write(name, data)
    self:tick("Gen2 scaffold core", i, #names)
  end
end

-- Gen2/Gen1 sprites store tiles column-major; decode2bpp expects row-major
local function colMajorToRowMajor(pixels, tilesWide, tilesHigh)
  local BPT = 16  -- bytes per tile (8x8 at 2bpp)
  local out = {}
  for y = 0, tilesHigh - 1 do
    for x = 0, tilesWide - 1 do
      local src = (x * tilesHigh + y) * BPT + 1
      local dst = (y * tilesWide + x) * BPT + 1
      for b = 0, BPT - 1 do out[dst + b] = pixels[src + b] end
    end
  end
  return out
end
local GEN2_TYPES = {
  [0]="NORMAL",[1]="FIGHTING",[2]="FLYING",[3]="POISON",
  [4]="GROUND",[5]="ROCK",[6]="BIRD",[7]="BUG",[8]="GHOST",[9]="STEEL",
  [0x13]="CURSE_TYPE",
  [0x14]="FIRE",[0x15]="WATER",[0x16]="GRASS",[0x17]="ELECTRIC",
  [0x18]="PSYCHIC",[0x19]="ICE",[0x1A]="DRAGON",[0x1B]="DARK",
}
-- everything below SPECIAL ($14) is a physical type (Gen2 keeps Gen1's split)
local GEN2_SPECIAL_TYPE = 0x14

-- Gen2 move effect id -> the effect record the battle engine dispatches on
-- (src/battle/MoveEffects.lua).  The ids were read back off the ROM by
-- grouping every move by its effect byte and naming the group from its
-- members, so this table is keyed by what Gold actually stores rather than
-- by a remembered constants file.  Effects with no Gen1 counterpart map to
-- NO_ADDITIONAL_EFFECT, which still lands the move's damage.
--
-- A pair { lowChance, highChance } picks by the move's own effect_chance
-- byte, since Gen2 stores the odds per move while the engine bakes them
-- into the effect record.
local GEN2_MOVE_EFFECTS = {
  [0x00] = "NO_ADDITIONAL_EFFECT",
  [0x01] = "SLEEP_EFFECT",
  [0x02] = { "POISON_SIDE_EFFECT1", "POISON_SIDE_EFFECT2" },
  [0x03] = "DRAIN_HP_EFFECT",
  [0x04] = { "BURN_SIDE_EFFECT1", "BURN_SIDE_EFFECT2" },
  [0x05] = "FREEZE_SIDE_EFFECT1",
  [0x06] = { "PARALYZE_SIDE_EFFECT1", "PARALYZE_SIDE_EFFECT2" },
  [0x07] = "EXPLODE_EFFECT",
  [0x08] = "DREAM_EATER_EFFECT",
  [0x09] = "MIRROR_MOVE_EFFECT",
  [0x0A] = "ATTACK_UP1_EFFECT",
  [0x0B] = "DEFENSE_UP1_EFFECT",
  [0x0C] = "SPEED_UP1_EFFECT",
  [0x0D] = "SP_ATK_UP1_EFFECT",
  [0x0E] = "SP_DEF_UP1_EFFECT",
  [0x0F] = "ACCURACY_UP1_EFFECT",
  [0x10] = "EVASION_UP1_EFFECT",
  [0x11] = "SWIFT_EFFECT",
  [0x12] = "ATTACK_DOWN1_EFFECT",
  [0x13] = "DEFENSE_DOWN1_EFFECT",
  [0x14] = "SPEED_DOWN1_EFFECT",
  [0x15] = "SP_ATK_DOWN1_EFFECT",
  [0x16] = "SP_DEF_DOWN1_EFFECT",
  [0x17] = "ACCURACY_DOWN1_EFFECT",
  [0x18] = "EVASION_DOWN1_EFFECT",
  [0x19] = "HAZE_EFFECT",
  [0x1A] = "BIDE_EFFECT",
  [0x1B] = "THRASH_PETAL_DANCE_EFFECT",
  [0x1C] = "SWITCH_AND_TELEPORT_EFFECT",
  [0x1D] = "TWO_TO_FIVE_ATTACKS_EFFECT",
  [0x1E] = "CONVERSION_EFFECT",
  [0x1F] = { "FLINCH_SIDE_EFFECT1", "FLINCH_SIDE_EFFECT2" },
  [0x20] = "HEAL_EFFECT",
  [0x21] = "POISON_EFFECT",
  [0x22] = "PAY_DAY_EFFECT",
  [0x23] = "LIGHT_SCREEN_EFFECT",
  [0x26] = "OHKO_EFFECT",
  [0x27] = "CHARGE_EFFECT",
  [0x28] = "SUPER_FANG_EFFECT",
  [0x29] = "SPECIAL_DAMAGE_EFFECT",
  [0x2A] = "TRAPPING_EFFECT",
  [0x2C] = "ATTACK_TWICE_EFFECT",
  [0x2D] = "JUMP_KICK_EFFECT",
  [0x2E] = "MIST_EFFECT",
  [0x2F] = "FOCUS_ENERGY_EFFECT",
  [0x30] = "RECOIL_EFFECT",
  [0x31] = "CONFUSION_EFFECT",
  [0x32] = "ATTACK_UP2_EFFECT",
  [0x33] = "DEFENSE_UP2_EFFECT",
  [0x34] = "SPEED_UP2_EFFECT",
  [0x35] = "SP_ATK_UP2_EFFECT",
  [0x36] = "SP_DEF_UP2_EFFECT",
  [0x37] = "ACCURACY_UP2_EFFECT",
  [0x38] = "EVASION_UP2_EFFECT",
  [0x39] = "TRANSFORM_EFFECT",
  [0x3A] = "ATTACK_DOWN2_EFFECT",
  [0x3B] = "DEFENSE_DOWN2_EFFECT",
  [0x3C] = "SPEED_DOWN2_EFFECT",
  [0x3D] = "SP_ATK_DOWN2_EFFECT",
  [0x3E] = "SP_DEF_DOWN2_EFFECT",
  [0x3F] = "ACCURACY_DOWN2_EFFECT",
  [0x40] = "EVASION_DOWN2_EFFECT",
  [0x41] = "REFLECT_EFFECT",
  [0x42] = "POISON_EFFECT",
  [0x43] = "PARALYZE_EFFECT",
  [0x44] = "ATTACK_DOWN_SIDE_EFFECT",
  [0x45] = "DEFENSE_DOWN_SIDE_EFFECT",
  [0x46] = "SPEED_DOWN_SIDE_EFFECT",
  [0x47] = "SP_ATK_DOWN_SIDE_EFFECT",
  [0x48] = "SP_DEF_DOWN_SIDE_EFFECT",
  [0x49] = "ACCURACY_DOWN_SIDE_EFFECT",
  [0x4A] = "EVASION_DOWN_SIDE_EFFECT",
  [0x4B] = "CHARGE_EFFECT",
  [0x4C] = "CONFUSION_SIDE_EFFECT",
  [0x4D] = "TWINEEDLE_EFFECT",
  [0x4F] = "SUBSTITUTE_EFFECT",
  [0x50] = "HYPER_BEAM_EFFECT",
  [0x51] = "RAGE_EFFECT",
  [0x52] = "MIMIC_EFFECT",
  [0x53] = "METRONOME_EFFECT",
  [0x54] = "LEECH_SEED_EFFECT",
  [0x55] = "SPLASH_EFFECT",
  [0x56] = "DISABLE_EFFECT",
  [0x57] = "SPECIAL_DAMAGE_EFFECT",
  [0x58] = "SPECIAL_DAMAGE_EFFECT",
  [0x5C] = "FLINCH_SIDE_EFFECT2",
  [0x6C] = "BURN_SIDE_EFFECT1",
  [0x76] = "CONFUSION_EFFECT",
  [0x7D] = "BURN_SIDE_EFFECT2",
  [0x84] = "HEAL_EFFECT",
  [0x85] = "HEAL_EFFECT",
  [0x86] = "HEAL_EFFECT",
  [0x91] = "CHARGE_EFFECT",
  [0x92] = "FLINCH_SIDE_EFFECT1",
  [0x96] = "FLINCH_SIDE_EFFECT2",
  [0x97] = "CHARGE_EFFECT",
  [0x98] = "PARALYZE_SIDE_EFFECT2",
  [0x99] = "SWITCH_AND_TELEPORT_EFFECT",
  [0x9B] = "FLY_EFFECT",
  [0x9C] = "DEFENSE_UP1_EFFECT",
}
-- effect_chance at or above this picks the high-odds variant of a paired
-- effect (the engine's *_SIDE_EFFECT2 records sit around 30%)
local GEN2_EFFECT_CHANCE_SPLIT = 76
-- EFFECT_PRIORITY_HIT (Quick Attack, Mach Punch, ExtremeSpeed)
local GEN2_EFFECT_PRIORITY_HIT = 0x67
-- EFFECT_TRIPLE_KICK: three strikes, not the engine's 2-5 distribution
local GEN2_EFFECT_TRIPLE_KICK = 0x68

-- "SAND-ATTACK" -> "SAND_ATTACK", matching the Gen1 move constants the
-- battle engine special-cases by id (COUNTER, REST, SEISMIC_TOSS, ...)
local function gen2MoveId(name)
  local id = name:upper():gsub("['%.]", ""):gsub("[%s%-]+", "_")
  id = id:gsub("^_+", ""):gsub("_+$", "")
  if id == "" then return nil end
  return id
end

local function pokeNameToSymKey(name)
  -- pret capitalises each word segment: "MR. MIME" -> "MrMime",
  -- "FARFETCH'D" -> "FarfetchD", "HO-OH" -> "HoOh", "BULBASAUR" -> "Bulbasaur"
  local parts = {}
  for word in name:lower():gmatch("[%a%d]+") do
    parts[#parts + 1] = word:sub(1, 1):upper() .. word:sub(2)
  end
  return table.concat(parts)
end

-- EvosAttacks packs each species' evolution records (variable width, zero
-- terminated) ahead of its `db level, db move` learnset (also zero
-- terminated), so the evolutions have to be walked to find the moves.
-- Moves: 7 bytes each -- db animation, effect, power, type, accuracy, pp,
-- effect_chance -- in move-constant order, with MoveNames alongside.  The
-- scaffold only ever held MOVE_nnn placeholders at 0 power, which is why
-- nothing could be battled with.
function RomExtractorGen2:extractMoves()
  self:beginStage("Gen2 moves")
  local constants = self:constants()
  local order = constants.moveOrder or {}
  local moves = self:readSourceTable("moves")
  local sym = self:symbol("Moves")
  if not (sym and self.rom and #order > 0) then
    self:write("moves", moves)
    self:tick("Gen2 moves", 1, 1)
    return
  end

  local names = gen2ReadVarNames(self.rom, self:symbol("MoveNames"), #order)
  local out, ids = {}, {}
  for index = 1, #order do
    local ok, row = pcall(function()
      return self.rom:bytes(sym.bank, sym.address + (index - 1) * 7, 7)
    end)
    if not ok or type(row) ~= "table" then break end
    local name = names[index] or order[index]
    local id = gen2MoveId(name) or order[index]
    if out[id] then id = order[index] end
    ids[index] = id

    local effect = GEN2_MOVE_EFFECTS[row[2]]
    if type(effect) == "table" then
      effect = row[7] >= GEN2_EFFECT_CHANCE_SPLIT and effect[2] or effect[1]
    end
    local move = {
      id = id, index = index, name = name,
      source = string.format("ROM:Moves[%d]", index),
      effect = effect or "NO_ADDITIONAL_EFFECT",
      power = row[3],
      type = GEN2_TYPES[row[4]] or "NORMAL",
      -- Gen2 stores accuracy as a 0-255 fraction like Gen1
      accuracy = math.floor(row[5] * 100 / 255 + 0.5),
      pp = row[6],
      effectChance = row[7],
      anim = { sound = "SFX_00", pitch = 0, tempo = 0 },
    }
    if row[2] == GEN2_EFFECT_PRIORITY_HIT then move.priority = 1 end
    if row[2] == GEN2_EFFECT_TRIPLE_KICK then move.multiHit = 3 end
    out[id] = move
    self:tick("Gen2 moves", index, #order)
  end

  if next(out) then
    for index = 1, #order do order[index] = ids[index] or order[index] end
    self:write("constants", constants)
    self:write("moves", out)
  else
    self:write("moves", moves)
  end
end

function RomExtractorGen2:gen2Learnsets(count)
  local out = {}
  local sym = self:symbol("EvosAttacksPointers")
  if not (sym and self.rom) then return out end
  local species = self:constants().speciesOrder or {}
  local function speciesId(index)
    return species[index] or string.format("SPECIES_%03d", index)
  end
  for i = 1, count do
    pcall(function()
      local address = self.rom:word(sym.bank, sym.address + (i - 1) * 2)
      local evolutions = {}
      for _ = 1, 16 do
        local method = self.rom:byte(sym.bank, address)
        if method == 0 then break end
        local width = GEN2_EVO_LENGTHS[method] or error("bad evo method")
        local row = self.rom:bytes(sym.bank, address + 1, width - 1)
        local evo
        if method == GEN2_EVOLVE_LEVEL then
          evo = { method = "LEVEL", level = row[1], species = speciesId(row[2]) }
        elseif method == GEN2_EVOLVE_ITEM then
          evo = { method = "ITEM", level = 1,
                  item = string.format("ITEM_%03d", row[1]),
                  species = speciesId(row[2]) }
        elseif method == GEN2_EVOLVE_TRADE then
          -- a held item is required unless the byte is -1 (Kadabra, Machoke)
          evo = { method = "TRADE", level = 1, species = speciesId(row[2]) }
          if row[1] ~= 0xFF then
            evo.heldItem = string.format("ITEM_%03d", row[1])
          end
        elseif method == GEN2_EVOLVE_HAPPINESS then
          evo = { method = "HAPPINESS", species = speciesId(row[2]),
                  timeOfDay = GEN2_EVO_TIMES[row[1]] }
        elseif method == GEN2_EVOLVE_STAT then
          evo = { method = "STAT", level = row[1],
                  compare = GEN2_EVO_STATS[row[2]], species = speciesId(row[3]) }
        end
        if evo then evolutions[#evolutions + 1] = evo end
        address = address + width
      end
      if self.rom:byte(sym.bank, address) ~= 0 then return end
      address = address + 1
      local order = self:constants().moveOrder or {}
      local level1Moves, learnset = {}, {}
      for _ = 1, 64 do
        local level = self.rom:byte(sym.bank, address)
        if level == 0 then break end
        local index = self.rom:byte(sym.bank, address + 1)
        local move = order[index] or string.format("MOVE_%03d", index)
        if level <= 1 then
          level1Moves[#level1Moves + 1] = move
        else
          learnset[#learnset + 1] = { level = level, move = move }
        end
        address = address + 2
      end
      out[i] = { level1Moves = level1Moves, learnset = learnset,
                 evolutions = evolutions }
    end)
  end
  return out
end

-- GetTilePermission (home bank) indexes CollisionPermissionTable by the
-- collision class and keeps the low nybble: 0 land, 1 water, $f wall.
function RomExtractorGen2:gen2CollisionClasses()
  if self._collisionClasses then return self._collisionClasses end
  local land, water = {}, {}
  local sym = self:symbol("CollisionPermissionTable")
  if sym and self.rom then
    pcall(function()
      local raw = self.rom:bytes(sym.bank, sym.address, 256)
      for i, value in ipairs(raw) do
        local permission = value % 16
        if permission == 0 then
          land[#land + 1] = i - 1
        elseif permission == 1 then
          water[#water + 1] = i - 1
        end
      end
    end)
  end
  self._collisionClasses = { land = land, water = water }
  return self._collisionClasses
end

-- Each tileset carries an animation script -- Tileset<Id>Anim, four bytes a
-- row: a VRAM destination and the routine that fills it, run down until
-- DoneTileAnimation.  A row calling AnimateWaterTile is the surf shimmer,
-- and its destination is $9140 = tile $14 in every set that has one, which
-- is what TileRenderer's TILEANIM_WATER already shifts.  Reading the script
-- rather than listing the tilesets keeps Silver and any hack honest.
-- AnimateFlowerTile is deliberately not reported: TILEANIM_WATER_FLOWER
-- would drive it from Gen 1's flower PNGs, which are the wrong drawing.
function RomExtractorGen2:gen2TilesetAnimation(id)
  local sym = self:symbol(id .. "Anim")
  if not (sym and self.rom) then return nil end
  local water = self:symbol("AnimateWaterTile")
  local done = self:symbol("DoneTileAnimation")
  if not (water and done) then return nil end
  local found = false
  pcall(function()
    local raw = self.rom:bytes(sym.bank, sym.address, 48 * 4)
    for pos = 1, #raw - 3, 4 do
      local fn = raw[pos + 2] + raw[pos + 3] * 256
      if fn == water.address then found = true end
      if fn == done.address then break end
    end
  end)
  return found and "TILEANIM_WATER" or nil
end

-- CheckGrassCollision tests wPlayerStandingTile against an $ff-terminated
-- array of ten collision classes, not the single $14 tall-grass class.
function RomExtractorGen2:gen2GrassClasses()
  if self._grassClasses then return self._grassClasses end
  local out = {}
  local sym = self:symbol("CheckGrassCollision.blocks")
  if sym and self.rom then
    pcall(function()
      local raw = self.rom:bytes(sym.bank, sym.address, 32)
      for _, value in ipairs(raw) do
        if value == 0xFF then break end
        out[#out + 1] = value
      end
    end)
  end
  if #out == 0 then out = { GEN2_COLL_TALL_GRASS } end
  self._grassClasses = out
  return out
end

-- DoPlayerMovement.TryJump: any collision class whose high nybble is $A is a
-- ledge, and the low three bits index an eight byte table of facing bits that
-- is ANDed with wFacingDirection.  DoPlayerMovement.action_table (04:4323, six
-- bytes a row, rows d_right/d_left/d_up/d_down) gives those bits as
-- right $01, left $02, up $04, down $08 -- NOT the walking-direction ids.
-- Gen1 keyed hops off a standing-tile/ledge-tile pair instead, so field.ledges
-- has nothing to say here.
local GEN2_LEDGE_HI_NYBBLE = 0xA0
local GEN2_LEDGE_TABLE_BYTES = 8
local GEN2_LEDGE_DIRS = { [0] = "right", [1] = "left", [2] = "up", [3] = "down" }

function RomExtractorGen2:gen2LedgeHops()
  local sym = self:symbol("DoPlayerMovement.ledge_table")
  if not (sym and self.rom) then return nil end
  local ok, raw = pcall(function()
    return self.rom:bytes(sym.bank, sym.address, GEN2_LEDGE_TABLE_BYTES)
  end)
  if not ok or type(raw) ~= "table" then return nil end
  local hops = {}
  for class = GEN2_LEDGE_HI_NYBBLE, GEN2_LEDGE_HI_NYBBLE + 0x0F do
    local mask = raw[class % GEN2_LEDGE_TABLE_BYTES + 1]
    local dirs = {}
    for bit = 0, 3 do
      if math.floor(mask / 2 ^ bit) % 2 == 1 then
        dirs[#dirs + 1] = GEN2_LEDGE_DIRS[bit]
      end
    end
    if #dirs > 0 then hops[class] = dirs end
  end
  return next(hops) and hops or nil
end

-- SpriteMovementData rows are 6 bytes; byte 0 selects the movement function
-- (GetSpriteMovementFunction) and byte 1 the standing facing.  Only the three
-- RandomWalk functions wander, which is what the port's NPC "WALK" means.
local GEN2_MOVE_FN_ROAM = {
  [1] = "UP_DOWN",     -- MovementFunction_RandomWalkY
  [2] = "LEFT_RIGHT",  -- MovementFunction_RandomWalkX
  [3] = "ANY_DIR",     -- MovementFunction_RandomWalkXY
}
local GEN2_MOVE_FACING = { [0] = "DOWN", [1] = "UP", [2] = "LEFT", [3] = "RIGHT" }
local GEN2_MOVEMENT_ENTRY_BYTES = 6
local GEN2_MOVEMENT_MAX = 0x25

function RomExtractorGen2:gen2MovementTable()
  if self._movementTable then return self._movementTable end
  local out = {}
  local sym = self:symbol("SpriteMovementData")
  if sym and self.rom then
    pcall(function()
      local raw = self.rom:bytes(sym.bank, sym.address,
        (GEN2_MOVEMENT_MAX + 1) * GEN2_MOVEMENT_ENTRY_BYTES)
      for index = 0, GEN2_MOVEMENT_MAX do
        local base = index * GEN2_MOVEMENT_ENTRY_BYTES
        local roam = GEN2_MOVE_FN_ROAM[raw[base + 1]]
        if roam then
          out[index] = { movement = "WALK", range = roam }
        else
          out[index] = {
            movement = "STAY",
            range = GEN2_MOVE_FACING[raw[base + 2]] or "DOWN",
          }
        end
      end
    end)
  end
  self._movementTable = out
  return out
end

-- Marts is a dw pointer table; each mart is `db count`, the item ids, `db -1`.
-- The table ends where its own first entry starts.
function RomExtractorGen2:gen2Marts()
  if self._marts then return self._marts end
  local out = {}
  local sym = self:symbol("Marts")
  if sym and self.rom then
    pcall(function()
      local first = self.rom:word(sym.bank, sym.address)
      local count = math.floor((first - sym.address) / 2)
      for index = 0, count - 1 do
        local pointer = self.rom:word(sym.bank, sym.address + index * 2)
        local size = self.rom:byte(sym.bank, pointer)
        local stock = {}
        for slot = 1, math.min(size, 32) do
          local item = self.rom:byte(sym.bank, pointer + slot)
          if item == 0xFF then break end
          stock[#stock + 1] = string.format("ITEM_%03d", item)
        end
        out[index] = stock
      end
    end)
  end
  self._marts = out
  return out
end

-- `pokemart MARTTYPE_*, MART_*` anywhere in the opening bytes of an object's
-- script.  Clerks branch on an event first (Cherrygrove restocks after the
-- rival fight), so the opcode is not always at offset 0.
function RomExtractorGen2:gen2MartStock(bank, address)
  local marts = self:gen2Marts()
  for offset = 0, GEN2_SCRIPT_SCAN_BYTES - 1 do
    local ok, op = pcall(self.rom.byte, self.rom, bank, address + offset)
    if not ok then return nil end
    if op == GEN2_SCRIPT_OP_POKEMART then
      local dialog = self.rom:byte(bank, address + offset + 1)
      local index = self.rom:word(bank, address + offset + 2)
      if dialog <= GEN2_MART_TYPE_MAX and marts[index] and #marts[index] > 0 then
        return marts[index]
      end
    end
  end
  return nil
end

-- Trainer classes and their parties.  TrainerGroups is a dw table of per-class
-- party lists; each party is a $50-terminated name, a trainer type byte, then
-- `db level, species` rows (plus a held item and/or four moves when the type
-- says so) ending at $ff.  A class's data runs up to the next class pointer.
local GEN2_TRAINERTYPE_MOVES = 1
local GEN2_TRAINERTYPE_ITEM = 2

function RomExtractorGen2:gen2TrainerParties(bank, startAddress, endAddress, moveOrder)
  local parties, names = {}, {}
  -- The last group in TrainerGroups has no successor to bound it, so the
  -- caller passes the end of the bank window.  Reading there asserts, which
  -- used to abort the whole class loop and drop GRUNTF (group 66) entirely --
  -- the Slowpoke Well and hideout Rockets then had no party to battle.  Stop
  -- on the first record that cannot be a trainer instead.
  local limit = math.min(endAddress or 0x8000, 0x7FFF)
  local address = startAddress
  local stop = false
  while address < limit and #parties < 64 and not stop do
    local nameBytes = {}
    local named = false
    while address < limit and #nameBytes <= 12 do
      local b = self.rom:byte(bank, address)
      address = address + 1
      if b == 0x50 then named = true break end
      nameBytes[#nameBytes + 1] = b
    end
    local kind = named and address < limit and self.rom:byte(bank, address) or nil
    -- TRAINERTYPE_NORMAL/MOVES/ITEM/ITEM_MOVES is a two bit field
    if not named or #nameBytes == 0 or not kind or kind > 3 then
      stop = true
    else
      address = address + 1
      local party = {}
      while address < limit and #party < 6 and not stop do
        local level = self.rom:byte(bank, address)
        if level == 0xFF then
          address = address + 1
          break
        end
        local species = address + 1 < limit and self.rom:byte(bank, address + 1) or 0
        address = address + 2
        if level < 1 or level > 100 or species < 1 or species > 251 then
          stop = true
        else
          local slot = {
            level = level,
            species = string.format("SPECIES_%03d", species),
          }
          if kind % 4 >= GEN2_TRAINERTYPE_ITEM then
            local item = self.rom:byte(bank, address)
            address = address + 1
            if item > 0 then slot.item = string.format("ITEM_%03d", item) end
          end
          if kind % 2 == GEN2_TRAINERTYPE_MOVES then
            local moves = {}
            for i = 0, 3 do
              local move = self.rom:byte(bank, address + i)
              if move > 0 then
                moves[#moves + 1] = moveOrder[move] or string.format("MOVE_%03d", move)
              end
            end
            address = address + 4
            if #moves > 0 then slot.moves = moves end
          end
          party[#party + 1] = slot
        end
      end
      if not stop then
        parties[#parties + 1] = party
        names[#names + 1] = gen2DecodeString(nameBytes, #nameBytes) or ""
      end
    end
  end
  return parties, names
end

-- Trainer class pics are LZ3 blobs behind a dba table indexed by class - 1,
-- stored column major like the mon pics and always 7x7 tiles.
local GEN2_TRAINER_PIC_TILES = 7

-- FixPicBank (14:5863) rewrites the bank byte of a pic pointer through a
-- from/to table terminated by $FF.  Without it the entries that live past the
-- remap -- Rival2, Champion, Bruno, ... -- decompress from the wrong bank and
-- come out as vertical noise.
function RomExtractorGen2:gen2PicBankFix()
  if self._picBankFix then return self._picBankFix end
  local fix = {}
  local sym = self:symbol("FixPicBank.FixPicBankTable")
  if sym and self.rom then
    pcall(function()
      local address = sym.address
      while address < 0x8000 do
        local from = self.rom:byte(sym.bank, address)
        if from == 0xFF then break end
        fix[from] = self.rom:byte(sym.bank, address + 1)
        address = address + 2
      end
    end)
  end
  self._picBankFix = fix
  return fix
end

function RomExtractorGen2:gen2TrainerPic(group, relative)
  local sym = self:symbol("TrainerPicPointers")
  if not sym or not self.rom then return nil end
  relative = relative or string.format("battle/trainers/class_%02d.png", group)
  local ok = pcall(function()
    local row = sym.address + (group - 1) * 3
    local bank = self.rom:byte(sym.bank, row)
    bank = self:gen2PicBankFix()[bank] or bank
    local address = self.rom:word(sym.bank, row + 1)
    self:gen2WritePic(bank, address, relative, self:gen2TrainerPalette(group))
  end)
  return ok and ("assets/generated/" .. relative) or nil
end

-- TrainerPalettes rows are two BGR555 colors indexed by the class constant
-- itself (ApplyMonOrTrainerPals loads wTrainerClass straight into a);
-- shades 0 and 3 are always white and black.
function RomExtractorGen2:gen2TrainerPalette(group)
  local sym = self:symbol("TrainerPalettes")
  if not (sym and self.rom) then return nil end
  local colors
  pcall(function()
    local row = sym.address + group * 4
    colors = { [0] = { 1, 1, 1 }, [3] = { 0, 0, 0 } }
    for i = 0, 1 do
      local raw = self.rom:word(sym.bank, row + i * 2)
      colors[i + 1] = {
        (raw % 32) / 31,
        (math.floor(raw / 32) % 32) / 31,
        (math.floor(raw / 1024) % 32) / 31,
      }
    end
  end)
  return colors
end

function RomExtractorGen2:gen2WritePic(bank, address, relative, palette)
  local raw = self.rom:bytes(bank, address, 0x8000 - address)
  local pixels = decompressLz3(raw)
  local tiles = GEN2_TRAINER_PIC_TILES
  assert(#pixels >= tiles * tiles * 16, "short trainer pic")
  local reordered = colMajorToRowMajor(pixels, tiles, tiles)
  -- matte before the recolor: matteColor0 keys on pure white, which is
  -- shade 0 of every trainer palette
  local image = ImageWriter.matteColor0(
    ImageWriter.decode2bpp(reordered, tiles * 8, tiles * 8))
  self:saveImage(ImageWriter.recolorShades(image, palette), relative)
end

-- Two groups share the RIVAL class name; the port's battle code keys the
-- player-named rival off these ids.
local GEN2_RIVAL_GROUPS = { [9] = "RIVAL1", [42] = "RIVAL2" }
-- TrainerPicPointers rows for the two faces the new game intro shows
local GEN2_CLASS_RIVAL1 = 9
local GEN2_CLASS_POKEMON_PROF = 10

-- GetTrainerAttributes (0E:5541) indexes TrainerClassAttributes by class - 1
-- with a 7-byte stride and copies bytes 0..1 to the AI's item slots and byte
-- 2 to wEnemyTrainerBaseReward.  ComputeTrainerReward then multiplies that by
-- the level of the last mon, which is the same shape as Gen1's baseMoney --
-- so BattleState's payout works untouched once the byte is on the class.
local GEN2_CLASS_ATTRIBUTE_BYTES = 7
local GEN2_CLASS_ATTRIBUTE_REWARD = 2

function RomExtractorGen2:gen2TrainerBaseMoney(group)
  local sym = self:symbol("TrainerClassAttributes")
  if not (sym and self.rom) then return 0 end
  local ok, value = pcall(function()
    return self.rom:byte(sym.bank, sym.address
      + (group - 1) * GEN2_CLASS_ATTRIBUTE_BYTES + GEN2_CLASS_ATTRIBUTE_REWARD)
  end)
  return (ok and value) or 0
end

function RomExtractorGen2:gen2Trainers()
  if self._trainers then return self._trainers end
  local byClass, byGroup = {}, {}
  local sym = self:symbol("TrainerGroups")
  if sym and self.rom then
    local moveOrder = (self:constants() or {}).moveOrder or {}
    pcall(function()
      local first = self.rom:word(sym.bank, sym.address)
      local count = math.floor((first - sym.address) / 2)
      local classNames = gen2ReadVarNames(
        self.rom, self:symbol("TrainerClassNames"), count)
      local used = {}
      local function sanitize(text)
        local label = tostring(text or ""):upper():gsub("[^%u%d]+", "_")
        return (label:gsub("^_+", ""):gsub("_+$", ""))
      end
      for group = 1, count do
        local startAddress = self.rom:word(sym.bank, sym.address + (group - 1) * 2)
        local endAddress = group < count
          and self.rom:word(sym.bank, sym.address + group * 2) or 0x8000
        local parties, names = self:gen2TrainerParties(
          sym.bank, startAddress, endAddress, moveOrder)
        local className = classNames[group]
        local label = GEN2_RIVAL_GROUPS[group] or sanitize(className)
        if label == "" then label = string.format("GROUP_%02d", group) end
        if used[label] then
          local alt = sanitize(names[1])
          label = label .. "_" .. (alt ~= "" and alt or tostring(group))
        end
        if used[label] then label = label .. "_" .. tostring(group) end
        used[label] = true
        local id = "OPP_" .. label
        byClass[id] = {
          id = id,
          index = group,
          name = className or label,
          source = "ROM:TrainerGroups",
          baseMoney = self:gen2TrainerBaseMoney(group),
          parties = parties,
          partyNames = names,
        }
        byGroup[group] = id
      end
    end)
  end
  self._trainers = { byClass = byClass, byGroup = byGroup }
  return self._trainers
end

-- index -> the move id extractMoves keys moves.lua by.  Derived from
-- MoveNames the same way rather than read back out of the table, because the
-- items stage runs before extractMoves has replaced the MOVE_nnn scaffold.
function RomExtractorGen2:gen2MoveIdsByIndex()
  if self._gen2MoveIds then return self._gen2MoveIds end
  local byIndex = {}
  local order = (self:constants() or {}).moveOrder or {}
  if self.rom and #order > 0 then
    local names = gen2ReadVarNames(self.rom, self:symbol("MoveNames"), #order)
    local seen = {}
    for index = 1, #order do
      local name = names[index] or order[index]
      local id = gen2MoveId(name) or order[index]
      if seen[id] then id = order[index] end
      seen[id] = true
      byIndex[index] = id
    end
  end
  self._gen2MoveIds = byIndex
  return byIndex
end

-- machines[n] = { kind, number, move } for machine slot n (1..57)
function RomExtractorGen2:gen2Machines()
  if self._gen2Machines then return self._gen2Machines end
  local out = {}
  local sym = self.rom and self:symbol("TMHMMoves")
  if sym then
    local byIndex = self:gen2MoveIdsByIndex()
    local total = GEN2_TM_COUNT + GEN2_HM_COUNT
    local ok, bytes = pcall(function()
      return self.rom:bytes(sym.bank, sym.address, total)
    end)
    if ok and type(bytes) == "table" then
      for n = 1, total do
        local move = byIndex[bytes[n] or 0]
        if move then
          local hm = n > GEN2_TM_COUNT
          out[n] = {
            kind = hm and "HM" or "TM",
            number = hm and (n - GEN2_TM_COUNT) or n,
            move = move,
          }
        end
      end
    end
  end
  self._gen2Machines = out
  return out
end

-- The three breeding bytes of a base_stats row (1-based into the 32-byte
-- entry).  Class fields rather than chunk locals: this file sits on Lua's
-- 200-local-per-chunk ceiling.
RomExtractorGen2.GEN2_BASE_GENDER = 14      -- GENDER_F* threshold, 255 = none
RomExtractorGen2.GEN2_BASE_EGG_CYCLES = 16  -- steps to hatch, in units of 256
RomExtractorGen2.GEN2_BASE_EGG_GROUPS = 24  -- dn group1, group2
RomExtractorGen2.GEN2_EGG_GROUPS = {
  [1] = "MONSTER", [2] = "WATER_1", [3] = "BUG", [4] = "FLYING",
  [5] = "GROUND", [6] = "FAIRY", [7] = "PLANT", [8] = "HUMANSHAPE",
  [9] = "WATER_3", [10] = "MINERAL", [11] = "INDETERMINATE",
  [12] = "WATER_2", [13] = "DITTO", [14] = "DRAGON", [15] = "NONE",
}

function RomExtractorGen2:extractPokemon()
  self:beginStage("Gen2 Pokemon")
  local constants = self:constants()
  local speciesOrder = constants.speciesOrder or {}
  local fallbackMove = constants.moveOrder and constants.moveOrder[1] or "TACKLE"

  local pokeNames = gen2ReadFixedNames(self.rom, self:symbol("PokemonNames"), #speciesOrder, 10)
  local learnsets = self:gen2Learnsets(#speciesOrder)

  -- Base stats from BaseData (14:5b0b, 32 bytes/entry, dex order)
  local baseSym = self:symbol("BaseData")
  local ENTRY = 32
  local machines = self:gen2Machines()

  local out = {}
  local spritesWritten = 0
  for i, id in ipairs(speciesOrder) do
    local name = pokeNames[i] or id
    local hp, atk, def, spd, satk, sdef = 45, 49, 49, 45, 65, 65
    local type1, type2 = "NORMAL", "NORMAL"
    local catchRate, baseExp = 45, 64
    local growthRate = "MEDIUM_FAST"
    local picDims = 0x77  -- default 7x7; overwritten from BaseData below
    local tmhm = {}
    -- breeding: no Gen1 counterpart, so these stay nil on a Red/Blue import
    local genderRatio, eggCycles, eggGroups

    if baseSym and self.rom then
      local ok, entry = pcall(function()
        return self.rom:bytes(baseSym.bank, baseSym.address + (i - 1) * ENTRY, ENTRY)
      end)
      if ok and type(entry) == "table" and #entry >= 11 then
        hp=entry[2]; atk=entry[3]; def=entry[4]; spd=entry[5]; satk=entry[6]; sdef=entry[7]
        type1 = GEN2_TYPES[entry[8]]  or "NORMAL"
        type2 = GEN2_TYPES[entry[9]]  or type1
        catchRate = entry[10]; baseExp = entry[11]
        growthRate = GEN2_GROWTH_RATES[entry[GEN2_BASE_GROWTH_RATE]] or growthRate
      end
      if ok and type(entry) == "table" and #entry >= ENTRY then
        genderRatio = entry[RomExtractorGen2.GEN2_BASE_GENDER]
        eggCycles = entry[RomExtractorGen2.GEN2_BASE_EGG_CYCLES]
        local groups = entry[RomExtractorGen2.GEN2_BASE_EGG_GROUPS] or 0
        local names = RomExtractorGen2.GEN2_EGG_GROUPS
        local g1 = names[math.floor(groups / 16)]
        local g2 = names[groups % 16]
        if g1 then
          eggGroups = { g1 }
          if g2 and g2 ~= g1 then eggGroups[2] = g2 end
        end
        for byteIndex = 0, 7 do
          local value = entry[GEN2_BASE_TMHM_FIRST + byteIndex] or 0
          for bit = 0, 7 do
            if math.floor(value / 2 ^ bit) % 2 == 1 then
              local slot = machines[byteIndex * 8 + bit + 1]
              if slot then tmhm[#tmhm + 1] = slot.move end
            end
          end
        end
      end
      picDims = (ok and type(entry) == "table" and entry[GEN2_BASE_PIC_DIMS]) or 0x55
    end

    local picTilesW = math.max(1, math.floor(picDims / 16))
    local picTilesH = math.max(1, picDims % 16)

    -- Battle sprites from individual *Frontpic / *Backpic symbols
    local cleanName = name:lower():gsub("[^%a%d]", "")
    local capKey   = pokeNameToSymKey(name)
    -- placeholder.png, not pikachu.png: extractAssets stamps the logo over
    -- whatever the fallback names, and naming a real species there wiped
    -- PIKACHU's own pic every run
    local spriteFront = "assets/generated/battle/front/placeholder.png"
    local spriteBack  = "assets/generated/battle/back/placeholder.png"
    local forms

    if self.rom and cleanName ~= "" then
      -- one LZ3 pic -> one PNG; returns the asset path or nil
      local function writePic(symbolName, dir, fileBase)
        local sym = self:symbol(symbolName)
        if not sym then return nil end
        local ok1, raw = pcall(function()
          return self.rom:bytes(sym.bank, sym.address, 0x8000 - sym.address)
        end)
        if not ok1 or type(raw) ~= "table" then return nil end
        local ok2, pixels = pcall(decompressLz3, raw)
        if not ok2 or type(pixels) ~= "table" or #pixels < 16 then return nil end
        -- Trust the decompressed size over pic_dims; pics are square
        local tiles = math.floor(#pixels / 16)
        local side = math.floor(math.sqrt(tiles) + 0.5)
        local tw, th = picTilesW, picTilesH
        if side * side == tiles then tw, th = side, side end
        if tw * th * 16 > #pixels then return nil end
        -- Gen2 pics store tiles column-major; decode2bpp wants row-major
        local reordered = colMajorToRowMajor(pixels, tw, th)
        local relPath = "battle/" .. dir .. "/" .. fileBase .. ".png"
        local ok3 = pcall(function()
          -- matte the paper away or the pic draws a white box over the
          -- colorized battlefield it sits on
          self:saveImage(ImageWriter.matteColor0(
            ImageWriter.decode2bpp(reordered, tw * 8, th * 8)), relPath)
        end)
        if not ok3 then return nil end
        spritesWritten = spritesWritten + 1
        return "assets/generated/" .. relPath
      end

      local function trySprite(symSuffix, dir, dest)
        local candidates = { capKey .. symSuffix }
        if cleanName == "nidoran" then
          candidates = { "NidoranM"..symSuffix, "NidoranF"..symSuffix, "Nidoran"..symSuffix }
        elseif cleanName == "unown" then
          candidates = { "UnownA"..symSuffix, "Unown"..symSuffix }
        end
        for _, candidate in ipairs(candidates) do
          local path = writePic(candidate, dir, cleanName)
          if path then return path end
        end
        return dest
      end
      spriteFront = trySprite("Frontpic", "front", spriteFront)
      spriteBack  = trySprite("Backpic",  "back",  spriteBack)

      -- UNOWN has 26 pics, one per letter, chosen from the DVs
      -- (GetUnownLetter 20:$5749); without them every UNOWN was an "A".
      if cleanName == "unown" then
        forms = {}
        for index = 1, 26 do
          local letter = string.char(64 + index)
          local base = "unown_" .. letter:lower()
          forms[index] = {
            letter = letter,
            spriteFront = writePic("Unown" .. letter .. "Frontpic", "front", base)
              or spriteFront,
            spriteBack = writePic("Unown" .. letter .. "Backpic", "back", base)
              or spriteBack,
          }
        end
      end
    end

    local learn = learnsets[i] or {}
    local level1Moves = learn.level1Moves or {}
    if #level1Moves == 0 then
      level1Moves = { learn.learnset and learn.learnset[1] and learn.learnset[1].move or fallbackMove }
    end

    out[id] = {
      id = id, index = i, dex = i, name = name,
      trueColor = false, type1 = type1, type2 = type2,
      types = type2 ~= type1 and { type1, type2 } or { type1 },
      baseStats = {
        hp = hp, attack = atk, defense = def, speed = spd,
        special = satk, spatk = satk, spdef = sdef,
      },
      catchRate = catchRate, baseExp = baseExp, growthRate = growthRate,
      tmhm = tmhm,
      -- breeding (base_stats bytes 14/16/24): DayCare.compatibility needs
      -- the real groups and gender split, and Gen2Commands' giveegg needs
      -- the species' own hatch counter instead of a flat five cycles
      genderRatio = genderRatio, eggCycles = eggCycles, eggGroups = eggGroups,
      level1Moves = level1Moves, learnset = learn.learnset or {},
      evolutions = learn.evolutions or {},
      spriteFront = spriteFront, spriteBack = spriteBack,
      forms = forms,
      -- the species' real CGB colour pair (see extractPalettes);
      -- PaletteFX.monPal honours this ahead of its species->name map, so
      -- every COLORS mode reaches the Gen2 palette rather than MEWMON
      palette = "MON_" .. id,
      shinyPalette = "MON_" .. id .. "_SHINY",
      icon = "assets/generated/icons/placeholder.png",
    }
  end
  Logger.info("Gen2 Pokemon: %d sprites extracted", spritesWritten)
  self:gen2DexEntries(out)
  self:write("pokemon", out)
  self:tick("Gen2 Pokemon", 1, 1)
end

-- GetDexEntryPointer (11:4326): the row is `dw pointer` at
-- PokedexDataPointerTable + (dex - 1) * 2, and the bank is $68 plus the top
-- two bits of (dex - 1) -- i.e. one bank per 64 dex numbers.  The entry
-- itself is `db kind@`, `dw height`, `dw weight`, then the description; the
-- height is decimal-coded feet/inches (204 = 2'04") and the weight is tenths
-- of a pound, which is exactly what DexEntryMenu prints.
local GEN2_DEX_POINTER_BANK = 0x68

function RomExtractorGen2:gen2DexEntries(pokemon)
  local table_ = self:symbol("PokedexDataPointerTable")
  if not (self.rom and table_) then return end
  local charmap = self:readSourceTable("charmap")
  local texts = self._gen2Texts
  local written = 0
  for _, def in pairs(pokemon) do
    local dex = tonumber(def.dex)
    if dex and dex >= 1 then
      local ok = pcall(function()
        local row = table_.address + (dex - 1) * 2
        local address = self.rom:word(table_.bank, row)
        local bank = GEN2_DEX_POINTER_BANK + math.floor((dex - 1) / 64)
        local kind, offset = {}, 0
        while offset < 16 do
          local value = self.rom:byte(bank, address + offset)
          offset = offset + 1
          if value == 0x50 then break end
          kind[#kind + 1] = self:textGlyph(charmap, value)
        end
        local height = self.rom:word(bank, address + offset)
        local weight = self.rom:word(bank, address + offset + 2)
        -- the description is TWO $50-terminated strings: the dex screen
        -- prints the first page, then the second on a button press.  Reading
        -- only as far as the first terminator dropped the back half of every
        -- entry.
        local body, used = self:decodeGen2TextAt(bank, address + offset + 4, charmap)
        local page2 = self:decodeGen2TextAt(bank, address + offset + 4 + used, charmap)
        if page2 ~= "" then body = body .. "\n" .. page2 end
        local key = "_Gen2DexEntry_" .. tostring(def.id)
        if texts and body ~= "" then texts[key] = body end
        def.dexEntry = {
          kind = table.concat(kind),
          heightFt = math.floor(height / 100),
          heightIn = height % 100,
          weight = weight,
          text = (texts and body ~= "") and key or nil,
        }
        written = written + 1
      end)
      if not ok then def.dexEntry = nil end
    end
  end
  Logger.info("Gen2 Pokemon: %d dex entries", written)
  -- extractTextFromRom already wrote text.lua; the descriptions have to go
  -- back through it because DexEntryMenu looks them up by label
  if texts and written > 0 then self:write("text", texts) end
end

-- ------------------------------------------------------------------
-- CGB colour.  Gen1 had no palettes of its own -- the Super Game Boy
-- supplied them -- so RomExtractor rips SuperPalettes/MonsterPalettes and
-- PaletteFX colorizes DMG-grey art through a shader.  Gen2 IS a Game Boy
-- Color game: every species carries two real 15-bit colours, and the four
-- shades on screen are white / colour 1 / colour 2 / black
-- (LoadPalette_White_Col1_Col2_Black, 02:5ADB).  Without a palettes.lua
-- data.palettes was nil for Gold, which made BattleState:colorMode() fail
-- outright -- the battle drew in flat greys no matter what COLORS said.
-- ------------------------------------------------------------------

-- PokemonPalettes (02:6D3D) is 8 bytes per entry -- normal colour 1,
-- normal colour 2, shiny colour 1, shiny colour 2 -- indexed BY SPECIES
-- NUMBER, with entry 0 the "?" placeholder, so Bulbasaur sits at +8.
local GEN2_MON_PAL_BYTES = 8
-- HPBarPals (02:6D2D) is the three two-colour bar palettes, green first,
-- immediately before ExpBarPalette and PokemonPalettes.
local GEN2_BAR_PAL_NAMES = { "GREENBAR", "YELLOWBAR", "REDBAR" }
local GEN2_PAL_WHITE = { 255, 255, 255 }
local GEN2_PAL_BLACK = { 0, 0, 0 }

local function gen2Rgb5(value)
  local function channel(shift)
    local v = math.floor(value / shift) % 32
    return math.floor(v * 255 / 31 + 0.5)
  end
  return { channel(1), channel(32), channel(1024) }
end

-- name a species' palette carries in data.palettes.palettes; also stamped
-- on the pokemon record as `palette`, which PaletteFX.monPal honours ahead
-- of the species->name map (so ADVANCED, whose pack is the Gen1 gbc table,
-- still resolves the real Gen2 colours instead of collapsing to MEWMON).
local function gen2MonPalName(id) return "MON_" .. id end

function RomExtractorGen2:gen2MonPalettes()
  if self._monPalettes then return self._monPalettes end
  local out = {}
  local shiny = {}
  local sym = self:symbol("PokemonPalettes")
  if sym and self.rom then
    for i, id in ipairs((self:constants().speciesOrder or {})) do
      local ok, colors, shinyColors = pcall(function()
        local base = sym.address + i * GEN2_MON_PAL_BYTES
        return {
          GEN2_PAL_WHITE,
          gen2Rgb5(self.rom:word(sym.bank, base)),
          gen2Rgb5(self.rom:word(sym.bank, base + 2)),
          GEN2_PAL_BLACK,
        }, {
          GEN2_PAL_WHITE,
          gen2Rgb5(self.rom:word(sym.bank, base + 4)),
          gen2Rgb5(self.rom:word(sym.bank, base + 6)),
          GEN2_PAL_BLACK,
        }
      end)
      if ok then
        out[id] = colors
        shiny[id] = shinyColors
      end
    end
  end
  self._monPalettes = out
  self._monShinyPalettes = shiny
  return out, shiny
end

-- GetMonNormalOrShinyPalettePointer (02:$5C66) picks the second half of the
-- row when CheckShininess says yes; the red Gyarados is nothing more than
-- that -- a GYARADOS wearing PokemonPalettes[GYARADOS] + 4.
function RomExtractorGen2:gen2MonShinyPalettes()
  if not self._monShinyPalettes then self:gen2MonPalettes() end
  return self._monShinyPalettes or {}
end

function RomExtractorGen2:extractPalettes()
  self:beginStage("Gen2 palettes")
  local palettes, pokemon, order = {}, {}, {}
  for id, colors in pairs(self:gen2MonPalettes()) do
    local name = gen2MonPalName(id)
    palettes[name] = colors
    pokemon[id] = name
    order[#order + 1] = name
  end
  for id, colors in pairs(self:gen2MonShinyPalettes()) do
    local name = gen2MonPalName(id) .. "_SHINY"
    palettes[name] = colors
    order[#order + 1] = name
  end
  table.sort(order)

  local bars = self:symbol("HPBarPals")
  if bars and self.rom then
    for index, name in ipairs(GEN2_BAR_PAL_NAMES) do
      pcall(function()
        local base = bars.address + (index - 1) * 4
        palettes[name] = {
          GEN2_PAL_WHITE,
          gen2Rgb5(self.rom:word(bars.bank, base)),
          gen2Rgb5(self.rom:word(bars.bank, base + 2)),
          GEN2_PAL_BLACK,
        }
      end)
    end
  end

  -- ExpBarPalette is four bytes, laid out exactly like one HPBarPals entry:
  -- colors 1 and 2 only (the HUD's tan and the bar's blue), with white and
  -- black implied at the ends.  PokemonPalettes starts four bytes later.
  local expPal = self:symbol("ExpBarPalette")
  if expPal and self.rom then
    pcall(function()
      palettes.EXPBAR = {
        GEN2_PAL_WHITE,
        gen2Rgb5(self.rom:word(expPal.bank, expPal.address)),
        gen2Rgb5(self.rom:word(expPal.bank, expPal.address + 2)),
        GEN2_PAL_BLACK,
      }
    end)
  end

  -- The "?" entry at PokemonPalettes+0 is what the game shows for an
  -- unknown species; PaletteFX asks for MEWMON in exactly that spot, and
  -- for GRAYMON when a mon is TRANSFORMED.
  local unknown = self:symbol("PokemonPalettes")  if unknown and self.rom then
    pcall(function()
      palettes.MEWMON = {
        GEN2_PAL_WHITE,
        gen2Rgb5(self.rom:word(unknown.bank, unknown.address)),
        gen2Rgb5(self.rom:word(unknown.bank, unknown.address + 2)),
        GEN2_PAL_BLACK,
      }
    end)
  end
  palettes.GRAYMON = palettes.GRAYMON or {
    GEN2_PAL_WHITE, { 173, 173, 173 }, { 82, 82, 82 }, GEN2_PAL_BLACK,
  }
  palettes.BLACK = { GEN2_PAL_BLACK, GEN2_PAL_BLACK, GEN2_PAL_BLACK, GEN2_PAL_BLACK }

  self:write("palettes", {
    source = "ROM:PokemonPalettes + HPBarPals",
    palettes = palettes, order = order, pokemon = pokemon,
  })
  self:tick("Gen2 palettes", 1, 1)
end

-- ------------------------------------------------------------------
-- Party-menu icons.  MonMenuIcons (23:6975) is ONE byte per species (the
-- icon set runs past $0F, so it is not the packed nybble array Gen1 used),
-- IconPointers (23:6A70) is a dw per icon into the same bank, and every
-- icon is 8 tiles / 128 bytes: two 16x16 frames, each four tiles in
-- reading order (top-left, top-right, bottom-left, bottom-right).  Gold
-- shipped no icons.lua at all, so PartyMenu's `if not icons then return
-- end` drew nothing -- the missing party sprites.
-- ------------------------------------------------------------------
local GEN2_ICON_BYTES = 8 * 16

function RomExtractorGen2:extractIcons()
  self:beginStage("Gen2 party icons")
  local speciesOrder = self:constants().speciesOrder or {}
  local monPalettes = self:gen2MonPalettes()
  local menuSym = self:symbol("MonMenuIcons")
  local ptrSym = self:symbol("IconPointers")
  local bySpecies = {}

  if menuSym and ptrSym and self.rom then
    local okIndices, indices = pcall(function()
      return self.rom:bytes(menuSym.bank, menuSym.address, #speciesOrder)
    end)
    if okIndices and type(indices) == "table" then
      for i, id in ipairs(speciesOrder) do
        local iconIndex = indices[i]
        local colors = monPalettes[id]
        if iconIndex and colors then
          local relPath = "icons/" .. id:lower() .. ".png"
          local ok = pcall(function()
            local address = self.rom:word(ptrSym.bank,
                                          ptrSym.address + iconIndex * 2)
            local raw = self.rom:bytes(ptrSym.bank, address, GEN2_ICON_BYTES)
            local tiles = gen2SplitTiles(raw)
            -- OBJ colour 0 is transparent, so the sheet keeps alpha 0 there
            -- and PartyMenu's plain (non-#obp) load draws it as authored.
            local pal = {}
            for n = 1, 4 do
              pal[n] = { colors[n][1] / 255, colors[n][2] / 255, colors[n][3] / 255 }
            end
            local image = ImageWriter.blank(16, 32, 0, 0, 0, 0)
            for frame = 0, 1 do
              for col = 0, 1 do
                for row = 0, 1 do
                  local tile = tiles[frame * 4 + row * 2 + col]
                  if tile then
                    for y = 0, 7 do
                      for x = 0, 7 do
                        local shade = tile[y * 8 + x + 1]
                        if shade ~= 0 then
                          local c = pal[shade + 1]
                          image:setPixel(col * 8 + x, frame * 16 + row * 8 + y,
                                         c[1], c[2], c[3], 1)
                        end
                      end
                    end
                  end
                end
              end
            end
            self:saveImage(image, relPath)
          end)
          if ok then
            -- a table entry (rather than a built-in icon NAME) is what tells
            -- PartyMenu this is authored art: no OBP re-bake and no OAM
            -- left-half mirror, both of which are Gen1-only behaviour.
            bySpecies[id] = { image = "assets/generated/" .. relPath }
          end
        end
        if i % 32 == 0 then self:tick("Gen2 party icons", i, #speciesOrder) end
      end
    end
  end

  local count = 0
  for _ in pairs(bySpecies) do count = count + 1 end
  Logger.info("Gen2 icons: %d species icons written", count)
  self:write("icons", {
    source = "ROM:MonMenuIcons + IconPointers",
    icons = {}, byDex = {}, bySpecies = bySpecies,
  })
  self:tick("Gen2 party icons", 1, 1)
end

-- GrassMonProbTable / WaterMonProbTable, as the cumulative 0..256 thresholds
-- Encounter.roll compares a rand(0,255) against.
local GEN2_GRASS_BUCKETS = { 77, 154, 205, 230, 243, 253, 256 }
local GEN2_WATER_BUCKETS = { 154, 230, 256 }
local GEN2_GRASS_SLOTS, GEN2_WATER_SLOTS = 7, 3
local GEN2_GRASS_RECORD = 2 + 3 + GEN2_GRASS_SLOTS * 2 * 3
local GEN2_WATER_RECORD = 2 + 1 + GEN2_WATER_SLOTS * 2

-- One `db level, db species` run out of a wildmons record.
function RomExtractorGen2:gen2WildSlots(bank, address, count)
  local slots = {}
  local raw = self.rom:bytes(bank, address, count * 2)
  for i = 1, count do
    slots[i] = {
      level = raw[i * 2 - 1],
      species = string.format("SPECIES_%03d", raw[i * 2]),
    }
  end
  return slots
end

function RomExtractorGen2:extractEncounters()
  self:beginStage("Gen2 encounters")
  local out = {}

  -- Wildmons records are keyed by (map group, map number) and each carries a
  -- morn/day/nite set; the engine has one slot table per map, so it gets day.
  local mapIndex = self:gen2MapIndex()
  local keyByLabel = {}
  for mapId, def in pairs(self:readSourceTable("maps")) do
    if type(def) == "table" then
      out[mapId] = {
        grass = { rate = 0, slots = {} },
        water = { rate = 0, slots = {} },
        fish = { old = {}, good = {}, super = {} },
      }
    end
    local label = (type(def) == "table")
      and ((type(def.label) == "string" and def.label)
           or (type(def.source) == "string"
               and def.source:match("^SYMBOL:(.+)_MapAttributes$")))
    if label and not keyByLabel[label] then keyByLabel[label] = mapId end
  end

  local filled = 0
  local function walk(symbolName, terrain, record, slotCount, buckets)
    local sym = self.rom and self:symbol(symbolName)
    if not sym then return end
    local grass = terrain == "grass"
    local address = sym.address
    for _ = 1, 256 do
      if self.rom:byte(sym.bank, address) == 0xFF then break end
      local group = self.rom:byte(sym.bank, address)
      local number = self.rom:byte(sym.bank, address + 1)
      local entry = mapIndex[group * 256 + number]
      local mapId = entry and keyByLabel[entry.label]
      if mapId and out[mapId] then
        -- grass: db morn, day, nite rates then the morn/day/nite slot sets.
        -- `grass` stays the day table (what the Gen1-shaped roll reads) and
        -- the other two ride alongside for GetTimeOfDay to pick.
        local slotBase = grass and 5 or 3
        local entry = {
          rate = self.rom:byte(sym.bank, address + (grass and 3 or 2)),
          buckets = buckets,
          slots = self:gen2WildSlots(sym.bank,
            address + slotBase + (grass and slotCount * 2 or 0), slotCount),
        }
        if grass then
          entry.byTime = {
            morn = {
              rate = self.rom:byte(sym.bank, address + 2),
              buckets = buckets,
              slots = self:gen2WildSlots(sym.bank, address + slotBase, slotCount),
            },
            nite = {
              rate = self.rom:byte(sym.bank, address + 4),
              buckets = buckets,
              slots = self:gen2WildSlots(sym.bank,
                address + slotBase + slotCount * 4, slotCount),
            },
          }
        end
        out[mapId][terrain] = entry
        filled = filled + 1
      end
      address = address + record
    end
  end

  pcall(walk, "JohtoGrassWildMons", "grass", GEN2_GRASS_RECORD, GEN2_GRASS_SLOTS, GEN2_GRASS_BUCKETS)
  pcall(walk, "KantoGrassWildMons", "grass", GEN2_GRASS_RECORD, GEN2_GRASS_SLOTS, GEN2_GRASS_BUCKETS)
  pcall(walk, "JohtoWaterWildMons", "water", GEN2_WATER_RECORD, GEN2_WATER_SLOTS, GEN2_WATER_BUCKETS)
  pcall(walk, "KantoWaterWildMons", "water", GEN2_WATER_RECORD, GEN2_WATER_SLOTS, GEN2_WATER_BUCKETS)

  Logger.info("Gen2 encounters: %d tables from ROM", filled)
  self:write("encounters", out)
  self:tick("Gen2 encounters", 1, 1)
end

-- Walks MapGroupPointers and its 9-byte map headers so ROM (group, number)
-- references -- which is how warps and connections name their targets -- can be
-- resolved back to a map label.
function RomExtractorGen2:gen2MapIndex()
  if self._mapIndex then return self._mapIndex, self._mapHeaderByLabel end
  local byGroupNumber, byLabel = {}, {}
  self._mapIndex, self._mapHeaderByLabel = byGroupNumber, byLabel

  local ptr = self:symbol("MapGroupPointers")
  if not (ptr and self.rom) then return byGroupNumber, byLabel end

  local attrLabel = {}
  for name, location in pairs(self.symbols or {}) do
    local label = type(name) == "string" and name:match("^(.+)_MapAttributes$")
    if label and type(location) == "table" then
      local bank, address = tonumber(location[1]), tonumber(location[2])
      if bank and address then attrLabel[bank * 0x10000 + address] = label end
    end
  end

  pcall(function()
    local starts = {}
    for group = 1, GEN2_MAP_GROUP_COUNT do
      starts[group] = self.rom:word(ptr.bank, ptr.address + (group - 1) * 2)
    end
    -- a group's header list runs until the next group's list begins
    local sorted = {}
    for _, address in ipairs(starts) do sorted[#sorted + 1] = address end
    table.sort(sorted)
    local following = {}
    for i, address in ipairs(sorted) do following[address] = sorted[i + 1] end

    for group = 1, GEN2_MAP_GROUP_COUNT do
      local base = starts[group]
      local stop = following[base]
      local count = stop and math.floor((stop - base) / GEN2_MAP_HEADER_BYTES) or 32
      for number = 1, count do
        local header = base + (number - 1) * GEN2_MAP_HEADER_BYTES
        local bank = self.rom:byte(ptr.bank, header)
        local address = self.rom:word(ptr.bank, header + 3)
        local label = (bank > 0 and address >= 0x4000 and address < 0x8000)
          and attrLabel[bank * 0x10000 + address] or nil
        if label then
          local entry = {
            group = group, number = number, label = label,
            bank = bank, address = address,
            tileset = self.rom:byte(ptr.bank, header + 1),
            environment = self.rom:byte(ptr.bank, header + 2),
            landmark = self.rom:byte(ptr.bank, header + 5),
            -- byte 6 indexes the Music table (map_header's `music` field)
            music = self.rom:byte(ptr.bank, header + 6),
            -- low nibble of byte 7 is the PALETTE_* the map forces; 4 is
            -- PALETTE_DARK, the only value ReplaceTimeOfDayPals answers with
            -- .NeedsFlash (23:$4400)
            palette = self.rom:byte(ptr.bank, header + 7) % 16,
          }
          byGroupNumber[group * 256 + number] = entry
          byLabel[label] = byLabel[label] or entry
        end
      end
    end
  end)
  return byGroupNumber, byLabel
end

-- Numeric tileset id -> "Tileset<Family>", read from the Tilesets table by
-- matching each entry's GFX pointer against the Tileset*GFX symbols.
function RomExtractorGen2:gen2TilesetNames()
  if self._tilesetNames then return self._tilesetNames end
  local byId = {}
  self._tilesetNames = byId

  local table_ = self:symbol("Tilesets")
  if not (table_ and self.rom) then return byId end

  local gfxLabel = {}
  for name, location in pairs(self.symbols or {}) do
    local family = type(name) == "string" and name:match("^(Tileset.+)GFX$")
    if family and type(location) == "table" then
      local bank, address = tonumber(location[1]), tonumber(location[2])
      if bank and address then
        -- Several families share one GFX pointer (Tileset0 and TilesetJohto
        -- both point at 06:$4A00), so a plain `pairs` write let the winner
        -- flip between extractions -- and with it every Johto map's tileset
        -- name.  Prefer the descriptive label over the numbered placeholder,
        -- then the longer name, then alphabetical.
        local key = bank * 0x10000 + address
        local prev = gfxLabel[key]
        local function rank(n)
          return n:match("^Tileset%d+$") and 0 or 1, #n, n
        end
        if not prev then
          gfxLabel[key] = family
        else
          local a1, a2, a3 = rank(family)
          local b1, b2, b3 = rank(prev)
          if a1 > b1 or (a1 == b1 and (a2 > b2 or (a2 == b2 and a3 > b3))) then
            gfxLabel[key] = family
          end
        end
      end
    end
  end

  pcall(function()
    for id = 0, 47 do
      -- the table is indexed directly by tileset id, starting at 0
      local entry = table_.address + id * GEN2_TILESET_ENTRY_BYTES
      if entry + 2 >= 0x8000 then break end
      local bank = self.rom:byte(table_.bank, entry)
      local address = self.rom:word(table_.bank, entry + 1)
      local family = gfxLabel[bank * 0x10000 + address]
      if family then byId[id] = family end
    end
  end)
  return byId
end

-- OverworldSprites (05:47de) is indexed directly by `sprite id - 1`.  Each
-- 6 byte row is `dw gfx pointer / db length / db bank / db type / db palette`.
-- The declared length is what the engine copies into VRAM, not what the sheet
-- occupies in ROM, so the real size comes from the gap to the next sheet.
function RomExtractorGen2:gen2OverworldSprites()
  if self._overworldSprites then return self._overworldSprites end
  local byIndex = {}
  self._overworldSprites = byIndex

  local table_ = self:symbol("OverworldSprites")
  if not (table_ and self.rom) then return byIndex end

  local gfxLabel = {}
  for name, location in pairs(self.symbols or {}) do
    local base = type(name) == "string" and name:match("^(.+)SpriteGFX$")
    if base and type(location) == "table" then
      local bank, address = tonumber(location[1]), tonumber(location[2])
      if bank and address then gfxLabel[bank * 0x10000 + address] = base end
    end
  end

  local rows = {}
  pcall(function()
    -- OverworldSprites is indexed by SPRITE_* - 1 (SPRITE_NONE has no row).
    -- Do NOT stop at the first missing *SpriteGFX symbol: a gap used to drop
    -- every later id (Misty, fruit trees, trophies) out of byIndex, so object
    -- rows fell through to the wrong sheet.  Skip unknown rows and keep going
    -- until we hit a run of empty pointers past the known end of the table.
    local misses = 0
    for slot = 0, 127 do
      local entry = table_.address + slot * GEN2_OVERWORLD_SPRITE_BYTES
      if entry + 5 >= 0x8000 then break end
      local address = self.rom:word(table_.bank, entry)
      local bank = self.rom:byte(table_.bank, entry + 3)
      if address == 0 or bank == 0 then
        misses = misses + 1
        if misses >= 3 then break end
      else
        local base = gfxLabel[bank * 0x10000 + address]
        if not base then
          misses = misses + 1
          if misses >= 8 then break end
        else
          misses = 0
          rows[#rows + 1] = {
            -- sprite constant id = slot + 1 (SPRITE_CHRIS = 1 at slot 0)
            index = slot + 1,
            base = base,
            bank = bank,
            address = address,
            kind = self.rom:byte(table_.bank, entry + 4),
            palette = self.rom:byte(table_.bank, entry + 5) % 8,
          }
        end
      end
    end
  end)

  -- sheet length = distance to the next sheet in the same bank, capped by the
  -- most this sprite kind can possibly use
  local sorted = {}
  for _, row in ipairs(rows) do sorted[#sorted + 1] = row end
  table.sort(sorted, function(a, b)
    if a.bank ~= b.bank then return a.bank < b.bank end
    return a.address < b.address
  end)
  local spanOf = {}
  for i, row in ipairs(sorted) do
    local nextRow = sorted[i + 1]
    if nextRow and nextRow.bank == row.bank and nextRow.address > row.address then
      spanOf[row.bank * 0x10000 + row.address] = nextRow.address - row.address
    end
  end

  for _, row in ipairs(rows) do
    local cap = GEN2_SPRITE_KIND_BYTES[row.kind] or GEN2_SPRITE_WALK_BYTES
    local span = spanOf[row.bank * 0x10000 + row.address] or cap
    local bytes = math.min(span, cap)
    -- 2bpp, 16px wide: one row of pixels is 4 bytes
    local height = math.floor(bytes / 4)
    if height >= 16 then
      byIndex[row.index] = {
        id = GEN2_SPRITE_ID_OVERRIDES[row.index] or gen2SpriteConstant(row.base),
        index = row.index,
        file = "sprites/" .. row.base:lower() .. ".png",
        bank = row.bank,
        address = row.address,
        bytes = height * 4,
        width = 16,
        height = height,
        frames = math.floor(height / 16),
        palette = row.palette,
      }
    end
  end
  return byIndex
end

-- SpriteMons (05:$4669) is one species byte per SPRITE_POKEMON slot, in the
-- order GetMonSprite.Icon indexes them.  Returned 0-based, matching
-- `spriteByte - SPRITE_POKEMON`.
function RomExtractorGen2:gen2SpriteMons()
  if self._spriteMons then return self._spriteMons end
  local mons = {}
  self._spriteMons = mons

  local table_ = self:symbol("SpriteMons")
  if not (table_ and self.rom) then return mons end
  local following = self:symbol("OutdoorSprites")
  local count = GEN2_SPRITE_MONS_COUNT
  if following and following.bank == table_.bank
     and following.address > table_.address then
    count = following.address - table_.address
  end

  pcall(function()
    local raw = self.rom:bytes(table_.bank, table_.address, count)
    for i = 1, count do
      if raw[i] and raw[i] > 0 then mons[i - 1] = raw[i] end
    end
  end)
  return mons
end

-- Walk a map's MapEvents block.  Layout: 2 filler bytes, then each section is
-- a count byte followed by fixed size records.
function RomExtractorGen2:gen2ReadMapEvents(attrBank, attrAddress)
  local bank = self.rom:byte(attrBank, attrAddress + GEN2_ATTR_EVENTS_BANK)
  local address = self.rom:word(attrBank, attrAddress + GEN2_ATTR_EVENTS_POINTER)
  if bank == 0 or address < 0x4000 or address >= 0x8000 then return nil end

  local cursor = address + 2
  local function section(recordBytes)
    local count = self.rom:byte(bank, cursor)
    cursor = cursor + 1
    local rows = {}
    for i = 1, count do
      rows[i] = self.rom:bytes(bank, cursor, recordBytes)
      cursor = cursor + recordBytes
    end
    return rows
  end

  local warps = section(GEN2_WARP_EVENT_BYTES)
  local coords = section(GEN2_COORD_EVENT_BYTES)
  local bgs = section(GEN2_BG_EVENT_BYTES)
  local objects = section(GEN2_OBJECT_EVENT_BYTES)
  return { bank = bank, warps = warps, coords = coords, bgs = bgs, objects = objects }
end

-- FruitTreeItems: one item id per berry tree, indexed by the `fruittree`
-- operand minus one.
function RomExtractorGen2:gen2FruitTreeItems()
  if self._fruitTreeItems then return self._fruitTreeItems end
  local items = {}
  local sym = self:symbol("FruitTreeItems")
  if sym then
    pcall(function()
      items = self.rom:bytes(sym.bank, sym.address, GEN2_FRUIT_TREE_COUNT)
    end)
  end
  self._fruitTreeItems = items
  return items
end

-- InitializeEventsScript is a flat run of `setevent` commands run once on a
-- new game.  An object whose event flag is in this set starts out hidden --
-- that is how the ROM keeps the Elm's Lab officer and the Cherrygrove rival
-- off the map until their scenes fire.
--
-- The run is interrupted by a block of `variablesprite` assignments (the
-- wVariableSprites defaults, which is where Route 36's Sudowoodo comes from).
-- Stopping there dropped every `setevent` after it, so both are read here.
function RomExtractorGen2:gen2InitialEvents()
  if self._initialEvents then return self._initialEvents end
  local events = {}
  local varSprites = {}
  local sym = self:symbol("InitializeEventsScript")
  if sym then
    pcall(function()
      local address = sym.address
      while address < 0x8000 do
        local op = self.rom:byte(sym.bank, address)
        if op == GEN2_SCRIPT_OP_SETEVENT then
          events[self.rom:word(sym.bank, address + 1)] = true
          address = address + 3
        elseif op == 0x32 or op == 0x35 or op == 0x36 then
          address = address + 3   -- clearevent / clearflag / setflag
        elseif op == 0x6C then    -- variablesprite <slot>, <sprite>
          varSprites[self.rom:byte(sym.bank, address + 1)] =
            self.rom:byte(sym.bank, address + 2)
          address = address + 3
        else
          break
        end
      end
    end)
  end
  self._initialEvents = events
  self._initialVarSprites = varSprites
  return events
end

-- wVariableSprites as InitializeEventsScript leaves it on a new game.
function RomExtractorGen2:gen2InitialVarSprites()
  self:gen2InitialEvents()
  return self._initialVarSprites or {}
end

-- Most Gen2 NPC and sign scripts reach their dialogue within a handful of
-- bytes, either directly, through `jumptext`/`writetext`, through the far
-- text jump, or through `jumpstd` into the shared StdScripts table.  Scan for
-- the first pointer whose target decodes as plausible dialogue rather than
-- emulating the whole script VM.
function RomExtractorGen2:gen2BankCount()
  if not self._bankCount then
    self._bankCount = math.floor(#self.rom.data / 0x4000)
  end
  return self._bankCount
end

function RomExtractorGen2:gen2TextBlockAt(bank, address)
  if not (bank and address) then return nil end
  if bank < 1 or bank >= self:gen2BankCount() then return nil end
  if address < 0x4000 or address >= 0x8000 then return nil end
  -- text scripts open with `text` ($00); skip it before sampling
  local start = address
  if self.rom:byte(bank, start) == 0x00 then start = start + 1 end
  local letters, printable = 0, 0
  for i = 0, 31 do
    local b = self.rom:byte(bank, start + i)
    if b == 0x50 or b == 0x57 or b == 0x58 then break end
    printable = printable + 1
    -- $80-$BF letters, $E0-$FF punctuation and digits, $7F space, $4E/$4F/$51/
    -- $55 line breaks and $52-$5D the {PLAYER}/{RIVAL}/{TM} substitutions.
    -- Without the last two groups "{PLAYER}'s House" reads as noise.
    if (b >= 0x80 and b <= 0xBF) or b >= 0xE0 or b == 0x7F
       or b == 0x4E or b == 0x4F or b == 0x51 or b == 0x55
       or (b >= 0x52 and b <= 0x5D) then
      letters = letters + 1
    end
  end
  if printable >= 6 and letters >= printable * 0.85 then return bank, start end
  return nil
end

function RomExtractorGen2:gen2ScriptTextAddress(bank, address, depth)
  if not (bank and address) then return nil end
  if bank < 1 or bank >= self:gen2BankCount() then return nil end
  if address < 0x4000 or address >= 0x8000 then return nil end

  -- signs in particular often point straight at the text block
  local directBank, directAddr = self:gen2TextBlockAt(bank, address)
  if directBank then return directBank, directAddr end

  local std = self:symbol("StdScripts")
  -- A short line like "{PLAYER}'s House" fails the prose test, so remember the
  -- first text operand seen and fall back to it rather than scanning on into
  -- the next script and printing its line instead.
  local fallbackBank, fallbackAddr
  for offset = 0, GEN2_SCRIPT_SCAN_BYTES - 1 do
    local op = self.rom:byte(bank, address + offset)
    if op == GEN2_SCRIPT_OP_FAR_TEXT then
      local far = self.rom:byte(bank, address + offset + 3)
      local target = self.rom:word(bank, address + offset + 1)
      local b, a = self:gen2TextBlockAt(far, target)
      if b then return b, a end
      if not fallbackBank and far >= 1 and far < self:gen2BankCount()
         and target >= 0x4000 and target < 0x8000 then
        fallbackBank, fallbackAddr = far, target
      end
    elseif op == GEN2_SCRIPT_OP_JUMPSTD and std and (depth or 0) < 2 then
      -- StdScripts is a table of `dba` rows: bank byte then address word
      local row = std.address + self.rom:byte(bank, address + offset + 1) * 3
      if row + 2 < 0x8000 then
        local b, a = self:gen2ScriptTextAddress(
          self.rom:byte(std.bank, row),
          self.rom:word(std.bank, row + 1),
          (depth or 0) + 1)
        if b then return b, a end
      end
    elseif GEN2_SCRIPT_TEXT_OPS[op] then
      local target = self.rom:word(bank, address + offset + 1)
      local b, a = self:gen2TextBlockAt(bank, target)
      if b then return b, a end
      if not fallbackBank and target >= 0x4000 and target < 0x8000 then
        fallbackBank, fallbackAddr = bank, target
      end
    end
  end
  return fallbackBank, fallbackAddr
end

function RomExtractorGen2:extractMapsFromRom()
  self:beginStage("Gen2 maps (ROM)")
  local maps = self:readSourceTable("maps")
  if not self.rom then
    self:write("maps", maps)
    self:tick("Gen2 maps (ROM)", 1, 1)
    return
  end

  local keys = {}
  for mapId in pairs(maps) do keys[#keys + 1] = mapId end
  table.sort(keys)

  local mapIndex, headerByLabel = self:gen2MapIndex()
  local tilesetNames = self:gen2TilesetNames()
  local spriteRows = self:gen2OverworldSprites()
  local spriteMons = self:gen2SpriteMons()
  local fruitTreeItems = self:gen2FruitTreeItems()
  local initialEvents = self:gen2InitialEvents()
  local tpOk, textPointers = pcall(function() return self:readSourceTable("text_pointers") end)
  if not tpOk or type(textPointers) ~= "table" then textPointers = {} end
  local thOk, trainerHeaders = pcall(function() return self:readSourceTable("trainer_headers") end)
  if not thOk or type(trainerHeaders) ~= "table" then trainerHeaders = {} end
  local movementTable = self:gen2MovementTable()
  local trainerData = self:gen2Trainers()
  self._gen2ScriptTexts = {}

  local keyByLabel = {}
  for _, mapId in ipairs(keys) do
    local def = maps[mapId]
    if type(def) == "table" then
      local label = (type(def.label) == "string" and def.label)
        or (type(def.source) == "string"
            and def.source:match("^SYMBOL:(.+)_MapAttributes$"))
      if label and not keyByLabel[label] then keyByLabel[label] = mapId end
    end
  end

  local function keyForGroupNumber(group, number)
    local entry = mapIndex[group * 256 + number]
    return entry and keyByLabel[entry.label] or nil
  end

  local loaded, connected, rewired = 0, 0, 0
  local placedObjects, namedObjects, spokenObjects = 0, 0, 0
  local itemObjects, hiddenObjects = 0, 0
  local trainerObjects, serviceObjects = 0, 0
  for index, mapId in ipairs(keys) do
    local def = maps[mapId]
    if type(def) == "table" then
      local source = def.source
      local symbolName = type(source) == "string" and source:match("^SYMBOL:(.+)$") or nil
      local mapLabel = (symbolName and symbolName:match("^(.+)_MapAttributes$"))
        or (type(def.label) == "string" and def.label) or nil
      local header = mapLabel and headerByLabel[mapLabel] or nil
      def.tileset = (header and tilesetNames[header.tileset])
        or inferTilesetId(mapId, def.label)
      def.landmark = header and header.landmark or def.landmark
      -- The map's (group, number) pair from MapGroupPointers.  Warps already
      -- carry it, but a save does too -- wMapGroup/wMapNumber is the ONLY
      -- record a Gold/Silver battery save keeps of where the player was
      -- standing, so src/save_convert/Gen2Save.lua needs the reverse lookup
      -- to put an imported save back on the right map.
      if header then
        def.group = header.group
        def.number = header.number
      end
      -- map header byte 2 (constants/map_data_constants.asm ENVIRONMENT_*):
      -- 1 TOWN, 2 ROUTE, 3 INDOOR, 4 CAVE, 5 ENVIRONMENT_5, 6 GATE,
      -- 7 DUNGEON.  Escape Rope / Dig gate on CAVE and DUNGEON.
      def.environment = header and header.environment or def.environment

      local sym = symbolName and self:symbol(symbolName) or nil
      if sym then
        pcall(function()
          local border = self.rom:byte(sym.bank, sym.address)
          local height = self.rom:byte(sym.bank, sym.address + 1)
          local width = self.rom:byte(sym.bank, sym.address + 2)
          local blocksBank = self.rom:byte(sym.bank, sym.address + 3)
          local blocksPtr = self.rom:word(sym.bank, sym.address + 4)
          if width > 0 and height > 0 then
            local bank = blocksBank > 0 and blocksBank or sym.bank
            def.width = width
            def.height = height
            def.borderBlock = border
            def.blocks = self.rom:bytes(bank, blocksPtr, width * height)
            loaded = loaded + 1
          end
        end)

        pcall(function()
          local flags = self.rom:byte(sym.bank, sym.address + GEN2_ATTR_CONNECTION_FLAGS)
          local cursor = sym.address + GEN2_ATTR_CONNECTION_FLAGS + 1
          local connections = {}
          for _, spec in ipairs(GEN2_CONNECTION_DIRS) do
            local direction, flag = spec[1], spec[2]
            if flags % (flag * 2) >= flag then
              local group = self.rom:byte(sym.bank, cursor)
              local number = self.rom:byte(sym.bank, cursor + 1)
              local yOffset = signedByte(self.rom:byte(sym.bank, cursor + 8))
              local xOffset = signedByte(self.rom:byte(sym.bank, cursor + 9))
              local target = keyForGroupNumber(group, number)
              if target then
                -- offsets are stored in tiles and negated relative to the
                -- neighbour's own view, same convention as Gen1
                local encoded = (direction == "north" or direction == "south")
                  and xOffset or yOffset
                connections[direction] = {
                  map = target,
                  offset = math.floor(-encoded / 2),
                }
                connected = connected + 1
              end
              cursor = cursor + GEN2_CONNECTION_BYTES
            end
          end
          def.connections = connections
        end)

        -- Object and sign events come straight from the ROM: the checked-in
        -- scaffold labels every NPC SPRITE_RED, so without this every
        -- character on every map looked like the player.
        --
        -- Phase 2B + Kanto post-game enrichment (geometry stays 1x1 scaffold):
        --   * sprite id from OverworldSprites + GEN2_SPRITE_ID_OVERRIDES
        --     (Misty, Rocket, Silver/Chris, Copycat, Super Nerd, Gramps,
        --     Cooltrainer, Snorlax, Bill, …)
        --   * eventFlag as EVENT_G2_%04d; set => hidden, $FFFF => always on
        --   * text/script linkage for talk dispatch
        --   * special markers for Move Deleter, Magnet Train, Bill's
        --     grandfather, radio lottery, Name Rater, SnorlaxAwake so the
        --     Machine Part → EXPN → Copycat → Magnet Pass chain and the
        --     Misty Route 25 date → Cerulean gym unlock have named objects
        pcall(function()
          local events = self:gen2ReadMapEvents(sym.bank, sym.address)
          if not events then return end
          local bank = events.bank

          -- Warps as well, so the scaffold can ship an empty list rather than
          -- committed cart geometry.  Destinations stay in the placeholder
          -- MAP_G<group>_N<number> form the rewiring loop below resolves.
          local warps = {}
          for i, row in ipairs(events.warps) do
            warps[i] = {
              y = row[1],
              x = row[2],
              destWarp = math.max(1, row[3]),
              destMap = string.format("MAP_G%02X_N%02X", row[4], row[5]),
            }
          end
          if #warps > 0 then def.warps = warps end

          local objects = {}
          for i, row in ipairs(events.objects) do
            local sprite = spriteRows[row[1]]
            -- GetMonSprite (05:$42CB) decodes the sprite byte, not the sprite
            -- table: $F0 and up index wVariableSprites (the map's own
            -- `variablesprite` callback fills the slot in, which is how Route
            -- 36's Sudowoodo gets its sheet), $E0/$E1 are the day-care mons,
            -- and $80..$DF are SPRITE_POKEMON plus a SpriteMons index -- those
            -- objects walk around as the species' party menu icon.
            local spriteId
            if row[1] >= GEN2_SPRITE_VARS then
              -- $F0+ indexes wVariableSprites.  Copycat and some gym
              -- impersonators are driven this way; still honour an override
              -- if the constant was pinned (e.g. SPRITE_COPYCAT at $FB).
              spriteId = GEN2_SPRITE_ID_OVERRIDES[row[1]]
                or string.format("SPRITE_VAR_%02d", row[1] - GEN2_SPRITE_VARS)
            elseif row[1] == GEN2_SPRITE_BREED_1 then
              spriteId = "SPRITE_MON_BREED_1"
            elseif row[1] == GEN2_SPRITE_BREED_2 then
              spriteId = "SPRITE_MON_BREED_2"
            elseif row[1] >= GEN2_SPRITE_POKEMON then
              local species = spriteMons[row[1] - GEN2_SPRITE_POKEMON]
              spriteId = species and gen2MonSpriteId(species) or "SPRITE_RED"
            else
              -- Prefer explicit Kanto/story overrides, then the OverworldSprites
              -- table id, then GRAMPS only as a last resort so Misty / Rocket /
              -- Super Nerd / etc. never silently become an old man.
              spriteId = GEN2_SPRITE_ID_OVERRIDES[row[1]]
                or (sprite and sprite.id)
                or "SPRITE_GRAMPS"
            end
            local kind = row[8] % 16
            local scriptAddress = row[10] + row[11] * 256
            local eventFlag = row[12] + row[13] * 256
            local textConst = string.format("TEXT_%s_OBJ_%03d", mapId, i)
            local behavior = movementTable[row[4]]
            local movementName = behavior and behavior.movement or "STAY"
            local isBigDoll = type(movementName) == "string"
              and movementName:find("BIG") ~= nil
            local object = {
              id = string.format("%s_OBJ_%03d", mapId, i),
              name = string.format("%s_OBJ_%03d", mapId, i),
              index = i,
              sprite = spriteId,
              y = row[2] - GEN2_EVENT_COORD_BIAS,
              x = row[3] - GEN2_EVENT_COORD_BIAS,
              movement = behavior and behavior.movement or "STAY",
              range = behavior and behavior.range or "ANY_DIR",
              big = isBigDoll or nil,
              source = string.format("ROM_OBJECT_EVENT:%02X", bank),
            }
            -- Visibility rule (engine/overworld/map_objects.asm):
            --   eventFlag == $FFFF  -> always visible (no flag gate)
            --   eventFlag set      -> object is hidden / absent
            --   eventFlag clear    -> object is present
            -- InitializeEventsScript pre-sets a subset so those start hidden.
            if eventFlag ~= GEN2_EVENT_FLAG_NONE and eventFlag ~= 0 then
              object.eventFlag = string.format("EVENT_G2_%04d", eventFlag)
              object.hidden = initialEvents[eventFlag] or nil
            end
            -- MAPOBJECT_TIMEOFDAY: a MORN/DAY/NITE bitmask, $FF for always.
            -- Mom has three rows sharing one event flag and differing only in
            -- this byte, so ignoring it put three of her in the house.
            if row[7] ~= GEN2_TIME_OF_DAY_ANY then
              object.timeOfDay = row[7]
            end

            -- Strength boulders and Rock Smash rocks share SPRITE_BOULDER and
            -- are told apart only by MAPOBJECT_MOVEMENT:
            -- SPRITEMOVEDATA_SMASHABLE_ROCK ($18) vs _STRENGTH_BOULDER ($19).
            if row[4] == 0x18 then
              object.smashable = true
            elseif row[4] == 0x19 then
              object.pushable = true
            end

            -- An item ball's script pointer is a two byte `db item, db quantity`
            -- fragment, and a berry tree's is `fruittree <id>`; neither is
            -- dialogue, so following them printed garbage NPC lines.
            -- Some objects point outside the bank window; a raw read there
            -- asserts and used to abort the whole map, leaving the scaffold's
            -- SPRITE_RED placeholders behind (Cherrygrove, Route 30, ...).
            local script = scriptAddress >= 0x4000 and scriptAddress < 0x7FFF
            local item, quantity, fruitTree
            if script and kind == GEN2_OBJECT_KIND_ITEMBALL then
              item = self.rom:byte(bank, scriptAddress)
              quantity = self.rom:byte(bank, scriptAddress + 1)
            elseif script
                and self.rom:byte(bank, scriptAddress) == GEN2_SCRIPT_OP_FRUITTREE then
              -- a berry tree is scenery that happens to hand out an item; it
              -- must stay on the map once picked, unlike an item ball, and
              -- FruitTreeScript keys its once-a-day flag off the tree id
              fruitTree = self.rom:byte(bank, scriptAddress + 1)
              item = fruitTreeItems[fruitTree]
              quantity = 1
            elseif kind == GEN2_OBJECT_KIND_TRAINER then
              object.trainerObject = true
              -- The script pointer of a trainer object is a 12 byte header:
              -- dw EVENT_BEAT_*, db class, db id, dw seen, dw beaten,
              -- dw win (unused), dw after-battle script.
              if script then
                pcall(function()
                  local beatEvent = self.rom:word(bank, scriptAddress)
                  local group = self.rom:byte(bank, scriptAddress + 2)
                  local trainerId = self.rom:byte(bank, scriptAddress + 3)
                  local classId = trainerData.byGroup[group]
                  local trainer = classId and trainerData.byClass[classId]
                  if not (trainer and trainer.parties[trainerId]) then return end
                  object.trainerClass = classId
                  object.trainerParty = trainerId
                  local header = { range = row[9] }
                  if beatEvent ~= GEN2_EVENT_FLAG_NONE and beatEvent ~= 0 then
                    header.event = string.format("EVENT_G2_%04d", beatEvent)
                  end
                  local function registerText(suffix, textAddress)
                    if not textAddress or textAddress < 0x4000 then return nil end
                    local b, a = self:gen2ScriptTextAddress(bank, textAddress)
                    if not b then return nil end
                    local const = string.format("TEXT_%s_OBJ_%03d_%s", mapId, i, suffix)
                    self._gen2ScriptTexts[const] = { bank = b, address = a }
                    return const
                  end
                  header.battle = registerText("SEEN", self.rom:word(bank, scriptAddress + 4))
                  header.won = registerText("BEATEN", self.rom:word(bank, scriptAddress + 6))
                  header.after = registerText("AFTER", self.rom:word(bank, scriptAddress + 10))
                  trainerHeaders[mapId] = trainerHeaders[mapId] or {}
                  trainerHeaders[mapId][i] = header
                  trainerObjects = trainerObjects + 1
                end)
              end
            elseif script then
              -- Service / post-game special markers.
              -- Pokecenter nurses are `jumpstd pokecenternurse`; mart clerks
              -- run `pokemart` a few opcodes in.  Kanto post-game NPCs (Move
              -- Deleter, Magnet Train, Bill's grandfather, radio lottery,
              -- Snorlax wake check, Name Rater) open with or quickly reach a
              -- `special <index>` — scan a short window and tag the object so
              -- the scaffold surfaces those roles without hand-porting maps.
              pcall(function()
                local marker
                if self.rom:byte(bank, scriptAddress) == GEN2_SCRIPT_OP_JUMPSTD
                   and self.rom:byte(bank, scriptAddress + 1) == GEN2_STD_POKECENTER_NURSE then
                  marker = { nurse = true }
                else
                  local stock = self:gen2MartStock(bank, scriptAddress)
                  if stock then marker = { mart = stock } end
                end

                -- Scan opening bytecode for `special <id>` (op $0F, dw index).
                -- Scripts often do opentext / writetext / special, so look
                -- through a modest window rather than only the first byte.
                if not marker then
                  for off = 0, 24 do
                    local addr = scriptAddress + off
                    if addr + 2 >= 0x8000 then break end
                    if self.rom:byte(bank, addr) == GEN2_SCRIPT_OP_SPECIAL then
                      local specialId = self.rom:word(bank, addr + 1)
                      local role = GEN2_KANTO_SPECIAL_MARKERS[specialId]
                      if role then
                        marker = { special = role, specialId = specialId }
                        object.special = role
                        object.specialId = specialId
                        break
                      end
                    end
                  end
                end

                if not marker then return end
                textPointers[mapId] = textPointers[mapId] or {}
                local entry = textPointers[mapId][textConst] or { text = textConst }
                entry.nurse = marker.nurse
                entry.mart = marker.mart
                if marker.special then
                  entry.special = marker.special
                  entry.specialId = marker.specialId
                end
                textPointers[mapId][textConst] = entry
                serviceObjects = serviceObjects + 1
              end)
            end

            if item and item > 0 then
              object.item = string.format("ITEM_%03d", item)
              object.quantity = quantity
              object.fruitTree = fruitTree
              itemObjects = itemObjects + 1
            else
              object.text = textConst
              local ok, textBank, textAddr = pcall(
                self.gen2ScriptTextAddress, self, bank, scriptAddress)
              if ok and textBank then
                self._gen2ScriptTexts[textConst] = { bank = textBank, address = textAddr }
                textPointers[mapId] = textPointers[mapId] or {}
                local entry = textPointers[mapId][textConst] or {}
                entry.text = textConst
                textPointers[mapId][textConst] = entry
                spokenObjects = spokenObjects + 1
              end
            end

            placedObjects = placedObjects + 1
            if sprite then namedObjects = namedObjects + 1 end
            if object.hidden then hiddenObjects = hiddenObjects + 1 end
            objects[i] = object
          end
          if #objects > 0 then def.objects = objects end

          local signs = {}
          for i, row in ipairs(events.bgs) do
            local textConst = string.format("TEXT_%s_BG_%03d", mapId, i)
            local kind = row[3]
            local ptr = row[4] + row[5] * 256
            signs[i] = {
              id = string.format("%s_BG_%03d", mapId, i),
              -- the bg_event macro stores raw coordinates; only object_event
              -- biases by 4
              y = row[1],
              x = row[2],
              text = textConst,
              source = string.format("ROM_BG_EVENT:%02X", bank),
            }
            -- BGEVENT_ITEM: pointer targets HiddenItem data laid out by the
            -- `hiddenitem` macro as `dwb event_flag, item` — event word FIRST,
            -- then the item byte (wHiddenItemEvent / wHiddenItemID).  Reading
            -- item-then-flag gave the low byte of EVENT_FOUND_MACHINE_PART
            -- (251) as the item and a garbage flag, so the gym water tile
            -- handed out the wrong item and ignored the Power Plant gate.
            if kind == GEN2_BG_EVENT_ITEM then
              local ok, eventFlag, itemId = pcall(function()
                return self.rom:word(bank, ptr), self.rom:byte(bank, ptr + 2)
              end)
              if ok and itemId and itemId > 0 then
                signs[i].item = string.format("ITEM_%03d", itemId)
                if eventFlag and eventFlag ~= 0 and eventFlag ~= 0xFFFF then
                  signs[i].eventFlag = string.format("EVENT_G2_%04d", eventFlag)
                end
                signs[i].hiddenItem = true
                -- do not attach dialogue text; runtime gives the item instead
                signs[i].text = nil
              end
            elseif kind ~= 8 then
              local ok, textBank, textAddr = pcall(
                self.gen2ScriptTextAddress, self, bank, ptr)
              if ok and textBank then
                self._gen2ScriptTexts[textConst] = { bank = textBank, address = textAddr }
                textPointers[mapId] = textPointers[mapId] or {}
                textPointers[mapId][textConst] = { text = textConst }
              end
            end
          end
          if #signs > 0 then def.signs = signs end
        end)
      end

      -- scaffold warps name their destination as a raw MAP_G<group>_N<number>
      -- id; point them at the registry key the runtime actually loads
      for _, warp in ipairs(def.warps or {}) do
        -- Warp id $FF is GSC's "back the way you came" sentinel: EnterMapWarp
        -- swaps in wBackupWarp/MapGroup/MapNumber and ignores the group/map
        -- bytes stored beside it (which just name the map itself).  Every
        -- Pokecenter 2F reaches its own 1F this way.
        if warp.destWarp == 255 then
          warp.destMap = "LAST_WARP"
        else
          local group, number = tostring(warp.destMap or ""):match("^MAP_G(%x%x)_N(%x%x)$")
          if group then
            local target = keyForGroupNumber(tonumber(group, 16), tonumber(number, 16))
            if target then
              warp.destMap = target
              rewired = rewired + 1
            end
          end
        end
      end
    end
    self:tick("Gen2 maps (ROM)", index, #keys)
  end

  maps._romInfo = {
    source = "RomExtractorGen2",
    decodedMapCount = loaded,
    totalMapCount = #keys,
    connectionCount = connected,
    resolvedWarpCount = rewired,
    objectCount = placedObjects,
    resolvedSpriteCount = namedObjects,
    objectTextCount = spokenObjects,
    itemObjectCount = itemObjects,
    hiddenObjectCount = hiddenObjects,
    trainerObjectCount = trainerObjects,
    serviceObjectCount = serviceObjects,
  }
  self:write("maps", maps)
  self:write("text_pointers", textPointers)
  self:write("trainer_headers", trainerHeaders)
end

-- ---------------------------------------------------------------------------
-- Gen2 script disassembler
--
-- Every map header carries a script bank plus pointers to <Map>_MapScripts
-- (scenes and callbacks) and <Map>_MapEvents (coord/bg/object scripts).  All of
-- those are entry points into the same bytecode language, decoded here into an
-- IR that the runtime VM turns into ScriptRunner rows.  applymovement operands
-- point at a *second* bytecode language (MovementPointers, 89 commands) which
-- is decoded alongside it.
-- ---------------------------------------------------------------------------

local GEN2_ATTR_SCRIPTS_POINTER = 7
local GEN2_SCRIPT_MAX_STEPS = 512
local GEN2_MOVEMENT_MAX_STEPS = 128
local GEN2_SCRIPT_POOL_LIMIT = 400000
local GEN2_OBJECT_ROW_KIND = 8
local GEN2_OBJECT_ROW_SCRIPT = 10
-- coord_event: db scene, y, x, unused; dw script; dw 0  (script at offset 4)
local GEN2_COORD_ROW_SCRIPT = 5
local GEN2_TRAINER_HEADER_BYTES = 12
local GEN2_TRAINER_HEADER_AFTER = 10

local function gen2ScriptLabel(bank, address)
  return string.format("S%02X_%04X", bank, address)
end

local function gen2MovementLabel(bank, address)
  return string.format("M%02X_%04X", bank, address)
end

-- $0000-$3FFF is the home bank, which is mapped alongside whichever bank is
-- switched in, so a map's object can point straight at the shared
-- ObjectEvent/BGEvent/CoordinatesEvent scripts there.  Reading those with the
-- map's own bank number asserts, which is how the Burned Tower lost every one
-- of its scripts and 40-odd other objects across the game went mute.
function RomExtractorGen2:gen2Home(bank, address)
  if address and address < 0x4000 then return 0 end
  return bank
end

function RomExtractorGen2:gen2InRom(bank, address)
  if not (bank and address) then return false end
  -- below $0100 is the interrupt/header area, never a script
  if address >= 0x100 and address < 0x4000 then return true end
  if bank < 1 or bank >= self:gen2BankCount() then return false end
  return address >= 0x4000 and address < 0x8000
end

-- writetext/jumptext operands are text scripts, not code.  Register them under
-- a stable const so extractTextFromRom decodes them with everything else.
function RomExtractorGen2:gen2RegisterScriptText(bank, address)
  if not self:gen2InRom(bank, address) then return "" end
  bank = self:gen2Home(bank, address)
  local const = string.format("TEXT_S%02X_%04X", bank, address)
  local known = self._gen2ScriptTexts
  if known and known[const] == nil then
    -- A disassembled writetext operand IS a text script, so take it as given.
    -- gen2TextBlockAt's "looks like prose" test is for scanning unknown script
    -- bytes and rejected 213 real lines here -- Elm's greeting among them --
    -- which then printed as their own constant name.
    local start = address
    local ok, lead = pcall(self.rom.byte, self.rom, bank, address)
    if ok and lead == 0x00 then start = address + 1 end
    known[const] = { bank = bank, address = start }
  end
  return const
end

function RomExtractorGen2:gen2ReadMovement(bank, address, pool)
  if not self:gen2InRom(bank, address) then return "" end
  bank = self:gen2Home(bank, address)
  local label = gen2MovementLabel(bank, address)
  if pool.movements[label] then return label end
  local rows = {}
  pool.movements[label] = rows
  local limit = bank == 0 and 0x4000 or 0x8000
  local pc = address
  for _ = 1, GEN2_MOVEMENT_MAX_STEPS do
    if pc >= limit then break end
    local op = self.rom:byte(bank, pc)
    local name = Gen2ScriptOps.MOVEMENTS[op]
    if not name then break end
    pc = pc + 1
    local row = { name }
    if Gen2ScriptOps.MOVEMENT_ARGS[name] then
      row[2] = self.rom:byte(bank, pc)
      pc = pc + 1
    end
    rows[#rows + 1] = row
    if Gen2ScriptOps.MOVEMENT_TERMINATORS[name] then break end
  end
  return label
end

-- Claim a label and schedule it; `false` marks "queued but not decoded yet" so
-- a script reached twice is only walked once.
function RomExtractorGen2:gen2QueueScript(bank, address, pool)
  if not self:gen2InRom(bank, address) then return nil end
  bank = self:gen2Home(bank, address)
  local label = gen2ScriptLabel(bank, address)
  if pool.scripts[label] == nil then
    pool.scripts[label] = false
    pool.queue[#pool.queue + 1] = { bank, address, label }
  end
  return label
end

-- `elevator <ptr>`: db count, then `db floor, db warp, db group, db number`
-- per floor, $ff terminated (GoldenrodDeptStoreElevatorData).  Resolved here
-- because the row only carries a word, and the bank is the script's.
function RomExtractorGen2:gen2ElevatorFloors(bank, address)
  if type(address) ~= "number" or address < 0x4000 then return nil end
  local ok, floors = pcall(function()
    local count = self.rom:byte(bank, address)
    local out = {}
    for i = 0, math.min(count, 16) - 1 do
      local at = address + 1 + i * 4
      local floor = self.rom:byte(bank, at)
      if floor == 0xFF then break end
      out[#out + 1] = {
        floor = floor,
        warp = self.rom:byte(bank, at + 1),
        group = self.rom:byte(bank, at + 2),
        number = self.rom:byte(bank, at + 3),
      }
    end
    return out
  end)
  return ok and floors and #floors > 0 and floors or nil
end

-- `loadmenu <ptr>`: a MenuHeader -- db flags, menu_coords, dw MenuData, db
-- default -- whose MenuData is db flags, db count, then that many
-- "@"-terminated labels (GoldenrodGameCornerTMVendorMenuHeader).
function RomExtractorGen2:gen2MenuItems(bank, address)
  if type(address) ~= "number" or address < 0x4000 then return nil end
  local ok, items = pcall(function()
    self._menuCharmap = self._menuCharmap or self:readSourceTable("charmap")
    local data = self.rom:word(bank, address + 5)
    if data < 0x4000 then return nil end
    local count = self.rom:byte(bank, data + 1)
    if count < 1 or count > 16 then return nil end
    local out = { default = self.rom:byte(bank, address + 7) }
    local at = data + 2
    for _ = 1, count do
      local text, used = self:decodeGen2TextAt(bank, at, self._menuCharmap)
      -- a header whose MenuData is built at runtime decodes to noise; the
      -- label lengths are the cheapest tell
      if text == "" or #text > 20 then return nil end
      out[#out + 1] = text
      at = at + used
    end
    return out
  end)
  return ok and items and #items > 0 and items or nil
end

-- `writecmdqueue <ptr>` copies one `cmdqueue TYPE, <ptr>` row -- db type, dw
-- address, dw filler -- into wCmdQueue, and the only type any map uses is
-- CMDQUEUE_STONETABLE (2).  That address holds `stonetable <warp id>,
-- <object event id>, <script>` rows (db, db, dw) terminated by -1, which
-- CmdQueue_StoneTable/HandleStoneQueue walk every frame looking for a
-- strength boulder that has come to rest on a pit tile: when the boulder's
-- own object id and the warp under it both match a row, that row's script
-- runs.  It is what drops the four Ice Path B1F boulders through to B2F and
-- what clears Blackthorn Gym's floor.  Without it the boulders just sat on
-- the holes, so the puzzle could not be solved.
--
-- Resolved at import time for the same reason as elevator/loadmenu: the row
-- only carries a word, and the bank is the enclosing script's.
function RomExtractorGen2:gen2StoneTable(bank, address, pool)
  local CMDQUEUE_STONETABLE, MAX_ROWS = 2, 8
  if type(address) ~= "number" or address < 0x4000 then return nil end
  local ok, rows = pcall(function()
    if self.rom:byte(bank, address) ~= CMDQUEUE_STONETABLE then return nil end
    local at = self.rom:word(bank, address + 1)
    if at < 0x4000 then return nil end
    local out = {}
    for _ = 1, MAX_ROWS do
      local warp = self.rom:byte(bank, at)
      if warp == 0xFF then break end
      local script = self:gen2QueueScript(bank, self.rom:word(bank, at + 2), pool)
      if not script then return nil end
      out[#out + 1] = {
        warp = warp,
        object = self.rom:byte(bank, at + 1),
        script = script,
      }
      at = at + 4
    end
    return out
  end)
  return ok and rows and #rows > 0 and rows or nil
end

function RomExtractorGen2:gen2DecodeScript(bank, address, label, pool)
  local rows = {}
  local limit = bank == 0 and 0x4000 or 0x8000
  local pc = address
  for _ = 1, GEN2_SCRIPT_MAX_STEPS do
    if pc >= limit then break end
    local op = self.rom:byte(bank, pc)
    local command = Gen2ScriptOps.COMMANDS[op + 1]
    if not command then
      -- a handful of object "script pointers" in the ROM address text or data;
      -- record the stall instead of walking off into noise
      rows[#rows + 1] = { "unknown", op }
      pool.desyncs = pool.desyncs + 1
      Logger.warn("gen2 script desync: %s (%02X:%04X) opcode %02X",
                  tostring(label), bank, pc, op)
      break
    end
    local name, spec = command[1], command[2]
    local row, argCount = { name }, 0
    pc = pc + 1
    -- Script_givepoke returns before reading the two name pointers when the
    -- trainer byte is zero, which every in-game gift POKeMON is.
    if name == "givepoke" and self.rom:byte(bank, pc + 3) == 0 then
      spec = "bbbb"
    end
    for i = 1, #spec do
      local kind = spec:sub(i, i)
      local value
      if kind == "b" then
        value = self.rom:byte(bank, pc)
      elseif kind == "w" or kind == "d" then
        value = self.rom:word(bank, pc)
      elseif kind == "m" then
        value = self.rom:byte(bank, pc) * 65536
          + self.rom:byte(bank, pc + 1) * 256 + self.rom:byte(bank, pc + 2)
      elseif kind == "p" then
        value = self:gen2QueueScript(bank, self.rom:word(bank, pc), pool)
      elseif kind == "f" then
        value = self:gen2QueueScript(
          self.rom:byte(bank, pc), self.rom:word(bank, pc + 1), pool)
      elseif kind == "t" then
        value = self:gen2RegisterScriptText(bank, self.rom:word(bank, pc))
      elseif kind == "T" then
        value = self:gen2RegisterScriptText(
          self.rom:byte(bank, pc), self.rom:word(bank, pc + 1))
      elseif kind == "M" then
        value = self:gen2ReadMovement(bank, self.rom:word(bank, pc), pool)
      elseif kind == "D" then
        value = self:gen2AsmName(self.rom:byte(bank, pc), self.rom:word(bank, pc + 1))
          or string.format("%02X:%04X",
            self.rom:byte(bank, pc), self.rom:word(bank, pc + 1))
      end
      argCount = argCount + 1
      row[argCount + 1] = value == nil and "" or value
      pc = pc + Gen2ScriptOps.ARG_BYTES[kind]
    end
    if name == "elevator" then
      row[2] = self:gen2ElevatorFloors(bank, row[2]) or row[2]
    elseif name == "loadmenu" then
      row[2] = self:gen2MenuItems(bank, row[2]) or row[2]
    elseif name == "writecmdqueue" then
      row[2] = self:gen2StoneTable(bank, row[2], pool) or row[2]
    end
    rows[#rows + 1] = row
    pool.instructions = pool.instructions + 1
    if Gen2ScriptOps.TERMINATORS[name] then break end
  end
  pool.scripts[label] = rows
end

function RomExtractorGen2:gen2DrainScripts(pool)
  while #pool.queue > 0 do
    local job = table.remove(pool.queue)
    if pool.instructions >= GEN2_SCRIPT_POOL_LIMIT then
      pool.scripts[job[3]] = nil
    else
      local ok = pcall(self.gen2DecodeScript, self, job[1], job[2], job[3], pool)
      if not ok or pool.scripts[job[3]] == false then
        pool.scripts[job[3]] = nil
        pool.failures = pool.failures + 1
      end
    end
  end
end

-- Commands that name a destination map do it as a (group, number) pair.  The
-- runtime only knows registry keys, so fold the pair down to one here: the
-- group slot becomes the key and the number slot is zeroed, which keeps every
-- later argument at the index the command table says it is at.
local GEN2_SCRIPT_MAP_ARG = {
  warp = 2, warpfacing = 3, warpmod = 3, blackoutmod = 2,
  checkmapscene = 2, setmapscene = 2,
}

function RomExtractorGen2:gen2ResolveScriptMapIds(maps, keys, pool)
  local mapIndex = self:gen2MapIndex()
  if not mapIndex then return end
  local keyByLabel = {}
  for _, mapId in ipairs(keys) do
    local def = maps[mapId]
    local label = (type(def.label) == "string" and def.label)
      or (type(def.source) == "string"
          and def.source:match("^SYMBOL:(.+)_MapAttributes$"))
    if label and not keyByLabel[label] then keyByLabel[label] = mapId end
  end
  for _, rows in pairs(pool.scripts) do
    for _, row in ipairs(rows) do
      local slot = GEN2_SCRIPT_MAP_ARG[row[1]]
      if slot and type(row[slot]) == "number" and type(row[slot + 1]) == "number" then
        local entry = mapIndex[row[slot] * 256 + row[slot + 1]]
        local key = entry and keyByLabel[entry.label]
        if key then
          row[slot] = key
          row[slot + 1] = 0
        end
      end
      -- elevator floors name their destination the same (group, number) way
      if row[1] == "elevator" and type(row[2]) == "table" then
        for _, floor in ipairs(row[2]) do
          local entry = mapIndex[(floor.group or 0) * 256 + (floor.number or 0)]
          floor.map = entry and keyByLabel[entry.label] or nil
          floor.group, floor.number = nil, nil
        end
      end
    end
  end

  -- `loadtrainer <group>, <id>` names a trainer by its ROM group byte, but
  -- everything downstream of the extractor speaks the port's trainer class
  -- id, so translate here rather than teaching the runtime the ROM layout.
  local trainerData = self:gen2Trainers()
  local byGroup = trainerData and trainerData.byGroup
  if not byGroup then return end
  for _, rows in pairs(pool.scripts) do
    for _, row in ipairs(rows) do
      if row[1] == "loadtrainer" and type(row[2]) == "number" then
        local classId = byGroup[row[2]]
        if classId then row[2] = classId end
      end
    end
  end
end

-- StdScripts is a dba table of the scripts jumpstd/callstd reach: the
-- Pokecenter nurse, bookshelves, the PC, radio, ...  Nothing else queues them
-- because they hang off no map header, so `jumpstd pokecenternurse` used to
-- lower to a dropped stub and talking to a nurse did nothing.
local GEN2_STD_SCRIPT_COUNT = 46   -- 0..45; row 46 points outside the ROM

function RomExtractorGen2:gen2QueueStdScripts(pool)
  local sym = self:symbol("StdScripts")
  if not sym or not self.rom then return nil end
  local out = {}
  for index = 0, GEN2_STD_SCRIPT_COUNT - 1 do
    pcall(function()
      local row = sym.address + index * 3
      local bank = self.rom:byte(sym.bank, row)
      local address = self.rom:word(sym.bank, row + 1)
      if not self:gen2InRom(bank, address) then return end
      local label = self:gen2QueueScript(bank, address, pool)
      if label then out[index] = label end
    end)
  end
  return next(out) and out or nil
end

-- `SpawnPoints` ([5,$5319], data/maps/spawn_points.asm) is an $FF-terminated
-- table of `db group, map, x, y` rows.  GetWhiteoutSpawn (4:$68EE) matches
-- the recorded spawn map against it and falls back to row 0 -- the bedroom in
-- New Bark Town -- when nothing matches, which is exactly where an unlowered
-- blackoutmod left every blackout.
--
-- EnterMapWarp.SetSpawn (0:$239B) is the other half: stepping out of a map
-- whose tileset is TILESET_POKECENTER (6) into a TOWN/ROUTE map records that
-- outdoor map as the spawn.  Both halves are folded into one table here so
-- the runtime needs no ROM layout knowledge.
local GEN2_SPAWN_ROW_BYTES = 4
local GEN2_SPAWN_MAX = 64
local GEN2_POKECENTER_TILESET = 6

function RomExtractorGen2:gen2SpawnPoints(maps, keys)
  local sym = self:symbol("SpawnPoints")
  if not (sym and self.rom) then return nil end
  local mapIndex, headerByLabel = self:gen2MapIndex()

  local keyByLabel = {}
  for _, mapId in ipairs(keys) do
    local def = maps[mapId]
    local label = (type(def.label) == "string" and def.label)
      or (type(def.source) == "string"
          and def.source:match("^SYMBOL:(.+)_MapAttributes$"))
    if label and not keyByLabel[label] then keyByLabel[label] = mapId end
  end

  local points = {}
  -- the row number is the SPAWN_* constant, which is also the bit
  -- wVisitedSpawns records the Fly destination under (gen2SpawnFlags)
  local order = {}
  for index = 0, GEN2_SPAWN_MAX - 1 do
    local ok, row = pcall(self.rom.bytes, self.rom, sym.bank,
      sym.address + index * GEN2_SPAWN_ROW_BYTES, GEN2_SPAWN_ROW_BYTES)
    if not ok or row[1] == 0xFF then break end
    local entry = mapIndex[row[1] * 256 + row[2]]
    local key = entry and keyByLabel[entry.label]
    if key then
      points[key] = { x = row[3], y = row[4] }
      order[#order + 1] = { index = index, map = key }
    end
  end
  if not next(points) then return nil end

  local centers = {}
  for label, mapId in pairs(keyByLabel) do
    local header = headerByLabel[label]
    if header and header.tileset == GEN2_POKECENTER_TILESET then
      centers[mapId] = true
    end
  end

  return { points = points, centers = centers, order = order }
end

-- R/B keeps a Fly-warp table; GSC does not.  Picking a landmark off the town
-- map sets wDefaultSpawnpoint and FlyFromAnim then warps to that spawn point,
-- so SpawnPoints IS the fly-destination list -- and with field.flyWarps left
-- empty the party menu's FLY had nowhere at all to go.
function RomExtractorGen2:gen2FlyWarps()
  local spawns = self._gen2Spawns
  local points = spawns and spawns.points
  if not points then return nil end
  local out = {}
  for mapId, at in pairs(points) do
    -- a Pokemon Center is a spawn (a blackout lands inside one) but never a
    -- fly destination: the bird sets you down on the town it stands in
    if not (spawns.centers and spawns.centers[mapId]) then
      out[mapId] = { x = at.x, y = at.y }
    end
  end
  return next(out) and out or nil
end

-- The order the FLY cursor walks those destinations in.
--
-- The picker (src/ui/TownMap.lua, LoadTownMap_Fly) cycles `field.flyOrder`
-- filtered to what the player has visited, and Gen 2 shipped none at all --
-- so even with flyWarps populated the cursor had an empty list and the
-- screen fell back to a plain viewer with no cursor and no way to depart.
--
-- LANDMARK order is the right one, and it is the game's own: GSC's Fly
-- cursor moves over the town map from landmark to landmark, and the
-- landmark constants run New Bark east and north through Johto and then on
-- through Kanto -- so walking them in id order walks the map.
function RomExtractorGen2:gen2FlyOrder(warps)
  local defs = self._gen2MapDefs
  if not (warps and defs) then return nil end
  local out = {}
  for mapId in pairs(warps) do out[#out + 1] = mapId end
  if #out == 0 then return nil end
  table.sort(out, function(a, b)
    local la = tonumber((defs[a] or {}).landmark) or 255
    local lb = tonumber((defs[b] or {}).landmark) or 255
    if la ~= lb then return la < lb end
    return a < b
  end)
  return out
end

-- `EngineFlags` ([3,$404D], data/engine_flags.asm) is the `dw address, db mask`
-- table `setflag`/`checkflag`/`checkevent`'s ENGINE_* rows index.  The rows
-- point all over the save's WRAM block -- badges, Pokegear cards, day-care,
-- the Fly points, the daily flags -- and src/script/Gen2ScriptVM.lua only ever
-- sees the ROW NUMBER, which it spells FLAG_G2_nnnn.
--
-- Handing the addresses to src/save_convert/Gen2Save.lua is what lets an
-- imported cartridge save carry every one of those bits under the same id the
-- scripts check, instead of only the handful that had been special-cased.
--
-- The table has no terminator: it simply ends, so a row whose address leaves
-- WRAM or whose mask is not a single bit is the first byte past it.
local GEN2_ENGINE_FLAG_ROW_BYTES = 3
local GEN2_ENGINE_FLAG_MAX = 128
local SINGLE_BIT = {
  [0x01] = 0, [0x02] = 1, [0x04] = 2, [0x08] = 3,
  [0x10] = 4, [0x20] = 5, [0x40] = 6, [0x80] = 7,
}

function RomExtractorGen2:gen2EngineFlags()
  local sym = self:symbol("EngineFlags")
  if not (sym and self.rom) then return nil end
  local out = {}
  for row = 0, GEN2_ENGINE_FLAG_MAX - 1 do
    local ok, bytes = pcall(self.rom.bytes, self.rom, sym.bank,
      sym.address + row * GEN2_ENGINE_FLAG_ROW_BYTES, GEN2_ENGINE_FLAG_ROW_BYTES)
    if not ok then break end
    local address = bytes[1] + bytes[2] * 256
    local bitIndex = SINGLE_BIT[bytes[3]]
    if not bitIndex or address < 0xC000 or address > 0xDFFF then break end
    out[#out + 1] = { row = row, address = address, bit = bitIndex }
  end
  return #out > 0 and out or nil
end

-- wVisitedSpawns ($D9EE, `flag_array NUM_SPAWNS`) is the Fly-destination set:
-- HasVisitedSpawn tests bit [spawn id], and a spawn id IS a SpawnPoints row
-- number.  This project spells the same set save.visited[mapId] (see
-- src/ui/TownMap.lua), so pair each bit with the map its row names.
function RomExtractorGen2:gen2SpawnFlags()
  local spawns = self._gen2Spawns
  local order = spawns and spawns.order
  if not order then return nil end
  local out = {}
  for _, entry in ipairs(order) do
    out[#out + 1] = { bit = entry.index, map = entry.map }
  end
  return #out > 0 and out or nil
end


-- PHONE_* constants index -- the same numbers `addcellnum`,
-- `askforphonenumber` and `checkcellnum` carry.  Each row is twelve bytes:
--
--   db trainer class, trainer id
--   db map group, map number
--   db time-of-day mask, bank, dw script   ; the call they place to you
--   db time-of-day mask, bank, dw script   ; the call you place to them
--
-- GetCallerName (36:$439D) prints the trainer's own name whenever the class
-- byte is nonzero and otherwise indexes NonTrainerCallerNames (36:$43CD) with
-- the trainer id, which is where MOM, BIKE SHOP, BILL and PROF.ELM come from.
-- Only the identity is extracted: the POKeGEAR resolves a trainer contact's
-- name out of the trainer roster (class index -> partyNames[id]) at runtime,
-- so the two never drift apart.
--
-- The two `dba`s are real scripts, walked into the same pool the map scripts
-- use: LoadCallerScript (36:$4215) copies the row into wPhoneCaller and
-- PhoneCall (36:$4298) runs one of them, so a contact you ring plays its
-- `call` script and a contact who rings you plays `receive`.  Without them the
-- POKeGEAR had no dialogue at all to show.
local GEN2_PHONE_ROW_BYTES = 12
local GEN2_PHONE_MAX = 64
local GEN2_NONTRAINER_NAMES = 5
-- db class, id | db group, number | db ptime, bank, dw callee script (the one
-- that runs when YOU ring them) | db ctime, bank, dw caller script (the one
-- that runs when THEY ring you -- ELM's is the same $41E1
-- ElmPhoneCallerScript SpecialPhoneCallList fires, which is what pins the
-- order down).
-- (1-based, as self.rom:bytes hands the row back)
local GEN2_PHONE_CALL_TIME = 5
local GEN2_PHONE_CALL_BANK = 6
local GEN2_PHONE_RECEIVE_TIME = 9
local GEN2_PHONE_RECEIVE_BANK = 10

function RomExtractorGen2:gen2PhoneContacts(pool)
  local sym = self:symbol("PhoneContacts")
  if not (sym and self.rom) then return nil end

  -- the five NonTrainerCallerNames pointers, in PHONE_* id order
  local names = {}
  local nsym = self:symbol("NonTrainerCallerNames")
  if nsym then
    for id = 0, GEN2_NONTRAINER_NAMES - 1 do
      local ok, address = pcall(self.rom.word, self.rom, nsym.bank,
        nsym.address + id * 2)
      if not ok then break end
      local read, raw = pcall(self.rom.bytes, self.rom, nsym.bank, address, 16)
      if read then names[id] = gen2DecodeString(raw, 16) end
    end
  end

  -- SpecialPhoneCallList closes the table; sizing off it beats guessing
  local limit = GEN2_PHONE_MAX
  local stop = self:symbol("SpecialPhoneCallList")
  if stop and stop.bank == sym.bank and stop.address > sym.address then
    limit = math.floor((stop.address - sym.address) / GEN2_PHONE_ROW_BYTES)
  end

  local out = {}
  for id = 0, limit - 1 do
    local ok, row = pcall(self.rom.bytes, self.rom, sym.bank,
      sym.address + id * GEN2_PHONE_ROW_BYTES, GEN2_PHONE_ROW_BYTES)
    if not ok then break end
    local class, trainer = row[1], row[2]
    -- the unused rows are class 0 / id 0, which GetCallerName renders as the
    -- "----------" placeholder; skip them so the POKeGEAR can never list one
    local entry
    if class ~= 0 then
      entry = { class = class, trainer = trainer }
    elseif trainer ~= 0 and names[trainer] then
      entry = { name = names[trainer] }
    end
    if entry and pool then
      entry.receive = self:gen2QueueScript(row[GEN2_PHONE_RECEIVE_BANK],
        row[GEN2_PHONE_RECEIVE_BANK + 1] + row[GEN2_PHONE_RECEIVE_BANK + 2] * 256,
        pool)
      entry.receiveTime = row[GEN2_PHONE_RECEIVE_TIME]
      entry.call = self:gen2QueueScript(row[GEN2_PHONE_CALL_BANK],
        row[GEN2_PHONE_CALL_BANK + 1] + row[GEN2_PHONE_CALL_BANK + 2] * 256,
        pool)
      entry.callTime = row[GEN2_PHONE_CALL_TIME]
    end
    out[id] = entry
  end
  if not next(out) then return nil end
  return out
end

-- `SpecialPhoneCallList` ([36,$45F6] .. PhoneOutOfAreaScript, 48 bytes) is
-- indexed by the SPECIALCALL_* constant `specialphonecall` carries.  Six bytes
-- a row:
--
--   dw Condition   ; SpecialCallOnlyWhenOutside (36:$4190) or
--                  ; SpecialCallWhereverYouAre (36:$419F)
--   db caller      ; a PHONE_* id, so the ringing card shows the right name
--   dba script     ; the caller script, always in bank $41
--
-- CheckSpecialPhoneCall (36:$413E) polls wSpecialPhoneCallID every step and
-- fires the row once its condition passes, which is how Elm rings about the
-- egg after Falkner instead of the moment the gym script ends.  SPECIALCALL_
-- NONE is 0, so the id `specialphonecall` carries is one PAST the row index --
-- 48 bytes hold eight rows but the scripts reach up to `specialphonecall 8`.
-- Store it keyed by that id so the runtime never has to remember the bias.
local GEN2_SPECIAL_CALL_ROW_BYTES = 6
local GEN2_SPECIAL_CALL_CALLER = 3
local GEN2_SPECIAL_CALL_BANK = 4

function RomExtractorGen2:gen2SpecialPhoneCalls(pool)
  local sym = self:symbol("SpecialPhoneCallList")
  local outside = self:symbol("SpecialCallOnlyWhenOutside")
  if not (sym and self.rom) then return nil end

  local limit = 0
  local stop = self:symbol("PhoneOutOfAreaScript")
  if stop and stop.bank == sym.bank and stop.address > sym.address then
    limit = math.floor((stop.address - sym.address) / GEN2_SPECIAL_CALL_ROW_BYTES)
  end

  local out = {}
  for row0 = 0, limit - 1 do
    local ok, row = pcall(self.rom.bytes, self.rom, sym.bank,
      sym.address + row0 * GEN2_SPECIAL_CALL_ROW_BYTES,
      GEN2_SPECIAL_CALL_ROW_BYTES)
    if not ok then break end
    local label = self:gen2QueueScript(row[GEN2_SPECIAL_CALL_BANK],
      row[GEN2_SPECIAL_CALL_BANK + 1] + row[GEN2_SPECIAL_CALL_BANK + 2] * 256,
      pool)
    if label then
      out[row0 + 1] = {
        caller = row[GEN2_SPECIAL_CALL_CALLER],
        script = label,
        outside = outside ~= nil
          and (row[1] + row[2] * 256) == outside.address or nil,
      }
    end
  end
  if not next(out) then return nil end
  return out
end

function RomExtractorGen2:extractMapScripts()  self:beginStage("Gen2 map scripts")
  local maps = self:readSourceTable("maps")
  local keys = {}
  for key, def in pairs(maps) do
    if type(def) == "table" and not key:match("^_") then keys[#keys + 1] = key end
  end
  table.sort(keys)

  local pool = {
    scripts = {}, movements = {}, queue = {},
    instructions = 0, desyncs = 0, failures = 0,
  }
  local out = {
    source = "RomExtractorGen2",
    maps = {},
    scripts = pool.scripts,
    movements = pool.movements,
  }
  local decodedMaps, sceneCount, callbackCount, coordCount, objectCount = 0, 0, 0, 0, 0
  local signCount = 0

  for index, mapId in ipairs(keys) do
    local def = maps[mapId]
    local symbolName = type(def.source) == "string"
      and def.source:match("^SYMBOL:(.+)$") or nil
    local sym = symbolName and self:symbol(symbolName)
    if sym then
      -- A throw anywhere below used to drop the WHOLE map: Burned Tower 1F
      -- lost its rival battle that way.  Log it instead of losing it silently.
      local ok, err = pcall(function()
        local bank = self.rom:byte(sym.bank, sym.address + GEN2_ATTR_EVENTS_BANK)
        local scriptsPtr = self.rom:word(sym.bank, sym.address + GEN2_ATTR_SCRIPTS_POINTER)
        if not self:gen2InRom(bank, scriptsPtr) then return end
        local entry = { bank = bank }

        local cursor = scriptsPtr
        local scenes = self.rom:byte(bank, cursor)
        cursor = cursor + 1
        if scenes > 0 then
          entry.scenes = {}
          for i = 1, scenes do
            entry.scenes[i] =
              self:gen2QueueScript(bank, self.rom:word(bank, cursor), pool) or ""
            cursor = cursor + 4
            sceneCount = sceneCount + 1
          end
        end

        local callbacks = self.rom:byte(bank, cursor)
        cursor = cursor + 1
        if callbacks > 0 then
          entry.callbacks = {}
          for i = 1, callbacks do
            entry.callbacks[i] = {
              type = self.rom:byte(bank, cursor),
              script = self:gen2QueueScript(
                bank, self.rom:word(bank, cursor + 1), pool) or "",
            }
            cursor = cursor + 3
            callbackCount = callbackCount + 1
          end
        end

        local events = self:gen2ReadMapEvents(sym.bank, sym.address)
        if events then
          local objects, afters = {}, {}
          for i, row in ipairs(events.objects) do
            local kind = row[GEN2_OBJECT_ROW_KIND] % (GEN2_OBJECT_KIND_MASK + 1)
            local pointer = row[GEN2_OBJECT_ROW_SCRIPT]
              + row[GEN2_OBJECT_ROW_SCRIPT + 1] * 256
            local label
            if not self:gen2InRom(bank, pointer) then
              label = nil
            else
              -- a pointer below $4000 lives in the always-mapped home bank
              local pbank = self:gen2Home(bank, pointer)
              if kind == GEN2_OBJECT_KIND_TRAINER then
                label = self:gen2QueueScript(
                  pbank, pointer + GEN2_TRAINER_HEADER_BYTES, pool)
                local after = self.rom:word(
                  pbank, pointer + GEN2_TRAINER_HEADER_AFTER)
                afters[i] = self:gen2QueueScript(pbank, after, pool)
              elseif kind ~= GEN2_OBJECT_KIND_ITEMBALL then
                label = self:gen2QueueScript(pbank, pointer, pool)
              end
            end
            if label then
              objects[i] = label
              objectCount = objectCount + 1
            end
          end
          if next(objects) then entry.objects = objects end
          if next(afters) then entry.objectAfter = afters end

          local coords = {}
          for _, row in ipairs(events.coords) do
            local pointer = row[GEN2_COORD_ROW_SCRIPT]
              + row[GEN2_COORD_ROW_SCRIPT + 1] * 256
            local label = self:gen2QueueScript(bank, pointer, pool)
            if label then
              -- CheckCurrentMapCoordEvents subtracts 4 from the player's
              -- position before comparing, so unlike object_events these
              -- coordinates are stored unbiased already
              coords[#coords + 1] = {
                scene = row[1],
                y = row[2],
                x = row[3],
                script = label,
              }
              coordCount = coordCount + 1
            end
          end
          if #coords > 0 then entry.coords = coords end

          -- bg_events are scripts, not text: BGEVENT_READ points at one that
          -- usually opens with `jumptext`, but the interesting ones (the
          -- Ruins of Alph wall patterns, the elevator panels, the Pokemon
          -- Center PCs) do real work.  Extracting only the text pointer left
          -- those signs inert.  BGEVENT_ITEM (7) points at `dwb event_flag, item` (flag word, then item byte)
          -- in the pointer slot and BGEVENT_COPY (8) a RAM address, so both
          -- stay out.
          local signs, signConds = {}, {}
          for i, row in ipairs(events.bgs) do
            local kind = row[3]
            local ptr = row[4] + row[5] * 256
            -- BGEVENT_IFSET (5) / IFNOTSET (6) point at `dw event, dw script`
            -- rather than at the script, so following the pointer straight
            -- disassembled the flag word as opcodes (the Player's House
            -- poster decoded as $CC and died on the first byte).
            if kind == 5 or kind == 6 then
              local event = self.rom:word(bank, ptr)
              ptr = self.rom:word(bank, ptr + 2)
              signConds[i] = { event = event, ifSet = kind == 5 }
            end
            -- BGEVENT_COPY (8) stores a RAM address in the pointer slot
            if kind ~= GEN2_BG_EVENT_ITEM and kind ~= 8 then
              local label = self:gen2QueueScript(bank, ptr, pool)
              if label then
                signs[i] = label
                signCount = signCount + 1
              end
            end
          end
          if next(signs) then entry.signs = signs end
          if next(signConds) then entry.signConds = signConds end
        end

        out.maps[mapId] = entry
        decodedMaps = decodedMaps + 1
      end)
      if not ok then
        Logger.warn("gen2 map scripts: %s dropped (%s)", mapId, tostring(err))
      end
    end
    self:tick("Gen2 map scripts", index, #keys)
  end

  out.stds = self:gen2QueueStdScripts(pool)
  out.marts = self:gen2Marts()
  out.spawns = self:gen2SpawnPoints(maps, keys)
  -- extractField runs after this stage and needs both of these: GSC has no
  -- Fly-warp list of its own, because Fly lands on the SPAWN POINT of the
  -- landmark picked off the town map (FlyFunction -> LoadSpawnPoint), and
  -- the ORDER the picker walks them in is the landmark order the map is
  -- drawn in.
  self._gen2Spawns = out.spawns
  self._gen2MapDefs = maps
  out.phone = self:gen2PhoneContacts(pool)
  out.specialCalls = self:gen2SpecialPhoneCalls(pool)
  -- wVariableSprites as InitializeEventsScript leaves it on a new game, so an
  -- object_event whose sprite byte is $F0 or more resolves before the map's
  -- own `variablesprite` callback has had a chance to run
  out.varSprites = self:gen2InitialVarSprites()
  self:gen2DrainScripts(pool)
  self:gen2ResolveScriptMapIds(maps, keys, pool)
  -- drop labels that were claimed but never decoded
  for label, rows in pairs(pool.scripts) do
    if rows == false then pool.scripts[label] = nil end
  end
  -- gen2RegisterScriptText parks `false` for pointers that did not look like
  -- dialogue; extractTextFromRom only wants the real locations
  for const, location in pairs(self._gen2ScriptTexts or {}) do
    if location == false then self._gen2ScriptTexts[const] = nil end
  end

  local scriptCount, movementCount = 0, 0
  for _ in pairs(pool.scripts) do scriptCount = scriptCount + 1 end
  for _ in pairs(pool.movements) do movementCount = movementCount + 1 end
  out.info = {
    mapCount = decodedMaps,
    sceneCount = sceneCount,
    callbackCount = callbackCount,
    coordCount = coordCount,
    signCount = signCount,
    objectCount = objectCount,
    scriptCount = scriptCount,
    movementCount = movementCount,
    instructionCount = pool.instructions,
    desyncCount = pool.desyncs,
    failureCount = pool.failures,
  }
  Logger.info(string.format(
    "gen2 map scripts: %d maps, %d scripts, %d instructions, %d desyncs",
    decodedMaps, scriptCount, pool.instructions, pool.desyncs))
  self:write("map_scripts", out)
end

-- LZ3 blob at a symbol.  The stream is $FF-terminated, so reading to the
-- end of the bank and letting decompressLz3 stop on its own is safe.
function RomExtractorGen2:gen2Lz(symbolName)
  local sym = self:symbol(symbolName)
  if not sym or not self.rom then return nil end
  local ok, raw = pcall(function()
    return self.rom:bytes(sym.bank, sym.address, 0x8000 - sym.address)
  end)
  if not ok or type(raw) ~= "table" then return nil end
  local out = decompressLz3(raw)
  return #out > 0 and out or nil
end

-- `count` CGB palettes of 4 bgr555 colors, as {r,g,b} in 0..1.  `offset` is
-- for tables indexed by a palette id, such as PredefPals.
function RomExtractorGen2:gen2Palettes(symbolName, count, offset)
  local sym = self:symbol(symbolName)
  if not sym or not self.rom then return nil end
  local ok, raw = pcall(function()
    return self.rom:bytes(sym.bank, sym.address + (offset or 0), count * 8)
  end)
  if not ok or type(raw) ~= "table" then return nil end
  local out = {}
  for index = 0, count - 1 do
    local pal = {}
    for color = 0, 3 do
      local value = (raw[index * 8 + color * 2 + 1] or 0)
        + (raw[index * 8 + color * 2 + 2] or 0) * 256
      pal[color + 1] = {
        (value % 32) / 31,
        (math.floor(value / 32) % 32) / 31,
        (math.floor(value / 1024) % 32) / 31,
      }
    end
    out[index + 1] = pal
  end
  return out
end

-- `count` entries of TrainerPalettes as {r,g,b} quads in 0..1.  The table
-- holds only each class's middle two colours; LoadPalette_White_Col1_Col2_
-- Black is what supplies the white and the black around them.
function RomExtractorGen2:gen2TrainerPalettes(count)
  local sym = self:symbol("TrainerPalettes")
  if not (sym and self.rom) then return nil end
  local ok, raw = pcall(function()
    return self.rom:bytes(sym.bank, sym.address, count * 4)
  end)
  if not ok or type(raw) ~= "table" then return nil end
  local out = {}
  for index = 0, count - 1 do
    local pal = { { 1, 1, 1 }, nil, nil, { 0, 0, 0 } }
    for color = 0, 1 do
      local value = (raw[index * 4 + color * 2 + 1] or 0)
        + (raw[index * 4 + color * 2 + 2] or 0) * 256
      pal[color + 2] = {
        (value % 32) / 31,
        (math.floor(value / 32) % 32) / 31,
        (math.floor(value / 1024) % 32) / 31,
      }
    end
    out[index + 1] = pal
  end
  return out
end

-- The Gold/Silver title screen (engine/movie/title.asm TitleScreen).
-- TitleScreenGFX1 decompresses to vTiles2 ($9000 -> BG ids $00-$6F) and
-- GFX2 to vTiles1 ($8800 -> ids $80-$BB); TitleScreenTilemap is a raw
-- $FF-terminated 32-wide BG map copied straight to $9800.
-- FillTitleScreenPals paints the attrmap: everything palette 0, rows 0-6
-- palette 1 (the logo), row 6 cols 5-14 palette 3 (the VERSION ribbon),
-- and rows 12-16 palette 4 (the cloud band ScrollTitleScreenClouds
-- slides sideways one pixel every eight frames).
--
-- Mascot geometry: OAM y/x are screen + 16 / + 8, and TitleScreen spawns the
-- bird at `depixel 12, 11` = (96, 88), so its origin is screen (80, 80).  The
-- five frames span dy -24..+24 and dx -32..+24, so a 64x64 canvas with the
-- origin at (32, 24) holds every one of them.  `sets` is
-- .Frameset_GSIntroHoOhLugia (data/sprite_anims/framesets.asm) as
-- { oam set, frames } pairs; both versions loop.
local GEN2_MASCOT = {
  w = 64, h = 64, ox = 32, oy = 24, originX = 80, originY = 80,
  sets = {
    gold = { { 1, 10 }, { 2, 9 }, { 3, 10 }, { 4, 10 }, { 3, 9 }, { 5, 10 } },
    silver = {
      { 2, 3 }, { 1, 7 }, { 2, 7 }, { 3, 7 }, { 3, 7 },
      { 4, 7 }, { 4, 7 }, { 3, 7 }, { 2, 3 },
    },
  },
}

function RomExtractorGen2:extractGen2TitleArt()
  local mapSym = self:symbol("TitleScreenTilemap")
  local pals = self:gen2Palettes("GSTitleBGPals", 8)
  local gfx1 = self:gen2Lz("TitleScreenGFX1")
  local gfx2 = self:gen2Lz("TitleScreenGFX2")
  if not (mapSym and pals and gfx1 and gfx2) then return nil end

  local tiles = gen2SplitTiles(gfx1)
  for index, tile in pairs(gen2SplitTiles(gfx2)) do
    tiles[0x80 + index] = tile
  end

  local ok, raw = pcall(function()
    return self.rom:bytes(mapSym.bank, mapSym.address, 32 * 18)
  end)
  if not ok or type(raw) ~= "table" then return nil end

  local function palIndex(row, col)
    if row < 7 and col < 20 then
      if row == 6 and col >= 5 and col < 15 then return 4 end
      return 2
    end
    if row >= 12 and row <= 16 then return 5 end
    return 1
  end

  local image = ImageWriter.blank(256, 144, 1, 1, 1, 1)
  for row = 0, 17 do
    for col = 0, 31 do
      local id = raw[row * 32 + col + 1] or 0x50
      if id == 0xFF then id = 0x50 end
      gen2DrawTile(image, tiles[id], col * 8, row * 8, pals[palIndex(row, col)])
    end
  end
  self:saveImage(image, "title/gen2_title.png")

  local title = {
    layout = "gen2",
    background = {
      path = "assets/generated/title/gen2_title.png",
      width = 256, height = 144,
    },
    -- the LY-override band ScrollTitleScreenClouds animates
    clouds = { y = 96, height = 40, framesPerPixel = 8 },
    copyrightRow = 136,
    music = "Music_TitleScreen",
  }

  -- TitleScreenGFX4 is the OBJ sheet for the version mascot (TitleScreen
  -- decompresses it to vTiles0, so OAM tile ids index it directly).  The
  -- sheet ships raw for mods as well as composed.
  local mon = self:gen2Lz("TitleScreenGFX4")
  if mon and #mon % (8 * 16) == 0 then
    local okMon = pcall(function()
      -- 8 tiles a row, so the sheet is 64 px wide and one pixel tall per
      -- 16-byte tile
      self:saveImage(
        ImageWriter.decode2bpp(mon, 64, #mon / 16, true), "title/gen2_mon.png")
    end)
    if okMon then
      title.monSheet = { path = "assets/generated/title/gen2_mon.png" }
    end
  end

  -- The mascot itself: HO-OH (Gold) / LUGIA (Silver) is an OBJ, not part of
  -- the BG map, which is why rows 7-11 of TitleScreenTilemap are blank.
  -- TitleScreen spawns SPRITE_ANIM_OBJ_GS_INTRO_HO_OH_LUGIA at
  -- `depixel 12, 11` and the wing flap is five OAM sets
  -- (SpriteAnimOAMData.OAMData_GSIntroHoOh1..5): a leading count byte then
  -- `dsprite` rows of `db dy, dx, tile, attr`, drawn as 8x16 objects
  -- (TitleScreen sets B_LCDC_OBJ_SIZE) so each row covers tiles t and t+1.
  local obPals = self:gen2Palettes("GSTitleOBPals", 8)
  if mon and obPals then
    local okMascot, mascot = pcall(self.gen2TitleMascot, self, mon, obPals)
    if okMascot and mascot then title.mascot = mascot end
  end
  return title
end

-- Mascot geometry: OAM y/x are screen + 16 / + 8, and the anim object sits
-- at depixel 12, 11 = (96, 88), so the object's origin is screen (80, 80).
-- The five frames span dy -24..+24 and dx -32..+24, so a 64x64 canvas with
-- the origin at (32, 24) holds every one of them.
-- .Frameset_GSIntroHoOhLugia (data/sprite_anims/framesets.asm), as
-- { oam set, frames } pairs; both versions loop.
function RomExtractorGen2:gen2TitleMascot(mon, obPals)
  local tiles = gen2SplitTiles(mon)
  local frames = {}
  for index = 1, 5 do
    local sym = self:symbol("SpriteAnimOAMData.OAMData_GSIntroHoOh" .. index)
    if not sym then return nil end
    local count = self.rom:byte(sym.bank, sym.address)
    if not count or count == 0 then return nil end
    local raw = self.rom:bytes(sym.bank, sym.address + 1, count * 4)
    local image = ImageWriter.blank(GEN2_MASCOT.w, GEN2_MASCOT.h, 0, 0, 0, 0)
    for obj = 0, count - 1 do
      local dy = raw[obj * 4 + 1] or 0
      local dx = raw[obj * 4 + 2] or 0
      local tile = raw[obj * 4 + 3] or 0
      local attr = raw[obj * 4 + 4] or 0
      if dy > 127 then dy = dy - 256 end
      if dx > 127 then dx = dx - 256 end
      local pal = obPals[(attr % 8) + 1] or obPals[1]
      local xFlip = math.floor(attr / 0x20) % 2 == 1
      local yFlip = math.floor(attr / 0x40) % 2 == 1
      -- 8x16 mode ignores tile bit 0: the pair is (t & $FE, t | $01)
      local top = tiles[tile - tile % 2]
      local bottom = tiles[tile - tile % 2 + 1]
      for half = 0, 1 do
        local pixels = half == 0 and top or bottom
        if pixels then
          for y = 0, 7 do
            for x = 0, 7 do
              local shade = pixels[y * 8 + x + 1]
              -- OBJ colour 0 is transparent on hardware
              if shade ~= 0 then
                local sx = xFlip and (7 - x) or x
                local sy = yFlip and (15 - (half * 8 + y)) or (half * 8 + y)
                local color = pal[shade + 1]
                image:setPixel(GEN2_MASCOT.ox + dx + sx,
                               GEN2_MASCOT.oy + dy + sy,
                               color[1], color[2], color[3], 1)
              end
            end
          end
        end
      end
    end
    local file = "title/gen2_mascot_" .. index .. ".png"
    self:saveImage(image, file)
    frames[index] = "assets/generated/" .. file
  end
  -- frame 1 stays the plain `mascot.path` so an older UI still finds art
  return {
    path = frames[1],
    frames = frames,
    width = GEN2_MASCOT.w, height = GEN2_MASCOT.h,
    x = GEN2_MASCOT.originX - GEN2_MASCOT.ox,
    y = GEN2_MASCOT.originY - GEN2_MASCOT.oy,
    sequence = GEN2_MASCOT.sets[self.version] or GEN2_MASCOT.sets.gold,
  }
end

-- Intro_DrawBackground (bank $39) paints a 16-wide grid of 2x2 metatiles:
-- each tilemap byte indexes a 4-byte NW/NE/SW/SE entry in the scene's Meta
-- table.  The water map is 32 rows tall -- twice the BG map -- because
-- Intro_UpdateTilemapAndBGMap feeds rows in at the top as the camera rises,
-- so the whole column is composed and the scene scrolls through it.
function RomExtractorGen2:gen2IntroBackground(spec)
  local gfx = self:gen2Lz(spec.gfx)
  local metaSym = self:symbol(spec.meta)
  local mapSym = self:symbol(spec.map)
  if not (gfx and metaSym and mapSym) then return nil end
  local rows = spec.rows or 16
  local ok, meta = pcall(function()
    return self.rom:bytes(metaSym.bank, metaSym.address,
      math.min(0x400, 0x8000 - metaSym.address))
  end)
  local okMap, map = pcall(function()
    return self.rom:bytes(mapSym.bank, mapSym.address + (spec.mapOffset or 0),
      rows * 16)
  end)
  if not (ok and okMap) or type(meta) ~= "table" or type(map) ~= "table" then
    return nil
  end

  local tiles = gen2SplitTiles(gfx)
  local height = rows * 16
  local image = ImageWriter.blank(256, height, 1, 1, 1, 1)
  for cell = 0, rows * 16 - 1 do
    local index = map[cell + 1] or 0
    local mx, my = (cell % 16) * 16, math.floor(cell / 16) * 16
    for corner = 0, 3 do
      local id = meta[index * 4 + corner + 1]
      gen2DrawTile(image, id and tiles[id] or nil,
        mx + (corner % 2) * 8, my + math.floor(corner / 2) * 8, spec.pal)
    end
  end
  self:saveImage(image, spec.file)
  return { path = "assets/generated/" .. spec.file, width = 256, height = height }
end

-- SpriteAnimOAMData (data/sprite_anims/oam.asm) is a `table_width 3` list,
-- one row per SPRITE_ANIM_OAMSET_* constant: `db vtile offset` then
-- `dw pointer`.  The vtile offset is added to every tile id in the block it
-- points at, which is how ONE 4x4 block serves as Jigglypuff ($00/$04/$08)
-- and as Pikachu ($40/$44/$48/$4c) out of the same 16-wide OBJ sheet -- the
-- offset is the only thing that tells the two apart.
--
-- The block itself is a count byte then `db dy, dx, tile, attr` rows
-- (`dbsprite` writes y before x).  The intro never sets B_LCDC_OBJ_SIZE, so
-- unlike the title mascot these are plain 8x8 objects.
function RomExtractorGen2:gen2OamSet(index)
  local sym = self:symbol("SpriteAnimOAMData")
  if not (sym and self.rom) then return nil end
  local ok, head = pcall(function()
    return self.rom:bytes(sym.bank, sym.address + index * 3, 3)
  end)
  if not ok or type(head) ~= "table" then return nil end
  local address = (head[2] or 0) + (head[3] or 0) * 256
  if address < 0x4000 or address >= 0x8000 then return nil end
  local okBlock, objs = pcall(function()
    local count = self.rom:byte(sym.bank, address)
    if not count or count == 0 or count > 40 then return nil end
    local raw = self.rom:bytes(sym.bank, address + 1, count * 4)
    local list = {}
    for obj = 0, count - 1 do
      local dy = raw[obj * 4 + 1] or 0
      local dx = raw[obj * 4 + 2] or 0
      if dy > 127 then dy = dy - 256 end
      if dx > 127 then dx = dx - 256 end
      list[obj + 1] = { dy, dx, raw[obj * 4 + 3] or 0, raw[obj * 4 + 4] or 0 }
    end
    return list
  end)
  if not okBlock or type(objs) ~= "table" then return nil end
  return { vtile = head[1] or 0, objs = objs }
end

-- The intro's OBJ cast, as `{ oam set, frames [, x-flipped] }` steps taken
-- from data/sprite_anims/framesets.asm.  A frameset's X-flip mirrors the
-- WHOLE object (AddSpriteOAM negates each offset as well as setting the
-- attribute bit), which is why RedWalk can flip its walk cycle -- so a
-- flipped step here is composed and then mirrored about the origin.
--
-- Palettes: the ocean scene loads _CGB_GSIntro.ShellderLaprasOBPals (two --
-- Shellder on 0, Magikarp on 1), the meadow loads the single predef pal
-- PREDEFPAL_GS_INTRO_JIGGLYPUFF_PIKACHU_OB ($39, white/yellow/pink/black)
-- that both mons share.  Lapras is on OB pal 0 too, but by the time it
-- swims in, Intro_LoadMagikarpPalettes has overwritten pal 0 with what the
-- source calls the "Magikarp" OB palette -- white/cream/blue/black, which
-- is Lapras's own.  Reading it off pal 0 as loaded at scene start gives a
-- red Lapras with a grey shell.
RomExtractorGen2.GEN2_INTRO_SCENES = {
  {
    key = "water", gfx = "Intro_WaterGFX2",
    palSymbol = "_CGB_GSIntro.ShellderLaprasOBPals", palCount = 2,
    actors = {
      { name = "shellder", steps = { { 4, 8 }, { 5, 8 } } },
      { name = "magikarp", steps = { { 6, 1, true }, { 7, 1, true } } },
      { name = "lapras", steps = { { 9, 7 }, { 10, 7 }, { 11, 7 }, { 9, 7 } },
        palSymbol = "Intro_LoadMagikarpPalettes.MagikarpOBPal", palCount = 1 },
    },
  },
  {
    key = "grass", gfx = "Intro_GrassGFX2",
    palSymbol = "PredefPals", palCount = 1, palOffset = 0x39 * 8,
    actors = {
      { name = "jigglypuff",
        steps = { { 14, 25, true }, { 16, 9 }, { 14, 25 }, { 16, 9 } } },
      { name = "pikachu", steps = { { 17, 4 }, { 18, 5 }, { 20, 4 } } },
      { name = "pikachuTail",
        steps = { { 21, 3 }, { 22, 3 }, { 23, 3 }, { 22, 3 } } },
      { name = "note", steps = { { 12, 8 } } },
    },
  },
}

function RomExtractorGen2:gen2IntroActors(scene)
  local gfx = self:gen2Lz(scene.gfx)
  local shared = self:gen2Palettes(scene.palSymbol, scene.palCount,
    scene.palOffset)
  if not (gfx and shared) then return nil end
  local tiles = gen2SplitTiles(gfx)
  local out = {}
  for _, actor in ipairs(scene.actors) do
    local pals = shared
    if actor.palSymbol then
      pals = self:gen2Palettes(actor.palSymbol, actor.palCount or 1,
        actor.palOffset)
    end
    local sets, bx, minY, maxY = {}, 8, 0, 8
    for _, step in ipairs(actor.steps) do
      local set = sets[step[1]] or self:gen2OamSet(step[1])
      if not set then sets = nil break end
      sets[step[1]] = set
      for _, obj in ipairs(set.objs) do
        -- the canvas is symmetric in x so a mirrored step still fits
        bx = math.max(bx, obj[2] + 8, -obj[2])
        minY = math.min(minY, obj[1])
        maxY = math.max(maxY, obj[1] + 8)
      end
    end
    if sets and pals then
      local w, h = bx * 2, maxY - minY
      local ox, oy = bx, -minY
      local frames, sequence = {}, {}
      for index, step in ipairs(actor.steps) do
        local image = ImageWriter.blank(w, h, 0, 0, 0, 0)
        local set = sets[step[1]]
        for _, obj in ipairs(set.objs) do
          local dy, dx, tile, attr = obj[1], obj[2], obj[3], obj[4]
          local pixels = tiles[(tile + set.vtile) % 0x100]
          local pal = pals[(attr % 8) + 1] or pals[1]
          if pixels and pal then
            local xFlip = math.floor(attr / 0x20) % 2 == 1
            local yFlip = math.floor(attr / 0x40) % 2 == 1
            for y = 0, 7 do
              for x = 0, 7 do
                local shade = pixels[y * 8 + x + 1]
                -- OBJ colour 0 is transparent on hardware
                if shade ~= 0 then
                  local px = ox + dx + (xFlip and (7 - x) or x)
                  if step[3] then px = w - 1 - px end
                  local color = pal[shade + 1]
                  image:setPixel(px, oy + dy + (yFlip and (7 - y) or y),
                    color[1], color[2], color[3], 1)
                end
              end
            end
          end
        end
        local file = "intro/gen2_" .. scene.key .. "_" .. actor.name
          .. "_" .. index .. ".png"
        self:saveImage(image, file)
        frames[index] = "assets/generated/" .. file
        sequence[index] = { index, step[2] }
      end
      out[actor.name] = {
        path = frames[1], frames = frames, sequence = sequence,
        width = w, height = h, originX = ox, originY = oy,
      }
    end
  end
  return next(out) and out or nil
end

-- Raw (uncompressed) 2bpp sheet at a symbol, sized in tiles.
function RomExtractorGen2:gen2RawSheet(symbolName, tilesWide, tilesHigh, file, columnMajor)
  local sym = self:symbol(symbolName)
  if not sym or not self.rom then return nil end
  local ok, raw = pcall(function()
    return self.rom:bytes(sym.bank, sym.address, tilesWide * tilesHigh * 16)
  end)
  if not ok or type(raw) ~= "table" then return nil end
  if columnMajor then
    raw = ImageWriter.columnsToRows(raw, tilesWide, tilesHigh, 16)
  end
  local okSave = pcall(function()
    self:saveImage(
      ImageWriter.decode2bpp(raw, tilesWide * 8, tilesHigh * 8, true), file)
  end)
  if not okSave then return nil end
  return { path = "assets/generated/" .. file,
           width = tilesWide * 8, height = tilesHigh * 8 }
end

-- 1bpp tile: one byte per row, set bits are the darkest shade (that is what
-- FarCopyBytesDouble makes of them by writing the byte to both planes).
local function gen2Tile1bpp(raw, offset)
  local pixels = {}
  for y = 0, 7 do
    local row = raw[offset + y + 1] or 0
    for x = 0, 7 do
      pixels[y * 8 + x + 1] = math.floor(row / 2 ^ (7 - x)) % 2 * 3
    end
  end
  return pixels
end

local GEN2_DMG_PAL = {
  { 1, 1, 1 }, { 2 / 3, 2 / 3, 2 / 3 }, { 1 / 3, 1 / 3, 1 / 3 }, { 0, 0, 0 },
}

-- Both splash screens build their text out of a tile-id string laid over a
-- cleared (white) tilemap, so compose the same rows here instead of dumping
-- the sheet in ROM order.
function RomExtractorGen2:gen2TextSheet(tiles, rows, file)
  local widest = 0
  for _, row in ipairs(rows) do widest = math.max(widest, #row) end
  if widest == 0 then return nil end
  local image = ImageWriter.blank(widest * 8, #rows * 8, 1, 1, 1, 1)
  for y, row in ipairs(rows) do
    for x, index in ipairs(row) do
      gen2DrawTile(image, tiles[index], (x - 1) * 8, (y - 1) * 8, GEN2_DMG_PAL)
    end
  end
  self:saveImage(image, file)
  return { path = "assets/generated/" .. file,
           width = widest * 8, height = #rows * 8 }
end

-- Copyright (bank 1, $64F8): 30 raw 2bpp tiles at $9600, then three tilemap
-- rows of tile ids.  Ids are relative to $60.
local GEN2_COPYRIGHT_ROWS = {
  { 0x60, 0x61, 0x62, 0x63, 0x7A, 0x7B, 0x7C, 0x7D,
    0x65, 0x66, 0x67, 0x68, 0x69, 0x6A },
  { 0x60, 0x61, 0x62, 0x63, 0x7A, 0x7B, 0x7C, 0x7D,
    0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x71, 0x72 },
  { 0x60, 0x61, 0x62, 0x63, 0x7A, 0x7B, 0x7C, 0x7D,
    0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x71, 0x72 },
}
-- GameFreakPresents_PlaceGameFreak / _PlacePresents (bank $39, $4ADF/$4AF4).
-- Ids are relative to $80.
local GEN2_GAMEFREAK_ROW =
  { 0x80, 0x81, 0x82, 0x83, 0x8D, 0x84, 0x85, 0x83, 0x81, 0x86 }
local GEN2_PRESENTS_ROW = { 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C }

local function gen2Rebase(row, base)
  local out = {}
  for index, id in ipairs(row) do out[index] = id - base end
  return out
end

-- GoldSilverIntro's attract movie (bank $39): the Nintendo copyright, the
-- GAME FREAK presents splash, then the ocean and grass scenes the starters
-- appear over.
function RomExtractorGen2:extractGen2IntroArt()
  local intro = { layout = "gen2" }

  local copySym = self:symbol("CopyrightGFX")
  if copySym then
    local ok, raw = pcall(function()
      return self.rom:bytes(copySym.bank, copySym.address, 30 * 16)
    end)
    if ok and type(raw) == "table" then
      local tiles = gen2SplitTiles(raw)
      local rows = {}
      for index, row in ipairs(GEN2_COPYRIGHT_ROWS) do
        rows[index] = gen2Rebase(row, 0x60)
      end
      intro.copyright = self:gen2TextSheet(tiles, rows, "intro/gen2_copyright.png")
    end
  end

  local logoSym = self:symbol("GameFreakLogoGFX")
  if logoSym then
    local ok, raw = pcall(function()
      return self.rom:bytes(logoSym.bank, logoSym.address, 28 * 8)
    end)
    if ok and type(raw) == "table" then
      local tiles = {}
      for index = 0, 27 do tiles[index] = gen2Tile1bpp(raw, index * 8) end
      intro.gamefreak = self:gen2TextSheet(tiles,
        { gen2Rebase(GEN2_GAMEFREAK_ROW, 0x80) }, "intro/gen2_gamefreak.png")
      intro.presents = self:gen2TextSheet(tiles,
        { gen2Rebase(GEN2_PRESENTS_ROW, 0x80) }, "intro/gen2_presents.png")
    end
  end

  intro.stars = self:gen2RawSheet("GameFreakLogoStarsGFX", 5, 1,
    "intro/gen2_stars.png")
  -- IntroScene1 starts the camera 15 metatile rows down the water column
  -- (`Intro_WaterTilemap + 15 tiles`) and rises to row 0.
  intro.water = self:gen2IntroBackground({
    gfx = "Intro_WaterGFX1", meta = "Intro_WaterMeta",
    map = "Intro_WaterTilemap", mapOffset = 0, rows = 32,
    pal = GEN2_INTRO_WATER_PAL, file = "intro/gen2_water.png",
  })
  if intro.water then intro.waterStartY = 15 * 16 end
  intro.grass = self:gen2IntroBackground({
    gfx = "Intro_GrassGFX1", meta = "Intro_GrassMeta",
    map = "Intro_GrassTilemap", mapOffset = 0, rows = 16,
    pal = GEN2_INTRO_GRASS_PAL, file = "intro/gen2_grass.png",
  })
  -- The OBJ cast: Shellder/Magikarp/Lapras over the ocean and
  -- Jigglypuff/Pikachu/the note over the meadow, composed from
  -- Intro_WaterGFX2 / Intro_GrassGFX2 (both decompressed to vTiles0, so OAM
  -- tile ids index them directly once the OAM set's vtile offset is added).
  intro.actors = {}
  for _, scene in ipairs(RomExtractorGen2.GEN2_INTRO_SCENES) do
    local ok, actors = pcall(self.gen2IntroActors, self, scene)
    if ok and actors then
      for name, actor in pairs(actors) do intro.actors[name] = actor end
    end
  end
  if not next(intro.actors) then intro.actors = nil end
  -- Intro_ChikoritaAppears / _CyndaquilAppears / _TotodileAppears
  intro.starters = { "SPECIES_152", "SPECIES_155", "SPECIES_158" }
  if not (intro.water or intro.grass) then return nil end
  return intro
end

-- POKéGEAR town map.  FillTownMap copies a flat run of tile ids into the
-- screen tilemap until $FF, TownMapPals gives every tile a palette from a
-- nibble table, and TownMapGFX is 48 raw tiles.  Landmark rows are
-- `db x, y, dw name` (GetLandmarkCoords / GetLandmarkName).
local GEN2_TOWN_MAP_WIDTH = 20
local GEN2_TOWN_MAP_HEIGHT = 18
local GEN2_TOWN_MAP_TILES = 48
local GEN2_TOWN_MAP_PAL_LIMIT = 0x60   -- TownMapPals: above this, palette 0
local GEN2_TOWN_MAP_PALETTES = 6
local GEN2_LANDMARK_BYTES = 4
local GEN2_LANDMARK_COUNT = 95

function RomExtractorGen2:gen2TownMapPalettes()
  local sym = self:symbol("PokegearPals")
  local pals = {}
  if not (sym and self.rom) then return pals end
  pcall(function()
    for p = 0, GEN2_TOWN_MAP_PALETTES - 1 do
      local colors = {}
      for c = 0, 3 do
        local raw = self.rom:word(sym.bank, sym.address + (p * 4 + c) * 2)
        colors[c] = {
          (raw % 32) / 31,
          (math.floor(raw / 32) % 32) / 31,
          (math.floor(raw / 1024) % 32) / 31,
        }
      end
      pals[p] = colors
    end
  end)
  return pals
end

function RomExtractorGen2:gen2TownMapImage(mapSymbol, relative)
  local map = self:symbol(mapSymbol)
  local gfx = self:symbol("TownMapGFX")
  if not (map and gfx and self.rom) then return nil end
  local palMap = self:symbol("TownMapPals.PalMap")
  local ok = pcall(function()
    local tiles = self.rom:bytes(gfx.bank, gfx.address, GEN2_TOWN_MAP_TILES * 16)
    local nibbles = palMap and self.rom:bytes(palMap.bank, palMap.address,
                                              GEN2_TOWN_MAP_PAL_LIMIT / 2)
    local pals = self:gen2TownMapPalettes()
    local cells = self.rom:bytes(map.bank, map.address,
                                 GEN2_TOWN_MAP_WIDTH * GEN2_TOWN_MAP_HEIGHT)
    local image = love.image.newImageData(GEN2_TOWN_MAP_WIDTH * 8,
                                          GEN2_TOWN_MAP_HEIGHT * 8)
    for cell = 0, GEN2_TOWN_MAP_WIDTH * GEN2_TOWN_MAP_HEIGHT - 1 do
      local tile = cells[cell + 1] or 0
      local palIndex = 0
      if nibbles and tile < GEN2_TOWN_MAP_PAL_LIMIT then
        local packed = nibbles[math.floor(tile / 2) + 1] or 0
        palIndex = (tile % 2 == 0) and (packed % 8)
          or (math.floor(packed / 16) % 8)
      end
      local colors = pals[palIndex] or pals[0]
      local px = (cell % GEN2_TOWN_MAP_WIDTH) * 8
      local py = math.floor(cell / GEN2_TOWN_MAP_WIDTH) * 8
      local base = (tile % GEN2_TOWN_MAP_TILES) * 16
      for y = 0, 7 do
        local low = tiles[base + y * 2 + 1] or 0
        local high = tiles[base + y * 2 + 2] or 0
        for x = 0, 7 do
          local divisor = 2 ^ (7 - x)
          local shade = math.floor(high / divisor) % 2 * 2
            + math.floor(low / divisor) % 2
          local c = colors and colors[shade] or { 0, 0, 0 }
          image:setPixel(px + x, py + y, c[1], c[2], c[3], 1)
        end
      end
    end
    self:saveImage(image, relative)
  end)
  return ok and ("assets/generated/" .. relative) or nil
end

function RomExtractorGen2:gen2Landmarks()
  local sym = self:symbol("Landmarks")
  if not (sym and self.rom) then return nil end
  local charmap = self:readSourceTable("charmap")
  local out = {}
  for id = 0, GEN2_LANDMARK_COUNT - 1 do
    pcall(function()
      local row = sym.address + id * GEN2_LANDMARK_BYTES
      local name = self:decodeGen2TextAt(sym.bank,
        self.rom:word(sym.bank, row + 2), charmap)
      -- $1F is the landmark line break (TownMap_ConvertLineBreakCharacters)
      name = name:gsub("{BYTE:1F}", "\n")
      out[id] = {
        x = self.rom:byte(sym.bank, row),
        y = self.rom:byte(sym.bank, row + 1),
        name = name ~= "" and name or nil,
      }
    end)
  end
  return next(out) and out or nil
end

function RomExtractorGen2:gen2TownMap()
  local johto = self:gen2TownMapImage("JohtoMap", "ui/town_map_johto.png")
  if not johto then return nil end
  local out = {
    johto = johto,
    kanto = self:gen2TownMapImage("KantoMap", "ui/town_map_kanto.png"),
    landmarks = self:gen2Landmarks(),
  }
  -- Player "you are here" icon: ChrisSpriteGFX facing-down (4 tiles = 16x16)
  -- tinted with PAL_OW_RED so it is not a greyscale silhouette on the map.
  pcall(function()
    local sym = self:symbol("ChrisSpriteGFX")
    if not (sym and self.rom) then return end
    local raw = self.rom:bytes(sym.bank, sym.address, 4 * 16)
    -- MapObjectPals red (0-31 RGB → 0-1): light, skin, red, black
    local redPal = {
      { 28/31, 31/31, 16/31 },
      { 31/31, 19/31, 10/31 },
      { 31/31,  7/31,  1/31 },
      { 0, 0, 0 },
    }
    local image
    if ImageWriter.decode2bppColor then
      image = ImageWriter.matteColor0(
        ImageWriter.decode2bppColor(raw, 16, 16, redPal, true))
    else
      image = ImageWriter.matteColor0(ImageWriter.decode2bpp(raw, 16, 16, true))
      if ImageWriter.recolorShades then
        image = ImageWriter.recolorShades(image, redPal)
      end
    end
    self:saveImage(image, "ui/town_map_player.png")
    out.playerIcon = "assets/generated/ui/town_map_player.png"
  end)
  -- Nest / fly cursor from PokegearSpritesGFX when present (LZ3).
  pcall(function()
    local pixels = self:gen2Lz("PokegearSpritesGFX")
    if not pixels or #pixels < 16 then return end
    -- First 4 tiles often form the blinking map cursor frame (16x16).
    local n = math.min(#pixels, 4 * 16)
    local slice = {}
    for i = 1, n do slice[i] = pixels[i] end
    while #slice < 4 * 16 do slice[#slice + 1] = 0 end
    local image = ImageWriter.matteColor0(ImageWriter.decode2bpp(slice, 16, 16, true))
    self:saveImage(image, "ui/town_map_cursor.png")
    out.cursor = "assets/generated/ui/town_map_cursor.png"
  end)
  -- Nest icon (dex AREA) if a dedicated symbol exists
  pcall(function()
    local pixels = self:gen2Lz("TownMapCursorGFX") or self:gen2Lz("PokegearSpritesGFX")
    if pixels and #pixels >= 16 then
      local slice = {}
      for i = 1, math.min(#pixels, 2 * 16) do slice[i] = pixels[i] end
      while #slice < 16 do slice[#slice + 1] = 0 end
      local image = ImageWriter.matteColor0(ImageWriter.decode2bpp(slice, 8, 8, true))
      self:saveImage(image, "ui/town_map_nest.png")
      out.nest = { path = "assets/generated/ui/town_map_nest.png" }
    end
  end)
  return out
end

-- Gold/Silver pokegear RLE tilemaps (tile, count)* terminated by $FF.
-- Used when the linker symbols ClockTilemapRLE etc. are not in the symbol
-- table; byte-identical to gfx/pokegear/*.tilemap.rle in pret/pokegold.
-- Gold/Silver pokegear RLE tilemaps (tile_id, count)* terminated by $FF.
local GEN2_POKEGEAR_RLE = {
  CLOCK = {
     79,   8,  79,   4,  48,   1, 127,   6,  49,   1,  79,   8,  79,   4, 127,   8,
     79,  12,  50,   1, 127,   6,  51,   1,  79,  20,  79,   2,   6,   1,   7,  14,
     23,   1,  79,   2,  79,   2,  22,   1, 127,  14,  22,   1,  79,   2,  79,   2,
     22,   1, 127,  14,  22,   1,  79,   2,  79,   2,  22,   1, 127,  14,  22,   1,
     79,   2,  79,   2,  22,   1, 127,  14,  22,   1,  79,   2,  79,   2,  22,   1,
    127,  14,  22,   1,  79,   2,  79,   2,  38,   1,   7,  14,  39,   1,  79,   2,
     79,  20, 255,
  },
  PHONE = {
     79,   8,   6,   1,   7,  10,  23,   1,  79,   8,  22,   1,  79,  10,  22,   1,
      6,   1,   7,   7,  39,   1,  79,  10,  22,   1,  22,   1, 127,  18,  22,   1,
     22,   1, 127,  18,  22,   1,  22,   1, 127,  18,  22,   1,  22,   1, 127,  18,
     22,   1,  22,   1, 127,  18,  22,   1,  22,   1, 127,  18,  22,   1,  22,   1,
    127,  18,  22,   1,  22,   1, 127,  18,  22,   1,  22,   1, 127,  18,  22,   1,
    255,
  },
  RADIO = {
     79,   8,   6,   1,   7,  10,  23,   1,  79,   8,  22,   1,  79,   2,  55,   1,
     79,   1,  56,   1,  57,   1,  79,   1,  58,   1,  79,   2,  22,   1,  72,   1,
     74,   7,  22,   1,  59,  10,  22,   1,  76,   1,  78,   7,  22,   1,  79,  10,
     22,   1,  76,   1,  78,   7,  22,   1,  54,   1, 127,   1,  88,   1,  89,   1,
     90,   1,  91,   1,  92,   1,  93,   1, 127,   1,  53,   1,  22,   1,  76,   1,
     78,   7,  38,   1,   7,  10,  39,   1,  76,   1,  78,  18,  77,   1,  76,   1,
     78,  18,  77,   1,  76,   1, 127,  18,  77,   1,  76,   1, 127,  18,  77,   1,
     76,   1, 127,  18,  77,   1,  76,   1,  78,  18,  77,   1, 255,
  },
}

-- Border palette from gfx/pokegear/pokegear.pal (0-31 RGB → 0-1)
local GEN2_POKEGEAR_BORDER_PAL = {
  [0] = { 28/31, 31/31, 20/31 },
  [1] = { 21/31, 21/31, 21/31 },
  [2] = { 13/31, 13/31, 13/31 },
  [3] = { 0, 0, 0 },
}

-- Authentic POKéGEAR cards: decompress TownMapGFX ($00+) + PokegearGFX ($30+),
-- apply RLE tilemaps, paint with PokegearPals / border palette.
function RomExtractorGen2:gen2Pokegear()
  local pals = self:gen2TownMapPalettes()
  local out = { palettes = {}, cards = {} }
  for index, colors in pairs(pals) do
    local entry = {}
    for c = 0, 3 do
      local rgb = colors[c] or { 0, 0, 0 }
      entry[c + 1] = {
        math.floor(rgb[1] * 255 + 0.5),
        math.floor(rgb[2] * 255 + 0.5),
        math.floor(rgb[3] * 255 + 0.5),
      }
    end
    out.palettes[index] = entry
  end

  local function loadTiles(symbolName, baseId)
    local bank = {}
    local pixels = self:gen2Lz(symbolName)
    if not pixels or #pixels < 16 then
      local sym = self:symbol(symbolName)
      if sym and self.rom then
        local ok, raw = pcall(function()
          return self.rom:bytes(sym.bank, sym.address, 128 * 16)
        end)
        if ok and type(raw) == "table" and #raw >= 16 then
          pixels = raw
        end
      end
    end
    if not pixels then return bank, 0 end
    local n = math.floor(#pixels / 16)
    for t = 0, n - 1 do
      local tile = {}
      for i = 1, 16 do tile[i] = pixels[t * 16 + i] or 0 end
      bank[baseId + t] = tile
    end
    return bank, n
  end

  local tileBank = {}
  local tmBank, tmCount = loadTiles("TownMapGFX", 0)
  for id, tile in pairs(tmBank) do tileBank[id] = tile end
  local pgBank, pgCount = loadTiles("PokegearGFX", 0x30)
  for id, tile in pairs(pgBank) do tileBank[id] = tile end
  out.tileCount = (tmCount or 0) + (pgCount or 0)

  local function cellsFromBytes(bytes)
    if type(bytes) ~= "table" or #bytes < 2 then return nil end
    local cells = {}
    local i = 1
    while i + 1 <= #bytes and #cells < 20 * 18 do
      local tile = bytes[i]
      if tile == 0xFF then break end
      local count = bytes[i + 1]
      i = i + 2
      if count == 0 then count = 256 end
      for _ = 1, count do
        if #cells >= 20 * 18 then break end
        cells[#cells + 1] = tile
      end
    end
    while #cells < 20 * 18 do cells[#cells + 1] = 0x4F end
    return cells
  end

  local function decodeRleSymbol(symbolName)
    local sym = self:symbol(symbolName)
    if not (sym and self.rom) then return nil end
    local bytes = {}
    local ok = pcall(function()
      local addr, i = sym.address, 0
      while i < 400 do
        local tile = self.rom:byte(sym.bank, addr + i)
        bytes[#bytes + 1] = tile
        if tile == 0xFF then break end
        bytes[#bytes + 1] = self.rom:byte(sym.bank, addr + i + 1)
        i = i + 2
      end
    end)
    return ok and cellsFromBytes(bytes) or nil
  end

  local function paintTile(image, tile, colors, px, py)
    if not tile then
      for y = 0, 7 do
        for x = 0, 7 do
          image:setPixel(px + x, py + y, 0.82, 0.85, 0.70, 1)
        end
      end
      return
    end
    for y = 0, 7 do
      local low = tile[y * 2 + 1] or 0
      local high = tile[y * 2 + 2] or 0
      for x = 0, 7 do
        local div = 2 ^ (7 - x)
        local shade = math.floor(high / div) % 2 * 2 + math.floor(low / div) % 2
        local c = colors[shade] or colors[0] or { 0.8, 0.8, 0.7 }
        image:setPixel(px + x, py + y, c[1], c[2], c[3], 1)
      end
    end
  end

  local function renderCard(cells, relative)
    if not cells then return nil end
    local colors = (pals and pals[0]) or GEN2_POKEGEAR_BORDER_PAL
    if not colors[0] and colors[1] then
      -- out.palettes is 1-based 0-255 triples; convert
      colors = {
        [0] = { colors[1][1]/255, colors[1][2]/255, colors[1][3]/255 },
        [1] = { (colors[2] or colors[1])[1]/255, (colors[2] or colors[1])[2]/255, (colors[2] or colors[1])[3]/255 },
        [2] = { (colors[3] or colors[1])[1]/255, (colors[3] or colors[1])[2]/255, (colors[3] or colors[1])[3]/255 },
        [3] = { (colors[4] or {0,0,0})[1]/255, (colors[4] or {0,0,0})[2]/255, (colors[4] or {0,0,0})[3]/255 },
      }
    end
    local image = love.image.newImageData(160, 144)
    for row = 0, 17 do
      for col = 0, 19 do
        local tileId = cells[row * 20 + col + 1] or 0x4F
        paintTile(image, tileBank[tileId], colors, col * 8, row * 8)
      end
    end
    self:saveImage(image, relative)
    return "assets/generated/" .. relative
  end

  for _, pair in ipairs({
    { "CLOCK", "ClockTilemapRLE" },
    { "PHONE", "PhoneTilemapRLE" },
    { "RADIO", "RadioTilemapRLE" },
  }) do
    local name, sym = pair[1], pair[2]
    local cells = decodeRleSymbol(sym) or cellsFromBytes(GEN2_POKEGEAR_RLE[name])
    if cells then
      out.cards[name] = renderCard(cells, "ui/pokegear_" .. name:lower() .. ".png")
    end
  end

  pcall(function()
    local pixels = self:gen2Lz("PokegearGFX")
    if not pixels or #pixels < 16 then return end
    local tiles = math.floor(#pixels / 16)
    local rows = math.max(1, math.ceil(tiles / 16))
    while #pixels < rows * 16 * 16 do pixels[#pixels + 1] = 0 end
    local image
    if ImageWriter.decode2bppColor then
      image = ImageWriter.decode2bppColor(pixels, 128, rows * 8, GEN2_POKEGEAR_BORDER_PAL, false)
    else
      image = ImageWriter.decode2bpp(pixels, 128, rows * 8, false)
    end
    self:saveImage(image, "ui/pokegear_tiles.png")
    out.tiles = "assets/generated/ui/pokegear_tiles.png"
  end)
  pcall(function()
    local pixels = self:gen2Lz("PokegearSpritesGFX")
    if not pixels or #pixels < 16 then return end
    local tiles = math.floor(#pixels / 16)
    local rows = math.max(1, math.ceil(tiles / 2))
    while #pixels < rows * 2 * 16 do pixels[#pixels + 1] = 0 end
    local rawImg
    if ImageWriter.decode2bppColor then
      rawImg = ImageWriter.decode2bppColor(pixels, 16, rows * 8, GEN2_POKEGEAR_BORDER_PAL, true)
    else
      rawImg = ImageWriter.decode2bpp(pixels, 16, rows * 8, true)
    end
    local image = ImageWriter.matteColor0(rawImg)
    self:saveImage(image, "ui/pokegear_sprites.png")
    out.sprites = "assets/generated/ui/pokegear_sprites.png"
  end)
  pcall(function()
    local sym = self:symbol("ChrisSpriteGFX")
    if not (sym and self.rom) then return end
    local raw = self.rom:bytes(sym.bank, sym.address, 4 * 16)
    local redPal = {
      [0] = { 28/31, 31/31, 16/31 },
      [1] = { 31/31, 19/31, 10/31 },
      [2] = { 31/31,  7/31,  1/31 },
      [3] = { 0, 0, 0 },
    }
    local image
    if ImageWriter.decode2bppColor then
      image = ImageWriter.matteColor0(ImageWriter.decode2bppColor(raw, 16, 16, redPal, true))
    else
      image = ImageWriter.matteColor0(ImageWriter.decode2bpp(raw, 16, 16, true))
      if ImageWriter.recolorShades then image = ImageWriter.recolorShades(image, redPal) end
    end
    self:saveImage(image, "ui/pokegear_player.png")
    out.playerIcon = "assets/generated/ui/pokegear_player.png"
  end)

  if not next(out.palettes) and not out.tiles and not out.playerIcon and not next(out.cards) then
    return nil
  end
  return out
end

-- ChrisPicAndTrainerCardGFX is raw (uncompressed) 2bpp copied straight to
-- vTiles2 by TrainerCard.InitRAM: $290 bytes = 41 tiles, of which the first
-- 5x7 = 35 are the standing portrait row-major and the last 6 are the card's
-- own "ID No" label.
local GEN2_PLAYER_PIC_COLS = 5
local GEN2_PLAYER_PIC_ROWS = 7

function RomExtractorGen2:gen2PlayerFrontPic()
  local sym = self:symbol("ChrisPicAndTrainerCardGFX")
  if not (sym and self.rom) then return nil end
  local relative = "battle/chrisf.png"
  local cols, rows = GEN2_PLAYER_PIC_COLS, GEN2_PLAYER_PIC_ROWS
  local ok = pcall(function()
    local raw = self.rom:bytes(sym.bank, sym.address, cols * rows * 16)
    self:saveImage(ImageWriter.matteColor0(
      ImageWriter.decode2bpp(raw, cols * 8, rows * 8)), relative)
  end)
  if not ok then return nil end
  return "assets/generated/" .. relative
end

-- ChrisBackpic is a 6x6-tile LZ3 pic like every Gen2 back sprite, so the
-- battle draws it 1:1 at hlcoord 1,6 (see BATTLE_SCALE_GEN2).
function RomExtractorGen2:gen2PlayerPics()
  local sym = self:symbol("ChrisBackpic")
  if not (sym and self.rom) then return nil end
  local relative = "battle/chrisb.png"
  local ok = pcall(function()
    local raw = self.rom:bytes(sym.bank, sym.address, 0x8000 - sym.address)
    local pixels = decompressLz3(raw)
    local tiles = math.floor(math.sqrt(math.floor(#pixels / 16)) + 0.5)
    assert(tiles >= 1 and tiles * tiles * 16 <= #pixels, "short back pic")
    self:saveImage(ImageWriter.matteColor0(ImageWriter.decode2bpp(
      colMajorToRowMajor(pixels, tiles, tiles), tiles * 8, tiles * 8)), relative)
  end)
  if not ok then return nil end
  local path = "assets/generated/" .. relative
  return { back = path, demoBack = path, oakBack = path,
           front = self:gen2PlayerFrontPic() or path }
end

-- CutTreeBlockPointers (03:$489E) and WhirlpoolBlockPointers share a format:
-- `db tilesetId, dw rows` until $FF, where each row is `db before, db after,
-- db anim` until $FF.  CutDownTreeOrGrass / DisappearWhirlpool write `after`
-- over the block and hand `anim` to the sprite animation (1 = the tree
-- splitting apart, 0 = the leaf/grass puff), so both bytes are worth keeping.
-- Gen1's cut swap was a flat list because R/B only ever cut one block in one
-- tileset; GSC cuts five tilesets' worth.
function RomExtractorGen2:gen2BlockSwaps(symbolName)
  local table_ = self:symbol(symbolName)
  if not (table_ and self.rom) then return nil end
  local names = self:gen2TilesetNames()
  local out = {}
  local ok = pcall(function()
    local entry = table_.address
    for _ = 1, 16 do
      local id = self.rom:byte(table_.bank, entry)
      if id == 0xFF then break end
      local rows = self.rom:word(table_.bank, entry + 1)
      entry = entry + 3
      local name = names[id]
      if name then
        local list = {}
        for i = 0, 31 do
          local before = self.rom:byte(table_.bank, rows + i * 3)
          if before == 0xFF then break end
          list[#list + 1] = {
            before = before,
            after = self.rom:byte(table_.bank, rows + i * 3 + 1),
            anim = self.rom:byte(table_.bank, rows + i * 3 + 2) == 1
                   and "tree" or "grass",
          }
        end
        if #list > 0 then out[name] = list end
      end
    end
  end)
  if not ok or not next(out) then return nil end
  return out
end

function RomExtractorGen2:gen2CutTreeSwaps()
  return self:gen2BlockSwaps("CutTreeBlockPointers")
end

-- The floors that run pitch black until FLASH: their map header asks for
-- PALETTE_DARK, which is the one palset ReplaceTimeOfDayPals turns into
-- .NeedsFlash.  Keyed by pret label, like the rest of the field tables.
function RomExtractorGen2:gen2DarkMaps()
  local out = {}
  for _, entry in pairs((self:gen2MapIndex())) do
    if entry.palette == 4 then out[entry.label] = true end
  end
  return next(out) and out or nil
end

-- FruitTreeItems (17:$4091), one item id per fruit tree, indexed by
-- wCurFruitTree - 1 (GetFruitTreeItem 17:$4084).  The table has no
-- terminator, so it is bounded by the next symbol in the bank.
function RomExtractorGen2:gen2FruitTrees()
  local table_ = self:symbol("FruitTreeItems")
  if not (table_ and self.rom) then return nil end
  local stop = table_.address + 64
  for _, location in pairs(self.symbols or {}) do
    if type(location) == "table" and tonumber(location[1]) == table_.bank then
      local address = tonumber(location[2])
      if address and address > table_.address and address < stop then
        stop = address
      end
    end
  end
  local out = {}
  local ok = pcall(function()
    for i = 0, stop - table_.address - 1 do
      local item = self.rom:byte(table_.bank, table_.address + i)
      if item and item > 0 then out[i + 1] = string.format("ITEM_%03d", item) end
    end
  end)
  if not ok or not next(out) then return nil end
  return out
end

-- TreeMonMaps (2E:$63E6) tags each headbutt map with a set id; TreeMons
-- (2E:$6470) points at the sets, each a common table then a rare table of
-- `db species, level, chance` rows behind a total-chance byte.  Entry 3 is
-- the rock-smash list and uses the shorter `db chance, species, level` form.
function RomExtractorGen2:gen2TreeMons()
  local mapsSym = self:symbol("TreeMonMaps")
  local setsSym = self:symbol("TreeMons")
  if not (mapsSym and setsSym and self.rom) then return nil end
  local byGroupNumber = self:gen2MapIndex()
  local out = { maps = {}, sets = {}, rock = {} }
  local ok = pcall(function()
    local address = mapsSym.address
    for _ = 1, 64 do
      local group = self.rom:byte(mapsSym.bank, address)
      if group == 0xFF or group == 0 then break end
      local set = self.rom:byte(mapsSym.bank, address + 2)
      local entry = byGroupNumber[group * 256 + self.rom:byte(mapsSym.bank, address + 1)]
      -- GetTreeMons quits on 0 and on anything >= 4, so the rows tagged 5 are
      -- "no trees here" just as much as the rows tagged 0
      if entry and set >= 1 and set <= 3 then out.maps[entry.label] = set end
      address = address + 3
    end
    for set = 1, 2 do
      local at = self.rom:word(setsSym.bank, setsSym.address + set * 2)
      local halves = {}
      for half = 1, 2 do
        local rows = { rate = self.rom:byte(setsSym.bank, at) }
        at = at + 1
        for _ = 1, 6 do
          rows[#rows + 1] = {
            species = string.format("SPECIES_%03d", self.rom:byte(setsSym.bank, at)),
            level = self.rom:byte(setsSym.bank, at + 1),
            chance = self.rom:byte(setsSym.bank, at + 2),
          }
          at = at + 3
        end
        halves[half] = rows
      end
      out.sets[set] = { common = halves[1], rare = halves[2] }
    end
    local at = self.rom:word(setsSym.bank, setsSym.address + 3 * 2)
    for _ = 1, 8 do
      local chance = self.rom:byte(setsSym.bank, at)
      if chance == 0xFF then break end
      out.rock[#out.rock + 1] = {
        chance = chance,
        species = string.format("SPECIES_%03d", self.rom:byte(setsSym.bank, at + 1)),
        level = self.rom:byte(setsSym.bank, at + 2),
      }
      at = at + 3
    end
  end)
  if not ok or not next(out.maps) then return nil end
  return out
end

-- Game Corner slots (engine/games/slot_machine.asm).  Reel{1,2,3}Tilemap are
-- 18-entry strips of reel icon tile ids -- one icon is 4 tiles, so the icon
-- index is the id / 4 -- and Slots_GetPayout's table pays per icon.  Slots1LZ
-- is the BG tile set SlotsTilemap arranges into the cabinet; Slots2LZ is the
-- OAM sheet the six reel icons are drawn from, two 8x16 sprites apiece, so
-- its tiles run down each column before moving right.
function RomExtractorGen2:gen2Slots()
  if not self.rom then return nil end
  local ok, out = pcall(function()
    local reels = {}
    for index = 1, 3 do
      local sym = self:symbol("Reel" .. index .. "Tilemap")
      if not sym then return nil end
      local strip = {}
      for step = 0, 17 do
        strip[step + 1] =
          math.floor(self.rom:byte(sym.bank, sym.address + step) / 4)
      end
      reels[index] = strip
    end

    local pay = self:symbol("Slots_GetPayout.Payouts")
    local payouts = { [0] = 300, 50, 6, 8, 10, 15 }
    if pay then
      for icon = 0, 5 do
        payouts[icon] = self.rom:word(pay.bank, pay.address + icon * 2)
      end
    end

    -- the cabinet: 20 columns of BG tile ids, however many rows the block
    -- between SlotsTilemap and Slots1LZ holds
    local mapSym = self:symbol("SlotsTilemap")
    local bgSym = self:symbol("Slots1LZ")
    local tilemap
    if mapSym and bgSym then
      tilemap = {}
      for at = 0, (bgSym.address - mapSym.address) - 1 do
        tilemap[at + 1] = self.rom:byte(mapSym.bank, mapSym.address + at)
      end
    end

    local function sheet(name, transparent)
      local pixels = self:gen2Lz(name)
      if not pixels then return nil end
      local tiles = math.floor(#pixels / 16)
      local rows = math.ceil(tiles / 16)
      -- decode2bpp wants a full rectangle; the blobs are not multiples of a
      -- 16-tile row, so pad the tail out with blank tiles
      for at = #pixels + 1, rows * 16 * 16 do pixels[at] = 0 end
      return ImageWriter.decode2bpp(pixels, 128, rows * 8, transparent), tiles
    end

    local bg = sheet("Slots1LZ", false)
    if bg then self:saveImage(bg, "minigames/slots_bg.png") end

    local icons = sheet("Slots2LZ", true)
    if icons then
      local symbols = ImageWriter.blank(6 * 16, 16, 1, 1, 1, 0)
      for icon = 0, 5 do
        for part = 0, 3 do
          local tile = icon * 4 + part
          ImageWriter.blit(symbols, icons,
            icon * 16 + math.floor(part / 2) * 8, part % 2 * 8,
            tile % 16 * 8, math.floor(tile / 16) * 8, 8, 8)
        end
      end
      self:saveImage(symbols, "minigames/slots_symbols.png")
    end

    -- SlotMachinePals is 16 entries: BG 0-7 then OBJ 0-7.  A reel icon's OAM
    -- attribute is its own index (Slots_UpdateReelPositionAndOAM shifts the
    -- tile id right twice), so OBJ n colours icon n.
    local palettes = self:gen2Palettes("SlotMachinePals", 16)
    -- PaletteFX zones want 0-255 triples; gen2Palettes hands back 0..1
    if palettes then
      for _, pal in ipairs(palettes) do
        for _, color in ipairs(pal) do
          for channel = 1, 3 do
            color[channel] = math.floor(color[channel] * 255 + 0.5)
          end
        end
      end
    end

    return {
      reels = reels,
      payouts = payouts,
      tilemap = tilemap,
      tilemapWidth = 20,
      bg = bg and "assets/generated/minigames/slots_bg.png" or nil,
      symbols = icons and "assets/generated/minigames/slots_symbols.png" or nil,
      palettes = palettes,
    }
  end)
  if not ok then Logger.warn("gen2 slots: %s", tostring(out)) end
  return ok and out or nil
end

-- Celadon's CardFlip (bank $38).  The board, the face-up card stamp, the
-- per-card tile pair and the cursor's OAM templates are all plain tables in
-- the ROM, so the port reads them rather than re-inventing the geometry.
RomExtractorGen2.CARD_FLIP_CURSOR_SHAPES = {
  "SingleTile", "PokeGroup", "NumGroup",
  "NumGroupPair", "PokeGroupPair", "Impossible",
}

function RomExtractorGen2:gen2CardFlip()
  if not self.rom then return nil end
  local ok, out = pcall(function()
    local mapSym = self:symbol("CardFlipTilemap")
    local faceSym = self:symbol("CardFlip_DisplayCardFaceUp.FaceUpCardTilemap")
    local slotSym = self:symbol("CardFlip_UpdateCursorOAM.OAMData")
    if not (mapSym and faceSym and slotSym) then return nil end

    -- CardFlip_InitTilemap copies 12 rows of 11 columns to tilemap offset 9
    local tilemap = {}
    for at = 0, 11 * 12 - 1 do
      tilemap[at + 1] = self.rom:byte(mapSym.bank, mapSym.address + at)
    end

    -- CardFlip_DisplayCardFaceUp stamps 6 rows of 5 columns, then overwrites
    -- the digit at +23 and a 3x3 run of the mon picture at +38
    local faceUp = {}
    for at = 0, 5 * 6 - 1 do
      faceUp[at + 1] = self.rom:byte(faceSym.bank, faceSym.address + at)
    end
    local cards = {}
    for card = 0, 23 do
      local at = faceSym.address + 30 + card * 2
      cards[card] = {
        digit = self.rom:byte(faceSym.bank, at),
        base = self.rom:byte(faceSym.bank, at + 1),
      }
    end

    -- the six cursor templates: db count, then count x (y, x, tile, attr)
    local shapes, shapeAt = {}, {}
    for _, name in ipairs(RomExtractorGen2.CARD_FLIP_CURSOR_SHAPES) do
      local sym = self:symbol("CardFlip_UpdateCursorOAM." .. name)
      if sym then
        shapeAt[sym.address] = name
        local sprites = {}
        for index = 0, self.rom:byte(sym.bank, sym.address) - 1 do
          local at = sym.address + 1 + index * 4
          sprites[index + 1] = {
            y = self.rom:byte(sym.bank, at),
            x = self.rom:byte(sym.bank, at + 1),
            tile = self.rom:byte(sym.bank, at + 2),
            attr = self.rom:byte(sym.bank, at + 3),
          }
        end
        shapes[name] = sprites
      end
    end

    -- 48 bet positions, 6 columns x 8 rows: db x, y, dw template
    local slots = {}
    for index = 0, 47 do
      local at = slotSym.address + index * 4
      slots[index + 1] = {
        x = self.rom:byte(slotSym.bank, at),
        y = self.rom:byte(slotSym.bank, at + 1),
        shape = shapeAt[self.rom:word(slotSym.bank, at + 2)] or "Impossible",
      }
    end

    -- BG tiles: LZ01 fills $00 up, LZ02 lands on $3E, and the two play-counter
    -- lights are raw 2bpp at $EF and $F5
    local pixels = {}
    for at = 1, 256 * 16 do pixels[at] = 0 end
    local function paste(bytes, tile)
      if not bytes then return end
      for at = 1, #bytes do pixels[tile * 16 + at] = bytes[at] end
    end
    paste(self:gen2Lz("CardFlipLZ01"), 0x00)
    paste(self:gen2Lz("CardFlipLZ02"), 0x3E)
    for _, pair in ipairs({ { "CardFlipOffButtonGFX", 0xEF }, { "CardFlipOnButtonGFX", 0xF5 } }) do
      local sym = self:symbol(pair[1])
      if sym then
        local raw = {}
        for at = 0, 15 do raw[at + 1] = self.rom:byte(sym.bank, sym.address + at) end
        paste(raw, pair[2])
      end
    end
    self:saveImage(ImageWriter.decode2bpp(pixels, 128, 128, false),
      "minigames/cardflip_bg.png")

    local cursorPixels = self:gen2Lz("CardFlipLZ03")
    local cursor
    if cursorPixels then
      for at = #cursorPixels + 1, 16 * 16 do cursorPixels[at] = 0 end
      cursor = ImageWriter.decode2bpp(cursorPixels, 128, 8, true)
      self:saveImage(cursor, "minigames/cardflip_cursor.png")
    end

    local palettes = self:gen2Palettes("CardFlip_InitAttrPals.palettes", 9)
    if palettes then
      for _, pal in ipairs(palettes) do
        for _, color in ipairs(pal) do
          for channel = 1, 3 do
            color[channel] = math.floor(color[channel] * 255 + 0.5)
          end
        end
      end
    end

    return {
      tilemap = tilemap,
      tilemapWidth = 11,
      faceUp = faceUp,
      faceUpWidth = 5,
      cards = cards,
      slots = slots,
      shapes = shapes,
      palettes = palettes,
      bg = "assets/generated/minigames/cardflip_bg.png",
      cursor = cursor and "assets/generated/minigames/cardflip_cursor.png" or nil,
    }
  end)
  if not ok then Logger.warn("gen2 card flip: %s", tostring(out)) end
  return ok and out or nil
end

-- ------------------------------------------------------------------
-- The EGG.  It is not a species, so nothing above picks it up: the pic
-- (EggPic, LZ3 like every other pic), the party icon (EggIcon, 8 raw tiles
-- = two 16x16 frames) and the four "how close is it" lines EggStatsScreen
-- picks between all live outside the species tables.  The palette is
-- PokemonPalettes entry 252 -- the table is 256 entries long, one past
-- CELEBI is the egg's gold pair.
--
-- EggStatsScreen (20:50ED) reads the hatch counter out of the happiness
-- byte and compares it against 6 / 11 / 41, which is what `thresholds`
-- below mirrors; one counter tick is 256 steps.
-- ------------------------------------------------------------------
function RomExtractorGen2:gen2Egg()
  if not self.rom then return nil end
  local out = { name = "EGG", stepsPerCycle = 256 }

  local palSym = self:symbol("PokemonPalettes")
  local colors = { GEN2_PAL_WHITE, { 247, 214, 90 }, { 189, 132, 0 }, GEN2_PAL_BLACK }
  if palSym then
    pcall(function()
      local base = palSym.address + 252 * GEN2_MON_PAL_BYTES
      colors = {
        GEN2_PAL_WHITE,
        gen2Rgb5(self.rom:word(palSym.bank, base)),
        gen2Rgb5(self.rom:word(palSym.bank, base + 2)),
        GEN2_PAL_BLACK,
      }
    end)
  end
  out.palette = colors

  local iconSym = self:symbol("EggIcon")
  if iconSym then
    local ok = pcall(function()
      local raw = self.rom:bytes(iconSym.bank, iconSym.address, 8 * 16)
      local tiles = gen2SplitTiles(raw)
      local pal = {}
      for n = 1, 4 do
        pal[n] = { colors[n][1] / 255, colors[n][2] / 255, colors[n][3] / 255 }
      end
      local image = ImageWriter.blank(16, 32, 0, 0, 0, 0)
      for frame = 0, 1 do
        for col = 0, 1 do
          for row = 0, 1 do
            local tile = tiles[frame * 4 + row * 2 + col]
            if tile then
              for y = 0, 7 do
                for x = 0, 7 do
                  local shade = tile[y * 8 + x + 1]
                  if shade ~= 0 then
                    local c = pal[shade + 1]
                    image:setPixel(col * 8 + x, frame * 16 + row * 8 + y,
                                   c[1], c[2], c[3], 1)
                  end
                end
              end
            end
          end
        end
      end
      self:saveImage(image, "icons/egg.png")
    end)
    if ok then out.icon = "assets/generated/icons/egg.png" end
  end

  local picSym = self:symbol("EggPic")
  if picSym then
    local ok = pcall(function()
      local raw = self.rom:bytes(picSym.bank, picSym.address,
                                 0x8000 - picSym.address)
      local pixels = decompressLz3(raw)
      local side = math.floor(math.sqrt(math.floor(#pixels / 16)) + 0.5)
      if side < 1 or side * side * 16 > #pixels then error("bad egg pic") end
      self:saveImage(ImageWriter.matteColor0(ImageWriter.decode2bpp(
        colMajorToRowMajor(pixels, side, side), side * 8, side * 8)),
        "battle/front/egg.png")
    end)
    if ok then out.pic = "assets/generated/battle/front/egg.png" end
  end

  local charmap = self:readSourceTable("charmap")
  out.hatchText = {}
  for key, symbolName in pairs({
    soon = "EggSoonString", close = "EggCloseString",
    more = "EggMoreTimeString", lots = "EggALotMoreTimeString",
  }) do
    local sym = self:symbol(symbolName)
    if sym then
      local ok, text = pcall(function()
        return self:decodeGen2TextAt(sym.bank, sym.address, charmap)
      end)
      if ok and type(text) == "string" and text ~= "" then
        out.hatchText[key] = text
      end
    end
  end
  -- EggStatsScreen's `cp 6 / cp $0b / cp $29` ladder, in hatch cycles
  out.thresholds = { soon = 6, close = 11, more = 41 }
  return out
end

function RomExtractorGen2:extractField()
  self:beginStage("Gen2 field")
  local src = copy(self.manifest.field or {})
  if type(src.presetNames) ~= "table" then
    src.presetNames = {
      player = { "GOLD", "KRIS", "CHRIS" },
      rival = { "SILVER", "RIVAL", "???" },
    }
  end
  src.playerSprites = src.playerSprites or {}
  if type(src.playerSprites.walk) ~= "string" then src.playerSprites.walk = "SPRITE_RED" end
  -- Gen2 OverworldSprites row for SurfSpriteGFX is $54; Gen1 used SEEL.
  if type(src.playerSprites.surf) ~= "string" then
    src.playerSprites.surf = (self.rom and "SPRITE_SURF") or "SPRITE_SEEL"
  end
  if type(src.playerSprites.bike) ~= "string" then src.playerSprites.bike = "SPRITE_RED_BIKE" end
  if type(src.playerSprites.fly) ~= "string" then src.playerSprites.fly = "SPRITE_BIRD" end
  src.forcedMovement = src.forcedMovement or {}
  if type(src.forcedMovement.tiles) ~= "table" then src.forcedMovement.tiles = {} end
  if type(src.forcedMovement.slopeMaps) ~= "table" then src.forcedMovement.slopeMaps = {} end
  if type(src.forcedMovement.clearMaps) ~= "table" then src.forcedMovement.clearMaps = {} end
  -- OakSpeech shows MAREEP, not Red's NIDORINO, while Oak explains what a
  -- POKeMON is; the Gen1 default resolves to nothing in a Gen2 species table.
  src.oakSpeech = src.oakSpeech or {}
  src.oakSpeech.demoSpecies = "SPECIES_179"
  -- Title screen and attract movie: TitleState and Gen2Intro read these,
  -- and both degrade to their text fallbacks when the rip comes up empty.
  if self.rom then
    local okTitle, title = pcall(self.extractGen2TitleArt, self)
    if okTitle and title then src.title = title end
    local okIntro, intro = pcall(self.extractGen2IntroArt, self)
    if okIntro and intro then src.intro = intro end
    src.ledgeHops = self:gen2LedgeHops() or src.ledgeHops
    src.townMap = self:gen2TownMap() or src.townMap
    src.playerPics = self:gen2PlayerPics() or src.playerPics
    src.gen2CutTrees = self:gen2CutTreeSwaps() or src.gen2CutTrees
    src.gen2Whirlpools = self:gen2BlockSwaps("WhirlpoolBlockPointers")
      or src.gen2Whirlpools
    src.flyWarps = self:gen2FlyWarps() or src.flyWarps
    src.flyOrder = self:gen2FlyOrder(src.flyWarps) or src.flyOrder
    -- what the save codec needs to carry a cartridge save's flags and Fly set
    src.engineFlags = self:gen2EngineFlags() or src.engineFlags
    src.spawnFlags = self:gen2SpawnFlags() or src.spawnFlags
    src.gen2FruitTrees = self:gen2FruitTrees() or src.gen2FruitTrees
    src.gen2DarkMaps = self:gen2DarkMaps() or src.gen2DarkMaps
    src.gen2TreeMons = self:gen2TreeMons() or src.gen2TreeMons
    src.gen2Slots = self:gen2Slots() or src.gen2Slots
    src.gen2CardFlip = self:gen2CardFlip() or src.gen2CardFlip
    src.egg = self:gen2Egg() or src.egg
    src.pokegear = self:gen2Pokegear() or src.pokegear
    -- Prefer the pokegear Chris icon (PAL_OW_RED) on the town map too
    if src.pokegear and src.pokegear.playerIcon and src.townMap then
      src.townMap.playerIcon = src.pokegear.playerIcon
    end
    -- Derive water-capable tilesets from AnimateWaterTile presence so that
    -- OverworldState:tilesetHasWater() returns true for outdoor Gen2 maps.
    -- gen2TilesetAnimation reads the ROM's tileset animation script and
    -- returns "TILEANIM_WATER" when the tileset calls AnimateWaterTile.
    local waterTs = {}
    local tilesetIds = self:gen2TilesetNames()
    local seen = {}
    for _, name in pairs(tilesetIds) do
      if not seen[name] then
        seen[name] = true
        if self:gen2TilesetAnimation(name) == "TILEANIM_WATER" then
          waterTs[#waterTs + 1] = name
        end
      end
    end
    if next(waterTs) then src.waterTilesets = waterTs end
  end
  self:write("field", src)
  self:tick("Gen2 field", 1, 1)
end

-- Gen2 keeps the text font in bank $3E as two sheets: `Font` is 128 *1bpp*
-- tiles for codes $80-$FF, `FontExtra` is 32 2bpp tiles for $60-$7F.  The
-- textbox frame is not part of either -- `Frames` holds one 6-tile style per
-- entry and LoadFrame copies the chosen one over codes $79-$7E, so bake the
-- default style in here rather than shipping the unused bold letters that
-- sit in those slots on the sheet.
-- Trainer card badge slots.
--
-- TrainerCard_Page2_LoadGFX copies two sheets: 44 raw 2bpp tiles from
-- BadgeGFX (Johto) / BadgeGFX2 (Kanto), and 86 from LeaderGFX / LeaderGFX2.
-- The first 32 badge tiles are the eight badges, four apiece, laid out 2x2
-- row-major by TrainerCard_Page2_3_OAMUpdate's .facing1 template; the rest
-- are the spin frames a still card has no use for.
--
-- The leader sheet is eight groups of ten.  TrainerCard_Page2_3_PlaceLeadersFaces
-- writes four consecutive tile ids, steps hl by $11, writes three, steps by
-- $11 again and writes three -- on a 20-wide tilemap that is row 0 columns
-- 0-3 then row 1 columns 1-3 then row 2 columns 1-3.  So tile 0 is the slot's
-- little number plate and tiles 1-9 are the gym leader's head, three by three,
-- in the columns beside it.  That is what the user sees on a real card: the
-- LEADERS' FACES are the badge page, and the badge itself is an OAM sprite
-- laid over the face -- TrainerCard_JohtoBadgesOAM puts it at screen x 16,
-- y 88, which is the slot's own column, one tile row down.
--
-- Colour is _CGB_TrainerCard's: it loads the CHRIS, FALKNER, WHITNEY, BUGSY,
-- MORTY, PRYCE, JASMINE and CHUCK entries of TrainerPalettes into BG slots
-- 0-7, then paints the eight 4x2 badge boxes with slots 1-7 -- the eighth
-- (Clair's) keeps the screen fill, which is slot 1, Falkner.  Baking it in
-- here is what stops the card coming out as the flat grey wash the SGB
-- packet would otherwise put over the whole screen.
local GEN2_BADGE_TILE_BYTES = 16
local GEN2_BADGE_TILES = 4

function RomExtractorGen2:extractTrainerCardBadges()
  local johto, kanto = self:symbol("BadgeGFX"), self:symbol("BadgeGFX2")
  local johtoFaces = self:symbol("LeaderGFX")
  local kantoFaces = self:symbol("LeaderGFX2")
  if not (self.rom and johto and kanto and johtoFaces and kantoFaces) then
    return false
  end
  local trainers = self:gen2TrainerPalettes(9)
  if not trainers then return false end
  return (pcall(function()
    -- badge box i takes the gym leader's own trainer-class palette
    local slotPal = { 1, 3, 2, 4, 7, 6, 5, 1 }
    local faceTiles = 10
    -- like gen2DrawTile, but color 0 is left clear so a badge can sit over
    -- a face and a face over the card
    local function draw(image, tile, px, py, pal)
      if not tile then return end
      for y = 0, 7 do
        for x = 0, 7 do
          local shade = tile[y * 8 + x + 1]
          local color = pal[shade + 1]
          image:setPixel(px + x, py + y, color[1], color[2], color[3],
            shade == 0 and 0 or 1)
        end
      end
    end
    local count = #GEN2_BADGES
    local badges = ImageWriter.blank(16, count * 16, 0, 0, 0, 0)
    local slots = ImageWriter.blank(32, count * 24, 0, 0, 0, 0)
    for index, entry in ipairs(GEN2_BADGES) do
      -- Johto and Kanto are the same eight boxes on pages 2 and 3
      local box = (index - 1) % 8 + 1
      local pal = trainers[slotPal[box] + 1]
      local sym = entry.kanto and kanto or johto
      local badge = gen2SplitTiles(self.rom:bytes(sym.bank,
        sym.address + entry.bit * GEN2_BADGE_TILES * GEN2_BADGE_TILE_BYTES,
        GEN2_BADGE_TILES * GEN2_BADGE_TILE_BYTES))
      for t = 0, GEN2_BADGE_TILES - 1 do
        draw(badges, badge[t], t % 2 * 8,
          (index - 1) * 16 + math.floor(t / 2) * 8, pal)
      end
      local faceSym = entry.kanto and kantoFaces or johtoFaces
      local head = gen2SplitTiles(self.rom:bytes(faceSym.bank,
        faceSym.address + (box - 1) * faceTiles * GEN2_BADGE_TILE_BYTES,
        faceTiles * GEN2_BADGE_TILE_BYTES))
      local y0 = (index - 1) * 24
      draw(slots, head[0], 0, y0, pal)
      for t = 1, faceTiles - 1 do
        draw(slots, head[t], 8 + (t - 1) % 3 * 8,
          y0 + math.floor((t - 1) / 3) * 8, pal)
      end
    end
    self:saveImage(badges, "trainer_card/gen2_badges.png")
    self:saveImage(slots, "trainer_card/gen2_slots.png")
  end))
end

-- The Ruins of Alph wall puzzles (`special 41` -> UnownPuzzle, 3:$44BA).
-- Four LZ3 pictures listed by LoadUnownPuzzlePiecesGFX.LZPointers (56:$5FCA)
-- in the order the chamber scripts pass to `setval`: 0 Kabuto, 1 Omanyte,
-- 2 Aerodactyl, 3 Ho-Oh.  The board is 6x6 cells holding 16 pieces; the
-- ROM's own start layout and solved layout come along so the port is not
-- guessing either.
function RomExtractorGen2:extractUnownPuzzle()
  local ptrs = self:symbol("LoadUnownPuzzlePiecesGFX.LZPointers")
  local startSym = self:symbol("InitUnownPuzzlePiecePositions.PuzzlePieceInitialPositions")
  local solvedSym = self:symbol("CheckSolvedUnownPuzzle.SolvedPuzzleConfiguration")
  if not (self.rom and ptrs and startSym and solvedSym) then return false end
  local ok, result = pcall(function()
    local puzzles = {}
    for i, name in ipairs({ "kabuto", "omanyte", "aerodactyl", "ho_oh" }) do
      local lo = self.rom:byte(ptrs.bank, ptrs.address + (i - 1) * 2)
      local hi = self.rom:byte(ptrs.bank, ptrs.address + (i - 1) * 2 + 1)
      local address = lo + hi * 256
      local raw = self.rom:bytes(ptrs.bank, address, 0x8000 - address)
      local pixels = decompressLz3(raw)
      -- a plain gfx blob (FarDecompress straight into VRAM), not a pic, so
      -- the tiles are already row-major.  6x6 tiles = 48x48; the game
      -- pixel-doubles it to 96x96 and cuts 4x4 pieces of 24x24 out of that.
      local tiles = math.floor(#pixels / 16)
      local side = math.floor(math.sqrt(tiles) + 0.5)
      if side * side ~= tiles then side = 6 end
      local relPath = "minigames/unown_puzzle_" .. name .. ".png"
      self:saveImage(ImageWriter.decode2bpp(pixels, side * 8, side * 8), relPath)
      puzzles[i] = {
        name = name,
        image = "assets/generated/" .. relPath,
        tiles = side,
      }
    end
    local starts, solved = {}, {}
    for i = 1, 16 do
      starts[i] = self.rom:byte(startSym.bank, startSym.address + i - 1)
    end
    for i = 1, 36 do
      solved[i] = self.rom:byte(solvedSym.bank, solvedSym.address + i - 1)
    end
    -- _CGB_UnownPuzzle (02:$57E1) feeds PalPacket_UnownPuzzle's body to
    -- CopyFourPalettes, so BG palette 0 is PredefPals[first body byte].
    local palette
    local packet = self:symbol("PalPacket_UnownPuzzle")
    local predef = self:symbol("PredefPals")
    if packet and predef then
      local index = self.rom:byte(packet.bank, packet.address + 1)
      palette = {}
      for c = 0, 3 do
        palette[c + 1] = gen2Rgb5(
          self.rom:word(predef.bank, predef.address + index * 8 + c * 2))
      end
    end
    return { width = 6, height = 6, pieces = 16, palette = palette,
             start = starts, solved = solved, puzzles = puzzles }
  end)
  if not ok then
    Logger.warn("Gen2 Unown puzzle: %s", tostring(result))
    return false
  end
  self:write("unown_puzzle", result)
  Logger.info("Gen2 Unown puzzle: %d pictures (%dx%d tiles)",
    #result.puzzles, result.puzzles[1].tiles, result.puzzles[1].tiles)
  return true
end

-- The Pokédex's UNOWN MODE (engine/pokedex/pokedex.asm).
-- Pokedex_LoadUnownFont requests UnownFont at FIRST_UNOWN_CHAR, so tiles
-- 1-26 are the printed letters A-Z.  Its Pokedex_InvertTiles pass is not
-- reproduced: the ROM prints these on the dex's inverted $60-$7f field,
-- while the port draws them on a plain page, so the rip is kept the way it
-- is stored -- strokes on shade 3, field on shade 0, which drops out.
--
-- PrintUnownWord (engine/pokedex/unown_dex.asm) walks UnownWords, whose
-- entry 0 is an unused duplicate of A's.  The strings are not charmap text:
-- the `unownword` macro stores each character as its UnownFont tile id and
-- terminates with -1, so decoding them as dialogue produced {BYTE:nn} runs.
function RomExtractorGen2:extractUnownDex()
  local font = self:symbol("UnownFont")
  if not (self.rom and font) then return false end
  local ok, result = pcall(function()
    local NUM_UNOWN = 26
    local raw = self.rom:bytes(font.bank, font.address, NUM_UNOWN * 16)
    local relPath = "ui/unown_font.png"
    self:saveImage(
      ImageWriter.decode2bpp(raw, NUM_UNOWN * 8, 8, true), relPath)
    local words
    local table_ = self:symbol("UnownWords")
    if table_ then
      words = {}
      local base
      for i = 1, NUM_UNOWN do
        local at = self.rom:word(table_.bank, table_.address + i * 2)
        local letters = {}
        for n = 0, 15 do
          local b = self.rom:byte(table_.bank, at + n)
          if b == 0xFF then break end
          -- word 1 is "ANGRY", so its first tile id is FIRST_UNOWN_CHAR
          base = base or b
          letters[#letters + 1] = string.char(65 + (b - base) % NUM_UNOWN)
        end
        words[i] = table.concat(letters)
      end
    end
    return {
      font = "assets/generated/" .. relPath,
      letters = NUM_UNOWN,
      tile = 8,
      words = words,
    }
  end)
  if not ok then
    Logger.warn("Gen2 Unown dex: %s", tostring(result))
    return false
  end
  self:write("unown_dex", result)
  Logger.info("Gen2 Unown dex: %d letters, %d words",
    result.letters, result.words and #result.words or 0)
  return true
end

local GEN2_FONT_TILES = 128
local GEN2_FONT_EXTRA_TILES = 32
local GEN2_FRAME_TILES = 6
local GEN2_FRAME_BASE_CODE = 0x79

-- Gen2's battle animations are a bytecode VM, nothing like Gen1's
-- subanimation/frame-block model.  A script is a stream of frame delays
-- (bytes < $D0) and commands ($D0..$FF, BattleAnimCommands at 33:$4283);
-- `anim_obj` spawns one of BattleAnimObjects' 6-byte rows, which names a
-- frameset in BattleAnimFrameData, and each frame names a 4-byte
-- BattleAnimOAMData row that points at a run of `db y, x, tile, attr`
-- sprites.  BattleAnimOAMUpdate (33:$4958) places them at
-- (obj.x + obj.xOffset + sprite.x, obj.y + obj.yOffset + sprite.y) with the
-- tile taken as oamRow.tileOffset + sprite.tile inside the object's own
-- AnimObjGFX sheet, which is what lets the port skip VRAM emulation.
-- One table rather than a dozen chunk locals: this file sits on Lua's
-- 200-local-per-chunk ceiling.
local GEN2_ANIM = {}
GEN2_ANIM.CMD_BASE = 0xD0
GEN2_ANIM.OPS = {
  [0xD0] = { "obj", 4 },          [0xD6] = { "incobj", 1 },
  [0xD7] = { "setobj", 2 },       [0xD8] = { "incbgeffect", 1 },
  [0xD9] = { "battlergfx_2row" }, [0xDA] = { "battlergfx_1row" },
  [0xDB] = { "checkpokeball" },   [0xDC] = { "transform" },
  [0xDD] = { "raisesub" },        [0xDE] = { "dropsub" },
  [0xDF] = { "resetobp0" },       [0xE0] = { "sound", 2 },
  [0xE1] = { "cry", 1 },          [0xE2] = { "minimizeopp" },
  [0xE3] = { "oamon" },           [0xE4] = { "oamoff" },
  [0xE5] = { "clearobjs" },       [0xE6] = { "beatup" },
  [0xEE] = { "ifparamand", 3 },   [0xEF] = { "jumpuntil", 2 },
  [0xF0] = { "bgeffect", 4 },     [0xF1] = { "bgp", 1 },
  [0xF2] = { "obp0", 1 },         [0xF3] = { "obp1", 1 },
  [0xF4] = { "keepsprites" },     [0xF8] = { "ifparamequal", 3 },
  [0xF9] = { "setvar", 1 },       [0xFA] = { "incvar" },
  [0xFB] = { "ifvarequal", 3 },   [0xFC] = { "jump", 2 },
  [0xFD] = { "loop", 3 },         [0xFE] = { "call", 2 },
  [0xFF] = { "ret" },
}
-- which argument byte starts the `dw address` operand
GEN2_ANIM.JUMPS = {
  jump = 1, call = 1, jumpuntil = 1, loop = 2,
  ifparamand = 2, ifparamequal = 2, ifvarequal = 2,
}
GEN2_ANIM.OBJECT_BYTES = 6
GEN2_ANIM.OBJECT_COUNT = 188   -- BattleAnimObjects $4AA5..$4F0D
GEN2_ANIM.FN_TABLE = 0x4F1D    -- DoBattleAnimFrame's jumptable
GEN2_ANIM.FN_END = 0x4FBD      -- BattleAnimFunction_Null
GEN2_ANIM.OAM_BYTES = 4
GEN2_ANIM.GFX_BYTES = 4
GEN2_ANIM.GFX_COUNT = 42       -- AnimObjGFX $7C3B..$7CE3
-- BattleObjectPals ([2,$5C09], 48 bytes) is six palettes -- gray, yellow,
-- red, green, blue, brown -- that CGBCopyBattleObjectPals loads into OBJ
-- slots 2..7, so an object's palette field is the table index plus two.
GEN2_ANIM.OBJ_PALETTES = 6
GEN2_ANIM.SHEET_COLS = 16
GEN2_ANIM.MAX_STEPS = 512

-- Decode one script into a flat instruction list plus an address -> index map
-- so the player can follow jump/call/loop targets without re-walking bytes.
function RomExtractorGen2:gen2AnimScript(bank, entry)
  local byAddress, pending = {}, { entry }
  local visited = {}
  while #pending > 0 do
    local address = table.remove(pending)
    for _ = 1, GEN2_ANIM.MAX_STEPS do
      if visited[address] then break end
      visited[address] = true
      local ok, op = pcall(self.rom.byte, self.rom, bank, address)
      if not ok then break end
      local size, record = 1, nil
      if op < GEN2_ANIM.CMD_BASE then
        record = { op = "delay", frames = op }
      elseif op >= 0xD1 and op <= 0xD5 then
        local count = op - 0xD0
        local ids = {}
        for i = 1, count do
          ids[i] = self.rom:byte(bank, address + i)
        end
        size = 1 + count
        record = { op = "gfx", ids = ids }
      else
        local spec = GEN2_ANIM.OPS[op]
        if not spec then
          record = { op = "nop" }
        else
          local args = {}
          for i = 1, (spec[2] or 0) do
            args[i] = self.rom:byte(bank, address + i)
          end
          size = 1 + (spec[2] or 0)
          record = { op = spec[1], args = args }
          local at = GEN2_ANIM.JUMPS[spec[1]]
          if at then
            record.target = args[at] + args[at + 1] * 256
            if record.target >= 0x4000 and record.target < 0x8000 then
              pending[#pending + 1] = record.target
            else
              record.target = nil
            end
          end
        end
      end
      byAddress[address] = record
      address = address + size
      if record.op == "ret" or record.op == "jump" then break end
    end
  end

  local addresses = {}
  for address in pairs(byAddress) do addresses[#addresses + 1] = address end
  table.sort(addresses)
  local code, labels = {}, {}
  for index, address in ipairs(addresses) do
    code[index] = byAddress[address]
    labels[address] = index
  end
  for _, record in ipairs(code) do
    if record.target then
      record.to = labels[record.target]
      record.target = nil
    end
  end
  if not labels[entry] then return nil end
  return { entry = labels[entry], code = code }
end

function RomExtractorGen2:gen2AnimObjects()
  local sym = self:symbol("BattleAnimObjects")
  if not sym then return {} end
  local out = {}
  for id = 0, GEN2_ANIM.OBJECT_COUNT - 1 do
    local ok, row = pcall(self.rom.bytes, self.rom, sym.bank,
      sym.address + id * GEN2_ANIM.OBJECT_BYTES, GEN2_ANIM.OBJECT_BYTES)
    if not ok then break end
    out[id] = {
      oamFlags = row[1], fixY = row[2], frameset = row[3],
      fn = row[4], palette = row[5], gfx = row[6],
    }
  end
  return out
end

-- BattleAnimFrameData is a dw pointer table; GetBattleAnimFrame walks
-- 2-byte frames `db oamID, (flags << 6) | duration` until a terminator, so
-- the framesets end where the first one starts.  Four bytes are commands
-- rather than OAM ids (data/battle_anims/framesets.asm):
--   $FF oamend     -- hold the last frame
--   $FE oamrestart -- loop back to the first frame
--   $FD oamwait n  -- draw nothing for n ticks (two bytes)
--   $FC oamdelete  -- retire the object (one byte)
-- Reading $FC/$FD as OAM ids drew whatever row happened to sit at index
-- 252/253 -- the stray foot that showed up in Tackle and half the other
-- moves -- and then walked off two bytes misaligned, so every frame after
-- the terminator was the *next* frameset's bytes read as garbage.
function RomExtractorGen2:gen2AnimFramesets()
  local sym = self:symbol("BattleAnimFrameData")
  if not sym then return {} end
  local out = {}
  local ok, first = pcall(self.rom.word, self.rom, sym.bank, sym.address)
  if not ok then return out end
  local count = math.floor((first - sym.address) / 2)
  for id = 0, count - 1 do
    pcall(function()
      local address = self.rom:word(sym.bank, sym.address + id * 2)
      local frames, loop = {}, "hold"
      for _ = 1, 64 do
        local oam = self.rom:byte(sym.bank, address)
        if oam == 0xFF then loop = "hold"; break end
        if oam == 0xFE then loop = "restart"; break end
        if oam == 0xFC then loop = "delete"; break end
        local packed = self.rom:byte(sym.bank, address + 1)
        if oam == 0xFD then
          -- oamwait: no sprite for `packed` ticks
          frames[#frames + 1] = { wait = true, duration = packed }
        else
          -- GetBattleAnimFrame (33:$6716): duration = packed & $3F,
          -- flags = (packed & $C0) >> 1, i.e. bit 7 = Y flip, bit 6 = X flip
          frames[#frames + 1] = {
            oam = oam,
            duration = packed % 64,
            xflip = math.floor(packed / 64) % 2 == 1,
            yflip = math.floor(packed / 128) % 2 == 1,
          }
        end
        address = address + 2
      end
      if #frames > 0 then out[id] = { frames = frames, loop = loop } end
    end)
  end
  return out
end

function RomExtractorGen2:gen2AnimOam()
  local sym = self:symbol("BattleAnimOAMData")
  if not sym then return {} end
  local out = {}
  local ok, first = pcall(self.rom.word, self.rom,
    sym.bank, sym.address + 2)
  if not ok then return out end
  local count = math.floor((first - sym.address) / GEN2_ANIM.OAM_BYTES)
  for id = 0, count - 1 do
    pcall(function()
      local row = self.rom:bytes(sym.bank,
        sym.address + id * GEN2_ANIM.OAM_BYTES, GEN2_ANIM.OAM_BYTES)
      local address = row[3] + row[4] * 256
      local sprites = {}
      for i = 0, row[2] - 1 do
        local s = self.rom:bytes(sym.bank, address + i * 4, 4)
        sprites[i + 1] = {
          y = signedByte(s[1]), x = signedByte(s[2]),
          tile = s[3], attr = s[4],
        }
      end
      out[id] = { tile = row[1], sprites = sprites }
    end)
  end
  return out
end

-- AnimObjGFX rows are `db tiles, db bank, dw address`, and LoadBattleAnimGFX
-- routes them through DecompressRequest2bpp, so the blobs are LZ3.  Each
-- sheet is written as a 16-wide strip so the player can index it with a flat
-- tile number.
function RomExtractorGen2:gen2AnimGfx()
  local sym = self:symbol("AnimObjGFX")
  if not sym then return {} end
  local out = {}
  for id = 0, GEN2_ANIM.GFX_COUNT - 1 do
    local ok, row = pcall(self.rom.bytes, self.rom, sym.bank,
      sym.address + id * GEN2_ANIM.GFX_BYTES, GEN2_ANIM.GFX_BYTES)
    if not ok then break end
    local tiles = row[1]
    if tiles > 0 then
      local relative = ("battle/anims/gen2_%02d.png"):format(id)
      local saved = pcall(function()
        local address = row[3] + row[4] * 256
        local compressed = self.rom:bytes(row[2], address, 0x8000 - address)
        local raw = decompressLz3(compressed)
        local cols = math.min(GEN2_ANIM.SHEET_COLS, tiles)
        local rows = math.ceil(tiles / cols)
        local padded = {}
        for i = 1, cols * rows * 16 do padded[i] = raw[i] or 0 end
        -- OBJ color 0 is transparent on hardware, so matte every shade-0
        -- pixel rather than flood-filling in from the border
        self:saveImage(
          ImageWriter.decode2bpp(padded, cols * 8, rows * 8, true), relative)
        out[id] = { tiles = tiles, cols = cols,
                    image = "assets/generated/" .. relative }
      end)
      if not saved then out[id] = nil end
    end
  end
  return out
end

function RomExtractorGen2:gen2AnimPalettes()
  local sym = self:symbol("BattleObjectPals")
  if not sym then return {} end
  local out = {}
  for index = 0, GEN2_ANIM.OBJ_PALETTES - 1 do
    pcall(function()
      local colors = {}
      for slot = 0, 3 do
        colors[slot + 1] = gen2Rgb5(
          self.rom:word(sym.bank, sym.address + (index * 4 + slot) * 2))
      end
      out[index] = colors
    end)
  end
  return out
end

-- Name each object `function` slot from DoBattleAnimFrame's jumptable.  The
-- routines themselves are hand-written asm and cannot be ported as data, but
-- the names tell the player which motion to approximate.
function RomExtractorGen2:gen2AnimFunctions()
  local out = {}
  local byAddress = {}
  for name, entry in pairs(self.manifest.symbols or {}) do
    local prefix = name:match("^BattleAnimFunction_([%w_]+)$")
    if prefix and entry[1] == 51 then byAddress[entry[2]] = prefix end
  end
  local count = math.floor((GEN2_ANIM.FN_END - GEN2_ANIM.FN_TABLE) / 2)
  for id = 0, count - 1 do
    pcall(function()
      local address = self.rom:word(51, GEN2_ANIM.FN_TABLE + id * 2)
      out[id] = byAddress[address]
    end)
  end
  return out
end

function RomExtractorGen2:gen2BattleAnims()
  local sym = self:symbol("BattleAnimations")
  if not (sym and self.rom) then
    return { move = {}, misc = {}, effects = {} }
  end
  local scripts = {}
  local ok, first = pcall(self.rom.word, self.rom, sym.bank, sym.address)
  if ok then
    local count = math.floor((first - sym.address) / 2)
    for id = 1, count - 1 do
      pcall(function()
        local entry = self.rom:word(sym.bank, sym.address + id * 2)
        scripts[id] = self:gen2AnimScript(sym.bank, entry)
      end)
    end
  end
  local order = (self:constants() or {}).moveOrder or {}
  local moveAnims = {}
  for index, move in ipairs(order) do
    if scripts[index] then moveAnims[move] = index end
  end
  return {
    gen2 = true,
    scripts = scripts,
    moveAnims = moveAnims,
    objects = self:gen2AnimObjects(),
    functions = self:gen2AnimFunctions(),
    framesets = self:gen2AnimFramesets(),
    oam = self:gen2AnimOam(),
    gfx = self:gen2AnimGfx(),
    palettes = self:gen2AnimPalettes(),
    -- the ids BattleAnimations keeps past the last move
    misc = { throwPokeBall = 256, sendOutMon = 257 },
    move = {}, effects = {},
  }
end

-- Sequences the ROM never emits but hand-written port text does.
local GEN2_FONT_ALIASES = { ["\xc3\x97"] = 0xF1 }

function RomExtractorGen2:extractFontSheets()
  local fontSym = self:symbol("Font")
  local extraSym = self:symbol("FontExtra")
  if not (self.rom and fontSym and extraSym) then return false end
  return (pcall(function()
    local raw = self.rom:bytes(fontSym.bank, fontSym.address, GEN2_FONT_TILES * 8)
    local image = ImageWriter.blank(128, 64, 0, 0, 0, 0)
    for tile = 0, GEN2_FONT_TILES - 1 do
      local tileX, tileY = tile % 16 * 8, math.floor(tile / 16) * 8
      for y = 0, 7 do
        local row = raw[tile * 8 + y + 1] or 0
        for x = 0, 7 do
          if math.floor(row / 2 ^ (7 - x)) % 2 == 1 then
            image:setPixel(tileX + x, tileY + y, 0, 0, 0, 1)
          end
        end
      end
    end
    self:saveImage(image, "fonts/font.png")

    local shaded = ImageWriter.decode2bpp(
      self.rom:bytes(extraSym.bank, extraSym.address, GEN2_FONT_EXTRA_TILES * 16),
      128, 16)
    local extra = ImageWriter.blank(128, 16, 0, 0, 0, 0)
    for y = 0, 15 do
      for x = 0, 127 do
        if shaded:getPixel(x, y) < 0.5 then extra:setPixel(x, y, 0, 0, 0, 1) end
      end
    end
    local frameSym = self:symbol("Frames")
    if frameSym then
      -- Frames is 1bpp (gfx/frames/N.1bpp): nine frames of six tiles, eight
      -- bytes each.  Read as 2bpp it swallowed frame 2 as well and drew the
      -- text box border out of the interleaved halves of both.
      local frame = ImageWriter.decode1bpp(
        self.rom:bytes(frameSym.bank, frameSym.address, GEN2_FRAME_TILES * 8),
        GEN2_FRAME_TILES * 8, 8)
      for tile = 0, GEN2_FRAME_TILES - 1 do
        local slot = GEN2_FRAME_BASE_CODE - 0x60 + tile
        local dstX, dstY = slot % 16 * 8, math.floor(slot / 16) * 8
        for y = 0, 7 do
          for x = 0, 7 do
            local ink = frame:getPixel(tile * 8 + x, y) < 0.5
            extra:setPixel(dstX + x, dstY + y, 0, 0, 0, ink and 1 or 0)
          end
        end
      end
    end
    self:saveImage(extra, "fonts/font_extra.png")
  end))
end

-- The in-battle HUD overlay.  Gen 2 builds the same picture as Gen 1 out of
-- the same VRAM slots, just sourced differently and shifted by one tile:
--
--   LoadBattleFontsHPBar ($3E:4066) copies FontBattleExtra tiles 0-11 over
--   $60-$6B and tiles 16-18 over $70-$72;
--   LoadHPBar ($3E:4081) then overlays EnemyHPBarBorderGFX (1bpp, 4) at $6C,
--   HPExpBarBorderGFX (1bpp, 6) at $73 and ExpBarGFX (2bpp, 9) at $55.
--
-- pokered puts "HP" at $71 and the bar at $62 (cap) / $63+n (fill) / $6C
-- (nub); Gen 2 puts "HP" at $60 and the bar at $61 / $62+n / $6B.  The port's
-- HudTiles/drawHPBar speak the pokered layout, so this remaps Gen 2's tiles
-- into pokered's slots -- one table here instead of a generation branch in
-- every HUD draw call.
--
-- Without these four sheets a Gen 2-only install (Android, iOS) has NO HP
-- bar, no <LV> tile and no HUD underline at all: on a dev box that also has
-- a Gen 1 cache the version mount silently falls through to pokered's copies,
-- which is why this went unnoticed for so long.
local GEN2_HUD_TILES = 25            -- FontBattleExtra tiles _LoadFontsBattleExtra copies
local GEN2_HUD_SHEET_COLS = 15       -- font_battle_extra.png is 15x2 tiles from $62
local GEN2_EXP_BAR_TILES = 9         -- ExpBarGFX, LoadHPBar's `lb bc, BANK, 9`

-- code -> FontBattleExtra tile index.  $62-$6C is the bar in pokered order,
-- $71 is "HP", and $6D-$78 are the HUD chrome (mostly re-overlaid below).
local GEN2_HUD_MAP = {
  [0x62] = 1,                                     -- ":[" bar left cap
  [0x63] = 2, [0x64] = 3, [0x65] = 4, [0x66] = 5, -- fill 0-3 px
  [0x67] = 6, [0x68] = 7, [0x69] = 8, [0x6A] = 9, -- fill 4-7 px
  [0x6B] = 10,                                    -- fill 8 px (full)
  [0x6C] = 11,                                    -- right nub (bar types 0/2)
  [0x6D] = 13, [0x6E] = 14, [0x6F] = 15,          -- double bar, ":L", halfarrow
  [0x70] = 16, [0x71] = 0,  [0x72] = 18,          -- <to>, "HP", <ID>
  [0x73] = 19, [0x74] = 20, [0x75] = 21,
  [0x76] = 22, [0x77] = 23, [0x78] = 24,
}

function RomExtractorGen2:extractBattleHudSheets()
  local fbe = self:symbol("FontBattleExtra")
  local enemyBorder = self:symbol("EnemyHPBarBorderGFX")
  local hpExpBorder = self:symbol("HPExpBarBorderGFX")
  if not (self.rom and fbe and enemyBorder and hpExpBorder) then return false end
  return (pcall(function()
    -- Colour 0 goes TRANSPARENT, exactly as pokered's copies of these sheets
    -- are written (RomExtractor:raw2bpp "battle/font_battle_extra.png" with
    -- transparent = true, and raw1bpp for the three battle_hud pages).  On a
    -- white battle field an opaque shade-0 background is invisible, which is
    -- why the Gen 2 sheets got away without it -- but the HUD is drawn over
    -- the world in DRAMATIC_SHAPE's overworld battle, and there every tile
    -- became a white slab with its ink hidden inside it: the <LV> glyph, the
    -- HP bar's empty run and the whole underline row all painted out.
    local src = ImageWriter.decode2bpp(
      self.rom:bytes(fbe.bank, fbe.address, GEN2_HUD_TILES * 16),
      GEN2_HUD_TILES * 8, 8, true)

    -- $62-$7F, 15 tiles per row, exactly the shape pokered's sheet has so
    -- HudTiles.build's `per = width / 8` indexes it the same way.
    local sheet = ImageWriter.blank(GEN2_HUD_SHEET_COLS * 8, 16, 0, 0, 0, 0)
    for code, tile in pairs(GEN2_HUD_MAP) do
      local slot = code - 0x62
      ImageWriter.blit(sheet, src, slot % GEN2_HUD_SHEET_COLS * 8,
        math.floor(slot / GEN2_HUD_SHEET_COLS) * 8, tile * 8, 0, 8, 8)
    end
    self:saveImage(sheet, "battle/font_battle_extra.png")

    -- battle_hud_1 lands on $6D-$6F: the player bar's double-bar cap, the
    -- <LV> tile and the halfarrow.  LoadHPBar ($3E:4081) overlays
    -- EnemyHPBarBorderGFX's four 1bpp tiles over $6C-$6F, so tiles 1-3 of it
    -- ARE those three -- read them from there rather than guessing at
    -- FontBattleExtra's shaded lookalikes, which held a dashed rule where the
    -- solid cap belongs and a copy of the halfarrow sitting two rows high.
    local enemyBorderArt = ImageWriter.decode1bpp(
      self.rom:bytes(enemyBorder.bank, enemyBorder.address, 4 * 8), 32, 8, true)
    local hud1 = ImageWriter.blank(24, 8, 0, 0, 0, 0)
    for i = 0, 2 do
      ImageWriter.blit(hud1, enemyBorderArt, i * 8, 0, (i + 1) * 8, 0, 8, 8)
    end
    self:saveImage(hud1, "battle/battle_hud_1.png")

    -- HPExpBarBorderGFX is 1bpp: six tiles, 8 bytes each.  $73-$75 is the
    -- HUD's left edge and elbow, $76-$78 the underline and its tail.
    local border = ImageWriter.decode1bpp(
      self.rom:bytes(hpExpBorder.bank, hpExpBorder.address, 6 * 8), 48, 8, true)
    for page = 0, 1 do
      local hud = ImageWriter.blank(24, 8, 0, 0, 0, 0)
      for i = 0, 2 do
        ImageWriter.blit(hud, border, i * 8, 0, (page * 3 + i) * 8, 0, 8, 8)
      end
      self:saveImage(hud, "battle/battle_hud_" .. (page + 2) .. ".png")
    end

    -- ExpBarGFX -> VRAM $55, the seven partial widths PlaceExpBar picks with
    -- `add $54`.  0 and 8 pixels reuse the HP bar's own empty/full tiles, so
    -- only these seven need a sheet of their own.
    local expBar = self:symbol("ExpBarGFX")
    if expBar then
      self:saveImage(ImageWriter.decode2bpp(
        self.rom:bytes(expBar.bank, expBar.address, GEN2_EXP_BAR_TILES * 16),
        GEN2_EXP_BAR_TILES * 8, 8, true), "battle/exp_bar.png")
    end
  end))
end

-- Which byte sequence draws which glyph.  Only codes the two sheets cover
-- ($60-$FF) belong here: everything below is a control code or a macro the
-- runtime substitutes, and a macro in this table would draw one wrong tile
-- instead of its expansion.  The scaffold charmap only fills gaps, since it
-- spells most codes back as their own "{BYTE:xx}" token.
function RomExtractorGen2:gen2FontCharmap()
  local entries, seen = {}, {}
  local function add(seq, code)
    if type(seq) ~= "string" or seq == "" or seen[seq] then return end
    if code < 0x60 or code > 0xFF then return end
    if seq:match("^<.*>$") or seq:match("^{BYTE:") then return end
    seen[seq] = true
    entries[#entries + 1] = { seq = seq, code = code }
  end
  for code = 0x60, 0xFF do add(GEN2_CHARMAP[code], code) end
  for seq, code in pairs(GEN2_FONT_ALIASES) do add(seq, code) end
  for key, seq in pairs(self:readSourceTable("charmap") or {}) do
    local code = tonumber(key)
    if code then add(seq, code) end
  end
  -- longest sequence first so the renderer matches 'd / 's / PK greedily
  table.sort(entries, function(a, b)
    if #a.seq == #b.seq then return a.code < b.code end
    return #a.seq > #b.seq
  end)
  return entries
end

function RomExtractorGen2:extractRuntimeScaffolds()
  self:beginStage("Gen2 runtime scaffolds")
  local constants = self:constants()
  local maps = self:readSourceTable("maps")
  local tilesetManifest = self.manifest.tilesets or {}

  local tilesets = {}
  local tilesetIds = {}
  for _, id in ipairs(constants.tilesetOrder or {}) do tilesetIds[id] = true end
  for _, map in pairs(maps) do
    if type(map) == "table" and type(map.tileset) == "string" then
      tilesetIds[map.tileset] = true
    end
  end
  for id in pairs(tilesetManifest) do
    if type(id) == "string" and id ~= "source" then
      tilesetIds[id] = true
    end
  end
  for _, row in ipairs(gen2TilesetRows(self.manifest.symbols)) do
    tilesetIds["Tileset" .. row[3]] = true
  end
  if tilesetIds.HOUSE or tilesetIds.TilesetPlayersHouse
      or tilesetIds.TilesetTraditionalHouse then
    tilesetIds.HOUSE = true
  end
  if not next(tilesetIds) then
    tilesetIds.OVERWORLD = true
  end
  local orderedTilesets = {}
  for id in pairs(tilesetIds) do orderedTilesets[#orderedTilesets + 1] = id end
  table.sort(orderedTilesets)
  for _, id in ipairs(orderedTilesets) do
    local spec = tilesetManifest[id] or tilesetManifest[id:lower()] or {}
    local gfxId = id
    if id == "HOUSE" then
      spec = tilesetManifest.TilesetTraditionalHouse
          or tilesetManifest.TilesetHouse or spec
      gfxId = (tilesetManifest.TilesetTraditionalHouse and "TilesetTraditionalHouse")
          or (tilesetManifest.TilesetHouse and "TilesetHouse")
          or gfxId
    end
    local base = spec.imageBase or (id == "HOUSE" and "traditionalhouse"
                                   or id:gsub("^Tileset", ""):lower())
    local gfx = self:symbol(gfxId .. "GFX")
    local meta = self:symbol(gfxId .. "Meta")
    local coll = self:symbol(gfxId .. "Coll")
    local imagePath = "assets/generated/tilesets/" .. base .. ".png"

    if gfx and meta and coll and self.rom then
      local dcOk, pixels = pcall(function()
        local compressed = self.rom:bytes(gfx.bank, gfx.address, 0x8000 - gfx.address)
        return decompressLz3(compressed)
      end)
      if not dcOk or type(pixels) ~= "table" then pixels = {} end
      local width = tonumber(spec.imageWidth) or 128
      local height = tonumber(spec.imageHeight) or 128
      if #pixels < 256 then
        writeGeneratedTilesetPlaceholder(imagePath)
        width, height = 128, 128
      else
        width, height = inferTilesetDimensions(#pixels)
        local expectedBytes = width * height / 4
        while #pixels < expectedBytes do pixels[#pixels + 1] = 0 end
        while #pixels > expectedBytes do pixels[#pixels] = nil end
        local imgOk = pcall(function()
          ImageWriter.save(ImageWriter.decode2bpp(pixels, width, height), imagePath)
        end)
        if not imgOk then writeGeneratedTilesetPlaceholder(imagePath); width, height = 128, 128 end
      end

      -- <Tileset>Coll immediately follows <Tileset>Meta, so the gap between
      -- them is the real block count; the old fixed 0x80 over-read every
      -- 64 block indoor tileset by a kilobyte of collision data.
      local blockCount = tonumber(spec.blockCount)
      if not blockCount and coll.bank == meta.bank and coll.address > meta.address then
        blockCount = math.floor((coll.address - meta.address) / 16)
      end
      blockCount = blockCount or 0x80
      local blocksRaw = self.rom:bytes(meta.bank, meta.address, blockCount * 16)
      local blocks = {}
      for offset = 1, #blocksRaw, 16 do
        local block = {}
        for pos = offset, offset + 15 do block[#block + 1] = blocksRaw[pos] end
        blocks[#blocks + 1] = block
      end

      -- Gen2 collision is per 16x16 cell, not per 8x8 tile: <Tileset>Coll
      -- holds 4 classes per block in NW/NE/SW/SE order, and
      -- CollisionPermissionTable says which classes are land or water
      -- (GetCoordTileCollision / GetTilePermission).
      local classes = self:gen2CollisionClasses()
      local collision = {}
      local ok, collRaw = pcall(function()
        return self.rom:bytes(coll.bank, coll.address, blockCount * 4)
      end)
      if ok and type(collRaw) == "table" then collision = collRaw end

      tilesets[id] = {
        id = id,
        source = "ROM:Tilesets[" .. id .. "]",
        image = imagePath,
        imageWidth = width,
        imageHeight = height,
        tilesPerRow = width / 8,
        blocks = blocks,
        collision = collision,
        walkable = classes.land,
        waterTiles = classes.water,
        shoreTiles = {},
        grassTile = GEN2_COLL_TALL_GRASS,
        grassTiles = self:gen2GrassClasses(),
        counterTiles = GEN2_COUNTER_CLASSES,
        doorTiles = {},
        warpTiles = {},
        animation = self:gen2TilesetAnimation(id),
      }

    else
      local fallbackImage = imagePath
      if id == "TilesetPlayersHouse" and not tilesets.TilesetHouse then
        fallbackImage = "assets/generated/tilesets/house.png"
      end
      tilesets[id] = {
        id = id,
        source = "Gen2 scaffold",
        image = fallbackImage,
        imageWidth = 128,
        imageHeight = 128,
        tilesPerRow = 16,
        blocks = {},
        walkable = {},
        counterTiles = GEN2_COUNTER_CLASSES,
        doorTiles = {},
        warpTiles = {},
        animation = {},
      }
    end
    -- Augment with Gen2 GBC palette data (palMap + palColors) from ROM
    if self.rom then
      local palSym = self:symbol(gfxId .. "PalMap")
      if palSym then
        local palOk, palRaw = pcall(function()
          return self.rom:bytes(palSym.bank, palSym.address, 48)
        end)
        if palOk and type(palRaw) == "table" then
          local palMap = {}
          for _, byte in ipairs(palRaw) do
            palMap[#palMap + 1] = byte % 16
            palMap[#palMap + 1] = math.floor(byte / 16)
          end
          local setIdx = gen2PaletteSetIndex(id)
          local colOk, colRaw = pcall(function()
            return self.rom:bytes(GEN2_BG_PALETTE_BANK,
                                  GEN2_BG_PALETTE_ADDR + setIdx * 56, 56)
          end)
          if colOk and type(colRaw) == "table" then
            local palColors = {}
            for p = 0, 6 do
              local pal = {}
              for c = 0, 3 do
                local lo = colRaw[p * 8 + c * 2 + 1]
                local hi = colRaw[p * 8 + c * 2 + 2]
                local val = lo + hi * 256
                pal[#pal + 1] = {
                  math.floor(val % 32 * 255 / 31),
                  math.floor(math.floor(val / 32) % 32 * 255 / 31),
                  math.floor(math.floor(val / 1024) % 32 * 255 / 31),
                }
              end
              palColors[#palColors + 1] = pal
            end
            tilesets[id].palMap = palMap
            tilesets[id].palColors = palColors
          end
        end
      end
    end
  end
  self:write("tilesets", tilesets)

  local sprites = {}
  local spriteIds = {}
  for _, id in ipairs(constants.spriteOrder or {}) do
    spriteIds[id] = true
  end
  for _, map in pairs(maps) do
    for _, obj in ipairs((type(map) == "table" and map.objects) or {}) do
      -- SPRITE_VAR_nn is a wVariableSprites slot and SPRITE_MON_BREED_n is a
      -- live day-care species, neither of them a sheet: giving either a
      -- placeholder def here would stop the runtime resolving it
      if type(obj) == "table" and type(obj.sprite) == "string"
         and not obj.sprite:match("^SPRITE_VAR_%d+$")
         and not obj.sprite:match("^SPRITE_MON_BREED_%d$") then
        spriteIds[obj.sprite] = true
      end
    end
  end
  spriteIds.SPRITE_RED = true
  spriteIds.SPRITE_SEEL = true
  spriteIds.SPRITE_RED_BIKE = true
  spriteIds.SPRITE_BIRD = true
  local orderedSprites = {}
  for id in pairs(spriteIds) do orderedSprites[#orderedSprites + 1] = id end
  table.sort(orderedSprites)

  -- Every overworld sprite sheet, read straight from the ROM's OverworldSprites
  -- table rather than a hand written symbol list, so NPCs, item balls and fruit
  -- trees all get their own graphics instead of falling back to the player.
  local gen2SpriteImageMap = {}
  local gen2SpriteFrames = {}
  local gen2SpritePalIdx = {}
  local gen2SpriteIndex = {}
  -- Big Snorlax / Lapras use FacingBigDollSymmetric: 8 unique 8x8 tiles in a
  -- 16x32 strip, mirrored horizontally to form a 32x32 body covering 2x2 cells.
  local BIG_SPRITE_IDS = {
    SPRITE_BIG_SNORLAX = true,
    SPRITE_BIG_LAPRAS = true,
  }
  for _, row in pairs(self:gen2OverworldSprites()) do
    local ok, raw = pcall(function()
      return self.rom:bytes(row.bank, row.address, row.bytes)
    end)
    if ok and type(raw) == "table" and #raw >= row.bytes then
      local width, height = row.width, row.height
      local frames = row.frames
      local img = ImageWriter.decode2bpp(raw, width, height)
      -- Expand symmetric big dolls to a real 32x32 sheet so the renderer can
      -- draw the full body (not just the top-left 16x16 face tile).
      if BIG_SPRITE_IDS[row.id] and width == 16 and height >= 32 then
        local left = ImageWriter.decode2bpp(raw, 16, 32)
        -- composite left | mirror(left) into 32x32
        if ImageWriter.mirrorComposite32 then
          img = ImageWriter.mirrorComposite32(left)
        else
          -- Inline: left is 16x32 ImageData; build 32x32 by copy + mirror.
          local ok2, big = pcall(function()
            local out = love.image.newImageData(32, 32)
            for y = 0, 31 do
              for x = 0, 15 do
                local r, g, b, a = left:getPixel(x, y)
                out:setPixel(x, y, r, g, b, a)
                out:setPixel(31 - x, y, r, g, b, a)
              end
            end
            return out
          end)
          if ok2 and big then img = big end
        end
        width, height, frames = 32, 32, 1
        row.big = true
      end
      self:saveImage(img, row.file)
      spriteIds[row.id] = true
      gen2SpriteImageMap[row.id] = "assets/generated/" .. row.file
      gen2SpriteFrames[row.id] = frames
      gen2SpritePalIdx[row.id] = row.palette
      gen2SpriteIndex[row.id] = row.index
      if row.big then
        -- remembered below when writing sprites[]
        gen2SpriteImageMap[row.id .. "__big"] = true
      end
    end
  end
  orderedSprites = {}
  for id in pairs(spriteIds) do orderedSprites[#orderedSprites + 1] = id end
  table.sort(orderedSprites)

  -- SPRITE_POKEMON objects have no sheet of their own: GetMonSprite.Mon hands
  -- the species to LoadOverworldMonIcon, so they wear the 16x32 two-frame
  -- party menu icon extractIcons already wrote.  Those icons are baked in the
  -- mon's own palette with a transparent colour 0, hence trueColor.
  local speciesOrder = constants.speciesOrder or {}
  local monIconDefs = {}
  -- Every species, not just the SpriteMons rows a map object happens to name:
  -- the day-care yard picks its two sheets from whatever is boarded, so any of
  -- the 251 can be asked for and a missing def falls back to the player sheet.
  for species = 1, #speciesOrder do
    monIconDefs[gen2MonSpriteId(species)] =
      "assets/generated/icons/" .. speciesOrder[species]:lower() .. ".png"
    spriteIds[gen2MonSpriteId(species)] = true
  end
  orderedSprites = {}
  for id in pairs(spriteIds) do orderedSprites[#orderedSprites + 1] = id end
  table.sort(orderedSprites)

  -- Read Gen2 OBJ palettes (MapObjectPals at 02:78ae)
  local gen2ObjPals = {}   -- 0-based: gen2ObjPals[i] = 4-color palette
  if self.rom then
    local ok1, palData = pcall(function()
      return self.rom:bytes(2, 0x78ae, 128)  -- 8 palettes x 4 colors x 2 bytes
    end)
    if ok1 and type(palData) == "table" then
      for p = 0, 7 do
        local pal = {}
        for c = 0, 3 do
          local lo = palData[p * 8 + c * 2 + 1]
          local hi = palData[p * 8 + c * 2 + 2]
          local val = lo + hi * 256
          pal[#pal + 1] = {
            math.floor(val % 32 * 255 / 31),
            math.floor(math.floor(val / 32) % 32 * 255 / 31),
            math.floor(math.floor(val / 1024) % 32 * 255 / 31),
          }
        end
        gen2ObjPals[p] = pal
      end
    end
  end

  for _, id in ipairs(orderedSprites) do
    local img = monIconDefs[id] or gen2SpriteImageMap[id]
       or "assets/generated/sprites/placeholder_sprite.png"
    local spriteDef = {
      id = id,
      source = "Gen2 scaffold",
      image = img,
      -- the OverworldSprites row number, i.e. the object_event sprite byte:
      -- `variablesprite` names its replacement sheet by that number
      index = gen2SpriteIndex[id],
      frames = gen2SpriteFrames[id] or 6,
      walker = (gen2SpriteFrames[id] or 6) >= 6,
    }
    if gen2SpriteImageMap[id .. "__big"] then
      spriteDef.big = true
      spriteDef.width = 32
      spriteDef.height = 32
      spriteDef.frames = 1
      spriteDef.walker = false
    end
    if monIconDefs[id] then
      spriteDef.frames, spriteDef.walker = 2, false
      spriteDef.monIcon, spriteDef.trueColor = true, true
    end
    -- Attach the correct Gen2 OBJ palette so the sprite renders in proper GBC colors
    local pal = gen2ObjPals[gen2SpritePalIdx[id] or 0]
    if pal and not monIconDefs[id] then spriteDef.gen2ObjPal = pal end
    sprites[id] = spriteDef
  end
  self:write("sprites", sprites)

  local fontFromRom = self:extractFontSheets()
  self:extractBattleHudSheets()
  self:extractTrainerCardBadges()
  self:extractUnownPuzzle()
  self:extractUnownDex()
  if not fontFromRom then
    -- keep the placeholders so RomImporter's readiness check still passes
    self:copyAsset("assets/logo/pokemon_logo.png",
      "assets/generated/fonts/font.png")
    self:copyAsset("assets/logo/pokemon_logo.png",
      "assets/generated/fonts/font_extra.png")
  end
  self:write("font", {
    -- Font.load falls back to LOVE's built-in raster font on "Gen2 scaffold",
    -- so this string has to change once the real sheets are on disk
    source = fontFromRom and "ROM:Font, FontExtra, Frames" or "Gen2 scaffold",
    image = "assets/generated/fonts/font.png",
    imageExtra = "assets/generated/fonts/font_extra.png",
    mainBase = 0x80,
    extraBase = 0x60,
    glyphsPerRow = 16,
    charmap = self:gen2FontCharmap(),
  })

  -- TypeMatchups: db attacker, defender, multiplier(x10); $fe splits off the
  -- rows Foresight cancels, $ff ends the table.
  local typeChart = { source = "ROM:TypeMatchups", matchups = {}, types = {} }
  for value, typeName in pairs(GEN2_TYPES) do
    typeChart.types[typeName] = {
      name = typeName,
      category = value >= GEN2_SPECIAL_TYPE and "special" or "physical",
    }
  end
  local matchupSym = self:symbol("TypeMatchups")
  if matchupSym and self.rom then
    local address = matchupSym.address
    for _ = 1, 256 do
      local first = self.rom:byte(matchupSym.bank, address)
      if first == 0xFF then break end
      if first == 0xFE then
        address = address + 1
      else
        local row = self.rom:bytes(matchupSym.bank, address, 3)
        local attacker, defender = GEN2_TYPES[row[1]], GEN2_TYPES[row[2]]
        if attacker and defender then
          typeChart.matchups[#typeChart.matchups + 1] = {
            attacker = attacker, defender = defender, multiplier = row[3],
          }
        end
        address = address + 3
      end
    end
  end
  self:write("type_chart", typeChart)

  local trainers = {}
  local trainerSource = self.manifest.trainers
  if type(trainerSource) == "table" then
    if #trainerSource > 0 then
      for index, label in ipairs(trainerSource) do
        local id = "OPP_" .. tostring(label)
        trainers[id] = {
          id = id,
          index = index,
          name = tostring(label),
          source = "Gen2 scaffold",
          pic = "assets/generated/battle/trainers/placeholder.png",
          parties = {},
        }
      end
    else
      trainers = copy(trainerSource)
    end
  end
  -- Real classes and parties from TrainerGroups replace the scaffold rows.
  for id, def in pairs(self:gen2Trainers().byClass) do
    local pic = self:gen2TrainerPic(def.index)
    -- the pic is already baked through TrainerPalettes; trueColor keeps
    -- BattleState from re-quantizing it back to four shades
    def.trueColor = pic ~= nil or nil
    def.pic = pic or "assets/generated/battle/trainers/placeholder.png"
    trainers[id] = def
  end
  trainers.OPP_PROF_OAK = trainers.OPP_PROF_OAK or {
    id = "OPP_PROF_OAK",
    index = 0,
    name = "PROF_OAK",
    source = "Gen2 scaffold",
    parties = {},
  }
  trainers.OPP_PROF_OAK.pic = self:gen2TrainerPic(GEN2_CLASS_POKEMON_PROF)
    or "assets/generated/battle/trainers/prof_oak.png"
  trainers.OPP_PROF_OAK.trueColor = true
  trainers.OPP_RIVAL1 = trainers.OPP_RIVAL1 or {
    id = "OPP_RIVAL1",
    index = 0,
    name = "RIVAL1",
    source = "Gen2 scaffold",
    parties = {},
  }
  trainers.OPP_RIVAL1.pic = self:gen2TrainerPic(GEN2_CLASS_RIVAL1)
    or "assets/generated/battle/trainers/rival1.png"
  trainers.OPP_RIVAL1.trueColor = true
  self:write("trainers", trainers)

  self:write("battle_anims", self:gen2BattleAnims())
  self:tick("Gen2 runtime scaffolds", 1, 1)
end

-- The pack picture is four raw 15-tile images behind PackGFXPointers;
-- DrawPackGFX selects one with `and 3` and PlacePackGFX lays it out 5 tiles
-- across by 3 down, row-major, so it is not a column-major pic.
local GEN2_PACK_IMAGES = 4
local GEN2_PACK_TILES_WIDE = 5
local GEN2_PACK_TILES_HIGH = 3

function RomExtractorGen2:gen2PackArt()
  local sym = self:symbol("PackGFXPointers")
  if not sym or not self.rom then return end
  for index = 0, GEN2_PACK_IMAGES - 1 do
    pcall(function()
      local address = self.rom:word(sym.bank, sym.address + index * 2)
      local raw = self.rom:bytes(sym.bank, address,
        GEN2_PACK_TILES_WIDE * GEN2_PACK_TILES_HIGH * 16)
      self:saveImage(
        ImageWriter.decode2bpp(raw, GEN2_PACK_TILES_WIDE * 8, GEN2_PACK_TILES_HIGH * 8),
        string.format("ui/pack_%d.png", index))
    end)
  end
end

function RomExtractorGen2:extractIntroAssetsFromRom()
  self:beginStage("Gen2 intro assets (ROM)")
  local placeholder = "assets/logo/pokemon_logo.png"

  -- Oak and the rival in the speech are the PokemonProf and Rival1 trainer
  -- class pics.  The Gen1 names this used to read (OakSpriteGFX, BluePic)
  -- exist in Gold too but hold unrelated data, and Rom.decompressPic is the
  -- Gen1 codec, so both came out as noise.
  local wroteOak = self:gen2TrainerPic(GEN2_CLASS_POKEMON_PROF,
                                       "battle/trainers/prof_oak.png") ~= nil
  local wroteRival = self:gen2TrainerPic(GEN2_CLASS_RIVAL1,
                                         "battle/trainers/rival1.png") ~= nil
  if not wroteOak then
    self:copyAsset(placeholder, "assets/generated/battle/trainers/prof_oak.png")
  end
  if not wroteRival then
    self:copyAsset(placeholder, "assets/generated/battle/trainers/rival1.png")
  end
  self:gen2PackArt()

  self:tick("Gen2 intro assets (ROM)", 1, 1)
end

-- ---------------------------------------------------------------------------
-- audio
--
-- Gen2 runs Gen1's sound driver from bank $3A with a wider command set
-- (audio/engine.asm MusicCommands).  Music, Cries and SFX are three tables of
-- `db bank, dw address` rows pointing at song headers, and a header has the
-- same `db (channels-1) << 6 | channel, dw address` shape Gen1 used, so
-- ChipSynth reads both generations through one headerChannels.  Only the note
-- stream itself differs, which is why every def here carries engine = "gen2".
-- ---------------------------------------------------------------------------

-- Each table runs until whatever symbol follows it in the same bank
-- (Music_Nothing's own header sits directly after Music, for instance).
function RomExtractorGen2:gen2AudioRows(sym)
  local stop = 0x8000
  for _, location in pairs(self.symbols or {}) do
    if type(location) == "table" and tonumber(location[1]) == sym.bank then
      local address = tonumber(location[2])
      if address and address > sym.address and address < stop then
        stop = address
      end
    end
  end
  return math.floor((stop - sym.address) / 3)
end

-- (bank, address) -> the `prefix`ed symbol naming it, skipping local labels
-- and the per-channel streams the header itself points at.
function RomExtractorGen2:gen2AudioNames(prefix)
  local byAddress = {}
  for name, location in pairs(self.symbols or {}) do
    if type(name) == "string" and type(location) == "table"
        and name:sub(1, #prefix) == prefix
        and not name:find(".", 1, true)
        and not name:find("_Ch%d+$") then
      local bank, address = tonumber(location[1]), tonumber(location[2])
      if bank and address then byAddress[bank * 0x10000 + address] = name end
    end
  end
  return byAddress
end

-- `banks` collects every ROM bank the defs reach into, so the caller knows
-- which 16K slices must ship in programs.bin.
function RomExtractorGen2:gen2AudioTable(tableName, prefix, banks)
  local defs, index = {}, {}
  local sym = self:symbol(tableName)
  if not (sym and self.rom) then return defs, index end
  local names = self:gen2AudioNames(prefix)
  pcall(function()
    for row = 0, self:gen2AudioRows(sym) - 1 do
      local bank = self.rom:byte(sym.bank, sym.address + row * 3)
      local address = self.rom:word(sym.bank, sym.address + row * 3 + 1)
      local name = address >= 0x4000 and address < 0x8000
        and names[bank * 0x10000 + address] or nil
      if name then
        defs[name] = { bank = bank, address = address, engine = "gen2" }
        index[tostring(row)] = name
        banks[bank] = true
      end
    end
  end)
  return defs, index
end

-- Six drumkits of thirteen samples; `togglenoise <kit>` picks one at runtime
-- and a noise note's high nibble is the sample id within it.  Unlike Gen1's
-- SFX_* drums these are raw stream pointers, not channel headers.
function RomExtractorGen2:gen2Drumkits(banks)
  local sym = self:symbol("Drumkits")
  if not (sym and self.rom) then return nil end
  local kits = {}
  local ok = pcall(function()
    for kit = 0, 5 do
      local base = self.rom:word(sym.bank, sym.address + kit * 2)
      if base < 0x4000 or base >= 0x8000 then return end
      local drums = {}
      for drum = 1, 13 do
        local address = self.rom:word(sym.bank, base + (drum - 1) * 2)
        if address >= 0x4000 and address < 0x8000 then
          drums[tostring(drum)] = { bank = sym.bank, address = address }
        end
      end
      kits[tostring(kit)] = drums
    end
  end)
  if not (ok and next(kits)) then return nil end
  banks[sym.bank] = true
  return kits
end

-- The port asks for SFX by the gen-1 labels its call sites were written
-- against; map each onto the Gold sample that plays in the same situation.
RomExtractorGen2.GEN2_SFX_ALIASES = {
  -- Sfx_ReadText and Sfx_ReadText2 sit at the same address (3c:$4950), so
  -- which of the two names the extracted table ends up carrying depends on
  -- `pairs` order; chain them together so the alias resolves either way.
  Press_AB = "Sfx_ReadText2", Sfx_ReadText2 = "Sfx_ReadText",
  Menu = "Sfx_Menu", Tink = "Sfx_Wrong",
  Wrong = "Sfx_Wrong", Collision = "Sfx_Bump", Ledge_Jump = "Sfx_JumpOverLedge",
  Go_Inside = "Sfx_EnterDoor", Go_Outside = "Sfx_ExitBuilding",
  Enter_Door = "Sfx_EnterDoor", Save = "Sfx_Save", Run = "Sfx_Run",
  Get_Item1 = "Sfx_Item", Get_Item2 = "Sfx_Item", Get_Key_Item = "Sfx_KeyItem",
  Level_Up = "Sfx_LevelUp", Caught_Mon = "Sfx_CaughtMon",
  Dex_Page_Added = "Sfx_LevelUp", Pokeflute = "Sfx_Pokeflute",
  Heal_HP = "Sfx_Potion", Faint_Fall = "Sfx_Faint", Ball_Poof = "Sfx_BallPoof",
  Ball_Toss = "Sfx_ThrowBall", Ball_Wobble = "Sfx_BallWobble",
  Cut = "Sfx_Cut", Shrink = "Sfx_Squeak", Swap = "Sfx_SwitchPokemon",
  Withdraw_Deposit = "Sfx_Transaction", Trade_Machine = "Sfx_GiveTrademon",
  Teleport_Enter1 = "Sfx_WarpTo", Teleport_Exit1 = "Sfx_WarpFrom",
  Teleport_Exit2 = "Sfx_WarpFrom", Turn_On_PC = "Sfx_BootPc",
  Shut_Down_PC = "Sfx_ShutDownPc", Choose_PC_Option = "Sfx_ChoosePcOption",
  Slots_New_Spin = "Sfx_SlotMachineStart", Slots_Stop_Wheel = "Sfx_StopSlot",
  Slots_Reward = "Sfx_GetCoinFromSlots", Safari_Zone_PA = "Sfx_Fanfare2",
  Intro_Crash = "Sfx_GsIntroCharizardFireball",
  Intro_Whoosh = "Sfx_GsIntroPokemonAppears", Shooting_Star = "Sfx_Shine",
  Super_Effective = "Sfx_SuperEffective", Damage = "Sfx_Damage",
  Not_Very_Effective = "Sfx_NotVeryEffective", Exp_Bar = "Sfx_ExpBar",
  Get_Badge = "Sfx_GetBadge", Get_TM = "Sfx_GetTm",
  Egg_Crack = "Sfx_EggCrack", Egg_Hatch = "Sfx_EggHatch",
  Healing_Machine = "Sfx_PokeballsPlacedOnTable",
  Pokedex_Rating = "Sfx_DexFanfare230Plus", Fanfare = "Sfx_Fanfare",
}

-- Scene themes the engine asks for by role, and the battle set.  Anything
-- missing from the ROM tables is dropped rather than left dangling.
RomExtractorGen2.GEN2_SONG_ROLES = {
  battle = {
    wild = "Music_JohtoWildBattle", trainer = "Music_JohtoTrainerBattle",
    gym = "Music_JohtoGymBattle", final = "Music_ChampionBattle",
    wildWin = "Music_WildPokemonVictory",
    trainerWin = "Music_TrainerVictory",
    gymWin = "Music_GymLeaderVictory", finalWin = "Music_GymLeaderVictory",
  },
  special = {
    heal = "Music_HealPokemon", title = "Music_TitleScreen",
    credits = "Music_Credits", hallOfFame = "Music_HallOfFame",
    introBattle = "Music_JohtoWildBattle", oakRoute = "Music_Route29",
    bike = "Music_Bicycle", surf = "Music_Surf", evolution = "Music_Evolution",
    meetEvil = "Music_LookRocket", meetFemale = "Music_LookLass",
    meetMale = "Music_LookYoungster",
  },
}

function RomExtractorGen2:extractAudio()
  self:beginStage("Gen2 audio")
  local banks = {}
  local songs, musicIndex = self:gen2AudioTable("Music", "Music_", banks)
  local sfx, sfxIndex = self:gen2AudioTable("SFX", "Sfx_", banks)
  local cryDefs, cryIndex = self:gen2AudioTable("Cries", "Cry", banks)
  local drumkits = self:gen2Drumkits(banks)
  local waves = self:symbol("WaveSamples")
  if waves then banks[waves.bank] = true end

  if not (next(songs) and next(sfx) and waves) then
    Logger.warn("Gen2 audio: sound tables missing, using the scaffold")
    return self:extractAudioScaffold()
  end

  -- one flat blob of the 16K banks the sound data lives in, indexed by
  -- bankOrder exactly like the Gen1 importer's programs.bin
  local bankOrder, chunks = {}, {}
  for bank = 0, 0x7F do
    if banks[bank] then bankOrder[#bankOrder + 1] = bank end
  end
  for index, bank in ipairs(bankOrder) do
    local first = bank * 0x4000 + 1
    chunks[index] = self.rom.data:sub(first, first + 0x3FFF)
  end
  local written, writeError = require("src.import.CacheFs")
    .write("assets/generated/audio/programs.bin", table.concat(chunks))
  if not written then
    Logger.warn("Gen2 audio: programs.bin failed (%s), using the scaffold",
                tostring(writeError))
    return self:extractAudioScaffold()
  end

  -- PokemonCries rows are `dw cryId, dw pitch, dw length` in species order
  local cries = {}
  local pokemonCries = self:symbol("PokemonCries")
  if pokemonCries then
    pcall(function()
      for index, species in ipairs(self:constants().speciesOrder or {}) do
        local row = pokemonCries.address + (index - 1) * 6
        local name = cryIndex[tostring(self.rom:word(pokemonCries.bank, row))]
        if name and cryDefs[name] then
          cries[species] = {
            header = cryDefs[name],
            pitch = self.rom:word(pokemonCries.bank, row + 2),
            length = self.rom:word(pokemonCries.bank, row + 4),
          }
        end
      end
    end)
  end

  -- map header byte 6 is the song index; towns and routes double as the set
  -- the bike and surf themes are allowed to replace
  local mapSongs, outdoorSongs = {}, {}
  local _, headerByLabel = self:gen2MapIndex()
  for mapId, def in pairs(self:readSourceTable("maps")) do
    local label = type(def) == "table" and type(def.source) == "string"
      and def.source:match("^SYMBOL:(.+)_MapAttributes$") or nil
    local header = label and headerByLabel[label]
    local song = header and musicIndex[tostring(header.music)]
    if song then
      mapSongs[mapId] = song
      -- environment 1/2 are TOWN and ROUTE: the maps the bike and surf
      -- themes are allowed to take over
      if header.environment == 1 or header.environment == 2 then
        outdoorSongs[song] = true
      end
    end
  end

  -- Aliases may chain (Dex_Page_Added -> Level_Up -> Sfx_LevelUp), so resolve
  -- each one down to a name the ROM table actually has rather than reading
  -- whatever `pairs` happened to insert first.
  for name, alias in pairs(RomExtractorGen2.GEN2_SFX_ALIASES) do
    local target, hops = alias, 0
    while sfx[target] == nil and RomExtractorGen2.GEN2_SFX_ALIASES[target]
          and hops < 8 do
      target = RomExtractorGen2.GEN2_SFX_ALIASES[target]
      hops = hops + 1
    end
    if sfx[target] then
      sfx[name] = sfx[target]
    else
      Logger.warn("Gen2 audio: sfx alias %s -> %s is not in the ROM table",
                  name, alias)
    end
  end
  local roles = {}
  for group, entries in pairs(RomExtractorGen2.GEN2_SONG_ROLES) do
    roles[group] = {}
    for role, name in pairs(entries) do
      if songs[name] then roles[group][role] = name end
    end
  end

  self:write("audio", {
    source = "canonical Pokemon Gold ROM sound programs",
    runtime = true,
    gen2 = true,
    programFile = "assets/generated/audio/programs.bin",
    bankOrder = bankOrder,
    waveBanks = {
      -- WaveSamples holds ten distinct 16-byte waves, not Gen1's five
      gen2 = { bank = waves.bank, address = waves.address, count = 10 },
    },
    drumkits = drumkits and { gen2 = drumkits } or nil,
    songs = songs,
    sfx = sfx,
    cries = cries,
    musicIndex = musicIndex,
    sfxIndex = sfxIndex,
    cryIndex = cryIndex,
    mapSongs = mapSongs,
    outdoorSongs = outdoorSongs,
    battle = roles.battle,
    special = roles.special,
    fanfares = {
      Sfx_Item = true, Sfx_KeyItem = true, Sfx_CaughtMon = true,
      Sfx_Fanfare = true, Sfx_Fanfare2 = true, Sfx_GetBadge = true,
      Sfx_GetTm = true, Sfx_GetEgg = true, Sfx_Evolved = true,
      Sfx_LevelUp = true, Sfx_Pokeflute = true,
      Level_Up = true, Caught_Mon = true, Get_Item1 = true, Get_Item2 = true,
      Get_Key_Item = true, Pokeflute = true, Dex_Page_Added = true,
    },
  })
  local counts = { 0, 0, 0 }
  for _ in pairs(songs) do counts[1] = counts[1] + 1 end
  for _ in pairs(sfx) do counts[2] = counts[2] + 1 end
  for _ in pairs(cries) do counts[3] = counts[3] + 1 end
  Logger.info("Gen2 audio: %d songs, %d sfx, %d cries from %d banks",
              counts[1], counts[2], counts[3], #bankOrder)
  self:tick("Gen2 audio", 1, 1)
end

function RomExtractorGen2:extractAudioScaffold()
  self:beginStage("Gen2 audio scaffold")
  local constants = self:constants()
  local maps = self:readSourceTable("maps")
  self:writeAsset("assets/generated/audio/fallback/beep.wav", toneWav(0.08, 880, 0.24))
  self:writeAsset("assets/generated/audio/fallback/cry.wav", toneWav(0.12, 440, 0.22))
  self:writeAsset("assets/generated/audio/fallback/music.wav", toneWav(0.45, 220, 0.12))

  local musicFile = "assets/generated/audio/fallback/music.wav"
  local beepFile = "assets/generated/audio/fallback/beep.wav"
  local cryFile = "assets/generated/audio/fallback/cry.wav"
  local songs = {}
  local songNames = {
    "Music_TitleScreen", "Music_PalletTown", "Music_Cities1", "Music_Cities2",
    "Music_Celadon", "Music_Cinnabar", "Music_Vermilion", "Music_Lavender",
    "Music_Routes1", "Music_Routes2", "Music_Routes3", "Music_Routes4",
    "Music_IndigoPlateau", "Music_SafariZone", "Music_Dungeon1", "Music_Dungeon2",
    "Music_Dungeon3", "Music_BikeRiding", "Music_Surfing", "Music_PkmnHealed",
    "Music_Credits", "Music_HallOfFame", "Music_IntroBattle", "Music_Evolution",
    "Music_BattleWildPokemon", "Music_BattleTrainer", "Music_BattleGymLeader",
    "Music_FinalBattle", "Music_DefeatedWildMon", "Music_DefeatedTrainer",
    "Music_DefeatedGymLeader",
  }
  for _, song in ipairs(songNames) do
    songs[song] = { file = musicFile, loopFile = musicFile }
  end

  local mapSongs = {}
  for mapId in pairs(maps) do
    mapSongs[mapId] = "Music_PalletTown"
  end

  local sfx = {
    Press_AB = beepFile,
    Collision = beepFile,
    Go_Inside = beepFile,
    Get_Item1 = beepFile,
    Get_Item2 = beepFile,
    Get_Key_Item = beepFile,
    Level_Up = beepFile,
    Caught_Mon = beepFile,
    Dex_Page_Added = beepFile,
    Pokeflute = beepFile,
    Low_Health_Alarm = beepFile,
  }

  local cries = {}
  for _, species in ipairs(constants.speciesOrder or {}) do
    cries[species] = cryFile
  end

  self:write("audio", {
    source = "Gen2 scaffold fallback audio",
    runtime = false,
    songs = songs,
    mapSongs = mapSongs,
    battle = {
      wild = "Music_BattleWildPokemon",
      trainer = "Music_BattleTrainer",
      gym = "Music_BattleGymLeader",
      final = "Music_FinalBattle",
      wildWin = "Music_DefeatedWildMon",
      trainerWin = "Music_DefeatedTrainer",
      gymWin = "Music_DefeatedGymLeader",
      finalWin = "Music_DefeatedGymLeader",
    },
    sfx = sfx,
    cries = cries,
    special = {
      heal = "Music_PkmnHealed",
      title = "Music_TitleScreen",
      credits = "Music_Credits",
      hallOfFame = "Music_HallOfFame",
      introBattle = "Music_IntroBattle",
      oakRoute = "Music_Routes2",
      bike = "Music_BikeRiding",
      surf = "Music_Surfing",
      evolution = "Music_Evolution",
    },
    outdoorSongs = {
      Music_PalletTown = true,
      Music_Cities1 = true,
      Music_Cities2 = true,
      Music_Celadon = true,
      Music_Cinnabar = true,
      Music_Vermilion = true,
      Music_Lavender = true,
      Music_Routes1 = true,
      Music_Routes2 = true,
      Music_Routes3 = true,
      Music_Routes4 = true,
      Music_IndigoPlateau = true,
      Music_SafariZone = true,
      Music_Dungeon1 = true,
      Music_Dungeon2 = true,
      Music_Dungeon3 = true,
    },
    fanfares = {
      Level_Up = true,
      Caught_Mon = true,
      Get_Item1 = true,
      Get_Item2 = true,
      Get_Key_Item = true,
      Pokeflute = true,
      Dex_Page_Added = true,
    },
  })
  self:tick("Gen2 audio scaffold", 1, 1)
end

function RomExtractorGen2:extractAssets()
  self:beginStage("Gen2 placeholder assets")
  local src = "assets/logo/pokemon_logo.png"
  local assets = {
    "assets/generated/title/pokemon_logo.png",
    -- fonts/font.png and fonts/font_extra.png are NOT listed: this stage runs
    -- last, so a placeholder here would clobber extractFontSheets' real rip
    "assets/generated/sprites/placeholder_sprite.png",
    "assets/generated/icons/placeholder.png",
    "assets/generated/battle/front/placeholder.png",
    "assets/generated/battle/back/placeholder.png",
    "assets/generated/battle/anims/move_anim_0.png",
    "assets/generated/battle/anims/move_anim_1.png",
    "assets/generated/battle/trainers/placeholder.png",
  }
  for i, path in ipairs(assets) do
    if path == "assets/generated/sprites/placeholder_sprite.png" then
      writeGeneratedSpritePlaceholder(path)
    else
      self:copyAsset(src, path)
    end
    self:tick("Gen2 placeholder assets", i, #assets)
  end
end

function RomExtractorGen2:run()
  self:extractScaffoldCore()
  self:extractMoves()
  self:extractMapsFromRom()
  self:extractMapScripts()
  self:extractTextFromRom()
  self:extractPokemon()
  self:extractPalettes()
  self:extractIcons()
  self:extractEncounters()
  self:extractField()
  self:extractRuntimeScaffolds()
  self:extractIntroAssetsFromRom()
  self:extractAudio()
  self:extractAssets()
  if self.progress then
    self.progress(STAGE_COUNT, STAGE_COUNT, "Ready", 1, 1)
  end
  return true
end

return RomExtractorGen2