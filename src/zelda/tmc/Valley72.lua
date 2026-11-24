-- Round 72: the Royal Valley (area $09): sub_StateChange_RoyalValley_Main and the forest maze
-- (sub_StateChange_RoyalValley_ForestMaze, $09:01).  Neither was ported: the valley's graveyard gate stood open
-- (its four closed-gate tiles were never laid), the crow / key lists never loaded, and the maze's edges led nowhere
-- (no exit, no room beside it), so the valley's upper half (the graveyard, Dampe) could not be reached; Dampe was
-- missing from his house (sub_StateChange_HouseInteriors2_Dampe).
--
-- CARTRIDGE BEHAVIOUR (src/roomInit.c, src/movement.c, src/playerUtils.c, src/gameUtils.c):
--   * sub_StateChange_RoyalValley_Main: HAKA_KEY_LOST clear -> with ITEM_QST_GRAVEYARD_KEY == 1 the lists
--     gUnk_080D90C8 + gUnk_080D9108 (the crow scene); HAKA_KEY_LOST set and HAKA_KEY_FOUND clear -> gUnk_080D9108.
--     Key != 2 -> gUnk_080D9098 and the closed gate: TILE_TYPE_378 .. 381 at (14, 22), (15, 22), (14, 23),
--     (15, 23) on the bottom layer.  SPECIAL_TILE_114 at (7, 41) and (7, 49).  MAZE_CLEAR and an arrival at
--     ($78, $278) -> SFX_SECRET; MAZE_CLEAR cleared.
--   * sub_StateChange_RoyalValley_ForestMaze: gArea.unk_0c_0 = 1 (the fake scroll: sub_0807BEEC gives the same room
--     for every edge, sub_0807BD14 moves the room's map_x / map_y one room's size that way), then sub_0804C128:
--     sub_080AF250(0) (the room's exits = gExitList_RoyalValley_ForestMaze).  Entered by a scroll: unk_0c_1 == 0 ->
--     (unk_0c_4 == 0 -> unk_0c_1 = 1); else the scroll direction == gUnk_080D9338[unk_0c_1] -> unk_0c_1 + 1, else 0.
--     unk_0c_1 == 0 -> the direction == gUnk_080D9340[unk_0c_4] -> unk_0c_4 + 1, else unk_0c_4 = 0.  unk_0c_1 == 6
--     -> sub_080AF250(1) (exits = gUnk_08135190), MAZE_CLEAR, the sign, unk_0c_1 = 0.  unk_0c_4 == 6 -> the exits,
--     HAKA_01_T0 clear -> TILE_TYPE_115 at (7, 4), LoadRoomTileEntities(gUnk_080D9328) (the secret chest),
--     MAZE_CLEAR, unk_0c_4 = 0.  Not by a scroll (sub_0804C258): unk_0c_1 = 1, unk_0c_4 = 0; start_anim 4 (in from
--     the north) -> unk_0c_1 = 7 and the way-out exits.  sub_0804C290: unk_0c_1 != 0 -> SetTileType(
--     gUnk_080D9348[unk_0c_1]) (the sign of that step; its SIGN tile entity holds the text).
-- The tables, the way-out exit list and the secret chest's tile entity are read from the player's ROM (RomTables
-- "Valley72.*"); the entity lists by address from the importer's entity region.
-- SIMPLIFIED: AR_HAS_NO_ENEMIES (the maze's area flag) is not applied; UpdateFakeScroll's kept entities are
-- reloaded with the room instead; sub_08059278 (the light manager's first run) waits for its own update.
local M = {}

M.AREA, M.MAIN, M.MAZE = 0x09, 0x00, 0x01
M.ITEM_GRAVEYARD_KEY = 0x3C
M.HAKA_KEY_LOST, M.HAKA_KEY_FOUND, M.MAZE_CLEAR = 0x20, 0x21, 0x62 -- global
M.HAKA_01_T0 = 0x5C -- local (bank 3)
M.SFX_SECRET = 0x73
M.TILE_TYPE_115, M.SPECIAL_TILE_114 = 0x73, 0x4072
M.GATE = { { 0x17A, 14, 22 }, { 0x17B, 15, 22 }, { 0x17C, 14, 23 }, { 0x17D, 15, 23 } } -- TILE_TYPE_378 .. 381
M.LIST_CROW, M.LIST_KEY, M.LIST_GATE = 0x080D90C8, 0x080D9108, 0x080D9098

local RT = require("src.zelda.tmc.RomTables")
local DIR1 = RT.t("Valley72.MAZE_DIR")   -- gUnk_080D9338 (u8, from 0)
local DIR2 = RT.t("Valley72.MAZE_DIR2")  -- gUnk_080D9340 (u8, from 0)
local SIGN = RT.t("Valley72.MAZE_SIGN")  -- gUnk_080D9348 ({type, pos}, from 0)
local OUT = RT.t("Valley72.MAZE_OUT")    -- gUnk_08135190 (Transition list)
local CHEST = RT.t("Valley72.MAZE_CHEST") -- gUnk_080D9328 (TileEntity)
M.tables = { DIR1 = DIR1, DIR2 = DIR2, SIGN = SIGN, OUT = OUT, CHEST = CHEST }

local function at(f, room) return f.room and f.room.area == M.AREA and f.room.room == room end

-- sub_080AF250: the maze room's exit list (0 the room's own, 1 the way out)
local function setExits(f, out)
  local r = f.room
  r.exits0 = r.exits0 or r.exits
  if out then
    local t = {}
    for i, e in ipairs(M.tables.OUT) do local c = {} for k, v in pairs(e) do c[k] = v end t[i] = c end
    r.exits = t
  else r.exits = r.exits0 end
end

-- sub_0804C290: the sign of step unk_0c_1
local function sign(f, st)
  local s = st.c1 ~= 0 and M.tables.SIGN[st.c1]
  if s then f:objects():setTileType(1, s.pos % 64, math.floor(s.pos / 64), s.type) end
end

-- sub_0804C128 (+ sub_0804C258) on the maze room's init; dir = the scroll direction (0 N 1 E 2 S 3 W) or nil
function M.mazeInit(f, dir, startAnim)
  local st = f.maze72 or { c1 = 0, c4 = 0, ox = 0, oy = 0 }
  f.maze72 = st
  st.on = true -- gArea.unk_0c_0
  setExits(f, false)
  if dir then
    if st.c1 == 0 then
      if st.c4 == 0 then st.c1 = 1 end
    elseif dir == M.tables.DIR1[st.c1] then st.c1 = st.c1 + 1
    else st.c1 = 0 end
    if st.c1 == 0 then
      if dir == M.tables.DIR2[st.c4] then st.c4 = st.c4 + 1; st.c1 = 0 else st.c4 = 0 end
    end
    if st.c1 == 6 then
      setExits(f, true)
      f:setFlag("global", M.MAZE_CLEAR, true)
      sign(f, st)
      st.c1 = 0
      return st
    end
    if st.c4 == 6 then
      setExits(f, true)
      if not f:flag("local", M.HAKA_01_T0) then f:objects():setTileType(1, 7, 4, M.TILE_TYPE_115) end
      local te = f.room.tileEntities or {}
      local c = M.tables.CHEST
      if c and c.type then te[#te + 1] = { type = c.type, flag = c.flag, a = c.a, b = c.b, pos = c.pos, c = c.c, d = c.d } end
      f.room.tileEntities = te
      f:setFlag("global", M.MAZE_CLEAR, true)
      sign(f, st)
      st.c4 = 0
      return st
    end
  else
    st.c1, st.c4, st.ox, st.oy = 1, 0, 0, 0
    if startAnim == 4 then st.c1 = 7; setExits(f, true) end
  end
  sign(f, st)
  return st
end

-- sub_StateChange_RoyalValley_Main
function M.mainInit(f)
  local key = f:inventory(M.ITEM_GRAVEYARD_KEY) or 0
  if not f:flag("global", M.HAKA_KEY_LOST) then
    if key == 1 then f:loadEntityList(M.LIST_CROW); f:loadEntityList(M.LIST_KEY) end
  elseif not f:flag("global", M.HAKA_KEY_FOUND) then f:loadEntityList(M.LIST_KEY) end
  if key ~= 2 then
    f:loadEntityList(M.LIST_GATE)
    for _, g in ipairs(M.GATE) do f:objects():setTileType(1, g[2], g[3], g[1]) end
  end
  f.room:setTile(1, 7, 41, M.SPECIAL_TILE_114)
  f.room:setTile(1, 7, 49, M.SPECIAL_TILE_114)
  if f:flag("global", M.MAZE_CLEAR) then
    local e = f.entry
    if e and e.x == 0x78 and e.y == 0x278 then f:sound(M.SFX_SECRET) end
  end
  f:setFlag("global", M.MAZE_CLEAR, false)
end

-- sub_StateChange_HouseInteriors2_Dampe ($22:12): Dampe (gUnk_080F2FD4) until he has talked, or once the key is
-- back with him (2)
M.DAMPE_AREA, M.DAMPE_ROOM, M.DANPEI_TALK1ST, M.LIST_DAMPE = 0x22, 0x12, 0x69, 0x080F2FD4
function M.dampeInit(f)
  if not f:flag("local", M.DANPEI_TALK1ST) or (f:inventory(M.ITEM_GRAVEYARD_KEY) or 0) > 1 then f:loadEntityList(M.LIST_DAMPE) end
end

-- one line in Field:spawnRoomEntities
function M.roomInit(f)
  if f.room.area == M.DAMPE_AREA and f.room.room == M.DAMPE_ROOM then M.dampeInit(f) end
  if f.room.area ~= M.AREA then f.maze72 = nil return end
  if at(f, M.MAIN) then
    if f.maze72 then f.maze72.on = false end
    M.mainInit(f)
  elseif at(f, M.MAZE) then
    local tr = f.transition
    local dir = tr and tr.exit and tr.exit.maze72dir
    local st = M.mazeInit(f, dir, tr and tr.facing or (f.entry and f.entry.facing))
    -- sub_0807BD14: the room info moved one room's size the way Link scrolled
    if dir then
      if dir == 0 then st.oy = st.oy - f.room.height elseif dir == 2 then st.oy = st.oy + f.room.height
      elseif dir == 1 then st.ox = st.ox + f.room.width else st.ox = st.ox - f.room.width end
    end
    f.room.x, f.room.y = f.room.x + st.ox, f.room.y + st.oy
  end
end

-- one line in Field:adjacentRoom: sub_0807BEEC with gArea.unk_0c_0 -- every edge without a border exit scrolls
-- into the maze room again (Link comes in on the opposite edge)
function M.adjacent(f, dir)
  local st = f.maze72
  if not (st and st.on and at(f, M.MAZE)) then return nil end
  local p, r = f.player, f.room
  local ex, ey = math.floor(p.x), math.floor(p.y)
  if dir == 0 then ey = r.height elseif dir == 2 then ey = 0 elseif dir == 1 then ex = 0 else ex = r.width end
  return { warpType = 0, area = r.area, room = r.room, endX = ex, endY = ey, shape = 0, facing = dir * 2, scroll = true,
           maze72dir = dir }
end

return M
