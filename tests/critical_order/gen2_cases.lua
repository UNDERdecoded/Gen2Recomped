-- Same public critical consumer through both native Gen-2 move pipelines.
return function(root, backend, version, api)
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
      data.constants = data.constants or {}
      data.constants.generation = 2
    end
  )
  local T, rows = f.T, {}
  T.eq(f.e.available, true, "real Gen-2 critical producer is available")
  f.game.input.wasPressed = function(_, key)
    return key == "a"
  end
  f.game.input.isDown = function(_, key)
    return key == "a"
  end
  for _, enemy in ipairs({ false, true }) do
    for _, level in ipairs({ 1, 3, 29, 30, 99, 100 }) do
      for _, critical in ipairs({ false, true }) do
        for _, stab in ipairs({ false, true }) do
          for _, roll in ipairs({ 217, 255 }) do
            local s = f.fresh("TACKLE", { enemy = enemy })
            for _, who in ipairs({ s.user, s.target }) do
              local mon = native and who or who.mon
              mon.level, mon.hp, mon.maxHp = 30, 400, 400
              mon.stats = {
                hp = 400,
                attack = 50,
                defense = 50,
                speed = 50,
                special = 50,
                spatk = 50,
                spdef = 50,
                specialAttack = 50,
                specialDefense = 50,
              }
              if not native then
                who.curStats = mon.stats
              end
            end
            local user = native and s.user or s.user.mon
            user.level = level
            if native then
              s.battle:volatile(s.user).types = { stab and "NORMAL" or "GRASS" }
              s.battle:volatile(s.target).types = { "NORMAL" }
              s.battle.random = function(n)
                return n == 39 and roll - 217 or 0
              end
            else
              s.user.curTypes, s.target.curTypes = { stab and "NORMAL" or "GRASS" }, { "NORMAL" }
              s.battle.rng = function(lo, hi)
                return lo == 217 and hi == 255 and roll or lo or 0
              end
            end
            f.e.state.critical, f.e.state.calls = critical, 0
            local before = s.hp()
            s.use()
            if not native then
              local count = 0
              while s.battle:updateQueue() do
                count = count + 1
                assert(count < 10000, "Gen-2 move queue did not settle")
              end
            end
            local amount = before - s.hp()
            T.eq(s.pp(), 9, "Gen-2 native move spends one PP on either side")
            T.eq(f.e.state.calls, 1, "one public critical decision per Gen-2 move")
            if level == 29 and critical and not stab and roll == 217 then
              T.eq(amount, 17, "Gen-2 level-29 critical regression through native pipeline")
            end
            rows[#rows + 1] = {
              enemy = enemy,
              level = level,
              critical = critical,
              stab = stab,
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
