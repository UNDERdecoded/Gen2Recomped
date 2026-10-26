-- Execute actual scripts and public event dispatch on unchanged native code.
-- Observe event-visible PP, mutations, command order, final state and all RNG.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local entry = [=[return function(mod)
    assert(mod.content.move_effects:register("PP_CALL_EFFECT", {kind="primary",run=function(ctx)
      ctx.callMove("TACKLE"); return {}
    end}))
    assert(mod.content.moves:register("PP_CALLER", {id="PP_CALLER",name="PP_CALLER",type="NORMAL",
      power=0,accuracy=100,pp=10,effect="PP_CALL_EFFECT"}))
    mod.exports.api=mod
  end]=]
  local f =
    dofile(root .. "/tests/enemy_actions/choice_band.lua").fixture(root, backend, version, { entry = entry })
  local caller, registries, previousRegistryData
  if native then
    caller = assert(require("src.mods.Gen3Compat").moveId("PP_CALLER"))
    local moves = require("src.core.game3.battle.moves")
    moves._rom[caller] = assert(f.data.gen3Moves._rom[caller])
    moves.BY_NUM[caller], moves._numByName.PP_CALLER = "PP_CALLER", caller
    registries = require("src.core.game3.battle.mod_registries")
    previousRegistryData = registries.data()
    registries.bind(f.data)
  else
    caller = -1
  end
  local ids = {
    [33] = f.ids.TACKLE,
    [10] = f.ids.SCRATCH,
    [19] = f.ids.FLY,
    [214] = f.ids.SLEEP_TALK,
    [165] = f.ids.STRUGGLE,
  }
  ids[caller] = "PP_CALLER"
  for _, row in ipairs({
    { 57, "SURF", 0, "NO_ADDITIONAL_EFFECT", 11, "WATER", 8 },
    { 76, "SOLARBEAM", 151, "SOLARBEAM_EFFECT", 12, "GRASS", 0 },
  }) do
    local number, name, effect, binding, kind, typeName, target = unpack(row)
    ids[number] = ("MOVE_%03d"):format(number)
    if native then
      local def = {
        effect = effect,
        power = 40,
        type = kind,
        accuracy = 100,
        pp = 10,
        target = target,
        flags = 51,
        priority = 0,
        secondaryChance = 0,
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
        power = 40,
        type = typeName,
        accuracy = 100,
        pp = 10,
        target = target,
        flags = 51,
        secondaryChance = 0,
      }
    end
  end
  local function setMoves(user, numbers, value)
    user.mon.moves = {}
    if native then
      user.mon.pp, user.mon.maxPp = {}, {}
    end
    for i, number in ipairs(numbers) do
      if native then
        user.mon.moves[i], user.mon.pp[i], user.mon.maxPp[i] = number, value or 10, 10
      else
        user.mon.moves[i] = { id = ids[number], pp = value or 10 }
      end
    end
    if not native then
      user.curMoves = user.mon.moves
    end
  end
  local function pp(user)
    local out = {}
    for i = 1, 4 do
      local value
      if native then
        value = user.mon.pp[i]
      else
        value = user.curMoves[i] and user.curMoves[i].pp
      end
      out[i] = value == nil and "absent" or value
    end
    return out
  end
  local function setPP(user, slot, value)
    if native then
      user.mon.pp[slot] = value
    else
      user.curMoves[slot].pp = value
    end
  end
  local function eventPP(event)
    local out = {}
    for i = 1, 4 do
      local row = event.user.mon.moves[i]
      f.T.check(row == nil or type(row) == "table", "public API-3 moves expose PP records")
      local value
      if row then
        value = row.pp
      end
      out[i] = value == nil and "absent" or value
    end
    return out
  end
  local function pressure(target, enabled)
    if native then
      target.ability, target.mon.ability = enabled and 46 or 0, enabled and 46 or 0
    else
      target.abilityOverride = enabled and "PRESSURE" or false
    end
  end
  local rows = {}
  for _, double in ipairs({ false, true }) do
    for actor = 0, double and 3 or 1 do
      for _, kind in ipairs({
        "ordinary",
        "pressure",
        "one_pp_pressure",
        "zero_pp",
        "refill_zero",
        "callback_zero",
        "callback_set",
        "callback_replace",
        "callback_remove",
        "callback_pressure_on",
        "callback_pressure_off",
        "planned_replace",
        "planned_removed",
        "sleep_talk",
        "awake_sleep_talk",
        "sleeping_block",
        "charge_start",
        "charge_release",
        "charge_planned_release",
        "charge_planned_release_zero",
        "charge_bypass",
        "charge_hook_set",
        "charge_hook_remove",
        "charge_refill_zero",
        "sun_skip",
        "spread",
        "spread_pressure",
        "spread_callback_set",
        "spread_zero",
        "spread_refill_zero",
        "spread_callback_remove",
        "spread_one_pressure",
        "authored_call",
        "struggle_zero",
      }) do
        local b = f.field(double)
        local user, targetId = f.at(b, actor), actor % 2 == 0 and actor + 1 or actor - 1
        local target = f.at(b, targetId)
        local move = kind == "authored_call" and caller
          or kind == "struggle_zero" and 165
          or kind:match("^charge") and 19
          or kind == "sun_skip" and 76
          or kind:match("^spread") and 57
          or kind:find("sleep_talk", 1, true) and 214
          or 33
        setMoves(user, { move, move == 214 and 33 or 10, 165 }, 10)
        if
          kind == "zero_pp"
          or kind == "refill_zero"
          or kind == "charge_refill_zero"
          or kind == "spread_zero"
          or kind == "spread_refill_zero"
          or kind == "struggle_zero"
        then
          setPP(user, 1, 0)
        end
        if
          kind == "one_pp_pressure"
          or kind == "spread_one_pressure"
          or kind == "charge_planned_release_zero"
        then
          setPP(user, 1, 1)
        end
        if kind == "pressure" or kind == "one_pp_pressure" or kind == "callback_pressure_off" then
          pressure(target, true)
        end
        if kind == "spread_pressure" or kind == "spread_one_pressure" then
          for id = 0, double and 3 or 1 do
            if id % 2 ~= actor % 2 then
              pressure(f.at(b, id), true)
            end
          end
        end
        if kind == "sleep_talk" or kind == "sleeping_block" then
          user.mon.status, user.sleepTurns = "SLP", 4
        end
        if kind == "sun_skip" then
          if native then
            b.weather = "SUN"
          else
            b.field.weather = "SUN"
          end
        end
        local planned = kind == "planned_replace" or kind == "planned_removed"
        if planned then
          user.choicedMove = 10
          f.hold(user, 186)
        end
        local action, number, slot = nil, move, 1
        if native then
          local plan = require("src.core.game3.battle.engine").planTurnActions(
            b,
            require("src.core.game3.battle.adapter").new(b),
            { [actor] = { kind = "move", move = move, slot = 1, target = targetId } }
          )[1]
          number, slot = plan.move, plan.slot
        else
          action =
            require("src.battle.EnemyMoveChoice").withMove(user.curMoves[1], ids[move], user.curMoves[1], 1)
          action.kind, action.target = "move", targetId
          action.targetType = f.data.moves[ids[move]].target or 0
          action = require("src.battle.Gen3ChoiceBand").plan(b, user, action)
        end
        local retired = native and user.mon.pp or user.curMoves
        if planned then
          setMoves(user, kind == "planned_removed" and { 33 } or { 33, 10 }, 7)
        end
        local function execute()
          if native then
            require("src.core.game3.battle.engine").resolveMove(
              actor,
              targetId,
              number,
              slot,
              require("src.core.game3.battle.adapter").new(b),
              b,
              {}
            )
          else
            b:executeAction(user, target, action)
          end
        end
        local plannedRelease = kind == "charge_planned_release" or kind == "charge_planned_release_zero"
        if kind == "charge_release" or plannedRelease then
          execute()
          if not native then
            action = user.charging
            if plannedRelease then
              action = require("src.battle.Gen3ChoiceBand").plan(b, user, action)
            end
          elseif plannedRelease then
            local plan = require("src.core.game3.battle.engine").planTurnActions(
              b,
              require("src.core.game3.battle.adapter").new(b),
              { [actor] = { kind = "move", move = number, slot = slot, target = targetId } }
            )[1]
            number, slot = plan.move, plan.slot
          end
          b.queue, b.current = {}, nil
        end
        local events, eventsAfter, chargeCalls, draws = {}, {}, {}, {}
        local offCrit = f.e.api.hooks:wrap("battle.crit", function()
          return false
        end)
        local offCharge = f.e.api.hooks:wrap("battle.charge_required", function(nextRead, ctx)
          chargeCalls[#chargeCalls + 1] =
            { pp = pp(user), called = ctx.isCalled or false, charge = ctx.charge }
          if kind == "charge_hook_set" then
            setPP(user, 1, 4)
          end
          if kind == "charge_hook_remove" then
            setMoves(user, {})
          end
          if kind == "charge_refill_zero" then
            setPP(user, 1, 9)
          end
          if kind == "charge_bypass" then
            return false
          end
          return nextRead(ctx)
        end)
        local off = f.e.api.events:on("battle.move_used", function(e)
          events[#events + 1] = {
            pp = pp(user),
            publicPP = eventPP(e),
            user = e.user.mon.nickname,
            target = e.target.mon.nickname,
            move = e.move.id,
            called = e.isCalled or false,
          }
          if #events == 1 then
            if kind == "refill_zero" or kind == "spread_refill_zero" then
              setPP(user, 1, 9)
            end
            if kind == "callback_zero" then
              setPP(user, 1, 0)
            end
            if kind == "callback_set" or kind == "spread_callback_set" then
              setPP(user, 1, 4)
            end
            if kind == "callback_replace" then
              setMoves(user, { 33, 10 }, 7)
            end
            if kind == "callback_remove" or kind == "spread_callback_remove" then
              setMoves(user, {})
            end
            if kind == "callback_pressure_on" then
              pressure(target, true)
            end
            if kind == "callback_pressure_off" then
              pressure(target, false)
            end
          end
        end)
        local offAfter = f.e.api.events:on("battle.move_used", function(e)
          eventsAfter[#eventsAfter + 1] = { pp = pp(user), publicPP = eventPP(e), move = e.move.id }
        end)
        b.rng = function(lo, hi)
          draws[#draws + 1] = { lo, hi, hi }
          return hi
        end
        local before = pp(user)
        execute()
        off()
        offAfter()
        offCharge()
        offCrit()
        local state = {}
        for id = 0, double and 3 or 1 do
          local a = f.at(b, id)
          local charging, hidden
          if native then
            charging, hidden = a.twoTurnMove ~= nil, a.semiInvulnerable ~= nil
          else
            charging, hidden = a.charging ~= nil, a.invulnerable == true
          end
          state[#state + 1] = { pp = pp(a), hp = a.mon.hp, charging = charging, hidden = hidden }
        end
        local oldPP = {}
        for i = 1, 4 do
          local value
          if native then
            value = retired[i]
          else
            value = retired[i] and retired[i].pp
          end
          oldPP[i] = value == nil and "absent" or value
        end
        f.T.eq(#f.result.errors, 0, "actual move-used and charge callbacks stay error-free")
        rows[#rows + 1] = {
          case = kind,
          double = double,
          actor = actor,
          before = before,
          events = events,
          eventsAfter = eventsAfter,
          chargeCalls = chargeCalls,
          draws = draws,
          state = state,
          retiredPP = oldPP,
        }
      end
    end
  end
  if registries then
    registries.bind(previousRegistryData)
  end
  f.close()
  return rows
end
return M
