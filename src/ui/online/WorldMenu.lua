-- THE WORLDS SCREEN (docs/online-design.md 2.6 "WORLDS", workstream WS8).
--
-- Out of a world:  HOST A WORLD (name, players 2-16 (8), public/friends,
--                  a world GTS on/off),
--                  JOIN A WORLD (WS2's LongCodeEntry), RECENT WORLDS (re-host
--                  one this game hosted before: same name, members and bans)
-- In a world:      CHAT, EMOTE, PLAYERS (host: KICK / BAN), BANS (host),
--                  SHOW CODE (host), GTS (when the world runs one), LEAVE
--                  (host: CLOSE WORLD)
--
--   WorldMenu.open(game)   -- = OnlineWorld.openMenu(game); WS4's LINK menu
--                          -- calls that for its WORLDS row

local WorldUi = require("src.ui.online.WorldUi")
local P = require("src.online.world.WorldProtocol")

local WorldMenu = {}
WorldMenu.__index = WorldMenu
WorldMenu.isOpaque = true
WorldMenu.isWorldUi = true

local function world() return require("src.online.world.OnlineWorld") end

function WorldMenu.open(game, opts)
  local self = setmetatable({}, WorldMenu)
  self.game = game
  self.opts = opts or {}
  self.width, self.height = WorldUi.surface()
  self.style = WorldUi.style(game)
  self.index = 1
  self.hostName = P.cleanText(world().playerName(game) .. "'S WORLD", P.WORLD_NAME_MAX)
  self.hostCap = world().defaultCap(game)
  self.hostPublic = false
  self.hostGts = true
  self.stage = world().current() and "inworld" or "root"
  game.stack:push(self)
  return self
end

function WorldMenu:uiSize() return self.width, self.height end

function WorldMenu:close()
  if self.game.stack:top() == self then self.game.stack:pop() end
end

function WorldMenu:go(stage, index)
  if stage == "root" then self.recent = nil end
  self.stage = stage
  self.index = index or 1
  self.notice = nil
end

-- ------------------------------------------------------------ rows

function WorldMenu:rows()
  local W = world()
  local s = W.current()
  local c = s and s.client
  local st = self.stage
  if st == "root" then
    -- read once per visit to this screen, not every frame
    if not self.recent then
      local okS, list = pcall(function() return require("src.online.world.WorldStore").new():list() end)
      self.recent = okS and list or {}
    end
    local recent = self.recent
    return {
      { label = "HOST A WORLD", go = "hostSetup" },
      { label = "JOIN A WORLD", go = "join" },
      { label = "RECENT WORLDS", go = "recent", disabled = #recent == 0 },
      { label = "BACK", back = true },
    }
  elseif st == "hostSetup" then
    return {
      { label = "NAME", value = self.hostName, act = "name" },
      { label = "PLAYERS", value = tostring(self.hostCap), act = "cap" },
      { label = "WHO", value = self.hostPublic and "ANYONE" or "FRIENDS", act = "public" },
      { label = "GTS", value = self.hostGts and "ON" or "OFF", act = "gts_toggle" },
      { label = "FILTER", act = "filter_toggle",
        value = (self.hostFilter == nil and (self.hostPublic and "ON" or "OFF"))
                or (self.hostFilter and "ON" or "OFF") },
      { label = "START", act = "start" },
      { label = "BACK", go = "root" },
    }
  elseif st == "recent" then
    local rows = {}
    for _, w in ipairs(self.recent or {}) do
      rows[#rows + 1] = { label = w.name, value = tostring(w.cap), world = w }
    end
    rows[#rows + 1] = { label = "BACK", go = "root" }
    return rows
  elseif st == "inworld" then
    if not c then return { { label = "BACK", back = true } } end
    local rows = {
      { label = "CHAT", act = "chat" },
      { label = "EMOTE", go = "emote" },
      { label = "PLAYERS", go = "players" },
    }
    if s.host then
      rows[#rows + 1] = { label = "BANS", go = "bans" }
      rows[#rows + 1] = { label = "SHOW CODE", act = "code" }
    end
    if c:hasService("gts") then rows[#rows + 1] = { label = "GTS", act = "gts" } end
    -- the 4-player multi over the world's relay (the same rows as the Union Room)
    if c:hasService("multi") and require("src.online.LinkRooms").multiAvailable(self.game) then
      rows[#rows + 1] = { label = "MULTI: LEAD", act = "multi", role = "host" }
      rows[#rows + 1] = { label = "MULTI: JOIN", act = "multi", role = "join" }
    end
    rows[#rows + 1] = { label = s.host and "CLOSE WORLD" or "LEAVE", go = "confirmLeave" }
    rows[#rows + 1] = { label = "BACK", back = true }
    return rows
  elseif st == "emote" then
    local rows = {}
    for _, e in ipairs(P.EMOTES) do rows[#rows + 1] = { label = e:upper(), emote = e } end
    rows[#rows + 1] = { label = "BACK", go = "inworld" }
    return rows
  elseif st == "players" then
    local rows = {}
    if c then
      local list = {}
      for _, m in pairs(c.members) do list[#list + 1] = m end
      table.sort(list, function(a, b) return a.pid < b.pid end)
      for _, m in ipairs(list) do
        local where = m.busy and "LINKED" or WorldUi.mapName(self.game, m.pos and m.pos.m)
        local name = m.name .. (m.pid == c.you and "*" or "") .. (m.host and "+" or "")
        rows[#rows + 1] = { label = name, value = where, member = m }
      end
    end
    rows[#rows + 1] = { label = "BACK", go = "inworld" }
    return rows
  elseif st == "member" then
    return {
      { label = "KICK", act = "kick" },
      { label = "BAN", act = "ban" },
      { label = "BACK", go = "players" },
    }
  elseif st == "bans" then
    local rows = {}
    if s and s.host then
      for _, b in ipairs(s.host:bans()) do rows[#rows + 1] = { label = b.name or "?", value = "UNBAN", ban = b } end
    end
    rows[#rows + 1] = { label = "BACK", go = "inworld" }
    return rows
  elseif st == "confirmLeave" then
    return { { label = "YES", act = "leave" }, { label = "NO", go = "inworld" } }
  end
  return { { label = "BACK", back = true } }
end

-- ------------------------------------------------------------ actions

function WorldMenu:startHosting(spec)
  local W = world()
  local ok, err = pcall(W.hostWorld, self.game, spec)
  if not ok then
    self:go("root")
    self.notice = "Couldn't open the world:\n" .. tostring(err)
    return
  end
  self:go("opening")
end

function WorldMenu:showCode()
  local W = world()
  local code, warning = W.inviteCode()
  if not code then
    self.notice = warning == "starting" and "Still opening the world..." or ("No code yet:\n" .. tostring(warning))
    return
  end
  local menu = self
  local ShowCode = require("src.ui.online.ShowCode")
  ShowCode.open(self.game, {
    code = code, title = "WORLD CODE",
    status = "Share this code to invite players.",
    onUpdate = function(screen, dt)
      W.tick(dt)
      local s = W.current()
      if not s then screen:close() return end
      screen:setStatus(("%d/%d in %s"):format(s.host:count(), s.world.cap, s.world.name))
    end,
    onCancel = function() menu:go("inworld") end,
  })
end

function WorldMenu:join()
  local menu = self
  local Util = require("src.online.net.Util")
  require("src.ui.online.LongCodeEntry").open(self.game, {
    title = "WORLD CODE", myLanIp = Util.lanIP(), allowShort = false,
    onDone = function(invite)
      local s, why = world().joinWorld(menu.game, invite)
      if not s then
        menu:go("root")
        menu.notice = tostring(why)
        return
      end
      menu:go("joining")
    end,
    onCancel = function() menu:go("root") end,
  })
end

function WorldMenu:activate(row)
  local W = world()
  local s = W.current()
  local c = s and s.client
  if row.back then self:close() return end
  if row.go then
    if row.go == "join" then self:join() return end
    self:go(row.go)
    return
  end
  if row.world then
    self:startHosting({ worldId = row.world.id })
    return
  end
  if row.emote and c then
    c:emote(row.emote)
    self:close()
    return
  end
  if row.member and s and s.host and row.member.pid ~= c.you then
    self.target = row.member
    self:go("member")
    return
  end
  if row.ban and s and s.host then
    s.host:unban(row.ban.id)
    return
  end
  local act = row.act
  if act == "name" then
    self.editing = not self.editing
  elseif act == "cap" then
    self.hostCap = self.hostCap % P.MAX_CAP + 1
    if self.hostCap < P.MIN_CAP then self.hostCap = P.MIN_CAP end
  elseif act == "public" then
    self.hostPublic = not self.hostPublic
  elseif act == "gts_toggle" then
    self.hostGts = not self.hostGts
  elseif act == "filter_toggle" then
    local on = self.hostFilter
    if on == nil then on = self.hostPublic end
    self.hostFilter = not on
  elseif act == "start" then
    if self.hostPublic then
      local okH, Handshake = pcall(require, "src.link.Handshake")
      if okH and not Handshake.onlineAllowed(self.game) then
        self.notice = "An open world needs an\nunmodded game. Pick FRIENDS."
        return
      end
    end
    self:startHosting({ name = self.hostName, cap = self.hostCap, public = self.hostPublic,
                        gts = self.hostGts, filter = self.hostFilter })
  elseif act == "chat" then
    require("src.ui.online.ChatOverlay").open(self.game)
  elseif act == "code" then
    self:showCode()
  elseif act == "gts" then
    self:openGts()
  elseif act == "multi" then
    local okO, err = pcall(require("src.online.MultiBattle").open, self.game,
                           { world = true, role = row.role }, { role = row.role })
    if not okO then self.notice = "The multi room did\nnot open." end
    if not okO then require("src.core.Logger").warn("world: multi: %s", tostring(err)) end
  elseif act == "kick" or act == "ban" then
    if self.target and c then c:kick(self.target.pid, act == "ban" and "banned by host" or "kicked by host", act == "ban") end
    self:go("players")
  elseif act == "leave" then
    W.leave()
    self:go("root")
    self.notice = "You left the world."
  end
end

-- the world GTS: WS7's GtsClient on a service channel (see OnlineWorld)
function WorldMenu:openGts()
  local ch = world().gtsChannel()
  if not ch then self.notice = "This world has no GTS." return end
  local okG, GtsClient = pcall(require, "src.online.gts.GtsClient")
  if not (okG and GtsClient and GtsClient.open) then
    ch:close()
    self.notice = "This build has no GTS screen."
    return
  end
  local ok, err = pcall(GtsClient.open, self.game, { channel = ch })
  if not ok then
    ch:close()
    self.notice = "GTS: " .. tostring(err)
  end
end

-- ------------------------------------------------------------ update

function WorldMenu:update(dt)
  local W = world()
  W.tick(dt)
  local s = W.current()
  local c = s and s.client
  local input = self.game.input
  if self.stage ~= "root" and self.stage ~= "hostSetup" and self.stage ~= "recent" and not s then
    self:go("root")
    if W.lastEnded and W.lastEnded.text then self.notice = W.lastEnded.text end
  end
  if self.stage == "opening" then
    if s and s.host then
      local code = W.inviteCode()
      if code then self:go("inworld") self:showCode() return end
      if s.host.state == "failed" then self:go("root") return end
    end
    if input and input:wasPressed("b") then W.leave() self:go("root") end
    return
  elseif self.stage == "joining" then
    if c and c.state == "in" then self:go("inworld") return end
    if input and input:wasPressed("b") then W.leave() self:go("root") end
    return
  end
  local rows = self:rows()
  if self.index > #rows then self.index = #rows end
  if self.editing then return end
  self.index = WorldUi.nav(self.game, self.index, rows)
  if not input then return end
  local row = rows[self.index]
  if self.stage == "hostSetup" and row and (input:wasPressed("left") or input:wasPressed("right")) then
    local d = input:wasPressed("left") and -1 or 1
    if row.act == "cap" then
      self.hostCap = math.max(P.MIN_CAP, math.min(P.MAX_CAP, self.hostCap + d))
    elseif row.act == "public" then
      self.hostPublic = not self.hostPublic
    elseif row.act == "gts_toggle" then
      self.hostGts = not self.hostGts
    elseif row.act == "filter_toggle" then
      self:activate(row)
    end
  end
  if input:wasPressed("a") and row and not row.disabled then
    WorldUi.sound(self.game, "Select")
    self:activate(row)
  elseif input:wasPressed("b") then
    if self.stage == "root" or self.stage == "inworld" then self:close()
    elseif self.stage == "member" then self:go("players")
    elseif self.stage == "hostSetup" or self.stage == "recent" then self:go("root")
    else self:go("inworld") end
  end
end

-- the world's name is typed while the NAME row is being edited
function WorldMenu:onKeyPressed(key)
  if self.editing then
    if key == "backspace" then
      self.hostName = (self.hostName or ""):gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
    elseif key == "return" or key == "kpenter" or key == "escape" then
      self.editing = false
      self.hostName = P.cleanText(self.hostName, P.WORLD_NAME_MAX) or "WORLD"
    end
    return
  end
  local input = self.game and self.game.input
  if input and input.keypressed then input:keypressed(key) end
end

function WorldMenu:onTextInput(t)
  if not self.editing then return end
  local next = ((self.hostName or "") .. tostring(t or "")):gsub("[%c]", "")
  if #P.utf8chars(next) <= P.WORLD_NAME_MAX then self.hostName = next:upper() end
end

-- ------------------------------------------------------------ draw

local TITLES = {
  root = "WORLDS", hostSetup = "HOST A WORLD", recent = "RECENT WORLDS",
  emote = "EMOTE", players = "PLAYERS", member = "PLAYER", bans = "BANS",
  confirmLeave = "LEAVE THE WORLD?",
}

function WorldMenu:draw()
  local st = self.style
  local W, H = self.width, self.height
  st:clear(W, H)
  local s = world().current()
  local c = s and s.client
  if self.stage == "opening" or self.stage == "joining" then
    local text
    if self.stage == "opening" then
      text = "Opening the world...\n" .. ((s and s.host and s.host.connector and s.host.connector.pending)
        and "Asking the router for a port." or "")
    else
      text = "Joining...\n" .. tostring((c and c.job and c.job.progress) or "")
    end
    WorldUi.drawText(st, 4, 4, W - 8, text .. "\n(B: cancel)")
    return
  end
  local title = TITLES[self.stage]
  if self.stage == "inworld" and s then
    local n = 0 for _ in pairs(c and c.members or {}) do n = n + 1 end
    title = ("%s %d/%d"):format(tostring(s.world and s.world.name or (c and c.world and c.world.name) or "WORLD"),
                                n, tonumber(s.world and s.world.cap or (c and c.world and c.world.cap)) or 0)
  elseif self.stage == "member" and self.target then
    title = self.target.name
  end
  local rows = self:rows()
  local lh = st:lineHeight()
  local reserve = (self.notice or self.editing) and (3 * lh + 16) or 0
  -- the frame: 4 above it, its own 10 of padding and the title line
  local room = H - 4 - 10 - (lh + 4) - 2 - reserve
  local rowH = lh + 2
  -- a short screen (Emerald's 160 rows) packs the rows a little tighter
  -- before it scrolls, so every list ends on its BACK
  if #rows * rowH > room and #rows * lh <= room then rowH = lh end
  local visible = math.max(3, math.floor(room / rowH))
  local first = 1
  if self.index > visible then first = self.index - visible + 1 end
  local h = WorldUi.drawList(st, 4, 4, W - 8, rows, self.index, title,
                             { first = first, visible = visible, rowH = rowH })
  if self.editing then
    local C = require("src.ui.online.CodeStyle").colors
    WorldUi.drawText(st, 4, 8 + h, W - 8, "Type a name, ENTER to finish.", C.dim)
  elseif self.notice then
    WorldUi.drawText(st, 4, 8 + h, W - 8, self.notice)
  end
end

return WorldMenu
