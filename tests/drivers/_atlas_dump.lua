-- scratch: dump a Gen2 tileset atlas, recoloured and magnified, with tile
-- ids labelled, so a template author can see what each tile depicts.
--   ATLAS_TS=TilesetCave SHOT_DIR=shots/vx POKEPORT_DRIVER=tests/drivers/_atlas_dump.lua
return function(game)
  local U = require("tests.drivers.util")
  U.wait(3)
  local id = os.getenv("ATLAS_TS") or "TilesetCave"
  local dir = os.getenv("SHOT_DIR") or "shots"
  local ts = game.data.tilesets[id]
  assert(ts, "unknown tileset " .. id)

  local path = ts.image
  local src = love.image.newImageData(path)
  local iw, ih = src:getDimensions()
  local perRow = iw / 8
  local out = love.image.newImageData(iw, ih)
  local palMap, palColors = ts.palMap, ts.palColors
  for t = 0, (iw / 8) * (ih / 8) - 1 do
    local colors = palColors and palColors[math.min(palMap[t + 1] or 0, #palColors - 1) + 1]
    local ox, oy = (t % perRow) * 8, math.floor(t / perRow) * 8
    for py = 0, 7 do
      for px = 0, 7 do
        local r, g, b, a = src:getPixel(ox + px, oy + py)
        if colors then
          local shade = math.floor(r * 3 + 0.5)
          local c = colors[4 - shade] or colors[1]
          r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
        end
        out:setPixel(ox + px, oy + py, r, g, b, a)
      end
    end
  end
  local img = love.graphics.newImage(out)
  img:setFilter("nearest", "nearest")

  local S = 8
  local cw, ch = iw * S + 40, ih * S + 40
  local canvas = love.graphics.newCanvas(cw, ch)
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0.1, 0.1, 0.12, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, 20, 20, 0, S, S)
  love.graphics.setColor(1, 0, 0, 0.5)
  for tx = 0, perRow do
    love.graphics.line(20 + tx * 8 * S, 20, 20 + tx * 8 * S, 20 + ih * S)
  end
  for ty = 0, ih / 8 do
    love.graphics.line(20, 20 + ty * 8 * S, 20 + iw * S, 20 + ty * 8 * S)
  end
  love.graphics.setColor(1, 1, 0, 1)
  for t = 0, (iw / 8) * (ih / 8) - 1 do
    local ox, oy = 20 + (t % perRow) * 8 * S, 20 + math.floor(t / perRow) * 8 * S
    love.graphics.print(string.format("%02X", t), ox + 2, oy + 2)
  end
  love.graphics.setCanvas()
  local data = canvas:newImageData()
  local path = (os.getenv("SHOT_DIR") or "shots") .. "/atlas_" .. id .. ".png"
  local f = assert(io.open(path, "wb"))
  f:write(data:encode("png"):getString())
  f:close()
  U.log("wrote " .. path .. "  (" .. perRow .. " per row)")
  U.log("RESULT PASS (0 pass, 0 fail)")
end
