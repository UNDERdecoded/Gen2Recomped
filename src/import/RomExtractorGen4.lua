-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Gen 4 (Platinum) extractor: cartridge in, cache out.
--
-- Eleven modules under src/import read Platinum correctly and none of them
-- writes anything.  This is the stage runner that puts them in order and
-- lands their output in data/generated, which is what CacheFs.mountVersion
-- serves to a running game.
--
-- IT TAKES A PATH, NOT THE ROM'S BYTES, and that is the one place it refuses
-- to look like RomExtractorGen2 and RomExtractorGen3.  Those are handed the
-- whole cartridge as a Lua string because a Game Boy ROM is at most 32 MiB
-- and every stage wants a different part of it.  Platinum is 128 MiB, the
-- engine has to run alongside it on a phone, and almost every stage wants ONE
-- FILE out of a filesystem.  NdsRom reads ranges on demand from an open
-- handle; handing it a 128 MiB string instead would undo that before the
-- first stage ran.
--
-- The consequence is that RomImporter's `startData` path cannot drive this as
-- it drives the others: it reads the file into memory and hashes the string.
-- Verification still needs the bytes, but extraction must not, so an import
-- that reaches this point has to pass the path along.  That is a real seam
-- and it is not built yet -- see the note at the bottom of this file.
--
-- WHAT EACH STAGE WRITES, and why the shape is what it is: every table is
-- keyed the way the engine already expects for Gen 1-3, because
-- Commands.resolve, the party screens and the Pokedex are
-- generation-agnostic and a fourth spelling of "species" would be a fourth
-- set of branches in code that currently has none.

local RomExtractorGen4 = {}
RomExtractorGen4.__index = RomExtractorGen4

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local Gen4Text = require("src.import.Gen4Text")
local Gen4Species = require("src.import.Gen4Species")
local Gen4Moves = require("src.import.Gen4Moves")
local Gen4Items = require("src.import.Gen4Items")
local Gen4Mart = require("src.import.Gen4Mart")
local Gen4Shadow = require("src.import.Gen4Shadow")
local Gen4Behaviors = require("src.import.Gen4Behaviors")
local Gen4InitScripts = require("src.import.Gen4InitScripts")
local Gen4Encounters = require("src.import.Gen4Encounters")
local Gen4Trainers = require("src.import.Gen4Trainers")
local Gen4Maps = require("src.import.Gen4Maps")
local Gen4Events = require("src.import.Gen4Events")
local Gen4MapHeaders = require("src.import.Gen4MapHeaders")
local Gen4Script = require("src.import.Gen4Script")
local Gen4ScriptOps = require("src.import.Gen4ScriptOps")
local Gen4Movement = require("src.import.Gen4Movement")
local Gen4Graphics = require("src.import.Gen4Graphics")
local Gen4HealthboxParts = require("src.import.Gen4HealthboxParts")
local Gen4Subscreen = require("src.import.Gen4Subscreen")
local Gen4Icons = require("src.import.Gen4Icons")
local Gen4ItemIcons = require("src.import.Gen4ItemIcons")
local Gen4SpecialChars = require("src.import.Gen4SpecialChars")
local Gen4Trades = require("src.import.Gen4Trades")
local Gen4Elevators = require("src.import.Gen4Elevators")
local Gen4Archives = require("src.import.Gen4Archives")
local Gen4Screens = require("src.import.Gen4Screens")
local Gen4Battle = require("src.import.Gen4Battle")
local Gen4MoveAnim = require("src.import.Gen4MoveAnim")
local Gen4Particle = require("src.import.Gen4Particle")
local Gen4CellAnim = require("src.import.Gen4CellAnim")
local Gen4Cells = require("src.import.Gen4Cells")
local Gen4Font = require("src.import.Gen4Font")
local Gen4Tileset = require("src.import.Gen4Tileset")
local Gen4TypeChart = require("src.import.Gen4TypeChart")
local Gen4Models = require("src.import.Gen4Models")
local Gen4Pokegra = require("src.import.Gen4Pokegra")
local Gen4Trgra = require("src.import.Gen4Trgra")
local Gen4Otherpoke = require("src.import.Gen4Otherpoke")
local Gen4ObjectGfx = require("src.import.Gen4ObjectGfx")
local Gen4Facings = require("src.import.Gen4Facings")
local Gen4Terrain = require("src.import.Gen4Terrain")
local Gen4AreaLight = require("src.import.Gen4AreaLight")
local Gen4PropShapes = require("src.import.Gen4PropShapes")
local Gen4ScriptBands = require("src.import.Gen4ScriptBands")
local Gen4Pickups = require("src.import.Gen4Pickups")
local Gen4Bdhc = require("src.import.Gen4Bdhc")
local Gen4DistWorld = require("src.import.Gen4DistWorld")
local Gen4Field = require("src.import.Gen4Field")
local Gen4Menus = require("src.import.Gen4Menus")
local Gen4IntroScene = require("src.import.Gen4IntroScene")
local Gen4Dex = require("src.import.Gen4Dex")
local Gen4Sdat = require("src.import.Gen4Sdat")
local Gen4Naming = require("src.import.Gen4Naming")
local Gen4Nsbmd = require("src.import.Gen4Nsbmd")
local Gen4ModelPack = require("src.import.Gen4ModelPack")
local Gen4Anim = require("src.import.Gen4Anim")
local ImageWriter = require("src.import.ImageWriter")
local Gen4ScriptVM = require("src.script.Gen4ScriptVM")
local LuaWriter = require("src.import.LuaWriter")

local floor = math.floor

-- THE TIMING IS THIS PORT'S, NOT THE CARTRIDGE'S.  Platinum times its two
-- battle-sprite frames from a per-species animation script that is not
-- extracted, so the pattern below is the same two-beats-out-and-back settle
-- Gen 3's stage uses -- deliberately identical, so a Pokemon does not move at
-- one speed in Hoenn and another in Sinnoh for no reason anyone chose.
local GEN4_PIC_ANIM_PLAY = {
  { frame = 1, dur = 8 }, { frame = 2, dur = 8 },
  { frame = 1, dur = 8 }, { frame = 2, dur = 8 },
  { frame = 1, dur = 8 },
}

-- Cartridge paths, in one place.  A stage that spells one itself is a stage
-- that keeps working after the path it wanted stops existing.
local PATH = {
  text = "/msgdata/pl_msg.narc",
  personal = "/poketool/personal/pl_personal.narc",
  learnsets = "/poketool/personal/wotbl.narc",
  evolutions = "/poketool/personal/evo.narc",
  moves = "/poketool/waza/pl_waza_tbl.narc",
  items = "/itemtool/itemdata/pl_item_data.narc",
  encounters = "/fielddata/encountdata/pl_enc_data.narc",
  trainerData = "/poketool/trainer/trdata.narc",
  trainerParty = "/poketool/trainer/trpoke.narc",
  matrices = "/fielddata/mapmatrix/map_matrix.narc",
  land = "/fielddata/land_data/land_data.narc",
  events = "/fielddata/eventdata/zone_event.narc",
  scripts = "/fielddata/script/scr_seq.narc",
  mapNames = "/fielddata/maptable/mapname.bin",
  areaData = "/fielddata/areadata/area_data.narc",
  battleBg = "/battle/graphic/pl_batt_bg.narc",
  battleObj = "/battle/graphic/pl_batt_obj.narc",
  fonts = "/graphic/pl_font.narc",
  overworld = "/data/mmodel/mmodel.narc",
  pokegra = "/poketool/pokegra/pl_pokegra.narc",
  trainerFront = Gen4Trgra.PATH,
  growthTables = "/poketool/personal/pl_growtbl.narc",
  pokeHeight = "/poketool/pokegra/height.narc",
  otherpoke = "/poketool/pokegra/pl_otherpoke.narc",
  trades = Gen4Trades.PATH,
  winframe = "/graphic/pl_winframe.narc",
  title = "/demo/title/titledemo.narc",
  intro = Gen4IntroScene.PATH,
  introTv = Gen4IntroScene.TV_PATH,
  naming = Gen4Naming.PATH,
  dex = Gen4Dex.PATH,
}
RomExtractorGen4.PATH = PATH

-- Message banks, each found by looking rather than assumed -- see the module
-- that uses it for what identified it.
local BANK = {
  species = 412, dexEntry = 706,
  -- THE POKEDEX'S OWN THREE, and they are STRINGS in the cartridge rather
  -- than numbers: height, weight and the category line ("Seed Pokemon") are
  -- one pre-formatted entry per species, which is why `infomain.c` renders
  -- them with a MessageLoader and no formatting of its own.
  --
  -- Taken from pokeplatinum's `generated/text_banks.txt`, whose zero-based
  -- line numbers ARE the cartridge's bank ids -- checked against every bank
  -- this table already had: 202 nature, 391/392 item, 619/620 trainer class,
  -- 646/647/648 move, and 706, which that list names
  -- TEXT_BANK_SPECIES_POKEDEX_ENTRY_EN.  Nine out of nine, so the tenth is
  -- not a guess.
  --
  -- 708 and 710 are the GIRA variants, which `pokedex_data_index.c` selects
  -- for the Origin Forme dex; the ordinary path takes 707 and 709.
  dexWeight = 707, dexHeight = 709, dexCategory = 711,
  -- The labels on the page: 9 is "HT", 10 is "WT", 0 "SEEN", 1 "OBTAINED".
  pokedex = 697,
  nature = 202, typeName = 624,
  move = 647, moveUpper = 648,
  item = 392, itemDescription = 391,
  moveDescription = 646,
  trainer = 618, mapLabel = 433,
  -- 105 entries, found by looking rather than assumed: bank 619 answers
  -- "Youngster" and "Lass" at 2 and 3, which is exactly where the trainer
  -- class list puts them.  620 is the same list with articles ("a Youngster").
  trainerClass = 619, trainerClassArticle = 620,
  -- 21 entries, read out of the cartridge rather than taken on trust: 0 is
  -- CONTINUE, 1 is NEW GAME and 12 is PLAYER, which is the order
  -- main_menu.c's own sOptions/sContinueOptionStringsIDs tables expect.
  -- 14 is the six-entry alerts bank the NEW GAME warning lives in.
  mainMenu = Gen4Menus.BANK, mainMenuAlert = Gen4Menus.ALERT_BANK,
  -- 53 entries: 0 OPTIONS, 3 TEXT SPEED, 10-12 SLOW/MID/FAST, 22-41 the
  -- twenty frame names, 43-48 the descriptions.
  options = Gen4Menus.OPTIONS_BANK,
  -- 8 entries: the briefcase's lines and the three offers.
  starter = Gen4Menus.STARTER_BANK,
  -- 12 entries: the seven the field menu shows, RETIRE and CHAT, and the
  -- three Safari/Park lines.  Entry 3 is a TEMPLATE, not a word.
  startMenu = Gen4Menus.START_BANK,
  -- 8 entries, one per pocket, in the order an item's `fieldPocket` numbers
  -- them -- so the index is the pocket rather than a lookup away from it.
  bagPockets = Gen4Menus.BAG_BANK,
  -- 187 entries: the summary screen's six page titles, every field label, and
  -- the twenty-five nature and twenty-five characteristic lines.
  summary = Gen4Menus.SUMMARY_BANK,
  -- The Poketch's twenty-five apps: 29 has them in app order, 213 has their
  -- names picked out in colour.  See Gen4Menus.POKETCH_DESC_BANK.
  poketchDesc = Gen4Menus.POKETCH_DESC_BANK,
  poketchName = Gen4Menus.POKETCH_NAME_BANK,
  -- 45 entries and 1: Rowan's introduction, and the television broadcast
  -- that plays before it.  Both checked entry by entry against the
  -- cartridge rather than taken from the header.
  rowanIntro = Gen4IntroScene.BANK, rowanIntroTv = Gen4IntroScene.TV_BANK,
  -- 205 entries: the party screen's question lines, its submenu, the six
  -- place words and ABLE!/UNABLE!/LEARNED.  See Gen4Menus.PARTY_BANK for how
  -- 453 was got and what confirms it.
  partyMenu = Gen4Menus.PARTY_BANK,
  -- 8 entries: the four traded Pokemon's nicknames then the four trainers who
  -- owned them, which is `NPCTrade_GetOTName`'s own `MAX_NPC_TRADES + id`.
  tradeNames = Gen4Trades.NAME_BANK,
}
RomExtractorGen4.BANK = BANK

local STAGES = {
  -- THE PROGRESS BAR'S DENOMINATOR, so a stage added to `run()` and not to this
  -- list makes the bar run past its own end. `gen4_move_anims` sits beside
  -- "moves" for the same reason it does in `run()`: it is the same 501 slots
  -- read a second way.
  --
  -- BOTH ANIMATION STAGES CARRY THE `gen4_` PREFIX, and that is not cosmetic --
  -- it is the whole reason the move animations were dead. `Data` loads a Gen 4
  -- table by its FILE NAME, and only the prefixed ones are on its Gen 4 list,
  -- so a stage writing `move_anims.lua` wrote a file nothing ever opened:
  -- `Gen4MoveAnimPlayer.new` reads `data.gen4_move_anims`, found nil on every
  -- boot and returned nil, and every move in Platinum fell through to the
  -- fallback animation. Written on every import, loaded by nothing -- the same
  -- trap `gen4_species_sprites` sat in, and `tools/gen4_cache_wiring_check.lua`
  -- now exists so the third one cannot hide.
  "text", "species", "moves", "gen4_move_anims", "gen4_particles",
  "gen4_cellactors", "items", "encounters",
  "trainers", "maps", "events", "regions", "tilesets", "scripts", "link",
  "graphics", "fonts", "constants", "overworld", "species_sprites",
  "trainer_sprites",
  "heights", "field", "menus", "intro", "naming", "dex", "cries", "models",
  "terrain", "distortion",
}
RomExtractorGen4.STAGES = STAGES

function RomExtractorGen4.new(romPath, version, manifest, progress)
  local rom, err = NdsRom.open(romPath)
  if not rom then return nil, err end
  return setmetatable({
    rom = rom, version = version, manifest = manifest,
    progress = progress, stage = 0, wrote = {},
  }, RomExtractorGen4)
end

function RomExtractorGen4:close()
  if self.rom then self.rom:close() end
  self.rom = nil
end

function RomExtractorGen4:beginStage(name)
  self.stage = self.stage + 1
  if self.progress then self.progress(self.stage - 1, #STAGES, name, 0, 1) end
end

function RomExtractorGen4:tick(name, current, total)
  if self.progress and total > 0 then
    self.progress(self.stage - 1 + current / total, #STAGES, name, current, total)
  end
end

function RomExtractorGen4:write(name, value)
  LuaWriter.write("data/generated/" .. name .. ".lua", value)
  self.wrote[#self.wrote + 1] = name
end

-- An archive, parsed once and remembered: land_data alone is 16 MB and three
-- stages want it.
function RomExtractorGen4:archive(key)
  self._archives = self._archives or {}
  if self._archives[key] then return self._archives[key] end
  local path = PATH[key]
  if not path then return nil, ("no cartridge path named %q"):format(tostring(key)) end
  local bytes, readErr = self.rom:read(path)
  if not bytes then return nil, readErr end
  local arc, parseErr = Narc.parse(bytes)
  if not arc then return nil, ("%s: %s"):format(path, tostring(parseErr)) end
  self._archives[key] = arc
  return arc
end

-- The same, for an archive named by its cartridge path rather than by a key
-- in PATH.  The graphics stage walks a table of paths, so keying every one of
-- them in PATH would be a second list to keep in step with the first.
function RomExtractorGen4:archiveAt(path)
  self._archives = self._archives or {}
  if self._archives[path] then return self._archives[path] end
  local bytes = self.rom:read(path)
  if not bytes then return nil end
  local arc = Narc.parse(bytes)
  if not arc then return nil end
  self._archives[path] = arc
  return arc
end

function RomExtractorGen4:bank(n)
  self._banks = self._banks or {}
  if self._banks[n] then return self._banks[n] end
  local arc = self:archive("text")
  if not arc then return nil end
  local b = Gen4Text.bank(arc:get(n))
  self._banks[n] = b
  return b
end

function RomExtractorGen4:string(bankId, index)
  local b = self:bank(bankId)
  if not b or index == nil or index >= b.count then return nil end
  return Gen4Text.render(Gen4Text.codes(b, index))
end

-- ---------------------------------------------------------------------------
-- Stages
-- ---------------------------------------------------------------------------

-- Every bank, flattened.  This is the biggest single table the cache holds --
-- 46,053 strings -- and it is written whole rather than per-consumer, because
-- a script's `message` names a bank and an entry and nothing else knows in
-- advance which of the 724 banks a given map will reach for.
function RomExtractorGen4:extractText()
  self:beginStage("text")
  local arc = assert(self:archive("text"))
  local out = {}
  for i = 0, arc.count - 1 do
    local b = Gen4Text.bank(arc:get(i))
    if b then
      local bank = {}
      for j = 0, b.count - 1 do
        bank[j] = Gen4Text.render(Gen4Text.codes(b, j))
      end
      out[i] = bank
    end
    self:tick("text", i + 1, arc.count)
  end
  self:write("gen4_text", out)

  -- ...and the same strings again, flat, under the names the ENGINE looks them
  -- up by.  `data.text` is a map of label to string in every other generation,
  -- because Gen 1-3 address a string by one id; Gen 4 needs a bank and an
  -- index, so the label carries both.  Gen4Text.label owns the spelling, so
  -- the writer here and whatever lowers a `message` command cannot disagree.
  --
  -- Walked with pairs, NOT with a length operator: a bank is keyed from ZERO,
  -- and `#bank` on a zero-based table is nil-terminated at the first index it
  -- checks -- which for most banks is zero, so a length walk would write an
  -- empty table and report success.
  local flat, strings = {}, 0
  for bank, decoded in pairs(out) do
    for index, value in pairs(decoded) do
      flat[Gen4Text.label(bank, index)] = value
      strings = strings + 1
    end
  end
  self:write("text", flat)

  -- Required by Data.lua and read by nothing.  Gen 1 and Gen 2 keep a pointer
  -- table beside their text; Gen 4 has no equivalent, and an empty table is
  -- the honest answer -- inventing entries to fill it would put names in the
  -- cache that resolve to nothing.
  self:write("text_pointers", {})
  self.textReport = { banks = arc.count, strings = strings }

  return out
end

function RomExtractorGen4:extractSpecies()
  self:beginStage("species")
  local personal = assert(self:archive("personal"))
  local learn = assert(self:archive("learnsets"))
  local evo = assert(self:archive("evolutions"))
  local names = self:bank(BANK.species)
  local out = Gen4Species.all(personal, names, Gen4Text)
  for id, s in pairs(out) do
    s.learnset = Gen4Species.parseLearnset(learn:get(id))
    s.evolutions = Gen4Species.parseEvolutions(evo:get(id))
    s.dexEntry = self:string(BANK.dexEntry, id)
  end
  -- Kept, because the sprite stage stamps picture paths onto these very
  -- rows and rewrites the module.  Only that stage knows which pictures
  -- actually decoded, and a species whose art failed must not be handed a
  -- path to a file that is not there.
  self._pokemon = out
  self:write("pokemon", out)
  return out
end

function RomExtractorGen4:extractMoves()
  self:beginStage("moves")
  local out = Gen4Moves.all(assert(self:archive("moves")), self:bank(BANK.move), Gen4Text)
  for id, m in pairs(out) do m.description = self:string(BANK.moveDescription, id) end
  self:write("moves", out)
  return out
end

-- The move ANIMATION programs -- what a move does on screen, as opposed to
-- what it does to the other Pokemon.
--
-- `/wazaeffect/we.arc` is a NARC despite the extension and holds one bytecode
-- program per move slot.  `Gen4MoveAnim` carries the opcode widths, derived
-- from pret's handler bodies and checked by CLOSURE -- every program has to
-- walk to its exact last word, and `tools/gen4_moveanim_check.lua` asserts all
-- 501 do.  A program that does not walk is dropped and COUNTED rather than
-- written half-decoded, because a truncated animation is one that stops in the
-- middle of a battle rather than one that looks slightly wrong.
--
-- WHAT IS AND IS NOT HERE.  The program says what to load, what to play and how
-- long to wait; the visible burst of nearly every move is an `SPA ` particle
-- program in waza_particle.narc.  `particles` below is a list of INDICES INTO
-- THAT ARCHIVE -- Scratch is 40, Pound 31 -- and the `gen4_particles` stage
-- below now extracts every one of them, emitters and all, so the index is a
-- join that resolves rather than a note for later.
function RomExtractorGen4:extractMoveAnims()
  self:beginStage("gen4_move_anims")
  local arc = self:archiveAt(Gen4MoveAnim.ARCHIVE_PROGRAMS)
  if not arc then
    -- Not fatal: a cartridge without it still gives a playable game, and a
    -- stage that errors here would cost the whole import over animations.
    self:write("gen4_move_anims", { programs = {}, skipped = 0, absent = true })
    return
  end

  local programs, skipped = {}, 0
  for index = 0, arc.count - 1 do
    local data = arc:get(index)
    local decoded = data and Gen4MoveAnim.decode(data)
    if decoded then
      local code, wordAt = {}, {}
      for i, row in ipairs(decoded) do
        local instruction = { row.op }
        for j = 1, #row.args do instruction[j + 1] = row.args[j] end
        code[i] = instruction
        -- WHERE EACH INSTRUCTION STARTED, IN WORDS. 77 of the 501 programs
        -- branch, and every jump target in them is a WORD offset into the
        -- original stream -- so a player walking a decoded instruction list
        -- cannot follow one without this map. Stored as `wordAt[i]` rather
        -- than folded into the instruction so the instruction stays exactly
        -- "opcode then operands".
        wordAt[i] = row.at
      end
      local s = Gen4MoveAnim.summary(decoded)
      programs[index] = {
        code = code,
        wordAt = wordAt,
        particles = s.particles,
        sounds = s.sounds,
        delayFrames = s.delayFrames,
      }
    else
      skipped = skipped + 1
    end
    self:tick("gen4_move_anims", index + 1, arc.count)
  end

  local out = {
    programs = programs,
    count = arc.count,
    skipped = skipped,
    particleArchive = Gen4MoveAnim.ARCHIVE_PARTICLES,
  }
  self:write("gen4_move_anims", out)
  -- KEPT FOR THE NEXT STAGE. `gen4_cellactors` extracts exactly the 2D sprite
  -- resources the PROGRAMS ask for, so it needs them decoded -- and decoding all
  -- 501 a second time to learn what 38 sprites reference would be wasteful. It
  -- falls back to decoding if this is absent, so the two stages stay independent.
  self._moveAnims = out
  return out
end

-- The particle EFFECTS -- the pictures a move's animation actually throws.
--
-- `Gen4MoveAnim` decodes the program and `move_anims` writes it; this writes
-- what `loadparticlesystem <slot> <member>` points AT. Scratch's program names
-- member 40, and member 40 holds a 64x64 texture of three claw slashes: that
-- picture is the move's whole visible effect, and without it a perfectly
-- decoded program has nothing to draw.
--
-- THE TEXTURES AND THE EMITTERS. An earlier version of this stage wrote only
-- the art and said so in a comment that is worth keeping the shape of: "a
-- guessed emitter produces motion that is plausible and wrong". That was the
-- right call while the emitter layout was a guess. It is not one now -- every
-- emitter block length was measured by single-bit subtraction until all 608
-- files closed exactly on their own declared emitter area, and the field
-- offsets were then confirmed against pret's `lib/spl/include/spl_resource.h`,
-- which lays `SPLResourceHeader` out to the same 88 bytes and names the same
-- eleven flag bits. Two methods that share no assumption agreed, so the
-- emitters go in the cache.
--
-- WHY THEY GO IN AT ALL, rather than being read from the ROM at battle time:
-- the cartridge is not redistributable and the running game never opens it. A
-- decoded emitter is data about the game, the same as a base stat.
--
-- THE FIELDS ARE STORED AS `Gen4Particle` DECODES THEM, fixed point already
-- divided out, and that round-trips exactly: all 1,468 emitters survive
-- `LuaWriter` and come back bit-identical, which the wiring check asserts
-- rather than assumes.
function RomExtractorGen4:extractParticles()
  self:beginStage("gen4_particles")

  local index = { effects = {}, skipped = {}, textures = 0, emitters = 0 }
  local sources = {
    { key = "move", path = Gen4Particle.ARCHIVE_MOVES },
    { key = "ball", path = Gen4Particle.ARCHIVE_BALLS },
    { key = "opening", path = Gen4Particle.ARCHIVE_FIELD, first=4, last=4 },
  }
  local total = 0
  for _, src in ipairs(sources) do
    local arc = self:archiveAt(src.path)
    if arc then total = total + (src.first and 1 or arc.count) end
  end
  if total == 0 then
    self:write("gen4_particles", index)
    return index
  end

  local done = 0
  for _, src in ipairs(sources) do
    local arc = self:archiveAt(src.path)
    if arc then
      for member = src.first or 0, src.last or (arc.count - 1) do
        local data = arc:get(member)
        local list = data and Gen4Particle.textures(data)
        if list then
          -- THE EMITTERS ARE WHAT MAKES THE ART MOVE, and they are read here
          -- rather than inferred at battle time. `emitters()` returns nil when
          -- the blocks do not tile their own declared area exactly, so a file
          -- whose emitters did not close contributes its textures and no
          -- motion instead of motion that is wrong.
          local emitters = Gen4Particle.emitters(data)
          local entry = { textures = {}, emitters = emitters or nil }
          for i, texture in ipairs(list) do
            local image = Gen4Particle.rgba(texture)
            local name = ("particle/%s_%03d_%d"):format(src.key, member, i - 1)
            local saved = self:saveImage(name, image, {
              format = texture.formatName,
              colours = #texture.palette,
            })
            if saved then
              entry.textures[#entry.textures + 1] = saved
              index.textures = index.textures + 1
            end
          end
          -- AN EFFECT WITH EMITTERS AND NO TEXTURES IS STILL AN EFFECT.  The
          -- old gate was `#entry.textures > 0`, which was right when textures
          -- were all this stage wrote; keeping it now would drop an emitter
          -- list on the floor for a file whose art lives in another member.
          if #entry.textures > 0 or entry.emitters then
            index.effects[src.key .. "_" .. member] = entry
            if entry.emitters then
              index.emitters = (index.emitters or 0) + #entry.emitters
            end
          end
        else
          -- COUNTED, NOT DROPPED SILENTLY. A move whose effect did not decode
          -- is a move that will draw nothing, and the number is how anyone
          -- finds out without playing all 467 of them.
          index.skipped[#index.skipped + 1] = src.key .. "_" .. member
        end
        done = done + 1
        self:tick("gen4_particles", done, total)
      end
    end
  end

  self:write("gen4_particles", index)
  return index
end

-- THE 2D CELL-ACTOR SPRITES -- the third and last layer of a move's animation.
--
-- A move's visible effect is up to three things: the battlers moving (the
-- program alone), a 3D particle burst (`gen4_particles`) and a flat 2D sprite
-- animated from a cell bank. THIRTY-TWO of the 501 programs use the third, and
-- until this stage they drew nothing at all.
--
-- THIS STAGE EXTRACTS WHAT THE PROGRAMS ASK FOR, NOT EVERYTHING IN THE ARCHIVES.
-- The four archives hold 37/39/37/37 members and a sprite pairs one of each, so
-- extracting every combination would be 37 x 39 images of which 29 tuples are
-- ever named. Reading the programs first and extracting their 29 is not a
-- shortcut: it is the only version that cannot produce art nothing points at.
-- Anything a program names that does not resolve is COUNTED in `skipped`, which
-- is the number that says the join is incomplete.
function RomExtractorGen4:extractCellActors()
  self:beginStage("gen4_cellactors")

  local index = { sprites = {}, skipped = {}, images = 0, tuples = 0 }
  local char = self:archiveAt(Gen4CellAnim.ARCHIVE_CHAR)
  local pltt = self:archiveAt(Gen4CellAnim.ARCHIVE_PALETTE)
  local cellArc = self:archiveAt(Gen4CellAnim.ARCHIVE_CELL)
  local animArc = self:archiveAt(Gen4CellAnim.ARCHIVE_ANIM)
  if not (char and pltt and cellArc and animArc) then
    -- Not fatal, for the same reason the move-animation stage is not: a cache
    -- without these still plays every move's timing, sound and motion.
    self:write("gen4_cellactors", { sprites = {}, skipped = {}, images = 0,
                                    tuples = 0, absent = true })
    return
  end

  -- WHAT THE PROGRAMS NAME. `addsprite` and `addspritewithfunc` carry the four
  -- member indices directly -- pret's macro says "Index of the character
  -- resource to use. (Same as for LoadCharResObj)", so these are NARC member
  -- indices and not slots in the manager, which is the one thing here that reads
  -- like a slot and is not.
  local programs = self._moveAnims and self._moveAnims.programs
  if not programs then
    local arc = self:archiveAt(Gen4MoveAnim.ARCHIVE_PROGRAMS)
    programs = {}
    if arc then
      for i = 0, arc.count - 1 do
        local decoded = Gen4MoveAnim.decode(arc:get(i) or "")
        if decoded then
          local code = {}
          for k, row in ipairs(decoded) do
            local instruction = { row.op }
            for j = 1, #row.args do instruction[j + 1] = row.args[j] end
            code[k] = instruction
          end
          programs[i] = { code = code }
        end
      end
    end
  end

  local OP_LOAD_PALETTE = 75
  local OP_ADD_WITH_FUNC = 78
  local OP_ADD = 79
  local wanted, order = {}, {}
  for id, program in pairs(programs or {}) do
    -- The palette BANK the program uploads, per palette member. It is 1 on all
    -- 34 calls in the cartridge, and it matters: the OAM entries' own palette
    -- field then indexes what was uploaded, not the file's banks.
    local bankOf = {}
    for _, row in ipairs(program.code or {}) do
      if row[1] == OP_LOAD_PALETTE then bankOf[row[3]] = row[4] end
    end
    for _, row in ipairs(program.code or {}) do
      if row[1] == OP_ADD_WITH_FUNC or row[1] == OP_ADD then
        local c, p, ce, an = row[4], row[5], row[6], row[7]
        local key = ("%s_%s_%s_%s"):format(tostring(c), tostring(p),
                                           tostring(ce), tostring(an))
        if not wanted[key] then
          wanted[key] = { char = c, palette = p, cell = ce, anim = an,
                          bank = bankOf[p] or 0, moves = {} }
          order[#order + 1] = key
        end
        local moves = wanted[key].moves
        moves[#moves + 1] = id
      end
    end
  end
  table.sort(order)
  index.tuples = #order

  local function member(arc, i)
    if i == nil or not arc then return nil end
    local bytes = arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end

  for step, key in ipairs(order) do
    local want = wanted[key]
    local sheet = Gen4Graphics.tiles(member(char, want.char))
    local colours = Gen4Graphics.palette(member(pltt, want.palette))
    local bank = nil
    local cellBytes = member(cellArc, want.cell)
    if cellBytes then bank = Gen4Cells.parse(cellBytes, Gen4Graphics) end
    local animBytes = member(animArc, want.anim)
    local anim = animBytes and Gen4CellAnim.parse(animBytes, Gen4Graphics)

    -- THE FILE'S COLOURS ARE PADDED UP TO THE BANK ITS OAM ASKS FOR, which is
    -- what `Gen4CellAnim.paletteFor` is for -- see its comment. The script's own
    -- `paletteIndex` operand is 1 on every call in the cartridge and so cannot
    -- be what selects anything; the cell bank's OAM field can, and does.
    local oamBank = Gen4CellAnim.bankOf(bank)
    if oamBank == nil then
      index.skipped[#index.skipped + 1] = key .. " (its cell bank mixes palette banks)"
      colours = nil
    else
      colours = Gen4CellAnim.paletteFor(colours, oamBank)
    end

    if sheet and colours and bank and anim then
      local images, blank = {}, 0
      for i, cell in ipairs(bank.cells) do
        if #(cell.oam or {}) == 0 then
          -- AN EMPTY CELL IS A BLANK FRAME, not a failure. Cell 0 of members 17,
          -- 19 and 26 has no OAM entries at all and their animations name it --
          -- a deliberate beat of nothing before the sprite appears.
          blank = blank + 1
        else
          local image = Gen4Cells.assemble(cell, sheet, colours, bank,
                                           Gen4Graphics)
          local saved = image and self:saveImage(
            ("cellactor/%s_%02d"):format(key, i - 1), image,
            { cellIndex = i - 1 })
          if saved then
            images[i] = saved
            index.images = index.images + 1
          else
            index.skipped[#index.skipped + 1] =
              ("%s cell %d did not assemble"):format(key, i - 1)
          end
        end
      end
      index.blank = (index.blank or 0) + blank
      if next(images) then
        index.sprites[key] = {
          char = want.char, palette = want.palette, cell = want.cell,
          anim = want.anim, bank = want.bank,
          cells = images,
          sequences = anim.sequences,
          moves = want.moves,
        }
      else
        index.skipped[#index.skipped + 1] = key .. " (no cell assembled)"
      end
    else
      -- NAMED, NOT DROPPED: which of the four did not read is the only useful
      -- thing to know here.
      index.skipped[#index.skipped + 1] = ("%s (sheet %s palette %s bank %s anim %s)")
        :format(key, tostring(sheet ~= nil), tostring(colours ~= nil),
                tostring(bank ~= nil), tostring(anim ~= nil))
    end
    self:tick("gen4_cellactors", step, #order)
  end

  self:write("gen4_cellactors", index)
  return index
end

function RomExtractorGen4:extractItems()
  self:beginStage("items")
  local out = Gen4Items.all(assert(self:archive("items")), self:bank(BANK.item), Gen4Text)
  for id, it in pairs(out) do it.description = self:string(BANK.itemDescription, id) end
  self:write("items", out)
  return out
end

function RomExtractorGen4:extractEncounters()
  self:beginStage("encounters")
  local out = Gen4Encounters.all(assert(self:archive("encounters")))
  self:write("encounters", out)
  return out
end

-- THE FIELD CALLED `sprite` IS NOT THE CLASS, AND IS NOT ANYTHING.
--
-- A trdata header is { u8 monDataType, u8 trainerType, u8 sprite, u8 partySize,
-- u16 items[4], u32 aiMask, u32 battleType }, and the obvious reading is that
-- `sprite` says which trainer picture to draw.  Measured across all 928
-- trainers: `sprite` is ZERO for every single one, and `trainerType` is what
-- carries the class -- 102 distinct values in 0..102, against a 105-entry class
-- list.  The game agrees: TRDATA_CLASS reads `trainerType`.
--
-- Cross-checked against the overworld art, which is a table this stage does not
-- own: of the 63 classes that appear on a map, 60 are drawn as EXACTLY ONE
-- overworld sprite, and the three that are not -- `belle_and_pa`,
-- `double_team`, `young_couple` -- are pair classes fought by two visible
-- people.  A wrong join would not produce that.
function RomExtractorGen4:extractTrainers()
  self:beginStage("trainers")
  local out = Gen4Trainers.all(assert(self:archive("trainerData")),
                               assert(self:archive("trainerParty")),
                               self:bank(BANK.trainer), Gen4Text)
  local classes = self:bank(BANK.trainerClass)
  local zeroSprites, total = 0, 0
  for _, trainer in pairs(out) do
    total = total + 1
    if (trainer.sprite or 0) == 0 then zeroSprites = zeroSprites + 1 end
    -- Named `class` because that is what it is.  `trainerType` is kept so
    -- nothing that already reads it breaks.
    trainer.class = trainer.trainerType
    if classes and trainer.class and trainer.class < classes.count then
      trainer.className = Gen4Text.render(Gen4Text.codes(classes, trainer.class))
    end
  end
  self._trainers = out
  self.trainerReport = { trainers = total, zeroSprites = zeroSprites }
  self:write("trainers", out)
  return out
end

-- Headers, matrices and the permission grids.  The 3D meshes are NOT written:
-- they are the larger half of land_data and nothing renders them yet, so
-- putting 16 MB of NSBMD in the cache would cost every player disk for
-- something no code reads.
function RomExtractorGen4:extractMaps()
  self:beginStage("maps")
  local matrices = assert(self:archive("matrices"))
  local land = assert(self:archive("land"))
  local names = Gen4Maps.mapNames(assert(self.rom:read(PATH.mapNames)))
  local nameCount = 0
  for _ in pairs(names) do nameCount = nameCount + 1 end

  local limits = {
    areaData = assert(self:archive("areaData")).count,
    matrix = matrices.count,
    scripts = assert(self:archive("scripts")).count,
    messages = assert(self:archive("text")).count,
    encounters = assert(self:archive("encounters")).count,
    events = assert(self:archive("events")).count,
    names = nameCount,
  }
  local arm9 = assert(self.rom:arm9())
  local at, count = Gen4MapHeaders.find(arm9, limits)
  if not at then return nil, "map header table not found in the ARM9" end

  local headers = Gen4MapHeaders.all(arm9, at, count)
  for id, h in pairs(headers) do
    h.internalName = names[id]
    h.label = self:string(BANK.mapLabel, h.labelText)
  end
  -- Kept for the field stage, which has to turn a header id from the ARM9
  -- into the map name this cache uses.
  self._mapHeaders = headers
  local headerCount = 0
  for id in pairs(headers) do
    if id + 1 > headerCount then headerCount = id + 1 end
  end
  self._mapHeaderCount = headerCount
  self:write("gen4_map_headers", headers)

  local outMatrices = {}
  for i = 0, matrices.count - 1 do
    outMatrices[i] = Gen4Maps.matrix(matrices:get(i))
    self:tick("maps", i + 1, matrices.count)
  end
  self:write("gen4_map_matrices", outMatrices)

  -- Permissions as one binary string per chunk rather than 1,024 numbers:
  -- the same choice Gen 3's map grids make, and for the same reason -- a
  -- 666-entry table of thousand-element arrays is slow to load and enormous
  -- on disk, while a string is neither.
  local perms, objects = {}, {}
  for i = 0, land.count - 1 do
    local chunk = Gen4Maps.land(land:get(i))
    if chunk then
      perms[i] = chunk.permissions
      local o = Gen4Maps.objects(chunk)
      if #o > 0 then objects[i] = o end
    end
  end
  self:write("gen4_map_permissions", perms)
  self:write("gen4_map_objects", objects)

  -- GRIDS ARE SHARED, MAPS ARE NOT.  Several headers name the same matrix --
  -- every building in Jubilife sits on the overworld's -- so the grid is
  -- built once per MATRIX and each map id points at it, which is the same
  -- split Gen 3 makes between map_layouts and the map defs that reference
  -- them.
  --
  -- This is not a tidiness argument.  Building a def per header instead took
  -- the whole extraction from 3.9 seconds to 22, because the 30x30 overworld
  -- is 921,600 cells and it was being re-encoded once for every building that
  -- stands on it.
  local chunkCache = {}
  local function chunkFor(id)
    if not id or id >= land.count then return nil end
    if chunkCache[id] == nil then chunkCache[id] = Gen4Maps.land(land:get(id)) or false end
    return chunkCache[id] or nil
  end

  local layouts, layoutCount = {}, 0
  for i = 0, matrices.count - 1 do
    local m = Gen4Maps.matrix(matrices:get(i))
    local def = m and Gen4Maps.mapDef(m, chunkFor)
    if def then
      def.name = m.name
      layouts[i] = def
      layoutCount = layoutCount + 1
    end
    self:tick("maps", i + 1, matrices.count)
  end
  self:write("map_layouts", layouts)

  -- A GEN 4 OVERWORLD MAP IS A REGION OF A SHARED GRID, and that is the
  -- structural break the rest of this has to absorb.  84 headers name matrix
  -- 0 -- the 960x960 Sinnoh overworld -- and each is a piece of it, not a grid
  -- of its own.  The matrix's per-cell header array says which piece, so each
  -- map is cut out of the layout and given a grid it actually owns, which is
  -- the Gen 1-3 shape everything downstream already understands.
  --
  -- Only two matrices carry that array; for the other 287 the matrix IS the
  -- map and the whole layout is the grid.  Cutting is also SMALLER, not
  -- larger: the overworld's regions total 0.34 MB against the layout's 1.76,
  -- because header 0 owns 731 of the 900 chunks -- ocean, border, the space
  -- between routes -- and is not a map.
  local extents = {}
  for i = 0, matrices.count - 1 do
    local m = Gen4Maps.matrix(matrices:get(i))
    local e = m and Gen4Maps.extents(m)
    if e then extents[i] = e end
  end

  -- How many headers each matrix serves, so a shared grid is never inlined
  -- once per header that looks at it.
  local usersOf = {}
  for _, h in pairs(headers) do
    usersOf[h.matrix] = (usersOf[h.matrix] or 0) + 1
  end

  local defs, built, cropped, inlined = {}, 0, 0, 0
  for id, h in pairs(headers) do
    local mapId = names[id]
    local layout = layouts[h.matrix]
    if mapId and layout then
      local grid, region = layout, nil
      local byMatrix = extents[h.matrix]
      if byMatrix and byMatrix[id] then
        region = byMatrix[id]
        local cut = Gen4Maps.crop(layout, region.x, region.y,
                                  region.width, region.height)
        if cut then grid = cut; cropped = cropped + 1 end
      end

      -- ONLY INLINE A GRID THIS MAP OWNS.  A cropped region is its own; a
      -- matrix no other header looks at is its own.  A SHARED matrix is not,
      -- and inlining it puts the same grid in the cache once per header --
      -- the twelve headers that name the overworld without claiming chunks in
      -- it were carrying 1.76 MB each, which is 21 MB of one grid repeated.
      -- Those reference `layout` instead and read gen4_map_layouts.
      local owns = (region ~= nil) or (usersOf[h.matrix] == 1)
      if owns then inlined = inlined + 1 end

      defs[mapId] = {
        id = mapId,
        header = id,
        layout = h.matrix,
        label = self:string(BANK.mapLabel, h.labelText),
        width = grid.width,
        height = grid.height,
        blocks = owns and grid.blocks or nil,
        behaviorCells = owns and grid.behaviorCells or nil,
        borderBlock = grid.borderBlock,
        blockPx = 16,
        generation = 4,
        -- Every Gen 4 map names the same stand-in, because Gen 4 has no
        -- tileset in the Gen 1-3 sense and MapLoader will not build a map
        -- without one.  See extractTilesets.
        tileset = Gen4Tileset.ID,
        -- Where this map sits in the layout it was cut from.  Zero for a map
        -- that IS its matrix; the region's corner otherwise.  Event
        -- coordinates below are already map-local, so this is only needed to
        -- put a map back on the shared grid.
        originX = grid.originX or 0,
        originY = grid.originY or 0,
        -- A region is the bounding box of the chunks a header owns, so four
        -- of the sixty-six are not solid rectangles; flagged rather than
        -- silently squared off.
        regionSolid = region and region.solid or nil,
        encounters = h.encounters,
        events = h.events,
        allowBike = h.allowBike,
        allowRunning = h.allowRunning,
        allowEscapeRope = h.allowEscapeRope,
        allowFly = h.allowFly,
        weather = h.weather,
        -- WHICH MESSAGE BANK THIS MAP'S OWN SCRIPTS READ FROM.
        --
        -- A Gen 4 `message` command names an ENTRY, not a string: the bank is
        -- the map header's `msgArchiveID` and the pair is what addresses a
        -- line.  The header has always been parsed and the byte has never been
        -- carried, so `show_text` was handed a bare index, found nothing under
        -- it in `data.text` -- which is keyed `TEXT_Bnnnn_nnnnn` -- and
        -- degraded to an empty box.  That is "talking to people brings up a
        -- text box but its blank", exactly.
        messages = h.messages,
        -- WHICH OF PLATINUM'S SEVENTEEN FIELD CAMERAS THIS MAP USES.  The byte
        -- has always been parsed (`Gen4MapHeaders`, offset 21) and has never
        -- been carried, so every map was drawn with the same made-up
        -- straight-down view.  300 of the 593 headers are
        -- CAMERA_TYPE_INTERIOR_ORTHOGRAPHIC, 189 are DEFAULT and 60 are CAVE;
        -- see `src/render/Gen4Camera.lua` for the table they index.
        cameraType = h.camera,
        -- WHICH BATTLE BACKGROUND A FIGHT ON THIS MAP USES.
        --
        -- `MapHeader_GetBattleBG` is the whole of the cartridge's answer:
        -- `SetBackgroundAndTerrain` (field_battle_data_transfer.c) reads the
        -- header and overrides it to BACKGROUND_WATER only while the player is
        -- surfing.  The byte has been parsed since Gen4MapHeaders was written
        -- (`floor(flags / 128) % 32`) and never carried, so nothing in the
        -- engine could say where a Sinnoh battle happens -- which is half of
        -- why a Platinum fight draws on blank paper.
        --
        -- The TERRAIN is NOT this and is not stored on the map: the cartridge
        -- takes it from the tile behaviour under the player and only falls back
        -- to this background when none of ice / tall grass / sand / snow / mud
        -- / cave floor / surfable matches.  See `src/battle/Gen4Battle.lua`,
        -- which carries that rule verbatim.
        battleBackground = h.battleBackground,
        dayMusic = h.dayMusic,
        nightMusic = h.nightMusic,
      }
      built = built + 1
    end
  end
  self:linkRegions(defs)
  self._mapDefs = defs
  self.mapDefReport = { maps = built, layouts = layoutCount, headers = count,
                        cropped = cropped, inlined = inlined,
                        linked = (self.regionLinkReport or {}).maps,
                        edges = (self.regionLinkReport or {}).edges }
  return headers, names
end

-- SINNOH'S OVERWORLD IS ONE GRID, AND A MAP IS A WINDOW ONTO IT.
--
-- 84 headers name matrix 0, the 960x960 overworld, and each takes a rectangle
-- out of it.  There are no warps between them: the player walks from Twinleaf
-- Town to Route 201 and the header simply changes underfoot.  Nothing in this
-- port knew that, so the edge of every outdoor map was a cliff into terrain
-- the renderer draws and nobody owns -- reported as "im able to walk outside
-- of the boundaries still", and, once the boundary was sealed, as a town with
-- no way out.
--
-- THE ENGINE ALREADY HAS THE MACHINERY.  Gen 1-3 maps connect at their edges
-- and `OverworldState:checkEdgeExit` walks the player across a seam without a
-- warp, reading the neighbour's own collision as it goes.  A connection is
-- `{ map, offset }` where `offset` is how far the neighbour is shifted ALONG
-- the seam, and the landing is `destX = cellX - offset` (`connectionLanding`).
-- For two windows onto the same grid that offset is exactly the difference of
-- their origins, which is what makes this a derivation rather than a guess:
--
--     up / down    offset = destOriginX - originX
--     left / right offset = destOriginY - originY
--
-- ADJACENCY IS TESTED, NOT ASSUMED.  `connectionLanding` puts an upward step
-- on the destination's BOTTOM row, which is only right when the destination's
-- bottom edge IS this map's top edge; two regions that overlap or sit corner
-- to corner get no connection rather than a wrong one.  `connectionFor`
-- already narrows a multi-neighbour edge to the one covering the player's
-- position along it, using the same origin arithmetic, so a long route with
-- three maps along its side needs nothing extra here.
--
-- Measured over this cartridge: 40 layouts are shared, 69 maps come out with
-- at least one connection and there are 140 edges between them.  Twinleaf Town
-- gets `up -> Route 201` at offset 0; Route 201 gets Twinleaf below it,
-- Verity Lakefront to the west at -32 and Sandgem Town to the east; Jubilife
-- City gets Routes 203, 218, 202 and 204.  That is Sinnoh.
function RomExtractorGen4:linkRegions(defs)
  local byLayout = {}
  for _, def in pairs(defs) do
    if def.layout then
      local list = byLayout[def.layout]
      if not list then list = {} ; byLayout[def.layout] = list end
      list[#list + 1] = def
    end
  end

  local linked, edges = 0, 0
  for _, list in pairs(byLayout) do
    if #list > 1 then
      for _, a in ipairs(list) do
        local ax, ay = a.originX or 0, a.originY or 0
        local aw, ah = a.width or 0, a.height or 0
        local rows, any = {}, false
        for _, b in ipairs(list) do
          if b ~= a then
            local bx, by = b.originX or 0, b.originY or 0
            local bw, bh = b.width or 0, b.height or 0
            local overlapX = ax < bx + bw and bx < ax + aw
            local overlapY = ay < by + bh and by < ay + ah
            -- COMPASS NAMES, because that is the only spelling the engine
            -- reads.  `Map:connection` is called as
            -- `self.map:connection(COMPASS[dir])` and COMPASS turns the
            -- walker's "up" into "north" -- so a table keyed by the walking
            -- direction answers nil for every edge in the region, and every
            -- Gen 4 map with a neighbour ends at an invisible wall.  Reported
            -- from play: *"I'm supposed to walk out of town but there's an
            -- invisible wall"* -- Twinleaf's north edge, which carries a
            -- perfectly good connection to Route 201 under the wrong key.
            -- Gen 3 has written north/south/west/east all along.
            local dir
            if overlapX and by + bh == ay then dir = "north"
            elseif overlapX and by == ay + ah then dir = "south"
            elseif overlapY and bx + bw == ax then dir = "west"
            elseif overlapY and bx == ax + aw then dir = "east" end
            if dir then
              local offset = (dir == "north" or dir == "south") and (bx - ax)
                             or (by - ay)
              rows[dir] = rows[dir] or {}
              rows[dir][#rows[dir] + 1] = { map = b.id, offset = offset }
              any = true
            end
          end
        end
        if any then
          -- The record COPIES the first row's fields and points `list` at the
          -- plain array, for the reason RomExtractorGen3 gives where it builds
          -- the same shape: hanging `list = { self }` off the record makes a
          -- cyclic table and LuaWriter refuses to serialise one.
          local conns = {}
          for dir, found in pairs(rows) do
            table.sort(found, function(p, q)
              if p.offset ~= q.offset then return p.offset < q.offset end
              return tostring(p.map) < tostring(q.map)
            end)
            conns[dir] = { map = found[1].map, offset = found[1].offset,
                           list = found }
            edges = edges + #found
          end
          a.connections = conns
          linked = linked + 1
        end
      end
    end
  end
  self.regionLinkReport = { maps = linked, edges = edges }
  return linked, edges
end

-- Attach each map's events to its def, in map-local coordinates.
--
-- The events are stored per EVENT ARCHIVE and their coordinates are measured
-- from the MATRIX's corner, not the map's -- which is consistent, because on
-- the overworld the matrix is the only thing all 84 maps share.  Every one of
-- the 5,636 events in the cartridge falls inside its own map's matrix grid,
-- which is what says the coordinates are matrix-global rather than local.
--
-- Subtracting the region origin makes them local, so a Gen 4 map's objects sit
-- at the same kind of coordinates a Gen 1-3 map's do and nothing downstream
-- needs to know the difference.
--
-- GEN 4 IS 3D: X and Z are the two HORIZONTAL axes and Y is height.  So the
-- engine's `y` takes the cartridge's `z`, and the cartridge's `y` becomes
-- elevation.  Reading them in the order they appear puts every object on the
-- map's top edge.
function RomExtractorGen4:extractRegions(events, names)
  self:beginStage("regions")
  local defs = self._mapDefs or {}

  local counts = { objects = 0, warps = 0, signs = 0, coordEvents = 0 }
  local outside, dangling, dynamicWarps = 0, 0, 0

  local byHeader = {}
  for _, def in pairs(defs) do byHeader[def.header] = def end

  for header, def in pairs(byHeader) do
    local ev = events and events[def.events]
    local ox, oy = def.originX or 0, def.originY or 0
    local objects, warps, signs, coords = {}, {}, {}, {}

    -- An event outside its own map's box is not dropped.  Four regions are
    -- L-shaped and their bounding box does not cover every chunk they own, so
    -- a strict bounds test would silently delete real NPCs; the count is
    -- reported instead.
    local function localX(v) return v - ox end
    local function localY(v) return v - oy end
    local function note(x, y)
      if x < 0 or y < 0 or x >= def.width or y >= def.height then
        outside = outside + 1
      end
    end

    for i, o in ipairs(ev and ev.objectEvents or {}) do
      local x, y = localX(o.x), localY(o.z)
      note(x, y)
      -- The key into `data.sprites`, resolved THROUGH the overlay-5 table and
      -- never straight off the id -- see Gen4ObjectGfx for what that cost.
      -- `noSprite` is a reason, not a failure: a signpost or a VAR_ slot has
      -- no billboard of its own and must not read as a broken lookup.
      local spriteKey, _, noSprite = self:spriteFor(o.graphics)
      local kind, band, entry, member = Gen4ScriptBands.classify(o.script)
      -- Asked once and reused: the trainer record below needs it, and so do
      -- the two sight fields, which must be absent rather than zero on
      -- everything that is not a trainer.
      local trainerHere = Gen4ScriptBands.trainerId(o.script or -1) ~= nil
      objects[#objects + 1] = {
        index = i, localId = o.localId,
        graphicsId = o.graphics,
        sprite = spriteKey,
        spriteName = Gen4ObjectGfx.name(o.graphics),
        noSprite = noSprite,
        -- ...and, when the reason is that it is a MODEL, which one.  A
        -- member of fldeff.narc, not of the sprite archive: the two are
        -- different files and the same number means different things in
        -- each, so this is deliberately not called `member`.
        fldeffModel = self:modelFor(o.graphics),
        -- What the script id MEANS, rather than only what it is.
        scriptKind = kind,
        -- ...and, for the 417 trainers, WHICH TRAINER.  The id comes from the
        -- band the same way the cartridge derives it, and the class it lands on
        -- agrees with the art this object wears.
        trainer = (function()
          local id, side = Gen4ScriptBands.trainerId(o.script or -1)
          if not id then return nil end
          local record = self._trainers and self._trainers[id]
          return {
            id = id,
            class = record and record.class,
            className = record and record.className,
            name = record and record.name,
            partySize = record and record.partySize,
            -- Which half of a double battle this object is, from the BAND:
            -- 3000 and 5000 reach the same file and only the band tells them
            -- apart.
            battler = side,
          }
        end)(),
        -- ...and, for the 329 item balls, WHICH ITEM.
        pickup = (function()
          local visible, hidden = self:pickupTables()
          return Gen4Pickups.resolve(o.script, visible, hidden)
        end)(),
        scriptBand = band,
        berryPatch = band == 'berry_tree_interactions' and o.data[1] or nil,
        scriptEntry = (kind == "band" or kind == "map") and entry or nil,
        scriptFile = member,
        movementType = o.movementType,
        movementRangeX = o.rangeX, movementRangeY = o.rangeZ,
        trainerType = o.trainerType,
        -- HOW FAR THIS TRAINER CAN SEE -- `data[0]`, AND NOT `movementRangeX`.
        --
        -- `GetTrainerDistToPlayer` (trainer_encounter.c) reads the range as
        -- `MapObject_GetDataAt(trainerMapObj, 0)`, and `data[3]` is its own
        -- field in the ObjectEvent record (map_header_data.h) sitting BEFORE
        -- `movementRangeX`/`movementRangeZ`.  The two are easy to conflate --
        -- both are "a range on an object event" -- and conflating them answers
        -- zero, because a trainer stands still and its movement range IS zero.
        --
        -- MEASURED over the cartridge's 417 trainer objects: 390 carry a range
        -- of 1 to 6 (68/129/101/62/21/9) and 27 carry zero, which is the
        -- cartridge's own way of saying "walk up and talk to me" -- the gym
        -- trainers and the like.  `movementRangeX` is zero for every one of the
        -- 417, so reading that field instead would have meant exactly what
        -- reading nothing meant: not one trainer in Sinnoh ever notices anybody.
        --
        -- Emitted only for a trainer.  `data` is generic object storage and
        -- means something else on the other 3,138 objects, so giving them all a
        -- `sightRange` would be three thousand bogus numbers for the sake of a
        -- uniform record.  `OverworldController.checkTrainerSight` tests
        -- `sightRange ~= nil` and treats zero as a real setting, which is why
        -- the zero-range 27 must still be written rather than left out.
        sightRange = trainerHere and (o.data and o.data[1] or 0) or nil,
        -- ...AND WHICH WAYS IT LOOKS, collapsed here the way the cartridge
        -- collapses it.
        --
        -- `GetTrainerType` rewrites FACE_SIDES(4), FACE_COUNTERCLOCKWISE(5),
        -- FACE_CLOCKWISE(6), SPIN_COUNTERCLOCKWISE(7) and SPIN_CLOCKWISE(8) to
        -- NORMAL(1) before asking about distance, so all five look ONE way --
        -- along their own facing -- despite their numbers being larger than
        -- VIEW_ALL_DIRECTIONS(2), which looks four.  NONE(0) and UNK_003(3)
        -- match neither branch and return DISTANCE_INVALID: they never spot.
        --
        -- So the raw number is not orderable and Emerald's `type >= 2 means
        -- every way` rule is wrong on this cartridge for 21 of the 417 objects.
        -- Stated as a count of directions instead, decided once, here, beside
        -- the pret reference: 0 never spots, 1 looks along its facing, 4 looks
        -- all round.  The cartridge's own distribution is 1 x385, 2 x11, 4 x13,
        -- 5 x3, 6 x2, 7 x3 -- so 11 objects in Sinnoh look every way and 21 are
        -- the turners and spinners Emerald's rule would have given all four to.
        -- Simulated over the ROM: 417 trainers get both fields, no non-trainer
        -- gets either, 406 answer sightWays 1 and 11 answer 4, and 390 end up
        -- able to spot the player at a mean range of 2.48 tiles.
        sightWays = trainerHere and (function()
          local ty = tonumber(o.trainerType) or 0
          if ty == 2 then return 4 end
          if ty == 1 or (ty >= 4 and ty <= 8) then return 1 end
          return 0
        end)() or nil,
        flag = o.hiddenFlag,
        -- THE FLAG THAT HIDES THIS OBJECT, under the name the rest of the
        -- engine already looks for.
        --
        -- `sub_020620C4` (map_object.c) spawns an object event when
        -- `ObjectEvent_HasNoScript(e) || FieldSystem_CheckFlag(e->hiddenFlag)
        -- == FALSE` -- so an object WITH a script is absent exactly while its
        -- flag is set, and an object WITHOUT one (script 0xFFFF) ignores the
        -- field entirely.  1,566 of the cartridge's 3,555 object events carry
        -- such a flag and the port read none of them, so nobody a script
        -- dismissed ever stayed dismissed.
        --
        -- Written as `eventFlag` because that is the field
        -- `OverworldController.objectVisible` already consults, with the same
        -- "flag set means hidden" polarity Gen 2 has -- no new branch in the
        -- visibility code, and one spelling of the flag name shared with
        -- `setflag`/`checkflag`.
        eventFlag = (o.script ~= 0xFFFF and (o.hiddenFlag or 0) ~= 0)
                    and Gen4ScriptVM.flagName(o.hiddenFlag) or nil,
        script = o.script,
        direction = o.direction,
        x = x, y = y,
        elevation = o.y,
      }
      counts.objects = counts.objects + 1
    end

    for i, w in ipairs(ev and ev.warpEvents or {}) do
      local x, y = localX(w.x), localY(w.z)
      note(x, y)
      -- The destination is a HEADER id; the engine keys maps by their internal
      -- name, so it is resolved here rather than left for every consumer to
      -- resolve differently.
      --
      -- !! AND SIX OF THEM ARE NOT DANGLING, THEY ARE THE LIFTS. This used to
      -- read "six warps in the cartridge go nowhere" and leave their destMap
      -- nil. 4095 paired with anchor 256 is 0xfff/0x100 -- the cartridge's
      -- DYNAMIC destination, resolved from the special location when the door
      -- is taken (field_control.c 1011). Marked with a sentinel map id the way
      -- Gen 3's MAP_G127_N127 is, so `Warp.resolve` has something to dispatch
      -- on rather than a hole. BOTH halves are required: either number alone
      -- would be a guess, and together they are exactly what pret asserts.
      local destination = names and names[w.destination]
      local dynamic = w.destination == Gen4Events.NO_DESTINATION
                      and w.anchor == Gen4Events.DYNAMIC_ANCHOR
      if dynamic then
        destination = Gen4Elevators.DYNAMIC_MAP
        dynamicWarps = dynamicWarps + 1
      elseif not destination and w.destination ~= Gen4Events.NO_DESTINATION then
        dangling = dangling + 1
      end
      warps[#warps + 1] = {
        index = i, x = x, y = y,
        destMap = destination,
        destHeader = w.destination,
        -- ONE-BASED, because `Warp.lua` indexes `destDef.warps[destWarp]` and
        -- that is a Lua array.  The cartridge's anchor is zero-based and this
        -- wrote it through raw, so EVERY warp in Sinnoh came out one door
        -- early: the log reads `map: T01 at (20,11)` into Twinleaf's third
        -- house and `map: T01 at (20,21)` on the way back, which is the
        -- SECOND house's door.  Gen 3 adds the one and says why at
        -- `RomExtractorGen3.lua:11652`; Gen 2 clamps at one.  This was the
        -- only extractor of the three that did neither.
        destWarp = (w.anchor or 0) + 1,
      }
      counts.warps = counts.warps + 1
    end

    for i, b in ipairs(ev and ev.bgEvents or {}) do
      local x, y = localX(b.x), localY(b.z)
      note(x, y)
      local kind, band, entry, file = Gen4ScriptBands.classify(b.script)
      local visible, hidden = self:pickupTables()
      signs[#signs + 1] = {
        index = i, x = x, y = y,
        script = b.script, kind = b.kind,
        facing = b.playerFacing, elevation = b.y,
        scriptKind = kind, scriptBand = band,
        scriptEntry = (kind == "band" or kind == "map") and entry or nil,
        scriptFile = file,
        -- 262 of these are a hidden item, and `range` is how close you have to
        -- stand for the Itemfinder to sing.
        pickup = Gen4Pickups.resolve(b.script, visible, hidden),
      }
      counts.signs = counts.signs + 1
    end

    for i, c in ipairs(ev and ev.coordEvents or {}) do
      local x, y = localX(c.x), localY(c.z)
      note(x, y)
      coords[#coords + 1] = {
        index = i, x = x, y = y,
        width = c.width, height = c.length,
        script = c.script, value = c.value, var = c.variable,
        elevation = c.y,
      }
      counts.coordEvents = counts.coordEvents + 1
    end

    def.objects = objects
    def.warps = warps
    def.signs = signs
    def.coordEvents = coords
  end

  self:write("maps", defs)
  self.regionReport = {
    objects = counts.objects, warps = counts.warps,
    signs = counts.signs, coordEvents = counts.coordEvents,
    outside = outside, dangling = dangling, dynamicWarps = dynamicWarps,
  }
  return defs
end

function RomExtractorGen4:extractEvents()
  self:beginStage("events")
  local out = Gen4Events.all(assert(self:archive("events")))
  self:write("gen4_events", out)
  return out
end

-- The script pool, FLAT and labelled "M<member>/S<offset>" -- the same shape
-- Gen 2 and Gen 3 use, because Gen4ScriptVM.compile resolves a branch by
-- looking its label up in one table and a nested pool would make every branch
-- carry its member separately.  The label spelling comes from
-- Gen4ScriptVM.label so the extractor and the VM cannot drift apart.
--
-- Lowering happens at LOAD time in Gen4ScriptVM, not here, so that a lowering
-- fix does not require re-importing the cartridge.
function RomExtractorGen4:extractScripts()
  self:beginStage("scripts")
  local arc = assert(self:archive("scripts"))
  local scripts, entries = {}, {}
  -- The instruction's own width, asked for rather than written down: the
  -- movement list is at `(the byte after the instruction) + offset`, so a
  -- change to the opcode table must not be able to silently move it.
  local moveOp
  for op, entry in pairs(Gen4ScriptOps.COMMANDS) do
    if entry[1] == "applymovement" then moveOp = op end
  end
  local moveSize = moveOp and Gen4ScriptOps.size(moveOp)
  local movesRead, movesRefused = 0, 0
  for m = 0, arc.count - 1 do
    local bytes = arc:get(m)
    if bytes and #bytes >= 6 then
      -- Follow jumps as well as entry points: a block reached only by a
      -- `goto` is still a block the runner will need.
      local ordered = Gen4Script.entries(bytes)
      local queue, seen = {}, {}
      for _, at in ipairs(ordered) do
        if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
      end
      local i = 1
      while i <= #queue do
        local at = queue[i]; i = i + 1
        local instructions, stopped = Gen4Script.decode(bytes, at)
        scripts[Gen4ScriptVM.label(m, at)] =
          { instructions = instructions, stopped = stopped }
        for _, ins in ipairs(instructions) do
          local t = ins.target
          if t and t >= 1 and t <= #bytes and not seen[t] then
            seen[t] = true; queue[#queue + 1] = t
          end
          -- ...AND THE MOVEMENT LIST AN `applymovement` POINTS AT, which is in
          -- this same member a few bytes further down -- see Gen4Movement for
          -- why there is no archive to look in.  Decoded here rather than at
          -- load time because the bytes are only in hand during the import;
          -- the lowering sees the steps and never the offset.
          if ins.name == "applymovement" and moveSize then
            local address = Gen4Movement.addressOf(ins, moveSize)
            local steps = address and Gen4Movement.decode(bytes, address)
            if steps then
              ins.movement = steps
              movesRead = movesRead + 1
            else
              movesRefused = movesRefused + 1
            end
          end
        end
      end
      -- The ENTRY POINTS in order: a script id in an event is an index into
      -- this list, not a byte offset, so the order is the mapping.
      local list = {}
      for k, at in ipairs(ordered) do list[k] = Gen4ScriptVM.label(m, at) end
      entries[m] = list
    end
    self:tick("scripts", m + 1, arc.count)
  end
  self._scripts, self._entries = scripts, entries
  self.movementReport = { read = movesRead, refused = movesRefused }
  return scripts
end

-- ---------------------------------------------------------------------------

-- The join: which script each map's objects and signs run.
--
-- A map header names a scr_seq member (`scripts`) and an events archive
-- (`events`); an object event carries a SCRIPT ID, which indexes that
-- member's entry-point list.  Nothing else connects the two, which is why
-- this stage exists at all and why it has to run after both.
--
-- MAP IDS ARE THE CARTRIDGE'S OWN INTERNAL NAMES -- "C01", "C05GYM0113",
-- "D25R0106" -- from mapname.bin, keyed by header id.  They are unique, they
-- are stable across revisions, and they are what a log line should say.  The
-- player-facing name is a different table (message bank 433) and several maps
-- share one, so it would not do as a key.
--
-- NOT EVERY SCRIPT ID IS A SCRIPT, and getting this wrong makes a working
-- link look broken.  Counting anything that did not resolve as "missing"
-- reported 2,350 failures against 1,887 successes -- more misses than hits,
-- which should never be believed without checking what the misses are.
-- Classified instead:
--
--   0                       no script
--   1 .. 1999               an entry in THIS MAP's own script member, at
--                           index id - 1
--   >= 2000                 an entry in a SHARED script file, chosen by the
--                           highest threshold the id clears
--   65535                   the "no script" sentinel, which is not a band
--
-- The bands are in Gen4ScriptBands, taken from the cartridge's own dispatcher
-- rather than guessed, and they are no longer recorded as `special`: an id in
-- a band is an ordinary entry point in a shared file, and 1,885 of the 1,920
-- land inside the file their band names.
--
-- TWO BUGS FIXED HERE AT ONCE, and the second hid behind the first.
--
--   * `specials` was keyed by an object's localId AND by a sign's index in the
--     same table, so a sign with index 1 silently replaced the object with
--     localId 1.  228 of 2,148 entries -- better than one in ten -- were being
--     overwritten, and nothing counted them because the count was taken before
--     the write.  Objects and signs now have a table each.
--   * Nothing looked at what the ids meant, so nothing noticed that the events
--     running berry-tree scripts were being drawn as Team Galactic's Mars.
--     Classifying them is what exposed the graphics indirection in
--     Gen4ObjectGfx.
function RomExtractorGen4:linkScripts(headers, events, names)
  self:beginStage("link")
  local maps = {}
  local linked, special, none = 0, 0, 0
  -- Computed ONCE rather than per map: the init tables below resolve band ids
  -- through it and so does the pool record at the end of this function, and
  -- building the archive's name list 594 times to answer the same question is
  -- the sort of thing that turns a four-second import into a minute.
  local bands = self:scriptBands()
  local scriptsArc = self:archive("scripts")
  local initMaps, initCallbacks, initRows, initUnknown, initUnresolved = 0, 0, 0, 0, 0
  local initCoords = 0

  -- A script id from an init table, resolved to the label the VM compiles.
  -- The same dispatcher an object's script id goes through -- these ids are
  -- not a separate number space, and 182 of the 525 in this cartridge name a
  -- block in a SHARED file rather than the map's own.
  local function labelFor(list, scriptId)
    local kind, name, index = Gen4ScriptBands.classify(scriptId)
    if kind == "map" then return list and list[scriptId] end
    if kind == "band" then
      local band = bands and bands[name]
      return band and band.entries and band.entries[index + 1] or nil
    end
    return nil
  end
  for id, h in pairs(headers or {}) do
    local mapId = names and names[id]
    local ev = events and events[h.events]
    local list = self._entries and self._entries[h.scripts]
    if mapId and ev and list then
      local objects, signs = {}, {}
      -- A TABLE EACH, because a localId and a sign index are both small
      -- integers and sharing one table makes them collide.
      local shared = { objects = {}, signs = {} }
      local function place(into, sharedInto, key, scriptId)
        if not scriptId or scriptId == 0 then none = none + 1; return end
        local kind, band, entry, member = Gen4ScriptBands.classify(scriptId)
        if kind == "sentinel" then none = none + 1; return end
        if kind == "map" then
          local label = list[scriptId]
          if label then into[key] = label; linked = linked + 1; return end
        end
        sharedInto[key] = {
          id = scriptId, band = band, entry = entry, file = member,
          kind = kind,
        }
        special = special + 1
      end
      -- BY THE EVENT'S POSITION, NOT ITS localId.
      --
      -- A localId is the handle a script uses to move an object about, and
      -- the cartridge REUSES ONE inside a map: 40 objects across 28 maps
      -- share a localId with another object on the same map.  Keyed that way,
      -- the second of a pair silently took the first's entry -- Twinleaf
      -- Town's arrow signpost, which has the no-script sentinel, answered
      -- with the guitarist's dialogue.
      --
      -- The position in the event list is unique by construction, and the
      -- maps stage already writes it onto the object record as `index`, so
      -- both sides of the join name the same thing.
      for i, npc in ipairs(ev.objectEvents or {}) do
        place(objects, shared.objects, i, npc.script)
      end
      for i, sign in ipairs(ev.bgEvents or {}) do
        place(signs, shared.signs, i, sign.script)
      end
      -- ...AND THE COORDINATE TRIGGERS, which are the third thing on a map
      -- that runs a script and the third one nothing read.
      --
      -- Reported from play: *"she doesnt say anything unless i talk to her but
      -- mom is talking to me when i come down the stairs"*.  Both halves of
      -- that sentence are this table.  The player's house in Twinleaf has ONE
      -- coord event -- `(6,10), 1x1, var 0x40A4 == 1 -> script 5` -- on the
      -- very tile its exit warp is on, and the neighbour who "blocks the door"
      -- stands there because the cartridge means you to walk into her and have
      -- the scene play.  `def.coordEvents` has been written by the maps stage
      -- all along and read by nothing, so the scene never ran and pressing A on
      -- her -- her OBJECT script, a different thing entirely -- was the only
      -- way to get a word out of her.
      --
      -- 186 of them across 76 maps.  Every one is gated on a real var (all 186
      -- `variable` fields are at or above 0x4000), and 72 cover a RECTANGLE
      -- rather than one cell -- up to 8x1 and 1x6 -- which Gen 3 has no
      -- equivalent of and which the runtime side has to honour.
      --
      -- ONLY THE LABEL IS RESOLVED HERE, keyed by the event's position in the
      -- map's own list.  Where the trigger IS was localised by the maps stage
      -- and is already on `def.coordEvents`; re-deriving the map's origin in a
      -- second place is how the two halves start disagreeing.
      local coords = nil
      for i, c in ipairs(ev.coordEvents or {}) do
        local label = labelFor(list, c.script)
        if label then
          coords = coords or {}
          coords[i] = label
          initCoords = initCoords + 1
        elseif c.script and c.script ~= 0 then
          initUnresolved = initUnresolved + 1
        end
      end

      -- ...AND THE MAP'S OWN ENTRY CONDITIONS, which is the second script
      -- member the header names and the one nothing has ever read.  See
      -- Gen4InitScripts for the format and for the three reports it explains.
      local callbacks, tables = nil, nil
      local initBytes = scriptsArc and h.initScripts
        and h.initScripts < scriptsArc.count and scriptsArc:get(h.initScripts)
      local parsed, unknown = initBytes and Gen4InitScripts.parse(initBytes)
      initUnknown = initUnknown + (unknown or 0)
      if parsed then
        initMaps = initMaps + 1
        callbacks = {}
        for _, c in ipairs(parsed.callbacks) do
          local label = labelFor(list, c.script)
          if label then
            callbacks[#callbacks + 1] = { type = c.type, name = c.name, script = label }
            initCallbacks = initCallbacks + 1
          else
            initUnresolved = initUnresolved + 1
          end
        end
        tables = {}
        for _, t in ipairs(parsed.tables) do
          local rows = {}
          for _, r in ipairs(t.rows) do
            local label = labelFor(list, r.script)
            if label then
              -- `a` and `b` are kept as the cartridge wrote them, because
              -- EITHER may be a var or a literal: `FieldSystem_TryGetVar`
              -- answers the value for a var and the id itself for anything
              -- else, and deciding here which is which would throw away the
              -- only thing that says so.
              rows[#rows + 1] = { a = r.a, b = r.b, script = label }
              initRows = initRows + 1
            else
              initUnresolved = initUnresolved + 1
            end
          end
          if #rows > 0 then
            tables[#tables + 1] = { type = t.type, name = t.name, rows = rows }
          end
        end
        if #callbacks == 0 then callbacks = nil end
        if #tables == 0 then tables = nil end
      end

      if next(objects) or next(signs) or next(shared.objects) or next(shared.signs)
         or callbacks or tables or coords then
        maps[mapId] = {
          objects = objects, signs = signs, header = id,
          callbacks = callbacks, tables = tables, coords = coords,
          -- Named `shared` rather than `specials`: they are entries in shared
          -- script files, which is a fact about them rather than an admission.
          shared = (next(shared.objects) or next(shared.signs)) and shared or nil,
        }
      end
    end
  end
  self:write("map_scripts", {
    source = "RomExtractorGen4",
    scripts = self._scripts or {},
    maps = maps,
    bands = bands,
  })
  self.linkReport = {
    linked = linked, special = special, none = none, maps = 0,
    initMaps = initMaps, initCallbacks = initCallbacks, initRows = initRows,
    initUnknownTypes = initUnknown, initUnresolved = initUnresolved,
    coordEvents = initCoords,
  }
  for _ in pairs(maps) do self.linkReport.maps = self.linkReport.maps + 1 end
  return maps
end

-- THE SHARED SCRIPT FILES, ADDRESSED.
--
-- `callcommonscript` is the cartridge's subroutine call into a SHARED script
-- file -- 668 call sites in this cartridge, 652 of them into `scripts_common`
-- -- and the VM left every one of them as a `g4_common` row nobody could
-- execute, because the pool had no way to say which block a band id names.
--
-- Three things are needed and all three already exist somewhere:
--
--   * WHICH MEMBER a band's file is.  `Gen4Archives.names` carries scr_seq's
--     1,124 member names, so `scripts_common` resolves to member 211 --
--     derived rather than written down, which is what keeps it right if the
--     archive is ever re-ordered.
--   * WHICH BLOCK an id names.  `extractScripts` already walks every member
--     and records its ENTRY POINTS in order; a band id is an index into that
--     list, exactly as a map's own script id is.  Only the band members' lists
--     are written here -- thirty of the 1,124 -- so this costs nothing.
--   * WHICH TEXT BANK it reads.  `Gen4ScriptBands.TEXT_BANK`, transcribed from
--     the same dispatcher table the thresholds came from.  A common script's
--     `message 3` is entry 3 of bank 213 and has nothing to do with the town
--     the player is standing in.
function RomExtractorGen4:scriptBands()
  local names = Gen4Archives.names(PATH.scripts)
  if not names then return nil end
  local memberOf = {}
  for index, name in ipairs(names) do memberOf[name] = index - 1 end

  local out, resolved, missing = {}, 0, 0
  for _, band in ipairs(Gen4ScriptBands.BANDS) do
    local member = memberOf[band[3]]
    local entries = member and (self._entries or {})[member]
    if entries then
      out[band[2]] = {
        member = member,
        threshold = band[1],
        textBank = Gen4ScriptBands.TEXT_BANK[band[2]],
        entries = entries,
      }
      resolved = resolved + 1
    else
      missing = missing + 1
    end
  end
  self.bandReport = { resolved = resolved, missing = missing }
  return out
end

-- Every stage, in order.  Returns the list of tables written, so the caller
-- can record what a cache contains rather than assuming.
-- ---------------------------------------------------------------------------
-- Graphics
-- ---------------------------------------------------------------------------

-- Compose one picture from members of an open archive.
--
-- `job` names the three parts by member index.  A job with no tilemap is a
-- SHEET rather than a screen -- a set of pieces the game arranges through OAM
-- -- and is laid out at `tilesWide` so it can at least be looked at.  That
-- layout is provisional and is recorded as such in the index; the pixels are
-- right, the arrangement is a placeholder until the NCER cell banks are read.
function RomExtractorGen4:composeJob(arc, job)
  local function member(i)
    if i == nil then return nil end
    local bytes = arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end

  local sheet = Gen4Graphics.tiles(member(job.tiles))
  local palette = Gen4Graphics.palette(member(job.palette))
  -- A JOB MAY SAY WHICH SUB-PALETTE ITS COLOURS GO IN. Almost nothing needs to:
  -- a 256-colour sheet has one palette and a 16-colour one usually ships all
  -- sixteen sub-palettes together. The move-animation effect backgrounds are the
  -- exception -- one sixteen-colour palette that the game loads into slot 9, with
  -- tilemap cells that name slot 9 -- and composing those at slot 0 produces a
  -- blank picture rather than a wrong one.
  if palette and job.paletteSlot and job.paletteSlot ~= 0 then
    palette = Gen4Graphics.paletteAtSlot(palette, job.paletteSlot)
  end
  -- ...AND A JOB MAY ASK FOR THE GREY VERSION OF ITS COLOURS. `SetBgGrayscale`
  -- rewrites the background's palette entries outright, so for an indexed picture
  -- greying the palette and greying the pixels are the same operation -- done here,
  -- once per import, rather than sixty times a second at draw time.
  if palette and job.grayscale then
    palette = Gen4Graphics.grayscalePalette(palette)
  end
  if not (sheet and palette) then return nil end

  local map
  local layout = "tilemap"
  if job.tilemap then map = Gen4Graphics.tilemap(member(job.tilemap)) end
  if not map then
    -- WHERE THE WIDTH COMES FROM, in order, and the order is the point.
    --
    -- A width written down for this group beats everything: it was measured for
    -- the cases where nothing else is right. Then the sheet's OWN header, if the
    -- archive invited it -- `Gen4Graphics.tiles` reports tilesX/tilesY as nil for
    -- the 0xFFFF sprite sheets, so a number here is the cartridge stating a size
    -- rather than a decoder's guess. Only then the archive default or the bare 8.
    --
    -- MEASURED, because this changes which sheets may call themselves final: of
    -- the 258 sheets in this table laid out by a chosen width, 65 declare their
    -- own tilesX/tilesY and 193 say 0xFFFF and genuinely need a bank or a stated
    -- width. Of those 65, twenty-six are currently drawn at a width the file
    -- contradicts -- pl_winframe's message boxes among them, declared 6x3 and laid
    -- out at 8. `preferDeclaredSize` is OPT-IN per archive rather than the new
    -- default for exactly that reason: turning it on everywhere redraws twenty-six
    -- existing pictures, several of them visible UI, and that wants its own pass
    -- and its own play-test instead of riding along with the Underground.
    local wide
    if job.tilesWideStated then
      wide, layout = job.tilesWide, "stated"
    elseif job.preferDeclaredSize and sheet.tilesX and sheet.tilesX > 0 then
      wide, layout = sheet.tilesX, "declared"
    else
      wide, layout = job.tilesWide or 8, "fallback"
    end
    local cells = {}
    for i = 0, sheet.count - 1 do
      cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = 0 }
    end
    map = {
      width = wide * 8,
      height = math.ceil(sheet.count / wide) * 8,
      cells = cells,
    }
  end

  -- The layout's provenance rides back with the picture, so the caller does not
  -- have to re-derive it from the job and get a different answer.
  return Gen4Graphics.compose(map, sheet, palette, job.firstTile), layout
end

-- Assemble a sheet through its cell bank, returning one image per cell.
--
-- This is what a cell bank is FOR.  A sprite sheet records no width -- its
-- NCGR says 0xFFFF x 0xFFFF -- because the shape lives in the bank: a list of
-- rectangles at signed offsets from the sprite's centre.  Laying the sheet out
-- at a guessed width produces the right pixels in the wrong order, which looks
-- like a decode bug and is not one.
--
-- Returns nil when there is no bank, so the caller can fall back to the width
-- guess and mark the result provisional.
function RomExtractorGen4:assembleCells(arc, job, sheet, palette)
  if not (job.cell and sheet and palette) then return nil end
  local raw = arc:get(job.cell)
  if not raw then return nil end
  if Gen4Graphics.isCompressed(raw) then raw = Gen4Graphics.decompress(raw) end

  local bank = Gen4Cells.parse(raw, Gen4Graphics)
  if not bank or bank.count == 0 then return nil end

  local out = {}
  for i, cell in ipairs(bank.cells) do
    local image = Gen4Cells.assemble(cell, sheet, palette, bank, Gen4Graphics)
    if image then
      -- A one-cell bank is the sprite itself and keeps the plain name; a bank
      -- with several is a set of frames and each one is numbered.
      out[#out + 1] = {
        suffix = (bank.count > 1) and ("_%02d"):format(i - 1) or "",
        image = image,
        cellIndex = i - 1,
      }
    end
  end
  if #out == 0 then return nil end
  return out, bank
end

-- Decode a job's sheet and palette once, for the callers that need them before
-- deciding between cell assembly and a flat layout.
function RomExtractorGen4:partsFor(arc, job)
  local function member(i)
    if i == nil then return nil end
    local bytes = arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end
  return Gen4Graphics.tiles(member(job.tiles)),
         Gen4Graphics.palette(member(job.palette))
end

-- One pixel of a composed picture, as the 0-1 triple LOVE draws with.  A
-- composed image is RGBA8 in row order, so this is arithmetic rather than a
-- decode.
local function pixelAt(image, x, y)
  if not image or x < 0 or y < 0 or x >= image.width or y >= image.height then
    return nil
  end
  local at = (y * image.width + x) * 4
  local r, g, b = image.rgba:byte(at + 1, at + 3)
  if not b then return nil end
  return { r / 255, g / 255, b / 255 }
end

-- WHERE THE ARTWORK IS INSIDE A PICTURE: the tightest box that holds every
-- pixel which is neither transparent nor the sheet's own background.
--
-- Both cases occur in the title archive and only one of them is transparency.
-- The logo is on a transparent sheet, so alpha finds it; the copyright lines
-- are white on an OPAQUE BLACK 256x256 sheet, where alpha finds the whole
-- sheet and says nothing.  Treating "fully transparent OR exactly the
-- top-left pixel's colour" as background covers both without needing to know
-- which kind a given sheet is.
local function contentBox(image)
  if not image or image.width == 0 or image.height == 0 then return nil end
  local rgba = image.rgba
  local br, bg, bb, ba = rgba:byte(1, 4)
  local minX, minY, maxX, maxY = image.width, image.height, -1, -1
  for y = 0, image.height - 1 do
    local row = y * image.width * 4
    for x = 0, image.width - 1 do
      local at = row + x * 4
      local r, g, b, a = rgba:byte(at + 1, at + 4)
      local background = (a == 0) or (a == ba and r == br and g == bg and b == bb)
      if not background then
        if x < minX then minX = x end
        if y < minY then minY = y end
        if x > maxX then maxX = x end
        if y > maxY then maxY = y end
      end
    end
  end
  if maxX < 0 then return nil end
  return { x = minX, y = minY, w = maxX - minX + 1, h = maxY - minY + 1 }
end

-- Stack same-sized pictures into one column, which is the shape both frame
-- records want: a fixed cell height, one frame per cell, in order.
--
-- Every row is asserted to be the stated size rather than padded to it.  A
-- frame that came out the wrong shape would otherwise be stacked anyway and
-- read back at the wrong offset, which draws SOMETHING for every frame and the
-- right thing for none.
local function stackImages(cells, width, height)
  if #cells == 0 then return nil end
  local rows = {}
  for _, cell in ipairs(cells) do
    local image = cell.image
    if image.width ~= width or image.height ~= height then return nil end
    rows[#rows + 1] = image.rgba
  end
  return {
    width = width, height = height * #cells,
    rgba = table.concat(rows),
  }
end

-- One archive member decoded as a palette, decompressed if it needs to be.
function RomExtractorGen4:paletteMember(arc, index)
  local bytes = arc and index and arc:get(index)
  if not bytes then return nil end
  if Gen4Graphics.isCompressed(bytes) then
    bytes = Gen4Graphics.decompress(bytes)
  end
  return Gen4Graphics.palette(bytes)
end

-- Compose tiles + tilemap against a palette this caller built itself.
--
-- Separate from composeJob because these archives carry no name table and so
-- no job: the indices come from the cartridge's own loader, and the palette is
-- often not one member but two loads merged, or one row replicated.  Handing
-- composeJob a member index for the palette could not express either.
-- `firstTile`, when the sheet is loaded somewhere other than tile 0.  See
-- Gen4Graphics.compose: a tilemap indexes VRAM rather than the member it
-- shipped beside, and the intro's Poke Ball is the one place in this cartridge
-- where the two differ.
function RomExtractorGen4:composeWith(arc, tilesIndex, tilemapIndex, palette,
                                      firstTile)
  local function member(i)
    if i == nil then return nil end
    local bytes = arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end
  local sheet = Gen4Graphics.tiles(member(tilesIndex))
  local map = Gen4Graphics.tilemap(member(tilemapIndex))
  if not (sheet and map and palette) then return nil end
  return Gen4Graphics.compose(map, sheet, palette, firstTile)
end

-- Save a composed picture, and return what the index should record about it.
function RomExtractorGen4:saveImage(relative, image, extra)
  if not image then return nil end
  local data = ImageWriter.fromRGBA8(image.width, image.height, image.rgba)
  if not data then return nil end
  local path = "assets/generated/gen4/" .. relative .. ".png"
  ImageWriter.save(data, path)
  local entry = { path = path, width = image.width, height = image.height }
  if extra then
    for k, v in pairs(extra) do entry[k] = v end
  end
  return entry
end

-- ...and the same, for bytes that are not a picture.
--
-- `ImageWriter.save` encodes a PNG and hands the string to `CacheFs.write`,
-- which is what routes a cache file to the save directory on a normal build
-- and into the game folder on a portable one.  A side-car binary wants the
-- second half of that and none of the first: the terrain's packed geometry is
-- 17.7 MB, which is a fifty-megabyte Lua table if it goes through `write`.
function RomExtractorGen4:saveBinary(relative, bytes)
  if type(bytes) ~= "string" then return nil end
  local path = "assets/generated/gen4/" .. relative
  local CacheFs = require("src.import.CacheFs")
  local written, why = CacheFs.write(path, bytes)
  if not written then
    error("could not write " .. path .. ": " .. tostring(why))
  end
  return path
end

-- Battles, menus, the summary pages and the title sequence.
--
-- This stage exists because none of the above could previously be SEEN.  The
-- decoders were correct and the archives were readable, but a Gen 4 screen is
-- never one member: it is a tile sheet, a palette and a tilemap that sit at
-- unrelated indices, and until they are paired correctly there is no picture,
-- only three files.
--
-- WHAT PAIRS THEM IS THE NAME, which is why Gen4Archives comes first.  Where
-- the index is arithmetic instead of a name -- the battle backgrounds, whose
-- archive has no name table at all -- Gen4Battle carries the arithmetic and it
-- is checked against the cartridge before it is used: every member this stage
-- reaches for is confirmed to be the kind of file it is supposed to be, and a
-- background whose parts are not all present is skipped and counted rather
-- than composed from whatever happened to be at that index.
function RomExtractorGen4:extractGraphics()
  self:beginStage("graphics")

  local index = {
    backgrounds = {}, terrain = {}, battleObjects = {}, screens = {},
    palettes = {}, skipped = {},
  }

  -- Battle backgrounds: 23 backgrounds x 3 times of day over one shared
  -- tilemap.  The tilemap is 512 x 256 because the background scrolls; the
  -- visible screen is the left 256 x 192 of it.
  local bgArc = self:archive("battleBg")
  if bgArc then
    local total = Gen4Battle.BACKGROUND_COUNT * #Gen4Battle.TIMES
    local done = 0
    for i = 0, Gen4Battle.BACKGROUND_COUNT - 1 do
      for t = 0, #Gen4Battle.TIMES - 1 do
        local spec = Gen4Battle.background(i, t)
        local image = spec and self:composeJob(bgArc, {
          tiles = spec.tiles, palette = spec.palette, tilemap = spec.tilemap,
        })
        local name = ("%s_%s"):format(spec.name, spec.time)
        local entry = self:saveImage("battle/background/" .. name, image, {
          background = i, time = spec.time, fadeTo = spec.fadeTo,
        })
        if entry then
          index.backgrounds[name] = entry
        else
          index.skipped[#index.skipped + 1] = "battle/background/" .. name
        end
        -- ...and the grey one, for `SetBgGrayscale` (18 calls over 5 programs, nine
        -- on and nine off). A second picture rather than a draw-time filter,
        -- because the cartridge's operation is on the PALETTE and this is the same
        -- operation performed once: see Gen4Graphics.grayscalePalette for the
        -- five-bit arithmetic and why it is not done on the expanded channels.
        local gray = spec and self:composeJob(bgArc, {
          tiles = spec.tiles, palette = spec.palette, tilemap = spec.tilemap,
          grayscale = true,
        })
        local grayEntry = self:saveImage("battle/background/" .. name .. "_gray",
                                         gray, {
          background = i, time = spec.time, fadeTo = spec.fadeTo, grayscale = true,
        })
        if grayEntry then
          index.backgrounds[name .. "_gray"] = grayEntry
        else
          index.skipped[#index.skipped + 1] =
            "battle/background/" .. name .. "_gray"
        end
        done = done + 1
        self:tick("graphics", done, total + 200)
      end
    end

    -- ...and the MOVE ANIMATION backgrounds out of the same archive: 58 of them,
    -- each with a normal, a mirrored and a contest arrangement over one tile
    -- sheet and one sixteen-colour palette. See Gen4Battle.EFFECT_BG_MEMBERS for
    -- where the table comes from and why it cannot be computed.
    --
    -- DEDUPED BY THE THREE MEMBERS. 174 combinations resolve to 81 distinct
    -- pictures -- most backgrounds use the same tilemap for two or three of the
    -- arrangements -- so the image is written once under a name built from the
    -- members and every key that resolves to it points at that file.
    index.effects = {}
    local byArt, effectsWritten = {}, 0
    for bg = 0, Gen4Battle.EFFECT_BG_COUNT - 1 do
      for _, variant in ipairs(Gen4Battle.EFFECT_VARIANTS) do
        local spec = Gen4Battle.effectBackground(bg, variant)
        local key = spec and Gen4Battle.effectKey(bg, variant)
        if spec and key then
          local entry = byArt[spec.art]
          if entry == nil then
            local image = self:composeJob(bgArc, {
              tiles = spec.tiles, palette = spec.palette,
              tilemap = spec.tilemap, paletteSlot = spec.slot,
            })
            -- WHETHER THE PICTURE COVERS THE SCREEN, measured rather than assumed.
            -- The layer is 4bpp and its holes show whatever is underneath, so a
            -- whole-screen operation on it -- the `fadebg` type 2 blend, which
            -- tints this layer's sixteen colours and nothing else -- is only
            -- reproducible as a whole-screen quad where there ARE no holes.
            -- Measured over all 81: 35 cover the visible 256x192 completely and
            -- the thinnest covers 72.7% of it.
            local opaque = image and Gen4Graphics.coversScreen(image) or nil
            entry = self:saveImage("battle/effect/" .. spec.art, image, {
              tiles = spec.tiles, palette = spec.palette,
              tilemap = spec.tilemap, paletteSlot = spec.slot,
              opaque = opaque,
            }) or false
            byArt[spec.art] = entry
            if entry then effectsWritten = effectsWritten + 1 end
          end
          if entry then
            index.effects[key] = entry
          else
            index.skipped[#index.skipped + 1] = "battle/effect/" .. spec.art
          end
        end
      end
    end
    index.effectsWritten = effectsWritten
  end

  -- Terrain platforms: the ground each side stands on, chosen from the tile
  -- the player was walking on rather than from the map.  Two sides per
  -- terrain, and three palettes per terrain outdoors -- indoor and special
  -- terrains list one palette three times, so those are written once.
  local objArc = self:archive("battleObj")
  if objArc then
    for i = 0, Gen4Battle.TERRAIN_COUNT - 1 do
      for _, side in ipairs({ "player", "enemy" }) do
        local times = Gen4Battle.terrain(i, side, 0).timeless
          and { 0 } or { 0, 1, 2 }
        for _, t in ipairs(times) do
          local spec = Gen4Battle.terrain(i, side, t)
          local tiles = Gen4Archives.find(PATH.battleObj, spec.tiles)
          local palette = Gen4Archives.find(PATH.battleObj, spec.palette)
          local name = spec.timeless
            and ("%s_%s"):format(spec.name, side)
            or ("%s_%s_%s"):format(spec.name, side, Gen4Battle.TIMES[t + 1])

          -- Every terrain shares one bank per side -- terrain/player_cell and
          -- terrain/enemy_cell -- which is exactly why all 24 platform sheets
          -- are the same 128 tiles.  The bank turns those 128 tiles into the
          -- 256x32 player platform and the 128x64 enemy one.
          local job = {
            tiles = tiles, palette = palette,
            cell = Gen4Archives.find(PATH.battleObj, "terrain/" .. side .. "_cell"),
            tilesWide = Gen4Battle.PLATFORM_TILES_WIDE,
          }
          local sheet, pal = self:partsFor(objArc, job)
          local frames = self:assembleCells(objArc, job, sheet, pal)
          local image = frames and frames[1] and frames[1].image
            or (tiles and palette and self:composeJob(objArc, job))

          local entry = self:saveImage("battle/terrain/" .. name, image, {
            terrain = i, side = side, art = spec.art,
            provisionalLayout = (frames == nil) or nil,
          })
          if entry then
            index.terrain[name] = entry
          else
            index.skipped[#index.skipped + 1] = "battle/terrain/" .. name
          end
        end
      end
    end

    -- Healthboxes, type icons, the interface pieces and the trainer backs.
    -- These are all OAM sheets, so the same caveat applies to their layout.
    local names = Gen4Archives.names(PATH.battleObj)
    local groups = Gen4Archives.groups(PATH.battleObj)
    if names and groups then
      -- One palette per family, taken from the family's own `shared` member
      -- where it has one.
      local familyPalette = {}
      for _, group in ipairs(groups) do
        local family = Gen4Battle.familyFor(group.base)
        if family and group.NCLR and not familyPalette[family.prefix] then
          familyPalette[family.prefix] = group.NCLR
        end
      end
      for _, group in ipairs(groups) do
        local family = Gen4Battle.familyFor(group.base)
        if family and family.prefix ~= "terrain/" and group.NCGR then
          local palette = group.NCLR or familyPalette[family.prefix]
          -- `group.NCGR` -- the sheet's own member -- is passed so the
          -- ADJACENT rule can apply. It is the last thing cellBank tries and
          -- the only one that needs to know WHICH member the sheet is, because
          -- a base name is not unique in this archive (`healthbox/enemy` is
          -- members 188, 194 and 197). Measured over every NCGR here: 118
          -- unchanged, 6 NEWLY RESOLVED, 0 changed -- and the six are the three
          -- healthboxes, which were the only sheets in the archive with no bank
          -- at all and are exactly the ones the battle screen needs.
          local bankAt, bankName, bankHow =
            Gen4Archives.cellBank(PATH.battleObj, group.base, group.NCGR)
          local job = {
            tiles = group.NCGR, palette = palette,
            cell = bankAt, tilesWide = family.tilesWide,
          }
          local name = group.base:gsub("/", "_")
          -- `local a, b = x and f()` keeps only f()'s FIRST return value, so
          -- this cannot be folded into the guard -- the palette would always
          -- arrive nil and every sheet would silently take the fallback path.
          local sheet, pal
          if palette then sheet, pal = self:partsFor(objArc, job) end
          local frames = sheet and pal and self:assembleCells(objArc, job, sheet, pal)
          if frames then
            for _, frame in ipairs(frames) do
              local entry = self:saveImage(
                "battle/" .. name .. frame.suffix, frame.image, {
                  family = family.label, cellBank = bankName,
                  cellMatch = bankHow, cell = frame.cellIndex,
                })
              if entry then index.battleObjects[name .. frame.suffix] = entry end
            end
          else
            local image = palette and self:composeJob(objArc, job)
            local entry = self:saveImage("battle/" .. name, image, {
              family = family.label, provisionalLayout = true,
            })
            if entry then index.battleObjects[name] = entry end
          end
        end
      end

      -- THE PIECES THAT FINISH A HEALTHBOX ARE NOT IN THIS ARCHIVE.
      --
      -- The frame above is an NCGR and a cell bank; the two GAUGES are neither.
      -- healthbox.c reaches them through GetHealthBoxPartsTile ->
      -- sHealthBoxPartsBitmap, which is
      -- `#include "res/graphics/battle/healthbox/healthbox_parts.4bpp.h"` --
      -- an array compiled into the battle overlay. A stage that walks archives
      -- was never going to find it, which is why the healthboxes came out with
      -- no bars and the gauges sat undrawn.
      --
      -- It is composed with the HEALTHBOX FAMILY'S OWN PALETTE, which is the
      -- whole point of doing it here rather than in a stage of its own: the
      -- gauge tiles are 4bpp indices into the same sixteen colours the box is
      -- drawn from, so the greens, yellows and reds come out of the cartridge
      -- instead of being chosen to look close.
      index.healthboxParts =
        self:extractHealthboxParts(objArc, familyPalette["healthbox/"])

      -- ...AND NEITHER ARE THE NUMBERS ON IT.  The level, the current HP and
      -- the max HP are not text and are not parts either: all three go through
      -- FontSpecialChars_DrawBattleScreenText, off a 23-tile glyph strip in
      -- pl_font.narc.  It is composed HERE, beside the parts, for the same
      -- reason -- the strip carries no colours of its own and the battle asks
      -- for three indices into THIS palette.  See Gen4SpecialChars, including
      -- for what this port previously said about those numbers and why that
      -- was wrong.
      index.healthboxDigits =
        self:extractBattleDigits(objArc, familyPalette["healthbox/"])
    end
  end

  -- PLATINUM'S BATTLE BOTTOM SCREEN, which is where the FIGHT, BAG, POKeMON
  -- and RUN buttons actually live. See Gen4Subscreen for what each of the
  -- seven tilemaps is and why the per-background palette replaces sub-palette
  -- ZERO.
  index.subscreen = self:extractBattleSubscreen()

  -- Everything the player looks at outside a battle: the title sequence, the
  -- start menu's icons and window frames, the summary pages, the party
  -- screen, the bag, the trainer card, the Poketch, the town map, the
  -- Pokedex, mail and the fonts.
  local plans = Gen4Screens.planAll()
  local totalJobs = 0
  for _, plan in ipairs(plans) do totalJobs = totalJobs + #plan.jobs end
  local done = 0
  for _, plan in ipairs(plans) do
    local arc = self:archiveAt(plan.archive.path)
    if arc then
      for _, job in ipairs(plan.jobs) do
        local relative = plan.archive.out .. "/" .. job.name:gsub("/", "_")
        local sheet, palette = self:partsFor(arc, job)
        local frames = self:assembleCells(arc, job, sheet, palette)
        local wrote = false

        -- THE SCREEN'S COLOURS, published beside its picture.
        --
        -- A composed picture cannot hold a colour that appears only in TEXT,
        -- and Platinum draws text at runtime out of a sub-palette its own C
        -- code names -- TEXT_COLOR(1, 2, 0) on BG palette 3 for the bag, on
        -- BG palette 15 for the trainer card.  Without this, every screen
        -- that prints anything has its ink WRITTEN DOWN by hand, and a hand
        -- written colour can be wrong with nothing to catch it.  It was:
        -- five of the six colours in `Gen4BagMenu` and one of the two in
        -- `Gen4TrainerCard` were a unit low in at least one channel, because
        -- they were read off a decoder that floored where `Gen4Graphics`
        -- rounds.  Invisible on screen and wrong all the same.
        --
        -- ONE ENTRY PER PALETTE FILE, not per screen: 394 jobs across the
        -- fifteen UI archives share 146 palettes, and the trainer card alone
        -- points five screens at `trainer_card_normal`.  `paletteName` comes
        -- from the planner, which is the only place the four resolution rules
        -- live; recomputing it here would be those rules written twice.
        local paletteKey
        if palette and job.paletteName then
          paletteKey = plan.archive.out .. "/" .. job.paletteName
          if not index.palettes[paletteKey] then
            index.palettes[paletteKey] = Gen4Graphics.paletteHex(palette)
          end
        end

        if frames then
          -- Assembled from a cell bank: a real sprite, at its real size.
          for _, frame in ipairs(frames) do
            local entry = self:saveImage(relative .. frame.suffix, frame.image, {
              kind = job.kind,
              cellBank = job.cellFrom,
              cellMatch = job.cellMatch,
              cell = frame.cellIndex,
              borrowedPalette = job.borrowedPalette or nil,
              paletteKey = paletteKey,
            })
            if entry then
              index.screens[relative .. frame.suffix] = entry
              wrote = true
            end
          end
        else
          local composed, layout = self:composeJob(arc, job)
          local entry = self:saveImage(relative, composed, {
            kind = job.kind,
            -- A screen has a tilemap and is final.  A sheet laid out at a width
            -- NOTHING states is provisional and says so.
            --
            -- It used to be every sheet, on the reasoning that a sheet records no
            -- width. Most do not -- 193 of 258 -- but 65 state one outright, and
            -- calling those provisional is the flag lying in the safe direction,
            -- which is still lying: the whole point of the flag is that somebody
            -- can trust its absence. So it now follows where the width actually
            -- came from, and a sheet laid out at its own declared size is final.
            provisionalLayout = (layout == "fallback") or nil,
            layoutFrom = (job.tilemap == nil) and layout or nil,
            borrowedTiles = job.borrowedTiles or nil,
            borrowedPalette = job.borrowedPalette or nil,
            paletteKey = paletteKey,
          })
          if entry then
            index.screens[relative] = entry
            wrote = true
          end
        end

        if not wrote then index.skipped[#index.skipped + 1] = relative end
        done = done + 1
        self:tick("graphics", done, totalJobs)
      end
    end
  end

  -- THE ITEM ICONS GO IN THE SAME INDEX as every other picture, under
  -- `items/icon_nnn`, so the bag reaches them through the `img` it already
  -- has rather than through a record of their own.
  self:extractItemIcons(index)

  index.frames = self:extractWindowFrames()

  -- Kept for the menus stage, which names the title art by role and would
  -- otherwise have to re-derive the archive member spellings.
  for name, image in pairs(require("src.import.Gen4UIResources").images(self.rom)) do
    if image then index.screens[name] = self:saveImage(name, image, {originX=image.originX,originY=image.originY,sequences=image.sequences}) end
  end
  self._graphicsIndex = index

  self:write("gen4_graphics", index)
  return index
end

-- ---------------------------------------------------------------------------
-- The item icons
-- ---------------------------------------------------------------------------

-- One 32x32 picture per ITEM, not per sprite, because a third of the items
-- borrow another item's shape and recolour it -- see `Gen4ItemIcons`. Writing
-- one file per sprite and pairing later would put every flute in the same
-- colour, which is the failure that looks like a palette bug.
--
-- HOW MANY ROWS THE TABLE HAS is not a new constant: it is the data archive's
-- count plus the gap `Gen4Items` already measured. 446 records and a 22-row
-- hole from id 113 is 468 ids, and 468 is exactly the length of the array the
-- scan finds. Two stages that were written months apart agreeing on the same
-- two numbers is the reason neither of them is guessed here.
function RomExtractorGen4:extractItemIcons(index)
  local arc = self:archiveAt(Gen4ItemIcons.PATH)
  if not (arc and index) then return nil end

  local okArm, arm9 = pcall(function() return self.rom:arm9() end)
  if not (okArm and type(arm9) == "string") then return nil end

  local items = self:archive("items")
  local dataCount = tonumber(items and items.count) or 446
  local rows = dataCount + Gen4Items.GAP_SIZE
  local members = tonumber(arc.count) or 711

  local at, matches = Gen4ItemIcons.findTable(arm9, members, dataCount, rows)
  if not at then
    require("src.core.Logger").warn(
      "gen4 item icons: no %d-row archive table in the ARM9 -- the bag's "
      .. "icon frame stays empty", rows)
    return nil
  end

  -- A WRONG ARRAY DOES NOT FAIL, IT MIS-DRAWS.  Every item would still get an
  -- icon; a third of them would get somebody else's.  So the twelve rows that
  -- were checked by looking are asserted, and the stage declines outright
  -- rather than filling the bag with plausible wrong pictures.
  local okTable, wrong = Gen4ItemIcons.verify(arm9, at)
  if not okTable then
    require("src.core.Logger").warn(
      "gen4 item icons: the table at 0x%X disagrees with the verified "
      .. "items (%s) -- skipped rather than drawn wrong",
      at - 1, table.concat(wrong, ", "))
    return nil
  end
  if matches and matches > 1 then
    require("src.core.Logger").warn(
      "gen4 item icons: %d arrays fit the bounds; took the first, which "
      .. "passes the verified rows", matches)
  end

  local function member(i)
    local bytes = i and arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end

  -- Palettes are shared far more than sprites are, and composing is the
  -- expensive half; both get held for the whole run.
  local sheets, palettes = {}, {}
  local written, skipped = 0, 0
  for item = 0, rows - 1 do
    local _, iconId, palId = Gen4ItemIcons.row(arm9, at, item)
    if iconId and palId then
      if sheets[iconId] == nil then
        sheets[iconId] = Gen4Graphics.tiles(member(iconId)) or false
      end
      if palettes[palId] == nil then
        palettes[palId] = Gen4Graphics.palette(member(palId)) or false
      end
      local sheet, palette = sheets[iconId], palettes[palId]
      if sheet and palette then
        local cells = {}
        for i = 0, sheet.count - 1 do
          cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = 0 }
        end
        local image = Gen4Graphics.compose({
          width = Gen4ItemIcons.SIZE,
          height = Gen4ItemIcons.SIZE,
          cells = cells,
        }, sheet, palette)
        local key = ("items/icon_%03d"):format(item)
        local entry = image and self:saveImage(key, image, {
          kind = Gen4Screens.SHEET,
          item = item, icon = iconId, palette = palId,
        })
        if entry then
          index.screens[key] = entry
          written = written + 1
        else
          skipped = skipped + 1
        end
      else
        skipped = skipped + 1
      end
    end
  end
  if written == 0 then return nil end
  index.itemIcons = { count = written, size = Gen4ItemIcons.SIZE,
                      key = "items/icon_%03d" }
  return written, skipped
end

-- ---------------------------------------------------------------------------
-- The party icons
-- ---------------------------------------------------------------------------

-- One 32x64 picture per icon -- two frames of the bounce, stacked, which is
-- the shape `icons.bySpecies` already means everywhere else in this engine.
--
-- WHY IT IS SHAPED LIKE GEN 3'S. Gen3PartyMenu and Gen4PartyMenu ask the same
-- question of the same record (`icons.bySpecies[species]`, then `frameHeight`),
-- and the box, the summary page and the Poketch's party app all read it too. A
-- Gen 4 record with a shape of its own would have meant touching every one of
-- them to gain nothing.
function RomExtractorGen4:extractMonIcons()
  local arc = self:archiveAt(Gen4Icons.PATH)
  if not arc then return nil end

  local okArm, arm9 = pcall(function() return self.rom:arm9() end)
  if not (okArm and type(arm9) == "string") then return nil end

  -- NarcArchive keeps its member count as a plain field, so the sheet run is
  -- however many members follow the six cell and animation banks.
  local sheets = (tonumber(arc.count) or 547) - Gen4Icons.FIRST_SHEET
  local at, entropy = Gen4Icons.findPaletteTable(arm9, sheets)
  if not at then return nil end

  -- A WRONG TABLE DOES NOT FAIL, IT MIS-COLOURS -- which reads as a palette
  -- bug rather than as "the scan found the wrong array". So the seven values
  -- the render was checked against are asserted here, and the whole stage
  -- declines rather than writing a party list in the wrong colours.
  local okTable, wrong = Gen4Icons.verify(arm9, at)
  if not okTable then
    require("src.core.Logger").warn(
      "gen4 icons: the palette table found at 0x%X disagrees with the verified "
      .. "species (%s) -- the party icons are skipped rather than written in "
      .. "the wrong colours", at - 1, table.concat(wrong, ", "))
    return nil
  end

  local function member(i)
    local bytes = i and arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end

  local palette = Gen4Graphics.palette(member(Gen4Icons.PALETTE_MEMBER))
  if not palette then return nil end

  local bySpecies, written, skipped = {}, 0, 0
  for icon = 0, sheets - 1 do
    local sheet = Gen4Graphics.tiles(member(Gen4Icons.FIRST_SHEET + icon))
    if sheet then
      -- The ramp this icon uses, out of the ARM9 table -- and `compose` takes
      -- a sub-palette per CELL, so it is set on every cell rather than passed
      -- as an offset.
      local ramp = Gen4Icons.ramp(arm9, at, icon)
      local cells = {}
      for i = 0, sheet.count - 1 do
        cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = ramp }
      end
      local image = Gen4Graphics.compose({
        width = Gen4Icons.WIDTH,
        height = Gen4Icons.FRAME_HEIGHT * Gen4Icons.FRAMES,
        cells = cells,
      }, sheet, palette)
      local entry = image and self:saveImage(("pokemon/icon/%03d"):format(icon),
        image, { icon = icon, ramp = ramp,
                 frameHeight = Gen4Icons.FRAME_HEIGHT,
                 frames = Gen4Icons.FRAMES })
      if entry then
        bySpecies[icon] = { image = entry.path,
                            frameHeight = Gen4Icons.FRAME_HEIGHT }
        written = written + 1
      else
        skipped = skipped + 1
      end
    else
      skipped = skipped + 1
    end
    self:tick("species_sprites", icon + 1, sheets)
  end
  if written == 0 then return nil end

  return {
    bySpecies = bySpecies,
    frameHeight = Gen4Icons.FRAME_HEIGHT,
    frames = Gen4Icons.FRAMES,
    width = Gen4Icons.WIDTH,
    count = written, skipped = skipped,
    paletteTable = at - 1, spread = entropy,
    source = ("ROM:%s + ARM9+0x%X sPokemonIconPaletteIndex")
      :format(Gen4Icons.PATH, at - 1),
  }
end

-- ---------------------------------------------------------------------------
-- The battle subscreen
-- ---------------------------------------------------------------------------

-- Compose the seven bottom-screen tilemaps, once each for a layer whose
-- colours are fixed and once per battle background for a layer that follows
-- the backdrop.
--
-- IT IS THE SAME ARCHIVE AS THE BACKGROUNDS. pl_batt_bg carries the battle
-- backdrops, their palettes AND the whole bottom screen; the stage above walks
-- it for backdrops and never had a reason to ask for a tilemap in the forties.
-- One tile sheet (member 28) serves all seven maps.
function RomExtractorGen4:extractBattleSubscreen()
  local arc = self:archiveAt(Gen4Subscreen.PATH)
  if not arc then return nil end

  local function member(i)
    local bytes = i and arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end

  local sheet = Gen4Graphics.tiles(member(Gen4Subscreen.TILES))
  local base = Gen4Graphics.palette(member(Gen4Subscreen.PALETTE))
  if not (sheet and base) then return nil end

  -- Sub-palette 0 replaced, and NOTHING ELSE. The cartridge loads
  -- PALETTE_SIZE_BYTES to PLTT_DEST(0) -- one sub-palette over the first --
  -- so this copies sixteen entries and leaves the other fifteen sub-palettes
  -- exactly as member 242 wrote them.
  local function paletteFor(background)
    local row = Gen4Subscreen.BACKGROUND_PALETTES[background]
    local over = row and Gen4Graphics.palette(member(row[1]))
    if not over then return base end
    local out = {}
    for i = 1, #base do out[i] = base[i] end
    for i = 1, 16 do
      if over[i] then out[i] = over[i] end
    end
    return out
  end

  local index, written = { layers = {}, backgrounds = {} }, 0
  for _, layer in ipairs(Gen4Subscreen.LAYERS) do
    local map = Gen4Graphics.tilemap(member(layer.member))
    if map then
      -- Only the top 192 rows are ever on screen; the map is 256 tall because
      -- that is the smallest BG size that holds a screen. Cropping here rather
      -- than at draw time keeps 64 blank rows out of every one of these files.
      map.height = math.min(map.height or Gen4Subscreen.MAP_HEIGHT,
                            Gen4Subscreen.HEIGHT)
      local backgrounds = Gen4Subscreen.recolours(layer.name)
        and Gen4Subscreen.BACKGROUND_COUNT or 1
      local row = { member = layer.member, recolours =
                    Gen4Subscreen.recolours(layer.name) or nil, images = {} }
      for bg = 0, backgrounds - 1 do
        local image = Gen4Graphics.compose(map, sheet, paletteFor(bg))
        local entry = image and self:saveImage(
          Gen4Subscreen.imageName(layer.name, bg), image, {
            layer = layer.name, member = layer.member,
            background = Gen4Subscreen.recolours(layer.name) and bg or nil,
            source = ("ROM:pl_batt_bg member %d over tiles %d, palette %d")
              :format(layer.member, Gen4Subscreen.TILES, Gen4Subscreen.PALETTE),
          })
        if entry then
          row.images[bg] = entry.path
          written = written + 1
        end
      end
      if next(row.images) then index.layers[layer.name] = row end
    end
  end
  if written == 0 then return nil end

  index.width, index.height = Gen4Subscreen.WIDTH, Gen4Subscreen.HEIGHT
  index.written = written
  return index
end

-- ---------------------------------------------------------------------------
-- The healthbox parts
-- ---------------------------------------------------------------------------

-- Compose sHealthBoxPartsBitmap into one sheet, and say where the gauges are
-- inside it.
--
-- WHY IT IS SEARCHED FOR RATHER THAN ADDRESSED. A hard offset is a fact about
-- one build. The type chart and the object-graphics table are both found by
-- scanning the overlays for a signature and this follows them -- see
-- Gen4HealthboxParts for the signature, which is derived from the ENUM (three
-- identical empty-gauge tiles nine tiles apart, then four ramps that each add
-- one pixel column per step) and so writes no cartridge bytes into the port.
-- MEASURED OVER THE ARM9 AND ALL 122 OVERLAYS: it matches in exactly one place,
-- overlay 16, the battle overlay.
--
-- THE GAUGE GEOMETRY COMES OUT WITH IT. Each ramp's step size IS the gauge's
-- height in rows, and the two answers -- 2 rows for the three HP ramps, 1 for
-- the EXP ramp -- are the same one-versus-two the assembled box art shows,
-- where the HP trough is two pixels deep and the EXP groove is one. Neither
-- reading knows about the other.
function RomExtractorGen4:extractHealthboxParts(arc, paletteMember)
  if not (self.rom and arc and paletteMember) then return nil end

  local raw = arc:get(paletteMember)
  if not raw then return nil end
  if Gen4Graphics.isCompressed(raw) then raw = Gen4Graphics.decompress(raw) end
  local palette = Gen4Graphics.palette(raw)
  if not palette then return nil end

  local overlay, at, bin
  for id = 0, 130 do
    local ok, bytes = pcall(function() return self.rom:overlay(id) end)
    if ok and type(bytes) == "string" then
      local hit = Gen4HealthboxParts.find(bytes)
      if hit then overlay, at, bin = id, hit, bytes break end
    end
  end
  if not bin then return nil end

  local T = Gen4HealthboxParts.TILE_BYTES
  local count = Gen4HealthboxParts.COUNT
  local wide = Gen4HealthboxParts.TILES_WIDE

  -- Gen4Graphics.compose wants a sheet the way Gen4Graphics.tiles returns one.
  -- This is raw 4bpp tile data with no NCGR around it, so the three fields
  -- compose actually reads are supplied directly rather than parsed.
  local sheet = {
    bpp = 4, perTile = T, count = count, bitmap = false,
    pixels = bin:sub(at, at + T * count - 1),
  }
  local cells = {}
  for i = 0, count - 1 do
    cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = 0 }
  end
  local rows = math.ceil(count / wide)
  local image = Gen4Graphics.compose(
    { width = wide * 8, height = rows * 8, cells = cells }, sheet, palette)
  if not image then return nil end

  local gauges = {}
  for _, ramp in ipairs(Gen4HealthboxParts.RAMPS) do
    gauges[ramp.name] = {
      part = ramp.at,                      -- FILL_0's part index, 0-based
      steps = Gen4HealthboxParts.RAMP_TILES,
      cells = ramp.cells,
      rows = ramp.rows,
      width = ramp.cells * Gen4HealthboxParts.CELL_PX,
    }
  end

  local entry = self:saveImage("battle/healthbox_parts", image, {
    family = "healthboxes",
    count = count, tile = 8, tilesWide = wide,
    order = table.concat(Gen4HealthboxParts.PARTS, ","),
    source = ("ROM:overlay%d+0x%X, sHealthBoxPartsBitmap (%d tiles)")
      :format(overlay, at - 1, count),
  })
  if not entry then return nil end

  return {
    image = entry.path, count = count, tile = 8, tilesWide = wide,
    overlay = overlay, at = at - 1,
    gauges = gauges,
  }
end

-- ---------------------------------------------------------------------------
-- The healthbox numbers
-- ---------------------------------------------------------------------------

-- The glyph strip every number on a healthbox is drawn from, composed in the
-- healthbox family's own palette.  `arc` and `paletteMember` are the battle
-- object archive and the family's NCLR -- the same pair the parts sheet takes,
-- and for the same reason: the strip's pixels are role indices, not colours.
--
-- Returns nil rather than a half-answer on anything unexpected, which is what
-- every other stage here does: the screen that reads this declines and says so
-- once, and the box keeps whatever it was drawing before.
function RomExtractorGen4:extractBattleDigits(arc, paletteMember)
  if not (self.rom and arc and paletteMember) then return nil end

  local raw = arc:get(paletteMember)
  if not raw then return nil end
  if Gen4Graphics.isCompressed(raw) then raw = Gen4Graphics.decompress(raw) end
  local palette = Gen4Graphics.palette(raw)
  if not palette then return nil end

  local fonts = self:archive("fonts")
  local member = fonts and fonts:get(Gen4SpecialChars.MEMBER)
  if not member then return nil end
  if Gen4Graphics.isCompressed(member) then
    member = Gen4Graphics.decompress(member)
  end
  local sheet = Gen4Graphics.tiles(member)
  if not (sheet and sheet.pixels) then return nil end

  -- THE MEMBER INDEX IS FROM AN ORDER FILE, SO IT IS CHECKED.  A strip whose
  -- glyph tiles use a nibble above 2 is not this sheet -- the roles ARE the
  -- whole content of it -- and an archive that has been repacked would
  -- otherwise be composed into confetti in the healthbox's colours.
  local shaped = Gen4SpecialChars.looksRight(sheet.pixels)
  if not shaped then return nil end

  local roles = Gen4SpecialChars.rolePalette(palette)
  if not roles then return nil end

  local count = Gen4SpecialChars.COUNT
  local cells = {}
  for i = 0, count - 1 do
    cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = 0 }
  end
  -- ONE ROW, so a consumer indexes a glyph by multiplying: tile n is at
  -- x = n * 8, y = 0, which is the arithmetic the enum already gives it.
  local image = Gen4Graphics.compose(
    { width = count * Gen4SpecialChars.TILE, height = Gen4SpecialChars.TILE,
      cells = cells }, sheet, roles)
  if not image then return nil end

  local entry = self:saveImage("battle/healthbox_digits", image, {
    family = "healthboxes",
    count = count, tile = Gen4SpecialChars.TILE,
    source = ("ROM:pl_font.narc[%d] font_special_chars, in the healthbox "
              .. "palette at fg %d / shadow %d")
      :format(Gen4SpecialChars.MEMBER, Gen4SpecialChars.BATTLE_FG,
              Gen4SpecialChars.BATTLE_SHADOW),
  })
  if not entry then return nil end

  return {
    image = entry.path,
    tile = Gen4SpecialChars.TILE,
    count = count,
    digit0 = Gen4SpecialChars.DIGIT_0,
    digits = Gen4SpecialChars.DIGITS,
    glyphs = Gen4SpecialChars.GLYPHS,
    -- Recorded so a reader can tell the sheet was composed for the BATTLE and
    -- not for the party screen, which asks the same strip for other colours.
    fg = Gen4SpecialChars.BATTLE_FG,
    shadow = Gen4SpecialChars.BATTLE_SHADOW,
    bg = Gen4SpecialChars.BATTLE_BG,
  }
end

-- ---------------------------------------------------------------------------
-- The window frames
-- ---------------------------------------------------------------------------

-- pl_winframe, laid out the way the ENGINE reads a frame rather than the way
-- the generic screen planner lays out a sheet.
--
-- The planner above already writes every member of this archive as a picture,
-- at eight tiles across, which is fine for looking at and useless for drawing:
-- `src/render/Font.lua` wants a standard frame as a 24x24 cell (three tiles
-- across, in member order) and a dialogue frame as one row of eighteen.  Both
-- are the same pixels at a different stride, so this costs one more compose per
-- frame and nothing else.
--
-- WHY THIS IS WORTH A STAGE OF ITS OWN.  Font.drawBox is what every menu, every
-- choice box and every message in this engine goes through.  Give it a frames
-- record and all of them are Platinum's in one step; leave it out and each new
-- Gen 4 screen has to draw its own border, which is how twenty screens end up
-- with twenty slightly different rectangles.
function RomExtractorGen4:extractWindowFrames()
  local arc = self:archive("winframe")
  if not arc then return nil end
  local groups = Gen4Archives.groups(PATH.winframe)
  if not groups then return nil end

  local byBase = {}
  for _, group in ipairs(groups) do byBase[group.base] = group end

  local out = {}

  -- THE STANDARD FRAME, three tiles across.  Both variants go on one sheet in
  -- the order LoadStandardWindowTiles chooses between them, so a save (or a
  -- mod) can select the field one; frame 1 is the system one, which is what
  -- every menu uses.
  local cells = {}
  for _, spec in ipairs(Gen4Menus.STANDARD) do
    local group = byBase[spec.name]
    local palette = byBase[spec.palette]
    -- `standard_field` carries no palette of its own.  That is a fact about
    -- the archive, not a failure: it is drawn with the system palette, and
    -- naming the borrow here keeps it out of the generic shared-sheet
    -- guesswork above.
    if group and group.NCGR and palette and palette.NCLR then
      local image = self:composeJob(arc, {
        tiles = group.NCGR, palette = palette.NCLR,
        tilesWide = Gen4Menus.STANDARD_TILES_WIDE,
      })
      if image and image.width == 24 and image.height == 24 then
        cells[#cells + 1] = { name = spec.name, image = image }
      end
    end
  end
  if #cells > 0 then
    local sheet = stackImages(cells, 24, 24)
    local entry = sheet and self:saveImage("windows/frames", sheet, {
      count = #cells, cell = 24, tile = 8,
      order = (function()
        local names = {}
        for i, c in ipairs(cells) do names[i] = c.name end
        return table.concat(names, ",")
      end)(),
    })
    if entry then
      out.standard = {
        image = entry.path, count = #cells, cell = 24, tile = 8,
      }
    end
  end

  -- THE DIALOGUE FRAME: all twenty message boxes, each as one row of eighteen
  -- tiles, stacked.  Eighteen across is the stride Font.lua's dialogue reader
  -- already uses, so the only new thing is the row.
  local strips, fill = {}, nil
  for frame = 0, Gen4Menus.MESSAGE_BOX_COUNT - 1 do
    local group = byBase[Gen4Menus.messageBoxName(frame)]
    if group and group.NCGR and group.NCLR then
      local image = self:composeJob(arc, {
        tiles = group.NCGR, palette = group.NCLR,
        tilesWide = Gen4Menus.MESSAGE_BOX_TILES,
      })
      if image and image.height == 8 then
        strips[#strips + 1] = { name = group.base, image = image }
        -- The interior colour, read off the one tile of the eighteen that
        -- DrawMessageBoxFrame never places -- `tile + 8`, the only solid tile
        -- in the sheet.  Sampling it beats choosing a colour that looks close:
        -- it is the colour the window bitmap would have covered.
        if not fill then fill = pixelAt(image, Gen4Menus.FILL_SAMPLE_X,
                                       Gen4Menus.FILL_SAMPLE_Y) end
      end
    end
  end
  if #strips > 0 then
    local sheet = stackImages(strips, Gen4Menus.MESSAGE_BOX_TILES * 8, 8)
    local entry = sheet and self:saveImage("windows/dialogue", sheet, {
      count = #strips, tiles = Gen4Menus.MESSAGE_BOX_TILES,
    })
    if entry then
      out.dialogue = {
        image = entry.path,
        tiles = Gen4Menus.MESSAGE_BOX_TILES,
        count = #strips,
        -- Which arrangement the eighteen are in.  Font.lua's existing dialogue
        -- reader is FireRed's -- five-tile rows mirrored back down -- and this
        -- one is not, so the record says which rather than letting the reader
        -- assume.
        layout = "gen4",
        fill = fill,
      }
    end
  end

  self._winFrames = out
  return out
end

-- ---------------------------------------------------------------------------
-- Fonts
-- ---------------------------------------------------------------------------

-- The four NFGR fonts, and the per-glyph widths that text layout needs.
--
-- This is a stage of its own rather than a corner of the graphics one because
-- what it produces is not really a picture.  A font sheet is written so the
-- result can be LOOKED AT, but the thing the engine will actually consume is
-- the width table: 509 advances per font, without which every line of Gen 4
-- text is monospaced and wrong.
--
-- Colours are NOT baked in beyond the preview.  A glyph pixel is a ROLE --
-- nothing, foreground, shadow, background -- and the game picks three real
-- colours per text box at draw time.  Writing one colouring into the cache
-- would freeze menu text into battle colours.
function RomExtractorGen4:extractFonts()
  self:beginStage("fonts")

  local index = { fonts = {}, pages = {}, skipped = {} }
  local arc = self:archive("fonts")
  if not arc then
    self:write("gen4_fonts", index)
    return index
  end

  local names = Gen4Archives.names(PATH.fonts)
  for member = 0, arc.count - 1 do
    local name = names and names[member + 1]
    -- NFGR carries no magic, so it is identified by its own arithmetic: the
    -- header's offsets and counts have to account for the member's length
    -- EXACTLY.  That is a far stronger test than a four-byte tag, and it is
    -- the only one available here.
    local raw = arc:get(member)
    local font = raw and Gen4Font.parse(raw)
    if font and font.exact then
      local label = name and Gen4Archives.baseName(name) or ("font_%02d"):format(member)
      local sheet = Gen4Font.sheet(font, { columns = 32 })
      local entry = self:saveImage("font/" .. label .. "_sheet", sheet, {
        glyphs = font.numGlyphs,
        glyphWidth = font.pixelWidth,
        glyphHeight = font.pixelHeight,
        maxWidth = font.maxWidth,
        maxHeight = font.maxHeight,
        columns = 32,
        -- The sheet is a preview in one arbitrary colouring; the roles below
        -- are what a renderer should use.
        preview = true,
      })

      -- Widths as a plain array, one byte per glyph, indexed from zero the way
      -- the cartridge indexes them.  A character code reaches its glyph by
      -- subtracting one -- charcode 1 is glyph 0 -- and that is the game's own
      -- rule, not a convention this extractor invented.
      local widths = {}
      for glyph = 0, font.numGlyphs - 1 do
        widths[glyph + 1] = font.widths[glyph]
      end

      index.fonts[label] = {
        member = member,
        glyphs = font.numGlyphs,
        glyphWidth = font.pixelWidth,
        glyphHeight = font.pixelHeight,
        maxWidth = font.maxWidth,
        maxHeight = font.maxHeight,
        tilesWide = font.tilesWide,
        tilesHigh = font.tilesHigh,
        widths = widths,
        sheet = entry and entry.path or nil,
        roles = Gen4Font.ROLES,
      }

      -- The same font again, in the shape src/render/Font.lua already reads.
      -- BASE IS 1, not 0: the cartridge reaches a glyph by subtracting one
      -- from the character code, so code 1 is glyph 0.  Font.lua indexes its
      -- quads by `code - base` and its widths by `code - base + 1`, which with
      -- base 1 lands on exactly the array written above -- the two agree
      -- without either side adjusting for the other.
      index.pages[label] = {
        image = entry and entry.path or nil,
        base = 1,
        glyphsPerRow = 32,
        glyphWidth = font.pixelWidth,
        glyphHeight = font.pixelHeight,
        -- The fallback for a code the width table does not cover.  The real
        -- advances are in `widths` and Font.advanceOf prefers them.
        advance = font.maxWidth,
        widths = widths,
        -- The sheet carries its own two tones, so it blits as it is rather
        -- than being multiplied by whatever colour a menu last set.
        preTinted = true,
      }
    elseif name and name:upper():match("NFGR") then
      -- A member NAMED as a font that does not parse is worth recording; a
      -- member that is simply something else is not.
      index.skipped[#index.skipped + 1] = name
    end
    self:tick("fonts", member + 1, arc.count)
  end

  self:write("gen4_fonts", index)
  self:writeFontDef(index)
  return index
end

-- Publish the fonts as `data.font`, which is what src/render/Font.lua loads.
--
-- This deliberately does NOT invent a fourth spelling.  Font.lua already takes
-- a page table, named faces beside it, per-glyph widths and a charmap, because
-- Gen 1, Gen 2 and Gen 3 each needed some of that; Gen 4 needs the same things
-- and nothing new.  Writing a gen4-shaped font table instead would mean a
-- generation branch in every screen that draws a word.
--
-- ONE PAGE, THREE FACES.  All four fonts number their glyphs from the same
-- base, so registering them as four pages would leave the code-to-page lookup
-- answering with whichever sorted first -- the exact problem Font.lua's own
-- comment describes for Emerald's five Latin faces.  The message font is the
-- page because it is the one dialogue is set in; the other three are faces,
-- chosen by name.
function RomExtractorGen4:writeFontDef(index)
  local PRIMARY = "font_message"
  -- Written by the graphics stage, which runs first.  Absent only when
  -- pl_winframe did not read, and then both records below are simply nil and
  -- Font.lua falls back to the drawn rectangle.
  local winFrames = self._winFrames or {}
  local page = index.pages[PRIMARY]
  if not page then
    -- Rather than pick an arbitrary survivor: without the dialogue font there
    -- is no sensible primary, and a font table with the wrong primary is worse
    -- than none, which merely falls back to the built-in raster.
    return
  end

  local faces = {}
  for label, other in pairs(index.pages) do
    if label ~= PRIMARY then
      faces[label:gsub("^font_", "")] = other
    end
  end

  -- The charmap, inverted from the text decoder so the two cannot disagree
  -- about what a character is.
  --
  -- Only codes the font actually HAS are included.  Gen4Text knows 2,876
  -- characters and this cartridge's font holds 509 glyphs, so the rest are
  -- Japanese codes with nothing to draw; mapping them would put a character on
  -- screen as whatever happened to sit at that quad. 484 of the 509 are
  -- spoken for, and none of them is a ligature -- no entry in range covers
  -- more than one character -- so there is no multi-letter sequence here to
  -- mis-match ordinary text the way Gen 3's PK/MN pair does.
  local charmap = {}
  for code, text in pairs(Gen4Text.CHARS) do
    if type(code) == "number" and type(text) == "string"
        and code >= 1 and text ~= "" then
      local entry = index.fonts[PRIMARY]
      if entry and code <= entry.glyphs then
        charmap[#charmap + 1] = { code = code, seq = text }
      end
    end
  end
  table.sort(charmap, function(a, b) return a.code < b.code end)

  self:write("font", {
    pages = { message = page },
    faces = next(faces) and faces or nil,
    charmap = charmap,
    -- Gen 4 draws its own window frames; they come out of pl_winframe in the
    -- graphics stage rather than being tiled from font cells the way Gen 1
    -- and Gen 2 do.  `frame = "drawn"` stays as the floor under both records
    -- below: a cache extracted before the frame stage existed still gets a
    -- rectangle rather than a box with no border at all.
    frame = "drawn",
    frames = winFrames.standard,
    dialogueFrame = winFrames.dialogue,
    source = ("ROM:pl_font.narc NFGR (%d glyphs, %dx%d, %d charmap entries)")
      :format(index.fonts[PRIMARY].glyphs, page.glyphWidth, page.glyphHeight,
              #charmap),
  })
end

-- ---------------------------------------------------------------------------
-- The stand-in tileset
-- ---------------------------------------------------------------------------

-- Gen 4's world is 3D -- an NSBMD mesh and a texture set per chunk -- and
-- there is no tileset in the Gen 1-3 sense anywhere in the cartridge.
-- MapLoader pairs every map def with one anyway, so until the mesh pipeline
-- exists a Platinum map cannot be BUILT, never mind drawn.
--
-- So one is synthesised: a flat colour per terrain class, keyed by the
-- behaviour byte every permission cell already carries.  It is shaped exactly
-- like a Gen 3 tileset, which is what makes it cost nothing -- TileRenderer
-- takes any tileset whose blockTiles is 2 and hands it to Gen3Tiles, so this
-- goes down the path Hoenn already uses and the renderer needs no Gen 4 branch
-- at all.
--
-- TWO RECORDS, as Gen 3 writes: the raw tileset the compositor reads
-- (map_tilesets) and the pair record a map def names (tilesets).
function RomExtractorGen4:extractTilesets()
  self:beginStage("tilesets")

  local primary = Gen4Tileset.primary()
  local pair = Gen4Tileset.pair()

  self:write("map_tilesets", { [Gen4Tileset.PRIMARY_ID] = primary })
  self:write("tilesets", { [Gen4Tileset.ID] = pair })

  -- The atlas is for looking at rather than for drawing -- Gen3Tiles
  -- composites from `tiles` and `palettes` -- but a picture of the colour key
  -- is worth having when a map comes out the wrong colour.
  self:saveImage("tileset/standin", Gen4Tileset.atlas(), { key = true })

  -- How many of the 256 BEHAVIOUR VALUES land in each class.  Not how many
  -- cells: only 75 of the 256 values occur anywhere in this cartridge, so the
  -- unknown bucket is large here and vanishingly small on the map -- 14 cells
  -- out of 346,819, every one of them a value the cartridge itself calls
  -- UNKNOWN_xNN.  Naming the field for what it counts is the difference
  -- between that being obvious and it reading as a broken classifier.
  local valuesPerClass = {}
  for behaviour = 0, 255 do
    local class = Gen4Tileset.classOf(behaviour)
    valuesPerClass[class.name] = (valuesPerClass[class.name] or 0) + 1
  end

  self.tilesetReport = {
    classes = #Gen4Tileset.CLASSES,
    valuesPerClass = valuesPerClass,
  }
  return pair
end

-- ---------------------------------------------------------------------------
-- Constants and the type chart
-- ---------------------------------------------------------------------------

-- The tables the ENGINE asks for by name, rather than the ones the cartridge
-- happens to have.
--
-- Everything above this point writes what Platinum contains. This writes what
-- src/core/Data.lua opens, and the difference between the two is why a cache
-- full of correct data still does not boot: Data requires `constants`, `maps`,
-- `pokemon`, `moves`, `items`, `text`, `type_chart` and the rest by those
-- exact names, and a table called `gen4_species` is not one of them however
-- right it is.
--
-- `constants.gen` alone is read in seventy-one places. It is the value the
-- whole engine branches on, and without it nothing downstream knows which
-- generation it is running.
function RomExtractorGen4:extractConstants()
  self:beginStage("constants")

  -- The type chart, out of the battle overlay. See Gen4TypeChart for why the
  -- search is structural and why stopping at the first terminator would make
  -- Normal do neutral damage to Ghost.
  local chart, parsed
  for overlay = 0, 130 do
    local ok, bytes = pcall(function() return self.rom:overlay(overlay) end)
    if ok and bytes and #bytes > 0 then
      local at = Gen4TypeChart.find(bytes)
      if at then
        parsed = Gen4TypeChart.parse(bytes, at)
        if parsed then
          parsed.overlay = overlay
          chart = Gen4TypeChart.chart(parsed)
          break
        end
      end
    end
    self:tick("constants", overlay + 1, 140)
  end
  if chart then self:write("type_chart", chart) end

  -- The eighteen type names, in the cartridge's own order -- which is how the
  -- type NUMBERING was established rather than assumed. Slot 9 is the unused
  -- "???" type and is kept, because leaving it out shifts every type above it.
  local types = {}
  for i = 0, Gen4TypeChart.TYPE_COUNT - 1 do
    types[i] = self:string(BANK.typeName, i) or Gen4TypeChart.TYPES[i]
  end

  local natures = {}
  for i = 0, 24 do natures[i + 1] = self:string(BANK.nature, i) end

  local function order(count)
    local out = {}
    for i = 1, count do out[i] = i end
    return out
  end

  -- SINNOH'S EIGHT, in the cartridge's own numbering.
  --
  -- `givebadge <n>` and `checkbadgeacquired <n>` index a bit field, and `n` is
  -- the position in `generated/badges.txt` -- Coal, Forest, Cobble, Fen, Relic,
  -- Mine, Icicle, Beacon.  `ScrCmd_CountBadgesAcquired` walks a `sBadgeIDs`
  -- table that turns out to be the identity permutation (pret's comment on it
  -- is "Game Freak moment"), so the order here is the whole mapping.
  --
  -- WITHOUT THIS, `Badges.list` fell through to the KANTO eight and a Gen 4
  -- script asking for badge 0 was asking about the BOULDERBADGE.  Nothing had
  -- noticed because nothing awarded a Gen 4 badge at all -- `givebadge` had no
  -- lowering -- so every count was zero and every gate stayed shut.
  --
  -- No display names: the cartridge keeps them in the trainer card's ART and
  -- in gym dialogue ("received the Coal Badge from Roark!"), not in a table, so
  -- claiming one here would be inventing it.
  local badges = {}
  for i, id in ipairs({ "COAL", "FOREST", "COBBLE", "FEN",
                        "RELIC", "MINE", "ICICLE", "BEACON" }) do
    badges[i] = { id = "BADGE_" .. id }
  end

  -- WHAT THE ORDINARY POKE MART SELLS.  A C array in the ARM9 binary rather
  -- than a NARC member -- see Gen4Mart for why that is, and for the byte
  -- pattern that pins it down.
  local martCommon, martSpecialties, martAt, martHits
  do
    local ok, arm9 = pcall(function() return self.rom:arm9() end)
    if ok and type(arm9) == "string" then
      martAt, martHits = Gen4Mart.find(arm9)
      martCommon = martAt and Gen4Mart.parse(arm9, martAt) or nil
      martSpecialties = Gen4Mart.specialties(arm9, self.rom:header().arm9.ram)
    end
    -- A miss is reported through `constantsReport` rather than thrown: the
    -- import's own report is where a stage says what it found, and a cartridge
    -- whose mart table moved should still produce a playable cache.
    -- `martRows = 0` in that report is the whole signal.
  end

  -- WHAT A NEW GAME STARTS WITH SET, AND WHY SINNOH WAS FULL OF PEOPLE.
  --
  -- Reported from play: *"barry can be seen standing at the top of the stairs
  -- too not normal"*, and his mother standing in the doorway of the player's
  -- house before she has any business being there.
  --
  -- `FieldSystem_InitNewGameState` (script_manager.c) runs ONE script at the
  -- start of a new game, before the first map is even built:
  --
  --     FieldSystem_RunScript(fieldSystem, SCRIPT_ID(INIT_NEW_GAME, 0));
  --
  -- and that script -- band 9600, `scripts_init_new_game` -- is 119
  -- instructions in a single straight-line block, of which **112 are
  -- `setflag`**.  A set flag HIDES its object, so those 112 are the whole of
  -- "the cutscene actors whose stories have not started yet are not on the map
  -- yet".  Flag 0x173 is the placeholder in the player's BEDROOM, which is
  -- Barry at the top of the stairs; 0x1F1 is the one in the house below, which
  -- is his mother in the doorway.
  --
  -- The port never ran it, so all 112 stayed clear and every one of those
  -- actors spawned.
  --
  -- REPLAYED AS EFFECTS rather than executed, which is what Gen 3 already does
  -- with its own `EventScript_ResetAllMapFlags` (see `gen3NewGameFlags`).  The
  -- block has no branches at all -- one entry point, one block, no `goto` and
  -- no `callif` -- so the effects ARE the script, and `boot.initialFlags` is a
  -- seam that already exists and is already applied by `SaveData.newGame`.
  local newGame
  do
    local names = Gen4Archives.names(PATH.scripts)
    local memberOf = {}
    for index, name in ipairs(names or {}) do memberOf[name] = index - 1 end
    local file
    for _, band in ipairs(Gen4ScriptBands.BANDS) do
      if band[2] == "init_new_game" then file = band[3] end
    end
    local member = file and memberOf[file]
    local arc = member and self:archive("scripts")
    local bytes = arc and member < arc.count and arc:get(member)
    local entries = bytes and Gen4Script.entries(bytes)
    if entries and entries[1] then
      local flags, cleared, vars, seen = {}, {}, {}, {}
      -- Branch targets are followed for the same reason `extractScripts`
      -- follows them: a block reached only by a jump is still part of the
      -- script.  This one has none, and the walk costs nothing to be sure.
      local queue = { entries[1] }
      seen[entries[1]] = true
      local i = 1
      while i <= #queue do
        local at = queue[i]; i = i + 1
        for _, ins in ipairs(Gen4Script.decode(bytes, at)) do
          local t = ins.target
          if t and t >= 1 and t <= #bytes and not seen[t] then
            seen[t] = true; queue[#queue + 1] = t
          end
          if ins.name == "setflag" then
            flags[#flags + 1] = Gen4ScriptVM.flagName(ins.args[1])
          elseif ins.name == "clearflag" then
            cleared[#cleared + 1] = Gen4ScriptVM.flagName(ins.args[1])
          elseif ins.name == "setvarfromvalue" then
            vars[#vars + 1] = { id = ins.args[1], value = ins.args[2] }
          end
        end
      end
      newGame = {
        flags = flags, cleared = cleared, vars = vars,
        member = member,
        source = ("ROM:%s entry 0, %d setflag / %d clearflag / %d setvar")
          :format(file, #flags, #cleared, #vars),
      }
    end
  end

  -- THE PATCH OF DARK UNDER EVERYBODY.  See Gen4Shadow for the whole chain:
  -- which graphics ids cast one, how big, what turns it off, and where the
  -- picture is.  Reported from play as missing entirely.
  local shadow
  do
    local table_, rows, at, hits
    for overlay = 0, 130 do
      local ok, bytes = pcall(function() return self.rom:overlay(overlay) end)
      if ok and bytes and #bytes > 0 then
        at, hits = Gen4Shadow.find(bytes)
        if at then
          table_, rows = Gen4Shadow.parse(bytes, at)
          if table_ then
            shadow = {
              byGraphics = table_,
              rows = rows,
              overlay = overlay,
              at = at - 1,
              matches = hits,
              sizes = Gen4Shadow.SIZES,
              scales = Gen4Shadow.SCALES,
              suppress = Gen4Shadow.suppressed(Gen4Behaviors),
              source = ("ROM:overlay%d+0x%X, gObjectEventGfxRenderDetailsTable")
                :format(overlay, at - 1),
            }
            break
          end
        end
      end
    end
    -- ...AND THE PICTURE, which is embedded in its own model rather than in a
    -- texture archive: fldeff member 0x11 is an NSBMD named `kage` whose TEX0
    -- section carries a 16x16 `kage` worn with `kage_pl`.  Two earlier guesses
    -- -- the map texture sets and mmodel -- have neither, which is worth
    -- recording so nobody looks there again.
    local raw = self.rom:read(Gen4Shadow.ARCHIVE)
    local arc = raw and Narc.parse(raw) or nil
    local bytes = arc and Gen4Shadow.MEMBER < arc.count and arc:get(Gen4Shadow.MEMBER)
    local sections = bytes and Gen4Nsbmd.sections(bytes)
    local texAt = sections and sections.TEX0
    if texAt then
      local parsed = Gen4Models.parse(bytes, texAt)
      local index = parsed and Gen4Models.paletteIndexByName(parsed, Gen4Shadow.PALETTE)
      local image = parsed and Gen4Models.decode(parsed, bytes, 1, index or 1)
      local entry = image and self:saveImage("field/shadow", image)
      if entry and shadow then shadow.image = entry end
    end
  end

  -- THE EXPERIENCE CURVES, BECAUSE TWO OF THE SIX HAVE NO FORMULA.
  --
  -- `Growth` carries the six polynomials Gen 1 and Gen 2 get away with, and
  -- Gen 3 added ERRATIC and FLUCTUATING, which are piecewise and have no closed
  -- form at all.  Without a table those two fall back to MEDIUM_FAST with a
  -- one-time warning -- and the gap is not small: at level 100 MEDIUM_FAST
  -- wants 1,000,000 experience, ERRATIC 600,000 and FLUCTUATING 1,640,000, so
  -- 36 of Sinnoh's 508 species were levelling on a curve 40% too slow or 64%
  -- too fast for their whole run.
  --
  -- `Pokemon_LoadExperienceTableOf` reads the whole member:
  --
  --     NARC_ReadWholeMemberByIndexPair(monExpTable,
  --         NARC_INDEX_POKETOOL__PERSONAL__PL_GROWTBL, monExpRate)
  --
  -- so the archive is one member per rate, indexed by the same `expRate` byte a
  -- species record carries -- 8 members of 101 u32, levels 0..100.  The order
  -- is `generated/exp_rates.txt`, which is the SAME order Gen 3's extractor
  -- uses for `gExperienceTables`, so the shape `Growth.setTables` already reads
  -- needs no translation.
  --
  -- CHECKED AGAINST THE FORMULAS RATHER THAN TRUSTED.  MEDIUM_SLOW and FAST
  -- match their polynomial at all 100 levels; MEDIUM_FAST and SLOW match at 99
  -- of 100, and the single disagreement is LEVEL 1, where the table says 0 and
  -- the formula says 1 -- the cartridge is right, because level 1 costs no
  -- experience.  So the table is not only exact for the two curves that had
  -- none, it is a correction for two that did.  All six are monotonic.
  local growth = self:archive("growthTables")
  local experienceTables, growthReport = nil, nil
  if growth then
    local ORDER = { "MEDIUM_FAST", "ERRATIC", "FLUCTUATING",
                    "MEDIUM_SLOW", "FAST", "SLOW" }
    local out, rows = {}, 0
    for i, name in ipairs(ORDER) do
      local member = growth:get(i - 1)
      if member and #member >= 404 then
        local curve = {}
        for level = 0, 100 do
          local a, b, c, d = member:byte(level * 4 + 1, level * 4 + 4)
          -- 1-based BY LEVEL, so curve[1] is the experience for level 1 --
          -- the same indexing Gen 3 writes and `Growth.expForLevel` reads.
          curve[level + 1] = a + b * 256 + c * 65536 + d * 16777216
        end
        out[name] = curve
        rows = rows + 1
      end
    end
    if rows > 0 then
      experienceTables = out
      growthReport = rows
    end
  end
  -- Reported the way every other stage in this file reports: a field on the
  -- extractor, not a log line.  THIS FILE REQUIRES NO LOGGER AT ALL -- an
  -- earlier draft of this block called `Logger.info` and would have taken the
  -- whole import down on a nil index at the one moment nobody is watching.
  self.growthReport = { curves = growthReport or 0 }

  -- THE MOVE EACH TM AND HM TEACHES -- `sTMHMMoves`, a flat ARM9 table.
  --
  -- `Item_MoveForTMHM(item)` is `sTMHMMoves[item - ITEM_TM01]`: 100 u16 in
  -- TM01..TM92 then HM01..HM08 order.  It is the only place the pairing
  -- exists.  A TM's own item description is the MOVE's description re-wrapped,
  -- and joining on that was tried and MEASURED: 0 of 100 raw, 61 of 100 with
  -- the line breaks normalised.  Sixty-one per cent is not a table, so the
  -- ARM9 is read instead.
  --
  -- FOUND BY THE HM TAIL, not by an address, because Rev 0 is a different
  -- binary: the eight HMs are a fixed and highly distinctive run (Cut, Fly,
  -- Surf, Strength, Defog, Rock Smash, Waterfall, Rock Climb = 15, 19, 57, 70,
  -- 432, 249, 127, 431), so the search is for that sequence and the table is
  -- the 92 entries in front of it.
  --
  -- TWO MATCHES IN THE ARM9 and only one is the table -- the same shape as the
  -- type chart's two terminators, and the same lesson: take the one that
  -- VALIDATES rather than the first one found.  Every entry must be a move
  -- this cartridge has and no entry may repeat.
  --
  -- The check that says the search worked is that the result is recognisable:
  -- TM01 Focus Punch, TM02 Dragon Claw, TM03 Water Pulse, TM04 Calm Mind,
  -- TM05 Roar, TM86 Grass Knot (Gardenia's), TM92 Trick Room.
  local tmhmMoves, tmhmReport = nil, nil
  do
    local HM_TAIL = { 15, 19, 57, 70, 432, 249, 127, 431 }
    local NUM_TMS, NUM_HMS = 92, 8
    local needle = {}
    for _, v in ipairs(HM_TAIL) do
      needle[#needle + 1] = string.char(v % 256, math.floor(v / 256) % 256)
    end
    needle = table.concat(needle)
    local ok, arm9 = pcall(function() return self.rom:arm9() end)
    if ok and type(arm9) == "string" then
      local at, candidates = 1, 0
      while true do
        local p = arm9:find(needle, at, true)
        if not p then break end
        at = p + 1
        candidates = candidates + 1
        local start = p - NUM_TMS * 2
        if start >= 1 and not tmhmMoves then
          local list, good, seen = {}, true, {}
          for i = 0, NUM_TMS + NUM_HMS - 1 do
            local a, b = arm9:byte(start + i * 2, start + i * 2 + 1)
            local v = (a or 0) + (b or 0) * 256
            if v == 0 or seen[v] then good = false end
            seen[v] = true
            list[i + 1] = v
          end
          if good then
            tmhmMoves = list
            tmhmReport = { at = start - 1, entries = #list }
          end
        end
      end
      tmhmReport = tmhmReport or { candidates = candidates }
      tmhmReport.candidates = candidates
    end
  end
  self.tmhmReport = tmhmReport or { entries = 0 }

  -- ...AND WHICH SPECIES CAN LEARN WHICH OF THEM, which is the half that was
  -- missing and the reason a TM could not be used in Sinnoh at all.
  --
  -- `def.tmhm` -- a plain list of move ids -- is what ItemEffects.use scans
  -- when a machine is used, what DayCare reads for egg moves, and what a party
  -- screen asks to print ABLE or UNABLE beside a member.  On a Gen 1-3 cache
  -- the extractor writes it directly; ON A GEN 4 CACHE IT WAS NEVER WRITTEN AT
  -- ALL, and ItemEffects scans it with a bare `ipairs(speciesDef.tmhm)`, so
  -- teaching a TM on Platinum did not merely look wrong -- IT RAISED.
  --
  -- The cartridge does not store a list. It stores a 128-BIT MASK, four u32 on
  -- every personal record, and CanPokemonFormLearnTM turns a machine id into
  -- (word, bit) with `tmID < 32 -> mask 1, 1 << tmID`, then 32/64/96. So bit b
  -- of word w is machine w * 32 + b, ZERO-BASED, in the same TM01..TM92,
  -- HM01..HM08 order sTMHMMoves is in -- which is what makes the pairing one
  -- index and not a join.
  --
  -- TWO THINGS SAY THE BIT ORDER IS RIGHT, and neither is the arithmetic:
  --   * 100 machines live in 128 bits, so 28 bits are spare. Measured over all
  --     493 species: the highest bit set anywhere is 99 and NOTHING is set at
  --     or above 100. A wrong word order or a flipped bit order would scatter
  --     set bits into that empty tail.
  --   * MAGIKARP AND DITTO COME OUT WITH EXACTLY ZERO. They are the two
  --     species in the game that learn no machine at all, and "exactly none"
  --     is a result a wrong reading does not produce -- it produces a
  --     plausible handful. Bulbasaur comes out with 28, ending HM01 Cut,
  --     HM04 Strength, HM06 Rock Smash; Pikachu with 32, including TM24
  --     Thunderbolt, TM25 Thunder and TM73 Thunder Wave.
  local machineReport = { species = 0, machines = 0, highest = -1, stray = 0 }
  if tmhmMoves and self._pokemon then
    for _, def in pairs(self._pokemon) do
      local mask = def.tmLearnset
      if type(mask) == "table" then
        local list = {}
        for word = 1, 4 do
          local v = mask[word] or 0
          for bit = 0, 31 do
            if v % 2 == 1 then
              local id = (word - 1) * 32 + bit          -- zero-based machine id
              if id > machineReport.highest then machineReport.highest = id end
              if id >= #tmhmMoves then
                machineReport.stray = machineReport.stray + 1
              else
                list[#list + 1] = tmhmMoves[id + 1]
              end
            end
            v = floor(v / 2)
          end
        end
        def.tmhm = list
        machineReport.species = machineReport.species + 1
        machineReport.machines = machineReport.machines + #list
      end
    end
    -- Written here as well as by the sprite stage that runs later, because a
    -- reader should not have to know the order of the stages to know when the
    -- module on disk became correct.
    self:write("pokemon", self._pokemon)
  end
  self.machineReport = machineReport

  -- THE FOUR IN-GAME TRADES. See src/import/Gen4Trades.lua for the record's
  -- twenty words, why the pairing reads as itself, and why the OT names are
  -- the same bank plus four. Written into `constants` beside `gen3Trades` so
  -- the two generations' trade rows carry the same vocabulary -- with one
  -- difference stated rather than smoothed over: GEN 3'S `species` AND
  -- `request` ARE STRINGS and Gen 4's are the cartridge's NUMBERS, because a
  -- Gen 4 script compares species NUMBERS (`comparevartovar` against
  -- `getpartymonspecies`) and converting them to names here would mean
  -- converting them back at every site.
  local trades
  do
    local arc = self:archive("trades")
    local bank = self:bank(BANK.tradeNames)
    local names
    if bank then
      names = {}
      for i = 0, bank.count - 1 do
        names[i + 1] = self:string(BANK.tradeNames, i)
      end
    end
    trades = arc and Gen4Trades.all(arc, names) or nil
    if trades then
      trades.source = ("ROM:%s (%d records of %d bytes) + bank %d")
        :format(Gen4Trades.PATH, #trades, Gen4Trades.RECORD_BYTES,
                BANK.tradeNames)
    end
  end
  self.tradeReport = { trades = trades and #trades or 0 }

  self:write("constants", {
    gen4HoneyEncounters = require('src.world.Gen4HoneyTrees').tables(self.rom),
    experienceTables = experienceTables,
    tmhmMoves = tmhmMoves,
    gen4Trades = trades,
    -- The one field seventy-one places read.
    gen = 4,
    generation = 4,
    badges = badges,
    martCommon = martCommon,
    martSpecialties = martSpecialties,
    gen4BerryGrowth = require('src.import.Gen4BerryData').growth(
      self:archiveAt(require('src.import.Gen4BerryData').PATH)),
    gen4BerryPositions = require('src.import.Gen4BerryData').positions(self.rom),
    gen4PoketchRoutes = require('src.import.Gen4PoketchMap').routes(self.rom),
    gen4PoketchCoin = require('src.import.Gen4PoketchSprites').coin(self:archiveAt('/graphic/poketch.narc')),
    gen4BerryInitial = require('src.import.Gen4BerryData').initial(self.rom),
    gen4PoketchMapCells = require('src.import.Gen4BerryData').mapCells(
      self:archiveAt('/graphic/poketch.narc')),
    gen4NewGame = newGame,
    -- THE DIALOGUE WINDOW, in the cartridge's own tiles.
    --
    -- Reported from play: *"the textbox should fit the bottom of the screen
    -- currently text is spilling outside of it"*.  It was the Game Boy's box
    -- -- `Theme`'s default of 20x6 tiles at row 12 -- with a DS font printing
    -- into it, because nothing ever told the theme otherwise.
    --
    -- `FieldMessage_AddWindow` (field_message.c) is the whole answer:
    --
    --     Window_Add(bgConfig, window, BG_LAYER_MAIN_3, 2, 19, 27, 4, 12, ...)
    --
    -- which is left 2, top 19, **27 tiles wide and 4 tall** -- the text
    -- INTERIOR, with the frame drawn round it by
    -- `Window_DrawMessageBoxWithScrollCursor`.  On a 32x24-tile screen that
    -- puts the interior at x 16..232, y 152..184.
    --
    -- Transcribed rather than read out of a file because it is a literal in
    -- code, the same as the camera table and the mart's stock; the citation is
    -- the check.
    gen4MessageWindow = {
      left = 2, top = 19, width = 27, height = 4,
      source = "ROM:FieldMessage_AddWindow, Window_Add(.., 2, 19, 27, 4, ..)",
    },
    -- ...AND THE SCREEN IT SITS AT THE BOTTOM OF.  A DS is 256x192, and the
    -- box above only makes sense on one.
    gen4Screen = { width = 256, height = 192 },
    gen4Shadow = shadow,
    types = types,
    typeCount = Gen4TypeChart.TYPE_COUNT,
    natures = natures,
    natureOrder = order(25),
    speciesOrder = order(508),
    moveOrder = order(471),
    itemOrder = order(446),
    trainerOrder = order(928),
    world = {
      -- A Gen 4 cell is sixteen pixels, and the map defs say so too.
      blockPx = 16,
      -- PLATINUM'S OWN STEP TIMINGS, AND THE PORT WAS USING GEN 1/2'S.
      --
      -- `MovementAction_InitWalk(mapObj, dir, distance, duration, ...)` is called
      -- once per speed in `unk_020655F4.c`, and every row multiplies out to the
      -- sixteen pixels of one cell:
      --
      --     FX32_CONST(0.5), 32    slower
      --     FX32_CONST(1),   16    slow
      --     FX32_CONST(2),    8    WALK NORMAL
      --     FX32_CONST(4),    4    walk fast
      --     FX32_CONST(8),    2    faster
      --     FX32_CONST(16),   1    instant
      --     FX32_CONST(4),    4    RUN            <- gMovementActionFuncs_Run*
      --
      -- so a Sinnoh walk is TWO pixels a frame over eight frames, not one over
      -- sixteen. The fallbacks in FieldDefaults are 16 and 8, which are Gen 1/2's
      -- numbers, and a Gen 4 cache that does not state its own inherits them --
      -- every step in Sinnoh was running at half the cartridge's pace.
      stepFrames = 8,
      -- ...and the run is the WALK-FAST row, four pixels over four frames.
      -- `MOVEMENT_ACTION_RUN_*` is a distinct action with an identical distance
      -- and duration to `MOVEMENT_ACTION_WALK_FAST_*`; the only argument that
      -- differs is the last one, which pret stores into a field it names
      -- `unused`. So the run is not a different SPEED from walk-fast, it is a
      -- different ANIMATION at the same speed.
      runStepFrames = 4,
    },
    source = ("ROM:Platinum (types bank %d, natures bank %d, type chart overlay %s)")
      :format(BANK.typeName, BANK.nature, tostring(parsed and parsed.overlay)),
  })

  self.constantsReport = {
    shadowRows = shadow and shadow.rows or 0,
    shadowOverlay = shadow and shadow.overlay or nil,
    shadowImage = shadow and shadow.image and shadow.image.path or nil,
    newGameFlags = newGame and #newGame.flags or 0,
    newGameVars = newGame and #newGame.vars or 0,
    martRows = martCommon and #martCommon or 0,
    martAt = martAt and (martAt - 1) or nil,
    martMatches = martHits or 0,
    badges = #badges,
    chartRows = parsed and #parsed.rows or 0,
    chartSections = parsed and parsed.sections or 0,
    chartOverlay = parsed and parsed.overlay or nil,
    types = Gen4TypeChart.TYPE_COUNT,
    natures = #natures,
  }
  return chart
end

-- ---------------------------------------------------------------------------
-- Overworld sprites
-- ---------------------------------------------------------------------------

-- The NPCs, which turn out not to need the 3D pipeline at all.
--
-- mmodel.narc reads as a wall: Gen 4's overworld is 3D, so the people in it
-- must be models, and models mean NSBMD.  They are not.  421 of its 470
-- members are BTX0 -- Nitro TEXTURE archives -- and only 24 are BMD0.  A Gen 4
-- NPC is a flat quad wearing a texture; the geometry is shared and the
-- per-character art is a texture set.  The member names say so outright
-- (`youngster.nsbtx`, `lass.nsbtx`, `hiker.nsbtx`).
--
-- So the whole overworld cast comes out by reading textures, and the mesh
-- work is not on the path to it.

-- The name an overworld sprite is filed under in `data.sprites`.
--
-- KEYED BY MEMBER, NOT BY graphicsId.  This file used to say the map defs'
-- `graphicsId` "indexes this archive" and key the table by it.  It does not
-- index this archive; it is a key into a lookup table in overlay 5, and the
-- difference is not academic -- ZERO of the 3,555 map objects were drawing
-- their own art.  See Gen4ObjectGfx.  The sprite table is therefore keyed by
-- the mmodel MEMBER, which is what actually identifies a picture, and the map
-- objects go through the table to get one.
function RomExtractorGen4.spriteKey(member)
  return ("SPRITE_G4_%03d"):format(member or 0)
end

-- The two pickup tables, read once each: the visible items out of their own
-- script file, the hidden ones out of the ARM9.  See Gen4Pickups for why they
-- cannot be read the same way.
function RomExtractorGen4:pickupTables()
  if self._pickups then return self._pickups.visible, self._pickups.hidden end
  local visible, hidden
  local scripts = self:archive("scripts")
  local names = scripts and Gen4Archives.names(PATH.scripts)
  if scripts and names then
    for index, name in ipairs(names) do
      if name == "scripts_visible_items" then
        visible = Gen4Pickups.visibleItems(scripts:get(index - 1), Gen4Script)
        break
      end
    end
  end
  -- The bound is the ITEM NAME BANK, not pl_item_data.narc: the data archive
  -- has 446 members and item ids run to at least 451, so using its count
  -- truncates the hidden-item run at 216 rows and loses 41 items silently.
  local nameBank = self:bank(BANK.item)
  hidden = Gen4Pickups.hiddenItems(self.rom and self.rom:arm9(),
                                   nameBank and nameBank.count or nil)
  self._pickups = { visible = visible, hidden = hidden }
  return visible, hidden
end

-- The graphicsId -> member table, read once from the cartridge.
function RomExtractorGen4:objectGfxTable()
  if self._objectGfx ~= nil then return self._objectGfx end
  local overlay = self.rom and self.rom:overlay(Gen4ObjectGfx.OVERLAY)
  local members = self:archive("overworld")
  local map = overlay and Gen4ObjectGfx.read(overlay, members and members.count or 470)
  self._objectGfx = map or false
  return self._objectGfx
end

-- The graphicsId -> fldeff member table, read once.  Separate from the sprite
-- table above because it is a DIFFERENT table naming a DIFFERENT archive, and
-- folding them together would lose which archive a member belongs to -- which
-- is the whole content of the answer.
function RomExtractorGen4:objectModelTable()
  if self._objectModels ~= nil then return self._objectModels end
  local overlay = self.rom and self.rom:overlay(Gen4ObjectGfx.OVERLAY)
  local map = overlay and Gen4ObjectGfx.readModels(overlay,
                                                   Gen4ObjectGfx.MODEL_MEMBERS)
  self._objectModels = map or false
  return self._objectModels
end

-- modelFor(graphicsId) -> fldeff member, or nil
function RomExtractorGen4:modelFor(graphicsId)
  local map = self:objectModelTable()
  return map and map[graphicsId] or nil
end

-- spriteFor(graphicsId) -> key, member, reason
-- `reason` is set when the id has no billboard of its own rather than when the
-- lookup failed; the two must not look alike in the index.
function RomExtractorGen4:spriteFor(graphicsId)
  local map = self:objectGfxTable()
  local member = map and map[graphicsId]
  if member then return RomExtractorGen4.spriteKey(member), member, nil end
  return nil, nil, Gen4ObjectGfx.reason(graphicsId) or "unmapped"
end

function RomExtractorGen4:extractOverworld()
  self:beginStage("overworld")

  local arc = self:archive("overworld")
  local index = { sprites = {}, skipped = {}, counts = {} }
  if not arc then
    self:write("gen4_overworld", index)
    return index
  end

  local names = Gen4Archives.names(PATH.overworld)
  local frames = 0

  for member = 0, arc.count - 1 do
    local bytes = arc:get(member)
    if bytes and Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end

    if bytes and bytes:sub(1, 4) == "BTX0" then
      local raw = names and names[member + 1] or ("sprite_%03d"):format(member)
      local label = raw:gsub("%.nsbtx$", ""):gsub("[^%w_]", "_")

      local sheet, report = Gen4Models.sheet(bytes)
      if sheet then
        local entry = self:saveImage("overworld/" .. label, sheet, {
          member = member,
          frames = sheet.frames,
          frameWidth = sheet.frameWidth,
          frameHeight = sheet.frameHeight,
          -- What the member held besides the character.  Recorded rather than
          -- dropped: a sprite set that suddenly stops reporting the slots it
          -- always had is a change worth seeing.
          otherSizes = report and report.otherSize or nil,
          undecodable = report and report.undecodable or nil,
        })
        if entry then
          index.sprites[label] = entry
          frames = frames + sheet.frames
          local key = ("%dx%d"):format(sheet.frameWidth, sheet.frameHeight)
          index.counts[key] = (index.counts[key] or 0) + 1
        end
      else
        -- A member whose textures are all a format this does not read, or
        -- whose modal size is far too large to be a person.  Named, so the
        -- gap is a list rather than a number.
        index.skipped[#index.skipped + 1] = {
          member = member, name = label,
          reason = report and (report.oversize and ("oversize " .. tostring(report.modal))
                               or "no decodable frames") or "not parsed",
        }
      end
    end
    self:tick("overworld", member + 1, arc.count)
  end

  -- WHICH OF A SHEET'S PICTURES FACES WHICH WAY.
  --
  -- Without this the renderer reads a Platinum sheet with the six fixed slots
  -- every earlier generation uses -- stand down, stand up, stand left, then
  -- their steps -- and a Platinum sheet is not in that order.  On a sixteen
  -- texture NPC the slot the renderer takes for "standing south" holds a BACK
  -- view and the one it takes for "stepping south" holds a LEFT view, so the
  -- character changes direction every step: reported, exactly, as spinning in
  -- circles while walking.
  --
  -- The real order is in this same archive -- see Gen4Facings -- and the
  -- twenty-five tables at its tail are read here once.
  local sequences, seqReport = Gen4Facings.read(arc)
  local facingsReport = { byName = 0, byCount = 0, none = 0,
                          sequences = seqReport }

  -- ...and the same sheets under the names src/render/SpriteRenderer.lua
  -- reads.  `data.sprites` is a flat map of key to sheet in every generation,
  -- and the fields are the ones a Gen 3 entry carries, because the renderer
  -- is generation-agnostic and a Gen 4 spelling would mean a branch wherever
  -- an NPC is drawn.
  --
  -- `trueColor` is true because these are real colours out of the cartridge's
  -- own palettes, not a four-shade Game Boy set the renderer has to map; it is
  -- what makes SpriteRenderer use the PNG as it is.  `walker` says the frames
  -- are a walk cycle rather than an arbitrary sequence, so it is false for the
  -- single-frame props -- the item ball, the cut tree, the boulder -- which
  -- have exactly one picture and nothing to step through.
  local sprites = {}
  for label, entry in pairs(index.sprites) do
    local key = RomExtractorGen4.spriteKey(entry.member)
    local facings, facingSource
    local seqName, how = Gen4Facings.sequenceFor(label, entry.frames)
    local seq = seqName and sequences[seqName] or nil
    if seq then
      local built, why = Gen4Facings.facings(seq, entry.frames)
      if built then
        facings = built
        facingSource = ("ROM:mmodel.narc[%d] (%s.bin)"):format(seq.member, seqName)
        if how == "name" then
          facingsReport.byName = facingsReport.byName + 1
        else
          facingsReport.byCount = facingsReport.byCount + 1
        end
      else
        facingsReport.none = facingsReport.none + 1
        facingsReport.refused = facingsReport.refused or {}
        facingsReport.refused[label] = why
      end
    else
      -- NOT A FAILURE.  A berry tree, an item ball, a boulder: two pictures or
      -- one, no sides, and nothing to face.  The renderer keeps its classic
      -- slots for these, which is exactly what they had before.
      facingsReport.none = facingsReport.none + 1
    end
    sprites[key] = {
      id = key,
      image = entry.path,
      frames = entry.frames,
      frameWidth = entry.frameWidth,
      frameHeight = entry.frameHeight,
      walker = (entry.frames or 1) > 1,
      trueColor = true,
      -- { stand, step, step } per side, in the sheet's own frame numbers.
      -- All four sides are real art: Platinum draws an east side of its own,
      -- so nothing here is the mirror of the west one.
      facings = facings,
      facingSource = facingSource,
      source = ("ROM:mmodel.narc[%d]"):format(entry.member),
    }
  end
  for label,entry in pairs(index.sprites) do
    if Gen4Facings.sequenceFor(label,entry.frames)=='walk_and_run' then
      local walk=sprites[RomExtractorGen4.spriteKey(entry.member)]
      local facings=Gen4Facings.cycles(sequences.walk_and_run,64)
      if facings then
        local id=walk.id..'_RUN';local run={}
        for k,v in pairs(walk) do run[k]=v end
        run.id=id;run.facings=facings;run.fullCycle=true
        sprites[id]=run;walk.run=id
      end
    end
  end
  index.facings = facingsReport
  self:write("gen4_overworld", index)
  self:write("sprites", sprites)

  self.overworldReport = {
    facings = facingsReport,
    frames = frames, skipped = #index.skipped, sprites = (function()
      local n = 0
      for _ in pairs(sprites) do n = n + 1 end
      return n
    end)(),
  }
  return index
end

-- Species battle pictures.
--
-- The rest of this file extracts things the engine had never seen; this stage
-- fills in the one gap that makes a battle screen possible at all, and it does
-- it by writing the SAME FIELDS Gen 3 writes.  `Sprites.path` reads
-- `def.spriteFront` and `def.spriteBack` off the species row for every
-- generation, and `PicAnim` reads `def.picAnim`; a Gen 4 spelling of either
-- would mean a generation branch in every screen that draws a Pokemon.
--
-- THE FILENAME CARRIES BOTH THE ID AND THE NAME.  Gen 3 names its files by
-- the species slug alone, which it can because a Gen 3 row is keyed by a
-- SPECIES_* constant.  A Gen 4 row is keyed by its integer id and the NAMES
-- COLLIDE -- Nidoran-f and Nidoran-m slug identically -- so a slug-only path
-- would have one species quietly overwrite another's picture.  "029_nidoran"
-- is unique by construction and still readable to whoever writes an override.
-- "029_nidoran" rather than "nidoran": see the stage below for why both
-- halves are needed.  Everything outside [a-z0-9] folds to an underscore and
-- runs collapse, so the two Nidoran, Mr. Mime, Farfetch'd, Ho-Oh and the
-- Porygon numerals all produce a path a filesystem will take.
function RomExtractorGen4.speciesSlug(species, def)
  local name = def and def.name
  if type(name) ~= "string" or name == "" then
    return ("%03d"):format(species)
  end
  local slug = name:lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if slug == "" then return ("%03d"):format(species) end
  return ("%03d_%s"):format(species, slug)
end

-- Alternate forms, the Substitute doll and the in-battle shadows.
--
-- Run from the same stage as the base pictures because it is the same decoder
-- on the same shape -- 20x10 tiles, encrypted, linear, two frames side by
-- side -- and differs only in where the numbers come from.  See Gen4Otherpoke
-- for why those numbers are a table rather than arithmetic.
function RomExtractorGen4:extractFormSprites(index, mons)
  local arc = self:archive("otherpoke")
  if not arc then return end

  local function sheetAt(member)
    if not member then return nil end
    local bytes = arc:get(member)
    if not bytes or #bytes == 0 then return nil end
    local info = Gen4Graphics.tiles(bytes)
    if not (info and info.tilesX and info.tilesY) then return nil end
    return {
      pixels = Gen4Graphics.decryptSprite(info.pixels),
      width = info.tilesX * 8, height = info.tilesY * 8,
    }
  end

  local written, borrowed = 0, 0

  for _, row in ipairs(Gen4Otherpoke.FORMS) do
    local normalMember, shinyMember, didBorrow = Gen4Otherpoke.palettes(row)
    if didBorrow then borrowed = borrowed + 1 end
    local normal = normalMember and Gen4Graphics.palette(arc:get(normalMember))
    local shiny = shinyMember and Gen4Graphics.palette(arc:get(shinyMember))
    local key = Gen4Otherpoke.key(row)
    local record = {
      species = row.species, name = row.name, form = row.form,
      borrowedPalette = didBorrow or nil,
    }

    for _, face in ipairs({ "front", "back" }) do
      local sheet = sheetAt(row[face])
      if sheet then
        for _, tone in ipairs({ { "", normal }, { "shiny_", shiny } }) do
          if tone[2] then
            local image = Gen4Pokegra.frame(sheet, tone[2], 1)
            local entry = image and self:saveImage(
              ("battle/forms/%s%s/%s"):format(tone[1], face, key), image,
              { species = row.species, form = row.form })
            if entry then
              record[tone[1] .. face] = entry.path
              written = written + 1
            end
          end
        end
        if face == "front" and normal then
          local strip = Gen4Pokegra.strip(sheet, normal)
          local entry = strip and self:saveImage(
            ("battle/forms/anim/%s"):format(key), strip,
            { species = row.species, form = row.form })
          if entry then
            record.picAnim = {
              sheet = entry.path, count = Gen4Pokegra.FRAMES,
              width = floor(entry.width / Gen4Pokegra.FRAMES),
              height = entry.height, play = GEN4_PIC_ANIM_PLAY,
              source = ("ROM:pl_otherpoke.narc[%d]"):format(row.front),
            }
            written = written + 1
            if shiny then
              local shinyStrip = Gen4Pokegra.strip(sheet, shiny)
              local shinyEntry = shinyStrip and self:saveImage(
                ("battle/forms/anim/shiny/%s"):format(key), shinyStrip,
                { species = row.species, form = row.form })
              if shinyEntry then
                record.picAnim.shinySheet = shinyEntry.path
                written = written + 1
              end
            end
          end
        end
      end
    end

    index.forms[key] = record

    -- ...and onto the species row, under the form name.  Additive: nothing
    -- reads `def.forms` yet, and the fields inside it are spelled exactly like
    -- the ones beside it, so whatever does read it needs no new vocabulary.
    local def = mons and mons[row.species]
    if def and row.species > 0 then
      def.forms = def.forms or {}
      def.forms[row.form] = record
    end
  end

  -- THE SUBSTITUTE DOLL AND THE SHADOWS, which are not a Pokemon and would
  -- have no row to sit on.  Both are wanted by any battle that runs: the doll
  -- the moment something uses Substitute, the shadow under every battler.
  local subSheet = sheetAt(Gen4Otherpoke.SUBSTITUTE.front)
  local subBack = sheetAt(Gen4Otherpoke.SUBSTITUTE.back)
  local subPalette = Gen4Graphics.palette(arc:get(Gen4Otherpoke.SUBSTITUTE.palette))
  local shadowSheet = sheetAt(Gen4Otherpoke.SHADOWS.sheet)
  local shadowPalette = Gen4Graphics.palette(arc:get(Gen4Otherpoke.SHADOWS.palette))

  index.extras = {}
  local function extra(name, sheet, palette)
    if not (sheet and palette) then return end
    local entry = self:saveImage("battle/" .. name, Gen4Pokegra.strip(sheet, palette))
    if entry then
      index.extras[name] = entry.path
      written = written + 1
    end
  end
  extra("substitute_front", subSheet, subPalette)
  extra("substitute_back", subBack, subPalette)
  extra("shadows", shadowSheet, shadowPalette)

  index.counts.formImages = written
  index.counts.forms = #Gen4Otherpoke.FORMS
  index.counts.borrowedPalettes = borrowed
end

-- THE FACE ACROSS THE FIELD FROM YOU.
--
-- Battles ran without one for as long as they ran at all:
-- `BattleState.trainerPicPath` reads `trainer.pic`, nothing wrote it, and
-- `getImage` answers nil on a nil path -- so every Sinnoh trainer fought you
-- as a name and a party with no portrait.
--
-- ONE PICTURE PER CLASS, NOT PER TRAINER.  trfgra is 105 members-of-five and
-- `generated/trainer_classes.txt` has 105 rows;
-- `SpriteSystem_SetTrainerClassGraphicsIndex(trainerClass, FACE_FRONT, ...)`
-- is what indexes it.  So every Youngster in the region shares one face, and
-- the path is stamped on every trainer row carrying that class -- which is
-- also why this stage rewrites `trainers` rather than writing a table of its
-- own for a reader to join.  Same shape as the species-sprite stage, which
-- rewrites `pokemon` for the same reason.
--
-- See `Gen4Trgra` for which of the archive's two NCGRs is readable without a
-- cell walk, why the pixels have to be decrypted first, and the measurement
-- that decides frame 1 is the picture.
function RomExtractorGen4:extractTrainerSprites()
  self:beginStage("trainer_sprites")

  local index = { classes = {}, missing = {}, counts = {} }
  local arc = self:archive("trainerFront")
  if not arc then
    self.trainerSpriteReport = { classes = 0, written = 0 }
    self:write("gen4_trainer_sprites", index)
    return index
  end

  local names = self:bank(BANK.trainerClass)
  local total = Gen4Trgra.classCount(arc)
  local written, animated, byClass = 0, 0, {}

  for class = 0, total - 1 do
    local sheet = Gen4Trgra.sheet(arc, Gen4Graphics, class)
    local palette = Gen4Trgra.palette(arc, Gen4Graphics, class)
    local name = nil
    if names and class < names.count then
      name = Gen4Text.render(Gen4Text.codes(names, class))
    end
    if not (sheet and palette) then
      index.missing[#index.missing + 1] = { class = class, name = name }
    else
      local frames = Gen4Trgra.framesUsed(sheet)
      if frames > 1 then animated = animated + 1 end
      local image = Gen4Trgra.frame(sheet, palette, 1)
      local entry = image and self:saveImage(
        ("battle/trainer/%s"):format(Gen4Trgra.slug(class, name)), image,
        { class = class, name = name, frames = frames })
      if entry then
        written = written + 1
        byClass[class] = entry.path
        index.classes[class] = entry
      end
    end
  end

  -- ...AND ONTO THE TRAINERS, which is the half that makes it visible.
  local stamped = 0
  for _, trainer in pairs(self._trainers or {}) do
    local path = trainer.class and byClass[trainer.class]
    if path then
      trainer.pic = path
      stamped = stamped + 1
    end
  end
  if stamped > 0 then self:write("trainers", self._trainers) end

  index.counts.classes = total
  index.counts.written = written
  -- Recorded, not emitted: 25 of the 105 sheets carry a real second frame and
  -- the other 80 leave it blank, so the strip is not the picture here the way
  -- it is for a species.  An animation stage can read this back.
  index.counts.twoFrame = animated
  index.counts.stamped = stamped
  self.trainerSpriteReport = { classes = total, written = written,
                               stamped = stamped, twoFrame = animated }
  self:write("gen4_trainer_sprites", index)
  return index
end

function RomExtractorGen4:extractSpeciesSprites()
  self:beginStage("species_sprites")

  local index = { species = {}, forms = {}, missing = {}, counts = {} }
  local arc = self:archive("pokegra")
  local mons = self._pokemon
  if not arc then
    self:write("gen4_species_sprites", index)
    return index
  end
  local heights = self:archive("pokeHeight")
  local total = Gen4Pokegra.speciesCount(arc)

  local written, fellBack, femaleSheets, animated = 0, 0, 0, 0

  for species = 1, total - 1 do
    local normal = Gen4Graphics.palette(arc:get(species * 6 + Gen4Pokegra.SLOT.normalPalette))
    local shiny = Gen4Graphics.palette(arc:get(species * 6 + Gen4Pokegra.SLOT.shinyPalette))
    local def = mons and mons[species]
    local record = { id = species }
    local slug = RomExtractorGen4.speciesSlug(species, def)

    for _, face in ipairs({ "front", "back" }) do
      local sheet, slot = Gen4Pokegra.sheet(arc, Gen4Graphics, species, face)
      if not sheet then
        index.missing[#index.missing + 1] = { species = species, face = face }
      else
        if slot == Gen4Pokegra.FACES[face].fallback then fellBack = fellBack + 1 end

        -- The still picture is frame 1 of the pair, in each palette.
        for _, tone in ipairs({ { "", normal }, { "shiny_", shiny } }) do
          local image = Gen4Pokegra.frame(sheet, tone[2], 1)
          local entry = image and self:saveImage(
            ("battle/%s%s/%s"):format(tone[1], face, slug), image,
            { species = species, face = face, slot = slot })
          if entry then
            written = written + 1
            record[tone[1] .. face] = entry.path
            if def then
              local key = (face == "front")
                and (tone[1] == "" and "spriteFront" or "spriteShiny")
                or (tone[1] == "" and "spriteBack" or "spriteShinyBack")
              def[key] = entry.path
            end
          end
        end

        -- ...and the two-frame strip, which needs no restacking because the
        -- cartridge already stores the pair side by side at exactly the pitch
        -- PicAnim cuts at.
        if face == "front" then
          local strip = Gen4Pokegra.strip(sheet, normal)
          local entry = strip and self:saveImage(
            ("battle/anim/%s"):format(slug), strip, { species = species })
          if entry and def then
            def.picAnim = {
              sheet = entry.path,
              count = Gen4Pokegra.FRAMES,
              width = floor(entry.width / Gen4Pokegra.FRAMES),
              height = entry.height,
              play = GEN4_PIC_ANIM_PLAY,
              source = ("ROM:pl_pokegra.narc[%d]"):format(species * 6 + slot),
            }
            local shinyStrip = Gen4Pokegra.strip(sheet, shiny)
            local shinyEntry = shinyStrip and self:saveImage(
              ("battle/anim/shiny/%s"):format(slug), shinyStrip,
              { species = species })
            -- A shiny that loses its colours for the two frames it is moving
            -- and gets them back when it settles is the Gen 3 bug this avoids:
            -- the cartridge loads ONE palette for the battler and draws every
            -- frame through it, so the strip is decoded twice here.
            if shinyEntry then def.picAnim.shinySheet = shinyEntry.path end
            animated = animated + 1
          end
          if entry then written = written + 1 end
        end

        -- The distinct female art, only where it IS distinct: 89 species,
        -- against 322 whose female member repeats the male byte for byte.
        if Gen4Pokegra.femaleDiffers(arc, species, face) then
          local femaleSheet = Gen4Pokegra.sheetAt(arc, Gen4Graphics, species,
            Gen4Pokegra.FACES[face].fallback)
          local image = femaleSheet and Gen4Pokegra.frame(femaleSheet, normal, 1)
          local entry = image and self:saveImage(
            ("battle/female_%s/%s"):format(face, slug), image,
            { species = species, face = face })
          if entry then
            record["female" .. face] = entry.path
            if def then
              def[(face == "front") and "spriteFrontFemale" or "spriteBackFemale"] = entry.path
            end
            femaleSheets = femaleSheets + 1
            written = written + 1
          end
        end
      end

      -- Where the picture SITS.  height.narc is four one-byte members per
      -- species in the same slot order as the sheets, and a missing entry is
      -- left nil rather than defaulted to 0 -- a real 0 and "no such sheet"
      -- mean different things to whatever places the sprite.
      local slotIndex = Gen4Pokegra.FACES[face].preferred
      local offset = Gen4Pokegra.offset(heights, species, slotIndex)
        or Gen4Pokegra.offset(heights, species, Gen4Pokegra.FACES[face].fallback)
      if offset then record[face .. "Offset"] = offset end
    end

    if next(record) and record.id then index.species[species] = record end
    self:tick("species_sprites", species, total)
  end

  index.counts = {
    images = written, viaFemaleSlot = fellBack,
    femaleVariants = femaleSheets, animated = animated,
  }
  self:extractFormSprites(index, mons)

  -- THE PARTY ICONS, which live in an archive of their own and had never been
  -- opened. See Gen4Icons for the archive's shape and for how the ramp table
  -- in the ARM9 is found -- and for the tie-break that finding it needs.
  index.icons = self:extractMonIcons()

  self:write("gen4_species_sprites", index)

  -- The species module is rewritten because the paths were stamped onto its
  -- own rows above.  extractSpecies has already run and self._pokemon IS the
  -- table it wrote, so this is the whole of the wiring.
  if mons then self:write("pokemon", mons) end

  self.speciesSpriteReport = index.counts
  self.speciesSpriteReport.missing = #index.missing
  return index
end


-- The height field, which is the half of "3D map" that is not art.
--
-- Everything else about a Gen 4 map treats it as a grid: the permission word
-- says what a tile IS, and that is enough to walk on a flat world.  It is not
-- enough for Sinnoh, where a bridge crosses a path and the two share an (x, z),
-- and where a slope rises between two tiles that are both "ground".  The BDHC
-- block in each land chunk is the cartridge's own answer and it is small,
-- self-checking and independent of the mesh, so it comes out now while the
-- NSBMD does not.
--
-- WHAT IT IS NOT: a walkability map.  Measured rather than assumed -- tiles the
-- permission grid calls void are covered by a plate 75.6% of the time and real
-- ground 72.3%, which is no correlation at all.  The two answer different
-- questions and neither can be derived from the other; where no plate covers a
-- point the game LEAVES THE HEIGHT ALONE (CalculateObjectHeight returns FALSE),
-- so plates are the exceptions rather than the surface.
function RomExtractorGen4:extractHeights()
  self:beginStage("heights")

  local land = self:archive("land")
  local index = { chunks = {}, counts = {}, failed = {} }
  if not land then
    self:write("gen4_map_heights", index)
    return index
  end

  local totals = { points = 0, normals = 0, constants = 0,
                   plates = 0, strips = 0, access = 0 }
  local parsed, empty = 0, 0

  for member = 0, land.count - 1 do
    local chunk = Gen4Maps.land(land:get(member))
    local block = chunk and chunk.bdhc
    if not block or #block == 0 then
      empty = empty + 1
    else
      local bdhc, why = Gen4Bdhc.parse(block)
      if not bdhc then
        index.failed[#index.failed + 1] = { member = member, reason = why }
      else
        parsed = parsed + 1
        for key in pairs(totals) do totals[key] = totals[key] + bdhc.counts[key] end
        -- Kept in the cartridge's own indexed shape rather than flattened into
        -- one rectangle per plate.  It is smaller, and it keeps the strip
        -- index, which is how the game narrows the search -- flattening would
        -- throw away the only structure here that is not derivable.
        index.chunks[member] = {
          points = bdhc.points, normals = bdhc.normals,
          constants = bdhc.constants, plates = bdhc.plates,
          strips = bdhc.strips, access = bdhc.access,
        }
      end
    end
    self:tick("heights", member + 1, land.count)
  end

  index.counts = totals
  index.counts.chunks = parsed
  index.counts.empty = empty
  index.counts.failed = #index.failed
  -- The units, stated once so no caller has to rediscover them: a land chunk
  -- is 32x32 tiles and its plate coordinates run -256..256, so a tile is 16
  -- world units and THE CHUNK IS CENTRED ON THE ORIGIN, not cornered at it.
  -- Tile (tx, tz) has its centre at ((tx + 0.5) * 16 - 256, (tz + 0.5) * 16 - 256).
  index.tileSize = Gen4Bdhc.TILE_UNITS
  index.chunkOrigin = -Gen4Bdhc.CHUNK_UNITS / 2

  self:write("gen4_map_heights", index)
  self.heightReport = index.counts
  return index
end


-- WHERE A NEW GAME STARTS.  The stage that stops Platinum opening in Red's
-- bedroom.
--
-- Data.lua's overlay is ADDITIVE: a module a version does not write resolves to
-- the ROOT cache, which is Red's.  `field.lua` used to be blocked from that for
-- a stated reason -- "field.lua is where boot.startMap and boot.screens live
-- ... which is how NEW GAME on Emerald opened Red's intro in Red's house" --
-- and it was unblocked when Gen 3 learned to write one.  Gen 4 did not, so the
-- first New Game on Platinum took `REDS_HOUSE_2F` and died in MapLoader.  The
-- fix is the one Gen 3 got.
--
-- `screens.newGame = false` is not decoration: Game.lua reads that key and, if
-- it is NIL rather than false, pushes "OakSpeech" for any non-Gen-2 version.
-- Platinum's opening is Rowan's, not Oak's, and neither is built -- so the
-- honest value is an explicit false, which means "this version has no new-game
-- screen", not "nobody said".
function RomExtractorGen4:extractField()
  self:beginStage("field")

  local headers = self._mapHeaders
  local maps = self._mapDefs
  local start, respawn, at, spawns, spawnAt =
    Gen4Field.find(self.rom and self.rom:arm9(), headers, maps,
                   headers and self._mapHeaderCount or nil)

  local out = { source = "ROM:Platinum" }
  if not start then
    -- Reported rather than guessed.  A field table with an invented start map
    -- is worse than none: it boots, walks into a map that is not there, and
    -- looks like a map bug rather than a missing table.
    out.error = tostring(respawn)
    self:write("field", out)
    self.fieldReport = { found = false, reason = out.error }
    return out
  end

  local function nameFor(id)
    local header = headers and headers[id]
    return header and header.internalName or nil
  end

  local startMap = nameFor(start.mapHeaderID)
  local healMap = nameFor(spawns[1].blackOutMap)

  out.boot = {
    startMap = startMap,
    startX = start.x, startY = start.z,
    startFacing = start.facing,
    -- Where a blackout sends you before you have seen a Pokemon Centre: the
    -- first spawn row's BLACKOUT half, which is the player's own ground floor.
    lastHeal = healMap and { map = healMap, x = spawns[1].blackOutX,
                             y = spawns[1].blackOutZ } or nil,
    -- THE BOOT SCREENS, NAMED HERE BECAUSE NOBODY ELSE CAN NAME THEM.
    --
    -- Data.lua seeds a default for each of these and then overrides the ones
    -- it still recognises as the default -- Gen 2 takes Gen2Intro, Gen 3 takes
    -- Gen3Title, and a Gen 4 cache that named none of them would keep RED'S.
    -- Writing them outright is also what makes them stick: every override in
    -- seedDefaults is guarded by `== BOOT_DEFAULTS.screens.x`, so a value this
    -- stage states is left alone by all of them.
    --
    -- `newGame = false` is deliberate and is not a gap.  OakSpeech replays a
    -- professor's intro out of text Platinum does not have; Platinum's own
    -- opening is Rowan's, which is a scripted scene on the intro map rather
    -- than a screen, so there is nothing to push here.
    screens = {
      splash = "Gen4Intro",
      title = "Gen4Title",
      -- WAS `false`, AND THAT WAS THE WHOLE OF "NEW GAME HAS NO INTRO".
      -- OakSpeech replays a professor's intro out of text Platinum does not
      -- have, so there was nothing to put here and the game opened straight
      -- into the bedroom.  There is something now: the `intro` stage extracts
      -- the television broadcast and Rowan's script, and Gen4RowanIntro plays
      -- them.
      newGame = "Gen4RowanIntro",
      -- Named for the same reason as the two above: left at the default this
      -- resolves to the Game Boy OPTION screen, whose rows are Gen 1's and
      -- whose FRAME row cannot reach Platinum's twenty message boxes.
      options = "Gen4Options",
    },
  }

  -- The fly and blackout destinations, named rather than numbered, because a
  -- header id means nothing to the code that will eventually draw a town map.
  out.healLocations = {}
  for index, row in ipairs(spawns) do
    out.healLocations[index] = {
      index = index - 1,
      blackOut = { map = nameFor(row.blackOutMap), header = row.blackOutMap,
                   x = row.blackOutX, y = row.blackOutZ },
      fly = { map = nameFor(row.flyMap), header = row.flyMap,
              x = row.flyX, y = row.flyZ },
      isWarpPos = row.isWarpPos == 1,
      unlockOnMapEntry = row.unlockOnMapEntry == 1,
      firstArrival = row.firstArrival,
    }
  end

  -- THE PLAYER'S OWN SHEETS, WHICH ARE NOT AN NPC'S.
  --
  -- Reported from play, and visible in one line of the log: `player sheet:
  -- SPRITE_RED -> ninja_boy`.  With no `field.playerSprites` the avatar falls
  -- back to a GAME BOY sprite id, which a Gen 4 cache resolves through its own
  -- sprite table to whatever happens to sit there -- `ninja_boy` is mmodel
  -- member 1 and the player is member 0, so the hero walked Sinnoh as a
  -- passer-by and nothing reported an error.
  --
  -- Found by NAME rather than by graphics id.  `player_m` and `player_f` are
  -- what the object-graphics table calls them, and a name cannot be off by one
  -- the way an id can -- which is exactly the mistake this is fixing.
  out.playerSprites, out.playerForms = self:playerSheets()

  out.source = ("ROM:Platinum (locations arm9+0x%X, spawns arm9+0x%X)")
    :format(at, spawnAt)
  self:write("field", out)
  self.fieldReport = {
    found = true, startMap = startMap, startX = start.x, startY = start.z,
    facing = start.facing, healLocations = #spawns,
  }
  return out
end

-- ---------------------------------------------------------------------------
-- The main menu
-- ---------------------------------------------------------------------------

-- What the title screen and the main menu need that is not a picture: the
-- words, the layout and the two colours.
--
-- The pictures are already written -- the graphics stage composes titledemo
-- into `gen4_graphics.screens` under `title/...` -- so this stage's job is to
-- say which of them is which, and to hand over the strings in the cartridge's
-- own words rather than in English this file typed out.
--
-- THE STRINGS ARE READ, NOT ASSUMED.  Bank 550 is stated in Gen4Menus and
-- checked here: if entry 0 does not come back as something, the record says so
-- rather than shipping a menu whose rows are blank.
function RomExtractorGen4:extractMenus()
  self:beginStage("menus")

  local out = {
    bank = BANK.mainMenu,
    layout = Gen4Menus.LAYOUT,
    colors = {
      background = Gen4Menus.rgb(Gen4Menus.COLORS.background),
      unfocused = Gen4Menus.rgb(Gen4Menus.COLORS.unfocused),
    },
    source = ("ROM:Platinum (bank %d, titledemo.narc)"):format(BANK.mainMenu),
  }

  local text = {}
  for key, index in pairs(Gen4Menus.TEXT) do
    text[key] = self:string(BANK.mainMenu, index)
  end
  out.text = text

  -- The rows this port offers, each already carrying its own words so the
  -- screen has no bank lookup to do and no English of its own to fall back on.
  out.rows = {}
  for _, row in ipairs(Gen4Menus.ROWS) do
    out.rows[#out.rows + 1] = {
      id = row.id,
      lines = row.lines,
      label = (row.text and self:string(BANK.mainMenu, row.text))
        or row.fallback,
      -- Whether the cartridge has this row at all.  OPTION does not exist on
      -- Platinum's main menu and is this engine's addition; saying so here is
      -- cheaper than a reader later mistaking it for extracted data.
      fromCartridge = row.fromCartridge,
    }
  end

  out.continueRows = {}
  for _, row in ipairs(Gen4Menus.CONTINUE_ROWS) do
    out.continueRows[#out.continueRows + 1] = {
      label = self:string(BANK.mainMenu, row.label),
      value = row.value,
      needsPokedex = row.needsPokedex or nil,
    }
  end

  -- The warning NEW GAME arms when a save already exists, in the cartridge's
  -- own wording.
  out.newGameWarning = self:string(BANK.mainMenuAlert, Gen4Menus.ALERT_NEW_GAME)

  -- THE POKETCH.  The order is one bank's and the names are another's, and
  -- the pairing is checked rather than assumed: every coloured name must open
  -- exactly one description in the ordered bank.
  local names = {}
  for i = 0, Gen4Menus.POKETCH_COUNT - 1 do
    local text = self:string(BANK.poketchName, Gen4Menus.POKETCH_NAME_FIRST + i)
    local name = Gen4Menus.poketchName(text)
    if name then names[#names + 1] = name end
  end
  out.poketch = {
    descBank = BANK.poketchDesc, nameBank = BANK.poketchName,
    border = Gen4Menus.POKETCH_BORDER,
    unavailable = Gen4Menus.POKETCH_UNAVAILABLE,
    digits = Gen4Menus.POKETCH_DIGITS,
    apps = {}, unpaired = {},
  }
  -- THE LONGEST NAME THE DESCRIPTION CONTAINS, not the one it starts with.
  --
  -- Matching on the opening "The <name>" paired twenty-four of the
  -- twenty-five and left the Calendar out, because its description is the one
  -- that does not begin that way: "Use the monthly Calendar to make a note of
  -- important dates."  Matching anywhere instead needs LONGEST, because
  -- "Counter" occurs inside "Trainer Counter" -- and then the twenty-five
  -- assignments have to be a permutation, which is the check that says the
  -- looser match did not fold two apps onto one name.
  local used = {}
  for i = 0, Gen4Menus.POKETCH_COUNT - 1 do
    local description = self:string(BANK.poketchDesc, Gen4Menus.POKETCH_DESC_FIRST + i)
    local found = nil
    for _, name in ipairs(names) do
      if type(description) == "string" and description:find(name, 1, true) then
        if not found or #name > #found then found = name end
      end
    end
    if not found or used[found] then
      out.poketch.unpaired[#out.poketch.unpaired + 1] = i
    end
    if found then used[found] = true end
    out.poketch.apps[i + 1] = {
      id = i,
      name = found,
      description = description,
      art = found and Gen4Menus.POKETCH_ART[found] or nil,
      live = found and Gen4Menus.POKETCH_LIVE[found] or nil,
    }
  end

  -- THE SUMMARY PAGES.  Every word on them, and the rows they sit in.
  out.summary = { bank = BANK.summary, layout = Gen4Menus.SUMMARY_LAYOUT,
                  pages = {}, text = {}, natures = {}, characteristics = {} }
  for key, index in pairs(Gen4Menus.SUMMARY_TEXT) do
    out.summary.text[key] = self:string(BANK.summary, index)
  end
  for i = 0, Gen4Menus.SUMMARY_NATURES - 1 do
    out.summary.natures[i + 1] =
      self:string(BANK.summary, Gen4Menus.SUMMARY_NATURE_FIRST + i)
  end
  for i = 0, Gen4Menus.SUMMARY_CHARACTERISTICS - 1 do
    out.summary.characteristics[i + 1] =
      self:string(BANK.summary, Gen4Menus.SUMMARY_CHARACTERISTIC_FIRST + i)
  end
  for i, page in ipairs(Gen4Menus.SUMMARY_PAGES) do
    out.summary.pages[i] = {
      key = page.key, art = page.art,
      title = self:string(BANK.summary, Gen4Menus.SUMMARY_TEXT[page.title]),
    }
  end

  -- THE PARTY SCREEN'S WORDS.  Bank 453, and the screen reads nothing else --
  -- no English of its own, which is the rule every other Gen 4 screen here
  -- follows.  See Gen4Menus.PARTY_BANK for how the bank was identified.
  out.partyMenu = { bank = BANK.partyMenu, text = {}, order = {} }
  for key, index in pairs(Gen4Menus.PARTY_TEXT) do
    out.partyMenu.text[key] = self:string(BANK.partyMenu, index)
  end
  for i = 1, Gen4Menus.PARTY_ORDER_WORDS do
    out.partyMenu.order[i] =
      self:string(BANK.partyMenu, Gen4Menus.PARTY_ORDER_FIRST + i - 1)
  end

  -- THE BAG.  Eight pocket names and where the screen puts things; the art
  -- itself is already in `gen4_graphics.screens` under `bag/`.
  out.bag = { bank = BANK.bagPockets, pockets = {},
              layout = Gen4Menus.BAG_LAYOUT,
              icon = Gen4Menus.BAG_ICON,
              iconCell = Gen4Menus.BAG_ICON_CELL,
              iconStride = Gen4Menus.BAG_ICON_STRIDE }
  for i = 0, Gen4Menus.BAG_POCKETS - 1 do
    out.bag.pockets[i + 1] = self:string(BANK.bagPockets, i)
  end

  -- THE OPTIONS SCREEN, in the cartridge's words and the cartridge's order.
  --
  -- The order is the point.  Platinum lists STEREO before MONO and Emerald
  -- lists MONO before STEREO, so a screen that reused the Gen 3 row would show
  -- the right two words, store the wrong one, and look entirely correct doing
  -- it.  What is written here is the enum order out of the cartridge, row by
  -- row, with each row's own description line beside it.
  out.options = { bank = BANK.options,
                  title = self:string(BANK.options, Gen4Menus.OPTIONS_TITLE),
                  rows = {} }
  for _, row in ipairs(Gen4Menus.OPTION_ROWS) do
    local values
    if row.values == "frames" then
      values = {}
      for index = Gen4Menus.FRAME_FIRST, Gen4Menus.FRAME_LAST do
        values[#values + 1] = self:string(BANK.options, index)
      end
    elseif type(row.values) == "table" then
      values = {}
      for _, index in ipairs(row.values) do
        values[#values + 1] = self:string(BANK.options, index)
      end
    end
    out.options.rows[#out.options.rows + 1] = {
      key = row.key,
      label = self:string(BANK.options, row.label),
      values = values,
      description = row.description
        and self:string(BANK.options, row.description) or nil,
    }
  end
  -- CHOOSING A STARTER, in the cartridge's words and its own order.
  --
  -- The species ids come from `choose_starter_app.c`, the offer lines from
  -- bank 360, and the ball models from ev_pokeselect -- three separate lists
  -- that have to agree.  They are checked against each other here: the species
  -- the id names must be the one the offer line is about, or the record says
  -- so rather than shipping a briefcase that hands over the wrong Pokemon.
  out.starter = { bank = BANK.starter, rows = {},
    intro = self:string(BANK.starter, Gen4Menus.STARTER_TEXT.theseArePokeBalls),
    choose = self:string(BANK.starter, Gen4Menus.STARTER_TEXT.nowChoose) }
  for _, row in ipairs(Gen4Menus.STARTERS) do
    local name = self:string(BANK.species, row.species)
    out.starter.rows[#out.starter.rows + 1] = {
      species = row.species,
      name = name,
      model = row.model,
      offer = self:string(BANK.starter, row.text),
      -- Set only when the species id and the name bank disagree with what the
      -- cartridge's own source says this slot holds.  Nothing should ever read
      -- it; it exists so that if the three lists ever drift, the drift is in
      -- the data rather than in somebody's memory.
      mismatch = (name ~= row.expect) and
        ("expected %s, species %d is %s"):format(row.expect, row.species,
                                                 tostring(name)) or nil,
    }
  end

  -- Extracted and not offered as a row; see Gen4Menus.OPTIONS_CONFIRM for why.
  out.options.confirm = {
    label = self:string(BANK.options, Gen4Menus.OPTIONS_CONFIRM.label),
    dialog = self:string(BANK.options, Gen4Menus.OPTIONS_CONFIRM.dialog),
    yes = self:string(BANK.options, Gen4Menus.OPTIONS_CONFIRM.yes),
    no = self:string(BANK.options, Gen4Menus.OPTIONS_CONFIRM.no),
  }

  -- The title sequence's pictures, by role.  The paths are what the graphics
  -- stage already wrote; naming them here means the title screen does not have
  -- to know what an archive member is called.
  --
  -- AND WITH EACH ONE, WHERE ITS ARTWORK ACTUALLY IS.  Every sheet here is
  -- 256x192 or 256x256 and most of it is empty: the logo's artwork occupies
  -- rows 27 to 148 of its own sheet, the copyright's four lines rows 64 to 119.
  -- A screen that draws these at 0,0 and trusts the sheet size puts the logo
  -- forty rows lower than it belongs and clips "VERSION" off the bottom -- which
  -- it did, and it looked like a layout choice rather than a measurement that
  -- was never taken.  So the box is measured here, off the composed pixels, and
  -- the screen positions by it.
  local screens = (self._graphicsIndex or {}).screens or {}
  local titleJobs = Gen4Screens.plan(PATH.title, { tilesWide = 8 }) or {}
  local titleArc = self:archiveAt(PATH.title)
  local boxes = {}
  for _, job in ipairs(titleJobs) do
    local image = titleArc and self:composeJob(titleArc, job)
    boxes[job.name] = image and contentBox(image) or nil
  end
  local function art(name, role)
    local entry = screens["title/" .. name]
    if not entry then return nil end
    return { path = entry.path, width = entry.width, height = entry.height,
             content = boxes[name], role = role }
  end
  -- ------------------------------------------------------- the start menu --
  -- The other half of the original brief, and the words for it.  The port
  -- decides WHERE to draw this; the cartridge decides what it says, which row
  -- comes first and which icon belongs to which row.
  out.startMenu = {
    bank = BANK.startMenu,
    layout = Gen4Menus.START_LAYOUT,
    icons = Gen4Menus.START_ICONS,
    rows = {},
  }
  for _, row in ipairs(Gen4Menus.START_ROWS) do
    out.startMenu.rows[#out.startMenu.rows + 1] = {
      id = row.id,
      label = self:string(BANK.startMenu, row.text),
      icon = row.icon,
      femaleIcon = row.femaleIcon,
      hidden = row.hidden,
      playerName = row.playerName,
    }
  end

  out.title = {
    logo = art("logo", "logo"),
    logoJP = art("logo_jp", "logo"),
    copyright = art("copyright", "copyright"),
    presents = art("gf_presents", "card"),
    topBorder = art("top_screen_border", "field"),
    bottomBorder = art("bottom_screen_border", "field"),
  }
  -- The centrepiece is a 3D model (giratina.nsbmd) and there is no 3D path
  -- yet, so the title screen shows the logo over the border rather than over
  -- Giratina.  Recorded rather than left to be rediscovered as a bug.
  out.title.missing = { "giratina.nsbmd (the animated centrepiece)" }

  self:write("gen4_menus", out)
  self.menusReport = {
    rows = #out.rows,
    continueRows = #out.continueRows,
    haveContinue = text.continue ~= nil,
    optionRows = #out.options.rows,
    art = (out.title.logo and 1 or 0) + (out.title.copyright and 1 or 0)
      + (out.title.presents and 1 or 0) + (out.title.topBorder and 1 or 0),
    logoBox = out.title.logo and out.title.logo.content or nil,
  }
  return out
end

-- ---------------------------------------------------------------------------
-- The opening: the television, and Rowan
-- ---------------------------------------------------------------------------

-- THE CRIES, which is the first sound this cartridge has made in this port.
--
-- Platinum's audio is an SDAT -- sequences over banks over wave archives --
-- and playing the MUSIC means writing a synthesiser.  The cries are not that,
-- and the difference is worth stating because it is what makes this a stage
-- rather than a project: 493 of 493 species' banks point at wave archive INDEX
-- == the species id, every one of those archives holds exactly one sample, and
-- every one of those samples is PCM8.  One 8-bit recording each, at 10512 Hz
-- for 388 of them and 13379 Hz for the other 105.
--
-- THE INDEX IS THE SPECIES AND THE NAME IS NOT.  See `Gen4Sdat` for the trap
-- in full: the archives are NAMED PV001..PV518 with a 25-wide hole that looks
-- exactly like a relocated block and is not.  Reading the names would have
-- given 25 species the wrong cry; reading the indices gives all 493 the right
-- one, and the cartridge's own `Sound_PlayPokemonCry` agrees.
function RomExtractorGen4:extractCries()
  self:beginStage("cries")

  local raw = self.rom and self.rom:read(Gen4Sdat.PATH)
  local sdat = raw and Gen4Sdat.open(raw)
  if not sdat then
    self.cryReport = { written = 0, reason = "no SDAT" }
    return nil
  end

  local cries, written, skipped = {}, 0, 0
  -- The national dex, which is where the cries stop.  The bank table runs to
  -- 771 and the entries past the species are music and effects, so the loop is
  -- bounded by what a species IS rather than by how many banks exist -- and
  -- every one of the 493 is checked for a PCM8 sample anyway, so a bank that
  -- turned out not to be a cry would be skipped rather than written wrong.
  local SPECIES = 493
  for species = 1, SPECIES do
    local bank = Gen4Sdat.bank(sdat, species)
    local index = bank and bank.waves and bank.waves[1]
    -- The bank's own pointer, not the species id twice: they agree on all 493
    -- here, and a cartridge where they did not is one where following the
    -- pointer is right and assuming is wrong.
    local list = index and Gen4Sdat.samples(sdat, index)
    local sample = list and list[1]
    local wav = sample and Gen4Sdat.wav(sdat, sample)
    local name = self:string(BANK.species, species)
    if wav and name and name ~= "" then
      local path = self:saveBinary(("cries/%03d.wav"):format(species), wav)
      if path then
        -- Keyed by the species NAME, because `Sound.playCry` is -- the same
        -- table Gen 1, 2 and 3 fill, so nothing in the engine needs a Gen 4
        -- branch to make a sound.
        cries[name] = { file = path, seconds = sample.bytes / math.max(1, sample.rate) }
        written = written + 1
      end
    else
      skipped = skipped + 1
    end
  end

  if written > 0 then
    local audio = require("src.import.Gen4Audio").catalogue(sdat, self._mapHeaders)
    audio.cries = cries
    audio.ndsArchive = self:saveBinary("sound/pl_sound_data.sdat", raw)
    audio.source = ("ROM:Platinum (%s)"):format(Gen4Sdat.PATH)
    self:write("audio", audio)
  end
  self.cryReport = { written = written, skipped = skipped }
  return cries
end

-- ---------------------------------------------------------------------------

-- THE POKEDEX'S ENTRY PAGE, composed out of FOUR tilemaps into one picture.
--
-- The graphics stage already wrote `pokedex/info_main` and its three
-- companions and every one of them is blank, because that stage pairs a
-- tilemap with the tiles and palette that SHARE ITS NAME and in this archive
-- nothing does.  See `Gen4Dex` for the pairing, where it comes from, and the
-- three independent ways it is checked.
--
-- This stage does not replace that one.  It adds the composition the planner
-- cannot express -- several tilemaps stamped into one grid over one sheet --
-- and leaves the per-member pictures alone, so nothing that reads them today
-- changes.
function RomExtractorGen4:extractDex()
  self:beginStage("dex")

  local out = {
    layout = Gen4Dex.LAYOUT,
    orders = Gen4Dex.orders(self.rom),
    source = ("ROM:Platinum (%s)"):format(Gen4Dex.PATH),
  }

  local arc = self:archive("dex")
  local function member(name)
    local index = Gen4Archives.find(Gen4Dex.PATH, name)
    if not (arc and index) then return nil end
    local bytes = arc:get(index)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end

  local paletteBytes = member(Gen4Dex.PALETTE)
  local listPalette = member("background_scroll_sinnoh.NCLR")
  local listTiles = member("scroll_main_background.NCGR.lz")
  local listMap = member("scroll_main_background.NSCR.lz")
  if listPalette and listTiles and listMap then
    out.list = self:saveImage("dex/list_page", Gen4Graphics.compose(
      Gen4Graphics.tilemap(listMap), Gen4Graphics.tiles(listTiles),
      Gen4Graphics.paletteAtSlot(Gen4Graphics.palette(listPalette), 5)))
  end
  local palette = paletteBytes and Gen4Graphics.palette(paletteBytes)
  local tilesBytes = member(Gen4Dex.TILES)
  local sheet = tilesBytes and Gen4Graphics.tiles(tilesBytes)

  if palette and sheet then
    -- The entry page.  The first layer IS the screen, so it is the canvas;
    -- a blank one is built anyway and stamped, because relying on the first
    -- layer being full size is an invariant that is only almost true.
    local canvas = Gen4Graphics.canvas(Gen4Dex.SCREEN_TILES_W,
                                       Gen4Dex.SCREEN_TILES_H)
    local stamped = 0
    for _, layer in ipairs(Gen4Dex.ENTRY_LAYERS) do
      local bytes = member(layer.name)
      local map = bytes and Gen4Graphics.tilemap(bytes)
      if map then
        Gen4Graphics.stamp(canvas, map, layer.x, layer.y)
        stamped = stamped + 1
      else
        -- Recorded rather than warned: this file has no logger, and a stage
        -- that quietly composes three of four panels is exactly the failure
        -- this whole section exists because of.
        out.missing = out.missing or {}
        out.missing[#out.missing + 1] = layer.name
      end
    end
    if stamped > 0 then
      out.entry = self:saveImage("dex/entry_page",
                                 Gen4Graphics.compose(canvas, sheet, palette),
                                 { layers = stamped })
    end

    -- The banner, which the app draws on its own layer over the page.
    local bannerBytes = member(Gen4Dex.BANNER_MAP)
    local bannerMap = bannerBytes and Gen4Graphics.tilemap(bannerBytes)
    if bannerMap then
      out.banner = self:saveImage("dex/banner",
                                  Gen4Graphics.compose(bannerMap, sheet, palette))
    end
  else
    out.missing = out.missing or {}
    out.missing[#out.missing + 1] =
      (not palette and Gen4Dex.PALETTE or Gen4Dex.TILES)
  end

  -- ------------------------------------------------------- the words -----
  -- HEIGHT, WEIGHT AND CATEGORY ARE STRINGS, one per species, already
  -- formatted by the cartridge ("2'04\"", "15.2 lbs.", "Seed Pokemon").  The
  -- species table carries none of the three, so a page drawn without them has
  -- three empty boxes on it -- which is what the art has slots for.
  out.words = {
    height = self:string(BANK.pokedex, Gen4Dex.LABEL.height),
    weight = self:string(BANK.pokedex, Gen4Dex.LABEL.weight),
    seen = self:string(BANK.pokedex, Gen4Dex.LABEL.seen),
    obtained = self:string(BANK.pokedex, Gen4Dex.LABEL.obtained),
    search = self:string(BANK.pokedex, Gen4Dex.LABEL.search),
    switch = self:string(BANK.pokedex, Gen4Dex.LABEL.switch),
  }
  -- Preserve the whole small label bank for native search descriptions,
  -- capitalization and order/name/type labels rather than port-written text.
  out.labels={}
  local labelBank=self:bank(BANK.pokedex)
  if labelBank then
    for i=0,labelBank.count-1 do out.labels[i]=self:string(BANK.pokedex,i) end
  end
  out.height, out.weight, out.category = {}, {}, {}
  -- InfoMain substitutes SPECIES_NONE for seen-but-not-caught details.
  out.height[0] = self:string(BANK.dexHeight, 0)
  out.weight[0] = self:string(BANK.dexWeight, 0)
  out.category[0] = self:string(BANK.dexCategory, 0)
  out.unknownEntry = self:string(BANK.dexEntry, 0)
  local species = 0
  for index = 1, Gen4Dex.MAX_SPECIES do
    local height = self:string(BANK.dexHeight, index)
    local weight = self:string(BANK.dexWeight, index)
    local category = self:string(BANK.dexCategory, index)
    if height then out.height[index] = height end
    if weight then out.weight[index] = weight end
    if category then out.category[index] = category end
    if height or weight or category then species = index end
  end

  self:write("gen4_dex", out)
  self.dexReport = {
    species = species,
    entry = out.entry ~= nil,
    banner = out.banner ~= nil,
    layers = out.entry and out.entry.layers or 0,
    missing = out.missing and #out.missing or 0,
  }
  return out
end

-- ---------------------------------------------------------------------------

-- THE KEYBOARD'S OWN ART, which the port has been drawing around rather than
-- drawing.  Reported from play: the naming screen "still needs a lot of work
-- before it matches the platinum rom".  `/data/namein.narc` is where it lives
-- and nothing had opened it; see `Gen4Naming` for every index and why it is
-- checked twice.
--
-- FIVE PICTURES AND SIXTEEN COLOURS.  The backdrop and the four keyboard
-- panels are ordinary tiles-plus-tilemap compositions; the colours are the
-- window's own palette row, carried through because the keyboard's
-- CHECKERBOARD is painted by code at run time rather than stored in the
-- tilemap.  Extracting the pictures alone would have produced a frame with
-- nothing inside it.
function RomExtractorGen4:extractNaming()
  self:beginStage("naming")

  local out = {
    panels = {}, colours = {},
    bgColour = Gen4Naming.BG_COLOUR,
    altColour = Gen4Naming.ALT_COLOUR,
    source = ("ROM:Platinum (%s)"):format(Gen4Naming.PATH),
  }

  local arc = self:archive("naming")
  if arc then
    local palette = self:paletteMember(arc, Gen4Naming.PALETTE)

    local background = palette and self:composeWith(arc, Gen4Naming.TILES,
                                                   Gen4Naming.BACKGROUND_MAP,
                                                   palette)
    out.background = self:saveImage("naming/background", background, {
      tiles = Gen4Naming.TILES, tilemap = Gen4Naming.BACKGROUND_MAP,
    })

    for page, member in ipairs(Gen4Naming.PANEL_MAPS) do
      local image = palette
        and self:composeWith(arc, Gen4Naming.TILES, member, palette)
      local entry = self:saveImage(("naming/panel_%d"):format(page - 1), image, {
        tiles = Gen4Naming.TILES, tilemap = member, page = page - 1,
      })
      if entry then out.panels[page] = entry end
    end

    -- The window's palette row, as floats, because the two colours the
    -- checkerboard is painted in are INDICES into it and nothing else in the
    -- cache can resolve them.  Sixteen of them, one-based, so index c of the
    -- cartridge's tables is `colours[c + 1]` and the off-by-one is spelled out
    -- here rather than repeated at every use.
    if palette then
      local first = Gen4Naming.WINDOW_PALETTE_ROW * 16
      for c = 0, 15 do
        local rgb = palette[first + c + 1]
        if rgb then
          out.colours[c + 1] = { rgb[1] / 255, rgb[2] / 255, rgb[3] / 255 }
        end
      end
    end
  end

  self:write("gen4_naming", out)

  local panels = 0
  for _ in pairs(out.panels) do panels = panels + 1 end
  self.namingReport = {
    panels = panels,
    background = out.background ~= nil,
    colours = #out.colours,
  }
  return out
end

-- ---------------------------------------------------------------------------

-- What a NEW GAME on Platinum actually opens with, which until now was
-- nothing: a news broadcast on a television, then Professor Rowan asking who
-- you are.  Both live in archives with NO NAME TABLE, so this stage cannot go
-- through the generic screen planner and every member index comes out of
-- Gen4IntroScene, where it is transcribed from the cartridge's own loaders.
--
-- EVERY PICTURE IS COMPOSED AND THEN LOOKED AT, because a wrong member index
-- here does not fail: it decodes, it composes, and it writes a picture.  The
-- television is the case in point -- composed with the palette its first load
-- names, the broadcast is a black rectangle with coloured noise in it.
function RomExtractorGen4:extractIntro()
  self:beginStage("intro")

  local out = {
    text = {}, tv = {}, backdrops = {}, figures = {}, ball = {},
    source = ("ROM:Platinum (banks %d/%d, %s, %s)"):format(
      BANK.rowanIntro, BANK.rowanIntroTv,
      Gen4IntroScene.PATH, Gen4IntroScene.TV_PATH),
  }

  -- The script, by the names Gen4IntroScene gives the entries rather than by
  -- index, so the screen that plays it never spells a bank index itself.
  for key, index in pairs(Gen4IntroScene.TEXT) do
    out.text[key] = self:string(BANK.rowanIntro, index)
  end
  out.text.tv = self:string(BANK.rowanIntroTv, Gen4IntroScene.TV_TEXT)

  out.controlInfo = {}
  for _, index in ipairs(Gen4IntroScene.CONTROL_INFO) do
    out.controlInfo[#out.controlInfo + 1] = self:string(BANK.rowanIntro, index)
  end
  out.adventureInfo = {}
  for _, index in ipairs(Gen4IntroScene.ADVENTURE_INFO) do
    out.adventureInfo[#out.adventureInfo + 1] = self:string(BANK.rowanIntro, index)
  end

  -- The rival's eight preset names, with "New name!" at the head of the list
  -- the way the cartridge's own menu orders them.  The first entry is the
  -- prompt to type one, not a name, and is marked rather than left for the
  -- screen to know by position.
  out.rivalNames = {}
  for index = Gen4IntroScene.RIVAL_NAME_FIRST, Gen4IntroScene.RIVAL_NAME_LAST do
    out.rivalNames[#out.rivalNames + 1] = {
      label = self:string(BANK.rowanIntro, index),
      custom = (index == Gen4IntroScene.RIVAL_NAME_FIRST) or nil,
    }
  end

  out.script = Gen4IntroScene.SCRIPT
  out.role = Gen4IntroScene.ROLE

  -- ------------------------------------------------------------ television --
  local tvArc = self:archive("introTv")
  if tvArc then
    -- The background palette as the app actually builds it: member 6 whole,
    -- then member 9 over colours 32 upwards.  See Gen4IntroScene.TV_PALETTE.
    local base = self:paletteMember(tvArc, Gen4IntroScene.TV_PALETTE)
    local over = self:paletteMember(tvArc, Gen4IntroScene.TV_PALETTE_OVERLAY)
    local palette = base
    if base and over then
      palette = {}
      for i = 1, #base do palette[i] = base[i] end
      local first = Gen4IntroScene.TV_OVERLAY_FIRST
      for i = first + 1, math.min(first + Gen4IntroScene.TV_OVERLAY_COUNT, #over) do
        palette[i] = over[i]
      end
    end
    for _, layer in ipairs(Gen4IntroScene.TV_LAYERS) do
      local image = palette and self:composeWith(tvArc, layer.tiles,
                                                layer.tilemap, palette)
      local entry = self:saveImage("intro/tv_" .. layer.name, image, {
        tiles = layer.tiles, tilemap = layer.tilemap,
      })
      if entry then out.tv[layer.name] = entry end
    end
  end

  -- --------------------------------------------------------------- Rowan ---
  local arc = self:archive("intro")
  if arc then
    local backdropPalette =
      self:paletteMember(arc, Gen4IntroScene.BACKDROP_PALETTE.platinum)
    for index, member in ipairs(Gen4IntroScene.BACKDROP_MAPS) do
      local role = Gen4IntroScene.BACKDROP_ROLE[index] or ("backdrop_" .. index)
      local image = backdropPalette
        and self:composeWith(arc, Gen4IntroScene.BACKDROP_TILES, member,
                             backdropPalette)
      local entry = self:saveImage("intro/backdrop_" .. role, image, {
        tilemap = member, role = role,
      })
      if entry then out.backdrops[role] = entry end
    end

    for _, figure in ipairs(Gen4IntroScene.FIGURES) do
      local own = self:paletteMember(arc, figure.palette)
      -- Replicated across every palette row; see Gen4IntroScene.FIGURE_ROWS
      -- for why that is the same picture the hardware draws rather than a
      -- shortcut around the cell rewrite.
      local palette
      if own then
        palette = {}
        for row = 0, Gen4IntroScene.FIGURE_ROWS - 1 do
          for colour = 1, 16 do
            palette[row * 16 + colour] = own[colour] or own[1]
          end
        end
      end
      local image = palette
        and self:composeWith(arc, figure.tiles,
                             Gen4IntroScene.FIGURE_TILEMAP, palette)
      local entry = self:saveImage("intro/figure_" .. figure.name, image, {
        tiles = figure.tiles, palette = figure.palette,
      })
      if entry then out.figures[figure.name] = entry end
    end

    -- --------------------------------------------------------- the ball ---
    -- Three pictures, not one: the same tilemap and palette with three tile
    -- sheets loaded into it in turn, which is the button being pushed in.
    --
    -- THE PALETTE IS THE THIRD ROW OF MEMBER 41 and nothing says so except
    -- the arithmetic in the app: it loads three rows starting at background
    -- row 7 and then points the tilemap's cells at row 9.  Composing with the
    -- member's first sixteen colours gives a picture that is wrong without
    -- looking broken, which is this archive's whole hazard.
    --
    -- ...AND THE SHEET IS LOADED AT TILE 32, which is the same arithmetic one
    -- step further on and was the half that was missing.  Without it every
    -- ball cell read past the end of a sixteen-tile sheet and the 736 empty
    -- cells drew that sheet's tile 0, so all three frames came out as the same
    -- field of one glyph with a hole in it -- which is exactly what they were
    -- on disk.  See Gen4IntroScene.BALL.tileFirst.
    local ballSource = self:paletteMember(arc, Gen4IntroScene.BALL.palette)
    local ballPalette
    if ballSource then
      ballPalette = {}
      local first = Gen4IntroScene.BALL.paletteFirst
      for row = 0, Gen4IntroScene.FIGURE_ROWS - 1 do
        for colour = 1, 16 do
          ballPalette[row * 16 + colour] =
            ballSource[first + colour] or ballSource[colour] or ballSource[1]
        end
      end
    end
    for step, member in ipairs(Gen4IntroScene.BALL.frames) do
      local image = ballPalette
        and self:composeWith(arc, member, Gen4IntroScene.BALL.tilemap,
                             ballPalette, Gen4IntroScene.BALL.tileFirst)
      local entry = self:saveImage(("intro/ball_%d"):format(step - 1), image, {
        tiles = member, tilemap = Gen4IntroScene.BALL.tilemap,
        palette = Gen4IntroScene.BALL.palette,
        tileFirst = Gen4IntroScene.BALL.tileFirst,
      })
      if entry then out.ball[step] = entry end
    end
  end

  self:write("gen4_intro", out)

  local backdrops, figures = 0, 0
  for _ in pairs(out.backdrops) do backdrops = backdrops + 1 end
  for _ in pairs(out.figures) do figures = figures + 1 end
  self.introReport = {
    backdrops = backdrops, figures = figures,
    tv = (out.tv.broadcast and 1 or 0) + (out.tv.bezel and 1 or 0)
      + (out.tv.scanlines and 1 or 0),
    haveHello = out.text.hello ~= nil,
    rivalNames = #out.rivalNames,
    ball = #out.ball,
  }
  return out
end

-- The player's walking, cycling, surfing, fishing and Poke-Ball sheets, for
-- both characters, in the two shapes `Player:refreshForm` reads:
-- `field.playerSprites` (the default pair) and `field.playerForms[gender]`
-- (the override the intro's boy-or-girl answer selects).
--
-- A sheet the cartridge does not have, or one whose graphics id has no
-- billboard, is simply absent: refreshForm keeps whatever it had for that
-- slot, which is better than pointing it at a sprite that is not the player.
function RomExtractorGen4:playerSheets()
  -- graphics id by NAME, built once.  Gen4ObjectGfx.name answers nil past the
  -- end of its list, which is the stop condition.
  if not self._gfxIdByName then
    local byName = {}
    local id = 0
    while true do
      local name = Gen4ObjectGfx.name(id)
      if not name then break end
      if byName[name] == nil then byName[name] = id end
      id = id + 1
      if id > 4096 then break end
    end
    self._gfxIdByName = byName
  end

  local function sheet(name)
    local id = self._gfxIdByName[name]
    if not id then return nil end
    local key = self:spriteFor(id)
    return key
  end

  -- THE BATTLE BACK PIC, which is a different sheet from every field one.
  --
  -- Item 7 of the play-test list: *"No trainer sprite in battle before the
  -- Pokemon is sent out"*.  Half of that was the renderer, which never drew one;
  -- the other half is here.  `field.playerPics` is not written by this
  -- extractor at all, so `Sprites.playerPath(data, "back")` fell through to the
  -- generation-agnostic default and answered `assets/generated/battle/redb.png`
  -- -- RED'S GEN 1 BACK SPRITE, on a Sinnoh cache.  `playerForms` was written
  -- but carried field sprites only, and `back` is the key
  -- `Sprites.playerForm` reads.
  --
  -- LUCAS AND DAWN are Diamond and Pearl's two player characters and these are
  -- their names in the cartridge's own sprite order -- `trainer_backs/` runs
  -- lucas_dp, dawn_dp, barry_dp (the rival), then the five stat trainers.  The
  -- names are the evidence: pokeplatinum was searched for a gender-to-index
  -- constant and has none to find.
  --
  -- Frame 00 of five.  The other four are the throw, which nothing plays yet.
  local function backPic(art)
    return ("assets/generated/gen4/battle/trainer_backs_%s_00.png"):format(art)
  end

  local function formFor(prefix, label, backArt)
    local form = {
      label = label,
      walk = sheet(prefix),
      bike = sheet(prefix .. "_bike"),
      surf = sheet(prefix .. "_surf"),
      fieldMove = sheet(prefix .. "_holding_poke_ball"),
      fishing = sheet(prefix .. "_fishing"),
      back = backArt and backPic(backArt) or nil,
    }
    return form.walk and form or nil
  end

  local boy = formFor("player_m", "BOY", "lucas_dp")
  local girl = formFor("player_f", "GIRL", "dawn_dp")
  if not (boy or girl) then return nil, nil end

  local default = boy or girl
  local forms = { order = {} }
  if boy then forms.order[#forms.order + 1] = "boy"; forms.boy = boy end
  if girl then forms.order[#forms.order + 1] = "girl"; forms.girl = girl end

  return {
    walk = default.walk, bike = default.bike, surf = default.surf,
    fieldMove = default.fieldMove, fishing = default.fishing,
  }, forms
end

-- ---------------------------------------------------------------------------
-- 3D models
-- ---------------------------------------------------------------------------

-- WHICH ARCHIVES' MODELS ARE PUBLISHED, and why this is a list rather than
-- "all of them".
--
-- The cartridge holds 1,030 models and the whole lot packs to under 4 MB, so
-- size is not the reason.  The reason is that a model in the cache is only
-- worth having when something draws it, and exactly one screen does so far.
-- Publishing the other twenty archives now would put twenty archives' worth of
-- geometry in every player's cache to be read by nothing, and would make the
-- import slower for no one's benefit.  Each entry moves here when the screen
-- that needs it exists.
-- SINNOH'S GROUND, in the cache.
--
-- Everything this stage needs was already read and none of it was ever kept:
-- the 666 land chunks decode, pack and verify with no failures, the 74 map
-- texture sets decode every one of their 3,130 textures, and a map's own
-- header says which set it wears.  What was missing was somewhere to put them.
--
-- THE GEOMETRY IS A SIDE-CAR BINARY and the Lua module is an index of offsets
-- into it -- see Gen4Terrain for why 17.7 MB cannot be a Lua table -- and the
-- heights are a second one beside it, 301 KB of BDHC left in the cartridge's
-- own form because Gen4Bdhc reads it as it stands.
--
-- WHAT THIS DOES NOT DO is bake a picture.  A chunk is drawn top-down into a
-- canvas at run time, once, the same way Gen3Tiles bakes its metatile sheets --
-- so the cache carries the mesh and the textures, not 666 rendered images that
-- would have to be re-rendered anyway the first time the camera changed.
function RomExtractorGen4:extractTerrain(names)
  self:beginStage("terrain")

  local land = self:archive("land")
  local matrices = self:archive("matrices")
  local areaArc = self:archive("areaData")
  local texArc = self:archiveAt("/fielddata/areadata/area_map_tex/map_tex_set.narc")
  local out = {
    source = "ROM:land_data.narc + map_matrix.narc + map_tex_set.narc",
    chunkTiles = Gen4Terrain.CHUNK_TILES,
    tileUnits = Gen4Terrain.TILE_UNITS,
    chunkUnits = Gen4Terrain.CHUNK_UNITS,
    pixelsPerUnit = Gen4Terrain.PIXELS_PER_UNIT,
    chunks = {}, matrices = {}, maps = {}, sets = {},
    refused = {},
  }
  if not (land and matrices) then
    self:write("gen4_terrain", out)
    return out
  end

  -- The chunks.
  local blob = Gen4Terrain.newBlob()
  local packed, refused = 0, 0
  for m = 0, land.count - 1 do
    local chunk, why = Gen4Terrain.chunk(land:get(m))
    if chunk then
      out.chunks[m] = Gen4Terrain.append(blob, chunk)
      packed = packed + 1
    else
      refused = refused + 1
      out.refused[m] = why
    end
    self:tick("terrain", m + 1, land.count + matrices.count + (texArc and texArc.count or 0))
  end
  local geometry, heights = Gen4Terrain.finish(blob)
  out.chunkFile = self:saveBinary("terrain/chunks.bin", geometry)
  out.heightFile = self:saveBinary("terrain/heights.bin", heights)
  out.chunkBytes, out.heightBytes = #geometry, #heights

  -- The matrices, which are what says WHICH chunk is where.  A map def already
  -- carries its matrix id and its corner in it, so nothing here is per map.
  for i = 0, matrices.count - 1 do
    out.matrices[i] = Gen4Terrain.grid(Gen4Maps.matrix(matrices:get(i)))
    self:tick("terrain", land.count + i + 1,
              land.count + matrices.count + (texArc and texArc.count or 0))
  end

  -- WHICH PALETTE EACH TEXTURE IS WORN WITH, gathered from the chunks.
  --
  -- The chunks are already packed above, and every shape in them carries the
  -- material's `texture` AND `palette` names.  This is the join the texture
  -- decode needs and it was being thrown away: `Gen4Terrain.textures` used
  -- palette 1 for everything, so every outdoor map in Sinnoh wore one palette.
  -- See that function for the measurement.
  --
  -- The model path below never had this problem -- it has always looked
  -- `shape.palette` up in the member's own palette dictionary -- which is why
  -- the buildings were the right colour standing on ground that was not.
  local pairing = {}
  local pairedShapes = 0
  for _, chunk in pairs(out.chunks) do
    for _, shape in ipairs(chunk.shapes or {}) do
      if shape.texture and shape.palette then
        local worn = pairing[shape.texture]
        if not worn then worn = {} ; pairing[shape.texture] = worn end
        worn[shape.palette] = (worn[shape.palette] or 0) + 1
        pairedShapes = pairedShapes + 1
      end
    end
  end

  -- The texture sets.
  local setsBuilt, undecoded = 0, 0
  if texArc then
    for m = 0, texArc.count - 1 do
      local bytes = texArc:get(m)
      if bytes and Gen4Graphics.isCompressed(bytes) then
        bytes = Gen4Graphics.decompress(bytes)
      end
      local parsed = bytes and Gen4Models.parse(bytes)
      local list, missed = parsed and Gen4Terrain.textures(parsed, bytes, pairing)
      if list then
        local entry = { textures = {} }
        for _, tex in ipairs(list) do
          -- '#' separates a variant key and is not a filename; two underscores
          -- keep "grass#lm2" and "grass_lm2" from landing on the same file.
          local safe = tostring(tex.name):gsub("#", "__"):gsub("[^%w_%-]", "_")
          local saved = self:saveImage(("terrain/tex/%02d/%s"):format(m, safe),
                                       tex.image,
                                       { texture = tex.texture, palette = tex.palette })
          if saved then entry.textures[tex.name] = saved end
        end
        entry.undecoded = (missed and #missed > 0) and missed or nil
        undecoded = undecoded + (missed and #missed or 0)
        out.sets[m] = entry
        setsBuilt = setsBuilt + 1
      end
      self:tick("terrain", land.count + matrices.count + m + 1,
                land.count + matrices.count + texArc.count)
    end
  end

  -- ...and which set each map wears, through its area record.
  local attributed, noArea = 0, 0
  for id, h in pairs(self._mapHeaders or {}) do
    local mapId = names and names[id]
    local record = areaArc and areaArc:get(h.areaData)
    local area = record and Gen4Maps.areaData(record)
    if mapId and area then
      out.maps[mapId] = { texture = area.mapTexture, area = h.areaData,
                          -- `areaLight`, not the old `lighting`: that name was on
                          -- pret's `dummy04` and selected nothing. See
                          -- Gen4Maps.areaData for how the ROM settled which is
                          -- which.
                          areaLight = area.areaLight,
                          outdoors = area.outdoors,
                          -- `mapPropArchivesID`: which of the 71 prop
                          -- allow-lists this map loads. Without it a prop id
                          -- cannot be told from a dummy box.
                          props = area.buildings }
      attributed = attributed + 1
    elseif mapId then
      noArea = noArea + 1
    end
  end

  self:areaLights(out.maps)
  self:mapProps()

  self:write("gen4_terrain", out)
  self.terrainReport = {
    chunks = packed, refused = refused, sets = setsBuilt,
    pairedShapes = pairedShapes,
    undecoded = undecoded, maps = attributed, noArea = noArea,
    geometry = #geometry, heights = #heights,
  }
  return out
end

-- THE MAP PROPS, AND THE ALLOW-LIST THAT DECIDES WHETHER ONE DRAWS AT ALL.
--
-- Reported from play as items 2 and 4: "signs are not rendered at all" and "some
-- areas draw placeholder tile art". Those are one fault, not two, and the
-- placeholder IS the cartridge's own dummy box.
--
-- A signpost in Platinum is not a sprite and not a tile. It is a MAP PROP -- an
-- entry in a land chunk's object records, carrying a model id, a position, a
-- rotation and a scale -- so it arrives with the houses through the same model
-- path. `Gen4Maps.objects` has decoded those records for as long as the terrain
-- stage has existed and `build_model.narc` is extracted beside them.
--
-- WHAT WAS MISSING IS THE INDIRECTION IN THE MIDDLE, AND IT IS NOT OPTIONAL.
-- `AreaDataManager_Load` does this:
--
--     mapPropModelIDs = NARC read of area_build.narc[areaData.mapPropArchivesID]
--     mapPropModelIDsCount = mapPropModelIDs[0]              // first u16 is a COUNT
--     GF_ASSERT(count < MAX_MAP_PROP_MODEL_FILES)            // 768
--     for (i = 0; i < count; i++) {
--         u16 id = mapPropModelIDs[i + 1];
--         mapPropModelFiles[id] = NARC read of build_model.narc[id];
--     }
--
-- so each area loads a SUBSET of `build_model.narc`, the ids are GLOBAL members
-- of that archive, and `mapPropModelFiles` is sparse -- indexed by the global id,
-- not by position in the list.
--
-- AND AN ID OUTSIDE THAT SUBSET DOES NOT VANISH, IT BECOMES A BOX:
--
--     if (mapPropModelFiles[mapPropModelID] == NULL) {
--         // Return the dummy box model if the requested one is not loaded
--         return &mapPropModelFiles[0];
--     }
--
-- with `map_prop.c` forcing `loadedProp->modelID = 0` alongside it, and
-- `AreaDataManager_Load` guaranteeing member 0 is resident whatever else is. That
-- member is `dmybox00` -- confirmed by reading it: build_model.narc member 0 is
-- 1900 bytes of NSBMD and the string "dmybox" is inside it. **The placeholder art
-- in the report is this model.** Any prop the port cannot resolve is not a
-- missing sign, it is a visible grey box, which is exactly what was seen.
--
-- `Gen4Maps.areaBuildings` HAS DECODED THIS LIST CORRECTLY THE WHOLE TIME AND
-- NOTHING EVER CALLED IT. All 71 members decode on the count-then-ids shape with
-- none refused, the largest list is 138 against the cartridge's 768 assert, and
-- the 527 distinct ids top out at 589 against a 590-member archive. A decoder
-- with no caller is the same failure as a table with no reader, one step earlier.
--
-- THE ASSOCIATION IS MEASURED, NOT ASSUMED. Walking every map's matrix and
-- testing its chunks' prop ids against its own area's list: of the 204 matrices
-- that carry props, **201 are covered exactly**. Three are not, and matrix 0 is
-- the loudest -- 501 placements with 101 distinct ids outside every single area
-- list, which is what a matrix shared by maps from different areas looks like
-- when only one area's subset is resident. On the cartridge those props draw the
-- dummy box, so the three exceptions are the rule working, not the rule failing.
--
-- Keyed by the ARCHIVE MEMBER and not by map, for the same reason the area lights
-- are: 71 lists against 593 maps.
function RomExtractorGen4:mapProps()
  local buildArc = self:archiveAt("/fielddata/areadata/area_build_model/area_build.narc")
  local texArc = self:archiveAt("/fielddata/areadata/area_build_model/areabm_texset.narc")
  local modelArc = self:archiveAt("/fielddata/build_model/build_model.narc")
  if not buildArc or not modelArc then
    self.mapPropReport = { sets = 0, reason = "archive missing" }
    return
  end

  local out = { sets = {}, models = modelArc.count, dummy = 0 }
  local decoded, refused, largest, ids = 0, 0, 0, {}
  for m = 0, buildArc.count - 1 do
    local list, err = Gen4Maps.areaBuildings(buildArc:get(m))
    if list then
      decoded = decoded + 1
      if #list > largest then largest = #list end
      for _, id in ipairs(list) do ids[id] = true end
      out.sets[m] = {
        props = list,
        -- `areabm_texset.narc` is read with the SAME member index as
        -- `area_build.narc`, and both archives are 71 long. The prop texture is
        -- bound to every model in the list by
        -- `Easy3D_BindTextureToResource(mapPropModelFiles[id], mapPropTexture)`,
        -- so a prop without its area's texture set is an untextured prop, not
        -- merely a differently-coloured one.
        texture = (texArc and m < texArc.count) and m or nil,
      }
    else
      refused = refused + 1
    end
  end

  local distinct, highest = 0, -1
  for id in pairs(ids) do
    distinct = distinct + 1
    if id > highest then highest = id end
  end

  -- ...AND THE DRAW LIST, which is the other half of making a prop appear right.
  --
  -- `MapProp_Draw` never hands the model to the renderer whole. It walks a
  -- (material, shape) list out of `build_model_matshp.dat` and issues one
  -- `NNS_G3dDraw1Mat1Shp` per pair, so the file IS the draw order. It is not the
  -- shapes' own order either: 160 of the 478 non-empty lists put their shape ids
  -- out of sequence, and models 22, 23 and 236 draw material 0 LAST after
  -- materials 1..4 -- translucency ordering, which comes out wrong if a prop is
  -- drawn the obvious way. Folded into this table rather than given its own so
  -- that everything a prop needs arrives together.
  local shapeBytes = self.rom and self.rom:read(Gen4PropShapes.PATH)
  local shapes, shapeErr = shapeBytes and Gen4PropShapes.parse(shapeBytes)
  if shapes then
    out.draw = shapes.lists
    out.drawModels = shapes.models
    out.drawPairs = shapes.pairs
  end

  self:write("gen4_mapprops", out)
  self.mapPropReport = {
    sets = decoded, refused = refused, largest = largest,
    distinct = distinct, highest = highest, models = modelArc.count,
    textureSets = texArc and texArc.count or 0,
    drawLists = shapes and shapes.models or 0,
    drawPairs = shapes and shapes.pairs or 0,
    drawError = (not shapes) and (shapeErr or "file missing") or nil,
  }
end

-- THE AREA LIGHTS, WHICH IS THE COLOUR OF THE WORLD AND WAS NOT BEING EXTRACTED.
--
-- Reported from play as the overworld "rendering everything as flat 2d", with a
-- Twinleaf shot beside the cartridge's. The geometry was only part of it: the
-- port's grass is a BRIGHT SATURATED GREEN and its path YELLOW, where the
-- cartridge's are a muted olive and a warm ORANGE-BROWN. Same textures. The
-- cartridge LIGHTS them and this port was drawing them unlit, and unlit textures
-- always come out brighter and flatter than lit ones.
--
-- THE INDEX WAS IN THE CACHE THE WHOLE TIME, UNREAD AND POINTING AT THE WRONG U16.
-- The terrain stage above has written a byte onto all 593 maps since it was first
-- written, straight off the area record beside `texture`, under the name
-- `lighting`. It was pret's `dummy04` -- the one field of `AreaDataFile` the
-- cartridge never reads -- and the real `areaLightArchiveID` sat in the next u16
-- under the name `flags`. Writing a field nobody reads is how that survives:
-- there was no consumer to be wrong, so nothing ever disagreed with it.
--
-- `Gen4Maps.areaData` now names both correctly and records how the ROM settled
-- it. The corrected index is what this stage keys on.
--
-- THAT WOULD HAVE BEEN THE SIXTH WRITE-AND-NEVER-READ TABLE, after
-- gen4_species_sprites, gen4_move_anims, gen4_particles, gen4_overworld (which
-- was Dawn) and the terrain byte itself -- which had gone one worse than unread,
-- because an unread field is also an unchecked one and this one was the wrong
-- field entirely. It is written under the
-- `gen4_` prefix and listed in Data's GEN4_PREFIXED for exactly that reason, so
-- `tools/gen4_cache_wiring_check.lua` can see it.
--
-- KEYED BY THE BYTE, NOT BY MAP. There are four members and 593 maps, so keying
-- per map would store the same fifteen templates 593 times; the byte is what the
-- cartridge selects on and it is already on every map record.
function RomExtractorGen4:areaLights(mapsByName)
  local raw = self.rom and self.rom:read(Gen4AreaLight.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then
    self.areaLightReport = { members = 0, reason = "archive missing" }
    return
  end

  local out = { members = {}, path = Gen4AreaLight.PATH }
  local templates, parsed = Gen4AreaLight.all(arc)
  for m = 0, arc.count - 1 do
    out.members[m] = templates[m]
  end

  -- ...and which of the four each map actually asks for, so a check can prove the
  -- index and the archive meet rather than assuming they do.
  local used, unknown = {}, 0
  for _, record in pairs(mapsByName or {}) do
    local light = record and record.areaLight
    if light then
      if light < Gen4AreaLight.FILE_COUNT and out.members[light] then
        used[light] = (used[light] or 0) + 1
      else
        -- GF_ASSERT(archiveID < AREA_LIGHT_FILE_COUNT) is the cartridge's own
        -- bound, so a byte past it is a parse fault upstream and not a map that
        -- happens to be unlit.
        unknown = unknown + 1
      end
    end
  end
  out.used = used

  self:write("gen4_arealight", out)
  local total = 0
  for _, ts in pairs(out.members) do total = total + #ts end
  self.areaLightReport = {
    members = parsed, count = arc.count, templates = total,
    used = used, unknown = unknown,
  }
end

local MODEL_ARCHIVES = {
  { path = "/graphic/ev_pokeselect.narc", out = "starter",
    label = "starter selection" },
  -- THE FIELD'S OWN ANIMATION ARCHIVE, and it holds no models at all: 72
  -- texture-pattern flipbooks, 98 texture scrolls and the doors, laid over the
  -- map meshes.  Nothing consumes these yet -- the map meshes are not built --
  -- so they are extracted and checked rather than drawn.  They are here now
  -- because they are what makes water move, and because an animation archive
  -- with no models beside it is exactly the case a reader that assumed models
  -- would get wrong quietly.
  { path = "/arc/bm_anime.narc", out = "field",
    label = "field animations" },
  -- THE TITLE SEQUENCE'S OWN 3D, which is the whole of what the title screen
  -- is missing.  `title_gira` is member 1: Giratina, four shapes and 996
  -- triangles, carrying its OWN textures, with a 121-frame joint animation
  -- (BCA0) and a 121-frame texture scroll (BTA0) beside it.  `op_ana` (240
  -- frames, joint + texture) is the portal it comes through and `op_kao`
  -- (174 frames, joint + material) the face.  Every decoder these need is
  -- already proven against the starter models; nothing was reading them
  -- because nothing asked this archive for models.
  { path = "/demo/title/titledemo.narc", out = "title",
    label = "title sequence" },
  -- ...AND THE OPENING CUTSCENE'S.  `gOpeningCutsceneAppTemplate` runs for
  -- 2,430 frames before the title screen and draws out of this archive:
  -- sixteen map models (`op_map01_00_00`, `titlemap05_20`, ...) flown through
  -- by a camera, over 33 tile sheets, 21 palettes and 24 tilemaps.  The models
  -- carry no TEX0 of their own -- the four BTX0 members beside them are the
  -- texture sets -- which the stage already handles by leaving `image` unset.
  { path = "/demo/title/op_demo.narc", out = "opening",
    label = "opening cutscene" },
  -- THE BUILDINGS STANDING ON THE GROUND.  A land chunk's mesh is its FLOOR --
  -- 9,497 walkable tiles have no land triangle under them at all, because
  -- indoor chunks are a shell and their floors are building models -- so a
  -- Sinnoh drawn from the chunks alone is a Sinnoh with no houses in it.
  --
  -- 590 models, all 590 decoding exactly, 1,362 shapes and 89,253 vertices.
  -- 568 of them carry their OWN textures, which is why they belong in this
  -- stage rather than needing the per-area texture sets: for those 568 the
  -- picture is inside the model file and the stage that already reads a
  -- model's own TEX0 reads it without a new line.  The other 22 come out
  -- untextured and are drawn that way rather than wearing a borrowed picture.
  { path = "/fielddata/build_model/build_model.narc", out = "buildings",
    label = "map buildings" },
  -- THE OBJECTS THAT ARE MODELS RATHER THAN BILLBOARDS -- every sign and
  -- every mailbox in Sinnoh, and they were invisible until this archive was
  -- read.  `board_a`..`board_f` at members 69-74 are the six signpost
  -- graphics ids; see Gen4ObjectGfx.readModels for the nine-row table that
  -- names them and for why the six identically-named models in mmodel.narc
  -- are NOT the answer.  201 members, 145 of them BMD0, 319KB in all.
  { path = "/data/mmodel/fldeff.narc", out = "fldeff",
    label = "field-effect models" },
}

-- Platinum's 3D, in the shape the engine can load: packed geometry, the
-- textures as ordinary PNGs, and the animations that drive each model.
--
-- THE GEOMETRY IS VERIFIED TWICE, and the second one is the one that matters
-- here.  Gen4Nsbmd already checks every model against the counts its own
-- header states -- that is what makes the decode trustworthy.  This stage then
-- packs each model into two binary strings and UNPACKS THEM AGAIN, requiring
-- every coordinate and every index to come back unchanged.  A packer that
-- drops a field, swaps two, or mis-signs a negative produces a model that
-- still draws, inside out or with a wall missing, and nothing else would
-- notice.
-- The Distortion World's runtime floor: the one dungeon whose walkable ground
-- is not in its map.  See src/import/Gen4DistWorld.lua for the formats and for
-- why every table here is FOUND rather than indexed.
--
-- AFTER the maps stage, because the shuttle check below needs the map header
-- ids to mean something, and before nothing -- no other stage reads this.
function RomExtractorGen4:extractDistortionWorld()
  self:beginStage("distortion")

  local out = {
    source = "ROM:tw_arc.narc + tw_arc_attr.narc + overlay 9",
    grid = Gen4DistWorld.GRID,
    baseLocalId = Gen4DistWorld.BASE_LOCAL_ID,
    kinds = Gen4DistWorld.KIND_NAMES,
    floors = {}, maps = {}, attrs = {},
    cast = {}, events = {}, movingPlatforms = {}, simpleProps = {},
    elevatorPaths = {}, shuttles = {}, horizontal = {},
    refused = {},
  }

  local mainArc = self:archiveAt(Gen4DistWorld.MAIN_PATH)
  local attrArc = self:archiveAt(Gen4DistWorld.ATTR_PATH)
  if not (mainArc and attrArc) then
    out.refused.archives = "tw_arc.narc or tw_arc_attr.narc missing"
    self:write("gen4_distortion_world", out)
    return out
  end

  local infos, why = Gen4DistWorld.mapInfo(mainArc:get(0))
  if not infos then
    out.refused.mapInfo = why
    self:write("gen4_distortion_world", out)
    return out
  end

  local total = #infos + attrArc.count + #Gen4DistWorld.TABLES + 1
  local done = 0
  for _, info in ipairs(infos) do
    local file, err = Gen4DistWorld.mapFile(mainArc:get(info.fileIndex + 1))
    out.floors[info.header] = Gen4DistWorld.FLOOR_NAMES[info.header]
    if file then
      out.maps[info.header] = {
        fileIndex = info.fileIndex,
        offsetX = info.offsetX,
        offsetAltitude = info.offsetAltitude,
        offsetZ = info.offsetZ,
        platforms = file.platforms,
        jumps = file.jumps,
        cameras = file.cameras,
        ghostPropBytes = file.ghostPropBytes,
      }
    else
      out.refused["map" .. tostring(info.header)] = err
    end
    done = done + 1
    self:tick("distortion", done, total)
  end

  -- The attribute grids are stored in the cartridge's own
  -- `vertical + horizontal * 32` order, NOT transposed into rows: the four
  -- platform kinds read the two axes differently and a transpose that suits
  -- FLOOR is wrong for the two wall kinds and the ceiling.
  for i = 0, attrArc.count - 1 do
    local grid, err = Gen4DistWorld.attrGrid(attrArc:get(i))
    if grid then
      out.attrs[i] = grid
    else
      out.refused["attr" .. tostring(i)] = err
    end
    done = done + 1
    self:tick("distortion", done, total)
  end

  local bin, meta = self.rom:overlay(Gen4DistWorld.OVERLAY)
  if not bin then
    out.refused.overlay = "overlay 9 unreadable"
    self:write("gen4_distortion_world", out)
    return out
  end
  out.overlayBytes = #bin
  out.overlayRam = meta and meta.ram or nil

  for _, t in ipairs(Gen4DistWorld.TABLES) do
    local at = Gen4DistWorld.findTable(bin, meta.ram, t.maps)
    if at then
      out[t.key] = Gen4DistWorld.readTable(bin, meta.ram, at, t.maps, t.key)
      out.refused["found_" .. t.key] = nil
    else
      -- NAMED, not silent: a missing table is a different cartridge build, and
      -- the engine has to be able to tell that from "this floor has no cast".
      out.refused[t.key] = ("no run of %d {mapHeaderID, pointer} records matching its map set")
        :format(#t.maps)
    end
    done = done + 1
    self:tick("distortion", done, total)
  end

  local eat, paths = Gen4DistWorld.findElevatorPaths(bin)
  if paths then
    out.elevatorPaths = paths
  else
    out.refused.elevatorPaths = "no run of 22 self-indexing 32-byte records"
  end
  done = done + 1
  self:tick("distortion", done, total)

  -- WHAT THE ENGINE ACTUALLY WANTS.  A shuttle pair is a lift between two
  -- floors at IDENTICAL map coordinates, which in a port with no vertical axis
  -- is a warp.  The pairing is proved, not assumed: follow the elevator path
  -- chain, and require a platform at the same (x, z) on the altitude it lands
  -- on whose index is this platform's destIndex.  18 of 34 pass, they form 9
  -- symmetric pairs, and the 16 that fail are all on B2F -- horizontal
  -- platforms driven by that floor's own 24 coordinate events.
  if next(out.movingPlatforms) and next(out.elevatorPaths) then
    local shuttles, horizontal = Gen4DistWorld.classify(out.movingPlatforms, out.elevatorPaths)
    out.shuttles = shuttles
    out.horizontal = horizontal
  end

  self:write("gen4_distortion_world", out)
  return out
end

function RomExtractorGen4:extractModels()
  self:beginStage("models")

  local out = { sets = {}, source = "ROM:Platinum (NSBMD/NSBTX/NSBCA)" }
  local totalModels, totalShapes, failed = 0, 0, 0
  local animFailed = 0
  local patternWritten = 0

  for _, entry in ipairs(MODEL_ARCHIVES) do
    local arc = self:archiveAt(entry.path)
    local set = { label = entry.label, path = entry.path,
                  models = {}, animations = {} }
    -- Joint animations wait until the whole archive has been read: see below
    -- for why their matrices are only written where something can wear them.
    local pending = {}
    if arc then
      for member = 0, arc.count - 1 do
        local bytes = arc:get(member)
        if bytes and Gen4Graphics.isCompressed(bytes) then
          bytes = Gen4Graphics.decompress(bytes)
        end
        local magic = bytes and bytes:sub(1, 4)

        if magic == Gen4Nsbmd.MAGIC then
          local parsed = Gen4Nsbmd.parse(bytes)
          local sections = Gen4Nsbmd.sections(bytes)
          -- The model file carries its own textures in a second section, and
          -- `Gen4Models.parse` has to be told where: reading a model file the
          -- way a texture archive is read finds the MODEL section and builds a
          -- texture table out of geometry.
          local textures = sections and sections.TEX0
            and Gen4Models.parse(bytes, sections.TEX0) or nil
          local textureBytes=bytes
          if not textures and entry.out=='opening' then
            local textureMember=(member==100 or member==101) and 102
              or (member>=103 and member<=108) and 109
              or (member==110 or member==111) and 112
            if textureMember then
              textureBytes=arc:get(textureMember)
              if Gen4Graphics.isCompressed(textureBytes) then textureBytes=Gen4Graphics.decompress(textureBytes) end
              local textureSections=Gen4Nsbmd.sections(textureBytes)
              textures=Gen4Models.parse(textureBytes,textureSections and textureSections.TEX0)
            end
          end
          for _, model in ipairs(parsed and parsed.models or {}) do
            local packed = Gen4ModelPack.pack(model)
            local ok, why = Gen4ModelPack.verify(model, packed)
            if not ok then
              failed = failed + 1
              self.modelFailure = self.modelFailure or why
            end
            packed.member = member
            packed.animations = {}

            -- Each shape's texture, written once per NAME rather than once per
            -- shape: fifteen shapes of the briefcase share three pictures
            -- between them, and saving one file per shape would write the same
            -- image five times.
            local written = {}
            for _, shape in ipairs(packed.shapes) do
              local name = shape.texture
              if name and textures then
                local key = ("%s/%s"):format(model.name, name)
                if written[name] == nil then
                  written[name] = false
                  local index, palette
                  for i, texture in ipairs(textures.textures) do
                    if texture.name == name then index = i end
                  end
                  for i, entry2 in ipairs(textures.palettes) do
                    if entry2.name == shape.palette then palette = i end
                  end
                  local image = index
                    and Gen4Models.decode(textures, textureBytes, index, palette or 1)
                  local saved = image and self:saveImage(
                    "models/" .. entry.out .. "/" .. key:gsub("[^%w_/%-]", "_"),
                    image, { texture = name, palette = shape.palette })
                  written[name] = saved and saved.path or false
                end
                shape.image = written[name] or nil
              end
              totalShapes = totalShapes + 1
            end

            -- THE FRAMES A DOOR IS NOT CURRENTLY SHOWING.
            --
            -- The loop above writes the texture each SHAPE references, which
            -- for an animated material is frame zero and nothing else -- so a
            -- BTP0's other three pictures were decoded, named, and never
            -- written.  That is why the flipbooks could be read and not played.
            --
            -- WHERE THEY LIVE was the open question, and it is answered: of the
            -- 16 build models carrying a BTP0, ALL 16 have every one of that
            -- animation's texture names in their OWN TEX0 -- no misses, and no
            -- model without a TEX0.  So the picture is inside the model file
            -- beside the one it replaces, and this is the same decode with a
            -- different list of names.
            --
            -- `bm_anime` is earlier in MODEL_ARCHIVES than `build_model`, so
            -- its patterns are already read when this runs.  That ordering is
            -- load-bearing and is why the list is checked rather than assumed
            -- present.
            local fieldSet = out.sets.field
            if textures and fieldSet and model.name then
              for _, record in ipairs(fieldSet.animations or {}) do
                if record.name == model.name and record.pattern then
                  local names = record.pattern.textures or {}
                  local palettes = record.pattern.palettes or {}
                  packed.patternImages = packed.patternImages or {}
                  for i, name in ipairs(names) do
                    if packed.patternImages[name] == nil then
                      local index, palette
                      for j, texture in ipairs(textures.textures) do
                        if texture.name == name then index = j end
                      end
                      for j, entry2 in ipairs(textures.palettes) do
                        if entry2.name == palettes[i] then palette = j end
                      end
                      local image = index
                        and Gen4Models.decode(textures, textureBytes, index, palette or 1)
                      local key = ("%s/%s"):format(model.name, name)
                      local saved = image and self:saveImage(
                        "models/" .. entry.out .. "/" .. key:gsub("[^%w_/%-]", "_"),
                        image, { texture = name, palette = palettes[i] })
                      packed.patternImages[name] = saved and saved.path or false
                      if saved then patternWritten = patternWritten + 1 end
                    end
                  end
                end
              end
            end

            set.models[#set.models + 1] = packed
            totalModels = totalModels + 1
          end

        elseif magic and Gen4Anim.KINDS[magic] then
          -- The animations are carried beside the models rather than merged
          -- into them, because an animation names what it drives and the
          -- pairing is by NAME -- which is the cross-check, and folding them
          -- together here would throw it away.
          local parsed = Gen4Anim.parse(bytes)
          for _, anim in ipairs(parsed and parsed.animations or {}) do
            local record = {
              name = anim.name, member = member, kind = parsed.kind,
              what = parsed.what, frames = anim.frames,
              joints = anim.nodes, targets = anim.targets,
            }
            -- A JOINT ANIMATION ALSO CARRIES ITS NUMBERS NOW.  The other four
            -- formats are still structure only: what they drive is named and
            -- checked, and nothing reads their values yet.
            if parsed.kind == "BTA0" then
              record.targets = nil
              record.srt = Gen4Anim.textureSrt(bytes, anim)
            elseif parsed.kind == "BTP0" then
              record.targets = nil
              record.pattern = Gen4Anim.texturePattern(bytes, anim)
            elseif parsed.kind == "BMA0" then
              record.targets = nil
              record.colour = Gen4Anim.materialColour(bytes, anim)
            elseif parsed.kind == "BVA0" then
              record.visibility = Gen4Anim.visibility(bytes, anim)
            elseif parsed.kind == "BCA0" then
              -- Decoded below, once it is known whether anything here can be
              -- posed by it.
              pending[#pending + 1] = { record = record, bytes = bytes, anim = anim }
            end
            set.animations[#set.animations + 1] = record
          end
        end
      end
    end
    -- A JOINT ANIMATION'S MATRICES ARE ONLY WRITTEN WHERE A MODEL HERE CAN
    -- WEAR THEM, which is the same pairing `Gen4Anim.resolve` checks: a joint
    -- animation names nothing, so the only thing that can claim it is a model
    -- in the same archive with that many nodes.
    --
    -- This is a size decision as much as a correctness one, and the numbers
    -- are worth recording.  `bm_anime` holds no models at all -- it is 98
    -- animations laid over map meshes that are not built yet -- and writing
    -- its joint matrices anyway cost 2.2 MB of cache for poses nothing could
    -- apply.  Its texture scrolls and flipbooks, which are what make water
    -- move, are 200 KB and are written.
    local wearable = {}
    for _, model in ipairs(set.models) do wearable[#model.nodes] = true end
    for _, item in ipairs(pending) do
      if wearable[item.anim.nodes] then
        local tracks = Gen4Anim.jointMatrices(item.bytes, item.anim)
        item.record.tracks = {}
        for _, joint in ipairs(tracks or {}) do
          local blob = Gen4Anim.packTrack(joint.track)
          local ok, why = Gen4Anim.verifyTrack(joint.track, blob)
          if not ok then
            animFailed = animFailed + 1
            self.animFailure = self.animFailure or why
          end
          item.record.tracks[#item.record.tracks + 1] =
            { index = joint.index, frames = joint.frames, matrices = blob }
        end
      else
        item.record.unworn = true
      end
    end

    -- BY MEMBER, BECAUSE POSITION IS NOT MEMBER.
    --
    -- `Gen4Ground:building` reaches a model as `set.models[index + 1]`, which is
    -- right for `build_model.narc` ONLY because that archive happens to be one
    -- model per member with every member decoding.  It is a coincidence, not a
    -- rule: this loop appends one entry per MODEL and an NSBMD member may carry
    -- several, and `fldeff.narc` is 201 members of which only 145 are BMD0 at
    -- all.  Indexing it by position would put the wrong model on every sign and
    -- still draw something, which is the failure that looks like success.
    --
    -- So the member each entry actually came from -- which the loop above has
    -- always stamped and nothing has ever read -- is published as an index.
    -- First one wins, so a member carrying several models resolves to its first,
    -- the same one the cartridge's own single-model lookup would take.
    set.byMember = {}
    for i, model in ipairs(set.models) do
      if model.member and set.byMember[model.member] == nil then
        set.byMember[model.member] = i
      end
    end

    out.sets[entry.out] = set
  end

  -- ------------------------------------------------------------------------
  -- WHAT `bm_anime` ACTUALLY ANIMATES, which is not what this file said.
  --
  -- The note beside that archive read "72 texture-pattern flipbooks and 98
  -- scrolls are what makes Platinum's water move, and a baked chunk is still by
  -- definition."  Close, and wrong about the mechanism -- which is the kind of
  -- wrong that sends the next person to rebake the terrain.
  --
  -- MEASURED against this cartridge: of the 95 animations in `bm_anime`,
  --
  --    68 name a BUILD MODEL, by the model's own name
  --     3 name a texture in the area building texture sets
  --     0 name any material, shape or texture of a LAND CHUNK
  --
  -- and the names say the same thing out loud once you read them: `door_op`,
  -- `pc_door_op`, `stair_pc_u01d`, `funsui` (a fountain), `machine_l02`,
  -- `treeeff01`.  They animate the PROPS STANDING ON the ground -- doors
  -- opening, fountains running, tree tops moving -- not the ground.  Some of
  -- those props are water (`l_lake`, `wfall`), which is why the water intuition
  -- was nearly right and its mechanism was not.
  --
  -- The two archives are separate, so the per-archive pairing above cannot see
  -- across them; this is the one cross-archive link, made here once so nothing
  -- at run time has to search 95 animations per building per frame.
  local field, buildings = out.sets.field, out.sets.buildings
  local linked, byName = 0, {}
  if field and buildings then
    for _, record in ipairs(field.animations or {}) do
      if record.name then
        byName[record.name] = byName[record.name] or {}
        local list = byName[record.name]
        list[#list + 1] = { kind = record.kind, frames = record.frames,
                            member = record.member }
      end
    end
    for _, model in ipairs(buildings.models or {}) do
      local found = model.name and byName[model.name]
      if found then
        model.animations = found
        linked = linked + 1
      end
    end
  end

  self:write("gen4_models", out)
  self.modelReport = {
    models = totalModels, shapes = totalShapes, failedRoundTrip = failed,
    reason = self.modelFailure or self.animFailure,
    failedTracks = animFailed,
    animatedBuildings = linked,
    patternFrames = patternWritten,
  }
  return out
end

function RomExtractorGen4:run()
  self:extractText()
  self:extractSpecies()
  self:extractMoves()
  -- BESIDE THE MOVES, because it is the same 501 slots read a second way and a
  -- reader looking for "what does this move do" should find both in one place.
  self:extractMoveAnims()
  -- ...and the pictures those programs point at, beside them for the same
  -- reason: "what does this move look like" is one question with two halves.
  self:extractParticles()
  -- ...and the THIRD layer, the flat 2D sprites 32 of the programs build out of
  -- four separate archives. It runs after the programs because it extracts
  -- exactly the resource tuples they name.
  self:extractCellActors()
  self:extractItems()
  self:extractEncounters()
  self:extractTrainers()
  local headers, names = self:extractMaps()
  local events = self:extractEvents()
  self:extractRegions(events, names)
  self:extractTilesets()
  self:extractConstants()
  self:extractOverworld()
  self:extractSpeciesSprites()
  self:extractTrainerSprites()
  self:extractHeights()
  self:extractField()
  self:extractScripts()
  self:linkScripts(headers, events, names)
  self:extractGraphics()
  self:extractFonts()
  -- LAST, AND THAT IS THE POINT.  The menus stage names the title art by role
  -- out of the graphics stage's own index, so it cannot run before the pictures
  -- exist -- run earlier it writes a record with every art path nil, which is a
  -- title screen that draws nothing and reports no error.
  self:extractMenus()
  self:extractIntro()
  self:extractNaming()
  self:extractDex()
  self:extractCries()
  self:extractModels()
  -- AFTER the maps stage, which is where the header table and the map names
  -- come from, and after the models stage only because the stage list reads
  -- in the order the progress bar shows.
  self:extractTerrain(names)
  -- LAST, and it needs nothing from the stages before it: the Distortion World
  -- reads two archives of its own and one ARM9 overlay, and joins to the rest
  -- of the cache only by map header id.
  self:extractDistortionWorld()
  return self.wrote
end

-- NOT BUILT YET, and each is a seam rather than a detail:
--
--   * RomImporter has to hand this a PATH.  Its `startData` reads the whole
--     file to hash it, which is correct for verification and wrong to carry
--     into extraction at 128 MiB.
--   * A TEXT RENDERER.  The fonts and their widths are extracted now, but
--     nothing draws with them: there is no Gen 4 text box, no line breaking
--     and no colour choice per box.  That is engine work, not extraction.
--   * The sheets with no cell bank ANYWHERE in their archive -- window frames,
--     mail backgrounds, the fonts -- are still laid out at a stated width and
--     still flagged `provisionalLayout`.  Most of those are tilesets rather
--     than sprites, so a bank may not exist to find.
--   * WHAT SWITCHES A FORM.  The form pictures are all extracted now, but
--     nothing chooses between them: Castform still needs the weather, Cherrim
--     the sun, Rotom its appliance, Arceus the held plate, and Unown a letter
--     from its personality value.  That is battle and party logic rather than
--     extraction, and it is the reason `def.forms` is written but not yet read.
--   * The map meshes and the BDHC height blocks, for the same reason.
--   * A map DEFINITION per map -- the grid, the objects with their sprites
--     and positions -- so the overworld has something to load.  The script
--     pool now names every map and its objects' scripts, but nothing yet
--     builds the world those objects stand in.

return RomExtractorGen4

