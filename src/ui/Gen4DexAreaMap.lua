-- PLATINUM'S POKEDEX AREA PAGE: the cartridge's map of where a species lives,
-- by time of day, out of zukan_enc (src/import/Gen4ZukanEnc.lua, cache module
-- `gen4_zukan_enc`). Used by src/ui/Gen4Pokedex.lua's AREA tab.
--
-- READ FROM CODE (pokeplatinum src/applications/pokedex/ov21_021DC9BC.c,
-- pokedex_enc_data.c, pokedex_field_map.c, ov21_021DDD2C.c):
--   * the time: morning -> 0, day / twilight -> 1, night / late night -> 2
--     (PokedexEncounters_PopulateEncounterCollection); LEFT / RIGHT step it
--     (clamped, no sound) once DOWN has moved the focus onto the bottom
--     screen's slider, UP gives it back (ov21_021E3EEC, ov21_021DE358); the
--     slider can be dragged, x / 85 picking the time (ov21_021DE3D0)
--   * the lists: the time's dungeon and field lists, and the special ones
--     (special, or special National Dex once the National Dex is had); a
--     special place already on the timed list is not drawn twice; the four
--     hidden places' entries are dropped while they are hidden -- only Spring
--     Path has one, dungeon 10 (springPathDungeons)
--   * the fields: each listed field ORs its cell matrix into a 30 x 30 grid,
--     the empty cells around them become edge pieces (PokedexFieldMap's
--     neighbour table, types 2-47), the special grid is drawn first and the
--     timed one over it, 5 x 5 pixels a cell from (89, 30)
--   * the dungeons: dungeon_highlight anim 2 (timed) / 3 (special), Mt.
--     Coronet 0 / 1, at (92 + x * 5, 32 + y * 5); Feebas uses 4 / 5 and
--     y - 18 (its Mt. Coronet B1F pool)
--   * the blink (ov21_021DDC14): 32 frames of the fields fading in and out
--     (alpha 0 -> 16 -> 0, added onto the map, G2_SetBlendAlpha BG1|BG3 over
--     BG3, ev 16), then 32 of the dungeons the same way, and round again
--   * "Area Unknown": size_check_icons anim 2 at (160, 96) with the words
--     centred on it, when nothing at all is drawn (ov21_021DD9E8)
--   * the time's name (bank pokedex 36-38) centred in 72 pixels from x 8,
--     y 32; the species' picture at (40, 120) (ov21_021DDCF4)
--   * the hidden places' map pieces stamp BG3 at tiles (13,8) Newmoon Island,
--     (28,7) Seabreak Path, (11,8) Fullmoon Island, (25,16) Spring Path once
--     SystemVars_CheckHiddenLocation says they are found
-- NOT DONE: the page's fade in and out, the slider's palette roll between
-- times (drawn straight in the new time's colours).

local M = {}

local bit = require("bit")
local band, bor = bit.band, bit.bor

local GRID = 30
local FN_WEST, FN_EAST, FN_SOUTH, FN_NORTH = 1, 2, 4, 8
local FN_SW, FN_NW, FN_SE, FN_NE = 16, 32, 64, 128

-- GetNeighborType (pokedex_field_map.c), neighbour mask -> piece
local PIECE = {
  [0] = 0, [FN_WEST] = 2, [FN_EAST] = 3, [FN_SOUTH] = 4, [FN_NORTH] = 5,
  [FN_WEST + FN_EAST] = 6, [FN_WEST + FN_SOUTH] = 7, [FN_WEST + FN_NORTH] = 8,
  [FN_EAST + FN_SOUTH] = 9, [FN_EAST + FN_NORTH] = 10, [FN_SOUTH + FN_NORTH] = 11,
  [FN_WEST + FN_EAST + FN_SOUTH] = 12, [FN_WEST + FN_EAST + FN_NORTH] = 13,
  [FN_WEST + FN_SOUTH + FN_NORTH] = 14, [FN_EAST + FN_SOUTH + FN_NORTH] = 15,
  [FN_WEST + FN_EAST + FN_SOUTH + FN_NORTH] = 16,
  [FN_SW] = 17, [FN_NW] = 18, [FN_SE] = 19, [FN_NE] = 20,
  [FN_SW + FN_NW] = 21, [FN_SW + FN_SE] = 22, [FN_SW + FN_NE] = 23, [FN_NW + FN_SE] = 24,
  [FN_NW + FN_NE] = 25, [FN_SE + FN_NE] = 26,
  [FN_SW + FN_NW + FN_SE] = 27, [FN_SW + FN_NW + FN_NE] = 28, [FN_SW + FN_SE + FN_NE] = 29,
  [FN_NW + FN_SE + FN_NE] = 30, [FN_SW + FN_NW + FN_SE + FN_NE] = 31,
  [FN_WEST + FN_SE + FN_NE] = 32, [FN_EAST + FN_SW + FN_NW] = 33,
  [FN_SOUTH + FN_NW + FN_NE] = 34, [FN_NORTH + FN_SW + FN_SE] = 35,
  [FN_WEST + FN_SOUTH + FN_NE] = 36, [FN_WEST + FN_NORTH + FN_SE] = 37,
  [FN_EAST + FN_SOUTH + FN_NW] = 38, [FN_EAST + FN_NORTH + FN_SW] = 39,
  [FN_WEST + FN_SE] = 40, [FN_WEST + FN_NE] = 41, [FN_EAST + FN_SW] = 42, [FN_EAST + FN_NW] = 43,
  [FN_SOUTH + FN_NW] = 44, [FN_SOUTH + FN_NE] = 45, [FN_NORTH + FN_SW] = 46, [FN_NORTH + FN_SE] = 47,
}
M.PIECE = PIECE

local SPECIES_FEEBAS = 349
-- springPathDungeons (the other three hidden places list nothing)
local HIDDEN_DUNGEONS = { [2] = { 10 } }
-- HIDDEN_LOCATION_* -> the BG3 piece and its tile position
M.HIDDEN_PIECES = {
  { location = 1, key = "pt_map_newmoon_island", tx = 13, ty = 8 },
  { location = 3, key = "pt_map_seabreak_path", tx = 28, ty = 7 },
  { location = 0, key = "pt_map_fullmoon_island", tx = 11, ty = 8 },
  { location = 2, key = "pt_map_spring_path", tx = 25, ty = 16 },
}

-- morning -> 0, day / twilight -> 1, night / late night -> 2
function M.timeForHour(hour)
  local tod = require("src.import.Gen4Encounters").timeOfDayForHour(hour)
  if tod == 0 then return 0 end
  if tod == 1 or tod == 2 then return 1 end
  return 2
end

function M.hiddenVisible(save, location)
  local ok, H = pcall(require, "src.world.Gen4HiddenPaths")
  if not ok or not save then return false end
  local ok2, v = pcall(H.unlocked, save, location)
  return ok2 and v and true or false
end

local function contains(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

-- PokedexEncData_LocateVisibleFields
local function locateFields(grid, fields, list, skip)
  local n = 0
  for _, loc in ipairs(list or {}) do
    if not contains(skip, loc) then
      local f = fields[loc]
      if f then
        for a = f.a0, f.a0 + f.an - 1 do
          for b = f.b0, f.b0 + f.bn - 1 do
            if a >= 0 and a < GRID and b >= 0 and b < GRID then
              local v = f.cells[(a - f.a0) * f.bn + (b - f.b0) + 1] or 0
              grid[a * GRID + b] = bor(grid[a * GRID + b], v)
            end
          end
        end
      end
      n = n + 1
    end
  end
  return n
end

local function at(grid, a, b)
  if a < 0 or a >= GRID or b < 0 or b >= GRID then return -1 end
  return grid[a * GRID + b]
end

-- PokedexFieldMap_SmoothFields ("x" is the first index, "y" the second)
function M.smooth(grid)
  for a = 0, GRID - 1 do
    for b = 0, GRID - 1 do
      if grid[a * GRID + b] == 0 then
        local n = 0
        if at(grid, a - 1, b) == 1 then n = n + FN_WEST end
        if at(grid, a + 1, b) == 1 then n = n + FN_EAST end
        if at(grid, a, b - 1) == 1 then n = n + FN_SOUTH end
        if at(grid, a, b + 1) == 1 then n = n + FN_NORTH end
        if band(n, FN_WEST) == 0 and band(n, FN_SOUTH) == 0 and at(grid, a - 1, b - 1) == 1 then n = n + FN_SW end
        if band(n, FN_WEST) == 0 and band(n, FN_NORTH) == 0 and at(grid, a - 1, b + 1) == 1 then n = n + FN_NW end
        if band(n, FN_EAST) == 0 and band(n, FN_SOUTH) == 0 and at(grid, a + 1, b - 1) == 1 then n = n + FN_SE end
        if band(n, FN_EAST) == 0 and band(n, FN_NORTH) == 0 and at(grid, a + 1, b + 1) == 1 then n = n + FN_NE end
        grid[a * GRID + b] = PIECE[n] or 0
      end
    end
  end
  return grid
end

local function newGrid()
  local g = {}
  for i = 0, GRID * GRID - 1 do g[i] = 0 end
  return g
end

-- compute(enc, species, time, national, visible) -> the page's picture:
-- { timed = grid, special = grid, dungeons = { {x, y, anim} }, unknown }
-- `visible(location)` answers SystemVars_CheckHiddenLocation.
function M.compute(enc, species, time, national, visible)
  local L = enc.lists or {}
  local names = { [0] = "Morning", [1] = "Day", [2] = "Night" }
  local tname = names[time] or "Day"
  local dTimed = (L["dungeon" .. tname] or {})[species] or {}
  local fTimed = (L["field" .. tname] or {})[species] or {}
  local dSpecial = (L[national and "dungeonSpecialNat" or "dungeonSpecial"] or {})[species] or {}
  local fSpecial = (L[national and "fieldSpecialNat" or "fieldSpecial"] or {})[species] or {}
  local hiddenD = {}
  for loc, list in pairs(HIDDEN_DUNGEONS) do
    if not (visible and visible(loc)) then for _, d in ipairs(list) do hiddenD[#hiddenD + 1] = d end end
  end
  local out = { timed = newGrid(), special = newGrid(), dungeons = {} }
  local fields = enc.fields or {}
  local nTimedF = locateFields(out.timed, fields, fTimed, {})
  local nSpecialF = locateFields(out.special, fields, fSpecial, fTimed)
  M.smooth(out.timed); M.smooth(out.special)
  local feebas = species == SPECIES_FEEBAS
  local ox, oy = 92, feebas and (32 - 18) or 32
  local function place(list, skip, anim, coronet)
    local n = 0
    for _, loc in ipairs(list) do
      if not contains(skip, loc) then
        local d = (enc.dungeons or {})[loc]
        if d then
          out.dungeons[#out.dungeons + 1] = { x = ox + d.x * 5, y = oy + d.y * 5, anim = d.coronet and coronet or anim }
        end
        n = n + 1
      end
    end
    return n
  end
  local nTimedD = place(dTimed, hiddenD, 2, feebas and 4 or 0)
  local skip = {}
  for _, v in ipairs(hiddenD) do skip[#skip + 1] = v end
  for _, v in ipairs(dTimed) do skip[#skip + 1] = v end
  local nSpecialD = place(dSpecial, skip, 3, feebas and 5 or 1)
  out.unknown = nTimedF + nSpecialF + nTimedD + nSpecialD == 0
  return out
end

-- ------------------------------------------------------------ drawing --

local function img(dex, key)
  local enc = dex.game.data.gen4_zukan_enc
  local rec = enc and enc.art and enc.art[key]
  return rec and dex:img(rec), rec
end

function M.available(game)
  local enc = game and game.data and game.data.gen4_zukan_enc
  return enc and enc.lists and enc.family ~= "hgss" and true or false
end

-- the page's state, kept on the Pokedex screen
function M.state(dex)
  local s = dex.areaState
  local species = dex:species()
  if not s or s.species ~= species then
    s = { species = species, time = s and s.time or M.timeForHour(tonumber(os.date("%H"))), t = 0, focus = s and s.focus or false }
    dex.areaState = s
  end
  return s
end

function M.picture(dex)
  local s = M.state(dex)
  local key = s.time .. ":" .. tostring(dex.game.save and dex.game.save.pokedex and dex.game.save.pokedex.national)
  if s.key ~= key then
    local save = dex.game.save
    s.pic = M.compute(dex.game.data.gen4_zukan_enc, s.species, s.time,
      ((save or {}).pokedex or {}).national and true or false,
      function(loc) return M.hiddenVisible(save, loc) end)
    s.key = key
  end
  return s.pic
end

-- keys while the AREA tab is up; true when the key was the page's
function M.update(dex, input)
  local s = M.state(dex)
  s.t = s.t + 1
  if s.focus then
    if input:wasPressed("up") then s.focus = false; return true end
    if input:wasPressed("left") then s.time = math.max(0, s.time - 1); return true end
    if input:wasPressed("right") then s.time = math.min(2, s.time + 1); return true end
  elseif input:wasPressed("down") then
    s.focus = true; return true
  elseif input:wasPressed("up") then
    return true
  end
  return false
end

-- the slider on the bottom screen: a press below the page buttons picks the
-- time by x / 85
function M.touch(dex, x, y)
  if y < 48 then return false end
  local s = M.state(dex)
  s.time = math.max(0, math.min(2, math.floor(x / 85)))
  s.focus = true
  return true
end

local function drawGrid(dex, grid, key, alpha)
  local strip = img(dex, key)
  if not strip then return end
  local g = love.graphics
  local sw, sh = strip:getDimensions()
  dex._quads = dex._quads or {}
  for a = 0, GRID - 1 do
    for b = 0, GRID - 1 do
      local t = grid[a * GRID + b]
      if t ~= 0 then
        local sx = t * 5
        local qk = key .. t
        local q = dex._quads[qk]
        if not q then q = g.newQuad(sx % sw, math.floor(sx / sw) * 5, 5, 5, sw, sh); dex._quads[qk] = q end
        g.draw(strip, q, 89 + b * 5, 30 + a * 5)
      end
    end
  end
end

local function drawAt(dex, key, x, y)
  local image, rec = img(dex, key)
  if not image then return false end
  love.graphics.draw(image, x + (rec.originX or 0), y + (rec.originY or 0))
  return true
end

function M.draw(dex, Font, Search)
  local g = love.graphics
  local s = M.state(dex)
  local pic = M.picture(dex)
  g.setColor(1, 1, 1, 1)
  local base = img(dex, "pt_area_map") or dex:screenArt("pokedex/area_map")
  if base then g.draw(base, 0, 0) end
  for _, piece in ipairs(M.HIDDEN_PIECES) do
    if M.hiddenVisible(dex.game.save, piece.location) then drawAt(dex, piece.key, piece.tx * 8, piece.ty * 8) end
  end
  -- the blink: 32 frames of fields, then 32 of dungeons
  local phase = math.floor(s.t / 32) % 2
  local c = s.t % 32
  local ev = (c < 16 and c or 32 - c) / 16
  g.setBlendMode("add")
  g.setColor(1, 1, 1, ev)
  if phase == 0 then
    drawGrid(dex, pic.special, "pt_field_2", ev)
    drawGrid(dex, pic.timed, "pt_field_1", ev)
  else
    for _, d in ipairs(pic.dungeons) do drawAt(dex, "pt_dungeon_" .. d.anim, d.x, d.y) end
  end
  g.setBlendMode("alpha")
  g.setColor(1, 1, 1, 1)
  -- the species, at (40, 120)
  local Sprites = require("src.pokemon.Sprites")
  local path = Sprites.path(dex.game.data, s.species, "front", { kind = "dex", mon = dex:displayMon() })
  local pk = path and dex:img(path)
  if pk then g.draw(pk, 40 - 40, 120 - 40, 0, 80 / pk:getWidth(), 80 / pk:getHeight()) end
  -- the time's name
  local tname = Search.label(dex, 36 + s.time, ({ "Morning", "Day", "Night" })[s.time + 1])
  Font.draw(tname, 8 + math.floor((72 - Font.width(tname)) / 2), 32)
  if pic.unknown then
    drawAt(dex, "pt_sizeicon_2", 160, 96)
    local word = Search.label(dex, 35, "Area Unknown")
    Font.draw(word, 160 - math.floor(Font.width(word) / 2), 88)
  end
end

-- the bottom screen's slider: area_sub in the time's colours, the icon at
-- (32,128) / (128,96) / (224,128) (ov21_021DE5A4)
local SLIDER = { [0] = { 32, 128 }, { 128, 96 }, { 224, 128 } }
function M.drawBottom(dex)
  local s = M.state(dex)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local sub = img(dex, "pt_area_sub_" .. s.time)
  if sub then g.draw(sub, 0, 0) end
  local p = SLIDER[s.time]
  drawAt(dex, "pt_timeicon_" .. s.time, p[1], p[2])
  return sub ~= nil
end

return M
