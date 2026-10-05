-- PLATINUM'S AREA-NAME SIGN (pokeplatinum src/overlay005/map_name_popup.c).
--
-- Reported from play: "the popup that appears when going into a town or route
-- is also missing from platinum". The cartridge's rules, all of them here:
--
-- WHEN (two callers):
--   * walking across a map boundary (FieldMap_ChangeZone): shown whenever the
--     LOCATION NAME changes -- a city's several headers share one name and do
--     not re-announce it -- and with the new header's sign, building or not;
--   * arriving by warp, Fly or a field transition
--     (FieldSystem_RequestLocationName): only when the header has a sign
--     (`mapLabelWindowID` != 0) and is not a building (MAP_TYPE_INDOORS /
--     MAP_TYPE_POKECENTER) -- so walking out of a house announces the town.
--   A new name while one is up slides the old one out first, then the new one
--   in (MapNamePopUp_Show's SLIDE_IN / WAIT / SLIDE_OUT arms).
--
-- WHAT: sign `mapLabelWindowID - 1` of /arc/area_win_gra.narc (city, town,
-- route, cave, forest, water, park, lake, indoors), 17x5 tiles from the top-left
-- of the screen, the name from the location-names bank (433) in FONT_SYSTEM,
-- colours 3 / 2 of the sign's palette, at x = 4 + the cartridge's centring
-- offset and y = 16.
--
-- HOW: a field SysTask, so in 30 Hz ticks: in from 38 px up at 4 a tick, 60
-- ticks held, out at 4 a tick.

local Gen4AreaPopup = {}

local HIDDEN = 38
local HOLD_TICKS = 60
local SPEED = 4
local INDOORS, POKECENTER = 4, 5

local function record(game) return game and game.data and game.data.gen4_area_popup end

local function headerRow(game, header)
  local rec = record(game)
  return rec and rec.headers and rec.headers[tonumber(header) or -1]
end

local function nameFor(game, text)
  local t = game.data.text or {}
  local s = t[("TEXT_B0433_%05d"):format(tonumber(text) or 0)]
  return type(s) == "string" and (s:gsub("[\n\r\f\v]", " ")) or nil
end

local function fresh(game, row, window)
  return { gen4 = true, name = nameFor(game, row.text), text = row.text,
           window = window, y = HIDDEN, state = "in", ticks = 0, frame = 0 }
end

-- MapNamePopUp_Show
local function show(game, sign, row, window)
  if not row then return sign end
  if not (sign and sign.gen4 and sign.state ~= "end") then
    return fresh(game, row, window)
  end
  if sign.state == "in" or sign.state == "wait" then
    sign.state = "out"
  end
  sign.next = { row = row, window = window }
  return sign
end

-- The boundary walk (FieldMap_ChangeZone).
function Gen4AreaPopup.onCross(game, sign, oldHeader, newHeader)
  local old, new = headerRow(game, oldHeader), headerRow(game, newHeader)
  if not new then return sign end
  if old and old.text == new.text then return sign end
  local window = new.window
  if window ~= 0 then window = window - 1 end
  return show(game, sign, new, window)
end

-- An arrival (FieldSystem_RequestLocationName).
function Gen4AreaPopup.onArrive(game, sign, header)
  local row = headerRow(game, header)
  if not row or row.window == 0 then return sign end
  if row.mapType == INDOORS or row.mapType == POKECENTER then return sign end
  return show(game, sign, row, row.window - 1)
end

-- One 60 Hz frame; the sign moves every other one. Answers the sign, or nil
-- once it has gone.
function Gen4AreaPopup.tick(game, sign)
  if not (sign and sign.gen4) then return sign end
  sign.frame = (sign.frame or 0) + 1
  if sign.frame % 2 == 1 then return sign end
  if sign.state == "in" then
    sign.y = math.max(0, sign.y - SPEED)
    if sign.y == 0 then sign.state, sign.ticks = "wait", 0 end
  elseif sign.state == "wait" then
    sign.ticks = sign.ticks + 1
    if sign.ticks >= HOLD_TICKS then sign.state = "out" end
  elseif sign.state == "out" then
    sign.y = math.min(HIDDEN, sign.y + SPEED)
    if sign.y == HIDDEN then
      if sign.next then
        local n = sign.next
        local replaced = fresh(game, n.row, n.window)
        replaced.frame = sign.frame
        return replaced
      end
      return nil
    end
  end
  return sign
end

-- MapNamePopUp_DrawWindowFrame's centring, given the name's pixel width.
function Gen4AreaPopup.xOffset(strWidth)
  local margin = math.floor((strWidth + 8) / 8) * 8 - strWidth
  local left = math.floor(margin / 2)
  local spare = 0
  if 8 > 4 + left then spare = math.floor(((8 - (4 + left)) * 2 + 8 - 1) / 8) end
  local x = 0
  if strWidth > 0 then
    local tiles = math.floor((strWidth + 8) / 8) + spare
    x = math.floor((tiles * 8 + 8 - strWidth) / 2)
  end
  return 4 + x
end

local cache = setmetatable({}, { __mode = "k" })

local function signImage(game, window)
  local rec = record(game)
  local win = rec and rec.windows and rec.windows[window]
  if not win then return nil, nil end
  local per = cache[rec] or {}
  cache[rec] = per
  if per[window] then return per[window], win end
  local data = love.image.newImageData(win.w, win.h)
  for y = 0, win.h - 1 do
    for x = 0, win.w - 1 do
      local i = y * win.w + x + 1
      local v = tonumber(win.idx:sub(i, i), 16) or 0
      if v ~= 0 then
        local c = win.palette[v + 1] or { 0, 0, 0 }
        data:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  per[window] = img
  return img, win
end

function Gen4AreaPopup.draw(game, sign)
  if not (sign and sign.gen4) then return end
  local img, win = signImage(game, sign.window)
  if not img then return end
  local g = love.graphics
  g.push()
  g.translate(0, -sign.y)
  g.setColor(1, 1, 1, 1)
  g.draw(img, 0, 0)
  if sign.name then
    local Font = require("src.render.Font")
    local faced = Font.pushFace and Font.pushFace("system")
    local width = Font.width and Font.width(sign.name) or #sign.name * 6
    local function c01(c) return { c[1] / 255, c[2] / 255, c[3] / 255, 1 } end
    local tone = Font.beginTwoTone and Font.beginTwoTone(c01(win.palette[4]), c01(win.palette[3]))
    if not tone then g.setColor(c01(win.palette[4])) end
    Font.draw(sign.name, Gen4AreaPopup.xOffset(width), 16)
    if tone then Font.endTwoTone() end
    if faced and Font.popFace then Font.popFace() end
  end
  g.pop()
  g.setColor(1, 1, 1, 1)
end

return Gen4AreaPopup
