-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) event-script bytecode table: 840 opcodes, $000-$347.
--
-- Note the shape change from every generation above.  Gen 3 has 228 opcodes
-- in ONE byte; Gen 4 has 840 and reads its opcode as a HALFWORD, so a Gen 4
-- instruction is a u16 opcode followed by its operands and the smallest
-- possible instruction is two bytes, not one.  A decoder carried over from
-- Gen3ScriptOps and fed Gen 4 bytes desyncs on the first command.
--
-- WHERE THE WIDTHS COME FROM, and why that matters more than it sounds.
--
-- Gen3ScriptOps' own header records what it cost to get this wrong: the
-- Emerald table was reasoned out from handler call shapes, $E0 came out two
-- bytes short, and the result was not garbage -- it was the Sootopolis
-- cutscene playing twice with no warp home, because a two-byte slip lands on
-- a plausible opcode and keeps going.  It then says the thing that settled
-- it: pret's table, slot for slot, rather than shapes reasoned out here.
--
-- So this table is not reasoned out.  It is READ, mechanically, from
-- pokeplatinum, which is the same authority:
--
--   * the opcode numbers are the ORDER of the ScriptCommand() lines in
--     include/data/scripts/scrcmd.h -- position is the opcode, which is why
--     all 840 are listed here including the dummies.  Two of those lines are
--     spelled in mixed case (SCRCMD_GetExchangeServiceCornerItemAndCost at
--     $2A2 and ScrCmd_GETRANDOMBATTLEGROUNDTRAINERS at $2FB); a reader that
--     matches only [A-Z_] drops them and shifts every opcode after $2A2 down
--     by one, which is precisely the two-byte-slip failure one level up.
--
--   * the operand widths are the stream reads in each handler body, in
--     source order.  The five primitives each consume a fixed width --
--     ScriptContext_ReadByte 1, ReadHalfWord 2, ReadWord 4, and the two
--     inlines GetVar/GetVarPointer 2 apiece (both are ReadHalfWord
--     underneath, include/inlines.h:145) -- so the signature is the sequence
--     of calls, not an inference from what the handler then does with them.
--
-- THE TWO WAYS THAT COULD STILL BE WRONG, both measured rather than hoped:
--
--   1. A handler that reads inside an `if` has no fixed width at all.  Nine
--      do; they are marked "*" and listed in VARIABLE_LENGTH, NOT guessed.
--   2. A handler that delegates its read to a helper would hide operands
--      from a body-level reader.  Every function in pokeplatinum that takes
--      a ScriptContext* and reaches a stream read, transitively, was
--      collected and every handler body checked against that set: ZERO
--      handlers delegate.  Each operand is read where it can be seen.
--
-- And the corpus agrees -- with the caveat Gen3ScriptOps insists on.
-- Walking /fielddata/script/scr_seq.narc (1,124 script files) from all 4,079
-- entry points reaches a clean `end` 4,070 times with no unknown opcode; the
-- other 9 stop at one of the variable-length commands above.  That is
-- CORROBORATION, not proof, and Gen3ScriptOps explains exactly why: a
-- too-short operand lands on a plausible opcode and the walk sails on.  The
-- proof is the handler source; the corpus only shows nothing contradicts it.
--
-- Spec letters, the same ones Gen3ScriptOps uses:
--   b  one byte    w  two-byte little-endian    d  four-byte value
--   *  variable length; the handler decides.  See VARIABLE_LENGTH.

local Gen4ScriptOps = {}

-- Opcodes are a HALFWORD in Gen 4, so this is the width of the opcode itself
-- and an instruction is OPCODE_BYTES + the spec's total.
Gen4ScriptOps.OPCODE_BYTES = 2
Gen4ScriptOps.OPCODE_COUNT = 840

-- { name, spec }.  Dummies keep their slot and an empty spec: they are real
-- opcodes the cartridge simply never uses, and renumbering around them would
-- shift everything after.
Gen4ScriptOps.COMMANDS = {
  [0x000] = { "noop", "" },
  [0x001] = { "dummy", "" },
  [0x002] = { "end", "" },
  [0x003] = { "waittime", "ww" },
  [0x004] = { "unused_004", "bb" },
  [0x005] = { "unused_005", "bd" },
  [0x006] = { "unused_006", "bd" },
  [0x007] = { "unused_007", "db" },
  [0x008] = { "unused_008", "db" },
  [0x009] = { "unused_009", "bb" },
  [0x00A] = { "unused_00a", "dd" },
  [0x00B] = { "unused_00b", "bb" },
  [0x00C] = { "unused_00c", "bb" },
  [0x00D] = { "unused_00d", "bd" },
  [0x00E] = { "unused_00e", "db" },
  [0x00F] = { "unused_00f", "db" },
  [0x010] = { "unused_010", "dd" },
  [0x011] = { "comparevartovalue", "ww" },
  [0x012] = { "comparevartovar", "ww" },
  [0x013] = { "unused_013", "w" },
  [0x014] = { "callcommonscript", "w" },
  [0x015] = { "returncommonscript", "" },
  [0x016] = { "goto", "d" },
  [0x017] = { "unused_017", "bd" },
  [0x018] = { "unused_018", "bd" },
  [0x019] = { "unused_019", "bd" },
  [0x01A] = { "call", "d" },
  [0x01B] = { "return", "" },
  [0x01C] = { "gotoif", "bd" },
  [0x01D] = { "callif", "bd" },
  [0x01E] = { "setflag", "w" },
  [0x01F] = { "clearflag", "w" },
  [0x020] = { "checkflag", "w" },
  [0x021] = { "checkflagfromvar", "ww" },
  [0x022] = { "setflagfromvar", "w" },
  [0x023] = { "settrainerflag", "w" },
  [0x024] = { "cleartrainerflag", "w" },
  [0x025] = { "checktrainerflag", "w" },
  [0x026] = { "addvar", "ww" },
  [0x027] = { "subvar", "ww" },
  [0x028] = { "setvarfromvalue", "ww" },
  [0x029] = { "setvarfromvar", "ww" },
  [0x02A] = { "unused_02a", "ww" },
  [0x02B] = { "messageinstant", "b" },
  [0x02C] = { "message", "b" },
  [0x02D] = { "messagevar", "w" },
  [0x02E] = { "messagenoskip", "w" },
  [0x02F] = { "messagesynchronized", "b" },
  [0x030] = { "waitabpress", "" },
  [0x031] = { "waitbutton", "" },
  [0x032] = { "waitabpadpress", "" },
  [0x033] = { "openmessage", "" },
  [0x034] = { "closemessage", "" },
  [0x035] = { "closemessagewithouterasing", "" },
  [0x036] = { "drawsignpostinstantmessage", "bbww" },
  [0x037] = { "drawsignposttextbox", "bw" },
  [0x038] = { "setsignpostcommand", "b" },
  [0x039] = { "waitforsignpostdone", "" },
  [0x03A] = { "drawsignpostscrollingmessage", "bw" },
  [0x03B] = { "getsignpostinput", "w" },
  [0x03C] = { "showstartmenu", "" },
  [0x03D] = { "scrollbg3", "bbbbbb" },
  [0x03E] = { "showyesnomenu", "w" },
  [0x03F] = { "unused_03f", "" },
  [0x040] = { "initglobaltextmenu", "bbbbw" },
  [0x041] = { "initlocaltextmenu", "bbbbw" },
  [0x042] = { "addmenuentryimm", "bb" },
  [0x043] = { "showmenu", "" },
  [0x044] = { "initglobaltextlistmenu", "bbbbw" },
  [0x045] = { "initlocaltextlistmenu", "bbbbw" },
  [0x046] = { "addlistmenuentry", "www" },
  [0x047] = { "showlistmenu", "" },
  [0x048] = { "showmenumulticolumn", "b" },
  [0x049] = { "playse", "w" },
  [0x04A] = { "stopse", "w" },
  [0x04B] = { "waitse", "w" },
  [0x04C] = { "playcry", "ww" },
  [0x04D] = { "waitcry", "" },
  [0x04E] = { "playfanfare", "w" },
  [0x04F] = { "waitfanfare", "" },
  [0x050] = { "playmusic", "w" },
  [0x051] = { "stopmusic", "w" },
  [0x052] = { "playdefaultmusic", "" },
  [0x053] = { "setspecialbgm", "w" },
  [0x054] = { "fadeoutbgm", "ww" },
  [0x055] = { "fadeinbgm", "w" },
  [0x056] = { "setbgmplayerpaused", "bb" },
  [0x057] = { "setbgm", "w" },
  [0x058] = { "setbgmfixed", "b" },
  [0x059] = { "checkrecordedchatotcryisplayable", "w" },
  [0x05A] = { "tryrecordchatotcry", "w" },
  [0x05B] = { "stoprecordingchatotcry", "" },
  [0x05C] = { "storerecordedchatotcry", "" },
  [0x05D] = { "setsubscene63", "" },
  [0x05E] = { "applymovement", "wd" },
  [0x05F] = { "waitmovement", "" },
  [0x060] = { "lockall", "" },
  [0x061] = { "releaseall", "" },
  [0x062] = { "lockobject", "w" },
  [0x063] = { "releaseobject", "w" },
  [0x064] = { "addobject", "w" },
  [0x065] = { "removeobject", "w" },
  [0x066] = { "addfreecamera", "ww" },
  [0x067] = { "restorecamera", "" },
  [0x068] = { "faceplayer", "" },
  [0x069] = { "getplayermappos", "ww" },
  [0x06A] = { "unused_06a", "www" },
  [0x06B] = { "movecamera", "www" },
  [0x06C] = { "setobjectflagispersistent", "wb" },
  [0x06D] = { "setmovementtype", "ww" },
  [0x06E] = { "unused_06e", "" },
  [0x06F] = { "givemoney", "d" },
  [0x070] = { "removemoney", "d" },
  [0x071] = { "checkmoney", "wd" },
  [0x072] = { "showmoney", "ww" },
  [0x073] = { "hidemoney", "" },
  [0x074] = { "updatemoneydisplay", "" },
  [0x075] = { "showcoins", "ww" },
  [0x076] = { "hidecoins", "" },
  [0x077] = { "updatecoindisplay", "" },
  [0x078] = { "getcoinsamount", "w" },
  [0x079] = { "addcoins", "w" },
  [0x07A] = { "subtractcoinsfromvalue", "w" },
  [0x07B] = { "additem", "www" },
  [0x07C] = { "removeitem", "www" },
  [0x07D] = { "canfititem", "www" },
  [0x07E] = { "checkitem", "www" },
  [0x07F] = { "isitemtmhm", "ww" },
  [0x080] = { "getitempocket", "ww" },
  [0x081] = { "dummy081", "" },
  [0x082] = { "dummy082", "" },
  [0x083] = { "sendgoodtopc", "www" },
  [0x084] = { "dummy084", "www" },
  [0x085] = { "checkhasroomforgoodsinpc", "www" },
  [0x086] = { "dummy086", "www" },
  [0x087] = { "givetrap", "www" },
  [0x088] = { "dummy088", "www" },
  [0x089] = { "dummy089", "www" },
  [0x08A] = { "dummy08a", "www" },
  [0x08B] = { "dummy08b", "www" },
  [0x08C] = { "dummy08c", "www" },
  [0x08D] = { "dummy08d", "www" },
  [0x08E] = { "dummy08e", "www" },
  [0x08F] = { "givesphere", "www" },
  [0x090] = { "dummy090", "www" },
  [0x091] = { "dummy091", "www" },
  [0x092] = { "dummy092", "www" },
  [0x093] = { "countsealoccurence", "ww" },
  [0x094] = { "giveortakeseal", "ww" },
  [0x095] = { "getpartymonform", "ww" },
  [0x096] = { "givepokemon", "wwww" },
  [0x097] = { "giveegg", "ww" },
  [0x098] = { "resetpartymonmoveslot_unused", "www" },
  [0x099] = { "checkpartymonhasmove", "www" },
  [0x09A] = { "findpartyslotwithmove", "ww" },
  [0x09B] = { "getrematchtrainerid", "ww" },
  [0x09C] = { "unused_09c", "" },
  [0x09D] = { "unused_09d", "" },
  [0x09E] = { "unused_09e", "" },
  [0x09F] = { "unused_09f", "" },
  [0x0A0] = { "dummy0a0", "" },
  [0x0A1] = { "returntofield", "" },
  [0x0A2] = { "0a2", "" },
  [0x0A3] = { "0a3", "" },
  [0x0A4] = { "unused_0a4", "w" },
  [0x0A5] = { "0a5", "" },
  [0x0A6] = { "0a6", "www" },
  [0x0A7] = { "showdressupphoto", "ww" },
  [0x0A8] = { "0a8", "ww" },
  [0x0A9] = { "opensealcapsuleeditor", "" },
  [0x0AA] = { "openregionmap", "" },
  [0x0AB] = { "openpokemonstorage", "b" },
  [0x0AC] = { "0ac", "" },
  [0x0AD] = { "openunionroomtrainercase", "" },
  [0x0AE] = { "0ae", "" },
  [0x0AF] = { "0af", "" },
  [0x0B0] = { "cleargame", "" },
  [0x0B1] = { "openpchalloffamescreen", "" },
  [0x0B2] = { "trystartgtsapp", "ww" },
  [0x0B3] = { "0b3", "w" },
  [0x0B4] = { "startchoosestarterscene", "" },
  [0x0B5] = { "savechosenstarter", "" },
  [0x0B6] = { "startapproachingtrainertask", "w" },
  [0x0B7] = { "checkisapproachingtrainertaskdone", "ww" },
  [0x0B8] = { "getapproachingtrainertype", "w" },
  [0x0B9] = { "getapproachingtrainerid", "ww" },
  [0x0BA] = { "unused_0ba", "w" },
  [0x0BB] = { "openpokemonnamingscreen", "ww" },
  [0x0BC] = { "fadescreen", "wwww" },
  [0x0BD] = { "waitfadescreen", "" },
  [0x0BE] = { "warp", "wwwww" },
  [0x0BF] = { "userockclimb", "w" },
  [0x0C0] = { "usesurf", "w" },
  [0x0C1] = { "usewaterfall", "w" },
  [0x0C2] = { "usefly", "www" },
  [0x0C3] = { "0c3", "" },
  [0x0C4] = { "0c4", "" },
  [0x0C5] = { "playhmcutin", "w" },
  [0x0C6] = { "changeintocontestattire", "" },
  [0x0C7] = { "checkplayeronbike", "w" },
  [0x0C8] = { "setplayerbike", "b" },
  [0x0C9] = { "forcebicycling", "b" },
  [0x0CA] = { "getplayerstate", "w" },
  [0x0CB] = { "setplayerstate", "w" },
  [0x0CC] = { "changeplayerstate", "" },
  [0x0CD] = { "bufferplayername", "b" },
  [0x0CE] = { "bufferrivalname", "b" },
  [0x0CF] = { "buffercounterpartname", "b" },
  [0x0D0] = { "bufferpartymonspecies", "bw" },
  [0x0D1] = { "bufferitemname", "bw" },
  [0x0D2] = { "bufferpocketname", "bw" },
  [0x0D3] = { "buffertmhmmovename", "bw" },
  [0x0D4] = { "buffermovename", "bw" },
  [0x0D5] = { "buffernumber", "bw" },
  [0x0D6] = { "bufferpartymonnickname", "bw" },
  [0x0D7] = { "bufferpoketchappname", "bw" },
  [0x0D8] = { "buffertrainerclassname", "bw" },
  [0x0D9] = { "buffertrainerclassfromappearance", "b" },
  [0x0DA] = { "bufferspeciesnamefromvar", "bwwb" },
  [0x0DB] = { "bufferplayerstarterspeciesname", "b" },
  [0x0DC] = { "bufferrivalstarterspeciesname", "b" },
  [0x0DD] = { "bufferplayercounterpartstarterspeciesname", "b" },
  [0x0DE] = { "getplayerstarterspecies", "w" },
  [0x0DF] = { "bufferundergroundgoodsname", "bw" },
  [0x0E0] = { "bufferundergroundtrapname", "bw" },
  [0x0E1] = { "bufferundergrounditemname", "bw" },
  [0x0E2] = { "buffermapname", "bw" },
  [0x0E3] = { "getswarmmapandspecies", "ww" },
  [0x0E4] = { "gettrainerid", "w" },
  [0x0E5] = { "starttrainerbattle", "ww" },
  [0x0E6] = { "printtrainerdialogue", "ww" },
  [0x0E7] = { "gettrainermessagetypes", "www" },
  [0x0E8] = { "gettrainerrematchmessagetypes", "www" },
  [0x0E9] = { "checkistrainerdoublebattle", "w" },
  [0x0EA] = { "playtrainerencounterbgm", "w" },
  [0x0EB] = { "blackoutfrombattle", "" },
  [0x0EC] = { "checkwonbattle", "w" },
  [0x0ED] = { "checklostbattle", "w" },
  [0x0EE] = { "checkhastwoalivemons", "w" },
  [0x0EF] = { "startdummytrainerbattle", "" },
  [0x0F0] = { "settargettrainerdefeated", "" },
  [0x0F1] = { "gotoiftargettrainerdefeated", "d" },
  [0x0F2] = { "startbattleclient", "wwww" },
  [0x0F3] = { "startbattleserver", "wwww" },
  [0x0F4] = { "unused_0f4", "w" },
  [0x0F5] = { "unused_0f5", "w" },
  [0x0F6] = { "startlinkbattle", "" },
  [0x0F7] = { "unused_0f7", "" },
  [0x0F8] = { "startcontestcommsync", "w" },
  [0x0F9] = { "waitforcommsyncstate", "w" },
  [0x0FA] = { "newcontest", "wwww" },
  [0x0FB] = { "endcontest", "w" },
  [0x0FC] = { "bufferjudgename", "ww" },
  [0x0FD] = { "buffercontestanttrainername", "ww" },
  [0x0FE] = { "buffercontestantmonname", "ww" },
  [0x0FF] = { "buffercontestregistrationentrynumber", "ww" },
  [0x100] = { "waitforlinkcontestsetup", "" },
  [0x101] = { "runcontestapplication", "" },
  [0x102] = { "buffercontestrank", "w" },
  [0x103] = { "buffercontesttype", "w" },
  [0x104] = { "bufferwinningcontestanttrainername", "w" },
  [0x105] = { "settrue", "w" },
  [0x106] = { "bufferwinningcontestantmonname", "w" },
  [0x107] = { "getplayercontestplacement", "w" },
  [0x108] = { "getwinningcontestantentrynum", "w" },
  [0x109] = { "getcontestregistrationentrynum", "w" },
  [0x10A] = { "getcontestantobjeventgfx", "ww" },
  [0x10B] = { "getcontestantmoncontestfame", "ww" },
  [0x10C] = { "getcontestmode", "w" },
  [0x10D] = { "checkplayermonhasribbon", "w" },
  [0x10E] = { "setribbonname", "w" },
  [0x10F] = { "getfirsttimevictoryaccessory", "w" },
  [0x110] = { "getcontestinfo", "wwww" },
  [0x111] = { "startcontestcameraflashtask", "w" },
  [0x112] = { "waitforcontestcameraflashtask", "" },
  [0x113] = { "stophblank", "" },
  [0x114] = { "starthblank", "" },
  [0x115] = { "getshouldskipawardceremony", "w" },
  [0x116] = { "showlinkcontestrecords", "" },
  [0x117] = { "lockautoscrollforlinkcontests", "" },
  [0x118] = { "locktextspeed", "" },
  [0x119] = { "checkpartypokerus", "w" },
  [0x11A] = { "getpartymongender_unused", "ww" },
  [0x11B] = { "setspeciallocation", "wwwww" },
  [0x11C] = { "getfloorsabove", "w" },
  [0x11D] = { "showcurrentfloor", "bbww" },
  [0x11E] = { "getlocaldexseencount", "w" },
  [0x11F] = { "getlocaldexcaughtcount_unused", "w" },
  [0x120] = { "getnationaldexseencount", "w" },
  [0x121] = { "getnationaldexcaughtcount", "w" },
  [0x122] = { "unused_122", "" },
  [0x123] = { "loadpokedexrating", "bw" },
  [0x124] = { "startwildbattle", "ww" },
  [0x125] = { "startfirstbattle", "w" },
  [0x126] = { "startcatchingtutorial", "" },
  [0x127] = { "slatherhoneytree", "" },
  [0x128] = { "gethoneytreestatus", "w" },
  [0x129] = { "starthoneytreebattle", "" },
  [0x12A] = { "stophoneytreeshaking", "" },
  [0x12B] = { "startsignatureapp", "" },
  [0x12C] = { "checksavetype", "w" },
  [0x12D] = { "trysavegame", "w" },
  [0x12E] = { "dressupphotohasdata", "ww" },
  [0x12F] = { "contestphotohasdata", "ww" },
  [0x130] = { "setdressupphototitle", "w" },
  [0x131] = { "enablepoketch", "" },
  [0x132] = { "checkpoketchenabled", "w" },
  [0x133] = { "registerpoketchapp", "w" },
  [0x134] = { "checkpoketchappregistered", "ww" },
  [0x135] = { "135", "w" },
  [0x136] = { "clearreceivedtempdataallplayers", "" },
  [0x137] = { "unused_137", "w" },
  [0x138] = { "getunionroomtealamessage", "w" },
  [0x139] = { "139", "w" },
  [0x13A] = { "13a", "" },
  [0x13B] = { "13b", "" },
  [0x13C] = { "dounionroomgreeting", "w" },
  [0x13D] = { "initcommfieldcmd", "" },
  [0x13E] = { "13e", "" },
  [0x13F] = { "getunionroommessage", "ww" },
  [0x140] = { "140", "w" },
  [0x141] = { "141", "w" },
  [0x142] = { "142", "" },
  [0x143] = { "143", "ww" },
  [0x144] = { "144", "w" },
  [0x145] = { "145", "w" },
  [0x146] = { "146", "ww" },
  [0x147] = { "pokemartcommon", "w" },
  [0x148] = { "pokemartspecialties", "w" },
  [0x149] = { "pokemartdecor", "w" },
  [0x14A] = { "pokemartseal", "w" },
  [0x14B] = { "blackoutfrombattle2", "" },
  [0x14C] = { "setblackoutwarpid", "w" },
  [0x14D] = { "getplayergender", "w" },
  [0x14E] = { "healparty", "" },
  [0x14F] = { "dummy14f", "" },
  [0x150] = { "endcommunication", "" },
  [0x151] = { "fieldcommenterbattleroom", "" },
  [0x152] = { "setcommplayerdir", "w" },
  [0x153] = { "153", "" },
  [0x154] = { "loadtrainerappearances", "" },
  [0x155] = { "gettrainerinfotrainerclass", "ww" },
  [0x156] = { "settrainerinfoappearance", "w" },
  [0x157] = { "checkpokedexacquired", "w" },
  [0x158] = { "givepokedex", "" },
  [0x159] = { "checkrunningshoesacquired", "w" },
  [0x15A] = { "giverunningshoes", "" },
  [0x15B] = { "checkbadgeacquired", "ww" },
  [0x15C] = { "givebadge", "w" },
  [0x15D] = { "countbadgesacquired", "w" },
  [0x15E] = { "checkbagacquired", "w" },
  [0x15F] = { "givebag", "" },
  [0x160] = { "checkhaspartner", "w" },
  [0x161] = { "sethaspartner", "" },
  [0x162] = { "clearhaspartner", "" },
  [0x163] = { "checkstepflag", "w" },
  [0x164] = { "setstepflag", "" },
  [0x165] = { "clearstepflag", "" },
  [0x166] = { "checkgamecompleted", "w" },
  [0x167] = { "setgamecompleted", "" },
  [0x168] = { "loaddooranimation", "wwwwb" },
  [0x169] = { "waitforanimation", "b" },
  [0x16A] = { "unloadanimation", "b" },
  [0x16B] = { "playdooropenanimation", "b" },
  [0x16C] = { "playdoorcloseanimation", "b" },
  [0x16D] = { "bufferdaycaremonnicknames", "" },
  [0x16E] = { "getdaycarestate", "w" },
  [0x16F] = { "initpersistedmapfeaturesforpastoriagym", "" },
  [0x170] = { "presspastoriagymbutton", "" },
  [0x171] = { "initpersistedmapfeaturesforhearthomegym", "" },
  [0x172] = { "movehearthomegymdplift", "" },
  [0x173] = { "initpersistedmapfeaturesforcanalavegym", "" },
  [0x174] = { "initpersistedmapfeaturesforveilstonegym", "" },
  [0x175] = { "initpersistedmapfeaturesforsunyshoregym", "b" },
  [0x176] = { "presssunyshoregymbutton", "b" },
  [0x177] = { "getpartycount", "w" },
  [0x178] = { "openbag", "b" },
  [0x179] = { "getselecteditem", "w" },
  [0x17A] = { "checkpockethasitems", "ww" },
  [0x17B] = { "bufferberryname", "bww" },
  [0x17C] = { "buffernaturename", "bw" },
  [0x17D] = { "getberrygrowthstage", "w" },
  [0x17E] = { "getberryitemid", "w" },
  [0x17F] = { "getberrymulchtype", "w" },
  [0x180] = { "getberrymoisture", "w" },
  [0x181] = { "getberryyield", "w" },
  [0x182] = { "setberrymulch", "w" },
  [0x183] = { "plantberry", "w" },
  [0x184] = { "setberrywateringstate", "w" },
  [0x185] = { "harvestberry", "" },
  [0x186] = { "setobjecteventpos", "www" },
  [0x187] = { "setposition", "wwwww" },
  [0x188] = { "setobjecteventmovementtype", "ww" },
  [0x189] = { "setobjecteventdir", "ww" },
  [0x18A] = { "setwarpeventpos", "www" },
  [0x18B] = { "setbgeventpos", "www" },
  [0x18C] = { "18c", "ww" },
  [0x18D] = { "showsavingicon", "" },
  [0x18E] = { "hidesavingicon", "" },
  [0x18F] = { "storesaveresult", "w" },
  [0x190] = { "waitabpresstime", "w" },
  [0x191] = { "selectmovetutorpokemon", "" },
  [0x192] = { "openpartymenuforunionroombattle", "" },
  [0x193] = { "getselectedpartyslot", "w" },
  [0x194] = { "openpartymenuforcontest", "wwww" },
  [0x195] = { "getcontestpartymenuresult", "ww" },
  [0x196] = { "setmonsummary", "w" },
  [0x197] = { "getmonpartyslot", "w" },
  [0x198] = { "getpartymonspecies", "ww" },
  [0x199] = { "checkispartymonoutsider", "ww" },
  [0x19A] = { "countpartynoneggs", "w" },
  [0x19B] = { "countalivemonsexcept", "ww" },
  [0x19C] = { "countalivemonsandboxmons", "w" },
  [0x19D] = { "countpartyeggs", "w" },
  [0x19E] = { "dummy19e", "ww" },
  [0x19F] = { "undergroundnpcmessage", "w" },
  [0x1A0] = { "closeundergroundnpcmessage", "" },
  [0x1A1] = { "buffertreasurenameforundergroundvendor_unused", "bw" },
  [0x1A2] = { "buffertrapnameforundergroundvendor_unused", "bw" },
  [0x1A3] = { "removemoney2", "w" },
  [0x1A4] = { "movemontopartyfromdaycareslot", "ww" },
  [0x1A5] = { "dummy1a5", "w" },
  [0x1A6] = { "dummy1a6", "" },
  [0x1A7] = { "dummy1a7", "" },
  [0x1A8] = { "resetdaycarepersonalityandstepcounter", "" },
  [0x1A9] = { "giveeggfromdaycare", "" },
  [0x1AA] = { "bufferdaycarepricebyslot", "ww" },
  [0x1AB] = { "checkmoney2", "ww" },
  [0x1AC] = { "hatchegg", "" },
  [0x1AD] = { "dummy1ad", "w" },
  [0x1AE] = { "bufferdaycaregainedlevelsbyslot", "ww" },
  [0x1AF] = { "bufferpartymonnicknamereturnspecies", "www" },
  [0x1B0] = { "storepartymonintodaycare", "w" },
  [0x1B1] = { "showobject", "w" },
  [0x1B2] = { "hideobject", "w" },
  [0x1B3] = { "1b3", "" },
  [0x1B4] = { "countmailinmailbox", "w" },
  [0x1B5] = { "startrankingsmachine", "w" },
  [0x1B6] = { "gettimeofday", "w" },
  [0x1B7] = { "getrandom", "ww" },
  [0x1B8] = { "getrandom2", "ww" },
  [0x1B9] = { "getpartymonfriendship", "ww" },
  [0x1BA] = { "increasepartymonfriendship", "ww" },
  [0x1BB] = { "decreasepartymonfriendship_unused", "ww" },
  [0x1BC] = { "bufferdaycarenicknamelevelgender", "wwww" },
  [0x1BD] = { "getplayerdir", "w" },
  [0x1BE] = { "getdaycarecompatibilitylevel", "w" },
  [0x1BF] = { "checkdaycarehasegg", "w" },
  [0x1C0] = { "checkpartyhasspecies", "ww" },
  [0x1C1] = { "calcsizecontestresult", "ww" },
  [0x1C2] = { "updatesizecontestrecord", "w" },
  [0x1C3] = { "bufferpartypokemonsize", "www" },
  [0x1C4] = { "buffersizecontestrecord", "www" },
  [0x1C5] = { "initsizecontestrecord", "" },
  [0x1C6] = { "selectpartymonmove", "w" },
  [0x1C7] = { "getselectedpartymonmove", "w" },
  [0x1C8] = { "getpartymonmovecount", "ww" },
  [0x1C9] = { "clearpartymonmoveslot", "ww" },
  [0x1CA] = { "getpartymonmove", "www" },
  [0x1CB] = { "bufferpartymovename", "bww" },
  [0x1CC] = { "givejournal", "" },
  [0x1CD] = { "createjournalevent", "wwwww" },
  [0x1CE] = { "unused_1ce", "" },
  [0x1CF] = { "dostrengthfunc", "*" },  -- variable; see VARIABLE_LENGTH
  [0x1D0] = { "doflashfunc", "*" },  -- variable; see VARIABLE_LENGTH
  [0x1D1] = { "dodefogfunc", "*" },  -- variable; see VARIABLE_LENGTH
  [0x1D2] = { "addaccessory", "ww" },
  [0x1D3] = { "canfitaccessory", "www" },
  [0x1D4] = { "unused_1d4", "www" },
  [0x1D5] = { "addcontestbackdrop", "w" },
  [0x1D6] = { "checkbackdrop", "ww" },
  [0x1D7] = { "openpoffincooking", "w" },
  [0x1D8] = { "checkcancookpoffin", "w" },
  [0x1D9] = { "openbattletowerrecordsapp", "ww" },
  [0x1DA] = { "setbattletowernull", "" },
  [0x1DB] = { "initbattletower", "ww" },
  [0x1DC] = { "freebattletower", "" },
  [0x1DD] = { "callbattletowerfunction", "www" },
  [0x1DE] = { "getbattletowerpartnerspeciesandmove", "wwww" },
  [0x1DF] = { "1df", "w" },
  [0x1E0] = { "1e0", "w" },
  [0x1E1] = { "1e1", "www" },
  [0x1E2] = { "1e2", "ww" },
  [0x1E3] = { "1e3", "ww" },
  [0x1E4] = { "1e4", "w" },
  [0x1E5] = { "incrementgamerecord", "w" },
  [0x1E6] = { "unused_1e6", "www" },
  [0x1E7] = { "unused_1e7", "wwwb" },
  [0x1E8] = { "checklocaldexcompleted", "w" },
  [0x1E9] = { "checknationaldexcompleted", "w" },
  [0x1EA] = { "showdiplomasinnoh", "" },
  [0x1EB] = { "showdiplomanationaldex", "" },
  [0x1EC] = { "addtrophygardenmon", "" },
  [0x1ED] = { "gettrophygardenslot1species", "w" },
  [0x1EE] = { "getpartymonhelditem_unused", "ww" },
  [0x1EF] = { "unused_1ef", "w" },
  [0x1F0] = { "deletepartymonhelditem_unused", "w" },
  [0x1F1] = { "getfossilcount", "w" },
  [0x1F2] = { "dummy_1f2", "" },
  [0x1F3] = { "dummy_1f3", "" },
  [0x1F4] = { "getspeciesfromfossil", "ww" },
  [0x1F5] = { "findfossilatthreshold", "www" },
  [0x1F6] = { "countpartymonsbelowlevelthreshold", "ww" },
  [0x1F7] = { "survivepoison", "ww" },
  [0x1F8] = { "waitfortransition", "" },
  [0x1F9] = { "dummy1f9", "w" },
  [0x1FA] = { "messagefrombankinstant", "ww" },
  [0x1FB] = { "messagefrombank", "ww" },
  [0x1FC] = { "sentenceinstant", "wwww" },
  [0x1FD] = { "sentence", "wwww" },
  [0x1FE] = { "printbattletowerintromessage", "b" },
  [0x1FF] = { "messageseenbanlistspecies", "bwwb" },
  [0x200] = { "getpreviousmapid", "w" },
  [0x201] = { "getcurrentmapid", "w" },
  [0x202] = { "startendsafarigame", "b" },
  [0x203] = { "warptocolosseum", "wwwww" },
  [0x204] = { "204", "" },
  [0x205] = { "205", "" },
  [0x206] = { "startgreatmarshlookout", "" },
  [0x207] = { "getcurnetid", "w" },
  [0x208] = { "drawpokemonpreview", "ww" },
  [0x209] = { "removepokemonpreview", "" },
  [0x20A] = { "startvsseeker", "w" },
  [0x20B] = { "setmovecodeforfacingdirection", "" },
  [0x20C] = { "messagefromtrainertype", "" },
  [0x20D] = { "20d", "bw" },
  [0x20E] = { "initgreatmarshtram", "" },
  [0x20F] = { "movegreatmarshtram", "ww" },
  [0x210] = { "checkgreatmarshtramlocation", "ww" },
  [0x211] = { "setplayerheightcalculationenabled", "b" },
  [0x212] = { "getpartymonnature", "ww" },
  [0x213] = { "findpartyslotwithnature", "ww" },
  [0x214] = { "getspiritombcounter", "w" },
  [0x215] = { "clearamitysquarestepcount", "" },
  [0x216] = { "getamitysquarestepcount", "w" },
  [0x217] = { "calcamitysquarefoundaccessory", "ww" },
  [0x218] = { "getrandomseenspecies", "w" },
  [0x219] = { "setnewspressdeadline", "w" },
  [0x21A] = { "getnewspressdeadline", "w" },
  [0x21B] = { "enableswarms", "" },
  [0x21C] = { "activateroamingpokemon", "b" },
  [0x21D] = { "dogroupconnectionaction", "*" },  -- variable; see VARIABLE_LENGTH
  [0x21E] = { "dummy21e", "" },
  [0x21F] = { "checkhaslearnableremindermoves", "ww" },
  [0x220] = { "220", "" },
  [0x221] = { "openmoveremindermenu", "w" },
  [0x222] = { "222", "" },
  [0x223] = { "checklearnedremindermove", "w" },
  [0x224] = { "openmovetutormenu", "ww" },
  [0x225] = { "checklearnedtutormove", "w" },
  [0x226] = { "initnpctrade", "b" },
  [0x227] = { "getnpctradespecies", "w" },
  [0x228] = { "getnpctraderequestedspecies", "w" },
  [0x229] = { "startnpctrade", "w" },
  [0x22A] = { "finishnpctrade", "" },
  [0x22B] = { "turnonpokedexlanguagedetection", "" },
  [0x22C] = { "turnonpokedexformdetection", "" },
  [0x22D] = { "getsetnationaldexenabled", "bw" },
  [0x22E] = { "countpartymonribbons_unused", "ww" },
  [0x22F] = { "countpartyribbons", "w" },
  [0x230] = { "getpartymonribbon", "www" },
  [0x231] = { "setpartymonribbon", "ww" },
  [0x232] = { "bufferribbonname", "bw" },
  [0x233] = { "getpartymonevtotal", "ww" },
  [0x234] = { "getdayofweek", "w" },
  [0x235] = { "calltvbroadcast", "*" },  -- variable; see VARIABLE_LENGTH
  [0x236] = { "savetvsegmenthiddenitem", "w" },
  [0x237] = { "calltvinterview", "*" },  -- variable; see VARIABLE_LENGTH
  [0x238] = { "checktvintervieweligible", "ww" },
  [0x239] = { "openbattleregulationmenu", "w" },
  [0x23A] = { "getpartymonfootprinttype", "www" },
  [0x23B] = { "playpokecenterhealinganimation", "w" },
  [0x23C] = { "playelevatoranimation", "ww" },
  [0x23D] = { "playboatcutscene", "bbwww" },
  [0x23E] = { "mysterygiftgive", "*" },  -- variable; see VARIABLE_LENGTH
  [0x23F] = { "dummy23f", "" },
  [0x240] = { "dummy240", "" },
  [0x241] = { "dummy241", "" },
  [0x242] = { "dummy242", "" },
  [0x243] = { "choosecustommessageword", "www" },
  [0x244] = { "choosetwocustommessagewords", "wwww" },
  [0x245] = { "buffercustommessageword", "ww" },
  [0x246] = { "getgameversion", "w" },
  [0x247] = { "getfirstnonegginparty", "w" },
  [0x248] = { "getpartymontype", "www" },
  [0x249] = { "getwallpaperfromcustommessagewords", "wwwww" },
  [0x24A] = { "getcapturedflagcount", "w" },
  [0x24B] = { "loadpcanimation", "b" },
  [0x24C] = { "playpcbootupanimation", "b" },
  [0x24D] = { "playpcshutdownanimation", "b" },
  [0x24E] = { "getjubilifelotterytrainerid", "w" },
  [0x24F] = { "checkforjubilifelotterywinner", "wwww" },
  [0x250] = { "randomizejubilifelottery", "" },
  [0x251] = { "buffermonnicknamefrompc", "bw" },
  [0x252] = { "getpcboxesfreeslotcount", "w" },
  [0x253] = { "setclearincatchingshowflag", "w" },
  [0x254] = { "checkhasenoughmonforcatchingshow", "w" },
  [0x255] = { "movecatchingshowmonstopcboxes", "" },
  [0x256] = { "calccatchingshowpoints", "ww" },
  [0x257] = { "showaccessoryshop", "" },
  [0x258] = { "258", "" },
  [0x259] = { "259", "" },
  [0x25A] = { "playhalloffamehealinganimation", "w" },
  [0x25B] = { "initpersistedmapfeaturesforplatformlift", "" },
  [0x25C] = { "triggerplatformlift", "" },
  [0x25D] = { "checkplatformliftnotusedwhenenteredmap", "w" },
  [0x25E] = { "initlakeguardiancontainmentunits", "" },
  [0x25F] = { "deactivatelakeguardiancontainmentunits", "" },
  [0x260] = { "incrementtrainerscore2", "w" },
  [0x261] = { "bufferaccessoryname", "bw" },
  [0x262] = { "checkpartyhasspecies2", "ww" },
  [0x263] = { "changedeoxysform", "w" },
  [0x264] = { "checkpartycombeegendercount", "w" },
  [0x265] = { "hidepoketch", "" },
  [0x266] = { "showpoketch", "" },
  [0x267] = { "267", "w" },
  [0x268] = { "gethour", "w" },
  [0x269] = { "shakeobject", "wwwww" },
  [0x26A] = { "flickerobject", "www" },
  [0x26B] = { "checkhasalllegendarytitansinparty", "w" },
  [0x26C] = { "trygetrandommassagegirlaccessory", "w" },
  [0x26D] = { "messageunown", "w" },
  [0x26E] = { "getgbacartridgeversion", "w" },
  [0x26F] = { "clearspiritombcounter", "" },
  [0x270] = { "sethiddenlocation", "wb" },
  [0x271] = { "openshaymintabletnamingscreen", "w" },
  [0x272] = { "buffertabletname", "b" },
  [0x273] = { "buffercontestbackdropname", "bw" },
  [0x274] = { "hascoinsfromvalue", "wd" },
  [0x275] = { "checkbonusroundstreak", "w" },
  [0x276] = { "checkcanaddcoins", "ww" },
  [0x277] = { "getdailyrandomlevel", "w" },
  [0x278] = { "getpartymonlevel", "ww" },
  [0x279] = { "removeaccessory", "ww" },
  [0x27A] = { "usevistalighthousebinoculars", "" },
  [0x27B] = { "initdailyrandomlevel", "" },
  [0x27C] = { "27c", "*" },  -- variable; see VARIABLE_LENGTH
  [0x27D] = { "trybufferandunlockrandomtoughword", "ww" },
  [0x27E] = { "checkisdepartmentstoreregular", "w" },
  [0x27F] = { "checkalltoughwordsunlocked", "w" },
  [0x280] = { "buffervarpaddingdigits", "bwbb" },
  [0x281] = { "getpartymonconteststat", "www" },
  [0x282] = { "checkistodayplayerbirthday", "w" },
  [0x283] = { "setinitialvolumeforsequence", "ww" },
  [0x284] = { "getunownformsseencount", "w" },
  [0x285] = { "initturnbackcave", "ww" },
  [0x286] = { "getundergrounditemsgivenaway", "w" },
  [0x287] = { "getundergroundfossilsunearthed", "w" },
  [0x288] = { "getundergroundtrapsset", "w" },
  [0x289] = { "givepoffin", "wwwwwww" },  -- destVar, five flavors, smoothness (ScrCmd_GivePoffin)
  [0x28A] = { "checkhasemptypoffincaseslot", "w" },
  [0x28B] = { "checkdistributionevent", "bw" },
  [0x28C] = { "drawpokemonpreviewfrompartyslot", "w" },
  [0x28D] = { "setpokemonpreviewanim", "" },
  [0x28E] = { "waitpokemonpreviewanim", "w" },
  [0x28F] = { "getleaguevictories", "w" },
  [0x290] = { "openpartymenufordaycare", "w" },
  [0x291] = { "getdaycarepartymenuresult", "ww" },
  [0x292] = { "checkshouldshowghost", "bw" },
  [0x293] = { "getundergroundtalkcounter", "w" },
  [0x294] = { "showbattlepoints", "bb" },
  [0x295] = { "hidebattlepoints", "" },
  [0x296] = { "updatebpdisplay", "" },
  [0x297] = { "getbattlepoints", "w" },
  [0x298] = { "givebattlepoints", "w" },
  [0x299] = { "removebattlepoints", "w" },
  [0x29A] = { "checkbattlepoints", "ww" },
  [0x29B] = { "getexchangeservicecorneritemandcost", "wwww" },
  [0x29C] = { "calculatetrainerinfoappearance", "ww" },
  [0x29D] = { "addmenuentry", "ww" },
  [0x29E] = { "startdestroyobstacleanimation", "ww" },
  [0x29F] = { "29f", "w" },
  [0x2A0] = { "starttagbattle", "www" },
  [0x2A1] = { "unused_2a1", "www" },
  [0x2A2] = { "trysetunusedcollectedorbflag", "w" },
  [0x2A3] = { "checkhaswifilistvalidlogin", "w" },
  [0x2A4] = { "getwiflistvalidfriendscount", "w" },
  [0x2A5] = { "openpartymenufortrade", "" },
  [0x2A6] = { "getgamecornerprizedata", "www" },
  [0x2A7] = { "checkitemisplate", "ww" },
  [0x2A8] = { "subtractcoinsfromvar", "w" },
  [0x2A9] = { "hascoinsfromvar", "ww" },
  [0x2AA] = { "checkismysterygiftphrase", "wwwww" },
  [0x2AB] = { "countuniquesealsinsealcase", "w" },
  [0x2AC] = { "unlockmysterygift", "" },
  [0x2AD] = { "getmovementtype", "ww" },
  [0x2AE] = { "issequenceplaying", "ww" },
  [0x2AF] = { "gettrainercaseplayermessage", "w" },
  [0x2B0] = { "2b0", "" },
  [0x2B1] = { "destroynetworkicon", "" },
  [0x2B2] = { "2b2", "" },
  [0x2B3] = { "bufferballsealname", "bw" },
  [0x2B4] = { "locklasttalked", "" },
  [0x2B5] = { "2b5", "www" },
  [0x2B6] = { "2b6", "wb" },
  [0x2B7] = { "checkpartyhasbadegg", "w" },
  [0x2B8] = { "2b8", "w" },
  [0x2B9] = { "showunionroommenu", "" },
  [0x2BA] = { "2ba", "w" },
  [0x2BB] = { "2bb", "" },
  [0x2BC] = { "checkdidnotcapture", "w" },
  [0x2BD] = { "startlegendarybattle", "ww" },
  [0x2BE] = { "gettrainercardlevel", "w" },
  [0x2BF] = { "setcyclingbgm", "" },
  [0x2C0] = { "messageautoscroll", "w" },
  [0x2C1] = { "opensaveinfo", "" },
  [0x2C2] = { "closesaveinfo", "" },
  [0x2C3] = { "unused_2c3", "b" },
  [0x2C4] = { "launchbattlefrontierscene", "b" },
  [0x2C5] = { "deleteactivebattlefactorystreak", "ww" },
  [0x2C6] = { "2c6", "" },
  [0x2C7] = { "iscommgamecodeplatinum", "w" },
  [0x2C8] = { "openfrontierrecordsapp", "www" },
  [0x2C9] = { "initpersistedmapfeaturesforeternagym", "" },
  [0x2CA] = { "advanceeternagymclock", "" },
  [0x2CB] = { "countrepeatedspeciesinparty", "ww" },
  [0x2CC] = { "callbattlehalllobbyfunction", "www" },
  [0x2CD] = { "2cd", "" },
  [0x2CE] = { "unused_2ce", "" },
  [0x2CF] = { "checkbattlehallpartnerusesdifferentspecies", "ww" },
  [0x2D0] = { "getbattlehallselectedslots", "ww" },
  [0x2D1] = { "deleteactivebattlehallstreak", "w" },
  [0x2D2] = { "callbattlecastlelobbyfunction", "www" },
  [0x2D3] = { "checkbattlecastlepartnerusesdifferentspecies", "www" },
  [0x2D4] = { "getbattlecastleselectedslots", "www" },
  [0x2D5] = { "deleteactivebattlecastlestreak", "w" },
  [0x2D6] = { "saveextradata", "" },
  [0x2D7] = { "checkismiscsaveinit", "w" },
  [0x2D8] = { "pokemartfrontier", "b" },
  [0x2D9] = { "callbattlearcadelobbyfunction", "www" },
  [0x2DA] = { "checkbattlearcadepartnerusesdifferentspecies", "www" },
  [0x2DB] = { "getbattlearcadeselectedslots", "www" },
  [0x2DC] = { "deleteactivebattlearcadestreak", "w" },
  [0x2DD] = { "findpartyslotwithspecies", "ww" },
  [0x2DE] = { "showbattlehallrecordmonselectionmenu", "wwwww" },
  [0x2DF] = { "calcamitysquareberryandaccessorymanoptionid", "w" },
  [0x2E0] = { "checkamitysquaremangiftisaccessory", "ww" },
  [0x2E1] = { "getamitysquareberryoraccessoryidfromman", "ww" },
  [0x2E2] = { "openscratchoffcardsapp", "" },
  [0x2E3] = { "freescratchoffcardsargs", "" },
  [0x2E4] = { "getscratchoffcardswonitem", "www" },
  [0x2E5] = { "checkhaslearnabletutormoves", "www" },
  [0x2E6] = { "showmovetutormoveselectionmenu", "www" },
  [0x2E7] = { "opensummaryscreenteachmove", "ww" },
  [0x2E8] = { "getsummaryselectedmoveslot", "w" },
  [0x2E9] = { "resetmoveslot", "www" },
  [0x2EA] = { "checkcanaffordmove", "ww" },
  [0x2EB] = { "payshardcost", "w" },
  [0x2EC] = { "showshardcost", "bbww" },
  [0x2ED] = { "closeshardcostwindow", "" },
  [0x2EE] = { "judgestats", "wwww" },
  [0x2EF] = { "bufferstatname", "bw" },
  [0x2F0] = { "initpersistedmapfeaturesforvilla", "" },
  [0x2F1] = { "2f1", "ww" },
  [0x2F2] = { "initpersistedmapfeaturesfordistortionworld", "" },
  [0x2F3] = { "buffertrainername", "bw" },
  [0x2F4] = { "getrandombattlegroundtrainers", "wwww" },
  [0x2F5] = { "buffervaluepaddingdigits", "bdbb" },
  [0x2F6] = { "2f6", "www" },
  [0x2F7] = { "2f7", "w" },
  [0x2F8] = { "setsceneplaybgmmusicbox", "" },
  [0x2F9] = { "setfieldscene", "w" },
  [0x2FA] = { "getcurrentbgm", "w" },
  [0x2FB] = { "2fb", "" },
  [0x2FC] = { "checkabpress", "w" },
  [0x2FD] = { "buffertypename", "bw" },
  [0x2FE] = { "getitemquantity", "ww" },
  [0x2FF] = { "calchiddenpowertype", "ww" },
  [0x300] = { "setfavoritemon", "" },
  [0x301] = { "getfavoritemon", "www" },
  [0x302] = { "getrotomformsinsave", "wwwww" },
  [0x303] = { "getpartyrotomcountandfirst", "ww" },
  [0x304] = { "setrotomform", "wwww" },
  [0x305] = { "getpartymonform2", "ww" },
  [0x306] = { "showlistmenuremembercursor", "ww" },
  [0x307] = { "getemptypoffincaseslotcount", "w" },
  [0x308] = { "addcameraoverrideobject", "ww" },
  [0x309] = { "removecameraoverrideobject", "" },
  [0x30A] = { "incrementtrainerscore", "w" },
  [0x30B] = { "savetvsegmentpokemonstoragebulletin", "" },
  [0x30C] = { "savetvsegmenthomeandmanornofurniture", "" },
  [0x30D] = { "savetvsegmenthomeandmanor", "w" },
  [0x30E] = { "30e", "w" },
  [0x30F] = { "checkmetfurniturerequirements", "ww" },
  [0x310] = { "startlibrarytv", "" },
  [0x311] = { "adddistortionworldmapobject", "w" },
  [0x312] = { "deletedistortionworldmapobject", "w" },
  [0x313] = { "checkheapmemory", "w" },
  [0x314] = { "getbattleresult", "w" },
  [0x315] = { "getoverworldweather", "w" },
  [0x316] = { "dummy316", "" },
  [0x317] = { "getplayer3dpos", "www" },
  [0x318] = { "startfatefulencounter", "ww" },
  [0x319] = { "startgiratinaoriginbattle", "ww" },
  [0x31A] = { "setspeciesseen", "w" },
  [0x31B] = { "getcurrentsafarigamecaughtnum", "w" },
  [0x31C] = { "findpartyslotwithfatefulencounterspecies", "ww" },
  [0x31D] = { "tryrevertpartypokemonforms", "w" },
  [0x31E] = { "tryrevertpokemonform", "ww" },
  [0x31F] = { "resetdistortionworldpersistedcameraangles", "" },
  [0x320] = { "dodwwarp", "" },
  [0x321] = { "startdistortionworldgiratinashadowevent", "w" },
  [0x322] = { "finishdistortionworldgiratinashadowevent", "" },
  [0x323] = { "checknowifiplazacooldown", "w" },
  [0x324] = { "getbattlehallrecordkeeperstats", "bbbbww" },
  [0x325] = { "getnumspecieswithbattlehallrecords", "w" },
  [0x326] = { "getbattlehalltotalsinglesrecord", "w" },
  [0x327] = { "showlistmenusetwidth", "w" },
  [0x328] = { "setpartygiratinaform", "w" },
  [0x329] = { "getbattlefrontierreporterposition", "wwww" },
  [0x32A] = { "checkifbattlehallstreakis50", "w" },
  [0x32B] = { "checkpartyhasfatefulencounterregigigas", "w" },
  [0x32C] = { "activateregiruinsdot", "wwww" },
  [0x32D] = { "32d", "" },
  [0x32E] = { "32e", "" },
  [0x32F] = { "checkpartyhashelditem", "ww" },
  [0x330] = { "loglinkinfoinwifihistory", "" },
  [0x331] = { "331", "" },
  [0x332] = { "332", "" },
  [0x333] = { "setplayervolume", "w" },
  [0x334] = { "addtogamerecord", "ww" },
  [0x335] = { "addtogamerecordbigvalue", "wd" },
  [0x336] = { "checkishalloffamecorrupted", "w" },
  [0x337] = { "checkhasseenspecies", "ww" },
  [0x338] = { "338", "" },
  [0x339] = { "339", "" },
  [0x33A] = { "setmenuxoriginside", "b" },
  [0x33B] = { "setmenuyoriginside", "b" },
  [0x33C] = { "bufferitemnamewitharticle", "bw" },
  [0x33D] = { "bufferitemnameplural", "bw" },
  [0x33E] = { "bufferundergroundgoodsnamewitharticle", "bw" },
  [0x33F] = { "bufferundergroundtrapnamewitharticle", "bw" },
  [0x340] = { "bufferundergrounditemnamewitharticle", "bw" },
  [0x341] = { "bufferspeciesnamewitharticle", "bwwb" },
  [0x342] = { "bufferplayercounterpartstarterspeciesnamewitharticle", "b" },
  [0x343] = { "bufferaccessorynamewitharticle", "bw" },
  [0x344] = { "buffertrainerclassnamewitharticle", "bw" },
  [0x345] = { "bufferballsealnameplural", "bw" },
  [0x346] = { "capitalizefirstletter", "b" },
  [0x347] = { "bufferfloornumber", "bb" },
}

-- The eight handlers whose operand count depends on what they just read, so
-- no fixed spec can describe them.  Left unresolved on purpose: a guessed
-- width here is the Sootopolis bug again, and the decoder should refuse a
-- command it cannot size rather than silently walk past it.  Each needs its
-- handler read individually before it can be lowered.
Gen4ScriptOps.VARIABLE_LENGTH = {
  [0x1CF] = "dostrengthfunc",  -- scrcmd_system_flags.c
  [0x1D0] = "doflashfunc",  -- scrcmd_system_flags.c
  [0x1D1] = "dodefogfunc",  -- scrcmd_system_flags.c
  [0x21D] = "dogroupconnectionaction",  -- scrcmd_group_connection.c
  [0x235] = "calltvbroadcast",  -- scrcmd_tv_broadcast.c
  [0x237] = "calltvinterview",  -- scrcmd_tv_broadcast.c
  [0x23E] = "mysterygiftgive",  -- scrcmd_mystery_gift.c
  [0x27C] = "27c",  -- scrcmd_tv_broadcast.c
  -- (givepoffin, 0x289, was listed here and is NOT variable: ScrCmd_GivePoffin
  -- reads one var pointer and six vars, every time.)
}

-- What ends a script.  `end` returns from the whole script; `return` pops one
-- call frame.  Both stop a linear walk, which is what the extractor needs.
Gen4ScriptOps.TERMINATORS = {
  [0x002] = true,   -- end
  [0x01B] = true,   -- return
}

function Gen4ScriptOps.name(op)
  local entry = Gen4ScriptOps.COMMANDS[op]
  return entry and entry[1] or ("unknown_%03X"):format(op or -1)
end

-- Bytes this instruction occupies, opcode included -- or nil when the command
-- is variable-length, which the caller must handle rather than skip.
-- Operand bytes a spec string accounts for, opcode NOT included.
local function specWidth(spec)
  local n = 0
  for i = 1, #spec do
    local c = spec:sub(i, i)
    n = n + (c == "b" and 1 or c == "w" and 2 or c == "d" and 4 or 0)
  end
  return n
end
Gen4ScriptOps.specWidth = specWidth

function Gen4ScriptOps.size(op)
  local entry = Gen4ScriptOps.COMMANDS[op]
  if not entry then return nil end
  local spec = entry[2]
  if spec:find("*", 1, true) then return nil end
  return Gen4ScriptOps.OPCODE_BYTES + specWidth(spec)
end

-- SOME VARIABLE-LENGTH COMMANDS ARE VARIABLE BY A RULE WE CAN READ, and
-- leaving those undecoded costs whole scripts rather than single rows.
--
-- `Gen4Script.decode` stops the walk at a `*` command rather than guessing a
-- width, which is right -- the header of this file records what a guessed
-- width cost Gen 3 -- but "stop" means every instruction AFTER it is never
-- decoded.  Measured on the cartridge: of 8,567 scripts, 8,549 end at `end`,
-- 2 at an unknown opcode, 2 at an overrun, and **14 stop at a variable-length
-- command** -- so fourteen scripts are truncated, not fourteen rows.
--
-- Four of those fourteen are the three field-move flag commands, and
-- pokeplatinum states their rule outright in `asm/macros/scrcmd.inc`:
--
--     .macro DoStrengthFunc func, checkDestVarID=0
--     .short SCRCMD_DOSTRENGTHFUNC
--     .byte \func
--     .if \func == FIELD_MOVE_FUNC_CHECK_ACTIVE
--         .short \checkDestVarID
--     .endif
--     .endm
--
-- One byte always; a word as well, and only, when that byte is
-- FIELD_MOVE_FUNC_CHECK_ACTIVE.  That is READ, not inferred from handler
-- shapes, which is the same standard the fixed widths in this file are held
-- to.
--
-- A function here returns the spec string for one instruction given the bytes
-- at its position, or NIL -- and nil still stops the walk.  Refusing an
-- undefined sub-function is the whole point: `ScrCmd_DoStrengthFunc`'s
-- `default:` arm is `GF_ASSERT(FALSE)`, so a fourth value is not a width this
-- table may invent.
Gen4ScriptOps.FIELD_MOVE_FUNC = {
  CLEAR_ACTIVE = 0, SET_ACTIVE = 1, CHECK_ACTIVE = 2,
}

local function fieldMoveFuncSpec(data, pc)
  local func = data:byte(pc + Gen4ScriptOps.OPCODE_BYTES)
  if func == Gen4ScriptOps.FIELD_MOVE_FUNC.CHECK_ACTIVE then return "bw" end
  if func == Gen4ScriptOps.FIELD_MOVE_FUNC.SET_ACTIVE
     or func == Gen4ScriptOps.FIELD_MOVE_FUNC.CLEAR_ACTIVE then return "b" end
  return nil
end

-- MysteryGiftGive (scrcmd.inc): a u16 STAGE, then one destination var for
-- CHECK_AVAILABLE_PGT / GET_PGT_TYPE / CHECK_CAN_RECEIVE (1, 2, 3), two for
-- RECEIVED / CANT_RECEIVE (5, 6), and nothing for LOAD, GIVE and the two
-- UNLOADs (0, 4, 7, 8). Undecodable before, so every mart's OnTransition
-- (common script 10200) stopped at its first instruction and never set
-- FLAG_HIDE_MART_MYSTERY_GIFT_DELIVERYMAN -- the deliveryman stood in every
-- mart whether or not a gift was waiting.
Gen4ScriptOps.MYSTERY_GIFT_STAGE_ARGS = { [0] = 0, 1, 1, 1, 0, 2, 2, 0, 0 }
local function mysteryGiftSpec(data, pc)
  local lo, hi = data:byte(pc + Gen4ScriptOps.OPCODE_BYTES, pc + Gen4ScriptOps.OPCODE_BYTES + 1)
  if not (lo and hi) then return nil end
  local args = Gen4ScriptOps.MYSTERY_GIFT_STAGE_ARGS[lo + hi * 256]
  if not args then return nil end
  return "w" .. ("w"):rep(args)
end

Gen4ScriptOps.VARIABLE_SPEC = {
  [0x23E] = mysteryGiftSpec,    -- mysterygiftgive
  [0x1CF] = fieldMoveFuncSpec,  -- dostrengthfunc
  [0x1D0] = fieldMoveFuncSpec,  -- doflashfunc
  [0x1D1] = fieldMoveFuncSpec,  -- dodefogfunc
}

-- The spec for the instruction at `pc`, resolving a `*` command when its rule
-- is known.  `data` and `pc` are optional: without them a `*` command is
-- undecidable, which is what every caller that has no bytes to hand should get.
function Gen4ScriptOps.specAt(op, data, pc)
  local entry = Gen4ScriptOps.COMMANDS[op]
  if not entry then return nil end
  local spec = entry[2]
  if not spec:find("*", 1, true) then return spec end
  local rule = Gen4ScriptOps.VARIABLE_SPEC[op]
  if not rule or type(data) ~= "string" or type(pc) ~= "number" then return nil end
  return rule(data, pc)
end

-- Bytes the instruction at `pc` occupies, opcode included, or nil when its
-- width still cannot be known.  `size` above stays as it was: it answers from
-- the opcode alone and several callers have nothing else to give it.
function Gen4ScriptOps.sizeAt(op, data, pc)
  local spec = Gen4ScriptOps.specAt(op, data, pc)
  if not spec then return nil end
  return Gen4ScriptOps.OPCODE_BYTES + specWidth(spec)
end

return Gen4ScriptOps
