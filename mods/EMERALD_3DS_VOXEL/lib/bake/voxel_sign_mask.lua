-- Port of 3ds_port/scripts/voxel_sign_mask.py: which pixels of a signpost
-- cell are the sign.
--
-- Lua shapes: a pixel set is {[y*16 + x] = true}; mask rows are a 1-based
-- array of 16 ints (Python's rows[y] is rows[y + 1]).

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local bit = require("bit")
local band, rshift, lshift, bor = bit.band, bit.rshift, bit.lshift, bit.bor
local floor = math.floor

local function zeros()
  local t = {}
  for i = 1, 16 do t[i] = 0 end
  return t
end
M.zeros = zeros

function M.any(rows)
  for i = 1, #rows do if rows[i] ~= 0 then return true end end
  return false
end

-- Lower-layer colours of the walkable cells next to (x, y): a set of rgb
function M.ground_colours(pair, layout, x, y)
  local colours = {}
  for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { 1, 1 } }) do
    local nx, ny = x + d[1], y + d[2]
    if not (layout:off_map(nx, ny) or layout:blocked(nx, ny)) then
      local m = layout:metatile(nx, ny)
      if next(pair:layer_pixels(m, 1)) == nil then
        for _, c in pairs(pair:layer_pixels(m, 0)) do colours[c] = true end
      end
    end
  end
  return colours
end

-- Rows of bits: pixels not reachable from the border through empty ones.
-- opaque: {[p] = truthy} (16x16)
function M.cutout_mask(opaque, width, height)
  width, height = width or 16, height or 16
  local outside = {}
  local queue, head = {}, 1
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      if x == 0 or x == width - 1 or y == 0 or y == height - 1 then
        queue[#queue + 1] = y * width + x
      end
    end
  end
  while head <= #queue do
    local p = queue[head]
    head = head + 1
    if not outside[p] and not opaque[p] then
      outside[p] = true
      local x, y = p % width, floor(p / width)
      if x + 1 < width then queue[#queue + 1] = p + 1 end
      if x - 1 >= 0 then queue[#queue + 1] = p - 1 end
      if y + 1 < height then queue[#queue + 1] = p + width end
      if y - 1 >= 0 then queue[#queue + 1] = p - width end
    end
  end
  local rows = {}
  for y = 0, height - 1 do
    local v = 0
    for x = 0, width - 1 do
      if not outside[y * width + x] then v = v + 2 ^ x end
    end
    rows[y + 1] = v
  end
  return rows
end

function M.metatile_mask(pair, layout, x, y)
  local metatile = layout:metatile(x, y)
  if layout:draws_post_sign(metatile) then
    return M.cutout_mask(pair:layer_pixels(metatile, 1))
  end
  local ground = M.ground_colours(pair, layout, x, y)
  local pixels = {}
  for p, c in pairs(pair:layer_pixels(metatile, 0)) do
    if not ground[c] then pixels[p] = true end
  end
  for p in pairs(pair:layer_pixels(metatile, 1)) do pixels[p] = true end
  return M.cutout_mask(pixels)
end

local HEAD_MAX_WIDTH = 15
local HEAD_MAX_PIXELS = 160
M.HEAD_MAX_WIDTH, M.HEAD_MAX_PIXELS = HEAD_MAX_WIDTH, HEAD_MAX_PIXELS

function M.head_mask(pair, sign_rows, north)
  if py.popcount(sign_rows[1]) > HEAD_MAX_WIDTH then
    return zeros()
  end
  local upper = {}
  for p in pairs(pair:layer_pixels(north, 1)) do upper[p] = true end
  return M.connected_head(upper, sign_rows, HEAD_MAX_WIDTH, HEAD_MAX_PIXELS)
end

function M.connected_head(upper, sign_rows, max_width, max_pixels)
  local top = sign_rows[1]
  local queue, head, n = {}, {}, 0
  for x = 0, 15 do
    if upper[15 * 16 + x] then
      local near = false
      for xx = x - 1, x + 1 do
        if xx >= 0 and xx < 16 and band(rshift(top, xx), 1) ~= 0 then near = true end
      end
      if near then
        local p = 15 * 16 + x
        if not head[p] then n = n + 1 end
        head[p] = true
        queue[#queue + 1] = p
      end
    end
  end
  local qi = 1
  while qi <= #queue do
    local p = queue[qi]
    qi = qi + 1
    local x, y = p % 16, floor(p / 16)
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = x + dx, y + dy
        if nx >= 0 and nx < 16 and ny >= 0 and ny < 16 then
          local q = ny * 16 + nx
          if upper[q] and not head[q] then
            head[q] = true
            n = n + 1
            queue[#queue + 1] = q
          end
        end
      end
    end
  end
  if n == 0 then return zeros() end
  local lo, hi = 16, -1
  for p in pairs(head) do
    local x = p % 16
    if x < lo then lo = x end
    if x > hi then hi = x end
  end
  if hi - lo + 1 > max_width or n > max_pixels then
    return zeros()
  end
  return M.cutout_mask(head)
end

-- a two-cell event board beside a wall over proven clean ground:
-- rows, head, ground or nil
function M.event_board_masks(pair, layout, x, y)
  local voxel_cells = S.import("voxel_cells")
  local pk = voxel_cells.pk
  if not layout.outdoor or not layout.signs[pk(x, y)] or not layout:blocked(x, y) then return nil end
  for _, row in ipairs({ y - 1, y + 1 }) do
    if layout:off_map(x, row) or layout:blocked(x, row) then return nil end
  end
  local all = true
  for _, o in ipairs({ -1, 1 }) do
    if not (layout:off_map(x + o, y) or layout:blocked(x + o, y)) then all = false end
  end
  if all then return nil end
  local ground = layout:metatile(x, y + 1)
  local lower = pair:layer_pixels(ground, 0)
  local voxel_art = S.import("voxel_art")
  if voxel_art.count(lower) ~= 256 then return nil end
  for p, c in pairs(pair:layer_pixels(ground, 1)) do
    if lower[p] ~= c then return nil end
  end
  local body, north = layout:metatile(x, y), layout:metatile(x, y - 1)
  for _, m in ipairs({ body, north }) do
    if not voxel_art.same(pair:layer_pixels(m, 0), lower) then return nil end
  end
  local function differs(m)
    local out = {}
    for p, c in pairs(pair:layer_pixels(m, 1)) do
      if c ~= lower[p] then out[p] = true end
    end
    return out
  end
  local body_pixels, head_pixels = differs(body), differs(north)
  local rows = M.cutout_mask(body_pixels)
  local head = M.connected_head(head_pixels, rows, 16, 256)
  if not M.any(rows) or not M.any(head) then return nil end
  return rows, head, ground
end

return M
