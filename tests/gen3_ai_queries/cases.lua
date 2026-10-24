-- Equivalent programs through both actual VMs with typed native session records.
local C = {}
function C.run(backend, version)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local source = backend == "gen1"
  local VM = source and require("src.core.game3.battle.ai_vm")
  local AI = not source and require("src.battle.Gen3AI")
  local hostState = not source and require("src.battle.BattleState")
  local typeNames = {
    "NORMAL",
    "FIGHTING",
    "FLYING",
    "POISON",
    "GROUND",
    "ROCK",
    "BUG",
    "GHOST",
    "STEEL",
    "CURSE_TYPE",
    "FIRE",
    "WATER",
    "GRASS",
    "ELECTRIC",
    "PSYCHIC_TYPE",
    "ICE",
    "DRAGON",
    "DARK",
  }
  local rawMoves = {
    [0] = { type = 0, power = 0, effect = 0 },
    [33] = { type = 0, power = 35, effect = 0 },
    [76] = { type = 12, power = 120, effect = 151 },
    [19] = { type = 2, power = 70, effect = 155 },
  }
  local defs = {}
  for number, move in pairs(rawMoves) do
    defs[("MOVE_%03d"):format(number)] = {
      index = number,
      type = typeNames[move.type + 1],
      power = move.power,
      gen3Effect = move.effect,
      name = number == 76 and "SOLARBEAM" or number == 19 and "FLY" or "TACKLE",
    }
  end
  local restores = {}
  local function patch(t, key, value)
    local old = t[key]
    t[key] = value
    restores[#restores + 1] = function()
      t[key] = old
    end
  end
  if source then
    local Moves = require("src.core.game3.battle.moves")
    local Pokemon = require("src.core.game3.pokemon")
    patch(Moves, "_rom", rawMoves)
    patch(Moves, "_romLoaded", true)
    patch(Moves, "_linkRows", nil)
    patch(Moves, "_numByName", { TACKLE = 33, SOLARBEAM = 76, FLY = 19 })
    patch(Moves, "BY_NUM", { [33] = "TACKLE", [76] = "SOLARBEAM", [19] = "FLY" })
    patch(Pokemon, "_moveNames", { [0] = "-", [33] = "TACKLE", [76] = "SOLARBEAM", [19] = "FLY" })
    patch(Pokemon, "_romMoveNames", Pokemon._moveNames)
    patch(Pokemon, "_battleMoves", rawMoves)
  end
  local specs = {}
  for _, field in ipairs({
    { "get_move_type_from_result", 12 },
    { "get_move_power_from_result", 120 },
    { "get_move_effect_from_result", 151 },
  }) do
    specs[#specs + 1] = {
      name = field[1] .. "-considered",
      query = field[1],
      considered = true,
      expected = { false, true },
      value = field[2],
    }
    for _, which in ipairs({ 0, 1, 2, 3 }) do
      specs[#specs + 1] = {
        name = field[1] .. "-last-" .. which,
        query = field[1],
        which = which,
        value = which == 1 and ({
          get_move_type_from_result = 2,
          get_move_power_from_result = 70,
          get_move_effect_from_result = 155,
        })[field[1]] or field[2],
        expected = { true, true },
      }
    end
    specs[#specs + 1] = {
      name = field[1] .. "-no-history",
      query = field[1],
      noHistory = true,
      value = 0,
      expected = { true, true },
    }
    specs[#specs + 1] =
      { name = field[1] .. "-missing-definition", query = field[1], last = 999, value = 0, error = true }
    specs[#specs + 1] =
      { name = field[1] .. "-unknown-name", query = field[1], last = "NO_SUCH_MOVE", value = 0, error = true }
  end
  for _, which in ipairs({ 0, 1, 2, 3 }) do
    for _, count in ipairs({ 0, 1, 2, 7 }) do
      specs[#specs + 1] = {
        name = "protect-" .. which .. "-" .. count,
        query = "get_protect_count",
        which = which,
        count = count,
        value = count,
        expected = { true, true },
      }
    end
    for _, single in ipairs({ false, true }) do
      for typ = 0, 17 do
        local present = not single or which < 2
        local roleTypes = { [0] = { 0, 10 }, [1] = { 11, 11 }, [2] = { 12, 14 }, [3] = { 8, 17 } }
        local has = present and (roleTypes[which][1] == typ or roleTypes[which][2] == typ)
        specs[#specs + 1] = {
          name = "type-" .. which .. "-" .. typ .. (single and "-single" or "-double"),
          query = "is_of_type",
          which = which,
          typ = typ,
          single = single,
          value = 1,
          expected = { has, has },
        }
      end
      for _, active in ipairs({ false, true }) do
        local taken = active and (not single or which < 2)
        specs[#specs + 1] = {
          name = "flash-" .. which .. (active and "-lit" or "-unlit") .. (single and "-single" or "-double"),
          query = "if_flash_fired",
          which = which,
          single = single,
          flash = active,
          expected = { taken, taken },
        }
      end
    end
  end
  for typ = 0, 17 do
    specs[#specs + 1] = {
      name = "metadata-type-" .. typ,
      query = "get_move_type_from_result",
      which = 1,
      moveType = typ,
      value = typ,
      expected = { true, true },
    }
  end
  for name, typ in pairs({
    FIGHT = 1,
    ELECTR = 13,
    PSYCHC = 14,
    PSYCHIC_TYPE = 14,
    CURSE_TYPE = 9,
    MYSTERY = 9,
    PSYCHIC = 14,
    FAIRY = 18,
  }) do
    specs[#specs + 1] = {
      name = "type-alias-" .. name,
      query = "is_of_type",
      which = 1,
      typ = typ,
      userType = typ,
      typeName = name,
      value = 1,
      expected = { true, true },
    }
  end
  specs[#specs + 1] = {
    name = "metadata-custom-type",
    query = "get_move_type_from_result",
    which = 1,
    moveType = 18,
    moveTypeName = "FAIRY",
    value = 18,
    expected = { true, true },
  }
  specs[#specs + 1] = {
    name = "metadata-numeric-type",
    query = "get_move_type_from_result",
    which = 1,
    moveType = 10,
    numericType = true,
    value = 10,
    expected = { true, true },
  }
  specs[#specs + 1] = {
    name = "last-move-alias",
    query = "get_move_type_from_result",
    which = 1,
    aliasLast = true,
    value = 2,
    expected = { true, true },
  }
  for _, query in ipairs({
    "get_move_type_from_result",
    "get_move_power_from_result",
    "get_move_effect_from_result",
  }) do
    specs[#specs + 1] = {
      name = query .. "-implicit-none",
      query = query,
      noHistory = true,
      omitNone = true,
      value = 0,
      expected = { true, true },
    }
  end
  for which = 0, 3 do
    specs[#specs + 1] = {
      name = "protect-unset-" .. which,
      query = "get_protect_count",
      which = which,
      noProtect = true,
      value = 0,
      expected = { true, true },
    }
  end
  -- Iteration order is stable even for the named type-alias fixture above.
  table.sort(specs, function(a, b)
    return a.name < b.name
  end)
  local rows = {}
  local noneDef = defs.MOVE_000
  for _, spec in ipairs(specs) do
    rawMoves[19].type = spec.moveType or 2
    defs.MOVE_019.type = spec.numericType and spec.moveType
      or spec.moveTypeName
      or typeNames[(spec.moveType or 2) + 1]
    defs.MOVE_000 = not spec.omitNone and noneDef or nil
    local battlers = {}
    local roleTypes = { [0] = { 0, 10 }, [1] = { 11, 11 }, [2] = { 12, 14 }, [3] = { 8, 17 } }
    for id = 0, spec.single and 1 or 3 do
      local kinds = roleTypes[id]
      battlers[id] = {
        id = id,
        position = id,
        isPlayer = id % 2 == 0,
        side = id % 2 == 0 and "player" or "enemy",
        mon = source and { moves = { 33, 76 }, pp = { 10, 10 } } or {},
        type1 = kinds[1],
        type2 = kinds[2],
        curTypes = { typeNames[kinds[1] + 1], typeNames[kinds[2] + 1] },
      }
      if id == 1 and spec.userType then
        battlers[id].type1, battlers[id].type2 = spec.userType, spec.userType
        battlers[id].curTypes = { spec.typeName or typeNames[spec.userType + 1] }
      end
      local count = spec.which == 1 and id == 1 or spec.which ~= 1 and id == 0
      battlers[id].expProtectStreak = count and spec.count or id + 10
      battlers[id].protectRun = battlers[id].expProtectStreak
      if count and spec.noProtect then
        battlers[id].expProtectStreak, battlers[id].protectRun = nil, nil
      end
      local flash = id == spec.which and spec.flash or id ~= spec.which and not spec.flash
      battlers[id].expFlashFire = flash
      battlers[id].flashFire = flash
      battlers[id].lastMove = spec.noHistory and nil
        or spec.last
        or (source and (id == 1 and 19 or 76) or (id == 1 and "MOVE_019" or "MOVE_076"))
      if spec.noHistory then
        battlers[id].lastMove = nil
      end
    end
    local user, target = battlers[1], battlers[0]
    local battle = {
      battlers = battlers,
      double = not spec.single,
      trainer = { aiFlags = 1 },
      sides = { { battlers = { battlers[0], battlers[2] } }, { battlers = { battlers[1], battlers[3] } } },
      data = {
        moves = defs,
        constants = { typeOrder = typeNames },
        type_chart = { types = { FAIRY = { index = 18 } } },
      },
    }
    if not source then
      setmetatable(battle, { __index = hostState })
    end
    local draws = {}
    battle.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return lo or 0
    end
    local branch = spec.query == "if_flash_fired"
    local scores, ok = { 100, 100 }
    if source then
      local ops = {}
      if spec.query:match("^get_move_") then
        ops[#ops + 1] = spec.considered and { op = "get_considered_move" }
          or { op = "get_last_used_move", battler = spec.which or 0 }
      end
      ops[#ops + 1] =
        { op = spec.query, battler = spec.which or 0, type = spec.typ, target = branch and "bonus" or nil }
      if not branch then
        ops[#ops + 1] = { op = "if_equal", value = spec.value, target = "bonus" }
      end
      ops[#ops + 1] = { op = "end" }
      local pack = { scripts = { main = ops, bonus = { { op = "score", delta = 5 }, { op = "end" } } } }
      ok = pcall(function()
        for slot = 1, 2 do
          VM.run(
            VM.new({
              pack = pack,
              st = battle,
              user = user,
              target = target,
              scores = scores,
              movesetIndex = slot,
              rng = battle.rng,
            }),
            "main"
          )
        end
      end)
    else
      local ops = {}
      if spec.query:match("^get_move_") then
        ops[#ops + 1] = spec.considered and { name = "get_considered_move", args = {} }
          or {
            name = spec.aliasLast and "get_last_used_move" or "get_last_used_bank_move",
            args = { spec.which or 0 },
          }
      end
      ops[#ops + 1] = {
        name = spec.query,
        args = branch and { spec.which or 0, 10 }
          or spec.query == "is_of_type" and { spec.which or 0, spec.typ }
          or { spec.which or 0 },
      }
      if not branch then
        ops[#ops + 1] = { name = "if_equal", args = { spec.value, 10 } }
      end
      ops[#ops + 1] = { name = "end", args = {} }
      for i, op in ipairs(ops) do
        op.next = i + 1
      end
      ops[10], ops[11] = { name = "score", args = { 5 }, next = 11 }, { name = "end", args = {} }
      local program = { entries = { [0] = 1 }, code = ops }
      battle.data.constants.gen3BattleAI = program
      T.eq(AI.runs(program, 1), true, spec.name .. " full reachable program is supported")
      local result
      ok, result = pcall(
        AI.scoreMoves,
        battle,
        user,
        target,
        { { id = "MOVE_033", pp = 10 }, { id = "MOVE_076", pp = 10 } }
      )
      if ok then
        scores = result
      end
    end
    T.eq(ok, not spec.error, spec.name .. " error boundary")
    if not spec.error then
      for slot = 1, 2 do
        T.eq(scores and scores[slot], spec.expected[slot] and 105 or 100, spec.name .. " branch result")
      end
    end
    T.eq(#draws, 0, spec.name .. " query consumes no RNG")
    rows[#rows + 1] = { name = spec.name, ok = ok, scores = scores or false, rng = draws }
  end
  for i = #restores, 1, -1 do
    restores[i]()
  end
  return rows
end
return C
