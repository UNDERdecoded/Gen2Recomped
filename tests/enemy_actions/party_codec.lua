-- Compare real codecs, retaining the complete identity/stats/metadata result.
local M = {}
local KEYS = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
local SHORT = { "hp", "atk", "def", "spe", "spa", "spd" }
local SOURCE = { "maxHp", "attack", "defense", "speed", "spAtk", "spDef" }
local SPECIES = {
  { 60, { 40, 50, 40, 90, 40, 40 }, 127, { 11, 6 } },
  { 303, { 1, 90, 45, 40, 30, 30 }, 255, { 25, 0 } },
}
function M.fixture(root, backend, version, format)
  local native = backend == "gen1"
  local ids = {}
  local function configure(data)
    data.constants = data.constants or {}
    data.constants.natureOrder, data.constants.natures = {}, {}
    for n = 0, 24 do
      local id = format .. "_NATURE_" .. n
      data.constants.natureOrder[n + 1] = id
      data.constants.natures[id] = { index = n, modifiers = {} }
      local order = { "attack", "defense", "speed", "spatk", "spdef" }
      local up, down = math.floor(n / 5) + 1, n % 5 + 1
      if up ~= down then
        data.constants.natures[id].modifiers[order[up]] = 110
        data.constants.natures[id].modifiers[order[down]] = 90
      end
    end
    for _, row in ipairs(SPECIES) do
      local n, base, ratio, pair = unpack(row)
      local id = format .. "_SPECIES_" .. n
      ids[n] = id
      if native then
        local p = data.gen3Pokemon
        p._names[n], p._stats[n], p._types[n] = id, {}, { 0, 0 }
        for i, k in ipairs(SHORT) do
          p._stats[n][k] = base[i]
        end
        p._speciesMeta[n] = { genderRatio = ratio, growthRate = 0, friendship = 70 }
        p._abilities[n], p._learnsets[n] = pair, { { 1, 33 } }
      else
        local def = require("src.mods.Merge").deepCopy(data.pokemon.CHARMANDER)
        def.id, def.index, def.name, def.genderRatio = id, n, id, ratio
        def.baseStats, def.evYield, def.growthRate, def.abilities = {}, {}, "MEDIUM_FAST", {}
        for i, k in ipairs(KEYS) do
          def.baseStats[k] = base[i]
        end
        for i, a in ipairs(pair) do
          if a ~= 0 then
            def.abilities[i] = "ABILITY_" .. a
          end
        end
        data.pokemon[id] = def
      end
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  f.codecIds = ids
  return f
end
function M.run(root, backend, version)
  local native, rows = backend == "gen1", {}
  for _, format in ipairs({ "canonical", "raw", "translated" }) do
    local f = M.fixture(root, backend, version, format)
    local T, Protocol = f.T, require("src.link.Protocol")
    for _, species in ipairs(SPECIES) do
      for _, realLevel in ipairs({ 1, 35, 100 }) do
        for nature = 0, 24 do
          for slot = 1, 2 do
            for _, investment in ipairs({ 0, 1, 2 }) do
              for _, forced in ipairs({ false, 50 }) do
                local pid = 100000 + nature
                pid = pid - pid % 25 + nature
                local ivs, evs = {}, {}
                for i, k in ipairs(KEYS) do
                  ivs[native and SHORT[i] or k] = investment == 0 and 0 or investment == 1 and 31 or i * 4
                  evs[native and SHORT[i] or k] = investment == 0 and 0
                    or investment == 1 and (i < 3 and 252 or i == 3 and 6 or 0)
                    or i * 12
                end
                local second = species[4][2] ~= 0 and slot == 2
                local mon = {
                  species = native and species[1] or f.codecIds[species[1]],
                  speciesNumbering = native and "internal" or nil,
                  level = realLevel,
                  exp = realLevel ^ 3 + (realLevel == 35 and 12 or 0),
                  hp = 1,
                  personality = pid,
                  ivs = ivs,
                  evs = evs,
                  nature = native and nature or f.data.constants.natureOrder[nature + 1],
                  abilitySlot = second and 2 or 1,
                  abilityNum = second and 1 or 0,
                  ability = native and species[4][second and 2 or 1] or nil,
                  moves = native and { 33 } or { { id = f.ids.TACKLE, pp = 6, ppUps = 3 } },
                  pp = native and { 6 } or nil,
                  ppBonusesPacked = native and 3 or nil,
                  otId = 1234,
                  otSecretId = 5678,
                  secretId = 5678,
                  ot = "TRAINER",
                  nickname = "PÖKEMON",
                  otGender = 1,
                  item = native and 0 or nil,
                  pokeball = 4,
                  happiness = 203,
                  friendship = 203,
                  contest = { cool = 7, beauty = 19, cute = 31, smart = 43, tough = 55, sheen = 67 },
                  language = 5,
                  gen3Language = 5,
                  pokerus = 35,
                  gen3Pokerus = 35,
                  markings = 9,
                  gen3Markings = 9,
                  ribbons = 123456,
                  metLevel = 12,
                  metLocation = 17,
                  metGame = 3,
                  status = "PAR",
                  fatefulEncounter = true,
                  modernFatefulEncounter = investment == 2 and true or nil,
                }
                if not native then
                  f.data.items.CODEC_BALL = { index = 4 }
                  mon.ball = "CODEC_BALL"
                end
                local before = require("src.link.Json").encode(mon)
                local packed = native and Protocol.packMon3(mon) or Protocol.packMon(mon)
                packed = require("src.link.Json").decode(require("src.link.Json").encode(packed))
                local restored, why
                if native then
                  restored, why =
                    Protocol.unpackMon3(f.data, packed, { strict = true, forceLevel = forced or nil })
                else
                  restored, why =
                    Protocol.unpackMon(f.data, packed, { strict = true, forceLevel = forced or nil })
                end
                T.check(restored ~= nil, "native party packet decodes: " .. tostring(why))
                assert(restored, why)
                T.eq(require("src.link.Json").encode(mon), before, "codec does not mutate sender")
                local stats, ivOut, evOut = {}, {}, {}
                for i, k in ipairs(KEYS) do
                  stats[i] = native and restored[SOURCE[i]] or restored.stats[k]
                  ivOut[i], evOut[i] =
                    restored.ivs[native and SHORT[i] or k], restored.evs[native and SHORT[i] or k]
                  T.eq(ivOut[i], ivs[native and SHORT[i] or k], "full six-stat IVs survive")
                  T.eq(evOut[i], evs[native and SHORT[i] or k], "full six-stat EVs survive")
                end
                T.eq(restored.personality, pid, "PID survives the actual wire path")
                T.eq(restored.hp, forced and stats[1] or 1, "forced level heals without changing genotype")
                if not forced then
                  T.eq(restored.status, "PAR", "ordinary status survives")
                end
                -- Lua's a-and-nil-or-b idiom cannot represent the forced nil.
                if forced then
                  T.eq(restored.status, nil, "forced-level status is cleared")
                end
                local ability = native and restored.ability or tonumber((restored.ability or ""):match("%d+"))
                T.eq(ability, species[4][second and 2 or 1], "stored valid ability slot survives")
                local gender = native and ({ M = "male", F = "female", U = "unknown" })[restored.gender]
                  or restored.gender
                local pp = native and restored.pp[1] or restored.moves[1].pp
                local maxPp = native and restored.maxPp[1] or restored.moves[1].maxPp
                rows[#rows + 1] = {
                  species = species[1],
                  format = format,
                  pid = restored.personality,
                  nature = native and restored.nature or restored.personality % 25,
                  gender = gender,
                  ability = ability,
                  stats = stats,
                  ivs = ivOut,
                  evs = evOut,
                  level = restored.level,
                  exp = restored.exp,
                  hp = restored.hp,
                  status = restored.status,
                  moves = { { 33, pp, maxPp } },
                  nickname = restored.nickname,
                  ot = restored.ot,
                  otId = restored.otId,
                  secretId = native and restored.otSecretId or restored.secretId,
                  friendship = restored.friendship,
                  contest = restored.contest,
                  language = native and restored.language or restored.gen3Language,
                  pokerus = native and restored.pokerus or restored.gen3Pokerus,
                  markings = native and restored.markings or restored.gen3Markings,
                  ribbons = restored.ribbons,
                  metLevel = restored.metLevel,
                  metLocation = restored.metLocation,
                  metGame = restored.metGame,
                  ball = native and restored.pokeball or f.data.items[restored.ball].index,
                  otGender = restored.otGender,
                  fatefulEncounter = restored.fatefulEncounter,
                  modernFatefulEncounter = restored.modernFatefulEncounter,
                }
              end
            end
          end
        end
      end
    end
    f.close()
  end
  return rows
end
return M
