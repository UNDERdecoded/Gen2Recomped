local M = {}
function M.run(root, backend, version, patchStats)
  local native = backend == "gen1"
  local species = {
    { "CHARMANDER", 4, 60, 40 },
    { "CHARMELEON", 5, 90, 70 },
    { "PIDGEY", 16, 110, 30 },
    { "NIDORAN_F", 29, 45, 50 },
    { "MEW", 151, 100, 100 },
  }
  local function configure(data, engine, ids, rom, names)
    for _, r in ipairs({
      { "BEAT_UP", 251, 154, "BEAT_UP_EFFECT", 10, 0, 0 },
      { "HELPING_HAND", 270, 176, "HELPING_HAND_EFFECT", 0, 16, 5 },
    }) do
      local name, num, effect, handler, power, target, priority = unpack(r)
      local key = engine == "gen1" and name or ("MOVE_%03d"):format(num)
      ids[name], names[num] = key, name
      if engine == "gen1" then
        local d = {
          effect = effect,
          power = power,
          type = 17,
          target = target,
          priority = priority,
          accuracy = 100,
          pp = 20,
          flags = power == 0 and 0 or 2,
          secondaryChance = 0,
        }
        data.gen3Moves._rom[num], rom[num], data.gen3Pokemon._moveNames[num] = d, d, name
      else
        data.moves[key] = {
          id = key,
          index = num,
          name = name,
          gen3Effect = effect,
          effect = handler,
          power = power,
          type = "DARK",
          target = target,
          priority = priority,
          accuracy = 100,
          accuracyRaw = 255,
          pp = 20,
          protectAffected = power ~= 0,
          makesContact = false,
        }
      end
    end
    for _, r in ipairs(species) do
      local name, num, attack, defense = unpack(r)
      if engine == "gen1" then
        data.gen3Pokemon._stats[num] = { hp = 50, atk = attack, def = defense, spe = 50, spa = 50, spd = 50 }
        data.gen3Pokemon._types[num] = { 0, 0 }
      else
        local d = require("src.mods.Merge").deepCopy(data.pokemon.CHARMANDER)
        d.id, d.name, d.index, d.dex, d.evolutions, d.types = name, name, num, num, {}, { "NORMAL" }
        d.baseStats =
          { hp = 50, attack = attack, defense = defense, speed = 50, special = 50, spatk = 50, spdef = 50 }
        d.evYield = { attack = 1 }
        data.pokemon[name] = d
      end
    end
    if engine == "gen2" then
      data.type_chart.types = {
        NORMAL = { id = "NORMAL", index = 0, category = "physical" },
        DARK = { id = "DARK", index = 17, category = "special" },
        GHOST = { id = "GHOST", index = 7, category = "physical" },
        FIGHTING = { id = "FIGHTING", index = 1, category = "physical" },
      }
      data.type_chart.matchups = {
        { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
        { attacker = "DARK", defender = "FIGHTING", multiplier = 5 },
        { attacker = "DARK", defender = "GHOST", multiplier = 20 },
      }
    end
  end
  local entry
  if patchStats then
    entry = [[return function(mod)
      assert(mod.content.pokemon:patch("MEW", {baseStats={attack=133}}))
      mod.exports.baseAttack=assert(mod.content.pokemon:get("MEW")).baseStats.attack
      local choice
      mod.hooks:wrap("battle.enemy_action",function(nextAction,...)
        if choice then return choice(nextAction,...) end
        return nextAction(...)
      end)
      mod.exports.choose=function(callback) choice=callback end
      mod.exports.api=mod
    end]]
  end
  local f = dofile(root .. "/tests/enemy_actions/fixture.lua").new(
    root,
    backend,
    version,
    3,
    "unified",
    configure,
    entry
  )
  local T, rows, moves, hits, calls, trace = f.T, {}, {}, {}, { crit = 0, damage = 0 }, {}
  if patchStats then
    T.eq(f.e.baseAttack, 133, "the identical API-3 species patch loads through both real SDKs")
  end
  local mutate
  local stopCrit = f.e.api.hooks:wrap("battle.crit", function()
    calls.crit = calls.crit + 1
    return true
  end)
  local stopDamage = f.e.api.hooks:wrap("battle.damage", function(nextDamage, ...)
    calls.damage = calls.damage + 1
    return nextDamage(...)
  end)
  local stopMove = f.e.api.events:on("battle.move_used", function(e)
    moves[#moves + 1] = { user = e.user.mon.nickname, target = e.target.mon.nickname, move = e.move.id }
  end)
  local stopHit = f.e.api.events:on("battle.damage_dealt", function(e)
    hits[#hits + 1] = {
      user = e.user.mon.nickname,
      target = e.target.mon.nickname,
      move = e.move.id,
      amount = e.damage,
      crit = e.crit,
      typeMult = e.typeMult,
      kind = e.kind,
      substitute = e.substitute or false,
    }
    if mutate then
      mutate(#hits)
    end
  end)
  local function at(b, id)
    if native then
      return b.battlers[id]
    end
    return b:battlerAt(id)
  end
  local function put(b, id, a)
    if native then
      b.battlers[id] = a
      if id == 0 then
        b.player = a
      elseif id == 1 then
        b.enemy = a
      end
    else
      b:placeBattler(id, a)
    end
  end
  local function make(mon, id, index)
    if native then
      return require("src.core.game3.battle.state").makeBattler(
        mon,
        id % 2 == 0 and "player" or "enemy",
        { id = id, partyIndex = index }
      )
    end
    local a = require("src.battle.BattleState").makeBattler(f.data, mon, id % 2 == 0)
    a.partyIndex = index
    return a
  end
  local function fresh(spec, userId)
    moves, hits, calls, trace, mutate = {}, {}, { crit = 0, damage = 0 }, {}, nil
    local b, copy = f.fresh("TACKLE", { enemy = true }).battle, require("src.mods.Merge").deepCopy
    local template = copy(b.player.mon)
    local function party(prefix)
      local p = {}
      for i = 1, 6 do
        local mon = copy(template)
        local r = species[(i - 1) % #species + 1]
        mon.species, mon.level, mon.hp, mon.nickname = native and r[2] or r[1], 5 + i * 5, 10000, prefix .. i
        if native then
          mon.maxHp, mon.ability, mon.moves, mon.pp, mon.maxPp =
            10000, 0, { 251, 270 }, { 20, 20 }, { 20, 20 }
          for _, k in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do
            mon[k] = 50
          end
        else
          mon.moves = { { id = f.ids.BEAT_UP, pp = 20 }, { id = f.ids.HELPING_HAND, pp = 20 } }
          mon.stats =
            { hp = 10000, attack = 50, defense = 50, speed = 50, special = 50, spatk = 50, spdef = 50 }
        end
        if spec.filter and i >= 3 then
          if i == 3 then
            mon.status = "PSN"
          elseif i == 4 then
            mon.hp = 0
          elseif i == 5 then
            mon.isEgg = true
          else
            mon.status = 0
          end
        end
        if spec.allBlocked then
          mon.status = "PSN"
        end
        if spec.onlyOne and i > 1 then
          mon.status = "PSN"
        end
        p[i] = mon
      end
      return p
    end
    local player, enemy = party("A"), party("B")
    b.double = true
    if native then
      b.playerParty, b.foeParty = player, enemy
    else
      f.game.save.party, b.enemyParty = player, enemy
    end
    for id = 0, 3 do
      local p = id % 2 == 0 and player or enemy
      local index = id < 2 and 1 or 2
      put(b, id, make(p[index], id, index))
      local a = at(b, id)
      if native then
        a.ability, a.mon.ability = 0, 0
      else
        a.abilityOverride = false
      end
    end
    if not native then
      b:syncSides()
    end
    local user = at(b, userId)
    local target = at(b, userId % 2 == 0 and 1 or 0)
    local p = userId % 2 == 0 and player or enemy
    if spec.empty then
      if native then
        if userId % 2 == 0 then
          b.playerParty = {}
        else
          b.foeParty = {}
        end
      else
        if userId % 2 == 0 then
          f.game.save.party = {}
        else
          b.enemyParty = {}
        end
      end
    end
    if spec.typeName then
      local ids = { NORMAL = 0, DARK = 17, GHOST = 7, FIGHTING = 1 }
      if native then
        target.type1, target.type2 = ids[spec.typeName], ids[spec.typeName]
      else
        target.curTypes = { spec.typeName }
      end
    end
    if spec.normalMove then
      if native then
        require("src.core.game3.battle.moves")._rom[251].type = 0
      else
        f.data.moves[f.ids.BEAT_UP].type = "NORMAL"
      end
    else
      if native then
        require("src.core.game3.battle.moves")._rom[251].type = 17
      else
        f.data.moves[f.ids.BEAT_UP].type = "DARK"
      end
    end
    if spec.targetSpecies then
      target.species = native and 151 or "MEW"
    end
    if spec.userSpecies then
      user.species = native and 151 or "MEW"
    end
    if spec.battleStats then
      if native then
        user.mon.attack, target.mon.defense = 999, 1
      else
        user.curStats.attack, target.curStats.defense = 999, 1
      end
      user.stages.attack, target.stages.defense = 6, -6
    end
    if spec.battleParty and not native and user.isPlayer then
      b.playerParty = player
      f.game.save.party = {}
    end
    if spec.defAbility then
      if native then
        local ab = require("src.core.game3.battle.abilities").id(spec.defAbility)
        target.ability, target.mon.ability = ab, ab
      else
        target.abilityOverride = spec.defAbility
      end
    end
    if spec.dynamic == "wake" then
      p[3].status = "PSN"
    end
    if spec.sleep then
      user.mon.status, user.sleepTurns = "SLP", 5
    end
    if spec.protected then
      if native then
        target.expProtected = true
      else
        target.protecting = true
      end
    end
    if spec.hidden then
      if native then
        target.semiInvulnerable = "ON_AIR"
      else
        target.invulnerable = true
      end
    end
    if spec.substitute then
      target.substituteHP = spec.substitute
    end
    if spec.endure then
      target.mon.hp = 4
      if native then
        target.expEnduring = true
      else
        target.enduring = true
      end
    end
    if spec.lowHP then
      target.mon.hp = spec.lowHP
    end
    local phase, number = "critical", 0
    b.rng = function(lo, hi)
      if lo == 1 and hi == 100 then
        return spec.miss and 100 or 1
      end
      if lo == 0 and hi == 255 then
        return spec.miss and 255 or 0
      end
      if
        phase == "critical"
        and (
          (lo == 0 and (hi == 15 or hi == 7 or hi == 3 or hi == 2 or hi == 1))
          or (lo == 1 and (hi == 16 or hi == 8 or hi == 4 or hi == 3 or hi == 2))
        )
      then
        number = number + 1
        local choices = spec.critical or { false }
        local critical = choices[(number - 1) % #choices + 1]
        phase = "variation"
        trace[#trace + 1] = { kind = "critical", value = critical }
        return critical and lo or hi
      end
      if (lo == 85 and hi == 100) or (phase == "variation" and lo == 0 and hi == 15) then
        local variation = spec.variation or 100
        phase = "critical"
        trace[#trace + 1] = { kind = "variation", value = variation }
        return lo == 85 and variation or 100 - variation
      end
      return lo or 0
    end
    return b, user, target, p
  end
  local function pp(a)
    return native and a.mon.pp[1] or a.curMoves[1].pp
  end
  local function use(b, id)
    local target = id % 2 == 0 and 1 or 0
    f.e.choose(function()
      return { move = "BEAT_UP", target = target }
    end)
    if native then
      local C = require("src.core.game3.battle.commands")
      local a = id % 2 == 0 and C.playerAction(b, 1, 1, id, target) or C.enemyAction(b, id)
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
      if id % 2 == 0 then
        b.chosenTargets = { [id] = at(b, target) }
      end
      local a = id % 2 == 0 and at(b, id).curMoves[1] or b:enemyAction(at(b, id))
      b:executeAction(at(b, id), at(b, target), a)
    end
  end
  local specs = {
    { name = "mixed-team" },
    { name = "filtered", filter = true },
    { name = "all-blocked", allBlocked = true },
    { name = "one", onlyOne = true },
    { name = "empty", empty = true },
    { name = "resist", typeName = "FIGHTING" },
    { name = "super", typeName = "GHOST" },
    { name = "authored-normal-ghost", normalMove = true, typeName = "GHOST" },
    { name = "ignores-battle-stats", battleStats = true },
    { name = "target-active-species", targetSpecies = true },
    { name = "user-active-species", userSpecies = true },
    { name = "critical-each", critical = { true } },
    { name = "critical-mixed", critical = { false, true, false, true } },
    { name = "variation", variation = 85 },
    { name = "protected", protected = true },
    { name = "sleep", sleep = true },
    { name = "hidden", hidden = true },
    { name = "sub-break", substitute = 1 },
    { name = "sub-survive", substitute = 1000 },
    { name = "ko-stop", lowHP = 1 },
    { name = "endure", endure = true },
    { name = "miss", miss = true },
    { name = "helped", helped = true },
    { name = "helped-critical", helped = true, critical = { true } },
    { name = "armor-critical", defAbility = "BATTLE_ARMOR", critical = { true } },
    { name = "battle-scoped-party", battleParty = true },
    { name = "callback-wake", dynamic = "wake" },
    { name = "callback-block", dynamic = "block" },
    { name = "callback-faint", dynamic = "faint" },
    { name = "callback-species", dynamic = "species" },
    { name = "callback-user-hp", dynamic = "userHP" },
    { name = "accuracy-wake", allBlocked = true, dynamic = "accuracy" },
  }
  for id = 0, 3 do
    for _, spec in ipairs(specs) do
      local b, user, target, party = fresh(spec, id)
      if spec.miss then
        local m = native and require("src.core.game3.battle.moves")._rom[251] or f.data.moves[f.ids.BEAT_UP]
        m.accuracy, m.accuracyRaw = 1, 1
      end
      if spec.helped then
        local helperId = (id + 2) % 4
        if native then
          require("src.core.game3.battle.engine").resolveMove(
            helperId,
            helperId,
            270,
            2,
            require("src.core.game3.battle.adapter").new(b),
            b,
            {}
          )
        else
          b:executeAction(at(b, helperId), at(b, helperId), at(b, helperId).curMoves[2])
        end
        moves, hits, calls, trace = {}, {}, { crit = 0, damage = 0 }, {}
      end
      if spec.dynamic then
        mutate = function(number)
          if number ~= 1 then
            return
          end
          if spec.dynamic == "wake" then
            party[3].status = nil
          elseif spec.dynamic == "block" then
            party[3].status = "PSN"
          elseif spec.dynamic == "faint" then
            party[3].hp = 0
          elseif spec.dynamic == "species" then
            party[2].species = native and 151 or "MEW"
          elseif spec.dynamic == "userHP" then
            user.mon.hp = 0
          end
        end
      end
      local stopAccuracy
      if spec.dynamic == "accuracy" then
        stopAccuracy = f.e.api.hooks:wrap("battle.accuracy", function(nextAccuracy, ...)
          party[3].status = nil
          return nextAccuracy(...)
        end)
      end
      local before = target.mon.hp
      use(b, id)
      if stopAccuracy then
        stopAccuracy()
      end
      T.eq(pp(user), spec.sleep and 20 or 19, "native Beat Up spends PP once, not per participant")
      T.same(
        calls,
        { crit = 0, damage = 0 },
        "native Beat Up bypasses ordinary damage and public critical callbacks"
      )
      if spec.name == "mixed-team" then
        T.eq(#hits, 6, "six healthy members each contribute a real strike")
      end
      if
        spec.name == "mixed-team"
        or spec.name == "critical-each"
        or spec.name == "variation"
        or spec.name == "target-active-species"
        or spec.name == "user-active-species"
      then
        local amounts = {}
        for _, h in ipairs(hits) do
          amounts[#amounts + 1] = h.amount
        end
        local expected = spec.name == "target-active-species" and { 2, 3, 4, 3, patchStats and 5 or 4, 3 }
          or spec.name == "critical-each" and { 6, 10, 14, 8, patchStats and 22 or 18, 12 }
          or spec.name == "variation" and { 2, 4, 5, 3, patchStats and 9 or 7, 5 }
          or { 3, 5, 7, 4, patchStats and 11 or 9, 6 }
        T.same(amounts, expected, "native per-member level/base/critical/variation rounding")
      end
      if spec.dynamic == "accuracy" then
        T.eq(#hits, 1, "eligibility is read after the public accuracy callback")
      end
      if spec.dynamic == "wake" then
        T.eq(#hits, 6, "later participants can become eligible after a hit")
      end
      if spec.dynamic == "block" or spec.dynamic == "faint" then
        T.eq(#hits, 5, "later participant conditions are read live")
      end
      if spec.name == "filtered" then
        T.eq(#hits, 3, "poisoned, fainted and egg entries are excluded, numeric-zero status is healthy")
      end
      if spec.name == "all-blocked" or spec.name == "empty" then
        T.eq(#hits, 0, "no eligible members produces no hit")
      end
      if spec.name == "sub-break" then
        T.eq(#hits, 6, "later members continue after the Substitute breaks")
      end
      if spec.name == "ko-stop" then
        T.eq(#hits, 1, "remaining strikes stop when the target faints")
      end
      local memory = native and (target.lastSpecialDamageTaken or 0) or (target.specialDamageTaken or 0)
      if spec.endure then
        T.eq(target.mon.hp, 1, "Endure retains one HP through the remaining strikes")
        T.eq(#hits, 6, "zero-damage Endure strikes still execute")
        T.eq(memory, 0, "the final zero-damage strike replaces earlier special counter memory")
      end
      if spec.name == "mixed-team" then
        T.eq(memory, 6, "special counter memory keeps the final strike, not their sum")
      end
      rows[#rows + 1] = {
        case = spec.name,
        id = id,
        hits = hits,
        moves = moves,
        trace = trace,
        calls = calls,
        amount = before - target.mon.hp,
        pp = pp(user),
        specialMemory = memory,
        substitute = target.substituteHP or 0,
      }
    end
  end
  stopHit()
  stopMove()
  stopDamage()
  stopCrit()
  f.close()
  return rows
end
return M
