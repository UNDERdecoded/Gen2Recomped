-- HEARTGOLD / SOULSILVER POKEDEX: THE SEARCH, THE SIZES, THE FORMS AND THE
-- AREAS AS DATA (no drawing). Used by src/ui/HgssDexSearch.lua and
-- src/ui/HgssDexDetails.lua.
--
-- READ FROM CODE (pokeheartgold asm/overlay_18.s, src/application/pokedex/):
--   * the search is `ov18_021F7ED4`: the dex order (Johto / National) cut to
--     the SEEN species (ov18_021F8198), then in this order: the sort
--     (ov18_021F822C: 0 numerical keeps the list, 1 A-to-Z keeps uncaught
--     ones, 2-5 heaviest / lightest / tallest / smallest keep only CAUGHT
--     ones -- each re-orders to the sort list's own order, ov18_021F8764),
--     the first letter (ov18_021F82CC: 26 = any, else zukan_data member
--     18 + letter, uncaught kept), type 1 and type 2 (ov18_021F831C: 17 =
--     any, else member 62 + type, CAUGHT only), the body style
--     (ov18_021F8468: grid cell -> member, below; uncaught kept), the area
--     (ov18_021F8584: a bit of the per-species zukan_hw_data byte; "unknown"
--     without the National Dex means "not in Johto"), then the height and
--     weight ranges (ov18_021F8640 / 86D0: the stops table, CAUGHT only,
--     skipped when the range is the full 0..152)
--   * the search's defaults (ov18_021F7ED4 calls): order 0, letter 26, types
--     17 / 17, height 0..152, weight 0..152, area 3 (all), body 14 (all)
--   * the body-style grid's cell -> body style (ov18_021F8468's jump table)
--   * the forms list (ov18_021E8254): Castform's four and Cherrim's two
--     always; the tracked species' seen forms; otherwise the seen genders
--   * the area flags: bit 0 Johto, bit 1 Kanto, bit 2 unknown, bit 3 all
--     (zukan_hw_data member 1)
-- FALLBACKS (the installed cache predates the `search` record): heights and
-- weights from constants.dexHeights / dexWeights, else parsed back out of message banks 814 / 812 (the US strings, feet /
-- inches and pounds), the sort lists sorted from those and from the names,
-- the letters from the names, the types from data.pokemon; no body styles
-- (that filter then keeps everything); the area flags from scanning
-- data.encounters (found anywhere = Johto or Kanto by the map's name, else
-- unknown).

local D = {}

local bit = require("bit")
local band, bor = bit.band, bit.bor

local floor = math.floor
D.STOPS = 152
D.DEFAULTS = { order = 0, letter = 26, type1 = 17, type2 = 17, hmin = 0, hmax = 152, wmin = 0, wmax = 152, area = 3, body = 14 }

-- ov18_021F8468: body-style grid cell -> body style (zukan_data 79 + style)
D.BODY_OF_CELL = { [0] = 12, 8, 9, 10, 4, 3, 7, 0, 13, 6, 11, 2, 5, 1 }

function D.copyDefaults()
  local t = {}
  for k, v in pairs(D.DEFAULTS) do t[k] = v end
  return t
end

local function text(game, bank, index)
  local t = ((game.data or {}).text or {})[("TEXT_B%04d_%05d"):format(bank, index)]
  if type(t) ~= "string" then return nil end
  return (t:gsub("{[^}]*}", ""))
end
D.text = text

-- ------------------------------------------------------- height / weight --

-- the US strings back to decimetres / hectograms ("  2'11”", "14.1 lbs.")
local function parseHeight(s)
  if not s then return nil end
  local ft, inch = s:match("(%d+)%D+(%d+)")
  if not ft then return nil end
  local inches = tonumber(ft) * 12 + tonumber(inch)
  return floor(inches * 2.54 / 10 + 0.5)
end
local function parseWeight(s)
  if not s then return nil end
  local lbs = s:match("(%d+%.?%d*)")
  if not lbs then return nil end
  return floor(tonumber(lbs) / 0.220462 + 0.5)
end

function D.height(game, search, species)
  local id = tonumber(species)
  if search and search.height and search.height[id] then return search.height[id] end
  -- the constants record carries zukan_data's own heights (/a/0/7/4)
  local own = ((game.data or {}).constants or {}).dexHeights
  if own and id and own[id] then return own[id] end
  return parseHeight(text(game, 814, id or 0))
end
function D.weight(game, search, species)
  local id = tonumber(species)
  if search and search.weight and search.weight[id] then return search.weight[id] end
  -- the constants record carries zukan_data's own weights (/a/0/7/4)
  local own = ((game.data or {}).constants or {}).dexWeights
  if own and id and own[id] then return own[id] end
  return parseWeight(text(game, 812, id or 0))
end

-- the US conversions the cartridge prints (Chikorita: 9 dm = 2'11", 64 hg =
-- 14.1 lbs.)
function D.fmtHeight(dm)
  if not dm then return "--'--\"" end
  local inches = floor(dm * 10 / 2.54 + 0.5)
  return ("%d'%02d\""):format(floor(inches / 12), inches % 12)
end
function D.fmtWeight(hg)
  if not hg then return "---.- lbs." end
  local tenths = floor(hg * 2.20462 + 0.5)
  return ("%d.%d lbs."):format(floor(tenths / 10), tenths % 10)
end

-- the slider's stops (zukan_hw_data member 0): {height dm, weight hg}
function D.stops(search)
  if search and search.stops and search.stops[D.STOPS] then return search.stops end
  -- fallback: an even spread to the cartridge's last stop (999 / 9999)
  local t = {}
  for k = 0, D.STOPS do
    t[k] = { floor(999 * (k / D.STOPS) ^ 3 + 0.5), floor(9999 * (k / D.STOPS) ^ 3 + 0.5) }
  end
  return t
end

-- ------------------------------------------------------------- the lists --

local function nameOf(game, sp)
  local def = ((game.data or {}).pokemon or {})[sp]
  return def and def.name or ""
end

local function sortedBy(game, search, ids, key, desc)
  local vals = {}
  for _, sp in ipairs(ids) do
    local v
    if key == "name" then v = nameOf(game, sp):upper()
    elseif key == "height" then v = D.height(game, search, sp) or 0
    else v = D.weight(game, search, sp) or 0 end
    vals[sp] = v
  end
  local out = {}
  for i, sp in ipairs(ids) do out[i] = sp end
  table.sort(out, function(a, b)
    if vals[a] == vals[b] then return a < b end
    if desc then return vals[a] > vals[b] end
    return vals[a] < vals[b]
  end)
  return out
end

-- every species the lists can name (1..493)
local function allSpecies()
  local t = {}
  for i = 1, 493 do t[i] = i end
  return t
end

function D.sortList(game, search, order)
  local key = ({ [1] = "alphabetical", [2] = "heaviest", [3] = "lightest", [4] = "tallest", [5] = "shortest" })[order]
  if not key then return nil end
  if search and search.sorts and search.sorts[key] and #search.sorts[key] > 0 then return search.sorts[key] end
  local all = allSpecies()
  if key == "alphabetical" then return sortedBy(game, search, all, "name") end
  if key == "heaviest" then return sortedBy(game, search, all, "weight", true) end
  if key == "lightest" then return sortedBy(game, search, all, "weight") end
  if key == "tallest" then return sortedBy(game, search, all, "height", true) end
  return sortedBy(game, search, all, "height")
end

function D.letterList(game, search, letter)
  if search and search.letters and search.letters[letter] then return search.letters[letter] end
  local want = string.char(65 + letter)
  local t = {}
  for i = 1, 493 do if nameOf(game, i):sub(1, 1):upper() == want then t[#t + 1] = i end end
  return t
end

local TYPE_NAMES = { "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
  "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK" }
D.TYPE_NAMES = TYPE_NAMES
function D.typeList(game, search, t)
  if search and search.types and search.types[t] then return search.types[t] end
  local want = TYPE_NAMES[t + 1]
  local out = {}
  for i = 1, 493 do
    local def = ((game.data or {}).pokemon or {})[i]
    for _, ty in ipairs((def and def.types) or {}) do
      if tostring(ty):upper() == want then out[#out + 1] = i; break end
    end
  end
  return out
end

function D.bodyList(search, cell)
  local style = D.BODY_OF_CELL[cell]
  if style and search and search.bodies and search.bodies[style] then return search.bodies[style] end
  return nil -- no data: the filter keeps everything
end

-- ------------------------------------------------------------- the areas --

-- the Kanto half of the cartridge's map (for the encounter-scan fallback)
local KANTO = {}
for _, n in ipairs({ "Pallet Town", "Viridian City", "Pewter City", "Cerulean City", "Vermilion City", "Lavender Town",
  "Celadon City", "Fuchsia City", "Saffron City", "Cinnabar Island", "Indigo Plateau", "Mt. Moon", "Rock Tunnel",
  "Viridian Forest", "Seafoam Islands", "Cerulean Cave", "Power Plant", "Victory Road", "Mt. Silver", "Mt. Silver Cave",
  "Route 28" }) do KANTO[n] = true end
for r = 1, 25 do KANTO["Route " .. r] = true end
local function isKanto(label)
  if KANTO[label] then return true end
  return tostring(label):find("^DIGLETT") ~= nil
end
D.isKanto = isKanto

local function slotsHave(list, species)
  for _, s in pairs(list or {}) do
    if type(s) == "table" then
      if s.species == species then return true end
    elseif s == species then return true end
  end
  return false
end

-- where `species` is met, by map name: { {label=, kanto=, times={morning=,
-- day=, night=}} }, sorted by name (the cartridge sorts by
-- sMapIDs_Alphabetical, ov18_021E8A00)
function D.areas(game, species)
  local data = game.data or {}
  local byLabel, out = {}, {}
  for id, map in pairs(data.maps or {}) do
    local area = map.encounters and (data.encounters or {})[map.encounters]
    if type(area) == "table" then
      local times = {}
      local anyTime = false
      if (tonumber(area.grassRate) or 0) > 0 then
        local timed = area.timed or {}
        local hasTimed = false
        for _, t in ipairs({ "morning", "day", "night" }) do
          for _, v in pairs(timed[t] or {}) do if (tonumber(v) or 0) ~= 0 then hasTimed = true end end
        end
        if hasTimed then
          for _, t in ipairs({ "morning", "day", "night" }) do
            if slotsHave(timed[t], species) then times[t] = true end
          end
        elseif slotsHave(area.grass, species) then anyTime = true end
      end
      for _, method in ipairs({ "surf", "oldRod", "goodRod", "superRod", "rockSmash" }) do
        local block = area[method]
        if type(block) == "table" and (tonumber(block.rate) or 0) > 0 and slotsHave(block.slots, species) then anyTime = true end
      end
      if slotsHave(area.hgssSwarm, species) then anyTime = true end
      if anyTime then times.morning, times.day, times.night = true, true, true end
      if times.morning or times.day or times.night then
        local label = map.label or tostring(id)
        local rec = byLabel[label]
        if not rec then
          rec = { label = label, kanto = isKanto(label), times = {} }
          byLabel[label] = rec
          out[#out + 1] = rec
        end
        for t in pairs(times) do rec.times[t] = true end
      end
    end
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

function D.areaFlags(game, search, species)
  if search and search.areaFlags and search.areaFlags[species] then return search.areaFlags[species] end
  local flags = 8
  for _, rec in ipairs(D.areas(game, species)) do
    flags = bor(flags, rec.kanto and 2 or 1)
  end
  if flags == 8 then flags = bor(flags, 4) end
  return flags
end

-- ------------------------------------------- the areas, from zukan_enc --
-- When the cache carries `gen4_zukan_enc` (src/import/Gen4ZukanEnc.lua) the
-- AREA list and its map markers are the cartridge's. READ FROM CODE
-- (pokeheartgold ov18_021E5C40.c ov18_021E8528 .. ov18_021E8B78, asm
-- overlay_18 ov18_021F04C0 / 41C4 / 42E4 / 463C / 47C0 / 47F8 / 48AC):
--   * the lists: overworld methods 3 + time (bit 0) and 7 (bit 1), then
--     dungeon methods time (bit 0) and 6 (bit 1); a place's x picks its
--     region (x < 22 Johto); Kanto folds Route 2 East into Route 2 and
--     Route 16 East into Route 16; row 0 is the whole region (bank 802 134
--     Johto / 135 Kanto), the rest are sorted by sMapIDs_Alphabetical with
--     the cartridge's own swap loop and named by their map section
--   * the markers: an overworld {x, y, w, h} -> anim by size (w 1: h 1 -> 0,
--     2 -> 6, 3 -> 7, 4 -> 8, 5 -> 9; w 2: h 1 -> 1 else 10; w 3: h 1 -> 2
--     else 11; w 4 -> 3, 5 -> 4, 6 -> 5) at ((x - 22 * region) * 8 + w * 4 +
--     64, y * 8 + h * 4 + 40); Route 2 / 2 East {32, 4, 1, 3}, Route 10
--     w 1 h 2, Route 16 / 16 East {35, 8, 2, 1}; a dungeon at ((x - 22 *
--     region) * 8 + 68, y * 8 + 44), anim 0, Victory Road anim 6 y + 4,
--     National Park x + 4 y + 4, the Ruins of Alph anim 6 y + 4; Diglett's
--     Cave, Ice Path and Dark Cave add their other mouths (47C0 / 47F8)
--   * row 0 shows every marker, another row only its own; the shown set
--     swaps each blink between the timed places (palette 4) and the special
--     ones (palette 5): 15 frames in, 15 out (ov18_021EE26C)
local function encMapId(Z, rec)
  if rec.dungeon then return Z.HG_DUNGEONS[rec.idx + 1] end
  return Z.HG_OVERWORLDS[rec.idx + 1]
end

function D.encAvailable(game)
  local enc = game and game.data and game.data.gen4_zukan_enc
  return enc and enc.family == "hgss" and enc.methods ~= nil or false
end

function D.encAreas(game, species, time, region)
  local enc = game.data.gen4_zukan_enc
  local Z = require("src.import.Gen4ZukanEnc")
  local function list(m) return ((enc.methods or {})[m] or {})[species] or {} end
  local rows = { { all = true, flags = 0 } }
  local function owIndexOf(mapId)
    for i = 1, #Z.HG_OVERWORLDS do if Z.HG_OVERWORLDS[i] == mapId then return i - 1 end end
    return 1
  end
  local function inRegion(x) return (region == 0 and x < 22) or (region ~= 0 and x >= 22) end
  local function addOw(lst, b)
    for _, idx in ipairs(lst) do
      local ow = (enc.overworlds or {})[idx]
      if inRegion(ow and ow.x or 0) then
        local id = idx
        if region ~= 0 then
          local mid = Z.HG_OVERWORLDS[idx + 1]
          if mid == 10 or mid == 414 then id = owIndexOf(10)
          elseif mid == 24 or mid == 422 then id = owIndexOf(24) end
        end
        local found
        for _, r in ipairs(rows) do if not r.all and not r.dungeon and r.idx == id then found = r end end
        if found then found.flags = bor(found.flags, bit.lshift(1, b))
        else rows[#rows + 1] = { idx = id, flags = bit.lshift(1, b) } end
      end
    end
  end
  local function addDg(lst, b)
    for _, idx in ipairs(lst) do
      local dg = (enc.dungeons or {})[idx]
      if inRegion(dg and dg.x or 0) then
        local found
        for _, r in ipairs(rows) do if r.dungeon and r.idx == idx then found = r end end
        if found then found.flags = bor(found.flags, bit.lshift(1, b))
        else rows[#rows + 1] = { idx = idx, dungeon = true, flags = bit.lshift(1, b) } end
      end
    end
  end
  addOw(list(3 + time), 0); addOw(list(7), 1)
  addDg(list(time), 0); addDg(list(6), 1)
  -- ov18_021E8A00, swaps and all
  local alpha = {}
  for i, id in ipairs(Z.HG_ALPHABETICAL) do if alpha[id] == nil then alpha[id] = i - 1 end end
  local function key(r) return alpha[encMapId(Z, r)] or 0 end
  for i = 2, #rows - 1 do
    local ki = key(rows[i])
    for j = i + 1, #rows do
      local kj = key(rows[j])
      if ki > kj then rows[i], rows[j] = rows[j], rows[i]; ki = kj end
    end
  end
  local headers = require("src.ui.HgssPokegear").headers(game.data)
  for _, r in ipairs(rows) do
    if r.all then
      r.label = text(game, 802, region == 0 and 134 or 135) or (region == 0 and "Johto" or "Kanto")
    else
      r.mapId = encMapId(Z, r)
      local h = headers and headers[r.mapId]
      r.label = (h and h.label) or ("MAP " .. tostring(r.mapId))
    end
  end
  return rows
end

-- ov18_021F41C4 / 42E4: a row's marker {anim, x, y} and its extra mouths
D.ENC_EXTRA = { [1] = { { 0x94, 0x4c } }, [2] = { { 0xec, 0x4c } }, [4] = { { 0xe4, 0x5c }, { 0xdc, 0x7c } } }
function D.encMarker(game, rec, region)
  local enc = game.data.gen4_zukan_enc
  local Z = require("src.import.Gen4ZukanEnc")
  if rec.all then return nil, 0 end
  if not rec.dungeon then
    local mid = Z.HG_OVERWORLDS[rec.idx + 1]
    local ow = (enc.overworlds or {})[rec.idx] or { x = 0, y = 0, w = 1, h = 1 }
    local x0, y0, w, h = ow.x, ow.y, ow.w, ow.h
    if mid == 10 or mid == 414 then x0, y0, w, h = 0x20, 4, 1, 3
    elseif mid == 18 then w, h = 1, 2
    elseif mid == 24 or mid == 422 then x0, y0, w, h = 0x23, 8, 2, 1 end
    local anim = 0
    if w == 1 then anim = ({ [1] = 0, [2] = 6, [3] = 7, [4] = 8, [5] = 9 })[h] or 0
    elseif w == 2 then anim = h == 1 and 1 or 10
    elseif w == 3 then anim = h == 1 and 2 or 11
    elseif w == 4 then anim = 3 elseif w == 5 then anim = 4 elseif w == 6 then anim = 5 end
    return { anim = anim, x = (x0 - 22 * region) * 8 + math.floor(w * 8 / 2) + 0x40,
      y = y0 * 8 + math.floor(h * 8 / 2) + 0x28 }, 0
  end
  local dg = (enc.dungeons or {})[rec.idx] or { x = 0, y = 0 }
  local m = { anim = 0, x = (dg.x - 22 * region) * 8 + 0x44, y = dg.y * 8 + 0x2c }
  local mid = Z.HG_DUNGEONS[rec.idx + 1] or 0
  if mid == 0x7c or mid == 0xb2 or mid == 0xb3 then m.anim = 6; m.y = m.y + 4
  elseif mid == 0x60 or mid == 0x1e7 then m.x = m.x + 4; m.y = m.y + 4
  elseif mid == 0x71 or mid == 0x13b or (mid >= 0x1ea and mid <= 0x1ec) then m.anim = 6; m.y = m.y + 4 end
  local extra = 0
  if mid == 0x6a then extra = 1
  elseif mid == 0x78 or (mid >= 0xed and mid <= 0xef) then extra = 2
  elseif mid == 0x7b or mid == 0xb0 then extra = 4 end
  return m, extra
end

-- ------------------------------------------------------------ the search --

local function filter(list, keep)
  local out = {}
  for _, sp in ipairs(list) do if keep(sp) then out[#out + 1] = sp end end
  return out
end
-- ov18_021F8764: the members of `list` (the current results) in `by`'s
-- order, uncaught ones only when keepUncaught
-- (the sort passes its list as the outer one, so the results take the sort's
-- order; the letter / type / body filters pass the current results, which
-- keep theirs -- see keepOrder)
local function intersectInOrder(list, by, keepUncaught, owned)
  local inList = {}
  for _, sp in ipairs(list) do inList[sp] = true end
  local out = {}
  for _, sp in ipairs(by) do
    if inList[sp] and (keepUncaught or owned(sp)) then out[#out + 1] = sp; inList[sp] = nil end
  end
  return out
end

local function keepOrder(list, by, keepUncaught, owned)
  local inBy = {}
  for _, sp in ipairs(by) do inBy[sp] = true end
  return filter(list, function(sp) return inBy[sp] and (keepUncaught or owned(sp)) end)
end

-- dex: the HgssPokedex (status(), order, hasNational); c: the criteria.
-- Returns the result list (species ids) and whether some data was missing.
function D.results(dex, c)
  local game = dex.game
  local search = (dex.art or {}).search
  local function owned(sp) return dex:status(sp) == "owned" end
  local out = {}
  for _, sp in ipairs(dex.baseOrder or dex.order or {}) do
    if dex:status(sp) then out[#out + 1] = sp end
  end
  local missing = false
  if c.order and c.order > 0 then
    out = intersectInOrder(out, D.sortList(game, search, c.order) or out, c.order == 1, owned)
  end
  if c.letter and c.letter < 26 then
    out = keepOrder(out, D.letterList(game, search, c.letter), true, owned)
  end
  for _, t in ipairs({ c.type1, c.type2 }) do
    if t and t < 17 then out = keepOrder(out, D.typeList(game, search, t), false, owned) end
  end
  if c.body and c.body < 14 then
    local list = D.bodyList(search, c.body)
    if list then out = keepOrder(out, list, true, owned) else missing = true end
  end
  if c.area and c.area < 3 then
    local mask = bit.lshift(1, c.area)
    if not dex.hasNational and c.area == 2 then
      out = filter(out, function(sp) local f = D.areaFlags(game, search, sp); return band(f, 6) ~= 0 and band(f, 1) == 0 end)
    else
      out = filter(out, function(sp) return band(D.areaFlags(game, search, sp), mask) ~= 0 end)
    end
  end
  local stops = D.stops(search)
  if not (c.hmin == 0 and c.hmax == D.STOPS) then
    local lo, hi = stops[c.hmin][1], stops[c.hmax][1]
    out = filter(out, function(sp)
      local h = D.height(game, search, sp)
      return owned(sp) and h and h >= lo and h <= hi
    end)
  end
  if not (c.wmin == 0 and c.wmax == D.STOPS) then
    local lo, hi = stops[c.wmin][2], stops[c.wmax][2]
    out = filter(out, function(sp)
      local w = D.weight(game, search, sp)
      return owned(sp) and w and w >= lo and w <= hi
    end)
  end
  return out, missing
end

-- ------------------------------------------------------------- the forms --

local FORM_LABEL = {
  [201] = { base = 69, exc = "!", que = "?" },
  [351] = { base = 160, sunny = 161, rainy = 162, snowy = 163 },
  [421] = { base = 164, sunny = 165 },
  [386] = { base = 145, attack = 146, defense = 147, speed = 148 },
  [412] = { base = 118, sandy = 119, trash = 120 },
  [413] = { base = 118, sandy = 119, trash = 120 },
  [422] = { base = 116, east_sea = 117 },
  [423] = { base = 116, east_sea = 117 },
  [479] = { base = 153, heat = 154, wash = 155, frost = 156, fan = 157, mow = 158 },
  [487] = { base = 151, origin = 152 },
  [492] = { base = 149, sky = 150 },
}
for i = 1, 25 do FORM_LABEL[201][string.char(97 + i)] = 69 + i end

-- the forms the FORMS page lists: { {key=, label=, female=bool} }
function D.forms(game, species)
  local id = tonumber(species)
  local data = game.data or {}
  local def = (data.pokemon or {})[id] or {}
  local Forms = require("src.pokemon.Gen4Forms")
  local labels = FORM_LABEL[id]
  local function label(key)
    local v = labels and labels[key]
    if type(v) == "number" then return text(game, 802, v) or key end
    return v or key
  end
  local out = {}
  if id == 351 or id == 421 then
    for _, key in ipairs(id == 351 and { "base", "sunny", "rainy", "snowy" } or { "base", "sunny" }) do
      out[#out + 1] = { key = key, label = label(key) }
    end
    return out
  end
  -- Pichu: male / female / Spiky-eared in the order seen (Gen45DexRecord;
  -- ov18_021E8254 lists it with the tracked-form species; 802 #166
  -- "Spiky-eared"). Its picture is def.forms.spiky (hgss-otherpoke-v1); an
  -- older import shows the base one.
  local pichu = id == 172 and ((game.save or {}).pokedex or {}).hgssPichuForms
  if pichu and #pichu > 0 then
    for _, v in ipairs(pichu) do
      if v == 2 then
        local has = def.forms and def.forms.spiky
        out[#out + 1] = { key = has and "spiky" or "base", label = text(game, 802, 166) or "Spiky-eared", spiky = true }
      elseif v == 1 then out[#out + 1] = { key = "base", label = text(game, 802, 115) or "Female", female = true }
      else out[#out + 1] = { key = "base", label = text(game, 802, 114) or "Male" } end
    end
    return out
  end
  if labels then
    local seen = Forms.seen((game.save or {}).pokedex, id)
    for _, key in ipairs(seen) do
      if def.forms and def.forms[key] then out[#out + 1] = { key = key, label = label(key) } end
    end
    if #out == 0 then out[1] = { key = "base", label = label("base") } end
    return out
  end
  -- every other species: the genders seen, first-seen first
  -- (ov18_021E8254 default case, from Gen45DexRecord); a save from before
  -- the genders were kept lists every gender the species has
  local seenG = require("src.pokemon.Gen45DexRecord").gendersSeen(game, id)
  if #seenG > 0 then
    for _, g in ipairs(seenG) do
      if g == "none" then out[#out + 1] = { key = "base", label = text(game, 802, 121) or "One form" }
      elseif g == "female" then out[#out + 1] = { key = "base", label = text(game, 802, 115) or "Female", female = true }
      else out[#out + 1] = { key = "base", label = text(game, 802, 114) or "Male" } end
    end
    return out
  end
  local ratio = tonumber(def.genderRatio)
  if ratio == 255 or ratio == nil then
    out[1] = { key = "base", label = text(game, 802, 121) or "One form" }
  elseif ratio == 254 then
    out[1] = { key = "base", label = text(game, 802, 115) or "Female", female = true }
  elseif ratio == 0 then
    out[1] = { key = "base", label = text(game, 802, 114) or "Male" }
  else
    out[1] = { key = "base", label = text(game, 802, 114) or "Male" }
    out[2] = { key = "base", label = text(game, 802, 115) or "Female", female = true }
  end
  return out
end

-- a form's front / back picture
function D.formPicture(game, species, form, side)
  local data = game.data or {}
  local def = (data.pokemon or {})[species]
  if not def then return nil end
  if form and form.female then
    local p = side == "back" and def.spriteBackFemale or def.spriteFrontFemale
    if p then return p end
  end
  local rec = form and form.key ~= "base" and def.forms and def.forms[form.key]
  if rec then
    local p = side == "back" and (rec.spriteBack or rec.back) or (rec.spriteFront or rec.front)
    if p then return p end
  end
  return side == "back" and def.spriteBack or def.spriteFront
end

return D
