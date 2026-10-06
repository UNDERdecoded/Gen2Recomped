-- tools/gen4_pc_mart_harness/main.lua
--
-- PLATINUM'S PC STORAGE, MAIN MENU AND POKE MART, rendered in the states that
-- matter into three sheets in the LOVE save directory:
--
--   pc.png     the box (cursor on a Pokemon, on an empty slot, holding one,
--              on the header, on PARTY PKMN / CLOSE BOX), the party panel, the
--              action menu, the storage-system menu, another wallpaper
--   mainmenu.png  CONTINUE focused (with and without a Pokedex), NEW GAME
--              focused, the list scrolled to its last row, no save
--   mart.png   BUY/SELL/SEE YA! over the field, the buy list, the list
--              scrolled, the quantity window, the confirmation, selling
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_pc_mart_harness
--
-- (run from the repository root).  The cache needs `gen4_box_art`,
-- `gen4_main_menu_art` and `gen4_shop_art` (tools/gen4_art_extract `box`,
-- `mainmenu`, `shop`) for the cartridge pictures; without them every screen
-- draws its fallbacks, which is a state worth seeing too.

local function sheet(pages, name, perRow)
  perRow = perRow or 3
  local rows = math.ceil(#pages / perRow)
  local cv = love.graphics.newCanvas(perRow * 260, rows * 196)
  love.graphics.setCanvas(cv)
  love.graphics.clear(1, 0, 1, 1)
  for i, p in ipairs(pages) do
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(p, ((i - 1) % perRow) * 260, math.floor((i - 1) / perRow) * 196)
  end
  love.graphics.setCanvas()
  cv:newImageData():encode("png", name)
end

local function render(fn, bg)
  local cv = love.graphics.newCanvas(256, 192)
  love.graphics.setCanvas(cv)
  love.graphics.clear(bg and bg[1] or 0, bg and bg[2] or 0, bg and bg[3] or 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  fn()
  love.graphics.setCanvas()
  return cv
end

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
    require("src.pokemon.Boxes").load(Data)
    package.loaded["src.core.Sound"] = { play = function() end, playCry = function() end }

    local function mon(species, level, extra)
      local m = { species = species, level = level, hp = 20, stats = { hp = 20 }, maxHp = 20,
                  moves = { { id = 33 } }, gender = "male", personality = 0, markings = 0 }
      for k, v in pairs(extra or {}) do m[k] = v end
      return m
    end
    local itemId = 17 -- POTION
    local input = { wasPressed = function() return false end, isDown = function() return false end }
    local function newGame(save)
      return { data = Data, save = save, input = input,
        stack = { pop = function() end, push = function() end } }
    end

    -- ------------------------------------------------------------- the PC --
    local function pcSave()
      local save = { party = { mon(392, 42, { item = itemId }), mon(395, 38, { gender = "female" }), mon(25, 30) },
                     options = {}, inventory = {}, badges = {}, currentBox = 1 }
      require("src.pokemon.Boxes").ensure(save)
      local b = save.boxes[1]
      b[1] = mon(387, 5, { item = itemId, markings = 5, nickname = "TURTLE" })
      b[2] = mon(390, 7, { gender = "female" })
      b[3] = mon(393, 9)
      b[8] = mon(54, 20)
      b[9] = mon(175, 1, { isEgg = true, egg = true, nickname = "EGG" })
      b[15] = mon(133, 12)
      b[30] = mon(448, 40)
      save.boxes[2][1] = mon(25, 3)
      return save
    end
    local PC = require("src.ui.Gen4BoxMenu")
    local Storage = require("src.ui.Gen4StorageMenu")
    local pcScenes = {
      { "on a mon", function(s) s.row, s.col = 1, 1 end },
      { "empty slot", function(s) s.row, s.col = 2, 4 end },
      { "holding", function(s) s.row, s.col = 3, 3; s.held = { mon = mon(392, 42), from = 30, box = 1 } end },
      { "header", function(s) s.row = 0 end },
      { "action menu", function(s) s.row, s.col = 1, 2; s:choose(); s.action = 2 end },
      { "party panel", function(s) s.partyOpen = true; s.partyIndex = 2 end },
      { "party cancel", function(s) s.partyOpen = true; s.partyIndex = 7 end },
      { "box 2 wallpaper", function(s) s.game.save.currentBox = 2; s.row, s.col = 1, 1 end },
      { "header menu", function(s) s.row = 0; s:choose() end },
      { "wallpaper page", function(s) s.row = 0; s:choose(); s:runAction("WALLPAPER"); s:runAction(s.menu[2].key); s.action = 3 end },
      { "jump", function(s) s.row = 0; s:choose(); s:runAction("JUMP"); s.action = 12 end },
      { "close box button", function(s) s.row, s.col = 6, 5; s.game.save.boxes[1].wallpaper = 21 end },
      { "egg + release", function(s) s.row, s.col = 2, 3; s:choose(); s:runAction("RELEASE") end },
      { "mark menu", function(s) s.row, s.col = 1, 1; s:choose(); s:runAction("MARK"); s:pickMenuRow(2); s.action = 4 end },
    }
    local pages = {}
    for _, sc in ipairs(pcScenes) do
      local game = newGame(pcSave())
      local screen = PC.new(game, { mode = "move" })
      screen.t = 0
      sc[2](screen)
      pages[#pages + 1] = render(function() screen:draw() end)
      print("pc", sc[1])
    end
    do
      -- an older cache: no gen4_box_art / gen4_box_ink, the fallbacks drawn
      local art, ink = Data.gen4_box_art, Data.gen4_box_ink
      Data.gen4_box_art, Data.gen4_box_ink = nil, nil
      local screen = PC.new(newGame(pcSave()), { mode = "move" })
      screen.row, screen.col = 1, 1
      screen:choose()
      pages[#pages + 1] = render(function() screen:draw() end)
      Data.gen4_box_art, Data.gen4_box_ink = art, ink
    end
    do
      local game = newGame(pcSave())
      local st = Storage.new(game, {})
      st.index = 2
      pages[#pages + 1] = render(function() st:draw() end, { 0.2, 0.4, 0.2 })
    end
    sheet(pages, "pc.png")

    -- ------------------------------------------------------ the main menu --
    local save = { player = { name = "LUCAS", gender = "male" }, pokedex = { seen = { [1] = true, [4] = true }, owned = {} },
                   badges = {}, playSeconds = 3 * 3600 + 7 * 60 }
    package.loaded["src.core.SaveData"] = {
      saveFilename = function() return "harness.sav" end,
      load = function() return save end,
      playSeconds = function(s) return s.playSeconds or 0 end,
    }
    local realInfo = love.filesystem.getInfo
    local haveSave = true
    love.filesystem.getInfo = function(name, ...)
      if name == "harness.sav" then return haveSave and { type = "file" } or nil end
      return realInfo(name, ...)
    end
    local Main = require("src.ui.Gen4MainMenu")
    local mpages = {}
    local menuScenes = {
      { "continue", function(s) s.index = 1 end },
      { "new game", function(s) s.index = 2 end },
      { "last row", function(s) s.index = #s.items end },
      { "no dex", function(s) s.index = 1; s.save = { player = { name = "DAWN", gender = "female" }, pokedex = {}, playSeconds = 59 } end },
      { "no save", function(s) s.index = 1 end, false },
      { "frame cycle", function(s) s.index = 2; s.t = 0.9 end },
    }
    for _, sc in ipairs(menuScenes) do
      haveSave = sc[3] ~= false
      local screen = Main.new(newGame({}), {})
      sc[2](screen)
      mpages[#mpages + 1] = render(function() screen:draw() end)
      print("main menu", sc[1], #screen.items)
    end
    do
      -- Platinum's full list does not fit: eight rows scroll, with arrows
      haveSave = true
      local screen = Main.new(newGame({}), {})
      for i = 1, 5 do screen.items[#screen.items + 1] = { key = "x" .. i, label = "EXTRA " .. i, lines = 1 } end
      screen.index = 6
      screen:targetScroll()
      screen.scrollPos = screen.scrollTarget
      mpages[#mpages + 1] = render(function() screen:draw() end)
      local art, ink = Data.gen4_main_menu_art, Data.gen4_main_menu_ink
      Data.gen4_main_menu_art, Data.gen4_main_menu_ink = nil, nil
      local old = Main.new(newGame({}), {})
      old.index = 2
      mpages[#mpages + 1] = render(function() old:draw() end)
      Data.gen4_main_menu_art, Data.gen4_main_menu_ink = art, ink
    end
    sheet(mpages, "mainmenu.png")

    -- ------------------------------------------------------------ the mart --
    local Shop = require("src.ui.Gen4ShopMenu")
    local stock = { 4, 17, 18, 26, 27, 28, 29, 30, 79, 80 }
    local function shopGame()
      local inv = {}
      if itemId then inv[itemId] = 3 end
      inv[17] = 2
      return newGame({ money = 3200, inventory = inv, party = {}, options = {}, badges = {} })
    end
    local field = function()
      -- a stand-in for the field behind the counter
      love.graphics.setColor(0.45, 0.6, 0.45, 1)
      love.graphics.rectangle("fill", 0, 0, 256, 192)
      love.graphics.setColor(0.6, 0.5, 0.35, 1)
      for y = 0, 192, 16 do love.graphics.rectangle("fill", 0, y, 256, 2) end
      love.graphics.setColor(1, 1, 1, 1)
    end
    local spages = {}
    local shopScenes = {
      { "menu", function(s) s.mode = "menu"; s.cursor = 1 end },
      { "buy", function(s) s.mode = "buy"; s.cursor = 2 end },
      { "buy scrolled", function(s) s.mode = "buy"; s.cursor = 9; s.scroll = 3; s.message = nil end },
      { "cancel row", function(s) s.mode = "buy"; s.cursor = #stock + 1; s.scroll = #stock + 1 - 7 end },
      { "quantity", function(s) s.mode = "buy"; s.cursor = 2; s:choose() ; s.qty = 3 end },
      { "confirm", function(s) s.mode = "buy"; s.cursor = 2; s:choose(); s.qty = 3; s:choose() end },
      { "sell quantity", function(s) s:sellItem(17); s.qty = 2 end },
      { "sell confirm", function(s) s:sellItem(17); s.qty = 2; s:choose(); s.yesNo = 2 end },
      { "cannot sell", function(s) s:sellItem(428) end },
      { "bought", function(s) s.mode = "buy"; s.cursor = 2; s:choose(); s:choose(); s:choose() end },
      { "tm counter", function(s) s.stock = { 328, 329, 420 }; s.mode = "buy"; s.cursor = 1 end },
      { "exit", function(s) s.mode = "exit"; s.message = s:line(1, "Please come again!") end },
    }
    for _, sc in ipairs(shopScenes) do
      local game = shopGame()
      local screen = Shop.new(game, stock, function() end)
      sc[2](screen)
      if screen.mode ~= "menu" and screen.mode ~= "exit" then screen.camStep = screen.camDest end
      spages[#spages + 1] = render(function() field(); screen:draw() end)
      print("mart", sc[1], screen.mode)
    end
    do
      local art = Data.gen4_shop_art
      Data.gen4_shop_art = nil
      local screen = Shop.new(shopGame(), stock, function() end)
      screen.mode = "buy"; screen.cursor = 3; screen.message = nil; screen.camStep = screen.camDest
      spages[#spages + 1] = render(function() field(); screen:draw() end)
      Data.gen4_shop_art = art
    end
    sheet(spages, "mart.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
