-- Round 26A: swimming with the Flippers (ITEM_FLIPPERS $46).
--
-- PORTED (decomp):
--   player.c sub_08074808 (SurfaceAction_Water with the Flippers):
--     ResetLantern; swim_state 8 (1 for PL_FLAGS10000, not used here),
--     speed 0, FX_WATER_SPLASH (not Minish), SFX_1A5, ResetActiveItems;
--     while (swim_state & $F) != 1 sub_08079744 nudges Link 1 px a frame
--     toward the tile centre (8, 8) and swim_state counts down.
--   playerUtils.c PlayerSwimming: base speed $C0 ($100 with
--     ITEM_SWIM_BUTTERFLY); speed below it -> the base speed in the d-pad's
--     direction; above it (a stroke) the speed drops by 4 a frame and the
--     direction is kept (at exactly the base speed it also takes 4 off, so
--     plain swimming alternates $C0 / $BC and samples the d-pad every other
--     frame, as the C does).  ToggleDiving: B (INPUT_CANCEL) flips swim_state
--     bit $80, remainingDiveTime $78, SFX_TOGGLE_DIVING; the dive ends when
--     the time runs out (SFX_TOGGLE_DIVING) or on B again.
--     PlayerUpdateSwimming: A (INPUT_INTERACT) strokes: speed $180 ($1C0
--     with the Swim Butterfly), direction = d-pad or facing (sub_08079520),
--     SFX_162; FX_RIPPLE every 8 frames moving, every 16 still.
--   Animations: ANIM_SWIM_STILL $28C / ANIM_SWIM_MOVE $290 (+ facing),
--     ANIM_DIVE $2BE (ResolvePlayerAnimation), Minish ANIM_SWIM_MINISH
--     $C0C / ANIM_DIVE_MINISH $C1C.
--   itemOnGround.c ItemOnGround_Sunken_Action2: a sunken item (kind 8)
--     touched while diving (not Minish, USA) -> ItemOnGround_Kind1_Init ->
--     sub_08081598: picked up, the hop over Link's head (action 4, 14
--     frames, zVelocity 2.0).
--   sub_08073D20: off SURFACE_WATER -> swim_state 0 (back on land).
-- SIMPLIFIED: the stroke and swim move straight at the speed (no
--   sub_08079E08 sliding); sub_080793E4($10) (hurt by a solid push while
--   swimming) is not ported; "out of the water" is the ACT under Link's
--   feet no longer being ACT_WATER (Dungeon:checkFall's probe), shallow
--   water is not a swim surface here; while diving p.diving is set
--   (collisionFlags |= 4: the cartridge's enemies skip a diver; the port's
--   enemies may read it).
local bit = require("bit")
local band = bit.band

local Swim = {}

Swim.ITEM_FLIPPERS, Swim.ITEM_SWIM_BUTTERFLY = 0x46, 0x72
Swim.ITEM_LANTERN_OFF, Swim.ITEM_LANTERN_ON = 0x0F, 0x10
Swim.ACT_WATER = 0x10
Swim.SPEED, Swim.SPEED_BF = 0xC0, 0x100          -- PlayerSwimming
Swim.STROKE, Swim.STROKE_BF = 0x180, 0x1C0       -- PlayerUpdateSwimming
Swim.DIVE_TIME = 0x78                            -- ToggleDiving
Swim.ANIM = { still = 0x28C, move = 0x290, dive = 0x2BE, minish = 0xC0C, diveMinish = 0xC1C }
Swim.SFX = { ENTER = 0x1A5, DIVE = 0x163, STROKE = 0x162 }
Swim.FX = { SPLASH = 0x0B, RIPPLE = 0x20 }
local SPECIAL_FX = 0x0F

local function inv(f, item) return (f.inventory and f:inventory(item) or 0) > 0 end

local function dirInput(input)
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  return dx, dy
end

local function facingFor(dx, dy, cur)
  if dy < 0 and cur == 0 then return 0 end
  if dx > 0 and cur == 2 then return 2 end
  if dy > 0 and cur == 4 then return 4 end
  if dx < 0 and cur == 6 then return 6 end
  if dy < 0 then return 0 end
  if dy > 0 then return 4 end
  if dx > 0 then return 2 end
  if dx < 0 then return 6 end
  return cur
end

-- an animation without the facing (Player's NO_FACING is local)
local function setAnimFlat(p, id)
  local s = p.animationState
  p.animationState = 0
  p:setAnim(id)
  p.animationState = s
end
Swim.setAnimFlat = setAnimFlat

-- ResetLantern (playerUtils.c): the lit lantern back to ITEM_LANTERN_OFF
function Swim.resetLantern(p)
  local f = p.field
  local eq = f.save and f.save.equip
  if eq then
    for _, b in ipairs({ "a", "b" }) do if eq[b] == Swim.ITEM_LANTERN_ON then eq[b] = Swim.ITEM_LANTERN_OFF end end
  end
  p.lanternLit, p.lantern = nil, nil
end

local function onWater(d, p)
  return d:actAt(p.x, p.y - 1, p.layer) == Swim.ACT_WATER
end

function Swim.stop(p)
  p.swimming, p.diving, p.swim = nil, nil, nil
  if p.state == "ext" and p.extUpdate == Swim.update then p.state, p.extUpdate = "normal", nil end
  p.animId = -1
end

-- sub_08081598: the sunken item picked up
local function pickUp(f, p, e)
  local O = f:objects()
  e.buried, e.hidden = nil, false
  O:collect(e)
  -- an item with an item-get scene went straight to it (no hop)
  if p.state == "itemget" then return end
  e.deleted = nil
  e.act, e.timer, e.cz, e.czv, e.hidden = 4, 14, -math.floor(((p.z or 0) + 4) * 65536), 2 * 65536, false
  e.pickedUp = true
end

-- ItemOnGround_Sunken_Action2 against Link (IsColliding, the item's and
-- Link's boxes as Objects:updateGround uses them)
function Swim.findSunken(f, p)
  if p.minish then return nil end
  for _, e in ipairs(f.entities or {}) do
    if e.buried == 8 and not e.deleted and math.abs(math.floor(p.x) - e.x) <= 8 and math.abs(math.floor(p.y) - e.y) <= 8 then
      pickUp(f, p, e)
      return e
    end
  end
  return nil
end

-- Dungeon:checkFall hook (ItemsR26.water): Link on ACT_WATER
function Swim.water(d, p, act)
  if act ~= Swim.ACT_WATER then return nil end
  local f = d.field
  if f:inventory(Swim.ITEM_FLIPPERS) == 0 then return nil end -- PLAYER_DROWN: the old respawn
  local resume = p.swimming and p.swim
  p.swimming = true
  p.state, p.extUpdate = "ext", Swim.update
  p.swimDungeon = d
  if resume then return true end
  Swim.resetLantern(p)
  p.swim = { state = 8, speed = 0, dir = nil, dive = 0, t = 0 }
  if not p.minish then f:addFx(p.x, p.y, SPECIAL_FX, Swim.FX.SPLASH) end
  f:sound(Swim.SFX.ENTER)
  p.lockFacing = nil
  return true
end

function Swim.update(p, input)
  local f = p.field
  local d = p.swimDungeon or f._dungeon
  local s = p.swim
  if not s or not d then Swim.stop(p) return end
  s.t = s.t + 1
  -- entering: sub_08079744 toward the tile centre
  if band(s.state, 0xF) ~= 1 then
    local tx = math.floor(p.x) % 16
    local ty = math.floor(p.y) % 16
    if tx ~= 8 then p.x = p.x + (tx > 8 and -1 or 1) end
    if ty ~= 8 then p.y = p.y + (ty > 8 and -1 or 1) end
    s.state = s.state - 1
  end
  local locked = not p.control or (f.inputLocked and f:inputLocked())
  local dx, dy = 0, 0
  if not locked then dx, dy = dirInput(input) end
  local held = dx ~= 0 or dy ~= 0
  if held then p.animationState = facingFor(dx, dy, p.animationState) end
  local base = inv(f, Swim.ITEM_SWIM_BUTTERFLY) and Swim.SPEED_BF or Swim.SPEED
  local entering = band(s.state, 0xF) ~= 1
  if base > s.speed then
    s.speed = base
    s.dir = held and { dx, dy } or nil
  else
    s.speed = s.speed - 4
  end
  if not entering then
    local pressB = not locked and input.pressed("b")
    if s.dive == 0 then
      if pressB then -- ToggleDiving
        p.diving = true
        s.dive = Swim.DIVE_TIME
        f:sound(Swim.SFX.DIVE)
      else
        -- PlayerUpdateSwimming
        if not locked and input.pressed("a") then
          s.speed = inv(f, Swim.ITEM_SWIM_BUTTERFLY) and Swim.STROKE_BF or Swim.STROKE
          if held then s.dir = { dx, dy }
          else
            local st = p.animationState
            s.dir = { st == 2 and 1 or st == 6 and -1 or 0, st == 4 and 1 or st == 0 and -1 or 0 }
          end
          f:sound(Swim.SFX.STROKE)
        end
        if s.dir == nil then
          if s.t % 16 == 0 then f:addFx(p.x, p.y, SPECIAL_FX, Swim.FX.RIPPLE) end
        elseif s.t % 8 == 0 then f:addFx(p.x, p.y, SPECIAL_FX, Swim.FX.RIPPLE) end
      end
    else
      s.dive = s.dive - 1
      if s.dive ~= 0 then
        if pressB then p.diving, s.dive = nil, 0; f:sound(Swim.SFX.DIVE) end
      else
        p.diving = nil
        f:sound(Swim.SFX.DIVE)
      end
    end
  end
  -- the move
  if s.dir and not entering then
    local mx, my = s.dir[1], s.dir[2]
    local sp = s.speed / 256
    if mx ~= 0 and my ~= 0 then sp = sp * 0.70710678 end
    p:moveBy(mx * sp, my * sp)
  end
  p.moving = s.dir ~= nil
  -- the animation (ResolvePlayerAnimation / sub_080797EC)
  if p.minish then
    if p.diving then setAnimFlat(p, Swim.ANIM.diveMinish) else p:setAnim(Swim.ANIM.minish) end
  elseif p.diving then setAnimFlat(p, Swim.ANIM.dive)
  else p:setAnim(held and Swim.ANIM.move or Swim.ANIM.still) end
  p.anim:update(1)
  if p.diving then Swim.findSunken(f, p) end
  -- back on land
  if not onWater(d, p) then Swim.stop(p) end
end

-- every frame: a swim cut off (room change, knockback) on dry land ends
function Swim.frame(p, input)
  if p.swimming and p.state ~= "ext" and p.state ~= "hurt" then
    local d = p.field and p.field._dungeon
    if not d or not onWater(d, p) then p.swimming, p.diving, p.swim = nil, nil, nil end
  end
  return nil
end

return Swim
