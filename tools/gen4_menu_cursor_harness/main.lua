-- tools/gen4_menu_cursor_harness/main.lua
--
-- THE UNDERGROUND MENU AND THE FIELD START MENU, RENDERED with the cursor on
-- a few rows each, into menu_cursor.png (LOVE save directory) -- the
-- cartridge's cursor sprite (palette row 1) and the Underground icons.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_menu_cursor_harness

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
    package.loaded["src.ui.SecondScreen"] = { mode = function() return "off" end,
      stowed = function() return false end, draw = function(_, fn) fn() end, drawFrame = function() end }
    local game = { data = Data, save = { options = {}, player = { gender = "boy" }, playerName = "LUCAS" },
      input = { wasPressed = function() return false end, isDown = function() return false end },
      stack = { pop = function() end, push = function() end } }
    local pages = {}
    local function shot(screen, index)
      screen.index = index
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(0.35, 0.45, 0.35, 1)
      screen:draw()
      love.graphics.setCanvas()
      pages[#pages + 1] = cv
    end
    local ug = require("src.ui.Gen4UndergroundMenu").new(game, {})
    shot(ug, 1); shot(ug, 4); shot(ug, 6)
    local start = require("src.ui.Gen4StartMenu").new(game, {})
    shot(start, 1); shot(start, 3)
    local sheet = love.graphics.newCanvas(#pages * 260, 192)
    love.graphics.setCanvas(sheet)
    for i, p in ipairs(pages) do love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(p, (i - 1) * 260, 0) end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "menu_cursor.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
