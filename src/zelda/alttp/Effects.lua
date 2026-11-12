-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SMALL EFFECTS (round 21), the SNES routines the GBA keeps (zelda3 names),
-- with the GBA's own tables read at import (Effects.extract, found by value;
-- the GBA's OBJ chars differ from the SNES's):
--
--   SpriteModule_Die / SpriteDeath_DrawPoof (the death puff)
--       a killed sprite goes to state 6 with sprite_delay_main 31 (the
--       sword's hit timer bit 0x80) or 15 (arrows, bombs); the timer runs at
--       3 / 4 speed (it is put back on frames where frame & 3 == 0). The
--       puff is 4 OAM entries of kPerishOverlay (X / Y / Char / Flags, GBA
--       0x1721C2 / E2 / 0x172202 / 0x172222) from i = ((delay & 0x1C) ^ 0x1C)
--       + 3 down, minus 4 px for a small sprite (flags3 & 0x20); the sprite
--       itself is still drawn while delay >= 10. At 0 its prize drops
--       (Sprite_DoTheDeath) -- and only then is the screen clear for the
--       room's kill-tags (Sprite_CheckIfScreenIsClear counts state 6).
--   Ancilla1E_DashDust (the dash's dust; AddDashingDustEx)
--       one at a time (Ancilla_AllocInit limit 0). Charging: at (Link x,
--       Link y + 20), 3 chars a stage (kDashDust_Draw_X / Y / Char, GBA
--       0x17EDF8 / 0x17EDBC / 0x17EE34, + kDashDust_Draw_X1 0x17EE52 by
--       facing), a stage every 3 frames, hidden at 5, gone at 6. Running
--       (DashDust_Motive): at Link + kAddDashingDust_X / Y (0x16E158 /
--       0x16E150) by facing, one char a stage (0x16E160), gone at 3.
--   Ancilla1D_ScreenShake (AncillaAdd_DashTremor, the dash's bonk)
--       16 frames: bg1_x_offset (facing left / right) or bg1_y_offset
--       (up / down) = +-3, negated every frame, starting from 3 when Link is
--       left of 0x80 / above 0x78 on screen (else -3). Module07_Dungeon /
--       the overworld add it to the camera for the BGs and the sprites;
--       Link is drawn after the camera is put back (he stays still).
--
-- OURS: the shake outdoors is not zeroed at the overworld's scroll edges
-- (DashTremor_TwiddleOffset); the charging dust's grass / water variant
-- (draw_water_ripples_or_grass, +15) is not used; no sound.

local bit = require("bit")
local band, bxor = bit.band, bit.bxor

local E = {}

-- the GBA's tables (RomMap-style addresses, found by value against zelda3)
E.ROM = {
  perishX = 0x1721C2, perishY = 0x1721E2, perishChar = 0x172202, perishFlags = 0x172222,
  dustY = 0x17EDBC, dustX = 0x17EDF8, dustChar = 0x17EE34, dustX1 = 0x17EE52,
  addDustY = 0x16E150, addDustX = 0x16E158, motiveChar = 0x16E160,
  -- the item strip (LoadItemGFXIntoWRAM4BPPBuffer's RAM, offsets from the
  -- strip's start, SNES 0x9480): kLinkDmaSources6 (128 x u16) and the
  -- second row's offset kLinkDmaSources7 (16 x u16) -- the same values as
  -- the SNES minus 0x9480
  itemDma = 0x22A9F2, itemDma2 = 0x22AAF2,
  -- TileDetect_MainHandler's kDoSwordInteractionWithTiles_x / _y (40 x s16
  -- on the GBA; its item 2 rows differ from the SNES) and _o (8, the spin's
  -- order): the tile a tool / the sword / the spin attack acts on (OwSword)
  tileX = 0x1681D4, tileY = 0x16817C, spinO = 0x16822F,
}

function E.extract(rom, check)
  local R = E.ROM
  local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
  local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end
  local t = {
    perishX = s8(rom:bytesU8(R.perishX, 32)), perishY = s8(rom:bytesU8(R.perishY, 32)),
    perishChar = rom:bytesU8(R.perishChar, 32), perishFlags = rom:bytesU8(R.perishFlags, 32),
    dustX = s16(rom:bytesU16(R.dustX, 30)), dustY = s16(rom:bytesU16(R.dustY, 30)),
    dustChar = rom:bytesU8(R.dustChar, 30), dustX1 = s16(rom:bytesU16(R.dustX1, 4)),
    addDustX = s16(rom:bytesU16(R.addDustX, 4)), addDustY = s16(rom:bytesU16(R.addDustY, 4)),
    motiveChar = rom:bytesU8(R.motiveChar, 3),
    itemDma = rom:bytesU16(R.itemDma, 128), itemDma2 = rom:bytesU16(R.itemDma2, 16),
    tileX = s16(rom:bytesU16(R.tileX, 40)), tileY = s16(rom:bytesU16(R.tileY, 40)), spinO = rom:bytesU8(R.spinO, 8),
  }
  check(t.tileX[5] == 6 and t.tileX[7] == -1 and t.tileY[6] == 28 and t.tileX[40] == 22 and t.tileY[40] == 28
        and t.spinO[1] == 10 and t.spinO[8] == 0, "sword tile offsets")
  check(t.perishX[4] == 8 and t.perishY[3] == 8 and t.perishX[25] == -3 and t.perishFlags[7] == 0xC4
        and t.perishChar[2] ~= 0 and t.perishChar[1] == 0, "death puff tables")
  check(t.dustX[1] == 10 and t.dustY[1] == -2 and t.dustX1[3] == 4 and t.dustX1[4] == -4
        and t.addDustY[1] == 20 and t.addDustX[3] == 6 and t.dustChar[3] == 0xFF, "dash dust tables")
  check(t.itemDma[17] == 0x380 and t.itemDma2[3] == 0x60, "item strip DMA tables")
  return t
end

local function tabs(game)
  local cb = game.data and game.data.roomIdx and game.data.roomIdx.combat
  return cb and cb.fx
end
function E.ready(game) return tabs(game) ~= nil end

-- ------------------------------------------------------------ death puff
-- a sprite killed by a hit (Actors:takeDamage): sword = the sword's hit
-- timer (bit 0x80) was running
function E.death(game, a, sword)
  if not tabs(game) then return nil end
  game.puffs = game.puffs or {}
  local p = { a = a, x = a.x, y = a.y, z = a.z or 0, lower = a.lower, delay = sword and 31 or 15,
              room = game.interior and game.interior.room }
  game.puffs[#game.puffs + 1] = p
  return p
end

-- the puff a sprite is in (or nil)
function E.puffOf(game, a)
  for _, p in ipairs(game.puffs or {}) do if p.a == a then return p end end
end

-- any sprite still dying (Sprite_CheckIfScreenIsClear counts state 6)
function E.dying(game)
  return game.puffs ~= nil and #game.puffs > 0
end

-- ------------------------------------------------------------ dash dust
-- AddDashingDustEx: motive = running (DashDust_Motive), else charging
function E.dashDust(game, motive)
  local T = tabs(game)
  if not T or game.dust then return end
  local lk = game.link
  local j = math.floor((lk.facing or 2) / 2)
  local x, y
  if motive then x, y = lk.x + T.addDustX[j + 1], lk.y + T.addDustY[j + 1]
  else x, y = lk.x, lk.y + 20 end
  game.dust = { motive = motive, x = x, y = y, stage = 0, timer = 3, lower = game.interior and game.interior.lower }
end

-- ------------------------------------------------------------ the shake
-- AncillaAdd_DashTremor: Link's position on screen picks the first sign
function E.tremor(game, sx, sy)
  if game.shake then return end
  local j = math.floor((game.link.facing or 2) / 2)
  local axis = (j <= 1) and "y" or "x"            -- kAddDashTremor_Dir: 2, 2, 0, 0
  local s = (axis == "y") and sy or sx
  local lim = (axis == "y") and 0x78 or 0x80
  game.shake = { n = 16, axis = axis, v = (s and s < lim) and 3 or -3, off = 0 }
end

-- the camera offset this frame (BGs and sprites; Link is drawn without it)
function E.shakeOffset(game)
  local s = game.shake
  if not s or s.off == 0 then return 0, 0 end
  if s.axis == "x" then return s.off, 0 end
  return 0, s.off
end

-- ------------------------------------------------------------ per frame
function E.update(game)
  local fr = game.frame or 0
  -- the puffs (SpriteDeath_MainEx)
  local list = game.puffs
  if list then
    local room = game.interior and game.interior.room
    local i = 1
    while i <= #list do
      local p = list[i]
      if p.room ~= room then
        -- (the room changed: the sprite is gone with it)
        table.remove(list, i)
      else
        p.delay = p.delay - 1
        if band(fr, 3) == 0 then p.delay = p.delay + 1 end
        if p.delay <= 0 then
          table.remove(list, i)
          if p.prize then p.prize() end
        else
          i = i + 1
        end
      end
    end
  end
  -- the dust (Ancilla1E_DashDust / DashDust_Motive)
  local d = game.dust
  if d then
    if d.timer > 0 then d.timer = d.timer - 1 end
    if d.timer == 0 then
      d.timer = 3
      d.stage = d.stage + 1
      if (d.motive and d.stage >= 3) or (not d.motive and d.stage >= 6) then game.dust = nil end
    end
  end
  -- the shake (Ancilla1D_ScreenShake)
  local s = game.shake
  if s then
    s.n = s.n - 1
    if s.n < 0 then game.shake = nil
    else s.v = -s.v; s.off = s.v end
  end
end

-- ------------------------------------------------------------ drawing
-- the puffs of the room (at the sprites' priority), cx / cy = the camera
function E.drawPuffs(game, spr, cx, cy, inPass)
  local T = tabs(game)
  if not T or not game.puffs or not spr then return end
  for _, p in ipairs(game.puffs) do
    if inPass == nil or inPass(p) then
      local a = p.a
      -- the sprite itself while delay >= 10 (SpriteActive_Main draws it)
      if p.delay >= 10 and spr.drawActor then
        local ok = pcall(spr.drawActor, spr, a, a.x - cx, a.y - cy, game.frame, game.interior and game.interior.room)
        if not ok then p.noBody = true end
      end
      local f3 = spr.info and spr.info.flags3 and spr.info.flags3[a.type + 1] or 0
      local r12 = band(f3, 0x20) ~= 0 and 4 or 0
      local ox, oy = a.x - cx - r12, a.y - (p.z or 0) - cy - r12
      local i = bxor(band(p.delay, 0x1C), 0x1C) + 3
      for n = 3, 0, -1 do
        local k = i + 1
        local ch = T.perishChar[k] or 0
        if ch ~= 0 then
          spr:oam(ox + (T.perishX[k] or 0), oy + (T.perishY[k] or 0), ch, T.perishFlags[k] or 4, 0)
        end
        i = i - 1
        if n == 0 then break end
      end
    end
  end
end

-- the dash dust (with Link's OBJ priority)
function E.drawDust(game, spr, cx, cy)
  local T, d = tabs(game), game.dust
  if not T or not d or not spr then return end
  if d.motive then
    local ch = T.motiveChar[d.stage + 1]
    if ch then spr:oam(d.x - cx, d.y - cy, ch, 4, 0) end
    return
  end
  if d.stage >= 5 then return end
  local j = math.floor((game.link.facing or 2) / 2)
  local r12 = T.dustX1[j + 1] or 0
  local t = 3 * d.stage
  for _ = 0, 2 do
    local ch = T.dustChar[t + 1]
    if ch and ch ~= 0xFF then
      spr:oam(d.x - cx + r12 + T.dustX[t + 1], d.y - cy + T.dustY[t + 1], ch, 4, 0)
    end
    t = t + 1
  end
end

return E
