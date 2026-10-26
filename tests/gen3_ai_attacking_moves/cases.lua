-- Real native VMs and literal opcode dispatch for zero-usable-move contexts.
local C = {}
function C.run(root, backend, version)
  local source, T = backend == "gen1", require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local AI = not source and require("src.battle.Gen3AI")
  local VM = source and require("src.core.game3.battle.ai_vm")
  local Commands = source and require("src.core.game3.battle.ai_cmds")
  local copy = require("src.mods.Merge").deepCopy
  local raw = {
    [0] = { power = 255, type = 0, effect = 0 }, -- NONE must never be inspected.
    [1] = { power = 0, type = 0, effect = 0, pp = 10 },
    [33] = { power = 35, type = 0, effect = 0, pp = 10 },
  }
  local defs = {
    NONE = { index = 0, power = 255 },
    STATUS = { index = 1, power = 0 },
    ATTACK = { index = 33, power = 35, category = "status" },
  }
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
    patch(Moves, "_rom", raw)
    patch(Moves, "_romLoaded", true)
    patch(Moves, "_linkRows", nil)
    patch(Moves, "BY_NUM", { [0] = "NONE", [1] = "STATUS", [33] = "ATTACK" })
    patch(Moves, "_numByName", { NONE = 0, STATUS = 1, ATTACK = 33 })
  end
  local rows = {}
  local function check(name, ids, expected, opts)
    opts = opts or {}
    local battlers, draws = {}, {}
    for id = 0, 3 do
      battlers[id] = {
        id = id,
        position = id,
        isPlayer = id % 2 == 0,
        side = id % 2 == 0 and "player" or "enemy",
        mon = { moves = { 33, 33, 33, 33 }, pp = { 10, 10, 10, 10 }, hp = 100 },
        curMoves = { { id = "ATTACK", pp = 10 } },
      }
    end
    local user = battlers[opts.user or 1]
    local target = battlers[opts.target or 0]
    user.mon.moves, user.mon.pp = {}, {}
    local hostMoves = {}
    local candidate
    for i = 1, 5 do
      local n = ids[i]
      user.mon.moves[i] = n
      user.mon.pp[i] = opts.zeroPP and 0 or 10
      hostMoves[i] = n ~= nil
          and { id = ({ [0] = 0, [1] = "STATUS", [33] = "ATTACK" })[n] or n, pp = user.mon.pp[i] }
        or nil
      if i <= 4 and n ~= nil and n ~= 0 and n ~= "" and not opts.zeroPP then
        candidate = candidate or i
      end
    end
    if not source then
      user.curMoves = hostMoves
      if opts.noCurrent then
        user.curMoves = nil
      end
      user.mon.moves = opts.noCurrent and hostMoves or { { id = "STATUS", pp = 10 } }
    end
    user.disabledMove, user.disabledTurns, user.tauntTurns, user.expTauntedTurns = "ATTACK", 3, 2, 2
    local b = {
      battlers = battlers,
      double = true,
      data = { constants = {}, moves = defs },
      trainer = { aiFlags = 1 },
    }
    b.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return lo
    end
    for _, opcode in ipairs({ "if_user_has_attacking_move", "if_user_has_no_attacking_moves" }) do
      local before = copy(user)
      local ok, score = pcall(function()
        if source then
          local scores = { 100, 100, 100, 100 }
          local pack = {
            scripts = {
              main = { { op = opcode, target = "yes" }, { op = "end" } },
              yes = { { op = "score", delta = 5 }, { op = "end" } },
            },
          }
          local v = VM.new({
            st = b,
            user = user,
            target = target,
            scores = scores,
            pack = pack,
            movesetIndex = candidate or 1,
            rng = b.rng,
          })
          if candidate then
            VM.run(v, "main")
          else
            -- A native AI has no considered move on an empty/zero-PP board.
            -- Exercise its actual command rather than inventing a usable slot.
            v:jump("main")
            Commands.dispatch(v, v.ops[v.ip])
            return v.scriptName == "yes" and 105 or 100
          end
          return scores[candidate]
        end
        local program = {
          entries = { [0] = 1 },
          code = {
            { name = opcode, args = { 3 }, next = 2 },
            { name = "end", args = {} },
            { name = "score", args = { 5 }, next = 4 },
            { name = "end", args = {} },
          },
        }
        b.data.constants.gen3BattleAI = program
        if not candidate then
          return AI.OPS[opcode]({ battle = b, user = user, target = target }, { 3 }) == 3 and 105 or 100
        end
        T.eq(AI.runs(program, 1), true, name .. " query is reachable")
        local current = hostMoves[candidate]
        local scores = AI.scoreMoves(b, user, target, { { id = current.id, pp = 10 } })
        return scores and scores[1] or false
      end)
      T.eq(ok, not opts.error, name .. " error boundary")
      if ok then
        local hit = opcode == "if_user_has_attacking_move" and expected
          or opcode == "if_user_has_no_attacking_moves" and not expected
        T.eq(score, hit and 105 or 100, name .. "/" .. opcode)
      end
      T.same(user, before, name .. " preserves current moves and battle state")
      T.eq(#draws, 0, name .. " consumes no RNG")
      rows[#rows + 1] =
        { name = name, opcode = opcode, direct = candidate == nil, ok = ok, score = ok and score or false }
    end
  end
  for power = 0, 255 do
    raw[33].power, defs.ATTACK.power = power, power
    for slot = 1, 4 do
      local moves = { 1, 1, 1, 1 }
      moves[slot] = 33
      check(
        "power-" .. power .. "/slot-" .. slot,
        moves,
        power ~= 0,
        { user = power % 4, target = (power + 1) % 4 }
      )
    end
  end
  raw[33].power, defs.ATTACK.power = 35, 35
  for _, spec in ipairs({
    { name = "empty-board", ids = {}, hit = false },
    { name = "zero-board", ids = { 0, 0, 0, 0 }, hit = false },
    { name = "empty-strings", ids = { "", "", "", "" }, hit = false },
    { name = "only-status", ids = { 1, 1, 1, 1 }, hit = false },
    { name = "sparse-fourth", ids = { [4] = 33 }, hit = true },
    { name = "fifth-does-not-count", ids = { 1, 1, 1, 1, 33 }, hit = false },
    { name = "zero-pp-still-attacking", ids = { 1, 1, 33, 1 }, hit = true, zeroPP = true },
    { name = "missing-record", ids = { 1, 999, 1, 1 }, error = true },
    { name = "early-exit-before-invalid", ids = { 33, 999, 1, 1 }, hit = true },
    { name = "invalid-before-attack", ids = { 999, 33, 1, 1 }, error = true },
    { name = "mon-moves-fallback", ids = { 1, 1, 33, 1 }, hit = true, noCurrent = true },
  }) do
    for id = 0, 3 do
      spec.user, spec.target = id, (id + 1) % 4
      check(spec.name .. "/" .. id, spec.ids, spec.hit == true, spec)
    end
  end
  for i = #restores, 1, -1 do
    restores[i]()
  end
  return rows
end
return C
