-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SHOPS (round 22): sprite 0xBB, the SNES Sprite_BB_Shopkeeper the GBA
-- keeps (zelda3 sprite_main.c), for the standard clerk and his wares:
--
--   SpritePrep_Shopkeeper: the room's low byte in kShopKeeperWhere {0x0F,
--   0x10, 0x00, 0x06, 0x18, 0x12, 0x1E, 0xFF, 0x1F, 0x23, 0x24, 0x25, 0x27}
--   picks the wares: case 0 (0x10F) potion / fighter shield / bombs, case 1
--   (0x110) fire shield / bee / arrows, cases 5, 7, 8 (0x112, 0x11F
--   Kakariko, ...) potion / heart / bombs; ShopKeeper_SpawnShopItem puts
--   ware n at the clerk's x + {-44, 8, 60}, y + 0x27 (sprite 0xBB again,
--   subtype2 = the ware 7..13). The other cases (chest games, the thieves)
--   are not ported (the clerk only talks).
--   Shopkeeper_StandardClerk: a barrier; R facing him -> message 0x165
--   (Sprite_ShowSolicitedMessage, Npc.lua); once, when Link is above his
--   y + 0x60, 0x165 unconditionally.
--   ShopItem_*: a barrier; R while Link touches it (ShopItem_CheckForAPress:
--   filtered_joypad_L & 0x80 + Sprite_CheckDamageToLink_same_layer):
--     7  red potion  150  needs an empty bottle (none ported: 0x16D)
--     8  shield       50  owned -> 0x166
--     9  fire shield 500  owned -> 0x166
--     10 heart        10  full health -> only the beep; else +1 heart (item 0x42)
--     11 arrows       30  full -> 0x16E; else +10 arrows (item 0x44)
--     12 bombs        50  full -> 0x16E; else +10 bombs (item 0x31)
--     13 bee          10  needs an empty bottle (0x16D)
--   too few rupees -> 0x17C; bought -> the ware is gone and the clerk's
--   thanks kShopKeeper_GiveItemMsgs[ware - 7] {0x168, 0x167, 0x167, 0x16C,
--   0x169, 0x16A, 0x16B} (ShopKeeper_RapidTerminateReceiveItem: no hold-up).
--   Bags hold ui.maxBombs / ui.maxArrows (0x16B588 / 0x16B598) at level 0.
--
-- The clerk is drawn with the GBA's copy of kShopkeeper_Dmd (0x17D2C4,
-- Npc.lua), the wares and their prices with its kShopKeeper_ItemWithPrice_Dmd
-- (0x17D0E4, 35 entries; the GBA's chars, found by x / y / size), xor the
-- sprite's flags (page 1). The icon / digit drawing below is only a fallback
-- for an old import. OURS: "touching" is Link's box grown by 2 px (our
-- barrier stops him 1 px short); no beep.

local bit = require("bit")

local M = {}
M.TYPE = 0xBB
-- r35: the shopkeeper's room list (13 of the GBA's 14) and the wares' x
-- offsets, read from the ROM at import
M.WHERE = require("src.zelda.alttp.RomTables").get("shop.where")
M.ITEM_X = require("src.zelda.alttp.RomTables").get("shop.itemX")
M.WARES = {
  [0] = { 7, 8, 12 }, [1] = { 9, 13, 11 }, [5] = { 7, 10, 12 }, [7] = { 7, 10, 12 }, [8] = { 7, 10, 12 },
}
-- r36: wares 7-12's prices are read at import from the cartridge's
-- ShopItem code (RomTablesSpec "shop.price"); r37: the bee's (13) too: the
-- GBA's ware 13 (0x17D034 [13] = 0x0810F3B8) calls the bottle ware
-- 0x0810EDB4 with index 0, which charges s16 0x17D0BC [index * 4] and gives
-- byte 0x17D0C4 [index * 4] (0x0E, the bee) -- "shop.bottlePrice"
M.ITEMS = {
  [7] = { item = 0x2E, bottle = true, icon = 0x2E },
  [8] = { item = 0x04, shield = 1, icon = 0x04 },
  [9] = { item = 0x05, shield = 2, icon = 0x05 },
  [10] = { item = 0x42, heart = true, drop = 0xD8 },
  [11] = { item = 0x44, arrows = 10, drop = 0xE2 },
  [12] = { item = 0x31, bombs = 10, drop = 0xDD },
  [13] = { item = 0x0E, bottle = true, icon = 0x0E },
}
-- r37: kShopKeeper_GiveItemMsgs (0x17D0CC, read at 0x0810EF6C) and the
-- clerk's hello (0x17D080 [0], read at 0x0810E38A), from the import
M.GIVE_MSG = require("src.zelda.alttp.RomTables").get("msg.shopGive")
-- r36: prices and messages read at import (RomTablesSpec "shop.price", "msg.shop")
require("src.zelda.alttp.RomTables").onBind(function()
  local RT = require("src.zelda.alttp.RomTables")
  for k, v in pairs(RT.get("shop.price")) do if M.ITEMS[k] then M.ITEMS[k].cost = v end end
  M.ITEMS[13].cost = RT.get("shop.bottlePrice")[RT.get("shop.beeIndex")[0]]
  M.MSG_HELLO = RT.get("msg.shopHello")[0]
  local t = RT.get("msg.shop")
  M.MSG_POOR, M.MSG_HAVE, M.MSG_FULL, M.MSG_BOTTLE = t.poor, t.have, t.full, t.bottle
end)
-- the sprite sheet's digit chars (SNES 0x30 '0', 0x31 '1', 0x13 '5', 0x03 '3'
-- in kShopKeeper_ItemWithPrice_Dmd), as GBA OBJ chars (SNES char row k ->
-- GBA row (k & 3) + 4 * (k >> 3 & 1), half k >> 2 & 1; r16 dmdsearch)
M.DIGIT = { [0] = 0x60, [1] = 0x61, [3] = 0x03, [5] = 0x23 }

local function where(room)
  local low = room % 256
  for i, r in ipairs(M.WHERE) do if r == low then return i - 1 end end
end

-- the shield Link wears (link_shield_type): the uncle's, unless one was bought
local function shieldType(game)
  local p = game.progress
  if p.shield then return p.shield end
  return p.sword and 1 or 0
end

local function buy(game, actors, a)
  local it = M.ITEMS[a.shopItem]
  local st, ui = game.stats, game.data.ui or {}
  local function poor() game:showMessage(M.MSG_POOR) end
  local function pay()
    if (st.rupees or 0) < it.cost then return false end
    st.rupees = st.rupees - it.cost
    return true
  end
  if it.bottle then game:showMessage(M.MSG_BOTTLE) return end
  if it.shield then
    if shieldType(game) >= it.shield then game:showMessage(M.MSG_HAVE) return end
    if not pay() then return poor() end
    game.progress.shield = it.shield
  elseif it.heart then
    if (st.health or 0) >= (st.healthMax or 24) then game.shopBeeps = (game.shopBeeps or 0) + 1 return end
    if not pay() then return poor() end
    st.health = math.min(st.healthMax or 24, (st.health or 0) + 8)
  elseif it.arrows then
    local max = (ui.maxArrows and ui.maxArrows[(st.arrowLevel or 0) + 1]) or 30
    if (st.arrows or 0) >= max then game:showMessage(M.MSG_FULL) return end
    if not pay() then return poor() end
    st.arrows = math.min(max, (st.arrows or 0) + it.arrows)
  elseif it.bombs then
    local max = (ui.maxBombs and ui.maxBombs[(st.bombLevel or 0) + 1]) or 10
    if (st.bombs or 0) >= max then game:showMessage(M.MSG_FULL) return end
    if not pay() then return poor() end
    st.bombs = math.min(max, (st.bombs or 0) + it.bombs)
  end
  a.dead = true
  game.shopBought = (game.shopBought or 0) + 1
  game.shopLog = game.shopLog or {}
  game.shopLog[#game.shopLog + 1] = { ware = a.shopItem, cost = it.cost, room = actors.inside.room }
  game:showMessage(M.GIVE_MSG[a.shopItem])
end

-- one frame (Actors:update)
function M.update(actors, a, lk)
  local game, inside = actors.game, actors.inside
  if not a.shopPrep then
    a.shopPrep = true
    a.ai = 0
    if not a.shopItem then
      local j = where(inside.room)
      local wares = j and M.WARES[j]
      if wares then
        for n, w in ipairs(wares) do
          actors.list[#actors.list + 1] = { type = M.TYPE, shopItem = w, shopPrep = true, x = a.x + M.ITEM_X[n],
                                            y = a.y + 0x27, lower = a.lower, t = 0, index = -1, hp = 1 }
        end
      end
      a.clerk = wares ~= nil
    end
  end
  if a.shopItem then
    -- ShopItem_CheckForAPress: R this frame, Link touching it
    if game.rNow and not game.textBox then
      local A = require("src.zelda.alttp.Actors")
      local lx, ly, lw, lh = A.linkBox(lk)
      if A.overlapCart(lx - 2, ly - 2, lw + 4, lh + 4, a.x, a.y, 16, 16) then
        game.rNow = false
        buy(game, actors, a)
      end
    end
    return
  end
  -- Shopkeeper_StandardClerk: the greeting once Link is within y + 0x60
  if a.clerk and a.ai == 0 and a.y + 0x60 >= lk.y and not game.textBox then
    game:showMessage(M.MSG_HELLO)
    a.ai = 1
  end
end

-- a ware: its picture and its price under it -- the GBA's copy of
-- kShopKeeper_ItemWithPrice_Dmd (0x17D0E4: 5 entries per ware, the price's
-- digits first), when the import has it
function M.draw(spr, a, x, y, frame, game)
  local it = M.ITEMS[a.shopItem]
  if not it then return false end
  local t = spr.data.t and spr.data.t.npc
  local list = t and t.dmd and t.dmd.shopItems
  if list and #list == 35 and not M.ICONS then
    -- the sprite's own OAM flags (kSpriteInit_Flags3 & 15: page 1) xor each entry's
    local f = bit.band(spr.info.flags3[M.TYPE + 1] or 0, 0x0F)
    spr:drawDmd(a, list, (a.shopItem - 7) * 5, 5, x, y, f)
    return true
  end
  if it.drop then
    local kinds = { [0xD8] = "heart", [0xE2] = "arrow10", [0xDD] = "bomb4" }
    spr:drawAbsorbable({ type = it.drop, kind = kinds[it.drop], x = a.x, y = a.y, ai = 0 }, x + 4, y + 4, frame or 0)
  elseif game and game.drawItemIcon then
    game:drawItemIcon(it.icon, x, y)
  end
  local s = tostring(it.cost)
  local px = x + 8 - #s * 4
  for i = 1, #s do
    local ch = M.DIGIT[tonumber(s:sub(i, i))]
    if ch then spr:oam(px + (i - 1) * 8, y + 16, ch, 0x02, 0) end
  end
  return true
end

return M
