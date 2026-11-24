-- Round 32: the figurine data (Carlov's gallery, Figurines.lua), copied
-- from the player's ROM at import time into figurines.bin.  Nothing here is
-- shipped: only the USA bus addresses of the tables.
--
--   gUnk_080FC3E4  137 x 8   {u32 bank, u16 flag, u8 unk_6 (stage / kind),
--                             u8 type (OBJECT_A2 palette, capsule colour)}
--   gFigurines     137 x 16  {pal ptr, gfx ptr, s32 size (< 0: LZ77), 0}
--   the palettes (9 banks read per figurine) and the gfx they point at,
--   kept as two raw regions (lo .. hi of every pointer).
local X = {}

X.FIG_FLAGS, X.FIG_TABLE, X.COUNT = 0x080FC3E4, 0x081281A8, 137

-- (idx, bytes) or nil
function X.build(rom)
  local palLo, palHi, gfxLo, gfxHi = math.huge, 0, math.huge, 0
  for k = 0, X.COUNT - 1 do
    local a = X.FIG_TABLE + 16 * k
    local pal, gfx, size = rom:u32(a), rom:u32(a + 4), rom:u32(a + 8)
    if size >= 0x80000000 then size = 0x100000000 - size end
    if pal >= 0x08000000 and gfx >= 0x08000000 then
      palLo, palHi = math.min(palLo, pal), math.max(palHi, pal + 9 * 32)
      gfxLo, gfxHi = math.min(gfxLo, gfx), math.max(gfxHi, gfx + size)
    end
  end
  if palHi == 0 or gfxHi == 0 or gfxHi - gfxLo > 0x100000 or palHi - palLo > 0x20000 then return nil end
  local parts, at, idx = {}, 0, {}
  local function add(name, lo, len)
    local s = rom:str(lo, len)
    idx[name] = { lo, at, #s }
    parts[#parts + 1] = s
    at = at + #s
  end
  add("flags", X.FIG_FLAGS, X.COUNT * 8)
  add("table", X.FIG_TABLE, X.COUNT * 16)
  add("pal", palLo, palHi - palLo)
  add("gfx", gfxLo, gfxHi - gfxLo)
  return idx, table.concat(parts)
end

function X.run(rom, store, manifest)
  local idx, bytes = X.build(rom)
  if not idx then manifest.r32 = false return end
  assert(store:write("figurines.bin", bytes))
  manifest.r32 = { figurines = idx }
end

return X
