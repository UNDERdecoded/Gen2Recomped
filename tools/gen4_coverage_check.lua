-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_coverage_check.lua -- THE FIRST CHECK, FINALLY RERUNNABLE.
--
-- The standing list of checks on the Gen 4 script pipeline opened with "chapter
-- walks -- is the opcode lowered at all", and that entry was the only one of
-- the eight with NO TOOL BEHIND IT.  The 97.35% figure every other measurement
-- was quoted against lived in notes, produced by throwaway probes that no
-- longer exist, on a machine that is not this one.  A NUMBER YOU CANNOT
-- RECOMPUTE IS A NUMBER YOU ARE TRUSTING, NOT MEASURING -- which is the same
-- fault the command audit was caught for when it turned out to be grading a
-- stale copy of the module.  So: one file, one command, the number out loud.
--
-- It also answers the question the percentage hides.  97.35% of INSTRUCTIONS
-- are lowered, but only 322 of the 718 distinct opcodes that occur are -- the
-- coverage is high because the common opcodes are the lowered ones, and the
-- remaining 396 are a long tail whose median occurrence count is 1.  Ranking
-- that tail by how often it actually occurs is the useful output here, because
-- it separates the work that shows up in play from the work that does not:
-- `callbattletowerfunction` x146 is one side system behind one door, while
-- `openbag` x44 and `checkpockethasitems` x72 are main-game scenes.
--
-- SIX CHECKS, and the fifth is the one that earns the file: coverage may not
-- REGRESS.  Recorded floors, measured here:
--
--     blocks in the pool                8,567
--     instructions walked              78,093
--     instructions lowered             76,587   = 98.07%
--
-- THE TWO FLOORS ARE NOT THE SAME NUMBER TWICE, and raising them together
-- is a trap this walked into once: the percentage printed is ROUNDED and the
-- one compared is not. 76,170 / 78,093 is 97.5381%, which prints as "97.54"
-- and is BELOW a 97.54 floor. Raise the instruction floor -- it is exact --
-- and move the percentage only when its unrounded value clears the next step.
--     distinct opcodes occurring          718
--     of those, lowered                   329
--     blocks whose decode stopped early     0
--
-- The lowered figure moved by FIVE when `openpokemonnamingscreen` was lowered,
-- and those five are the whole of the nickname prompt in Sinnoh -- Sandgem
-- Town, Eterna's Name Rater, the Mining Museum's fossil, Hearthome, Veilstone.
-- Worth naming because five instructions out of 78,093 is a rounding error in
-- the percentage and a whole feature in the game: THE PERCENTAGE IS NOT THE
-- MEASURE OF ANYTHING A PLAYER MEETS.
--
-- That same five-instruction move is what caught tools/gen4_seam_check.lua
-- grading a snapshot instead of the tree: this file's number changed and that
-- one's did not.
--
-- The next 39 are the FOUR IN-GAME TRADES -- five commands on four maps, one
-- of them Oreburgh City. Same lesson, louder: thirty-nine instructions is five
-- hundredths of a percent and four whole conversations that did nothing.
--
-- The last of those is not a formality.  The decoder STOPS rather than guess at
-- an opcode it has marked variable-length, and a block cut short still reports
-- every instruction before the cut as decoded -- so a rise in that number is a
-- silent loss of corpus, and it must stay at zero for the other five figures to
-- mean what they say.
--
-- Run:  texlua tools/gen4_coverage_check.lua <rom path>

local romPath = arg and arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_coverage_check.lua <rom path>\n")
  os.exit(2)
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

-- The engine's own modules, with everything they drag in stubbed: this runs
-- headless and must not need love2d.  `src.script.Commands` has to be a REAL
-- table with a `meta` field -- Gen4Commands writes into it at load time, and an
-- inert metatable-only stub swallows those writes and leaves VM.lowered lying.
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
local Script = require("src.import.Gen4Script")
local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")

-- CANARY FIRST, BOTH WAYS.  A `lowered` that answered true for everything would
-- report 100% and a `lowered` that answered false for everything would report
-- 0%, and both would run to completion without erroring.  Asserting only the
-- true side is the mistake the command audit made: it proved it could see a var
-- write and never proved it could see the absence of one.
assert(VM.lowered("gotoif"), "canary: gotoif must be lowered")
assert(not VM.lowered("gen2recomped_no_such_command"),
       "canary: VM.lowered must be able to answer NO")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-48s %s\n"):format(what, tostring(got)))
  else fails = fails + 1
       io.write(("  FAIL  %-48s got %s, expected %s\n")
                :format(what, tostring(got), tostring(want))) end
end

-- Walk the pool exactly as RomExtractorGen4:extractScripts builds it: every
-- entry point, plus every block a jump reaches.  Reachability matters to the
-- figure -- counting bytes in the NARC instead would inflate the denominator
-- with data the game never runs.
local rom = assert(NdsRom.open(romPath))
local arc = assert(Narc.parse(assert(rom:read("/fielddata/script/scr_seq.narc"))))

local blocks, stoppedEarly, total, lowered = 0, 0, 0, 0
local occurs, missing = {}, {}

for m = 0, arc.count - 1 do
  local bytes = arc:get(m)
  if bytes and #bytes >= 6 then
    local queue, seen = {}, {}
    for _, at in ipairs(Script.entries(bytes)) do
      if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
    end
    local i = 1
    while i <= #queue do
      local at = queue[i]; i = i + 1
      local ins, stopped = Script.decode(bytes, at)
      blocks = blocks + 1
      if not stopped then stoppedEarly = stoppedEarly + 1 end
      for _, op in ipairs(ins) do
        total = total + 1
        local name = op.name or ("?%03X"):format(op.op or 0)
        occurs[name] = (occurs[name] or 0) + 1
        if VM.lowered(name) then lowered = lowered + 1
        else missing[name] = (missing[name] or 0) + 1 end
        local t = op.target
        if t and t >= 1 and t <= #bytes and not seen[t] then
          seen[t] = true; queue[#queue + 1] = t
        end
      end
    end
  end
end
rom:close()

local distinct, absent = 0, 0
for _ in pairs(occurs) do distinct = distinct + 1 end
local ranked = {}
for name, n in pairs(missing) do
  absent = absent + 1
  ranked[#ranked + 1] = { name = name, n = n }
end
table.sort(ranked, function(a, b)
  if a.n ~= b.n then return a.n > b.n end
  return a.name < b.name
end)

local pct = total > 0 and (100 * lowered / total) or 0

io.write(("\ncorpus: %d blocks, %d instructions, %d lowered (%.2f%%)\n")
         :format(blocks, total, lowered, pct))
io.write(("opcodes: %d distinct occur, %d lowered, %d NOT\n\n")
         :format(distinct, distinct - absent, absent))

io.write("the unlowered tail, ranked by how often it actually occurs --\n")
io.write("this is the work queue, and the count is the argument for order:\n")
local shown, tailOnes = 0, 0
for _, e in ipairs(ranked) do
  if e.n == 1 then tailOnes = tailOnes + 1 end
  if shown < 24 then
    shown = shown + 1
    io.write(("   %-46s x%d\n"):format(e.name, e.n))
  end
end
io.write(("   ... and %d more, of which %d occur exactly once\n\n")
         :format(math.max(0, absent - shown), tailOnes))

-- Recorded floors.  Measured, not aspirational: these are what the corpus reads
-- today, so any future edit that drops a lowering or shortens a decode fails
-- here instead of quietly lowering the number everything else is quoted against.
-- THESE THREE MOVED IN PASS 168, UPWARD, AND THEY ARE FLOORS NOW.
--
-- `Gen4ScriptOps.VARIABLE_SPEC` taught the decoder the width rule for the
-- three field-move flag commands, which it used to stop the walk at. Stopping
-- truncates the script, so four scripts were ending early -- and everything
-- after the stop had never been decoded in the whole history of this corpus.
--
--     blocks in the pool            8,567 -> 8,571    (+4)
--     instructions walked          78,093 -> 78,189   (+96)
--     distinct opcodes seen           718 -> 720      (+2)
--     coverage                      98.06% -> 98.15%
--
-- THE +2 IS THE ONE WORTH READING. The two opcodes that appeared are 0x0C3
-- (x2) and 0x0C4 (x1) -- the weather-clears that Flash and Defog call -- and
-- they sit on the line directly after `DoFlashFunc` / `DoDefogFunc`. They had
-- therefore never been seen ANYWHERE in the cartridge, not once, because the
-- only places they occur are past a truncation point. A corpus census cannot
-- report what its walk never reaches, and that is the shape of blindness this
-- comment exists to record.
--
-- Verified by reverting the decoder change and re-running the same corpus:
-- 8 variable stops become 4, and the two opcodes disappear again.
--
-- Floors rather than exact pins because reach going UP is the work. A fall
-- means the decoder lost ground, which is what these are for.
ok(blocks >= 8571, "blocks in the pool (floor)", blocks, 8571)
ok(total >= 78189, "instructions walked (floor)", total, 78189)
ok(stoppedEarly == 0, "blocks whose decode stopped early", stoppedEarly, 0)
ok(distinct >= 720, "distinct opcodes occurring in the corpus (floor)", distinct, 720)
-- THE FLOOR HAS TO BE RAISED WHEN IT IS PASSED, or it stops protecting
-- anything. It sat at 76,178 while the real figure had reached 76,587 --
-- 409 instructions of slack -- and a floor with slack in it does not notice
-- a lowering being lost. Measured: deleting `L.openbag`, which lowers 44
-- occurrences, left this check GREEN, and so did every other check in the
-- tree. Raised to what the corpus actually reads, the same deletion fails
-- here, which is the only place it can.
--
-- So this number is not decoration and not a record of a past run: it is
-- the one assertion standing between a deleted lowering and nobody
-- noticing. Raise it whenever it is beaten.
-- RAISED AGAIN IN PASS 168, and raising it is not bookkeeping. Pass 166 found
-- this floor sitting 409 instructions below the corpus, which meant up to 409
-- instructions of lowering could be deleted with every check in the tree
-- staying green -- and proved it by deleting `L.openbag`. Leaving it at 76,587
-- after this pass would re-open a 153-instruction gap of exactly the same
-- kind. A floor is only worth what it is level with.
-- 76,740 -> 76,781 in pass 169 (the item bands, `messagefrombank` and the
-- word-choice screen). Re-levelled again rather than left with 41 instructions
-- of slack, for the reason in the paragraph above: the gap is the whole fault.
-- 76,781 -> 76,785 in pass 170 (survivepoison, hatchegg, blackoutfrombattle2):
-- three commands, four instructions, because two of them occur once each in
-- the whole cartridge. Read off the run rather than predicted -- the first
-- attempt at this line guessed 76,788 and the check rejected it.
ok(lowered >= 76785, "instructions lowered (floor, may not regress)",
   lowered, ">= 76785")
-- COMPARED ON THE NUMBER IT PRINTS, which it was not, and this check caught
-- me with it on a clean tree: the true figure is 98.1468%, the line printed
-- "98.15", I pinned `pct >= 98.15` off the printed value, and the check failed
-- saying "got 98.15, expected >= 98.15". A check whose message contradicts its
-- own verdict is worse than no check -- the reader believes the message.
--
-- The floor on `lowered` above is the one with teeth (it bites on a single
-- instruction); this is the human-readable twin, so it compares the same
-- rounded value it shows.
local shown = tonumber(("%.2f"):format(pct))
ok(shown >= 98.20, "corpus coverage %", ("%.2f"):format(pct), ">= 98.20")

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
