-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- LINK'S ITEMS (round 18): the GBA's item button, the bow and its arrows,
-- bombs, the lamp and the torches, and the per-palace keys. The routines are
-- the SNES ones the GBA keeps (zelda3 names); every table is the GBA's own
-- copy, read from the ROM at import (offsets below, located by value with
-- r18/py/tabfind.py / maptab.py: char tables come with the GBA's 32-wide OBJ
-- rows, small offset tables as int16).
--
-- The buttons. The GBA moves the SNES Y item to A and the SNES A action
-- (lift, talk, open, read, dash) to R: 0x0806995C copies GBA A into the
-- item byte (+0x53E/+0x53A) and R into the action byte (+0x53F/+0x539) in
-- the default control mode, and the cartridge's own messages say so: their
-- button glyph codes are 0x5B (R: "press R to lift / open / talk", "dash"),
-- 0x5C (B: the sword), 0x5D (L: the map) and 0x5E (A: "press A to light
-- torches", "throw it using A"); SELECT + L + R leaves sleep mode.
--
--   Link_HandleYItem      the chosen menu slot -> the item routine
--   LinkItem_Bow          kBowDelays {3, 3, 8}: Link halts, the arrow
--                         leaves on the third step if he has arrows
--   AncillaAdd_Arrow      kShootBow_X/Y (int16), Xvel/Yvel (+-48 = 3 px)
--   Ancilla09_Arrow       waits 4 frames, flies; a sprite (1 x 1 point box
--                         kAncilla_HitBox[dir | 4]) takes damage class 6
--                         (kAncilla_Damage[9]) and holds the arrow; a wall
--                         (kAncilla_CheckTileColl0 probe, kAncilla_TileColl0
--                         _Attrs class 1/2) stops it, pulled in by kArrow_X/Y
--   Ancilla0A_ArrowInTheWall  8 wobble steps of 2 frames, 128 frames, gone
--   Arrow_Draw            kArrow_Draw_Char/Flags (GBA pairs), X/Y
--   LinkItem_Bombs, AncillaAdd_Bomb  kBomb_Place_X0/Y0 (a wall in the
--                         way) or X1/Y1, two bombs at most
--   Ancilla07_Bomb        kBomb_Tab0 (fuse 0xA0, then 10 explosion steps);
--                         steps 1-8 hurt sprites (48 x 48, damage class 8)
--                         and Link (32 x 32, kBomb_Dmg_ToLink); step 7
--                         breaks walls (Bomb_CheckForDestructibles: door
--                         types 0x28 / 0x2A / 0x2E indoors,
--                         Overworld_BombTiles32x32 outdoors: bushes and the
--                         secret 0x86 -> map16 0xDB4 / 0xDB5, the cave)
--   Bomb_Draw, AncillaDraw_Explosion  kBomb_Draw_Tab0/Tab2, the explosion
--                         char/flags, XY (int16) and size tables
--   LinkItem_Lamp         costs kLinkItem_MagicCosts[6 * 3] magic (else
--                         message 123); AncillaAdd_MagicPowder's probe in
--                         front of Link lights a torch (attribute 0xC0 + n,
--                         Dungeon_LightTorch); the flame (Ancilla2F, 23
--                         frames, kLampFlame_Draw tables)
--   torches               the room's torch list (ROM 0x1635D2, the new-game
--                         copy of dung_torch_data), drawn with the object
--                         tile data's words 0xEC2 / 0xECA (GBA base
--                         0x164520); a lit torch burns 0xC0 * 4 frames
--                         (dung_torch_timers); tags 0x33 (torch door) and
--                         0x3E (torch chest) want 4 lit
--   damage                kEnemyDamages[class * 8 + enemy_damage_data[type *
--                         16 + class]] (the GBA keeps enemy_damage_data
--                         unpacked at 0x17D924)
--   keys                  link_num_keys is the current palace's; the others
--                         are kept per palace (the castle and the sewers
--                         share); the big key is per palace (kUpperBitmasks),
--                         a big-key door (type 0x1E) and a big chest want it
--                         (message 122 at the door)
--
-- OURS (docs/zelda/alttp.md "Items (round 18)"): Link's bow and lamp poses
-- and the bow sprite are not drawn (he stands);
-- the bomb's knockback uses the nearest entry of its speed table (r20: a
-- bomb can be lifted and thrown, Carry.lua; its flight is the pot's arc); arrows
-- test the walls of Link's level only; the dark room's light with lit
-- torches is a 74 / 87 / 100 % brightness for 1 / 2 / 3 torches (the
-- cartridge's fixed colour 8 / 4 / 0 of 31); bomb floors are not broken;
-- the sound effects.

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift
local Link = require("src.zelda.alttp.Link")

local IT = {}

IT.OFF = {
  damageSub = 0x17D924,   -- enemy_damage_data, 243 types x 16 classes
  ancDamage = 0x171FAF,   -- kAncilla_Damage (57)
  tileAttrs = 0x1719F8,   -- kAncilla_TileColl0_Attrs (256)
  collX = 0x171B0C, collY = 0x171AF8,         -- kAncilla_CheckTileColl0_X/Y (20, s8)
  hbX = 0x171D17, hbW = 0x171D23, hbY = 0x171D2F, hbH = 0x171D3B,   -- kAncilla_HitBox (12)
  bowDelays = 0x169084,   -- kBowDelays (3)
  shootYv = 0x16E52A, shootXv = 0x16E52E,     -- kShootBow_Yvel / Xvel (s8)
  shootY = 0x16E532, shootX = 0x16E53A,       -- kShootBow_Y / X (int16)
  arrowY = 0x17F3BC, arrowX = 0x17F3C4,       -- kArrow_Y / X (int16, the pull into a wall)
  arrowCF = 0x17F3CC,     -- kArrow_Draw_Char / Flags as GBA pairs (48)
  arrowYX = 0x17F42C,     -- kArrow_Draw_Y / X as int16 pairs (48)
  bombDmgSpeed = 0x17F560, bombDmgZvel = 0x17F570, bombDmgDelay = 0x17F580,
  bombToLink = 0x17F590,  -- kBomb_Dmg_ToLink (3)
  bombTab0 = 0x17F593,    -- kBomb_Tab0 (11)
  bombDrawTab0 = 0x17F59E, -- kBomb_Draw_Tab0 (12)
  explCF = 0x17F5AA,      -- kBomb_DrawExplosion_CharFlags (54 pairs)
  explXY = 0x17F616,      -- kBomb_DrawExplosion_XY (108, int16)
  explExt = 0x17F6EE,     -- kBomb_DrawExplosion_Ext (54)
  bombDrawTab2 = 0x17F72D, -- kBomb_Draw_Tab2 (11)
  placeY1 = 0x16E54C, placeX1 = 0x16E554, placeY0 = 0x16E55C, placeX0 = 0x16E564,   -- int16
  magicCosts = 0x1690F5,  -- kLinkItem_MagicCosts (27)
  flameChar = 0x17EF00, flameY = 0x17EF0C, flameX = 0x17EF24,   -- kLampFlame_Draw (12; Y int16)
  lampY = 0x16E164, lampX = 0x16E16C,         -- kLampFlame_Y / X (int16)
  powderY = 0x17F278, powderX = 0x17F280,     -- kMagicPower_Y / X (int16)
  torches = 0x1635D2,     -- dung_torch_data, new game (0x120 bytes)
  tileData = 0x164520,    -- the room object tile data (SNES SrcPtr base)
}
IT.MSG_BIG_KEY, IT.MSG_NO_MAGIC = 122, 123   -- BMG = SNES numbers here (plain text checked)

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end

function IT.extract(rom, R, check)
  local O = IT.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local u16 = function(o, n) return rom:bytesU16(o, n) end
  local t = {
    damageSub = u8(O.damageSub, 243 * 16), ancDamage = u8(O.ancDamage, 57),
    tileAttrs = u8(O.tileAttrs, 256), collX = s8(u8(O.collX, 20)), collY = s8(u8(O.collY, 20)),
    hbX = s8(u8(O.hbX, 12)), hbY = s8(u8(O.hbY, 12)), hbW = u8(O.hbW, 12), hbH = u8(O.hbH, 12),
    bowDelays = u8(O.bowDelays, 3),
    shootXv = s8(u8(O.shootXv, 4)), shootYv = s8(u8(O.shootYv, 4)),
    shootX = s16(u16(O.shootX, 4)), shootY = s16(u16(O.shootY, 4)),
    arrowX = s16(u16(O.arrowX, 4)), arrowY = s16(u16(O.arrowY, 4)),
    arrowCF = u8(O.arrowCF, 96), arrowYX = s16(u16(O.arrowYX, 96)),
    bombDmgSpeed = u8(O.bombDmgSpeed, 16), bombDmgZvel = u8(O.bombDmgZvel, 16),
    bombDmgDelay = u8(O.bombDmgDelay, 16), bombToLink = u8(O.bombToLink, 3),
    bombTab0 = u8(O.bombTab0, 11), bombDrawTab0 = u8(O.bombDrawTab0, 12), bombDrawTab2 = u8(O.bombDrawTab2, 11),
    explCF = u8(O.explCF, 108), explXY = s16(u16(O.explXY, 108)), explExt = u8(O.explExt, 54),
    placeX0 = s16(u16(O.placeX0, 4)), placeY0 = s16(u16(O.placeY0, 4)),
    placeX1 = s16(u16(O.placeX1, 4)), placeY1 = s16(u16(O.placeY1, 4)),
    magicCosts = u8(O.magicCosts, 27),
    flameChar = u8(O.flameChar, 12), flameY = s16(u16(O.flameY, 12)), flameX = s8(u8(O.flameX, 12)),
    lampX = s16(u16(O.lampX, 4)), lampY = s16(u16(O.lampY, 4)),
    powderX = s16(u16(O.powderX, 4)), powderY = s16(u16(O.powderY, 4)),
    torchUnlit = u16(O.tileData + 0xEC2, 4), torchLit = u16(O.tileData + 0xECA, 4),
    torches = {},
  }
  -- the torch table: room, positions..., 0xFFFF, in 0x120 bytes
  local i = 0
  while i < 0x120 do
    local room = rom:u16(O.torches + i); i = i + 2
    local list = {}
    while i < 0x120 do
      local p = rom:u16(O.torches + i); i = i + 2
      if p == 0xFFFF then break end
      list[#list + 1] = p
    end
    if room ~= 0xFFFF and room < 0x200 and #list > 0 then t.torches[room + 1] = list end
  end
  -- structural checks (shapes, not the data)
  check(t.bowDelays[1] == t.bowDelays[2] and t.bowDelays[3] > t.bowDelays[1]
        and t.shootXv[3] == -t.shootXv[4] and t.shootYv[1] == -t.shootYv[2] and t.shootXv[1] == 0,
        "bow tables")
  check(t.bombTab0[1] > 0x40 and t.bombDrawTab2[1] == 1 and t.placeX1[3] < 0 and t.placeY0[2] > t.placeY0[1],
        "bomb tables")
  check(t.ancDamage[9 + 1] == 6 and t.ancDamage[7 + 1] == 8 and t.magicCosts[1] > t.magicCosts[2],
        "ancilla damage / magic cost tables")
  check(t.torches[0x99 + 1] ~= nil and #t.torches[0x99 + 1] == 3, "torch table")
  return t
end

-- ------------------------------------------------------------- helpers

local function tabs(game) return game.data.roomIdx and game.data.roomIdx.items end
IT.tabs = tabs

-- damage of class `cls` to sprite type `type` (Sprite_ApplyCalculatedDamage)
function IT.damage(game, cls, type)
  local T, cb = tabs(game), game.data.roomIdx.combat
  if not (T and cb) then return 2 end
  local sub = T.damageSub[type * 16 + cls + 1] or 0
  return cb.enemyDamage[cls * 8 + sub + 1] or 0
end

-- the palace key slot of the room Link is in (the castle and the sewers
-- share theirs), or nil outdoors / in a cave
function IT.palaceOf(game)
  local ent = game.interior and game.interior.entrance
  local p = ent and ent.palace or 0xFF
  if p == 0xFF then return nil end
  if p == 2 then p = 0 end
  return p
end

-- the GBA grid slot of the chosen item -> the item routine
IT.SLOT = { [1] = "bow", [4] = "bombs", [13] = "lamp", [17] = "book" }   -- r23: the book (Desert.lua)

local function dirIndex(facing) return math.floor((facing or 0) / 2) end

-- ------------------------------------------------------------- install

function IT.install(G)
  -- the big key of the palace Link is in (the castle's: progress.bigKey.castle)
  function G:hasBigKey()
    local bk = self.progress.bigKey or {}
    local p = IT.palaceOf(self)
    if p == nil then return false end
    if p == 0 and bk.castle then return true end
    return bk[p] == true or bk[tostring(p)] == true
  end

  -- keys per palace: the counter is the current palace's (link_num_keys);
  -- entering another palace stores it and loads that palace's
  local syncKeys = G.syncKeys
  function G:syncKeys()
    local p = IT.palaceOf(self)
    local pr = self.progress
    if p ~= nil then
      pr.keysBy = pr.keysBy or {}
      if pr.keyPalace == nil then pr.keyPalace = p end
      if pr.keyPalace ~= p then
        pr.keysBy[tostring(pr.keyPalace)] = pr.keys or 0
        pr.keys = pr.keysBy[tostring(p)] or 0
        pr.keyPalace = p
      end
    end
    return syncKeys(self)
  end

  local getItem = G.getItem
  function G:getItem(id)
    local p = IT.palaceOf(self)
    if id == 0x32 and p ~= nil and p ~= 0 then
      -- a palace's big key (the castle's stays progress.bigKey.castle)
      self.progress.bigKey = self.progress.bigKey or {}
      self.progress.bigKey[tostring(p)] = true
      self.itemLog = self.itemLog or {}
      self.itemLog[#self.itemLog + 1] = { id = id, room = self.interior and self.interior.room }
      return self:syncKeys()
    end
    return getItem(self, id)
  end

  -- the chosen item (the menu's slot; 0x080A9E38: kept if owned, else the next owned)
  function G:yItem()
    local Menu = require("src.zelda.alttp.Menu")
    local inv = Menu.inventory(self)
    local function owned(s) return (inv[0x1F + s] or 0) ~= 0 end
    local cur = self.progress.curItem or 0
    if cur < 1 or not owned(cur) then
      local c = (cur < 1) and 0 or cur
      cur = 0
      for _ = 1, 24 do
        c = c + 1
        if c > 24 then c = 1 end
        if owned(c) and c ~= 6 and c ~= 12 and c ~= 18 and c ~= 24 then cur = c break end
      end
      if cur > 0 then self.progress.curItem = cur end
    end
    return IT.SLOT[cur], cur
  end

  -- one frame of the item button (A); true while it holds Link
  function G:itemFrame(inp)
    local T = tabs(self)
    if not T then return false end
    local lk = self.link
    local bu = self.bowUse
    if bu then
      -- LinkItem_Bow: the delay counts down; each underflow is a step
      bu.delay = bu.delay - 1
      if bu.delay >= 0 then return true end
      bu.step = bu.step + 1
      bu.delay = T.bowDelays[bu.step + 1] or 0
      if bu.step ~= 3 then return true end
      self.bowUse = nil
      if (self.stats.arrows or 0) > 0 then
        self.stats.arrows = self.stats.arrows - 1
        self:addArrow()
      end
      return true
    end
    if not inp.y then return false end
    if (lk.doorway or 0) ~= 0 or self.carry then return false end
    local item = self:yItem()
    self.itemPresses = (self.itemPresses or 0) + 1
    if item == "bow" then
      self.bowUse = { step = 0, delay = T.bowDelays[1] }
      lk.steps = 0
      return true
    elseif item == "bombs" then
      self:addBomb()
      return false
    elseif item == "lamp" then
      self:useLamp()
      return false
    end
    return false
  end

  -- the ancillae list
  local function list(self)
    self.anc = self.anc or {}
    return self.anc
  end

  function G:addArrow()
    local T = tabs(self)
    local lk = self.link
    local j = dirIndex(lk.facing)
    local a = { kind = "arrow", dir = j, x = lk.x + T.shootX[j + 1], y = lk.y + 8 + T.shootY[j + 1],
                vx = T.shootXv[j + 1], vy = T.shootYv[j + 1], sx = 0, sy = 0, itl = 8,
                lower = self.interior and (self.interior.lower or false) or false,
                indoors = self.interior ~= nil }
    local l = list(self)
    l[#l + 1] = a
    self.arrowsShot = (self.arrowsShot or 0) + 1
    return a
  end

  function G:addBomb()
    local T = tabs(self)
    if (self.stats.bombs or 0) <= 0 then return nil end
    local n = 0
    for _, a in ipairs(list(self)) do if a.kind == "bomb" then n = n + 1 end end
    if n >= 2 then return nil end
    self.stats.bombs = self.stats.bombs - 1
    local lk = self.link
    local j = dirIndex(lk.facing)
    local x, y = lk.x + T.placeX1[j + 1], lk.y + T.placeY1[j + 1]
    -- Ancilla_CheckInitialTileCollision_Class2: a wall where the bomb would go
    if self:ancWall(x, y, j, true) then x, y = lk.x + T.placeX0[j + 1], lk.y + T.placeY0[j + 1] end
    local a = { kind = "bomb", dir = j, x = x, y = y, itl = 0, t = T.bombTab0[1], z = 0,
                lower = self.interior and (self.interior.lower or false) or false,
                indoors = self.interior ~= nil }
    local l = list(self)
    l[#l + 1] = a
    self.bombsPlaced = (self.bombsPlaced or 0) + 1
    return a
  end

  -- the tile collision class of an ancilla's probe (kAncilla_TileColl0_Attrs)
  function G:ancAttr(x, y)
    if self.interior then return self.interior:attrAt(x, y) or 0 end
    return self.ow:attrAt(self.link.world, x, y) or 0
  end
  function G:ancWall(x, y, j, fresh)
    local T = tabs(self)
    local k = j + (fresh and 4 or 4)
    local px, py = x + T.collX[k + 1], y + T.collY[k + 1]
    local c = T.tileAttrs[self:ancAttr(px, py) + 1] or 0
    return c == 1 or c == 2, px, py
  end

  function G:useLamp()
    local T = tabs(self)
    local lk = self.link
    -- LinkCheckMagicCost(6): a = magic; a && (a -= cost) < 0x80
    local cost = T.magicCosts[6 * 3 + 1]
    local m = self.stats.magic or 0
    if m == 0 or m - cost < 0 then
      self:showMessage(IT.MSG_NO_MAGIC)
      self.lampRefused = (self.lampRefused or 0) + 1
      return false
    end
    self.stats.magic = m - cost
    local j = dirIndex(lk.facing)
    -- AncillaAdd_MagicPowder's probe: Link + kMagicPower_X/Y, then the tile
    -- under kAncilla_CheckTileColl0_X/Y[dir]
    local px = lk.x + T.powderX[j + 1] + T.collX[j + 1]
    local py = lk.y + T.powderY[j + 1] + T.collY[j + 1]
    local at = self:ancAttr(px, py)
    if self.interior and band(at, 0xF0) == 0xC0 then self:lightTorch(band(at, 0x0F)) end
    local l = list(self)
    l[#l + 1] = { kind = "flame", dir = j, x = lk.x + T.lampX[j + 1], y = lk.y + T.lampY[j + 1], t = 23,
                  lower = self.interior and (self.interior.lower or false) or false }
    self.lampUses = (self.lampUses or 0) + 1
    return true
  end

  -- ---------------------------------------------------------- torches
  function G:roomTorches()
    local inside = self.interior
    if not inside then return nil end
    if inside.torches and inside.torchRoom == inside.room then return inside.torches end
    local T = tabs(self)
    local out = {}
    inside.torches, inside.torchRoom, inside.torchDown = out, inside.room, nil
    local list = T and T.torches[inside.room + 1]
    if not list then return out end
    for i, pos in ipairs(list) do
      local cell = band(rshift(band(pos, 0x3FFF), 1), 0xFFF)
      local tc = { index = i - 1, cell = cell, lit = band(pos, 0x8000) ~= 0, timer = 0 }
      out[#out + 1] = tc
      local attr = 0xC0 + band(i - 1, 15)
      for _, d in ipairs({ 0, 1, 64, 65 }) do
        inside.attrs[cell + d] = attr; inside.grid[cell + d] = true
      end
      self:drawTorch(tc)
    end
    return out
  end

  function G:drawTorch(tc)
    local T = tabs(self)
    local inside = self.interior
    local w = tc.lit and T.torchLit or T.torchUnlit
    inside.patch[tc.cell] = w[1]; inside.patch[tc.cell + 64] = w[2]
    inside.patch[tc.cell + 1] = w[3]; inside.patch[tc.cell + 65] = w[4]
    self.roomImages = nil
  end

  function G:litTorches()
    local n = 0
    for _, tc in ipairs(self:roomTorches() or {}) do if tc.lit then n = n + 1 end end
    return n
  end

  function G:lightTorch(i)
    for _, tc in ipairs(self:roomTorches() or {}) do
      if tc.index == i and not tc.lit then
        tc.lit, tc.timer = true, (self.interior.room == 0) and 0x80 or 0xC0
        self:drawTorch(tc)
        self.torchesLit = (self.torchesLit or 0) + 1
        return true
      end
    end
    return false
  end

  -- Dungeon_ProcessTorchesAndDoors: every 4th frame the timers run down
  function G:torchFrame()
    if band(self.frame, 3) ~= 0 then return end
    for _, tc in ipairs(self:roomTorches() or {}) do
      if tc.lit and tc.timer > 0 then
        tc.timer = tc.timer - 1
        if tc.timer == 0 and self.interior.room ~= 0 then tc.lit = false; self:drawTorch(tc) end
      end
    end
  end

  -- room tags 0x33 (RoomTag_TorchPuzzleDoor) and 0x3E (RoomTag_TorchPuzzleChest)
  function G:torchTags()
    local inside = self.interior
    local hdr = inside.hdr or {}
    local lit = self:litTorches()
    inside.mem.tagDone = inside.mem.tagDone or {}
    for slot, tag in ipairs({ hdr[6] or 0, hdr[7] or 0 }) do
      if tag == 0x33 then
        local down = lit < 4
        if down ~= inside.torchDown then
          inside.torchDown = down
          if down then self:closeShutters() else self:openShutters() end
        end
      elseif tag == 0x3E and not inside.mem.tagDone[slot] and lit >= 4 then
        inside.mem.tagDone[slot] = true
        inside.mem.chestShown = true
        if inside.revealChests then inside:revealChests() end
        self.roomImages = nil
      end
    end
  end

  -- the dark room with lit torches (kLitTorchesColorPlus 31 / 8 / 4 / 0)
  local darkFactor = G.darkFactor
  function G:darkFactor()
    local d = darkFactor(self)
    if d == nil then return nil end
    local lit = self:litTorches()
    if lit >= 3 then return nil end
    if lit == 2 then return 1 - 4 / 31 end
    if lit == 1 then return 1 - 8 / 31 end
    return d
  end

  -- -------------------------------------------------------- the frame
  function G:updateAncillae()
    local inside = self.interior
    if inside ~= self.ancRoom or (inside and inside.room) ~= self.ancRoomId then
      self.ancRoom, self.ancRoomId = inside, inside and inside.room
      self.anc = {}
      self.bowUse = nil
    end
    if inside then
      self:roomTorches()
      self:torchFrame()
      self:torchTags()
    else
      self:applyOwBombs()
    end
    local l = self.anc
    if not l or #l == 0 then return end
    local keep = {}
    for _, a in ipairs(l) do
      if a.kind == "arrow" then self:arrowFrame(a)
      elseif a.kind == "stuck" then self:stuckFrame(a)
      elseif a.kind == "bomb" then self:bombFrame(a)
      elseif a.kind == "flame" then a.t = a.t - 1; if a.t <= 0 then a.gone = true end
      end
      if not a.gone then keep[#keep + 1] = a end
    end
    self.anc = keep
  end

  local function actorsHere(self)
    if self.interior then return self.actors end
    return self.owActors
  end

  local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
  end

  function G:arrowFrame(a)
    local T = tabs(self)
    a.itl = a.itl - 1
    if a.itl >= 0 then
      if a.itl >= 4 then return end
    else
      a.itl = -1
    end
    -- Ancilla_MoveY / MoveX: 1/16 px
    a.sy = a.sy + a.vy * 16; a.sx = a.sx + a.vx * 16
    local my = (a.sy >= 0) and math.floor(a.sy / 256) or -math.floor(-a.sy / 256)
    local mx = (a.sx >= 0) and math.floor(a.sx / 256) or -math.floor(-a.sx / 256)
    a.sy, a.sx = a.sy - my * 256, a.sx - mx * 256
    a.y, a.x = a.y + my, a.x + mx
    -- sprites (Ancilla_CheckSpriteCollision: 1 x 1 at kAncilla_HitBox[dir | 4])
    local k = a.dir + 4
    local hx, hy = a.x + T.hbX[k + 1], a.y + T.hbY[k + 1]
    local acts = actorsHere(self)
    local Actors = require("src.zelda.alttp.Actors")
    local cb = self.data.roomIdx.combat
    if acts then
      for _, s in ipairs(acts.list) do
        if not s.dead and (s.lower or false) == (a.lower or false) and Actors.fights(s.type) then
          local bx, by, bw, bh = Actors.hitbox(cb, s)
          if overlap(hx, hy, 1, 1, bx, by - (s.z or 0), bw, bh) then
            local RX, RY = { [0] = 0, 0, -64, 64 }, { [0] = -64, 64, 0, 0 }
            acts:swordHit(hx, hy, 1, 1, { cls = 6, arrow = true, lower = a.lower,
                                          rvx = RX[a.dir], rvy = RY[a.dir],
                                          dmg = function(t) return IT.damage(self, 6, t) end })
            self.arrowHits = (self.arrowHits or 0) + 1
            a.kind, a.itl, a.aux, a.on = "stuck", 0, 1, s
            a.ox, a.oy = a.x - s.x, a.y - s.y + (s.z or 0)
            return
          end
        end
      end
    end
    -- walls
    local wall = self:ancWall(a.x, a.y, a.dir, true)
    if wall then
      a.x, a.y = a.x + T.arrowX[a.dir + 1], a.y + T.arrowY[a.dir + 1]
      a.kind, a.itl, a.aux = "stuck", 0, 1
      self.arrowWalls = (self.arrowWalls or 0) + 1
      return
    end
    -- off the screen (both OAM entries at y 0xF0)
    local cx, cy = self:ancCamera()
    local sx, sy = a.x - cx, a.y - cy
    if sx < -16 or sx > (self.viewW or 240) + 16 or sy < -16 or sy > (self.viewH or 160) + 16 then a.gone = true end
  end

  function G:ancCamera()
    if self.interior then return self.interior:camera(self.link.x, self.link.y, 240, 160) end
    return self.cam.x, self.cam.y
  end

  -- Ancilla0A_ArrowInTheWall
  function G:stuckFrame(a)
    local s = a.on
    if s then
      if s.dead then a.gone = true return end
      a.x, a.y = s.x + a.ox, s.y + a.oy - (s.z or 0)
    end
    a.aux = a.aux - 1
    if a.aux == 0 then
      a.aux = 2
      a.itl = a.itl + 1
      if a.itl == 9 then a.gone = true
      elseif band(a.itl, 8) ~= 0 then a.aux = 0x80 end
    end
  end

  function G:bombFrame(a)
    local T = tabs(self)
    -- r20: lifted (Carry.lua): it rides above Link's head; thrown: it flies
    -- (the pot's arc, OURS) until it lands or meets a wall
    if a.held then
      local c = self.carry
      local x, y
      if self.carriedPos then x, y = self:carriedPos() end
      if c and c.obj and c.obj.bomb == a and x then
        local Cy = require("src.zelda.alttp.Carry")
        a.x, a.y, a.z = x + 8, y + 8 + Cy.HELD_Z, Cy.HELD_Z
      else
        a.held = nil
      end
    elseif a.fly then
      local Cy = require("src.zelda.alttp.Carry")
      local f = a.fly
      f.zv = f.zv - Cy.GRAVITY
      a.z = (a.z or 0) + f.zv
      local nx, ny = a.x + f.vx, a.y + f.vy
      if self:carryBlocked(nx, ny + 4) then f.vx, f.vy = 0, 0 else a.x, a.y = nx, ny end
      if a.z <= 0 then a.z, a.fly = 0, nil; self.bombLandings = (self.bombLandings or 0) + 1 end
    end
    -- Bomb_CheckSpriteAndPlayerDamage: steps 1-8
    if a.itl >= 1 and a.itl <= 8 then self:bombDamage(a) end
    a.t = a.t - 1
    if a.t <= 0 then
      a.itl = a.itl + 1
      if a.itl == 1 then self.explosions = (self.explosions or 0) + 1 end
      if a.itl == 11 then a.gone = true return end
      a.t = T.bombTab0[a.itl + 1]
    end
    if a.itl == 7 and a.t == 2 then self:bombDestroy(a) end
  end

  function G:bombDamage(a)
    local T = tabs(self)
    local acts = actorsHere(self)
    local Actors = require("src.zelda.alttp.Actors")
    -- sprites: a 48 x 48 box round the bomb (each sprite every 4th frame)
    if acts then
      for idx, s in ipairs(acts.list) do
        if not s.dead and band(bit.bxor(idx, self.frame), 3) == 0 and (s.lower or false) == (a.lower or false) then
          local px, py = Actors.project(a.x - 8, a.y - 8, s.x, s.y, 64)
          acts:swordHit(a.x - 24, a.y - 24 - (a.z or 0), 48, 48,
                        { cls = 8, bomb = true, lower = a.lower, rvx = px, rvy = py, only = s,
                          dmg = function(t) return IT.damage(self, 8, t) end })
        end
      end
    end
    -- Link: 32 x 32 against his 16 x 24
    local lk = self.link
    if (self.blink or 0) > 0 or self.recoil then return end
    if self.interior and (self.interior.lower or false) ~= (a.lower or false) then return end
    if overlap(lk.x, lk.y, 16, 24, a.x - 16, a.y - 16, 32, 32) then
      self:hurtLink(T.bombToLink[1], a.x, a.y)
      if self.recoil then
        local vx, vy = Actors.project(a.x - 8, a.y - 12, lk.x, lk.y, T.bombDmgSpeed[1])
        self.recoil.vx, self.recoil.vy, self.recoil.t = vx, vy, T.bombDmgDelay[1]
      end
      self.bombHurt = (self.bombHurt or 0) + 1
    end
  end

  -- Bomb_CheckForDestructibles
  function G:bombDestroy(a)
    if self.interior then
      local inside = self.interior
      local base = math.floor(band(a.y, 0x1F8) / 8) * 64 + math.floor(band(a.x, 0x1F8) / 8) - 0x82
      for r = 0, 2 do
        for c = 0, 2 do
          local cell = base + r * 64 + c * 2
          for _, l in ipairs(inside.locks) do
            local t = band(l.type or 0, 0xFE)
            if not l.open and (t == 0x28 or t == 0x2A or t == 0x2E) then
              for _, lc in ipairs(l.cells) do
                if lc == cell then
                  inside:openLock(l)
                  inside.mem.doors[l.index] = true
                  self.roomImages = nil
                  self.wallsBombed = (self.wallsBombed or 0) + 1
                  return
                end
              end
            end
          end
        end
      end
      return
    end
    -- Overworld_BombTiles32x32: 3 x 3 tiles from ((x - 23) & ~7, (y - 20) & ~7)
    local x0, y0 = band(a.x - 23, bit.bnot(7)), band(a.y - 20, bit.bnot(7))
    for r = 0, 2 do
      for c = 0, 2 do
        self:bombTile(x0 + c * 16, y0 + r * 16)
      end
    end
  end

  function G:bombTile(x, y)
    local O = require("src.zelda.alttp.Overworld")
    if self:owTileChange(x, y, G.SWORD_CUT) then
      local Drops = require("src.zelda.alttp.Drops")
      local kind = Drops.CUT_KIND[self.lastCutFrom] or 2
      local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
      self:terrainDrop(kind, self.lastSecret, tx, ty)
      self:spawnDebris(kind, tx, ty)
      return
    end
    -- Overworld_RevealSecret: the secret 0x86 under the tile -> 0xDB4 + 0xDB5
    local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
    local screen = O.screenAt(self.link.world, tx, ty)
    if not screen then return end
    local area = self.ow:area(screen)
    local pos = math.floor((ty - area.y) / 16) * 128 + math.floor((tx - area.x) / 16) * 2
    local secrets = self.data.roomIdx.owSecrets and self.data.roomIdx.owSecrets[area.parent + 1]
    for _, sc in ipairs(secrets or {}) do
      if sc.pos == pos and sc.type == 0x86 then
        self.progress.owBombed = self.progress.owBombed or {}
        local key = self.link.world .. ":" .. tx .. ":" .. ty
        if not self.progress.owBombed[key] then
          self.progress.owBombed[key] = true
          self.cavesOpened = (self.cavesOpened or 0) + 1
        end
        self:owSetMap16(tx, ty, 0xDB4)
        self:owSetMap16(tx + 16, ty, 0xDB5)
        return
      end
    end
  end

  -- the caves opened by bombs stay open (save_ow_event_info |= 2)
  function G:applyOwBombs()
    local ob = self.progress.owBombed
    if not ob or self.owBombsApplied == self.link.world then return end
    self.owBombsApplied = self.link.world
    for key in pairs(ob) do
      local w, x, y = key:match("^(%a+):(%-?%d+):(%-?%d+)$")
      if w == self.link.world then
        self:owSetMap16(tonumber(x), tonumber(y), 0xDB4)
        self:owSetMap16(tonumber(x) + 16, tonumber(y), 0xDB5)
      end
    end
  end

  -- ---------------------------------------------------------- drawing
  function G:drawAncillae(cx, cy, spr)
    local l = self.anc
    if not (l and #l > 0 and spr) then return end
    local T = tabs(self)
    local Layers = require("src.zelda.alttp.Layers")
    for _, a in ipairs(l) do
      if not (self.inPrioPass and self.interior and not self:inPrioPass(Layers.spritePrio(self.data, a.lower))) then
        local x, y = a.x - cx, a.y - cy
        if a.kind == "arrow" or a.kind == "stuck" then
          -- Arrow_Draw
          local j = a.dir
          if a.kind == "stuck" then
            j = j * 4 + 8 + ((band(a.itl, 8) ~= 0) and 1 or band(a.itl, 3))
          elseif a.itl >= 0 then
            j = bor(j, 4)
          end
          j = j * 2
          for i = 0, 1 do
            local ch, fl = T.arrowCF[(j + i) * 2 + 1], T.arrowCF[(j + i) * 2 + 2]
            if ch ~= 0xFF then
              spr:oam(x + T.arrowYX[(j + i) * 2 + 2], y + T.arrowYX[(j + i) * 2 + 1], ch, bor(band(fl, bit.bnot(0x3E)), 4), 0)
            end
          end
        elseif a.kind == "bomb" then
          -- Bomb_Draw / AncillaDraw_Explosion
          local frame = T.bombDrawTab0[a.itl + 1] * 6
          local n = T.bombDrawTab2[a.itl + 1]
          local r11 = 2
          if a.itl == 0 then r11 = (a.t < 0x20) and band(a.t, 0xE) or 4 end
          local base = frame
          for idx = 0, n - 1 do
            local f = frame + idx
            local ch = T.explCF[f * 2 + 1]
            if ch ~= 0xFF then
              local fl = bor(band(T.explCF[f * 2 + 2], bit.bnot(0x3E)), r11)
              local i = idx + base
              spr:oam(x + T.explXY[i * 2 + 2], y - (a.z or 0) + T.explXY[i * 2 + 1], ch, fl, T.explExt[f + 1])
            end
          end
        elseif a.kind == "flame" then
          -- Ancilla2F_LampFlame
          local j = rshift(band(a.t, 0xF8), 1)
          repeat
            local ch = T.flameChar[j + 1]
            if ch ~= 0xFF then spr:oam(x + T.flameX[j + 1], y + T.flameY[j + 1], ch, 2, 0) end
            j = j + 1
          until band(j, 3) == 0
        end
      end
    end
  end

  local drawDrops = G.drawDrops
  function G:drawDrops(cx, cy, spr)
    drawDrops(self, cx, cy, spr)
    self:drawAncillae(cx, cy, spr)
  end
end

return IT
