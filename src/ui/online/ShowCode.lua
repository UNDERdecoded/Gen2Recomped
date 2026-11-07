-- SHOW CODE (docs/online-design.md 2.2, workstream WS2).
--
-- The host's half of an invite: the code drawn big enough to read across a
-- room or off a phone held up to a webcam, a COPY button that puts it on the
-- clipboard, a line saying what the code reaches (LAN / internet / hub), a
-- status line the caller keeps current ("Waiting for a friend..."), and --
-- once per run, on a code that carries a public address -- the privacy note:
-- a direct code shows your internet address to whoever you give it to.
--
-- USE (WS4):
--   local screen = ShowCode.open(game, {
--     code = "XXXX-XXXX-...",        -- or invite = InviteCode.decode(...)
--     title = "YOUR CODE",           -- optional
--     status = "Waiting for a friend...",
--     onUpdate = function(screen, dt) end, -- poll the transport here
--     onCancel = function() end,     -- B / CANCEL; the screen pops itself first
--     style = "game" | "neutral",
--     width = , height = ,
--   })
--   screen:setStatus("Connecting...")   -- any time
--   screen:close()                      -- pop when the session starts
--
-- ShowCode.layout is pure, for tests.

local InviteCode = require("src.online.InviteCode")

local ShowCode = {}
ShowCode.__index = ShowCode
ShowCode.isOpaque = true

-- the privacy note is said once per run, as the doc asks
ShowCode.privacyShown = false
ShowCode.PRIVACY = "This code shows your internet address. Share it only with friends."

-- How a code is laid out on a surface `W` wide with symbols `cw` wide:
-- the largest scale (up to 3) at which its groups fit in at most `maxLines`
-- lines and, given `maxH` and the font's line height `lh`, in that height
-- (a line is lh * scale + 2, plus 8 for the frame).  Returns { scale=,
-- groupsPerLine=, lines=, groups={...}, width=, height= }.
function ShowCode.layout(code, W, cw, maxLines, margin, maxH, lh, onlyScale)
  maxLines = maxLines or 3
  margin = margin or 8
  local raw = InviteCode.normalize(code) or tostring(code or "")
  local groups = {}
  for i = 1, #raw, InviteCode.GROUP do groups[#groups + 1] = raw:sub(i, i + InviteCode.GROUP - 1) end
  if #groups == 0 then groups[1] = "" end
  for scale = onlyScale or 3, onlyScale or 1, -1 do
    local cell = cw * scale
    local gap = math.max(4, math.floor(cell / 2))
    local groupW = InviteCode.GROUP * cell + gap
    local perLine = math.max(1, math.floor((W - 2 * margin + gap) / groupW))
    local lines = math.ceil(#groups / perLine)
    -- balance the lines: 5 groups over 2 lines is 3 + 2, not 4 + 1
    perLine = math.ceil(#groups / lines)
    local height = lines * ((lh or cw) * scale + 2) + 8
    if (lines <= maxLines and (not maxH or height <= maxH)) or scale == 1 or onlyScale then
      local widest = 0
      for l = 1, lines do
        local first = (l - 1) * perLine + 1
        local last = math.min(#groups, l * perLine)
        local w = 0
        for k = first, last do w = w + #groups[k] * cell + (k < last and gap or 0) end
        if w > widest then widest = w end
      end
      if widest <= W - 2 * margin or scale == 1 or onlyScale then
        return { scale = scale, groupsPerLine = perLine, lines = lines, groups = groups,
                 gap = gap, cell = cell, width = widest, height = height }
      end
    end
  end
end

function ShowCode.new(game, opts)
  local self = setmetatable({}, ShowCode)
  opts = opts or {}
  self.game = game
  self.opts = opts
  self.invite = opts.invite
  if not self.invite and opts.code then self.invite = InviteCode.decode(opts.code) end
  self.code = (self.invite and self.invite.display) or opts.code or "??????"
  self.title = opts.title or "YOUR CODE"
  self.status = opts.status
  self.detail = opts.detail or (self.invite and InviteCode.describe(self.invite)) or nil
  self.buttons = { { id = "copy", label = "COPY" }, { id = "cancel", label = "CANCEL" } }
  self.index = 1
  self.notice = nil
  local CodeStyle = require("src.ui.online.CodeStyle")
  self.width, self.height = CodeStyle.surface(opts)
  self.styleKind = opts.style or CodeStyle.defaultKind(game)
  -- the privacy note: a code that carries a public address, the first time
  local hasPublic = self.invite and self.invite.public and self.invite.kind ~= "hub"
  if opts.privacy == true or (opts.privacy ~= false and hasPublic and not ShowCode.privacyShown) then
    self.privacy = true
    ShowCode.privacyShown = true
  end
  return self
end

function ShowCode.open(game, opts)
  local screen = ShowCode.new(game, opts)
  game.stack:push(screen)
  return screen
end

function ShowCode:uiSize() return self.width, self.height end

function ShowCode:setStatus(text) self.status = text end

function ShowCode:close()
  if self.game and self.game.stack and self.game.stack:top() == self then self.game.stack:pop() end
end

function ShowCode:copy()
  local text = self.code
  local ok = false
  if self.opts.setClipboard then
    self.opts.setClipboard(text); ok = true
  elseif love and love.system and love.system.setClipboardText then
    ok = pcall(love.system.setClipboardText, text)
  end
  self.notice = { text = ok and "Copied!" or "Could not copy.", timer = 2 }
  if self.opts.onCopy then self.opts.onCopy(text) end
  return ok
end

function ShowCode:cancel()
  self:close()
  if self.opts.onCancel then self.opts.onCancel() end
end

function ShowCode:press(id)
  if id == "copy" then self:copy() elseif id == "cancel" then self:cancel() end
end

function ShowCode:update(dt)
  dt = dt or 1 / 60
  if self.notice then
    self.notice.timer = self.notice.timer - dt
    if self.notice.timer <= 0 then self.notice = nil end
  end
  if self.opts.onUpdate then
    self.opts.onUpdate(self, dt)
    if self.game and self.game.stack and self.game.stack:top() ~= self then return end
  end
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("left") or input:wasPressed("right") then
    self.index = self.index % #self.buttons + 1
  end
  if input:wasPressed("a") then
    self:press(self.buttons[self.index].id)
  elseif input:wasPressed("select") then
    self:copy()
  elseif input:wasPressed("b") then
    self:cancel()
  end
end

-- Ctrl+C / Cmd+C copies as well; everything else goes to Input as usual
function ShowCode:onKeyPressed(key)
  if key == "c" and love and love.keyboard and love.keyboard.isDown
     and love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") then
    self:copy()
    return
  end
  local input = self.game and self.game.input
  if input and input.keypressed then input:keypressed(key) end
end

function ShowCode:measure()
  local CodeStyle = require("src.ui.online.CodeStyle")
  local style = self.style or CodeStyle.new(self.styleKind)
  self.style = style
  local W, H = self.width, self.height
  local M = { margin = 8, lh = style:lineHeight() }
  M.cw = style:cellWidth(InviteCode.CHARSET)
  M.titleY = 2
  local function tile(v) return math.ceil(v / 8) * 8 end
  M.buttonH = math.max(12, M.lh + 2)
  M.buttonY = H - 2 - M.buttonH
  M.buttonW = math.floor((W - 3 * M.margin) / 2)
  M.boxY = tile(M.titleY + M.lh + 1)
  -- how many text lines the code should leave room for (the notice, the
  -- status, the privacy note)
  local want = self.notice and #style:wrap(self.notice.text, W - 2 * M.margin) or 0
  if self.status then want = want + #style:wrap(self.status, W - 2 * M.margin) end
  if self.privacy then
    want = want + #style:wrap(self.opts.privacyText or ShowCode.PRIVACY, W - 2 * M.margin)
  end
  -- the largest scale whose framed code (rounded up to whole tiles) leaves
  -- room for the text under it
  local avail = M.buttonY - M.boxY - 3 -- the text starts 1 below the box and stops 2 above the buttons
  for scale = 3, 1, -1 do
    local Lt = ShowCode.layout(self.code, W - 8, M.cw, 3, M.margin, nil, M.lh, scale)
    local boxH = tile(Lt.lines * (M.lh * scale + 2) + 8)
    local fits = Lt.width <= W - 8 - 2 * M.margin and Lt.lines <= 3
    -- triple size only when every wanted line still fits; double size
    -- needs two (the rest are dropped, least important first)
    local need = scale >= 3 and math.min(math.max(want, 1), 4) or math.min(math.max(want, 1), 2)
    if (fits and math.floor((avail - boxH) / M.lh) >= need) or scale == 1 then
      M.layout = Lt
      break
    end
  end
  local lineH = M.lh * M.layout.scale + 2
  M.boxH = tile(M.layout.lines * lineH + 8)
  M.codeY = M.boxY + math.floor((M.boxH - M.layout.lines * lineH) / 2) + 1
  M.lineH = lineH
  M.textY = M.boxY + M.boxH + 1
  return M
end

function ShowCode:buttonRect(M, i)
  return M.margin + (i - 1) * (M.buttonW + M.margin), M.buttonY, M.buttonW, M.buttonH
end

function ShowCode:touchpressed(_, px, py)
  local CodeStyle = require("src.ui.online.CodeStyle")
  local x, y = CodeStyle.toSurface(px, py)
  if not x then return false end
  return self:tap(x, y)
end

function ShowCode:tap(x, y)
  local M = self:measure()
  for i, b in ipairs(self.buttons) do
    local bx, by, bw, bh = self:buttonRect(M, i)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then
      self.index = i
      self:press(b.id)
      return true
    end
  end
  if y >= M.boxY and y < M.boxY + M.boxH then self:copy() end -- tap the code to copy it
  return true
end

function ShowCode:draw()
  local M = self:measure()
  local style = self.style
  local C = require("src.ui.online.CodeStyle").colors
  local W = self.width
  style:clear(self.width, self.height)
  style:text(self.title, M.margin, M.titleY)

  style:box(4, M.boxY, W - 8, M.boxH)
  local Lt = M.layout
  for l = 1, Lt.lines do
    local first = (l - 1) * Lt.groupsPerLine + 1
    local last = math.min(#Lt.groups, l * Lt.groupsPerLine)
    local lineW = 0
    for k = first, last do lineW = lineW + #Lt.groups[k] * Lt.cell + (k < last and Lt.gap or 0) end
    local x = math.floor((W - lineW) / 2)
    local y = M.codeY + (l - 1) * M.lineH
    for k = first, last do
      local grp = Lt.groups[k]
      for c = 1, #grp do
        local ch = grp:sub(c, c)
        local cx = x + (c - 1) * Lt.cell + math.floor((M.cw - style:width(ch)) / 2) * Lt.scale
        style:scaled(cx, y, Lt.scale, function() style:text(ch, 0, 0) end)
      end
      x = x + #grp * Lt.cell + Lt.gap
    end
  end

  -- the lines under the code, as many as the space above the buttons holds
  local lines = {}
  local function add(text, color)
    if not text or text == "" then return end
    for _, l in ipairs(style:wrap(text, W - 2 * M.margin)) do lines[#lines + 1] = { l, color } end
  end
  -- most important first: what the player just did, what the session is
  -- doing, the privacy note, then what the code reaches
  if self.notice then add(self.notice.text, C.good) end
  add(self.status, C.ink)
  if self.privacy then add(self.opts.privacyText or ShowCode.PRIVACY, C.bad) end
  add(self.detail, C.dim)
  local room = math.max(0, math.floor((M.buttonY - M.textY - 2) / M.lh))
  for i = 1, math.min(#lines, room) do
    style:text(lines[i][1], M.margin, M.textY + (i - 1) * M.lh, lines[i][2])
  end

  for i, b in ipairs(self.buttons) do
    local x, y, w, h = self:buttonRect(M, i)
    style:key(x, y, w, h, i == self.index, false)
    style:text(b.label, x + math.floor((w - style:width(b.label)) / 2), y + math.floor((h - M.lh) / 2) + 1)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return ShowCode
