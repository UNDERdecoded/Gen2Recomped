-- tools/gen4_naming_harness/main.lua
--
-- PLATINUM'S NAMING SCREEN, RENDERED in a few states (fresh, typing, on the
-- home row, a page landing, a Pokemon's nickname) into naming.png.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_naming_harness

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
    package.loaded["src.ui.SecondScreen"] = { mode = function() return os.getenv("SS") and "display" or "off" end,
      stowed = function() return false end, draw = function(_, fn) topFn = fn end }
    local pressed = {}
    local game = { data = Data, save = { player = { name = "LUCAS", gender = 0 } },
      input = { wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end, isDown = function() return false end },
      stack = { pop = function() end, push = function() end } }
    local N = require("src.ui.Gen4NamingScreen")
    local pages, labels = {}, {}
    local function snap(s, label)
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 1)
      topFn = nil
      s:draw()
      love.graphics.setCanvas()
      pages[#pages + 1], labels[#labels + 1] = cv, label
      if topFn then
        local b = love.graphics.newCanvas(256, 192)
        love.graphics.setCanvas(b); love.graphics.clear(0, 0, 0, 1); topFn(); love.graphics.setCanvas()
        pages[#pages + 1], labels[#labels + 1] = b, label .. " (bottom)"
      end
    end
    local function step(s, key, n)
      if key then pressed[key] = true end
      for _ = 1, (n or 1) do s:update(1 / 60) end
    end
    local s = N.new(game, { title = "Your name?", kind = "player", maxLen = 7 })
    step(s, nil, 10); snap(s, "fresh")
    step(s, "a"); step(s, "right"); step(s, "a"); step(s, nil, 6); snap(s, "typing pop")
    step(s, nil, 20); snap(s, "typed")
    step(s, "up"); step(s, nil, 5); snap(s, "home UPPER")
    step(s, "right"); step(s, "right"); step(s, nil, 3); snap(s, "home Others")
    step(s, "right"); step(s, nil, 3); snap(s, "home BACK")
    step(s, "left"); step(s, "left"); step(s, "a"); step(s, nil, 8); snap(s, "page sliding")
    step(s, nil, 30); snap(s, "page landed")
    local mon = { species = 393, gender = "male" }
    local m = N.new(game, { title = "Nickname?", kind = "pokemon", mon = mon, species = 393, maxLen = 10 })
    step(m, nil, 21); snap(m, "nickname")
    local b = N.new(game, { title = "Box name?", kind = "box", maxLen = 8 })
    step(b, nil, 4); snap(b, "box")
    local cols = 4
    local sheet = love.graphics.newCanvas(cols * 260, math.ceil(#pages / cols) * 206)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(0.1, 0.1, 0.1, 1)
    for i, p in ipairs(pages) do
      local x, y = ((i - 1) % cols) * 260, math.floor((i - 1) / cols) * 206
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, x, y)
      love.graphics.print(labels[i], x + 2, y + 192)
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "naming.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
