-- PER-PART COLOURS for the online look: SKIN, HAIR, OUTFIT, ACCENT.
--
-- GBA and DS character art is palette-indexed (16 colours), so a sheet is a
-- handful of colour RAMPS -- a hat's light/mid/dark red, the skin's three
-- steps.  Recolouring a part remaps every entry of its ramp to the chosen hue
-- and brightness while keeping each entry's own place in the ramp (its value
-- and relative saturation), so the shading steps survive.  Nothing is flat-
-- filled, and the outline and the white highlights are never touched.
--
-- WHICH COLOUR IS WHICH PART:
--   * HAND MAPS (below) for the protagonists of Platinum, HeartGold /
--     SoulSilver, Emerald and Black / White: our own small tables of colour ->
--     part, written by looking at the imported sheets' palettes.  They are
--     metadata about the art, not the art: no pixel and no palette is stored.
--     Keyed by the colour (#rrggbb) rather than the palette slot because the
--     same character's overworld, back and front sheets order their palettes
--     differently but share the colours.
--   * THE CLASSIFIER for everything else (other trainers, sheets a map does
--     not cover): skin-like hues -> SKIN; the colours that sit in the top
--     third of each frame -> HAIR (a hat counts: it is on the head), or the
--     darkest ramp when no position is known; the largest remaining hue
--     groups -> OUTFIT then ACCENT.
-- Game Boy sheets have four shades and no parts: the UI says so.
--
-- A part value on the wire and in the save: { h = 0..359, s = 0..100,
-- b = -60..60 } (hue, saturation, brightness).

local Parts = {}

Parts.LIST = {
  { id = "s", label = "SKIN" },
  { id = "h", label = "HAIR" },
  { id = "o", label = "OUTFIT" },
  { id = "a", label = "ACCENT" },
}
Parts.IDS = { s = true, h = true, o = true, a = true }

local COLOURS = {
  { id = "red", label = "RED", h = 356, s = 75, b = 0 },
  { id = "orange", label = "ORANGE", h = 24, s = 80, b = 5 },
  { id = "yellow", label = "YELLOW", h = 48, s = 75, b = 10 },
  { id = "green", label = "GREEN", h = 118, s = 60, b = -5 },
  { id = "teal", label = "TEAL", h = 172, s = 65, b = -5 },
  { id = "blue", label = "BLUE", h = 216, s = 70, b = 0 },
  { id = "navy", label = "NAVY", h = 226, s = 65, b = -35 },
  { id = "purple", label = "PURPLE", h = 275, s = 55, b = -5 },
  { id = "pink", label = "PINK", h = 328, s = 50, b = 10 },
  { id = "black", label = "BLACK", h = 230, s = 12, b = -55 },
  { id = "white", label = "WHITE", h = 220, s = 6, b = 25 },
}

Parts.PRESETS = {
  s = {
    { id = "light", label = "LIGHT", h = 26, s = 18, b = 4 },
    { id = "fair", label = "FAIR", h = 24, s = 30, b = -2 },
    { id = "medium", label = "MEDIUM", h = 24, s = 42, b = -14 },
    { id = "tan", label = "TAN", h = 23, s = 52, b = -26 },
    { id = "brown", label = "BROWN", h = 20, s = 58, b = -40 },
    { id = "deep", label = "DEEP", h = 18, s = 55, b = -56 },
  },
  h = {
    { id = "black", label = "BLACK", h = 230, s = 15, b = -50 },
    { id = "brown", label = "BROWN", h = 24, s = 60, b = -20 },
    { id = "blonde", label = "BLONDE", h = 46, s = 60, b = 30 },
    { id = "red", label = "RED", h = 8, s = 75, b = 5 },
    { id = "blue", label = "BLUE", h = 215, s = 65, b = 0 },
    { id = "green", label = "GREEN", h = 130, s = 55, b = 0 },
    { id = "pink", label = "PINK", h = 330, s = 50, b = 15 },
    { id = "white", label = "WHITE", h = 220, s = 5, b = 45 },
  },
  o = COLOURS,
  a = COLOURS,
}

Parts.HUE_STEP = 15
-- the top this share of a figure is its head (chibi sprites: a big one)
Parts.HAIR_TOP = 0.36
Parts.LIGHT_STEP = 10

-- ------------------------------------------------------------ wire

local function num(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

function Parts.cleanPart(p)
  if type(p) ~= "table" or not (num(p.h) and num(p.s) and num(p.b)) then return nil end
  return { h = math.floor(p.h) % 360, s = math.max(0, math.min(100, math.floor(p.s))),
           b = math.max(-60, math.min(60, math.floor(p.b))) }
end

-- { s = part, h = part, o = part, a = part } -> the same, cleaned; nil when empty
function Parts.clean(c)
  if type(c) ~= "table" then return nil end
  local out, any = {}, false
  for id in pairs(Parts.IDS) do
    local p = Parts.cleanPart(c[id])
    if p then out[id] = p any = true end
  end
  return any and out or nil
end

function Parts.signature(c)
  if type(c) ~= "table" then return "" end
  local bits = {}
  for _, def in ipairs(Parts.LIST) do
    local p = c[def.id]
    bits[#bits + 1] = p and (p.h .. "," .. p.s .. "," .. p.b) or "-"
  end
  return table.concat(bits, ";")
end

-- ------------------------------------------------------------ colour maths

local function rgbToHsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 1e-6 then
    if mx == r then h = ((g - b) / d) % 6
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h * 60
  end
  return h, (mx > 1e-6 and d / mx or 0), mx
end
Parts.rgbToHsv = rgbToHsv

local function hsvToRgb(h, s, v)
  h = (h % 360) / 60
  local c = v * s
  local x = c * (1 - math.abs(h % 2 - 1))
  local r, g, b
  if h < 1 then r, g, b = c, x, 0
  elseif h < 2 then r, g, b = x, c, 0
  elseif h < 3 then r, g, b = 0, c, x
  elseif h < 4 then r, g, b = 0, x, c
  elseif h < 5 then r, g, b = x, 0, c
  else r, g, b = c, 0, x end
  local m = v - c
  return r + m, g + m, b + m
end
Parts.hsvToRgb = hsvToRgb

local function clamp01(v) if v < 0 then return 0 elseif v > 1 then return 1 end return v end

function Parts.hexOf(r, g, b)
  return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- remap one ramp entry (r, g, b) of a part whose most saturated entry has
-- saturation `maxS`, to the part value `p`.  Value keeps its order (scaled
-- by brightness), saturation keeps its share of the ramp's.
function Parts.remap(r, g, b, p, maxS)
  local _, s, v = rgbToHsv(r, g, b)
  local share = (maxS and maxS > 0.02) and (s / maxS) or 0.5
  local ns = clamp01((p.s / 100) * (0.35 + 0.65 * share))
  local nv = clamp01(v * (1 + p.b / 100))
  return hsvToRgb(p.h, ns, nv)
end

-- ------------------------------------------------------------ hand maps

local function m(list)
  local t = {}
  for part, colours in pairs(list) do
    for _, c in ipairs(colours) do t[c] = part end
  end
  return t
end

-- [game][gender] = { ["rrggbb"] = part }
Parts.HAND_MAPS = {
  platinum = {
    boy = m({ s = { "ffd6bd", "dea57b", "7b4242" }, h = { "3a4252" },
              o = { "3a638c", "5a84e6", "6373bd", "4a6384", "7badde", "638cd6" },
              a = { "bd3a4a", "de6b7b" } }),
    -- Dawn: navy hair with its blue highlight, the red coat (its dark
    -- shade too), pink trim; the white beanie and scarf stay white
    girl = m({ s = { "ffd6bd", "dea57b" }, h = { "3a4252", "3a638c", "52638c" },
               o = { "c53a3a", "f76b4a", "c53a4a", "f76b73", "7b4242", "c53a52", "ef6b6b" },
               a = { "c56b9c", "ef94c5", "f7a5c5", "ff94c5" } }),
  },
  heartgold = {
    boy = m({ s = { "ffd6bd", "dea57b", "7b4242" }, h = { "3a4242", "29293a", "3a4252" },
              o = { "c53a3a", "f76b4a" },
              a = { "ffb521", "bd7321", "ce9c3a", "ffde5a" } }),
    girl = m({ s = { "ffd6bd", "dea57b" }, h = { "7b4242", "5a2121", "844a42", "521919" },
               o = { "ff6b63", "ce3a3a", "ad2121", "d64a42" },
               a = { "ce9c3a", "ffde5a" } }),
  },
  emerald = {
    boy = m({ s = { "ffc594", "ffd5b4", "de9473", "dea494", "ffdecd", "cd8373", "7b5a52" },
              h = { "102039" },
              o = { "394a7b", "293962", "7b4141", "627b9c", "31416a", "182952", "4a5a83" },
              a = { "73cd73", "4a9452", "8bde73", "629c5a", "c54141", "ff625a" } }),
    girl = m({ s = { "ffdecd", "dea494", "cd8373" }, h = { "7b5a52", "a46a52", "4a3139" },
               o = { "c54141", "ff625a" },
               a = { "41ac20", "6ad541", "8bde73", "629c5a" } }),
  },
  black = {
    -- (overworld, back, and the trfgra front picture 0)
    -- `ns` = SKIN ONLY WHERE IT TOUCHES SKIN: the battle back's hand and ear
    -- shade is the same grey as the shadow on the white jacket stripes /
    -- Hilda's top and hat, so it follows the skin only in the patches that
    -- touch a skin pixel (Avatar.paintImageData) -- the throwing hand gets
    -- the chosen skin all over, the white cloth keeps its grey
    boy = m({ s = { "ffd6bd", "d69c73", "ffdeb5", "dea57b" }, ns = { "b5a59c" },
              h = { "634231", "73523a", "523121", "846b63", "6b4a3a", "ad8473" },
              o = { "73a5e6", "427bc5", "3a529c", "7bc5e6", "5a8ca5", "295a84", "213a52",
                    "293a52", "295a94", "4a739c", "739cde" },
              a = { "ef6b6b", "9c5a6b", "d6634a", "8c3131", "c54a4a" } }),
    girl = m({ s = { "ffd6bd", "d69c73", "ffdec5", "dea57b", "b5845a" }, ns = { "bdada5" },
               h = { "63423a", "7b4a31", "634a31", "423129", "423a29", "735a42", "7b4242" },
               o = { "3a529c", "427bc5", "42293a", "296b84", "318cc5", "296394" },
               a = { "ef5a9c", "c55284", "844263", "e66373", "b5424a", "c54a6b", "84314a" } }),
  },
}
Parts.HAND_MAPS.soulsilver = Parts.HAND_MAPS.heartgold
Parts.HAND_MAPS.white = Parts.HAND_MAPS.black

-- ------------------------------------------------------------ classifier

-- entries = { { key = "rrggbb", r, g, b, n = pixels }, ... } (opaque only)
-- -> { [key] = part }
function Parts.classify(entries)
  local out = {}
  local groups = {}
  local rest = {}
  for _, e in ipairs(entries) do
    local h, s, v = rgbToHsv(e.r, e.g, e.b)
    e.hh, e.ss, e.vv = h, s, v
    if v < 0.2 then
      -- the outline
    elseif s < 0.12 and v > 0.8 then
      -- white highlights
    elseif h >= 8 and h <= 45 and s >= 0.12 and s <= 0.62 and v >= 0.5 then
      out[e.key] = "s"
    else
      rest[#rest + 1] = e
    end
  end
  -- HAIR is where a head is: the colours that sit, on average, in the top
  -- of each figure (e.y, 0 = top of the figure; the caller measures it).  Without a
  -- position, the darkest ramp when it is dark.
  local hasY = false
  for _, e in ipairs(rest) do if e.y then hasY = true end end
  local hair = {}
  if hasY then
    for _, e in ipairs(rest) do
      if e.y and e.y < Parts.HAIR_TOP then hair[e] = true end
    end
  else
    local darkest
    for _, e in ipairs(rest) do
      if e.vv < 0.45 and (not darkest or e.vv < darkest.vv) then darkest = e end
    end
    if darkest and #rest > 1 then
      -- the whole dark ramp of that hue
      for _, e in ipairs(rest) do
        local dh = math.abs(((e.hh - darkest.hh + 180) % 360) - 180)
        if e.vv < 0.45 and (dh < 30 or e.ss < 0.15) then hair[e] = true end
      end
    end
  end
  for e in pairs(hair) do out[e.key] = "h" end
  -- OUTFIT, ACCENT: the largest hue groups of the rest
  for _, e in ipairs(rest) do
    if not hair[e] then
      local bin = (e.ss < 0.15) and "grey" or tostring(math.floor(((e.hh + 15) % 360) / 30))
      local g = groups[bin]
      if not g then g = { n = 0, list = {}, bin = bin } groups[bin] = g end
      g.n = g.n + e.n
      g.list[#g.list + 1] = e
    end
  end
  local list = {}
  for _, g in pairs(groups) do list[#list + 1] = g end
  table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.bin < b.bin end)
  local next = "o"
  for _, g in ipairs(list) do
    for _, e in ipairs(g.list) do out[e.key] = next end
    if next == "o" then next = "a" else break end
  end
  return out
end

-- the part map for one sheet: the hand map when it covers the sheet (at
-- least three of its colours), else the classifier
function Parts.mapFor(entries, hand)
  if hand then
    local hits = 0
    for _, e in ipairs(entries) do if hand[e.key] then hits = hits + 1 end end
    if hits >= 3 then return hand, "hand" end
  end
  return Parts.classify(entries), "auto"
end

-- a hand map's "near" parts: ns = SKIN, but only in patches touching skin
Parts.NEAR = { ns = "s" }

-- colour -> new colour for one sheet: { [key] = { r, g, b } }; an entry
-- with `near = part` applies only where its patch touches that part
-- (Avatar.paintImageData decides per pixel)
function Parts.plan(entries, parts, hand)
  local map, how = Parts.mapFor(entries, hand)
  local maxS = {}
  for _, e in ipairs(entries) do
    local part = map[e.key]
    if part and parts[part] then
      local _, s = rgbToHsv(e.r, e.g, e.b)
      if s > (maxS[part] or 0) then maxS[part] = s end
    end
  end
  local plan = {}
  for _, e in ipairs(entries) do
    local part = map[e.key]
    local near = part and Parts.NEAR[part]
    local p = part and parts[near or part]
    if p then
      local r, g, b = Parts.remap(e.r, e.g, e.b, p, maxS[near or part])
      plan[e.key] = { r, g, b, near = near }
    end
  end
  return plan, how, map
end

return Parts
