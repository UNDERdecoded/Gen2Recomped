-- tools/gen4_poketch_harness/main.lua
--
-- PLATINUM'S POKETCH, every app in the states that matter, rendered into
-- poketch.png (or $POKEPORT_OUT/poketch.png): the clock apps at a fixed time,
-- the counters with values, the timers running and sounding, the party apps
-- with a party carrying a fainted member, an egg and held items, and so on.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_poketch_harness [filter]
--
-- (run from the repository root). Needs `gen4_poketch_art` / `gen4_poketch_ink`
-- (tools/gen4_art_extract `poketch`).

function love.load(args)
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then
      local Assets = require("src.render.Assets")
      local realImage, held = Assets.image, {}
      Assets.image = function(path, ...)
        if type(path) == "string" and not held[path] then
          local f = io.open(assetRoot .. "/" .. path, "rb")
          if f then
            local bytes = f:read("*a"); f:close()
            local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
            if okI then img:setFilter("nearest", "nearest"); held[path] = img end
          end
        end
        return held[path] or realImage(path, ...)
      end
    end
    -- a fixed clock: 10:42 on Tuesday 14 October 2025
    local realDate = os.date
    os.date = function(fmt, t)
      if fmt == "*t" and t == nil then
        return { year = 2025, month = 10, day = 14, hour = 10, min = 42, sec = 30, wday = 3, yday = 287, isdst = false }
      end
      return realDate(fmt, t)
    end
    package.loaded["src.ui.SecondScreen"] = { mode = function() return "off" end,
      toLocal = function(_, x, y) return x, y end, drawFrame = function() end,
      draw = function(_, fn) fn() end }
    local Data = require("src.core.Data")
    Data:load()
    require("src.render.Font").load(Data)
    pcall(function() require("src.ui.Theme").load(Data) end)
    package.loaded["src.core.Sound"] = { playCry = function() end, play = function() end, playSfx = function() end }

    local function mon(species, level, hp, max, extra)
      local m = { species = species, level = level, hp = hp, stats = { hp = max }, maxHp = max,
                  friendship = 70, gender = "male", personality = 0 }
      for k, v in pairs(extra or {}) do m[k] = v end
      return m
    end
    local function makeGame()
      local party = {
        mon(392, 42, 120, 120, { item = 1, friendship = 255 }),
        mon(395, 38, 50, 110, { item = 137, friendship = 160 }),
        mon(25, 30, 70, 70, { status = "PAR", friendship = 100 }),
        mon(133, 25, 0, 60, { friendship = 40 }),
        mon(175, 1, 10, 10, { isEgg = true, friendship = 0 }),
        mon(54, 22, 6, 64, { friendship = 0 }),
      }
      return { data = Data, save = { party = party, options = {}, inventory = {}, poketch = {},
        player = { gender = "boy" },
        daycare = { breed = { { mon = party[2] }, { mon = party[3] } } } },
        input = { wasPressed = function() return false end, isDown = function() return false end },
        stack = { pop = function() end, push = function() end } }
    end
    local P = require("src.ui.Gen4Poketch")
    local function find(watch, name)
      for i, app in ipairs(watch.apps) do if app.name == name then return i end end
    end
    local filter = args and args[1]
    local scenes = {
      { "Digital Watch" }, { "Analog Watch" }, { "Calendar", function(w, s) s.calendar = { ["2025-10-03"] = true } end },
      { "Counter", function(w, s) s.counter = 1234 end }, { "Pedometer", function(w, s) s.steps = 4072 end },
      { "Stopwatch", function(w, s) s.stopwatch = 754.37 end },
      { "Stopwatch", function(w, s) s.stopwatch = 3.5; s.stopwatchRunning = true end, 20 },
      { "Kitchen Timer", function(w, s) s.timerDuration = 185; s.timer = 185 end },
      { "Kitchen Timer", function(w, s) s.timerDuration = 185; s.timer = 120; s.timerRunning = true end, 10 },
      { "Kitchen Timer", function(w, s) s.timerFinished = true; s.timer = 0 end, 20 },
      { "Alarm Clock", function(w, s) s.alarmHour = 7; s.alarmMinute = 30 end },
      { "Alarm Clock", function(w, s) s.alarmHour = 7; s.alarmMinute = 30; s.alarmEnabled = true end },
      { "Calculator", function(w, s) s.calculator = { display = "12345.6" } end },
      { "Memo Pad", function(w, s) s.memo = {}; for i = 0, 60 do s.memo[(40 + i) * 96 + 20 + i] = true end end },
      { "Dot Artist", function(w, s) s.dots = { [0] = 1, [1] = 2, [2] = 3, [100] = 3 } end },
      { "Pokémon List" }, { "Friendship Checker" }, { "Day-Care Checker" },
      { "Pokémon History", function(w, s) s.history = { { species = 25 }, { species = 133 }, { species = 392 } } end },
      { "Coin Toss", function(w, s) s.coin = "tails" end }, { "Roulette", function(w, s) s.roulette = 40 end },
      { "Move Tester", function(w, s) s.moveTester = { 2, 5, 18 } end },
      { "Matchup Checker", function(w, s) s.matchup = { 1, 2 }; s.compatibility = 70 end },
      { "Dowsing Machine" }, { "Marking Map" }, { "Berry Searcher" },
      { "Color Changer", function(w, s) s.color = 3 end }, { "Trainer Counter" },
    }
    local pages = {}
    for _, sc in ipairs(scenes) do
      if not filter or sc[1]:find(filter, 1, true) then
        local game = makeGame()
        local watch = P.new(game)
        local i = find(watch, sc[1])
        if i then
          watch.index = i
          if sc[2] then sc[2](watch, game.save.poketch) end
          for _ = 1, (sc[3] or 1) do watch:updatePresentation(1 / 60) end
          local cv = love.graphics.newCanvas(256, 192)
          love.graphics.setCanvas(cv)
          love.graphics.clear(0, 0, 0, 1)
          watch:drawWatch()
          love.graphics.setCanvas()
          pages[#pages + 1] = cv
        else
          print("no app " .. sc[1])
        end
      end
    end
    local perRow = 4
    local rows = math.ceil(#pages / perRow)
    local sheet = love.graphics.newCanvas(perRow * 260, rows * 196)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(1, 0, 1, 1)
    for i, p in ipairs(pages) do
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, ((i - 1) % perRow) * 260, math.floor((i - 1) / perRow) * 196)
    end
    love.graphics.setCanvas()
    local out = os.getenv("POKEPORT_OUT")
    local png = sheet:newImageData():encode("png")
    if out then
      local f = assert(io.open(out .. "/poketch.png", "wb")); f:write(png:getString()); f:close()
      print("saved to " .. out .. "/poketch.png")
    else
      love.filesystem.write("poketch.png", png)
      print("saved to " .. love.filesystem.getSaveDirectory())
    end
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
