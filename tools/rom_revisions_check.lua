-- GameVersion (the acceptance gate) and RomRevisions (what the launcher says
-- about a dump) must name the SAME hashes: every accepted row is a hash
-- GameVersion accepts for that version, and every hash GameVersion accepts is
-- an accepted row. Also pins the Renegade Platinum registration: its own
-- version on Platinum's engine, its own cache and save names.
--
--   python tools/run_lua_check.py tools/rom_revisions_check.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local RomRevisions = require("src.import.RomRevisions")

-- every RomRevisions row is accepted by GameVersion for the same version
for id, rows in pairs(RomRevisions.ACCEPTED) do
  check(GameVersion.info(id) ~= nil, "RomRevisions names a registered version: " .. id)
  for _, row in ipairs(rows) do
    check(GameVersion.acceptsSha1(id, row.sha1), ("%s accepts %s (%s)"):format(id, row.sha1, row.label))
    eq(GameVersion.forSha1(row.sha1), id, "forSha1 -> " .. id .. " for " .. row.label)
  end
end

-- every hash GameVersion accepts has a RomRevisions row
for id, info in pairs(GameVersion.VERSIONS) do
  local hashes = { info.sha1 }
  for _, alt in ipairs(info.sha1Alt or {}) do hashes[#hashes + 1] = alt end
  for _, sha1 in ipairs(hashes) do
    local game = RomRevisions.acceptedRow(sha1)
    eq(game, id, ("RomRevisions has a row for %s's %s"):format(id, sha1))
  end
  check(RomRevisions.GAME_NAMES[id] ~= nil, "RomRevisions.GAME_NAMES names " .. id)
  -- RomImporter's decodeManifest asserts the manifest's romSha1 is accepted
  if info.manifest then
    local f = io.open(info.manifest, "rb")
    local raw = f and f:read("*a")
    if f then f:close() end
    local sha1 = raw and raw:match('"romSha1"%s*:%s*"(%x+)"')
    check(sha1 and GameVersion.acceptsSha1(id, sha1), ("%s's manifest %s names an accepted dump"):format(id, info.manifest))
  end
end

-- every ORDER entry is registered, once
local seen = {}
for _, id in ipairs(GameVersion.ORDER) do
  check(GameVersion.info(id) ~= nil, "ORDER entry is registered: " .. id)
  check(not seen[id], "ORDER lists " .. id .. " once")
  seen[id] = true
end

-- Renegade Platinum: its own version, Platinum's engine
local RP = "renegadeplatinum"
local rp = GameVersion.info(RP)
check(rp ~= nil, "renegadeplatinum is registered")
eq(GameVersion.forSha1("381f9eef44564602a5f6469ee8c390fbb8ebac3a"), RP, "the Renegade dump is its own version")
eq(GameVersion.forSha1("0862ec35b24de5c7e2dcb88c9eea0873110d755c"), "platinum", "Platinum Rev 1 stays Platinum")
eq(GameVersion.generation(RP), 4, "Renegade is Gen 4")
eq(GameVersion.family(RP), "platinum", "Renegade runs Platinum's family")
check(GameVersion.isPlatinumFamily(RP), "isPlatinumFamily(renegadeplatinum)")
check(GameVersion.isPlatinumFamily("platinum"), "isPlatinumFamily(platinum)")
check(not GameVersion.isPlatinumFamily("heartgold"), "HeartGold is not Platinum's family")
check(not GameVersion.isPlatinumFamily("crystal"), "Crystal is not Platinum's family")
check(rp.cachePrefix ~= GameVersion.info("platinum").cachePrefix, "Renegade has its own cache")
check(rp.saveSuffix ~= GameVersion.info("platinum").saveSuffix, "Renegade has its own saves")
check(rp.importable == true and rp.dualScreen == true, "Renegade imports and has two screens")
eq(require("src.import.Gen4Versions").family(RP), "platinum", "the extractor reads Renegade as Platinum")
check(seen[RP], "Renegade has a launcher column")

-- an unaccepted CPUE file is still described as Platinum
local header = string.rep("\0", 0x200)
local function put(s, at, bytes) return s:sub(1, at) .. bytes .. s:sub(at + #bytes + 1) end
header = put(header, 0x00, "POKEMON PL")
header = put(header, 0x0C, "CPUE")
header = put(header, 0x1E, "\1")
header = put(header, 0x15C, "\86\207")
local d = RomRevisions.describe(header, string.rep("0", 40))
eq(d and d.game, "platinum", "an unknown CPUE dump is described as Platinum")

T.finish()
