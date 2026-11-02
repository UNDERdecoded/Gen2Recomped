-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER: THE OLIVINE LIGHTHOUSE'S LAMP COMING BACK ON --
-- ScrCmd_459 (scrcmd_c.c -> ov02_02245B80, asm/overlay_02_02245B80.s), run by
-- the lighthouse top (scr_seq_D27R0107) after Jasmine's Ampharos is healed.
--
-- READ FROM CODE (ov02_02245BC8's five states, field frames):
--   0  load /a/1/7/4 model 0 and animations 1, 2 (ov02_02245D18) at world
--      (136, 0, 160) -- fx32 0x88000 / 0xA0000 -- and show it
--   1  every frame both animations advance one frame and loop, the model
--      draws (ov02_02245DE0); a counter from 0 plays SEQ_SE_DP_FW411 at 0, 30,
--      50, 60, 70, 80 -- from 60 on pitched (counter / 10 - 5) * 64 -- and
--      SEQ_SE_DP_F207 at 50; after 0x5A frames the screens fade to white
--      (BeginNormalPaletteFade 24 steps x 2)
--   2  keep drawing until the fade is done
--   3  60 frames, then the model goes (ov02_02245DB0), the area light is
--      rebuilt from id 4 (data/dun20_02light.txt, the lit lighthouse) and the
--      screens fade back in from white (18 steps x 1)
--   4  until that fade is done
-- The lowering splits it so the white fades are the script engine's own
-- (g4_fade / g4_wait_fade): flash (states 0-1), fade out, lit (state 3's wait
-- and light switch), fade in.
--
-- The model is drawn through HgssHideoutFx's object slot (its live / free
-- passes in Gen4Ground), held there in state "held".
--
-- INFERRED: SE pitch 64 units = one semitone (the DS player's pitch scale).

local M = {}

M.X, M.Z = 136, 160
M.FRAMES = 0x5A + 1
M.LIT_WAIT = 60
M.LIT_LIGHT = 4
M.SE_FLASH, M.SE_ON = "SEQ_SE_DP_FW411", "SEQ_SE_DP_F207"
M.FLASH_AT = { [0] = true, [30] = true, [50] = true, [60] = true, [70] = true, [80] = true }

local function playSe(data, name, semitones)
  pcall(function()
    local Sound = require("src.core.Sound")
    local opts = semitones and semitones ~= 0 and { pitch = 2 ^ (semitones / 12) } or nil
    Sound.playSe(data, name, opts)
  end)
end

local function fx() return require("src.world.HgssHideoutFx") end

function M.available(data)
  local art = data and data.gen4_legend_art
  return type(art) == "table" and type(art.parts) == "table" and art.parts.lighthouse ~= nil
end

-- states 0-1; step() once per field frame, true when the flash is over
function M.startFlash(game, ow)
  local data = game.data
  M.run = { c = 0, n = 0 }
  if M.available(data) then
    local ground = ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
    local y = ground and ground.groundY and ground:groundY(M.X, M.Z) or 0
    fx().trap = { part = "lighthouse", frame = 0, state = "held", x = M.X, y = y, z = M.Z, tick = 0,
                  mapId = ow and ow.map and ow.map.id }
  end
end

function M.stepFlash(game)
  local r = M.run
  if not r then return true end
  local c = r.c
  if M.FLASH_AT[c] then
    playSe(game.data, M.SE_FLASH, c >= 60 and (math.floor(c / 10) - 5) or nil)
    if c == 50 then playSe(game.data, M.SE_ON) end
  end
  r.c = c + 1
  local t = fx().trap
  if t and t.part == "lighthouse" then
    local part = game.data.gen4_legend_art.parts.lighthouse
    local frames = math.max(1, math.floor(tonumber(part and part.frames) or 1))
    t.frame = (t.frame + 1) % frames
  end
  r.n = r.n + 1
  return r.n >= M.FRAMES
end

-- state 3: after the wait the model goes and the light becomes id 4
function M.lit(game, ow)
  local t = fx().trap
  if t and t.part == "lighthouse" then fx().trap = nil end
  M.run = nil
  local ground = ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  local light = game.data.gen4_arealight
  if ground and light and light.members and light.members[M.LIT_LIGHT] then
    ground.lightMember = M.LIT_LIGHT
    pcall(ground.applyLight, ground)
    -- the tint is baked into the meshes (Gen4Ground:applyLight)
    if ground.dropLitModels then pcall(ground.dropLitModels, ground) end
  end
  M.litMap = ow and ow.map and ow.map.id
end

return M
