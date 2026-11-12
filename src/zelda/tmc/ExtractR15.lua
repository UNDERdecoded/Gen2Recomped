-- Round 15: tables read from the player's ROM at import time (manifest.r15).
-- Nothing here is shipped; each entry names where it is read from (USA, BZME).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local Layout = require("src.zelda.tmc.Layout")

local ExtractR15 = {}

-- houseDoorExterior.c: a HOUSE_DOOR_EXT with type2 0 is the doors' manager;
-- its timer (EntityData type2 >> 8) indexes the room's property table
-- (GetCurrentRoomProperty) at a list of 12-byte door records: u16 x, u16 y
-- (room-relative, top-left of a 32x32 region), u8 layer, u8 condition
-- (2 = needs TATEKAKE_HOUSE), u8 type2, u8 type, u32 script ($FFFF x ends).
function ExtractR15.houseDoors(rom, manifest)
  local out = {}
  for area, info in pairs(manifest.areas or {}) do
    local propTable = type(info) == "table" and rom:ptr(Layout.gAreaTable + 4 * area)
    for r, room in pairs(type(info) == "table" and info.rooms or {}) do
      for _, l in pairs(room.entities or {}) do
        for _, d in ipairs(l) do
          if d.kind == 6 and d.id == 0x19 and band(d.paramB, 0xFF) == 0 and propTable then
            local idx = band(rshift(d.paramB, 8), 0xFF)
            local pp = rom:ptr(propTable + 4 * r)
            local lp = pp and rom:ptr(pp + 4 * idx)
            if lp then
              local list = {}
              for i = 0, 31 do
                local q = lp + 12 * i
                if not rom:valid(q + 11) or rom:u16(q) == 0xFFFF then break end
                list[#list + 1] = { x = rom:u16(q), y = rom:u16(q + 2), layer = rom:u8(q + 4), cond = rom:u8(q + 5),
                                    type2 = rom:u8(q + 6), type = rom:u8(q + 7), script = rom:u32(q + 8) }
              end
              out[area * 256 + r] = out[area * 256 + r] or {}
              out[area * 256 + r][idx] = list
            end
          end
        end
      end
    end
  end
  return out
end

function ExtractR15.run(rom, manifest)
  manifest.r15 = { houseDoors = ExtractR15.houseDoors(rom, manifest) }
end

return ExtractR15
