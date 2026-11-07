-- The hub's log: stdout plus one file per day under <dataDir>/logs.
--
--   local log = Log.new{ dir = "hub-data/logs", level = "info", keepDays = 14,
--                        addresses = false, stdout = true }
--   log:info("relay: room %s paired", code)   -- also :warn :error :debug
--   log:addr("203.0.113.7") -> "203.0.113.x" unless addresses = true
--
-- Player IP addresses are personal data.  By default the log keeps only the
-- first three octets, enough to see abuse from one network, not enough to
-- identify a home.  An operator who needs full addresses (to ban one)
-- turns `log.addresses` on and says so in their community's rules.

local Log = {}
Log.__index = Log

Log.LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }

function Log.new(opts)
  opts = opts or {}
  local self = setmetatable({
    dir = opts.dir,
    level = Log.LEVELS[opts.level or "info"] or 2,
    keepDays = opts.keepDays or 14,
    addresses = opts.addresses == true,
    stdout = opts.stdout ~= false,
    file = nil, day = nil,
    lines = {},          -- the last few lines, for the admin "log" command
    sink = opts.sink,    -- tests: fn(line)
  }, Log)
  if self.dir and opts.file ~= false then
    local Files = require("src.online.hub.Files")
    Files.mkdirs(self.dir)
    self:prune()
  else
    self.dir = nil
  end
  return self
end

function Log:addr(ip)
  if ip == nil then return "?" end
  ip = tostring(ip)
  if self.addresses then return ip end
  local a, b, c = ip:match("^(%d+)%.(%d+)%.(%d+)%.%d+")
  if a then
    local port = ip:match(":(%d+)$")
    return ("%s.%s.%s.x%s"):format(a, b, c, port and (":" .. port) or "")
  end
  return "?"
end

function Log:open()
  local day = os.date("%Y-%m-%d")
  if self.file and self.day == day then return self.file end
  if self.file then pcall(self.file.close, self.file) end
  self.file, self.day = nil, day
  if self.dir then
    self.file = io.open(("%s/hub-%s.log"):format(self.dir, day), "ab")
    if self.file then self.file:setvbuf("line") end
  end
  return self.file
end

-- delete day files older than keepDays (names carry the date)
function Log:prune()
  if not self.dir or self.keepDays <= 0 then return end
  local now = os.time()
  for back = self.keepDays + 1, self.keepDays + 60 do
    os.remove(("%s/hub-%s.log"):format(self.dir, os.date("%Y-%m-%d", now - back * 86400)))
  end
end

function Log:write(levelName, fmt, ...)
  local lv = Log.LEVELS[levelName] or 2
  if lv < self.level then return end
  local ok, text = pcall(string.format, fmt, ...)
  if not ok then text = tostring(fmt) end
  local line = ("%s [%s] %s"):format(os.date("%Y-%m-%d %H:%M:%S"), levelName, text)
  local keep = self.lines
  keep[#keep + 1] = line
  if #keep > 200 then table.remove(keep, 1) end
  if self.sink then self.sink(line) end
  if self.stdout then
    io.stdout:write(line, "\n")
    io.stdout:flush()
  end
  local f = self:open()
  if f then f:write(line, "\n") end
end

function Log:debug(fmt, ...) self:write("debug", fmt, ...) end
function Log:info(fmt, ...) self:write("info", fmt, ...) end
function Log:warn(fmt, ...) self:write("warn", fmt, ...) end
function Log:error(fmt, ...) self:write("error", fmt, ...) end

function Log:close()
  if self.file then pcall(self.file.close, self.file) end
  self.file = nil
end

return Log
