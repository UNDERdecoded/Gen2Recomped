-- An immediate-mode widget set, small on purpose.
--
-- No retained tree, no layout engine: every panel draws itself each frame
-- and asks whether the mouse is over it.  That keeps the editor's state in
-- the document where it belongs rather than mirrored into widget objects,
-- which is the failure mode a tool like this actually has -- a value
-- changed in a panel and nowhere else.

local Theme = require("ui.Theme")

local W = {}

W.state = { hot = nil, active = nil, mx = 0, my = 0, down = false,
            clicked = false, wheel = 0, scroll = {}, drag = nil,
            typing = nil, typed = "", backspace = false }

function W.beginFrame(mx, my, down, clicked, wheel)
  W.state.mx, W.state.my = mx, my
  W.state.down = down
  W.state.clicked = clicked
  W.state.wheel = wheel or 0
  W.state.hot = nil
  -- WHEEL OWNERSHIP, one frame behind.  A scrolling panel inside a scrolling
  -- dock is two things that both want the wheel, and the outer one runs
  -- first -- so it cannot know yet.  The inner one claims the rect it wants
  -- and the outer one honours last frame's claim, which is a frame of lag
  -- nobody can see and the alternative to both of them scrolling at once.
  W.state.claimedWheel = W.state.claimWheel
  W.state.claimWheel = nil
  -- Text that arrived while no field was focused belongs to nobody.  Left
  -- in the buffer it would appear in whichever field is clicked next, which
  -- is the sort of thing that looks like a haunting.
  if not W.state.typing then
    W.state.typed = ""
    W.state.backspace = false
  end
  -- A SUBMIT NOBODY READ IS DROPPED.  If the field that had focus was not
  -- drawn this frame -- its panel collapsed, its tab switched -- the pending
  -- return would otherwise sit there and fire whenever that field next
  -- appears, committing an edit the reader made a minute ago somewhere else.
  if W.state.submitted then
    if W.state.submitStale then
      W.state.submitted = nil
      W.state.submitStale = false
    else
      W.state.submitStale = true
    end
  else
    W.state.submitStale = false
  end
end

function W.hit(x, y, w, h)
  local s = W.state
  return s.mx >= x and s.my >= y and s.mx < x + w and s.my < y + h
end

function W.panel(x, y, w, h, label, alt)
  love.graphics.setColor(alt and Theme.panelAlt or Theme.panel)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  love.graphics.setColor(Theme.line)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  if label then
    love.graphics.setFont(Theme.fonts.small)
    love.graphics.setColor(Theme.dim)
    love.graphics.print(label:upper(), x + 8, y + 6)
  end
end

function W.text(s, x, y, color, font)
  love.graphics.setFont(font or Theme.fonts.body)
  love.graphics.setColor(color or Theme.text)
  love.graphics.print(s, x, y)
end

function W.textRight(s, x, y, color, font)
  font = font or Theme.fonts.body
  love.graphics.setFont(font)
  love.graphics.setColor(color or Theme.text)
  love.graphics.print(s, x - font:getWidth(s), y)
end

function W.button(id, x, y, w, h, label, opts)
  opts = opts or {}
  local over = W.hit(x, y, w, h) and not opts.disabled
  if over then W.state.hot = id end
  local pressed = over and W.state.clicked
  local fill = opts.on and Theme.accentDim
      or (over and Theme.panelAlt or Theme.panel)
  if opts.disabled then fill = Theme.panel end
  love.graphics.setColor(fill)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  love.graphics.setColor(over and Theme.accent or Theme.line)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  local font = opts.font or Theme.fonts.body
  love.graphics.setFont(font)
  love.graphics.setColor(opts.disabled and Theme.faint
      or (opts.on and Theme.text or (over and Theme.text or Theme.dim)))
  love.graphics.printf(label, x, y + (h - font:getHeight()) / 2, w, "center")
  return pressed
end

function W.tooltip(s, x, y)
  if not s or s == "" then return end
  local font = Theme.fonts.small
  love.graphics.setFont(font)
  local tw = math.min(360, font:getWidth(s) + 16)
  local _, lines = font:getWrap(s, tw - 16)
  local th = #lines * font:getHeight() + 10
  local sw, sh = love.graphics.getDimensions()
  x = math.min(x, sw - tw - 8)
  y = math.min(y, sh - th - 8)
  love.graphics.setColor(0, 0, 0, 0.88)
  love.graphics.rectangle("fill", x, y, tw, th, 3, 3)
  love.graphics.setColor(Theme.line)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, tw - 1, th - 1, 3, 3)
  love.graphics.setColor(Theme.text)
  love.graphics.printf(s, x + 8, y + 5, tw - 16)
end

-- A scrolling list.  `items` is a list of { label, value, sub, color }.
function W.list(id, x, y, w, h, items, selected, opts)
  opts = opts or {}
  local rowH = opts.rowH or 20
  W.panel(x, y, w, h, nil, true)
  local st = W.state.scroll[id] or 0
  if W.hit(x, y, w, h) then
    W.claimWheel(x, y, w, h)
    if W.state.wheel ~= 0 then st = st - W.state.wheel * rowH * 3 end
  end
  local maxScroll = math.max(0, #items * rowH - h + 8)

  -- SCROLL TO THE SELECTED ROW WHEN THE SELECTION CHANGES.
  --
  -- The class list is forty rows in a box that shows eight, so highlighting
  -- the resolved class is only useful if the resolved class is on screen --
  -- otherwise picking a tile still shows an apparently empty list, which is
  -- the bug this was meant to fix wearing a different hat.  Only on CHANGE,
  -- so the reader can scroll away and stay there.
  W.state.listSel = W.state.listSel or {}
  if selected ~= nil and W.state.listSel[id] ~= selected then
    W.state.listSel[id] = selected
    for i, item in ipairs(items) do
      if item.value == selected then
        local top = (i - 1) * rowH
        if top < st then st = top
        elseif top + rowH > st + h - 8 then st = top + rowH - h + 8 end
        break
      end
    end
  end

  st = math.max(0, math.min(maxScroll, st))
  W.state.scroll[id] = st

  local chosen = nil
  W.scissorIn(x + 1, y + 1, w - 2, h - 2)
  local font = opts.font or Theme.fonts.body
  love.graphics.setFont(font)
  for i, item in ipairs(items) do
    local ry = y + 4 + (i - 1) * rowH - st
    if ry + rowH > y and ry < y + h then
      local over = W.hit(x, math.max(y, ry), w, rowH) and W.hit(x, y, w, h)
      local on = item.value == selected
      if on or over then
        love.graphics.setColor(on and Theme.accentDim or Theme.panel)
        love.graphics.rectangle("fill", x + 2, ry, w - 4, rowH - 1, 2, 2)
      end
      love.graphics.setColor(item.color or (on and Theme.text or Theme.dim))
      love.graphics.print(item.label, x + 8, ry + (rowH - font:getHeight()) / 2)
      if item.sub then
        W.textRight(item.sub, x + w - 8, ry + (rowH - font:getHeight()) / 2,
                    item.subColor or Theme.faint, font)
      end
      if over and W.state.clicked then chosen = item.value end
    end
  end
  W.scissorOut()
  if maxScroll > 0 then
    local frac = h / (#items * rowH)
    local bh = math.max(20, h * frac)
    local by = y + (st / maxScroll) * (h - bh)
    love.graphics.setColor(Theme.line)
    love.graphics.rectangle("fill", x + w - 5, by, 3, bh, 2, 2)
  end
  return chosen
end

function W.slider(id, x, y, w, h, value, minV, maxV, opts)
  opts = opts or {}
  local over = W.hit(x, y, w, h)
  if over then W.state.hot = id end
  if over and W.state.down then W.state.active = id end
  if not W.state.down and W.state.active == id then W.state.active = nil end
  local t = (value - minV) / math.max(1e-9, (maxV - minV))
  if W.state.active == id then
    t = math.max(0, math.min(1, (W.state.mx - x) / w))
    value = minV + t * (maxV - minV)
    if opts.step then value = math.floor(value / opts.step + 0.5) * opts.step end
    t = (value - minV) / math.max(1e-9, (maxV - minV))
  end
  love.graphics.setColor(Theme.panelAlt)
  love.graphics.rectangle("fill", x, y + h / 2 - 3, w, 6, 3, 3)
  love.graphics.setColor(Theme.accentDim)
  love.graphics.rectangle("fill", x, y + h / 2 - 3, w * t, 6, 3, 3)
  love.graphics.setColor(over and Theme.accent or Theme.dim)
  love.graphics.circle("fill", x + w * t, y + h / 2, 6)
  return value
end

-- A one-line text field.  Typing goes through love.textinput, which the app
-- routes here by id -- so exactly one field can be typing at a time and it
-- is never ambiguous which.
-- `opts.numeric` keeps everything but digits and a leading minus out, which
-- is the difference between a field you can type a height into and a field
-- that will happily hold "4o" and resolve to nothing.
--
-- Returns the value and, on the frame the reader pressed return, `true` --
-- so a caller can commit on enter rather than only on a button.
function W.field(id, x, y, w, h, value, placeholder, opts)
  opts = opts or {}
  local over = W.hit(x, y, w, h)
  if W.state.clicked then
    -- A CLICK ANYWHERE ELSE GIVES UP THE FOCUS.  Without this the field keeps
    -- it after you click into the world, and every keypress -- Q, W, E, the
    -- edit-mode keys -- goes into the text box instead of the editor, which
    -- reads as the keyboard having stopped working.
    if over then W.state.typing = id
    elseif W.state.typing == id then W.state.typing = nil end
  end
  local active = W.state.typing == id
  if active and W.state.typed ~= "" then
    local add = W.state.typed
    if opts.numeric then
      add = add:gsub("[^%d%-]", "")
      -- a minus only means anything at the front
      add = add:gsub("%-", function()
        return (value == "" and add:sub(1, 1) == "-") and "-" or ""
      end)
    end
    value = value .. add
    W.state.typed = ""
  end
  if active and W.state.backspace then
    value = value:sub(1, -2)
    W.state.backspace = false
  end
  local submitted = false
  if active and W.state.submitted == id then
    W.state.submitted = nil
    W.state.submitStale = false
    W.state.typing = nil
    active = false
    submitted = true
  end
  love.graphics.setColor(active and Theme.panelAlt or Theme.panel)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  love.graphics.setColor(active and Theme.accent or Theme.line)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  love.graphics.setFont(Theme.fonts.body)
  if value == "" and not active then
    love.graphics.setColor(Theme.faint)
    love.graphics.print(placeholder or "", x + 6, y + 4)
  else
    love.graphics.setColor(Theme.text)
    love.graphics.print(value .. (active and "_" or ""), x + 6, y + 4)
  end
  return value, submitted
end


-- ------------------------------------------------------------- containers

-- A SCROLLING REGION.  The reason this exists: panels grew past the bottom
-- of the window and the controls under the fold were not "hard to reach",
-- they were GONE -- there was no gesture that could reach them at any window
-- size.  A panel that cannot fit must scroll; nothing else is honest.
--
-- Immediate-mode, so it is a pair: `beginScroll` sets a scissor and shifts
-- the origin, `endScroll` restores both and draws the bar.  The caller lays
-- out from `y` as usual and tells endScroll how far down it got.
local function wheelClaimed()
  local c = W.state.claimedWheel
  return c and W.hit(c[1], c[2], c[3], c[4]) or false
end
W.wheelClaimed = wheelClaimed

function W.claimWheel(x, y, w, h)
  W.state.claimWheel = { x, y, w, h }
end

-- CLIPPING INSIDE A SCROLLED REGION.
--
-- `love.graphics.setScissor` takes SCREEN coordinates and is not moved by the
-- current transform, while everything laid out inside a scroll region is in
-- the region's own shifted space.  Set a scissor there with the coordinates
-- you drew at and it clips a rectangle somewhere else -- which shows up as
-- content vanishing as you scroll, and looks like a layout bug rather than
-- what it is.  So: one helper that converts, and clamps to the region.
function W.scissorIn(x, y, w, h)
  local off = W.state.scrollOffset or 0
  local sx, sy = x, y - off
  local clip = W.state.clipRect
  if clip then
    local x0 = math.max(sx, clip[1])
    local y0 = math.max(sy, clip[2])
    local x1 = math.min(sx + w, clip[1] + clip[3])
    local y1 = math.min(sy + h, clip[2] + clip[4])
    sx, sy, w, h = x0, y0, math.max(0, x1 - x0), math.max(0, y1 - y0)
  end
  love.graphics.setScissor(sx, sy, w, h)
end

function W.scissorOut()
  local clip = W.state.clipRect
  if clip then
    love.graphics.setScissor(clip[1], clip[2], clip[3], clip[4])
  else
    love.graphics.setScissor()
  end
end

function W.beginScroll(id, x, y, w, h)
  local st = W.state.scroll[id] or 0
  if W.hit(x, y, w, h) and W.state.wheel ~= 0 and not wheelClaimed() then
    st = st - W.state.wheel * 48
  end
  W.state.scroll[id] = st
  love.graphics.push()
  love.graphics.setScissor(x, y, w, h)
  love.graphics.translate(0, -st)
  W.state.scrollOffset = st
  W.state.clipRect = { x, y, w, h }
  -- the mouse must move with the content or every hit test is off by the
  -- scroll amount, which presents as buttons that respond somewhere else
  W.state._scrollStack = W.state._scrollStack or {}
  table.insert(W.state._scrollStack, { id = id, my = W.state.my })
  W.state.my = W.state.my + st
  return st
end

function W.endScroll(id, x, y, w, h, contentBottom)
  local frame = table.remove(W.state._scrollStack)
  if frame then W.state.my = frame.my end
  love.graphics.pop()
  love.graphics.setScissor()
  W.state.scrollOffset = 0
  W.state.clipRect = nil
  local content = math.max(0, contentBottom - y)
  local maxScroll = math.max(0, content - h)
  local st = math.max(0, math.min(maxScroll, W.state.scroll[id] or 0))
  W.state.scroll[id] = st
  if maxScroll > 0 then
    local bh = math.max(24, h * (h / content))
    local by = y + (st / maxScroll) * (h - bh)
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle("fill", x + w - 6, y, 4, h, 2, 2)
    love.graphics.setColor(Theme.line)
    love.graphics.rectangle("fill", x + w - 6, by, 4, bh, 2, 2)
  end
  return maxScroll > 0
end

-- A collapsible section header.  Returns the new open state and the y to
-- carry on from.
function W.section(id, x, y, w, label, open, right)
  local h = Theme.btnH or 22
  local over = W.hit(x, y, w, h)
  if over then W.state.hot = id end
  if over and W.state.clicked then open = not open end
  love.graphics.setColor(over and Theme.panelAlt or Theme.panel)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  love.graphics.setFont(Theme.fonts.small)
  love.graphics.setColor(over and Theme.text or Theme.dim)
  love.graphics.print((open and "v  " or ">  ") .. label:upper(), x + 8,
                      y + math.floor((h - Theme.fonts.small:getHeight()) / 2))
  if right then
    W.textRight(right, x + w - 8,
                y + math.floor((h - Theme.fonts.small:getHeight()) / 2),
                Theme.faint, Theme.fonts.small)
  end
  return open, y + h + 4
end

-- Lay a row of chips out with wrapping, so a list of presets never runs off
-- the side of a panel that got narrower.
function W.chips(idPrefix, x, y, w, items, isOn, onPick, font)
  font = font or Theme.fonts.small
  local h = (Theme.btnH or 21) - 2
  local cx, cy = x, y
  for i, item in ipairs(items) do
    local label = item.label or tostring(item)
    local cw = font:getWidth(label) + 14
    -- A chip WIDER than the row it is in still gets its own line rather than
    -- hanging off the end: a class name is never truncated into a different
    -- class name.
    if cx + cw > x + w and cx > x then cx = x cy = cy + h + 2 end
    if W.button(idPrefix .. i, cx, cy, math.min(cw, w), h, label,
                { on = isOn(item), font = font }) then
      onPick(item, i)
    end
    if W.state.hot == idPrefix .. i and item.hint then
      W.state.tip = item.hint
    end
    cx = cx + cw + 4
  end
  return cy + h + 4
end

return W
