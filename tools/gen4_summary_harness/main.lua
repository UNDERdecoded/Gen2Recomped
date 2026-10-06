-- tools/gen4_summary_harness/main.lua
--
-- PLATINUM'S SUMMARY SCREEN, RENDERED page by page into summary.png (LOVE save
-- directory): info, memo, skills, battle moves, the battle move panel (and a
-- swap in progress), condition, contest moves and their panel, ribbons and the
-- ribbon panel, exit, an egg's memo, the bottom screen, and a cache without
-- the summary art (the fallbacks).
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_summary_harness
--
-- (run from the repository root).  The cache needs `gen4_summary_art` (see
-- tools/gen4_art_extract `summary`).

function love.load()
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
    local Data = require("src.core.Data")
    Data:load()
    require("src.render.Font").load(Data)
    pcall(function() require("src.ui.Theme").load(Data) end)

    local bottomFn
    -- the panel's taps arrive already in its own 256 x 192
    package.loaded["src.ui.SecondScreen"] = { mode = function() return "display" end,
      stowed = function() return false end, draw = function(_, fn) bottomFn = fn end,
      toLocal = function(_, x, y) return x, y end }

    local itemId
    for id, rec in pairs(Data.items or {}) do
      if type(rec) == "table" and rec.pocket == "ITEMS" and id ~= 0 then itemId = id; break end
    end
    local function makeMon()
      return { species = 392, level = 42, hp = 70, maxHp = 120, exp = 80000, nickname = "INFERNAPE",
        stats = { hp = 120, attack = 110, defense = 80, spAttack = 105, spDefense = 75, speed = 115 },
        moves = { { id = 7, pp = 12, ppUps = 0 }, { id = 183, pp = 30 }, { id = 53, pp = 3 } },
        personality = 0x12345678, otId = 0x1234ABCD, otName = "LUCAS", otGender = 0, shiny = true,
        item = itemId, ability = 66, status = "BRN", caughtBall = 4, markings = 5, pokerus = 0x10,
        metLevel = 5, metLocation = "TWINLEAF_TOWN", metYear = 2008, metMonth = 3, metDay = 22,
        ivs = { hp = 20, attack = 31, defense = 10, speed = 25, spAttack = 12, spDefense = 3 },
        contest = { cool = 200, beauty = 60, cute = 30, smart = 120, tough = 255, sheen = 140 },
        ribbons = { [0] = true, [1] = true, [5] = true, [9] = true, [20] = true, [30] = true,
                    [40] = true, [50] = true, [55] = true, [60] = true },
        gender = "male" }
    end
    local function makeGame(mon, noContest)
      return { data = Data, save = { party = { mon }, options = {}, inventory = {}, badges = {},
          flags = { FLAG_G4_0978 = not noContest or nil },
          player = { name = "LUCAS", id = 0x1234ABCD } },
        input = { wasPressed = function() return false end, isDown = function() return false end },
        stack = { pop = function() end, push = function() end } }
    end
    local Summary = require("src.ui.Gen4SummaryMenu")
    local function gotoPage(s, key)
      for i, p in ipairs(s.pages) do if p.key == key then s.page = i end end
    end
    local scenes = {
      { "info", function(s) gotoPage(s, "info") end },
      { "memo", function(s) gotoPage(s, "memo") end },
      { "skills", function(s) gotoPage(s, "skills") end },
      { "moves", function(s) gotoPage(s, "moves") end },
      { "move panel", function(s) gotoPage(s, "moves"); s.moveMode = true; s.moveIndex = 1 end },
      { "move swap", function(s) gotoPage(s, "moves"); s.moveMode = true; s.moveIndex = 3; s.swapMove = 1 end },
      { "condition", function(s) gotoPage(s, "condition"); s.t = 8 + 10 * 6 + 32 + 2 end },
      { "contest moves", function(s) gotoPage(s, "contestMoves") end },
      { "contest panel", function(s) gotoPage(s, "contestMoves"); s.moveMode = true; s.moveIndex = 2 end },
      { "ribbons", function(s) gotoPage(s, "ribbons") end },
      { "ribbon panel", function(s) gotoPage(s, "ribbons"); s.ribbonMode = true; s.ribbonIndex = 6 end },
      { "exit", function(s) gotoPage(s, "exit") end },
      { "egg", function(s) end, function(m) m.isEgg = true; m.egg = true; m.eggCycles = 8; return m end },
      { "no summary art", function(s) gotoPage(s, "info"); s.summaryArt = {} end },
    }
    local pages = {}
    for k, sc in ipairs(scenes) do
      local mon = makeMon()
      if sc[3] then mon = sc[3](mon) end
      local screen = Summary.new(makeGame(mon), mon)
      sc[2](screen)
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 1)
      bottomFn = nil
      screen:draw()
      love.graphics.setCanvas()
      pages[#pages + 1] = cv
      if k == 1 and bottomFn then
        local b = love.graphics.newCanvas(256, 192)
        love.graphics.setCanvas(b)
        love.graphics.clear(0, 0, 0, 1)
        bottomFn()
        love.graphics.setCanvas()
        pages[#pages + 1] = b
      end
      print(sc[1])
    end
    local perRow = 3
    local rows = math.ceil(#pages / perRow)
    local sheet = love.graphics.newCanvas(perRow * 260, rows * 196)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(1, 0, 1, 1)
    for i, p in ipairs(pages) do
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, ((i - 1) % perRow) * 260, math.floor((i - 1) / perRow) * 196)
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "summary.png")

    -- THE TOUCH SCREEN AND THE ANIMATIONS, into summary_touch.png: each scene
    -- is { name, setup(screen, game), noContest }, and draws its top and
    -- bottom screens side by side
    local function run(s, n) for _ = 1, n do s:update(1 / 60) end end
    local touchScenes = {
      { "8 buttons, at rest", function(s) gotoPage(s, "info") end },
      { "tap SKILLS (pressed + circle)", function(s) s:touchpressed("t", 60, 140); run(s, 1) end },
      { "tap circle frame 1", function(s) s:touchpressed("t", 60, 140); run(s, 4) end },
      { "held past the press", function(s) s:touchpressed("t", 60, 140); run(s, 12) end },
      { "released: SKILLS lit", function(s) s:touchpressed("t", 60, 140); run(s, 6); s:touchreleased("t"); run(s, 1) end },
      { "tap RIBBONS", function(s) s:touchpressed("t", 220, 100); run(s, 6); s:touchreleased("t"); run(s, 1) end },
      { "pad clears the lit button", function(s)
          s:touchpressed("t", 60, 140); run(s, 6); s:touchreleased("t"); run(s, 1)
          s.game.input = { wasPressed = function(_, k) return k == "right" end, isDown = function() return false end }
          run(s, 1)
        end },
      { "no Contest Hall: 5 pages", function(s) gotoPage(s, "info") end, true },
      { "no Contest Hall: tap MOVES", function(s) s:touchpressed("t", 190, 140); run(s, 2) end, true },
      { "graph frame 0", function(s) gotoPage(s, "condition"); run(s, 1) end },
      { "graph frame 1", function(s) gotoPage(s, "condition"); run(s, 2) end },
      { "graph frame 2", function(s) gotoPage(s, "condition"); run(s, 3) end },
      { "graph frame 3", function(s) gotoPage(s, "condition"); run(s, 4) end },
      { "graph grown + flash", function(s) gotoPage(s, "condition"); run(s, 5 + 12) end },
    }
    local tiles = {}
    for _, sc in ipairs(touchScenes) do
      local mon = makeMon()
      local game = makeGame(mon, sc[3])
      local screen = Summary.new(game, mon)
      sc[2](screen, game)
      bottomFn = nil
      local top = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(top)
      love.graphics.clear(0, 0, 0, 1)
      screen:draw()
      love.graphics.setCanvas()
      local bottom = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(bottom)
      love.graphics.clear(0, 0, 0, 1)
      if bottomFn then bottomFn() end
      love.graphics.setCanvas()
      tiles[#tiles + 1] = { top, bottom }
      print(sc[1], "page " .. tostring(screen:pageKey()), "visible " .. #screen:visiblePages())
    end
    local tsheet = love.graphics.newCanvas(2 * 520, math.ceil(#tiles / 2) * 196)
    love.graphics.setCanvas(tsheet)
    love.graphics.clear(1, 0, 1, 1)
    for i, t in ipairs(tiles) do
      local x, y = ((i - 1) % 2) * 520, math.floor((i - 1) / 2) * 196
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(t[1], x, y)
      love.graphics.draw(t[2], x + 260, y)
    end
    love.graphics.setCanvas()
    tsheet:newImageData():encode("png", "summary_touch.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
