-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Gen3 script VM.
--
-- Structurally a sibling of src/script/Gen2ScriptVM.lua, and deliberately so:
-- ScriptRunner and Commands.resolve are generation-agnostic, so a third
-- generation needs a lowering and a verb set, not a second script subsystem.
--
-- data/generated/map_scripts.lua holds Emerald's own bytecode, disassembled by
-- src/import/RomExtractorGen3.lua into the same pool shape Gen 2 uses: scripts
-- keyed S<offset>, applymovement data keyed M<offset>, and a per-map index of
-- objects, signs, coord events, map-script callbacks and var-gated tables.
--
-- Two things about Emerald differ from Gen 2 enough to shape this file:
--
-- CONDITIONS ARE A SEPARATE REGISTER.  Gen 2 branches on the result of the
-- command immediately before.  Emerald keeps a comparison result in
-- ctx->comparisonResult, valued 0/1/2 for less/equal/greater, and every
-- branch carries a condition byte 0-5 selecting a row of a 6x3 truth table
-- (LT, EQ, GT, LE, GE, NE).  `checkflag` sets the register to the flag's own
-- value, so `checkflag / goto_if 1` reads "if the flag is set" -- and
-- `goto_if 0` reads "if it is clear", because 0 < 1.  Collapsing all six
-- conditions to a boolean would inverte half the branches in the game.
--
-- MOST TEXT GOES THROUGH A STD.  The msgbox macro is `loadword 0, <text>`
-- followed by `callstd <n>`, and gStdScripts decides what kind of box that
-- is: 2 is an NPC line that locks and faces the player, 3 a sign, 4 a plain
-- box, 5 a yes/no that writes VAR_RESULT, 6 auto-close, 9 the fanfare box.
-- Those indices are not assumed here -- tools/gen3_discover.py decodes each
-- std script and identifies them by what they contain.  4,086 of the 50,775
-- commands in the game are a callstd, so getting this wrong would silence or
-- mis-frame most of the dialogue in Hoenn.

local Logger = require("src.core.Logger")
local MapScripts = require("src.script.MapScripts")
require("src.script.Gen3Commands")

local Gen3ScriptVM = {}

local compiled = setmetatable({}, { __mode = "k" })

-- gStdScripts indices, each identified by decoding the std script itself
-- (see tools/gen3_discover.py): the four msgbox variants are told apart by
-- which one contains a yesnobox and which lock or release.
local STD_OBTAIN_ITEM        = 0
local STD_FIND_ITEM          = 1
local STD_MSGBOX_NPC         = 2
local STD_MSGBOX_SIGN        = 3
local STD_MSGBOX_DEFAULT     = 4
local STD_MSGBOX_YESNO       = 5
local STD_MSGBOX_AUTOCLOSE   = 6

local PLAIN_MSGBOX = {
  [STD_MSGBOX_NPC] = true, [STD_MSGBOX_SIGN] = true,
  [STD_MSGBOX_DEFAULT] = true, [STD_MSGBOX_AUTOCLOSE] = true,
  [9] = true,                     -- the fanfare box; the tune is std-internal
}

-- Emerald numbers flags and vars in one space each; the port's flag registry
-- is keyed by name, so give them stable ones rather than raw integers.
local function flagName(n) return ("FLAG_G3_%04X"):format(tonumber(n) or 0) end

Gen3ScriptVM.flagName = flagName

-- ---------------------------------------------------------------------------
-- lowering table: ir row -> zero or more ScriptRunner rows
-- ---------------------------------------------------------------------------

local L = {}

local function emit(s, row) s.out[#s.out + 1] = row end

local droppedBranch = {}

local function branch(s, label)
  if type(label) ~= "string" then return nil end
  if not s.has(label) then
    if not droppedBranch[label] then
      droppedBranch[label] = true
      Logger.warn("gen3 script vm: branch to '%s' dropped (not in pool)", label)
    end
    return nil
  end
  s.want(label)
  return label
end

-- The extractor stores branch targets as raw cartridge addresses; the pool is
-- keyed by offset.  One place to convert, so a change of key format does not
-- have to be chased through forty lowering entries.
local function labelFor(value)
  if type(value) == "string" then return value end
  if type(value) ~= "number" then return nil end
  local offset = value - 0x08000000
  if offset < 0 then return nil end
  return ("S%07X"):format(offset)
end

-- control flow -------------------------------------------------------------

-- `end` really ends: ScriptContext_Stop, not a return to the caller.
L["end"] = function(_, s) emit(s, { "jump", "end" }) end
L.killscript = L["end"]
L["return"] = function(_, s) emit(s, { "g3_return" }) end

L["goto"] = function(ir, s)
  local to = branch(s, labelFor(ir[2]))
  if to then emit(s, { "jump", to }) end
end

L.call = function(ir, s)
  local to = branch(s, labelFor(ir[2]))
  if not to then return end
  local ret = s.newLabel()
  emit(s, { "g3_call", ret })
  emit(s, { "jump", to })
  emit(s, { "label", ret })
end

L.goto_if = function(ir, s)
  local to = branch(s, labelFor(ir[3]))
  if to then emit(s, { "g3_jump_if", ir[2], to }) end
end

L.call_if = function(ir, s)
  local to = branch(s, labelFor(ir[3]))
  if not to then return end
  local ret = s.newLabel()
  emit(s, { "g3_call_if", ir[2], ret, to })
  emit(s, { "label", ret })
end

L.nop = function() end

-- ------------------------------------------------------- the rest of the table
--
-- Everything here was previously ABSENT from L, which means dropped: the row
-- vanished and the script carried on with the comparison register holding
-- whatever the last unrelated check had left in it. A `checkdecorspace`
-- followed by `goto_if 1` then branched on nothing in particular.
--
-- Lowering them is not the same as implementing the features. Three groups:
--
--   * the ones the port can ANSWER (decorations it does not have, PC items,
--     obedience) get a real answer;
--   * the ones it cannot (contests, the slot machine, the rotating-tile
--     puzzles, the Pokenav, the elevator menu) are recognised, log once and
--     set the result the following branch reads, so the script takes its
--     "not now" path rather than a random one;
--   * the DEAD ones -- 33 of these 57 opcodes are never executed anywhere on
--     the cartridge -- are mapped to nop so the VM speaks the whole table
--     and the coverage figure means what it says.
local function stub(what)
  return function(_, s) emit(s, { "g3_unimplemented", what }) end
end

local function stubResult(what, result)
  return function(_, s)
    emit(s, { "g3_unimplemented_result", what, result })
  end
end

-- answered
L.checkdecor = function(ir, s) emit(s, { "g3_check_decor", ir[2] }) end
-- `checkdecorspace` names the decoration it is asking about, and dropping the
-- operand was harmless only while the answer was always yes
L.checkdecorspace = function(ir, s) emit(s, { "g3_check_decor_space", ir[2] }) end
L.checkpcitem = function(ir, s) emit(s, { "g3_check_pc_item", ir[2], ir[3] }) end
L.checkitemtype = function(ir, s) emit(s, { "g3_check_item_type", ir[2] }) end
L.getpokenewsactive = function(_, s) emit(s, { "g3_pokenews_active" }) end
L.checkmonobedience = function(_, s) emit(s, { "g3_check_obedience" }) end
L.checkmodernfatefulencounter = function(_, s) emit(s, { "g3_check_fateful" }) end
L.erasebox = function(_, s) emit(s, { "g3_erase_box" }) end

-- recorded
L.adddecoration = function(ir, s) emit(s, { "g3_add_decoration", ir[2] }) end
L.removedecoration = function(ir, s) emit(s, { "g3_remove_decoration", ir[2] }) end
L.setmonobedient = function(ir, s) emit(s, { "g3_set_obedient", ir[2] }) end
L.setmonmetlocation = function(ir, s)
  emit(s, { "g3_set_met_location", ir[2], ir[3] })
end
L.setmodernfatefulencounter = function(ir, s)
  emit(s, { "g3_set_fateful", ir[2] })
end

-- stubbed: features this port does not have. The result each one sets is the
-- answer that lets the surrounding script move on -- 0 for "did not happen".
-- CONTESTS ARE NOT STUBS ANY MORE.  `choosecontestmon` opens the party and
-- writes the slot into VAR_0x8004 -- exactly what the cartridge's own
-- command does -- `startcontest` runs the five appeal rounds, and
-- `showcontestresults` prints the standings the run left behind.  The LINK
-- transfer stays a stub: there is nobody on the other end.
L.choosecontestmon = function(_, s) emit(s, { "g3_choose_contest_mon" }) end
L.startcontest = function(_, s) emit(s, { "g3_start_contest" }) end
L.showcontestresults = function(_, s) emit(s, { "g3_contest_results" }) end
L.showcontestpainting = function(_, s) emit(s, { "g3_contest_painting" }) end
L.contestlinktransfer = stub("contestlinktransfer")
-- THE GAME CORNER IS NOT A STUB ANY MORE.  `playslotmachine` names the var
-- holding which seat the player sat down at (VAR_0x8004, set by the special
-- above it in every one of Mauville's scripts) and blocks until they get up.
L.playslotmachine = function(ir, s) emit(s, { "g3_play_slots", ir[2] }) end
-- THE ROTATING TILE PUZZLE IS NOT A STUB ANY MORE, and it was never only the
-- Trick House: the same four opcodes are the MOSSDEEP GYM floor, so a badge
-- was behind them.  `init` says which of the two arrow sets the room is
-- painted with, `move` names the button that was pressed, `turn` faces
-- everything at its new arrow and `free` drops the record.  See the header
-- over Gen3Commands.g3_rotate_move.
L.initrotatingtilepuzzle = function(ir, s) emit(s, { "g3_rotate_init", ir[2] }) end
L.freerotatingtilepuzzle = function(_, s) emit(s, { "g3_rotate_free" }) end
L.moverotatingtileobjects = function(ir, s) emit(s, { "g3_rotate_move", ir[2] }) end
L.turnrotatingtileobjects = function(_, s) emit(s, { "g3_rotate_turn" }) end
L.addelevmenuitem = stub("addelevmenuitem")
L.showelevmenu = stub("showelevmenu")
L.execram = stub("execram")

-- The VIRTUAL script family addresses a second script bank the port does not
-- page in; each is its ordinary counterpart, which is what they do once the
-- bank is the one already loaded. Never executed on this cartridge.
L.setvaddress = L.nop
L.vgoto = function(ir, s) return L["goto"](ir, s) end
L.vcall = function(ir, s) return L.call(ir, s) end
L.vgoto_if = function(ir, s) return L.goto_if(ir, s) end
L.vcall_if = function(ir, s) return L.call_if(ir, s) end
L.vbuffermessage = L.nop
L.vbufferstring = L.nop

-- Text STYLING, which this engine's one text box does not vary.
L.textcolor = L.nop
L.signmsg = L.nop
L.normalmsg = L.nop
L.loadhelp = L.nop
L.unloadhelp = L.nop
L.drawbox = L.nop
L.drawboxtext = L.nop

-- The RAM-scratch family: byte-level pokes into the script context's own
-- locals and into arbitrary addresses. Emerald's own scripts use exactly one
-- of these (compare_addr_to_addr, once) and this port has no such address
-- space, so they are recognised and inert rather than dropped.
L.returnram = L["return"] or L.nop
L.loadbyte = L.nop
L.writebytetoaddr = L.nop
L.loadbytefromaddr = L.nop
L.setptrbyte = L.nop
L.copylocal = L.nop
L.copybyte = L.nop
L.compare_local_to_local = L.nop
L.compare_local_to_value = L.nop
L.compare_local_to_addr = L.nop
L.compare_addr_to_local = L.nop
L.compare_addr_to_value = L.nop
L.compare_addr_to_addr = L.nop
L.comparehiddenvar = L.nop
L.callnative = L.nop
L.gotonative = L.nop
L.nop1 = L.nop
L.nop_e3 = L.nop
-- `waitstate` IS WHERE THE SCREEN COMES BACK.  On the cartridge the command
-- means "wait for whatever the special started", and what happens when that
-- finishes is a return to the field -- which fades in.  Nothing in the script
-- does it: of the 126 fades to black in Hoenn, 85 are closed by a waitstate
-- and only 17 by a fade of their own.  Lowered to a nop, every one of those
-- 85 would leave the overlay up for ever once the direction above was fixed.
L.waitstate = function(_, s) emit(s, { "g3_wait_state" }) end

-- text ---------------------------------------------------------------------
--
-- `loadword 0, <text>` does not print anything; it parks the pointer for a
-- following `message 0` or `callstd`.  Carrying it on the lowering state and
-- consuming it at the std is what turns the two-command idiom into one row.

L.loadword = function(ir, s)
  if ir[2] == 0 and type(ir[3]) == "string" then s.lastText = ir[3] end
end

L.message = function(ir, s)
  local key = type(ir[2]) == "string" and ir[2] or s.lastText
  if key then
    s.lastText = key
    emit(s, { "show_text", key })
  end
end
L.messageautoscroll = function(ir, s)
  local key = type(ir[3]) == "string" and ir[3] or s.lastText
  if key then emit(s, { "show_text", key }) end
end
L.messageinstant = L.message

-- A POKENAV CALL IS A MESSAGE with a phone around it, and the phone is the
-- part this port does not have yet.  Stubbed, the five story calls that
-- reach you while you walk -- WALLY about his father, SCOTT twice, ROXANNE
-- about her students -- said nothing at all, which is worse than saying it
-- in a plain box: the words are the cartridge's either way, and they are
-- already written as a transcript ("... ... Beep!  WALLY: ...").  So this
-- prints them, and the call window is a picture still owed.
L.pokenavcall = L.message
L.vmessage = L.message

-- BRAILLE IS NOT TEXT, and lowering it to `message` was the whole bug.  The
-- pointer a braillemessage carries is not in the text table -- the text scan
-- skips it, because a braille string is six-dot cells rather than charmap
-- bytes -- so every braille wall in Hoenn opened an empty box.  The cells and
-- the box they go in are read by the extractor (constants.gen3Braille); this
-- hands the address straight through so the overworld can draw them.
L.braillemessage = function(ir, s) emit(s, { "g3_braille", ir[2] }) end

-- the text box owns its own lifecycle in this engine
L.waitmessage = L.nop
L.closemessage = L.nop
L.closebraillemessage = function(_, s) emit(s, { "g3_braille_close" }) end
L.waitbuttonpress = L.nop

-- WHAT THE STD SCRIPTS ACTUALLY DO.
--
-- `callstd` is not a synonym for "print this".  Each slot is a real script
-- living in gStdScripts, and the four msgbox flavours differ in exactly the
-- part that was being thrown away here.  Decoded from the cartridge's own
-- table (Emerald gStdScripts, $01DC2A0):
--
--     std 2  MSGBOX_NPC       lock / FACEPLAYER / message / waitmessage /
--                             waitbuttonpress / release
--     std 3  MSGBOX_SIGN      lockall / message / waitmessage /
--                             waitbuttonpress / releaseall
--     std 4  MSGBOX_DEFAULT   message / waitmessage / waitbuttonpress
--     std 6  MSGBOX_AUTOCLOSE message / waitmessage / waitbuttonpress /
--                             release
--     std 1  FIND_ITEM        lock / FACEPLAYER / ...
--
-- Lowering all four to a bare `show_text` dropped the faceplayer, and
-- `msgbox ..., MSGBOX_NPC` is how nearly every ordinary person in Hoenn
-- talks -- so no NPC in the game ever turned to look at the player.  It also
-- dropped the `lock`, which is where VAR_FACING ($800C) is written, so any
-- of those scripts that then branched on which way the player is standing
-- read a stale value.
--
-- The waits are still nops: the text box owns its own lifecycle here.
local STD_PROLOGUE = {
  [STD_MSGBOX_NPC]   = { { "g3_lock" }, { "face_player" } },
  [STD_MSGBOX_SIGN]  = { { "g3_lock" } },
  [STD_FIND_ITEM]    = { { "g3_lock" }, { "face_player" } },
}
local STD_EPILOGUE = {
  [STD_MSGBOX_NPC]       = { { "g3_release" } },
  [STD_MSGBOX_SIGN]      = { { "g3_release" } },
  [STD_MSGBOX_AUTOCLOSE] = { { "g3_release" } },
  [STD_FIND_ITEM]        = { { "g3_release" } },
}

local function std(ir, s, isJump)
  local index = tonumber(ir[2])
  for _, row in ipairs(STD_PROLOGUE[index] or {}) do emit(s, row) end
  if PLAIN_MSGBOX[index] then
    if s.lastText then emit(s, { "show_text", s.lastText }) end
  elseif index == STD_MSGBOX_YESNO then
    -- `ask` leaves the answer on ctx; g3_from_yesno copies it into VAR_RESULT,
    -- which is what the compare_var_to_value that always follows will read
    emit(s, { "ask", s.lastText })
    emit(s, { "g3_from_yesno" })
  elseif index == STD_OBTAIN_ITEM or index == STD_FIND_ITEM then
    emit(s, { "g3_std_obtain_item", index })
  else
    emit(s, { "g3_std", index })
  end
  s.lastText = nil
  for _, row in ipairs(STD_EPILOGUE[index] or {}) do emit(s, row) end
  if isJump then emit(s, { "jump", "end" }) end
end

L.callstd = function(ir, s) std(ir, s, false) end
L.gotostd = function(ir, s) std(ir, s, true) end
L.callstd_if = function(ir, s)
  local after = s.newLabel()
  emit(s, { "g3_jump_unless", ir[2], after })
  std({ ir[1], ir[3] }, s, false)
  emit(s, { "label", after })
end
L.gotostd_if = function(ir, s)
  local after = s.newLabel()
  emit(s, { "g3_jump_unless", ir[2], after })
  std({ ir[1], ir[3] }, s, true)
  emit(s, { "label", after })
end

-- player and objects -------------------------------------------------------

L.lock = function(_, s) emit(s, { "g3_lock" }) end
L.lockall = L.lock
L.release = function(_, s) emit(s, { "g3_release" }) end
L.releaseall = L.release
L.lockfortrainer = L.lock
L.faceplayer = function(_, s) emit(s, { "face_player" }) end

L.applymovement = function(ir, s)
  if type(ir[3]) == "string" then emit(s, { "g3_move", ir[2], ir[3] }) end
end
-- ...AND THE "AT" FORM NAMES A MAP.
--
-- `applymovementat obj, movement, group, num` moves an object ON THAT MAP,
-- and the port was throwing the map away and moving object `obj` of whatever
-- map the player is standing on -- a different person entirely whenever the
-- two differ.  Its `waitmovementat` partner then waited on that stranger,
-- which is a script parked on a walk nobody asked for.  The map goes through
-- so the command can decline politely instead.
L.applymovementat = function(ir, s)
  if type(ir[3]) == "string" then
    emit(s, { "g3_move", ir[2], ir[3], ir[4], ir[5] })
  end
end
-- The wait is NOT implicit: applymovement starts a walk and returns, so two
-- of them in a row run together and this is what serialises them again at the
-- point the script asks. Lowering it to nop made every "walk with me" scene
-- play as the NPC's walk followed by the player's.
L.waitmovement = function(ir, s) emit(s, { "g3_wait_move", ir[2] or 0 }) end
L.waitmovementat = function(ir, s)
  emit(s, { "g3_wait_move", ir[2] or 0, ir[3], ir[4] })
end

L.removeobject = function(ir, s) emit(s, { "g3_hide_object", ir[2] }) end
L.removeobjectat = L.removeobject
L.addobject = function(ir, s) emit(s, { "g3_show_object", ir[2] }) end
L.addobjectat = L.addobject
L.hideobjectat = function(ir, s) emit(s, { "g3_hide_object", ir[2] }) end
L.showobjectat = function(ir, s) emit(s, { "g3_show_object", ir[2] }) end
L.turnobject = function(ir, s) emit(s, { "g3_turn", ir[2], ir[3] }) end
L.setobjectxy = function(ir, s) emit(s, { "g3_place", ir[2], ir[3], ir[4] }) end
L.setobjectxyperm = function(ir, s) emit(s, { "g3_place_perm", ir[2], ir[3], ir[4] }) end
L.setobjectmovementtype = function(ir, s) emit(s, { "g3_movement_type", ir[2], ir[3] }) end
L.copyobjectxytoperm = function(ir, s) emit(s, { "g3_copy_xy_to_perm", ir[2] }) end
L.setobjectsubpriority = L.nop
L.resetobjectsubpriority = L.nop
L.createvobject = function(ir, s) emit(s, { "g3_create_vobject", ir[2], ir[3], ir[4], ir[5] }) end
L.turnvobject = function(ir, s) emit(s, { "g3_turn_vobject", ir[2], ir[3] }) end
L.selectapproachingtrainer = L.nop

-- flags, vars and the comparison register ----------------------------------

L.setflag = function(ir, s) emit(s, { "set_flag", flagName(ir[2]) }) end
L.clearflag = function(ir, s) emit(s, { "clear_flag", flagName(ir[2]) }) end
L.checkflag = function(ir, s) emit(s, { "g3_check_flag", flagName(ir[2]) }) end

L.setvar = function(ir, s) emit(s, { "g3_setvar", ir[2], ir[3] }) end
L.addvar = function(ir, s) emit(s, { "g3_addvar", ir[2], ir[3] }) end
L.subvar = function(ir, s) emit(s, { "g3_addvar", ir[2], -(tonumber(ir[3]) or 0) }) end
L.copyvar = function(ir, s) emit(s, { "g3_copyvar", ir[2], ir[3] }) end
L.setorcopyvar = function(ir, s) emit(s, { "g3_setorcopyvar", ir[2], ir[3] }) end
L.compare_var_to_value = function(ir, s) emit(s, { "g3_compare_value", ir[2], ir[3] }) end
L.compare_var_to_var = function(ir, s) emit(s, { "g3_compare_var", ir[2], ir[3] }) end
L.random = function(ir, s) emit(s, { "g3_random", ir[2] }) end
L.specialvar = function(ir, s) emit(s, { "g3_special", ir[3], ir[2] }) end
L.special = function(ir, s) emit(s, { "g3_special", ir[2] }) end

-- items, money, party ------------------------------------------------------

L.additem = function(ir, s) emit(s, { "g3_give_item", ir[2], ir[3] }) end
L.removeitem = function(ir, s) emit(s, { "g3_take_item", ir[2], ir[3] }) end
L.checkitem = function(ir, s) emit(s, { "g3_check_item", ir[2], ir[3] }) end
L.checkitemspace = function(ir, s) emit(s, { "g3_check_item_space", ir[2], ir[3] }) end
L.addpcitem = L.additem
L.givemon = function(ir, s) emit(s, { "g3_give_pokemon", ir[2], ir[3], ir[4] }) end
L.giveegg = function(ir, s) emit(s, { "g3_give_egg", ir[2] }) end
L.setmonmove = L.nop
L.checkpartymove = function(ir, s) emit(s, { "g3_check_party_move", ir[2] }) end
L.getpartysize = function(_, s) emit(s, { "g3_party_size" }) end
L.addmoney = function(ir, s) emit(s, { "g3_add_money", ir[2] }) end
L.removemoney = function(ir, s) emit(s, { "g3_add_money", -(tonumber(ir[2]) or 0) }) end
L.checkmoney = function(ir, s) emit(s, { "g3_check_money", ir[2] }) end
L.showmoneybox = L.nop
L.hidemoneybox = L.nop
L.updatemoneybox = L.nop
L.checkcoins = function(ir, s) emit(s, { "g3_check_coins", ir[2] }) end
L.addcoins = function(ir, s) emit(s, { "g3_add_coins", ir[2] }) end
L.removecoins = function(ir, s) emit(s, { "g3_add_coins", -(tonumber(ir[2]) or 0) }) end
L.showcoinsbox = L.nop
L.hidecoinsbox = L.nop
L.updatecoinsbox = L.nop
L.pokemart = function(ir, s) emit(s, { "g3_mart", ir[2] }) end
-- THE TWO DECORATION COUNTERS.  Ten of them across Hoenn -- five floors of
-- the Lilycove department store, the Slateport market's stalls and the
-- Battle Frontier's -- selling ninety-three pieces between them.
--
-- Both were a nop, for a reason that has since gone away: a decoration id run
-- through the ITEM map comes out as a completely different object (decoration
-- 1 as a MASTER BALL), so there was nothing safe to hand a shop screen.
-- extractDecorations reads all 121 of gDecorations, the import now reads each
-- counter's list against that catalogue, and Gen3ShopMenu sells out of it.
--
-- The mode is carried because the cartridge carries it: $87 is
-- SetShopMenuMode(1) and $88 is SetShopMenuMode(2), and the only place the
-- two are ever told apart is one line of the clerk's dialogue.
L.pokemartdecoration = function(ir, s)
  emit(s, { "g3_decoration_mart", ir[2], 1 })
end
L.pokemartdecoration2 = function(ir, s)
  emit(s, { "g3_decoration_mart", ir[2], 2 })
end

-- battles ------------------------------------------------------------------

-- ir[2] is the battle type, ir[3] the trainer, ir[4] the script to run when
-- you win -- which is where every gym leader's badge is, and which the
-- decoder used to throw away.
L.trainerbattle = function(ir, s)
  emit(s, { "g3_trainer_battle", ir[2], ir[3], ir[4] })
end
L.dotrainerbattle = function(_, s) emit(s, { "g3_do_trainer_battle" }) end
L.checktrainerflag = function(ir, s) emit(s, { "g3_check_trainer_flag", ir[2] }) end
L.settrainerflag = function(ir, s) emit(s, { "g3_set_trainer_flag", ir[2] }) end
L.cleartrainerflag = function(ir, s) emit(s, { "g3_clear_trainer_flag", ir[2] }) end
L.setwildbattle = function(ir, s) emit(s, { "g3_set_wild", ir[2], ir[3], ir[4] }) end
L.dowildbattle = function(_, s) emit(s, { "g3_wild_battle" }) end
L.gotopostbattlescript = L.nop
L.gotobeatenscript = L.nop

-- warps --------------------------------------------------------------------

local function warp(ir, s)
  emit(s, { "g3_warp", ir[2], ir[3], ir[4], ir[5], ir[6] })
end
L.warp = warp
L.warpsilent = warp
L.warpdoor = warp
L.warpteleport = warp
L.warpmossdeepgym = warp
L.warpwhitefade = warp
-- FALLING THROUGH A HOLE keeps your position: `warphole <group> <num>` puts
-- you on that map at the cell you were standing on, and MAP_UNDEFINED
-- (255, 255) means "wherever setholewarp last pointed".  Lowering it to a
-- plain warp handed Commands.warp a nil x and a nil y, and that path skips
-- the warp with a warning rather than dropping the player somewhere wrong --
-- so the two holes in the game did nothing at all.
L.warphole = function(ir, s) emit(s, { "g3_warp_hole", ir[2], ir[3] }) end
L.setwarp = function(ir, s) emit(s, { "g3_set_warp", ir[2], ir[3], ir[4], ir[5], ir[6] }) end
-- NOT an alias for setwarp, though it was one.  The dynamic warp is the slot
-- a warp event pointing at map group 127, map 127 resolves through, and the
-- truck a new game starts inside is built out of exactly that pair: the coord
-- event sets it, the door reads it.  Sharing setwarp's slot meant the door
-- read whatever the last setwarp had left there -- or nothing.
L.setdynamicwarp = function(ir, s)
  emit(s, { "g3_set_dynamic_warp", ir[2], ir[3], ir[4], ir[5], ir[6] })
end
-- These three still share setwarp's slot.  They are the dive, hole and
-- escape-rope destinations, none of which this engine routes yet; they are
-- listed apart rather than aliased silently so the next person can see that
-- the lumping is a gap and not a decision.
L.setdivewarp = L.setwarp
L.setholewarp = function(ir, s)
  emit(s, { "g3_set_hole_warp", ir[2], ir[3], ir[4], ir[5], ir[6] })
end
L.setescapewarp = L.setwarp
L.setrespawn = function(ir, s) emit(s, { "g3_set_respawn", ir[2] }) end

-- sound --------------------------------------------------------------------

-- THE SOUND COMMANDS TAKE A NUMBER, AND NOTHING ELSE DOES.
--
-- Every one of these carries a raw song number out of the cartridge's song
-- table, and the engine addresses songs by the label the import stage writes
-- for them -- SONG_%03X.  Emitting the number meant every `playse`,
-- `playfanfare` and `playbgm` in Hoenn looked up nothing and did nothing:
-- a door that made no sound, an item that arrived in silence, a cutscene
-- whose music never started.
--
-- The two sentinels are the header's way of saying "leave it alone", the
-- same two the map-music stage keeps out of its table.
local SONG_KEEP = { [0xFFFF] = true, [0x7FFF] = true }

local function songLabel(number)
  number = tonumber(number)
  if not number or SONG_KEEP[number] then return nil end
  return ("SONG_%03X"):format(number)
end

L.playse = function(ir, s)
  local song = songLabel(ir[2])
  if song then emit(s, { "play_sound", song }) end
end
L.waitse = L.nop
L.playfanfare = function(ir, s)
  local song = songLabel(ir[2])
  if song then emit(s, { "play_once", song }) end
end
L.waitfanfare = L.nop
L.playbgm = function(ir, s)
  local song = songLabel(ir[2])
  if song then emit(s, { "play_music", song }) end
end
L.savebgm = L.nop
L.fadedefaultbgm = function(_, s) emit(s, { "play_default_music" }) end
L.fadenewbgm = function(ir, s)
  local song = songLabel(ir[2])
  if song then emit(s, { "play_music", song }) end
end
L.fadeoutbgm = function(_, s) emit(s, { "stop_music" }) end
L.fadeinbgm = function(_, s) emit(s, { "play_default_music" }) end
L.playmoncry = function(ir, s) emit(s, { "play_cry", ir[2] }) end
L.waitmoncry = L.nop

-- screen, field, world -----------------------------------------------------

L.delay = function(ir, s) emit(s, { "wait", ir[2] }) end
-- THE FOUR MODES, AND THE DIRECTION EACH ONE MEANS.
--
-- pokeemerald numbers them FADE_FROM_BLACK 0, FADE_TO_BLACK 1,
-- FADE_FROM_WHITE 2, FADE_TO_WHITE 3 -- so the EVEN ones fade the screen back
-- IN and the odd ones fade it OUT.  This was lowered the other way round,
-- which is not a cosmetic slip: `Commands.fade "in"` with no overlay up does
-- nothing at all, so the 126 fades TO black in Hoenn simply did not happen,
-- while the 18 fades FROM black each built a black overlay and ramped it to
-- fully opaque -- a screen that goes black and stays black, with the script
-- carrying on underneath it.
L.fadescreen = function(ir, s) emit(s, { "g3_fade_screen", ir[2] }) end
L.fadescreenspeed = L.fadescreen
L.fadescreenswapbuffers = L.fadescreen
L.setmetatile = function(ir, s) emit(s, { "g3_set_metatile", ir[2], ir[3], ir[4], ir[5] }) end
L.setmaplayoutindex = function(ir, s) emit(s, { "g3_set_layout", ir[2] }) end
L.opendoor = function(ir, s) emit(s, { "g3_door", "open", ir[2], ir[3] }) end
L.closedoor = function(ir, s) emit(s, { "g3_door", "close", ir[2], ir[3] }) end
L.setdooropen = function(ir, s) emit(s, { "g3_door", "set_open", ir[2], ir[3] }) end
L.setdoorclosed = function(ir, s) emit(s, { "g3_door", "set_closed", ir[2], ir[3] }) end
L.waitdooranim = L.nop
L.resetweather = function(_, s) emit(s, { "g3_weather", 0 }) end
L.setweather = function(ir, s) emit(s, { "g3_weather", ir[2] }) end
-- doweather is NOT a nop: it is the half of the pair that takes effect.
-- `setweather` records what the region will be, `doweather` makes it so, and
-- the cartridge always calls them in that order with a fade in between.
L.doweather = function(_, s) emit(s, { "g3_do_weather" }) end
-- `setflashlevel <n>` is how a cave says how dark it is and how the FLASH
-- animation opens the light: the number is an index into the cartridge's own
-- radius table, and dropping it left every cave at whatever the map load had
-- chosen.
L.setflashlevel = function(ir, s) emit(s, { "g3_set_flash_level", ir[2] }) end
L.animateflash = L.nop
L.dofieldeffect = function(ir, s) emit(s, { "g3_field_effect", ir[2] }) end
L.setfieldeffectargument = function(ir, s) emit(s, { "g3_field_effect_arg", ir[2], ir[3] }) end
L.waitfieldeffect = L.nop
L.setstepcallback = L.nop
L.incrementgamestat = function(ir, s) emit(s, { "g3_game_stat", ir[2] }) end
L.getplayerxy = function(ir, s) emit(s, { "g3_player_xy", ir[2], ir[3] }) end
L.checkplayergender = function(_, s) emit(s, { "g3_check_gender" }) end
L.initclock = L.nop
L.dotimebasedevents = L.nop
L.gettime = function(_, s) emit(s, { "g3_get_time" }) end
-- `setberrytree <tree> <berry> <stage>` plants one of Hoenn's fixed berry
-- plots.  A new game runs eighty of them and a handful of later scripts run
-- more, so leaving this a nop meant the region never had a berry in it.
L.setberrytree = function(ir, s)
  emit(s, { "g3_set_berry_tree", ir[2], ir[3], ir[4] })
end
L.setmysteryeventstatus = L.nop
L.reloadmapobjects = L.nop

-- menus and buffers --------------------------------------------------------

L.yesnobox = function(_, s)
  emit(s, { "ask", s.lastText })
  emit(s, { "g3_from_yesno" })
end
L.multichoice = function(ir, s) emit(s, { "g3_multichoice", ir[4], ir[5] }) end
L.multichoicedefault = function(ir, s) emit(s, { "g3_multichoice", ir[4], ir[6], ir[5] }) end
L.multichoicegrid = function(ir, s) emit(s, { "g3_multichoice", ir[4], ir[6] }) end
L.bufferspeciesname = function(ir, s) emit(s, { "g3_buffer", ir[2], "species", ir[3] }) end
L.bufferleadmonspeciesname = function(ir, s) emit(s, { "g3_buffer", ir[2], "lead" }) end
L.bufferpartymonnick = function(ir, s) emit(s, { "g3_buffer", ir[2], "party", ir[3] }) end
L.bufferitemname = function(ir, s) emit(s, { "g3_buffer", ir[2], "item", ir[3] }) end
L.bufferitemnameplural = function(ir, s) emit(s, { "g3_buffer", ir[2], "item", ir[3], ir[4] }) end
L.buffermovename = function(ir, s) emit(s, { "g3_buffer", ir[2], "move", ir[3] }) end
L.buffernumberstring = function(ir, s) emit(s, { "g3_buffer", ir[2], "number", ir[3] }) end
L.bufferstdstring = function(ir, s) emit(s, { "g3_buffer", ir[2], "std", ir[3] }) end
L.bufferstring = function(ir, s) emit(s, { "g3_buffer", ir[2], "text", ir[3] }) end
L.bufferboxname = function(ir, s) emit(s, { "g3_buffer", ir[2], "box", ir[3] }) end
L.buffertrainername = function(ir, s) emit(s, { "g3_buffer", ir[2], "trainer", ir[3] }) end
L.buffertrainerclassname = function(ir, s) emit(s, { "g3_buffer", ir[2], "class", ir[3] }) end
L.bufferdecorationname = function(ir, s) emit(s, { "g3_buffer", ir[2], "decoration", ir[3] }) end
L.buffercontesttypestring = function(ir, s) emit(s, { "g3_buffer", ir[2], "contest", ir[3] }) end
-- showmonpic carries the window's tile position as well as the species, and
-- both are needed: the cartridge puts the box where the script says.
L.showmonpic = function(ir, s)
  emit(s, { "g3_show_mon_pic", ir[2], ir[3], ir[4] })
end
L.hidemonpic = function(_, s) emit(s, { "g3_hide_mon_pic" }) end

-- Coverage hook: an unrecognised opcode lowers to nothing, so the only way to
-- see a gap is to ask the table.
function Gen3ScriptVM.lowered(op) return L[op] ~= nil end
Gen3ScriptVM.LOWERING = L

-- ---------------------------------------------------------------------------
-- compiler
-- ---------------------------------------------------------------------------

local function store(data)
  local pool = data and data.map_scripts
  if pool and pool.source == "RomExtractorGen3" then return pool end
  return nil
end

Gen3ScriptVM.store = store

function Gen3ScriptVM.compile(data, entry)
  local pool = store(data)
  local scripts = pool and pool.scripts
  if not (scripts and type(entry) == "string" and scripts[entry]) then return nil end

  compiled[scripts] = compiled[scripts] or {}
  local hit = compiled[scripts][entry]
  if hit ~= nil then return hit or nil end

  local out, queued, order = {}, { [entry] = true }, { entry }
  local counter = 0
  local state = {
    out = out,
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
      return ("%s_r%d"):format(entry, counter)
    end,
  }

  local index = 1
  while index <= #order do
    local label = order[index]
    index = index + 1
    emit(state, { "label", label })
    -- lastText does NOT survive across script boundaries: a callstd at the
    -- top of one script must not print the line the previous one loaded
    state.lastText = nil
    for _, ir in ipairs(scripts[label] or {}) do
      local lower = L[ir[1]]
      if lower then lower(ir, state) end
    end
    -- a script that ran off the end of its own bytecode still has to unwind
    emit(state, { "g3_return" })
  end

  if #out == 0 then
    Logger.warn("gen3 script vm: '%s' compiled to zero rows (silent NPC)", entry)
  end
  compiled[scripts][entry] = #out > 0 and out or false
  return #out > 0 and out or nil
end

-- ---------------------------------------------------------------------------
-- registration
-- ---------------------------------------------------------------------------

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

-- Map-script slot types.  1 and 3 fire while the map is being set up; 5 on
-- resume; the two table types are var-gated and are checked the same way.
local ON_LOAD, ON_TRANSITION, ON_RESUME = 1, 3, 5
-- The two VAR-GATED TABLES are not the same thing, and treating them as one
-- is what kept Professor Birch standing still on Route 101.
--
--   type 2  ON_FRAME_TABLE      re-checked on the field's frame, over and
--                               over, until a row matches
--   type 4  ON_WARP_INTO_MAP    checked once, as the map is warped into
--
-- Route 101's is a frame table: `VAR_ROUTE101_STATE == 0 -> setflag, setvar 1`.
-- The rescue's coord event then wants that var to be 1 -- and it sits on
-- (10,19) and (11,19), the very row the player lands on crossing up out of
-- Littleroot.  So the table has to have RUN by the time that arrival step is
-- checked.  Running both kinds once, at map entry, through a queue that
-- drains a script per frame, meant the var was still 0 when the coord event
-- asked, the trigger was marked as visited, and the chase never played:
-- Birch just stood at (9,13) where the map file puts him.
--
-- Counted over the cartridge, the split is visible in the data too: 339 of
-- the 375 frame-table rows rewrite the very var that gates them, which is
-- what a per-frame re-check needs to terminate, against 56 of 247 for the
-- warp-into rows, which do not need to.
local ON_FRAME_TABLE, ON_WARP_INTO_MAP_TABLE = 2, 4

local function contributionFor(data, mapId, entry, mapDef)
  local contribution = {}

  local talk = {}
  for objIndex, label in pairs(entry.objects or {}) do
    local obj = mapDef and mapDef.objects and mapDef.objects[objIndex]
    local textConst = obj and obj.text
    if textConst then
      local rows = Gen3ScriptVM.compile(data, label)
      if rows then talk[textConst] = rows end
    end
  end
  for bgIndex, label in pairs(entry.signs or {}) do
    local sign = mapDef and mapDef.signs and mapDef.signs[bgIndex]
    local textConst = sign and sign.text
    if textConst then
      local rows = Gen3ScriptVM.compile(data, label)
      if rows then talk[textConst] = rows end
    end
  end
  if next(talk) then contribution.talk = talk end

  -- ON_LOAD and ON_TRANSITION run before the map is live; ON_RESUME after.
  -- The var-gated tables are the map's real entry conditions -- an ON_FRAME
  -- table is how "the rival is waiting for you the first time you walk in" is
  -- written -- so they are evaluated on entry rather than being flattened
  -- into an unconditional run, which would fire every cutscene the map has
  -- ever had the moment the player steps on it.
  local onEnter = {}
  for _, callback in ipairs(entry.callbacks or {}) do
    if callback.type == ON_LOAD or callback.type == ON_TRANSITION
       or callback.type == ON_RESUME then
      local rows = Gen3ScriptVM.compile(data, callback.script)
      if rows then onEnter[#onEnter + 1] = rows end
    end
  end
  local onWarpIn, onFrame = {}, {}
  for _, tbl in ipairs(entry.tables or {}) do
    local into = (tbl.type == ON_FRAME_TABLE) and onFrame
                 or (tbl.type == ON_WARP_INTO_MAP_TABLE) and onWarpIn
    for _, row in ipairs(tbl.rows or {}) do
      local rows = into and Gen3ScriptVM.compile(data, row.script)
      if rows then
        into[#into + 1] = { var = row.var, value = row.value, rows = rows }
      end
    end
  end
  if #onEnter > 0 or #onWarpIn > 0 or #onFrame > 0 then
    local Gen3Commands = require("src.script.Gen3Commands")
    contribution.onEnter = function(game, overworld)
      -- a fresh visit re-arms the frame table: these closures outlive the
      -- map, and a save loaded into the same map has to be asked again
      for _, g in ipairs(onFrame) do g.armed = nil end
      for _, rows in ipairs(onEnter) do
        queue(overworld, rows, { mapId = mapId })
      end
      for _, g in ipairs(onWarpIn) do
        if Gen3Commands.getVar(game.save, g.var) == g.value then
          queue(overworld, g.rows, { mapId = mapId })
          break
        end
      end
    end
  end

  -- The frame table, asked every frame the field is idle.
  --
  -- It runs the script DIRECTLY rather than through the pending queue: the
  -- whole reason the queue exists is to defer a cutscene until the warp
  -- transition it was triggered by has finished, and a frame table is asked
  -- after that point by definition.  The deferral is what put the var write
  -- a frame late, behind the arrival step it was meant to precede.
  --
  -- A row that has fired is not asked again until the var it gates on has
  -- moved off the matching value.  On the cartridge nothing stops a row
  -- re-firing -- it does not need to, because the script all but always
  -- rewrites its own var -- but 36 of the 375 rows do not, and one of those
  -- looping every frame is a hang rather than a glitch.  Re-arming on the
  -- var makes the ordinary case identical and the pathological one finite.
  if #onFrame > 0 then
    local Gen3Commands = require("src.script.Gen3Commands")
    contribution.onFrame = function(game, overworld)
      for _, g in ipairs(onFrame) do
        local now = Gen3Commands.getVar(game.save, g.var)
        if now ~= g.value then
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

  local coords = {}
  for _, coord in ipairs(entry.coords or {}) do
    local rows = Gen3ScriptVM.compile(data, coord.script)
    if rows then
      coords[#coords + 1] = { x = coord.x, y = coord.y, var = coord.var,
                              value = coord.value, rows = rows }
    end
  end
  if #coords > 0 then
    local Gen3Commands = require("src.script.Gen3Commands")
    -- WHICH ROWS HAVE FIRED WHERE THE PLAYER IS STANDING.
    --
    -- A Gen 3 coord event is gated on a var, so the same cell can be asked
    -- more than once with different answers: the player lands on it while the
    -- var is still 0, the map's frame table writes 1, and the cell is asked
    -- again.  What must not happen is the same ROW running twice for one
    -- visit to the cell, so the memory is per row and it is thrown away the
    -- moment the player is somewhere else.
    --
    -- ...AND "SOMEWHERE ELSE" CANNOT MEAN "ASKED ABOUT A DIFFERENT CELL".
    --
    -- Reported from play: the fences that push you back -- the girl on the
    -- route, Birch's grass, the desert sandstorm without the goggles -- could
    -- all be walked through on the second try.  Every one of them fires a
    -- coord event whose script walks the player BACK off the cell, and a
    -- scripted step does not call onStep: nothing here ever heard about the
    -- move, the memory still read "on that cell, row already fired", and the
    -- walk back in was waved through.
    --
    -- overworld.cellSerial counts cell changes however they happen -- a step,
    -- a scripted walk, a warp, a ledge hop -- which is the question this
    -- actually wants to ask.  The cell string stays as the answer for a
    -- controller that does not keep one.
    local firedAt, fired = nil, {}
    contribution.onStep = function(game, overworld, x, y)
      if overworld.runner:isRunning() then return false end
      -- BOTH, because either alone has a hole: the coordinates miss a
      -- scripted walk off the cell and back onto it, and the counter alone
      -- would depend on the field having bumped it before the step that is
      -- being reported completes.  Together they clear whenever the player
      -- has been anywhere else and never when the same cell is merely
      -- re-asked, which is the case Route 101's rescue needs.
      local here = ("%s|%d,%d"):format(tostring(overworld.cellSerial or 0),
                                       x, y)
      if firedAt ~= here then firedAt, fired = here, {} end
      for i, coord in ipairs(coords) do
        if not fired[i] and coord.x == x and coord.y == y
           and (coord.var == nil or coord.var == 0
                or Gen3Commands.getVar(game.save, coord.var) == coord.value) then
          fired[i] = true
          overworld.runner:run(coord.rows, { mapId = mapId })
          return true
        end
      end
      return false
    end
  end

  return next(contribution) and contribution or nil
end

local PHASE_KEYS = {
  talk = { talk = true },
  scenes = { onEnter = true, onStep = true, onFrame = true },
}

function Gen3ScriptVM.register(data, phase)
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
      Logger.warn("gen3 script vm: %s failed to compile (%s)",
                  mapId, tostring(contribution))
    end
  end
  Logger.info("gen3 script vm: %d maps attached (%s)", attached, tostring(phase or "all"))
  return attached
end

return Gen3ScriptVM
