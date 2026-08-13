-- Vanilla Gen2 (Gold/Silver, international) raw SRAM save (32768 bytes) <->
-- this project's save.lua shape (src/core/SaveData.lua / SaveData.newGame).
--
-- The sibling of src/save_convert/GenSave.lua, which is Gen1-only: its
-- header even says "Day Care ... intentionally not modeled", and its badge
-- table is the eight Kanto badges written into save.inventory.  Routing a
-- Gold/Silver .sav through it therefore lost the two things Gen2 keeps
-- somewhere else entirely -- the DAY-CARE pens (wBreedMon1/wBreedMon2) and
-- the sixteen badges (wJohtoBadges/wKantoBadges, which this port spells as
-- save.flags entries; see src/inventory/Badges.lua and Gen2ScriptVM's
-- ENGINE_FLAG_NAMES).  This module is the Gen2 codec SaveConvert routes to.
--
-- Pure Lua, no love.* dependency -- runs under plain luajit for the CLI
-- (tools/save_convert/convert.lua) and headless tests alike.
--
-- OFFSET DERIVATION.  Every address below comes out of the pret/pokegold
-- symbol table this project already ships (tools/rom_manifest_gold.json,
-- produced by tools/make_gen2_manifest.py from a pokegold build's .sym), so
-- none of it is hand-counted:
--
--   sOptions      = bank1 $A000  -> file 0x2000
--   sCheckValue1  = bank1 $A008  -> file 0x2008
--   sGameData     = bank1 $A009  -> file 0x2009   (= sPlayerData)
--   sPokemonData  = bank1 $A88A  -> file 0x288A
--   sGameDataEnd  = bank1 $AD69  -> file 0x2D69   (= sChecksum, dw LE)
--   sCheckValue2  = bank1 $AD6B  -> file 0x2D6B
--   sBox          = bank1 $AD6C  -> file 0x2D6C   (the ACTIVE box buffer)
--   sBox1..sBox7  = bank2 $A000 + (n-1) * $450 -> file 0x4000 + ...
--   sBox8..sBox14 = bank3 $A000 + (n-8) * $450 -> file 0x6000 + ...
--
-- and the mirrored WRAM window is one single linear run: wPlayerData
-- ($D1A1) through wPokemonDataEnd ($DF01) is copied verbatim to $A009
-- onwards, which the endpoints confirm exactly --
-- 0x2009 + (wPokemonData $DA22 - wPlayerData $D1A1) = 0x288A = sPokemonData,
-- and 0x2009 + (wPokemonDataEnd $DF01 - $D1A1) = 0x2D69 = sGameDataEnd.
-- So a single `sram(wramAddress)` helper places every field, and the two
-- independent endpoint checks make the whole chain self-verifying.
--
-- Regions with no equivalent in save.lua (sprite/animation scratch, the
-- Hall of Fame roster, mail, the link battle record, the backup save copies
-- in banks 0/3) are intentionally not modeled: encode() starts from the
-- ORIGINAL imported bytes as a template when available (decode stashes them
-- in save.rawImport) so that data round-trips untouched instead of being
-- invented -- the same contract GenSave.lua keeps for Gen1.

local bit = require("bit")

local Gen2Save = {}

-- ------------------------------------------------------------------
-- Sizes (pokegold constants/pokemon_data_constants.asm,
-- constants/item_constants.asm)
-- ------------------------------------------------------------------

local NAME_LENGTH = 11        -- NAME_LENGTH / MON_NAME_LENGTH (10 + $50)
local PARTY_LENGTH = 6
local MONS_PER_BOX = 20
local NUM_BOXES = 14
local BOX_STRUCT_SIZE = 32    -- box_struct, confirmed by wBreedMon1 ($DC57)
                              -- + 32 = wBreedMon1BoxEnd/wDayCareLady ($DC77)
local PARTY_STRUCT_SIZE = 48  -- box_struct + Status,Unused,HP,MaxHP,Atk,Def,
                              -- Spd,SpclAtk,SpclDef; wPartyMons ($DA2A)
                              -- + 6 * 48 = wPartyMonOT ($DB4A)
local BOX_REGION_SIZE = 1 + (MONS_PER_BOX + 1)
                      + MONS_PER_BOX * BOX_STRUCT_SIZE
                      + MONS_PER_BOX * NAME_LENGTH * 2   -- 1102 = sBox1End
local BOX_SLOT_STRIDE = 0x450 -- sBox2 - sBox1 (1102 rounded up by 2 pad bytes)

local MAX_ITEMS, MAX_KEY_ITEMS, MAX_BALLS, MAX_PC_ITEMS = 20, 25, 12, 50
local NUM_TMS, NUM_HMS = 50, 7
local TM01_ITEM_INDEX, HM01_ITEM_INDEX = 191, 243  -- data/generated/items.lua
                                                    -- ITEM_191 key "TM_01",
                                                    -- ITEM_243 key "HM_01"

local TERMINATOR = 0x50       -- "@", the text terminator
local EGG_SPECIES_BYTE = 0xFD -- EGG (constants/pokemon_constants.asm)

-- ------------------------------------------------------------------
-- Absolute byte offsets (0-based, matching a raw 32768-byte .sav file)
-- ------------------------------------------------------------------

local WRAM_ANCHOR = 0xD1A1    -- wPlayerData
local SRAM_ANCHOR = 0x2009    -- sPlayerData (bank 1, $A009)

-- A WRAM address inside wPlayerData..wPokemonDataEnd -> its file offset.
local function sram(addr) return SRAM_ANCHOR + (addr - WRAM_ANCHOR) end

local O = {}
O.options       = 0x2000
O.checkValue1   = 0x2008
O.gameData      = 0x2009
O.playerId      = sram(0xD1A1)   -- wPlayerID (2B big-endian)
O.playerName    = sram(0xD1A3)   -- wPlayerName
O.momName       = sram(0xD1AE)   -- wMomsName
O.rivalName     = sram(0xD1B9)   -- wRivalName
O.gameTimeHours = sram(0xD1EB)   -- wGameTimeHours (2B big-endian)
O.gameTimeMins  = sram(0xD1ED)
O.gameTimeSecs  = sram(0xD1EE)
O.gameTimeFrames = sram(0xD1EF)
-- wPlayerGender, bit 0 -- Crystal only (NamePlayer.Kris at 01:$60DE reads
-- `ld a, [$D472] / bit 0, a`).  Gold and Silver never write the byte and have
-- no KRIS to be, so a stray 1 there is inert: field.playerForms is absent on
-- those rips, and Sprites.playerForm answers nil whatever this says.
O.gender        = sram(0xD472)
O.statusFlags   = sram(0xD571)   -- wStatusFlags (bit 0 POKEDEX, 1 UNOWN DEX)
O.money         = sram(0xD573)   -- wMoney (3B big-endian BINARY, not BCD)
O.coins         = sram(0xD57A)   -- wCoins (2B big-endian)
O.johtoBadges   = sram(0xD57C)
O.kantoBadges   = sram(0xD57D)
O.tmsHms        = sram(0xD57E)   -- 57 quantity bytes: TM01..TM50, HM01..HM07
O.numItems      = sram(0xD5B7)
O.items         = sram(0xD5B8)   -- 20 x (id, qty) + $FF
O.numKeyItems   = sram(0xD5E1)
O.keyItems      = sram(0xD5E2)   -- 25 x id + $FF (no quantities)
O.numBalls      = sram(0xD5FC)
O.balls         = sram(0xD5FD)   -- 12 x (id, qty) + $FF
O.numPCItems    = sram(0xD616)
O.pcItems       = sram(0xD617)   -- 50 x (id, qty) + $FF
O.pokegearFlags = sram(0xD67C)   -- wPokegearFlags
O.eventFlags    = sram(0xD7B7)   -- wEventFlags, flag_array NUM_EVENTS (256B)
O.curBox        = sram(0xD8BC)   -- wCurBox (0-based)
O.visitedSpawns = sram(0xD9EE)   -- wVisitedSpawns, flag_array NUM_SPAWNS (4B)
O.mapGroup      = sram(0xDA00)
O.mapNumber     = sram(0xDA01)
O.yCoord        = sram(0xDA02)
O.xCoord        = sram(0xDA03)
O.partyCount    = sram(0xDA22)
O.partySpecies  = sram(0xDA23)   -- 6 + $FF
O.partyMons     = sram(0xDA2A)
O.partyMonOT    = sram(0xDB4A)
O.partyMonNicks = sram(0xDB8C)
O.pokedexCaught = sram(0xDBE4)   -- 32B flag_array NUM_POKEMON (251)
O.pokedexSeen   = sram(0xDC04)
O.dayCareMan    = sram(0xDC40)
O.breedMon1Nick = sram(0xDC41)
O.breedMon1OT   = sram(0xDC4C)
O.breedMon1     = sram(0xDC57)
O.dayCareLady   = sram(0xDC77)
O.stepsToEgg    = sram(0xDC78)
O.breedMon2Nick = sram(0xDC7A)
O.breedMon2OT   = sram(0xDC85)
O.breedMon2     = sram(0xDC90)
O.eggMonNick    = sram(0xDCB0)
O.eggMonOT      = sram(0xDCBB)
O.eggMon        = sram(0xDCC6)
O.checksum      = 0x2D69         -- sChecksum, 2B LITTLE-endian
O.checkValue2   = 0x2D6B
O.curBoxData    = 0x2D6C         -- sBox, the working copy of wCurBox's box
O.checksumStart = 0x2009         -- sGameData
O.checksumEnd   = 0x2D69         -- sGameDataEnd (exclusive)

-- sBox1..sBox7 sit in bank 2 ($4000), sBox8..sBox14 in bank 3 ($6000).
local function boxSlotOffset(n)
  if n <= 7 then return 0x4000 + (n - 1) * BOX_SLOT_STRIDE end
  return 0x6000 + (n - 8) * BOX_SLOT_STRIDE
end

-- SAVE_CHECK_VALUE_1 / _2 (constants/misc_constants.asm).  The real game
-- rejects a save whose check values are wrong before it even looks at the
-- checksum, so they double as a cheap "is this a Gen2 image at all?" probe.
local CHECK_VALUE_1, CHECK_VALUE_2 = 0x99, 0x27

Gen2Save.OFFSETS = O
Gen2Save.SAVE_SIZE = 32768
Gen2Save.NUM_BOXES = NUM_BOXES
Gen2Save.BOX_REGION_SIZE = BOX_REGION_SIZE

-- ------------------------------------------------------------------
-- Byte-level helpers.  `bytes` is a 32768-byte Lua string (1-based, so
-- byte offset N is string position N+1); `buf` for writing is a
-- 32768-entry array of 1-char strings, joined at the end.
-- ------------------------------------------------------------------

local function u8(bytes, off) return bytes:byte(off + 1) or 0 end
local function u16be(bytes, off) return u8(bytes, off) * 256 + u8(bytes, off + 1) end
local function u16le(bytes, off) return u8(bytes, off) + u8(bytes, off + 1) * 256 end
local function u24be(bytes, off)
  return u8(bytes, off) * 65536 + u8(bytes, off + 1) * 256 + u8(bytes, off + 2)
end

local function setByte(buf, off, v) buf[off + 1] = string.char(bit.band(v, 0xFF)) end
local function setU16be(buf, off, v)
  setByte(buf, off, bit.band(bit.rshift(v, 8), 0xFF))
  setByte(buf, off + 1, bit.band(v, 0xFF))
end
local function setU16le(buf, off, v)
  setByte(buf, off, bit.band(v, 0xFF))
  setByte(buf, off + 1, bit.band(bit.rshift(v, 8), 0xFF))
end
local function setU24be(buf, off, v)
  setByte(buf, off, bit.band(bit.rshift(v, 16), 0xFF))
  setByte(buf, off + 1, bit.band(bit.rshift(v, 8), 0xFF))
  setByte(buf, off + 2, bit.band(v, 0xFF))
end

-- Checksum (pokegold engine/menus/save.asm): a plain 16-bit sum of every
-- byte in sGameData..sGameDataEnd-1, stored little-endian at sChecksum.
local function checksum(bytes, from, to)
  local sum = 0
  for i = from, to - 1 do sum = sum + u8(bytes, i) end
  return bit.band(sum, 0xFFFF)
end

local function checksumBuf(buf, from, to)
  local sum = 0
  for i = from, to - 1 do
    local c = buf[i + 1]
    sum = sum + (c and c:byte() or 0)
  end
  return bit.band(sum, 0xFFFF)
end

-- flag_array bit N: byte N/8, bit N%8 counting from the LSB
local function bitGet(bytes, base, index)
  local b = u8(bytes, base + math.floor(index / 8))
  return bit.band(b, bit.lshift(1, index % 8)) ~= 0
end

local function bitSet(buf, base, index, value)
  local off = base + math.floor(index / 8)
  local cur = buf[off + 1]
  cur = cur and cur:byte() or 0
  local mask = bit.lshift(1, index % 8)
  setByte(buf, off, value and bit.bor(cur, mask) or bit.band(cur, bit.bnot(mask)))
end

-- ------------------------------------------------------------------
-- Text.  The Gen2 charmap this port generates (data/generated/charmap.lua)
-- is a flat byte -> glyph table keyed by the byte's DECIMAL VALUE AS A
-- STRING ("128" = "A"); bytes with no printable glyph come out as the
-- literal token "{BYTE:9A}", which round-trips because the reverse map
-- accepts it back.  setCharmap also takes GenSave's {byByte, byToken}
-- shape so a caller can hand either one over.
-- ------------------------------------------------------------------

local charmap

function Gen2Save.setCharmap(cm)
  if type(cm) ~= "table" then charmap = nil; return end
  if type(cm.byByte) == "table" and type(cm.byToken) == "table" then
    charmap = { byByte = cm.byByte, byToken = cm.byToken, maxToken = 1 }
    for token in pairs(cm.byToken) do
      if #token > charmap.maxToken then charmap.maxToken = #token end
    end
    return
  end
  local byByte, byToken, maxToken = {}, {}, 1
  for key, glyph in pairs(cm) do
    local b = tonumber(key)
    if b and type(glyph) == "string" and #glyph > 0 then
      byByte[b] = glyph
      -- first byte wins: several control bytes render as the same glyph,
      -- and the lowest is the one a name field would legitimately hold
      if byToken[glyph] == nil or b < byToken[glyph] then byToken[glyph] = b end
      if #glyph > maxToken then maxToken = #glyph end
    end
  end
  charmap = { byByte = byByte, byToken = byToken, maxToken = maxToken }
end

local function decodeName(bytes, off, len)
  local out = {}
  for i = 0, len - 1 do
    local b = u8(bytes, off + i)
    if b == TERMINATOR then break end
    out[#out + 1] = (charmap and charmap.byByte[b]) or "?"
  end
  return table.concat(out)
end

local function encodeName(buf, off, len, text)
  text = tostring(text or "")
  local i, pos = 0, 1
  while i < len - 1 and pos <= #text do
    -- longest-match first: a "{BYTE:9A}" token and a multi-byte UTF-8
    -- glyph are both ONE game character despite being several Lua bytes
    local b, clen
    for try = math.min(charmap and charmap.maxToken or 1, #text - pos + 1), 1, -1 do
      local cand = text:sub(pos, pos + try - 1)
      local mapped = charmap and charmap.byToken[cand]
      if mapped then b, clen = mapped, try; break end
    end
    if not b then
      -- unmappable: consume one whole UTF-8 sequence so we never split it
      local b0 = text:byte(pos)
      clen = (b0 < 0x80 and 1) or (b0 < 0xE0 and 2) or (b0 < 0xF0 and 3) or 4
      b = (charmap and charmap.byToken["?"]) or TERMINATOR
    end
    setByte(buf, off + i, b)
    i, pos = i + 1, pos + clen
  end
  -- exactly one terminator, then $50-pad the tail the way the naming
  -- screen leaves it (a zero tail renders as garbage glyphs on hardware)
  for j = i, len - 1 do setByte(buf, off + j, TERMINATOR) end
end

-- ------------------------------------------------------------------
-- DV / PP packing.  Unchanged from Gen1: DVs are dw as
-- byte0 = (Attack << 4) | Defense, byte1 = (Speed << 4) | Special, with
-- the HP DV derived from the four stat DVs' low bits; a PP byte is
-- (PP Ups << 6) | current PP.
-- ------------------------------------------------------------------

local function decodeDVs(bytes, off)
  local b0, b1 = u8(bytes, off), u8(bytes, off + 1)
  local atk, def = bit.rshift(b0, 4), bit.band(b0, 0xF)
  local spe, spc = bit.rshift(b1, 4), bit.band(b1, 0xF)
  local hp = bit.bor(bit.lshift(bit.band(atk, 1), 3), bit.lshift(bit.band(def, 1), 2),
                     bit.lshift(bit.band(spe, 1), 1), bit.band(spc, 1))
  return { hp = hp, attack = atk, defense = def, speed = spe, special = spc }
end

local function encodeDVs(buf, off, dvs)
  dvs = dvs or {}
  setByte(buf, off, bit.bor(bit.lshift(bit.band(dvs.attack or 0, 0xF), 4),
                            bit.band(dvs.defense or 0, 0xF)))
  setByte(buf, off + 1, bit.bor(bit.lshift(bit.band(dvs.speed or 0, 0xF), 4),
                                bit.band(dvs.special or 0, 0xF)))
end

local function decodePPByte(b) return bit.band(b, 0x3F), bit.rshift(b, 6) end
local function encodePPByte(pp, ppUps)
  return bit.bor(bit.lshift(bit.band(ppUps or 0, 3), 6), bit.band(pp or 0, 0x3F))
end

-- Status byte (constants/battle_constants.asm): bits 0-2 sleep turns,
-- 3 PSN, 4 BRN, 5 FRZ, 6 PAR, 7 TOX.  This port has no separate badly-
-- poisoned state, so TOX imports as PSN (which is how it behaves here).
local STATUS_BIT = { PSN = 3, BRN = 4, FRZ = 5, PAR = 6 }
local function decodeStatus(b)
  if bit.band(b, 7) > 0 then return "SLP" end
  if bit.band(b, 0x88) ~= 0 then return "PSN" end
  for name, idx in pairs(STATUS_BIT) do
    if bit.band(b, bit.lshift(1, idx)) ~= 0 then return name end
  end
  return nil
end
local function encodeStatus(status)
  if status == "SLP" then return 7 end
  if status and STATUS_BIT[status] then return bit.lshift(1, STATUS_BIT[status]) end
  return 0
end

-- ------------------------------------------------------------------
-- Badges.  Gen2 has no badge ITEM: the gyms run `setflag ENGINE_ZEPHYRBADGE`
-- and friends, EngineFlags rows $1A-$29, which are wJohtoBadges' eight bits
-- then wKantoBadges' eight.  This port stores them under the badge id in
-- save.flags -- the exact names src/script/Gen2ScriptVM.lua's
-- ENGINE_FLAG_NAMES produces and src/inventory/Badges.lua reads back.
-- The bit order is NOT the trainer card's display order (Mineral is bit 4,
-- Storm bit 5); it is the EngineFlags row order.
-- ------------------------------------------------------------------

local JOHTO_BADGE_BY_BIT = {
  [0] = "ZEPHYRBADGE", [1] = "HIVEBADGE", [2] = "PLAINBADGE", [3] = "FOGBADGE",
  [4] = "MINERALBADGE", [5] = "STORMBADGE", [6] = "GLACIERBADGE", [7] = "RISINGBADGE",
}
local KANTO_BADGE_BY_BIT = {
  [0] = "BOULDERBADGE", [1] = "CASCADEBADGE", [2] = "THUNDERBADGE", [3] = "RAINBOWBADGE",
  [4] = "SOULBADGE", [5] = "MARSHBADGE", [6] = "VOLCANOBADGE", [7] = "EARTHBADGE",
}

-- The other EngineFlags rows this port gives a real name to (the rest fall
-- through to the generic FLAG_G2_nnnn ids): rows $00/$01/$04 are
-- wPokegearFlags, rows $0B/$0C are wStatusFlags.  All of it lives in
-- src/script/Gen2Flags.lua so the VM and this codec cannot drift apart.
local Gen2Flags = require("src.script.Gen2Flags")
local engineFlagName = Gen2Flags.engineFlag
Gen2Save.engineFlagName = engineFlagName

-- The EngineFlags rows themselves come out of the ROM (field.engineFlags,
-- see RomExtractorGen2:gen2EngineFlags): 93 `dw address, db mask` rows
-- scattered across the save's WRAM block.  Decoding them generically is what
-- carries the Pokegear cards, the day-care staging bits, the Fly points, the
-- daily/weekly flags and the badges into an imported save -- before this,
-- only the five named rows above came across.
--
-- Rows $05/$06/$07 are the day-care staging bits; DayCare.syncFlags rewrites
-- them from the pens on load, so decoding them is harmless and encoding them
-- is what a cartridge expects.
local ENGINE_FLAG_WRAM_LO = WRAM_ANCHOR   -- wPlayerData
local ENGINE_FLAG_WRAM_HI = 0xDF01        -- wPokemonDataEnd (exclusive)

local function engineFlagRows(data)
  local field = data and data.field
  local rows = field and field.engineFlags
  if type(rows) ~= "table" then return nil end
  return rows
end

local function engineFlagSlot(row)
  local address = tonumber(row.address)
  local bitIndex = tonumber(row.bit)
  if not address or not bitIndex then return nil end
  if address < ENGINE_FLAG_WRAM_LO or address >= ENGINE_FLAG_WRAM_HI then
    return nil
  end
  return sram(address), bitIndex
end

-- wEventFlags bit N -> the name src/script/Gen2ScriptVM.lua's `eventFlag`
-- helper produces, which is what every extracted Gen2 script sets and
-- checks.  Keeping the two spellings identical is the whole reason an
-- imported cartridge save resumes its story progress at all.
local NUM_EVENT_FLAGS = 0x100 * 8   -- wEventFlags is a 256-byte flag_array
local eventFlagName = Gen2Flags.eventFlag
Gen2Save.eventFlagName = eventFlagName

-- ------------------------------------------------------------------
-- Crosswalks (built once from `data` = {pokemon=, moves=, items=, maps=})
-- ------------------------------------------------------------------

local function buildIndexCrosswalk(defs)
  local byIndex, byId = {}, {}
  for id, def in pairs(defs or {}) do
    if type(def) == "table" and def.index ~= nil then
      byIndex[def.index] = id
      byId[id] = def.index
    end
  end
  return byIndex, byId
end

function Gen2Save.crosswalks(data)
  local pokemonByIndex, pokemonIndex = buildIndexCrosswalk(data.pokemon)
  local movesByIndex, movesIndex = buildIndexCrosswalk(data.moves)
  local itemsByIndex, itemsIndex = buildIndexCrosswalk(data.items)

  -- Gen2's species index IS its national dex number (unlike Gen1, where
  -- the two numbering schemes differ -- the whole MissingNo. phenomenon),
  -- but prefer the explicit `dex` field the extractor writes.
  local pokemonByDex, pokemonDex = {}, {}
  for id, def in pairs(data.pokemon or {}) do
    if type(def) == "table" then
      local n = def.dex or def.index
      if n then pokemonByDex[n] = id; pokemonDex[id] = n end
    end
  end

  -- (map group, map number) -> map id.  The extractor stamps these onto
  -- every Gen2 map from its 9-byte map header (RomExtractorGen2's
  -- gen2MapIndex); a cache built before that lands simply has no group
  -- field, and decode() falls back to leaving the spawn alone.
  local mapsByGroupNumber, mapsHaveGroups = {}, false
  for id, def in pairs(data.maps or {}) do
    if type(def) == "table" and def.group and def.number then
      mapsByGroupNumber[def.group * 256 + def.number] = id
      mapsHaveGroups = true
    end
  end

  return {
    pokemonByIndex = pokemonByIndex, pokemonIndex = pokemonIndex,
    pokemonByDex = pokemonByDex, pokemonDex = pokemonDex,
    movesByIndex = movesByIndex, movesIndex = movesIndex,
    itemsByIndex = itemsByIndex, itemsIndex = itemsIndex,
    mapsByGroupNumber = mapsByGroupNumber, mapsHaveGroups = mapsHaveGroups,
    speciesDefs = data.pokemon or {},
    itemDefs = data.items or {},
    mapDefs = data.maps or {},
  }
end

-- Gen2, like Gen1, has no "is nicknamed" bit: an un-nicknamed mon stores
-- its species' standard name in the nickname slot, and the game recovers
-- the answer by comparing the two.  This port models that as
-- mon.nickname == nil (every display site reads `mon.nickname or def.name`),
-- so the two conventions are translated at this boundary.
local function speciesName(cw, species)
  local def = species and cw.speciesDefs[species]
  return (def and def.name) or species or ""
end

local function importedNickname(cw, species, stored)
  if stored == speciesName(cw, species) then return nil end
  return stored
end

-- ------------------------------------------------------------------
-- Mon struct.  box_struct (32B) is a byte-for-byte prefix of party_struct
-- (48B); decodeMon reads the box fields, then Status/HP/stats if isParty.
--
--   +0  Species      +21 DVs (2)
--   +1  Item         +23 PP (4)
--   +2  Moves (4)    +27 Happiness   (an EGG counts its remaining cycles here)
--   +6  OT ID (2)    +28 PokerusStatus
--   +8  Exp (3)      +29 CaughtData (2, unused in Gold/Silver)
--   +11 StatExp (10) +31 Level
--
-- party_struct then adds +32 Status, +33 Unused, +34 HP, +36 MaxHP,
-- +38 Attack, +40 Defense, +42 Speed, +44 SpclAtk, +46 SpclDef.
--
-- Note a Gen2 box_struct does NOT store current HP (Gen1's did): box and
-- day-care mons come back without stats, exactly as src/pokemon/Stats.lua's
-- Stats.ensure already expects for imported mons, and it fills both in on
-- the first status screen or party move.
-- ------------------------------------------------------------------

local function decodeMon(bytes, off, isParty, cw)
  local speciesIdx = u8(bytes, off)
  if speciesIdx == 0 or speciesIdx == 0xFF then return nil end
  local mon = {
    species = cw.pokemonByIndex[speciesIdx],
    exp = u24be(bytes, off + 8),
    dvs = decodeDVs(bytes, off + 21),
    statExp = {
      hp = u16be(bytes, off + 11), attack = u16be(bytes, off + 13),
      defense = u16be(bytes, off + 15), speed = u16be(bytes, off + 17),
      special = u16be(bytes, off + 19),
    },
    otId = u16be(bytes, off + 6),
    happiness = u8(bytes, off + 27),
    level = u8(bytes, off + 31),
    moves = {},
    -- kept verbatim so an export reproduces them: this port models
    -- neither, and re-deriving would quietly wipe a real cartridge's data
    pokerus = u8(bytes, off + 28),
    caughtData = u16be(bytes, off + 29),
  }
  if not mon.species then
    mon.species = string.format("SPECIES_%03d", speciesIdx)
  end
  local itemIdx = u8(bytes, off + 1)
  if itemIdx > 0 then mon.item = cw.itemsByIndex[itemIdx] end
  for i = 0, 3 do
    local moveIdx = u8(bytes, off + 2 + i)
    if moveIdx > 0 then
      local pp, ppUps = decodePPByte(u8(bytes, off + 23 + i))
      mon.moves[#mon.moves + 1] = { id = cw.movesByIndex[moveIdx], pp = pp, ppUps = ppUps }
    end
  end
  if isParty then
    mon.status = decodeStatus(u8(bytes, off + 32))
    mon.hp = u16be(bytes, off + 34)
    mon.stats = {
      hp = u16be(bytes, off + 36), attack = u16be(bytes, off + 38),
      defense = u16be(bytes, off + 40), speed = u16be(bytes, off + 42),
      spatk = u16be(bytes, off + 44), spdef = u16be(bytes, off + 46),
    }
    mon.stats.special = mon.stats.spatk
  end
  return mon
end

local function encodeMon(buf, off, mon, isParty, cw)
  if not mon then
    setByte(buf, off, 0)
    return
  end
  setByte(buf, off, cw.pokemonIndex[mon.species] or 0)
  setByte(buf, off + 1, (mon.item and cw.itemsIndex[mon.item]) or 0)
  for i = 0, 3 do
    local mv = mon.moves and mon.moves[i + 1]
    setByte(buf, off + 2 + i, mv and (cw.movesIndex[mv.id] or 0) or 0)
    setByte(buf, off + 23 + i, mv and encodePPByte(mv.pp, mv.ppUps) or 0)
  end
  setU16be(buf, off + 6, mon.otId or 0)
  setU24be(buf, off + 8, mon.exp or 0)
  local se = mon.statExp or {}
  setU16be(buf, off + 11, se.hp or 0)
  setU16be(buf, off + 13, se.attack or 0)
  setU16be(buf, off + 15, se.defense or 0)
  setU16be(buf, off + 17, se.speed or 0)
  setU16be(buf, off + 19, se.special or 0)
  encodeDVs(buf, off + 21, mon.dvs)
  -- an EGG spends the happiness byte as its remaining incubation cycles,
  -- one per 256 steps (this port counts single steps in mon.eggSteps)
  if mon.isEgg then
    setByte(buf, off + 27, math.max(0, math.min(255, math.ceil((mon.eggSteps or 0) / 256))))
  else
    setByte(buf, off + 27, mon.happiness or 0)
  end
  setByte(buf, off + 28, mon.pokerus or 0)
  setU16be(buf, off + 29, mon.caughtData or 0)
  setByte(buf, off + 31, mon.level or 1)
  if isParty then
    setByte(buf, off + 32, encodeStatus(mon.status))
    setByte(buf, off + 33, 0)
    local st = mon.stats or {}
    setU16be(buf, off + 34, mon.hp or st.hp or 0)
    setU16be(buf, off + 36, st.hp or 0)
    setU16be(buf, off + 38, st.attack or 0)
    setU16be(buf, off + 40, st.defense or 0)
    setU16be(buf, off + 42, st.speed or 0)
    setU16be(buf, off + 44, st.spatk or st.special or 0)
    setU16be(buf, off + 46, st.spdef or st.special or 0)
  end
end

-- ------------------------------------------------------------------
-- Item pockets.  ITEM/BALL/PC are (id, qty) pairs; KEY_ITEM is bare ids
-- with no quantity; TM_HM is a fixed 57-byte quantity array indexed by
-- machine number rather than a list.  All four fold into this port's one
-- flat save.inventory (src/inventory/Bag.lua re-splits them by def.pocket).
-- ------------------------------------------------------------------

local function decodePairList(bytes, off, capacity, cw, inventory, order)
  for i = 0, capacity - 1 do
    local idByte = u8(bytes, off + i * 2)
    if idByte == 0xFF or idByte == 0 then break end
    local id = cw.itemsByIndex[idByte]
    if id then
      inventory[id] = u8(bytes, off + i * 2 + 1)
      order[#order + 1] = id
    end
  end
end

local function decodeIdList(bytes, off, capacity, cw, inventory, order)
  for i = 0, capacity - 1 do
    local idByte = u8(bytes, off + i)
    if idByte == 0xFF or idByte == 0 then break end
    local id = cw.itemsByIndex[idByte]
    if id then
      inventory[id] = 1
      order[#order + 1] = id
    end
  end
end

-- machine slot (0-based over TM01..TM50, HM01..HM07) -> item index
local function machineItemIndex(slot)
  if slot < NUM_TMS then return TM01_ITEM_INDEX + slot end
  return HM01_ITEM_INDEX + (slot - NUM_TMS)
end

local function decodeMachines(bytes, off, cw, inventory, order)
  for slot = 0, NUM_TMS + NUM_HMS - 1 do
    local qty = u8(bytes, off + slot)
    if qty > 0 then
      local id = cw.itemsByIndex[machineItemIndex(slot)]
      if id then
        inventory[id] = qty
        order[#order + 1] = id
      end
    end
  end
end

local function pocketOf(cw, id)
  local def = cw.itemDefs[id]
  return def and def.pocket or nil
end

local function encodePairList(buf, off, capacity, ids, inventory, cw)
  local n = 0
  for _, id in ipairs(ids) do
    if n >= capacity then break end
    local idx = cw.itemsIndex[id]
    local qty = inventory[id]
    if idx and qty and qty > 0 then
      setByte(buf, off + n * 2, idx)
      setByte(buf, off + n * 2 + 1, math.min(qty, 99))
      n = n + 1
    end
  end
  setByte(buf, off + n * 2, 0xFF)
  return n
end

local function encodeIdList(buf, off, capacity, ids, cw)
  local n = 0
  for _, id in ipairs(ids) do
    if n >= capacity then break end
    local idx = cw.itemsIndex[id]
    if idx then
      setByte(buf, off + n, idx)
      n = n + 1
    end
  end
  setByte(buf, off + n, 0xFF)
  return n
end

-- ------------------------------------------------------------------
-- Box regions
-- ------------------------------------------------------------------

local BOX_MONS = 1 + (MONS_PER_BOX + 1)                              -- 22
local BOX_OT = BOX_MONS + MONS_PER_BOX * BOX_STRUCT_SIZE             -- 662
local BOX_NICKS = BOX_OT + MONS_PER_BOX * NAME_LENGTH                -- 882

local function decodeBoxRegion(bytes, base, cw)
  local out = {}
  local count = math.min(u8(bytes, base), MONS_PER_BOX)
  for i = 0, count - 1 do
    local mon = decodeMon(bytes, base + BOX_MONS + i * BOX_STRUCT_SIZE, false, cw)
    if mon then
      if u8(bytes, base + 1 + i) == EGG_SPECIES_BYTE then
        mon.isEgg = true
        mon.eggSteps = (mon.happiness or 0) * 256
        mon.happiness = nil
      end
      mon.ot = decodeName(bytes, base + BOX_OT + i * NAME_LENGTH, NAME_LENGTH)
      mon.nickname = importedNickname(cw, mon.species,
        decodeName(bytes, base + BOX_NICKS + i * NAME_LENGTH, NAME_LENGTH))
      out[#out + 1] = mon
    end
  end
  return out
end

local function encodeBoxRegion(buf, base, mons, cw, playerName)
  local n = math.min(#mons, MONS_PER_BOX)
  setByte(buf, base, n)
  for i = 0, n - 1 do
    local mon = mons[i + 1]
    setByte(buf, base + 1 + i,
            mon.isEgg and EGG_SPECIES_BYTE or (cw.pokemonIndex[mon.species] or 0))
    encodeMon(buf, base + BOX_MONS + i * BOX_STRUCT_SIZE, mon, false, cw)
    encodeName(buf, base + BOX_OT + i * NAME_LENGTH, NAME_LENGTH, mon.ot or playerName)
    encodeName(buf, base + BOX_NICKS + i * NAME_LENGTH, NAME_LENGTH,
               mon.nickname or speciesName(cw, mon.species))
  end
  setByte(buf, base + 1 + n, 0xFF)
end

-- ------------------------------------------------------------------
-- Day care.  This is the half GenSave never modeled at all.
--
-- wDayCareMan / wDayCareLady are bit fields, not counts:
--   wDayCareMan  bit 0 DAYCAREMAN_HAS_MON_F, bit 6 DAYCAREMAN_HAS_EGG_F,
--                bit 7 DAYCAREMAN_ACTIVE_F (the "we've met" intro bit)
--   wDayCareLady bit 0 DAYCARELADY_HAS_MON_F, bit 7 DAYCARELADY_ACTIVE_F
-- and each pen is nickname (11) + OT (11) + a bare box_struct (32), with a
-- third such block for the pending EGG.  src/pokemon/DayCare.lua keeps all
-- of it under save.daycare.breed.
-- ------------------------------------------------------------------

local DAYCAREMAN_HAS_MON = 0
local DAYCAREMAN_HAS_EGG = 6
local DAYCAREMAN_ACTIVE  = 7
local DAYCARELADY_HAS_MON = 0
local DAYCARELADY_ACTIVE  = 7

local function hasBit(b, n) return bit.band(b, bit.lshift(1, n)) ~= 0 end
local function withBit(b, n, on)
  if on then return bit.bor(b, bit.lshift(1, n)) end
  return bit.band(b, bit.bnot(bit.lshift(1, n)))
end

local function decodePen(bytes, monOff, nickOff, otOff, cw)
  local mon = decodeMon(bytes, monOff, false, cw)
  if not mon then return nil end
  mon.ot = decodeName(bytes, otOff, NAME_LENGTH)
  mon.nickname = importedNickname(cw, mon.species, decodeName(bytes, nickOff, NAME_LENGTH))
  return mon
end

local function encodePen(buf, monOff, nickOff, otOff, mon, cw, playerName)
  if not mon then
    setByte(buf, monOff, 0)
    return
  end
  encodeMon(buf, monOff, mon, false, cw)
  encodeName(buf, otOff, NAME_LENGTH, mon.ot or playerName)
  encodeName(buf, nickOff, NAME_LENGTH, mon.nickname or speciesName(cw, mon.species))
end

-- ------------------------------------------------------------------
-- decode: raw 32768-byte SRAM string -> save.lua-shaped table
-- ------------------------------------------------------------------

function Gen2Save.decode(bytes, data)
  assert(#bytes == Gen2Save.SAVE_SIZE, "expected a 32768-byte save")
  assert(charmap, "Gen2Save.setCharmap must be called before decode")
  local cw = Gen2Save.crosswalks(data)
  local warnings = {}
  local function warn(msg) warnings[#warnings + 1] = msg end

  if u8(bytes, O.checkValue1) ~= CHECK_VALUE_1
     or u8(bytes, O.checkValue2) ~= CHECK_VALUE_2 then
    warn("save check values are not Gold/Silver's (this may not be a Gen2 save)")
  end
  if checksum(bytes, O.checksumStart, O.checksumEnd) ~= u16le(bytes, O.checksum) then
    warn("main data checksum mismatch")
  end

  local playerName = decodeName(bytes, O.playerName, NAME_LENGTH)
  local save = {
    meta = { format = "gen2_import" },
    player = {
      name = playerName,
      rival = decodeName(bytes, O.rivalName, NAME_LENGTH),
      mom = decodeName(bytes, O.momName, NAME_LENGTH),
      id = u16be(bytes, O.playerId),
      gender = (u8(bytes, O.gender) % 2 == 1) and "girl" or "boy",
    },
    money = u24be(bytes, O.money),
    coins = u16be(bytes, O.coins),
    inventory = {},
    pcItems = {},
    pokedex = { seen = {}, owned = {} },
    flags = {},
    party = {},
    boxes = {},
    currentBox = 1,
  }

  -- bag: four pockets folded into one flat inventory
  local bagOrder = {}
  decodePairList(bytes, O.items, MAX_ITEMS, cw, save.inventory, bagOrder)
  decodeIdList(bytes, O.keyItems, MAX_KEY_ITEMS, cw, save.inventory, bagOrder)
  decodePairList(bytes, O.balls, MAX_BALLS, cw, save.inventory, bagOrder)
  decodeMachines(bytes, O.tmsHms, cw, save.inventory, bagOrder)
  save.bagOrder = bagOrder

  local pcOrder = {}
  decodePairList(bytes, O.pcItems, MAX_PC_ITEMS, cw, save.pcItems, pcOrder)
  save.pcOrder = pcOrder

  -- badges: save.flags entries, not inventory (see the table comment above)
  local johto, kanto = u8(bytes, O.johtoBadges), u8(bytes, O.kantoBadges)
  for i = 0, 7 do
    if hasBit(johto, i) then save.flags[JOHTO_BADGE_BY_BIT[i]] = true end
    if hasBit(kanto, i) then save.flags[KANTO_BADGE_BY_BIT[i]] = true end
  end

  -- event flags -> the exact ids every extracted Gen2 script uses
  for n = 0, NUM_EVENT_FLAGS - 1 do
    if bitGet(bytes, O.eventFlags, n) then save.flags[eventFlagName(n)] = true end
  end

  -- Per-map scene ids (MapScenes).  These are a SEPARATE store from the event
  -- flags and nothing used to read them, so an imported save came up with
  -- every scene at 0: the one-time cutscenes re-armed and the player was
  -- walled into New Bark Town (and Violet City, and anywhere else with a
  -- scene).  field.mapSceneVars is mapId -> the WRAM address the ROM keeps
  -- that map's scene byte at, emitted by the importer off the MapScenes table.
  local sceneVars = data and data.field and data.field.mapSceneVars
  if type(sceneVars) == "table" then
    save.g2Scenes = save.g2Scenes or {}
    for mapId, address in pairs(sceneVars) do
      if type(address) == "number" then
        save.g2Scenes[mapId] = u8(bytes, sram(address))
      end
    end
  end

  -- every EngineFlags row, under the id the script VM checks.  The badge
  -- rows come through here too and simply re-set the names above.
  for _, row in ipairs(engineFlagRows(data) or {}) do
    local off, bitIndex = engineFlagSlot(row)
    if off and hasBit(u8(bytes, off), bitIndex) then
      save.flags[engineFlagName(row.row)] = true
    end
  end

  -- wVisitedSpawns -> the FLY list.  HasVisitedSpawn tests bit [spawn id];
  -- this port spells the same set save.visited[mapId] (src/ui/TownMap.lua),
  -- so without this an imported save could not fly anywhere.
  local spawnFlags = data and data.field and data.field.spawnFlags
  if type(spawnFlags) == "table" then
    save.visited = save.visited or {}
    for _, entry in ipairs(spawnFlags) do
      if entry.map and bitGet(bytes, O.visitedSpawns, entry.bit) then
        save.visited[entry.map] = true
      end
    end
  end

  -- pokedex (flag_array NUM_POKEMON: bit 0 = dex #1)
  for dex, species in pairs(cw.pokemonByDex) do
    local idx = dex - 1
    if bitGet(bytes, O.pokedexCaught, idx) then save.pokedex.owned[species] = true end
    if bitGet(bytes, O.pokedexSeen, idx) then save.pokedex.seen[species] = true end
  end

  -- party
  local partyCount = math.min(u8(bytes, O.partyCount), PARTY_LENGTH)
  for i = 0, partyCount - 1 do
    local mon = decodeMon(bytes, O.partyMons + i * PARTY_STRUCT_SIZE, true, cw)
    if mon then
      if u8(bytes, O.partySpecies + i) == EGG_SPECIES_BYTE then
        mon.isEgg = true
        mon.eggSteps = (mon.happiness or 0) * 256
        mon.happiness = nil
      end
      mon.ot = decodeName(bytes, O.partyMonOT + i * NAME_LENGTH, NAME_LENGTH)
      mon.nickname = importedNickname(cw, mon.species,
        decodeName(bytes, O.partyMonNicks + i * NAME_LENGTH, NAME_LENGTH))
      save.party[#save.party + 1] = mon
    end
  end

  -- boxes.  wCurBox's box lives in the sBox working buffer, NOT in its
  -- numbered bank-2/3 slot (which the game only refreshes when the player
  -- changes box), so reading the slot for the active box would resurrect a
  -- stale copy.
  local curBox = bit.band(u8(bytes, O.curBox), 0x0F) + 1
  if curBox < 1 or curBox > NUM_BOXES then curBox = 1 end
  for n = 1, NUM_BOXES do
    if n == curBox then
      save.boxes[n] = decodeBoxRegion(bytes, O.curBoxData, cw)
    else
      save.boxes[n] = decodeBoxRegion(bytes, boxSlotOffset(n), cw)
    end
  end
  save.currentBox = curBox

  -- day care
  local manByte, ladyByte = u8(bytes, O.dayCareMan), u8(bytes, O.dayCareLady)
  local breed = { steps = u8(bytes, O.stepsToEgg), met = {} }
  if hasBit(manByte, DAYCAREMAN_HAS_MON) then
    local mon = decodePen(bytes, O.breedMon1, O.breedMon1Nick, O.breedMon1OT, cw)
    if mon then breed[1] = { mon = mon, steps = 0, depositLevel = mon.level } end
  end
  if hasBit(ladyByte, DAYCARELADY_HAS_MON) then
    local mon = decodePen(bytes, O.breedMon2, O.breedMon2Nick, O.breedMon2OT, cw)
    if mon then breed[2] = { mon = mon, steps = 0, depositLevel = mon.level } end
  end
  if hasBit(manByte, DAYCAREMAN_HAS_EGG) then
    local egg = decodePen(bytes, O.eggMon, O.eggMonNick, O.eggMonOT, cw)
    if egg then
      egg.isEgg = true
      egg.eggSteps = (egg.happiness or 0) * 256
      egg.happiness = nil
      breed.egg = egg
    end
  end
  breed.met[1] = hasBit(manByte, DAYCAREMAN_ACTIVE) or nil
  breed.met[2] = hasBit(ladyByte, DAYCARELADY_ACTIVE) or nil
  save.daycare = { breed = breed }
  -- FLAG_G2_0005/0006/0007 are the three EngineFlags rows the Route 34
  -- callbacks read to decide whether to show the yard Pokemon and stand the
  -- MAN OUTSIDE at the fence.  Derive them from the pens we just read so
  -- they can never disagree with them.
  local okDayCare, DayCare = pcall(require, "src.pokemon.DayCare")
  if okDayCare and type(DayCare) == "table" then DayCare.syncFlags(save) end

  -- map + position
  local group, number = u8(bytes, O.mapGroup), u8(bytes, O.mapNumber)
  local mapId = cw.mapsByGroupNumber[group * 256 + number]
  if mapId then
    save.player.map = mapId
    save.player.x = u8(bytes, O.xCoord)
    save.player.y = u8(bytes, O.yCoord)
  elseif not cw.mapsHaveGroups then
    warn("this ROM cache predates map group/number extraction, so the saved "
         .. "location could not be resolved -- re-import the ROM to fix it")
  else
    warn(("unknown map (group %d, number %d), defaulting spawn"):format(group, number))
  end

  -- play time: this project stores save.playTime as a single float of
  -- SECONDS (src/core/Game.lua accumulates dt each frame).  wGameTimeHours
  -- is a big-endian word; minutes/seconds/frames are single bytes.
  save.playTime = u16be(bytes, O.gameTimeHours) * 3600
                + u8(bytes, O.gameTimeMins) * 60
                + u8(bytes, O.gameTimeSecs)
                + u8(bytes, O.gameTimeFrames) / 60

  save.warnings = warnings
  save.rawImport = bytes -- template for a later encode(); see the file header
  return save
end

-- ------------------------------------------------------------------
-- encode: save.lua-shaped table -> raw 32768-byte SRAM string
-- ------------------------------------------------------------------

function Gen2Save.encode(save, data, template)
  assert(charmap, "Gen2Save.setCharmap must be called before encode")
  local cw = Gen2Save.crosswalks(data)
  local src = template or save.rawImport
  local buf = {}
  if src and #src == Gen2Save.SAVE_SIZE then
    for i = 1, Gen2Save.SAVE_SIZE do buf[i] = src:sub(i, i) end
  else
    local zero = string.char(0)
    for i = 1, Gen2Save.SAVE_SIZE do buf[i] = zero end
  end

  local player = save.player or {}
  local playerName = player.name or "GOLD"
  encodeName(buf, O.playerName, NAME_LENGTH, playerName)
  encodeName(buf, O.rivalName, NAME_LENGTH, player.rival or "SILVER")
  if player.mom then encodeName(buf, O.momName, NAME_LENGTH, player.mom) end
  setU16be(buf, O.playerId, player.id or 0)
  setU24be(buf, O.money, math.min(math.floor(save.money or 0), 999999))
  setU16be(buf, O.coins, math.min(math.floor(save.coins or 0), 9999))
  -- wPlayerGender: only bit 0 is the gender, so keep whatever else the
  -- template byte carried rather than zeroing the rest of it.  buf is a table
  -- of one-character strings at this point, not a byte string, so read it the
  -- way bitSet does rather than through u8.
  do
    local cur = buf[O.gender + 1]
    setByte(buf, O.gender,
      withBit(cur and cur:byte() or 0, 0, player.gender == "girl"))
  end

  -- badges
  local johto, kanto = 0, 0
  for i = 0, 7 do
    johto = withBit(johto, i, (save.flags or {})[JOHTO_BADGE_BY_BIT[i]] and true or false)
    kanto = withBit(kanto, i, (save.flags or {})[KANTO_BADGE_BY_BIT[i]] and true or false)
  end
  setByte(buf, O.johtoBadges, johto)
  setByte(buf, O.kantoBadges, kanto)

  -- event flags: this port's save is the only authority, so a flag it does
  -- not hold clears the template's bit rather than surviving the export
  if save.flags then
    for n = 0, NUM_EVENT_FLAGS - 1 do
      bitSet(buf, O.eventFlags, n, save.flags[eventFlagName(n)] and true or false)
    end
    -- ...and the scene bytes alongside them, or exporting and re-importing
    -- would drop the player back at scene 0 on every map that has one.
    local sceneVars = data and data.field and data.field.mapSceneVars
    if type(sceneVars) == "table" then
      for mapId, address in pairs(sceneVars) do
        local scene = save.g2Scenes and save.g2Scenes[mapId]
        if type(address) == "number" and type(scene) == "number" then
          setByte(buf, sram(address), scene)
        end
      end
    end
    for _, row in ipairs(engineFlagRows(data) or {}) do
      local off, bitIndex = engineFlagSlot(row)
      if off then
        local cur = buf[off + 1]
        setByte(buf, off, withBit(cur and cur:byte() or 0, bitIndex,
                                  save.flags[engineFlagName(row.row)] and true or false))
      end
    end
  end

  -- wVisitedSpawns: the FLY destinations this save has reached
  local spawnFlags = data and data.field and data.field.spawnFlags
  if type(spawnFlags) == "table" then
    local visited = save.visited or {}
    for _, entry in ipairs(spawnFlags) do
      if entry.map then
        bitSet(buf, O.visitedSpawns, entry.bit, visited[entry.map] and true or false)
      end
    end
  end

  -- pokedex
  for dex, species in pairs(cw.pokemonByDex) do
    local idx = dex - 1
    bitSet(buf, O.pokedexCaught, idx,
           (save.pokedex and save.pokedex.owned and save.pokedex.owned[species]) and true or false)
    bitSet(buf, O.pokedexSeen, idx,
           (save.pokedex and save.pokedex.seen and save.pokedex.seen[species]) and true or false)
  end

  -- bag: split the flat inventory back into the four pockets by def.pocket
  local inventory = save.inventory or {}
  local pockets = { ITEM = {}, KEY_ITEM = {}, BALL = {}, TM_HM = {} }
  local placed = {}
  local function place(id)
    if placed[id] or not inventory[id] then return end
    local p = pockets[pocketOf(cw, id)]
    if p then p[#p + 1] = id; placed[id] = true end
  end
  for _, id in ipairs(save.bagOrder or {}) do place(id) end
  for id in pairs(inventory) do place(id) end

  setByte(buf, O.numItems, encodePairList(buf, O.items, MAX_ITEMS, pockets.ITEM, inventory, cw))
  setByte(buf, O.numKeyItems, encodeIdList(buf, O.keyItems, MAX_KEY_ITEMS, pockets.KEY_ITEM, cw))
  setByte(buf, O.numBalls, encodePairList(buf, O.balls, MAX_BALLS, pockets.BALL, inventory, cw))
  for slot = 0, NUM_TMS + NUM_HMS - 1 do
    local id = cw.itemsByIndex[machineItemIndex(slot)]
    setByte(buf, O.tmsHms + slot, math.min(id and inventory[id] or 0, 99))
  end

  local pcItems = save.pcItems or {}
  local pcOrder, pcSeen = {}, {}
  for _, id in ipairs(save.pcOrder or {}) do
    if pcItems[id] and not pcSeen[id] then pcOrder[#pcOrder + 1] = id; pcSeen[id] = true end
  end
  for id in pairs(pcItems) do
    if not pcSeen[id] then pcOrder[#pcOrder + 1] = id; pcSeen[id] = true end
  end
  setByte(buf, O.numPCItems, encodePairList(buf, O.pcItems, MAX_PC_ITEMS, pcOrder, pcItems, cw))

  -- party
  local party = save.party or {}
  local partyN = math.min(#party, PARTY_LENGTH)
  setByte(buf, O.partyCount, partyN)
  for i = 0, partyN - 1 do
    local mon = party[i + 1]
    encodeMon(buf, O.partyMons + i * PARTY_STRUCT_SIZE, mon, true, cw)
    setByte(buf, O.partySpecies + i,
            mon.isEgg and EGG_SPECIES_BYTE or (cw.pokemonIndex[mon.species] or 0))
    encodeName(buf, O.partyMonOT + i * NAME_LENGTH, NAME_LENGTH, mon.ot or playerName)
    encodeName(buf, O.partyMonNicks + i * NAME_LENGTH, NAME_LENGTH,
               mon.nickname or speciesName(cw, mon.species))
  end
  setByte(buf, O.partySpecies + partyN, 0xFF)

  -- boxes: the active box goes to BOTH sBox and its numbered slot, which is
  -- the invariant the game itself maintains on every PC visit
  local boxes = save.boxes or {}
  local curBox = math.max(1, math.min(NUM_BOXES, save.currentBox or 1))
  setByte(buf, O.curBox, curBox - 1)
  for n = 1, NUM_BOXES do
    local mons = boxes[n] or {}
    encodeBoxRegion(buf, boxSlotOffset(n), mons, cw, playerName)
    if n == curBox then encodeBoxRegion(buf, O.curBoxData, mons, cw, playerName) end
  end

  -- day care
  local breed = (save.daycare and save.daycare.breed) or {}
  local manMon = breed[1] and breed[1].mon or nil
  local ladyMon = breed[2] and breed[2].mon or nil
  local manByte = u8(src or "", O.dayCareMan)
  local ladyByte = u8(src or "", O.dayCareLady)
  manByte = withBit(manByte, DAYCAREMAN_HAS_MON, manMon ~= nil)
  manByte = withBit(manByte, DAYCAREMAN_HAS_EGG, breed.egg ~= nil)
  manByte = withBit(manByte, DAYCAREMAN_ACTIVE, (breed.met and breed.met[1]) and true or false)
  ladyByte = withBit(ladyByte, DAYCARELADY_HAS_MON, ladyMon ~= nil)
  ladyByte = withBit(ladyByte, DAYCARELADY_ACTIVE, (breed.met and breed.met[2]) and true or false)
  setByte(buf, O.dayCareMan, manByte)
  setByte(buf, O.dayCareLady, ladyByte)
  setByte(buf, O.stepsToEgg, math.min(math.floor(breed.steps or 0), 255))
  encodePen(buf, O.breedMon1, O.breedMon1Nick, O.breedMon1OT, manMon, cw, playerName)
  encodePen(buf, O.breedMon2, O.breedMon2Nick, O.breedMon2OT, ladyMon, cw, playerName)
  encodePen(buf, O.eggMon, O.eggMonNick, O.eggMonOT, breed.egg, cw, playerName)

  -- map + position
  local mapDef = player.map and cw.mapDefs[player.map] or nil
  if mapDef and mapDef.group and mapDef.number then
    setByte(buf, O.mapGroup, mapDef.group)
    setByte(buf, O.mapNumber, mapDef.number)
    setByte(buf, O.xCoord, player.x or 0)
    setByte(buf, O.yCoord, player.y or 0)
  end

  -- play time
  local t = math.max(0, tonumber(save.playTime) or 0)
  local hours = math.floor(t / 3600)
  setU16be(buf, O.gameTimeHours, math.min(hours, 999))
  setByte(buf, O.gameTimeMins, math.floor(t / 60) % 60)
  setByte(buf, O.gameTimeSecs, math.floor(t) % 60)
  setByte(buf, O.gameTimeFrames, math.floor((t % 1) * 60))

  -- check values then the checksum, in that order: the checksum covers
  -- sCheckValue1 but stops before sCheckValue2
  setByte(buf, O.checkValue1, CHECK_VALUE_1)
  setByte(buf, O.checkValue2, CHECK_VALUE_2)
  setU16le(buf, O.checksum, checksumBuf(buf, O.checksumStart, O.checksumEnd))

  return table.concat(buf)
end

return Gen2Save
