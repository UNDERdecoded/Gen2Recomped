-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- What lives in the grass: a map's wild encounter table.
--
-- ONE TABLE PER MAP, NOT PER PATCH, and that is worth stating up front because
-- it is the first thing anyone expects to be otherwise. Gen 2 rolls every
-- square of tall grass on Route 29 against the same seven slots; there is no
-- record anywhere that says "this corner has Rattata and that one has
-- Sentret", and the roll has nowhere to read one from. What the cartridge does
-- have is THREE of those tables -- morning, day and night -- plus water and
-- three fishing rods, which is where the variety actually lives. This panel
-- edits exactly that, and says so rather than offering a per-patch control
-- that would quietly do nothing.
--
-- THE SLOTS ARE POSITIONAL. Slot 1 is the 77/256 bucket and slot 4 the 25/256
-- one, so "which Pokemon is common here" is a statement about WHERE in the
-- list it sits, not about the list containing it. The panel shows each slot's
-- own share for that reason: a reader moving a species from slot 7 to slot 1
-- is making it eight times more likely, and nothing else on screen would say
-- so.

local Theme = require("Theme")
local PAL = Theme.PAL
local MapEdits = require("tools.map-editor.MapEdits")

local Wilds = {}

local TERRAINS = { { id = "grass", label = "GRASS" },
                   { id = "water", label = "WATER" } }
local TIMES = { { id = "day", label = "DAY" },
                { id = "morn", label = "MORN" },
                { id = "nite", label = "NIGHT" } }

local function store(S)
  if not S.mapEdits then S.mapEdits = (MapEdits.load()) end
  return S.mapEdits
end

local function game(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring(S.version or v or "unknown")
end

local function markEdited(S)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
end

local function speciesLabel(S, id)
  local ok, Catalog = pcall(require, "Catalog")
  if ok and type(Catalog) == "table" and Catalog.speciesLabel then
    local okL, label = pcall(Catalog.speciesLabel, S.data, id)
    if okL and label then return label end
  end
  return tostring(id or "?")
end

-- Every species the import produced, in dex order -- which is the order a
-- reader is thinking in, and is not the order the ids sort in as strings.
local function speciesIds(S)
  if S._wildSpecies then return S._wildSpecies end
  local out = {}
  for id, entry in pairs((S.data and S.data.pokemon) or {}) do
    if type(entry) == "table" then
      out[#out + 1] = { id = id, n = tonumber(entry.index or entry.dex)
                        or tonumber(id:match("(%d+)$") or "") or 0 }
    end
  end
  table.sort(out, function(a, b)
    if a.n ~= b.n then return a.n < b.n end
    return a.id < b.id
  end)
  local ids = {}
  for i, e in ipairs(out) do ids[i] = e.id end
  S._wildSpecies = ids
  return ids
end

local function baseRecord(S)
  local enc = S.data and S.data.encounters
  return enc and enc[S.mapId or ""] or nil
end

-- The table being edited, and whether it is MINE or the cartridge's.
local function currentTable(S)
  local terrain = S.wildTerrain or "grass"
  local time = (terrain == "grass") and (S.wildTime or "day") or "day"
  return MapEdits.wildTable(store(S), game(S), S.mapId, baseRecord(S),
                            terrain, time)
end

-- Every edit goes through here, and every one of them writes the WHOLE table.
--
-- A slot list is seven entries whose meaning is positional, so there is no
-- such thing as a patch of one: changing slot 4's species means storing a
-- seven-entry list with a different slot 4. The copy is made from whatever is
-- resolving right now -- mine if I have edited this terrain, the cartridge's
-- if I have not -- so a first edit inherits the map rather than blanking it.
local function mutate(S, fn)
  local terrain = S.wildTerrain or "grass"
  local time = (terrain == "grass") and (S.wildTime or "day") or "day"
  local cur = currentTable(S) or { rate = 0, slots = {} }
  local next_ = { rate = cur.rate or 0, slots = {}, buckets = cur.buckets }
  for i, slot in ipairs(cur.slots or {}) do
    next_.slots[i] = { species = slot.species, level = slot.level }
  end
  fn(next_)
  MapEdits.setWildTable(store(S), game(S), S.mapId, terrain, time, next_)
  markEdited(S)
end

-- What share of the roll a slot actually gets.
--
-- The buckets are CUMULATIVE thresholds out of 256, so a slot's own share is
-- the gap between its threshold and the one before it. Shown because the
-- position IS the probability and nothing else on screen says so -- a reader
-- moving a species from slot 7 to slot 1 is making it eight times more likely.
local DEFAULT_BUCKETS = { 77, 154, 205, 230, 243, 253, 256 }

local function shareOf(tbl, i)
  local b = (tbl and tbl.buckets) or DEFAULT_BUCKETS
  local hi = b[i]
  if not hi then return nil end
  local lo = b[i - 1] or 0
  return (hi - lo) / 256
end

function Wilds.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 16 * s
  local fieldH = 30 * s

  if not S.mapId then
    Kit.emptyBox(x, y, w, h, "Pick a map first.")
    return
  end

  S.wildTerrain = S.wildTerrain or "grass"
  S.wildTime = S.wildTime or "day"

  Kit.caption(x, y, "WILD ENCOUNTERS - " .. tostring(S.mapId))
  local fy = y + Kit.textHeight("caption") + 6 * s
  Kit.text("small", "one table per map -- every patch of grass rolls the same",
           x, fy, PAL.muted)
  fy = fy + 18 * s

  -- TERRAIN, then TIME. Water has one table and no time of day, so its row
  -- disappears rather than sitting there doing nothing.
  local chipH = 26 * s
  local cw = (w - 6 * s) / 2
  for i, t in ipairs(TERRAINS) do
    if Kit.chip(x + (i - 1) * (cw + 6 * s), fy, cw, chipH, t.label,
                S.wildTerrain == t.id) then
      S.wildTerrain = t.id
    end
  end
  fy = fy + chipH + 6 * s

  if S.wildTerrain == "grass" then
    local tw = (w - 12 * s) / 3
    for i, t in ipairs(TIMES) do
      if Kit.chip(x + (i - 1) * (tw + 6 * s), fy, tw, chipH, t.label,
                  S.wildTime == t.id) then
        S.wildTime = t.id
      end
    end
    fy = fy + chipH + 8 * s
  else
    fy = fy + 2 * s
  end

  local tbl, mine = currentTable(S)
  if not tbl then
    Kit.text("small", "this map has no encounter record at all", x, fy)
    fy = fy + 18 * s
    tbl = { rate = 0, slots = {} }
  end

  -- THE RATE, which is the one number that decides whether anything happens.
  --
  -- Out of 256 per step: the game rolls and starts a battle when the roll is
  -- under it. Shown as a percentage as well because "10" is not a quantity
  -- anybody has intuition for and "3.9% a step" is.
  Kit.text("body", "RATE", x, fy + 7 * s)
  local rate = tonumber(tbl.rate) or 0
  if Kit.stepper(x + 56 * s, fy, 28 * s, fieldH, "-") then
    mutate(S, function(t) t.rate = math.max(0, (t.rate or 0) - 1) end)
  end
  Kit.textCenter("body", tostring(rate), x + 84 * s, fy + 7 * s, 48 * s)
  if Kit.stepper(x + 132 * s, fy, 28 * s, fieldH, "+") then
    mutate(S, function(t) t.rate = math.min(255, (t.rate or 0) + 1) end)
  end
  Kit.text("small", rate > 0
    and string.format("%.1f%% of steps", rate / 256 * 100)
    or "nothing spawns here", x + 168 * s, fy + 8 * s, PAL.muted)
  fy = fy + fieldH + 8 * s

  Kit.text("small", mine and "* your table" or "the cartridge's table",
           x, fy, mine and PAL.yellow or PAL.muted)
  if mine and Kit.button(x + w - 110 * s, fy - 6 * s, 110 * s, 24 * s,
                         "REVERT", { font = "small" }) then
    local terrain = S.wildTerrain
    local time = (terrain == "grass") and S.wildTime or "day"
    MapEdits.setWildTable(store(S), game(S), S.mapId, terrain, time, nil)
    markEdited(S)
  end
  fy = fy + 20 * s

  -- THE SLOTS.
  local rowH = 34 * s
  local slots = tbl.slots or {}
  local count = math.max(#slots, 7)
  for i = 1, count do
    local slot = slots[i]
    local share = shareOf(tbl, i)
    local ry = fy + (i - 1) * rowH
    if ry + rowH > y + h then break end

    Kit.text("small", share and string.format("%d  %.0f%%", i, share * 100)
             or tostring(i), x, ry + 9 * s, PAL.muted)

    local bw = 150 * s
    if Kit.button(x + 52 * s, ry, w - 52 * s - bw - 8 * s, rowH - 6 * s,
                  slot and speciesLabel(S, slot.species) or "(empty)",
                  { font = "small" }) then
      S.wildPick = (S.wildPick == i) and nil or i
      S.wildQuery = ""
    end

    if slot then
      if Kit.stepper(x + w - bw, ry, 26 * s, rowH - 6 * s, "-") then
        mutate(S, function(t)
          t.slots[i].level = math.max(1, (t.slots[i].level or 5) - 1)
        end)
      end
      Kit.textCenter("small", "L" .. tostring(slot.level or 0),
                     x + w - bw + 28 * s, ry + 9 * s, 44 * s)
      if Kit.stepper(x + w - bw + 74 * s, ry, 26 * s, rowH - 6 * s, "+") then
        mutate(S, function(t)
          t.slots[i].level = math.min(100, (t.slots[i].level or 5) + 1)
        end)
      end
      if Kit.button(x + w - 44 * s, ry, 44 * s, rowH - 6 * s, "x",
                    { font = "small" }) then
        mutate(S, function(t) t.slots[i] = nil end)
      end
    end
  end
  fy = fy + count * rowH + 6 * s

  Kit.text("small",
    "slot 1 is the commonest; the share is fixed by position, not by species",
    x, fy, PAL.muted)

  -- the picker floats over the rows it edits
  Wilds.drawPicker(S, Kit, x, y, w, h)
  return fy + 18 * s
end

-- The species list, drawn LAST and over everything -- Kit has no z-order, so
-- "on top" and "drawn last" are the same statement.
function Wilds.drawPicker(S, Kit, x, y, w, h)
  local i = S.wildPick
  if not i then return false end
  local s = Kit.scale
  local pw = math.min(w, 380 * s)
  local ph = math.min(h, 460 * s)
  local px0 = x + (w - pw) / 2
  local py0 = y + (h - ph) / 2
  if Kit.tapAway("wild-pick", px0, py0, pw, ph) then
    S.wildPick = nil
    return true
  end

  love.graphics.setColor(0.03, 0.04, 0.11, 0.55)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", px0, py0, pw, ph, 14 * s, 14 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(px0, py0, pw, ph)

  local pad = 16 * s
  Kit.caption(px0 + pad, py0 + pad, "SLOT " .. tostring(i))
  local closeW = 28 * s
  if Kit.button(px0 + pw - pad - closeW, py0 + pad - 4 * s, closeW, 24 * s, "x",
                { font = "small", radius = 6 * s }) then
    S.wildPick = nil
    return true
  end
  local cy = py0 + pad + Kit.textHeight("caption") + 8 * s
  local fieldH = 30 * s
  S.wildQuery = Kit.textfield("wild-q", px0 + pad, cy, pw - 2 * pad, fieldH,
                              S.wildQuery or "", "search Pokemon...")
  cy = cy + fieldH + 8 * s

  local q = (S.wildQuery or ""):lower()
  local shown = 0
  for _, id in ipairs(speciesIds(S)) do
    local label = speciesLabel(S, id)
    if q == "" or label:lower():find(q, 1, true) or id:lower():find(q, 1, true) then
      shown = shown + 1
      if shown > 10 then break end
      if Kit.button(px0 + pad, cy, pw - 2 * pad, fieldH - 2 * s, label,
                    { font = "small" }) then
        mutate(S, function(t)
          t.slots[i] = t.slots[i] or { level = 5 }
          t.slots[i].species = id
          t.slots[i].level = t.slots[i].level or 5
        end)
        S.wildPick = nil
      end
      cy = cy + fieldH
    end
  end
  if shown == 0 then
    Kit.text("small", "no Pokemon matches that", px0 + pad, cy)
  elseif shown > 10 then
    Kit.text("small", "keep typing to narrow it", px0 + pad, cy)
  end
  return true
end

function Wilds.wheelmoved(S, dy)
  if S.wildPick then return end
  S.wildScroll = math.max(0, (S.wildScroll or 0) - (dy or 0) * 3)
end

function Wilds.keypressed(S, key)
  if key == "escape" and S.wildPick then S.wildPick = nil end
end

return Wilds
