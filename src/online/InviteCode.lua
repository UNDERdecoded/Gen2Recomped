-- INVITE CODES (docs/online-design.md 2.2, workstream WS2).
--
-- Two kinds of code, both over the same 31-symbol alphabet CodeEntry already
-- uses for relay rooms (23456789ABCDEFGHJKMNPQRSTUVWXYZ: no 0/O/1/I/L, so a
-- code read aloud or copied by hand never has to be checked twice).
--
-- * DIRECT codes (serverless).  The host's address(es), its port, a 20-bit
--   session secret (the nonce) and a version, packed into one number and
--   written in base 31 with ONE check symbol on the end.  No server is needed
--   to read one: the joiner gets everything it needs to dial out of the code.
--
-- * SHORT codes: the six-symbol room codes a hub or the pokeserver relay hands
--   out.  They carry nothing but the room name, so they are passed through.
--
-- THE PACKING.  The doc lays the direct code out as bit fields
-- (ver:3 kind:2 flags:4 [public:32] [lan:16|32] [port:16] nonce:20 check:5).
-- The same fields are packed here as a MIXED-RADIX number rather than a bit
-- string, which is what lets the doc's own lengths come out.  Base 31 is not
-- a power of two and `kind` has 3 states, not 4, so whole bit fields waste
-- room: bit-packed, a LAN-only code is 50 bits = 11 symbols, where the mixed
-- radix fits it in 10.  The header is
--
--   version (8) x kind (3) x hasPublic (2) x lanMode (4) x customPort (2)
--     = 384 states                                   (~8.6 bits)
--
-- and the body is public (2^32), lan (2^16 / 2^24 / 2^32), port (2^16) and
-- nonce (2^20), each present only when the header says so.  The header is the
-- LEAST significant digit group, so a decoder peels it off first and then
-- knows exactly which fields follow and how long the code must be.
--
--   public + 192.168 LAN, default port   384 * 2^68  -> 16 symbols + check = 17
--   192.168 LAN only, default port       384 * 2^36  ->  9 symbols + check = 10
--
-- (384 * 2^36 = 2.6388e13 against 31^9 = 2.6439e13: it fits, just.)
--
-- THE CHECK SYMBOL is a weighted sum mod 31 rather than a CRC over the bits.
-- 31 is prime, so with weights 1..n+1 every single-symbol substitution changes
-- the sum by (delta * weight) which is never 0 mod 31, and every swap of two
-- neighbours changes it by (a - b) * 1, also never 0.  A CRC over the packed
-- bits cannot promise either, because one changed symbol moves many bits.
-- n + 1 stays under 31 for every shape (the longest is 23 symbols).
--
-- LAN ADDRESSES.  lanMode 1 ("short") carries only the low 16 bits of a
-- 192.168/16 or 172.16/12 address; the joiner, who is on the same network,
-- rebuilds the top two octets from ITS OWN LAN address (decode's myLanIp).
-- A joiner whose own address is not in either range gets 192.168, and the
-- result says so (lanPrefixGuessed).  lanMode 2 ("ten") carries the low 24 bits
-- of a 10/8 address; lanMode 3 the whole address.
--
-- THE OUTSIDE PORT (format version 2).  A router may map a different outside
-- port (UPnP "port taken", NAT-PMP's choice).  Version 2 adds one 16-bit field,
-- pubPort, on any code with a public address.  It is only written when needed:
-- every other code stays version 1, so older builds still read them and an
-- older build shown a version 2 code says "update to join" rather than dialling
-- the wrong port.
--
-- Pure Lua (LuaJIT): no love, no bit library, no string.unpack, no `//`.
-- Numbers above 2^53 never exist as numbers -- the code is built as a little
-- base-31 digit array.

local CodeEntry = require("src.link.CodeEntry")

local InviteCode = {}

InviteCode.CHARSET = CodeEntry.CHARSET
InviteCode.BASE = #InviteCode.CHARSET -- 31
InviteCode.VERSION = 2          -- decode accepts <= this
InviteCode.PLAIN_VERSION = 1    -- written unless a code needs the outside port
InviteCode.MAX_VERSION = 7      -- the header has room for 0..7
InviteCode.DEFAULT_PORT = 7777  -- Net.defaultPort(); kept literal so this stays love-free
InviteCode.SHORT_LENGTH = CodeEntry.LENGTH -- 6
InviteCode.NONCE_BITS = 20
InviteCode.NONCE_MAX = 1048575  -- 2^20 - 1
InviteCode.GROUP = 4            -- symbols per displayed group

-- kind ids are the doc's: 0 link session, 1 world, 2 hub-assisted
InviteCode.KINDS = { [0] = "session", [1] = "world", [2] = "hub" }
local KIND_ID = { session = 0, world = 1, hub = 2 }

-- lanMode ids
local LAN_NONE, LAN_SHORT, LAN_TEN, LAN_FULL = 0, 1, 2, 3
InviteCode.LAN_MODES = { [0] = "none", [1] = "short", [2] = "ten", [3] = "full" }

local BASE = InviteCode.BASE
local CHARSET = InviteCode.CHARSET
local SYMBOL_VALUE = {}
for i = 1, BASE do SYMBOL_VALUE[CHARSET:sub(i, i)] = i - 1 end

-- symbols people type for one that is not in the alphabet, named in the error
local LOOKALIKE = { ["0"] = "0 (zero)", O = "O", ["1"] = "1 (one)", I = "I", L = "L" }

-- ------------------------------------------------------------- big numbers
-- little-endian arrays of base-31 digits; every intermediate stays < 2^31

local function bnNew(v)
  local n = {}
  v = v or 0
  while v > 0 do
    n[#n + 1] = v % BASE
    v = math.floor(v / BASE)
  end
  return n
end

-- n = n * m + a   (m, a < 2^21)
local function bnMulAdd(n, m, a)
  local carry = a or 0
  for i = 1, #n do
    local v = n[i] * m + carry
    n[i] = v % BASE
    carry = math.floor(v / BASE)
  end
  while carry > 0 do
    n[#n + 1] = carry % BASE
    carry = math.floor(carry / BASE)
  end
  return n
end

-- n = floor(n / m), returns n % m   (m < 2^21)
local function bnDivMod(n, m)
  local r = 0
  for i = #n, 1, -1 do
    local v = r * BASE + n[i]
    n[i] = math.floor(v / m)
    r = v % m
  end
  while #n > 0 and n[#n] == 0 do n[#n] = nil end
  return r
end

local function bnIsZero(n)
  for i = 1, #n do if n[i] ~= 0 then return false end end
  return true
end

-- number of base-31 digits needed for every value below `product`
local function digitsBelow(radices)
  local p = bnNew(1)
  for _, r in ipairs(radices) do bnMulAdd(p, r, 0) end
  -- p - 1
  local i = 1
  while p[i] == 0 do p[i] = BASE - 1; i = i + 1 end
  p[i] = p[i] - 1
  while #p > 0 and p[#p] == 0 do p[#p] = nil end
  return math.max(1, #p)
end

-- ------------------------------------------------------------- addresses

local function parseIPv4(ip)
  if type(ip) ~= "string" then return nil end
  local a, b, c, d = ip:match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
  if not a then return nil end
  local o = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
  for k = 1, 4 do
    if o[k] > 255 or #(({ a, b, c, d })[k]) > 3 then return nil end
  end
  return o
end
InviteCode.parseIPv4 = parseIPv4

local function ipString(o)
  return ("%d.%d.%d.%d"):format(o[1], o[2], o[3], o[4])
end

-- the high and low 16-bit halves of an address
local function ipHalves(o) return o[1] * 256 + o[2], o[3] * 256 + o[4] end

local function isShortLan(o)
  return (o[1] == 192 and o[2] == 168) or (o[1] == 172 and o[2] >= 16 and o[2] <= 31)
end
InviteCode.isShortLan = isShortLan

-- which lanMode an address is written in
local function lanModeFor(o, forceFull)
  if forceFull then return LAN_FULL end
  if isShortLan(o) then return LAN_SHORT end
  if o[1] == 10 then return LAN_TEN end
  return LAN_FULL
end

-- ------------------------------------------------------------- shapes

-- The body fields of a shape, in DECODE order (the order they come off the
-- number after the header).  Each entry is { name, radix }.
local function bodyFields(hasPublic, lanMode, customPort, hasPubPort)
  local f = {}
  if hasPublic then
    f[#f + 1] = { "pubHi", 65536 }
    f[#f + 1] = { "pubLo", 65536 }
  end
  if lanMode == LAN_SHORT then
    f[#f + 1] = { "lanLo", 65536 }
  elseif lanMode == LAN_TEN then
    f[#f + 1] = { "lanMid", 256 }
    f[#f + 1] = { "lanLo", 65536 }
  elseif lanMode == LAN_FULL then
    f[#f + 1] = { "lanHi", 65536 }
    f[#f + 1] = { "lanLo", 65536 }
  end
  if customPort then f[#f + 1] = { "port", 65536 } end
  if hasPubPort then f[#f + 1] = { "pubPort", 65536 } end
  f[#f + 1] = { "nonce", InviteCode.NONCE_MAX + 1 }
  return f
end

local HEADER_RADIX = 8 * 3 * 2 * 4 * 2 -- 384

local function packHeader(ver, kind, hasPublic, lanMode, customPort)
  local h = ver
  h = h * 3 + kind
  h = h * 2 + (hasPublic and 1 or 0)
  h = h * 4 + lanMode
  h = h * 2 + (customPort and 1 or 0)
  return h
end

local function unpackHeader(h)
  local customPort = h % 2 == 1; h = math.floor(h / 2)
  local lanMode = h % 4; h = math.floor(h / 4)
  local hasPublic = h % 2 == 1; h = math.floor(h / 2)
  local kind = h % 3; h = math.floor(h / 3)
  return h, kind, hasPublic, lanMode, customPort
end

-- payload symbol count (without the check symbol) of a shape
local payloadCache = {}
local function payloadLength(hasPublic, lanMode, customPort, hasPubPort)
  local key = (hasPubPort and 1000 or 0) + (hasPublic and 1 or 0) * 100 + lanMode * 10 + (customPort and 1 or 0)
  local n = payloadCache[key]
  if not n then
    local radices = { HEADER_RADIX }
    for _, f in ipairs(bodyFields(hasPublic, lanMode, customPort, hasPubPort)) do radices[#radices + 1] = f[2] end
    n = digitsBelow(radices)
    payloadCache[key] = n
  end
  return n
end

-- every full length (payload + check) a direct code can have, sorted, and
-- as a set
local LENGTHS, LENGTH_SET = {}, {}
for _, pub in ipairs({ false, true }) do
  for lan = 0, 3 do
    for _, cp in ipairs({ false, true }) do
      if pub or lan ~= LAN_NONE then
        for _, pp in ipairs({ false, pub }) do
          local n = payloadLength(pub, lan, cp, pp) + 1
          if not LENGTH_SET[n] then LENGTH_SET[n] = true; LENGTHS[#LENGTHS + 1] = n end
        end
      end
    end
  end
end
table.sort(LENGTHS)
InviteCode.LENGTHS = LENGTHS
InviteCode.MIN_LENGTH = LENGTHS[1]
InviteCode.MAX_LENGTH = LENGTHS[#LENGTHS]

function InviteCode.isValidLength(n)
  return n == InviteCode.SHORT_LENGTH or LENGTH_SET[n] == true
end

-- expected full length (with check symbol) for an encode spec's shape
function InviteCode.lengthFor(hasPublic, lanMode, customPort)
  if type(lanMode) == "string" then
    for id, name in pairs(InviteCode.LAN_MODES) do if name == lanMode then lanMode = id end end
  end
  return payloadLength(hasPublic and true or false, lanMode or LAN_NONE, customPort and true or false) + 1
end

-- ------------------------------------------------------------- check symbol

-- digits: payload values, most significant first.  Returns the check value c
-- with  sum(i * d_i) + (n + 1) * c == 0  (mod 31).
local function checkValue(digits)
  local n = #digits
  local s = 0
  for i = 1, n do s = (s + i * digits[i]) % BASE end
  local w = (n + 1) % BASE
  -- inverse of w mod 31 (w is 1..30; brute force is 30 steps)
  local inv = 1
  for k = 1, BASE - 1 do
    if (w * k) % BASE == 1 then inv = k; break end
  end
  return ((BASE - s) % BASE * inv) % BASE
end
InviteCode._checkValue = checkValue

-- ------------------------------------------------------------- text helpers

-- "ABCDEFGHJ" -> "ABCD-EFGH-J"
function InviteCode.group(raw, size, sep)
  size = size or InviteCode.GROUP
  sep = sep or "-"
  local out = {}
  for i = 1, #raw, size do out[#out + 1] = raw:sub(i, i + size - 1) end
  return table.concat(out, sep)
end

-- Uppercase, drop separators (space, -, _, ., tab, newline).  Returns the
-- bare symbol string, or nil, message, "badchar", position when a character
-- is not in the alphabet.
function InviteCode.normalize(text)
  if type(text) ~= "string" then return nil, "No code entered.", "empty" end
  local out = {}
  local pos = 0
  for ch in text:upper():gmatch(".") do
    if not ch:match("[%s%-_%.]") then
      pos = pos + 1
      if SYMBOL_VALUE[ch] then
        out[#out + 1] = ch
      else
        local named = LOOKALIKE[ch]
        if named then
          return nil, ("Character %d is %s: codes have no 0, O, 1, I or L."):format(pos, named),
            "badchar", pos
        end
        return nil, ("Character %d (%s) is not part of a code."):format(pos, ch), "badchar", pos
      end
    end
  end
  if #out == 0 then return nil, "No code entered.", "empty" end
  return table.concat(out)
end

function InviteCode.isSymbol(ch)
  return type(ch) == "string" and SYMBOL_VALUE[ch:upper()] ~= nil
end

-- ------------------------------------------------------------- encode

local function nonceOf(v)
  v = tonumber(v)
  if not v or v ~= math.floor(v) or v < 0 or v > InviteCode.NONCE_MAX then return nil end
  return v
end

-- A fresh session secret.  `random` is math.random-shaped (defaults to
-- love.math.random when LÖVE is loaded, else math.random).
function InviteCode.newNonce(random)
  random = random or (love and love.math and love.math.random) or math.random
  return random(0, InviteCode.NONCE_MAX)
end

--- InviteCode.encode{ kind=, public=, lan=, port=, nonce=, hub=, version=, lanFull= }
--   kind    "session" | "world" | "hub" | 0 | 1 | 2   (default "session")
--   public  "a.b.c.d"  the host's public IPv4 (router, STUN or typed)
--   lan     "a.b.c.d"  the host's LAN IPv4
--   port    UDP port, default 7777 (not written when it is the default)
--   nonce   0 .. 2^20-1, the session secret (or the hub room ticket)
--   hub     { ip=, port= } for kind "hub": the hub's address (written in the
--           public slot) and its port; `ticket` may stand in for nonce
--   lanFull write the LAN address whole even when a short form exists
--   publicPort  the router's outside port (Connector's inviteFields): the
--           code's port when there is no LAN address, else a version 2 code
--           with both.  hub.publicPort is the same for a hub code, and a hub
--           code's `lan` is the hub's LAN address beside its public one (a
--           friend on the same Wi-Fi does not depend on router hairpin)
--   room    a six-symbol relay room: with kind "room"/"short", or with no
--           address at all, encode returns the room code itself
-- Accepts Connector Host:inviteFields() as is.
-- Returns "XXXX-XXXX-..." , rawSymbols [, warning]  or  nil, message
function InviteCode.encode(spec)
  if type(spec) ~= "table" then return nil, "Nothing to encode." end
  if spec.kind == "room" or spec.kind == "short"
     or (spec.room and not spec.public and not spec.lan and not spec.hub) then
    local raw, why = InviteCode.normalize(spec.room)
    if not raw or #raw ~= InviteCode.SHORT_LENGTH then return nil, why or "A room code is six characters." end
    return raw, raw
  end
  local kind = spec.kind or "session"
  if type(kind) == "string" then kind = KIND_ID[kind] end
  if type(kind) ~= "number" or not InviteCode.KINDS[kind] then return nil, "Unknown code kind." end
  local version = spec.version or InviteCode.PLAIN_VERSION
  if version < 0 or version > InviteCode.MAX_VERSION or version ~= math.floor(version) then
    return nil, "Bad code version."
  end
  local public, port = spec.public, spec.port
  local nonce = spec.nonce
  local warning
  local publicPort = spec.publicPort
  if kind == KIND_ID.hub then
    local hub = spec.hub or {}
    public = hub.ip or hub.host or hub.public or public
    port = hub.port or port
    publicPort = hub.publicPort or publicPort
    if hub.ticket ~= nil then nonce = hub.ticket elseif spec.ticket ~= nil then nonce = spec.ticket end
  end
  -- a router that mapped a different outside port: with no LAN address the
  -- code's one port is the outside one; with one, version 2 carries both
  local noLan = spec.lan == nil or spec.lan == false or spec.lan == ""
  publicPort = tonumber(publicPort)
  if publicPort and public and publicPort ~= tonumber(port or InviteCode.DEFAULT_PORT) then
    if noLan then
      port, publicPort = publicPort, nil
    else
      if publicPort ~= math.floor(publicPort) or publicPort < 1 or publicPort > 65535 then
        return nil, "Port must be 1-65535."
      end
      if version < 2 then version = 2 end
    end
  else
    publicPort = nil
  end
  port = tonumber(port or InviteCode.DEFAULT_PORT)
  if not port or port ~= math.floor(port) or port < 1 or port > 65535 then
    return nil, "Port must be 1-65535."
  end
  nonce = nonceOf(nonce)
  if not nonce then return nil, "The session secret must be 0-1048575." end

  local pub, lan
  if public ~= nil and public ~= false and public ~= "" then
    pub = parseIPv4(public)
    if not pub then return nil, ("Not an IPv4 address: %s"):format(tostring(public)) end
  end
  if spec.lan ~= nil and spec.lan ~= false and spec.lan ~= "" then
    lan = parseIPv4(spec.lan)
    if not lan then return nil, ("Not an IPv4 address: %s"):format(tostring(spec.lan)) end
  end
  if not pub and not lan then return nil, "A code needs a LAN or an internet address." end

  local hasPublic = pub ~= nil
  local lanMode = lan and lanModeFor(lan, spec.lanFull) or LAN_NONE
  local customPort = port ~= InviteCode.DEFAULT_PORT

  local hasPubPort = version >= 2 and hasPublic
  local values = { nonce = nonce, port = port, pubPort = publicPort or port }
  if pub then values.pubHi, values.pubLo = ipHalves(pub) end
  if lan then
    local hi, lo = ipHalves(lan)
    values.lanHi, values.lanLo = hi, lo
    values.lanMid = lan[2]
  end

  -- Horner, most significant first: the body in reverse decode order, then
  -- the header as the lowest digit group
  local fields = bodyFields(hasPublic, lanMode, customPort, hasPubPort)
  local n = bnNew(0)
  for i = #fields, 1, -1 do
    local f = fields[i]
    bnMulAdd(n, f[2], values[f[1]])
  end
  bnMulAdd(n, HEADER_RADIX, packHeader(version, kind, hasPublic, lanMode, customPort))

  local len = payloadLength(hasPublic, lanMode, customPort, hasPubPort)
  local digits = {}
  for i = 1, len do digits[i] = n[len - i + 1] or 0 end -- most significant first
  local c = checkValue(digits)
  local out = {}
  for i = 1, len do out[i] = CHARSET:sub(digits[i] + 1, digits[i] + 1) end
  out[len + 1] = CHARSET:sub(c + 1, c + 1)
  local raw = table.concat(out)
  return InviteCode.group(raw), raw, warning
end

-- ------------------------------------------------------------- decode

local function lanEndpointPrefix(myLanIp)
  local mine = parseIPv4(myLanIp)
  if mine and isShortLan(mine) then return mine[1], mine[2], false end
  return 192, 168, true
end

-- Build the endpoint list a Connector dials, LAN first (cheapest path).
local function endpointsOf(invite)
  local list = {}
  if invite.kind == "hub" then
    if invite.lan then list[#list + 1] = { ip = invite.lan, port = invite.port, path = "hub-lan" } end
    if invite.public then
      list[#list + 1] = { ip = invite.public, port = invite.publicPort or invite.port, path = "hub" }
    end
    return list
  end
  if invite.lan then list[#list + 1] = { ip = invite.lan, port = invite.port, path = "lan" } end
  if invite.public then
    list[#list + 1] = { ip = invite.public, port = invite.publicPort or invite.port, path = "public" }
  end
  return list
end

--- InviteCode.decode(text, myLanIp) -> invite  |  nil, message, reason
--
-- invite (the table WS1's Connector.join consumes):
--   type     "direct" | "short"
--   kind     "session" | "world" | "hub"  (direct)   "short" (short)
--   kindId   0 | 1 | 2                      (direct)
--   version  format version                (direct)
--   public   "a.b.c.d" or nil              host's public IPv4 (hub: the hub's)
--   lan      "a.b.c.d" or nil              host's LAN IPv4, prefix rebuilt
--   lanMode  "short" | "ten" | "full" | nil
--   lanPrefixGuessed  true when a short LAN address got 192.168 because the
--            joiner's own address was not in 192.168/16 or 172.16/12
--   port     UDP port (7777 unless the code says otherwise)
--   publicPort  the router's outside port, when it differs (version 2 codes)
--   nonce    0..2^20-1 session secret, sent back in hello.nonce
--   ticket   = nonce, kind "hub" only (the hub room ticket)
--   hub      { ip=, port=, lan=, lanPort= }, kind "hub" only (lan: the hub's LAN
--            address, when the code carries a public one too)
--   room     six-symbol room code, type "short" only
--   endpoints { { ip=, port=, path="lan"|"public"|"hub-lan"|"hub" }, ... }
--            in the order to try them (LAN first); empty for short codes
--   display  canonical display form "XXXX-XXXX-..."
--   raw      canonical symbols with no separators
--   code     SHORT codes only (= room).  Deliberately absent on a direct
--            code: Connector's relay rung reads `room or code` as a relay
--            room name, and a direct code must never be sent to a relay
--            (it holds the host's address).
--
-- reason is one of "empty", "badchar", "length", "checksum", "version",
-- "shape", for callers that branch on it; message is for the player.
function InviteCode.decode(text, myLanIp)
  local raw, why, reason, pos = InviteCode.normalize(text)
  if not raw then return nil, why, reason, pos end
  local n = #raw
  if n == InviteCode.SHORT_LENGTH then
    return {
      type = "short", kind = "short", room = raw, code = raw, display = raw, raw = raw, endpoints = {},
    }
  end
  if not LENGTH_SET[n] then
    if n < InviteCode.MIN_LENGTH then
      return nil, ("Too short: %d characters. Codes are %d (short) or %d-%d long.")
        :format(n, InviteCode.SHORT_LENGTH, InviteCode.MIN_LENGTH, InviteCode.MAX_LENGTH), "length"
    end
    return nil, ("%d characters is not a code length. A character may be missing or doubled.")
      :format(n), "length"
  end
  local digits = {}
  for i = 1, n do digits[i] = SYMBOL_VALUE[raw:sub(i, i)] end
  local check = digits[n]
  digits[n] = nil
  if checkValue(digits) ~= check then
    return nil, "That code has a typo. Check each character.", "checksum"
  end
  local num = {}
  for i = 1, #digits do num[i] = digits[#digits - i + 1] end -- little-endian
  local version, kind, hasPublic, lanMode, customPort = unpackHeader(bnDivMod(num, HEADER_RADIX))
  if version > InviteCode.VERSION then
    return nil, "This code was made by a newer version of the game. Update to join.", "version"
  end
  local hasPubPort = version >= 2 and hasPublic
  if (not hasPublic and lanMode == LAN_NONE)
     or payloadLength(hasPublic, lanMode, customPort, hasPubPort) ~= #digits then
    return nil, "That code is not valid (it may have more than one typo).", "shape"
  end
  local v = {}
  for _, f in ipairs(bodyFields(hasPublic, lanMode, customPort, hasPubPort)) do v[f[1]] = bnDivMod(num, f[2]) end
  if not bnIsZero(num) then
    return nil, "That code is not valid (it may have more than one typo).", "shape"
  end

  local invite = {
    type = "direct",
    version = version,
    kindId = kind,
    kind = InviteCode.KINDS[kind],
    port = customPort and v.port or InviteCode.DEFAULT_PORT,
    nonce = v.nonce,
    lanMode = lanMode ~= LAN_NONE and InviteCode.LAN_MODES[lanMode] or nil,
    raw = raw,
    display = InviteCode.group(raw),
  }
  if (customPort and v.port < 1) or (hasPubPort and v.pubPort < 1) then
    return nil, "That code is not valid (port 0).", "shape"
  end
  if hasPubPort and v.pubPort ~= invite.port then invite.publicPort = v.pubPort end
  if hasPublic then
    invite.public = ipString({ math.floor(v.pubHi / 256), v.pubHi % 256,
                               math.floor(v.pubLo / 256), v.pubLo % 256 })
  end
  if lanMode == LAN_SHORT then
    local a, b, guessed = lanEndpointPrefix(myLanIp)
    invite.lan = ipString({ a, b, math.floor(v.lanLo / 256), v.lanLo % 256 })
    invite.lanPrefixGuessed = guessed
  elseif lanMode == LAN_TEN then
    invite.lan = ipString({ 10, v.lanMid, math.floor(v.lanLo / 256), v.lanLo % 256 })
  elseif lanMode == LAN_FULL then
    invite.lan = ipString({ math.floor(v.lanHi / 256), v.lanHi % 256,
                            math.floor(v.lanLo / 256), v.lanLo % 256 })
  end
  if invite.kind == "hub" then
    invite.ticket = invite.nonce
    invite.hub = { ip = invite.public or invite.lan, port = invite.public and invite.publicPort or invite.port }
    if invite.public and invite.lan then invite.hub.lan, invite.hub.lanPort = invite.lan, invite.port end
  end
  invite.endpoints = endpointsOf(invite)
  return invite
end

-- Pull a code out of pasted text ("Join me! ABCD-EFGH-... see you"):
-- every run of letters, digits, dashes and single spaces is tried, the
-- longest first, and the first that decodes wins.  Falls back to the
-- whole text so the player still gets decode's own message.
-- Returns invite, raw  or  nil, message, reason
function InviteCode.findInText(text, myLanIp)
  if type(text) ~= "string" or text == "" then return nil, "The clipboard is empty.", "empty" end
  local candidates = {}
  for run in text:gmatch("[%w][%w%- ]*[%w]") do candidates[#candidates + 1] = run end
  for word in text:gmatch("[%w%-]+") do candidates[#candidates + 1] = word end
  table.sort(candidates, function(a, b) return #a > #b end)
  for _, c in ipairs(candidates) do
    local raw = InviteCode.normalize(c)
    if raw and InviteCode.isValidLength(#raw) then
      local inv = InviteCode.decode(raw, myLanIp)
      if inv then return inv, raw end
    end
  end
  return InviteCode.decode(text, myLanIp)
end

-- One line for a status row: "LAN 192.168.1.20 + internet, port 7777".
function InviteCode.describe(invite)
  if type(invite) ~= "table" then return "" end
  if invite.type == "short" then return "Room " .. tostring(invite.room) end
  local parts = {}
  if invite.kind == "hub" then parts[#parts + 1] = "Hub " .. tostring(invite.hub and invite.hub.ip) end
  if invite.kind ~= "hub" and invite.lan then parts[#parts + 1] = "LAN " .. invite.lan end
  if invite.kind ~= "hub" and invite.public then parts[#parts + 1] = "internet " .. invite.public end
  local s = table.concat(parts, " + ")
  if invite.port ~= InviteCode.DEFAULT_PORT then s = s .. ", port " .. invite.port end
  if invite.publicPort then s = s .. ", outside port " .. invite.publicPort end
  return s
end

return InviteCode
