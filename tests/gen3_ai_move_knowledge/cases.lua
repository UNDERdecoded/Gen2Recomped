-- Same move-knowledge scenarios through the real source and host AI VMs.
local C = {}
function C.run(backend, version)
  local T, source = require("tests.modkit"), backend == "gen1"
  require("src.core.GameVersion").set(version)
  local VM = source and require("src.core.game3.battle.ai_vm")
  local AI = source and require("src.core.game3.battle.ai") or require("src.battle.Gen3AI")
  local K
  if not source then
    local ok, module = pcall(require, "src.battle.Gen3AIMoveKnowledge")
    K = ok and module or nil
    T.check(K ~= nil, "native move knowledge module is available")
  end
  local HostState = not source and require("src.battle.BattleState")
  local raw, defs, names = {}, {}, {}
  for _, row in ipairs({
    { 33, "TACKLE", 0 },
    { 76, "SOLARBEAM", 151 },
    { 19, "FLY", 155 },
    { 182, "PROTECT", 111 },
    { 45, "GROWL", 18 },
  }) do
    local n, name, e = unpack(row)
    raw[n] = { type = 0, power = 35, effect = e }
    names[n] = name
    defs["MOVE_" .. n] = { index = n, name = name, type = "NORMAL", power = 35, gen3Effect = e }
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
    local Moves, Pokemon = require("src.core.game3.battle.moves"), require("src.core.game3.pokemon")
    local byName = {}
    for n, name in pairs(names) do
      byName[name] = n
    end
    patch(Moves, "_rom", raw)
    patch(Moves, "_romLoaded", true)
    patch(Moves, "_linkRows", nil)
    patch(Moves, "_numByName", byName)
    patch(Moves, "BY_NUM", names)
    patch(Pokemon, "_moveNames", names)
    patch(Pokemon, "_romMoveNames", names)
    patch(Pokemon, "_battleMoves", raw)
  end
  local scenarios = {
    { name = "unobserved", history = {} },
    { name = "empty-name-slots", history = {}, emptyName = true },
    { name = "unknown-name-slots", history = {}, unknownName = true },
    { name = "invalid-definition", history = { 999 }, invalid = true },
    { name = "named-moves", history = { 33, 76 }, named = true },
    { name = "one-observed", history = { 33 } },
    { name = "second-observed", history = { 33, 76 } },
    { name = "duplicate-and-cap", history = { 33, 33, 76, 19, 182, 45 } },
    { name = "zero-not-learned", history = { 0, 33, 0, 76 } },
    { name = "stale-after-switch", history = { 33, 76 }, switch = true },
    { name = "learn-after-switch", history = { 33, 76 }, switch = true, after = 45 },
    { name = "absent-partner", history = { 33, 76 }, single = true },
    { name = "fainted-partner", history = { 33, 76 }, fainted = true },
    { name = "user-slot-gate", history = { 33, 76 }, sparse = true },
    { name = "one-user-slot", history = { 33, 76 }, empty = true },
    { name = "right-slot", history = { 33, 76 }, right = true },
  }
  local rows = {}
  local function snapshot(b, target)
    local row = source and AI.usedMoves(b, target.id) or K and K.usedMoves(b, target) or { 0, 0, 0, 0 }
    return { row[1], row[2], row[3], row[4] }
  end
  for _, scenario in ipairs(scenarios) do
    for _, query in ipairs({
      "if_has_move",
      "if_doesnt_have_move",
      "if_has_move_with_effect",
      "if_doesnt_have_move_with_effect",
    }) do
      for which = 0, 3 do
        local isEffect = query:find("with_effect") ~= nil
        for _, value in ipairs(isEffect and { 0, 151, 155, 111, 18, 999 } or { 0, 33, 76, 19, 182, 999 }) do
          local name = scenario.name .. "/" .. query .. "/" .. which .. "/" .. value
          local battlers = {}
          local function setMoves(b, list)
            local moves = {}
            for i = 1, 4 do
              local n = list[i]
              if n ~= nil then
                moves[i] = source and (scenario.named and names[n] or n)
                  or { id = type(n) == "string" and n or (n == 0 or n == 999) and n or "MOVE_" .. n, pp = 0 }
              end
            end
            b.mon.moves, b.mon.pp = moves, { 0, 0, 0, 0 }
            if not source then
              b.curMoves = moves
            end
          end
          local userId, targetId = scenario.right and 3 or 1, scenario.right and 2 or 0
          for id = 0, scenario.single and 1 or 3 do
            local b = {
              id = id,
              position = id,
              side = id % 2 == 0 and "player" or "enemy",
              isPlayer = id % 2 == 0,
              mon = { hp = 100 },
            }
            battlers[id] = b
            setMoves(
              b,
              id == userId and (scenario.empty and { 19 } or scenario.sparse and { 19, 0, 76 } or { 19, 76 })
                or id == targetId and (scenario.emptyName and { "", 33 } or scenario.unknownName and {
                  "NO_SUCH_MOVE",
                } or scenario.invalid and { 999 } or { 33, 76 })
                or id % 2 == 1 and { 182 }
                or { 45 }
            )
            if scenario.fainted and id == 3 then
              b.mon.hp = 0
            end
          end
          local user, target = battlers[userId], battlers[targetId]
          user.mon.pp[1] = 10
          local draws = {}
          local battle = {
            battlers = battlers,
            double = not scenario.single,
            trainer = { aiFlags = 1 },
            data = { moves = defs, constants = {} },
            sides = {
              { battlers = { battlers[0], battlers[2] } },
              { battlers = { battlers[1], battlers[3] } },
            },
            rng = function(lo, hi)
              draws[#draws + 1] = { lo, hi }
              return lo
            end,
          }
          if not source then
            setmetatable(battle, { __index = HostState })
          end
          -- An unrelated history family must survive learning and switching.
          battle._aiHistory = { unrelated = "preserved" }
          local function observe(n)
            target.lastMove = source and n or (n == 0 or n == 999) and n or "MOVE_" .. n
            if source then
              AI.recordLastUsedMove(battle, targetId)
            elseif K then
              K.observe(battle, target)
            end
          end
          for _, n in ipairs(scenario.history) do
            observe(n)
          end
          if scenario.switch then
            target.mon = { hp = 100 }
            setMoves(target, { 45 })
            target.lastMove = nil
            if scenario.after then
              observe(scenario.after)
            end
          end
          local history = snapshot(battle, target)
          T.eq(battle._aiHistory.unrelated, "preserved", name .. " keeps other history")
          if version == "emerald" then
            if scenario.switch then
              T.eq(history[1], scenario.after or 0, name .. " identity changes clear stale knowledge")
            elseif scenario.name == "duplicate-and-cap" then
              for i, n in ipairs({ 33, 76, 19, 182 }) do
                T.eq(history[i], n, name .. " bounded insertion order")
              end
            elseif scenario.name == "unobserved" then
              T.eq(history[1], 0, name .. " does not reveal target moves")
            end
          end
          local scores, ok = { 100 }
          if source then
            local pack = {
              scripts = {
                main = {
                  {
                    op = query,
                    battler = which,
                    move = not isEffect and value or nil,
                    effect = isEffect and value or nil,
                    target = "bonus",
                  },
                  { op = "end" },
                },
                bonus = { { op = "score", delta = 5 }, { op = "end" } },
              },
            }
            ok = pcall(function()
              for slot = 1, 1 do
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
            local program = {
              entries = { [0] = 1 },
              code = {
                { name = query, args = { which, value, 3 }, next = 2 },
                { name = "end", args = {} },
                { name = "score", args = { 5 }, next = 4 },
                { name = "end", args = {} },
              },
            }
            battle.data.constants.gen3BattleAI = program
            T.eq(AI.runs(program, 1), true, name .. " reachable")
            local result
            ok, result = pcall(AI.scoreMoves, battle, user, target, { { id = "MOVE_19", pp = 10 } })
            if ok then
              scores = result
            end
          end
          local expectedError = (scenario.invalid or scenario.unknownName and version == "firered")
            and isEffect
            and (version == "firered" and which ~= 1 or version == "emerald" and (which == 0 or which == 2))
          T.eq(ok, not expectedError, name .. " error boundary")
          T.eq(scores and scores[1] == 100 or scores and scores[1] == 105, true, name .. " branch score")

          T.same(snapshot(battle, target), history, name .. " read query preserves knowledge")
          T.eq(#draws, 0, name .. " no query RNG")
          rows[#rows + 1] = {
            name = name,
            ok = ok,
            scores = scores or false,
            history = version == "emerald" and history or {},
            rng = draws,
          }
        end
      end
    end
  end
  for i = #restores, 1, -1 do
    restores[i]()
  end
  return rows
end
return C
