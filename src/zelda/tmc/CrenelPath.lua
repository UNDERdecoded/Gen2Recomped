-- Round 8: the Mt. Crenel path pieces.
--
-- BOTTLES (item/itemJarEmpty.c, playerItem/playerItemBottle.c,
--   object/linkEmptyingBottle.c): gSave.stats.bottles[4] (save.bottles[1..4]),
--   ITEM_BOTTLE1..4 ($1C-$1F) on a button.
--   - empty: ANIM_BOTTLE_SWING, then ANIM_BOTTLE_SWING_END on the frame's
--     bit $80; the swing catches what its box touches: MINERAL_WATER_SOURCE
--     (hurtType $4D) -> ITEM_BOTTLE_MINERAL_WATER, a fairy ($49), or water
--     (ACT_TILE_16 at gUnk_080B7878's point for the frame) -> ITEM_BOTTLE_WATER;
--     a catch is the item get of the new contents (sub_0801B9F0).
--   - water / mineral water: ANIM_BOTTLE_POUR; on Link's frame 1 the bottle
--     empties and LINK_EMPTYING_BOTTLE lands at gUnk_08122A18[facing] from
--     him: water turns SPECIAL_TILE_50 -> 51, mineral water SPECIAL_TILE_59
--     -> 60 (and 97 -> 34) on its tile and the four 8 px around it
--     (sub_08094980); FX_WATER_SPLASH / FX_GREEN_SPLASH2.
-- MINERAL_WATER_SOURCE ($6E, mineralWaterSource.c): an invisible box
--   $30 x $20 (half sizes) that bottles catch from.
-- CRENEL_BEAN_SPROUT ($6B, crenelBeanSprout.c):
--   type 3  the bean in the Minish path: Minish Link lifts it (R) and carries
--           it (WATERBEAN_OUT); its sprout (type 1) sits on it.
--   type 0  outside: while WATERBEAN_OUT and not WATERBEAN_PUT it is the bean
--           in Link's hands; R throws it when the tile ahead is ACT_TILE_25
--           (zVelocity 2.0, speed $100, SFX_PLY_VO5); landing in the hole:
--           WATERBEAN_PUT, animation 8, then 10 and SPECIAL_TILE_59 on its
--           tile.  Planted and its local flag (type2) clear: it waits.
--   type 2  planted from the start (SPECIAL_TILE_50), waits for plain water.
--   Action4: while its tile is SPECIAL_TILE_60 (type 0) / 51 (type 2) the
--   timer runs 192 frames (Link held still), then Action6: SetLocalFlag
--   (type2), the base tile ($1CE / $1CD) and every 15 frames one vine tile
--   up ($1CC, $1CB, $1C9) -- two for type 0, three for type 2 -- then
--   SFX_SECRET after 60 frames.  Grown (flag set): the vine tiles are put
--   back on load (sub_080969A4).  The vine's tiles are ladders (Climb.lua).
local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift
local Anim = require("src.zelda.tmc.Anim")

local CP = {}

local ITEM_BOTTLE1, ITEM_BOTTLE4 = 0x1C, 0x1F
local B_EMPTY, B_WATER, B_MINERAL, B_FAIRY = 0x20, 0x26, 0x27, 0x28
local ANIM_POUR, ANIM_SWING, ANIM_SWING_END = 0x610, 0x614, 0x618
local SP = function(n) return 0x4000 + n end
local WATERBEAN_OUT, WATERBEAN_PUT = 0x1A, 0x1B
local ACT_HOLE, ACT_WATER = 0x19, 0x10
local SFX_BOTTLE, SFX_1DB, SFX_SECRET, SFX_VO5 = 0x1DC, 0x1DB, 0x72, 0x79
local FX_WATER_SPLASH, FX_GREEN_SPLASH2, FX_DEATH = 0x0B, 0x2B, 0x02
local OBJ_SPROUT, OBJ_WATER_SOURCE = 0x6B, 0x6E

-- ---------------------------------------------------------------------------
-- bottles
-- ---------------------------------------------------------------------------
function CP.bottles(f)
  f.save.bottles = f.save.bottles or {}
  return f.save.bottles
end

-- Field:giveItem: a new bottle starts empty; contents fill the first empty
-- bottle (true = handled)
function CP.giveItem(f, item)
  local b = CP.bottles(f)
  -- the Fire Element: the Cave of Flames is cleared (LV2_CLEAR; where the
  -- cartridge sets it is not traced, simplified to the element get)
  if item == 0x41 then f:setFlag("global", 0x03, true) end
  if item >= ITEM_BOTTLE1 and item <= ITEM_BOTTLE4 then
    local i = item - ITEM_BOTTLE1 + 1
    if not b[i] then b[i] = B_EMPTY end
    return false
  elseif item >= B_EMPTY + 1 and item <= 0x31 then
    for i = 1, 4 do
      if (f.save.items[ITEM_BOTTLE1 + i - 1] or 0) > 0 and b[i] == B_EMPTY then b[i] = item return true end
    end
    return true
  end
  return false
end

local function act(f, x, y, layer)
  local r = f.room
  local t = r:tileType(layer or 1, math.floor(x / 16), math.floor(y / 16))
  if not t or t >= 0x4000 then return nil, t end
  return f.assets.actTile[t], t
end
CP.act = act

local function tileAt(f, x, y, layer)
  return f.room:tileType(layer or 1, math.floor(x / 16), math.floor(y / 16))
end

-- sub_08094980: replace `from` by `to` at the point and the four 8 px around it
local AROUND = { { 0, 0 }, { -8, 0 }, { 8, 0 }, { 0, 8 }, { 0, -8 } }
function CP.replaceAround(f, x, y, layer, from, to)
  for _, o in ipairs(AROUND) do
    local px, py = x + o[1], y + o[2]
    if tileAt(f, px, py, layer) == from then
      f.room:setTile(layer or 1, math.floor(px / 16), math.floor(py / 16), to)
    end
  end
end

-- gUnk_08122A18: where the poured water lands, by facing
local POUR_AT = { [0] = { 0, -8 }, { 8, 1 }, { 2, 8 }, { -8, 1 } }

local function pourLand(f, p, contents)
  local o = POUR_AT[math.floor(p.animationState / 2)]
  local x, y = p.x + o[1], p.y + o[2]
  local layer = p.layer == 2 and 2 or 1
  if contents == B_MINERAL then
    f:addFx(x, y, 0x0F, FX_GREEN_SPLASH2)
    CP.replaceAround(f, x, y, layer, SP(59), SP(60))
  else
    f:addFx(x, y, 0x0F, FX_WATER_SPLASH)
    CP.replaceAround(f, x, y, layer, SP(50), SP(51))
  end
  CP.replaceAround(f, x, y, layer, SP(97), SP(34))
end

-- gUnk_080B7878: the swing's water probe for the frame byte's low nibble
local SWING_PROBE = { { 0, -16 }, { 16, -16 }, { 16, 0 }, { 16, 16 }, { 0, 16 }, { -16, 16 }, { -16, 0 }, { -16, -16 }, { 0, 0 } }

local function catchSource(f, p)
  local fx, fy = p:frontPoint(10)
  for _, e in ipairs(f.entities) do
    if e.waterSource and not e.deleted and math.abs(e.x - fx) < 0x30 + 5 and math.abs(e.y - fy) < 0x20 + 5 then return B_MINERAL end
    if e.id == 0x40 and e.kind == 6 and not e.deleted and math.abs(e.x - fx) < 10 and math.abs(e.y - fy) < 10 then
      e.deleted = true
      return B_FAIRY
    end
  end
  return nil
end

local function finish(p)
  p.state = "normal"
  p.extUpdate = nil
  p.animId = -1
end

function CP.useBottle(p, item, button)
  if item < ITEM_BOTTLE1 or item > ITEM_BOTTLE4 or p.state ~= "normal" then return false end
  local f = p.field
  local b = CP.bottles(f)
  local i = item - ITEM_BOTTLE1 + 1
  local contents = b[i] or B_EMPTY
  p.state = "ext"
  p.moving = false
  if contents == B_EMPTY then
    p:setAnim(ANIM_SWING, true)
    f:sound(SFX_BOTTLE)
    local caught, ending = nil, false
    p.extUpdate = function(pl)
      pl.anim:update(1)
      local fl = pl.anim.flags or 0
      if not caught and not ending then
        caught = catchSource(f, pl)
        if not caught and band(fl, 0xF) ~= 0 then
          local o = SWING_PROBE[band(fl, 0xF)]
          if o and act(f, pl.x + (pl.anim:hflip() and -o[1] or o[1]), pl.y + o[2], pl.layer) == ACT_WATER then caught = B_WATER end
        end
        if caught then
          -- sub_0801B9F0: the new contents' item get
          b[i] = B_EMPTY
          finish(pl)
          f:giveItem(caught)
          return
        end
      end
      if band(fl, 0x80) ~= 0 or pl.anim.done then
        if ending then return finish(pl) end
        ending = true
        pl:setAnim(ANIM_SWING_END, true)
      end
    end
    return true
  end
  if contents == B_WATER or contents == B_MINERAL then
    p:setAnim(ANIM_POUR, true)
    local poured = 0
    p.extUpdate = function(pl)
      pl.anim:update(1)
      -- PlayerItemBottle_UseOther: Link's frame byte 1 empties it and the
      -- water lands (2 and 3 only add splashes)
      local fl = pl.anim.flags or 0
      if poured == 0 and fl == 1 then poured = 1; b[i] = B_EMPTY; pourLand(f, pl, contents) end
      if band(pl.anim.flags or 0, 0x80) ~= 0 or pl.anim.done then
        if poured == 0 then b[i] = B_EMPTY; pourLand(f, pl, contents) end
        finish(pl)
      end
    end
    return true
  end
  if contents == B_FAIRY then
    -- round 22: PlayerItemBottle_UseOther: on Link's frame byte 1 the bottle
    -- empties, LINK_EMPTYING_BOTTLE type 2 (the fairy flies off) and
    -- ModHealth($20)
    p:setAnim(ANIM_POUR, true)
    local used = false
    p.extUpdate = function(pl)
      pl.anim:update(1)
      local fl = pl.anim.flags or 0
      if not used and (fl == 1 or band(fl, 0x80) ~= 0 or pl.anim.done) then
        used = true; b[i] = B_EMPTY; f:modStat("health", 0x20)
      end
      if band(fl, 0x80) ~= 0 or pl.anim.done then finish(pl) end
    end
    return true
  end
  p.state = "normal"
  return false
end

-- round 22: player.c sub_08071D04 -- when the death animation is over, a
-- bottled fairy (GetBottleContaining(ITEM_BOTTLE_FAIRY)) is let out: the
-- bottle becomes empty ($20), CreateObject(FAIRY, $60, 2), ModHealth(32),
-- killed cleared, a hop (zVelocity 1.5); iframes 226 after landing.
-- SIMPLIFIED: no hop and no FAIRY object; 120 frames of iframes
function CP.fairyRevive(p)
  local f = p.field
  local b = CP.bottles(f)
  for i = 1, 4 do
    if b[i] == B_FAIRY and (f.save.items[ITEM_BOTTLE1 + i - 1] or 0) > 0 then
      b[i] = B_EMPTY
      f:modStat("health", 32)
      p.state = "normal"
      p.timer = 0
      p.invuln = 120
      p:setAnim(p:animFor("idle"), true)
      f:sound(0x109)
      return true
    end
  end
  return false
end
CP.B_FAIRY = B_FAIRY

-- ---------------------------------------------------------------------------
-- MINERAL_WATER_SOURCE
-- ---------------------------------------------------------------------------
local function spawnWaterSource(dungeon, e)
  e.waterSource = true
  e.hidden = true
  e.hurtType = 0x4D
  dungeon:track(e)
  return e
end

-- ---------------------------------------------------------------------------
-- CRENEL_BEAN_SPROUT
-- ---------------------------------------------------------------------------
local function sproutAnim(f, e, idx)
  e.objAnim, e.animIndex = idx, idx
  e.anim = e.anim or Anim.new()
  e.anim:set(f.assets:sprite(e.sprite), idx, true)
end

local GROW = { 0x1CC, 0x1CB, 0x1C9 }
local function growTiles(f, e, n)
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  local layer = e.layer or 1
  local O = f:objects()
  O:setTileType(layer, tx, ty, e.form == 0 and 0x1CE or 0x1CD)
  for k = 1, n do O:setTileType(layer, tx, ty - k, GROW[k]) end
end

function CP.spawnSprout(dungeon, e)
  local f = dungeon.field
  local def = f:objects():def(OBJ_SPROUT, e.form or 0)
  if def then f:objects():dress(e, def, 0) end
  e.literalAnim = true
  e.sprout = true
  e.timer = 192
  local ty = e.form or 0
  e.localFlag = e.type2
  if ty == 0 then
    if f:flag("global", WATERBEAN_OUT) and not f:flag("global", WATERBEAN_PUT) then
      e.action = 1 -- in Link's hands
      e.held = true
      sproutAnim(f, e, 3)
    elseif f:flag("global", WATERBEAN_OUT) or f:flag("global", WATERBEAN_PUT) then
      if not f:flag("local", e.localFlag) then
        sproutAnim(f, e, 10)
        e.y = e.y + 4
        e.action = 4
        f.room:setTile(e.layer or 1, math.floor(e.x / 16), math.floor(e.y / 16), SP(59))
      else
        growTiles(f, e, 2)
        return nil
      end
    else
      -- not brought out yet: it shows as the empty spot at origin + ($D0, $44)
      e.x, e.y = 0xD0, 0x44
      e.action = 4
      e.hidden = true
      sproutAnim(f, e, 3)
    end
  elseif ty == 3 then
    if f:flag("global", WATERBEAN_OUT) then return nil end
    e.action = 1
    e.carryable = true
    sproutAnim(f, e, 0xC)
  elseif ty == 2 then
    if not f:flag("local", e.localFlag) then
      sproutAnim(f, e, 0xB)
      e.y = e.y + 4
      e.action = 4
      f.room:setTile(e.layer or 1, math.floor(e.x / 16), math.floor(e.y / 16), SP(50))
    else
      growTiles(f, e, 3)
      return nil
    end
  else
    sproutAnim(f, e, ty + 3)
    e.action = 1
  end
  e.extUpdate = function(_, me, input) CP.updateSprout(f, me, input) end
  dungeon:track(e)
  return e
end

-- Link carries the bean (type 3 lifted in the Minish path, or type 0 outside)
local function carryUpdate(f, p, e, input)
  local dx, dy = 0, 0
  local locked = not p.control or f:inputLocked()
  if not locked then
    if input.down("left") then dx = dx - 1 end
    if input.down("right") then dx = dx + 1 end
    if input.down("up") then dy = dy - 1 end
    if input.down("down") then dy = dy + 1 end
  end
  local walk, idle = p:animFor("walk"), p:animFor("idle")
  if p:walk(dx, dy, require("src.zelda.tmc.Player").WALK_SPEED, walk, idle) then p.anim:update(1) end
  e.x, e.y = p.x, p.y + 1
  e.z = p.minish and 10 or 16
  -- the throw target: the tile ahead (gUnk_08123184), only into a hole
  local s = math.floor(p.animationState / 2)
  local off = ({ [0] = { 0, -16 }, { 16, 0 }, { 0, 16 }, { -16, 0 } })[s]
  local tx = bor(band(math.floor(e.x + off[1]), bit.bnot(15)), 8)
  local ty2 = bor(band(math.floor(e.y + off[2]), bit.bnot(15)), 8)
  e.targetX, e.targetY = tx, ty2
  local canThrow = act(f, tx, ty2, e.layer) == ACT_HOLE
  f.rActionOverride = canThrow and "throw" or nil
  if not locked and input.pressed("r") and canThrow and e.form == 0 then
    p.state, p.extUpdate, p.animId = "normal", nil, -1
    f.rActionOverride = nil
    e.held = nil
    e.action = 5
    e.zv = 2
    f:sound(SFX_VO5)
    return
  end
end

function CP.liftBean(f, p)
  -- R in front of the type-3 bean (Minish Link): Action2 SubAction0 sets
  -- WATERBEAN_OUT
  local fx, fy = p:frontPoint(8)
  for _, e in ipairs(f.entities) do
    if e.sprout and e.carryable and not e.deleted and math.abs(e.x - fx) < 12 and math.abs(e.y - fy) < 12 then
      e.carryable = nil
      e.held = true
      f:setFlag("global", WATERBEAN_OUT, true)
      f:sound(0x7E)
      p.state = "ext"
      p.extUpdate = function(pl, input) carryUpdate(f, pl, e, input) end
      f.heldBean = e
      return true
    end
  end
  return false
end

function CP.updateSprout(f, e, input)
  local p = f.player
  if e.held then
    -- round 20: a hit (Player:hurt) or a death runs its own state; the bean
    -- stays over Link's head meanwhile (the carry used to overwrite "dead":
    -- Link went on at 0 hearts)
    if p.state == "hurt" or p.state == "dead" then
      e.x, e.y = p.x, p.y + 1
      e.anim:update(0)
      return
    end
    if p.state ~= "ext" or p.extUpdate == nil then
      p.state = "ext"
      p.extUpdate = function(pl, inp) carryUpdate(f, pl, e, inp) end
    end
    e.anim:update(p.moving and 1 or 0)
    return
  end
  if e.action == 5 then
    -- Action5: to the target tile, then the drop
    local dx, dy = (e.targetX or e.x) - e.x, (e.targetY or e.y) - e.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 1 then e.x, e.y = e.x + dx / d, e.y + dy / d else e.x, e.y = e.targetX or e.x, e.targetY or e.y end
    e.z = e.z + e.zv
    e.zv = e.zv - 0.25
    if e.z <= 0 then
      e.z = 0
      -- sub_08096A78
      f:setFlag("global", WATERBEAN_PUT, true)
      sproutAnim(f, e, bit.rshift(e.form, 1) + 8)
      e.x, e.y = math.floor(e.x / 16) * 16 + 8, math.floor(e.y / 16) * 16 + 8 + 4
      e.action = 3
      f.room:setTile(e.layer or 1, math.floor(e.x / 16), math.floor(e.y / 16), SP(59))
    end
    return
  end
  if e.action == 3 then
    e.anim:update(1)
    if e.anim.done then e.action = 4; sproutAnim(f, e, 10) end
    return
  end
  if e.action == 4 then
    local want = (e.form or 0) >= 2 and SP(51) or SP(60)
    if tileAt(f, e.x, e.y, e.layer) == want then
      e.anim:update(1)
      p.keepStill = true
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.action, e.subAction = 6, 0
        f:addFx(e.x, e.y, 0x0F, FX_DEATH)
      end
    else
      e.timer = 192
    end
    return
  end
  if e.action == 6 then
    p.keepStill = nil
    if e.subAction == 0 then
      f:setFlag("local", e.localFlag, true)
      e.timer, e.subtimer, e.grown = 15, (e.form or 0) >= 2 and 3 or 2, 0
      e.hidden = true
      e.subAction = 1
      f:objects():setTileType(e.layer or 1, math.floor(e.x / 16), math.floor(e.y / 16), e.form == 0 and 0x1CE or 0x1CD)
      f:sound(SFX_1DB)
      if p.state == "normal" then p.state, p.extUpdate = "ext", function() end end -- PausePlayer
    elseif e.subAction == 1 then
      e.timer = e.timer - 1
      if e.timer == 0 then
        e.grown = e.grown + 1
        f:objects():setTileType(e.layer or 1, math.floor(e.x / 16), math.floor(e.y / 16) - e.grown, GROW[e.grown])
        if e.grown == e.subtimer then e.subAction, e.timer = 2, 60 else e.timer = 15 end
      end
    elseif e.subAction == 2 then
      if e.timer > 0 then
        e.timer = e.timer - 1
        if e.timer == 0 then
          f:sound(SFX_SECRET)
          if p.state == "ext" and not p.climbing then p.state, p.extUpdate, p.animId = "normal", nil, -1 end
          e.deleted = true
        end
      end
    end
    return
  end
  e.anim:update(1)
end

-- ---------------------------------------------------------------------------
-- Melari's Mines: the scene's natives (npc/mountainMinish.c, melari.c,
-- townMinish.c, drLeft.c, kid.c, cutsceneMiscObject.c, script.c) and
-- ShowNPCDialogue (npcUtils.c).  Tables read from the ROM (npcData).
-- ---------------------------------------------------------------------------
local Native = require("src.zelda.tmc.Native")
local N = Native.N
local A_LOOK, A_MSG, A_KID_DIALOG = 0x08111284, 0x0811130E, 0x0810BE10
local OYAKATA_DEMO, ITEM_FIRE_ELEMENT, ITEM_GREEN_SWORD, ITEM_QST_BROKEN_SWORD = 0x7E, 0x41, 0x02, 0x35

local function npcT(f) return require("src.zelda.tmc.Ppu").table({ A = f.assets }, "npcData") end

-- GetFacingDirection (0..31, 0 = north, clockwise)
local function dir32(e, p)
  local a = math.atan2(p.x - e.x, -(p.y - e.y))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
local function inRect(e, p, rx, ry) return math.abs(p.x - e.x) < rx and math.abs(p.y - e.y) < ry end

-- ShowNPCDialogue(ent, dialog at addr)
function CP.showDialogue(f, e, t, addr)
  local w = t.u32(addr)
  local flag, ftype, dtype = band(w, 0xFFF), band(rshift(w, 12), 0xF), band(rshift(w, 16), 0xF)
  local ia, ib = t.u16(addr + 4), t.u16(addr + 6)
  local function check()
    if ftype == 0 then return f:flag("room", flag)
    elseif ftype == 1 then return f:flag("local", flag)
    elseif ftype == 2 then return f:flag("global", flag)
    elseif ftype == 3 then return f:kinstoneFused(flag)
    elseif ftype == 4 then return (f:inventory(flag) or 0) ~= 0 end
    return false
  end
  local function set(v)
    local kind = ftype == 0 and "room" or ftype == 1 and "local" or "global"
    f:setFlag(kind, flag, v)
  end
  local text = 0
  if dtype == 2 then local was = check(); set(true); text = was and ia or ib
  elseif dtype == 3 then local was = check(); set(not was); text = was and ia or ib
  elseif dtype == 4 then text = check() and ia or ib
  elseif dtype == 1 then text = ib
  elseif dtype == 6 then text = f.player.minish and ib or ia end
  if text ~= 0 then f:message(text, e) end
end

N[0x08068104] = function(f, e) e.talkable = true end            -- MountainMinish_MakeInteractable
N[0x0806811C] = function(f, e)                                    -- the mountain Minish turns to Link
  if (e.lookTimer or 0) > 0 then e.lookTimer = e.lookTimer - 1 return end
  e.lookTimer = 2
  local p = f.player
  local d = inRect(e, p, 0x20, 0x20) and dir32(e, p) or -1
  if d < 0 then e.animationState = e.form or 0; d = (e.form or 0) * 4 end
  local t = npcT(f)
  if not t then return end
  local a = A_LOOK + rshift(e.animationState or 0, 1) * 0x20 + rshift(d, 1) * 2
  local b2 = t.u8(a + 1)
  if band(b2, 0x80) ~= 0 then e.animationState = band(math.floor((d + 2) / 4), 7) end
  e.staticFrame = band(b2, 0x7F)
end
N[0x08068190] = function(f, e)                                    -- the mountain Minish's line by the story
  local t = npcT(f)
  if not t then return end
  local row = math.min(e.type2 or band(e.param or 0, 0xFF), 8)
  local col = 0
  if f:flag("local", OYAKATA_DEMO) then col = 1 end
  if (f:inventory(ITEM_FIRE_ELEMENT) or 0) ~= 0 then col = 2 end
  if (f:inventory(ITEM_GREEN_SWORD) or 0) ~= 0 then col = 3 end
  f:message(t.u16(A_MSG + row * 8 + col * 2), e)
end
N[0x080681D8] = function(f, e, ctx) e.form = ctx.intVariable end -- type = intVariable
local function animByState(f, e, ctx) e.staticFrame = nil; e.field80 = ctx.intVariable + rshift(e.animationState or 4, 1) end
N[0x0806AF60] = animByState                                      -- townMinish.c sub_0806AF60
N[0x0806C028] = animByState                                      -- drLeft.c sub_0806C028
N[0x08068910] = function(f, e)                                    -- Melari turns his head to Link
  if (e.headTimer or 0) > 0 then e.headTimer = e.headTimer - 1 return end
  e.headTimer = 16
  if band(e.anim and e.anim.flags or 0, 0x20) ~= 0 then
    local p = f.player
    local d = inRect(e, p, 0x30, 0x30) and dir32(e, p) or 0x10
    local st = band(math.floor((d + 4) / 8), 3)
    e.field80 = band(e.field80 or 0, bit.bnot(3)) + st
  end
end
N[0x08068964] = function(f)                                       -- Melari takes the broken sword
  f:giveItem(ITEM_QST_BROKEN_SWORD, 0, 3) -- round 22: melari.c InitItemGetSequence(.., 0, 3): held up, no sound / text
  f.save.items[ITEM_QST_BROKEN_SWORD] = 2
end
N[0x08095164] = function(f)                                       -- the broken sword object (type 8): animation 3
  for _, o in ipairs(f.entities) do
    if o.kind == 6 and o.id == 0x6A and o.form == 8 then o.objAnim = 3; o.field80 = 3 end
  end
end
N[0x0806265C] = function(f, e)                                    -- kid.c: the line for the story stage
  local prog = f.save.progress or 0
  if prog == 0 then f:message(0, e) return end
  local t = npcT(f)
  if not t then return end
  CP.showDialogue(f, e, t, A_KID_DIALOG + ((e.form or 0) * 9 - 1 + prog) * 8)
end
N[0x08062698] = function(f, e) e.speed = math.random(0, 0x3F) + 0xC0 end
N[0x080626AC] = function(f, e) e.timer = math.random(0, 0x1F) + 64 end
N[0x080626C0] = function(f, e, ctx)
  ctx.condition = 0
  if (e.timer or 0) ~= 0 then e.timer = e.timer - 1; if e.timer == 0 then ctx.condition = 1 end end
end

-- Crenel.spawnObject
function CP.spawnObject(dungeon, e)
  if e.id == OBJ_WATER_SOURCE then return spawnWaterSource(dungeon, e) end
  if e.id == OBJ_SPROUT then return CP.spawnSprout(dungeon, e) or false end
  return nil
end

return CP
