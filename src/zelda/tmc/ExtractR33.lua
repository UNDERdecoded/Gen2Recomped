-- Round 33: tables copied from the player's ROM at import time into r33.bin.
-- Nothing here is shipped: only the USA bus addresses of the tables.
--
--   gWorldEvents  $70 x 20  WorldEvent {type, entity_idx, area, room,
--                           offsetX, offsetY, x, y, _c, _e (the world map
--                           position of the hint marker), ...}; the
--                           manifest's kinstones.world keeps only some
--                           fields; MapMenu's fusion markers and the local
--                           map hint (subtaskLocalMapHint.c) read _c / _e.
--   gUnk_080FF1D4 / gUnk_080FF204  worldEvent5.c: the BG3 overlay {gfx group,
--                           x, y} per event and the alpha ramp ($FFFF ends).
-- They are served through Ppu:table (manifest.r33[name] = {base, off, size}).
local X = {}

X.RANGES = {
  worldEvents = { 0x080FE320, 0x70 * 20 },
  we5Bg3 = { 0x080FF1D4, 0x30 },
  we5Alpha = { 0x080FF204, 0x40 },
  lightRayPal = { 0x085B4180, 0x80 }, -- gUnk_085B4180: lightRayManager.c sub_08057450's colours (4 x 16)
}
-- LIGHT_RAY_MANAGER ($01) rooms (USA room data): {area, room, property}.
-- GetCurrentRoomProperty(type): the zone list {mode, x, y, w, h} ($FF ends)
X.LIGHT_RAY_ROOMS = { { 0x00, 0x00, 17 }, { 0x20, 0x09, 8 } }
local AREA_TABLE = 0x080D50FC -- gAreaTable (Layout.gAreaTable)

function X.build(rom)
  local parts, at, idx = {}, 0, {}
  local ranges = {}
  for name, r in pairs(X.RANGES) do ranges[name] = r end
  for _, l in ipairs(X.LIGHT_RAY_ROOMS) do
    local ok, addr = pcall(function()
      local pt = rom:ptr(AREA_TABLE + 4 * l[1])
      local pp = pt and rom:ptr(pt + 4 * l[2])
      return pp and rom:ptr(pp + 4 * l[3])
    end)
    if ok and addr then ranges[string.format("lrm_%02X_%02X", l[1], l[2])] = { addr, 5 * 16 + 1 } end
  end
  for name, r in pairs(ranges) do
    local s = rom:str(r[1], r[2])
    if not s or #s ~= r[2] then return nil end
    idx[name] = { r[1], at, #s }
    parts[#parts + 1] = s
    at = at + #s
  end
  return idx, table.concat(parts)
end

function X.run(rom, store, manifest)
  local idx, bytes = X.build(rom)
  if not idx then manifest.r33 = false return end
  assert(store:write("r33.bin", bytes))
  manifest.r33 = idx
end

-- (Ppu:table's fallback) a reader for one of the ranges, or nil
function X.table(A, name)
  local m = A.manifest and A.manifest.r33
  local e = m and m[name]
  local blob
  if e then
    A.r33Blob = A.r33Blob or A.store:read("r33.bin") or false
    blob = A.r33Blob or nil
  elseif rawget(_G, "R26_DEV_ROM") then -- (dev scenes on an older cache read the ROM, as ExtractR26.tables)
    A.r33Dev = A.r33Dev or { X.build(rawget(_G, "R26_DEV_ROM")) }
    local i, b = A.r33Dev[1], A.r33Dev[2]
    e, blob = i and i[name], b
  end
  if not (e and blob) then return nil end
  return e, blob
end

return X
