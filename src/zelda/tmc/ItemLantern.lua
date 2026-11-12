-- Round 26A: the Lantern (ITEM_LANTERN_OFF $0F / ITEM_LANTERN_ON $10),
-- src/item/itemLantern.c, src/playerItem/playerItemLantern.c, the burn of
-- playerUtils.c sub_0807AB44 and object/flame.c types 1 and 2.
--
-- PORTED (decomp):
--   sub_08075A0C (A/B on ITEM_LANTERN_OFF): not while carrying, rolling,
--     jumping or Minish (it stays off); else ForceEquipItem(ITEM_LANTERN_ON)
--     on that button and ANIM_LANTERN_LIGHT ($600 + facing,
--     gItemDefinitions).
--   sub_08075ADC: once Link's frame flag bit 1 clears (or items are
--     disabled) the lantern is lit: PL_USE_LANTERN (p.lanternLit, read by
--     EnemyField1's / EnemyDHC's sub_0806FD54), SFX_ITEM_LANTERN_ON.
--   sub_08075B54 (lit): the button again, the lantern no longer on a button
--     or a jump -> ITEM_LANTERN_OFF, SFX_ITEM_LANTERN_OFF.  Else, not
--     rolling, the tile ahead (gUnk_08126EEC: north (0,-13), east (13,0),
--     south (0,16), west (-13,0)) with tile-type flag $40 (sub_080B1BA4,
--     ExtractR23.flags) -> ANIM_LANTERN_BURN ($60C + facing).
--   sub_08075C9C: frame flag $10 -> sub_0807AB44 at the tile ahead; flag $80
--     -> lit again.
--   sub_0807AB44: the tile-interaction entry with filter $0B
--     (sub_0806FC50); its new tile $76 (TILE_TYPE_118, a lit torch) ->
--     FLAME type 1 (40 frames, 8 px up) and the torch tile set at once;
--     else FLAME type 2 at the tile (SPECIAL_TILE_79 now; 15 frames later
--     the entry's tile, and the fire spreads with sub_0807AB44 at the four
--     neighbours).  FLAME plays SFX_124.
--   PlayerItemLantern: drawn while Link's sprite is 6 and frameIndex < $37:
--     sprite 18 (gPlayerItemDefinitions, palette 0) showing Link's
--     frameIndex with his flip; its 4 x 4 hitbox at offsets {6,-6} {7,-3}
--     {-5,2} {-7,-3} by facing is kept as a hidden entity with
--     lanternFlame / hurtType 7 (BossOctorok reads it).
--   ResetLantern (Swim.resetLantern) on entering water.
-- SIMPLIFIED: LAMP_PARTICLE (the flicker) is not ported; "Link's sprite is
--   6" for the burn check is "lit and in the normal state" (Link's lantern
--   walk needs Player:animFor to pick ANIM_LANTERN $608 / ANIM_LANTERN_ON
--   $604 -- see ItemLantern.walkAnims); sub_0807B7D8's TILE_TYPE_53 clone
--   case is not ported; frame flags come from Link's keyframes (byte 4),
--   with a fallback timeline when the sprite has no animation data.
local bit = require("bit")
local band = bit.band

local L = {}

L.OFF, L.ON = 0x0F, 0x10
L.ANIM = { light = 0x600, on = 0x604, walk = 0x608, burn = 0x60C }
L.SFX = { ON = 0x13D, OFF = 0x13E, FLAME = 0x124 }
L.PROBE = { [0] = { 0, -13 }, [2] = { 13, 0 }, [4] = { 0, 16 }, [6] = { -13, 0 } } -- gUnk_08126EEC
L.HIT = { [0] = { 6, -6 }, [2] = { 7, -3 }, [4] = { -5, 2 }, [6] = { -7, -3 } }    -- PlayerItemLantern offsets
L.TT_TORCH_ON = 0x76
L.SPECIAL_79 = 0x4000 + 79
L.SPRITE = 18
local FLAME = 0x2A

local FALLBACK = { light = { [1] = 1, [10] = 0 }, burn = { [6] = 0x10, [12] = 0x80 } }

local function setAnim(p, l, kind)
  p:setAnim(L.ANIM[kind], true)
  l.kind, l.fresh, l.ft, l.cur = kind, true, 0, 0
end

local function step(p, l)
  local a = p.anim
  if a.keys then
    if l.fresh then l.fresh = false; l.key = a.key; l.cur = a.flags or 0; return l.cur, l.cur end
    a:update(1)
    if a.key ~= l.key then l.key = a.key; l.cur = a.flags or 0; return l.cur, l.cur end
    return 0, l.cur
  end
  l.fresh = false
  l.ft = l.ft + 1
  local e = (FALLBACK[l.kind] or {})[l.ft]
  if e then l.cur = e; return e, e end
  return 0, l.cur
end

-- Player:animFor hook: the lit lantern's walk / stand animations
-- (sub_080797EC ANIM_LANTERN, sub_080790E4 ANIM_LANTERN_ON)
function L.walkAnims(p)
  if p.lanternLit and not p.minish then return L.ANIM.walk, L.ANIM.on end
  return nil
end

local function equipSlot(f, item)
  local eq = f.save and f.save.equip
  if not eq then return nil end
  if eq.a == item then return "a" end
  if eq.b == item then return "b" end
  return nil
end

local function back(p)
  if p.state == "ext" and p.extUpdate == L.update then p.state, p.extUpdate = "normal", nil end
  p.animId = -1
end

function L.off(p, quiet)
  local f = p.field
  local slot = equipSlot(f, L.ON)
  if slot then f.save.equip[slot] = L.OFF end
  p.lanternLit, p.lantern = nil, nil
  if p.lanternEnt then p.lanternEnt.deleted = true; p.lanternEnt = nil end
  back(p)
  if not quiet then f:sound(L.SFX.OFF) end
end

local function tileAhead(p, off)
  local o = off or L.PROBE[band(p.animationState or 4, 6)]
  return math.floor((p.x + o[1]) / 16), math.floor((p.y + o[2]) / 16)
end

-- sub_0806FC50(tileType, filter): the tile-interaction entry
local function entryFor(f, tt, filter)
  local acts = f.assets.manifest and f.assets.manifest.tileActs
  if not (tt and acts) then return nil end
  local idx = acts.map[tt]
  local e = idx and idx ~= 0 and acts.entries[idx]
  if not e or band(bit.rshift(e.mask, filter), 1) == 0 then return nil end
  return e
end

local function inRoom(r, tx, ty) return tx >= 0 and ty >= 0 and tx < r.tw and ty < r.th end

local function flame(f, x, y, layer, form, timer, onEnd)
  local e = { kind = 6, id = FLAME, form = form, x = x, y = y, z = 0, layer = layer, timer = timer,
              animationState = 0, field80 = 0, field82 = 0, interactType = 0, flame = true }
  local O = f:objects()
  local def = O and O.def and O:def(FLAME, form)
  if def then O:dress(e, def, 0) end
  e.extUpdate = function(_, me)
    if me.anim and me.anim.update then me.anim:update(1) end
    me.timer = me.timer - 1
    if me.timer < 0 then
      me.deleted = true
      if onEnd then onEnd(me) end
    end
  end
  f.entities[#f.entities + 1] = e
  if f._dungeon and f._dungeon.track then f._dungeon:track(e) end
  f:sound(L.SFX.FLAME)
  return e
end

-- sub_0807AB44: burn the tile at (x + ox, y + oy)
function L.burn(f, x, y, layer, ox, oy)
  local r = f.room
  local tx, ty = math.floor((x + ox) / 16), math.floor((y + oy) / 16)
  if not inRoom(r, tx, ty) then return nil end
  local tt = r:tileType(layer == 2 and 2 or 1, tx, ty)
  local e = entryFor(f, tt, 0x0B)
  if not e then return nil end
  if e.tile == L.TT_TORCH_ON then
    flame(f, tx * 16 + 8, ty * 16 + 8 - 8, layer, 1, 40)
    f:objects():setTileType(layer == 2 and 2 or 1, tx, ty, e.tile) -- sub_0807B7D8
  else
    r:setTile(layer == 2 and 2 or 1, tx, ty, L.SPECIAL_79)
    flame(f, tx * 16 + 8, ty * 16 + 8, layer, 2, 15, function(me)
      if band(e.tile, 0x4000) ~= 0 then r:setTile(layer == 2 and 2 or 1, tx, ty, e.tile)
      else f:objects():setTileType(layer == 2 and 2 or 1, tx, ty, e.tile) end
      for _, o in ipairs({ { 0, 16 }, { 0, -16 }, { 16, 0 }, { -16, 0 } }) do L.burn(f, me.x, me.y, layer, o[1], o[2]) end
    end)
  end
  return e
end

-- the A / B press
function L.use(p, item, button, input)
  if item ~= L.OFF and item ~= L.ON then return nil end
  local f = p.field
  if item == L.ON or p.lanternLit then L.off(p) return true end
  if p.carried or p.state == "roll" or (p.z or 0) > 0 or p.jumping or p.minish then
    local slot = button or equipSlot(f, L.OFF)
    if f.save and f.save.equip and slot then f.save.equip[slot] = L.OFF end
    return true
  end
  if f.save and f.save.equip then f.save.equip[button or "b"] = L.ON end
  local l = { st = 1, button = button }
  p.lantern = l
  p.state, p.extUpdate = "ext", L.update
  p.moving = false
  setAnim(p, l, "light")
  return true
end

function L.update(p, input)
  local f = p.field
  local l = p.lantern
  if not l then back(p) return end
  if l.st == 1 then
    -- sub_08075ADC: the flag is read before the animation steps
    local cur = l.fresh and (p.anim.keys and (p.anim.flags or 0) or 1) or l.cur
    if band(cur, 1) == 0 then
      l.st = 2
      p.lanternLit = true
      f:sound(L.SFX.ON)
      back(p)
      return
    end
    step(p, l)
  elseif l.st == 3 then
    local edge = step(p, l)
    if band(edge, 0x10) ~= 0 then L.burn(f, p.x, p.y, p.layer, unpack(L.PROBE[band(p.animationState or 4, 6)])) end
    if band(edge, 0x80) ~= 0 then l.st = 2; back(p) end
  else
    back(p)
  end
end

local function hitEnt(p)
  local f = p.field
  local e = p.lanternEnt
  if not e or e.deleted or e.room ~= f.room then
    e = { kind = 8, id = 6, lanternFlame = true, fire = true, hitW = 4, hitH = 4, -- fire = contact $87 for ToDObjects.fireContact (round 26A wiring)
          hurtType = 7, hidden = true, noTouch = true, x = p.x, y = p.y,
          z = 0, room = f.room, hitW = nil, field82 = 0, interactType = 0 }
    f.entities[#f.entities + 1] = e
    p.lanternEnt = e
  end
  local o = L.HIT[band(p.animationState or 4, 6)]
  e.x, e.y, e.layer, e.w, e.h = p.x + o[1], p.y + o[2], p.layer, 4, 4
end

-- every frame (top of Player:update)
function L.frame(p, input)
  p.usingLantern = p.lanternLit and true or nil -- round 26A wiring: ToDObjects.lanternOn (the dark rooms' light circle)
  local l = p.lantern
  if not p.lanternLit or not l then return nil end
  local f = p.field
  if l.st == 2 then
    if not equipSlot(f, L.ON) or (p.z or 0) > 0 or p.jumping or p.minish then L.off(p) return nil end
    hitEnt(p)
    if p.state == "normal" and not p.carried then
      local tx, ty = tileAhead(p)
      local r = f.room
      if inRoom(r, tx, ty) then
        local tt = r:tileType(p.layer == 2 and 2 or 1, tx, ty)
        local fl = require("src.zelda.tmc.ExtractR23").flags(f.assets.manifest, tt)
        if band(fl, 0x40) ~= 0 then
          l.st = 3
          p.state, p.extUpdate = "ext", L.update
          setAnim(p, l, "burn")
          return true -- round 26A wiring fix: consume the frame (Player:update read its state before this hook, its normal walk would replace ANIM_LANTERN_BURN)
        end
      end
    end
  elseif l.st == 3 then
    hitEnt(p)
  end
  return nil
end

-- PlayerItemLantern: sprite 18 over Link while he shows sprite 6
function L.draw(p, x, y)
  if not p.lanternLit or p:sprite() ~= 6 then return nil end
  local fr = p.anim.frame
  if not fr or fr >= 0x37 then return nil end
  local A = p.field.assets
  local img, ox, oy = A:spriteFrame(L.SPRITE, fr, A:objPalette(0), "lantern")
  if not img then return nil end
  if p:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
  return nil
end

return L
