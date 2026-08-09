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
require("src.script.Gen2Commands")

local Gen2ScriptVM = {}

local compiled = setmetatable({}, { __mode = "k" })

local function eventFlag(n) return string.format("EVENT_G2_%04d", n) end
local function itemId(n) return string.format("ITEM_%03d", n) end

-- EngineFlags ($03:$404D, `dw address, db mask` rows) is what `setflag`/
-- `checkflag` index.  Rows $00-$04 all address wPokegearFlags and row $0B is
-- wStatusFlags bit 0, the POKeDEX bit -- all START-menu features rather than
-- bag items, so they have to land on the names the menus already gate on
-- instead of an opaque FLAG_G2_ id.
local ENGINE_FLAG_NAMES = {
  [0] = "EVENT_GOT_RADIO_CARD",
  [1] = "EVENT_GOT_MAP_CARD",
  [4] = "EVENT_GOT_POKEGEAR",
  [11] = "EVENT_GOT_POKEDEX",
  -- rows $1A-$29 are wJohtoBadges then wKantoBadges, bit 0 first.  The bit
  -- order is not the card's display order: FlyFunction checks $1F for
  -- STORMBADGE and StrengthFunction $1C for PLAINBADGE, putting Mineral on
  -- bit 4 and Storm on bit 5.  Gen2 has no badge ITEM, so these have to carry
  -- the badge id itself -- Badges.has reads them straight out of save.flags.
  [26] = "ZEPHYRBADGE", [27] = "HIVEBADGE",
  [28] = "PLAINBADGE",  [29] = "FOGBADGE",
  [30] = "MINERALBADGE", [31] = "STORMBADGE",
  [32] = "GLACIERBADGE", [33] = "RISINGBADGE",
  [34] = "BOULDERBADGE", [35] = "CASCADEBADGE",
  [36] = "THUNDERBADGE", [37] = "RAINBOWBADGE",
  [38] = "SOULBADGE",    [39] = "MARSHBADGE",
  [40] = "VOLCANOBADGE", [41] = "EARTHBADGE",
}

local function engineFlag(n)
  return ENGINE_FLAG_NAMES[n] or string.format("FLAG_G2_%04d", n)
end

-- ---------------------------------------------------------------------------
-- lowering table: ir row -> zero or more ScriptRunner rows
-- ---------------------------------------------------------------------------

local L = {}

local function emit(s, row) s.out[#s.out + 1] = row end

-- A pointer that fell outside the ROM, or a far script that failed to
-- disassemble, is stored as "" by the extractor.  Branches to one lower to
-- nothing at all rather than to a jump ScriptRunner cannot resolve.
local function branch(s, label)
  if type(label) ~= "string" or not s.has(label) then return nil end
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
L.jumpstd = function(ir, s)
  local to = branch(s, s.stds and s.stds[ir[2]])
  if to then emit(s, { "jump", to }) else emit(s, { "g2_std", ir[2] }) end
  emit(s, { "g2_return" })
end
L.callstd = function(ir, s)
  local to = branch(s, s.stds and s.stds[ir[2]])
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
-- prompt itself, so drop that row rather than showing the line twice
L.yesorno = function(_, s)
  if s.lastTextRow == #s.out then
    table.remove(s.out)
    s.lastTextRow = nil
  end
  emit(s, { "g2_yesno", s.lastText })
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
L.pause = function(ir, s) emit(s, { "wait", ir[2] }) end
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
  [0x1B] = "heal_party",     -- HealParty, called by PokecenterNurseScript
  [0x1E] = "g2_daycare_man",     -- DayCareMan, wBreedMon1
  [0x1F] = "g2_daycare_lady",    -- DayCareLady, wBreedMon2
  [0x20] = "g2_daycare_outside", -- DayCareManOutside, the EGG handover
  [0x29] = "g2_unown_puzzle", -- UnownPuzzle, the Ruins of Alph wall patterns
  [0x2A] = "g2_slots",       -- SlotMachine, wScriptVar picks the lucky one
  [0x2B] = "g2_card_flip",   -- CardFlip
  [0x44] = "g2_daycare_mon1", -- DayCareMon1, the left mon in the yard
  [0x45] = "g2_daycare_mon2", -- DayCareMon2, the right mon in the yard
  -- Mania's SHUCKIE.  ManiaScript is `special GiveShuckle` + `iffalse
  -- .partyfull`, so the warn-once stub's lastCheck = false read back as a
  -- full party no matter how many slots were free.
  [0x4A] = "g2_give_shuckle",  -- GiveShuckle (01:$73E1)
  [0x4B] = "g2_return_shuckie", -- ReturnShuckie (01:$7452)
  [0x4E] = "g2_show_coins",  -- DisplayCoinCaseBalance
  [0x4F] = "g2_show_coins",  -- DisplayMoneyAndCoinBalance
  [0x56] = "g2_name_rater",  -- NameRater, whose whole script IS the special
}

-- Specials the port has no state for but that are genuine no-ops here, so
-- they must not warn: WaitSFX just spins until the sound channel is quiet.
local SPECIALS_NOOP = { [0x3A] = true } -- WaitSFX

L.special = function(ir, s)
  if SPECIALS_NOOP[ir[2]] then return end
  local name = SPECIALS[ir[2]]
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
L.closepokepic = function() end
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

  -- The ROM runs exactly one scene -- the one wMapScenes names for this map --
  -- and then every callback.  Running all of them would fire every cutscene
  -- state the map has ever had the moment the player walks in.
  local scenes, callbacks = {}, {}
  for i, label in ipairs(entry.scenes or {}) do
    scenes[i] = Gen2ScriptVM.compile(data, label) or false
  end
  for _, callback in ipairs(entry.callbacks or {}) do
    local rows = Gen2ScriptVM.compile(data, callback.script)
    if rows then callbacks[#callbacks + 1] = rows end
  end
  if #scenes > 0 or #callbacks > 0 then
    local Gen2Commands = require("src.script.Gen2Commands")
    contribution.onEnter = function(game, overworld)
      local scene = Gen2Commands.getScene(game.save, mapId)
      local rows = scenes[scene + 1]
      if rows then queue(overworld, rows, { mapId = mapId }) end
      for _, cb in ipairs(callbacks) do
        queue(overworld, cb, { mapId = mapId })
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
