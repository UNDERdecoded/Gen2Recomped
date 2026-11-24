-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LAST SOLID-BUT-INVISIBLE SPRITES (round 31). Round 30's scan of every
-- entrance's room listed sprites drawActor did not draw; these were left:
--
--   0x72 the ponds (GBA routine 0x080DF44C). The pond itself draws nothing
--        on the cartridge (WishPond2_Draw only shows the thrown item); the
--        fairy it spawns does: FaerieQueen_Draw -- Light World by the GBA's
--        X / Y / char / flags / big tables (0x176748 / 0x176760 / 0x176778 /
--        0x176790 / 0x1767A8, 12 OAMs a frame, frame = frame_counter >> 4 &
--        1), Dark World by its kFaerieQueen_Dmd copy (0x1766A8, 10 a frame);
--        every 16 frames a sparkle (0x72 with A = C = 31: SingleSmall,
--        graphics C >> 3) at + kWishPond_X / Y (0x1765BC / 0x1765C4).
--        FatFairy.lua runs 0x114 / 0x116 (a.fairy); room 0x115 (low byte
--        0x15) runs the happiness pond, table 0x1765CC, ported here
--        (Sprite_HappinessPond): contact 0x89 -> "throw Rupees?" -> the
--        costs by upgrades (0x176688 hex / 0x17668C: 5 20 25 50) -> paid
--        into the pond (+ link_rupees_in_pond); 100 -> the fairy (80 px
--        above), 0x95 -> bombs (0x96: link_bomb_upgrades + 1) or arrows
--        (0x97), at the top 0x98 (100 Rupees back); under 100: 0x94 and the
--        luck (0x176698 {1, 0, 0, 2}, messages 0x176690).
--   0xC8 the fountain fairy (Sprite_C8_BigFairy, 0x080DDAA8): kBigFaerie_Dmd
--        (0x1762C8, graphics + 1 & 3 every 6 frames), shadow; Link within
--        0x30 -> 0x15A, Link held, the cloud (C8 with head_dir 1) homes in at
--        speed 8, + 0xA0 hearts filler, full -> it grows away (A * 2 + 1
--        every 16 frames) and Link is freed. The SNES sets delay_aux2 of
--        SLOT 0 (a zelda3-noted bug): the fairy is slot 0 in all three
--        fountains, so she blinks away after the healing -- kept.
--   0xB2 the good bee (Sprite_B2_PlayerBee state 0 in room 0x120): it dies
--        at once and, unless a bottle holds a good bee (8), becomes a bee
--        0x79 with head_dir 1 (GoldBee_SpawnSelf: delay 64, A 64, aux4 96,
--        speeds from kSpawnBee_InitVel 0x174A28); netted -> bottle 8
--        (Bee_PutInBottle: 7 + head_dir; Items27 "goldbee").
--   0xE9 the potion shop (Sprite_E9_PotionShop): subtype 0 the assistant
--        (Shopkeeper_Draw, kShopkeeper_Dmd 0x17D2C4; 0x4E with a bottle,
--        else 0x4D; after talking hearts filled), SpritePrep_PotionShop's
--        cauldrons (subtypes 2 / 3 / 4 at (-40, -72) / (+8, -72) /
--        (-88, -72); kGreen / Blue / RedPotionItem_Dmd 0x17D328 / 0x17D340
--        / 0x17D360): no bottle -> 0x4F on contact; R touching -> 60 / 160 /
--        120 Rupees (0x17C) and an empty bottle (0x50) -> receipt 0x2F /
--        0x30 / 0x2E, delay 64. Subtype 1 (the powder bag) stays Items27's.
--   0x33 the rupee pull (Sprite_33_RupeePull, room 0x101): draws nothing;
--        touching it sets link_need_for_pullforrupees_sprite, R facing up
--        is the pull (action 7); then RupeePull_SpawnPrize: with any kills
--        since the last pull, four rupees (0x174D30: x vel -18 -12 12 18,
--        y vel 16 24 24 16, kinds 0xD9 / 0xDA / 0xDB by kills < 4 / hurt /
--        not hurt), z vel 32; the counters are cleared.
--   0xF3 / 0xF5 / 0xF7 the GBA's own sprites (routines 0x0811130C /
--        0x08111BB8 / 0x081142B4, prep table 0x17451C; their init flags
--        are past zelda3's 243: flags3 0x22788F + t, flags4 0x227988 + t):
--        0xF3 (Link's house, 0x104): SpritePrep 0x081115C0 kills itself and
--          puts up to three carvings (the riddle prizes) at + 0x17D590 by
--          the riddle count (+0x16B5 > 1 / > 4 / > 7), drawn by
--          0x17D5EC's entries (dmd, count, palette). Nothing at count 0.
--        0xF5 (room 0x88, the Palace of the Four Sword's door keeper):
--          barrier; 0 solicited 0x101 (GBA numbers; ours = n - 3) -> 1:
--          "don't" or < 20 Rupees -> 0x103; paid 20 -> with the Four Swords
--          flags (0x020023EC ~= 0xFFFF and 0x03000008 & 0xF0) 0x1A9 and
--          state 2 (he leaves: sprite_state 0), else 0x1A8.
--        0xF7 (room 0x11F, the riddle carver): barrier; SpritePrep
--          0x081140B8 picks the state from the riddle count / basket
--          (+0x16B5 / +0x16B4), the bug net (0x0200232F) and the Four Swords
--          flag (0x03000008 & 0x0F); states 0x17D8D0: 0 0x1AB; 1 0x1AC; 2
--          choice -> 0x1AD / 0x1AE (the basket, receipt 0x52, riddle 1);
--          4 0x1AF; 5 / 6 the riddle (0x17D900 [riddle]); 7 0x1B4 (wrong,
--          basket emptied); 8 0x1B2 (the last); 9 0x1B0 / 0x1B1 (right, +1);
--          10 receipt 0x53 + sword (0x57 without); 11 0x1B3.
--
-- OURS: the Four Swords save flags are progress.fsCleared (the GBA's link
-- with the Four Swords save is not ported), so the door keeper and the
-- carver stay in their first state in a normal game; the riddle answers
-- (netting into the basket, messages 0x1BD..) are not ported
-- (progress.riddleBasket is the hook); the happiness pond's {number} words
-- are not printed; the hearts filler adds 1 health a frame; no sound, no
-- palette filter, the cloud's / fairy's sparkle garnish is not drawn (the
-- pond fairy's sparkles are).

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = {}
-- r36: messages and the cauldron's prices read at import from the cartridge
-- (RomTablesSpec "msg.spr31", "msg.fairy", "msg.shop", "spr31.cauldronRows")
local RT = require("src.zelda.alttp.RomTables")
local MSGS = RT.get("msg.spr31")
local M37 = RT.get("msg.spr37")    -- r37: the other calls (SNES numbers)
local I37 = RT.get("msg.imm37")

M.OFF = {
  fqX = 0x176748, fqY = 0x176760, fqChar = 0x176778, fqFlags = 0x176790, fqBig = 0x1767A8,
  fqDmd = { 0x1766A8, 20 }, wishX = 0x1765BC, wishY = 0x1765C4,
  pondCostHex = 0x176688, pondCost = 0x17668C, luckMsg = 0x176690, luck = 0x176698,
  bigFairy = { 0x1762C8, 16 }, beeVel = 0x174A28,
  shop = { 0x17D2C4, 4 }, green = { 0x17D328, 3 }, blue = { 0x17D340, 4 }, red = { 0x17D360, 4 },
  f3Tab = 0x17D5EC, f3Offs = 0x17D590, f5 = { 0x17D690, 2 }, f7 = { 0x17D8C0, 2 }, riddles = 0x17D900,
  flags3 = 0x22788F, flags4 = 0x227988, rupeePull = 0x174D30,
}
M.GBA_TYPES = { 0xF3, 0xF5, 0xF7 }

local function dmd(rom, spec)
  local t = {}
  for i = 0, spec[2] - 1 do
    local p = spec[1] + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end
local function s8(t) for i, v in ipairs(t) do if v >= 128 then t[i] = v - 256 end end return t end

function M.extract(rom, R, check)
  local O = M.OFF
  local t = { dmd = {} }
  for _, k in ipairs({ "fqDmd", "bigFairy", "shop", "green", "blue", "red", "f5", "f7" }) do t.dmd[k] = dmd(rom, O[k]) end
  t.fqX, t.fqY = rom:bytesU8(O.fqX, 24), rom:bytesU8(O.fqY, 24)
  t.fqChar, t.fqFlags, t.fqBig = rom:bytesU8(O.fqChar, 24), rom:bytesU8(O.fqFlags, 24), rom:bytesU8(O.fqBig, 24)
  t.wishX, t.wishY = rom:bytesU8(O.wishX, 8), rom:bytesU8(O.wishY, 8)
  t.pondCost, t.luck = rom:bytesU8(O.pondCost, 4), rom:bytesU8(O.luck, 4)
  t.luckMsg = rom:bytesU16(O.luckMsg, 4)
  t.beeVel = s8(rom:bytesU8(O.beeVel, 8))
  -- 0xF3's carvings: 9 entries (dmd pointer, count, palette)
  t.f3 = {}
  for i = 0, 8 do
    local p = O.f3Tab + i * 12
    local n = rom:u32(p + 4)
    t.f3[i + 1] = { dmd = dmd(rom, { rom:u32(p) - 0x08000000, n }), n = n, pal = rom:u8(p + 8) }
  end
  t.f3Offs = {}
  for i = 0, 2 do t.f3Offs[i + 1] = { rom:u16(O.f3Offs + i * 4), rom:u16(O.f3Offs + i * 4 + 2) } end
  t.riddles = rom:bytesU16(O.riddles, 12)
  local rp = rom:bytesU8(O.rupeePull, 11)
  t.pullXv, t.pullYv, t.pullType = s8({ rp[1], rp[2], rp[3], rp[4] }), { rp[5], rp[6], rp[7], rp[8] }, { rp[9], rp[10], rp[11] }
  t.flags3, t.flags4 = {}, {}
  for _, ty in ipairs(M.GBA_TYPES) do
    t.flags3[ty], t.flags4[ty] = rom:u8(O.flags3 + ty), rom:u8(O.flags4 + ty)
  end
  check(t.fqX[2] == 16 and t.fqY[3] == 16 and t.fqBig[1] == 2 and t.dmd.bigFairy[2][4] == 0x40
        and t.pondCost[4] == 50 and t.luck[4] == 2 and t.luckMsg[1] == 0x153 and t.beeVel[4] == -15
        and t.wishY[8] == 36 and t.dmd.shop[4][4] == 0x4C and t.riddles[2] == 0x1B6
        and t.f3[2].n == 2 and t.f3Offs[3][1] == 32 and t.flags4[0xF7] == 7
        and t.pullXv[1] == -18 and t.pullType[3] == 0xDB, "round 31 sprite tables")
  return t
end

local function T(game) return game.data.t and game.data.t.spr31 end
M.tabs = T

-- ------------------------------------------------------------ helpers
local function gbaMsg(game, n) return game:showMessage(require("src.zelda.alttp.Text").bmgIndex(n)) end
local function inv(game) return require("src.zelda.alttp.Menu").inventory(game) end
local function bottleWith(game, f)
  local iv = inv(game)
  for _, k in ipairs(require("src.zelda.alttp.Items27").BOTTLES) do if f(iv[k] or 0) then return k end end
  return nil
end
local function rng(a)
  a.seed = band((a.seed or (a.x * 31 + a.y + 7)) * 1103515245 + 12345, 0x7FFFFFFF)
  return band(rshift(a.seed, 16), 255)
end
local function busy(game)
  return game.textBox or game.carry or game.swing or game.dash or game.recoil or game.holdItem or game.receipt
end
local function touching(actors, a) return require("src.zelda.alttp.Desert").touching(actors, a, actors.game.link) end
-- the point in front of Link within 4 px of the hit box (Townsfolk30's rule
-- for "touching + facing" against a barrier)
local function facingNear(game, a)
  local C = require("src.zelda.alttp.Carry")
  local A = require("src.zelda.alttp.Actors")
  local q = C.QUERY[game.link.facing]
  local px, py = game.link.x + q[1], game.link.y + q[2]
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  local hx, hy, hw, hh = a.x, a.y, 16, 16
  if cb then hx, hy, hw, hh = A.hitbox(cb, a) end
  return px >= hx - 4 and px < hx + hw + 4 and py >= hy - 4 and py < hy + hh + 4
end
M.facingNear = facingNear
function M.give(game, id, after)
  game:getItem(id)
  game.holdItem = { item = id, t = 0 }
  local rm = game.receiptMessage and game:receiptMessage(id)
  local function done(g) g.holdItem = nil; if after then after(g) end end
  if rm and game:showMessage(rm) then game.onTextDone = done else done(game) end
end
local function riddle(game)
  local p = game.progress
  p.riddle = p.riddle or { n = 0, basket = 0 }
  return p.riddle
end
M.riddle = riddle

-- the GBA's init flags of its own sprites (zelda3's tables stop at 0xF2)
local function patchTables(game, tb)
  if game.s31Patched then return end
  game.s31Patched = true
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  local info = game.data.sprInfo
  for ty, v in pairs(tb.flags4) do if cb and cb.flags4 and cb.flags4[ty + 1] == nil then cb.flags4[ty + 1] = v end end
  for ty, v in pairs(tb.flags3) do if info and info.flags3 and info.flags3[ty + 1] == nil then info.flags3[ty + 1] = v end end
end

-- ------------------------------------------------------------ prep
local function spawn(actors, a, fields)
  local b = { type = a.type, x = a.x, y = a.y, lower = a.lower, t = 0, index = -1, dir = 1, hp = 255, state = "idle",
              s31 = true, ai = 0, gfx = 0, delay = 0 }
  for k, v in pairs(fields) do b[k] = v end
  actors.list[#actors.list + 1] = b
  return b
end

function M.prep(actors, a)
  local game = actors.game
  local tb = T(game)
  a.s31, a.ai, a.gfx, a.delay = true, a.ai or 0, a.gfx or 0, a.delay or 0
  local t = a.type
  if t == 0xB2 then
    -- Sprite_B2_PlayerBee state 0 (sprite_E 0: the room's own bee)
    a.dead = true
    if not bottleWith(game, function(v) return v == 8 end) then
      local b = actors:spawnSecret(0x79, a.x, a.y, a.lower)
      b.golden, b.headDir = true, 1
      b.delay, b.A, b.aux4 = 64, 64, 96
      b.vx, b.vy = tb.beeVel[band(rng(a), 7) + 1], tb.beeVel[band(rng(a), 7) + 1]
      b.flip = b.vx >= 0
      game.goldBees = (game.goldBees or 0) + 1
    end
  elseif t == 0xE9 and not a.sub31 and not a.i27 then
    -- SpritePrep_PotionShop: the three cauldrons
    a.sub31 = 0
    spawn(actors, a, { x = a.x - 40, y = a.y - 72, sub31 = 2 })
    spawn(actors, a, { x = a.x + 8, y = a.y - 72, sub31 = 3 })
    spawn(actors, a, { x = a.x - 88, y = a.y - 72, sub31 = 4 })
  elseif t == 0xF3 and not a.carving then
    a.dead = true    -- SpritePrep 0x081115C0: sprite_state 0
    local n = riddle(game).n or 0
    for i, lim in ipairs({ 1, 4, 7 }) do
      if n > lim then
        local o = tb.f3Offs[i]
        spawn(actors, a, { x = a.x + o[1], y = a.y + o[2], carving = i - 1, ai = i - 1 })
      end
    end
  elseif t == 0xF7 then
    -- SpritePrep 0x081140B8
    local r = riddle(game)
    local p = game.progress
    local net = (inv(game)[0x2F] or 0) ~= 0
    if r.n == 11 then a.ai = 11
    elseif not (net and p.fsCleared) then a.ai = 0
    elseif r.n == 0 then a.ai = 1
    elseif (r.basket or 0) <= 1 then a.ai = 6
    elseif r.basket - 2 ~= r.n - 1 then a.ai = 7
    elseif r.n == 10 then a.ai = 8
    else a.ai = 9 end
  elseif t == 0x72 and actors.room == 0x115 and not a.fairyOf then
    a.pond = true
  elseif t == 0xC8 and not a.cloud then
    a.G = 0
  end
end

-- ------------------------------------------------------------ the happiness pond (room 0x115)
local function pondFairy(actors, a, dy)
  local f = spawn(actors, a, { y = a.y + dy, fairyOf = a, queen = true })
  a.fairyKid = f
  return f
end

local function happiness(actors, a)
  local game = actors.game
  local tb = T(game)
  local st, p = game.stats, game.progress
  if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
  local ai = a.ai
  if ai == 0 then
    game.s31Hold = nil
    if a.delay > 0 or busy(game) then return end
    if touching(actors, a) then
      game:showMessage(M37.happiness)
      a.ai = 1
      game.link.facing = 0
    end
  elseif ai == 1 then
    if (game.lastChoice or 0) == 0 then
      local i = ((st.bombLevel or 0) + (st.arrowLevel or 0)) ~= 0 and 1 or 0
      a.gfx = i * 2
      game:showMessage(M37.pondCost)
      a.ai = 2
      game.s31Hold = true
    else
      game:showMessage(MSGS.pond)
      a.ai, a.delay = 0, 255
    end
  elseif ai == 2 then
    local i = a.gfx + (game.lastChoice or 0)
    local cost = tb.pondCost[i + 1] or 5
    if (st.rupees or 0) < cost then
      game:showMessage(MSGS.pond)
      a.ai, a.delay = 0, 255
    else
      a.D, a.ai = cost, 3
    end
  elseif ai == 3 then
    a.delay = 80
    st.rupees = st.rupees - a.D
    p.pondRupees = (p.pondRupees or 0) + a.D
    game.pondPaid = (game.pondPaid or 0) + a.D
    if p.pondRupees >= 100 then
      p.pondRupees = p.pondRupees - 100
      a.ai = 5
    else
      a.ai = 4
    end
  elseif ai == 4 then
    if a.delay == 0 then game:showMessage(MSGS.pondUnder); a.ai = 13 end
  elseif ai == 5 then
    if a.delay == 0 then
      pondFairy(actors, a, -80)
      a.filter, a.ai, a.delay = 0x1F, 6, 255
    end
  elseif ai == 6 then
    if band(game.frame or 0, 7) == 0 then
      a.filter = math.max(0, a.filter - 1)
      if a.filter == 0 then game:showMessage(MSGS.pondUpgrade); a.ai = 7 end
    end
  elseif ai == 7 then
    a.ai = ((game.lastChoice or 0) == 0) and 8 or 12
  elseif ai == 8 or ai == 12 then
    local key = ai == 8 and "bombLevel" or "arrowLevel"
    local n = (st[key] or 0) + 1
    if n ~= 8 then
      st[key] = n
      local ui = game.data.t and game.data.t.ui
      local maxT = ui and (ai == 8 and ui.maxBombs or ui.maxArrows)
      if maxT then
        if ai == 8 then st.bombs = maxT[n + 1] else st.arrows = maxT[n + 1] end
      end
      game:showMessage(ai == 8 and 0x96 or 0x97)
    else
      st.rupees = (st.rupees or 0) + 100
      game:showMessage(MSGS.pondBack)
    end
    game.pondUpgrades = (game.pondUpgrades or 0) + 1
    a.ai = 9
  elseif ai == 9 then
    a.ai, a.filter = 10, 0x1F
  elseif ai == 10 then
    if band(game.frame or 0, 7) == 0 then
      a.filter = math.max(0, a.filter - 1)
      if a.filter == 30 and a.fairyKid then a.fairyKid.dead = true; a.fairyKid = nil
      elseif a.filter == 0 then a.ai = 11 end
    end
  elseif ai == 11 then
    a.ai, a.delay = 0, 255
  elseif ai == 13 then
    local i = band(rng(a), 3)
    p.itemLuck = tb.luck[i + 1]
    gbaMsg(game, tb.luckMsg[i + 1])
    a.ai, a.delay = 0, 255
  end
end

-- the fairy's sparkles (Sprite_72_FairyPond with B: every 16 frames)
local function queen(actors, a)
  local game = actors.game
  local tb = T(game)
  a.qgfx = band(rshift(game.frame or 0, 4), 1)   -- (FatFairy's a.gfx is the thrown item)
  a.sparks = a.sparks or {}
  for i = #a.sparks, 1, -1 do
    local s = a.sparks[i]
    s.c = s.c - 1
    if s.c <= 0 then table.remove(a.sparks, i) end
  end
  if band(game.frame or 0, 15) == 0 then
    a.sparks[#a.sparks + 1] = { x = tb.wishX[band(rng(a), 7) + 1], y = tb.wishY[band(rng(a), 7) + 1], c = 31 }
  end
end

-- ------------------------------------------------------------ the fountain fairy
local function bigFairy(actors, a)
  local game = actors.game
  local lk = game.link
  if a.cloud then
    a.sub2 = (a.sub2 or 0) + 1
    if a.ai == 0 then
      a.A = 0
      local A = require("src.zelda.alttp.Actors")
      local vx, vy = A.project(a.x, a.y, lk.x, lk.y + 8, 8)   -- (Sprite_IsBelowLink: link_y + 8)
      a.fx, a.fy = (a.fx or 0) + vx, (a.fy or 0) + vy
      local mx, my = math.floor(a.fx / 16), math.floor(a.fy / 16)
      a.x, a.y, a.fx, a.fy = a.x + mx, a.y + my, a.fx - mx * 16, a.fy - my * 16
      if lk.x - a.x + 3 >= 0 and lk.x - a.x + 3 < 6 and lk.y - a.y + 11 >= 0 and lk.y - a.y + 11 < 6 then
        game.s31Fill = (game.s31Fill or 0) + 0xA0
        a.ai = 1
      end
    elseif a.ai == 1 then
      if game.stats.health >= game.stats.healthMax then
        a.ai = 2
        if a.parent then a.parent.aux2 = 112 end   -- (slot 0's delay_aux2: the fairy herself)
      end
    elseif a.ai == 2 then
      if band(a.sub2, 15) ~= 0 or (a.A or 0) >= 0x80 then return end
      a.A = a.A * 2 + 1
      if a.A >= 0x80 then
        a.A = 255
        game.s31Hold = nil
        a.dead = true
        game.fairyHeals = (game.fairyHeals or 0) + 1
      end
    end
    return
  end
  local i = a.aux2 or 0
  if i ~= 0 then
    a.aux2 = i - 1
    if i - 1 < 0x40 then
      if i - 1 == 0 then a.dead = true end
      a.blink = band(i - 1, 1) == 1
    end
  end
  a.G = (a.G or 0) - 1
  if a.G < 0 then a.G, a.gfx = 5, band((a.gfx or 0) + 1, 3) end
  a.sub2 = (a.sub2 or 0) + 1
  if a.ai == 0 then
    local dx, dy = lk.x - a.x, lk.y - a.y
    if dx + 0x30 >= 0 and dx + 0x30 < 0x60 and dy + 0x30 >= 0 and dy + 0x30 < 0x60 and not game.textBox then
      game.dash = nil
      a.ai = 1
      game:showMessage(M37.cloud)
      game.s31Hold = true
      spawn(actors, a, { cloud = true, parent = a, y = a.y - math.floor(a.z or 0), z = 0 })
    end
  end
end

-- ------------------------------------------------------------ talking (R)
function M.talk(game, a)
  local actors = game.actors
  local tb = T(game)
  local st = game.stats
  local t = a.type
  if t == 0xE9 and a.sub31 == 0 then
    local msg = (bottleWith(game, function(v) return v >= 2 end)) and I37.cauldronHalf or M37.cauldron
    game:showMessage(msg)
    game.onTextDone = function(g) g.s31Fill = (g.s31Fill or 0) + 160 end
    return true
  elseif t == 0xE9 and a.sub31 and a.sub31 >= 2 then
    if (a.delay or 0) > 0 then return true end
    if not bottleWith(game, function(v) return v >= 2 end) then game:showMessage(M37.cauldronFull) return true end
    local row = RT.get("spr31.cauldronRows")[a.sub31]
    local cost = row and row[4]
    local id = ({ [2] = 0x2F, [3] = 0x30, [4] = 0x2E })[a.sub31]
    if (st.rupees or 0) < cost then game:showMessage(RT.get("msg.shop").poor) return true end
    if not bottleWith(game, function(v) return v == 2 end) then game:showMessage(MSGS.cauldronNoBottle) return true end
    a.delay = 64
    st.rupees = st.rupees - cost
    M.give(game, id)
    game.potionsBought = (game.potionsBought or 0) + 1
    return true
  elseif t == 0xF5 then
    if a.ai ~= 0 then return true end
    game:showMessage(M37.keeper)
    game.onTextDone = function(g)
      -- state 1
      local FEE = require("src.zelda.alttp.RomTables").get("fee20").pay   -- r38: 0x080DE0DC
      if (g.lastChoice or 0) ~= 0 or (g.stats.rupees or 0) < FEE then g:showMessage(M37.keeperNo) return end
      g.stats.rupees = g.stats.rupees - FEE
      if g.progress.fsCleared then
        g:showMessage(I37.keeperDone)
        g.onTextDone = function() a.dead = true end   -- state 2: he leaves
      else
        g:showMessage(I37.keeperPaid)
      end
      g.fsKeeperPaid = (g.fsKeeperPaid or 0) + 1
    end
    return true
  elseif t == 0xF7 then
    return M.carver(game, a)
  elseif t == 0x33 then
    if game.link.facing ~= 0 or not touching(actors, a) then return false end
    M.rupeePull(game, a)
    return true
  end
  return false
end

-- RupeePull_SpawnPrize (OURS: at the pull itself, not when Link has backed off)
function M.rupeePull(game, a)
  local tb = T(game)
  a.dead = true
  local k = game.s31Killed or 0
  if k > 0 then
    local j = k < 4 and 0 or ((game.s31Hurt or 0) > 0 and 1 or 2)
    for i = 4, 1, -1 do
      game:spawnDrop(tb.pullType[j + 1], a.x, a.y)
      local d = game.drops[#game.drops]
      if d and d.type == tb.pullType[j + 1] then d.xvel, d.yvel, d.zvel = tb.pullXv[i], tb.pullYv[i], 32 end
    end
  end
  game.s31Killed, game.s31Hurt = 0, 0
  game.rupeePulls = (game.rupeePulls or 0) + 1
end

-- the riddle carver's solicited states (0x17D8D0)
function M.carver(game, a)
  local tb = T(game)
  local r = riddle(game)
  local function riddleMsg() return tb.riddles[(r.n or 0) + 1] or tb.riddles[2] end   -- r38: no literal fallback
  local ai = a.ai
  if ai == 0 then game:showMessage(M37.carver0)
  elseif ai == 1 then
    game:showMessage(M37.carver1)
    game.onTextDone = function(g)
      if (g.lastChoice or 0) ~= 0 then g:showMessage(M37.carverNo) return end   -- state 2, choice 1 -> state 1
      g:showMessage(M37.carverYes)
      g.onTextDone = function(g2)
        -- state 3: the basket (receipt 0x52), riddle 1, empty basket
        r.n, r.basket = 1, 1
        g2.progress.basket = true
        g2:showMessage(M37.carverBasket)                                            -- state 4
        g2.onTextDone = function(g3) gbaMsg(g3, riddleMsg()); a.ai = 6 end   -- state 5
      end
    end
  elseif ai == 6 then gbaMsg(game, riddleMsg())
  elseif ai == 7 then
    game:showMessage(M37.carverEmpty)
    r.basket, a.ai = 1, 6
  elseif ai == 8 then
    game:showMessage(M37.carverRight)
    game.onTextDone = function(g)
      r.basket, r.n = 1, r.n + 1
      g.progress.riddleFlag = true                                   -- 0x020023F0
      -- state 10: the prize by the sword (0x57 without one)
      local sw = g.progress.swordLevel
      g.progress.hurricane = true
      a.ai = 11
    end
  elseif ai == 9 then
    local n = r.n
    game:showMessage((n == 1 or n == 4 or n == 7) and I37.carverNext1 or I37.carverNext)
    game.onTextDone = function(g)
      r.n, r.basket = r.n + 1, 1
      gbaMsg(g, riddleMsg())
      a.ai = 6
    end
  elseif ai == 11 then game:showMessage(M37.carverDone) end
  game.carverTalks = (game.carverTalks or 0) + 1
  return true
end

-- ------------------------------------------------------------ drawing
local function oamFlags(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end

local function drawQueen(spr, tb, a, x, y, dark)
  local f = oamFlags(spr, 0x72)
  local g = a.qgfx or 0
  if not dark then
    for i = 11, 0, -1 do
      local j = g * 12 + i + 1
      spr:oam(x + tb.fqX[j], y + tb.fqY[j], tb.fqChar[j], bor(f, tb.fqFlags[j]), tb.fqBig[j])
    end
  else
    spr:drawDmd(a, tb.dmd.fqDmd, g * 10, 10, x, y, f)
  end
  local info = spr.info
  for _, s in ipairs(a.sparks or {}) do
    local ch = info.single2[(info.single1[0x72 + 1] or 0) + rshift(s.c, 3) + 1]
    if ch then spr:oam(x + s.x, y + s.y, ch, bor(band(f, 0xF1), 0x08), 0) end
  end
end

function M.draw(spr, a, x, y, frame, game)
  local tb = spr.data.t and spr.data.t.spr31
  if not tb then return false end
  local t = a.type
  y = y - math.floor(a.z or 0)
  if t == 0x33 then return true end   -- (the handle is part of the wall)
  if t == 0x72 then
    if a.queen or a.fairy then
      local dy = a.queen and 0 or -70
      drawQueen(spr, tb, a, x, y + dy, game and require("src.zelda.alttp.FatFairy").dark(game))
    end
    return true                   -- the pond itself: nothing (WishPond2_Draw shows the thrown item only)
  elseif t == 0xC8 then
    if a.cloud then return true end   -- (the cloud is its sparkle garnish: not drawn)
    if a.blink then return true end
    spr:drawDmd(a, tb.dmd.bigFairy, (a.gfx or 0) * 4, 4, x, y, oamFlags(spr, t))
    spr:drawShadow(x, y + math.floor(a.z or 0), t)
    return true
  elseif t == 0xE9 then
    local f = oamFlags(spr, t)
    if (a.sub31 or 0) == 0 then
      spr:drawDmd(a, tb.dmd.shop, band(rshift(frame or 0, 5), 1) * 2, 2, x, y, f)
      spr:drawShadow(x, y, t)
    else
      local d = ({ [2] = tb.dmd.green, [3] = tb.dmd.blue, [4] = tb.dmd.red })[a.sub31]
      if not d then return false end
      for i = #d, 1, -1 do
        local e = d[i]
        spr:oam(x + e[1], y + e[2], e[3], bxor(e[4], f), e[5])
      end
    end
    return true
  elseif t == 0xF3 then
    if not a.carving then return true end
    local e = tb.f3[(a.A or 0) * 3 + a.carving + 1]
    if not e then return false end
    local pal = e.pal >= 8 and e.pal - 8 or e.pal
    local f = bor(band(oamFlags(spr, t), 0xF1), pal * 2)
    for i = e.n, 1, -1 do
      local d = e.dmd[i]
      spr:oam(x + d[1], y + d[2], d[3], bor(band(d[4], 0xF1), band(f, 0x0F)), d[5])
    end
    return true
  elseif t == 0xF5 then
    spr:drawDmd(a, tb.dmd.f5, 0, 2, x, y, oamFlags(spr, t))
    return true
  elseif t == 0xF7 then
    spr:drawDmd(a, tb.dmd.f7, 0, 2, x, y, oamFlags(spr, t))
    return true
  end
  return false
end

-- ------------------------------------------------------------ install
M.TYPES = { [0x33] = true, [0x72] = true, [0xB2] = true, [0xC8] = true, [0xE9] = true, [0xF3] = true, [0xF5] = true, [0xF7] = true }
M.TALK = { [0x33] = true, [0xE9] = true, [0xF5] = true, [0xF7] = true }

function M.install(G)
  local B = require("src.zelda.alttp.Barrier29")
  B.TYPES[0xF5], B.TYPES[0xF7] = true, true      -- both call Sprite_BehaveAsBarrier
  local A = require("src.zelda.alttp.Actors")
  local up0 = A.update
  function A:update()
    local game = self.game
    local tb = game and T(game)
    if tb and self.inside and not game.textBox then
      patchTables(game, tb)
      local list = self.list
      local n = #list
      for i = 1, n do
        local a = list[i]
        if a and M.TYPES[a.type] and not a.dead and not a.i27 and not a.p30 then
          if not a.s31 then M.prep(self, a) end
          if not a.dead then
            if a.type == 0x72 then
              if a.pond then happiness(self, a) end
              if a.queen or a.fairy then queen(self, a) end
            elseif a.type == 0xC8 then bigFairy(self, a)
            elseif a.type == 0xE9 and (a.delay or 0) > 0 then a.delay = a.delay - 1 end
          end
        end
      end
    end
    -- the hearts filler (OURS: 1 health a frame)
    if game and (game.s31Fill or 0) > 0 and game.stats then
      local st = game.stats
      if st.health < st.healthMax then st.health = st.health + 1; game.s31Fill = game.s31Fill - 1
      else game.s31Fill = 0 end
    end
    return up0(self)
  end
  -- num_sprites_killed / number_of_times_hurt_by_sprites (the rupee pull)
  local died0 = A.died
  function A:died(a, ...)
    if self.game then self.game.s31Killed = (self.game.s31Killed or 0) + 1 end
    return died0(self, a, ...)
  end
  local hurt0 = G.hurtLink
  if hurt0 then
    function G:hurtLink(...)
      local h0 = self.stats and self.stats.health
      local r = hurt0(self, ...)
      if h0 and self.stats.health < h0 then self.s31Hurt = (self.s31Hurt or 0) + 1 end
      return r
    end
  end
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    if M.TYPES[a.type] and a.type ~= 0xB2 and not a.i27 and not a.p30 and self.data.t and self.data.t.spr31 then
      local r = M.draw(self, a, x, y, frame, M.game)
      if r then return r end
    end
    return da0(self, a, x, y, frame, room)
  end
  local act0 = G.escapeAct
  function G:escapeAct()
    if T(self) and self.actors and self.interior and not self.textBox then
      for _, a in ipairs(self.actors.list) do
        if M.TALK[a.type] and a.s31 and not a.dead and not a.i27 and facingNear(self, a) then
          if M.talk(self, a) then
            self.s31Talks = (self.s31Talks or 0) + 1
            self.lastS31 = a.type
            return true
          end
        end
      end
    end
    return act0(self)
  end
  local roomFrame = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    M.game = self
    if self.s31Hold and inp then
      for _, k in ipairs({ "up", "down", "left", "right", "a", "b", "y" }) do inp[k] = false end
    end
    return roomFrame(self, inp)
  end
end

return M
