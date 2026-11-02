-- What the player sees of an in-game bake (lib/BakeJob.lua): a small box in
-- the corner of the game picture ("Building Emerald 3DS voxels... 42%"),
-- drawn from the engine's render.hud hook so the game under it stays
-- playable, and the E3DS 3D options row reading "E3DS 3D (BUILDING)" with
-- the percentage beside the angle while it runs.
--
-- The row is the engine's (src/render/Pipelines.lua rows()): its label is
-- read when the options screen builds its rows and its value -- the level's
-- label -- every time it is drawn, both off the registered record.  So the
-- record's `label` and `levels` are rewritten here while a bake runs and
-- put back after.

local V = ...
local BakeJob = V.require("BakeJob")

local BakeUI = {}

local PIPELINE = "e3ds_voxel"
local SHOW_FAILURE = 15      -- seconds a failure / missing-ROM note stays up
local SHOW_DONE = 4

local original      -- { label, levels = {...} } as registered

local function record()
  local ok, Pipelines = pcall(require, "src.render.Pipelines")
  if not (ok and Pipelines and Pipelines.get) then return nil end
  return Pipelines.get(PIPELINE)
end

-- The row's label and level labels for the job's state.
function BakeUI.updateRow()
  local def = record()
  if not def or type(def.levels) ~= "table" then return end
  if not original then
    original = { label = def.label, levels = {} }
    for i, l in ipairs(def.levels) do original.levels[i] = l end
  end
  local state, suffix, levelSuffix = BakeJob.state, nil, nil
  if state == "running" then
    suffix = " (BUILDING)"
    levelSuffix = (" %d%%"):format(math.floor((BakeJob.progress or 0) * 100))
  elseif state == "failed" then
    suffix = " (FAILED)"
  elseif state == "need_rom" then
    suffix = " (NEEDS ROM)"
  end
  local label = original.label .. (suffix or "")
  if def.label ~= label then pcall(function() def.label = label end) end
  for i, l in ipairs(original.levels) do
    local want = (i > 1 and levelSuffix) and (l .. levelSuffix) or l
    if def.levels[i] ~= want then pcall(function() def.levels[i] = want end) end
  end
end

-- ------------------------------------------------------------ the box --

local fonts = {}
local function font(size)
  size = math.max(8, math.floor(size + 0.5))
  local f = fonts[size]
  if not f then
    local ok, made = pcall(love.graphics.newFont, size)
    f = ok and made or love.graphics.getFont()
    fonts[size] = f
  end
  return f
end

local function lines(level)
  local state, age = BakeJob.state, (love.timer.getTime() - (BakeJob.changedAt or 0))
  if state == "running" then
    local pct = math.floor((BakeJob.progress or 0) * 100)
    return { ("Building Emerald 3DS voxels... %d%%"):format(pct), BakeJob.label }, BakeJob.progress or 0
  end
  if not (level and level > 0) then return nil end
  if (state == "failed" or state == "need_rom") and age < SHOW_FAILURE then
    return { state == "failed" and "Emerald 3DS voxels: not built" or "Emerald 3DS voxels",
             BakeJob.message }
  end
  if state == "done" and age < SHOW_DONE then
    return { "Emerald 3DS voxels built" }
  end
  return nil
end

-- word-wrap one line to `width` with font `f`
local function wrap(f, text, width)
  local out, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    local candidate = line == "" and word or (line .. " " .. word)
    if line ~= "" and f:getWidth(candidate) > width then
      out[#out + 1] = line
      line = word
    else
      line = candidate
    end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end

function BakeUI.draw(viewport, level)
  local text, fraction = lines(level)
  if not text then return end
  local gx = viewport and viewport.gameX or 0
  local gy = viewport and viewport.gameY or 0
  local gw = viewport and viewport.gameWidth or love.graphics.getWidth()
  local gh = viewport and viewport.gameHeight or love.graphics.getHeight()
  local f = font(math.max(10, math.min(22, gh / 30)))
  local pad = math.floor(f:getHeight() * 0.45)
  local maxW = math.min(gw * 0.9, f:getWidth("M") * 40)
  local rows = {}
  for i, l in ipairs(text) do
    if l and l ~= "" then
      for _, w in ipairs(wrap(f, l, maxW - 2 * pad)) do rows[#rows + 1] = { w, i > 1 } end
    end
  end
  local w = 0
  for _, r in ipairs(rows) do w = math.max(w, f:getWidth(r[1])) end
  local lh = f:getHeight()
  local barH = fraction and math.max(2, math.floor(lh * 0.25)) or 0
  local boxW = w + 2 * pad
  local boxH = #rows * lh + 2 * pad + (fraction and (barH + pad * 0.5) or 0)
  local x, y = gx + pad, gy + pad
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", x, y, boxW, boxH, pad * 0.5, pad * 0.5)
  love.graphics.setFont(f)
  for i, r in ipairs(rows) do
    if r[2] then love.graphics.setColor(0.82, 0.86, 0.9, 1) else love.graphics.setColor(1, 1, 1, 1) end
    love.graphics.print(r[1], x + pad, y + pad + (i - 1) * lh)
  end
  if fraction then
    local by = y + pad + #rows * lh + pad * 0.25
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.rectangle("fill", x + pad, by, w, barH)
    love.graphics.setColor(0.45, 0.85, 0.55, 1)
    love.graphics.rectangle("fill", x + pad, by, w * math.max(0, math.min(1, fraction)), barH)
  end
  love.graphics.pop()
end

return BakeUI
