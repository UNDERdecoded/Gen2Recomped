local M = {}
local STATS = { "attack", "defense", "speed", "spatk", "spdef", "accuracy", "evasion" }
local FLAGS = {
  { "confusionTurns", "confusedTurns" },
  { "focusEnergy", "focusEnergy" },
  { "substituteHP", "substituteHP" },
  { "expSeeded", "leechSeeded" },
  { "expIngrain", "ingrained" },
  { "expPerishTurns", "perishTurns" },
  { "expCursed", "cursed" },
  { "expTrapped", "trapped" },
  { "escapePrevention", "escapePrevention" },
  { "expLockedOn", "lockOnTurns" },
  { "expLockedOnById", "lockOnByPos" },
}
function M.fixture(root, backend, version)
  local native = backend == "gen1"
  local function configure(data, _, ids, rom, names)
    local id = native and "BATON_PASS" or "MOVE_226"
    ids.BATON_PASS, names[226] = id, "BATON_PASS"
    if native then
      local move = {
        effect = 127,
        type = 0,
        power = 0,
        accuracy = 0,
        pp = 20,
        target = 16,
        flags = 0,
        secondaryChance = 0,
        priority = 0,
      }
      data.gen3Moves._rom[226], rom[226], data.gen3Pokemon._moveNames[226] = move, move, "BATON_PASS"
      data.gen3Pokemon._types[4] = { 0, 0 }
      data.gen3Pokemon._abilities[4] = { 0, 0 }
    else
      data.moves[id] = {
        id = id,
        index = 226,
        name = "BATON_PASS",
        effect = "BATON_PASS_EFFECT",
        gen3Effect = 127,
        power = 0,
        type = "NORMAL",
        accuracy = 0,
        pp = 20,
        target = 16,
        protectAffected = false,
      }
      data.pokemon.CHARMANDER.types = { "NORMAL" }
      data.pokemon.CHARMANDER.abilities = {}
    end
    local Copy = require("src.mods.Merge").deepCopy
    for _, row in ipairs({ { 1, "BULBASAUR", "GRASS", 12 }, { 7, "SQUIRTLE", "WATER", 11 } }) do
      if native then
        data.gen3Pokemon._types[row[1]] = { row[4], row[4] }
        data.gen3Pokemon._abilities[row[1]] = { 0, 0 }
      else
        local mon = Copy(data.pokemon.CHARMANDER)
        mon.id, mon.index, mon.dex, mon.types = row[2], row[1], row[1], { row[3] }
        data.pokemon[row[2]] = mon
      end
    end
    for _, row in ipairs({
      { 52, "EMBER", "FIRE", 10, 40 },
      { 55, "WATER_GUN", "WATER", 11, 40 },
      { 75, "RAZOR_LEAF", "GRASS", 12, 55 },
      { 49, "SONICBOOM", "NORMAL", 0, 1 },
    }) do
      local moveId = native and row[2] or ("MOVE_%03d"):format(row[1])
      ids[row[2]], names[row[1]] = moveId, row[2]
      if native then
        local move = {
          type = row[4],
          power = row[5],
          effect = 0,
          accuracy = 100,
          pp = 10,
          secondaryChance = 0,
          target = 0,
          priority = 0,
          flags = 0,
        }
        data.gen3Moves._rom[row[1]], rom[row[1]], data.gen3Pokemon._moveNames[row[1]] = move, move, row[2]
      else
        data.moves[moveId] = {
          id = moveId,
          index = row[1],
          name = row[2],
          type = row[3],
          power = row[5],
          pp = 10,
          accuracy = 100,
          effect = "NO_ADDITIONAL_EFFECT",
        }
      end
    end
    if not native then
      for _, kind in ipairs({ "FIRE", "WATER", "GRASS" }) do
        data.type_chart.matchups[#data.type_chart.matchups + 1] =
          { attacker = kind, defender = kind, multiplier = 5 }
      end
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  return f
end
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = M.fixture(root, backend, version)
  local T, Copy, rows = f.T, require("src.mods.Merge").deepCopy, {}
  local events, draws = {}, {}
  local stop = f.e.api.events:on("battle.battler_switched", function(e)
    events[#events + 1] = { name = e.battler.mon.nickname, old = e.previous.mon.nickname, reason = e.reason }
  end)
  local function at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  local function actor(mon, id)
    if native then
      return require("src.core.game3.battle.state").makeBattler(
        mon,
        id % 2 == 0 and "player" or "enemy",
        { id = id, partyIndex = id < 2 and 1 or 2 }
      )
    end
    return require("src.battle.BattleState").makeBattler(f.data, mon, id % 2 == 0)
  end
  local function fresh(double)
    local b = f.fresh("TACKLE", { enemy = true }).battle
    b.double = double
    if not native then
      b:syncSides()
    end
    if double then
      for id = 2, 3 do
        local a = actor(Copy(at(b, id % 2).mon), id)
        if native then
          b.battlers[id] = a
        else
          b:placeBattler(id, a)
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
        a.mon.moves, a.mon.pp, a.mon.maxPp = { 226, 33 }, { 20, 10 }, { 20, 10 }
        a.type1, a.type2, a.ability, a.mon.ability = 0, nil, 0, 0
      else
        a.mon.moves = { { id = f.ids.BATON_PASS, pp = 20 }, { id = f.ids.TACKLE, pp = 10 } }
        a.curMoves, a.curTypes, a.abilityOverride = a.mon.moves, { "NORMAL" }, false
      end
    end
    local function party(side)
      local out = { at(b, side).mon }
      if double then
        out[2] = at(b, side + 2).mon
      end
      for i = 1, 2 do
        local m = Copy(out[1])
        m.nickname = "BENCH_" .. side .. "_" .. i
        out[#out + 1] = m
      end
      return out
    end
    if native then
      b.playerParty, b.foeParty = party(0), party(1)
    else
      b.game.save.party, b.enemyParty = party(0), party(1)
    end
    b.rng = function(lo, hi)
      draws[#draws + 1] = { lo = lo, hi = hi, value = hi }
      return hi
    end
    return b
  end
  local function view(a)
    local stages, flags = {}, {}
    for _, k in ipairs(STATS) do
      local key = native and ({ spatk = "spAtk", spdef = "spDef" })[k] or k
      stages[k] = (a.stages or {})[key or k] or 0
    end
    for _, pair in ipairs(FLAGS) do
      flags[pair[2]] = a[native and pair[1] or pair[2]]
    end
    return {
      name = a.mon.nickname,
      stages = stages,
      flags = flags,
      hp = a.mon.hp,
      last = a.lastMove and (native and a.lastMove or f.data.moves[a.lastMove].index),
      disabled = a.disabledTurns or a.expDisabledTurns,
      taunt = a.tauntTurns or a.expTauntedTurns,
    }
  end
  for _, double in ipairs({ false, true }) do
    for id = 0, double and 3 or 1 do
      for _, kind in ipairs({
        "first",
        "last",
        "invalid",
        "confusion",
        "volatiles",
        "none",
        "interactive",
        "egg",
        "reserved",
        "bindings",
        "spikes1",
        "spikes2",
        "spikes3",
        "called",
      }) do
        events, draws = {}, {}
        local b = fresh(double)
        local user = at(b, id)
        local old = user
        local party = native and (id % 2 == 0 and b.playerParty or b.foeParty)
          or (id % 2 == 0 and b.game.save.party or b.enemyParty)
        local offset = double and 2 or 1
        user.stages.attack, user.stages.defense = 2, -1
        user.lastMove = native and 33 or f.ids.TACKLE
        if kind == "confusion" then
          user[native and "confusionTurns" or "confusedTurns"] = 3
        end
        if kind == "volatiles" then
          for _, pair in ipairs(FLAGS) do
            if pair[2] ~= "confusedTurns" and pair[2] ~= "lockOnByPos" then
              user[native and pair[1] or pair[2]] = pair[2] == "perishTurns" and 3
                or pair[2] == "substituteHP" and 25
                or true
            end
          end
          user[native and "expLockedOn" or "lockOnTurns"] = 2
          user[native and "expLockedOnBy" or "lockOnBy"] = native and "enemy" or false
          user[native and "expLockedOnById" or "lockOnByPos"] = 1
        end
        if kind == "none" then
          for i = offset + 1, #party do
            party[i].hp = 0
          end
        end
        if kind == "egg" then
          party[offset + 1].isEgg = true
        end
        if kind == "reserved" and double then
          b.monToSwitchInto = { [id < 2 and id + 2 or id - 2] = offset + 1 }
        end
        if kind == "bindings" then
          local foe = at(b, id % 2 == 0 and 1 or 0)
          user[native and "expSeeded" or "leechSeeded"] = true
          user[native and "expSeedSource" or "leechSeedSource"] = foe
          foe[native and "expSeedSource" or "leechSeedSource"] = user
          foe[native and "expSeeded" or "leechSeeded"] = true
          foe[native and "expInfatuatedWith" or "infatuated"] = user
          if native then
            foe.expInfatuated = true
          end
        end
        local layers = tonumber(kind:match("^spikes(%d)$"))
        if layers then
          local side = native and (id % 2 == 0 and b.playerSide or b.enemySide) or b:sideOf(user)
          side.spikes = layers
        end
        local selected = kind == "last" and #party or kind == "invalid" and 99 or offset + 1
        local interactive = kind == "interactive"
        b.interactiveChoices = interactive
        if not interactive then
          b.batonPassChooser = function()
            return selected
          end
        end
        if native then
          require("src.core.game3.battle.engine").resolveMove(
            id,
            id,
            226,
            kind ~= "called" and 1 or nil,
            require("src.core.game3.battle.adapter").new(b),
            b,
            { called = kind == "called" }
          )
        else
          if kind == "called" then
            b:performMove(user, user, user.curMoves[1], true)
          else
            b:executeAction(user, user, user.curMoves[1])
          end
        end
        local before = { actor = view(at(b, id)), pp = native and old.mon.pp[1] or old.mon.moves[1].pp }
        if interactive and id % 2 == 0 then
          if native then
            require("src.core.game3.battle.engine").resumeChoice(
              b,
              require("src.core.game3.battle.adapter").new(b),
              #party
            )
          else
            local pending = b._gen3BatonPending
            T.check(pending ~= nil, "native move pauses for party choice")
            T.eq(at(b, id), old, "no replacement before the choice")
            T.check(
              require("src.battle.Gen3BatonPass").select(b, pending, #party),
              "explicit last eligible member is accepted"
            )
            require("src.battle.Gen3BatonPass").await(b, pending)
          end
        end
        T.eq(
          native and old.mon.pp[1] or old.mon.moves[1].pp,
          kind == "called" and 20 or 19,
          "Baton Pass spends donor PP once; called moves do not spend their own PP"
        )
        if kind ~= "none" then
          T.check(at(b, id) ~= old, "native Baton Pass replaces its own slot")
          T.eq(at(b, id).stages.attack, 2, "attack stage is inherited")
          T.eq(at(b, id).stages.defense, -1, "defense stage is inherited")
        end
        rows[#rows + 1] = {
          double = double,
          id = id,
          kind = kind,
          before = before,
          after = view(at(b, id)),
          events = Copy(events),
          draws = Copy(draws),
          oldLast = view(old).last,
          seedFrom = ((at(b, id)[native and "expSeedSource" or "leechSeedSource"] or {}).mon or {}).nickname,
          foeSeedFrom = ((
            at(b, id % 2 == 0 and 1 or 0)[native and "expSeedSource" or "leechSeedSource"] or {}
          ).mon or {}).nickname,
          foeInfatuated = at(b, id % 2 == 0 and 1 or 0)[native and "expInfatuated" or "infatuated"] ~= nil,
        }
      end
    end
  end
  local typeIds = { NORMAL = 0, FIRE = 10, WATER = 11, GRASS = 12 }
  for _, double in ipairs({ false, true }) do
    for _, id in ipairs(double and { 1, 3 } or { 1 }) do
      for _, types in ipairs({
        { "NORMAL" },
        { "FIRE" },
        { "WATER" },
        { "GRASS" },
        { "FIRE", "GRASS" },
        { "WATER", "GRASS" },
      }) do
        for _, moves in ipairs({
          { "EMBER", "WATER_GUN" },
          { "RAZOR_LEAF", "EMBER" },
          { "SONICBOOM", "TACKLE" },
          { "BATON_PASS", "TACKLE" },
        }) do
          events, draws = {}, {}
          local b, selected = fresh(double)
          local user = at(b, id)
          for pos = 0, double and 2 or 0, 2 do
            local foe = at(b, pos)
            if native then
              foe.type1, foe.type2 = typeIds[types[1]], types[2] and typeIds[types[2]]
            else
              foe.curTypes = Copy(types)
            end
          end
          local party = native and b.foeParty or b.enemyParty
          local offset = double and 2 or 1
          for j = 1, 2 do
            local mon = party[offset + j]
            mon.species = native and (j == 1 and 1 or 7) or (j == 1 and "BULBASAUR" or "SQUIRTLE")
            if native then
              local number = ({
                EMBER = 52,
                WATER_GUN = 55,
                RAZOR_LEAF = 75,
                SONICBOOM = 49,
                TACKLE = 33,
                BATON_PASS = 226,
              })[moves[j]]
              mon.moves, mon.pp, mon.maxPp = { number }, { 0 }, { 10 }
            else
              mon.moves = { { id = f.ids[moves[j]], pp = 0 } }
            end
          end
          if native then
            selected = require("src.core.game3.battle.engine").mostSuitableMon(
              b,
              require("src.core.game3.battle.adapter").new(b),
              id
            )
          else
            local candidates, ownParty = require("src.battle.Gen3BatonPass").candidates(b, user)
            selected = require("src.battle.Gen3BatonPass").enemyChoice(b, user, candidates, ownParty)
          end
          rows[#rows + 1] = {
            kind = "native_ai",
            double = double,
            id = id,
            types = types,
            moves = moves,
            selected = selected,
            draws = Copy(draws),
          }
        end
      end
    end
  end
  stop()
  f.close()
  return rows
end
return M
