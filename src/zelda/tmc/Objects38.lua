-- Round 38: TREE_HIDING_PORTAL ($9C, src/object/treeHidingPortal.c) -- the
-- trees that hide a Minish entrance (03:01 / 03:05 / 03:06 / 07:00 / 0B:00).
-- Listed in R37.MODULES (spawnObject).
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * Init: CheckFlags(flag at +$86, paramC's high half) set ->
--     CreateMinishEntrance and gone; else action 1, collision layer 2.
--   * Action1: Link within 48 px both ways (sub_0800419C, no layer test) and
--     global EZERO_1ST -> a sparkle (CreateSparkleFx: FX_SPARKLE4 at +-15 /
--     -15..4) every 4th frame; Link in PLAYER_BOUNCE with ACT_TILE_84 ($54,
--     the tree) at the tile in front (gUnk_080B4468 probe, bottom layer)
--     -> action 2, timer 15, SetPlayerControl(1).
--   * Action2: 15 frames -> action 3, timer 60, not drawn,
--     CreateMinishEntrance(COORD_TO_TILE_OFFSET(this, $20, 8)) (kinstone.c:
--     tile types $185.. as a 5 x 4 block on the bottom layer, row by row),
--     19 FX_BUSH at gUnk_08124364's offsets (to the -1000 end), layer 2.
--   * Action3: 60 frames -> SetFlag(flag), SetPlayerControl(0),
--     SFX_SECRET_BIG, gone.
-- MISC_MANAGER $0F types 0 / 9 / $C (src/manager/miscManager.c; x, y =
-- fields $38 / $3A in room coordinates, c0 / c1 = flag1 / flag2):
--   * Type0 ($48:01): room flag type2 -> each of (0x128, 0x68) (0x158, 0x68)
--     (0x128, 0x98) (0x158, 0x98) whose room flag type2 + 1..4 is clear and
--     whose bottom tile type is TILE_TYPE_97 becomes TILE_TYPE_38 (+ a
--     DIRT_PARTICLE); SFX_124; gone.
--   * Type9 ($05:02 / $05:05): flag2 already set -> SetDirtTile, gone;
--     later flag2 -> SetDirtTile + FX_BIG_EXPLOSION2 + SFX_16E, gone.
--     SetDirtTile: TILE_TYPE_29 bottom, TILE_TYPE_0 top here and above.
--   * TypeC ($68:01): flag2 -> gone; flag1 -> FX_BIG_EXPLOSION (layer 2)
--     at x, y, SFX_1B0, gone.
-- SIMPLIFIED: Type0's DIRT_PARTICLE object is not created.
local RT = require("src.zelda.tmc.RomTables")

local M = {}
M.TREE_HIDING_PORTAL = 0x9C
M.EZERO_1ST, M.ACT_TILE_84, M.ENTRANCE_TILE = 0x14, 0x54, 0x185
local SPECIAL_FX, FX_BUSH, FX_SPARKLE4 = 0x0F, 0x03, 0x26
local SFX_SECRET_BIG = 0x73
local BUSH_OFFS = RT.t("Objects38.BUSH_OFFS") -- gUnk_08124364 (19 {x, y} before -1000)

-- kinstone.c CreateMinishEntrance (tx, ty: the block's top-left tile)
function M.minishEntrance(f, tx, ty)
  local O = f:objects()
  if not O then return end
  local t = M.ENTRANCE_TILE
  for y = 0, 3 do
    for x = 0, 4 do
      local px, py = tx + x, ty + y
      if px >= 0 and py >= 0 and px < f.room.tw and py < f.room.th then O:setTileType(1, px, py, t) end
      t = t + 1
    end
  end
end

local function entrance(f, e)
  M.minishEntrance(f, math.floor((e.x - 0x20) / 16), math.floor((e.y - 8) / 16))
end

-- TreeHidingPortal sub_0809E9A0: the act tile in front of a bouncing Link
local function bounceTile(f)
  local p = f.player
  if not p.bounce or not p.probe then return 0 end
  local x, y = p:probe()
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  local r = f.room
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return 0 end
  local tt = r:tileType(1, tx, ty)
  if not tt then return 0 end
  if tt >= 0x4000 then return tt end
  return f.assets.actTile[tt] or 0
end
M.bounceTile = bounceTile

local function update(d, e)
  local f = d.field
  local p = f.player
  e.t38 = (e.t38 or 0) + 1
  if e.action == 1 then
    if math.abs(e.x - p.x) <= 0x30 and math.abs(e.y - p.y) <= 0x30 and f:flag("global", M.EZERO_1ST)
      and e.t38 % 4 == 0 and f.addFx then
      local x = math.random(0, 15)
      if math.random(0, 1) == 1 then x = -x end
      local y = math.random(0, 15)
      if y > 4 then y = -y end
      f:addFx(e.x + x, e.y + y, SPECIAL_FX, FX_SPARKLE4)
    end
    if bounceTile(f) == M.ACT_TILE_84 then
      e.action, e.timer = 2, 15
      p.control = false
    end
  elseif e.action == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.timer = 3, 60
      e.hidden = true
      entrance(f, e)
      if f.addFx then
        for i = 0, #BUSH_OFFS do
          local o = BUSH_OFFS[i]
          if o and o.x ~= -1000 then
            f:addFx(e.x + o.x, e.y + o.y, SPECIAL_FX, FX_BUSH)
            local fx = f.entities[#f.entities]
            if fx and fx.fx then fx.layer = 2 end
          end
        end
      end
    end
  elseif e.action == 3 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      if (e.flag or 0) ~= 0 then d:set(e.flag, true) end
      p.control = true
      f:sound(SFX_SECRET_BIG)
      e.deleted = true
    end
  end
end
M.update = update

-- ---------------------------------------------------------------------------
-- MISC_MANAGER types 0 / 9 / $C
-- ---------------------------------------------------------------------------
M.MISC_MANAGER = 0x0F
local TT_0, TT_29, TT_38, TT_97 = 0x00, 0x1D, 0x26, 0x61
local FX_BIG_EXPLOSION, FX_BIG_EXPLOSION2 = 0x35, 0x43
local SFX_124, SFX_16E, SFX_1B0 = 0x124, 0x16E, 0x1B0
local T0_SPOTS = { { 0x128, 0x68 }, { 0x158, 0x68 }, { 0x128, 0x98 }, { 0x158, 0x98 } }

local function setType(f, layer, tx, ty, t)
  local r = f.room
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return end
  local O = f:objects()
  if O then O:setTileType(layer, tx, ty, t) end
end

function M.dirtTile(f, tx, ty) -- SetDirtTile
  setType(f, 1, tx, ty, TT_29)
  setType(f, 2, tx, ty, TT_0)
  setType(f, 2, tx, ty - 1, TT_0)
end

local function fxAt(f, x, y, id, layer)
  if not f.addFx then return end
  f:addFx(x, y, SPECIAL_FX, id)
  local fx = f.entities[#f.entities]
  if fx and fx.fx and layer then fx.layer = layer end
end

local function miscTick(d, m)
  if m.deleted then return end
  local f = d.field
  local t = m.type
  if t == 0 then
    m.action = 1
    if not f:flag("room", m.type2 or 0) then return end
    for i, s in ipairs(T0_SPOTS) do
      if not f:flag("room", (m.type2 or 0) + i) then
        local tx, ty = math.floor(s[1] / 16), math.floor(s[2] / 16)
        if f.room:tileType(1, tx, ty) == TT_97 then setType(f, 1, tx, ty, TT_38) end
      end
    end
    f:sound(SFX_124)
    m.deleted = true
  elseif t == 9 then
    local tx, ty = math.floor((m.x or 0) / 16), math.floor((m.y or 0) / 16)
    if (m.action or 0) == 0 then
      m.action = 1
      if d:check(m.c1) then M.dirtTile(f, tx, ty); m.deleted = true end
    elseif d:check(m.c1) then
      M.dirtTile(f, tx, ty)
      fxAt(f, m.x, m.y, FX_BIG_EXPLOSION2, 1)
      f:sound(SFX_16E)
      m.deleted = true
    end
  elseif t == 0xC then
    if d:check(m.c1) then m.deleted = true return end
    if not d:check(m.c0) then return end
    fxAt(f, m.x, m.y, FX_BIG_EXPLOSION, 2)
    f:sound(SFX_1B0)
    m.deleted = true
  end
end
M.miscTick = miscTick

function M.spawnManager(d, m)
  if m.id ~= M.MISC_MANAGER or not (m.type == 0 or m.type == 9 or m.type == 0xC) then return nil end
  m.action = 0
  require("src.zelda.tmc.R26").ticker(d, function(dd, me) miscTick(dd, me) end, m)
  return true
end

function M.spawnObject(d, e)
  if e.id ~= M.TREE_HIDING_PORTAL then return nil end
  local f = d.field
  if (e.flag or 0) ~= 0 and d:check(e.flag) then
    entrance(f, e)
    e.deleted = true
    return e
  end
  e.action, e.layer, e.hidden = 1, 2, true -- (no sprite: its frames are empty)
  e.extUpdate = update
  d:track(e)
  return e
end

return M
