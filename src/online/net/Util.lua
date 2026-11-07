-- Shared helpers for the online transport stack (src/online/net/*):
-- a clock, address helpers and a tiny coroutine "job" runner.
--
-- Every slow network operation in this directory (HTTP to a router, UDP
-- request/response with retries, DNS) is written as straight-line code that
-- calls Util.yield()/Util.sleep() while it waits.  Run inside Util.job(fn)
-- those calls yield, and the caller resumes the job once per frame with
-- job:update(), so a frame never blocks on the network.  Called outside a
-- job (headless tools, the exit-time unmap) the same calls sleep for a
-- moment instead, so the code still terminates under its own deadlines.

local Util = {}

local hasSocket, socket = pcall(require, "socket")
if not hasSocket then socket = nil end
Util.socket = socket

-- IPv4 sockets created eagerly.  LuaSocket 3.0-rc1 (LOVE 11) makes a plain
-- socket.udp() lazily: setoption() before the first bind fails, sendto()
-- from an unbound one fails with "refused", and binding "*" picks an IPv6
-- wildcard that can't reach IPv4 hosts.  udp4/tcp4 avoid all three.
function Util.udp()
  return (socket.udp4 or socket.udp)()
end

function Util.tcp()
  return (socket.tcp4 or socket.tcp)()
end

function Util.now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  if socket and socket.gettime then return socket.gettime() end
  return os.clock()
end

-- tests can replace the clock (LoopNet drives a fake one)
Util.clock = Util.now
function Util.time() return Util.clock() end

---------------------------------------------------------------- jobs

local current = {} -- stack of coroutines started by Util.job

local function inJob()
  local co = coroutine.running()
  return co ~= nil and current[#current] == co
end
Util.inJob = inJob

-- give up control: inside a job, yield to the frame; outside, nap briefly
function Util.yield()
  if inJob() then
    coroutine.yield()
  elseif socket and socket.sleep then
    socket.sleep(0.002)
  end
end

function Util.sleep(seconds)
  local deadline = Util.time() + (seconds or 0)
  repeat Util.yield() until Util.time() >= deadline
end

local Job = {}
Job.__index = Job

-- fn(job, ...) runs as a coroutine.  Its return values land in job.result
-- (first) and job.results (all); an error lands in job.reason with
-- state "failed".  fn may also set job.state itself before returning.
function Util.job(fn, ...)
  local args = { n = select("#", ...), ... }
  local job = setmetatable({ state = "running", log = {} }, Job)
  job.co = coroutine.create(function()
    return fn(job, unpack(args, 1, args.n))
  end)
  return job
end

function Job:update()
  if self.state ~= "running" or not self.co then return self.state end
  current[#current + 1] = self.co
  local function pack(...) return { n = select("#", ...), ... } end
  local res = pack(coroutine.resume(self.co))
  current[#current] = nil
  if not res[1] then
    self.state = "failed"
    self.reason = self.reason or tostring(res[2])
    self.co = nil
  elseif coroutine.status(self.co) == "dead" then
    self.co = nil
    -- keep nils: `return nil, why` must reach job.results[2]
    local out = { n = math.max(0, res.n - 1) }
    for i = 2, res.n do out[i - 1] = res[i] end
    self.results = out
    self.result = out[1]
    if self.state == "running" then
      if out[1] == nil and out[2] ~= nil then
        self.state = "failed"
        self.reason = self.reason or tostring(out[2])
      else
        self.state = "done"
      end
    end
  end
  return self.state
end

function Job:done() return self.state ~= "running" end

function Job:cancel(reason)
  if self.state == "running" then
    self.state = "failed"
    self.reason = reason or "cancelled"
  end
  self.co = nil
end

-- drive a job to completion right here (tools, exit-time cleanup), with a
-- hard wall-clock budget so a dead router can't hang the quit
function Util.runSync(job, budget, tick)
  local deadline = Util.now() + (budget or 5)
  while job.state == "running" do
    if tick then tick() end
    job:update()
    if Util.now() > deadline then
      job:cancel("timed out")
      break
    end
    if job.state == "running" and socket and socket.sleep then
      socket.sleep(0.002)
    end
  end
  return job
end

---------------------------------------------------------------- addresses

function Util.parseIPv4(s)
  if type(s) ~= "string" then return nil end
  local a, b, c, d = s:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not (a and b and c and d) then return nil end
  if a > 255 or b > 255 or c > 255 or d > 255 then return nil end
  return a, b, c, d
end

function Util.isIPv4(s) return Util.parseIPv4(s) ~= nil end

-- "host:port" -> host, port (port defaults to `defaultPort`)
function Util.splitEndpoint(s, defaultPort)
  if type(s) ~= "string" then return nil end
  local h, p = s:match("^(.-):(%d+)$")
  if h then return h, tonumber(p) end
  return s, defaultPort
end

function Util.endpoint(host, port)
  return ("%s:%d"):format(host, port)
end

-- RFC 1918 / loopback / link-local: a LAN-side address
function Util.isPrivate(ip)
  local a, b = Util.parseIPv4(ip)
  if not a then return false end
  return a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31)
      or (a == 192 and b == 168) or (a == 169 and b == 254)
end

-- RFC 6598 shared address space: the router's "public" address is itself
-- behind the ISP's NAT, so a port mapping on the home router can't help
function Util.isCgnat(ip)
  local a, b = Util.parseIPv4(ip)
  return a == 100 and b >= 64 and b <= 127
end

function Util.isPublic(ip)
  local a = Util.parseIPv4(ip)
  if not a then return false end
  return not (Util.isPrivate(ip) or Util.isCgnat(ip) or a == 0 or a >= 224)
end

-- best-effort LAN IPv4 (no packet is sent: connecting a UDP socket only
-- picks the outbound interface).  Same trick as Net.lanIP.
function Util.lanIP(towards)
  if not socket then return nil end
  local ok, ip = pcall(function()
    local udp = Util.udp()
    udp:setpeername(towards or "192.0.2.1", 9) -- TEST-NET-1, never routed
    local addr = udp:getsockname()
    udp:close()
    return addr
  end)
  if ok and ip and ip ~= "0.0.0.0" then return ip end
  return nil
end

-- 32-bit big-endian helpers (LuaJIT: no string.pack)
function Util.u16(n)
  n = math.floor(n) % 65536
  return string.char(math.floor(n / 256), n % 256)
end

function Util.u32(n)
  n = math.floor(n) % 4294967296
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
                     math.floor(n / 256) % 256, n % 256)
end

function Util.rd16(s, i)
  local a, b = s:byte(i, i + 1)
  if not b then return nil end
  return a * 256 + b
end

function Util.rd32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

function Util.ipBytes(ip)
  local a, b, c, d = Util.parseIPv4(ip)
  if not a then return nil end
  return string.char(a, b, c, d)
end

function Util.ipFromBytes(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  if not d then return nil end
  return ("%d.%d.%d.%d"):format(a, b, c, d)
end

-- Session secrets need their OWN generator: Lua's math.random is unseeded
-- in LOVE (two games would draw the same "random" nonce) and reseeding it
-- would disturb game code and tests that rely on its sequence.  xorshift32
-- seeded from the high-resolution clock, CPU time and a heap address.
local bit = require("bit")
local rngState = nil

local function seedRng()
  local t = (socket and socket.gettime and socket.gettime()) or os.time()
  local addr = tonumber(tostring({}):match("0x(%x+)") or "0", 16) or 0
  local s = math.floor((t % 1) * 4294967296) + math.floor(t) * 2654435761
            + math.floor(os.clock() * 1e6) * 40503 + addr
  rngState = bit.tobit(s % 4294967296)
  if rngState == 0 then rngState = 0x2545F491 end
  for _ = 1, 8 do Util.rand32() end
end

function Util.rand32()
  if not rngState then seedRng() end
  local x = rngState
  x = bit.bxor(x, bit.lshift(x, 13))
  x = bit.bxor(x, bit.rshift(x, 17))
  x = bit.bxor(x, bit.lshift(x, 5))
  rngState = x
  return x % 4294967296
end

-- random 20-bit session nonce (never 0: 0 means "no nonce" on the wire)
function Util.newNonce()
  local n = 0
  while n == 0 do n = Util.rand32() % 1048576 end
  return n
end

function Util.randomBytes(n)
  local t = {}
  for i = 1, n do t[i] = string.char(Util.rand32() % 256) end
  return table.concat(t)
end

return Util
