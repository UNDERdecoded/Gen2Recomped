-- Game Boy Printer stand-in.  Yellow's printer jobs
-- (engine/printer/printer.asm: PrintPokedexEntry and friends) drove a
-- serial thermal printer; this port renders the same printout into a PNG
-- under prints/ in the save directory instead, and the caller shows a
-- dialog with where it landed.  Scaled up 4x so the "print" is legible
-- on a modern screen.

local Logger = require("src.core.Logger")

local Printer = {}

local SCALE = 4

-- Render drawFn (which draws a w x h GB-pixel image at 0,0) into
-- prints/<name>_<stamp>.png.  Returns the save-dir-relative path, or nil
-- and an error string (headless / no canvas support degrades gracefully).
function Printer.save(name, w, h, drawFn)
  if not (love.graphics and love.graphics.newCanvas) then
    return nil, "no graphics"
  end
  local ok, canvas = pcall(love.graphics.newCanvas, w * SCALE, h * SCALE)
  if not ok then return nil, tostring(canvas) end
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.scale(SCALE, SCALE)
  love.graphics.clear(1, 1, 1, 1)
  love.graphics.setColor(1, 1, 1, 1)
  local drawOk, drawErr = pcall(drawFn)
  love.graphics.pop()
  if not drawOk then return nil, tostring(drawErr) end
  local data
  ok, data = pcall(canvas.newImageData, canvas)
  if not ok then return nil, tostring(data) end
  love.filesystem.createDirectory("prints")
  local path = ("prints/%s_%s.png"):format(name, os.date("%Y-%m-%d_%H%M%S"))
  local encOk, err = pcall(data.encode, data, "png", path)
  if not encOk then return nil, tostring(err) end
  Logger.info("printed %s -> %s/%s",
    name, love.filesystem.getSaveDirectory(), path)
  return path
end

return Printer
