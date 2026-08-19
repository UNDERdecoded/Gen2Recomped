-- Draws that want the SCREEN's resolution, not the Game Boy's.
--
-- Everything the game draws lands in a 160x144 canvas that is then blown up to
-- the window -- which is the whole point, and why the art looks like the art.
-- But a few things are not Game Boy art: a live 3D model standing in for a
-- Pokemon's pic is geometry, and rasterising it into a 56x56 well before
-- multiplying it by six is throwing away detail that exists and then
-- magnifying what is left.  The model comes out looking like a photograph of a
-- sprite.
--
-- So a caller drawing in Game Boy space can hand the drawing forward instead:
--
--     NativeOverlay.queue(function(dx, dy, dw, dh) ... end, x, y, w, h)
--
-- The rect is in 160x144 canvas coordinates -- the same numbers the caller
-- would have drawn at -- and the callback is invoked after the frame is
-- composited, with that rect mapped to real screen pixels.  A model asked to
-- render at 358x358 instead of 56x56 is simply sharp.
--
-- TWO THINGS THIS CHANGES, both of which the queue handles:
--
--   * ORDER.  These run over the finished composite, so anything the Game Boy
--     canvas drew on top of the rect would otherwise end up underneath.  The
--     scissor in force at queue time is captured and re-applied (mapped), so a
--     caller that was already clipping -- the battle clips pics to the rows
--     the move menu does not cover -- keeps exactly the clip it had.
--   * PALETTE.  Nothing here passes through the SGB/DMG zone remap, because it
--     is composited after it.  That is correct for full-colour geometry and is
--     the reason a caller no longer needs markTrueColor for it.
--
-- The queue is per frame and cleared by beginFrame, so a frame that ends
-- early -- a state that returns before endFrame, a crash caught upstream --
-- cannot leak a stale draw into the next one.

local NativeOverlay = {}

local queue = {}

-- `draw(dx, dy, dw, dh)` is called with the rect in screen units.
-- Returns false when there is nothing to queue with.
function NativeOverlay.queue(draw, x, y, w, h)
  if type(draw) ~= "function" then return false end
  if not (tonumber(x) and tonumber(y) and tonumber(w) and tonumber(h)) then
    return false
  end
  local cx, cy, cw, ch
  local G = love and love.graphics
  if G and G.getScissor then cx, cy, cw, ch = G.getScissor() end
  queue[#queue + 1] = {
    draw = draw, x = x, y = y, w = w, h = h,
    cx = cx, cy = cy, cw = cw, ch = ch,
  }
  return true
end

function NativeOverlay.pending()
  return #queue
end

function NativeOverlay.clear()
  queue = {}
end

-- Map every queued rect from canvas space to screen units and run it.
-- `ox, oy` is the letterbox origin and `sx, sy` the per-axis scale -- the same
-- numbers the UI blit used, so a queued rect lands exactly where the pixels it
-- replaces landed.
function NativeOverlay.flush(ox, oy, sx, sy)
  if not queue[1] then return end
  -- swap the list out first: a callback that queues again is drawing for the
  -- NEXT frame, not extending this one into an unbounded loop
  local items = queue
  queue = {}
  if not (tonumber(ox) and tonumber(oy) and tonumber(sx) and tonumber(sy)) then
    return
  end

  local G = love and love.graphics
  if not G then return end
  local canScissor = G.getScissor and G.setScissor and G.intersectScissor

  for _, item in ipairs(items) do
    local dx, dy = ox + item.x * sx, oy + item.y * sy
    local dw, dh = item.w * sx, item.h * sy

    local px, py, pw, ph
    if canScissor and item.cx then
      px, py, pw, ph = G.getScissor()
      G.intersectScissor(ox + item.cx * sx, oy + item.cy * sy,
                         item.cw * sx, item.ch * sy)
    end

    local r, g, b, a = G.getColor()
    G.setColor(1, 1, 1, 1)
    pcall(item.draw, dx, dy, dw, dh)
    G.setColor(r, g, b, a)

    if px ~= nil then
      G.setScissor(px, py, pw, ph)
    elseif canScissor and item.cx then
      G.setScissor()
    end
  end
end

return NativeOverlay
