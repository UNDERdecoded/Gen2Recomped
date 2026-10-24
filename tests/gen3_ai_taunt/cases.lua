-- Shared real-VM predicates and native effect/residual lifetime checks.
local C = {}
function C.run(backend, version)
  local T, source = require("tests.modkit"), backend == "gen1"
  require("src.core.GameVersion").set(version)
  local VM = source and require("src.core.game3.battle.ai_vm")
  local AI = not source and require("src.battle.Gen3AI")
  local HostState = not source and require("src.battle.BattleState")
  local function fresh(double)
    local b = {
      battlers = {},
      double = double,
      absent = {},
      over = false,
      playerSide = { hazards = {} },
      enemySide = { hazards = {} },
      trainer = { aiFlags = 1 },
      turn = 1,
      data = { constants = {}, moves = { TEST = { index = 33 } } },
    }
    for id = 0, double and 3 or 1 do
      b.battlers[id] = {
        id = id,
        position = id,
        side = id % 2 == 0 and "player" or "enemy",
        isPlayer = id % 2 == 0,
        name = "TEST",
        ability = 0,
        stages = {},
        mon = {
          hp = 100,
          maxHp = 100,
          speed = 100 - id * 10,
          level = 30,
          ability = 0,
          item = 0,
          moves = { 33 },
          pp = { 10 },
          stats = { hp = 100, speed = 100 - id * 10 },
        },
      }
    end
    b.player, b.enemy = b.battlers[0], b.battlers[1]
    b.playerParty, b.foeParty = { b.player.mon }, { b.enemy.mon }
    b.sides = {
      { battlers = { b.battlers[0], b.battlers[2] } },
      { battlers = { b.battlers[1], b.battlers[3] } },
    }
    local draws = {}
    b.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return lo
    end
    if not source then
      setmetatable(b, { __index = HostState })
    end
    return b, draws
  end
  local function timer(target)
    return tonumber(target and (source and target.expTauntedTurns or target.tauntTurns)) or 0
  end
  local function setTimer(target, value)
    if source then
      target.expTauntedTurns = value
    else
      target.tauntTurns = value
    end
  end
  local function query(b, user, target, opcode)
    local scores = { 100 }
    if source then
      local pack = {
        scripts = {
          main = { { op = opcode, target = "bonus" }, { op = "end" } },
          bonus = { { op = "score", delta = 5 }, { op = "end" } },
        },
      }
      VM.run(
        VM.new({
          st = b,
          user = user,
          target = target,
          scores = scores,
          movesetIndex = 1,
          pack = pack,
          rng = b.rng,
        }),
        "main"
      )
    else
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
      T.eq(AI.runs(program, 1), true, "Taunt predicate is reachable")
      scores = AI.scoreMoves(b, user, target, { { id = "TEST", pp = 10 } })
    end
    return scores and scores[1] or false
  end
  local rows = {}
  for _, double in ipairs({ false, true }) do
    for id = 0, double and 3 or 1 do
      for _, value in ipairs({ false, 0, 1, 2, 7, "1", -1 }) do
        local b, draws = fresh(double)
        local user, target = b.battlers[id % 2 == 0 and 1 or 0], b.battlers[id]
        -- Other battlers carry the opposite state; predicates must read TARGET.
        for _, other in pairs(b.battlers) do
          setTimer(other, tonumber(value) and tonumber(value) > 0 and 0 or 2)
        end
        setTimer(target, value or nil)
        local before = timer(target)
        local active, inactive =
          query(b, user, target, "if_target_taunted"), query(b, user, target, "if_target_not_taunted")
        T.eq(active, before > 0 and 105 or 100, "positive predicate reads live target timer")
        T.eq(inactive, before <= 0 and 105 or 100, "negative predicate reads live target timer")
        T.eq(timer(target), before, "read query preserves timer")
        T.eq(#draws, 0, "read queries consume no RNG")
        rows[#rows + 1] = {
          name = (double and "double" or "single") .. "/" .. id .. "/" .. type(value) .. ":" .. tostring(
            value
          ),
          active = active,
          inactive = inactive,
          timer = before,
          rng = draws,
        }
      end
    end
  end
  local b, draws = fresh(false)
  local user, target = b.enemy, b.player
  local apply, tick, restore
  if source then
    local Adapter = require("src.core.game3.battle.adapter")
    local old = Adapter.textSink
    Adapter.textSink = function(id)
      return id
    end -- presentation-only ROM text seam
    restore = function()
      Adapter.textSink = old
    end
    local adapter = Adapter.new(b)
    local Status = require("src.core.game3.battle.effects.status")
    apply = function()
      Status.taunt({ adapter = adapter, user = user, target = target })
    end
    require("src.core.game3.battle.residual_handlers").registerAll()
    tick = function()
      require("src.core.game3.battle.residuals").runTurn(adapter)
    end
  else
    local effect = require("src.battle.Gen3MoveEffects").primary.TAUNT_EFFECT
    apply = function()
      effect(b, user, target)
    end
    -- Ordinary message queue storage, without a graphical consumer.
    b.queue = {}
    tick = function()
      b:gen3CountersTick()
    end
    restore = function() end
  end
  local function observe(label, expected)
    local active = query(b, user, target, "if_target_taunted")
    local inactive = query(b, user, target, "if_target_not_taunted")
    T.eq(timer(target), expected, label .. " actual native timer")
    T.eq(active, expected > 0 and 105 or 100, label .. " positive predicate")
    T.eq(inactive, expected == 0 and 105 or 100, label .. " negative predicate")
    rows[#rows + 1] = { name = label, timer = timer(target), active = active, inactive = inactive }
  end
  setTimer(target, 0)
  observe("before-effect", 0)
  apply()
  observe("after-effect", 2)
  tick()
  observe("after-first-residual", 1)
  apply()
  observe("repeat-does-not-refresh", 1)
  tick()
  observe("after-second-residual", 0)
  apply()
  observe("can-reapply-after-expiry", 2)
  restore()
  return rows
end
return C
