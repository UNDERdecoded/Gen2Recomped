-- Controlled native-shaped inputs. The source engine and its handlers remain
-- unchanged; all mounted item/move tables belong to this fixture.
local M = {}
local NUMBERS = { TACKLE = 33, SCRATCH = 10, FLY = 19, STRUGGLE = 165, SLEEP_TALK = 214, BATON_PASS = 226 }
function M.fixture(root, backend, version, options)
  options = options or {}
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/fixture.lua").new(
    root,
    backend,
    version,
    options.api or 3,
    options.format or "unified",
    function(data, _, ids, rom, names)
      for _, row in ipairs({
        { 214, "SLEEP_TALK", 97, "SLEEP_TALK_EFFECT", 0, 1 },
        { 226, "BATON_PASS", 127, "BATON_PASS_EFFECT", 0, 16 },
      }) do
        local number, name, effect, binding, power, target = unpack(row)
        ids[name] = native and name or ("MOVE_%03d"):format(number)
        names[number] = name
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
          data.gen3Moves._rom[number], rom[number], data.gen3Pokemon._moveNames[number] = def, def, name
        else
          data.moves[ids[name]] = {
            id = ids[name],
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
      for _, row in ipairs({
        { 186, "CHOICE_BAND", "CHOICE_BAND", 29 },
        { 529, "IMITATION_BAND", "CHOICE_BAND", 29 },
        { 500, "PLAIN_TOKEN", nil, 0 },
      }) do
        local number, name, effect, byte = unpack(row, 1, 4)
        if native then
          data.gen3Items._byId[number] = {
            name = name:gsub("_", " "),
            pocket = "ITEMS",
            price = 10,
            holdEffect = byte,
            holdEffectParam = 0,
          }
        else
          local id = ("ITEM_%03d"):format(number)
          data.items[id] = {
            id = id,
            index = number,
            name = name:gsub("_", " "),
            price = 10,
            holdEffect = effect,
            gen3HoldEffect = byte,
            holdEffectParam = 0,
          }
        end
      end
      if native then
        data.gen3Pokemon._types[4], data.gen3Pokemon._abilities[4] = { 0, 0 }, { 0, 0 }
      else
        data.constants.generation = 3
        data.pokemon.CHARMANDER.types, data.pokemon.CHARMANDER.abilities = { "NORMAL" }, {}
      end
    end,
    options.entry
  )
  if native then
    local Items = require("src.core.game3.items_data")
    local previous, close = Items._byId, f.close
    Items._byId = f.data.gen3Items._byId
    f.close = function()
      Items._byId = previous
      close()
    end
  end
  function f.hold(user, number)
    user.mon.item = native and (number or 0) or number and ("ITEM_%03d"):format(number) or nil
    if native then
      user.item = number or 0
    end
  end
  function f.moves(user, names, pp)
    if native then
      user.mon.moves, user.mon.pp, user.mon.maxPp = {}, {}, {}
      for slot, name in ipairs(names) do
        user.mon.moves[slot], user.mon.pp[slot], user.mon.maxPp[slot] = NUMBERS[name], pp or 10, 10
      end
    else
      user.mon.moves = {}
      for slot, name in ipairs(names) do
        user.mon.moves[slot] = { id = f.ids[name], pp = pp or 10 }
      end
      user.curMoves = user.mon.moves
    end
  end
  function f.moveId(name)
    return native and NUMBERS[name] or f.ids[name]
  end
  function f.at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  function f.field(double)
    local b = f.fresh("TACKLE").battle
    b.double = double
    if not native then
      b:syncSides()
    end
    if double then
      local Copy = require("src.mods.Merge").deepCopy
      for id = 2, 3 do
        local mon = Copy(f.at(b, id % 2).mon)
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
      local a = f.at(b, id)
      a.mon.nickname, a.mon.hp = "P" .. id, 400
      f.moves(a, { "TACKLE", "SCRATCH", "SLEEP_TALK", "STRUGGLE" })
      f.hold(a, nil)
      if native then
        a.mon.maxHp, a.type1, a.type2, a.ability, a.mon.ability = 400, 0, 0, 0, 0
        a.mon.attack, a.mon.defense, a.mon.spAtk, a.mon.spDef, a.mon.speed = 50, 50, 50, 50, 100 - id * 10
      else
        a.curTypes, a.abilityOverride, a.mon.stats.hp = { "NORMAL" }, false, 400
        a.curStats.attack, a.curStats.defense, a.curStats.spatk, a.curStats.spdef = 50, 50, 50, 50
        a.curStats.speed = 100 - id * 10
      end
    end
    b.phase, b.queue, b.current = "moveSelect", {}, nil
    return b
  end
  return f
end
function M.run(root, backend, version)
  local native, f = backend == "gen1", M.fixture(root, backend, version)
  local T, rows = f.T, {}
  local cases = {
    { name = "first-choice", move = "TACKLE", expected = 33 },
    { name = "second-slot", move = "SCRATCH", expected = 10 },
    { name = "existing-choice", move = "SCRATCH", previous = 33, expected = 33 },
    { name = "empty-hand", move = "TACKLE", item = false },
    { name = "ordinary-item", move = "TACKLE", item = 500 },
    { name = "effect-on-other-item", move = "TACKLE", item = 529, expected = 33 },
    { name = "empty-hand-substitution", move = "TACKLE", item = false, force = true, expected = 33 },
    { name = "suppressed-effect", move = "TACKLE", suppress = true },
    { name = "suppressed-existing", move = "SCRATCH", suppress = true, previous = 33, expected = 33 },
    { name = "lost-item-keeps-choice", move = "SCRATCH", item = false, previous = 33, expected = 33 },
    { name = "lost-move-clears-after-read", move = "TACKLE", previous = 10, learned = { "TACKLE" } },
    { name = "lost-move-without-item", move = "TACKLE", previous = 10, learned = { "TACKLE" }, item = false },
    { name = "struggle-does-not-bind", move = "STRUGGLE" },
    { name = "struggle-keeps-choice", move = "STRUGGLE", previous = 33, expected = 33 },
    { name = "successful-baton", move = "BATON_PASS", learned = { "BATON_PASS", "TACKLE" } },
    {
      name = "failed-baton",
      move = "BATON_PASS",
      failed = true,
      learned = { "BATON_PASS", "TACKLE" },
      expected = 226,
    },
    {
      name = "native-called-provenance",
      move = "TACKLE",
      caller = "SLEEP_TALK",
      learned = { "SLEEP_TALK", "SCRATCH" },
      expected = 214,
    },
    {
      name = "native-called-baton",
      move = "BATON_PASS",
      caller = "SLEEP_TALK",
      learned = { "SLEEP_TALK", "SCRATCH" },
      expected = 214,
    },
    { name = "custom-called-without-native-caller", move = "TACKLE", called = true, expected = 33 },
    { name = "disobedience-command-guard", move = "TACKLE", notObeyed = true },
  }
  for _, case in ipairs(cases) do
    for _, enemy in ipairs({ false, true }) do
      local c = f.fresh("TACKLE", { enemy = enemy })
      local b, user, target = c.battle, c.user, c.target
      if not native then
        b:syncSides()
      end
      user.mon.nickname, target.mon.nickname = "USER", "TARGET"
      f.moves(user, case.learned or { "TACKLE", "SCRATCH" })
      f.hold(user, case.item == nil and 186 or case.item or nil)
      f.hold(target, nil)
      user.choicedMove = case.previous
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
        if ctx.trigger == "check" and ctx.mon.nickname == "USER" then
          if case.suppress then
            return nil, 0
          end
          if case.force then
            return "HELD_CHOICE_BAND", 0
          end
        end
        return nextRead(ctx)
      end)
      b.rng = function(lo, hi)
        draws[#draws + 1] = { lo, hi, hi }
        return hi
      end
      if native then
        local Moves = require("src.core.game3.battle.moves")
        local id = f.moveId(case.move)
        require("src.core.game3.battle.engine").moveEndEffects({
          st = b,
          adapter = require("src.core.game3.battle.adapter").new(b),
          user = user,
          target = target,
          moveId = id,
          move = Moves.get(id),
          opts = { calledBy = case.caller and f.moveId(case.caller), called = case.called },
          firstDmg = 0,
          failed = case.failed,
          notObeyed = case.notObeyed,
        })
      else
        b._gbaMoveFrame = {
          user = user,
          moveId = f.moveId(case.move),
          move = b.data.moves[f.moveId(case.move)],
          calledBy = case.caller and f.moveId(case.caller),
          failed = case.failed,
          notObeyed = case.notObeyed,
        }
        require("src.battle.GbaItemSchedule").moveEnd(b)
        b._gbaMoveFrame = nil
      end
      off()
      T.eq(user.choicedMove, case.expected, "native move-end binds or cleans the learned choice")
      T.eq(#trace, case.notObeyed and 2 or 3, "complete zero-damage move-end held read sequence")
      T.eq(#draws, 0, "choice command consumes no RNG")
      T.eq(#f.result.errors, 0, "public hook chain remains error-free")
      rows[#rows + 1] = {
        case = case.name,
        enemy = enemy,
        choice = user.choicedMove,
        trace = trace,
        draws = draws,
        userHp = user.mon.hp,
        targetHp = target.mon.hp,
      }
    end
  end
  f.close()
  return rows
end
return M
