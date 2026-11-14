-- THE AREA-NAME POPUP, the data half (pokeplatinum
-- src/overlay005/map_name_popup.c).
--
-- Entering a town or a route the cartridge drops a sign from the top-left of
-- the screen with the place's name on it. Two things the field needs that the
-- import did not keep:
--
--   * per map header: `mapLabelTextID` (the line in the location-names bank),
--     `mapLabelWindowID` (which sign: 0 none, else 1 + the window index) and
--     `mapType` (a building shows no sign on arrival -- MapHeader_IsBuilding:
--     MAP_TYPE_INDOORS or MAP_TYPE_POKECENTER);
--   * the nine signs of /arc/area_win_gra.narc -- city, town, route, cave,
--     forest, water, park, lake, indoors -- each 17x5 tiles (the window is
--     blitted tile by tile in reading order, MapNamePopUp_DrawWindowFrame)
--     and one sixteen-colour palette, whose entries 3 and 2 are the name's
--     ink and shadow (TEXT_COLOR(3, 2, 0)).
--
-- Written to the cache module `gen4_area_popup`.

local Gen4AreaPopup = {}

Gen4AreaPopup.PATH = "/arc/area_win_gra.narc"
Gen4AreaPopup.WIDTH_TILES, Gen4AreaPopup.HEIGHT_TILES = 17, 5
Gen4AreaPopup.KINDS = { "city", "town", "route", "cave", "forest", "water", "park", "lake", "indoors" }

local function hexTiles(G, sheet, palette)
  local w, h = Gen4AreaPopup.WIDTH_TILES * 8, Gen4AreaPopup.HEIGHT_TILES * 8
  local out = {}
  local data = sheet.pixels
  local four = sheet.bpp ~= 8
  local perTile = four and 32 or 64
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local t = math.floor(y / 8) * Gen4AreaPopup.WIDTH_TILES + math.floor(x / 8)
      local base = t * perTile
      local tx, ty = x % 8, y % 8
      local v = 0
      if four then
        local b = data:byte(base + ty * 4 + math.floor(tx / 2) + 1) or 0
        v = (tx % 2 == 0) and (b % 16) or math.floor(b / 16)
      else
        v = (data:byte(base + ty * 8 + tx + 1) or 0) % 16
      end
      out[#out + 1] = ("%x"):format(v)
    end
  end
  return { w = w, h = h, idx = table.concat(out) }
end

function Gen4AreaPopup.extract(rom, headers)
  local Narc = require("src.import.NarcArchive")
  local G = require("src.import.Gen4Graphics")
  local raw = rom:read(Gen4AreaPopup.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil, "no " .. Gen4AreaPopup.PATH end
  local function member(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local out = { windows = {}, headers = {} }
  for i, kind in ipairs(Gen4AreaPopup.KINDS) do
    local sheet = G.tiles(member((i - 1) * 2))
    local pal = G.palette(member((i - 1) * 2 + 1))
    if sheet and pal then
      local win = hexTiles(G, sheet, pal)
      win.kind = kind
      win.palette = {}
      for k = 1, 16 do win.palette[k] = pal[k] or { 0, 0, 0 } end
      out.windows[i - 1] = win
    end
  end
  -- THE HEADERS THE MAPS STAGE FOUND, not a fixed address: the table sits at
  -- arm9+0xE601C on the US cartridge and 0x58 bytes later on the German one,
  -- and 24-byte records read from the wrong place still parse -- every map
  -- came out "no sign" until this took the located table.
  if type(headers) ~= "table" then headers = Gen4AreaPopup.locate(rom) end
  for id, h in pairs(headers or {}) do
    out.headers[id] = { text = h.labelText, window = h.labelWindow, mapType = h.mapType }
  end
  return out
end

-- Standalone (no maps stage before it): the known offset when it holds a
-- full table on this cartridge, else the structural search with the bounds
-- the Platinum archives give.
function Gen4AreaPopup.locate(rom)
  local H = require("src.import.Gen4MapHeaders")
  local Narc = require("src.import.NarcArchive")
  local arm9 = rom and rom:arm9()
  if not arm9 then return nil end
  local function count(path)
    local raw = rom:read(path)
    local arc = raw and Narc.parse(raw)
    return arc and arc.count or 0
  end
  local limits = {
    matrix = count("/fielddata/mapmatrix/map_matrix.narc"),
    scripts = count("/fielddata/script/scr_seq.narc"),
    messages = count("/msgdata/pl_msg.narc"),
    encounters = count("/fielddata/encountdata/pl_enc_data.narc"),
    events = count("/fielddata/eventdata/zone_event.narc"),
    names = 593,
  }
  local at, n = H.find(arm9, limits)
  return at and H.all(arm9, at, n) or nil
end

return Gen4AreaPopup
