local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local definitions = {
    { "STOCKPILE", 254, 160, "STOCKPILE_EFFECT", 0, 16, 0 },
    { "SPIT_UP", 255, 161, "SPIT_UP_EFFECT", 100, 0, 0 },
    { "SWALLOW", 256, 162, "SWALLOW_EFFECT", 0, 16, 0 },
    { "HELPING_HAND", 270, 176, "HELPING_HAND_EFFECT", 0, 16, 5 },
  }
  local function configure(data, engine, ids, rom, names)
    for _, row in ipairs(definitions) do
      local name, num, effect, handler, power, target, priority = unpack(row)
      local key = engine == "gen1" and name or ("MOVE_%03d"):format(num)
      ids[name], names[num] = key, name
      if engine == "gen1" then
        local d = {
          effect = effect,
          power = power,
          type = 0,
          target = target,
          priority = priority,
          accuracy = 100,
          pp = 20,
          flags = power == 0 and 0 or 51,
          secondaryChance = 0,
        }
        data.gen3Moves._rom[num], rom[num], data.gen3Pokemon._moveNames[num] = d, d, name
      else
        data.moves[key] = {
          id = key,
          index = num,
          name = name,
          effect = handler,
          gen3Effect = effect,
          power = power,
          type = "NORMAL",
          target = target,
          priority = priority,
          accuracy = 100,
          accuracyRaw = 255,
          pp = 20,
          protectAffected = power ~= 0,
        }
      end
    end
    if engine == "gen2" then
      data.type_chart.types = {}
      data.type_chart.matchups = {
        { attacker = "NORMAL", defender = "ROCK", multiplier = 5 },
        { attacker = "NORMAL", defender = "STEEL", multiplier = 5 },
        { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
      }
      for name, index in pairs({
        NORMAL = 0,
        ROCK = 5,
        GHOST = 7,
        STEEL = 8,
        FIRE = 10,
        WATER = 11,
        GRASS = 12,
        ELECTRIC = 13,
      }) do
        data.type_chart.types[name] =
          { id = name, index = index, category = index < 10 and "physical" or "special" }
      end
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  local T, rows, hits, moves = f.T, {}, {}, {}
  local calls, rolls = { crit = 0, damage = 0, variation = 0 }, 100
  local stopCrit = f.e.api.hooks:wrap("battle.crit", function()
    calls.crit = calls.crit + 1
    return true
  end)
  local stopDamage = f.e.api.hooks:wrap("battle.damage", function(nextDamage, ...)
    calls.damage = calls.damage + 1
    return nextDamage(...)
  end)
  local stopHit = f.e.api.events:on("battle.damage_dealt", function(e)
    hits[#hits + 1] = {
      user = e.user.mon.nickname,
      target = e.target.mon.nickname,
      move = e.move.id,
      amount = e.damage,
      crit = e.crit,
      typeMult = e.typeMult,
      substitute = e.substitute or false,
    }
  end)
  local stopMove = f.e.api.events:on("battle.move_used", function(e)
    moves[#moves + 1] = { user = e.user.mon.nickname, target = e.target.mon.nickname, move = e.move.id }
  end)
  local function at(b, id)
    if native then
      return b.battlers[id]
    end
    return b:battlerAt(id)
  end
  local function make(mon, id)
    if native then
      return require("src.core.game3.battle.state").makeBattler(
        mon,
        id % 2 == 0 and "player" or "enemy",
        { id = id }
      )
    end
    return require("src.battle.BattleState").makeBattler(f.data, mon, id % 2 == 0)
  end
  local function put(b, id, a)
    if native then
      b.battlers[id] = a
    else
      b:placeBattler(id, a)
    end
  end
  local function fresh(spec, userId)
    moves, hits = {}, {}
    local b, copy = f.fresh("TACKLE", { enemy = true }).battle, require("src.mods.Merge").deepCopy
    b.double = true
    put(b, 2, make(copy(b.player.mon), 2))
    put(b, 3, make(copy(b.enemy.mon), 3))
    if not native then
      b:syncSides()
    end
    for id = 0, 3 do
      local a = at(b, id)
      a.mon.nickname, a.mon.hp, a.mon.level = "P" .. id, 10000, spec.level or 30
      if native then
        a.mon.maxHp, a.ability, a.mon.ability = 10000, 0, 0
        a.mon.moves, a.mon.pp, a.mon.maxPp = { 254, 255, 256, 270 }, { 20, 10, 10, 20 }, { 20, 10, 10, 20 }
        for _, k in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do
          a.mon[k] = spec.stat or 50
        end
        a.type1, a.type2 = 0, 0
      else
        a.curStats = {
          hp = 10000,
          attack = spec.stat or 50,
          defense = spec.stat or 50,
          speed = 50,
          special = spec.stat or 50,
          spatk = spec.stat or 50,
          spdef = spec.stat or 50,
        }
        a.mon.stats, a.curTypes, a.abilityOverride = a.curStats, { "NORMAL" }, false
        a.curMoves = {
          { id = f.ids.STOCKPILE, pp = 20 },
          { id = f.ids.SPIT_UP, pp = 10 },
          { id = f.ids.SWALLOW, pp = 10 },
          { id = f.ids.HELPING_HAND, pp = 20 },
        }
        a.mon.moves = a.curMoves
      end
    end
    local user, target = at(b, userId), at(b, userId % 2 == 0 and 1 or 0)
    local kind = spec.moveType or "NORMAL"
    local typeIds = { NORMAL = 0, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13 }
    local def = native and require("src.core.game3.battle.moves")._rom[255] or f.data.moves[f.ids.SPIT_UP]
    def.type = native and typeIds[kind] or kind
    if spec.stab ~= false then
      if native then
        user.type1, user.type2 = typeIds[kind], typeIds[kind]
      else
        user.curTypes = { kind }
      end
    end
    if spec.ability then
      if native then
        local ab = require("src.core.game3.battle.abilities").id(spec.ability)
        user.ability, user.mon.ability = ab, ab
      else
        user.abilityOverride = spec.ability
      end
    end
    if spec.defAbility then
      if native then
        local ab = require("src.core.game3.battle.abilities").id(spec.defAbility)
        target.ability, target.mon.ability = ab, ab
      else
        target.abilityOverride = spec.defAbility
      end
    end
    user.stages.attack, user.stages.spAtk, user.stages.spatk =
      spec.attackStage or 0, spec.attackStage or 0, spec.attackStage or 0
    target.stages.defense, target.stages.spDef, target.stages.spdef =
      spec.defenseStage or 0, spec.defenseStage or 0, spec.defenseStage or 0
    if spec.item then
      local item = ({ NORMAL_POWER = 217, CHOICE_BAND = 186 })[spec.item]
      if native then
        user.item, user.mon.item = item, item
      else
        user.items.PROBE =
          { holdEffect = spec.item, holdEffectParam = spec.item == "NORMAL_POWER" and 10 or 0 }
        user.mon.item = "PROBE"
      end
    end
    if spec.partnerAbility then
      local partner = at(b, (userId + 2) % 4)
      if native then
        local ab = require("src.core.game3.battle.abilities").id(spec.partnerAbility)
        partner.ability, partner.mon.ability = ab, ab
      else
        partner.abilityOverride = spec.partnerAbility
      end
    end
    if spec.pinch then
      user.mon.hp = 3000
    end
    if spec.sport then
      if native then
        b.expWaterSport = true
      else
        b.field.waterSport = "FIRE"
      end
    end
    if spec.defAbility == "VOLT_ABSORB" then
      target.mon.hp = 5000
    end
    if spec.identified then
      if native then
        target.expIdentified = true
      else
        target.identified = true
      end
    end
    if spec.defAbility == "MARVEL_SCALE" then
      target.mon.status = "PSN"
    end
    if spec.endure then
      target.mon.hp = 1
      if native then
        target.expEnduring = true
      else
        target.enduring = true
      end
    end
    if spec.weather then
      if native then
        b.weather = spec.weather
      else
        b.field.weather = spec.weather
      end
    end
    if spec.stab == false then
      if native then
        user.type1, user.type2 = 10, 10
      else
        user.curTypes = { "FIRE" }
      end
    end
    local types = spec.types or { "NORMAL" }
    if native then
      local ids = { NORMAL = 0, ROCK = 5, GHOST = 7, STEEL = 8 }
      target.type1, target.type2 = ids[types[1]], ids[types[2] or types[1]]
    else
      target.curTypes = types
    end
    if spec.defense then
      if native then
        target.mon.defense = spec.defense
      else
        target.curStats.defense = spec.defense
      end
    end
    b.rng = function(lo, hi)
      if lo == 85 and hi == 100 then
        calls.variation = calls.variation + 1
        return rolls
      end
      if spec.miss and lo == 1 and hi == 100 then
        return 100
      end
      if spec.miss and lo == 0 and hi == 99 then
        return 99
      end
      if spec.miss and lo == 0 and hi == 255 then
        return 255
      end
      return lo or 0
    end
    return b, user, target
  end
  local function count(a)
    return native and (a.expStockpile or 0) or (a.stockpile or 0)
  end
  local function pp(a, slot)
    return native and a.mon.pp[slot] or a.curMoves[slot].pp
  end
  local function action(b, id, slot, target)
    if native then
      local C = require("src.core.game3.battle.commands")
      f.e.choose(function()
        return { move = definitions[slot][1], target = target }
      end)
      local a = id % 2 == 0 and C.playerAction(b, 1, slot, id, target) or C.enemyAction(b, id)
      require("src.core.game3.battle.engine").resolveMove(
        id,
        a.target,
        a.move,
        a.slot,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {}
      )
    else
      f.e.choose(function()
        return { move = definitions[slot][1], target = target }
      end)
      local a = id % 2 == 0 and at(b, id).curMoves[slot] or b:enemyAction(at(b, id))
      if id % 2 == 0 then
        b.chosenTargets = { [id] = at(b, target) }
      end
      b:executeAction(at(b, id), at(b, target), a)
    end
  end
  local specs = {
    { name = "normal" },
    { name = "no-stab", stab = false },
    { name = "resist", types = { "STEEL" } },
    { name = "dual-resist", types = { "ROCK", "STEEL" } },
    { name = "immune", types = { "GHOST" } },
    { name = "low", level = 1, stat = 1, defense = 500 },
    { name = "wide", stat = 300, defense = 50 },
    { name = "helped", helped = true },
    { name = "protected", protected = true },
    { name = "substitute", substitute = 30 },
    { name = "sleep", sleep = true },
    { name = "hidden", hidden = true },
    { name = "miss", miss = true },
    { name = "burn", burn = true },
    { name = "reflect", reflect = true },
    { name = "huge-stage", stat = 55, ability = "HUGE_POWER", attackStage = 1 },
    { name = "hustle-stage", stat = 55, ability = "HUSTLE", attackStage = -1 },
    { name = "guts-burn", stat = 55, ability = "GUTS", burn = true, attackStage = 1 },
    { name = "marvel-scale", stat = 55, defAbility = "MARVEL_SCALE", defenseStage = 1 },
    { name = "scarf-stage", stat = 55, item = "NORMAL_POWER", attackStage = 1 },
    { name = "huge-band", stat = 55, ability = "HUGE_POWER", item = "CHOICE_BAND", attackStage = -1 },
    { name = "endure-zero", endure = true },
    { name = "fire-rain", moveType = "FIRE", weather = "RAIN" },
    { name = "fire-sun", moveType = "FIRE", weather = "SUN" },
    { name = "thick-fat", moveType = "FIRE", defAbility = "THICK_FAT", stat = 55, attackStage = 1 },
    {
      name = "low-dual-no-stab",
      level = 1,
      stat = 1,
      defense = 500,
      stab = false,
      types = { "ROCK", "STEEL" },
    },
    { name = "identified-ghost", types = { "GHOST" }, identified = true },
    {
      name = "plus-minus",
      moveType = "ELECTRIC",
      ability = "PLUS",
      partnerAbility = "MINUS",
      stat = 55,
      attackStage = 1,
    },
    { name = "plus-alone", moveType = "ELECTRIC", ability = "PLUS", stat = 55, attackStage = 1 },
    {
      name = "blaze-sport",
      moveType = "FIRE",
      ability = "BLAZE",
      pinch = true,
      sport = true,
      stat = 55,
      attackStage = 1,
    },
    { name = "absorbed", moveType = "ELECTRIC", defAbility = "VOLT_ABSORB" },
    { name = "wonder-guard", defAbility = "WONDER_GUARD" },
  }
  for id = 0, 3 do
    for n = 0, 3 do
      for _, spec in ipairs(specs) do
        for _, variation in ipairs({ 85, 100 }) do
          rolls = variation
          local b, user, target = fresh(spec, id)
          for i = 1, n do
            action(b, id, 1, id)
          end
          T.eq(count(user), n, "real Stockpile producer records native count")
          if spec.helped then
            action(b, (id + 2) % 4, 4, (id + 2) % 4)
          end
          if spec.protected then
            if native then
              target.expProtected = true
            else
              target.protecting = true
            end
          end
          if spec.substitute then
            target.substituteHP = spec.substitute
          end
          if spec.sleep then
            user.mon.status, user.sleepTurns = "SLP", 5
          end
          if spec.burn then
            user.mon.status = "BRN"
          end
          if spec.hidden then
            if native then
              target.semiInvulnerable = "ON_AIR"
            else
              target.invulnerable = true
            end
          end
          if spec.reflect then
            if native then
              (target.side == "player" and b.playerSide or b.enemySide).expReflectTurns = 5
            else
              target.reflect = true
            end
          end
          if spec.miss then
            local move = native and require("src.core.game3.battle.moves")._rom[255]
              or f.data.moves[f.ids.SPIT_UP]
            move.accuracy, move.accuracyRaw = 1, 1
          end
          moves, hits, calls = {}, {}, { crit = 0, damage = 0, variation = 0 }
          local before = target.mon.hp
          action(b, id, 2, target == b.player and 0 or target.position or target.id)
          if spec.name == "normal" then
            T.eq(
              before - target.mon.hp,
              45 * n,
              "Spit Up multiplies the computed base including its final +2"
            )
          end
          local expected = spec.sleep or spec.hidden or spec.miss or spec.defAbility == "VOLT_ABSORB"
          T.eq(count(user), expected and n or 0, "native count consumption follows execution outcome")
          T.eq(pp(user, 2), spec.sleep and 10 or 9, "Spit Up uses owned PP after ordinary interruption")
          T.same(
            calls,
            { crit = 0, damage = 0, variation = 0 },
            "set damage bypasses ordinary damage/critical hooks and variance"
          )
          rows[#rows + 1] = {
            case = spec.name,
            id = id,
            count = n,
            roll = variation,
            amount = before - target.mon.hp,
            stockpile = count(user),
            pp = pp(user, 2),
            hits = hits,
            moves = moves,
            calls = calls,
            substitute = target.substituteHP or 0,
          }
          if spec.miss then
            local move = native and require("src.core.game3.battle.moves")._rom[255]
              or f.data.moves[f.ids.SPIT_UP]
            move.accuracy, move.accuracyRaw = 100, 255
          end
        end
      end
    end
  end
  for _, id in ipairs({ 0, 3 }) do
    local b, user, target = fresh({}, id)
    for i = 1, 4 do
      action(b, id, 1, id)
    end
    T.eq(count(user), 3, "Stockpile caps at three after four actual casts")
    T.eq(pp(user, 1), 16, "the capped fourth cast still spends PP")
    moves, hits, calls = {}, {}, { crit = 0, damage = 0, variation = 0 }
    local before = target.mon.hp
    local targetId = id % 2 == 0 and 1 or 0
    action(b, id, 2, targetId)
    T.eq(before - target.mon.hp, 135, "capped Stockpile releases its native three-stack base")
    action(b, id, 2, targetId)
    T.eq(count(user), 0, "spent Stockpile cannot be reused")
    T.eq(pp(user, 2), 8, "a second empty Spit Up still consumes its own PP")
    T.eq(#hits, 1, "the empty second use emits no damaging hit")
    rows[#rows + 1] = {
      case = "cap-and-reuse",
      id = id,
      hits = hits,
      moves = moves,
      stockpile = count(user),
      pp = pp(user, 2),
      stockpilePP = pp(user, 1),
    }
  end
  for n = 1, 3 do
    local b, user, target = fresh({}, 0)
    for i = 1, n do
      action(b, 0, 1, 0)
    end
    user.mon.hp = 1000
    action(b, 0, 3, 0)
    T.eq(count(user), 0, "Swallow consumes the same native Stockpile counter")
    local healed = user.mon.hp
    moves, hits, calls = {}, {}, { crit = 0, damage = 0, variation = 0 }
    action(b, 0, 2, 1)
    T.eq(#hits, 0, "Swallow leaves no stored damage to release")
    rows[#rows + 1] = {
      case = "swallow-consumption",
      count = n,
      healed = healed,
      pp = pp(user, 2),
      stockpile = count(user),
      moves = moves,
      hits = hits,
    }
  end
  stopMove()
  stopHit()
  stopDamage()
  stopCrit()
  f.close()
  return rows
end
return M
