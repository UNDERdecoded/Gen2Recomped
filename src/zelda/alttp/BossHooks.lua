-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- TEAM A'S ITEMS ON TEAM B'S BOSSES (round 26): the real item uses reach
-- the palace modules' entry points (zelda3 names):
--
--   the hammer        HelmasaurKing_CheckMaskDamageFromHammer: the hammer's
--                     action box against the king's box moved down 8 ->
--                     PalaceOfDarkness.hammerHit (health - 1, Link pushed).
--   the hookshot      Sprite_8D_Arrghi's sprite_B branch: a puff the hook
--                     meets rides the hook back -> SwampPalace.hookPuff,
--                     each frame at the hook, let go when it is in.
--   the Fire Rod      Ancilla_CheckDamageToSprite_preset class 11 /
--   / Bombos          Bombos 13 on Kholdstare's shell and eyes ->
--                     IcePalace.fireHit.
--   the rods          classes 11 / 12 on Trinexx's heads ->
--                     TurtleRock.rodHit.
--   the arrows        class 6, 9 with the silver bow (GBA bow byte 0x20 >= 3,
--                     receipt 0x3B) on Ganon -> Ganon.arrowHit.
--
-- OURS: the hammer box is Tools.lua's (16 x 16 at the tool point), once per
-- swing at its impact step.

local BH = {}

local function mod(name)
  local ok, m = pcall(require, "src.zelda.alttp." .. name)
  return ok and m or nil
end
local function isType(m, t) return m and m.TYPES and m.TYPES[t] end
local FIRE, ICE = 11, 12

-- a rod / tool ancilla hits sprite s (Tools.spriteHit)
function BH.toolHit(game, acts, s, cls, a)
  local swamp, ice, tr = mod("SwampPalace"), mod("IcePalace"), mod("TurtleRock")
  if a and a.kind == "hook" then
    if s.type == 0x8D and swamp and swamp.hookPuff then
      if not a.puff then
        a.puff = s
        swamp.hookPuff(acts, s, a.x, a.y)
        game.hookPuffs = (game.hookPuffs or 0) + 1
      end
      return true
    end
    return false
  end
  -- a part that refuses the hit (untouchable, flags3 0x40) lets the shot
  -- go on to the next sprite ("pass")
  if cls == FIRE and isType(ice, s.type) and ice.fireHit then
    return ice.fireHit(acts, s, ice.FIRE_ROD) and true or "pass"
  end
  if (cls == FIRE or cls == ICE) and isType(tr, s.type) and tr.rodHit then
    return tr.rodHit(acts, s, cls) and true or "pass"
  end
  return false
end

-- a medallion on sprite s (OwEvents.spellDamage)
function BH.spellHit(game, acts, s, cls, kind)
  local ice = mod("IcePalace")
  if kind == "bombos" and isType(ice, s.type) and ice.fireHit then
    ice.fireHit(acts, s, ice.BOMBOS)
    return true
  end
  return false
end

-- the hammer's impact (Tools.useFrame)
function BH.hammer(game, acts, x, y, w, h)
  local pod = mod("PalaceOfDarkness")
  if not (acts and pod and pod.hammerHit) then return end
  local Actors = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx.combat
  for _, a in ipairs(acts.list) do
    if a.type == 0x92 and not a.dead then
      local hx, hy, hw, hh = Actors.hitbox(cb, a)
      if Actors.overlapCart(x, y, w, h, hx, hy + 8 - (a.z or 0), hw, hh) and pod.hammerHit(acts, a) then
        game.maskHammers = (game.maskHammers or 0) + 1
      end
    end
  end
end

function BH.silver(game)
  local inv = require("src.zelda.alttp.Menu").inventory(game)
  return (inv[0x20] or 0) >= 3
end

function BH.install(G)
  local Tools = require("src.zelda.alttp.Tools")
  local EV = require("src.zelda.alttp.OwEvents")
  -- the bosses' parts the shared code does not fight with (the shell is
  -- BG-drawn) still meet the ancillae (Ancilla_CheckSpriteCollision: any
  -- sprite in state >= 9)
  local types = {}
  for _, n in ipairs({ "PalaceOfDarkness", "SwampPalace", "IcePalace", "TurtleRock", "Ganon" }) do
    local m = mod(n)
    for t in pairs(m and m.TYPES or {}) do types[t] = true end
  end
  Tools.bossTypes, EV.bossTypes = types, types
  Tools.bossHook = BH.toolHit
  Tools.hammerHook = BH.hammer
  EV.bossHook = BH.spellHit

  -- the puff rides the hook back
  local upd0 = G.updateAncillae
  function G:updateAncillae()
    upd0(self)
    local swamp = mod("SwampPalace")
    local keep = {}
    for _, a in ipairs(self.anc or {}) do if a.kind == "hook" and a.puff then keep[a] = true end end
    for a in pairs(keep) do
      if swamp and not a.puff.dead then swamp.hookPuff(self.actors, a.puff, a.x, a.y) end
    end
  end

  -- the arrows on Ganon (Ancilla_CheckDamageToSprite, class 6 / 9)
  local Actors = require("src.zelda.alttp.Actors")
  local sh0 = Actors.swordHit
  function Actors:swordHit(x, y, w, h, how)
    local ganon = mod("Ganon")
    if how and how.arrow and how.cls == 6 and ganon and ganon.arrowHit and self.room ~= -1 then
      local cb = self.game.data.roomIdx.combat
      local handled = false
      for _, a in ipairs(self.list) do
        if ganon.TYPES[a.type] and not a.dead and not (how.only and how.only ~= a) then
          local hx, hy, hw, hh = Actors.hitbox(cb, a)
          if Actors.overlapCart(x, y, w, h, hx, hy - (a.z or 0), hw, hh) then
            ganon.arrowHit(self, a, BH.silver(self.game))
            handled = true
          end
        end
      end
      if handled then return 1 end
    end
    return sh0(self, x, y, w, h, how)
  end
end

return BH
