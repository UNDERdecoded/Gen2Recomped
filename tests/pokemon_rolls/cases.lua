local C = {}
function C.run(root, backend, version, api, format)
  local Fixture = dofile(root .. "/tests/pokemon_rolls/fixture.lua")
  local V = require("src.core.GameVersion")
  local gen = V.generation(version)
  if gen ~= 2 and gen ~= 3 then
    local f = Fixture.new(root, backend, version, api, format, "delegate")
    f.T.eq(f.e.available, false, "identity hooks unavailable outside Gen 2/3")
    f.close()
    return { { mode = "unavailable", available = false } }
  end
  local rows = {}
  for _, mode in ipairs({
    "delegate",
    "force",
    "suppress",
    "nil",
    "invalid",
    "steer",
    "replacement",
    "iv_edit",
    "threshold",
    "invalid_threshold",
    "ratio_only",
    "new_threshold",
    "error_before",
    "error_after",
    "rollback",
    "no-mod",
  }) do
    for _, natural in ipairs({ false, true }) do
      local f = Fixture.new(root, backend, version, api, format, mode)
      f.T.eq(#f.result.errors > 0, mode == "rollback", "identity entry outcome")
      local mon = f.make(natural)
      local before = {
        personality = mon.personality,
        ivs = f.copy(mon.ivs),
        dvs = f.copy(mon.dvs),
        otId = mon.otId,
        otSecretId = mon.otSecretId,
      }
      local queryRandomCalls = 0
      local randomMath, randomLove = math.random, love.math.random
      math.random = function(...)
        queryRandomCalls = queryRandomCalls + 1
        return randomMath(...)
      end
      love.math.random = function(...)
        queryRandomCalls = queryRandomCalls + 1
        return randomLove(...)
      end
      local rngBefore = backend == "gen1" and gen == 3 and f.copy(require("src.core.game3.rng").getState())
        or nil
      local shiny, gender = f.shiny(mon), f.gender(mon)
      math.random, love.math.random = randomMath, randomLove
      if rngBefore then
        f.T.same(
          require("src.core.game3.rng").getState(),
          rngBefore,
          "native GBA RNG state unchanged by identity queries"
        )
      end
      f.T.eq(queryRandomCalls, 0, "identity queries do not draw random numbers")
      local row = {
        mode = mode,
        natural = natural,
        shiny = shiny,
        gender = gender,
        birthGender = ({ M = "male", F = "female", U = "unknown" })[mon.gender] or mon.gender,
      }
      if mode == "force" then
        f.T.eq(shiny, true, "hook forces actual shiny read")
        f.T.eq(gender, "female", "hook forces actual gender read")
      end
      if mode == "suppress" then
        f.T.eq(shiny, false, "hook suppresses actual shiny read")
        f.T.eq(gender, "male", "hook suppresses actual gender read")
      end
      if mode == "invalid" then
        f.T.eq(shiny, true, "Lua zero is truthy for shiny")
        f.T.eq(gender, natural and "female" or "male", "invalid gender falls back to native")
      end
      if mode == "nil" then
        f.T.eq(shiny, false, "nil shiny becomes false")
        f.T.eq(gender, natural and "female" or "male", "nil gender falls back to native")
      end
      if mode == "new_threshold" or mode == "threshold" then
        f.T.eq(gender, "female", "definition threshold reaches native gender predicate")
      end
      if mode == "invalid_threshold" then
        f.T.eq(
          gender,
          gen == 2 and "female" or natural and "female" or "male",
          "invalid gender fallback keeps native generation timing"
        )
      end
      if mode == "ratio_only" then
        f.T.eq(
          gender,
          natural and "female" or "male",
          "ratio metadata alone does not replace definition threshold"
        )
      end
      if mode == "steer" or mode == "replacement" then
        f.T.eq(shiny, true, "DV/PID context can steer native shiny predicate")
        f.T.eq(gender, "female", "DV/PID context can steer native gender predicate")
      end
      local after = {
        personality = mon.personality,
        ivs = f.copy(mon.ivs),
        dvs = f.copy(mon.dvs),
        otId = mon.otId,
        otSecretId = mon.otSecretId,
      }
      f.T.same(after, before, "identity queries do not mutate saved genes")
      local e = f.e
      if not (e and e.calls) then
        row.birthGender = nil
      end
      if e and e.calls then
        row.shinyCalls, row.genderCalls = e.calls["shiny.roll"] or 0, e.calls["gender.roll"] or 0
        if api == 3 then
          local obs = e.observations["gender.roll"]
          f.T.eq(obs.species, "CHARMANDER", "API-3 species ID is common")
          f.T.eq(obs.defId, "CHARMANDER", "API-3 definition ID is common")
          row.genderContext = obs
          row.shinyContext = e.observations["shiny.roll"]
        end
        e.stopShiny()
        e.stopGender()
        local calls = f.copy(e.calls)
        if gen == 2 then
          if backend == "gen1" then
            require("src.battle.gen2.Mon").syncIdentity(mon, f.data)
          else
            require("src.pokemon.Pokemon").syncIdentity(f.data, mon)
          end
        end
        row.retiredShiny, row.retiredGender = f.shiny(mon), f.gender(mon, true)
        f.T.same(e.calls, calls, "unsubscribe stops later query and refresh dispatch")
      end
      rows[#rows + 1] = row
      f.close()
    end
  end
  for _, forced in ipairs({ true, false }) do
    local f = Fixture.new(root, backend, version, api, format, forced and "suppress" or "force")
    local mon = f.make(false, forced)
    local value = f.shiny(mon)
    f.T.eq(value, gen == 2 and true or forced, "forced shiny precedence follows native generation")
    rows[#rows + 1] =
      { mode = "forced", forced = forced, shiny = value, shinyCalls = f.e.calls["shiny.roll"] or 0 }
    f.close()
  end
  if gen == 3 then
    local edges = {
      { pid = 0, ot = 0, yes = true },
      { pid = 7, ot = 0, yes = true },
      { pid = 8, ot = 0, yes = false },
      { pid = 65536, ot = 65536, yes = true },
      { pid = 65536, ot = 0, sid = 1, yes = true },
      { pid = 0, ot = 0, sid = 65535, yes = false },
      { pid = 0, trainer = 7, yes = true },
      { pid = 4294967295, ot = 0, yes = true },
    }
    for _, mode in ipairs({ "no-mod", "delegate" }) do
      for index, edge in ipairs(edges) do
        local f = Fixture.new(root, backend, version, api, format, mode)
        local mon = f.make(false)
        mon.personality, mon.otId, mon.otSecretId, mon.trainerId = edge.pid, edge.ot, edge.sid, edge.trainer
        local value = f.shiny(mon)
        f.T.eq(value, edge.yes, "native GBA shiny XOR threshold and trainer-ID layouts")
        rows[#rows + 1] = { mode = "gba_trainer_identity", policy = mode, case = index, shiny = value }
        f.close()
      end
    end
  end
  if version == "gold" then
    local f = Fixture.new(root, backend, version, api, format, "no-mod")
    local def = f.data.pokemon[backend == "gen1" and "CHARMANDER" or "SPECIES_004"]
    local native = backend == "gen1" and require("src.battle.gen2.Mon") or require("src.pokemon.DayCare")
    local bit = require("bit")
    local hash, female, male, unknown = 0, 0, 0, 0
    local outcomes = {}
    for ratio = 0, 255 do
      def.genderRatio = ratio
      for attack = 0, 15 do
        for speed = 0, 15 do
          local dvs = { attack = attack, speed = speed }
          local g = backend == "gen1" and native.gender(def, dvs)
            or native.gender(f.data, { species = "SPECIES_004", dvs = dvs })
          local code = g == "female" and 1 or g == "male" and 2 or 3
          female = female + (code == 1 and 1 or 0)
          male = male + (code == 2 and 1 or 0)
          unknown = unknown + (code == 3 and 1 or 0)
          hash = bit.bxor(bit.rol(hash, 5), code)
          outcomes[#outcomes + 1] = tostring(code)
        end
      end
    end
    rows[#rows + 1] = {
      mode = "native_gender_matrix",
      hash = hash,
      female = female,
      male = male,
      unknown = unknown,
      cases = 65536,
      outcomes = table.concat(outcomes),
    }
    f.close()
  end
  return rows
end
return C
