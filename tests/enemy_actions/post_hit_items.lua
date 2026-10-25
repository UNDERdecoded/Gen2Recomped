-- Identical command inputs drive unchanged native code and the shared host
-- command. Record every held read, RNG call, activation, HP and flinch state.
local M = {}
function M.fixture(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/held_item/fixture.lua").new(root, backend, version, 3, "unified")
  f.game.save.options.ruleset = "gen3_emerald"
  if native then
    f.data.gen3Items._byId[219] =
      { name = "SHELL BELL", pocket = "ITEMS", price = 100, holdEffect = 62, holdEffectParam = 8 }
  else
    f.data.items.ITEM_219 = {
      id = "ITEM_219",
      index = 219,
      name = "SHELL BELL",
      price = 100,
      holdEffect = "SHELL_BELL",
      holdEffectParam = 8,
    }
  end
  function f.put(actor, id)
    if native then
      actor.item, actor.mon.item = id or 0, id or 0
    else
      actor.mon.item = id and ("ITEM_%03d"):format(id) or nil
    end
  end
  function f.field(double)
    local b = f.reset(nil, double)
    if not native then
      b:syncSides()
    end
    for id = 0, double and 3 or 1 do
      local a = f.actor(id)
      a.mon.nickname, a.mon.hp = "P" .. id, 400
      a.mon.level = 30
      if native then
        a.mon.moves, a.mon.pp, a.mon.maxPp = { 33 }, { 10 }, { 10 }
        a.mon.maxHp, a.type1, a.type2, a.ability, a.mon.ability = 400, 0, 0, 0, 0
        a.mon.attack, a.mon.defense, a.mon.spAtk, a.mon.spDef, a.mon.speed = 50, 50, 50, 50, 100 - id * 10
      else
        a.mon.moves = { { id = "MOVE_033", pp = 10 } }
        a.curMoves = a.mon.moves
        a.mon.stats.hp, a.abilityOverride, a.curTypes = 400, false, { "NORMAL" }
        a.curStats.attack, a.curStats.defense, a.curStats.spatk, a.curStats.spdef = 50, 50, 50, 50
        a.curStats.speed = 100 - id * 10
      end
      f.put(a, nil)
    end
    return b
  end
  return f
end
function M.command(root, backend, version)
  local native = backend == "gen1"
  local f = M.fixture(root, backend, version)
  local file = assert(io.open(root .. "/tests/post_hit_items/command-cases.json", "rb"))
  local inputs = require("src.link.Json").decode(file:read("*a"))
  file:close()
  local rows = {}
  for _, double in ipairs({ false, true }) do
    for actor = 0, double and 3 or 1 do
      for _, case in ipairs(inputs.command_cases) do
        for _, roll in ipairs(inputs.rng_values) do
          local b = f.field(double)
          local user = f.actor(actor)
          local target = f.actor(case.same_actor and actor or actor % 2 == 0 and actor + 1 or actor - 1)
          user.mon.hp, target.mon.hp = case.user_hp, case.target_hp
          if native then
            user.mon.maxHp = case.user_max_hp
          else
            user.mon.stats.hp = case.user_max_hp
          end
          local item = case.physical_item or case.item_effect == "SHELL_BELL" and 562 or nil
          f.put(user, item)
          if case.player_item then
            f.put(f.actor(0), case.player_item)
          end
          if case.metadata_cleared and item then
            if native then
              f.data.gen3Items._byId[item].holdEffect = 0
            else
              f.data.items[("ITEM_%03d"):format(item)].holdEffect = "NONE"
            end
          elseif item == 187 then
            if native then
              f.data.gen3Items._byId[item].holdEffect = 30
            else
              f.data.items.ITEM_187.holdEffect = "FLINCH"
            end
          elseif item == 219 then
            if native then
              f.data.gen3Items._byId[item].holdEffect = 62
            else
              f.data.items.ITEM_219.holdEffect = "SHELL_BELL"
            end
          end
          target.substituteHP = case.substitute_hp
          if case.target_moved then
            if native then
              target.expMovedThisTurn = true
            else
              target.gbaMovedTurn = b.turnCount or 0
            end
          end
          if case.ability then
            if native then
              target.ability = case.ability
            else
              target.abilityOverride = case.ability
            end
          end
          local trace, draws = {}, {}
          local off = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
            trace[#trace + 1] = {
              holder = ctx.mon.nickname,
              item = ctx.item,
              definition = ctx.def and ctx.def.id,
              effect = ctx.effect,
              parameter = ctx.parameter,
              trigger = ctx.trigger,
              actualBattle = ctx.battle == b,
            }
            local n, hook = #trace, case.hook
            if n == 1 and hook == "suppress_attacker" then
              return nil, 0
            end
            if n == 1 and (hook == "replace_attacker" or hook == "replace_both_differently") then
              return case.hook_effect, case.hook_parameter
            end
            if n == 2 and (hook == "replace_player" or hook == "replace_both_differently") then
              return case.second_effect, case.second_parameter
            end
            if hook == "alternate_each_read" then
              if n % 2 == 1 then
                return nextRead(ctx)
              end
              return ctx.effect or "HELD_NONE", (ctx.parameter or 0) + 64
            end
            return nextRead(ctx)
          end)
          b.rng = function(lo, hi)
            draws[#draws + 1] = { lo, hi, roll }
            return roll
          end
          local move = not case.no_move and { flags = case.move_flags } or nil
          if move and case.no_flags then
            move.flags = nil
          end
          local frame = {
            user = not case.no_user and user or nil,
            target = not case.no_target and target or nil,
            move = move,
            firstDmg = case.first_damage,
            targetDamaged = case.target_damaged,
            noEffect = case.no_effect,
          }
          local active, animations = false, {}
          if native then
            local ad = require("src.core.game3.battle.adapter").new(b)
            frame.adapter, frame.st = ad, b
            active = require("src.core.game3.battle.held_items").kingsRockShellBell(frame)
            for _, event in ipairs(ad:eventsSince(0)) do
              if event.kind == "anim" then
                animations[#animations + 1] = {
                  name = event.name,
                  user = event.attackerId,
                  target = event.targetId,
                }
              end
            end
          else
            active = require("src.battle.Gen3PostHitItems").run(b, frame)
            for _, event in ipairs(b.queue) do
              if event.anim then
                animations[#animations + 1] = {
                  name = event.anim,
                  user = event.attackerPosition,
                  target = event.targetPosition,
                }
              end
            end
          end
          off()
          local state = {}
          for id = 0, double and 3 or 1 do
            local a = f.actor(id)
            state[#state + 1] = { hp = a.mon.hp, flinched = a.flinched or false }
          end
          f.T.eq(#f.result.errors, 0, "held command callbacks remain error-free")
          rows[#rows + 1] = {
            case = case.label,
            double = double,
            actor = actor,
            roll = roll,
            active = active or false,
            firstDamage = frame.firstDmg,
            state = state,
            trace = trace,
            draws = draws,
            animations = animations,
          }
        end
      end
    end
  end
  f.close()
  return rows
end
function M.execution(root, backend, version)
  local native = backend == "gen1"
  local f = M.fixture(root, backend, version)
  local ids = {}
  for _, row in ipairs({
    { 33, "TACKLE", 0, "NO_ADDITIONAL_EFFECT", 35, 0 },
    { 3, "DOUBLE_SLAP", 29, "TWO_TO_FIVE_ATTACKS_EFFECT", 15, 0 },
    { 167, "TRIPLE_KICK", 104, "TRIPLE_KICK_EFFECT", 10, 0 },
    { 57, "SURF", 0, "NO_ADDITIONAL_EFFECT", 35, 8 },
    { 89, "EARTHQUAKE", 0, "NO_ADDITIONAL_EFFECT", 35, 32 },
    { 214, "SLEEP_TALK", 97, "SLEEP_TALK_EFFECT", 0, 1 },
  }) do
    local number, name, effect, binding, power, target = unpack(row)
    ids[number] = ("MOVE_%03d"):format(number)
    if native then
      local def = {
        effect = effect,
        power = power,
        type = 0,
        accuracy = 100,
        pp = 10,
        target = target,
        flags = 51,
        secondaryChance = 0,
        priority = 0,
      }
      local moves = require("src.core.game3.battle.moves")
      moves._rom[number], moves.BY_NUM[number], moves._numByName[name] = def, name, number
      f.data.gen3Moves._rom[number], f.data.gen3Pokemon._moveNames[number] = def, name
    else
      f.data.moves[ids[number]] = {
        id = ids[number],
        index = number,
        name = name,
        gen3Effect = effect,
        effect = binding,
        power = power,
        type = "NORMAL",
        accuracy = 100,
        pp = 10,
        target = target,
        flags = 51,
        secondaryChance = 0,
      }
    end
  end
  if not native then
    f.data.type_chart.matchups[#f.data.type_chart.matchups + 1] =
      { attacker = "NORMAL", defender = "GHOST", multiplier = 0 }
    require("src.battle.TypeChart").load(f.data)
  end
  local rows = {}
  for _, double in ipairs({ false, true }) do
    for actor = 0, double and 3 or 1 do
      for _, number in ipairs({ 33, 3, 167, 57, 89, 214 }) do
        for _, itemCase in ipairs({
          "empty",
          "king",
          "king_player_shell",
          "king_player_king",
          "shell",
          "fake_shell",
          "override_shell",
          "override_rock",
          "suppressed",
          "zero_parameter",
        }) do
          for _, kind in ipairs({
            "ordinary",
            "substitute_5",
            "substitute_100",
            "target_low_hp",
            "heal_cap",
            "miss",
            "immune",
            "target_moved",
            "live_drop",
            "live_equip",
            "user_faint",
          }) do
            for _, chanceRoll in ipairs({ 0, 99 }) do
              local b = f.field(double)
              local user, targetId = f.actor(actor), actor % 2 == 0 and actor + 1 or actor - 1
              local target = f.actor(targetId)
              user.mon.hp = kind == "heal_cap" and 399 or 200
              local item = itemCase:match("^king") and 187
                or itemCase == "shell" and 219
                or itemCase == "fake_shell" and 562
                or itemCase == "suppressed" and 187
                or itemCase == "zero_parameter" and 219
                or nil
              f.put(user, item)
              if actor ~= 0 and itemCase == "king_player_shell" then
                f.put(f.actor(0), 219)
              end
              if actor ~= 0 and itemCase == "king_player_king" then
                f.put(f.actor(0), 187)
              end
              if kind == "substitute_5" then
                target.substituteHP = 5
              end
              if kind == "substitute_100" then
                target.substituteHP = 100
              end
              if kind == "target_low_hp" then
                target.mon.hp = 5
              end
              if kind == "target_moved" then
                if native then
                  target.expMovedThisTurn = true
                else
                  target.gbaMovedTurn = b.turnCount or 0
                end
              end
              if kind == "immune" then
                if native then
                  target.type1, target.type2 = 7, 7
                else
                  target.curTypes = { "GHOST" }
                end
              end
              if number == 214 then
                user.mon.status, user.sleepTurns = "SLP", 4
              end
              if native then
                user.mon.moves, user.mon.pp, user.mon.maxPp = { number }, { 10 }, { 10 }
                if number == 214 then
                  user.mon.moves[2], user.mon.pp[2], user.mon.maxPp[2] = 3, 10, 10
                end
              else
                user.mon.moves = { { id = ids[number], pp = 10 } }
                if number == 214 then
                  user.mon.moves[2] = { id = ids[3], pp = 10 }
                end
                user.curMoves = user.mon.moves
                f.T.eq(b.ruleset.baseDamageStyle, "gba", "script comparison uses native GBA damage")
              end
              local trace, draws, damage, events = {}, {}, {}, {}
              local off = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
                trace[#trace + 1] = {
                  holder = ctx.mon.nickname,
                  item = ctx.item,
                  definition = ctx.def and ctx.def.id,
                  effect = ctx.effect,
                  parameter = ctx.parameter,
                  trigger = ctx.trigger,
                  actualBattle = ctx.battle == b,
                }
                if ctx.trigger == "flinch" and ctx.mon.nickname == user.mon.nickname then
                  if itemCase == "override_shell" then
                    return "HELD_SHELL_BELL", 8
                  end
                  if itemCase == "override_rock" then
                    return "HELD_FLINCH", 128
                  end
                  if itemCase == "suppressed" then
                    return nil, 0
                  end
                  if itemCase == "zero_parameter" then
                    return "HELD_SHELL_BELL", 0
                  end
                end
                return nextRead(ctx)
              end)
              local offCrit = f.e.api.hooks:wrap("battle.crit", function()
                return false
              end)
              local offAccuracy
              if kind == "miss" then
                offAccuracy = f.e.api.hooks:wrap("battle.accuracy", function()
                  return false
                end)
              end
              local offMove = f.e.api.events:on("battle.move_used", function(e)
                events[#events + 1] = {
                  user = e.user.mon.nickname,
                  target = e.target.mon.nickname,
                  move = e.move.id,
                  called = e.isCalled or false,
                }
              end)
              local offDamage = f.e.api.events:on("battle.damage_dealt", function(e)
                damage[#damage + 1] = {
                  user = e.user.mon.nickname,
                  target = e.target.mon.nickname,
                  move = e.move.id,
                  damage = e.damage,
                  critical = e.crit or false,
                  substitute = e.substitute or false,
                  typeMult = e.typeMult,
                }
                if #damage == 1 then
                  if kind == "live_drop" then
                    f.put(user, nil)
                  end
                  if kind == "live_equip" then
                    f.put(user, 219)
                  end
                  if kind == "user_faint" then
                    user.mon.hp = 0
                  end
                end
              end)
              b.rng = function(lo, hi)
                local value = lo == 0 and hi == 99 and chanceRoll or hi
                draws[#draws + 1] = { lo, hi, value }
                return value
              end
              if native then
                require("src.core.game3.battle.engine").resolveMove(
                  actor,
                  targetId,
                  number,
                  1,
                  require("src.core.game3.battle.adapter").new(b),
                  b,
                  {}
                )
              else
                b:executeAction(user, target, user.curMoves[1])
              end
              off()
              offCrit()
              offMove()
              offDamage()
              if offAccuracy then
                offAccuracy()
              end
              local state = {}
              for id = 0, double and 3 or 1 do
                local a = f.actor(id)
                local pp = {}
                for i = 1, 4 do
                  local value
                  if native then
                    value = a.mon.pp[i]
                  else
                    value = a.curMoves[i] and a.curMoves[i].pp
                  end
                  pp[i] = value == nil and "absent" or value
                end
                state[#state + 1] = {
                  hp = a.mon.hp,
                  pp = pp,
                  status = a.mon.status,
                  flinched = a.flinched or false,
                  substitute = a.substituteHP or 0,
                }
              end
              f.T.eq(#f.result.errors, 0, "full held-item script callbacks remain error-free")
              rows[#rows + 1] = {
                double = double,
                actor = actor,
                move = number,
                itemCase = itemCase,
                case = kind,
                roll = chanceRoll,
                trace = trace,
                draws = draws,
                damage = damage,
                events = events,
                state = state,
              }
            end
          end
        end
      end
    end
  end
  f.close()
  return rows
end
return M
