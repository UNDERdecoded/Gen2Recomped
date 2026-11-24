-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WIDESCREEN for the Zelda games (2026-11-18, user request: "no black bars on
-- the sides of the screen"). OURS -- the GBA's picture is 240 x 160.
--
-- How it works (ZeldaRuntime draws, the games decide what to show):
--   * The 240 x 160 picture keeps its place and scale (Host:viewport, integer
--     by default). Widescreen widens only the PLAY FIELD to the sides: the
--     field is `width(...)` game pixels wide (= the window's width / scale,
--     rounded up to an even count so the cartridge's 240 stay centred), so at
--     an integer scale it fills the window exactly. Nothing is stretched; the
--     height stays 160 (16:9, 16:10, 21:9 and landscape phones lose their
--     side bars; 4:3 and portrait phones are nearly unchanged).
--   * A game that can show more of its world sets `game.wideScreen = true`
--     and takes the width as viewSize(scale, wide); it returns the field size
--     and, as a third value, the width in normal game pixels the field spans
--     (`wide`, or nil = the cartridge's 240). Its camera, gameplay and
--     culling stay the cartridge's 240 x 160 screen; only drawing widens.
--   * The HUD, text, menus stay in the centred 240 x 160 (drawOverlay into
--     the normal canvas). Full-screen fills the overlay draws (fades, the
--     iris, game over, a menu's backdrop) are continued over the side
--     margins: a filled rectangle touching the 240 picture's left or right
--     edge is recorded (recordEdges) and drawn again over that margin in the
--     same colour and blend (drawEdges), so a fade to black covers the whole
--     window.
--   * The option: WIDESCREEN ON / OFF in the system menu, kept per game
--     (Host:gameOption "widescreen"), ON by default.

local Wide = {}

Wide.BASE_W, Wide.BASE_H = 240, 160
Wide.MAX_W = 512            -- 32:9 and wider keep small bars (a room is 512)

-- the option (per game; nil = default ON)
function Wide.enabled(host)
  if not host then return false end
  if host.extra and host.extra.wide == false then return false end
  local v = host.gameOption and host:gameOption("widescreen")
  return v ~= false
end

function Wide.setEnabled(host, on)
  if host and host.gameOption then host:gameOption("widescreen", on and true or false) end
end

-- The play field's width in game pixels for a window `winW` wide, the
-- picture at x = `x` scaled by `scale` (Host:viewport): enough to reach the
-- farther window edge on both sides, even, 240 .. MAX_W. Pure (tests).
function Wide.widthFor(winW, x, scale)
  scale = tonumber(scale) or 1
  if scale <= 0 then return Wide.BASE_W end
  local left = x
  local right = winW - (x + Wide.BASE_W * scale)
  local m = math.ceil(math.max(left, right) / scale - 1e-6)
  if m <= 0 then return Wide.BASE_W end
  m = math.min(m, (Wide.MAX_W - Wide.BASE_W) / 2)
  return Wide.BASE_W + 2 * m
end

-- the field width for this host now (240 when off or unsupported)
function Wide.width(host, scale, x)
  local g = host and host.game
  if not (g and g.wideScreen and Wide.enabled(host)) then return Wide.BASE_W end
  local w = love.graphics.getDimensions()
  return Wide.widthFor(w, x, scale)
end

-- ----------------------------------------------------- the overlay's edges

-- Run fn with love.graphics.rectangle watched: each filled, square-cornered
-- rectangle drawn at the overlay's own origin that touches x = 0 or x = 240
-- is recorded { side, y, h, r, g, b, a, blend }. Returns the list.
function Wide.recordEdges(fn)
  local lg = love.graphics
  local rect0 = lg.rectangle
  local list = {}
  local W = Wide.BASE_W
  lg.rectangle = function(mode, x, y, w, h, rx, ...)
    if mode == "fill" and not rx and type(x) == "number" and (w or 0) > 0 and (h or 0) > 0 then
      local ax, ay, bx, by = 0, 0, 1, 1
      if lg.transformPoint then
        ax, ay = lg.transformPoint(0, 0)
        bx, by = lg.transformPoint(1, 1)
      end
      if ax == 0 and ay == 0 and bx == 1 and by == 1 then
        local sx, sy0, sw
        if lg.getScissor then sx, sy0, sw = lg.getScissor() end
        if not sx or (sx <= 0 and sx + sw >= W) then
          local left, right = x <= 0 and x + w >= 1, x + w >= W and x <= W - 1
          if left or right then
            local r, g, b, a = lg.getColor()
            local bm, am = lg.getBlendMode()
            if left then list[#list + 1] = { "l", y, h, r, g, b, a, bm, am } end
            if right then list[#list + 1] = { "r", y, h, r, g, b, a, bm, am } end
          end
        end
      end
    end
    return rect0(mode, x, y, w, h, rx, ...)
  end
  local ok, err = pcall(fn)
  lg.rectangle = rect0
  if not ok then error(err, 0) end
  return list
end

-- Draw recorded edge fills over the margins: the picture at (x, y) scaled by
-- `scale`, `margin` game pixels of play field on each side.
function Wide.drawEdges(list, x, y, scale, margin)
  if not list or #list == 0 or (margin or 0) <= 0 then return end
  local lg = love.graphics
  local mw = margin * scale
  local rx = x + Wide.BASE_W * scale
  for _, e in ipairs(list) do
    lg.setBlendMode(e[8] or "alpha", e[9])
    lg.setColor(e[4], e[5], e[6], e[7])
    local ey0 = math.max(0, e[2])
    local ey1 = math.min(Wide.BASE_H, e[2] + e[3])
    if ey1 > ey0 then
      local yy, hh = y + ey0 * scale, (ey1 - ey0) * scale
      if e[1] == "l" then lg.rectangle("fill", x - mw, yy, mw, hh)
      else lg.rectangle("fill", rx, yy, mw, hh) end
    end
  end
  lg.setBlendMode("alpha")
  lg.setColor(1, 1, 1, 1)
end

-- the system menu's row
function Wide.menuRow(host)
  local g = host and host.game
  if not (g and g.wideScreen) then return nil end
  return { id = "wide", label = "WIDESCREEN", value = Wide.enabled(host) and "ON" or "OFF" }
end

return Wide
