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
  { "gettrainername", "bbb" }, { "getstring", "bd" }, { "itemnotify", "" },
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

Gen2ScriptOps.ARG_BYTES = {
  b = 1, w = 2, p = 2, t = 2, d = 2, M = 2, f = 3, T = 3, D = 3, m = 3,
}

-- commands after which the interpreter never falls through to the next byte
Gen2ScriptOps.TERMINATORS = {
  sjump = true, farsjump = true, memjump = true, jumpstd = true,
  jumptext = true, jumptextfaceplayer = true, stopandsjump = true,
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
