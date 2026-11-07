-- The GTS screen (docs/online-design.md 2.7a, workstream WS7).
--
-- Opened through GtsClient.open(game, opts) -- the Global Terminal counters
-- (WS6b), the LINK menu (WS4) and a world's menu (WS8) all land here.  One
-- screen for every game, in the cartridge's look ("game": its own font and
-- window frame, on its own surface -- 160x144, 240x160 or 256x192) or the
-- neutral look:
--
--   GTS                       DEPOSIT POKéMON | SUMMARY (your deposit)
--                             SEEK POKéMON
--                             EXIT
--   DEPOSIT   party -> the species you want (seen only) -> gender -> level
--             band -> confirm
--   SEEK      species (seen only) -> gender -> level band -> the results
--             (seven at a time) -> a listing -> OFFER -> a party mon that
--             meets its wants -> confirm -> the trade
--   SUMMARY   your deposit and what it asks for -> TAKE BACK
--
-- Results that arrive (a trade done while you were away, a mon returned)
-- are announced as they are filed, and a trade evolution plays.
--
-- Deposits and offers take a party mon or any PC box mon ("B<n>" beside it).
--
-- opts: channel (netLike) | connect | (the provider), style, width, height, persist,
--       noConnectText, ownsChannel (close it on exit), onDone(result),
--       client (an existing GtsClient, tests)

local GtsRules = require("src.online.gts.GtsRules")
local GtsPools = require("src.online.gts.GtsPools")

local GtsScreen = {}
GtsScreen.__index = GtsScreen
GtsScreen.isOpaque = true

GtsScreen.NO_CONNECT = "Could not connect to the GTS."

function GtsScreen.new(game, opts, channel)
  opts = opts or {}
  local self = setmetatable({ game = game, opts = opts, views = {}, notes = {},
                              t = 0 }, GtsScreen)
  local CodeStyle = require("src.ui.online.CodeStyle")
  self.width, self.height = CodeStyle.surface(opts)
  self.styleKind = opts.style or CodeStyle.defaultKind(game)
  self.style = CodeStyle.new(self.styleKind)
  self.channel = channel
  if opts.client then
    self.client = opts.client
    self.client.onEvent = function(ev) self:onEvent(ev) end
  elseif channel then
    local GtsClient = require("src.online.gts.GtsClient")
    self.client = GtsClient.forGame(game, { channel = channel, player = opts.player, persist = opts.persist,
                                            onEvent = function(ev) self:onEvent(ev) end })
  end
  if not self.client then
    self:message(opts.noConnectText or GtsScreen.NO_CONNECT, function() self:finish("noconnect") end)
  elseif self.client.state == "ready" then
    self:mainMenu()
  else
    self:push({ kind = "wait", text = "Connecting to the GTS...", onBack = function() self:finish("closed") end })
  end
  return self
end

function GtsScreen.open(game, opts, channel)
  local s = GtsScreen.new(game, opts, channel)
  if game and game.stack then game.stack:push(s) end
  return s
end

function GtsScreen:uiSize() return self.width, self.height end

function GtsScreen:data() return self.client and self.client.data or (self.game and self.game.data) end

function GtsScreen:finish(result)
  if self.done then return end
  self.done = true
  if self.client and (self.opts.ownsChannel or self.opts.connect) then self.client:close() end
  if self.game and self.game.stack and self.game.stack:top() == self then self.game.stack:pop() end
  if self.opts.onDone then self.opts.onDone(result or "done") end
end

-- ------------------------------------------------------------ views

function GtsScreen:push(v)
  v.index = v.index or 1
  v.top = v.top or 1
  self.views[#self.views + 1] = v
  return v
end

function GtsScreen:pop()
  self.views[#self.views] = nil
end

function GtsScreen:top() return self.views[#self.views] end

function GtsScreen:reset() self.views = {} end

function GtsScreen:message(text, onDone)
  return self:push({ kind = "message", text = text, onDone = onDone })
end

-- a list: rows = { { label =, sub =, disabled = why, pick = fn } }
function GtsScreen:list(title, header, rows, onBack, extra)
  local v = { kind = "list", title = title, header = header, rows = rows, onBack = onBack }
  for k, x in pairs(extra or {}) do v[k] = x end
  return self:push(v)
end

function GtsScreen:confirm(text, onYes)
  return self:list(nil, text, {
    { label = "YES", pick = onYes },
    { label = "NO", pick = function() self:pop() end },
  }, function() self:pop() end)
end

-- wait for a request: a "Please wait..." view until cb fires
function GtsScreen:waitFor(text)
  local v = self:push({ kind = "wait", text = text or "Communicating... Please wait." })
  return function()
    for i = #self.views, 1, -1 do
      if self.views[i] == v then table.remove(self.views, i) break end
    end
  end
end

-- ------------------------------------------------------------ names

function GtsScreen:monName(mon)
  local data = self:data()
  if mon.nickname and mon.nickname ~= "" then return mon.nickname end
  local def = data.pokemon and data.pokemon[mon.species]
  return def and def.name or "?"
end

function GtsScreen:infoLine(info, withLevel)
  local data = self:data()
  local name = GtsRules.speciesName(data, info.dex)
  local g = GtsRules.GENDER_MARK[info.gender or "none"] or ""
  local s = name .. (g ~= "" and (" " .. g) or "")
  if withLevel ~= false and info.level then s = s .. " Lv" .. info.level end
  return s
end

-- ------------------------------------------------------------ menus

function GtsScreen:mainMenu()
  self:reset()
  local c = self.client
  local pool = c.pool
  local rows = {}
  if c.status and c.status.deposit then
    rows[#rows + 1] = { label = "SUMMARY", pick = function() self:summary() end }
  else
    rows[#rows + 1] = { label = "DEPOSIT POKéMON", pick = function() self:depositFlow() end }
  end
  rows[#rows + 1] = { label = "SEEK POKéMON", pick = function() self:seekFlow() end }
  rows[#rows + 1] = { label = "EXIT", pick = function() self:finish("done") end }
  local header = GtsPools.describe(pool)
  self:list("GLOBAL TRADE STATION", header, rows, function() self:finish("done") end, { main = true })
end

-- every mon the player can put up: the party, then each PC box (the
-- cartridge GTS takes box Pokemon too).  filter(source, mon) -> why | nil;
-- onPick(source, mon)
function GtsScreen:monRows(filter, onPick)
  local rows = {}
  local save = self.client.save
  local function add(source, mon, where)
    local info = GtsRules.infoOf(self:data(), mon)
    local g = GtsRules.GENDER_MARK[info.gender] or ""
    rows[#rows + 1] = {
      label = self:monName(mon) .. (g ~= "" and (" " .. g) or ""),
      right = (where and (where .. " ") or "") .. "Lv" .. tostring(mon.level),
      disabled = filter(source, mon),
      pick = function() onPick(source, mon) end,
    }
  end
  for i, mon in ipairs(save.party or {}) do add({ where = "party", index = i }, mon) end
  local okB, Boxes = pcall(require, "src.pokemon.Boxes")
  if okB and Boxes then
    local okE, boxes = pcall(Boxes.ensure, save)
    if okE and type(boxes) == "table" then
      for b = 1, Boxes.count() do
        local box = boxes[b]
        if type(box) == "table" then
          for slot = 1, Boxes.capacity() do
            local mon = box[slot]
            if type(mon) == "table" then add({ where = "box", box = b, slot = slot }, mon, "B" .. b) end
          end
        end
      end
    end
  end
  return rows
end

-- species the save has seen, for a want or a seek
function GtsScreen:speciesRows(onPick)
  local data = self:data()
  local pool = self.client:poolInfo()
  local rows = {}
  for _, dex in ipairs(GtsRules.seenList(self.client.save, data, pool and pool.maxDex)) do
    rows[#rows + 1] = { label = GtsRules.speciesName(data, dex), right = ("%03d"):format(dex),
                        pick = function() onPick(dex) end }
  end
  return rows
end

function GtsScreen:wantFlow(title, onWant)
  local data = self:data()
  local gen = self.client:poolInfo() and self.client:poolInfo().gen
  local rows = self:speciesRows(function(dex)
    local gRows = {}
    for _, g in ipairs(GtsRules.genderOptions(data, dex, gen)) do
      gRows[#gRows + 1] = { label = GtsRules.GENDER_LABEL[g], pick = function()
        local bRows = {}
        for b = 0, GtsRules.MAX_BAND do
          bRows[#bRows + 1] = { label = GtsRules.band(b).label, pick = function()
            onWant({ dex = dex, gender = g, band = b })
          end }
        end
        self:list(title, "Choose the level.", bRows, function() self:pop() end)
      end }
    end
    if #gRows == 1 then
      gRows[1].pick()
    else
      self:list(title, "Choose the gender.", gRows, function() self:pop() end)
    end
  end)
  if #rows == 0 then
    self:message("You haven't seen any POKéMON yet.")
    return
  end
  self:list(title, "Choose a POKéMON you've seen.", rows, function() self:pop() end)
end

function GtsScreen:depositFlow()
  local c = self.client
  local rows = self:monRows(function(src) return c:depositBlocker(src) end,
    function(src, mon)
      local name = self:monName(mon)
      self:wantFlow("WHAT DO YOU WANT?", function(want)
        local text = ("Deposit %s and ask for %s?"):format(name, GtsRules.describeWant(self:data(), want))
        self:confirm(text, function()
          local done = self:waitFor()
          c:deposit(src, want, function(ok, reply)
            done()
            if ok then
              self:mainMenu()
              self:message(("%s was sent to the GTS."):format(name))
            else
              self:message(reply.text or "It could not be deposited.")
            end
          end)
        end)
      end)
    end)
  self:list("DEPOSIT", "Which POKéMON will you deposit?", rows, function() self:pop() end)
end

function GtsScreen:summary()
  local c = self.client
  local dep = c.status and c.status.deposit
  if not dep then return self:mainMenu() end
  local header = ("Your %s asks for %s."):format(self:infoLine(dep.info), GtsRules.describeWant(self:data(), dep.want))
  self:list("SUMMARY", header, {
    { label = "TAKE BACK", pick = function()
      self:confirm("Take your POKéMON back?", function()
        local done = self:waitFor()
        c:withdraw(function(ok, reply)
          done()
          if ok then
            self:mainMenu()
          else
            self:message(reply.text or "It could not be taken back.")
          end
        end)
      end)
    end },
    { label = "BACK", pick = function() self:pop() end },
  }, function() self:pop() end)
end

function GtsScreen:seekFlow()
  local c = self.client
  self:wantFlow("SEEK POKéMON", function(query)
    local done = self:waitFor("Searching...")
    c:search(query, function(ok, reply)
      done()
      if not ok then return self:message(reply.text or "The search failed.") end
      if #reply.items == 0 then return self:message("No POKéMON were found.") end
      local rows = {}
      for _, dep in ipairs(reply.items) do
        rows[#rows + 1] = { label = self:infoLine(dep.info), sub = "wants " .. GtsRules.describeWant(self:data(), dep.want, true),
                            pick = function() self:listing(dep) end }
      end
      self:list("RESULTS", nil, rows, function() self:pop() end)
    end)
  end)
end

function GtsScreen:listing(dep)
  local c = self.client
  local who = dep.name or "?"
  local header = ("%s's %s. Wants %s."):format(who, self:infoLine(dep.info), GtsRules.describeWant(self:data(), dep.want))
  self:list("TRADE", header, {
    { label = "OFFER A POKéMON", pick = function()
      local rows = self:monRows(function(src) return c:offerBlocker(dep, src) end,
        function(src, mon)
          local text = ("Trade %s for %s?"):format(self:monName(mon), self:infoLine(dep.info))
          self:confirm(text, function()
            local done = self:waitFor()
            c:offer(dep, src, function(ok, reply)
              done()
              if ok then
                self:mainMenu()
              else
                self:message(reply.text or "The trade could not be made.")
              end
            end)
          end)
        end)
      self:list("OFFER", "Which POKéMON will you offer?", rows, function() self:pop() end)
    end },
    { label = "BACK", pick = function() self:pop() end },
  }, function() self:pop() end)
end

-- ------------------------------------------------------------ events

function GtsScreen:onEvent(ev)
  local c = self.client
  if ev.type == "welcome" then
    self:mainMenu()
  elseif ev.type == "denied" then
    self:reset()
    self:message(ev.text or "The GTS refused the connection.", function() self:finish("denied") end)
  elseif ev.type == "closed" then
    if self.done then return end
    self:reset()
    self:message(ev.text or "The connection was lost.", function() self:finish("closed") end)
  elseif ev.type == "received" then
    local player = (c.save.player and c.save.player.name) or "You"
    local name = self:monName(ev.mon)
    local text
    if ev.kind == "traded" then
      text = ("Your POKéMON was traded to %s! %s received %s!"):format(ev.from or "someone", player, name)
    elseif ev.kind == "returned" then
      text = ("%s came back from the GTS."):format(name)
    else
      text = ("Trade completed! %s received %s!"):format(player, name)
    end
    if c.status and (ev.kind == "traded" or ev.kind == "returned") then c.status.deposit = nil end
    local v = self:top()
    if v and v.main then self:mainMenu() end
    local evo, row, mon = ev.evolveTo, ev.evolveRow, ev.mon
    self:message(text, function()
      if evo and self.game and self.game.stack then
        pcall(function()
          require("src.pokemon.Evolution").evolve(self.game, mon, evo, function()
            if self.game.writeSave then self.game:writeSave() end
          end, "TRADE", row)
        end)
      end
    end)
  elseif ev.type == "returned" then
    self:message(ev.text or "Your POKéMON was returned.")
  elseif ev.type == "mail_error" then
    self:message("A POKéMON is waiting but could not be received: " .. tostring(ev.text))
  end
end

-- ------------------------------------------------------------ update

function GtsScreen:pressed(b)
  local input = self.game and self.game.input
  return input and input.wasPressed and input:wasPressed(b)
end

function GtsScreen:visibleRows()
  local M = self:measure()
  return M.rows
end

function GtsScreen:update(dt)
  dt = dt or 1 / 60
  self.t = self.t + dt
  if self.client then self.client:update(dt) end
  if self.done then return end
  local v = self:top()
  if not v then return end
  if v.kind == "message" then
    if self:pressed("a") or self:pressed("b") then
      self:pop()
      if v.onDone then v.onDone() end
    end
  elseif v.kind == "wait" then
    if v.onBack and self:pressed("b") then v.onBack() end
  elseif v.kind == "list" then
    local n = #v.rows
    local page = math.max(1, self:visibleRows())
    if self:pressed("up") then v.index = v.index > 1 and v.index - 1 or n
    elseif self:pressed("down") then v.index = v.index < n and v.index + 1 or 1
    elseif self:pressed("left") then v.index = math.max(1, v.index - page)
    elseif self:pressed("right") then v.index = math.min(n, v.index + page)
    elseif self:pressed("a") then self:pick(v, v.index)
    elseif self:pressed("b") then if v.onBack then v.onBack() end
    end
    if v.index < v.top then v.top = v.index end
    if v.index >= v.top + page then v.top = v.index - page + 1 end
  end
end

function GtsScreen:pick(v, i)
  local row = v.rows[i]
  if not row then return end
  if row.disabled then
    self:message(row.disabled)
    return
  end
  if row.pick then row.pick() end
end

-- ------------------------------------------------------------ layout / draw

function GtsScreen:measure()
  local style = self.style
  local W, H = self.width, self.height
  local M = { margin = 8, lh = style:lineHeight() }
  M.rowH = M.lh + 2
  M.titleY = 2
  local v = self:top()
  M.headerLines = {}
  if v and v.header then M.headerLines = style:wrap(v.header, W - 2 * M.margin - 4) end
  M.listY = M.titleY + M.lh + 4 + (#M.headerLines > 0 and (#M.headerLines * M.lh + 4) or 0)
  M.footY = H - M.lh - 4
  M.boxY, M.boxBottom = M.listY - 2, M.footY
  if style.kind == "game" then
    -- the cartridge frame is whole 8-pixel tiles: rows start one tile in
    M.boxY = math.ceil((M.listY - 2) / 8) * 8
    M.listY = M.boxY + 8
    M.boxBottom = math.floor(M.footY / 8) * 8
    M.footY = M.boxBottom
  end
  local subRows = v and v.kind == "list" and v.rows[1] and v.rows[1].sub
  M.perRow = subRows and (2 * M.lh + 2) or M.rowH
  local inner = style.kind == "game" and (M.boxBottom - 8 - M.listY) or (M.footY - M.listY - 4)
  M.rows = math.max(1, math.floor(inner / M.perRow))
  return M
end

function GtsScreen:tap(x, y)
  local v = self:top()
  if not v then return false end
  if v.kind == "message" then
    self:pop()
    if v.onDone then v.onDone() end
    return true
  end
  if v.kind ~= "list" then return true end
  local M = self:measure()
  local i = math.floor((y - M.listY - 2) / M.perRow) + v.top
  if y >= M.listY and i >= v.top and i <= math.min(#v.rows, v.top + M.rows - 1) then
    v.index = i
    self:pick(v, i)
  end
  return true
end

function GtsScreen:touchpressed(_, px, py)
  local CodeStyle = require("src.ui.online.CodeStyle")
  local x, y = CodeStyle.toSurface(px, py)
  if not x then return false end
  return self:tap(x, y)
end

local function trimTo(style, text, maxW)
  if style:width(text) <= maxW then return text end
  while #text > 1 and style:width(text .. "..") > maxW do text = text:sub(1, -2) end
  return text .. ".."
end

function GtsScreen:draw()
  local style = self.style
  local C = require("src.ui.online.CodeStyle").colors
  local W, H = self.width, self.height
  local M = self:measure()
  style:clear(W, H)
  local v = self:top()
  local title = (v and v.title) or "GTS"
  if title == "GLOBAL TRADE STATION" and style:width(title) > W - 2 * M.margin then title = "GTS" end
  style:text(trimTo(style, title, W - 2 * M.margin), M.margin, M.titleY)

  if v and (v.kind == "message" or v.kind == "wait") then
    local lines = style:wrap(v.text or "", W - 2 * M.margin - 8)
    local boxH = math.max(3 * M.lh, (#lines + 1) * M.lh + 8)
    local boxY = math.floor((H - boxH) / 2)
    style:box(4, boxY, W - 8, boxH)
    for i, l in ipairs(lines) do
      style:text(l, M.margin + 4, boxY + 6 + (i - 1) * M.lh)
    end
    if v.kind == "wait" then
      local dots = string.rep(".", math.floor(self.t * 3) % 4)
      style:text(dots, W - M.margin - 4 - style:width("..."), boxY + boxH - M.lh - 4, C.dim)
    elseif v.kind == "message" then
      style:text("A", W - M.margin - 4 - style:width("A"), boxY + boxH - M.lh - 4, C.dim)
    end
  elseif v and v.kind == "list" then
    if #M.headerLines > 0 then
      local hy = M.titleY + M.lh + 3
      for i, l in ipairs(M.headerLines) do
        style:text(l, M.margin + 2, hy + (i - 1) * M.lh, C.dim)
      end
    end
    style:box(style.kind == "game" and 0 or 4, M.boxY, style.kind == "game" and W or (W - 8), M.boxBottom - M.boxY)
    local last = math.min(#v.rows, v.top + M.rows - 1)
    for i = v.top, last do
      local row = v.rows[i]
      local y = M.listY + 2 + (i - v.top) * M.perRow
      local selected = i == v.index
      if selected then style:rect("fill", 8, y - 1, W - 16, M.perRow, C.soft) end
      local color = row.disabled and C.dim or C.ink
      local x = M.margin + 8
      if selected and love and love.graphics then
        -- a drawn cursor: not every cartridge font has a ">" that reads as one
        style:setColor(C.ink)
        local cy = y + math.floor(M.lh / 2)
        local s = math.max(2, math.floor(M.lh / 4))
        love.graphics.polygon("fill", M.margin + 2, cy - s, M.margin + 2, cy + s, M.margin + 2 + s, cy)
        love.graphics.setColor(1, 1, 1, 1)
      end
      local rightW = row.right and (style:width(row.right) + 6) or 0
      style:text(trimTo(style, row.label, W - x - M.margin - 4 - rightW), x, y, color)
      if row.right then style:text(row.right, W - M.margin - 4 - style:width(row.right), y, color) end
      if row.sub then style:text(trimTo(style, row.sub, W - x - M.margin - 4), x + 4, y + M.lh, C.dim) end
    end
    if v.top > 1 then style:text("^", W - M.margin - 2, M.listY - 1, C.dim) end
    if last < #v.rows then style:text("v", W - M.margin - 2, M.footY - M.lh, C.dim) end
    local sel = v.rows[v.index]
    local foot = sel and sel.disabled or nil
    if not foot and #v.rows > M.rows then foot = ("%d/%d"):format(v.index, #v.rows) end
    if foot then style:text(trimTo(style, foot, W - 2 * M.margin), M.margin, M.footY + 2, C.dim) end
  end
  if love and love.graphics then love.graphics.setColor(1, 1, 1, 1) end
end

return GtsScreen
