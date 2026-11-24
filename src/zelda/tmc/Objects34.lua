-- Round 34: objects the round 34 survey found drawn as nothing (or a fixed
-- frame) although their code is short.  In R34.MODULES (spawnObject); the
-- objects run from Dungeon:update (extUpdate).
--
-- CARTRIDGE BEHAVIOUR (src/object/*.c):
--   * GIANT_ROCK $50 (giantRock.c, $10:00): drawn, collision layer 2,
--     spritePriority 0, animation = type.
--   * GIANT_LEAF $3F (giantLeaf.c, $11:00): drawn, OAM priority 3,
--     spritePriority 7, frameIndex = type; sub_0808D618: tile 16500
--     (SPECIAL_TILE_116) on the bottom layer at its tile + 13 offsets
--     (gUnk_08121750 / gUnk_0812176A by type).
--   * BELL $77 (bell.c, Hyrule Town): drawn, layer 1, spritePriority 0,
--     animation 0 played every frame.
--   * HIDDEN_LADDER_DOWN $57 (hiddenLadderDown.c, $03:06, $07:00):
--     spritePriority 7; its flag set -> drawn and the 3 x 3 tile types
--     418..426 round its tile; else, when the tile under it becomes type
--     $1A6 (the Mole Mitts dug it) -> drawn, SetFlag.
--   * FIREPLACE $8D (fireplace.c, house fireplaces): flag set -> the cold
--     fireplace (sub_0809B7DC: tile type $30C on layer 2, SPECIAL_TILE_98)
--     and gone; else the fire (tile type $30B on layer 2, SPECIAL_TILE_97 on
--     its layer); every frame: the tile under it no longer 97 / 98 -> the
--     cold fireplace, SetFlag, gone.
--   * SMOKE $2D (smoke.c, $03:01): type 0 every 64 - (Random & $1F) frames
--     (40 the first time) makes a type 1 at x + gUnk_08121068[Random & 7];
--     type 1: speed $40, direction 6 (DirectionNorthEast | 2), OAM priority 1,
--     spritePriority 0, animation $28, gone at its end.
--   * STEAM $7A (steam.c, Mt. Crenel): drawn alpha-blended (BLDALPHA $60A
--     type 0, $808 type 1), layer 2 resolved; every 8 frames subtimer + 1;
--     spriteOffset x = gUnk_08123484[subtimer], y = the same + unk_68 (type
--     1: up to $40 while Link is past x $1F0, back to 0 else); no animation
--     (frameIndex stays 0).
-- SIMPLIFIED: STEAM's blend is love's alpha (EVA / 16); Random is love's.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}
M.GIANT_ROCK, M.GIANT_LEAF, M.BELL, M.HIDDEN_LADDER_DOWN, M.FIREPLACE, M.SMOKE, M.STEAM =
  0x50, 0x3F, 0x77, 0x57, 0x8D, 0x2D, 0x7A
local LEAF0 = require("src.zelda.tmc.RomTables").t("Objects34.LEAF0")  -- gUnk_08121750
local LEAF1 = require("src.zelda.tmc.RomTables").t("Objects34.LEAF1")  -- gUnk_0812176A
local SMOKE_DX = require("src.zelda.tmc.RomTables").t("Objects34.SMOKE_DX")                                             -- gUnk_08121068
local STEAM_OFF = require("src.zelda.tmc.RomTables").t("Objects34.STEAM_OFF")                -- gUnk_08123484 (s8)
M.LEAF0, M.LEAF1, M.STEAM_OFF = LEAF0, LEAF1, STEAM_OFF
local SP97, SP98, SP116 = 0x4061, 0x4062, 0x4074

local function rnd() return love and love.math and love.math.random(0, 0x7FFF) or math.random(0, 0x7FFF) end

local function dress(f, e, anim)
  local O = f:objects()
  local def = O and O:def(e.id, e.form or 0)
  if def then O:dress(e, def, anim or 0); e.objAnim = anim or 0 end
  return def ~= nil
end

local function setAnim(f, e, n)
  e.objAnim, e.animIndex = n, n
  if e.anim and e.sprite then e.anim:set(f.assets:sprite(e.sprite), n, true) end
end

-- a tile position (x + y * 64) plus an offset -> tx, ty
local function tilePos(e) return math.floor(e.x / 16), math.floor(e.y / 16) end
local function offset(tx, ty, off)
  local p = tx + ty * 64 + off
  return p % 64, math.floor(p / 64)
end
local function inRoom(r, x, y) return x >= 0 and y >= 0 and x < r.tw and y < r.th end

local function setType(f, layer, x, y, t)
  local r = f.room
  if inRoom(r, x, y) then f:objects():setTileType(layer, x, y, t) end
end
local function setTile(f, layer, x, y, t)
  local r = f.room
  if inRoom(r, x, y) then r:setTile(layer, x, y, t) end
end
local function tileType(f, layer, x, y)
  local r = f.room
  if not inRoom(r, x, y) then return nil end
  return (r:tileType(layer, x, y))
end

-- HIDDEN_LADDER_DOWN
local function ladderShow(f, d, e)
  e.hidden = false
  local tx, ty = tilePos(e)
  local L = e.layer or 1
  local t = 418
  for dy = -1, 1 do
    for dx = -1, 1 do setType(f, L, tx + dx, ty + dy, t); t = t + 1 end
  end
end

-- FIREPLACE sub_0809B7DC
local function fireOut(f, e)
  local tx, ty = tilePos(e)
  setType(f, 2, tx, ty, 0x30C)
  setTile(f, e.layer or 1, tx, ty, SP98)
  e.timer = 1
end
M.fireOut = fireOut

local function smokePuff(f, d, src)
  local s = { kind = 6, id = M.SMOKE, form = 1, x = src.x + SMOKE_DX[band(rnd(), 7)], y = src.y, z = 0,
              animationState = 0, field80 = 0, field82 = 0, interactType = 0, layer = 2 }
  if not dress(f, s, 0x28) then return end
  s.spritePriority, s.oamPrio = 0, 1
  s.extUpdate = function(_, me)
    me.anim:update(1)
    me.x, me.y = me.x + 0x40 / 256 * 0.9239, me.y - 0x40 / 256 * 0.3827 -- direction 6 (DirectionNorthEast | 2: 67.5 deg from north)
    if band(me.anim.flags or 0, 0x80) ~= 0 or me.anim.done then me.deleted = true end
  end
  f.entities[#f.entities + 1] = s
  d:track(s)
end

function M.spawnObject(d, e)
  local f = d.field
  local id = e.id
  if id == M.GIANT_ROCK then
    dress(f, e, e.form or 0)
    e.layer, e.spritePriority = 2, 0
    return e
  elseif id == M.GIANT_LEAF then
    dress(f, e, 0)
    e.staticFrame, e.oamPrio, e.spritePriority = e.form or 0, 3, 7
    local tx, ty = tilePos(e)
    for _, off in ipairs((e.form or 0) ~= 0 and LEAF1 or LEAF0) do
      local x, y = offset(tx, ty, off)
      setTile(f, 1, x, y, SP116)
    end
    return e
  elseif id == M.BELL then
    dress(f, e, 0)
    e.layer, e.spritePriority = 1, 0
    e.extUpdate = function(_, me) me.anim:update(1) end
    d:track(e)
    return e
  elseif id == M.HIDDEN_LADDER_DOWN then
    dress(f, e, 0)
    e.spritePriority = 7
    if d:check(e.flag) then ladderShow(f, d, e); return e end
    e.hidden = true
    e.extUpdate = function(dd, me)
      if not me.hidden then return end
      local tx, ty = tilePos(me)
      if tileType(f, me.layer or 1, tx, ty) == 0x1A6 then
        me.hidden = false
        dd:set(me.flag)
      end
    end
    d:track(e)
    return e
  elseif id == M.FIREPLACE then
    dress(f, e, 0)
    e.timer = 0
    if d:check(e.flag) then fireOut(f, e); e.deleted = true; e.hidden = true; return e end
    local tx, ty = tilePos(e)
    setType(f, 2, tx, ty, 0x30B)
    setTile(f, e.layer or 1, tx, ty, SP97)
    e.extUpdate = function(dd, me)
      local x, y = tilePos(me)
      local t = tileType(f, me.layer or 1, x, y)
      if t ~= SP97 and t ~= SP98 then fireOut(f, me) end
      if me.timer ~= 0 then dd:set(me.flag); me.deleted = true end
    end
    d:track(e)
    return e
  elseif id == M.SMOKE and (e.form or 0) == 0 then
    e.hidden, e.timer = true, 40
    e.extUpdate = function(dd, me)
      me.timer = me.timer - 1
      if me.timer <= 0 then
        me.timer = 64 - band(rnd(), 0x1F)
        smokePuff(f, dd, me)
      end
    end
    d:track(e)
    return e
  elseif id == M.STEAM then
    dress(f, e, 0)
    e.layer, e.staticFrame = 2, 0 -- (frameIndex 0: steam.c never animates)
    e.drawAlpha = band((e.form or 0) == 0 and 0x60A or 0x808, 0x1F) / 16
    e.timer, e.subtimer, e.rise = 1, band(rnd(), 0xF), 0
    e.extUpdate = function(_, me)
      if (me.form or 0) ~= 0 then
        if f.player.x > 0x1F0 then if me.rise < 0x40 then me.rise = me.rise + 1 end
        elseif me.rise > 0 then me.rise = me.rise - 1 end
      end
      me.timer = me.timer - 1
      if me.timer == 0 then me.timer = 8; me.subtimer = band(me.subtimer + 1, 0xF) end
      me.spriteOX = STEAM_OFF[me.subtimer]
      me.spriteOY = STEAM_OFF[me.subtimer] + me.rise
    end
    d:track(e)
    return e
  end
  return nil
end

return M
