-- Round 32: PUSHABLE_FURNITURE ($4C, src/object/pushableFurniture.c) and
-- PUSHABLE_FURNITURE_MANAGER ($26, src/manager/pushableFurnitureManager.c):
-- the house wardrobes / shelves / boxes that hide the Minish cracks.  The
-- port drew the room-listed ones only (no tiles, not pushable) and never
-- created the manager's.  Listed in R27B.MODULES (spawnManager / frame);
-- Link's push comes from one line in PushAnim.update (M.playerPush).
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * The manager: GetCurrentRoomProperty(type) = 8-byte entries {flag,
--     type, type2, timer, x, y} up to flag $FF (max 32): each one a
--     PUSHABLE_FURNITURE with parent = the manager, layer 1, unk_82 = flag;
--     unk_2a = origin_y + timer (the y Link is compared with for the
--     furniture's priority, sub_0805C7CC / sub_08090514); type2 != $FF:
--     all pushed -> SetLocalFlag(type2).
--   * PushableFurniture_Init: speed $80, subtimer = timer (the room list's
--     paramB >> 8, or the manager's timer), unk_80 = 0 for type 1 (one tile,
--     pushed any way, SPECIAL_TILE_74), else 1 (two tiles, pushed left /
--     right, SPECIAL_TILE_43..47); types 2 / 4: y += 2 (sprite -2).  A
--     subtimer: the target unk_7e = (s8)subtimer + x (type 1 type2 1: + y);
--     $80 = already there; the flag (parent NULL: CheckFlags(paramC >> 16),
--     manager: CheckLocalFlag(unk_82) or, unk_82 & $80, the manager in
--     action 2) -> unk_81 = 1 (done) and moved to the target.
--   * sub_0808FF50 tiles: unk_80 0: SPECIAL_TILE_74 at its tile.  unk_80 1:
--     x & 8 -> its tile gets gUnk_08121EE4[unk_81] (43 / done 34) and the
--     one right [unk_81 + 4] (45 / 37), else its tile and the one left
--     [unk_81 + 2] (44 / 36), merged with a neighbour's halves
--     (sub_08090094), then sub_0809028C: the top layer two rows up (tile
--     types $300 / $301 / $302 / $306 / $308, the wall behind) decides
--     SPECIAL_TILE_38 / 101 / 102 on the bottom layer there.
--   * UpdatePlayerCollision: SPECIAL_TILE_43..45 in front, facing left /
--     right, sub_0801A370 (the push test, the tile beyond free; full size:
--     moving + ANIM frame bit 0, Minish: the Power Bracelets) -> the tile =
--     SPECIAL_TILE_48 + facing left, pushedObject $90 ($A0 Minish);
--     SPECIAL_TILE_74 with sub_0801A458 -> SPECIAL_TILE_75 + facing / 2,
--     pushedObject $A0 ($C0 Minish).  PlayerPush walks Link pushedObject &
--     $7F frames at kPushSpeed ($80; Minish $40).
--   * Action1: sub_0808FB68 / sub_0808FBFC see that tile -> action 2,
--     direction, CONTROL_1, sub_0808FD44 (speed $80 for 16 frames / Minish
--     $40 for 32; one-tile: 32 / 64 frames; SFX_10F; the old tiles back,
--     sub_08090498 for the wall row).  Not pushing: sub_0808FDE8 turns the
--     end halves 44 / 45 into 46 / 47 (not pushable that way) by the
--     neighbour's collision and back.
--   * Action2: LinearMoveUpdate; at the end the tiles again; with a target
--     reached: unk_81 = 1, the flag (SetFlag / SetLocalFlag / the
--     manager's bit), then timer 4 / 24 (+16 full size) -> SFX_BUTTON_PRESS.
--   * Types 2 / 4: Link's PLAYER_BOUNCE (the boots) into its front within
--     20 px below and 12 px across -> 12 frames, frameIndex 1, SFX_80,
--     type2 1: OBJECT_63 type 0 (CreateRandomItemDrop(4)), type2 2: a heart.
-- (round 34: sub_0800445C pushes Link out of the moving piece, Push34.lua)
-- SIMPLIFIED: the manager's priority swap is the sprite priority /
--   OAM priority only.
local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local M = {}
M.ID, M.MGR = 0x4C, 0x26
local ST = function(n) return 0x4000 + n end
local S34, S36, S37, S38 = ST(34), ST(36), ST(37), ST(38)
local S43, S44, S45, S46, S47, S48, S49 = ST(43), ST(44), ST(45), ST(46), ST(47), ST(48), ST(49)
local S74, S75, S78, S101, S102 = ST(74), ST(75), ST(78), ST(101), ST(102)
M.S43, M.S44, M.S45, M.S46, M.S47, M.S48, M.S49, M.S74, M.S75 = S43, S44, S45, S46, S47, S48, S49, S74, S75
local EE4 = { [0] = S43, S34, S44, S36, S45, S37 } -- gUnk_08121EE4
local EF0 = { [0] = S38, S101, S102, 0 }             -- gUnk_08121EF0
local SFX_10F, SFX_80, SFX_BUTTON_PRESS = 0x10F, 0x80, 0x10C
local ITEM_POWER_BRACELETS, ITEM_HEART = 0x45, 0x5F
local DV = require("src.zelda.tmc.RomTables").t("Furniture32.DV")

-- ---------------------------------------------------------------------------
-- tile helpers (tile positions as (tx, ty) of the room's map)
-- ---------------------------------------------------------------------------
local function inside(r, x, y) return x >= 0 and y >= 0 and x < r.tw and y < r.th end
local function getT(r, L, x, y) -- GetTileIndex
  if not inside(r, x, y) then return 0 end
  return r.maps[L == 2 and "top" or "bottom"][y * r.tw + x] or 0
end
local function ttype(r, L, x, y) -- GetTileTypeAtTilePos
  if not inside(r, x, y) then return 0 end
  return r:tileType(L, x, y) or 0
end
local function coll(r, L, x, y) -- GetCollisionDataAtTilePos
  if not inside(r, x, y) then return 0xFF end
  return (r.coll[L == 2 and 2 or 1] or r.coll[1])[y * r.tw + x] or 0
end
-- SetTile, remembering the first tile replaced (RestorePrevTileEntity)
local function setT(r, L, x, y, mt)
  if not inside(r, x, y) or not mt or mt == 0 then return end
  r.prev32 = r.prev32 or {}
  local k = (L == 2 and "t" or "b") .. (y * r.tw + x)
  if r.prev32[k] == nil then r.prev32[k] = getT(r, L, x, y) end
  r:setTile(L, x, y, mt)
end
local function restorePrev(r, L, x, y)
  local k = (L == 2 and "t" or "b") .. (y * r.tw + x)
  local v = r.prev32 and r.prev32[k]
  if v ~= nil then r:setTile(L, x, y, v); r.prev32[k] = nil end
end
local function act(f, tt) return (tt and tt < 0x4000) and (f.assets.actTile[tt] or 0) or tt end
M._h = { getT = getT, setT = setT, coll = coll }

-- ---------------------------------------------------------------------------
-- flags
-- ---------------------------------------------------------------------------
local function flagDone(f, e)
  if not e.f32parent then return e.f32flag ~= 0 and f:dungeon():check(e.f32flag) end
  if band(e.f32u82, 0x80) ~= 0 then return e.f32parent.action == 2 end
  return f:flag("local", e.f32u82)
end
local function setDone(f, e)
  local m = e.f32parent
  if not m then
    if e.f32flag ~= 0 then f:dungeon():set(e.f32flag, true) end
  elseif band(e.f32u82, 0x80) ~= 0 then
    m.u28 = bor(m.u28 or 0, 2 ^ (e.f32index or 0))
  else
    f:setFlag("local", e.f32u82, true)
  end
end

-- ---------------------------------------------------------------------------
-- sub_08090094 / sub_0809028C / sub_0808FF50
-- ---------------------------------------------------------------------------
local function halfTile(e, r, mt, x, y)
  local c1 = coll(r, 1, x, y)
  local cur = getT(r, 1, x, y)
  if cur < 0x4000 then
    local n = mt
    if (mt == S37 or mt == S45 or mt == S47) and c1 == 5 then n = S34 end
    if (mt == S36 or mt == S44 or mt == S46) and c1 == 10 then n = S34 end
    setT(r, 1, x, y, n)
    return
  end
  local n = cur
  if cur == S37 then
    if mt == S36 or mt == S44 then n = S34; e.f32u83 = bor(e.f32u83, 0x10) end
  elseif cur == S45 or cur == S47 then
    if mt == S44 then n = S43; e.f32u83 = bor(e.f32u83, 0x10) end
    if mt == S36 then n = S34; e.f32u83 = bor(e.f32u83, 0x10) end
  elseif cur == S36 then
    if mt == S37 or mt == S45 then n = S34; e.f32u83 = bor(e.f32u83, 0x20) end
  elseif cur == S44 or cur == S46 then
    if mt == S45 then n = S43; e.f32u83 = bor(e.f32u83, 0x20) end
    if mt == S37 then n = S34; e.f32u83 = bor(e.f32u83, 0x20) end
  else
    return
  end
  setT(r, 1, x, y, n)
end

local function wall(r, i, x, y) setT(r, 1, x, y, EF0[i]) end -- sub_08090480

local function wallRow(e, r, right)
  e.f32u83 = band(e.f32u83, 0x30)
  local ax, ay = e.f32t70[1], e.f32t70[2] - 2 -- unk_70 - $80
  local bx, by = e.f32t72[1], e.f32t72[2] - 2 -- unk_72 - $80
  local u = function(v) e.f32u83 = bor(e.f32u83, v) end
  local has = function(v) return band(e.f32u83, v) ~= 0 end
  if right then
    if has(0x20) then wall(r, 0, bx + 1, by)
    else
      local t = ttype(r, 2, bx, by)
      if t == 0x301 then u(8) elseif t == 0x308 then u(2) end
    end
    if has(0x2A) then wall(r, 0, ax, ay); wall(r, 0, bx, by) end
    if has(0x10) then
      if ttype(r, 1, ax - 1, ay) ~= 0x300 then wall(r, 0, ax - 1, ay); wall(r, 2, ax - 2, ay) end
      return
    end
    local t = ttype(r, 2, ax - 1, ay)
    if t == 0x300 then u(4) elseif t == 0x308 then u(1) end
    if has(0x15) and not has(0x2A) then wall(r, 0, ax, ay); wall(r, 1, bx, by) end
  else
    if has(0x10) then wall(r, 0, ax - 1, ay)
    else
      local t = ttype(r, 2, ax, ay)
      if t == 0x302 then u(4) elseif t == 0x306 then u(1) end
    end
    if has(0x15) then wall(r, 0, ax, ay); wall(r, 0, bx, by) end
    if has(0x20) then
      if ttype(r, 1, bx + 1, by) ~= 0x300 then wall(r, 0, bx + 1, by); wall(r, 1, bx + 2, by) end
      return
    end
    local t = ttype(r, 2, bx + 1, by)
    if t == 0x300 then u(8) elseif t == 0x306 then u(2) end
    if has(0x2A) and not has(0x15) then wall(r, 2, ax, ay); wall(r, 0, bx, by) end
  end
end

-- sub_08090498: the wall row back before a push
local function wallRestore(f, e, r)
  local ax, ay = e.f32t70[1], e.f32t70[2] - 2
  restorePrev(r, 1, ax, ay)
  if band(e.f32u83, 1) ~= 0 and ttype(r, 2, ax, ay) == 0x306 then r.coll[1][ay * r.tw + ax] = 0x62 end
  local bx, by = e.f32t72[1], e.f32t72[2] - 2
  restorePrev(r, 1, bx, by)
  if band(e.f32u83, 2) ~= 0 and ttype(r, 2, bx, by) == 0x308 then r.coll[1][by * r.tw + bx] = 0x63 end
end

-- sub_0808FF50
function M.tiles(f, e)
  local r = f.room
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  e.f32t7c = { tx, ty }
  if e.f32u80 == 0 then
    e.f32t70 = { tx, ty }
    e.f32o74 = getT(r, 1, tx, ty)
    setT(r, 1, tx, ty, S74)
  elseif band(math.floor(e.x), 8) ~= 0 then
    e.f32t70 = { tx, ty }
    e.f32o74 = getT(r, 1, tx, ty)
    setT(r, 1, tx, ty, EE4[e.f32u81])
    e.f32t72 = { tx + 1, ty }
    e.f32o76 = getT(r, 1, tx + 1, ty)
    halfTile(e, r, EE4[e.f32u81 + 4], tx + 1, ty)
    wallRow(e, r, true)
  else
    e.f32t72 = { tx, ty }
    e.f32o76 = getT(r, 1, tx, ty)
    setT(r, 1, tx, ty, EE4[e.f32u81])
    e.f32t70 = { tx - 1, ty }
    e.f32o74 = getT(r, 1, tx - 1, ty)
    halfTile(e, r, EE4[e.f32u81 + 2], tx - 1, ty)
    wallRow(e, r, false)
  end
end

-- sub_08090254: the tiles before the furniture
local function untile(f, e)
  local r = f.room
  r:setTile(1, e.f32t70[1], e.f32t70[2], e.f32o74)
  if e.f32u80 == 1 then r:setTile(1, e.f32t72[1], e.f32t72[2], e.f32o76) end
end

-- sub_0808FDE8
local function edgeHalves(f, e)
  local r = f.room
  local x, y = e.f32t70[1], e.f32t70[2]
  local c = coll(r, 1, x - 1, y)
  local free = (band(c, 0xF0) == 0 or band(c, 0xF0) == 0x50)
  if getT(r, 1, x, y) == S46 then
    if not free or band(c, 5) == 0 then r:setTile(1, x, y, S44) end
  elseif coll(r, 1, x, y) == 5 and free and band(c, 5) ~= 0 then
    r:setTile(1, x, y, S46)
  end
  x, y = e.f32t72[1], e.f32t72[2]
  c = coll(r, 1, x + 1, y)
  free = (band(c, 0xF0) == 0 or band(c, 0xF0) == 0x50)
  if getT(r, 1, x, y) == S47 then
    if not free or band(c, 10) == 0 then r:setTile(1, x, y, S45) end
  elseif coll(r, 1, x, y) == 10 and free and band(c, 10) ~= 0 then
    r:setTile(1, x, y, S47)
  end
end

-- ---------------------------------------------------------------------------
-- the object
-- ---------------------------------------------------------------------------
function M.init(f, e)
  local typ, t2 = e.form or 0, band(e.param or 0, 0xFF)
  e.f32 = f.room
  e.f32action = 1
  e.f32speed = 0x80
  e.f32sub = e.f32sub or band(rshift(e.param or 0, 8), 0xFF) -- subtimer = timer (paramB >> 8)
  e.f32timer = 0
  e.f32u81, e.f32u83 = 0, 0
  e.f32flag = e.f32flag or rshift((e.data and e.data.paramC) or 0, 16)
  e.solid = false -- the tiles stop Link
  e.oamPrio = 2
  if typ == 1 then
    e.spritePriority = 4
    e.f32u80 = 0
  else
    e.f32u80 = 1
    e.spritePriority = 5
    if typ == 2 or typ == 4 then
      e.y = e.y + 2
      e.spriteOY = (e.spriteOY or 0) - 2
      e.f32bonk, e.staticFrame = 0, 0
    end
  end
  local vert = typ == 1 and t2 == 1
  local s = e.f32sub
  if s ~= 0 then
    local cond = false
    if s == 0x80 then
      cond = true
      e.f32u7e = vert and math.floor(e.y) or math.floor(e.x)
    else
      local d = s >= 0x80 and s - 0x100 or s
      e.f32u7e = d + (vert and math.floor(e.y) or math.floor(e.x))
      cond = flagDone(f, e)
    end
    if cond then
      e.f32u81 = 1
      if vert then e.y = e.f32u7e else e.x = e.f32u7e end
    end
  end
  M.tiles(f, e)
end

-- sub_0808FD44
local function startPush(f, e, second)
  local mini = f.player.minish
  if e.f32u80 == 1 then
    if e.f32u83 ~= 0 then wallRestore(f, e, f.room) end
    e.f32speed, e.f32timer = mini and 0x40 or 0x80, mini and 32 or 16
  else
    e.f32speed, e.f32timer = mini and 0x40 or 0x80, mini and 64 or 32
  end
  f:sound(SFX_10F)
  untile(f, e)
  f.player.control32 = e -- SetPlayerControl(CONTROL_1)
end

-- sub_0808FC5C (true: the push is over)
local function slide(f, e)
  local v = DV[e.f32dir]
  e.x = e.x + v[1] * e.f32speed / 256
  e.y = e.y + v[2] * e.f32speed / 256
  e.f32timer = e.f32timer - 1
  if e.f32timer > 0 then return false end
  e.x, e.y = math.floor(e.x + 0.5), math.floor(e.y + 0.5)
  local typ, t2 = e.form or 0, band(e.param or 0, 0xFF)
  if e.f32sub == 0 then M.tiles(f, e) return true end
  local reached
  if typ == 1 and t2 == 1 then reached = e.y == e.f32u7e else reached = e.x == e.f32u7e end
  if not reached then M.tiles(f, e) return true end
  e.f32u81 = 1
  setDone(f, e)
  e.f32timer = e.f32u80 == 0 and 4 or 24
  if not f.player.minish then e.f32timer = e.f32timer + 16 end
  M.tiles(f, e)
  return true
end

-- sub_0808FECC: Link bounced (PLAYER_BOUNCE) into its front
local function bonked(f, e)
  local p = f.player
  return not p.minish and p.bounce ~= nil and (p.animationState or 4) == 0 and p.y - e.y < 0x14
    and e.x + 12 > p.x and e.x - 12 < p.x
end

-- sub_0808FF20
local function bonkDrop(f, e)
  local t2 = band(e.param or 0, 0xFF)
  if t2 == 1 then
    pcall(require("src.zelda.tmc.Drops").randomDrop, f, { x = e.x, y = e.y, z = 8, layer = 1 }, 4, f:objects())
  elseif t2 == 2 then
    local it = f:objects():groundItem(ITEM_HEART, 0, e.x, e.y)
    if it then it.layer = 1; f.entities[#f.entities + 1] = it end
  end
end

function M.update(f, e)
  local a = e.f32action
  if a == 1 then
    if e.f32u81 == 0 then
      local r = f.room
      if e.f32u80 == 0 then
        local t = getT(r, 1, e.f32t7c[1], e.f32t7c[2])
        if t ~= S74 and t >= S75 and t <= S78 then
          e.f32action, e.f32dir = 2, band(t - S75, 3) * 8
          startPush(f, e, false)
        end
      else
        local t = getT(r, 1, e.f32t70[1], e.f32t70[2])
        if t == S48 or t == S49 then
          e.f32action, e.f32dir = 2, band(t - 0x4030, 1) * 16 + 8
          startPush(f, e, false)
        else
          t = getT(r, 1, e.f32t72[1], e.f32t72[2])
          if t == S48 or t == S49 then
            e.f32action, e.f32dir = 2, band(t - 0x4030, 1) * 16 + 8
            startPush(f, e, true)
          end
          if e.f32action == 1 then edgeHalves(f, e) end
        end
      end
    elseif e.f32timer > 0 then
      e.f32timer = e.f32timer - 1
      if e.f32timer == 0 then f:sound(SFX_BUTTON_PRESS) end
    end
    if e.f32bonk then
      if e.f32bonk == 0 then
        if bonked(f, e) then e.f32bonk, e.f32bonkT = 1, 12 end
      elseif e.f32bonk == 1 then
        e.f32bonkT = e.f32bonkT - 1
        if e.f32bonkT <= 0 then
          e.staticFrame, e.f32bonk = 1, 2
          f:sound(SFX_80)
          bonkDrop(f, e)
        end
      end
    end
  elseif a == 2 then
    require("src.zelda.tmc.Push34").out(f, e) -- round 34: sub_0800445C (Link pushed out of the piece)
    if slide(f, e) then
      e.f32action = 1
      if f.player.control32 == e then f.player.control32 = nil end
    end
  end
  -- sub_08090514 (the manager's subAction from sub_0805C7CC)
  local m = e.f32parent
  if m then
    local p = f.player
    local sa
    if p.minish then sa = (p.y < m.u2a + 0x10) and 1 or 0 else sa = (p.y < m.u2a + 0x28) and 3 or 2 end
    if sa == 0 then e.oamPrio, e.spritePriority = 2, 4
    elseif sa == 1 then e.oamPrio, e.spritePriority = 3, 4
    elseif sa == 2 then e.oamPrio, e.spritePriority = 2, 5
    else e.oamPrio, e.spritePriority = 2, 3 end
  end
end

-- ---------------------------------------------------------------------------
-- Link's side: UpdatePlayerCollision cases SPECIAL_TILE_43..45 / 74
-- ---------------------------------------------------------------------------
local OFF = require("src.zelda.tmc.RomTables").t("Furniture32.OFF") -- gUnk_080B4488

-- sub_0801A4F8
local function pushTest(f, p, dx, dy, x0, y0)
  if p.minish then
    if (f:inventory(ITEM_POWER_BRACELETS) or 0) ~= 1 then return false end
    local d = OFF[p.animationState or 4]
    if (d[1] ~= 0 and p.x ~= x0) or (d[2] ~= 0 and p.y ~= y0) then return false end
    return true
  end
  return p.pushFrame == true
end

local function blockedAct(f, r, L, x, y)
  local a = act(f, ttype(r, L, x, y))
  return a == 0x52 or a == 0x26 or a == 0x27 or a == 0x29 or a == 0x74
end

-- sub_0801A370
local function canPush2(f, p, tx, ty)
  local s = p.animationState or 4
  if band(s, 2) == 0 then return false end
  local r = f.room
  local off = OFF[s][1]
  local x, y = tx + off, ty
  local t = getT(r, p.layer or 1, x, y)
  if t == S43 then x = x + off
  elseif t >= S44 and t <= S47 then return true end
  if coll(r, 2, x, y - 2) == 0x46 then return false end
  if blockedAct(f, r, p.layer or 1, x, y) then return false end
  local c = coll(r, p.layer or 1, x, y)
  if c == 0 then return true end
  if (c == 5 or c == 0x45) and off == 1 then return true end
  if (c == 0xA or c == 0x44) and off == -1 then return true end
  return false
end

-- sub_0801A458 (collision type 8)
local function canPush1(f, p, tx, ty)
  local d = OFF[p.animationState or 4]
  local x, y = tx + d[1], ty + d[2]
  local r = f.room
  if blockedAct(f, r, p.layer or 1, x, y) then return false end
  local c = coll(r, p.layer or 1, x, y)
  if c == 0x28 then return false end
  if c >= 1 and c <= 0xF then return false end
  if r:isSolid(x * 16 + 8, y * 16 + 8, p.layer or 1) then return false end
  return true
end

local function pushUpdate(p)
  local ps = p.push32
  local d = OFF[ps.dir]
  p:moveBy(d[1] * ps.speed / 256, d[2] * ps.speed / 256)
  if p.anim then p.anim:update(1) end
  ps.left = ps.left - 1
  if ps.left <= 0 then
    p.push32 = nil; p.extUpdate = nil; p.state = "normal"
    p.pushT, p.pushing = 0, false
  end
end

-- PushAnim.update: true when a furniture push started
function M.playerPush(p, dx, dy, x0, y0)
  local f = p.field
  if p.state ~= "normal" or (p.z or 0) ~= 0 or p.control32 then return false end
  if dx == 0 and dy == 0 then return false end
  local s = p.animationState or 4
  local held = (s == 0 and dy < 0) or (s == 4 and dy > 0) or (s == 2 and dx > 0) or (s == 6 and dx < 0)
  if not held then return false end
  local fx, fy
  if not p.minish and not p.probe then return false end -- round 33: (a stand-in player without the sensor, tests)
  if p.minish then fx, fy = require("src.zelda.tmc.Push31").front(p) else fx, fy = p:probe() end
  local tx, ty = math.floor(fx / 16), math.floor(fy / 16)
  local r = f.room
  local L = p.layer or 1
  local t = getT(r, L, tx, ty)
  local frames
  if t >= S43 and t <= S45 then
    if not pushTest(f, p, dx, dy, x0, y0) or not canPush2(f, p, tx, ty) then return false end
    r:setTile(L, tx, ty, S48 + rshift(band(s, 4), 2))
    frames = p.minish and 0x20 or 0x10
  elseif t == S74 then
    if not pushTest(f, p, dx, dy, x0, y0) or not canPush1(f, p, tx, ty) then return false end
    r:setTile(L, tx, ty, S75 + rshift(s, 1))
    frames = p.minish and 0x40 or 0x20
  else
    return false
  end
  p.state = "ext"
  p.x, p.y = math.floor(p.x), math.floor(p.y)
  p.push32 = { left = frames, dir = s, speed = p.minish and 0x40 or 0x80 }
  p.extUpdate = pushUpdate
  if not p.minish then
    local PA = require("src.zelda.tmc.PushAnim")
    p.pushing = true
    p:setAnim(PA.anim(p), true)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- DOUBLE_BOOKSHELF ($8B, doubleBookshelf.c): the library's double shelf
-- ---------------------------------------------------------------------------
--   * Init type 0: frameIndex 0, action 3 subAction 4 (SPECIAL_TILE_34 x3 at
--     its tile - 1 .. + 1), sub_0809B334 (SPECIAL_TILE_38 x3 two rows up),
--     and its child: DOUBLE_BOOKSHELF type 1 at (+16, +16), or (0, +16) with
--     the flag (paramC >> 16) set (child unk_84 1).  The child: frameIndex 1,
--     subAction = unk_84: 0 -> SPECIAL_TILE_130 at x-2, 34 at x-1..x+1; 1 ->
--     95 at x-1, 34 at x, x+1, 130 at x+2.
--   * The parent each frame (sub_0809B274): Link 20 px above it -> b0 5;
--     then Link right of x - $1C -> SPECIAL_TILE_34 at its tile + 2 and the
--     child's sub_0809B358 (five tiles at child - (2, 2) from gUnk_08123D68
--     [unk_84 + 2k]); back left of x - $20 -> RestorePrevTileEntity on all.
--     The child copies the parent's OAM / sprite priority.
--   * DoubleBookshelf_Action1 of the child only reads a tile type (checked
--     on the ROM at $0809B034: no state change), so the second shelf never
--     slides; UpdatePlayerCollision's SPECIAL_TILE_95 (-> 116) has no taker.
local S95, S116, S130 = ST(95), ST(116), ST(130)
local ARR = { [0] = S34, S34, S116, S38, S116, S116, S38, S116, S34, S34 } -- gUnk_08123D68

local function shelfTiles(f, c)
  local r = f.room
  local tx, ty = math.floor(c.x / 16) - 1, math.floor(c.y / 16)
  if c.u84b == 0 then
    setT(r, 1, tx - 1, ty, S130); setT(r, 1, tx, ty, S34); setT(r, 1, tx + 1, ty, S34); setT(r, 1, tx + 2, ty, S34)
  else
    setT(r, 1, tx, ty, S95); setT(r, 1, tx + 1, ty, S34); setT(r, 1, tx + 2, ty, S34); setT(r, 1, tx + 3, ty, S130)
  end
end

function M.shelfInit(f, e)
  e.b32 = f.room
  local r = f.room
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  e.staticFrame = e.form or 0
  if (e.form or 0) ~= 0 then return end
  e.u84b = 0
  e.shelfTile = { tx, ty }
  for dx = -1, 1 do setT(r, 1, tx + dx, ty, S34); setT(r, 1, tx + dx, ty - 2, S38) end
  local flag = rshift((e.data and e.data.paramC) or 0, 16)
  local done = flag ~= 0 and f:dungeon():check(flag)
  local c = f:spawn({ kind = 6, id = 0x8B, paramA = 1, paramB = 0, pool = 0x0F, x = e.x + (done and 0 or 16), y = e.y + 16, paramC = 0 })
  if c then
    c.b32, c.layer, c.staticFrame, c.shelfParent = f.room, e.layer or 1, 1, e
    c.u84b = done and 1 or 0
    e.shelfChild = c
    shelfTiles(f, c)
  end
end

function M.shelfUpdate(f, e)
  local c = e.shelfChild
  if (e.form or 0) ~= 0 then
    local pa = e.shelfParent
    if pa then e.oamPrio, e.spritePriority = pa.oamPrio, pa.spritePriority end
    return
  end
  local p, r = f.player, f.room
  local tx, ty = e.shelfTile[1], e.shelfTile[2]
  if e.u84b == 0 then
    if p.y + 0x14 >= e.y then return end
    e.u84b, e.spritePriority = 1, 5
  elseif e.u84b == 1 then
    if p.x + 0x1C > e.x then
      e.u84b = 2
      setT(r, 1, tx + 2, ty, S34)
      if c then
        local cx, cy = math.floor(c.x / 16) - 2, math.floor(c.y / 16) - 2
        for k = 0, 4 do setT(r, 1, cx + k, cy, ARR[c.u84b + 2 * k]) end
      end
      return
    end
    if p.y + 0x10 <= e.y then return end
    e.u84b, e.spritePriority = 0, 4
  else
    if p.x + 0x20 >= e.x then return end
    e.u84b = 1
    restorePrev(r, 1, tx + 2, ty)
    if c then
      local cx, cy = math.floor(c.x / 16) - 2, math.floor(c.y / 16) - 2
      for k = 0, 4 do restorePrev(r, 1, cx + k, cy) end
    end
  end
end

-- furniture.c FurnitureInit flags $400: sub_08090E64 (a FLAME over it)
local function furnitureFlame(f, e)
  e.flame32 = f.room
  local fu = e.furniture
  if not fu or band(fu.flags or 0, 0x7FFF) ~= 0x400 then return end
  local t2 = band(e.param or 0, 0xFF)
  if t2 ~= 0 then e.spriteOX = 1 end
  local fl = { kind = 6, id = 0x2A, form = 0, x = e.x + (t2 - 2), y = e.y, z = 16, layer = 2, oamPrio = 1,
               animationState = 0, field80 = 0, field82 = 0, interactType = 0, flame = true }
  local O = f:objects()
  local def = O and O.def and O:def(0x2A, 0)
  if not def then return end
  O:dress(fl, def, 0)
  fl.extUpdate = function(_, me) if me.anim and me.anim.update then me.anim:update(1) end end
  f.entities[#f.entities + 1] = fl
  f:sound(0x124) -- SFX_124
end

-- ---------------------------------------------------------------------------
-- the manager and the R27B interface
-- ---------------------------------------------------------------------------
local function region(f)
  local A = f.assets
  local reg = A.manifest.entityRegion
  if not reg then return nil end
  A.entityBlob = A.entityBlob or A.store:read("entities.bin") or ""
  return A.entityBlob, reg.base
end

-- the property list (8-byte entries up to $FF)
function M.propList(f, k)
  local props = f.room.maps and f.room.maps.header and f.room.maps.header.props
  local addr = props and props[k]
  if not addr then return nil end
  local b, base = region(f)
  if not b then return nil end
  local o = addr - base
  if o < 0 or o >= #b then return nil end
  local out = {}
  for i = 0, 31 do
    local q = o + 8 * i + 1
    local fl = b:byte(q)
    if not fl or fl == 0xFF then break end
    out[#out + 1] = { flag = fl, type = b:byte(q + 1), type2 = b:byte(q + 2), timer = b:byte(q + 3),
      x = b:byte(q + 4) + 256 * b:byte(q + 5), y = b:byte(q + 6) + 256 * b:byte(q + 7) }
  end
  return out
end

function M.spawnManager(d, m)
  if m.id ~= M.MGR then return nil end
  local f = d.field
  local list = M.propList(f, m.type or 0)
  if not list then return true end
  local mg = { u2a = m.b1 or 0, u28 = 0, u29 = 0, type2 = m.type2 or 0xFF }
  if f.f32managers and f.f32managers.room ~= f.room then f.f32managers = nil end
  for i, it in ipairs(list) do
    local e = f:spawn({ kind = 6, id = M.ID, paramA = it.type, paramB = it.type2, pool = 0x0F, x = it.x, y = it.y, paramC = 0 })
    if e then
      e.f32parent, e.f32u82, e.f32sub, e.f32index, e.f32flag = mg, it.flag, it.timer, i - 1, 0
      e.layer = 1
      mg.u29 = bor(mg.u29, 2 ^ (i - 1))
    end
  end
  if mg.type2 == 0xFF or f:flag("local", mg.type2) then mg.action = 2 else mg.action = 1 end
  f.f32managers = f.f32managers or { room = f.room }
  f.f32managers[#f.f32managers + 1] = mg
  return true
end

function M.frame(f)
  local r = f.room
  if not r then return false end
  if f.f32managers and f.f32managers.room ~= r then f.f32managers = nil end
  for _, mg in ipairs(f.f32managers or {}) do
    if mg.action == 1 and mg.u28 == mg.u29 then mg.action = 2; f:setFlag("local", mg.type2, true) end
  end
  local ents = f.entities
  for i = 1, #ents do
    local e = ents[i]
    if e.kind == 6 and not e.deleted and not e.unplaced then
      if e.id == M.ID then
        if e.f32 ~= r then M.init(f, e) else M.update(f, e) end
      elseif e.id == 0x8B then
        if e.b32 ~= r then M.shelfInit(f, e) else M.shelfUpdate(f, e) end
      elseif e.id == 0x4D and e.flame32 ~= r then
        furnitureFlame(f, e)
      end
    end
  end
  -- CONTROL_1 while a piece slides (Link's own push walk runs on)
  local p = f.player
  if p.control32 and (p.control32.deleted or p.control32.f32action ~= 2) then p.control32 = nil end
  return false
end

return M
