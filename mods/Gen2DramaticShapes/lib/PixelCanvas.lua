local V = ...

local PixelCanvas = {}

function PixelCanvas.new(w, h)
  return pcall(love.graphics.newCanvas, w, h, { dpiscale = 1 })
end

return PixelCanvas
