-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local V = ...
local Card = {}
local Setting = V.require("ModSetting")
Card.setting = Setting.new("renderScale", "RENDER SCALE", { "auto", 1, 2, 3, 4 }, { "AUTO", "1X", "2X", "3X", "4X" })
function Card.mobile()
  local os = love.system and love.system.getOS and love.system.getOS() or ""
  local arch = jit and jit.arch or ""
  return os == "Android"
    or os == "iOS"
    or os == "Horizon"
    or os == "Switch"
    or (os == "Linux" and (arch == "arm" or arch == "arm64"))
end
function Card.factor()
  if V.renderBudget == false then
    return 1
  end
  local value = Card.setting:get()
  if value == "auto" then
    return Card.mobile() and 2 or 1
  end
  return math.max(1, math.min(4, math.floor(tonumber(value) or 1)))
end
function Card.size(w, h)
  local f = Card.factor()
  return math.max(1, math.ceil(w / f)), math.max(1, math.ceil(h / f))
end
local canvas, width, height
function Card.present(image, w, h)
  if image:getWidth() == w and image:getHeight() == h then
    return image
  end
  if not canvas or width ~= w or height ~= h then
    local ok, made = V.require("PixelCanvas").new(w, h)
    if not ok then
      return nil
    end
    Card.invalidate()
    canvas, width, height = made, w, h
    canvas:setFilter("nearest", "nearest")
  end
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.setShader()
  love.graphics.setDepthMode()
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("replace", "premultiplied")
  image:setFilter("nearest", "nearest")
  love.graphics.draw(image, 0, 0, 0, w / image:getWidth(), h / image:getHeight())
  love.graphics.pop()
  return canvas
end
function Card.invalidate()
  if canvas then
    canvas:release()
  end
  canvas, width, height = nil, nil, nil
end
return Card
