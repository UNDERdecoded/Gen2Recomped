-- World chat: the log a client keeps, and the rate limits the host applies
-- (docs/online-design.md 2.8 "What syncs": chat and emotes).  Pure.
--
--   local bucket = Chat.bucket(burst, refillSeconds)
--   bucket:take(now) -> true | false, secondsUntilNext
--
--   local log = Chat.log(max)
--   log:add{ pid=, name=, text=, kind = "chat"|"notice"|"emote"|"system", t= }
--   log:recent(n, now, maxAge) -> newest-last list
--
-- The size cap and the character clean-up are WorldProtocol.cleanText's.
-- The host enforces both (a modified client cannot talk faster than the
-- bucket lets it); the client runs the same bucket so an honest player is
-- told "slow down" before anything is sent.

local P = require("src.online.world.WorldProtocol")

local Chat = {}

-- ------------------------------------------------------------ token bucket

local Bucket = {}
Bucket.__index = Bucket

function Chat.bucket(burst, refill)
  return setmetatable({ burst = burst or P.CHAT_BURST, refill = refill or P.CHAT_REFILL,
                        tokens = burst or P.CHAT_BURST, at = nil }, Bucket)
end

function Bucket:take(now)
  now = now or 0
  if self.at then
    local gained = (now - self.at) / self.refill
    if gained > 0 then self.tokens = math.min(self.burst, self.tokens + gained) end
  end
  self.at = now
  if self.tokens >= 1 then
    self.tokens = self.tokens - 1
    return true
  end
  return false, (1 - self.tokens) * self.refill
end

-- a cooldown is a bucket of one
function Chat.cooldown(seconds)
  return Chat.bucket(1, seconds)
end

-- ------------------------------------------------------------ log

local Log = {}
Log.__index = Log

function Chat.log(max)
  return setmetatable({ max = max or 40, lines = {}, seq = 0 }, Log)
end

function Log:add(entry)
  self.seq = self.seq + 1
  entry.seq = self.seq
  local lines = self.lines
  lines[#lines + 1] = entry
  while #lines > self.max do table.remove(lines, 1) end
  return entry
end

-- the newest `n` lines (oldest first), optionally only those younger than
-- `maxAge` seconds at `now`
function Log:recent(n, now, maxAge)
  local out = {}
  for i = #self.lines, 1, -1 do
    local e = self.lines[i]
    if maxAge and now and e.t and now - e.t > maxAge then break end
    table.insert(out, 1, e)
    if #out >= n then break end
  end
  return out
end

-- one line as shown: "NAME: text", or the notice as it is
function Chat.format(entry)
  if entry.kind == "chat" then
    return ("%s: %s"):format(tostring(entry.name or "?"), tostring(entry.text or ""))
  elseif entry.kind == "emote" then
    return ("%s %s"):format(tostring(entry.name or "?"), tostring(entry.text or ""))
  end
  return tostring(entry.text or "")
end

-- canned lines for a player without a keyboard (the chat screen offers
-- these on the d-pad; anything typed goes through the same send)
Chat.PHRASES = {
  "Hello!", "Want to trade?", "Want to battle?", "Thanks!", "Good game!",
  "Follow me!", "Wait a moment.", "Be right back.", "See you!",
}

return Chat
