-- Message framing and inbound checks for the online transport.
--
-- Messages are JSON objects (src/link/Json.lua, the same encoding Net.lua
-- uses, so a v2 Net peer and a Transport peer read each other).  Before a
-- received packet is decoded it is size-capped and its nesting depth is
-- scanned without recursion; after decoding it must be an object with a
-- short string `type`, finite numbers, string/number keys, and a bounded
-- node count.  Anything else is dropped and reported, never thrown.
--
--   Wire.encode(msg, channel) -> data | nil, why
--   Wire.decode(data, channel, allowTypes) -> msg | nil, why
--
-- Channels: 0 reliable session, 1 unreliable-sequenced (world sync),
-- 2 reliable bulk.  Caps follow docs/online-design.md 2.11.

local Json = require("src.link.Json")

local Wire = {}

Wire.MAX_RELIABLE = 65536
Wire.MAX_UNRELIABLE = 512
Wire.MAX_DEPTH = 16     -- party -> mons -> mon -> extra (plainCopy caps extra at 8)
Wire.MAX_NODES = 20000
Wire.MAX_TYPE_LEN = 32

-- ENet flag per channel
Wire.FLAGS = { [0] = "reliable", [1] = "unreliable", [2] = "reliable" }

function Wire.capFor(channel)
  if channel == 1 then return Wire.MAX_UNRELIABLE end
  return Wire.MAX_RELIABLE
end

-- every type the v2 link code (LinkState, LinkBattle, Tournament, the relay)
-- sends or expects; a channel can opt into this as an allowlist
Wire.LINK_TYPES = {}
for _, t in ipairs({
  "hello", "records", "party", "pick", "confirm", "action", "event", "hash",
  "forfeit", "bye",
  -- relay / tournament control (pokeserver protocol)
  "host", "hosted", "join", "join_error", "paired", "peer_gone",
  "host_tournament", "join_tournament", "start_tournament", "tournament_result",
  "tournament_hosted", "tournament_host_error", "tournament_join_error",
  "tournament_roster", "bracket_update", "match_start", "match_start_spectate",
  "spectate", "tournament_bye", "tournament_over",
}) do Wire.LINK_TYPES[t] = true end

-- max bracket depth outside string literals; a pre-decode guard so a
-- 60 KB "[[[[..." can't recurse the decoder into the ground
function Wire.scanDepth(s)
  local depth, maxDepth = 0, 0
  local i, n = 1, #s
  local find, byte = string.find, string.byte
  while i <= n do
    local j = find(s, '[%[%]{}"]', i)
    if not j then break end
    local c = byte(s, j)
    if c == 34 then -- string: skip to the closing unescaped quote
      local k = j + 1
      while true do
        local q = find(s, '["\\]', k)
        if not q then return maxDepth, "unterminated string" end
        if byte(s, q) == 92 then
          k = q + 2
        else
          k = q + 1
          break
        end
      end
      i = k
    else
      if c == 91 or c == 123 then
        depth = depth + 1
        if depth > maxDepth then maxDepth = depth end
      else
        depth = depth - 1
      end
      i = j + 1
    end
  end
  return maxDepth
end

local function checkValue(v, depth, budget)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      return false, "non-finite number"
    end
    return true
  elseif t == "string" or t == "boolean" then
    return true
  elseif t == "table" then
    if depth > Wire.MAX_DEPTH then return false, "nested too deeply" end
    for k, val in pairs(v) do
      budget.n = budget.n + 1
      if budget.n > Wire.MAX_NODES then return false, "too many fields" end
      local kt = type(k)
      if kt ~= "string" and kt ~= "number" then return false, "bad key" end
      local ok, why = checkValue(val, depth + 1, budget)
      if not ok then return false, why end
    end
    return true
  end
  return false, "bad value type " .. t
end

function Wire.checkShape(msg, allowTypes)
  if type(msg) ~= "table" then return false, "not an object" end
  local ty = msg.type
  if type(ty) ~= "string" or #ty == 0 or #ty > Wire.MAX_TYPE_LEN
     or not ty:match("^[%w_%-%.]+$") then
    return false, "missing or bad type"
  end
  if allowTypes and not allowTypes[ty] and ty:sub(1, 1) ~= "_" then
    return false, "unknown type " .. ty
  end
  return checkValue(msg, 1, { n = 0 })
end

function Wire.encode(msg, channel)
  if type(msg) ~= "table" then return nil, "not an object" end
  local ok, data = pcall(Json.encode, msg)
  if not ok then return nil, "unencodable: " .. tostring(data) end
  if #data > Wire.capFor(channel or 0) then
    return nil, ("message too large (%d bytes)"):format(#data)
  end
  return data
end

function Wire.decode(data, channel, allowTypes)
  if type(data) ~= "string" then return nil, "not a string" end
  if #data > Wire.capFor(channel or 0) then
    return nil, ("oversize message (%d bytes)"):format(#data)
  end
  local depth, why = Wire.scanDepth(data)
  if why then return nil, why end
  if depth > Wire.MAX_DEPTH then return nil, "nested too deeply" end
  local msg, err = Json.decode(data)
  if msg == nil then return nil, "bad json: " .. tostring(err) end
  local ok, bad = Wire.checkShape(msg, allowTypes)
  if not ok then return nil, bad end
  return msg
end

return Wire
