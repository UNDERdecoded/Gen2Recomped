-- tools/gen4_poffin_harness/main.lua
--
-- THE POFFIN HOUSE'S COOKING SCREEN, PLAYED BY A SCRIPT AND RENDERED.
--
--   cd <repo>
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_poffin_harness
--
-- Gives the save a Cheri Berry, opens Gen4PoffinCooking, picks the Berry,
-- stirs the way the arrow asks (FOLLOW=0 holds RIGHT only), lifting the
-- finger every so often so the batter slows, and draws
-- every 90th 30 Hz frame into poffin_cook.png in LOVE's save directory for
-- `bt_gen4`, plus the results screen. Prints the Poffin made.

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    -- POKEPORT_ASSET_ROOT: read the pictures from the cache folder, as the
    -- launcher's mount would (the battle and contest harnesses do the same)
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
    local held = {}
    local pressed = {}
    local input = {
      isDown = function(_, k) return held[k] == true end,
      wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v == true end,
    }
    local stack = {}
    local game = { data = Data, input = input,
      save = { inventory = { [149] = 1 }, player = { name = "LUCAS" }, money = 0, party = {} } }
    game.stack = {
      push = function(_, s) stack[#stack + 1] = s end,
      pop = function() stack[#stack] = nil end,
      top = function() return stack[#stack] end,
    }
    local made
    local Cook = require("src.ui.Gen4PoffinCooking")
    -- GROUP=2..4 cooks in a group; the top screen is captured too
    local topFn
    package.loaded["src.ui.SecondScreen"] = { mode = function() return "display" end,
      stowed = function() return false end, draw = function(_, fn) topFn = fn end }
    game.stack:push(Cook.new(game, { group = tonumber(os.getenv("GROUP") or "1"), onDone = function(n) made = n end }))
    local function top() return stack[#stack] end
    top():update(1 / 30)                 -- opens the Berry list
    pressed.a = true
    top():update(1 / 30)                 -- the Menu picks the Cheri Berry
    local cook = stack[1]
    local frames, n = {}, 0
    while cook.mode == "stir" and n < 4000 do
      n = n + 1
      -- hold RIGHT, lifting for 20 frames out of every 120
      local stirring = os.getenv("LIFT") == "0" or (n % 120) >= 20
      local follow = os.getenv("FOLLOW") ~= "0"
      local cw = not follow or cook.stir.dir == 0
      held.right, held.left = stirring and cw, stirring and not cw
      cook:update(1 / 30)
      if n % 90 == 0 or cook.mode ~= "stir" then
        local c = love.graphics.newCanvas(256, 192)
        love.graphics.setCanvas(c)
        love.graphics.clear(0, 0, 0, 1)
        topFn = nil
        cook:draw()
        love.graphics.setCanvas()
        frames[#frames + 1] = { c = c, n = n, v = cook.stir.velocity, p = cook.stir.phase }
        if n == 90 and topFn then
          local t = love.graphics.newCanvas(256, 192)
          love.graphics.setCanvas(t)
          love.graphics.clear(0, 0, 0, 1)
          topFn()
          love.graphics.setCanvas()
          frames[#frames + 1] = { c = t, n = n, v = 0, p = 0 }
        end
      end
    end
    local COLS = 6
    local rows = math.ceil(#frames / COLS)
    local sheet = love.graphics.newCanvas(COLS * 260, rows * 208)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(0.1, 0.1, 0.1, 1)
    for i, f in ipairs(frames) do
      local x, y = ((i - 1) % COLS) * 260, math.floor((i - 1) / COLS) * 208
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(f.c, x, y)
      love.graphics.print(("%d v=%d ph=%d"):format(f.n, f.v, f.p), x + 2, y + 193)
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "poffin_cook.png")
    local s = cook.stir
    print(("stirred %d frames (%d real), burns %d, spills %d, mode %s"):format(s.frames, n, s.burns, s.spills, cook.mode))
    local P = require("src.pokemon.Gen4Poffin")
    local p = cook.poffin
    if p then
      print(("made: %s Lv.%d flavors %s smooth %d"):format(P.name(Data, p), P.level(p), table.concat(p.flavors, ","), p.smoothness))
      for _, l in ipairs(cook.lines or {}) do print("  " .. l) end
      print("  " .. tostring(cook.message))
    end
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
