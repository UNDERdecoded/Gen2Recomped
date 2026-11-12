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
                    [0x736] = true, [0x737] = true, [0x73A] = true, [0x73B] = true,
                    [0x1B8] = true, [0x1BA] = true, [0x458] = true } -- round 11: ANIM_FALL (+ Minish, no cap)
NO_FACING[0x1B9], NO_FACING[0x45B], NO_FACING[0x45F] = true, true, true -- round 22: ANIM_GET_ITEM_BIG (+ no cap), _SWORD

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
  if not NO_FACING[base] then
    index = index + rshift(self.animationState, 1)
    -- bug round: sub_08079064 also sets the entity's spriteSettings.flipX
    -- for a facing animation (animationState >= 5, i.e. left); the drawer
    -- XORs it with the keyframe's flip. Without it Link faced right when
    -- walking, standing or swinging left.
    self.entFlip = self.animationState >= 5
  end
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
  -- round 9: Link's own collision tables (sub_080085CC picks one by state)
  local tab = 0
  if self.swimming then tab = self.minish and 2 or 3
  elseif (self.z or 0) > 0 or self.jumping then tab = 4
  elseif self.minish then tab = 1
  elseif self.carried or self.gusting then tab = 5 end
  local sw = self.swimming and true or false
  local function solid(px, py) return room:isSolidPlayer(px, py, self.layer, tab, sw) end
  if solid(x - hw, y + top) or solid(x + hw - 1, y + top)
     or solid(x - hw, y + bottom) or solid(x + hw - 1, y + bottom) then
    -- round 8: ladder tiles are solid in the collision data; Link walks
    -- into them lined up with the ladder (Climb.lua)
    if not (not self.minish and require("src.zelda.tmc.Climb").enterable(self.field, x, y)) then return true end
  end
  return self.field:entityBlocks(self, x, y)
end

-- one axis at a time, with the cartridge's corner nudge: if only one front
-- corner is caught, slide sideways around it (src/movement.c MoveNorth's
-- COL_NORTH_WEST / COL_NORTH_EAST cases)
-- round 10: a blocked step still ends flush with the wall (the cartridge
-- works in whole pixels: x.HALF.HI): Link moves to the last free whole pixel
-- before the obstacle, so a sub-pixel remainder (e.g. y 524.75 at a south
-- border lane) never keeps him a pixel short of an edge or a door
local function snapTo(self, cur, new, axis)
  local t = new > cur and math.floor(new) or math.ceil(new)
  local step = new > cur and -1 or 1
  while (new > cur and t > cur) or (new < cur and t < cur) do
    local free
    if axis == "x" then free = not self:blocked(t, self.y) else free = not self:blocked(self.x, t) end
    if free then return t end
    t = t + step
  end
  return nil
end

-- round 11: the cartridge probes only the leading edge of a move
-- (movement.c MoveNorth/East/...): when Link stands embedded in something
-- solid (a pushed statue settling against him, an object pushing him out)
-- he can still step away as long as the side he moves toward is free
function Player:leadFree(nx, ny, dx, dy)
  local room = self.field.room
  local hw, top, bottom = HW, TOP, BOTTOM
  if self.minish then hw, top, bottom = HW_MINISH, TOP_MINISH, BOTTOM_MINISH end
  local tab = self.minish and 1 or 0
  local function solid(px, py) return room:isSolidPlayer(px, py, self.layer, tab, self.swimming and true or false) end
  if dx > 0 then return not (solid(nx + hw - 1, ny + top) or solid(nx + hw - 1, ny + bottom)) end
  if dx < 0 then return not (solid(nx - hw, ny + top) or solid(nx - hw, ny + bottom)) end
  if dy > 0 then return not (solid(nx - hw, ny + bottom) or solid(nx + hw - 1, ny + bottom)) end
  if dy < 0 then return not (solid(nx - hw, ny + top) or solid(nx + hw - 1, ny + top)) end
  return true
end

function Player:moveBy(dx, dy)
  -- round 18: Minish doors / log tunnels (MinishTunnel.lua)
  if self.tunnel then local tm = require("src.zelda.tmc.MinishTunnel").move(self, dx, dy); if tm ~= nil then return tm end end
  local moved = false
  local embedded = (dx ~= 0 or dy ~= 0) and self:blocked(self.x, self.y)
  if dx ~= 0 then
    local nx = self.x + dx
    local sx = self:blocked(nx, self.y) and snapTo(self, self.x, nx, "x")
    if sx and sx ~= self.x then self.x = sx; moved = true
    elseif not self:blocked(nx, self.y) then self.x = nx; moved = true
    elseif embedded and self:leadFree(nx, self.y, dx, 0) then self.x = nx; moved = true
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
    local sy = self:blocked(self.x, ny) and snapTo(self, self.y, ny, "y")
    if sy and sy ~= self.y then self.y = sy; moved = true
    elseif not self:blocked(self.x, ny) then self.y = ny; moved = true
    elseif embedded and self:leadFree(self.x, ny, 0, dy) then self.y = ny; moved = true
    elseif dx == 0 then
      for _, n in ipairs({ -1, 1 }) do
        if not self:blocked(self.x + n * 4, ny) and not self:blocked(self.x + n, self.y) then
          self.x = self.x + n; moved = true; break
        end
      end
    end
  end
  if self.minish and moved then require("src.zelda.tmc.MinishTunnel").surface(self) end -- round 18
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
  if self.inCart then return false end -- round 7: in a mine cart (hurtType 30)
  -- round 23: the mushroom fling (PLAYER_08072C9C) runs with COLLISION_OFF from
  -- sub_08072CC0 until it lands (sub_08072D54's COLLISION_ON) -- a hit mid-flight
  -- used to end the fling and leave Link at z > 0 (no lifting afterwards)
  if self.fling and (self.fling.phase or 0) < 3 then return false end
  local f = self.field
  f:modStat("health", -damage)
  f:sound(0x7A) -- SFX_PLY_VO7-ish grunt (named SFX in sound.h are sparse)
  local dx, dy = self.x - (sx or self.x), self.y - (sy or self.y + 1)
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.01 then dx, dy, d = 0, 1, 1 end
  self.kbx, self.kby = dx / d * 2, dy / d * 2
  self.invuln = 60
  if self.state == "carry" then f:objects():dropCarried(self) end
  -- round 20: hit while gliding (PlayerParachute: iframes -> the fall, still in the air)
  if (self.para or self.fall) and require("src.zelda.tmc.Whirlwind").hurt(self) then return true end
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
  do local x = require("src.zelda.tmc.Crenel").useItem(self, item, button, input) if x then return true end end -- round 5
  return false
end

function Player:update(input)
  local f = self.field
  if self.invuln > 0 then self.invuln = self.invuln - 1 end
  require("src.zelda.tmc.Layers").surface(f, self) -- round 23: sub_0807A8D8 (every frame): the tile-type flags pick the layer
  local walkAnim = self:animFor("walk")
  local idleAnim = self:animFor("idle")
  local st = self.state

  do local x = require("src.zelda.tmc.ItemsR26").frame(self, input) if x then return end end -- round 26A: item states (sword charge/spin, swimming...; ItemsR26.lua)
  do local x = require("src.zelda.tmc.R27B").playerFrame(self, input) if x then return end end -- round 27b: frozen Link etc. (R27B.lua)
  if st == "ext" then return self.extUpdate(self, input) end -- round 5 (Crenel.lua: cane, spring jump)
  if st == "dead" then
    self.timer = self.timer - 1
    self.anim:update(1)
    if self.timer <= 0 and require("src.zelda.tmc.CrenelPath").fairyRevive(self) then return end -- round 22: a bottled fairy
    if self.timer <= 0 then f:onPlayerDied() end
    return
  elseif st == "hurt" then
    self:moveBy(self.kbx, self.kby)
    self.timer = self.timer - 1
    self.anim:update(1)
    if self.timer <= 0 then self.state = "normal" end
    return
  elseif st == "itemget" then
    require("src.zelda.tmc.ItemGet").update(f, self) -- round 22: PLAYER_ITEMGET (ItemGet.lua)
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
  if f.macroInput then locked = false end -- a player macro drives Link in cutscenes
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
      -- round 13: GustJar.release puts Link in the blow state (ext)
      if self.state == "gust" then self.state = "normal" end
      if self.state ~= "normal" then return end
    else
      self.lockFacing = true
      if self.jar and self.jar.state == "pullout" then self.anim:update(1)
      elseif self:walk(dx, dy, Player.GUST_SPEED, ANIM.gustWalk, ANIM.gust) then self.anim:update(1) end
      self.lockFacing = nil
      f:items():gustFrame(self)
      return
    end
  end

  if not locked then
    -- bug round: A talks / reads / opens before it uses the A item
    if input.pressed("a") and f:tryInteractA(self) then return end
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
        if input.pressed(b) and item and ((item >= 1 and item <= 6) or (item >= 0x1C and item <= 0x1F)) then -- round 8: bottles too
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

  local x0, y0 = self.x, self.y
  do local pa = require("src.zelda.tmc.PushAnim").anim(self) if pa then walkAnim, idleAnim = pa, pa end end -- round 12: ANIM_PUSH
  do local lw, li = require("src.zelda.tmc.ItemLantern").walkAnims(self) if lw then walkAnim, idleAnim = lw, li end end -- round 26A: walking with the lit lantern (ANIM_LANTERN $608 / ON $604)
  if self:walk(dx, dy, Player.WALK_SPEED, walkAnim, idleAnim) then
    self.anim:update(1)
  elseif not self.minish then
    self.anim:update(1)
  end
  require("src.zelda.tmc.Climb").surface(self) -- round 8: ladders, climb walls
  require("src.zelda.tmc.PortalJump").check(self, dx, dy, x0, y0) -- round 10: onto a portal stump
  require("src.zelda.tmc.Ledge").check(self, dx, dy) -- round 12: jumping off a ledge
  require("src.zelda.tmc.PushAnim").update(self, dx, dy, x0, y0) -- round 12: the push animation's frame flag
  if self.x ~= x0 or self.y ~= y0 then require("src.zelda.tmc.Layers").update(f, self) end -- round 11: CheckOnLayerTransition
end

-- Bug round (user report: "no sword animation or sprite"): the blade is
-- not part of Link's frames. The cartridge draws it as the PLAYER_ITEM_SWORD
-- entity attached to Link (playerItemSword.c): its sprite is the sword
-- level's (gPlayerItemDefinition_0: SPRITE_14 Smith's, SPRITE_15 White /
-- Red / Blue, SPRITE_16 Four Sword; OBJ palette 1), its frame is Link's
-- frameIndex - $6A (sub_080A78B8), flipped as Link's entity flipX, one more
-- time when Link faces sideways (no keyframe flip of its own), at Link's
-- position; Link's frame byte unk_1
-- picks the extra-sprite slot (sub_08078E84): 1 (set) over Link, 3 behind.
local SWORD_SPRITE = { [1] = 14, [2] = 15, [3] = 15, [4] = 15, [5] = 15, [6] = 16 }
-- the drawn flip: the keyframe's flip XOR the entity's flipX (above)
function Player:hflip() return self.anim:hflip() ~= (self.entFlip or false) end

function Player:swordPart(frame)
  if self.state ~= "sword" or self.minish then return nil end
  local item = self.field:equipped(self.swordButton or "b")
  local si = SWORD_SPRITE[item or 1] or 14
  local sf = (frame or 0) - 0x6A
  if sf < 0 or sf > 0x8A then return nil end
  local A = self.field.assets
  local link = A:sprite(self:sprite())
  local lf = link and link.frames and link.frames[frame]
  local front = not (lf and (lf[2] or 0) == 0)
  return si, sf, front
end

function Player:drawSword(x, y, si, sf)
  local A = self.field.assets
  local img, ox, oy = A:spriteFrame(si, sf, A:objPalette(1), "sword")
  if not img then return end
  local flip = self.entFlip or false
  if band(self.animationState or 0, 2) ~= 0 then flip = not flip end
  if flip then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
end

function Player:draw(camX, camY, palette)
  if self.hidden or self.tunnel then return end -- round 18: tunnel = hidden in a Minish door / log
  if self.invuln > 0 and self.invuln % 4 < 2 and self.state ~= "itemget" then return end
  local A = self.field.assets
  local sprite = self:sprite()
  local frame = self.anim.frame
  if frame == 0xFF then return end
  local img, ox, oy = A:spriteFrame(sprite, frame, palette, "link")
  if not img then return end
  local x = math.floor(self.x - camX)
  local y = math.floor(self.y - camY - (self.z or 0))
  if self.spriteOY and self.spriteOYFrame == self.field.frame then y = y + self.spriteOY end -- round 25: gPlayerState.spriteOffsetY (lava platforms, Gleerok's neck), set each frame it applies
  -- round 7: a cart under him (Minecart.lua), the cane over him (Pacci.lua)
  if self.drawUnder then self.drawUnder(self, x, math.floor(self.y - camY)) end
  local si, sf, front = self:swordPart(frame)
  if si and not front then self:drawSword(x, y, si, sf) end
  if self:hflip() then
    love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else
    love.graphics.draw(img, x + ox, y + oy)
  end
  if si and front then self:drawSword(x, y, si, sf) end
  if self.drawOver then self.drawOver(self, x, y) end
  require("src.zelda.tmc.ItemsR26").draw(self, x, y) -- round 26A: item parts drawn over Link (ItemsR26.lua)
  -- the item held up during an item get, and the carried pot / bush
  if self.state == "itemget" and self.heldItem then
    require("src.zelda.tmc.ItemGet").drawHeld(self, x, y) -- round 22: LINK_HOLDING_ITEM's place
  elseif self.carried then
    self.field:objects():drawCarried(self.carried, x, y - 14)
  end
end

return Player
