-- Six-symbol short codes (the pokeserver room format), one namespace for
-- everything the hub hands out: relay rooms, tournaments and rendezvous
-- tickets.  Same alphabet as src/link/CodeEntry.lua (no 0/O/1/I/L), so a
-- code typed on the d-pad scrubber or the long-code entry reads back here.
--
--   local codes = Codes.new{ rand = fn() -> uint32, now = fn() -> seconds }
--   local code = codes:allocate(owner)      -- nil when the space is exhausted
--   codes:lookup(text) -> owner | nil, "expired" | nil
--   codes:release(code[, keepSeconds])      -- answers "expired" for a while
--   Codes.normalize(text) -> "ABC234" | nil

local Codes = {}
Codes.__index = Codes

Codes.CHARSET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
Codes.LENGTH = 6
Codes.GRAVE_SECONDS = 3600

function Codes.new(opts)
  opts = opts or {}
  return setmetatable({
    rand = opts.rand or function() return math.random(0, 2147483646) end,
    now = opts.now or os.time,
    active = {},     -- code -> owner
    grave = {},      -- code -> time it stops answering "expired"
    count = 0,
  }, Codes)
end

-- upper case, separators and spaces dropped; nil unless exactly six symbols
-- of the alphabet
function Codes.normalize(text)
  if type(text) ~= "string" then return nil end
  local s = text:upper():gsub("[%s%-_]", "")
  if #s ~= Codes.LENGTH then return nil end
  for i = 1, #s do
    if not Codes.CHARSET:find(s:sub(i, i), 1, true) then return nil end
  end
  return s
end

function Codes:make()
  local n = #Codes.CHARSET
  local out = {}
  for i = 1, Codes.LENGTH do
    local r = self.rand() % n
    out[i] = Codes.CHARSET:sub(r + 1, r + 1)
  end
  return table.concat(out)
end

function Codes:allocate(owner)
  local now = self.now()
  for _ = 1, 64 do
    local code = self:make()
    local graveUntil = self.grave[code]
    if graveUntil and graveUntil <= now then
      self.grave[code] = nil
      graveUntil = nil
    end
    if self.active[code] == nil and graveUntil == nil then
      self.active[code] = owner
      self.count = self.count + 1
      return code
    end
  end
  return nil
end

function Codes:lookup(text)
  local code = Codes.normalize(text)
  if not code then return nil, nil end
  local owner = self.active[code]
  if owner ~= nil then return owner end
  local graveUntil = self.grave[code]
  if graveUntil and graveUntil > self.now() then return nil, "expired" end
  return nil, nil
end

function Codes:release(code, keepSeconds)
  if code == nil or self.active[code] == nil then return end
  self.active[code] = nil
  self.count = self.count - 1
  self.grave[code] = self.now() + (keepSeconds or Codes.GRAVE_SECONDS)
end

-- forget graves that no longer answer
function Codes:sweep()
  local now = self.now()
  for code, untilAt in pairs(self.grave) do
    if untilAt <= now then self.grave[code] = nil end
  end
end

return Codes
