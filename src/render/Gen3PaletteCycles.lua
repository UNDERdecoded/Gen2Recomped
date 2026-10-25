-- Bounded, pure palette animation. Records use absolute BG colour offsets
-- (slot * 16 + colour), even in the secondary bank, just like metatile words.
-- No callback execution, cartridge IO, clock advancement or retained cache.
local M = {}
local names = { "primary", "secondary" }
local function integer(n, lo, hi)
  return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi
end
local function dense(t, max)
  if type(t) ~= "table" or getmetatable(t) ~= nil or #t > max then return false end
  local n = 0
  for k in pairs(t) do
    if not integer(k, 1, #t) then return false end
    n = n + 1
  end
  return n == #t
end

-- The native renderer owns its last sample. Static banks need no new colour
-- tables or packed strings every terrain tick, but source tables are mutable:
-- compare their complete shape and RGB bytes before reusing that sample.
-- In particular, empty metadata is static; missing metadata is still unknown.
function M.staticUnchanged(pair, layout, ticks, previous)
  if not previous or not previous.complete
    or not integer(ticks, 0, 9007199254740991)
    or not integer(layout.palettesInPrimary, 1, 15) then return false end
  for _, name in ipairs(names) do
    local bank = pair[name]
    local selected = previous[name .. "Frames"]
    if type(bank) ~= "table" or getmetatable(bank) ~= nil
      or not dense(bank.paletteCycles, 0)
      or type(selected) ~= "table" or #selected ~= 0 then return false end
  end
  -- Reject either animated bank before scanning any colours. Emerald often
  -- combines a static primary with an animated secondary.
  for _, name in ipairs(names) do
    local bank = pair[name]
    local packed = previous[name .. "RGB8"]
    if type(packed) ~= "string" or #packed ~= 768
      or not dense(bank.palettes, 16) or #bank.palettes ~= 16 then return false end
    local at = 1
    for p = 1, 16 do
      local palette = bank.palettes[p]
      if not dense(palette, 16) or #palette ~= 16 then return false end
      for c = 1, 16 do
        local rgb = palette[c]
        if not dense(rgb, 3) or #rgb ~= 3 then return false end
        local r, g, b = packed:byte(at, at + 2)
        if rgb[1] ~= r or rgb[2] ~= g or rgb[3] ~= b then return false end
        at = at + 3
      end
    end
  end
  return true
end

-- Missing metadata is unknown, not evidence that an old cache is static.
function M.sample(pair, layout, ticks)
  if not integer(ticks, 0, 9007199254740991) then return nil, "terrain clock unavailable" end
  local split = type(layout) == "table" and layout.palettesInPrimary
  if not integer(split, 1, 15) then return nil, "palette animation data unavailable" end
  local runs, bytes = 0, 0
  for _, name in ipairs(names) do
    local bank = pair[name]
    local list = type(bank) == "table" and getmetatable(bank) == nil and bank.paletteCycles
    if not dense(list, 32) then return nil, "palette animation data unavailable" end
    local lo, hi = name == "primary" and 0 or split * 16, name == "primary" and split * 16 or 256
    for _, a in ipairs(list) do
      runs = runs + 1
      if runs > 32 or type(a) ~= "table" or getmetatable(a) ~= nil
        or not integer(a.first, lo, hi - 1) or not integer(a.count, 1, hi - lo)
        or a.first + a.count > hi or not integer(a.step, 1, 65535)
        or (a.phase ~= nil and not integer(a.phase, 0, 65535)) then
        return nil, "palette animation data unavailable"
      end
      if a.kind == "frames" then
        if not dense(a.frames, 256) or #a.frames < 2 then return nil, "palette animation data unavailable" end
        for _, f in ipairs(a.frames) do
          if type(f) ~= "string" or #f ~= a.count * 3 then return nil, "palette animation data unavailable" end
          bytes = bytes + #f
          if bytes > 262144 then return nil, "palette animation data unavailable" end
        end
      elseif a.kind ~= "rotate" or a.count < 2 or (a.direction ~= 1 and a.direction ~= -1) then
        return nil, "palette animation data unavailable"
      end
    end
  end
  local out = { ticks = ticks, primary = {}, secondary = {}, complete = true }
  local key = { "gen3-palette-v1" }
  for _, name in ipairs(names) do
    local src, dst = pair[name], out[name]
    if not dense(src.palettes, 16) or #src.palettes ~= 16 then return nil, "palette animation data unavailable" end
    for p = 1, 16 do
      local palette = src.palettes[p]
      if not dense(palette, 16) or #palette ~= 16 then return nil, "palette animation data unavailable" end
      dst[p] = {}
      for c = 1, 16 do
        local rgb = palette[c]
        if not dense(rgb, 3) or #rgb ~= 3 then return nil, "palette animation data unavailable" end
        dst[p][c] = {}
        for channel = 1, 3 do
          if not integer(rgb[channel], 0, 255) then return nil, "palette animation data unavailable" end
          dst[p][c][channel] = rgb[channel]
        end
      end
    end
    local selected = {}
    for i, a in ipairs(src.paletteCycles) do
      -- Reduce before adding phase: ticks + phase could exceed exact doubles.
      local length = a.kind == "frames" and #a.frames or a.count
      local period = length * a.step
      local f = math.floor(((ticks % period) + (a.phase or 0)) % period / a.step)
      selected[i] = f
      local frame = a.kind == "frames" and a.frames[f + 1]
      for c = 0, a.count - 1 do
        local at = a.first + c
        local rgb
        if frame then
          rgb = { frame:byte(c * 3 + 1, c * 3 + 3) }
        else
          local from = a.first + (c - a.direction * f) % a.count
          local source = src.palettes[math.floor(from / 16) + 1][from % 16 + 1]
          rgb = { source[1], source[2], source[3] }
        end
        dst[math.floor(at / 16) + 1][at % 16 + 1] = rgb
      end
    end
    out[name .. "Frames"] = selected
    local packed = {}
    for _, p in ipairs(dst) do
      for _, rgb in ipairs(p) do packed[#packed + 1] = string.char(rgb[1], rgb[2], rgb[3]) end
    end
    out[name .. "RGB8"] = table.concat(packed)
    key[#key + 1] = out[name .. "RGB8"]
  end
  out.contentKey = table.concat(key)
  return out
end
return M
