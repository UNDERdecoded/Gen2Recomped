-- Port of 3ds_port/scripts/voxel_night.py: authored exterior glass regions,
-- without recolouring frames or roof art.
--
-- Lua shapes:
--   * NIGHT_WINDOWS[name] = array of {left, top, right, bottom} (Python's
--     tuples, same order)
--   * window_mask(art, rectangles) -> a 0-based table of w*h bytes (Python's
--     bytearray); art an RGBA Image
--   * component_rectangles(art, predicate, top) -> sorted array of
--     {x0, y0, x1, y1}; predicate(r, g, b, a)
--   * building_mask(art, name) -> a Lua STRING of w*h bytes (bytes(mask),
--     what gen_voxel_buildings hands Image.frombytes("L", ...)); M.any(mask)
--     is Python's any(mask)
--   Errors raise "ValueError: ..." as Python does.

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local floor = math.floor
local schar = string.char
local concat = table.concat

local function rects_of(list)
  local out = {}
  for _, r in ipairs(list) do out[#out + 1] = r end
  return out
end

-- tuple((xpos, top, xpos + w, bottom) for xpos in xs for top, bottom in pairs)
local function grid(xs, w, rows)
  local out = {}
  for _, x in ipairs(xs) do
    for _, tb in ipairs(rows) do out[#out + 1] = { x, tb[1], x + w, tb[2] } end
  end
  return out
end

local function cat(...)
  local out = {}
  for _, t in ipairs({ ... }) do
    for _, r in ipairs(t) do out[#out + 1] = r end
  end
  return out
end

local GYM = { { 11, 50, 21, 53 }, { 27, 50, 37, 53 }, { 75, 50, 85, 53 },
              { 49, 62, 55, 77 }, { 57, 62, 63, 77 } }

local devon = {}
for _, x in ipairs({ 18, 42, 122, 138 }) do
  for _, top in ipairs({ 42, 74 }) do devon[#devon + 1] = { x, top, x + 4, top + 12 } end
end
for _, x in ipairs({ 55, 71, 87, 103 }) do
  for _, top in ipairs({ 58, 66, 90, 98 }) do devon[#devon + 1] = { x, top, x + 2, top + 5 } end
end
for _, x in ipairs({ 10, 26, 42, 114, 130, 146 }) do devon[#devon + 1] = { x, 98, x + 4, 102 } end
for _, x in ipairs({ 10, 18, 26, 34, 42, 114, 122, 130, 138, 146 }) do
  devon[#devon + 1] = { x, 105, x + 4, 110 }
end

M.NIGHT_WINDOWS = {
  dewford_house = { { 34, 46, 39, 52 }, { 41, 46, 46, 52 } },
  dewford_hall = { { 50, 46, 55, 52 }, { 57, 46, 62, 52 } },
  dewford_gym_exterior = rects_of(GYM),
  littleroot_house_w = { { 17, 62, 23, 68 }, { 25, 62, 31, 68 } },
  littleroot_house_e = { { 49, 62, 55, 68 }, { 57, 62, 63, 68 } },
  littleroot_lab = grid({ 18, 25, 34, 41 }, 5, { { 61, 63 }, { 64, 68 } }),
  oldale_house = cat(grid({ 34, 41 }, 5, { { 43, 49 }, { 50, 53 } }), { { 20, 48, 28, 52 } }),
  kit_house_4 = cat(grid({ 34, 41 }, 5, { { 43, 45 }, { 46, 49 }, { 50, 53 } }), { { 20, 48, 28, 52 } }),
  kit_house_5 = cat(grid({ 18, 25, 50, 57 }, 5, { { 43, 45 }, { 46, 49 }, { 50, 53 } }),
                    { { 36, 48, 44, 52 } }),
  flower_shop = grid({ 9, 65, 81 }, 6, { { 42, 48 }, { 49, 52 } }),
  pokemon_center = { { 17, 45, 31, 61 } },
  poke_mart = { { 17, 45, 31, 61 } },
  gym = rects_of(GYM),
  gym_rustboro = rects_of(GYM),
  devon_corporation = devon,
}

function M.window_mask(art, rectangles)
  local width, height = art.width, art.height
  local mask = {}
  for i = 0, width * height - 1 do mask[i] = 0 end
  for _, r in ipairs(rectangles) do
    local left, top, right, bottom = r[1], r[2], r[3], r[4]
    if not (0 <= left and left < right and right <= width and 0 <= top and top < bottom and bottom <= height) then
      error("ValueError: window rectangle is outside the building art", 2)
    end
    for ypos = top, bottom - 1 do
      for xpos = left, right - 1 do
        local red, green, blue, alpha = art:get(xpos, ypos)
        if alpha >= 128 and red >= 90 and green > red and blue > red + 12 then
          local v = 128 + floor((red + green + blue) / 6)
          if v > 255 then v = 255 end
          mask[ypos * width + xpos] = v
        end
      end
    end
  end
  return mask
end

-- set order: irrelevant (remaining.pop() picks a seed, but every component
-- is flooded whole and the rectangles are sorted)
function M.component_rectangles(art, predicate, top)
  local W, H = art.width, art.height
  local remaining = {}
  local order = {}
  for ypos = top, H - 1 do
    for xpos = 0, W - 1 do
      if predicate(art:get(xpos, ypos)) then
        local k = ypos * W + xpos
        remaining[k] = true
        order[#order + 1] = k
      end
    end
  end
  local rects = {}
  for _, seed in ipairs(order) do
    if remaining[seed] then
      remaining[seed] = nil
      local pending = { seed }
      local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
      while #pending > 0 do
        local k = pending[#pending]
        pending[#pending] = nil
        local xpos, ypos = k % W, floor(k / W)
        if xpos < x0 then x0 = xpos end
        if ypos < y0 then y0 = ypos end
        if xpos > x1 then x1 = xpos end
        if ypos > y1 then y1 = ypos end
        local nb = { { xpos - 1, ypos }, { xpos + 1, ypos }, { xpos, ypos - 1 }, { xpos, ypos + 1 } }
        for _, n in ipairs(nb) do
          local nx, ny = n[1], n[2]
          if nx >= 0 and nx < W and ny >= 0 and ny < H then
            local nk = ny * W + nx
            if remaining[nk] then
              remaining[nk] = nil
              pending[#pending + 1] = nk
            end
          end
        end
      end
      rects[#rects + 1] = { x0, y0, x1 + 1, y1 + 1 }
    end
  end
  return py.sorted(rects)
end

local function mask_bytes(mask, n)
  local parts, chunk = {}, {}
  for i = 0, n - 1, 4096 do
    local m = math.min(4096, n - i)
    for k = 1, m do chunk[k] = mask[i + k - 1] end
    parts[#parts + 1] = schar(unpack(chunk, 1, m))
  end
  return concat(parts)
end

function M.any(mask)
  if type(mask) == "string" then return mask:find("[^%z]") ~= nil end
  for _, v in pairs(mask) do if v ~= 0 then return true end end
  return false
end

function M.building_mask(art, name)
  if name:sub(-5) == "_bare" then name = name:sub(1, -6) end
  local rectangles = M.NIGHT_WINDOWS[name] or {}
  if py.startswith(name, "rustboro_stone_") then
    local frames = M.component_rectangles(art, function(r, g, b, a)
      return r == 65 and g == 74 and b == 106 and a == 255
    end, 48)
    rectangles = {}
    for _, rect in ipairs(frames) do
      if rect[3] - rect[1] == 10 and rect[4] - rect[2] == 10 then rectangles[#rectangles + 1] = rect end
    end
  elseif py.startswith(name, "rustboro_olive_") then
    local panes = M.component_rectangles(art, function(r, g, b, a)
      return a >= 128 and r >= 90 and g > r and b > r + 12
    end, 48)
    rectangles = {}
    for _, rect in ipairs(panes) do
      local w, h = rect[3] - rect[1], rect[4] - rect[2]
      if 2 <= w and w <= 12 and 2 <= h and h <= 12 then rectangles[#rectangles + 1] = rect end
    end
  end
  local mask = M.window_mask(art, rectangles)
  local W = art.width
  if name == "devon_corporation" then
    for _, r in ipairs(rectangles) do
      for ypos = r[2], r[4] - 1 do
        for xpos = r[1], r[3] - 1 do
          local red, green, blue, alpha = art:get(xpos, ypos)
          if alpha >= 128 and red >= 32 and green > red + 2 and blue > red + 12 then
            mask[ypos * W + xpos] = 180
          end
        end
      end
    end
  end
  local n = W * art.height
  if #rectangles > 0 then
    local any = false
    for i = 0, n - 1 do if mask[i] ~= 0 then any = true; break end end
    if not any then error("ValueError: " .. name .. " has no glass pixels in its authored windows", 2) end
  end
  return mask_bytes(mask, n)
end

return M
