-- Equal control-flow programs through each engine's actual native AI VM.
local C = {}
function C.run(backend, version)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local source = backend == "gen1"
  local VM = source and require("src.core.game3.battle.ai_vm")
  local AI = not source and require("src.battle.Gen3AI")
  local rows = {}
  for _, opcode in ipairs({
    "if_random_less_than",
    "if_random_greater_than",
    "if_random_equal",
    "if_random_not_equal",
  }) do
    for _, threshold in ipairs({ 0, 128, 255 }) do
      for _, raw in ipairs({ 0, 127, 128, 129, 255, 256, 257, 384, 65534, 65535 }) do
        local draws, index = {}, 0
        local values = { raw, (raw + 1) % 65536 }
        local function rng(lo, hi)
          index = index + 1
          draws[#draws + 1] = { lo, hi }
          return assert(values[index], "unexpected native AI RNG draw")
        end
        local scores
        if source then
          local user = { mon = { moves = { 33, 76 }, pp = { 10, 10 } } }
          local pack = {
            scripts = {
              main = { { op = "call", target = "test" }, { op = "end" } },
              test = { { op = opcode, value = threshold, target = "bonus" }, { op = "end" } },
              bonus = { { op = "score", delta = 5 }, { op = "end" } },
            },
          }
          scores = { 100, 100 }
          for slot = 1, 2 do
            local vm = VM.new({ pack = pack, user = user, scores = scores, movesetIndex = slot, rng = rng })
            VM.run(vm, "main")
          end
        else
          local program = {
            entries = { [0] = 1 },
            code = {
              { name = "call", args = { 3 }, next = 2 },
              { name = "end", args = {} },
              { name = opcode, args = { threshold, 6 }, next = 4 },
              { name = "end", args = {} },
              [6] = { name = "score", args = { 5 }, next = 7 },
              [7] = { name = "end", args = {} },
            },
          }
          local battle = {
            trainer = { aiFlags = 1 },
            rng = rng,
            data = {
              constants = { gen3BattleAI = program },
              moves = {
                FIRST = { index = 33 },
                SECOND = { index = 76 },
              },
            },
          }
          T.eq(AI.runs(program, 1), true, opcode .. " supports the whole reachable script")
          scores = AI.scoreMoves(battle, {}, {}, { { id = "FIRST", pp = 10 }, { id = "SECOND", pp = 10 } })
        end
        T.eq(#draws, 2, opcode .. " consumes one draw per move")
        for slot = 1, 2 do
          local byte = values[slot] % 256
          local taken = {
            if_random_less_than = byte < threshold,
            if_random_greater_than = byte > threshold,
            if_random_equal = byte == threshold,
            if_random_not_equal = byte ~= threshold,
          }
          T.eq(scores and scores[slot], taken[opcode] and 105 or 100, opcode .. " exact low-byte branch")
          T.eq(draws[slot] and draws[slot][1], 0, "native Random lower bound")
          T.eq(draws[slot] and draws[slot][2], 65535, "native Random upper bound")
        end
        rows[#rows + 1] = { opcode = opcode, threshold = threshold, raw = raw, scores = scores, rng = draws }
      end
    end
  end
  return rows
end
return C
