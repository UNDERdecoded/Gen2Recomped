-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- OVERWORLD ACTORS (round 10): what a cut / lifted bush or rock holds
-- besides items -- soldiers 0x41/0x42, the bee 0x79, the hoarder 0x3E, the
-- cucco 0x0B (zelda3 Sprite_SpawnSecret 0x868264) -- live on the overworld
-- through the room actors' code (Actors.lua) over an adapter that answers
-- the room questions (walls, level, tags) from the overworld's attributes.
-- They are dropped when Link leaves the area or goes indoors (the SNES
-- clears its sprite slots on an area change). Installed into Game.

local Actors = require("src.zelda.alttp.Actors")

local M = {}

-- the "inside" the actor code asks: walls from the overworld attributes
local function adapter(game)
  local O = require("src.zelda.alttp.Overworld")
  return {
    lower = false, hdr = {}, mem = { taken = {}, doors = {} }, locks = {},
    blocked = function(_, x, y)
      local at = game.ow:attrAt(game.link.world, x, y)
      return O.isSolid(at) or O.LEDGE[at] ~= nil
    end,
  }
end

function M.install(G)
  -- the area's sprite graphics and palette set (overworld_sprite_gfx /
  -- overworld_sprite_palettes per screen; Light World by story phase)
  function G:owSpriteSet()
    local t = self.data.t
    if not (t and t.owSprGfxDW and self.area) then return nil end
    local s = self.area.parent or 0
    local dark = s >= 64
    local gfxTab = dark and t.owSprGfxDW or t.owSprGfxLW[math.min(3, self:storyProgress()) + 1]
    local gfx = gfxTab and gfxTab[(s % 64) + 1]
    -- r15: the sprite palette set is the per-phase RAM table 0x02002DC0
    -- (cached as owBgPalLW / owBgPalDW, misnamed); 0x14C8E8 is the BG's
    local palTab = dark and t.owBgPalDW or (t.owBgPalLW and t.owBgPalLW[math.min(3, self:storyProgress()) + 1])
    local pal = palTab and palTab[(s % 64) + 1]
    return gfx, pal
  end

  function G:owActorList()
    local oa = self.owActors
    if not oa or oa.areaKey ~= (self.area and self.area.parent) or oa.world ~= self.link.world then
      oa = Actors.new(self)
      oa.inside = adapter(self)
      oa.room = -1
      oa.areaKey = self.area and self.area.parent
      oa.world = self.link.world
      oa.cleared = true
      self.owActors = oa
    end
    return oa
  end

  function G:spawnOwActor(t, x, y)
    return self:owActorList():spawnSecret(t, x, y, false)
  end

  -- one overworld frame of the actors (called before Link moves)
  function G:updateOwActors()
    local oa = self.owActors
    if not oa then return end
    if oa.areaKey ~= (self.area and self.area.parent) or oa.world ~= self.link.world then
      self.owActors = nil
      return
    end
    oa:update()
    local live = false
    for _, a in ipairs(oa.list) do if not a.dead then live = true break end end
    -- r28: a sprite still dying (its puff's prize / an Octoballoon's
    -- babies land in this list) keeps the list
    if not live and not require("src.zelda.alttp.Effects").dying(self) then self.owActors = nil end
  end

  function G:drawOwActors(cx, cy, spr)
    local oa = self.owActors
    if not (oa and spr) then return end
    for _, a in ipairs(oa.list) do
      if not a.dead and not (a.inv and a.inv > 0 and a.inv % 4 < 2) then
        if spr:hasShadow(a.type) then spr:drawShadow(a.x - cx, a.y - cy, a.type) end
        spr:drawActor(a, a.x - cx, a.y - (a.z or 0) - cy, self.frame, -1)
      end
    end
    -- r21: the death puffs outdoors (Effects.lua)
    require("src.zelda.alttp.Effects").drawPuffs(self, spr, cx, cy)
  end
end

return M
