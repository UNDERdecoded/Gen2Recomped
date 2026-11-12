-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DROPS (round 9, user request "cutting grass uses the rom's scripts for
-- dropping items"). What a cut or lifted bush, grass, rock or pot leaves
-- behind, ported from the GBA's own routines (the SNES zelda3 names):
--
--   0x080CEFE0 GetRandomNumber        r = VCOUNT + frame counter (RAM +0x996)
--                                     + seed (RAM +0x15DE); seed = r
--   0x080C2A6A throwable-terrain tail  secret 0xFF: nothing; outdoors, no
--                                     secret and terrain kind 2/3 (bush,
--                                     grass): the substitution below
--   0x080CA754 Overworld_SubstituteAlternateSecret
--                                     rng & 1 -> keep; more than 3 active
--                                     sprites (not 0x6C) -> keep; story
--                                     progress <= 1 -> keep; counter + 1,
--                                     j = counter & 7 (+8 in the Dark World);
--                                     secret = tab2[j] unless tab0[area & 63]
--                                     & tab1[j]
--   0x080C2534 Sprite_SpawnSecret     outdoors rng & 8 -> nothing; secret 0
--                                     -> nothing; secret 4 -> 19 + (rng & 3);
--                                     type = items[secret - 1] (0 -> nothing),
--                                     ai state / z velocity / x + XLo from the
--                                     tables, pickup delay 0x20, aux 0x30,
--                                     a 255 lifetime for the absorbables
--   0x080C382C (GBA only)             no bow: arrows (0xE1/0xE2) become
--                                     green/blue rupees (0xD9/0xDA)
--
-- The tables are the cartridge's (RomMap.drops, read at import into
-- data.t.drops). The secret comes from the cartridge's secrets tables
-- (outdoors 0x22C624 by area and tile, indoors 0x2264C8 by room and pot).
--
-- The dropped items (sprite types 0xD8-0xE6) move and are picked up as
-- zelda3 Sprite_Absorbable_Main / Sprite_D8_Heart / Sprite_HandleAbsorptionByPlayer
-- do: z velocity in 1/16 px, -2 a frame, a landing halves x/y speed and
-- bounces with half the fall speed until below 9; the heart rises (z
-- velocity 20 for 18 frames) then glides down at -3 swaying 1 px/frame^2
-- to +-10; touching Link absorbs it once the 0x20-frame pickup delay is
-- over; the lifetime (255) drops every other frame, the item blinks below
-- 0x28 and goes at 0.
--
-- Round 9 too: the debris of a cut bush or a broken thrown object
-- (G:spawnDebris, the cartridge's piece tables), and a thrown object hurts
-- the enemies it meets (Carry.lua, Actors:thrownHit).
--
-- OURS: the GBA's VCOUNT (the scanline the CPU is on when the routine
-- runs) cannot be known from Lua: it is modelled as (frame * 37 + call *
-- 73) % 228, so the random numbers follow the cartridge's formula with a
-- stand-in for the scanline. Round 10: enemies a secret holds (soldiers
-- 0x41/0x42, the bee 0x79, the hoarder 0x3E, the cucco 0x0B) are spawned
-- (Actors.spawnSecret; outdoors OwActors.lua); 0xD3/0xD4 are not. The fairy (0xE3) floats like the
-- heart. Pickup boxes: Link (x+3, y+8, 10x12) against the item (x, y, 8x8)
-- (the SNES Sprite_CheckDamageToPlayer_1 boxes are not ported).

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local D = {}

-- ---------------------------------------------------------------- the routines
-- st = { seed, fc, vcount } ; every call returns the new seed (0..255)
function D.rng(st)
  local r = band((st.vcount or 0) + band(st.fc or 0, 0xFF) + band(st.seed or 0, 0xFF), 0xFF)
  st.seed = r
  st.calls = (st.calls or 0) + 1
  if st.nextVcount then st.vcount = st.nextVcount(st) end
  return r
end

-- 0x080CA754. st also holds: secret, progress, dark, area, ctr, others (the
-- count of active sprites other than 0x6C). Changes st.secret / st.ctr.
function D.substitute(tabs, st)
  if band(D.rng(st), 1) ~= 0 then return end
  if (st.others or 0) > 3 then return end
  if (st.progress or 0) <= 1 then return end
  st.ctr = band((st.ctr or 0) + 1, 0xFF)
  local j = band(st.ctr, 7)
  if (st.dark or 0) ~= 0 then j = bor(j, 8) end
  local a = tabs.substArea[band(st.area or 0, 0x3F) + 1] or 0
  if band(a, tabs.substMask[j + 1] or 0) == 0 then
    st.secret = tabs.substSecret[j + 1]
  end
end

-- 0x080C2534: returns the spawned sprite's type and its table row (or nil)
function D.spawnSecret(tabs, st)
  if (st.indoor or 0) == 0 and band(D.rng(st), 8) ~= 0 then return nil end
  local b = st.secret or 0
  if b == 0 then return nil end
  if b == 4 then b = 19 + band(D.rng(st), 3) end
  local item = tabs.secretItems[b]
  if not item or item == 0 then return nil end
  -- 0x080C382C (GBA only): without the bow (inventory byte 0x02002320 = 0)
  -- arrows become rupees: 0xE1 -> 0xD9, 0xE2 -> 0xDA
  if (st.bow or 0) == 0 then
    if item == 0xE1 then item = 0xD9 elseif item == 0xE2 then item = 0xDA end
  end
  return item, { flag = tabs.secretFlag[b] or 0, xlo = tabs.secretXLo[b] or 0,
                 ignore = tabs.secretIgnore[b] or 0, zvel = tabs.secretZVel[b] or 0 }
end

-- the throwable-terrain tail 0x080C2A6A: `what` is the terrain kind (SNES
-- sprite_C: 2 bush, 3 thick grass, 4 dark bush, 1 rock, 0 pot ...)
function D.terrain(tabs, st)
  local sec = st.secret or 0
  if sec == 0xFF then return nil end
  if bor(sec, st.indoor or 0) == 0 and band((st.what or 0) - 2, 0xFF) <= 1 then
    D.substitute(tabs, st)
  end
  if band(st.secret or 0, 0x80) ~= 0 then
    st.deferred = band(st.secret, 0x7F)
    st.secret = 0
  end
  return D.spawnSecret(tabs, st)
end

-- kLink_Lift_tab: the terrain kind of a lifted tile by its attribute
D.LIFT_KIND = { [0x54] = 0, [0x52] = 1, [0x50] = 2, [0x51] = 4, [0x53] = 5, [0x55] = 6, [0x56] = 7, [0x57] = 8 }
-- what the sword cuts (Overworld_ToolAndTileInteraction): map16 -> kind
D.CUT_KIND = { [0x36] = 2, [0x72A] = 4, [0x37E] = 3 }

-- the absorbables (sprite types 0xD8-0xE6, zelda3 Sprite_HandleAbsorptionByPlayer)
D.ABSORB = {
  [0xD8] = "heart", [0xD9] = "rupee1", [0xDA] = "rupee5", [0xDB] = "rupee20",
  [0xDC] = "bomb1", [0xDD] = "bomb4", [0xDE] = "bomb8", [0xDF] = "magic",
  [0xE0] = "magicFull", [0xE1] = "arrow5", [0xE2] = "arrow10", [0xE3] = "fairy",
  [0xE4] = "key",
}
D.LIFETIME = 255
D.BLINK = 0x28

-- ------------------------------------------------------------- in the game
function D.install(G)
  -- the GBA's RNG state for this game
  function G:dropRng()
    local st = self.rngState
    if not st then
      st = { seed = 0, calls = 0 }
      self.rngState = st
    end
    st.fc = band(self.frame or 0, 0xFF)
    st.vcount = ((self.frame or 0) * 37 + st.calls * 73) % 228
    st.nextVcount = function(s) return ((self.frame or 0) * 37 + s.calls * 73) % 228 end
    return st
  end

  -- story progress as the cartridge counts it (sram_progress_indicator):
  -- 0 new, 1 has the sword (uncle), 2 Zelda in the sanctuary, 3 Agahnim
  function G:storyProgress()
    local p = self.progress or {}
    if p.agahnim or p.agahnim1 or (tonumber(p.sramProgress) or 0) >= 3 then return 3 end
    if p.escaped then return 2 end
    if p.sword then return 1 end
    return 0
  end

  -- a cut / lifted terrain tile at world or room (x, y) (its 16x16 corner):
  -- what = terrain kind, secret = the secrets table's value (0 none,
  -- 0xFF a revealed hole/stairs)
  function G:terrainDrop(what, secret, x, y)
    local tabs = self.data.t and self.data.t.drops
    if not tabs then return nil end
    local st = self:dropRng()
    st.secret, st.what = secret or 0, what
    st.indoor = self.state == "room" and 1 or 0
    st.progress = self:storyProgress()
    st.dark = (self.link.world == "dw") and 1 or 0
    st.area = self.area and self.area.parent or 0
    st.ctr = self.substCtr or 0
    -- the active sprites the substitution counts: the terrain piece
    -- itself, the drops and the room's live actors
    local n = 1
    for _, d in ipairs(self.drops or {}) do if not d.gone then n = n + 1 end end
    if self.state == "room" and self.actors then
      for _, a in ipairs(self.actors.list) do if not a.dead then n = n + 1 end end
    end
    -- round 10: and the overworld's live actors
    if self.state == "play" and self.owActors then
      for _, a in ipairs(self.owActors.list) do if not a.dead then n = n + 1 end end
    end
    st.others = n
    st.bow = 0
    for _, id in ipairs((self.progress and self.progress.items) or {}) do
      if id == 0x0B or id == 0x3A or id == 0x3B then st.bow = 1 end
    end
    local item, row = D.terrain(tabs, st)
    self.substCtr = st.ctr
    self.dropLog = self.dropLog or {}
    self.dropLog[#self.dropLog + 1] = { what = what, secret = secret, item = item or 0 }
    if not item then return nil end
    return self:spawnDrop(item, x + (row.xlo or 0), y, row)
  end

  function G:spawnDrop(item, x, y, row)
    self.drops = self.drops or {}
    local kind = D.ABSORB[item]
    if item == 0xE4 and self.state == "room" then
      -- the small key: the escape's own key actor (picked up by Actors)
      local Actors = require("src.zelda.alttp.Actors")
      -- r19: t = 0 / index = -1 as Actors' own key drop (a pot's key had no
      -- frame counter and stopped the actor update: room BA's key pot)
      self.actors.list[#self.actors.list + 1] = { type = Actors.KEY, x = x, y = y, t = 0, index = -1,
                                                  lower = self.interior and self.interior.lower,
                                                  potKey = true }   -- r22: a pot's key (Interior.liftPot)
      return item
    end
    if not kind then
      -- round 10: an enemy or critter, spawned (OwActors / Actors.spawnSecret)
      self.enemyDrops = (self.enemyDrops or 0) + 1
      if self.state == "room" and self.actors and self.actors.inside then
        self.actors:spawnSecret(item, x, y, self.interior and self.interior.lower)
      elseif self.state == "play" then
        self:spawnOwActor(item, x, y)
      end
      return item
    end
    local zv = row and row.zvel or 0
    if zv >= 128 then zv = zv - 256 end
    local d = { type = item, kind = kind, x = x, y = y, z = 0, zsub = 0, zvel = zv,
                xvel = 0, yvel = 0, ai = row and row.flag or 0, delay = 0x20, aux2 = 0x30,
                life = D.LIFETIME, t = 0, world = self.link.world, area = self.area and self.area.parent,
                room = self.interior and self.interior.room or nil,
                lower = self.state == "room" and self.interior and self.interior.lower or false }
    if kind == "heart" or kind == "fairy" then d.ai = 0 end
    self.drops[#self.drops + 1] = d
    return item
  end

  local function absorb(self, d)
    local s, p = self.stats, self.progress
    local k = d.kind
    if k == "heart" then s.health = math.min(s.healthMax, s.health + 8)
    elseif k == "rupee1" then s.rupees = math.min(999, s.rupees + 1)
    elseif k == "rupee5" then s.rupees = math.min(999, s.rupees + 5)
    elseif k == "rupee20" then s.rupees = math.min(999, s.rupees + 20)
    elseif k == "bomb1" then s.bombs = s.bombs + 1
    elseif k == "bomb4" then s.bombs = s.bombs + 4
    elseif k == "bomb8" then s.bombs = s.bombs + 8
    elseif k == "magic" then s.magic = math.min(0x80, s.magic + 0x10)
    elseif k == "magicFull" then s.magic = 0x80
    elseif k == "arrow5" then s.arrows = s.arrows + 5
    elseif k == "arrow10" then s.arrows = s.arrows + 10
    elseif k == "fairy" then s.health = math.min(s.healthMax, s.health + 56)
    elseif k == "key" then self:getItem(0x24)
    end
    self.absorbed = (self.absorbed or 0) + 1
    self.absorbLog = self.absorbLog or {}
    self.absorbLog[#self.absorbLog + 1] = d.type
  end

  -- one frame of every drop (zelda3 Sprite_Absorbable_Main / Sprite_D8_Heart)
  function G:updateDrops()
    self:updateDebris()
    local list = self.drops
    if not list or #list == 0 then return end
    local lk = self.link
    local here = self.state == "room" and self.interior and self.interior.room or nil
    local keep = {}
    for _, d in ipairs(list) do
      if d.room == here and (here or (d.world == lk.world and d.area == (self.area and self.area.parent))) and not d.gone then
        d.t = d.t + 1
        -- Sprite_ReturnIfPhasingOut: the lifetime drops every other frame
        if d.life and d.life > 0 then
          if band(self.frame, 1) == 0 then d.life = d.life - 1 end
          if d.life == 0 then d.gone = true end
        end
        if d.delay > 0 then d.delay = d.delay - 1 end
        if d.aux2 > 0 then d.aux2 = d.aux2 - 1 end
        if not d.gone then
          if d.kind == "heart" or d.kind == "fairy" then
            -- Sprite_D8_Heart: InitializeAscent / BeginDescending / GlideGroundward
            if d.ai == 0 then d.ai, d.wait, d.zvel, d.sway = 1, 18, 20, 0
            elseif d.ai == 1 then
              if d.wait > 0 then d.wait = d.wait - 1; d.zvel = d.zvel - 1
              else d.ai, d.zvel, d.xvel = 2, -3, 0 end
            elseif d.ai == 2 then
              if (d.wait or 0) > 0 then d.wait = d.wait - 1 else
                local j = band(d.sway, 1)
                d.xvel = d.xvel + (j == 0 and 1 or -1)
                if d.xvel == (j == 0 and 10 or -10) then d.sway = d.sway + 1; d.wait = 8 end
              end
            else d.zvel, d.xvel = 0, 0 end
          else
            d.zvel = d.zvel - 2
          end
          -- Sprite_MoveXY / Sprite_MoveZ (1/16 px)
          d.xsub = (d.xsub or 0) + d.xvel * 16
          d.x = d.x + math.floor(d.xsub / 256); d.xsub = d.xsub % 256
          d.zsub = d.zsub + d.zvel * 16
          d.z = d.z + math.floor(d.zsub / 256); d.zsub = d.zsub % 256
          if d.z < 0 then
            d.z, d.zsub = 0, 0
            if d.kind == "heart" or d.kind == "fairy" then
              d.ai, d.zvel, d.xvel = 3, 0, 0
            else
              d.xvel = math.floor(d.xvel / 2)
              local t = math.floor(band(-d.zvel, 0xFF) / 2)
              if t < 9 then d.zvel = 0 else d.zvel = t end
            end
          end
          -- Sprite_CheckAbsorptionByPlayer
          if d.delay == 0 and lk.x + 3 < d.x + 8 and d.x < lk.x + 13 and lk.y + 8 < d.y - d.z + 8
             and d.y - d.z < lk.y + 20 then
            absorb(self, d)
            d.gone = true
          end
        end
        if not d.gone then keep[#keep + 1] = d end
      end
    end
    self.drops = keep
  end

  -- the debris of a cut bush or a broken thrown object (zelda3
  -- ThrowableScenery_ScatterIntoDebris -> Garnish16_ThrownItemDebris, GBA
  -- 0x080CD724): a 31-frame countdown, 4 pieces from the cartridge's tables
  function G:spawnDebris(what, x, y)
    self.debris = self.debris or {}
    self.debris[#self.debris + 1] = { what = what, x = x, y = y, cd = 31, outdoor = self.state ~= "room",
                                      room = self.interior and self.state == "room" and self.interior.room or nil,
                                      lower = self.state == "room" and self.interior and self.interior.lower or false }
  end

  function G:updateDebris()
    local list = self.debris
    if not list or #list == 0 then return end
    local keep = {}
    local here = self.state == "room" and self.interior and self.interior.room or nil
    for _, e in ipairs(list) do
      e.cd = e.cd - 1
      if e.cd > 0 and e.room == here then keep[#keep + 1] = e end
    end
    self.debris = keep
  end

  function G:drawDebris(cx, cy, spr)
    local tabs = self.data.t and self.data.t.drops
    if not (tabs and tabs.debrisX and spr and self.debris) then return end
    local Layers = require("src.zelda.alttp.Layers")
    for _, e in ipairs(self.debris) do
      if not (self.inPrioPass and not self:inPrioPass(Layers.spritePrio(self.data, e.lower))) then
      local base = bit.lshift(bit.bxor(rshift(e.cd, 2), 7), 2)
      if e.what == 4 or (e.what == 2 and e.outdoor) then base = base + 0x20
      elseif e.what == 0x10 then base = base + 0x40 end
      local kf = band(tabs.kindFlags[e.what + 1] or 0, 0x3F)
      for i = 3, 0, -1 do
        local j = i + base
        local ch = (e.what == 0) and 0x8E or tabs.debrisChar[j + 1]
        spr:oam(e.x - cx + tabs.debrisX[j + 1], e.y - cy + tabs.debrisY[j + 1], ch,
                bor(tabs.debrisFlags[j + 1] or 0, kf), 0)
      end
      end
    end
  end

  -- drawing: the cartridge's absorbable pictures through the sprite sheets
  -- (Sprites.lua: SpriteDraw_SingleSmall / thin-and-tall / single large)
  function G:drawDrops(cx, cy, spr)
    local list = self.drops or {}
    if not spr then return end
    local Layers = require("src.zelda.alttp.Layers")
    for _, d in ipairs(list) do
      -- round 14: one GBA OBJ priority per pass (Layers.lua)
      local hidden = d.life and d.life < D.BLINK and band(d.life, 1) == 0
      if self.inPrioPass and not self:inPrioPass(Layers.spritePrio(self.data, d.lower)) then hidden = true end
      if not hidden then
        -- round 10: the small shadow too (SingleSmall draws it at y + 2 + 1)
        if spr:hasShadow(d.type) then
          local kind = self.data.t and self.data.t.drops and self.data.t.drops.absorbKind[d.type - 0xD8 + 1] or 1
          spr:drawShadow(d.x - cx, d.y - cy, d.type, kind == 0 and 2 or 10)
        end
        spr:drawAbsorbable(d, d.x - cx, d.y - d.z - cy, self.frame)
      end
    end
    self:drawDebris(cx, cy, spr)
  end
end

return D
