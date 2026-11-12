-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- LIFT, CARRY, THROW (bug round, user report "can't pick up pots"). Installed
-- into Game (G) as methods.
--
-- From the cartridge (zelda3 player.c Link_PerformThrow /
-- Link_APress_LiftCarryThrow, dungeon.c Dungeon_LiftAndReplaceLiftable,
-- overworld.c Overworld_HandleLiftableTiles):
--   * A in front of a liftable: the point checked is Link + (7, 3) up,
--     (7, 24) down, (-3, 14) left, (16, 14) right
--     (kDungeon_QueryIfTileLiftable_x/y);
--   * indoors the pots (Interior.markPots: attribute 0x70 + n), outdoors the
--     small objects the cartridge replaces (bush 0x36 -> 0xDC7 ...,
--     Escape's CUT table, with the secret under them) on liftable tile
--     attributes 0x50-0x5D; the gloves each attribute pair needs are
--     kGetBestActionToPerformOnTile_a { 0, 1, 0, 0, 2, 1, 2 } (0x50/51 bush
--     none, 0x52/53 rock the Power Glove, ...);
--   * the lift: Link stands still for some_animation_timer 6, 7, 7 frames on
--     lift poses 0, 1, 2 (kLiftTab2), pose row 0x10; carrying is row 0x0D
--     with the walk steps; throwing is row 0x0E.
-- OURS (the thrown-terrain sprite, Sprite_SpawnThrowableTerrain, is not
-- ported): the lifted object is the room's / screen's own 16x16 picture of
-- it, it rises from its tile to 14 px above Link over the lift, is carried
-- there, and a throw sends it 4 px a frame in Link's facing from 14 px up,
-- falling 0.25 px a frame per frame, until it lands or hits a wall, where
-- it breaks. Round 9: it breaks into the cartridge's debris pieces and hurts
-- the enemies it meets (Drops.lua); what a pot or bush hid comes out through
-- the cartridge's drop routine (Drops.lua).

local Link = require("src.zelda.alttp.Link")

local C = {}

C.QUERY = { [Link.UP] = { 7, 3 }, [Link.DOWN] = { 7, 24 }, [Link.LEFT] = { -3, 14 }, [Link.RIGHT] = { 16, 14 } }
C.GLOVES_NEEDED = { [0] = 0, 1, 0, 0, 2, 1, 2 }
C.LIFT_TIMES = { 6, 7, 7 }
C.THROW_TIMES = { 4, 4 }
C.HELD_Z = 14
C.THROW_SPEED = 4
C.GRAVITY = 0.25
local STEP = { [Link.UP] = { 0, -1 }, [Link.DOWN] = { 0, 1 }, [Link.LEFT] = { -1, 0 }, [Link.RIGHT] = { 1, 0 } }

function C.install(G)
  function G:gloveLevel()
    local lv = 0
    for _, id in ipairs(self.progress.items or {}) do
      if id == 0x1B then lv = math.max(lv, 1) elseif id == 0x1C then lv = 2 end
    end
    return lv
  end

  -- start a lift: obj = { img, quad, x, y } (world / room pixels of the tile)
  function G:startLift(obj)
    obj.fromX, obj.fromY = obj.x, obj.y
    self.carry = { phase = "lift", obj = obj, t = 0, poseStep = 0 }
    self.link.steps = 0
    self.lifts = (self.lifts or 0) + 1
  end

  -- A in front of something liftable: indoors a pot, outdoors a bush/rock
  function G:tryLift()
    local lk = self.link
    local q = C.QUERY[lk.facing]
    local px, py = lk.x + q[1], lk.y + q[2]
    -- r20: Link's own bomb before it goes off (Ancilla07_Bomb: R on it lifts
    -- it like a pot; its fuse keeps running in his hands)
    for _, b in ipairs(self.anc or {}) do
      if b.kind == "bomb" and b.itl == 0 and not b.held and not b.fly
         and math.abs(b.x - px) <= 10 and math.abs(b.y - py) <= 10 then
        b.held = true
        self.bombLifts = (self.bombLifts or 0) + 1
        self:startLift({ x = b.x - 8, y = b.y - 8, kind = "bomb", what = 0, bomb = b })
        return true
      end
    end
    if self.state == "room" and self.interior then
      local inside = self.interior
      local pot = inside:potAt(px, py)
      if not pot then return false end
      -- the pot's own picture: its 4 map words through the room's tiles
      local img
      if self.view then
        local View = require("src.zelda.alttp.View")
        local id = love.image.newImageData(16, 16)
        View.fill(id, 16, 16, inside:wordsPixels(inside:potWords(pot)), inside:palette())
        img = love.graphics.newImage(id)
        img:setFilter("nearest", "nearest")
      end
      local item = inside:liftPot(pot)
      self.roomImages = nil
      if item and item ~= 0 then
        self.potItems = (self.potItems or 0) + 1
      end
      -- round 9: what the pot hid comes out through the cartridge's drop
      -- routine (Drops.lua; RevealPotItem: values 0x80+ are switches/holes)
      if item and item ~= 0 then
        self:terrainDrop(0, item < 0x80 and item or 0xFF, pot.x * 8, pot.y * 8)
      end
      self:startLift({ img = img, quad = img and love.graphics.newQuad(0, 0, 16, 16, 16, 16),
                       x = pot.x * 8, y = pot.y * 8, kind = "pot", what = 0 })
      return true
    end
    if self.state ~= "play" then return false end
    local a = self.ow:attrAt(lk.world, px, py)
    if not a or a < 0x50 or a > 0x5D then return false end
    -- r25: the cartridge's rule by attribute (BigRock.lua: kTile50data -> kGetBestActionToPerformOnTile_a)
    local need = (C.need and C.need(a)) or C.GLOVES_NEEDED[math.floor((a - 0x50) / 2)] or 3
    if need > self:gloveLevel() then return false end
    -- the tile's picture before it changes
    local O = require("src.zelda.alttp.Overworld")
    local tx, ty = math.floor(px / 16) * 16, math.floor(py / 16) * 16
    local screen = O.screenAt(lk.world, tx, ty)
    local img, quad
    if screen and self.view then
      -- a copy: the screen's pictures may be dropped from the view's cache
      -- (and released) while the bush is still carried
      local src = self.view:screen(screen).bg2
      local cv = love.graphics.newCanvas(16, 16)
      cv:setFilter("nearest", "nearest")
      love.graphics.push("all")
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.origin()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(src, love.graphics.newQuad(tx % 512, ty % 512, 16, 16, 512, 512), 0, 0)
      love.graphics.pop()
      img = cv
      quad = love.graphics.newQuad(0, 0, 16, 16, 16, 16)
    end
    if not self:owTileChange(px, py, self.CUT_TILES) then return false end
    self.lifted = (self.lifted or 0) + 1
    -- round 9: the drop (kLink_Lift_tab kind of the tile's attribute)
    local Drops = require("src.zelda.alttp.Drops")
    self:terrainDrop(Drops.LIFT_KIND[a] or 2, self.lastSecret, tx, ty)
    self:startLift({ img = img, quad = quad, x = tx, y = ty, kind = "bush", what = Drops.LIFT_KIND[a] or 2 })
    return true
  end

  -- one frame; returns true when Link is held still this frame. Clears
  -- inp.a / inp.b while something is carried (A throws, no sword).
  function G:carryFrame(inp)
    self:updateThrown()
    return self:carryHeldFrame(inp)
  end

  -- r22: the thrown object's flight (it also flies on while Link recoils)
  function G:updateThrown()
    local th = self.thrown
    if th then
      th.t = th.t + 1
      th.zv = th.zv - C.GRAVITY
      th.z = th.z + th.zv
      local nx, ny = th.x + th.vx, th.y + th.vy
      -- round 9: it hurts the enemies it meets (ThrownSprite_CheckDamageToSprites:
      -- box x, y - z + 8, 15 x 8; class 1 an outdoor bush, else 3) and breaks
      local hitFoe = false
      if self.state == "room" and self.actors and self.interior then
        local cls = (th.what == 2 and self.state ~= "room") and 1 or 3
        local sx = th.vx > 0 and 1 or (th.vx < 0 and -1 or 0)
        local sy = th.vy > 0 and 1 or (th.vy < 0 and -1 or 0)
        hitFoe = self.actors:thrownHit(th.x, th.y - th.z + 8, 15, 8, cls, sx, sy, self.interior.lower or false) > 0
        if hitFoe then self.thrownHits = (self.thrownHits or 0) + 1 end
      end
      if hitFoe or self:carryBlocked(nx + 8, ny + 20) or th.z <= 0 then
        self.thrown = nil
        self.landed = (self.landed or 0) + 1
        -- ThrowableScenery_ScatterIntoDebris: the pieces where it broke
        self:spawnDebris(th.what or 2, th.x, th.y - math.max(0, th.z))
      else
        th.x, th.y = nx, ny
      end
    end
  end

  -- r22: the throw (CarriedSprite_CheckForThrow: the sprite leaves Link's
  -- hands in his facing; a bomb flies with its fuse running)
  function G:throwCarried()
    local c, lk = self.carry, self.link
    if not c or c.phase == "throw" then return false end
    local s = STEP[lk.facing]
    local o = c.obj
    if o.bomb then
      -- r20: the bomb is thrown (OURS: the pot's arc; the cartridge's
      -- thrown-bomb bounce is not traced); its fuse runs on
      o.bomb.held = nil
      o.bomb.fly = { vx = s[1] * C.THROW_SPEED, vy = s[2] * C.THROW_SPEED, zv = 0 }
      self.bombThrows = (self.bombThrows or 0) + 1
    else
      self.thrown = { img = o.img, quad = o.quad, x = lk.x, y = lk.y, z = C.HELD_Z, zv = 0, what = o.what,
                      vx = s[1] * C.THROW_SPEED, vy = s[2] * C.THROW_SPEED, t = 0 }
    end
    c.phase, c.t, c.poseStep = "throw", 0, 0
    self.throws = (self.throws or 0) + 1
    return true
  end

  -- r22: Link hurt while he lifts or carries (CarriedSprite_CheckForThrow:
  -- link_incapacitated_timer != 0 throws it at once, whatever is pressed);
  -- the escape / overworld recoil branches call this every recoil frame
  function G:carryRecoilFrame()
    self:updateThrown()
    local c = self.carry
    if not c then return end
    if c.phase == "throw" then
      c.t = c.t + 1
      c.poseStep = (c.t > C.THROW_TIMES[1]) and 1 or 0
      if c.t >= C.THROW_TIMES[1] + C.THROW_TIMES[2] then self.carry = nil end
      return
    end
    self.hurtThrows = (self.hurtThrows or 0) + 1
    self:throwCarried()
  end

  function G:carryHeldFrame(inp)
    local c = self.carry
    if not c then return false end
    local lk = self.link
    if c.phase == "lift" then
      c.t = c.t + 1
      local total, acc = 0, 0
      for _, v in ipairs(C.LIFT_TIMES) do total = total + v end
      for i, v in ipairs(C.LIFT_TIMES) do
        acc = acc + v
        if c.t <= acc then c.poseStep = i - 1 break end
      end
      if c.t >= total then c.phase, c.t = "carry", 0 end
      lk.steps = 0
      return true
    elseif c.phase == "throw" then
      c.t = c.t + 1
      c.poseStep = (c.t > C.THROW_TIMES[1]) and 1 or 0
      if c.t >= C.THROW_TIMES[1] + C.THROW_TIMES[2] then self.carry = nil end
      return true
    end
    -- carrying: the action button (SNES A, GBA R) or B throws (r22:
    -- CarriedSprite_CheckForThrow tests (filtered_joypad_H |
    -- filtered_joypad_L) & 0x80, B and A; it was R only, so a player
    -- carrying a pot could neither swing nor shoot nor throw with B)
    if inp.a or inp.b then
      if inp.b and not inp.a then self.bThrows = (self.bThrows or 0) + 1 end
      self:throwCarried()
      inp.a, inp.b = false, false
      return true
    end
    inp.a, inp.b = false, false
    return false
  end

  function G:carryBlocked(x, y)
    if self.state == "room" and self.interior then return self.interior:blocked(x, y) end
    local O = require("src.zelda.alttp.Overworld")
    return O.isSolid(self.ow:attrAt(self.link.world, x, y) or 1)
  end

  -- where the carried object is drawn (world / room pixels, top-left)
  function G:carriedPos()
    local c, lk = self.carry, self.link
    if not c or c.phase == "throw" then return nil end
    local hx, hy = lk.x, lk.y - C.HELD_Z
    if c.phase == "lift" then
      local total = 0
      for _, v in ipairs(C.LIFT_TIMES) do total = total + v end
      local p = math.min(1, c.t / total)
      return math.floor(c.obj.fromX + (hx - c.obj.fromX) * p + 0.5),
             math.floor(c.obj.fromY + (hy - c.obj.fromY) * p + 0.5)
    end
    return hx, hy
  end

  -- round 10: the cartridge's picture of a lifted / thrown object, the
  -- sprite 0xEC (Sprite_EC_ThrownItem: one 16x16 OAM entry, char
  -- kThrowableScenery_Char[what + (indoors + dark world >= 2 and 6 or 0)],
  -- palette kThrowableScenery_Flags[what]; a bush indoors 0x50). Objects
  -- 6-8 (the big rocks) keep the tile picture.
  function G:drawThrowable(what, x, y)
    local cb = self.data.roomIdx and self.data.roomIdx.combat
    if not (cb and cb.throwChar and what and what < 6) then return false end
    local spr = self:shadowSprites()
    if not spr then return false end
    local indoors = (self.state == "room") and 1 or 0
    local dark = (self.link.world == "dw") and 1 or 0
    local ch = cb.throwChar[what + ((indoors + dark >= 2) and 6 or 0) + 1]
    if not ch or ch == 0 then return false end
    local fl = cb.throwFlags[what + 1] or 0
    if what == 2 and indoors == 1 then fl = 0x50 end
    spr:oam(x, y, ch, fl, 2)
    return true
  end

  function G:drawCarried()
    local lg = love.graphics
    local cx, cy = self.cam.x, self.cam.y
    local x, y = self:carriedPos()
    local c = self.carry
    if c.obj.bomb then return end   -- r20: the bomb ancilla draws itself
    if x and self:drawThrowable(c.obj.what, x - cx, y - cy) then return end
    if x and c.obj.img and c.obj.quad then lg.draw(c.obj.img, c.obj.quad, x - cx, y - cy) end
  end

  function G:drawThrown()
    local th = self.thrown
    if not th then return end
    local x, y = math.floor(th.x - self.cam.x + 0.5), math.floor(th.y - th.z - self.cam.y + 0.5)
    if self:drawThrowable(th.what, x, y) then return end
    if not (th.img and th.quad) then return end
    love.graphics.draw(th.img, th.quad, x, y)
  end

  -- drop what is carried (room changes, game over)
  function G:dropCarry()
    if self.carry and self.carry.obj and self.carry.obj.bomb then self.carry.obj.bomb.held = nil end
    self.carry, self.thrown = nil, nil
  end
end

return C
