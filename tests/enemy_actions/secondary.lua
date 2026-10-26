local M = {}
local EFFECTS = {
  { "poison", 2, "POISON_SIDE_EFFECT1", "POISON", { status = "PSN" } },
  { "burn", 4, "BURN_SIDE_EFFECT1", "BURN", { status = "BRN" } },
  { "freeze", 5, "FREEZE_SIDE_EFFECT1", "FREEZE", { status = "FRZ" } },
  { "paralysis", 6, "PARALYZE_SIDE_EFFECT1", "PARALYSIS", { status = "PAR" } },
  { "flinch", 31, "FLINCH_SIDE_EFFECT1", "FLINCH", { flinch = true } },
  { "confusion", 76, "CONFUSION_SIDE_EFFECT", "CONFUSION", { confusion = true } },
  { "attack-down", 68, "ATTACK_DOWN_SIDE_EFFECT", "ATK_MINUS_1", { stat = "attack", delta = -1 } },
  { "defense-down", 69, "DEFENSE_DOWN_SIDE_EFFECT", "DEF_MINUS_1", { stat = "defense", delta = -1 } },
  { "spatk-down", 71, "SP_ATK_DOWN_HIT_EFFECT", "SP_ATK_MINUS_1", { stat = "spatk", delta = -1 } },
  { "speed-down", 70, "SPEED_DOWN_SIDE_EFFECT", "SPD_MINUS_1", { stat = "speed", delta = -1 } },
  { "spdef-down", 72, "SP_DEF_DOWN_SIDE_EFFECT", "SP_DEF_MINUS_1", { stat = "spdef", delta = -1 } },
  { "accuracy-down", 73, "ACCURACY_DOWN_SIDE_EFFECT", "ACC_MINUS_1", { stat = "accuracy", delta = -1 } },
  { "attack-up", 139, "ATTACK_UP_HIT_EFFECT", "ATK_PLUS_1", { stat = "attack", delta = 1, user = true } },
  { "defense-up", 138, "DEFENSE_UP_HIT_EFFECT", "DEF_PLUS_1", { stat = "defense", delta = 1, user = true } },
  { "all-stats-up", 140, "ALL_UP_HIT_EFFECT", "ALL_STATS_UP", { allStats = true, user = true } },
  { "tri-attack", 36, "TRI_ATTACK_EFFECT", "TRI_ATTACK", { tri = true } },
  { "toxic", 202, "POISON_FANG_EFFECT", "TOXIC", { status = "TOX" } },
}
local AB = {
  NONE = 0,
  SERENE_GRACE = 32,
  SHIELD_DUST = 19,
  LIMBER = 7,
  IMMUNITY = 17,
  WATER_VEIL = 41,
  MAGMA_ARMOR = 40,
  OWN_TEMPO = 20,
  INNER_FOCUS = 39,
  CLEAR_BODY = 29,
  WHITE_SMOKE = 73,
  KEEN_EYE = 51,
  HYPER_CUTTER = 52,
}
function M.run(root, backend, version, execution)
  local native = backend == "gen1"
  local function configure(data, engine, ids, rom, names)
    if engine == "gen2" then
      data.type_chart.matchups[#data.type_chart.matchups + 1] =
        { attacker = "NORMAL", defender = "STEEL", multiplier = 5 }
    end
    for i, e in ipairs(EFFECTS) do
      local n, name = 599 + i, "SECONDARY_" .. i
      local id = engine == "gen1" and name or ("MOVE_%03d"):format(n)
      ids[name], names[n] = id, name
      if engine == "gen1" then
        local d = {
          effect = e[2],
          power = 35,
          type = 0,
          accuracy = 100,
          pp = 10,
          flags = 2,
          target = 0,
          priority = 0,
          secondaryChance = 30,
        }
        data.gen3Moves._rom[n], rom[n], data.gen3Pokemon._moveNames[n] = d, d, name
      else
        data.moves[id] = {
          id = id,
          name = name,
          index = n,
          gen3Effect = e[2],
          effect = e[3],
          power = 35,
          type = "NORMAL",
          accuracy = 100,
          pp = 10,
          secondaryChance = 30,
          effectChance = 77,
          protectAffected = true,
        }
      end
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  local T, rows, events, liveUser = f.T, {}, {}, nil
  local stops = {
    f.e.api.hooks:wrap("battle.accuracy", function()
      return true
    end),
    f.e.api.hooks:wrap("battle.crit", function()
      return false
    end),
    f.e.api.events:on("battle.status_inflicted", function(e)
      events[#events + 1] = {
        status = e.status,
        target = e.target.mon.nickname,
        sourceIsUser = e.source == liveUser,
        targetStatus = e.target.mon.status,
      }
    end),
  }
  local conditions = {
    { name = "certain", certain = true, direct = true },
    { name = "certain-mist", certain = true, mist = true, direct = true },
    { name = "certain-clear-body", certain = true, theirs = "CLEAR_BODY", direct = true },
    { name = "certain-shield-dust", certain = true, theirs = "SHIELD_DUST", direct = true },
    { name = "stage-cap-up", stages = 6 },
    { name = "stage-cap-down", stages = -6 },
    { name = "ordinary" },
    { name = "serene-grace", mine = "SERENE_GRACE" },
    { name = "shield-dust", theirs = "SHIELD_DUST" },
    { name = "limber", theirs = "LIMBER" },
    { name = "immunity", theirs = "IMMUNITY" },
    { name = "water-veil", theirs = "WATER_VEIL" },
    { name = "magma-armor", theirs = "MAGMA_ARMOR" },
    { name = "own-tempo", theirs = "OWN_TEMPO" },
    { name = "inner-focus", theirs = "INNER_FOCUS" },
    { name = "clear-body", theirs = "CLEAR_BODY" },
    { name = "white-smoke", theirs = "WHITE_SMOKE" },
    { name = "substitute-zero", sub = 0 },
    { name = "safeguard-zero", safeguard = 0 },
    { name = "mist-zero", mist = 0 },
    { name = "substitute", sub = 1000 },
    { name = "broken-substitute", sub = 1 },
    { name = "fainted", hp = 0, direct = true },
    { name = "fainting-hit", hp = 1 },
    { name = "status-existing", status = "PAR" },
    { name = "frozen", status = "FRZ" },
    { name = "fire-hit-frozen", status = "FRZ", moveType = 10 },
    { name = "fire-substitute-frozen", status = "FRZ", moveType = 10, sub = 1000 },
    { name = "fire-broken-sub-frozen", status = "FRZ", moveType = 10, sub = 1 },
    { name = "safeguard", safeguard = true },
    { name = "mist", mist = true },
    { name = "fire-type", kind = 10 },
    { name = "ice-type", kind = 15 },
    { name = "poison-type", kind = 3 },
    { name = "steel-type", kind = 8 },
    { name = "sun", sky = "SUN" },
    { name = "moved", moved = true },
    { name = "pokedude", demo = true },
  }
  local function at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  for _, condition in ipairs(conditions) do
    if not execution or not condition.direct then
      for i, e in ipairs(EFFECTS) do
        for _, chance in ipairs({ 0, 30, 100 }) do
          for _, word in ipairs({ 0, 30, 31, 60, 99 }) do
            events = {}
            local b = f.fresh("TACKLE", { enemy = true }).battle
            b.double = true
            local Copy = require("src.mods.Merge").deepCopy
            if native then
              local B = require("src.core.game3.battle.state")
              b.battlers[2], b.battlers[3] =
                B.makeBattler(Copy(b.player.mon), "player", { id = 2 }),
                B.makeBattler(Copy(b.enemy.mon), "enemy", { id = 3 })
            else
              local B = require("src.battle.BattleState")
              b:syncSides()
              b:placeBattler(2, B.makeBattler(f.data, Copy(b.player.mon), true))
              b:placeBattler(3, B.makeBattler(f.data, Copy(b.enemy.mon), false))
              b:syncSides()
            end
            local id = (i + chance + word) % 4
            local user, target = at(b, id), at(b, id % 2 == 0 and 1 or 0)
            liveUser = user
            for pos = 0, 3 do
              local a = at(b, pos)
              a.mon.nickname, a.mon.hp = "P" .. pos, 1000
              if native then
                a.ability, a.mon.ability, a.type1, a.type2, a.mon.maxHp = 0, 0, 0, 0, 1000
                for _, k in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do
                  a.mon[k] = 50
                end
              else
                a.abilityOverride, a.curTypes, a.mon.stats.hp = false, { "NORMAL" }, 1000
                for _, k in ipairs({ "attack", "defense", "speed", "spatk", "spdef" }) do
                  a.curStats[k] = 50
                end
              end
            end
            local function ability(a, name)
              if native then
                a.ability, a.mon.ability = AB[name or "NONE"], AB[name or "NONE"]
              else
                a.abilityOverride = name or false
              end
            end
            if condition.stages then
              for pos = 0, 3 do
                local a = at(b, pos)
                for _, stat in ipairs({
                  "attack",
                  "defense",
                  "speed",
                  "spatk",
                  "spdef",
                  "accuracy",
                  "evasion",
                }) do
                  local key = native and ({ spatk = "spAtk", spdef = "spDef" })[stat] or nil
                  a.stages[key or stat] = condition.stages
                end
              end
            end
            ability(user, condition.mine)
            ability(target, condition.theirs)
            local number, move = 599 + i
            if native then
              user.mon.moves, user.mon.pp = { number }, { 10 }
              move = require("src.core.game3.battle.moves")._rom[number]
              move.secondaryChance, move.type = chance, condition.moveType or 0
              target.type1, target.type2 = condition.kind or 0, condition.kind or 0
              target.status, target.mon.status = condition.status, condition.status
            else
              user.curMoves = { { id = f.ids["SECONDARY_" .. i], pp = 10 } }
              user.mon.moves = user.curMoves
              move = f.data.moves[user.curMoves[1].id]
              move.secondaryChance = chance
              move.type = condition.moveType == 10 and "FIRE" or "NORMAL"
              move.effectChance = math.floor(chance * 255 / 100)
              target.curTypes = {
                ({ [0] = "NORMAL", [10] = "FIRE", [15] = "ICE", [3] = "POISON", [8] = "STEEL" })[condition.kind or 0],
              }
              target.mon.status = condition.status
            end
            target.mon.hp, target.substituteHP, target.expMovedThisTurn =
              condition.hp or 1000, condition.sub, condition.moved
            if native then
              b.pokedude, b.weather = condition.demo, condition.sky
              local side = target.side == "player" and b.playerSide or b.enemySide
              side.expSafeguardTurns, side.expMistTurns =
                condition.safeguard == true and 5 or condition.safeguard,
                condition.mist == true and 5 or condition.mist
            else
              b.pokedudeDemo, b.field.weather = condition.demo and {}, condition.sky
              target.safeguardTurns, target.mist =
                condition.safeguard == true and 5 or condition.safeguard, condition.mist
            end
            local draws = {}
            b.rng = function(lo, hi)
              local value = lo + word % (hi - lo + 1)
              draws[#draws + 1] = { lo = lo, hi = hi, word = word, value = value }
              return value
            end
            local result
            local descriptor = Copy(e[5])
            descriptor.certain = condition.certain
            if native then
              local Engine, Adapter =
                require("src.core.game3.battle.engine"), require("src.core.game3.battle.adapter")
              if execution then
                Engine.resolveMove(user, target, number, 1, Adapter.new(b), b, {})
                result = "execution"
              else
                local context = Engine.newContext(user, target, number, 1, Adapter.new(b), b, {}, {})
                result = require("src.core.game3.battle.effects.secondary").withChance(
                  context,
                  e[4],
                  condition.certain == true,
                  e[5].user
                )
              end
            else
              if execution then
                b:executeAction(user, target, user.curMoves[1])
                result = "execution"
              else
                result = require("src.battle.Gen3Secondary").withChance(
                  require("src.battle.EffectRegistry").makeCtx(b, user, target, move, user.curMoves[1]),
                  descriptor
                )
              end
            end
            if not execution and not condition.certain then
              T.check(#draws >= 1, "native chance draws before effect protection even at zero")
              T.same(
                draws[1],
                { lo = 0, hi = 99, word = word, value = word },
                "native secondary range and input word"
              )
            end
            if not execution and condition.certain then
              local chanceDraws = 0
              for _, draw in ipairs(draws) do
                if draw.lo == 0 and draw.hi == 99 then
                  chanceDraws = chanceDraws + 1
                end
              end
              T.eq(chanceDraws, 0, "certain effect opcode bypasses the chance draw")
            end
            if execution then
              T.eq(
                native and user.mon.pp[1] or user.curMoves[1].pp,
                9,
                "native executed move spends owned PP once"
              )
            end
            local function view(a)
              local stats = {}
              for _, k in ipairs({ "attack", "defense", "speed", "spatk", "spdef", "accuracy", "evasion" }) do
                local nk = native and ({ spatk = "spAtk", spdef = "spDef" })[k] or nil
                stats[#stats + 1] = a.stages[nk or k] or 0
              end
              return {
                status = not native and a.mon.status == "PSN" and a.mon.toxic and "TOX"
                  or a.mon.status
                  or false,
                hp = a.mon.hp,
                stages = stats,
                flinched = a.flinched or false,
                confusion = (native and a.confusionTurns or a.confusedTurns) or 0,
                sub = a.substituteHP or 0,
              }
            end
            rows[#rows + 1] = {
              case = condition.name,
              effect = e[1],
              chance = chance,
              word = word,
              user = id,
              result = result or false,
              draws = draws,
              target = view(target),
              attacker = view(user),
              events = events,
            }
          end
        end
      end
    end
  end
  if not native then
    local c = f.fresh("TACKLE", { enemy = true })
    local b, mon = c.battle, c.target.mon
    mon.status, mon.toxic, c.target.toxicCounter = "PSN", true, 1
    f.game.stack.states = { b }
    T.eq(f.e.api.world:party()[1].status, "TOX", "API-3 party query preserves badly poisoned identity")
    T.eq(
      f.e.api.battle:snapshot().player.status,
      "TOX",
      "API-3 battle snapshot preserves badly poisoned identity"
    )
    local rebuilt = require("src.battle.BattleState").makeBattler(f.data, mon, true)
    T.eq(rebuilt.toxicCounter, 1, "saved native toxic marker restores the initial residual counter")
    for _, desired in ipairs({ "PSN", "TOX" }) do
      local stop = f.e.api.hooks:wrap("battle.damage", function(nextDamage, context)
        context.target.mon.status = desired
        return nextDamage(context)
      end)
      c.use()
      stop()
      T.eq(
        c.target.toxicCounter,
        desired == "TOX" and 1 or nil,
        "callback status write resets the owning battler counter"
      )
      T.eq(mon.status, "PSN", "native callback writes keep the engine status representation")
      T.eq(
        mon.toxic == true,
        desired == "TOX",
        "native callback status edits update the toxic marker atomically"
      )
      T.eq(f.e.api.world:party()[1].status, desired, "public read reflects callback status replacement")
    end
    local record = require("src.battle.MoveEffects").RECORDS.PARALYZE_SIDE_EFFECT1
    local custom = require("src.mods.Merge").deepCopy(record)
    custom.run = function()
      return {}
    end
    local ctx = require("src.battle.EffectRegistry").makeCtx(
      b,
      c.user,
      c.target,
      f.data.moves[f.ids.SECONDARY_4],
      c.user.curMoves[1]
    )
    T.eq(
      require("src.battle.Gen3Secondary").run(ctx, custom),
      false,
      "authored secondary handlers retain their own chance contract"
    )
  end
  for _, stop in ipairs(stops) do
    stop()
  end
  f.close()
  return rows
end
return M
