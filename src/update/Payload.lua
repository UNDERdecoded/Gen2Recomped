-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHERE A DOWNLOADED PAYLOAD LIVES, AND WHAT IT IS CALLED.  One fact, in one
-- file, because it was four.
--
-- The downloader wrote the .love and the boot shell mounted it, and neither
-- asked the other where that was.  Spelled out across the tree before this
-- module existed:
--
--   src/update/Boot.lua          PAYLOAD_DIR = "updates"
--                                PENDING     = "updates/pending.txt"
--                                isPayloadName -> "^Gen2Recomped%-.+%.love$"
--   src/update/Check.lua         payloadName = "Gen2Recomped-" .. v .. ".love"
--   src/update/check_worker.lua  "updates/" .. payloadName       (x4)
--                                saveDir .. "/updates/" .. ...   (x2)
--                                "updates/dl.bat"
--
-- Seven literals for two facts.  Rename the release asset, or move the folder,
-- and the download still succeeds and the next boot still finds nothing -- the
-- exact failure shape this port keeps producing (the same thing spelled
-- differently in two places that never meet).  So: zero requires, no love.*
-- calls, loadable from a plain-Lua test and from inside a love.thread, and
-- every other file in src/update asks it.
--
-- tools/auto_update_check.lua fails if any of those literals reappears
-- anywhere in src/update outside this file.

local Payload = {}

-- The save-directory-relative folder every payload lives in.  Relative on
-- purpose: love.filesystem's write directory IS the save directory, so the
-- same string is what Boot mounts and what the worker writes, and only the
-- bridge/curl transports (which take host paths) ever prefix the absolute
-- save directory to it.
Payload.DIR = "updates"

-- The release asset name is "<PREFIX><X.Y.Z><EXT>".  Must match the name
-- .github/workflows/release.yml stages:
--   cp "payload/game.love" "$outdir/Gen2Recomped-${v}.love"
-- and the name listed in that release's sha256sums.txt, because the checksum
-- is looked up by this exact string.
Payload.PREFIX = "Gen2Recomped-"
Payload.EXT = ".love"

-- The crash-guard marker Boot writes before a handoff.
Payload.PENDING = Payload.DIR .. "/pending.txt"

-- THE CHECKSUM MANIFEST, ONCE.  Every release carries one of these beside the
-- payload; measured against the live v0.8.3 release it is 1,171 bytes and
-- lists the payload as
--   96fd608027b41973fe7bd4f650826e11b7234add0ef93049aaf7567ac1d9e11d  Gen2Recomped-0.8.3.love
-- so the same file answers "is this payload intact?" for the downloader, for
-- the Switch OTA launcher (ports/switch/ota-launcher/include/ota_protocol.h
-- builds its URL from OTA_REPO_SLUG) and for a hand-placed console sideload.
-- It was spelled out in src/update/Check.lua as well; this is the only Lua
-- copy now, for the same reason the folder and the asset name are.
Payload.SUMS = "sha256sums.txt"

-- Save-directory-relative path of a sideloaded checksum manifest.
function Payload.sumsRel()
  return Payload.DIR .. "/" .. Payload.SUMS
end

-- Payload.name("0.8.3") -> "Gen2Recomped-0.8.3.love"
function Payload.name(version)
  return Payload.PREFIX .. tostring(version) .. Payload.EXT
end

-- Save-directory-relative path of a finished payload.
function Payload.rel(version)
  return Payload.DIR .. "/" .. Payload.name(version)
end

-- Save-directory-relative path of the in-flight download and its done-marker.
-- Both derive from rel() so a half-finished transfer can never be mistaken for
-- a finished payload: Payload.isName rejects the ".part" and ".done" suffixes.
function Payload.partRel(version)
  return Payload.rel(version) .. ".part"
end

function Payload.doneRel(version)
  return Payload.rel(version) .. ".done"
end

-- The helper batch file the Windows background download goes through.
function Payload.scriptRel()
  return Payload.DIR .. "/dl.bat"
end

-- Is this directory entry a payload Boot should probe?  Anchored at both ends
-- so "<name>.part" and "<name>.done" are not candidates.
function Payload.isName(name)
  if type(name) ~= "string" then return false end
  local pattern = "^" .. Payload.PREFIX:gsub("%-", "%%-")
    .. ".+" .. Payload.EXT:gsub("%.", "%%.") .. "$"
  return name:match(pattern) ~= nil
end

-- Payload.parseSums(text)         -> { [filename] = lowercase hex }
-- Payload.parseSums(text, name)   -> that one hex, or nil
--
-- The format `sha256sum` emits and .github/workflows/release.yml runs:
-- "<hex>  <filename>", two spaces, optionally "*" for binary mode and
-- optionally a "./" prefix.  THIS LIVED IN src/update/Check.lua, which is a
-- main-thread module; the sideload verifier runs from src/update/Boot.lua on
-- the very first line of love.load, before Check is loaded at all, and a
-- second parser for the same file is the fault this tree keeps producing.
-- Check.parseSums delegates here and remains the name the tests drive.
function Payload.parseSums(text, target)
  local map = {}
  for line in tostring(text):gmatch("[^\r\n]+") do
    local hash, file = line:match("^(%x+)%s+%*?(%S+)")
    if hash and file then
      map[(file:gsub("^%./", ""))] = hash:lower()
    end
  end
  if target ~= nil then return map[target] end
  return map
end

return Payload
