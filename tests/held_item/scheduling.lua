local M = {}
function M.run(f)
  if f.gen ~= 3 then
    return {}
  end
  local T, rows, trace = f.T, {}, {}
  local off = f.e.api.hooks:wrap("held_item.trigger", function(next, ctx)
    if ctx.trigger == "residual" then
      trace[#trace + 1] = ctx.mon.nickname
    end
    return next(ctx)
  end, 100)
  local function reset(item)
    f.reset(item)
    trace = {}
  end
  local function observe(label, expected)
    for key, value in pairs(expected) do
      local got = key == "reads" and table.concat(trace, ",")
        or key == "player" and f.mon("player").hp
        or key == "enemy" and f.mon("enemy").hp
        or key == "pp" and f.pp()
      T.eq(got, value, "native schedule " .. label .. ":" .. key)
    end
    local row = { label = label }
    for key, value in pairs(expected) do
      row[key] = value
    end
    rows[#rows + 1] = row
  end
  local function grant(effect, parameter, holder)
    local s = f.e.state
    s.mode, s.trigger, s.holder, s.requiresItem = "override", "residual", holder, false
    s.effect, s.parameter = effect, parameter
  end
  local function speed(player, enemy)
    if f.backend == "gen1" then
      f.mon("player").speed, f.mon("enemy").speed = player, enemy
    else
      f.battle.player.curStats.speed, f.battle.enemy.curStats.speed = player, enemy
    end
  end
  local function poison()
    f.mon("player").status = "PSN"
    if f.backend == "gen1" then
      f.battle.player.status = "PSN"
    end
  end
  local function synthetic(effect)
    for _, row in ipairs(f.catalog) do
      if row[3] == effect then
        return row[1]
      end
    end
    error("missing effect " .. effect)
  end
  reset()
  speed(100, 10)
  f.mon("player").hp = 100
  grant("HELD_BERRY", 7, "PLAYER")
  f.residual()
  observe("residual retry", { player = 135, reads = "PLAYER,ENEMY,PLAYER,PLAYER,PLAYER,PLAYER" })

  reset()
  speed(100, 10)
  f.mon("player").hp, f.mon("enemy").hp = 100, 100
  grant("HELD_BERRY", 7)
  f.residual()
  observe(
    "first successful slot restarts",
    { player = 135, enemy = 107, reads = "PLAYER,ENEMY,PLAYER,PLAYER,PLAYER,PLAYER" }
  )

  reset()
  f.mon("player").hp = 100
  grant("HELD_BERRY", 7, "PLAYER")
  f.attack()
  observe("move then after action", { player = 128, reads = "PLAYER,ENEMY,PLAYER,PLAYER,PLAYER,PLAYER" })

  reset()
  f.mon("player").hp = 100
  grant("HELD_BERRY", 7, "PLAYER")
  f.attack(true)
  observe("called move has no separate action", { player = 100, reads = "PLAYER,ENEMY" })

  reset("LEPPA_BERRY")
  f.pp(1)
  f.attack()
  observe("PP restores after move", { pp = 10 })
  T.check(not f.mon("player").item or f.mon("player").item == 0, "native Leppa consumed")

  reset()
  f.pp(0)
  grant("HELD_RESTORE_PP", 16, "PLAYER")
  f.residual()
  observe("PP restoration respects move cap", { pp = 10 })

  reset()
  f.mon("player").hp = 100
  grant("HELD_BERRY", 7, "PLAYER")
  f.mon("player").status = "PAR"
  if f.backend == "gen1" then
    f.battle.player.status = "PAR"
  end
  f.resolve("TACKLE", true)
  observe(
    "canceled action still checks items",
    { player = 128, reads = "PLAYER,ENEMY,PLAYER,PLAYER,PLAYER,PLAYER" }
  )

  reset(synthetic("CURE_PSN"))
  f.mon("player").hp = 20
  poison()
  f.residual()
  observe("cure precedes lethal poison", { player = 20 })
  T.check(not f.mon("player").status, "native poison cure")

  reset("ORAN_BERRY")
  f.mon("player").hp = 20
  poison()
  f.residual()
  observe("HP berry cannot revive poison faint", { player = 0 })
  T.check(not f.mon("player").item or f.mon("player").item == 0, "berry consumed before poison faint")

  reset()
  f.mon("player").hp = 200
  poison()
  grant("HELD_BERRY", 7, "PLAYER")
  f.residual()
  -- Normal Berry triggers at 200, poison subtracts 50, then four retries.
  observe("normal item before chip and retries after", { player = 185 })

  reset("LEFTOVERS")
  f.mon("player").hp = 20
  if f.backend == "gen1" then
    f.battle.player.expIngrain = true
  else
    f.battle.player.ingrained = true
  end
  poison()
  f.residual()
  observe("Ingrain item then poison", { player = 20 })

  reset("LEFTOVERS")
  f.mon("player").hp, f.mon("enemy").hp = 200, 200
  poison()
  if f.backend == "gen1" then
    f.battle.player.expSeeded, f.battle.player.expSeedSource = true, f.battle.enemy
  else
    f.battle.player.leechSeeded, f.battle.player.leechSeedSource = true, f.battle.enemy
  end
  f.residual()
  observe("item then seed then poison", { player = 125, enemy = 250 })

  reset("LEFTOVERS")
  f.mon("player").hp, f.mon("enemy").hp = 200, 100
  local previous = f.battle.enemy
  local replacement = require("src.mods.Merge").deepCopy(previous.mon)
  if f.backend == "gen1" then
    f.battle.player.expSeeded, f.battle.player.expSeedSource = true, previous
    f.battle.enemy = require("src.core.game3.battle.state").makeBattler(replacement, "enemy", { id = 1 })
  else
    f.battle.player.leechSeeded, f.battle.player.leechSeedSource = true, previous
    f.battle.enemy = require("src.battle.BattleState").makeBattler(f.data, replacement, false, nil, f.battle)
    f.battle:syncSides()
  end
  f.residual()
  T.eq(previous.mon.hp, 100, "withdrawn seed source does not receive healing")
  observe("seed heals current occupant", { player = 175, enemy = 150 })

  reset()
  speed(100, 10)
  f.mon("player").hp, f.mon("enemy").hp = 100, 20
  if f.backend == "gen1" then
    f.battle.player.expSeeded, f.battle.player.expSeedSource = true, f.battle.enemy
    f.battle.player.ability = "LIQUID_OOZE"
  else
    f.battle.player.leechSeeded, f.battle.player.leechSeedSource = true, f.battle.enemy
    f.battle.player.abilityOverride = "LIQUID_OOZE"
  end
  f.residual()
  observe("Liquid Ooze faints seed source", { player = 50, enemy = 0 })
  if f.backend == "gen2" then
    T.check(f.battle.enemy.faintQueued, "seed source uses native faint queue")
  end

  reset("LEFTOVERS")
  speed(100, 10)
  f.mon("player").hp = 20
  if f.backend == "gen1" then
    f.battle.playerSide.tokens = { { id = "EXP_WISH", turns = 1 } }
    f.battle.weather, f.battle.weatherTurns = "SAND", 2
  else
    f.battle.player.wishTurns = 1
    f.battle.field.weather, f.battle.field.weatherTurns = "SANDSTORM", 2
  end
  f.residual()
  observe("Wish before weather and Leftovers", { player = 220, enemy = 375 })

  for _, speeds in ipairs({
    { 100, 10, "PLAYER,ENEMY,PLAYER,ENEMY" },
    { 10, 100, "ENEMY,PLAYER,PLAYER,ENEMY" },
    { 50, 50, "PLAYER,ENEMY,PLAYER,ENEMY" },
  }) do
    reset()
    speed(speeds[1], speeds[2])
    f.residual()
    observe("residual speed " .. speeds[1] .. ":" .. speeds[2], { reads = speeds[3] })
  end

  for _, effect in ipairs({ "ATTACK_UP", "RANDOM_STAT_UP", "CRITICAL_UP" }) do
    reset(synthetic(effect))
    f.mon("player").hp = 10
    local p = f.battle.player
    for _, stat in ipairs({ "attack", "defense", "speed", "spatk", "spdef", "spAtk", "spDef" }) do
      p.stages[stat] = 6
    end
    p.focusEnergy = true
    local held = f.mon("player").item
    f.residual()
    T.eq(f.mon("player").item, held, "ineligible pinch effect is not consumed: " .. effect)
    observe("ineligible " .. effect, { player = 10 })
  end
  reset()
  f.mon("player").hp = 100
  speed(100, 10)
  grant("HELD_BERRY", 0, "PLAYER")
  f.residual()
  observe(
    "zero heal still activates bounded retries",
    { player = 100, reads = "PLAYER,ENEMY,PLAYER,PLAYER,PLAYER,PLAYER" }
  )
  reset()
  f.mon("player").hp = 100
  grant("HELD_BERRY", 7, "PLAYER")
  if f.backend == "gen1" then
    f.battle.player.expLastTakenMove = 33
  else
    f.battle.enemy.lastMove = f.ids.TACKLE
  end
  f.resolve("MIRROR_MOVE", true)
  observe(
    "nested Mirror Move has one action sweep",
    { player = 128, reads = "PLAYER,ENEMY,PLAYER,PLAYER,PLAYER,PLAYER" }
  )

  for _, spread in ipairs({ false, true }) do
    f.reset(nil, true)
    trace = {}
    for id = 0, 3 do
      local actor = f.actor(id)
      actor.mon.hp, actor.mon.maxHp = 400, 400
      actor.mon.stats = actor.mon.stats or {}
      actor.mon.stats.hp = 400
      actor.mon.nickname = ({ "PLAYER", "ENEMY", "ALLY", "FOE" })[id + 1]
    end
    f.mon("player").hp = 100
    grant("HELD_BERRY", 7, "PLAYER")
    f.resolve(spread and "SURF" or "TACKLE", true)
    local selective = "PLAYER,ENEMY,ALLY,FOE,"
    observe(
      spread and "spread has one action sweep" or "double action slot order",
      { player = 128, reads = selective .. (spread and selective or "") .. "PLAYER,PLAYER,PLAYER,PLAYER" }
    )
  end
  f.reset(nil, true)
  trace = {}
  for id = 0, 3 do
    local actor = f.actor(id)
    actor.mon.hp, actor.mon.maxHp = 100, 400
    actor.mon.stats = actor.mon.stats or {}
    actor.mon.stats.hp = 400
    actor.mon.nickname = ({ "PLAYER", "ENEMY", "ALLY", "FOE" })[id + 1]
    if f.backend == "gen1" then
      actor.mon.speed = 100 - id * 10
    else
      actor.curStats.speed = 100 - id * 10
    end
  end
  grant("HELD_BERRY", 7)
  f.residual()
  observe(
    "double residual retries first slot",
    { player = 135, enemy = 107, reads = "PLAYER,ENEMY,ALLY,FOE,PLAYER,PLAYER,PLAYER,PLAYER" }
  )
  T.eq(f.actor(2).mon.hp, 107, "ally receives normal item phase")
  T.eq(f.actor(3).mon.hp, 107, "second foe receives normal item phase")

  off()
  f.e.state.requiresItem = true
  return rows
end
return M
