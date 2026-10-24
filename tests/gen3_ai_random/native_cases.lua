-- Optional, read-only Emerald AI-stage import. No cartridge data is persisted.
local N = {}
function N.run(backend, romPath)
  require("tests.modkit")
  require("src.core.GameVersion").set("emerald")
  local function read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a")
    file:close()
    return bytes
  end
  local raw = read(romPath)
  assert(raw:sub(0xAD, 0xB0) == "BPEE", "expected the English Emerald cartridge")
  local source, program, pack, VM, AI = backend == "gen1"
  local allowed = {
    ["end"] = true,
    ["call"] = true,
    ["goto"] = true,
    score = true,
    if_random_less_than = true,
    if_random_greater_than = true,
    if_random_equal = true,
    if_random_not_equal = true,
  }
  local candidates = {}
  if source then
    require("src.import.gba.versions").select("emerald")
    local Rom = require("src.import.gba.rom")
    pack = require("src.import.gba.battle_ai_extract").extract(setmetatable({ _raw = raw, size = #raw }, Rom))
    VM = require("src.core.game3.battle.ai_vm")
    local function runnable(entry)
      local seen, queue = {}, { entry }
      while #queue > 0 do
        local name = table.remove(queue)
        if not seen[name] then
          seen[name] = true
          local body = pack.scripts[name]
          if not body then
            return false
          end
          for _, op in ipairs(body) do
            if not allowed[op.op] then
              return false
            end
            if op.target then
              queue[#queue + 1] = op.target
            end
          end
        end
      end
      return true
    end
    for label, body in pairs(pack.scripts) do
      if body[1] and body[1].op:match("^if_random_") and runnable(label) then
        candidates[#candidates + 1] = assert(tonumber(label:sub(3), 16))
      end
    end
  else
    local Json = require("src.link.Json")
    local Extract = require("src.import.RomExtractorGen3")
    local e = Extract.new(raw, "emerald", Json.decode(read("tools/rom_manifest_emerald.json")))
    function e:write(name, value)
      if name == "constants" then
        program = value.gen3BattleAI
      end
    end
    e:extractBattleAI()
    assert(program and program.code, "native Emerald AI stage did not produce a program")
    AI = require("src.battle.Gen3AI")
    for pc, op in pairs(program.code) do
      if op.name:match("^if_random_") then
        local runnable = true
        for name in pairs(AI.reachable(program, pc)) do
          if not allowed[name] then
            runnable = false
          end
        end
        if runnable then
          candidates[#candidates + 1] = pc
        end
      end
    end
  end
  table.sort(candidates)
  assert(#candidates > 0, "no native random-only subroutines were found")
  local rows = {}
  for _, pc in ipairs(candidates) do
    for _, rawValue in ipairs({ 0, 1, 79, 80, 127, 128, 255, 256, 384, 65535 }) do
      local draws = {}
      local function rng(lo, hi)
        assert(#draws < 100, "unbounded native subroutine")
        draws[#draws + 1] = { lo, hi }
        return rawValue
      end
      local scores
      if source then
        scores = { 100 }
        local vm = VM.new({
          pack = pack,
          user = { mon = { moves = { 33 }, pp = { 10 } } },
          scores = scores,
          movesetIndex = 1,
          rng = rng,
        })
        VM.run(vm, ("0x%06X"):format(pc))
      else
        program.entries = { [0] = pc }
        scores = AI.scoreMoves({
          trainer = { aiFlags = 1 },
          rng = rng,
          data = { constants = { gen3BattleAI = program }, moves = { TEST = { index = 33 } } },
        }, {}, {}, { { id = "TEST", pp = 10 } })
      end
      assert(scores and scores[1], "native subroutine produced no score")
      rows[#rows + 1] = { pc = pc, raw = rawValue, scores = scores, rng = draws }
    end
  end
  return rows
end
return N
