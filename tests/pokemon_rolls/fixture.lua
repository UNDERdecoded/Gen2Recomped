local F = {}
function F.new(root, backend, version, api, format, mode)
  local f = dofile(root .. "/tests/charge_required/fixture.lua").new(
    root,
    backend,
    version,
    api,
    format,
    mode == "no-mod",
    mode == "rollback",
    "portable_pokemon_rolls",
    function(data, gen)
      if backend == "gen2" then
        data.constants.generation = gen
        local def = data.pokemon.CHARMANDER
        def.genderRatio = gen == 3 and 31 or 127
        if gen == 3 then
          def.baseStats = { hp = 80, attack = 50, defense = 50, speed = 50, spatk = 50, spdef = 50 }
          def.evYield = { hp = 0, attack = 0, defense = 0, speed = 0, spatk = 0, spdef = 0 }
        end
        def.id = "SPECIES_004"
        data.pokemon.SPECIES_004, data.pokemon.CHARMANDER = def, nil
      elseif gen == 3 then
        data.gen3Pokemon._speciesMeta[4].genderRatio = 31
      end
    end,
    function(files)
      local J = require("src.link.Json")
      local base = "mods/portable_pokemon_rolls/"
      local manifest = J.decode(files[base .. "manifest.json"])
      manifest.games = { version }
      manifest.content_format = format
      files[base .. "manifest.json"] = J.encode(manifest)
      files[base .. "case.txt"] = mode
    end
  )
  f.copy = require("src.mods.Merge").deepCopy
  function f.make(shiny, forced)
    local dvs = shiny and { attack = 2, defense = 10, speed = 10, special = 10 }
      or { attack = 15, defense = 0, speed = 0, special = 0 }
    if backend == "gen1" and f.gen == 2 then
      return require("src.battle.gen2.Mon").new(f.data, "CHARMANDER", 5, { dvs = dvs, shiny = forced })
    elseif backend == "gen1" and f.gen == 3 then
      local session =
        { party = {}, name = "PROBE", version = version, trainerId = 0, secretId = 0, mapSec = 1 }
      local ok, _, mon = require("src.core.game3.party").giveMon(
        session,
        4,
        5,
        "",
        { fixedPersonality = shiny and 0 or 65791 }
      )
      assert(ok and mon, "native GBA Party.giveMon failed")
      if forced ~= nil then
        mon.isShiny = forced
      end
      return mon
    end
    local sequence = { dvs.attack, dvs.defense, dvs.speed, dvs.special }
    if f.gen == 3 then
      sequence[5], sequence[6] = shiny and 0 or 1, shiny and 0 or 255
    end
    local index = 0
    local mon = require("src.pokemon.Pokemon").new(f.data, "SPECIES_004", 5, function(lo)
      index = index + 1
      return sequence[index] or lo or 0
    end, nil, { shiny = forced })
    if f.gen == 3 then
      mon.otId, mon.otSecretId = 0, 0
      if forced ~= nil then
        mon.isShiny = forced
      end
    end
    return mon
  end
  function f.shiny(mon)
    if backend == "gen1" then
      if f.gen == 2 then
        return mon.shiny
      end
      return require("src.core.game3.pokemon").isShiny(mon)
    end
    return require("src.pokemon.Pokemon").isShiny(mon)
  end
  function f.gender(mon, query)
    if backend == "gen1" then
      if f.gen == 2 then
        return query and require("src.core.gen2.Breeding").genderOf(f.data, mon) or mon.gender
      end
      local g = require("src.core.game3.pokemon").gender(mon.species, mon.personality)
      return ({ M = "male", F = "female", U = "unknown" })[g]
    end
    local g = (query or f.gen == 3) and require("src.pokemon.DayCare").gender(f.data, mon)
      or require("src.pokemon.Pokemon").genderOf(f.data, mon)
    return g == "none" and "unknown" or g
  end
  return f
end
return F
