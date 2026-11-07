-- Who this install is, to a world host (docs/online-design.md 2.8
-- "Identity").  Not an account: on first use each install makes a random
-- 128-bit token (save/online/identity.json) and never sends it.  A host is
-- told only a hash of the token and the WORLD's id, so a host learns one
-- stable id per player for its own world -- enough to recognise a returning
-- member, keep a ban, route a GTS result -- and two hosts cannot match
-- their member lists against each other.
--
--   Identity.token()            -> hex token (made and stored on first use)
--   Identity.forWorld(worldId)  -> 32 hex digits
--   Identity.playerId()         -> 32 hex digits, the same in every world
--   Identity.hash(text)         -> hex digest (sha256 under LOVE, else FNV)
--
-- Identity.fs may be replaced (tests): { read(path) -> text|nil,
-- write(path, text) -> ok }.  Default: love.filesystem, else memory only.

local Identity = {}

Identity.PATH = "online/identity.json"

local memory = {}

local function loveFs()
  local fs = love and love.filesystem
  if not fs then return nil end
  return {
    read = function(path)
      local ok, info = pcall(fs.getInfo, path)
      if not (ok and info) then return nil end
      local okR, text = pcall(fs.read, path)
      return okR and text or nil
    end,
    write = function(path, text)
      pcall(fs.createDirectory, path:match("^(.*)/[^/]+$") or "")
      local ok, res = pcall(fs.write, path, text)
      return ok and res and true or false
    end,
  }
end

Identity.fs = nil

local function fsys()
  if Identity.fs then return Identity.fs end
  return loveFs() or {
    read = function(path) return memory[path] end,
    write = function(path, text) memory[path] = text return true end,
  }
end

-- ------------------------------------------------------------ hashing

local bit = bit or (pcall(require, "bit") and require("bit")) or nil

local function fnvHex(text, seed)
  -- FNV-1a 32-bit (two lanes with different offsets make 64 bits); only the
  -- fallback when love.data is missing (headless tests)
  local h = seed
  for i = 1, #text do
    h = bit.bxor(h, text:byte(i))
    h = bit.tobit(h * 16777619)
  end
  return ("%08x"):format(h % 4294967296)
end

function Identity.hash(text)
  text = tostring(text or "")
  if love and love.data and love.data.hash and love.data.encode then
    local ok, raw = pcall(love.data.hash, "sha256", text)
    if ok and raw then
      local okE, hex = pcall(love.data.encode, "string", "hex", raw)
      if okE and hex then return hex end
    end
  end
  local out = {}
  for lane = 0, 3 do out[#out + 1] = fnvHex(text, bit.tobit(2166136261 + lane * 7919)) end
  return table.concat(out)
end

local function randomHex(n)
  local Util = require("src.online.net.Util")
  local parts = {}
  for _ = 1, math.ceil(n / 8) do parts[#parts + 1] = ("%08x"):format(Util.rand32() % 4294967296) end
  return table.concat(parts):sub(1, n)
end

local cached

function Identity.token()
  if cached then return cached end
  local fs = fsys()
  local text = fs.read(Identity.PATH)
  local token = type(text) == "string" and text:match('"token"%s*:%s*"(%x+)"')
  if not token or #token < 32 then
    token = randomHex(32)
    fs.write(Identity.PATH, ('{"token":"%s","made":%d}'):format(token, os.time()))
  end
  cached = token
  return token
end

function Identity.forWorld(worldId)
  return Identity.hash(Identity.token() .. ":" .. tostring(worldId or "")):sub(1, 32)
end

-- one stable id for this install outside any world (the GTS client probes
-- for it: src/online/gts/GtsClient.lua identity); still only a hash
function Identity.playerId()
  return Identity.hash("player:" .. Identity.token()):sub(1, 32)
end

-- tests: forget the cached token (and use another fs)
function Identity.reset(fs)
  cached = nil
  Identity.fs = fs
end

return Identity
