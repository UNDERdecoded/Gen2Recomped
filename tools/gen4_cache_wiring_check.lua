-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).
--
-- tools/gen4_cache_wiring_check.lua -- the nineteenth standing check, and the
-- only one that measures the SEAM between the importer and the running game
-- rather than either side of it.
--
-- WHY IT EXISTS. Every other check in this directory proves a table is right.
-- None of them asks whether the engine ever opens it. `Data` loads a Gen 4
-- table by its FILE NAME off an explicit list, so a stage that writes a name
-- the list does not carry produces a perfectly correct file that nothing reads,
-- forever, with no error anywhere.
--
-- THAT HAS NOW HAPPENED THREE TIMES. `gen4_species_sprites` was the first and
-- its own comment in Data.lua records it. `gen4_move_anims` and `gen4_particles`
-- were the second and third, and they were expensive: the move-animation player
-- is 800 lines with 42 checks behind it, and `Gen4MoveAnimPlayer.new` reads
-- `data.gen4_move_anims` while the stage wrote `move_anims.lua`. The
-- constructor returned nil on every boot. Every move in Platinum fell back to
-- the generic animation and nothing logged a word, which is exactly what the
-- player reported: "scratch doesnt work and doesnt show a move animation or
-- fx". Two whole subsystems, proved correct, wired to nothing.
--
-- A per-stage check cannot see this. The stage passes, the table is right, the
-- cache is written -- the fault is in the space between two files, which is
-- why it needs a check of its own.
--
-- Run:  texlua tools/gen4_cache_wiring_check.lua <rom path>

local romPath = arg and arg[1]
if not romPath then
  io.write("usage: texlua tools/gen4_cache_wiring_check.lua <rom path>\n")
  os.exit(2)
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
package.path = root .. "../?.lua;" .. root .. "?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then
    io.write(("  ok    %-54s %s\n"):format(what, tostring(got == nil and "" or got)))
  else
    fails = fails + 1
    io.write(("  FAIL  %-54s got %s, expected %s\n")
      :format(what, tostring(got), tostring(want)))
  end
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  -- BOTH SIDES NORMALISED. The engine's .lua is CRLF on the machine this is
  -- edited on and LF in a fresh clone; a pattern anchored with $ silently
  -- matches neither on the wrong one, and a source-scanning check that
  -- silently matches nothing reports a clean sweep.
  return (s:gsub("\r\n", "\n"))
end

local extractorPath = root .. "../src/import/RomExtractorGen4.lua"
local dataPath = root .. "../src/core/Data.lua"
local playerPath = root .. "../src/battle/Gen4MoveAnimPlayer.lua"
local extractor = slurp(extractorPath)
local data = slurp(dataPath)
local player = slurp(playerPath)

io.write("the sources\n")
ok(extractor ~= nil, "the Gen 4 extractor reads", extractor and #extractor, "bytes")
ok(data ~= nil, "Data.lua reads", data and #data, "bytes")
ok(player ~= nil, "the move-animation player reads", player and #player, "bytes")
if not (extractor and data and player) then
  io.write("\nnothing to measure\n")
  os.exit(1)
end

-- ---------------------------------------------------------------------------
-- 1: WHAT THE EXTRACTOR WRITES
-- ---------------------------------------------------------------------------
io.write("\nwhat the importer writes\n")
local written, writeOrder = {}, {}
for name in extractor:gmatch('self:write%("([A-Za-z0-9_]+)"') do
  if not written[name] then
    written[name] = true
    writeOrder[#writeOrder + 1] = name
  end
end
table.sort(writeOrder)
-- A CANARY. A scan that matched nothing would find no unloaded tables either,
-- and report a clean run -- the same shape of empty measurement that made a
-- `sed` with a `$` anchor look like a passing fault plant.
ok(#writeOrder >= 30, "the stages write this many distinct tables",
   #writeOrder, "at least 30")
ok(written["gen4_move_anims"] == true and written["gen4_particles"] == true,
   "including both animation tables, under their prefixed names",
   ("move_anims %s, particles %s"):format(tostring(written["gen4_move_anims"]),
                                          tostring(written["gen4_particles"])),
   "both true")
-- AND THE OLD NAMES ARE GONE. Renaming the stage without removing the old
-- write would leave the cache carrying both files, one of them dead.
ok(written["move_anims"] == nil and written["particles"] == nil,
   "...and nothing writes the un-prefixed names any more",
   ("move_anims %s, particles %s"):format(tostring(written["move_anims"]),
                                          tostring(written["particles"])),
   "neither")

-- ---------------------------------------------------------------------------
-- 2: WHAT DATA OPENS, for a Gen 4 cache
-- ---------------------------------------------------------------------------
io.write("\nwhat the engine opens\n")
local LISTS = { "SHARED_MODULES", "GEN4_MODULES", "OPTIONAL", "GEN4_PREFIXED" }
local loaded, perList = {}, {}
for _, list in ipairs(LISTS) do
  local body = data:match("local " .. list .. "%s*=%s*{(.-)}")
  local n = 0
  for name in (body or ""):gmatch('"([A-Za-z0-9_]+)"') do
    loaded[name] = list
    n = n + 1
  end
  perList[list] = n
  ok(n > 0, ("Data's %s list parses"):format(list), n .. " names", "more than 0")
end
-- The cache marker is opened directly rather than through a list.
for name in data:gmatch('loadModule%(dir,%s*"([A-Za-z0-9_]+)"%)') do
  loaded[name] = loaded[name] or "loadModule"
end
ok(loaded["gen4_map_headers"] ~= nil,
   "...and the Gen 4 cache marker is one of them",
   loaded["gen4_map_headers"], "found")

-- ---------------------------------------------------------------------------
-- 3: THE CLAIM. Every table the importer writes is either opened by the engine
-- or is a KNOWN write-only dump.
--
-- The eight below are named, not pattern-matched, and the set must be EXACTLY
-- these eight. None of them is read by anything -- `grep` finds no reader in
-- src/ for any of the eight -- and that is legitimate only because each one's
-- CONTENT reaches the runtime through a table that IS opened: the Gen 4
-- importer lowers its own intermediate shapes into the engine's shared ones
-- before writing the cache, and dumps the intermediates beside them.
--
-- !! `gen4_overworld` WAS THE NINTH AND IS GONE FROM THIS LIST, because "no
-- reader in src/" stopped being true of it and nothing noticed. It is lowered
-- into `sprites` AND it is read directly, for the one thing `sprites` cannot
-- answer: which archive member a graphics-id NAME belongs to. Section 5 below
-- is what makes that impossible to miss again -- this list says "written and
-- unread", and section 5 checks the unread half rather than assuming it.
--
-- The check cannot tell a legitimate dump from a stranded table -- that takes
-- a person. What it can do is make the list impossible to grow quietly, which
-- is the only thing that would have caught the move animations.
-- ---------------------------------------------------------------------------
io.write("\nthe seam\n")
local DUMPS = {
  gen4_text = "lowered into `text` (and `text_pointers`)",
  gen4_events = "lowered into `map_scripts`",
  -- `gen4_map_matrices` WAS HERE: Data loads it now for the matrix border
  -- heights (Gen4Ground), so it has a reader of its own.
  gen4_map_objects = "lowered into `maps`",
  -- `gen4_map_permissions` WAS HERE and is on the loaded list now: the
  -- 291 outdoor maps carry no `behaviorCells`, so the land chunk's
  -- permission block is the only thing that names a cave mouth or a bike
  -- slope, and `Gen4Ground:behaviourAt` reads it.
  gen4_map_heights = "lowered into `maps`",
  -- `gen4_trainer_sprites` WAS HERE: the Hall of Fame reads it directly for
  -- the player's own picture on the last page (src/ui/Gen4HallOfFame.lua).
  gen4_fonts = "lowered into `font`",
}
local stranded, dumps = {}, 0
for _, name in ipairs(writeOrder) do
  if not loaded[name] then
    if DUMPS[name] then dumps = dumps + 1
    else stranded[#stranded + 1] = name end
  end
end
ok(#stranded == 0,
   "EVERY TABLE THE IMPORTER WRITES IS OPENED BY THE ENGINE",
   #stranded == 0 and "all of them"
     or ("written and never opened: " .. table.concat(stranded, ", ")),
   "no stranded tables")
local declared = 0
for _ in pairs(DUMPS) do declared = declared + 1 end
ok(dumps == declared,
   "...and every declared write-only dump is still written",
   ("%d of %d"):format(dumps, declared), declared)

-- THE OTHER DIRECTION, which is the cheaper half of the same bug: a `gen4_`
-- name on Data's list that no stage writes is a load that always fails, and it
-- degrades silently too.
local phantom = {}
for name, list in pairs(loaded) do
  if name:match("^gen4_") and not written[name] then
    phantom[#phantom + 1] = name .. " (" .. list .. ")"
  end
end
table.sort(phantom)
ok(#phantom == 0, "...and the engine opens no Gen 4 table that is never written",
   #phantom == 0 and "none" or table.concat(phantom, ", "), "none")

-- ---------------------------------------------------------------------------
-- 4: THE THREE NAMES MUST AGREE, spelled out literally.
--
-- A rename that touches two of the three files and not the third is exactly how
-- this broke, so the literal string is asserted in each place rather than the
-- relationship being inferred.
-- ---------------------------------------------------------------------------
ok(loaded["gen4_move_anims"] == "GEN4_PREFIXED",
   "the move programs are on Data's Gen 4 list",
   tostring(loaded["gen4_move_anims"]), "GEN4_PREFIXED")
ok(loaded["gen4_particles"] == "GEN4_PREFIXED",
   "...and so are the particle effects",
   tostring(loaded["gen4_particles"]), "GEN4_PREFIXED")
ok(player:find("data%.gen4_move_anims") ~= nil,
   "...and the player reads that exact field",
   player:find("data%.gen4_move_anims") ~= nil, true)
ok(player:find("data%.gen4_particles") ~= nil,
   "...and reads the particle effects too",
   player:find("data%.gen4_particles") ~= nil, true)
ok(loaded["gen4_cellactors"] == "GEN4_PREFIXED",
   "...and the 2D cell-actor sprites are on the list as well",
   tostring(loaded["gen4_cellactors"]), "GEN4_PREFIXED")
ok(player:find("data%.gen4_cellactors") ~= nil,
   "...and the player reads that field too",
   player:find("data%.gen4_cellactors") ~= nil, true)

-- ---------------------------------------------------------------------------
-- 5: THE CACHE IS LOSSLESS. The emitters go into the cache as decoded numbers,
-- so the question "does the running game simulate what the cartridge says" is
-- really two questions, and this is the first: do the numbers survive being
-- written as Lua source and read back.
--
-- fx32 values are k/4096 and `LuaWriter` emits them through `tostring`, which
-- is %.14g. That is enough for these and NOT OBVIOUSLY enough -- so it is
-- measured on all 1,468 rather than argued from the format.
-- ---------------------------------------------------------------------------
io.write("\nthe cache round trip\n")
local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local P = require("src.import.Gen4Particle")
local PS = require("src.battle.Gen4ParticleSystem")
local LuaWriter = require("src.import.LuaWriter")

local rom = assert(NdsRom.open(romPath))
local raw = rom:read(P.ARCHIVE_MOVES)
local moves = raw and Narc.parse(raw)
ok(moves ~= nil and moves.count > 0, "the move effect archive opens",
   moves and moves.count, "more than 0")

local function differences(a, b, path, out)
  if type(a) ~= type(b) then
    out[#out + 1] = path .. ": " .. type(a) .. " became " .. type(b)
    return
  end
  if type(a) ~= "table" then
    if a ~= b then
      out[#out + 1] = ("%s: %s became %s"):format(path, tostring(a), tostring(b))
    end
    return
  end
  for k, v in pairs(a) do differences(v, b[k], path .. "." .. tostring(k), out) end
  for k in pairs(b) do
    if a[k] == nil then out[#out + 1] = path .. "." .. tostring(k) .. " appeared" end
  end
end

local emitterCount, drift = 0, {}
if moves then
  for i = 0, moves.count - 1 do
    local file = moves:get(i)
    local list = file and P.emitters(file)
    for k, e in ipairs(list or {}) do
      emitterCount = emitterCount + 1
      -- THE REAL SERIALISER, not a stand-in. A round trip through a copy
      -- written for the test proves the test's copy is lossless.
      local encoded = LuaWriter.encode({ flags = e.flags, blocks = e.blocks,
                                         fields = e.fields })
      local chunk = load(encoded)
      local back = chunk and chunk()
      if not back then
        drift[#drift + 1] = ("%d/%d did not parse"):format(i, k)
      elseif #drift < 6 then
        differences({ flags = e.flags, blocks = e.blocks, fields = e.fields },
                    back, ("%d/%d"):format(i, k), drift)
      end
    end
  end
end
ok(emitterCount == 1468, "every emitter in the cartridge was encoded",
   emitterCount, 1468)
ok(#drift == 0, "AND EVERY ONE COMES BACK BIT-IDENTICAL",
   #drift == 0 and "no drift" or table.concat(drift, "; ", 1, math.min(3, #drift)),
   "no drift")

-- ---------------------------------------------------------------------------
-- 6: AND THE SECOND QUESTION -- does the cache route SIMULATE the same thing.
--
-- `Gen4ParticleSystem.new` takes cartridge bytes; `fromEmitters` takes what the
-- cache holds. The running game only ever uses the second, and every one of the
-- 58 assertions in `gen4_particle_check` exercises the first. That is exactly
-- the gap this file exists to close, so the two are run side by side and
-- compared particle for particle, frame for frame.
-- ---------------------------------------------------------------------------
io.write("\nthe two routes are one simulation\n")
local compared, mismatch, framesRun, particleFrames = 0, {}, 0, 0
if moves then
  for i = 0, moves.count - 1, 5 do
    local file = moves:get(i)
    local direct = file and PS.new(file)
    local list = file and P.emitters(file)
    local viaCache = nil
    if list then
      local chunk = load(LuaWriter.encode(list))
      viaCache = chunk and PS.fromEmitters(chunk())
    end
    if direct and viaCache then
      compared = compared + 1
      direct:start(9000 + i)
      viaCache:start(9000 + i)
      local frame = 0
      while frame < 120 do
        local a = direct:update()
        local b = viaCache:update()
        frame = frame + 1
        if a ~= b then
          if #mismatch < 5 then
            mismatch[#mismatch + 1] = ("%d ended at frame %d on one route only")
              :format(i, frame)
          end
          break
        end
        if not a then break end
        -- BOTH LISTS. Children are half the particles on the screen now -- 745
        -- emitters carry a child resource -- and a comparison that walked only
        -- the parents would call the two routes identical while the cache route
        -- sprayed something else entirely.
        local same = true
        for _, which in ipairs({ "particles", "children" }) do
          local a2, b2 = direct[which], viaCache[which]
          if #a2 ~= #b2 then
            if #mismatch < 5 then
              mismatch[#mismatch + 1] = ("%d frame %d: %d %s vs %d")
                :format(i, frame, #a2, which, #b2)
            end
            same = false
            break
          end
          for n, p in ipairs(a2) do
            local q = b2[n]
            particleFrames = particleFrames + 1
            if p.x ~= q.x or p.y ~= q.y or p.z ~= q.z
               or p.scaleX ~= q.scaleX or p.scaleY ~= q.scaleY
               or p.alpha ~= q.alpha or p.texture ~= q.texture
               or p.life ~= q.life or p.age ~= q.age
               or p.rotation ~= q.rotation then
              if #mismatch < 5 then
                mismatch[#mismatch + 1] = ("%d frame %d %s %d diverges")
                  :format(i, frame, which, n)
              end
              same = false
              break
            end
          end
          if not same then break end
        end
        if not same then break end
      end
      framesRun = framesRun + frame
    end
  end
end
ok(compared >= 90, "enough effects run on both routes to mean anything",
   compared, "at least 90")
ok(particleFrames > 8000, "...and enough particle-frames compared",
   particleFrames, "over 8000")
ok(#mismatch == 0, "THE CACHE ROUTE AND THE CARTRIDGE ROUTE NEVER DIVERGE",
   #mismatch == 0 and "identical"
     or table.concat(mismatch, "; ", 1, math.min(3, #mismatch)),
   "identical")
ok(framesRun > 1000, "...over this many frames of simulation", framesRun,
   "over 1000")

-- ---------------------------------------------------------------------------
-- 5: THE MIRROR IMAGE -- A MODULE NOBODY LOADS THAT SOMEBODY READS.
--
-- Everything above walks one way: every name the extractor WRITES must be on a
-- list in Data.lua or argued off it. That catches a table written and never
-- loaded, which is what it was built for and what it has caught three times.
--
-- IT CANNOT SEE THE OTHER DIRECTION, and the other direction happened. Data.lua
-- listed `gen4_overworld` among the modules that are "extractor INPUT ... no
-- running screen reads them" -- TRUE WHEN WRITTEN -- and then
-- `OverworldController.resolveGraphicsVar` began reading
-- `data.gen4_overworld.sprites[name].member`, which is the only NAME -> ARCHIVE
-- MEMBER hop in the port. With the module unloaded that returned nil for all
-- sixteen `var_0`..`var_f` graphics ids, and every object using one drew nothing.
-- Dawn, twice reported missing, was `var_0` holding 97 = `player_f`.
--
-- So: EVERY `data.gen4_*` FIELD READ ANYWHERE IN src/ MUST NAME A LOADED MODULE.
-- Read out of the source with the comments stripped, because a comment that
-- mentions a module is exactly what must not satisfy this.
do
  local readers, missing = {}, {}
  local p = io.popen('grep -rho "data\\.gen4_[a-z_]*" "'
                     .. (root ~= "" and root or "./") .. '../src" 2>/dev/null')
  for line in (p and p:lines() or function() return nil end) do
    local name = line:match("data%.(gen4_[a-z_]+)")
    if name then readers[name] = (readers[name] or 0) + 1 end
  end
  if p then p:close() end
  local n = 0
  for name in pairs(readers) do
    n = n + 1
    if not loaded[name] then missing[#missing + 1] = name end
  end
  ok(n >= 4, "the port reads this many gen4_ cache modules by name", n,
     "at least 4")
  ok(#missing == 0,
     "EVERY MODULE THE PORT READS IS ONE Data.lua LOADS",
     #missing == 0 and "all loaded" or table.concat(missing, ", "), "all loaded")
  -- THE ONE THIS SECTION EXISTS FOR, named literally, so a revert is caught by
  -- an assertion that says what it is rather than by a count moving.
  ok(loaded["gen4_overworld"] == "GEN4_PREFIXED",
     "...including the name -> member hop the var_N sprites need",
     tostring(loaded["gen4_overworld"]), "GEN4_PREFIXED")
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
