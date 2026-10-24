local M = {}
function M.run(f)
  local T, e, rows = f.T, f.e, {}
  local function observe(label, player, enemy)
    f.run()
    T.eq(e.state.calls, 1, "ordinary native residual phase invokes public hook once")
    local ctx = e.state.last
    T.eq(f.hp("player"), ctx.battlers.player.hp - player, "native player HP follows accepted descriptor")
    T.eq(f.hp("enemy"), ctx.battlers.enemy.hp - enemy, "native enemy HP follows accepted descriptor")
    for _, side in ipairs({ "player", "enemy" }) do
      T.eq(ctx.battlers[side].name, "PROBE", "native display name in detached snapshot")
      T.eq(ctx.battlers[side].maxHp, 400, "native maximum HP in detached snapshot")
    end
    T.eq(ctx.turn, 1, "current native turn in detached field context")
    T.eq(ctx.battle, nil, "field context contains no live battle handle")
    T.eq(ctx.field.tokens[1].onExpire, nil, "field callback is absent")
    T.eq(ctx.field.tokens[1].state.intensity, 4, "portable extension data survives")
    rows[#rows + 1] = {
      label = label,
      playerDamage = player,
      enemyDamage = enemy,
      turn = ctx.turn,
      tokens = ctx.field.tokens[1].state.intensity,
      playerSide = ctx.battlers.player.side,
      enemySide = ctx.battlers.enemy.side,
      types = ctx.battlers.player.types,
    }
  end
  observe("default", 0, 0)
  f.reset()
  e.state.calls = 0
  e.state.requests = {
    { side = "enemy", amount = 3, message = "Field enemy" },
    { side = "player", amount = 5, message = "Field player" },
    { side = "enemy", amount = 2 },
  }
  observe("batch", 5, 5)
  f.reset()
  e.state.calls = 0
  e.state.requests = {
    { side = "enemy", amount = -1 },
    { side = "player", amount = 1.5 },
    { side = "enemy", amount = math.huge },
    { side = "enemy", amount = 0 / 0 },
    { side = "other", amount = 1 },
    { side = "player", amount = 1, message = {} },
    { side = "enemy", amount = 4, message = "" },
  }
  observe("validation", 0, 4)
  f.reset()
  e.state.calls = 0
  e.state.mode, e.state.invalid = "invalid", false
  observe("non table", 0, 0)
  f.reset()
  e.state.calls = 0
  e.state.mode, e.state.invalid = "invalid", nil
  observe("nil", 0, 0)
  for _, after in ipairs({ false, true }) do
    f.reset()
    e.state.calls = 0
    local off = e.api.hooks:wrap("battle.field_residual", function(next, ctx)
      if after then
        next(ctx)
      end
      error("intentional field wrapper failure")
    end, 100)
    e.state.requests = { { side = "enemy", amount = 1 } }
    observe("error:" .. tostring(after), 0, 1)
    off()
  end
  if f.api >= 3 then
    f.reset()
    e.state.calls = 0
    local off = e.api.hooks:wrap("battle.field_residual", function(next, ctx)
      local a, b = next(ctx), next(ctx)
      T.eq(a, b, "API-3 repeated next returns same downstream result")
      return a
    end, 100)
    e.state.requests = { { side = "player", amount = 1 } }
    observe("replay", 1, 0)
    off()
  end
  f.reset()
  e.state.calls = 0
  e.state.mode = "mutate"
  f.run()
  T.check(f.hp("player") > 0, "context HP mutation cannot replace native HP")
  T.eq(f.battle.field.tokens[1].state.intensity, 4, "nested token mutation stays detached")
  rows[#rows + 1] =
    { label = "detached", live = f.hp("player") > 0, tokens = f.battle.field.tokens[1].state.intensity }
  if f.gen > 1 then
    for _, expiry in ipairs({ false, true }) do
      f.reset()
      local b = f.battle
      if f.backend == "gen1" then
        b.weather, b.weatherTurns = f.gen == 2 and "sun" or "SUN", expiry and 1 or 3
      else
        b.field.weather, b.field.weatherTurns = "SUN", expiry and 1 or 3
      end
      f.run()
      local expected = not expiry and (f.gen == 2 and "sun" or "SUN") or nil
      T.eq(e.state.last.field.weather, expected, "field hook observes native weather upkeep first")
      rows[#rows + 1] = { label = "weather:" .. tostring(expiry), weather = e.state.last.field.weather }
    end
  end
  f.reset()
  e.state.requests = { { side = "enemy", amount = 99999, message = "Field KO" } }
  f.run()
  T.eq(f.hp("enemy"), 0, "field damage clamps at zero")
  T.eq(e.state.faints, 1, "native field KO emits faint once")
  rows[#rows + 1] = { label = "enemy KO", enemy = f.hp("enemy"), faints = e.state.faints }
  if f.gen == 3 then
    f.reset()
    if f.backend == "gen1" then
      f.battle.player.type1, f.battle.player.type2 = 14, 14
    else
      f.battle.player.curTypes = { "PSYCHIC_TYPE" }
    end
    f.run()
    T.same(e.state.last.battlers.player.types, { "PSYCHIC", "PSYCHIC" }, "GBA native Psychic type pair")
    rows[#rows + 1] = { label = "psychic", types = e.state.last.battlers.player.types }
    f.reset({ double = true })
    e.state.requests = {
      { side = "player", battlerId = 2, amount = 7 },
      { side = "enemy", battler = 3, amount = 9 },
      { side = "player", battlerId = 3, amount = 80 },
      { side = "enemy", battlerId = 2, amount = 80 },
      { side = "enemy", battlerId = "3", amount = 80 },
      { side = "enemy", battlerId = 4, amount = 80 },
      { side = "enemy", amount = 2 },
    }
    f.run()
    local ctx = e.state.last
    for id = 0, 3 do
      T.eq(ctx.battlers[id].battlerId, id, "GBA snapshot carries actual native slot ID")
      T.eq(f.actor(id).mon.hp, 400 - ({ [0] = 0, 2, 7, 9 })[id], "GBA descriptors target correct flank")
    end
    T.eq(ctx.battlers.player.battlerId, 0, "player alias is left flank")
    T.eq(ctx.battlers.enemy.battlerId, 1, "enemy alias is left flank")
    f.run()
    T.eq(e.state.calls, 1, "GBA same native turn dispatches once")
    T.eq(f.actor(2).mon.hp, 393, "GBA duplicate phase cannot replay damage")
    rows[#rows + 1] = {
      label = "doubles",
      calls = e.state.calls,
      player = f.actor(2).mon.hp,
      enemy = f.actor(3).mon.hp,
      left = f.actor(1).mon.hp,
    }
    for _, reverse in ipairs({ false, true }) do
      f.reset({ double = true })
      e.state.requests = {}
      local mons = {}
      for id = 0, 3 do
        mons[id] = f.actor(id).mon
        local target = reverse and 3 - id or id
        e.state.requests[#e.state.requests + 1] =
          { side = target % 2 == 0 and "player" or "enemy", battlerId = target, amount = 99999 }
      end
      f.run()
      for id = 0, 3 do
        T.eq(mons[id].hp, 0, "native terminal double batch settles every target")
      end
      T.eq(e.state.faints, 2, "native terminal double batch emits only player faints")
      T.eq(e.state.awards, 0, "native terminal double batch cannot award enemy EXP")
      rows[#rows + 1] = {
        label = "double terminal:" .. tostring(reverse),
        faints = e.state.faints,
        awards = e.state.awards,
      }
    end
    for _, ownDown in ipairs({ false, true }) do
      local b = f.reset({ double = true })
      if f.backend == "gen1" then
        b.playerHalf = 1
      else
        b.ally = { party = { f.actor(2).mon } }
        b.playerParty = { f.actor(0).mon }
        f.game.save.party = b.playerParty
      end
      if ownDown then
        f.actor(0).mon.hp = 0
      end
      e.state.requests = {
        { side = "player", battlerId = 0, amount = 99999 },
        { side = "enemy", battlerId = 1, amount = 99999 },
        { side = "enemy", battlerId = 3, amount = 99999 },
      }
      f.run()
      T.eq(e.state.calls, ownDown and 0 or 1, "GBA field authority checks player's own party")
      T.eq(f.actor(2).mon.hp, 400, "GBA partner survives player's own-party terminal batch")
      T.eq(e.state.awards, 0, "GBA partner cannot authorize terminal enemy EXP")
      if not ownDown then
        T.eq(e.state.faints, 1, "GBA own-party terminal batch suppresses enemy faint processing")
        if f.backend == "gen2" then
          f.drain()
          T.eq(b.result, "lose", "native ally cannot prevent own-party field loss")
        end
      end
      rows[#rows + 1] = {
        label = "allied:" .. tostring(ownDown),
        calls = e.state.calls,
        partner = 400,
        awards = e.state.awards,
      }
    end
    for _, what in ipairs({ "turn", "mon", "hooks" }) do
      f.reset({ double = true })
      local Runtime = require("src.mods.Runtime")
      local hooks = Runtime.hooks
      local off = e.api.hooks:wrap("battle.field_residual", function(next, ctx)
        local result = next(ctx)
        if what == "turn" then
          if f.backend == "gen1" then
            f.battle.turn = f.battle.turn + 1
          else
            f.battle.turnCount = f.battle.turnCount + 1
          end
        elseif what == "mon" then
          f.actor(2).mon = require("src.mods.Merge").deepCopy(f.actor(2).mon)
        else
          Runtime.hooks = {}
        end
        return result
      end, 100)
      e.state.requests = { { side = "player", battlerId = 2, amount = 8 } }
      f.run()
      Runtime.hooks = hooks
      off()
      T.eq(f.actor(2).mon.hp, 400, "GBA stale callback cannot damage replacement/next turn")
      rows[#rows + 1] = { label = "stale:" .. what, hp = f.actor(2).mon.hp }
    end
  end
  for _, reverse in ipairs({ false, true }) do
    f.reset()
    local p, n = { side = "player", amount = 99999 }, { side = "enemy", amount = 99999 }
    e.state.requests = reverse and { n, p } or { p, n }
    f.run()
    T.eq(f.hp("player"), 0, "terminal batch clamps player HP")
    T.eq(f.hp("enemy"), 0, "terminal batch clamps enemy HP")
    f.drain()
    T.eq(e.state.awards, 0, "terminal field batch never awards enemy EXP")
    T.eq(e.state.faints, f.gen == 2 and 2 or 1, "native terminal faint announcements")
    if f.backend == "gen2" or f.gen < 3 then
      T.eq(f.battle.result or f.battle.outcome, "lose", "native terminal field batch resolves as loss")
    end
    rows[#rows + 1] = {
      label = "terminal:" .. tostring(reverse),
      player = f.hp("player"),
      enemy = f.hp("enemy"),
      awards = e.state.awards,
      faints = e.state.faints,
    }
  end
  e.stop()
  e.stop()
  f.reset()
  local calls = e.state.calls
  f.run()
  T.eq(e.state.calls, calls, "unsubscribe removes field callback")
  rows[#rows + 1] = { label = "unsubscribed", calls = e.state.calls - calls }
  return rows
end
return M
