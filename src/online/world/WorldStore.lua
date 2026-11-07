-- What a world host keeps on disk (docs/online-design.md 2.8 "Persistence
-- on the host"): save/online/worlds/<worldId>/
--
--   world.json    { id, name, cap, public, filter (nil = on when public),
--                   created, version }
--   members.json  { members = { [idHash] = { name, first, last, visits } },
--                   bans    = { [idHash] = { name, at, reason } } }
--   gts.json      the world GTS's database, written by WS7's GtsService
--                 through store:file("gts") (see WorldHost:storage)
--
-- WRITE-TWICE, not rename: love.filesystem (PhysFS) has no rename, so a
-- file is written complete to `<name>.tmp` first and then over `<name>`;
-- a read that finds `<name>` torn or missing falls back to the `.tmp`.  A
-- crash at any point leaves one whole copy.
--
--   local store = WorldStore.new{ fs = WorldStore.loveFs() | WorldStore.memoryFs() }
--   store:list()                    -> { {id, name, cap, public, created}, ... }
--   store:open(worldId) / store:create{ name, cap, public } -> world record
--   store:readJson(worldId, name) / store:writeJson(worldId, name, value)
--   store:file(worldId, name)       -> { read() -> text, write(text) } (WS7)
--   store:members(worldId) / store:saveMembers(worldId, m)

local Json = require("src.link.Json")
local P = require("src.online.world.WorldProtocol")

local WorldStore = {}
WorldStore.__index = WorldStore

WorldStore.ROOT = "online/worlds"

-- ------------------------------------------------------------ adapters

function WorldStore.loveFs()
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
      local dir = path:match("^(.*)/[^/]+$")
      if dir then pcall(fs.createDirectory, dir) end
      local ok, res = pcall(fs.write, path, text)
      return ok and res and true or false
    end,
    remove = function(path) pcall(fs.remove, path) end,
    list = function(dir)
      local ok, items = pcall(fs.getDirectoryItems, dir)
      return ok and items or {}
    end,
  }
end

function WorldStore.memoryFs()
  local files = {}
  return {
    files = files,
    read = function(path) return files[path] end,
    write = function(path, text) files[path] = text return true end,
    remove = function(path) files[path] = nil end,
    list = function(dir)
      local seen, out = {}, {}
      local prefix = dir .. "/"
      for path in pairs(files) do
        if path:sub(1, #prefix) == prefix then
          local child = path:sub(#prefix + 1):match("^([^/]+)")
          if child and not seen[child] then seen[child] = true out[#out + 1] = child end
        end
      end
      table.sort(out)
      return out
    end,
  }
end

function WorldStore.new(opts)
  opts = opts or {}
  local self = setmetatable({}, WorldStore)
  self.fs = opts.fs or WorldStore.loveFs() or WorldStore.memoryFs()
  self.root = opts.root or WorldStore.ROOT
  return self
end

local function decode(text)
  if type(text) ~= "string" or text == "" then return nil end
  local ok, v = pcall(Json.decode, text)
  if ok and type(v) == "table" then return v end
  return nil
end

function WorldStore:path(worldId, name)
  return ("%s/%s/%s.json"):format(self.root, tostring(worldId), name)
end

function WorldStore:readJson(worldId, name)
  local path = self:path(worldId, name)
  return decode(self.fs.read(path)) or decode(self.fs.read(path .. ".tmp"))
end

function WorldStore:writeJson(worldId, name, value)
  local ok, text = pcall(Json.encode, value)
  if not ok then return false, text end
  return self:writeText(worldId, name, text)
end

function WorldStore:writeText(worldId, name, text)
  local path = self:path(worldId, name)
  if not self.fs.write(path .. ".tmp", text) then return false, "can't write " .. path end
  if not self.fs.write(path, text) then return false, "can't write " .. path end
  if self.fs.remove then self.fs.remove(path .. ".tmp") end
  return true
end

-- a raw text file in the world's folder, for a service that keeps its own
-- format (WS7's GtsStore adapter can sit on this)
function WorldStore:file(worldId, name)
  local store = self
  return {
    path = self:path(worldId, name),
    read = function()
      local path = store:path(worldId, name)
      local text = store.fs.read(path)
      if text == nil or text == "" then text = store.fs.read(path .. ".tmp") end
      return text
    end,
    write = function(text) return store:writeText(worldId, name, text) end,
  }
end

-- ------------------------------------------------------------ worlds

local function newWorldId()
  local Util = require("src.online.net.Util")
  return ("w%08x%04x"):format(Util.rand32() % 4294967296, Util.rand32() % 65536)
end

function WorldStore:create(spec)
  spec = spec or {}
  local world = {
    id = spec.id or newWorldId(),
    name = P.cleanText(spec.name, P.WORLD_NAME_MAX) or "WORLD",
    cap = P.clampCap(spec.cap),
    public = spec.public and true or false,
    filter = spec.filter,
    created = os.time(),
    version = P.VERSION,
  }
  self:writeJson(world.id, "world", world)
  return world
end

function WorldStore:open(worldId)
  local w = self:readJson(worldId, "world")
  if not w then return nil end
  w.id = tostring(worldId)
  w.name = P.cleanText(w.name, P.WORLD_NAME_MAX) or "WORLD"
  w.cap = P.clampCap(w.cap)
  w.public = w.public == true
  if w.filter ~= true and w.filter ~= false then w.filter = nil end
  return w
end

function WorldStore:saveWorld(world)
  return self:writeJson(world.id, "world", {
    id = world.id, name = world.name, cap = world.cap, public = world.public,
    filter = world.filter, created = world.created, version = P.VERSION,
  })
end

function WorldStore:list()
  local out = {}
  for _, id in ipairs(self.fs.list(self.root) or {}) do
    local w = self:open(id)
    if w then out[#out + 1] = w end
  end
  table.sort(out, function(a, b) return (a.created or 0) > (b.created or 0) end)
  return out
end

-- ------------------------------------------------------------ members

function WorldStore:members(worldId)
  local m = self:readJson(worldId, "members") or {}
  if type(m.members) ~= "table" then m.members = {} end
  if type(m.bans) ~= "table" then m.bans = {} end
  return m
end

function WorldStore:saveMembers(worldId, m)
  return self:writeJson(worldId, "members", m)
end

return WorldStore
