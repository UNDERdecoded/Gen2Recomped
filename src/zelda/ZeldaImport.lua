-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A ZELDA IMPORT, shaped like a Pokemon extractor so the launcher's import
-- path (RomImporter:startData -> rom_import_worker.lua, or the in-process
-- coroutine on a host without threads) runs it unchanged:
--
--   ZeldaImport.new(bytes, version, manifest, onProgress) -> extractor
--   extractor:run()
--
-- `manifest` is not a JSON manifest here: the launcher passes
-- { zelda = true, romPath = <path or nil> }. The cartridge was already
-- verified by SHA-1 (GameVersion.forSha1) before this runs, so the player's
-- own dump is the only source of every byte the game module writes.
--
-- The worker has already pointed CacheFs at the data root, set
-- CacheFs.prefix to the game's subtree, cleared that subtree's
-- data/generated + assets/generated and turned on CacheFs.bulkWrites; the
-- launcher writes the completion marker (markerLine) afterwards through the
-- synced path. ImportRecovery breadcrumbs come from the progress callback.

local Registry = require("src.zelda.ZeldaRegistry")

local Import = {}
Import.__index = Import

-- The first line of <prefix>rom-cache.complete for a Zelda version: the
-- module's cacheVersion and the ROM hash, so a module bump or a swapped ROM
-- both re-import.
function Import.markerLine(version)
  local GV = require("src.core.GameVersion")
  local info = GV.info(version) or {}
  return ("zelda-cache:%s:v%d:%s"):format(tostring(version),
    Registry.cacheVersion(version), tostring(info.sha1))
end

-- The game module's own completeness check, run after the marker matched.
-- Returns ok, why.
function Import.moduleReady(version)
  local mod, why = Registry.require(version, "import")
  if not mod then return false, why end
  local cache = require("src.zelda.ZeldaCache").open(version)
  local ok, ready, reason = pcall(mod.isReady, cache)
  if not ok then return false, "isReady failed: " .. tostring(ready) end
  if not ready then return false, reason or "the game's cache is incomplete" end
  return true
end

-- Why an import of this version cannot start, or nil.
function Import.blockedReason(version)
  local mod, why = Registry.require(version, "import")
  if not mod then return why end
  return nil
end

function Import.new(bytes, version, manifest, onProgress)
  local self = setmetatable({}, Import)
  self.bytes = bytes
  self.version = version
  self.romPath = type(manifest) == "table" and manifest.romPath or nil
  self.onProgress = onProgress
  return self
end

function Import:run()
  local mod, why = Registry.require(self.version, "import")
  if not mod then error(why, 0) end
  local cache = require("src.zelda.ZeldaCache").open(self.version)
  local lastLabel = "Extracting"
  local function progress(frac, label)
    frac = tonumber(frac) or 0
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    if label then lastLabel = tostring(label) end
    if self.onProgress then
      self.onProgress(math.floor(frac * 1000 + 0.5), 1000, lastLabel, nil, nil)
    end
  end
  local ctx = {
    version = self.version,
    bytes = self.bytes,       -- the whole verified ROM, always present
    romPath = self.romPath,   -- may be nil (Android inbox, dropped file)
    cache = cache,
    checkpoint = function(op) if self.checkpoint then self.checkpoint(op) end end,
    -- every import is a full one: the worker cleared data/generated and
    -- assets/generated, and a stage stamp anywhere else must not be trusted
    -- (the launcher only re-imports when the ROM, the module's cacheVersion
    -- or the cache itself changed)
    fresh = true,
  }
  progress(0, "Reading cartridge")
  mod.extract(self.romPath, cache, progress, ctx)
  progress(1, "Finishing")
  self.bytes = nil
end

function Import:close()
  self.bytes = nil
end

return Import
