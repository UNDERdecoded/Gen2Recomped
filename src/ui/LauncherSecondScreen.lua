-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE BOTTOM SCREEN, BEFORE A GAME IS EVEN CHOSEN.
--
-- Reported from play: "its still not detecting the second screen on the ayn
-- thor for platinum maybe the launcher itself has to intialize with it".
--
-- That is exactly it, and for a plainer reason than the report guesses. The
-- panel's frame is sent by `SecondScreen.flush`, and the only caller was
-- `Game:draw` -- but `love.draw` returns at `Importer:draw()` and never
-- reaches `Game:draw` while the launcher is up. So no frame was ever pushed
-- before a game started, the host had nothing to show, and a player looking at
-- a blank bottom panel on the game list concluded the device was not detected.
-- Nothing was wrong with the detection; nothing was asking.
--
-- So this is what the second screen shows while the launcher owns the window:
-- every game as a tile in a grid, sortable, and a button through to the mods
-- panel. It is the launcher's own second screen, not a preview of a game's.
--
-- WHY IT DRAWS IN LOVE'S DEFAULT FONT and nothing prettier: at launcher time
-- NO CARTRIDGE CACHE IS MOUNTED. Every font this engine draws with is baked
-- from ROM data that does not exist yet, so reaching for one here would either
-- raise or silently draw nothing. The default font is the only one guaranteed
-- to be there this early, and a legible panel beats a themed blank one.
--
-- WHY IT IS INERT WITHOUT A PANEL: `tick` returns immediately unless
-- `SecondScreen.deviceReady()` says a real second display is attached. On a
-- phone, a desktop, a handheld with one screen -- every platform but the ones
-- this is for -- it costs one boolean per frame and allocates nothing. It
-- never draws into the window: a launcher that grew a second panel in the
-- corner of a single-screen device would be a regression, not a feature.

local SecondScreen = require("src.ui.SecondScreen")

local LauncherSecondScreen = {}

-- The DS's screen, which is the space `SecondScreen` works in.
local W, H = 256, 192

-- Sort orders the header button cycles. Generation first, because that is what
-- was asked for and it is the order the shelf is in.
LauncherSecondScreen.SORTS = { "generation", "name" }

-- TOUCH TARGETS ARE SIZED FOR A FINGER, not a cursor. 78x40 on a 256x192
-- panel is roughly 9mm on the Thor's lower screen; the header buttons are
-- taller than they need to be for the same reason.
local COLS = 3
local TILE_W, TILE_H = 78, 40
local TILE_GAP = 5
local GRID_X, GRID_Y = 8, 46
local HEADER_H = 38
local ROWS_VISIBLE = 3

local state = {
  sort = 1,
  scroll = 0,          -- whole rows
  pressed = nil,       -- what a finger went down on
  host = nil,
}

-- ---------------------------------------------------------------------------
-- The shelf
-- ---------------------------------------------------------------------------

-- Every game the launcher knows, with the two things a tile shows.
--
-- GameVersion.ORDER rather than `pairs(VERSIONS)`: a grid whose tiles move
-- between frames is unusable, and `pairs` order is not stable across runs.
local function shelf(importer)
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not ok or not GameVersion then return {} end
  local out = {}
  for _, id in ipairs(GameVersion.ORDER or {}) do
    local info = GameVersion.VERSIONS and GameVersion.VERSIONS[id]
    if info then
      out[#out + 1] = {
        id = id,
        name = info.launcherName or info.label or id,
        gen = tonumber(info.generation) or 1,
        -- `importer.ready` is the launcher's own map, and it is what
        -- `RomImporter:play` guards on -- so a tile is playable exactly when
        -- the button in the window is. Asking a second source would be a
        -- second answer to drift from.
        ready = not not (importer and importer.ready and importer.ready[id]),
      }
    end
  end
  local mode = LauncherSecondScreen.SORTS[state.sort] or "generation"
  table.sort(out, function(a, b)
    if mode == "name" then
      if a.name ~= b.name then return a.name < b.name end
      return a.id < b.id
    end
    if a.gen ~= b.gen then return a.gen < b.gen end
    return a.name < b.name
  end)
  return out
end

local function rows(n)
  return math.max(1, math.ceil(n / COLS))
end

local function tileRect(index)
  local i = index - 1
  local col = i % COLS
  local row = math.floor(i / COLS) - state.scroll
  if row < 0 or row >= ROWS_VISIBLE then return nil end
  return GRID_X + col * (TILE_W + TILE_GAP),
         GRID_Y + row * (TILE_H + TILE_GAP),
         TILE_W, TILE_H
end

local SORT_RECT = { 8, 6, 104, HEADER_H - 10 }
local MODS_RECT = { 144, 6, 104, HEADER_H - 10 }
local UP_RECT   = { 118, 6, 20, (HEADER_H - 10) / 2 - 1 }
local DOWN_RECT = { 118, 6 + (HEADER_H - 10) / 2 + 1, 20, (HEADER_H - 10) / 2 - 1 }

local function inRect(r, x, y)
  return x >= r[1] and y >= r[2] and x < r[1] + r[3] and y < r[2] + r[4]
end

-- What is under a point: a rect name, or a tile index.
local function hit(importer, x, y)
  if inRect(SORT_RECT, x, y) then return "sort" end
  if inRect(MODS_RECT, x, y) then return "mods" end
  if inRect(UP_RECT, x, y) then return "up" end
  if inRect(DOWN_RECT, x, y) then return "down" end
  local games = shelf(importer)
  for i = 1, #games do
    local tx, ty, tw, th = tileRect(i)
    if tx and x >= tx and y >= ty and x < tx + tw and y < ty + th then
      return i, games[i]
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Acting on a tap
-- ---------------------------------------------------------------------------

local function clampScroll(count)
  local maxScroll = math.max(0, rows(count) - ROWS_VISIBLE)
  if state.scroll > maxScroll then state.scroll = maxScroll end
  if state.scroll < 0 then state.scroll = 0 end
end

local function activate(importer, what, game)
  if what == "sort" then
    state.sort = (state.sort % #LauncherSecondScreen.SORTS) + 1
    state.scroll = 0
    return true
  end
  if what == "up" then
    state.scroll = state.scroll - 1
    clampScroll(#shelf(importer))
    return true
  end
  if what == "down" then
    state.scroll = state.scroll + 1
    clampScroll(#shelf(importer))
    return true
  end
  if what == "mods" then
    -- The launcher's own panel switch, which is all "manage mods" means here.
    -- Doing more than this from a second screen -- installing, deleting -- is
    -- a file-picker flow that belongs where the keyboard is.
    if importer then importer.tab = "mods" end
    return true
  end
  if type(what) == "number" and game then
    -- NOT PLAYABLE IS NOT A DEAD TAP: selecting the tab puts the game's own
    -- card up in the window, which is where its Import ROM button is. A tile
    -- that did nothing would read as broken.
    if importer then importer.tab = game.id end
    if game.ready and importer and importer.play then
      pcall(importer.play, importer, game.id)
    end
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- The host: a stand-in for `Game`, so `SecondScreen` needs no launcher branch
-- ---------------------------------------------------------------------------
--
-- Everything in `src/ui/SecondScreen.lua` is keyed on a `game` -- its options,
-- its canvas, its dirty flag, its touch handlers. The launcher has no Game and
-- should not grow a second copy of that module to avoid one, so it presents a
-- table shaped like the part of Game that the module actually reads.
--
-- `secondScreenAlways` is the opt-in: `SecondScreen.available` answers on the
-- cartridge's generation, and at launcher time there is no cartridge.
local function hostFor(importer)
  local host = state.host
  if not host then
    host = {
      secondScreenAlways = true,
      -- The launcher is not a Nintendo DS framebuffer. Use the Android host's
      -- actual lower-panel resolution; SecondScreen scales this module's
      -- 256x192 logical layout to it and maps touches back to logical space.
      -- A running Gen 4 Game does not set this flag and remains true 256x192.
      secondScreenNativePanel = true,
      data = {},
      save = { options = { secondScreenMode = "display" } },
    }
    -- The panel's taps arrive through the transport and are delivered by
    -- `SecondScreen.pumpInput` to exactly these three, with coordinates
    -- already in the bottom screen's own space.
    function host.touchpressed(_, _, x, y)
      local what, game = hit(host.importer, x, y)
      state.pressed = what and { what = what, game = game } or nil
    end
    function host.touchmoved(_, _, x, y)
      if not state.pressed then return end
      -- A finger that slid off its target cancels. This is the behaviour a
      -- touch panel needs and a mouse does not: on a 78px tile a tap that
      -- drifts is common, and firing `play` on release somewhere else would
      -- boot the wrong cartridge.
      local what = hit(host.importer, x, y)
      if what ~= state.pressed.what then state.pressed = nil end
    end
    function host.touchreleased(_, _, x, y)
      local press = state.pressed
      state.pressed = nil
      if not press then return end
      local what, game = hit(host.importer, x, y)
      if what ~= press.what then return end
      activate(host.importer, what, game or press.game)
    end
    state.host = host
  end
  host.importer = importer
  return host
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local GEN_TINT = {
  [1] = { 0.78, 0.26, 0.24 },
  [2] = { 0.80, 0.66, 0.24 },
  [3] = { 0.25, 0.58, 0.36 },
  [4] = { 0.30, 0.44, 0.74 },
}

local function button(r, label, held, accent)
  local g = love.graphics
  local a = accent or { 0.22, 0.26, 0.34 }
  if held then
    g.setColor(a[1] * 1.5, a[2] * 1.5, a[3] * 1.5, 1)
  else
    g.setColor(a[1], a[2], a[3], 1)
  end
  g.rectangle("fill", r[1], r[2], r[3], r[4], 4, 4)
  g.setColor(1, 1, 1, 0.22)
  g.rectangle("line", r[1], r[2], r[3], r[4], 4, 4)
  g.setColor(1, 1, 1, 1)
  local font = g.getFont()
  local tw = font and font:getWidth(label) or 0
  local th = font and font:getHeight() or 8
  g.print(label, math.floor(r[1] + (r[3] - tw) / 2),
                 math.floor(r[2] + (r[4] - th) / 2))
end

local function body(importer)
  local g = love.graphics
  -- Never inherit the font left by a cartridge's launcher panel.
  if g.newFont and g.setFont then
    local pw, ph = SecondScreen.panelSize()
    local density = math.max(1, math.ceil(math.max(pw / W, ph / H)))
    if not state.font or state.fontDensity ~= density then
      -- Rasterize at panel resolution while keeping fixed logical metrics.
      local made, font = pcall(g.newFont, 8, 'normal', density)
      state.font = made and font or g.newFont(8)
      state.fontDensity = density
    end
    g.setFont(state.font)
  end
  local pal = importer and importer.palette and importer.palette() or {}
  local function color(key, fallback, alpha)
    local c = pal[key] or fallback
    g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1)
  end
  local games = shelf(importer)
  clampScroll(#games)

  local top, bot = pal.bgTop or {22,34,74}, pal.bgBot or {7,11,29}
  for y = 0, H - 1 do
    local t = y / (H - 1)
    g.setColor((top[1]*(1-t)+bot[1]*t)/255,
      (top[2]*(1-t)+bot[2]*t)/255, (top[3]*(1-t)+bot[3]*t)/255, 1)
    g.rectangle("fill", 0, y, W, 1)
  end

  local press = state.pressed
  local sortName = LauncherSecondScreen.SORTS[state.sort] or "generation"
  button(SORT_RECT, "SORT: " .. sortName:upper(),
         press and press.what == "sort")
  button(MODS_RECT, "MANAGE MODS", press and press.what == "mods",
         { 0.34, 0.24, 0.40 })
  button(UP_RECT, "^", press and press.what == "up")
  button(DOWN_RECT, "v", press and press.what == "down")

  for i, game in ipairs(games) do
    local x, y, w, h = tileRect(i)
    if x then
      local tint = GEN_TINT[game.gen] or GEN_TINT[1]
      local held = press and press.what == i
      -- A CARTRIDGE THAT IS NOT IMPORTED READS AS ABSENT, not as missing: it
      -- keeps its place in the grid so the shelf does not reshuffle as games
      -- are added, and dims instead.
      color("cardBlue", {12,18,40}, held and 0.75 or 1)
      g.rectangle("fill", x, y, w, h, 4, 4)
      local selected = importer and importer.tab == game.id
      g.setColor(tint[1], tint[2], tint[3], selected and 1 or 0.5)
      g.rectangle("line", x, y, w, h, 4, 4)
      g.rectangle("fill", x + 4, y + 2, w - 8, 2)
      g.setColor(1, 1, 1, game.ready and 1 or 0.5)
      -- Release-status suffixes belong to the detailed top-screen card.
      local name = game.name:gsub(' %b()$', '')
      g.print(name, x + 5, y + 5)
      g.setColor(1, 1, 1, game.ready and 0.72 or 0.38)
      g.print("GEN " .. game.gen, x + 5, y + h - 16)
      if not game.ready then
        g.setColor(1, 1, 1, 0.5)
        local font = g.getFont()
        local label = "no ROM"
        local tw = font and font:getWidth(label) or 0
        g.print(label, x + w - tw - 5, y + h - 16)
      end
    end
  end

  -- Which rows of the shelf are on screen, so the arrows mean something.
  g.setColor(1, 1, 1, 0.45)
  g.print(("%d games   rows %d-%d of %d"):format(
    #games, state.scroll + 1,
    math.min(rows(#games), state.scroll + ROWS_VISIBLE), rows(#games)),
    8, H - 16)
  g.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- The per-frame entry point, called from love.draw
-- ---------------------------------------------------------------------------

-- True only while a real second display is attached. Everything below is gated
-- on it, and it is the whole answer to "only if the device has two screens".
function LauncherSecondScreen.active()
  local ok, ready = pcall(SecondScreen.deviceReady)
  return (ok and ready) and true or false
end

function LauncherSecondScreen.tick(importer)
  if not LauncherSecondScreen.active() then return false end
  local host = hostFor(importer)
  -- `SecondScreen.draw` renders the body to the host's own canvas and raises
  -- the dirty flag; `flush` takes the taps and sends the frame. Both are the
  -- same calls a Gen 4 session makes, so the panel cannot drift from the game's.
  local okDraw = pcall(SecondScreen.draw, host, function() body(importer) end)
  local okFlush = pcall(SecondScreen.flush, host)
  return okDraw and okFlush
end

-- Forget the host when the launcher closes, so a canvas is not held for the
-- whole session and the next launcher visit starts on the shelf's first row.
function LauncherSecondScreen.forget()
  state.host = nil
  state.pressed = nil
  state.scroll = 0
end

-- Published for tools/gen4_launcher_second_screen_check.lua, which needs to
-- ask what is under a point without a GPU.
LauncherSecondScreen._hit = function(importer, x, y) return hit(importer, x, y) end
-- The grid's geometry, so a check can work out where a tile OUGHT to be
-- instead of asking `hit` and then asking `hit` to agree with itself.
LauncherSecondScreen._layout = {
  cols = COLS, tileW = TILE_W, tileH = TILE_H, gap = TILE_GAP,
  x = GRID_X, y = GRID_Y, rows = ROWS_VISIBLE,
}
LauncherSecondScreen._activate = activate
LauncherSecondScreen._shelf = shelf
LauncherSecondScreen._state = state
LauncherSecondScreen._host = hostFor

return LauncherSecondScreen
