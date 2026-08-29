-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Generation 3 (Game Boy Advance) cartridge extractor.
--
-- WHY THIS IS NOT A BRANCH INSIDE RomExtractorGen2.
--
-- Gold, Silver, Crystal, Prism and Polished Crystal share one extractor
-- because they share a machine: banked ROM, 2bpp tiles, four greys, one text
-- engine, a `layout` key per cartridge for the strides that moved.  Emerald
-- shares none of that.  It is flat-addressed, 4bpp against sixteen colours of
-- 15-bit BGR, its assets are LZ77-compressed, its species are numbered in an
-- order that is not the Pokedex, and it has concepts the Gen 2 tables have no
-- column for at all -- abilities, natures, a split Special stat, EVs.
--
-- And it has no symbol table.  Every address this reads comes from
-- tools/gen3_discover.py, which finds each table structurally against the
-- cartridge and refuses to emit a manifest if any one of them is unproved.
-- Nothing here hardcodes an address; if the manifest lacks a symbol, the
-- stage that needs it says so and is skipped rather than reading whatever
-- happens to be at offset zero.
--
-- The CONTRACT is the same as Gen 2's, because the runtime's is: `new` takes
-- (romData, version, manifest, progress), `run` walks DATA_STAGES then
-- ASSET_STAGES, `write(name, table)` lands a module in data/generated, and
-- `saveImage` lands a PNG in assets/generated.

local RomGba = require("src.import.RomGba")
local Gen3ScriptOps = require("src.import.Gen3ScriptOps")
local LuaWriter = require("src.import.LuaWriter")
local ImageWriter = require("src.import.ImageWriter")
local Logger = require("src.core.Logger")

local RomExtractorGen3 = {}
RomExtractorGen3.__index = RomExtractorGen3

-- The progress denominator.  Kept honest with the two stage lists below: a
-- mismatch does not break anything, it just makes the bar lie, which is the
-- kind of small wrongness that survives for months.
local STAGE_COUNT = 26

function RomExtractorGen3.new(romData, version, manifest, progress)
  return setmetatable({
    rom = RomGba.new(romData),
    version = version,
    manifest = manifest or {},
    symbols = (manifest or {}).symbols or {},
    layout = (manifest or {}).layout or {},
    progress = progress,
    stage = 0,
    counts = {},
  }, RomExtractorGen3)
end

-- ---------------------------------------------------------------------------
-- Manifest access
-- ---------------------------------------------------------------------------

-- A Gen 3 symbol is a FLAT offset, not Gen 2's [bank, address] pair: there
-- are no banks to name.  Returns nil rather than raising, so a stage can
-- degrade to "not extracted" instead of taking the whole import down.
function RomExtractorGen3:symbol(name)
  local value = self.symbols[name]
  if type(value) == "number" then return value end
  -- tolerate the Gen 2 pair shape if a manifest is ever written that way
  if type(value) == "table" and value[2] then return value[2] end
  return nil
end

function RomExtractorGen3:need(name, stage)
  local off = self:symbol(name)
  if not off then
    Logger.warn("gen3: %s is not in the manifest -- %s skipped", name, stage)
  end
  return off
end

function RomExtractorGen3:layoutValue(key, default)
  local v = tonumber(self.layout[key])
  return v or default
end

-- ---------------------------------------------------------------------------
-- Progress, output
-- ---------------------------------------------------------------------------

function RomExtractorGen3:beginStage(name)
  self.stage = self.stage + 1
  if self.progress then
    self.progress(self.stage - 1, STAGE_COUNT, name, 0, 1)
  end
end

function RomExtractorGen3:tick(name, current, total)
  if self.progress and total > 0 then
    self.progress(self.stage - 1 + current / total, STAGE_COUNT, name,
                  current, total)
  end
end

function RomExtractorGen3:write(name, value)
  LuaWriter.write("data/generated/" .. name .. ".lua", value)
end

function RomExtractorGen3:saveImage(image, relative)
  ImageWriter.save(image, "assets/generated/" .. relative)
end

-- ---------------------------------------------------------------------------
-- Text
--
-- Only the printable half is needed by the tables below -- names are plain
-- character runs closed by $FF.  The control block ($FA-$FE) belongs to the
-- dialogue decoder, which is its own piece of work; a name that contains one
-- would be a bug in the table, not something to paper over here.
-- ---------------------------------------------------------------------------

local EOS, NEWLINE = 0xFF, 0xFE

-- THE CONTROL BLOCK, verified by decoding the cartridge's own dialogue and
-- reading whether it makes sense -- not by assuming pokeemerald's constants.
--
--   $FA  scroll up one line and carry on (rendered "\v", as Gen 2's does)
--   $FB  wait for A, then clear the box and carry on ("\f")
--   $FC  an EXTENDED command: one selector byte, then that command's own
--        operands.  Rare -- 165 uses in the whole cartridge.
--   $FD  a PLACEHOLDER: one id byte naming what to splice in
--   $FE  line break
--   $FF  end of string
--
-- The placeholder ids were each confirmed against a line that uses them:
-- "{PLAYER} received the EFFORT RIBBON", "Oh, {RIVAL} went out to ROUTE 103",
-- and -- the decisive one -- "...to notice that you came\vto visit,
-- {PLAYER}{KUN}", which is exactly how Gen 3 spells the player's name plus
-- the honorific that is empty in English.
local TEXT_SCROLL, TEXT_PAGE = 0xFA, 0xFB
local TEXT_EXTENDED, TEXT_PLACEHOLDER = 0xFC, 0xFD

local PLACEHOLDERS = {
  [0x00] = "{UNKNOWN}", [0x01] = "{PLAYER}",
  [0x02] = "{VAR1}", [0x03] = "{VAR2}", [0x04] = "{VAR3}",
  [0x05] = "{KUN}", [0x06] = "{RIVAL}", [0x07] = "{VERSION}",
  [0x08] = "{AQUA}", [0x09] = "{MAGMA}", [0x0A] = "{ARCHIE}",
  [0x0B] = "{MAXIE}", [0x0C] = "{KYOGRE}", [0x0D] = "{GROUDON}",
}

-- How many operand bytes each $FC command takes, after its selector.  A wrong
-- width here does not raise -- it shifts the rest of the string and the line
-- comes out as garbage from that point on, which is the same failure mode a
-- wrong script operand width has.
local EXTENDED_OPERANDS = {
  [0x01] = 1,   -- colour
  [0x02] = 1,   -- highlight
  [0x03] = 1,   -- shadow
  [0x04] = 3,   -- colour + highlight + shadow together
  [0x05] = 1,   -- palette
  [0x06] = 1,   -- font size
  [0x07] = 0,   -- reset size
  [0x08] = 1,   -- pause n frames
  [0x09] = 0,   -- pause until the player presses A
  [0x0A] = 0,   -- wait for the sound effect to finish
  [0x0B] = 2,   -- play bgm
  [0x0C] = 1,   -- escape: the next byte is a literal, not a control code
  [0x0D] = 1,   -- shift right
  [0x0E] = 1,   -- shift down
  [0x0F] = 0,   -- fill window
  [0x10] = 2,   -- play sound effect
  [0x11] = 1,   -- clear n pixels
  [0x12] = 1,   -- skip to column n
  [0x13] = 1,   -- clear to column n
  [0x14] = 1,   -- minimum letter spacing
  [0x15] = 0, [0x16] = 0,   -- japanese / latin
  [0x17] = 0, [0x18] = 0,   -- pause and resume music
}

function RomExtractorGen3:charmap()
  if self._charmap then return self._charmap end
  local map = {}
  for key, glyph in pairs(self.manifest.charmap or {}) do
    local code = tonumber(key)
    if code then map[code] = glyph end
  end
  self._charmap = map
  return map
end

-- A NAME or other plain field: characters and line breaks only.  A control
-- code in one of these would be a bug in the table rather than something to
-- render, so they are spelled out as {BYTE:xx} instead of interpreted.
function RomExtractorGen3:readString(off, maxLength)
  local map = self:charmap()
  local out = {}
  for i = 0, (maxLength or 64) - 1 do
    local b = self.rom:u8(off + i)
    if b == EOS then break end
    if b == NEWLINE then
      out[#out + 1] = "\n"
    else
      out[#out + 1] = map[b] or ("{BYTE:%02X}"):format(b)
    end
  end
  return table.concat(out)
end

-- DIALOGUE: the full control block.  Returns the decoded text and how many
-- bytes it consumed, or nil when the run is not text at all -- which is what
-- makes it usable as a probe over unknown ROM as well as a reader for a
-- pointer that is known good.
function RomExtractorGen3:readText(off, maxBytes)
  local map = self:charmap()
  local out = {}
  local i = 0
  local limit = maxBytes or 1024
  while i < limit do
    local ok, b = pcall(self.rom.u8, self.rom, off + i)
    if not ok then return nil end
    if b == EOS then
      return table.concat(out), i + 1
    elseif b == NEWLINE then
      out[#out + 1] = "\n"; i = i + 1
    elseif b == TEXT_SCROLL then
      out[#out + 1] = "\v"; i = i + 1
    elseif b == TEXT_PAGE then
      out[#out + 1] = "\f"; i = i + 1
    elseif b == TEXT_PLACEHOLDER then
      -- Only $00-$0D are placeholders.  Spelling an unknown id as
      -- "{PLACEHOLDER:BF}" and carrying on made the SCAN believe graphics data
      -- was dialogue -- the token's own letters satisfied the letter gate.
      local id = self.rom:u8(off + i + 1)
      local name = PLACEHOLDERS[id]
      if not name then return nil end
      out[#out + 1] = name
      i = i + 2
    elseif b == TEXT_EXTENDED then
      local cmd = self.rom:u8(off + i + 1)
      local operands = EXTENDED_OPERANDS[cmd]
      if not operands then return nil end     -- an unknown command means this
      if cmd == 0x0C then                     -- was never a string
        -- ESCAPE: the operand is a literal byte, control code or not
        out[#out + 1] = map[self.rom:u8(off + i + 2)] or ""
      end
      i = i + 2 + operands
    else
      local glyph = map[b]
      if glyph == nil then return nil end
      out[#out + 1] = glyph
      i = i + 1
    end
  end
  return nil
end

-- A fixed-width name table: `count` slots of `stride` bytes each.
function RomExtractorGen3:names(symbolName, stride, count, stage)
  local base = self:need(symbolName, stage)
  if not base then return nil end
  local out = {}
  for i = 0, count - 1 do
    out[i] = self:readString(base + i * stride, stride)
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Identifiers
--
-- The engine keys everything by a STRING id, and Gen 3's names are not
-- unique-safe on their own: "?" appears 25 times in the species table (the
-- unused internal slots), and names carry spaces, the cartridge's own e-acute
-- and, in the item table, punctuation.  So an id is the name upper-cased and
-- reduced to [A-Z0-9_], with the internal index appended whenever that would
-- otherwise collide -- never silently overwriting a row.
-- ---------------------------------------------------------------------------

local function slug(name)
  local s = tostring(name or ""):upper()
  s = s:gsub("\195\169", "E")          -- the cartridge's e-acute
  s = s:gsub("[^A-Z0-9]+", "_")
  s = s:gsub("^_+", ""):gsub("_+$", "")
  return s
end

local function uniqueId(taken, base, index, prefix)
  if base == "" or base == nil then
    base = ("%s_%03d"):format(prefix, index)
  end
  if not taken[base] then
    taken[base] = true
    return base
  end
  local id = ("%s_%03d"):format(base, index)
  taken[id] = true
  return id
end

-- ---------------------------------------------------------------------------
-- STAGE: constants
--
-- The order arrays every other module is indexed against.  Gen 3's species
-- numbering is INTERNAL: 1-251 agree with the National Dex, 252-276 are 25
-- unused slots the cartridge fills with "?", and Hoenn runs 277-411.  The
-- unused slots are kept in the order array rather than skipped, because every
-- other table in the ROM is indexed by that same internal number -- dropping
-- them would shift all of Hoenn by 25.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractConstants()
  self:beginStage("Gen3 constants")
  local L = self.layoutValue
  local numSpecies = self:layoutValue("numSpecies", 412)
  local numMoves = self:layoutValue("numMoves", 355)
  local numItems = self:layoutValue("numItems", 377)
  local numTypes = self:layoutValue("numTypes", 18)
  local numAbilities = self:layoutValue("numAbilities", 78)

  local speciesNames = self:names("gSpeciesNames",
    self:layoutValue("speciesNameLength", 11), numSpecies, "constants")
  local moveNames = self:names("gMoveNames",
    self:layoutValue("moveNameLength", 13), numMoves, "constants")
  local typeNames = self:names("gTypeNames",
    self:layoutValue("typeNameLength", 7), numTypes, "constants")
  local abilityNames = self:names("gAbilityNames",
    self:layoutValue("abilityNameLength", 13), numAbilities, "constants")

  local constants = { source = "ROM:Emerald" }

  local speciesIds, taken = {}, {}
  if speciesNames then
    for i = 1, numSpecies - 1 do
      speciesIds[i] = uniqueId(taken, slug(speciesNames[i]), i, "SPECIES")
    end
    constants.speciesOrder = {}
    for i = 1, numSpecies - 1 do constants.speciesOrder[i] = speciesIds[i] end
  end

  local moveIds, mtaken = {}, {}
  if moveNames then
    for i = 1, numMoves - 1 do
      moveIds[i] = uniqueId(mtaken, slug(moveNames[i]), i, "MOVE")
    end
    constants.moveOrder = {}
    for i = 1, numMoves - 1 do constants.moveOrder[i] = moveIds[i] end
  end

  if typeNames then
    constants.types = {}
    constants.typeOrder = {}
    for i = 0, numTypes - 1 do
      local id = slug(typeNames[i])
      if id == "" then id = ("TYPE_%02d"):format(i) end
      constants.typeOrder[i + 1] = id
      constants.types[id] = { id = id, index = i, name = typeNames[i] }
    end
  end

  if abilityNames then
    constants.abilities = {}
    constants.abilityOrder = {}
    local ataken = {}
    for i = 0, numAbilities - 1 do
      local id = uniqueId(ataken, slug(abilityNames[i]), i, "ABILITY")
      constants.abilityOrder[i + 1] = id
      constants.abilities[id] = { id = id, index = i, name = abilityNames[i] }
    end
  end

  -- kept on the extractor so later stages share one numbering
  self._speciesIds, self._moveIds = speciesIds, moveIds
  self._constants = constants
  self:write("constants", constants)
  self.counts.species = speciesIds and #speciesIds or 0
  self.counts.moves = moveIds and #moveIds or 0
  Logger.info("Gen3 constants: %d species, %d moves, %d types, %d abilities",
              self.counts.species, self.counts.moves, numTypes, numAbilities)
end

-- ---------------------------------------------------------------------------
-- STAGE: moves
--
-- struct BattleMove is twelve bytes: effect, power, type, accuracy, pp,
-- secondaryEffectChance, target, priority (SIGNED), flags, then padding.
-- Accuracy and the secondary chance are already percentages here, unlike
-- Gen 1/2's 0-255 scaling -- so nothing is divided on the way out.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractMoves()
  self:beginStage("Gen3 moves")
  local base = self:need("gBattleMoves", "moves")
  local names = self:names("gMoveNames",
    self:layoutValue("moveNameLength", 13),
    self:layoutValue("numMoves", 355), "moves")
  if not (base and names and self._moveIds) then return end

  local stride = self:layoutValue("battleMoveEntry", 12)
  local types = (self._constants or {}).typeOrder or {}
  local out = {}
  local count = self:layoutValue("numMoves", 355) - 1
  for i = 1, count do
    local o = base + i * stride
    local id = self._moveIds[i]
    out[id] = {
      id = id,
      index = i,
      name = names[i],
      effect = self.rom:u8(o),
      power = self.rom:u8(o + 1),
      type = types[self.rom:u8(o + 2) + 1] or self.rom:u8(o + 2),
      accuracy = self.rom:u8(o + 3),
      pp = self.rom:u8(o + 4),
      secondaryChance = self.rom:u8(o + 5),
      target = self.rom:u8(o + 6),
      priority = self.rom:s8(o + 7),
      flags = self.rom:u8(o + 8),
      source = ("ROM:gBattleMoves[%d]"):format(i),
    }
    if i % 64 == 0 then self:tick("Gen3 moves", i, count) end
  end
  self:write("moves", out)
  Logger.info("Gen3 moves: %d from ROM", count)
end

-- ---------------------------------------------------------------------------
-- STAGE: pokemon
--
-- struct BaseStats is 28 bytes.  The Special split is the headline change --
-- Gen 1/2 have one Special, Gen 3 has spAttack and spDefense as separate
-- base stats, separate EVs and separate IVs -- but the row also carries two
-- ABILITIES, an egg-cycle count, a body colour and a safari flee rate, none
-- of which the Gen 2 table has a column for.
--
-- Learnsets are a u16 list per species, each entry (level << 9) | move, ended
-- by $FFFF.  Evolutions are five 8-byte {method, param, target, padding} rows
-- per species, most of them empty.
-- ---------------------------------------------------------------------------

local GROWTH_RATES = {
  [0] = "MEDIUM_FAST", "ERRATIC", "FLUCTUATING", "MEDIUM_SLOW", "FAST", "SLOW",
}

function RomExtractorGen3:extractPokemon()
  self:beginStage("Gen3 Pokemon")
  local base = self:need("gBaseStats", "pokemon")
  local nameLen = self:layoutValue("speciesNameLength", 11)
  local names = self:names("gSpeciesNames", nameLen,
                           self:layoutValue("numSpecies", 412), "pokemon")
  if not (base and names and self._speciesIds) then return end

  local stride = self:layoutValue("baseStatsEntry", 28)
  local types = (self._constants or {}).typeOrder or {}
  local abilities = (self._constants or {}).abilityOrder or {}
  local learnBase = self:symbol("gLevelUpLearnsets")
  local evoBase = self:symbol("gEvolutionTable")
  local dexBase = self:symbol("gSpeciesToNationalPokedexNum")
  local evoStride = self:layoutValue("evolutionEntry", 8)
    * self:layoutValue("evolutionsPerSpecies", 5)

  local out = {}
  local count = self:layoutValue("numSpecies", 412) - 1
  local blanks = 0
  for i = 1, count do
    local id = self._speciesIds[i]
    local o = base + i * stride
    local name = names[i]
    -- the 25 unused internal slots are spelled "?" and carry a zero row;
    -- they are KEPT so every ROM table stays index-aligned, but marked so
    -- nothing tries to show them
    local unused = name:gsub("%?", "") == ""
    if unused then blanks = blanks + 1 end

    local def = {
      id = id,
      index = i,
      name = name,
      unused = unused or nil,
      -- The KEY SPELLING matters more than it looks.  src/pokemon/Stats.lua
      -- decides Gen 1's single Special against Gen 2's split structurally --
      -- `if base.spatk and base.spdef` -- so a Gen 3 row spelled spAttack /
      -- spDefense takes the Gen 1 branch and silently produces a Pokemon with
      -- no special stats at all.  `special` is carried as well because the
      -- Gen 1 path and several UI screens read it directly.
      baseStats = {
        hp = self.rom:u8(o), attack = self.rom:u8(o + 1),
        defense = self.rom:u8(o + 2), speed = self.rom:u8(o + 3),
        spatk = self.rom:u8(o + 4), spdef = self.rom:u8(o + 5),
        special = self.rom:u8(o + 4),
      },
      types = { types[self.rom:u8(o + 6) + 1] or self.rom:u8(o + 6),
                types[self.rom:u8(o + 7) + 1] or self.rom:u8(o + 7) },
      type1 = types[self.rom:u8(o + 6) + 1] or self.rom:u8(o + 6),
      type2 = types[self.rom:u8(o + 7) + 1] or self.rom:u8(o + 7),
      catchRate = self.rom:u8(o + 8),
      -- baseExp is what src/battle/Experience.lua reads; expYield is kept
      -- under the cartridge's own name for anything that wants it
      baseExp = self.rom:u8(o + 9),
      expYield = self.rom:u8(o + 9),
      evYield = self.rom:u16(o + 10),
      heldItems = { self.rom:u16(o + 12), self.rom:u16(o + 14) },
      genderRatio = self.rom:u8(o + 16),
      eggCycles = self.rom:u8(o + 17),
      friendship = self.rom:u8(o + 18),
      growthRate = GROWTH_RATES[self.rom:u8(o + 19)] or self.rom:u8(o + 19),
      eggGroups = { self.rom:u8(o + 20), self.rom:u8(o + 21) },
      abilities = { abilities[self.rom:u8(o + 22) + 1],
                    abilities[self.rom:u8(o + 23) + 1] },
      safariFleeRate = self.rom:u8(o + 24),
      bodyColor = self.rom:u8(o + 25) % 128,
      source = ("ROM:gBaseStats[%d]"):format(i),
    }
    -- ability slot 0 is NONE and reads back as the first ability name; a
    -- second slot of 0 means "no second ability", not "a duplicate of the
    -- first", so it has to be dropped rather than carried
    if self.rom:u8(o + 23) == 0 then def.abilities[2] = nil end

    if dexBase and i <= 411 then
      def.dex = self.rom:u16(dexBase + (i - 1) * 2)
    end

    if learnBase then
      local p = self.rom:pointer(learnBase + i * 4)
      if p then
        local moves = {}
        for k = 0, 63 do
          local word = self.rom:u16(p + k * 2)
          if word == 0xFFFF then break end
          local level = math.floor(word / 512)
          local move = word % 512
          moves[#moves + 1] = { level = level,
                                move = self._moveIds and self._moveIds[move] or move }
        end
        if #moves > 0 then
          def.learnset = moves
          -- src/pokemon/Pokemon.lua builds a new mon's moveset from
          -- level1Moves, falling back to walking the learnset; Gen 1 and
          -- Gen 2 both emit it, so emit it here too rather than leaving
          -- every Gen 3 starter with an empty moveset.
          local starting = {}
          for _, entry in ipairs(moves) do
            if entry.level <= 1 then starting[#starting + 1] = entry.move end
          end
          if #starting > 0 then def.level1Moves = starting end
        end
      end
    end

    if evoBase then
      local evos = {}
      for k = 0, self:layoutValue("evolutionsPerSpecies", 5) - 1 do
        local e = evoBase + i * evoStride + k * self:layoutValue("evolutionEntry", 8)
        local method = self.rom:u16(e)
        if method ~= 0 then
          evos[#evos + 1] = {
            method = method,
            param = self.rom:u16(e + 2),
            into = self._speciesIds[self.rom:u16(e + 4)] or self.rom:u16(e + 4),
          }
        end
      end
      if #evos > 0 then def.evolutions = evos end
    end

    out[id] = def
    if i % 32 == 0 then self:tick("Gen3 Pokemon", i, count) end
  end

  self._pokemon = out
  self:write("pokemon", out)
  Logger.info("Gen3 Pokemon: %d species (%d unused internal slots)",
              count - blanks, blanks)
end

-- ---------------------------------------------------------------------------
-- STAGE: items
--
-- struct Item is 44 bytes: a 14-byte name, then the item's OWN id (which is
-- how the table was verified), price, hold effect and parameter, a pointer to
-- its description, importance, the pocket, and the use handlers.
-- ---------------------------------------------------------------------------

local POCKETS = {
  [1] = "ITEM", [2] = "BALL", [3] = "TM_HM", [4] = "BERRY", [5] = "KEY_ITEM",
}

function RomExtractorGen3:extractItems()
  self:beginStage("Gen3 items")
  local base = self:need("gItems", "items")
  if not base then return end
  local stride = self:layoutValue("itemEntry", 44)
  local count = self:layoutValue("numItems", 377)

  local out, taken = {}, {}
  for i = 0, count - 1 do
    local o = base + i * stride
    local name = self:readString(o, 14)
    local id = uniqueId(taken, slug(name), i, "ITEM")
    local descPtr = self.rom:pointer(o + 20)
    out[id] = {
      id = id,
      index = i,
      name = name,
      price = self.rom:u16(o + 16),
      holdEffect = self.rom:u8(o + 18),
      holdEffectParam = self.rom:u8(o + 19),
      description = descPtr and self:readString(descPtr, 160) or nil,
      importance = self.rom:u8(o + 24),
      pocket = POCKETS[self.rom:u8(o + 26)],
      source = ("ROM:gItems[%d]"):format(i),
    }
    if i % 64 == 0 then self:tick("Gen3 items", i, count) end
  end
  self:write("items", out)
  Logger.info("Gen3 items: %d from ROM", count)
end

-- ---------------------------------------------------------------------------
-- STAGE: type chart
--
-- gTypeEffectiveness lists ONLY the non-neutral matchups -- anything absent
-- is 1x -- as three-byte {attacker, defender, multiplier * 10} rows.  A
-- FE FE 00 marker splits the table: rows after it are the ones Foresight (and
-- Scrappy) cancel, which is why the immunities sit at the end.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractTypeChart()
  self:beginStage("Gen3 type chart")
  local base = self:need("gTypeEffectiveness", "type chart")
  if not base then return end
  local types = (self._constants or {}).typeOrder or {}
  local matchups, foresight = {}, false
  for k = 0, 255 do
    local o = base + k * 3
    local a, b, mul = self.rom:u8(o), self.rom:u8(o + 1), self.rom:u8(o + 2)
    if a == 0xFF and b == 0xFF then break end
    if a == 0xFE and b == 0xFE then
      foresight = true
    else
      matchups[#matchups + 1] = {
        attacker = types[a + 1] or a,
        defender = types[b + 1] or b,
        -- x10 INTEGERS, not a float.  src/battle/Damage.lua applies each
        -- row as `math.floor(d * m / 10)`, so handing it 0.5 divides by ten
        -- again and makes every resisted hit do a tenth of the damage it
        -- should.  The cartridge already stores 0/5/20, which is the same
        -- scale, so this is a pass-through and not a conversion.
        multiplier = mul,
        -- everything past the marker is cancelled by Foresight, which is the
        -- only reason the table is ordered the way it is
        foresightCancels = foresight or nil,
      }
    end
  end
  -- The PHYSICAL/SPECIAL SPLIT is by type in Gen 3, exactly as in Gen 1 and
  -- Gen 2 -- the per-move split only arrives in Gen 4.  src/battle/Damage.lua
  -- reads it through TypeChart.category(move.type), and with the key absent it
  -- calls every move physical and warns once per type, which would have made
  -- every special attacker in Hoenn hit off the wrong stat.
  --
  -- The boundary is not a magic number: the special types are the ones from
  -- FIRE onward, and the cartridge's own type ORDER says which those are.
  -- Slot 9 is the unused "???" type that sits between the two halves.
  local typeRecords, fireIndex = {}, nil
  for index, name in ipairs(types) do
    if name == "FIRE" then fireIndex = index - 1 end
  end
  local categorised = 0
  for index, name in ipairs(types) do
    local zero = index - 1
    local record = { id = name, index = zero, name = name }
    if fireIndex then
      record.category = zero >= fireIndex and "special" or "physical"
      categorised = categorised + 1
    end
    typeRecords[name] = record
  end
  if not fireIndex then
    Logger.warn("gen3 type chart: no FIRE type -- the physical/special split "
                .. "could not be derived and every move will read as physical")
  end

  self:write("type_chart", {
    source = "ROM:gTypeEffectiveness",
    matchups = matchups,
    types = typeRecords,
    splitBoundary = fireIndex,
  })
  Logger.info("Gen3 type chart: %d non-neutral matchups, %d types split at "
              .. "FIRE (index %s)", #matchups, categorised, tostring(fireIndex))
end

-- ---------------------------------------------------------------------------
-- STAGE: sprites
--
-- Front and back pics are LZ77-compressed 4bpp, 64x64 -- eight tiles by eight,
-- 2048 bytes -- against a sixteen-colour palette that is itself compressed.
--
-- THREE THINGS THAT ARE NOT LIKE GEN 2.
--
-- Palette index 0 is the sheet's TRANSPARENCY colour, not white and not paper
-- -- carrying the Gen 2 habit over mattes the wrong colour out of all 440.
--
-- Seven species store an 8192-byte blob where the sprite table declares 2048,
-- because the pic buffer is allocated for four frames and only the first is
-- uploaded to VRAM.  The LZ77 header is the authority on how much data there
-- is; the table's size is what goes to the hardware.
--
-- And SIX OF THOSE SEVEN ARE NOT ANIMATED.  Blaziken, Marshtomp, Poochyena,
-- Walrein, Swablu and Rayquaza have one real frame and three filled solid
-- with $FF -- palette index 15 across all 2048 bytes.  Only CASTFORM really
-- carries four there, which are its four weather forms.
--
-- WHERE THE ANIMATION ACTUALLY IS.  A SECOND front-pic table
-- (gMonFrontPicTableAnimated) holds TWO frames for every one of the 439
-- species -- between 18% and 63% of the bytes differ between them -- so the
-- battle animation is universal, not a seven-species special case, and the
-- padded blobs in the still table are a red herring.
--
-- For 392 species frame 1 repeats the still pic; for the other 47 it does
-- NOT, and both frames are poses of their own.  That is why BOTH frames are
-- written rather than just the second: assuming frame 1 is always the still
-- pic would have dropped 47 species' first animation frame.
--
-- KNOWN GAP: Castform's three alternate forms are written with the NORMAL
-- form's palette, so they come out monochrome.  Each weather form has its own
-- palette on the cartridge and the table that holds them has not been located
-- yet; the tile data above is correct, only the colours are.  Recorded here
-- rather than quietly shipped, because a monochrome Castform looks like a
-- decode bug and is not one.
-- ---------------------------------------------------------------------------

local MON_PIC_BYTES = 2048

function RomExtractorGen3:decodeSprite(tableBase, index, palBase)
  local picPtr = self.rom:pointer(tableBase + index * 8)
  local palPtr = palBase and self.rom:pointer(palBase + index * 8)
  if not (picPtr and palPtr) then return nil end
  local raw = self.rom:lz77(picPtr)
  local palRaw = self.rom:lz77(palPtr)
  if not (raw and palRaw) then return nil end
  return raw, RomGba.palette(palRaw), math.max(1, math.floor(#raw / MON_PIC_BYTES))
end

-- Is this frame real pixels, or the $FF fill the pic buffer was padded with?
-- A genuine 64x64 frame never has one byte value repeated 2048 times.
local function frameIsFill(raw, frame)
  local offset = (frame - 1) * MON_PIC_BYTES
  local first = raw[offset + 1]
  if first == nil then return true end
  for i = 2, MON_PIC_BYTES do
    if raw[offset + i] ~= first then return false end
  end
  return true
end

function RomExtractorGen3:spriteImage(raw, colors, frame, cols, rows)
  local offset = (frame - 1) * MON_PIC_BYTES
  local slice = {}
  for i = 1, MON_PIC_BYTES do slice[i] = raw[offset + i] or 0 end
  local px = RomGba.tiles4bpp(slice, cols, rows)
  local image = ImageWriter.blank(cols * 8, rows * 8)
  local transparent = self:layoutValue("monPaletteTransparentIndex", 0)
  for y = 1, rows * 8 do
    for x = 1, cols * 8 do
      local idx = px[y][x]
      local c = colors[idx + 1]
      if idx == transparent or not c then
        image:setPixel(x - 1, y - 1, 0, 0, 0, 0)
      else
        image:setPixel(x - 1, y - 1, c[1] / 255, c[2] / 255, c[3] / 255, 1)
      end
    end
  end
  return image
end

function RomExtractorGen3:extractSprites()
  self:beginStage("Gen3 sprites")
  local front = self:need("gMonFrontPicTable", "sprites")
  local back = self:symbol("gMonBackPicTable")
  local pal = self:symbol("gMonPaletteTable")
  local shiny = self:symbol("gMonShinyPaletteTable")
  local animTable = self:symbol("gMonFrontPicTableAnimated")
  if not (front and pal and self._speciesIds) then return end

  local cols = self:layoutValue("monPicWidth", 8)
  local rows = self:layoutValue("monPicHeight", 8)
  local count = self:layoutValue("numSpecies", 412) - 1
  local written, animated = 0, 0

  for i = 1, count do
    local id = self._speciesIds[i]
    local slug_ = id:lower()
    local ok = pcall(function()
      local raw, colors, frames = self:decodeSprite(front, i, pal)
      if not raw then return end
      self:saveImage(self:spriteImage(raw, colors, 1, cols, rows),
                     "battle/front/" .. slug_ .. ".png")
      written = written + 1
      -- extra frames from the STILL table, but only the ones actually drawn:
      -- six of the seven over-sized blobs are padding, and Castform's weather
      -- forms are the only real multi-frame pic there
      local wrote = 0
      for f = 2, frames do
        if not frameIsFill(raw, f) then
          self:saveImage(self:spriteImage(raw, colors, f, cols, rows),
            ("battle/front/%s_f%d.png"):format(slug_, f))
          wrote = wrote + 1
        end
      end
      -- ...and the REAL battle animation, which every species has.  BOTH
      -- frames, because for 47 species frame 1 is not the still pic.
      if animTable then
        local araw = self:decodeSprite(animTable, i, pal)
        if araw and #araw >= 2 * MON_PIC_BYTES then
          for f = 1, 2 do
            self:saveImage(self:spriteImage(araw, colors, f, cols, rows),
              ("battle/front_anim/%s_%d.png"):format(slug_, f))
          end
          wrote = wrote + 1
        end
      end
      if wrote > 0 then animated = animated + 1 end
      if shiny then
        local sraw, scolors = self:decodeSprite(front, i, shiny)
        if sraw then
          self:saveImage(self:spriteImage(sraw, scolors, 1, cols, rows),
                         "battle/shiny/" .. slug_ .. ".png")
        end
      end
      if back then
        local braw, bcolors = self:decodeSprite(back, i, pal)
        if braw then
          self:saveImage(self:spriteImage(braw, bcolors, 1, cols, rows),
                         "battle/back/" .. slug_ .. ".png")
        end
      end
    end)
    if not ok then
      Logger.warn("gen3 sprites: species %d (%s) failed", i, tostring(id))
    end
    if i % 16 == 0 then self:tick("Gen3 sprites", i, count) end
  end
  Logger.info("Gen3 sprites: %d written, %d with a second frame", written, animated)
end

-- ---------------------------------------------------------------------------
-- STAGE: trainer sprites
--
-- 93 of them, 64x64 like the mon pics but with their own palette table, and
-- living PAST every mon graphics table -- which is why the discovery tool has
-- to start its search there: from offset zero it finds gMonFrontPicTable
-- every single time.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractTrainerSprites()
  self:beginStage("Gen3 trainer sprites")
  local pics = self:need("gTrainerFrontPicTable", "trainer sprites")
  local pals = self:symbol("gTrainerFrontPicPaletteTable")
  if not (pics and pals) then return end
  local classes = (self._constants or {}).trainerClasses or {}
  local written = 0
  for i = 0, 92 do
    local ok = pcall(function()
      local raw, colors = self:decodeSprite(pics, i, pals)
      if not raw then return end
      self:saveImage(self:spriteImage(raw, colors, 1, 8, 8),
                     ("battle/trainers/%03d.png"):format(i))
      written = written + 1
    end)
    if not ok then Logger.warn("gen3 trainer pic %d failed", i) end
  end
  Logger.info("Gen3 trainer sprites: %d of 93", written)
end

-- ---------------------------------------------------------------------------
-- STAGE: tutor moves
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractTutorMoves()
  self:beginStage("Gen3 tutor moves")
  local base = self:need("gTutorMoves", "tutor moves")
  if not (base and self._moveIds) then return end
  local list = {}
  for i = 0, 29 do
    local move = self.rom:u16(base + i * 2)
    list[i + 1] = self._moveIds[move] or move
  end
  local constants = self._constants or {}
  constants.tutorMoves = list
  self:write("constants", constants)
  Logger.info("Gen3 tutor moves: %d (%s ... %s)", #list, list[1], list[#list])
end

-- ---------------------------------------------------------------------------
-- STAGE: trainers
--
-- struct Trainer is 40 bytes.  The party is behind `partyFlags`: bit 0 means
-- each member carries a held item, bit 1 means it carries its own moves, and
-- the four combinations give four different member strides (8, 16, 16, 16).
-- Reading the wrong one gives a party of plausible-looking nonsense rather
-- than an error, so the flag is honoured rather than assumed.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractTrainers()
  self:beginStage("Gen3 trainers")
  local base = self:need("gTrainers", "trainers")
  if not base then return end
  local out, taken = {}, {}
  local count = 855
  for i = 0, count - 1 do
    local o = base + i * 40
    local flags = self.rom:u8(o)
    local name = self:readString(o + 4, 12)
    local id = uniqueId(taken, slug(name), i, "TRAINER")
    local partySize = self.rom:u8(o + 32)
    local partyPtr = self.rom:pointer(o + 36)
    local hasItems = (flags % 2) == 1
    local hasMoves = (math.floor(flags / 2) % 2) == 1
    local stride = (hasMoves and 16) or (hasItems and 16) or 8
    local party = {}
    if partyPtr and partySize > 0 and partySize <= 6 then
      for k = 0, partySize - 1 do
        local p = partyPtr + k * stride
        local member = {
          iv = self.rom:u16(p),
          level = self.rom:u16(p + 2),
          species = self._speciesIds and self._speciesIds[self.rom:u16(p + 4)]
                    or self.rom:u16(p + 4),
        }
        if hasItems then member.item = self.rom:u16(p + 6) end
        if hasMoves then
          local moves = {}
          local mo = p + (hasItems and 8 or 6)
          for m = 0, 3 do
            local mv = self.rom:u16(mo + m * 2)
            if mv ~= 0 then
              moves[#moves + 1] = self._moveIds and self._moveIds[mv] or mv
            end
          end
          if #moves > 0 then member.moves = moves end
        end
        party[#party + 1] = member
      end
    end
    out[id] = {
      id = id, index = i, name = name,
      class = self.rom:u8(o + 1),
      pic = self.rom:u8(o + 3),
      doubleBattle = self.rom:u8(o + 24) ~= 0 or nil,
      -- BattleState.newTrainer reads `parties[n]`, a LIST of parties, because
      -- Gen 1 and Gen 2 both give a trainer class several numbered teams.  A
      -- Gen 3 trainer is one record with one team, so it becomes a list of
      -- one; `party` stays as the cartridge's own flat shape for anything
      -- that would rather read it directly.
      parties = { party },
      party = party,
      source = ("ROM:gTrainers[%d]"):format(i),
    }
    if i % 64 == 0 then self:tick("Gen3 trainers", i, count) end
  end
  self:write("trainers", out)
  Logger.info("Gen3 trainers: %d from ROM", count)
end

-- ---------------------------------------------------------------------------
-- STAGE: machines
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractMachines()
  self:beginStage("Gen3 machines")
  local base = self:need("gTMHMMoves", "machines")
  if not (base and self._moveIds) then return end
  local machines = {}
  for i = 0, 57 do
    local move = self.rom:u16(base + i * 2)
    local kind = i < 50 and "TM" or "HM"
    local number = i < 50 and (i + 1) or (i - 49)
    machines[i + 1] = {
      kind = kind, number = number,
      id = ("%s_%02d"):format(kind, number),
      move = self._moveIds[move] or move,
    }
  end
  local constants = self._constants or {}
  constants.machines = machines
  self:write("constants", constants)
  Logger.info("Gen3 machines: 50 TMs + 8 HMs")
end


-- ---------------------------------------------------------------------------
-- STAGE: encounters
--
-- struct WildPokemonHeader is 20 bytes -- map group, map number, then four
-- pointers to a WildPokemonInfo per encounter kind.  The slot COUNT differs
-- per kind and is not stored anywhere: land is 12, water 5, rock smash 5,
-- fishing 10 (four Old Rod, three Good, three Super).  Reading a fixed count
-- would run one table into the next.
-- ---------------------------------------------------------------------------

local ENCOUNTER_KINDS = {
  { key = "grass", offset = 4,  slots = 12 },
  { key = "water", offset = 8,  slots = 5 },
  { key = "rock",  offset = 12, slots = 5 },
  { key = "fish",  offset = 16, slots = 10 },
}

function RomExtractorGen3:extractEncounters()
  self:beginStage("Gen3 encounters")
  local base = self:need("gWildMonHeaders", "encounters")
  if not base then return end
  local out, headers = {}, 0
  for i = 0, 400 do
    local o = base + i * 20
    if self.rom:u16(o) == 0xFFFF then break end
    local group, number = self.rom:u8(o), self.rom:u8(o + 1)
    local entry = { group = group, number = number }
    local any = false
    for _, kind in ipairs(ENCOUNTER_KINDS) do
      local infoPtr = self.rom:pointer(o + kind.offset)
      if infoPtr then
        local monPtr = self.rom:pointer(infoPtr + 4)
        if monPtr then
          local slots = {}
          for k = 0, kind.slots - 1 do
            local p = monPtr + k * 4
            slots[k + 1] = {
              min = self.rom:u8(p),
              max = self.rom:u8(p + 1),
              species = self._speciesIds and self._speciesIds[self.rom:u16(p + 2)]
                        or self.rom:u16(p + 2),
            }
          end
          entry[kind.key] = { rate = self.rom:u8(infoPtr), slots = slots }
          any = true
        end
      end
    end
    if any then
      -- Keyed by group/number because map IDs do not exist until phase 03.
      --
      -- A MAP CAN APPEAR MORE THAN ONCE.  Group 24 map 106 -- Altering Cave --
      -- has NINE headers, the alternate tables the cartridge swaps between.
      -- Assigning straight into the table kept the last and silently dropped
      -- eight, which is the kind of loss that never shows up as an error and
      -- only ever shows up as "why does this cave only spawn Zubat".
      local key = ("%d_%d"):format(group, number)
      local existing = out[key]
      if existing then
        existing.alternates = existing.alternates or {}
        existing.alternates[#existing.alternates + 1] = entry
      else
        out[key] = entry
      end
      headers = headers + 1
    end
  end
  local maps, alternates = 0, 0
  for _, entry in pairs(out) do
    maps = maps + 1
    alternates = alternates + #(entry.alternates or {})
  end
  self:write("encounters", out)
  Logger.info("Gen3 encounters: %d headers over %d maps (%d alternate tables)",
              headers, maps, alternates)
end

-- ---------------------------------------------------------------------------
-- STAGE: egg moves
--
-- One flat u16 list for the whole cartridge.  A species is ANNOUNCED by
-- (species + 20000) and everything after it belongs to that species until the
-- next announcement; $FFFF ends the list.  There is no per-species pointer.
-- ---------------------------------------------------------------------------

local EGG_SPECIES_MARK = 20000

function RomExtractorGen3:extractEggMoves()
  self:beginStage("Gen3 egg moves")
  local base = self:need("gEggMoves", "egg moves")
  if not (base and self._speciesIds and self._moveIds) then return end
  local bySpecies, current, count = {}, nil, 0
  for i = 0, 4095 do
    local word = self.rom:u16(base + i * 2)
    if word == 0xFFFF then break end
    if word > EGG_SPECIES_MARK then
      current = self._speciesIds[word - EGG_SPECIES_MARK]
      if current then bySpecies[current] = {}; count = count + 1 end
    elseif current and bySpecies[current] then
      local list = bySpecies[current]
      list[#list + 1] = self._moveIds[word] or word
    end
  end
  self._eggMoves = bySpecies
  Logger.info("Gen3 egg moves: %d species", count)
end

-- ---------------------------------------------------------------------------
-- STAGE: dex entries
--
-- struct PokedexEntry is THIRTY-TWO bytes, not the 36 its field list suggests
-- at a glance: a 12-byte category, height and weight in TENTHS (Bulbasaur is
-- 7 and 69, meaning 0.7 m and 6.9 kg), the description pointer, an unused
-- second pointer, and the two scale/offset pairs the dex screen poses the
-- sprite and the trainer with.
--
-- Indexed by NATIONAL dex number, which is why species carry `dex` -- the
-- internal slot is the wrong key here and would shift all of Hoenn by 25.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractDexEntries()
  self:beginStage("Gen3 dex entries")
  local base = self:need("gPokedexEntries", "dex entries")
  local coords = self:symbol("gMonFrontPicCoords")
  if not (base and self._pokemon) then return end
  local filled = 0
  for _, def in pairs(self._pokemon) do
    local dex = def.dex
    if dex and dex > 0 and dex <= 386 then
      local o = base + dex * 32
      local ok = pcall(function()
        def.category = self:readString(o, 12)
        def.height = self.rom:u16(o + 12) / 10      -- metres
        def.weight = self.rom:u16(o + 14) / 10      -- kilograms
        local desc = self.rom:pointer(o + 16)
        if desc then def.dexEntry = self:readString(desc, 256) end
      end)
      if ok then filled = filled + 1 end
    end
    if self._eggMoves and self._eggMoves[def.id] then
      def.eggMoves = self._eggMoves[def.id]
    end
    -- HOW MUCH OF THE 64x64 FRAME A SPECIES ACTUALLY DRAWS, and where it sits
    -- on the battle platform: a width/height nibble pair in TILES and a signed
    -- y-offset, four bytes each.  Read HERE rather than beside the sprites --
    -- it is data, and the sprite stage is wrapped in pcall and may not run at
    -- all.  Without it every mon is centred in a 64x64 box and the small ones
    -- float above the platform.
    if coords and def.index then
      local o = coords + def.index * 4
      local size = self.rom:u8(o)
      def.picCoords = { width = math.floor(size / 16), height = size % 16,
                        yOffset = self.rom:s8(o + 1) }
    end
  end
  -- rewritten so the dex text and egg moves land in the same module
  self:write("pokemon", self._pokemon)
  Logger.info("Gen3 dex entries: %d species with category, size and text", filled)
end

-- ---------------------------------------------------------------------------
-- STAGE: trainer classes
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractTrainerClasses()
  self:beginStage("Gen3 trainer classes")
  local base = self:need("gTrainerClassNames", "trainer classes")
  if not base then return end
  local names = {}
  for i = 0, 66 do names[i] = self:readString(base + i * 13, 13) end
  local constants = self._constants or {}
  constants.trainerClasses = names
  self:write("constants", constants)
  -- and give every trainer the readable class it was only carrying a number for
  Logger.info("Gen3 trainer classes: %d (0 = %s)", 67, tostring(names[0]))
end


-- ---------------------------------------------------------------------------
-- STAGE: text
--
-- GEN 3 HAS NO TEXT POINTER TABLE.  Gold and Crystal keep one, which is how
-- the Gen 2 extractor knows what the dialogue IS: it walks the table.  Here
-- every string is reached from a script or from code, so until the script
-- engine lands (phase 04) the only way to find the dialogue is to look for it.
--
-- So this scans for runs that decode cleanly as text and keys each one by its
-- OFFSET, which is exactly what a script operand will name when phase 04
-- resolves one.  The gates are deliberately strict, because the cost of a
-- false positive is a garbage line shown to a player:
--
--   * readText must accept the whole run, terminator included -- one byte it
--     cannot map and the run is rejected outright;
--   * at least MIN_TEXT_LETTERS letters, so tables of small numbers that
--     happen to sit in the printable range do not qualify;
--   * more than half the characters must be letters or spaces;
--   * and a run that starts inside an already-accepted one is skipped, so a
--     sentence is not also harvested from its second word onward.
--
-- MEASURED FALSE-POSITIVE RATE: 73 of 12,165 strings -- 0.6% -- land at or
-- above $C00000, which is graphics rather than dialogue.  That is the honest
-- cost of scanning, and it goes to ZERO in phase 04: once the script engine
-- can resolve a text operand, the pool becomes what is REACHABLE instead of
-- what merely decodes, and nothing points at those 73.
-- ---------------------------------------------------------------------------

local MIN_TEXT_LETTERS = 8

-- Score the DECODED CHARACTERS, not the rendered tokens.
--
-- "{VERSION}" and "{PLACEHOLDER:BF}" are seven and eleven letters of my own
-- spelling, and counting them let a five-character run of graphics data --
-- "hzi{VERSION}iy" -- clear an eight-letter gate.  The tokens come out before
-- anything is counted.
local function textQuality(text)
  local body = text:gsub("%b{}", "")
  local letters, spaces, other = 0, 0, 0
  for i = 1, #body do
    local c = body:sub(i, i)
    if c:match("%a") then letters = letters + 1
    elseif c == " " or c == "\n" then spaces = spaces + 1
    else other = other + 1 end
  end
  return letters, spaces, other
end

function RomExtractorGen3:extractText()
  self:beginStage("Gen3 text")
  local out, count = {}, 0
  local size = self.rom.size
  local off = 0
  local map = self:charmap()
  while off < size - 4 do
    -- Cheap rejection first -- the scan touches every byte of a 16 MiB
    -- cartridge.  A string may open with a CHARACTER, with a PLACEHOLDER
    -- ("{PLAYER} received the EFFORT RIBBON.") or with a formatting command,
    -- and only leading spaces and line breaks are ruled out.  Requiring a
    -- character lost every line that starts on the player's name, which is a
    -- lot of them.
    local b = self.rom:u8(off)
    if (map[b] == nil and b ~= TEXT_PLACEHOLDER and b ~= TEXT_EXTENDED)
       or b == 0x00 then
      off = off + 1
    else
      local text, used = self:readText(off, 1024)
      local letters, spaces, other = 0, 0, 0
      if text then letters, spaces, other = textQuality(text) end
      -- and at least one space: every real line has a word boundary, and a
      -- letter run with none is a symbol table or compressed data
      if text and letters >= MIN_TEXT_LETTERS and spaces >= 1
         and letters + spaces > other then
        count = count + 1
        out[("TEXT_%06X"):format(off)] = text
        off = off + used
      else
        off = off + 1
      end
    end
    if off % 0x100000 < 2 then self:tick("Gen3 text", off, size) end
  end
  -- kept, not discarded: extractScriptText adds the lines the scan's quality
  -- gate is too strict to find, and it can only do that by re-writing this
  self._text = out
  self._textScanCount = count
  self:write("text", out)
  -- text_pointers is the module Data.lua requires; until the script engine can
  -- say which line belongs to which map, it carries the offset index alone
  self:write("text_pointers", { source = "ROM:scan", byOffset = true })
  Logger.info("Gen3 text: %d strings recovered by scan", count)
end

-- ---------------------------------------------------------------------------
-- STAGE: script text
--
-- The whole-cartridge scan in extractText has to guess what is prose, and it
-- guesses conservatively: at least eight letters and one space, or a 16 MiB
-- sweep returns every symbol table in the ROM.  That gate throws away real
-- lines -- "Cabin 2" is seven letters -- and no heuristic will ever fix that,
-- because the string alone does not say whether it is text.
--
-- The scripts do.  A pointer sitting in a `message` operand IS text, whatever
-- it looks like, so once the scripts are decoded every such pointer can be
-- decoded unconditionally.  This also rewrites each operand from a raw
-- cartridge address into the text module's own key, which is what makes the
-- script pool self-contained: nothing downstream needs the ROM to resolve a
-- line.
-- ---------------------------------------------------------------------------

-- operand slot (1-based, including the opcode name) that carries a text
-- pointer, for every command that takes one
local TEXT_OPERAND = {
  loadword = 3, message = 2, messageautoscroll = 3, messageinstant = 2,
  braillemessage = 2, bufferstring = 3, pokenavcall = 2, vmessage = 2,
}

function RomExtractorGen3:extractScriptText()
  self:beginStage("Gen3 script text")
  local pool, text = self._scriptPool, self._text
  if not (pool and text) then
    Logger.warn("gen3: script text needs both extractText and extractMapScripts")
    return
  end
  local base = RomGba.BASE
  local added, rewritten, notText = 0, 0, 0

  for _, rows in pairs(pool.scripts) do
    for _, row in ipairs(rows) do
      local slot = TEXT_OPERAND[row[1]]
      local value = slot and row[slot]
      if type(value) == "number" and value >= base
         and value < base + self.rom.size then
        local off = value - base
        local key = ("TEXT_%06X"):format(off)
        if not text[key] then
          -- no quality gate here: the script is the evidence
          local ok, decoded = pcall(self.readText, self, off, 1024)
          if ok and decoded then
            text[key] = decoded
            added = added + 1
          else
            -- `loadword` also carries non-text pointers (mart lists,
            -- multichoice tables); leave those as raw addresses
            notText = notText + 1
          end
        end
        if text[key] then
          row[slot] = key
          rewritten = rewritten + 1
        end
      end
    end
  end

  self:write("text", text)
  self:write("map_scripts", pool)
  pool.info.textReferences = rewritten
  pool.info.textAdded = added
  Logger.info("Gen3 script text: %d references keyed, %d lines the scan "
              .. "missed, %d operands that are not text",
              rewritten, added, notText)
end

-- ---------------------------------------------------------------------------
-- Stage lists and entry point
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- STAGE: map layouts
--
--   struct MapLayout { s32 width, s32 height, u16 *border, u16 *map,
--                      Tileset *primary, Tileset *secondary }
--
-- 24 bytes, no border dimensions -- those are FireRed's; Emerald's border is
-- always 2x2.  The secondary tileset may be NULL (one 58x26 layout is built
-- that way), so nothing here may assume two.
--
-- Blockdata is a flat u16 per 16x16 metatile cell: bits 0-9 the metatile id,
-- 10-11 collision, 12-15 elevation.  It is kept as a byte string rather than
-- a Lua array because 441 layouts come to 325,479 cells, and a table of that
-- many numbers costs about forty times the memory of the string.
-- ---------------------------------------------------------------------------

local function mapKey(group, number)
  return ("MAP_G%02d_N%02d"):format(group, number)
end

function RomExtractorGen3:layoutBlocks(off, cells)
  local pieces, chunk = {}, {}
  for i = 0, cells - 1 do
    local v = self.rom:u16(off + i * 2)
    chunk[#chunk + 1] = string.char(v % 256, math.floor(v / 256) % 256)
    if #chunk >= 2048 then
      pieces[#pieces + 1] = table.concat(chunk); chunk = {}
    end
  end
  pieces[#pieces + 1] = table.concat(chunk)
  return table.concat(pieces)
end

function RomExtractorGen3:extractMapLayouts()
  self:beginStage("Gen3 map layouts")
  local base = self:need("gMapLayouts", "map layouts")
  if not base then return end
  local count = self:layoutValue("numMapLayouts", 441)

  local out, tilesets = {}, {}
  local cells = 0
  for i = 0, count - 1 do
    local a = self.rom:pointer(base + i * 4)
    if a then
      local width, height = self.rom:u32(a), self.rom:u32(a + 4)
      local primary = self.rom:pointer(a + 16)
      local secondary = self.rom:pointer(a + 20)
      if primary then tilesets[primary] = true end
      if secondary then tilesets[secondary] = true end
      local blockPtr = self.rom:pointer(a + 12)
      local borderPtr = self.rom:pointer(a + 8)
      cells = cells + width * height
      -- COLLISION LIVES ON THE MAP CELL, not on the tileset.
      --
      -- This is the structural difference that a Gen 1/Gen 2 habit gets wrong.
      -- There, passability is a property of the tileset block, so every
      -- instance of a given block is passable or not alike.  In Gen 3 the
      -- blockdata word carries its own collision bits, so the SAME metatile is
      -- walkable in one place and a wall in another -- which is how a house
      -- front and its doorway share one tile.  Reading the tileset's behaviour
      -- byte instead reports Littleroot as 100% walkable, houses included.
      --
      --   bits 0-9   metatile id
      --   bits 10-11 collision (0 = passable)
      --   bits 12-15 elevation, which drives bridges and multi-level terrain
      local collision, elevation = nil, nil
      if blockPtr then
        local coll, elev = {}, {}
        for k = 0, width * height - 1 do
          local word = self.rom:u16(blockPtr + k * 2)
          coll[k + 1] = math.floor(word / 1024) % 4
          elev[k + 1] = math.floor(word / 4096) % 16
        end
        collision, elevation = coll, elev
      end
      out[i + 1] = {
        id = i + 1,                     -- layoutId is 1-based in a MapHeader
        width = width,
        height = height,
        collisionCells = collision,
        elevationCells = elevation,
        primaryTileset = primary,
        secondaryTileset = secondary,
        -- the border is always 2x2 metatiles in Emerald
        border = borderPtr and self:layoutBlocks(borderPtr, 4) or nil,
        blocks = blockPtr and self:layoutBlocks(blockPtr, width * height) or nil,
        source = ("ROM:gMapLayouts[%d]"):format(i),
      }
    end
    if i % 32 == 0 then self:tick("Gen3 map layouts", i, count) end
  end
  self._tilesetAddresses = tilesets
  self._layoutRecords = out
  out._romInfo = { source = "RomExtractorGen3", layoutCount = count,
                   metatileCells = cells }
  self:write("map_layouts", out)
  Logger.info("Gen3 map layouts: %d layouts, %d metatile cells", count, cells)
end

-- ---------------------------------------------------------------------------
-- STAGE: maps
--
--   struct MapHeader { MapLayout *layout, MapEvents *events,
--                      u8 *mapScripts, MapConnections *connections,
--                      u16 music, u16 layoutId, u8 regionMapSectionId,
--                      u8 cave, u8 weather, u8 mapType, u8 filler[2],
--                      u8 flags, u8 battleType }   -- 28 bytes
--
-- gMapGroups is 34 pointers, one per group, each at a back-to-back array of
-- MapHeader pointers; a group's map count is the gap to the next group
-- pointer, and the last group's is the gap to gMapGroups itself.  The events
-- block is four counts then four pointers, and its four arrays have strides
-- 24 / 8 / 16 / 12.
-- ---------------------------------------------------------------------------

local MAP_TYPES = {
  [0] = "NONE", "TOWN", "CITY", "ROUTE", "UNDERGROUND", "UNDERWATER",
  "OCEAN_ROUTE", "UNKNOWN", "INDOOR", "SECRET_BASE",
}

local BG_EVENT_KINDS = {
  [0] = "SCRIPT", "SCRIPT_UP", "SCRIPT_DOWN", "SCRIPT_RIGHT", "SCRIPT_LEFT",
  "HIDDEN_ITEM", "SECRET_BASE",
}

local CONNECTION_DIRECTIONS = {
  [1] = "DOWN", [2] = "UP", [3] = "LEFT", [4] = "RIGHT",
  [5] = "DIVE", [6] = "EMERGE",
}

function RomExtractorGen3:mapHeaderList()
  local base = self:symbol("gMapGroups")
  if not base then return nil end
  local groups = self:layoutValue("numMapGroups", 34)
  local starts = {}
  for g = 0, groups - 1 do
    starts[g + 1] = self.rom:pointer(base + g * 4)
    if not starts[g + 1] then return nil end
  end
  local list = {}
  for g = 1, groups do
    local stop = starts[g + 1] or base
    for n = 0, math.floor((stop - starts[g]) / 4) - 1 do
      local header = self.rom:pointer(starts[g] + n * 4)
      if header then
        list[#list + 1] = { group = g - 1, number = n, header = header }
      end
    end
  end
  return list
end

function RomExtractorGen3:mapEvents(off)
  local rom = self.rom
  local counts = { object = rom:u8(off), warp = rom:u8(off + 1),
                   coord = rom:u8(off + 2), bg = rom:u8(off + 3) }
  local objectsAt = rom:pointer(off + 4)
  local warpsAt = rom:pointer(off + 8)
  local coordsAt = rom:pointer(off + 12)
  local bgAt = rom:pointer(off + 16)

  local objects, warps, coords, signs = {}, {}, {}, {}
  for i = 0, counts.object - 1 do
    local o = objectsAt + i * 24
    local range = rom:u8(o + 10)
    objects[i + 1] = {
      localId = rom:u8(o),
      graphicsId = rom:u8(o + 1),
      kind = rom:u8(o + 2),
      x = rom:s16(o + 4), y = rom:s16(o + 6),
      elevation = rom:u8(o + 8),
      movementType = rom:u8(o + 9),
      movementRangeX = range % 16,
      movementRangeY = math.floor(range / 16),
      trainerType = rom:u16(o + 12),
      trainerRange = rom:u16(o + 14),
      script = rom:pointer(o + 16),
      flag = rom:u16(o + 20),
    }
  end
  for i = 0, counts.warp - 1 do
    local o = warpsAt + i * 8
    warps[i + 1] = {
      x = rom:s16(o), y = rom:s16(o + 2), elevation = rom:u8(o + 4),
      destWarp = rom:u8(o + 5),
      destMap = mapKey(rom:u8(o + 7), rom:u8(o + 6)),
    }
  end
  for i = 0, counts.coord - 1 do
    local o = coordsAt + i * 16
    coords[i + 1] = {
      x = rom:s16(o), y = rom:s16(o + 2), elevation = rom:u8(o + 4),
      var = rom:u16(o + 6), value = rom:u16(o + 8),
      script = rom:pointer(o + 12),
    }
  end
  for i = 0, counts.bg - 1 do
    local o = bgAt + i * 12
    local kind = rom:u8(o + 5)
    local sign = {
      x = rom:s16(o), y = rom:s16(o + 2), elevation = rom:u8(o + 4),
      kind = BG_EVENT_KINDS[kind] or kind,
    }
    if kind <= 4 then
      sign.script = rom:pointer(o + 8)
    elseif kind == 5 then
      -- hidden item: item id, then flag and quantity packed into one word
      sign.item = rom:u16(o + 8)
      local packed = rom:u16(o + 10)
      sign.hiddenItemFlag = packed % 256
      sign.quantity = math.floor(packed / 256) % 128
      sign.underfoot = math.floor(packed / 32768) == 1
    else
      sign.secretBaseId = rom:u32(o + 8)
    end
    signs[i + 1] = sign
  end
  return objects, warps, coords, signs
end

function RomExtractorGen3:mapScriptEntries(off)
  local rom, entries = self.rom, {}
  local o = off
  for _ = 1, 32 do
    local kind = rom:u8(o)
    if kind == 0 then break end
    if kind > 8 then break end
    local ptr = rom:pointer(o + 1)
    o = o + 5
    if Gen3ScriptOps.MAP_SCRIPT_TABLE_TYPES[kind] and ptr then
      local rows = {}
      local q = ptr
      for _ = 1, 32 do
        local var = rom:u16(q)
        if var == 0 then break end
        rows[#rows + 1] = { var = var, value = rom:u16(q + 2),
                            script = rom:pointer(q + 4) }
        q = q + 8
      end
      entries[#entries + 1] = { type = kind, rows = rows }
    else
      entries[#entries + 1] = { type = kind, script = ptr }
    end
  end
  return entries
end

function RomExtractorGen3:extractMaps()
  self:beginStage("Gen3 maps")
  local list = self:mapHeaderList()
  if not list then
    Logger.warn("gen3: gMapGroups is not in the manifest -- maps skipped")
    return
  end
  local rom = self.rom
  local out = {}
  local roots, connected, warpCount, objectCount = {}, 0, 0, 0
  -- Per-map script index, in the shape src/script/ already consumes: a pool
  -- of scripts keyed by label, and per map an index of which object, sign,
  -- coord event or map-script slot reaches which label.
  local scriptIndex = {}

  local function root(ptr) if ptr then roots[ptr] = true end end
  local function label(ptr) return ptr and ("S%07X"):format(ptr) or nil end

  for index, entry in ipairs(list) do
    local h = entry.header
    local key = mapKey(entry.group, entry.number)
    local def = {
      id = key,
      group = entry.group,
      number = entry.number,
      layoutId = rom:u16(h + 18),
      music = rom:u16(h + 16),
      regionMapSection = rom:u8(h + 20),
      cave = rom:u8(h + 21) ~= 0,
      weather = rom:u8(h + 22),
      mapType = MAP_TYPES[rom:u8(h + 23)] or rom:u8(h + 23),
      flags = rom:u8(h + 26),
      battleScene = rom:u8(h + 27),
      source = ("ROM:gMapGroups[%d][%d]"):format(entry.group, entry.number),
    }

    local entry = { objects = {}, signs = {}, coords = {}, callbacks = {},
                    tables = {} }

    local eventsAt = rom:pointer(h + 4)
    if eventsAt then
      local objects, warps, coords, signs = self:mapEvents(eventsAt)
      -- The TEXT constant is the join between a map object and its script:
      -- MapScripts keys talk contributions by it, exactly as Gen 2 does.
      for i, o in ipairs(objects) do
        o.text = ("TEXT_%s_OBJ_%03d"):format(key, i)
        if o.script then entry.objects[i] = label(o.script) end
      end
      for i, sign in ipairs(signs) do
        sign.text = ("TEXT_%s_BG_%03d"):format(key, i)
        if sign.script then entry.signs[i] = label(sign.script) end
      end
      if #objects > 0 then def.objects = objects; objectCount = objectCount + #objects end
      if #warps > 0 then def.warps = warps; warpCount = warpCount + #warps end
      if #coords > 0 then def.coordEvents = coords end
      if #signs > 0 then def.signs = signs end
      for _, o in ipairs(objects) do root(o.script) end
      for _, c in ipairs(coords) do
        root(c.script)
        if c.script then
          entry.coords[#entry.coords + 1] = {
            x = c.x, y = c.y, var = c.var, value = c.value,
            script = label(c.script),
          }
        end
      end
      for _, sign in ipairs(signs) do root(sign.script) end
    end

    local scriptsAt = rom:pointer(h + 8)
    if scriptsAt then
      local entries = self:mapScriptEntries(scriptsAt)
      if #entries > 0 then
        def.mapScripts = entries
        for _, e in ipairs(entries) do
          root(e.script)
          if e.script then
            entry.callbacks[#entry.callbacks + 1] =
              { type = e.type, script = label(e.script) }
          end
          if e.rows then
            local rows = {}
            for _, r in ipairs(e.rows) do
              root(r.script)
              if r.script then
                rows[#rows + 1] = { var = r.var, value = r.value,
                                    script = label(r.script) }
              end
            end
            if #rows > 0 then
              entry.tables[#entry.tables + 1] = { type = e.type, rows = rows }
            end
          end
        end
      end
    end

    if next(entry.objects) or next(entry.signs) or #entry.coords > 0
        or #entry.callbacks > 0 or #entry.tables > 0 then
      scriptIndex[key] = entry
    end

    local connAt = rom:pointer(h + 12)
    if connAt then
      local count = rom:u32(connAt)
      local at = rom:pointer(connAt + 4)
      if at and count > 0 and count <= 8 then
        local list_ = {}
        for i = 0, count - 1 do
          local o = at + i * 12
          local dir = rom:u32(o)
          list_[i + 1] = {
            direction = CONNECTION_DIRECTIONS[dir] or dir,
            offset = rom:s32(o + 4),
            map = mapKey(rom:u8(o + 8), rom:u8(o + 9)),
          }
        end
        def.connections = list_
        connected = connected + 1
      end
    end

    -- Everything src/world/Map.lua reads off a map def, copied from the
    -- layout the header names.  Gen 1 and Gen 2 store blockdata ON the map;
    -- Gen 3 stores it on a layout that several maps can share, and resolving
    -- that here rather than in the loader is what lets MapLoader stay
    -- generation-agnostic.
    local layout = self._layoutRecords and self._layoutRecords[def.layoutId]
    if layout then
      def.width = layout.width
      def.height = layout.height
      def.blocks = layout.blocks
      def.collisionCells = layout.collisionCells
      def.elevationCells = layout.elevationCells
      def.border = layout.border
      -- Gen 3 has no single border BLOCK -- it has a 2x2 border patch -- so
      -- the def carries its top-left corner for the engine's border fill and
      -- the full patch beside it.
      def.borderBlock = layout.border
        and (layout.border:byte(1) + layout.border:byte(2) * 256) % 1024 or 0
      def.tileset = self:tilesetPairKey(layout.primaryTileset,
                                        layout.secondaryTileset)
    end

    out[key] = def
    if index % 32 == 0 then self:tick("Gen3 maps", index, #list) end
  end

  self._scriptRoots = roots
  self._mapScriptIndex = scriptIndex
  out._romInfo = {
    source = "RomExtractorGen3",
    mapCount = #list,
    groupCount = self:layoutValue("numMapGroups", 34),
    connectionCount = connected,
    warpCount = warpCount,
    objectCount = objectCount,
  }
  self:write("maps", out)
  Logger.info("Gen3 maps: %d maps, %d objects, %d warps, %d with connections",
              #list, objectCount, warpCount, connected)
end

-- ---------------------------------------------------------------------------
-- STAGE: map scripts
--
-- Walks every script reachable from the map headers -- object events, bg
-- events, coord events and both kinds of map script -- following call/goto so
-- that subroutines shared between maps are decoded once.  See
-- src/import/Gen3ScriptOps.lua for where the operand widths come from.
--
-- A warp does not end a script, it yields; the map change then tears the
-- context down.  Scripts written as `warp / waitstate` with no `end` are
-- common enough that walking past the waitstate reads movement data as
-- bytecode, so WARP_YIELD stops there.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:decodeScriptAt(start, queue)
  local rom, ops = self.rom, Gen3ScriptOps.COMMANDS
  local lines, o, previous = {}, start, nil
  for _ = 1, 4096 do
    local op = rom:u8(o)
    local command = ops[op + 1]
    if not command then
      return lines, ("unknown opcode $%02X at %07X"):format(op, o)
    end
    local name, spec = command[1], command[2]
    local at, args = o + 1, {}
    if spec == "*" then
      local kind = rom:u8(at)
      local length = Gen3ScriptOps.TRAINER_BATTLE_LENGTH[kind]
      if not length then
        return lines, ("trainerbattle type %d at %07X"):format(kind, o)
      end
      args[1] = kind
      args[2] = rom:u16(at + 1)
      at = at + length - 1
    else
      for i = 1, #spec do
        local letter = spec:sub(i, i)
        if letter == "b" then
          args[#args + 1] = rom:u8(at); at = at + 1
        elseif letter == "w" then
          args[#args + 1] = rom:u16(at); at = at + 2
        else
          local word = rom:u32(at)
          args[#args + 1] = word
          at = at + 4
          local target = self.rom:pointer(at - 4)
          if queue and target and (name == "call" or name == "goto"
                        or name == "goto_if" or name == "call_if") then
            queue[#queue + 1] = target
          end
          -- the other bytecode language rides in on these two operands
          if target and (name == "applymovement"
                         or name == "applymovementat") then
            self._movementRoots = self._movementRoots or {}
            self._movementRoots[target] = true
            -- store the POOL LABEL, not the raw pointer: the lowering looks
            -- movement data up by key exactly as the Gen 2 VM does
            args[#args] = ("M%07X"):format(target)
          end
        end
      end
    end
    lines[#lines + 1] = { address = o, op = op, name = name, args = args }
    o = at
    if Gen3ScriptOps.TERMINATORS[op] then return lines, nil end
    if op == 0x27 and previous and Gen3ScriptOps.WARP_YIELD[previous] then
      return lines, nil
    end
    previous = op
  end
  return lines, ("ran past 4096 commands from %07X"):format(start)
end

function RomExtractorGen3:extractMapScripts()
  self:beginStage("Gen3 map scripts")
  local roots = self._scriptRoots
  if not roots then
    Logger.warn("gen3: no script roots -- run extractMaps first")
    return
  end
  local queue = {}
  for ptr in pairs(roots) do queue[#queue + 1] = ptr end
  table.sort(queue)
  local rootCount = #queue

  -- The pool shape is deliberately the one src/script/ already consumes:
  -- `scripts[label] = { {opName, arg1, ...}, ... }` with FLAT ir rows, a
  -- separate `movements` pool, and a per-map index.  A Gen 3 lowering VM can
  -- then be a sibling of Gen2ScriptVM rather than a second script subsystem.
  local scripts, movements = {}, {}
  local seen, commands, failures = {}, 0, {}
  local count = 0
  while #queue > 0 do
    local start = table.remove(queue)
    if not seen[start] then
      seen[start] = true
      count = count + 1
      local lines, err = self:decodeScriptAt(start, queue)
      commands = commands + #lines
      local rows = {}
      for i, line in ipairs(lines) do
        local row = { line.name }
        for k = 1, #line.args do row[k + 1] = line.args[k] end
        rows[i] = row
      end
      scripts[("S%07X"):format(start)] = rows
      if err then failures[#failures + 1] = err end
      if count % 128 == 0 then
        self:tick("Gen3 map scripts", count, count + #queue)
      end
    end
  end

  local out = {
    source = "RomExtractorGen3",
    scripts = scripts,
    movements = movements,          -- filled by extractMovementScripts
    maps = self._mapScriptIndex or {},
    info = {
      rootCount = rootCount,
      scriptCount = count,
      commandCount = commands,
      failureCount = #failures,
    },
  }
  self._scriptPool = out
  self:write("map_scripts", out)
  if #failures > 0 then
    Logger.warn("Gen3 map scripts: %d of %d scripts did not decode; first: %s",
                #failures, count, failures[1])
  end
  Logger.info("Gen3 map scripts: %d scripts, %d commands from %d roots",
              count, commands, rootCount)
end

-- ---------------------------------------------------------------------------
-- STAGE: movement scripts
--
-- `applymovement` and `applymovementat` point at the OTHER bytecode language:
-- a flat array of one-byte movement action ids closed by $FE.  There is no
-- length anywhere, so the terminator is the only bound -- and every one of the
-- 896 arrays the map scripts reach does terminate, using ids well inside the
-- 158-entry gMovementActionFuncs table.  An array that ran past $FF ids would
-- mean applymovement's operand width was wrong, so this doubles as a check on
-- the script decoder.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractMovementScripts()
  self:beginStage("Gen3 movement scripts")
  local scripts = self._movementRoots
  local pool = self._scriptPool
  if not (scripts and pool) then
    Logger.warn("gen3: no movement roots -- run extractMapScripts first")
    return
  end
  local limit = self:layoutValue("movementActionCount", 158)
  local terminator = self:layoutValue("movementStepEnd", 0xFE)

  local starts = {}
  for ptr in pairs(scripts) do starts[#starts + 1] = ptr end
  table.sort(starts)

  local steps, unterminated, unknown = 0, 0, 0
  for index, start in ipairs(starts) do
    local rows, o = {}, start
    for _ = 1, 256 do
      local id = self.rom:u8(o)
      if id == terminator then break end
      -- flat ir rows, same as the script pool: { name } or { name, arg }
      rows[#rows + 1] = { Gen3ScriptOps.movementName(id), id }
      if id >= limit then unknown = unknown + 1 end
      o = o + 1
    end
    if self.rom:u8(o) ~= terminator then unterminated = unterminated + 1 end
    steps = steps + #rows
    pool.movements[("M%07X"):format(start)] = rows
    if index % 128 == 0 then self:tick("Gen3 movement scripts", index, #starts) end
  end

  pool.info.movementCount = #starts
  pool.info.movementSteps = steps
  pool.info.movementUnterminated = unterminated
  pool.info.movementUnknownActions = unknown
  pool.info.movementActionTableSize = limit
  self:write("map_scripts", pool)
  if unterminated > 0 then
    Logger.warn("Gen3 movement scripts: %d never reached the $%02X terminator",
                unterminated, terminator)
  end
  Logger.info("Gen3 movement scripts: %d scripts, %d steps", #starts, steps)
end

-- ---------------------------------------------------------------------------
-- STAGE: tilesets
--
--   struct Tileset { u8 isCompressed, u8 isSecondary, u32 *tiles,
--                    u16 *palettes, u16 *metatiles, u16 *metatileAttributes,
--                    TilesetCB callback }   -- 24 bytes
--
-- A metatile is 16x16: eight u16 tile entries, four for the bottom layer then
-- four for the top, each `tile | palette << 12` with bits 10 and 11 the flips.
-- Nothing on the cartridge records how MANY metatiles a tileset has, but the
-- attributes array is laid out immediately after the metatile array, so the
-- gap between the two pointers divided by sixteen is the count exactly -- and
-- that comes out a whole number for all 73 real tilesets.
--
-- The palette block is sixteen 16-colour palettes; a primary tileset owns
-- slots 0-5 and a secondary 6-12, which is why both are written whole rather
-- than merged here.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:tilesetSheet(tiles, palettes, count)
  local cols = 16
  local rows = math.ceil(count / cols)
  local px = RomGba.tiles4bpp(tiles, cols, rows)
  local image = ImageWriter.blank(cols * 8, rows * 8)
  local colors = palettes[1] or {}
  for y = 1, rows * 8 do
    for x = 1, cols * 8 do
      local idx = px[y] and px[y][x] or 0
      local c = colors[idx + 1]
      if idx == 0 or not c then
        image:setPixel(x - 1, y - 1, 0, 0, 0, 0)
      else
        image:setPixel(x - 1, y - 1, c[1] / 255, c[2] / 255, c[3] / 255, 1)
      end
    end
  end
  return image
end

function RomExtractorGen3:extractTilesets()
  self:beginStage("Gen3 tilesets")
  local addresses = self._tilesetAddresses
  if not addresses then
    Logger.warn("gen3: no tileset addresses -- run extractMapLayouts first")
    return
  end
  local rom = self.rom
  local sorted = {}
  for a in pairs(addresses) do sorted[#sorted + 1] = a end
  table.sort(sorted)

  local out, written, skipped = {}, 0, 0
  for index, a in ipairs(sorted) do
    local compressed = rom:u8(a) ~= 0
    local secondary = rom:u8(a + 1) ~= 0
    local tilesAt = rom:pointer(a + 4)
    local palAt = rom:pointer(a + 8)
    local metaAt = rom:pointer(a + 12)
    local attrAt = rom:pointer(a + 16)
    local span = (metaAt and attrAt) and (attrAt - metaAt) or -1
    local metatiles = (span > 0 and span % 16 == 0) and span / 16 or nil

    if not (tilesAt and palAt and metatiles) then
      skipped = skipped + 1
    else
      local key = ("TILESET_%07X"):format(a)
      local ok, err = pcall(function()
        local raw = compressed and rom:lz77(tilesAt)
                    or rom:bytes(tilesAt, 512 * 32)
        local palettes = {}
        for p = 0, 15 do
          palettes[p + 1] = RomGba.palette(rom:bytes(palAt + p * 32, 32))
        end
        -- metatile composition and attributes, as byte strings for the same
        -- reason the blockdata is: 73 tilesets come to about 26,000 metatiles
        local comp, attrs = {}, {}
        for m = 0, metatiles - 1 do
          for t = 0, 7 do
            local v = rom:u16(metaAt + m * 16 + t * 2)
            comp[#comp + 1] = string.char(v % 256, math.floor(v / 256) % 256)
          end
          local av = rom:u16(attrAt + m * 2)
          attrs[#attrs + 1] = string.char(av % 256, math.floor(av / 256) % 256)
        end
        -- The 4bpp TILE PIXELS travel with the record, not just as a PNG.
        -- A metatile draws tiles out of BOTH banks with a per-tile palette and
        -- flip, so the composite cannot be assembled from a pre-baked sheet
        -- that already has one palette applied -- src/render/Gen3Tiles.lua
        -- needs the raw indices.  512 tiles is 16 KB, and there are 73.
        local pixels = {}
        for k = 1, #raw do pixels[k] = string.char(raw[k]) end

        out[key] = {
          id = key,
          address = a,
          index = index - 1,
          compressed = compressed,
          secondary = secondary,
          tileCount = math.floor(#raw / 32),
          metatileCount = metatiles,
          -- all sixteen slots as this tileset stores them; a PRIMARY leaves
          -- 6..15 zeroed and a SECONDARY leaves 0..5 zeroed, because each only
          -- owns its own bank.  Which half to read is the pair's business, not
          -- the tileset's -- see palettesInPrimary in the manifest.
          palettes = palettes,
          tiles = table.concat(pixels),
          metatiles = table.concat(comp),
          attributes = table.concat(attrs),
          callback = rom:u32(a + 20),
          image = "assets/generated/tilesets/" .. key:lower() .. ".png",
          source = ("ROM:Tileset@%07X"):format(a),
        }
        self:saveImage(
          self:tilesetSheet(raw, palettes, math.floor(#raw / 32)),
          "tilesets/" .. key:lower() .. ".png")
        written = written + 1
      end)
      if not ok then
        skipped = skipped + 1
        Logger.warn("gen3 tileset %07X: %s", a, tostring(err))
      end
    end
    self:tick("Gen3 tilesets", index, #sorted)
  end

  out._romInfo = { source = "RomExtractorGen3", tilesetCount = written,
                   skipped = skipped }
  self:write("map_tilesets", out)
  self._tilesets = out
  Logger.info("Gen3 tilesets: %d written, %d skipped", written, skipped)

  -- ------------------------------------------------------------------
  -- and the PAIR records, in the shape MapLoader already reads.
  --
  -- A Gen 3 metatile draws out of two tilesets at once, so the unit the
  -- renderer needs is the PAIR, not either half -- 441 layouts resolve to 76
  -- distinct pairs.  Writing them into `tilesets` under the key each map's
  -- own `tileset` field names means MapLoader.tilesetFor works untouched:
  -- there is no Gen 3 arm in the loader at all.
  --
  -- The two halves are referenced by KEY rather than copied in.  There are
  -- only three primaries in the whole game and 76 pairs, so inlining them
  -- would store the 512-metatile primary seventy-six times.
  -- ------------------------------------------------------------------
  local layouts = self._layoutRecords or {}
  local pairs_, pairCount = {}, 0
  for _, lay in pairs(layouts) do
    local key = self:tilesetPairKey(lay.primaryTileset, lay.secondaryTileset)
    if key and not pairs_[key] then
      local primary = out[("TILESET_%07X"):format(lay.primaryTileset)]
      local secondary = lay.secondaryTileset
        and out[("TILESET_%07X"):format(lay.secondaryTileset)] or nil
      if primary then
        pairCount = pairCount + 1
        local metatiles = (primary.metatileCount or 0)
          + (secondary and secondary.metatileCount or 0)
        -- One collision class per METATILE, which is the Gen 3 shape: a Gen 2
        -- block carries four (NW/NE/SW/SE) because it is 32px and holds four
        -- 16px cells, while a metatile IS one 16px cell.  blockCells = 1 is
        -- what tells Map:cellTile to index it that way.
        local collision = {}
        for id = 0, metatiles - 1 do
          local src, local_ = primary, id
          if id >= (primary.metatileCount or 0) and secondary then
            src, local_ = secondary, id - primary.metatileCount
          end
          local at = local_ * 2 + 1
          local word = 0
          if src.attributes and at + 1 <= #src.attributes then
            word = src.attributes:byte(at) + src.attributes:byte(at + 1) * 256
          end
          collision[id + 1] = word % 256          -- the behaviour byte
        end
        pairs_[key] = {
          id = key,
          primaryKey = primary.id,
          secondaryKey = secondary and secondary.id or nil,
          -- 2x2 tiles per metatile, and the metatile IS the collision cell
          blockTiles = 2,
          blockCells = 1,
          metatileCount = metatiles,
          collision = collision,
          -- EVERY behaviour byte is "walkable" here, and that is not a
          -- shortcut.  In Gen 3 passability is the map CELL's business -- the
          -- collision bits in its blockdata word -- and the behaviour byte
          -- only names what kind of ground it is: tall grass, sand, a puddle,
          -- a door, ice.  Map:cellTile already returns $FF for a cell the
          -- collision bits block, so listing behaviours here would block
          -- terrain a second time and for the wrong reason: with only {0},
          -- Littleroot's three doorways read as walls.
          walkable = (function()
            local all = {}
            for b = 0, 254 do all[b + 1] = b end
            return all
          end)(),
          source = ("ROM:tileset pair %07X/%s"):format(
            lay.primaryTileset,
            lay.secondaryTileset and ("%07X"):format(lay.secondaryTileset) or "none"),
        }
      end
    end
  end
  pairs_._romInfo = { source = "RomExtractorGen3", pairCount = pairCount }
  self:write("tilesets", pairs_)

  -- The bank boundaries travel with the DATA, not as literals in the
  -- renderer.  src/render/Gen3Tiles.lua needs all three to composite a
  -- metatile, and the palette one in particular fails silently when it is
  -- wrong -- slot 6 read from the primary bank is sixteen zero words, so
  -- every wall in Littleroot renders solid black while the roofs above them
  -- stay perfect.  tools/gen3_discover.py derives them from the cartridge.
  local constants = self._constants or {}
  constants.gen3Layout = {
    tilesInPrimary = self:layoutValue("tilesInPrimary", 512),
    metatilesInPrimary = self:layoutValue("metatilesInPrimary", 512),
    palettesInPrimary = self:layoutValue("palettesInPrimary", 6),
    metatileLayers = self:layoutValue("metatileLayers", 2),
  }
  self._constants = constants
  self:write("constants", constants)
  Logger.info("Gen3 tileset pairs: %d (the unit a metatile actually draws from)",
              pairCount)
end

-- One key per (primary, secondary) pair; nil when there is no primary.
function RomExtractorGen3:tilesetPairKey(primary, secondary)
  if not primary then return nil end
  if secondary then
    return ("TILESET_%07X_%07X"):format(primary, secondary)
  end
  return ("TILESET_%07X_NONE"):format(primary)
end


-- ---------------------------------------------------------------------------
-- STAGE: battle tables
--
-- The two things a Gen 3 battle needs that no earlier generation has, and that
-- cannot be computed from anything the engine already knows.
--
-- NATURES.  25 of them, each raising one stat by 10% and lowering another,
-- and five of the 25 are neutral because the two coincide.  The cartridge
-- stores this as a 25x5 grid of -1/0/+1 whose stat order is NOT the base-stat
-- order: it omits HP entirely and runs Atk, Def, Speed, SpAtk, SpDef.  Getting
-- that order wrong would swap Speed and Special on every nature in the game.
--
-- EXPERIENCE CURVES.  Gen 1 and Gen 2 get away with closed-form polynomials;
-- src/pokemon/Growth.lua has all six of theirs.  Gen 3 adds ERRATIC and
-- FLUCTUATING, which have NO closed form -- they are piecewise, with different
-- rules over different level bands -- so the table has to come off the
-- cartridge or those 28 species level at the wrong rate for their whole life.
-- The other four are emitted too, so the whole set comes from one source.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractBattleTables()
  self:beginStage("Gen3 battle tables")
  local constants = self._constants or {}

  local natureBase = self:symbol("gNatureStatTable")
  local nameBase = self:symbol("gNatureNamePointers")
  if natureBase then
    -- the cartridge's own stat order for this table, straight from the manifest
    local order = self.layout.natureStatOrder
      or { "attack", "defense", "speed", "spatk", "spdef" }
    local natures, ids, neutral = {}, {}, 0
    for i = 0, 24 do
      local name = ("NATURE_%02d"):format(i)
      if nameBase then
        local p = self.rom:pointer(nameBase + i * 4)
        if p then
          local decoded = self:readString(p, 16)
          if decoded and decoded ~= "" then name = decoded end
        end
      end
      local record = { id = name, index = i, name = name, modifiers = {} }
      for slot, stat in ipairs(order) do
        local v = self.rom:s8(natureBase + i * 5 + slot - 1)
        if v > 0 then record.raises = stat
        elseif v < 0 then record.lowers = stat end
        -- 10% up or down, expressed the way the stat code will apply it
        record.modifiers[stat] = v > 0 and 110 or v < 0 and 90 or 100
      end
      if not record.raises then neutral = neutral + 1 end
      natures[name] = record
      ids[i + 1] = name
    end
    constants.natures = natures
    constants.natureOrder = ids
    constants.natureStatOrder = order
    Logger.info("Gen3 natures: 25 (%d neutral, %s ... %s)",
                neutral, ids[1], ids[25])
  else
    Logger.warn("gen3: gNatureStatTable is not in the manifest -- natures skipped")
  end

  local expBase = self:symbol("gExperienceTables")
  if expBase then
    local order = self.layout.growthRateOrder
      or { "MEDIUM_FAST", "ERRATIC", "FLUCTUATING", "MEDIUM_SLOW", "FAST", "SLOW" }
    local maxLevel = self:layoutValue("maxLevel", 100)
    local tables = {}
    for row, name in ipairs(order) do
      local curve = {}
      for level = 0, maxLevel do
        -- 1-based by LEVEL, so curve[1] is the exp needed for level 1
        curve[level + 1] = self.rom:u32(expBase + (row - 1) * (maxLevel + 1) * 4
                                        + level * 4)
      end
      tables[name] = curve
    end
    constants.experienceTables = tables
    constants.maxLevel = maxLevel
    Logger.info("Gen3 experience: %d curves x %d levels (ERRATIC L100 = %d, "
                .. "FLUCTUATING L100 = %d)", #order, maxLevel + 1,
                tables.ERRATIC and tables.ERRATIC[maxLevel + 1] or -1,
                tables.FLUCTUATING and tables.FLUCTUATING[maxLevel + 1] or -1)
  else
    Logger.warn("gen3: gExperienceTables is not in the manifest -- "
                .. "ERRATIC and FLUCTUATING species would level at the "
                .. "MEDIUM_FAST rate")
  end

  self._constants = constants
  self:write("constants", constants)
end


-- ---------------------------------------------------------------------------
-- STAGE: intro and title scenes
--
-- The title screen and the intro have no table of contents on the cartridge.
-- Their graphics are loaded by code walking a list of (pointer, destination)
-- words into LZDecompressVram, so the lists are found by SHAPE -- alternating
-- compressed-blob pointers and video-RAM addresses, which nothing else in the
-- ROM looks like -- and tools/gen3_discover.py records the triples.
--
-- Which blob is the art is settled by a hard constraint rather than by size:
-- a tilemap can only name tiles its own sheet contains, so the real pairing is
-- the one where the highest tile id fits, and fits TIGHTLY.  The `fit` field
-- carries that ratio; 1.00 means the tilemap reaches the sheet's last tile,
-- which is what a map built for that sheet looks like.  Sizing alone gets the
-- title screen's cloud layer backwards -- 3584 bytes of art against a
-- 2048-byte tilemap -- and renders confetti.
--
-- KNOWN GAP: a palette is recorded only when the list's own span holds exactly
-- ONE pointer that could be one.  Scoring candidates by how many colours they
-- produce was tried and rejected -- it accepts palettes that render a
-- coherent-looking picture in entirely the wrong colours, which is worse than
-- admitting the palette is unknown.  Scenes with no unambiguous candidate are
-- written WITHOUT one and render colourless on purpose.
-- ---------------------------------------------------------------------------

function RomExtractorGen3:extractScenes()
  self:beginStage("Gen3 intro and title")
  local scenes = self.manifest.scenes
  if type(scenes) ~= "table" or #scenes == 0 then
    Logger.warn("gen3: no scenes in the manifest -- intro and title skipped")
    return
  end

  local out, decoded, exact, failed, checked = {}, 0, 0, 0, 0
  for index, scene in ipairs(scenes) do
    -- keyed by the SHEET, not by the loader: several functions load the same
    -- layer, and one function loads several (the title is Rayquaza plus clouds)
    local id = ("SCENE_%07X"):format(scene.graphics or index)
    if not out[id] then
      local ok, err = pcall(function()
        local tiles = self.rom:lz77(scene.graphics)
        local tmap = self.rom:lz77(scene.tilemap)
        if not (tiles and tmap) then error("blob did not decompress") end

        -- Replay the palette loads the loader function performs, in order,
        -- into a 256-colour background buffer.  This is what the hardware ends
        -- up holding, and it is why a scene's colours are a BANK rather than a
        -- single palette: the title screen loads fifteen palettes in one call
        -- and its tilemap picks between them per cell.
        local bank, loaded = {}, 0
        for _, load in ipairs(scene.paletteLoads or {}) do
          local raw = load.compressed and self.rom:lz77(load.source)
                      or self.rom:bytes(load.source, load.size)
          if raw then
            for i = 0, math.floor(math.min(load.size, #raw) / 2) - 1 do
              local slot = load.offset + i
              if slot < 256 then
                local lo, hi = raw[i * 2 + 1], raw[i * 2 + 2]
                local r, g, b = RomGba.bgr555(lo + hi * 256)
                bank[slot + 1] = { r, g, b }
                loaded = loaded + 1
              end
            end
          end
        end
        if loaded == 0 then error("no palette could be read from the loader") end

        -- The check that makes this worth trusting.  A wrong palette is the
        -- worst kind of wrong: it still renders a coherent picture, just in
        -- the wrong colours, so it survives being looked at.  What it cannot
        -- survive is arithmetic -- every visible pixel must land on a colour
        -- the loader actually loaded, and a scene that fails is dropped.
        local blank = 0
        for c = 0, math.floor(#tmap / 2) - 1 do
          local e = tmap[c * 2 + 1] + tmap[c * 2 + 2] * 256
          local tid, pl = e % 1024, math.floor(e / 4096) % 16
          local base = tid * 32
          for k = 1, 32 do
            local byte = tiles[base + k]
            if not byte then break end
            local lo, hi = byte % 16, math.floor(byte / 16)
            if lo ~= 0 and not bank[pl * 16 + lo + 1] then blank = blank + 1 end
            if hi ~= 0 and not bank[pl * 16 + hi + 1] then blank = blank + 1 end
          end
          if blank > 0 then break end
        end
        if blank > 0 then
          error(("%d pixels use a colour the loader never loads"):format(blank))
        end
        checked = checked + 1

        local pixels = {}
        for k = 1, #tiles do pixels[k] = string.char(tiles[k]) end
        local mapBytes = {}
        for k = 1, #tmap do mapBytes[k] = string.char(tmap[k]) end

        -- `fit` is how far into the sheet the tilemap reaches: 1.00 means its
        -- highest tile id is the sheet's last tile, which is what a tilemap
        -- built for that sheet looks like.
        local fitted = (tonumber(scene.fit) or 0) >= 0.99
        if fitted then exact = exact + 1 end

        local cells = math.floor(#tmap / 2)
        out[id] = {
          id = id,
          index = index - 1,
          loader = scene["function"],
          graphics = scene.graphics,
          graphicsDest = scene.graphicsDest,
          tilemap = scene.tilemap,
          tilemapDest = scene.tilemapDest,
          fit = scene.fit,
          exactFit = fitted or nil,
          tileCount = math.floor(#tiles / 32),
          tiles = table.concat(pixels),
          map = table.concat(mapBytes),
          mapWidth = 32, mapHeight = math.max(1, math.floor(cells / 32)),
          palettes = bank,
          paletteLoads = scene.paletteLoads,
          source = ("ROM:loader %07X"):format(scene["function"] or 0),
        }
        decoded = decoded + 1
      end)
      if not ok then
        failed = failed + 1
        Logger.warn("gen3 scene %s: %s", id, tostring(err))
      end
    end
    self:tick("Gen3 intro and title", index, #scenes)
  end

  out._romInfo = { source = "RomExtractorGen3", sceneCount = decoded,
                   paletteChecked = checked, exactFit = exact, failed = failed }
  self:write("scenes", out)
  Logger.info("Gen3 intro and title: %d layers, %d pairing their sheet "
              .. "exactly, %d with every pixel on a loaded colour, %d dropped",
              decoded, exact, checked, failed)
end

-- The save file's shape.  None of this is a guess and none of it is a
-- constant typed from memory: the sector layout is the one table in 16 MiB
-- with fourteen chunks that tile three structures exactly, and the 24
-- substructure orders were recovered by interpreting the switch that decides
-- them, one case at a time.  Both travel in the manifest; this stage is what
-- puts them where the runtime codec can reach them.
function RomExtractorGen3:extractSaveLayout()
  self:beginStage("Gen3 save layout")
  local save = self.manifest.save
  local orders = self.manifest.substructOrders
  local fields = self.manifest.saveFields
  if type(save) ~= "table" or type(orders) ~= "table" then
    Logger.warn("gen3: the manifest carries no save layout -- save import "
                .. "will refuse rather than guess one")
    return
  end

  -- Re-derive the totals rather than trusting the manifest's own arithmetic:
  -- a layout whose chunks do not tile its structures would mis-assemble every
  -- save, and it would do it quietly.
  local block2, block1, storage = 0, 0, 0
  for id, row in ipairs(save.sectors) do
    if id == 1 then block2 = block2 + row.size
    elseif id <= 5 then block1 = block1 + row.size
    else storage = storage + row.size end
  end
  if block2 ~= save.saveBlock2Size or block1 ~= save.saveBlock1Size
     or storage ~= save.pokemonStorageSize then
    error("gen3 save layout: the chunks do not add up to their structures")
  end
  for _, row in ipairs(orders) do
    local seen = {}
    for _, slot in ipairs(row) do seen[slot] = true end
    if not (seen[0] and seen[1] and seen[2] and seen[3]) then
      error("gen3 save layout: a substructure order is not a permutation")
    end
  end

  -- The field offsets have a check of their own that has to hold: the flag
  -- bytes and the variables abut, and the game stats begin exactly where the
  -- variables end.  Three offsets derived three different ways agreeing to the
  -- byte is the evidence; if it stops holding, something upstream moved.
  if type(fields) == "table" then
    local b1 = fields.saveBlock1 or {}
    if not (b1.flags and b1.vars and b1.gameStats) then
      error("gen3 save layout: the block fields are incomplete")
    end
    if b1.vars - b1.flags ~= fields.flagBytes
       or b1.gameStats - b1.vars ~= fields.varCount * 2 then
      error(("gen3 save layout: flags/vars/stats stopped tiling (%d, %d, %d)")
            :format(b1.flags, b1.vars, b1.gameStats))
    end

    -- And the other run, which is the stronger evidence of the two: the party,
    -- money, coins, the registered item, the PC slots and the five bag pockets
    -- were each found a different way, and they have to lie end to end.
    local bag, party = fields.bag, fields.party
    if bag and party then
      local at = party.start + party.size * party.monSize
      for _, piece in ipairs({ { b1.money, 4 }, { b1.coins, 2 },
                               { b1.coins + 2, 2 },
                               { bag.pcItems, bag.pcItemCount * bag.itemSlotSize } }) do
        if piece[1] ~= at then
          error(("gen3 save layout: the SaveBlock1 run broke at +%04X (expected "
                 .. "+%04X)"):format(piece[1], at))
        end
        at = at + piece[2]
      end
      for i, off in ipairs(bag.pockets) do
        if off ~= at then
          error(("gen3 save layout: bag pocket %d starts at +%04X, not +%04X")
                :format(i, off, at))
        end
        at = at + bag.capacities[i] * bag.itemSlotSize
      end
    end

    -- The boxes' shape is forced by three constants and the storage size, so
    -- it has to close exactly on that size.
    local st = fields.storage
    if st then
      if st.boxes + st.boxCount * st.boxCapacity * st.boxMonSize ~= st.boxNames
         or st.boxNames + st.boxCount * st.boxNameLength ~= st.boxWallpapers
         or st.boxWallpapers + st.boxCount ~= save.pokemonStorageSize then
        error("gen3 save layout: the boxes do not close on the storage size")
      end
    end
  end

  local out = {
    sectorSize = save.sectorSize,
    sectorsPerSlot = save.sectorsPerSlot,
    security = save.security,
    sectors = save.sectors,
    saveBlock2Size = save.saveBlock2Size,
    saveBlock1Size = save.saveBlock1Size,
    pokemonStorageSize = save.pokemonStorageSize,
    substructOrders = orders,
    fields = fields,
    _romInfo = { source = "RomExtractorGen3",
                 sectors = #save.sectors, orders = #orders,
                 fields = fields ~= nil,
                 total = block2 + block1 + storage },
  }
  self:write("save_layout", out)
  Logger.info("Gen3 save layout: %d sectors covering %d bytes, %d "
              .. "substructure orders", #save.sectors,
              block2 + block1 + storage, #orders)
end

-- The music.  Gen 1 and Gen 2 drive four Game Boy channels from a small note
-- engine; Gen 3 uses M4A, which sequences tracks against voicegroups of
-- sampled instruments and mixes them in software.  Nothing about the existing
-- audio path applies.
--
-- What this stage writes is the SHAPE of the music, not the music: which songs
-- exist, how many tracks each has, which voicegroup it plays against and where
-- its samples live.  The audio itself is megabytes and belongs in the asset
-- pass; what the engine needs first is to know what it is being asked to play.
function RomExtractorGen3:extractSongs()
  self:beginStage("Gen3 music")
  local at = self.manifest.symbols and self.manifest.symbols.gSongTable
  if not at then
    Logger.warn("gen3: no song table in the manifest -- music skipped")
    return
  end

  local total = (self.manifest.layout and self.manifest.layout.numSongs) or 0
  local out, playable, tracks, groups = {}, 0, 0, {}
  for i = 0, total - 1 do
    local header = self.rom:pointer(at + i * 8)
    if header then
      local trackCount = self.rom:u8(header)
      local row = {
        id = ("SONG_%03X"):format(i),
        index = i,
        header = header,
        trackCount = trackCount,
        blockCount = self.rom:u8(header + 1),
        priority = self.rom:u8(header + 2),
        reverb = self.rom:u8(header + 3),
        player = self.rom:u16(at + i * 8 + 4),
        source = ("ROM:song %d at %07X"):format(i, header),
      }
      if trackCount > 0 then
        row.voicegroup = self.rom:pointer(header + 4)
        row.tracks = {}
        for k = 1, trackCount do
          row.tracks[k] = self.rom:pointer(header + 4 + k * 4)
        end
        playable = playable + 1
        tracks = tracks + trackCount
        if row.voicegroup then groups[row.voicegroup] = true end
      end
      out[row.id] = row
    end
    self:tick("Gen3 music", i + 1, total)
  end

  local groupCount = 0
  for _ in pairs(groups) do groupCount = groupCount + 1 end

  -- The same check the manifest made, restated here against what was actually
  -- written: a song that claims tracks has to have a pointer for every one of
  -- them, or the table was read at the wrong stride.
  local missing = 0
  for id, row in pairs(out) do
    if row.trackCount and row.trackCount > 0 then
      for k = 1, row.trackCount do
        if not row.tracks[k] then missing = missing + 1 end
      end
    end
  end
  if missing > 0 then
    error(("gen3 music: %d track pointers are missing"):format(missing))
  end

  out._romInfo = { source = "RomExtractorGen3", songCount = total,
                   playable = playable, trackCount = tracks,
                   voicegroups = groupCount, table = at }
  self:write("songs", out)
  Logger.info("Gen3 music: %d song slots, %d playable, %d tracks, %d voicegroups",
              total, playable, tracks, groupCount)
end

RomExtractorGen3.DATA_STAGES = {
  "extractConstants", "extractMoves", "extractPokemon", "extractItems",
  "extractTypeChart", "extractTrainers", "extractMachines",
  "extractEncounters", "extractEggMoves", "extractDexEntries",
  "extractTrainerClasses", "extractTutorMoves", "extractBattleTables",
  "extractText",
  -- world data: layouts first (it collects the tileset addresses), then maps
  -- (which collects the script roots), then the scripts those roots reach
  "extractMapLayouts", "extractMaps", "extractMapScripts",
  "extractMovementScripts", "extractScriptText", "extractTilesets",
  "extractScenes", "extractSaveLayout", "extractSongs",
}

-- Assets are wrapped in pcall the way Gen 2's are: a sprite that fails to
-- decompress must not take the whole import down with it, because the data
-- modules are the part that decides whether the game boots at all.
RomExtractorGen3.ASSET_STAGES = {
  "extractSprites", "extractTrainerSprites",
}

function RomExtractorGen3:run()
  for _, stage in ipairs(RomExtractorGen3.DATA_STAGES) do
    self[stage](self)
  end
  for _, stage in ipairs(RomExtractorGen3.ASSET_STAGES) do
    local ok, err = pcall(self[stage], self)
    if not ok then
      Logger.warn("gen3 %s failed: %s", stage, tostring(err))
    end
  end
  if self.progress then
    self.progress(STAGE_COUNT, STAGE_COUNT, "Ready", 1, 1)
  end
end

RomExtractorGen3.STAGE_COUNT = STAGE_COUNT

return RomExtractorGen3
