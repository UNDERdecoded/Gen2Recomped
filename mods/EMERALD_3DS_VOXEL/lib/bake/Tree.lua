-- The generators' repository, in memory: path -> bytes.
--
-- The Python generators read and write a decomp-layout tree on disk
-- (data/layouts/layouts.json, data/tilesets/..., 3ds_port/assets/voxel/...,
-- 3ds_port/romfs/voxel/*.bin).  Their ports read and write one of these
-- instead.  Paths are relative to the tree's root, '/'-separated, with no
-- leading './' -- exactly the strings `os.path.join(ROOT, ...)` names
-- relative to ROOT.  Text files are kept with '\n' line ends (CPython's text
-- mode reads CRLF and LF alike, so the generators cannot tell).
--
--   local t = Tree.new()
--   t:write(path, bytes)      t:read(path) -> bytes | nil
--   t:exists(path)            t:isfile(path)   t:isdir(path)
--   t:listdir(dir)            names directly under dir, sorted (os.listdir
--                             order is unspecified; the generators that care
--                             sort it themselves)
--   t:files()                 every file path, sorted
--   t:remove(path)
--   t:cached(key, fn)         a per-tree memo for parsed files (json, u16
--                             lists): fn() runs once per key
--
-- No love.* here: a Tree is plain Lua and can live in a love.thread.

local V = ...

local Tree = {}
Tree.__index = Tree

local function norm(path)
  path = path:gsub("\\", "/"):gsub("/+", "/"):gsub("^%./", ""):gsub("/$", "")
  -- resolve "a/b/../c" the way os.path.join(ROOT, "..", ...) callers expect
  if path:find("%.%.") or path:find("/%./") then
    local parts = {}
    for p in path:gmatch("[^/]+") do
      if p == ".." then parts[#parts] = nil
      elseif p ~= "." then parts[#parts + 1] = p end
    end
    path = table.concat(parts, "/")
  end
  return path
end
Tree.norm = norm

function Tree.new()
  return setmetatable({ data = {}, dirs = { [""] = {} }, memo = {} }, Tree)
end

local function parent(path)
  return path:match("^(.*)/[^/]*$") or ""
end

local function name(path)
  return path:match("([^/]*)$")
end

function Tree:_mkdirs(dir)
  local dirs = self.dirs
  if dirs[dir] then return end
  local up = parent(dir)
  self:_mkdirs(up)
  dirs[dir] = {}
  dirs[up][name(dir)] = true
end

function Tree:write(path, bytes)
  assert(type(bytes) == "string", "Tree:write wants a string")
  path = norm(path)
  local dir = parent(path)
  self:_mkdirs(dir)
  self.dirs[dir][name(path)] = true
  -- a file rewritten: whatever was parsed from it is stale
  if self.data[path] ~= nil then self.memo = {} end
  self.data[path] = bytes
end

function Tree:read(path)
  return self.data[norm(path)]
end

function Tree:isfile(path) return self.data[norm(path)] ~= nil end
function Tree:isdir(path) return self.dirs[norm(path)] ~= nil end
function Tree:exists(path)
  path = norm(path)
  return self.data[path] ~= nil or self.dirs[path] ~= nil
end

function Tree:listdir(dir)
  local d = self.dirs[norm(dir)]
  if not d then error("FileNotFoundError: " .. tostring(dir), 2) end
  local out = {}
  for k in pairs(d) do out[#out + 1] = k end
  table.sort(out)
  return out
end

function Tree:files()
  local out = {}
  for k in pairs(self.data) do out[#out + 1] = k end
  table.sort(out)
  return out
end

function Tree:remove(path)
  path = norm(path)
  if self.data[path] ~= nil then self.memo = {} end
  self.data[path] = nil
  local d = self.dirs[parent(path)]
  if d then d[name(path)] = nil end
end

-- open(path).read() that raises like Python when the file is missing
function Tree:must(path)
  local b = self.data[norm(path)]
  if b == nil then error("FileNotFoundError: " .. tostring(path), 2) end
  return b
end

-- a per-tree memo; keys are strings ("json:" .. path, "u16:" .. path, ...)
function Tree:cached(key, fn)
  local hit = self.memo[key]
  if hit == nil then
    hit = fn()
    self.memo[key] = hit
  end
  return hit
end

return Tree
