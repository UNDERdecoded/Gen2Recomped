-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHICH ZELDA GAME MODULE PLAYS A VERSION ID.
--
-- GameVersion names the version ("alttp", "minishcap") and its `module` dir
-- ("alttp", "tmc"); the game itself is src/zelda/<dir>/init.lua, written by
-- that game's agent to the interface in docs/zelda/CONTRACT.md. This file is
-- the one place that turns the first into the second, so the launcher, the
-- import worker (a separate Lua state: no love.graphics here) and the runtime
-- all agree on what "this game is supported" means:
--
--   * no init.lua on disk         -> not supported yet (a clean message)
--   * init.lua that fails to load -> that error, shown, not swallowed
--   * init.lua missing a function -> which one
--
-- Zero love.graphics, so it loads inside the import worker.

local Registry = {}

-- What each entry point needs. `newGame` is only required to PLAY; an import
-- needs `extract` and `isReady`.
Registry.IMPORT_FIELDS = { "extract", "isReady" }
Registry.PLAY_FIELDS = { "newGame" }

-- Test / harness overrides: id -> module table. A registered module wins over
-- the file on disk (tools/zelda_runtime uses this for the placeholder game).
local overrides = {}
local cache = {}
local missUntil = {}

local function GV() return require("src.core.GameVersion") end

function Registry.register(id, module)
  overrides[id] = module
  cache[id] = nil
end

function Registry.forget(id)
  if id then cache[id] = nil; missUntil[id] = nil else cache = {}; missUntil = {} end
end

-- The module dir for a version id, or nil when the id is not a Zelda game.
function Registry.dirOf(id)
  local info = GV().info(id)
  if not info or info.engine ~= "zelda" then return nil end
  return info.module or id
end

local function fileExists(path)
  if love and love.filesystem and love.filesystem.getInfo then
    return love.filesystem.getInfo(path, "file") ~= nil
  end
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- load(id) -> module | nil, reason, kind
-- kind: "unknown" (not a Zelda id), "missing" (no module yet), "error" (the
-- module failed to load or is incomplete).
function Registry.load(id)
  if overrides[id] then return overrides[id] end
  -- harnesses only: the ROM-free placeholder behind every Zelda id, in every
  -- Lua state (the import worker cannot see a register() made in the main one)
  if os.getenv("POKEPORT_ZELDA_PLACEHOLDER") == "1" and Registry.dirOf(id) then
    return require("src.zelda.ZeldaPlaceholder")
  end
  if cache[id] then return cache[id] end
  local dir = Registry.dirOf(id)
  if not dir then return nil, tostring(id) .. " is not a Zelda game", "unknown" end
  local info = GV().info(id)
  local name = info.displayName or id
  -- the launcher asks every frame while a page is up: remember a miss briefly
  local now = (love and love.timer and love.timer.getTime) and love.timer.getTime() or os.clock()
  if missUntil[id] and now < missUntil[id] then
    return nil, name .. " is not supported by this build yet.", "missing"
  end
  if not fileExists("src/zelda/" .. dir .. "/init.lua") then
    missUntil[id] = now + 3
    return nil, name .. " is not supported by this build yet.", "missing"
  end
  missUntil[id] = nil
  local ok, mod = pcall(require, "src.zelda." .. dir)
  if not ok then
    return nil, ("%s failed to load: %s"):format(name, tostring(mod)), "error"
  end
  if type(mod) ~= "table" then
    return nil, ("%s: src/zelda/%s/init.lua did not return a table"):format(name, dir), "error"
  end
  cache[id] = mod
  return mod
end

-- The module when it can do `purpose` ("import" | "play"), else nil + reason.
function Registry.require(id, purpose)
  local mod, why, kind = Registry.load(id)
  if not mod then return nil, why, kind end
  local fields = purpose == "play" and Registry.PLAY_FIELDS or Registry.IMPORT_FIELDS
  for _, f in ipairs(fields) do
    if type(mod[f]) ~= "function" then
      local name = (GV().info(id) or {}).displayName or id
      return nil, ("%s is not playable yet (its module has no %s)."):format(name, f), "missing"
    end
  end
  return mod
end

-- Is there a module for this id that can at least import?
function Registry.supported(id)
  return Registry.require(id, "import") ~= nil
end

-- The module's cache format number (bumping it forces a re-import).
function Registry.cacheVersion(id)
  local mod = Registry.load(id)
  return mod and tonumber(mod.cacheVersion) or 0
end

return Registry
