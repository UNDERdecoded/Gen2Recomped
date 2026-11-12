-- Importer step for the pause map pages (round 5, Layout.R5_EXTRACT).
--
-- gDungeonLayouts (common.c) -> per dungeon, per floor, DungeonLayout
-- {area, room, unk_2, unk_3, mapDataOffset}; DrawDungeonFeatures copies
-- the room's 2-bit-per-tile outline from gMapData + mapDataOffset.  The
-- outlines go into dmap.bin; the layout lists into manifest.dungeonMaps.
-- Runs in the import worker: no love.graphics here.

local Layout = require("src.zelda.tmc.Layout")

local M = {}

M.gDungeonLayouts = 0x080C9C50        -- 7 pointers (None, DWS, CoF, FoW, ToD, PoW, DHC)
M.gDungeonFloorMetadatas = 0x080C9C6C -- 16 x {numFloors, highestFloor, unk_2, pad}
M.DUNGEONS = 7

function M.extract(rom, store, manifest)
  local parts, at, out = {}, 0, {}
  for d = 1, M.DUNGEONS - 1 do
    local floors = rom:ptr(M.gDungeonLayouts + 4 * d)
    local n = rom:u8(M.gDungeonFloorMetadatas + 4 * d)
    local list = {}
    for fl = 0, n - 1 do
      local lp = floors and rom:ptr(floors + 4 * fl)
      local rooms = {}
      for i = 0, 63 do
        if not lp then break end
        local q = lp + 8 * i
        local area = rom:u8(q)
        if area == 0 then break end
        local room = rom:u8(q + 1)
        local off = rom:u32(q + 4)
        local hp = rom:ptr(Layout.gAreaRoomHeaders + 4 * area)
        local len = 0
        if hp then
          local w, h = rom:u16(hp + 10 * room + 4), rom:u16(hp + 10 * room + 6)
          len = math.floor((math.floor(w / 16) + 3) / 4) * math.floor(h / 16)
        end
        local bytes = len > 0 and rom:str(Layout.gMapData + off, len) or ""
        rooms[#rooms + 1] = { area, room, rom:u8(q + 2), rom:u8(q + 3), at, #bytes }
        parts[#parts + 1] = bytes
        at = at + #bytes
      end
      list[fl] = rooms
    end
    out[d] = list
  end
  assert(store:write("dmap.bin", table.concat(parts)))
  manifest.dungeonMaps = out
end

return M
