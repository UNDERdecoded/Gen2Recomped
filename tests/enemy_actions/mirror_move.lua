-- Owned command sequences exercise unchanged native received-move history.
local M = {}
function M.run(root, backend, version, options)
  options = options or {}
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version, options)
  local rows = {}
  local caller, custom = native and 119 or "MOVE_119", nil
  if options.public then
    if native then
      local compat, moves = require("src.mods.Gen3Compat"), require("src.core.game3.battle.moves")
      caller, custom = assert(compat.moveId("PORTABLE_MIRROR")), assert(compat.moveId("PORTABLE_STRIKE"))
      for _, name in ipairs({ "PORTABLE_MIRROR", "PORTABLE_STRIKE" }) do
        local n = assert(compat.moveId(name))
        moves._rom[n] = assert(f.data.gen3Moves._rom[n])
        moves.BY_NUM[n], moves._numByName[name] = name, n
      end
    else
      caller, custom = "PORTABLE_MIRROR", "PORTABLE_STRIKE"
    end
  end
  local selected = options.outer and (native and 118 or "MOVE_118") or caller
  local function definition(n)
    return native and f.data.gen3Moves._rom[n] or f.data.moves[("MOVE_%03d"):format(n)]
  end
  definition(119).flags = 0
  if not native then
    definition(119).mirrorMoveAffected = false
  end
  local function number(value)
    if options.public and value ~= nil then
      if native then
        return require("src.mods.Gen3Compat").moveName(value)
      end
      local def = f.data.moves[value]
      if def then
        return def.name
      end
      for _, row in pairs(f.data.moves) do
        if row.index == value then
          return row.name
        end
      end
      return value
    end
    if native or value == nil then
      return value
    end
    local def = f.data.moves[value]
    return def and def.index or value
  end
  for _, double in ipairs({ false, true }) do
    for actor = 0, double and 3 or 1 do
      for _, kind in ipairs({
        "none",
        "hit",
        "unreflectable",
        "miss",
        "miss-first",
        "callback-change",
        "other-target",
        "protected",
        "substitute",
        "immune",
        "flag-change",
        "zero-pp",
        "pressure",
        "custom-incoming",
        "faint-target",
        "self-target",
      }) do
        if (kind ~= "other-target" or double) and (kind ~= "custom-incoming" or options.public) then
          for _, item in ipairs({ 0, 186, 187, 219 }) do
            local b = f.field(double)
            definition(33).flags = 51
            definition(118).flags = 0
            if not native then
              definition(33).mirrorMoveAffected = true
            end
            if options.outer then
              if native then
                b.moveMax, b.moveExcluded = caller, {}
                for n = 1, caller do
                  if n ~= caller then
                    b.moveExcluded[n] = true
                  end
                end
              else
                f.data.constants.moveOrder = { caller }
              end
            end
            local user = f.actor(actor)
            local foeId = actor % 2 == 0 and actor + 1 or actor - 1
            local foe = f.actor(foeId)
            for id = 0, double and 3 or 1 do
              local a = f.actor(id)
              f.setMoves(a.mon, { selected, kind == "custom-incoming" and custom or 33, 10 })
              if not native then
                a.curMoves = a.mon.moves
              end
            end
            f.put(user, item ~= 0 and item or nil)
            if kind == "pressure" then
              if native then
                foe.ability = "PRESSURE"
              else
                foe.abilityOverride = "PRESSURE"
              end
            elseif kind == "substitute" then
              user.substituteHP = 100
            end
            local scratch = definition(10)
            scratch.type = native and 0 or "NORMAL"
            scratch.flags, scratch.accuracy = kind == "unreflectable" and 35 or 51, 100
            if not native then
              scratch.mirrorMoveAffected = kind ~= "unreflectable"
            end
            local step = "setup"
            local trace, events, damage, draws, animations = {}, {}, {}, {}, {}
            local offHeld = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, c)
              trace[#trace + 1] = {
                step = step,
                holder = c.mon.nickname,
                item = c.item,
                effect = c.effect,
                parameter = c.parameter,
                definition = c.def and c.def.id,
                trigger = c.trigger,
                actualBattle = c.battle == b,
              }
              return nextRead(c)
            end)
            local offCrit = f.e.api.hooks:wrap("battle.crit", function()
              return false
            end)
            local offMove = f.e.api.events:on("battle.move_used", function(e)
              local pp = {}
              for i = 1, 3 do
                pp[i] = e.user.mon.moves[i].pp
              end
              events[#events + 1] = {
                step = step,
                move = e.move.id,
                called = e.isCalled or false,
                user = e.user.mon.nickname,
                target = e.target.mon.nickname,
                pp = pp,
              }
              if step == "copy" and not e.isCalled and kind == "flag-change" then
                local changed = definition(33)
                changed.flags = 35
                if not native then
                  changed.mirrorMoveAffected = false
                end
              end
              if step == "copy" and not e.isCalled and kind == "callback-change" then
                if native then
                  foe.lastMoveId, foe.lastMove = 10, 10
                else
                  foe.lastMove = "MOVE_010"
                end
              end
            end)
            local offDamage = f.e.api.events:on("battle.damage_dealt", function(e)
              damage[#damage + 1] = {
                step = step,
                move = e.move.id,
                user = e.user.mon.nickname,
                target = e.target.mon.nickname,
                damage = e.damage,
                critical = e.crit or false,
                substitute = e.substitute or false,
                typeMult = e.typeMult,
              }
            end)
            local targetRoll = 0
            b.rng = function(lo, hi)
              local value = lo == 1 and hi == 100 and (step == "miss" and 100 or 1) or hi
              if lo == 0 and hi == 3 then
                value = targetRoll % 4
                targetRoll = targetRoll + 1
              end
              draws[#draws + 1] = { step = step, lo = lo, hi = hi, value = value }
              return value
            end
            local function act(attackerId, targetId, slot, label)
              step = label
              local a, t = f.actor(attackerId), f.actor(targetId)
              local adapter = native and require("src.core.game3.battle.adapter").new(b)
              if native then
                require("src.core.game3.battle.engine").resolveMove(
                  attackerId,
                  targetId,
                  a.mon.moves[slot],
                  slot,
                  adapter,
                  b,
                  {}
                )
              else
                b:executeAction(a, t, a.curMoves[slot])
              end
              for _, e in ipairs(native and adapter:eventsSince(0) or b.queue) do
                if native and (e.kind == "move" or e.kind == "anim") or not native and e.anim then
                  local ref = native and (e.kind == "move" and e.moveId or e.name) or e.anim
                  local isMove = native and e.kind == "move" or not native and f.data.moves[e.anim] ~= nil
                  animations[#animations + 1] = {
                    step = step,
                    kind = isMove and "move" or "anim",
                    move = isMove and number(ref) or ref,
                    user = native and e.attackerId or e.attackerPosition,
                    target = native and e.targetId or e.targetPosition,
                    turn = native and e.turn or e.animContext and e.animContext.moveTurn or 0,
                  }
                end
              end
              if not native then
                b.queue, b.nextInsert = {}, 0
              end
            end
            if kind ~= "none" and kind ~= "miss-first" then
              act(foeId, actor, 2, "incoming")
            end
            if kind == "miss" or kind == "miss-first" then
              scratch.accuracy = 50
              act(foeId, actor, 3, "miss")
              scratch.accuracy = 100
            elseif kind == "unreflectable" then
              act(foeId, actor, 3, "unreflectable")
            elseif kind == "protected" then
              if native then
                user.expProtected = true
              else
                user.protecting = true
              end
              act(foeId, actor, 3, "protected")
              user.expProtected, user.protecting = nil, nil
            elseif kind == "immune" then
              if native then
                user.type1, user.type2 = 7, 7
              else
                user.curTypes = { "GHOST" }
                f.data.type_chart.matchups[#f.data.type_chart.matchups + 1] =
                  { attacker = "NORMAL", defender = "GHOST", multiplier = 0 }
                f.data.type_chart.types.GHOST = { id = "GHOST", index = 7, category = "physical" }
                require("src.battle.TypeChart").load(f.data)
              end
              act(foeId, actor, 3, "immune")
              if native then
                user.type1, user.type2 = 0, 0
              else
                user.curTypes = { "NORMAL" }
              end
            elseif kind == "other-target" then
              act(foeId, actor < 2 and actor + 2 or actor - 2, 3, "other-target")
            elseif kind == "faint-target" then
              -- A second received move KOs the recipient. Its earlier valid
              -- history must survive; a fainted Pokemon cannot then copy it.
              user.mon.hp = 1
              act(foeId, actor, 3, "faint-target")
            elseif kind == "self-target" then
              act(foeId, foeId, 3, "self-target")
            end
            if kind == "zero-pp" then
              if native then
                user.mon.pp[1] = 0
              else
                user.curMoves[1].pp = 0
              end
            end
            if kind ~= "faint-target" then
              act(actor, foeId, 1, "copy")
            end
            offHeld()
            offCrit()
            offMove()
            offDamage()
            local state = {}
            for id = 0, double and 3 or 1 do
              local a = f.actor(id)
              local pp = {}
              for i = 1, 3 do
                pp[i] = native and a.mon.pp[i] or a.curMoves[i].pp
              end
              state[#state + 1] = {
                hp = a.mon.hp,
                status = a.mon.status,
                last = number(native and a.lastMoveId or a.lastMove),
                received = number(native and a.expLastTakenMove or a.gbaLastTakenMove),
                substituteHP = a.substituteHP or 0,
                pp = pp,
                choice = number(a.choicedMove),
                flinched = a.flinched or false,
              }
            end
            f.T.eq(#f.result.errors, 0, "received-move callbacks stay error-free")
            rows[#rows + 1] = {
              double = double,
              actor = actor,
              case = kind,
              item = item,
              outer = options.outer or false,
              state = state,
              trace = trace,
              events = events,
              damage = damage,
              draws = draws,
              animations = animations,
            }
          end
        end
      end
    end
  end
  f.close()
  return rows
end
function M.content(root, backend, version, outer)
  return M.run(root, backend, version, {
    public = true,
    outer = outer,
    entry = [=[return function(mod)
  assert(mod.content.moves:register("PORTABLE_MIRROR",{id="PORTABLE_MIRROR",name="PORTABLE_MIRROR",type="NORMAL",power=0,accuracy=100,pp=10,effect="MIRROR_MOVE_EFFECT"}))
  assert(mod.content.moves:register("PORTABLE_STRIKE",{id="PORTABLE_STRIKE",name="PORTABLE_STRIKE",type="NORMAL",power=35,accuracy=100,pp=10,effect="NO_ADDITIONAL_EFFECT"}))
  assert(mod.content.moves:get("PORTABLE_MIRROR").effect=="MIRROR_MOVE_EFFECT")
  mod.exports.api=mod
 end]=],
  })
end
function M.chained(root, backend, version)
  return M.content(root, backend, version, true)
end
return M
