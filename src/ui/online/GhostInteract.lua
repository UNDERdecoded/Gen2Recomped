-- WALK UP TO A PLAYER, PRESS A (docs/online-design.md 2.8).
--
--   GhostInteract.open(game, pid)       TRADE / BATTLE / CANCEL, then "Waiting
--                                        for NAME..." until they answer
--   GhostInteract.openInvite(game, ev)  the other end: "NAME wants to TRADE."
--                                        ACCEPT / DECLINE
--
-- Both are small windows over the field (the world keeps drawing and
-- moving under them).  An accepted invite becomes a w_session, and
-- OnlineWorld opens the link screen on it (src/online/world/WorldLink.lua),
-- popping these windows first.

local WorldUi = require("src.ui.online.WorldUi")
local P = require("src.online.world.WorldProtocol")

local GhostInteract = {}
GhostInteract.__index = GhostInteract
GhostInteract.isOpaque = false
GhostInteract.isWorldUi = true

local REASONS = {
  declined = "%s said no.", busy = "%s is busy.", ["too far"] = "%s is too far away.",
  ["not here"] = "%s is not here.", ["no answer"] = "%s didn't answer.",
  ["too soon"] = "Wait a moment first.", ["already asking"] = "You already asked someone.",
  left = "%s left.", cancelled = "Cancelled.",
}

local function world() return require("src.online.world.OnlineWorld") end

function GhostInteract.new(game, opts)
  local self = setmetatable({}, GhostInteract)
  self.game = game
  self.opts = opts
  self.index = 1
  self.width, self.height = WorldUi.surface()
  self.style = WorldUi.style(game)
  return self
end

function GhostInteract:uiSize() return self.width, self.height end

function GhostInteract.open(game, pid)
  local c = world().client()
  if not (c and c.members[pid]) then return nil end
  local self = GhostInteract.new(game, {})
  self.kind = "ask"
  self.pid = pid
  self.name = c:nameOf(pid)
  self.rows = { { label = "TRADE", mode = "trade" }, { label = "BATTLE", mode = "battle" },
                { label = "CANCEL" } }
  game.stack:push(self)
  return self
end

function GhostInteract.openInvite(game, ev)
  local self = GhostInteract.new(game, {})
  self.kind = "invite"
  self.ev = ev
  self.name = ev.name or "?"
  self.rows = { { label = "ACCEPT", ok = true }, { label = "DECLINE", ok = false } }
  game.stack:push(self)
  WorldUi.sound(game, "Select")
  return self
end

function GhostInteract:close()
  if self.game.stack:top() == self then self.game.stack:pop() end
end

function GhostInteract:say(text, seconds)
  self.message = text
  self.messageLeft = seconds or 1.6
  self.rows = nil
end

function GhostInteract:update(dt)
  dt = dt or 1 / 60
  local W = world()
  W.tick(dt)
  local s = W.current()
  local c = s and s.client
  if not (c and c.state == "in") then self:close() return end
  local input = self.game.input
  if self.message then
    self.messageLeft = self.messageLeft - dt
    if self.messageLeft <= 0 or (input and (input:wasPressed("a") or input:wasPressed("b"))) then
      self:close()
    end
    return
  end
  if self.kind == "waiting" then
    local ans = s.lastAnswer
    if ans and ans ~= self.seenAnswer and not ans.ok then
      s.lastAnswer = nil
      self:say((REASONS[ans.reason] or ("%s: " .. tostring(ans.reason))):format(self.name))
      return
    end
    if not c.pendingInvite and not (ans and ans.ok) then
      -- answered and the session is opening (OnlineWorld pops us), or gone
      self.waitGone = (self.waitGone or 0) + dt
      if self.waitGone > 3 then self:close() end
    end
    if input and input:wasPressed("b") then
      c:cancelInvite()
      self:say("Cancelled.", 0.8)
    end
    return
  end
  if self.kind == "invite" then
    if s.withdrawn and s.withdrawn[self.ev.iid] then
      self:say(("%s gave up asking."):format(self.name))
      return
    end
    if not c.incoming[self.ev.iid] then self:close() return end
  end
  self.index = WorldUi.nav(self.game, self.index, self.rows)
  if not input then return end
  if input:wasPressed("a") then
    local row = self.rows[self.index]
    if self.kind == "ask" then
      if not row.mode then self:close() return end
      local m = c.members[self.pid]
      if not m then self:say(("%s left."):format(self.name)) return end
      if m.busy then self:say(("%s is busy."):format(self.name)) return end
      if c:invite(self.pid, row.mode) then
        self.kind, self.mode = "waiting", row.mode
        self.seenAnswer = s.lastAnswer
        self.rows = {}
      else
        self:say("You already asked someone.")
      end
    elseif self.kind == "invite" then
      c:answer(self.ev.iid, row.ok)
      if row.ok then
        self.kind = "waiting"
        self.rows = {}
        self.accepted = true
      else
        self:close()
      end
    end
  elseif input:wasPressed("b") then
    if self.kind == "invite" then c:answer(self.ev.iid, false) end
    self:close()
  end
end

function GhostInteract:draw()
  local st = self.style
  local W, H = self.width, self.height
  local lh = st:lineHeight()
  local boxW = math.min(W - 8, 152)
  local x = math.floor((W - boxW) / 2)
  if self.message then
    WorldUi.drawText(st, x, H - (lh * 3 + 16), boxW, self.message)
    return
  end
  if self.kind == "waiting" then
    local text = self.accepted and "Linking up..." or
      ("Waiting for %s...\n(B: cancel)"):format(self.name)
    WorldUi.drawText(st, x, H - (lh * 3 + 16), boxW, text)
    return
  end
  local title
  if self.kind == "invite" then
    title = ("%s: %s?"):format(self.name, self.ev.mode == "battle" and "BATTLE" or "TRADE")
  else
    title = self.name
  end
  local h = (#self.rows) * (lh + 2) + lh + 14
  WorldUi.drawList(st, x, H - h - 4, boxW, self.rows, self.index, title)
end

return GhostInteract
