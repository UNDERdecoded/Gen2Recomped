-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE TOWNSPEOPLE INDOORS (round 30). Round 29 (Barrier29.lua) made these
-- block Link; they were not drawn and did not talk. zelda3 names, the GBA's
-- draw tables (copies of the SNES DrawMultipleData, 8 bytes an entry, found
-- by their x / y / size and the SNES -> GBA OBJ char mapping) and byte tables
-- are read at import (file offsets in OFF):
--
--   0x1F the sick kid (Sprite_1F_SickKid, room 0x102): kBugNetKid_Dmd
--        (6 an entry by graphics), Gfx / Delay 0x176000 / 0x176008. Resting:
--        no bottle -> 0x104; with one: the perk animation, 0x105, the bug net
--        (receipt 0x21), then 0x106. SpritePrep: the net already -> state 3.
--   0x28 the storytellers (Sprite_28_DarkWorldHintNPC, StoryTeller_1_Draw):
--        subtype by kStoryTellerRooms (0x176370) [x_hi & 1 picks the second
--        of room 0x10E]; 0xFE "20 Rupees?" -> 0xFF / 0x101 / 0x102 / 0x103
--        (paid, hearts filled) or 0x100; subtype 3 (0x11A) 0x149 and its
--        h-flip every 64 frames; subtype 4 (0x114) bobs (z).
--   0x29 Sprite_HumanMulti_1 by kHumanMultiTypes (0x175F1C: rooms 3, 0xE1,
--        0x19): the flute boy's father (0x103; FluteBoyFather_Draw, 0xA1 /
--        0xA4 asleep / 0xA2 when the flute is played next to him (Flute.lua)
--        / 0xA3), the thieves' hideout guy (0xE1; Thief_Draw with the head
--        char by direction, 0x171), Blind's hut guy (0x119; 0x172).
--   0x31 the fortune teller (Sprite_FortuneTeller, FortuneTeller_Draw by
--        world * 2 + graphics): prices 0x174ED4 (u16), readings 0x174F0C
--        (u16, GBA numbers): 0xF2 (too poor) / 0xF3, the reading
--        (FortuneTeller_PerformPseudoScience: the first two unmet goals, the
--        flag 0x40 alternates), 0xF4, the price taken and hearts filled.
--   0x32 the quarrelling brothers (kQuarrelBros_Dmd, head to Link): even
--        room 0x131, odd 0x12F (0x130 once the wall between them is open).
--   0x35 the innkeeper (InnKeeper_Draw): 0x182, with the flippers 0x183.
--   0x65 the shooting gallery's host (ArcheryGameGuy_Draw: X / Y / char /
--        flags / big tables 0x176866..): 0x85.
--   0xB5 the bomb shop (Sprite_B5_BombShop): the clerk's breathing
--        (kBombShopGuy_Delay 0x176460), 0x117 / 0x118; SpritePrep_BombShoppe
--        puts the bombs (subtype 1) at (-24, -24) -- 100 Rupees, +27 bombs
--        (link_bomb_filler), 0x119 / 0x17C / 0x16E -- and, with crystals 5
--        and 6 and the smiths reunited, the super bomb (subtype 2).
--   0xBC the drunkard in the inn (DrinkingGuy_Draw): 0x175.
--
-- Messages are the SNES numbers zelda3 uses (= the GBA's - 3: Text.bmgIndex).
-- OURS: talking is "A while facing the person" (Sprite_ShowSolicitedMessage's
-- touch + A); the fortune teller's price is not printed (the {number}
-- command is not ported); the shooting gallery game, the super bomb (follower
-- 13), the bomb clerk's puffs, the brothers' door check and sound are not
-- ported; the hideout guy's head turns by our 4-way rule.

local bit = require("bit")
local band, bxor, rshift = bit.band, bit.bxor, bit.rshift

local M = {}
local HEAD_CHAR = require("src.zelda.alttp.RomTables").get("folk.headChar")
local HEAD_FLAGS = require("src.zelda.alttp.RomTables").get("folk.headFlags")

M.OFF = {
  bugkid = { 0x176010, 18 }, bugkidGfx = 0x176000, bugkidDelay = 0x176008,
  story = { 0x1763C0, 10 }, storyRooms = 0x176370,
  humanRooms = 0x175F1C, dad = { 0x175F2C, 6 }, blind = { 0x175F5C, 16 }, thief = { 0x17768C, 24 },
  fortune = { 0x174F4C, 12 }, prices = 0x174ED4, readings = 0x174F0C,
  quarrel = { 0x17CF68, 16 }, inn = { 0x175FE0, 2 },
  archX = 0x176866, archY = 0x176875, archChar = 0x176884, archFlags = 0x176893, archBig = 0x1768A2,
  bomb = { 0x176474, 6 }, bombDelay = 0x176460,
  drunk = { 0x1760A0, 6 },
}

M.TYPES = { [0x1F] = true, [0x28] = true, [0x29] = true, [0x31] = true, [0x32] = true, [0x35] = true,
            [0x65] = true, [0xB5] = true, [0xBC] = true }

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
  for _, k in ipairs({ "bugkid", "story", "dad", "blind", "thief", "fortune", "quarrel", "inn", "bomb", "drunk" }) do
    t.dmd[k] = dmd(rom, O[k])
  end
  t.bugkidGfx, t.bugkidDelay = s8(rom:bytesU8(O.bugkidGfx, 8)), rom:bytesU8(O.bugkidDelay, 7)
  t.storyRooms, t.humanRooms = rom:bytesU8(O.storyRooms, 5), rom:bytesU8(O.humanRooms, 3)
  t.prices, t.readings = rom:bytesU16(O.prices, 4), rom:bytesU16(O.readings, 16)
  t.archX, t.archY = s8(rom:bytesU8(O.archX, 15)), s8(rom:bytesU8(O.archY, 15))
  t.archChar, t.archFlags, t.archBig = rom:bytesU8(O.archChar, 15), rom:bytesU8(O.archFlags, 15), rom:bytesU8(O.archBig, 15)
  t.bombDelay = rom:bytesU8(O.bombDelay, 8)
  check(t.dmd.inn[1][5] == 2 and t.dmd.story[10][5] == 2 and t.dmd.bugkid[1][5] == 0 and t.bugkidGfx[8] == -1
        and t.storyRooms[3] == 0x12 and t.humanRooms[2] == 0xE1 and t.prices[4] == 30 and t.archBig[6] == 0
        and t.bombDelay[1] == 255, "townsfolk tables")
  return t
end
local function T(game) return game.data.t and game.data.t.people30 end
M.tabs = T

-- ------------------------------------------------------------ helpers
local function frameCounter(game) return band(game.frame or 0, 255) end
local function msg(game, n) return game:showMessage(n) end
-- r37: the townsfolk's messages, read at import (RomTablesSpec "msg.town",
-- "msg.imm37", the tables "msg.inn" / "msg.bombGuy", the archery keeper's,
-- the shop's "not enough rupees"); the bomb bag's price / count ("price37")
local RT37 = require("src.zelda.alttp.RomTables")
local TM = RT37.get("msg.town")
local function inv(game) return require("src.zelda.alttp.Menu").inventory(game) end
local function hasItem(game, id)
  for _, v in ipairs(game.progress.items or {}) do if v == id then return true end end
  return false
end
M.hasItem = hasItem
-- SNES sprite_D to face Link (0 right, 1 left, 2 down, 3 up), ^ 3 = the
-- people's head direction (0 up, 1 down, 2 left, 3 right)
local function faceLink(a, lk)
  local dx, dy = lk.x - a.x, lk.y - a.y
  if math.abs(dx) >= math.abs(dy) then return dx >= 0 and 0 or 1 end
  return dy >= 0 and 2 or 3
end
M.faceLink = faceLink
local function rng(a)
  a.seed = band((a.seed or (a.x * 31 + a.y)) * 1103515245 + 12345, 0x7FFFFFFF)
  return band(rshift(a.seed, 16), 255)
end
-- Link_ReceiveItem with the receipt message; after(g) when it is read
function M.give(game, id, after)
  game:getItem(id)
  game.holdItem = { item = id, t = 0 }
  local rm = game:receiptMessage(id)
  local function done(g) g.holdItem = nil; if after then after(g) end end
  if rm and game:showMessage(rm) then game.onTextDone = done else done(game) end
end
local function bottles(game)
  local iv = inv(game)
  for _, k in ipairs(require("src.zelda.alttp.Items27").BOTTLES) do if (iv[k] or 0) >= 2 then return true end end
  return false
end
local function touching(game, a)
  local A = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  if not cb then return false end
  local hx, hy, hw, hh = A.hitbox(cb, a)
  local lx, ly, lw, lh = A.linkBox(game.link)
  return A.overlapCart(lx, ly, lw, lh, hx, hy, hw, hh)
end
M.touching = touching

-- ------------------------------------------------------------ prep / update
function M.prep(actors, a)
  local game = actors.game
  local tb = T(game)
  local room = actors.room or 0
  a.p30, a.ai, a.gfx, a.delay, a.D, a.sub2 = true, 0, 0, 0, 1, 0
  local t = a.type
  if t == 0x1F then
    if hasItem(game, 0x21) or (inv(game)[0x1F + 16] or 0) ~= 0 then a.ai = 3 end
  elseif t == 0x28 then
    local r = band(room, 0xFF)
    local j
    for i, v in ipairs(tb.storyRooms) do if v == r then j = i - 1 break end end
    j = j or 0
    if j == 0 and band(rshift(a.x, 8), 1) == 1 then j = 1 end
    a.sub2 = j
  elseif t == 0x29 then
    local r = band(room, 0xFF)
    for i, v in ipairs(tb.humanRooms) do if v == r then a.sub2 = i - 1 end end
    a.D = 0
  elseif t == 0x31 then
    a.x, a.y = a.x + 8, a.y + 8   -- SpritePrep_IncrXYLow8
    a.dark = game.link.world == "dw" or nil   -- savegame_is_darkworld
  elseif t == 0xB5 and not a.ware then
    -- SpritePrep_BombShoppe: the wares beside the clerk
    local list = actors.list
    list[#list + 1] = { type = 0xB5, x = a.x - 24, y = a.y - 24, lower = a.lower, ware = 1, sub2 = 1, p30 = true,
                        ai = 0, gfx = 0, delay = 0, D = 1, dir = 1, t = 0, state = "idle", hp = 255, index = -1 }
    local p = game.progress
    if band(p.crystals or 0, 5) == 5 and band(p.smith or 0, 0x20) ~= 0 then
      list[#list + 1] = { type = 0xB5, x = a.x - 56, y = a.y - 24, lower = a.lower, ware = 2, sub2 = 2, p30 = true,
                          ai = 0, gfx = 0, delay = 0, D = 1, dir = 1, t = 0, state = "idle", hp = 255, index = -1 }
    end
  end
end

function M.update(actors, a)
  local game = actors.game
  local tb = T(game)
  local lk = game.link
  local fc = frameCounter(game)
  if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
  local t = a.type
  if t == 0x1F then
    if a.ai == 1 then
      game.p30Hold = true
      if a.delay == 0 then
        local j = a.A or 0
        local g = tb.bugkidGfx[j + 1]
        if g and g >= 0 then
          a.gfx, a.delay, a.A = g, tb.bugkidDelay[j + 1] or 0, j + 1
        else
          msg(game, TM.t1Fgive)
          a.ai = 2
          game.onTextDone = function(g2)
            M.give(g2, 0x21, function(g3) g3.p30Hold = nil end)
            a.ai = 3
            g2.bugNetGiven = (g2.bugNetGiven or 0) + 1
          end
        end
      end
    elseif a.ai == 3 then a.gfx = 1 end
  elseif t == 0x28 then
    if a.delay == 0 then a.gfx = band(rshift(fc, 4), 1) end
    if a.sub2 == 3 and a.delay == 0 then
      if band(fc, 0x3F) == 0 then a.flip = not a.flip end
      if rng(a) == 0 then a.delay = 32 end
    elseif a.sub2 == 4 then
      a.gfx = band(rshift(fc, 1), 1)
      a.zv = a.zv or 0
      a.z = (a.z or 0) + a.zv / 16
      if a.z < 0 then a.z = 0 end
      a.zv = a.zv + (((a.z or 0) >= 4) and -1 or 1)
    end
  elseif t == 0x29 then
    if a.sub2 == 0 then
      a.gfx = (a.ai ~= 0 and 2) or ((fc < 48) and 2 or band(rshift(fc, 7), 1))
    elseif a.sub2 == 1 then
      a.gfx = 2
      if band(fc, 3) == 0 then
        local d = bxor(faceLink(a, lk), 3)
        a.head = d == 3 and 2 or d
      end
    end
  elseif t == 0x31 then
    if a.ai == 3 then a.gfx = band(rshift(fc, 4), 1) else a.gfx = 0 end
  elseif t == 0x32 then
    a.D = bxor(faceLink(a, lk), 3)
  elseif t == 0x65 then
    a.gfx = 3
  elseif t == 0xB5 and not a.ware then
    if a.delay == 0 then
      local j = a.E or 0
      a.E = band(j + 1, 7)
      a.delay = tb.bombDelay[j + 1] or 0
      a.gfx = band(j, 1)
    end
  elseif t == 0xBC then
    if rng(a) == 0 then a.delay = 32 end
    a.gfx = (a.delay or 0) > 0 and 1 or 0
  end
end

-- ------------------------------------------------------------ talking
-- FortuneTeller_PerformPseudoScience: the first two unmet goals
local function readings(game)
  local p, iv = game.progress, inv(game)
  local slots = {}
  local function add(q) if #slots < 2 then slots[#slots + 1] = q end end
  if (p.mapIcons or 0) >= 3 then
    if not hasItem(game, 0x1D) then add(2) end
    if band(p.pendants or 0, 2) == 0 then add(1) end
    if not (hasItem(game, 0x29) or hasItem(game, 0x0D)) then add(3) end
    if not hasItem(game, 0x1E) then add(4) end
    if not hasItem(game, 0x1F) then add(5) end
    if game:storyProgress() < 3 then add(6) end
    if not p.halfMagic then add(7) end
    if not hasItem(game, 0x0F) then add(8) end
    if not p.purpleChest then add(9) end
    if band(p.smith or 0, 0x20) == 0 then add(10) end
    if not hasItem(game, 0x19) then add(11) end
    if not p.fortune12 then add(12) end
    if (iv[0x3D] or 0) < 4 then add(13) end
    add(14); add(15)
  end
  while #slots < 2 do slots[#slots + 1] = 0 end
  game.fortuneFlip = not game.fortuneFlip
  return slots[game.fortuneFlip and 2 or 1]
end

function M.talk(game, a)
  local tb = T(game)
  local t, st = a.type, game.stats
  if t == 0x1F then
    if a.ai == 0 then
      if not bottles(game) then msg(game, TM.t1Fno) else a.ai, a.A, a.delay = 1, 0, 0; game.p30Hold = true end
    elseif a.ai == 3 then msg(game, TM.t1Fafter) end
    return true
  elseif t == 0x28 then
    if a.sub2 == 3 then msg(game, TM.t28end) return true end
    msg(game, TM.t28)
    game.onTextDone = function(g)
      local FEE = require("src.zelda.alttp.RomTables").get("fee20").pay   -- r38: 0x080DE0DC
      if (g.lastChoice or 0) == 0 and (st.rupees or 0) >= FEE then
        st.rupees = st.rupees - FEE
        msg(g, ({ [0] = TM.t28a, TM.t28b, TM.t28c, TM.t28d, TM.t28d })[a.sub2] or TM.t28a)
        g.onTextDone = function(g2) g2.stats.health = g2.stats.healthMax; g2.storyPaid = (g2.storyPaid or 0) + 1 end
      else
        msg(g, TM.t28no)
      end
    end
    return true
  elseif t == 0x29 then
    if a.sub2 == 0 then
      if a.ai ~= 0 then msg(game, TM.t29again)
      elseif not hasItem(game, 0x14) and (inv(game)[0x2E] or 0) < 2 then msg(game, TM.t29need)
      else msg(game, TM.t29) end
    elseif a.sub2 == 1 then msg(game, TM.t29b)
    else
      msg(game, TM.t29c)
      a.D = bxor(faceLink(a, game.link), 3)
    end
    return true
  elseif t == 0x31 then
    local j = a.price or band(rng(a), 3)
    a.price = j
    local cost = tb.prices[j + 1] or 10
    if (st.rupees or 0) < cost then msg(game, TM.fortunePoor) return true end
    msg(game, TM.fortune)
    game.onTextDone = function(g)
      -- r38: "no" -> back to waiting with no message (0x080D3A7C: choice != 0 ->
      -- state 2; the GBA shows nothing, the SNES 0xF5)
      if (g.lastChoice or 0) ~= 0 then return end
      a.ai = 3
      local n = require("src.zelda.alttp.Text").bmgIndex(tb.readings[readings(g) + 1])
      msg(g, n)
      g.onTextDone = function(g2)
        a.ai = 0
        msg(g2, TM.fortuneDone)
        g2.onTextDone = function(g3)
          g3.stats.rupees = math.max(0, (g3.stats.rupees or 0) - cost)
          g3.stats.health = g3.stats.healthMax
          a.price = nil
          g3.fortunes = (g3.fortunes or 0) + 1
        end
      end
    end
    return true
  elseif t == 0x32 then
    local room = game.interior and game.interior.room or 0
    if band(room, 1) == 0 then msg(game, TM.quarrel)
    else msg(game, game.interior.mem and game.interior.mem.quarrelOpen and RT37.get("msg.imm37").quarrelOpen or RT37.get("msg.imm37").quarrelShut) end
    return true
  elseif t == 0x35 then
    msg(game, RT37.get("msg.inn")[hasItem(game, 0x1E) and 1 or 0])
    return true
  elseif t == 0x65 then
    msg(game, RT37.get("msg.archery").hello)
    return true
  elseif t == 0xB5 then
    if not a.ware then
      local p = game.progress
      msg(game, (band(p.crystals or 0, 5) == 5 and band(p.smith or 0, 0x20) ~= 0) and RT37.get("msg.bombGuy")[1] or RT37.get("msg.bombGuy")[0])
    elseif a.ware == 1 then
      local ui = game.data.t and game.data.t.ui
      local max = (ui and ui.maxBombs and ui.maxBombs[(st.bombLevel or 0) + 1]) or 10
      if (st.bombs or 0) >= max then msg(game, TM.bombFull)
      elseif (st.rupees or 0) < RT37.get("price37").bombBag then msg(game, RT37.get("msg.shop").poor)
      else
        st.rupees = st.rupees - RT37.get("price37").bombBag
        st.bombs = math.min(max, (st.bombs or 0) + RT37.get("price37").bombBagCount)
        a.dead = true
        msg(game, TM.bombSold)
        game.bombsBought = (game.bombsBought or 0) + 1
      end
    else
      msg(game, RT37.get("msg.bombGuy")[1])
    end
    return true
  elseif t == 0xBC then
    a.gfx = 0
    msg(game, TM.tBC)
    return true
  end
  return false
end

-- ------------------------------------------------------------ drawing
local function oamFlags(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end

function M.draw(spr, a, x, y, frame)
  local tb = spr.data.t and spr.data.t.people30
  if not tb then return false end
  local t, d = a.type, tb.dmd
  local f = oamFlags(spr, t)
  y = y - math.floor(a.z or 0)
  if t == 0x1F then
    spr:drawDmd(a, d.bugkid, (a.gfx or 0) * 6, 6, x, y, f)
  elseif t == 0x28 then
    spr:drawDmd(a, d.story, (a.sub2 or 0) * 2 + (a.gfx or 0), 1, x, y, bxor(f, a.flip and 0x40 or 0))
  elseif t == 0x29 then
    if a.sub2 == 0 then spr:drawDmd(a, d.dad, (a.gfx or 0) * 2, 2, x, y, f)
    elseif a.sub2 == 1 then
      -- Thief_Draw: oam flags 15; the head (first entry) by direction
      local e = d.thief[(a.gfx or 2) * 2 + 1]
      local h = a.head or 1
      local chars, flips = HEAD_CHAR, HEAD_FLAGS   -- r35: the guards' head tables, read at import
      spr:drawDmd(a, d.thief, (a.gfx or 2) * 2 + 1, 1, x, y, 15)
      spr:oam(x + e[1], y + e[2], chars[h], bit.bor(band(bxor(e[4], 15), bit.bnot(0x40)), flips[h]), e[5])
    else spr:drawDmd(a, d.blind, (a.gfx or 0) * 2 + (a.D or 0) * 4, 2, x, y, f) end
  elseif t == 0x31 then
    local j = (a.dark and 2 or 0) + (a.gfx or 0)
    spr:drawDmd(a, d.fortune, j * 3, 3, x, y, f)
  elseif t == 0x32 then
    spr:drawDmd(a, d.quarrel, (a.gfx or 0) * 2 + (a.D or 1) * 4, 2, x, y, f)
  elseif t == 0x35 then
    spr:drawDmd(a, d.inn, 0, 2, x, y, f)
  elseif t == 0x65 then
    local g = a.gfx or 3
    for i = 2, 0, -1 do
      local j = g * 3 + i + 1
      spr:oam(x + tb.archX[j], y + tb.archY[j], tb.archChar[j], bit.bor(tb.archFlags[j], f), tb.archBig[j])
    end
  elseif t == 0xB5 then
    spr:drawDmd(a, d.bomb, (a.sub2 or 0) * 2 + (a.gfx or 0), 1, x, y, f)
  elseif t == 0xBC then
    spr:drawDmd(a, d.drunk, (a.gfx or 0) * 3, 3, x, y, f)
  else return false end
  return true
end

-- ------------------------------------------------------------ install

function M.install(G)
  local A = require("src.zelda.alttp.Actors")
  local up0 = A.update
  function A:update()
    local game = self.game
    if game and T(game) and self.inside and not game.textBox then
      local list = self.list
      for i = 1, #list do
        local a = list[i]
        if M.TYPES[a.type] and not a.dead and not a.i27 then
          if not a.p30 then M.prep(self, a) end
          M.update(self, a)
        end
      end
    end
    return up0(self)
  end
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    if M.TYPES[a.type] and a.p30 and not a.i27 and self.data.t and self.data.t.people30 then
      return M.draw(self, a, x, y, frame)
    end
    return da0(self, a, x, y, frame, room)
  end
  -- A in front of a person (Sprite_ShowSolicitedMessage)
  local act0 = G.escapeAct
  function G:escapeAct()
    if T(self) and self.actors and self.interior and not self.textBox then
      local C = require("src.zelda.alttp.Carry")
      local q = C.QUERY[self.link.facing]
      local px, py = self.link.x + q[1], self.link.y + q[2]
      local A = require("src.zelda.alttp.Actors")
      local cb = self.data.roomIdx and self.data.roomIdx.combat
      for _, a in ipairs(self.actors.list) do
        -- the point in front of Link within 4 px of the person's hit box
        -- (Link stands against it: Sprite_BehaveAsBarrier)
        local hx, hy, hw, hh = a.x, a.y, 16, 16
        if cb then hx, hy, hw, hh = A.hitbox(cb, a) end
        if M.TYPES[a.type] and a.p30 and not a.dead and not a.i27
           and px >= hx - 4 and px < hx + hw + 4 and py >= hy - 4 and py < hy + hh + 4 then
          if M.talk(self, a) then
            self.p30Talks = (self.p30Talks or 0) + 1
            self.lastP30 = a.type
            return true
          end
        end
      end
    end
    return act0(self)
  end
  -- Link held while the sick kid perks up (flag_is_link_immobilized)
  local roomFrame = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    -- (the room's sprites run inside escapeRoomFrame: only Link's input goes)
    if self.p30Hold and inp then
      for _, k in ipairs({ "up", "down", "left", "right", "a", "b", "y" }) do inp[k] = false end
    end
    return roomFrame(self, inp)
  end
end

return M
