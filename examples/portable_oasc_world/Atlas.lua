-- Pure pixel decoding of the public contract; no engine modules or GPU calls.
local A = {}
local function word(s, at)
  if type(s) ~= "string" or at < 1 or at + 1 > #s then
    return nil
  end
  return s:byte(at) + s:byte(at + 1) * 256
end
local function bank(t, id, split)
  if id < split then
    return t.primary, id
  end
  return t.secondary, id - split
end
function A.equal(a, b)
  if not a or not b or a.id ~= b.id or a.graphicsState ~= b.graphicsState then
    return false
  end
  for _, k in ipairs({ "tilesInPrimary", "metatilesInPrimary", "palettesInPrimary", "metatileLayers" }) do
    if a.layout[k] ~= b.layout[k] then
      return false
    end
  end
  for _, name in ipairs({ "primary", "secondary" }) do
    local x, y = a[name], b[name]
    for _, k in ipairs({ "tiles4bpp", "metatileEntriesLE16", "layerTypes" }) do
      if x[k] ~= y[k] then
        return false
      end
    end
    for p = 1, 16 do
      for c = 1, 16 do
        for channel = 1, 3 do
          if x.palettes[p][c][channel] ~= y.palettes[p][c][channel] then
            return false
          end
        end
      end
    end
  end
  return true
end
function A.decode(t, mid)
  if
    t.version ~= 1
    or t.graphicsState ~= "base"
    or type(mid) ~= "number"
    or mid % 1 ~= 0
    or mid < 0
    or mid > 1023
  then
    return nil, "unsupported metatile"
  end
  local record, index = bank(t, mid, t.layout.metatilesInPrimary)
  local layer = record.layerTypes:byte(index + 1)
  if layer == nil or layer > 2 then
    return nil, "unsupported metatile layer"
  end
  local bottom, top = {}, {}
  for k = 0, 7 do
    local entry = word(record.metatileEntriesLE16, index * 16 + k * 2 + 1)
    if not entry then
      return nil, "metatile entries unavailable"
    end
    local tid = entry % 1024
    local tiles, localId = bank(t, tid, t.layout.tilesInPrimary)
    if (localId + 1) * 32 > #tiles.tiles4bpp then
      return nil, "tile pixels unavailable"
    end
    local paletteId = math.floor(entry / 4096)
    local palettes = paletteId < t.layout.palettesInPrimary and t.primary.palettes or t.secondary.palettes
    local palette = palettes[paletteId + 1]
    local flipX, flipY = math.floor(entry / 1024) % 2 == 1, math.floor(entry / 2048) % 2 == 1
    local out, quadrant = k < 4 and bottom or top, k % 4
    for y = 0, 7 do
      for x = 0, 7 do
        local sx, sy = flipX and 7 - x or x, flipY and 7 - y or y
        local byte = tiles.tiles4bpp:byte(localId * 32 + sy * 4 + math.floor(sx / 2) + 1)
        local colorId = sx % 2 == 0 and byte % 16 or math.floor(byte / 16)
        local color = palette[colorId + 1]
        local offset = (math.floor(quadrant / 2) * 8 + y) * 16 + (quadrant % 2) * 8 + x + 1
        out[offset] = colorId == 0 and string.char(0, 0, 0, 0)
          or string.char(color[1], color[2], color[3], 255)
      end
    end
  end
  local under, over, middle = {}, {}, {}
  local transparent = string.char(0, 0, 0, 0)
  for i = 1, 256 do
    under[i] = layer == 1 and top[i]:byte(4) ~= 0 and top[i] or bottom[i]
    over[i] = layer == 1 and transparent or top[i]
    middle[i] = layer == 0 and bottom[i] or layer == 1 and top[i] or transparent
  end
  return { under = table.concat(under), over = table.concat(over), middle = table.concat(middle) }
end
return A
