-- Round 14 (a port feature, not cartridge behaviour): seamless room changes.
--
-- The cartridge changes rooms behind a fade or a full-screen scroll with
-- Link held still.  Here, unless the "CARTRIDGE TRANSITIONS" option (the
-- runtime's menu, off by default) asks for the original:
-- * a warp whose landing spot is where Link already stands on the map
--   (border warps that keep the world coordinate, rooms that tile an area
--   or a dungeon floor) switches rooms at once -- the room's code,
--   entities, flags, the follower and scripts load exactly as on a normal
--   change (Field:enterRoom) -- and the camera eases from where it was to
--   the new room's camera, drawing the rooms around (View.lua), so Link
--   keeps walking with no black screen;
-- * every other warp (doors to interiors, stairs, holes, Minish portals,
--   special warps) takes a quick crossfade: the last picture of the old
--   room fades out over the new one in S.XFADE frames.
-- The rooms near the edge Link walks toward are loaded ahead (View.preload).
local V = require("src.zelda.tmc.View")

local S = {}
S.XFADE = 12       -- frames of the crossfade
S.EASE_MIN = 3     -- camera ease: at least this many px a frame...
S.EASE_DIV = 6     -- ...or 1/6 of the way left
S.NEAR = 40        -- px: a landing this close to Link's map spot is continuous
S.SCROLL_H, S.SCROLL_V = 0x3C, 0x28 -- round 15: the cartridge scroll's frames

local function host(game) return game and game.opts and game.opts.host end

-- the option (Host:gameOption "cartTransitions"); off by default
function S.cartridge(game)
  if game._cartTrans == nil then
    local h = host(game)
    local v = false
    if h and h.gameOption then
      local ok, x = pcall(h.gameOption, h, "cartTransitions")
      v = ok and x == true
    end
    game._cartTrans = v
  end
  return game._cartTrans
end

function S.setCartridge(game, v)
  game._cartTrans = v and true or false
  local h = host(game)
  if h and h.gameOption then pcall(h.gameOption, h, "cartTransitions", game._cartTrans) end
end

-- where a room sits on the map (the festival town takes the town's place,
-- as Field:enterRoom places it)
local function roomOrigin(f, area, room, hdr)
  if area == 0x15 and room == 0 then
    local town = f.assets:area(0x02)
    local t = town and town.rooms and town.rooms[0]
    if t then return t.x + 0x130, t.y end
  end
  return hdr.x, hdr.y
end
S.roomOrigin = roomOrigin

-- Field:startTransition: pick the kind of change for `tr`
function S.plan(f, tr, exit, dir)
  if S.cartridge(f.game) then tr.kind = "cart" return end
  tr.kind = "xfade"
  if dir == nil then return end
  local dest = f.assets:area(exit.area)
  local hdr = dest and dest.rooms and dest.rooms[exit.room]
  if not hdr then return end
  local ox, oy = roomOrigin(f, exit.area, exit.room, hdr)
  local p, r = f.player, f.room
  local dx = (ox + tr.x) - (r.x + p.x)
  local dy = (oy + tr.y) - (r.y + p.y)
  if math.abs(dx) <= S.NEAR and math.abs(dy) <= S.NEAR
     and V.isOverworld(f.assets, exit.area) == V.isOverworld(f.assets, r.area) then
    tr.kind = "scroll"
    -- Link stays where he is on the map, just inside the new room; then
    -- he walks on to the spot the cartridge sets him down on (its scroll
    -- carries him there), so the room starts as it does on the cartridge
    local nx, ny = r.x + p.x - ox, r.y + p.y - oy
    tr.cartX, tr.cartY = tr.x, tr.y
    tr.x = math.max(5, math.min(hdr.w - 5, nx))
    tr.y = math.max(6, math.min(hdr.h - 3, ny))
  end
end

-- after the switch of a "scroll" change: the camera starts where it was on
-- the map and eases to the new room's camera
function S.afterScroll(f, old, tr)
  local r = f.room
  local p = f.player
  -- round 15: the cartridge's border scroll (scroll.c Scroll2Sub2) runs 60
  -- frames left / right ($3C) and 40 up / down ($28) with the game held:
  -- the new room's enemies do not act before it would have ended
  if tr and tr.cartX then
    local horiz = math.abs((old.room.x + old.camX) - (r.x + f.camX)) > math.abs((old.room.y + old.camY) - (r.y + f.camY))
    f.enemyHold = horiz and S.SCROLL_H or S.SCROLL_V
  end
  -- (not when the new room already drives Link: a mine cart ride crossing
  -- rooms, Minecart.onEnterRoom)
  if tr and tr.cartX and p and p.state == "normal" and not f.cartRide and (math.abs(tr.cartX - p.x) >= 1 or math.abs(tr.cartY - p.y) >= 1) then
    local tx, ty = tr.cartX, tr.cartY
    p.state = "ext"
    p.scrollWalk = 64
    p:setAnim(p:animFor("walk"))
    p.extUpdate = function(pl)
      local dx, dy = tx - pl.x, ty - pl.y
      local s = 1.25 -- the walking speed
      pl.x = pl.x + math.max(-s, math.min(s, dx))
      pl.y = pl.y + math.max(-s, math.min(s, dy))
      pl.moving = true
      pl.anim:update(1)
      pl.scrollWalk = pl.scrollWalk - 1
      if (math.abs(tx - pl.x) < 0.01 and math.abs(ty - pl.y) < 0.01) or pl.scrollWalk <= 0 then
        pl.state, pl.extUpdate, pl.scrollWalk, pl.animId = "normal", nil, nil, -1
      end
    end
  end
  V.put(old.room)
  local cx, cy = old.room.x + old.camX - r.x, old.room.y + old.camY - r.y
  if math.abs(cx - f.camX) < 1 and math.abs(cy - f.camY) < 1 then return end
  f.camFree = { x = cx, y = cy, prev = old.room }
  f.camX, f.camY = math.floor(cx), math.floor(cy)
end

-- Field:snapCamera's last step: ease a free camera toward the clamped one
function S.ease(f, tx, ty)
  local c = f.camFree
  local function step(a, b)
    local d = b - a
    local s = math.max(S.EASE_MIN, math.abs(d) / S.EASE_DIV)
    if math.abs(d) <= s then return b end
    return a + (d > 0 and s or -s)
  end
  c.x, c.y = step(c.x, tx), step(c.y, ty)
  f.camX, f.camY = math.floor(c.x), math.floor(c.y)
  if c.x == tx and c.y == ty then f.camFree = nil end
end

-- each frame: load the rooms ahead of an edge Link is near (one a frame)
function S.preload(f)
  if S.cartridge(f.game) then return end
  local p, r = f.player, f.room
  if not (p and r and r.width) then return end
  local m = 64
  if p.x < m or p.y < m or p.x > r.width - m or p.y > r.height - m then
    V.preload(f, p.x - 160, p.y - 120, 320, 240, 1)
  end
end

-- the crossfade's old picture: drawn into a canvas the size of the one
-- being drawn (240x160, or the runtime's zoom canvas)
function S.capture(f, drawFn)
  local tr = f.transition
  if not (tr and tr.kind == "xfade" and tr.phase == "out" and not tr.captured) then return end
  local g = love.graphics
  local cur = g.getCanvas()
  local w, h = 240, 160
  if cur then w, h = cur:getDimensions() end
  local ok, c = pcall(g.newCanvas, w, h)
  if not ok then tr.captured = true return end
  g.push("all")
  g.setCanvas(c)
  g.clear(0, 0, 0, 1)
  g.origin()
  drawFn()
  g.pop()
  tr.capture, tr.captured = c, true
end

-- the old picture over the new one, fading out
function S.drawFade(f)
  local tr = f.transition
  if not (tr and tr.kind == "xfade" and tr.phase == "xfade" and tr.capture) then return end
  local g = love.graphics
  g.push("all")
  g.origin()
  g.setColor(1, 1, 1, 1 - (tr.t or 0) / S.XFADE)
  g.draw(tr.capture, 0, 0)
  g.pop()
end

return S
