-- The four baked files, parsed: buildings.bin (VXB8), relief.bin (VXL4),
-- regions.bin (VXR5) and signposts.bin (VXS3), plus layouts.lua.
--
-- Read exactly as Emerald 3DS's voxel_building.c / voxel_relief.c /
-- voxel_regions.c / voxel_sign.c read them; every table is keyed by the
-- 1-based layout id, the same number this engine keeps on a map def as
-- `layoutId`.  Bulk arrays (vertices, page texels) stay in the file string
-- and are read through Bin views when a map is built.

local V = ...
local Bin = V.require("Bin")

local Data = {}

local u8, s8, u16, s16, u32 = Bin.u8, Bin.s8, Bin.u16, Bin.s16, Bin.u32

-- --------------------------------------------------------------- loading --

-- The baked files live either in the mod's own generated/ folder (bake/bake.py's
-- default) or in the save directory's e3ds_voxel/ folder.
local function readBaked(name)
  local blob = V.mod:read("generated/" .. name)
  if blob then return blob end
  if love and love.filesystem and love.filesystem.getInfo("e3ds_voxel/" .. name) then
    return love.filesystem.read("e3ds_voxel/" .. name)
  end
  return nil
end
Data.readBaked = readBaked

-- ------------------------------------------------------------ regions.bin --

local function parseRegions(s)
  if not s or Bin.tag(s, 0) ~= "VXR5" then return nil, "regions.bin missing or not VXR5" end
  local out = {}
  for i = 0, u16(s, 4) - 1 do
    local e = 8 + 12 * i
    out[u16(s, e)] = { w = u16(s, e + 2), h = u16(s, e + 4), offset = u32(s, e + 8) }
  end
  return { s = s, layouts = out }
end

Data.ROLE = { FLOOR = 0, WATER = 1, LEDGE = 2, STAIR = 3, WALL = 4, TREE = 5, PROP = 6,
              SHELF = 7, FENCE = 8, CLIFF = 9, SIGNPOST = 10 }

function Data.roleAt(layout, x, y)
  local r = Data.regions and Data.regions.layouts[layout]
  if not r or x < 0 or y < 0 or x >= r.w or y >= r.h then return 0 end
  return u8(Data.regions.s, r.offset + y * r.w + x)
end

-- ---------------------------------------------------------- signposts.bin --

local function signKey(layout, x, y) return layout * 1048576 + y * 1024 + x end

local function parseSigns(s)
  if not s or Bin.tag(s, 0) ~= "VXS3" then return nil, "signposts.bin missing or not VXS3" end
  local byKey, heads = {}, {}
  for i = 0, u32(s, 4) - 1 do
    local o = 8 + 74 * i
    local rec = { layout = u16(s, o), x = u16(s, o + 2), y = u16(s, o + 4),
                  rows = {}, head = {}, headGround = u16(s, o + 70), ground = u16(s, o + 72) }
    local hasHead = false
    for r = 0, 15 do
      rec.rows[r] = u16(s, o + 6 + r * 2)
      rec.head[r] = u16(s, o + 38 + r * 2)
      if rec.head[r] ~= 0 then hasHead = true end
    end
    rec.hasHead = hasHead
    byKey[signKey(rec.layout, rec.x, rec.y)] = rec
    if hasHead and rec.y > 0 then heads[signKey(rec.layout, rec.x, rec.y - 1)] = rec end
  end
  return { byKey = byKey, heads = heads }
end

function Data.signAt(layout, x, y)
  return Data.signs and Data.signs.byKey[signKey(layout, x, y)]
end

-- the sign whose head (a lamp's lantern) is drawn in this cell
function Data.signHeadAt(layout, x, y)
  return Data.signs and Data.signs.heads[signKey(layout, x, y)]
end

-- ------------------------------------------------------------- relief.bin --

local function parseRelief(s)
  if not s or Bin.tag(s, 0) ~= "VXL4" then return nil, "relief.bin missing or not VXL4" end
  if u16(s, 6) ~= 5 then return nil, "relief.bin lattice side is not 5" end
  local layouts = {}
  for i = 0, u16(s, 4) - 1 do
    local r = 8 + 14 * i
    local id, cells, ww, hw = u16(s, r), u16(s, r + 2), u16(s, r + 4), u16(s, r + 6)
    local offset, base = u32(s, r + 8), s16(s, r + 12)
    -- width bit 15: a level map (v0.4.0; dev writes it no more), bit 14:
    -- wide cells (s16 heights), bits 10-13: the south seam's ease
    local wide = math.floor(ww / 16384) % 2 == 1
    local L = { id = id, w = ww % 1024, h = hw % 1024, level = ww >= 32768, wide = wide,
                ease = math.floor(ww / 1024) % 16,
                belt = math.floor(hw / 1024) % 16, unit = (math.floor(hw / 16384) % 2 == 1) and 2 or 1,
                drawn = hw >= 32768, base = base / 16, cells = {} }
    local stride = wide and 52 or 27
    for k = 0, cells - 1 do
      local o = offset + k * stride
      L.cells[u8(s, o + 1) * 256 + u8(s, o)] = o + 2
    end
    -- the rows the ease is spread over: six a level, at most half the map
    -- (voxel_relief.c EaseRows)
    L.easeRows = math.min(math.floor((6 * 8 * L.ease + 15) / 16), math.floor(L.h / 2))
    layouts[id] = L
  end
  -- the cut-tile table: variants (a metatile with its background pixels
  -- cleared, atlas id 1152 + i) and the cut cells that use them
  local cuts, cutVariants = {}, {}
  if Bin.tag(s, #s - 4) == "CUTS" then
    local t = u32(s, #s - 8)
    local variants, cutCells = u16(s, t), u16(s, t + 2)
    for k = 0, variants - 1 do
      local v = t + 4 + k * 36
      local rows = {}
      for r = 0, 15 do rows[r] = u16(s, v + 4 + r * 2) end
      cutVariants[k] = { layout = u16(s, v), metatile = u16(s, v + 2), rows = rows }
    end
    local o = t + 4 + variants * 36
    for k = 0, cutCells - 1 do
      local c = o + k * 14
      cuts[u16(s, c) * 65536 + u8(s, c + 3) * 256 + u8(s, c + 2)] = {
        variant = u16(s, c + 4), foot = s16(s, c + 6) / 16, ground = u16(s, c + 8),
        wall = u16(s, c + 10), sides = u8(s, c + 12), flags = u8(s, c + 13) }
    end
  end
  return { s = s, layouts = layouts, cuts = cuts, cutVariants = cutVariants }
end

-- Layouts whose relief this mod stands up instead of Emerald 3DS's (set by
-- lib/Generic.lua when Emerald 3DS's is not yet on terraces: no point a
-- level over its base -- Sootopolis' crater).
Data.override = {}

function Data.reliefLayout(layout)
  if Data.override[layout] == true then return nil end
  return Data.relief and Data.relief.layouts[layout]
end

-- How high Emerald 3DS's relief reaches on a layout, pixels (0 without).
function Data.reliefTop(layout)
  local L = Data.relief and Data.relief.layouts[layout]
  if not L then return 0 end
  if L.top then return L.top end
  local s, top = Data.relief.s, 0
  for _, o in pairs(L.cells) do
    for i = 0, 24 do
      local h = L.wide and s16(s, o + 2 * i) or s8(s, o + i) * L.unit
      if math.abs(h) > top then top = math.abs(h) end
    end
  end
  L.top = top
  return top
end

-- The 25 heights (and depths) of a lifted cell, in PIXELS, or nil.
local gridCache = setmetatable({}, { __mode = "k" })
-- The lattices this mod made for maps Emerald 3DS has no relief for
-- (lib/Generic.lua), by layout: y * 256 + x -> { heights, depths }.
Data.generic = {}

function Data.reliefCell(layout, x, y)
  local L = Data.relief and Data.override[layout] ~= true and Data.relief.layouts[layout]
  if not L then
    local G = Data.generic[layout]
    local c = G and x >= 0 and y >= 0 and x <= 255 and G[y * 256 + x]
    if c then return c[1], c[2] end
    return nil
  end
  if x < 0 or y < 0 or x > 255 or y > 255 then return nil end
  local o = L.cells[y * 256 + x]
  if not o then return nil end
  local cache = gridCache[L]
  if not cache then cache = {}; gridCache[L] = cache end
  local hit = cache[o]
  if hit then return hit[1], hit[2] end
  local s, g, d = Data.relief.s, {}, {}
  for i = 0, 24 do
    g[i] = L.wide and s16(s, o + 2 * i) or s8(s, o + i) * L.unit
    d[i] = L.level and 0 or g[i]
  end
  cache[o] = { g, d }
  return g, d
end

-- VoxelRelief_StretchZ: a map whose south seam is eased has its last rows
-- drawn longer, and everything past them moved `add` tiles south, so its
-- edge meets the next map's.  z in the map's own cells; unchanged without.
function Data.stretchZ(layout, z)
  local L = Data.relief and Data.relief.layouts[layout]
  if not L or L.ease == 0 or L.easeRows == 0 then return z end
  local add = 8 * L.ease / 16
  local to = L.h - add
  local from = to - L.easeRows
  if z <= from then return z end
  if z >= to then return z + add end
  return from + (z - from) * (to - from + add) / (to - from)
end

function Data.cutAt(layout, x, y)
  if Data.override[layout] == true then return nil end
  return Data.relief and Data.relief.cuts[layout * 65536 + y * 256 + x]
end

-- ---------------------------------------------------------- buildings.bin --

local function parseBuildings(s)
  if not s or Bin.tag(s, 0) ~= "VXB8" then return nil, "buildings.bin missing or not VXB8" end
  local nPages, nModels, nPageModels = u16(s, 4), u16(s, 6), u16(s, 8)
  local nPlacements, heightBytes, nMasks = u16(s, 10), u16(s, 12), u16(s, 14)
  local nVertices, nVariants, nDecks = u32(s, 16), u16(s, 20), u16(s, 22)
  local o = 24
  local B = { s = s, pages = {}, models = {}, pageModels = {}, placements = {}, byLayout = {},
              variants = {}, decks = {} }
  for i = 0, nPages - 1 do
    local hw = u16(s, o + 2)
    B.pages[i] = { w = u16(s, o), h = hw % 32768, glow = hw >= 32768, offset = u32(s, o + 4) }
    o = o + 8
  end
  for i = 0, nModels - 1 do
    local vc = u32(s, o + 8)
    B.models[i] = { w = u8(s, o), h = u8(s, o + 1), ground = u16(s, o + 2),
                    first = u32(s, o + 4), count = vc % 2147483648, heights = u32(s, o + 12) }
    o = o + 16
  end
  for i = 0, nPageModels - 1 do
    B.pageModels[i] = { model = u16(s, o), page = u16(s, o + 2), ox = s16(s, o + 4), oy = s16(s, o + 6) }
    o = o + 8
  end
  for i = 0, nPlacements - 1 do
    local p = { layout = u16(s, o), pageModel = u16(s, o + 2), x = u16(s, o + 4), y = u16(s, o + 6),
                ground = u16(s, o + 8), extraCount = u16(s, o + 10), extraFirst = u32(s, o + 12) }
    B.placements[i] = p
    local list = B.byLayout[p.layout]
    if not list then list = {}; B.byLayout[p.layout] = list end
    list[#list + 1] = p
    o = o + 16
  end
  B.heightsAt = o
  o = o + heightBytes + heightBytes % 2
  o = o + heightBytes * 2           -- footprints (shadows only)
  o = o + nMasks * 32               -- masks (shadows only)
  B.quartersAt = o
  o = o + heightBytes + heightBytes % 2
  for i = 0, nVariants - 1 do
    B.variants[i] = { layout = u16(s, o), metatile = u16(s, o + 2), quarters = u8(s, o + 4) }
    o = o + 6
  end
  for i = 0, nDecks - 1 do
    local d = { layout = u16(s, o), x = u8(s, o + 2), y = u8(s, o + 3), top = u8(s, o + 4),
                bottom = u8(s, o + 5), elevation = u8(s, o + 6) }
    B.decks[d.layout * 65536 + d.y * 256 + d.x] = d
    o = o + 8
  end
  o = o + (4 - o % 4) % 4
  B.vertexBase, B.vertexCount = o, nVertices
  B.verts = Bin.floats(s, o)
  -- per layout, the cell -> (placement, height index) owner grid: the first
  -- placement in file order that owns the cell (a height byte other than 255)
  B.owner = {}
  return B
end

function Data.placements(layout)
  return Data.buildings and Data.buildings.byLayout[layout]
end

local function ownerGrid(layout)
  local B = Data.buildings
  local grid = B.owner[layout]
  if grid then return grid end
  grid = {}
  for _, p in ipairs(B.byLayout[layout] or {}) do
    local m = B.models[B.pageModels[p.pageModel].model]
    for cy = 0, m.h - 1 do
      for cx = 0, m.w - 1 do
        local k = m.heights + cy * m.w + cx
        local key = (p.y + cy) * 1024 + p.x + cx
        if not grid[key] and u8(B.s, B.heightsAt + k) ~= 255 then
          grid[key] = { p = p, k = k }
        end
      end
    end
  end
  B.owner[layout] = grid
  return grid
end

-- VoxelBuildings_CellAt: the ground metatile to draw flat under a model's
-- cell (OWN_GROUND resolved against the ground variants), and its top.
-- `own` is the cell's own metatile; `variantFits(v)` says whether variant v
-- is drawn from this map's tilesets.
function Data.buildingCell(layout, x, y, own, variantFits)
  local B = Data.buildings
  if not B then return nil end
  local hit = ownerGrid(layout)[y * 1024 + x]
  if not hit then return nil end
  local ground = hit.p.ground
  if ground == 0xFFFF then
    ground = own
    local quarters = u8(B.s, B.quartersAt + hit.k)
    if quarters ~= 0 then
      for v = 0, math.min(127, #B.variants) do
        local var = B.variants[v]
        if var and var.metatile == own and var.quarters == quarters and variantFits(var) then
          ground = 1024 + v
          break
        end
      end
    end
  end
  return ground, u8(B.s, B.heightsAt + hit.k) / 16
end

function Data.deckAt(layout, x, y)
  return Data.buildings and Data.buildings.decks[layout * 65536 + y * 256 + x]
end

-- A building page as an ImageData, cached by page number.
local pageImages = {}
function Data.pageImage(page)
  local hit = pageImages[page]
  if hit then return hit end
  local P = Data.buildings.pages[page]
  local data = Bin.decodePica(Bin.u16s(Data.buildings.s, P.offset), P.w, P.h)
  local ok, img = pcall(love.graphics.newImage, data)
  if not ok then return nil end
  img:setFilter("nearest", "nearest")
  img:setWrap("clamp", "clamp")
  pageImages[page] = img
  return img
end

-- --------------------------------------------------------------- the lot --

function Data.load()
  if Data.ready ~= nil then return Data.ready, Data.why end
  local missing = {}
  local function take(name, parse, field)
    local blob = readBaked(name)
    if not blob then missing[#missing + 1] = name; return end
    local value, err = parse(blob)
    if not value then missing[#missing + 1] = err; return end
    Data[field] = value
  end
  take("regions.bin", parseRegions, "regions")
  take("signposts.bin", parseSigns, "signs")
  take("relief.bin", parseRelief, "relief")
  take("buildings.bin", parseBuildings, "buildings")
  local layouts = readBaked("layouts.lua")
  if layouts then
    local chunk = load(layouts, "@generated/layouts.lua")
    local ok, value = pcall(chunk or error)
    Data.layouts = ok and value or nil
  end
  if not Data.layouts then missing[#missing + 1] = "layouts.lua" end
  Data.ready = #missing == 0
  Data.why = Data.ready and nil or table.concat(missing, ", ")
  return Data.ready, Data.why
end

-- Forget everything loaded, so the next Data.load reads the files again
-- (lib/BakeJob.lua, once an in-game bake has written e3ds_voxel/).
function Data.reset()
  Data.ready, Data.why = nil, nil
  Data.regions, Data.signs, Data.relief, Data.buildings, Data.layouts = nil, nil, nil, nil, nil
  pageImages = {}
end

return Data
