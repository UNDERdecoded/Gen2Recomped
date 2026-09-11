-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen3 (Emerald) event-script bytecode table.
--
-- gScriptCmdTable lives at flat 0x1DB67C and holds 228 handlers, $00-$E3;
-- $E3 repeats the $00 (ScrCmd_nop) handler as table padding, so the live
-- opcode range is $00-$E2.  Seven further slots share the ScrCmd_nop1
-- handler -- $C7-$CC and $D0 -- which are the FireRed-only commands Emerald
-- keeps in the table but does not implement.  They still carry operands, so
-- their widths below are real even though the handler throws them away.
--
-- Where the operand widths come from.  A retail cartridge ships no macro
-- file, so each ScrCmd_* handler was disassembled and its
-- `bl ScriptReadHalfword` (0x098E0C) and `bl ScriptReadWord` (0x098E24)
-- calls counted; that pins every two- and four-byte operand exactly, and it
-- agrees with the specs below for all 228 slots.  ScriptReadByte is inlined
-- by the compiler and leaves no call to count, so byte operands come from
-- the macro definitions instead -- and were then validated the only way that
-- really counts: disassembling every script reachable from all 518 map
-- headers (object events, both bg-event script kinds, coord events and both
-- kinds of map script), which walks 2796 roots into 6897 scripts and 50775
-- commands with ZERO desyncs.  One wrong width anywhere shows up as a run of
-- garbage opcodes within a few dozen bytes, so that number is the proof.
--
-- $D1-$E2 deserve a note.  Those handlers are not laid out in table order in
-- scrcmd.c, so their names could not simply be read off a source listing;
-- they were identified by what each handler calls.  $D1 and $D7 have the
-- exact call shape of $39 `warp` (two halfword reads, then the same
-- SetWarpDestination/DoWarp pair), and warpmossdeepgym and warpwhitefade are
-- the only two warp commands left unaccounted for, so those two are they.
-- $D3-$D6 call into the rotating-tile-puzzle module at 0x1A89xx and appear
-- exactly nine times each across the corpus -- one init, move, turn and free
-- per rotating-tile puzzle: five in the Mossdeep Gym and four in the Trick
-- House.  WHICH of the four each slot is was read off the handlers, and the
-- guess that stood here before was wrong in a way that hid itself.  $D3 is
-- moverotatingtileobjects and takes a HALFWORD, not initrotatingtilepuzzle
-- taking a byte -- and calling it a byte left the operand's high 00 behind
-- to decode as a $00 nop.  Three bytes either way, so the corpus never
-- desynced; it just named two commands after each other, swapped the other
-- two, and printed a nop that is not in the cartridge.  The handlers say it
-- plainly: gScriptCmdTable[$D3] reads a halfword, VarGets it and calls
-- 01A89A0 (MoveRotatingTileObjects); [$D4] takes nothing and calls 01A8AF8
-- (TurnRotatingTileObjects); [$D5] reads a halfword and calls 01A8934
-- (InitRotatingTilePuzzle); [$D6] takes nothing and calls 01A895C.  $DA sits
-- immediately after ScrCmd_braillemessage in the binary and takes no operand,
-- which is closebraillemessage.
--
-- Spec letters:
--   b  one byte    w  two byte little-endian value    d  four byte value
--                                                        (usually a pointer)
--   *  variable length; see TRAINER_BATTLE_LENGTH

local Gen3ScriptOps = {}

Gen3ScriptOps.COMMANDS = {
  { "nop", "" }, { "nop1", "" }, { "end", "" }, { "return", "" }, { "call", "d" },
  { "goto", "d" }, { "goto_if", "bd" }, { "call_if", "bd" }, { "gotostd", "b" },
  { "callstd", "b" }, { "gotostd_if", "bb" }, { "callstd_if", "bb" }, { "returnram", "" },
  { "killscript", "" }, { "setmysteryeventstatus", "b" }, { "loadword", "bd" },
  { "loadbyte", "bb" }, { "writebytetoaddr", "bd" }, { "loadbytefromaddr", "bd" },
  { "setptrbyte", "bd" }, { "copylocal", "bb" }, { "copybyte", "dd" },
  { "setvar", "ww" }, { "addvar", "ww" }, { "subvar", "ww" }, { "copyvar", "ww" },
  { "setorcopyvar", "ww" }, { "compare_local_to_local", "bb" }, { "compare_local_to_value", "bb" },
  { "compare_local_to_addr", "bd" }, { "compare_addr_to_local", "db" },
  { "compare_addr_to_value", "db" }, { "compare_addr_to_addr", "dd" },
  { "compare_var_to_value", "ww" }, { "compare_var_to_var", "ww" }, { "callnative", "d" },
  { "gotonative", "d" }, { "special", "w" }, { "specialvar", "ww" }, { "waitstate", "" },
  { "delay", "w" }, { "setflag", "w" }, { "clearflag", "w" }, { "checkflag", "w" },
  { "initclock", "ww" }, { "dotimebasedevents", "" }, { "gettime", "" },
  { "playse", "w" }, { "waitse", "" }, { "playfanfare", "w" }, { "waitfanfare", "" },
  { "playbgm", "wb" }, { "savebgm", "w" }, { "fadedefaultbgm", "" }, { "fadenewbgm", "w" },
  { "fadeoutbgm", "b" }, { "fadeinbgm", "b" }, { "warp", "bbbww" }, { "warpsilent", "bbbww" },
  { "warpdoor", "bbbww" }, { "warphole", "bb" }, { "warpteleport", "bbbww" },
  { "setwarp", "bbbww" }, { "setdynamicwarp", "bbbww" }, { "setdivewarp", "bbbww" },
  { "setholewarp", "bbbww" }, { "getplayerxy", "ww" }, { "getpartysize", "" },
  { "additem", "ww" }, { "removeitem", "ww" }, { "checkitemspace", "ww" },
  { "checkitem", "ww" }, { "checkitemtype", "w" }, { "addpcitem", "ww" },
  { "checkpcitem", "ww" }, { "adddecoration", "w" }, { "removedecoration", "w" },
  { "checkdecor", "w" }, { "checkdecorspace", "w" }, { "applymovement", "wd" },
  { "applymovementat", "wdbb" }, { "waitmovement", "w" }, { "waitmovementat", "wbb" },
  { "removeobject", "w" }, { "removeobjectat", "wbb" }, { "addobject", "w" },
  { "addobjectat", "wbb" }, { "setobjectxy", "www" }, { "showobjectat", "wbb" },
  { "hideobjectat", "wbb" }, { "faceplayer", "" }, { "turnobject", "wb" },
  { "trainerbattle", "*" }, { "dotrainerbattle", "" }, { "gotopostbattlescript", "" },
  { "gotobeatenscript", "" }, { "checktrainerflag", "w" }, { "settrainerflag", "w" },
  { "cleartrainerflag", "w" }, { "setobjectxyperm", "www" }, { "copyobjectxytoperm", "w" },
  { "setobjectmovementtype", "wb" }, { "waitmessage", "" }, { "message", "d" },
  { "closemessage", "" }, { "lockall", "" }, { "lock", "" }, { "releaseall", "" },
  { "release", "" }, { "waitbuttonpress", "" }, { "yesnobox", "bb" }, { "multichoice", "bbbb" },
  { "multichoicedefault", "bbbbb" }, { "multichoicegrid", "bbbbb" }, { "drawbox", "" },
  { "erasebox", "bbbb" }, { "drawboxtext", "bbbb" }, { "showmonpic", "wbb" },
  { "hidemonpic", "" }, { "showcontestpainting", "b" }, { "braillemessage", "d" },
  { "givemon", "wbwddb" }, { "giveegg", "w" }, { "setmonmove", "bbw" },
  { "checkpartymove", "w" }, { "bufferspeciesname", "bw" }, { "bufferleadmonspeciesname", "b" },
  { "bufferpartymonnick", "bw" }, { "bufferitemname", "bw" }, { "bufferdecorationname", "bw" },
  { "buffermovename", "bw" }, { "buffernumberstring", "bw" }, { "bufferstdstring", "bw" },
  { "bufferstring", "bd" }, { "pokemart", "d" }, { "pokemartdecoration", "d" },
  { "pokemartdecoration2", "d" }, { "playslotmachine", "w" }, { "setberrytree", "bbb" },
  { "choosecontestmon", "" }, { "startcontest", "" }, { "showcontestresults", "" },
  { "contestlinktransfer", "" }, { "random", "w" }, { "addmoney", "db" },
  { "removemoney", "db" }, { "checkmoney", "db" }, { "showmoneybox", "bbb" },
  { "hidemoneybox", "" }, { "updatemoneybox", "" }, { "getpokenewsactive", "w" },
  { "fadescreen", "b" }, { "fadescreenspeed", "bb" }, { "setflashlevel", "w" },
  { "animateflash", "b" }, { "messageautoscroll", "d" }, { "dofieldeffect", "w" },
  { "setfieldeffectargument", "bw" }, { "waitfieldeffect", "w" }, { "setrespawn", "w" },
  { "checkplayergender", "" }, { "playmoncry", "ww" }, { "setmetatile", "wwww" },
  { "resetweather", "" }, { "setweather", "w" }, { "doweather", "" }, { "setstepcallback", "b" },
  { "setmaplayoutindex", "w" }, { "setobjectsubpriority", "wbbb" }, { "resetobjectsubpriority", "wbb" },
  { "createvobject", "bbwwbb" }, { "turnvobject", "bb" }, { "opendoor", "ww" },
  { "closedoor", "ww" }, { "waitdooranim", "" }, { "setdooropen", "ww" },
  { "setdoorclosed", "ww" }, { "addelevmenuitem", "bwww" }, { "showelevmenu", "" },
  { "checkcoins", "w" }, { "addcoins", "w" }, { "removecoins", "w" }, { "setwildbattle", "wbw" },
  { "dowildbattle", "" }, { "setvaddress", "d" }, { "vgoto", "d" }, { "vcall", "d" },
  { "vgoto_if", "bd" }, { "vcall_if", "bd" }, { "vmessage", "d" }, { "vbuffermessage", "d" },
  { "vbufferstring", "bd" }, { "showcoinsbox", "bb" }, { "hidecoinsbox", "bb" },
  { "updatecoinsbox", "bb" }, { "incrementgamestat", "b" }, { "setescapewarp", "bbbww" },
  { "waitmoncry", "" }, { "bufferboxname", "bw" }, { "textcolor", "b" },
  { "loadhelp", "d" }, { "unloadhelp", "" }, { "signmsg", "" }, { "normalmsg", "" },
  { "comparehiddenvar", "bd" }, { "setmonobedient", "w" }, { "checkmonobedience", "w" },
  { "execram", "" }, { "setmonmetlocation", "wb" }, { "warpmossdeepgym", "bbbww" },
  { "buffertrainerclassname", "bw" }, { "moverotatingtileobjects", "w" },
  { "turnrotatingtileobjects", "" }, { "initrotatingtilepuzzle", "w" },
  { "freerotatingtilepuzzle", "" }, { "warpwhitefade", "bbbww" }, { "selectapproachingtrainer", "" },
  { "lockfortrainer", "" }, { "closebraillemessage", "" }, { "messageinstant", "d" },
  { "fadescreenswapbuffers", "b" }, { "buffertrainername", "bw" }, { "buffercontesttypestring", "bw" },
  { "pokenavcall", "d" }, { "bufferitemnameplural", "bww" }, { "setmodernfatefulencounter", "w" },
  { "checkmodernfatefulencounter", "ww" }, { "nop_e3", "" },
}

-- trainerbattle ($5C) is the one variable-length command: the byte after the
-- opcode picks which parameter block follows.  The lengths below include that
-- selector byte.  Types 0/5 are the plain single battle, 3 drops the intro
-- text, 1/2/4/7 add a third text or script pointer, 6/8 add a fourth, and 9
-- is the Battle Pyramid form, shaped like type 0.
-- ---------------------------------------------------------------------------
-- HOW LONG A `trainerbattle` IS, and every one of these was a byte short.
--
-- The record is six bytes of header -- the opcode, the battle type, the
-- trainer as a halfword and a music override as another -- and then a number
-- of four-byte pointers that depends on the type: the intro line, the defeat
-- line, and for the types that have one, the script to run after you win.
--
-- Reading it one byte short does not fail; it RESUMES ONE BYTE EARLY, and
-- from there every byte of the rest of the script is read as something it is
-- not.  ROXANNE's script is the whole story: eighteen bytes of trainerbattle
-- read as seventeen, so the walk restarted on the record's last byte and the
-- next two bytes decoded as `gotostd 38` -- a standard script that does not
-- exist.  Her real continuation, the one that hands over the STONE BADGE,
-- was never reached.  That is why the region's scripts CHECK the eight badge
-- flags forty times and SET them not once.
--
-- DERIVED, not corrected by inspection: every script root is walked to its
-- FIRST trainerbattle -- which is decoded with lengths that are not yet in
-- doubt, because the corruption only starts after one -- and the four-byte
-- ROM pointers trailing the header are counted there.  565 trustworthy sites,
-- and every type is unanimous: 366 of 368 type-0 records carry two pointers,
-- all 89 type-2 carry three, all 55 type-3 carry one, all 22 type-6 carry
-- four.  Type 5 never appears first in a script, so it takes the same
-- correction as the other nine.
-- ---------------------------------------------------------------------------
Gen3ScriptOps.TRAINER_BATTLE_HEADER = 6
Gen3ScriptOps.TRAINER_BATTLE_LENGTH = {
  [0] = 14, [1] = 18, [2] = 18, [3] = 10, [4] = 18,
  [5] = 14, [6] = 22, [7] = 18, [8] = 22, [9] = 14,
}
-- how many of those trailing words are pointers
Gen3ScriptOps.TRAINER_BATTLE_POINTERS = {
  [0] = 2, [1] = 3, [2] = 3, [3] = 1, [4] = 3,
  [5] = 2, [6] = 4, [7] = 3, [8] = 4, [9] = 2,
}

-- ...AND WHICH OF THEM IS THE SCRIPT.
--
-- Not the last one, and not guessed: every slot of every trainerbattle the
-- decoder reaches was followed and asked two questions -- does it decode as a
-- script that terminates, and does it decode as text.  The answers do not
-- overlap anywhere.  Type 1 slot 3 is a script at 6 sites out of 6, type 2
-- slot 3 at 89 out of 89, type 6 slot 4 at 22 out of 22, type 8 slot 4 at its
-- single site; every other slot of every other type decodes as a script at
-- ZERO sites and as text at most of them.
--
-- So 117 of the region's 565 trainer battles hand over to a script when you
-- win, and the rest simply say their line.  The eight gym leaders are in the
-- 117: that script is where the badge is.
Gen3ScriptOps.TRAINER_BATTLE_SCRIPT_SLOT = {
  [1] = 3, [2] = 3, [6] = 4, [8] = 4,
}

-- Commands after which control never returns to the next byte.
Gen3ScriptOps.TERMINATORS = {
  [0x02] = true,  -- end
  [0x03] = true,  -- return
  [0x05] = true,  -- goto
  [0x08] = true,  -- gotostd
  [0x0C] = true,  -- returnram
  [0x0D] = true,  -- killscript
  [0x24] = true,  -- gotonative
  [0x5E] = true,  -- gotopostbattlescript
  [0x5F] = true,  -- gotobeatenscript
  [0xB9] = true,  -- vgoto
  [0xCF] = true,  -- execram
}

-- A warp does not end a script, it YIELDS: the handler returns "stop for this
-- frame", the following `waitstate` blocks, and then the map change tears the
-- script context down.  Scripts written `warp / waitstate` with no `end` are
-- common, and walking past that waitstate reads whatever follows -- usually
-- movement data -- as bytecode.  Four scripts in one Lilycove building and the
-- two Mossdeep Gym warps depend on this rule.
Gen3ScriptOps.WARP_YIELD = {
  [0x39] = true,  -- warp
  [0x3A] = true,  -- warpsilent
  [0x3B] = true,  -- warpdoor
  [0x3C] = true,  -- warphole
  [0x3D] = true,  -- warpteleport
  [0xD1] = true,  -- warpmossdeepgym
  [0xD7] = true,  -- warpwhitefade
}

-- Map-script table types.  `mapScripts` is a flat list of `u8 type, u32 ptr`
-- entries closed by a zero type -- ALWAYS five bytes per entry, including the
-- two types below.  For those two the pointer is not a script but a table of
-- `u16 var, u16 value, u32 script` rows closed by a zero var.  Reading them as
-- nine-byte inline entries instead walks off the end of the list and into the
-- next map's data.
Gen3ScriptOps.MAP_SCRIPT_TABLE_TYPES = { [2] = true, [4] = true }
-- ...and the two of them by name, because a bare 2 in another file is a
-- number nobody can check
Gen3ScriptOps.ON_FRAME_TABLE = 2
Gen3ScriptOps.ON_WARP_INTO_MAP_TABLE = 4

Gen3ScriptOps.OPCODE_COUNT = 228

function Gen3ScriptOps.commandsFor(_version)
  return Gen3ScriptOps.COMMANDS
end

-- ---------------------------------------------------------------------------
-- Movement scripts: the second bytecode language
--
-- `applymovement` points at a flat array of one-byte movement action ids
-- closed by $FE.  All 896 movement scripts the map scripts reach terminate
-- properly and use ids $00-$96, well inside the 158-entry
-- gMovementActionFuncs table found at flat 0x50DC50 -- whose length is fixed
-- by the fact that action 0's step-function array starts on the byte just
-- past the table's last entry.
--
-- The ids below $19 are named; those names come from the pret reference
-- decomposition, NOT from anything the cartridge says, and the first four are
-- the only ones the binary corroborates on its own (actions $00-$03 each hold
-- one of the four face-direction step functions at 0x093951/61/71/81).
-- Everything from $19 up is left as its raw id rather than guessed at -- an
-- engine that animates the wrong action is worse than one that logs an id it
-- does not know yet.
-- ---------------------------------------------------------------------------

Gen3ScriptOps.MOVEMENT_STEP_END = 0xFE
Gen3ScriptOps.MOVEMENT_ACTION_COUNT = 158

Gen3ScriptOps.MOVEMENT_ACTIONS = {
  [0x00] = "face_down",
  [0x01] = "face_up",
  [0x02] = "face_left",
  [0x03] = "face_right",
  [0x04] = "walk_slow_down",
  [0x05] = "walk_slow_up",
  [0x06] = "walk_slow_left",
  [0x07] = "walk_slow_right",
  [0x08] = "walk_down",
  [0x09] = "walk_up",
  [0x0A] = "walk_left",
  [0x0B] = "walk_right",
  [0x0C] = "jump2_down",
  [0x0D] = "jump2_up",
  [0x0E] = "jump2_left",
  [0x0F] = "jump2_right",
  [0x10] = "delay_1",
  [0x11] = "delay_2",
  [0x12] = "delay_4",
  [0x13] = "delay_8",
  [0x14] = "delay_16",
  [0x15] = "walk_fast_down",
  [0x16] = "walk_fast_up",
  [0x17] = "walk_fast_left",
  [0x18] = "walk_fast_right",
  [0x19] = "in_place_slow_down",
  [0x1A] = "in_place_slow_up",
  [0x1B] = "in_place_slow_left",
  [0x1C] = "in_place_slow_right",
  [0x1D] = "in_place_down",
  [0x1E] = "in_place_up",
  [0x1F] = "in_place_left",
  [0x20] = "in_place_right",
  -- THE ONES THAT ARE NOT A DIRECTION.
  --
  -- Everything above is derivable from the cartridge, because a walk or a
  -- turn shows up in the movement type's own step functions.  These do not:
  -- they set a flag on the object or play a one-off effect, and there is
  -- nothing in the data that says which is which.  They are pokeemerald's
  -- names, and they are here because being unnamed was not free -- an action
  -- the port cannot name is DROPPED, and two of these change what is on
  -- screen rather than how it moves.
  --
  -- set_invisible is used 81 times across Hoenn, more than any other unnamed
  -- action.  Dropping it leaves an object standing where the script meant it
  -- to disappear.
  -- 0x3E/0x3F and 0x4E are TURNS, and dropping them is visible: an NPC that
  -- should turn to face you during a scene simply does not.  They were missed
  -- the first time round by an audit that matched `movement_%d+` while the
  -- fallback formats `movement_%02X` -- so every id whose hex contains a
  -- letter went uncounted, and the audit reported none left.
  [0x3E] = "face_player",
  [0x3F] = "face_away_player",
  [0x4E] = "face_original_direction",
  [0x4F] = "bow_down",
  [0x5A] = "rock_smash_break",
  [0x5B] = "cut_tree",
  [0x5E] = "affine_anim_start",
  [0x5F] = "affine_anim_clear",
  [0x40] = "lock_facing",
  [0x41] = "unlock_facing",
  [0x50] = "jump_landing_effect_on",
  [0x51] = "jump_landing_effect_off",
  [0x52] = "animation_off",
  [0x54] = "set_invisible",
  [0x55] = "set_visible",
  [0x56] = "emote_exclamation",
  [0x57] = "emote_question",
  -- 0x58 is the one action left over after everything above, and it is used
  -- exactly ONCE on the whole cartridge.  It sits immediately after the two
  -- named emotes, and Emerald's emote set is exclamation, question, heart --
  -- so this is the heart.  That is an inference from position rather than a
  -- reading, and it costs nothing to be wrong about: every emote is handled
  -- the same way, by keeping the pause and not drawing a bubble the port has
  -- not extracted.
  [0x58] = "emote_heart",
  [0x62] = "walk_down_start_affine",
  [0x63] = "walk_down_affine",
  [0x91] = "walk_slow_diagonal_up_right",
  [0x92] = "walk_slow_diagonal_down_left",
  [0x96] = "walk_left_affine",
}

function Gen3ScriptOps.movementName(id)
  return Gen3ScriptOps.MOVEMENT_ACTIONS[id] or ("movement_%02X"):format(id)
end

return Gen3ScriptOps
