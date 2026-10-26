local M = {}
function M.fixture(root, backend, version, entry)
  local native = backend == "gen1"
  return dofile(root .. "/tests/enemy_actions/fixture.lua").new(
    root,
    backend,
    version,
    3,
    "unified",
    function(data, _, ids, rom, names)
      if not native then
        data.items.FOCUS_BAND = {
          index = 196,
          name = "FOCUS BAND",
          holdEffect = "FOCUS_BAND",
          gen3HoldEffect = 39,
          holdEffectParam = 10,
        }
        data.items.SCOPE_LENS = { index = 198, name = "SCOPE LENS", holdEffect = "SCOPE_LENS" }
        data.items.LUCKY_PUNCH = { index = 222, name = "LUCKY PUNCH", holdEffect = "LUCKY_PUNCH" }
        data.type_chart.matchups[#data.type_chart.matchups + 1] =
          { attacker = "NORMAL", defender = "GHOST", multiplier = 0 }
      end
      for _, row in ipairs({
        { 3, "DOUBLE_SLAP", 29, "TWO_TO_FIVE_ATTACKS_EFFECT" },
        { 24, "DOUBLE_KICK", 44, "ATTACK_TWICE_EFFECT" },
        { 41, "TWINEEDLE", 77, "TWINEEDLE_EFFECT" },
      }) do
        local number, name, effect, hostEffect = unpack(row)
        local id = native and name or ("MOVE_%03d"):format(number)
        ids[name], names[number] = id, name
        if native then
          local def = {
            effect = effect,
            power = 15,
            type = 0,
            accuracy = 100,
            pp = 10,
            target = 0,
            flags = 51,
            secondaryChance = 20,
            priority = 0,
          }
          data.gen3Moves._rom[number], rom[number], data.gen3Pokemon._moveNames[number] = def, def, name
          data.gen3Pokemon._types[4], data.gen3Pokemon._abilities[4] = { 0, 0 }, { 0, 0 }
        else
          data.moves[id] = {
            id = id,
            index = number,
            name = name,
            effect = hostEffect,
            gen3Effect = effect,
            power = 15,
            type = "NORMAL",
            accuracy = 100,
            pp = 10,
            target = 0,
            flags = 51,
            protectAffected = true,
            secondaryChance = 20,
          }
          data.pokemon.CHARMANDER.types, data.pokemon.CHARMANDER.abilities = { "NORMAL" }, {}
        end
      end
    end,
    entry
  )
end
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = M.fixture(root, backend, version)
  local T, Copy = f.T, require("src.mods.Merge").deepCopy
  local rows, draws, damage, used = {}, {}, {}, {}
  local currentKind, liveUser, liveTarget
  -- Public events are detached views. Mutate the owned fixture's real battlers
  -- to test live continuation; this does not assert event-view write-through.
  local off = f.e.api.events:on("battle.damage_dealt", function(e)
    damage[#damage + 1] = {
      user = e.user.mon.nickname,
      target = e.target.mon.nickname,
      move = e.move.id,
      damage = e.damage,
      crit = e.crit or false,
      substitute = e.substitute or false,
      typeMult = e.typeMult,
    }
    if #damage == 1 and currentKind == "sleep_after_hit" then
      liveUser.mon.status = "SLP"
    end
    if #damage == 1 and currentKind == "type_after_hit" then
      if native then
        liveTarget.type1, liveTarget.type2 = 7, 7
      else
        liveTarget.curTypes = { "GHOST" }
      end
    end
    if #damage == 1 and currentKind == "user_ko" then
      liveUser.mon.hp = 0
    end
  end)
  local offMove = f.e.api.events:on("battle.move_used", function(e)
    used[#used + 1] = { user = e.user.mon.nickname, target = e.target.mon.nickname, move = e.move.id }
  end)
  local function at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  local function fresh(double, first, second)
    local b = f.fresh("TACKLE", { enemy = true }).battle
    b.double = double
    if not native then
      b:syncSides()
    end
    if double then
      for id = 2, 3 do
        local mon = Copy(at(b, id % 2).mon)
        if native then
          b.battlers[id] = require("src.core.game3.battle.state").makeBattler(
            mon,
            id % 2 == 0 and "player" or "enemy",
            { id = id, partyIndex = 2 }
          )
        else
          b:placeBattler(id, require("src.battle.BattleState").makeBattler(f.data, mon, id % 2 == 0))
        end
      end
    end
    if not native then
      b:syncSides()
    end
    for id = 0, double and 3 or 1 do
      local a = at(b, id)
      a.mon.nickname = "P" .. id
      if native then
        a.mon.moves, a.mon.pp, a.mon.maxPp = { 3, 24, 41, 33 }, { 10, 10, 10, 10 }, { 10, 10, 10, 10 }
        a.mon.maxHp, a.ability, a.mon.ability, a.type1, a.type2 = 400, 0, 0, 0, 0
        a.mon.speed = 100 - id * 10
      else
        a.mon.moves = {
          { id = f.ids.DOUBLE_SLAP, pp = 10 },
          { id = f.ids.DOUBLE_KICK, pp = 10 },
          { id = f.ids.TWINEEDLE, pp = 10 },
          { id = f.ids.TACKLE, pp = 10 },
        }
        a.curMoves, a.curTypes, a.abilityOverride = a.mon.moves, { "NORMAL" }, false
        a.mon.stats.hp = 400
        for _, stat in ipairs({ "attack", "defense", "spatk", "spdef" }) do
          a.curStats[stat] = 50
        end
        a.curStats.speed = 100 - id * 10
      end
      a.mon.hp = 400
    end
    local count, crit, variance = 0, 0, 0
    b.rng = function(lo, hi)
      local value = hi
      if lo == 0 and hi == 3 then
        count = count + 1
        value = count == 1 and first or second
      end
      if lo == 0 and hi == 15 then
        crit = crit + 1
        value = currentKind == "crit" and crit % 2 == 1 and 0 or hi
      end
      if lo == 85 and hi == 100 then
        variance = variance + 1
        value = variance % 2 == 1 and lo or hi
      end
      if lo == 0 and hi == 99 and (currentKind == "poison" or currentKind == "focus_band") then
        value = 0
      end
      draws[#draws + 1] = { lo = lo, hi = hi, value = value }
      return value
    end
    return b
  end
  local function view(b)
    local all = {}
    for id = 0, b.double and 3 or 1 do
      local a = at(b, id)
      local pp = {}
      for i = 1, 4 do
        pp[i] = native and a.mon.pp[i] or a.curMoves[i].pp
      end
      all[#all + 1] = {
        hp = a.mon.hp,
        pp = pp,
        status = a.mon.status,
        sub = tonumber(a.substituteHP) or 0,
        last = native and a.lastMoveId or a.lastMove and f.data.moves[a.lastMove].index,
        attack = a.stages.attack or 0,
      }
    end
    return all
  end
  for _, double in ipairs({ false, true }) do
    for uid = 0, double and 3 or 1 do
      local tid = uid % 2 == 0 and uid + 1 or uid - 1
      for slot = 1, 3 do
        for first = 0, 3 do
          for second = 0, 3 do
            for _, kind in ipairs({
              "ordinary",
              "crit",
              "focus_crit",
              "scope_crit",
              "focus_scope_crit",
              "max_crit",
              "sub_survive",
              "sub_break",
              "endure",
              "focus_band",
              "target_ko",
              "protected",
              "hidden",
              "immune",
              "accuracy_miss",
              "poison",
              "sleep_after_hit",
              "type_after_hit",
              "user_ko",
              "called",
            }) do
              currentKind = kind
              draws, damage, used = {}, {}, {}
              local b = fresh(double, first, second)
              local user, target = at(b, uid), at(b, tid)
              liveUser, liveTarget = user, target
              if kind == "focus_crit" or kind == "focus_scope_crit" or kind == "max_crit" then
                user.focusEnergy = true
              end
              if kind == "scope_crit" or kind == "focus_scope_crit" then
                if native then
                  user.item, user.mon.item = 198, 198
                else
                  user.mon.item = "SCOPE_LENS"
                end
              end
              if kind == "max_crit" then
                user.species = 113
                if native then
                  user.item, user.mon.item = 222, 222
                else
                  user.mon.item = "LUCKY_PUNCH"
                end
              end
              if kind == "sub_survive" then
                target.substituteHP = 400
              end
              if kind == "sub_break" then
                target.substituteHP = 1
              end
              if kind == "target_ko" then
                target.mon.hp = 1
              end
              if kind == "endure" then
                target.mon.hp = 1
                target[native and "expEnduring" or "enduring"] = true
              end
              if kind == "focus_band" then
                target.mon.hp = 1
                if native then
                  target.item, target.mon.item = 196, 196
                else
                  target.mon.item = "FOCUS_BAND"
                end
              end
              if kind == "protected" then
                target[native and "expProtected" or "protecting"] = true
              end
              if kind == "hidden" then
                if native then
                  target.semiInvulnerable = "ON_AIR"
                else
                  target.invulnerable, target.hiddenAs = true, "air"
                end
              end
              if kind == "immune" then
                if native then
                  target.type1, target.type2 = 7, 7
                else
                  target.curTypes = { "GHOST" }
                end
              end
              local number = ({ 3, 24, 41 })[slot]
              local def = native and f.data.gen3Moves._rom[number]
                or f.data.moves[({ f.ids.DOUBLE_SLAP, f.ids.DOUBLE_KICK, f.ids.TWINEEDLE })[slot]]
              local old = def.accuracy
              if kind == "accuracy_miss" then
                def.accuracy = 90
              end
              if native then
                local nativeSlot = slot
                if kind == "called" then
                  nativeSlot = nil
                end
                require("src.core.game3.battle.engine").resolveMove(
                  uid,
                  tid,
                  user.mon.moves[slot],
                  nativeSlot,
                  require("src.core.game3.battle.adapter").new(b),
                  b,
                  {},
                  { called = kind == "called" }
                )
              elseif kind == "called" then
                b:performMove(user, target, user.curMoves[slot], true)
              else
                b:executeAction(user, target, user.curMoves[slot])
              end
              def.accuracy = old
              local label = (double and "double" or "single")
                .. "/"
                .. uid
                .. "/"
                .. slot
                .. "/"
                .. first
                .. "/"
                .. second
                .. "/"
                .. kind
              rows[#rows + 1] = {
                label = label,
                field = view(b),
                draws = Copy(draws),
                damage = Copy(damage),
                used = Copy(used),
              }
              if kind == "ordinary" then
                T.eq(
                  #damage,
                  slot == 1 and (first > 1 and second + 2 or first + 2) or 2,
                  "native hit count follows its own four-value opcode"
                )
              end
              if
                kind == "sleep_after_hit"
                or kind == "type_after_hit"
                or kind == "user_ko"
                or kind == "endure"
              then
                T.eq(#damage, 1, "native continuation stops at its actual live condition")
              end
              if kind == "sleep_after_hit" then
                T.eq(user.mon.status, "SLP", "callback actually changes the live user's status")
              end
              if kind == "user_ko" then
                T.eq(user.mon.hp, 0, "callback actually faints the live user")
              end
              if kind == "type_after_hit" then
                T.eq(
                  native and target.type1 or target.curTypes[1],
                  native and 7 or "GHOST",
                  "callback actually changes the live target's type"
                )
              end
              if kind == "endure" or kind == "focus_band" then
                T.eq(target.mon.hp, 1, "native damage survival is retained")
              end
              if kind == "sub_break" then
                T.check(target.mon.hp < 400, "later hits continue after the Substitute breaks")
              end
              T.eq(
                native and user.mon.pp[slot] or user.curMoves[slot].pp,
                kind == "called" and 10 or 9,
                "a multi-hit move spends PP once"
              )
            end
          end
        end
      end
    end
  end
  off()
  offMove()
  f.close()
  return rows
end
return M
