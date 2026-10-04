-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The scrolling region a `fillsBody` panel owes the drawer.
--
-- WHY THIS FILE EXISTS, and it is the clearest case of this tree's recurring
-- bug there has been: the same thing spelled differently in two places that
-- never meet, where the two places were an attribute and its meaning.
--
-- `Sidebar.lua` lets a panel say `fillsBody = true`, and the contract that
-- comes with it is stated there:
--
--   > Such a panel says so, and gets the body exactly: no virtual page, no
--   > outer scroll, no outer rail. Its own scrolling was always the right one.
--
-- TILES signs up to that and honours it -- it draws a header and hands the
-- whole remaining rectangle to a palette that sizes its rows, its page and its
-- own rail from the height it was given. MODELS copied the attribute and not
-- the contract: it flowed five rows down a column, about 340 px, and painted
-- nothing else. The drawer had already reserved the full body for it and taken
-- the no-virtual-page branch, so the remaining two thirds were painted by
-- nobody and came out as a flat band of `PAL.bgBot` under the last stepper --
-- which is the "black bar at the bottom of the panel". Measured on a 600 px
-- body: the lowest pixel anything painted was y=368, and the 232 px below it
-- belonged to no one. And because `fillsBody` also suppresses the outer
-- scroll, anything that HAD flowed past the body would have been unreachable
-- from either scrollbar.
--
-- A comment telling the next author to be careful is a list. This is the
-- invariant: a panel that declares the flag calls `BodyFill.region` with the
-- rectangle it was handed, and the region
--
--   * PAINTS ITSELF, so no part of the body is ever unpainted drawer even when
--     the content inside it is two rows long;
--   * clamps and owns its own scroll offset, keyed by a name on `S`;
--   * clips to itself, and raises `Kit.blockClicks` while the pointer is
--     outside it, because a row scrolled out of sight must be DEAD -- Kit
--     hit-tests raw coordinates, so clipping hides a control and nothing more.
--     `Sidebar` does exactly this one level out, for exactly this reason;
--   * draws its own rail, with the rail's width taken OUT of the content width
--     rather than drawn over it. A rail over the last column makes that column
--     unclickable, which is how the tile palette's right-hand swatches became
--     unselectable-but-visible.
--
-- The content is painted by a callback and is handed a y ABOVE the region when
-- it is scrolled -- the rectangle moves, the canvas is never translated. That
-- is the drawer's own rule and it is here for the drawer's own reason: a
-- translate moves the pixels and leaves Kit testing the mouse against where
-- the control used to be.

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, cardBorder = { 70, 80, 105 },
}

local BodyFill = {}

BodyFill.RAIL = 6          -- rail width, DPI units
BodyFill.GUTTER = 4        -- gap between the content and the rail

-- Where a region keeps its offset. One field per key on `S`, so two regions in
-- one panel do not share a scroll -- which is the bug the voxel tab had when
-- its class list and its cell grid both read `S.voxelScroll`.
local function field(key)
  return "bodyFill_" .. tostring(key or "default")
end

function BodyFill.scrollOf(S, key)
  return (S and S[field(key)]) or 0
end

function BodyFill.maxScroll(contentH, h)
  return math.max(0, (tonumber(contentH) or 0) - (tonumber(h) or 0))
end

-- THE REGION.
--
-- `contentH` is how tall the content is in the same units the panel was handed
-- -- the panel measures it, exactly as a flowing panel measures itself for
-- `Sidebar.reportHeight`. `paint(cx, cy, cw)` draws it, at a `cy` that is the
-- region's top minus the scroll.
--
-- Returns the content width (the region's width less the rail when there is
-- one) and the maximum scroll, so a caller can lay its rows out at the width
-- that will actually be clickable.
function BodyFill.region(S, Kit, key, x, y, w, h, contentH, paint)
  local s = (Kit and Kit.scale) or 1
  h = math.max(0, h or 0)
  contentH = math.max(0, tonumber(contentH) or 0)

  -- THE SURFACE FIRST, AND THIS LINE IS THE BUG FIX. Whatever the content
  -- turns out to be, the whole rectangle the drawer reserved is painted by
  -- this panel, so there is no band left over for the drawer's plate to show
  -- through as a bar.
  Kit.card(x, y, w, h)

  local maxScroll = BodyFill.maxScroll(contentH, h)
  local hasRail = maxScroll > 0
  local railW = BodyFill.RAIL * s
  local innerW = hasRail and math.max(1, w - railW - BodyFill.GUTTER * s) or w

  local at = math.max(0, math.min(BodyFill.scrollOf(S, key), maxScroll))
  if S then S[field(key)] = at end

  if type(paint) == "function" then
    Kit.pushClip(x, y, innerW, h)
    local wasBlocked = Kit.blockClicks
    if not Kit.hit(x, y, innerW, h) then Kit.blockClicks = true end
    paint(x, y - at, innerW)
    Kit.blockClicks = wasBlocked
    Kit.popClip()
  end

  if hasRail and love and love.graphics then
    local rx = x + w - railW
    local thumb = math.max(20 * s, h * (h / math.max(1, contentH)))
    local ty = y + (h - thumb) * (at / maxScroll)
    if Theme and Theme.col then
      Theme.col(PAL.cardBorder, 0.18)
    else
      love.graphics.setColor(1, 1, 1, 0.10)
    end
    love.graphics.rectangle("fill", rx, y, railW, h, railW / 2, railW / 2)
    if Theme and Theme.col then
      Theme.col(PAL.cardBorder, 0.6)
    else
      love.graphics.setColor(1, 1, 1, 0.34)
    end
    love.graphics.rectangle("fill", rx, ty, railW, thumb, railW / 2, railW / 2)
    love.graphics.setColor(1, 1, 1, 1)
  end

  return innerW, maxScroll
end

-- A WHEEL NOTCH, and the "return false when it was not for me" rule.
--
-- `Sidebar.wheelmoved` offers the open panel the notch first and scrolls the
-- drawer only when the panel declines. A `fillsBody` panel has no outer scroll
-- to fall back to, so declining costs nothing -- but a handler that claims
-- every notch is what killed the drawer's scroll on the voxel tool, and the
-- next panel to use this helper may not fill the body. So: taken when there is
-- somewhere for it to go, declined when there is not.
function BodyFill.wheel(S, key, dy, maxScroll)
  maxScroll = math.max(0, tonumber(maxScroll) or 0)
  if maxScroll <= 0 then return false end
  local at = math.max(0, math.min(BodyFill.scrollOf(S, key)
                                  - (tonumber(dy) or 0) * 48, maxScroll))
  if S then S[field(key)] = at end
  return true
end

function BodyFill.reset(S, key)
  if S then S[field(key)] = 0 end
end

return BodyFill
