-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen2 script and movement bytecode tables.
--
-- ScriptCommandTable lives at 25:6BE4 in Gold and holds 162 handlers, $00-$A1.
-- The names below are the ROM's own symbol names; the argument specs were
-- derived from the handlers' `GetScriptByte` calls and then validated by
-- disassembling every script reachable from every map header and map event in
-- Gold (2507 scripts, 2 undecodable).
--
-- Spec letters:
--   b  one byte                     w  two byte little-endian value
--   p  two byte script pointer      t  two byte text pointer
--   d  two byte data pointer        f  three byte far script pointer
--   T  three byte far text pointer  D  three byte far data pointer
--   m  three byte money value       M  two byte movement-data pointer

local Gen2ScriptOps = {}

Gen2ScriptOps.COMMANDS = {
  { "scall", "p" }, { "farscall", "f" }, { "memcall", "p" }, { "sjump", "p" },
  { "farsjump", "f" }, { "memjump", "p" }, { "ifequal", "bp" },
  { "ifnotequal", "bp" }, { "iffalse", "p" }, { "iftrue", "p" },
  { "ifgreater", "bp" }, { "ifless", "bp" }, { "jumpstd", "w" },
  { "callstd", "w" }, { "callasm", "D" }, { "special", "w" },
  { "memcallasm", "D" }, { "checkmapscene", "bb" }, { "setmapscene", "bbb" },
  { "checkscene", "" }, { "setscene", "b" }, { "setval", "b" },
  { "addval", "b" }, { "random", "b" }, { "checkver", "" }, { "readmem", "w" },
  { "writemem", "w" }, { "loadmem", "wb" }, { "readvar", "b" },
  { "writevar", "b" }, { "loadvar", "bb" }, { "giveitem", "bb" },
  { "takeitem", "bb" }, { "checkitem", "b" }, { "givemoney", "bm" },
  { "takemoney", "bm" }, { "checkmoney", "bm" }, { "givecoins", "w" },
  { "takecoins", "w" }, { "checkcoins", "w" }, { "addcellnum", "b" },
  { "delcellnum", "b" }, { "checkcellnum", "b" }, { "checktime", "b" },
  { "checkpoke", "b" }, { "givepoke", "bbbbbD" }, { "giveegg", "bb" },
  { "givepokemail", "T" }, { "checkpokemail", "T" }, { "checkevent", "w" },
  { "clearevent", "w" }, { "setevent", "w" }, { "checkflag", "w" },
  { "clearflag", "w" }, { "setflag", "w" }, { "wildon", "" },
  { "wildoff", "" }, { "xycompare", "d" }, { "warpmod", "bbb" },
  { "blackoutmod", "bb" }, { "warp", "bbbb" }, { "getmoney", "bb" },
  -- getnum is ONE byte in BOTH trees.  pokegold's macro is `db \1 ;
  -- string_buffer` and nothing else (macros/scripts/events.asm:424), exactly
  -- like Crystal's -- reading two bytes here over-ran the operand by one and
  -- DESYNCED the rest of every Gold script that used it.
  { "getcoins", "b" }, { "getnum", "b" }, { "getmonname", "bb" },
  { "getitemname", "bb" }, { "getcurlandmarkname", "b" },
  -- getstring is `dw string, db buffer`, NOT `db buffer, dw string`.  Both
  -- orderings total four bytes so the script never desynced, but the pointer
  -- came out byte-swapped: the Lavender radio director's
  -- `getstring "EXPN CARD", STRING_BUFFER_1` read $016E instead of $6E98, so
  -- the `jumpstd receiveitem` after it printed whatever the string buffer
  -- still held -- the player's last TM.  Checked against every getstring
  -- reachable from a *Script symbol in both ROMs: COIN, SUNDAY.., GEAR,
  -- RADIO CARD, EGG and EXPN CARD all decode under this order, none under
  -- the other.
  { "gettrainername", "bbb" }, { "getstring", "db" }, { "itemnotify", "" },
  -- Script_reanchormap ends with a GetScriptByte call: the operand is unused
  -- but skipping it swallowed the following pokepic.
  { "pocketisfull", "" }, { "opentext", "" }, { "reanchormap", "b" },
  { "closetext", "" }, { "writeunusedbyte", "b" }, { "farwritetext", "T" },
  { "writetext", "t" }, { "repeattext", "bb" }, { "yesorno", "" },
  { "loadmenu", "d" }, { "closewindow", "" }, { "jumptextfaceplayer", "t" },
  { "jumptext", "t" }, { "waitbutton", "" }, { "promptbutton", "" },
  { "pokepic", "b" }, { "closepokepic", "" }, { "_2dmenu", "" },
  { "verticalmenu", "" }, { "loadpikachudata", "" }, { "randomwildmon", "" },
  { "loadtemptrainer", "" }, { "loadwildmon", "bb" }, { "loadtrainer", "bb" },
  { "startbattle", "" }, { "reloadmapafterbattle", "" },
  { "catchtutorial", "b" }, { "trainertext", "b" }, { "trainerflagaction", "b" },
  { "winlosstext", "tt" }, { "scripttalkafter", "" }, { "endifjustbattled", "" },
  { "checkjustbattled", "" }, { "setlasttalked", "b" }, { "applymovement", "bM" },
  { "applymovementlasttalked", "M" }, { "faceplayer", "" },
  { "faceobject", "bb" }, { "variablesprite", "bb" }, { "disappear", "b" },
  { "appear", "b" }, { "follow", "bb" }, { "stopfollow", "" },
  { "moveobject", "bbb" }, { "writeobjectxy", "b" }, { "loademote", "b" },
  { "showemote", "bbb" }, { "turnobject", "bb" }, { "follownotexact", "bb" },
  { "earthquake", "b" }, { "changemapblocks", "bbb" }, { "changeblock", "bbb" },
  { "reloadmap", "" }, { "refreshmap", "" }, { "writecmdqueue", "d" },
  { "delcmdqueue", "b" }, { "playmusic", "w" }, { "encountermusic", "" },
  { "musicfadeout", "wb" }, { "playmapmusic", "" }, { "dontrestartmapmusic", "" },
  { "cry", "w" }, { "playsound", "w" }, { "waitsfx", "" }, { "warpsound", "" },
  { "specialsound", "" }, { "autoinput", "D" }, { "newloadmap", "b" },
  { "pause", "b" }, { "deactivatefacing", "b" }, { "sdefer", "p" },
  { "warpcheck", "" }, { "stopandsjump", "p" }, { "endcallback", "" },
  { "end", "" }, { "reloadend", "" }, { "endall", "" }, { "pokemart", "bw" },
  { "elevator", "d" }, { "trade", "b" }, { "askforphonenumber", "b" },
  { "phonecall", "T" }, { "hangup", "" }, { "describedecoration", "b" },
  { "fruittree", "b" }, { "specialphonecall", "w" }, { "checkphonecall", "" },
  { "verbosegiveitem", "bb" }, { "swarm", "bb" }, { "halloffame", "" },
  { "credits", "" }, { "warpfacing", "bbbbb" },
}

-- Crystal's ScriptCommandTable is NOT Gold's with entries appended.  It
-- inserts `farjumptext` at $52, which shifts all 88 commands after it down by
-- one, and it changes the operand width of seven commands that kept their
-- names.  Disassembling a Crystal ROM with the Gold table desyncs on the
-- first shifted command and never recovers, so Crystal gets its own table.
--
-- Generated from pret/pokecrystal macros/scripts/events.asm: the `const
-- <name>_command` run gives the order, and each MACRO body gives the operand
-- widths.  Where a command kept both its name and its total width, Gold's
-- spec letters are reused verbatim so the semantic distinctions (p vs t vs d)
-- carry over; the seven that changed width are listed below.
--
--   $10 memcallasm    dba -> dw   (D -> d)
--   $2F givepokemail  dba -> dw   (T -> d)
--   $30 checkpokemail dba -> dw   (T -> d)
--   $92 reloadend     0 args -> 1 ("" -> b)
--   $98 phonecall     dba -> dw   (T -> w)
--   $A0 swarm         +map_id     (bb -> bbb)
--
-- `d` rather than `p` for the mail and asm pointers on purpose: `p` makes the
-- extractor queue the target and disassemble it as code, and mail data is not
-- code.
Gen2ScriptOps.COMMANDS_CRYSTAL = {
  { "scall", "p" }, { "farscall", "f" }, { "memcall", "p" },
  { "sjump", "p" }, { "farsjump", "f" }, { "memjump", "p" },
  { "ifequal", "bp" }, { "ifnotequal", "bp" }, { "iffalse", "p" },
  { "iftrue", "p" }, { "ifgreater", "bp" }, { "ifless", "bp" },
  { "jumpstd", "w" }, { "callstd", "w" }, { "callasm", "D" },
  { "special", "w" }, { "memcallasm", "d" }, { "checkmapscene", "bb" },
  { "setmapscene", "bbb" }, { "checkscene", "" }, { "setscene", "b" },
  { "setval", "b" }, { "addval", "b" }, { "random", "b" },
  { "checkver", "" }, { "readmem", "w" }, { "writemem", "w" },
  { "loadmem", "wb" }, { "readvar", "b" }, { "writevar", "b" },
  { "loadvar", "bb" }, { "giveitem", "bb" }, { "takeitem", "bb" },
  { "checkitem", "b" }, { "givemoney", "bm" }, { "takemoney", "bm" },
  { "checkmoney", "bm" }, { "givecoins", "w" }, { "takecoins", "w" },
  { "checkcoins", "w" }, { "addcellnum", "b" }, { "delcellnum", "b" },
  { "checkcellnum", "b" }, { "checktime", "b" }, { "checkpoke", "b" },
  { "givepoke", "bbbbbD" }, { "giveegg", "bb" }, { "givepokemail", "d" },
  { "checkpokemail", "d" }, { "checkevent", "w" }, { "clearevent", "w" },
  { "setevent", "w" }, { "checkflag", "w" }, { "clearflag", "w" },
  { "setflag", "w" }, { "wildon", "" }, { "wildoff", "" },
  { "xycompare", "d" }, { "warpmod", "bbb" }, { "blackoutmod", "bb" },
  { "warp", "bbbb" }, { "getmoney", "bb" }, { "getcoins", "b" },
  { "getnum", "b" }, { "getmonname", "bb" }, { "getitemname", "bb" },
  -- `db` not `bd` -- see the note on the Gold entry above.
  { "getcurlandmarkname", "b" }, { "gettrainername", "bbb" }, { "getstring", "db" },
  { "itemnotify", "" }, { "pocketisfull", "" }, { "opentext", "" },
  { "reanchormap", "b" }, { "closetext", "" }, { "writeunusedbyte", "b" },
  { "farwritetext", "T" }, { "writetext", "t" }, { "repeattext", "bb" },
  { "yesorno", "" }, { "loadmenu", "d" }, { "closewindow", "" },
  -- farjumptext's operand is a far TEXT pointer, not a far SCRIPT pointer.
  -- Both are three bytes so the stream never desynced, but `f` made the
  -- extractor queue the target and disassemble the text as bytecode, and the
  -- operand came out as a script label with nothing to print behind it.  All
  -- eleven of Crystal's uses are std scripts -- the three bookshelves, the
  -- Team Rocket oath, the incense burner, the merchandise shelf, the window,
  -- the homepage, the trash can and the POKeCENTER and MART signs -- so every
  -- one of those was silent.
  { "jumptextfaceplayer", "t" }, { "farjumptext", "T" }, { "jumptext", "t" },
  { "waitbutton", "" }, { "promptbutton", "" }, { "pokepic", "b" },
  { "closepokepic", "" }, { "_2dmenu", "" }, { "verticalmenu", "" },
  { "loadpikachudata", "" }, { "randomwildmon", "" }, { "loadtemptrainer", "" },
  { "loadwildmon", "bb" }, { "loadtrainer", "bb" }, { "startbattle", "" },
  { "reloadmapafterbattle", "" }, { "catchtutorial", "b" }, { "trainertext", "b" },
  { "trainerflagaction", "b" }, { "winlosstext", "tt" }, { "scripttalkafter", "" },
  { "endifjustbattled", "" }, { "checkjustbattled", "" }, { "setlasttalked", "b" },
  { "applymovement", "bM" }, { "applymovementlasttalked", "M" }, { "faceplayer", "" },
  { "faceobject", "bb" }, { "variablesprite", "bb" }, { "disappear", "b" },
  { "appear", "b" }, { "follow", "bb" }, { "stopfollow", "" },
  { "moveobject", "bbb" }, { "writeobjectxy", "b" }, { "loademote", "b" },
  { "showemote", "bbb" }, { "turnobject", "bb" }, { "follownotexact", "bb" },
  { "earthquake", "b" }, { "changemapblocks", "bbb" }, { "changeblock", "bbb" },
  { "reloadmap", "" }, { "refreshmap", "" }, { "writecmdqueue", "d" },
  { "delcmdqueue", "b" }, { "playmusic", "w" }, { "encountermusic", "" },
  { "musicfadeout", "wb" }, { "playmapmusic", "" }, { "dontrestartmapmusic", "" },
  { "cry", "w" }, { "playsound", "w" }, { "waitsfx", "" },
  { "warpsound", "" }, { "specialsound", "" }, { "autoinput", "D" },
  { "newloadmap", "b" }, { "pause", "b" }, { "deactivatefacing", "b" },
  { "sdefer", "p" }, { "warpcheck", "" }, { "stopandsjump", "p" },
  { "endcallback", "" }, { "end", "" }, { "reloadend", "b" },
  { "endall", "" }, { "pokemart", "bw" }, { "elevator", "d" },
  { "trade", "b" }, { "askforphonenumber", "b" }, { "phonecall", "w" },
  { "hangup", "" }, { "describedecoration", "b" }, { "fruittree", "b" },
  { "specialphonecall", "w" }, { "checkphonecall", "" }, { "verbosegiveitem", "bb" },
  { "verbosegiveitemvar", "bb" }, { "swarm", "bbb" }, { "halloffame", "" },
  { "credits", "" }, { "warpfacing", "bbbbb" }, { "battletowertext", "b" },
  { "getlandmarkname", "bb" }, { "gettrainerclassname", "bb" }, { "getname", "bbb" },
  { "wait", "b" }, { "checksave", "" },
}

-- Which table a ROM speaks.  Gold/Silver share COMMANDS; Crystal has its own.
-- Defaults to Gold, so nothing changes until a caller asks for crystal.
-- Prism's ScriptCommandTable (engine/scripting.asm): 232 commands where
-- Gold/Crystal have ~120, and the two diverge from index 13 onward -- so a
-- Prism script read with Crystal's table desyncs on the first shifted opcode
-- and never recovers.  Widths are DERIVED from the handlers' own stream reads
-- (tools/derive_args.py walks each handler's control flow to `ret`, taking the
-- max over branches because both arms of an `if_*` consume the same bytes).
Gen2ScriptOps.COMMANDS_PRISM = {
  { "scall", "p" }, { "farscall", "f" }, { "ptcall", "d" }, -- 00
  { "jump", "p" }, { "farjump", "f" }, { "ptjump", "d" }, -- 03
  { "if_equal", "bp" }, { "if_not_equal", "bp" }, { "iffalse", "p" }, -- 06
  { "iftrue", "p" }, { "if_greater_than", "bp" }, { "if_less_than", "bp" }, -- 09
  { "jumpstd", "b" }, { "fieldmovepokepic", "" }, { "callasm", "D" }, -- 0C
  { "special", "b" }, { "ptcallasm", "w" }, { "checkmaptriggers", "bb" }, -- 0F
  { "domaptrigger", "bbb" }, { "checktriggers", "" }, { "dotrigger", "b" }, -- 12
  { "writebyte", "b" }, { "addvar", "b" }, { "random", "b" }, -- 15
  { "readarrayhalfword", "b" }, { "copybytetovar", "w" }, { "copyvartobyte", "w" }, -- 18
  { "loadvar", "wb" }, { "checkcode", "b" }, { "writevarcode", "b" }, -- 1B
  { "writecode", "bb" }, { "giveitem", "bb" }, { "takeitem", "bb" }, -- 1E
  { "checkitem", "b" }, { "givemoney", "bm" }, { "takemoney", "bm" }, -- 21
  { "checkmoney", "bm" }, { "givecoins", "w" }, { "takecoins", "w" }, -- 24
  { "checkcoins", "w" }, { "writehalfword", "w" }, { "pushhalfword", "w" }, -- 27
  { "pushhalfwordvar", "" }, { "checktime", "b" }, { "checkpoke", "b" }, -- 2A
  { "givepoke", "bbbbww" }, { "giveegg", "bb" }, { "copyhalfwordvartovar", "" }, -- 2D
  { "copyvartohalfwordvar", "" }, { "checkevent", "w" }, { "clearevent", "w" }, -- 30
  { "setevent", "w" }, { "checkflag", "w" }, { "clearflag", "w" }, -- 33
  { "setflag", "w" }, { "wildon", "" }, { "wildoff", "" }, -- 36
  { "warpmod", "bbb" }, { "blackoutmod", "bb" }, { "warp", "bbbb" }, -- 39
  { "readmoney", "bb" }, { "readcoins", "b" }, { "variablestablerandom", "bb" }, -- 3C
  { "pokenamemem", "bb" }, { "itemtotext", "bb" }, { "mapnametotext", "b" }, -- 3F
  { "trainertotext", "bbb" }, { "stringtotext", "wb" }, { "itemnotify", "" }, -- 42
  { "pocketisfull", "" }, { "opentext", "" }, { "refreshscreen", "" }, -- 45
  { "closetext", "" }, { "cmdwitharrayargs", "c" }, { "farwritetext", "T" }, -- 48
  { "writetext", "t" }, { "repeattext", "" }, { "yesorno", "" }, -- 4B
  { "loadmenudata", "w" }, { "closewindow", "" }, { "jumptextfaceplayer", "t" }, -- 4E
  { "farjumptext", "T" }, { "jumptext", "t" }, { "waitbutton", "" }, -- 51
  { "buttonsound", "" }, { "pokepic", "b" }, { "closepokepic", "" }, -- 54
  { "eventvarop", "b" }, { "verticalmenu", "" }, { "scrollingmenu", "b" }, -- 57
  { "randomwildmon", "" }, { "loadmemtrainer", "" }, { "loadwildmon", "bL" }, -- 5A
  { "loadtrainer", "bb" }, { "startbattle", "" }, { "reloadmapafterbattle", "" }, -- 5D
  { "addhalfwordtovar", "w" }, { "trainertext", "b" }, { "trainerflagaction", "b" }, -- 60
  { "winlosstext", "tt" }, { "scripttalkafter", "" }, { "end_if_just_battled", "" }, -- 63
  { "check_just_battled", "" }, { "setlasttalked", "b" }, { "applymovement", "bM" }, -- 66
  { "applymovement2", "M" }, { "faceplayer", "" }, { "faceperson", "bb" }, -- 69
  { "variablesprite", "bb" }, { "disappear", "b" }, { "appear", "b" }, -- 6C
  { "follow", "bb" }, { "stopfollow", "" }, { "moveperson", "bbb" }, -- 6F
  { "writepersonxy", "b" }, { "loademote", "b" }, { "showemote", "bbbb" }, -- 72
  { "spriteface", "bb" }, { "follownotexact", "bb" }, { "earthquake", "b" }, -- 75
  { "changemap", "bw" }, { "changeblock", "bbb" }, { "reloadmap", "" }, -- 78
  { "reloadmappart", "" }, { "writecmdqueue", "w" }, { "delcmdqueue", "b" }, -- 7B
  { "playmusic", "w" }, { "encountermusic", "" }, { "musicfadeout", "wb" }, -- 7E
  { "playmapmusic", "" }, { "dontrestartmapmusic", "" }, { "cry", "b" }, -- 81
  { "playsound", "w" }, { "waitsfx", "" }, { "warpsound", "" }, -- 84
  { "copyvarbytetovar", "" }, { "newloadmap", "b" }, { "pause", "b" }, -- 87
  { "deactivatefacing", "b" }, { "priorityjump", "p" }, { "warpcheck", "" }, -- 8A
  { "ptpriorityjump", "p" }, { "return", "" }, { "end", "" }, -- 8D
  { "reloadandreturn", "b" }, { "end_all", "" }, { "pokemart", "bb" }, -- 90
  { "elevator", "w" }, { "scriptstartasmf", "" }, { "pophalfwordvar", "" }, -- 93
  { "unused_96", "" }, { "unused_97", "" }, { "pushbyte", "b" }, -- 96
  { "fruittree", "b" }, { "swapbyte", "b" }, { "loadarray", "wb" }, -- 99
  { "verbosegiveitem", "bb" }, { "verbosegiveitem2", "bb" }, { "swarm", "bbb" }, -- 9C
  { "killsfx", "" }, { "checkiteminbox", "b" }, { "warpfacing", "bbbbb" }, -- 9F
  { "battletowertext", "b" }, { "landmarktotext", "bb" }, { "trainerclassname", "bb" }, -- A2
  { "name", "bbb" }, { "wait", "b" }, { "loadscrollingmenudata", "w" }, -- A5
  { "backupcustchar", "" }, { "restorecustchar", "" }, { "addhalfwordvartovar", "" }, -- A8
  { "addhalfwordtohalfwordvar", "w" }, { "givecraftingEXP", "b" }, { "copybytetohalfwordvar", "w" }, -- AB
  { "givetm", "b" }, { "unused_AF", "" }, { "itemplural", "b" }, -- AE
  { "pullvar", "" }, { "setplayersprite", "b" }, { "setplayercolor", "bb" }, -- B1
  { "loadsignpost", "w" }, { "checkpokemontype", "b" }, { "isinarray", "wwbb" }, -- B4
  { "pusharray", "" }, { "poparray", "" }, { "startmirrorbattle", "" }, -- B7
  { "comparevartobyte", "w" }, { "backupsecondpokemon", "" }, { "restoresecondpokemon", "" }, -- BA
  { "loadhalfwordvar", "b" }, { "pullhalfwordvar", "" }, { "divideby", "b" }, -- BD
  { "isinsingulararray", "w" }, { "getnthstring", "wb" }, { "readpersonxy", "bw" }, -- C0
  { "return_if_callback_else_end", "" }, { "copy", "wc" }, { "switch", "b" }, -- C3
  { "multiplyvar", "b" }, { "seteventvar", "b" }, { "callasmf", "D" }, -- C6
  { "jumptable", "d" }, { "anonjumptable", "" }, { "varblocks", "w" }, -- C9
  { "addbytetovar", "w" }, { "paragraphdelay", "" }, { "playwaitsfx", "w" }, -- CC
  { "scriptstartasm", "" }, { "copystring", "b" }, { "endtext", "" }, -- CF
  { "pushvar", "" }, { "popvar", "" }, { "swapvar", "" }, -- D2
  { "getweekday", "" }, { "toggle", "www" }, { "unused_D7", "" }, -- D5
  { "selse", "" }, { "sendif", "" }, { "siffalse", "" }, -- D8
  { "siftrue", "" }, { "sifgt", "b" }, { "siflt", "b" }, -- DB
  { "sifeq", "b" }, { "sifne", "b" }, { "readarray", "b" }, -- DE
  { "givetmnomessage", "b" }, { "findpokemontype", "b" }, { "startpokeonly", "bbb" }, -- E1
  { "endpokeonly", "bbb" }, { "fadetomapmusic", "b" }, { "menuanonjumptable", "w" }, -- E4
  { "modifyeventvar", "b" }, { "showtext", "t" }, { "closetextend", "" }, -- E7
  { "toggleevent", "w" }, { "getpartymonname", "b" }, -- EA
}

-- Commands after which the interpreter never reads the next byte.  Derived
-- from the handlers (those reaching StopScript or an UNCONDITIONAL ScriptJump)
-- and unioned with the ones that are certain by definition.  A terminator the
-- walker does not know is what runs it off the end of a script into the data
-- that follows, which is where "opcode FF" desyncs come from -- FF is past the
-- end of a 232-entry table, so it was never a command at all.
Gen2ScriptOps.TERMINATORS_PRISM = {
  anonjumptable = true, closetextend = true, ["end"] = true, end_all = true,
  endtext = true, farjump = true, farjumptext = true, fruittree = true,
  jump = true, jumpstd = true, jumptext = true, jumptextfaceplayer = true,
  loadsignpost = true, menuanonjumptable = true, pokemart = true, ptjump = true,
  ptpriorityjump = true, reloadandreturn = true, ["return"] = true, return_if_callback_else_end = true,
  scriptstartasmf = true, scripttalkafter = true,
}

-- Prism's `sif` family.  `sif true` with no `then` guards exactly ONE
-- following command, so a terminator in that position ends the branch rather
-- than the script -- see gen2DecodeScript.  A `then` marker after the sif
-- (opcode $CF, which Prism aliases onto scriptstartasm) opens a block that
-- runs to `sendif` instead, and needs no special handling.
Gen2ScriptOps.SIF_COMMANDS_PRISM = {
  siftrue = true, siffalse = true,
  sifeq = true, sifne = true, sifgt = true, siflt = true,
}

-- Polished Crystal's script command table: 224 commands where
-- Gold/Crystal have ~120, renumbered from index 3 onward -- so a
-- Polished Crystal script read with Crystal's table desyncs on the
-- first shifted opcode and never recovers.
--
-- GENERATED by tools/gen_polished_ops.py.  Names and operand widths
-- come from the disassembly's macros/scripts/events.asm, where each
-- MACRO body is literally what the assembler emits; the terminator
-- list is derived from engine/overworld/scripting.asm by following
-- each handler to StopScript/ScriptJump rather than from the command
-- NAMES, which lie both ways here (`iffalse_jumptext` falls through,
-- `fruittree` never returns).  Do not hand-edit: regenerate.
Gen2ScriptOps.COMMANDS_POLISHED = {
  { "scall", "p" }, { "farscall", "f" }, { "memcall", "p" }, -- 00
  { "sjump", "p" }, { "farsjump", "f" }, { "memjump", "p" }, -- 03
  { "ifequal", "bp" }, { "ifnotequal", "bp" }, { "iffalse", "p" }, -- 06
  { "iftrue", "p" }, { "ifgreater", "bp" }, { "ifless", "bp" }, -- 09
  { "jumpstd", "b" }, { "callstd", "b" }, { "callasm", "f" }, -- 0C
  { "special", "b" }, { "memcallasm", "w" }, { "checkmapscene", "" }, -- 0F
  { "setmapscene", "b" }, { "checkscene", "" }, { "setscene", "b" }, -- 12
  { "setval", "b" }, { "setval16", "w" }, { "addval", "b" }, -- 15
  { "random", "b" }, { "random16", "w" }, { "readmem", "w" }, -- 18
  { "readmem16", "ww" }, { "writemem", "w" }, { "loadmem", "wb" }, -- 1B
  { "readvar", "b" }, { "writevar", "b" }, { "loadvar", "bb" }, -- 1E
  { "giveitem", "bbb" }, { "takeitem", "bbb" }, { "checkitem", "b" }, -- 21
  { "givemoney", "bm" }, { "takemoney", "bm" }, { "checkmoney", "bm" }, -- 24
  { "givecoins", "w" }, { "takecoins", "w" }, { "checkcoins", "w" }, -- 27
  { "addcellnum", "b" }, { "delcellnum", "b" }, { "checkcellnum", "b" }, -- 2A
  { "checktime", "b" }, { "checkpoke", "" }, { "givepoke", "bbbbbbbbbppb" }, -- 2D
  { "giveegg", "" }, { "givepokemail", "p" }, { "checkpokemail", "p" }, -- 30
  { "checkevent", "w" }, { "clearevent", "w" }, { "setevent", "w" }, -- 33
  { "checkflag", "w" }, { "clearflag", "w" }, { "setflag", "w" }, -- 36
  { "wildon", "" }, { "wildoff", "" }, { "warpmod", "b" }, -- 39
  { "blackoutmod", "" }, { "warp", "bb" }, { "getmoney", "bb" }, -- 3C
  { "getcoins", "b" }, { "getnum", "b" }, { "getmonname", "b" }, -- 3F
  { "getitemname", "bb" }, { "getcurlandmarkname", "b" }, { "gettrainername", "bbb" }, -- 42
  { "getstring", "tb" }, { "itemnotify", "" }, { "pocketisfull", "" }, -- 45
  { "opentext", "" }, { "reanchormap", "" }, { "closetext", "" }, -- 48
  { "farwritetext", "f" }, { "writetext", "t" }, { "repeattext", "" }, -- 4B
  { "yesorno", "" }, { "loadmenu", "M" }, { "closewindow", "" }, -- 4E
  { "jumptextfaceplayer", "t" }, { "farjumptext", "f" }, { "jumptext", "t" }, -- 51
  { "waitbutton", "" }, { "promptbutton", "" }, { "pokepic", "b" }, -- 54
  { "closepokepic", "" }, { "_2dmenu", "" }, { "verticalmenu", "" }, -- 57
  { "randomwildmon", "" }, { "loadtemptrainer", "" }, { "loadwildmon", "bb" }, -- 5A
  { "loadtrainer", "bb" }, { "startbattle", "" }, { "reloadmapafterbattle", "" }, -- 5D
  { "catchtutorial", "b" }, { "trainertext", "b" }, { "trainerflagaction", "b" }, -- 60
  { "winlosstext", "tt" }, { "scripttalkafter", "" }, { "endifjustbattled", "" }, -- 63
  { "checkjustbattled", "" }, { "setlasttalked", "b" }, { "applymovement", "bM" }, -- 66
  { "applymovementlasttalked", "M" }, { "faceplayer", "" }, { "faceobject", "bb" }, -- 69
  { "variablesprite", "bb" }, { "disappear", "b" }, { "appear", "b" }, -- 6C
  { "follow", "bb" }, { "stopfollow", "" }, { "moveobject", "bbb" }, -- 6F
  { "writeobjectxy", "b" }, { "loademote", "b" }, { "showemote", "bbb" }, -- 72
  { "turnobject", "bb" }, { "follownotexact", "bb" }, { "earthquake", "b" }, -- 75
  { "changemapblocks", "f" }, { "changeblock", "bbb" }, { "reloadmap", "" }, -- 78
  { "refreshmap", "" }, { "usestonetable", "p" }, { "playmusic", "b" }, -- 7B
  { "encountermusic", "" }, { "musicfadeout", "bb" }, { "playmapmusic", "" }, -- 7E
  { "dontrestartmapmusic", "" }, { "cry", "b" }, { "playsound", "b" }, -- 81
  { "waitsfx", "" }, { "warpsound", "" }, { "specialsound", "" }, -- 84
  { "autoinput", "b" }, { "newloadmap", "b" }, { "pause", "b" }, -- 87
  { "deactivatefacing", "b" }, { "sdefer", "p" }, { "warpcheck", "" }, -- 8A
  { "stopandsjump", "p" }, { "endcallback", "" }, { "end", "" }, -- 8D
  { "reloadend", "b" }, { "endall", "" }, { "pokemart", "bb" }, -- 90
  { "elevator", "p" }, { "trade", "b" }, { "askforphonenumber", "b" }, -- 93
  { "hangup", "" }, { "describedecoration", "b" }, { "fruittree", "bb" }, -- 96
  { "specialphonecall", "b" }, { "checkphonecall", "" }, { "verbosegiveitem", "bbb" }, -- 99
  { "verbosegiveitemvar", "bb" }, { "swarm", "b" }, { "halloffame", "" }, -- 9C
  { "credits", "" }, { "warpfacing", "bbb" }, { "battletowertext", "b" }, -- 9F
  { "getlandmarkname", "bb" }, { "gettrainerclassname", "bb" }, { "wait", "b" }, -- A2
  { "checksave", "" }, { "trainerpic", "b" }, { "givetmhm", "b" }, -- A5
  { "checktmhm", "b" }, { "verbosegivetmhm", "b" }, { "tmhmnotify", "" }, -- A8
  { "gettmhmname", "bb" }, { "checkdarkness", "" }, { "checkunits", "" }, -- AB
  { "unowntypeface", "" }, { "restoretypeface", "" }, { "jumpstashedtext", "" }, -- AE
  { "jumpopenedtext", "t" }, { "iftrue_jumptext", "t" }, { "iffalse_jumptext", "t" }, -- B1
  { "iftrue_jumptextfaceplayer", "t" }, { "iffalse_jumptextfaceplayer", "t" }, { "iftrue_jumpopenedtext", "t" }, -- B4
  { "iffalse_jumpopenedtext", "t" }, { "writethistext", "" }, { "jumpthistext", "" }, -- B7
  { "jumpthistextfaceplayer", "" }, { "jumpthisopenedtext", "" }, { "showtext", "t" }, -- BA
  { "showtextfaceplayer", "t" }, { "applyonemovement", "bbb" }, { "showcrytext", "t" }, -- BD
  { "endtext", "" }, { "waitendtext", "" }, { "iftrue_endtext", "" }, -- C0
  { "iffalse_endtext", "" }, { "loadgrottomon", "" }, { "giveapricorn", "bbb" }, -- C3
  { "paintingpic", "b" }, { "checkegg", "" }, { "givekeyitem", "b" }, -- C6
  { "checkkeyitem", "b" }, { "takekeyitem", "b" }, { "verbosegivekeyitem", "b" }, -- C9
  { "keyitemnotify", "" }, { "givebp", "w" }, { "takebp", "w" }, -- CC
  { "checkbp", "w" }, { "sjumpfwd", "b" }, { "ifequalfwd", "bb" }, -- CF
  { "iffalsefwd", "b" }, { "iftruefwd", "b" }, { "scalltable", "p" }, -- D2
  { "setmapobjectmovedata", "bb" }, { "setmapobjectpal", "bb" }, { "givespecialitem", "b" }, -- D5
  { "givebadge", "b" }, { "setquantity", "" }, { "pluralize", "p" }, -- D8
  -- $DB loadtrainerwithpal is the LAST command.  RunScriptCommand.Jumptable
  -- (25:$62f2) holds exactly $DC entries -- the word at entry $DC is the
  -- dispatcher's own code, not a pointer.  The four rows that used to follow
  -- here (nooryes, digmod, toggleevent, usepaletteswap) came from a Crystal
  -- fork's LONGER table; this ROM never dispatches $DC-$DF, so decoding them
  -- as commands consumed operand bytes that were never operands and every
  -- "after usepaletteswap"/"after nooryes"/"after digmod" desync in the log
  -- was this table being four rows too generous.
  { "loadtrainerwithpal", "bbb" }, -- DB
}

Gen2ScriptOps.TERMINATORS_POLISHED = {
  ["credits"] = true, ["describedecoration"] = true, ["end"] = true, ["endall"] = true,
  ["endcallback"] = true, ["endtext"] = true, ["farjumptext"] = true, ["farsjump"] = true,
  ["fruittree"] = true, ["halloffame"] = true, ["jumpopenedtext"] = true, ["jumpstashedtext"] = true,
  ["jumpstd"] = true, ["jumptext"] = true, ["jumptextfaceplayer"] = true, ["jumpthisopenedtext"] = true,
  ["jumpthistext"] = true, ["jumpthistextfaceplayer"] = true, ["memjump"] = true, ["pokemart"] = true,
  -- `reloadmapafterbattle` IS NOT A TERMINATOR, and treating it as one
  -- truncated 463 of 4472 decoded scripts (10%) -- essentially every trainer
  -- and gym-leader script, cut off exactly where it hands out its rewards.
  --
  -- The two opcodes look alike and behave differently.  Script_reloadend
  -- (25:$7166) is `call Script_newloadmap / jr Script_end`: it really does end.
  -- Script_reloadmapafterbattle (25:$6AF7) falls past its blackout and
  -- mem-script branches into Script_reloadmap (25:$6B3B) and the script CARRIES
  -- ON.  BlackthornGymClairScript is the proof -- nine commands follow it,
  -- ending in `end`, and two of them hide the gramps blocking the Dragon's Den
  -- mouth and reveal his stepped-aside copy.  Lose those and the Den has no
  -- entrance, which is the reported bug.  Gen2ScriptVM already lowers this
  -- opcode to an ordinary command (g2_after_battle), so the importer was
  -- contradicting the runtime.
  ["reloadend"] = true, ["scripttalkafter"] = true, ["sjump"] = true,
  ["sjumpfwd"] = true, ["stopandsjump"] = true, ["trade"] = true, ["waitendtext"] = true,
}

function Gen2ScriptOps.terminatorsFor(version)
  if version == "polishedcrystal" then
    return Gen2ScriptOps.TERMINATORS_POLISHED
  end
  if version == "prism" then return Gen2ScriptOps.TERMINATORS_PRISM end
  return Gen2ScriptOps.TERMINATORS
end

-- ADDITIVE BY CONSTRUCTION. Every branch here tests one version id and the
-- fall-through is the Gold table these functions have always returned, so a
-- version that is not named reads exactly the bytes it read before. That is
-- the whole reason the hack tables live beside Gold's rather than being merged
-- into it: Gold, Silver and Crystal cannot be affected by a hack's table being
-- wrong, and a hack cannot be affected by the others being right.
-- OPERAND WIDTHS AND OPERAND KINDS, READ OUT OF THE CARTRIDGE'S HANDLERS.
--
-- tools/gen_polished_ops.py builds COMMANDS_POLISHED from a Polished Crystal
-- disassembly and is right about almost all 224 commands -- but it was run
-- against a different build from the one being imported, and where the two
-- disagree the walker resumes on the wrong byte and never recovers.
--
-- Each entry below was read by disassembling the handler the ROM's own
-- jumptable (25:$62f2) points at and counting its calls to GetScriptByte
-- (00:$20f7) and GetScriptWord (00:$2113). Nothing here is inferred from how
-- many desyncs it removes: that number improves when the walker decodes LESS,
-- and a search that optimises it converges on a table where every command is
-- one byte wide.
--
-- HOW THIS LIST WAS WRONG THE FIRST TIME, because it is worth keeping: the
-- opcodes were enumerated from the source table with a pattern that only
-- matched LOWERCASE operand specs, and three entries -- loadmenu, applymovement
-- and applymovementlasttalked -- carry an uppercase one. So every opcode from
-- $4F upwards came out one too low, and two of the five "fixes" landed on the
-- command NEXT to the one whose handler had been read. loadtrainer was already
-- correct and was made wrong; loadwildmon was wrong and was left alone.
--
--   warp         $3D 25:$709b  FOUR bytes -- group, number, x, y, into
--                    $dcac/$dcad/$dcaf/$dcae. At two, every scripted warp fed
--                    the runtime a nil x and y, which is a hard crash the
--                    moment a script warps you anywhere.
--   giveitem     $21 25:$6e06  two, not three
--   takeitem     $22 25:$6e20  two, not three
--   loadwildmon  $5C 25:$6a90  three ($d234, $d467, $d115), not two
--
-- ...and two are about what the operand IS rather than how wide it is. `f` is
-- a far SCRIPT pointer and `T` a far TEXT pointer; both are three bytes, so a
-- wrong letter costs nothing in alignment and everything in meaning -- the
-- operand is queued as a script that is never entered instead of as a line of
-- dialogue, and the command comes out with an empty argument.
--
--   farwritetext $4B 25:$65a9  GetScriptByte (the bank) then GetScriptWord,
--                    then `jp $20ca` -- the same printer writetext reaches
--   farjumptext  $52 25:$656d  bank, then the address, then ScriptJump into
--                    JumpTextScript
--
-- jumptext ($53) and jumptextfaceplayer ($51) are deliberately NOT here: both
-- go through _GetTextPointer (25:$654b), which takes the bank from $ffeb --
-- the script's own -- and reads only two bytes, so `t` is already right and
-- widening either would desync every script that uses it.
local POLISHED_WIDTH_FIXES = {
  warp = "bbbb", giveitem = "bb", takeitem = "bb",
  loadwildmon = "bbb", farwritetext = "T", farjumptext = "T",
  -- THE FORWARD JUMPS, which Gold and Crystal do not have at all. The operand
  -- is a byte counted from the instruction after it (Script_sjumpfwd,
  -- 25:$6c46). Emitted as a bare number the port cannot branch on it, so the
  -- command does nothing and the script falls into the arm it meant to skip.
  -- That is the Elm loop: his script ends `checkevent 121 / iffalsefwd 32 /
  -- scall / jumptext`, and with the skip inert the "I need your help!" branch
  -- runs again every time you answer it.
  sjumpfwd = "j", iffalsefwd = "j", iftruefwd = "j", ifequalfwd = "bj",
  -- EVERY WIDTH BELOW WAS READ OUT OF ITS HANDLER via the jumptable at
  -- 25:$62f2, counting GetScriptByte (00:$20f7), GetScriptWord (00:$2113)
  -- and the bank-25 wrappers GetScriptWordBC/DE (25:$64b2/$64aa).  The
  -- convention that made the first automated sweep lie: `rst $10` is
  -- FarCall with an INLINE `dw addr, db bank` -- and bit 15 of that word is
  -- a far-JUMP flag, so a set bit ends the handler and a clear one returns
  -- past the three inline bytes.
  --
  -- The map-pair commands (checkmapscene "bb", setmapscene "bbb", warpmod
  -- "bbb", blackoutmod "bb", warpfacing "bbbbb") matter twice over: with the
  -- short specs the (group, number) pair was never read, so
  -- gen2ResolveScriptMapIds had nothing to fold and g2_set_scene refused the
  -- bare number -- which is a big slice of "areas where I step and activate
  -- an event aren't working": their scenes were never armed.
  checkmapscene = "bb", setmapscene = "bbb",
  checkpoke = "bb",                -- species byte + form byte (GetScriptByte x2)
  giveegg = "bb",                  -- species + form; the LEVEL is not an
                                   -- operand here: the handler writes 1
  givepoke = "bbbbbbg",            -- species, form, level, item, ball, c540,
                                   -- then a trigger byte that pulls SIX more
                                   -- (two far name pointers) when nonzero
  warpmod = "bbb", blackoutmod = "bb",
  getmonname = "bbb",              -- GetScriptWordDE species word + buffer
  pokepic = "s", cry = "s",        -- species byte, form byte ONLY if nonzero
  showcrytext = "ts",              -- text pointer + the same species pair
  autoinput = "bd",                -- input kind + a data pointer (jp $0744)
  verbosegiveitem = "bb",          -- falls into Script_giveitem, adds nothing
  swarm = "bbb", warpfacing = "bbbbb",
  giveapricorn = "bb",             -- two unconditional GetScriptByte
  -- POINTERS THAT ARE NOT SCRIPTS.  `f` and `p` QUEUE their target through
  -- the script walker; these commands point at asm or data, and queueing
  -- them decoded _UpdateSprites, the bridge callbacks, the gym trash cans
  -- and every *_BlockData table as bytecode -- most of the remaining
  -- "opcode after <start>" desyncs were exactly these.
  callasm = "D",                   -- far pointer to Z80 code, named not walked
  changemapblocks = "D",           -- far pointer to a block-data table
  usestonetable = "d",             -- pointer to a stone table (decoded below)
  pluralize = "d",                 -- pointer to the singular/plural strings
}

function Gen2ScriptOps.commandsFor(version)
  if version == "polishedcrystal" then
    if not Gen2ScriptOps._polishedFixed then
      Gen2ScriptOps._polishedFixed = true
      for _, command in ipairs(Gen2ScriptOps.COMMANDS_POLISHED) do
        local fixed = POLISHED_WIDTH_FIXES[command[1]]
        if fixed then command[2] = fixed end
      end
      -- Some commands share a NAME with Crystal's but not an operand order
      -- (giveegg is species+form here, species+level there), and the VM
      -- lowers by name alone.  This flag tells the extractor to normalise
      -- those rows back to the shape the VM speaks -- it travels WITH the
      -- table so nothing downstream needs a version id.
      Gen2ScriptOps.COMMANDS_POLISHED.normalizeOperands = true
    end
    return Gen2ScriptOps.COMMANDS_POLISHED
  end
  if version == "prism" then return Gen2ScriptOps.COMMANDS_PRISM end
  if version == "crystal" then return Gen2ScriptOps.COMMANDS_CRYSTAL end
  return Gen2ScriptOps.COMMANDS
end

Gen2ScriptOps.ARG_BYTES = {
  b = 1, w = 2, p = 2, t = 2, d = 2, M = 2, f = 3, T = 3, D = 3, m = 3,
  -- `j` is one byte like `b`, but it is a RELATIVE FORWARD JUMP: the
  -- extractor turns it into the label of the instruction it lands on, so the
  -- port has something to branch to. See the "j" arm in RomExtractorGen2.
  j = 1,
  -- `s` is a SPECIES PAIR: one byte, plus a form byte that is present ONLY
  -- when the species byte is nonzero (GetCurPartyMonSpeciesIfZero skips the
  -- second read -- Script_pokepic 25:$65fe, Script_cry 25:$68a7).  `g` is
  -- givepoke's trigger byte: six more bytes follow when it is nonzero.  Both
  -- list their MINIMUM here; the extractor's own arm advances the rest.
  s = 1, g = 1,
  -- PRISM'S TWO VARIABLE TAILS, both read straight out of the handlers the
  -- script jumptable points at (25:$62f2 -> the addresses below).
  --
  -- `L` is loadwildmon's SECOND operand (Script_loadwildmon 25:$60F8).  The
  -- handler reads it with GetScriptByte, tests `bit 7`, and RETURNS when the
  -- bit is clear -- so the short form is TWO bytes total.  With the bit set it
  -- clears it, stores the value, and copies FIVE more bytes into $C7FB.  Read
  -- as a fixed five-operand command (the old "bbbbb") every short loadwildmon
  -- over-ran its operands by four bytes and the rest of that script decoded
  -- from the wrong byte -- silently, because the bytes it landed on were
  -- usually still valid opcodes.
  --
  -- `c` is an INLINE BLOB LENGTH: one count byte, then that many raw data
  -- bytes that are NOT bytecode.  Two commands use it, and the macros say so
  -- in as many words -- `cmdwitharrayargs_length` and `copycmd_length` both
  -- emit `db <end label> - <label placed immediately after the db>`, i.e. the
  -- byte counts everything that follows it up to the matching
  -- `endcmdwitharrayargs` / `endcopy`.  Script_copy (25:$6DF1) is
  -- GetScriptHalfwordOrVar_HL (the destination) / GetScriptByteOrVar (the
  -- count) / `GetScriptByte, ld [hl+], dec c` until the count runs out, and
  -- the macro pair `copy`/`endcopy` (macros/event.asm) emits exactly that:
  -- `dw dest, db length` followed by the payload.  The old "wbb" read two
  -- fixed bytes and then tried to execute the payload.
  L = 1, c = 1,
}

-- commands after which the interpreter never falls through to the next byte
Gen2ScriptOps.TERMINATORS = {
  sjump = true, farsjump = true, memjump = true, jumpstd = true,
  -- farjumptext is Crystal's far-pointer jumptext and ends the script the
  -- same way; missing it would walk the disassembler into the next script.
  jumptext = true, jumptextfaceplayer = true, farjumptext = true,
  stopandsjump = true,
  endcallback = true, ["end"] = true, reloadend = true, endall = true,
  halloffame = true, credits = true, fruittree = true,
  -- BOTH `jp ScriptJump` UNCONDITIONALLY, exactly like jumpstd.
  --
  -- Script_scripttalkafter (Crystal 25:$7125) loads the after-script pointer
  -- and jumps; Script_describedecoration (25:$70DF) farcalls DescribeDecoration
  -- and jumps to whatever it returned.  Neither can fall through, so leaving
  -- them out walked the disassembler PAST the end of the script into whatever
  -- bytes followed -- four live desyncs in Crystal at 1E:$6BD4 (the player's
  -- house decoration signs), each reported as "opcode CC after
  -- describedecoration".  Both were already right in TERMINATORS_POLISHED,
  -- which is what gave the omission away.
  scripttalkafter = true, describedecoration = true,
}

-- MovementPointers (01:501D in Gold) -- the second bytecode language, used by
-- applymovement.  Names are the ROM's `Movement_*` symbols.
Gen2ScriptOps.MOVEMENTS = {
  [0x00] = "turn_head_down", "turn_head_up", "turn_head_left", "turn_head_right",
  "turn_step_down", "turn_step_up", "turn_step_left", "turn_step_right",
  "slow_step_down", "slow_step_up", "slow_step_left", "slow_step_right",
  "step_down", "step_up", "step_left", "step_right",
  "big_step_down", "big_step_up", "big_step_left", "big_step_right",
  "slow_slide_step_down", "slow_slide_step_up", "slow_slide_step_left",
  "slow_slide_step_right",
  "slide_step_down", "slide_step_up", "slide_step_left", "slide_step_right",
  "fast_slide_step_down", "fast_slide_step_up", "fast_slide_step_left",
  "fast_slide_step_right",
  "turn_away_down", "turn_away_up", "turn_away_left", "turn_away_right",
  "turn_in_down", "turn_in_up", "turn_in_left", "turn_in_right",
  "turn_waterfall_down", "turn_waterfall_up", "turn_waterfall_left",
  "turn_waterfall_right",
  "slow_jump_step_down", "slow_jump_step_up", "slow_jump_step_left",
  "slow_jump_step_right",
  "jump_step_down", "jump_step_up", "jump_step_left", "jump_step_right",
  "fast_jump_step_down", "fast_jump_step_up", "fast_jump_step_left",
  "fast_jump_step_right",
  "remove_sliding", "set_sliding", "remove_fixed_facing", "fix_facing",
  "show_object", "hide_object",
  "step_sleep_1", "step_sleep_2", "step_sleep_3", "step_sleep_4",
  "step_sleep_5", "step_sleep_6", "step_sleep_7", "step_sleep_8",
  "step_sleep", "step_end", "step_wait_end", "remove_object", "step_loop",
  "step_stop", "teleport_from", "teleport_to", "skyfall", "step_dig",
  "step_bump", "fish_got_bite", "fish_cast_rod", "hide_emote", "show_emote",
  "step_shake", "tree_shake", "rock_smash", "return_dig",
}

-- POLISHED CRYSTAL'S MOVEMENT LANGUAGE RUNS FIFTEEN OPCODES FURTHER.
--
-- Gold and Crystal end at $58 return_dig; polished's own
-- DoMovementFunction.MovementPointers (01:$53B4) carries on to $67, adding
-- running, fast and stairs steps.  Read through the short table an unknown
-- opcode breaks the decode loop immediately, so a movement list that OPENS
-- with one of them decoded to nothing at all: 54 of 458 polished movement
-- lists came out empty, and an empty list makes applymovement a silent no-op.
-- SSAquaCaptainsCabinWarpsToGrandpasCabinMovement (1F:$6916) is exactly that
-- -- `run_step_right, run_step_up x6` -- which is the walk that carries the
-- player out of the captain's cabin during the granddaughter cutscene.
Gen2ScriptOps.MOVEMENTS_POLISHED = (function()
  local t = {}
  for op, name in pairs(Gen2ScriptOps.MOVEMENTS) do t[op] = name end
  t[0x59] = "skyfall_top"
  t[0x5A] = "run_step_down"
  t[0x5B] = "run_step_up"
  t[0x5C] = "run_step_left"
  t[0x5D] = "run_step_right"
  t[0x5E] = "fast_step_down"
  t[0x5F] = "fast_step_up"
  t[0x60] = "fast_step_left"
  t[0x61] = "fast_step_right"
  t[0x62] = "stairs_step_down"
  t[0x63] = "stairs_step_up"
  t[0x64] = "stairs_step_left"
  t[0x65] = "stairs_step_right"
  t[0x66] = "exeggutor_shake"
  t[0x67] = "step_right"
  return t
end)()

function Gen2ScriptOps.movementsFor(version)
  if version == "polishedcrystal" then
    return Gen2ScriptOps.MOVEMENTS_POLISHED
  end
  return Gen2ScriptOps.MOVEMENTS
end

-- the movement commands that consume a following byte (macros/scripts/movement.asm).
-- rock_smash's length byte was the one that got read back as a step: the rock
-- smash movement decoded as `rock_smash` + `slow_step_left`, so every smashable
-- rock slid one cell left instead of rattling in place.
Gen2ScriptOps.MOVEMENT_ARGS = {
  step_sleep = 1, step_wait_end = 1, step_dig = 1,
  step_shake = 1, rock_smash = 1, return_dig = 1,
}

Gen2ScriptOps.MOVEMENT_TERMINATORS = {
  step_end = true, step_wait_end = true, remove_object = true,
  step_stop = true, step_loop = true,
}

-- direction suffix -> port facing name, for the runtime translator
Gen2ScriptOps.MOVEMENT_DIRS = {
  down = "down", up = "up", left = "left", right = "right",
}

return Gen2ScriptOps
