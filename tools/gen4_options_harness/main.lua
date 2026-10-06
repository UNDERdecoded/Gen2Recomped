-- tools/gen4_options_harness/main.lua
--
-- PLATINUM'S OPTIONS SCREEN, RENDERED with the cursor on each row in turn,
-- the bottom screen beside the first, into options.png (LOVE save directory).
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_options_harness

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    -- POKEPORT_ASSET_ROOT: the launcher mounts the cache's `assets/`; this
    -- harness has no launcher, so read the pictures (contest art, fonts,
    -- sprites) straight from that folder, as the battle harness does.
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
    local topFn
    package.loaded["src.ui.SecondScreen"] = { mode = function() return "display" end,
      stowed = function() return false end, draw = function(_, fn) topFn = fn end }
    local game = { data = Data, save = { options = {} },
      input = { wasPressed = function() return false end, isDown = function() return false end },
      stack = { pop = function() end, push = function() end } }
    local screen = require("src.ui.Gen4Options").new(game, {})
    local pages = {}
    for row = 1, 3 do
      screen.index = row
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 1)
      topFn = nil
      screen:draw()
      love.graphics.setCanvas()
      pages[#pages + 1] = cv
      if row == 1 and topFn then
        local b = love.graphics.newCanvas(256, 192)
        love.graphics.setCanvas(b)
        love.graphics.clear(0, 0, 0, 1)
        topFn()
        love.graphics.setCanvas()
        pages[#pages + 1] = b
      end
    end
    local sheet = love.graphics.newCanvas(#pages * 260, 192)
    love.graphics.setCanvas(sheet)
    for i, p in ipairs(pages) do love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(p, (i - 1) * 260, 0) end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "options.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
