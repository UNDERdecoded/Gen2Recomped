-- Parity test: the link fingerprint no longer hashes catchRate, so a
-- Yellow-shaped dataset that differs from Red/Blue only at
-- Dragonair/Dragonite's catch rate digests identical and the handshake
-- reports "full" (#511).
--
-- Real cross-version link play (two processes, Red vs Yellow) is outside
-- what this checkout can assert: it needs both a Red and a Yellow
-- data/generated/ cache and two live UDP peers. What IS assertable from
-- one process: (1) catchRate is excluded from the hashed species surface,
-- so editing only that field never moves the digest, and (2) a synthetic
-- Yellow stand-in built by copying the real Data and retuning just those
-- two species' catchRate (the only real R/B vs Yellow link-surface delta,
-- per data/pokemon/base_stats/dragonair.asm 45 vs 27 and dragonite.asm 45
-- vs 9) fingerprints identically and clears Handshake.checkCompat as
-- "full", not "subset".
--
-- A human still has to run the actual cross-version check: launch a Red
-- instance and a Yellow instance (POKEPORT_VERSION=red / =yellow,
-- distinct POKEPORT_IDENTITY sandboxes), host/join on localhost, and
-- confirm no "game data is not the same" notice appears and a trade goes
-- through both ways.
--
-- Self-contained; run via `luajit tests/parity_link_fingerprint_yellow.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity link fingerprint yellow")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
Data:load()

local Fingerprint = require("src.link.Fingerprint")
local Handshake = require("src.link.Handshake")

local function copy(record)
  local out = {}
  for k, v in pairs(record) do out[k] = v end
  return out
end

local function cloneData(base)
  local out = { pokemon = {}, moves = {}, type_chart = base.type_chart,
                constants = base.constants }
  for id, record in pairs(base.pokemon) do out.pokemon[id] = record end
  for id, record in pairs(base.moves) do out.moves[id] = record end
  return out
end

-- (1) catchRate alone must not move the digest: this is the field
-- allowlist change at src/link/Fingerprint.lua SPECIES_FIELDS.
local vanilla = cloneData(Data)
local first = Fingerprint.compute(vanilla, {})

local rateOnly = cloneData(Data)
local pidgeyRate = copy(Data.pokemon.PIDGEY)
pidgeyRate.catchRate = (pidgeyRate.catchRate or 0) + 1
rateOnly.pokemon.PIDGEY = pidgeyRate
eq(Fingerprint.compute(rateOnly, {}), first,
   "a catchRate-only edit does not move the link fingerprint")

-- (2) a Yellow stand-in: same records, Dragonair/Dragonite catch rate
-- retuned to Yellow's values (the only real R/B vs Yellow link delta).
Fingerprint.forget(vanilla)
local yellowish = cloneData(Data)
if Data.pokemon.DRAGONAIR then
  local dragonair = copy(Data.pokemon.DRAGONAIR)
  dragonair.catchRate = 27 -- pokeyellow data/pokemon/base_stats/dragonair.asm
  yellowish.pokemon.DRAGONAIR = dragonair
end
if Data.pokemon.DRAGONITE then
  local dragonite = copy(Data.pokemon.DRAGONITE)
  dragonite.catchRate = 9 -- pokeyellow data/pokemon/base_stats/dragonite.asm
  yellowish.pokemon.DRAGONITE = dragonite
end
check(Data.pokemon.DRAGONAIR ~= nil and Data.pokemon.DRAGONITE ~= nil,
      "fixture has Dragonair and Dragonite to retune")
local yellowPrint = Fingerprint.compute(yellowish, {})
eq(yellowPrint, first,
   "a Yellow-shaped dataset (only Dragonair/Dragonite catch rate differs) " ..
   "fingerprints identically to Red/Blue")

-- (3) the handshake actually reads "full" for that pairing, not "subset"
local redHello = { protocol = 2, engineVersion = "0.1.0", fingerprint = first }
local yellowHello = { protocol = 2, engineVersion = "0.1.0", fingerprint = yellowPrint }
local verdict, reason = Handshake.checkCompat(redHello, yellowHello)
eq(verdict, "full", "Red vs Yellow-shaped peer clears the handshake as full")
check(reason == nil, "a full verdict carries no mismatch reason")

-- control: a real gameplay-affecting edit (base stats) still splits the
-- two builds, so the fingerprint has not gone toothless
local buffed = cloneData(Data)
local strongPidgey = copy(Data.pokemon.PIDGEY)
strongPidgey.baseStats = copy(Data.pokemon.PIDGEY.baseStats)
strongPidgey.baseStats.attack = strongPidgey.baseStats.attack + 1
buffed.pokemon.PIDGEY = strongPidgey
local buffedPrint = Fingerprint.compute(buffed, {})
check(buffedPrint ~= first, "a baseStats edit still moves the digest")
local buffedHello = { protocol = 2, engineVersion = "0.1.0", fingerprint = buffedPrint }
local verdict2 = Handshake.checkCompat(redHello, buffedHello)
eq(verdict2, "subset", "a genuinely different dataset still reads subset, not full")

S.finish()
