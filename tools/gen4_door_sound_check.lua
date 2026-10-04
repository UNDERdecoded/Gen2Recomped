-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EVERY DOOR IN SINNOH OPENED IN SILENCE, AND THE REASON GIVEN HAD EXPIRED.
--
-- `loaddooranimation`, `playdooropenanimation` and `playdoorcloseanimation`
-- lowered onto `g4_noop`, and measured over the whole decoded script corpus
-- they are **194 invocations** -- the largest declined subject in the port,
-- ahead of the money box (109) and the journal (78).
--
-- The comment declining them gave three reasons: this port reads NSBMD without
-- NSBCA, it bakes a chunk's props into a flat canvas, and it "has no SE bank
-- for Gen 4 yet". The first two are still true. The third stopped being true
-- at some point nobody re-checked: `audio.lua` carries **2,030 sound effects**
-- keyed by the cartridge's own SSEQ symbols, and `g4_play_sound` has been
-- using them all along. Same shape as `g4_overworld_weather`'s "the port keeps
-- no saved weather" -- a declined feature outliving its blocker.
--
-- WHAT THIS GRADES
--   1. the three cartridge tables -- twenty models, three sound types, four
--      effects -- against pokeplatinum;
--   2. the hitbox, which is where the model comes from and therefore which of
--      the three sounds plays;
--   3. the search, over every door prop in the cache, WITH A CONTROL: asking
--      one tile too far must miss, or the hitbox is decoration;
--   4. the three sound types all reached by real placements, so none is cold;
--   5. the 52 `loaddooranimation` sites in the ROM itself;
--   6. the wiring, and that the stale claim is gone.
--
-- THE CANARY THIS FILE OPENS WITH IS NOT A FORMALITY. The first draft of this
-- measurement reported **0 of 52 sites resolved** -- and the fault was the
-- probe's own module loader, which stubbed `Gen4Archives` so every `find()`
-- answered nil and no prop could ever be identified as a door. A zero that
-- comes from a dead join looks exactly like a zero that comes from wrong
-- geometry.
--
-- Run:  texlua tools/gen4_door_sound_check.lua <data/generated> [pokeplatinum] [rom]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local CACHE = arg and arg[1]
local PRET  = arg and arg[2]
local ROM   = arg and arg[3]

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
local function code(src)
  if not src then return "" end
  return (src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " "))
end
local function cdefn(src, name)
  return src and src:match("[%w_%*%s]-" .. name .. "%s*%b()%s*\n{(.-)\n}")
end

love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end,
               newCanvas = function() return nil end,
               newImage = function() return nil end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
  image = { newImageData = function() return nil end },
  math = { random = math.random },
}

local Doors    = require("src.world.Gen4Doors")
local Archives = require("src.import.Gen4Archives")
local Commands = require("src.script.Commands")
local Gen4Commands = require("src.script.Gen4Commands")
local VM       = require("src.script.Gen4ScriptVM")

-- ---------------------------------------------------------------------------
section("0. the canary -- the model join has to be alive")
-- ---------------------------------------------------------------------------
-- A dead join cannot identify any prop as a door, so every number below would
-- come out zero and look like a geometry fault. This happened.
do
  local list = Archives.names(Doors.MODEL_PATH)
  ok(list ~= nil and #list > 500,
     "build_model.narc listed %s members; Gen4Archives is not answering and "
     .. "every door lookup below would come back nil",
     tostring(list and #list))
  local idx, names = Doors.join()
  local n = 0
  for _ in pairs(idx) do n = n + 1 end
  ok(n == #Doors.MODELS,
     "%d of %d door models resolve in build_model.narc; a model that does not "
     .. "resolve is a door whose sound can never be chosen", n, #Doors.MODELS)
  ok(Doors.indexOf("iron_door") ~= nil,
     "iron_door does not resolve, so the join is dead")
  ok(Doors.modelNameOf(Doors.indexOf("iron_door")) == "iron_door",
     "the member -> name direction of the join disagrees with the other one")
  report("%d door models, all resolved in a %d-member archive", n, #list)
end

-- ---------------------------------------------------------------------------
section("1. the three cartridge tables, against pokeplatinum")
-- ---------------------------------------------------------------------------
ok(#Doors.MODELS == 20,
   "%d door models, expected the 20 in DoorAnimation_FindDoorAndLoad",
   #Doors.MODELS)
if not PRET then
  skip("no pokeplatinum checkout, so the model list, the sound types and the "
       .. "four effects are unverified against pret")
else
  local src = slurp(PRET .. "/src/overlay005/ov5_021D431C.c")
  ok(src ~= nil, "src/overlay005/ov5_021D431C.c is not readable")
  if src then
    -- THE LIST, IN ORDER. Compared row for row rather than as a set, because a
    -- set comparison cannot see a dropped entry that another entry duplicates.
    local body = cdefn(src, "DoorAnimation_FindDoorAndLoad")
    ok(body ~= nil, "DoorAnimation_FindDoorAndLoad is not defined")
    if body then
      local arr = body:match("doorModelIDs%[%]%s*=%s*{(.-)}")
      ok(arr ~= nil, "could not find the doorModelIDs array")
      if arr then
        local pret = {}
        for n in arr:gmatch("([a-z0-9_]+)_nsbmd") do pret[#pret + 1] = n end
        ok(#pret == #Doors.MODELS,
           "pret lists %d door models and this port has %d", #pret, #Doors.MODELS)
        local bad = {}
        for i = 1, math.max(#pret, #Doors.MODELS) do
          if pret[i] ~= Doors.MODELS[i] then
            bad[#bad + 1] = ("%d: %s vs pret's %s"):format(i,
              tostring(Doors.MODELS[i]), tostring(pret[i]))
          end
        end
        ok(#bad == 0, "%d model(s) differ from pret's order: %s", #bad,
           table.concat(bad, ", "))
        report("%d door models agree with pret, in order", #pret)
      end
      -- ...and the hitbox, which decides WHICH door is found
      local hb = body:match("TerrainCollisionHitbox_Init%s*%(([^)]*)%)")
      ok(hb ~= nil, "could not find the hitbox construction")
      if hb then
        local nums = {}
        for v in hb:gmatch("%-?%d+") do nums[#nums + 1] = tonumber(v) end
        -- (x, z, offsetX, offsetZ, sizeX, sizeZ, &hitbox) -- the first two are
        -- names, so the numeric operands are the four that follow
        ok(nums[1] == Doors.HITBOX_OFFSET_X,
           "pret offsets the hitbox by %s in x; this port uses %s",
           tostring(nums[1]), tostring(Doors.HITBOX_OFFSET_X))
        ok(nums[2] == 0, "pret's z offset is %s, not 0", tostring(nums[2]))
        ok(nums[3] == Doors.HITBOX_SIZE_X,
           "pret's hitbox is %s tiles wide; this port uses %s",
           tostring(nums[3]), tostring(Doors.HITBOX_SIZE_X))
        ok(nums[4] == Doors.HITBOX_SIZE_Z,
           "pret's hitbox is %s tiles deep; this port uses %s",
           tostring(nums[4]), tostring(Doors.HITBOX_SIZE_Z))
      end
    end

    -- THE SOUND TYPE, from the function that decides it.
    local st = cdefn(src, "DoorAnimation_GetSoundEffectType")
    ok(st ~= nil, "DoorAnimation_GetSoundEffectType is not defined")
    if st then
      -- the chime arm names exactly one model
      local chimeArm = st:match("VEILSTONE_DPT_STORE_CHIME")
      ok(chimeArm ~= nil, "pret no longer has a Veilstone chime arm")
      local chimeModel = st:match("if %(doorModelID == ([a-z0-9_]+)_nsbmd%)")
      ok(chimeModel ~= nil and Doors.CHIME[chimeModel] == true,
         "pret's chime model is %s; this port's chime set is %s",
         tostring(chimeModel),
         (function() local t = {} for k in pairs(Doors.CHIME) do t[#t+1] = k end
            table.sort(t) return table.concat(t, ",") end)())
      local nChime = 0
      for _ in pairs(Doors.CHIME) do nChime = nChime + 1 end
      ok(nChime == 1, "%d model(s) in the chime set, expected 1", nChime)

      -- the sliding arm names six
      local slideArm = st:match("SLIDING;")
          and st:match("if %(%(doorModelID ==(.-)%)%s*{%s*\n%s*return DOOR_SOUND_EFFECT_TYPE_SLIDING")
      slideArm = slideArm or st:match("return DOOR_SOUND_EFFECT_TYPE_SLIDING")
                               and st:match("%)%s*|| %(doorModelID.-\n")
      -- read every model named anywhere after the chime arm
      local after = st:match("SLIDING.-return") and st or st
      local sliding = {}
      for n in st:gmatch("doorModelID == ([a-z0-9_]+)_nsbmd") do
        sliding[#sliding + 1] = n
      end
      -- the first of those is the chime model; the rest are the sliding set
      table.remove(sliding, 1)
      ok(#sliding == 6,
         "pret names %d sliding model(s) after the chime one, expected 6",
         #sliding)
      local miss, extra = {}, {}
      local want = {}
      for _, n in ipairs(sliding) do
        want[n] = true
        if Doors.SLIDING[n] ~= true then miss[#miss + 1] = n end
      end
      for n in pairs(Doors.SLIDING) do
        if not want[n] then extra[#extra + 1] = n end
      end
      ok(#miss == 0, "%d sliding model(s) pret names are not in this port's "
         .. "set: %s", #miss, table.concat(miss, ", "))
      ok(#extra == 0, "%d model(s) are sliding here and not in pret: %s",
         #extra, table.concat(extra, ", "))
      report("chime: %s; sliding: %s", tostring(chimeModel),
             table.concat(sliding, ", "))
    end

    -- THE FOUR EFFECTS, and the two that are deliberately silent on close.
    local openFn = cdefn(src, "DoorAnimation_PlayOpenAnimation")
    local closeFn = cdefn(src, "DoorAnimation_PlayCloseAnimation")
    ok(openFn ~= nil and closeFn ~= nil,
       "the open/close animation functions are not both defined")
    if openFn and closeFn then
      local function sseq(body2, kind)
        return body2:match("TYPE_" .. kind .. ".-soundEffectID = ([A-Za-z0-9_]+);")
      end
      -- open: each arm names an SSEQ
      ok(openFn:find(Doors.SOUND.sliding.open .. "_sseq", 1, true) ~= nil,
         "pret's sliding open sound is not %s", Doors.SOUND.sliding.open)
      ok(openFn:find(Doors.SOUND.chime.open .. "_sseq", 1, true) ~= nil,
         "pret's chime open sound is not %s", Doors.SOUND.chime.open)
      ok(openFn:find(Doors.SOUND.hinged.open .. "_sseq", 1, true) ~= nil,
         "pret's hinged open sound is not %s", Doors.SOUND.hinged.open)
      -- close: ONLY the hinged arm names one; the other two are 0
      ok(closeFn:find(Doors.SOUND.hinged.close .. "_sseq", 1, true) ~= nil,
         "pret's hinged close sound is not %s", Doors.SOUND.hinged.close)
      local zeros = 0
      for _ in closeFn:gmatch("soundEffectID = 0;") do zeros = zeros + 1 end
      ok(zeros == 2,
         "pret's close function has %d silent arm(s), expected 2 (sliding and "
         .. "the chime) -- a pneumatic door that creaked shut would be audibly "
         .. "wrong in every Pokemon Centre", zeros)
      ok(Doors.SOUND.sliding.close == false and Doors.SOUND.chime.close == false,
         "this port gives the sliding or chime doors a close sound: %s / %s",
         tostring(Doors.SOUND.sliding.close), tostring(Doors.SOUND.chime.close))
      -- and the animation INDEX, which is the half still missing
      ok(openFn:find("animationIndex = 0") ~= nil
         and closeFn:find("animationIndex = 1") ~= nil,
         "pret no longer plays animation 0 to open and 1 to close; this port "
         .. "does not animate yet, and that is the pair it will need")
    end
  end
end

-- ---------------------------------------------------------------------------
section("2. the sounds are in this cache, by the cartridge's own symbol")
-- ---------------------------------------------------------------------------
local audio = loadTable(CACHE, "audio")
if not audio or type(audio.sfx) ~= "table" then
  skip("no audio.lua with an sfx table, so the sound symbols are unverified")
else
  local n = 0
  for _ in pairs(audio.sfx) do n = n + 1 end
  ok(n > 500,
     "this cache has %d sound effect(s); the comment this pass deleted said "
     .. "there was no SE bank at all, and that is the claim being re-measured",
     n)
  local missing = {}
  for _, kind in ipairs({ "hinged", "sliding", "chime" }) do
    for _, act in ipairs({ "open", "close" }) do
      local name = Doors.SOUND[kind][act]
      if name and not audio.sfx[name] then missing[#missing + 1] = name end
    end
  end
  ok(#missing == 0,
     "%d door sound symbol(s) are not in this cache: %s -- naming the SSEQ "
     .. "symbol rather than the number is what makes this checkable",
     #missing, table.concat(missing, ", "))
  report("%d sound effects in the cache; all 4 door symbols present", n)
end

-- ---------------------------------------------------------------------------
section("3. the search, over every door prop -- with a control")
-- ---------------------------------------------------------------------------
local terrain = loadTable(CACHE, "gen4_terrain")
if not terrain or type(terrain.matrices) ~= "table" then
  skip("no gen4_terrain.lua with matrices, so the search is unverified")
else
  local data = { gen4_terrain = terrain, audio = audio }
  local _, names = Doors.join()
  local half = (terrain.chunkUnits or 512) / 2
  local unit = terrain.tileUnits or 16
  local tested, found, byType = 0, 0, {}
  local controlTested, controlFound = 0, 0
  for mi, grid in pairs(terrain.matrices) do
    if type(grid) == "table" and type(grid.land) == "table"
       and grid.width and grid.height then
      for cell = 0, (grid.width * grid.height) - 1 do
        local land = grid.land[cell + 1]
        local rec = land and terrain.chunks and terrain.chunks[land]
        for _, o in ipairs((type(rec) == "table" and rec.objects) or {}) do
          if names[o.model] then
            local tx = math.floor(((tonumber(o.x) or 0) + half) / unit)
            local tz = math.floor(((tonumber(o.z) or 0) + half) / unit)
            local mx, mz = cell % grid.width, math.floor(cell / grid.width)
            local def = { id = "probe", layout = mi }
            tested = tested + 1
            local got = Doors.modelAt(data, def, mx, mz, tx, tz)
            if got then
              found = found + 1
              local t = Doors.soundType(got)
              byType[t] = (byType[t] or 0) + 1
            end
            -- THE CONTROL, AND IT PROBES BOTH DIRECTIONS IN X.
            --
            -- The hitbox starts one tile LEFT of the named tile and runs three
            -- tiles, so a query six tiles to the right must miss, one three
            -- tiles to the LEFT must miss, and one four tiles away in z must
            -- miss. Without the leftward probe a widened window is invisible:
            -- raising the width to 64 moves the far edge away from the door
            -- rather than over it, so the rightward probe still misses and the
            -- control reports clean. Planting exactly that is what found this.
            controlTested = controlTested + 3
            if Doors.modelAt(data, def, mx, mz, tx + 6, tz) then
              controlFound = controlFound + 1
            end
            if Doors.modelAt(data, def, mx, mz, tx - 3, tz) then
              controlFound = controlFound + 1
            end
            if Doors.modelAt(data, def, mx, mz, tx, tz + 4) then
              controlFound = controlFound + 1
            end
          end
        end
      end
    end
  end
  ok(tested >= 150,
     "only %d door prop(s) in this cache, which is too few for the search to "
     .. "have been measured", tested)
  ok(found == tested,
     "%d of %d door props were not found when asked at their own tile",
     tested - found, tested)
  -- THE CONTROL IS THE POINT. A few hits are expected where two doors stand
  -- within six tiles of each other, so this is a ceiling rather than a zero --
  -- but it has to be far below the total or the hitbox means nothing.
  ok(controlFound < controlTested * 0.15,
     "%d of %d off-target queries still found a door (%.0f%%); the hitbox is "
     .. "not actually constraining the search",
     controlFound, controlTested, 100 * controlFound / math.max(1, controlTested))
  report("%d door props, all found at their own tile; %d of %d off-target "
         .. "queries hit", tested, controlFound, controlTested)

  -- ALL THREE SOUND TYPES REACHED BY REAL PLACEMENTS, so none is a cold arm.
  for _, t in ipairs({ "hinged", "sliding", "chime" }) do
    ok((byType[t] or 0) > 0,
       "no door prop in this cache is %s, so that arm of the sound table is "
       .. "never taken and nothing proves it is wired", t)
    report("  %-8s %d door prop(s)", t, byType[t] or 0)
  end
  -- ...and a map whose matrix this cache does not have must REFUSE, with a
  -- reason, rather than answering some other map's door.
  local gotBad, why = Doors.modelAt(data, { id = "x", layout = 99999 }, 0, 0, 0, 0)
  ok(gotBad == nil and type(why) == "string" and why ~= "",
     "an unknown matrix answered %s rather than refusing with a reason",
     tostring(gotBad))
  local outside, why2 = Doors.modelAt(data, { id = "x", layout = 0 }, 999, 999, 0, 0)
  ok(outside == nil and type(why2) == "string",
     "a cell outside the grid answered %s rather than refusing",
     tostring(outside))
end

-- ---------------------------------------------------------------------------
section("4. the 52 sites in the ROM itself")
-- ---------------------------------------------------------------------------
if not ROM or not terrain then
  skip("no ROM (or no terrain), so the cartridge's own call sites are not "
       .. "resolved")
else
  local okR, NdsRom = pcall(require, "src.import.NdsRom")
  local okN, Narc = pcall(require, "src.import.NarcArchive")
  local okS, Script = pcall(require, "src.import.Gen4Script")
  if not (okR and okN and okS) then
    skip("the ROM readers are not available in this harness")
  else
    local rom = NdsRom.open(ROM)
    if not rom then
      skip("could not open %s", tostring(ROM))
    else
      local arc = Narc.parse(rom:read("/fielddata/script/scr_seq.narc"))
      local sites = {}
      for m = 0, (arc and arc.count or 0) - 1 do
        local bytes = arc:get(m)
        if bytes and #bytes >= 6 then
          local queue, seen = {}, {}
          for _, at in ipairs(Script.entries(bytes)) do
            if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
          end
          local i = 1
          while i <= #queue do
            local at = queue[i]; i = i + 1
            local ins = Script.decode(bytes, at)
            for _, op in ipairs(ins) do
              if op.name == "loaddooranimation" then
                sites[#sites + 1] = op.args
              end
              local t = op.target
              if t and t >= 1 and t <= #bytes and not seen[t] then
                seen[t] = true; queue[#queue + 1] = t
              end
            end
          end
        end
      end
      rom:close()
      ok(#sites >= 50,
         "%d loaddooranimation site(s) in the ROM, expected 52 -- too few for "
         .. "this section to have measured anything", #sites)
      -- THE REGION SITES. Matrix 0 is the 30x30 region grid; a site at (0,0)
      -- is on an indoor map with a matrix of its own, which this section
      -- cannot name without walking the map table, so it counts them apart.
      local data = { gen4_terrain = terrain, audio = audio }
      local def0 = { id = "region", layout = 0 }
      local indoor, outdoor, resolved, byModel = 0, 0, 0, {}
      for _, a in ipairs(sites) do
        local mx, mz, tx, tz = a[1], a[2], a[3], a[4]
        if mx == 0 and mz == 0 then
          indoor = indoor + 1
        else
          outdoor = outdoor + 1
          local got = Doors.modelAt(data, def0, mx, mz, tx, tz)
          if got then
            resolved = resolved + 1
            byModel[got] = (byModel[got] or 0) + 1
          end
        end
      end
      ok(outdoor >= 10,
         "only %d site(s) name a region cell, which is too few to measure",
         outdoor)
      ok(resolved == outdoor,
         "%d of %d region-map door sites did not resolve to a door model -- "
         .. "this is the measurement the whole pass rests on and it was 15 of "
         .. "15 when written", outdoor - resolved, outdoor)
      report("%d sites: %d on a region map (all resolved), %d on an indoor "
             .. "map (their own matrix, not walked here)", #sites, outdoor,
             indoor)
      local mk = {}
      for k in pairs(byModel) do mk[#mk + 1] = k end
      table.sort(mk)
      for _, k in ipairs(mk) do
        report("  %-32s x%d  (%s)", k, byModel[k], Doors.soundType(k))
      end
    end
  end
end

-- ---------------------------------------------------------------------------
section("5. the wiring, and the stale claim")
-- ---------------------------------------------------------------------------
do
  local src = code(slurp("src/script/Gen4ScriptVM.lua"))
  -- THE CLAIM IS GONE. Asserted because the comment outliving its blocker is
  -- the fault this pass is about, and the next one will be found the same way.
  for _, name in ipairs({ "loaddooranimation", "playdooropenanimation",
                          "playdoorcloseanimation" }) do
    local body = src:match("L%." .. name .. "%s*=%s*function.-\nend")
    ok(body ~= nil, "`%s` has no lowering", name)
    if body then
      ok(body:find("g4_door_anim") ~= nil,
         "`%s` does not lower onto g4_door_anim", name)
      ok(body:find("g4_noop") == nil,
         "`%s` still lowers onto a no-op", name)
    end
  end
  -- ...and each arm is named exactly once, so `open` cannot silently be
  -- lowered as `close`
  local arms = {}
  for arm in src:gmatch('"g4_door_anim",%s*"([a-z]+)"') do
    arms[arm] = (arms[arm] or 0) + 1
  end
  for _, arm in ipairs({ "load", "open", "close", "unload" }) do
    ok(arms[arm] == 1,
       "the %q arm of g4_door_anim is emitted %s time(s), expected once",
       arm, tostring(arms[arm]))
  end
  ok(type(Commands.g4_door_anim) == "function",
     "g4_door_anim has no handler, so the rows the lowering emits reach "
     .. "nothing")
end

-- THE TAG LIVES ON THE OVERWORLD, NOT THE SAVE, and that is behavioural.
do
  local Doors2 = Doors
  local ow = { map = { def = { id = "probe", layout = 0 } }, gen4Doors = nil }
  local ctx = { save = {}, overworld = ow,
                game = { save = {}, data = { gen4_terrain = terrain,
                                             audio = audio } } }
  local played = {}
  local realPlay = Doors2.play
  Doors2.play = function(_, model, action)
    played[#played + 1] = tostring(model) .. ":" .. tostring(action)
    return true
  end
  Commands.g4_door_anim(ctx, "load", 0, 0, 0, 0, 77)
  ok(type(ow.gen4Doors) == "table",
     "loading a door animation did not put the tag on the overworld")
  ok(ctx.save.gen4Doors == nil,
     "the door tag went into the save, where it would make a door in one town "
     .. "answer for a door in another")
  Commands.g4_door_anim(ctx, "open", 77)
  ok(#played == 1, "opening the door played %d sound(s), expected 1", #played)
  Commands.g4_door_anim(ctx, "unload", 77)
  ok(ow.gen4Doors[77] == nil,
     "unloading the tag left it set, so a tag reused for something else would "
     .. "still play a door's sound")
  -- an unloaded tag still makes a sound rather than going silent
  played = {}
  Commands.g4_door_anim(ctx, "open", 77)
  ok(#played == 1,
     "opening an unloaded tag played nothing; a silent door is the fault this "
     .. "pass is fixing, and hinged is what the cartridge plays for a model it "
     .. "does not name specially")
  Doors2.play = realPlay
end

-- THE CLOSE SOUND IS ABSENT FOR TWO TYPES, AND THAT ARM IS FORCED, because no
-- amount of play-testing proves a sound did NOT play.
do
  ok(Doors.soundNameFor("pokecenter_door", "close") == false,
     "a sliding door has a close sound, which the cartridge sets to 0")
  ok(Doors.soundNameFor("veilstone_dpt_store_door", "close") == false,
     "the Veilstone chime door has a close sound")
  ok(Doors.soundNameFor("door01", "close") == Doors.SOUND.hinged.close,
     "a hinged door's close sound is %s",
     tostring(Doors.soundNameFor("door01", "close")))
  ok(Doors.soundNameFor("not-a-door", "open") == Doors.SOUND.hinged.open,
     "an unidentified model does not fall back to the hinged sound, so a door "
     .. "whose model could not be found would be silent")
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
