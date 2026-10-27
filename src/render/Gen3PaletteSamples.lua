-- Native-only palette samples. The public sampler remains detached and pure.
-- Each decoder retains at most four owned pictures; mutable source tables are
-- checked by value before reuse, never merely by identity or current RGB output.
local Cycles = require("src.render.Gen3PaletteCycles")
local M = {}
M.__index = M
local banks = {"primary", "secondary"}
local fields = {"kind", "first", "count", "step", "phase"}
local function dense(t, size)
  if type(t) ~= "table" or getmetatable(t) ~= nil or #t ~= size then return false end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k ~= math.floor(k) or k < 1 or k > size then return false end
    n = n + 1
  end
  return n == size
end

-- Called only after the full sampler has validated the complete source.
local function snapshot(pair, layout)
  local out = {split = layout.palettesInPrimary}
  for _, name in ipairs(banks) do
    local src, bytes, programs = pair[name], {}, {}
    for _, p in ipairs(src.palettes) do
      for _, rgb in ipairs(p) do bytes[#bytes + 1] = string.char(rgb[1], rgb[2], rgb[3]) end
    end
    for i, rule in ipairs(src.paletteCycles) do
      local copy = {}
      for _, key in ipairs(fields) do copy[key] = rule[key] end
      if rule.kind == "frames" then
        copy.frames = {}
        for j, frame in ipairs(rule.frames) do copy.frames[j] = frame end
      else
        copy.direction = rule.direction
      end
      programs[i] = copy
    end
    out[name] = {rgb = table.concat(bytes), programs = programs}
  end
  return out
end

local function unchanged(pair, layout, source)
  if layout.palettesInPrimary ~= source.split then return false end
  for _, name in ipairs(banks) do
    local bank, old = pair[name], source[name]
    if type(bank) ~= "table" or getmetatable(bank) ~= nil
      or not dense(bank.paletteCycles, #old.programs)
      or not dense(bank.palettes, 16) then return false end
    for i, rule in ipairs(bank.paletteCycles) do
      local saved = old.programs[i]
      if type(rule) ~= "table" or getmetatable(rule) ~= nil then return false end
      for _, key in ipairs(fields) do if rule[key] ~= saved[key] then return false end end
      if saved.frames then
        if not dense(rule.frames, #saved.frames) then return false end
        for j, bytes in ipairs(saved.frames) do if rule.frames[j] ~= bytes then return false end end
      elseif rule.direction ~= saved.direction then
        return false
      end
    end
    local at = 1
    for p = 1, 16 do
      local palette = bank.palettes[p]
      if not dense(palette, 16) then return false end
      for c = 1, 16 do
        local rgb = palette[c]
        if not dense(rgb, 3) then return false end
        local r, g, b = old.rgb:byte(at, at + 2)
        if rgb[1] ~= r or rgb[2] ~= g or rgb[3] ~= b then return false end
        at = at + 3
      end
    end
  end
  return true
end

local function selected(sample, source, ticks)
  for _, name in ipairs(banks) do
    local indices = sample[name .. "Frames"]
    for i, rule in ipairs(source[name].programs) do
      local length = rule.kind == "frames" and #rule.frames or rule.count
      local period = length * rule.step
      local index = math.floor(((ticks % period) + (rule.phase or 0)) % period / rule.step)
      if indices[i] ~= index then return false end
    end
  end
  return true
end

function M.new(pair, layout, first)
  return setmetatable({source = snapshot(pair, layout), pictures = {first},
    hits = 0, misses = 1, invalidations = 0}, M)
end

function M:sample(pair, layout, ticks)
  if type(ticks) ~= "number" or ticks ~= math.floor(ticks) or ticks < 0 or ticks > 9007199254740991 then
    self.source, self.pictures = nil, {}
    return nil, "terrain clock unavailable"
  end
  local same = self.source and unchanged(pair, layout, self.source)
  if same then
    for i = #self.pictures, 1, -1 do
      local hit = self.pictures[i]
      if selected(hit, self.source, ticks) then
        table.remove(self.pictures, i);self.pictures[#self.pictures + 1] = hit
        hit.ticks = ticks;self.hits = self.hits + 1
        return hit
      end
    end
  else
    self.source, self.pictures = nil, {}
    self.invalidations = self.invalidations + 1
  end
  self.misses = self.misses + 1
  local sample, reason = Cycles.sample(pair, layout, ticks)
  if not sample then self.source, self.pictures = nil, {};return nil, reason end
  if not self.source then self.source = snapshot(pair, layout) end
  self.pictures[#self.pictures + 1] = sample
  if #self.pictures > 4 then table.remove(self.pictures, 1) end
  return sample
end

function M:stats()
  return {entries = #self.pictures, hits = self.hits, misses = self.misses,
    invalidations = self.invalidations, limit = 4}
end
return M
