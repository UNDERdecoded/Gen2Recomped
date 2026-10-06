-- tools/gen4_mining_harness/main.lua
--
-- THE MINING GAME, RENDERED: the opening message, the wall before a tap, a
-- few digs mid-animation, a tool switch (the frame of the tap and the one
-- after), a late wall with the crack end, and the closing message -- into
-- mining.png (LOVE save directory).
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_mining_harness

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
    local body
    package.loaded["src.ui.SecondScreen"] = {
      mode = function() return "display" end, stowed = function() return false end,
      drawFrame = function() end, draw = function(_, fn) body = fn end,
      toLocal = function(_, x, y) return x, y end,
    }
    package.loaded["src.ui.Gen4MiningScreen"] = nil
    local Screen = require("src.ui.Gen4MiningScreen")
    love.math.setRandomSeed(7)
    local pressed = {}
    local game = { data = Data, save = { player = { id = 1 }, underground = {} },
      input = { wasPressed = function(_, k) return pressed[k] end, isDown = function() return false end },
      stack = { pop = function() end, push = function() end } }
    local s = assert(Screen.new(game, {}))
    local pages, labels = {}, {}
    local function shot(label)
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 1)
      body = nil
      s:draw()
      if body then body() end
      love.graphics.setCanvas()
      pages[#pages + 1] = cv
      labels[#labels + 1] = label
    end
    local function frames(n) for _ = 1, n do s:update() end end
    local function tap(x, y) s:touchpressed(1, x, y) end

    shot("intro")
    frames(80)                       -- the ping message ends; tutorial (never mined)
    shot("tutorial")
    for _ = 1, 20 do
      if s.phase ~= "tutorial" then break end
      pressed.a = true; frames(1); pressed.a = nil
    end
    shot("digging " .. tostring(s.phase))
    tap(40, 80); frames(3)
    shot("pickaxe +3f")
    tap(100, 120); frames(1); tap(104, 124); frames(6)
    shot("more digs +6f")
    tap(230, 80)                     -- hammer
    shot("hammer tap")
    frames(1)
    shot("hammer +1f")
    frames(4)
    tap(60, 150); frames(2)
    shot("hammer dig +2f")
    -- a weak wall: the crack across the top and its end, mid-shake
    for i = 1, 14 do tap(16 + (i * 37) % 190, 40 + (i * 23) % 140); frames(1) end
    shot("late wall")
    frames(60)
    shot("settled")
    -- dig everything out (cheat: clear the dirt) to reach the closing lines
    for y = 1, #s.state.dirt do for x = 1, #s.state.dirt[y] do s.state.dirt[y][x] = 0 end end
    s.state.dirt[1][1] = 1
    tap(4, 36)
    frames(26)
    shot("won " .. tostring(s.phase))
    frames(61)
    shot("next line")

    local cols = 4
    local rows = math.ceil(#pages / cols)
    local sheet = love.graphics.newCanvas(cols * 260, rows * 206)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(0.2, 0.2, 0.2, 1)
    for i, p in ipairs(pages) do
      local x, y = ((i - 1) % cols) * 260, math.floor((i - 1) / cols) * 206
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, x, y + 14)
      love.graphics.print(labels[i], x + 2, y)
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "mining.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
