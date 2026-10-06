-- tools/gen4_pokedex_harness/main.lua
--
-- PLATINUM'S POKEDEX LIST (top screen), rendered in Sinnoh mode, National
-- mode, search results and halfway through a scroll step, side by side, into
-- pokedex_list.png (LOVE save directory).
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_pokedex_harness

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
    package.loaded["src.ui.SecondScreen"] = { mode = function() return "display" end,
      stowed = function() return true end, raised = function() return false end,
      draw = function() end }
    -- a save that has met the first stretch of the Sinnoh dex, with gaps
    local orders = (Data.gen4_dex or {}).orders or {}
    local sinnoh = orders.sinnoh or {}
    local seen, owned = {}, {}
    for i = 1, 40 do
      local id = sinnoh[i]
      if id and i % 7 ~= 3 then
        seen[id] = true
        if i % 3 ~= 0 then owned[id] = true end
      end
    end
    local game = { data = Data, save = { options = {}, party = {},
        pokedex = { seen = seen, owned = owned, national = true } },
      input = { wasPressed = function() return false end, isDown = function() return false end },
      stack = { pop = function() end, push = function() end } }
    local Dex = require("src.ui.Gen4Pokedex")
    local pages = {}
    local function shoot(screen)
      local cv = love.graphics.newCanvas(256, 192)
      love.graphics.setCanvas(cv)
      love.graphics.clear(0, 0, 0, 1)
      screen:drawList()
      love.graphics.setCanvas()
      pages[#pages + 1] = cv
    end
    local dex = Dex.new(game)
    dex.national = false; dex.entries = dex:listing()
    dex.index = 5; dex.listAnim = nil
    shoot(dex)                                  -- Sinnoh, owned selected
    dex.index = 3; shoot(dex)                   -- Sinnoh, unseen gap selected
    dex.index = 4; dex:move(1); dex.listAnim.counter = 320; shoot(dex) -- mid-step
    local nat = Dex.new(game)
    nat.national = true; nat.entries = nat:listing(); nat.index = math.min(392, #nat.entries); nat.listAnim = nil
    shoot(nat)                                  -- National
    local res = Dex.new(game)
    res.national = false; res.entries = res:listing()
    local list = {}
    for _, id in ipairs(res.entries) do if res:status(id) then list[#list + 1] = id end end
    res.entries = list; res.filtered = true; res.index = 2; res.listAnim = nil
    shoot(res)                                  -- search results
    local sheet = love.graphics.newCanvas(3 * 260, 2 * 196)
    love.graphics.setCanvas(sheet)
    for i, p in ipairs(pages) do
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(p, ((i - 1) % 3) * 260, math.floor((i - 1) / 3) * 196)
    end
    love.graphics.setCanvas()
    sheet:newImageData():encode("png", "pokedex_list.png")
    print("saved to " .. love.filesystem.getSaveDirectory())
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
