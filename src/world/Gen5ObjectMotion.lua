-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SCRIPTED OBJECT MOTIONS (overlay 10): an object raised or lowered in place
-- (0x225) and the Relic Song's dance round its own spot (0x226) -- Meloetta
-- in Castelia's cafe (Z053).
--
-- READ FROM CODE (Black):
--   0x225 <object, height, frames> (ov10 0x0216A7A0, task 0x0216A839): the
--         object's y goes from where it is to height << 15 (8 units a step)
--         in a straight line, y0 + (target - y0) * k / frames, k = 1..frames,
--         its ground-follow off (MapObject flag 0x8000); the script waits
--   0x226 <object> (0x0216A884, task 0x0216A8F1): three phases round the
--         spot it stood on (+8 its start position), the counter reset each
--         phase, angle index (angle >> 4) into the sin/cos table 0x020A1B38,
--         x += cos * r, z += sin * r, y kept:
--           0: 110 frames, angle (k << 17) / 110 (two turns), r = 3k/110 * 16
--              units (out to three tiles);
--           1: 80 frames, angle (k << 16) / 80 (one turn), r three tiles;
--           2: 80 frames, one turn, r = 3 (80 - k) / 80 tiles (back in);
--         the script waits for all 270 frames
-- INFERRED: one step a field frame (Gen4FieldFx's 2 ticks); the height is
-- shown as a sprite lift over the ground under the object.

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end
local function tpf() return require("src.world.Gen4FieldFx").TICKS_PER_FRAME end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local function groundAt(ow, e)
  local g = ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  return g and g.groundY and g:groundY((e.px or 0) + 8, (e.py or 0) + 8) or 0
end

local function liftOf(e) return e.spriteOffset and tonumber(e.spriteOffset.lift) or 0 end
local function setLift(e, lift) e.spriteOffset = { lift = lift, gen5Motion = true } end

local function add(ow, m)
  ow.gen5Motions = ow.gen5Motions or {}
  table.insert(ow.gen5Motions, m)
end

local function waitFrames(ctx, n)
  if ctx.runner and n > 0 then Commands.wait(ctx, n * tpf()) end
end

function Commands.g5_object_height(ctx, obj, height, frames)
  local ow = ctx.overworld
  local e = ow and G4().objectById and G4().objectById(ctx, val(ctx, obj))
  if not e then return end
  local n = math.max(1, val(ctx, frames))
  local ground = groundAt(ow, e)
  local y0 = ground + liftOf(e)
  local target = val(ctx, height) * 8
  add(ow, { e = e, k = 0, tick = 0, n = n, step = function(m)
    setLift(e, y0 + (target - y0) * m.k / n - ground)
  end })
  waitFrames(ctx, n)
end

local TAU = 2 * math.pi
local PHASES = {
  { n = 110, turns = 2, r = function(k) return 48 * k / 110 end },
  { n = 80, turns = 1, r = function() return 48 end },
  { n = 80, turns = 1, r = function(k) return 48 * (80 - k) / 80 end },
}

function Commands.g5_object_dance(ctx, obj)
  local ow = ctx.overworld
  local e = ow and G4().objectById and G4().objectById(ctx, val(ctx, obj))
  if not e then return end
  local bx, bz = e.px or 0, e.py or 0
  local phase, total = 1, 0
  for _, p in ipairs(PHASES) do total = total + p.n end
  add(ow, { e = e, k = 0, tick = 0, n = total, step = function(m)
    -- which phase frame m.k (1..270) falls in
    local k, i = m.k, 1
    while i < #PHASES and k > PHASES[i].n do k = k - PHASES[i].n; i = i + 1 end
    phase = i
    local p = PHASES[phase]
    local a = TAU * p.turns * k / p.n
    local r = p.r(k)
    e.px = bx + math.cos(a) * r
    e.py = bz + math.sin(a) * r
  end, done = function()
    e.px, e.py = bx, bz
  end })
  waitFrames(ctx, total)
end

-- every engine tick (OverworldState:update / animate)
function M.tick(ow)
  local list = ow and ow.gen5Motions
  if not list then return end
  for i = #list, 1, -1 do
    local m = list[i]
    m.tick = m.tick + 1
    if m.tick % tpf() == 0 then
      m.k = m.k + 1
      pcall(m.step, m)
      if m.k >= m.n then
        table.remove(list, i)
        if m.done then pcall(m.done) end
      end
    end
  end
  if #list == 0 then ow.gen5Motions = nil end
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwobjectheight = L.bwobjectheight or function(ins, s) emit(s, { "g5_object_height", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwobjectdance = L.bwobjectdance or function(ins, s) emit(s, { "g5_object_dance", ins.args[1] }) end
end

return M
