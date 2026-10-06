-- tools/gen4_bag_harness/main.lua
--
-- PLATINUM'S BAG, RENDERED in the states that matter, into bag.png (LOVE save
-- directory): every one of the eight pockets with a few items in it (the boy's
-- bag), the girl's bag, a long pocket scrolled to the middle and to the end,
-- CLOSE BAG selected, an empty pocket, a cache without the bag art (the
-- fallbacks) and the bottom screen.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_bag_harness
--
-- (run from the repository root).  The cache needs `gen4_bag_art` (see
-- tools/gen4_art_extract `bag`).

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

    -- a handful of items from every pocket, in id order
    local byPocket = {}
    local ids = {}
    for id, rec in pairs(Data.items or {}) do
      if type(id) == "number" and type(rec) == "table" and id > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local p = Data.items[id].fieldPocket or 0
      byPocket[p] = byPocket[p] or {}
      table.insert(byPocket[p], id)
    end
    local function makeSave(per, gender, only)
      local inv, order = {}, {}
      for p = 0, 7 do
        local list = byPocket[p] or {}
        local n = (only and only ~= p) and 0 or math.min(per, #list)
        if only == nil and p == 4 then n = 0 end -- an empty BERRIES pocket
        for i = 1, n do
          local key = ("ITEM_%03d"):format(list[i])
          inv[key] = (i * 7) % 120 + 1
          order[#order + 1] = key
        end
      end
      return { inventory = inv, bagOrder = order, player = { gender = gender }, options = {}, badges = {} }
    end
    local function makeGame(save)
      return { data = Data, save = save,
        input = { wasPressed = function() return false end, isDown = function() return false end },
        stack = { pop = function() end, push = function() end } }
    end
    local Bag = require("src.ui.Gen4BagMenu")
    local function move(s, n)
      for _ = 1, n do
        if s.moveCursor then s:moveCursor(1) else s.index = math.min(#s.rows, s.index + 1); s:clampScroll() end
      end
    end

    local scenes = {}
    for p = 1, 8 do
      scenes[#scenes + 1] = { "pocket " .. p, function(s) s.pocket = p; s.index = 1; s.top = 1; s:rebuild() end,
        function() return makeSave(4, "boy") end }
    end
    scenes[#scenes + 1] = { "girl", function(s) s.pocket = 3; s:rebuild(); s.index = 2; s:clampScroll() end,
      function() return makeSave(4, "girl") end }
    scenes[#scenes + 1] = { "long, middle", function(s) s.pocket = 1; s:rebuild(); move(s, 9) end,
      function() return makeSave(20, "boy", 0) end }
    scenes[#scenes + 1] = { "long, close", function(s) s.pocket = 1; s:rebuild(); move(s, 40) end,
      function() return makeSave(20, "boy", 0) end }
    scenes[#scenes + 1] = { "tm pocket", function(s) s.pocket = 4; s:rebuild(); move(s, 1) end,
      function() return makeSave(12, "boy", 3) end }
    scenes[#scenes + 1] = { "no bag art", function(s) s.bagArt = {} end,
      function() return makeSave(4, "boy") end }

    local pages = {}
    for k, sc in ipairs(scenes) do
      local screen = Bag.new(makeGame(sc[3]()), {})
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
      print(sc[1], screen.pocket, screen.index, #screen.rows)
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
    sheet:newImageData():encode("png", "bag.png")

    -- THE ACTION MENU, TRASH, MOVING AND THE TOUCH SCREEN, into bag_touch.png:
    -- each scene drives the screen through its own update() with scripted
    -- presses, and draws the top and bottom screens side by side
    local function press(s, ...)
      local keys = {}
      for _, k in ipairs({ ... }) do keys[k] = true end
      s.game.input = { wasPressed = function(_, k) return keys[k] or false end, isDown = function() return false end }
      s:update()
      s.game.input = { wasPressed = function() return false end, isDown = function() return false end }
    end
    local function idle(s, n) for _ = 1, n do s:update() end end
    local function pocketOf(s, p) s.pocket = p; s.listPos, s.cursorPos = 0, 1; s:rebuild() end
    local touchScenes = {
      { "ITEMS: A opens the actions", function(s) pocketOf(s, 1); press(s, "a") end },
      { "MEDICINE actions, cursor on TRASH", function(s) pocketOf(s, 2); press(s, "a"); press(s, "down"); press(s, "down") end },
      { "KEY ITEMS actions", function(s) pocketOf(s, 8); press(s, "a") end },
      { "TMs: stats instead of the message", function(s) pocketOf(s, 4); press(s, "a") end },
      { "BERRIES: CHECK TAG, narrow box", function(s) pocketOf(s, 5); press(s, "a") end,
        function() return makeSave(4, "boy", 4) end },
      { "TRASH: how many", function(s)
          pocketOf(s, 1); press(s, "a")
          for _ = 1, 4 do press(s, "down") end
          -- walk to TRASH whatever the menu holds
          local m = s.menu
          for i, a in ipairs(m.rows) do if a == "trash" then m.index = i end end
          press(s, "a"); press(s, "up"); press(s, "up")
        end },
      { "TRASH: is it OK", function(s)
          pocketOf(s, 1); press(s, "a")
          for i, a in ipairs(s.menu.rows) do if a == "trash" then s.menu.index = i end end
          press(s, "a"); press(s, "up"); press(s, "a")
        end },
      { "TRASH: threw away", function(s)
          pocketOf(s, 1); press(s, "a")
          for i, a in ipairs(s.menu.rows) do if a == "trash" then s.menu.index = i end end
          press(s, "a"); press(s, "up"); press(s, "a"); press(s, "a")
        end },
      { "SELECT: moving, bar two down", function(s) pocketOf(s, 1); press(s, "select"); press(s, "down"); press(s, "down") end },
      { "moved: first item now third", function(s)
          pocketOf(s, 1); press(s, "select"); press(s, "down"); press(s, "down"); press(s, "down"); press(s, "a")
        end },
      { "touch: MEDICINE button pressed", function(s) s:touchpressed("t", 30, 100); idle(s, 3) end },
      { "touch: released, button lit", function(s) s:touchpressed("t", 30, 100); idle(s, 4); s:touchreleased("t"); idle(s, 4) end },
      { "touch: dial button = A", function(s) pocketOf(s, 1); s:touchpressed("t", 128, 80); idle(s, 1) end },
      { "touch: dial turned four steps", function(s)
          pocketOf(s, 1)
          -- a quarter turn anticlockwise round the ring, radius 50: down
          s:touchpressed("t", 128, 30)
          for k = 1, 16 do
            local a = math.rad(-90 - k * 90 / 16)
            s:touchmoved("t", 128 + 50 * math.cos(a), 80 + 50 * math.sin(a)); idle(s, 1)
          end
          idle(s, 6)
        end, function() return makeSave(20, "boy", 0) end },
    }
    local tiles = {}
    for _, sc in ipairs(touchScenes) do
      local screen = Bag.new(makeGame((sc[3] or function() return makeSave(6, "boy") end)()), {})
      sc[2](screen)
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
      print(sc[1], "pocket " .. screen.pocket, "index " .. screen.index, "dial " .. tostring(screen.dialRotation),
        screen.menu and ("menu " .. table.concat(screen.menu.rows, ",")) or "")
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
    tsheet:newImageData():encode("png", "bag_touch.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
