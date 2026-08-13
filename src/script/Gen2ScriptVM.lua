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

local Gen2ScriptVM = {}

local compiled = setmetatable({}, { __mode = "k" })

local eventFlag = Gen2Flags.eventFlag
local engineFlag = Gen2Flags.engineFlag
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
L.sdefer = L.scall

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
-- (25:$75AD) all end in PrintNum into a string buffer.  The port collapses
-- every wStringBuffer onto game.stringBuffer (see TextBox's text_ram
-- handling), so each of these is "put this number where {RAM:...} reads".
L.getmoney = function(_, s) emit(s, { "g2_buffer_money" }) end
L.getcoins = function(_, s) emit(s, { "g2_buffer_coins" }) end
L.getnum = function(_, s) emit(s, { "g2_buffer_num" }) end

-- Script_getcurlandmarkname (25:$755B) reads wMapGroup/wMapNumber, resolves
-- the landmark and copies its name into the buffer.
L.getcurlandmarkname = function(_, s) emit(s, { "g2_buffer_landmark" }) end

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
--   catchtutorial  is the Gen2 catching demo, which the port does not ship.
local function vmNoop() end
for _, name in ipairs({
  "xycompare", "writeobjectxy", "loadtemptrainer", "randomwildmon",
  "loadpikachudata", "_2dmenu", "describedecoration",
  "autoinput", "catchtutorial",
}) do
  L[name] = vmNoop
end



L["end"] = function(_, s) emit(s, { "g2_return" }) end
L.endcallback = L["end"]
L.reloadend = L["end"]

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

L.writetext = function(ir, s)
  s.lastText = ir[2]
  emit(s, { "show_text", ir[2] })
  s.lastTextRow = #s.out
end
L.farwritetext = L.writetext
L.repeattext = function(_, s)
  if s.lastText then emit(s, { "show_text", s.lastText }) end
end

L.jumptext = function(ir, s)
  emit(s, { "show_text", ir[2] })
  emit(s, { "g2_return" })
end
L.jumptextfaceplayer = function(ir, s)
  emit(s, { "face_player" })
  emit(s, { "show_text", ir[2] })
  emit(s, { "g2_return" })
end
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
  emit(s, { "g2_yesno", text or "" }) -- show_text indexes the id, never nil
end
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

-- plain `giveitem` is silent; only `verbosegiveitem` prints and plays
L.giveitem = function(ir, s) emit(s, { "g2_giveitem", itemId(ir[2]), ir[3] }) end
L.verbosegiveitem = function(ir, s)
  emit(s, { "give_item", itemId(ir[2]), ir[3] })
end
L.getitemname = function(ir, s) emit(s, { "g2_getitemname", itemId(ir[2]) }) end
L.getmonname = function(ir, s)
  emit(s, { "g2_getmonname", string.format("SPECIES_%03d", ir[2] or 0) })
end
L.takeitem = function(ir, s) emit(s, { "take_item", itemId(ir[2]), ir[3] }) end
L.checkitem = function(ir, s) emit(s, { "check_item", itemId(ir[2]) }) end
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
  emit(s, { "g2_cry", string.format("SPECIES_%03d", ir[2] or 0) })
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
-- movement, warps, presentation -------------------------------------------

L.warp = function(ir, s) emit(s, { "g2_warp", ir[2], ir[4], ir[5] }) end
L.warpfacing = function(ir, s) emit(s, { "g2_warp", ir[3], ir[5], ir[6], ir[2] }) end
L.blackoutmod = function(ir, s) emit(s, { "g2_blackout_point", ir[2] }) end

-- Script_halloffame (pokegold scripting.asm): induction + credits.
-- HallOfFameEnterScript ends with: HealParty → (optional SS Ticket call) → halloffame.
-- Without this lowering the opcode is skipped and the player can walk around
-- the Hall of Fame after the heal.
L.halloffame = function(_, s)
  emit(s, { "record_hall_of_fame" })
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
L.loadmenu = function(ir, s) emit(s, { "g2_loadmenu", ir[2] }) end
-- `writecmdqueue <ptr>`: the extractor has already followed the queue entry
-- and, when it is a CMDQUEUE_STONETABLE, turned it into the table's rows.
-- Registering them is all the map callback has to do -- the overworld fires
-- the matching row when a boulder settles on a hole.  A queue entry of any
-- other type still resolves to a bare pointer, which stays inert.
L.writecmdqueue = function(ir, s)
  if type(ir[2]) == "table" then emit(s, { "g2_stonetable", ir[2] }) end
end
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
  HealParty = "g2_heal_party",
  DayCareMan = "g2_daycare_man",
  DayCareLady = "g2_daycare_lady",
  DayCareManOutside = "g2_daycare_outside",
  MoveDeletion = "g2_move_deleter",
  BankOfMom = "g2_bank_of_mom",
  MagnetTrain = "g2_magnet_train",
  NameRival = "g2_name_rival",
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

L.special = function(ir, s)
  local key = ir[3]
  if type(key) ~= "string" then key = GOLD_SPECIAL_LABELS[ir[2]] end
  if key == nil then
    emit(s, { "g2_special", ir[2] })
    return
  end
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
  TryStrengthOW    = { "g2_try_strength" },
  SetStrengthFlag  = { "g2_strength_on" },
  GetPartyNickname = { "g2_party_nickname" },
  -- RockMonEncounter rolls the rock-smash wild table, which the port has no
  -- data for; report "nothing appeared" so the script ends after the rock.
  RockMonEncounter = { "g2_setvar", 0 },
}

L.callasm = function(ir, s)
  local row = ASM[ir[2]]
  if not row then return end
  local copy = {}
  for i = 1, #row do copy[i] = row[i] end
  emit(s, copy)
end
L.memcallasm = L.callasm
L.setval = function(ir, s) emit(s, { "g2_setvar", ir[2] }) end
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
  [1] = true,
  [5] = true, [6] = true, [7] = true, [9] = true,
  [10] = true, [11] = true, [14] = true, [16] = true, [20] = true,
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

L.loadvar = function(ir, s)
  if WRITE_VARS[ir[2]] then emit(s, { "g2_loadvar", ir[2], ir[3] }) end
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

-- checkver reports the running game: 0 = Gold/Silver, 1 = Crystal.  Left
-- unlowered the comparison read a stale var and took the Crystal branch.
L.checkver = function(_, s) emit(s, { "g2_setvar", 0 }) end

-- swarm <type>, <mapgroup+map>: the roaming/swarm species relocation.  The
-- port has no swarm table, so record the request rather than drop it.
L.swarm = function(ir, s) emit(s, { "g2_swarm", ir[2], ir[3] }) end

-- Deliberately nullary.  The port's text box owns its own lifecycle
-- (closewindow, closepokepic) and give_item already prints the line
-- itemnotify exists to print.
L.closewindow = function() end
L.itemnotify = function() end

-- ---------------------------------------------------------------------------
-- compiler
-- ---------------------------------------------------------------------------

local function store(data)
  return data and data.map_scripts or nil
end

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
    for _, ir in ipairs(scripts[label] or {}) do
      local lower = L[ir[1]]
      if lower then lower(ir, state) end
    end
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
    local Gen2Commands = require("src.script.Gen2Commands")
    contribution.onEnter = function(game, overworld)
      local flags = game.save.flags
      if flags then
        for i = 0, 7 do
          flags[eventFlag(i)] = nil
        end
      end
      for _, cb in ipairs(callbacks) do
        queue(overworld, cb, { mapId = mapId })
      end
      local scene = Gen2Commands.getScene(game.save, mapId)
      local rows = scenes[scene + 1]
      if rows then queue(overworld, rows, { mapId = mapId }) end
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
