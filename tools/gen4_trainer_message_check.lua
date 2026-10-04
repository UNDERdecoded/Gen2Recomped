-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHETHER A TRAINER CAN SAY ANYTHING.
--
-- `scripts_battles.s` is the one field script every trainer battle in Platinum
-- goes through, and three of its commands were not lowered:
--
--     OpenMessage                                    <- not lowered
--     GetTrainerMessageTypes VAR_0x8000, ..., ...    <- not lowered
--     PrintTrainerDialogue VAR_0x8004, VAR_0x8000    <- not lowered
--
-- so all three took the unknown-command path -- logged, stepped over -- and the
-- battle began on the next line.  Every trainer in Sinnoh fought in silence.
--
-- That is a 35-invocation hole in a 136-command file, which sounds small and is
-- not: THIS script is shared by all 417 trainers in the region, so its command
-- list is worth more per line than any map script in the game.  Ranking the
-- cartridge's unlowered opcodes by raw invocation count puts
-- `callbattletowerfunction` (121 uses, every one of them inside the Battle
-- Tower) far above it -- which is exactly the wrong answer, and the reason
-- section 6 measures this one file rather than a share of a total.
--
-- WHAT THIS CHECKS, in four independent directions:
--
--   * the walk itself, against a synthetic table built to the cartridge's
--     shape -- so this check has something that can fail with no cache, no
--     cartridge and no pokeplatinum present;
--   * the cache, whose trainer count, pair count and text-bank join are three
--     readings that must agree;
--   * the wiring, because a lowering that emits a row no handler answers is
--     this port's most repeated fault;
--   * `scripts_battles.s` end to end, when pokeplatinum is given: every macro
--     in the file must be a command this engine lowers.
--
-- Run:  texlua tools/gen4_trainer_message_check.lua <cache dir> [pokeplatinum dir]
--
-- Exits 2 when it could not run at all, 1 on a failure, 0 when clean.  A cache
-- with no `gen4_trainer_messages.lua` is REPORTED and not failed: the table
-- arrives with the next re-import, and a check that failed on its absence
-- would be red for a reason nobody can act on from here.

package.path = "./?.lua;" .. package.path

love = love or {
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = { getWidth = function() return 256 end, getHeight = function() return 192 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local CACHE = arg and arg[1]
local PP = arg and arg[2]
if not CACHE then
  io.write("usage: texlua tools/gen4_trainer_message_check.lua "
           .. "<cache dir> [pokeplatinum dir]\n")
  os.exit(2)
end

local fails, checks, reports = 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

local M = require("src.import.Gen4TrainerMessages")

-- ---------------------------------------------------------------------------
section("1. the enum, and the jump at the end of it")
-- The twenty dense types plus WIN at 100.  Spelled as explicit indices in the
-- module because an array constructor would renumber WIN to 20, and a reader
-- that believed 20 would hand out the wrong string for the one type the field
-- table never contains -- i.e. it would be wrong only inside the battle system.
ok(M.TYPES[0] == "pre_battle", "type 0 is %s, expected pre_battle",
   tostring(M.TYPES[0]))
ok(M.TYPES[17] == "rematch", "type 17 is %s, expected rematch",
   tostring(M.TYPES[17]))
ok(M.TYPES[19] == "double_battle_rematch_2",
   "type 19 is %s, expected double_battle_rematch_2", tostring(M.TYPES[19]))
ok(M.TYPES[20] == nil,
   "type 20 exists (%s); the cartridge enum jumps from 19 to 100 and a dense "
   .. "reading of it renumbers WIN", tostring(M.TYPES[20]))
ok(M.TYPES[100] == "win", "type 100 is %s, expected win", tostring(M.TYPES[100]))
local typeCount = 0
for _ in pairs(M.TYPES) do typeCount = typeCount + 1 end
ok(typeCount == 21, "%d message types, expected 21 (20 dense + WIN)", typeCount)
ok(M.TYPE_IDS.rematch == 17, "TYPE_IDS disagrees with TYPES on rematch")
ok(M.BANK == 617,
   "the message bank is %s; 617 is the lines, 618 the trainer NAMES and 619 the "
   .. "class names, so off-by-one here renders names as dialogue", tostring(M.BANK))
ok(M.TABLE_PATH == "/poketool/trmsg/trtbl.narc", "table path is %s", M.TABLE_PATH)
ok(M.OFFSET_PATH == "/poketool/trmsg/trtblofs.narc", "offset path is %s",
   M.OFFSET_PATH)
ok(M.RECORD_BYTES == 4, "record stride is %s, expected 4", tostring(M.RECORD_BYTES))

-- ---------------------------------------------------------------------------
section("2. the walk, on a synthetic table built to the cartridge's shape")
-- Six records in three runs, with the SAME ARRANGEMENT that makes the real
-- table dangerous: record 0 belongs to a trainer that is not trainer 0, and
-- several trainers have offset 0 meaning "no messages" rather than "start at
-- the beginning".  On the cartridge 92 of 928 trainers are in that position.
local function u16le(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function rec(t, mt) return u16le(t) .. u16le(mt) end
-- trainer 7: types 0,1,2 at records 0,1,2;  trainer 3: type 17 at record 3;
-- trainer 9: types 0,1 at records 4,5.
local TBL = rec(7,0) .. rec(7,1) .. rec(7,2) .. rec(3,17) .. rec(9,0) .. rec(9,1)
local OFS = u16le(0) .. u16le(0) .. u16le(0) .. u16le(12) .. u16le(0)
          .. u16le(0) .. u16le(0) .. u16le(0) .. u16le(0) .. u16le(16)
ok(M.recordCount(TBL) == 6, "synthetic table has %d records, expected 6",
   M.recordCount(TBL))
ok(M.trainerCount(OFS) == 10, "synthetic offsets cover %d trainers, expected 10",
   M.trainerCount(OFS))
ok(M.find(TBL, OFS, 7, 0) == 0, "trainer 7 type 0 -> %s, expected 0",
   tostring(M.find(TBL, OFS, 7, 0)))
ok(M.find(TBL, OFS, 7, 2) == 2, "trainer 7 type 2 -> %s, expected 2",
   tostring(M.find(TBL, OFS, 7, 2)))
ok(M.find(TBL, OFS, 3, 17) == 3, "trainer 3 type 17 -> %s, expected 3",
   tostring(M.find(TBL, OFS, 3, 17)))
ok(M.find(TBL, OFS, 9, 1) == 5, "trainer 9 type 1 -> %s, expected 5",
   tostring(M.find(TBL, OFS, 9, 1)))
-- THE ONE THAT MATTERS.  Trainer 0 has offset 0 and no run of its own; record 0
-- belongs to trainer 7.  Without the `t ~= trainerId` guard this returns 0 and
-- TRAINER_NONE speaks trainer 7's challenge.  Removing that guard on the real
-- tables takes "trainers with messages" from 836 to 928 and the pair count from
-- 2,497 to 13,765, which is how the guard was proved load-bearing.
ok(M.find(TBL, OFS, 0, 0) == nil,
   "trainer 0 found type 0 at entry %s; offset 0 must mean no messages, not "
   .. "start of table", tostring(M.find(TBL, OFS, 0, 0)))
ok(M.forTrainer(TBL, OFS, 0) == nil, "trainer 0 has a message row and must not")
ok(M.forTrainer(TBL, OFS, 5) == nil, "trainer 5 has a message row and must not")
-- A run does not bleed into the next trainer's.
ok(M.find(TBL, OFS, 7, 17) == nil,
   "trainer 7 picked up type 17 at %s, which belongs to trainer 3",
   tostring(M.find(TBL, OFS, 7, 17)))
ok(M.find(TBL, OFS, 9, 2) == nil,
   "trainer 9 picked up type 2 at %s, which belongs to trainer 7",
   tostring(M.find(TBL, OFS, 9, 2)))
ok(M.has(TBL, OFS, 7, 1) == true, "has() disagrees with find() on trainer 7")
ok(M.has(TBL, OFS, 7, 9) == false, "has() found a type trainer 7 does not have")
local srow, sn = M.forTrainer(TBL, OFS, 7)
ok(srow ~= nil and sn == 3, "trainer 7 has %s messages, expected 3", tostring(sn))
local sall, srep = M.all(TBL, OFS)
ok(srep.records == srep.reached,
   "synthetic: %d records but %d reached", srep.records, srep.reached)
ok(srep.withMessages == 3, "synthetic: %d trainers with messages, expected 3",
   srep.withMessages)
ok(srep.withoutMessages == 7, "synthetic: %d without, expected 7",
   srep.withoutMessages)
ok(srep.duplicates == 0, "synthetic: %d duplicate entry indices", srep.duplicates)
ok(srep.pairs == 6, "synthetic: %d pairs, expected 6", srep.pairs)
ok(sall[7] ~= nil and sall[3] ~= nil and sall[9] ~= nil and sall[0] == nil,
   "synthetic: the wrong set of trainers came back")
-- Out of range reads nothing rather than reading off the end.
ok(M.offsetFor(OFS, 10) == nil, "trainer 10 is past the offset table and resolved")
ok(M.find(TBL, OFS, 10, 0) == nil, "trainer 10 found a message")
-- `all` returns (rows, report) and the counts are on the SECOND value.  This
-- line read `.records` off the rows table, found nil, and failed -- the check
-- catching its own misuse of the module's signature rather than a fault in it.
local _, erep = M.all("", "")
ok(erep.records == 0 and erep.trainers == 0 and erep.withMessages == 0,
   "an empty table did not come back empty (%s records, %s trainers)",
   tostring(erep.records), tostring(erep.trainers))

-- ---------------------------------------------------------------------------
section("3. the four GetTrainerMessageTypes rows")
-- From `ScrCmd_GetTrainerMessageTypes` and its rematch twin.  The ZEROES are
-- the cartridge's: 0 is PRE_BATTLE and not "none", and keeping them as 0 rather
-- than nil is deliberate (see the module).  If someone tidies them to nil this
-- fails, which is the point.
local function rowIs(row, a, b, c, label)
  ok(row ~= nil and row[1] == a and row[2] == b and row[3] == c,
     "%s is {%s, %s, %s}, expected {%d, %d, %d}", label,
     tostring(row and row[1]), tostring(row and row[2]),
     tostring(row and row[3]), a, b, c)
end
rowIs(M.SCRIPT_TYPES.singles, 0, 2, 0, "SCRIPT_TYPES.singles")
rowIs(M.SCRIPT_TYPES.doubles_first, 3, 5, 6, "SCRIPT_TYPES.doubles_first")
rowIs(M.SCRIPT_TYPES.doubles_second, 7, 9, 10, "SCRIPT_TYPES.doubles_second")
rowIs(M.SCRIPT_TYPES_REMATCH.singles, 17, 0, 0, "rematch singles")
rowIs(M.SCRIPT_TYPES_REMATCH.doubles_first, 18, 0, 6, "rematch doubles_first")
rowIs(M.SCRIPT_TYPES_REMATCH.doubles_second, 19, 0, 10, "rematch doubles_second")
-- Every type named in those rows must be a type that exists.
for _, t in ipairs({ M.SCRIPT_TYPES, M.SCRIPT_TYPES_REMATCH }) do
  for label, row in pairs(t) do
    for i = 1, 3 do
      ok(M.TYPES[row[i]] ~= nil,
         "%s slot %d names message type %s, which is not in the enum",
         label, i, tostring(row[i]))
    end
  end
end

-- ---------------------------------------------------------------------------
section("4. the wiring: lowered, emitted, handled")
local vm = slurp("src/script/Gen4ScriptVM.lua") or ""
local cmds = slurp("src/script/Gen4Commands.lua") or ""
ok(#vm > 0, "src/script/Gen4ScriptVM.lua did not open")
ok(#cmds > 0, "src/script/Gen4Commands.lua did not open")
-- The six `scripts_battles.s` commands this pass lowered.  `getmovementtype`
-- was already lowered and is checked for its HANDLER below, not here.
for _, op in ipairs({ "openmessage", "gettrainermessagetypes",
                      "gettrainerrematchmessagetypes",
                      "printtrainerdialogue",
                      "getrematchtrainerid",
                      "setmovecodeforfacingdirection" }) do
  ok(vm:find("L%." .. op .. "%s*=") ~= nil,
     "`%s` is not lowered; it will take the unknown-command path and be "
     .. "stepped over", op)
end
-- THE RECURRING FAULT, asserted in the direction it actually happens: a row the
-- VM emits that no handler answers.  Checked over the WHOLE file rather than
-- the four rows added with it, because the cheap version of this check is one
-- that only ever looks at the newest code.
-- A ROW IS ANSWERED THREE WAYS, and the first version of this check knew only
-- one of them.  Looking for `function Commands.X(` alone reported nine false
-- positives: seven are `Commands.X = noop` assignments -- answered, and
-- deliberately -- and two are `pending("X", ...)`, which registers a handler
-- that logs once and does nothing.  A check that cried wolf nine times would
-- have been switched off before it ever caught the tenth, so the three are
-- separated here rather than merged.
--
-- `pending` rows are REPORTED and not failed: the port has declared them
-- incomplete in writing, which is the opposite of a silent hole.  Their COUNT
-- is pinned exactly, so a third cannot be added without a decision.
local emitted, unhandled, pendingRows, emittedCount = {}, {}, {}, 0
for name in vm:gmatch('"(g4_[a-z0-9_]+)"') do
  if not emitted[name] then
    emitted[name] = true
    emittedCount = emittedCount + 1
    local hasFn = cmds:find("function Commands%." .. name .. "%s*%(") ~= nil
    local hasAssign = cmds:find("Commands%." .. name .. "%s*=") ~= nil
    local isPending = cmds:find('pending%("' .. name .. '"') ~= nil
    if isPending then
      pendingRows[#pendingRows + 1] = name
    elseif not (hasFn or hasAssign) then
      unhandled[#unhandled + 1] = name
    end
  end
end
table.sort(pendingRows)
if #pendingRows > 0 then
  report("%d row(s) are lowered and registered but declared incomplete: %s",
         #pendingRows, table.concat(pendingRows, ", "))
end
-- TWO, and both are arguable in writing:
--   g4_common          the common-script archive is not resolved to labels
--   g4_use_rock_climb  no generation in this engine climbs a rock wall
-- `g4_get_movement_type` was a third and is implemented (nine disguised
-- trainers). A new one appearing here is a gap somebody should have argued for
-- before adding, which is what pinning the count exactly is for.
-- THREE, each argued in writing where it is declared:
--   g4_common                   the common-script archive is not resolved
--   g4_use_rock_climb           no generation here climbs a rock wall
--   g4_blackout_from_battle_2   identical to 0x14A in the cartridge but NOT
--                               interchangeable here (0x14A's no-op is
--                               justified by its caller), and unreachable
--                               under the Gen 4 poison rule
--   g4_open_hall_of_fame        the PC's post-game record browser.  `pending`
--                               rather than a no-op BECAUSE THE DATA EXISTS:
--                               `save.hallOfFame` has been collecting
--                               {species, level, nickname} rows all along and
--                               what is missing is a screen to read them back
--                               (src/ui/HallOfFame.lua is the induction
--                               ceremony, which walks the LIVE party).  Added
--                               in pass 173 with the PC itself, which had
--                               never been reachable: Field_TileBehaviorToScript
--                               had no Gen 4 arm.
--   g4_open_seal_capsule_editor  the Ball Capsule seal editor
--                               (`CapsuleMenu_StartFieldTask`).  `pending`
--                               rather than a no-op for the same reason, with
--                               the opposite data story: there is no seal
--                               state in this port at all, which is also why
--                               `countuniquesealsinsealcase` lowers onto
--                               `g4_no_feature` and answers zero.  Added in
--                               pass 176, which took the last of
--                               `scripts_common.s` that could be derived.
-- `g4_get_movement_type` was a fourth and is implemented. A new one appearing
-- here is a gap somebody should have argued for before adding, which is what
-- pinning the count exactly is for.
--
-- AND THE PIN FOUND A LIVE BUG WHEN PASS 176 RAISED IT. `pending` installs the
-- handler itself and returned nothing, so the `Commands.x = pending(...)`
-- spelling overwrote it with nil -- which meant `g4_open_hall_of_fame`, pinned
-- here since pass 173, had never had a handler at all. See
-- tools/gen4_underground_inventory_check.lua, which now sweeps every verb
-- assigned that way.
ok(#pendingRows == 5,
   "%d `pending` row(s), expected exactly 5 (g4_common, g4_use_rock_climb, "
   .. "g4_blackout_from_battle_2, g4_open_hall_of_fame and "
   .. "g4_open_seal_capsule_editor): %s",
   #pendingRows, table.concat(pendingRows, ", "))
io.write(("   %d distinct g4_ rows emitted by the VM\n"):format(emittedCount))
ok(#unhandled == 0,
   "%d emitted row(s) have no handler in Gen4Commands: %s",
   #unhandled, table.concat(unhandled, ", "))
-- A FLOOR ON THE COMPARISON. A regex that stopped matching would report a
-- clean zero over nothing at all.
ok(emittedCount >= 172,
   "only %d emitted rows were found (was 175); the scan is matching nothing",
   emittedCount)
for _, name in ipairs({ "g4_open_message", "g4_close_message",
                        "g4_trainer_message_types",
                        "g4_print_trainer_dialogue",
                        "g4_get_movement_type",
                        "g4_get_rematch_trainer_id",
                        "g4_set_move_code_facing" }) do
  ok(cmds:find("function Commands%." .. name .. "%s*%(") ~= nil
     or cmds:find("Commands%." .. name .. "%s*=") ~= nil,
     "no handler for %s", name)
  ok(emitted[name] == true, "nothing emits %s", name)
end
-- ONE SPELLING of the double-battle test. Two callers need it now, and the same
-- concept written twice in places that never meet is the fault that has cost
-- this port eight separate findings.
local spellings = 0
for _ in cmds:gmatch("tonumber%(rec%.battleType%)") do spellings = spellings + 1 end
ok(spellings == 1,
   "the double-battle test is spelled %d times in Gen4Commands.lua; it has two "
   .. "callers and must have one definition", spellings)
-- The cache module must be LOADED, or the index is written and read by nobody.
local data = slurp("src/core/Data.lua") or ""
ok(data:find('"gen4_trainer_messages"') ~= nil,
   "`gen4_trainer_messages` is not on Data.lua's Gen 4 module list, so the index "
   .. "would be written on every import and loaded by nothing")
-- ...and WRITTEN. Both halves, because either alone is a silent hole.
local ext = slurp("src/import/RomExtractorGen4.lua") or ""
ok(ext:find('self:write%("gen4_trainer_messages"') ~= nil,
   "no extractor stage writes gen4_trainer_messages")
ok(ext:find("self:extractTrainerMessages%(%)") ~= nil,
   "the trainer-message stage is never called from run()")
ok(ext:find('"gen4_trainer_messages",') ~= nil,
   "the stage is missing from STAGES, so the progress bar runs past its own end")

-- ---------------------------------------------------------------------------
section("5. the cache: the index, and the lines it names")
local chunk = loadfile(CACHE .. "/gen4_trainer_messages.lua")
if not chunk then
  report("%s/gen4_trainer_messages.lua is not in this cache yet -- the stage "
         .. "that writes it is new, so it arrives with the next re-import. "
         .. "Until then every trainer still battles in silence.", CACHE)
else
  local rows = chunk()
  ok(type(rows) == "table", "gen4_trainer_messages.lua did not return a table")
  local trainers, pairsCount, maxType, seen, dupes = 0, 0, -1, {}, 0
  for id, row in pairs(rows) do
    trainers = trainers + 1
    ok(type(id) == "number" and id >= 0,
       "trainer key %s is not a non-negative number", tostring(id))
    for mt, entry in pairs(row) do
      pairsCount = pairsCount + 1
      if mt > maxType then maxType = mt end
      ok(M.TYPES[mt] ~= nil,
         "trainer %s has a message of type %s, which is not in the enum",
         tostring(id), tostring(mt))
      if seen[entry] then dupes = dupes + 1 end
      seen[entry] = true
    end
  end
  io.write(("   %d trainers, %d (trainer, type) pairs, highest type %d\n")
           :format(trainers, pairsCount, maxType))
  -- EXACT, not floors: these are structural counts of one cartridge, and a
  -- re-extract that changes any of them has changed the walk, not the data.
  ok(trainers == 836,
     "%d trainers carry messages, expected exactly 836 of 928", trainers)
  ok(pairsCount == 2497,
     "%d (trainer, type) pairs, expected exactly 2497 -- the record count of "
     .. "trtbl and the entry count of bank 617 are the same number", pairsCount)
  ok(dupes == 0,
     "%d entry index(es) are claimed by more than one (trainer, type); each "
     .. "record is reachable from exactly one trainer", dupes)
  ok(maxType == 19,
     "highest message type is %d, expected 19 -- WIN (100) is loaded by the "
     .. "battle system and never appears in the field table", maxType)
  -- AND THE TEXT MUST BE THERE. An index into a bank the cache does not hold is
  -- an index to nowhere, and this is the join that actually renders.
  local tchunk = loadfile(CACHE .. "/text.lua")
  if not tchunk then
    report("%s/text.lua did not load, so the index could not be joined to the "
           .. "lines it names", CACHE)
  else
    local text = tchunk()
    local Gen4Text = require("src.import.Gen4Text")
    local resolved, missing, empty, sample = 0, {}, 0, nil
    for id, row in pairs(rows) do
      for mt, entry in pairs(row) do
        local label = Gen4Text.label(M.BANK, entry)
        local s = text[label]
        if s == nil then
          if #missing < 6 then
            missing[#missing + 1] = ("trainer %d type %d -> %s")
              :format(id, mt, label)
          end
        else
          resolved = resolved + 1
          if s == "" then empty = empty + 1 end
          if sample == nil and mt == 0 then sample = s end
        end
      end
    end
    io.write(("   %d of %d indices resolve to a line in bank %d\n")
             :format(resolved, pairsCount, M.BANK))
    if sample then
      io.write(("   a pre-battle line reads: %s\n")
               :format((sample:gsub("%s+", " "):sub(1, 64))))
    end
    ok(#missing == 0,
       "%d index(es) name a line this cache does not hold: %s",
       #missing, table.concat(missing, "; "))
    ok(resolved == 2497,
       "only %d of 2497 indices resolved; the index and the text bank have "
       .. "drifted apart", resolved)
    ok(empty == 0, "%d resolved line(s) are the empty string", empty)
  end
end

-- ---------------------------------------------------------------------------
if PP then
  section("6. `scripts_battles.s` end to end, against pokeplatinum")
  -- THE PAYOFF ASSERTION. Not "are the four new commands lowered" but "is the
  -- script that needs them runnable at all": every macro in the file must be a
  -- command this engine lowers. One unlowered command in here is a hole in
  -- every trainer battle in the region.
  local inc = slurp(PP .. "/asm/macros/scrcmd.inc")
  local enum = slurp(PP .. "/include/data/scripts/scrcmd.h")
  local battles = slurp(PP .. "/res/field/scripts/scripts_battles.s")
  if not (inc and enum and battles) then
    report("pokeplatinum sources not found under %s -- section 6 skipped", PP)
  else
    local macroConst = {}
    for name, body in inc:gmatch("%.macro%s+(%S+)(.-)%.endm") do
      local c = body:match("%.short%s+([A-Za-z][A-Za-z0-9_]*)")
      if c then macroConst[name] = c end
    end
    -- constant -> index, IN FILE ORDER.  Two of the 840 rows are mixed case
    -- (`SCRCMD_GetExchangeServiceCornerItemAndCost` and
    -- `ScrCmd_GETRANDOMBATTLEGROUNDTRAINERS`), and a pattern that demanded
    -- upper case drops them and shifts every opcode after the first by two --
    -- which silently RENAMES 170 opcodes rather than failing.  That is not a
    -- hypothetical: it is how this census first read 0x2F3 as
    -- `buffertrainername` when the cartridge calls it
    -- `buffervaluepaddingdigits`.
    local constIndex, n = {}, 0
    for c in enum:gmatch("ScriptCommand%(%s*([A-Za-z0-9_]+)%s*,") do
      constIndex[c] = n; n = n + 1
    end
    io.write(("   %d script commands in pokeplatinum's enum\n"):format(n))
    ok(n == 840, "%d commands in the enum, expected 840", n)
    local ops = slurp("src/import/Gen4ScriptOps.lua") or ""
    local opName = {}
    for id, nm in ops:gmatch('%[(0x[0-9A-Fa-f]+)%]%s*=%s*{%s*"([^"]+)"') do
      opName[tonumber(id)] = nm
    end
    -- THE REAL TABLE, NOT A REGEX OVER THE SOURCE -- and this is a correction,
    -- not a tidy-up. The regex matched `L.name =` and `L["name"] =` and missed
    -- the nine berry commands, which are lowered inside a loop:
    --
    --     for _, name in ipairs({ "getberrygrowthstage", ... }) do
    --       L[operation] = function(ins, s) ... end
    --     end
    --
    -- so a census built that way reported `scripts_berry_tree_interaction.s`
    -- (118 objects) as having fourteen unlowered uses when it has none. It
    -- under-reports coverage, which is the safe direction for a 0-holes
    -- assertion and the wrong direction for deciding what to work on next --
    -- it sent a whole pass after work that was already finished.
    --
    -- `Gen4ScriptVM.lowered(name)` asks the table itself and existed all along.
    local VM = require("src.script.Gen4ScriptVM")
    local function isLowered(nm) return VM.lowered(nm) end
    -- A CONTROL THAT COULD FAIL: our table and pret's enum must agree name for
    -- name at every index.  If they do not, every count below is measuring a
    -- misalignment rather than a gap.
    local agree, disagree, firstBad = 0, 0, nil
    for c, idx in pairs(constIndex) do
      local mine = opName[idx]
      local want = c:gsub("^SCRCMD_", ""):gsub("^ScrCmd_", ""):lower():gsub("_", "")
      if mine and mine:gsub("_", "") == want then
        agree = agree + 1
      elseif mine then
        disagree = disagree + 1
        if not firstBad then
          firstBad = ("0x%03X: ours %s, pret %s"):format(idx, mine, c)
        end
      end
    end
    io.write(("   opcode table vs pret: %d agree, %d disagree\n")
             :format(agree, disagree))
    ok(disagree == 0,
       "%d opcode(s) disagree with pokeplatinum's enum (first: %s)",
       disagree, tostring(firstBad))
    ok(agree >= 838, "only %d opcodes were compared (was 840)", agree)
    local named, uses, unlowered, holes = {}, 0, {}, 0
    for line in battles:gmatch("[^\r\n]+") do
      local mac = line:match("^%s*([A-Za-z_][A-Za-z0-9_]*)")
      if mac and macroConst[mac] then
        uses = uses + 1
        local idx = constIndex[macroConst[mac]]
        local nm = idx and opName[idx]
        if nm and not isLowered(nm) then
          holes = holes + 1
          if not named[nm] then
            named[nm] = true
            unlowered[#unlowered + 1] = ("%s (0x%03X)"):format(nm, idx)
          end
        end
      end
    end
    io.write(("   scripts_battles.s: %d macro uses, %d unlowered\n")
             :format(uses, holes))
    ok(uses >= 130,
       "only %d macro uses were found in scripts_battles.s (was 136); the scan "
       .. "is matching nothing", uses)
    ok(holes == 0,
       "%d use(s) of %d unlowered command(s) in the script every trainer battle "
       .. "in Sinnoh runs through: %s",
       holes, #unlowered, table.concat(unlowered, ", "))
    -- And the enum, re-derived from pret rather than trusted.
    local types = slurp(PP .. "/generated/trainer_message_types.txt")
    if types then
      local i, mismatched, bad = 0, 0, nil
      for name in types:gmatch("TRMSG_([A-Z0-9_]+)") do
        local id = (name == "WIN") and 100 or i
        if M.TYPES[id] ~= name:lower() then
          mismatched = mismatched + 1
          if not bad then
            bad = ("%d: ours %s, pret %s"):format(id, tostring(M.TYPES[id]),
                                                  name:lower())
          end
        end
        i = i + 1
      end
      ok(i == 21, "pret lists %d message types, expected 21", i)
      ok(mismatched == 0,
         "%d message type name(s) disagree with pret (first: %s)",
         mismatched, tostring(bad))
    end
    local tr = slurp(PP .. "/src/scrcmd_trainer.c")
    if tr then
      ok(tr:find("TRMSG_PRE_DOUBLE_BATTLE_1") ~= nil,
         "scrcmd_trainer.c does not mention TRMSG_PRE_DOUBLE_BATTLE_1; the rows "
         .. "in SCRIPT_TYPES were read from it and cannot be re-derived")
      ok(tr:find("ScriptContext_GetVarPointer") ~= nil,
         "scrcmd_trainer.c no longer uses ScriptContext_GetVarPointer; the "
         .. "destinations-not-values reading of gettrainermessagetypes rests on it")
    end
  end
else
  io.write("\n   (no pokeplatinum dir given -- section 6 skipped)\n")
end

io.write(("\n%d checks, %d failed, %d reported\n"):format(checks, fails, reports))
os.exit(fails == 0 and 0 or 1)
