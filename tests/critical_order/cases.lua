return function(root, backend, version, api)
  if version == "gold" or version == "silver" or version == "crystal" then
    return dofile(root .. "/tests/critical_order/gen2_cases.lua")(root, backend, version, api)
  end
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/charge_required/fixture.lua").new(
    root,
    backend,
    version,
    api,
    "unified",
    false,
    false,
    "portable_critical_order",
    function(data)
      if not native then
        data.type_chart.matchups = {
          { attacker = "NORMAL", defender = "ROCK", multiplier = 5 },
          { attacker = "NORMAL", defender = "STEEL", multiplier = 5 },
          { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
        }
      end
    end
  )
  local T, rows = f.T, {}
  f.game.input.wasPressed = function(_, key)
    return key == "a"
  end
  f.game.input.isDown = function(_, key)
    return key == "a"
  end
  T.eq(f.e.available, true, "real public critical producer is available")
  for _, enemy in ipairs({ false, true }) do
    for _, critical in ipairs({ false, true }) do
      for _, stab in ipairs({ false, true }) do
        for _, types in ipairs({ { "NORMAL" }, { "STEEL" }, { "ROCK", "STEEL" }, { "GHOST" } }) do
          for _, roll in ipairs({ 85, 92, 100 }) do
            local s = f.fresh("TACKLE", { enemy = enemy })
            local ids = { NORMAL = 0, ROCK = 5, GHOST = 7, STEEL = 8, FIRE = 10 }
            for _, who in ipairs({ s.user, s.target }) do
              if native then
                for _, key in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do
                  who.mon[key] = 50
                end
              else
                who.mon.stats = {
                  hp = 400,
                  attack = 50,
                  defense = 50,
                  speed = 50,
                  special = 50,
                  spatk = 50,
                  spdef = 50,
                }
                who.curStats = who.mon.stats
              end
            end
            if native then
              s.user.type1, s.user.type2 = stab and 0 or 10, stab and 0 or 10
              s.target.type1, s.target.type2 = ids[types[1]], ids[types[2] or types[1]]
            else
              s.user.curTypes, s.target.curTypes = { stab and "NORMAL" or "FIRE" }, types
            end
            s.battle.rng = function(lo, hi)
              if lo == 85 and hi == 100 then
                return roll
              end
              return lo or 0
            end
            f.e.state.critical, f.e.state.calls = critical, 0
            local before = s.hp()
            s.use()
            if not native then
              local count = 0
              while s.battle:updateQueue() do
                count = count + 1
                assert(count < 10000, "native move queue did not settle")
              end
            end
            local amount = before - s.hp()
            T.eq(s.pp(), 9, "native move spends one PP, including immunity")
            T.eq(f.e.state.calls, 1, "one real public critical decision per move")
            if critical and not stab and #types == 1 and types[1] == "STEEL" and roll == 85 then
              T.eq(amount, 9, "critical Steel regression through real move pipeline")
            end
            rows[#rows + 1] = {
              enemy = enemy,
              critical = critical,
              stab = stab,
              types = types,
              roll = roll,
              amount = amount,
              pp = s.pp(),
              calls = f.e.state.calls,
            }
          end
        end
      end
    end
  end
  f.close()
  return rows
end
