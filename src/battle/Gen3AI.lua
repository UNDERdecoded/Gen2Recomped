-- Hoenn's trainer AI, run rather than approximated.
--
-- `gTrainers[].aiFlags` is a bitfield and each bit names a SCRIPT: a little
-- bytecode program with about a hundred opcodes, its own interpreter
-- (sBattleAICmdTable, 0x5B083C) and one signed score per move.  The importer
-- decodes the programs out of the cartridge -- RomExtractorGen3:extractBattleAI
-- -- and this is the interpreter for them.
--
-- WHAT IT REPLACES.  Nothing ran them, so `TrainerAI.chooseMove` fell through
-- to `usable[rng(1, #usable)]` for every trainer in the region: Steven and the
-- Elite Four picked moves by coin flip.  Six hundred and forty trainers carry
-- AI_FLAG_CHECK_BAD_MOVE alone, a hundred and seventy-three carry
-- BAD_MOVE|TRY_TO_FAINT|CHECK_VIABILITY, and the rest are small groups on top
-- of those.
--
-- ------- THE RULE THAT MAKES THIS SAFE TO SHIP HALF-BUILT
--
-- A script is run only when EVERY opcode reachable inside it has an
-- implementation here.  One that reaches an opcode this file does not
-- implement is not run at all -- not run partly, not run with the unknown
-- step treated as a no-op, which would be an invented program rather than the
-- cartridge's.  Its moves keep the score they started with, and a trainer
-- whose every script was skipped comes out exactly where it came out before:
-- all scores equal, and the tie-break below is a uniform roll, which is the
-- random choice this engine already made.
--
-- So the floor never moves and the ceiling rises one script at a time.
-- `Gen3AI.coverage` reports which are live, and the tests assert it, so
-- "which of these actually runs" is a number rather than a claim.
--
-- ------- WHAT THE OPERANDS MEAN
--
-- Read out of the handlers rather than assumed: a battler operand is 0 for
-- the TARGET and 1 for the USER (`get_ability` settles it with a bare
-- `cmp #1`), results land in the thinking struct's funcResult, and the move
-- being scored is the one the outer loop is on.  Numbers stay the
-- cartridge's own -- effect 0x67, ability 0x1A, type 0x0D -- because that is
-- what the bytecode compares against, so the bridges are here and not in the
-- importer.

local Gen3AI = {}

-- AI_SetupAIData: every move starts at 100 and a script moves it from there.
Gen3AI.START_SCORE = 100
-- a runaway program is a bug in this file, not in the cartridge; the longest
-- real script is a thousand-odd instructions and no path through one is
-- anywhere near this
Gen3AI.STEP_CAP = 4096

-- ---------------------------------------------------------------------------
-- The opcodes
--
-- Each takes (vm, args) and returns the address to continue at, or nil to run
-- straight on to the next instruction.  `false` stops the script.
-- ---------------------------------------------------------------------------

Gen3AI.OPS = {}
local OPS = Gen3AI.OPS

-- ------- flow

OPS["end"] = function(vm)
  -- AIStackPop: `end` is also the return from a `call`, and only ends the
  -- script when nothing called it
  local back = table.remove(vm.stack)
  if back then return back end
  return false
end

OPS["goto"] = function(_, args) return args[1] end

OPS["call"] = function(vm, args, nextAt)
  vm.stack[#vm.stack + 1] = nextAt
  return args[1]
end

-- ------- the score itself

OPS["score"] = function(vm, args)
  -- a signed byte: 0xFF is -1, which is how a script discourages
  local by = args[1]
  if by > 127 then by = by - 256 end
  local at = vm.moveIndex
  vm.score[at] = (vm.score[at] or Gen3AI.START_SCORE) + by
  -- BattleAICmd_score clamps at zero rather than letting it run negative
  if vm.score[at] < 0 then vm.score[at] = 0 end
end

-- ------- the comparisons, which all read funcResult

local function cmp(test)
  return function(vm, args)
    if test(vm.result, args[1]) then return args[#args] end
  end
end

OPS["if_equal"] = cmp(function(a, b) return a == b end)
OPS["if_not_equal"] = cmp(function(a, b) return a ~= b end)
OPS["if_less_than"] = cmp(function(a, b) return a < b end)
OPS["if_more_than"] = cmp(function(a, b) return a > b end)
-- the two trailing-underscore forms are the same test on the same variable;
-- the cartridge has a second copy of each handler and the scripts use both
OPS["if_equal_"] = OPS["if_equal"]
OPS["if_not_equal_"] = OPS["if_not_equal"]

-- ------- membership, against the tables the importer read out

local function inList(vm, args)
  local list = vm.program.lists and vm.program.lists[args[1]]
  if not list then return nil end
  for _, v in ipairs(list) do
    if v == vm.result then return true end
  end
  return false
end

OPS["if_in_bytes"] = function(vm, args)
  local got = inList(vm, args)
  if got == nil then return nil end
  if got then return args[#args] end
end

OPS["if_not_in_bytes"] = function(vm, args)
  local got = inList(vm, args)
  if got == nil then return nil end
  if not got then return args[#args] end
end

OPS["if_in_hwords"] = OPS["if_in_bytes"]
OPS["if_not_in_hwords"] = OPS["if_not_in_bytes"]

-- ------- the roll
--
-- Random() & 0xFF < n, so `if_random_less_than 0x80` is a coin flip and
-- 0x50 is a little under a third.
OPS["if_random_less_than"] = function(vm, args)
  if vm.rng(0, 255) < args[1] then return args[#args] end
end

OPS["if_random_greater_than"] = function(vm, args)
  if vm.rng(0, 255) > args[1] then return args[#args] end
end

-- ------- reading the battle

OPS["if_target_is_ally"] = function(vm, args)
  -- the prologue every script opens with: in a double battle a move can be
  -- pointed at your own partner, and none of this scoring is about that
  local user, target = vm.user, vm.target
  if user and target and user.isPlayer == target.isPlayer then
    return args[#args]
  end
end

OPS["get_turn_count"] = function(vm)
  -- battleTurnCounter is 0 while the FIRST turn is being chosen, which is
  -- exactly when this engine asks: resolveTurn increments after the foe has
  -- already answered
  vm.result = vm.battle.turnCount or 0
end

OPS["get_considered_move_effect"] = function(vm)
  vm.result = vm.moveEffect or 0
end

OPS["get_considered_move"] = function(vm)
  vm.result = vm.moveNumber or 0
end

-- ------- the move's own effect, which these two read directly
--
-- `if_effect` does not go through funcResult: the handler compares
-- gBattleMoves[moveConsidered].effect against the operand and nothing else,
-- so a script can test it without a `get_` first.
OPS["if_effect"] = function(vm, args)
  if (vm.moveEffect or 0) == args[1] then return args[#args] end
end

OPS["if_not_effect"] = function(vm, args)
  if (vm.moveEffect or 0) ~= args[1] then return args[#args] end
end

-- ---------------------------------------------------------------------------
-- WHAT THIS MOVE WOULD DO, which three opcodes are built on
--
-- AI_CalcDmg is the ordinary damage formula with the random factor left OFF
-- and the critical multiplier at one; the AI then multiplies by its own roll,
-- simulatedRNG, which is `100 - Random() % 10` -- ninety-one to a hundred
-- percent, drawn ONCE per move when the thinking struct is set up and reused
-- by every script that asks.  So it is a slightly pessimistic estimate that
-- stays the same all the way through the scoring, and that is why a foe does
-- not change its mind about whether a move kills between two passes.
--
-- The base number comes from this engine's own Damage.compute rather than a
-- second formula: an AI that estimates by different rules than the battle
-- resolves by is an AI that is wrong in exactly the cases that matter.  The
-- random factor is pinned to the top of its range, which is what leaving it
-- out means here (Gen 3 rolls 85..100 out of 100).
local function estimate(vm, index)
  vm.damage = vm.damage or {}
  local memo = vm.damage[index]
  if memo ~= nil then return memo end
  local out = 0
  local move = vm.moves and vm.moves[index]
  local def = move and vm.battle.data and vm.battle.data.moves
               and vm.battle.data.moves[move.id]
  local power = def and tonumber(def.power) or 0
  if def and power > 1 and vm.user and vm.target then
    local ok, Damage = pcall(require, "src.battle.Damage")
    if ok and Damage and Damage.compute then
      local okDmg, dmg = pcall(Damage.compute, vm.battle.ruleset, vm.user,
        vm.target, def, { rng = function(_, hi) return hi end,
                          forceCrit = false, data = vm.battle.data })
      if okDmg then out = tonumber(dmg) or 0 end
    end
    -- the AI's own roll, one per move, held for the whole pass
    vm.roll = vm.roll or {}
    if not vm.roll[index] then
      vm.roll[index] = 100 - (vm.rng(0, 9))
    end
    out = math.floor(out * vm.roll[index] / 100)
    if out == 0 then out = 1 end
  end
  vm.damage[index] = out
  return out
end

-- Published under its own name, and called under it above: the damage model
-- is the one seam a test wants to stand in for without standing in for the
-- whole battle.
Gen3AI.estimate = estimate

-- Does it kill?  The handler refuses a move of power 0 or 1 outright and then
-- compares the estimate against the target's CURRENT hp, jumping when the
-- damage reaches it.
local function canFaint(vm)
  local move = vm.moves and vm.moves[vm.moveIndex]
  local def = move and vm.battle.data and vm.battle.data.moves
               and vm.battle.data.moves[move.id]
  if not def or (tonumber(def.power) or 0) <= 1 then return false end
  local hp = vm.target and vm.target.mon and tonumber(vm.target.mon.hp) or 0
  return Gen3AI.estimate(vm, vm.moveIndex) >= hp
end

OPS["if_can_faint"] = function(vm, args)
  if canFaint(vm) then return args[#args] end
end

OPS["if_cant_faint"] = function(vm, args)
  if not canFaint(vm) then return args[#args] end
end

-- MOVE_POWER_OTHER(0) for a move with no power worth counting or one of the
-- discouraged effects; otherwise MOVE_MOST_POWERFUL(2) when nothing else in
-- the moveset estimates higher, and MOVE_NOT_MOST_POWERFUL(1) when something
-- does.  The discouraged list is sDiscouragedPowerfulMoveEffects, read out of
-- the cartridge by the importer -- EXPLOSION should not count as this
-- Pokemon's best move just because the number is large.
OPS["get_how_powerful_move_is"] = function(vm)
  local data = vm.battle.data or {}
  local function defOf(i)
    local m = vm.moves and vm.moves[i]
    return m and data.moves and data.moves[m.id] or nil
  end
  local function counts(i)
    local def = defOf(i)
    if not def or (tonumber(def.power) or 0) <= 1 then return false end
    for _, e in ipairs(vm.program.discouraged or {}) do
      if e == tonumber(def.gen3Effect) then return false end
    end
    return true
  end
  if not counts(vm.moveIndex) then vm.result = 0 return end
  local mine = Gen3AI.estimate(vm, vm.moveIndex)
  for i = 1, #(vm.moves or {}) do
    if i ~= vm.moveIndex and counts(i) and Gen3AI.estimate(vm, i) > mine then
      vm.result = 1
      return
    end
  end
  vm.result = 2
end

-- THE AI'S OWN EFFECTIVENESS SCALE, which is not the battle's.
--
-- The handler seeds the damage variable with 40 and runs the type chart over
-- it, so neutral is 40, doubling is 80, quadrupling 160, halving 20 and
-- quartering 10 -- and an immunity is 0.  `if_type_effectiveness 0xA0` is
-- therefore "is this four times effective", which is what AI_TryToFaint asks
-- before it spends a bonus on a move that will not kill.
function Gen3AI.effectiveness(vm)
  local data = vm.battle.data or {}
  local move = vm.moves and vm.moves[vm.moveIndex]
  local def = move and data.moves and data.moves[move.id] or nil
  if not (def and def.type and vm.target) then return 40 end
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  if not (ok and TypeChart and TypeChart.rows) then return 40 end
  local types = vm.target.curTypes
  if not types then
    local mon = vm.target.mon
    types = mon and mon.types or {}
  end
  local okRows, rows = pcall(TypeChart.rows, def.type, types)
  if not okRows or type(rows) ~= "table" then return 40 end
  local v = 40
  for _, r in ipairs(rows) do v = math.floor(v * r / 10) end
  return v
end

OPS["if_type_effectiveness"] = function(vm, args)
  if Gen3AI.effectiveness(vm) == args[1] then return args[#args] end
end


-- ---------------------------------------------------------------------------
-- The battle, read the way the bytecode expects to read it
--
-- Every number below is the CARTRIDGE's -- ability 26, type 13, stat 3,
-- STATUS2_TORMENT -- because that is what the operands are.  Where this
-- engine models the same thing under a name, the bridge is here; where it
-- does not model it at all the flag simply never sets, and that is the honest
-- answer rather than a guess: the AI is scoring the battle THIS engine will
-- run, not the one the cartridge would have.
-- ---------------------------------------------------------------------------

-- 0 is the target and 1 the user; 2 and 3 are their partners.  Pinned off
-- get_ability, which settles it with a bare `cmp #1`.
local function who(vm, n)
  n = tonumber(n) or 0
  if n == 1 then return vm.user end
  if n == 0 then return vm.target end
  local of = (n == 3) and vm.user or vm.target
  local battle = vm.battle
  if battle and battle.partnerOf and of then return battle:partnerOf(of) end
  return nil
end
Gen3AI.who = who

local function indexOf(vm, group, id)
  local c = vm.battle.data and vm.battle.data.constants
  local row = c and c[group] and c[group][id]
  return row and tonumber(row.index) or 0
end

OPS["get_ability"] = function(vm, args)
  local b = who(vm, args[1])
  vm.result = 0
  if not b then return end
  local ok, Abilities = pcall(require, "src.battle.Abilities")
  local id = ok and Abilities and Abilities.of and Abilities.of(b) or nil
  if id then vm.result = indexOf(vm, "abilities", id) end
end

-- funcResult is 1 when the battler has it.  The cartridge also answers 2 for
-- "it might, we have not seen it act" and no script in Hoenn tests for that,
-- so the two answers this one gives are the two that are asked for.
OPS["check_ability"] = function(vm, args)
  local b = who(vm, args[1])
  vm.result = 0
  if not b then return end
  local ok, Abilities = pcall(require, "src.battle.Abilities")
  local id = ok and Abilities and Abilities.of and Abilities.of(b) or nil
  if id and indexOf(vm, "abilities", id) == args[2] then vm.result = 1 end
end

-- 0 and 2 are the target's two types, 1 and 3 the user's, 4 the considered
-- move's -- read off the five-way jump table in the handler.
OPS["get_type"] = function(vm, args)
  local sel = tonumber(args[1]) or 0
  vm.result = 0
  local function typeNumber(id)
    if not id then return 0 end
    return indexOf(vm, "types", id)
  end
  if sel == 4 then
    local move = vm.moves and vm.moves[vm.moveIndex]
    local def = move and vm.battle.data and vm.battle.data.moves
                 and vm.battle.data.moves[move.id]
    vm.result = typeNumber(def and def.type)
    return
  end
  local b = (sel == 1 or sel == 3) and vm.user or vm.target
  local types = b and (b.curTypes or (b.mon and b.mon.types)) or {}
  local slot = (sel == 0 or sel == 1) and 1 or 2
  -- a single-typed Pokemon carries the same type in both slots, which is how
  -- the cartridge stores one
  vm.result = typeNumber(types[slot] or types[1])
end

-- MON_MALE is 0 and MON_FEMALE 0xFE, which the ATTRACT branch confirms: it
-- reads both genders and calls the move bad when they match.
OPS["get_gender"] = function(vm, args)
  local b = who(vm, args[1])
  vm.result = 0xFF
  local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
  if not (ok and Pokemon and Pokemon.genderOf and b and b.mon) then return end
  local okG, g = pcall(Pokemon.genderOf, b.mon, vm.battle.data)
  if not okG then return end
  if g == "F" or g == "female" then vm.result = 0xFE
  elseif g == "M" or g == "male" then vm.result = 0
  else vm.result = 0xFF end
end

-- gBattleWeather, folded to the AI's own four: rain 1, sandstorm 2, sun 3,
-- hail 4 (the handler masks 0x7, 0x18, 0x60 and 0x80 in that order).
local AI_WEATHER = { RAIN = 1, SANDSTORM = 2, SUN = 3, HAIL = 4 }

OPS["get_weather"] = function(vm)
  local field = vm.battle.field
  vm.result = AI_WEATHER[field and field.weather] or 0
end

OPS["get_stockpile_count"] = function(vm, args)
  local b = who(vm, args[1])
  vm.result = (b and tonumber(b.stockpile)) or 0
end

OPS["get_used_held_item"] = function(vm, args)
  local b = who(vm, args[1])
  vm.result = 0
  local used = b and (b.usedItem or b.consumedItem)
  if used then vm.result = indexOf(vm, "items", used) end
end

-- The bench: everything on that side that could still come out.  The
-- cartridge counts party members that are alive, not eggs, and not already
-- standing on the field.
OPS["count_usable_party_mons"] = function(vm, args)
  local b = who(vm, args[1])
  vm.result = 0
  if not b then return end
  local battle = vm.battle
  local party
  if b.isPlayer then
    party = battle.playerParty or (battle.game and battle.game.save
                                   and battle.game.save.party)
  else
    party = battle.enemyParty
  end
  local out, side = 0, battle.sides and battle.sides[b.isPlayer and 1 or 2]
  local onField = {}
  for _, slot in pairs((side and side.battlers) or {}) do
    if slot and slot.mon then onField[slot.mon] = true end
  end
  for _, mon in ipairs(party or {}) do
    if mon and (tonumber(mon.hp) or 0) > 0 and not mon.isEgg
       and not onField[mon] then
      out = out + 1
    end
  end
  vm.result = out
end

OPS["is_double_battle"] = function(vm)
  vm.result = (vm.battle.isDouble and vm.battle:isDouble()) and 1 or 0
end

-- isFirstTurn: the turn the Pokemon came out on.  turnsOut is bumped at the
-- top of resolveTurn, AFTER the foe has already been asked, so it still reads
-- zero while this is being scored on that first turn.
OPS["is_first_turn_for"] = function(vm, args)
  local b = who(vm, args[1])
  vm.result = (b and (tonumber(b.turnsOut) or 0) == 0) and 1 or 0
end

OPS["if_hp_less_than"] = function(vm, args)
  local b = who(vm, args[1])
  if not (b and b.mon and b.mon.stats) then return end
  local maxHP = math.max(1, tonumber(b.mon.stats.hp) or 1)
  local pct = math.floor((tonumber(b.mon.hp) or 0) * 100 / maxHP)
  if pct < args[2] then return args[#args] end
end

OPS["if_hp_more_than"] = function(vm, args)
  local b = who(vm, args[1])
  if not (b and b.mon and b.mon.stats) then return end
  local maxHP = math.max(1, tonumber(b.mon.stats.hp) or 1)
  local pct = math.floor((tonumber(b.mon.hp) or 0) * 100 / maxHP)
  if pct > args[2] then return args[#args] end
end

OPS["if_hp_equal"] = function(vm, args)
  local b = who(vm, args[1])
  if not (b and b.mon and b.mon.stats) then return end
  local maxHP = math.max(1, tonumber(b.mon.stats.hp) or 1)
  local pct = math.floor((tonumber(b.mon.hp) or 0) * 100 / maxHP)
  if pct == args[2] then return args[#args] end
end

OPS["if_hp_not_equal"] = function(vm, args)
  local b = who(vm, args[1])
  if not (b and b.mon and b.mon.stats) then return end
  local maxHP = math.max(1, tonumber(b.mon.stats.hp) or 1)
  local pct = math.floor((tonumber(b.mon.hp) or 0) * 100 / maxHP)
  if pct ~= args[2] then return args[#args] end
end

-- THE STAGES ARE SHIFTED.  The cartridge keeps them 0..12 with 6 for neutral;
-- this engine keeps them -6..+6 with 0.  `if_stat_level_equal TARGET, SPEED,
-- 0` is therefore "the target's speed is at the FLOOR", which is what
-- CheckBadMove asks before it decides a speed-lowering move is wasted -- and
-- the check_ability for SPEED BOOST sitting on the next line is what says the
-- reading is right.
local STAT_STAGE = { [1] = "attack", [2] = "defense", [3] = "speed",
                     [4] = "spatk", [5] = "spdef", [6] = "accuracy",
                     [7] = "evasion" }

local function stageOf(vm, args)
  local b = who(vm, args[1])
  local name = STAT_STAGE[tonumber(args[2]) or 0]
  if not (b and name) then return nil end
  local stages = b.stages or {}
  local v = tonumber(stages[name])
  if v == nil and (name == "spatk" or name == "spdef") then
    v = tonumber(stages.special)
  end
  return (v or 0) + 6
end

OPS["if_stat_level_less_than"] = function(vm, args)
  local got = stageOf(vm, args)
  if got and got < args[3] then return args[#args] end
end

OPS["if_stat_level_more_than"] = function(vm, args)
  local got = stageOf(vm, args)
  if got and got > args[3] then return args[#args] end
end

OPS["if_stat_level_equal"] = function(vm, args)
  local got = stageOf(vm, args)
  if got and got == args[3] then return args[#args] end
end

OPS["if_stat_level_not_equal"] = function(vm, args)
  local got = stageOf(vm, args)
  if got and got ~= args[3] then return args[#args] end
end

-- ------- the three status words

local STATUS1 = { SLP = 0x07, PSN = 0x08, BRN = 0x10, FRZ = 0x20, PAR = 0x40 }

local function status1(b)
  if not (b and b.mon) then return 0 end
  -- a badly poisoned Pokemon carries TOXIC_POISON and not POISON, which is
  -- why the two bits are separate on the cartridge
  if b.toxicCounter then return 0x80 end
  return STATUS1[b.mon.status] or 0
end

local function status2(b)
  if not b then return 0 end
  local v = 0
  if b.confusedTurns then v = v + 0x7 end
  if b.infatuated then v = v + 0xF0000 end
  if b.focusEnergy then v = v + 0x100000 end
  if b.substituteHP then v = v + 0x1000000 end
  if b.trappingTurns or b.boundTurns then v = v + 0x4000000 end
  if b.nightmare then v = v + 0x8000000 end
  if b.foresighted then v = v + 0x20000000 end
  if b.tormented then v = v + 0x80000000 end
  return v
end

local function status3(b)
  if not b then return 0 end
  local v = 0
  if b.leechSeeded then v = v + 0x4 end
  if b.perishTurns then v = v + 0x20 end
  if b.ingrained then v = v + 0x400 end
  -- IMPRISON, MUD SPORT and WATER SPORT have no model in this engine, so
  -- their bits never set.  That is not a gap in the reading: the AI is
  -- scoring the battle this engine runs, and in it those moves do nothing, so
  -- a script that declines to repeat one is declining something that never
  -- happened.
  return v
end

local function sideStatus(vm, b)
  if not b then return 0 end
  local v = 0
  local battle = vm.battle
  local side = battle.sides and battle.sides[b.isPlayer and 1 or 2]
  -- the screens are per-battler here and per-side on the cartridge, so both
  -- flanks are asked and the answers joined
  for _, slot in pairs((side and side.battlers) or { b }) do
    if slot then
      if slot.reflect then v = v % 0x2 == 1 and v or v + 0x1 end
      if slot.lightScreen and v % 0x4 < 0x2 then v = v + 0x2 end
      if slot.safeguardTurns and v % 0x40 < 0x20 then v = v + 0x20 end
      if slot.mist and v % 0x200 < 0x100 then v = v + 0x100 end
    end
  end
  if side and side.spikes and v % 0x20 < 0x10 then v = v + 0x10 end
  if side and side.futureSight and v % 0x80 < 0x40 then v = v + 0x40 end
  return v
end

local function masked(value, mask)
  -- a plain bitwise AND, written for 5.1: both sides are read bit by bit so
  -- the 32-bit STATUS2 masks survive without the bit library
  local bit = 1
  while bit <= mask and bit <= 0x80000000 do
    if mask % (bit + bit) >= bit and value % (bit + bit) >= bit then
      return true
    end
    bit = bit * 2
  end
  return false
end
Gen3AI.masked = masked

local function statusTest(read)
  return function(vm, args)
    if masked(read(vm, who(vm, args[1])), args[2]) then return args[#args] end
  end
end

local function statusNotTest(read)
  return function(vm, args)
    if not masked(read(vm, who(vm, args[1])), args[2]) then
      return args[#args]
    end
  end
end

local function s1(_, b) return status1(b) end
local function s2(_, b) return status2(b) end
local function s3(_, b) return status3(b) end

OPS["if_status"] = statusTest(s1)
OPS["if_not_status"] = statusNotTest(s1)
OPS["if_status2"] = statusTest(s2)
OPS["if_not_status2"] = statusNotTest(s2)
OPS["if_status3"] = statusTest(s3)
OPS["if_not_status3"] = statusNotTest(s3)
OPS["if_side_affecting"] = statusTest(sideStatus)
OPS["if_not_side_affecting"] = statusNotTest(sideStatus)

-- ------- the rest

OPS["if_move"] = function(vm, args)
  if (vm.moveNumber or 0) == args[1] then return args[#args] end
end

OPS["if_not_move"] = function(vm, args)
  if (vm.moveNumber or 0) ~= args[1] then return args[#args] end
end

-- which == 0 asks about DISABLE, 1 about ENCORE
OPS["if_any_move_disabled_or_encored"] = function(vm, args)
  local b = who(vm, args[1])
  if not b then return end
  local hit = (args[2] == 0) and b.disabledSlot ~= nil
              or (args[2] == 1) and b.encoreTurns ~= nil
  if hit then return args[#args] end
end

OPS["if_curr_move_disabled_or_encored"] = function(vm, args)
  local b = vm.user
  local hit = (args[1] == 0) and b and b.disabledSlot == vm.moveIndex
              or (args[1] == 1) and b and b.encoreTurns ~= nil
  if hit then return args[#args] end
end

-- 0 is "the user's level is higher", 1 "lower", 2 "the same" -- the three
-- arms of the handler's switch, read off its `bhi` / `bcc` / `beq`.
OPS["if_level_cond"] = function(vm, args)
  local a = vm.user and vm.user.mon and tonumber(vm.user.mon.level) or 0
  local b = vm.target and vm.target.mon and tonumber(vm.target.mon.level) or 0
  local cond = tonumber(args[1]) or 0
  local hit = (cond == 0 and a > b) or (cond == 1 and a < b)
              or (cond == 2 and a == b)
  if hit then return args[#args] end
end

-- ---------------------------------------------------------------------------
-- Running one script over one move
-- ---------------------------------------------------------------------------

require("src.battle.Gen3AIPartyStatus").install(Gen3AI)

-- Every opcode a script can reach, followed through its branches.  Memoised
-- on the program table: the answer depends only on the cartridge.
function Gen3AI.reachable(program, entry)
  program._reach = program._reach or {}
  local memo = program._reach[entry]
  if memo then return memo end
  local names, seen, stack = {}, {}, { entry }
  while #stack > 0 do
    local pc = table.remove(stack)
    while pc and not seen[pc] do
      seen[pc] = true
      local row = program.code and program.code[pc]
      if not row then break end
      names[row.name] = true
      local dest = row.args and row.args[#row.args]
      if dest and program.code[dest] then stack[#stack + 1] = dest end
      if row.name == "end" or row.name == "goto" or row.name == "flee"
         or row.name == "watch" then
        pc = nil
      else
        pc = row.next
      end
    end
  end
  program._reach[entry] = names
  return names
end

function Gen3AI.runs(program, entry)
  if not (program and entry and program.code and program.code[entry]) then
    return false
  end
  program._runs = program._runs or {}
  local memo = program._runs[entry]
  if memo ~= nil then return memo end
  local ok = true
  for name in pairs(Gen3AI.reachable(program, entry)) do
    if not OPS[name] then ok = false end
  end
  program._runs[entry] = ok
  return ok
end

-- Which of the ten named scripts this file can currently run.  A number the
-- tests read, rather than a sentence in a comment that drifts.
Gen3AI.SCRIPT_NAMES = {
  [0] = "AI_CheckBadMove", "AI_TryToFaint", "AI_CheckViability",
  "AI_SetupFirstTurn", "AI_Risky", "AI_PreferStrongestMove",
  "AI_PreferBatonPass", "AI_DoubleBattle", "AI_HPAware",
  "AI_TrySunnyDayStart",
}

function Gen3AI.coverage(program)
  local out = {}
  for bit = 0, 31 do
    local entry = program and program.entries and program.entries[bit]
    if entry then
      out[bit] = { name = Gen3AI.SCRIPT_NAMES[bit], entry = entry,
                   runs = Gen3AI.runs(program, entry) }
    end
  end
  return out
end

local function runScript(vm, entry)
  local pc, steps = entry, 0
  while pc do
    steps = steps + 1
    if steps > Gen3AI.STEP_CAP then return false end
    local row = vm.program.code[pc]
    if not row then return false end
    local fn = OPS[row.name]
    if not fn then return false end
    local to = fn(vm, row.args, row.next)
    if to == false then return true end
    pc = to or row.next
  end
  return true
end

-- ---------------------------------------------------------------------------
-- The choice
-- ---------------------------------------------------------------------------

function Gen3AI.program(battle)
  local c = battle and battle.data and battle.data.constants
  local p = c and c.gen3BattleAI
  if type(p) == "table" and type(p.code) == "table"
     and type(p.entries) == "table" then
    return p
  end
  return nil
end

-- The score for each usable move, or nil when there is nothing to run: no
-- program, no trainer, no flags, or every script the flags name is one this
-- file cannot run yet.  nil means "no opinion", and the caller keeps whatever
-- it was doing.
function Gen3AI.scoreMoves(battle, user, target, moves)
  local program = Gen3AI.program(battle)
  local trainer = battle and battle.trainer
  local flags = trainer and tonumber(trainer.aiFlags)
  if not (program and flags and flags > 0 and moves and moves[1]) then
    return nil
  end
  local data = battle.data or {}
  local score, ran = {}, false
  for i = 1, #moves do score[i] = Gen3AI.START_SCORE end

  local vm = {
    battle = battle, user = user, target = target, program = program,
    score = score, stack = {}, moves = moves,
    rng = battle.rng or function(a, b) return a end,
  }

  for bit = 0, 31 do
    if math.floor(flags / 2 ^ bit) % 2 == 1 then
      local entry = program.entries[bit]
      if entry and Gen3AI.runs(program, entry) then
        for i = 1, #moves do
          local def = data.moves and data.moves[moves[i].id]
          vm.moveIndex = i
          vm.moveEffect = def and tonumber(def.gen3Effect) or 0
          vm.moveNumber = def and tonumber(def.index) or 0
          vm.result = 0
          vm.stack = {}
          if runScript(vm, entry) then ran = true end
        end
      end
    end
  end
  if not ran then return nil end
  return score
end

-- ChooseMoveOrAction_Doubles: the same scoring, once per battler it could aim
-- at, and the winner is a PAIR.  This is the half that decides which of your
-- two a foe goes for, and until it existed the answer was position order and
-- then a coin flip.
--
-- Only the opposing side is offered here.  The cartridge also scores the
-- user's own partner as a target, and every script's `if_target_is_ally`
-- prologue then returns immediately -- so an ally pair sits at the opening
-- 100 and can win a tie against foes that nothing has scored yet.  That is
-- survivable on hardware because CheckBadMove has already pushed the bad
-- foe-facing moves below 100 by then; with that script not yet running it
-- would just be a foe hitting its partner for no reason.  The arm comes back
-- with the move's own target byte, which is what says a move can hit an ally
-- at all.
--
-- Returns move, target -- or nil when the whole board came out flat, which is
-- the same "no opinion" the singles answer gives.
function Gen3AI.chooseAction(battle, user, moves, foes)
  if not (moves and moves[1] and foes and foes[1]) then return nil end
  local best, tied, pairs_ = nil, {}, 0
  for _, foe in ipairs(foes) do
    local score = Gen3AI.scoreMoves(battle, user, foe, moves)
    if score then
      for i = 1, #moves do
        pairs_ = pairs_ + 1
        if best == nil or score[i] > best then
          best, tied = score[i], { { moves[i], foe } }
        elseif score[i] == best then
          tied[#tied + 1] = { moves[i], foe }
        end
      end
    end
  end
  if not best or #tied == 0 then return nil end
  -- every pair level with every other is no opinion at all
  if #tied >= pairs_ then return nil end
  local pick = tied[1]
  if #tied > 1 and battle.rng then pick = tied[battle.rng(1, #tied)] end
  return pick[1], pick[2]
end

-- ChooseMoveOrAction_Singles: the highest score wins and a tie is a uniform
-- roll among the tied moves.  Returns the chosen move, or nil for "no
-- opinion" -- including when every score came out equal, because that is the
-- answer the caller already has and going through a second roll here would
-- only spend a different random number on it.
function Gen3AI.chooseMove(battle, user, target, moves)
  local score = Gen3AI.scoreMoves(battle, user, target, moves)
  if not score then return nil end
  local best, spread = score[1], false
  for i = 2, #moves do
    if score[i] ~= best then spread = true end
    if score[i] > best then best = score[i] end
  end
  if not spread then return nil end
  local tied = {}
  for i = 1, #moves do
    if score[i] == best then tied[#tied + 1] = moves[i] end
  end
  if #tied == 1 then return tied[1] end
  local rng = battle.rng
  return rng and tied[rng(1, #tied)] or tied[1]
end

return Gen3AI
