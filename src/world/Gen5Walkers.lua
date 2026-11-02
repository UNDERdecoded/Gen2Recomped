-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S STREET CROWDS: Castelia's passers-by and Tubeline Bridge's
-- (script command 0x134, overlay 55). The data is src/import/Gen5Walkers.lua's.
--
-- READ FROM CODE (Black, ov55; record 0x021F45F0 = { 0, work 0x3D8, init
-- 0x021F39C0, exit 0x021F3A64, update 0x021F3AA4 }):
--   * 32 walker slots of 0x18 bytes (+8), each a real map object (0x0216CE60
--     from the header 0x021F4620, its sprite the line's pick)
--   * every field frame each line's counter rises; at the time of day's
--     interval it resets and a walker is sent (0x021F3F30) -- unless the
--     start cell's line already has a walker there (0x021F3B48)
--   * a walker starts at the line's fixed coordinate (z0 for directions 0 /
--     1, x0 for 2 / 3) and a random one in the other range, and walks its
--     line's `steps` cells with the speed's movement (0x021F40F4)
--     (0x021F3F9C / 0x021F3D0C)
--   * blocked by the player or another object in front (0x021F42AC), it
--     steps aside -- a random one of the two perpendicular directions,
--     turned back if that leaves the line's range -- without counting the
--     step (0x021F3DD4); when its steps are spent it is removed (0x021F3DBC)
-- INFERRED: the line coordinates are zone-local; the time of day is
-- Gen5Roamers.period's (0x02189A38 is not followed); a walker's talk script
-- (its row's pick, a common script 0x286E..) is set for good, where the
-- cartridge sets it only while the player is in front of it and in range
-- (0x021F4318) and 0x7D0 otherwise; a walker that cannot step aside waits.

local M = {}

M.POOL = 32
M.SPEED = { [2] = 0x14, [4] = 0x10, [6] = 0x4C, [8] = 0x0C, [16] = 0x08 }
M.DIRS = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
M.DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function game() return package.loaded["src.core.Game"] end

local function config(data, zone)
  local c = data and data.constants and data.constants.gen5Walkers
  local z = c and c.zones
  return z and (z[zone] or z[tostring(zone)]) or nil
end

local sheets = {}
local function sheetFor(data, gfx)
  if sheets[gfx] ~= nil then return sheets[gfx] or nil end
  for _, def in pairs(data and data.maps or {}) do
    for _, o in ipairs(type(def) == "table" and def.objects or {}) do
      if o.graphicsId == gfx and o.sprite then sheets[gfx] = { o.sprite, o.spriteName }; return sheets[gfx] end
    end
  end
  -- (an id no map places: the sprite table itself)
  local key, name = require("src.script.Gen4Commands").bwSpriteFromTable(data, gfx)
  if key then sheets[gfx] = { key, name }; return sheets[gfx] end
  sheets[gfx] = false
  return nil
end

-- the common script's label for a band id (as Gen5Dive runs 0x271B): what
-- the talk path reads off an object's `text`
local function bandLabel(data, id)
  if not (id and id > 0) then return nil end
  local okV, VM = pcall(require, "src.script.Gen4ScriptVM")
  local pool = okV and VM.store and VM.store(data)
  local Bands = require("src.import.Gen4ScriptBands")
  local kind, name, index = Bands.classify(id)
  local band = pool and pool.bands and kind == "band" and pool.bands[name]
  return band and band.entries and band.entries[index + 1] or nil
end

local function stepTicks(speed)
  local code = M.SPEED[speed] or 0x0C
  local ok, Mv = pcall(require, "src.import.Gen5Movement")
  local a = ok and Mv.action(code)
  return (a and a.frames or 8) * 2
end

-- forget every walker on `ow`'s previous map
function M.clear(ow)
  local st = ow and ow.gen5Walkers
  if not st then return end
  local def = st.def
  if def and def.objects then
    local keep = {}
    for _, o in ipairs(def.objects) do if not o.gen5Walker then keep[#keep + 1] = o end end
    def.objects = keep
  end
  if ow.npcs then
    local keep = {}
    for _, n in ipairs(ow.npcs) do if not (n.def and n.def.gen5Walker) then keep[#keep + 1] = n end end
    ow.npcs = keep
  end
  ow.gen5Walkers = nil
end

-- 0x134: start the crowd on the current map
function M.start(ow, data)
  local def = ow and ow.map and ow.map.def
  local cfg = def and config(data, tonumber(def.header))
  if not cfg then return false end
  if ow.gen5Walkers and ow.gen5Walkers.def == def then return true end
  M.clear(ow)
  local counters = {}
  for i = 1, #cfg.lines do counters[i] = 0 end
  ow.gen5Walkers = { def = def, map = ow.map.id, cfg = cfg, counters = counters, list = {},
                     ticks = stepTicks(cfg.speed), serial = 0 }
  return true
end

local function npcOf(ow, obj)
  for _, n in ipairs(ow.npcs or {}) do if n.def == obj then return n end end
  return nil
end

local function occupied(ow, x, y)
  local p = ow.player
  if p and ((p.cellX == x and p.cellY == y) or (p.targetX == x and p.targetY == y)) then return true end
  for _, n in ipairs(ow.npcs or {}) do
    if not n.hidden and ((n.cellX == x and n.cellY == y) or (n.targetX == x and n.targetY == y)) then return true end
  end
  return false
end

local function spawn(ow, data, st, line)
  if #st.list >= M.POOL then return end
  local cfg = st.cfg
  local r = love.math.random
  local x, y
  if line.dir <= 1 then
    x, y = line.x0 + r(0, math.max(0, line.x1 - line.x0)), line.z0
  else
    x, y = line.x0, line.z0 + r(0, math.max(0, line.z1 - line.z0))
  end
  if occupied(ow, x, y) then return end
  local gfx = cfg.sprites[r(1, math.max(1, #cfg.sprites))]
  local sheet = gfx and sheetFor(data, gfx)
  if not sheet then return end
  -- the walker's talk script: one of its sprite's six (member 6, 0x021F3C62)
  local rows = data and data.constants and data.constants.gen5Walkers and data.constants.gen5Walkers.rows
  local row = rows and (rows[gfx] or rows[tostring(gfx)])
  local script = row and row[r(1, 6)] or 0
  local label = bandLabel(data, script)
  -- the map's own talk scripts do not hold a common one: added here, as
  -- Gen5BlackCity adds its residents'
  if label and ow.map and ow.map.id then
    local MS = require("src.script.MapScripts")
    if not MS.talkScript(ow.map.id, label) then
      local VM = require("src.script.Gen4ScriptVM")
      local okC, rows = pcall(VM.compile, data, label)
      if okC and rows then MS.attachBase(ow.map.id, { talk = { [label] = rows } }) end
    end
  end
  local def = st.def
  local maxIndex = 0
  for _, o in ipairs(def.objects or {}) do maxIndex = math.max(maxIndex, tonumber(o.index) or 0) end
  st.serial = st.serial + 1
  local dir = M.DIRS[line.dir] or "down"
  local obj = { index = maxIndex + 1, localId = 0x200 + st.serial, graphicsId = gfx, sprite = sheet[1],
    spriteName = sheet[2], x = x, y = y, direction = line.dir, movementType = 0, movementRangeX = 0,
    movementRangeY = 0, script = script, text = label, elevation = 0, gen5 = true, gen5Temp = true, gen5Walker = true }
  def.objects = def.objects or {}
  def.objects[#def.objects + 1] = obj
  if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(obj) end) end
  local npc = npcOf(ow, obj)
  if not npc then return end
  npc.facing = dir
  st.list[#st.list + 1] = { obj = obj, npc = npc, dir = dir, steps = line.steps, line = line }
end

local function remove(ow, st, w)
  w.obj.hidden = true
  if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(w.obj) end) end
  local def = st.def
  local keep = {}
  for _, o in ipairs(def.objects or {}) do if o ~= w.obj then keep[#keep + 1] = o end end
  def.objects = keep
  if ow.npcs then
    local nk = {}
    for _, n in ipairs(ow.npcs) do if n ~= w.npc then nk[#nk + 1] = n end end
    ow.npcs = nk
  end
end

local PERP = { up = { "left", "right" }, down = { "left", "right" }, left = { "up", "down" }, right = { "up", "down" } }

local function begin(st, w, dir)
  local n = w.npc
  local d = M.DELTA[dir]
  n.facing = dir
  n.targetX, n.targetY = n.cellX + d[1], n.cellY + d[2]
  n.moving, n.progress = true, 0
  n.scriptStepLen = st.ticks
end

-- one field frame
local function step(ow, data, st)
  -- a script running (a walker talked to) holds the crowd, as the field's
  -- object lock does
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return end
  local period = 1
  local okR, R = pcall(require, "src.world.Gen5Roamers")
  if okR and R.period then period = tonumber(R.period()) or 1 end
  for i, line in ipairs(st.cfg.lines) do
    st.counters[i] = st.counters[i] + 1
    local every = st.cfg.intervals[math.max(1, math.min(5, period + 1))] or 60
    if st.counters[i] >= every then
      st.counters[i] = 0
      spawn(ow, data, st, line)
    end
  end
  local keep = {}
  for _, w in ipairs(st.list) do
    local n = w.npc
    local alive = true
    if not n.moving then
      if w.steps <= 0 then
        remove(ow, st, w)
        alive = false
      else
        local d = M.DELTA[w.dir]
        local tx, ty = n.cellX + d[1], n.cellY + d[2]
        if occupied(ow, tx, ty) then
          -- 0x021F3DD4: aside, within the line's range
          local side = PERP[w.dir][love.math.random(1, 2)]
          local sd = M.DELTA[side]
          local sx, sy = n.cellX + sd[1], n.cellY + sd[2]
          local l = w.line
          local inside = (w.dir == "up" or w.dir == "down") and (sx >= l.x0 and sx <= l.x1)
                         or (sy >= l.z0 and sy <= l.z1)
          if not inside then
            side = (side == "left" and "right") or (side == "right" and "left")
                   or (side == "up" and "down") or "up"
            sd = M.DELTA[side]
            sx, sy = n.cellX + sd[1], n.cellY + sd[2]
          end
          if not occupied(ow, sx, sy) then begin(st, w, side); n.facing = w.dir end
        else
          begin(st, w, w.dir)
          w.steps = w.steps - 1
        end
      end
    end
    if alive then keep[#keep + 1] = w end
  end
  st.list = keep
end

-- every engine frame; the crowd steps on the field's 30
function M.update(ow, dt)
  local st = ow and ow.gen5Walkers
  if not st then return end
  if not (ow.map and ow.map.id == st.map and ow.map.def == st.def) then M.clear(ow); return end
  local G = game()
  local data = G and G.data
  st.acc = (st.acc or 0) + (tonumber(dt) or 0) * 30
  local n = 0
  while st.acc >= 1 and n < 4 do st.acc = st.acc - 1; step(ow, data, st); n = n + 1 end
  if st.acc > 4 then st.acc = 0 end
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
function Commands.g5_crowd(ctx)
  local ow = ctx and ctx.overworld
  local data = ctx and ctx.game and ctx.game.data
  if ow then M.start(ow, data) end
end

function M.install(L)
  L.bwcrowd = L.bwcrowd or function(ins, s) s.out[#s.out + 1] = { "g5_crowd" } end
end

return M
