-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A ZELDA GAME'S IMPORTED CACHE, as one object.
--
-- The Pokemon games read their cache through an overlay mounted onto the
-- un-prefixed paths (CacheFs.mountVersion) so `require "data.generated.x"`
-- lands on the right game. The Zelda games do not need that machinery and
-- must not touch it -- a Zelda boot leaves the Pokemon read path exactly as it
-- was. Instead every read goes through this accessor, which pins
-- CacheFs.prefix to the game's own subtree ("alttp/", "minishcap/") for the
-- duration of the call. It works wherever CacheFs works: the save directory,
-- a portable game folder or a custom data folder, and inside the import
-- worker thread (image helpers need love.graphics and are runtime-only).
--
-- This is the `root` handed to a game module's isReady(root) and newGame's
-- opts.root / opts.cache, and the 4th argument's `cache` in extract.

local Cache = {}
Cache.__index = Cache

local function CacheFs() return require("src.import.CacheFs") end

function Cache.open(version)
  local GV = require("src.core.GameVersion")
  local info = GV.info(version)
  assert(info, "unknown version " .. tostring(version))
  return setmetatable({ version = version, prefix = info.cachePrefix or (version .. "/") }, Cache)
end

Cache.__tostring = function(self) return self.prefix end

-- Run fn with CacheFs.prefix set to this game's subtree, restoring it after
-- (also on error).
function Cache:with(fn, ...)
  local C = CacheFs()
  local saved = C.prefix
  C.prefix = self.prefix
  local ok, a, b = pcall(fn, C, ...)
  C.prefix = saved
  if not ok then error(a, 0) end
  return a, b
end

function Cache:read(rel)
  return self:with(function(C) return C.read(rel) end)
end

function Cache:exists(rel)
  return self:with(function(C) return C.exists(rel) end) and true or false
end

-- Writes are for the import (extract); the runtime treats the cache as
-- read-only. Returns ok, err.
function Cache:write(rel, data)
  return self:with(function(C) return C.write(rel, data) end)
end

function Cache:remove(rel)
  return self:with(function(C) return C.remove(rel) end)
end

-- A Lua table written by the importer ("return { ... }"), run in an empty
-- environment so a cache file can never reach the engine's globals.
function Cache:loadLua(rel)
  local src = self:read(rel)
  if type(src) ~= "string" then return nil, "missing " .. tostring(rel) end
  local chunk, err = loadstring(src, "=" .. self.prefix .. rel)
  if not chunk then return nil, err end
  setfenv(chunk, {})
  local ok, value = pcall(chunk)
  if not ok then return nil, value end
  return value
end

function Cache:fileData(rel)
  local bytes = self:read(rel)
  if type(bytes) ~= "string" then return nil, "missing " .. tostring(rel) end
  return love.filesystem.newFileData(bytes, rel:match("[^/]+$") or rel)
end

function Cache:imageData(rel)
  local fd, err = self:fileData(rel)
  if not fd then return nil, err end
  local ok, img = pcall(love.image.newImageData, fd)
  if not ok then return nil, img end
  return img
end

-- A love Image, nearest-filtered (GBA pixels), cached per path.
function Cache:image(rel)
  self._images = self._images or {}
  local hit = self._images[rel]
  if hit ~= nil then return hit or nil end
  local data = self:imageData(rel)
  local img = false
  if data then
    local ok, im = pcall(love.graphics.newImage, data)
    if ok then im:setFilter("nearest", "nearest"); img = im end
  end
  self._images[rel] = img
  return img or nil
end

-- A love Source (static by default) from a cached .ogg/.wav.
function Cache:source(rel, kind)
  local fd = self:fileData(rel)
  if not fd then return nil end
  local ok, src = pcall(love.audio.newSource, fd, kind or "static")
  return ok and src or nil
end

return Cache
