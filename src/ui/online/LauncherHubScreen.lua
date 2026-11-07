-- The launcher's ONLINE HUB section (sidebar "Online Hub"): one-tap HOST
-- WITH FRIENDS and JOIN FRIEND, the in-launcher Link Hub's status, and a
-- touch-sized editor for every hub setting.  The hub itself is
-- src/online/LauncherHub.lua (a love.thread); this file only draws and
-- takes taps / keys.
--
--   local scr = LauncherHubScreen.new(launcher)
--   scr:update(dt) ; h = scr:draw(x, y, w, h, opts) ; scr:mousepressed(x, y)
--   scr:keypressed(key) -> bool ; scr:textinput(text) -> bool ; scr:close()
--
-- opts: { title, head, body, small = fonts, palette = launcher PAL, s = scale }
-- Pages: home | host | join | config.  Everything is a big tap target
-- (>= 44 px at scale 1), and narrow windows stack the columns.

local LH = require("src.online.LauncherHub")
local Strings = require("src.core.Strings")

local S = {}
S.__index = S

local function setc(c, a)
  if not c then love.graphics.setColor(1, 1, 1, a or 1) return end
  local k = (c[1] > 1 or c[2] > 1 or c[3] > 1) and 255 or 1
  love.graphics.setColor(c[1] / k, c[2] / k, c[3] / k, a or c[4] or 1)
end

local FALLBACK = {
  ink = { 236, 238, 244 }, warning = { 170, 176, 196 }, link = { 90, 150, 255 },
  cardBorder = { 90, 96, 120 }, bgTop = { 22, 24, 34 }, bgBot = { 14, 15, 22 },
  white = { 255, 255, 255 }, red = { 220, 70, 70 }, gold = { 236, 186, 60 },
  blue = { 70, 120, 230 }, playTop = { 70, 190, 110 },
}

function S.new(host)
  local self = setmetatable({ host = host, page = "home", t = 0, rects = {}, code = "",
                              toast = nil }, S)
  LH.load()
  return self
end

function S:say(text, secs) self.toast = { text = tostring(text), till = self.t + (secs or 3) } end

---------------------------------------------------------------- pages

function S:go(page)
  if self.editing then self:commitEdit() end
  self.page = page
  self.picker = nil
  if self.host then self.host.pageScroll = 0 end
  if page == "join" then
    self:openListener()
    if self.code == "" then
      local inv, what = LH.clipboardCode()
      if inv then
        self.code = inv.display or inv.raw or ""
        self.fromClipboard = true
        self:examine(what == "hub")
      end
    end
  else
    self:closeListener()
  end
end

function S:close()
  self:closeListener()
  if self.editing then self:commitEdit() end
end

function S:openListener()
  if self.listener then return end
  local okP, Platform = pcall(require, "src.core.Platform")
  local o = okP and Platform.online and Platform.online() or {}
  self.listenNote = nil
  if o.os == "iOS" then
    self.listenNote = "iPhone and iPad can't list nearby games (Apple limits local broadcasts). Enter your friend's code instead."
    return
  end
  if not o.hasSocket then
    self.listenNote = "This build can't look for nearby games. Enter your friend's code instead."
    return
  end
  if o.canBroadcast == false then
    self.listenNote = "Some phones hide nearby games. If yours isn't listed, enter the code."
  end
  local okB, LanBeacon = pcall(require, "src.online.net.LanBeacon")
  if not okB then return end
  local port = tonumber(os.getenv("POKEPORT_HUB_BEACON_PORT") or "")
  local ok, l = pcall(LanBeacon.newListener, { port = port })
  if ok then
    self.listener = l
    if l.error then self.listenNote = l.error end
  end
end

function S:closeListener()
  if self.listener then pcall(self.listener.close, self.listener) end
  self.listener = nil
end

function S:update(dt)
  self.t = self.t + dt
  LH.poll()
  if self.listener then pcall(self.listener.update, self.listener) end
  -- HOST WITH FRIENDS waits for the hub to come up, then the code shows
  if self.page == "host" and self.wantHub and LH.running() then self.wantHub = nil end
end

---------------------------------------------------------------- input

function S:rect(x, y, w, h, fn) self.rects[#self.rects + 1] = { x = x, y = y, w = w, h = h, fn = fn } end

function S:mousepressed(x, y)
  local clip = self.clip
  if clip and (y < clip[2] or y > clip[2] + clip[4] or x < clip[1] or x > clip[1] + clip[3]) then
    return false
  end
  for i = #self.rects, 1, -1 do
    local r = self.rects[i]
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      if self.editing and r.fieldId ~= self.editing.id then self:commitEdit() end
      r.fn()
      return true
    end
  end
  if self.editing then self:commitEdit() return true end
  return false
end

function S:startEdit(id, text, max, apply, charset)
  if self.editing then self:commitEdit() end
  self.editing = { id = id, text = tostring(text or ""), max = max or 24, apply = apply, charset = charset }
  if self.host and self.host._armTextInput then pcall(self.host._armTextInput, self.host)
  elseif love.keyboard and love.keyboard.setTextInput then pcall(love.keyboard.setTextInput, true) end
end

function S:commitEdit()
  local e = self.editing
  self.editing = nil
  if self.host and self.host._disarmTextInput then pcall(self.host._disarmTextInput, self.host) end
  if e and e.apply then e.apply(e.text) end
end

local function utf8Pop(s)
  local ok, utf8 = pcall(require, "utf8")
  local off = ok and utf8.offset(s, -1) or #s
  return off and s:sub(1, off - 1) or ""
end

function S:textinput(text)
  local e = self.editing
  if not e then return false end
  if e.charset == "code" then text = text:upper():gsub("[^%w%- ]", "") end
  if e.charset == "digits" then text = text:gsub("[^%d]", "") end
  e.text = (e.text .. text):sub(1, e.max)
  if e.live then e.live(e.text) end
  return true
end

function S:paste()
  if not (love.system and love.system.getClipboardText) then return nil end
  local ok, t = pcall(love.system.getClipboardText)
  return ok and t or nil
end

function S:keypressed(key)
  local e = self.editing
  if e then
    local ctrl = love.keyboard and (love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui"))
    if key == "backspace" then
      e.text = utf8Pop(e.text)
      if e.live then e.live(e.text) end
    elseif key == "return" or key == "kpenter" then
      local submit = e.submit
      self:commitEdit()
      if submit then submit() end
    elseif key == "escape" then
      self.editing = nil
      if self.host and self.host._disarmTextInput then pcall(self.host._disarmTextInput, self.host) end
    elseif key == "v" and ctrl then
      local t = self:paste()
      if t then self:textinput(t) end
    end
    return true
  end
  if key == "escape" and self.page ~= "home" then
    if self.picker then self.picker = nil else self:go("home") end
    return true
  end
  return false
end

---------------------------------------------------------------- drawing kit

function S:pal() return self.P or FALLBACK end

function S:button(x, y, w, h, label, fn, kind, font)
  local g, P = love.graphics, self:pal()
  local mx, my = love.mouse.getPosition()
  local hot = mx >= x and mx <= x + w and my >= y and my <= y + h
  local r = math.min(h * 0.3, 14 * self.s)
  local base = kind == "accent" and P.link or kind == "danger" and P.red or kind == "good" and (P.playTop or P.link)
               or kind == "gold" and P.gold or P.cardBorder
  setc(base, kind == nil and (hot and 0.55 or 0.38) or (hot and 1 or 0.88))
  g.rectangle("fill", x, y, w, h, r, r)
  g.setColor(1, 1, 1, hot and 0.16 or 0.08)
  g.rectangle("fill", x, y, w, h * 0.5, r, r)
  g.setFont(font or self.f.body)
  setc(P.white)
  local f = g.getFont()
  local text = Strings(label)
  local lines = select(2, f:getWrap(text, w - 12 * self.s))
  g.printf(text, x + 6 * self.s, math.floor(y + (h - #lines * f:getHeight()) / 2), w - 12 * self.s, "center")
  self:rect(x, y, w, h, fn)
  self.rects[#self.rects].label = label -- tests press buttons by label
end

function S:card(x, y, w, h, tint)
  local g, P = love.graphics, self:pal()
  setc(P.bgTop or P.bgBot, 0.92)
  g.rectangle("fill", x, y, w, h, 12 * self.s, 12 * self.s)
  setc(tint or P.cardBorder, tint and 0.8 or 0.45)
  g.setLineWidth(math.max(1, self.s))
  g.rectangle("line", x, y, w, h, 12 * self.s, 12 * self.s)
  g.setLineWidth(1)
end

-- wrapped text; returns the height used
function S:text(text, x, y, w, font, color, align)
  local g = love.graphics
  font = font or self.f.body
  g.setFont(font)
  setc(color or self:pal().ink)
  local t = Strings(tostring(text))
  local _, lines = font:getWrap(t, w)
  g.printf(t, x, y, w, align or "left")
  return #lines * font:getHeight()
end

function S:textHeight(text, w, font)
  font = font or self.f.body
  local _, lines = font:getWrap(Strings(tostring(text)), w)
  return #lines * font:getHeight()
end

-- a status pill
function S:pill(x, y, label, color)
  local g, f = love.graphics, self.f.small
  local w = f:getWidth(label) + 18 * self.s
  local h = f:getHeight() + 8 * self.s
  setc(color, 0.85)
  g.rectangle("fill", x, y, w, h, h / 2, h / 2)
  g.setFont(f)
  g.setColor(1, 1, 1, 1)
  g.print(label, x + 9 * self.s, y + 4 * self.s)
  return w, h
end

---------------------------------------------------------------- draw

function S:draw(x, y, w, h, opts)
  opts = opts or {}
  self.rects = {}
  self.f = { title = opts.title or love.graphics.getFont(), head = opts.head or opts.body or love.graphics.getFont(),
             body = opts.body or love.graphics.getFont(), small = opts.small or opts.body or love.graphics.getFont() }
  self.P = opts.palette
  self.s = opts.s or 1
  local g = love.graphics
  local sx, sy, sw, sh = g.getScissor()
  self.clip = sx and { sx, sy, sw, sh } or nil
  g.push("all")
  local used
  if self.picker then used = self:drawPicker(x, y, w, h)
  elseif self.page == "host" then used = self:drawHost(x, y, w, h)
  elseif self.page == "join" then used = self:drawJoin(x, y, w, h)
  elseif self.page == "config" then used = self:drawConfig(x, y, w, h)
  else used = self:drawHome(x, y, w, h) end
  if self.toast and self.t < self.toast.till then
    local f = self.f.body
    g.setFont(f)
    local tw = math.min(w - 20 * self.s, f:getWidth(self.toast.text) + 40 * self.s)
    local th = f:getHeight() + 20 * self.s
    local ty = (self.clip and self.clip[2] or y) + 10 * self.s
    g.setColor(0.06, 0.06, 0.08, 0.94)
    g.rectangle("fill", x + (w - tw) / 2, ty, tw, th, 12 * self.s, 12 * self.s)
    setc(self:pal().gold)
    g.printf(self.toast.text, x + (w - tw) / 2 + 10 * self.s, ty + 10 * self.s, tw - 20 * self.s, "center")
  end
  g.pop()
  return math.max(h, used or 0)
end

-- a back button + title row; returns the height used
function S:pageHeader(x, y, w, title)
  local s = self.s
  local bh = 44 * s
  self:button(x, y, 110 * s, bh, "< BACK", function()
    if self.picker then self.picker = nil else self:go("home") end
  end)
  self:text(title, x + 124 * s, y + (bh - self.f.head:getHeight()) / 2, w - 124 * s, self.f.head)
  return bh + 14 * s
end

local PHASE = { off = "OFF", starting = "STARTING", running = "RUNNING", stopping = "STOPPING", failed = "PROBLEM" }

function S:phaseColor()
  local P, ph = self:pal(), LH.phase()
  if ph == "running" then return P.playTop or P.link end
  if ph == "failed" then return P.red end
  if ph == "starting" or ph == "stopping" then return P.gold end
  return P.cardBorder
end

-- ----------------------------------------------------------------- home

function S:platformNote()
  local okP, Platform = pcall(require, "src.core.Platform")
  local o = okP and Platform.online and Platform.online() or {}
  if o.available == false or o.canHost == false then
    return o.reason or "Online play isn't available on this device."
  end
  if o.os == "iOS" or o.os == "Android" then
    return "Phones can host while this app is open on Wi-Fi. On mobile data your phone usually can't be reached: join a friend's hub instead."
  end
  return o.reason
end

function S:drawHome(x, y, w, h)
  local s, P = self.s, self:pal()
  local top = y
  y = y + self:text("Play with friends anywhere: host a Link Hub right here, or join a friend's with one code.",
                    x, y, w, self.f.body, P.warning) + 14 * s
  -- the two big buttons
  local narrow = w < 640 * s
  local bh = 76 * s
  if narrow then
    self:button(x, y, w, bh, "HOST WITH FRIENDS", function() self:hostWithFriends() end, "accent", self.f.head)
    y = y + bh + 10 * s
    self:button(x, y, w, bh, "JOIN FRIEND", function() self:go("join") end, "good", self.f.head)
    y = y + bh + 14 * s
  else
    local bw = (w - 14 * s) / 2
    self:button(x, y, bw, bh, "HOST WITH FRIENDS", function() self:hostWithFriends() end, "accent", self.f.head)
    self:button(x + bw + 14 * s, y, bw, bh, "JOIN FRIEND", function() self:go("join") end, "good", self.f.head)
    y = y + bh + 14 * s
  end
  local note = self:platformNote()
  if note then y = y + self:text(note, x, y, w, self.f.small, P.gold) + 12 * s end
  y = y + self:drawHubCard(x, y, w) + 14 * s
  local cfg = LH.config()
  if cfg.friend then y = y + self:drawFriendCard(x, y, w) + 14 * s end
  return y - top
end

function S:statRows()
  local st = LH.status() or {}
  local hub = st.hub or {}
  local rows = {}
  local conn = hub.connections or {}
  rows[#rows + 1] = { "Players connected", tostring(conn.total or 0) }
  local relay = hub.relay or {}
  rows[#rows + 1] = { "Short-code rooms", ("%d open, %d paired"):format(relay.rooms or 0, relay.paired or 0) }
  local rdv = hub.rendezvous or {}
  rows[#rows + 1] = { "Hub codes (rooms)", ("%d live, %d joined"):format(rdv.tickets or 0, rdv.introduced or 0) }
  local tours = hub.tournaments or {}
  rows[#rows + 1] = { "Tournaments", ("%d open, %d finished"):format(tours.open or 0, tours.finished or 0) }
  if hub.gts then
    local parts = {}
    local keys = {}
    for pool in pairs(hub.gts) do keys[#keys + 1] = pool end
    table.sort(keys)
    for _, pool in ipairs(keys) do parts[#parts + 1] = ("%s %d"):format(pool:upper(), hub.gts[pool].deposits or 0) end
    rows[#rows + 1] = { "GTS deposits", table.concat(parts, ", ") }
  else
    rows[#rows + 1] = { "GTS", "off" }
  end
  local world = st.world or hub.world
  if world then
    rows[#rows + 1] = { "World", ("%s: %d/%d players"):format(tostring(world.name or world.game or "world"),
                                                               world.members or 0, world.cap or 0) }
  else
    rows[#rows + 1] = { "World", "off" }
  end
  local ports = st.ports or {}
  local lan = LH.lanIp()
  if lan then rows[#rows + 1] = { "On this Wi-Fi", ("%s:%s"):format(lan, tostring(ports.udp or LH.config().port)) } end
  local m = st.mapping or {}
  if m.state == "ok" then
    rows[#rows + 1] = { "Internet", ("%s (router opened the ports, %s)"):format(tostring(m.ip), tostring(m.method or "")) }
  elseif m.state == "trying" then
    rows[#rows + 1] = { "Internet", "asking the router to open the ports..." }
  elseif m.state == "failed" then
    rows[#rows + 1] = { "Internet", "router didn't open the ports: same Wi-Fi only (see HOST for help)" }
  else
    rows[#rows + 1] = { "Internet", "router mapping off: same Wi-Fi only" }
  end
  if world and world.code then rows[#rows + 1] = { "World code", world.code } end
  return rows
end

function S:drawHubCard(x, y, w)
  local s, P, g = self.s, self:pal(), love.graphics
  local pad = 16 * s
  local inner = w - 2 * pad
  -- measure first (cards draw behind)
  local ph = LH.phase()
  local rows = (ph == "running") and self:statRows() or {}
  local twoCol = inner > 700 * s
  local rowH = self.f.body:getHeight() + 8 * s
  local statsH = twoCol and math.ceil(#rows / 2) * rowH or #rows * rowH * (inner < 420 * s and 2 or 1)
  local notes = {}
  if ph == "failed" then notes[#notes + 1] = { "Couldn't start: " .. tostring(LH.lastError() or "?"), P.red } end
  if ph == "off" then
    notes[#notes + 1] = { "Your hub is off. Start it to give friends short codes, a GTS, tournaments and an always-on world, all from this device.", P.warning }
  end
  for _, n in ipairs(LH._state.notes or {}) do notes[#notes + 1] = { n, P.gold } end
  if LH.needsRestart() then notes[#notes + 1] = { "Settings changed: restart the hub to use them.", P.gold } end
  local notesH = 0
  for _, n in ipairs(notes) do notesH = notesH + self:textHeight(n[1], inner, self.f.small) + 6 * s end
  local bh = 52 * s
  local nButtons = 1
  if ph == "running" or ph == "starting" then
    nButtons = nButtons + 1 + (ph == "running" and 1 or 0) + (LH.needsRestart() and 1 or 0)
  elseif ph ~= "stopping" then
    nButtons = nButtons + 1
  end
  local perRow = ((inner - (nButtons - 1) * 10 * s) / nButtons < 120 * s) and 2 or nButtons
  local buttonRows = math.ceil(nButtons / perRow)
  local logLines = (ph == "running" and LH.status() and LH.status().log) or {}
  local logShown = math.min(#logLines, 5)
  local logH = logShown > 0 and (logShown * self.f.small:getHeight() + 10 * s) or 0
  local ch = pad + self.f.head:getHeight() + 12 * s + statsH + notesH + 8 * s
             + buttonRows * bh + (buttonRows - 1) * 10 * s + logH + pad
  self:card(x, y, w, ch, ph == "running" and (P.playTop or P.link) or nil)
  local cy = y + pad
  self:text("YOUR LINK HUB", x + pad, cy, inner, self.f.head)
  self:pill(x + pad + self.f.head:getWidth(Strings("YOUR LINK HUB")) + 14 * s, cy + 2 * s, PHASE[ph] or ph, self:phaseColor())
  cy = cy + self.f.head:getHeight() + 12 * s
  -- stats
  local colW = twoCol and (inner - 20 * s) / 2 or inner
  for i, r in ipairs(rows) do
    local col = twoCol and ((i - 1) % 2) or 0
    local rx = x + pad + col * (colW + 20 * s)
    local ry = cy
    if inner < 420 * s then
      self:text(r[1], rx, ry, colW, self.f.small, P.warning)
      self:text(r[2], rx, ry + rowH * 0.85, colW, self.f.body, P.ink)
      cy = cy + rowH * 2
    else
      g.setFont(self.f.small); setc(P.warning)
      g.print(Strings(r[1]), rx, ry + 3 * s)
      local lw = math.min(colW * 0.45, 190 * s)
      g.setFont(self.f.body); setc(P.ink)
      g.printf(r[2], rx + lw, ry, colW - lw, "left")
      if not twoCol or col == 1 or i == #rows then cy = cy + rowH end
    end
  end
  for _, n in ipairs(notes) do cy = cy + self:text(n[1], x + pad, cy, inner, self.f.small, n[2]) + 6 * s end
  cy = cy + 8 * s
  -- buttons
  local labels = {}
  if ph == "running" or ph == "starting" then
    labels[#labels + 1] = { "STOP HUB", function() LH.stop() end, "danger" }
    if ph == "running" then labels[#labels + 1] = { "SHARE CODE", function() self:go("host") end, "accent" } end
    if LH.needsRestart() then labels[#labels + 1] = { "RESTART", function() self:restartHub() end, "gold" } end
  elseif ph ~= "stopping" then
    labels[#labels + 1] = { "START HUB", function() self:startHub() end, "good" }
  end
  labels[#labels + 1] = { "HUB SETTINGS", function() self:go("config") end }
  local n = #labels
  local bw = (inner - (n - 1) * 10 * s) / n
  if bw < 120 * s then
    -- a phone: two per row
    bw = (inner - 10 * s) / 2
  end
  local bx = x + pad
  for i, b in ipairs(labels) do
    if bx + bw > x + pad + inner + 1 then bx = x + pad; cy = cy + bh + 10 * s end
    self:button(bx, cy, bw, bh, b[1], b[2], b[3])
    bx = bx + bw + 10 * s
    if i == n then cy = cy + bh end
  end
  if logShown > 0 then
    cy = cy + 10 * s
    g.setFont(self.f.small)
    setc(P.warning, 0.75)
    for i = #logLines - logShown + 1, #logLines do
      local line = tostring(logLines[i]):gsub("^%d+%-%d+%-%d+ ", "")
      g.print(line:sub(1, math.floor(inner / math.max(1, self.f.small:getWidth("m")))), x + pad, cy)
      cy = cy + self.f.small:getHeight()
    end
  end
  return math.max(ch, cy - y + pad)
end

function S:drawFriendCard(x, y, w)
  local s, P = self.s, self:pal()
  local f = LH.config().friend
  local pad = 16 * s
  local inner = w - 2 * pad
  local lines = {
    ("Your games use %s's hub (%s) for short codes, the GTS and tournaments."):format(
      tostring(f.name or "a friend"), tostring(f.address)),
  }
  if not LH.config().useInGames then lines[1] = "Saved, but \"Use the hub in my games\" is off in HUB SETTINGS." end
  if LH.running() then lines[#lines + 1] = "While your own hub runs, your games use yours instead." end
  if f.worldCode then lines[#lines + 1] = "Their world: " .. f.worldCode .. " (in a game: LINK > WORLDS > JOIN)" end
  local th = 0
  for _, l in ipairs(lines) do th = th + self:textHeight(l, inner, self.f.small) + 4 * s end
  local bh = 48 * s
  local ch = pad + self.f.head:getHeight() + 8 * s + th + 10 * s + bh + pad
  self:card(x, y, w, ch, P.link)
  local cy = y + pad
  self:text("FRIEND'S HUB", x + pad, cy, inner, self.f.head)
  cy = cy + self.f.head:getHeight() + 8 * s
  for _, l in ipairs(lines) do cy = cy + self:text(l, x + pad, cy, inner, self.f.small, P.ink) + 4 * s end
  cy = cy + 10 * s
  local bw = math.min(220 * s, (inner - 10 * s) / 2)
  if f.worldCode then
    self:button(x + pad, cy, bw, bh, "JOIN THEIR WORLD", function()
      self:pickGame("Join their world with", function(v)
        LH.setPending({ kind = "world", code = f.worldCode })
        self:launch(v)
      end, f.worldGame)
    end, "accent")
    self:button(x + pad + bw + 10 * s, cy, bw, bh, "FORGET", function() LH.forgetFriend() end)
  else
    self:button(x + pad, cy, bw, bh, "FORGET", function() LH.forgetFriend() end)
  end
  return ch
end

function S:startHub()
  local ok, why = LH.start()
  if not ok then self:say(why or "Couldn't start the hub", 5) end
  return ok
end

function S:restartHub()
  LH.stop()
  self.restartWhenOff = true
end

-- ----------------------------------------------------------------- host

function S:hostWithFriends()
  local cfg = LH.config()
  if cfg.hostChoice == "hub" then
    if not LH.running() then self:startHub(); self.wantHub = true end
  end
  self:go("host")
end

function S:chooseHost(choice)
  local cfg = LH.config()
  cfg.hostChoice = choice
  LH.save(cfg)
  if choice == "hub" and not LH.running() then self:startHub(); self.wantHub = true end
end

function S:drawHost(x, y, w, h)
  local s, P = self.s, self:pal()
  local top = y
  y = y + self:pageHeader(x, y, w, "HOST WITH FRIENDS")
  local cfg = LH.config()
  if not cfg.hostChoice then
    y = y + self:text("How do you want to host?", x, y, w, self.f.head) + 12 * s
    local narrow = w < 640 * s
    local cw = narrow and w or (w - 14 * s) / 2
    local items = {
      { "hub", "KEEP A HUB RUNNING",
        "Friends join any time this app is open: trade and battle with codes, a GTS, tournaments, and an always-on world. Best for a group.", "accent" },
      { "direct", "JUST PLAY NOW",
        "Pick a game: it opens LINK > HOST and shows a code for one friend. No hub, nothing keeps running.", "good" },
    }
    local cy, cx = y, x
    local tallest = 0
    for i, it in ipairs(items) do
      local th = self:textHeight(it[3], cw - 32 * s, self.f.small)
      local ch = 16 * s + 64 * s + 10 * s + th + 16 * s
      self:card(cx, cy, cw, ch)
      self:button(cx + 16 * s, cy + 16 * s, cw - 32 * s, 64 * s, it[2], function() self:chooseHost(it[1]) end, it[4], self.f.head)
      self:text(it[3], cx + 16 * s, cy + 16 * s + 64 * s + 10 * s, cw - 32 * s, self.f.small, P.warning)
      tallest = math.max(tallest, ch)
      if narrow then cy = cy + ch + 12 * s else cx = cx + cw + 14 * s end
      if i == #items and not narrow then cy = cy + tallest + 12 * s end
    end
    return cy - top
  end
  if cfg.hostChoice == "direct" then
    y = y + self:text("Pick the game you'll play. It opens LINK > HOST and shows a code; send it to your friend (they paste it in JOIN FRIEND, or in their game's LINK > JOIN).",
                      x, y, w, self.f.body, P.ink) + 12 * s
    y = y + self:drawGameGrid(x, y, w, function(v)
      LH.setPending({ kind = "host" })
      self:launch(v)
    end)
    y = y + 12 * s
    self:button(x, y, math.min(w, 320 * s), 48 * s, "USE A HUB INSTEAD", function() self:chooseHost("hub") end)
    return y + 48 * s - top
  end
  -- hub mode
  local ph = LH.phase()
  if ph ~= "running" then
    local msg = ph == "starting" and "Starting your hub..." or ph == "failed" and ("Your hub couldn't start: " .. tostring(LH.lastError()))
                or ph == "stopping" and "Stopping..." or "Your hub is off."
    y = y + self:text(msg, x, y, w, self.f.head, ph == "failed" and P.red or P.ink) + 14 * s
    if ph == "off" or ph == "failed" then
      self:button(x, y, math.min(w, 300 * s), 56 * s, "START HUB", function() self:startHub() end, "good")
      y = y + 56 * s + 12 * s
    end
    self:button(x, y, math.min(w, 300 * s), 48 * s, "PLAY NOW INSTEAD (NO HUB)", function() self:chooseHost("direct") end)
    return y + 48 * s - top
  end
  local display, raw = LH.shareCode()
  if not display then
    y = y + self:text("No code yet: " .. tostring(raw), x, y, w, self.f.body, P.red)
    return y - top
  end
  -- the code card: code + buttons, and the QR beside (or under) it
  local narrow = w < 700 * s
  local pad = 18 * s
  local okQ, QrCode = pcall(require, "src.online.QrCode")
  local qr = okQ and self:qrFor(QrCode, display) or nil
  local target = narrow and math.min(w - 2 * pad, 330 * s) or 300 * s
  local qrCell = qr and math.max(2, math.floor(target / (qr.size + 8))) or 0
  local qrPx = qr and (qr.size + 8) * qrCell or 0
  local leftW = narrow and (w - 2 * pad) or (w - 2 * pad - qrPx - 20 * s)
  -- the biggest font that keeps the code on one line (a phone in portrait)
  local codeFont = self.f.title
  if codeFont:getWidth(display) > leftW then codeFont = self.f.head end
  if codeFont:getWidth(display) > leftW then codeFont = self.f.body end
  local codeH = self:textHeight(display, leftW, codeFont)
  local bh = 56 * s
  local lines = {
    "Friends: open Online Hub > JOIN FRIEND and paste this code, or scan the QR with a phone camera and paste what it shows.",
    "Your own games use this hub automatically while it runs.",
  }
  local linesH = 0
  for _, l in ipairs(lines) do linesH = linesH + self:textHeight(l, leftW, self.f.small) + 4 * s end
  local leftH = self.f.small:getHeight() + 6 * s + codeH + 14 * s + bh * 2 + 10 * s + 12 * s + linesH
  local ch = pad + (narrow and (leftH + 16 * s + qrPx) or math.max(leftH, qrPx)) + pad
  self:card(x, y, w, ch, P.link)
  local cx, cy = x + pad, y + pad
  self:text("YOUR HUB CODE", cx, cy, leftW, self.f.small, P.warning)
  cy = cy + self.f.small:getHeight() + 6 * s
  self:text(display, cx, cy, leftW, codeFont, P.gold)
  cy = cy + codeH + 14 * s
  local half = (leftW - 10 * s) / 2
  self:button(cx, cy, half, bh, "COPY", function() self:copy(LH.shareText(display), display) end, "accent", self.f.head)
  self:button(cx + half + 10 * s, cy, half, bh, "SHARE", function() self:share(display) end, "good", self.f.head)
  cy = cy + bh + 10 * s
  self:button(cx, cy, half, bh, "TEXT MESSAGE", function() self:openShareUrl("sms", display) end)
  self:button(cx + half + 10 * s, cy, half, bh, "EMAIL", function() self:openShareUrl("mailto", display) end)
  cy = cy + bh + 12 * s
  for _, l in ipairs(lines) do cy = cy + self:text(l, cx, cy, leftW, self.f.small, P.ink) + 4 * s end
  if qr then
    local qx, qy
    if narrow then qx, qy = x + (w - qrPx) / 2, cy + 16 * s
    else qx, qy = x + w - pad - qrPx, y + pad end
    local okD = pcall(QrCode.draw, qr, qx, qy, qrCell)
    if not okD then qr = nil end
  end
  y = y + ch + 14 * s
  -- reachability help
  y = y + self:drawReachHelp(x, y, w)
  y = y + 12 * s
  self:button(x, y, math.min(w, 320 * s), 48 * s, "PLAY NOW INSTEAD (NO HUB)", function() self:chooseHost("direct") end)
  return y + 48 * s - top
end

function S:qrFor(QrCode, text)
  if self.qrText ~= text then
    self.qrText = text
    self.qr = QrCode.encode(text, { ecl = "M" })
  end
  return self.qr
end

-- what the router said, and what to do about it
function S:drawReachHelp(x, y, w)
  local s, P = self.s, self:pal()
  local st = LH.status() or {}
  local m = st.mapping or {}
  local cfg = LH.config()
  local ports = st.ports or {}
  local portList = ("TCP and UDP %d"):format(ports.udp or cfg.port)
  if ports.world then portList = portList .. (", UDP %d"):format(ports.world) end
  local lines
  if m.state == "ok" then
    lines = { { "Friends anywhere can join: your router opened " .. portList .. ".", P.playTop or P.ink } }
    if m.note then lines[#lines + 1] = { m.note, P.gold } end
  elseif m.state == "trying" then
    lines = { { "Asking your router to open " .. portList .. "... friends on your Wi-Fi can join already.", P.ink } }
  else
    lines = {
      { m.state == "failed" and ("Your router didn't open the ports (" .. tostring(m.why or "no answer") .. ").")
        or "Router mapping is off in HUB SETTINGS.", P.gold },
      { "Friends on the same Wi-Fi can join right now.", P.ink },
      { "For friends elsewhere: turn on UPnP / NAT-PMP on your router, or forward " .. portList ..
        " to this device, then restart the hub. Or let a friend whose router works host instead.", P.warning },
    }
  end
  local h = 0
  for _, l in ipairs(lines) do h = h + self:text(l[1], x, y + h, w, self.f.small, l[2]) + 4 * s end
  return h
end

function S:copy(text, display)
  local ok = false
  if love.system and love.system.setClipboardText then ok = pcall(love.system.setClipboardText, text) end
  self:say(ok and ("Copied " .. tostring(display or "")) or "Couldn't copy: write the code down", 3)
end

-- the OS share sheet when this build has one (love.system.shareText: a
-- native bridge some mobile builds add); else copy, and say where it went
function S:share(display)
  local text = LH.shareText(display)
  local sys = love.system
  if sys and type(sys.shareText) == "function" then
    -- (false: the bridge could not bring the sheet up)
    local ok, shown = pcall(sys.shareText, text, "Link Hub code")
    if ok and shown ~= false then return end
  end
  self:copy(text, display)
  self:say("Copied: paste it in any chat app", 3)
end

local function urlEncode(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

function S:openShareUrl(kind, display)
  local text = urlEncode(LH.shareText(display))
  local url = kind == "sms" and ("sms:?&body=" .. text) or ("mailto:?subject=" .. urlEncode("Join my Link Hub") .. "&body=" .. text)
  local ok = love.system and love.system.openURL and pcall(love.system.openURL, url)
  if not ok then self:copy(LH.shareText(display), display) end
end

-- ----------------------------------------------------------------- games

function S:readyGames(filterGame)
  local GameVersion = require("src.core.GameVersion")
  local list = {}
  local ready = self.host and self.host.ready or {}
  local fam = filterGame and GameVersion.family and GameVersion.family(filterGame) or nil
  for _, v in ipairs(GameVersion.ORDER) do
    local info = GameVersion.VERSIONS[v]
    if info and ready[v] then
      if not fam or GameVersion.family(v) == fam then list[#list + 1] = v end
    end
  end
  return list
end

function S:drawGameGrid(x, y, w, onPick, filterGame)
  local s, P = self.s, self:pal()
  local GameVersion = require("src.core.GameVersion")
  local games = self:readyGames(filterGame)
  if #games == 0 then
    return self:text(filterGame and "None of your imported games can join that (it needs the same game family)."
                     or "Import a game first (Games > IMPORT ROMS).", x, y, w, self.f.body, P.gold)
  end
  local cols = math.max(1, math.floor((w + 10 * s) / (200 * s)))
  local bw = (w - (cols - 1) * 10 * s) / cols
  local bh = 56 * s
  for i, v in ipairs(games) do
    local c = (i - 1) % cols
    local r = math.floor((i - 1) / cols)
    local info = GameVersion.VERSIONS[v]
    self:button(x + c * (bw + 10 * s), y + r * (bh + 10 * s), bw, bh,
                info.launcherName or info.label or v, function() onPick(v) end, "accent")
  end
  local rows = math.ceil(#games / cols)
  return rows * bh + (rows - 1) * 10 * s
end

function S:pickGame(title, onPick, filterGame)
  self.picker = { title = title, onPick = onPick, filter = filterGame }
  if self.host then self.host.pageScroll = 0 end
end

function S:drawPicker(x, y, w, h)
  local s = self.s
  local p = self.picker
  local top = y
  y = y + self:pageHeader(x, y, w, p.title)
  y = y + self:drawGameGrid(x, y, w, function(v) self.picker = nil; p.onPick(v) end, p.filter)
  return y - top
end

function S:launch(version)
  if not (self.host and self.host.play) then return end
  self:close()
  self.host:play(version)
end

-- ----------------------------------------------------------------- join

-- what is in the code field: decode it and, for a friend's hub, call it
function S:examine(autoProbe)
  self.examined = nil
  if not self.code:match("%S") then return end
  local inv, what = LH.classify(self.code)
  if not inv then
    self.examined = { bad = what }
    return
  end
  self.examined = { invite = inv, what = what }
  if what == "hub" and autoProbe ~= false then LH.probe(inv) end
end

function S:joinPressed()
  if self.editing then self:commitEdit() end
  if not self.code:match("%S") then
    local t = self:paste()
    if t then self.code = t:sub(1, 120) end
  end
  self:examine(true)
  local e = self.examined
  if not e or e.bad then return end
  if e.what == "hub" then return end -- probing; the result shows below
  local code = e.invite.raw or e.invite.display or self.code
  if e.what == "world" then
    self:pickGame("Join the world with", function(v)
      LH.setPending({ kind = "world", code = code })
      self:launch(v)
    end)
  else
    self:pickGame("Join with which game?", function(v)
      LH.setPending({ kind = "join", code = code })
      self:launch(v)
    end)
  end
end

function S:drawJoin(x, y, w, h)
  local s, P, g = self.s, self:pal(), love.graphics
  local top = y
  y = y + self:pageHeader(x, y, w, "JOIN FRIEND")
  y = y + self:text("Paste your friend's code (a hub code, or a code their game shows under LINK > HOST).",
                    x, y, w, self.f.body, P.warning) + 10 * s
  -- the field
  local fh = math.max(56 * s, self.f.head:getHeight() + 24 * s)
  local editing = self.editing and self.editing.id == "code"
  self:card(x, y, w, fh, editing and P.link or nil)
  local shown = editing and self.editing.text or self.code
  g.setFont(self.f.head)
  if shown == "" then
    setc(P.warning, 0.7)
    g.print(Strings("Tap to type or paste a code"), x + 14 * s, y + (fh - self.f.head:getHeight()) / 2)
  else
    setc(P.gold)
    g.printf(shown .. ((editing and (self.t % 1 < 0.5)) and "_" or ""), x + 14 * s, y + (fh - self.f.head:getHeight()) / 2, w - 28 * s, "left")
  end
  self:rect(x, y, w, fh, function()
    self:startEdit("code", self.code, 64, function(t)
      self.code = t
      self.fromClipboard = nil
      self:examine(false)
    end, "code")
    self.editing.submit = function() self:joinPressed() end
  end)
  self.rects[#self.rects].fieldId = "code"
  y = y + fh + 10 * s
  -- buttons
  local bw = (w - 20 * s) / 3
  local bh = 56 * s
  self:button(x, y, bw, bh, "PASTE", function()
    local t = self:paste()
    if t and t ~= "" then
      local inv = LH.classify(t)
      self.code = inv and (inv.display or inv.raw) or t:sub(1, 64)
      self:examine(true)
    else
      self:say("The clipboard is empty", 2)
    end
  end)
  self:button(x + bw + 10 * s, y, bw, bh, "JOIN", function() self:joinPressed() end, "good", self.f.head)
  self:button(x + 2 * (bw + 10 * s), y, bw, bh, "CLEAR", function()
    self.code = ""; self.examined = nil; self.fromClipboard = nil
  end)
  y = y + bh + 10 * s
  if self.fromClipboard then
    y = y + self:text("Found a code on your clipboard and filled it in.", x, y, w, self.f.small, P.playTop or P.ink) + 6 * s
  end
  y = y + self:text("This app can't use the camera. To scan a friend's QR, use your phone's own camera or a QR app, copy the code it shows, then tap PASTE.",
                    x, y, w, self.f.small, P.warning) + 12 * s
  y = y + self:drawJoinResult(x, y, w)
  y = y + self:drawNearby(x, y, w)
  return y - top
end

function S:drawJoinResult(x, y, w)
  local s, P = self.s, self:pal()
  local e = self.examined
  if not e then return 0 end
  local top = y
  if e.bad then
    return self:text(tostring(e.bad), x, y, w, self.f.body, P.red) + 12 * s
  end
  local InviteCode = require("src.online.InviteCode")
  if e.what == "hub" then
    local p = LH.probeState()
    if not p or p.invite ~= e.invite then
      y = y + self:text("A Link Hub code: " .. InviteCode.describe(e.invite) .. ". Tap JOIN to connect.", x, y, w, self.f.body, P.ink)
      return y - top + 12 * s
    end
    if p.phase == "trying" then
      y = y + self:text(("Calling the hub%s..."):format(p.job.trying and (" at " .. p.job.trying) or ""), x, y, w, self.f.body, P.ink)
      return y - top + 12 * s
    end
    if p.phase == "ok" then
      local pong = p.pong
      y = y + self:text(("Connected to %s. Your games now use this hub: SHORT CODE, GTS, TOURNAMENT and WORLDS in a game's LINK menu."):format(tostring(pong.name or "the hub")),
                        x, y, w, self.f.body, P.playTop or P.ink) + 8 * s
      if type(pong.services) == "table" then
        y = y + self:text("Services: " .. table.concat(pong.services, ", "), x, y, w, self.f.small, P.warning) + 8 * s
      end
      local bw = math.min(300 * s, w)
      if pong.worldCode then
        self:button(x, y, bw, 56 * s, "JOIN THEIR WORLD", function()
          self:pickGame("Join their world with", function(v)
            LH.setPending({ kind = "world", code = pong.worldCode })
            self:launch(v)
          end, pong.worldGame)
        end, "accent")
        y = y + 56 * s + 10 * s
      end
      self:button(x, y, bw, 56 * s, "PLAY A GAME", function()
        self:pickGame("Play which game?", function(v) self:launch(v) end)
      end, "good")
      return y + 56 * s + 14 * s - top
    end
    -- failed: what to try
    y = y + self:text("Couldn't reach that hub (" .. tostring(p.why) .. ").", x, y, w, self.f.body, P.red) + 8 * s
    local tips = {
      "Same Wi-Fi? Make sure both devices are on it (not mobile data).",
      "Ask your friend whether their hub page says the router opened the ports. If not, they can turn on UPnP / NAT-PMP or forward the ports it lists, then restart the hub.",
      "Or swap: you host (HOST WITH FRIENDS) and send them your code.",
      "Or ask them for a code from their game's LINK > HOST: a direct code needs no hub.",
    }
    for _, t in ipairs(tips) do y = y + self:text("- " .. t, x, y, w, self.f.small, P.warning) + 4 * s end
    self:button(x, y + 6 * s, math.min(w, 260 * s), 52 * s, "TRY AGAIN", function() LH.probe(e.invite) end, "accent")
    return y + 6 * s + 52 * s + 14 * s - top
  end
  local what = e.what == "short" and ("A short code (room " .. tostring(e.invite.room) .. "): it works when you both use the same hub.")
               or e.what == "world" and "A world code: tap JOIN and pick a game of the same family."
               or ("A game code (" .. InviteCode.describe(e.invite) .. "): tap JOIN and pick your game; it connects straight away.")
  y = y + self:text(what, x, y, w, self.f.body, P.ink) + 12 * s
  return y - top
end

function S:drawNearby(x, y, w)
  local s, P = self.s, self:pal()
  local top = y
  y = y + self:text("ON THIS WI-FI", x, y, w, self.f.head) + 8 * s
  if self.listenNote then y = y + self:text(self.listenNote, x, y, w, self.f.small, P.gold) + 8 * s end
  local hosts = self.listener and self.listener:hosts() or {}
  if #hosts == 0 then
    y = y + self:text(self.listener and "Looking for hubs and games nearby..." or "", x, y, w, self.f.small, P.warning) + 8 * s
    return y - top
  end
  local bh = 56 * s
  for _, hst in ipairs(hosts) do
    local isHub = hst.hub == true or (type(hst.v) == "string" and hst.v:sub(1, 4) == "hub:")
    local label = ("%s  %s  (%s)"):format(isHub and "HUB" or "GAME", tostring(hst.name or "?"),
                                          isHub and hst.address or tostring(hst.game or "?"):upper())
    local kind = isHub and "accent" or (hst.compatible and "good" or nil)
    self:button(x, y, w, bh, label, function() self:pickNearby(hst, isHub) end, kind)
    y = y + bh + 8 * s
  end
  return y - top
end

function S:pickNearby(hst, isHub)
  local InviteCode = require("src.online.InviteCode")
  if isHub then
    local display = InviteCode.encode({ kind = "hub", lan = hst.ip, hub = { port = hst.port }, ticket = 0, lanFull = true })
    if display then
      self.code = display
      self:examine(true)
    end
    return
  end
  if not hst.compatible then
    self:say("That game is a different version of the app", 3)
    return
  end
  local display = InviteCode.encode({ kind = "session", lan = hst.ip, port = hst.port, nonce = hst.nonce or 0, lanFull = true })
  if not display then return end
  self.code = display
  self:examine(false)
  self:pickGame("Join with which game?", function(v)
    LH.setPending({ kind = "join", code = display })
    self:launch(v)
  end, hst.game)
end

-- ----------------------------------------------------------------- config

function S:configRows()
  local cfg = LH.config()
  local rows = {}
  local function add(r) rows[#rows + 1] = r end
  local function set(fn) return function(v) fn(cfg, v); LH.save(cfg) end end
  add({ kind = "header", label = "HUB" })
  add({ kind = "text", id = "name", label = "Hub name", get = function() return cfg.name end,
        set = set(function(c, v) c.name = v end), max = 24 })
  add({ kind = "number", id = "port", label = "Port (TCP + UDP)", get = function() return cfg.port end,
        set = set(function(c, v) c.port = v end), min = 1024, max = 65535, step = 1,
        help = "Friends' codes carry it. 7777 and 7778 are the games' own ports, so the hub uses 7780." })
  add({ kind = "toggle", id = "portMap", label = "Ask the router to open the ports", get = function() return cfg.portMap end,
        set = set(function(c, v) c.portMap = v end), help = "UPnP / NAT-PMP / PCP. Needed for friends outside your Wi-Fi." })
  add({ kind = "toggle", id = "lanBeacon", label = "Show the hub to this Wi-Fi", get = function() return cfg.lanBeacon end,
        set = set(function(c, v) c.lanBeacon = v end) })
  add({ kind = "toggle", id = "autoStart", label = "Start hub when launcher opens", get = function() return cfg.autoStart end,
        set = set(function(c, v) c.autoStart = v end) })
  add({ kind = "toggle", id = "useInGames", label = "Use the hub in my games", get = function() return cfg.useInGames end,
        set = set(function(c, v) c.useInGames = v end),
        help = "Games started from here use your hub (or a friend's) unless their own LINK HUB setting names one." })
  add({ kind = "cycle", id = "hostChoice", label = "HOST WITH FRIENDS does", get = function() return cfg.hostChoice or "ask" end,
        values = { "ask", "hub", "direct" }, labels = { ask = "ASK", hub = "START THE HUB", direct = "PLAY NOW (NO HUB)" },
        set = set(function(c, v) c.hostChoice = v ~= "ask" and v or nil end) })
  add({ kind = "header", label = "SERVICES" })
  add({ kind = "toggle", id = "relay", label = "Short codes (relay)", get = function() return cfg.relay end,
        set = set(function(c, v) c.relay = v end), help = "Six-character room codes; works even on mobile data, through this hub." })
  add({ kind = "toggle", id = "tournaments", label = "Tournaments", get = function() return cfg.tournaments end,
        set = set(function(c, v) c.tournaments = v end) })
  add({ kind = "toggle", id = "gts", label = "GTS", get = function() return cfg.gts.enabled end,
        set = set(function(c, v) c.gts.enabled = v end),
        help = "Deposits are checked against your own imported games' data; pick which below." })
  if cfg.gts.enabled then
    local games = LH.installedGames()
    if #games == 0 then add({ kind = "note", label = "No imported games found to back a GTS." }) end
    for _, gm in ipairs(games) do
      if gm.pool then
        add({ kind = "toggle", id = "gts_" .. gm.id, label = ("  %s (pool %s)"):format(gm.name, gm.pool:upper()),
              get = function() return cfg.gts.games[gm.id] == true end,
              set = set(function(c, v) c.gts.games[gm.id] = v or nil end) })
      end
    end
    add({ kind = "number", id = "gtsExpire", label = "  Deposits expire after (days, 0 = never)",
          get = function() return cfg.gts.expireDays end, set = set(function(c, v) c.gts.expireDays = v end),
          min = 0, max = 365, step = 5 })
  end
  add({ kind = "toggle", id = "world", label = "Always-on world", get = function() return cfg.world.enabled end,
        set = set(function(c, v) c.world.enabled = v end), help = "A world friends can walk into any time (LINK > WORLDS)." })
  if cfg.world.enabled then
    local games, values, labels = LH.installedGames(), {}, {}
    for _, gm in ipairs(games) do values[#values + 1] = gm.id; labels[gm.id] = gm.name end
    add({ kind = "cycle", id = "worldGame", label = "  World game", get = function() return cfg.world.game or "" end,
          values = values, labels = labels, set = set(function(c, v) c.world.game = v end),
          empty = "pick a game" })
    add({ kind = "text", id = "worldName", label = "  World name", get = function() return cfg.world.name end,
          set = set(function(c, v) c.world.name = v end), max = 20 })
    add({ kind = "number", id = "worldCap", label = "  Players (2-16)", get = function() return cfg.world.cap end,
          set = set(function(c, v) c.world.cap = v end), min = 2, max = 16, step = 1 })
    add({ kind = "number", id = "worldPort", label = "  World port (UDP)", get = function() return cfg.world.port end,
          set = set(function(c, v) c.world.port = v end), min = 1024, max = 65535, step = 1 })
    add({ kind = "toggle", id = "worldPublic", label = "  Open to strangers (unmodded games only)", get = function() return cfg.world.public end,
          set = set(function(c, v) c.world.public = v end) })
    add({ kind = "toggle", id = "worldGts", label = "  GTS inside the world", get = function() return cfg.world.gts end,
          set = set(function(c, v) c.world.gts = v end) })
  end
  add({ kind = "header", label = "LIMITS" })
  add({ kind = "number", id = "players", label = "Max players (UDP)", get = function() return cfg.caps.players end,
        set = set(function(c, v) c.caps.players = v end), min = 2, max = 1024, step = 8 })
  add({ kind = "number", id = "tcp", label = "Max short-code connections", get = function() return cfg.caps.tcp end,
        set = set(function(c, v) c.caps.tcp = v end), min = 2, max = 4096, step = 16 })
  add({ kind = "number", id = "perIp", label = "Max per address", get = function() return cfg.caps.perIp end,
        set = set(function(c, v) c.caps.perIp = v end), min = 1, max = 256, step = 1 })
  add({ kind = "number", id = "mps", label = "Messages per second", get = function() return cfg.caps.messagesPerSecond end,
        set = set(function(c, v) c.caps.messagesPerSecond = v end), min = 5, max = 500, step = 5 })
  add({ kind = "header", label = "PRIVACY AND LOGS" })
  add({ kind = "toggle", id = "maskIps", label = "Hide players' full IP in logs", get = function() return cfg.log.maskIps end,
        set = set(function(c, v) c.log.maskIps = v end) })
  add({ kind = "toggle", id = "logFile", label = "Write a log file", get = function() return cfg.log.file end,
        set = set(function(c, v) c.log.file = v end) })
  add({ kind = "cycle", id = "logLevel", label = "Log detail", get = function() return cfg.log.level end,
        values = { "warn", "info", "debug" }, labels = { warn = "PROBLEMS", info = "NORMAL", debug = "EVERYTHING" },
        set = set(function(c, v) c.log.level = v end) })
  add({ kind = "number", id = "keepDays", label = "Keep logs (days)", get = function() return cfg.log.keepDays end,
        set = set(function(c, v) c.log.keepDays = v end), min = 0, max = 365, step = 1 })
  add({ kind = "header", label = "ADMIN" })
  local key = tostring(cfg.adminKey or "")
  local shownKey = self.showKey and key or (key:sub(1, 3) .. string.rep("*", math.max(0, #key - 3)))
  add({ kind = "key", id = "adminKey", label = "Admin key: " .. shownKey, get = function() return cfg.adminKey end,
        help = "For the standalone hub's --admin commands on this machine. Keep it private." })
  return rows
end

function S:drawConfig(x, y, w, h)
  local s, P, g = self.s, self:pal(), love.graphics
  local top = y
  y = y + self:pageHeader(x, y, w, "HUB SETTINGS")
  y = y + self:text("Saved as you change them. A running hub picks them up when it restarts.",
                    x, y, w, self.f.small, P.warning) + 10 * s
  if LH.needsRestart() then
    self:button(x, y, math.min(w, 320 * s), 52 * s, "RESTART THE HUB NOW", function() self:restartHub() end, "gold")
    y = y + 52 * s + 12 * s
  end
  local rowH = 56 * s
  local narrow = w < 560 * s
  local ctrlW = narrow and w or math.min(320 * s, w * 0.45)
  for _, r in ipairs(self:configRows()) do
    if r.kind == "header" then
      y = y + 8 * s
      y = y + self:text(r.label, x, y, w, self.f.head, P.link) + 8 * s
    elseif r.kind == "note" then
      y = y + self:text(r.label, x, y, w, self.f.small, P.gold) + 8 * s
    else
      local labelW = narrow and w or (w - ctrlW - 16 * s)
      local lh = self:textHeight(r.label, labelW, self.f.body)
      local helpH = r.help and self:textHeight(r.help, labelW, self.f.small) or 0
      local textH = lh + (r.help and (helpH + 2 * s) or 0)
      local cy
      if narrow then
        self:text(r.label, x, y, w, self.f.body, P.ink)
        if r.help then self:text(r.help, x, y + lh + 2 * s, w, self.f.small, P.warning) end
        cy = y + textH + 6 * s
        self:drawControl(r, x, cy, w, rowH)
        y = cy + rowH + 14 * s
      else
        local blockH = math.max(rowH, textH)
        self:text(r.label, x, y + (r.help and 0 or (blockH - lh) / 2), labelW, self.f.body, P.ink)
        if r.help then self:text(r.help, x, y + lh + 2 * s, labelW, self.f.small, P.warning) end
        self:drawControl(r, x + w - ctrlW, y + (blockH - rowH) / 2, ctrlW, rowH)
        y = y + blockH + 10 * s
      end
      setc(P.cardBorder, 0.25)
      g.rectangle("fill", x, y - 5 * s, w, math.max(1, s))
    end
  end
  return y - top + 20 * s
end

function S:drawControl(r, x, y, w, h)
  local s, P, g = self.s, self:pal(), love.graphics
  if r.kind == "toggle" then
    local on = r.get() == true
    self:button(x, y, w, h, on and "ON" or "OFF", function() r.set(not on) end, on and "good" or nil, self.f.head)
  elseif r.kind == "number" then
    local bw = math.min(64 * s, w * 0.25)
    local editing = self.editing and self.editing.id == r.id
    self:button(x, y, bw, h, "-", function() r.set(math.max(r.min, (tonumber(r.get()) or r.min) - r.step)) end, nil, self.f.head)
    self:button(x + w - bw, y, bw, h, "+", function() r.set(math.min(r.max, (tonumber(r.get()) or r.min) + r.step)) end, nil, self.f.head)
    local fx, fw = x + bw + 8 * s, w - 2 * bw - 16 * s
    self:card(fx, y, fw, h, editing and P.link or nil)
    g.setFont(self.f.head)
    setc(P.gold)
    local txt = editing and (self.editing.text .. ((self.t % 1 < 0.5) and "_" or "")) or tostring(r.get())
    g.printf(txt, fx, y + (h - self.f.head:getHeight()) / 2, fw, "center")
    self:rect(fx, y, fw, h, function()
      self:startEdit(r.id, tostring(r.get()), 5, function(t)
        local n = tonumber(t)
        if n then r.set(math.max(r.min, math.min(r.max, math.floor(n)))) end
      end, "digits")
    end)
    self.rects[#self.rects].fieldId = r.id
  elseif r.kind == "text" then
    local editing = self.editing and self.editing.id == r.id
    self:card(x, y, w, h, editing and P.link or nil)
    g.setFont(self.f.body)
    setc(P.gold)
    local txt = editing and (self.editing.text .. ((self.t % 1 < 0.5) and "_" or "")) or tostring(r.get() or "")
    g.printf(txt, x + 12 * s, y + (h - self.f.body:getHeight()) / 2, w - 24 * s, "left")
    self:rect(x, y, w, h, function()
      self:startEdit(r.id, tostring(r.get() or ""), r.max or 24, function(t)
        if t:match("%S") then r.set(t) end
      end)
    end)
    self.rects[#self.rects].fieldId = r.id
  elseif r.kind == "cycle" then
    local cur = r.get()
    local label = (r.labels and r.labels[cur]) or (cur ~= "" and tostring(cur):upper()) or (r.empty or "-")
    self:button(x, y, w, h, label .. "  >", function()
      local vals = r.values
      if #vals == 0 then self:say("Import a game first", 2) return end
      local idx = 0
      for i, v in ipairs(vals) do if v == cur then idx = i end end
      r.set(vals[(idx % #vals) + 1])
    end)
  elseif r.kind == "key" then
    local key = tostring(r.get() or "")
    local bw = (w - 16 * s) / 3
    self:button(x, y, bw, h, self.showKey and "HIDE" or "SHOW", function() self.showKey = not self.showKey end)
    self:button(x + bw + 8 * s, y, bw, h, "COPY", function() self:copy(key, "the admin key") end)
    self:button(x + 2 * (bw + 8 * s), y, bw, h, "NEW KEY", function()
      local cfg = LH.config()
      cfg.adminKey = LH.randomKey(24)
      LH.save(cfg)
      self:say("New admin key saved (used from the next hub start)", 3)
    end, "danger")
  end
end

-- restart: once the old thread is gone, start again
local baseUpdate = S.update
function S:update(dt)
  baseUpdate(self, dt)
  if self.restartWhenOff and (LH.phase() == "off" or LH.phase() == "failed") then
    self.restartWhenOff = nil
    self:startHub()
  end
end

return S
