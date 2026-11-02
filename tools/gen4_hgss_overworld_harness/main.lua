-- tools/gen4_hgss_overworld_harness/main.lua
--
-- tools/gen4_overworld_harness, standing on an INSTALLED version folder.
--
--   INSTALL=G:/Gen2Recomped/heartgold VERSION=heartgold MAP=T20 X=14 Y=14 \
--     love tools/gen4_hgss_overworld_harness
--
-- The overworld harness reads data through POKEPORT_DATA_DIR and pictures
-- through POKEPORT_ASSET_ROOT, but the 3D ground opens its packed geometry
-- (`terrain/chunks.bin`) with love.filesystem, which only sees what is
-- mounted -- the launcher mounts a version's cache (CacheFs.mountVersion) and
-- a bare harness does not. So this mounts INSTALL at the root, read-only,
-- with the same PHYSFS_mount CacheFs uses, sets the two variables from it, and
-- hands over to the overworld harness unchanged. Pictures land in this
-- harness's own save folder (identity hgss_ow).

-- every line out as it is printed, so a hard crash still shows where it was
io.stdout:setvbuf("line")
local install = assert(os.getenv("INSTALL"), "set INSTALL to the version's folder")

-- POKEPORT_SIMULATE_SWITCH=1: reproduce the read path the Switch ends up with
-- (docs/switch.md). love-nx cannot overlay a version folder, so CacheFs falls
-- back to its prefix shim and every generated file is reachable ONLY as
-- "<version>/assets/generated/..." through the wrapped loaders. So mount the
-- PARENT of INSTALL (the cache root, as the Switch's save directory is), not
-- INSTALL itself, and install the same shim.
local simulateSwitch = (os.getenv("POKEPORT_SIMULATE_SWITCH") or "") ~= ""
  and os.getenv("POKEPORT_SIMULATE_SWITCH") ~= "0"
local mountDir = install
if simulateSwitch then
  mountDir = install:gsub("[/\\]+$", ""):match("^(.*)[/\\][^/\\]+$") or install
end

local ffi = require("ffi")
pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
local mounted = false
for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
  local ok, l = pcall(lib)
  if ok and l then
    local okf, fn = pcall(function() return l.PHYSFS_mount end)
    if okf and fn and fn(mountDir, "", 1) ~= 0 then mounted = true break end
  end
end
print(("mounted %s: %s"):format(mountDir, tostring(mounted)))
-- MODS_ROOT=G:/Gen2Recomped: mount the folder holding `mods/` as well, so
-- the harness loads the user's mods (DRAMATIC_SHAPE ...) the way the game does
if os.getenv("MODS_ROOT") then
  local okM = pcall(function() return ffi.C.PHYSFS_mount(os.getenv("MODS_ROOT"), "", 1) end)
  if not okM then pcall(function() return ffi.load("love").PHYSFS_mount(os.getenv("MODS_ROOT"), "", 1) end) end
  print(("mods root %s mounted"):format(os.getenv("MODS_ROOT")))
end
-- BW_HEIGHTS_ROM=<black/white .nds>: read an install imported before
-- src/import/Gen5Heights.lua as a new import would -- every BW map's height
-- edits (the tiles' raw values) mapped through the table built from the ROM,
-- with 0 written beside each raised tile -- in memory, the install untouched
if os.getenv("BW_HEIGHTS_ROM") then
  local Data = require("src.core.Data")
  local load0 = Data.load
  Data.load = function(self, ...)
    local r = { load0(self, ...) }
    local rom = require("src.import.NdsRom").open(os.getenv("BW_HEIGHTS_ROM"))
    local T = rom and require("src.import.Gen5Heights").build(rom)
    local maps, done = T and rawget(self, "maps") or self.maps, 0
    for _, def in pairs(maps or {}) do
      local e = type(def) == "table" and def.gen5 and def.gen4HeightEdits
      if e and not def.gen5Rail and not def.gen5NoGrid then
        local out = {}
        for k, v in pairs(e) do out[k] = T[v] end
        local add = {}
        for k, v in pairs(out) do
          if v ~= 0 then
            local x, y = k:match("(-?%d+),(-?%d+)")
            x, y = tonumber(x), tonumber(y)
            for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
              local key = (x + d[1]) .. "," .. (y + d[2])
              if e[key] == nil then add[key] = 0 end
            end
          end
        end
        for k, v in pairs(add) do out[k] = v end
        def.gen4HeightEdits = out
        done = done + 1
      end
    end
    print(("BW_HEIGHTS_ROM: %d map(s) re-read through Gen5Heights"):format(done))
    return (table.unpack or unpack)(r)
  end
end
if simulateSwitch then
  local leaf = install:gsub("[/\\]+$", ""):match("([^/\\]+)$")
  local unshimmedNewFile = love.filesystem.newFile
  require("src.import.CacheFs").installPrefixShim(leaf .. "/")
  -- SIM_OLD_SHIM=1: the shim as it was before newFile was redirected, to
  -- show the reported no-ground picture
  if os.getenv("SIM_OLD_SHIM") then love.filesystem.newFile = unshimmedNewFile end
  print(("simulated Switch: prefix shim on %s/, no direct cache reads"):format(leaf))
end

-- OUT_DIR: write the harness's PNGs there (plain io) instead of LÖVE's save
-- folder -- for a machine whose system drive has no room
local outDir = os.getenv("OUT_DIR")
if outDir then
  local probe = love.image.newImageData(1, 1)
  local mt = getmetatable(probe)
  local index = mt and mt.__index
  local encode = index and index.encode
  if encode then
    index.encode = function(self, format, filename)
      local data = encode(self, format)
      if filename then
        local f = assert(io.open(outDir .. "/" .. filename, "wb"))
        f:write(data:getString()); f:close()
        return data
      end
      return data
    end
  end
end

-- the overworld harness reads these two at load time
local env = { POKEPORT_DATA_DIR = install .. "/data/generated", POKEPORT_ASSET_ROOT = install }
-- simulated Switch: no io.open shortcuts around the read path
if simulateSwitch then env = {} end
local getenv = os.getenv
os.getenv = function(k) return env[k] or getenv(k) end

-- PARTY_DETAIL=1: with the overworld harness's "party after" line, each
-- member's species and friendship (what a script's friendship row changed)
if os.getenv("PARTY_DETAIL") then
  local print0 = print
  print = function(first, ...)
    print0(first, ...)
    if type(first) == "string" and first:match("^party after") then
      local G = package.loaded["src.core.Game"]
      local beaten = {}
      for id, yes in pairs((G and G.save and G.save.gen4TrainerFlags) or {}) do
        if yes then beaten[#beaten + 1] = tostring(id) end
      end
      table.sort(beaten)
      print0("  trainers beaten: " .. (#beaten > 0 and table.concat(beaten, ",") or "none"))
      local badges = {}
      for id, yes in pairs((G and G.save and G.save.badges) or {}) do if yes then badges[#badges + 1] = tostring(id) end end
      table.sort(badges)
      print0("  badges: " .. (#badges > 0 and table.concat(badges, ",") or "none"))
      -- SHOW_FLAGS="0x169,0x1D0": whether each is set at the end
      for id in tostring(os.getenv("SHOW_FLAGS") or ""):gmatch("%w+") do
        local C = require("src.script.Commands")
        local c = { save = G.save, game = G }
        C.check_flag(c, ("FLAG_G4_%04X"):format(tonumber(id)))
        print0(("  flag %s %s"):format(id, c.lastCheck and "set" or "clear"))
      end
      -- SHOW_SAVE="gen4SpecialLocation,hgssGymmick.candles": a save field (dotted), one level shown
      for key in tostring(os.getenv("SHOW_SAVE") or ""):gmatch("[%w_%.]+") do
        local v = G.save
        for part in key:gmatch("[^%.]+") do v = type(v) == "table" and v[part] or nil end
        local parts = {}
        if type(v) == "table" then
          for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
          table.sort(parts)
        end
        print0(("  save.%s = %s"):format(key, type(v) == "table" and "{" .. table.concat(parts, ", ") .. "}" or tostring(v)))
      end
      -- SHOW_MAPS="R32,R_32": a loaded map def's header, generation and source
      for id in tostring(os.getenv("SHOW_MAPS") or ""):gmatch("[%w_]+") do
        local d = G.data and G.data.maps and G.data.maps[id]
        print0(("  map %s: %s"):format(id, d and ("id=%s same=%s header=%s generation=%s label=%s width=%s"):format(tostring(d.id), tostring(d == (G.data.maps[(id:gsub("_", ""))])),
          tostring(d.header), tostring(d.generation), tostring(d.label), tostring(d.width)) or "absent"))
      end
      -- SHOW_LOCAL=0: every live entity answering to that local id
      if os.getenv("SHOW_LOCAL") then
        local want = tonumber(os.getenv("SHOW_LOCAL"))
        local OWs = G.stack and G.stack.states or {}
        for _, st in ipairs(OWs) do
          for i, e in ipairs(st.entities or {}) do
            local lid = e.localId or (e.def and e.def.localId)
            if lid == want then
              print0(("  entity %d: localId %s index %s sprite %s at (%s,%s) player=%s"):format(i, tostring(lid),
                tostring(e.def and e.def.index), tostring(e.def and (e.def.spriteName or e.def.sprite)),
                tostring(e.cellX), tostring(e.cellY), tostring(e == st.player)))
            end
          end
        end
      end
      -- SHOW_BUILDINGS=1: the ground's building set and, per placement in
      -- view, whether its model resolves
      if os.getenv("SHOW_BUILDINGS") then
        for _, st in ipairs((G.stack and G.stack.states) or {}) do
          local ground = st.map and st.map.renderer and st.map.renderer.gen4Ground
          if ground then
            local set = ground.buildingSet
            print0(("  building set %s (%s models)"):format(tostring(set and set.label),
              tostring(set and set.models and #set.models)))
            local where = {}
            local grid = ground.grid
            for i, l in ipairs((grid and grid.land) or {}) do
              where[l] = where[l] or { (i - 1) % grid.width, math.floor((i - 1) / grid.width) }
            end
            for land, rec in pairs((ground.terrain and ground.terrain.chunks) or {}) do
              local ok, objs = pcall(ground.objectsFor, ground, land, rec)
              local cw = where[land]
              if cw then print0(("  land %s at chunk (%d,%d), map offset (%s,%s)"):format(tostring(land), cw[1], cw[2],
                tostring(ground.offsetX), tostring(ground.offsetY))) end
              if ok and objs and #objs > 0 and (not os.getenv("LAND") or tonumber(os.getenv("LAND")) == land) then
                local parts = {}
                for _, o in ipairs(objs) do
                  local b = ground:building(o.model, o.archive)
                  parts[#parts + 1] = ("%s%s@%.0f,%.0f,%.0f"):format(tostring(o.model), b and "" or "!", o.x or 0, o.y or 0, o.z or 0)
                end
                print0(("  land %s: %s"):format(tostring(land), table.concat(parts, " ")))
              end
            end
          end
        end
      end
      -- SHOW_PLAYER=1: the player's position and state fields
      if os.getenv("SHOW_PLAYER") then
        for _, st in ipairs((G.stack and G.stack.states) or {}) do
          local p = st.player
          if p then
            print0(("  player cell (%s,%s) px (%s,%s) moving %s hidden %s locked %s elevation %s"):format(
              tostring(p.cellX), tostring(p.cellY), tostring(p.px), tostring(p.py), tostring(p.moving),
              tostring(p.hidden or p.invisible), tostring(p.inputLocked), tostring(p.elevation)))
          end
        end
      end
      -- SHOW_HEIGHTS="13,80;13,75": the ground's heights (world units) there
      if os.getenv("SHOW_HEIGHTS") then
        for _, st in ipairs((G.stack and G.stack.states) or {}) do
          local ground = st.map and st.map.renderer and st.map.renderer.gen4Ground
          if ground then
            for x, z in tostring(os.getenv("SHOW_HEIGHTS")):gmatch("(%d+),(%d+)") do
              local list = ground.heightsAt and ground:heightsAt(tonumber(x), tonumber(z)) or {}
              local over = ground.heightOverride and ground:heightOverride(tonumber(x), tonumber(z))
              print0(("  height %s,%s: %s (override %s)"):format(x, z, table.concat(list, "/"), tostring(over)))
            end
          end
        end
      end
      local ap = G and G.save and G.save.hgssApricorns
      if ap then
        local picked = {}
        for k in pairs(ap.picked or {}) do picked[#picked + 1] = k end
        print0(("  apricorns: box %s, Kurt %d of colour %d, trees picked %s"):format(
          table.concat(ap.box, ","), ap.kurtQuantity or 0, ap.kurtColour or 0, table.concat(picked, ",")))
      end
      local inv = G and G.save and G.save.inventory or {}
      for _, id in ipairs({ 492, 493, 494, 495, 496, 497, 498 }) do
        local k = ("ITEM_%03d"):format(id)
        if inv[k] then print0(("  item %d x%s"):format(id, tostring(inv[k]))) end
      end
      for i, mon in ipairs((G and G.save and G.save.party) or {}) do
        local moves = {}
        for _, mv in ipairs(mon.moves or {}) do moves[#moves + 1] = tostring(mv.id) end
        print0(("  party %d: species %s level %s shiny %s fateful %s friendship %s egg %s moves %s"):format(i, tostring(mon.species), tostring(mon.level), tostring(require("src.pokemon.Pokemon").isShiny(mon)), tostring(mon.fatefulEncounter),
          tostring(mon.happiness or mon.friendship), tostring(mon.isEgg or mon.egg or false),
          table.concat(moves, ",")))
      end
    end
  end
end

-- BW_RELINK=<black/white .nds>: the script pool relinked IN MEMORY with the
-- current Gen5ScriptLink (the way tools/gen5_facility_harness does), so an
-- alias change is tested without a re-import
if os.getenv("BW_RELINK") then
  local Data = require("src.core.Data")
  local load = Data.load
  Data.load = function(self, ...)
    local r = { load(self, ...) }
    local ok, err = pcall(function()
      local gen = (os.getenv("INSTALL") or "") .. "/data/generated/"
      local X = require("src.import.RomExtractorGen5")
      local x = assert(X.new(os.getenv("BW_RELINK"), os.getenv("VERSION") or "black"))
      local scripts = self.gen5_scripts or dofile(gen .. "gen5_scripts.lua")
      local zones = self.gen5_zones or dofile(gen .. "gen5_zones.lua")
      local maps = dofile(gen .. "maps.lua")
      local ver = self.gen5_version or dofile(gen .. "gen5_version.lua")
      local Link = require("src.import.Gen5ScriptLink")
      for op, w in pairs(require("src.import.Gen5ScriptOps").HAND_WIDTHS or {}) do scripts.widths[op] = w end
      local pool, rep = Link.pool(require("src.import.NarcArchive").parse(x.rom:read("/a/0/5/7")),
        scripts.widths, zones, maps, ver.scriptBands or Link.findBands(x.rom))
      for k, v in pairs(self.map_scripts or {}) do if pool[k] == nil then pool[k] = v end end
      self.map_scripts = pool
      print(("[relink] script pool relinked: %d instructions, %d named"):format(rep.instructions, rep.named))
      -- ...and the import-time constants a relinked command may read
      self.constants = self.constants or {}
      self.constants.gen5Marts = self.constants.gen5Marts or require("src.import.Gen5Marts").build(x)
      self.constants.gen5GateBoards = self.constants.gen5GateBoards or require("src.import.Gen5GateBoards").build(x)
      self.constants.gen5CameraPresets = self.constants.gen5CameraPresets or require("src.import.Gen5CameraPresets").build(x)
      x.rom:close()
    end)
    if not ok then print("[relink] FAILED " .. tostring(err)) end
    return (table.unpack or unpack)(r)
  end
end

-- CMD_TRACE="ecruteak|battle": print each script command whose name matches
-- one of the |-separated patterns, with its operands, as it runs
if os.getenv("CMD_TRACE") then
  local Commands = require("src.script.Commands")
  require("src.script.Gen4Commands")
  local pats = {}
  for p in tostring(os.getenv("CMD_TRACE")):gmatch("[^|]+") do pats[#pats + 1] = p end
  for name, fn in pairs(Commands) do
    if type(fn) == "function" then
      for _, p in ipairs(pats) do
        if name:find(p) then
          Commands[name] = function(ctx, ...)
            local a = {}
            for i = 1, select("#", ...) do a[i] = tostring((select(i, ...))) end
            print(("[cmd] %s(%s) npc=%s"):format(name, table.concat(a, ","),
              tostring(ctx and ctx.npc and ctx.npc.def and ctx.npc.def.localId)))
            return fn(ctx, ...)
          end
          break
        end
      end
    end
  end
end

-- HOUR=n: the wall clock reads hour n (0-23) today, so the area light and the
-- time-of-day prop animations (Gen4PropClock: the lighthouse lamp, Violet's
-- lanterns, the Pokémon Center dome) can be pictured at night
if os.getenv("HOUR") then
  local date, hour = os.date, tonumber(os.getenv("HOUR"))
  os.date = function(fmt, t)
    local out = date(fmt, t)
    if type(out) == "table" and hour then out.hour = hour end
    return out
  end
end

-- FOG_OFF=1: a map script's fog (Morty's gym) is dropped again at once, to
-- see what is under it
if os.getenv("FOG_OFF") then
  local Commands = require("src.script.Commands")
  require("src.script.Gen4Commands")
  local init = Commands.g4_ecruteak_gym_init
  Commands.g4_ecruteak_gym_init = function(ctx, ...)
    init(ctx, ...)
    local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
    if def then def.gen4Fog = nil end
    local list = def and def.gen4RuntimeProps or {}
    for _, p in ipairs(list) do print(("[fog off] prop %s at %s,%s,%s"):format(p.model, p.x, p.y, p.z)) end
  end
end

-- AUTO_BATTLE=win|lose: a script's battle ends at once with that result, so
-- the branch the script takes after it can be watched without fighting
if os.getenv("AUTO_BATTLE") then
  local Commands = require("src.script.Commands")
  Commands.start_battle = function(ctx, kind, id)
    -- AUTO_BATTLE_WILD=caught: a different result for a wild battle
    ctx.lastBattleResult = (kind == "wild" and os.getenv("AUTO_BATTLE_WILD")) or os.getenv("AUTO_BATTLE")
    print(("[auto battle] %s %s -> %s"):format(tostring(kind), tostring(id), ctx.lastBattleResult))
  end
end

-- MUSIC_TRACE=1: the harness has no audio device (conf.lua), so Music.play
-- would return at once. This stands in a silent device -- a queue source the
-- DS sequencer (src/audio/NitroAudio.lua) renders into for real -- and logs
-- every cue plus each change of [music] song / playing state per tick, so a
-- sequence that dies mid-battle shows up as `playing=false`.
if os.getenv("MUSIC_TRACE") then
  local function fake(queue)
    return setmetatable({ playing = false }, { __index = function(_, k)
      if k == "isPlaying" then return function(s) return queue and s.playing or false end
      elseif k == "play" then return function(s) s.playing = true; return true end
      elseif k == "stop" or k == "pause" then return function(s) s.playing = false end
      elseif k == "getFreeBufferCount" then return function(s) s.free = not s.free; return s.free and 1 or 0 end
      elseif k == "getVolume" then return function() return 1 end end
      return function() return 0 end
    end })
  end
  love.audio = love.audio or { newQueueableSource = function() return fake(true) end,
    newSource = function() return fake(false) end, setVolume = function() end, stop = function() end }
  love.sound = love.sound or { newSoundData = function() return fake(false) end }
  -- MUSIC_TRACE_NITRO=<file>: another NitroAudio.lua (an older copy) for a
  -- before / after comparison
  if os.getenv("MUSIC_TRACE_NITRO") then
    package.loaded["src.audio.NitroAudio"] = assert(loadfile(os.getenv("MUSIC_TRACE_NITRO")))()
  end
  local Music = require("src.core.Music")
  local play, update = Music.play, Music.update
  Music.play = function(data, song, loop, ctx)
    print(("[music] cue %s (%s) reason=%s"):format(tostring(song),
      tostring(data and data.audio and data.audio.songs and data.audio.songs[song] and data.audio.songs[song].name),
      tostring(ctx and ctx.reason)))
    return play(data, song, loop, ctx)
  end
  local tick, last = 0, nil
  Music.update = function(data, ...)
    local r = update(data, ...)
    tick = tick + 1
    local cur = Music.current()
    local src
    for i = 1, 60 do
      local n, v = debug.getupvalue(play, i)
      if not n then break end
      if n == "state" then src = v and v.source break end
    end
    local playing = src and src:isPlaying() or false
    local key = tostring(cur) .. "/" .. tostring(playing)
    if key ~= last then
      last = key
      print(("[music] tick %d current=%s playing=%s"):format(tick, tostring(cur), tostring(playing)))
    end
    return r
  end
  -- gen4_battle_harness ticks the battle alone; tick the music with it
  if os.getenv("HARNESS") == "gen4_battle_harness" then
    local BS = require("src.battle.BattleState")
    local bupdate = BS.update
    BS.update = function(self, ...)
      local r = { bupdate(self, ...) }
      pcall(Music.update, self.data)
      return (table.unpack or unpack)(r)
    end
  end
end

-- HGSS_FIELD_ROM=<HeartGold/SoulSilver .nds>: the water animation and the
-- "!" art read from the ROM into memory (field_rom.lua)
if os.getenv("HGSS_FIELD_ROM") then dofile("tools/gen4_hgss_overworld_harness/field_rom.lua") end
-- BW_FIELD_ROM=<Black/White .nds>: the field effects read from the ROM as the
-- data loads (bw_field_rom.lua)
if os.getenv("BW_FIELD_ROM") then dofile("tools/gen4_hgss_overworld_harness/bw_field_rom.lua") end

-- HARNESS picks another Gen 4 harness to run on the same mounted install
-- (gen4_battle_harness, ...); the overworld one by default
local harness = os.getenv("HARNESS") or "gen4_overworld_harness"
assert(harness:match("^gen4_[%w_]+_harness$"), "HARNESS names a tools/gen4_*_harness folder")
dofile(("tools/%s/main.lua"):format(harness))

-- CAM_TILT=cartridge|third|first|<degrees>: the options menu's CAM TILT row,
-- chosen before the first frame -- Platinum's camera modes on this install
local camTilt = os.getenv("CAM_TILT")
if camTilt then
  -- applied as the overworld is PUSHED: the overworld harness runs its whole
  -- tick loop inside love.load, so a tilt chosen after load came too late
  -- for every tick (the run walked on the cartridge camera whatever was asked)
  local StateStack = require("src.core.StateStack")
  local push0, applied = StateStack.push, false
  local function applyTilt()
    local Gen4Camera = require("src.render.Gen4Camera")
    local G = package.loaded["src.core.Game"]
    local at
    for i, t in ipairs(Gen4Camera.TILTS) do
      if tostring(t) == camTilt or (tonumber(camTilt) and tonumber(t) and math.abs(tonumber(t) - tonumber(camTilt)) < 0.5) then at = i end
    end
    assert(at, "CAM_TILT is one of: " .. table.concat((function()
      local l = {} for _, t in ipairs(Gen4Camera.TILTS) do l[#l + 1] = tostring(t) end return l end)(), ", "))
    if G and G.save then G.save.options = G.save.options or {}; G.save.options.gen4CameraTilt = at end
    Gen4Camera.setTilt(at)
    print(("[cam] tilt %s (row %d)"):format(tostring(Gen4Camera.TILTS[at]), at))
  end
  StateStack.push = function(self, state, ...)
    local G = package.loaded["src.core.Game"]
    if not applied and G and G.save and state == package.loaded["src.world.OverworldController"] then
      applied = true
      applyTilt()
    end
    return push0(self, state, ...)
  end
end

-- HGSS_MART_ROM=<HeartGold/SoulSilver .nds>: data.gen4_hgss_mart_art (the Poke
-- Mart's BUY touch screen, src/import/Gen4HgssMartArt.lua) decoded from the
-- ROM into memory as the overworld is pushed, for an install imported before
-- it existed (the install is not written)
if os.getenv("HGSS_MART_ROM") then
  local StateStack = require("src.core.StateStack")
  local push, injected = StateStack.push, false
  StateStack.push = function(self, state, ...)
    local G = package.loaded["src.core.Game"]
    if not injected and G and G.data then
      injected = true
      local rom = assert(require("src.import.NdsRom").open(os.getenv("HGSS_MART_ROM")))
      local idx, n = {}, 0
      for key, img in pairs(require("src.import.Gen4HgssMartArt").images(rom) or {}) do
        idx[key] = { image = love.image.newImageData(img.width, img.height, "rgba8", img.rgba),
                     originX = img.originX, originY = img.originY }
        n = n + 1
      end
      G.data.gen4_hgss_mart_art = idx
      print(("[mart] gen4_hgss_mart_art from the ROM: %d pictures"):format(n))
    end
    return push(self, state, ...)
  end
end

-- HGSS_SUMMARY_ROM=<HeartGold/SoulSilver .nds>: gen4_hgss_summary_art decoded
-- from the ROM into memory (src/import/Gen4HgssSummaryArt.lua -- the egg /
-- blank pages and the /a/0/3/9 status, marking and ribbon sprites an older
-- install lacks); the install is not written. RIBBONS=1,33,73: the summary's
-- Pokemon holds those ribbons; MON_STATUS=PSN / SHINY=1 / POKERUS=1 /
-- MARKINGS=<bits> likewise.
if os.getenv("HGSS_SUMMARY_ROM") or os.getenv("RIBBONS") or os.getenv("MON_STATUS")
  or os.getenv("SHINY") or os.getenv("POKERUS") or os.getenv("MARKINGS") then
  local Summary = require("src.ui.HgssSummaryMenu")
  local new, loaded = Summary.new, false
  Summary.new = function(game, arg)
    if os.getenv("HGSS_SUMMARY_ROM") and not loaded and game and game.data then
      loaded = true
      local rom = assert(require("src.import.NdsRom").open(os.getenv("HGSS_SUMMARY_ROM")))
      local idx, n = {}, 0
      for key, rec in pairs(game.data.gen4_hgss_summary_art or {}) do idx[key] = rec end
      for key, img in pairs(require("src.import.Gen4HgssSummaryArt").images(rom) or {}) do
        idx[key] = { image = love.image.newImageData(img.width, img.height, "rgba8", img.rgba),
                     originX = img.originX, originY = img.originY }
        n = n + 1
      end
      game.data.gen4_hgss_summary_art = idx
      print(("[summary] gen4_hgss_summary_art from the ROM: %d pictures"):format(n))
    end
    local mon = type(arg) == "table" and (arg.species and arg or arg.mon)
    if mon then
      if os.getenv("RIBBONS") then
        mon.ribbons = mon.ribbons or {}
        for id in os.getenv("RIBBONS"):gmatch("%d+") do mon.ribbons[tonumber(id)] = true end
      end
      if os.getenv("MON_STATUS") then mon.status = os.getenv("MON_STATUS") end
      if os.getenv("POKERUS") then mon.pokerus = tonumber(os.getenv("POKERUS")) end
      if os.getenv("MARKINGS") then mon.markings = tonumber(os.getenv("MARKINGS")) end
      if os.getenv("SHINY") then mon.shiny = true end
    end
    return new(game, arg)
  end
end

-- HGSS_PHONE_ROM=<HeartGold/SoulSilver .nds>: data.gen4_hgss_phone_call read
-- from the ROM as the overworld is pushed (src/import/Gen4HgssPhoneCall.lua),
-- so the scripted Pokegear calls run on an install imported before it existed
if os.getenv("HGSS_PHONE_ROM") then
  local StateStack = require("src.core.StateStack")
  local push, injected = StateStack.push, false
  StateStack.push = function(self, state, ...)
    local G = package.loaded["src.core.Game"]
    if not injected and G and G.data then
      injected = true
      local path = os.getenv("HGSS_PHONE_ROM")
      local rom = assert(require("src.import.NdsRom").open(path))
      local X = assert(require("src.import.RomExtractorGen4").new(path, os.getenv("VERSION") or "heartgold"))
      G.data.gen4_hgss_phone_call = require("src.import.Gen4HgssPhoneCall").read(rom,
        function(bank, i) return X:string(bank, i) end)
      X:close()
      print(("[phone] gen4_hgss_phone_call from %s: %d phonebook rows"):format(path, G.data.gen4_hgss_phone_call.book.count))
    end
    return push(self, state, ...)
  end
end

-- HGSS_PROP_ROM=<HeartGold/SoulSilver .nds>: the map prop animations
-- (gen4_models.sets.field / interiorField, src/import/Gen4HgssPropAnim.lua)
-- read from the ROM as the overworld is pushed, with the flipbook frames the
-- import would write decoded into memory instead -- so the windmill turns on
-- an install imported before they existed. HGSS_PROP_OFF=1: drop them instead
-- (the "before" picture).
if os.getenv("HGSS_PROP_ROM") or os.getenv("HGSS_PROP_OFF") then
  local StateStack = require("src.core.StateStack")
  local push, injected = StateStack.push, false
  local memory = {}
  local Assets = require("src.render.Assets")
  local image = Assets.image
  Assets.image = function(path, ...)
    if type(path) == "string" and memory[path] then
      local img = love.graphics.newImage(memory[path])
      return img
    end
    return image(path, ...)
  end
  StateStack.push = function(self, state, ...)
    local G = package.loaded["src.core.Game"]
    if not injected and G and G.data and G.data.gen4_models then
      injected = true
      local sets = G.data.gen4_models.sets or {}
      if os.getenv("HGSS_PROP_OFF") then
        sets.field, sets.interiorField = nil, nil
        print("[props] prop animations dropped")
        return push(self, state, ...)
      end
      local path = os.getenv("HGSS_PROP_ROM")
      local X = assert(require("src.import.RomExtractorGen4").new(path, os.getenv("VERSION") or "heartgold"))
      local P = require("src.import.Gen4HgssPropAnim")
      local report = assert(P.extractInto(X, G.data.gen4_models))
      -- the BTP0 frames, decoded from each claiming model's own TEX0
      local Nsbmd = require("src.import.Gen4Nsbmd")
      local Models = require("src.import.Gen4Models")
      local Graphics = require("src.import.Gen4Graphics")
      local ImageWriter = require("src.import.ImageWriter")
      local frames = 0
      for key, modelsKey, archive in ([[field buildings /a/0/4/0 interiorField interiorBuildings /a/1/4/8]]):gmatch("(%S+) (%S+) (%S+)") do
        local fset, mset = sets[key], sets[modelsKey]
        local arc = X:archiveAt(archive)
        for _, record in ipairs((fset and fset.animations) or {}) do
          for _, index in ipairs((record.pattern and (record.props or record.scriptProps)) or {}) do
            local packed = mset and mset.models and mset.models[index + 1]
            local bytes = packed and arc and arc:get(index)
            if bytes and Graphics.isCompressed(bytes) then bytes = Graphics.decompress(bytes) end
            local sections = bytes and Nsbmd.sections(bytes)
            local textures = sections and sections.TEX0 and Models.parse(bytes, sections.TEX0)
            if textures then
              packed.patternImages = packed.patternImages or {}
              for i, name in ipairs(record.pattern.textures or {}) do
                local ti, pi
                for j, t in ipairs(textures.textures) do if t.name == name then ti = j end end
                for j, p in ipairs(textures.palettes) do if p.name == (record.pattern.palettes or {})[i] then pi = j end end
                local img = ti and Models.decode(textures, bytes, ti, pi or 1)
                local data = img and ImageWriter.fromRGBA8(img.width, img.height, img.rgba)
                if data then
                  local key2 = ("hgssprop:%s/%d/%s"):format(modelsKey, index, name)
                  memory[key2] = data
                  packed.patternImages[name] = key2
                  frames = frames + 1
                end
              end
            end
          end
        end
      end
      X:close()
      print(("[props] from %s: outdoor %d props / %d records, rooms %d props / %d records, %d flipbook frames"):format(
        path, report.field and report.field.props or 0, report.field and report.field.records or 0,
        report.interiorField and report.interiorField.props or 0,
        report.interiorField and report.interiorField.records or 0, frames))
    end
    return push(self, state, ...)
  end
end

-- SET_VARS="0x4108=1,0x4030=152", SET_FLAGS / CLEAR_FLAGS="0x6A,0x73", APRICORNS: story state
-- before the first frame, through the engine's own setters, so a later
-- scene can be tested without playing up to it
if os.getenv("SET_VARS") or os.getenv("SET_FLAGS") or os.getenv("CLEAR_FLAGS") or os.getenv("APRICORNS") or os.getenv("KURT") or os.getenv("BADGES") or os.getenv("STRENGTH") then
  -- applied as the overworld is pushed: that is after the new save exists
  -- and before the first tick (this harness ticks inside love.load)
  local StateStack = require("src.core.StateStack")
  local push, applied = StateStack.push, false
  StateStack.push = function(self, state, ...)
    if not applied and state == require("src.world.OverworldController") then
      applied = true
      local G = package.loaded["src.core.Game"]
      local G4 = require("src.script.Gen4Commands")
      local Commands = require("src.script.Commands")
      local ctx = { save = G and G.save, game = G }
      -- STRENGTH=1: Strength already active, as the field-move script leaves it
      if os.getenv("STRENGTH") and ctx.save then
        ctx.save.gen4FieldMoveFlags = ctx.save.gen4FieldMoveFlags or {}
        ctx.save.gen4FieldMoveFlags.strength = true
        _G.__harnessStrength = true
      end
      -- BADGES=all (or a count): field-move tests need the badge checks to pass
      if os.getenv("BADGES") and ctx.save then
        local Badges = require("src.inventory.Badges")
        local list = Badges.list(G and G.data) or {}
        local n = tonumber(os.getenv("BADGES")) or #list
        for i = 1, math.min(n, #list) do Badges.set(ctx.save, list[i], true) end
        print(("[state] %d badge(s) given"):format(math.min(n, #list)))
      end
      for id, value in tostring(os.getenv("SET_VARS") or ""):gmatch("(%w+)=(%w+)") do
        G4.setVar(ctx.save, tonumber(id), tonumber(value))
        print(("[state] var %s = %s"):format(id, value))
      end
      for id in tostring(os.getenv("SET_FLAGS") or ""):gmatch("%w+") do
        Commands.set_flag(ctx, ("FLAG_G4_%04X"):format(tonumber(id)))
        print(("[state] flag %s set"):format(id))
      end
      for id in tostring(os.getenv("CLEAR_FLAGS") or ""):gmatch("%w+") do
        Commands.clear_flag(ctx, ("FLAG_G4_%04X"):format(tonumber(id)))
        print(("[state] flag %s clear"):format(id))
      end
      -- APRICORNS="3=5,0=2": colour (0 red .. 6 black) = how many in the box
      for colour, n in tostring(os.getenv("APRICORNS") or ""):gmatch("(%d+)=(%d+)") do
        require("src.world.HgssApricorns").give(ctx.save, tonumber(colour), tonumber(n))
        print(("[state] apricorn %s x%s"):format(colour, n))
      end
      -- KURT="2=3": Kurt already holds 3 of colour 2 (a day has passed)
      for colour, n in tostring(os.getenv("KURT") or ""):gmatch("(%d+)=(%d+)") do
        local A = require("src.world.HgssApricorns")
        A.give(ctx.save, tonumber(colour), tonumber(n))
        A.setKurt(ctx.save, tonumber(colour), tonumber(n))
        print(("[state] Kurt holds %s of colour %s"):format(n, colour))
      end
    end
    return push(self, state, ...)
  end
end

-- SECOND_SCREEN=off: single-screen play (the battle's own panel, the
-- supersampled picture -- src/render/SuperSample.lua), as with the option off
-- DEPTH_FORMAT=depth16 (etc.): the driver offers only that depth format, as
-- a phone with no 24-bit depth does (src/render/Gen4Model.lua chooseDepthFormat)
if os.getenv("DEPTH_FORMAT") then
  local only = os.getenv("DEPTH_FORMAT")
  local formats = love.graphics.getCanvasFormats
  love.graphics.getCanvasFormats = function(...)
    local t = formats(...)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    for _, f in ipairs({ "depth24", "depth24stencil8", "depth32f", "depth16" }) do out[f] = (f == only) end
    return out
  end
end

if os.getenv("SECOND_SCREEN") == "off" then
  local SS = require("src.ui.SecondScreen")
  SS.mode = function() return "off" end
end

-- ENC_FORCE=1: every step's rate check passes, so a short walk tests the
-- rest of the encounter path (table, slot, battle) instead of luck
if os.getenv("ENC_FORCE") then
  local Encounter = require("src.world.Encounter")
  Encounter.gen4StepAllowed = function() return true end
end

-- ENC_DEBUG=1: every encounter roll and every grass-cell answer, logged
if os.getenv("ENC_DEBUG") then
  local OW = require("src.world.OverworldController")
  local roll = OW.rollEncounter
  OW.rollEncounter = function(self, encDef, terrain)
    local enc = roll(self, encDef, terrain)
    print(("[enc] roll %s table=%s -> %s"):format(tostring(terrain),
      tostring(encDef and encDef.grass and #encDef.grass or nil), enc and tostring(enc.species) or "none"))
    return enc
  end
  local Map = require("src.world.Map")
  local isEnc = Map.isEncounterCell
  Map.isEncounterCell = function(self, cx, cy)
    local yes = isEnc(self, cx, cy)
    print(("[enc] cell %d,%d grass=%s"):format(cx, cy, tostring(yes)))
    return yes
  end
end

-- PROBE_CELL=x,y: after load, say which chunk the loaded terrain has there
local probe = os.getenv("PROBE_CELL")
if probe then
  local load = love.load
  love.load = function(...)
    local r = { load(...) }
    local x, y = probe:match("(%d+),(%d+)")
    local G = rawget(_G, "Game")
    local data = G and G.data or package.loaded["src.core.Data"]
    local t = data and data.gen4_terrain
    local g = t and t.matrices and t.matrices[0]
    print(("PROBE terrain source=%s grid=%sx%s land=%s"):format(tostring(t and t.source),
      tostring(g and g.width), tostring(g and g.height),
      tostring(g and g.land[tonumber(y) * g.width + tonumber(x) + 1])))
    return table.unpack and table.unpack(r) or unpack(r)
  end
end

