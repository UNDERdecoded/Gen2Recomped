-- Port of 3ds_port/scripts/gen_voxel_sign_masks.py: the signpost mask
-- sidecar.
--
-- OUTPUT  3ds_port/romfs/voxel/signposts.bin  (VXS3)

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local floor = math.floor
local tree = S.tree
local voxel_cells = S.import("voxel_cells")
local voxel_art = S.import("voxel_art")
local vsm = S.import("voxel_sign_mask")
local event_board_masks, head_mask, metatile_mask = vsm.event_board_masks, vsm.head_mask, vsm.metatile_mask
local pk = voxel_cells.pk

local OUT = "3ds_port/romfs/voxel/signposts.bin"

-- The ground under a sign's head: the head cell's drawing without it.
function M.head_ground(layout, pair, x, y)
  local own = pair:layer_pixels(layout:metatile(x, y), 0)
  local counts = py.dict()
  for dy = -1, 1 do
    for dx = -1, 1 do
      local nx, ny = x + dx, y + dy
      if not ((dx == 0 and (dy == 0 or dy == 1)) or layout:off_map(nx, ny) or layout:blocked(nx, ny)) then
        local m = layout:metatile(nx, ny)
        if next(pair:layer_pixels(m, 1)) == nil then
          if voxel_art.same(pair:layer_pixels(m, 0), own) then return m end
          counts:set(m, counts:get(m, 0) + 1)
        end
      end
    end
  end
  if counts:len() > 0 then
    return py.max_by(counts.keys, function(k) return counts.vals[k] end)
  end
  if not layout:off_map(x, y + 2) then return layout:metatile(x, y + 2) end
  return 0
end

-- The metatile the sign's own cell is laid with under it.
function M.cell_ground(layout, pair, x, y, rows)
  local own = pair:layer_pixels(layout:metatile(x, y), 0)
  local seen = {}
  for p, c in pairs(own) do
    local px, pyy = p % 16, floor(p / 16)
    if band(rshift(rows[pyy + 1], px), 1) == 0 then seen[p] = c end
  end
  local south = nil
  if not layout:off_map(x, y + 1) then south = layout:metatile(x, y + 1) end
  local found = py.dict()
  for dy = -1, 1 do
    for dx = -1, 1 do
      local nx, ny = x + dx, y + dy
      if not ((dx == 0 and dy == 0) or layout:off_map(nx, ny) or layout:blocked(nx, ny)) then
        local m = layout:metatile(nx, ny)
        if not (next(pair:layer_pixels(m, 1)) ~= nil or layout:role_at(nx, ny) == "signpost") then
          found:set(m, found:get(m, 0) + 1)
        end
      end
    end
  end
  if south ~= nil then found:setdefault(south, 0) end

  -- its four neighbours' lower layers: {pixels, dx, dy}
  local seams = {}
  for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
    local nx, ny = x + d[1], y + d[2]
    if not layout:off_map(nx, ny) then
      seams[#seams + 1] = { pair:layer_pixels(layout:metatile(nx, ny), 0), d[1], d[2] }
    end
  end

  local function seam(lower)
    local n = 0
    for _, s in ipairs(seams) do
      local other, dx, dy = s[1], s[2], s[3]
      for k = 0, 15 do
        local a, b
        if dx ~= 0 then
          if dx > 0 then a, b = k * 16 + 15, k * 16 + 0 else a, b = k * 16 + 0, k * 16 + 15 end
        else
          if dy > 0 then a, b = 15 * 16 + k, 0 * 16 + k else a, b = 0 * 16 + k, 15 * 16 + k end
        end
        if lower[a] ~= nil and lower[a] == other[b] then n = n + 1 end
      end
    end
    return n
  end

  local function score(m)
    local lower = pair:layer_pixels(m, 0)
    local match = 0
    for p, c in pairs(seen) do
      if lower[p] == c then match = match + 1 end
    end
    return { match, seam(lower), found.vals[m], m == south }
  end

  if found:len() == 0 then return 0 end
  return py.max_by(found.keys, score)
end

-- A sign's head in a blocked cell, when that cell's upper layer is the
-- head and nothing else.
function M.blocked_head(pair, head, north)
  for p in pairs(pair:layer_pixels(north, 1)) do
    local px, pyy = p % 16, floor(p / 16)
    if band(rshift(head[pyy + 1], px), 1) == 0 then return false end
  end
  return true
end

-- rows, head, the head cell's ground metatile, the sign cell's
function M.sign_record(layout, pair, x, y)
  local rows = metatile_mask(pair, layout, x, y)
  local ground = M.cell_ground(layout, pair, x, y, rows)
  if y == 0 then
    return rows, vsm.zeros(), 0, ground
  end
  local north = layout:metatile(x, y - 1)
  local head = head_mask(pair, rows, north)
  if vsm.any(head) and not layout:blocked(x, y - 1) then
    return rows, head, M.head_ground(layout, pair, x, y - 1), ground
  end
  if vsm.any(head) and layout.signs[pk(x, y)] and M.blocked_head(pair, head, north) then
    return rows, head, north, ground
  end
  return rows, vsm.zeros(), 0, ground
end

function M.layout_records(layout_id, layout, pair)
  local records = {}
  for y = 0, layout.h - 1 do
    for x = 0, layout.w - 1 do
      if layout:role_at(x, y) ~= "signpost" then
        local rows, head, ground = event_board_masks(pair, layout, x, y)
        if rows ~= nil then
          records[#records + 1] = { layout_id, x, y, rows, head, ground, ground }
        end
      else
        local rows, head, hg, cg = M.sign_record(layout, pair, x, y)
        records[#records + 1] = { layout_id, x, y, rows, head, hg, cg }
      end
    end
  end
  return records
end

function M.write_records(records, path)
  records = py.sorted(records, function(r) return { r[1], r[3], r[2] } end)
  local parts = { "VXS3", py.pack("<I", #records) }
  for _, r in ipairs(records) do
    local vals = { r[1], r[2], r[3] }
    for i = 1, 16 do vals[#vals + 1] = r[4][i] end
    for i = 1, 16 do vals[#vals + 1] = r[5][i] end
    vals[#vals + 1] = r[6]
    vals[#vals + 1] = r[7]
    parts[#parts + 1] = py.pack_list("<HHH16H16HHH", vals)
  end
  tree:write(path, table.concat(parts))
end

function M.main()
  local layouts = voxel_cells.load_layouts()
  local events = voxel_cells.MapEvents()
  local pairs_ = {}
  local records = {}
  local nl = #layouts
  for layout_id, entry in ipairs(layouts) do
    if layout_id % 16 == 0 then S:progress(layout_id / nl, "signposts") end
    local layout = voxel_cells.Layout(entry, events)
    local key = layout.primary .. "|" .. layout.secondary
    if layout.outdoor then
      if not pairs_[key] then pairs_[key] = voxel_cells.pair_for(layout.primary, layout.secondary) end
      local pair = pairs_[key]
      for _, r in ipairs(M.layout_records(layout_id, layout, pair)) do records[#records + 1] = r end
    end
  end
  M.write_records(records, OUT)
  if V.log then
    local heads = 0
    for _, r in ipairs(records) do if vsm.any(r[5]) then heads = heads + 1 end end
    V.log("voxel sign masks: %d records, %d with a head", #records, heads)
  end
end

return M
