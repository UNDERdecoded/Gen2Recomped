-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CANES, THE POWDER, THE MUSHROOM, THE BUG NET, THE MAGIC BAT (round 27,
-- team A). The SNES routines the GBA keeps (zelda3 names); the GBA's own
-- tables where they were found by value (OFF; the GBA widened the ancillae's
-- int8 offset tables to s16 and stores OBJ chars already converted with
-- (row & 7) * 32 + (row >> 3) * 16 + col), else the disassembly's constants:
--
--   LinkCheckMagicCost    0x080A3B64: cost = kLinkItem_MagicCosts (0x1690F5)
--                         [idx (0x169113)[x] + link_magic_consumption], the
--                         consumption byte GBA 0x0200235B (inventory 0x5B;
--                         magic is 0x4E); no magic: message 123. Tools.magic
--                         (the rods, medallions) is routed through it, so the
--                         Magic Bat halves those too.
--   LinkItem_Powder       kMushroomTimer (0x1690E5); the mushroom (0x24 = 1)
--                         does nothing, the powder (2) costs index 2, at step 4
--                         AncillaAdd_MagicPowder (kMagicPower_X/Y 0x17F280 /
--                         0x17F278, X1/Y1 0x17F270 / 0x17F268); link_item_in_hand
--                         0x40 (pose kPlayerOam_Tab2 -> 8).
--   Ancilla1A_PowderDust  kMagicPowder_Tab0 (0x17F0AC) every 2 frames, 9 steps;
--                         Powder_ApplyDamageToSprites: damage class 10 (249 ->
--                         a fairy 0xE3, 250 -> 0x8F), the Buzzblob 0x0D turns
--                         Cukeman (sprite_head_dir 1, messages 0x17A / 0x17B);
--                         drawn from the item strip at link_dma_var5 80
--                         (kMagicPowder_DrawX/Y 0x17F170 / 0x17F0D8, chars
--                         0x17F208, flags 0x17F21C).
--   LinkItem_Net          kBugNetTimers (0x16909E) every 4 frames, 10 steps,
--                         link_position_mode 0x10 (pose 35); the action box
--                         (kPlayer_SetupActionHitBox t = 0: 15 x 15 at Link +
--                         kSwordOamX/YOffs[r2] of the drawn pose) catches a bee
--                         (Bee_Main: message 0xC8, choice 0 -> the first empty
--                         bottle = 7) or a fairy (Sprite_E3_Fairy: 0xC9 -> 6);
--                         no empty bottle: 0xCA.
--   LinkItem_CaneOfByrna  index 8, kByrnaDelays {19, 7, 13, 32} (pose 34);
--                         Ancilla30_ByrnaWindupSpark (kInitialCaneSpark_X/Y
--                         0x17F9BC / 0x17F99C, draw 0x17F93C..), 17 steps, then
--                         Ancilla31_ByrnaSpark: four sparks (chars 0x16E838)
--                         on kCaneSpark_Transmute_Tab (0x17F9DC) angles + 3 a
--                         frame at radius 20 (Ancilla_GetRadialProjection,
--                         0x16E70C..0x16E7CC), around Link + (8, 12); Link takes
--                         no sprite damage; kCaneSpark_Magic {4, 2, 1} every 24
--                         frames; A again, another item or no magic ends it.
--   LinkItem_CaneOfSomaria index 4, kRodAnimDelays (pose 34); one block: a
--                         second use splits it (Ancilla2E_SomariaBlockFission,
--                         0x17FBAA.., then four Ancilla01_SomariaBullet at
--                         kFireRod_X/Yvel2 0x171D62 / 0x171D6E, blast tables
--                         0x17FAE2..0x17FB90); AncillaAdd_SomariaBlock at Link
--                         + kCaneOfSomaria_X/Y (0x17FA28 / 0x17FA20), 13 frames
--                         before it shows; Ancilla2C_SomariaBlock: four cover
--                         points (+-4) on switch attributes 0x23 / 0x24 / 0x25
--                         / 0x3B hold the room's floor switch
--                         (dung_flag_somaria_block_switch); a pit (0x20, 0xB0..
--                         but 0xB6 / 0xBC) or deep water (8) takes it after 2
--                         frames; the fifth sprite it touches fizzles it
--                         (Ancilla2D, 0x17FC0A..); the block is char 0xE9 ->
--                         GBA 0xD9, four flipped 8 x 8 quarters.
--   Sprite_ED_SomariaPlatform  the block on a transit tile (0xB6 / 0xBC) in a
--                         room with track tiles becomes the platform: it rides
--                         the 0xB0-0xBE tracks at 16 (kSomariaPlatform_Xvel /
--                         Yvel), junctions by the held d-pad, Link carried.
--   Sprite_E7_Mushroom    Lost Woods (area 0, lists of phases 2 / 3): touched
--                         -> receipt 0x29 (not while the powder is owned).
--   Sprite_Witch (0x36)   area 0x16: messages 0x4A / 0x4B / 0x4C; holding the
--                         item button with the mushroom chosen while touching
--                         her: she takes it (save_dung_info[0x109] |= 0x80).
--   MagicShopAssistant_SpawnPowder  room 0x109 entered from outside with that
--                         flag and no powder: the bag (0xE9 subtype 1) 16 px
--                         left of the assistant; R while touching -> receipt 0x0D.
--   Sprite_3A_MagicBat    room 0xE3 (x + 8): the powder touching Link at the
--                         bat summons it (rising, message 0x110, the pseudo
--                         attack, 0x111) -> link_magic_consumption 1.
--
-- OURS / NOT PORTED: carrying and throwing the Somaria block and pushing it;
-- conveyors under it; the platform's room 0x24 rule and its pipes (0xAE-0xB1);
-- dung_unk6 (the Cane Ride Spawn object) is read as "the room has an 0xB6 /
-- 0xBC tile"; the Mad Batter's lightning and palette flash; the Cukeman's own
-- picture; the potion cauldrons (the shop clerk's other sprites); the witch is
-- drawn with the disassembly's Witch_Draw constants (no GBA copy was found);
-- no sounds.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = {}

M.OFF = {
  costIdx = 0x169113, mushroomTimer = 0x1690E5, netTimers = 0x16909E,
  powderTab0 = 0x17F0AC, powderDrawY = 0x17F0D8, powderDrawX = 0x17F170, powderChar = 0x17F208,
  powderFlags = 0x17F21C, powderY1 = 0x17F268, powderX1 = 0x17F270, powderY = 0x17F278, powderX = 0x17F280,
  sparkDrawChar = 0x17F93C, sparkDrawFlags = 0x17F94C, sparkDrawY = 0x17F95C, sparkDrawX = 0x17F97C,
  sparkY = 0x17F99C, sparkX = 0x17F9BC, sparkTransmute = 0x17F9DC, sparkChar = 0x16E838,
  rad0 = 0x16E74C, rad1 = 0x16E78C, rad2 = 0x16E70C, rad3 = 0x16E7CC,
  transY = 0x17F9F0, transX = 0x17FA08, caneY = 0x17FA20, caneX = 0x17FA28,
  blockDrawY = 0x17FA3C, blockDrawX = 0x17FA54, blockCollY = 0x17FA6C, blockCollX = 0x17FA84,
  quadX = 0x17FAD2, quadY = 0x17FADA, blastMask = 0x17FAE2, blastChar0 = 0x17FAE8, blastChar1 = 0x17FB00,
  blastFlags0 = 0x17FB18, blastFlags1 = 0x17FB30, blastX0 = 0x17FB48, blastX1 = 0x17FB60,
  blastY0 = 0x17FB78, blastY1 = 0x17FB90,
  divY = 0x17FBAA, divX = 0x17FBCA, divChar = 0x17FBEA, divFlags = 0x17FBFA,
  fizzY = 0x17FC0A, fizzX = 0x17FC16, fizzChar = 0x17FC22, fizzFlags = 0x17FC28,
  fireXv2 = 0x171D62, fireYv2 = 0x171D6E,
}
M.INV_CONSUMPTION = 0x5B
M.INV_POWDER = 0x24           -- grid slot 5: 1 mushroom, 2 powder
M.BOTTLES = { 0x25, 0x2B, 0x31, 0x37 }
M.SLOTS = { [5] = "powder", [16] = "net", [20] = "somaria", [21] = "byrna" }
-- the disassembly's constants (no GBA table told apart by value)
M.BYRNA_DELAYS = { 19, 7, 13, 32 }
M.SPARK_MAGIC = { 4, 2, 1 }
M.ROD_DELAYS = { 3, 3, 5 }
M.BLOCK_CHAR = 0xD9           -- SNES 0xE9
M.BLOCK_FLAGS = { 0, 0x40, 0x80, 0xC0 }
M.COVER_X, M.COVER_Y = { 0, 0, -4, 4 }, { -4, 4, 0, 0 }
M.BLAST_FLAGS = { 2, 6 }
M.PLAT_XV = { 0, 0, -16, 16, -16, 16, 16, -16 }
M.PLAT_YV = { -16, 16, 0, 0, -16, 16, -16, 16 }
M.PLAT_POOF = { 1, 0, 3, 2 }
M.MSG_NO_MAGIC = 123
M.MSG_BEE, M.MSG_FAIRY, M.MSG_NOBOTTLE = 0xC8, 0xC9, 0xCA
M.MSG_WITCH = { none = 0x4A, took = 0x4B, give = 0x4C }
M.MSG_BAT = { 0x110, 0x111 }
M.MSG_CUKEMAN = 0x17A
M.WITCH_A = {
  { -3, 8, 0xAE }, { -3, 16, 0xBE }, { -2, 8, 0xAE }, { -2, 16, 0xBE }, { -1, 8, 0xAF }, { -1, 16, 0xBF },
  { 0, 9, 0xAF }, { 0, 17, 0xBF }, { 1, 10, 0xAF }, { 1, 18, 0xBF }, { 0, 11, 0xAF }, { 0, 18, 0xBF },
  { -1, 10, 0xAE }, { -1, 18, 0xBE }, { -3, 9, 0xAE }, { -3, 17, 0xBE },
}
M.WITCH_B = { { 0, -4, 0x80, 0x00 }, { -11, 15, 0x86, 0x04 }, { -3, 15, 0x86, 0x44 } }
M.WITCH_C = { { 0, 4, 0x84 }, { 0, 4, 0x82 } }
M.PLAT_DMD = {
  { -16, -16, 0x00 }, { 0, -16, 0x40 }, { -16, 0, 0x80 }, { 0, 0, 0xC0 },
  { -13, -13, 0x00 }, { -3, -13, 0x40 }, { -13, -3, 0x80 }, { -3, -3, 0xC0 },
  { -10, -10, 0x00 }, { -6, -10, 0x40 }, { -10, -6, 0x80 }, { -6, -6, 0xC0 },
  { -8, -8, 0x00 }, { -8, -8, 0x40 }, { -8, -8, 0x80 }, { -8, -8, 0xC0 },
}
M.MUSHROOM_AREA, M.WITCH_AREA, M.SHOP_ROOM, M.BAT_ROOM = 0x00, 0x16, 0x109, 0xE3

function M.conv(c) return (band(rshift(c, 4), 7)) * 32 + rshift(c, 7) * 16 + band(c, 15) end

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end

function M.extract(rom, R, check)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local w = function(o, n) return s16(rom:bytesU16(o, n)) end
  local t = {
    costIdx = u8(O.costIdx, 10), mushroomTimer = u8(O.mushroomTimer, 10), netTimers = u8(O.netTimers, 40),
    powderTab0 = u8(O.powderTab0, 40), powderDrawY = w(O.powderDrawY, 76), powderDrawX = w(O.powderDrawX, 76),
    powderChar = u8(O.powderChar, 19), powderFlags = u8(O.powderFlags, 76),
    powderY1 = w(O.powderY1, 4), powderX1 = w(O.powderX1, 4), powderY = w(O.powderY, 4), powderX = w(O.powderX, 4),
    sparkDrawChar = u8(O.sparkDrawChar, 16), sparkDrawFlags = u8(O.sparkDrawFlags, 16),
    sparkDrawY = w(O.sparkDrawY, 16), sparkDrawX = w(O.sparkDrawX, 16),
    sparkY = w(O.sparkY, 16), sparkX = w(O.sparkX, 16), sparkTransmute = u8(O.sparkTransmute, 16),
    sparkChar = u8(O.sparkChar, 4),
    rad0 = u8(O.rad0, 64), rad1 = u8(O.rad1, 64), rad2 = u8(O.rad2, 64), rad3 = u8(O.rad3, 64),
    transY = w(O.transY, 12), transX = w(O.transX, 12), caneY = w(O.caneY, 4), caneX = w(O.caneX, 4),
    blockDrawY = w(O.blockDrawY, 12), blockDrawX = w(O.blockDrawX, 12),
    blockCollY = w(O.blockCollY, 12), blockCollX = w(O.blockCollX, 12),
    quadX = w(O.quadX, 4), quadY = w(O.quadY, 4), blastMask = u8(O.blastMask, 6),
    blastChar0 = u8(O.blastChar0, 24), blastChar1 = u8(O.blastChar1, 24),
    blastFlags0 = u8(O.blastFlags0, 24), blastFlags1 = u8(O.blastFlags1, 24),
    blastX0 = s8(u8(O.blastX0, 24)), blastX1 = s8(u8(O.blastX1, 24)),
    blastY0 = u8(O.blastY0, 24), blastY1 = u8(O.blastY1, 24),
    divY = w(O.divY, 16), divX = w(O.divX, 16), divChar = u8(O.divChar, 16), divFlags = u8(O.divFlags, 16),
    fizzY = w(O.fizzY, 6), fizzX = w(O.fizzX, 6), fizzChar = u8(O.fizzChar, 6), fizzFlags = u8(O.fizzFlags, 6),
    fireXv2 = s8(u8(O.fireXv2, 12)), fireYv2 = s8(u8(O.fireYv2, 12)),
  }
  check(t.costIdx[3] == 6 and t.costIdx[9] == 24 and t.mushroomTimer[1] == 2 and t.mushroomTimer[9] == 6,
        "magic cost index / kMushroomTimer")
  check(t.netTimers[1] == 11 and t.netTimers[31] == 10, "kBugNetTimers")
  check(t.powderTab0[1] == 13 and t.powderDrawX[1] == -5 and t.powderDrawY[1] == -20 and t.powderChar[2] == 10
        and t.powderFlags[1] == 0x68 and t.powderX[3] == -12 and t.powderY1[2] == 40, "magic powder tables")
  check(t.sparkX[1] == 3 and t.sparkY[3] == -3 and t.sparkTransmute[1] == 0x34 and t.sparkChar[1] == 183
        and t.rad0[1] == 255 and t.rad2[17] == 255 and t.rad1[1] == 1 and t.rad3[34] == 1, "Cane of Byrna tables")
  check(t.caneY[2] == 31 and t.caneX[4] == 23 and t.blockCollX[3] == -8 and t.transX[7] == -16
        and t.quadY[1] == -15 and t.divChar[1] == 150 and t.fizzChar[1] == 50 and t.fireXv2[3] == -40
        and t.blastMask[1] == 7 and t.blastChar0[1] == 178, "Cane of Somaria tables")
  return t
end

local function T(game) return game.data.t and game.data.t.items27 end
local function IT(game) return require("src.zelda.alttp.Items").tabs(game) end
local function inv(game) return require("src.zelda.alttp.Menu").inventory(game) end
local function actorsHere(game) if game.interior then return game.actors end return game.owActors end
local function dirIndex(f) return math.floor((f or 0) / 2) end
local function setInv(game, k, v)
  local p = game.progress
  p.inv = p.inv or {}
  p.inv[k] = v
  p.inv[tostring(k)] = nil
end
M.setInv = setInv

-- ------------------------------------------------------------ magic
function M.consumption(game) return inv(game)[M.INV_CONSUMPTION] or 0 end

-- LinkCheckMagicCost(x) (0x080A3B64)
function M.magic(game, x)
  local tb = T(game)
  local cost
  if tb then cost = IT(game).magicCosts[(tb.costIdx[x + 1] or x * 3) + M.consumption(game) + 1] or 0
  else cost = IT(game).magicCosts[x * 3 + 1] or 0 end
  local a = game.stats.magic or 0
  if a ~= 0 and a - cost >= 0 then
    game.stats.magic = a - cost
    return true
  end
  if x ~= 3 then game:showMessage(M.MSG_NO_MAGIC) end
  return false
end

-- Ancilla_MoveX/Y (1/16 px)
local function move(a)
  a.sx, a.sy = (a.sx or 0) + (a.vx or 0), (a.sy or 0) + (a.vy or 0)
  local mx = (a.sx >= 0) and math.floor(a.sx / 16) or -math.floor(-a.sx / 16)
  local my = (a.sy >= 0) and math.floor(a.sy / 16) or -math.floor(-a.sy / 16)
  a.sx, a.sy = a.sx - mx * 16, a.sy - my * 16
  a.x, a.y = a.x + mx, a.y + my
end

local function lower(game) return game.interior and (game.interior.lower or false) or false end

local function emptyBottle(game)
  local iv = inv(game)
  for _, k in ipairs(M.BOTTLES) do if (iv[k] or 0) == 2 then return k end end
  return nil
end

-- ------------------------------------------------------------ the powder
local function addPowder(game)
  local tb = T(game)
  local lk = game.link
  local j = dirIndex(lk.facing)
  local a = { kind = "powder", dir = j, itl = 0, aux = 1, arr25 = tb.powderTab0[j * 10 + 1],
              x = lk.x + tb.powderX1[j + 1], y = lk.y + tb.powderY1[j + 1], lower = lower(game) }
  game.anc = game.anc or {}
  game.anc[#game.anc + 1] = a
  game.powderUses = (game.powderUses or 0) + 1
  return a
end

-- Powder_ApplyDamageToSprites
local function powderHits(game, a)
  local acts = actorsHere(game)
  if not acts then return end
  local cb = game.data.roomIdx.combat
  local Actors = require("src.zelda.alttp.Actors")
  local Items = require("src.zelda.alttp.Items")
  for i, s in ipairs(acts.list) do
    local k = s.index or i
    if not s.dead and not s.npc and band(bxor(game.frame or 0, k), 3) == 0
       and band(cb.bump and cb.bump[s.type + 1] or 0, 0x20) == 0 and (s.lower or false) == (a.lower or false) then
      local bx, by, bw, bh = Actors.hitbox(cb, s)
      if Actors.overlapCart(a.x - 8, a.y - 8, 15, 15, bx, by - (s.z or 0), bw, bh) then
        if s.type == 0x0D then
          if not s.cukeman then
            s.cukeman = true
            game.cukemen = (game.cukemen or 0) + 1
          end
        elseif Actors.fights(s.type) then
          local dmg = Items.damage(game, 10, s.type)
          if dmg == 249 then
            -- Sprite_Func18(k, 0xE3): a fairy
            s.dead = true
            if game.spawnDrop then game:spawnDrop(0xE3, s.x, s.y) end
            game.powderFairies = (game.powderFairies or 0) + 1
          elseif dmg == 250 then
            -- Sprite_Func18(k, 0x8F)
            s.type = 0x8F
            s.hp = 0
            game.powderSlimes = (game.powderSlimes or 0) + 1
          elseif dmg > 0 then
            acts:swordHit(bx, by, bw, bh, { cls = 10, arrow = true, lower = a.lower, only = s,
                                            dmg = function(t) return Items.damage(game, 10, t) end })
          end
          game.powderHits = (game.powderHits or 0) + 1
        end
      end
    end
  end
end

local function powderFrame(game, a)
  powderHits(game, a)
  a.aux = a.aux - 1
  if a.aux < 0 then
    a.aux = 1
    if a.itl == 9 then a.gone = true return end
    a.itl = a.itl + 1
    a.arr25 = T(game).powderTab0[a.itl + a.dir * 10 + 1]
  end
end

-- ------------------------------------------------------------ the Cane of Byrna
local function radial(tb, ang, r)
  local p0, p1 = tb.rad0[ang + 1] * r, tb.rad2[ang + 1] * r
  local r0 = rshift(p0, 8) + band(rshift(p0, 7), 1)
  local r4 = rshift(p1, 8) + band(rshift(p1, 7), 1)
  return (tb.rad1[ang + 1] ~= 0) and -r0 or r0, (tb.rad3[ang + 1] ~= 0) and -r4 or r4
end
M.radial = radial

local function byrnaSpark(game)
  for _, a in ipairs(game.anc or {}) do if a.kind == "byrna" and not a.gone then return a end end
  return nil
end
M.byrnaSpark = byrnaSpark

local function addWindup(game)
  for _, a in ipairs(game.anc or {}) do if a.kind == "byrna" then a.gone = true end end
  local a = { kind = "windup", itl = 0, aux = 9, arr3 = 2, x = game.link.x, y = game.link.y, lower = lower(game) }
  game.anc = game.anc or {}
  game.anc[#game.anc + 1] = a
  game.byrnaUses = (game.byrnaUses or 0) + 1
  return a
end

local function windupFrame(game, a)
  local tb, lk = T(game), game.link
  a.aux = a.aux - 1
  if a.aux < 0 then
    a.aux = 1
    a.itl = a.itl + 1
    if a.itl == 17 then
      -- ByrnaWindupSpark_TransmuteToNormal
      a.kind = "byrna"
      local j = lk.facing * 2
      a.arr = { tb.sparkTransmute[j + 1], tb.sparkTransmute[j + 2], tb.sparkTransmute[j + 3], tb.sparkTransmute[j + 4] }
      a.aux, a.G, a.itl, a.step, a.arr1 = 0x17, 0, 0, 0, 2
      game.byrnaOn = true
      return
    end
  end
  local u = game.toolUse
  local j = (u and u.kind == "byrna") and u.t or 3
  if j == 2 then
    local v = a.arr3 - 1
    if v < 0 then v = 0; j = 3 end
    a.arr3 = v
  end
  j = j + lk.facing * 2
  a.x, a.y = lk.x + tb.sparkX[j + 1], lk.y + tb.sparkY[j + 1]
end

local function byrnaFrame(game, a, newPress)
  local tb, lk = T(game), game.link
  local function kill() a.gone = true; game.byrnaOn = nil end
  if game:yItem() ~= "byrna" then return kill() end
  a.aux = a.aux - 1
  if a.aux == 0 then
    a.aux = 1
    local r0 = M.SPARK_MAGIC[M.consumption(game) + 1] or 4
    local m = game.stats.magic or 0
    if m == 0 or m - r0 < 0 then return kill() end
    a.G = a.G - 1
    if a.G < 0 then a.G = 0x17; game.stats.magic = m - r0 end
    if newPress then return kill() end
  end
  if a.step ~= 3 then
    a.itl = a.itl + 1
    local v = a.itl
    a.step = (v >= 4) and 3 or (v == 2 and 1) or (v == 3 and 2) or 0
  end
  a.arr1 = a.arr1 - 1
  a.flags = 2
  if a.arr1 < 0 then a.arr1 = 2; a.flags = 4 end
  local cx, cy = lk.x + 8, lk.y + 12 - (lk.z or 0)
  a.pts = {}
  local TL = require("src.zelda.alttp.Tools")
  local cls = IT(game).ancDamage[0x31 + 1]
  for i = a.step, 0, -1 do
    a.arr[i + 1] = band(a.arr[i + 1] + 3, 0x3F)
    local dy, dx = radial(tb, a.arr[i + 1], 20)
    local px, py = dx + cx - 4, dy + cy - 4
    a.pts[#a.pts + 1] = { px, py, i }
    local probe = { x = px, y = py, dir = 0, lower = a.lower }
    if TL.spriteHit(game, probe, cls) then game.byrnaHits = (game.byrnaHits or 0) + 1 end
  end
end

-- ------------------------------------------------------------ the Cane of Somaria
local function somariaBlock(game)
  for _, a in ipairs(game.anc or {}) do if a.kind == "somaria" and not a.gone then return a end end
  return nil
end
M.somariaBlock = somariaBlock

local function startFission(game, a)
  a.kind, a.aux, a.itl = "fission", 3, 0
  game.somariaSwitch = 0
  game.somariaSplits = (game.somariaSplits or 0) + 1
end

local function attrAt(game, x, y) return game:ancAttr(x, y) end

-- does the room have the platform's transit tiles (OURS: dung_unk6)
local function trackRoom(game)
  local inside = game.interior
  if not inside then return false end
  if inside.i27Track == nil then
    local found = false
    for _, t in ipairs({ inside.attrs or {}, inside.attrsLo or {} }) do
      for _, v in pairs(t) do if v == 0xB6 or v == 0xBC then found = true break end end
      if found then break end
    end
    inside.i27Track = found
  end
  return inside.i27Track
end

local function platformPoof(game, a, x, y)
  a.gone = true
  M.spawnPlatform(game, x, y)
end

-- r28: team B's Floors27 owns the platforms (dung_unk6 from the room's
-- objects, the poof, Sprite_ED_SomariaPlatform); this module's own
-- platform is the fallback when Floors27's tables are not imported
local function F27(game)
  local d = game.data.t and game.data.t.d26
  if d and d.floors27 and game.interior then return require("src.zelda.alttp.Floors27") end
  return nil
end
M.F27 = F27

local function transitCheck(game, a)
  local F = F27(game)
  if F then
    if F.somariaBlockCreated(game, a.x, a.y, a.lower) then a.gone = true; game.somariaSwitch = 0; return true end
    return false
  end
  if not trackRoom(game) then return false end
  local tb = T(game)
  for j = 11, 0, -1 do
    local x, y = a.x + tb.transX[j + 1], a.y + tb.transY[j + 1]
    local at = attrAt(game, x, y)
    if at == 0xB6 or at == 0xBC then platformPoof(game, a, x, y) return true end
  end
  return false
end

local function addBlock(game)
  local tb, lk = T(game), game.link
  local j = dirIndex(lk.facing)
  local a = { kind = "somaria", G = 12, timer = 18, S = 9, step = 0, dir = j, z = 0, lower = lower(game) }
  -- Ancilla_CheckInitialTileCollision_Class2: a wall right in front -> on Link
  local fx, fy = lk.x + tb.caneX[j + 1], lk.y + tb.caneY[j + 1]
  local IT0 = IT(game)
  local cls = IT0.tileAttrs[attrAt(game, fx, fy) + 1] or 0
  if cls == 1 or cls == 2 then a.x, a.y = lk.x + 8, lk.y + 16
  else a.x, a.y = fx, fy end
  game.anc = game.anc or {}
  game.anc[#game.anc + 1] = a
  game.somariaBlocks = (game.somariaBlocks or 0) + 1
  if cls ~= 1 and cls ~= 2 then transitCheck(game, a) end
  return a
end

local function onSwitchAll(game, a)
  local n = 0
  for j = 1, 4 do
    local at = attrAt(game, a.x + M.COVER_X[j], a.y + M.COVER_Y[j])
    if at == 0x23 or at == 0x24 or at == 0x25 or at == 0x3B then n = n + 1 end
  end
  return n == 4
end

local function blockFrame(game, a)
  if a.timer > 0 then a.timer = a.timer - 1 end
  a.G = a.G - 1
  if a.G >= 0 then return end
  a.G = 0
  a.shown = true
  local tb = T(game)
  if game.interior then
    local F = F27(game)
    if F and F.caneRideRoom(game) then
      if F.somariaBlock(game, a.x, a.y, a.lower, game.frame) then a.gone = true; game.somariaSwitch = 0; return end
    elseif not F and trackRoom(game) then
      local j = band(game.frame or 0, 3)
      repeat
        local x, y = a.x + tb.blockCollX[j + 1], a.y + tb.blockCollY[j + 1]
        local at = attrAt(game, x, y)
        if at == 0xB6 or at == 0xBC then platformPoof(game, a, x, y) return end
        j = j + 4
      until j >= 12
    else
      if onSwitchAll(game, a) then game.somariaSwitch = (game.somariaSwitch or 0) + 1 else game.somariaSwitch = 0 end
    end
  end
  local at = attrAt(game, a.x, a.y)
  if at == 0x20 or (band(at, 0xF0) == 0xB0 and at ~= 0xB6 and at ~= 0xBC) then
    if a.timer == 0 then a.gone = true; game.somariaSwitch = 0; game.somariaFalls = (game.somariaFalls or 0) + 1 return end
  elseif at == 0x08 then
    if a.timer == 0 then a.gone = true; game.somariaSwitch = 0; game.somariaFalls = (game.somariaFalls or 0) + 1 return end
  elseif at ~= 0x26 and at ~= 0x0C and at ~= 0x1C and not (at >= 0x68 and at <= 0x6B) then
    a.timer = 2
  end
  -- the sprites it touches (Ancilla_CheckBasicSpriteCollision, every frame after S)
  a.S = a.S - 1
  if a.S == 0 then
    a.S = 1
    local TL = require("src.zelda.alttp.Tools")
    local cls = IT(game).ancDamage[0x2C + 1]
    local hit = TL.spriteHit(game, a, cls, { a.x - 8, a.y - 8 - (a.z or 0), 15, 15 })
    if hit and hit.type ~= 0x1E and hit.type ~= 0x90 then
      a.S = 7
      a.step = a.step + 1
      game.somariaTouches = (game.somariaTouches or 0) + 1
      if a.step == 5 then
        a.kind, a.aux, a.itl = "fizz", 0, 0
        game.somariaSwitch = 0
        game.somariaFizzles = (game.somariaFizzles or 0) + 1
      end
    end
  end
end

local function spawnBullets(game, a)
  local tb = T(game)
  local z = (a.z == 0xFF) and 0 or (a.z or 0)
  for i = 3, 0, -1 do
    local b = { kind = "sbullet", step = 4, timer = 0, dir = i, lower = a.lower, itl = 0,
                x = a.x + tb.quadX[i + 1], y = a.y - z + tb.quadY[i + 1],
                vx = tb.fireXv2[i + 1], vy = tb.fireYv2[i + 1] }
    game.anc[#game.anc + 1] = b
  end
  game.somariaBullets = (game.somariaBullets or 0) + 4
end

local function fissionFrame(game, a)
  a.aux = a.aux - 1
  if a.aux < 0 then
    a.aux = 3
    a.itl = a.itl + 1
    if a.itl == 2 then a.gone = true; spawnBullets(game, a) end
  end
end

local function fizzFrame(game, a)
  a.aux = a.aux - 1
  if a.aux < 0 then
    a.aux = 3
    a.itl = a.itl + 1
    if a.itl == 3 then a.gone = true end
  end
end

local function bulletFrame(game, a)
  local tb = T(game)
  if a.poof then
    a.poof = a.poof - 1
    if a.poof <= 0 then a.gone = true end
    return
  end
  if band(game.frame or 0, tb.blastMask[a.step + 1] or 0) == 0 then move(a) end
  if a.timer == 0 then
    a.timer = 3
    local v = a.step + 1
    if v >= 6 then v = 4 end
    a.step = v
  else
    a.timer = a.timer - 1
  end
  local TL = require("src.zelda.alttp.Tools")
  local hit = TL.spriteHit(game, a, IT(game).ancDamage[0x01 + 1])
  local IT0 = IT(game)
  local c = IT0.tileAttrs[attrAt(game, a.x + IT0.collX[a.dir + 1], a.y + IT0.collY[a.dir + 1]) + 1] or 0
  if hit or c == 1 or c == 2 then a.poof = 7 end
  local cx, cy = game:ancCamera()
  if a.x - cx >= 0xF4 or a.x - cx < -16 or a.y - cy >= 0xF0 or a.y - cy < -16 then a.gone = true end
end

-- ------------------------------------------------------------ the Somaria platform (sprite 0xED)
function M.spawnPlatform(game, x, y)
  local acts = game.actors
  if not (acts and game.interior) then return nil end
  x, y = bor(band(x, bit.bnot(7)), 4), bor(band(y, bit.bnot(7)), 4)
  local t = 0
  if band(attrAt(game, x, y - 8), 0xF0) ~= 0xB0 then
    t = 1
    if band(attrAt(game, x, y + 8), 0xF0) ~= 0xB0 then
      t = 2
      if band(attrAt(game, x - 8, y), 0xF0) ~= 0xB0 then t = 3 end
    end
  end
  local p = { type = 0xED, x = x, y = y, i27 = "platform", D = M.PLAT_POOF[t + 1], gfx = 0, noTouch = true,
              untouchable = true, hp = 255, dir = 1, t = 0, state = "idle", lower = false, npc = false, sx = 0, sy = 0 }
  acts.list[#acts.list + 1] = p
  game.somariaPlatforms = (game.somariaPlatforms or 0) + 1
  return p
end

local function held(game)
  local i = game.input
  local function d(k) return i and i.isDown and i.isDown(k) end
  return (d("right") and 1 or 0) + (d("left") and 2 or 0) + (d("down") and 4 or 0) + (d("up") and 8 or 0)
end

-- SomariaPlatform_HandleJunctions
local function junction(game, p)
  local e, D, k = p.E, p.D, held(game)
  local function pick(mask, dflt)
    local t = band(k, mask)
    if band(t, 8) ~= 0 then p.D = 0 elseif band(t, 4) ~= 0 then p.D = 1
    elseif band(t, 2) ~= 0 then p.D = 2 elseif band(t, 1) ~= 0 then p.D = 3
    elseif dflt then dflt() end
  end
  if e == 0xB2 or e == 0xB5 then p.D = bxor(D, 3)
  elseif e == 0xB3 or e == 0xB4 then p.D = bxor(D, 2)
  elseif e == 0xB6 then
    p.ai = 1
    if band(k, ({ 4, 8, 1, 2 })[D + 1]) ~= 0 then p.ai = 0; p.D = bxor(D, 1) end
  elseif e == 0xB7 then pick(({ 3, 7, 6, 5 })[D + 1], function() if D == 0 then p.D = 2 end end); p.ai = 0
  elseif e == 0xB8 then pick(({ 11, 3, 10, 9 })[D + 1], function() if D == 1 then p.D = 2 end end); p.ai = 0
  elseif e == 0xB9 then pick(({ 9, 5, 12, 13 })[D + 1], function() if D == 2 then p.D = 0 end end); p.ai = 0
  elseif e == 0xBA then pick(({ 10, 6, 14, 12 })[D + 1], function() if D == 3 then p.D = 0 end end); p.ai = 0
  elseif e == 0xBB then pick(({ 11, 7, 14, 13 })[D + 1])
  elseif e == 0xBC then
    p.ai = 1
    local t = band(k, ({ 12, 12, 3, 3 })[D + 1])
    if t ~= 0 then pick(t); p.ai = 0 end
  elseif e == 0xBE then p.ai = 0; p.D = bxor(D, 1)
  end
end

local function platMove(game, p)
  junction(game, p)
  p.vx, p.vy = M.PLAT_XV[p.D + 1], M.PLAT_YV[p.D + 1]
end

local function platformFrame(game, p)
  local lk = game.link
  if p.gfx == 0 then
    -- SomariaPlatform_LocatePath
    for _ = 1, 64 do
      local at = attrAt(game, p.x, p.y)
      p.E = at
      if at >= 0xB0 and at < 0xBF then break end
      p.x, p.y = p.x + 8, p.y + 8
    end
    p.x, p.y = band(p.x, bit.bnot(7)) + 4, band(p.y, bit.bnot(7)) + 4
    p.head = p.D
    platMove(game, p)
    p.aux4, p.gfx, p.A = 14, 1, 0
    return
  end
  if (p.aux4 or 0) > 0 then p.aux4 = p.aux4 - 1 end
  -- Sprite_CheckDamageToLink_ignore_layer: Link on it
  local Actors = require("src.zelda.alttp.Actors")
  local lx, ly, lw, lh = Actors.linkBox(lk)
  local on = Actors.overlapCart(lx, ly, lw, lh, p.x - 8, p.y - 8, 16, 16)
  if on and not game.hookUse then
    p.C = 1
    game.onPlatform = 2
    if (p.ai or 0) ~= 0 then platMove(game, p) return end
    p.A = p.A + 1
    if band(p.A, 7) == 0 then
      local at = attrAt(game, p.x, p.y)
      if at ~= p.E then
        p.E = at
        p.head = p.D
        platMove(game, p)
        -- SomariaPlatform_HandleDrag
        if band(bxor(p.D, p.head), 2) ~= 0 then
          local nx = band(p.x, bit.bnot(7)) + 4
          lk.x = lk.x + (nx - p.x); p.x = nx
          local ny = band(p.y, bit.bnot(7)) + 4
          lk.y = lk.y + (ny - p.y); p.y = ny
        end
      end
    end
    local ox, oy = p.x, p.y
    move(p)
    lk.x, lk.y = lk.x + (p.x - ox), lk.y + (p.y - oy)
    -- SomariaPlatform_DragLink: toward (x - 8, y - 16)
    local dx, dy = p.x - 8 - lk.x, p.y - 16 - lk.y
    if dx ~= 0 then lk.x = lk.x + (dx < 0 and -1 or 1) end
    if dy ~= 0 then lk.y = lk.y + (dy < 0 and -1 or 1) end
    game.platformRides = (game.platformRides or 0) + 1
  elseif p.C then
    p.C = nil
    game.onPlatform = nil
  end
end

-- ------------------------------------------------------------ the item frame
-- one frame of an item in hand; returns true while it holds Link
local function useFrame(game, u, inp)
  local lk = game.link
  local tb = T(game)
  lk.moving, lk.steps = false, 0
  if u.kind == "powder" then
    u.delay = u.delay - 1
    if u.delay >= 0 then return true end
    u.t = u.t + 1
    u.delay = tb.mushroomTimer[u.t + 1] or 0
    if u.t == 4 then addPowder(game) end
    if u.t == 9 then game.toolUse = nil end
    return true
  elseif u.kind == "net" then
    u.delay = u.delay - 1
    if u.delay < 0 then
      u.var = u.var + 1
      u.delay = 3
      u.t = tb.netTimers[dirIndex(lk.facing) * 10 + u.var + 1] or 0
      if u.var == 10 then game.toolUse = nil return true end
    end
    M.netCatch(game)
    return true
  elseif u.kind == "somaria" or u.kind == "byrna" then
    u.delay = u.delay - 1
    if u.delay >= 0 then return true end
    u.t = u.t + 1
    local dl = u.kind == "somaria" and M.ROD_DELAYS or M.BYRNA_DELAYS
    u.delay = dl[u.t + 1] or 0
    if u.t == 3 then game.toolUse = nil end
    return true
  end
  return false
end

-- the net's box (kPlayer_SetupActionHitBox t = 0 + player_oam_x/y_offset of the drawn pose)
function M.netBox(game)
  local lk, u = game.link, game.toolUse
  if not (u and u.kind == "net") then return nil end
  local cb = game.data.roomIdx.combat
  local _, _, r2 = require("src.zelda.alttp.Link").pose(game.data, lk.facing, u.t, 35)
  local ox, oy = cb.swordOamX and cb.swordOamX[(r2 or 0) + 1], cb.swordOamY and cb.swordOamY[(r2 or 0) + 1]
  if not ox or ox == -128 or oy == -128 then return nil end
  local function w8(v) v = v % 256 return v >= 128 and v - 256 or v end
  return lk.x + w8(ox), lk.y + w8(oy), 15, 15
end

local function caught(game, kind, gone)
  local msg = kind == "bee" and M.MSG_BEE or M.MSG_FAIRY
  game:showMessage(msg)
  game.onTextDone = function(g)
    if (g.lastChoice or 0) == 0 then
      local b = emptyBottle(g)
      if b then
        setInv(g, b, kind == "bee" and 7 or 6)
        gone()
        g.netCatches = (g.netCatches or 0) + 1
        return
      end
      g:showMessage(M.MSG_NOBOTTLE)
    end
  end
end

-- Sprite_CheckDamageFromLink with link_position_mode 0x10 (kCheckDamageFromPlayer_Ne)
function M.netCatch(game)
  if game.textBox then return end
  local x, y, w, h = M.netBox(game)
  if not x then return end
  local Actors = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx.combat
  local acts = actorsHere(game)
  if acts then
    for _, s in ipairs(acts.list) do
      if not s.dead and (s.type == 0x79 or s.type == 0xB2) and (s.aux4 or 0) == 0 then
        local bx, by, bw, bh = Actors.hitbox(cb, s)
        if Actors.overlapCart(x, y, w, h, bx, by - (s.z or 0), bw, bh) then
          s.aux4 = 64
          caught(game, "bee", function() s.dead = true end)
          return
        end
      end
    end
  end
  for _, d in ipairs(game.drops or {}) do
    if not d.gone and d.kind == "fairy" and (d.netWait or 0) <= (game.frame or 0) then
      local bx, by, bw, bh = Actors.hitbox(cb, { type = 0xE3, x = d.x, y = d.y })
      if Actors.overlapCart(x, y, w, h, bx, by - (d.z or 0), bw, bh) then
        d.netWait = (game.frame or 0) + 48
        caught(game, "fairy", function() d.gone = true end)
        return
      end
    end
  end
end

-- ------------------------------------------------------------ people / things
local function spawnOw(game, oa)
  local area = game.area
  if not area or game.link.world ~= "lw" then return end
  local prog = game:storyProgress()
  if prog ~= 2 and prog ~= 3 then return end
  local parent = area.parent
  local bx, by = (parent % 8) * 512, math.floor((parent % 64) / 8) * 512
  local t = game.data.t.npc
  local list = t and t.ow[prog] and t.ow[prog][parent + 1]
  if not list then return end
  for _, e in ipairs(list) do
    local typ = e[3]
    local spawn = (typ == 0xE7 and parent == M.MUSHROOM_AREA and (inv(game)[M.INV_POWDER] or 0) < 2
                   and not game.progress.gotMushroom)
               or (typ == 0x36 and parent == M.WITCH_AREA)
    if spawn then
      oa.list[#oa.list + 1] = { type = typ, x = bx + e[2] * 16, y = by + e[1] * 16, i27 = typ == 0xE7 and "mushroom" or "witch",
                                untouchable = true, noTouch = true, hp = 255, dir = 1, t = 0, state = "idle", lower = false }
    end
  end
end

local function touching(game, a, w, h)
  local Actors = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx.combat
  local bx, by, bw, bh = Actors.hitbox(cb, a)
  if w then bx, by, bw, bh = a.x, a.y, w, h end
  local lx, ly, lw, lh = Actors.linkBox(game.link)
  return Actors.overlapCart(lx, ly, lw, lh, bx, by, bw, bh)
end

-- Sprite_ShowSolicitedMessage: Link faces it within reach and presses R
local function solicited(game, a, inp)
  if not inp.a or game.textBox then return false end
  local Carry = require("src.zelda.alttp.Carry")
  local q = Carry.QUERY and Carry.QUERY[game.link.facing]
  local lk = game.link
  local px, py = lk.x + (q and q[1] or 8), lk.y + (q and q[2] or 16)
  return px >= a.x - 2 and px < a.x + 18 and py >= a.y - 2 and py < a.y + 26
end

local function owThings(game, inp)
  local oa = game.owActors
  if not oa then return false end
  for _, a in ipairs(oa.list) do
    if not a.dead and a.i27 == "mushroom" then
      if touching(game, a, 16, 16) and not game.textBox then
        a.dead = true
        game.progress.gotMushroom = true
        game:getItem(0x29)
        local rm = game.receiptMessage and game:receiptMessage(0x29)
        if rm then game:showMessage(rm) end
        game.mushroomsTaken = (game.mushroomsTaken or 0) + 1
      end
    elseif not a.dead and a.i27 == "witch" then
      local iv = inv(game)
      local m = iv[M.INV_POWDER] or 0
      local holdItem = game.input and game.input.isDown and game.input.isDown("a")
      if m == 1 and holdItem and touching(game, a, 16, 24) and select(2, game:yItem()) == 5 and not game.textBox then
        -- Witch_AcceptShroom
        setInv(game, M.INV_POWDER, 0)
        game.progress.witchShroom = true
        game:showMessage(M.MSG_WITCH.took)
        game.witchTook = (game.witchTook or 0) + 1
        return true
      elseif solicited(game, a, inp) then
        local msg = M.MSG_WITCH.none
        if m == 0 and game.progress.witchShroom then msg = M.MSG_WITCH.took
        elseif m == 1 then msg = M.MSG_WITCH.give end
        game:showMessage(msg)
        game.lastNpcMsg = msg
        return true
      end
    elseif not a.dead and a.cukeman and inp.a and not game.textBox then
      -- Sprite_Cukeman: within (x - 0x18 .. + 0x18, y - 0x20 ..) and R
      local lk = game.link
      if a.x - lk.x + 0x18 >= 0 and a.x - lk.x + 0x18 < 0x30 and lk.y - a.y + 0x20 >= 0 and lk.y - a.y + 0x20 < 0x30 then
        a.cukeTalk = (a.cukeTalk or 0) + 1
        game:showMessage(M.MSG_CUKEMAN + band(a.cukeTalk - 1, 1))
        return true
      end
    end
  end
  return false
end

local function roomEnter(game, inside, acts)
  inside, acts = inside or game.interior, acts or game.actors
  if not (inside and acts) then return end
  local hasBag = false
  for _, s in ipairs(acts.list) do if s.i27 == "bag" then hasBag = true end end
  if inside.room == M.SHOP_ROOM and not hasBag and game.progress.witchShroom and (inv(game)[M.INV_POWDER] or 0) ~= 2 then
    for _, s in ipairs(acts.list) do
      if s.type == 0xE9 and not s.i27 then
        acts.list[#acts.list + 1] = { type = 0xE9, x = s.x - 16, y = s.y, i27 = "bag", untouchable = true,
                                      noTouch = true, hp = 255, dir = 1, t = 0, state = "idle", lower = s.lower }
        game.powderBags = (game.powderBags or 0) + 1
        break
      end
    end
  end
  if inside.room == M.BAT_ROOM then
    for _, s in ipairs(acts.list) do
      if s.type == 0x3A and not s.i27 then
        s.i27, s.x, s.ai, s.untouchable, s.noTouch = "bat", s.x + 8, 0, true, true
        s.z, s.vz, s.vx, s.sx, s.sz = 0, 0, 0, 0, 0
      end
    end
  end
end

local function roomThings(game, inp)
  local acts = game.actors
  if not acts then return false end
  for _, a in ipairs(acts.list) do
    if not a.dead and a.i27 == "bag" then
      if inp.a and touching(game, a, 16, 16) and not game.textBox then
        a.dead = true
        game:getItem(0x0D)
        setInv(game, M.INV_POWDER, 2)
        local rm = game.receiptMessage and game:receiptMessage(0x0D)
        if rm then game:showMessage(rm) end
        game.powderBought = (game.powderBought or 0) + 1
        return true
      end
    elseif not a.dead and a.i27 == "platform" then
      platformFrame(game, a)
    end
  end
  return false
end

-- Sprite_3A_MagicBat (runs each room frame)
local function batFrame(game, a)
  local lk = game.link
  if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
  if (a.aux1 or 0) > 0 then a.aux1 = a.aux1 - 1 end
  -- Sprite_MoveXY / MoveZ
  a.sx = (a.sx or 0) + (a.vx or 0)
  local mx = (a.sx >= 0) and math.floor(a.sx / 16) or -math.floor(-a.sx / 16)
  a.sx = a.sx - mx * 16; a.x = a.x + mx
  a.sz = (a.sz or 0) + (a.vz or 0)
  local mz = (a.sz >= 0) and math.floor(a.sz / 16) or -math.floor(-a.sz / 16)
  a.sz = a.sz - mz * 16; a.z = (a.z or 0) + mz
  if a.ai == 0 then
    if M.consumption(game) >= 2 then return end
    if not touching(game, a, 16, 16) then return end
    for _, b in ipairs(game.anc or {}) do
      if b.kind == "powder" and not b.gone then
        a.ai, a.A, a.shown = 1, 20, true
        game.batCut = true
        game.batSummons = (game.batSummons or 0) + 1
        return
      end
    end
  elseif a.ai == 1 then
    if (a.delay or 0) == 0 then
      a.A = a.A - 1
      a.delay = a.A
      if a.delay ~= 1 then
        a.vz = rshift(a.delay, 2)
        a.vx = (a.vx or 0) + ((band(a.A, 1) == 0) and -8 or 7)
        a.gfx = bxor(a.gfx or 0, 1)
      else
        game:showMessage(M.MSG_BAT[1])
        a.ai, a.gfx, a.vz, a.vx, a.delay = 2, 0, 0, 0, 255
      end
    end
  elseif a.ai == 2 then
    if (a.delay or 0) == 0 then a.ai = 3; a.aux1 = 64 end
  elseif a.ai == 3 then
    if (a.aux1 or 0) == 0 then
      game:showMessage(M.MSG_BAT[2])
      a.ai = 4
      setInv(game, M.INV_CONSUMPTION, 1)
      game.batBlessings = (game.batBlessings or 0) + 1
    end
  elseif a.ai == 4 and not game.textBox then
    a.dead = true
    game.batCut = nil
  end
end

-- ------------------------------------------------------------ install
function M.install(G)
  local Items = require("src.zelda.alttp.Items")
  for s, n in pairs(M.SLOTS) do Items.SLOT[s] = n end
  local TL = require("src.zelda.alttp.Tools")
  -- every item's magic goes through link_magic_consumption
  TL.magic = function(game, i) return M.magic(game, i) end

  local itemFrame0 = G.itemFrame
  function G:itemFrame(inp)
    if not T(self) then return itemFrame0(self, inp) end
    if self.batCut then self.link.moving = false; return true end
    -- the people / things that answer R or the item button
    if self.interior then
      if roomThings(self, inp) then return true end
    elseif self.state == "play" then
      if owThings(self, inp) then return true end
    end
    -- the byrna spark ends on a new press of the item button
    local spark = byrnaSpark(self)
    if spark and self.byrnaPress == nil then self.byrnaPress = inp.y and true or false end
    local u = self.toolUse
    if u and (u.kind == "powder" or u.kind == "net" or u.kind == "somaria" or u.kind == "byrna") then
      return useFrame(self, u, inp)
    end
    if inp.y and not self.bowUse and not u and (self.link.doorway or 0) == 0 and not self.carry then
      local item = self:yItem()
      local lk = self.link
      if item == "powder" then
        if (inv(self)[M.INV_POWDER] or 0) ~= 2 then return false end
        if not M.magic(self, 2) then return false end
        self.toolUse = { kind = "powder", t = 0, delay = T(self).mushroomTimer[1], hand = 0x40 }
        lk.steps = 0
        return true
      elseif item == "net" then
        self.toolUse = { kind = "net", var = 0, delay = 3, t = T(self).netTimers[dirIndex(lk.facing) * 10 + 1], mode = 0x10 }
        self.netSwings = (self.netSwings or 0) + 1
        lk.steps = 0
        return true
      elseif item == "somaria" then
        if (self.onPlatform or 0) ~= 0 then return false end
        local b = somariaBlock(self)
        if b then
          startFission(self, b)
        else
          if not M.magic(self, 4) then return false end
          addBlock(self)
        end
        self.toolUse = { kind = "somaria", t = 0, delay = M.ROD_DELAYS[1], mode = 8 }
        lk.steps = 0
        return true
      elseif item == "byrna" then
        if spark then return false end
        if not M.magic(self, 8) then return false end
        addWindup(self)
        self.toolUse = { kind = "byrna", t = 0, delay = M.BYRNA_DELAYS[1], mode = 8 }
        lk.steps = 0
        return true
      end
    end
    return itemFrame0(self, inp)
  end

  local updAnc0 = G.updateAncillae
  function G:updateAncillae()
    updAnc0(self)
    local l = self.anc
    local press = self.byrnaPress
    self.byrnaPress = nil
    if self.interior and self.actors then
      for _, a in ipairs(self.actors.list) do
        if a.i27 == "bat" and not a.dead then batFrame(self, a) end
      end
    end
    if not l or #l == 0 or not T(self) then if self.byrnaOn and not byrnaSpark(self) then self.byrnaOn = nil end return end
    local keep = {}
    local n = #l
    for i = 1, n do
      local a = l[i]
      if a.kind == "powder" then powderFrame(self, a)
      elseif a.kind == "windup" then windupFrame(self, a)
      elseif a.kind == "byrna" then byrnaFrame(self, a, press)
      elseif a.kind == "somaria" then blockFrame(self, a)
      elseif a.kind == "fission" then fissionFrame(self, a)
      elseif a.kind == "fizz" then fizzFrame(self, a)
      elseif a.kind == "sbullet" then bulletFrame(self, a)
      end
    end
    for _, a in ipairs(self.anc) do if not a.gone then keep[#keep + 1] = a end end
    self.anc = keep
    if self.byrnaOn and not byrnaSpark(self) then self.byrnaOn = nil end
  end

  -- link_disable_sprite_damage under the Byrna sparks
  local hurt0 = G.hurtLink
  function G:hurtLink(dmg, fx, fy)
    if T(self) and (byrnaSpark(self) or (function()
      for _, a in ipairs(self.anc or {}) do if a.kind == "windup" and not a.gone then return true end end
      return false end)()) then
      self.byrnaBlocked = (self.byrnaBlocked or 0) + 1
      return
    end
    return hurt0(self, dmg, fx, fy)
  end

  -- poses: kPlayerOam_Tab2[link_item_in_hand 0x40] = 8, Tab3[position mode 8 / 0x10] = 34 / 35
  local pose0 = G.linkPose
  function G:linkPose()
    local u = self.toolUse
    if u then
      if u.kind == "powder" then return 8, u.t end
      if u.kind == "net" then return 35, u.t end
      if u.kind == "somaria" or u.kind == "byrna" then return 34, u.t end
    end
    return pose0(self)
  end

  local drawAnc0 = G.drawAncillae
  function G:drawAncillae(cx, cy, spr)
    drawAnc0(self, cx, cy, spr)
    if T(self) and spr and self.anc then M.draw(self, cx, cy, spr) end
  end

  -- a room change ends a use, sets up the room's things
  local enter0 = G.enterRoom
  function G:enterRoom(e)
    local u = self.toolUse
    if u and (u.kind == "powder" or u.kind == "net" or u.kind == "somaria" or u.kind == "byrna") then self.toolUse = nil end
    self.somariaSwitch, self.onPlatform, self.batCut = 0, nil, nil
    local r = enter0(self, e)
    if T(self) then roomEnter(self) end
    return r
  end
  -- r28: the room's sprites are loaded by Actors:enterRoom (after the
  -- entrance and on every room-to-room move): the things are set up there
  local Actors = require("src.zelda.alttp.Actors")
  local aer0 = Actors.enterRoom
  function Actors:enterRoom(inside)
    local r = aer0(self, inside)
    if self.game and T(self.game) and self.game.actors == self then roomEnter(self.game, inside, self) end
    return r
  end

  -- the overworld's mushroom and witch (after the people's / enemies' loading)
  local updOw = G.updateOwActors
  function G:updateOwActors()
    local r = updOw(self)
    if T(self) and self.state == "play" and self.area and self.data.t.npc then
      local oa = self.owActors
      local key = self.area.parent .. ":" .. self.link.world
      if oa and oa.i27Key ~= key then
        oa.i27Key = key
        spawnOw(self, oa)
      end
    end
    return r
  end

  -- the Somaria block holds the room's floor switch
  -- (RoomTag_CheckForPressedSwitch: dung_flag_somaria_block_switch)
  local Palace = require("src.zelda.alttp.Palace")
  local tags0 = Palace.roomTags
  function Palace.roomTags(acts, lk)
    local game = acts.game
    local b = game and (game.somariaSwitch or 0) > 0 and somariaBlock(game)
    if b then
      game.somariaPresses = (game.somariaPresses or 0) + 1
      return tags0(acts, { x = b.x - 7, y = b.y - 22, facing = lk.facing })
    end
    return tags0(acts, lk)
  end

  -- drawing the module's sprites
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    if a.i27 then return M.drawThing(self, a, x, y, frame) end
    return da0(self, a, x, y, frame, room)
  end
end

-- ------------------------------------------------------------ drawing
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

function M.draw(game, cx, cy, spr)
  local tb = T(game)
  for _, a in ipairs(game.anc) do
    local x, y = a.x - cx, a.y - cy
    if a.kind == "powder" then
      local b = a.arr25 or 0
      for i = 0, 3 do
        stripChar(game, spr, tb.powderChar[b + 1], 80, x + tb.powderDrawX[b * 4 + i + 1], y + tb.powderDrawY[b * 4 + i + 1],
                  band(tb.powderFlags[b * 4 + i + 1], bit.bnot(0x30)))
      end
    elseif a.kind == "windup" and a.itl > 0 then
      local v = band(a.itl - 1, 0xF)
      local j = 0
      if v ~= 0 then j = 4 * ((v ~= 15) and (band(v, 1) + 1) or 3) end
      for _ = 0, 3 do
        local ch = tb.sparkDrawChar[j + 1]
        if ch ~= 0xFF then
          spr:oam(x + tb.sparkDrawX[j + 1], y + tb.sparkDrawY[j + 1], ch, band(tb.sparkDrawFlags[j + 1], bit.bnot(0x30)), 0)
        end
        j = j + 1
      end
    elseif a.kind == "byrna" and a.pts then
      for _, p in ipairs(a.pts) do spr:oam(p[1] - cx, p[2] - cy, tb.sparkChar[p[3] + 1], a.flags or 2, 0) end
    elseif a.kind == "somaria" and a.shown then
      for j = 0, 3 do
        spr:oam(x + tb.blockDrawX[j + 1], y + tb.blockDrawY[j + 1] - (a.z or 0), M.BLOCK_CHAR, bor(M.BLOCK_FLAGS[j + 1], 2), 0)
      end
    elseif a.kind == "fission" then
      local j = a.itl * 8
      for i = 0, 7 do
        local k = j + i
        if k < 16 then
          spr:oam(x + tb.divX[k + 1], y + tb.divY[k + 1] - (a.z or 0), tb.divChar[k + 1], band(tb.divFlags[k + 1], bit.bnot(0x30)), 0)
        end
      end
    elseif a.kind == "fizz" then
      local j = a.itl * 2
      for i = 0, 1 do
        local k = j + i
        if k < 6 and tb.fizzChar[k + 1] ~= 0xFF then
          spr:oam(x + tb.fizzX[k + 1], y + tb.fizzY[k + 1], tb.fizzChar[k + 1], band(tb.fizzFlags[k + 1], bit.bnot(0x30)), 0)
        end
      end
    elseif a.kind == "sbullet" and not a.poof then
      local j = a.dir * 6 + a.step
      local f = M.BLAST_FLAGS[1]
      if band(tb.blastY0[j + 1], 0x80) == 0 then
        spr:oam(x + tb.blastX0[j + 1], y + tb.blastY0[j + 1], tb.blastChar0[j + 1], bor(f, tb.blastFlags0[j + 1]), 0)
      end
      if band(tb.blastY1[j + 1], 0x80) == 0 then
        spr:oam(x + tb.blastX1[j + 1], y + tb.blastY1[j + 1], tb.blastChar1[j + 1], bor(f, tb.blastFlags1[j + 1]), 0)
      end
    end
  end
end

-- the overworld / room sprites of this module
function M.drawThing(spr, a, x, y, frame)
  local info = spr.info
  local f = band(info.flags3[a.type + 1] or 0, 0x0F)
  if a.i27 == "mushroom" then
    spr:single(a, x, y, 0, bor(8, (math.floor((frame or 0) / 32) % 2 == 1) and 0x40 or 0))
  elseif a.i27 == "witch" then
    -- Witch_Draw (the disassembly's tables; sprite_graphics = frame >> (A + 1) & 7, A = 2)
    local g = band(rshift(frame or 0, 3), 7) * 2
    for i = 0, 1 do
      local e = M.WITCH_A[g + i + 1]
      spr:oam(x + e[1], y + e[2], M.conv(e[3]), f, 0)
    end
    for i = 1, 3 do
      local e = M.WITCH_B[i]
      spr:oam(x + e[1], y + e[2], M.conv(e[3]), bxor(f, e[4]), 2)
    end
    local i = (g - 6 >= 0 and g - 6 < 6) and 2 or 1
    local e = M.WITCH_C[i]
    spr:oam(x + e[1], y + e[2], M.conv(e[3]), f, 2)
  elseif a.i27 == "bag" then
    spr:oam(x, y, M.conv(0xE6), bxor(0x04, f), 2)
  elseif a.i27 == "bat" then
    if (a.ai or 0) ~= 0 then spr:single(a, x, y - (a.z or 0), a.gfx or 0) end
  elseif a.i27 == "platform" then
    local j = band(a.aux4 or 0, 12)
    for i = 0, 3 do
      local e = M.PLAT_DMD[j + i + 1]
      spr:oam(x + e[1] + 8, y + e[2] + 8, M.conv(0xAC), bor(e[3], f), 2)
    end
  else
    return false
  end
  return true
end

return M
