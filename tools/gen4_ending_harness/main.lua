-- tools/gen4_ending_harness/main.lua
--
-- PLATINUM'S HALL OF FAME AND CREDITS, RENDERED: a party of three, the Hall of
-- Fame run through to its last frame, then the credits sampled across their
-- scenes, into ending.png (LOVE save directory for `bt_gen4`).
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_ending_harness

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then
      local Assets = require("src.render.Assets")
      local realImage, cache = Assets.image, {}
      Assets.image = function(path, ...)
        if type(path) == "string" and not cache[path] then
          local f = io.open(assetRoot .. "/" .. path, "rb")
          if f then
            local bytes = f:read("*a"); f:close()
            local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
            if okI then img:setFilter("nearest", "nearest"); cache[path] = img end
          end
        end
        return cache[path] or realImage(path, ...)
      end
    end
    local Data = require("src.core.Data")
    Data:load()
    require("src.render.Font").load(Data)
    local Pokemon = require("src.pokemon.Pokemon")
    local pressed = {}
    local game = { data = Data, input = { wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end,
      isDown = function() return false end },
      save = { player = { name = "LUCAS", gender = tonumber(os.getenv("GENDER") or "0"), id = 52049 }, playTime = 9 * 3600 + 41 * 60,
               party = { Pokemon.new(Data, 395, 50), Pokemon.new(Data, 448, 49), Pokemon.new(Data, 445, 52) } } }
    for _, m in ipairs(game.save.party) do m.metLocation = "R201"; m.otName = "LUCAS" end
    local done = false
    game.stack = { pop = function() done = true end, push = function() end }
    local pages, labels = {}, {}
    local function snap(screen, label)
      local c = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 1)
      local okD, errD = pcall(screen.draw, screen)
      love.graphics.setCanvas()
      if not okD then print("draw raised: " .. tostring(errD)) end
      pages[#pages + 1], labels[#labels + 1] = c, label
    end
    local HoF = require("src.ui.Gen4HallOfFame").new(game, { onDone = function() end })
    local shots = { [40] = true, [120] = true, [190] = true, [250] = true, [560] = true, [700] = true, [790] = true }
    for f = 1, 2000 do
      if shots[f] then snap(HoF, "HoF " .. f) end
      if HoF.waitingForButton then
        snap(HoF, "HoF end")
        for _ = 1, 30 do HoF:update(1 / 60) end
        snap(HoF, "HoF confetti")
        pressed.a = true
      end
      HoF:update(1 / 60)
      if done then break end
    end
    print("hall of fame done:", done)
    done = false
    local C = require("src.ui.Gen4Credits").new(game, { onDone = function() end })
    for _, f in ipairs({ 100, 1700, 2100, 3000, 5000, 6200, 7500, 8100, 8300 }) do
      C.frame = f
      snap(C, "credits " .. f)
    end
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
    sheet:newImageData():encode("png", "ending.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
