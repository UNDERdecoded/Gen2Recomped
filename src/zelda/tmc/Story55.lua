-- Round 55: the Flippers quest's second book -- Dr. Left's rafters ($2E:02).
--
-- CARTRIDGE BEHAVIOUR:
--   * HUGE_BOOK $88 (src/object/macroBook.c, the big book lying on the rafters; loaded by
--     sub_StateChange_MinishRafters_DrLeft while MIZUKAKI_START and not MIZUKAKI_HARIFALL):
--     Init: action 1, timer 128, subtimer 0, x -= 4, spriteOffsetY -4, animation 0;
--     sub_0809A958: SPECIAL_TILE_116 ($4074) on the 4 x 4 tiles from (tile - 2, tile - 2) and
--     SPECIAL_TILE_34 ($4022) on the last two of a fifth row (bottom layer).
--     sub_0809AA00 (every frame of actions 1 / 2): subtimer = 0; the child (the first TOWN_MINISH
--     with type 0, type2 8) counts once its x <= origin + $15A; Link counts the same way while
--     EntityInRectRadius(book, Link, $20, $22), and the first clone (gPlayerClones[0]) with him.
--     Action1: timer runs down; then, at each end of the animation, subtimer 3 -> action 2
--     (timer 90, animation 2), else the animation restarts as `subtimer` (0 / 1 / 2: the book
--     tips with the weight).  Action2: subtimer < 2 -> action 1; while the timer runs, a clone
--     gone -> action 1; at 0 and the animation's end -> action 3, animation 3,
--     RequestPriorityDuration(120).  Action3 by the frame's flags: $20 -> timer + 1,
--     SetPlayerControl($FF), SetGlobalFlag(MIZUKAKI_HARIFALL); $40 -> the tiles back
--     (RestorePrevTileEntity); $80 and frameDuration 0 -> gone.  While its timer is set it grows
--     (unk80 + 8) and slides x + 1/64 per frame.
--   * townMinish.c sub_0806AF70 (zVelocity = Q_16_16(2.25)) and sub_0806AF78 (GravityUpdate
--     Q_8_8(24); landed -> z 0 and the next hop): the rafters Minish hopping off the book
--     (script_TownMinish3 after MIZUKAKI_HARIFALL).
-- SIMPLIFIED: SetPlayerControl($FF) (controlMode != 0: no entity collisions / pause) is not
--   modelled; the affine growth is not drawn (unk80 kept); sub_0809AA9C's spriteOffsetY nudges
--   (1 / 2 px while the book tips) are not drawn.
local bit = require("bit")
local band = bit.band

local M = {}
M.HUGE_BOOK, M.TOWN_MINISH, M.MIZUKAKI_HARIFALL = 0x88, 0x38, 0x2A
M.SPECIAL_TILE_116, M.SPECIAL_TILE_34 = 0x4074, 0x4022

local N = require("src.zelda.tmc.Native").N
local function reg(addr, fn) if not N[addr] then N[addr] = fn end end

-- sub_0806AF70 / sub_0806AF78 (z up-positive here)
reg(0x0806AF70, function(f, e) e.zv = 2.25 end)
reg(0x0806AF78, function(f, e)
  local nz = (e.z or 0) + (e.zv or 0)
  e.zv = (e.zv or 0) - 24 / 256
  if nz <= 0 and e.zv <= 0 then e.z = 0; e.zv = 2.25 else e.z = nz end
end)

-- the 20 tiles of sub_0809A958 (tile type or 0), row by row
M.TILES = {}
for i = 1, 16 do M.TILES[i] = M.SPECIAL_TILE_116 end
M.TILES[17], M.TILES[18], M.TILES[19], M.TILES[20] = 0, 0, M.SPECIAL_TILE_34, M.SPECIAL_TILE_34

local function anim(f, e, a)
  e.objAnim, e.animIndex = a, a
  if e.anim and e.sprite then e.anim:set(f.assets:sprite(e.sprite), a, true) end
  e.flagKey = nil
end
-- the current keyframe's frame flags; `take` clears them until the next keyframe
local function fflags(e)
  if not e.anim then return 0 end
  if e.flagKey == e.anim.key then return band(e.anim.flags or 0, 0x80) end
  return e.anim.flags or 0
end
local function take(e) e.flagKey = e.anim and e.anim.key end

function M.setTiles(f, e)
  local r = f.room
  local tx0, ty0 = math.floor((e.x + 4) / 16) - 2, math.floor(e.y / 16) - 2
  e.saved = {}
  local k = 1
  for row = 0, 4 do
    for col = 0, 3 do
      local t = M.TILES[k]
      local tx, ty = tx0 + col, ty0 + row
      if band(t, 0x4000) ~= 0 and tx >= 0 and ty >= 0 and tx < r.tw and ty < r.th then
        e.saved[#e.saved + 1] = { tx, ty, r.maps.bottom[ty * r.tw + tx] }
        r:setTile(1, tx, ty, t)
      end
      k = k + 1
    end
  end
end
function M.restoreTiles(f, e)
  local r = f.room
  for _, s in ipairs(e.saved or {}) do if s[3] then r:setTile(1, s[1], s[2], s[3]) end end
  e.saved = {}
end

local function inRect(a, b, rx, ry) -- EntityInRectRadius
  return math.abs(math.floor(b.x) - math.floor(a.x)) <= rx and math.abs(math.floor(b.y) - math.floor(a.y)) <= ry
end
local function firstClone(f)
  local c = rawget(f, "playerClones")
  if type(c) ~= "table" then return nil end
  for i = 1, 3 do if c[i] and not c[i].deleted then return c[i] end end
  return nil
end
M.firstClone = firstClone

-- sub_0809AA00
function M.count(f, e)
  local limit = 0x15A -- origin_x + $15A (room coordinates)
  local n = 0
  if not e.child or e.child.deleted then
    e.child = nil
    for _, o in ipairs(f.entities) do
      if o.kind == 7 and o.id == M.TOWN_MINISH and (o.form or 0) == 0 and band(o.param or 0, 0xFF) == 8 and not o.deleted then e.child = o end
    end
  elseif math.floor(e.child.x) <= limit then n = n + 1 end
  local p = f.player
  e.playerWithinRect = inRect(e, p, 0x20, 0x22)
  if e.playerWithinRect then
    if math.floor(p.x) <= limit then n = n + 1 end
    local c = firstClone(f)
    if c and math.floor(c.x) <= limit then n = n + 1 end
  end
  e.subtimer = n
  return n
end

local function update(d, e)
  local f = d.field
  local a = e.action
  if a == 1 then
    if e.anim then e.anim:update(1) end
    M.count(f, e)
    if e.timer > 0 then e.timer = e.timer - 1
    elseif e.anim and e.anim.done then
      if e.subtimer == 3 then
        e.action, e.timer, e.subtimer = 2, 90, 0
        anim(f, e, 2)
      else
        anim(f, e, e.subtimer)
      end
    end
  elseif a == 2 then
    if e.anim then e.anim:update(1) end
    M.count(f, e)
    if e.subtimer < 2 then
      e.action, e.timer = 1, 0
    elseif e.timer > 0 then
      e.timer = e.timer - 1
      if firstClone(f) then return end
      e.action, e.timer = 1, 0
    elseif e.anim and e.anim.done then
      e.action, e.timer = 3, 0
      anim(f, e, 3)
    end
  elseif a == 3 then
    local fl = fflags(e)
    local hi = band(fl, 0xE0)
    if hi == 0x80 then
      if e.anim and (e.anim.timer or 0) == 0 then e.deleted, e.hidden = true, true return end
    elseif hi == 0x40 then
      take(e)
      M.restoreTiles(f, e)
    elseif hi == 0x20 then
      take(e)
      e.timer = e.timer + 1
      f:setFlag("global", M.MIZUKAKI_HARIFALL, true)
      if e.anim then e.anim:update(1) end
    else
      if e.anim then e.anim:update(1) end
    end
    if e.timer > 0 then
      e.unk80 = e.unk80 + 8
      e.x = e.x + 1 / 64
    end
  end
end
M.update = update

function M.spawnObject(d, e)
  if e.id ~= M.HUGE_BOOK then return nil end
  local f = d.field
  local def = f:objects():def(M.HUGE_BOOK, e.form or 0)
  if def then f:objects():dress(e, def, 0) end
  e.literalAnim = true
  e.action, e.timer, e.subtimer, e.unk80 = 1, 128, 0, 0x80
  e.x = e.x - 4
  e.spriteOffsetY = -4
  e.oamPrio, e.spritePriority = 3, 7
  anim(f, e, 0)
  M.setTiles(f, e)
  e.extUpdate = function(dd, me) if not me.deleted then update(dd, me) end end
  d:track(e)
  return e
end

return M
