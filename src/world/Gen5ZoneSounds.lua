-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- 0x1A4 <room>: THE ELITE FOUR ROOMS' AMBIENT SOUND.
--
-- READ FROM CODE (Black, ov21 0x021B568C): <room> 1..4 starts a zone effect
-- from overlay 56 (0x021BB990, effect records at 0x021F4344 + 0x18 * k):
--   1 -> record 0 (init 0x021F3DCC): SE 0x746 started as the room's
--        ambient sound (0x02028A7C), stopped on exit (0x02028B50); its
--        update plays 0x692 whenever the room building's animation comes
--        round to a frame from 0x021F4258 (0x0218C6F4)
--   2 -> record 2 (0x021F3F30): SE 0x756
--   3 -> record 3 (0x021F3FB8): SE 0x7EF
--   4 -> record 1 (0x021F3E94): no sound of its own -- 0x743 / 0x76E only
--        on its building animation's frames
-- PORTED: the ambient sound, looped while the player stays in the zone.
-- NOT PORTED: the sounds keyed to building-animation frames (0x692, 0x743,
-- 0x76E). INFERRED: an ambient SE loops (it is started once and only ever
-- stopped).

local M = {}

M.AMBIENT = { [1] = 0x746, [2] = 0x756, [3] = 0x7EF }

local function name(data, id)
  local Sound = require("src.core.Sound")
  return Sound.seName and Sound.seName(data, id) or id
end

function M.stop(ow)
  local st = ow and ow.gen5ZoneSound
  if not st then return end
  pcall(require("src.core.Sound").stopLoop, st.name)
  ow.gen5ZoneSound = nil
end

function M.start(ow, data, room)
  M.stop(ow)
  local id = M.AMBIENT[room]
  if not (ow and id) then return end
  local n = name(data, id)
  if n == nil then return end
  pcall(require("src.core.Sound").startLoop, data, n)
  ow.gen5ZoneSound = { name = n, map = ow.map and ow.map.id, room = room }
end

-- per frame: leaving the zone ends the effect
function M.update(ow)
  local st = ow and ow.gen5ZoneSound
  if st and ow.map and ow.map.id ~= st.map then M.stop(ow) end
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
function Commands.g5_zone_sound(ctx, room)
  local C = require("src.script.Gen4Commands")
  local n = math.floor(tonumber(C.valueOf(ctx, room)) or 0)
  if ctx.overworld then M.start(ctx.overworld, ctx.game and ctx.game.data, n) end
end

function M.install(L)
  L.bwzonesound = L.bwzonesound or function(ins, s) s.out[#s.out + 1] = { "g5_zone_sound", ins.args[1] } end
end

return M
