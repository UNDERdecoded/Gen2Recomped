-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Install a map-edits pack somebody else exported.
--
-- THE OTHER HALF OF `ModExport`, and the reason it needed one: an export that
-- nobody can install is a file, not a feature. The exporter has been able to
-- write a zip for a while and there was no door in the editor to bring one
-- back through, so the only way to check that an export WORKED was to find the
-- file, quit to the launcher and install it as a mod -- which is enough
-- friction that a broken export could sit unnoticed.
--
-- THROUGH THE LAUNCHER'S OWN INSTALLER. `LauncherMods.installZip` already
-- knows how to mount an archive in memory (the Switch refuses to reopen a file
-- it just wrote), find the manifest whether or not the zip has a wrapper
-- folder, refuse a Mac `._` resource fork by its magic bytes, and roll back a
-- half-written tree. None of that is worth a second copy, and a second copy is
-- how the two drift until one of them is the one nobody tests.
--
-- WHAT THIS FILE ADDS is the part the launcher has no opinion about: a map
-- pack can declare the cartridges it needs (`required_games`, see
-- src/import/AdoptedTileset.lua), and installing one whose cartridges are
-- absent produces a mod that loads, refuses, and looks broken. So the
-- requirement is read out of the manifest BEFORE the install and reported
-- with the result.

local ModImport = {}

-- Read `required_games` out of a zip without installing it.
--
-- Answered from the manifest alone, which is the only part of a mod that can
-- be read without running it -- the same reason the launcher scans manifests
-- rather than loading mods to build its list.
function ModImport.requirementsOf(manifest)
  if type(manifest) ~= "table" then return nil end
  -- `requiredGames`, as `Manifest.validate` publishes it. NOT a second parse of
  -- `raw.required_games`: the parser is a local in that file and reaching past
  -- it would be a second reading of the same field, free to disagree with the
  -- one the launcher uses.
  local list = manifest.requiredGames
  if type(list) ~= "table" or not list[1] then return nil end
  local okA, AT = pcall(require, "src.import.AdoptedTileset")
  if not okA then return nil end
  local want = {}
  for _, row in ipairs(list) do want[#want + 1] = row.version end
  return AT.missing(want), list
end

-- Install the zip at `path`. Returns the mod id, or nil plus a reason.
--
-- `replace = true`: a map pack is something the reader is likely to be handed
-- a second time -- the author fixed a warp and sent v2 -- and refusing that as
-- "a mod named X is already installed" would send them to the launcher to
-- uninstall by hand. An update is the expected case here, unlike a fresh
-- install from the mod index.
-- Install the zip at `path`.
--
-- Returns a RESULT TABLE, not a sentence: { id, needs }, where `needs` is one
-- row per declared cartridge carrying `imported`. The caller is a dialog that
-- has to draw a line per cartridge with a tick or a cross beside it, and a
-- pre-joined English sentence cannot be taken apart again.
--
-- `replace = true`: a map pack is something the reader is likely to be handed
-- a second time -- the author fixed a warp and sent v2 -- and refusing that as
-- "a mod named X is already installed" would send them to the launcher to
-- uninstall by hand. An update is the expected case here, unlike a fresh
-- install from the mod index.
function ModImport.install(path)
  if type(path) ~= "string" or path == "" then return nil, "no file chosen" end
  local okL, LauncherMods = pcall(require, "src.mods.LauncherMods")
  if not (okL and type(LauncherMods) == "table" and LauncherMods.installZip) then
    return nil, "this build has no mod installer"
  end

  local ok, id = LauncherMods.installZip(path, { replace = true })
  if not ok then return nil, tostring(id or "the pack could not be installed") end

  -- WHAT IT NEEDS, ONE ROW PER CARTRIDGE, each answered independently.
  --
  -- A pack built from two ROMs where the reader has one of them is the case
  -- worth getting right: a single "some cartridges are missing" tells them to
  -- go and check both, and they already have one.
  --
  -- `list`, not a re-parse of the manifest: the launcher's own row already
  -- carries `requiredGames`, so one place decides what a pack declares.
  local needs = {}
  do
    local okS, rows = pcall(LauncherMods.list)
    local declared = nil
    if okS and type(rows) == "table" then
      for _, m in ipairs(rows) do
        if m.id == id then declared = m.requiredGames end
      end
    end
    local okA, AT = pcall(require, "src.import.AdoptedTileset")
    for _, row in ipairs(declared or {}) do
      needs[#needs + 1] = {
        version = row.version,
        name = row.name or (okA and AT.displayName(row.version))
          or tostring(row.version):upper(),
        imported = okA and AT.hasDataset(row.version) or false,
      }
    end
  end

  return { id = id, needs = needs }
end

return ModImport
