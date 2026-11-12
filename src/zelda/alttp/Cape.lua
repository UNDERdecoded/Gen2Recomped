-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MAGIC CAPE AND THE BOTTLES (round 26, team A). zelda3 names, the
-- disassembly's constants (no GBA table was told apart by value):
--
--   LinkItem_Cape         with magic: link_cape_mode 1, the drain counter
--                         kCapeDepletionTimers[link_magic_consumption] {4, 8,
--                         8}: one magic point each time it runs out; at 0
--                         magic, or A again after link_bunny_transform_timer
--                         (20 frames), the cape comes off
--                         (Link_ForceUnequipCape); link_disable_sprite_damage
--                         while it is on; no magic: message 123.
--   LinkItem_Bottle       the chosen bottle (grid slots 6 / 12 / 18 / 24):
--                         3 red potion (health full; refused when full), 4
--                         green (magic full), 5 blue (both), 6 a fairy
--                         (ReleaseFairy); the bottle is empty (2) after.
--
-- OURS: Link is drawn at half alpha under the cape (the cartridge hides him
-- and keeps his shadow); the cape poof and sounds are not drawn; the
-- potions fill at once (the cartridge's refill counts up through Module 0E
-- submodules 4 / 8 / 9); the released fairy heals 7 hearts at once
-- (Sprite_E3_Fairy's own flight is not ported); bees are not released.

local CP = {}

CP.DEPLETE = { 4, 8, 8 }
CP.SLOT = 22
CP.BOTTLE_SLOTS = { [6] = 0x25, [12] = 0x2B, [18] = 0x31, [24] = 0x37 }
CP.MSG_NO_MAGIC = 123

local function inv(game) return require("src.zelda.alttp.Menu").inventory(game) end

function CP.install(G)
  local Items = require("src.zelda.alttp.Items")
  Items.SLOT[CP.SLOT] = "cape"

  -- the bottles can be chosen
  local yItem0 = G.yItem
  function G:yItem()
    local cur = self.progress.curItem or 0
    local b = CP.BOTTLE_SLOTS[cur]
    if b and (inv(self)[b] or 0) >= 2 then return "bottle", cur end
    return yItem0(self)
  end

  local itemFrame0 = G.itemFrame
  function G:itemFrame(inp)
    local c = self.cape
    if c then
      -- the drain
      c.ctr = c.ctr - 1
      if c.ctr <= 0 then
        c.ctr = CP.DEPLETE[1]
        self.stats.magic = math.max(0, (self.stats.magic or 0) - 1)
        if self.stats.magic == 0 then self.cape = nil; return false end
      end
      if c.t > 0 then c.t = c.t - 1 end
      if inp.y and c.t == 0 and self:yItem() == "cape" then self.cape = nil; self.capeOffs = (self.capeOffs or 0) + 1 end
      return itemFrame0(self, inp)
    end
    if inp.y and not self.bowUse and (self.link.doorway or 0) == 0 then
      local item, slot = self:yItem()
      if item == "cape" then
        if (self.stats.magic or 0) == 0 then self:showMessage(CP.MSG_NO_MAGIC); return false end
        self.cape = { ctr = CP.DEPLETE[1], t = 20 }
        self.capeUses = (self.capeUses or 0) + 1
        return false
      elseif item == "bottle" then
        CP.drink(self, slot)
        return false
      end
    end
    return itemFrame0(self, inp)
  end

  -- no damage under the cape (link_disable_sprite_damage)
  local hurt0 = G.hurtLink
  function G:hurtLink(dmg, fx, fy)
    if self.cape then return end
    return hurt0(self, dmg, fx, fy)
  end

  local drawLink0 = G.drawLink
  function G:drawLink(lk, tint)
    if lk == self.link and not tint and self.cape and love and love.graphics then
      love.graphics.setColor(1, 1, 1, 0.5)
      drawLink0(self, lk, tint)
      love.graphics.setColor(1, 1, 1, 1)
      return
    end
    return drawLink0(self, lk, tint)
  end
end

function CP.drink(game, slot)
  local b = CP.BOTTLE_SLOTS[slot]
  local v = inv(game)[b] or 0
  local s = game.stats
  local full = (s.health or 0) >= (s.healthMax or 24)
  local magicFull = (s.magic or 0) >= 0x80
  if v == 3 and not full then s.health = s.healthMax
  elseif v == 4 and not magicFull then s.magic = 0x80
  elseif v == 5 and not (full and magicFull) then s.health, s.magic = s.healthMax, 0x80
  elseif v == 6 then s.health = math.min(s.healthMax, (s.health or 0) + 7 * 8)
  else return false end
  game.progress.inv = game.progress.inv or {}
  game.progress.inv[b] = 2
  game.progress.inv[tostring(b)] = nil
  game.bottlesDrunk = (game.bottlesDrunk or 0) + 1
  return true
end

return CP
