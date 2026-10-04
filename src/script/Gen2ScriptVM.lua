-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Gen2 script VM.
--
-- data/generated/map_scripts.lua holds the ROM's own bytecode, disassembled by
-- src/import/RomExtractorGen2.lua: one flat pool of scripts keyed by
-- S<bank>_<addr>, one pool of applymovement data keyed by M<bank>_<addr>, and
-- a per-map index of scenes, callbacks, coord events and object scripts.
--
-- compile() lowers a script and everything it can reach into a single
-- ScriptRunner row list.  Because the ROM's `scall` is a real call, the lowered
-- form keeps a return stack (g2_call / g2_return in Gen2Commands) rather than
-- inlining, so a shared subroutine appears once no matter how many callers it
-- has.
--
-- Anything the port has no equivalent for lowers to nothing at all: an
-- unrecognised command is skipped, which degrades a scene rather than killing
-- the script.  register() therefore attaches these as *base* contributions,
-- behind the hand-ported data/scripts/ modules, which still win outright.

local Logger = require("src.core.Logger")
local MapScripts = require("src.script.MapScripts")
local Gen2Flags = require("src.script.Gen2Flags")
require("src.script.Gen2Commands")
require("src.script.Gen2Specials")

local Gen2ScriptVM = {}

local compiled = setmetatable({}, { __mode = "k" })

-- Prism's `sif` opcodes, and the `then` marker that turns one into a block.
-- Named here rather than reached through Gen2ScriptOps so the lowering does
-- not depend on which command table a given ROM selected.
-- ScriptCheckCondition (engine/script_conditionals.asm) sets carry when the
-- guarded body should RUN, and the six are six genuinely different tests:
--
--   .false        ld a, c / cp 1     -- runs when the variable is ZERO
--   .true         xor a  / cp c      -- runs when it is NOT zero
--   .less_than    ld a, c / cp b     -- variable <  operand
--   .greater_than ld a, b / cp c     -- variable >  operand
--   .equal        ld a, b / sub c    -- variable == operand
--   .not_equal                       -- and the inverse
--
-- Lowering all six as `jump_if_false` made `sif false` the exact opposite of
-- itself and threw the operand of the four comparing forms away.  The
-- Larvitar on Prism's first outdoor map is `yesorno / sif false / jumptext
-- .declined_text`: answering YES took the DECLINED branch, so it printed the
-- refusal, ended, never reached its givepoke, and was still standing there
-- blocking the path with the same lines on the next talk.
local SIF_OPS = {
  siftrue = true, siffalse = true,
  sifeq = true, sifne = true, sifgt = true, siflt = true,
}
-- the four that carry a value byte, and the comparison each one makes
local SIF_COMPARE = {
  sifeq = "eq", sifne = "ne", sifgt = "gt", siflt = "lt",
}
local THEN_OP = "scriptstartasm"

local eventFlag = Gen2Flags.eventFlag
-- scriptFlag, not engineFlag: a `setflag` operand is a ROW NUMBER in the
-- cartridge's own EngineFlags table, and Crystal's table has one extra row
-- from index 16 up.  engineFlag stays the raw Gold-numbered lookup for the
-- handful of call sites that pass a constant they already know the name of.
local engineFlag = Gen2Flags.scriptFlag
local function itemId(n) return string.format("ITEM_%03d", n) end

-- ---------------------------------------------------------------------------
-- lowering table: ir row -> zero or more ScriptRunner rows
-- ---------------------------------------------------------------------------

local L = {}

local function emit(s, row) s.out[#s.out + 1] = row end

-- A pointer that fell outside the ROM, or a far script that failed to
-- disassemble, is stored as "" by the extractor.  Branches to one lower to
-- nothing at all rather than to a jump ScriptRunner cannot resolve.
-- A branch whose target is not in the script pool is DROPPED, not errored:
-- the conditional simply vanishes and the script falls through as though the
-- flag were false.  That is deliberate (a half-extracted pool should still
-- play), but it used to be completely silent, which makes "this NPC does
-- nothing" impossible to diagnose from a log.  Say it once per label.
local droppedBranch = {}

local function branch(s, label)
  if type(label) ~= "string" then return nil end
  if not s.has(label) then
    if label ~= "" and not droppedBranch[label] then
      droppedBranch[label] = true
      Logger.warn("gen2 script vm: branch to '%s' dropped (not in pool)", label)
    end
    return nil
  end
  s.want(label)
  return label
end

-- control flow -------------------------------------------------------------

L.sjump = function(ir, s)
  local to = branch(s, ir[2])
  if to then emit(s, { "jump", to }) end
end
L.farsjump = L.sjump
L.stopandsjump = L.sjump

L.scall = function(ir, s)
  local to = branch(s, ir[2])
  if not to then return end
  local ret = s.newLabel()
  emit(s, { "g2_call", ret })
  emit(s, { "jump", to })
  emit(s, { "label", ret })
end
L.farscall = L.scall
-- `sdefer` is NOT a call.  Script_sdefer parks the pointer and returns; the
-- target runs once the current script has ended and the map is up, which is
-- why every Battle Tower scene uses it -- `sdefer RideElevator / setscene 1 /
-- end`.  Lowering it as an inline scall ran the cutscene from inside the
-- map's onEnter, while the warp transition was still in flight and the
-- objects it moves had not been placed, so the elevator's ride script queued
-- movements on entities that were not there yet and the runner never
-- finished: the player was left frozen in the elevator with no way out.
--
-- The overworld's own pending-script FIFO already has exactly these
-- semantics -- it holds a script until the transition ends, the current
-- runner is dead and no scripted walk is mid-step -- so hand it over rather
-- than splicing the rows in here.
L.sdefer = function(ir, s)
  if type(ir[2]) == "string" and ir[2] ~= "" then
    emit(s, { "g2_sdefer", ir[2] })
  end
end

L.iftrue = function(ir, s)
  local to = branch(s, ir[2])
  if to then emit(s, { "jump_if_true", to }) end
end
L.iffalse = function(ir, s)
  local to = branch(s, ir[2])
  if to then emit(s, { "jump_if_false", to }) end
end

local function compare(op)
  return function(ir, s)
    local to = branch(s, ir[3])
    if not to then return end
    emit(s, { "g2_compare", op, ir[2] })
    emit(s, { "jump_if_true", to })
  end
end
L.ifequal = compare("eq")
L.ifnotequal = compare("ne")
L.ifgreater = compare("gt")
L.ifless = compare("lt")

-- THE FORWARD-JUMP FAMILY, which Gold and Crystal do not have.
--
-- Polished Crystal's sjumpfwd/iftruefwd/iffalsefwd/ifequalfwd branch by a
-- byte offset counted from the instruction after the operand. The extractor
-- resolves that offset into an ordinary script label (see the "j" operand
-- kind), so by the time it reaches here a forward jump is the same thing as
-- an sjump or an iftrue and needs no new machinery -- only a name.
--
-- Without these four the commands were unhandled: the branch simply did not
-- happen, so the script ran on into the arm it was meant to skip. Elm's is
-- `checkevent 121 / iffalsefwd <past the request> / scall / jumptext`, which
-- is why answering "yes" put you straight back at "Please, I need your help!"
-- however many times you answered it.
L.sjumpfwd = function(ir, s)
  local to = branch(s, ir[2])
  if to then emit(s, { "jump", to }) end
end
L.iftruefwd = L.iftrue
L.iffalsefwd = L.iffalse
L.ifequalfwd = compare("eq")

-- Commands with no runtime model that genuinely need none.  Declaring them
-- keeps them out of the "unhandled opcode" audit and documents WHY each one
-- is a no-op, rather than leaving a reader to wonder whether it was missed.
--
--   opentext/closetext      the port's show_text owns its own box
--   waitbutton/promptbutton show_text already waits for A
--   wildon/wildoff          encounters are gated by the map, not a script flag
--   loademote               showemote carries the emote id itself
--   encountermusic          the battle intro picks its own track
--   deactivatefacing        facing locks are not modelled
--   writeunusedbyte         writes a byte nothing reads, in the ROM too
--   delcmdqueue             the cmd queue only ever holds the stone table
local function noop() end
for _, name in ipairs({
  "opentext", "closetext", "waitbutton", "promptbutton", "wildon", "wildoff",
  "loademote", "encountermusic", "deactivatefacing", "writeunusedbyte",
  "delcmdqueue",
  -- fieldmovepokepic farcalls FieldMovePokepicScript (2c:$5189), which opens
  -- the framed pic AND closes it again inside that same script.  The port's
  -- pokepic box is closed by a separate `closepokepic` row, and the calling
  -- script never emits one -- so opening a box here would leave it up with
  -- the runner parked behind it.  Presentation only; the command that
  -- matters is the callasm two rows later.
  "fieldmovepokepic",
  -- Prism's own, same reasoning: Script_buttonsound is ApplyTilemapInVBlank /
  -- ButtonSound, and show_text already waits for A; refreshscreen is the
  -- window teardown the port's text box does for itself.
  "buttonsound", "refreshscreen",
}) do
  L[name] = noop
end

-- Script_checkjustbattled: true when the script was re-entered straight out
-- of a won battle, which is the same flag g2_endifjustbattled reads.
L.checkjustbattled = function(_, s) emit(s, { "g2_check_just_battled" }) end

-- ---------------------------------------------------------------------------
-- The remaining ScriptCommandTable entries.
--
-- Semantics below were read out of the ROM handlers (ScriptCommandTable
-- 25:$6BE4), not guessed, because a wrong guess here is worse than no
-- handler: an unhandled opcode is skipped and logged, a wrong one silently
-- corrupts the script.
-- ---------------------------------------------------------------------------

-- Script_getmoney (25:$7583) / Script_getcoins (25:$7598) / Script_getnum
-- (25:$75AD) all end in PrintNum and then `jp GetStringBuffer`, which reads
-- ONE MORE script byte and indexes from wStringBuffer3 -- 0 -> 3, 1 -> 4,
-- 2 -> 5, anything else clamped to 0 (scripting.asm:1583).  Every macro puts
-- that buffer operand LAST.
--
-- Dropping it and writing the port's single legacy buffer is not harmless.
-- BugContestResultsScript is `getnum STRING_BUFFER_3` (the placing) and then
-- `getitemname STRING_BUFFER_4, SUN_STONE` (the prize), and
-- ContestResults_PlayerWonAPrizeText splices BOTH:
--
--     "<PLAYER>, the No.@" wStringBuffer3 " finisher, wins @" wStringBuffer4 "!"
--
-- With one shared buffer the second write won and the line came out as
-- "CHRIS, the No.EVERSTONE finisher, wins EVERSTONE!".
L.getmoney = function(ir, s) emit(s, { "g2_buffer_money", ir[3] }) end
L.getcoins = function(ir, s) emit(s, { "g2_buffer_coins", ir[2] }) end
L.getnum = function(ir, s) emit(s, { "g2_buffer_num", ir[2] }) end

-- Script_getcurlandmarkname (25:$755B) reads wMapGroup/wMapNumber, resolves
-- the landmark and copies its name into the buffer.
L.getcurlandmarkname = function(ir, s) emit(s, { "g2_buffer_landmark", ir[2] }) end

-- Script_loadmem (25:$7495): three GetScriptByte reads -- a WRAM address low
-- then high, then a value -- and `ld [hl], a`.  The port keeps the same tiny
-- address-keyed mirror readmem/writemem already use.
L.loadmem = function(ir, s) emit(s, { "g2_loadmem", ir[2], ir[3] }) end

-- `phonecall <text>` carries a FAR TEXT pointer, which the extractor has
-- already registered as dialogue, so the call can simply be printed.  Left
-- unlowered it was a silent no-op and the caller said nothing at all.
L.phonecall = function(ir, s) emit(s, { "show_text", ir[2] }) end
-- Script_hangup (25:$6F7A) just tears the call window down; the port's text
-- box closes itself.
L.hangup = function() end

-- Script_checkpokemail (25:$7608): does the party hold this mail?  The port
-- has no mail model, so answer "no" rather than leaving the branch to fall
-- through on a stale flag.
L.checkpokemail = function(_, s) emit(s, { "g2_false" }) end
L.givepokemail = function() end

-- ------------------------------------------------------------------ no-ops
-- Each of these was verified to touch only state the port does not model.
--
--   xycompare      (25:$7852) stores a pointer in wXYComparePointer and
--                  returns; the comparison itself belongs to a coord-event
--                  path this port resolves from its own map data.
--   writeobjectxy  (25:$71D9) copies an object's coords into WRAM for a
--                  later applymovement -- the port's movements read the live
--                  NPC instead.
--   loadtemptrainer/randomwildmon/loadpikachudata build a battle out of WRAM
--                  scratch the port fills from its own encounter tables.
--   _2dmenu/describedecoration are presentation the port has no
--                  equivalent for; the surrounding dialogue still runs.
--   autoinput      replays a canned joypad script over a cutscene.
--   (catchtutorial used to live here too; it is implemented now, below.)
local function vmNoop() end
for _, name in ipairs({
  "xycompare", "writeobjectxy", "loadtemptrainer", "randomwildmon",
  "loadpikachudata", "_2dmenu", "describedecoration",
  "autoinput",
}) do
  L[name] = vmNoop
end



L["end"] = function(_, s) emit(s, { "g2_return" }) end
L.endcallback = L["end"]
L.reloadend = L["end"]
-- Prism's own name for the same thing (engine/scripting.asm Script_return).
-- Without it a `return` lowered to NOTHING, which matters most inside a `sif`
-- guard: IntroOutside's `.init_events` is "if the events are already set up,
-- return" -- and a guard around zero rows is no guard at all, so the events
-- were re-initialised on every single entry to the map.
L["return"] = L["end"]
L.return_if_callback_else_end = L["end"]

-- A trainer's script is re-entered both right after the battle and when the
-- player talks to the beaten trainer.  Most open with `endifjustbattled` so
-- the after-battle line only shows on the second path; the ones that drive a
-- cutscene (the Slowpoke Well boss) deliberately omit it.
L.endifjustbattled = function(_, s) emit(s, { "g2_endifjustbattled" }) end
L.endall = function(_, s) emit(s, { "jump", "end" }) end

-- StdScripts bodies are decoded into the same pool as everything else, so a
-- jumpstd/callstd is an ordinary jump/call.  The Pokecenter nurse is
-- `jumpstd pokecenternurse` and nothing else; leaving it as a warn-once stub
-- was why talking to a nurse did nothing at all.
-- ir[2] is the StdScripts table index (0 = PokecenterNurseScript).  The
-- extractor stores pool.stds keyed by that numeric index; also accept a
-- stringified index from older IR dumps.
local function stdLabel(s, id)
  if not s.stds then return nil end
  local label = s.stds[id]
  if label then return label end
  local n = tonumber(id)
  if n ~= nil then return s.stds[n] end
  return nil
end

L.jumpstd = function(ir, s)
  local to = branch(s, stdLabel(s, ir[2]))
  if to then
    emit(s, { "jump", to })
    -- jumpstd is a terminal jump in the ROM; do not emit g2_return after a
    -- successful resolve (dead row is harmless but confuses traces).
    return
  end
  emit(s, { "g2_std", ir[2] })
  emit(s, { "g2_return" })
end
L.callstd = function(ir, s)
  local to = branch(s, stdLabel(s, ir[2]))
  if not to then emit(s, { "g2_std", ir[2] }); return end
  local ret = s.newLabel()
  emit(s, { "g2_call", ret })
  emit(s, { "jump", to })
  emit(s, { "label", ret })
end

-- text ---------------------------------------------------------------------

-- Prism's GetScriptHalfwordOrVar treats an operand of $ffff as "the halfword
-- variable holds it", so `jumptext -1` prints whichever line the preceding
-- readarrayhalfword pulled out of a table.  The extractor cannot name that
-- text at decode time -- it is one of many -- so it marks the operand and the
-- choice is made at run time.
local TEXT_FROM_HALFWORD = "<halfwordvar>"

local function showText(s, id)
  if id == TEXT_FROM_HALFWORD then
    emit(s, { "g2_show_halfword_text" })
  else
    emit(s, { "show_text", id })
  end
end

L.writetext = function(ir, s)
  s.lastText = ir[2]
  showText(s, ir[2])
  s.lastTextRow = #s.out
end
L.farwritetext = L.writetext
L.repeattext = function(_, s)
  if s.lastText then showText(s, s.lastText) end
end

L.jumptext = function(ir, s)
  showText(s, ir[2])
  emit(s, { "g2_return" })
end
L.jumptextfaceplayer = function(ir, s)
  emit(s, { "face_player" })
  showText(s, ir[2])
  emit(s, { "g2_return" })
end
-- Crystal's far-pointer jumptext: prints the line and ends the script, exactly
-- like jumptext.  Unlowered, the eleven std scripts that use it -- the
-- bookshelves, the signs, the trash can, the window -- printed nothing at all.
L.farjumptext = L.jumptext

-- POLISHED CRYSTAL'S COMPOUND TEXT COMMANDS.
--
-- This build collapses the pairs Gold and Crystal spell out -- open a box,
-- print, end -- into single opcodes, and adds a "this" family that prints the
-- text the script is already sitting on. None of them needs new machinery:
-- each is a combination of primitives already here, and the only difference
-- between the -opened- forms and the plain ones is whether the box was
-- already open, which the port's show_text owns either way.
--
-- Unlowered they are not wrong, they are ABSENT: the opcode lowers to
-- nothing, so the NPC opens a box, says nothing and closes it. 1,437 of this
-- cartridge's instructions were in this family.
L.jumpopenedtext = L.jumptext
L.jumpthistext = L.jumptext
L.jumpthisopenedtext = L.jumptext
L.jumpstashedtext = L.jumptext
L.jumpthistextfaceplayer = L.jumptextfaceplayer
-- `writethistext` prints the text the interaction stashed and keeps running;
-- the extractor resolves "this" to the operand where it can, and writetext
-- with a nil id falls back to the object's own line downstream, exactly as
-- the jumpthistext alias above already relies on.
L.writethistext = L.writetext
L.showtextfaceplayer = function(ir, s)
  emit(s, { "face_player" })
  s.lastText = ir[2]
  showText(s, ir[2])
  s.lastTextRow = #s.out
end

-- ...and the conditional forms, which are `iftrue`/`iffalse` fused to one of
-- the jumps above. The text operand belongs to the JUMP, so the branch has to
-- be built here rather than reusing L.iftrue -- there is no label to jump to,
-- only a line to print and a script to end.
local function conditionalJumpText(wantTrue, faces)
  return function(ir, s)
    local skip = s.newLabel()
    emit(s, { wantTrue and "jump_if_false" or "jump_if_true", skip })
    if faces then emit(s, { "face_player" }) end
    showText(s, ir[2])
    emit(s, { "g2_return" })
    emit(s, { "label", skip })
  end
end
L.iftrue_jumptext = conditionalJumpText(true, false)
L.iffalse_jumptext = conditionalJumpText(false, false)
L.iftrue_jumpopenedtext = conditionalJumpText(true, false)
L.iffalse_jumpopenedtext = conditionalJumpText(false, false)
L.iftrue_jumptextfaceplayer = conditionalJumpText(true, true)
L.iffalse_jumptextfaceplayer = conditionalJumpText(false, true)
-- `endtext` variants end the script after printing, which g2_return already is
L.iftrue_endtext = conditionalJumpText(true, false)
L.iffalse_endtext = conditionalJumpText(false, false)

-- yesorno reuses the box its writetext just opened, and ask() prints the
-- prompt itself, so drop that row rather than showing the line twice.  Only
-- the row immediately before is ours: a yesorno confirming an unported
-- special's prompt would otherwise re-ask whatever was written last, which is
-- what made mom's daylight saving question repeat.
L.yesorno = function(_, s)
  local text
  if s.lastTextRow == #s.out then
    table.remove(s.out)
    s.lastTextRow = nil
    text = s.lastText
  end
  -- No coercion to "": a yesorno whose prompt was printed from inside a
  -- `scall` has no compile-time text to fold, and an empty id drew an EMPTY
  -- box over the question.  nil means "ride whatever text was last shown",
  -- which is what Script_yesorno does -- the menu opens over the box that is
  -- already on screen.
  emit(s, { "g2_yesno", text })
end
-- `catchtutorial <battletype>`: the Dude's demo battle on Route 29.  The
-- operand picks a row of CatchTutorial's jump table and all three rows are
-- .DudeTutorial, so it carries no information the port needs.
L.catchtutorial = function(_, s) emit(s, { "g2_catch_tutorial" }) end
L.faceplayer = function(_, s) emit(s, { "face_player" }) end

-- flags and events ---------------------------------------------------------

L.checkevent = function(ir, s) emit(s, { "check_flag", eventFlag(ir[2]) }) end
L.setevent = function(ir, s) emit(s, { "set_flag", eventFlag(ir[2]) }) end
L.clearevent = function(ir, s) emit(s, { "clear_flag", eventFlag(ir[2]) }) end
L.checkflag = function(ir, s) emit(s, { "check_flag", engineFlag(ir[2]) }) end
L.setflag = function(ir, s) emit(s, { "set_flag", engineFlag(ir[2]) }) end
L.clearflag = function(ir, s) emit(s, { "clear_flag", engineFlag(ir[2]) }) end

-- scenes -------------------------------------------------------------------

L.setscene = function(ir, s) emit(s, { "g2_set_scene", "", ir[2] }) end
L.checkscene = function(_, s) emit(s, { "g2_check_scene", "" }) end
L.setmapscene = function(ir, s) emit(s, { "g2_set_scene", ir[2], ir[4] }) end
L.checkmapscene = function(ir, s) emit(s, { "g2_check_scene", ir[2] }) end

-- items --------------------------------------------------------------------

-- ITEM_FROM_MEM: Script_giveitem (25:$77CA) reads the item operand and, on
-- $FF, takes wScriptVar instead; Script_getitemname (25:$76D5) does the same
-- on $00.  The Battle Tower's prize is the only place in Crystal that uses
-- either -- BattleTower_GiveReward leaves the rolled vitamin in wScriptVar and
-- the script then names and hands over five of it -- so lowering the operand
-- literally handed out ITEM_255 and named ITEM_000.  A separate row keeps the
-- operand list free of holes.

-- plain `giveitem` is silent; only `verbosegiveitem` prints and plays
L.giveitem = function(ir, s)
  if ir[2] == 0xFF then
    emit(s, { "g2_giveitem_var", ir[3] })
  else
    emit(s, { "g2_giveitem", itemId(ir[2]), ir[3] })
  end
end
L.verbosegiveitem = function(ir, s)
  emit(s, { "give_item", itemId(ir[2]), ir[3] })
end
-- `verbosegiveitemvar item, var` ($9F -- Crystal only; Gold's command list has
-- no such row).  The same gift box as verbosegiveitem, except the QUANTITY
-- comes out of a script variable instead of the operand
-- (Script_verbosegiveitemvar, engine/overworld/scripting.asm:486:
-- `GetVarAction / ld a, [de] / ld [wItemQuantityChange], a`).
--
-- Kurt is its ONLY user in the entire game -- all seven of KurtsHouse's
-- `verbosegiveitemvar <BALL>, VAR_KURT_APRICORNS` rows.  With no lowering the
-- command was silently dropped, so "Ah, I just finished your BALL. Here."
-- was followed by the `iffalse .NoRoomForBall` on the very next line reading a
-- STALE lastCheck -- which sent the script straight to closetext.  Kurt
-- announced the ball and then nothing happened, every time, and the apricorn
-- was already gone.
L.verbosegiveitemvar = function(ir, s)
  emit(s, { "g2_verbose_give_item_var", itemId(ir[2]), ir[3] })
end
-- `getitemname buffer, item` -- the macro emits the ITEM first and the buffer
-- second (`db \2 ; item` then `db \1 ; string_buffer`), so ir[2] is the item
-- and ir[3] the buffer.  Item 0 is USE_SCRIPT_VAR.
L.getitemname = function(ir, s)
  if ir[2] == 0 then
    emit(s, { "g2_getitemname_var", ir[3] })
  else
    emit(s, { "g2_getitemname", itemId(ir[2]), ir[3] })
  end
end
-- `getstring "TEXT", buffer` (GetString) copies a fixed name into a string
-- buffer for a later writetext to splice back out.  The extractor already
-- resolved the pointer to the literal, and the port keeps ONE buffer, so the
-- buffer index is dropped the same way getitemname's is.  Left unlowered, the
-- Lavender radio director's "<PLAYER> received the EXPN CARD!" printed
-- whatever was in the buffer from several scenes ago -- usually a TM.
L.getstring = function(ir, s) emit(s, { "g2_getstring", ir[2], ir[3] }) end
-- `gettrainername buffer, group, id` ($43) and `getlandmarkname buffer,
-- landmark` ($A5).  Both macros write the BUFFER OPERAND LAST
-- (macros/scripts/events.asm:450 and :1036), and GetStringBuffer
-- (scripting.asm:1583) maps it 0 -> wStringBuffer3, 1 -> wStringBuffer4,
-- 2 -> wStringBuffer5, clamping anything else to 0.
--
-- Neither had a lowering, and between them they fill the two buffers the
-- phone scripts splice: the caller's own name and the route they are ringing
-- about.  With nothing writing them, every one of the ~70
-- `{RAM:wStringBuffer5}` landmark lines printed whatever RandomPhoneWildMon
-- had just left in the port's single shared buffer -- a SPECIES NAME.  "Come
-- pick it up on MAGIKARP."  Lines with no RandomPhone* special ahead of them
-- printed a species left over from an earlier call entirely.
L.gettrainername = function(ir, s)
  emit(s, { "g2_buffer_trainer_name", ir[2], ir[3], ir[4] })
end
L.getlandmarkname = function(ir, s)
  emit(s, { "g2_buffer_landmark_name", ir[2], ir[3] })
end
-- `battletowertext <slot>` (Script_battletowertext, 25:$6F52 -> BattleTowerText
-- 47:$4000): the generated opponent's own line -- 1 before the battle, 2 when
-- they win, 3 when they lose.  The line is picked from the male or female pool
-- by the trainer's class, once per opponent.
L.battletowertext = function(ir, s)
  emit(s, { "g2_battle_tower_text", ir[2] or 1 })
end
L.getmonname = function(ir, s)
  -- same zero-is-the-variable rule as `cry` above: `pokenamemem 0, 0` names
  -- whatever the script just looked up, not species zero
  if (ir[2] or 0) == 0 then
    emit(s, { "g2_getmonname_var", ir[3] })
  else
    emit(s, { "g2_getmonname", string.format("SPECIES_%03d", ir[2]), ir[3] })
  end
end
L.takeitem = function(ir, s) emit(s, { "take_item", itemId(ir[2]), ir[3] }) end
L.checkitem = function(ir, s)
  -- and again: `checkitem 0` asks about the item in the script variable
  if (ir[2] or 0) == 0 then
    emit(s, { "g2_check_item_var" })
  else
    emit(s, { "check_item", itemId(ir[2]) })
  end
end
-- BP: `givebp`/`takebp`/`checkbp` carry a HALFWORD (LoadCoinAmountToMem reads
-- two script bytes), so the amount is the first operand rather than money's
-- second -- givemoney below takes an account byte ahead of its amount and
-- these do not.  See Commands.g2_give_bp for where the cap and the check's
-- three answers come from.
L.givebp = function(ir, s) emit(s, { "g2_give_bp", ir[2] }) end
L.takebp = function(ir, s) emit(s, { "g2_give_bp", -(tonumber(ir[2]) or 0) }) end
L.checkbp = function(ir, s) emit(s, { "g2_check_bp", ir[2] }) end
L.checkdarkness = function(_, s) emit(s, { "g2_check_darkness" }) end
L.checkunits = function(_, s) emit(s, { "g2_check_units" }) end

L.givemoney = function(ir, s) emit(s, { "give_money", ir[3] }) end
L.takemoney = function(ir, s) emit(s, { "give_money", -(ir[3] or 0) }) end
L.checkmoney = function(ir, s) emit(s, { "g2_check_money", ir[3] }) end
-- itemnotify/pocketisfull print the "got"/"no room" line for the item
-- verbosegiveitem already handled, so only the bag-full test carries weight
L.pocketisfull = function(_, s) emit(s, { "g2_pocket_full" }) end
L.checkpoke = function(ir, s)
  emit(s, { "g2_check_poke", string.format("SPECIES_%03d", ir[2] or 0) })
end
-- `giveegg species, level`: an EGG party member.  Elm's aide hands one over
-- outside the Violet gym and the script `iftrue`s on the carry, so a missing
-- lowering left the whole delivery scene dead.
L.giveegg = function(ir, s)
  emit(s, { "g2_give_egg", string.format("SPECIES_%03d", ir[2] or 0), ir[3] })
end
L.givepoke = function(ir, s)
  emit(s, { "give_pokemon", string.format("SPECIES_%03d", ir[2] or 0), ir[3] })
end
-- Gen1's play_cry arms the *following* text box (the box auto-closes when
-- the cry ends).  Gen2's `cry` is a standalone PlayMonCry between pokepic
-- and the next opentext, so it must not arm anything -- doing so made the
-- starter's yes/no box auto-close before its ChoiceBox appeared, which the
-- script read back as NO.
L.cry = function(ir, s)
  -- Prism's GetScriptByteOrVar (00:$1A9D) answers the SCRIPT VARIABLE for a
  -- zero operand, which is how one starter script cries six different mons.
  -- Lowered literally it asked for SPECIES_000 and nothing sounded.
  emit(s, { "g2_cry",
            (ir[2] or 0) ~= 0 and string.format("SPECIES_%03d", ir[2]) or nil })
end

-- `pokepic <species>` opens the framed front pic and keeps running;
-- `closepokepic` is where the ROM's waitbutton lands, so that is where the
-- port waits.  A species of 0 means "whatever wScriptVar holds", which the
-- command resolves at run time.
L.pokepic = function(ir, s)
  local species = ir[2]
  emit(s, { "g2_pokepic",
            (species and species > 0)
              and string.format("SPECIES_%03d", species) or nil })
end
L.closepokepic = function(_, s) emit(s, { "g2_close_pokepic" }) end

-- PRISM'S PARTY-TYPE SEARCH, and the two commands that read its answer.
--
-- Script_findpokemontype (25:$6CC4) walks the party and stops at the FIRST
-- mon that either IS the given type or KNOWS a move of it, leaving that
-- mon's ONE-BASED party index in wScriptVar -- 0 when nobody qualifies, which
-- is what the `siffalse` after it branches on.  The type arrives as the
-- cartridge's own id byte and is resolved against the ROM's TypeNames at run
-- time (data.typeChart.ids), because Prism's numbering is its own: ELECTRIC
-- is $17 there and $0D in Crystal.
--
-- Unlowered, the command did nothing and wScriptVar kept whatever the
-- previous row left in it -- 0 after the `writetext` that precedes it -- so
-- Mound Cave's light switch always took the "you have no ELECTRIC Pokemon"
-- arm no matter what the party held.
L.findpokemontype = function(ir, s)
  emit(s, { "g2_find_party_type", ir[2] })
end

-- `getpartymonname <n>` (25:$6E7A): GetScriptByteOrVar, so an operand of 0
-- means "read wScriptVar" -- and the index it indexes with is ONE-BASED
-- (the ROM's base pointer is wPartyMonNicknames - NAME_LENGTH, $DE36 against
-- a $DE41 array, which is how the 1 that findpokemontype returns for the
-- first party slot lands on the first nickname).
L.getpartymonname = function(ir, s)
  emit(s, { "g2_party_mon_name", ir[2] })
end

-- objects ------------------------------------------------------------------

L.appear = function(ir, s) emit(s, { "g2_object", ir[2], true }) end
L.disappear = function(ir, s) emit(s, { "g2_object", ir[2], false }) end
L.applymovement = function(ir, s) emit(s, { "g2_move", ir[2], ir[3] }) end
L.applymovementlasttalked = function(ir, s) emit(s, { "g2_move", "npc", ir[2] }) end
L.turnobject = function(ir, s) emit(s, { "g2_turn", ir[2], ir[3] }) end
L.moveobject = function(ir, s) emit(s, { "g2_place", ir[2], ir[3], ir[4] }) end
L.faceobject = function(ir, s) emit(s, { "g2_turn", ir[2], ir[3] }) end
L.showemote = function(ir, s) emit(s, { "g2_emote", ir[3], ir[2], ir[4] }) end

-- `follow leader, follower` / `stopfollow`: the leader's next applymovement
-- drags the follower along one tile behind (StartFollow / EndFollow).  This
-- is what walks the player behind Cherrygrove's guide, Elm's aide and the
-- Burned Tower rival; with no lowering the guide walked off alone.
L.follow = function(ir, s) emit(s, { "g2_follow", ir[2], ir[3] }) end
L.follownotexact = L.follow
L.stopfollow = function(_, s) emit(s, { "g2_follow" }) end

-- battles ------------------------------------------------------------------

L.loadtrainer = function(ir, s) emit(s, { "g2_load_trainer", ir[2], ir[3] }) end
-- `loadwildmon <species>, <level>` arms a WILD battle, not a trainer one.
-- Sharing loadtrainer's lowering meant Sudowoodo and the Red Gyarados asked
-- for trainer class 185, found nothing, and silently skipped the battle.
L.loadwildmon = function(ir, s)
  emit(s, { "g2_load_wild", string.format("SPECIES_%03d", ir[2] or 0), ir[3] })
end
L.winlosstext = function(ir, s) emit(s, { "g2_winloss", ir[2], ir[3] }) end
L.startbattle = function(_, s) emit(s, { "g2_start_battle" }) end
L.reloadmapafterbattle = function(_, s) emit(s, { "g2_after_battle" }) end

-- movement, warps, presentation -------------------------------------------

L.warp = function(ir, s) emit(s, { "g2_warp", ir[2], ir[4], ir[5] }) end
L.warpfacing = function(ir, s) emit(s, { "g2_warp", ir[3], ir[5], ir[6], ir[2] }) end
-- `blackoutmod GROUP, MAP` (Script_blackoutmod) records the map
-- GetWhiteoutSpawn looks up in SpawnPoints -- where a blackout puts the
-- player.  With no lowering every blackout fell through to spawn 0, the
-- bedroom in New Bark Town, however far the story had got.  The extractor
-- has already folded the (group, map) pair into one registry key.
L.blackoutmod = function(ir, s) emit(s, { "g2_blackout_point", ir[2] }) end

-- Prism's Pokemon-mode sections.  Both are `Script_blackoutmod` (the new
-- respawn point) plus an engine-flag write and a party backup, and both answer
-- 1 in the script variable when they did their work -- LaurelForestMain and
-- MagikarpCavernsMain branch on that answer straight afterwards, so a silent
-- opcode left them on the failure arm.  The respawn point and the answer are
-- what the port can honour; the party swap is not modelled, so the mon the
-- player walks as is their lead, which is exactly what GetPlayerSprite falls
-- back to when wPokeonlyMainSpecies is clear.
L.startpokeonly = function(ir, s)
  emit(s, { "g2_blackout_point", ir[2] })
  emit(s, { "g2_setvar", 1 })
end
L.endpokeonly = L.startpokeonly

-- Script_halloffame (pokegold scripting.asm): induction + credits.
-- HallOfFameEnterScript ends with: HealParty → (optional SS Ticket call) → halloffame.
-- Without this lowering the opcode is skipped and the player can walk around
-- the Hall of Fame after the heal.
L.halloffame = function(_, s)
  emit(s, { "record_hall_of_fame" })
end

-- `credits` (Crystal $B2): roll the end credits on their own.  The Hall of
-- Fame path already pushes the same screen after the induction; this is the
-- command for the times the cartridge rolls them without one.
L.credits = function(_, s) emit(s, { "push_screen", "Credits" }) end

-- `gettrainerclassname <class>, <buffer>` (Crystal $A5): the trainer CLASS's
-- own name -- "SAGE", "BIRD KEEPER" -- rather than the individual's, which is
-- what gettrainername buffers.  Ten sites on Crystal, every one of them a line
-- that named nobody.
--
-- Operand order follows its neighbour `getlandmarkname`, which has the same
-- two-byte shape and puts the VALUE first and the buffer second; the class is
-- the `index` the port's trainer records are keyed by, so the class name is
-- the group's own `name` with no party member picked out of it.
L.gettrainerclassname = function(ir, s)
  emit(s, { "g2_buffer_trainer_name", ir[2], 0, ir[3] })
end

L.pause = function(ir, s) emit(s, { "wait", ir[2] }) end

-- Crystal-only.  Script_wait (25:$7C05) reads one byte and then loops that
-- many times over DelayFrames(6), so `wait n` is n * 6 frames -- six times
-- longer than `pause n`, which is a plain frame count.  Unhandled it lowered
-- to nothing at all, so every Crystal cutscene that paces itself with `wait`
-- ran its next step immediately.
local WAIT_FRAMES_PER_UNIT = 6
L.wait = function(ir, s)
  local units = tonumber(ir[2]) or 0
  if units > 0 then emit(s, { "wait", units * WAIT_FRAMES_PER_UNIT }) end
end

-- checksave is deliberately NOT handled.  Script_checksave (25:$7C15) farcalls
-- the save check and drops its result in wScriptVar for a following ifequal,
-- and I have not read what each returned value means -- inventing one would
-- send the script down a branch on a guess, which is exactly the failure the
-- specials rework above was fixing.  Left to warn once.
-- MUSIC_* and SFX_* are row indices into the ROM's Music and SFX pointer
-- tables, which is exactly how the importer keyed audio.musicIndex/sfxIndex.
L.playmusic = function(ir, s) emit(s, { "g2_music", ir[2] }) end
L.playsound = function(ir, s) emit(s, { "g2_sfx", ir[2] }) end
L.playmapmusic = function(_, s) emit(s, { "g2_mapmusic" }) end
L.musicfadeout = function(ir, s) emit(s, { "g2_musicfade", ir[2], ir[3] }) end
-- BIT_NO_MAP_MUSIC: the next map load keeps whatever is playing
L.dontrestartmapmusic = function(_, s) emit(s, { "g2_keepmusic" }) end
-- Script_warpsound / Script_specialsound pick their sample from map and item
-- state the port does not model; both only ever reach one of two jingles.
L.warpsound = function(_, s) emit(s, { "g2_sfx_name", "Sfx_EnterDoor" }) end
L.specialsound = function(_, s) emit(s, { "g2_sfx_name", "Sfx_Item" }) end
-- the ROM blocks on the sound driver; here effects are their own Sources and
-- nothing needs to wait, so this only has to stop being an unknown opcode
L.waitsfx = function(_, s) emit(s, { "g2_nop" }) end

-- `pokemart MARTTYPE_*, MART_*`: the second operand indexes the Marts pointer
-- table the extractor stamps into map_scripts.marts.
L.pokemart = function(ir, s) emit(s, { "g2_mart", ir[3] }) end
-- The extractor resolves both pointers into tables at import time: `elevator`
-- into its floor list, `loadmenu` into its MenuData labels.  `verticalmenu`
-- runs the armed menu and drops the 1-based choice (0 = cancelled) into the
-- script var, which is what the prize counters branch on.
L.elevator = function(ir, s) emit(s, { "g2_elevator", ir[2] }) end
-- `trade <NPCTRADE_*>` -> Script_trade -> NPCTrade (3F:$4BA8).  This was never
-- lowered, so every in-game trade NPC in Gen2 -- the ABRA man in Violet, the
-- BELLSPROUT girl on Route 34, all seven of them -- ran a script whose only
-- real command was skipped: no offer, no party menu, nothing said.
L.trade = function(ir, s) emit(s, { "g2_trade", ir[2] }) end
L.loadmenu = function(ir, s) emit(s, { "g2_loadmenu", ir[2] }) end
-- `writecmdqueue <ptr>`: the extractor has already followed the queue entry
-- and, when it is a CMDQUEUE_STONETABLE, turned it into the table's rows.
-- Registering them is all the map callback has to do -- the overworld fires
-- the matching row when a boulder settles on a hole.  A queue entry of any
-- other type still resolves to a bare pointer, which stays inert.
L.writecmdqueue = function(ir, s)
  if type(ir[2]) == "table" then emit(s, { "g2_stonetable", ir[2] }) end
end
-- Polished Crystal takes the stone table's pointer DIRECTLY where Crystal
-- queues it through writecmdqueue, and the extractor already resolves both
-- operands the same way (the `writecmdqueue or usestonetable` arm) -- so the
-- lowering is the same lowering.  Without it the boulder-into-hole rows were
-- decoded, resolved, and then thrown away.
L.usestonetable = L.writecmdqueue
L.verticalmenu = function(_, s) emit(s, { "g2_verticalmenu" }) end
L.checktime = function(ir, s) emit(s, { "g2_checktime", ir[2] }) end
-- No phone model yet, but the answer still has to be written: the nurse's
-- `checkphonecall / iftrue` would otherwise test whatever the last command
-- happened to leave in lastCheck (the player's own YES).
L.checkphonecall = function(_, s) emit(s, { "g2_false" }) end

-- The POKéGEAR phone book (wPhoneList).  `askforphonenumber` is the prompt
-- every trainer and Elm run; `addcellnum` is the unconditional register Mom
-- and the story NPCs use.  None of them were lowered, which is why Mom -- the
-- one number the port seeds itself -- was the only contact that ever showed.
L.addcellnum = function(ir, s) emit(s, { "g2_cellnum", ir[2], true }) end
L.delcellnum = function(ir, s) emit(s, { "g2_cellnum", ir[2], false }) end
L.checkcellnum = function(ir, s) emit(s, { "g2_check_cellnum", ir[2] }) end
-- like yesorno, the prompt rides the box the preceding writetext opened
L.askforphonenumber = function(ir, s)
  if s.lastTextRow == #s.out then
    table.remove(s.out)
    s.lastTextRow = nil
  end
  -- Same rule as yesorno, and here it was fatal rather than ugly.  Every
  -- trainer phone script is `scall <jumpstd AskNumber_M/F> /
  -- askforphonenumber`, so s.lastText is nil for ~50 of the ~59 sites -- and
  -- a nil id reached Commands.show_text, which indexes it and then calls
  -- gsub on the nil result.  That threw inside the script runner with the
  -- text box still on screen and no YES/NO menu: the frozen "Would you tell
  -- me your number?" box.  nil now means "re-use the last text shown".
  emit(s, { "g2_ask_cellnum", ir[2], s.lastText })
end

-- `specialphonecall <SPECIALCALL_*>` (Script_specialphonecall -> ld
-- [wSpecialPhoneCallID]) only ARMS the call; CheckSpecialPhoneCall (36:$413E)
-- fires it a step or two later once the row's condition passes.  Leaving it
-- unlowered is why Elm never rang about the egg after Falkner.
L.specialphonecall = function(ir, s) emit(s, { "g2_special_call", ir[2] }) end

-- SpecialsPointers rows the port already implements, all of them nullary.
-- Everything else stays a warn-once stub.
local SPECIALS = {
  -- The two phone specials.  Every trainer phone script opens with one of
  -- them: they pick the species the line is about -- one out of the CALLER'S
  -- own party, one out of the grass on the caller's route -- and leave its
  -- name in the string buffer the line splices back in.  Left unlowered, the
  -- "I caught a {mon}!" calls printed whatever the buffer last held.
  -- The Ruins of Alph chamber walls.  `writetext <patterns appear> / setval n
  -- / special DisplayUnownWords` -- with the special missing, the line printed
  -- and the ancient writing it announces never appeared.
  DisplayUnownWords = "g2_unown_wall",
  DisplayUnownWordsSpecial = "g2_unown_wall",
  -- The wall words are instructions, not decoration: each chamber opens on a
  -- different act.  These two are the ones a scene script can decide by
  -- itself; ESCAPE (Kabuto) and LIGHT (Aerodactyl) are triggered by using the
  -- item, so they hang off the item code -- see src/script/RuinsOfAlph.lua.
  HoOhChamber = "g2_hooh_chamber",
  HoOhChamberSpecial = "g2_hooh_chamber",
  OmanyteChamber = "g2_omanyte_chamber",
  OmanyteChamberSpecial = "g2_omanyte_chamber",
  -- The Day-Care man's Odd Egg.  His script prints the whole speech and then
  -- runs this to actually hand it over; with no handler the player got the
  -- text and an empty party slot.
  GiveOddEgg = "g2_give_odd_egg",
  GiveOddEggSpecial = "g2_give_odd_egg",
  -- "are you carrying one of these that you raised yourself?" -- the whole of
  -- ElmEggHatchedScript, and how he knows the EGG hatched.
  FindPartyMonThatSpeciesYourTrainerID = "g2_find_party_species_own",
  -- Mom's whole banking conversation lives in this one special; the script
  -- branch around it has no writetext at all.
  BankOfMom = "g2_bank_of_mom",
  RandomPhoneMon = "g2_random_phone_mon",
  RandomPhoneMonSpecial = "g2_random_phone_mon",
  RandomPhoneWildMon = "g2_random_phone_wild_mon",
  RandomPhoneWildMonSpecial = "g2_random_phone_wild_mon",
  -- Bug Catching Contest.  Both spellings are listed because a
  -- SpecialsPointers row can resolve under either the wrapper label or the
  -- routine it tail-calls, depending which symbol the manifest reached first;
  -- an entry that never matches simply never fires.
  GiveParkBalls = "g2_bug_contest_start",
  GiveParkBallsSpecial = "g2_bug_contest_start",
  ContestDropOffMons = "g2_bug_contest_drop_off",
  ContestDropOffMonsSpecial = "g2_bug_contest_drop_off",
  ContestReturnMons = "g2_bug_contest_return",
  ContestReturnMonsSpecial = "g2_bug_contest_return",
  BugContestJudging = "g2_bug_contest_judging",
  BugContestJudgingSpecial = "g2_bug_contest_judging",
  SelectRandomBugContestContestants = "g2_bug_contest_select",
  SelectRandomBugContestContestantsSpecial = "g2_bug_contest_select",
  -- Battle Tower.  Crystal only -- Gold and Silver have none of these rows --
  -- and the tower's own extracted scripts call every one of them, so this is
  -- the whole interface: the lobby, the level menu, the party rules, the
  -- opponent roll and the seven battles all live behind these five names.
  -- Both spellings again, for the same reason the contest rows carry both.
  BattleTowerAction = "g2_battle_tower_action",
  BattleTowerActionSpecial = "g2_battle_tower_action",
  BattleTowerBattle = "g2_battle_tower_battle",
  BattleTowerBattleSpecial = "g2_battle_tower_battle",
  BattleTowerRoomMenu = "g2_battle_tower_room_menu",
  BattleTowerRoomMenuSpecial = "g2_battle_tower_room_menu",
  CheckForBattleTowerRules = "g2_battle_tower_check_rules",
  CheckForBattleTowerRulesSpecial = "g2_battle_tower_check_rules",
  LoadOpponentTrainerAndPokemonWithOTSprite = "g2_battle_tower_load_opponent",
  LoadOpponentTrainerAndPokemonWithOTSpriteSpecial = "g2_battle_tower_load_opponent",
  Menu_ChallengeExplanationCancel = "g2_battle_tower_challenge_menu",
  -- BattleTower1F's "start a challenge" branch is `special TryQuickSave` +
  -- `iffalse` back to the menu, so leaving this to g2_special -- which answers
  -- false -- made the receptionist refuse to ever start one.
  TryQuickSave = "g2_try_quick_save",
  -- the "save and continue this challenge later" exit power-cycles the game
  Reset = "g2_soft_reset",
  HealParty = "g2_heal_party",
  DayCareMan = "g2_daycare_man",
  DayCareLady = "g2_daycare_lady",
  DayCareManOutside = "g2_daycare_outside",
  MoveDeletion = "g2_move_deleter",
  BankOfMom = "g2_bank_of_mom",
  MagnetTrain = "g2_magnet_train",
  NameRival = "g2_name_rival",
  -- PRISM SPELLS TWO OF THESE DIFFERENTLY, and the lookup is by the pret
  -- LABEL the ROM's own table points at, so a renamed routine misses a
  -- handler the port already has.  `SpecialNameRival` is the one that shows:
  -- IlkBrothersTalkToRival runs it the moment the rival teleports out of the
  -- brother's house, so with it unlowered the rival went unnamed for the rest
  -- of the game and every "{RIVAL}" in Prism's script printed the default.
  SpecialNameRival = "g2_name_rival",
  SpecialCheckPokerus = "g2_check_pokerus",
  -- `Special_TownMap` is FadeToMenu / _TownMap / ExitAllMenus -- the same
  -- three calls, in the same order, that Crystal reaches through
  -- OverworldTownMap, which the port already lowers.
  Special_TownMap = "g2_town_map",
  -- Prism's lent mon, structurally Crystal's Shuckie (see Gen2Commands).
  SpecialGiveNobusAggron = "g2_give_nobus_aggron",
  SpecialReturnNobusAggron = "g2_return_nobus_aggron",
  -- marks a dex entry seen from the script variable
  SpecialSeenMon = "g2_seen_mon",
  -- answers the first non-EGG party mon's happiness; scripts branch on it
  GetFirstPokemonHappiness = "g2_first_happiness",
  -- opens the party menu and answers 0 / $FF / the species number
  Special_SelectMonFromParty = "g2_select_mon_from_party",
  SetDayOfWeek = "g2_set_day_of_week",
  OverworldTownMap = "g2_town_map",
  UnownPrinter = "g2_unown_printer",
  MapRadio = "g2_map_radio",
  UnownPuzzle = "g2_unown_puzzle",
  SlotMachine = "g2_slots",
  CardFlip = "g2_card_flip",
  RestartMapMusic = "g2_restart_map_music",
  HealMachineAnim = "g2_heal_machine_anim",
  DayCareMon1 = "g2_daycare_mon1",
  DayCareMon2 = "g2_daycare_mon2",
  GiveShuckle = "g2_give_shuckle",
  ReturnShuckie = "g2_return_shuckie",
  BillsGrandfather = "g2_bills_grandfather",  -- (stones)
  CheckPokerus = "g2_check_pokerus",
  DisplayCoinCaseBalance = "g2_show_coins",
  DisplayMoneyAndCoinBalance = "g2_show_coins",
  PlaceMoneyTopRight = "g2_place_money_top_right",
  CheckForLuckyNumberWinners = "g2_lucky_winners",  -- lottery
  CheckLuckyNumberShowFlag = "g2_lucky_check_flag",
  ResetLuckyNumberShowFlag = "g2_lucky_reset",
  PrintTodaysLuckyNumber = "g2_lucky_print",
  SelectApricornForKurt = "g2_select_apricorn",
  NameRater = "g2_name_rater",
  LoadUsedSpritesGFX = "g2_load_used_sprites",  -- variablesprite refresh
  SnorlaxAwake = "g2_snorlax_awake",
  OlderHaircutBrother = "g2_haircut_older",
  YoungerHaircutBrother = "g2_haircut_younger",
  DaisysGrooming = "g2_daisys_grooming",
  ProfOaksPCBoot = "g2_oaks_pc",
  TrainerHouse = "g2_trainer_house",
  PhotoStudio = "g2_photo_studio",
  InitRoamMons = "g2_init_roam_mons",
  Diploma = "g2_diploma",
  PrintDiploma = "g2_print_diploma",

  -- -------------------------------------------------------------------------
  -- THE REST OF THE TABLE (src/script/Gen2Specials.lua)
  --
  -- Everything below was still falling through to `g2_special` on at least
  -- one of the three cartridges.  That handler answers `lastCheck = false`
  -- and leaves `g2Var` STALE, so an unhandled row standing between a check
  -- and its branch decided the branch -- see the SPECIALS_NOOP note above,
  -- which exists for exactly this reason.
  --
  -- Rows carrying a `Special_` prefix are Prism's spelling of a routine the
  -- base games reach under the bare label.  The lookup is by the label the
  -- ROM's own SpecialsPointers row points at, so a renamed routine misses a
  -- handler the port already has; every one of these is an alias onto the
  -- existing implementation, not a second one.
  -- -------------------------------------------------------------------------

  Special_DisplayCoinCaseBalance = "g2_show_coins",
  Special_DisplayMoneyAndCoinBalance = "g2_show_coins",
  Special_DayCareMan = "g2_daycare_man",
  Special_DayCareLady = "g2_daycare_lady",
  Special_DayCareManOutside = "g2_daycare_outside",
  Special_DayCareMon1 = "g2_daycare_mon1",
  Special_DayCareMon2 = "g2_daycare_mon2",
  Special_CardFlip = "g2_card_flip",
  Special_SlotMachine = "g2_slots",
  Special_YoungerHaircutBrother = "g2_haircut_younger",
  Special_OlderHaircutBrother = "g2_haircut_older",
  Special_DaisysGrooming = "g2_daisys_grooming",
  Special_NameRater = "g2_name_rater",
  Special_MagnetTrain = "g2_magnet_train",
  Special_HealParty = "g2_heal_party",
  Special_MoveDeletion = "g2_move_deleter",
  Special_BankOfMom = "g2_bank_of_mom",
  Special_SelectApricornForKurt = "g2_select_apricorn",
  Special_HealMachineAnim = "g2_heal_machine_anim",
  Special_UnownPuzzle = "g2_unown_puzzle",
  Special_UnownPrinter = "g2_unown_printer",
  Special_MapRadio = "g2_map_radio",
  Special_SetDayOfWeek = "g2_set_day_of_week",
  Special_PhotoStudio = "g2_photo_studio",
  Special_TrainerHouse = "g2_trainer_house",
  Special_Diploma = "g2_diploma",
  Special_PrintDiploma = "g2_print_diploma",
  Special_GiveShuckle = "g2_give_shuckle",
  Special_ReturnShuckie = "g2_return_shuckie",
  Special_CheckPokerus = "g2_check_pokerus",
  Special_PlaceMoneyTopRight = "g2_place_money_top_right",

  -- Party / box / dex checks.
  CheckFirstMonIsEgg = "g2_check_first_mon_egg",
  Special_CheckFirstMonIsEgg = "g2_check_first_mon_egg",
  MonCheck = "g2_mon_check",
  Special_MonCheck = "g2_mon_check",
  BeastsCheck = "g2_beasts_check",
  Special_BeastsCheck = "g2_beasts_check",
  FindPartyMonThatSpecies = "g2_find_party_species",
  Special_FindPartyMonThatSpecies = "g2_find_party_species",
  Special_FindPartyMonThatSpeciesYourTrainerID = "g2_find_party_species_own",
  FindPartyMonAboveLevel = "g2_find_party_above_level",
  Special_FindPartyMonAboveLevel = "g2_find_party_above_level",
  FindPartyMonAtLeastThatHappy = "g2_find_party_happy",
  Special_FindPartyMonAtLeastThatHappy = "g2_find_party_happy",
  GameCornerPrizeMonCheckDex = "g2_prize_mon_dex",
  Special_GameCornerPrizeMonCheckDex = "g2_prize_mon_dex",
  UnusedSetSeenMon = "g2_seen_mon",
  RandomUnseenWildMon = "g2_random_unseen_wild_mon",
  Special_RandomUnseenWildMon = "g2_random_unseen_wild_mon",
  Special_GetFirstPokemonHappiness = "g2_first_happiness",

  -- Small state pokes.
  GameboyCheck = "g2_gameboy_check",
  Special_GameboyCheck = "g2_gameboy_check",
  ActivateFishingSwarm = "g2_activate_fishing_swarm",
  Special_ActivateFishingSwarm = "g2_activate_fishing_swarm",
  SampleKenjiBreakCountdown = "g2_kenji_countdown",
  CheckCaughtCelebi = "g2_check_caught_celebi",
  GiveDratini = "g2_give_dratini",
  CheckPartyFullAfterContest = "g2_contest_party_full",
  Special_CheckPartyFullAfterContest = "g2_contest_party_full",

  -- The Magikarp guru, Buena's Blue Card, the Poke Seer.
  CheckMagikarpLength = "g2_magikarp_length",
  Special_CheckMagikarpLength = "g2_magikarp_length",
  MagikarpHouseSign = "g2_magikarp_sign",
  Special_MagikarpHouseSign = "g2_magikarp_sign",
  BuenasPassword = "g2_buenas_password",
  BuenaPrize = "g2_buena_prize",
  AskRememberPassword = "g2_ask_remember_password",
  PokeSeer = "g2_poke_seer",
  Special_PokeSeer = "g2_poke_seer",

  -- The PCs and the three move teachers.
  PokemonCenterPC = "g2_pokemon_center_pc",
  Special_PokemonCenterPC = "g2_pokemon_center_pc",
  PlayersHousePC = "g2_players_house_pc",
  Special_PlayersHousePC = "g2_players_house_pc",
  Special_KrissHousePC = "g2_players_house_pc",
  MoveTutor = "g2_move_tutor",
  Special_MoveTutor = "g2_move_tutor",
  MoveRelearner = "g2_move_relearner",
  Special_MoveRelearner = "g2_move_relearner",
  Special_GoldenrodHappinessMoveTutor = "g2_happiness_tutor",

  -- Prism's three remaining features.
  Special_FossilPuzzle = "g2_fossil_puzzle",
  Special_MemoryGame = "g2_memory_game",
  Special_SpurgeMartBank = "g2_spurge_bank",

  -- -------------------------------------------------------------------------
  -- The cable club, the mobile adapter and Mystery Gift.
  --
  -- 110-odd call sites, and the single biggest group in the table.  Two Game
  -- Boys is the one thing a single-player recompilation cannot fake, so every
  -- row answers a definite 0/false -- which is also what the cartridge answers
  -- with nothing plugged in: CheckLinkTimeout_Receptionist, AskMobileOrCable,
  -- CheckBothSelectedSameRoom and CheckMobileAdapterStatusSpecial all write 0
  -- to wScriptVar on failure and the receptionist scripts branch straight back
  -- to "please come again".  The Function10xxxx rows are the mobile adapter's
  -- unnamed routines, which pret leaves unlabelled; every one of them that
  -- touches wScriptVar writes 0 on the no-adapter path.
  -- -------------------------------------------------------------------------
  CheckLinkTimeout_Receptionist = "g2_unavailable",
  CheckBothSelectedSameRoom = "g2_unavailable",
  CheckMobileAdapterStatusSpecial = "g2_unavailable",
  CableClubCheckWhichChris = "g2_unavailable",
  Special_CableClubCheckWhichChris = "g2_unavailable",
  AskMobileOrCable = "g2_unavailable",
  Mobile_SelectThreeMons = "g2_unavailable",
  CheckMysteryGift = "g2_unavailable",
  UnlockMysteryGift = "g2_unavailable",
  GetMysteryGiftItem = "g2_unavailable",
  Function101225 = "g2_unavailable",
  Function101231 = "g2_unavailable",
  Function1011f1 = "g2_unavailable",
  Function101220 = "g2_unavailable",
  Function1037c2 = "g2_unavailable",
  Function1037eb = "g2_unavailable",
  Function10383c = "g2_unavailable",
  Function10387b = "g2_unavailable",
  Function103780 = "g2_unavailable",

  -- POLISHED CRYSTAL'S OWN NAMES for operations this VM already models.
  --
  -- The prefix rule above (specialKey) reaches the ones this cartridge spells
  -- `Special_<X>` over a name the tables already carry.  These are the rest:
  -- the routine was RENAMED as well as prefixed, so there is nothing for a
  -- rule to strip and the pairing has to be stated.  Each was matched by what
  -- the routine is, not by how close the spelling is.
  --
  --   FindThatSpecies            Crystal's FindPartyMonThatSpecies -- "is this
  --                              species in your party", and the ...
  --                              YourTrainerID form is the same test limited
  --                              to mons you raised.  38 call sites each.
  --   CianwoodPhotograph         the photo studio.  Crystal's special is
  --                              named after the building, this one after
  --                              what it does.
  --   DaisyMassage               Daisy's grooming.
  --   SoftReset                  Crystal calls the same routine `Reset`.
  --   RandomPhoneRareWildMon     the phone caller's "a rare one is out here"
  --                              line.  Crystal has only the common form, and
  --                              this port has no rare table to roll -- but
  --                              the buffer it fills is the one the line
  --                              splices, and leaving it unwritten prints
  --                              whatever species was in there from an
  --                              earlier call, which is the exact failure the
  --                              common form was fixed for.
  --   HallOfFame                 the induction the `halloffame` OPCODE also
  --                              reaches; this build offers it as a special
  --                              as well.
  --
  -- The two link routines answer a definite "unavailable" for the same reason
  -- every cable-club special above does: the port cannot link, and a script
  -- that branches on a stale wScriptVar takes an arm at random.
  Special_FindThatSpecies = "g2_find_party_species",
  Special_FindThatSpeciesYourTrainerID = "g2_find_party_species_own",
  Special_CianwoodPhotograph = "g2_photo_studio",
  Special_DaisyMassage = "g2_daisys_grooming",
  SoftReset = "g2_soft_reset",
  RandomPhoneRareWildMon = "g2_random_phone_wild_mon",
  HallOfFame = "record_hall_of_fame",
  PerformLinkChecks = "g2_unavailable",
  Special_CheckLinkTimeout = "g2_unavailable",
  -- "is the dex at least this full?", against the 16-bit number the script
  -- just set -- see the note on Commands.g2_dex_seen_at_least
  CountSeen = "g2_dex_seen_at_least",
  CountCaught = "g2_dex_caught_at_least",
  -- BeastsCheck's two siblings, keyed bare so the prefix rule reaches this
  -- cartridge's SpecialBirdsCheck / SpecialDuoCheck the same way it reaches
  -- its SpecialBeastsCheck
  BirdsCheck = "g2_birds_check",
  DuoCheck = "g2_duo_check",
  CheckBattleCaughtResult = "g2_battle_caught",
  GetOvercastIndex = "g2_overcast_index",
  CheckIfTrendyPhraseIsLucky = "g2_trendy_phrase_lucky",
  -- ...and one whose NAME is the least useful thing about it: see
  -- Commands.g2_warp_to_spawn_point.
  WarpToSpawnPoint = "g2_warp_to_spawn_point",
}

-- Fades / presentation (Route 24 Rocket uses FadeOutMusic + FadeOutToBlack +
-- ReloadSpritesNoPalettes + FadeInFromBlack after the battle)
local SPECIALS_NOOP = {
  FadeOutToWhite = true,
  FadeOutToBlack = true,
  FadeInFromWhite = true,
  FadeInFromBlack = true,
  ReloadSpritesNoPalettes = true,
  ClearBGPalettes = true,
  UpdateTimePals = true,
  ClearTilemap = true,
  UpdateSprites = true,
  UpdatePlayerSprite = true,
  WaitSFX = true,
  PlayMapMusic = true,
  FadeOutMusic = true,
  -- Presentation and dummy specials, most of them Crystal-only.  These MUST
  -- lower to nothing rather than fall through to g2_special, because that
  -- handler used to answer `lastCheck = false` -- so a palette reload or a cry
  -- sitting between a checkevent and its iftrue silently flipped the branch.
  -- Crystal has 112 unhandled specials to Gold's 55, which is why it bites
  -- there first.
  ClearBGPalettesBufferScreen = true,
  LoadMapPalettes = true,
  RefreshSprites = true,
  SetPlayerPalette = true,
  BattleTowerFade = true,
  StubbedTrainerRankings_Healings = true,
  PlayCurMonCry = true,
  PlaySlowCry = true,
  SurfStartStep = true,
  -- decorations are not modelled, so toggling their visibility does nothing
  ToggleDecorationsVisibility = true,
  ToggleMaptileDecorations = true,
  UnusedDummySpecial = true,
  UnusedBattleTowerDummySpecial1 = true,
  UnusedBattleTowerDummySpecial2 = true,
  -- the mobile-only failure box the room menu can raise; the port's menu
  -- never answers anything but 0 or CANCEL, so this branch is unreachable
  BattleTowerMobileError = true,
  -- PRISM'S FADES.  Its SpecialsPointers table is its own, and these four
  -- rows carry labels the base games do not print: `FadeOutPalettes` and
  -- `FadeInPalettes` unprefixed (Crystal reaches the same routines under
  -- Special_ names, which is why only Prism trips on them), plus
  -- Special_FadeInQuickly and RunSpritesCallback.  Counted over Prism's
  -- lowered scripts they are 38, 11, 2 and 5 call sites -- 56 in all, and
  -- every one of them was falling through to `g2_special`.
  --
  -- That matters for more than the warning.  g2_special answers
  -- `lastCheck = false`, so a fade standing between a checkevent and its
  -- iftrue silently flipped the branch -- the same failure the Crystal block
  -- above exists to prevent.  A palette fade decides nothing, so it lowers
  -- to nothing.  Both spellings are listed because the label the extractor
  -- reads back is whichever symbol the ROM's own table points at.
  FadeOutPalettes = true,
  Special_FadeOutPalettes = true,
  FadeInPalettes = true,
  Special_FadeInPalettes = true,
  FadeInQuickly = true,
  Special_FadeInQuickly = true,
  RunSpritesCallback = true,
  Special_RunSpritesCallback = true,
  Special_ClearBGPalettesBufferScreen = true,
  Special_ReloadSpritesNoPalettes = true,
  Special_BattleTowerFade = true,

  -- The link routines that do NOT write wScriptVar.  These have to lower to
  -- nothing rather than to g2_unavailable: zeroing the variable on their
  -- behalf would clobber a value the surrounding script set itself, which is
  -- the mirror image of the stale-value bug the rest of this work fixes.
  -- Checked one at a time against pret; the ones that DO write it are in
  -- SPECIALS above.
  WaitForOtherPlayerToExit = true,
  CloseLink = true,
  WaitForLinkedFriend = true,
  FailedLinkToPast = true,
  SetBitsForLinkTradeRequest = true,
  SetBitsForBattleRequest = true,
  SetBitsForTimeCapsuleRequest = true,
  CheckTimeCapsuleCompatibility = true,
  EnterTimeCapsule = true,
  TradeCenter = true,
  Special_TradeCenter = true,
  Colosseum = true,
  Special_Colosseum = true,
  TimeCapsule = true,
  Special_TimeCapsule = true,
  DisplayLinkRecord = true,
  Special_DisplayLinkRecord = true,
  -- presentation only: the Celebi sprite animation over the Ilex shrine, and
  -- Prism's own fade wrappers that turned up alongside it
  CelebiShrineEvent = true,
  Special_CelebiShrineEvent = true,

  -- POLISHED CRYSTAL'S PRESENTATION AND SAVE-STATE SPECIALS.
  --
  -- Nothing branches on any of these -- they paint, they reload a font, or
  -- they move bytes into SRAM -- so a no-op is the whole of what the port
  -- owes them, exactly as it is for Crystal's fades above.
  --
  --   ClearTileMap                     Crystal spells it ClearTilemap.
  --   FadeBlackQuickly /               two more fade wrappers this build adds
  --   FadeInPalettes_EnableDynNoApply  beside the ones already listed.
  --   LoadFonts_NoOAMUpdate            reloads the text font mid-scene; this
  --                                    port's font is always loaded.
  --   SaveOptions                      writes the options block to SRAM, which
  --                                    the port persists for itself.
  --   SaveMusic / RestoreMusic /       a PAIR that parks the current track
  --   DeleteSavedMusic                 over a scene and puts it back.  Both
  --                                    halves no-op together, so the track
  --                                    simply keeps playing -- which is the
  --                                    outcome the pair exists to produce.
  --   ShowItemIcon / ShowKeyItemIcon / the little icon beside a "received"
  --   ShowTMHMIcon                     line; give_item already prints the line.
  ClearTileMap = true,
  Special_FadeBlackQuickly = true,
  FadeInPalettes_EnableDynNoApply = true,
  LoadFonts_NoOAMUpdate = true,
  SaveOptions = true,
  SaveMusic = true,
  RestoreMusic = true,
  DeleteSavedMusic = true,
  ShowItemIcon = true,
  ShowKeyItemIcon = true,
  ShowTMHMIcon = true,
}

-- Specials that print their own prompt and are immediately followed by a
-- `yesorno` confirming it.  Emitting the last box as a show_text row lets
-- L.yesorno fold it exactly as it folds a real writetext.
local SPECIALS_PROMPT = {
  InitialSetDSTFlag = { "g2_set_dst", "InitialSetDSTFlag.DSTIsThatOKText" },
  InitialClearDSTFlag = { "g2_clear_dst", "InitialClearDSTFlag.TimeAskOkayText" },
}

-- The three tables above are keyed by the special's pret LABEL rather than by
-- its SpecialsPointers index, because the index is not portable between the
-- two games.  Gold has 129 specials and Crystal 207, and they agree only up to
-- $2E: Crystal inserts BattleTowerFade at $2F, which pushes 59 of Gold's the
-- rest of the way up by one.  Lowered against Gold's numbering, a Crystal
-- script asking for $3D landed on HealMachineAnim -- Poke Balls drifting over
-- whoever you happened to be talking to -- and one asking for $4A landed on
-- GiveShuckle, which is where the two SHUCKIE in a new Crystal party came
-- from.
--
-- ir[3] is the label the extractor resolved off SpecialsPointers.  A dataset
-- extracted before that existed carries only the index, so fall back to
-- reading it as a Gold index: correct for Gold and Silver, and no worse than
-- before for Crystal until the cartridge is re-imported.
-- Gold/Silver SpecialsPointers indices for the labels above, so a dataset
-- extracted before the importer started emitting labels still lowers.
-- Read off the cartridge, not typed out.
local GOLD_SPECIAL_LABELS = {
  [0x1B] = "HealParty",
  [0x1E] = "DayCareMan",
  [0x1F] = "DayCareLady",
  [0x20] = "DayCareManOutside",
  [0x21] = "MoveDeletion",
  [0x22] = "BankOfMom",
  [0x23] = "MagnetTrain",
  [0x24] = "NameRival",
  [0x25] = "SetDayOfWeek",
  [0x26] = "OverworldTownMap",
  [0x27] = "UnownPrinter",
  [0x28] = "MapRadio",
  [0x29] = "UnownPuzzle",
  [0x2A] = "SlotMachine",
  [0x2B] = "CardFlip",
  [0x2E] = "FadeOutToWhite",
  [0x2F] = "FadeOutToBlack",
  [0x30] = "FadeInFromWhite",
  [0x31] = "FadeInFromBlack",
  [0x32] = "ReloadSpritesNoPalettes",
  [0x33] = "ClearBGPalettes",
  [0x34] = "UpdateTimePals",
  [0x35] = "ClearTilemap",
  [0x36] = "UpdateSprites",
  [0x37] = "UpdatePlayerSprite",
  [0x3A] = "WaitSFX",
  [0x3B] = "PlayMapMusic",
  [0x3C] = "RestartMapMusic",
  [0x3D] = "HealMachineAnim",
  [0x44] = "DayCareMon1",
  [0x45] = "DayCareMon2",
  [0x4A] = "GiveShuckle",
  [0x4B] = "ReturnShuckie",
  [0x4C] = "BillsGrandfather",
  [0x4D] = "CheckPokerus",
  [0x4E] = "DisplayCoinCaseBalance",
  [0x4F] = "DisplayMoneyAndCoinBalance",
  [0x50] = "PlaceMoneyTopRight",
  [0x51] = "CheckForLuckyNumberWinners",
  [0x52] = "CheckLuckyNumberShowFlag",
  [0x53] = "ResetLuckyNumberShowFlag",
  [0x54] = "PrintTodaysLuckyNumber",
  [0x55] = "SelectApricornForKurt",
  [0x56] = "NameRater",
  [0x5D] = "LoadUsedSpritesGFX",
  [0x5F] = "SnorlaxAwake",
  [0x60] = "OlderHaircutBrother",
  [0x61] = "YoungerHaircutBrother",
  [0x62] = "DaisysGrooming",
  [0x64] = "ProfOaksPCBoot",
  [0x66] = "TrainerHouse",
  [0x67] = "PhotoStudio",
  [0x68] = "InitRoamMons",
  [0x69] = "FadeOutMusic",
  [0x6A] = "Diploma",
  [0x6B] = "PrintDiploma",
  [0x6C] = "InitialSetDSTFlag",
  [0x6D] = "InitialClearDSTFlag",
}

-- A SPECIAL'S LABEL, NORMALISED PAST THIS CARTRIDGE'S OWN PREFIX.
--
-- POLISHED CRYSTAL NAMES MOST OF ITS SPECIALS `Special_<X>` OR `Special<X>`,
-- and every table below is keyed on `<X>` -- which is what Gold, Silver and
-- Crystal call the same routine.  The extractor resolves a special's index by
-- following the SpecialsPointers row (`db bank, dw address`) to the routine
-- it points at and naming THAT, so what arrives here is the routine's own
-- label, prefix and all.
--
-- Measured against the cartridge itself: of the 160 rows its table names, 70
-- matched a key outright and 25 more differ from one by nothing but that
-- prefix -- SpecialNameRater, SpecialSnorlaxAwake, SpecialBuenasPassword,
-- SpecialBeastsCheck, the Ho-Oh and Omanyte chambers, Bill's grandfather, the
-- four lucky-number routines, both DST flags, SurfStartStep and the Bug
-- Contest contestant draw.  Falling through to `g2_special` does not just
-- skip them: it leaves wScriptVar holding whatever the previous row put
-- there, so a special standing between a check and its `iftrue` flips the
-- branch.
--
-- The trailing `Special` comes off as well, for a cartridge whose table
-- labels the ROW rather than the routine (`add_special X` emits `XSpecial::`
-- over the row, and this build does that too -- all 160 rows carry such a
-- label).  The extractor prefers the shortest symbol at the TARGET address,
-- so that spelling does not reach here on this build; it costs nothing and
-- the two rules compose for one that does.
--
-- THE EXACT KEY IS ALWAYS TRIED FIRST, so nothing that resolves today can
-- start resolving to something else; this only changes what happens after a
-- miss.  Checked: every key in the three tables still maps to itself, so Gold,
-- Silver, Crystal and Prism are untouched.  The 65 that remain are genuinely
-- this hack's own -- hidden grottoes, its Battle Tower rework, Hyper Training,
-- Wonder Trade, the maniac price checks -- and stay in the audit.
local function specialUnprefixed(name)
  return name:match("^Special_(.+)$") or name:match("^Special(%u.*)$")
end

local function specialKnown(name)
  return name ~= nil
    and (SPECIALS[name] or SPECIALS_NOOP[name] or SPECIALS_PROMPT[name]) ~= nil
end

local function specialKey(key)
  if specialKnown(key) then return key end
  local bare = specialUnprefixed(key)
  if specialKnown(bare) then return bare end
  local base = key:match("^(.+)Special$")
  if base then
    if specialKnown(base) then return base end
    bare = specialUnprefixed(base)
    if specialKnown(bare) then return bare end
  end
  return key
end

L.special = function(ir, s)
  local key = ir[3]
  if type(key) ~= "string" then key = GOLD_SPECIAL_LABELS[ir[2]] end
  if key == nil then
    emit(s, { "g2_special", ir[2] })
    return
  end
  key = specialKey(key)
  if SPECIALS_NOOP[key] then return end
  local prompt = SPECIALS_PROMPT[key]
  if prompt then
    emit(s, { prompt[1] })
    s.lastText = prompt[2]
    emit(s, { "show_text", prompt[2] })
    s.lastTextRow = #s.out
    return
  end
  local name = SPECIALS[key]
  if name then emit(s, { name }) else emit(s, { "g2_special", ir[2] }) end
end

-- `callasm` names a routine, and the extractor resolves the bank:address pair
-- back to its pret label.  The field-move std scripts (AskStrengthScript,
-- AskRockSmashScript) are nothing BUT a callasm and a branch on wScriptVar,
-- so leaving these unlowered is what made every boulder run its yes/no with
-- no party check at all.
local ASM = {
  HasRockSmash     = { "g2_party_move", "ROCK_SMASH", true },
  -- Prism's own name for the same test, and it really is the same test:
  -- CanUseRockSmash (engine/field_moves.asm) is `CheckEngine
  -- ENGINE_MUSCLEBADGE / CheckPartyMove ROCK_SMASH`, answering 1 when either
  -- fails and 0 when both pass -- which is the polarity g2_party_move already
  -- writes, and partyKnows already charges the badge from constants.hmBadges
  -- (Prism lists ROCK_SMASH -> ENGINE_MUSCLEBADGE).  Unlowered,
  -- AskRockSmashScript's `sif =, 1` read whatever the previous command left,
  -- so a breakable rock either refused a player who could smash it or skipped
  -- straight past the "you have no HM" line for one who could not.
  CanUseRockSmash  = { "g2_party_move", "ROCK_SMASH", true },
  TryStrengthOW    = { "g2_try_strength" },
  SetStrengthFlag  = { "g2_strength_on" },
  GetPartyNickname = { "g2_party_nickname" },
  RockMonEncounter = { "g2_rock_encounter" },
  -- BattleTowerHallwayChooseBattleRoomScript.asm_load_battle_room (27:$75CB)
  -- puts the chosen level group in wScriptVar; the ifequal chain right after
  -- it is what walks the player to the L10-20 / L30-40 / ... door.  The
  -- extractor only resolves top-level labels, so a dotted one arrives as its
  -- raw bank:address -- both spellings are listed, and the wrong one simply
  -- never matches.
  ["BattleTowerHallwayChooseBattleRoomScript.asm_load_battle_room"] =
    { "g2_battle_tower_room_index" },
  ["27:75CB"] = { "g2_battle_tower_room_index" },
  -- BlindingFlash (Prism 50:$77A8) is the routine HM FLASH itself ends in:
  -- it sets ENGINE_FLASH and repaints the map.  Prism reaches it from a
  -- SCRIPT as well -- Mound Cave's light switch is `findpokemontype ELECTRIC
  -- / yesorno / fieldmovepokepic / playwaitsfx / callasm BlindingFlash` --
  -- and with no row here callasm returned without emitting anything, so the
  -- player answered YES and the cave stayed dark.
  BlindingFlash = { "g2_blinding_flash" },
  ["50:77A8"] = { "g2_blinding_flash" },
  -- The Oxalis Salon's makeover.  The screen it opens has existed since
  -- PrismCustomization was written -- the new game runs it -- but nothing
  -- reached it from a script, so the salon took the player's money, ran no
  -- routine, and fell into arm 0 of its own jump table: refund, then "That's
  -- a big disappointment."  See Commands.g2_prism_salon for the three values.
  OxalisSalonCustomization = { "g2_prism_salon" },
  -- Prism's Pokemon orphanage.  The donation lady scores the chosen party mon
  -- and removes it; the adoption lady prices a row of her list against the
  -- points.  See the block in Gen2Commands under "Prism's Pokemon orphanage".
  IsThisPokemonPlayerLarvitar = { "g2_orphan_refuses_mon" },
  OrphanageCalculatePoints    = { "g2_orphan_points" },
  DeletePartyPoke             = { "g2_delete_party_mon" },
  CheckOrphanPointsFromScript = { "g2_check_orphan_points" },
  TakeOrphanPointsFromScript  = { "g2_take_orphan_points" },
  -- OrphanageDonationLady.process_donation: a LOCAL label, and the symbol
  -- export keeps none of those, so the extractor can only name it by bank and
  -- address -- the same way the Battle Tower's room chooser is listed above.
  ["17:6D3A"] = { "g2_orphan_donate" },
  -- Prism's Pachisi board.  Five routines over two flat byte tables per board
  -- -- the tile at each position and the step that leaves it -- plus the
  -- position counter the script keeps in an event variable.  See the block in
  -- Gen2Commands under "Prism's PACHISI BOARD".
  FacePlayerToNextTile = { "g2_pachisi_face" },
  CreatePachisiPath    = { "g2_pachisi_path" },
  BackwardsTile        = { "g2_pachisi_back" },
  GetPachisiTile       = { "g2_pachisi_tile" },
  PachisiGetPokemon    = { "g2_pachisi_mon" },
  GetPachisiItem       = { "g2_pachisi_item" },
}

-- Two of those read the SCRIPT STREAM themselves: CheckOrphanPointsFromScript
-- and TakeOrphanPointsFromScript both open with LoadCoinAmountToMem ->
-- GetScriptHalfwordOrVar, so a halfword follows the callasm.  The extractor
-- reads it as a second operand (RomExtractorGen2, the "D" operand kind) and it
-- is passed through to the command here.
local ASM_TAKES_HALFWORD = {
  CheckOrphanPointsFromScript = true,
  TakeOrphanPointsFromScript = true,
}

L.callasm = function(ir, s)
  local row = ASM[ir[2]]
  if not row then return end
  local copy = {}
  for i = 1, #row do copy[i] = row[i] end
  if ASM_TAKES_HALFWORD[ir[2]] then copy[#copy + 1] = ir[3] end
  emit(s, copy)
end
L.memcallasm = L.callasm
L.setval = function(ir, s) emit(s, { "g2_setvar", ir[2] }) end
-- the 16-bit twin: the port's script variable is a Lua number either way
L.setval16 = function(ir, s) emit(s, { "g2_setvar", ir[2] }) end
L.addval = function(ir, s) emit(s, { "g2_addvar", ir[2] }) end
L.random = function(ir, s) emit(s, { "g2_random", ir[2] }) end

-- _GetVarAction.VarActionTable (3:$418D), `dw address, db flags` per entry.
-- Only the ones with a runtime model are lowered -- an unknown var reading 0
-- would take a branch the ROM never takes, which is worse than the
-- fall-through an unlowered readvar already gives.  Resolved against the Gold
-- symbol table:
--   1 wPartyCount      5 CountCaughtMons  6 CountSeenMons  7 CountBadges
--   9 PlayerFacing    10 hHours  11 DayOfWeek  14 UnownCaught
--   16 BoxFreeSpace   20 wSpecialPhoneCallID
-- Entry 9 is what the Ilex Forest Farfetch'd branches on: each of its eight
-- scripts scalls a stub that ends in `readvar 9`, then `ifequal`s the four
-- directions to pick which way the bird hops.  Leaving it unlowered left
-- g2Var at 0, so every approach took the same DOWN branch and the bird
-- shuttled back and forth.
local READ_VARS = {
  [1] = true, [4] = true,
  [5] = true, [6] = true, [7] = true, [9] = true,
  [10] = true, [11] = true, [12] = true, [13] = true, [14] = true,
  [15] = true, [16] = true, [18] = true, [19] = true, [20] = true,
  [23] = true,
  -- VAR_BLUECARDBALANCE ($18) and VAR_KENJI_BREAK ($1A).  RadioTower2F reads
  -- the first one three times in one script -- to cap the card, to award the
  -- point, and to check the cap again afterwards -- so leaving it unreadable
  -- meant Buena's whole Blue Card game ran on a variable that never changed.
  [24] = true, [26] = true,
}

L.readvar = function(ir, s)
  if READ_VARS[ir[2]] then emit(s, { "g2_readvar", ir[2] }) end
end
-- Persistent WRAM byte used by scripts (wUndergroundSwitchPositions, etc.).
-- ir[2] is the 16-bit address the disassembler emitted.
L.readmem = function(ir, s)
  emit(s, { "g2_readmem", ir[2] })
end

L.writemem = function(ir, s)
  emit(s, { "g2_writemem", ir[2] })
end

-- Older Gold listings used these names for the same thing:
L.copybytetovar = L.readmem
L.copyvartobyte = L.writemem
L.addvar = L.addval   -- if your extractor still emits addvar
-- `loadvar var, value` writes through the SAME VarActionTable.  Only var 3
-- (wBattleType, $D119) has a model here: RedGyarados (49:$4F6F) is
-- `loadvar 3, 7` -- BATTLETYPE_SHINY -- between its loadwildmon and its
-- startbattle, and LoadEnemyMon reads that byte to force the shiny DVs.
-- Leaving it unlowered is what made the Lake of Rage Gyarados blue.
local WRITE_VARS = { [3] = true }

-- The name `loadvar` means two different things in the two dialects, and the
-- operand tells them apart without a version flag: Crystal's is `db var, db
-- value` through the VarActionTable, whose twenty-seven indices are all under
-- $20, while Prism's Script_loadvar is `call GetScriptHalfword /
-- WriteScriptByteToHL` -- `dw address, db value`, which is Crystal's loadmem
-- and always names a WRAM address at $C000 or above.
L.loadvar = function(ir, s)
  local v = tonumber(ir[2]) or 0
  if v > 0xFF then
    emit(s, { "g2_loadmem", ir[2], ir[3] })
  elseif WRITE_VARS[v] then
    emit(s, { "g2_loadvar", v, ir[3] })
  end
end

-- --------------------------------------------------------- Prism's variables
-- Prism keeps Crystal's VAR_* numbering up to VAR_MAPNUMBER ($0d) and then
-- goes its own way (constants/script_constants.asm):
--
--   $0e  Crystal UNOWNCOUNT      Prism ROOFPALETTE
--   $0f          ENVIRONMENT           BOXSPACE
--   $10          BOXSPACE              XCOORD
--   $11          CONTESTMINUTES        YCOORD
--   $12          XCOORD                EVENTMONRESPAWN
--   $13          YCOORD                --  (NUM_VARS is $13)
--
-- g2_readvar is indexed by CRYSTAL's list, so every Prism read above $0d
-- landed on the wrong variable: `checkcode VAR_XCOORD` answered BoxFreeSpace's
-- constant 20, and VAR_BOXSPACE answered the map's environment byte.  Two of
-- Prism's have no port model at all and are dropped rather than aliased --
-- an unlowered read leaves the branch to fall through, a WRONG read takes a
-- branch the ROM never takes.
local PRISM_VAR_TO_PORT = {
  [0x0f] = 0x10,   -- BOXSPACE
  [0x10] = 0x12,   -- XCOORD
  [0x11] = 0x13,   -- YCOORD
}
local PRISM_VAR_UNMODELLED = {
  [0x0e] = true,   -- ROOFPALETTE
  [0x12] = true,   -- EVENTMONRESPAWN
}
local function prismVar(n)
  n = tonumber(n)
  if not n or PRISM_VAR_UNMODELLED[n] then return nil end
  if n <= 0x0d then return n end
  return PRISM_VAR_TO_PORT[n]
end

-- `checkcode <var>` IS Crystal's readvar: GetScriptByte / GetVarAction /
-- ld a, [de] / ldh [hScriptVar].  Prism has no command spelled readvar at
-- all, so all 67 of its variable reads were silent and every branch off one
-- ran on whatever the previous check had left in the script variable.
L.checkcode = function(ir, s)
  local v = prismVar(ir[2])
  if v and READ_VARS[v] then emit(s, { "g2_readvar", v }) end
end

-- `writecode <var>, <value>` is Crystal's loadvar (GetScriptByte /
-- GetVarAction / GetScriptByte / ld [de], a) -- the literal form.
L.writecode = function(ir, s)
  local v = prismVar(ir[2])
  if v and WRITE_VARS[v] then emit(s, { "g2_loadvar", v, ir[3] }) end
end

-- `writevar <var>` / `writevarcode <var>` (Prism's spelling) write the script
-- variable back THROUGH the same table.  Most of what the table exposes is
-- derived and cannot be written -- a party count, a badge count, the clock --
-- so only the handful of real stored bytes are lowered, and the rest stay a
-- deliberate no-op rather than a guess.
--
-- VAR_BLUECARDBALANCE is the one that matters: RadioTower2F awards Buena's
-- point with `readvar / addval 1 / writevar`, so with the write dropped the
-- balance was pinned at zero no matter how many nights the player turned up.
local WRITEBACK_VARS = { [24] = true, [26] = true }

L.writevar = function(ir, s)
  if WRITEBACK_VARS[ir[2]] then emit(s, { "g2_writevar", ir[2] }) end
end

L.writevarcode = function(ir, s)
  local v = prismVar(ir[2])
  if v and WRITEBACK_VARS[v] then emit(s, { "g2_writevar", v }) end
end

-- ------------------------------------------------------- the variable stack
-- Prism keeps a byte stack in WRAM that scripts push the script variable onto
-- and pop back off (ScriptVarStackOperation), which is how it holds a value
-- across a `scall` or across the arms of a conditional.  Ninety-three
-- instructions lowered to nothing, so every pop read a stale variable.
L.pushvar = function(_, s) emit(s, { "g2_pushvar" }) end
L.popvar  = function(_, s) emit(s, { "g2_popvar" }) end
-- Script_pullvar reads the top WITHOUT decrementing the stack pointer.
L.pullvar = function(_, s) emit(s, { "g2_peekvar" }) end
-- Script_swapvar exchanges the top of the stack with the script variable.
L.swapvar = function(_, s) emit(s, { "g2_swapvar" }) end
-- Script_swapbyte is `call Script_writebyte` falling into Script_swapvar.
L.swapbyte = function(ir, s)
  emit(s, { "g2_setvar", ir[2] })
  emit(s, { "g2_swapvar" })
end

-- ------------------------------------------------------ the halfword variable
-- hScriptHalfwordVar is a second, sixteen-bit script variable.  Prism uses it
-- two ways and both matter: as a value (a text pointer read out of an array,
-- handed to `jumptext -1`) and as an ADDRESS -- GetHalfwordVar returns it in
-- hl, so copyhalfwordvartovar is an indirect read of the WRAM byte it names.
L.writehalfword = function(ir, s) emit(s, { "g2_sethalfword", ir[2] }) end
L.pushhalfword = function(ir, s)
  emit(s, { "g2_sethalfword", ir[2] })
  emit(s, { "g2_pushhalfword" })
end
L.pushhalfwordvar = function(_, s) emit(s, { "g2_pushhalfword" }) end
L.pophalfwordvar  = function(_, s) emit(s, { "g2_pophalfword" }) end
L.pullhalfwordvar = function(_, s) emit(s, { "g2_peekhalfword" }) end
L.copyhalfwordvartovar = function(_, s) emit(s, { "g2_readmem" }) end
L.copyvartohalfwordvar = function(_, s) emit(s, { "g2_writemem" }) end
-- Script_addhalfwordtovar: halfword = <literal> + var.
-- Script_addhalfwordvartovar: halfword = halfword + var.
L.addhalfwordtovar = function(ir, s) emit(s, { "g2_addhalfword", ir[2] }) end
L.addhalfwordvartovar = function(_, s) emit(s, { "g2_addhalfword" }) end
L.addhalfwordtohalfwordvar = function(ir, s)
  emit(s, { "g2_addhalfwordvalue", ir[2] })
end
L.copybytetohalfwordvar = function(ir, s) emit(s, { "g2_readmem16", ir[2] }) end

-- Script_addbytetovar adds the WRAM BYTE at an address to the variable.
L.addbytetovar = function(ir, s) emit(s, { "g2_addmem", ir[2] }) end
-- Script_multiplyvar: `inc a / jr nz` -- an operand of $ff negates instead.
L.multiplyvar = function(ir, s) emit(s, { "g2_mulvar", ir[2] }) end

-- Script_getweekday is UpdateTime / GetWeekday into the script variable,
-- which is exactly what VAR_WEEKDAY ($0b) already answers.
L.getweekday = function(_, s) emit(s, { "g2_readvar", 11 }) end

-- Script_toggleevent reads an event flag and writes back the other way.
L.toggleevent = function(ir, s) emit(s, { "g2_toggle_flag", eventFlag(ir[2]) }) end
L.toggle = L.toggleevent

-- Script_paragraphdelay is ClearSpeechBox / UnloadBlinkingCursor / eighteen
-- frames -- presentation only, and the port's text box paginates itself.
L.paragraphdelay = noop

-- ------------------------------------------------------------- jump tables
-- `jumptable <ptr>` CALLS the case the script variable selects and comes back
-- (`ld b, 1` into ScriptJumptable, whose LocalScriptJump arm is anonjumptable's
-- b=0).  The extractor has already followed the table and queued each case, so
-- ir[2] is a list of labels; what is left is the dispatch, which the port's IR
-- has no single row for.  Built as a compare-and-call chain, so an index the
-- table does not cover falls straight through exactly as the ROM's would.
-- `givebadge <n>` -- polished's own command where Gold and Crystal run
-- `setflag ENGINE_<X>BADGE`.  Script_givebadge (25:$73f7): an operand of
-- $10-$17 is a Kanto badge and gets `xor $18` down to bits 8-15, then the
-- engine flag is badge + $21 -- the same Johto-then-Kanto bit order the
-- flag table already names.  Unlowered, beating a gym gave NO badge, so no
-- HM ever became usable.
local GIVEBADGE_NAMES = {
  [0] = "ZEPHYRBADGE", "HIVEBADGE", "PLAINBADGE", "FOGBADGE",
  "MINERALBADGE", "STORMBADGE", "GLACIERBADGE", "RISINGBADGE",
  "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
  "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
}
L.givebadge = function(ir, s)
  local n = ir[2] or 0
  if n >= 0x10 then n = n - 0x10 + 8 end
  local name = GIVEBADGE_NAMES[n]
  if name then emit(s, { "set_flag", name }) end
end

-- `showcrytext <text>, <species>`: PlayMonCry then the box.  The cry uses
-- the same g2_cry the standalone command does; a species of 0 leans on the
-- runtime's current-mon fallback.
L.showcrytext = function(ir, s)
  local species = ir[3]
  emit(s, { "g2_cry", (species and species > 0)
    and string.format("SPECIES_%03d", species) or nil })
  s.lastText = ir[2]
  showText(s, ir[2])
  s.lastTextRow = #s.out
end

-- `scalltable <ptr>`: call one script out of a dw table by the script
-- variable.  The extractor resolves the table to labels, so this is
-- jumptable's shape with a RETURN to the caller either way -- which
-- jumptable's g2_call arms already model.
L.scalltable = function(ir, s)
  return L.jumptable(ir, s)
end

-- Prism's two INLINE jump tables (Script_anonjumptable 25:$6B22 and the menu
-- form above it).  The cases are the bytes the script pointer is standing on
-- rather than a pointer's target, and the extractor has already resolved them
-- into the same list of labels `jumptable` takes -- appended after whatever
-- operands the command has, so anonjumptable carries them in ir[2] and
-- menuanonjumptable (whose one operand is its menu data) in ir[3].
L.anonjumptable = function(ir, s)
  return L.jumptable({ "jumptable", ir[2] }, s)
end
-- and the menu form RUNS THE MENU FIRST.  Script_menuanonjumptable is
-- `Script_loadmenudata / Script_verticalmenu / Script_closewindow` and only
-- then falls into anonjumptable -- so the script variable the table is indexed
-- by is the player's CHOICE, not whatever the row before it left there.
-- Lowering it as a bare jump table sent every one of these menus down the
-- branch the previous command happened to select.
L.menuanonjumptable = function(ir, s)
  if type(ir[2]) == "table" then
    emit(s, { "g2_loadmenu", ir[2] })
    emit(s, { "g2_verticalmenu" })
  end
  return L.jumptable({ "jumptable", ir[3] }, s)
end

-- Prism's names for the menu Crystal calls `loadmenu`, and its scrolling list.
-- The scrolling form differs only in resetting the cursor and scroll position
-- (Script_loadscrollingmenudata is loadmenudata plus two stores), and
-- `scrollingmenu <flags>` is the vertical menu with the flags deciding whether
-- a speech box is drawn behind it -- presentation either way, and the answer it
-- leaves in the script variable is the same.
-- PRISM'S NAMES FOR THE THREE NAME-BUFFERING COMMANDS, with the operand order
-- taken from the macros rather than from the handlers' register juggling:
--
--   trainertotext    trainer_id, trainer_group, memory
--   landmarktotext   id, memory
--   trainerclassname id, memory
--
-- which is the same "value first, buffer second" shape `getlandmarkname`
-- already uses.  A class name is the group's own name with no party member
-- picked out of it, so it asks for member 0.
L.trainertotext = function(ir, s)
  emit(s, { "g2_buffer_trainer_name", ir[3], ir[2], ir[4] })
end
L.landmarktotext = L.getlandmarkname
L.trainerclassname = function(ir, s)
  emit(s, { "g2_buffer_trainer_name", ir[2], 0, ir[3] })
end

-- `copyvarbytetovar` reads the byte at the address the halfword variable is
-- holding -- the read `loadhalfwordvar` writes for -- and is the same
-- indirection `copyhalfwordvartovar` makes, which is why it shares its row.
L.copyvarbytetovar = function(_, s) emit(s, { "g2_readmem" }) end

-- `backupcustchar` / `restorecustchar` bracket the sections where the player
-- IS a Pokemon (Laurel Forest, the Magikarp Caverns).  With the restore
-- silent, coming back out of one left the player as whatever the section had
-- made them, permanently.
L.backupcustchar = function(_, s) emit(s, { "g2_backup_custchar" }) end
L.restorecustchar = function(_, s) emit(s, { "g2_restore_custchar" }) end

L.loadmenudata = L.loadmenu
L.loadscrollingmenudata = L.loadmenu
L.scrollingmenu = function(_, s) emit(s, { "g2_verticalmenu" }) end

-- Cosmetic commands with no port-side effect: object palette overrides and
-- the Unown-report typeface switch.  Lowered to nothing ON PURPOSE so the
-- audit stops counting them as missing behaviour -- the palette is per-map
-- art the renderer already bakes, and the typeface swap is Gen 2 VRAM
-- mechanics the port's font pipeline replaced.
L.setmapobjectpal = function() end
L.unowntypeface = function() end
L.restoretypeface = function() end

-- `waitendtext`: hold the box until A, then end -- the by-far most common
-- unlowered command (183 sites).  endtext is already "end", and show_text
-- rows arm their own button wait, so the remaining meaning is the end.
L.waitendtext = function(_, s) emit(s, { "g2_return" }) end

L.jumptable = function(ir, s)
  local cases = ir[2]
  if type(cases) ~= "table" or #cases == 0 then return end
  local done = s.newLabel()
  for i = 1, #cases do
    local to = branch(s, cases[i])
    if to then
      local skip = s.newLabel()
      emit(s, { "g2_compare", "eq", i - 1 })
      emit(s, { "jump_if_false", skip })
      emit(s, { "g2_call", done })
      emit(s, { "jump", to })
      emit(s, { "label", skip })
    end
  end
  emit(s, { "label", done })
end

-- ----------------------------------------------------------------- arrays
-- Script_loadarray parks a far pointer, an entry size and a current-entry
-- index taken from the script variable; readarray / readarrayhalfword then
-- read base + size * entry + index.  The blob and, where the entries are text
-- pointers, the labels for them come from the extractor -- the runtime has no
-- ROM to reach into.
L.loadarray = function(ir, s)
  local array = ir[2]
  if type(array) ~= "table" then return end
  emit(s, { "g2_loadarray", array })
end
L.readarray = function(ir, s) emit(s, { "g2_readarray", ir[2] }) end
L.readarrayhalfword = function(ir, s)
  emit(s, { "g2_readarrayhalfword", ir[2] })
end

-- Script_comparevartobyte compares the script variable against the WRAM byte
-- at an address and answers a THREE-way result in the variable itself:
-- 0 greater, 1 less, 2 equal.  The scripts that use it then branch on that
-- value, so leaving it unlowered left the previous check's result in place.
L.comparevartobyte = function(ir, s) emit(s, { "g2_comparemem", ir[2] }) end

-- `ptcall` / `ptjump` name a three-byte FAR pointer (`ld b, [hl] / ld e, [hl]
-- / ld d, [hl]`) rather than a script.  Where that pointer sits in ROM the
-- extractor has already dereferenced and queued it, so ir[2] arrives as an
-- ordinary label; where it sits in WRAM there is nothing to resolve and the
-- row is dropped, exactly as Crystal's memcall is.
L.ptcall = function(ir, s)
  if type(ir[2]) == "string" and ir[2] ~= "" then L.scall(ir, s) end
end
L.ptjump = function(ir, s)
  if type(ir[2]) == "string" and ir[2] ~= "" then L.sjump(ir, s) end
end

-- `changeblock x, y, block` (ChangeBlock, engine/overworld/scripting.asm)
-- rewrites one block of the loaded map and redraws it.  The Ruins of Alph
-- chambers use it for the hole that opens in the wall once their puzzle is
-- solved, and the same idiom drives cut trees and opened doors elsewhere.
--
-- GetBlockLocation shifts both coordinates right once, so the script's
-- arguments are in half-block (tile) units -- every one of the 212 uses in
-- the ROM is even on both axes.  `replace_block` indexes blocks directly.
L.changeblock = function(ir, s)
  local x, y = tonumber(ir[2]), tonumber(ir[3])
  if not (x and y) then return end
  emit(s, { "replace_block", math.floor(x / 2), math.floor(y / 2), ir[4] })
end

-- `variablesprite slot, sprite` (Script_variablesprite, 25:$7161) writes one
-- entry of wVariableSprites.  Object events with a sprite byte of $F0 or more
-- read it back, which is how Route 36 turns its "tree" into Sudowoodo.
L.variablesprite = function(ir, s)
  emit(s, { "g2_variablesprite", ir[2], ir[3] })
end

-- FruitTreeScript (17:$4000): tree n hands over FruitTreeItems[n] once, then
-- remembers the pick in wFruitTreeFlags until TryResetFruitTrees clears it.
L.fruittree = function(ir, s) emit(s, { "g2_fruittree", ir[2] }) end

-- `givetm <n>` / `givetmnomessage <n>` (Script_giveTM 25:$67F8, and $68B2 for
-- the quiet form).  The extractor has already turned the machine number into
-- the TM_nn / HM_nn item id (gen2MachineItem), because a machine is numbered
-- in a space of its own on this cartridge and there is nothing in the item
-- table at that number.  A cartridge where that did not resolve leaves a
-- number here, and a number is not an item, so nothing is emitted rather than
-- handing over whichever potion happens to share the id.
L.givetm = function(ir, s)
  if type(ir[2]) == "string" then emit(s, { "give_item", ir[2], 1 }) end
end
L.givetmnomessage = function(ir, s)
  if type(ir[2]) == "string" then emit(s, { "g2_giveitem", ir[2], 1 }) end
end

-- ---------------------------------------------------------------------------
-- POLISHED CRYSTAL'S TM/HM POCKET.
--
-- Five commands the cartridge dispatches in its own right -- Script_givetmhm,
-- Script_verbosegivetmhm, Script_checktmhm, Script_gettmhmname and
-- Script_tmhmnotify are all in the ROM's jumptable under those names -- and
-- between them they are 53 of the instructions the unhandled audit was still
-- counting.  Unhandled means the TM was never handed over: beating a gym
-- played the whole conversation and gave nothing, and the `checktmhm /
-- iftrue` that guards a second gift read a stale answer.
--
-- The operand is a MACHINE NUMBER, which the extractor has already turned
-- into the TM_nn / HM_nn item (see the note beside it).  A cartridge where
-- that did not resolve leaves a number here, and a number is not an item, so
-- nothing is emitted rather than handing over whichever potion shares the id
-- -- the same rule `givetm` above follows.
--
-- The verbose/silent split is the cartridge's own and matches the item
-- family beside it: `giveitem` is silent and `verbosegiveitem` prints, so
-- `givetmhm` is silent and `verbosegivetmhm` prints.
L.givetmhm = function(ir, s)
  if type(ir[2]) == "string" then emit(s, { "g2_giveitem", ir[2], 1 }) end
end
L.verbosegivetmhm = function(ir, s)
  if type(ir[2]) == "string" then emit(s, { "give_item", ir[2], 1 }) end
end
-- CheckTMHM/InnerCheckTMHM answer into wScriptVar, which is what the
-- `iftrue`/`iffalse` after it reads -- so an unresolved machine must still
-- write a definite answer rather than leave the last command's behind.
L.checktmhm = function(ir, s)
  if type(ir[2]) == "string" then
    emit(s, { "check_item", ir[2] })
  else
    emit(s, { "g2_false" })
  end
end
-- `gettmhmname <tmhm>, <buffer>`: the buffer operand is written LAST by
-- every name macro in this disassembly (getitemname, gettrainername,
-- getlandmarkname all do), so ir[2] is the machine and ir[3] the buffer --
-- and a machine is named exactly like the item it resolves to.
L.gettmhmname = function(ir, s)
  if type(ir[2]) == "string" then
    emit(s, { "g2_getitemname", ir[2], ir[3] })
  end
end
-- and the notify line, which `give_item` above already prints -- the same
-- reasoning as itemnotify and keyitemnotify.
L.tmhmnotify = function() end
L.keyitemnotify = function() end

-- PRISM'S EVENT VARIABLES (wEventVariables, sixty-four bytes at $D73D) are a
-- separate space from the event FLAGS checkevent/setevent use, and its longer
-- errands count with them.  The operand packs the operation into the top two
-- bits and the variable's index into the low six; `modifyeventvar`'s set and
-- add forms carry a second byte, which is why it reads with the `E` tail.
L.eventvarop = function(ir, s) emit(s, { "g2_eventvarop", ir[2] }) end
L.seteventvar = function(ir, s) emit(s, { "g2_seteventvar", ir[2] }) end
L.modifyeventvar = function(ir, s)
  emit(s, { "g2_modifyeventvar", ir[2], ir[3] })
end

-- `cmdwitharrayargs` BUILDS ONE OF SEVEN COMMANDS AND RUNS IT, with some of
-- its arguments taken from the array `loadarray` left loaded rather than from
-- the script (CreateScriptCommandWithCustomArguments, script_conditionals.asm).
--
-- Eighteen of Prism's thirty-one uses are `warp` with the destination
-- coordinates coming out of the array, so with no lowering there were eighteen
-- places where pressing a thing took the player nowhere.
--
-- The extractor has already decoded the blob into { command, args }, each
-- argument either a literal, a resolved map key, or an index into the array
-- entry; the runtime resolves the array ones and dispatches.
L.cmdwitharrayargs = function(ir, s)
  local built = ir[2]
  if type(built) ~= "table" or type(built.command) ~= "string" then return end
  emit(s, { "g2_cmd_array_args", built })
end

-- `givecraftingEXP <craft>` (Script_givecraftingEXP 25:$68C0): credit a
-- crafting level -- mining, smelting, ball making, jewel making -- with the
-- EXP the script variable is holding.  The whole mechanic is IncreaseCraftEXP;
-- see the note on g2_craft_exp for the level curve, which is the cartridge's
-- own integer square root rather than a table.  Twelve sites, and they are how
-- the mining and smelting a player does actually adds up to anything.
L.givecraftingEXP = function(ir, s) emit(s, { "g2_craft_exp", ir[2] }) end

-- `copy <dest>, <count>, <bytes...>` (Script_copy 25:$6DF1) writes a run of
-- raw bytes straight into WRAM.  The payload arrives through the `c` inline
-- blob tail, so ir[2] is the destination and ir[3] the bytes; the count is the
-- blob's own length and needs no separate argument.
L.copy = function(ir, s) emit(s, { "g2_copybytes", ir[2], ir[3] }) end

-- `loadhalfwordvar <value>` writes that byte to the address the halfword
-- variable is holding -- the write to the place copyhalfwordvartovar reads.
L.loadhalfwordvar = function(ir, s)
  emit(s, { "g2_writemem_value", ir[2] })
end

-- `isinsingulararray <array>`: the INDEX the script variable's value sits at
-- in the table, or $FF.  The extractor has already read the table's bytes.
L.isinsingulararray = function(ir, s)
  if type(ir[2]) == "string" and ir[2] ~= "" then
    emit(s, { "g2_find_in_array", ir[2] })
  end
end

-- ------------------------------------------------- Prism's remaining tail
--
-- `getnthstring <list>, <buffer>` (00:$2B30) is GetNthString -- skip the script
-- variable's count of "@"-terminated strings -- and then a copy of the one it
-- lands on into a string buffer, unless the buffer operand is $FF, in which
-- case only the POINTER is kept for the `copystring` that follows.  The list
-- itself is names in the ROM, so the extractor has already decoded it.
L.getnthstring = function(ir, s)
  if type(ir[2]) ~= "table" then return end
  emit(s, { "g2_nth_string", ir[2], ir[3] })
end

-- `copystring <buffer>` (25:$6C6A): the string getnthstring last named, into a
-- buffer.  The pair is how Prism's mining scripts splice an ore name into two
-- different lines without reading the table twice.
L.copystring = function(ir, s) emit(s, { "g2_copy_string", ir[2] }) end

-- `itemplural <buffer>` (25:$5B8B): pluralise the item name already sitting in
-- a string buffer, unless the script variable says there is only one of it.
-- The suffix rules and the dozen items that break them come from the ROM (see
-- gen2ItemPluralRules); nothing about them is spelled here.
L.itemplural = function(ir, s)
  if type(ir[3]) ~= "table" then return end
  emit(s, { "g2_item_plural", ir[2], ir[3] })
end

-- `readpersonxy <person>, <dest>` (25:$6BE8): where an object IS RIGHT NOW --
-- OBJECT_NEXT_MAP_X then OBJECT_NEXT_MAP_Y out of its live struct, not its
-- spawn row -- written as two bytes, or $FF $FF when the object is not on the
-- map.  Prison F1's guard script is `readpersonxy 5 / writebyte 39 /
-- comparevartobyte / sifne 2`: it runs only while that guard stands on a
-- particular tile, so unlowered the byte stayed zero and the gate never opened.
L.readpersonxy = function(ir, s)
  emit(s, { "g2_read_person_xy", ir[2], ir[3] })
end

-- `variablestablerandom <index>, <bound>` (25:$6339) is `random` with d=1, so
-- it takes its bits from VariableStableRandom (2C:$5C8F) instead of Random:
-- one draw per index that STAYS PUT until the game advances that index's
-- counter.  The bound and the rejection sampling are shared with `random`
-- itself (the `add a / jr nc` mask, then redraw while the value is too big).
L.variablestablerandom = function(ir, s)
  emit(s, { "g2_stable_random", ir[2], ir[3] })
end

-- `loadmemtrainer` (25:$66C5): the battle about to start is the trainer THIS
-- OBJECT already is -- wTempTrainerClass / wTempTrainerID, filled in when the
-- player talked to it -- rather than one a `loadtrainer` names.
L.loadmemtrainer = function(_, s) emit(s, { "g2_load_mem_trainer" }) end

-- `trainertext <n>` (25:$66A9): the n-th of the CURRENT trainer's own text
-- pointers -- seen, beaten, loss, after -- through wSeenTextPointer.  Prism's
-- generic-trainer objects carry their lines this way instead of writing a
-- `writetext` per trainer.
L.trainertext = function(ir, s) emit(s, { "g2_trainer_text", ir[2] }) end

-- `backupsecondpokemon` / `restoresecondpokemon` (25:$6A79 / $6AD3): Prism's
-- Pokemon mode stashes party slot 2 and shrinks the party to one, then puts it
-- back -- the same bracket `backupcustchar`/`restorecustchar` make around the
-- player's appearance, and they appear together at every site.
L.backupsecondpokemon = function(_, s) emit(s, { "g2_backup_second_mon" }) end
L.restoresecondpokemon = function(_, s) emit(s, { "g2_restore_second_mon" }) end

-- `checkpokemontype <type>` (25:$6A0B): open the party menu, and answer 1 when
-- the chosen mon is that type OR knows a move of it, 0 when it is neither, and
-- 2 when the player backed out -- which is why the site that follows it is a
-- three-way anonjumptable.
L.checkpokemontype = function(ir, s)
  emit(s, { "g2_check_mon_type", ir[2] })
end

-- `loadsignpost <text>` (25:$6B10) is the signpost window: RefreshScreen,
-- _Signpost on the pointer, CloseText, end.  Its one site takes the pointer
-- from the halfword variable a readarrayhalfword just loaded, which is the
-- same place `jumptext -1` reads its own.
L.loadsignpost = function(ir, s)
  showText(s, ir[2])
  emit(s, { "g2_return" })
end

-- the COIN CASE balance into string buffer 1, and checkitem against the PC
L.readcoins = function(_, s) emit(s, { "g2_readcoins" }) end
L.checkiteminbox = function(ir, s)
  emit(s, { "g2_check_item_box", itemId(ir[2]) })
end

-- `killsfx` (00:$0596) silences the sound channels.  Presentation only: the
-- port's audio layer has no per-channel kill and the next playsound replaces
-- whatever is running anyway.
L.killsfx = function() end

-- `divideby <n>` (25:$632C): `a = hScriptVar / n`, quotient back into the
-- script variable -- the same Divide the rest of the engine uses, so the
-- remainder is dropped.  Mining's `copybytetovar / divideby` pairs are what
-- turn a raw count into a level.
L.divideby = function(ir, s)
  local by = tonumber(ir[2])
  if by and by ~= 0 then emit(s, { "g2_divide_var", by }) end
end

-- `changemap <bank>, <blocks>` (Script_changemap 25:$66A4 -> ChangeMap
-- 00:$1868) is Prism's own, and it is NOT changeblock with more arguments: it
-- replaces the LOADED MAP'S WHOLE BLOCK TABLE from a compressed blob, reading
-- the map's own width and height to know how much to copy.
--
-- Reported from play: the five sticks of dynamite in Mound Cave.  The whole
-- scene ran -- the guy takes them, the player steps aside, the ground shakes
-- four times -- and the boulder was still there afterwards, because the one
-- command that actually opens the way was the one with no lowering.  The map's
-- script header re-applies the same swap on every later entry (`checkevent /
-- siftrue / changemap $1c, MoundF1_BlownUp_BlockData`), so it stayed shut for
-- good.
--
-- The extractor has already turned the operand into the decoded block bytes
-- (gen2MapBlockBlob); a cartridge where that did not resolve leaves a number
-- here, and a number is not a map, so the row is dropped rather than guessed.
L.changemap = function(ir, s)
  if type(ir[2]) == "table" and #ir[2] > 0 then
    emit(s, { "g2_changemap", ir[2] })
  end
end
-- POLISHED CRYSTAL'S NAME FOR THE SAME COMMAND -- and not the only command
-- called that.
--
-- Script_changemapblocks takes a FAR POINTER to a compressed block table, so
-- it is Prism's `changemap` exactly, and the extractor now decodes the
-- operand for it (the "D" arm).  Gold, Silver and Crystal also have a
-- `changemapblocks`, and it is a different command: three plain bytes, no
-- pointer.  Those rows arrive here as numbers, and the table guard drops
-- them untouched -- which is what they did before this existed, so the older
-- cartridges are no worse off and their command stays a known gap.
L.changemapblocks = function(ir, s)
  if type(ir[2]) == "table" and #ir[2] > 0 then
    emit(s, { "g2_changemap", ir[2] })
  end
end

-- The map-refresh family.  All of these redraw the loaded map after a
-- changeblock or a warp -- refreshmap/reloadmap/newloadmap re-run the tile
-- pass, reanchormap re-centres it -- and without them a block a script
-- rewrote stayed invisible until the player walked out and back in.
L.refreshmap = function(_, s) emit(s, { "g2_refreshmap" }) end
L.reloadmap = L.refreshmap
L.newloadmap = L.refreshmap
L.reanchormap = L.refreshmap
-- warpcheck re-tests the tile the player is standing on, which is how the
-- Ruins of Alph floor opens underfoot rather than on the next step.
L.warpcheck = function(_, s) emit(s, { "g2_warpcheck" }) end

L.earthquake = function(ir, s) emit(s, { "g2_earthquake", ir[2] }) end

-- setlasttalked retargets the object that applymovementlasttalked and
-- faceplayer act on, without the player having talked to it.
L.setlasttalked = function(ir, s) emit(s, { "g2_setlasttalked", ir[2] }) end

-- Game Corner coins are their own counter (wCoins), not the wallet.
L.checkcoins = function(ir, s) emit(s, { "g2_check_coins", ir[2] }) end
L.givecoins = function(ir, s) emit(s, { "g2_give_coins", ir[2] }) end
L.takecoins = function(ir, s) emit(s, { "g2_give_coins", -(ir[2] or 0) }) end

-- checkver reports which CARTRIDGE is running, and the answer is not the one
-- the first cut assumed.  Script_checkver is three instructions -- it loads a
-- single byte that sits immediately after it and writes it to wScriptVar --
-- and that byte reads 00 in Gold, 00 in Crystal and **01 in Silver**.  So the
-- axis is Silver vs everything else, not Crystal vs everything else.
--
-- Hard-coding 0 meant every `checkver; iftrue` in the game took the Gold arm
-- while playing Silver.  Five scripts carry that branch, and all five were
-- wrong:
--
--   RadioTower5FRocketBossScript   RAINBOW WING instead of SILVER WING (and
--                                  EVENT_GOT_RAINBOW_WING instead of 121)
--   PewterCityGrampsScript         the mirror of the same swap
--   Lugia (Whirl Islands)          Lv70 instead of Lv40
--   TinTowerHoOh                   Lv40 instead of Lv70
--   GoldenrodGameCornerPrizeMon    Gold's prize list
--
-- The bytecode already carries both arms -- this is purely which one the
-- comparison takes -- so no re-import is needed to pick up the fix.  A save
-- that already took the wrong arm keeps what it was given.
L.checkver = function(_, s)
  emit(s, { "g2_setvar",
            require("src.core.GameVersion").isSilver() and 1 or 0 })
end

-- Gold/Silver pass a map pair; Crystal passes kind then a map pair. The
-- extractor resolves the appropriate pair to its registry key.
L.swarm = function(ir, s) emit(s, { "g2_swarm", ir[2], ir[3] }) end

-- Deliberately nullary.  The port's text box owns its own lifecycle
-- (closewindow, closepokepic) and give_item already prints the line
-- itemnotify exists to print.
L.closewindow = function() end
L.itemnotify = function() end

-- ---------------------------------------------------------------------------
-- compiler
-- ---------------------------------------------------------------------------

-- The pool is claimed by PROVENANCE, not by version id.  Both generations
-- write data/generated/map_scripts.lua and both use the same row shape, so a
-- Gen 3 cache loaded here would be lowered against Gen 2's opcode names --
-- every one of which would miss, leaving 518 silent maps and no error.  The
-- extractor stamps its own name; that is the discriminator.
-- A POOL THIS VM DOES NOT OWN IS NOT THIS VM'S TO LOWER.
--
-- The test is a REFUSAL LIST rather than an allow list, and deliberately: a
-- Gen 1 cache and a hand-built developer pool both carry no `source` at all,
-- and demanding one would silently unhook every Kanto script.  So anything
-- unlabelled is still Gen 2's.
--
-- GEN 4 WAS MISSING FROM THAT LIST, and the cost was not theoretical.  A
-- Platinum cache walked straight in: this VM lowered Platinum's decoded
-- instructions with Gen 2 semantics and attached the result to 478 maps as
-- their SCENE and coord-event wiring -- "gen2 script vm: 478 maps attached
-- (scenes)" in a Platinum log, where the number should be zero and the line
-- should say gen4.  What the player got was Sinnoh running Johto's
-- interpretation of its own bytes on every map entry and every step.
local FOREIGN_POOLS = {
  RomExtractorGen3 = true,
  RomExtractorGen4 = true,
}

local function store(data)
  local pool = data and data.map_scripts
  if pool and FOREIGN_POOLS[pool.source] then return nil end
  return pool or nil
end

-- exported so data/scripts/init.lua can ask which VM owns the loaded cache
-- without duplicating the provenance test
Gen2ScriptVM.store = store

-- POLISHED CRYSTAL'S ALIASES FOR COMMANDS THIS VM ALREADY MODELS.
--
-- Every one of these is the same operation under another name -- a key item
-- is an item, `nooryes` is `yesorno` with the cursor starting on NO, and
-- `random16` is `random` over a wider range. They are listed rather than
-- guessed at: an alias whose semantics differ from the handler it points at
-- would be silently wrong, which is worse than being absent, so anything with
-- a real behavioural difference (givetmhm, changemapblocks, trainerflagaction)
-- is deliberately left out of this list and stays in the audit.
L.nooryes = L.yesorno
L.random16 = L.random
L.checkkeyitem = L.checkitem
L.givekeyitem = L.giveitem
L.takekeyitem = L.takeitem
L.verbosegivekeyitem = L.verbosegiveitem
L.givespecialitem = L.giveitem
L.applyonemovement = L.applymovement
-- `loadtrainerwithpal <group>, <id>, <palette>` is `loadtrainer` plus the
-- palette the trainer's pic is drawn in -- Script_loadtrainerwithpal falls
-- into the same battle setup, and the port picks a pic's palette from the
-- pic.  The two ids are in the same two operands, so the alias is exact and
-- only the presentation operand is dropped.
L.loadtrainerwithpal = L.loadtrainer

-- checkunits, trainerpic and paintingpic stay in the audit for the same
-- reason checksave does (see the note beside L.wait): each is a question or a
-- picture whose exact answer has not been read off the cartridge, and an
-- invented one would branch a script on a guess.
--
-- `checkegg` WALKS THE PARTY (Script_checkegg has a .loop and a .next), so it
-- is not Crystal's CheckFirstMonIsEgg special under another name -- that one
-- looks at the lead slot only.  Day-care and hatching scripts gate on this,
-- and with no lowering they read whatever the last command left.
L.checkegg = function(_, s) emit(s, { "g2_check_party_egg" }) end

-- Lower `entry` and every script reachable from it into one row list.
-- Coverage hook: an unrecognised opcode lowers to nothing, so the only way to
-- notice a gap is to ask the table directly.
function Gen2ScriptVM.lowered(op)
  return L[op] ~= nil
end

function Gen2ScriptVM.compile(data, entry)
  local pool = store(data)
  local scripts = pool and pool.scripts
  if not (scripts and type(entry) == "string" and scripts[entry]) then return nil end

  local key = entry
  compiled[scripts] = compiled[scripts] or {}
  local hit = compiled[scripts][key]
  if hit ~= nil then return hit or nil end

  local out, queued, order = {}, { [entry] = true }, { entry }
  local counter = 0
  local state = {
    out = out,
    stds = pool.stds,
    has = function(label)
      return type(label) == "string" and scripts[label] ~= nil
    end,
    want = function(label)
      if type(label) == "string" and scripts[label] and not queued[label] then
        queued[label] = true
        order[#order + 1] = label
      end
    end,
    newLabel = function()
      counter = counter + 1
      return string.format("%s_r%d", entry, counter)
    end,
  }

  local index = 1
  while index <= #order do
    local label = order[index]
    index = index + 1
    emit(state, { "label", label })
    state.lastText = nil
    state.lastTextRow = nil
    -- Prism's structured conditionals (macros/event.asm `sif` / `sendif`).
    -- These are not jumps in the stream -- there is no pointer to lower --
    -- so the branch has to be BUILT here, from the shape:
    --
    --     sif true, then     ->  jump_if_false <after sendif>
    --       <commands>
    --     sendif             ->  label <after sendif>
    --
    --     sif true           ->  jump_if_false <after the next command>
    --       <one command>    ->  label <after the next command>
    --
    -- The `then` marker is opcode $CF, which Prism aliases onto
    -- scriptstartasm (`then_command EQU scriptstartasm_command`).  Without
    -- this the guarded commands lowered UNCONDITIONALLY: IntroOutside's
    -- `.init_events` is `checkevent / sif true / return / jumpstd
    -- initializeevents`, so an unconditional `return` meant the game's events
    -- were never initialised at all -- which is most of "the events are not
    -- set up".
    local sifStack, guardLabel = {}, nil
    local rows = scripts[label] or {}
    for irIndex, ir in ipairs(rows) do
      local op = ir[1]
      if SIF_OPS[op] then
        local after = state.newLabel()
        local cmp = SIF_COMPARE[op]
        if cmp then
          -- the comparing forms test the script variable against their own
          -- operand byte, exactly as ifequal / ifless / ifgreater do
          emit(state, { "g2_compare", cmp, ir[2] })
          emit(state, { "jump_if_false", after })
        elseif op == "siffalse" then
          -- runs its body when the variable is ZERO, so skip it when it is not
          emit(state, { "jump_if_true", after })
        else
          emit(state, { "jump_if_false", after })
        end
        if rows[irIndex + 1] and rows[irIndex + 1][1] == THEN_OP then
          sifStack[#sifStack + 1] = after      -- block form, closed by sendif
        else
          guardLabel = after                   -- guards exactly the next row
        end
      elseif op == THEN_OP then
        -- the marker itself emits nothing
      elseif op == "sendif" then
        local after = table.remove(sifStack)
        if after then emit(state, { "label", after }) end
      elseif op == "switch" then
        -- Script_switch is literally `call Script_writebyte` falling through
        -- into Script_selse ("writebyte + selse combined into one ... abusing
        -- how selse and sendif work").  So it sets the script variable and
        -- then closes the arm it is in, which is how Prism writes a jump
        -- table's cases -- 410 instructions, the single largest unlowered
        -- command left.
        local setval = L.setval
        if setval then setval(ir, state) end
        local after = sifStack[#sifStack]
        if after then
          local done = state.newLabel()
          emit(state, { "jump", done })
          emit(state, { "label", after })
          sifStack[#sifStack] = done
        end
      elseif op == "selse" then
        -- `selse` closes the true arm and opens the false one; without a
        -- second label the false arm would fall into the true arm's code
        local after = sifStack[#sifStack]
        if after then
          local done = state.newLabel()
          emit(state, { "jump", done })
          emit(state, { "label", after })
          sifStack[#sifStack] = done
        end
      else
        local lower = L[op]
        if lower then lower(ir, state) end
        if guardLabel then
          emit(state, { "label", guardLabel })
          guardLabel = nil
        end
      end
    end
    -- an unbalanced `sif` (the decoder stopped inside the block) still has to
    -- close, or the jump target does not exist and the runner falls through
    for i = #sifStack, 1, -1 do emit(state, { "label", sifStack[i] }) end
    if guardLabel then emit(state, { "label", guardLabel }) end
    -- a script that ran off the end of its own bytecode still has to unwind
    emit(state, { "g2_return" })
  end

  -- A script that lowers to nothing is why an NPC can be walked up to,
  -- talked to, and say absolutely nothing: ScriptRunner gets nil and there is
  -- no dialogue to show.  It means every opcode in the script was unhandled,
  -- or the pool entry was empty to begin with.  Name it.
  if #out == 0 then
    Logger.warn("gen2 script vm: '%s' compiled to zero rows (silent NPC)", key)
  end
  compiled[scripts][key] = #out > 0 and out or false
  return #out > 0 and out or nil
end

-- Prism renamed a good deal of Crystal's script vocabulary without changing
-- what the commands DO -- `jump` for `sjump`, `if_equal` for `ifequal`,
-- `end_all` for `endall`.  An unlowered command is not an error, it just
-- lowers to nothing, so the whole class was silent: 1479 instructions, and
-- `jump` alone was 676 of them.  A script whose jumps vanish runs its first
-- straight-line stretch and then stops, which is most of what "the events do
-- not fire" looks like from the outside.
--
-- Deliberately NOT here: siftrue / siffalse.  They share a name-shape with
-- Crystal's iftrue / iffalse but take no pointer -- they are the structured
-- conditionals, and the lowering loop above builds their branches itself.
-- Aliasing them onto the pointer forms would read an operand that is not
-- there.
local PRISM_ALIASES = {
  jump = "sjump",
  farjump = "farsjump",
  -- priorityjump is `sjump` plus "run me before the map's own scripts", and
  -- the port has no priority queue -- the scene it names IS the next thing to
  -- run.  Prism's opening cutscene is a scene script whose entire body is
  -- `priorityjump .play_music`, so with no lowering the intro did nothing at
  -- all: no music, nobody turning to face the player, no dialogue.
  priorityjump = "sjump",
  ptpriorityjump = "sjump",
  if_equal = "ifequal",
  if_not_equal = "ifnotequal",
  if_greater_than = "ifgreater",
  if_less_than = "ifless",
  check_just_battled = "checkjustbattled",
  end_all = "endall",
  end_if_just_battled = "endifjustbattled",
  -- Prism renamed the scene machinery too.  A "trigger" is Crystal's
  -- "scene": dotrigger sets the current map's, domaptrigger sets another
  -- map's, and the check* pair read them back.  These are what decide WHICH
  -- cutscene a map is in, so with them silent a map could not advance past
  -- its opening scene at all.
  dotrigger = "setscene",
  checktriggers = "checkscene",
  domaptrigger = "setmapscene",
  checkmaptriggers = "checkmapscene",
  -- and `spriteface <person>, <facing>` is `turnobject` under another name --
  -- the command the intro uses to have the player and mom look at each other.
  spriteface = "turnobject",
  spritefacelasttalked = "turnobject",
  -- `faceperson p1, p2` makes p1 look at p2 -- Crystal's faceobject.
  faceperson = "faceobject",
  -- Prism's writebyte IS Crystal's setval: `call GetScriptByte / ldh
  -- [hScriptVar], a`.  It is what every one of its `switch` blocks tests, so
  -- with it silent the whole dispatch fell to the default arm.
  writebyte = "setval",
  -- text: showtext is writetext with a pointer, endtext ends the box, and
  -- closetextend is closetext + end -- and this port's show_text owns its own
  -- box (opentext/closetext are already no-ops here), so it is just `end`.
  showtext = "writetext",
  endtext = "end",
  closetextend = "end",
  -- audio
  playwaitsfx = "playsound",
  fadetomapmusic = "playmapmusic",
  -- Same handler, same operand widths, different name.  Prism's table sits
  -- one slot below Crystal's from $3F on, which is why these read as new
  -- commands; checked spec-by-spec against Crystal's before aliasing.
  moveperson = "moveobject",
  writepersonxy = "writeobjectxy",
  applymovement2 = "applymovementlasttalked",
  reloadmappart = "refreshmap",
  itemtotext = "getitemname",
  pokenamemem = "getmonname",
  mapnametotext = "getcurlandmarkname",
  name = "gettrainername",
}
for prismName, existing in pairs(PRISM_ALIASES) do
  if L[prismName] == nil and L[existing] then L[prismName] = L[existing] end
end

-- ---------------------------------------------------------------------------
-- registration
-- ---------------------------------------------------------------------------

-- The script a trainer object runs once the battle is won.  The ROM re-enters
-- the object's own script there, which is how the Slowpoke Well Rockets clear
-- out and Kurt walks in; without it the map's story simply never advances.
function Gen2ScriptVM.afterBattleRows(data, mapId, objIndex)
  local pool = store(data)
  local entry = pool and pool.maps and pool.maps[mapId]
  local label = entry and entry.objectAfter and entry.objectAfter[objIndex]
  if not label then return nil end
  local ok, rows = pcall(Gen2ScriptVM.compile, data, label)
  return ok and rows or nil
end

-- onEnter can fire mid-warp while the warping script's runner is still alive,
-- so scenes and callbacks go through the overworld's pending-script FIFO.
local function queue(overworld, rows, extra)
  if not (rows and overworld) then return false end
  overworld:queueScript(rows, extra)
  return true
end

-- Build the MapScripts contribution for one map: object talk scripts keyed by
-- the same TEXT constant the overworld dispatches on, plus onEnter for the
-- map's scene/callback entries and onStep for its coord events.
-- mapId -> the map's compiled scene scripts, indexed scene + 1.  Held on the
-- module so the deferred `g2_run_map_scene` row can find them after the map's
-- callbacks have had their turn (see the note in contributionFor).
Gen2ScriptVM.mapScenes = Gen2ScriptVM.mapScenes or {}

-- Queue the scene script wMapScenes names for `mapId` RIGHT NOW -- i.e. after
-- the callbacks that may have just rewritten it.  Returns true when one was
-- queued.
function Gen2ScriptVM.runMapScene(game, overworld, mapId)
  local scenes = Gen2ScriptVM.mapScenes[mapId]
  if not (scenes and game and overworld) then return false end
  local Gen2Commands = require("src.script.Gen2Commands")
  local scene = Gen2Commands.getScene(game.save, mapId)
  local rows = scenes[(tonumber(scene) or 0) + 1]
  if not rows then return false end
  return queue(overworld, rows, { mapId = mapId })
end

local function contributionFor(data, mapId, entry, mapDef)
  local contribution = {}

  local talk = {}
  for objIndex, label in pairs(entry.objects or {}) do
    local obj = mapDef and mapDef.objects and mapDef.objects[objIndex]
    local textConst = obj and obj.text
    if textConst then
      local rows = Gen2ScriptVM.compile(data, label)
      if rows then talk[textConst] = rows end
    end
  end
  -- bg_events dispatch through the same TEXT constant the sign carries, so a
  -- signpost that runs a real script (the Ruins of Alph wall patterns, the
  -- research-center machines) overrides its own flattened text.
  for bgIndex, label in pairs(entry.signs or {}) do
    local sign = mapDef and mapDef.signs and mapDef.signs[bgIndex]
    local textConst = sign and sign.text
    if textConst then
      local rows = Gen2ScriptVM.compile(data, label)
      local cond = entry.signConds and entry.signConds[bgIndex]
      if rows and cond then
        -- BGEVENT_IFSET / IFNOTSET: the sign is inert until its event flips,
        -- so gate the body rather than always running it.
        local gate = {
          { "check_flag", eventFlag(cond.event) },
          { cond.ifSet and "jump_if_false" or "jump_if_true", "end" },
        }
        for _, row in ipairs(rows) do gate[#gate + 1] = row end
        rows = gate
      end
      if rows then talk[textConst] = rows end
    end
  end
  if next(talk) then contribution.talk = talk end

  -- The ROM runs exactly one scene -- the one wMapScenes names for this map.
  -- Running all of them would fire every cutscene state the map has ever had
  -- the moment the player walks in.
  --
  -- Callbacks come FIRST.  In the engine they are not "the rest of the map
  -- script": RunMapCallback fires them from LoadMapAttributes while the map is
  -- still being set up, and the scene script only starts once the map is live
  -- (via the scene's own priorityjump).  So a callback that stages the cast is
  -- guaranteed to have run before the scene that walks the player up to it.
  --
  -- Crystal's ElmsLab is the case that proves it, and it is a Crystal-only
  -- shape -- Gold's ElmsLab_MapScripts declares ZERO callbacks:
  --
  --   ElmsLabMoveElmCallback:  checkscene / iftrue .Skip
  --                            moveobject ELMSLAB_ELM, 3, 4 / endcallback
  --
  -- ELM's object_event sits at (5,2), which is where he ends up AFTER the
  -- meeting (ElmsLab_ElmToDefaultPositionMovement1/2 walk him up-right-right-up
  -- from 3,4 to exactly 5,2).  The callback is what puts him at (3,4) for the
  -- meeting itself, and Crystal's ElmsLab_WalkUpToElmMovement is built for that
  -- spot: 7 steps up then turn_head_LEFT, where Gold's is 9 steps up then
  -- turn_head_RIGHT.  Queueing the scene first left ELM parked at (5,2): the
  -- player walked up and faced an empty tile, then ELM's "walk back to my
  -- desk" movements ran from the wrong origin and carried him off the walkable
  -- area.
  local scenes, callbacks = {}, {}
  for i, label in ipairs(entry.scenes or {}) do
    scenes[i] = Gen2ScriptVM.compile(data, label) or false
  end
  for _, callback in ipairs(entry.callbacks or {}) do
    local rows = Gen2ScriptVM.compile(data, callback.script)
    if rows then callbacks[#callbacks + 1] = rows end
  end
  -- Always install onEnter for Gen2 maps so temporary event bits clear on
  -- reload.  Kurt sets EVENT_TEMPORARY_UNTIL_MAP_RELOAD_2 after delivering a
  -- ball; without a clear, every later talk only prints "That turned out
  -- great!" and never accepts another apricorn.
  do
    -- THE SCENE IS LOOKED UP AFTER THE CALLBACKS HAVE RUN, not while they are
    -- still sitting in the queue.  A MAPCALLBACK_NEWMAP is very often a
    -- `setscene` and nothing else -- Route36NationalParkGate's is exactly
    --
    --     checkflag ENGINE_BUG_CONTEST_TIMER
    --     iftrue .BugContestIsRunning        -> setscene LEAVE_CONTEST_EARLY
    --     setscene SCENE_ROUTE36NATIONALPARKGATE_NOOP
    --
    -- and RunSceneScript reads wMapScenes only after LoadMapAttributes has
    -- fired those callbacks.  Resolving `scenes[scene + 1]` here instead read
    -- the value the callback was ABOUT to overwrite, so every such map ran one
    -- map-load behind: the Bug Contest officer asked "do you want to finish?"
    -- on the load AFTER the contest ended, handed over another prize, and did
    -- it again every time the player walked back in.
    --
    -- The callbacks are queued, and the pending-script FIFO runs one entry per
    -- frame, so the lookup has to be queued too -- as a row that performs it
    -- when its turn comes.
    Gen2ScriptVM.mapScenes[mapId] = scenes
    contribution.onEnter = function(game, overworld)
      local flags = game.save.flags
      if flags then
        for i = 0, 7 do
          flags[eventFlag(i)] = nil
        end
      end
      for _, cb in ipairs(callbacks) do
        -- `mapCallback` marks the one kind of script the cartridge runs while
        -- the map is still being built, which is the only kind allowed to move
        -- a live object with a bare setevent/clearevent -- see the note by
        -- syncFlagObjects in Commands.
        queue(overworld, cb, { mapId = mapId, mapCallback = true })
      end
      if #scenes > 0 then
        queue(overworld, { { "g2_run_map_scene", mapId } }, { mapId = mapId })
      end
    end
  end

  local coords = {}
  for _, coord in ipairs(entry.coords or {}) do
    local rows = Gen2ScriptVM.compile(data, coord.script)
    if rows then
      coords[#coords + 1] = { x = coord.x, y = coord.y, scene = coord.scene, rows = rows }
    end
  end
  if #coords > 0 then
    local Gen2Commands = require("src.script.Gen2Commands")
    contribution.onStep = function(game, overworld, x, y)
      if overworld.runner:isRunning() then return false end
      local scene = Gen2Commands.getScene(game.save, mapId)
      for _, coord in ipairs(coords) do
        -- $FF is the ROM's "any scene" wildcard
        if coord.x == x and coord.y == y
          and (coord.scene == scene or coord.scene == 0xFF) then
          overworld.runner:run(coord.rows, { mapId = mapId })
          return true
        end
      end
      return false
    end
  end

  return next(contribution) and contribution or nil
end

-- Attached in two phases (see data/scripts/init.lua).  "talk" runs before the
-- hand-ported modules so those still override individual TEXT constants;
-- "scenes" runs after them, because attachBase lets the last registration
-- replace onEnter/onStep wholesale and the ROM's scene and coord-event tables
-- are exactly what the hand-ports were standing in for.
local PHASE_KEYS = {
  talk = { talk = true },
  scenes = { onEnter = true, onStep = true },
}

function Gen2ScriptVM.register(data, phase)
  local keep = PHASE_KEYS[phase]
  local pool = store(data)
  if not (pool and pool.maps) then return 0 end
  local attached = 0
  for mapId, entry in pairs(pool.maps) do
    local mapDef = data.maps and data.maps[mapId]
    local ok, contribution = pcall(contributionFor, data, mapId, entry, mapDef)
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
      Logger.warn("gen2 script vm: %s failed to compile (%s)", mapId, tostring(contribution))
    end
  end
  Logger.info("gen2 script vm: %d maps attached (%s)", attached, tostring(phase or "all"))
  return attached
end

return Gen2ScriptVM
