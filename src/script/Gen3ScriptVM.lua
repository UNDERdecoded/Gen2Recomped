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
L.nop1 = L.nop
L.nop_e3 = L.nop
L.waitstate = L.nop

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
L.braillemessage = L.message
L.vmessage = L.message

-- the text box owns its own lifecycle in this engine
L.waitmessage = L.nop
L.closemessage = L.nop
L.closebraillemessage = L.nop
L.waitbuttonpress = L.nop

local function std(ir, s, isJump)
  local index = tonumber(ir[2])
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
L.applymovementat = L.applymovement
L.waitmovement = L.nop       -- g3_move is blocking, so the wait is implicit
L.waitmovementat = L.nop

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
L.copyobjectxytoperm = L.nop
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
L.pokemartdecoration = L.pokemart
L.pokemartdecoration2 = L.pokemart

-- battles ------------------------------------------------------------------

L.trainerbattle = function(ir, s)
  emit(s, { "g3_trainer_battle", ir[2], ir[3] })
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
L.warphole = function(ir, s) emit(s, { "g3_warp", ir[2], ir[3] }) end
L.setwarp = function(ir, s) emit(s, { "g3_set_warp", ir[2], ir[3], ir[4], ir[5], ir[6] }) end
L.setdynamicwarp = L.setwarp
L.setdivewarp = L.setwarp
L.setholewarp = L.setwarp
L.setescapewarp = L.setwarp
L.setrespawn = function(ir, s) emit(s, { "g3_set_respawn", ir[2] }) end

-- sound --------------------------------------------------------------------

L.playse = function(ir, s) emit(s, { "play_sound", ir[2] }) end
L.waitse = L.nop
L.playfanfare = function(ir, s) emit(s, { "play_once", ir[2] }) end
L.waitfanfare = L.nop
L.playbgm = function(ir, s) emit(s, { "play_music", ir[2] }) end
L.savebgm = L.nop
L.fadedefaultbgm = function(_, s) emit(s, { "play_default_music" }) end
L.fadenewbgm = function(ir, s) emit(s, { "play_music", ir[2] }) end
L.fadeoutbgm = function(_, s) emit(s, { "stop_music" }) end
L.fadeinbgm = function(_, s) emit(s, { "play_default_music" }) end
L.playmoncry = function(ir, s) emit(s, { "play_cry", ir[2] }) end
L.waitmoncry = L.nop

-- screen, field, world -----------------------------------------------------

L.delay = function(ir, s) emit(s, { "wait", ir[2] }) end
L.fadescreen = function(ir, s) emit(s, { "fade", (tonumber(ir[2]) or 0) % 2 == 0 and "out" or "in" }) end
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
L.doweather = L.nop
L.setflashlevel = L.nop
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
L.setberrytree = L.nop
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
L.showmonpic = function(ir, s) emit(s, { "g3_show_mon_pic", ir[2] }) end
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
  local gated = {}
  for _, tbl in ipairs(entry.tables or {}) do
    for _, row in ipairs(tbl.rows or {}) do
      local rows = Gen3ScriptVM.compile(data, row.script)
      if rows then
        gated[#gated + 1] = { var = row.var, value = row.value, rows = rows }
      end
    end
  end
  if #onEnter > 0 or #gated > 0 then
    local Gen3Commands = require("src.script.Gen3Commands")
    contribution.onEnter = function(game, overworld)
      for _, rows in ipairs(onEnter) do
        queue(overworld, rows, { mapId = mapId })
      end
      for _, g in ipairs(gated) do
        if Gen3Commands.getVar(game.save, g.var) == g.value then
          queue(overworld, g.rows, { mapId = mapId })
          break
        end
      end
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
    contribution.onStep = function(game, overworld, x, y)
      if overworld.runner:isRunning() then return false end
      for _, coord in ipairs(coords) do
        if coord.x == x and coord.y == y
           and (coord.var == nil or coord.var == 0
                or Gen3Commands.getVar(game.save, coord.var) == coord.value) then
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
  scenes = { onEnter = true, onStep = true },
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
