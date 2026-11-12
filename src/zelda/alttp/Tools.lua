-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- LINK'S TOOLS (round 26, team A): the Fire Rod, the Ice Rod, the hammer
-- and the pegs, the shovel, the boomerangs and the hookshot. The SNES
-- routines the GBA keeps (zelda3 names); the GBA's own tables where they
-- were found by value and checked by the code that reads them (OFF), else
-- the disassembly's constants (named below):
--
--   LinkItem_Rod          kRodAnimDelays {3, 3, 5}; magic cost index 0
--                         (LinkCheckMagicCost, kLinkItem_MagicCosts);
--                         link_item_in_hand 1 (pose kPlayerOam_Tab2 -> 6).
--   AncillaAdd_FireRodShot / Ancilla02_FireRodShot  from Link + kFireRod_X/Y
--                         {0, 0, -8, 16} / {-8, 16, 3, 3}, speed 64 (1/16 px);
--                         a sprite (Ancilla_CheckSpriteCollision, kAncilla_
--                         HitBox[dir]) takes kAncilla_Damage[2]; the tile
--                         probes dir | 8 and dir | 12 (kAncilla_CheckTile
--                         Coll0); a torch (attribute 0xC0 + n) is lit
--                         (Dungeon_LightTorch); a hit bursts 31 frames
--                         (FireShot_Draw chars GBA 0x17EFE8 / 0x17EFEB,
--                         offsets kFireShot_Draw_X2 / Y2 at 0x17EFC8 / D8).
--   AncillaAdd_IceRodShot / Ancilla0B_IceRodShot  kIceRod_X/Y {0, 0, -20,
--                         20} / {-16, 24, 8, 8}, speed 48; it waits until
--                         ancilla_item_to_link (from 255, every 4 frames)
--                         passes 1; kAncilla_Damage[0x0B]; a hit spreads
--                         (Ancilla11_IceRodWallHit, kIceShotSpread_CharFlags
--                         / XY at GBA 0x17EF70 / 0x17EF80, 2 x 8 frames).
--   LinkItem_Hammer       kHammerAnimDelays (GBA 0x169098); on the first
--                         step TileDetect_MainHandler(3) ->
--                         Overworld_ToolAndTileInteraction: a peg (map16
--                         0x21B) is driven in (0xDCB); link_item_in_hand 2.
--   LinkItem_Shovel       kShovelAnimDelay {7, 18, 16} / kShovelAnimDelay2
--                         {0, 1, 2}; on step 1 TileDetect_MainHandler(2):
--                         the diggable map16 tiles (0x34, 0x71, 0x35,
--                         0x10D, 0x10F, 0xE1, 0xE2, 0xDA, 0xF8, 0x10E) turn to
--                         0xDC9 and give what the secrets list hides; area
--                         0x2A at map16 spot 0x492 is the flute
--                         (AncillaAdd_DugUpFlute); link_position_mode 1.
--   LinkItem_Boomerang / AncillaAdd_Boomerang / Ancilla05_Boomerang
--                         kBoomerang_Tab0 (speeds 0x20 / 0x18 diagonal, red
--                         0x30 / 0x28), Tab1 (range 0x20 / 0x60 frames)
--                         (GBA 0x16E0B4..); the speed falls by 1 a frame in
--                         the last 4; a sprite, a wall or the screen's edge
--                         turns it; back at Link's speed H
--                         (Ancilla_ProjectSpeedTowardsPlayer); caught at
--                         Link + (8, 8) inside 16 x 24; damage class
--                         kAncilla_Damage[5]; Boomerang_Draw (char GBA
--                         0x46, kBoomerang_Flags 0x1803AC, XY 0x1803B4).
--   LinkItem_Hookshot / AncillaAdd_Hookshot / Ancilla1F_Hookshot /
--   LinkState_Hookshotting  GBA 0x080ADBF0: kHookshot_Yvel / Xvel / Yd /
--                         Xd at 0x16E5BC..; out 32 frames at 64, back the
--                         same; a sprite or a wall turns it; a hookable
--                         tile (attribute 0x27, tiledetect_misc_tiles)
--                         pulls Link at 64 (kHookshotArrA-D, GBA 0x167FD4..)
--                         until within 2 px of the hook + offset; over
--                         water he lands swimming (Swim.lua).
--
-- OURS: the stun / freeze damage codes (251-254) hold a sprite 64 frames
-- in place (sprite_state 11 is not ported: frozen sprites are not ice
-- blocks); the ice shot's sparkles are drawn as its spread's first frame;
-- the hookshot's head and chain use the item strip's frame of Link's pose;
-- no hit stars / dirt / wall-clink ancillae; no sounds; the peg puzzle
-- (HandlePegPuzzles) is not ported.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local TL = {}

TL.OFF = {
  hammerDelays = 0x169098,
  fireDrawX2 = 0x17EFC8, fireDrawY2 = 0x17EFD8, fireChar2 = 0x17EFE8, fireChar = 0x17EFEB,
  iceSpreadCF = 0x17EF70, iceSpreadXY = 0x17EF80,
  boomTab0 = 0x16E0B4, boomTab1 = 0x16E0B8, boomTab2 = 0x16E0BA, boomTab4 = 0x16E0C0, boomTab5 = 0x16E0C8,
  boomFlags = 0x1803AC, boomXY = 0x1803B4, boomDrawTab0 = 0x1803C8,
  hookYv = 0x16E5BC, hookXv = 0x16E5C0, hookYd = 0x16E5C4, hookXd = 0x16E5CC,
  hookArrA = 0x167FD4, hookArrB = 0x167FD8, hookArrC = 0x167FDC, hookArrD = 0x167FE0,
  hookChar = 0x17F914, hookFlags = 0x17F920,
}
-- the disassembly's constants (no GBA table found by value)
TL.ROD_DELAYS = { 3, 3, 5 }
TL.FIRE_X, TL.FIRE_Y, TL.FIRE_V = { 0, 0, -8, 16 }, { -8, 16, 3, 3 }, 64
TL.ICE_X, TL.ICE_Y, TL.ICE_V = { 0, 0, -20, 20 }, { -16, 24, 8, 8 }, 48
TL.SHOVEL_DELAY, TL.SHOVEL_STEP = { 7, 18, 16 }, { 0, 1, 2 }
TL.DIGGABLE = { [0x34] = 0xDC9, [0x71] = 0xDC9, [0x35] = 0xDC9, [0x10D] = 0xDC9, [0x10F] = 0xDC9, [0xE1] = 0xDC9,
                [0xE2] = 0xDC9, [0xDA] = 0xDC9, [0xF8] = 0xDC9, [0x10E] = 0xDC9 }
TL.PEG = { [0x21B] = 0xDCB }
TL.MAP16 = { 0x21B, 0xDCB, 0x34, 0x71, 0x35, 0x10D, 0x10F, 0xE1, 0xE2, 0xDA, 0xF8, 0x10E, 0xDC9 }
TL.BOOM_TAB3 = { 8, 4, 2, 1 }
TL.BOOM_TAB6 = { -10, -8, -9, -9, -10, -8, -9, -9 }
TL.BOOM_TAB7 = { -10, 11, 8, -8, -10, 11, 8, -8 }
TL.BOOM_X0 = { 0, 0, -8, 8, 8, 8, -8, -8 }
TL.BOOM_Y0 = { -16, 6, 0, 0, -8, 8, -8, 8 }
TL.HOOK_COLL_X, TL.HOOK_COLL_Y = { 0, 15, 0, 15, 0, 0, 8, 8 }, { 0, 0, 7, 7, 0, 15, 0, 15 }
TL.HOOK_MOVE_X, TL.HOOK_MOVE_Y = { 0, 0, 8, -8 }, { 8, -9, 0, 0 }
TL.HOOKABLE = 0x27
-- ancilla damage class indices (kAncilla_Damage[type])
TL.ANC_FIRE, TL.ANC_ICE, TL.ANC_BOOM = 2, 0x0B, 5
-- the item strip's blocks (LoadItemGFXIntoWRAM4BPPBuffer: kIntro_LoadGfx_Tab,
-- sheets 0 / 95 / 96; Weapon.lua holds the bow's)
TL.STRIP = {
  { off = 0x000, n = 7, sheet = 0, tile = 0 },    -- rod
  { off = 0x1C0, n = 7, sheet = 0, tile = 11 },   -- hammer
  { off = 0x440, n = 4, sheet = 95, tile = 38 },  -- shovel
  { off = 0x640, n = 4, sheet = 0, tile = 34 },   -- hookshot
  { off = 0x740, n = 14, sheet = 96, tile = 3 },  -- bug net
  { off = 0xAC0, n = 7, sheet = 96, tile = 33 },  -- cane
  { off = 0xC80, n = 2, sheet = 95, tile = 46 },  -- book
}

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end

function TL.extract(rom, R, check)
  local O = TL.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local t = {
    hammerDelays = u8(O.hammerDelays, 3),
    fireDrawX2 = u8(O.fireDrawX2, 16), fireDrawY2 = u8(O.fireDrawY2, 16), fireChar2 = u8(O.fireChar2, 3), fireChar = u8(O.fireChar, 4),
    iceSpreadCF = u8(O.iceSpreadCF, 16), iceSpreadXY = s8(u8(O.iceSpreadXY, 16)),
    boomTab0 = u8(O.boomTab0, 4), boomTab1 = u8(O.boomTab1, 2), boomTab2 = u8(O.boomTab2, 2),
    boomTab4 = u8(O.boomTab4, 8), boomTab5 = u8(O.boomTab5, 8),
    boomFlags = u8(O.boomFlags, 8), boomXY = s16(rom:bytesU16(O.boomXY, 8)), boomDrawTab0 = u8(O.boomDrawTab0, 2),
    hookYv = s8(u8(O.hookYv, 4)), hookXv = s8(u8(O.hookXv, 4)),
    hookYd = s16(rom:bytesU16(O.hookYd, 4)), hookXd = s16(rom:bytesU16(O.hookXd, 4)),
    hookArrA = s8(u8(O.hookArrA, 4)), hookArrB = s8(u8(O.hookArrB, 4)), hookArrC = s8(u8(O.hookArrC, 4)), hookArrD = s8(u8(O.hookArrD, 4)),
    hookChar = u8(O.hookChar, 12), hookFlags = u8(O.hookFlags, 12),
    map16 = {},
  }
  for _, m in ipairs(TL.MAP16) do t.map16[m] = rom:bytesU16(R.map16 + m * 8, 4) end
  check(t.hammerDelays[1] == 3 and t.hammerDelays[3] == 16, "kHammerAnimDelays")
  check(t.fireChar2[1] == 0x1D and t.fireChar[1] == 0x52 and t.fireDrawX2[1] == 7, "FireShot_Draw tables (GBA chars)")
  check(t.iceSpreadCF[1] == 0x9F and t.iceSpreadXY[9] == -8, "kIceShotSpread tables")
  check(t.boomTab0[1] == 0x20 and t.boomTab1[2] == 0x60 and t.boomTab5[1] == 2 and t.boomFlags[1] == 0xA4, "boomerang tables")
  check(t.hookYv[1] == -64 and t.hookXv[4] == 64 and t.hookYd[2] == 20 and t.hookXd[4] == 11 and t.hookArrA[2] == -16
        and t.hookChar[1] == 9, "hookshot tables")
  return t
end

local function T(game) return game.data.t and game.data.t.tools end
local function IT(game) return require("src.zelda.alttp.Items").tabs(game) end
local function actorsHere(game) if game.interior then return game.actors end return game.owActors end
local function dirIndex(f) return math.floor((f or 0) / 2) end
local function inv(game) return require("src.zelda.alttp.Menu").inventory(game) end

-- the map16 tiles this module changes, merged into the import's table once
local function mergeMap16(game)
  local tb, idx = T(game), game.data.roomIdx
  if not (tb and idx and idx.map16) or game.toolsMap16 then return end
  game.toolsMap16 = true
  for k, v in pairs(tb.map16) do if not idx.map16[k] then idx.map16[k] = v end end
end

-- LinkCheckMagicCost(i) (kLinkItem_MagicCosts[i * 3]; Items.lua's rule)
function TL.magic(game, i)
  local cost = IT(game).magicCosts[i * 3 + 1] or 0
  local m = game.stats.magic or 0
  if m == 0 or m - cost < 0 then
    game:showMessage(require("src.zelda.alttp.Items").MSG_NO_MAGIC)
    return false
  end
  game.stats.magic = m - cost
  return true
end

-- Ancilla_MoveX/Y: 1/16 px
local function move(a)
  a.sx, a.sy = (a.sx or 0) + a.vx, (a.sy or 0) + a.vy
  local mx = (a.sx >= 0) and math.floor(a.sx / 16) or -math.floor(-a.sx / 16)
  local my = (a.sy >= 0) and math.floor(a.sy / 16) or -math.floor(-a.sy / 16)
  a.sx, a.sy = a.sx - mx * 16, a.sy - my * 16
  a.x, a.y = a.x + mx, a.y + my
end

-- the tile class an ancilla probe meets (kAncilla_TileColl0_Attrs)
local function tileHit(game, a, j)
  local T0 = IT(game)
  local px, py = a.x + T0.collX[j + 1], a.y + T0.collY[j + 1]
  local at = game:ancAttr(px, py)
  local c = T0.tileAttrs[at + 1] or 0
  if a.kind == "fire" and band(at, 0xF0) == 0xC0 then c = 0 end
  return c == 1 or c == 2, at
end

-- Ancilla_CheckSpriteCollision + Ancilla_CheckDamageToSprite: the sprite hit
function TL.spriteHit(game, a, cls, box)
  local acts = actorsHere(game)
  if not acts then return nil end
  local T0 = IT(game)
  local j = a.dir
  local hx, hy, hw, hh = a.x + T0.hbX[j + 1], a.y + T0.hbY[j + 1], T0.hbW[j + 1], T0.hbH[j + 1]
  if box then hx, hy, hw, hh = box[1], box[2], box[3], box[4] end
  local Actors = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx.combat
  for _, s in ipairs(acts.list) do
    if not s.dead and not s.npc and (s.lower or false) == (a.lower or false)
       and (Actors.fights(s.type) or (TL.bossTypes and TL.bossTypes[s.type])) then
      local bx, by, bw, bh = Actors.hitbox(cb, s)
      if Actors.overlapCart(hx, hy, hw, hh, bx, by - (s.z or 0), bw, bh) then
        -- r26a: the later palaces' bosses take some items their own way
        -- (BossHooks.lua: the rods on Kholdstare / Trinexx, the hookshot on
        -- the Arrghus puffs)
        local bh = TL.bossHook and TL.bossHook(game, acts, s, cls, a)
        if bh == true then
          game.toolHits = (game.toolHits or 0) + 1
          return s
        end
        if bh == "pass" then
          -- the boss part ignores it (Sprite_ApplyCalculatedDamage refused): the next sprite
        elseif cls then
          local Items = require("src.zelda.alttp.Items")
          local dmg = Items.damage(game, cls, s.type)
          if dmg >= 251 and dmg <= 255 then
            -- the stun / freeze codes (OURS: held 64 frames)
            s.recoil, s.rvx, s.rvy, s.subx, s.suby = 64, 0, 0, 0, 0
            s.stunned = 64
            game.toolStuns = (game.toolStuns or 0) + 1
          else
            acts:swordHit(hx, hy, hw, hh, { cls = cls, arrow = true, lower = a.lower, only = s,
                                            dmg = function(t) return Items.damage(game, cls, t) end })
          end
        end
        if bh ~= "pass" then
          game.toolHits = (game.toolHits or 0) + 1
          return s
        end
      end
    end
  end
  return nil
end

local function offscreen(game, a)
  local cx, cy = game:ancCamera()
  local sx, sy = a.x - cx, a.y - cy
  return sx < -16 or sx > (game.viewW or 240) + 16 or sy < -16 or sy > (game.viewH or 160) + 16
end

-- ------------------------------------------------------------ the rods
local function addFire(game)
  local lk = game.link
  local j = dirIndex(lk.facing)
  local a = { kind = "fire", dir = j, x = lk.x + TL.FIRE_X[j + 1], y = lk.y + TL.FIRE_Y[j + 1],
              vx = (j == 2 and -TL.FIRE_V) or (j == 3 and TL.FIRE_V) or 0,
              vy = (j == 0 and -TL.FIRE_V) or (j == 1 and TL.FIRE_V) or 0,
              step = 0, ctr = 0, lower = game.interior and (game.interior.lower or false) or false }
  game.anc = game.anc or {}
  game.anc[#game.anc + 1] = a
  game.fireShots = (game.fireShots or 0) + 1
  return a
end

local function fireFrame(game, a)
  if a.step == 0 then
    move(a)
    local hit = TL.spriteHit(game, a, IT(game).ancDamage[TL.ANC_FIRE + 1]) ~= nil
    local at1, at2
    if not hit then
      local h1; h1, at1 = tileHit(game, a, a.dir + 8)
      hit = h1
      if not hit then local h2; h2, at2 = tileHit(game, a, a.dir + 12); hit = h2 end
    end
    for _, at in ipairs({ at1 or -1, at2 or -1 }) do
      if game.interior and band(at, 0xF0) == 0xC0 then
        if game:lightTorch(band(at, 0x0F)) then game.fireTorches = (game.fireTorches or 0) + 1 end
      end
    end
    a.ctr = a.ctr + 1
    if hit then a.step, a.t = 1, 31 end
    if offscreen(game, a) then a.gone = true end
  else
    a.t = a.t - 1
    if a.t <= 0 then a.gone = true end
  end
end

local function addIce(game)
  local lk = game.link
  local j = dirIndex(lk.facing)
  local a = { kind = "ice", dir = j, x = lk.x + TL.ICE_X[j + 1], y = lk.y + TL.ICE_Y[j + 1],
              vx = (j == 2 and -TL.ICE_V) or (j == 3 and TL.ICE_V) or 0,
              vy = (j == 0 and -TL.ICE_V) or (j == 1 and TL.ICE_V) or 0,
              step = 0, itl = 255, aux = 3, lower = game.interior and (game.interior.lower or false) or false }
  game.anc = game.anc or {}
  game.anc[#game.anc + 1] = a
  game.iceShots = (game.iceShots or 0) + 1
  return a
end

local function iceFrame(game, a)
  if a.kind == "icehit" then
    a.aux = a.aux - 1
    if a.aux < 0 then
      a.aux = 7
      a.itl = a.itl + 1
      if a.itl == 2 then a.gone = true end
    end
    return
  end
  a.aux = a.aux - 1
  if a.aux < 0 then
    a.itl = (a.itl + 1) % 256
    if band(a.itl, bit.bnot(1)) ~= 0 then a.step = 1; a.itl = bor(band(a.itl, 7), 4) end
    a.aux = 3
  end
  if a.step == 1 then
    if offscreen(game, a) then a.gone = true return end
    move(a)
    if TL.spriteHit(game, a, IT(game).ancDamage[TL.ANC_ICE + 1]) or tileHit(game, a, a.dir + 8) then
      a.kind, a.itl, a.aux = "icehit", 0, 4
    end
  end
end

-- ------------------------------------------------------------ the boomerang
local function addBoomerang(game, held)
  local tb = T(game)
  local lk = game.link
  local level = math.max(1, inv(game)[0x21] or 1)
  local j0 = level - 1
  local d = (held.up and 8 or 0) + (held.down and 4 or 0) + (held.left and 2 or 0) + (held.right and 1 or 0)
  local diag = band(d, 0xC) ~= 0 and band(d, 3) ~= 0
  local s = j0 * 2 + (diag and 1 or 0)
  local r0 = tb.boomTab0[s + 1]
  local r1 = d ~= 0 and d or TL.BOOM_TAB3[dirIndex(lk.facing) + 1]
  local a = { kind = "boom", level = level, G = j0, step = tb.boomTab1[j0 + 1], arr3 = tb.boomTab2[j0 + 1],
              H = r0, K = 0, back = false, vx = 0, vy = 0, S = 0, arr1 = 0, dir = dirIndex(lk.facing),
              lower = game.interior and (game.interior.lower or false) or false, edge = 0 }
  if band(r1, 0xC) ~= 0 then
    a.vy = band(r1, 8) ~= 0 and -r0 or r0
    a.dir = a.vy < 0 and 0 or 1
    a.edge = TL.BOOM_TAB3[a.dir + 1]
  end
  if band(r1, 3) ~= 0 then
    if band(r1, 2) == 0 then a.S = 1 end
    a.vx = band(r1, 2) ~= 0 and -r0 or r0
    a.dir = a.vx < 0 and 2 or 3
    a.edge = bor(a.edge, TL.BOOM_TAB3[a.dir + 1])
  end
  local j = 0
  for i = 1, 8 do if tb.boomTab4[i] == r1 then j = i - 1 break end end
  a.arr1 = tb.boomTab5[j + 1]
  if s ~= 0 or d == 0 then j = dirIndex(lk.facing) end
  a.x, a.y = lk.x + TL.BOOM_TAB7[j + 1], lk.y + 8 + TL.BOOM_TAB6[j + 1]
  game.anc = game.anc or {}
  game.anc[#game.anc + 1] = a
  game.boomThrows = (game.boomThrows or 0) + 1
  return a
end

local function boomFrame(game, a)
  local lk = game.link
  if a.back then
    if a.K ~= 0 then a.K = a.K + 1 end
    local Actors = require("src.zelda.alttp.Actors")
    a.vx, a.vy = Actors.project(a.x, a.y, lk.x, lk.y + 8, a.H)
  end
  if a.vy ~= 0 then a.vy = a.vy + a.K end
  if a.vx ~= 0 then a.vx = a.vx + a.K end
  move(a)
  local spr = TL.spriteHit(game, a, IT(game).ancDamage[TL.ANC_BOOM + 1])
  if not a.back then
    local cx, cy = game:ancCamera()
    local edge = false
    if band(a.edge, 3) ~= 0 then
      local t = a.x + (band(a.edge, 1) ~= 0 and 16 or 0) - cx
      if t < 0 or t >= 0x100 then edge = true end
    end
    if band(a.edge, 12) ~= 0 then
      local t = a.y + (band(a.edge, 4) ~= 0 and 16 or 0) - cy
      if t < 0 or t >= 0xE2 then edge = true end
    end
    if spr then a.back = true
    elseif tileHit(game, a, a.dir) then a.back = true; game.boomWalls = (game.boomWalls or 0) + 1
    elseif edge then a.back = true
    else
      a.step = a.step - 1
      if a.step == 0 then a.back = true elseif a.step < 5 then a.K = a.K - 1 end
    end
  else
    -- Boomerang_StopOffScreen: caught at Link
    local x, y = a.x + 8, a.y + 8
    if x >= lk.x and x < lk.x + 16 and y >= lk.y and y < lk.y + 24 then
      a.gone = true
      game.boomCatches = (game.boomCatches or 0) + 1
    end
  end
  -- the drops it touches come back with it (Sprite_HandleAncillaCollision for prizes)
  for _, d in ipairs(game.drops or {}) do
    if not d.gone and not d.onBoom and math.abs(d.x - a.x) < 12 and math.abs(d.y - a.y) < 12 then d.onBoom = a end
  end
  for _, d in ipairs(game.drops or {}) do
    if d.onBoom == a then
      if a.gone then d.onBoom = nil; d.x, d.y = lk.x, lk.y + 8 else d.x, d.y = a.x, a.y end
    end
  end
  -- the spin of its picture
  a.arr3 = a.arr3 - 1
  if a.arr3 < 0 then
    a.arr3 = T(game).boomDrawTab0[a.G + 1]
    a.arr1 = band(a.arr1 + (a.S ~= 0 and -1 or 1), 3)
  end
end

-- ------------------------------------------------------------ the hookshot
local function addHook(game)
  local tb = T(game)
  local lk = game.link
  local j = dirIndex(lk.facing)
  local a = { kind = "hook", dir = j, x = lk.x + tb.hookXd[j + 1], y = lk.y + tb.hookYd[j + 1],
              vx = tb.hookXv[j + 1], vy = tb.hookYv[j + 1], itl = 0, step = 0, pull = false,
              lower = game.interior and (game.interior.lower or false) or false }
  game.anc = game.anc or {}
  game.anc[#game.anc + 1] = a
  game.hookShots = (game.hookShots or 0) + 1
  return a
end

-- Hookshot_CheckSingleLayerTileCollision: two points by direction
local function hookTiles(game, a)
  local O = require("src.zelda.alttp.Overworld")
  local wall, hook = false, false
  for i = 0, 1 do
    local px = a.x + TL.HOOK_COLL_X[a.dir * 2 + i + 1]
    local py = a.y + TL.HOOK_COLL_Y[a.dir * 2 + i + 1]
    local at = game:ancAttr(px, py)
    if at == TL.HOOKABLE then hook = true
    elseif game.interior then
      local c = IT(game).tileAttrs[at + 1] or 0
      if c == 1 or c == 2 then wall = true end
    elseif O.isSolid(at) and at ~= 0x08 then wall = true end
  end
  return wall, hook
end

local function hookFrame(game, a)
  if a.pull then return end
  move(a)
  if a.step == 1 then
    a.itl = a.itl - 1
    if a.itl < 0 then a.gone = true; game.hookUse = nil end
    return
  end
  a.itl = a.itl + 1
  if a.itl == 32 then a.step = 1; a.vx, a.vy = -a.vx, -a.vy end
  if a.step == 0 and TL.spriteHit(game, a, nil, { a.x, a.y, 8, 8 }) then
    a.step = 1; a.vx, a.vy = -a.vx, -a.vy
    local s = TL.spriteHit(game, a, IT(game).ancDamage[0x1F + 1], { a.x, a.y, 8, 8 })
  end
  local wall, hook = hookTiles(game, a)
  if wall and a.step == 0 then
    a.step = 1; a.vx, a.vy = -a.vx, -a.vy
    game.hookWalls = (game.hookWalls or 0) + 1
  end
  if hook then
    if a.itl < 4 then a.gone = true; game.hookUse = nil return end
    a.pull = true
    a.step = 0
    game.hookPulls = (game.hookPulls or 0) + 1
  end
end

-- LinkState_Hookshotting: Link pulled to the hook
local function pullFrame(game, a)
  local tb = T(game)
  local lk = game.link
  local d = a.dir
  a.itl = a.itl - 1
  local vx, vy = 0, 0
  if a.itl >= 0 then
    if math.abs(a.y + tb.hookArrA[d + 1] - lk.y) >= 2 then vy = tb.hookArrC[d + 1] end
    if math.abs(a.x + tb.hookArrB[d + 1] - lk.x) >= 2 then vx = tb.hookArrD[d + 1] end
  end
  if vx ~= 0 or vy ~= 0 then
    lk.subX, lk.subY = lk.subX or 0, lk.subY or 0
    local tx = (lk.subX or 0) + vx * 16 + lk.x * 256
    local ty = (lk.subY or 0) + vy * 16 + lk.y * 256
    lk.x, lk.subX = math.floor(tx / 256), tx % 256
    lk.y, lk.subY = math.floor(ty / 256), ty % 256
    return true
  end
  a.gone = true
  game.hookUse = nil
  -- Player_TileDetectNearby: deep water -> swimming
  if not game.interior then
    local deep = 0
    for _, p in ipairs({ { 2, 10 }, { 13, 10 }, { 2, 21 }, { 13, 21 } }) do
      if game.ow:attrAt(lk.world, lk.x + p[1], lk.y + p[2]) == 0x08 then deep = deep + 1 end
    end
    if deep > 0 then
      local Swim = package.loaded["src.zelda.alttp.Swim"]
      if Swim and require("src.zelda.alttp.DarkWorld").hasFlippers(game) then Swim.enter(game) end
    end
  end
  game.hookArrivals = (game.hookArrivals or 0) + 1
  return true
end

-- ------------------------------------------------------------ the tile tools
local function toolTile(game, item, fromTo)
  local lk = game.link
  local OwSword = require("src.zelda.alttp.OwSword")
  local f = OwSword.tileOffset(game, item)
  if not f or game.interior then return false end
  mergeMap16(game)
  local x, y = lk.x + f[1], lk.y + f[2]
  if game:owTileChange(x, y, fromTo) then
    return true, x, y
  end
  return false, x, y
end

-- ------------------------------------------------------------ install
TL.ITEM_SLOT = { [2] = "boomerang", [3] = "hookshot", [7] = "firerod", [8] = "icerod", [14] = "hammer", [19] = "shovel" }

function TL.install(G)
  local Items = require("src.zelda.alttp.Items")
  for s, n in pairs(TL.ITEM_SLOT) do Items.SLOT[s] = n end
  local W = require("src.zelda.alttp.Weapon")
  -- the hook's strip frame is the one Link's pose shows (link_dma_var5)
  local drawItem0 = W.drawItem
  function W:drawItem(pc, x, y, spr)
    W.lastVar5 = pc.var5
    return drawItem0(self, pc, x, y, spr)
  end
  local have = {}
  for _, b in ipairs(W.ITEM_BLOCKS) do have[b.off] = true end
  for _, b in ipairs(TL.STRIP) do if not have[b.off] then W.ITEM_BLOCKS[#W.ITEM_BLOCKS + 1] = b end end

  local itemFrame0 = G.itemFrame
  function G:itemFrame(inp)
    if not T(self) then return itemFrame0(self, inp) end
    local u = self.toolUse
    if u then return TL.useFrame(self, u) end
    if self.hookUse then
      for _, a in ipairs(self.anc or {}) do
        if a.kind == "hook" and a.pull and not a.gone then return pullFrame(self, a) end
      end
      for _, a in ipairs(self.anc or {}) do if a.kind == "hook" and not a.gone then return true end end
      self.hookUse = nil
      return true
    end
    if inp.y and not self.bowUse and (self.link.doorway or 0) == 0 and not self.carry then
      local item = self:yItem()
      local lk = self.link
      if item == "firerod" or item == "icerod" then
        if TL.magic(self, 0) then
          if item == "firerod" then addFire(self) else addIce(self) end
          self.toolUse = { kind = "rod", t = 0, delay = TL.ROD_DELAYS[1], hand = 1 }
          lk.steps = 0
          return true
        end
        return false
      elseif item == "hammer" then
        self.toolUse = { kind = "hammer", t = 0, delay = T(self).hammerDelays[1], hand = 2 }
        lk.steps = 0
        return true
      elseif item == "shovel" then
        self.toolUse = { kind = "shovel", t = 0, var = 0, delay = TL.SHOVEL_DELAY[1], mode = 1 }
        lk.steps = 0
        return true
      elseif item == "boomerang" then
        for _, a in ipairs(self.anc or {}) do if a.kind == "boom" and not a.gone then return false end end
        local held = { up = self.input and self.input.isDown("up"), down = self.input and self.input.isDown("down"),
                       left = self.input and self.input.isDown("left"), right = self.input and self.input.isDown("right") }
        addBoomerang(self, held)
        self.toolUse = { kind = "boomerang", t = 0, delay = 7, hand = 0x80 }
        lk.steps = 0
        return true
      elseif item == "hookshot" then
        addHook(self)
        self.hookUse = true
        lk.steps = 0
        return true
      end
    end
    return itemFrame0(self, inp)
  end

  -- the items' own ancillae (Ancilla_Main)
  local updAnc0 = G.updateAncillae
  function G:updateAncillae()
    updAnc0(self)
    local l = self.anc
    if not l or #l == 0 or not T(self) then return end
    local keep = {}
    for _, a in ipairs(l) do
      if a.kind == "fire" then fireFrame(self, a)
      elseif a.kind == "ice" or a.kind == "icehit" then iceFrame(self, a)
      elseif a.kind == "boom" then boomFrame(self, a)
      elseif a.kind == "hook" then hookFrame(self, a)
      end
      if not a.gone then keep[#keep + 1] = a end
    end
    self.anc = keep
  end

  -- the poses (kPlayerOam_Tab2 by link_item_in_hand, Tab3 by link_position_mode)
  local TAB2 = { [1] = 6, [2] = 6, [0x80] = 9 }
  local pose0 = G.linkPose
  function G:linkPose()
    local u = self.toolUse
    if u then
      if u.mode == 1 then return 12, u.t end
      return TAB2[u.hand] or 6, u.t
    end
    if self.hookUse then return 32, 0 end
    return pose0(self)
  end

  local drawAnc0 = G.drawAncillae
  function G:drawAncillae(cx, cy, spr)
    drawAnc0(self, cx, cy, spr)
    if T(self) and spr and self.anc then TL.draw(self, cx, cy, spr) end
  end

  -- a room change ends a use
  local enter0 = G.enterRoom
  function G:enterRoom(e)
    self.toolUse, self.hookUse = nil, nil
    return enter0(self, e)
  end
end

-- one frame of a tool in hand (Link halted)
function TL.useFrame(game, u)
  local lk = game.link
  lk.moving, lk.steps = false, 0
  u.delay = u.delay - 1
  if u.delay >= 0 then return true end
  if u.kind == "rod" then
    u.t = u.t + 1
    u.delay = TL.ROD_DELAYS[u.t + 1] or 0
    if u.t == 3 then game.toolUse = nil end
  elseif u.kind == "hammer" then
    u.t = u.t + 1
    u.delay = T(game).hammerDelays[u.t + 1] or 0
    if u.t == 1 then
      local ok = toolTile(game, 3, TL.PEG)
      if ok then game.pegsHammered = (game.pegsHammered or 0) + 1 end
      game.hammerSwings = (game.hammerSwings or 0) + 1
      -- the hammer's hit on sprites (Player_SetupActionHitBox t = 0 at
      -- player_handler_timer 1; damage class 3: Sprite_CalculateSwordDamage)
      local f = require("src.zelda.alttp.OwSword").tileOffset(game, 3)
      if f and TL.hammerHook then TL.hammerHook(game, actorsHere(game), lk.x + f[1] - 8, lk.y + f[2] - 8, 16, 16) end
      if f then
        local acts = actorsHere(game)
        if acts then
          local Items = require("src.zelda.alttp.Items")
          acts:swordHit(lk.x + f[1] - 8, lk.y + f[2] - 8, 16, 16,
                        { cls = 3, hammer = true, lower = game.interior and (game.interior.lower or false) or false,
                          dmg = function(t) return Items.damage(game, 3, t) end })
        end
      end
    elseif u.t == 3 then
      game.toolUse = nil
    end
  elseif u.kind == "shovel" then
    u.var = u.var + 1
    u.delay = TL.SHOVEL_DELAY[u.var + 1] or 0
    u.t = TL.SHOVEL_STEP[u.var + 1] or 0
    if u.t == 1 then
      local ok, x, y = toolTile(game, 2, TL.DIGGABLE)
      if ok then
        game.digs = (game.digs or 0) + 1
        local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
        -- the flute: area 0x2A, map16 spot 0x492 (word_7E04B2)
        local area = game.area
        local pos = math.floor((ty - area.y) / 16) * 128 + math.floor((tx - area.x) / 16) * 2
        if area.parent == 0x2A and lk.world == "lw" and pos == 0x492 then
          game.fluteDug = (game.fluteDug or 0) + 1
          game:getItem(0x14)
        elseif (game.lastSecret or 0) ~= 0 then
          game:terrainDrop(5, game.lastSecret, tx, ty)
        end
      end
    end
    if u.var == 3 then game.toolUse = nil end
  elseif u.kind == "boomerang" then
    u.delay = 5
    u.t = u.t + 1
    if u.t == 2 then game.toolUse = nil end
  end
  return true
end

-- ------------------------------------------------------------ drawing
-- a char of the item strip at the frame link_dma_var5 (Weapon.drawItem's rule)
local function stripChar(game, spr, char, var5, x, y, flags)
  local W = require("src.zelda.alttp.Weapon")
  local w = game.weapon
  local fx = game.data.roomIdx and game.data.roomIdx.combat and game.data.roomIdx.combat.fx
  if not (w and fx and spr and spr.pal) then return end
  local src = fx.itemDma[var5 + 1] or 0
  local src2 = src + (fx.itemDma2[math.floor(var5 / 8) + 1] or 0)
  local m = W.ITEM_CHARS[char]
  if not m then return end
  local sheet, tile = W.itemTile((m[1] == 0 and src or src2) + m[2] * 32)
  local row = band(rshift(flags, 1), 7)
  local pal = spr.pal[row]
  local im = sheet and pal and w:itemImage(sheet, tile, pal, row)
  if not im then return end
  local hf, vf = band(flags, 0x40) ~= 0, band(flags, 0x80) ~= 0
  love.graphics.draw(im, x + (hf and 8 or 0), y + (vf and 8 or 0), 0, hf and -1 or 1, vf and -1 or 1)
end

function TL.draw(game, cx, cy, spr)
  local tb = T(game)
  for _, a in ipairs(game.anc) do
    local x, y = a.x - cx, a.y - cy
    if a.kind == "fire" then
      if a.step == 0 then
        local j = band(a.ctr, 0xC)
        for i = 2, 0, -1 do
          spr:oam(x + tb.fireDrawX2[j + i + 1], y + tb.fireDrawY2[j + i + 1], tb.fireChar2[i + 1], 2, 0)
        end
      else
        local j = rshift(a.t, 3)
        if j ~= 0 then spr:oam(x, y, tb.fireChar[j], 2, 2)
        else spr:oam(x, y - 3, tb.fireChar[4], 2, 0); spr:oam(x + 8, y - 3, tb.fireChar[4] + 1, 2, 0) end
      end
    elseif a.kind == "ice" or a.kind == "icehit" then
      local base = (a.kind == "icehit") and a.itl * 4 or 0
      if a.kind == "icehit" or a.step == 1 then
        for i = 0, 3 do
          local j = base + i
          if j < 8 then
            spr:oam(x + tb.iceSpreadXY[j * 2 + 2], y + tb.iceSpreadXY[j * 2 + 1], tb.iceSpreadCF[j * 2 + 1],
                    band(tb.iceSpreadCF[j * 2 + 2], bit.bnot(0x30)), 0)
          end
        end
      end
    elseif a.kind == "boom" then
      local j = a.arr1
      spr:oam(x + tb.boomXY[j * 2 + 2], y + tb.boomXY[j * 2 + 1], 0x46,
              band(tb.boomFlags[a.G * 4 + j + 1], bit.bnot(0x30)), 2)
    elseif a.kind == "hook" then
      -- the hook (chars 9 / 0xA of the strip) and the chain (0x19 -> GBA 0x29)
      local var5 = require("src.zelda.alttp.Weapon").lastVar5 or 0
      local j = a.dir * 3
      local hx, hy = x, y
      for i = 2, 0, -1 do
        local ch = tb.hookChar[j + 1]
        if ch ~= 0xFF then stripChar(game, spr, ch, var5, hx, hy, bor(tb.hookFlags[j + 1], 2)) end
        if i == 1 then hx, hy = hx - 8, hy + 8 else hx = hx + 8 end
        j = j + 1
      end
      local n = rshift(math.max(0, a.itl), 1)
      local r10 = 0
      if n >= 7 then r10 = n - 7; n = 6 end
      if n > 0 then
        if band(a.dir, 1) ~= 0 then r10 = -r10 end
        local px, py = x, y
        local d = a.dir
        if TL.HOOK_MOVE_Y[d + 1] == 0 then py = py + 4 end
        if TL.HOOK_MOVE_X[d + 1] == 0 then px = px + 4 end
        for _ = 0, n do
          if TL.HOOK_MOVE_Y[d + 1] ~= 0 then py = py + TL.HOOK_MOVE_Y[d + 1] + r10 end
          if TL.HOOK_MOVE_X[d + 1] ~= 0 then px = px + TL.HOOK_MOVE_X[d + 1] + r10 end
          stripChar(game, spr, 0x29, var5, px, py, bor(band(game.frame, 2) * 64, 2))
        end
      end
    end
  end
end

return TL
