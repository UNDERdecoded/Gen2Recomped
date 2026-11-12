-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 28: TEAM A'S ITEMS ON TEAM B'S ROUND-27 HOOKS (zelda3 names), on
-- top of BossHooks.lua's chain (installed after it by ExtractA27.install):
--
--   the Fire Rod      Ancilla02_FireRodShot in flight (Ancilla_CheckSprite
--                     Collision, class 11) on a Freezor 0xA1 ->
--                     Enemies27B.fireHit; its 31-frame burst (step 1) runs
--                     Ancilla_CheckBasicSpriteCollision every frame: a
--                     sprite whose (slot ^ frame) & 3 is 0 under the 16 x 16
--                     box (x - 8, y - 8 - z): a Firesnake 0x80 with
--                     delay_aux4 0 turns round (Enemies27A.ancillaHit); a
--                     Freezor takes class 11 (Enemies27B.fireHit).
--   Bombos            class 13 on a Freezor -> Enemies27B.fireHit.
--   the hammer        Terrorpin_CheckForHammer: the hammer's action box over
--                     the Terrorpin's 48 x 48 box flips it ->
--                     Enemies27B.hammerAt (BossHooks' Helmasaur hook kept).
--   the bunny beam    link_timer_tempbunny (Traps27 sets game.tempBunny =
--                     256): Link_HandleBunnyTransformation (20 frames held,
--                     no sprite damage; a perma-bunny clears it), then
--                     LinkState_TemporaryBunny counts it down as a bunny
--                     (DarkWorld.isBunny answers true), at 0 Link again;
--                     ForceNonbunnyStatus (leaving for the overworld) and a
--                     pit fall with the Moon Pearl clear it.
--   the Somaria cane  Items27 calls Floors27.somariaBlockCreated /
--                     somariaBlock in a cane-ride room (in Items27 itself).
--
-- OURS: the burst does not damage the other sprites it touches (only the
-- two above); no poof / sound for the bunny's change.

local H = {}

local bit = require("bit")
local band, bxor = bit.band, bit.bxor

local function mod(name)
  local ok, m = pcall(require, "src.zelda.alttp." .. name)
  return ok and m or nil
end
local function actorsHere(game) if game.interior then return game.actors end return game.owActors end

H.FREEZOR, H.FIRESNAKE, H.TERRORPIN = 0xA1, 0x80, 0x8E
H.FIRE, H.BOMBOS = 11, 13
H.TRANSFORM = 20

-- the burst of a Fire Rod shot (step 1): Ancilla_CheckBasicSpriteCollision
function H.burst(game, a)
  local acts = actorsHere(game)
  if not acts then return 0 end
  local A = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx.combat
  local e27a, e27b = mod("Enemies27A"), mod("Enemies27B")
  local n = 0
  local bx, by = a.x - 8, a.y - 8 - (a.z or 0)
  for i, s in ipairs(acts.list) do
    if not s.dead and (s.type == H.FIRESNAKE or s.type == H.FREEZOR)
       and (s.lower or false) == (a.lower or false)
       and band(bxor(s.k or i, game.frame or 0), 3) == 0 then
      local hx, hy, hw, hh = A.hitbox(cb, s)
      if A.overlapCart(bx, by, 16, 16, hx, hy - (s.z or 0), hw, hh) then
        if s.type == H.FIRESNAKE and e27a and e27a.ancillaHit(acts, s) then
          n = n + 1
          game.snakeTurns = (game.snakeTurns or 0) + 1
        elseif s.type == H.FREEZOR and e27b and e27b.fireHit(acts, s, H.FIRE) then
          n = n + 1
        end
      end
    end
  end
  return n
end

-- ------------------------------------------------------------ the bunny
local function bunnyFrame(game)
  local t = game.tempBunny or 0
  if t <= 0 then game.tempBunnyOn, game.bunnyChange = nil, nil return end
  if not game.tempBunnyOn then
    -- Link_HandleBunnyTransformation
    local DW = require("src.zelda.alttp.DarkWorld")
    if not game.bunnyChange and H.isBunny0 and H.isBunny0(game) then
      game.tempBunny = 0
      return
    end
    game.bunnyChange = (game.bunnyChange or H.TRANSFORM + 1) - 1
    if game.bunnyChange < 0 then
      game.bunnyChange, game.tempBunnyOn = nil, true
      game.tempBunnies = (game.tempBunnies or 0) + 1
    end
    return "hold"
  end
  -- LinkState_TemporaryBunny
  game.tempBunny = t - 1
  if game.tempBunny <= 0 then
    game.tempBunny, game.tempBunnyOn = 0, nil
    game.tempBunnyEnds = (game.tempBunnyEnds or 0) + 1
  end
end
H.bunnyFrame = bunnyFrame

function H.install(G)
  local Tools = require("src.zelda.alttp.Tools")
  local EV = require("src.zelda.alttp.OwEvents")
  -- (0x80 / 0x8E / 0xA1 fight: Enemies27A / 27B put them in Palace.FIGHTS,
  -- so the item loops already reach them)

  -- the Fire Rod's shot in flight on a Freezor
  local tool0 = Tools.bossHook
  Tools.bossHook = function(game, acts, s, cls, a)
    if s.type == H.FREEZOR and cls == H.FIRE and not (a and a.kind == "hook") then
      local e27b = mod("Enemies27B")
      if e27b and e27b.fireHit then return e27b.fireHit(acts, s, H.FIRE) and true or "pass" end
    end
    return tool0 and tool0(game, acts, s, cls, a) or false
  end
  -- Bombos on a Freezor
  local spell0 = EV.bossHook
  EV.bossHook = function(game, acts, s, cls, kind)
    if kind == "bombos" and s.type == H.FREEZOR then
      local e27b = mod("Enemies27B")
      if e27b and e27b.fireHit then e27b.fireHit(acts, s, H.BOMBOS); return true end
    end
    return spell0 and spell0(game, acts, s, cls, kind) or false
  end
  -- the hammer on a Terrorpin
  local ham0 = Tools.hammerHook
  Tools.hammerHook = function(game, acts, x, y, w, h)
    if ham0 then ham0(game, acts, x, y, w, h) end
    local e27b = mod("Enemies27B")
    if acts and e27b and e27b.hammerAt then
      local lower = game.interior and (game.interior.lower or false) or false
      local n = e27b.hammerAt(acts, x, y, w, h, lower)
      if n > 0 then game.hammerFlips = (game.hammerFlips or 0) + n end
    end
  end

  -- the Fire Rod's burst
  local upd0 = G.updateAncillae
  function G:updateAncillae()
    upd0(self)
    for _, a in ipairs(self.anc or {}) do
      if a.kind == "fire" and a.step == 1 and not a.gone then H.burst(self, a) end
    end
  end

  -- the temporary bunny
  local DW = require("src.zelda.alttp.DarkWorld")
  H.isBunny0 = H.isBunny0 or DW.isBunny
  local isB0 = H.isBunny0
  DW.isBunny = function(game) return game.tempBunnyOn == true or isB0(game) end
  local hurt0 = G.hurtLink
  function G:hurtLink(dmg, fx, fy)
    if self.bunnyChange then return end   -- link_disable_sprite_damage
    return hurt0(self, dmg, fx, fy)
  end
  local update0 = G.update
  function G:update(dt)
    if (self.tempBunny or 0) > 0 then
      -- ForceNonbunnyStatus: the overworld
      if not self.interior then self.tempBunny = 0 end
      if self.pitFall and DW.hasPearl(self) then self.tempBunny = 0 end
    end
    if (self.tempBunny or 0) > 0 and (self.state == "room" or self.state == "play") and not self.textBox and not self.menu
       and not self.mirrorWarp then
      local lk = self.link
      if bunnyFrame(self) == "hold" then
        local x, y = lk.x, lk.y
        local r = update0(self, dt)
        lk.x, lk.y, lk.moving = x, y, false
        return r
      end
    elseif (self.tempBunny or 0) <= 0 then
      self.tempBunnyOn, self.bunnyChange = nil, nil
    end
    return update0(self, dt)
  end
end

return H
