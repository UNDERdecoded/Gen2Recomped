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
  { "getcoins", "b" }, { "getnum", "bb" }, { "getmonname", "bb" },
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
--   $3F getnum        2 args -> 1 (bb -> b)
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
  { "closetext", "" }, { "cmdwitharrayargs", "b" }, { "farwritetext", "T" }, -- 48
  { "writetext", "t" }, { "repeattext", "" }, { "yesorno", "" }, -- 4B
  { "loadmenudata", "w" }, { "closewindow", "" }, { "jumptextfaceplayer", "t" }, -- 4E
  { "farjumptext", "T" }, { "jumptext", "t" }, { "waitbutton", "" }, -- 51
  { "buttonsound", "" }, { "pokepic", "b" }, { "closepokepic", "" }, -- 54
  { "eventvarop", "" }, { "verticalmenu", "" }, { "scrollingmenu", "b" }, -- 57
  { "randomwildmon", "" }, { "loadmemtrainer", "" }, { "loadwildmon", "bbbbb" }, -- 5A
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
  { "return_if_callback_else_end", "" }, { "copy", "wb" }, { "switch", "b" }, -- C3
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
  { "modifyeventvar", "" }, { "showtext", "t" }, { "closetextend", "" }, -- E7
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

function Gen2ScriptOps.terminatorsFor(version)
  if version == "prism" then return Gen2ScriptOps.TERMINATORS_PRISM end
  return Gen2ScriptOps.TERMINATORS
end

function Gen2ScriptOps.commandsFor(version)
  if version == "prism" then return Gen2ScriptOps.COMMANDS_PRISM end
  if version == "crystal" then return Gen2ScriptOps.COMMANDS_CRYSTAL end
  return Gen2ScriptOps.COMMANDS
end

Gen2ScriptOps.ARG_BYTES = {
  b = 1, w = 2, p = 2, t = 2, d = 2, M = 2, f = 3, T = 3, D = 3, m = 3,
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
