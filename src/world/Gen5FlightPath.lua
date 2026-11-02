-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- AN OBJECT FLOWN ALONG A BAKED PATH ROUND THE PLAYER (scripts 0x15B..0x15E,
-- overlay 21): Tornadus / Thundurus sweeping past at Z337, the trio at Z376.
--
-- READ FROM CODE (Black):
--   0x15B <object> (ov21 0x021D1A04 -> 0x021D182C) takes hold of the object
--         and keeps the player's position (0x021A3038) as the path's origin,
--         in a field process (0x021BB990, table 0x021DD5F0) the script
--         context keeps (0x02159104)
--   0x15D <path> (0x021D1A74 -> 0x021D1894) loads path `path` of /a/2/0/3
--         (src/import/Gen5FlightPaths.lua), puts the object at frame 0, and
--         sets it running; each frame (0x021D18F4) steps one frame
--         (0x02011590, 0x1000) and puts the object at origin + translation
--         (0x021D1988), turning it to face down / right / up / left when the
--         rotation's y is exactly 0 / 90 / 180 / 270 degrees; after the last
--         frame the object is set on the grid where it is (0x0216E014)
--   0x15E (0x021D1AB0) waits until it has stopped (task 0x021D1A9D reads the
--         running byte +0x19A); 0x15C (0x021D1A54 -> 0x021D1884) lets go
-- INFERRED: one path frame a field frame (Gen4FieldFx's 2 ticks); the
-- translation's y is shown as a sprite lift over the ground under the object.

local M = {}

M.FACING = { [0] = "down", [90] = "right", [180] = "up", [270] = "left" }

local function G4() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end
local function ticksPerFrame() return require("src.world.Gen4FieldFx").TICKS_PER_FRAME end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local function pathData(ctx, n)
  local G = ctx.game or package.loaded["src.core.Game"]
  local c = G and G.data and G.data.constants
  local all = c and c.gen5FlightPaths and c.gen5FlightPaths.paths
  local p = all and all[n + 1]
  return type(p) == "table" and p or nil
end

local function place(fl, f)
  local p, e = fl.path, fl.e
  local i = f * 3
  local tx, ty, tz = p.t[i + 1], p.t[i + 2], p.t[i + 3]
  if not tx then return end
  e.px, e.py = fl.bx + tx, fl.bz + tz
  e.spriteOffset = { lift = ty, gen5Flight = true }
  local face = M.FACING[p.ry[f + 1] or -1]
  if face then e.facing = face end
end

local function land(fl)
  local e = fl.e
  e.cellX = math.floor(((e.px or 0) + 8) / 16)
  e.cellY = math.floor(((e.py or 0) + 8) / 16)
  e.px, e.py = e.cellX * 16, e.cellY * 16
  if e.spriteOffset and e.spriteOffset.gen5Flight then e.spriteOffset = nil end
end

function Commands.g5_flight_attach(ctx, obj)
  local ow = ctx.overworld
  local p = ow and ow.player
  if not p then return end
  local e = G4().objectById and G4().objectById(ctx, val(ctx, obj))
  if not e then return end
  ow.gen5Flight = { e = e, bx = p.px or 0, bz = p.py or 0 }
end

function Commands.g5_flight_play(ctx, path)
  local ow = ctx.overworld
  local fl = ow and ow.gen5Flight
  if not fl then return end
  local p = pathData(ctx, val(ctx, path))
  if not p then fl.running = false return end
  fl.path, fl.frame, fl.tick, fl.running = p, 0, 0, true
  place(fl, 0)
end

-- every engine tick (OverworldState:update / animate)
function M.tick(ow)
  local fl = ow and ow.gen5Flight
  if not (fl and fl.running and fl.path) then return end
  fl.tick = fl.tick + 1
  if fl.tick % ticksPerFrame() ~= 0 then return end
  fl.frame = fl.frame + 1
  if fl.frame >= fl.path.frames then
    fl.running = false
    land(fl)
    return
  end
  place(fl, fl.frame)
end

function Commands.g5_flight_wait(ctx)
  local fl = ctx.overworld and ctx.overworld.gen5Flight
  if not (fl and fl.running and fl.path and ctx.runner) then return end
  local left = (fl.path.frames - fl.frame) * ticksPerFrame() - (fl.tick % ticksPerFrame())
  if left > 0 then Commands.wait(ctx, left) end
end
Commands.meta = Commands.meta or {}
Commands.meta.g5_flight_wait = { foreground = true, blocking = true }

function Commands.g5_flight_detach(ctx)
  local ow = ctx.overworld
  local fl = ow and ow.gen5Flight
  if fl and fl.running then fl.running = false land(fl) end
  if ow then ow.gen5Flight = nil end
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwflightattach = L.bwflightattach or function(ins, s) emit(s, { "g5_flight_attach", ins.args[1] }) end
  L.bwflightplay = L.bwflightplay or function(ins, s) emit(s, { "g5_flight_play", ins.args[1] }) end
  L.bwflightwait = L.bwflightwait or function(ins, s) emit(s, { "g5_flight_wait" }) end
  L.bwflightdetach = L.bwflightdetach or function(ins, s) emit(s, { "g5_flight_detach" }) end
end

return M
