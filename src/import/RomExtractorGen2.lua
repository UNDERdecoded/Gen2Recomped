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
-- Gold/Crystal have 26 map groups; Prism has 95.  Never trust this constant
-- directly -- :gen2MapGroupCount derives the real number from the ROM.  Read
-- as 26 against Prism, 69 of its 95 groups simply never get walked, so most of
-- the world is missing from an import that otherwise looks fine.
local GEN2_MAP_GROUP_COUNT = 26
local GEN2_MAP_HEADER_BYTES = 9      -- attrBank, tileset, environment, attrPtr, location, music, flags, fishGroup
local GEN2_CONNECTION_BYTES = 12
-- Gold/Crystal pack a Tilesets entry into 15 bytes; Prism uses 14 (it drops
-- the `dw 0` padding and promotes the trailing palette word to a full dba).
-- One byte of drift multiplies by the tileset id, so by the back of the table
-- every pointer is nonsense -- and since the reader only KEEPS ids whose
-- pointers match a known family, the symptom is not an error but a tileset
-- list that quietly comes up almost empty.  `layout.tilesetEntry` overrides.
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
local GEN2_OBJECT_KIND_SCRIPT = 0
local GEN2_OBJECT_KIND_ITEMBALL = 1
local GEN2_OBJECT_KIND_TRAINER = 2
-- Prism only: PERSONTYPE_FRUITTREE, whose parameter field IS the tree id.
-- A class field, not a chunk local -- this file is on Lua's 200-local ceiling.
-- Prism only: PERSONTYPE_GENERICTRAINER, a trainer whose whole object is
-- the `trainer` macro's data block with no script attached.
RomExtractorGen2.GEN2_OBJECT_KIND_GENERICTRAINER = 4
RomExtractorGen2.GEN2_OBJECT_KIND_FRUITTREE = 9
-- Prism's PERSONTYPE_* list runs SCRIPT 0, ITEMBALL 1, TRAINER 2, TMHMBALL 3,
-- GENERICTRAINER 4, TEXT 5, TEXTFP 6, JUMPSTD 7, MART 8, FRUITTREE 9.  The
-- first three match Crystal's OBJECTTYPE_*, which is why the base games need
-- none of this -- but 5 and 6 hold a TEXT pointer where Crystal only ever has
-- a script, and 7/8/9 hold an index rather than a pointer at all.  Gated on
-- `layout.objectTextKinds` so the base games keep reading every non-itemball,
-- non-trainer object as a script.
RomExtractorGen2.GEN2_OBJECT_KIND_TEXT = {
  -- PERSONTYPE_TMHMBALL takes the same slot an ITEMBALL's `db item, db qty`
  -- does, but holds a MACHINE number -- AcquaStart's is `TM_BODY_SLAM, 0`.
  -- Two bytes of item id read as bytecode is the campfire's GLACEON all over
  -- again, so it is named here to keep it out of the script queue; it is not
  -- text either, so it registers none (see the kind test at the call site).
  [3] = true,   -- PERSONTYPE_TMHMBALL
  [5] = true,   -- PERSONTYPE_TEXT
  [6] = true,   -- PERSONTYPE_TEXTFP (text, then face the player)
  [7] = true,   -- PERSONTYPE_JUMPSTD  -- a std INDEX, not a pointer
  [8] = true,   -- PERSONTYPE_MART     -- mart type and id
  [9] = true,   -- PERSONTYPE_FRUITTREE
}
local GEN2_EVENT_FLAG_NONE = 0xFFFF
local GEN2_TIME_OF_DAY_ANY = 0xFF
-- ItemAttributes row: dw price, then effect/param/property/pocket/menu bytes
local GEN2_ITEM_ATTR_BYTES = 7

-- TMHMMoves (4:$5A66) is a flat `db` list of 50 TM moves followed by 7 HM
-- moves (data/moves/tmhm_moves.asm); GetTMHMMove indexes it to turn a TM/HM
-- item into the move it teaches.  Which species may learn machine number n
-- lives in the 8-byte bitfield closing every 32-byte BaseData row (bit
-- (n-1)%8 of byte (n-1)/8), which is what CanLearnTMHMMove tests.
-- Gold/Crystal ship 50 TMs and 7 HMs.  Prism ships 96 and 5 (its HMs are Cut,
-- Fly, Surf, Strength and Rock Smash -- no Flash, Whirlpool or Waterfall), so
-- these are DEFAULTS that `layout.tmCount`/`layout.hmCount` override.  Read as
-- 50/7 against Prism, gen2Machines walks only the first 57 of its 101 machines
-- and then labels TMs 51..96 as HMs, so half the TM list goes missing and the
-- rest teach the wrong move.
local GEN2_TM_COUNT, GEN2_HM_COUNT = 50, 7
-- ...and then THREE MOVE-TUTOR SLOTS.  TMHMMoves does not stop at the HMs:
-- data/moves/tmhm_moves.asm appends MT01..MT03 (Flamethrower, Thunderbolt,
-- Ice Beam) so the table is NUM_TM_HM_TUTOR long, and CanLearnTMHMMove reads
-- bits 58..60 of the same base-stats bitfield for them.  Reading only the
-- first 57 dropped those three bits, so every species came back unable to
-- learn any tutor move -- which is what made the Goldenrod move tutor refuse
-- the whole party.
-- A class field rather than a chunk local: this file sits on Lua's
-- 200-local-per-chunk ceiling (see GEN2_BASE_GENDER below).
RomExtractorGen2.GEN2_TUTOR_COUNT = 3
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
-- Safe to hardcode: Crystal's insertion point is $52, so every command below
-- it keeps Gold's number.  Anything above $52 must come from
-- Gen2ScriptOps.commandsFor(version) instead -- see RomExtractorGen2:opcode.
local GEN2_SCRIPT_OP_SETEVENT = 0x33   -- dw event number

-- The opcode a named command has ON THIS CARTRIDGE.
--
-- `fruittree` and `pokemart` both sit above Crystal's $52 insertion point and
-- were hardcoded at Gold's numbers anyway, which is a real bug in both
-- directions.  `fruittree` is $9A in Gold, $9B in Crystal and $99 in Prism, so
-- against Crystal the test matched `describedecoration` instead: every one of
-- Crystal's berry trees stopped being a berry tree (6 objects survived where
-- Gold has 32) and four of the player's bedroom decorations became trees.
-- `pokemart` is $93/$94/$92 the same way, so mart stock resolved off the
-- wrong byte on two of the three carts.
function RomExtractorGen2:opcode(name)
  self._opcodes = self._opcodes or {}
  local hit = self._opcodes[name]
  if hit ~= nil then return hit ~= false and hit or nil end
  local commands = require("src.import.Gen2ScriptOps").commandsFor(self.version)
  local found = false
  for index, row in ipairs(commands or {}) do
    if type(row) == "table" and row[1] == name then found = index - 1 break end
  end
  self._opcodes[name] = found
  return found ~= false and found or nil
end

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
-- ChrisPicAndTrainerCardGFX (09:$547F) is a raw 2bpp sheet, not an LZ3 pic.
-- The label is literal: Chris's 5x7 tile (40x56) trainer-card portrait comes
-- first, ROW-major, then 6 tiles of card furniture.  The whole blob is only
-- 656 bytes / 41 tiles, bounded by CardStatusGFX at 09:$570F.
--
-- 7x7 was wrong twice over: it asks for 784 bytes, reading 128 bytes past the
-- end into CardStatusGFX, AND it lays 35 tiles of portrait out five-wide data
-- into a seven-wide image, which shears every row.  That is the scrambled
-- trainer card.  Verified by decoding the ROM directly.
local GEN2_PLAYER_PIC_COLS = 5
local GEN2_PLAYER_PIC_ROWS = 7
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
  -- Common Kanto / Johto story NPCs (pret sprite_constants.asm indices)
  [0x23] = "SPRITE_COOLTRAINER_M", -- Misty's date on Route 25
  [0x24] = "SPRITE_COOLTRAINER_F",
  [0x25] = "SPRITE_BUG_CATCHER",
  [0x26] = "SPRITE_TWIN",          -- Route 37 twins
  [0x27] = "SPRITE_YOUNGSTER",
  [0x28] = "SPRITE_LASS",
  [0x29] = "SPRITE_TEACHER",
  [0x2A] = "SPRITE_BEAUTY",        -- Route 37 / common trainers
  [0x2B] = "SPRITE_SUPER_NERD",    -- Power Plant / Machine Part
  -- $2C is ROCKER, not POKEFAN_M.  Naming $2C/$2D POKEFAN_M/POKEFAN_F made
  -- this table collide with the row $2E derives natively (PokefanFSpriteGFX ->
  -- SPRITE_POKEFAN_F): two rows claimed one id, whichever pairs() reached
  -- last won, and SPRITE_ROCKER stopped being produced at all.
  [0x2C] = "SPRITE_ROCKER",
  [0x2D] = "SPRITE_POKEFAN_M",
  [0x2E] = "SPRITE_POKEFAN_F",
  [0x2F] = "SPRITE_GRAMPS",        -- Bill's grandfather (Route 25)
  [0x30] = "SPRITE_GRANNY",
  [0x31] = "SPRITE_SWIMMER_GUY",
  [0x32] = "SPRITE_SWIMMER_GIRL",
  [0x33] = "SPRITE_BIG_SNORLAX",   -- Route 12 / 16
  [0x35] = "SPRITE_ROCKET",        -- Cerulean Gym grunt + residual Rockets
  [0x36] = "SPRITE_ROCKET_GIRL",
  [0x43] = "SPRITE_OFFICER",
  [0x45] = "SPRITE_SLOWPOKE",      -- Azalea Town, after the well
  [0x48] = "SPRITE_GYM_GUIDE",
  [0x52] = "SPRITE_SUDOWOODO",     -- post-reveal Sudowoodo (NOT $6D)
  -- Still / scenery (must NOT be reused for walking NPCs)
  [0x54] = "SPRITE_POKE_BALL",
  [0x59] = "SPRITE_ROCK",
  [0x5A] = "SPRITE_BOULDER",
  [0x5D] = "SPRITE_FRUIT_TREE",
  -- Mon / special sheets
  [0x9F] = "SPRITE_SNORLAX",
  -- Variable-sprite constants used as direct ids on some maps
  -- $F0 and up are wVariableSprites SLOTS, not sheets.  Name them after the
  -- slot -- the names NPC.lua's VAR_SPRITE_SLOTS already knows -- so the
  -- object resolves through the slot every time it is drawn: the map_scripts
  -- default first, then whatever a `variablesprite` has since written into
  -- save.gen2VarSprites.
  --
  -- Naming them after a SHEET pinned the object to one sprite for the whole
  -- game and threw the slot away.  $F6 is the clearest case: it defaults to
  -- the Rocket (sprite 53) and a script sets it to SILVER (sprite 4) for the
  -- rival in Azalea Town, so pinning it to SPRITE_ROCKET meant the rival
  -- turned up as a Team Rocket grunt.  $F5 had the same fault in the other
  -- direction -- pinned to SILVER, while its slot is reassigned too.
  [0xF4] = "SPRITE_WEIRD_TREE",         -- Sudowoodo pre-reveal, slot 4
  [0xF5] = "SPRITE_OLIVINE_RIVAL",      -- slot 5
  [0xF6] = "SPRITE_AZALEA_ROCKET",      -- slot 6
  [0xFB] = "SPRITE_COPYCAT",            -- slot 11
  [0xFC] = "SPRITE_JANINE_IMPERSONATOR",-- slot 12
}

-- GetMonSprite (05:$42CB) splits an object_event sprite byte four ways: below
-- $80 it is an OverworldSprites row, $80..$DF it is SPRITE_POKEMON plus an
-- index into SpriteMons and the object walks around as that species' party
-- menu icon, $E0/$E1 are the two day-care mons, and $F0 and up index
-- wVariableSprites.  Everything from $80 up used to miss the sprite table and
-- fall back to SPRITE_GRAMPS, so the Lake of Rage Gyarados, the Burned Tower
-- beasts, Ho-Oh and Lugia all stood there as an old man.
--
-- Prism moves every one of those boundaries, because its sprite list is 550
-- entries where Gold's is about a hundred: SPRITE_POKEMON is $bb, the day-care
-- pair sit at $ec/$ed, and only SPRITE_VARS stays at $f0.  Read with Gold's
-- numbers, SPRITE_LARVITAR ($e3) landed 99 slots into a 35-entry SpriteMons
-- table, missed, and fell back to SPRITE_RED -- so the Larvitar blocking
-- Acqua Start's path was standing there wearing the player's own sprite.
-- Manifest-driven so Gold and Crystal keep their own numbers untouched.
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
    -- CheckDict (00:$1087) inside a PlaceString run reads $14 as
    -- PlaceGenderedPlayerName and $52 as PrintPlayerName; both are the
    -- player's name, and $14 is the one nearly every line actually uses.
    [0x14] = "<PLAYER>",
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

-- Gen 2 stores ItemNames/MoveNames/TrainerClassNames as $50-terminated
-- strings.  Prism does NOT: every record is LENGTH-PREFIXED and carries no
-- terminator at all -- the byte in front of "Master Ball" is $0C, the whole
-- record's width including the prefix.  The two encodings share no framing,
-- so reading Prism the Crystal way walks off the first record and decodes the
-- rest of the bank as one run of garbage.  Nothing errors; the import just
-- finishes with every item, move and trainer class misnamed, which then
-- breaks every id derived from a name.  `layout.namesLengthPrefixed` picks it.
--
-- NOTE: this file sits ON Lua 5.1's 200-local ceiling for a main chunk, so a
-- new file-scope `local` no longer fits -- hang constants off the class table
-- instead (see RomExtractorGen2.MOVE_CATEGORIES below).  The overflow is a
-- LOAD error, not a runtime one, so nothing in the game reaches a breakpoint
-- to show it; tools/syntax_check.lua is what catches it.

-- Type ids as Gold/Crystal number them.  A hack may fill Crystal's unused
-- $0A-$12 gap with its own types (Prism does: Fairy, Gas, Sound and two
-- signature types), so this is the FALLBACK -- :gen2TypeName prefers the
-- ROM's own TypeNames table.  Declared up here because :gen2TypeName closes
-- over it; a `local` declared further down would leave the method reading a
-- nil global instead, and silently name every type NORMAL.
local GEN2_TYPES = {
  [0]="NORMAL",[1]="FIGHTING",[2]="FLYING",[3]="POISON",
  [4]="GROUND",[5]="ROCK",[6]="BIRD",[7]="BUG",[8]="GHOST",[9]="STEEL",
  [0x13]="CURSE_TYPE",
  [0x14]="FIRE",[0x15]="WATER",[0x16]="GRASS",[0x17]="ELECTRIC",
  [0x18]="PSYCHIC",[0x19]="ICE",[0x1A]="DRAGON",[0x1B]="DARK",
}
-- everything below SPECIAL ($14) is a physical type (Gen2 keeps Gen1's split)
local GEN2_SPECIAL_TYPE = 0x14

local function gen2ReadVarNames(rom, sym, count, prefixed)
  if not (rom and sym) then return {} end
  local names = {}; local bank = sym.bank; local addr = sym.address
  for i = 1, count do
    local ok, chunk = pcall(function()
      return rom:bytes(bank, addr, 16)
    end)
    if not ok or type(chunk) ~= "table" then break end
    local step
    if prefixed then
      -- record = [width][width - 1 text bytes]; a width outside the window is
      -- not a name, it is the table's end (or the wrong address), so stop
      -- rather than resync at random and emit plausible-looking rubbish.
      local width = chunk[1]
      if not width or width < 2 or width > 16 then break end
      local raw = {}; for j = 2, width do raw[#raw + 1] = chunk[j] end
      local name = gen2DecodeString(raw, #raw)
      if name then names[i] = name end
      step = width
    else
      local endIdx = 1
      while endIdx <= #chunk and chunk[endIdx] ~= 0x50 do endIdx = endIdx + 1 end
      endIdx = endIdx - 1
      local raw = {}; for j = 1, endIdx do raw[j] = chunk[j] end
      local name = gen2DecodeString(raw, endIdx)
      if name then names[i] = name end
      step = endIdx + 1
    end
    addr = addr + step
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
-- BG palettes are NOT "6 environment sets of 7 palettes" -- that model was a
-- guess and it is wrong in three separate ways.  What the ROM actually has
-- (LoadMapPals, 02:$766?/$71??) is:
--
--   TilesetBGPalette          flat list of 4-colour palettes, 42 of them,
--                             running to MapObjectPals
--   EnvironmentColorsPointers 8 words, one per ENVIRONMENT_* (1-based: 1 TOWN,
--                             2 ROUTE, 3 INDOOR, 4 CAVE, 5 ENV_5, 6 GATE,
--                             7 DUNGEON), each -> a 4x8 byte table of INDICES
--                             into TilesetBGPalette: one row per time of day
--                             (MORN/DAY/NITE/DARKNESS), eight BG palettes per
--                             row (index 7 being the white text palette).
--
-- So the stride is 8 palettes, not 7, and which palettes a map gets is decided
-- by its ENVIRONMENT byte and the clock -- not by pattern-matching the tileset
-- name.  Reading it the old way put caves 14 palettes into the table and
-- indoor maps 28 in (nearly black).
--
-- And the base address was hardcoded to Gold's 02:$775E.  Crystal's
-- TilesetBGPalette is at 02:$7319, so every Crystal tile came out of unrelated
-- bytes -- that is the garish red/green/pink overworld.  Everything below
-- resolves through the symbol table instead.
-- Kept as ONE table rather than eight `local`s on purpose: this chunk sits
-- right on Lua's 200-locals-per-function ceiling, and the file stops loading
-- outright the moment it is crossed.
local GEN2_PAL = {
  bank = 2,
  bgAddrFallback = 0x775e,     -- Gold/Silver, used only if symbols are absent
  objAddrFallback = 0x78ae,    -- ditto, MapObjectPals
  bgCountFallback = 42,
  perRow = 8,
  todRows = { "MORN", "DAY", "NITE", "DARK" },
  -- ENVIRONMENT_* is 1-based; index 0 is unused by any real map header but the
  -- ROM's pointer table still has a slot for it, so the array stays 0-based.
  defaultEnvironment = 1,      -- TOWN, for a tileset no map declares

  -- The VRAM-bank half of the same question, parked here for the same reason
  -- everything above is: five more chunk-level `local`s is exactly what pushed
  -- this file over the 200 ceiling once already.
  --
  -- A Crystal tileset is 192 tiles, not 96.  LoadTilesetGFX (00:$2821)
  -- decompresses the whole blob and copies it in TWO halves: $600 bytes (96
  -- tiles) to vTiles2 in VRAM bank 0, and the next $600 to the SAME address in
  -- VRAM bank 1.  A metatile byte carries only the low tile number; the bank is
  -- bit 3 of that tile's nibble in <Tileset>PalMap -- which is why these
  -- constants belong next to the palette ones.  The encoded pair is one byte:
  -- $00-$5F is bank 0, $80-$DF is bank 1, so the second half sits at
  -- `byte - $80 + 96`.
  --
  -- Reading those literally left Ecruteak's building fronts and the Burned
  -- Tower's roof blank and turned Elm's desk into a white smear: TilesetLab
  -- alone puts 481 of its 1024 references in the second bank, and 25 of
  -- Crystal's 37 tilesets use it.  $60-$7F is a hole (the palette map marks it
  -- unused and no metatile in either ROM touches it) and $E0-$FF only appears
  -- inside padding blocks no map uses, so both resolve to tile 0.
  --
  -- Gold and Silver do NOT split: their LoadTilesetGFX (00:$2944) decompresses
  -- straight to vTiles2, their sheets come out 96 tiles, and their palette maps
  -- are 48 bytes with no bank bit anywhere.
  tilesPerVramBank = 96,
  palMapBytes = 112,           -- Crystal: 224 nibbles, $00-$DF
  palMapBytesOneBank = 48,     -- Gold/Silver: 96 nibbles, $00-$5F
}

-- How many tiles a decoded sheet holds, from the def the extractor wrote.
function GEN2_PAL.sheetTiles(def)
  if type(def) ~= "table" then return 0 end
  local width = tonumber(def.imageWidth) or 0
  local height = tonumber(def.imageHeight) or 0
  return (width / 8) * (height / 8)
end

-- Exactly two banks' worth, not merely "more than one": the placeholder sheet a
-- failed decompress falls back on is 128x128 = 256 tiles, and that must not be
-- mistaken for a split tileset.  Detecting the split from the DECODED SHEET
-- rather than from the version also keeps the eight Crystal tilesets that are
-- genuinely 96 tiles (Cave, DarkCave, EliteFourRoom, Facility, Kanto,
-- PlayersHouse, PlayersRoom, Port) on the old path, where they belong.
function GEN2_PAL.twoVramBanks(tileCount)
  return tileCount == GEN2_PAL.tilesPerVramBank * 2
end

-- Metatile byte -> index into the flattened 0..191 sheet.
function GEN2_PAL.tileIndex(byte, tileCount)
  if not GEN2_PAL.twoVramBanks(tileCount) then return byte end
  if byte < GEN2_PAL.tilesPerVramBank then return byte end
  if byte >= 0x80 then
    local index = byte - 0x80 + GEN2_PAL.tilesPerVramBank
    if index < tileCount then return index end
  end
  return 0
end

-- BGR555 word -> {r, g, b} 0..255.
function GEN2_PAL.bgr555(lo, hi)
  local val = lo + hi * 256
  return {
    math.floor(val % 32 * 255 / 31),
    math.floor(math.floor(val / 32) % 32 * 255 / 31),
    math.floor(math.floor(val / 1024) % 32 * 255 / 31),
  }
end

-- `count` consecutive 4-colour palettes starting at bank:address.
function GEN2_PAL.read(rom, bank, address, count)
  local ok, raw = pcall(function()
    return rom:bytes(bank, address, count * 8)
  end)
  if not (ok and type(raw) == "table") then return nil end
  local out = {}
  for p = 0, count - 1 do
    local pal = {}
    for c = 0, 3 do
      pal[#pal + 1] = GEN2_PAL.bgr555(raw[p * 8 + c * 2 + 1],
                                      raw[p * 8 + c * 2 + 2])
    end
    out[p + 1] = pal
  end
  return out
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

-- Prism's move `type` byte is `category << 6 | type` (the Gen 4 split), so its
-- high bits name the damage class rather than another type.  A table field
-- rather than a `local`: the main chunk is at Lua 5.1's 200-local ceiling.
RomExtractorGen2.MOVE_CATEGORIES =
  { [0] = "physical", [1] = "special", [2] = "status" }

-- A ROM's own record LAYOUT, from the manifest, with the base game's value as
-- the default.
--
-- A hack can move a table AND reshape it, and the two are independent problems:
-- Prism's BaseData sits at 14:5A0E with **24 bytes per entry** where Crystal
-- uses 32 (verified by decoding -- entry 1 reads 45/49/49/45/65/65, Bulbasaur's
-- exact base stats).  A symbol alone is not enough to read a table; feeding a
-- 24-byte table through a hardcoded 32-byte stride yields garbage that still
-- "imports".  So strides live in `manifest.layout` and every reader asks here.
function RomExtractorGen2:layout(key, default)
  local table_ = self.manifest and self.manifest.layout
  local value = type(table_) == "table" and tonumber(table_[key]) or nil
  return value or default
end

-- Every variable-length name table in one ROM shares an encoding, so the
-- flag is consulted here rather than at each of the five call sites.
function RomExtractorGen2:varNames(name, count)
  return gen2ReadVarNames(self.rom, self:symbol(name), count,
                          self:layout("namesLengthPrefixed", 0) ~= 0)
end

-- Prism drops Fairy, Gas and Sound (plus two signature types) into the
-- $0A-$12 hole Crystal leaves unused, so a hardcoded id -> name table can
-- only ever be right for the base games.  TypeNames is a 28-entry pointer
-- list in type-id order in every Gen 2 ROM, so prefer the names the ROM
-- itself prints and keep the static table as the fallback.
function RomExtractorGen2:gen2TypeName(id)
  if not self._typeNames then
    local names = {}
    local sym = self:symbol("TypeNames")
    if sym and self.rom then
      for i = 0, 27 do
        pcall(function()
          local address = self.rom:word(sym.bank, sym.address + i * 2)
          local text = gen2DecodeString(self.rom:bytes(sym.bank, address, 14), 14)
          if text then
            local label = text:upper():gsub("[^%u%d]+", "_")
            label = label:gsub("^_+", ""):gsub("_+$", "")
            if label ~= "" then names[i] = label end
          end
        end)
      end
    end
    self._typeNames = names
  end
  return self._typeNames[id] or GEN2_TYPES[id]
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
  -- Prism's control block and a dozen of its printable codes are its own; the
  -- table is consulted first so both decoders -- the compressed one and the
  -- byte-at-a-time one -- agree, and it is empty for every other ROM.
  if self:layout("prismCharmap", 0) ~= 0 then
    local prism = RomExtractorGen2.PRISM_GLYPHS[value]
    if prism then return prism end
  end
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
-- A party icon as PartyMenu wants it: two 16x16 frames stacked into 16x32,
-- each frame four tiles in reading order.  OBJ colour 0 is transparent, so the
-- sheet keeps alpha 0 there and a plain (non-#obp) load draws it as authored.
-- Shared by the two icon table layouts -- Crystal's `dw` + MonMenuIcons
-- indirection and Prism's `dba` indexed by species.
local function gen2IconImage(tiles, colors)
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
  return image
end

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

-- Turn already-decoded character bytes into the port's text string.  Shared by
-- the Prism compressed path, which has no byte stream left to walk by the time
-- it gets here -- the line/paragraph control codes are characters in the
-- Huffman alphabet, not stream commands.
-- These are TextBox's markers, not plain whitespace (see TextBox's header):
-- \n is the second line, \v scrolls one line up, and \f is a PAGE BREAK --
-- the box waits for A and clears.  The byte-at-a-time decoder below has always
-- emitted them; this table is the compressed decoder's copy of the same
-- mapping, and while it spelled <PARA> as a blank line and <CONT> as a newline
-- every Prism box ran start to finish in one uninterrupted scroll, because
-- nothing in it ever asked for a button.
RomExtractorGen2.GEN2_TEXT_BREAKS = {
  [0x4E] = "\n",   -- <NEXT>, a line down
  [0x4F] = "\n",   -- <LINE>, the bottom line
  [0x51] = "\f",   -- <PARA>, a new paragraph: wait for A, then clear
  [0x55] = "\v",   -- <CONT>, scroll on
  -- <SCROLL> is <CONT> without the button press; the port has no marker for
  -- that, and one press is a far smaller error than a page that never stops
  [0x4C] = "\v",
  [0x5F] = "\n",   -- <LNBRK>, Prism's own: a line break outside scripting
}
RomExtractorGen2.GEN2_TEXT_ENDS = {
  [0x50] = true,  -- "@"
  [0x56] = true,  -- <SDONE>
  [0x57] = true,  -- <DONE>
  [0x58] = true,  -- <PROMPT>
}

-- Prism's control block ($44-$5f, macros/charmap.asm) is NOT Crystal's.  Five
-- of the codes mean something else entirely and two more are Prism's alone,
-- so read through Crystal's table they came out as "{BYTE:4B}" and friends in
-- the middle of a sentence:
--
--   $4a  Crystal <PKMN>   Prism <BMON>   (the player's mon)
--   $4b  --               Prism <PKMN>
--   $4d  --               Prism <POKE>
--   $5b  Crystal <PC>     Prism <MINB>   (the minimised box marker)
--   $5c  Crystal TM       Prism <......>
--
-- The buffer codes all resolve to the one stringBuffer the port keeps, the
-- same way TX_STRINGBUFFER does in the byte-at-a-time decoder.
RomExtractorGen2.PRISM_GLYPHS = {
  [0x44] = "{RAM:wStringBuffer1}",   -- <EMON>, the enemy's mon
  [0x45] = "{RAM:wStringBuffer1}",   -- <STRBF1>
  [0x46] = "{RAM:wStringBuffer2}",   -- <STRBF2>
  [0x47] = "{RAM:wStringBuffer3}",   -- <STRBF3>
  [0x48] = "{RAM:wStringBuffer4}",   -- <STRBF4>
  [0x49] = "{RAM:wStringBuffer1}",   -- <ENEMY>, the enemy trainer
  [0x4A] = "{RAM:wStringBuffer1}",   -- <BMON>, the player's mon
  [0x4B] = "PK\xc3\xa9MN",           -- <PKMN>
  [0x4D] = "POK\xc3\xa9",            -- <POKE>
  [0x5B] = "BOX",                    -- <MINB>
  [0x5C] = "\xe2\x80\xa6\xe2\x80\xa6", -- <......>
  [0x5D] = "{RAM:wStringBuffer1}",   -- <TRNER>
  [0x5E] = "ROCKET",                 -- <ROCKET>
  -- and the printable half.  `<...>` is $ba in Prism -- a code Gold and
  -- Crystal do not use at all -- and it is the single most common character
  -- in Prism's dialogue: every trailing pause in the game printed as
  -- "{BYTE:BA}".
  [0xBA] = "\xe2\x80\xa6",           -- "…" / <...>
  [0xBB] = "@", [0xBC] = "\xe2\x99\xa5", [0xBD] = "\xe2\x99\xa6",
  [0xBE] = "\xe2\x99\xa0", [0xBF] = "\xe2\x99\xa3",
  [0xC1] = "\xe2\x80\x9c", [0xC2] = "\xe2\x80\x9d",
  [0xC5] = " ",                      -- < >, the VWF's narrow space
  [0xCC] = ".",                      -- <DOT>
  [0xD7] = "9",                      -- <9> (trainer names: "9" itself is $ff)
  [0xD8] = " ",                      -- <BLANK>
  [0xD9] = "\xe2\x96\xb2", [0xDA] = "%", [0xDB] = "+", [0xDC] = "-",
  [0xDD] = "\xe2\x96\xbc", [0xDE] = "\xe2\x96\xb2", [0xDF] = "\xe2\x97\x80",
  [0xE4] = "PO", [0xE5] = "KE",      -- the two halves of the POKe glyph
  [0xEB] = "\xe2\x96\xb6", [0xEC] = "\xe2\x96\xb7", [0xED] = "\xe2\x96\xb6",
  [0xEE] = "\xe2\x96\xbc",
  [0xF2] = "*",                      -- <SHINY>, where Crystal has "."
}

function RomExtractorGen2:gen2GlyphBytes(bytes, charmap)
  local out = {}
  for _, b in ipairs(bytes) do
    if RomExtractorGen2.GEN2_TEXT_ENDS[b] then break end
    local brk = RomExtractorGen2.GEN2_TEXT_BREAKS[b]
    if brk then
      out[#out + 1] = brk
    else
      local glyph = RomExtractorGen2.PRISM_GLYPHS[b] or self:textGlyph(charmap, b)
      if glyph then out[#out + 1] = glyph end
    end
  end
  -- trailing \n / \f / \v carry no text and would open an empty final page
  return (table.concat(out):gsub("%s+$", ""))
end

function RomExtractorGen2:decodeGen2TextAt(bank, address, charmap, script, depth)
  local out = {}
  local offset = 0
  -- keep the three-byte lookaheads ($50 peek, TX_FAR pointer) inside the
  -- window too, so running off the end returns what was read instead of
  -- asserting in Rom.offset
  local limit = (bank == 0 and 0x4000 or 0x8000) - address - 3
  -- A Gen2 text is TWO interleaved encodings, and the same byte means
  -- different things in each.  At command level DoTextUntilTerminator (00:$13F6)
  -- indexes TextCommands, so $14 is TX_STRINGBUFFER with an index operand and
  -- $16 is TX_FAR.  TX_START ($00) then hands everything up to the next $50 to
  -- PlaceString, whose own dictionary (CheckDict, 00:$1087) reads $14 as
  -- PlaceGenderedPlayerName -- the PLAYER'S NAME, one byte, no operand -- and
  -- $16 as a carriage return.  TextCommand_START's trailing `inc hl` steps
  -- past that $50 and command level resumes.
  --
  -- Decoding every byte at command level is why "ELM: <PLAYER>!" came out as
  -- "ELM: {RAM:wStringBuffer1}" with the "!" eaten as the operand: the player's
  -- name printed as whatever was last in the string buffer, which is the item
  -- the player most recently picked up.  691 texts carried the wrong token.
  --
  -- A caller can also hand over an address that is already INSIDE a run, so
  -- the mode is seeded from the first byte rather than assumed: TextCommands
  -- has 23 rows, so every command byte is $00-$16 and anything from $17 up can
  -- only be a character, which means the run is already open.
  -- Prism opens a compressed run with TX_COMPRESSED ($03) and everything after
  -- it is a Huffman BIT stream, not bytes -- so the byte-at-a-time loop below
  -- cannot read it at all.  Decode the run first and glyph the result.
  do
    local okLead, lead = pcall(self.rom.byte, self.rom, bank, address)
    if okLead and lead == RomExtractorGen2.PRISM_TX_COMPRESSED
       and self:gen2PrismTextTables() then
      local chars, endPc = self:gen2PrismDecompressText(bank, address)
      if chars and #chars > 0 then
        return self:gen2GlyphBytes(chars, charmap), (endPc or address) - address
      end
    end
  end
  local sdoneEnds = self:layout("prismCharmap", 0) ~= 0
  -- PRISM'S FAR-TEXT FORM.
  --
  -- Gold and Crystal mark a far pointer with TX_FAR ($16) and follow it with
  -- `dw target, db bank`.  Prism does not: its `text_far` / `text_jump`
  -- macros (macros/text.asm:105-115) write the target's HIGH BYTE BIASED
  -- DOWN by $3C as the lead byte, then the low byte, then the bank -- with
  -- bit 7 of the bank set for the `text_jump` form.  A ROM address is
  -- $4000-$7FFF, so the biased lead lands in $04-$43, which is exactly the
  -- range below LEAST_CONTROL_CHAR ($44) that Prism's charmap keeps free for
  -- this.  There is no opcode byte at all.
  --
  -- Read as ordinary bytes those three came out as two glyphs and a stray
  -- {RAM:....}, and the decoder then ran on into whatever followed -- which
  -- is why every one of Prism's in-game trade lines was a wall of {BYTE:39}
  -- and {RAM:40E1} instead of dialogue: TradeTexts points at five pairs of
  -- three-byte `text_jump` stubs and nothing else.
  local prismFarBias = sdoneEnds and 0x3C or nil
  local inString = false
  do
    local okLead, lead = pcall(self.rom.byte, self.rom, bank, address)
    -- On Gold and Crystal, TextCommands has 23 rows, so anything above $16 can
    -- only be a character and the run is already open.  ON PRISM THAT TEST IS
    -- WRONG: its command range reaches all the way up to LEAST_CONTROL_CHAR
    -- ($44), because $04-$43 are the biased high bytes of the far-text form
    -- above.  Seeding inString on a $39 lead is what kept the far-pointer
    -- branch from ever firing.
    local floor = prismFarBias and 0x43 or 0x16
    if okLead and type(lead) == "number" and lead > floor then inString = true end
  end
  while offset < GEN2_TEXT_MAX_BYTES and offset < limit do
    local value = self.rom:byte(bank, address + offset)
    local splice = script and RomExtractorGen2.GEN2_TEXT_SPLICE[value]
    if value == 0x50 then
      if not (script and RomExtractorGen2.GEN2_TEXT_SPLICE[
                self.rom:byte(bank, address + offset + 1)]) then
        return table.concat(out), offset + 1
      end
      inString = false
    elseif inString and (value == 0x14 or value == 0x16) then
      -- PlaceString's reading of the two: the player's name, and a carriage
      -- return.  textGlyph turns $14 into {PLAYER} through GEN2_CHARMAP.
      out[#out + 1] = value == 0x14 and self:textGlyph(charmap, value) or "\n"
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
    elseif prismFarBias and not inString and offset == 0
           and value >= 0x04 and value <= 0x43 then
      local target = (value + prismFarBias) * 256
                     + self.rom:byte(bank, address + offset + 1)
      -- bit 7 of the bank byte is text_jump rather than text_far; both point
      -- at the same thing, so mask it off
      local far = self.rom:byte(bank, address + offset + 2) % 0x80
      -- Two guards, both narrowing:
      --   offset == 0 -- text_far / text_jump are the WHOLE body of the block
      --     they head, never a byte in the middle of one.  Without this the
      --     branch also fired on the $04 inside TextCompressionHuffmanTree,
      --     a data table that happens to sit in the text symbol list, and
      --     followed its bytes off into unrelated dialogue.
      --   a banked target -- the macro writes BANK(label), so the address is
      --     always $4000-$7FFF.
      if (depth or 0) < 3 and target >= 0x4000 and target < 0x8000
         and self:gen2InRom(far, target) then
        out[#out + 1] = (self:decodeGen2TextAt(far, target, charmap, script,
                                               (depth or 0) + 1))
      end
      return table.concat(out), offset + 3
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
      -- TX_START: opens another literal run, prints nothing itself.  From here
      -- to the next $50 the bytes are PlaceString's dictionary, not the
      -- command table.
      inString = true
    elseif value == 0x4E or value == 0x4F then
      out[#out + 1] = "\n"
    elseif value == 0x51 then
      out[#out + 1] = "\f"
    elseif value == 0x55 then
      out[#out + 1] = "\v"
    elseif value == 0x57 or value == 0x58
           or (value == 0x56 and sdoneEnds) then
      -- $56 is "……" in Gold and Crystal but <SDONE> in Prism -- "like done,
      -- but with a cursorless prompt".  Read as an ellipsis the decoder ran
      -- straight out the end of the string: `text "<PLAYER>!" / sdone` came
      -- out as the player's name followed by whatever bytes followed it,
      -- which is most of the scrambled dialogue that was left.
      return table.concat(out), offset + 1
    else
      out[#out + 1] = self:textGlyph(charmap, value)
    end
    offset = offset + 1
  end
  return table.concat(out), offset
end


-- Does this cartridge HAVE the professor's introduction?
--
-- Gold, Silver and Crystal ship OakText1..7 and OakSpeech replays them.  A
-- TOTAL CONVERSION MAY NOT: Prism writes its own introduction in
-- engine/intro_menu.asm and carries no OakText* symbol at all.  Seeding the
-- English fallbacks regardless put an _OakSpeechText1 in Prism's text table,
-- which is exactly the key Data.lua tests to decide `boot.screens.newGame` --
-- so Prism was handed an Oak speech it does not have, and the New Game branch
-- that opens PRISM'S CHARACTER CUSTOMISATION (Game:makeTitleState) was never
-- taken.  That is the "the customization menu still isn't appearing" report:
-- the screen was right, the speech in front of it should not have existed.
function RomExtractorGen2:gen2HasOakSpeech()
  return (self:symbol("OakText1") or self:symbol("_OakText1")) ~= nil
end

function RomExtractorGen2:extractTextFromRom()
  self:beginStage("Gen2 text (ROM)")
  local texts = self:readSourceTable("text")
  if not self.rom then
    if self:gen2HasOakSpeech() then
      for key, fallback in pairs(INTRO_TEXT_FALLBACKS) do
        local raw = texts[key]
        if type(raw) ~= "string" or raw == "" or raw:match("^%{GEN2_TEXT:") then
          texts[key] = fallback
        end
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

  if self:gen2HasOakSpeech() then
    for key, fallback in pairs(INTRO_TEXT_FALLBACKS) do
      local raw = texts[key]
      if type(raw) ~= "string" or raw == "" or raw:match("^%{GEN2_TEXT:") then
        texts[key] = fallback
      end
    end
  else
    -- and drop any half-resolved placeholder so the gate reads false
    for key in pairs(INTRO_TEXT_FALLBACKS) do
      local raw = texts[key]
      if type(raw) ~= "string" or raw == "" or raw:match("^%{GEN2_TEXT") then
        texts[key] = nil
      end
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
      local romNames = self:varNames("ItemNames", 300)
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
              + (kind == "HM" and self:layout("tmCount", GEN2_TM_COUNT) or 0)
            entry.machine = self:gen2Machines()[slot]
          end
        end
      end
    elseif name == "moves" and self.rom then
      local romNames = self:varNames("MoveNames", 300)
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
  [0x5C] = "SNORE_EFFECT",           -- flinch hit, but only while asleep
  [0x6C] = "BURN_SIDE_EFFECT1",
  [0x76] = "SWAGGER_EFFECT",         -- confuse AND raise the target's Attack 2
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

  -- ------------------------------------------------------------------
  -- Gen 2's own effects.  Everything above maps a Gen2 effect byte onto a
  -- Gen1 effect name the engine already implements; these 47 bytes had no
  -- mapping at all and silently became NO_ADDITIONAL_EFFECT, so 51 of the
  -- 251 moves lost their effect entirely.  Ten of them were worse than
  -- inert: Counter, Mirror Coat, Flail, Reversal, Return, Frustration,
  -- Present, Magnitude and Hidden Power carry base power 1 in the ROM
  -- because the handler is supposed to compute the real power.
  --
  -- Names follow pret/pokegold constants/move_effect_constants.asm.  An
  -- effect with no handler yet still lands here rather than vanishing:
  -- MoveEffects.warnUnknown logs it once and the move falls back to plain
  -- damage, which is both correct-ish and visible in the log.
  -- ------------------------------------------------------------------
  [0x24] = "TRI_ATTACK_EFFECT",
  [0x59] = "COUNTER_EFFECT",
  [0x5A] = "ENCORE_EFFECT",
  [0x5B] = "PAIN_SPLIT_EFFECT",
  [0x5D] = "CONVERSION2_EFFECT",
  [0x5E] = "LOCK_ON_EFFECT",
  [0x5F] = "SKETCH_EFFECT",
  [0x61] = "SLEEP_TALK_EFFECT",
  [0x62] = "DESTINY_BOND_EFFECT",
  [0x63] = "REVERSAL_EFFECT",
  [0x64] = "SPITE_EFFECT",
  [0x65] = "FALSE_SWIPE_EFFECT",
  [0x66] = "HEAL_BELL_EFFECT",
  [0x69] = "THIEF_EFFECT",
  [0x6A] = "MEAN_LOOK_EFFECT",
  [0x6B] = "NIGHTMARE_EFFECT",
  [0x6D] = "CURSE_EFFECT",
  [0x6F] = "PROTECT_EFFECT",
  [0x70] = "SPIKES_EFFECT",
  [0x71] = "FORESIGHT_EFFECT",
  [0x72] = "PERISH_SONG_EFFECT",
  [0x73] = "SANDSTORM_EFFECT",
  [0x74] = "ENDURE_EFFECT",
  [0x75] = "ROLLOUT_EFFECT",
  [0x77] = "FURY_CUTTER_EFFECT",
  [0x78] = "ATTRACT_EFFECT",
  [0x79] = "RETURN_EFFECT",
  [0x7A] = "PRESENT_EFFECT",
  [0x7B] = "FRUSTRATION_EFFECT",
  [0x7C] = "SAFEGUARD_EFFECT",
  [0x7E] = "MAGNITUDE_EFFECT",
  [0x7F] = "BATON_PASS_EFFECT",
  [0x80] = "PURSUIT_EFFECT",
  [0x81] = "RAPID_SPIN_EFFECT",
  [0x87] = "HIDDEN_POWER_EFFECT",
  [0x88] = "RAIN_DANCE_EFFECT",
  [0x89] = "SUNNY_DAY_EFFECT",
  [0x8A] = "DEFENSE_UP_HIT_EFFECT",
  [0x8B] = "ATTACK_UP_HIT_EFFECT",
  [0x8C] = "ALL_UP_HIT_EFFECT",
  [0x8E] = "BELLY_DRUM_EFFECT",
  [0x8F] = "PSYCH_UP_EFFECT",
  [0x90] = "MIRROR_COAT_EFFECT",
  [0x93] = "EARTHQUAKE_EFFECT",
  [0x94] = "FUTURE_SIGHT_EFFECT",
  [0x95] = "GUST_EFFECT",
  [0x9A] = "BEAT_UP_EFFECT",
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

  local names = self:varNames("MoveNames", #order)
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
    -- Crystal stores one type id per move and derives physical/special from
    -- the id alone ($14 and up is special).  Prism implements the Gen 4 split
    -- in the SAME byte: `category << 6 | type`, 0 physical / 1 special / 2
    -- status -- confirmed against Fire Punch (physical), Flamethrower
    -- (special) and Swords Dance (status), and by the fact that masking off
    -- the top two bits leaves every one of its 254 moves inside the valid
    -- type range.  Read Crystal's way the byte reads as type 64..155, so
    -- GEN2_TYPES misses and EVERY move in the game imports as NORMAL.
    -- `layout.moveCategoryDivisor` is the radix of that packing.
    local categoryDivisor = self:layout("moveCategoryDivisor", 0)
    local typeId, category = row[4], nil
    if categoryDivisor > 0 then
      typeId = row[4] % categoryDivisor
      category = RomExtractorGen2.MOVE_CATEGORIES[math.floor(row[4] / categoryDivisor)]
    end
    local move = {
      id = id, index = index, name = name,
      source = string.format("ROM:Moves[%d]", index),
      effect = effect or "NO_ADDITIONAL_EFFECT",
      power = row[3],
      type = self:gen2TypeName(typeId) or "NORMAL",
      -- Damage.lua already prefers move.category over the type's own class,
      -- so a split ROM needs nothing from the battle engine.
      category = category,
      -- Gen2 stores accuracy as a 0-255 fraction like Gen1 -- but a hack can
      -- re-encode it.  Prism stores PLAIN PERCENT: both ROMs carry exactly 11
      -- distinct accuracy values, Crystal's running 76..255 and Prism's the
      -- corresponding 0..100.  Dividing Prism's by 255 would make every move in
      -- the game ~39% accurate, silently.  `layout.moveAccuracyMax` is what the
      -- byte means by "100%".
      accuracy = math.floor(row[5] * 100 / self:layout("moveAccuracyMax", 255) + 0.5),
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
  -- pokecrystal calls it CollisionPermissionTable; Prism (and pokegold's own
  -- tilesets/collision.asm) call the same 256-byte table TileCollisionTable.
  -- Finding neither is not a cosmetic loss: `walkable` comes out EMPTY, and an
  -- empty permission set reads downstream as "nothing is known to block", so
  -- the player walks through walls, water and scenery alike -- which is
  -- exactly what Prism did.  LANDTILE 0 / WATERTILE 1 / WALLTILE $f / TALK $10
  -- are the same values in both, so only the name had to be found.
  local sym = self:symbol("CollisionPermissionTable")
    or self:symbol("TileCollisionTable")
  if not sym then
    Logger.warn("gen2 collision: no permission table (CollisionPermissionTable "
      .. "/ TileCollisionTable); every tile will read as passable")
  end
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
-- The spinners (engine/overworld/map_objects.asm MovementFunction_*).  Only
-- the two walk functions and "everything else stands still" were read before,
-- so every SPRITEMOVEDATA_SPINRANDOM_* / _SPIN_CLOCKWISE object -- the Rocket
-- grunts in the Mahogany base and the Goldenrod underground, the gym guards,
-- the Radio Tower sentries -- was extracted as a plain STAY and stood
-- motionless facing one way for the whole game.
local GEN2_MOVE_FACING = { [0] = "DOWN", [1] = "UP", [2] = "LEFT", [3] = "RIGHT" }
local GEN2_MOVEMENT_ENTRY_BYTES = 6
local GEN2_MOVEMENT_MAX = 0x25

RomExtractorGen2.GEN2_MOVE_FN_SPIN = {
  [0x04] = "SPIN_SLOW",   -- MovementFunction_RandomSpinSlow
  [0x05] = "SPIN_FAST",   -- MovementFunction_RandomSpinFast
  [0x18] = "SPIN_CW",     -- MovementFunction_SpinClockwise
  [0x19] = "SPIN_CCW",    -- MovementFunction_SpinCounterclockwise
}

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
        local spin = RomExtractorGen2.GEN2_MOVE_FN_SPIN[raw[base + 1]]
        if spin then
          -- `range` carries which spin it is; NPC.lua reads it back.  The
          -- facing byte for every spin entry is DOWN, which is also what
          -- FACING_FROM_RANGE falls back to for an unknown range.
          out[index] = { movement = "SPIN", range = spin }
        elseif roam then
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
    if op == self:opcode("pokemart") then
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
local GEN2_SPECIAL_TABLE_MAX = 255     -- Gold has 129 entries, Crystal 207
local GEN2_TRAINER_PIC_TILES = 7
-- Every Gen2 back pic is 6x6, in both cartridges, whatever the species' front
-- pic_dims say -- so a back pic must never inherit them.
local GEN2_BACK_PIC_TILES = 6

-- FixPicBank rewrites the bank byte of a pic pointer.  Both Gen2 games have
-- the routine but they do it two completely different ways, and running
-- Gold's reading over Crystal leaves every pointer on its raw bank:
--
--   Gold/Silver (14:$5863)  FixPicBank.FixPicBankTable, from/to pairs
--                           terminated by $FF.  Only a handful of banks move
--                           (Rival2, Champion, Bruno, ...); without it those
--                           decompress from the wrong bank as vertical noise.
--
--   Crystal (14:$51C5)      `sub n` then FixPicBank.PicsBanks[stored - n` --
--                           a flat list of the 24 pic banks ($48..$5F).  EVERY
--                           pointer needs it: the table stores $19 where the
--                           pic really lives in bank $4F.  Unfixed, all 67
--                           trainer pics decompress from garbage.
--
-- The `sub` bias is read back out of the routine's own code rather than
-- assumed, so a revision that renumbers the pic banks still resolves.
function RomExtractorGen2:gen2PicBankFix()
  if self._picBankFix then return self._picBankFix end
  local fix = {}
  self._picBankFix = fix
  if not self.rom then return fix end

  local pairsSym = self:symbol("FixPicBank.FixPicBankTable")
  if pairsSym then
    pcall(function()
      local address = pairsSym.address
      while address < 0x8000 do
        local from = self.rom:byte(pairsSym.bank, address)
        if from == 0xFF then break end
        fix[from] = self.rom:byte(pairsSym.bank, address + 1)
        address = address + 2
      end
    end)
    return fix
  end

  local banks = self:symbol("FixPicBank.PicsBanks")
  local routine = self:symbol("FixPicBank")
  if not banks then return fix end
  pcall(function()
    -- `d6 nn` = SUB n, the only subtract in this eight-byte routine
    local bias = 0x12
    if routine then
      local code = self.rom:bytes(routine.bank, routine.address, 8)
      for i = 1, #code - 1 do
        if code[i] == 0xD6 then bias = code[i + 1]; break end
      end
    end
    -- the table runs to whatever symbol follows it in the same bank
    local limit = 0x8000
    for _, location in pairs(self.symbols or {}) do
      local bank, address = tonumber(location[1]), tonumber(location[2])
      if bank == banks.bank and address and address > banks.address
          and address < limit then
        limit = address
      end
    end
    local count = math.min(limit - banks.address, 64)
    if count <= 0 then return end
    local raw = self.rom:bytes(banks.bank, banks.address, count)
    for index, bank in ipairs(raw) do fix[bias + index - 1] = bank end
  end)
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
-- The rival's class is the one the ROM NAMES "RIVAL", and BattleState wants
-- it under OPP_RIVAL1/2/3 because those are the ids it swaps the player's own
-- rival name into.  This used to be a hardcoded { [9] = RIVAL1, [42] = RIVAL2 }
-- -- Gold's and Crystal's layout and nobody else's.  Prism's group 42 is the
-- BIKER class, so every biker in the game fought under the rival's name and
-- Prism had no biker class at all.  Numbered off the class name the ROM
-- prints instead, the base games land on 9 and 42 exactly as before and Prism
-- gets the one rival it actually has.
local GEN2_RIVAL_CLASS_NAME = "RIVAL"
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
      -- HOW LONG THE TABLE IS, AND WHERE EACH GROUP ENDS.
      --
      -- Both used to assume TrainerGroups is stored in ADDRESS ORDER: the
      -- count came from the first pointer ("the table ends where the data
      -- starts"), and a group's end came from the NEXT ROW of the table.
      -- That holds in Gold and Crystal and it does NOT hold in Prism, which
      -- assembles its 67 groups in a different order from the pointer list.
      --
      -- What it cost: where the next row points LOWER than the group itself,
      -- the parse window is empty and the class comes out with no parties at
      -- all.  Measured against the cartridges that is 35 of Prism's 67
      -- classes -- the RIVAL among them, which is why the battle in the Ilk
      -- brother's house on Route 69 ran its text and never started -- and one
      -- class each in Gold and Crystal.  The count was worse still: Prism's
      -- first pointer is not its lowest, so `count` came out 1370 and the loop
      -- ran off the end of the bank into the caught error below, keeping only
      -- whatever it had managed to build before it.
      --
      -- Neither fact needs the order.  A dw table ends at the LOWEST address
      -- it points to, and a group ends at the next pointer ABOVE its own --
      -- read off the whole set rather than off the row after it.
      local ptrs, lowest = {}, 0x8000
      for i = 0, 511 do
        local at = sym.address + i * 2
        if at >= lowest then break end
        local p = self.rom:word(sym.bank, at)
        if p < 0x4000 or p >= 0x8000 then break end
        ptrs[#ptrs + 1] = p
        if p < lowest then lowest = p end
      end
      local count = #ptrs
      local sorted = {}
      for _, p in ipairs(ptrs) do sorted[#sorted + 1] = p end
      table.sort(sorted)
      local function groupEnd(start)
        for _, p in ipairs(sorted) do
          if p > start then return p end
        end
        return 0x8000
      end
      local classNames = self:varNames("TrainerClassNames", count)
      local used = {}
      local rivalSeen = 0
      local function sanitize(text)
        local label = tostring(text or ""):upper():gsub("[^%u%d]+", "_")
        return (label:gsub("^_+", ""):gsub("_+$", ""))
      end
      for group = 1, count do
        local startAddress = ptrs[group]
        local endAddress = groupEnd(startAddress)
        local parties, names = self:gen2TrainerParties(
          sym.bank, startAddress, endAddress, moveOrder)
        local className = classNames[group]
        local plain = sanitize(className)
        local label = plain
        if plain == GEN2_RIVAL_CLASS_NAME then
          rivalSeen = rivalSeen + 1
          label = GEN2_RIVAL_CLASS_NAME .. tostring(rivalSeen)
        end
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
    local names = self:varNames("MoveNames", #order)
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
    local tmCount = self:layout("tmCount", GEN2_TM_COUNT)
    local hmCount = self:layout("hmCount", GEN2_HM_COUNT)
    local total = tmCount + hmCount
      + self:layout("tutorCount", RomExtractorGen2.GEN2_TUTOR_COUNT)
    local ok, bytes = pcall(function()
      return self.rom:bytes(sym.bank, sym.address, total)
    end)
    if ok and type(bytes) == "table" then
      for n = 1, total do
        local move = byIndex[bytes[n] or 0]
        if move then
          local kind, number = "TM", n
          if n > tmCount + hmCount then
            kind, number = "TUTOR", n - tmCount - hmCount
          elseif n > tmCount then
            kind, number = "HM", n - tmCount
          end
          out[n] = { kind = kind, number = number, move = move }
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

-- Crystal pic animations ----------------------------------------------------
--
-- Crystal appends animation tiles to the same compressed front pic -- that is
-- why CYNDAQUIL decompresses to 49 tiles for a 5x5 body -- and drives them
-- from four tables that exist ONLY in Crystal (Gold and Silver have no
-- AnimationPointers symbol at all):
--
--   AnimationPointers      34:$4695   dw per species -> <Mon>Animation
--   AnimationIdlePointers  34:$56A3   dw per species -> <Mon>AnimationIdle
--   BitmasksPointers       34:$64EF   dw per species -> <Mon>Bitmasks
--   FramesPointers         35:$4000   dw per species -> <Mon>Frames
--
-- Everything is bank $34 except the frames, which live in bank $35 below
-- CHIKORITA and $36 from CHIKORITA up: GetMonFramesPointer (34:$45CE) picks
-- the bank with a literal `cp $98 / ld c, $35 / jr c / ld c, $36`.
RomExtractorGen2.GEN2_ANIM_BANK = 0x34
RomExtractorGen2.GEN2_ANIM_FRAMES_SPLIT = 152    -- CHIKORITA
-- ceil(w*h/8), the literal table at 34:$4368 indexed by (width - 5)
RomExtractorGen2.GEN2_ANIM_BITMASK_BYTES = { [5] = 4, [6] = 5, [7] = 7 }
-- a bounded unroll for setrepeat/dorepeat; the longest real script is well
-- under this, and the cap keeps a corrupt table from hanging the import
RomExtractorGen2.GEN2_ANIM_MAX_STEPS = 96

-- One animation script -> a flat list of { frame, duration } steps.
--
-- PokeAnim_DoAnimScript (34:$4250) reads 2-byte commands:
--   $FF ..   end
--   $FE n    setrepeat n
--   $FD i    dorepeat -- jump back to command index i, ZERO-based
--   f  d     hold frame f for d frames ($d173, the speed scaler
--            PokeAnim_GetDuration folds in, is 0 for every PokeAnims entry,
--            so d is plain 60Hz frames)
-- Flattening here rather than at run time keeps the player a cursor over a
-- list; the repeats are small and never nested in the ROM's own scripts.
--
-- NAME: the gen2Pic* prefix is load-bearing.  This file already has a
-- gen2AnimScript far below for BATTLE MOVE animations, and two `function
-- RomExtractorGen2:<same name>` definitions do not collide loudly -- the
-- later one simply wins, so every call here silently reached the move
-- decoder with a symbol name where it wanted a bank, returned nothing, and
-- no species got a picAnim record.
function RomExtractorGen2:gen2PicAnimScript(symbolName, species)
  local table_ = self:symbol(symbolName)
  if not (table_ and self.rom) then return nil end
  local bank = RomExtractorGen2.GEN2_ANIM_BANK
  local commands = {}
  local ok = pcall(function()
    local address = self.rom:word(table_.bank, table_.address + (species - 1) * 2)
    for _ = 1, RomExtractorGen2.GEN2_ANIM_MAX_STEPS do
      local op = self.rom:byte(bank, address)
      local arg = self.rom:byte(bank, address + 1)
      address = address + 2
      if op == 0xFF then break end
      commands[#commands + 1] = { op, arg }
    end
  end)
  if not ok or #commands == 0 then return nil end

  local steps, pc, repeats, guard = {}, 1, 0, 0
  while commands[pc] and guard < RomExtractorGen2.GEN2_ANIM_MAX_STEPS * 4 do
    guard = guard + 1
    local op, arg = commands[pc][1], commands[pc][2]
    if op == 0xFE then
      repeats = arg
      pc = pc + 1
    elseif op == 0xFD then
      if repeats > 0 then
        repeats = repeats - 1
        -- zero-based command index, hence the +1 into this 1-based list
        pc = (repeats > 0) and (arg + 1) or (pc + 1)
        if repeats > 0 and not commands[pc] then break end
      else
        pc = pc + 1
      end
    else
      steps[#steps + 1] = { frame = op, dur = math.max(1, arg) }
      pc = pc + 1
    end
  end
  return steps[1] and steps or nil
end

-- Rebuild one animation frame's tile layout.
--
-- A frame is NOT stored whole.  <Mon>Frames is a dw table; each frame is
-- `db bitmask_index` followed by one tile byte per SET bit of that bitmask.
-- The bitmask is walked LSB first across the pic's cells in COLUMN-major
-- order (the order the pic itself is stored in), and a set bit means
-- "replace this cell with tile <next byte>" -- an index into the WHOLE
-- decompressed blob, animation tiles included.  Cells whose bit is clear
-- keep the base pic's own tile.
function RomExtractorGen2:gen2PicAnimCells(species, cols, rows, count)
  if not (self.rom and count > 0) then return nil end
  local framesTable = self:symbol("FramesPointers")
  local bitmasks = self:symbol("BitmasksPointers")
  if not (framesTable and bitmasks) then return nil end
  local maskBytes = RomExtractorGen2.GEN2_ANIM_BITMASK_BYTES[cols]
  if not maskBytes then return nil end
  local animBank = RomExtractorGen2.GEN2_ANIM_BANK
  local frameBank = (species < RomExtractorGen2.GEN2_ANIM_FRAMES_SPLIT)
    and 0x35 or 0x36
  local out = {}
  local ok = pcall(function()
    local framesAt =
      self.rom:word(framesTable.bank, framesTable.address + (species - 1) * 2)
    local masksAt =
      self.rom:word(bitmasks.bank, bitmasks.address + (species - 1) * 2)
    local cells = cols * rows
    for index = 1, count do
      local at = self.rom:word(frameBank, framesAt + (index - 1) * 2)
      local maskIndex = self.rom:byte(frameBank, at)
      at = at + 1
      local mask = self.rom:bytes(animBank, masksAt + maskIndex * maskBytes,
                                  maskBytes)
      local tiles = {}
      for cell = 0, cells - 1 do
        local byte = mask[math.floor(cell / 8) + 1] or 0
        if math.floor(byte / 2 ^ (cell % 8)) % 2 == 1 then
          tiles[cell + 1] = self.rom:byte(frameBank, at)
          at = at + 1
        else
          tiles[cell + 1] = cell
        end
      end
      out[index] = tiles
    end
  end)
  return ok and out or nil
end

-- The whole record for one species, written next to spriteFront.  `sheet` is
-- a horizontal strip of frames 1..N; frame 0 is the untouched front pic the
-- caller already saved, so the runtime falls back to that image for it.
function RomExtractorGen2:gen2PicAnimation(species, cleanName, pixels,
                                           cols, rows)
  if not self:symbol("AnimationPointers") then return nil end   -- Gold/Silver
  local play = self:gen2PicAnimScript("AnimationPointers", species)
  local idle = self:gen2PicAnimScript("AnimationIdlePointers", species)
  if not (play or idle) then return nil end
  local count = 0
  for _, list in ipairs({ play or {}, idle or {} }) do
    for _, step in ipairs(list) do
      if step.frame > count then count = step.frame end
    end
  end
  if count == 0 then return nil end
  local frames = self:gen2PicAnimCells(species, cols, rows, count)
  if not frames then return nil end

  -- One frame at a time, each through the SAME decode-then-matte the still
  -- pic went through -- matteColor0 flood fills from the image border, so
  -- matting a whole strip at once would let one frame's enclosed white
  -- pocket escape through its neighbour and come out transparent.  Each
  -- frame is assembled column-major (the order the pic is stored in) into
  -- row-major bytes, then pasted into the strip.
  local relative = "battle/anim/" .. cleanName .. ".png"
  local ok = pcall(function()
    local sheet = love.image.newImageData(count * cols * 8, rows * 8)
    for index, tiles in ipairs(frames) do
      local raw = {}
      for byte = 1, cols * rows * 16 do raw[byte] = 0 end
      for cell = 0, cols * rows - 1 do
        local dest = ((cell % rows) * cols + math.floor(cell / rows)) * 16
        local source = (tiles[cell + 1] or cell) * 16
        for byte = 1, 16 do raw[dest + byte] = pixels[source + byte] or 0 end
      end
      local frame = ImageWriter.matteColor0(
        ImageWriter.decode2bpp(raw, cols * 8, rows * 8))
      sheet:paste(frame, (index - 1) * cols * 8, 0, 0, 0, cols * 8, rows * 8)
    end
    self:saveImage(sheet, relative)
  end)
  if not ok then return nil end
  return {
    sheet = "assets/generated/" .. relative,
    count = count,
    width = cols * 8,
    height = rows * 8,
    play = play,
    idle = idle,
  }
end

function RomExtractorGen2:extractPokemon()
  self:beginStage("Gen2 Pokemon")
  local constants = self:constants()
  local speciesOrder = constants.speciesOrder or {}
  local fallbackMove = constants.moveOrder and constants.moveOrder[1] or "TACKLE"

  local pokeNames = gen2ReadFixedNames(self.rom, self:symbol("PokemonNames"), #speciesOrder, 10)
  local learnsets = self:gen2Learnsets(#speciesOrder)

  -- Base stats from BaseData (Crystal 14:5424 / Gold 14:5b0b, dex order).
  -- The stride is the BASE game's 32 unless the manifest overrides it: Prism
  -- packs the same fields into 24.
  local baseSym = self:symbol("BaseData")
  local ENTRY = self:layout("baseDataEntry", 32)
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
        -- species types are plain ids in every ROM checked (Prism's top
        -- value is $1B), so no category bits to mask off here
        type1 = self:gen2TypeName(entry[8]) or "NORMAL"
        type2 = self:gen2TypeName(entry[9]) or type1
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
    -- Crystal only; stays nil on Gold and Silver (no AnimationPointers)
    local picAnim

    if self.rom and cleanName ~= "" then
      -- one LZ3 pic -> one PNG; returns the asset path or nil.
      -- tw/th are the DECLARED geometry: base stats pic_dims for a front pic,
      -- the fixed 6x6 for a back pic.
      local function writePic(symbolName, dir, fileBase, tw, th)
        local sym = self:symbol(symbolName)
        if not sym then return nil end
        local ok1, raw = pcall(function()
          return self.rom:bytes(sym.bank, sym.address, 0x8000 - sym.address)
        end)
        if not ok1 or type(raw) ~= "table" then return nil end
        local ok2, pixels = pcall(decompressLz3, raw)
        if not ok2 or type(pixels) ~= "table" or #pixels < 16 then return nil end
        local tiles = math.floor(#pixels / 16)
        -- Geometry comes from the declared size, NOT from the blob length.
        -- This used to read "the decompressed size is a perfect square, trust
        -- it over pic_dims", which holds in Gold -- every front pic there
        -- decompresses to exactly w*h tiles -- but not in Crystal, where the
        -- frame-animation tiles are appended to the same compressed pic.
        -- Cyndaquil is 25 pic tiles + 24 animation tiles = 49, so the square
        -- rule laid its 5x5 pic out 7 wide and scattered it; same for
        -- Chikorita, Abra, Victreebel, Kingler, Electrode and Shuckle.  The
        -- base pic is the first w*h tiles, still column-major.
        if not (tw and th and tw > 0 and th > 0 and tw * th <= tiles) then
          -- No usable declared size: fall back to the square guess.
          local side = math.floor(math.sqrt(tiles) + 0.5)
          if side * side ~= tiles then return nil end
          tw, th = side, side
        end
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
        -- The tiles past the base pic are Crystal's animation frames, and
        -- `pixels` is the only place they exist in decompressed form -- build
        -- the strip here rather than decompressing the pic a second time.
        if dir == "front" and fileBase == cleanName then
          picAnim = self:gen2PicAnimation(i, cleanName, pixels, tw, th)
        end
        return "assets/generated/" .. relPath
      end

      local function trySprite(symSuffix, dir, dest, tw, th)
        local candidates = { capKey .. symSuffix }
        if cleanName == "nidoran" then
          candidates = { "NidoranM"..symSuffix, "NidoranF"..symSuffix, "Nidoran"..symSuffix }
        elseif cleanName == "unown" then
          candidates = { "UnownA"..symSuffix, "Unown"..symSuffix }
        end
        for _, candidate in ipairs(candidates) do
          local path = writePic(candidate, dir, cleanName, tw, th)
          if path then return path end
        end
        return dest
      end
      -- Front pics wear the species' own pic_dims; every Gen2 BACK pic is
      -- 6x6 regardless (verified: all 278 in both cartridges decompress to
      -- exactly 36 tiles), so they must not inherit a 5x5 species' dims.
      spriteFront = trySprite("Frontpic", "front", spriteFront,
                              picTilesW, picTilesH)
      spriteBack  = trySprite("Backpic",  "back",  spriteBack,
                              GEN2_BACK_PIC_TILES, GEN2_BACK_PIC_TILES)

      -- UNOWN has 26 pics, one per letter, chosen from the DVs
      -- (GetUnownLetter 20:$5749); without them every UNOWN was an "A".
      if cleanName == "unown" then
        forms = {}
        for index = 1, 26 do
          local letter = string.char(64 + index)
          local base = "unown_" .. letter:lower()
          forms[index] = {
            letter = letter,
            spriteFront = writePic("Unown" .. letter .. "Frontpic", "front", base,
                                   picTilesW, picTilesH) or spriteFront,
            spriteBack = writePic("Unown" .. letter .. "Backpic", "back", base,
                                  GEN2_BACK_PIC_TILES, GEN2_BACK_PIC_TILES)
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
      -- Crystal's frame animation for the front pic (see gen2PicAnimation);
      -- absent on Gold and Silver, and the renderer simply holds the still
      picAnim = picAnim,
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
  do
    -- Crystal only; a Gold or Silver import prints 0 here and that is right.
    local animated = 0
    for _, def in pairs(out) do
      if def.picAnim then animated = animated + 1 end
    end
    Logger.info("Gen2 Pokemon: %d pic animations", animated)
  end
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

-- The four banks the dex entries live in, one per 64 species.
--
-- Gold really does compute this: GetDexEntryPointer (11:$4326) ends
-- `and 3 / add a, $68`, so bank = $68 + group.  Crystal replaced that
-- arithmetic with a four-byte LOOKUP -- $60, $6E, $73, $74 -- because its
-- entries no longer sit in consecutive banks.  Applying Gold's formula to
-- Crystal put all 251 entries in the wrong bank: VENONAT's dex text came out
-- as Brock's BOULDERBADGE speech, which is what happens to live at the same
-- address in bank $68.
--
-- Three routines carry the same table (the dex screen, the HEAVY BALL weight
-- check and Pokedex Show); any of them will do, and all three agree.
function RomExtractorGen2:gen2DexEntryBanks()
  if self._gen2DexBanks ~= nil then return self._gen2DexBanks or nil end
  self._gen2DexBanks = false
  for _, name in ipairs({
    "GetDexEntryPointer.PokedexEntryBanks",
    "PokedexShow_GetDexEntryBank.PokedexEntryBanks",
    "HeavyBall_GetDexEntryBank.PokedexEntryBanks",
  }) do
    local sym = self:symbol(name)
    if sym then
      local ok, raw = pcall(self.rom.bytes, self.rom, sym.bank, sym.address, 4)
      -- four real, non-descending ROM banks; anything else is not the table
      if ok and type(raw) == "table" and #raw == 4
         and raw[1] > 0 and raw[4] < self:gen2BankCount()
         and raw[2] >= raw[1] and raw[3] >= raw[2] and raw[4] >= raw[3] then
        self._gen2DexBanks = raw
        break
      end
    end
  end
  return self._gen2DexBanks or nil
end

function RomExtractorGen2:gen2DexEntries(pokemon)
  local table_ = self:symbol("PokedexDataPointerTable")
  if not (self.rom and table_) then return end
  local banks = self:gen2DexEntryBanks()
  local charmap = self:readSourceTable("charmap")
  local texts = self._gen2Texts
  local written = 0
  for _, def in pairs(pokemon) do
    local dex = tonumber(def.dex)
    if dex and dex >= 1 then
      local ok = pcall(function()
        local row = table_.address + (dex - 1) * 2
        local address = self.rom:word(table_.bank, row)
        local group = math.floor((dex - 1) / 64)
        -- the cartridge's own table where it has one, Gold's arithmetic where
        -- it does not (see gen2DexEntryBanks)
        local bank = (banks and banks[group + 1])
          or (GEN2_DEX_POINTER_BANK + group)
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

  -- Crystal: MonMenuIcons maps species -> icon id, then IconPointers is a
  -- `dw` into IconPointers' own bank.  Prism has no MonMenuIcons at all --
  -- its MonIconPointers is a `dba` (bank, lo, hi) indexed by species directly,
  -- and its icons are literally MonIcon1..MonIcon254.  Read Crystal's way the
  -- indirection table is missing, so `if menuSym` was false and the whole
  -- stage produced zero icons with no error: the party menu then drew nothing.
  local iconStride = self:layout("iconEntryBytes", 2)
  if iconStride >= 3 and ptrSym and self.rom then
    for i, id in ipairs(speciesOrder) do
      local colors = monPalettes[id]
      if colors then
        local relPath = "icons/" .. id:lower() .. ".png"
        local ok = pcall(function()
          local entry = ptrSym.address + (i - 1) * iconStride
          local bank = self.rom:byte(ptrSym.bank, entry)
          local address = self.rom:word(ptrSym.bank, entry + 1)
          -- Prism ships every minipic LZ-compressed (gfx/icon/N.2bpp.lz, 78
          -- bytes for the 128 the game unpacks).  Read raw, the compressed
          -- stream was decoded as 2bpp -- the green-and-pink noise, in the
          -- party menu AND on any overworld object whose sprite byte is a mon
          -- (Prism's Larvitar is one).
          local raw = (self:layout("iconsCompressed", 0) ~= 0
                       and self:gen2LzAt(bank, address, GEN2_ICON_BYTES))
            or self.rom:bytes(bank, address, GEN2_ICON_BYTES)
          local tiles = gen2SplitTiles(raw)
          self:saveImage(gen2IconImage(tiles, colors), relPath)
        end)
        -- a table entry (rather than a built-in icon NAME) is what tells
        -- PartyMenu this is authored art
        if ok then bySpecies[id] = { image = "assets/generated/" .. relPath } end
      end
      self:tick("Gen2 party icons", i, #speciesOrder)
    end
  elseif menuSym and ptrSym and self.rom then
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
            local image = gen2IconImage(tiles, colors)
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

-- Gen2 fishing (engine/events/fish.asm `Fish`).  Nothing here existed before:
-- the port ran Gen1's rod rules on a Gen2 cart, so the Old Rod always hooked
-- a level 5 MAGIKARP and the Super Rod -- whose Gen1 table is per-map and has
-- no Gen2 counterpart -- answered "Not even a nibble!" on every cast, on every
-- map, for the whole game.
--
-- The ROM's shape:
--   FishGroups      13 x { db chance; dw old, good, super }   (7 bytes each)
--   <rod table>     rows of { db chance, species, level }, walked until the
--                   rolled byte is <= chance; the last row is `100 percent`
--                   ($FF), so the walk always terminates.
--   species 0       means "read TimeFishGroups instead", and the level byte
--                   is the index into it: { db daySpecies, dayLevel,
--                   niteSpecies, niteLevel }.
-- `chance` on the group itself is the bite roll: Random >= it is no bite.
function RomExtractorGen2:gen2FishRows(bank, address)
  local rows = {}
  for _ = 1, 12 do
    local raw = self.rom:bytes(bank, address, 3)
    local row = { chance = raw[1] }
    if raw[2] == 0 then
      -- the time-of-day indirection; keep the index, resolve at roll time
      row.timeGroup = raw[3]
    else
      row.species = string.format("SPECIES_%03d", raw[2])
      row.level = raw[3]
    end
    rows[#rows + 1] = row
    address = address + 3
    if raw[1] >= 0xFF then break end
  end
  return rows
end

function RomExtractorGen2:gen2Fishing()
  local groupsSym = self:symbol("FishGroups")
  local timeSym = self:symbol("TimeFishGroups")
  if not (groupsSym and self.rom) then return nil, nil end
  local groups = {}
  -- NUM_FISHGROUPS is 13 in Crystal and Gold alike; stop early if the table
  -- runs into TimeFishGroups, which sits right behind the rod rows.
  for i = 0, 12 do
    local base = groupsSym.address + i * 7
    local chance = self.rom:byte(groupsSym.bank, base)
    local entry = { chance = chance, rods = {} }
    for r, rod in ipairs({ "old", "good", "super" }) do
      local ptr = self.rom:word(groupsSym.bank, base + 1 + (r - 1) * 2)
      if ptr >= 0x4000 and ptr < 0x8000 then
        entry.rods[rod] = self:gen2FishRows(groupsSym.bank, ptr)
      end
    end
    -- Keyed by the FISHGROUP_* CONSTANT, not by the row number.  `Fish`
    -- (24:$64C1) runs GetFishGroupIndex first, which ends in `dec d`, so
    -- ROW 0 IS FISHGROUP_SHORE = 1 and row 12 is FISHGROUP_QWILFISH_NO_SWARM
    -- = 13.  The map header byte the runtime looks this up with is that
    -- constant, so keying by the row number shifted every map one group over:
    -- Olivine served OCEAN, the Lake of Rage served DRATINI_2, Ilex Forest's
    -- Super Rod could land a DRAGONAIR, and Corsola and Dratini became
    -- uncatchable.  Routes 12 and 13 (QWILFISH_NO_SWARM = 13) indexed past
    -- the end of the table and never got a bite at all.
    --
    -- It also makes FISHGROUP_NONE fall out for free: `groups[0]` is now nil,
    -- so the runtime's missing-entry path answers "Not even a nibble!" --
    -- which is exactly GetFishingGroup's `and a / jr nz` guard
    -- (engine/events/overworld.asm).  Keyed from 0, Cerulean City (NONE)
    -- borrowed SHORE and handed out Krabby the cart never offers.
    groups[i + 1] = entry
  end
  local times = nil
  if timeSym then
    times = {}
    -- TimeFishGroups has 22 entries in Crystal; read to the end of the block
    -- and let a short table simply not resolve.
    for i = 0, 31 do
      local raw = self.rom:bytes(timeSym.bank, timeSym.address + i * 4, 4)
      if raw[1] == 0 or raw[1] > 251 then break end
      times[i] = {
        day = { species = string.format("SPECIES_%03d", raw[1]), level = raw[2] },
        nite = { species = string.format("SPECIES_%03d", raw[3]), level = raw[4] },
      }
    end
  end
  return groups, times
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

  -- Gold/Crystal split their wild data into exactly four $ff-terminated
  -- tables, so those four names were hardcoded.  A hack is free to use a
  -- different number: Prism has SIX grass tables and two water ones (the four
  -- small grass tables are swarm/special sets), and walking only the first two
  -- silently drops 16 maps' worth of encounters -- the import still succeeds
  -- and those routes just come up empty.  `manifest.wildTables` lists what a
  -- ROM actually has; absent, the Gen 2 four are the default.
  local wildTables = self.manifest and self.manifest.wildTables
  if type(wildTables) ~= "table" or #wildTables == 0 then
    wildTables = {
      { symbol = "JohtoGrassWildMons", terrain = "grass" },
      { symbol = "KantoGrassWildMons", terrain = "grass" },
      { symbol = "JohtoWaterWildMons", terrain = "water" },
      { symbol = "KantoWaterWildMons", terrain = "water" },
    }
  end
  for _, spec in ipairs(wildTables) do
    if type(spec) == "table" and type(spec.symbol) == "string" then
      if spec.terrain == "water" then
        pcall(walk, spec.symbol, "water",
              GEN2_WATER_RECORD, GEN2_WATER_SLOTS, GEN2_WATER_BUCKETS)
      else
        pcall(walk, spec.symbol, "grass",
              GEN2_GRASS_RECORD, GEN2_GRASS_SLOTS, GEN2_GRASS_BUCKETS)
      end
    end
  end

  Logger.info("Gen2 encounters: %d tables from ROM", filled)
  self:write("encounters", out)
  self:tick("Gen2 encounters", 1, 1)
end

-- Walks MapGroupPointers and its 9-byte map headers so ROM (group, number)
-- references -- which is how warps and connections name their targets -- can be
-- resolved back to a map label.
-- MapGroupPointers is followed immediately by the group header tables it
-- points into, so its FIRST entry marks the end of the pointer list and the
-- group count is a property of the ROM rather than something to hardcode.
-- Derives 26 for Gold/Crystal and 95 for Prism.
function RomExtractorGen2:gen2MapGroupCount()
  if self._mapGroupCount then return self._mapGroupCount end
  local count = GEN2_MAP_GROUP_COUNT
  local ptr = self:symbol("MapGroupPointers")
  if ptr and self.rom then
    pcall(function()
      local first = self.rom:word(ptr.bank, ptr.address)
      local derived = math.floor((first - ptr.address) / 2)
      if derived >= 1 and derived <= 512 then count = derived end
    end)
  end
  self._mapGroupCount = count
  return count
end

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
    for group = 1, self:gen2MapGroupCount() do
      starts[group] = self.rom:word(ptr.bank, ptr.address + (group - 1) * 2)
    end
    -- a group's header list runs until the next group's list begins
    local sorted = {}
    for _, address in ipairs(starts) do sorted[#sorted + 1] = address end
    table.sort(sorted)
    local following = {}
    for i, address in ipairs(sorted) do following[address] = sorted[i + 1] end

    for group = 1, self:gen2MapGroupCount() do
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
            -- byte 8 is the map's FISHGROUP_* (map_header's `fish_group`).
            -- Never read before, which is why Gen2 fishing fell through to
            -- the Gen1 rod tables in FieldDefaults -- Old Rod always a L5
            -- MAGIKARP, Super Rod "Not even a nibble!" everywhere, because
            -- its per-map table (field.superRod) is Gen1-only data.
            fishGroup = self.rom:byte(ptr.bank, header + 8),
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

-- Numeric tileset id -> "Tileset<Family>", read from the Tilesets table.
--
-- Each 15 byte entry opens with THREE far pointers -- GFX at +0, Meta (the
-- 16 byte metatile/block definitions) at +3 and Coll (four collision classes
-- per block) at +6 -- and only the three TOGETHER identify a family.  The GFX
-- pointer alone does not: in Crystal SIX families share
-- TilesetRuinsOfAlphGFX (77:$45A1) and TilesetJohtoModern shares 2D:$5EE0
-- with TilesetBattleTowerOutside.  A GFX-only lookup therefore collapsed
--   * tileset 26 and 32-36 (all of Ruins of Alph) onto TilesetAerodactylWordRoom
--   * tileset 2 (JOHTO_MODERN: Azalea Town, Goldenrod City, Routes 33/34)
--     onto TilesetBattleTowerOutside
-- and the loser got the winner's blocks AND the winner's collision.  Wrong
-- Meta is the garbled overworld; wrong Coll is why the Ruins of Alph inner
-- chamber and item rooms have no walkable exit tile -- the hardlock.
-- Gold and Silver have no ambiguous GFX pointer beyond Tileset0/TilesetJohto,
-- which are the same three pointers anyway, so this is a no-op there.
function RomExtractorGen2:gen2TilesetNames()
  if self._tilesetNames then return self._tilesetNames end
  local byId = {}
  self._tilesetNames = byId

  local table_ = self:symbol("Tilesets")
  if not (table_ and self.rom) then return byId end

  local PARTS = { "GFX", "Meta", "Coll" }
  local PTR_AT = { GFX = 0, Meta = 3, Coll = 6 }

  -- Tileset0 and TilesetJohto are byte for byte the same tileset in every
  -- Gen2 ROM, so even a full three-pointer match still has to break that
  -- tie: prefer the descriptive label over the numbered placeholder, then
  -- the longer name, then alphabetical, so the answer cannot flip between
  -- extractions with `pairs` order.
  local function better(candidate, held)
    if not held then return true end
    local function rank(n) return n:match("^Tileset%d+$") and 0 or 1, #n, n end
    local a1, a2, a3 = rank(candidate)
    local b1, b2, b3 = rank(held)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
  end

  local function keyOf(location)
    if type(location) ~= "table" then return nil end
    local bank, address = tonumber(location[1]), tonumber(location[2])
    if not (bank and address) then return nil end
    return math.floor(bank) * 0x10000 + math.floor(address)
  end

  -- string.format rather than `..`: on a 5.3+ host a float-typed key would
  -- concatenate as "393638.0" and never match the integer read out of the
  -- ROM, so the triple is normalised to integers here.
  local function tripleKey(gfx, meta, coll)
    return string.format("%d|%d|%d", gfx, meta, coll)
  end

  -- family -> { GFX = key, Meta = key, Coll = key }, from the symbol table.
  local families = {}
  for name, location in pairs(self.symbols or {}) do
    if type(name) == "string" then
      for _, part in ipairs(PARTS) do
        local family = name:match("^(Tileset.+)" .. part .. "$")
        local key = family and keyOf(location)
        if key then
          local slot = families[family]
          if not slot then slot = {}; families[family] = slot end
          slot[part] = key
        end
      end
    end
  end

  local byTriple, byGfx = {}, {}
  for family, slot in pairs(families) do
    if slot.GFX then
      if better(family, byGfx[slot.GFX]) then byGfx[slot.GFX] = family end
      if slot.Meta and slot.Coll then
        local triple = tripleKey(slot.GFX, slot.Meta, slot.Coll)
        if better(family, byTriple[triple]) then byTriple[triple] = family end
      end
    end
  end

  pcall(function()
    -- 48 was Crystal's roster; Prism has 57, and a fixed ceiling silently
    -- drops every tileset past it along with the maps that use them.
    local stride = self:layout("tilesetEntry", GEN2_TILESET_ENTRY_BYTES)
    local ceiling = self:layout("tilesetCount", 48)
    for id = 0, ceiling - 1 do
      -- the table is indexed directly by tileset id, starting at 0
      local entry = table_.address + id * stride
      if entry + 8 >= 0x8000 then break end
      local keys = {}
      for _, part in ipairs(PARTS) do
        local at = entry + PTR_AT[part]
        keys[part] = self.rom:byte(table_.bank, at) * 0x10000
          + self.rom:word(table_.bank, at + 1)
      end
      local family = byTriple[tripleKey(keys.GFX, keys.Meta, keys.Coll)]
        -- A ROM hack, or a .sym missing a Meta/Coll label, can leave a family
        -- without the full triple.  Fall back to the old GFX-only lookup
        -- rather than dropping the map onto inferTilesetId's name guess.
        or byGfx[keys.GFX]
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
    -- Gold and Crystal stop at 102 sprites, so 127 slots was headroom.  Prism
    -- has 200 sprite_header rows: SPRITE_P0 is slot 0, but SPRITE_P1 is $60,
    -- SPRITE_P0_SURF is $69 and the run of player variants continues past
    -- SPRITE_P12_SURF at $B8 -- so a 128-slot scan cut the table in half and
    -- took every one of the 14 selectable player characters with it.  The
    -- miss-run below is what actually ends the walk; this bound only has to be
    -- big enough not to end it early.  $FF is where the variable-sprite slots
    -- begin, so nothing real lives above it.
    local misses = 0
    for slot = 0, 0xEF do
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
            -- Offset 2 is the macro's `db \2 tiles`.  It is the VRAM
            -- ALLOCATION, not the sheet size -- see the long note by
            -- `bytes` below before trusting it for anything.  Kept because
            -- it is still the right figure for how much of a sheet is
            -- resident at once.
            length = self.rom:byte(table_.bank, entry + 2),
            kind = self.rom:byte(table_.bank, entry + 4),
            palette = self.rom:byte(table_.bank, entry + 5) % 8,
          }
        end
      end
    end
  end)

  -- sheet length = distance to the next sheet in the same bank; the sheets are
  -- laid out back to back, so that distance IS the sheet (see `bytes` below)
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

  local compressed = self:layout("spritesCompressed", 0) ~= 0
  for _, row in ipairs(rows) do
    local cap = GEN2_SPRITE_KIND_BYTES[row.kind] or GEN2_SPRITE_WALK_BYTES
    local span = spanOf[row.bank * 0x10000 + row.address]
    -- The header's length byte is NOT the size of the sheet.  It is the VRAM
    -- allocation: how many tiles the engine keeps resident for one object.
    -- pokecrystal declares
    --     overworld_sprite ChrisSpriteGFX, 12, WALKING_SPRITE, PAL_OW_RED
    -- i.e. `db 12 tiles` = 192 bytes, while gfx/sprites/chris.png is 16x96 =
    -- 24 tiles = 384.  EVERY walking sheet is declared at exactly half its
    -- real size, and STANDING rows all declare 12 as well whether the sheet
    -- is 16x16, 16x32, 16x48 or 16x96.
    --
    -- Preferring that byte therefore halved every walking sheet: 384 -> 192
    -- bytes -> 48px -> 3 frames, and `walker = frames >= 6` (below) went
    -- false, so the walk poses were never drawn and the player and every NPC
    -- SLID across the ground instead of stepping.  Measured against the
    -- cartridges: it sized 19 of Crystal's 102 sheets correctly and 0 of the
    -- 74 walkers; Gold, 0 of 72.
    --
    -- The distance to the next sheet in the same bank is the figure that
    -- actually tracks the sheet, because they are stored back to back.  It
    -- reproduces 101 of Crystal's 102 real sizes -- including the three
    -- STILL rows that are secretly 16x96 (PokeBall, Pokedex, Paper) and the
    -- 16x32 / 16x16 STANDING ones a kind cap used to round UP.  The kind cap
    -- is the fallback for the last sheet in a bank, which has no next sheet
    -- to measure against.  (The one miss is BigOnix, 32x32: last in its bank,
    -- so it falls back to 192 rather than 256.)
    --
    -- 384 is the ceiling either way -- no Gen2 overworld sheet is bigger than
    -- 24 tiles -- so a large gap can never inflate a sheet into its
    -- neighbours, and `height` below floors to whole tiles regardless, which
    -- is what keeps a ragged span from reaching decode2bpp's assert.
    local bytes = cap
    if span and span >= 64 then
      bytes = math.min(span, GEN2_SPRITE_WALK_BYTES)
    end
    -- Prism stores every overworld sheet LZ3-compressed
    -- (`INCBIN "gfx/overworld/p0.2bpp.lz"`), and its walking sprites are 24
    -- tiles rather than Crystal's 12 -- six poses, not three.  Both facts
    -- have to come from the DECOMPRESSED blob: the header's length byte says
    -- 192, which is what Prism copies to VRAM at a time and not how big the
    -- sheet is, so trusting it halves every sheet; and reading the compressed
    -- stream as 2bpp is what made the player character unreadable on screen.
    --
    -- Kept only when the result is a whole number of 16-byte tiles and at
    -- least one 2x2 frame, so a sheet that really is stored raw -- 27 of
    -- Prism's own, and every sheet in Gold and Crystal -- falls through to
    -- the header/span answer above untouched.
    if compressed then
      local out = self:gen2LzAt(row.bank, row.address)
      if out and #out >= 64 and #out % 64 == 0 then
        bytes = #out
        row.compressed = true
      end
    end
    -- 2bpp, 16px wide: one row of pixels is 4 bytes.  Round DOWN to whole
    -- tiles -- decode2bpp requires tile-aligned dimensions and asserts
    -- otherwise, which is a hard crash rather than a skipped sprite.
    local height = math.floor(bytes / 4 / 8) * 8
    if height >= 16 then
      byIndex[row.index] = {
        id = (self:layout("spriteOverrides", 1) ~= 0
              and GEN2_SPRITE_ID_OVERRIDES[row.index] or nil)
             or gen2SpriteConstant(row.base),
        index = row.index,
        -- the *SpriteGFX label this row came from, so a caller can find a
        -- row by its pret name rather than by the engine id it maps onto
        base = row.base,
        file = "sprites/" .. row.base:lower() .. ".png",
        bank = row.bank,
        address = row.address,
        bytes = height * 4,
        compressed = row.compressed,
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
  -- Prism's coord events are SEVEN bytes, Crystal's are eight.  Its
  -- `xy_trigger` is `db number, y, x / dw event / dw script` (macros/map.asm,
  -- XY_TRIGGER_SIZE EQU 7); Crystal's `coord_event` is `db scene, y, x / db 0
  -- / dw script / dw 0`.  One byte per event, and every section AFTER the
  -- coord events is read from the wrong offset -- IntroOutside has six of
  -- them, so its object list came out six bytes adrift: 69 objects on a
  -- campsite that has two, at coordinates like (202, 152) on a 22x36 map.
  -- That is why the player's mother was not standing there.
  local coords = section(self:layout("coordEventBytes", GEN2_COORD_EVENT_BYTES))
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
--
-- The opcodes are taken from the version's own command table.  setevent and
-- the flag commands sit below Crystal's $52 insertion point and so share
-- Gold's numbers, but `variablesprite` does NOT: $6C in Gold, $6D in Crystal
-- (where $6C is faceobject).  Hardcoding $6C meant a Crystal import fell out
-- of this loop's `else break` at the very first variablesprite -- so
-- map_scripts.varSprites came back EMPTY (Route 36's Sudowoodo and Route 37's
-- Twins Ann & Anne both read wVariableSprites slot 4 and drew as
-- placeholders) and every setevent past that point was lost with it.
function RomExtractorGen2:gen2InitialEvents()
  if self._initialEvents then return self._initialEvents end
  local events = {}
  local varSprites = {}
  local sym = self:symbol("InitializeEventsScript")
  if sym then
    pcall(function()
      local commands = Gen2ScriptOps.commandsFor(self.version)
      -- name -> opcode for this version
      local opOf = {}
      for index, command in ipairs(commands) do opOf[command[1]] = index - 1 end
      -- every command the run is made of; all three operand bytes wide
      local SKIP = { clearevent = true, clearflag = true, setflag = true }
      local setevent = opOf.setevent
      local variablesprite = opOf.variablesprite
      local skip = {}
      for name in pairs(SKIP) do
        if opOf[name] then skip[opOf[name]] = true end
      end
      local address = sym.address
      while address < 0x8000 do
        local op = self.rom:byte(sym.bank, address)
        if op == setevent then
          events[self.rom:word(sym.bank, address + 1)] = true
          address = address + 3
        elseif skip[op] then
          address = address + 3
        elseif op == variablesprite then
          -- the ROM operand is the raw slot: the `variablesprite` macro
          -- subtracts SPRITE_VARS ($F0) at assembly time
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
  -- PRISM'S TEXT IS HUFFMAN-COMPRESSED, and a bit stream is not prose.
  -- `ctxt` (macros/text.asm) opens a run with TX_COMPRESSED ($03) and packs
  -- everything after it into Huffman BITS, so the letter-frequency sample
  -- below reads it as noise and threw every one of these blocks away -- which
  -- is why Prism's generic trainers had a battle and no dialogue and its
  -- signs had no words.  That lead byte IS the "this is text" marker, exactly
  -- as $00 is for the uncompressed kind, so it answers on its own; the
  -- decoder downstream already knows how to unpack what follows.
  do
    local ok, lead = pcall(self.rom.byte, self.rom, bank, address)
    if ok and lead == RomExtractorGen2.PRISM_TX_COMPRESSED
       and self:layout("prismCharmap", 0) ~= 0 then
      return bank, address
    end
    -- ...and Prism's OTHER text shape: `text_far` / `text_jump`, three bytes
    -- with no opcode at all -- the target's high byte biased down by $3C, the
    -- low byte, the bank (see decodeGen2TextAt).  A block that is nothing but
    -- one of those is text as surely as a $03 run is, and the letter sample
    -- below cannot see it: three pointer bytes are not prose.
    --
    -- This is what Prism's SIGNPOSTS mostly are.
    if ok and self:layout("prismCharmap", 0) ~= 0
       and lead >= 0x04 and lead <= 0x43 then
      local okLow, low = pcall(self.rom.byte, self.rom, bank, address + 1)
      local okBank, far = pcall(self.rom.byte, self.rom, bank, address + 2)
      if okLow and okBank then
        local target = (lead + 0x3C) * 256 + low
        if target >= 0x4000 and target < 0x8000
           and self:gen2InRom(far % 0x80, target) then
          return bank, address
        end
      end
    end
  end

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
  -- the ORIGINAL address, not `start`: the $00 is only skipped for the prose
  -- sample above.  decodeGen2TextAt needs to see it, because that is what puts
  -- it into PlaceString's dictionary, where $14 is the player's name.
  if printable >= 6 and letters >= printable * 0.85 then return bank, address end
  return nil
end

function RomExtractorGen2:gen2ScriptTextAddress(bank, address, depth)
  if not (bank and address) then return nil end
  -- The scan below reads GOLD's opcode numbers out of the raw bytes -- $51 is
  -- farwritetext, $4C is jumpstd -- and Prism renumbered every one of them, so
  -- against a Prism script it matches whatever bytes happen to sit there and
  -- hands back an address that is not text at all.  Acqua Tutorial's two cave
  -- signs came out as "9{RAM:007F}C]{BYTE:26}..." that way.
  --
  -- Nothing is lost by refusing: this exists to FLATTEN a script into the one
  -- line it prints, for objects the port could not otherwise run, and every
  -- Prism object and signpost now carries its decoded script instead.  A
  -- script that fails to decode goes silent, which beats printing noise.
  if bank < 1 or bank >= self:gen2BankCount() then return nil end
  if address < 0x4000 or address >= 0x8000 then return nil end

  -- signs in particular often point straight at the text block
  local directBank, directAddr = self:gen2TextBlockAt(bank, address)
  if directBank then return directBank, directAddr end

  -- PAST HERE THE SCAN READS OPCODES, AND PRISM RENUMBERED THEM ALL.
  -- What follows walks raw bytes looking for GOLD's numbers -- $51 is
  -- farwritetext, $4C is jumpstd -- so against a Prism script it matches
  -- whatever happens to sit there and hands back an address that is not text.
  -- Acqua Tutorial's two cave signs came out as "9{RAM:007F}C]{BYTE:26}..."
  -- that way, and refusing costs Prism nothing: this exists to FLATTEN a
  -- script into the one line it prints, and every Prism object and signpost
  -- carries its decoded script instead.
  --
  -- THE DIRECT CHECK ABOVE IS A DIFFERENT QUESTION and the refusal used to
  -- sit in front of it, which was the bug.  A `dw seen_text` in a trainer's
  -- data block, or a signpost's text pointer, is already an address -- there
  -- is no bytecode to misread and no version to get wrong.  Refusing those
  -- left all 287 of Prism's generic trainers with a battle and no dialogue,
  -- and its signs with no words at all.
  if self:layout("objectTextKinds", 0) ~= 0 then return nil end


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
      -- Low nibble of map header byte 7: the PALETTE_* this map forces.
      -- ReplaceTimeOfDayPals (23:$40E5 Crystal / 23:$4400 Gold) turns it into
      -- wTimeOfDayPalset, so 0 AUTO follows the clock and 1 DAY / 2 NITE /
      -- 3 MORN / 4 DARK pin the row.  Every INDOOR map carries DAY -- which
      -- is why a Pokemon Center does not go dark at night on hardware -- and
      -- the Ruins of Alph chambers carry it too.
      def.mapPalette = header and header.palette or def.mapPalette
      -- Byte 8 is the FISHGROUP_* constant, and 0 is FISHGROUP_NONE -- NOT
      -- FISHGROUP_SHORE, which is 1 (constants/map_data_constants.asm).
      -- gen2Fishing keys its table by that same constant, so 0 finds nothing
      -- and the runtime answers "Not even a nibble!", matching the ROM's own
      -- `GetFishingGroup / and a / jr nz` guard.
      def.fishGroup = header and header.fishGroup or def.fishGroup

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
            -- Prism ships every map's block table LZ3-compressed
            -- (`INCBIN "maps/blk/IntroOutside.ablk.lz"`) and decompresses it
            -- at map load; Gold and Crystal store it raw.  Read raw, a Prism
            -- map's blocks ARE the compressed stream -- ids scattered over
            -- the whole 0..255 range against a tileset that has 177 blocks --
            -- so the very first map of a new game indexes past the metatile
            -- table.  gen2LzAt keeps the result only if it is exactly
            -- width*height bytes, which is the header's own answer for how
            -- big the table is, so this cannot misfire on a raw cartridge.
            def.blocks = self:gen2LzAt(bank, blocksPtr, width * height)
              or self.rom:bytes(bank, blocksPtr, width * height)
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
            local monBase = self:layout("spritePokemonBase", GEN2_SPRITE_POKEMON)
            local breed1 = self:layout("spriteBreedFirst", GEN2_SPRITE_BREED_1)
            local breed2 = self:layout("spriteBreedSecond", GEN2_SPRITE_BREED_2)
            if row[1] >= GEN2_SPRITE_VARS then
              -- $F0+ indexes wVariableSprites.  Copycat and some gym
              -- impersonators are driven this way; still honour an override
              -- if the constant was pinned (e.g. SPRITE_COPYCAT at $FB).
              spriteId = GEN2_SPRITE_ID_OVERRIDES[row[1]]
                or string.format("SPRITE_VAR_%02d", row[1] - GEN2_SPRITE_VARS)
            elseif row[1] == breed1 then
              spriteId = "SPRITE_MON_BREED_1"
            elseif row[1] == breed2 then
              spriteId = "SPRITE_MON_BREED_2"
            elseif row[1] >= monBase then
              local species = spriteMons[row[1] - monBase]
              -- falling back to the OverworldSprites row before SPRITE_RED:
              -- a mon slot with no species is still likelier to be the sheet
              -- at that index than the player
              spriteId = species and gen2MonSpriteId(species)
                or (sprite and sprite.id) or "SPRITE_RED"
            else
              -- Prefer explicit Kanto/story overrides, then the OverworldSprites
              -- table id, then GRAMPS only as a last resort so Misty / Rocket /
              -- Super Nerd / etc. never silently become an old man.  The
              -- overrides are Gold's INDICES, so a ROM that renumbered the
              -- sprite list must opt out of them -- Prism's $01 is its first
              -- player sheet, not SPRITE_RED, and its $54 is not a POKe BALL.
              spriteId = (self:layout("spriteOverrides", 1) ~= 0
                          and GEN2_SPRITE_ID_OVERRIDES[row[1]] or nil)
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
            -- Crystal's itemball field is a POINTER to `itemball ITEM` --
            -- `db item, db qty` sitting in the script bank.  Prism's is the
            -- item ITSELF: Events' `.itemball` reads MAPOBJECT_PARAMETER for
            -- the quantity and PARAMETER+1 (the low byte of the same field the
            -- other kinds use as a pointer) for the item.  Read Crystal's way
            -- the "pointer" was a small number, failed the in-bank test, and
            -- the ball fell through to the text branch -- which then registered
            -- the item id as a text address, so every Prism item ball printed
            -- a line decoded out of whatever bytes lived at $0028.
            if kind == GEN2_OBJECT_KIND_ITEMBALL
               and self:layout("objectItemInline", 0) ~= 0 then
              item = row[10]
              quantity = row[9]
            elseif kind == 3
               and self:layout("objectItemInline", 0) ~= 0 then
              -- PERSONTYPE_TMHMBALL.  `.tmhm` reads the machine number out
              -- of PARAMETER; the port has
              -- no machine-number-to-item map, so record it and leave the ball
              -- inert rather than handing out the wrong item
              object.machine = row[9]
            elseif script and kind == GEN2_OBJECT_KIND_ITEMBALL then
              item = self.rom:byte(bank, scriptAddress)
              quantity = self.rom:byte(bank, scriptAddress + 1)
            elseif kind == RomExtractorGen2.GEN2_OBJECT_KIND_FRUITTREE
               and self:layout("objectTextKinds", 0) ~= 0 then
              -- Prism gives berry trees a PERSONTYPE of their own and puts the
              -- tree id straight in the parameter field, so there is no script
              -- to sniff at all.
              fruitTree = row[9]
              item = fruitTreeItems[fruitTree]
              quantity = 1
            elseif script and kind == GEN2_OBJECT_KIND_SCRIPT
                and self.rom:byte(bank, scriptAddress) == self:opcode("fruittree") then
              -- A berry tree is scenery that happens to hand out an item; it
              -- must stay on the map once picked, unlike an item ball, and
              -- FruitTreeScript keys its once-a-day flag off the tree id.
              --
              -- GATED ON THE OBJECT KIND, and deliberately.  This branch used
              -- to sniff the first byte behind EVERY object's pointer field,
              -- but only a SCRIPT object's pointer is a script: a TRAINER's is
              -- a 12-byte header opening `dw EVENT_BEAT_*`, so a trainer whose
              -- beat-event low byte happened to equal the opcode was read as a
              -- berry tree -- Gentleman Preston on Olivine Lighthouse 3F, in
              -- both Gold and Crystal, whose EVENT_BEAT_GENTLEMAN_PRESTON ends
              -- $9A.  He stood there as scenery handing out a BERRY instead of
              -- battling.  Route 41's Olivine rival object went the same way.
              fruitTree = self.rom:byte(bank, scriptAddress + 1)
              item = fruitTreeItems[fruitTree]
              quantity = 1
            elseif kind == GEN2_OBJECT_KIND_TRAINER
                or (kind == RomExtractorGen2.GEN2_OBJECT_KIND_GENERICTRAINER
                    and self:layout("objectTextKinds", 0) ~= 0) then
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
                  -- A GENERICTRAINER's block is `dw flag / db group, id /
                  -- dw seen, win` and the two extra words are OPTIONAL
                  -- (macros/trainer.asm, `IF _NARG > 5`).  With only five
                  -- arguments the bytes at +10 are the trainer's own TEXT,
                  -- and reading them as a pointer registers a line decoded
                  -- out of the middle of a sentence, so the after-battle
                  -- line is taken only from the fixed 12-byte layout.
                  if kind == GEN2_OBJECT_KIND_TRAINER then
                    header.after = registerText("AFTER", self.rom:word(bank, scriptAddress + 10))
                  end
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
              local ok, textBank, textAddr
              if RomExtractorGen2.GEN2_OBJECT_KIND_TEXT[kind]
                 and self:layout("objectTextKinds", 0) ~= 0
                 and (kind == 5 or kind == 6) and script then
                -- PERSONTYPE_TEXT / _TEXTFP: the pointer IS the dialogue.
                -- gen2ScriptTextAddress exists to WALK a script looking for
                -- the text it writes, and walking dialogue as a script is
                -- what handed out that GLACEON -- so take the pointer as
                -- given, the same way a writetext operand is taken as given.
                ok, textBank, textAddr = true, self:gen2Home(bank, scriptAddress),
                  scriptAddress
              else
                ok, textBank, textAddr = pcall(
                  self.gen2ScriptTextAddress, self, bank, scriptAddress)
              end
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
            elseif self:layout("objectTextKinds", 0) ~= 0 then
              -- Prism: every signpost that is not a hidden item carries a
              -- SCRIPT, and the map-scripts pass links it (including the two
              -- std kinds).  The scaffold's own guess for this const came from
              -- a `<Map><Thing>_Text` symbol-name heuristic that assigns one
              -- label to every sign on the map and, on Prism, usually names
              -- something that is not text at all -- Acqua Tutorial's four
              -- cave signs all resolved to AcquaTutorialFirstSoil_Text and
              -- printed "{BYTE:41}...{RAM:BC87}...".  Drop it: the script is
              -- the behaviour, and a silent sign beats a noisy one.
              --
              -- Dropping the guess used to be the whole branch, on the grounds
              -- that the map-scripts pass links a SCRIPT for every Prism
              -- signpost.  IT DOES NOT: only 250 of 591 get one, and the other
              -- 341 were left showing a generated "You read the sign. <Map>."
              -- stub or nothing at all, where Gold and Crystal print the
              -- cartridge's words on every sign they have.
              --
              -- gen2TextBlockAt answers the narrow question -- "are these
              -- bytes text?" -- and now knows both of Prism's text shapes, so
              -- ask it.  This is the DIRECT check, not the opcode scan that
              -- had to be refused: a signpost's pointer is already an address,
              -- and there is no bytecode to misread.  A sign that also has a
              -- script still runs it; talk rows win over flat text.
              if textPointers[mapId] then textPointers[mapId][textConst] = nil end
              local okText, textBank, textAddr =
                pcall(self.gen2TextBlockAt, self, bank, ptr)
              if okText and textBank then
                self._gen2ScriptTexts[textConst] =
                  { bank = textBank, address = textAddr }
                textPointers[mapId] = textPointers[mapId] or {}
                textPointers[mapId][textConst] = { text = textConst }
              end
            elseif kind ~= 8 then
              -- 9 is Prism's SIGNPOST_JUMPSTDNOSFX: a std INDEX in the
              -- pointer slot, and walking it for text is what scrambled the
              -- Rock Smash sign
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

-- A bare $50-terminated name sitting in a script's own bank -- what
-- `getstring` points at.  Unlike a writetext operand this is NOT a text
-- script (no opener byte, no line breaks, never reused), so it is decoded
-- straight to a Lua string rather than registered in the text table.
function RomExtractorGen2:gen2ReadInlineString(bank, address, maxLen)
  if not self:gen2InRom(bank, address) then return nil end
  bank = self:gen2Home(bank, address)
  local ok, bytes = pcall(function()
    return self.rom:bytes(bank, address, maxLen or 16)
  end)
  if not (ok and type(bytes) == "table") then return nil end
  return gen2DecodeString(bytes, maxLen or 16)
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
    --
    -- The leading $00 is kept, NOT skipped.  It prints nothing, which is why
    -- skipping it looked free, but it is also TX_START -- the byte that hands
    -- the rest of the run to PlaceString, where $14 is the player's name
    -- rather than TX_STRINGBUFFER.  Starting one byte late is why every line a
    -- map script writes still printed the player's name as the last item
    -- picked up, long after the named symbol texts were fixed.
    known[const] = { bank = bank, address = address }
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
  -- Script BYTECODE never sits in the home bank.  Everything below $4000 in
  -- both disassemblies is engine code -- CallScript, QueueScript, the RST
  -- vectors, the Nintendo logo -- so a pointer that lands there is a pointer
  -- that was never a script pointer, and walking it produces a script-shaped
  -- run of nonsense that then queues more of the same.  Prism was decoding 229
  -- of these (Crystal 13), starting at $0100, the cartridge entry point.
  if address < 0x4000 then return nil end
  bank = self:gen2Home(bank, address)
  local label = gen2ScriptLabel(bank, address)
  if pool.scripts[label] == nil then
    pool.scripts[label] = false
    pool.queue[#pool.queue + 1] = { bank, address, label }
  end
  return label
end

-- `jumptable <ptr>` (Script_scriptjumptable, engine/scripting.asm) indexes a
-- table of `dw` script pointers by the script variable and CALLS the entry
-- (`ld b, 1` then ScriptJumptable, whose `jp z, LocalScriptJump` is only taken
-- for anonjumptable's b=0).  Nothing in the stream says how long the table is,
-- so the walk is bounded by the table's own targets: Prism writes the cases
-- directly after the table, so the first entry that points into the bytes the
-- table has already claimed -- or out of the bank -- is the end of it.
--
--     .MiningModes:                     <- the pointer
--         dw .onlyCheckIronPick         <- and the table stops here, because
--         dw .smartCheckBothPicks          .onlyCheckIronPick is the first
--         dw .onlyCheckNormalPicks         byte after the third dw
--     .onlyCheckIronPick:
--
-- Over-reading is the failure that matters: an extra entry queues whatever
-- follows as a script, and Prism's script bytes decode into something.
-- `ptcall <ptr>` / `ptjump <ptr>` do not name a script: they name a
-- THREE-BYTE far pointer -- `ld b, [hl] / ld e, [hl] / ld d, [hl]`, bank then
-- address -- and jump through it.  Prism uses the shape for the tables that
-- pick which version of a scene to run.  Where the pointer sits in ROM it can
-- be followed here; where it sits in WRAM ($c000 and up) it is filled in at
-- run time and there is nothing to resolve, so the row is dropped rather than
-- pointed at whatever happens to be at that address in the ROM image.
function RomExtractorGen2:gen2FarPointerScript(bank, address, pool)
  if type(address) ~= "number" or address < 0x4000 or address >= 0x8000 then
    return nil
  end
  local far = self.rom:byte(bank, address)
  local target = self.rom:word(bank, address + 1)
  return self:gen2QueueScript(far, target, pool)
end

RomExtractorGen2.GEN2_TEXT_FROM_HALFWORD = "<halfwordvar>"
RomExtractorGen2.GEN2_JUMPTABLE_MAX = 24

function RomExtractorGen2:gen2JumpTable(bank, address, pool)
  if type(address) ~= "number" then return nil end
  local low = bank == 0 and 0x0000 or 0x4000
  local high = bank == 0 and 0x4000 or 0x8000
  if address < low or address >= high then return nil end
  local out, stop = {}, high
  for i = 0, RomExtractorGen2.GEN2_JUMPTABLE_MAX - 1 do
    local at = address + i * 2
    if at + 2 > stop then break end
    local target = self.rom:word(bank, at)
    if target < low or target >= high then break end
    -- a case that starts inside the table is the table's own end
    if target > address and target < stop then stop = target end
    if at + 2 > stop then break end
    local label = self:gen2QueueScript(bank, target, pool)
    if not label then break end
    out[#out + 1] = label
  end
  if #out == 0 then return nil end
  return out
end

-- `loadarray <ptr>, <entry size>` (Script_loadarray) parks a far pointer, an
-- entry size and a current-entry index; `readarray <i>` / `readarrayhalfword
-- <i>` then read base + size * entry + i.  The runtime has no ROM to reach
-- back into, so the bytes come out here.
--
-- Length is not in the stream either.  A window is read and clamped to the
-- bank; the halfword view is what carries dialogue -- MiningScript's
-- `loadarray .MiningFailureTextsArray / readarrayhalfword 0 / jumptext -1` is
-- a table of TEXT pointers, and a pointer alone is useless to the port -- so
-- each plausible in-bank halfword is registered as text and the resulting
-- label kept alongside the raw value.
RomExtractorGen2.GEN2_ARRAY_WINDOW = 64

function RomExtractorGen2:gen2ScriptArray(bank, address, size, wantTexts)
  if type(address) ~= "number" then return nil end
  local low = bank == 0 and 0x0000 or 0x4000
  local high = bank == 0 and 0x4000 or 0x8000
  if address < low or address >= high then return nil end
  local count = math.min(RomExtractorGen2.GEN2_ARRAY_WINDOW, high - address)
  local bytes, words = {}, {}
  for i = 0, count - 1 do bytes[i + 1] = self.rom:byte(bank, address + i) end
  for i = 0, math.floor(count / 2) - 1 do
    words[i + 1] = bytes[i * 2 + 1] + bytes[i * 2 + 2] * 256
  end
  local texts
  if wantTexts then
    -- Only the scripts that actually READ halfwords get their entries decoded,
    -- and the run stops at the first value that is not a pointer into this
    -- bank: a byte array read as words is nothing but junk pointers, and
    -- registering those would fill the text pool with decoded noise.
    texts = {}
    for i = 1, #words do
      local w = words[i]
      if w < low or w >= high then break end
      texts[i] = self:gen2RegisterScriptText(bank, w) or false
    end
    if #texts == 0 then texts = nil end
  end
  return { bytes = bytes, words = words, texts = texts,
           size = tonumber(size) or 0 }
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
  -- Crystal inserts farjumptext at $52 and shifts 88 commands after it, so
  -- the table has to be chosen per version -- decoding Crystal with Gold's
  -- table desyncs on the first shifted opcode and never recovers.
  local commands = Gen2ScriptOps.commandsFor(self.version)
  local rows = {}
  -- set when the PREVIOUS command was a `sif` with no `then`: the command now
  -- being read is that conditional's whole body (see the break test below)
  local conditionalGuard = false
  -- How many `sif ... then` blocks are open at this point in the byte
  -- stream.  See the terminator rule at the bottom of the loop.
  local sifDepth = 0
  local arrays = nil
  local limit = bank == 0 and 0x4000 or 0x8000
  local pc = address
  for _ = 1, GEN2_SCRIPT_MAX_STEPS do
    if pc >= limit then break end
    local op = self.rom:byte(bank, pc)
    local command = commands[op + 1]
    if not command then
      -- a handful of object "script pointers" in the ROM address text or data;
      -- record the stall instead of walking off into noise
      rows[#rows + 1] = { "unknown", op }
      pool.desyncs = pool.desyncs + 1
      -- Naming what came BEFORE is what makes a desync actionable: a run of
      -- them all following the same command is a missing terminator or a bad
      -- width for that one command, where "<start>" means the pointer was
      -- never a script to begin with (an object whose "script" addresses text
      -- or data, which the ROM itself never executes).
      Logger.warn("gen2 script desync: %s (%02X:%04X) opcode %02X after %s",
                  tostring(label), bank, pc, op,
                  tostring(rows[#rows - 1] and rows[#rows - 1][1] or "<start>"))
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
        local raw = self.rom:word(bank, pc)
        -- Prism's GetScriptHalfwordOrVar reads $ffff as "use the halfword
        -- variable", which is how `loadarray / readarrayhalfword / jumptext -1`
        -- prints a line chosen out of a table.  $ffff is not an address, so
        -- registering it yielded nothing and the box came up empty.
        value = raw == 0xFFFF and RomExtractorGen2.GEN2_TEXT_FROM_HALFWORD
          or self:gen2RegisterScriptText(bank, raw)
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
    elseif name == "getstring" then
      -- row[2] is the STRING pointer (the operand order is `dw string, db
      -- buffer`), and the bytes it points at are a plain $50-terminated
      -- name, not a text script.  Resolve it here so the VM never has to
      -- reach back into the ROM: `getstring "EXPN CARD", 1` becomes a
      -- literal the `jumpstd receiveitem` after it can print.
      row[2] = self:gen2ReadInlineString(bank, row[2]) or row[2]
    elseif name == "jumptable" then
      row[2] = self:gen2JumpTable(bank, row[2], pool) or row[2]
    elseif name == "ptcall" or name == "ptjump" then
      row[2] = self:gen2FarPointerScript(bank, row[2], pool) or ""
    elseif name == "loadarray" then
      -- resolved after the walk: whether the entries are TEXT pointers is not
      -- knowable here, only from whether a readarrayhalfword follows
      arrays = arrays or {}
      arrays[#arrays + 1] = { row, row[2] }
    elseif name == "loadmenu" then
      row[2] = self:gen2MenuItems(bank, row[2]) or row[2]
    elseif name == "writecmdqueue" then
      row[2] = self:gen2StoneTable(bank, row[2], pool) or row[2]
    elseif name == "special" then
      -- Carry the special's pret NAME alongside its index.  The index alone
      -- is not portable: Crystal inserts BattleTowerFade at $2F, so 59 of
      -- Gold's specials sit one slot higher there.  Lowered against Gold's
      -- numbering, a Crystal script asking for $3D got HealMachineAnim (Poke
      -- Balls floating over whoever you were talking to) and one asking for
      -- $4A got GiveShuckle -- which is where the two SHUCKIE came from.
      row[3] = self:gen2SpecialNames()[row[2]]
    end
    rows[#rows + 1] = row
    pool.instructions = pool.instructions + 1
    -- Prism writes its map events with BLOCK-STRUCTURED conditionals
    -- (macros/event.asm `sif`), and the two shapes guard different amounts:
    --
    --     sif true, then     sif true
    --       <many commands>    <ONE command>
    --     sendif
    --
    -- With no `then` marker the conditional covers exactly the command that
    -- follows it, so a terminator sitting there ends the BRANCH, not the
    -- script -- IntroOutside's `.init_events` is `checkevent / sif true /
    -- return / jumpstd initializeevents`, and stopping at that `return` threw
    -- away the jumpstd that actually initialises the game's events.
    --
    -- `sif ... then` needs no such rule: its body runs to `sendif`, and any
    -- terminator inside it really does leave the script.
    local guardsNext = conditionalGuard
    local wasSif = conditionalGuard and true or false
    conditionalGuard = Gen2ScriptOps.SIF_COMMANDS_PRISM
      and Gen2ScriptOps.SIF_COMMANDS_PRISM[name] or false
    -- `scriptstartasm` IS Prism's `then` marker -- the macro says so outright
    -- (`then_command EQU scriptstartasm_command`) -- so one opcode means two
    -- different things depending on what precedes it.  After a `sif` it opens
    -- a block; anywhere else the bytes that follow are Z80 machine code, and
    -- walking into those is what "opcode F0 after scriptstartasm" was.
    if name == "scriptstartasm" then
      if wasSif then
        sifDepth = sifDepth + 1
      else
        break
      end
    elseif name == "sendif" and sifDepth > 0 then
      sifDepth = sifDepth - 1
    end
    -- A TERMINATOR INSIDE A `sif ... then` BLOCK ENDS THE BRANCH, NOT THE
    -- SCRIPT.  ScriptConditional skips a false block by walking commands to
    -- its `sendif` and carrying on past it, so everything after the block is
    -- still live code -- and this walker used to stop dead at the first
    -- terminator inside one.  IlksLabProfIlk is the case that shows it:
    --
    --     checkevent EVENT_MET_ILK_PRE / sif false, then
    --       ... / jumptextfaceplayer .first_encounter_text
    --     sendif
    --     faceplayer / opentext / checkevent EVENT_RIVAL_ROUTE_69 / ...
    --
    -- The decode stopped on that `jumptextfaceplayer`, so the professor's
    -- entire script after the first meeting -- the Pokedex hand-off and every
    -- later line -- was never decoded at all, and talking to him again did
    -- nothing.  Only a terminator at depth 0 leaves the script.
    if Gen2ScriptOps.terminatorsFor(self.version)[name] and not guardsNext
       and sifDepth == 0 then
      break
    end
  end
  -- `loadarray` names a blob whose entries are bytes or halfwords depending
  -- on which read command indexes it, and that command comes LATER in the
  -- stream.  MiningScript's `.MiningFailureTextsArray` is a table of text
  -- pointers, read with `readarrayhalfword 0` and printed by `jumptext -1`;
  -- the same script's other arrays are plain bytes.  Decide once, here, where
  -- the whole script is visible.
  if arrays then
    local wantTexts = false
    for _, r in ipairs(rows) do
      if r[1] == "readarrayhalfword" then wantTexts = true break end
    end
    for _, entry in ipairs(arrays) do
      local row, address = entry[1], entry[2]
      row[2] = self:gen2ScriptArray(bank, address, row[3], wantTexts) or address
    end
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
-- The table's own first pointer closes it -- StdScripts is at 47:$4000 and its
-- row 0 points at 47:$409C, so the rows fill exactly $9C bytes.  This used to
-- be a hardcoded 46, which is GOLD's count: Crystal has FIFTY-TWO, and the six
-- it adds are GymStatue2Script, ReceiveItemScript, ReceiveTogepiEggScript,
-- PCScript, GameCornerCoinVendorScript and HappinessCheckScript.  All six were
-- dropped, so `jumpstd` to any of them ran nothing at all -- the Goldenrod
-- Game Corner coin vendor stood silent, and so did every in-house PC.
local GEN2_STD_SCRIPT_MAX = 64

function RomExtractorGen2:gen2QueueStdScripts(pool)
  local sym = self:symbol("StdScripts")
  if not sym or not self.rom then return nil end
  local count = GEN2_STD_SCRIPT_MAX
  pcall(function()
    local first = self.rom:word(sym.bank, sym.address + 1)
    local rows = math.floor((first - sym.address) / 3)
    if rows > 0 and rows <= GEN2_STD_SCRIPT_MAX then count = rows end
  end)
  local out = {}
  for index = 0, count - 1 do
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
    -- The contact's OWN map, bytes 3 and 4.  GetAvailableCallers (36:$40DE)
    -- compares it against wMapGroup/wMapNumber and drops the contact from the
    -- sample when they match, so a trainer never phones you from the route you
    -- are standing on; RandomPhoneWildMon looks up the same map's grass table
    -- for the species its line names.  Both were unreachable without this.
    if entry then entry.group, entry.number = row[3], row[4] end
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
            -- PERSONTYPE_JUMPSTD (7) carries a STD INDEX where every other kind
            -- carries a pointer: Prism's smashable rocks are `person_event
            -- SPRITE_ROCK, ..., PERSONTYPE_JUMPSTD, 0, smashrock, -1`, and so
            -- are its signs and its PC/mart counters.  With nothing linked the
            -- object had no script at all and printed the placeholder name of
            -- a text entry that was never registered.
            if kind == 7 and self:layout("objectTextKinds", 0) ~= 0 then
              self._gen2Stds = self._gen2Stds or self:gen2QueueStdScripts(pool)
              label = self._gen2Stds
                and self._gen2Stds[row[GEN2_OBJECT_ROW_SCRIPT]] or nil
            elseif not self:gen2InRom(bank, pointer) then
              label = nil
            else
              -- a pointer below $4000 lives in the always-mapped home bank
              local pbank = self:gen2Home(bank, pointer)
              if kind == RomExtractorGen2.GEN2_OBJECT_KIND_GENERICTRAINER
                 and self:layout("objectTextKinds", 0) ~= 0 then
                -- PRISM'S GENERIC TRAINER POINTS AT DATA, NOT AT A SCRIPT.
                -- macros/trainer.asm is `dw flag / db group, id / dw seen,
                -- win` and optionally two more words -- eight or twelve bytes
                -- with no bytecode anywhere in them, the trainer's dialogue
                -- following inline.  Queued as a script the walker decoded the
                -- event flag's low byte as an opcode, which is every one of
                -- the "opcode $EC..$FF after <start>" desyncs: 40 of them, and
                -- one per generic trainer on the map.  The header branch above
                -- already reads the block properly; there is nothing here to
                -- walk.
                label = nil
              elseif kind == GEN2_OBJECT_KIND_TRAINER then
                label = self:gen2QueueScript(
                  pbank, pointer + GEN2_TRAINER_HEADER_BYTES, pool)
                local after = self.rom:word(
                  pbank, pointer + GEN2_TRAINER_HEADER_AFTER)
                afters[i] = self:gen2QueueScript(pbank, after, pool)
              elseif RomExtractorGen2.GEN2_OBJECT_KIND_TEXT[kind]
                     and self:layout("objectTextKinds", 0) ~= 0 then
                -- Prism's PERSONTYPE_TEXT (5) and PERSONTYPE_TEXTFP (6) point
                -- at TEXT, not at a script.  Queueing them as scripts walks
                -- dialogue through the script decoder, and a text byte is a
                -- perfectly valid opcode -- the campfire on the opening map is
                -- PERSONTYPE_TEXT, and its first line decoded into a `givepoke`
                -- that handed out a level 17 GLACEON every time it was talked
                -- to.  Anything the ROM stores as text has to be READ as text.
                label = nil
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
          -- The script sits at a different offset in the two layouts.
          -- Crystal: `db scene, y, x / db 0 / dw script / dw 0` -- offset 4.
          -- Prism:   `db number, y, x / dw event / dw script`   -- offset 5,
          -- because it carries an event word the base game does not have.
          -- Reading Prism at offset 4 splices the event's high byte onto the
          -- script's low byte, so most triggers resolved to nothing: of
          -- IntroOutside's six, only the two whose bytes happened to survive
          -- came through -- the pair that starts the earthquake, and neither
          -- of the pairs around it.
          local scriptAt = self:layout("coordEventScript", GEN2_COORD_ROW_SCRIPT)
          for _, row in ipairs(events.coords) do
            local pointer = row[scriptAt]
              + row[scriptAt + 1] * 256
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
            --
            -- Prism reuses 8 and adds 9 for something else entirely:
            -- SIGNPOST_JUMPSTD and SIGNPOST_JUMPSTDNOSFX, whose `signpost`
            -- macro writes `db <std>, db 0` where every other kind writes a
            -- pointer.  Read as one, 9 walked a std INDEX looking for text and
            -- printed whatever bytes lived down there -- the scrambled sign --
            -- and 8, already excluded, simply said nothing at all.
            local std = self:layout("objectTextKinds", 0) ~= 0
              and (kind == 8 or kind == 9) and row[4] or nil
            if std then
              self._gen2Stds = self._gen2Stds or self:gen2QueueStdScripts(pool)
              local label = self._gen2Stds and self._gen2Stds[std]
              if label then
                signs[i] = label
                signCount = signCount + 1
              end
            elseif kind ~= GEN2_BG_EVENT_ITEM and kind ~= 8 then
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
-- ---------------------------------------------------------------------------
-- Prism's compressed text
--
-- Crystal stores dialogue as one charmap byte per character.  Prism stores it
-- HUFFMAN-CODED, as a bit stream introduced by TX_COMPRESSED ($03), and
-- decodes it a character at a time in PrintCompressedString
-- (engine/compressed_text.asm).  Read as plain charmap bytes, what comes out
-- is the bit stream itself -- which on screen is the scrambled dialogue.
--
-- TextCompressionHuffmanTree is two bytes per non-leaf node, root first: at
-- node n, bit b selects tree[n * 2 + b].  A value below $70 is the next node;
-- $70 and up is a leaf.  The leaf then needs unpacking, because the tree packs
-- three different things into one byte range (GenerateCompressedTextBuffer):
--
--   $BC-$CF  ->  value - $78   the control characters $44-$57
--   $78-$7B  ->  value - $20   the control characters $58-$5B
--   $7C      ->  read 6 more bits, index TextCompressionSpecialValues64
--   $7D      ->  read 4 more bits, index TextCompressionSpecialValues16
--   anything else prints as itself
--
-- Bits are MSB-first within each byte (the ROM shifts with `sla e`).
RomExtractorGen2.PRISM_TX_COMPRESSED = 0x03
RomExtractorGen2.PRISM_HUFFMAN_LEAF = 0x70

function RomExtractorGen2:gen2PrismTextTables()
  if self._prismText ~= nil then return self._prismText or nil end
  self._prismText = false
  local tree = self:symbol("TextCompressionHuffmanTree")
  if not (tree and self.rom) then return nil end
  local ok, tables = pcall(function()
    -- The tree is at most $70 non-leaf nodes, so 224 bytes covers it.
    local nodes = self.rom:bytes(tree.bank, tree.address, 0x70 * 2)
    local out = { tree = nodes, bank = tree.bank }
    local s16 = self:symbol("TextCompressionSpecialValues16")
    if s16 then out.special16 = self.rom:bytes(s16.bank, s16.address, 16) end
    local s64 = self:symbol("TextCompressionSpecialValues64")
    -- (count, initial + count) pairs, walked until the running subtraction
    -- borrows; four pairs cover the whole 64
    if s64 then out.special64 = self.rom:bytes(s64.bank, s64.address, 8) end
    return out
  end)
  if not ok or type(tables) ~= "table" then return nil end
  self._prismText = tables
  return tables
end

-- Decode one TX_COMPRESSED run starting at `address` (which must point AT the
-- TX_COMPRESSED byte).  Returns the decoded character bytes, ready for the
-- ordinary charmap, and the address just past the run.
function RomExtractorGen2:gen2PrismDecompressText(bank, address)
  local t = self:gen2PrismTextTables()
  if not t then return nil end
  local out = {}
  local pc = address + 1          -- past TX_COMPRESSED
  local limit = bank == 0 and 0x4000 or 0x8000
  local cur, bitsLeft = 0, 0
  local function bit()
    if bitsLeft == 0 then
      if pc >= limit then return nil end
      cur = self.rom:byte(bank, pc)
      pc = pc + 1
      bitsLeft = 8
    end
    local b = math.floor(cur / 128) % 2
    cur = (cur * 2) % 256
    bitsLeft = bitsLeft - 1
    return b
  end
  local function bits(n)
    local v = 0
    for _ = 1, n do
      local b = bit()
      if b == nil then return nil end
      v = v * 2 + b
    end
    return v
  end

  for _ = 1, GEN2_TEXT_MAX_BYTES or 4096 do
    local node = 0
    local value
    for _ = 1, 24 do              -- a code longer than the tree is deep is noise
      local b = bit()
      if b == nil then return out, pc end
      value = t.tree[node * 2 + b + 1]
      if value == nil then return out, pc end
      if value >= RomExtractorGen2.PRISM_HUFFMAN_LEAF then break end
      node = value
    end
    if value == nil or value < RomExtractorGen2.PRISM_HUFFMAN_LEAF then
      return out, pc
    end
    local char
    if value >= 0xBC and value < 0xD0 then
      char = value - 0x78
    elseif value >= 0x78 and value < 0x7C then
      char = value - 0x20
    elseif value == 0x7C then
      local n = bits(6)
      if n == nil then return out, pc end
      -- (count, initial + count) pairs: subtract each count until it borrows,
      -- then add that pair's base back
      local list = t.special64 or {}
      for i = 1, #list - 1, 2 do
        local count, base = list[i], list[i + 1]
        if n < count then char = (n + base) % 256; break end
        n = n - count
      end
      char = char or 0x50
    elseif value == 0x7D then
      local n = bits(4)
      if n == nil then return out, pc end
      char = (t.special16 or {})[n + 1] or 0x50
    else
      char = value
    end
    out[#out + 1] = char
    -- PrintCompressedString stops on "@", and PlaceString stops the box on a
    -- finish character (<DONE> / <PROMPT> / <SDONE>).  Without those three the
    -- walk ran on into the next string and only stopped on the step cap.
    if RomExtractorGen2.GEN2_TEXT_ENDS[char] then return out, pc end
  end
  return out, pc
end

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

-- The same read against a bare (bank, address) rather than a symbol, for
-- blobs the ROM only reaches through a far pointer -- a map's block table
-- above all.  `expected`, when given, is the ONLY thing that decides whether
-- the answer is kept: an LZ3 decoder handed raw data does not fail, it
-- returns plausible-looking rubbish, so "it decompressed" proves nothing and
-- "it decompressed to exactly the size the header says" proves everything.
-- That makes this safe to attempt on a cartridge that stores the blob raw --
-- Gold and Crystal do -- because the length check simply will not match.
function RomExtractorGen2:gen2LzAt(bank, address, expected)
  if not self.rom then return nil end
  local ok, raw = pcall(function()
    return self.rom:bytes(bank, address, 0x8000 - address)
  end)
  if not ok or type(raw) ~= "table" then return nil end
  local okOut, out = pcall(decompressLz3, raw)
  if not okOut or type(out) ~= "table" or #out == 0 then return nil end
  if expected and #out ~= expected then return nil end
  return out
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

-- A single TWO-colour palette entry (the trainer / player format): the ROM
-- stores only the middle pair and LoadPalette_White_Col1_Col2_Black supplies
-- the white and the black around them.  KrisPalette is literally
-- TrainerPalettes + 4, so reading it as a four-colour CGB palette (which is
-- what gen2Palettes does) walks into the NEXT trainer's colours and hands
-- back {skin, blue, orange, dark orange} -- shade 3, the outline, comes out
-- orange and the pic speckles.
--
-- Returned ZERO-based, because that is what ImageWriter.recolorShades keys
-- on (`colors[shade]`, shade 0..3).  gen2Palettes' one-based table silently
-- shifts every shade by one through that lookup.
function RomExtractorGen2:gen2TwoColorPalette(symbolName)
  local sym = self:symbol(symbolName)
  if not (sym and self.rom) then return nil end
  local ok, raw = pcall(function()
    return self.rom:bytes(sym.bank, sym.address, 4)
  end)
  if not ok or type(raw) ~= "table" then return nil end
  local pal = { [0] = { 1, 1, 1 }, [3] = { 0, 0, 0 } }
  for color = 0, 1 do
    local value = (raw[color * 2 + 1] or 0) + (raw[color * 2 + 2] or 0) * 256
    pal[color + 1] = {
      (value % 32) / 31,
      (math.floor(value / 32) % 32) / 31,
      (math.floor(value / 1024) % 32) / 31,
    }
  end
  return pal
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

-- Crystal's title screen (engine/movie/title.asm _TitleScreen, 43:$6D67),
-- read straight off the cartridge.  Nothing about it is shaped like Gold's:
-- there is no TitleScreenTilemap to copy -- the map is DRAWN by
-- DrawTitleGraphic as runs of consecutive tile ids -- and Suicune is BG tiles
-- out of VRAM BANK 1, not an OBJ.
--
--   TitleLogoGFX     -> $8800.  LCDC bit 4 is clear, so BG tile ids are
--                       SIGNED: $80+n is blob[n] and $00+n is blob[128+n].
--                       One 156-tile blob therefore serves both id ranges --
--                       the logo AND the copyright line live in it.
--   TitleSuicuneGFX  -> $8800 in VRAM bank 1, 256 tiles, same signed rule.
--   TitleCrystalGFX  -> $8000, which only OBJ can reach: it is the sparkle,
--                       not part of the background.
--
--   logo     DrawTitleGraphic at (0,3), b=7 rows, c=20 cols, d=$80, e=$14
--            -> tile $80 + row*20 + col, wrapping through $FF back into $00
--   Suicune  LoadSuicuneFrame: 6 rows x 8 cols at (6,12), tile
--            base + row*16 + col.  SuicuneFrameIterator holds the four bases
--            and steps one every 8 frames.
--
-- The attrmap ByteFills are what give the logo its vertical gradient: rows
-- 3-4 palette 2, row 5 palette 3, row 6 palette 4, row 7 palette 5, rows 8-9
-- palette 6, and row 9 columns 5-15 palette 1 for the CRYSTAL VERSION ribbon.
-- Rows 12-17 are filled with attribute $08 -- bank 1, palette 0 -- which is
-- what puts Suicune on screen at all.
local GEN2_CRYSTAL_TITLE = {
  logoRow = 3, logoRows = 7, logoCols = 20, logoTile = 0x80, logoStride = 0x14,
  rowPal = { [3] = 2, [4] = 2, [5] = 3, [6] = 4, [7] = 5, [8] = 6, [9] = 6 },
  ribbonRow = 9, ribbonCol = 5, ribbonCols = 11, ribbonPal = 1,
  suicuneCol = 6, suicuneRow = 12, suicuneCols = 8, suicuneRows = 6,
  suicuneStride = 16, suicuneBases = { 0x80, 0x88, 0x00, 0x08 },
  suicunePal = 0, framesPerStep = 8,
}

-- Full four-colour CGB palettes (TitleScreenPalettes and friends), as the
-- 0..1 floats gen2DrawTile wants.  gen2Palettes above is a different format
-- -- the two-colour trainer/mon tables, where shades 0 and 3 are implied.
function RomExtractorGen2:gen2CgbPalettes(symbolName, count)
  local sym = self:symbol(symbolName)
  if not (sym and self.rom) then return nil end
  local raw = GEN2_PAL.read(self.rom, sym.bank, sym.address, count)
  if not raw then return nil end
  local out = {}
  for index, pal in ipairs(raw) do
    local converted = {}
    for slot, color in ipairs(pal) do
      converted[slot] = { color[1] / 255, color[2] / 255, color[3] / 255 }
    end
    out[index] = converted
  end
  return out
end

function RomExtractorGen2:extractCrystalTitleArt()
  local logo = self:gen2Lz("TitleLogoGFX")
  local suicune = self:gen2Lz("TitleSuicuneGFX")
  local pals = self:gen2CgbPalettes("TitleScreenPalettes", 8)
  if not (logo and suicune and pals) then return nil end

  local T = GEN2_CRYSTAL_TITLE
  local logoTiles = gen2SplitTiles(logo)
  local suicuneTiles = gen2SplitTiles(suicune)
  -- signed tile id -> index into a blob decompressed contiguously from $8800
  local function pick(tiles, id)
    return tiles[id >= 0x80 and (id - 0x80) or (id + 0x80)]
  end

  -- Background: the logo band over the black the cleared tilemap leaves.
  local image = ImageWriter.blank(160, 144, 0, 0, 0, 1)
  local id = T.logoTile
  for row = 0, T.logoRows - 1 do
    local rowStart = id
    local screenRow = T.logoRow + row
    for col = 0, T.logoCols - 1 do
      local pal = pals[(T.rowPal[screenRow] or 0) + 1]
      if screenRow == T.ribbonRow and col >= T.ribbonCol
          and col < T.ribbonCol + T.ribbonCols then
        pal = pals[T.ribbonPal + 1] or pal
      end
      gen2DrawTile(image, pick(logoTiles, id), col * 8, screenRow * 8, pal)
      id = (id + 1) % 256
    end
    id = (rowStart + T.logoStride) % 256
  end
  self:saveImage(image, "title/crystal_title.png")

  -- Suicune: four frames, drawn over the background rather than baked into
  -- it, so colour 0 has to stay clear the way an OBJ's would.
  local frames = {}
  local pal = pals[T.suicunePal + 1]
  for index, base in ipairs(T.suicuneBases) do
    local frame = ImageWriter.blank(T.suicuneCols * 8, T.suicuneRows * 8,
                                    0, 0, 0, 0)
    for row = 0, T.suicuneRows - 1 do
      for col = 0, T.suicuneCols - 1 do
        local tile = pick(suicuneTiles,
                          (base + row * T.suicuneStride + col) % 256)
        if tile then
          for y = 0, 7 do
            for x = 0, 7 do
              local shade = tile[y * 8 + x + 1]
              if shade ~= 0 then
                local color = pal[shade + 1]
                frame:setPixel(col * 8 + x, row * 8 + y,
                               color[1], color[2], color[3], 1)
              end
            end
          end
        end
      end
    end
    local file = "title/crystal_suicune_" .. index .. ".png"
    self:saveImage(frame, file)
    frames[index] = "assets/generated/" .. file
  end

  local sequence = {}
  for index = 1, #frames do sequence[index] = { index, T.framesPerStep } end

  return {
    layout = "gen2",
    background = {
      path = "assets/generated/title/crystal_title.png",
      width = 160, height = 144,
    },
    -- no clouds: Crystal's screen is static apart from Suicune
    mascot = {
      frames = frames, sequence = sequence,
      x = T.suicuneCol * 8, y = T.suicuneRow * 8,
    },
    music = "Music_TitleScreen",
  }
end

-- PRISM'S TITLE SCREEN (engine/title.asm _TitleScreen).  It answers the same
-- two questions Crystal's does -- it has TitleLogoGFX and no
-- TitleScreenTilemap -- so it was falling into the Crystal reader, which then
-- looked for TitleSuicuneGFX, found nothing, and returned nil.  Prism has no
-- title art at all as a result.
--
-- What it actually draws, read off the routine:
--
--   TitleLogoGFX      -> vFontTiles ($8800, VRAM bank 0).  LCDC bit 4 is
--                        clear so BG ids are SIGNED, the same rule Crystal
--                        uses: $80+n is blob[n] and $00+n is blob[128+n].
--                        gfx/title/logo.xbpp is 194 tiles -- `.xbpp` is
--                        Prism's name for a 2bpp sheet its .cfg trims six
--                        tiles off the end of, not a different depth.
--   TitleTyranitarGFX -> vWalkingFrameTiles ($8800, VRAM BANK 1), 119 tiles,
--                        which is exactly the 17x7 of gfx/title/tyranitar.png.
--
--   logo      DrawTitleGraphic at (0,3), b=9 rows, c=20 cols, d=$80, e=$14
--   "Pokemon" at (0,12),  b=7, c=9,  d=$80, e=$11 -> tyranitar cols 0-8
--   "Trainers" at (11,12), b=7, c=8, d=$89, e=$11 -> tyranitar cols 9-16
--   3D prism  at (7,12), five tiles of 0 -- the rotating prism is drawn per
--             frame from cleared VRAM, so it is a GAP in the static art, and
--             the two halves above are one picture split around it.
--
-- The attrmap ByteFills give the logo its gradient (rows 3-4 palette 2, row 5
-- palette 3, row 6 palette 4, row 7 palette 5, rows 8-11 palette 6) with the
-- PRISM VERSION ribbon at row 9 column 5 for NAME_LENGTH (11) on palette 1.
-- The band below is attribute 8 and 15 -- bank 1, palettes 0 and 7 -- so the
-- two halves of the one Tyranitar drawing are deliberately coloured apart.
function RomExtractorGen2:extractPrismTitleArt()
  local logo = self:gen2Lz("TitleLogoGFX")
  local mon = self:gen2Lz("TitleTyranitarGFX")
  local pals = self:gen2CgbPalettes("TitleScreenPalettes", 8)
  if not (logo and mon and pals) then return nil end

  local logoTiles = gen2SplitTiles(logo)
  local monTiles = gen2SplitTiles(mon)
  -- signed BG id -> index into a blob decompressed contiguously from $8800
  local function pick(tiles, id)
    return tiles[id >= 0x80 and (id - 0x80) or (id + 0x80)]
  end

  local rowPal = { [3] = 2, [4] = 2, [5] = 3, [6] = 4, [7] = 5,
                   [8] = 6, [9] = 6, [10] = 6, [11] = 6 }
  -- THE BACKDROP IS NOT BLACK.  _TitleScreen clears the whole tilemap to the
  -- space character on attribute 0, so every cell no DrawTitleGraphic call
  -- claims shows a blank tile in palette 0 -- and palette 0's colour 0 is
  -- WHITE.  Starting the canvas at black left the two columns between
  -- Tyranitar and the trainers, the column past them, and the rows above the
  -- logo as black holes that are not on the real screen.
  local blank = pals[1][1]
  -- SHADE 0 IS A HOLE, because that is the hardware rule the prism depends
  -- on.  Its 29 OAM entries all carry attribute $80/$81 -- bit 7 set, "behind
  -- BG" -- and an OBJ with that bit shows only where the BG pixel is colour 0
  -- of its palette.  So the gem is seen through the sky, through the white
  -- surround, and through the gaps in the band, but never through the logo's
  -- letters.  Punching shade 0 to alpha 0 here lets the renderer reproduce
  -- that exactly: backdrop, then prism, then this image over the top.
  -- TWO copies, because a colour-0 BG pixel is not "transparent" -- the
  -- hardware still draws it, it is just the one an OBJ behind the BG is
  -- allowed to replace.  So the renderer needs the screen twice: the plain
  -- one underneath, and the same screen with its colour-0 pixels punched out
  -- laid back over the gem.  Anywhere the gem is not, the plain copy shows
  -- through the hole and the sky keeps its gradient.
  local image = ImageWriter.blank(160, 144, blank[1], blank[2], blank[3], 1)
  local over = ImageWriter.blank(160, 144, blank[1], blank[2], blank[3], 0)
  local function drawTile(tile, px, py, pal)
    if not tile then return end
    for y = 0, 7 do
      for x = 0, 7 do
        local shade = tile[y * 8 + x + 1]
        local color = pal[shade + 1]
        image:setPixel(px + x, py + y, color[1], color[2], color[3], 1)
        over:setPixel(px + x, py + y, color[1], color[2], color[3],
                      shade == 0 and 0 or 1)
      end
    end
  end

  -- THE SCREEN IS SCROLLED.  _TitleScreen ends with `ld a, 16 / ldh [hSCY]`,
  -- so the viewport starts two tile rows down the BG map: BG row 2 is screen
  -- row 0.  Every coordinate in the routine is a BG-map row and has to lose
  -- those two rows to land on the 144px screen -- the logo at BG rows 3-11 is
  -- screen rows 1-9, and the Tyranitar band at BG rows 12-18 is screen rows
  -- 10-16.  Ignoring it ran the band off the bottom of the image: LOVE
  -- refuses an out-of-range setPixel, the whole rip threw, and the launcher
  -- fell back to the shipped logo.
  local SCY = 2
  local id = 0x80
  for row = 0, 8 do
    local rowStart = id
    local bgRow = 3 + row
    for col = 0, 19 do
      local pal = pals[(rowPal[bgRow] or 0) + 1]
      -- the PRISM VERSION ribbon, BG row 9 columns 5..15
      if bgRow == 9 and col >= 5 and col < 5 + 11 then
        pal = pals[2] or pal
      end
      drawTile(pick(logoTiles, id), col * 8, (bgRow - SCY) * 8, pal)
      id = (id + 1) % 256
    end
    id = (rowStart + 0x14) % 256
  end

  -- The Tyranitar band.  Both halves come out of one 17-wide sheet; the five
  -- columns between them are the prism's, and stay black.
  local function band(startCol, cols, base, palIndex)
    local pal = pals[palIndex + 1]
    local tile = base
    for row = 0, 6 do
      local rowStart = tile
      for col = 0, cols - 1 do
        drawTile(pick(monTiles, tile),
                 (startCol + col) * 8, (12 + row - SCY) * 8, pal)
        tile = (tile + 1) % 256
      end
      tile = (rowStart + 0x11) % 256
    end
  end
  band(0, 9, 0x80, 0)     -- "Pokemon" half, attribute 8  -> bank 1 palette 0
  band(11, 8, 0x89, 7)    -- "Trainers" half, attribute 15 -> bank 1 palette 7
  -- ...and the cover, drawn AFTER both in the routine, blanks five tiles --
  -- `hlbgcoord 7, 12 / ld bc, 5`, so ONE ROW of five, not five columns of
  -- seven.  The prism is animated over the rest of that block at run time
  -- from VRAM the routine cleared; only this row is reserved in the map.
  -- ...on attribute 9 -- bank 1, palette 1 -- over a tile the routine zeroed,
  -- so the reserved strip is palette 1's colour 0, not black either.
  local cover = pals[2][1]
  for col = 7, 11 do
    for y = 0, 7 do
      for xx = 0, 7 do
        image:setPixel(col * 8 + xx, (12 - SCY) * 8 + y,
                       cover[1], cover[2], cover[3], 1)
        over:setPixel(col * 8 + xx, (12 - SCY) * 8 + y,
                      cover[1], cover[2], cover[3], 0)
      end
    end
  end

  -- The copyright line, drawn into the WINDOW map rather than the BG:
  -- `hlbgcoord 3, 0, vWindowMap / lb bc, 1, 14 / ld d, $34`, with the window
  -- parked at hWY $88 -- screen row 17.  $34 is signed, so it is blob[180],
  -- and fourteen tiles from there is exactly the tail of the 194-tile logo
  -- sheet: the copyright shares the logo's blob, the way Crystal's does.
  for col = 0, 13 do
    drawTile(pick(logoTiles, (0x34 + col) % 256),
             (3 + col) * 8, 17 * 8, pals[1])
  end

  self:saveImage(image, "title/prism_title.png")
  self:saveImage(over, "title/prism_title_over.png")

  -- THE ROTATING PRISM IS NOT ART, so there is nothing here to rip.  Prism
  -- rasterises it in software every frame -- Update3DPrism / Draw3DPrism /
  -- Get3DPrismShade write OBJ tiles, Toggle3DPrismPage double-buffers them
  -- across two VRAM pages, and InitializeBackground places the 29 OAM entries
  -- that show them.  The cartridge stores no frames of it: _TitleScreen
  -- explicitly zeroes 70 tiles of BOTH object planes at startup.
  --
  -- What CAN be carried across is where it lives and what it is coloured
  -- with, so the renderer can draw the same solid in the same place out of
  -- the same palette.  The block is the five tiles the cover reserves on row
  -- 12 (`hlbgcoord 7, 12 / ld bc, 5`) by the seven rows the band spans, and
  -- the OAM attributes InitializeBackground writes are palettes 1, 2 and 3 --
  -- one per visible face, which is what makes the rotation read as a solid.
  -- WHERE IT SITS AND WHAT SHAPE IT IS, both read off InitializeBackground
  -- rather than guessed.  It writes 29 OAM entries as SEVEN columns of 8x16
  -- sprites -- x steps 8 at a time from $3c, and each column stacks
  -- 3, 4, 5, 5, 5, 4, 3 of them from y -$c, -$1c, -$2c, -$2c, -$2c, -$1c,
  -- -$c.  Every column therefore ENDS at the same y, so the silhouette is
  -- flat-bottomed with a stepped top rising to the middle: a cut gem, which
  -- is what AnimateTitleCrystal calls it.
  --
  -- That routine then slides all 29 down 2px a frame until the first entry
  -- reaches $2c, which is +56 from where it starts.  Screen coordinates are
  -- OAM minus (8, 16), so the gem comes to rest spanning x 52..108 and
  -- y -4..76 -- ACROSS the logo, not under the band.  Behind it, per the
  -- priority bit, which is why the letters stay in front of it.
  local columns = { 3, 4, 5, 5, 5, 4, 3 }
  -- and the colours it refracts through: TitleScreenSpectrumPalettes is a
  -- 57-entry ramp the routine feeds to the palette registers a line at a
  -- time (FillEveryByteWithDEOffset over wTitleScreenBGPIList...), which is
  -- what makes a grey solid read as a prism splitting light.
  local spectrum = {}
  local ssym = self:symbol("TitleScreenSpectrumPalettes")
  if ssym and self.rom then
    pcall(function()
      for index = 0, 56 do
        local word = self.rom:word(ssym.bank, ssym.address + index * 2)
        spectrum[index + 1] = {
          (word % 32) / 31,
          (math.floor(word / 32) % 32) / 31,
          (math.floor(word / 1024) % 32) / 31,
        }
      end
    end)
  end
  if not spectrum[1] then spectrum = nil end
  return {
    layout = "gen2",
    background = {
      path = "assets/generated/title/prism_title.png",
      width = 160, height = 144,
    },
    -- the same screen with its colour-0 pixels punched out; drawn back over
    -- the gem so only the pixels the hardware would let it replace show it
    overlay = {
      path = "assets/generated/title/prism_title_over.png",
      width = 160, height = 144,
    },
    -- no mascot frames: Tyranitar is static BG art and is already in the
    -- background above (TyranitarFrameIterator, despite its name, drives the
    -- clouds and the prism -- not the mon)
    prism = {
      x = 52, bottom = 76, cellWidth = 8, cellHeight = 16,
      columns = columns, spectrum = spectrum,
      backdrop = { blank[1], blank[2], blank[3] },
      framesPerTurn = 96,
    },
    music = "Music_TitleScreen",
  }
end

function RomExtractorGen2:extractGen2TitleArt()
  -- Crystal ships none of Gold's title data, so tell them apart by the
  -- tilemap Gold has and Crystal builds in code.
  -- Prism answers the Crystal test too (TitleLogoGFX, no tilemap), so it has
  -- to be asked FIRST -- by the one symbol only it has.
  if self:symbol("TitleTyranitarGFX") then
    return self:extractPrismTitleArt()
  end
  if self:symbol("TitleLogoGFX") and not self:symbol("TitleScreenTilemap") then
    return self:extractCrystalTitleArt()
  end
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
  if obPals then
    local okTrail, trail = pcall(self.gen2TitleTrail, self, obPals)
    if okTrail and trail then title.trail = trail end
  end
  return title
end

-- ---------------------------------------------------------------------------
-- The sparkle trail (SPRITE_ANIM_OBJ_GS_TITLE_TRAIL)
--
-- The stream of sparkles that pours off Ho-Oh / Lugia.  None of it was
-- ripped, so the bird flew over an empty sky.  Read straight off Gold:
--
--   TitleScreen+$67   ld hl, TitleScreenGFX3 / ld de, $8F80 / ld bc, $0080
--                     -- FOUR TILES, COPIED RAW.  Not LZ like GFX1/2/4, which
--                     is why decompressing it gave 1522 bytes of nonsense.
--                     $8F80 is tile $F8, which is exactly where the OAM sets
--                     below point.
--   OAMData_GSTitleTrail  `db 1 / dbsprite -1, -1, 4, 4, $00, 1 | OAM_PAL1`
--                     -- one 8x16 object at (-4, -4), OB palette 1.
--   oam.asm           spriteanimoam $f8 -> _1, $fa -> _2: the set's TILE
--                     OFFSET, so the two frames are tiles $F8/$F9 and $FA/$FB.
--   Frameset_GSTitleTrail   oamframe _1, 1 / oamframe _2, 1 / oamrestart --
--                     the sparkle twinkles every single frame.
--   RunTitleScreen    calls UpdateTitleTrailSprite once a frame.
--   UpdateTitleTrailSprite (01:$64B1)
--                     `and $3 / ret nz` -- a new sparkle every FOURTH frame --
--                     then indexes a six-record table of TWO (x, y) spawn
--                     points each, picking one by bit 2 of the same counter.
--                     A (0, 0) pair means "no sparkle this tick".
--   SpriteAnimFunc_GSTitleTrail (23:$582D)
--                     x += 4 and y += 1 every frame, plus a 2-pixel sine
--                     wobble on a phase that advances 3 a frame, and the
--                     sparkle deletes itself once x reaches $A4.
--
-- The record INDEX is read from [$C5B6] -- ten bytes past the block
-- TitleScreen copies to $C5AC, so nothing on the title screen ever writes it.
-- Rather than reproduce a read of uninitialised WRAM, the port walks the six
-- records in order, one per spawn tick; every spawn height in the table gets
-- used, which is what the screen looks like when the byte is not zero.
-- ---------------------------------------------------------------------------
function RomExtractorGen2:gen2TitleTrail(obPals)
  local gfx = self:symbol("TitleScreenGFX3")
  local spawn = self:symbol("UpdateTitleTrailSprite")
  local sets = self:symbol("SpriteAnimOAMData")
  local frameset = self:symbol("SpriteAnimFrameData.Frameset_GSTitleTrail")
  if not (gfx and sets and frameset and self.rom) then return nil end

  -- The copy length is bc = $80 on Gold; Silver ships fewer bytes and puts
  -- TitleScreenGFX4 right behind it, so measure rather than assume.
  local following = self:symbol("TitleScreenGFX4")
  local bytes = 4 * 16
  if following and following.bank == gfx.bank and following.address > gfx.address then
    bytes = math.max(bytes, math.min(0x80, following.address - gfx.address))
  end
  local raw = self.rom:bytes(gfx.bank, gfx.address, bytes)
  if type(raw) ~= "table" then return nil end
  local tiles = gen2SplitTiles(raw)

  -- THE FRAMESET SAYS HOW MANY FRAMES THERE ARE, and the two cartridges do
  -- not agree.  `oamframe <set>, <duration>` pairs, closed by $FE (restart)
  -- or $FF (end).  GOLD'S IS TWO FRAMES OF ONE TICK that swap the sparkle's
  -- two halves -- the twinkle -- AND SILVER'S IS ONE FRAME HELD FOR $20.
  -- Hardcoding Gold's pair gave Silver a flicker it does not have.
  local frames = {}
  do
    local ok = pcall(function()
      for index = 0, 15 do
        local set = self.rom:byte(frameset.bank, frameset.address + index * 2)
        if set == 0xFF or set == 0xFE or set == 0xFD then break end
        local duration = self.rom:byte(frameset.bank,
                                       frameset.address + index * 2 + 1)
        frames[#frames + 1] = { set = set, duration = math.max(1, duration or 1) }
      end
    end)
    if not ok then return nil end
  end
  if not frames[1] then return nil end

  -- SpriteAnimOAMData is `db <tile offset>, dw <block>` per OAM SET, and a
  -- block is `db <count>` then `db dy, dx, tile, attr` rows.  Both of the
  -- trail's sets point at the SAME block and differ only in the offset ($F8
  -- and $FA), which is how one drawing twinkles -- and SILVER'S BLOCK HOLDS
  -- TWO SPRITES, not one, so reading only the first row lost half of it.
  local blocks = {}
  local function blockFor(set)
    if blocks[set] ~= nil then return blocks[set] end
    blocks[set] = false
    local row = sets.address + set * 3
    local okRow, offset, pointer = pcall(function()
      return self.rom:byte(sets.bank, row), self.rom:word(sets.bank, row + 1)
    end)
    if not (okRow and pointer and pointer >= 0x4000 and pointer < 0x8000) then
      return false
    end
    local count = self.rom:byte(sets.bank, pointer)
    if not count or count < 1 or count > 16 then return false end
    local rows = {}
    for index = 0, count - 1 do
      local at = pointer + 1 + index * 4
      local dy = self.rom:byte(sets.bank, at)
      local dx = self.rom:byte(sets.bank, at + 1)
      if dy > 127 then dy = dy - 256 end
      if dx > 127 then dx = dx - 256 end
      rows[#rows + 1] = { dy = dy, dx = dx,
        tile = self.rom:byte(sets.bank, at + 2),
        attr = self.rom:byte(sets.bank, at + 3) }
    end
    blocks[set] = { offset = offset, rows = rows }
    return blocks[set]
  end

  -- one canvas big enough for every sprite of every frame, so the frames stay
  -- registered against each other
  local minX, minY, maxX, maxY
  for _, frame in ipairs(frames) do
    local block = blockFor(frame.set)
    for _, row in ipairs(block and block.rows or {}) do
      minX = math.min(minX or row.dx, row.dx)
      minY = math.min(minY or row.dy, row.dy)
      maxX = math.max(maxX or (row.dx + 8), row.dx + 8)
      maxY = math.max(maxY or (row.dy + 16), row.dy + 16)
    end
  end
  if not minX then return nil end
  local width, height = maxX - minX, maxY - minY

  local paths = {}
  for index, frame in ipairs(frames) do
    local block = blockFor(frame.set)
    local image = ImageWriter.blank(width, height, 0, 0, 0, 0)
    for _, row in ipairs(block and block.rows or {}) do
      local pal = obPals[(row.attr % 8) + 1] or obPals[1]
      -- 8x16 objects: the pair is (t & $FE, t | $01), and TitleScreenGFX3 is
      -- copied to VRAM tile $F8, so tile $F8 is tiles[0]
      local base = (row.tile + block.offset) % 256
      local top = base - base % 2 - 0xF8
      for half = 0, 1 do
        local pixels = tiles[top + half]
        if pixels then
          for y = 0, 7 do
            for x = 0, 7 do
              local shade = pixels[y * 8 + x + 1]
              if shade ~= 0 then
                local color = pal[shade + 1]
                image:setPixel(row.dx - minX + x, row.dy - minY + half * 8 + y,
                               color[1], color[2], color[3], 1)
              end
            end
          end
        end
      end
    end
    local file = "title/gen2_trail_" .. index .. ".png"
    self:saveImage(image, file)
    paths[index] = "assets/generated/" .. file
  end

  -- WHERE THE SPARKLES COME FROM, and the two cartridges do not agree here
  -- either.
  --
  -- Gold walks a table: `ld bc, $C5AC / ... / ld de, <table> / add hl, de`,
  -- six records of two (x, y) OAM points each, one picked by bit 2 of the
  -- frame counter and (0, 0) meaning "none this tick".
  --
  -- SILVER HAS NO TABLE AT ALL.  Its whole routine is
  --
  --     ld a, [$CE65] / and $03 / ret nz
  --     ld de, $7C58                 ; d = y = $7C, e = x = $58
  --     ld a, $0F / call InitSpriteAnimStruct / ret
  --
  -- -- every sparkle from one fixed point.  Read Gold's way, that immediate
  -- was taken for a table address and the six records came back all zero, so
  -- Silver's trail spawned nothing at all.  The two are told apart by what
  -- FOLLOWS the `ld de`: an immediately-following `ld a, n / call` is the
  -- spawn itself, not a pointer to a list.
  local spawns
  if spawn then
    local ok, rows = pcall(function()
      local at, direct
      for offset = 0, 0x40 do
        if self.rom:byte(spawn.bank, spawn.address + offset) == 0x11 then
          at = self.rom:word(spawn.bank, spawn.address + offset + 1)
          direct = self.rom:byte(spawn.bank, spawn.address + offset + 3) == 0x3E
            and self.rom:byte(spawn.bank, spawn.address + offset + 5) == 0xCD
          break
        end
      end
      if not at then return nil end
      -- OAM -> screen, plus the composition's own top-left offset
      local function point(x, y)
        if x == 0 and y == 0 then return false end
        return { x = x - 8 + minX, y = y - 16 + minY }
      end
      if direct then
        local one = point(at % 256, math.floor(at / 256))
        return one and { { one, one } } or nil
      end
      if at < 0x4000 or at >= 0x8000 then return nil end
      -- EACH RECORD IS `dbpixel y, x`, SO THE Y BYTE COMES FIRST.  Feeding
      -- them to point() in table order put Gold's sparkles in a vertical
      -- column at one x instead of along the bird at one height: the real
      -- table is y = $5C throughout with x running $50..$88.
      local out = {}
      for record = 0, 5 do
        local pair = {}
        for half = 0, 1 do
          local y = self.rom:byte(spawn.bank, at + record * 4 + half * 2)
          local x = self.rom:byte(spawn.bank, at + record * 4 + half * 2 + 1)
          pair[half + 1] = point(x, y)
        end
        out[record + 1] = pair
      end
      return out
    end)
    if ok then spawns = rows end
  end
  if not spawns then return nil end

  local sequence = {}
  for index, frame in ipairs(frames) do
    sequence[index] = { index, frame.duration }
  end

  return {
    frames = paths,
    sequence = sequence,   -- { frame, ticks } pairs, looping
    width = width, height = height,
    spawns = spawns,
    everyFrames = 4,      -- `and $3 / ret nz`
    dx = 4, dy = 1,       -- x += 4, y += 1 a frame
    sineAmplitude = 2,    -- `ld d, 2` into AnimSeqs_Sine
    sineStep = 3,         -- VAR1 += 3 a frame
    deleteX = 0xA4 - 8,   -- `cp $a4` on the OAM x
  }
end

-- Mascot geometry: OAM y/x are screen + 16 / + 8, and the anim object sits
-- at depixel 12, 11 = (96, 88), so the object's origin is screen (80, 80).
--
-- NOTHING ABOUT THIS IS SHARED BETWEEN THE TWO CARTRIDGES, which is why the
-- old symbol-name version drew Ho-Oh and silently produced nothing at all for
-- Silver.  Read it the way the hardware does instead, off two tables:
--
--   SpriteAnimFrameData.Frameset_GSIntroHoOhLugia
--                    `oamframe <oam set>, <duration>` pairs closed by $FE.
--                    GOLD is six frames of sets 1,2,3,4,3,5; SILVER IS NINE
--                    frames of sets 2,1,2,3,3,4,4,3,2 -- a different length,
--                    a different order and different durations.
--   SpriteAnimOAMData  `db <tile offset>, dw <block>` per OAM SET.  Gold's
--                    five sets point at five distinct Ho-Oh blocks with a
--                    $00 offset each.  SILVER'S FIVE SETS POINT AT ONLY TWO
--                    LUGIA BLOCKS AND CARRY OFFSETS $00/$20/$40/$60 -- the
--                    wing flap IS the tile offset, so resolving the blocks
--                    by name gave four identical frames even when it worked.
--                    (OAMData_GSIntroLugia3..5 exist in the ROM and are
--                    unreferenced; reading 1..5 by name read dead data.)
--
-- The canvas is sized from the union of every sprite of every frame rather
-- than hardcoded: HO-OH SPANS dx -32..+31 AND LUGIA SPANS dx -40..+39, so
-- the old fixed 64x64 canvas with its origin at (32, 24) sent Lugia's left
-- wing to x = -8, ImageWriter refused the pixel, and the pcall around this
-- function turned the error into "Silver has no mascot".
function RomExtractorGen2:gen2TitleMascot(mon, obPals)
  local sets = self:symbol("SpriteAnimOAMData")
  local frameset = self:symbol("SpriteAnimFrameData.Frameset_GSIntroHoOhLugia")
  if not (sets and frameset and self.rom and mon) then return nil end
  local tiles = gen2SplitTiles(mon)

  local frames = {}
  do
    local ok = pcall(function()
      for index = 0, 31 do
        local set = self.rom:byte(frameset.bank, frameset.address + index * 2)
        if set == nil or set == 0xFF or set == 0xFE or set == 0xFD then break end
        local duration = self.rom:byte(frameset.bank,
                                       frameset.address + index * 2 + 1)
        frames[#frames + 1] = { set = set, duration = math.max(1, duration or 1) }
      end
    end)
    if not ok then return nil end
  end
  if not frames[1] then return nil end

  local blocks = {}
  local function blockFor(set)
    if blocks[set] ~= nil then return blocks[set] end
    blocks[set] = false
    local row = sets.address + set * 3
    local okRow, offset, pointer = pcall(function()
      return self.rom:byte(sets.bank, row), self.rom:word(sets.bank, row + 1)
    end)
    if not (okRow and pointer and pointer >= 0x4000 and pointer < 0x8000) then
      return false
    end
    local count = self.rom:byte(sets.bank, pointer)
    if not count or count < 1 or count > 40 then return false end
    local rows = {}
    for index = 0, count - 1 do
      local at = pointer + 1 + index * 4
      local dy = self.rom:byte(sets.bank, at)
      local dx = self.rom:byte(sets.bank, at + 1)
      if dy == nil or dx == nil then return false end
      if dy > 127 then dy = dy - 256 end
      if dx > 127 then dx = dx - 256 end
      rows[#rows + 1] = { dy = dy, dx = dx,
        tile = self.rom:byte(sets.bank, at + 2) or 0,
        attr = self.rom:byte(sets.bank, at + 3) or 0 }
    end
    blocks[set] = { offset = offset or 0, rows = rows }
    return blocks[set]
  end

  -- one canvas for every frame so they stay registered against each other
  local minX, minY, maxX, maxY
  for _, frame in ipairs(frames) do
    local block = blockFor(frame.set)
    for _, row in ipairs(block and block.rows or {}) do
      minX = math.min(minX or row.dx, row.dx)
      minY = math.min(minY or row.dy, row.dy)
      maxX = math.max(maxX or (row.dx + 8), row.dx + 8)
      maxY = math.max(maxY or (row.dy + 16), row.dy + 16)
    end
  end
  if not minX then return nil end
  local width, height = maxX - minX, maxY - minY
  if width < 1 or height < 1 or width > 256 or height > 256 then return nil end

  -- One PNG per DISTINCT oam set, in order of first use: Gold's six frames
  -- are five images and Silver's nine frames are four.
  local paths, imageOf = {}, {}
  local sequence = {}
  for index, frame in ipairs(frames) do
    local slot = imageOf[frame.set]
    if not slot then
      local block = blockFor(frame.set)
      if not block then return nil end
      local image = ImageWriter.blank(width, height, 0, 0, 0, 0)
      for _, row in ipairs(block.rows) do
        local pal = obPals[(row.attr % 8) + 1] or obPals[1]
        local xFlip = math.floor(row.attr / 0x20) % 2 == 1
        local yFlip = math.floor(row.attr / 0x40) % 2 == 1
        -- 8x16 mode ignores tile bit 0: the pair is (t & $FE, t | $01), and
        -- the set's tile offset is added first
        local base = (row.tile + block.offset) % 256
        base = base - base % 2
        for half = 0, 1 do
          local pixels = tiles[base + half]
          if pixels then
            for y = 0, 7 do
              for x = 0, 7 do
                local shade = pixels[y * 8 + x + 1]
                -- OBJ colour 0 is transparent on hardware
                if shade ~= 0 then
                  local sx = xFlip and (7 - x) or x
                  local sy = yFlip and (15 - (half * 8 + y)) or (half * 8 + y)
                  local color = pal[shade + 1]
                  if color then
                    image:setPixel(row.dx - minX + sx, row.dy - minY + sy,
                                   color[1], color[2], color[3], 1)
                  end
                end
              end
            end
          end
        end
      end
      slot = #paths + 1
      local file = "title/gen2_mascot_" .. slot .. ".png"
      self:saveImage(image, file)
      paths[slot] = "assets/generated/" .. file
      imageOf[frame.set] = slot
    end
    sequence[index] = { slot, frame.duration }
  end

  -- frame 1 stays the plain `mascot.path` so an older UI still finds art
  return {
    path = paths[1],
    frames = paths,
    width = width, height = height,
    x = GEN2_MASCOT.originX + minX,
    y = GEN2_MASCOT.originY + minY,
    sequence = sequence,
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

-- Crystal's attract movie (CrystalIntro, 39:$48AC).  Nothing is shared with
-- Gold's: IntroSceneJumper walks IntroScenes (39:$491E), 28 `dw` that
-- alternate SETUP scenes -- which load a screen and hand straight on -- with
-- HOLD scenes that animate for a frame budget.  The budget is the `cp $NN`
-- guarding NextIntroScene against the counter at $CF64; every number below was
-- read off the cartridge, not guessed.  docs/CRYSTAL-INTRO.md has the workings.
--
-- Each setup scene decompresses a tilemap, an attrmap, a palette and one or
-- two GFX blobs.  BG tile ids are signed, so the VRAM destination decides
-- which id range a blob answers for: $9000 covers $00-$7F and $8800 covers
-- $80-$FF.
--
-- `mode` is how the scene is drawn back:
--   still  the composed screen, held
--   pulse  the Unown scenes.  CrystalIntro_UnownFade blacks every BG palette
--          and relights ONE of them, running colours 1-3 up the BWFade /
--          BlackLBlueFade / BlackBlueFade ramps against a triangle counter --
--          which is the eyes opening in the dark.  Those screens are stored as
--          a white-on-black mask and tinted at draw time.
-- Hung off the module table rather than declared `local`: this chunk sits on
-- Lua's 200-locals ceiling and stops loading outright if it is crossed.
RomExtractorGen2.CRYSTAL_INTRO = {
  -- { key, tilemap, attrmap, palette, { {gfx, vramDest}, ... }, holdFrames,
  --   mode, scroll }
  --
  -- `scroll` is the hSCX motion the hold scene applies, straight out of its
  -- handler.  Screens are composed at the full 256px BG-map width so the
  -- window can actually travel.
  { "unown_a", "IntroUnownATilemap", "IntroUnownAAttrmap", "IntroUnownsPalette",
    { { "IntroUnownsGFX", 0x9000 } }, 128, "pulse" },
  { "forest", "IntroBackgroundTilemap", "IntroBackgroundAttrmap",
    "IntroBackgroundPalette", { { "IntroBackgroundGFX", 0x9000 } }, 128, "still" },
  { "unown_hi", "IntroUnownHITilemap", "IntroUnownHIAttrmap", "IntroUnownsPalette",
    { { "IntroUnownsGFX", 0x9000 } }, 128, "pulse" },
  -- IntroScene8: 64 frames of Intro_PerspectiveScrollBG, then Suicune runs in
  -- over 30 more ($C3C0 counts $F0 down by 8) -- 94, not the 64 the first `cp`
  -- suggests.  The perspective scroll is an LY-override warp and is not
  -- reproduced; the screen holds instead.
  { "forest", false, false, false, false, 94, "still", nil,
    -- IntroScene7 spawns Suicune at pixel (216, 108) and parks its x at $F0;
    -- IntroScene8 holds until frame $40 then walks x down by 8 a frame until
    -- it hits 0, which is the run across and also what ends the scene.
    { { name = "suicune", y = 108, x = 0xF0, hold = 0x40, step = -8 } } },
  -- IntroScene10 rustles the grass, then WOOPER pops out at frame $20 and
  -- PICHU at $40 (InitSpriteAnimStruct at pixel (48,176) and (128,169) --
  -- both below the screen, so they rise into view on the hop).
  { "forest", false, false, false, false, 192, "still", nil, {
      { name = "wooper", x = 48, y = 176, spawn = 0x20, hop = true },
      { name = "pichu", x = 128, y = 169, spawn = 0x40, hop = true },
    } },
  { "unowns", "IntroUnownsTilemap", "IntroUnownsAttrmap", "IntroUnownsPalette",
    { { "IntroUnownsGFX", 0x9000 } }, 192, "pulse" },
  -- IntroScene14 subtracts $0A from hSCX every frame for the whole hold:
  -- the forest tears past while Suicune runs through it.
  { "forest", false, false, false, false, 128, "still", { step = -10 },
    -- IntroScene14: nothing until $40, then x -= 2 a frame; at $60 the jump
    -- sound plays and x -= 8 instead, until it drops under $88 and
    -- DeinitializeAllSprites takes Suicune off screen.
    { { name = "suicune", y = 108, x = 0xF0, hold = 0x40, step = -2,
        step2At = 0x60, step2 = -8, hideBelow = 0x88 } } },
  { "suicune_jump", "IntroSuicuneJumpTilemap", "IntroSuicuneJumpAttrmap",
    "IntroSuicunePalette", { { "IntroSuicuneJumpGFX", 0x9000 } }, 128, "still" },
  -- IntroScene18 walks hSCX up by 8 a frame until it reaches $60, then holds
  -- there for the rest of the scene -- the camera settling on Suicune's face.
  { "suicune_close", "IntroSuicuneCloseTilemap", "IntroSuicuneCloseAttrmap",
    "IntroSuicuneClosePalette", { { "IntroSuicuneCloseGFX", 0x8800 } }, 96,
    "still", { from = 0, to = 0x60, step = 8 } },
  { "suicune_back", "IntroSuicuneBackTilemap", "IntroSuicuneBackAttrmap",
    "IntroSuicunePalette",
    { { "IntroSuicuneBackGFX", 0x9000 }, { "IntroUnownsGFX", 0x8800 } }, 152, "still" },
  { "suicune_back", false, false, false, false, 8, "still" },
  { "suicune_back", false, false, false, false, 32, "still" },
  { "crystal_unowns", "IntroCrystalUnownsTilemap", "IntroCrystalUnownsAttrmap",
    "IntroCrystalUnownsPalette", { { "IntroCrystalUnownsGFX", 0x9000 } }, 128, "pulse" },
  { "crystal_unowns", false, false, false, false, 24, "pulse" },
}
-- The ramps CrystalIntro_UnownFade walks, in the order it writes them into
-- colours 1, 2 and 3 of the one lit palette.
RomExtractorGen2.CRYSTAL_INTRO_RAMPS = {
  { "bw", "CrystalIntro_UnownFade.BWFade" },
  { "lblue", "CrystalIntro_UnownFade.BlackLBlueFade" },
  { "blue", "CrystalIntro_UnownFade.BlackBlueFade" },
}
RomExtractorGen2.CRYSTAL_RAMP_STEPS = 32

-- The intro's OBJ cast.  SpriteAnimOAMData is a 140-entry table of
-- `db tileOffset, dw oamData` -- the lead byte is a TILE OFFSET, not a bank,
-- which is what made Wooper come out as scrambled fragments when it was
-- ignored.  Each oamData is a count byte then `db dy, dx, tile, attr` rows
-- drawn as 8x16 objects; attr bit 3 picks the VRAM bank, so Suicune comes out
-- of IntroSuicuneRunGFX (bank 0) and Pichu/Wooper out of IntroPichuWooperGFX
-- (bank 1).  OBJ palettes are the back half of the scene's 128-byte palette
-- block, the part the ROM copies over wOBPals1.
--
-- Frameset_IntroSuicune is `6E 03 6F 03 70 03 71 03` then a repeat, i.e. the
-- four run frames at three ticks each on a loop.
-- The cast, as { name, oam ids, ticks per frame }.  Framesets read off the
-- ROM: Frameset_IntroSuicune is `6E 03 6F 03 70 03 71 03` then a repeat --
-- four run frames at three ticks on a loop.  Frameset_IntroPichu is
-- `72 20 73 07 74 07 FF`, three frames of the SAME OAM layout at tile offsets
-- $00/$05/$0A.  Frameset_IntroWooper is a single frame, `75 03 FF`.
RomExtractorGen2.CRYSTAL_INTRO_ACTORS = {
  { name = "suicune", oam = { 0x6E, 0x6F, 0x70, 0x71 }, ticks = { 3, 3, 3, 3 } },
  { name = "pichu",   oam = { 0x72, 0x73, 0x74 },       ticks = { 32, 7, 7 } },
  { name = "wooper",  oam = { 0x75 },                   ticks = { 3 } },
}
RomExtractorGen2.CRYSTAL_INTRO_SHEETS = {
  [0] = "IntroSuicuneRunGFX",     -- attr bit 3 clear
  [1] = "IntroPichuWooperGFX",    -- attr bit 3 set
  palette = "IntroBackgroundPalette",
}

-- SpriteAnimOAMData entry -> { tileOffset, rows = { {dy, dx, tile, attr} } }
function RomExtractorGen2:gen2SpriteOam(oamId)
  local table_ = self:symbol("SpriteAnimOAMData")
  if not (table_ and self.rom) then return nil end
  local out
  pcall(function()
    local entry = table_.address + oamId * 3
    local offset = self.rom:byte(table_.bank, entry)
    local address = self.rom:word(table_.bank, entry + 1)
    local count = self.rom:byte(table_.bank, address)
    local rows = {}
    for index = 0, count - 1 do
      local raw = self.rom:bytes(table_.bank, address + 1 + index * 4, 4)
      rows[#rows + 1] = {
        signedByte(raw[1]), signedByte(raw[2]),
        (raw[3] + offset) % 256, raw[4],
      }
    end
    out = rows
  end)
  return out
end

function RomExtractorGen2:extractCrystalIntroActors()
  local cfg = RomExtractorGen2.CRYSTAL_INTRO_SHEETS
  local sheets = { [0] = self:gen2Lz(cfg[0]), [1] = self:gen2Lz(cfg[1]) }
  local pals = self:gen2CgbPalettes(cfg.palette, 16)
  if not (sheets[0] and pals) then return nil end
  local tiles = {
    [0] = gen2SplitTiles(sheets[0]),
    [1] = sheets[1] and gen2SplitTiles(sheets[1]) or {},
  }

  local out = {}
  for _, spec in ipairs(RomExtractorGen2.CRYSTAL_INTRO_ACTORS) do
    local sets = {}
    local minX, minY, maxX, maxY
    for index, oamId in ipairs(spec.oam) do
      local rows = self:gen2SpriteOam(oamId)
      if not rows then rows = {} end
      sets[index] = rows
      for _, row in ipairs(rows) do
        -- 8x16 objects, so a row covers dy .. dy+15
        local x0, y0, x1, y1 = row[2], row[1], row[2] + 7, row[1] + 15
        minX = math.min(minX or x0, x0); minY = math.min(minY or y0, y0)
        maxX = math.max(maxX or x1, x1); maxY = math.max(maxY or y1, y1)
      end
    end
    if minX then
      -- one canvas for every frame of this actor so they cannot jitter
      local width, height = maxX - minX + 1, maxY - minY + 1
      local originX, originY = -minX, -minY
      local frames, sequence = {}, {}
      for index, rows in ipairs(sets) do
        local image = ImageWriter.blank(width, height, 0, 0, 0, 0)
        for _, row in ipairs(rows) do
          local dy, dx, tile, attr = row[1], row[2], row[3], row[4]
          local bank = math.floor(attr / 8) % 2
          -- OBJ palettes are the second eight of the block, the half the ROM
          -- copies over wOBPals1
          local pal = pals[8 + (attr % 8) + 1]
          local xFlip = math.floor(attr / 32) % 2 == 1
          local yFlip = math.floor(attr / 64) % 2 == 1
          local sheet = tiles[bank] or tiles[0]
          local top = tile - tile % 2
          for half = 0, 1 do
            local pixels = sheet[top + half]
            if pixels and pal then
              for y = 0, 7 do
                for x = 0, 7 do
                  local shade = pixels[y * 8 + x + 1]
                  if shade ~= 0 then     -- OBJ colour 0 is transparent
                    local sx = xFlip and (7 - x) or x
                    local sy = half * 8 + y
                    if yFlip then sy = 15 - sy end
                    local color = pal[shade + 1]
                    local px, py = originX + dx + sx, originY + dy + sy
                    if px >= 0 and px < width and py >= 0 and py < height then
                      image:setPixel(px, py, color[1], color[2], color[3], 1)
                    end
                  end
                end
              end
            end
          end
        end
        local file = "intro/crystal_" .. spec.name .. "_" .. index .. ".png"
        self:saveImage(image, file)
        frames[index] = "assets/generated/" .. file
        sequence[index] = { index, spec.ticks[index] or 4 }
      end
      out[spec.name] = {
        frames = frames, sequence = sequence,
        originX = originX, originY = originY,
      }
    end
  end
  return next(out) and out or nil
end

function RomExtractorGen2:gen2CrystalIntroScene(spec)
  local tilemap = self:gen2Lz(spec[2])
  local attrmap = self:gen2Lz(spec[3])
  local pals = self:gen2CgbPalettes(spec[4], 8)
  if not (tilemap and attrmap and pals) then return nil end

  -- tile id -> pixels, assembled from each blob at the id range its VRAM
  -- destination covers
  local tiles = {}
  for _, load in ipairs(spec[5]) do
    local blob = self:gen2Lz(load[1])
    local base = (load[2] == 0x9000 and 0x00)
      or (load[2] == 0x8800 and 0x80) or nil
    if blob and base then
      for index, tile in pairs(gen2SplitTiles(blob)) do
        local id = (base + index) % 256
        if tiles[id] == nil then tiles[id] = tile end
      end
    end
  end

  local pulse = spec[7] == "pulse"
  -- the whole 32-tile BG map row, not just the visible 20, so a scrolling
  -- scene can window across it and wrap
  local image = ImageWriter.blank(256, 144, 0, 0, 0, 1)
  -- a mask keeps the shade so the tint keeps the eye's own shading
  local maskShades = { [0] = 0, 0.34, 0.67, 1 }
  for row = 0, 17 do
    for col = 0, 31 do
      local index = row * 32 + col + 1
      local tile = tiles[tilemap[index] or 0]
      if tile then
        if pulse then
          for y = 0, 7 do
            for x = 0, 7 do
              local level = maskShades[tile[y * 8 + x + 1]] or 0
              image:setPixel(col * 8 + x, row * 8 + y, level, level, level, 1)
            end
          end
        else
          local attr = (attrmap[index] or 0) % 8
          gen2DrawTile(image, tile, col * 8, row * 8, pals[attr + 1])
        end
      end
    end
  end
  local file = "intro/crystal_" .. spec[1] .. ".png"
  self:saveImage(image, file)
  return "assets/generated/" .. file
end

function RomExtractorGen2:extractCrystalIntroArt()
  if not self:symbol("IntroBackgroundTilemap") then return nil end
  local scenes, byKey = {}, {}
  for _, spec in ipairs(RomExtractorGen2.CRYSTAL_INTRO) do
    local path = byKey[spec[1]]
    if not path and spec[2] then
      local ok, result = pcall(self.gen2CrystalIntroScene, self, spec)
      path = ok and result or nil
      byKey[spec[1]] = path
    end
    if path then
      scenes[#scenes + 1] =
        { image = path, frames = spec[6], mode = spec[7], scroll = spec[8],
          actors = spec[9] }
    end
  end
  if #scenes == 0 then return nil end

  local ramps = {}
  for _, entry in ipairs(RomExtractorGen2.CRYSTAL_INTRO_RAMPS) do
    local pals = self:gen2CgbPalettes(entry[2], RomExtractorGen2.CRYSTAL_RAMP_STEPS / 4)
    -- gen2CgbPalettes groups colours in fours; the ramp is a flat list
    local flat = {}
    for _, group in ipairs(pals or {}) do
      for _, color in ipairs(group) do flat[#flat + 1] = color end
    end
    if #flat > 0 then ramps[entry[1]] = flat end
  end

  local okActors, actors = pcall(self.extractCrystalIntroActors, self)
  return {
    layout = "crystal",
    scenes = scenes,
    ramps = ramps,
    actors = (okActors and actors) or nil,
    music = "Music_CrystalOpening",
  }
end

-- GoldSilverIntro's attract movie (bank $39): the Nintendo copyright, the
-- GAME FREAK presents splash, then the ocean and grass scenes the starters
-- appear over.
function RomExtractorGen2:extractGen2IntroArt()
  local crystal = self:extractCrystalIntroArt()
  if crystal then return crystal end
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

-- The six BG palettes the town map and Pokegear casing are drawn with.
--
-- Gold calls the table PokegearPals; Crystal has no such symbol -- it splits
-- them into MalePokegearPals and FemalePokegearPals, which differ only in
-- palette 3, the colour of the gear's shell.  With neither name resolving,
-- this returned an EMPTY table and both the Pokegear map and the Fly map drew
-- every tile on palette nil, i.e. black.
--
-- `which` picks the Crystal variant ("female"); anything else takes the male
-- table, which is byte-identical to Gold's.
function RomExtractorGen2:gen2TownMapPalettes(which)
  local sym
  if which == "female" then sym = self:symbol("FemalePokegearPals") end
  sym = sym or self:symbol("PokegearPals") or self:symbol("MalePokegearPals")
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

-- PRISM SPLITS THE LANDMARK TABLE IN TWO, and that is why its map-name sign
-- never appeared.  Gold and Crystal keep one flat `Landmarks` array of four
-- byte rows -- town-map x, town-map y, then a pointer to the name -- and the
-- reader above walks it.  Prism has no symbol by that name at all: it keeps
-- the COORDINATES in six per-region compressed blobs (RegionLandmarks ->
-- Naljo/Rijon/Johto/Kanto/Sevii/TunodLandmarks, each an LZ blob the town map
-- decompresses into WRAM) and the NAMES in a separate flat `dw` table,
-- LandmarkNames, indexed by landmark id.  GetLandmarkName is the whole
-- routine: shift the id left once, add the table base, follow the word.
--
-- The sign only ever wants the name, so that second table is all this reads.
-- Coordinates stay absent, which the town map already copes with -- and
-- unpicking six LZ blobs to place cursors is a separate job from putting the
-- route's name on the screen.
function RomExtractorGen2:gen2LandmarkNames()
  local sym = self:symbol("LandmarkNames")
  if not (sym and self.rom) then return nil end
  local charmap = self:readSourceTable("charmap")
  local out = {}
  -- 255, inlined rather than named: this chunk is one `local` under
  -- Lua 5.1's 200-local ceiling for a main chunk, and a new top-level
  -- constant here stops the whole module LOADING.
  for id = 0, 255 do
    local ok = pcall(function()
      local ptr = self.rom:word(sym.bank, sym.address + id * 2)
      -- a pointer outside the ROM half of the address space is past the end
      -- of the table, not a name: stop rather than decode noise
      if ptr < 0x4000 or ptr >= 0x8000 then error("end") end
      local name = self:decodeGen2TextAt(sym.bank, ptr, charmap)
      name = name:gsub("{BYTE:1F}", "\n")
      if name == "" then error("end") end
      out[id] = { name = name }
    end)
    if not ok then break end
  end
  return next(out) and out or nil
end

function RomExtractorGen2:gen2Landmarks()
  local sym = self:symbol("Landmarks")
  if not sym then return self:gen2LandmarkNames() end
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
-- Combined TownMapGFX ($00-$2F) + PokegearGFX ($30-$5F) sheet + RLE cells.
-- Runtime draws tile-by-tile (gen1-recomp approach): $4F black, $7F cream.
function RomExtractorGen2:gen2Pokegear()
  local out = { palettes = {}, cards = {}, tilesWide = 16 }

  local function loadLzOrRaw(symbolName, maxTiles)
    local pixels = self:gen2Lz(symbolName)
    if pixels and #pixels >= 16 then return pixels end
    local sym = self:symbol(symbolName)
    if not (sym and self.rom) then return nil end
    local ok, raw = pcall(function()
      return self.rom:bytes(sym.bank, sym.address, (maxTiles or 48) * 16)
    end)
    return (ok and type(raw) == "table" and #raw >= 16) and raw or nil
  end

  local townMap = loadLzOrRaw("TownMapGFX", 48) or {}
  local gearTiles = loadLzOrRaw("PokegearGFX", 48) or {}
  local sheet = {}
  for i = 1, 0x30 * 16 do sheet[i] = townMap[i] or 0 end
  for i = 1, 0x30 * 16 do sheet[0x30 * 16 + i] = gearTiles[i] or 0 end
  while #sheet < 96 * 16 do sheet[#sheet + 1] = 0 end

  local borderPal = {
    [0] = { 28/31, 31/31, 20/31 },
    [1] = { 21/31, 21/31, 21/31 },
    [2] = { 13/31, 13/31, 13/31 },
    [3] = { 0, 0, 0 },
  }
  local image
  if ImageWriter.decode2bppColor then
    image = ImageWriter.decode2bppColor(sheet, 128, 48, borderPal, false)
  else
    image = ImageWriter.decode2bpp(sheet, 128, 48, false)
  end
  self:saveImage(image, "ui/pokegear_gear.png")
  out.tiles = "assets/generated/ui/pokegear_gear.png"
  out.tilesWide = 16

  local function cellsFromBytes(bytes)
    if type(bytes) ~= "table" then return nil end
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

  local function decodeRleSymbol(name)
    local sym = self:symbol(name)
    if not (sym and self.rom) then return nil end
    local bytes = {}
    local ok = pcall(function()
      local i = 0
      while i < 400 do
        local tile = self.rom:byte(sym.bank, sym.address + i)
        bytes[#bytes + 1] = tile
        if tile == 0xFF then break end
        bytes[#bytes + 1] = self.rom:byte(sym.bank, sym.address + i + 1)
        i = i + 2
      end
    end)
    return ok and cellsFromBytes(bytes) or nil
  end

  local FALLBACK = {
    clock = {
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  48, 127, 127, 127, 127, 127, 127,  49,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79, 127, 127, 127, 127, 127, 127, 127, 127,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  50, 127, 127, 127, 127, 127, 127,  51,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,   6,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,  23,  79,  79,
       79,  79,  22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,  79,  79,
       79,  79,  22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,  79,  79,
       79,  79,  22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,  79,  79,
       79,  79,  22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,  79,  79,
       79,  79,  22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,  79,  79,
       79,  79,  38,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,  39,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
    },
    phone = {
       79,  79,  79,  79,  79,  79,  79,  79,   6,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,  23,
       79,  79,  79,  79,  79,  79,  79,  79,  22,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  22,
        6,   7,   7,   7,   7,   7,   7,   7,  39,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  22,
       22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,
       22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,
       22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,
       22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,
       22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,
       22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,
       22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,
       22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,
       22, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  22,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
    },
    radio = {
       79,  79,  79,  79,  79,  79,  79,  79,   6,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,  23,
       79,  79,  79,  79,  79,  79,  79,  79,  22,  79,  79,  55,  79,  56,  57,  79,  58,  79,  79,  22,
       72,  74,  74,  74,  74,  74,  74,  74,  22,  59,  59,  59,  59,  59,  59,  59,  59,  59,  59,  22,
       76,  78,  78,  78,  78,  78,  78,  78,  22,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  22,
       76,  78,  78,  78,  78,  78,  78,  78,  22,  54, 127,  88,  89,  90,  91,  92,  93, 127,  53,  22,
       76,  78,  78,  78,  78,  78,  78,  78,  38,   7,   7,   7,   7,   7,   7,   7,   7,   7,   7,  39,
       76,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  77,
       76,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  77,
       76, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  77,
       76, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  77,
       76, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127,  77,
       76,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  78,  77,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
       79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,  79,
    },
  }

  out.cards = {
    clock = decodeRleSymbol("ClockTilemapRLE") or FALLBACK.clock,
    phone = decodeRleSymbol("PhoneTilemapRLE") or FALLBACK.phone,
    radio = decodeRleSymbol("RadioTilemapRLE") or FALLBACK.radio,
  }

  -- Crystal recolours the gear's shell for KRIS, so ship both tables and let
  -- the runtime pick; Gold has only the one and `female` resolves to it.
  local function collect(which)
    local built = {}
    for index, colors in pairs(self:gen2TownMapPalettes(which)) do
      local entry = {}
      for c = 0, 3 do
        local rgb = colors[c] or { 0, 0, 0 }
        entry[c + 1] = {
          math.floor(rgb[1] * 255 + 0.5),
          math.floor(rgb[2] * 255 + 0.5),
          math.floor(rgb[3] * 255 + 0.5),
        }
      end
      if type(index) == "number" then built[index + 1] = entry end
    end
    return built
  end
  out.palettes = collect(nil)
  if self:symbol("FemalePokegearPals") then
    out.palettesFemale = collect("female")
  end
  if not out.palettes[1] then
    out.palettes[1] = {
      { 230, 255, 164 }, { 172, 172, 172 }, { 107, 107, 107 }, { 0, 0, 0 },
    }
  end

  pcall(function()
    local pixels = self:gen2Lz("PokegearSpritesGFX")
    if not pixels or #pixels < 16 then return end
    while #pixels < 10 * 16 do pixels[#pixels + 1] = 0 end
    local img = ImageWriter.matteColor0(
      ImageWriter.decode2bppColor
        and ImageWriter.decode2bppColor(pixels, 16, 40, borderPal, true)
        or ImageWriter.decode2bpp(pixels, 16, 40, true))
    self:saveImage(img, "ui/pokegear_sprites.png")
    out.sprites = "assets/generated/ui/pokegear_sprites.png"
  end)

  pcall(function()
    local sym = self:symbol("ChrisSpriteGFX")
    if not (sym and self.rom) then return end
    local raw = self.rom:bytes(sym.bank, sym.address, 4 * 16)
    local redPal = {
      [0] = { 28/31, 31/31, 16/31 },
      [1] = { 31/31, 19/31, 10/31 },
      [2] = { 31/31, 7/31, 1/31 },
      [3] = { 0, 0, 0 },
    }
    local img
    if ImageWriter.decode2bppColor then
      img = ImageWriter.matteColor0(ImageWriter.decode2bppColor(raw, 16, 16, redPal, true))
    else
      img = ImageWriter.matteColor0(ImageWriter.decode2bpp(raw, 16, 16, true))
    end
    self:saveImage(img, "ui/pokegear_player.png")
    out.playerIcon = "assets/generated/ui/pokegear_player.png"
  end)

  return out
end

-- Crystal lets you play as KRIS, and ships a complete parallel asset set for
-- her.  The formats are NOT uniform with Chris's, which is the trap here:
--
--   KrisPic / KrisCardPic   raw, COLUMN-major (like a mon pic), same as
--                           Chris's Crystal card pic
--   KrisBackpic             raw 6x6 -- where ChrisBackpic is LZ3 compressed
--   KrisSpriteGFX           an ordinary overworld sheet, same geometry as
--                           ChrisSpriteGFX
--   KrisNameMenuHeader.FemaleNames  the default-name list the naming screen
--                           offers a girl
--
-- Everything is emitted under `playerForms`, one record per gender, so the
-- runtime picks a whole consistent set from save.player.gender rather than
-- second-guessing per asset.
RomExtractorGen2.PLAYER_FORM_GEOMETRY = {
  card = { cols = 5, rows = 7 },   -- trainer card portrait
  back = { cols = 6, rows = 6 },   -- battle back pic
  intro = { cols = 7, rows = 7 },  -- the bigger pic the Oak speech shows
}

-- A raw (uncompressed) column-major pic -> PNG.  With `pal` the four shades
-- are baked in, which is how KRIS keeps her blue hair: the trainer card and
-- the Oak intro colour the player pic through the SGB zone shader, and that
-- shader only knows CHRIS's browns.
function RomExtractorGen2:gen2RawColumnPicAt(bank, address, cols, rows, relative, pal)
  if not self.rom then return nil end
  local ok = pcall(function()
    local raw = self.rom:bytes(bank, address, cols * rows * 16)
    assert(raw and #raw >= cols * rows * 16, "short pic")
    local pixels = colMajorToRowMajor(raw, cols, rows)
    local image
    if pal and ImageWriter.decode2bppColor then
      image = ImageWriter.decode2bppColor(pixels, cols * 8, rows * 8, pal, false)
    else
      image = ImageWriter.decode2bpp(pixels, cols * 8, rows * 8)
    end
    self:saveImage(ImageWriter.matteColor0(image), relative)
  end)
  return ok and ("assets/generated/" .. relative) or nil
end

function RomExtractorGen2:gen2RawColumnPic(symbolName, cols, rows, relative, pal)
  local sym = self:symbol(symbolName)
  if not (sym and self.rom) then return nil end
  local ok = pcall(function()
    local raw = self.rom:bytes(sym.bank, sym.address, cols * rows * 16)
    assert(raw and #raw >= cols * rows * 16, "short pic: " .. symbolName)
    local pixels = colMajorToRowMajor(raw, cols, rows)
    local image
    if pal and ImageWriter.decode2bppColor then
      image = ImageWriter.decode2bppColor(pixels, cols * 8, rows * 8, pal, false)
    else
      image = ImageWriter.decode2bpp(pixels, cols * 8, rows * 8)
    end
    self:saveImage(ImageWriter.matteColor0(image), relative)
  end)
  return ok and ("assets/generated/" .. relative) or nil
end

-- The same, for a pic stored LZ3-compressed rather than raw -- which is what
-- every Gen2 back sprite is, ChrisBackpic included (KrisBackpic is the odd
-- raw one out).  The tile count comes from the decompressed size, because a
-- back pic is always square.
function RomExtractorGen2:gen2Lz3ColumnPic(symbolName, relative, pal)
  local sym = self:symbol(symbolName)
  if not (sym and self.rom) then return nil end
  local ok = pcall(function()
    local raw = self.rom:bytes(sym.bank, sym.address, 0x8000 - sym.address)
    local pixels = decompressLz3(raw)
    local tiles = math.floor(math.sqrt(math.floor(#pixels / 16)) + 0.5)
    assert(tiles >= 1 and tiles * tiles * 16 <= #pixels,
           "short pic: " .. symbolName)
    local rowMajor = colMajorToRowMajor(pixels, tiles, tiles)
    local image
    if pal and ImageWriter.decode2bppColor then
      image = ImageWriter.decode2bppColor(rowMajor, tiles * 8, tiles * 8,
                                          pal, false)
    else
      image = ImageWriter.decode2bpp(rowMajor, tiles * 8, tiles * 8)
    end
    self:saveImage(ImageWriter.matteColor0(image), relative)
  end)
  return ok and ("assets/generated/" .. relative) or nil
end

-- The default names Crystal offers for each gender.  NameMenuHeader's list is
-- a run of VARIABLE-length $50-terminated strings, not fixed-width records --
-- reading it on an 8-byte stride splices them into each other ("MECHRIS").
-- The first entry is the menu's own NEW NAME row and the last is its trailing
-- label, so the real names are the ones in between.
function RomExtractorGen2:gen2NamePresets(symbolName, wanted)
  local sym = self:symbol(symbolName)
  if not (sym and self.rom) then return nil end
  local all = {}
  pcall(function()
    local current, address = {}, sym.address
    for _ = 1, 96 do
      local byte = self.rom:byte(sym.bank, address)
      address = address + 1
      if byte == 0x50 then
        if #current > 0 then
          all[#all + 1] = gen2DecodeString(current, #current)
          current = {}
        end
        if #all >= (wanted or 5) + 1 then break end
      elseif byte == 0xFF or byte == 0x00 then
        break
      else
        current[#current + 1] = byte
      end
    end
  end)
  local names = {}
  for index = 2, #all do
    local text = all[index]
    -- drop the menu's own trailing label and anything that decoded oddly
    if type(text) == "string" and text ~= "" and not text:find("NAME") then
      names[#names + 1] = text
    end
  end
  return names[1] and names or nil
end

-- The two records themselves.  Deliberately independent of the sprite pass --
-- extractField runs BEFORE extractRuntimeScaffolds, so this can only name
-- Kris's sprite ids as strings; registerGen2KrisSprites below creates them.
-- Prism does not have two player characters, it has FOURTEEN, and the choice
-- is real character customisation rather than a boy/girl question.
--
-- GetPlayerSprite (engine/overworld.asm) reads `wPlayerCharacteristics & $f`,
-- indexes .Male0/.Female0/.Male1/... at a 9-byte stride, and walks that set as
-- `db state, sprite` pairs terminated by $ff:
--
--     .Male0
--       db PLAYER_NORMAL,    SPRITE_P0
--       db PLAYER_BIKE,      SPRITE_P0_BIKE
--       db PLAYER_SURF,      SPRITE_P0_SURF
--       db PLAYER_SURF_PIKA, SPRITE_SURFING_PIKACHU
--       db $ff
--
-- Keyed by form id ("p0".."p13") with `boy` and `girl` kept as aliases for the
-- first male and female set, because every consumer -- Sprites.playerForm,
-- Player:refreshForm, the Oak speech's ask_gender step -- looks the record up
-- by `save.player.gender` and does not care what the key is called.  So a
-- selection screen only has to write "p7" there for the rest to follow.
RomExtractorGen2.PRISM_PLAYER_SET_BYTES = 9
-- GetPlayerFrontpic / GetPlayerBackpic both branch at `cp 12`: the first
-- twelve characters index a flat array, the last two have their own symbols.
RomExtractorGen2.PRISM_PLAYER_FLAT_SETS = 12
RomExtractorGen2.PRISM_PLAYER_SETS = 14
-- constants/wram_constants.asm: PLAYER_NORMAL 0, PLAYER_BIKE 1, PLAYER_SURF 4,
-- PLAYER_SURF_PIKA 8.  SURF is FOUR, not two -- these are bit positions, not a
-- dense enum, and reading it as 2 silently dropped every surf sheet.
RomExtractorGen2.PRISM_PLAYER_STATES = { [0] = "walk", [1] = "bike", [4] = "surf" }

-- Prism gives every species its own OVERWORLD sheet, and it is NOT the party
-- minipic.  GetMonSprite.NPCPokemon indexes PokemonOWSpritePointers -- a `dba`
-- per species -- and loads twelve tiles with `lb hl, PAL_OW_PLAYER,
-- WALKING_SPRITE`, i.e. a walking sprite on the player's OBJ palette.  The
-- files are gfx/overworld/pokemon/<name>.2bpp.lz: 384 bytes decompressed, the
-- same 24-tile six-pose sheet Prism's player characters use.
--
-- Drawing the minipic instead is what put a two-frame party icon on the map
-- where the Larvitar's walking sprite belongs, and it came out purple because
-- an icon is baked in the MON's palette rather than the overworld one.
RomExtractorGen2.PRISM_MON_OW_FRAME_BYTES = 64   -- one 2x2 frame of 2bpp

function RomExtractorGen2:extractPrismMonOverworldSprites(speciesOrder)
  local sym = self:symbol("PokemonOWSpritePointers")
  if not (sym and self.rom and speciesOrder) then return nil end
  local out = {}
  for species = 1, #speciesOrder do
    pcall(function()
      local entry = sym.address + (species - 1) * 3
      local bank = self.rom:byte(sym.bank, entry)
      local address = self.rom:word(sym.bank, entry + 1)
      if bank < 1 or address < 0x4000 or address >= 0x8000 then return end
      local raw = self:gen2LzAt(bank, address)
      local frameBytes = RomExtractorGen2.PRISM_MON_OW_FRAME_BYTES
      -- accepted only as a whole number of 2x2 frames, so a pointer that is
      -- not really a sheet falls through and the species keeps its icon
      if not (raw and #raw >= frameBytes and #raw % frameBytes == 0) then return end
      local frames = #raw / frameBytes
      local image = ImageWriter.decode2bpp(raw, 16, frames * 16)
      local file = string.format("sprites/mon_ow_%03d.png", species)
      self:saveImage(image, file)
      out[gen2MonSpriteId(species)] = {
        image = "assets/generated/" .. file,
        frames = frames,
      }
    end)
  end
  return next(out) and out or nil
end

function RomExtractorGen2:extractPrismPlayerForms()
  local sym = self:symbol("PlayerSpriteSets")
  if not (sym and self.rom) then return nil end
  local sprites = self:gen2OverworldSprites()
  local byIndex = {}
  for _, row in pairs(sprites) do byIndex[row.index] = row end

  local forms = {}
  local backSym = self:symbol("PlayerBackpics") or self:symbol("ChrisBackpic")
  local picsSym = self:symbol("PlayerPics") or self:symbol("ChrisPic")
  local patrolSym = self:symbol("PlayerPalettePatroller")
  local patrolBackSym = self:symbol("PlayerPalettePatrollerBack")
  local G = RomExtractorGen2.PLAYER_FORM_GEOMETRY
  local PRISM_BACKPIC_BYTES = G.back.cols * G.back.rows * 16
  local PRISM_INTRO_BYTES = G.intro.cols * G.intro.rows * 16
  local ok = pcall(function()
    for set = 0, RomExtractorGen2.PRISM_PLAYER_SETS - 1 do
      local at = sym.address + set * RomExtractorGen2.PRISM_PLAYER_SET_BYTES
      local record = { label = string.format("%d", set + 1) }
      for pair = 0, 3 do
        local state = self.rom:byte(sym.bank, at + pair * 2)
        if state == 0xFF then break end
        local spriteId = self.rom:byte(sym.bank, at + pair * 2 + 1)
        local key = RomExtractorGen2.PRISM_PLAYER_STATES[state]
        local row = byIndex[spriteId]
        -- only ids whose sheet actually came out of the ROM: naming one that
        -- was never extracted leaves the player invisible, where leaving the
        -- key unset falls back to field.playerSprites
        if key and row then record[key] = row.id end
      end
      -- The pic the character-select screen shows.  Prism keeps twelve of
      -- them in one PlayerPics block as RAW 7x7 2bpp -- ChrisPic, KrisPic,
      -- ChrisPic2, KrisPic2, ... -- exactly the shape Crystal's ChrisPic has,
      -- so gen2RawColumnPic reads them unchanged.
      --
      -- Without this the select screen fell through to field.playerPics.front,
      -- which points at the BACK pic, and Prism's back pics are `.xbpp` (a
      -- custom bit depth) stored uncompressed where the reader expects LZ3 --
      -- so what it drew was a decompressor's output on raw data.  That is the
      -- scrambled trainer sprite on the boy/girl screen.
      -- GetPlayerFrontpic is `and $f / cp 12 / jr nc, .palettePatroller /
      -- ld hl, PlayerPics / ld bc, 7 * 7 tiles / rst AddNTimes`: a flat array
      -- indexed by character, with the last two characters served by their own
      -- symbol.  ChrisPic and PlayerPics are the same address, so the first
      -- twelve fall out of one stride.
      local picBank, picAt = nil, nil
      if set < RomExtractorGen2.PRISM_PLAYER_FLAT_SETS and picsSym then
        picBank, picAt = picsSym.bank, picsSym.address + set * PRISM_INTRO_BYTES
      elseif patrolSym then
        picBank, picAt = patrolSym.bank, patrolSym.address
      end
      if picBank then
        record.intro = self:gen2RawColumnPicAt(
          picBank, picAt, G.intro.cols, G.intro.rows,
          "battle/prism_player" .. set .. ".png", nil)
        record.card = record.intro
      end
      -- The battle BACK pic.  `.xbpp` is a red herring -- GetPlayerBackpic is
      -- `ld bc, 6 * 6 tiles / ld hl, PlayerBackpics / rst AddNTimes` then a
      -- plain Get2bpp, and p0.xbpp is exactly 576 bytes, so it is ordinary
      -- raw column-major 2bpp indexed by character.  Read through
      -- ChrisBackpic as an LZ3 pic (which is what it is in Crystal), the
      -- decompressor ran on raw pixels: that is the scrambled back sprite in
      -- battle, and it was the same for all fourteen characters because only
      -- one symbol was ever consulted.
      -- and GetPlayerBackpic is the same shape, with the same cut-off -- the
      -- last two characters' back pic is 7x7 rather than 6x6.
      if set < RomExtractorGen2.PRISM_PLAYER_FLAT_SETS and backSym then
        record.back = self:gen2RawColumnPicAt(
          backSym.bank, backSym.address + set * PRISM_BACKPIC_BYTES,
          G.back.cols, G.back.rows,
          "battle/prism_playerback" .. set .. ".png", nil)
      elseif patrolBackSym then
        record.back = self:gen2RawColumnPicAt(
          patrolBackSym.bank, patrolBackSym.address,
          G.intro.cols, G.intro.rows,
          "battle/prism_playerback" .. set .. ".png", nil)
      end
      if record.walk then
        forms["p" .. set] = record
        -- the sets alternate male, female, male, female...
        if set == 0 then forms.boy = record end
        if set == 1 then forms.girl = record end
      end
    end
  end)
  if not ok or not next(forms) then return nil end
  return forms
end

-- ---------------------------------------------------------------------------
-- Prism's character customisation  (event/customization.asm PlayerCustomization)
--
-- Prism does not ask "boy or girl?".  The intro runs PlayerCustomization, which
-- asks three questions and packs the answers into wPlayerCharacteristics:
--
--   byte 0  bit 0    gender          } together `& $f`, the index
--           bits 1-3 character model } GetPlayerSprite reads
--           bits 4-6 skin tone
--   bytes 1-2        the outfit colour, a 15-bit RGB the player mixes on
--                    three 0-31 sliders
--
-- src/ui/PrismCustomization.lua has drawn all of that since it was written, and
-- src/ui/OakSpeech.lua already runs it as a `customize_player` step -- but both
-- gate on `field.playerCustomization`, WHICH NOTHING EVER EMITTED.  So the step
-- was dropped from the intro on every boot and Prism silently kept Crystal's
-- boy/girl question.  This is the missing table.
--
--   SkinTonePalettes   seven RGB15 words (SkinToneBox sits 14 bytes behind it,
--                      which is what sizes the list)
--   models             PlayerSpriteSets is fourteen sets and the model menu is
--                      a two-column grid -- `wMenuCursorY-1` doubled, or'd with
--                      `wMenuCursorX-1` -- so seven rows of boy/girl
--   default            PlayerCust_InitRAM zeroes the characteristics byte and
--                      calls PlayerCust_InitBluePal, which writes $00 $7C:
--                      RGB15 $7C00, i.e. pure blue
-- ---------------------------------------------------------------------------
function RomExtractorGen2:gen2PlayerCustomization()
  local sym = self:symbol("SkinTonePalettes")
  if not (sym and self.rom) then return nil end
  -- size the palette list off whatever the linker put behind it
  local bytes = 7 * 2
  for _, name in ipairs({ "SkinToneBox", "PlayerCust_SetPalettes" }) do
    local next_ = self:symbol(name)
    if next_ and next_.bank == sym.bank and next_.address > sym.address then
      bytes = math.min(bytes, next_.address - sym.address)
      break
    end
  end
  local tones = {}
  local ok = pcall(function()
    for index = 0, math.floor(bytes / 2) - 1 do
      local word = self.rom:word(sym.bank, sym.address + index * 2)
      tones[index + 1] = {
        r = word % 32,
        g = math.floor(word / 32) % 32,
        b = math.floor(word / 1024) % 32,
      }
    end
  end)
  if not ok or not tones[1] then return nil end

  -- one model row per PAIR of sprite sets; the odd one out (a set with no
  -- partner) still gets a row rather than being unreachable
  local sets = RomExtractorGen2.PRISM_PLAYER_SETS or 2
  local models = math.max(1, math.ceil(sets / 2))

  return {
    models = models,
    skinTones = tones,
    -- the three outfit sliders, 0-31 each, drawn at x = 14, 16 and 18
    channels = { "r", "g", "b" },
    maxLevel = 31,
    default = { form = "p0", skinTone = 1, clothes = { r = 0, g = 0, b = 31 } },
  }
end

function RomExtractorGen2:extractGen2PlayerForms()
  local prism = self:extractPrismPlayerForms()
  if prism then return prism end
  -- Gold and Silver have no second player character; nothing to choose.
  if not self:symbol("KrisPic") then return nil end
  local G = RomExtractorGen2.PLAYER_FORM_GEOMETRY
  local krisPal = self:gen2TwoColorPalette("KrisPalette")
  -- GetPlayerOrMonPalettePointer (02:$574B) picks between exactly these two:
  -- PlayerPalette (02:$70CE) for Chris and KrisPalette (02:$70D2) for Kris.
  -- They are FOUR bytes apart because each is the two-colour trainer format,
  -- so Chris's pair is his skin and that red-brown jacket.
  local chrisPal = self:gen2TwoColorPalette("PlayerPalette")
  -- Chris's three pics, baked in PlayerPalette exactly as Kris's are baked in
  -- hers.  trueColor is a property of the FORM, not of one pic, so it can only
  -- be set once all three are baked: the boy record used to claim trueColor
  -- while pointing `card` and `back` at the plain four-shade chrisf.png and
  -- chrisb.png rips, which told the renderer those were already coloured and
  -- left the trainer card portrait and the battle back sprite in black and
  -- white.  They are written under their own names so the uncoloured
  -- playerPics defaults, which the zone shader still owns, stay untouched.
  local chrisCard = self:gen2RawColumnPic("ChrisCardPic", G.card.cols,
                                          G.card.rows,
                                          "battle/chriscard.png", chrisPal)
  local chrisBack = self:gen2Lz3ColumnPic("ChrisBackpic",
                                          "battle/chrisback.png", chrisPal)
  local chrisIntro = self:gen2RawColumnPic("ChrisPic", G.intro.cols,
                                           G.intro.rows,
                                           "battle/chrisintro.png", chrisPal)
  local chrisBaked = (chrisCard and chrisBack and chrisIntro) and true or nil
  return {
    boy = {
      label = "BOY",
      card = chrisCard or "assets/generated/battle/chrisf.png",
      -- Bake Chris the same way Kris is baked.  Leaving him to the SGB zone
      -- shader is what put him on the gender-select screen in purple and
      -- white: the shader has no idea this pic is the player and coloured him
      -- off whatever zone palette was live, so the two choices never matched
      -- each other or the cartridge.
      trueColor = chrisBaked,
      intro = chrisIntro,
      -- gen2SpriteConstant maps ChrisSpriteGFX / ChrisBikeSpriteGFX onto the
      -- engine's SPRITE_RED / SPRITE_RED_BIKE ids (GEN2_SPRITE_ID_OVERRIDES
      -- $01/$02), so naming SPRITE_CHRIS here matched nothing and the boy
      -- record silently fell through to field.playerSprites.
      back = chrisBack or "assets/generated/battle/chrisb.png",
      walk = "SPRITE_RED", bike = "SPRITE_RED_BIKE",
      names = self:gen2NamePresets("ChrisNameMenuHeader.MaleNames", 5),
    },
    girl = {
      label = "GIRL",
      -- KrisPalette is the ordinary two-colour trainer format (white and
      -- black implied), and its first entry is her skin and that blue hair.
      trueColor = true,
      card = self:gen2RawColumnPic("KrisCardPic", G.card.cols, G.card.rows,
                                   "battle/krisf.png", krisPal),
      -- the Oak intro shows the bigger 7x7 pic, not the card portrait
      intro = self:gen2RawColumnPic("KrisPic", G.intro.cols, G.intro.rows,
                                    "battle/krisintro.png", krisPal),
      -- KrisBackpic is the odd one out: ChrisBackpic is LZ3 and hers is a
      -- raw INCBIN, still column-major, still 6x6 = 36 tiles (the gap to the
      -- next label in bank $22 is exactly $240 bytes).  GetKrisBackpic's
      -- `ld bc, $2231` is NOT the size -- $31 = 49 is the 7x7 VRAM box
      -- Get2bpp fills, so it copies 13 tiles of whatever follows and the
      -- battle never draws them.  Reading 49 tiles here is what shredded
      -- her: at 49 tiles the column stride is 7, not 6.
      back = self:gen2RawColumnPic("KrisBackpic", G.back.cols, G.back.rows,
                                   "battle/krisb.png", krisPal),
      walk = "SPRITE_KRIS", bike = "SPRITE_KRIS_BIKE",
      names = self:gen2NamePresets("KrisNameMenuHeader.FemaleNames", 5),
    },
  }
end

-- Kris's overworld sheets ride on Chris's row geometry -- same width, height
-- and frame count, different pixels -- and are registered as their own sprite
-- ids so playerSprites.walk can simply name one.
--
-- Crystal's own OverworldSprites table already carries her: KrisSpriteGFX is
-- slot 95 (SPRITE_KRIS, $60) and KrisBikeSpriteGFX slot 96, both on OBJ
-- palette 1 rather than Chris's 0.  So the normal sprite pass writes both
-- sheets correctly and this is only a backstop for a rip where that row is
-- missing -- it must NOT overwrite the real row, whose palette is right.
function RomExtractorGen2:registerGen2KrisSprites(sprites, spriteDefFor)
  if not (sprites and spriteDefFor and self:symbol("KrisSpriteGFX")) then return end
  for _, pair in ipairs({
    { "KrisSpriteGFX", "Chris", "SPRITE_KRIS", "sprites/kris.png" },
    { "KrisBikeSpriteGFX", "ChrisBike", "SPRITE_KRIS_BIKE", "sprites/kris_bike.png" },
  }) do
    local sym = self:symbol(pair[1])
    -- `sprites[id] and nil or spriteDefFor(...)` ALWAYS took the right branch:
    -- in Lua `x and nil or y` reduces to plain `y`, because `x and nil` is
    -- falsy whatever x was and `or` then hands back y.  So this backstop fired
    -- on every Crystal import and clobbered the REAL rows -- SPRITE_KRIS came
    -- out cloned from Chris's row 1, carrying his OBJ palette 0 (the red one)
    -- and his index, and Kris walked the overworld in his colours.  Rows 96
    -- and 97, the ones with palette 1, never reached the data at all.
    local def = (not sprites[pair[3]]) and spriteDefFor(pair[2]) or nil
    if sym and def and self.rom then
      pcall(function()
        local raw = self.rom:bytes(sym.bank, sym.address, def.bytes)
        assert(#raw >= def.bytes, "short Kris sheet")
        self:saveImage(ImageWriter.decode2bpp(raw, def.width, def.height),
                       pair[4])
        local built = {}
        for key, value in pairs(sprites[def.id] or {}) do built[key] = value end
        built.id = pair[3]
        built.image = "assets/generated/" .. pair[4]
        sprites[pair[3]] = built
      end)
    end
  end
end

function RomExtractorGen2:gen2PlayerFrontPic()
  -- Prefer the dedicated trainer-card/front sheet; fall through alternate
  -- pret labels so a symbols file rename does not leave the card on the
  -- battle back pic.
  -- Gold packs the card portrait and the card's own tiles into one sheet and
  -- stores it ROW-major.  Crystal splits them -- ChrisCardPic / KrisCardPic
  -- for the portrait, TrainerCardGFX for the furniture -- and stores the
  -- portrait COLUMN-major, the way it stores mon pics.  Reading Crystal's with
  -- Gold's row order is what shredded the block over ID No./MONEY.
  local sym = self:symbol("ChrisPicAndTrainerCardGFX")
    or self:symbol("ChrisPicFront")
    or self:symbol("PlayerPic")
  local columnMajor = false
  if not sym then
    sym = self:symbol("ChrisCardPic")
    columnMajor = sym and true or false
  end
  if not (sym and self.rom) then return nil end
  local relative = "battle/chrisf.png"
  local cols, rows = GEN2_PLAYER_PIC_COLS, GEN2_PLAYER_PIC_ROWS
  local ok = pcall(function()
    local raw = self.rom:bytes(sym.bank, sym.address, cols * rows * 16)
    assert(raw and #raw >= cols * rows * 16, "short Chris front pic")
    if columnMajor then raw = colMajorToRowMajor(raw, cols, rows) end
    self:saveImage(ImageWriter.matteColor0(
      ImageWriter.decode2bpp(raw, cols * 8, rows * 8)), relative)
  end)
  -- No LZ3 fallback: unlike the back pic, the trainer-card front is NOT a
  -- compressed trainer pic.  There is no `ChrisPic` label in pokegold, so a
  -- decompress attempt here could only ever produce garbage.
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
      -- GetTreeMons (2E:$42D2) is `cp $08 / jr nc, .quit` then `and a / jr z,
      -- .quit`: the valid set indices are 1 through SEVEN.  Only 0 means "no
      -- trees here".  Capping this at 3 threw away every map tagged Kanto,
      -- Lake or Forest.
      if entry and set >= 1 and set <= 7 then out.maps[entry.label] = set end
      address = address + 3
    end
    -- A tree set is TWO $FF-terminated tables back to back, common then rare,
    -- and a row is `db chance, species, level` -- exactly the shape the rock
    -- table below already uses.  There is NO leading total-chance byte.
    --
    -- Reading it as a rate byte plus six `species, level, chance` rows shifted
    -- every field by one and ran a row past the terminator, so headbutt spawned
    -- nonsense: the Forest set's real first row is `50, CATERPIE, 10`, which
    -- came out as species 10 / level 10 / chance 15.  Verified by decoding
    -- TreeMonSet_Forest (2E:$649C) against pret's source.
    local function readTable(at)
      local rows = {}
      for _ = 1, 16 do
        local chance = self.rom:byte(setsSym.bank, at)
        if chance == 0xFF then
          at = at + 1
          break
        end
        rows[#rows + 1] = {
          chance = chance,
          species = string.format("SPECIES_%03d",
            self.rom:byte(setsSym.bank, at + 1)),
          level = self.rom:byte(setsSym.bank, at + 2),
        }
        at = at + 3
      end
      return rows, at
    end
    -- TreeMons (2E:$42E8) is seven sets, and every one of them is reachable:
    --   1 Canyon  2 Town  3 Route  4 Kanto  5 Lake  6 Forest  7 Rock
    -- TreeMonMaps tags maps with 1 through 6, and NINE of them -- Routes 29,
    -- 30, 31, 34, 35, 36, 37, 38, 39, i.e. most of the early game -- carry
    -- set 3, Route.
    --
    -- Reading only sets 1 and 2 left all of those maps pointing at a set that
    -- was never extracted, so `sets` came up nil and headbutt on any of them
    -- could only ever answer "Nope. Nothing…" -- no mon ever appeared.  Set 3
    -- was ALSO being read as the rock-smash list, which is Route's table, not
    -- Rock's; rock is set 7, and its own symbol pins it.
    local rockSym = self:symbol("TreeMonSet_Rock")
    local rockIndex = 7
    for set = 1, 7 do
      if rockSym
         and self.rom:word(setsSym.bank, setsSym.address + set * 2)
             == rockSym.address then
        rockIndex = set
      end
    end
    for set = 1, 7 do
      local at = self.rom:word(setsSym.bank, setsSym.address + set * 2)
      local common, afterCommon = readTable(at)
      -- Rock's set is the last one in the bank and has no rare half; reading
      -- one anyway walks into GetTreeMon's code, and if a future rip ever put
      -- it at the very end of the bank that read would assert and take the
      -- whole table down with it.
      local rare = (set ~= rockIndex) and (readTable(afterCommon)) or {}
      out.sets[set] = { common = common, rare = rare }
    end
    -- RockMonEncounter rolls the same structure, so the rock list is just
    -- that set's common table.
    out.rock = (readTable((rockSym and rockSym.address)
      or self.rom:word(setsSym.bank, setsSym.address + rockIndex * 2)))
  end)
  if not ok or not next(out.maps) then return nil end
  return out
end

-- The Bug Catching Contest, read off the cartridge rather than transcribed.
--
-- ContestMons (crystal 25:$7D87) is the contest's own encounter table, and
-- ChooseWildEncounter_BugContest (25:$7D31) fixes its shape: `Random` is
-- rejected at >= 200 then halved to 0-99, so the FIRST byte of each 4-byte row
-- is a percentage rate, followed by species, min level and max level.  The ten
-- rates total exactly 100.  A level is `min + Random % (max - min + 1)`, or
-- just `min` when the two are equal.
--
-- BugContestantPointers (04:$7783) is indexed by `contestantID - 1`, so slot 0
-- is unused and the nine AI contestants are IDs 2-10 (the player is 1):
-- ComputeAIContestantScores (04:$78B0) builds the ID with `ld a, e / inc a /
-- inc a` and indexes with `dec a`.  Each record is `db trainerClass, db
-- trainerID` followed by THREE `db species, dw score` picks, one of which that
-- contestant rolls on the day (`Random & 3`, re-rolled on 3).
--
-- Balls and clock come from GiveParkBalls (04:$75DB) and StartBugContestTimer
-- (04:$5490); both are `ld a, $14` -- 20 Park Balls, 20 minutes.
--
-- Prizes are deliberately NOT read here.  BugContestResults_FirstPlace and its
-- siblings are ordinary extracted scripts, so the VM hands out the Sun Stone /
-- Everstone / Gold Berry / Berry itself once the placings are set.
--
-- Gold and Crystal carry byte-identical tables; only the addresses differ, and
-- both are resolved through symbols.
-- The seven in-game trades (NPCTrades, crystal 3F:$4E58).
--
-- GetTradeAttr (3F:$4DC2) is `a = index & $0F / swap a / hl = NPCTrades +
-- 2*a + e`, so the stride is THIRTY-TWO bytes and every field is named by the
-- offset the engine asks for.  The offsets below are the ones NPCTrade,
-- DoNPCTrade and GetTradeMonNames actually pass in `e`, not a guess at the
-- macro:
--
--   0   dialog set        (Trade_GetDialog, 3F:$4C59)
--   1   the species the player must hand over  (NPCTrade compares it against
--       wCurPartySpecies)
--   2   the species the NPC gives back
--   3   nickname, 11 bytes                     (`ld e, $03`)
--   14  the two DV bytes                       (`ld e, $0E`)
--   17  the OT ID, two bytes                   (`ld e, $11`, copied with
--       Trade_CopyTwoBytesReverseEndian into the mon's big-endian ID field,
--       so the table itself holds it low byte first)
--   19  OT name, 11 bytes                      (`ld e, $13`)
--   30  the gender the offered mon must be     (`ld e, $1E`; 0 either,
--       1 male, 2 female -- only DORIS the DODRIO asks)
--
-- PrintTradeText (3F:$4F38) indexes TradeTexts (3F:$4F53) as `kind * 8 +
-- dialogSet * 2`: five kinds of line -- offer, declined, wrong mon, thanks,
-- already traded -- times four dialog sets, which is exactly the 40 bytes
-- between it and NPCTradeCableText.
-- The four Unown words carved into the Ruins of Alph chamber walls.
--
-- Each wall script is `writetext <patterns appear> / setval <n> / special
-- DisplayUnownWords`, and that special (22:$6E68) is the whole picture: it
-- opens the window MenuHeaders_UnownWalls (22:$6ED5) names for word n -- five
-- bytes, `db flags` then `menu_coords x1, y1, x2, y2` -- and copies the word
-- out of UnownWalls (22:$6EBC), four $FF-terminated runs of tile ids.
--
-- A glyph is a 2x2 block of the CHAMBER'S OWN tileset, and _CopyWord's
-- ConvertChar builds it from the run's byte `a` as `a, a+1` over `a+$10,
-- a+$10+1`.  Three ids are not glyph bases at all and are spelled out
-- literally: $60 is Y ($5B $5C over $4D $5D), $62 is Z ($4E $4F over $5E $5F)
-- and $64 is the dash ($02 $03 over $03 $02).
function RomExtractorGen2:gen2UnownWalls()
  local sym = self:symbol("UnownWalls")
  local boxSym = self:symbol("MenuHeaders_UnownWalls")
  if not (sym and boxSym and self.rom) then return nil end
  local out = { words = {}, boxes = {} }
  local ok = pcall(function()
    local at = sym.address
    for word = 1, 4 do
      local ids = {}
      for _ = 1, 16 do
        local id = self.rom:byte(sym.bank, at)
        at = at + 1
        if id == 0xFF then break end
        ids[#ids + 1] = id
      end
      out.words[word] = ids
      -- `db flags` then the four coords, and they are Y FIRST: word 0's row is
      -- $40 $04 $03 $09 $10, which as (y1 3, x1 4... ) would be a 6x14 slot --
      -- far too narrow for six two-tile glyphs.  Read as y1 4, x1 3, y2 9,
      -- x2 16 it is a 14x6 window, which is exactly six glyphs wide and one
      -- glyph tall, and that matches _CopyWord advancing hl by two COLUMNS per
      -- glyph.
      local row = boxSym.address + (word - 1) * 5
      out.boxes[word] = {
        y1 = self.rom:byte(boxSym.bank, row + 1),
        x1 = self.rom:byte(boxSym.bank, row + 2),
        y2 = self.rom:byte(boxSym.bank, row + 3),
        x2 = self.rom:byte(boxSym.bank, row + 4),
      }
    end
  end)
  if not ok or not (out.words[1] and out.words[1][1]) then return nil end
  return out
end

-- Crystal's fourteen Odd Eggs (OddEggs 7E:$756E, OddEggProbabilities
-- 7E:$7552).  _GiveOddEgg (7E:$74B6) rolls a 16-bit Random and walks the
-- probability list until one is not below it, then copies that record over.
--
-- A record is 59 bytes, the same battle_tower_mon shape: a 48 byte
-- party_struct then an 11 byte nickname ("EGG").  Seven species, each listed
-- twice -- the second of every pair carries the shiny DV pair $2A/$AA, which
-- is the whole point of the Odd Egg.
function RomExtractorGen2:gen2OddEggs()
  local sym = self:symbol("OddEggs")
  local probSym = self:symbol("OddEggProbabilities")
  if not (sym and probSym and self.rom) then return nil end
  local COUNT, ROW = 14, 59
  local out = { probabilities = {}, eggs = {} }
  local moveOrder = (self:constants() or {}).moveOrder or {}
  local ok = pcall(function()
    for i = 0, COUNT - 1 do
      out.probabilities[i + 1] =
        self.rom:word(probSym.bank, probSym.address + i * 2)
      local row = self.rom:bytes(sym.bank, sym.address + i * ROW, ROW)
      local moves = {}
      for m = 0, 3 do
        local id = row[3 + m]
        if id > 0 then
          moves[#moves + 1] = moveOrder[id] or string.format("MOVE_%03d", id)
        end
      end
      out.eggs[i + 1] = {
        species = string.format("SPECIES_%03d", row[1]),
        item = row[2] > 0 and string.format("ITEM_%03d", row[2]) or nil,
        moves = #moves > 0 and moves or nil,
        dvs = { row[22], row[23] },
        happiness = row[28],
        level = row[32],
      }
    end
  end)
  if not ok or not out.eggs[1] then return nil end
  return out
end

-- The Bank of Mom.  MomScript's `checkevent $40 / iftrue .BankOfMom` branch is
-- `setevent $40 / special BankOfMom / waitbutton / closetext / end` -- there is
-- no writetext anywhere in it, because the entire conversation lives inside
-- that special (5:$6218), a jumptable over IsThisAboutYourMoney,
-- StopOrStartSavingMoney, StoreMoney, TakeMoney and their refusals.  With no
-- handler the branch ran and printed nothing, which is why Mom went silent the
-- moment the banking talk unlocked.
--
-- Only her lines are read here; the flow itself is in Gen2Commands.
-- SPROUT TOWER's swaying pillar.
--
-- TilesetTowerAnim (3F:$4297) is ten rows of `dw <dest>, AnimateTowerPillarTile`
-- and each dest is a `dw <VRAM address>, dw <frame block>` pair, so ten of the
-- tileset's tiles are re-written every animation step.  The routine (3F:$4645)
-- reads `wTileAnimationTimer & 7`, indexes TowerPillarTileFrameOffsets --
-- 0, 16, 32, 48, 64, 48, 32, 16 -- and copies the 16 bytes at that offset into
-- VRAM: five distinct frames played 0 1 2 3 4 3 2 1, which is the sway going
-- out and coming back.
--
-- Written out as one strip, ten columns (one per animated tile, in the order
-- the runtime lists them) by five rows (one per frame), because the renderer
-- patches whole-atlas clones from it.
function RomExtractorGen2:gen2TowerPillarAnim()
  local sym = self:symbol("TilesetTowerAnim")
  if not (sym and self.rom) then return nil end
  local FRAMES, COUNT = 5, 10
  local tiles, raw = {}, {}
  local ok = pcall(function()
    for row = 0, COUNT - 1 do
      local entry = self.rom:word(sym.bank, sym.address + row * 4)
      -- `dw dest, dw src`: dest is the VRAM address, and vTiles2 is $9000, so
      -- the tile id is the offset from there in 16-byte units
      local dest = self.rom:word(sym.bank, entry)
      local src = self.rom:word(sym.bank, entry + 2)
      tiles[row + 1] = math.floor((dest - 0x9000) / 16)
      for frame = 0, FRAMES - 1 do
        raw[frame + 1] = raw[frame + 1] or {}
        local at = src + frame * 16
        for byte = 0, 15 do
          raw[frame + 1][row * 16 + byte + 1] = self.rom:byte(sym.bank, at + byte)
        end
      end
    end
  end)
  if not ok or not tiles[COUNT] then return nil end
  -- one 80x40 sheet: the frames stack, so row f column i is tile i at frame f
  local flat = {}
  for frame = 1, FRAMES do
    for i = 1, COUNT * 16 do flat[#flat + 1] = raw[frame][i] end
  end
  -- no matte: these are background tiles, written exactly like the tileset
  -- atlas itself, so the overdraw fully replaces the static tile underneath
  local okImage = pcall(function()
    self:saveImage(ImageWriter.decode2bpp(flat, COUNT * 8, FRAMES * 8),
                   "tilesets/towerpillar.png")
  end)
  if not okImage then return nil end
  return {
    tileset = "TilesetTower",
    image = "assets/generated/tilesets/towerpillar.png",
    tiles = tiles,
    frames = FRAMES,
    -- TowerPillarTileFrameOffsets, as 1-based frame numbers
    sequence = { 1, 2, 3, 4, 5, 4, 3, 2 },
  }
end

function RomExtractorGen2:gen2MomBank()
  local charmap = self:readSourceTable("charmap")
  local wanted = {
    isThisAboutYourMoney = "_MomIsThisAboutYourMoneyText",
    whatDoYouWantToDo = "_MomBankWhatDoYouWantToDoText",
    saveMoney = "_MomSaveMoneyText",
    startSavingMoney = "_MomStartSavingMoneyText",
    storeMoney = "_MomStoreMoneyText",
    takeMoney = "_MomTakeMoneyText",
    storedMoney = "_MomStoredMoneyText",
    takenMoney = "_MomTakenMoneyText",
    insufficientFundsInWallet = "_MomInsufficientFundsInWalletText",
    notEnoughRoomInBank = "_MomNotEnoughRoomInBankText",
    haventSavedThatMuch = "_MomHaventSavedThatMuchText",
    notEnoughRoomInWallet = "_MomNotEnoughRoomInWalletText",
    justDoWhatYouCan = "_MomJustDoWhatYouCanText",
  }
  local out = {}
  for key, symbolName in pairs(wanted) do
    local sym = self:symbol(symbolName)
    if sym then
      local ok, text = pcall(self.decodeGen2TextAt, self,
                             sym.bank, sym.address, charmap, true)
      if ok and type(text) == "string" and text ~= "" then out[key] = text end
    end
  end
  if not out.isThisAboutYourMoney then return nil end
  return out
end

function RomExtractorGen2:gen2NpcTrades()
  local sym = self:symbol("NPCTrades")
  if not (sym and self.rom) then return nil end
  -- kept function-local: RomExtractorGen2.lua sits one slot under Lua's
  -- 200-locals-per-chunk ceiling, so nothing new may go at file scope
  local ROW_BYTES, COUNT, DIALOG_SETS = 32, 7, 4
  local TEXT_KINDS = { "offer", "declined", "wrongMon", "thanks", "afterTrade" }
  -- TradeTexts closes the table, and the two ROMs do not agree on its length:
  -- Crystal has seven trades, Gold six (it has no HAUNTER/XATU row and swaps
  -- ABRA for DROWZEE), so size it off the symbol rather than a constant.
  local textSym = self:symbol("TradeTexts")
  if textSym and textSym.bank == sym.bank and textSym.address > sym.address then
    COUNT = math.min(COUNT,
      math.floor((textSym.address - sym.address) / ROW_BYTES))
  end
  local charmap = self:readSourceTable("charmap")
  local out = { trades = {}, texts = {} }
  local ok = pcall(function()
    for index = 0, COUNT - 1 do
      local at = sym.address + index * ROW_BYTES
      local row = self.rom:bytes(sym.bank, at, ROW_BYTES)
      -- 1-based, as self.rom:bytes hands the row back
      out.trades[index + 1] = {
        dialog = row[1],
        give = string.format("SPECIES_%03d", row[2]),
        get = string.format("SPECIES_%03d", row[3]),
        nickname = gen2DecodeString(self.rom:bytes(sym.bank, at + 3, 11), 11),
        dvs = { row[15], row[16] },
        -- the npctrade macro's `\6`: the mon arrives HOLDING this (GOLD BERRY,
        -- METAL COAT, ...), which is half of why some of these trades are
        -- worth doing at all
        item = row[17] ~= 0 and string.format("ITEM_%03d", row[17]) or nil,
        otId = row[18] + row[19] * 256,
        ot = gen2DecodeString(self.rom:bytes(sym.bank, at + 19, 11), 11),
        gender = row[31],
      }
    end
    -- HOW MANY DIALOG SETS THE TABLE HAS IS NOT FIXED.
    --
    -- TradeTexts is `kind-major`: five kinds (offer, declined, wrongMon,
    -- thanks, afterTrade) each followed by one pointer per dialog set.  The
    -- SET COUNT differs between the cartridges -- Crystal has four
    -- (COLLECTOR, HAPPY, GIRL, NEWBIE) and Gold only three -- so a hardcoded
    -- four walked Gold's table with a stride of 8 bytes where it is 6, read
    -- the fifth kind past the end of the table, and threw `bank 3F address
    -- out of range`.  That throw was inside this function's pcall, so
    -- gen2NpcTrades returned NIL and Gold shipped with NO in-game trade
    -- dialogue at all: every one of its six trade NPCs fell through to the
    -- engine's placeholder wording instead of the cartridge's lines.
    --
    -- The rows themselves say how many sets there are: the dialog byte is an
    -- index into exactly this table.
    local sets = 0
    for _, trade in ipairs(out.trades) do
      sets = math.max(sets, (tonumber(trade.dialog) or 0) + 1)
    end
    DIALOG_SETS = math.max(1, math.min(DIALOG_SETS, sets))
    if textSym then
      for kind, name in ipairs(TEXT_KINDS) do
        local lines = {}
        for set = 0, DIALOG_SETS - 1 do
          local pointer = self.rom:word(textSym.bank,
            textSym.address + (kind - 1) * DIALOG_SETS * 2 + set * 2)
          local text = self:decodeGen2TextAt(textSym.bank, pointer, charmap, true)
          lines[set + 1] = type(text) == "string" and text or ""
        end
        out.texts[name] = lines
      end
    end
    -- The two lines that are the same whoever you are trading with.
    -- Prism renames the cable line (ConnectLinkCableText, engine/npctrade.asm)
    -- and the base games call it NPCTradeCableText; try both.
    for key, names in pairs({ cable = { "NPCTradeCableText", "ConnectLinkCableText" },
                              tradedFor = { "TradedForText" } }) do
      local one
      for _, symbolName in ipairs(names) do
        one = one or self:symbol(symbolName)
      end
      if one then
        local text = self:decodeGen2TextAt(one.bank, one.address, charmap, true)
        if type(text) == "string" then out.texts[key] = text end
      end
    end
  end)
  if not ok or not out.trades[1] then return nil end
  return out
end

function RomExtractorGen2:gen2BugContest()
  local monsSym = self:symbol("ContestMons")
  local listSym = self:symbol("BugContestantPointers")
  if not (monsSym and listSym and self.rom) then return nil end
  local out = { parkBalls = 20, minutes = 20, mons = {}, contestants = {} }
  local ok = pcall(function()
    local at = monsSym.address
    local total = 0
    for _ = 1, 16 do
      local rate = self.rom:byte(monsSym.bank, at)
      if rate == 0 or rate == 0xFF then break end
      out.mons[#out.mons + 1] = {
        rate = rate,
        species = string.format("SPECIES_%03d", self.rom:byte(monsSym.bank, at + 1)),
        minLevel = self.rom:byte(monsSym.bank, at + 2),
        maxLevel = self.rom:byte(monsSym.bank, at + 3),
      }
      at = at + 4
      total = total + rate
      if total >= 100 then break end
    end
    for id = 2, 10 do
      local address = self.rom:word(listSym.bank, listSym.address + (id - 1) * 2)
      local picks = {}
      for pick = 0, 2 do
        local base = address + 2 + pick * 3
        picks[#picks + 1] = {
          species = string.format("SPECIES_%03d", self.rom:byte(listSym.bank, base)),
          score = self.rom:word(listSym.bank, base + 1),
        }
      end
      out.contestants[#out.contestants + 1] = {
        id = id,
        trainerClass = self.rom:byte(listSym.bank, address),
        trainerId = self.rom:byte(listSym.bank, address + 1),
        picks = picks,
      }
    end
  end)
  if not ok or not out.mons[1] then return nil end
  return out
end

-- The Battle Tower.
--
-- Crystal only: Gold and Silver have no BattleTower* symbols at all, so every
-- lookup below misses and this returns nil, which leaves the runtime module
-- and the script specials inert on those two carts exactly as the cartridge
-- leaves them.
--
-- What is read, and from where:
--   BattleTowerTrainers (7E:$414E)  70 records of 11 bytes -- a 10 byte name
--     padded with $50, then the trainer class.  70 is not a guess: the roll in
--     LoadOpponentTrainerAndPokemon is `Random & $7F` rejected at >= $46, and
--     $414E + 70 * 11 lands exactly on BattleTowerMons.
--   BattleTowerMons (7E:$4450)  level groups of 21 battle_tower_mon.  Each
--     record is 59 bytes: a 48 byte party_struct followed by an 11 byte
--     nickname, which is dropped here because ReadBTTrainerParty (5C:$42B7)
--     overwrites it with the species name before the battle starts.  21 is the
--     `Random & $1F` rejected at >= $15 in LoadRandomBattleTowerMon, and 1239
--     (= 21 * 59) is the stride that routine adds per level group.
--   BTTrainerClassGenders (47:$72F0)  one byte per trainer class - 1; nonzero
--     picks the female line pool in BattleTowerText (47:$4000).
--   BTMaleTrainerTexts / BTFemaleTrainerTexts  three slots -- before the
--     battle, on the opponent winning, on the opponent losing -- each a table
--     of 25 (male) or 15 (female) lines.  BattleTowerText rolls the line ONCE,
--     for slot 1, and reuses that index for the other two, so an opponent's
--     three lines belong to one personality.
--
-- Stats are not stored: the DVs and stat exp are, and Stats.calc reproduces
-- the ROM's own stat block from them exactly (checked against the precomputed
-- stats sitting at offsets 34..47 of each record).
function RomExtractorGen2:gen2BattleTower()
  local trainersSym = self:symbol("BattleTowerTrainers")
  local monsSym = self:symbol("BattleTowerMons")
  if not (trainersSym and monsSym and self.rom) then return nil end
  local moveOrder = (self:constants() or {}).moveOrder or {}
  local byGroup = (self:gen2Trainers() or {}).byGroup or {}
  local out = {
    -- LoadOpponentTrainerAndPokemon keeps 7 beaten-trainer slots in SRAM, and
    -- BattleTowerBattleRoom's script ends the challenge on
    -- wNrOfBeatenBattleTowerTrainers == 7.
    battles = 7,
    monsPerGroup = 21,
    -- BattleTowerRoomMenu_PlacePickLevelMenu offers Strings_Ll0ToL40 (4 rows
    -- plus CANCEL) until wStatusFlags bit 6 -- the Hall of Fame bit -- is set,
    -- and Strings_L10ToL100 (10 rows plus CANCEL) after it.
    levelGroupsBeforeHallOfFame = 4,
    -- BattleTower_UbersCheck returns early once the chosen group is >= 7, so
    -- MEWTWO, MEW, LUGIA, HO-OH and CELEBI are legal only from L70 up.
    ubers = { "SPECIES_150", "SPECIES_151",
              "SPECIES_249", "SPECIES_250", "SPECIES_251" },
    uberMinLevel = 70,
    -- BattleTower_RandomlyChooseReward: `Random & 7`, 6 and 7 folded back to
    -- 0 and 1, + $1A, rerolled when it lands on $1E.  Five vitamins, five at
    -- a time (`giveitem ITEM_FROM_MEM, 5`).
    rewards = {}, rewardReject = "ITEM_030", rewardCount = 5,
    -- BattleTower_GiveReward answers $12 when the bag cannot take them.
    rewardBagFull = 18,
    trainers = {}, groups = {}, texts = {},
  }
  local ok = pcall(function()
    for index = 0, 5 do
      out.rewards[index + 1] = string.format("ITEM_%03d", 0x1A + index)
    end
    local gendersSym = self:symbol("BTTrainerClassGenders")
    -- BTTrainerClassSprites (5C:$4B90), also indexed by class - 1: the
    -- overworld sheet LoadOpponentTrainerAndPokemonWithOTSprite puts on the
    -- battle room's opponent object before it walks in.
    local spritesSym = self:symbol("BTTrainerClassSprites")
    local overworld = self:gen2OverworldSprites() or {}
    for index = 0, 69 do
      local at = trainersSym.address + index * 11
      local raw = self.rom:bytes(trainersSym.bank, at, 10)
      local class = self.rom:byte(trainersSym.bank, at + 10)
      local female, sprite = false, nil
      if class > 0 then
        if gendersSym then
          female = self.rom:byte(gendersSym.bank,
                                 gendersSym.address + class - 1) ~= 0
        end
        if spritesSym then
          local id = self.rom:byte(spritesSym.bank,
                                   spritesSym.address + class - 1)
          sprite = (overworld[id] or {}).id
        end
      end
      out.trainers[index + 1] = {
        name = gen2DecodeString(raw, 10) or string.format("TRAINER_%02d", index),
        class = class,
        classKey = byGroup[class],
        sprite = sprite,
        female = female or nil,
      }
    end
    -- Level groups run until a record stops looking like one.  Crystal has
    -- ten, L10 through L100, and the tenth ends exactly where _GiveOddEgg
    -- begins.
    for group = 1, 16 do
      local base = monsSym.address + (group - 1) * 1239
      if base + 1239 > 0x8000 then break end
      local party, level, sane = {}, nil, true
      for slot = 0, 20 do
        local record = self.rom:bytes(monsSym.bank, base + slot * 59, 48)
        local function word(at) return record[at] * 256 + record[at + 1] end
        local species, item, monLevel = record[1], record[2], record[32]
        if species < 1 or species > 251 or monLevel < 1 or monLevel > 100
           or (level and monLevel ~= level) then
          sane = false
          break
        end
        level = monLevel
        local moves = {}
        for i = 0, 3 do
          local move = record[3 + i]
          if move > 0 then
            moves[#moves + 1] = moveOrder[move] or string.format("MOVE_%03d", move)
          end
        end
        party[slot + 1] = {
          species = string.format("SPECIES_%03d", species),
          level = monLevel,
          item = item > 0 and string.format("ITEM_%03d", item) or nil,
          -- the raw held-item byte, because LoadRandomBattleTowerMon rejects a
          -- candidate whose item byte matches one already drawn -- including
          -- two mons that both hold nothing
          itemByte = item,
          moves = #moves > 0 and moves or nil,
          dvs = {
            attack = math.floor(record[22] / 16),
            defense = record[22] % 16,
            speed = math.floor(record[23] / 16),
            special = record[23] % 16,
          },
          statExp = {
            hp = word(12), attack = word(14), defense = word(16),
            speed = word(18), special = word(20),
          },
          -- The party_struct's own stat block.  These are used verbatim rather
          -- than recomputed: CalcMonStats floors the stat-exp square root and
          -- Stats.calc ceilings it, which disagrees by one point on 117 of the
          -- 210 records, and an opponent that is one point off is not the
          -- opponent the cartridge sends out.
          --
          -- The block runs `status, unused, curHP, maxHP, atk, def, spd, satk,
          -- sdef` from byte 32 of the party_struct, so maxHP is 0-based offset
          -- 36 -- record[37] here, because self.rom:bytes hands the record back
          -- ONE-BASED.  Reading it as record[36] took the low half of curHP and
          -- the high half of maxHP, and every stat after it was skewed the same
          -- way: the first L10 opponent came out with 10496 HP and 6400
          -- defense instead of 41 and 24, so nothing the player did to a
          -- Battle Tower opponent could dent it.
          stats = {
            hp = word(37), attack = word(39), defense = word(41),
            speed = word(43), spatk = word(45), spdef = word(47),
            special = word(45),
          },
          happiness = record[28],
        }
      end
      if not (sane and party[21]) then break end
      -- the HP DV is the low bits of the other four, the same derivation
      -- Stats.randomDVs uses
      for _, slot in ipairs(party) do
        local dvs = slot.dvs
        dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4
               + (dvs.speed % 2) * 2 + (dvs.special % 2)
      end
      out.groups[group] = { level = level, mons = party }
    end
    -- Menu_ChallengeExplanationCancel (5F:$5224) is the receptionist's three
    -- rows; MenuData is a flags byte, a row count, then that many $50
    -- terminated labels.
    local menuSym = self:symbol("MenuData_ChallengeExplanationCancel")
    if menuSym then
      out.menu = {}
      local at = menuSym.address + 2
      for index = 1, self.rom:byte(menuSym.bank, menuSym.address + 1) do
        out.menu[index] =
          gen2DecodeString(self.rom:bytes(menuSym.bank, at, 16), 16) or ""
        while at < 0x7FFF and self.rom:byte(menuSym.bank, at) ~= 0x50 do
          at = at + 1
        end
        at = at + 1
      end
    end
    -- Strings_L10ToL100: eleven 8-byte rows, L.10 through L.100 and then
    -- CANCEL.  Only the labels come from here; how many of them are offered is
    -- the Hall of Fame test above.
    local levelSym = self:symbol("Strings_L10ToL100")
    if levelSym then
      out.levelLabels = {}
      for index = 1, 10 do
        out.levelLabels[index] = gen2DecodeString(
          self.rom:bytes(levelSym.bank,
                         levelSym.address + (index - 1) * 8, 8), 8) or ""
      end
      out.cancelLabel = gen2DecodeString(
        self.rom:bytes(levelSym.bank, levelSym.address + 80, 8), 8)
    end
    local charmap = self:readSourceTable("charmap")
    -- _CheckForBattleTowerRules (22:$7201) runs four party checks in order and
    -- prints the header first, then a line per failing rule, then
    -- BattleTower_PleaseReturnWhenReady.  The three middle lines splice
    -- wStringBuffer1, which the routine fills with "3" before it starts.
    local rulesSym = self:symbol("_CheckForBattleTowerRules.TextPointers")
    if rulesSym then
      out.ruleTexts = {}
      for index = 0, 4 do
        local at = self.rom:word(rulesSym.bank, rulesSym.address + index * 2)
        local text = self:decodeGen2TextAt(rulesSym.bank, at, charmap, true)
        out.ruleTexts[index + 1] = type(text) == "string" and text or ""
      end
    end
    local readySym = self:symbol(
      "BattleTower_PleaseReturnWhenReady.BattleTowerReturnWhenReadyText")
    if readySym then
      out.notReadyText = self:decodeGen2TextAt(
        readySym.bank, readySym.address, charmap, true)
    end
    for _, row in ipairs({ { "male", "BTMaleTrainerTexts", 25 },
                           { "female", "BTFemaleTrainerTexts", 15 } }) do
      local sym = self:symbol(row[2])
      if sym then
        local slots = {}
        for slot = 0, 2 do
          local pointers = self.rom:word(sym.bank, sym.address + slot * 2)
          local lines = {}
          for line = 0, row[3] - 1 do
            local at = self.rom:word(sym.bank, pointers + line * 2)
            local text = self:decodeGen2TextAt(sym.bank, at, charmap, true)
            lines[line + 1] = type(text) == "string" and text or ""
          end
          slots[slot + 1] = lines
        end
        out.texts[row[1]] = slots
      end
    end
  end)
  if not ok or not (out.trainers[1] and out.groups[1]) then return nil end
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
      -- 5x5, DECLARED, not guessed from the blob length.  Crystal appends a
      -- pic's animation frames to the same compressed stream, so EggPic
      -- decompresses to 47 tiles -- 25 of pic and 22 of animation -- and the
      -- "the tile count must be a perfect square" rule that the species pics
      -- already abandoned for exactly this reason threw here too.  That threw
      -- inside this pcall, field.egg came out with no `pic` key at all, and an
      -- EGG's stats page drew nothing where the egg belongs.  UnusedEggPic is
      -- the same art without the frames and is exactly 25 tiles, which is what
      -- pins the geometry down.
      local side = 5
      if side * side * 16 > #pixels then error("short egg pic") end
      local base = {}
      for i = 1, side * side * 16 do base[i] = pixels[i] end
      -- ...and baked in the egg's own palette (PokemonPalettes row 252, read
      -- above), because every screen that shows this pic marks it trueColor --
      -- "already coloured, renderer keep out".
      local pal = {}
      for shade = 0, 3 do
        local c = colors[shade + 1]
        pal[shade] = { c[1] / 255, c[2] / 255, c[3] / 255 }
      end
      self:saveImage(ImageWriter.matteColor0(ImageWriter.decode2bppColor(
        colMajorToRowMajor(base, side, side), side * 8, side * 8, pal, false)),
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

-- MapObjectPals (02:$78AE): eight OBJ palettes, four BGR555 colours each.
-- Memoised and shared -- the overworld sprite sheets bake one of these in,
-- and so does the heal machine overlay, which runs in an earlier stage.
-- MapObjectPals: the CGB OBJ palettes overworld sprites wear.  Symbol-resolved
-- for the same reason TilesetBGPalette is -- it sits at 02:$78AE in Gold and
-- 02:$7469 in Crystal, and the hardcoded Gold address is why Crystal's people
-- came out miscoloured.
function RomExtractorGen2:gen2ObjPalettes()
  if self._gen2ObjPals then return self._gen2ObjPals end
  local out = {}   -- 0-based: out[i] = 4-colour palette
  self._gen2ObjPals = out
  if not self.rom then return out end
  local sym = self:symbol("MapObjectPals")
  local bank = sym and sym.bank or GEN2_PAL.bank
  local addr = sym and sym.address or GEN2_PAL.objAddrFallback
  local pals = GEN2_PAL.read(self.rom, bank, addr, 8)
  if not pals then return out end
  for p = 0, 7 do out[p] = pals[p + 1] end
  return out
end

-- The flat TilesetBGPalette list (1-based here; index 1 is the ROM's palette
-- 0).  Its length is the gap to MapObjectPals, which is exactly 336 bytes /
-- 42 palettes in both Gold and Crystal -- measured rather than assumed, so a
-- ROM that sizes it differently still reads whole palettes.
function RomExtractorGen2:gen2BgPalettes()
  if self._gen2BgPals ~= nil then return self._gen2BgPals or nil end
  self._gen2BgPals = false
  if not self.rom then return nil end
  local sym = self:symbol("TilesetBGPalette")
  local bank = sym and sym.bank or GEN2_PAL.bank
  local addr = sym and sym.address or GEN2_PAL.bgAddrFallback
  local count = GEN2_PAL.bgCountFallback
  local nextSym = self:symbol("MapObjectPals")
  if sym and nextSym and nextSym.bank == bank and nextSym.address > addr then
    count = math.floor((nextSym.address - addr) / 8)
  end
  local pals = GEN2_PAL.read(self.rom, bank, addr, count)
  if not pals then return nil end
  self._gen2BgPals = pals
  return pals
end

-- EnvironmentColorsPointers -> env (0..7) -> { MORN = {8 palettes}, DAY = ...,
-- NITE = ..., DARK = ... }, each palette already resolved to RGB.
function RomExtractorGen2:gen2EnvPalettes()
  if self._gen2EnvPals ~= nil then return self._gen2EnvPals or nil end
  self._gen2EnvPals = false
  local bgPals = self:gen2BgPalettes()
  local ptrSym = self:symbol("EnvironmentColorsPointers")
  if not (bgPals and ptrSym and self.rom) then return nil end
  local out = {}
  local rowCache = {}
  local ok = pcall(function()
    for env = 0, 7 do
      local tableAddr = self.rom:word(ptrSym.bank, ptrSym.address + env * 2)
      local rows = rowCache[tableAddr]
      if not rows then
        -- 4 times of day x 8 palettes, one index byte each
        local raw = self.rom:bytes(ptrSym.bank, tableAddr,
                                   #GEN2_PAL.todRows * GEN2_PAL.perRow)
        rows = {}
        for t, name in ipairs(GEN2_PAL.todRows) do
          local row = {}
          for p = 1, GEN2_PAL.perRow do
            local index = raw[(t - 1) * GEN2_PAL.perRow + p]
            row[p] = bgPals[(index or 0) + 1] or bgPals[1]
          end
          rows[name] = row
        end
        rowCache[tableAddr] = rows
      end
      out[env] = rows
    end
  end)
  if not ok then return nil end
  self._gen2EnvPals = out
  return out
end

-- MapScenes (25:$4000 in Gold, 13:$501E in Crystal) is `db group, db number,
-- dw sceneVar` per map that has scene scripts -- 59 entries in Gold, 79 in
-- Crystal -- and each sceneVar is one SRAM byte holding that map's current
-- scene id.
--
-- Nothing was reading it.  A battery save carries these bytes, but the
-- importer had no offsets for them, so every imported game came up with every
-- scene at 0 and the one-time cutscenes re-armed: Elm's errand fires again and
-- New Bark Town will not let you leave, and the same shape of thing happens in
-- Violet City.  Event flags alone do not cover it -- scenes are a separate
-- store, and the port keeps them in save.g2Scenes keyed by map registry id.
function RomExtractorGen2:gen2MapSceneVars()
  if self._gen2SceneVars then return self._gen2SceneVars end
  local out = {}
  self._gen2SceneVars = out
  local sym = self:symbol("MapScenes")
  local index = self:gen2MapIndex()
  if not (sym and index and self.rom) then return out end
  pcall(function()
    for entry = 0, 127 do
      local offset = sym.address + entry * 4
      if offset + 3 >= 0x8000 then break end
      local group = self.rom:byte(sym.bank, offset)
      if group == 0xFF then break end
      local number = self.rom:byte(sym.bank, offset + 1)
      local address = self.rom:word(sym.bank, offset + 2)
      local header = index[group * 256 + number]
      if header and header.label then
        out[header.label] = address
      end
    end
  end)
  return out
end

-- SpecialsPointers index -> the pret label of the routine it points at, so a
-- `special` can be lowered by NAME instead of by a number that means different
-- things in the two games.  Gold has 129 entries and Crystal 207, and they
-- agree only up to $2E: Crystal inserts BattleTowerFade at $2F and everything
-- after it shifts by one.
function RomExtractorGen2:gen2SpecialNames()
  if self._gen2SpecialNames then return self._gen2SpecialNames end
  local out = {}
  self._gen2SpecialNames = out
  local sym = self:symbol("SpecialsPointers")
  if not (sym and self.rom and self.symbols) then return out end
  -- (bank, address) -> label, so a pointer can be named without scanning
  local byLocation = {}
  for name, location in pairs(self.symbols) do
    if type(name) == "string" and type(location) == "table" then
      local key = tonumber(location[1]) * 0x10000 + tonumber(location[2])
      local prev = byLocation[key]
      -- several labels can share an address; prefer the shortest real name
      if not prev or #name < #prev then byLocation[key] = name end
    end
  end
  pcall(function()
    for index = 0, GEN2_SPECIAL_TABLE_MAX do
      local offset = sym.address + index * 3
      if offset + 2 >= 0x8000 then break end
      local bank = self.rom:byte(sym.bank, offset)
      local address = self.rom:word(sym.bank, offset + 1)
      local name = byLocation[bank * 0x10000 + address]
      if name then out[index] = name end
    end
  end)
  return out
end

-- Which ENVIRONMENT_* a tileset is actually used under, taken from the map
-- headers rather than from the tileset's NAME.  A tileset used by maps of
-- several environments takes the commonest; ties break toward the lower env so
-- the answer does not depend on table iteration order.
function RomExtractorGen2:gen2TilesetEnvironments()
  if self._gen2TilesetEnv then return self._gen2TilesetEnv end
  local out = {}
  self._gen2TilesetEnv = out
  local index = self:gen2MapIndex()
  if not index then return out end
  -- id -> "TilesetJohto" the same way every other caller resolves it; the
  -- scaffold's tilesetOrder is deliberately empty (it suppressed ROM
  -- inference), so indexing that would have found nothing.
  local names = self:gen2TilesetNames()
  local tally = {}
  for _, entry in pairs(index) do
    local name = names[entry.tileset or -1]
    local env = entry.environment
    if name and type(env) == "number" and env >= 0 and env <= 7 then
      tally[name] = tally[name] or {}
      tally[name][env] = (tally[name][env] or 0) + 1
    end
  end
  for name, counts in pairs(tally) do
    local best, bestCount = nil, -1
    for env = 0, 7 do
      local n = counts[env] or 0
      if n > bestCount then best, bestCount = env, n end
    end
    out[name] = best
  end
  return out
end

-- HealMachineAnim.PC_ElmsLab_OAM (04:$67B5), read straight out of the ROM:
-- two $7C monitor tiles then three rows of two $7D balls, the right column
-- x-flipped.  Raw shadow-OAM bytes, so screen = x - 8 / y - 16.
--
-- Gen1's PokeCenterOAMData puts the balls at x 40/48; Gen2 puts them at
-- 24/32, which is why they sat a full 16px right of the machine.  Every row
-- carries attribute $16/$36 -- CGB OBJ palette 6 -- so the overlay is
-- colourable rather than the DMG greys it was drawing.
local GEN2_HEAL_OAM_PALETTE = 6
local GEN2_HEAL_MACHINE_LAYOUT = {
  monitor = { { 26, 16 }, { 30, 16 } },
  balls = {
    { 24, 22 }, { 32, 22, true },
    { 24, 27 }, { 32, 27, true },
    { 24, 32 }, { 32, 32, true },
  },
}

function RomExtractorGen2:extractField()
  self:beginStage("Gen2 field")
  local src = copy(self.manifest.field or {})
  if type(src.presetNames) ~= "table" then
    src.presetNames = {
      player = { "GOLD", "KRIS", "CHRIS" },
      rival = { "SILVER", "RIVAL", "???" },
    }
  end
  -- Where NEW GAME drops the player.  Gold/Crystal both start in the player's
  -- bedroom, so that was a constant in Data.lua -- but it is cart content, and
  -- Prism starts somewhere else entirely (INTRO_OUTSIDE).  With the constant
  -- the overworld asks the map registry for PLAYERS_HOUSE2_F, which a Prism
  -- import has never heard of, and NEW GAME dies before the first frame.
  --
  -- SpawnPoints is `db group, number, x, y` per entry and SPAWN_HOME is entry
  -- 0 (engine/intro_menu.asm sets wDefaultSpawnpoint to it), so the real start
  -- is a four-byte read.  Written only when it resolves to a map this import
  -- actually has, so a ROM without the symbol keeps the old behaviour.
  src.boot = src.boot or {}
  local spawn = self:symbol("SpawnPoints")
  if spawn and self.rom and not src.boot.startMap then
    pcall(function()
      local row = self.rom:bytes(spawn.bank, spawn.address, 4)
      local index = self:gen2MapIndex()
      local entry = index[row[1] * 256 + row[2]]
      local maps = self:readSourceTable("maps")
      local mapId
      for id, def in pairs(maps) do
        if type(def) == "table" and entry then
          local label = (type(def.label) == "string" and def.label)
            or (type(def.source) == "string"
                and def.source:match("^SYMBOL:(.+)_MapAttributes$"))
          if label == entry.label then mapId = id; break end
        end
      end
      if mapId then
        src.boot.startMap = mapId
        src.boot.startX, src.boot.startY = row[3], row[4]
        src.boot.startFacing = src.boot.startFacing or "down"
        Logger.info("gen2 field: new game spawns at %s (%d,%d)",
                    tostring(mapId), row[3], row[4])
      end
    end)
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
    -- A SILENT pcall here cost a whole afternoon: Prism's title came
    -- back nil, field.title was simply absent, and the launcher fell
    -- back to the shipped logo with nothing anywhere saying why.  The
    -- fallback is still the right behaviour -- a title screen is not
    -- worth failing an import over -- but it should say so out loud.
    local okTitle, title = pcall(self.extractGen2TitleArt, self)
    if okTitle and title then
      src.title = title
    elseif not okTitle then
      Logger.warn("title screen: %s (falling back to the shipped logo)",
                  tostring(title))
    else
      Logger.warn("title screen: no art ripped for this ROM"
                  .. " (falling back to the shipped logo)")
    end
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
    src.gen2BugContest = self:gen2BugContest() or src.gen2BugContest
    src.gen2Trades = self:gen2NpcTrades() or src.gen2Trades
    src.gen2UnownWalls = self:gen2UnownWalls() or src.gen2UnownWalls
    -- Crystal only; Gold and Silver have no OddEggs symbol at all
    src.gen2OddEggs = self:gen2OddEggs() or src.gen2OddEggs
    src.gen2MomBank = self:gen2MomBank() or src.gen2MomBank
    src.gen2TileAnim = self:gen2TowerPillarAnim() or src.gen2TileAnim
    -- Crystal only; nil on Gold and Silver, which have no Battle Tower
    src.gen2BattleTower = self:gen2BattleTower() or src.gen2BattleTower
    src.gen2Slots = self:gen2Slots() or src.gen2Slots
    src.gen2CardFlip = self:gen2CardFlip() or src.gen2CardFlip
    src.egg = self:gen2Egg() or src.egg
    src.pokegear = self:gen2Pokegear() or src.pokegear
    -- Crystal's boy/girl asset sets; nil on Gold and Silver, which have only
    -- Chris.  Kris's overworld sheets are registered later, by the sprite
    -- pass, but the record only names their ids so order does not matter.
    src.playerForms = self:extractGen2PlayerForms() or src.playerForms
    src.playerCustomization = self:gen2PlayerCustomization()
      or src.playerCustomization
    -- MapScenes -> the per-map scene byte each one lives in.  Keyed by the
    -- map registry id the script VM keys save.g2Scenes with, so the battery
    -- save converter can read them straight across.  Without this every
    -- imported save came up with every scene at 0 and the one-time cutscenes
    -- re-armed -- Elm's errand fires again and New Bark Town will not let you
    -- leave.
    do
      local sceneVars = self:gen2MapSceneVars()
      if next(sceneVars) then
        local byLabel = {}
        for mapId, def in pairs(self:readSourceTable("maps") or {}) do
          if type(def) == "table" and type(def.label) == "string" then
            byLabel[def.label] = mapId
          end
        end
        local scenes = {}
        for label, address in pairs(sceneVars) do
          if byLabel[label] then scenes[byLabel[label]] = address end
        end
        if next(scenes) then src.mapSceneVars = scenes end
      end
    end
    -- The Pokemon Center heal machine overlay (the monitor tile and the ball
    -- tile OverworldController's fxHeal blits).  `special HealMachineAnim`
    -- always ran and the jingle always played, but src.overworldFx came in
    -- from the Gen1 manifest pointing at assets/generated/fx/heal_machine.png
    -- -- a file only RomExtractor (Gen1) ever writes.  The load pcall-failed,
    -- healMachineImg latched to false, and the nurse healed with no visible
    -- animation at all.  HealMachineAnim.HealMachineGFX is 2 raw 2bpp tiles
    -- stacked vertically, which is exactly the 8x16 sheet fxHeal quads up.
    src.overworldFx = src.overworldFx or {}
    local healLayout = copy(GEN2_HEAL_MACHINE_LAYOUT)
    -- The machine does NOT wear a MapObjectPals entry.  HealMachineAnim.
    -- LoadPalettes (04:$6434) copies its own four colours over OBJ palette 6
    -- on a CGB before the animation runs, which is why its OAM rows all name
    -- palette 6 -- so reading MapObjectPals[6] handed back PAL_OW_TREE and the
    -- Poke Balls came out green (and, unapplied, grey).  Its own row is white,
    -- light orange, red, black.
    local healPal = self:symbol("HealMachineAnim.palettes")
    if healPal then
      local pals = GEN2_PAL.read(self.rom, healPal.bank, healPal.address, 1)
      healLayout.gen2ObjPal = pals and pals[1] or nil
    end
    healLayout.gen2ObjPal = healLayout.gen2ObjPal
      or self:gen2ObjPalettes()[GEN2_HEAL_OAM_PALETTE]
    src.overworldFx.healMachine =
      self:gen2RawSheet("HealMachineAnim.HealMachineGFX", 1, 2,
        "fx/heal_machine.png")
      or self:gen2RawSheet("HealMachineGFX", 1, 2, "fx/heal_machine.png")
      -- Never leave the inherited Gen1 path in place: it names a png this
      -- importer does not write, and a dangling entry is worse than none.
      or nil
    if src.overworldFx.healMachine then
      for k, v in pairs(healLayout) do src.overworldFx.healMachine[k] = v end
    end
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
  -- The Gen2 rod tables (see gen2Fishing above).  Written under their own
  -- keys so FieldDefaults' Gen1 `fishing` table stays exactly as it is for a
  -- Red/Blue/Yellow import; OverworldState:goFishing prefers these when the
  -- import produced them.
  pcall(function()
    local groups, times = self:gen2Fishing()
    if groups then
      src.fishGroups = groups
      src.timeFishGroups = times
    end
  end)
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
-- (DoBattleAnimFrame's jumptable is resolved from the symbol; it used to be
-- hardcoded to Gold's $4F1D..$4FBD, which is not where Crystal's is.)
GEN2_ANIM.OAM_BYTES = 4
GEN2_ANIM.GFX_BYTES = 4
GEN2_ANIM.GFX_COUNT = 42       -- AnimObjGFX $7C3B..$7CE3
-- BattleObjectPals ([2,$5C09], 48 bytes) is six palettes -- gray, yellow,
-- red, green, blue, brown -- that CGBCopyBattleObjectPals loads into OBJ
-- slots 2..7, so an object's palette field is the table index plus two.
GEN2_ANIM.OBJ_PALETTES = 6
GEN2_ANIM.SHEET_COLS = 16
GEN2_ANIM.MAX_STEPS = 512
-- DoBattleAnimFrame's jumptable, in table order.
--
-- Only pokegold's symbols file names these routines; Crystal's has no
-- BattleAnimFunction_* symbol at all, so on Crystal there was nothing to name
-- them WITH -- and the table was being read at Gold's hardcoded $4F1D anyway,
-- while Crystal's jumptable is at $4FCE.  The result was an empty function
-- map, every animation object fell through Gen2AnimPlayer's MOTION lookup to
-- "Null", and not one of them moved: objects appeared where the script spawned
-- them and stayed there for the whole animation.
--
-- The order is the same in both games, which is what makes listing them here
-- safe: 80 entries either way, every pointer relocated by one of two
-- constants ($B1 and $BB), and 75 of the 80 routines byte-identical once those
-- relocations are undone.  Gold still prefers its own symbols; this is the
-- fallback that gives Crystal the same names.
GEN2_ANIM.FN_NAMES = {
  "Null", "MoveFromUserToTarget", "MoveFromUserToTargetAndDisappear",
  "MoveInCircle", "MoveWaveToTarget", "ThrowFromUserToTarget",
  "ThrowFromUserToTargetAndDisappear", "Drop",
  "MoveFromUserToTargetSpinAround", "Shake", "FireBlast", "RazorLeaf",
  "Bubble", "Surf", "Sing", "WaterGun", "Ember", "Powder", "PokeBall",
  "PokeBallBlocked", "Recover", "ThunderWave", "Clamp_Encore", "Bite",
  "SolarBeam", "Gust", "RazorWind", "Kick", "Absorb", "Egg", "MoveUp",
  "Wrap", "LeechSeed", "Sound", "ConfuseRay", "Dizzy", "Amnesia",
  "FloatUp", "Dig", "String", "Paralyzed", "SpiralDescent", "PoisonGas",
  "Horn", "Needle", "PetalDance", "ThiefPayday", "AbsorbCircle",
  "Bonemerang", "Shiny", "SkyAttack", "GrowthSwordsDance",
  "SmokeFlameWheel", "PresentSmokescreen", "StrengthSeismicToss",
  "SpeedLine", "Sludge", "MetronomeHand", "MetronomeSparkleSketch",
  "Agility", "SacredFire", "SafeguardProtect", "LockOnMindReader",
  "Spikes", "HealBellNotes", "BatonPass", "Conversion", "EncoreBellyDrum",
  "SwaggerMorningSun", "HiddenPower", "Curse", "PerishSong", "RapidSpin",
  "BetaPursuit", "RainSandstorm", "AnimObjB0", "PsychUp", "AncientPower",
  "RockSmash", "Cotton",
}

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
  -- Resolved from the routine that dispatches through it, never hardcoded:
  -- the table sits sixteen bytes past DoBattleAnimFrame's own label (the
  -- `ld hl, .Jumptable` is its sixth instruction), which is $4F1D in Gold and
  -- $4FCE in Crystal.  Reading Crystal at Gold's address produced nothing.
  local sym = self:symbol("DoBattleAnimFrame")
  if not (sym and self.rom) then return out end
  local jump = self:symbol("DoBattleAnimFrame.Jumptable")
  local address = (jump and jump.address) or (sym.address + 0x10)
  local byAddress = {}
  for name, entry in pairs(self.manifest.symbols or {}) do
    local prefix = name:match("^BattleAnimFunction_([%w_]+)$")
    if prefix and entry[1] == sym.bank then byAddress[entry[2]] = prefix end
  end
  -- the first pointer bounds the table, the way every other dw table here is
  -- bounded; the baked list's length is the fallback
  local ok, first = pcall(self.rom.word, self.rom, sym.bank, address)
  local count = ok and math.floor((first - address) / 2) or 0
  if count < 1 or count > 256 then count = #GEN2_ANIM.FN_NAMES end
  for id = 0, count - 1 do
    pcall(function()
      local target = self.rom:word(sym.bank, address + id * 2)
      out[id] = byAddress[target] or GEN2_ANIM.FN_NAMES[id + 1]
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
  -- Prism has no FontExtra at all: its gfx/font.asm is Font (font.1bpp),
  -- FontBattleExtra (battle_extra.2bpp) and Frames, and _LoadFontsBattleExtra
  -- copies FontBattleExtra straight to `vBGTiles tile $60` -- the same slots
  -- Crystal fills from FontExtra.  Bailing out on the missing symbol wrote
  -- NEITHER sheet, so Prism had no font.png either and every letter on screen
  -- came from the placeholder.
  local extraSym = self:symbol("FontExtra") or self:symbol("FontBattleExtra")
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
  -- Resolved once for the whole loop: both walk the ROM and both are the same
  -- answer for every tileset.
  local envPalettes = self:gen2EnvPalettes()
  local tilesetEnvironments = self:gen2TilesetEnvironments()
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
      -- Prism stores the metatile and collision tables COMPRESSED --
      -- `Tileset03Meta:: INCBIN "tilesets/03_metatiles.bin.lz"` -- and
      -- decompresses them into wDecompressedMetatiles at map load.  Gold and
      -- Crystal store both raw.  Read raw, the LZ3 stream itself becomes the
      -- block table: every block of every map gets nonsense tile ids, the
      -- collision table is nonsense too, and the Coll-minus-Meta gap measures
      -- the COMPRESSED span, so the block count comes out short as well
      -- (Tileset03: 110 blocks read, 177 real).  Prism's first map indexes
      -- blocks past that short table, which is where a new game died.
      --
      -- The METATILE blob alone decides the block count.  Collision does not
      -- get a vote: Prism's own tilesets/NN_collision.bin files disagree with
      -- their metatile files on nineteen of the fifty-seven tilesets -- some
      -- are padded up to a round 64 or 256 entries (09, 11, 13, 22, 40), one
      -- is three entries SHORT of its metatile table (37) -- so requiring the
      -- two to agree threw away nineteen correct decompressions and left
      -- those tilesets on the raw path.  That is what still left 99 maps
      -- indexing past their tileset after the first pass at this.
      --
      -- Guarded instead by: the manifest flag (so Gold and Crystal, which
      -- store both blobs raw, never enter this branch at all), the 16-byte
      -- granularity a metatile table must have, and the result being LONGER
      -- than the span it was read from -- which is what "compressed" means.
      local blocksRaw, preCollRaw, preAttrRaw
      if self:layout("tilesetCompressed", 0) ~= 0 then
        local rawSpan = (coll.bank == meta.bank and coll.address > meta.address)
          and (coll.address - meta.address) or nil
        local okMeta, metaOut = pcall(function() return self:gen2Lz(gfxId .. "Meta") end)
        if okMeta and type(metaOut) == "table" and #metaOut > 0 and #metaOut % 16 == 0
           and (not rawSpan or #metaOut > rawSpan) then
          blocksRaw = metaOut
          blockCount = math.floor(#metaOut / 16)
          local okColl, collOut = pcall(function() return self:gen2Lz(gfxId .. "Coll") end)
          if okColl and type(collOut) == "table" and #collOut >= 4 then
            preCollRaw = collOut
          end
          -- <Tileset>Attr is Prism's answer to Crystal's <Tileset>PalMap, and
          -- a better one: one CGB attribute byte per metatile CELL rather than
          -- one nibble per tile id, so it carries the palette (bits 0-2) and
          -- the VRAM bank (bit 3) for each of a block's 16 positions.  Prism
          -- ships no PalMap at all, which is why every one of its 71 tilesets
          -- came out with no palette data whatsoever.
          local okAttr, attrOut = pcall(function() return self:gen2Lz(gfxId .. "Attr") end)
          if okAttr and type(attrOut) == "table" and #attrOut == #metaOut then
            preAttrRaw = attrOut
          end
        else
          Logger.warn("gen2 tileset %s: metatiles did not decompress "
            .. "(%s bytes over a %s byte span), falling back to a raw read",
            tostring(id), tostring(type(metaOut) == "table" and #metaOut),
            tostring(rawSpan))
        end
      end
      if not blockCount and coll.bank == meta.bank and coll.address > meta.address then
        blockCount = math.floor((coll.address - meta.address) / 16)
      end
      blockCount = blockCount or 0x80
      blocksRaw = blocksRaw or self.rom:bytes(meta.bank, meta.address, blockCount * 16)
      -- Flatten the two VRAM banks into one 0..191 range here, so every reader
      -- downstream -- the atlas bake, the animated-tile overdraw, mods -- can
      -- treat a metatile byte as a plain index into the extracted sheet.
      -- See GEN2_PAL.tileIndex.
      local tileCount = (width / 8) * (height / 8)
      local blocks = {}
      -- Prism splits its sheet the same way, at a different offset and by a
      -- different route.  LoadTileset (home/map.asm) zero-fills scratch to
      -- `2 * $80` tiles, decompresses, copies `$7f tiles` to vBGTiles in VRAM
      -- bank 0, then copies from `scratch + $80 tiles` to the SAME vBGTiles in
      -- bank 1.  So the split is at 128, not Crystal's 96, and a metatile byte
      -- is the plain tile number with the bank living in the ATTRIBUTE byte --
      -- where Crystal packs both into the metatile byte itself ($80+ = bank 1).
      --
      -- Without this, every bank-1 tile drew as its bank-0 twin: Tileset45 has
      -- 113 of its 128 tile numbers used in both banks, so more than half that
      -- tileset was rendering the wrong art AND the wrong palette.
      local attrSplit = preAttrRaw and 128 or nil
      local palMapFromAttr = preAttrRaw and {} or nil
      for offset = 1, #blocksRaw, 16 do
        local block = {}
        for pos = offset, offset + 15 do
          local index
          if attrSplit then
            local attr = preAttrRaw[pos] or 0
            local bank = math.floor(attr / 8) % 2
            index = bank * attrSplit + (blocksRaw[pos] or 0)
            -- a sheet shorter than the split still has to land somewhere real
            if index >= tileCount then index = blocksRaw[pos] or 0 end
            if index >= tileCount then index = 0 end
            palMapFromAttr[index + 1] = attr % 8
          else
            index = GEN2_PAL.tileIndex(blocksRaw[pos], tileCount)
          end
          block[#block + 1] = index
        end
        blocks[#blocks + 1] = block
      end
      -- Dense, not sparse.  Only tiles a block actually references pick up an
      -- attribute, so the table above has holes -- and `#` on a table with
      -- holes is undefined in Lua, which matters because TileRenderer gates
      -- the whole GBC atlas on `#tileset.palMap > 0`.  A hole is palette 0,
      -- the same answer gen2TileColors' own `or 0` gives.
      if palMapFromAttr then
        for index = 1, tileCount do
          palMapFromAttr[index] = palMapFromAttr[index] or 0
        end
      end

      -- Gen2 collision is per 16x16 cell, not per 8x8 tile: <Tileset>Coll
      -- holds 4 classes per block in NW/NE/SW/SE order, and
      -- CollisionPermissionTable says which classes are land or water
      -- (GetCoordTileCollision / GetTilePermission).
      local classes = self:gen2CollisionClasses()
      local collision = {}
      local ok, collRaw = pcall(function()
        if preCollRaw then return preCollRaw end
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
        -- Set only where <Tileset>Attr supplied it (Prism).  The PalMap
        -- reader below sees this and leaves it alone rather than looking for
        -- a symbol that does not exist on this cartridge.
        palMap = palMapFromAttr,
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
    -- Augment with Gen2 GBC palette data (palMap + palColors) from ROM.
    -- The MAP may already be in place: Prism carries its palettes in
    -- <Tileset>Attr, decoded above, and ships no PalMap symbol at all.  Only
    -- the COLOURS are shared work, so the reader below fills in whichever half
    -- is still missing rather than owning both.
    if self.rom then
      local palSym = self:symbol(gfxId .. "PalMap")
      if palSym and not tilesets[id].palMap then
        -- How many tiles the sheet actually came out as decides both the
        -- palette map's length and whether it carries a VRAM-bank bit.
        local twoBanks = GEN2_PAL.twoVramBanks(GEN2_PAL.sheetTiles(tilesets[id]))
        local palOk, palRaw = pcall(function()
          return self.rom:bytes(palSym.bank, palSym.address,
            twoBanks and GEN2_PAL.palMapBytes or GEN2_PAL.palMapBytesOneBank)
        end)
        if palOk and type(palRaw) == "table" then
          -- Crystal's palette map is 224 nibbles -- one per metatile byte
          -- $00-$DF, each `vramBank << 3 | palette` -- not 96.  Reading only
          -- the first 96 stopped at the bank-0 half, so every second-bank tile
          -- took a clamped, wrong palette.  Re-key it by the same flattened
          -- 0..191 index GEN2_PAL.tileIndex produces and drop the bank bit, which
          -- the block bytes now carry themselves.  Reading PAST the map would
          -- run into the next tileset's, which is why the length is version-
          -- derived rather than fixed.
          local nibbles = {}
          for _, byte in ipairs(palRaw) do
            nibbles[#nibbles + 1] = byte % 16
            nibbles[#nibbles + 1] = math.floor(byte / 16)
          end
          local palMap = {}
          if twoBanks then
            for tile = 0, GEN2_PAL.tilesPerVramBank * 2 - 1 do
              local raw = tile < GEN2_PAL.tilesPerVramBank and tile
                or (tile - GEN2_PAL.tilesPerVramBank + 0x80)
              palMap[tile + 1] = (nibbles[raw + 1] or 0) % 8
            end
          else
            for index, nibble in ipairs(nibbles) do palMap[index] = nibble end
          end
          tilesets[id].palMap = palMap
        end
      end
      -- The colours, for either source of the map.  `id` may be the HOUSE
      -- alias, whose maps are recorded under the real graphics family, so try
      -- both before falling back.
      if tilesets[id].palMap then
        local env = tilesetEnvironments[id] or tilesetEnvironments[gfxId]
        if env == nil then env = GEN2_PAL.defaultEnvironment end
        local rows = envPalettes and envPalettes[env]
        if rows then
          -- palColors stays the DAY row so every existing reader keeps
          -- working unchanged; palColorsByTod carries the other three so the
          -- renderer can follow the clock (GetTimeOfDay) the way the ROM does.
          tilesets[id].palColors = rows.DAY
          tilesets[id].palColorsByTod = {
            MORN = rows.MORN, DAY = rows.DAY,
            NITE = rows.NITE, DARK = rows.DARK,
          }
          tilesets[id].palEnvironment = env
        else
          -- A map with no colours renders grey, which reads as "the import
          -- half worked".  Say which half.
          Logger.warn("gen2 tileset %s: palette map but no colours for "
            .. "environment %s (EnvironmentColorsPointers missing?)",
            tostring(id), tostring(env))
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
      -- Prism stores every overworld sprite sheet LZ3-compressed --
      -- `Player0SpriteGFX:: INCBIN "gfx/overworld/p0.2bpp.lz"`, 207 of the 234
      -- of them -- where Gold and Crystal store them raw.  Read raw, the
      -- compressed stream is decoded as 2bpp tiles, which is exactly the
      -- "scrambled player sprite" that made Prism's own character unreadable.
      --
      -- row.bytes is the sprite_header's own declared VRAM size, so it is the
      -- length gen2LzAt checks against -- and a sheet that really is raw (the
      -- other 27, and every sheet in Gold and Crystal) simply fails that check
      -- and falls through to the read below.
      if row.compressed then
        local out = self:gen2LzAt(row.bank, row.address)
        if out and #out >= row.bytes then
          -- the sheet may decode longer than the frames we keep; take the head
          local head = {}
          for n = 1, row.bytes do head[n] = out[n] end
          return head
        end
      end
      return self.rom:bytes(row.bank, row.address, row.bytes)
    end)
    if ok and type(raw) == "table" and #raw >= row.bytes then
      local width, height = row.width, row.height
      local frames = row.frames
      -- One malformed sheet must not take the import down.  decode2bpp
      -- ASSERTS on a non-tile-aligned size, and this stage runs last, so a
      -- single bad row used to throw away a complete extraction -- every
      -- table already read, at the final step.  Skip the sprite instead.
      local okImg, img = pcall(ImageWriter.decode2bpp, raw, width, height)
      if not okImg then
        Logger.warn("gen2 sprite %s skipped (%dx%d): %s",
                    tostring(row.id), width, height, tostring(img))
        img = nil
      end
      if img then
      -- Expand symmetric big dolls to a real 32x32 sheet so the renderer can
      -- draw the full body (not just the top-left 16x16 face tile).
      if BIG_SPRITE_IDS[row.id] and width == 16 and height >= 32 then
        -- decode2bpp validates the payload length against the dimensions, so
        -- it must be handed EXACTLY the 128 bytes of a 16x32 body.  `raw` is
        -- the whole sheet, and a taller one (Prism ships 48-row sheets) made
        -- this assert "192 bytes, expected 128" and abort the entire import.
        local head = {}
        for n = 1, 128 do head[n] = raw[n] end
        local okLeft, left = pcall(ImageWriter.decode2bpp, head, 16, 32)
        if not okLeft then left = nil end
        -- composite left | mirror(left) into 32x32
        if left and ImageWriter.mirrorComposite32 then
          img = ImageWriter.mirrorComposite32(left)
        elseif left then
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
  end
  orderedSprites = {}
  for id in pairs(spriteIds) do orderedSprites[#orderedSprites + 1] = id end
  table.sort(orderedSprites)

  -- SPRITE_POKEMON objects have no sheet of their own: GetMonSprite.Mon hands
  -- the species to LoadOverworldMonIcon, so they wear the 16x32 two-frame
  -- party menu icon extractIcons already wrote.  Those icons are baked in the
  -- mon's own palette with a transparent colour 0, hence trueColor.
  local speciesOrder = constants.speciesOrder or {}
  -- Prism has REAL sheets for these; where it does, they win over the icon.
  local monOwSheets = self:extractPrismMonOverworldSprites(speciesOrder) or {}
  local monIconDefs = {}
  -- Every species, not just the SpriteMons rows a map object happens to name:
  -- the day-care yard picks its two sheets from whatever is boarded, so any of
  -- the 251 can be asked for and a missing def falls back to the player sheet.
  for species = 1, #speciesOrder do
    local id = gen2MonSpriteId(species)
    if not monOwSheets[id] then
      monIconDefs[id] =
        "assets/generated/icons/" .. speciesOrder[species]:lower() .. ".png"
    end
    spriteIds[id] = true
  end
  orderedSprites = {}
  for id in pairs(spriteIds) do orderedSprites[#orderedSprites + 1] = id end
  table.sort(orderedSprites)

  -- Read Gen2 OBJ palettes (MapObjectPals at 02:78ae)
  local gen2ObjPals = self:gen2ObjPalettes()

  for _, id in ipairs(orderedSprites) do
    local sheet = monOwSheets[id]
    local img = (sheet and sheet.image) or monIconDefs[id]
       or gen2SpriteImageMap[id]
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
    if sheet then
      -- a walking sheet like any other NPC's, on PAL_OW_PLAYER
      spriteDef.frames = sheet.frames
      spriteDef.walker = sheet.frames >= 3
      spriteDef.monIcon, spriteDef.trueColor = nil, nil
    elseif monIconDefs[id] then
      spriteDef.frames, spriteDef.walker = 2, false
      spriteDef.monIcon, spriteDef.trueColor = true, true
    end
    -- Attach the correct Gen2 OBJ palette so the sprite renders in proper GBC colors
    local pal = gen2ObjPals[sheet and 0 or (gen2SpritePalIdx[id] or 0)]
    if pal and not monIconDefs[id] then spriteDef.gen2ObjPal = pal end
    sprites[id] = spriteDef
  end

  -- gen2OverworldSprites keys its rows by the GFX label minus the SpriteGFX
  -- suffix, so Chris's row is base "Chris" and his bike is "ChrisBike".
  self:registerGen2KrisSprites(sprites, function(base)
    for _, row in pairs(self:gen2OverworldSprites()) do
      if row.base == base then return row end
    end
    return nil
  end)
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
  -- walk ids rather than GEN2_TYPES so a hack's own types (Prism's Fairy,
  -- Gas and Sound) end up in the roster too
  for value = 0, 27 do
    local typeName = self:gen2TypeName(value)
    if typeName and not typeChart.types[typeName] then
      typeChart.types[typeName] = {
        name = typeName,
        category = value >= GEN2_SPECIAL_TYPE and "special" or "physical",
      }
    end
  end
  -- Prism replaces that sparse list with a PACKED BIT ARRAY: one row per
  -- attacking type, `layout.matchupTableWidth` bytes wide, each defending type
  -- taking two bits (0 immune, 1 not-very, 2 neutral, 3 super).  Nothing about
  -- it looks like the Crystal table -- which is why no scan for triples, pairs
  -- or a byte matrix ever found it, and why type effectiveness silently fell
  -- back to the engine defaults.  Verified against the game's own
  -- battle/type_matchup.asm: every row decodes identically.
  local packedSym = self:symbol("TypeMatchup")
  local packedWidth = self:layout("matchupTableWidth", 0)
  if packedSym and packedWidth > 0 and self.rom then
    typeChart.source = "ROM:TypeMatchup (2-bit packed)"
    local MULTIPLIER = { [0] = 0, 5, 10, 20 }   -- x10, as the sparse rows use
    for attack = 0, 27 do
      local attacker = self:gen2TypeName(attack)
      local ok, row = pcall(function()
        return self.rom:bytes(packedSym.bank,
                              packedSym.address + attack * packedWidth,
                              packedWidth)
      end)
      if attacker and ok and type(row) == "table" then
        for defend = 0, 27 do
          local defender = self:gen2TypeName(defend)
          local byte = row[math.floor(defend / 4) + 1]
          if defender and byte then
            local code = math.floor(byte / (4 ^ (defend % 4))) % 4
            -- only the non-neutral cells are worth carrying; neutral is the
            -- engine's default and listing 784 rows would bloat the file
            if code ~= 2 then
              typeChart.matchups[#typeChart.matchups + 1] = {
                attacker = attacker, defender = defender,
                multiplier = MULTIPLIER[code],
              }
            end
          end
        end
      end
    end
  end

  local matchupSym = self:symbol("TypeMatchups")
  if matchupSym and self.rom and #typeChart.matchups == 0 then
    local address = matchupSym.address
    for _ = 1, 256 do
      local first = self.rom:byte(matchupSym.bank, address)
      if first == 0xFF then break end
      if first == 0xFE then
        address = address + 1
      else
        local row = self.rom:bytes(matchupSym.bank, address, 3)
        local attacker = self:gen2TypeName(row[1])
        local defender = self:gen2TypeName(row[2])
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
  Menu = "Sfx_Menu",
  -- Gen1's SFX_TINK is the menu CURSOR blip.  Aliasing it to Sfx_Wrong made
  -- every cursor move in the port -- party menu, POKeGEAR, bag -- play the
  -- error buzz.  Sfx_Wrong keeps its own alias just below.
  Tink = "Sfx_Menu",
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
  -- PlayBattleMusic (crystal 11:$6E6C, gold 17:$4556) picks ELEVEN themes,
  -- not four.  Four of them were missing entirely, so the rival, Team Rocket
  -- and every Kanto trainer all opened on the plain Johto trainer theme, and
  -- night-time wild battles used the day song.  The keys here are the branch
  -- names in that routine; BattleState:computeMusicKind resolves them.
  battle = {
    wild = "Music_JohtoWildBattle",
    wildNight = "Music_JohtoWildBattleNight",   -- wTimeOfDay == NITE
    kantoWild = "Music_KantoWildBattle",        -- RegionCheck says Kanto
    suicune = "Music_SuicuneBattle",            -- Crystal only; roamer/Suicune
    trainer = "Music_JohtoTrainerBattle",
    kantoTrainer = "Music_KantoTrainerBattle",
    gym = "Music_JohtoGymBattle",
    kantoGym = "Music_KantoGymBattle",          -- IsKantoGymLeader
    rival = "Music_RivalBattle",                -- classes $09 and $2A
    rocket = "Music_RocketBattle",              -- classes $1F and $42
    final = "Music_ChampionBattle",
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

-- The stages split into two kinds, and they must fail differently.
--
-- The DATA stages produce what the game cannot run without; if one of those
-- throws, the import is genuinely broken and should say so.  The ASSET stages
-- decode graphics, and every one of them runs AFTER all the data is already
-- written.  A single bad sheet in one of those used to abort the whole import
-- -- three separate times against Prism, each a different decode2bpp assert
-- (a 61px sheet, a 192-byte payload for a 128-byte frame) -- throwing away a
-- complete, correct extraction at the very last step over one cosmetic tile.
--
-- So asset stages are allowed to fail: log which one, keep the placeholder art
-- that stage would have replaced, and finish.  A game with one wrong sprite is
-- worth far more than no game at all.
--
-- Table fields, not `local`s: this chunk is at Lua 5.1's 200-local ceiling.
RomExtractorGen2.DATA_STAGES = {
  "extractScaffoldCore", "extractMoves", "extractMapsFromRom",
  "extractMapScripts", "extractTextFromRom", "extractPokemon",
  "extractPalettes", "extractIcons", "extractEncounters", "extractField",
}
RomExtractorGen2.ASSET_STAGES = {
  "extractRuntimeScaffolds", "extractIntroAssetsFromRom", "extractAudio",
  "extractAssets",
}

function RomExtractorGen2:run()
  for _, stage in ipairs(RomExtractorGen2.DATA_STAGES) do
    self[stage](self)
  end
  local failed = 0
  for _, stage in ipairs(RomExtractorGen2.ASSET_STAGES) do
    local ok, err = pcall(self[stage], self)
    if not ok then
      failed = failed + 1
      Logger.warn("gen2 asset stage %s failed, continuing: %s",
                  stage, tostring(err):gsub("%s+", " "))
    end
  end
  if failed > 0 then
    Logger.warn("gen2 import finished with %d asset stage(s) incomplete; "
                .. "data is complete, some art falls back to placeholders",
                failed)
  end
  if self.progress then
    self.progress(STAGE_COUNT, STAGE_COUNT, "Ready", 1, 1)
  end
  return true
end

return RomExtractorGen2