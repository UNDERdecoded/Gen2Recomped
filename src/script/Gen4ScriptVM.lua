-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Gen 4 script lowering.
--
-- Structurally a sibling of src/script/Gen3ScriptVM.lua, and deliberately so:
-- ScriptRunner and Commands.resolve are generation-agnostic, so a fourth
-- generation needs a lowering and a verb set, not a fourth script subsystem.
-- Shared verbs (`jump`, `label`, `show_text`, `ask`, `set_flag`, `wait`,
-- `play_sound`, `play_music`) are emitted as-is; anything Gen 4 does that no
-- earlier generation has gets a `g4_` verb, exactly as Gen 3 uses `g3_`.
--
-- WHAT IS AND IS NOT HERE.  This is the lowering half.  Gen4Script turns
-- cartridge bytes into instructions and this turns instructions into
-- ScriptRunner rows.  The extractor half -- writing a script pool into
-- data/generated and registering a contribution per map through MapScripts --
-- is NOT built yet, so nothing calls this in a running game.  It is written
-- now because the decode is proven and the lowering is what the decode is
-- for, and because a lowering table is far easier to check against the
-- cartridge than against a half-built extractor.
--
-- WHY THESE COMMANDS, AND WHERE IT GOT TO.  Gen4Script's coverage measurement
-- picked them, not taste.  Measured against the whole cartridge -- 4,079
-- scripts, 50,843 instructions -- this table lowers 97.8% of instructions and
-- leaves 85.7% of scripts with nothing unimplemented in them at all.
--
-- It got there in three passes, and the shape of those passes is the useful
-- part.  The conversation set alone reached 87.8% of instructions but only
-- 52.7% of whole scripts, because a script is only as lowered as its worst
-- command.  Adding EIGHT more -- the four generated trainer-battle commands
-- that occur exactly 928 times each, once per trainer in trdata.narc, and the
-- four that drive a signpost -- took it to 97.3% and 82.4%.  The third pass
-- added ten commands that occur twenty-odd times each and are load bearing
-- anyway: `warp`, without which the player cannot leave a map;
-- `starttrainerbattle`, without which the trainer preamble runs and nothing
-- happens; `pokemartcommon`, without which the clerk says hello and sells
-- nothing.
--
-- Frequency is a good guide to what to lower FIRST and a poor guide to what
-- to stop at.  What remains unlowered is a flat tail of side systems -- TV
-- interviews, the journal, the Battle Tower, Turnback Cave, the Poketch --
-- at a few dozen occurrences each, and those are left as explicit
-- `g4_unimplemented` rows rather than dropped.
--
-- TWO GEN 4 SHAPES THAT ARE NOT GEN 3 SHAPES.
--
-- Conditions are a COMPARISON REGISTER, as in Gen 3, but the comparison and
-- the branch are separate commands: `comparevartovalue` sets the register and
-- `gotoif` / `callif` carry a one-byte condition selecting less / equal /
-- greater / less-or-equal / greater-or-equal / not-equal.  That is the single
-- commonest pair in the game -- 8,058 comparisons and 9,400 conditional
-- branches -- so collapsing the six conditions to a boolean would invert or
-- drop a branch in most scripts in Sinnoh.
--
-- `call` is a real subroutine call with a return stack, and `callcommonscript`
-- calls into a SHARED script archive rather than the current file.  Gen 3's
-- `callstd` is the nearest relative.  Common scripts are left as a `g4_common`
-- row rather than inlined: 345 call sites reach them, they are not in the
-- map's own member, and inlining would need the whole common archive resolved
-- before a single map could lower.

local Gen4ScriptVM = {}

-- ---------------------------------------------------------------------------
-- lowering table: one decoded instruction -> zero or more ScriptRunner rows
-- ---------------------------------------------------------------------------

local L = {}
Gen4ScriptVM.LOWERING = L

local function emit(s, row) s.out[#s.out + 1] = row end

-- A decoded jump carries `target`, an absolute position inside the member.
-- The pool keys scripts by that position, so the label is derived from it in
-- one place rather than in every branch entry.
-- A BRANCH TARGET'S LABEL MUST CARRY ITS MEMBER, and for the whole Gen 4
-- effort it did not.
--
-- The pool is keyed by `Gen4ScriptVM.label(member, at)` -- "M0427/S00C0" --
-- because a script file is one member of scr_seq and an offset means nothing
-- without one.  This built "S00C0".  So `s.has(label)` was false for EVERY
-- branch in the cartridge, `branch` answered nil, and `goto`, `gotoif`, `call`
-- and `callif` each emitted NOTHING AT ALL.
--
-- MEASURED over all 8,567 blocks, compiling each one before and after:
--
--                     rows      jump/call rows   labels
--     before        63,629           6,385            0
--     after        590,965         169,017       66,258
--
-- ZERO LABELS IS THE TELL.  Not one branch target was emitted anywhere in
-- Platinum, and the 6,385 surviving "jump" rows are all `jump end` -- the one
-- control-flow lowering that does not go through here, because it uses the
-- literal label "end".  The only control flow the game had was "stop".
--
-- WHAT IT COST, which is every play report on the opening at once: Route 201's
-- scene is `message` then four `comparevartovalue` rows then `end`, so the
-- briefcase, the starter and Barry-as-follower are all behind branches that
-- were never emitted; Twinleaf's guitarist keeps his approach and loses the
-- eight branches that decide where he walks; and Rowan and the counterpart are
-- revealed by a `clearflag`/`addobject` pair inside a branch block.
--
-- INVISIBLE TO ALL SEVEN CHECKS, and that is the lesson rather than the bug.
-- `g4_jump_if` resolves to a handler, its arity matches, its operands are in
-- the right order and its width agrees with pret -- every one of those asks
-- about a row that was never emitted.  Coverage counted the INSTRUCTION as
-- lowered, which it was.  tools/gen4_branch_check.lua is the eighth check and
-- it asks the one question the others cannot: does every jump land somewhere.
--
-- The member comes off the block being lowered -- `state.member`, parsed from
-- its own label -- and a Gen 4 branch operand is always an offset within the
-- SAME member, which is what makes that the right source.
local function labelFor(instruction, member)
  local t = instruction.target
  if type(t) ~= "number" then return nil end
  if member then return Gen4ScriptVM.label(member, t) end
  return ("S%04X"):format(t)
end
Gen4ScriptVM.labelFor = labelFor

local function branch(s, instruction)
  local label = labelFor(instruction, s and s.member)
  if not label then return nil end
  if s.has and not s.has(label) then return nil end
  if s.want then s.want(label) end
  return label
end

-- control flow -------------------------------------------------------------

L["end"] = function(_, s) emit(s, { "jump", "end" }) end
L["return"] = function(_, s) emit(s, { "g4_return" }) end

L["goto"] = function(ins, s)
  local to = branch(s, ins)
  if to then emit(s, { "jump", to }) end
end

L.call = function(ins, s)
  local to = branch(s, ins)
  if not to then return end
  local ret = s.newLabel()
  emit(s, { "g4_call", ret })
  emit(s, { "jump", to })
  emit(s, { "label", ret })
end

-- The condition byte is the FIRST operand and the target the second.
L.gotoif = function(ins, s)
  local to = branch(s, ins)
  if to then emit(s, { "g4_jump_if", ins.args[1], to }) end
end

L.callif = function(ins, s)
  local to = branch(s, ins)
  if not to then return end
  local ret = s.newLabel()
  emit(s, { "g4_call_if", ins.args[1], ret })
  emit(s, { "jump", to })
  emit(s, { "label", ret })
end

-- A REAL CALL, into the shared script file the id names.
--
-- This used to emit `g4_common <id>` and stop, on the reading that common
-- scripts "are not in the map's own member, and inlining would need the whole
-- common archive resolved before a single map could lower".  Both halves of
-- that turned out to be already done: `extractScripts` decodes EVERY member of
-- scr_seq -- member 211, `scripts_common`, has 231 blocks in the pool -- and
-- the extractor now writes each band's entry-point list beside them.  So the
-- id resolves to a label in the same table `goto` and `call` already jump
-- into, and this becomes the ordinary call it always was.
--
-- 668 sites in this cartridge: 652 into `common_scripts`, 14 into
-- `pokedex_ratings`, 2 into `pokemon_center_2f_common`.  Falls back to the old
-- unexecutable row when the pool has no band table, which is what a cache
-- imported before this looks like.
L.callcommonscript = function(ins, s)
  local label = s.bandLabel and s.bandLabel(ins.args[1])
  if not label then emit(s, { "g4_common", ins.args[1] }) return end
  if s.want then s.want(label) end
  local ret = s.newLabel()
  emit(s, { "g4_call", ret })
  emit(s, { "jump", label })
  emit(s, { "label", ret })
end
L.returncommonscript = function(_, s) emit(s, { "g4_return" }) end

-- comparisons --------------------------------------------------------------

L.comparevartovalue = function(ins, s)
  emit(s, { "g4_compare_var_value", ins.args[1], ins.args[2] })
end
L.comparevartovar = function(ins, s)
  emit(s, { "g4_compare_var_var", ins.args[1], ins.args[2] })
end

-- variables and flags ------------------------------------------------------

L.setvarfromvalue = function(ins, s) emit(s, { "g4_set_var", ins.args[1], ins.args[2] }) end
L.setvarfromvar = function(ins, s) emit(s, { "g4_copy_var", ins.args[1], ins.args[2] }) end
L.addvar = function(ins, s) emit(s, { "g4_add_var", ins.args[1], ins.args[2] }) end
L.subvar = function(ins, s) emit(s, { "g4_sub_var", ins.args[1], ins.args[2] }) end

-- Flags are named the way Gen 3's are, so the save format and the debug
-- screens do not need a fourth spelling.
local function flagName(n) return ("FLAG_G4_%04X"):format(tonumber(n) or 0) end
Gen4ScriptVM.flagName = flagName

L.setflag = function(ins, s) emit(s, { "set_flag", flagName(ins.args[1]) }) end
L.clearflag = function(ins, s) emit(s, { "clear_flag", flagName(ins.args[1]) }) end
L.checkflag = function(ins, s) emit(s, { "g4_check_flag", flagName(ins.args[1]) }) end
L.checkflagfromvar = function(ins,s) emit(s, {'g4_check_flag_var',ins.args[1],ins.args[2]}) end
L.setflagfromvar = function(ins,s) emit(s, {'g4_set_flag_var',ins.args[1]}) end
L.openbag = function(ins,s) emit(s,{'g4_open_bag',ins.args[1]}) end
L.getselecteditem = function(ins,s) emit(s,{'g4_selected_item',ins.args[1]}) end
L.checkpockethasitems = function(ins,s) emit(s,{'g4_pocket_has_items',ins.args[1],ins.args[2]}) end
L.bufferberryname = function(ins,s) emit(s,{'g4_buffer',ins.args[1],'item',ins.args[2]}) end
for _, name in ipairs({'getberrygrowthstage','getberryitemid','getberrymulchtype',
  'getberrymoisture','getberryyield','setberrymulch','plantberry','setberrywateringstate','harvestberry'}) do
  local operation = name
  L[operation]=function(ins,s) emit(s,{'g4_berry',operation,ins.args[1]}) end
end
L.settrainerflag = function(ins, s) emit(s, { "g4_set_trainer_flag", ins.args[1] }) end
L.cleartrainerflag = function(ins, s) emit(s, { "g4_clear_trainer_flag", ins.args[1] }) end
L.checktrainerflag = function(ins, s) emit(s, { "g4_check_trainer_flag", ins.args[1] }) end

-- the conversation ---------------------------------------------------------

-- `message` names an entry in the map's own text bank, which the map header's
-- msgArchiveID selects -- so the row carries the entry and the runner
-- resolves the bank.  Carrying a resolved string here instead would bake one
-- language into the lowering.
-- A GEN 4 `message` NAMES AN ENTRY, AND THE BANK IS THE MAP'S.
--
-- This used to lower straight to `show_text`, on the reading that "the row
-- carries the entry and the runner resolves the bank".  Nothing resolved it:
-- `Commands.show_text` looks its argument up in `data.text`, which the Gen 4
-- extractor keys `TEXT_Bnnnn_nnnnn`, so a bare index found nothing and the box
-- came up EMPTY.  `g4_message` is that join -- the map def's own `messages`
-- bank plus this entry -- and it has to be a separate verb because a Gen 1-3
-- `show_text` takes a whole id and a Gen 4 one takes half of one.
-- ...AND FROM WHICHEVER BANK THE BLOCK'S OWN FILE READS.
--
-- `ScriptContext_Load` takes a script file AND a text bank together, so a
-- block that lives in a shared file does NOT read the current map's message
-- archive -- it reads its band's.  A common script's `message 3` is entry 3 of
-- TEXT_BANK_COMMON_STRINGS wherever the player happens to be standing, and
-- resolving it against the town's bank would print some other map's line.
-- One place, because four commands print a line and three of them are signs.
local function message(entry, s)
  local bank = s.bankFor and s.bankFor(s.member)
  if bank then
    emit(s, { "g4_message_bank", bank, entry })
  else
    emit(s, { "g4_message", entry })
  end
end

L.message = function(ins, s) message(ins.args[1], s) end
-- FOUR MORE SPELLINGS OF THE SAME COMMAND, and `message2` -- which this used
-- to alias -- IS NOT ONE OF THEM.  Checked against the decoder's own table:
-- there is no opcode named `message2`, so that line lowered nothing.  The
-- real siblings are 0x2B, 0x2E and 0x2F, which differ only in how the box
-- animates, and 0x2D, which takes the entry out of a VAR instead of a byte.
L.messageinstant = L.message
L.messagenoskip = L.message
L.messagesynchronized = L.message
L.messagevar = function(ins, s)
  emit(s, { "g4_message_var", ins.args[1], s.bankFor and s.bankFor(s.member) })
end

-- `messagefrombank <bank> <entry>` -- an explicit bank rather than the map's,
-- and otherwise the same operation, so it shares the row. The `instant` twin
-- differs only in not waiting for the printer, which `show_text` does for both
-- anyway (the same reason `g4_wait_button` is a no-op).
--
-- Nine uses over three bands -- tv_broadcast (6), mystery_gift_deliveryman (2)
-- and tv_reporter_interviews (1) -- and the latter two have 13 and 12 objects
-- behind them, which is how the band-reach invariant found them.
L.messagefrombank = function(ins, s)
  emit(s, { "g4_message_bank", ins.args[1], ins.args[2] })
end
L.messagefrombankinstant = L.messagefrombank

-- `choosecustommessageword <unused> <resultVar> <destVar>` -- two destinations
-- and a literal 0 the macro emits for an operand pokeplatinum itself calls
-- unused. See the handler for why it answers "cancelled" rather than nothing.
L.choosecustommessageword = function(ins, s)
  emit(s, { "g4_choose_message_word", ins.args[1], ins.args[2], ins.args[3] })
end
-- `openmessage` -- AND ITS ABSENCE IS WHY `closemessage` WAS LOWERED ALONE.
-- The cartridge opens the field text window explicitly before printing into
-- it and closes it explicitly afterwards; we had the close and not the open,
-- so the pair was asymmetric in the one direction nothing complains about.
-- Ten sites, nine of them in `scripts_battles.s`, which is every trainer.
L.openmessage = function(_, s) emit(s, { "g4_open_message" }) end
L.closemessage = function(_, s) emit(s, { "g4_close_message" }) end
L.closemessagewithouterasing = L.closemessage
L.waitbutton = function(_, s) emit(s, { "g4_wait_button" }) end
-- `showyesnomenu <destVar>` PUTS THE ANSWER SOMEWHERE, and this dropped it.
-- The row asked the question and the script then compared a var nothing had
-- written, so every yes/no in Sinnoh branched on stale state.
L.showyesnomenu = function(ins, s)
  emit(s, { "ask" })
  emit(s, { "g4_from_yesno", ins.args[1] })
end

L.lockall = function(_, s) emit(s, { "g4_lock_all" }) end
L.releaseall = function(_, s) emit(s, { "g4_release_all" }) end
-- `lockobject` / `releaseobject`, which is what the decoder calls 0x62 and
-- 0x63.  These were written as `lock` and `release`, which are not opcode
-- names, so neither ever fired.
L.lockobject = function(ins, s) emit(s, { "g4_lock", ins.args[1] }) end
L.releaseobject = function(ins, s) emit(s, { "g4_release", ins.args[1] }) end
L.faceplayer = function(_, s) emit(s, { "g4_face_player" }) end

L.bufferplayername = function(ins, s) emit(s, { "g4_buffer", ins.args[1], "player" }) end
-- `bufferpokemonname` is not an opcode either; the cartridge has one buffer
-- for a party member's SPECIES and another for its NICKNAME, plus move,
-- number and the counterpart's name.  All six are byte-slot-then-word.
L.bufferpartymonspecies = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "species", ins.args[2] })
end
L.bufferpartymonnickname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "nickname", ins.args[2] })
end
L.buffermovename = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "move", ins.args[2] })
end
L.buffernumber = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "number", ins.args[2] })
end
L.buffercounterpartname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "rival" })
end
L.bufferitemname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "item", ins.args[2] })
end

-- movement, sound and screen ----------------------------------------------

-- THE STEPS, not the offset.  `ins.movement` is the list the extractor
-- decoded out of the same member the instruction lives in (Gen4Movement); the
-- raw displacement it used to pass was meaningless to the runner, which is why
-- `g4_move` could do nothing with it but turn the object round.
--
-- A row with no list still turns the object to face the player, which is what
-- this did before and is better than a character talking to a wall.
L.applymovement = function(ins, s)
  emit(s, { "g4_move", ins.args[1], ins.movement })
end
L.waitmovement = function(_, s) emit(s, { "g4_wait_move" }) end
L.playse = function(ins, s) emit(s, { "g4_play_sound", ins.args[1] }) end
L.waitse = function(ins, s) emit(s, { "g4_wait_sound", ins.args[1] }) end
L.playcry = function(ins, s) emit(s, { "g4_play_cry", ins.args[1] }) end
L.playfanfare = function(ins, s) emit(s, { "g4_fanfare", ins.args[1] }) end
L.waitfanfare = function(_, s) emit(s, { "g4_wait_fanfare" }) end
-- `fadescreen <steps> <framesPerStep> <type> <colour>` -- FOUR operands, and the
-- DIRECTION IS THE THIRD. This passed the first two and the command read the
-- first, which is a constant 6 at all 736 reached sites; see `g4_fade` for the
-- measurement and for why the parity is the opposite of Hoenn's.
L.fadescreen = function(ins, s)
  emit(s, { "g4_fade", ins.args[3], ins.args[1], ins.args[2], ins.args[4] })
end
L.waitfadescreen = function(_, s) emit(s, { "g4_wait_fade" }) end
L.waittime = function(ins, s) emit(s, { "wait", ins.args[1] }) end

L.addobject = function(ins, s) emit(s, { "g4_show_object", ins.args[1] }) end
L.removeobject = function(ins, s) emit(s, { "g4_hide_object", ins.args[1] }) end

-- items --------------------------------------------------------------------

-- ALL FOUR ARE `(item, count, destVar)` -- `scrcmd_item.c` -- and all four
-- write whether they succeeded into that var, which the script then compares.
-- This used to name two of them `giveitem` and `takeitem`, which are not
-- opcodes (the decoder calls them `additem` and `removeitem`, after the
-- cartridge), so NO GIFT IN SINNOH WAS LOWERED AT ALL; and it dropped the
-- destination on the other two, so `checkitem` branched on a stale register.
L.additem = function(ins, s)
  emit(s, { "g4_give_item", ins.args[1], ins.args[2], ins.args[3] })
end
L.removeitem = function(ins, s)
  emit(s, { "g4_take_item", ins.args[1], ins.args[2], ins.args[3] })
end
L.checkitem = function(ins, s)
  emit(s, { "g4_check_item", ins.args[1], ins.args[2], ins.args[3] })
end
L.canfititem = function(ins, s)
  emit(s, { "g4_can_fit_item", ins.args[1], ins.args[2], ins.args[3] })
end

-- the trainer-battle preamble ---------------------------------------------

-- These four are generated, not hand-written: every trainer in the game gets
-- the same opening, which is why each occurs exactly 928 times -- once per
-- trainer in trdata.narc.  Lowering them is worth more than their share of
-- the listing suggests, because a script that stops at one stops before the
-- battle it exists to start.
L.gettrainerid = function(ins, s) emit(s, { "g4_get_trainer_id", ins.args[1] }) end
L.getapproachingtrainerid = function(ins, s)
  emit(s, { "g4_get_approaching_trainer_id", ins.args[1], ins.args[2] })
end
L.checkistrainerdoublebattle = function(ins, s)
  emit(s, { "g4_check_trainer_double", ins.args[1] })
end
L.checkhastwoalivemons = function(ins, s) emit(s, { "g4_check_two_alive", ins.args[1] }) end
L.getmovementtype = function(ins, s)
  emit(s, { "g4_get_movement_type", ins.args[1], ins.args[2] })
end
-- `trainerbattle` used to sit here and is not an opcode; the cartridge's own
-- name is `starttrainerbattle`, which is lowered further down with its two
-- operands.
-- `getrematchtrainerid <trainer> <destVar>` -- operand order is value then
-- DESTINATION, which is the reverse of `getmovementtype` two lines up, and the
-- C is the only place that says so: `trainerID = ScriptContext_GetVar(ctx)`
-- comes first, `destVar = ScriptContext_GetVarPointer(ctx)` second.  One use,
-- reached every time the player talks to a trainer they have already beaten.
-- THE APPROACH TRIO.  `startapproachingtrainertask <approachNum>`,
-- `checkisapproachingtrainertaskdone <approachNum> <destVar>` and
-- `getapproachingtrainertype <destVar>` are the "a trainer notices you and
-- walks over" sequence, and they are lowered DESPITE being unreachable here
-- today -- our overworld spots the player itself and then runs the trainer's
-- own script, so `Battles_ApproachingTrainer` is never entered.
--
-- They are lowered anyway because of what the script does with the middle one:
--
--     Battles_WaitTrainerSinglesTaskDone:
--       CheckIsApproachingTrainerTaskDone 0, VAR_RESULT
--       GoToIfEq VAR_RESULT, FALSE, Battles_WaitTrainerSinglesTaskDone
--
-- which is a jump to itself gated on a var the unlowered command never wrote.
-- The moment anything does dispatch that entry -- a map whose trainer uses the
-- approach band, a mod, the harness -- a stale FALSE in VAR_RESULT is not a
-- missing animation, it is a HANG.  Lowering it to the cartridge's own
-- degenerate answer (see the handler: no task means done) makes the loop
-- terminate on its first pass, which is exactly what the C does when there is
-- no task to wait for.
L.startapproachingtrainertask = function(ins, s)
  emit(s, { "g4_start_approach", ins.args[1] })
end
L.checkisapproachingtrainertaskdone = function(ins, s)
  emit(s, { "g4_approach_done", ins.args[1], ins.args[2] })
end
L.getapproachingtrainertype = function(ins, s)
  emit(s, { "g4_approach_type", ins.args[1] })
end
L.getrematchtrainerid = function(ins, s)
  emit(s, { "g4_get_rematch_trainer_id", ins.args[1], ins.args[2] })
end
-- `setmovecodeforfacingdirection` takes no operands and is answered by doing
-- nothing; see the handler for why that is a decision and not a stub.
L.setmovecodeforfacingdirection = function(_, s)
  emit(s, { "g4_set_move_code_facing" })
end
L.checkwonbattle = function(ins, s) emit(s, { "g4_check_won_battle", ins.args[1] }) end
-- Its twin, and NOT the negation of it: `CheckPlayerLostBattle` reads a
-- different bit of the same result mask, so a battle that ended some third way
-- (a draw, a fled wild) answers no to both.  One site in the cartridge.
L.checklostbattle = function(ins, s)
  emit(s, { "g4_check_lost_battle", ins.args[1] })
end

-- WHAT THE TRAINER SAYS, which until now was nothing at all.
--
-- `gettrainermessagetypes <preVar> <postVar> <notEnoughVar>` writes THREE
-- message-type numbers into three vars, and the operands are VAR IDS rather
-- than var-or-literals: the C takes them with `ScriptContext_GetVarPointer`,
-- not `ScriptContext_GetVar`.  Resolving them as values first -- which is what
-- most of this file does, and what a copy of a neighbouring lowering would do
-- -- would read the three destinations and then write to wherever their
-- CONTENTS pointed, which on a fresh save is var 0 three times.
--
-- The rematch twin differs only in the table it picks from, so both go through
-- one row with a flag; see `Gen4TrainerMessages.SCRIPT_TYPES` for the four
-- rows and for the literal zeroes that are the cartridge's own.
L.gettrainermessagetypes = function(ins, s)
  emit(s, { "g4_trainer_message_types",
            ins.args[1], ins.args[2], ins.args[3] })
end
L.gettrainerrematchmessagetypes = function(ins, s)
  emit(s, { "g4_trainer_message_types",
            ins.args[1], ins.args[2], ins.args[3], "rematch" })
end

-- `printtrainerdialogue <trainer> <messageType>` -- and THESE two ARE
-- var-or-literal (`ScriptContext_GetVar` both), which is the opposite of the
-- command above it.  The cartridge writes the string into the script message
-- buffer and prints it into the window `openmessage` opened, then waits for
-- the printer; the handler does the same through `show_text`.
L.printtrainerdialogue = function(ins, s)
  emit(s, { "g4_print_trainer_dialogue", ins.args[1], ins.args[2] })
end

-- signposts ---------------------------------------------------------------

-- Gen 4's sign boxes are a small state machine rather than one command:
-- draw, set what the box does, poll the player's choice, wait for it to
-- finish.  All four have to lower together or a sign opens and never closes.
-- A SIGN'S FIRST OPERAND IS ITS TEXT, and all three of these lowered it as if
-- it were part of the box.  `ScrCmd_DrawSignpostInstantMessage` (scrcmd.c)
-- reads `(messageID, signpostType, narcMember, unused)` and then does
-- `MessageLoader_GetString(ctx->loader, messageID, ...)` -- it draws the
-- wooden frame AND prints the line.  The frame is cosmetic; the line is the
-- sign.  159 of these in the cartridge, plus 26 scrolling ones, every one of
-- them silent.
--
-- The box itself stays the engine's own, which is why nothing here asks for
-- `signpostType` or the member: this port has one message box and it is
-- already the cartridge's art.
L.drawsignpostinstantmessage = function(ins, s)
  message(ins.args[1], s)
end
-- `drawsignposttextbox <type> <member>` draws an EMPTY frame -- there is no
-- message operand at all -- and whatever fills it comes later.  The engine
-- opens its box when something is printed into it, so this is genuinely
-- nothing to do rather than something skipped.
L.setsignpostcommand = function(_, s) emit(s, { "g4_signpost_command" }) end
-- `getsignpostinput <destVar>` is which line of a multi-choice sign was
-- picked.  Answering 0 -- the first -- is not the same as asking, and it is
-- said here rather than left as a stale register for the branch below it.
L.getsignpostinput = function(ins, s) emit(s, { "g4_signpost_input", ins.args[1] }) end
L.waitforsignpostdone = function(_, s) emit(s, { "g4_signpost_wait" }) end

-- odds and ends that the corpus actually reaches --------------------------

L.getplayermappos = function(ins, s) emit(s, { "g4_player_pos", ins.args[1], ins.args[2] }) end
L.getplayergender = function(ins, s) emit(s, { "g4_player_gender", ins.args[1] }) end
L.bufferrivalname = function(ins, s) emit(s, { "g4_buffer", ins.args[1], "rival" }) end
L.waitcry = function(_, s) emit(s, { "g4_wait_cry" }) end
-- WHERE AN OBJECT STANDS, WHICH WAY IT FACES, AND HOW IT BEHAVES -- the three
-- rows a map's entry script uses to arrange its actors before you see them.
-- Twinleaf's player house calls all three (`setobjecteventpos 0, 2, 4 /
-- setobjecteventdir 0, 0 / setobjecteventmovementtype 0, 14`) and only the
-- first was lowered.
-- THE THREE ROWS THE NEW-GAME SCRIPT ENDS WITH, which are bookkeeping rather
-- than anything on screen: the size-contest record, Jubilife's lottery number
-- and the daily random level.  Named as no-ops so they stop going through the
-- unknown-command path -- a log line saying nothing is worse than one saying
-- which feature is absent.
L.initsizecontestrecord = function(_, s) emit(s, { "g4_noop", "size contest record" }) end
L.randomizejubilifelottery = function(_, s) emit(s, { "g4_noop", "Jubilife lottery" }) end
L.initdailyrandomlevel = function(_, s) emit(s, { "g4_noop", "daily random level" }) end

L.setobjecteventdir = function(ins, s)
  emit(s, { "g4_set_object_dir", ins.args[1], ins.args[2] })
end
L.setobjecteventmovementtype = function(ins, s)
  emit(s, { "g4_set_object_movement", ins.args[1], ins.args[2] })
end
-- ...AND ITS LIVE TWIN, WHICH IS A SEPARATE OPCODE AND WAS NEVER LOWERED.
--
-- `setobjecteventmovementtype` (above, 90 sites) rewrites the map's stored
-- TEMPLATE -- `MapHeaderData_SetObjectEventMovementType`.  `setmovementtype`
-- (30 sites) rewrites the LIVE actor -- `MapObject_SwitchMovementType`.  They
-- are adjacent in the command table and one letter apart in the name, and only
-- the template one was here, so all thirty live rows went through the
-- unknown-command path.
--
-- Eight of those thirty set `MOVEMENT_TYPE_FOLLOW_PLAYER`, and those eight are
-- the entire partner system: Barry out of Twinleaf, Cheryl, Riley, Marley,
-- Mira, Buck, and Amity Square's pet.  Without them Verity Lakefront's arrival
-- scene addresses `LOCALID_FOLLOWER`, finds nobody, and holds the input gate
-- for ever.
L.setmovementtype = function(ins, s)
  emit(s, { "g4_switch_movement", ins.args[1], ins.args[2] })
end
-- MAP_OBJ_STATUS_PERSISTENT -- the bit that decides whether an object survives
-- a map change (`sub_0206184C` deletes every object whose header id is not the
-- new map's unless it is set).  Five script sites, all of them on a partner.
L.setobjectflagispersistent = function(ins, s)
  emit(s, { "g4_set_object_persistent", ins.args[1], ins.args[2] })
end
-- FLAG_HAS_PARTNER (0x961), the save's own memory of an escort.  `sethaspartner`
-- 16 sites, `clearhaspartner` 22, `checkhaspartner` 2 -- and the clear is the
-- one that matters most, because at several sites it is the ONLY thing that
-- ends the escort (Lake Verity Low Water clears it and never touches the
-- movement type).
L.sethaspartner = function(_, s) emit(s, { "g4_set_partner", true }) end
L.clearhaspartner = function(_, s) emit(s, { "g4_set_partner", false }) end
L.checkhaspartner = function(ins, s)
  emit(s, { "g4_check_partner", ins.args[1] })
end
-- `setposition <localID> <x> <y> <z> <dir>`, and the GROUND coordinates are x
-- and z -- `MapObject_SetPosDirFromCoords(obj, x, y, z, dir)`, where y is
-- HEIGHT.  Reading them as x and y would put every placed actor on the wrong
-- tile, so the order is rearranged here rather than at the far end.
L.setposition = function(ins, s)
  emit(s, { "g4_place_object", ins.args[1], ins.args[2], ins.args[4],
            ins.args[5], ins.args[3] })
end

L.setobjecteventpos = function(ins, s)
  emit(s, { "g4_set_object_pos", ins.args[1], ins.args[2], ins.args[3] })
end

-- ...AND THE OTHER TWO THINGS A SCRIPT CAN PICK UP AND MOVE.
--
-- `ScrCmd_SetWarpEventPos` and `ScrCmd_SetBgEventPos` are the same shape as
-- the object one -- `(index, x, z)`, all three through `ScriptContext_GetVar`
-- so any of them may be a var -- and they move a WARP or a SIGN rather than a
-- character.  Both speak the matrix's coordinates, like every other coordinate
-- in a Gen 4 script, so both go through the same conversion.
L.setwarpeventpos = function(ins, s)
  emit(s, { "g4_set_warp_pos", ins.args[1], ins.args[2], ins.args[3] })
end
L.setbgeventpos = function(ins, s)
  emit(s, { "g4_set_bg_pos", ins.args[1], ins.args[2], ins.args[3] })
end
-- A SCRIPTED MENU IS THREE COMMANDS, AND ONLY THE MIDDLE ONE WAS LOWERED.
--
-- The cartridge builds one in three beats (scrcmd.c):
--
--     init(global|local)textmenu  anchorX anchorY cursor canExitWithB destVar
--     addmenuentryimm            entryStringID entryIndex     (once per line)
--     showmenu                                                 -- blocks
--
-- and `ResumeOnMenuSelection` waits for `destVar` to stop being
-- LIST_MENU_NO_SELECTION_YET.  The port lowered only `addmenuentryimm` and
-- `showmenu`, so the DESTINATION VAR -- the entire output of the menu -- was
-- dropped on the floor, and every script that then branched on it read
-- whatever the last command had left there.  161 of the 186 menus in this
-- cartridge write var 0x800C, which is the same register `showyesnomenu` uses,
-- so the stale value was usually the previous yes/no answer.
--
-- The init also decides WHICH TEXT BANK the entry ids name, and the two
-- spellings differ: `local` passes the script's own loader, `global` passes
-- NULL and the menu manager opens TEXT_BANK_MENU_ENTRIES instead.  90 of 151
-- are global.  See Gen4ScriptBands.MENU_ENTRIES_BANK.
local function menuInit(ins, s, bank)
  -- anchorX/anchorY are dropped on purpose: they are DS tile coordinates on a
  -- 256x192 screen (anchorX is 1 in 126 of 186 cases, 31 or 30 -- the
  -- right-hand edge -- in 56 more), and this port's menu places itself by its
  -- own rules on a screen of a different size.  Passing a foreign coordinate
  -- through would put the box off the edge; the cursor row and the B rule are
  -- real behaviour and are kept.
  emit(s, { "g4_menu_init", ins.args[5], ins.args[4], ins.args[3], bank })
end

L.initglobaltextmenu = function(ins, s)
  menuInit(ins, s, require("src.import.Gen4ScriptBands").MENU_ENTRIES_BANK)
end
L.initglobaltextlistmenu = L.initglobaltextmenu
L.initlocaltextmenu = function(ins, s)
  menuInit(ins, s, s.bankFor and s.bankFor(s.member) or nil)
end
L.initlocaltextlistmenu = L.initlocaltextmenu

-- `addmenuentryimm <entryStringID> <entryIndex>` is TWO bytes, not three; the
-- third operand this used to pass was always nil.
L.addmenuentryimm = function(ins, s)
  emit(s, { "g4_menu_entry", ins.args[1], ins.args[2] })
end
-- The same row with both operands out of vars (`addmenuentry`, 0x29D), and the
-- list-menu form, whose middle operand is a SECOND COLUMN of text this port has
-- no place to draw -- `FieldMenuManager_AddListMenuEntry(entry, altText,
-- index)`.  The line and the value it stands for are what the script branches
-- on, so those are carried and the alt column is not.
L.addmenuentry = function(ins, s)
  emit(s, { "g4_menu_entry_var", ins.args[1], ins.args[2] })
end
L.addlistmenuentry = function(ins, s)
  emit(s, { "g4_menu_entry_var", ins.args[1], ins.args[3] })
end

L.showmenu = function(_, s) emit(s, { "g4_menu_show" }) end
L.showlistmenu = L.showmenu
-- One site in the whole cartridge, and its column count is a layout decision
-- this port does not take, so it opens as the single column everything else
-- uses.
L.showmenumulticolumn = L.showmenu
-- (`closemenu` was here and is not an opcode; the menu closes with the
-- script.)

-- a few that matter far more than their count --------------------------------

-- Each of these occurs only twenty-odd times and every one of them is load
-- bearing: without `warp` the player cannot leave a map, without
-- `starttrainerbattle` the trainer preamble above runs and then nothing
-- happens, and without `pokemartcommon` the clerk that motivated this file
-- says hello and sells nothing.  Frequency is a good guide to what to lower
-- first and a poor guide to what to stop at.
-- `warp` IS FIVE OPERANDS, NOT THREE, and the second is not one of the
-- useful ones.  `ScrCmd_Warp` (scrcmd.c:3566) reads
-- `(mapHeaderID, unused, x, z, direction)`, so passing args 1..3 handed the
-- runner the header, the padding and the X coordinate as if they were map,
-- x and y.  Every scripted warp in Sinnoh went to the wrong place or nowhere.
L.warp = function(ins, s)
  emit(s, { "g4_warp", ins.args[1], ins.args[3], ins.args[4], ins.args[5] })
end
L.starttrainerbattle = function(ins, s)
  emit(s, { "g4_start_battle", ins.args[1], ins.args[2] })
end
L.pokemartcommon = function(ins, s) emit(s, { "g4_pokemart", ins.args[1] }) end
L.pokemartspecialties = function(ins, s) emit(s, { "g4_pokemart", ins.args[1], "specialty" }) end
L.checkbadgeacquired = function(ins, s) emit(s, { "g4_check_badge", ins.args[1], ins.args[2] }) end
L.getplayerdir = function(ins, s) emit(s, { "g4_player_dir", ins.args[1] }) end
L.returntofield = function(_, s) emit(s, { "g4_return_to_field" }) end
L.waitforanimation = function(_, s) emit(s, { "g4_wait_animation" }) end
L.drawsignposttextbox = function(_, s) emit(s, { "g4_signpost_command" }) end
-- `drawsignpostscrollingmessage <messageID> <destVar>` prints its line into
-- the sign's window and then waits for the player, leaving what they pressed
-- in the var.  The line is the part that matters.
L.drawsignpostscrollingmessage = function(ins, s)
  message(ins.args[1], s)
  emit(s, { "g4_signpost_input", ins.args[2] })
end

-- ---------------------------------------------------------------------------

function Gen4ScriptVM.lowered(name) return L[name] ~= nil end

-- ---------------------------------------------------------------------------
-- the pool, and attaching it to maps
-- ---------------------------------------------------------------------------

local MapScripts = require("src.script.MapScripts")
local Logger = require("src.core.Logger")

local compiled = setmetatable({}, { __mode = "k" })

-- The `source` check is the same guard Gen3ScriptVM uses, and for the same
-- reason: a cache built by a different generation's extractor has a pool of
-- the same NAME and an entirely different shape, and attaching it would
-- produce maps whose scripts are another game's.
local function store(data)
  local pool = data and data.map_scripts
  if pool and pool.source == "RomExtractorGen4" then return pool end
  return nil
end
Gen4ScriptVM.store = store

-- Compile one label into ScriptRunner rows, following branches into the
-- labels they reach.  Memoised per pool, because a common script is reached
-- from hundreds of call sites and lowering it hundreds of times would be the
-- slowest thing in a boot.
function Gen4ScriptVM.compile(data, entry)
  local pool = store(data)
  local scripts = pool and pool.scripts
  if not (scripts and type(entry) == "string" and scripts[entry]) then return nil end

  compiled[scripts] = compiled[scripts] or {}
  local hit = compiled[scripts][entry]
  if hit ~= nil then return hit or nil end

  -- The band tables, resolved once per compile rather than per row: 668 call
  -- sites across the cartridge and a common script is reached from hundreds of
  -- them.  `memberBank` is the inverse -- which text bank a block's own member
  -- reads from -- and it is nil for the 1,094 members that are a map's own.
  local bands = pool.bands
  local memberBank = {}
  if bands then
    for _, band in pairs(bands) do
      if band.member and band.textBank then memberBank[band.member] = band.textBank end
    end
  end

  local out, queued, order, counter = {}, { [entry] = true }, { entry }, 0
  local state = {
    out = out,
    -- Which block a band id names: the highest threshold it clears picks the
    -- file, and the remainder indexes that file's entry points -- the same
    -- arithmetic `Gen4ScriptBands.classify` does for an object's script id.
    bandLabel = function(id)
      if not bands then return nil end
      local Bands = require("src.import.Gen4ScriptBands")
      local kind, name, index = Bands.classify(id)
      if kind ~= "band" then return nil end
      local band = bands[name]
      local label = band and band.entries and band.entries[index + 1]
      if label and scripts[label] then return label end
      return nil
    end,
    bankFor = function(member) return member and memberBank[member] or nil end,
    has = function(label) return type(label) == "string" and scripts[label] ~= nil end,
    want = function(label)
      if type(label) == "string" and scripts[label] and not queued[label] then
        queued[label] = true
        order[#order + 1] = label
      end
    end,
    newLabel = function()
      counter = counter + 1
      return ("%s_r%d"):format(entry, counter)
    end,
  }

  local index = 1
  while index <= #order do
    local label = order[index]
    index = index + 1
    -- EVERY block needs its label emitted before its rows, INCLUDING THE
    -- FIRST.  This used to skip the entry on the reading that execution starts
    -- there anyway -- true, and beside the point: a script that LOOPS BACK to
    -- its own first block jumps to a label `ScriptRunner.scanLabels` cannot
    -- find, because the only thing that makes a row a jump target is a `label`
    -- row.  878 sites in the cartridge jump to their own entry.  A `label` row
    -- costs nothing to execute (the runner skips it) and one row of storage.
    emit(state, { "label", label })
    -- WHICH MEMBER THIS BLOCK LIVES IN, which decides its text bank.  The
    -- label carries it -- "M0211/S0017" -- so there is nothing to look up.
    state.member = tonumber(label:match("^M(%d+)/"))
    local block = scripts[label]
    Gen4ScriptVM.lower(block and block.instructions, state)
  end

  compiled[scripts][entry] = out
  return out
end

-- A label's branches are resolved against the member it lives in, so a label
-- carries its member: "M0123/S0017".  One place that spelling is built, so a
-- change of key format does not have to be chased through the extractor and
-- the VM separately.
function Gen4ScriptVM.label(member, at)
  return ("M%04d/S%04X"):format(member, at)
end

-- A map's entry scripts are QUEUED, not run: `setMap -> onEnter` can happen
-- mid-warp while the warp command's own runner is still suspended-alive, and
-- starting a second runner there trips `ScriptRunner:run`'s assert.  The
-- overworld drains the queue once the world is idle.  Same helper, same
-- reasoning, as Gen3ScriptVM's.
local function queue(overworld, rows, ctx)
  if overworld and overworld.queueScript then
    overworld:queueScript(rows, ctx)
    return true
  end
  if overworld and overworld.runner then
    overworld.runner:run(rows, ctx)
    return true
  end
  return false
end

local PHASE_KEYS = {
  talk = { talk = true },
  scenes = { onEnter = true, onStep = true, onFrame = true },
}

-- What a map contributes.  Gen 4 has no TEXT constant the way Gen 2 and Gen 3
-- do -- an object event carries a SCRIPT ID and nothing else -- so the key
-- `talk` is indexed by is the script's own label, and the extractor writes
-- that same label into each object's `text` field.  Both halves derive it
-- from Gen4ScriptVM.label, so they cannot drift apart.
-- A BAND-CLASSIFIED EVENT'S BLOCK, WHICH IS HALF OF SINNOH.
--
-- `RomExtractorGen4.linkScripts` binds an object whose script id names a block
-- in the MAP'S OWN member straight to that label, and files every other one
-- under `entry.shared` as `{ id, band, entry, file, kind }` -- the
-- CLASSIFICATION, not the answer.  Nothing above the extractor ever read that
-- table, so those events had no script at all: measured over the cache,
--
--     objects  3,555   1,485 bound to a map-local label   1,821 shared   202 no script   47 sentinel
--     signs      682     402 bound                          280 shared
--
-- and the shared column is every trainer in the region (417), every item ball
-- (329), every hidden item (262), every berry tree (118), all 688 field-move
-- obstacles, both Pokemon Center upper floors (54 each) and the 92 objects on
-- `common_scripts`.  2,100 events, 49.6% of the 4,237 on the maps, and pressing
-- A on any of them did nothing whatsoever.
--
-- NOT ONE TRAINER IN PLATINUM COULD BE FOUGHT.  The 417 carry a resolved
-- `trainer = { id, class, className, party }` from the band, and nothing read
-- that either, so they could not be started by talking; `checkTrainerSight`
-- keys on `sightRange`, which the Gen 4 extractor does not write, so they could
-- not be started by being spotted.  Both halves are dead and this is the first.
--
-- THE RESOLUTION IS THE ARITHMETIC THIS FILE ALREADY DOES.  `state.bandLabel`
-- in `compile` and `Gen4ScriptBands.classify` both say it: the band names the
-- file, the remainder indexes that file's entry points, and the pool's own
-- `bands` table carries both.  So NOTHING NEEDS RE-EXTRACTING -- 2,100 of the
-- 2,101 shared records resolve out of a cache already on disk, to 382 distinct
-- blocks totalling 96,642 compiled rows, with none compiling to nothing.
--
-- The one that does not resolve has no band: that is the link stage's OTHER
-- reason for filing a record here, a map-local id that found no block, and
-- exactly one event in the cartridge is it.  It has no label to offer and must
-- not read as a band failure, which is why the test below is the label rather
-- than the record.
local function sharedLabel(pool, record)
  if type(record) ~= "table" then return nil end
  local bands = pool and pool.bands
  local band = record.band and bands and bands[record.band]
  local label = band and band.entries and band.entries[(record.entry or 0) + 1]
  if type(label) == "string" and pool.scripts and pool.scripts[label] then
    return label
  end
  return nil
end

local function contributionFor(data, mapId, entry)
  local pool = store(data)
  local contribution = {}
  local talk = {}
  local function add(label)
    if type(label) ~= "string" or talk[label] then return end
    local rows = Gen4ScriptVM.compile(data, label)
    if rows then talk[label] = rows end
  end
  for _, label in pairs(entry.objects or {}) do add(label) end
  for _, label in pairs(entry.signs or {}) do add(label) end
  -- ...AND THE SHARED HALF, through the same resolver `bindObjects` stamps with.
  -- Both sides are needed and neither is enough: the label goes on the object so
  -- `talkTo` has something to ask for, and the rows go in the view so the ask
  -- finds them.  One without the other is a press of A that reaches nothing,
  -- which is indistinguishable from the bug being fixed here.
  --
  -- `add` memoises inside the map, and `compile` memoises across them, so the
  -- 2,100 events cost 382 compiles rather than 2,100 -- which matters because
  -- the berry-tree block alone is 2,904 rows and 118 objects point at it.
  for _, record in pairs((entry.shared or {}).objects or {}) do
    add(sharedLabel(pool, record))
  end
  for _, record in pairs((entry.shared or {}).signs or {}) do
    add(sharedLabel(pool, record))
  end
  if next(talk) then contribution.talk = talk end

  -- THE MAP'S OWN ENTRY CONDITIONS.
  --
  -- `entry.callbacks` and `entry.tables` are the init-script member the link
  -- stage now reads -- see Gen4InitScripts for the format, and for why three
  -- separate reports from play ("a woman blocking the door", "mom does
  -- nothing as i come down stairs", "my rival doesnt talk to me") were all
  -- this one gap.  The shapes are deliberately the ones `Gen3ScriptVM` already
  -- produces, because `MapScripts` declares `onEnter` and `onFrame` for Gen 3
  -- and the overworld already asks for both every frame; nothing above this
  -- file needs to learn a fourth generation's spelling.
  local onEnter = {}
  for _, callback in ipairs(entry.callbacks or {}) do
    -- ON_LOAD, ON_TRANSITION and ON_RESUME all run once as the map comes up.
    -- The cartridge distinguishes them by how far through the load it is --
    -- ON_LOAD while the map is being built, ON_RESUME on coming back to the
    -- field from a menu or a battle -- and this engine has one seam at the
    -- point all three have passed.  Running them in the order they appear is
    -- the cartridge's order too, because the table is read front to back.
    local rows = Gen4ScriptVM.compile(data, callback.script)
    if rows then onEnter[#onEnter + 1] = rows end
  end

  local onFrame = {}
  for _, tbl in ipairs(entry.tables or {}) do
    for _, row in ipairs(tbl.rows or {}) do
      local rows = Gen4ScriptVM.compile(data, row.script)
      if rows then onFrame[#onFrame + 1] = { a = row.a, b = row.b, rows = rows } end
    end
  end

  if #onEnter > 0 or #onFrame > 0 then
    contribution.onEnter = function(_, overworld)
      -- A fresh visit re-arms the frame table, for the reason Gen3ScriptVM
      -- gives: these closures outlive the map, and a save loaded back into the
      -- same map has to be asked again.
      for _, g in ipairs(onFrame) do g.armed = nil end
      for _, rows in ipairs(onEnter) do
        queue(overworld, rows, { mapId = mapId })
      end
    end
  end

  -- ASKED EVERY IDLE FIELD FRAME, which is what the cartridge does:
  -- `field_control.c` calls `FieldSystem_RunInitScript(ON_FRAME_TABLE)` from
  -- three places in the input loop, and the FIRST matching row wins.
  --
  -- BOTH SIDES ARE RESOLVED, not just the left one.  `FieldSystem_TryGetVar`
  -- answers a var's value when the id names one and THE ID ITSELF when it does
  -- not, so `0x40A4 vs 0x0000` is "var 0x40A4 equals zero" while a row with
  -- two var ids is a var-to-var comparison.  Reading the right-hand side as a
  -- literal always would be right for this cartridge's 207 rows and wrong in
  -- principle; `valueOf` is the rule itself.
  --
  -- A row that has fired is not asked again until its two sides stop matching.
  -- On the cartridge nothing stops a row re-firing, because a scene all but
  -- always rewrites the var it is gated on -- Twinleaf's `setvarfromvalue
  -- 0x40A4, 1` is exactly that -- but one that does not would otherwise run
  -- every frame, which is a hang rather than a glitch.
  if #onFrame > 0 then
    contribution.onFrame = function(game, overworld)
      local Gen4Commands = require("src.script.Gen4Commands")
      local ctx = { save = game.save, game = game, overworld = overworld }
      for _, g in ipairs(onFrame) do
        local matched = Gen4Commands.valueOf(ctx, g.a) == Gen4Commands.valueOf(ctx, g.b)
        if not matched then
          g.armed = true
        elseif g.armed ~= false then
          g.armed = false
          overworld.runner:run(g.rows, { mapId = mapId })
          return true
        end
      end
      return false
    end
  end

  -- THE COORDINATE TRIGGERS, joined back to where they are.
  --
  -- The link stage resolved each one's script to a label and filed it under
  -- the event's position in the map's own list; the maps stage put the
  -- localised rectangle on `def.coordEvents` under the same index.  Joining
  -- here rather than duplicating either half is the same split `bindObjects`
  -- makes, and for the same reason: the map defs are written before a single
  -- script has been decoded.
  local coords = {}
  local def = data and data.maps and data.maps[mapId]
  for index, label in pairs(entry.coords or {}) do
    local where = def and def.coordEvents and def.coordEvents[index]
    local rows = where and Gen4ScriptVM.compile(data, label)
    if rows then
      coords[#coords + 1] = {
        x = where.x, y = where.y,
        -- A Gen 4 trigger covers a RECTANGLE.  114 of the cartridge's 186 are
        -- one cell, and the other 72 are not -- a doorway four tiles wide, a
        -- corridor six deep -- so the extent is honoured rather than the
        -- corner taken as the whole of it.  Missing or zero reads as one,
        -- which is what a cell with no extent is.
        width = math.max(tonumber(where.width) or 1, 1),
        height = math.max(tonumber(where.height) or 1, 1),
        var = where.var, value = where.value, rows = rows,
      }
    end
  end

  if #coords > 0 then
    -- WHICH ROWS HAVE FIRED WHERE THE PLAYER IS STANDING.
    --
    -- The memory and its two-part key are Gen3ScriptVM's, and the reasoning
    -- there applies here unchanged: a trigger is gated on a var, so the same
    -- cell can be asked again with a different answer, but one ROW must not
    -- run twice for one visit -- and "somewhere else" cannot mean "asked about
    -- a different cell", because a script that walks the player back off the
    -- trigger does not report a step.  `overworld.cellSerial` counts cell
    -- changes however they happen, which is the question this wants to ask.
    local firedAt, fired = nil, {}
    contribution.onStep = function(game, overworld, x, y)
      if overworld.runner:isRunning() then return false end
      local here = ("%s|%d,%d"):format(tostring(overworld.cellSerial or 0), x, y)
      if firedAt ~= here then firedAt, fired = here, {} end
      local Gen4Commands = require("src.script.Gen4Commands")
      local ctx = { save = game.save, game = game, overworld = overworld }
      for i, coord in ipairs(coords) do
        local inside = x >= coord.x and x < coord.x + coord.width
                       and y >= coord.y and y < coord.y + coord.height
        -- ONLY THE VAR SIDE IS RESOLVED.  `sub_0203CC14` is
        -- `TryGetVar(e.var) == e.value` -- the value is compared RAW, unlike
        -- the init frame table two functions up, where BOTH sides go through
        -- `TryGetVar`.  They look like the same test and they are not, and
        -- resolving the value as well would turn any trigger that wants a
        -- number at or above 0x4000 into a comparison against a var.
        if not fired[i] and inside
           and Gen4Commands.valueOf(ctx, coord.var) == (tonumber(coord.value) or 0) then
          fired[i] = true
          Logger.debug("gen4 coord: %s (%d,%d) row %d fired (var %s == %s)",
                       mapId, x, y, i, tostring(coord.var), tostring(coord.value))
          overworld.runner:run(coord.rows, { mapId = mapId })
          return true
        end
      end
      -- WHY A TRIGGER THE PLAYER IS STANDING ON DID NOT FIRE.  The two ways it
      -- can decline look identical from inside the game -- the row already ran
      -- this visit, or the var does not hold the value it wants yet -- and a
      -- scene that needs both halves of a sequence to land in order is exactly
      -- where that matters.  Silent unless the player is on a trigger.
      for i, coord in ipairs(coords) do
        local inside = x >= coord.x and x < coord.x + coord.width
                       and y >= coord.y and y < coord.y + coord.height
        if inside then
          local got = Gen4Commands.valueOf(ctx, coord.var)
          Logger.debug("gen4 coord: %s (%d,%d) row %d declined -- %s",
                       mapId, x, y, i,
                       fired[i] and "already ran this visit"
                         or ("var %s is %s, wants %s"):format(
                              tostring(coord.var), tostring(got),
                              tostring(coord.value)))
        end
      end
      return false
    end
  end

  return next(contribution) and contribution or nil
end

-- WHAT AN OBJECT SAYS WHEN YOU PRESS A ON IT.
--
-- Every earlier generation puts a TEXT constant in the object's own record
-- and `OverworldState:talkTo` reads it as `npc.def.text`.  A Gen 4 object has
-- no such thing: it carries a SCRIPT ID, which is an index into its map's own
-- entry-point list, and the list only exists once the scripts have been
-- decoded.  So the cache's map objects have no `text` and pressing A on an
-- NPC in Sinnoh reached `showMapText(nil)` -- "no text for Twinleaf Town/nil"
-- in the log, and nothing at all on screen.
--
-- The join already exists: the link stage resolved every object's script id
-- to a label and filed it under the object's localId.  This stamps that label
-- back onto the object record, which is where the engine looks, so the two
-- halves stay one fact.  It is done HERE rather than in the extractor because
-- the maps table is written before a single script has been decoded, and a
-- nine-megabyte rewrite to add one string per object would be the wrong
-- trade.
--
-- Signs are the same shape and are keyed by their index in the map's own
-- list, which is what the extractor filed them under.
function Gen4ScriptVM.resolveTalk(data,mapId,index,textConst)
  local pool=store(data)
  local entry=pool and pool.maps and pool.maps[mapId]
  local label=entry and entry.objects and index and entry.objects[index]
  if not label and entry and entry.shared and index then
    label=sharedLabel(pool,(entry.shared.objects or {})[index])
  end
  if not label and type(textConst)=='string' then label=textConst end
  return label and Gen4ScriptVM.compile(data,label) or nil
end

function Gen4ScriptVM.bindObjects(data)
  local pool = store(data)
  if not (pool and pool.maps and data and data.maps) then return 0 end
  local stamped = 0
  for mapId, entry in pairs(pool.maps) do
    local def = data.maps[mapId]
    if type(def) == "table" then
      for i, object in ipairs(def.objects or {}) do
        -- `index`, not `localId`: a map can carry the same localId twice and
        -- the link stage keys by position for exactly that reason.
        local key = object.index or i
        local label = entry.objects and entry.objects[key]
        -- The map's own member first, then the band's block.  The two are
        -- disjoint by construction -- `place` files a record under `shared`
        -- only when the local lookup already failed -- so the order is a
        -- statement of precedence rather than a guard against a clash.
        if label == nil and entry.shared then
          label = sharedLabel(pool, entry.shared.objects
                                    and entry.shared.objects[key])
        end
        if label and object.text == nil then
          object.text = label
          stamped = stamped + 1
        end
      end
      for i, sign in ipairs(def.signs or {}) do
        local key = sign.index or i
        local label = entry.signs and entry.signs[key]
        if label == nil and entry.shared then
          label = sharedLabel(pool, entry.shared.signs
                                    and entry.shared.signs[key])
        end
        if label and sign.text == nil then
          sign.text = label
          stamped = stamped + 1
        end
      end
    end
  end
  return stamped
end

function Gen4ScriptVM.register(data, phase)
  local keep = PHASE_KEYS[phase]
  local pool = store(data)
  if not (pool and pool.maps) then return 0 end
  -- The labels have to be on the objects before the first press of A, and
  -- `talk` is the phase that owns them.
  if phase == "talk" or phase == nil then
    local stamped = Gen4ScriptVM.bindObjects(data)
    Logger.info("gen4 script vm: %d object(s) and sign(s) carry their script "
                .. "label", stamped)
  end
  local attached = 0
  for mapId, entry in pairs(pool.maps) do
    local ok, contribution = pcall(contributionFor, data, mapId, entry)
    if ok and contribution and keep then
      local filtered = {}
      for key, value in pairs(contribution) do
        if keep[key] then filtered[key] = value end
      end
      contribution = next(filtered) and filtered or nil
    end
    if ok and contribution then
      MapScripts.attachBase(mapId, contribution)
      attached = attached + 1
    elseif not ok then
      Logger.warn("gen4 script vm: %s failed to compile (%s)", mapId, tostring(contribution))
    end
  end
  Logger.info("gen4 script vm: %d maps attached (%s)", attached, tostring(phase or "all"))
  return attached
end

-- Lower one decoded script.  Anything without an entry becomes an explicit
-- `g4_unimplemented` row rather than nothing: a silently dropped command is a
-- script that runs and quietly does the wrong thing, which is far harder to
-- find than one that reports what it could not do.
-- THE NEXT LAYER DOWN, by how often the cartridge actually asks ------------
--
-- An unlowered command is not a stall -- it emits `g4_unimplemented` and the
-- block carries on -- so these were inert rather than blocking.  That is also
-- why they are easy to leave: nothing ever breaks loudly.  Taken in frequency
-- order across all 8,567 decoded blocks, which is the only honest priority.
--
-- Every one below is read from its own `ScrCmd_*` in pret rather than from its
-- name.  The names mislead in both directions: `getpartymonspecies` takes the
-- SLOT IN A VAR and writes the species to a second var, and `checkmoney`
-- writes a BOOLEAN rather than the amount.

-- `ScriptContext_Pause(ctx, ScriptContext_CheckABPress)` -- the same wait
-- `waitbutton` performs, and it already has a verb.
L.waitabpress = function(_, s) emit(s, { "g4_wait_button" }) end

-- `*mapID = ctx->fieldSystem->location->mapHeaderID` -- the HEADER id, which
-- is the number the map def carries as `header`, not the engine's map key.
L.getcurrentmapid = function(ins, s) emit(s, { "g4_get_map_id", ins.args[1] }) end

-- `*destVar = LCRNG_Next() % upperBound`, and the bound is read THROUGH
-- `ScriptContext_GetVar`, so it may itself be a var.
L.getrandom = function(ins, s)
  emit(s, { "g4_get_random", ins.args[1], ins.args[2] })
end

L.getrandom2 = function(ins,s)
  emit(s, {'g4_get_random',ins.args[1],ins.args[2]})
  emit(s, {'wait',1})
end
L.buffervaluepaddingdigits = function(ins,s)
  emit(s, {'g4_buffer_padded_number',ins.args[1],ins.args[2],ins.args[3],ins.args[4]})
end

-- `Party_HealAllMembers`.  The engine already has this verb for four other
-- cartridges and it means the same thing on all five.
L.healparty = function(_, s) emit(s, { "heal_party" }) end

-- `*destVar = currentMoney < value ? FALSE : TRUE` -- a yes/no, NOT the
-- balance, and `value` is a literal WORD rather than a var.
L.checkmoney = function(ins, s)
  emit(s, { "g4_check_money", ins.args[1], ins.args[2] })
end
L.removemoney = function(ins, s) emit(s, { "g4_remove_money", ins.args[1] }) end

-- The money box is a HUD this port does not draw.  Named so they stop
-- counting as unimplemented, because a noop here is the truth: there is
-- nothing to show or hide.
L.showmoney = function(_, s) emit(s, { "g4_noop", "money box" }) end
L.hidemoney = function(_, s) emit(s, { "g4_noop", "money box" }) end

-- `u16 *partySlot = GetVarPointer; u16 *destVar = GetVarPointer` -- BOTH are
-- var ids, and the slot is the VALUE HELD IN THE FIRST.  An egg reads as
-- SPECIES_NONE rather than as the species inside it.
L.getpartymonspecies = function(ins, s)
  emit(s, { "g4_party_species", ins.args[1], ins.args[2] })
end

-- `destVar = GetVarPointer; species = GetVar` -- so the species may be a var,
-- and eggs are skipped here too.
L.checkpartyhasspecies = function(ins, s)
  emit(s, { "g4_party_has_species", ins.args[1], ins.args[2] })
end

-- `SystemVars_GetPlayerStarter` -- which starter the player chose, kept in the
-- system vars rather than derived from the party, because the party can lose
-- it.
L.getplayerstarterspecies = function(ins, s)
  emit(s, { "g4_starter_species", ins.args[1] })
end

-- THE FIVE ROWS THAT HAND OVER THE FIRST POKEMON, and three of them were
-- unlowered.  Route 201's briefcase scene, in full:
--
--     startchoosestarterscene          <- opens the app, PAUSES the script
--     savechosenstarter                <- writes VAR_PLAYER_STARTER
--     returntofield
--     getplayerstarterspecies 0x8000
--     givepokemon 0x8000, 5, 0, 0x800C
--
-- `src/ui/Gen4StarterSelect` -- the briefcase, built from the cartridge's own
-- `psel_all` model and its 41-frame animation -- had no callers anywhere in
-- the tree.  This is the line that opens it.
L.startchoosestarterscene = function(_, s) emit(s, { "g4_choose_starter" }) end
L.savechosenstarter = function(_, s) emit(s, { "g4_save_starter" }) end
-- `givepokemon <species> <level> <heldItem> <destVar>` -- the first three are
-- var-or-literal, which matters because the starter arrives as a var.
L.givepokemon = function(ins, s)
  emit(s, { "g4_give_pokemon", ins.args[1], ins.args[2], ins.args[3],
            ins.args[4] })
end
-- The rival's and the counterpart's starters are DERIVED from yours rather
-- than stored -- `SystemVars_GetRivalStarter` and
-- `SystemVars_GetPlayerCounterpartStarter` are two `if` ladders over
-- VAR_PLAYER_STARTER and no state at all.
L.bufferrivalstarterspeciesname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "rivalStarter" })
end
L.bufferplayerstarterspeciesname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "playerStarter" })
end

-- `openpokemonnamingscreen <slotVar> <destVar>` -- THE NICKNAME PROMPT, and it
-- was unlowered at every one of its five sites: SANDGEM TOWN, Eterna City's
-- Name Rater, the Mining Museum's fossil, Hearthome and Veilstone.  Sandgem is
-- the SECOND TOWN, so this is main-path from the first hour.
--
-- THE OPERAND ORDER IS SLOT THEN DESTINATION, and both are read that way by
-- ScrCmd_OpenPokemonNamingScreen -- `ScriptContext_GetVar` first, then
-- `ScriptContext_GetVarPointer`.  The call sites agree without being asked to:
-- three of the five compute the slot as `getpartycount` then `subvar 1` (the
-- member just handed over) and pass it in 0x4000, then compare 0x800C after.
L.openpokemonnamingscreen = function(ins, s)
  emit(s, { "g4_name_pokemon", ins.args[1], ins.args[2] })
end

-- THE FOUR PEOPLE WHO WILL SWAP A POKEMON WITH YOU, and all five of their
-- commands were unlowered on all four maps.  OREBURGH CITY IS ONE OF THEM --
-- the third town -- which is how tools/gen4_map_reach.lua found this at all:
-- `finishnpctrade` occurs eleven times (far down a list ranked by occurrence)
-- and sits on four maps (near the top of one ranked by reach).
--
-- THE SCRIPT IS ONE SHAPE ON ALL FOUR, and reading it is what says what each
-- command has to do:
--
--     initnpctrade <id>                   0 Oreburgh, 1 Eterna,
--                                         2 Snowpoint, 3 Route 226
--     setvarfromvar 0x8004, 0x800C        <- the slot the party menu returned
--     getpartymonspecies 0x8004, 0x8005
--     getnpctraderequestedspecies 0x800C
--     comparevartovar 0x8005, 0x800C
--     gotoif NE <"that is not what I asked for">
--     startnpctrade 0x8004
--     finishnpctrade
--     setflag <this trade's>
--
-- So the ONLY thing that decides whether the swap happens is a comparison of
-- two species numbers -- which means `getnpctraderequestedspecies` leaving its
-- var unwritten does not merely fail to ask, it makes the branch read whatever
-- the last comparison left. An unlowered var-writing command is the dangerous
-- kind, and this is the fifth time that sentence has been written in this file.
L.initnpctrade = function(ins, s) emit(s, { "g4_trade_init", ins.args[1] }) end
L.getnpctraderequestedspecies = function(ins, s)
  emit(s, { "g4_trade_requested", ins.args[1] })
end
-- DOES NOT OCCUR IN THE CORPUS -- the four scripts buffer the offered species
-- another way -- and is lowered anyway because it is one line off the same
-- record, and an opcode left unlowered for no reason is a trap for whoever
-- writes the fifth trade.
L.getnpctradespecies = function(ins, s)
  emit(s, { "g4_trade_species", ins.args[1] })
end
L.startnpctrade = function(ins, s) emit(s, { "g4_trade_start", ins.args[1] }) end
L.finishnpctrade = function(_, s) emit(s, { "g4_trade_finish" }) end
-- `openpartymenufortrade` -- FieldSystem_OpenPartyMenu_SelectForTrade, then
-- ScriptContext_Pause. The slot comes back through `getselectedpartyslot`,
-- which until now was a stub answering CANCELLED because nothing in front of
-- it was built. This is the thing in front of it.
L.openpartymenufortrade = function(_, s) emit(s, { "g4_open_party_for_trade" }) end

-- SMALL STATE THE OPENING READS.  Each is two or three lines on the cartridge,
-- and the ones that write a var were the dangerous kind to leave unlowered:
-- the branch after them reads whatever the last comparison left in the
-- register, so an unlowered `countbadgesacquired` does not merely fail to
-- count badges, it makes the next `gotoif` decide at random.
L.giverunningshoes = function(_, s) emit(s, { "g4_running_shoes" }) end
L.gettimeofday = function(ins, s) emit(s, { "g4_time_of_day", ins.args[1] }) end
L.countbadgesacquired = function(ins, s)
  emit(s, { "g4_count_badges", ins.args[1] })
end
-- `ScrCmd_CheckRunningShoesAcquired`: `*destVar = PlayerData_HasRunningShoes()`.
--
-- 0x159 was in the opcode table and had no lowering, which for a command that
-- writes a var is the bad case described above: the `gotoif` after it read
-- whatever the last comparison left behind, so a script asking whether the
-- player has the shoes got an answer with nothing to do with the shoes.
L.checkrunningshoesacquired = function(ins, s)
  emit(s, { "g4_has_running_shoes", ins.args[1] })
end
L.checkpoketchappregistered = function(ins, s)
  emit(s, { "g4_poketch_registered", ins.args[1], ins.args[2] })
end
L.getsetnationaldexenabled = function(ins, s)
  emit(s, { "g4_national_dex", ins.args[1], ins.args[2] })
end
-- `Sound_PlayBGM(ScriptContext_ReadHalfWord(ctx))` and
-- `Sound_PlayBGM(FieldBGM_GetForMapHeader(...))`.  Both verbs already exist on
-- this engine and neither was reaching them.
L.playmusic = function(ins, s) emit(s, { "play_music", ins.args[1] }) end
-- THE SCRIPTED CAMERA.  `ApplyFreeCameraMovement` is not an opcode -- the
-- macro expands to `ApplyMovement LOCALID_CAMERA` -- so these four are the
-- whole feature, and the pan itself rides the movement path that already
-- exists.  13 `addfreecamera` sites, 14 `restorecamera`.
L.addfreecamera = function(ins, s)
  emit(s, { "g4_add_free_camera", ins.args[1], ins.args[2] })
end
L.restorecamera = function(_, s) emit(s, { "g4_restore_camera" }) end
L.addcameraoverrideobject = function(ins, s)
  emit(s, { "g4_camera_override", ins.args[1], ins.args[2] })
end
L.removecameraoverrideobject = function(_, s)
  emit(s, { "g4_restore_camera" })
end

-- DOORS.  A Gen 4 door is an NSBCA animation on the door's own NSBMD map prop,
-- played on a tagged one-shot slot with a sound effect
-- (`DoorAnimation_FindDoorAndLoad` searches the loaded props for one of twenty
-- named door models at the given tile, then
-- `MapPropOneShotAnimationManager_PlayAnimationWithSoundEffect`).  This port
-- reads NSBMD but not NSBCA, bakes the ground's props into a flat canvas, and
-- has no SE bank for Gen 4 yet -- three separate stages, none of them close.
--
-- Named rather than left on the unknown-command path, so the log says WHICH
-- feature is absent instead of printing an opcode nobody can look up.  The
-- wait is a no-op too: with nothing animating there is nothing to wait for,
-- and holding the script would be a frozen pause rather than a door opening.
L.loaddooranimation = function(_, s) emit(s, { "g4_noop", "door animations" }) end
L.playdooropenanimation = function(_, s) emit(s, { "g4_noop", "door animations" }) end
L.playdoorcloseanimation = function(_, s) emit(s, { "g4_noop", "door animations" }) end
L.unloadanimation = function(_, s) emit(s, { "g4_noop", "door animations" }) end
L.waitforanimation = function(_, s) emit(s, { "g4_noop", "door animations" }) end

-- `FieldMenuManager_SetHorizontalAnchor` / `SetVerticalAnchor` -- which corner
-- the NEXT script menu is drawn from.  This engine's menu places itself, so
-- the anchor has nowhere to land; it is cosmetic either way.
L.setmenuxoriginside = function(_, s) emit(s, { "g4_noop", "menu anchor side" }) end
L.setmenuyoriginside = function(_, s) emit(s, { "g4_noop", "menu anchor side" }) end

-- `TVInterview_IsEligible`.  Lowered rather than skipped for the reason every
-- var-writing command has to be: an unlowered one leaves the comparison
-- register holding the LAST command's answer, so the `gotoif` behind it
-- branches on something unrelated.  Answering "no" is both honest -- this port
-- has no TV broadcast system -- and the answer that keeps the scripts quiet.
L.checktvintervieweligible = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "the TV broadcast system" })
end

-- CHAPTER TWO, measured the same way the opening was: walking every script
-- block reachable from Sandgem through Jubilife to the Oreburgh gym (327
-- blocks) left 16 unlowered rows, and only ONE of them stopped anything --
-- `givebadge`, in the gym leader's own script.
L.givebadge = function(ins, s) emit(s, { "g4_give_badge", ins.args[1] }) end
-- The trainer's own class, which the cartridge derives from their APPEARANCE
-- (`Appearance_CalculateFromTrainerInfo` -> `Appearance_GetData`).  This port
-- has no appearance system, so the class comes back as zero and the buffer
-- behind it falls back rather than printing a wrong one.
L.loadtrainerappearances = function(_, s)
  emit(s, { "g4_noop", "trainer appearance variants" })
end
L.gettrainerinfotrainerclass = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "the trainer appearance system" })
end
L.buffertrainerclassfromappearance = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "trainerClass", 0 })
end
-- ...and the one that takes a class DIRECTLY, which is real: every trainer row
-- carries `class` and `className`, so the name map is already in the cache.
L.buffertrainerclassnamewitharticle = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "trainerClass", ins.args[2] })
end
L.capitalizefirstletter = function(ins, s)
  emit(s, { "g4_capitalize", ins.args[1] })
end
-- `GameRecords_IncrementTrainerScore` -- the trainer-card score counters,
-- which this port keeps none of.
L.incrementtrainerscore = function(_, s) emit(s, { "g4_noop", "trainer score records" }) end
L.incrementtrainerscore2 = function(_, s) emit(s, { "g4_noop", "trainer score records" }) end
-- `ScrCmd_Dummy1F9` reads a var and returns.  It is a no-op ON THE CARTRIDGE,
-- so this is not a stand-in for anything.
L.dummy1f9 = function(_, s) emit(s, { "g4_noop", "a cartridge no-op (dummy1f9)" }) end
L.playdefaultmusic = function(_, s) emit(s, { "play_default_music" }) end
L.stopmusic = function(_, s) emit(s, { "stop_music" }) end

-- The journal is Platinum's own diary screen and this port has none.  A noop
-- rather than a gap: the scripts that write entries must keep running, and
-- what they write has nowhere to go.
L.givejournal = function(_, s) emit(s, { "g4_noop", "journal" }) end
L.createjournalevent = function(_, s) emit(s, { "g4_noop", "journal entry" }) end


-- ---------------------------------------------------------------------------
-- CHAPTER THREE -- the Oreburgh gate to Gardenia's gym
-- ---------------------------------------------------------------------------
--
-- The reachable set again, from the Oreburgh gate through Jubilife, Route 204,
-- Floaroma, the Valley Windworks, Eterna Forest and Eterna City to the gym:
-- 191 entry points, 610 blocks, 5,230 instructions, 176 unlowered rows across
-- 42 commands.  These are the ones that change what a player sees; contests,
-- accessories and the TV are the tail and are left named.

-- THE BLACKOUT IS ALREADY DONE BY THE TIME THIS ROW RUNS.
--
-- `BlackOutFromBattle / ReleaseAll / End` is the same three rows at all eight
-- sites: the cartridge hands a LOST scripted battle back to the script and
-- lets the script order the blackout.  This port does not -- `OverworldState:
-- afterBattle` heals the party, halves the money and warps to the heal point
-- the moment a battle is lost, exactly as it does for Gen 1-3, so by the time
-- the script resumes the player is already standing in the Pokemon Centre.
--
-- So this is a no-op because the work HAS BEEN DONE, not because it is
-- missing; implementing it for real would halve the money a second time.
L.blackoutfrombattle = function(_, s)
  emit(s, { "g4_noop", "the scripted blackout (the battle teardown has already done it)" })
end
-- 0x14B IS THE SAME FUNCTION AS 0x14A IN THE CARTRIDGE -- byte for byte, both
-- a single `FieldTask_StartBlackOutFromBattle(ctx->task)` -- AND IT STILL MUST
-- NOT SHARE THE ROW ABOVE. That is the interesting part.
--
-- The row above is a no-op, and its reasoning is a claim about the CALLER:
-- "the battle teardown has already done it". 0x14A's only use is
-- `CommonScript_LostHoneyTreeBattle`, which is reached after losing a battle,
-- so the claim holds. 0x14B's only use is `CommonScript_PoisonWhiteout`, where
-- NO BATTLE HAPPENED -- so the same no-op would leave the player walking around
-- with a wiped party.
--
-- Two identical cartridge functions, and our substitute for one of them is
-- valid for its caller and not for the other's. A shared row would have been
-- defensible from the C alone and wrong.
--
-- Declared rather than implemented, because the path is UNREACHABLE under the
-- rule the same pass put in: `Pokemon_DoPoisonDamage` is `if (hp > 1) hp--`, so
-- field poison cannot take a Pokemon below 1 HP, so `CountAliveMonsExcept`
-- cannot reach 0 from poison, so this script entry cannot be reached from it.
-- Implementing it would add a third copy of the engine's whiteout sequence for
-- a caller that never runs.
L.blackoutfrombattle2 = function(_, s)
  emit(s, { "g4_blackout_from_battle_2" })
end
L.setblackoutwarpid = function(ins, s)
  emit(s, { "g4_set_blackout_warp", ins.args[1] })
end

-- THE ITEM-PICKUP LINE, which is 96 of the 176 rows on its own and every one
-- of them in `scripts_common` -- so this is not a Floaroma fix, it is every
-- item in the region.  `getitempocket` is the dangerous kind of gap: a
-- var-writer left unlowered leaves the comparison register holding the
-- previous command's answer, and the pocket name printed after it is then
-- whatever that happened to be.
L.getitempocket = function(ins, s)
  emit(s, { "g4_item_pocket", ins.args[1], ins.args[2] })
end
L.bufferpocketname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "pocket", ins.args[2] })
end
L.bufferitemnameplural = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "itemPlural", ins.args[2] })
end
L.checkitemisplate = function(ins, s)
  emit(s, { "g4_item_is_plate", ins.args[1], ins.args[2] })
end

-- THE ITEM BANDS. `scripts_visible_items.s` (329 objects) and
-- `scripts_hidden_items.s` (262) are shared bands, and both finish a pickup
-- with `IsItemTMHM` followed by two `GoToIfEq`s. Unlowered, the var neither
-- jump tested was ever written, so neither was taken and the script fell into
-- `End` -- 591 pickups that added the item and said nothing. See the handler.
L.isitemtmhm = function(ins, s)
  emit(s, { "g4_item_is_tmhm", ins.args[1], ins.args[2] })
end
-- One operand, no destination: a flag the cartridge sets and never reads.
L.trysetunusedcollectedorbflag = function(ins, s)
  emit(s, { "g4_try_set_collected_orb_flag", ins.args[1] })
end
-- A TV segment with nowhere to go; lowered so the row stops warning on all 262
-- hidden items.
L.savetvsegmenthiddenitem = function(ins, s)
  emit(s, { "g4_save_tv_segment", "hidden_item", ins.args[1] })
end

L.getpartycount = function(ins, s) emit(s, { "g4_party_count", ins.args[1] }) end
L.countalivemonsexcept = function(ins,s)
  emit(s, {'g4_party_alive_except',ins.args[1],ins.args[2]})
end
-- `survivepoison <destVar> <slot>` -- `Pokemon_TrySurvivePoison`, and the
-- script calls it ONCE PER PARTY SLOT in a loop:
--
--     CommonScript_TrySurvivePoison:
--       SurvivePoison VAR_RESULT, VAR_0x8005
--       GoToIfEq VAR_RESULT, FALSE, CommonScript_FaintedFromPoison
--       BufferPartyMonNickname 0, VAR_0x8005
--       Message CommonStrings_Text_PokemonSurvivedThePoisoning
--     CommonScript_FaintedFromPoison:
--       AddVar VAR_0x8005, 1
--       GoToIfNe VAR_0x8004, VAR_0x8005, CommonScript_TrySurvivePoison
--
-- Destination first, slot second -- `GetVarPointer` then `GetVar`, the same
-- order as `getmovementtype` and the reverse of `getrematchtrainerid`. The loop
-- terminates on the slot counter either way, so an unlowered row did not hang
-- it; it printed the survived line for every mon or for none.
L.survivepoison = function(ins, s)
  emit(s, { "g4_survive_poison", ins.args[1], ins.args[2] })
end
-- `hatchegg` -- no operands. `FieldSystem_HatchEgg` is `Party_GetFirstEgg`
-- plus the hatch scene; the common script around it does the "Oh?" and the
-- fades, so this row is only the hatch.
L.hatchegg = function(_, s) emit(s, { "g4_hatch_egg" }) end
L.countalivemonsandboxmons = function(ins,s)
  emit(s, {'g4_party_alive_and_boxes',ins.args[1]})
end
L.countpartynoneggs = function(ins, s)
  emit(s, { "g4_party_non_eggs", ins.args[1] })
end

-- THE POKETCH, whose registration this port could already READ and had never
-- once WRITTEN: `checkpoketchappregistered` has been lowered since the small-
-- state pass and answers from `save.poketch.registered`, which nothing filled.
-- Every app was therefore unregistered for ever, and the Jubilife scene that
-- hands the watch over is four of the five sites.
L.enablepoketch = function(_, s) emit(s, { "g4_enable_poketch" }) end
L.registerpoketchapp = function(ins, s)
  emit(s, { "g4_register_poketch_app", ins.args[1] })
end
L.bufferpoketchappname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "poketchApp", ins.args[2] })
end

-- THE AVATAR.  `setplayerstate` is a BITMASK (see the command), and only two
-- values are ever passed: WALKING, which is a dismount, and HEALING, which is
-- the nurse's pose this port draws no differently.  `changeplayerstate` is the
-- latch that applies the requested bit -- this port applies it in the setter,
-- so the latch has nothing left to do.
L.setplayerstate = function(ins, s) emit(s, { "g4_player_state", ins.args[1] }) end
L.changeplayerstate = function(_, s)
  emit(s, { "g4_noop", "the player-state latch (the state is applied when it is set)" })
end
L.setplayerbike = function(ins, s) emit(s, { "g4_player_bike", ins.args[1] }) end

-- MUSIC.  `playmusic` already lowers to the shared `play_music`, so `setbgm`
-- goes to the same verb: the cartridge's distinction is "play now" against
-- "play on this map from now on", and without a Gen 4 sequence bank there is
-- nothing on either side of it.  The fades and the encounter jingle are noops
-- for the same reason -- `audio.lua` on a Platinum cache is cries and nothing
-- else.
L.setbgm = function(ins, s) emit(s, { "play_music", ins.args[1] }) end
L.fadeoutbgm = function(_, s) emit(s, { "g4_noop", "a BGM fade" }) end
L.playtrainerencounterbgm = function(_, s)
  emit(s, { "g4_noop", "the trainer encounter jingle" })
end

L.getdayofweek = function(ins, s) emit(s, { "g4_day_of_week", ins.args[1] }) end

-- THE ETERNA GYM FLOWER CLOCK, and the reason this is a noop rather than a
-- blocker is MEASURED rather than assumed.
--
-- On the cartridge the clock's two hands are walkways: advancing the clock
-- rotates them and that is how you cross the gym.  The obstruction is not in
-- the map at all -- it lives in `PersistedMapFeatures` and the gym_features
-- overlay.  Dumping the gym's own permission grid (header 67, matrix 220,
-- chunk 294) shows 775 cells of behaviour NONE, one warp, and NOT ONE blocked
-- or dynamic-collision cell: the floor is a single open disc.
--
-- So in this port the puzzle is ABSENT, not impassable -- Gardenia is reachable
-- by walking straight at her.  And the five `advanceeternagymclock` rows are
-- all AFTER a trainer is beaten and none of them gates a branch (the script
-- counts its own progress in VAR_ETERNA_GYM_TRAINERS_BEATEN), so nothing reads
-- a state this port does not keep.  The fidelity gap is real and is recorded in
-- the tracker; the stall is not.
L.advanceeternagymclock = function(_, s)
  emit(s, { "g4_noop", "the Eterna Gym flower clock (the gym floor is open here)" })
end
L.initpersistedmapfeaturesforeternagym = function(_, s)
  emit(s, { "g4_noop", "the Eterna Gym persisted map feature" })
end

-- THE JUBILIFE TAG BATTLE, which is on the critical path and whose absence is
-- worse than a skipped fight: the scene reads `CheckWonBattle` on the next row
-- and branches to its own blackout on FALSE, so an unlowered battle blacks the
-- player out mid-cutscene.  What this port fields, and what it does not, is
-- written out on the command.
L.starttagbattle = function(ins, s)
  emit(s, { "g4_start_tag_battle", ins.args[1], ins.args[2], ins.args[3] })
end

L.removemoney2 = function(ins, s) emit(s, { "g4_remove_money", ins.args[1] }) end
L.updatemoneydisplay = function(_, s)
  emit(s, { "g4_noop", "the money window refresh" })
end
L.playpokecenterhealinganimation = function(ins, s)
  emit(s, { "g4_heal_animation", ins.args[1] })
end
-- `ScrCmd_Dummy` -- a no-op on the cartridge too, like `dummy1f9`.
L.dummy = function(_, s) emit(s, { "g4_noop", "a cartridge no-op (dummy)" }) end
-- One site, in `scripts_common`.  The port HAS a start menu, but the one it
-- would push is Gen 1/2's, and opening Kanto's menu in Sinnoh is worse than
-- not opening one: a Gen 4 start menu is its own task and is on the tracker.
L.showstartmenu = function(_, s)
  emit(s, { "g4_noop", "the scripted start-menu prompt" })
end

-- VAR-WRITERS WHOSE FEATURE DOES NOT EXIST HERE, which must still write a zero
-- so the comparison behind them is not reading the previous command's answer.
L.gettrainercardlevel = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the trainer card" })
end
L.checkpartypokerus = function(ins, s)
  emit(s, { "g4_party_pokerus", ins.args[1] })
end
L.checkdistributionevent = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "Mystery Gift distribution events" })
end


L.buffertmhmmovename = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "tmhmMove", ins.args[2] })
end
L.giveegg = function(ins, s)
  emit(s, { "g4_give_egg", ins.args[1], ins.args[2] })
end
L.startlegendarybattle = function(ins, s)
  emit(s, { "g4_legendary_battle", ins.args[1], ins.args[2] })
end
-- Event-distributed Pokemon, which cannot exist in a save this port wrote.
-- !! AND THE SAME MISTAKE HERE, WITH A WORSE RESULT.
-- pret reads `GetVarPointer` then `GetVar`: operand 1 is the destination and
-- operand 2 is the species. Passing args[2] as the destination meant the port
-- wrote its zero into a var id taken from the SPECIES operand -- clobbering an
-- unrelated var rather than merely failing to write one.
--
-- Both of these are the "destination comes first" shape that `scrcmd_party.c`'s
-- four party queries already demonstrated, written up two sections above, and
-- then walked into twice anyway -- on the two commands whose names both contain
-- "fatefulencounter". Reading carefully is not a substitute for a check.
L.findpartyslotwithfatefulencounterspecies = function(ins, s)
  emit(s, { "g4_fateful_slot", ins.args[1], ins.args[2] })
end

-- FIVE COMMANDS PRET HAS NOT NAMED, and all five turn out to be safe.  Read
-- one at a time rather than lumped together, because "unnamed" is not a
-- category: `ScrCmd_2CD` starts a weather task; `32D`, `32E`, `331` and `332`
-- walk the map-object list turning a status flag on or off (the Eterna City
-- and Galactic-building cutscenes hiding and showing their cast).  NOT ONE OF
-- THEM WRITES A VAR, which is the only thing that would make a noop dangerous.
L["2cd"] = function(_, s) emit(s, { "g4_noop", "a weather task (scrcmd 2CD)" }) end
L["32d"] = function(_, s) emit(s, { "g4_noop", "an object status flag (scrcmd 32D)" }) end
L["32e"] = function(_, s) emit(s, { "g4_noop", "an object status flag (scrcmd 32E)" }) end
L["331"] = function(_, s) emit(s, { "g4_noop", "an object status flag (scrcmd 331)" }) end
L["332"] = function(_, s) emit(s, { "g4_noop", "an object status flag (scrcmd 332)" }) end


L.startfirstbattle = function(ins, s)
  emit(s, { "g4_start_first_battle", ins.args[1] })
end
-- Route 202 parks the field script until the catching demonstration ends.
L.startcatchingtutorial = function(_, s)
  emit(s, { "g4_catching_tutorial" })
end
L.givepokedex = function(_, s) emit(s, { "g4_give_pokedex" }) end
L.getlocaldexseencount = function(ins, s)
  emit(s, { "g4_dex_seen_count", ins.args[1] })
end
L.checklocaldexcompleted = function(ins, s)
  emit(s, { "g4_dex_complete", ins.args[1], false })
end
L.setstepflag = function(_, s)
  emit(s, { "g4_noop", "the step-counter freeze (a script already holds the gate)" })
end
L.clearstepflag = function(_, s)
  emit(s, { "g4_noop", "the step-counter freeze (a script already holds the gate)" })
end
L.incrementgamerecord = function(ins, s)
  emit(s, { "g4_add_game_record", ins.args[1], 1, true })
end
L.setinitialvolumeforsequence = function(_, s)
  emit(s, { "g4_noop", "a sequence volume (there is no Gen 4 sequence bank)" })
end

-- The counterpart's starter, with its article, at Rowan's lab.  The species is
-- DERIVED (see `counterpartStarter`) and the article comes from bank 413.
L.bufferplayercounterpartstarterspeciesnamewitharticle = function(ins, s)
  emit(s, { "g4_buffer_counterpart_starter_article", ins.args[1] })
end


L.startdestroyobstacleanimation = function(ins, s)
  emit(s, { "g4_destroy_obstacle_anim", ins.args[1], ins.args[2] })
end

-- THE OTHER SHARED SCRIPT.  `scripts_field_moves.s` is to HMs what
-- `scripts_battles.s` is to trainers: one file, seventeen entries, and every
-- use of Cut, Rock Smash, Strength, Rock Climb, Surf, Waterfall, Defog and
-- Flash in Sinnoh goes through it -- twice over, because each has a "talk to
-- the obstacle" path and a "use it from the party menu" path.  Nine of its
-- commands were unlowered, 23 uses.

-- `playhmcutin <slot>` -- the "<MON> used CUT!" splash, which the cartridge
-- blocks on (`ScriptContext_Pause(ctx, ScriptContext_WaitForHMCutInFinished)`).
-- Nine uses: once in every HM path there is.
L.playhmcutin = function(ins, s) emit(s, { "g4_hm_cut_in", ins.args[1] }) end

-- The three that actually move the player.  Each takes the party slot of the
-- Pokemon doing it, and each starts a field task the cartridge does not wait
-- for -- the script ends and the task finishes the motion.
L.usesurf = function(ins, s) emit(s, { "g4_use_surf", ins.args[1] }) end
L.usewaterfall = function(ins, s) emit(s, { "g4_use_waterfall", ins.args[1] }) end
L.userockclimb = function(ins, s) emit(s, { "g4_use_rock_climb", ins.args[1] }) end

-- 0x0C3 AND 0x0C4 ARE THE SAME FUNCTION, BYTE FOR BYTE.  pokeplatinum leaves
-- both numbered because there is nothing to tell them apart:
--
--     FieldOverworldState_SetWeather(fieldState, OVERWORLD_WEATHER_CLEAR);
--     ov5_021D5F7C(..., FieldOverworldState_GetWeather(fieldState));
--
-- in both.  The script uses 0x0C3 after Flash and 0x0C4 after Defog, which is
-- the only thing that distinguishes them and is not a difference in behaviour.
--
-- THAT PLATINUM CLEARS *WEATHER* FOR FLASH IS THE INTERESTING PART: a dark
-- cave and a foggy route are the same mechanism on this cartridge -- an
-- overworld weather state -- so lighting a cave and blowing away fog are one
-- operation. Gen 2 bakes darkness into the palette instead (see the Gen 2
-- notes on FLASH), which is why nothing in this engine was looking for a
-- weather write here.
--
-- Both lower to ONE row. Two rows doing the same thing is how a port ends up
-- fixing one and not the other.
L["0c3"] = function(_, s) emit(s, { "g4_clear_overworld_weather" }) end
L["0c4"] = L["0c3"]

-- `dostrengthfunc` / `doflashfunc` / `dodefogfunc` -- one opcode each, and all
-- three are VARIABLE LENGTH: a sub-function byte, plus a destination word only
-- when that byte is FIELD_MOVE_FUNC_CHECK_ACTIVE.  `Gen4ScriptOps.VARIABLE_SPEC`
-- now decodes that rule, which is what makes these reachable at all -- the
-- decoder used to stop the walk here and four scripts ended early.
--
-- All six uses in the cartridge are in this one file: SET_ACTIVE twice for
-- Strength and once each for Flash and Defog, CHECK_ACTIVE twice for Strength.
-- CLEAR_ACTIVE is never used from a script -- the C clears them -- but it is a
-- sub-function the opcode defines, so the handler answers it.
local function fieldMoveFlag(which)
  return function(ins, s)
    emit(s, { "g4_field_move_flag", which, ins.args[1], ins.args[2] })
  end
end
L.dostrengthfunc = fieldMoveFlag("strength")
L.doflashfunc = fieldMoveFlag("flash")
L.dodefogfunc = fieldMoveFlag("defog")

-- ---------------------------------------------------------------------------
-- SAVING
-- ---------------------------------------------------------------------------
--
-- `scripts_common.s` holds the whole save dialogue, and twelve of its
-- commands had no row here, so every one of the eighteen `callcommonscript
-- 2006` sites in Sinnoh ran into an unlowered command -- and so did the START
-- menu's SAVE and the Underground descent, which reach the same file from C
-- (`start_menu.c:1327` and `field_map_change.c:1175` both start
-- `SCRIPT_ID(COMMON_SCRIPTS, 5)`).
--
-- They are lowered as a group because they only make sense as one: the two
-- `checksavetype` calls decide which of the five save messages the player
-- reads, and a handler that answered any of them wrongly would put the wrong
-- text on screen without failing anything.  `src/script/Gen4Save.lua` holds
-- the model and says why each answer is what it is.
--
-- `checksavetype <destVar>` -- 0 overwrite-blocked, 1 first save, 2 full,
-- 3 quick.  Called twice: once before the "would you like to save?" prompt to
-- catch the blocked case, once after to pick the message.
L.checksavetype = function(ins, s) emit(s, { "g4_check_save_type", ins.args[1] }) end

-- `trysavegame <destVar>` -- the write.  `ScrCmd_TrySaveGame` is
-- `FieldSystem_Save`, which stamps the player's position and sends the Poketch
-- its SAVE event before `SaveData_Save`, and answers 1 for SAVE_RESULT_OK and
-- 0 for anything else.  `CommonScript_SaveComplete` branches on that zero
-- straight into `CommonScript_SaveError`.
L.trysavegame = function(ins, s) emit(s, { "g4_try_save_game", ins.args[1] }) end

-- `storesaveresult <var>` -- the only way the CALLER learns what happened.
-- `ScrCmd_StoreSaveResult` writes the var through a pointer the script was
-- started with, and both C callers pass one: the START menu reads it to decide
-- whether to show its "saved" state, and the Underground descent reads it to
-- decide whether to descend at all.  A script started without one ignores the
-- write, which is why the handler tolerates no destination.
L.storesaveresult = function(ins, s) emit(s, { "g4_store_save_result", ins.args[1] }) end

-- `showsavingicon` / `hidesavingicon` -- `Window_AddWaitDial`, the spinner in
-- the corner of the message box while the write runs.  A pair, so both halves
-- are stated: pass 169's lesson was that a `close` with no `open` cannot be
-- made truthful after the fact.
L.showsavingicon = function(_, s) emit(s, { "g4_saving_icon", 1 }) end
L.hidesavingicon = function(_, s) emit(s, { "g4_saving_icon", 0 }) end

-- `waitabpresstime <frames>` -- wait for A or B, but no longer than N frames.
-- `CommonScript_SaveComplete` uses it for the 30-frame hold on "<player> saved
-- the game." after the jingle, so the line is readable whether or not the
-- player presses anything.
L.waitabpresstime = function(ins, s) emit(s, { "g4_wait_ab_press_time", ins.args[1] }) end

-- `opensaveinfo` / `closesaveinfo` -- the panel above the message box with the
-- location, the player's name, the badges, the Pokedex count and the clock.
-- Three `closesaveinfo` uses and one `opensaveinfo`, because the panel is
-- opened once and closed on each of the three ways out (saved, cancelled,
-- errored).
--
-- `ScrCmd_OpenSaveInfo` draws nothing when `SaveData_OverwriteCheck` holds,
-- which is the case this port does not have; see Gen4Save.overwriteBlocked.
L.opensaveinfo = function(_, s) emit(s, { "g4_save_info", 1 }) end
L.closesaveinfo = function(_, s) emit(s, { "g4_save_info", 0 }) end

-- 0x258 / 0x259 -- UNNAMED IN POKEPLATINUM AND NOT A MYSTERY.  `ScrCmd_258` is
-- `ov5_021E1000`, which is `ov5_021E0F54(fieldSystem, PLAYER_TRANSITION_SAVE)`:
-- it puts the player avatar into the save pose and keeps it there as a task.
-- `ScrCmd_259` is `ov5_021E100C`, which ends the task and requests the walking
-- state back.  `CommonScript_StartSave` brackets the write with them.
--
-- Note the guard in the C: `ov5_021E0F54` returns NULL unless the player is
-- PLAYER_AVATAR_WALKING, so saving from a bike or from the water poses nothing
-- -- and `ov5_021E0FC0` returns immediately on a NULL task, so the close is a
-- no-op in exactly the same cases.  The handler keeps that pairing.
L["258"] = function(_, s) emit(s, { "g4_save_pose", 1 }) end
L["259"] = function(_, s) emit(s, { "g4_save_pose", 0 }) end

-- `saveextradata` / `checkismiscsaveinit` -- the Frontier-records and
-- battle-video sectors.  `CommonScript_SaveExtraBlock` calls the first behind
-- `FLAG_MAP_LOCAL_SAVE_EXTRA_BLOCK` and `CommonScript_QuickSaveCheckMiscFlag`
-- reads the second to turn the first quick save into a full one.  Gen4Save
-- says what survives the port and what does not.
L.saveextradata = function(_, s) emit(s, { "g4_save_extra_data" }) end
L.checkismiscsaveinit = function(ins, s)
  emit(s, { "g4_misc_save_init", ins.args[1] })
end

-- ---------------------------------------------------------------------------
-- THE PC
-- ---------------------------------------------------------------------------
--
-- `CommonScript_PC` is reached from the tile behaviour rather than from any
-- object or bg event (`Field_TileBehaviorToScript` -> COMMON_SCRIPTS 18), and
-- this port had no Gen 4 arm for that dispatch at all -- see
-- src/world/Gen4TileScripts.lua.  With the dispatch in place these six are
-- what the script runs into.
--
-- `loadpcanimation` / `playpcbootupanimation` / `playpcshutdownanimation`:
-- the PC's screen lighting up and going dark.  `FieldSystem_LoadPCAnimation`
-- (overlay006/pc_animation.c) finds the loaded MAP PROP whose model is one of
-- four PC models -- `pokecenter_pc_nsbmd` and the three desk laptops -- and
-- hands its prop animations to the one-shot manager under a tag; the other two
-- play animation 0 and animation 1 of that tag.
--
-- THIS IS THE DOOR ANIMATION AGAIN, exactly: an NSBCA one-shot on an NSBMD map
-- prop.  Same three missing stages (this port reads NSBMD and not NSBCA, bakes
-- the ground's props into a flat canvas, and has no Gen 4 SE bank), so it
-- takes the SAME named no-op rather than a fourth spelling of the same
-- absence.  The sound the script plays either side of them is a separate
-- command and is already lowered.
L.loadpcanimation = function(_, s) emit(s, { "g4_noop", "prop animations" }) end
L.playpcbootupanimation = function(_, s) emit(s, { "g4_noop", "prop animations" }) end
L.playpcshutdownanimation = function(_, s) emit(s, { "g4_noop", "prop animations" }) end

-- `savetvsegmentpokemonstoragebulletin` -- files a TV segment about the
-- player's party after a visit to the storage system.  Same answer as
-- `savetvsegmenthiddenitem` and now the same ROW: there is no TV broadcast
-- system in this engine, so the segment is recorded nowhere and nothing would
-- read it if it were.  One statement of that, not two.
L.savetvsegmentpokemonstoragebulletin = function(_, s)
  emit(s, { "g4_save_tv_segment", "pokemon_storage_bulletin" })
end

-- `checkismiscsaveinit`'s neighbour in spirit: `checkishalloffamecorrupted
-- <destVar>` answers whether the Hall of Fame block failed its checksum.
L.checkishalloffamecorrupted = function(ins, s)
  emit(s, { "g4_hall_of_fame_corrupted", ins.args[1] })
end

-- `openpchalloffamescreen` -- the post-game record browser.
L.openpchalloffamescreen = function(_, s) emit(s, { "g4_open_hall_of_fame" }) end
L.buffermapname = function(ins, s)
  emit(s, { "g4_buffer_map_name", ins.args[1], ins.args[2] })
end
-- `bufferspeciesnamefromvar <slot> <var> <?> <?>`: the species is the SECOND
-- operand and the last two select a form/gender the port does not draw into a
-- name, so only the first two are read.
L.bufferspeciesnamefromvar = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "species", ins.args[2] })
end
-- THE TRAINER CARD'S APPEARANCE, which is what the cartridge derives a
-- trainer's CLASS from (`Appearance_CalculateFromTrainerInfo`).  This port has
-- no appearance system -- see `loadtrainerappearances` above, which is already
-- a noop for the same reason -- so the calculation writes the zero its reader
-- then falls back on, and the setter has nothing to set.
L.calculatetrainerinfoappearance = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "trainer appearance variants" })
end
L.settrainerinfoappearance = function(_, s)
  emit(s, { "g4_noop", "trainer appearance variants" })
end
-- SWARMS: the daily roaming-species table, which needs a daily-reset system
-- this port does not run for Gen 4.  `getswarmmapandspecies` writes TWO vars
-- and both must be written, or the comparison behind either reads the last
-- command's answer.
L.enableswarms = function(_, s) emit(s, { "g4_noop", "daily swarms" }) end
L.getswarmmapandspecies = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "daily swarms" })
  emit(s, { "g4_no_feature", ins.args[2], "daily swarms" })
end
-- ...AND THE ROAMERS ARE NOT SWARMS, though they sit next to them in the
-- opcode table and in `special_encounter.h`.
--
-- `activateroamingpokemon <slot>` -- one BYTE, and it is the command that
-- RELEASES one. Eight sites over three maps: ETERNA CITY'S SOUTH HOUSE (slots
-- 3, 4, 5 -- Moltres, Zapdos, Articuno, twice each), FULLMOON ISLAND (slot 1,
-- Cresselia) and VERITY CAVERN (slot 0, MESPRIT -- which is main-path, the
-- moment you look into Lake Verity's water).
--
-- Unlowered, the release did nothing and every rule behind it had nothing to
-- act on: no roamer, no movement, no encounter, nothing on the Marking Map.
-- Slot 2 is DARKRAI and no script activates it -- that is the Member's Card.
--
-- The rules are Platinum's own and they are NOT Gen 2's or Gen 3's with
-- different numbers; src/world/Gen4Roamers.lua has the comparison table and
-- the two things I got wrong reading it from memory.
L.activateroamingpokemon = function(ins, s)
  emit(s, { "g4_release_roamer", ins.args[1] })
end


-- ---------------------------------------------------------------------------
-- CHAPTER FOUR -- Eterna to Veilstone (271 roots, 835 blocks)
-- ---------------------------------------------------------------------------

-- THE CYCLING ROAD, which is the only thing in this chapter that could stop a
-- player leaving Eterna.  See `g4_check_on_bike` for the gate's own script.
L.checkplayeronbike = function(ins, s)
  emit(s, { "g4_check_on_bike", ins.args[1] })
end
L.forcebicycling = function(ins, s) emit(s, { "g4_force_bike", ins.args[1] }) end
L.setcyclingbgm = function(_, s)
  emit(s, { "g4_noop", "the cycling BGM override" })
end
L.getpreviousmapid = function(ins, s)
  emit(s, { "g4_previous_map", ins.args[1] })
end

-- PARTY QUERIES, AND THE DESTINATION IS THE FIRST OPERAND ON THREE OF THEM --
-- the opposite of the way they read aloud.  `getpartymonfriendship` is 143
-- sites across the cartridge, the third commonest unlowered command there was.
L.getpartymonfriendship = function(ins, s)
  emit(s, { "g4_mon_friendship", ins.args[1], ins.args[2] })
end
L.getpartymontype = function(ins, s)
  emit(s, { "g4_mon_types", ins.args[1], ins.args[2], ins.args[3] })
end
L.checkpartymonhasmove = function(ins, s)
  emit(s, { "g4_mon_has_move", ins.args[1], ins.args[2], ins.args[3] })
end
L.getfirstnonegginparty = function(ins, s)
  emit(s, { "g4_first_non_egg", ins.args[1] })
end
-- ...and this one puts the destination SECOND, which is why they are lowered
-- one at a time against `scrcmd_party.c` rather than by pattern.
L.checkpartyhasspecies2 = function(ins, s)
  emit(s, { "g4_party_has_species2", ins.args[1], ins.args[2] })
end

L.startwildbattle = function(ins, s)
  emit(s, { "g4_start_wild_battle", ins.args[1], ins.args[2] })
end
L.getnationaldexseencount = function(ins, s)
  emit(s, { "g4_national_dex_seen", ins.args[1] })
end
L.getselectedpartyslot = function(ins, s)
  emit(s, { "g4_selected_party_slot", ins.args[1] })
end

-- `bufferitemnamewitharticle` -- bank 393, the item names with their articles
-- already attached, exactly like the species bank 413 above.
L.bufferitemnamewitharticle = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "bank:393", ins.args[2] })
end

-- EVERY SINNOH GYM PUZZLE IS A RUNTIME OVERLAY, NOT MAP COLLISION.
--
-- Measured on three gyms now, not assumed from one.  Dumping each gym's own
-- permission grid gives behaviour NONE everywhere plus its warps and NOT ONE
-- blocked or dynamic-collision cell:
--
--     Eterna    header 67  matrix 220  chunk 294   775 open, 1 warp
--     Hearthome header 88  matrix 222  chunk 230   (entrance + trainer rooms)
--     Veilstone header 133 matrix 115  chunk 235
--     2,504 open cells across the three, 3 warp entrances, 1 warp panel
--
-- Gardenia's rotating flower clock, Fantina's quiz doors and Maylene's
-- punching bags all live in `PersistedMapFeatures` and the gym_features
-- overlay, which this port does not have.  So the puzzles are ABSENT, not
-- impassable: every one of these gyms can be crossed by walking at the leader.
-- That is a fidelity gap on the tracker and it is NOT a stall, and only the
-- measurement tells the two apart.
L.initpersistedmapfeaturesforhearthomegym = function(_, s)
  emit(s, { "g4_noop", "the Hearthome Gym persisted map feature" })
end
L.initpersistedmapfeaturesforveilstonegym = function(_, s)
  emit(s, { "g4_noop", "the Veilstone Gym persisted map feature" })
end

-- ---------------------------------------------------------------------------
-- SIDE SYSTEMS THIS PORT DOES NOT HAVE
-- ---------------------------------------------------------------------------
--
-- Grouped by the feature they belong to rather than by opcode, because that is
-- how they will be built: each block below is one absent system, and every
-- var-writer in them still writes, because an unlowered one leaves the
-- comparison register holding the previous command's answer.

-- THE UNDERGROUND (the Sinnoh Underground and its goods PC).
L.checkhasroomforgoodsinpc = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[3], "the Underground goods PC" })
end
L.sendgoodtopc = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[3], "the Underground goods PC" })
end
L.getundergroundfossilsunearthed = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the Underground" })
end
L.getundergrounditemsgivenaway = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the Underground" })
end
L.getundergroundtrapsset = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the Underground" })
end
L.getundergroundtalkcounter = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the Underground" })
end
-- The names ARE in the cache even though the system is not: bank 626 plain,
-- 627 with articles (checked, because the line-number rule puts 627 on the
-- WITH_ARTICLES row and it was worth confirming which way round they sit).
L.bufferundergroundgoodsname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "bank:626", ins.args[2] })
end
L.bufferundergroundgoodsnamewitharticle = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "bank:627", ins.args[2] })
end

-- CONTESTS, which is also all that is left in chapters two and three.
L.addcontestbackdrop = function(_, s) emit(s, { "g4_noop", "contest backdrops" }) end
-- `buffercontestantmonname` is deliberately LEFT UNLOWERED: a contestant is a
-- live entrant, not a table row, so there is no bank to read and filling the
-- slot with a blank would hide an absent system instead of reporting it.
L.contestphotohasdata = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "contest photos" })
end
L.checkhasemptypoffincaseslot = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the poffin case" })
end

-- ACCESSORIES (the contest dress-up items).
L.addaccessory = function(_, s) emit(s, { "g4_noop", "contest accessories" }) end
L.canfitaccessory = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[3], "contest accessories" })
end
L.bufferaccessoryname = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "bank:386", ins.args[2] })
end
L.bufferaccessorynamewitharticle = function(ins, s)
  emit(s, { "g4_buffer", ins.args[1], "bank:387", ins.args[2] })
end

-- THE MOVE TUTOR at Grandma Wilma's house on Route 210.
L.openmovetutormenu = function(_, s) emit(s, { "g4_noop", "the move tutor" }) end
L.selectmovetutorpokemon = function(_, s)
  emit(s, { "g4_noop", "the move tutor" })
end
L.checklearnedtutormove = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the move tutor" })
end

-- AMITY SQUARE's berry-and-accessory man.
L.clearamitysquarestepcount = function(_, s)
  emit(s, { "g4_noop", "the Amity Square step count" })
end
L.getamitysquarestepcount = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the Amity Square step count" })
end
L.calcamitysquarefoundaccessory = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "Amity Square accessories" })
end
L.calcamitysquareberryandaccessorymanoptionid = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "Amity Square accessories" })
end
L.checkamitysquaremangiftisaccessory = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "Amity Square accessories" })
end
L.getamitysquareberryoraccessoryidfromman = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "Amity Square accessories" })
end

-- THE POKEMON NEWS PRESS at Solaceon.
L.getrandomseenspecies = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the Pokemon News Press" })
end
L.setnewspressdeadline = function(_, s)
  emit(s, { "g4_noop", "the Pokemon News Press" })
end
L.getnewspressdeadline = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the Pokemon News Press" })
end

-- ODDS AND ENDS, each read on its own.
L.changedeoxysform = function(_, s) emit(s, { "g4_noop", "Deoxys forms" }) end
L.addtogamerecord = function(ins, s)
  emit(s, { "g4_add_game_record", ins.args[1], ins.args[2], false })
end
L.addtogamerecordbigvalue = function(ins, s)
  emit(s, { "g4_add_game_record", ins.args[1], ins.args[2], true })
end
L.checkdaycarehasegg = function(ins, s)
  emit(s, { "g4_daycare_has_egg", ins.args[1] })
end
L.clearspiritombcounter = function(_, s)
  emit(s, { "g4_noop", "the Spiritomb counter (it needs the Underground)" })
end
L.getspiritombcounter = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the Spiritomb counter" })
end
-- FOUR MORE UNNAMED OPCODES, read one at a time as before.  `0A8` and `27C`
-- belong to the contest photo path (`0A8` writes a var, so it must); `338` and
-- `339` walk the map-object list in Amity Square and write nothing.
L["0a8"] = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "contest photos (scrcmd 0A8)" })
end
L["338"] = function(_, s) emit(s, { "g4_noop", "an object query (scrcmd 338)" }) end
L["339"] = function(_, s) emit(s, { "g4_noop", "an object query (scrcmd 339)" }) end


-- ---------------------------------------------------------------------------
-- CHAPTERS FIVE AND SIX -- Veilstone to Pastoria; Lake Valor to Canalave
-- ---------------------------------------------------------------------------

L.getoverworldweather = function(ins, s)
  emit(s, { "g4_overworld_weather", ins.args[1] })
end
L.getpartymonmove = function(ins, s)
  emit(s, { "g4_mon_move", ins.args[1], ins.args[2], ins.args[3] })
end
L.getpartymonmovecount = function(ins, s)
  emit(s, { "g4_mon_move_count", ins.args[1], ins.args[2] })
end
L.findpartyslotwithmove = function(ins, s)
  emit(s, { "g4_find_slot_with_move", ins.args[1], ins.args[2] })
end
L.openpokemonstorage = function(ins, s)
  emit(s, { "g4_storage", ins.args[1] })
end
L.slatherhoneytree=function(_,s) emit(s,{'g4_honey_slather'}) end
L.gethoneytreestatus=function(ins,s) emit(s,{'g4_honey_status',ins.args[1]}) end
L.starthoneytreebattle=function(_,s) emit(s,{'g4_honey_battle'}) end
L.stophoneytreeshaking=function(_,s) emit(s,{'g4_honey_stop'}) end
L.getpcboxesfreeslotcount = function(ins, s)
  emit(s, { "g4_pc_free_slots", ins.args[1] })
end
L.checkdidnotcapture = function(ins, s)
  emit(s, { "g4_did_not_capture", ins.args[1] })
end

-- ---------------------------------------------------------------------------
-- A CORRECTION: "every Sinnoh gym puzzle is a runtime overlay" WAS TOO STRONG
-- ---------------------------------------------------------------------------
--
-- That claim was made from three gyms (Eterna, Hearthome, Veilstone), all of
-- which measure as one open floor. Measuring the rest shows it is false for
-- three others, and the behaviour that makes the difference has a name:
--
--   behaviour 0x59 DYNAMIC_HEIGHT_COLLISION -- "ask the height system"
--
-- Censused over all 666 land chunks and 346,819 non-void cells:
--
--   942 cells, in 6 chunks, 0.272% of the world -- and NOWHERE ELSE:
--     chunk 225           C02GYM0101  Canalave gym        293 cells
--     chunks 223, 224     C06GYM0101  Pastoria gym        356 cells
--                                     + 10 H_GROUND, 6 M_GROUND, 10 L_GROUND
--     chunks 296, 297, 298  C08GYM0101/2/3  Sunyshore gym 293 cells
--
-- So: Eterna, Hearthome and Veilstone keep their whole puzzle in the
-- gym_features overlay, and Canalave, Pastoria and Sunyshore put PART of
-- theirs in the map -- Pastoria's three water levels even have behaviours of
-- their own.
--
-- WHAT THIS PORT DOES WITH IT: `Gen4Maps.mapDef` turns every non-void cell
-- into collision 0, so a DYNAMIC_HEIGHT_COLLISION cell is ordinary floor. The
-- gyms stay crossable -- still no stall -- but the player walks over water in
-- Pastoria and across the gaps in Canalave and Sunyshore instead of solving
-- them.
--
-- The blast radius is exactly those three gyms. The behaviour never appears on
-- a route, in a cave or in a building, so treating it as floor cannot let a
-- player walk off a cliff anywhere else -- which is the question worth asking
-- before leaving it alone, and the census is what answers it.
L.initpersistedmapfeaturesforpastoriagym = function(_, s)
  emit(s, { "g4_noop", "the Pastoria Gym water level (its cells read as floor here)" })
end
L.initpersistedmapfeaturesforcanalavegym = function(_, s)
  emit(s, { "g4_noop", "the Canalave Gym sliding floor (its cells read as floor here)" })
end
L.presspastoriagymbutton = function(_, s)
  emit(s, { "g4_noop", "the Pastoria Gym water-level button" })
end

-- THE GREAT MARSH / SAFARI GAME, one absent system.
L.startendsafarigame = function(_, s) emit(s, { "g4_noop", "the Great Marsh safari game" }) end
L.startgreatmarshlookout = function(_, s)
  emit(s, { "g4_noop", "the Great Marsh lookout" })
end
L.getcurrentsafarigamecaughtnum = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the Great Marsh safari game" })
end
-- !! `setspeciallocation` IS THE LIFT, AND THIS USED TO THROW IT AWAY.
--
-- The comment here read "it stamps the MET LOCATION on what you catch in the
-- marsh" and the row lowered to a noop. The slot has four readers in the
-- cartridge and the met location is not one of them; the one that matters is
-- `field_control.c` 1011, where a warp with destHeaderID 0xfff and destWarpID
-- 0x100 takes its destination FROM THIS SLOT. Six warps carry that pair and
-- all six are lift cars, so the lift scripts were writing a floor into a
-- command that discarded it: EVERY LIFT IN SINNOH WAS A DEAD END, for two
-- lines of comment. See src/import/Gen4Elevators.lua for the whole of it.
--
-- `setspeciallocation <mapHeaderID> <warpId> <x> <z> <faceDirection>` -- the
-- five fields of a `Location`, in that order, all var-or-literal, writing no
-- var. OPERAND 2 IS A WARP INDEX, not an x: `setspeciallocation 14 1 18 2 1`
-- is header 14, warp 1, (18, 2), facing south, and the Veilstone store's
-- middle floors say warp 2 where its ends say warp 1. The coordinates are
-- overwritten from that warp whenever it is not WARP_ID_NONE.
L.setspeciallocation = function(ins, s)
  emit(s, { "g4_special_location", ins.args[1], ins.args[2], ins.args[3],
            ins.args[4], ins.args[5] })
end
-- `getfloorsabove <destVar>` -- `FieldMenu_GetFloorsAbove(specialLocation)`, so
-- it answers about the floor you GOT ON AT and not the car you are standing
-- in. A var-writer, and the panel branches on it six ways.
L.getfloorsabove = function(ins, s)
  emit(s, { "g4_floors_above", ins.args[1] })
end
-- `bufferfloornumber <slot> <floor>` -- `StringTemplate_SetFloorNumber`, both
-- operands BYTES, and the second is an index where ZERO IS THE BASEMENT.
L.bufferfloornumber = function(ins, s)
  emit(s, { "g4_buffer_floor", ins.args[1], ins.args[2] })
end
-- `checkisdepartmentstoreregular <destVar>` -- the buy counter against five.
L.checkisdepartmentstoreregular = function(ins, s)
  emit(s, { "g4_store_regular", ins.args[1] })
end
-- `showcurrentfloor <left> <top> <var> <unused>` is the little "Current Floor
-- / 3F" window in the corner of the panel, and THE VAR IS AN INPUT even though
-- the operand is a var POINTER: the window's own task watches it and closes
-- when it turns 0xFFFF, which is what the lift's `setvar VAR_ELEVATOR_..., -1`
-- three lines later is for. So this is the one var-pointer operand in the file
-- that must NOT be written -- `g4_no_feature` would zero the floor count the
-- panel is about to branch on.
--
-- The window itself is a HUD this port does not draw, the same call this file
-- already makes for the money box. Nothing is lost by it: the window's two
-- lines are bank 361 entries 15 "Current Floor" and 16 "{STRVAR_1}", and the
-- string it interpolates is filled by `bufferfloornumber` above whether or not
-- anything draws it.
L.showcurrentfloor = function(_, s)
  emit(s, { "g4_noop", "the lift's current-floor window" })
end
-- `playelevatoranimation <direction> <loops>` -- the car rocking, with
-- `direction` an ELEVATOR_DIR_UP/DOWN out of a var. There is no elevator
-- cutscene in this port and one is not faked; the lift still takes you to the
-- floor, it just arrives without the ride.
L.playelevatoranimation = function(_, s)
  emit(s, { "g4_noop", "the elevator animation" })
end

-- THE SHARD MOVE TUTOR in the Route 212 house, one absent system. Its
-- var-writers must still write: `checkcanaffordmove` answering a leftover
-- would let a script charge for a move it never taught.
L.checkcanaffordmove = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "the shard move tutor" })
end
L.checkhaslearnabletutormoves = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[3], "the shard move tutor" })
end
L.getsummaryselectedmoveslot = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[1], "the shard move tutor" })
end
L.opensummaryscreenteachmove = function(_, s)
  emit(s, { "g4_noop", "the shard move tutor" })
end
L.showmovetutormoveselectionmenu = function(_, s)
  emit(s, { "g4_noop", "the shard move tutor" })
end
L.resetmoveslot = function(_, s) emit(s, { "g4_noop", "the shard move tutor" }) end
L.payshardcost = function(_, s) emit(s, { "g4_noop", "the shard move tutor" }) end

-- THE DEX MILESTONES, none of which this port tracks per-region or per-form.
L.getunownformsseencount = function(ins, s)
  emit(s, { "g4_unown_forms_seen", ins.args[1] })
end
L.checknationaldexcompleted = function(ins, s)
  emit(s, { "g4_dex_complete", ins.args[1], true })
end
L.getnationaldexcaughtcount=function(ins,s) emit(s,{'g4_dex_caught_count',ins.args[1],true}) end
L.getlocaldexcaughtcount_unused=function(ins,s) emit(s,{'g4_dex_caught_count',ins.args[1],false}) end
L.checkgamecompleted = function(ins, s)
  emit(s, { "g4_game_completed", ins.args[1] })
end
L.setgamecompleted = function(_, s) emit(s, { "g4_set_game_completed" }) end
L.turnonpokedexformdetection = function(_, s)
  emit(s, { "g4_enable_dex_form_detection" })
end
L.showdiplomasinnoh = function(_, s) emit(s, { "g4_noop", "the Sinnoh diploma" }) end
L.showdiplomanationaldex = function(_, s)
  emit(s, { "g4_noop", "the National Dex diploma" })
end

-- PRESENTATION, and the reason each is a no-op is its own.
L.stopse = function(ins, s) emit(s, { "g4_stop_sound", ins.args[1] }) end
-- Canalave's library television and the boat cutscene are both scripted
-- set-pieces with their own screens; the scripts around them continue.
L.startlibrarytv = function(_, s) emit(s, { "g4_noop", "the Canalave library TV" }) end
L.playboatcutscene = function(_, s) emit(s, { "g4_noop", "the boat cutscene" }) end
-- `2b5 <map> <x> <z>` is `FieldOverworldState_SetExitLocation` -- where a
-- dungeon puts you back out. It writes no var; the port's own `lastOutdoor`
-- already answers the same question for the warps it handles.
L["2b5"] = function(_, s) emit(s, { "g4_noop", "the stored exit location (scrcmd 2B5)" }) end
-- `29f` reads one var and returns without writing anything.
L["29f"] = function(_, s) emit(s, { "g4_noop", "a cartridge no-op (scrcmd 29F)" }) end


-- ---------------------------------------------------------------------------
-- CHAPTERS SEVEN AND EIGHT -- and the end of the game
-- ---------------------------------------------------------------------------

-- THE HALL OF FAME. `cleargame` is `ClearGame(task)`: the induction, the
-- credits, the autosave and the return to the title. The port has had that
-- whole flow since Gen 1 as `record_hall_of_fame` -- Gen 2 lowers its own
-- `HallOfFame` special to the same verb -- so the last three rows of the
-- Sinnoh story are one line.
L.cleargame = function(_, s)
  emit(s, { "g4_prepare_hall_of_fame" })
  emit(s, { "record_hall_of_fame" })
end
L.playhalloffamehealinganimation = function(_, s)
  emit(s, { "g4_noop", "the Hall of Fame healing animation" })
end

-- !! CORRECTED. These two were briefly lowered to the port's `g4_show_object`
-- and `g4_hide_object` on the reading that `DistWorld_AddMapObjectWithLocalID`
-- merely spawns an object the map already carries. IT DOES NOT, and the check
-- that settled it was to look at the map:
--
--   Distortion World 1F  (header 573, events member 524):  0 objects
--   Distortion World B1F (header 574, events member 0):    0 objects
--
-- The map's event table is EMPTY. `AddMapObjectWithLocalID` walks
-- `sMapObjectEvents`, a table inside OVERLAY 9, and the 42 ids it holds start
-- at DIST_WORLD_MAP_OBJECT_BASE_LOCAL_ID = 128 and are named CYNTHIA_PORTAL,
-- CYNTHIA_ELEVATOR, MESPRIT, CYRUS, UXIE, AZELF and the boulder-pit triggers.
--
-- So these are the Distortion World's CAST, not its platforms, and they live
-- in an overlay this port does not extract. Pointing them at show/hide asks
-- the overworld for local id 128 on a map whose object list is empty: it finds
-- nothing and says so, once per id. A no-op is the honest lowering until
-- `sMapObjectEvents` is extracted, which is the real fix and is on the tracker.
L.adddistortionworldmapobject = function(_, s)
  emit(s, { "g4_noop", "a Distortion World cast member (its table is in overlay 9)" })
end
L.deletedistortionworldmapobject = function(_, s)
  emit(s, { "g4_noop", "a Distortion World cast member (its table is in overlay 9)" })
end
L.initpersistedmapfeaturesfordistortionworld = function(_, s)
  emit(s, { "g4_noop", "the Distortion World persisted map feature" })
end
L.finishdistortionworldgiratinashadowevent = function(_, s)
  emit(s, { "g4_noop", "the Giratina shadow event" })
end
L.dodwwarp = function(_, s) emit(s, { "g4_noop", "the Distortion World warp" }) end
L.setpartygiratinaform = function(_, s)
  emit(s, { "g4_noop", "Giratina's forms" })
end

L.getbattleresult = function(ins, s)
  emit(s, { "g4_get_battle_result", ins.args[1] })
end
L.checkpartyhashelditem = function(ins, s)
  emit(s, { "g4_party_has_held_item", ins.args[1], ins.args[2] })
end
L.setspeciesseen = function(ins, s)
  emit(s, { "g4_set_species_seen", ins.args[1] })
end
-- `waitabpadpress` pauses until A or B. Gen 3 lowers its own `waitbuttonpress`
-- to nothing for the reason that applies here too: this port's text boxes
-- already wait for the button themselves, so a second wait with no box on
-- screen is a hang rather than a pause.
L.waitabpadpress = function(_, s) emit(s, { "g4_noop", "a wait for A or B" }) end

-- THE PLATFORM LIFTS, and why they are NOT a blocker even though they first
-- looked like one.
--
-- IRON ISLAND FIRST. B1F-right, B2F-left and B3F each split into two connected
-- components, which reads like a wing the player cannot reach. It is not:
-- dumping B3F cell by cell, component 2 is the ROOM -- 150 CAVE_FLOOR cells and
-- its three warps, east, west and north -- and component 1 is 606 cells of
-- behaviour NONE, the map's unused surround. The room is entered and left by
-- warp and is walkable throughout.
--
-- `PlatformLift_Trigger` moves a platform between two FLOOR HEIGHTS in the
-- same room; it is a height feature, and this port walks without height. So
-- the lift is scenery here, not a gate.
--
-- A COMPONENT COUNT IS NOT A MEASUREMENT. What the components CONTAIN is --
-- which is the difference between this no-op and the Distortion World above.
--
-- !! AND THAT ARGUED THREE OF THE NINE. There are SIX MORE in the POKEMON
-- LEAGUE -- the four Elite Four elevators, Cynthia's elevator and the
-- Champion's room -- and this no-op has covered them since the day it was
-- written without one of them being looked at. That is the department-store
-- lifts' mistake exactly: a note that is right about what it examined and
-- silent about the rest of what it decides.
--
-- MEASURED, in the permission grid, for all six: each room is a SHAFT with a
-- warp in the wall at the top (behaviour 0x6E) and a warp on the floor at the
-- bottom, and THE COLUMN BETWEEN THEM IS OPEN FLOOR END TO END -- 13/13, 13/13,
-- 13/13, 13/13, 21/21 and 16/16 tiles of behaviour 0 with no collision bit. The
-- Elite Four are reachable in order without the lift, and Cynthia's room ends
-- in an explicit `Warp` to the Hall of Fame hallway rather than in the
-- platform. See src/import/Gen4PlatformLifts.lua.
L.triggerplatformlift = function(_, s)
  emit(s, { "g4_noop", "the platform lift (all nine rooms are walkable without it)" })
end
L.initpersistedmapfeaturesforplatformlift = function(_, s)
  emit(s, { "g4_noop", "the platform lift persisted map feature" })
end
-- ...BUT THE QUESTION THE SLOT IS ASKED IS ANSWERABLE, and an unlowered
-- var-writer is the dangerous kind -- this is the fifth time that sentence has
-- been needed. `checkplatformliftnotusedwhenenteredmap <destVar>` has five
-- sites, all five League elevator rooms, and the `gotoif` behind it gates the
-- room's own coord event through VAR_MAP_LOCAL_0x00.
--
-- The answer is DID YOU COME IN AT THE BOTTOM:
-- `PersistedMapFeatures_InitForPlatformLift` sets the flag TRUE and clears it
-- only in the six League cases, only when the arrival z is not the room's
-- bottom-floor warp z. Iron Island never clears it.
--
-- SAID PLAINLY: nothing a player sees changes today, because the trigger this
-- gates is the no-op above. What changes is that the slot is truthful for the
-- height work and the var stops holding the previous comparison.
L.checkplatformliftnotusedwhenenteredmap = function(ins, s)
  emit(s, { "g4_platform_lift_bottom", ins.args[1] })
end

-- SUNYSHORE'S GEAR GYM, which is one of the three that carry
-- DYNAMIC_HEIGHT_COLLISION cells (293 of them, chunks 296-298) -- so like
-- Canalave and Pastoria its floor reads as ordinary ground here and the puzzle
-- is absent rather than impassable.
L.presssunyshoregymbutton = function(_, s)
  emit(s, { "g4_noop", "the Sunyshore Gym gear button" })
end
L.initpersistedmapfeaturesforsunyshoregym = function(_, s)
  emit(s, { "g4_noop", "the Sunyshore Gym persisted map feature" })
end

-- `pokemartseal <martID>` -- `SunyshoreMarketDailyStocks[martID]` with
-- MART_TYPE_SEAL. THE SAME SHAPE AS `pokemartspecialties` AND REFUSED FOR THE
-- SAME REASON: it indexes a second stock table that is not extracted, and
-- seals are a ball-decoration system this port does not have. 35 sites, all of
-- them Sunyshore. Opening a common mart in its place would sell Potions under
-- a seal sign.
L.pokemartseal = function(ins, s) emit(s, { "g4_pokemart", ins.args[1], "seal" }) end

-- THE LAKE GUARDIAN CONTAINMENT UNITS in the Galactic HQ control room, the
-- Spear Pillar set-pieces, and the rest -- each read on its own.
L.initlakeguardiancontainmentunits = function(_, s)
  emit(s, { "g4_noop", "the lake guardian containment units" })
end
L.deactivatelakeguardiancontainmentunits = function(_, s)
  emit(s, { "g4_noop", "the lake guardian containment units" })
end
L.sethiddenlocation = function(_, s)
  emit(s, { "g4_noop", "a hidden location marker" })
end
-- !! THE DESTINATION IS OPERAND 1, AND THIS PASSED OPERAND 2.
-- `checkpartyhasfatefulencounterregigigas` takes ONE operand and pret reads it
-- with `GetVarPointer` -- it is the destination. Passing args[2] handed the
-- command NIL, so nothing was written at any of its 9 sites and the `gotoif`
-- behind each one branched on the previous command's answer. Caught by comparing
-- pret's operand KINDS against the arg indices this file passes.
L.checkpartyhasfatefulencounterregigigas = function(ins, s)
  emit(s, { "g4_fateful_regigigas", ins.args[1] })
end
-- `noop` is named that on the cartridge too.
L.noop = function(_, s) emit(s, { "g4_noop", "a cartridge no-op" }) end
-- FOUR MORE UNNAMED COMMANDS, and reading them one at a time paid for itself:
-- THREE ARE NO-OPS AND ONE WRITES A VAR.
--
--   18C  GetVar localID, GetVar dir        -- writes nothing
--   2B6  GetVar localID, ReadByte          -- writes nothing
--   2FB  no operands at all                -- writes nothing
--   20D  ReadByte, then GetVarPointer      -- WRITES A VAR
--
-- A first pass had all four as no-ops on the strength of "they are set-piece
-- effects". The grep that produced that had landed on a NEIGHBOURING function
-- for two of them -- `ScrCmd_2FB` reads nothing, but the lines under it belong
-- to `ScrCmd_CheckABPress`, which does. Matching each definition exactly is
-- what separated them, and 20D would have left its five Spear Pillar sites
-- branching on the previous command's answer.
L["18c"] = function(_, s) emit(s, { "g4_noop", "a Spear Pillar effect (scrcmd 18C)" }) end
L["2fb"] = function(_, s) emit(s, { "g4_noop", "a Spear Pillar cue (scrcmd 2FB)" }) end
L["2b6"] = function(_, s) emit(s, { "g4_noop", "an Iron Island cue (scrcmd 2B6)" }) end
L["20d"] = function(ins, s)
  emit(s, { "g4_no_feature", ins.args[2], "a Spear Pillar effect (scrcmd 20D)" })
end


L.getgameversion = function(ins, s) emit(s, { "g4_game_version", ins.args[1] }) end
L.getleaguevictories = function(ins, s)
  emit(s, { "g4_league_victories", ins.args[1] })
end
L.getpartymonevtotal = function(ins, s)
  emit(s, { "g4_mon_ev_total", ins.args[1], ins.args[2] })
end
L.getpartymonribbon = function(ins, s)
  emit(s, { "g4_get_mon_ribbon", ins.args[1], ins.args[2], ins.args[3] })
end
L.setpartymonribbon = function(ins, s)
  emit(s, { "g4_set_mon_ribbon", ins.args[1], ins.args[2] })
end
-- `showobject` / `hideobject` are the OTHER pair -- `MapObjMan_LocalMapObjByIndex`
-- then a visibility flag, where `addobject`/`removeobject` add and delete. The
-- port's show and hide do exactly this, and the add/delete pair was already
-- pointed at them; these two were simply never lowered.
L.showobject = function(ins, s) emit(s, { "g4_show_object", ins.args[1] }) end
L.hideobject = function(ins, s) emit(s, { "g4_hide_object", ins.args[1] }) end
L.resetdistortionworldpersistedcameraangles = function(_, s)
  emit(s, { "g4_noop", "the Distortion World camera angles" })
end
L.setsubscene63 = function(_, s) emit(s, { "g4_noop", "a subscene change" }) end

-- `startgiratinaoriginbattle <species> <level>` is `Encounter_NewVsGiratinaOrigin`
-- -- the same call shape as `startlegendarybattle` with the Origin Forme set
-- on the way in. This port models no forms (see `setpartygiratinaform`, a
-- no-op just above), so it fights the species it is handed, which is the same
-- Pokemon in its other shape.
L.startgiratinaoriginbattle = function(ins, s)
  emit(s, { "g4_legendary_battle", ins.args[1], ins.args[2] })
end
L.startdistortionworldgiratinashadowevent = function(_, s)
  emit(s, { "g4_noop", "the Giratina shadow event" })
end

function Gen4ScriptVM.lower(instructions, state)
  local s = state or {}
  s.out = s.out or {}
  s.newLabel = s.newLabel or (function()
    local n = 0
    return function() n = n + 1; return ("R%04d"):format(n) end
  end)()
  for _, ins in ipairs(instructions or {}) do
    local handler = L[ins.name]
    if handler then
      handler(ins, s)
    elseif ins.variable then
      emit(s, { "g4_unimplemented", ins.name, "variable length" })
    else
      emit(s, { "g4_unimplemented", ins.name })
    end
  end
  return s.out
end

return Gen4ScriptVM
