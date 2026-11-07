-- Name -> IPv4 without stalling a frame.  luasocket's socket.dns.toip
-- blocks for as long as the resolver takes, so inside LOVE the lookup runs
-- on a love.thread and the calling job polls its channel; IPv4 literals
-- return at once.  Without love.thread (headless tools) it falls back to
-- the blocking call.  Used for the manual-forward DNS name (L2), the STUN
-- server and hub/relay addresses typed as names.
--
--   Dns.resolve(name, timeout) -> ip | nil, why     (call inside Util.job)

local Util = require("src.online.net.Util")

local Dns = {}

local THREAD_CODE = [[
local name, out = ...
local ok, socket = pcall(require, "socket")
if not ok then out:push("!no luasocket") return end
local ip, err = socket.dns.toip(name)
out:push(ip or ("!" .. tostring(err)))
]]

local cache = {}

function Dns.resolve(name, timeout)
  if type(name) ~= "string" or name == "" then return nil, "no address" end
  if Util.isIPv4(name) then return name end
  if name == "localhost" then return "127.0.0.1" end
  if cache[name] then return cache[name] end
  local ip, why
  if love and love.thread and love.thread.newThread then
    local out = love.thread.newChannel()
    local th = love.thread.newThread(THREAD_CODE)
    th:start(name, out)
    local deadline = Util.time() + (timeout or 5)
    while true do
      local v = out:pop()
      if v then
        if v:sub(1, 1) == "!" then why = v:sub(2) else ip = v end
        break
      end
      local terr = th:getError()
      if terr then why = terr break end
      if Util.time() > deadline then why = "lookup timed out" break end
      Util.yield()
    end
  elseif Util.socket then
    local r, err = Util.socket.dns.toip(name)
    ip, why = r, err
  else
    why = "no resolver"
  end
  if ip then
    cache[name] = ip
    return ip
  end
  return nil, ("can't find %s (%s)"):format(name, tostring(why))
end

return Dns
