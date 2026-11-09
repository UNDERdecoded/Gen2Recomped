-- Link.
--
-- Walking follows src/player.c PlayerNormal: kWalkSpeed is 1.25 px a frame
-- (Q8.8 $140), shield held 0.75 (kWalkSpeedShield), Gust Jar 0.5
-- (kWalkSpeedGustJar); diagonals split the speed by sin/cos, the facing
-- snaps to the last cardinal held.  Animations are the cartridge's
-- (include/player.h); the high byte is the sprite (1 = Link with Ezlo,
-- 4 = no cap, $C = Minish), the low byte plus facing >> 1 the animation.
--
-- BUTTONS as on the cartridge: A and B use the items set on them (pause
-- menu), R is the action button (talk, open, read, lift/throw, portal,
-- roll while moving), L is Kinstone fusion.
--
-- STATES: normal, sword, roll, carry (lift -> carry -> throw), shield,
-- gust, hurt (knockback), itemget (item held up while its message shows),
-- portal (activate + shrink / grow), dead.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local Anim = require("src.zelda.tmc.Anim")

local Player = {}
Player.__index = Player

Player.WALK_SPEED = 0x140 / 256        -- kWalkSpeed
Player.ROLL_SPEED = 0x200 / 256        -- kWalkSpeedRolling
Player.SHIELD_SPEED = 0xC0 / 256       -- kWalkSpeedShield
Player.GUST_SPEED = 0x80 / 256         -- kWalkSpeedGustJar

-- item ids (include/item.h)
Player.ITEM = { SMITH_SWORD = 0x01, GREEN_SWORD = 0x02, RED_SWORD = 0x03, BLUE_SWORD = 0x04, FOURSWORD = 0x06,
                SHIELD = 0x0D, MIRROR_SHIELD = 0x0E, GUST_JAR = 0x11, MOLE_MITTS = 0x13 }

-- with Ezlo (cap), without him (PL_NO_CAP until EZERO_1ST), Minish
-- (Minish Link has no idle animation of his own: he stands on the first
-- walk frame)
local ANIM = {
  idle = 0x100, walk = 0x104, sword = 0x108, roll = 0x2AC,
  idleNoCap = 0x400, walkNoCap = 0x404, swordNoCap = 0x408, rollNoCap = 0x438,
  idleMinish = 0xC04, walkMinish = 0xC04, rollMinish = 0xC08, swordMinish = 0xC00,
  shield = 0x164, shieldWalk = 0x160, shieldNoCap = 0x414,
  gust = 0x504, gustWalk = 0x518, gustBlow = 0x514,
  carry = 0x348, throw = 0x344, pickup = 0x338, pickupNoCap = 0x928,
  getItem = 0x2E0, getItemNoCap = 0x45E,
  portalActivate = 0x738, portalShrink = 0x2C3, grow = 0x73C,
}
Player.ANIM = ANIM

-- animations that do not add the facing
local NO_FACING = { [0x2E0] = true, [0x45E] = true, [0x2C3] = true, [0x738] = true, [0x73C] = true,
                    [0x736] = true, [0x737] = true, [0x73A] = true, [0x73B] = true }

function Player:animFor(kind)
  if self.minish then return ANIM[kind .. "Minish"] or ANIM.walkMinish end
  if not self.hasCap then return ANIM[kind .. "NoCap"] or ANIM[kind] end
  return ANIM[kind]
end

-- the player's hitbox against tiles: feet-centred box
local HW, TOP, BOTTOM = 4, -5, 2
local HW_MINISH, TOP_MINISH, BOTTOM_MINISH = 2, -2, 1

function Player.new(field, x, y, facing)
  local self = setmetatable({
    field = field, x = x or 120, y = y or 80, z = 0, zv = 0,
    animationState = facing or 4, layer = 1,
    anim = Anim.new(), animId = -1, control = true, moving = false,
    action = 1, flags = 0, minish = false, state = "normal", timer = 0,
    invuln = 0, kbx = 0, kby = 0,
  }, Player)
  self:setAnim(self:animFor("idle"))
  return self
end

function Player:sprite()
  return band(rshift(self.animId, 8), 0xFF)
end

function Player:setAnim(id, force)
  local base = id
  local sprite = rshift(base, 8)
  local index = band(base, 0xFF)
  if not NO_FACING[base] then index = index + rshift(self.animationState, 1) end
  local full = sprite * 256 + index
  if full == self.animId and not force then return end
  self.animId = full
  local spr = self.field.assets:sprite(sprite)
  self.anim:set(spr, index, true)
end

-- solid test for the box around (x, y)
function Player:blocked(x, y)
  local room = self.field.room
  local hw, top, bottom = HW, TOP, BOTTOM
  if self.minish then hw, top, bottom = HW_MINISH, TOP_MINISH, BOTTOM_MINISH end
  if room:isSolid(x - hw, y + top, self.layer) or room:isSolid(x + hw - 1, y + top, self.layer)
     or room:isSolid(x - hw, y + bottom, self.layer) or room:isSolid(x + hw - 1, y + bottom, self.layer) then
    return true
  end
  return self.field:entityBlocks(self, x, y)
end

-- one axis at a time, with the cartridge's corner nudge: if only one front
-- corner is caught, slide sideways around it (src/movement.c MoveNorth's
-- COL_NORTH_WEST / COL_NORTH_EAST cases)
function Player:moveBy(dx, dy)
  local moved = false
  if dx ~= 0 then
    local nx = self.x + dx
    if not self:blocked(nx, self.y) then self.x = nx; moved = true
    elseif dy == 0 then
      for _, n in ipairs({ -1, 1 }) do
        if not self:blocked(nx, self.y + n * 4) and not self:blocked(self.x, self.y + n) then
          self.y = self.y + n; moved = true; break
        end
      end
    end
  end
  if dy ~= 0 then
    local ny = self.y + dy
    if not self:blocked(self.x, ny) then self.y = ny; moved = true
    elseif dx == 0 then
      for _, n in ipairs({ -1, 1 }) do
        if not self:blocked(self.x + n * 4, ny) and not self:blocked(self.x + n, self.y) then
          self.x = self.x + n; moved = true; break
        end
      end
    end
  end
  return moved
end

local function facingFor(dx, dy, current)
  -- keep the current facing if it is one of the held directions
  if dy < 0 and current == 0 then return 0 end
  if dx > 0 and current == 2 then return 2 end
  if dy > 0 and current == 4 then return 4 end
  if dx < 0 and current == 6 then return 6 end
  if dy < 0 then return 0 end
  if dy > 0 then return 4 end
  if dx > 0 then return 2 end
  if dx < 0 then return 6 end
  return current
end

function Player:frontPoint(dist)
  dist = dist or 12
  local s = self.animationState
  if s == 0 then return self.x, self.y - dist - 2 end
  if s == 2 then return self.x + dist, self.y - 2 end
  if s == 4 then return self.x, self.y + dist - 2 end
  return self.x - dist, self.y - 2
end

-- the tile in front, as the cartridge probes it (gUnk_080B4468:
-- north (0,-15), east (12,-3), south (0,9), west (-12,-3))
local PROBE = { [0] = { 0, -15 }, [2] = { 12, -3 }, [4] = { 0, 9 }, [6] = { -12, -3 } }
function Player:probe()
  local p = PROBE[self.animationState] or PROBE[4]
  return self.x + p[1], self.y + p[2]
end

local function dirInput(input)
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  return dx, dy
end

function Player:walk(dx, dy, speed, anim, idle)
  if dx ~= 0 or dy ~= 0 then
    if not self.lockFacing then self.animationState = facingFor(dx, dy, self.animationState) end
    if dx ~= 0 and dy ~= 0 then speed = speed * 0.70710678 end
    self:moveBy(dx * speed, dy * speed)
    self.moving = true
    self:setAnim(anim)
    return true
  end
  self.moving = false
  self:setAnim(idle)
  return false
end

-- hurt: knockback away from (sx, sy), damage in save units (8 = a heart)
function Player:hurt(damage, sx, sy)
  if self.invuln > 0 or self.state == "dead" or self.state == "itemget" then return false end
  local f = self.field
  f:modStat("health", -damage)
  f:sound(0x7A) -- SFX_PLY_VO7-ish grunt (named SFX in sound.h are sparse)
  local dx, dy = self.x - (sx or self.x), self.y - (sy or self.y + 1)
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.01 then dx, dy, d = 0, 1, 1 end
  self.kbx, self.kby = dx / d * 2, dy / d * 2
  self.invuln = 60
  if self.state == "carry" then f:objects():dropCarried(self) end
  self.state = "hurt"
  self.timer = 12
  if (f.save.stats.health or 0) <= 0 then
    self.state = "dead"
    self.timer = 90
    f:sound(0x87) -- SFX_PLY_DIE
  end
  return true
end

-- the shield blocks hits from the front while held (and not Minish)
function Player:blocksFrom(sx, sy)
  if self.state ~= "shield" then return false end
  local dx, dy = sx - self.x, sy - self.y
  local s = self.animationState
  if s == 0 then return dy < 0 and math.abs(dx) <= -dy + 4 end
  if s == 4 then return dy > 0 and math.abs(dx) <= dy + 4 end
  if s == 2 then return dx > 0 and math.abs(dy) <= dx + 4 end
  return dx < 0 and math.abs(dy) <= -dx + 4
end

function Player:startItemGet(item)
  self.state = "itemget"
  self.heldItem = item
  self:setAnim(self.hasCap and ANIM.getItem or ANIM.getItemNoCap, true)
end

-- the item on A or B
function Player:useItem(item, button, input)
  local f = self.field
  local I = Player.ITEM
  if not item or item == 0 then return false end
  if item >= I.SMITH_SWORD and item <= I.FOURSWORD then
    self.state = "sword"
    self.timer = 24
    self.swordButton = button
    self:setAnim(self:animFor("sword"), true)
    f:items():swordStart(self)
    return true
  elseif (item == I.SHIELD or item == I.MIRROR_SHIELD) and not self.minish then
    self.state = "shield"
    self.itemButton = button
    return true
  elseif item == I.GUST_JAR and not self.minish then
    self.state = "gust"
    self.itemButton = button
    self.timer = 0
    f:items():gustStart(self)
    return true
  end
  return false
end

function Player:update(input)
  local f = self.field
  if self.invuln > 0 then self.invuln = self.invuln - 1 end
  local walkAnim = self:animFor("walk")
  local idleAnim = self:animFor("idle")
  local st = self.state

  if st == "dead" then
    self.timer = self.timer - 1
    self.anim:update(1)
    if self.timer <= 0 then f:onPlayerDied() end
    return
  elseif st == "hurt" then
    self:moveBy(self.kbx, self.kby)
    self.timer = self.timer - 1
    self.anim:update(1)
    if self.timer <= 0 then self.state = "normal" end
    return
  elseif st == "itemget" then
    self.anim:update(1)
    if not f:messageActive() then
      self.itemGetHold = (self.itemGetHold or 0) + 1
      if self.itemGetHold > 4 then self.state = "normal"; self.heldItem = nil; self.itemGetHold = nil end
    end
    return
  elseif st == "portal" then
    self.anim:update(1)
    self.timer = self.timer - 1
    if self.timer <= 0 then f:objects():portalDone(self) end
    return
  elseif st == "sword" then
    self.anim:update(1)
    f:items():swordFrame(self)
    self.timer = self.timer - 1
    if self.anim.done or self.timer <= 0 then self.state = "normal" end
    return
  elseif st == "roll" then
    self.anim:update(1)
    self.timer = self.timer - 1
    local s = self.animationState
    local dx = (s == 2 and 1 or s == 6 and -1 or 0) * Player.ROLL_SPEED
    local dy = (s == 4 and 1 or s == 0 and -1 or 0) * Player.ROLL_SPEED
    self:moveBy(dx, dy)
    if self.timer <= 0 then self.state = "normal" end
    return
  elseif st == "throw" then
    self.anim:update(1)
    self.timer = self.timer - 1
    if self.timer <= 0 then self.state = "normal" end
    return
  end

  if self.scriptAnim then
    self:setAnim(self.scriptAnim)
    self.anim:update(1)
    return
  end
  if self.scriptWalking ~= nil then
    -- a player script moves Link; only animate
    self:setAnim(self.scriptWalking and walkAnim or idleAnim)
    self.anim:update(1)
    return
  end

  local locked = not self.control or f:inputLocked()
  local dx, dy = 0, 0
  if not locked then dx, dy = dirInput(input) end

  if st == "carry" then
    if not locked and (input.pressed("r") or input.pressed("a") or input.pressed("b")) then
      f:objects():throwCarried(self)
      self.state = "throw"
      self.timer = 10
      self:setAnim(ANIM.throw, true)
      return
    end
    self:walk(dx, dy, Player.WALK_SPEED, ANIM.carry, ANIM.carry)
    if not self.moving then return end
    self.anim:update(1)
    return
  elseif st == "shield" then
    if locked or not input.down(self.itemButton or "a") then self.state = "normal"
    else
      local cap = self.hasCap and ANIM.shield or ANIM.shieldNoCap
      self.lockFacing = true
      if self:walk(dx, dy, Player.SHIELD_SPEED, self.hasCap and ANIM.shieldWalk or cap, cap) then self.anim:update(1) end
      self.lockFacing = nil
      return
    end
  elseif st == "gust" then
    if locked or not input.down(self.itemButton or "a") then
      f:items():gustRelease(self)
      self.state = "normal"
    else
      self.lockFacing = true
      if self:walk(dx, dy, Player.GUST_SPEED, ANIM.gustWalk, ANIM.gust) then self.anim:update(1) end
      self.lockFacing = nil
      f:items():gustFrame(self)
      return
    end
  end

  if not locked then
    for _, b in ipairs({ "b", "a" }) do
      if input.pressed(b) and not self.minish then
        local item = f:equipped(b)
        if self:useItem(item, b, input) then return end
      end
    end
    if self.minish and (input.pressed("b") or input.pressed("a")) then
      -- Minish Link only swings the sword
      for _, b in ipairs({ "b", "a" }) do
        local item = f:equipped(b)
        if input.pressed(b) and item and item >= 1 and item <= 6 then
          if self:useItem(item, b, input) then return end
        end
      end
    end
    if input.pressed("r") then
      if f:tryAction(self) then return end
      if (dx ~= 0 or dy ~= 0) then
        self.animationState = facingFor(dx, dy, self.animationState)
        self.state = "roll"
        self.timer = 16
        self:setAnim(self:animFor("roll"), true)
        return
      end
    end
  end

  if self:walk(dx, dy, Player.WALK_SPEED, walkAnim, idleAnim) then
    self.anim:update(1)
  elseif not self.minish then
    self.anim:update(1)
  end
end

function Player:draw(camX, camY, palette)
  if self.hidden then return end
  if self.invuln > 0 and self.invuln % 4 < 2 and self.state ~= "itemget" then return end
  local A = self.field.assets
  local sprite = self:sprite()
  local frame = self.anim.frame
  if frame == 0xFF then return end
  local img, ox, oy = A:spriteFrame(sprite, frame, palette, "link")
  if not img then return end
  local x = math.floor(self.x - camX)
  local y = math.floor(self.y - camY - (self.z or 0))
  if self.anim:hflip() then
    love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else
    love.graphics.draw(img, x + ox, y + oy)
  end
  -- the item held up during an item get, and the carried pot / bush
  if self.state == "itemget" and self.heldItem then
    self.field:objects():drawItemIcon(self.heldItem, x, y - 22)
  elseif self.carried then
    self.field:objects():drawCarried(self.carried, x, y - 14)
  end
end

return Player
