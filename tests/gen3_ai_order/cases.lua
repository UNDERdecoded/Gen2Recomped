-- Actual VM programs; the checker additionally evaluates the original C function.
local C = {}
function C.run(root, version)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local AI = require("src.battle.Gen3AI")
  local O = require("src.battle.Gen3AIOrder")
  local Core = require("src.battle.Gen3OrderCore")
  local copy = require("src.mods.Merge").deepCopy
  local raw, defs = {}, {}
  local rows = {}
  local function at(values, id, default)
    return values and values[id + 1] ~= nil and values[id + 1] or default
  end
  for _, spec in ipairs(dofile(root .. "/tests/gen3_ai_order/scenarios.lua")) do
    for k in pairs(raw) do
      raw[k] = nil
    end
    for k in pairs(defs) do
      defs[k] = nil
    end
    local flags = spec.mode == "link" and 1
      or spec.mode == "recorded" and 2
      or spec.mode == "frontier" and 4
      or 0
    local b = {
      battlers = {},
      double = spec.double == true,
      badges = { [3] = spec.badge == true },
      kinds = { frontier = flags == 4, recordedLink = flags == 2 },
      link = flags == 1,
      weather = spec.weather or 0,
      randomTurnNumber = spec.word or 0,
      absent = {},
      data = { items = defs, constants = {}, moves = {} },
      trainer = { aiFlags = 1 },
    }
    local input = {
      spec.user or 1,
      spec.target or 0,
      b.double and 4 or 2,
      b.weather,
      flags,
      spec.badge and 1 or 0,
      b.randomTurnNumber,
      spec.tie or 0,
    }
    for id = 0, 3 do
      local speed, stage, ability =
        at(spec.speeds, id, 100), at(spec.stages, id, 0), at(spec.abilities, id, 0)
      local effect, parameter = at(spec.effects, id, 0), at(spec.parameters, id, 0)
      local item = spec.enigma and 175 or effect ~= 0 and (180 + id) or 0
      raw[item] = {
        name = "ORDER ITEM",
        pocket = "ITEMS",
        holdEffect = spec.enigma and 0 or effect,
        holdEffectParam = spec.enigma and 0 or parameter,
      }
      defs["ITEM_" .. item] = {
        index = item,
        gen3HoldEffect = raw[item].holdEffect,
        holdEffect = Core.effectNames[raw[item].holdEffect],
        holdEffectParam = raw[item].holdEffectParam,
      }
      local status = at(spec.statuses, id, 0)
      local statusWord = type(status) == "number" and status
        or (status == "PAR" or status == "PARALYSIS") and 64
        or 0
      local hp, priority = at(spec.hps, id, 100), at(spec.priorities, id, 0)
      local berry = { holdEffect = effect, holdEffectParam = parameter }
      local actor = {
        id = id,
        position = id,
        isPlayer = id % 2 == 0,
        side = id % 2 == 0 and "player" or "enemy",
        ability = ability,
        abilityOverride = ability,
        status = status,
        item = item,
        items = defs,
        stages = { speed = stage },
        curStats = { speed = speed },
        enigmaBerry = spec.enigma and berry or nil,
        mon = {
          speed = speed,
          stats = { speed = speed },
          hp = hp,
          moves = { 33 + id },
          pp = { 10 },
          status = status,
          item = "ITEM_" .. item,
        },
      }
      b.battlers[id] = actor
      b.data.moves["TEST_" .. id] = { index = 33 + id, power = 35, priority = priority }
      for _, value in ipairs({
        speed,
        stage + 6,
        ability,
        statusWord,
        item,
        raw[item].holdEffect,
        raw[item].holdEffectParam,
        spec.enigma and effect or 0,
        spec.enigma and parameter or 0,
        hp,
        priority,
      }) do
        input[#input + 1] = value
      end
    end
    b.player, b.enemy = b.battlers[0], b.battlers[1]
    local user, target = b.battlers[spec.user or 1], b.battlers[spec.target or 0]
    local observations = {}
    for _, wanted in ipairs({ 0, 1, 2, 3, 255 }) do
      for _, inverse in ipairs({ false, true }) do
        local draws = {}
        b.rng = function(lo, hi)
          draws[#draws + 1] = { lo, hi }
          return spec.tie or 0
        end
        local before = copy(b.battlers)
        local score
        local p = {
          entries = { [0] = 1 },
          code = {
            { name = inverse and "if_user_doesnt_go" or "if_user_goes", args = { wanted, 3 }, next = 2 },
            { name = "end", args = {} },
            { name = "score", args = { 5 }, next = 4 },
            { name = "end", args = {} },
          },
        }
        b.data.constants.gen3BattleAI = p
        T.eq(AI.runs(p, 1), true, "native order predicate is reachable")
        local scores = AI.scoreMoves(b, user, target, { { id = "TEST_" .. user.id, pp = 10 } })
        score = scores and scores[1] or false
        if spec.expected ~= nil then
          T.eq(
            score,
            ((spec.expected == wanted) ~= inverse) and 105 or 100,
            spec.name .. " literal native result"
          )
        end
        T.same(b.battlers, before, spec.name .. " preserves native actor state")
        T.check(#draws <= 1, "query never draws a new Quick Claw word")
        for _, draw in ipairs(draws) do
          T.same(draw, { 0, 65535 }, "native tie RNG ABI")
        end
        observations[#observations + 1] = { wanted = wanted, inverse = inverse, score = score, draws = draws }
      end
    end
    local a, z = O.speed(user, b), O.speed(target, b)
    local TurnOrder = require("src.battle.TurnOrder")
    local actualDraws = {}
    local function actualRng(lo, hi)
      actualDraws[#actualDraws + 1] = { lo, hi }
      return (spec.tie or 0) % 2
    end
    local first = TurnOrder.firstMover(
      user,
      b.data.moves["TEST_" .. user.id],
      target,
      b.data.moves["TEST_" .. target.id],
      actualRng,
      false,
      b
    )
    local entries = {}
    for id = 0, b.double and 3 or 1 do
      entries[#entries + 1] = { battler = b.battlers[id], move = b.data.moves["TEST_" .. id] }
    end
    local sortDraws = {}
    TurnOrder.order(entries, function(lo, hi)
      sortDraws[#sortDraws + 1] = { lo, hi }
      return (spec.tie or 0) % 2
    end, b)
    local order = {}
    for _, entry in ipairs(entries) do
      order[#order + 1] = entry.battler.id
    end
    rows[#rows + 1] = {
      name = spec.name,
      native = input,
      speeds = { a, z },
      observations = observations,
      actual = { first = first, draws = actualDraws, order = order, sortDraws = sortDraws },
    }
  end
  return rows
end
return C
