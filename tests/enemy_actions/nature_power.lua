-- Owned native-shaped definitions exercise the terrain caller independently
-- of cartridge assets. Both engines execute their unchanged native dispatcher.
local M = {}
local DEFS = {
  { 267, "NATURE_POWER", 173, "NATURE_POWER_EFFECT", 0, 1 },
  { 214, "SLEEP_TALK", 97, "SLEEP_TALK_EFFECT", 0, 1 },
  { 78, "STUN_SPORE", 67, "PARALYZE_EFFECT", 0, 0 },
  { 75, "RAZOR_LEAF", 0, "NO_ADDITIONAL_EFFECT", 35, 8 },
  { 89, "EARTHQUAKE", 0, "NO_ADDITIONAL_EFFECT", 35, 32 },
  { 56, "HYDRO_PUMP", 0, "NO_ADDITIONAL_EFFECT", 35, 0 },
  { 57, "SURF", 0, "NO_ADDITIONAL_EFFECT", 35, 8 },
  { 61, "BUBBLEBEAM", 0, "NO_ADDITIONAL_EFFECT", 35, 0 },
  { 157, "ROCK_SLIDE", 0, "NO_ADDITIONAL_EFFECT", 35, 8 },
  { 247, "SHADOW_BALL", 0, "NO_ADDITIONAL_EFFECT", 35, 0 },
  { 129, "SWIFT", 0, "NO_ADDITIONAL_EFFECT", 35, 8 },
}
function M.fixture(root, backend, version, options)
  local native = backend == "gen1"
  options = options or {}
  local f
  if options.entry then
    f = dofile(root .. "/tests/enemy_actions/choice_band.lua").fixture(
      root,
      backend,
      version,
      { entry = options.entry }
    )
    local field = f.field
    f.field = function(double)
      local b = field(double)
      f.actor = function(id)
        return f.at(b, id)
      end
      return b
    end
    f.put = f.hold
  else
    f = dofile(root .. "/tests/enemy_actions/post_hit_items.lua").fixture(root, backend, version)
  end
  f.game.save.options.ruleset = "gen3_emerald"
  for _, item in ipairs({
    { 187, "KINGS ROCK", 30, "FLINCH", 10 },
    { 219, "SHELL BELL", 62, "SHELL_BELL", 8 },
  }) do
    local n, name, effect, kind, parameter = unpack(item)
    if native then
      f.data.gen3Items._byId[n] =
        { name = name, pocket = "ITEMS", price = 100, holdEffect = effect, holdEffectParam = parameter }
    else
      local id = ("ITEM_%03d"):format(n)
      f.data.items[id] =
        { id = id, index = n, name = name, price = 100, holdEffect = kind, holdEffectParam = parameter }
    end
  end
  if native then
    f.data.gen3Items._byId[186] =
      { name = "CHOICE BAND", pocket = "ITEMS", price = 100, holdEffect = 29, holdEffectParam = 0 }
  else
    f.data.items.ITEM_186 = {
      id = "ITEM_186",
      index = 186,
      name = "CHOICE BAND",
      price = 100,
      holdEffect = "CHOICE_BAND",
      holdEffectParam = 0,
    }
  end
  for _, row in ipairs(DEFS) do
    local n, name, effect, binding, power, target = unpack(row)
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
        flags = 51,
        secondaryChance = 0,
      }
    end
  end
  return f
end
function M.run(root, backend, version, options)
  options = options or {}
  local native = backend == "gen1"
  local f = M.fixture(root, backend, version, options)
  local caller = native and 267 or "MOVE_267"
  if options.public then
    if native then
      caller = assert(require("src.mods.Gen3Compat").moveId("PORTABLE_NATURE"))
      local moves = require("src.core.game3.battle.moves")
      moves._rom[caller] = assert(f.data.gen3Moves._rom[caller])
      moves.BY_NUM[caller], moves._numByName.PORTABLE_NATURE = "PORTABLE_NATURE", caller
    else
      caller = "PORTABLE_NATURE"
    end
  end
  local second = native and 33 or "MOVE_033"
  if options.sleepCaller then
    second = caller
    caller = native and 214 or "MOVE_214"
  end
  local function history(value)
    if not options.public or value == nil then
      return value
    end
    if native then
      return require("src.mods.Gen3Compat").moveName(value)
    end
    local row = f.data.moves[value]
    if row then
      return row.name
    end
    for _, def in pairs(f.data.moves) do
      if type(def) == "table" and def.index == value then
        return def.name
      end
    end
    return value
  end
  local rows = {}
  for _, double in ipairs({ false, true }) do
    for actor = 0, double and 3 or 1 do
      for _, terrain in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 10, "4", "bad" }) do
        for _, kind in ipairs({
          "ordinary",
          "pressure",
          "zero_pp",
          "parent_zero",
          "parent_replace",
          "parent_remove",
          "parent_reorder",
          "child_zero",
          "child_refill",
        }) do
          for _, item in ipairs({ 0, 186, 187, 219 }) do
            local b = f.field(double)
            b.terrain = terrain
            local user, targetId = f.actor(actor), actor % 2 == 0 and actor + 1 or actor - 1
            local target = f.actor(targetId)
            user.mon.hp = 200
            if options.sleepCaller then
              user.mon.status, user.sleepTurns = "SLP", 4
            end
            f.put(user, item ~= 0 and item or nil)
            local original
            if native then
              user.mon.moves, user.mon.pp, user.mon.maxPp =
                { caller, second }, { kind == "zero_pp" and 0 or 10, 10 }, { 10, 10 }
              original = user.mon.pp
            else
              user.mon.moves =
                { { id = caller, pp = kind == "zero_pp" and 0 or 10 }, { id = second, pp = 10 } }
              user.curMoves = user.mon.moves
              original = user.curMoves[1]
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
            local trace, draws, events, damage = {}, {}, {}, {}
            local offHeld = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, c)
              trace[#trace + 1] = {
                holder = c.mon.nickname,
                item = c.item,
                definition = c.def and c.def.id,
                trigger = c.trigger,
                effect = c.effect,
                parameter = c.parameter,
                actualBattle = c.battle == b,
              }
              return nextRead(c)
            end)
            local offCrit = f.e.api.hooks:wrap("battle.crit", function()
              return false
            end)
            local function pp()
              local value
              if native then
                value = user.mon.pp[1]
              else
                value = user.curMoves[1] and user.curMoves[1].pp
              end
              return value == nil and "absent" or value
            end
            local function setPP(value)
              if native then
                user.mon.pp[1] = value
              else
                user.curMoves[1].pp = value
              end
            end
            local offMove = f.e.api.events:on("battle.move_used", function(e)
              events[#events + 1] = {
                user = e.user.mon.nickname,
                target = e.target.mon.nickname,
                move = e.move.id,
                called = e.isCalled or false,
                pp = pp(),
                publicPP = e.user.mon.moves[1] and e.user.mon.moves[1].pp or "absent",
              }
              if not e.isCalled then
                if kind == "parent_zero" then
                  setPP(0)
                end
                if kind == "parent_replace" then
                  if native then
                    user.mon.moves, user.mon.pp, user.mon.maxPp = { 33, caller }, { 3, 8 }, { 10, 10 }
                  else
                    user.mon.moves = { { id = "MOVE_033", pp = 3 }, { id = caller, pp = 8 } }
                    user.curMoves = user.mon.moves
                  end
                end
                if kind == "parent_remove" then
                  if native then
                    user.mon.moves, user.mon.pp, user.mon.maxPp = { [2] = 33 }, { [2] = 10 }, { [2] = 10 }
                  else
                    user.mon.moves = { [2] = { id = "MOVE_033", pp = 10 } }
                    user.curMoves = user.mon.moves
                  end
                elseif kind == "parent_reorder" then
                  if native then
                    user.mon.moves, user.mon.pp, user.mon.maxPp = { 33, caller }, { 4, 10 }, { 10, 10 }
                  else
                    user.mon.moves = { { id = "MOVE_033", pp = 4 }, { id = caller, pp = 10 } }
                    user.curMoves = user.mon.moves
                  end
                end
              elseif kind == "child_zero" then
                setPP(0)
              elseif kind == "child_refill" then
                setPP(7)
              end
            end)
            local observers = {}
            local offObserver = f.e.api.events:on("battle.move_used", function(e)
              observers[#observers + 1] = {
                move = e.move.id,
                called = e.isCalled or false,
                pp = pp(),
                publicPP = e.user.mon.moves[1] and e.user.mon.moves[1].pp or "absent",
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
            end)
            local selector = 0
            b.rng = function(lo, hi)
              local value = lo == 1 and hi == 100 and 1 or hi
              if lo == 0 and hi == 3 then
                value = selector % 4
                selector = selector + 1
              end
              draws[#draws + 1] = { lo, hi, value }
              return value
            end
            if native then
              require("src.core.game3.battle.engine").resolveMove(
                actor,
                targetId,
                caller,
                1,
                require("src.core.game3.battle.adapter").new(b),
                b,
                {}
              )
            else
              b:executeAction(user, target, user.curMoves[1])
            end
            offHeld()
            offCrit()
            offMove()
            offObserver()
            offDamage()
            local state = {}
            for id = 0, double and 3 or 1 do
              local a = f.actor(id)
              local pps = {}
              for i = 1, 4 do
                local v
                if native then
                  v = a.mon.pp[i]
                else
                  v = a.curMoves[i] and a.curMoves[i].pp
                end
                pps[i] = v == nil and "absent" or v
              end
              local last = native and a.lastMoveId or a.lastMove
              if not native and last then
                last = f.data.moves[last] and f.data.moves[last].index or last
              end
              local choice = a.choicedMove
              state[#state + 1] = {
                hp = a.mon.hp,
                pp = pps,
                status = a.mon.status,
                flinched = a.flinched or false,
                lastMove = history(last),
                choice = history(choice),
              }
            end
            local oldPP = native and original[1] or original.pp
            f.T.eq(#f.result.errors, 0, "Nature Power callbacks remain error-free")
            rows[#rows + 1] = {
              double = double,
              actor = actor,
              terrain = terrain,
              case = kind,
              item = item,
              events = events,
              observers = observers,
              damage = damage,
              trace = trace,
              draws = draws,
              state = state,
              retiredPP = oldPP,
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
    assert(mod.content.moves:register("PORTABLE_NATURE", {id="PORTABLE_NATURE",name="PORTABLE_NATURE",
      type="NORMAL",power=0,accuracy=100,pp=10,effect="NATURE_POWER"}))
    local move=assert(mod.content.moves:get("PORTABLE_NATURE"))
    assert(move.effect=="NATURE_POWER" and move.pp==10 and move.type=="NORMAL" and move.power==0)
    mod.exports.api=mod
  end]=],
  })
end
function M.chained(root, backend, version)
  return M.run(root, backend, version, { sleepCaller = true })
end
return M
