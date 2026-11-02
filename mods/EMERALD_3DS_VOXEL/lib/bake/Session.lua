-- One generator run = one Python process.
--
-- Each Emerald 3DS generator ran in its own interpreter: its modules'
-- top-level code (tables read from the tree, memo dicts) started fresh.
-- A Session gives the Lua ports the same: S.import(name) runs
-- lib/bake/<name>.lua once per session as chunk(V, S) and caches the value,
-- so a port's module-level state lives exactly as long as the session.
--
--   local S = Session.new(V, tree)
--   local voxel_cells = S.import("voxel_cells")
--
-- Inside a ported module:   local V, S = ...
--                           local tree = S.tree
--                           local voxel_art = S.import("voxel_art")
-- (an import inside a Python function stays an S.import inside the Lua
-- function: same order, same laziness).
--
-- Infrastructure modules (Image, py, json, Tree, ...) are not sessions':
-- they load once through V.require.

local V = ...

local Session = {}
Session.__index = Session

-- compiled chunks, shared by every session
local chunks = {}

local function source_of(rel)
  if V.read then return V.read(rel) end                 -- harness / thread
  if V.mod and V.mod.read then return V.mod:read(rel) end -- main.lua's V
  if love and love.filesystem and V.path then
    return love.filesystem.read(V.path .. "/" .. rel)
  end
  return nil
end

local function chunk_of(name)
  local hit = chunks[name]
  if hit then return hit end
  local rel = "lib/bake/" .. name .. ".lua"
  local src = source_of(rel)
  if not src then error("bake: " .. rel .. " is missing", 0) end
  local fn, err = loadstring(src, "@" .. tostring(V.path) .. "/" .. rel)
  if not fn then error(err, 0) end
  chunks[name] = fn
  return fn
end

function Session.new(tree, opts)
  local S = setmetatable({ tree = tree, modules = {}, loading = {}, opts = opts or {} }, Session)
  S.import = function(name) return S:_import(name) end
  return S
end

function Session:_import(name)
  local hit = self.modules[name]
  if hit ~= nil then return hit end
  if self.loading[name] then
    -- a circular import: Python hands back the partly initialised module.
    -- Ports avoid this by importing lazily, inside the function.
    return self.loading[name]
  end
  local partial = {}
  self.loading[name] = partial
  local value = chunk_of(name)(V, self, partial)
  if value == nil then value = partial end
  self.loading[name] = nil
  self.modules[name] = value
  return value
end

-- progress(fraction, label) passed down from Bake.run, or a no-op
function Session:progress(f, label)
  local p = self.opts.progress
  if p then p(f, label) end
end

-- A streaming writer for the tree file `path` (opts.output from Bake.run,
-- when its caller writes the outputs itself), or nil: then the generator
-- writes the bytes into the tree as Python writes the file.  The writer has
-- :write(chunk) and :close(); a generator that streams leaves `path` out of
-- the tree.
function Session:output(path)
  local o = self.opts.output
  return o and o(path) or nil
end

-- A part of the step's bar (not in Python): S:part(lo, hi, label) starts
-- it at `lo`, then S:tick(f) reports f (0..1) of the way through it.  A
-- tick outside any part says nothing.  Long steps (the relief) use these so
-- the bar moves through work that has no natural fraction of its own.
function Session:part(lo, hi, label)
  self._part = { lo, hi, label }
  self:progress(lo, label)
end

function Session:tick(f, label)
  local p = self._part
  if not p then return end
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  self:progress(p[1] + (p[2] - p[1]) * f, label or p[3])
end

return Session
