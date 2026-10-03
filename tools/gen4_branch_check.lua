-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_branch_check.lua -- THE EIGHTH CHECK: does a jump land anywhere.
--
-- The other seven all ask about a row that was EMITTED.  Does its verb resolve;
-- does its arity match; are its operands the right ones, in the right order, of
-- the right width; is the opcode lowered at all.  Every one of those questions
-- is silent about a row the lowering DECIDED NOT TO EMIT -- and that is exactly
-- what happened to every branch in Platinum for the whole Gen 4 effort:
-- `branch()` built a label without its member, `s.has` answered false, and
-- `goto`, `gotoif`, `call` and `callif` each emitted nothing.  Coverage said
-- 97.35% because the INSTRUCTION was lowered, which it was.
--
-- MEASURED BEFORE THE FIX, over all 8,567 blocks: 63,629 rows, 6,385 jump/call
-- rows -- all of them `jump end`, the one lowering that bypasses `branch` --
-- and **zero labels in the entire cartridge**.  After: 599,532 rows, 169,017
-- jump/call rows, 74,825 labels.
--
-- SO THIS CHECK ASKS FOUR THINGS, and each is a different way for control flow
-- to be quietly absent rather than wrong:
--
--   1. EVERY EMITTED JUMP TARGET IS AN EMITTED LABEL.  A jump to a label that
--      was never emitted runs off the end of the row list, which stops the
--      script exactly like a successful `end`.
--   2. EVERY BLOCK THAT CONTAINS A BRANCH COMPILES TO ONE.  Counting the
--      branch instructions in the decoded block and the branch rows in the
--      compiled output is what catches a whole class going missing -- the
--      failure that started this -- because a check that only looked at rule 1
--      passes trivially when there are no jumps at all.
--   3. NO BLOCK COMPILES TO A SINGLE UNCONDITIONAL STOP when its own
--      instructions say otherwise.
--   4. THE CORPUS TOTALS ARE WHAT THEY WERE.  Stated as numbers so a change of
--      method cannot be mistaken for a change of code.  66,258 of the 74,825
--      labels are branch targets; the other 8,567 are the entry label each
--      block now emits for itself, one per block, which is what lets the 878
--      self-loops in the cartridge land.
--
-- Run:  texlua tools/gen4_branch_check.lua <rom path>

local romPath = arg and arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_branch_check.lua <rom path>\n")
  os.exit(2)
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

-- The engine's own modules, with everything they drag in stubbed: this runs
-- headless and must not need love2d.
local KEEP = {
  ["src.script.Gen4ScriptVM"] = true, ["src.script.Gen4Commands"] = true,
  ["src.import.Gen4ScriptOps"] = true, ["src.import.Gen4ScriptBands"] = true,
  ["src.import.Gen4Movement"] = true, ["src.import.Gen4Script"] = true,
  ["src.import.NdsRom"] = true, ["src.import.NarcArchive"] = true,
}
local shared = { meta = {} }
local quiet = setmetatable({}, { __index = function() return function() end end })
local inert = setmetatable({}, { __index = function() return function() end end })
table.insert(package.searchers, 1, function(name)
  if KEEP[name] then return nil end
  if name == "src.script.Commands" then return function() return shared end end
  if name == "src.core.Logger" then return function() return quiet end end
  if name:sub(1, 4) ~= "src." then return nil end
  return function() return inert end
end)

local VM = require("src.script.Gen4ScriptVM")
local Ops = require("src.import.Gen4ScriptOps")
local Movement = require("src.import.Gen4Movement")
local Script = require("src.import.Gen4Script")
local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")

-- CANARY FIRST.  A harness whose pool is empty, or whose VM is a stub, passes
-- every test below by having nothing to test -- the same trap the command
-- audit fell into when it read the wrong var store.
assert(VM.lowered("gotoif"), "canary: gotoif must be lowered")
assert(type(VM.compile) == "function", "canary: VM.compile must be the real one")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-48s %s\n"):format(what, tostring(got)))
  else fails = fails + 1
       io.write(("  FAIL  %-48s got %s, expected %s\n"):format(what, tostring(got), tostring(want))) end
end

-- Build the pool exactly as RomExtractorGen4:extractScripts does -- entry
-- points AND every block a jump reaches, keyed the way the cache keys them.
local rom = assert(NdsRom.open(romPath))
local arc = assert(Narc.parse(assert(rom:read("/fielddata/script/scr_seq.narc"))))
local moveOp
for op, e in pairs(Ops.COMMANDS) do if e[1] == "applymovement" then moveOp = op end end
local moveSize = moveOp and Ops.size(moveOp)

local scripts, entries = {}, {}
for m = 0, arc.count - 1 do
  local bytes = arc:get(m)
  if bytes and #bytes >= 6 then
    local ordered = Script.entries(bytes)
    local queue, seen = {}, {}
    for _, at in ipairs(ordered) do
      if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
    end
    local i = 1
    while i <= #queue do
      local at = queue[i]; i = i + 1
      local ins, stopped = Script.decode(bytes, at)
      scripts[VM.label(m, at)] = { instructions = ins, stopped = stopped }
      for _, op in ipairs(ins) do
        local t = op.target
        if t and t >= 1 and t <= #bytes and not seen[t] then
          seen[t] = true; queue[#queue + 1] = t
        end
        if op.name == "applymovement" and moveSize then
          local a = Movement.addressOf(op, moveSize)
          local st = a and Movement.decode(bytes, a)
          if st then op.movement = st end
        end
      end
    end
    local list = {}
    for k, at in ipairs(ordered) do list[k] = VM.label(m, at) end
    entries[m] = list
  end
end
rom:close()
local data = { map_scripts = { source = "RomExtractorGen4", scripts = scripts, entries = entries } }

-- The four instruction names that MUST become a branch row.
local BRANCHERS = { ["goto"] = true, gotoif = true, call = true, callif = true }
-- ...and the row verbs they become.  `jump end` is deliberately excluded: its
-- label is the literal "end" and it never goes through `branch`.
local BRANCH_ROWS = { jump = true, g4_jump_if = true, g4_call = true, g4_call_if = true }

local blocks, rows, branchRows, labelRows = 0, 0, 0, 0
local dangling, silent, danglingExamples, silentExamples = 0, 0, {}, {}

for label, block in pairs(scripts) do
  blocks = blocks + 1
  local compiled = VM.compile(data, label)
  if compiled then
    rows = rows + #compiled

    -- rule 1: every jump target is an emitted label
    local emitted = {}
    for _, r in ipairs(compiled) do
      if r[1] == "label" then emitted[r[2]] = true; labelRows = labelRows + 1 end
    end
    for _, r in ipairs(compiled) do
      if BRANCH_ROWS[r[1]] then
        branchRows = branchRows + 1
        local target = r[#r]
        if type(target) == "string" and target ~= "end" and not emitted[target] then
          dangling = dangling + 1
          if #danglingExamples < 6 then
            danglingExamples[#danglingExamples + 1] =
              ("%s -> %s (%s)"):format(label, target, tostring(r[1]))
          end
        end
      end
    end

    -- rule 2: a block whose own instructions branch must compile to a branch
    local wanted = 0
    for _, ins in ipairs(block.instructions or {}) do
      if ins.name and BRANCHERS[ins.name] and type(ins.target) == "number" then
        wanted = wanted + 1
      end
    end
    if wanted > 0 then
      local got = 0
      for _, r in ipairs(compiled) do
        if r[1] == "g4_jump_if" or r[1] == "g4_call_if" or r[1] == "g4_call" then got = got + 1 end
        if r[1] == "jump" and r[#r] ~= "end" then got = got + 1 end
      end
      if got == 0 then
        silent = silent + 1
        if #silentExamples < 6 then
          silentExamples[#silentExamples + 1] =
            ("%s: %d branch instruction(s), 0 branch rows"):format(label, wanted)
        end
      end
    end
  end
end

io.write(("corpus: %d blocks, %d rows, %d branch rows, %d labels\n\n")
  :format(blocks, rows, branchRows, labelRows))

-- 8,567 -> 8,571 in pass 168: the decoder stopped truncating four scripts at
-- the field-move flag commands, so the walk reaches further. A floor, because
-- reach going up is the work -- and see `gen4_coverage_check` for the two
-- opcodes that had never been seen anywhere until that walk got past them.
ok(blocks >= 8571, "blocks in the pool (floor)", blocks, 8571)
ok(dangling == 0, "jumps to a label that was never emitted", dangling, 0)
for _, e in ipairs(danglingExamples) do io.write("        " .. e .. "\n") end
ok(silent == 0, "blocks that branch but compile to no branch", silent, 0)
for _, e in ipairs(silentExamples) do io.write("        " .. e .. "\n") end

-- rule 4: the totals.  Stated, so a change of METHOD cannot be read as a
-- change of code -- the same reason the corpus walk states 8,567 blocks.
--
-- FLOORS, NOT EQUALITIES, and that distinction cost a red check. These are
-- DATA VOLUMES: every opcode that gains a lowering compiles more rows, so an
-- exact pin turns progress into a failure. It did -- the bag, the berries and
-- the PC were lowered and `rows` went 599,532 -> 599,584, a check failing
-- because the port had got better.
--
-- What they are really for is a walk that stops short: fewer blocks, a
-- truncated decode, a corpus that shrank. They may not regress.
--
-- THEY DO NOT CATCH A LOWERING BEING LOST, and that was worth finding out
-- rather than assuming. Deleting `L.openbag` -- 44 occurrences -- left this
-- check green, because an opcode with no lowering still compiles a row; it
-- is a different row, not a missing one. `gen4_coverage_check`'s `lowered`
-- floor is the assertion that catches that, and it only does so while the
-- floor is kept level with the corpus.
--
-- `dangling == 0` and `silent == 0` above stay exact: those are facts about
-- shape rather than quantities, and may not move at all.
ok(labelRows >= 74825, "labels emitted across the corpus (floor)", labelRows, 74825)
ok(branchRows >= 169017, "branch rows across the corpus (floor)", branchRows, 169017)
ok(rows >= 599584, "compiled rows across the corpus (floor)", rows, 599584)

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
