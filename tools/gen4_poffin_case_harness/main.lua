-- tools/gen4_poffin_case_harness/main.lua
--
-- THE POFFIN CASE, RENDERED: puts eight Poffins in the save, opens
-- Gen4PoffinCase and draws the top screen in its states -- the list, the list
-- scrolled, the SPICY filter, the action menu, the discard question -- and the
-- bottom screen, into poffin_case.png (LOVE save directory for `bt_gen4`).
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_poffin_case_harness

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
    local P = require("src.pokemon.Gen4Poffin")
    local pressed = {}
    local game = { data = Data, input = { wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end,
      isDown = function() return false end }, save = { gen4Poffins = {}, party = {} } }
    game.stack = { push = function() end, pop = function() end }
    local recipes = {
      { { 10, 0, 0, 0, 0 }, 20 }, { { 0, 12, 0, 0, 0 }, 25 }, { { 0, 0, 30, 0, 0 }, 18 },
      { { 0, 0, 0, 8, 4 }, 30 }, { { 15, 6, 0, 0, 0 }, 22 }, { { 4, 0, 4, 4, 0 }, 35 },
      { { 0, 0, 0, 0, 22 }, 21 }, { { 60, 0, 0, 0, 0 }, 40 },
    }
    for _, r in ipairs(recipes) do P.add(game.save, P.make(r[1], r[2])) end
    local Case = require("src.ui.Gen4PoffinCase")
    local screen = Case.new(game, function() end)
    local pages = {}
    local function snap(fn)
      local c = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 1)
      local okF, errF = pcall(fn)
      love.graphics.setCanvas()
      if not okF then print("draw raised: " .. tostring(errF)) end
      pages[#pages + 1] = c
    end
    local function press(k) pressed[k] = true; screen:update() end
    snap(function() screen:draw() end)
    snap(function() screen:drawBottom() end)
    for _ = 1, 7 do press("down") end
    snap(function() screen:draw() end)
    press("r")
    snap(function() screen:draw() end)
    snap(function() screen:drawBottom() end)
    press("l")
    press("a")
    snap(function() screen:draw() end)
    press("down"); press("a")
    snap(function() screen:draw() end)
    press("a")
    snap(function() screen:draw() end)
    -- the feeding cutscene, sampled
    local Pokemon = require("src.pokemon.Pokemon")
    local mon = Pokemon.new(Data, 393, 20)
    local Feed = require("src.ui.Gen4PoffinFeed")
    local feed = Feed.new(game, { mon = mon, poffin = P.case(game.save)[1], taste = "like", onDone = function() end })
    for f = 1, 200 do
      feed:update(1 / 60)
      if f == 12 or f == 20 or f == 28 or f == 90 or f == 120 or f == 160 then snap(function() feed:draw() end) end
    end
    local cols = 4
    local sheet = love.graphics.newCanvas(cols * 260, math.ceil(#pages / cols) * 196)
    love.graphics.setCanvas(sheet)
    love.graphics.clear(0.1, 0.1, 0.1, 1)
    for i, p in ipairs(pages) do
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, ((i - 1) % cols) * 260, math.floor((i - 1) / cols) * 196)
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "poffin_case.png")
    print(("%d Poffins left; saved to %s"):format(#P.case(game.save), love.filesystem.getSaveDirectory()))
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
