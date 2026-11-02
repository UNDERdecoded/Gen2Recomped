-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- 0x146 <preset, frames>: THE CUTSCENE CAMERA TO A PRESET (READ FROM CODE,
-- ov21 0x021B542C: /a/1/6/3[preset] handed to the camera's move over
-- <frames>; the presets are src/import/Gen5CameraPresets.lua). It sits where
-- 0x143 does, between 0x13F / 0x141 and 0x145, and is undone the same way
-- (0x144 / 0x147 / 0x140). Every site is a Route 10 badge gate's `146 6 30`:
-- the camera swings to the gate's bars at (15.5, 5.5) while they open.
-- As with 0x143 the point looked at is carried and the angles and the frames
-- are not -- the player's own camera mode decides those here. A preset with
-- no point (0..5, angles only) leaves the camera where it is.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

function M.preset(data, n)
  local p = data and data.constants and data.constants.gen5CameraPresets
  return p and (p[n] or p[tostring(n)]) or nil
end

function Commands.g5_camera_preset(ctx, preset, _frames)
  local C = require("src.script.Gen4Commands")
  local n = math.floor(tonumber(C.valueOf(ctx, preset)) or -1)
  local p = M.preset(ctx.game and ctx.game.data, n)
  if not p then
    require("src.core.Logger").warn("gen5 camera preset %d: not in this cache (re-import the ROM)", n)
    return
  end
  if p.usePoint and Commands.g4_add_free_camera then
    Commands.g4_add_free_camera(ctx, math.floor(p.x / 16), math.floor(p.z / 16))
  end
end

function M.install(L)
  L.bwcamerapreset = L.bwcamerapreset or function(ins, s) s.out[#s.out + 1] = { "g5_camera_preset", ins.args[1], ins.args[2] } end
  -- a cache linked before the name keeps bw_146 without its operands; every
  -- site in Black is `146 0006 001E`
  L.bw_146 = L.bw_146 or function(_, s) s.out[#s.out + 1] = { "g5_camera_preset", 6, 30 } end
end

return M
