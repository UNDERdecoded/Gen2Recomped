-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE LAUNCHER'S BOTTOM SCREEN, WITHOUT A GPU OR A SECOND DISPLAY.
--
-- Reported from play: "its still not detecting the second screen on the ayn
-- thor for platinum maybe the launcher itself has to intialize with it", and
-- then the brief: a grid of every game tile, sortable by generation, with a
-- button to manage mods, all touch-friendly.
--
-- The reason nothing appeared is measurable and is checked here: the frame is
-- sent by `SecondScreen.flush`, whose only caller was `Game:draw`, which
-- `love.draw` never reaches while the launcher owns the window.
--
-- WHAT THIS CHECKS THAT A PLAY-TEST CANNOT: that every tile's own rectangle
-- maps back to its own tile. A grid whose hit test is off by one column boots
-- the wrong cartridge, and on a device with no keyboard that is not a thing
-- the player can back out of.
--
-- Usage: texlua tools/gen4_launcher_second_screen_check.lua

package.path = "./?.lua;" .. package.path

-- The panel's own size, which is the DS's screen and the space the transport
-- delivers taps in. A tap outside it is discarded before it arrives.
local W, H = 256, 192
local CLOCK = 1000

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

-- ---------------------------------------------------------------------------
-- A RECORDING love.graphics: every draw is kept, so what the panel put on
-- screen can be counted rather than assumed.
-- ---------------------------------------------------------------------------
local REC = { rects = {}, prints = {}, canvas = nil }
local function resetRec() REC.rects, REC.prints = {}, {} end

local fakeFont = {}
function fakeFont:getWidth(s) return #tostring(s) * 6 end
function fakeFont:getHeight() return 12 end

local pushes = 0
love = {
  -- A CLOCK THAT MOVES. `SecondScreen.flush` throttles the GPU readback to
  -- PUSH_INTERVAL, so a frozen clock lets exactly one frame out for the whole
  -- run and every later push check measures the throttle instead of the panel.
  timer = { getTime = function()
    CLOCK = CLOCK + 1 / 60
    return CLOCK
  end },
  graphics = {
    getFont = function() return fakeFont end,
    setColor = function() end, origin = function() end,
    setScissor = function() end, clear = function() end,
    push = function() end, pop = function() end,
    translate = function() end, scale = function() end,
    getCanvas = function() return nil end,
    setCanvas = function() end,
    rectangle = function(_, x, y, w, h)
      REC.rects[#REC.rects + 1] = { x = x, y = y, w = w, h = h }
    end,
    print = function(text, x, y)
      REC.prints[#REC.prints + 1] = { text = tostring(text), x = x, y = y }
    end,
    newCanvas = function(w, h)
      local c = { w = w, h = h }
      function c:newImageData()
        local d = { }
        function d:getString() return string.rep("\0", 256 * 192 * 4) end
        function d:release() end
        return d
      end
      function c:getDimensions() return self.w, self.h end
      function c:setFilter() end
      function c:release() end
      return c
    end,
    getWidth = function() return 480 end,
    getHeight = function() return 320 end,
  },
  system = { getOS = function() return "Android" end },
  filesystem = {
    getInfo = function() return nil end,
    read = function() return nil end,
    write = function() return true end,
    createDirectory = function() return true end,
  },
}

-- A transport that says a panel IS attached, so `display` mode is reachable.
-- FORWARD-DECLARED ON PURPOSE. Inside `local T = { f = function() return T end }`
-- the name is not in scope yet, so the closure would read a nil global and
-- every `available` call would raise into the pcall and answer "no panel" --
-- which is exactly the symptom being investigated, arriving from the test.
local TRANSPORT
TRANSPORT = {
  attached = true,
  available = function() return TRANSPORT.attached end,
  push = function() pushes = pushes + 1 return true end,
  pollTouch = function() return TRANSPORT.queue end,
  queue = nil,
}

local SecondScreen = require("src.ui.SecondScreen")
SecondScreen._setTransport(TRANSPORT)
local LSS = require("src.ui.LauncherSecondScreen")

-- A launcher with a plausible readiness map: some imported, some not.
local function importer(readyIds)
  local ready = {}
  for _, id in ipairs(readyIds or {}) do ready[id] = true end
  local I = { ready = ready, tab = "red", played = {} }
  function I:play(v) self.played[#self.played + 1] = v end
  return I
end

local READY = { "red", "crystal", "emerald", "platinum" }

-- ---------------------------------------------------------------------------
section("1. the shelf holds every game, in a stable order")
-- ---------------------------------------------------------------------------
local GameVersion = require("src.core.GameVersion")
local I = importer(READY)
LSS._state.sort = 1
local games = LSS._shelf(I)
ok(#games == #GameVersion.ORDER,
   "the shelf has %d tiles for %d known games", #games, #GameVersion.ORDER)
do
  local seen = {}
  for _, g in ipairs(games) do seen[g.id] = true end
  local missing = {}
  for _, id in ipairs(GameVersion.ORDER) do
    if not seen[id] then missing[#missing + 1] = id end
  end
  ok(#missing == 0, "missing from the shelf: %s", table.concat(missing, " "))
end
-- SORTED BY GENERATION, which is what was asked for.
do
  local rising, gens = true, {}
  for i, g in ipairs(games) do
    gens[#gens + 1] = g.gen
    if i > 1 and games[i - 1].gen > g.gen then rising = false end
  end
  ok(rising, "generations run %s -- not ascending",
     table.concat(gens, ","))
end
-- ...AND THE ORDER DOES NOT MOVE BETWEEN FRAMES. `pairs` order is not stable
-- across runs, and a grid whose tiles jump is unusable.
do
  local a, b = LSS._shelf(I), LSS._shelf(I)
  local same = #a == #b
  for i = 1, math.min(#a, #b) do
    if a[i].id ~= b[i].id then same = false end
  end
  ok(same, "two reads of the shelf came back in different orders")
end
-- readiness comes from the launcher's own map, not a second source
do
  local bad = {}
  for _, g in ipairs(games) do
    local want = not not I.ready[g.id]
    if g.ready ~= want then bad[#bad + 1] = g.id end
  end
  ok(#bad == 0, "readiness disagrees with the launcher for: %s",
     table.concat(bad, " "))
end

-- ---------------------------------------------------------------------------
section("2. sortable, and the sort actually changes the order")
-- ---------------------------------------------------------------------------
do
  LSS._state.sort = 1
  local byGen = LSS._shelf(I)
  ok(LSS._activate(I, "sort"), "the sort button did nothing")
  local byName = LSS._shelf(I)
  local differs = false
  for i = 1, #byGen do
    if byGen[i].id ~= byName[i].id then differs = true break end
  end
  ok(differs, "cycling the sort produced the same order, so it is not sorting")
  local rising = true
  for i = 2, #byName do
    if byName[i - 1].name > byName[i].name then rising = false end
  end
  ok(rising, "the name sort is not in name order")
  -- and it comes back round
  for _ = 1, #LSS.SORTS do LSS._activate(I, "sort") end
  local back = LSS._shelf(I)
  local same = true
  for i = 1, #byName do if back[i].id ~= byName[i].id then same = false end end
  ok(same, "cycling the sort %d times did not return to where it started",
     #LSS.SORTS)
  LSS._state.sort = 1
end

-- ---------------------------------------------------------------------------
section("3. every tile's own rectangle maps back to its own tile")
-- ---------------------------------------------------------------------------
-- THE CHECK THAT MATTERS MOST, and the first version of it was worthless: it
-- asked `_hit` where each tile was and then asked `_hit` whether it agreed. A
-- grid that is consistently wrong passes that every time. So the rectangles are
-- worked out HERE, from the published layout, and `_hit` is measured against
-- them. An off-by-one column boots the wrong cartridge, and on a device with no
-- keyboard that is not something the player can back out of.
local LAY = LSS._layout
ok(type(LAY) == "table" and LAY.cols and LAY.tileW,
   "the grid publishes no layout, so nothing can check its hit map")

-- A finger is not a cursor. 40px on a 192px-tall panel is about 9mm on the
-- Thor's lower screen; anything under 30 is a target you cannot reliably hit.
ok(LAY.tileW >= 44 and LAY.tileH >= 30,
   "tiles are %dx%d -- too small for a fingertip", LAY.tileW, LAY.tileH)
ok(LAY.gap >= 3, "tiles are %dpx apart; adjacent targets need a gap", LAY.gap)

local function expect(index, scroll)
  local i = index - 1
  local col = i % LAY.cols
  local row = math.floor(i / LAY.cols) - scroll
  if row < 0 or row >= LAY.rows then return nil end
  return LAY.x + col * (LAY.tileW + LAY.gap),
         LAY.y + row * (LAY.tileH + LAY.gap)
end

do
  local all = LSS._shelf(I)
  local wrong, tested, offPanel = 0, 0, 0
  for scroll = 0, math.max(0, math.ceil(#all / LAY.cols) - 1) do
    LSS._state.scroll = scroll
    for i = 1, #all do
      local ex, ey = expect(i, scroll)
      if ex then
        -- corners just inside, and the middle
        local probes = {
          { ex, ey }, { ex + LAY.tileW - 1, ey },
          { ex, ey + LAY.tileH - 1 },
          { ex + LAY.tileW - 1, ey + LAY.tileH - 1 },
          { ex + math.floor(LAY.tileW / 2), ey + math.floor(LAY.tileH / 2) },
        }
        for _, pt in ipairs(probes) do
          tested = tested + 1
          if pt[1] < 0 or pt[2] < 0 or pt[1] >= W or pt[2] >= H then
            offPanel = offPanel + 1
          end
          local what, game = LSS._hit(I, pt[1], pt[2])
          if what ~= i or not game or game.id ~= all[i].id then
            wrong = wrong + 1
            if wrong == 1 then
              io.write(("   first mismatch: tile %d (%s) at %d,%d answered %s\n")
                :format(i, all[i].id, pt[1], pt[2], tostring(what)))
            end
          end
        end
        -- JUST PAST THE TILE IS NOT THE TILE. The gap has to be dead, or two
        -- neighbouring cartridges share an edge and the wrong one boots.
        local past = LSS._hit(I, ex + LAY.tileW, ey + math.floor(LAY.tileH / 2))
        checks = checks + 1
        if past == i then
          fails = fails + 1
          io.write(("FAIL: the gap right of tile %d still answers tile %d\n")
            :format(i, i))
        end
        local below = LSS._hit(I, ex + math.floor(LAY.tileW / 2), ey + LAY.tileH)
        checks = checks + 1
        if below == i then
          fails = fails + 1
          io.write(("FAIL: the gap below tile %d still answers tile %d\n")
            :format(i, i))
        end
      else
        -- A TILE THAT IS SCROLLED OFF MUST NOT BE REACHABLE. Its row is
        -- outside the viewport; a hit there taps a cartridge the player
        -- cannot see.
        local anywhere = false
        for px = 0, W - 1, 3 do
          for py = 0, H - 1, 3 do
            if LSS._hit(I, px, py) == i then anywhere = true end
          end
        end
        checks = checks + 1
        if anywhere then
          fails = fails + 1
          io.write(("FAIL: tile %d is scrolled out of view but still hits\n")
            :format(i))
        end
      end
    end
  end
  LSS._state.scroll = 0
  ok(tested > 100, "only %d probe(s) -- the grid may be drawing nowhere", tested)
  ok(wrong == 0, "%d of %d probes on a tile resolved to the wrong tile",
     wrong, tested)
  ok(offPanel == 0, "%d tile corner(s) fall outside the 256x192 panel, where "
     .. "the transport discards taps", offPanel)
end

-- ---------------------------------------------------------------------------
section("4. the buttons")
-- ---------------------------------------------------------------------------
do
  ok(LSS._hit(I, 12, 14) == "sort", "the sort button is not where it draws")
  ok(LSS._hit(I, 180, 14) == "mods", "MANAGE MODS is not where it draws")
  -- MANAGE MODS goes to the launcher's mods panel and nowhere else
  I.tab = "red"
  LSS._activate(I, "mods")
  ok(I.tab == "mods", "MANAGE MODS left the launcher on tab %q", tostring(I.tab))
  ok(#I.played == 0, "MANAGE MODS started a game")
end

-- ---------------------------------------------------------------------------
section("5. a tile taps through to the launcher, and only plays what is ready")
-- ---------------------------------------------------------------------------
do
  local all = LSS._shelf(I)
  local readyGame, absentGame
  for _, g in ipairs(all) do
    if g.ready and not readyGame then readyGame = g end
    if not g.ready and not absentGame then absentGame = g end
  end
  ok(readyGame ~= nil and absentGame ~= nil,
     "the fixture needs one imported game and one absent one")
  -- an imported game boots
  I.played, I.tab = {}, "red"
  LSS._activate(I, 1, readyGame)
  ok(I.tab == readyGame.id, "tapping %s selected tab %q",
     readyGame.id, tostring(I.tab))
  ok(#I.played == 1 and I.played[1] == readyGame.id,
     "tapping the imported %s played %s", readyGame.id,
     tostring(I.played[1]))
  -- ...AND AN ABSENT ONE DOES NOT. `RomImporter:play` guards on the same map,
  -- so this cannot boot a cartridge that is not there -- but it must still
  -- select the tab, or the tile reads as broken with no way to import.
  I.played, I.tab = {}, "red"
  LSS._activate(I, 2, absentGame)
  ok(I.tab == absentGame.id, "tapping an absent game selected tab %q",
     tostring(I.tab))
  ok(#I.played == 0, "tapping the un-imported %s tried to play it",
     absentGame.id)
end

-- ---------------------------------------------------------------------------
section("6. scrolling stays on the shelf")
-- ---------------------------------------------------------------------------
do
  LSS._state.scroll = 0
  LSS._activate(I, "up")
  ok(LSS._state.scroll == 0, "scrolling up from the top reached row %d",
     LSS._state.scroll)
  for _ = 1, 50 do LSS._activate(I, "down") end
  local maxRow = math.max(0, math.ceil(#LSS._shelf(I) / 3) - 3)
  ok(LSS._state.scroll == maxRow,
     "fifty downs reached row %d; the last row is %d", LSS._state.scroll, maxRow)
  -- and nothing is stranded past the end
  local visible = 0
  for _ = 1, 1 do
    for px = 0, 255, 6 do
      for py = 0, 191, 6 do
        if type(LSS._hit(I, px, py)) == "number" then visible = 1 end
      end
    end
  end
  ok(visible == 1, "at the bottom of the shelf no tile is reachable at all")
  LSS._state.scroll = 0
end

-- ---------------------------------------------------------------------------
section("7. a finger that slides off its target cancels")
-- ---------------------------------------------------------------------------
-- On a 78px tile a tap that drifts is ordinary, and firing on release wherever
-- the finger ended would boot a cartridge the player did not choose.
do
  local host = LSS._host(I)
  local function pointOn(index)
    for px = 0, 255 do
      for py = 0, 191 do
        if LSS._hit(I, px, py) == index then return px, py end
      end
    end
  end
  local ax, ay = pointOn(1)
  local bx, by = pointOn(2)
  ok(ax and bx, "could not find a point on each of the first two tiles")
  -- straight tap: fires
  I.played, I.tab = {}, "red"
  host.touchpressed(host, 1, ax, ay)
  host.touchreleased(host, 1, ax, ay)
  local first = LSS._shelf(I)[1]
  ok(I.tab == first.id, "a clean tap on tile 1 selected %q", tostring(I.tab))
  -- slid off: does not
  I.played, I.tab = {}, "sentinel"
  host.touchpressed(host, 1, ax, ay)
  host.touchmoved(host, 1, bx, by)
  host.touchreleased(host, 1, bx, by)
  ok(I.tab == "sentinel",
     "a finger that slid from tile 1 to tile 2 still activated %q", I.tab)
  ok(#I.played == 0, "a slid tap played %s", tostring(I.played[1]))
  -- released off the panel entirely: does not
  I.played, I.tab = {}, "sentinel"
  host.touchpressed(host, 1, ax, ay)
  host.touchreleased(host, 1, 250, 188)
  ok(I.tab == "sentinel", "releasing off the tile activated %q", I.tab)
  -- THE TWO GUARDS ARE SEPARATE, and the first version of this section could
  -- only see one of them: with a move in between, either guard alone stops a
  -- slid tap, so removing one changed nothing. These two cases each need one.
  --
  -- (a) release lands on a DIFFERENT tile with no move reported. Only the
  --     release-time comparison catches this.
  I.played, I.tab = {}, "sentinel"
  host.touchpressed(host, 1, ax, ay)
  host.touchreleased(host, 1, bx, by)
  ok(I.tab == "sentinel",
     "a press on tile 1 released on tile 2 activated %q", I.tab)
  ok(#I.played == 0, "it played %s", tostring(I.played[1]))
  -- (b) the HELD HIGHLIGHT lets go as the finger leaves. Only the move-time
  --     cancel does that, and it is visible, so it is measurable: tile 1 is
  --     drawn in its held colour while pressed and its normal one once the
  --     finger has moved away.
  local function tileFillAt(px, py)
    resetRec()
    LSS.tick(I)
    for _, r in ipairs(REC.rects) do
      if r.x == px and r.y == py then return r end
    end
    return nil
  end
  local ex1, ey1 = expect(1, 0)
  host.touchpressed(host, 1, ax, ay)
  ok(LSS._state.pressed ~= nil and LSS._state.pressed.what == 1,
     "pressing tile 1 recorded %s", tostring(LSS._state.pressed
       and LSS._state.pressed.what))
  ok(tileFillAt(ex1, ey1) ~= nil, "tile 1 is not drawn at its own rect")
  host.touchmoved(host, 1, bx, by)
  ok(LSS._state.pressed == nil,
     "the finger moved to another tile and tile 1 is still held")
  host.touchreleased(host, 1, bx, by)
end

-- ---------------------------------------------------------------------------
section("8. SecondScreen takes the launcher's host as-is")
-- ---------------------------------------------------------------------------
do
  local host = LSS._host(I)
  ok(SecondScreen.available(host) == true,
     "SecondScreen will not serve the launcher's host, so no panel is possible")
  TRANSPORT.attached = true
  ok(SecondScreen.mode(host) == "display",
     "with a panel attached the host's mode is %q, not \"display\"",
     SecondScreen.mode(host))
  -- ...and a game's own host is unaffected by the new flag
  local gen4 = { data = { isGen4Cache = true },
                 save = { options = { secondScreenMode = "display" } } }
  ok(SecondScreen.available(gen4) == true, "a Gen 4 session lost its panel")
  local gen2 = { data = {}, save = { options = {} } }
  ok(SecondScreen.mode(gen2) == "off",
     "a Gen 1/2 session now answers %q instead of \"off\"",
     SecondScreen.mode(gen2))
end

-- ---------------------------------------------------------------------------
section("9. inert with one screen, live with two")
-- ---------------------------------------------------------------------------
do
  TRANSPORT.attached = false
  ok(LSS.active() == false, "the panel reports itself active with one display")
  local before = pushes
  ok(LSS.tick(I) == false, "tick did work with no second display attached")
  ok(pushes == before, "%d frame(s) were pushed to a display that is not there",
     pushes - before)
  TRANSPORT.attached = true
  ok(LSS.active() == true, "with a panel attached the shelf is still inactive")
  resetRec()
  -- `flush` throttles the 192KB GPU readback to PUSH_INTERVAL, and the frames
  -- drawn in section 7 were moments ago on this clock. Time is moved on
  -- deliberately rather than by widening the tick, so the throttle stays real.
  CLOCK = CLOCK + 1
  local ran = LSS.tick(I)
  ok(ran == true, "tick did not draw with a panel attached")
  ok(pushes > before, "the panel drew but no frame was pushed")
  -- ...AND THE THROTTLE IS STILL THERE: a second tick in the same instant
  -- must not pull the canvas back off the GPU again.
  local afterOne = pushes
  LSS.tick(I)
  ok(pushes == afterOne,
     "two ticks in one frame pushed %d times; the readback is not throttled",
     pushes - afterOne + 1)
  -- IT DREW THE SHELF, not an empty screen: one rect per tile plus the four
  -- header buttons, and every game's name printed.
  ok(#REC.rects >= #LSS._shelf(I), "only %d rectangle(s) for %d tiles plus "
     .. "buttons", #REC.rects, #LSS._shelf(I))
  local names = {}
  for _, p in ipairs(REC.prints) do names[p.text] = true end
  local absent = {}
  for i, g in ipairs(LSS._shelf(I)) do
    if i <= 9 and not names[g.name:gsub(' %b()$', '')] then absent[#absent + 1] = g.name end
  end
  ok(#absent == 0, "on screen but unnamed: %s", table.concat(absent, ", "))
  ok(names["MANAGE MODS"] == true, "MANAGE MODS was not drawn")
end

-- ---------------------------------------------------------------------------
section("10. taps arrive from the transport, not the window")
-- ---------------------------------------------------------------------------
-- The panel is not in the window, so its taps come back through the host's
-- touch file. This is the whole path, end to end.
do
  TRANSPORT.attached = true
  local host = LSS._host(I)
  local px, py
  for x = 0, 255 do
    for y = 0, 191 do
      if LSS._hit(I, x, y) == "mods" then px, py = x, y break end
    end
    if px then break end
  end
  ok(px ~= nil, "MANAGE MODS could not be located for the transport test")
  I.tab = "sentinel"
  TRANSPORT.queue = {
    { kind = "down", id = 1, x = px, y = py },
    { kind = "up",   id = 1, x = px, y = py },
  }
  SecondScreen.pumpInput(host)
  TRANSPORT.queue = nil
  ok(I.tab == "mods",
     "a down/up delivered by the transport left the launcher on %q",
     tostring(I.tab))
end

section('11. lower-panel text is independent of the selected cartridge font')
do
  local current, sizes = fakeFont, {}
  love.graphics.newFont = function(size)
    sizes[#sizes+1]=size
    return {getWidth=function(_,s) return #tostring(s)*4 end,getHeight=function() return size end}
  end
  love.graphics.setFont = function(font) current=font end
  love.graphics.getFont = function() return current end
  local expected
  for _, id in ipairs(require('src.core.GameVersion').ORDER) do
    I.tab=id
    current={getHeight=function() return 30 end,getWidth=function(_,s) return #s*20 end}
    ok(LSS.tick(I),'lower launcher draws after selecting %s',id)
    expected=expected or current
    ok(current==expected and current:getHeight()==8,'stable lower font for %s',id)
  end
  ok(#sizes==1,'lower launcher font is allocated once')
end
io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
