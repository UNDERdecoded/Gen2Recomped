-- PLATINUM'S BATTLE FRONTIER SCENE ENGINE (overlay104's FrontierScriptContext),
-- over the scripts src/import/Gen4FrontierScripts.lua decodes.
--
-- Lowered to ScriptRunner rows the way the field VM lowers a field script,
-- and for the same reason: one runner, one set of rows, and every command a
-- function that can yield. Most of what a frontier script says, the field
-- engine already says the same way -- a message from the scene's own bank, a
-- list menu, a yes/no, a number buffered, a fanfare -- and those are handed
-- to Gen4ScriptVM's lowering with the scene's bank standing in for the map's.
-- What is the frontier's own is lowered here:
--
--   * CONTROL FLOW over "F<member>/<offset>" labels. Conditions and the
--     compare result are the field engine's (sConditionTable is the same
--     six rows), so g4_jump_if / g4_call_if / g4_return carry them.
--   * VARIABLES. A frontier operand below 0x8000 is a LITERAL, always; at
--     0x8000 and up it is the script's own variable. The field engine reads
--     0x4000.. as variables, so the frontier's own set rows take values here
--     (fr_set / fr_add / fr_compare) rather than through g4_set_var.
--   * THE SCENE: objects from 24's lists, ApplyMovement's lists, the mon pic
--     45 shows, the scene changes and the exit -- src/ui/Gen4FrontierScene.lua.
--   * GetSystemVar / SetSystemVar: the field's variables, read and written.
--
-- Facility commands (the Battle Hall's, ...) are lowered by the facility's own
-- module through Gen4FrontierVM.facility[name].

local G4VM = require("src.script.Gen4ScriptVM")

local VM = {}
VM.facility = {}

local function emit(s, row) s.out[#s.out + 1] = row end
VM.emit = emit

local L = {}
VM.L = L

-- control flow ---------------------------------------------------------------
L["end"] = function(_, s) emit(s, { "fr_stop" }); emit(s, { "jump", "end" }) end
L.exitfrontier = function(_, s) emit(s, { "fr_exit" }); emit(s, { "jump", "end" }) end
L.changescenewithinscript = function(ins, s) emit(s, { "fr_change_scene", ins.args[1] }) end
L.changescript = function(ins, s)
  emit(s, { "fr_change_script", ins.args[1], ins.args[2] })
  emit(s, { "jump", "end" })
end
L["goto"] = function(ins, s) s.want(ins.args[1]); emit(s, { "jump", ins.args[1] }) end
L.gotoif = function(ins, s) s.want(ins.args[2]); emit(s, { "g4_jump_if", ins.args[1], ins.args[2] }) end
L.call = function(ins, s)
  s.want(ins.args[1])
  local ret = s.newLabel()
  emit(s, { "g4_call", ret })
  emit(s, { "jump", ins.args[1] })
  emit(s, { "label", ret })
end
L.callif = function(ins, s)
  s.want(ins.args[2])
  local ret = s.newLabel()
  emit(s, { "g4_call_if", ins.args[1], ret })
  emit(s, { "jump", ins.args[2] })
  emit(s, { "label", ret })
end
L["return"] = function(_, s) emit(s, { "g4_return" }) end
L.noop = function() end

-- variables ------------------------------------------------------------------
L.setvarfromvalue = function(ins, s) emit(s, { "fr_set", ins.args[1], ins.args[2] }) end
L.setvarfromvar = L.setvarfromvalue
L.addvar = function(ins, s) emit(s, { "fr_add", ins.args[1], ins.args[2], 1 }) end
L.subvar = function(ins, s) emit(s, { "fr_add", ins.args[1], ins.args[2], -1 }) end
L.comparevartovalue = function(ins, s) emit(s, { "fr_compare", ins.args[1], ins.args[2] }) end
L.comparevartovar = L.comparevartovalue
L.getsystemvar = function(ins, s) emit(s, { "fr_get_system_var", ins.args[1], ins.args[2] }) end
L.setsystemvar = function(ins, s) emit(s, { "fr_set_system_var", ins.args[1], ins.args[2] }) end
L.getplayerobjeventgfx = function(ins, s) emit(s, { "fr_player_gfx", ins.args[1] }) end
L.waittime = function(ins, s) emit(s, { "fr_wait", ins.args[1] }) end
-- GetRandom <dest> <bound>: LCRNG_Next() % bound
L.getrandom = function(ins, s) emit(s, { "fr_random", ins.args[1], ins.args[2] }) end
-- FadeScreen <transition> <frames> <type> <colour>: the scene's own screen,
-- not the field's overlay behind it
L.fadescreen = function(ins, s) emit(s, { "fr_fade", ins.args[3], ins.args[1], ins.args[2] }) end
L.waitfadescreen = function(_, s) emit(s, { "fr_wait_fade" }) end

-- buffers the field engine spells differently ----------------------------------
L.bufferspeciesname = function(ins, s) emit(s, { "fr_buffer_species", ins.args[1], ins.args[2] }) end
L.bufferpartnername = function(ins, s) emit(s, { "g4_buffer", ins.args[1], "player" }) end
L.buffermovename = function(ins, s) emit(s, { "fr_buffer_kind", ins.args[1], "move", ins.args[2] }) end
L.buffertypename = function(ins, s) emit(s, { "fr_buffer_kind", ins.args[1], "type", ins.args[2] }) end

-- sound ----------------------------------------------------------------------
L.playsoundeffect = function(ins, s) emit(s, { "g4_play_sound", ins.args[1] }) end
L.waitsoundeffect = function(ins, s) emit(s, { "g4_wait_sound", ins.args[1] }) end

-- records --------------------------------------------------------------------
L.incrementrecordvalue = function(ins, s) emit(s, { "fr_record", ins.args[1] }) end

-- the scene ------------------------------------------------------------------
L["22"] = function() end                                     -- load sprite resources
L["23"] = function() end                                     -- unload one
L["24"] = function(ins, s) emit(s, { "fr_objects", ins.args[1] }) end
L["25"] = function(ins, s) emit(s, { "fr_remove_object", ins.args[1] }) end
L["26"] = function(ins, s) emit(s, { "fr_object_flag", ins.args[1], ins.args[2] }) end
L.applymovement = function(ins, s) emit(s, { "fr_move", ins.args[1], ins.args[2] }) end
L.waitmovement = function(_, s) emit(s, { "fr_wait_move" }) end
L["45"] = function(ins, s) emit(s, { "fr_show_mon", ins.args[1], ins.args[2], ins.args[3] }) end
L["46"] = function(ins, s) emit(s, { "fr_hide_mon", ins.args[1] }) end
L["3f"] = function(ins, s) emit(s, { "fr_battle_transition", ins.args[1] }) end

-- the frontier's presentation this port does not draw: particle bursts, the
-- background effect task, link handshakes, the battle recorder, TV
local SILENT = { "initparticlesystem", "createparticlesystememitter", "waitforparticlesystememitters",
  "freeparticlesystem", "4e", "syncconnectedplayers", "clearreceivedtempdataallplayers",
  "initnewbattlerecording", "freebattlerecording", "c8", "c9", "playfrontierbrainencountereffect",
  "4c" }
for _, n in ipairs(SILENT) do L[n] = function() end end
-- C7: the Battle Hall's TV note (FrontierScrCmd_C7 -> sub_0206D048): the
-- Frontline News interview's pending state (src/script/PtTvRecords.lua)
L["c7"] = function(_, s) emit(s, { "fr_hall_tv" }) end
-- 70 / 71: the battle recorder's checks, answered "nothing recorded"
L["70"] = function(ins, s) emit(s, { "fr_set", ins.args[1], 0 }) end
L["71"] = function(ins, s) emit(s, { "fr_set", ins.args[1], 0 }) end
-- 6D: save the battle video -- there is none to save, and it says it failed
L["6d"] = function(ins, s) emit(s, { "fr_set", ins.args[4], 0 }) end
-- 73: SaveData_SaveStateInit -- the save, with its result
L["73"] = function(ins, s) emit(s, { "fr_save", ins.args[1] }) end

-- what the field engine lowers the same way (messages, menus, buffers, fades,
-- fanfares, the saving icon, BP, a party heal)
local SHARED = { "messageinstant", "messagenoskip", "message", "closemessage", "initlocaltextlistmenu", "initglobaltextlistmenu", "initlocaltextmenu",
  "initglobaltextmenu", "addlistmenuentry", "addmenuentry", "showlistmenu", "showmenu",
  "setmenuxoriginside", "setmenuyoriginside", "showyesnomenu", "buffernumber",
  "bufferplayername", "playfanfare", "waitfanfare", "healparty", "givebattlepoints",
  "showsavingicon", "hidesavingicon", "waitabpress", "incrementtrainerscore" }

function VM.lowerOne(ins, s)
  local fn = L[ins.name] or VM.facility[ins.name]
  if fn then return fn(ins, s) end
  for _, n in ipairs(SHARED) do
    if n == ins.name then return G4VM.lower({ ins }, s) end
  end
  emit(s, { "g4_noop", "frontier " .. ins.name })
end

-- the store and its compiled entry points ------------------------------------

local compiled = setmetatable({}, { __mode = "k" })

function VM.member(data, member)
  local store = data and data.gen4_frontier_scripts
  return store and store.members and store.members[member]
end

-- rows for `entry` (a label) of `member`, with `bank` as the message bank
function VM.compile(data, member, entry, bank)
  local m = VM.member(data, member)
  if not (m and m.blocks[entry]) then return nil end
  compiled[m] = compiled[m] or {}
  local key = entry .. "@" .. tostring(bank)
  if compiled[m][key] then return compiled[m][key] end
  local out, queued, order, counter = {}, { [entry] = true }, { entry }, 0
  local s = {
    out = out, member = member,
    bankFor = function() return bank end,
    want = function(label)
      if label and m.blocks[label] and not queued[label] then
        queued[label] = true
        order[#order + 1] = label
      end
    end,
    newLabel = function() counter = counter + 1; return ("%s_r%d"):format(entry, counter) end,
    has = function(label) return m.blocks[label] ~= nil end,
  }
  local i = 1
  while i <= #order do
    local label = order[i]
    i = i + 1
    emit(s, { "label", label })
    for _, ins in ipairs(m.blocks[label].instructions) do VM.lowerOne(ins, s) end
    -- a block that just falls off its end (it cannot, but a truncated decode
    -- could) stops rather than running into the next one
    emit(s, { "jump", "end" })
  end
  compiled[m][key] = out
  return out
end

function VM.entryLabel(data, member, index)
  local m = VM.member(data, member)
  local off = m and m.entries[(index or 0) + 1]
  return off and require("src.import.Gen4FrontierScripts").label(member, off)
end

return VM
