-- Owned party/move definitions drive the actual native Assist dispatch.
local M = {}
local BLOCKED =
  { 118, 165, 166, 102, 68, 243, 182, 197, 203, 194, 214, 168, 266, 289, 270, 343, 271, 264, 119, 274 }
local NAMES = {
  [118] = "METRONOME",
  [165] = "STRUGGLE",
  [166] = "SKETCH",
  [102] = "MIMIC",
  [68] = "COUNTER",
  [243] = "MIRROR_COAT",
  [182] = "PROTECT",
  [197] = "DETECT",
  [203] = "ENDURE",
  [194] = "DESTINY_BOND",
  [214] = "SLEEP_TALK",
  [168] = "THIEF",
  [266] = "FOLLOW_ME",
  [289] = "SNATCH",
  [270] = "HELPING_HAND",
  [343] = "COVET",
  [271] = "TRICK",
  [264] = "FOCUS_PUNCH",
  [119] = "MIRROR_MOVE",
  [274] = "ASSIST",
}
function M.fixture(root, backend, version, options)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/nature_power.lua").fixture(root, backend, version, options)
  local function mount(n, name, effect, binding, power, target)
    if native then
      local def = {
        effect = effect,
        power = power,
        type = 0,
        accuracy = 100,
        pp = 10,
        target = target,
        flags = n == 274 and 0 or 51,
        secondaryChance = 0,
        priority = 0,
      }
      local moves = require("src.core.game3.battle.moves")
      moves._rom[n], moves.BY_NUM[n], moves._numByName[name] = def, name, n
      f.data.gen3Moves._rom[n], f.data.gen3Pokemon._moveNames[n] = def, name
    else
      local id = ("MOVE_%03d"):format(n)
      f.data.moves[id] = {
        id = id,
        index = n,
        name = name,
        gen3Effect = effect,
        effect = binding,
        power = power,
        type = "NORMAL",
        accuracy = 100,
        pp = 10,
        target = target,
        flags = n == 274 and 0 or 51,
        secondaryChance = 0,
      }
    end
  end
  mount(274, "ASSIST", 180, "ASSIST_EFFECT", 0, 1)
  mount(10, "SCRATCH", 0, "NO_ADDITIONAL_EFFECT", 35, 0)
  for _, n in ipairs(BLOCKED) do
    if n ~= 274 and n ~= 214 then
      mount(
        n,
        NAMES[n],
        n == 118 and 83 or n == 119 and 9 or 0,
        n == 118 and "METRONOME_EFFECT" or n == 119 and "MIRROR_MOVE_EFFECT" or "NO_ADDITIONAL_EFFECT",
        0,
        0
      )
    end
  end
  local field = f.field
  f.field = function(double)
    local b = field(double)
    local player, enemy = { f.actor(0).mon }, { f.actor(1).mon }
    if double then
      player[2], enemy[2] = f.actor(2).mon, f.actor(3).mon
    end
    b.enemyPartyB = nil
    b.playerParty = player
    if native then
      b.foeParty = enemy
      for id = 0, double and 3 or 1 do
        f.actor(id).partyIndex = id < 2 and 1 or 2
      end
    else
      b.enemyParty = enemy
    end
    return b
  end
  f.setMoves = function(mon, numbers, pp)
    if native then
      mon.moves, mon.pp, mon.maxPp = {}, {}, {}
      for slot, n in pairs(numbers) do
        mon.moves[slot], mon.pp[slot], mon.maxPp[slot] = n, pp or 10, 10
      end
    else
      mon.moves = {}
      for slot, n in pairs(numbers) do
        mon.moves[slot] =
          { id = type(n) == "number" and (n == 0 and 0 or ("MOVE_%03d"):format(n)) or n, pp = pp or 10 }
      end
    end
  end
  f.party = function(b, user)
    if native then
      return user.side == "player" and b.playerParty or b.foeParty
    end
    if user.isPlayer then
      b.playerParty = b.playerParty or b.game.save.party
      return b.playerParty
    end
    b.enemyParty = b.enemyParty or { user.mon }
    return b.enemyParty
  end
  return f
end
local function cases()
  local out = {
    { name = "empty" },
    { name = "own-only", own = true },
    { name = "alive", moves = { 33 } },
    { name = "fainted", moves = { 33 }, hp = 0 },
    { name = "egg", moves = { 33 }, egg = true },
    { name = "zero-species", moves = { 33 }, species = 0 },
    { name = "missing-species", moves = { 33 }, missing = true },
    { name = "zero-pp", moves = { 33 }, pp = 0 },
    { name = "duplicate-slots", moves = { 33, 10, 33, 89 } },
    { name = "sparse-slots", moves = { [4] = 33 } },
    { name = "fifth-slot", moves = { [5] = 33 } },
    { name = "duplicates-members", moves = { 33, 10, 33 }, extra = { 33, 89 } },
    { name = "native-caller", moves = { 267 } },
    { name = "active-partner", partner = true },
    { name = "split-owner", moves = { 33 }, extra = { 10 }, split = true },
    { name = "split-partner", partner = true, extra = { 89 }, split = true },
  }
  for _, n in ipairs(BLOCKED) do
    out[#out + 1] = { name = "blocked-" .. n, moves = { n } }
    out[#out + 1] = { name = "filtered-" .. n, moves = { n, 33, n, 10 } }
  end
  return out
end
function M.run(root, backend, version, options)
  local native = backend == "gen1"
  options = options or {}
  local f = M.fixture(root, backend, version, options)
  local caller = native and 274 or "MOVE_274"
  local custom
  if options.public then
    if native then
      local g, m = require("src.mods.Gen3Compat"), require("src.core.game3.battle.moves")
      caller, custom = assert(g.moveId("PORTABLE_ASSIST")), assert(g.moveId("PORTABLE_STRIKE"))
      for _, name in ipairs({ "PORTABLE_ASSIST", "PORTABLE_STRIKE" }) do
        local n = assert(g.moveId(name))
        m._rom[n] = assert(f.data.gen3Moves._rom[n])
        m.BY_NUM[n], m._numByName[name] = name, n
      end
    else
      caller, custom = "PORTABLE_ASSIST", "PORTABLE_STRIKE"
    end
  end
  local function history(value)
    if not options.public or value == nil then
      return value
    end
    if native then
      return require("src.mods.Gen3Compat").moveName(value)
    end
    local def = f.data.moves[value]
    if def then
      return def.name
    end
    for _, row in pairs(f.data.moves) do
      if type(row) == "table" and row.index == value then
        return row.name
      end
    end
    return value
  end
  local rows = {}
  for _, double in ipairs({ false, true }) do
    for actor = 0, double and 3 or 1 do
      for _, case in
        ipairs((function()
          local list = cases()
          if options.held then
            while #list > 16 do
              table.remove(list)
            end
          end
          if options.public then
            list[#list + 1] = { name = "custom-bench", moves = { custom } }
          end
          return list
        end)())
      do
        for _, kind in ipairs({ "ordinary", "pressure", "zero-caller-pp", "parent-bench-change" }) do
          for _, pick in ipairs({ 1, 2, 3, 4, 5 }) do
            local b = f.field(double)
            b.terrain = 8
            if options.item then
              f.put(f.actor(actor), options.item)
            end
            for id = 0, double and 3 or 1 do
              local a = f.actor(id)
              f.setMoves(a.mon, { 274 })
              if not native then
                a.curMoves = a.mon.moves
              end
            end
            local user, targetId = f.actor(actor), actor % 2 == 0 and actor + 1 or actor - 1
            local target = f.actor(targetId)
            local party = f.party(b, user)
            local ownIndex
            for i, mon in ipairs(party) do
              if mon == user.mon then
                ownIndex = i
              end
            end
            assert(ownIndex, "party fixture preserves the actual active owner")
            if native then
              user.partyIndex = ownIndex
            end
            f.setMoves(
              user.mon,
              case.own and { caller, 33 } or { caller },
              kind == "zero-caller-pp" and 0 or 10
            )
            if not native then
              user.curMoves = user.mon.moves
            end
            local function bench(numbers)
              local mon = require("src.mods.Merge").deepCopy(user.mon)
              mon.nickname = "BENCH" .. (#party + 1)
              mon.hp = case.hp or 400
              mon.isEgg = case.egg or nil
              if case.missing then
                mon.species = nil
              elseif case.species ~= nil then
                mon.species = case.species
              end
              f.setMoves(mon, numbers, case.pp or 10)
              party[#party + 1] = mon
              return mon
            end
            if case.moves then
              bench(case.moves)
            end
            if case.extra then
              bench(case.extra)
            end
            if case.partner then
              if double then
                local ally = f.actor(actor < 2 and actor + 2 or actor - 2)
                f.setMoves(ally.mon, { 33 })
                if not native then
                  ally.curMoves = ally.mon.moves
                end
              else
                bench({ 33 })
              end
            end
            if case.split and not native and not user.isPlayer then
              b.enemyParty, b.enemyPartyB = { party[1] }, {}
              for i = 2, #party do
                b.enemyPartyB[#b.enemyPartyB + 1] = party[i]
              end
            end
            if kind == "pressure" then
              for id = 0, double and 3 or 1 do
                local a = f.actor(id)
                if a ~= user then
                  if native then
                    a.ability = "PRESSURE"
                  else
                    a.abilityOverride = "PRESSURE"
                  end
                end
              end
            end
            local trace, events, damage, draws = {}, {}, {}, {}
            local offHeld = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, c)
              trace[#trace + 1] = {
                holder = c.mon.nickname,
                item = c.item,
                definition = c.def and c.def.id,
                effect = c.effect,
                parameter = c.parameter,
                trigger = c.trigger,
                actualBattle = c.battle == b,
              }
              return nextRead(c)
            end)
            local offCrit = f.e.api.hooks:wrap("battle.crit", function()
              return false
            end)
            local function pp()
              if native then
                return user.mon.pp[1]
              end
              return user.curMoves[1].pp
            end
            local offMove = f.e.api.events:on("battle.move_used", function(e)
              events[#events + 1] = {
                move = e.move.id,
                called = e.isCalled or false,
                target = e.target.mon.nickname,
                user = e.user.mon.nickname,
                pp = pp(),
                publicPP = e.user.mon.moves[1].pp,
              }
              if not e.isCalled and kind == "parent-bench-change" then
                if #party == ownIndex then
                  bench({ 10 })
                else
                  f.setMoves(party[#party], { 10 })
                end
              end
            end)
            local offDamage = f.e.api.events:on("battle.damage_dealt", function(e)
              damage[#damage + 1] = {
                move = e.move.id,
                user = e.user.mon.nickname,
                target = e.target.mon.nickname,
                damage = e.damage,
                critical = e.crit or false,
                substitute = e.substitute or false,
                typeMult = e.typeMult,
              }
            end)
            local selector = 0
            local picked = false
            b.rng = function(lo, hi)
              local value = lo == 1 and hi == 100 and 1 or hi
              if lo == 1 and hi <= 24 and not picked then
                value = math.min(pick, hi)
                picked = true
              elseif lo == 0 and hi == 3 then
                value = selector % 4
                selector = selector + 1
              end
              draws[#draws + 1] = { lo, hi, value, pp = pp() }
              return value
            end
            local adapter = native and require("src.core.game3.battle.adapter").new(b)
            if native then
              require("src.core.game3.battle.engine").resolveMove(actor, targetId, caller, 1, adapter, b, {})
            else
              b:executeAction(user, target, user.curMoves[1])
            end
            local animations = {}
            for _, event in ipairs(native and adapter:eventsSince(0) or b.queue) do
              if native and event.kind == "move" or not native and event.anim then
                local move = native and event.moveId
                  or f.data.moves[event.anim] and f.data.moves[event.anim].index
                  or event.anim
                animations[#animations + 1] = {
                  move = history(move),
                  user = native and event.attackerId or event.attackerPosition,
                  target = native and event.targetId or event.targetPosition,
                  turn = native and event.turn or event.animContext and event.animContext.moveTurn or 0,
                }
              end
            end
            offHeld()
            offCrit()
            offMove()
            offDamage()
            local state = {}
            for id = 0, double and 3 or 1 do
              local a = f.actor(id)
              local last = native and a.lastMoveId or a.lastMove
              if not native and last then
                last = f.data.moves[last] and f.data.moves[last].index or last
              end
              state[#state + 1] = {
                hp = a.mon.hp,
                status = a.mon.status,
                last = history(last),
                choice = history(a.choicedMove),
                flinched = a.flinched or false,
              }
            end
            local partyState = {}
            for _, mon in ipairs(party) do
              local pps = {}
              for slot = 1, 5 do
                local value
                if native then
                  value = mon.pp[slot]
                else
                  value = mon.moves[slot] and mon.moves[slot].pp
                end
                pps[slot] = value == nil and "absent" or value
              end
              partyState[#partyState + 1] =
                { name = mon.nickname, hp = mon.hp, egg = mon.isEgg or false, pp = pps }
            end
            f.T.eq(#f.result.errors, 0, "Assist public callbacks stay error-free")
            rows[#rows + 1] = {
              double = double,
              actor = actor,
              case = case.name,
              kind = kind,
              pick = pick,
              item = options.item,
              events = events,
              trace = trace,
              draws = draws,
              damage = damage,
              animations = animations,
              state = state,
              party = partyState,
            }
          end
        end
      end
    end
  end
  f.close()
  return rows
end
function M.content(root, backend, version)
  return M.run(root, backend, version, {
    public = true,
    entry = [=[return function(mod)
  assert(mod.content.moves:register("PORTABLE_ASSIST",{id="PORTABLE_ASSIST",name="PORTABLE_ASSIST",type="NORMAL",power=0,accuracy=100,pp=10,effect="ASSIST"}))
  assert(mod.content.moves:register("PORTABLE_STRIKE",{id="PORTABLE_STRIKE",name="PORTABLE_STRIKE",type="NORMAL",power=35,accuracy=100,pp=10,effect="NO_ADDITIONAL_EFFECT"}))
  local record=assert(mod.content.moves:get("PORTABLE_ASSIST"));assert(record.effect=="ASSIST")
  mod.exports.api=mod
 end]=],
  })
end
function M.held(root, backend, version)
  local rows = {}
  for _, item in ipairs({ 186, 187, 219 }) do
    for _, row in ipairs(M.run(root, backend, version, { held = true, item = item })) do
      rows[#rows + 1] = row
    end
  end
  return rows
end
-- A native caller that returns before move-end must retain the old history,
-- including when a real outer Metronome dispatch selected that failed caller.
function M.failedCallers(root, backend, version)
  local native = backend == "gen1"
  local f = M.fixture(root, backend, version)
  local rows = {}
  for _, double in ipairs({ false, true }) do
    for actor = 0, double and 3 or 1 do
      for _, previous in ipairs({ 0, 33, 10 }) do
        for _, child in ipairs({ 274, 119 }) do
          local b = f.field(double)
          local user, targetId = f.actor(actor), actor % 2 == 0 and actor + 1 or actor - 1
          local target = f.actor(targetId)
          for id = 0, double and 3 or 1 do
            f.setMoves(f.actor(id).mon, { 274 })
          end
          f.setMoves(user.mon, { 118 })
          if native then
            user.lastMoveId, user.lastMove =
              previous ~= 0 and previous or nil, previous ~= 0 and previous or nil
            b.moveMax, b.moveExcluded = child, {}
            for n = 1, child do
              if n ~= child then
                b.moveExcluded[n] = true
              end
            end
          else
            user.curMoves = user.mon.moves
            user.lastMove = previous ~= 0 and ("MOVE_%03d"):format(previous) or nil
            f.data.constants.moveOrder = { ("MOVE_%03d"):format(child) }
          end
          local events, trace, draws, damage = {}, {}, {}, {}
          local offMove = f.e.api.events:on("battle.move_used", function(e)
            events[#events + 1] = {
              move = e.move.id,
              called = e.isCalled or false,
              user = e.user.mon.nickname,
              target = e.target.mon.nickname,
              pp = e.user.mon.moves[1].pp,
            }
          end)
          local offHeld = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, c)
            trace[#trace + 1] = {
              trigger = c.trigger,
              holder = c.mon.nickname,
              item = c.item,
              effect = c.effect,
              parameter = c.parameter,
            }
            return nextRead(c)
          end)
          local offDamage = f.e.api.events:on("battle.damage_dealt", function(e)
            damage[#damage + 1] = { move = e.move.id, damage = e.damage }
          end)
          b.rng = function(lo, hi)
            draws[#draws + 1] = { lo, hi, lo }
            return lo
          end
          if native then
            require("src.core.game3.battle.engine").resolveMove(
              actor,
              targetId,
              118,
              1,
              require("src.core.game3.battle.adapter").new(b),
              b,
              {}
            )
          else
            b:executeAction(user, target, user.curMoves[1])
          end
          offMove()
          offHeld()
          offDamage()
          local last = native and user.lastMoveId or user.lastMove
          if not native then
            last = last and f.data.moves[last].index
          end
          rows[#rows + 1] = {
            double = double,
            actor = actor,
            previous = previous,
            child = child,
            last = last or 0,
            pp = native and user.mon.pp[1] or user.curMoves[1].pp,
            events = events,
            trace = trace,
            draws = draws,
            damage = damage,
          }
          f.T.eq(#f.result.errors, 0, "failed native caller callbacks have no errors")
        end
      end
    end
  end
  f.close()
  return rows
end
return M
