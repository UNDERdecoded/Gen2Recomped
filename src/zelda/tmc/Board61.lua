-- Round 61: BOARD $80 (src/object/board.c) -- the floating board in the Mayor's lake cabin's pool, where Minish
-- Link arrives from MinishPaths_MayorsCabin (its south exit lands at (0xB8, 0x48), on deep water).  The port drew
-- the board (ObjStatic: frameIndex = type) but ran none of its code, so nothing held Minish Link up there.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Board_Init: width / height = Board_Sizes[type] (read from the ROM: RomTables "Board61.SIZES"); the rect's
--     corner is (x - width / 2, y - height / 2); tilePos = its tile; collision layer 1; type 0 puts
--     SPECIAL_TILE_116 on the tile above it (layer 1).
--   * sub_08098BE8 (every frame): Minish Link inside the rect (sub_08098C30: (u32)(px - x) <= width and
--     (u32)(py - y) <= height), PlayerCanBeMoved and z 0 -> gPlayerState.field_0x14 = 1 (no fall / drown this
--     frame) and sub_0807AAF8(player, tilePos) (the board's tile goes into the path memory: RespawnPlayer puts
--     him back on it).
local bit = require("bit")
local band = bit.band

local M = {}
M.BOARD = 0x80
M.SPECIAL_TILE_116 = 0x4074
local SIZES = require("src.zelda.tmc.RomTables").t("Board61.SIZES") -- Board_Sizes

function M.rect(e)
  local s = SIZES[e.form or 0] or SIZES[0]
  local w, h = s.w, s.h
  return math.floor(e.x) - math.floor(w / 2), math.floor(e.y) - math.floor(h / 2), w, h
end

-- sub_08098C30
function M.inside(e, px, py)
  local x0, y0, w, h = M.rect(e)
  local dx, dy = math.floor(px) - x0, math.floor(py) - y0
  return dx >= 0 and dx <= w and dy >= 0 and dy <= h
end

-- PlayerCanBeMoved (the port's busy states) and z 0
local BUSY = { fall = true, portal = true, dead = true, climb = true, cart = true, hole = true, drown = true, itemget = true }
local function movable(p) return not BUSY[p.state] and not p.falling and not p.hidden and (p.z or 0) == 0 end

local function boards(f)
  local out = {}
  for _, e in ipairs(f.entities or {}) do
    if e.kind == 6 and e.id == M.BOARD and not e.deleted then out[#out + 1] = e end
  end
  return out
end

-- sub_08098BE8 for every board: true when one holds Minish Link up (field_0x14); its tile becomes the safe spot
function M.supports(f)
  local p = f.player
  if not p or not p.minish or not movable(p) then return false end
  for _, e in ipairs(boards(f)) do
    if M.inside(e, p.x, p.y) then
      local d = f._dungeon
      if d then
        local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
        d.safe = { x = tx * 16 + 8, y = ty * 16 + 8, layer = 1 } -- sub_0807AAF8
      end
      return true
    end
  end
  return false
end

-- Board_Init's tile (type 0: SPECIAL_TILE_116 one tile above)
function M.roomInit(f)
  local r = f.room
  if not r or not r.setTile then return end
  for _, e in ipairs(boards(f)) do
    if not e.board61 then
      e.board61 = true
      e.layer = 1
      if (e.form or 0) == 0 then
        local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16) - 1
        if ty >= 0 then r:setTile(1, tx, ty, M.SPECIAL_TILE_116) end
      end
    end
  end
end

return M
