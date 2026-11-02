-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ZORUA'S ILLUSION (scripts 0x221..0x224, overlay 59): the puff that hides
-- a disguise, played with Gen4FieldFx's field-object player.
--
-- READ FROM CODE (Black):
--   0x222 <effect, x, y, z> (ov10 0x0216BC88 -> ov59 0x021F3AA0): the effect
--         placed at tile (x, z) centre, height y * 8 units (x << 16 + 0x8000,
--         y << 15, z << 16 + 0x8000), its sound played (0x567 effect 0,
--         0x793 effect 1)
--   0x224 <effect> (0x0216BD1C -> 0x021F3B40) starts it, 0x223 <effect>
--         (0x0216BCE4 -> 0x021F3B68) waits for it, each a field task
-- INFERRED: the tile coordinates are the matrix's (the origin is taken off,
-- as 0x069 does); 0x221 <effect, x, y, z, ...> (0x0216BBD4) is read as the
-- effect's end (its task 0x021F3C6D moves the effect between two points and
-- is not followed); the animation runs for its longest track.

local M = {}

M.SE = { [0] = 0x567, [1] = 0x793 }

local function G4() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local function origin(ow)
  local def = ow and ow.map and ow.map.def
  return tonumber(def and def.originX) or 0, tonumber(def and def.originY) or 0
end

function Commands.g5_illusion_place(ctx, effect, x, y, z)
  local ow = ctx.overworld
  if not ow then return end
  local ox, oy = origin(ow)
  local e = val(ctx, effect)
  ow.gen5Illusion = ow.gen5Illusion or {}
  ow.gen5Illusion[e] = { x = (val(ctx, x) - ox) * 16 + 8, z = (val(ctx, z) - oy) * 16 + 8, y = val(ctx, y) * 8 }
  pcall(function() require("src.core.Sound").playSe(ctx.game.data, M.SE[e] or M.SE[1]) end)
end

function Commands.g5_illusion_start(ctx, effect)
  local ow = ctx.overworld
  local e = val(ctx, effect)
  local at = ow and ow.gen5Illusion and ow.gen5Illusion[e]
  if not at then return end
  local FX = require("src.world.Gen4FieldFx")
  FX.clear(ow, "bwIllusion" .. e)
  FX.spawn(ow, "bwIllusion" .. e, at.x, at.z, at.y, nil, "bwIllusion" .. e)
end

local function running(ow, e)
  for _, f in ipairs(ow and ow.gen4FieldFx or {}) do
    if f.tag == "bwIllusion" .. e then return f end
  end
  return nil
end

-- the wait is the effect's own length on the script's frame clock (a field
-- object stage that does not tick under a scene would otherwise park the
-- script for good: N's throne room did)
local function waitFor(ctx, f)
  if not (f and ctx.runner) then return end
  local left = math.max(0, (f.frames or 0) - (f.frame or 0)) * require("src.world.Gen4FieldFx").TICKS_PER_FRAME
  if left > 0 then Commands.wait(ctx, left) end
end

function Commands.g5_illusion_wait(ctx, effect)
  waitFor(ctx, running(ctx.overworld, val(ctx, effect)))
end
Commands.meta = Commands.meta or {}
Commands.meta.g5_illusion_wait = { foreground = true, blocking = true }

function Commands.g5_illusion_end(ctx, effect)
  local ow = ctx.overworld
  local e = val(ctx, effect)
  if ow then require("src.world.Gen4FieldFx").clear(ow, "bwIllusion" .. e) end
  if ow and ow.gen5Illusion then ow.gen5Illusion[e] = nil end
end

-- N'S CASTLE (overlay 64; READ FROM CODE, Black):
--   0x23F (ov21 0x021D2F44 -> ov64 0x021F37B8) effect 0 (/a/2/1/9 model 0,
--         four animations) at the player's position (0x021A3038), waited for
--   0x256 <x, y, z> (0x021D3018 -> 0x021F3A44) effect 1 (the puff, model 6)
--         at the tile, as 0x222 places
--   0x255 <object, x, y, z, arc, frames> (0x021D2F6C -> 0x021F3970) carries
--         effect 0 from the object's position (0x0216D88C) to the tile
--         (x << 16 + 0x8000, y << 15, z << 16 + 0x8000), SE 0x566; its task
--         0x021F3AF9 steps a counter to `frames` and puts the effect at
--         from + (to - from) * k / frames, raised by (arc << 15) * h / frames
--         where h = k up to (frames + 1) / 2 and frames - k after (a tent);
--         the script waits for the task (0x0215897C), and the effect stays
--         at the tile; 0x257 / 0x258 wait for the effects (0x021F3ADC /
--         0x021F3AC0)
-- INFERRED: the task steps once per field frame (Gen4FieldFx's 2 ticks).
local function castleAt(ctx, part, x, y, z, wait)
  local ow = ctx.overworld
  if not ow then return end
  local FX = require("src.world.Gen4FieldFx")
  FX.clear(ow, part)
  FX.spawn(ow, part, x, z, y, nil, part)
  if wait then Commands.g5_castle_wait(ctx) end
end

function Commands.g5_castle_player(ctx)
  local p = ctx.overworld and ctx.overworld.player
  if not p then return end
  local g = ctx.overworld.map and ctx.overworld.map.renderer and ctx.overworld.map.renderer.gen4Ground
  local y = g and g.groundY and g:groundY((p.px or 0) + 8, (p.py or 0) + 8) or 0
  castleAt(ctx, "bwCastle0", (p.px or 0) + 8, y, (p.py or 0) + 8, true)
end

function Commands.g5_castle_puff(ctx, x, y, z)
  local ox, oy = origin(ctx.overworld)
  castleAt(ctx, "bwCastle1", (val(ctx, x) - ox) * 16 + 8, val(ctx, y) * 8, (val(ctx, z) - oy) * 16 + 8, false)
end

function Commands.g5_castle_carry(ctx, obj, x, y, z, arc, frames)
  local ow = ctx.overworld
  if not ow then return end
  local ox, oy = origin(ow)
  local tx, ty, tz = (val(ctx, x) - ox) * 16 + 8, val(ctx, y) * 8, (val(ctx, z) - oy) * 16 + 8
  local n = math.max(1, val(ctx, frames))
  local rise = val(ctx, arc) * 8
  -- from the object (its tile centre on the ground under it), else the tile
  local e = G4().objectById and G4().objectById(ctx, val(ctx, obj))
  local fx, fz, fy = tx, tz, ty
  if e then
    fx, fz = (e.px or 0) + 8, (e.py or 0) + 8
    local g = ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
    fy = g and g.groundY and g:groundY(fx, fz) or 0
  end
  pcall(function() require("src.core.Sound").playSe(ctx.game.data, 0x566) end)
  castleAt(ctx, "bwCastle0", fx, fy, fz, false)
  local fxs = ow.gen4FieldFx or {}
  local f = fxs[#fxs]
  if f and f.tag == "bwCastle0" then
    local k = 0
    f.onFrame = function(it)
      if k >= n then return end
      k = k + 1
      local h = k < math.floor((n + 1) / 2) and k or n - k
      it.x = fx + (tx - fx) * k / n
      it.z = fz + (tz - fz) * k / n
      it.y = fy + (ty - fy) * k / n + rise * h / n
    end
  end
  -- the script waits for the carry, not for the effect's own animation
  if ctx.runner then Commands.wait(ctx, n * require("src.world.Gen4FieldFx").TICKS_PER_FRAME) end
end

function Commands.g5_castle_wait(ctx)
  local ow = ctx.overworld
  local f
  for _, e in ipairs(ow and ow.gen4FieldFx or {}) do
    if e.tag == "bwCastle0" or e.tag == "bwCastle1" then f = e end
  end
  waitFor(ctx, f)
end
Commands.meta.g5_castle_player = { foreground = true, blocking = true }
Commands.meta.g5_castle_carry = { foreground = true, blocking = true }
Commands.meta.g5_castle_wait = { foreground = true, blocking = true }

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwillusionplace = L.bwillusionplace or function(ins, s) emit(s, { "g5_illusion_place", ins.args[1], ins.args[2], ins.args[3], ins.args[4] }) end
  L.bwillusionstart = L.bwillusionstart or function(ins, s) emit(s, { "g5_illusion_start", ins.args[1] }) end
  L.bwillusionwait = L.bwillusionwait or function(ins, s) emit(s, { "g5_illusion_wait", ins.args[1] }) end
  L.bwcastleplayer = L.bwcastleplayer or function(ins, s) emit(s, { "g5_castle_player" }) end
  L.bwcastlepuff = L.bwcastlepuff or function(ins, s) emit(s, { "g5_castle_puff", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwcastlecarry = L.bwcastlecarry or function(ins, s)
    emit(s, { "g5_castle_carry", ins.args[1], ins.args[2], ins.args[3], ins.args[4], ins.args[5], ins.args[6] })
  end
  L.bwcastlewait = L.bwcastlewait or function(ins, s) emit(s, { "g5_castle_wait" }) end
  L.bwillusionend = L.bwillusionend or function(ins, s) emit(s, { "g5_illusion_end", ins.args[1] }) end
end

return M
