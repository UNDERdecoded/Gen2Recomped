-- Round 26 (team A): the sword's split charge and the Link clones:
-- src/playerUtils.c (gPlayerChargeActions: sub_08078008, sub_08078124,
-- sub_08078140, sub_08078070, sub_080780E0, sub_08078108; DeleteClones;
-- IsPreventedFromUsingItem's R cancel), src/player.c
-- (SurfaceAction_CloneTile) and src/object/playerClone.c (PlayerClone_Init /
-- _Action1 / _Action2, sub_08084B1C, sub_08084CAC).
--
--   ChargeState (gPlayerState.chargeState), every frame:
--     0  the sword on A (else B) is Red / Blue / Four ($03 / $04 / $06; the
--        Smith's and the White sword can't split) and fully charged (spin
--        charge done = sword_state $20): preChargeTimer + 1, past 20 -> 10,
--        action 3; else preChargeTimer 0.
--     3  still charged: chargeTimer + 6 (+ 12 with ITEM_SKILL_FAST_SPLIT
--        $74); at 800 -> action 4, SFX_ITEM_SWORD_CHARGE_FINISH ($D8); every
--        20 SFX_ITEM_SWORD_CHARGE ($D7); not charged -> action 1.
--     4  the spin starts (sword_state $40) -> action 5 when PL_CLONING (all
--        clones made), else the spin's sub_08075694 cancels (action 1,
--        DeleteClones); not charged -> action 1.
--     5  chargeTimer - 1 each frame, below 0 -> action 2 (clones go).
--     1  chargeTimer - 16, below 0 -> action 2.  2: preChargeTimer - 1, below
--        0 -> action 0.
--   SurfaceAction_CloneTile (Link on ACT_TILE_87 = $57) in action 4: clones
--     allowed n = 1 (Red) / 2 (Blue) / 3 (Four); the first free slot gets a
--     PLAYER_CLONE at Link; all made -> PL_CLONING, Link snapped to the tile
--     centre (x / y & ~$F | 8).
--   PlayerClone_Init: on the tile centre, animation 8, SPECIAL_TILE_22 on
--     its tile (no second clone there), SFX_112.  Action1: blinks while
--     action 4; action 5 -> drawn, offset (unk78 / 7a) from Link kept,
--     the delay subtimer (type + 1) * 15; any other action -> gone, the
--     tile back (TILE_TYPE_789).  Action2: copies Link's frame each frame,
--     at Link + offset; Link hit (iframes) -> action 1; boxed in on every
--     side (no PlayerCloneCollisions pattern free) -> 30 blinking frames
--     -> action 1.  Ends: DeleteClones, FX_SPARKLE_SECRET, SFX_18F.
--   R pressed while cloning (IsPreventedFromUsingItem) -> action 1.
-- The clones are f.playerClones (FoWObjects.cloneOn / ToDObjects / DHC read
-- it): { x, y, z, layer, playerClone = true }.  Their sword: while Link's
-- sword box is out (f.swordBoxNow), the same box at each clone hits enemies.
-- SIMPLIFIED: the clone's own PLAYER_ITEM_SWORD child entity is that box
--   copy; the collision patterns are "the clone's spot is solid"; the clone
--   tile swap uses a per-room used-tile set (no SPECIAL_TILE_22 graphics).
local bit = require("bit")
local band, bor = bit.band, bit.bor

local M = {}
M.ACT_CLONE_TILE = 0x57
M.SKILL_FAST_SPLIT = 0x74
M.CHARGE_MAX = 800
M.SFX = { FINISH = 0xD8, CHARGE = 0xD7, CLONE = 0x112, VO2 = 0x76, GONE = 0x18F }
M.CLONES = { [3] = 1, [4] = 2, [6] = 3 }

local function isSword(i) return i and i >= 1 and i <= 6 end
local function clones(f) local c = rawget(f, "playerClones") return type(c) == "table" and c or nil end
local function swordType(f)
  local a, b = f:equipped("a"), f:equipped("b")
  local t = isSword(a) and a or (isSword(b) and b or nil)
  if t == 1 or t == 2 then return nil end
  return t
end
function M.state(p)
  local cs = p.chargeState
  if not cs then cs = { action = 0, pre = 0, timer = 0 } p.chargeState = cs end
  return cs
end
local function charged(p) return p.ss and p.ss.mode == "charge" and p.ss.charged end
local function spinning(p) return p.ss and p.ss.mode == "spin" end

function M.deleteClones(f, fx)
  for _, c in ipairs(clones(f) or {}) do
    c.deleted = true
    if fx and f.addFx then f:addFx(c.x, c.y, 0x0F, 0x3F) end -- FX_SPARKLE_SECRET
  end
  if fx and clones(f) and #clones(f) > 0 then f:sound(M.SFX.GONE) end
  f.playerClones = {}
  local p = f.player
  if p then
    p.cloning = nil
    local cs = M.state(p)
    if cs.action == 4 or cs.action == 5 then cs.action = 1 end
  end
end

local function newClone(f, p, i)
  local x = band(math.floor(p.x), 0xFFF0) + 8
  local y = band(math.floor(p.y), 0xFFF0) + 8
  local c = { type = i, x = x, y = y, z = 0, layer = p.layer, playerClone = true, action = 1, draw = true, timer = 0, subtimer = 0 }
  f.playerClones = clones(f) or {}
  f.playerClones[#f.playerClones + 1] = c
  f.cloneTiles = f.cloneTiles or {}
  f.cloneTiles[math.floor(x / 16) .. ":" .. math.floor(y / 16)] = f.room
  f:sound(M.SFX.CLONE)
  return c
end

-- SurfaceAction_CloneTile
function M.cloneTile(f, p)
  local cs = M.state(p)
  if cs.action ~= 4 or p.cloning then return end
  if (f._dungeon:actAt(p.x, p.y, p.layer) or 0) ~= M.ACT_CLONE_TILE then return end
  local key = math.floor(p.x / 16) .. ":" .. math.floor(p.y / 16)
  if f.cloneTiles and f.cloneTiles[key] == f.room then return end -- SPECIAL_TILE_22 on a used tile
  local n = M.CLONES[cs.swordType or 0] or 0
  local have = #(clones(f) or {})
  if have < n then newClone(f, p, have) end
  if #(clones(f) or {}) >= n then
    p.cloning = true
    p.x = band(math.floor(p.x), 0xFFF0) + 8
    p.y = band(math.floor(p.y), 0xFFF0) + 8
  end
end

local function cloneUpdate(f, p, c, cs)
  if c.action == 1 then
    if cs.action == 5 then
      c.action, c.draw, c.health = 2, true, 1
      c.subtimer = (c.type + 1) * 15
      c.ox, c.oy = c.x - math.floor(p.x), c.y - math.floor(p.y)
    elseif cs.action ~= 4 then
      return false
    else
      c.draw = not c.draw
      return true
    end
  end
  if c.subtimer == 1 then f:sound(M.SFX.VO2); c.subtimer = 0 elseif c.subtimer > 0 then c.subtimer = c.subtimer - 1 end
  if cs.action ~= 5 then return false end
  if (p.invuln or 0) >= 1 then cs.action = 1 return false end
  c.x, c.y, c.layer = math.floor(p.x) + c.ox, math.floor(p.y) + c.oy, p.layer
  c.frame, c.sprite, c.flip, c.animationState = p.anim.frame, p:sprite(), p.hflip and p:hflip() or false, p.animationState
  if f.room:isSolid(c.x, c.y - 2, c.layer) then
    if c.timer ~= 0 then
      c.timer = c.timer - 1
      if c.timer ~= 0 then c.draw = not c.draw return true end
      cs.action = 1
      return false
    end
    c.timer = 30
    return true
  end
  c.timer, c.draw = 0, true
  return true
end

-- the clones' swords: Link's sword box at each clone
local function cloneSwords(f, p)
  local b = f.swordBoxNow
  if not b or b.t ~= (f.frame or 0) - 1 or b.fromClone then return end
  local E = f:enemies()
  for _, c in ipairs(clones(f) or {}) do
    if c.action == 2 and not c.deleted then
      local dx, dy = c.x - math.floor(p.x), c.y - math.floor(p.y)
      E:swordHits({ x = b.x + dx, y = b.y + dy, w = b.w, h = b.h })
    end
  end
end

function M.frame(p, input)
  local f = p.field
  if not f or not f._dungeon or p.minish then return nil end
  local cs = M.state(p)
  -- a room change takes the clones away (InitializePlayer -> DeleteClones)
  local cl = clones(f)
  if cl and #cl > 0 and cl[1].room0 ~= f.room then
    if cl[1].room0 == nil then for _, c in ipairs(cl) do c.room0 = f.room end
    else M.deleteClones(f, false) end
  end
  local a = cs.action
  if a == 0 then
    local t = charged(p) and swordType(f)
    if t then
      cs.pre = cs.pre + 1
      if cs.pre > 20 then cs.pre, cs.action, cs.swordType = 10, 3, t end
    else cs.pre = 0 end
  elseif a == 3 then
    if charged(p) then
      cs.timer = cs.timer + (((f:inventory(M.SKILL_FAST_SPLIT) or 0) ~= 0) and 12 or 6)
      if cs.timer >= M.CHARGE_MAX then cs.timer, cs.action = M.CHARGE_MAX, 4; f:sound(M.SFX.FINISH)
      elseif cs.timer % 20 == 0 then f:sound(M.SFX.CHARGE) end
    else cs.action = 1 end
  elseif a == 4 then
    if spinning(p) then
      if p.cloning then cs.action = 5 else cs.action = 1; M.deleteClones(f, false) end
    elseif not charged(p) then cs.action = 1 end
  elseif a == 5 then
    cs.timer = cs.timer - 1
    if cs.timer < 0 then cs.timer, cs.action = 0, 2 end
    if input and input.pressed("r") and p.cloning then cs.action = 1 end
  elseif a == 1 then
    cs.timer = cs.timer - 16
    if cs.timer < 0 then cs.timer, cs.action = 0, 2 end
  elseif a == 2 then
    cs.pre = cs.pre - 1
    if cs.pre < 0 then cs.pre, cs.action = 0, 0 end
  end
  if cs.action == 4 then M.cloneTile(f, p) end
  -- the clones
  local alive = {}
  local ended = false
  for _, c in ipairs(clones(f) or {}) do
    if not c.deleted and cloneUpdate(f, p, c, cs) then alive[#alive + 1] = c else ended = true end
  end
  if ended and #(clones(f) or {}) > 0 then M.deleteClones(f, true)
  elseif clones(f) then f.playerClones = alive end
  if cs.action == 5 then cloneSwords(f, p) end
  return nil
end

-- the clones drawn with Link's frame (sub_08084B1C copies it)
function M.draw(p, x, y)
  local f = p.field
  if not f or not clones(f) then return nil end
  local A = f.assets
  for _, c in ipairs(clones(f)) do
    if c.draw and not c.deleted then
      local spr = c.action == 2 and c.sprite or p:sprite()
      local fr = c.action == 2 and c.frame or p.anim.frame
      if fr and fr ~= 0xFF then
        local img, ox, oy = A:spriteFrame(spr, fr, A:objPalette(0x16), "link")
        if img then
          local cx, cy = x + (c.x - math.floor(p.x)), y + (c.y - math.floor(p.y))
          if c.action == 2 and c.flip then love.graphics.draw(img, cx - ox, cy + oy, 0, -1, 1) else love.graphics.draw(img, cx + ox, cy + oy) end
        end
      end
    end
  end
  return nil
end

return M
