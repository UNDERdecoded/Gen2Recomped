-- A minimal non-blocking HTTP/1.1 client over luasocket TCP, for talking
-- to a router's UPnP description and SOAP control URLs.  socket.http blocks
-- for its whole timeout, which would freeze a frame; this one connects with
-- timeout 0 and yields (Util.yield) between polls, so run it inside a
-- Util.job.  Outside a job it naps instead and still honours `timeout`.
--
--   local res, why = HttpLite.request{ method = "POST", url = "http://...",
--                       headers = { ... }, body = "...", timeout = 3 }
--   res = { status = 200, headers = { ["content-type"] = ... }, body = "..." }
--
-- Only plain http:// to IPv4 literals (a router is always one; anything
-- else is refused rather than resolved with a blocking DNS call).

local Util = require("src.online.net.Util")

local HttpLite = {}

HttpLite.MAX_BODY = 256 * 1024

function HttpLite.parseUrl(url)
  if type(url) ~= "string" then return nil end
  local host, port, path = url:match("^[Hh][Tt][Tt][Pp]://([^/:]+):?(%d*)(.*)$")
  if not host then return nil end
  if path == "" then path = "/" end
  return { host = host, port = tonumber(port) or 80, path = path }
end

-- resolve `rel` against the absolute URL `base`
function HttpLite.resolve(base, rel)
  if not rel or rel == "" then return base end
  if rel:match("^[%a][%w+.-]*://") then return rel end
  local b = HttpLite.parseUrl(base)
  if not b then return rel end
  local root = ("http://%s:%d"):format(b.host, b.port)
  if rel:sub(1, 1) == "/" then return root .. rel end
  local dir = b.path:match("^(.*/)") or "/"
  return root .. dir .. rel
end

-- split a raw response into status line, headers and body (pure)
function HttpLite.parseResponse(raw)
  local headEnd = raw:find("\r\n\r\n", 1, true)
  local sepLen = 4
  if not headEnd then
    headEnd = raw:find("\n\n", 1, true)
    sepLen = 2
  end
  if not headEnd then return nil, "incomplete headers" end
  local head = raw:sub(1, headEnd - 1)
  local body = raw:sub(headEnd + sepLen)
  local status = tonumber(head:match("^HTTP/%d%.%d%s+(%d+)"))
  if not status then return nil, "bad status line" end
  local headers = {}
  for line in head:gmatch("[^\r\n]+") do
    local k, v = line:match("^([^:]+):%s*(.-)%s*$")
    if k then headers[k:lower()] = v end
  end
  if (headers["transfer-encoding"] or ""):lower():find("chunked", 1, true) then
    local dec, why = HttpLite.dechunk(body)
    if not dec then return nil, why end
    body = dec
  elseif headers["content-length"] then
    local n = tonumber(headers["content-length"])
    if n and #body > n then body = body:sub(1, n) end
  end
  return { status = status, headers = headers, body = body }
end

function HttpLite.dechunk(s)
  local out, i = {}, 1
  while true do
    local lineEnd = s:find("\r\n", i, true)
    if not lineEnd then return nil, "bad chunk" end
    local size = tonumber((s:sub(i, lineEnd - 1):match("^%s*(%x+)")), 16)
    if not size then return nil, "bad chunk size" end
    if size == 0 then break end
    local start = lineEnd + 2
    out[#out + 1] = s:sub(start, start + size - 1)
    i = start + size + 2
    if i > #s + 1 then return nil, "truncated chunk" end
  end
  return table.concat(out)
end

-- is the raw buffer a complete response yet?  (Connection: close lets us
-- read to EOF as well, but this stops early on Content-Length / chunked end)
function HttpLite.complete(raw)
  local headEnd = raw:find("\r\n\r\n", 1, true)
  if not headEnd then return false end
  local head = raw:sub(1, headEnd):lower()
  local bodyLen = #raw - (headEnd + 3)
  local cl = tonumber(head:match("\ncontent%-length:%s*(%d+)"))
  if cl then return bodyLen >= cl end
  if head:find("\ntransfer%-encoding:[^\n]*chunked") then
    return raw:find("\r\n0\r\n\r\n", headEnd, true) ~= nil
        or raw:sub(headEnd + 4, headEnd + 8) == "0\r\n\r\n"
  end
  return false
end

function HttpLite.request(req)
  local socket = Util.socket
  if not socket then return nil, "no luasocket" end
  local u = HttpLite.parseUrl(req.url)
  if not u then return nil, "bad url " .. tostring(req.url) end
  if not Util.isIPv4(u.host) then return nil, "not an IPv4 address: " .. u.host end
  local timeout = req.timeout or 3
  local deadline = Util.time() + timeout
  local tcp = Util.tcp()
  tcp:settimeout(0)
  local ok, err = tcp:connect(u.host, u.port)
  if not ok and err ~= "timeout" and err ~= "Operation already in progress" then
    tcp:close()
    return nil, "connect: " .. tostring(err)
  end
  if not ok then
    while true do
      local _, writable = socket.select(nil, { tcp }, 0)
      if writable and #writable > 0 then break end
      if Util.time() > deadline then
        tcp:close()
        return nil, ("no answer from %s:%d"):format(u.host, u.port)
      end
      Util.yield()
    end
  end
  local body = req.body or ""
  local lines = {
    ("%s %s HTTP/1.1"):format(req.method or "GET", u.path),
    ("Host: %s:%d"):format(u.host, u.port),
    "Connection: close",
    "User-Agent: Gen2Recomped/online",
  }
  for k, v in pairs(req.headers or {}) do lines[#lines + 1] = k .. ": " .. v end
  if req.method == "POST" or #body > 0 then
    lines[#lines + 1] = "Content-Length: " .. #body
  end
  local out = table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
  local sent = 0
  while sent < #out do
    local n, serr, last = tcp:send(out, sent + 1)
    if n then
      sent = n
    elseif serr == "timeout" then
      sent = last or sent
      if Util.time() > deadline then tcp:close() return nil, "send timed out" end
      Util.yield()
    else
      tcp:close()
      return nil, "send: " .. tostring(serr)
    end
  end
  local buf = {}
  local total = 0
  local raw = ""
  while true do
    local data, rerr, partial = tcp:receive(8192)
    local chunk = data or partial
    if chunk and #chunk > 0 then
      buf[#buf + 1] = chunk
      total = total + #chunk
      if total > HttpLite.MAX_BODY then tcp:close() return nil, "response too large" end
      raw = table.concat(buf)
      if HttpLite.complete(raw) then break end
    end
    if rerr == "closed" then break end
    if rerr and rerr ~= "timeout" then
      tcp:close()
      return nil, "receive: " .. tostring(rerr)
    end
    if not data then
      if Util.time() > deadline then
        tcp:close()
        return nil, "response timed out"
      end
      Util.yield()
    end
  end
  tcp:close()
  return HttpLite.parseResponse(raw)
end

return HttpLite
