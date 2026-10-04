-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE PROP ANIMATION JOIN -- the port's was by NAME and the cartridge's is by
-- CLAIM, and 44 of 112 animated props fell in the gap.
--
-- `Gen4Ground:animationsFor` asked `animsByName[model.name]`: does a
-- `bm_anime` animation share this prop model's name?  That is this port's own
-- join.  The cartridge's runs through a third archive, which pokeplatinum's
-- map-format graph names:
--
--     area_build    --> bm_anime_list : mapPropModelIDs
--     bm_anime_list --> bm_anime      : animeArchiveIDs
--
-- Measured on this cartridge, the two disagree about a third of the subject:
--
--     112  prop models claimed by a bm_anime animation
--      68  of them share a NAME with one
--      44  do not, and were handed to the static bake, where the draw never
--          asks for a pose or a material at all
--
-- The 44 split 22 joint -- already reached, because `oneShotProps` keys on the
-- claim -- and 22 TEXTURE, twelve BTA0 and ten BTP0 over 124 placements:
--
--     wfall3_4, wfall3_5, wfall16_5, wfall11_14, wfall7_4dun, wfall3_4dun
--         all six claimed by animation 18 (`wfall`, 61 frames, 3 SRT
--         targets), none of them named `wfall`.  PLATINUM'S WATERFALLS WERE
--         STATIC.
--     cy_slope, cy_slope_dun       animations 20/21, 21 frames
--     ev_o01                       animations 35/36, 31 frames
--     l_lake_l4                    animation 19, 61 frames
--     c5_o03, r212s02              animation 0 (`funsui`), 16 frames
--     stair_pc_u01/d01/u02/d02     animations 15/16, 20 frames (escalators)
--     table_l01/l02/l03, pc01      animations 41/42 (`pc_moni_on`/`_off`)
--     machine_pc03                 animation 32 (`moniter_mb`, 73 frames)
--     ele_door1                    animations 51/52 -- the elevator door
--
-- AND THE ELEVATOR DOOR IS THE EIGHTH INSTANCE of the pattern
-- `claude/gen4_declined_subjects.md` tracks, with a twist: the stale claim was
-- a PREDICTION rather than a blocker.  `Gen4PropAnim.lua` said its BTP0 pair
-- made it "the one of the twenty that could move today".  It could not, and
-- the reasons were three, each in a different file:
--
--   * `oneShotProps` required `record.tracks`, which no BTP0 record has, so
--     `ele_door1` went to the STATIC bake and the runner's eight frames were
--     advancing against a prop nothing asked for a pose;
--   * `animationsFor` joined by name, and the animations are `ele_door1_op` /
--     `ele_door1_cl` while the model is `ele_door1`;
--   * the extractor decoded a BTP0's alternate frames only for a model whose
--     name an animation SHARED, so the four `ele_door.*` pictures were never
--     written and there was nothing to flip through.
--
-- A fourth thing had to be true and was not obvious: a flipbook door must NOT
-- be driven by the frame clock.  The clock is a free-running loop over the
-- animation's period, so putting `ele_door1` on it would have opened and shut
-- the door for ever on its own -- worse than the static door it replaced.  The
-- clock-driven set therefore excludes the script-owned animations, derived
-- from `Gen4PropAnim.DOORS`.
--
-- WHAT THIS CHECK GRADES, and what it deliberately does not: every assertion
-- outside sections 2 and 3 runs with no cartridge and no cache, against
-- records built here to the cache's real shape.  Sections 2 and 3 re-derive
-- the two joins from the ROM, because a count copied out of this comment is a
-- number nobody is checking.
--
-- Run:  texlua tools/gen4_prop_claim_check.lua <rom path> [data/generated]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local ROM   = arg and arg[1]
local CACHE = arg and arg[2]

local fails, checks, reports, skips = 0, 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function skip(fmt, ...)
  skips = skips + 1
  io.write("SKIP: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  if not p then return nil end
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function loadTable(dir, name)
  if not dir then return nil end
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if not f then return nil end
  local okRun, t = pcall(f)
  return okRun and t or nil
end
local function keys(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- A graphics stub, because `Gen4Ground` requires modules that reach for LOVE
-- at load.  Nothing in this check draws: every subject is arithmetic or a
-- table lookup, which is exactly why they were split out of the draw.
love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end,
               newCanvas = function() return nil end,
               newImage = function() return nil end,
               setColor = function() end, rectangle = function() end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
  image = { newImageData = function() return nil end },
  math = { random = math.random },
}

local GameVersion = require("src.core.GameVersion")
GameVersion.set("platinum")

local Gen4Ground   = require("src.render.Gen4Ground")
local Gen4TexAnim  = require("src.render.Gen4TexAnim")
local Gen4PropAnim = require("src.import.Gen4PropAnim")
local OneShot      = require("src.world.Gen4PropOneShot")
local NdsRom       = require("src.import.NdsRom")
local Narc         = require("src.import.NarcArchive")
local Nsbmd        = require("src.import.Gen4Nsbmd")
local Gen4Models   = require("src.import.Gen4Models")
local Gen4Graphics = require("src.import.Gen4Graphics")
local Gen4Anim     = require("src.import.Gen4Anim")

local LIST_PATH  = "/arc/bm_anime_list.narc"
local ANIM_PATH  = "/arc/bm_anime.narc"
local MODEL_PATH = "/fielddata/build_model/build_model.narc"

local GROUND_SRC    = slurp("src/render/Gen4Ground.lua")
local EXTRACTOR_SRC = slurp("src/import/RomExtractorGen4.lua")

-- ---------------------------------------------------------------------------
section("0. the requires, and a canary that the lookups mean anything")
-- ---------------------------------------------------------------------------
-- Shape 6b of claude/check_design_lessons.md, both directions: a check that
-- grades an empty namespace reports every subject absent, and "absent" is
-- indistinguishable from the fault being looked for.
ok(type(Gen4Ground) == "table" and type(Gen4Ground.animationsFor) == "function",
   "src.render.Gen4Ground did not resolve to the module that owns "
   .. "animationsFor, so every lookup below would answer nil")
ok(type(Gen4Ground.texturePatternAt) == "function",
   "Gen4Ground has no texturePatternAt -- the flipbook half of the one-shot "
   .. "pose is the subject of section 5 and would be ungraded")
ok(type(Gen4Ground.propMaterials) == "function",
   "Gen4Ground has no propMaterials -- the three draw sites would be asking "
   .. "three different questions again")
ok(type(Gen4Ground.oneShotAnimations) == "function",
   "Gen4Ground has no oneShotAnimations, so nothing keeps a flipbook door off "
   .. "the frame clock")
ok(Gen4Ground.thisDoesNotExist == nil,
   "the module answers something for a name it does not define, so a lookup "
   .. "that found a function proves nothing")
ok(type(Gen4TexAnim.materials) == "function"
   and type(Gen4TexAnim.animates) == "function",
   "Gen4TexAnim did not resolve")
ok(type(OneShot.poseIn) == "function",
   "Gen4PropOneShot did not resolve, so the slot search is not the real one")
ok(type(Gen4PropAnim.DOORS) == "table" and #Gen4PropAnim.DOORS == 20,
   "Gen4PropAnim.DOORS holds %s rows, not the twenty `doorModelIDs[]` names",
   type(Gen4PropAnim.DOORS) == "table" and #Gen4PropAnim.DOORS or "nothing")
ok(GROUND_SRC ~= nil and #GROUND_SRC > 40000,
   "src/render/Gen4Ground.lua could not be read, so the source assertions in "
   .. "sections 7 and 8 would pass over an empty string")
ok(EXTRACTOR_SRC ~= nil and #EXTRACTOR_SRC > 100000,
   "src/import/RomExtractorGen4.lua could not be read")

-- ---------------------------------------------------------------------------
section("1. the script-owned animations, derived from the door table")
-- ---------------------------------------------------------------------------
local ONE_SHOT = Gen4Ground.oneShotAnimations()
do
  local fromDoors, rows = {}, 0
  for _, row in ipairs(Gen4PropAnim.DOORS or {}) do
    for _, id in ipairs(row.ids or {}) do
      if not fromDoors[id] then rows = rows + 1 end
      fromDoors[id] = true
    end
  end
  -- A FLOOR FIRST, so emptying DOORS cannot make the comparison below vacuous.
  -- Fourteen distinct ids over the twenty doors: 5/6, 7/8/9/10, 27/28, 29/30,
  -- 33/34, 51/52 -- see Gen4PropAnim.DOORS, derived from `doorModelIDs[]`.
  ok(rows == 14,
     "the door rows name %d distinct animation ids, not the fourteen "
     .. "(5/6, 7/8/9/10, 27/28, 29/30, 33/34, 51/52) the twenty doors use",
     rows)
  ok(keys(ONE_SHOT) == rows,
     "oneShotAnimations holds %d ids and the door table names %d -- a door "
     .. "animation missing from this set is put on the frame clock and opens "
     .. "and shuts by itself", keys(ONE_SHOT), rows)
  local same = true
  for id in pairs(fromDoors) do if not ONE_SHOT[id] then same = false end end
  for id in pairs(ONE_SHOT) do if not fromDoors[id] then same = false end end
  ok(same, "oneShotAnimations is not the door table's own id set")
  -- NAMED, because this pair is the whole point of the section: they are the
  -- only BTP0 door, so they are the only ids that could reach the clock route
  -- at all.  `Gen4PropAnim.DOORS`' `elevator_door` row, ids { 51, 52 }.
  ok(ONE_SHOT[51] and ONE_SHOT[52],
     "animations 51/52 (`ele_door1_op` / `ele_door1_cl`, the elevator door) "
     .. "are not treated as script-owned, so the one flipbook door would run "
     .. "on the frame clock")
  -- ...and a non-door flipbook must NOT be in it, or the clock route loses
  -- the monitors and the escalators along with the door.
  ok(not ONE_SHOT[41] and not ONE_SHOT[15] and not ONE_SHOT[18],
     "a non-door animation (41 `pc_moni_on`, 15 `stair_pc_u01d`, 18 `wfall`) "
     .. "is treated as script-owned, which takes it off the clock and nothing "
     .. "else would ever play it")
  ok(Gen4Ground.oneShotAnimations() == ONE_SHOT,
     "oneShotAnimations rebuilds its set on every call")
end

-- ---------------------------------------------------------------------------
section("2. the two joins, re-derived from the cartridge")
-- ---------------------------------------------------------------------------
local claims, kindOf, animName, modelName
if not ROM then
  skip("no cartridge, so the two joins are not re-derived this run")
else
  local rom = NdsRom.open(ROM)
  ok(rom ~= nil, "could not open %s", tostring(ROM))
  local list  = rom and Narc.parse(rom:read(LIST_PATH))
  local anim  = rom and Narc.parse(rom:read(ANIM_PATH))
  local build = rom and Narc.parse(rom:read(MODEL_PATH))
  ok(list and anim and build,
     "one of %s / %s / %s is missing", LIST_PATH, ANIM_PATH, MODEL_PATH)
  if list and anim and build then
    -- ONE RECORD PER MODEL, which is what makes a claim usable as an index.
    -- `Gen4Ground` reads a claim as `set.models[index + 1]`, so the claim has
    -- to be a MODEL index; the list is per model and this archive is one model
    -- per member, so the two coincide here.  Asserted rather than assumed,
    -- because `fldeff.narc` is the archive where it does not hold.
    ok(list.count == build.count and list.count == 590,
       "bm_anime_list has %d members and build_model %d; both are 590, one "
       .. "record per prop model", list.count, build.count)
    local several = 0
    modelName = {}
    local tex0 = {}
    for member = 0, build.count - 1 do
      local bytes = build:get(member)
      if bytes and Gen4Graphics.isCompressed(bytes) then
        bytes = Gen4Graphics.decompress(bytes)
      end
      if bytes and bytes:sub(1, 4) == Nsbmd.MAGIC then
        local parsed = Nsbmd.parse(bytes)
        local models = (parsed or {}).models or {}
        if #models ~= 1 then several = several + 1 end
        if models[1] then modelName[member] = models[1].name end
        local sections = Nsbmd.sections(bytes)
        local t = sections and sections.TEX0
          and Gen4Models.parse(bytes, sections.TEX0) or nil
        if t then
          local names = {}
          for _, x in ipairs(t.textures or {}) do names[x.name] = true end
          tex0[member] = names
        end
      end
    end
    ok(several == 0,
       "%d build_model member(s) hold other than exactly one model, so a "
       .. "claim's number is no longer a model index and `props` would select "
       .. "the wrong prop", several)

    claims = {}
    local animated = 0
    for member = 0, list.count - 1 do
      local entry = Gen4PropAnim.parse(list:get(member))
      if entry and entry.has then
        animated = animated + 1
        for _, id in ipairs(entry.ids) do
          claims[id] = claims[id] or {}
          claims[id][#claims[id] + 1] = member
        end
      end
    end
    ok(animated == 112, "%d props carry an animation, not 112", animated)

    kindOf, animName = {}, {}
    local byKind = {}
    local patternTextures = {}
    for member = 0, anim.count - 1 do
      local bytes = anim:get(member)
      local parsed = Gen4Anim.parse(bytes)
      kindOf[member] = parsed and parsed.kind
      byKind[kindOf[member]] = (byKind[kindOf[member]] or 0) + 1
      local first = parsed and parsed.animations and parsed.animations[1]
      animName[member] = first and first.name
      if parsed and parsed.kind == "BTP0" and first then
        local tp = Gen4Anim.texturePattern(bytes, first)
        patternTextures[member] = tp and tp.textures or {}
      end
    end
    ok(anim.count == 98, "bm_anime holds %d animations, not 98", anim.count)
    ok(byKind.BCA0 == 32 and byKind.BTA0 == 43 and byKind.BTP0 == 23,
       "bm_anime is %s BCA0 / %s BTA0 / %s BTP0, not 32 / 43 / 23",
       tostring(byKind.BCA0), tostring(byKind.BTA0), tostring(byKind.BTP0))
    ok(keys(claims) == 98,
       "%d of the 98 bm_anime members are claimed; all 98 are, so nothing in "
       .. "that archive is orphaned", keys(claims))

    -- THE NAME JOIN AND THE CLAIM JOIN, counted the same way, side by side.
    local nameToIndex = {}
    for member, name in pairs(modelName) do
      if name and nameToIndex[name] == nil then nameToIndex[name] = member end
    end
    local byName, byClaim = {}, {}
    for member = 0, anim.count - 1 do
      local index = animName[member] and nameToIndex[animName[member]]
      if index then byName[index] = true end
      for _, owner in ipairs(claims[member] or {}) do byClaim[owner] = true end
    end
    ok(keys(byName) == 68,
       "the NAME join reaches %d prop models, not 68", keys(byName))
    ok(keys(byClaim) == 112,
       "the CLAIM join reaches %d prop models, not 112", keys(byClaim))
    -- The control the whole subject rests on: the claim is a strict superset.
    -- If a model were reachable by name and not by claim, a union would be the
    -- wrong fix and the name route could not simply be widened.
    local nameOnly = 0
    for index in pairs(byName) do if not byClaim[index] then nameOnly = nameOnly + 1 end end
    ok(nameOnly == 0,
       "%d model(s) are reachable by NAME and not by CLAIM -- the claim is "
       .. "supposed to be the superset, and if it is not then widening the "
       .. "join is not the whole answer", nameOnly)

    local claimOnly = { BCA0 = 0, BTA0 = 0, BTP0 = 0 }
    local total = 0
    for index in pairs(byClaim) do
      if not byName[index] then
        total = total + 1
        local seen = {}
        for member = 0, anim.count - 1 do
          for _, owner in ipairs(claims[member] or {}) do
            if owner == index then seen[kindOf[member]] = true end
          end
        end
        for kind in pairs(seen) do
          claimOnly[kind] = (claimOnly[kind] or 0) + 1
        end
      end
    end
    ok(total == 44,
       "%d prop models are claim-only, not the 44 this pass is about", total)
    ok(claimOnly.BTA0 == 12 and claimOnly.BTP0 == 10,
       "the claim-only texture split is %s BTA0 / %s BTP0, not 12 / 10",
       tostring(claimOnly.BTA0), tostring(claimOnly.BTP0))
    ok(claimOnly.BCA0 == 22,
       "%s claim-only models carry a joint animation, not 22 -- those are the "
       .. "ones `oneShotProps` already reached", tostring(claimOnly.BCA0))

    -- THE WATERFALLS, named, because they are the visible half of the fault.
    local falls, mismatched = 0, 0
    for _, owner in ipairs(claims[18] or {}) do
      falls = falls + 1
      if modelName[owner] ~= animName[18] then mismatched = mismatched + 1 end
    end
    ok(animName[18] == "wfall",
       "animation 18 is named %q, not `wfall`", tostring(animName[18]))
    ok(falls == 6 and mismatched == 6,
       "animation 18 (`wfall`) claims %d model(s) of which %d do not share "
       .. "its name; it claims six and NONE of them is named `wfall`, which "
       .. "is why the name join left every waterfall static", falls, mismatched)

    -- ---------------------------------------------------------------------
    section("3. the claim-only flipbooks' pictures are in their own TEX0")
    -- ---------------------------------------------------------------------
    -- The extractor decodes a BTP0's alternate frames out of the MODEL's own
    -- texture section.  That was measured for the 16 name-joined models; this
    -- is the same measurement for the ten the claim adds, and it is the fact
    -- that makes widening the extractor a longer list of names rather than a
    -- second archive to find.
    local pairsChecked, misses, noTex = 0, 0, 0
    for index in pairs(byClaim) do
      if not byName[index] then
        for member = 0, anim.count - 1 do
          if kindOf[member] == "BTP0" then
            for _, owner in ipairs(claims[member] or {}) do
              if owner == index then
                pairsChecked = pairsChecked + 1
                local have = tex0[index]
                if not have then noTex = noTex + 1 end
                for _, name in ipairs(patternTextures[member] or {}) do
                  if not (have and have[name]) then misses = misses + 1 end
                end
              end
            end
          end
        end
      end
    end
    ok(pairsChecked == 15,
       "%d claim-only model/BTP0 pairs were examined, not the fifteen this "
       .. "cartridge has -- a scan that stopped matching reports a clean zero "
       .. "over nothing", pairsChecked)
    ok(noTex == 0, "%d claim-only flipbook model(s) have no TEX0 at all", noTex)
    ok(misses == 0,
       "%d texture name(s) a claim-only BTP0 animation keys on are absent "
       .. "from the claiming model's own TEX0, so the frames cannot be "
       .. "decoded there and the flipbook needs another source", misses)
  end
end

-- ---------------------------------------------------------------------------
section("4. animationsFor -- the union, executed on records built here")
-- ---------------------------------------------------------------------------
-- Every record below has the cache's real shape and none of it comes from a
-- cache, so this section fails on a tree with no cartridge and no install.
local function bta(member, name, target, owners)
  return { kind = "BTA0", member = member, name = name, frames = 8,
           props = owners,
           srt = { { name = target, translateT = { 0, -0.5, -1 } } } }
end
local function btp(member, name, target, textures, owners)
  return { kind = "BTP0", member = member, name = name, frames = 8,
           props = owners,
           pattern = { textures = textures,
                       targets = { { name = target, keys = {
                         { frame = 0, texture = 0 },
                         { frame = 4, texture = 1 } } } } } }
end

local DOOR_TEX = { "ele_door.1", "ele_door.2", "ele_door.3", "ele_door.4" }
local DOOR_IMAGES = { ["ele_door.1"] = "a/1.png", ["ele_door.2"] = "a/2.png",
                      ["ele_door.3"] = "a/3.png", ["ele_door.4"] = "a/4.png" }
local MONI_TEX = { "pc_moni.1", "pc_moni.2" }
local MONI_IMAGES = { ["pc_moni.1"] = "b/1.png", ["pc_moni.2"] = "b/2.png" }

-- index 0 name-only, 1 claim-only BTA0, 2 both, 3 the flipbook door with its
-- pictures, 4 the same door with the pictures missing, 5 a clock-driven
-- flipbook, 6 a joint door.
local MODELS = {
  [1] = { name = "named_prop" },
  [2] = { name = "claim_prop" },
  [3] = { name = "both_prop" },
  [4] = { name = "ele_door1", patternImages = DOOR_IMAGES },
  [5] = { name = "ele_door1_nopics" },
  [6] = { name = "table_l01", patternImages = MONI_IMAGES },
  [7] = { name = "t1_door1" },
  [8] = { name = "ele_door1_only", patternImages = DOOR_IMAGES },
}
local ANIMS = {
  bta(100, "named_prop",  "water", nil),
  bta(101, "not_a_model", "water", { 1 }),
  bta(102, "both_prop",   "water", { 2 }),
  bta(103, "scroll_only", "glass", { 3 }),
  btp(51, "ele_door1_op", "panel", DOOR_TEX, { 3, 4, 7 }),
  btp(52, "ele_door1_cl", "panel", DOOR_TEX, { 3, 4, 7 }),
  btp(41, "pc_moni_on",   "screen", MONI_TEX, { 5 }),
  { kind = "BCA0", member = 7, name = "door_op", frames = 8, props = { 6 },
    tracks = { { index = 0, frames = 8, matrices = "" } } },
}

local function fixture()
  local g = setmetatable({}, Gen4Ground)
  g.buildingSet = { models = MODELS }
  g.animsByName, g.animsByProp, g.animsByMember = {}, {}, {}
  for _, record in ipairs(ANIMS) do
    if record.name then
      g.animsByName[record.name] = g.animsByName[record.name] or {}
      table.insert(g.animsByName[record.name], record)
    end
    for _, index in ipairs(record.props or {}) do
      g.animsByProp[index] = g.animsByProp[index] or {}
      table.insert(g.animsByProp[index], record)
    end
    if record.member and g.animsByMember[record.member] == nil then
      g.animsByMember[record.member] = record
    end
  end
  return g
end

local ground = fixture()
do
  local function count(index, archive)
    local list = ground:animationsFor(index, archive)
    return list and #list or 0
  end
  -- THE CONTROL: the route that already worked must still work, or the union
  -- has replaced the name join rather than widened it.
  ok(count(0) == 1,
     "a model reachable only by NAME resolved %d animation(s), not 1 -- the "
     .. "route that worked before has been broken", count(0))
  -- THE NEW BEHAVIOUR.  Before pass 190 this answered nil, which is what left
  -- the waterfalls, the escalators and the slopes in the static bake.
  ok(count(1) == 1,
     "a model reachable only by CLAIM resolved %d animation(s), not 1 -- this "
     .. "is the 44-model gap, and `wfall3_4` is one of them", count(1))
  -- Dedupe: the same record must not be evaluated twice into one material.
  ok(count(2) == 1,
     "a model reachable BOTH ways resolved %d animation(s); it is one record "
     .. "and a union that does not dedupe evaluates it twice", count(2))
  -- THE EXCLUSION, which is what keeps the door from running itself.
  --
  -- Model 7 is claimed by the two door animations and NOTHING else, and it
  -- carries their pictures -- so everything the clock route needs is present
  -- and the only reason to refuse is that the animations are script-owned.
  -- Aimed at this model rather than at model 4, which has no pictures: model 4
  -- is refused by `animates` whatever the exclusion does, so an assertion on
  -- it passes for the wrong reason and a plant removing the exclusion would
  -- not reach it.
  ok(ground:animationsFor(7) == nil,
     "the flipbook door resolved clock-driven animations; animations 51/52 "
     .. "are script-owned, and on the clock the door opens and shuts for ever")
  ok(ground:animationsFor(4) == nil,
     "a claimed flipbook with no pictures in the cache resolved clock-driven "
     .. "animations; there is nothing to draw and a rebake every frame buys "
     .. "an unchanging door")
  -- ...and the disjointness control: a flipbook that is NOT a door still runs
  -- on the clock, so the exclusion is narrow rather than "no BTP0 ever".
  ok(count(5) == 1,
     "a clock-driven flipbook (`pc_moni_on`) resolved %d animation(s), not 1 "
     .. "-- excluding every BTP0 instead of the door animations would stop "
     .. "the monitors and the escalators as well", count(5))
  -- A claimed flipbook whose pictures the cache does not carry stays out, the
  -- same answer `Gen4TexAnim.animates` gives: there is nothing to draw.
  ok(ground:animationsFor(3) ~= nil,
     "a model claimed by a scroll AND a flipbook door resolved nothing; the "
     .. "scroll alone should still animate it")
  ok(ground:animationsFor(1, "fldeff") == nil,
     "a fldeff index resolved a buildings animation -- the two archives share "
     .. "numbers and mean different models")
  ok(ground:animationsFor(99) == nil,
     "an index with no model resolved animations")
  -- A SECOND RECORD ON ONE MODEL comes back whole: model 3 is claimed by the
  -- scroll and by both door animations, and only the scroll may survive.
  local list = ground:animationsFor(3)
  ok(list and #list == 1 and list[1].member == 103,
     "model 3 resolved %s animation(s) and the first is member %s; only the "
     .. "scroll (103) belongs on the clock",
     list and #list or "nil", list and list[1] and tostring(list[1].member))
end

-- ---------------------------------------------------------------------------
section("5. texturePatternAt -- the flipbook pose, and the clamp")
-- ---------------------------------------------------------------------------
do
  -- The two keys must name DIFFERENT pictures, or every comparison below
  -- compares a value with itself and the section cannot fail.
  ok(DOOR_IMAGES[DOOR_TEX[1]] ~= DOOR_IMAGES[DOOR_TEX[2]],
     "the fixture's two flipbook keys resolve to the same picture, so this "
     .. "section cannot tell a moving door from a still one")
  local first = ground:texturePatternAt({ animation = 51, frame = 0 }, 3)
  ok(type(first) == "table" and first.panel
     and first.panel.image == DOOR_IMAGES[DOOR_TEX[1]],
     "frame 0 of animation 51 wore %s, not the first key's picture %s",
     tostring(type(first) == "table" and first.panel and first.panel.image),
     DOOR_IMAGES[DOOR_TEX[1]])
  local moved = ground:texturePatternAt({ animation = 51, frame = 4 }, 3)
  ok(type(moved) == "table" and moved.panel
     and moved.panel.image == DOOR_IMAGES[DOOR_TEX[2]],
     "frame 4 wore %s, not the second key's picture %s -- the frame argument "
     .. "is being ignored and the door would not move at all",
     tostring(type(moved) == "table" and moved.panel and moved.panel.image),
     DOOR_IMAGES[DOOR_TEX[2]])
  -- THE HELD STATE.  `Gen4PropOneShot.advance` clamps a finished one-shot at
  -- `frame == frames`, and `Gen4TexAnim.materials` takes `frame % period` --
  -- so an unclamped read of frame 8 of an 8-frame animation wraps to key zero
  -- and snaps the door shut the instant it finishes opening.
  local held = ground:texturePatternAt({ animation = 51, frame = 8 }, 3)
  ok(type(held) == "table" and held.panel
     and held.panel.image == DOOR_IMAGES[DOOR_TEX[2]],
     "a finished one-shot (frame 8 of 8) wore %s; it must hold the LAST key "
     .. "%s, and wearing the first key %s again is the door snapping shut as "
     .. "soon as it has opened",
     tostring(type(held) == "table" and held.panel and held.panel.image),
     DOOR_IMAGES[DOOR_TEX[2]], DOOR_IMAGES[DOOR_TEX[1]])
  local past = ground:texturePatternAt({ animation = 51, frame = 400 }, 3)
  ok(type(past) == "table" and past.panel
     and past.panel.image == DOOR_IMAGES[DOOR_TEX[2]],
     "a frame far past the end did not clamp to the last key")
  local before = ground:texturePatternAt({ animation = 51, frame = -3 }, 3)
  ok(type(before) == "table" and before.panel
     and before.panel.image == DOOR_IMAGES[DOOR_TEX[1]],
     "a negative frame did not clamp to the first key")
  -- The refusals, each for its own reason.
  ok(ground:texturePatternAt({ animation = 51, frame = 0 }, 4) == nil,
     "a model with no patternImages produced flipbook materials; a cache "
     .. "imported before those frames were written has the animation and not "
     .. "the pictures, and drawing the nearest one looks deliberate")
  ok(ground:texturePatternAt({ animation = 7, frame = 0 }, 6) == nil,
     "a BCA0 slot produced flipbook materials; the joint path owns it and "
     .. "answering here would pose the same door twice")
  ok(ground:texturePatternAt({ animation = 9999, frame = 0 }, 3) == nil,
     "an unknown animation produced flipbook materials")
  ok(ground:texturePatternAt(nil, 3) == nil, "a nil slot produced materials")
  ok(ground:texturePatternAt({ animation = 51, frame = 0 }, nil) == nil,
     "a nil model index produced materials")
end

-- ---------------------------------------------------------------------------
section("6. oneShotProps -- which props a script can pose")
-- ---------------------------------------------------------------------------
do
  local fresh = fixture()
  local set = fresh:oneShotProps()
  ok(type(set) == "table", "oneShotProps answered %s", type(set))
  -- THE CONTROL: the joint arm, which is what passes 185-188 built.
  ok(set[6] == true,
     "a model claimed by a joint animation with tracks is not one-shot "
     .. "capable, so nineteen of the twenty doors would stop moving")
  -- THE NEW ARM.
  ok(set[3] == true,
     "the flipbook door is not one-shot capable (model 3 answered %s), so "
     .. "`ele_door1` goes to the static bake where the draw never asks for a "
     .. "pose at all", tostring(set[3]))
  -- ...but only where the pictures exist.  Model 4 is the SAME door claimed by
  -- the same two animations with no patternImages, so `animates` says no and
  -- it stays baked rather than being drawn live every frame for no motion.
  -- The pair is the discriminator: an arm that answered yes on the claim
  -- alone would mark both.
  ok(set[4] ~= true,
     "a claimed flipbook whose pictures the cache does not carry was called "
     .. "one-shot capable (model 4 answered %s); it would be drawn live every "
     .. "frame and never move", tostring(set[4]))
  -- A clock-driven flipbook is NOT a one-shot: `animationsFor` answers for it
  -- and counting it here as well would make the two arms say the same thing.
  ok(set[5] ~= true,
     "a clock-driven flipbook (`pc_moni_on`) was counted as a script-owned "
     .. "one-shot, which is the clock route and this one answering the same "
     .. "question")
  ok(fresh:oneShotProps() == set, "oneShotProps rebuilds its set every call")
  -- AND THE TWO SELECTIONS STAY COMPLEMENTS, asked of the methods rather than
  -- recomputed here -- shape 6a of claude/check_design_lessons.md.
  for _, index in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 99 }) do
    local object = { model = index }
    ok(fresh:shouldBake(object) == (not fresh:shouldAnimate(object)),
       "shouldBake and shouldAnimate agree for model %d, so a prop is in "
       .. "both passes or in neither", index)
  end
  ok(fresh:shouldAnimate({ model = 3 }) == true,
     "the flipbook door is not selected for the animated pass")
  ok(fresh:shouldAnimate({ model = 1 }) == true,
     "a claim-only scroll model is not selected for the animated pass")
  -- ...and the door-only model, which NO clock route answers for, is still in
  -- the animated pass -- through `oneShotProps` alone.  If it were not, the
  -- draw would never ask it for a pose and the flipbook would never play.
  ok(fresh:shouldAnimate({ model = 7 }) == true,
     "the flipbook door whose only animations are script-owned is not "
     .. "selected for the animated pass, so the one route that could play it "
     .. "never runs")
end

-- ---------------------------------------------------------------------------
section("7. propMaterials -- one question, three draw sites")
-- ---------------------------------------------------------------------------
do
  local g = fixture()
  local object = { model = 3, archive = nil }
  -- No one-shot running: the scroll alone.
  local idle = g:propMaterials(object, 0)
  ok(type(idle) == "table" and idle.glass and not idle.panel,
     "with no one-shot running the prop wore %s; the clock scroll `glass` "
     .. "alone is right and a `panel` here means the door animates by itself",
     idle and (idle.panel and "panel too" or "glass") or "nothing")
  -- With one running: BOTH, because replacing the table would drop the scroll.
  g.oneShots = { [1] = { tag = 1, animation = 51, frames = 8, frame = 4,
                         object = object } }
  local both = g:propMaterials(object, 0)
  ok(type(both) == "table" and both.glass and both.panel,
     "with a one-shot running the prop wore %s; it must carry the clock "
     .. "scroll AND the script flipbook, and assigning rather than merging "
     .. "drops whichever was built first",
     both and ((both.glass and "glass " or "") .. (both.panel and "panel" or ""))
       or "nothing")
  ok(both and both.panel and both.panel.image == DOOR_IMAGES[DOOR_TEX[2]],
     "the merged flipbook is not at the one-shot's own frame")
  ok(both and both.glass and both.glass.uv ~= nil,
     "the merged scroll lost its uv matrix")
  -- A one-shot on a DIFFERENT object must not reach this one.
  local other = g:propMaterials({ model = 3, archive = nil }, 0)
  ok(type(other) == "table" and other.glass and not other.panel,
     "a one-shot running on another object posed this one; slots are matched "
     .. "by object identity")
  -- fldeff takes neither route: a different archive, same numbers.
  ok(g:propMaterials({ model = 3, archive = "fldeff" }, 0) == nil,
     "a fldeff prop wore buildings materials")
  ok(g:propMaterials(nil, 0) == nil, "a nil object wore materials")

  -- THE JOIN ASSERTED ON THE SOURCE, because every assertion above calls
  -- `propMaterials` directly and none of them can see whether the draw does.
  -- Shape 6c of claude/check_design_lessons.md.
  local src = GROUND_SRC or ""
  local calls = 0
  for _ in src:gmatch("self:propMaterials%s*%(") do calls = calls + 1 end
  ok(calls == 3,
     "Gen4Ground calls propMaterials %d time(s); the static pass, the flat "
     .. "pass and the animated bake are three sites and each must ask the "
     .. "same question", calls)
  local direct = 0
  for _ in src:gmatch("Gen4TexAnim%.materials%s*%(") do direct = direct + 1 end
  ok(direct == 2,
     "Gen4TexAnim.materials is called %d time(s) in Gen4Ground; exactly two "
     .. "belong there (propMaterials and texturePatternAt) and a third is a "
     .. "draw site that has gone back to spelling the question for itself",
     direct)
  -- The constructor's claim index, which the fixture above stands in for.
  local built = src:match("self%.animsByProp%s*=%s*{}(.-)\n  self%.animated")
  ok(built ~= nil and #built < 4000,
     "could not locate the constructor's animation indexing between "
     .. "`animsByProp = {}` and `self.animated`")
  if built then
    ok(built:find("record%.props") ~= nil,
       "the constructor does not read `record.props`, so the claim index is "
       .. "empty and `animationsFor`'s second route answers nothing")
    ok(built:find("self%.animsByProp%[index%]") ~= nil,
       "the constructor does not key the claim index by the prop model index")
    ok(built:find("self%.animsByName%[record%.name%]") ~= nil,
       "the constructor stopped building the name index")
  end
  -- Anchored on the signature and on an `end` AT COLUMN ONE, which only the
  -- function's own terminator is, and length-bounded: a lazy match that
  -- overran would still be non-nil and the assertions below would then be
  -- graded against some other function (shape 3a).
  local fn = src:match("function Gen4Ground:animationsFor%(index, archive%)(.-)\r?\nend")
  ok(fn ~= nil and #fn < 2500 and fn:find("return list, images") ~= nil,
     "could not locate animationsFor's body (%s characters)",
     fn and #fn or "no match")
  if fn and #fn < 2500 then
    ok(fn:find("self%.animsByProp") ~= nil and fn:find("self%.animsByName") ~= nil,
       "animationsFor does not consult both joins")
    ok(fn:find("oneShotAnimations%s*%(") ~= nil,
       "animationsFor does not exclude the script-owned animations, so a "
       .. "flipbook door would be driven by the frame clock")
  end
end

-- ---------------------------------------------------------------------------
section("8. the extractor writes a flipbook's frames for a CLAIMED model")
-- ---------------------------------------------------------------------------
do
  local src = EXTRACTOR_SRC or ""
  -- Sliced between two anchors that could only bound the intended region --
  -- shape 3a of claude/check_design_lessons.md -- and length-bounded, because
  -- a lazy match that overran would still be non-nil.
  local body = src:match("local modelIndex = #set%.models(.-)set%.models%[#set%.models %+ 1%] = packed")
  ok(body ~= nil,
     "could not locate the pattern-image region between `modelIndex` and the "
     .. "model append; the extractor's claim route is ungraded")
  ok(body == nil or #body < 6000,
     "the pattern-image region extracted %d characters, which is more than "
     .. "that block is -- the slice has run past its end", body and #body or 0)
  if body and #body < 6000 then
    ok(body:find("record%.props") ~= nil,
       "the extractor's pattern-image loop does not read `record.props`, so a "
       .. "claim-only BTP0 model's frames are still never decoded")
    ok(body:find("owner == modelIndex") ~= nil,
       "the claim is not compared against this model's own index")
    -- AND THE CONDITION ITSELF, not merely that the pieces are present.
    --
    -- Found by a plant that landed and did NOT fail: dropping `or claimed`
    -- from the guard leaves the whole `record.props` loop above it in place
    -- as dead code, so the three assertions above all still matched while
    -- the claim route had been switched off.  Shape 6c of
    -- claude/check_design_lessons.md reproduced inside the check -- two rows
    -- meet in one boolean and only one end was graded.
    local cond = body:match("if record%.pattern and ([^\r\n]+) then")
    ok(cond ~= nil,
       "could not read the pattern-image guard's own condition")
    ok(cond == nil or (cond:find("claimed") ~= nil
                       and cond:find("record%.name == model%.name") ~= nil
                       and cond:find(" or ") ~= nil),
       "the pattern-image guard reads %q; it has to admit a model on EITHER "
       .. "its own name or the cartridge's claim, and a guard that names only "
       .. "one of the two leaves the other's code in place doing nothing",
       tostring(cond))
  end
  -- AND THE CLAIM IS RECORDED ON EVERY ANIMATION, not only the joint ones --
  -- pass 187's fix, which everything above depends on.  Asserted on the loop
  -- rather than on a cache, because a cache can be older than the fix.
  local claimLoop = src:match(
    "local claims = entry%.claims(.-)for _, item in ipairs%(pending%)")
  ok(claimLoop ~= nil and #claimLoop < 3000,
     "could not locate the claim-recording region between `local claims = "
     .. "entry.claims` and the pending loop (%s characters)",
     claimLoop and #claimLoop or "no match")
  if claimLoop and #claimLoop < 3000 then
    ok(claimLoop:find("ipairs%(set%.animations%)") ~= nil,
       "the claim-recording loop does not walk `set.animations`; walking "
       .. "`pending` records the claim for the 32 BCA0 members alone and "
       .. "leaves the 43 BTA0 and 23 BTP0 without it")
    ok(claimLoop:find("record%.props = owners") ~= nil,
       "the claim-recording loop does not write `record.props`")
  end
end

-- ---------------------------------------------------------------------------
section("9. the installed cache -- which of the two known states it is in")
-- ---------------------------------------------------------------------------
-- READ STRUCTURALLY, AND THAT IS NOT A STYLE CHOICE.
--
-- The cache writer has TWO spellings of every key: the ordinary `props = {`
-- and, for a value too large to sit inside the chunk it is being written
-- into, `__t["props"] = {`. Counting the live file with `grep -o 'props = '`
-- answers 95 of 98 and `'tracks = '` answers 47 where the previous import
-- gave 52 -- so a textual count reads as three members the claim map misses
-- and a five-record regression, when the structural counts are 98 and 52 and
-- nothing is missing or lost. 95 + 3 = 98; 47 + 5 = 52.
--
-- Verified against both of this repository's real caches: the live install
-- (a full re-import, all 98 claimed) and the older reference cache (the 32
-- BCA0 records only). See 3c-ii of claude/check_design_lessons.md.
if not CACHE then
  skip("no cache, so the installed claim coverage is not read this run")
else
  local models = loadTable(CACHE, "gen4_models")
  local field = (((models or {}).sets or {}).field or {})
  local animations = field.animations or {}
  ok(#animations == 98,
     "the cache's field animation set holds %d records, not 98; the rest of "
     .. "this section would measure a fraction of the archive", #animations)
  if #animations == 98 then
    local withProps, byKind, propsByKind = 0, {}, {}
    for _, record in ipairs(animations) do
      byKind[record.kind] = (byKind[record.kind] or 0) + 1
      if record.props then
        withProps = withProps + 1
        propsByKind[record.kind] = (propsByKind[record.kind] or 0) + 1
      end
    end
    -- TWO STATES ARE LEGITIMATE and a third is not.  Pass 187 writes the claim
    -- on every animation; an import that ran before it wrote the claim only
    -- inside the BCA0 loop, so a cache is either all-98 or exactly-32.
    -- Anything between is a claim table that has stopped resolving, which is
    -- the failure this assertion exists for.
    local full = (withProps == 98)
    local preFix = (withProps == (byKind.BCA0 or -1)
                    and propsByKind.BCA0 == byKind.BCA0
                    and (propsByKind.BTA0 or 0) == 0
                    and (propsByKind.BTP0 or 0) == 0)
    ok(full or preFix,
       "%d of 98 field animations carry `props` (%s BCA0, %s BTA0, %s BTP0). "
       .. "A current cache carries all 98 and a cache imported before pass "
       .. "187 carries exactly the %s BCA0 records; anything else means the "
       .. "claim table has stopped resolving for part of the archive",
       withProps, tostring(propsByKind.BCA0), tostring(propsByKind.BTA0),
       tostring(propsByKind.BTP0), tostring(byKind.BCA0))
    if full then
      report("this cache carries the claim on all 98 animations")
    elseif preFix then
      report("this cache carries the claim on the %d BCA0 animations only -- "
             .. "it predates pass 187's extractor fix, so the 22 "
             .. "texture-animated claim-only props (the waterfalls, the "
             .. "escalators, the slopes, the elevator door) cannot move until "
             .. "it is re-imported", withProps)
    end
    -- The flipbook pictures, the same way: 16 models today, 26 once the
    -- extractor's claim route has run.
    local built = (((models or {}).sets or {}).buildings or {}).models or {}
    local withImages = 0
    for _, packed in ipairs(built) do
      if packed.patternImages and keys(packed.patternImages) > 0 then
        withImages = withImages + 1
      end
    end
    ok(#built == 590, "the cache holds %d build models, not 590", #built)
    ok(withImages == 16 or withImages == 26,
       "%d build models carry flipbook pictures. Sixteen is the name join "
       .. "alone and 26 is the name join plus the ten claim-only BTP0 models; "
       .. "any other number means the picture extraction is matching "
       .. "something else", withImages)
    report("%d of 590 build models carry flipbook pictures (16 = name join "
           .. "only, 26 = after the claim route)", withImages)
  end
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
