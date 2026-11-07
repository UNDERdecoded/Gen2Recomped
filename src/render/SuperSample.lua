-- A SCREEN DRAWN AT A MULTIPLE OF ITSELF, for a window much bigger than it.
--
-- The DS battle lays itself out on the cartridge's 256 x 192 and the renderer
-- blows that canvas up to the window -- five or six window pixels a DS pixel
-- on a desktop, every letter a stack of blocks. Single-screen play is where
-- that shows: there is no second panel, just the one big picture.
--
-- draw(game, fn) runs `fn` -- a draw in the screen's own coordinates -- into a
-- canvas R times the size, under love.graphics.scale(R), with:
--
--   * the scissor calls scaled with it (setScissor / intersectScissor take
--     framebuffer pixels, which the transform does not reach; getScissor
--     answers in the caller's units again);
--   * Font.hd on, so letters come from the smoothed pages (src/render/
--     FontHD.lua) rather than as R-pixel blocks;
--
-- then lays the result into the ordinary UI canvas at 1/R (so a wipe, a
-- capture or a menu over it sees the same picture) and, while the caller is
-- the top of the stack, hands the big canvas to the renderer as its UI source
-- (Renderer.uiOverride: the composite already divides by its size).
--
-- R is the window's own scale for the surface, rounded up, at most MAX.

local SS = {}

SS.MAX = 4

local function scaleFor(renderer)
  -- POKEPORT_SS_SCALE pins it (the battle harness has no real window)
  local pinned = os.getenv and tonumber(os.getenv("POKEPORT_SS_SCALE") or "")
  if pinned then return math.max(1, math.min(SS.MAX, math.floor(pinned))) end
  local okR, R = pcall(function()
    local w, h = renderer:uiSize()
    local pw, ph = renderer:pixelSize()
    local up
    if renderer.uiFill or renderer.splitViewport then up = math.min(pw / w, ph / h)
    else up = renderer:fitScale() end
    return math.max(1, math.min(SS.MAX, math.ceil(up - 0.01)))
  end)
  return okR and R or 1
end
SS.scaleFor = scaleFor

-- is the DS's second screen down (off, or stowed)? -- the one condition every
-- caller shares
function SS.singleScreen(game)
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if not ok then return false end
  if SecondScreen.mode(game) == "off" then return true end
  return SecondScreen.stowed(game) and true or false
end

function SS.draw(game, owner, fn, surfaceW, surfaceH)
  if SS.active then return fn() end
  local Renderer = require("src.render.Renderer")
  local renderer = (game and game.renderer) or Renderer
  local R = scaleFor(renderer)
  if R <= 1 then return fn() end
  local g = love.graphics
  -- the owner's own surface (it is the one asking for this), else the
  -- renderer's
  --
  -- ...UNLESS THE CALLER SAYS WHICH SURFACE THIS FRAME IS IN. Game:draw passes
  -- the stack's top as the owner, and a battle holds a bigger surface than the
  -- DS's 256x192 that a text box or the summary over it asks for. Sizing this
  -- canvas by the box cropped the battle to the box's 256x192 and handed that
  -- to the renderer as the whole UI, which stretched it over the window: the
  -- "zoom on the player's Pokemon" of a move learn (the YES/NO, with no uiSize
  -- of its own, was the one frame that came out right).
  local w, h = surfaceW, surfaceH
  if not (w and h) and owner and owner.uiSize then w, h = owner:uiSize() end
  if not (w and h) then w, h = renderer:uiSize() end
  local key = w .. "x" .. h .. "x" .. R
  local canvas = SS.canvas
  if not canvas or SS.key ~= key then
    if canvas and canvas.release then canvas:release() end
    -- dpiscale 1: R already IS the window's pixels per screen pixel (from
    -- pixelSize); a canvas left at the window's density multiplied that
    -- again -- 3072x2304 (27 MB, nine times the fill) on a 3x phone
    canvas = g.newCanvas(w * R, h * R, { dpiscale = 1 })
    canvas:setFilter("linear", "linear")
    SS.canvas, SS.key = canvas, key
  end
  local Font = require("src.render.Font")
  local setS, interS, getS = g.setScissor, g.intersectScissor, g.getScissor
  g.push("all")
  g.setCanvas(canvas)
  g.clear(0, 0, 0, 0)
  g.origin()
  g.scale(R)
  g.setScissor = function(x, y, sw, sh)
    if x then return setS(x * R, y * R, sw * R, sh * R) end
    return setS()
  end
  g.intersectScissor = function(x, y, sw, sh) return interS(x * R, y * R, sw * R, sh * R) end
  g.getScissor = function()
    local x, y, sw, sh = getS()
    if not x then return nil end
    return x / R, y / R, sw / R, sh / R
  end
  local wasHd = Font.hd
  Font.hd = true
  -- a pass inside this one (the battle's own, under the stack's) just draws
  SS.active = true
  local ok, err = pcall(fn)
  SS.active = false
  Font.hd = wasHd
  g.setScissor, g.intersectScissor, g.getScissor = setS, interS, getS
  g.pop()
  if not ok then error(err, 0) end
  -- ...into the ordinary canvas too, at the screen's own size
  g.setColor(1, 1, 1, 1)
  g.draw(canvas, 0, 0, 0, 1 / R, 1 / R)
  local top = game and game.stack and game.stack.top and game.stack:top()
  if top == owner then renderer.uiOverride = canvas end
end

return SS
