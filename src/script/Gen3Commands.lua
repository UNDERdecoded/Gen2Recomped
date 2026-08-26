-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Runtime commands for the Gen3 script VM.
--
-- Gen3ScriptVM lowers Emerald bytecode into ScriptRunner rows.  Most rows are
-- ordinary engine commands (show_text, set_flag, warp, ...); the ones with no
-- Gen1/Gen2 equivalent live here under a `g3_` prefix so they never collide
-- with the hand-ported vocabulary in data/scripts/ or with Gen2Commands.
--
-- THE COMPARISON REGISTER is the structural difference from Gen 2.  Emerald
-- does not branch on "the last command succeeded"; it keeps a result valued
-- 0, 1 or 2 -- less, equal, greater -- and every branch carries a condition
-- byte selecting a row of this table:
--
--            result:  0(<)  1(=)  2(>)
--     0  LT            yes    no    no
--     1  EQ             no   yes    no
--     2  GT             no    no   yes
--     3  LE            yes   yes    no
--     4  GE             no   yes   yes
--     5  NE            yes    no   yes
--
-- `checkflag` sets the register to the flag's own value, so `checkflag /
-- goto_if 1` reads "if the flag is set" and `goto_if 0` reads "if it is
-- clear" -- 0 is less than 1.  Collapsing the six conditions to a boolean
-- would invert about half the branches in Hoenn, which is the kind of wrong
-- that looks like scattered event bugs rather than a decoder fault.
--
-- WHAT IS DELIBERATELY INERT.  Several verbs below record their request and
-- do nothing else, because the engine has no Gen 3 equivalent yet (decorations,
-- secret bases, contests, the Battle Frontier).  That is a considered choice:
-- a script that skips a step degrades a scene, while a script that guesses at
-- one corrupts a save.  Every inert verb is named here rather than left out of
-- the lowering table, so `Gen3ScriptVM.lowered` reports honest coverage.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")

local Gen3Commands = {}

-- ---------------------------------------------------------------------------
-- vars
--
-- Emerald has two var ranges: $4000-$40FF persist in the save, $8000-$800F are
-- scratch for the running script.  VAR_RESULT is $800D and is where almost
-- every check lands, which is why the yes/no box has to write it.
-- ---------------------------------------------------------------------------

local VAR_TEMP_BASE, VAR_TEMP_TOP = 0x8000, 0x8010
local VAR_RESULT = 0x800D

local function varStore(save)
  if not save then return nil end
  save.gen3Vars = save.gen3Vars or {}
  return save.gen3Vars
end

local function getVar(save, id)
  id = tonumber(id) or 0
  local store = varStore(save)
  return (store and store[id]) or 0
end

local function setVar(save, id, value)
  id = tonumber(id) or 0
  local store = varStore(save)
  if store then store[id] = tonumber(value) or 0 end
end

Gen3Commands.getVar = getVar
Gen3Commands.setVar = setVar
Gen3Commands.VAR_RESULT = VAR_RESULT

-- A `setvar`-family operand is a var id when it is in either var range and a
-- literal otherwise; `setorcopyvar` is the command that has to tell them apart
-- at runtime, which is the whole reason it exists as a separate opcode.
local function isVarId(n)
  n = tonumber(n) or 0
  return (n >= 0x4000 and n < 0x4200) or (n >= VAR_TEMP_BASE and n < VAR_TEMP_TOP)
end

local function valueOf(ctx, n)
  if isVarId(n) then return getVar(ctx.save, n) end
  return tonumber(n) or 0
end

-- ---------------------------------------------------------------------------
-- the comparison register
-- ---------------------------------------------------------------------------

-- [condition][result + 1]
local CONDITION = {
  [0] = { true,  false, false },   -- LT
  [1] = { false, true,  false },   -- EQ
  [2] = { false, false, true  },   -- GT
  [3] = { true,  true,  false },   -- LE
  [4] = { false, true,  true  },   -- GE
  [5] = { true,  false, true  },   -- NE
}

local function compare(a, b)
  if a < b then return 0 end
  if a > b then return 2 end
  return 1
end

local function setResult(ctx, result)
  ctx.g3Compare = result
  ctx.lastCheck = result == 1
end

local function holds(ctx, condition)
  local row = CONDITION[tonumber(condition) or 1]
  if not row then return false end
  return row[(ctx.g3Compare or 1) + 1] == true
end

Gen3Commands.compare = compare
Gen3Commands.holds = holds

-- ---------------------------------------------------------------------------
-- control flow
-- ---------------------------------------------------------------------------

function Commands.g3_call(ctx, returnLabel)
  ctx.g3Stack = ctx.g3Stack or {}
  ctx.g3Stack[#ctx.g3Stack + 1] = returnLabel
end

function Commands.g3_return(ctx)
  local stack = ctx.g3Stack
  if stack and #stack > 0 then return table.remove(stack) end
  return "end"
end

function Commands.g3_jump_if(ctx, condition, target)
  if holds(ctx, condition) then return target end
end

function Commands.g3_jump_unless(ctx, condition, target)
  if not holds(ctx, condition) then return target end
end

function Commands.g3_call_if(ctx, condition, returnLabel, target)
  if not holds(ctx, condition) then return end
  ctx.g3Stack = ctx.g3Stack or {}
  ctx.g3Stack[#ctx.g3Stack + 1] = returnLabel
  return target
end

-- ---------------------------------------------------------------------------
-- vars, flags, comparisons
-- ---------------------------------------------------------------------------

function Commands.g3_setvar(ctx, id, value)
  setVar(ctx.save, id, tonumber(value) or 0)
end

function Commands.g3_addvar(ctx, id, delta)
  setVar(ctx.save, id, getVar(ctx.save, id) + (tonumber(delta) or 0))
end

function Commands.g3_copyvar(ctx, dest, src)
  setVar(ctx.save, dest, getVar(ctx.save, src))
end

-- `setorcopyvar` is `copyvar` when its source names a var and `setvar` when it
-- is a literal -- the one command that decides at runtime.
function Commands.g3_setorcopyvar(ctx, dest, src)
  setVar(ctx.save, dest, valueOf(ctx, src))
end

function Commands.g3_compare_value(ctx, id, value)
  setResult(ctx, compare(getVar(ctx.save, id), tonumber(value) or 0))
end

function Commands.g3_compare_var(ctx, a, b)
  setResult(ctx, compare(getVar(ctx.save, a), getVar(ctx.save, b)))
end

-- checkflag writes the FLAG'S OWN VALUE into the register, not a comparison:
-- that is what makes `checkflag / goto_if 1` mean "if set".
function Commands.g3_check_flag(ctx, name)
  Commands.check_flag(ctx, name)
  setResult(ctx, ctx.lastCheck and 1 or 0)
end

function Commands.g3_random(ctx, bound)
  bound = math.max(tonumber(bound) or 1, 1)
  setVar(ctx.save, VAR_RESULT, math.random(0, bound - 1))
end

-- the yes/no std leaves its answer on ctx; Emerald's scripts read VAR_RESULT
function Commands.g3_from_yesno(ctx)
  local yes = ctx.lastCheck and 1 or 0
  setVar(ctx.save, VAR_RESULT, yes)
  setResult(ctx, yes)
end

function Commands.g3_player_xy(ctx, xVar, yVar)
  local player = ctx.overworld and ctx.overworld.player
  setVar(ctx.save, xVar, player and player.cellX or 0)
  setVar(ctx.save, yVar, player and player.cellY or 0)
end

function Commands.g3_check_gender(ctx)
  local save = ctx.save
  local female = save and (save.playerGender == 1 or save.playerGender == "female")
  setVar(ctx.save, VAR_RESULT, female and 1 or 0)
  setResult(ctx, female and 1 or 0)
end

function Commands.g3_get_time(ctx)
  local ow = ctx.overworld
  local hour = ow and ow.clockHour and ow:clockHour() or 12
  setVar(ctx.save, 0x8000, hour)
end

function Commands.g3_party_size(ctx)
  local party = ctx.save and ctx.save.party
  setVar(ctx.save, VAR_RESULT, party and #party or 0)
end

-- ---------------------------------------------------------------------------
-- player and objects
-- ---------------------------------------------------------------------------

-- $FF is "the player"; $8000-$800F name a var holding the real id; anything
-- else is a local object id.
local PLAYER_OBJECT = 0xFF

local function objectId(ctx, id)
  id = tonumber(id) or 0
  if isVarId(id) then id = getVar(ctx.save, id) end
  if id == PLAYER_OBJECT or id == 0 then return nil end
  return id
end

function Commands.g3_lock(ctx) ctx.g3Locked = true end
function Commands.g3_release(ctx) ctx.g3Locked = nil end

local DIRECTIONS = { [1] = "down", [2] = "up", [3] = "left", [4] = "right" }

function Commands.g3_move(ctx, target, movementLabel)
  local pool = ctx.game and ctx.game.data and ctx.game.data.map_scripts
  local rows = pool and pool.movements and pool.movements[movementLabel]
  if not rows then return end
  local index = objectId(ctx, target)

  -- Consecutive identical steps are coalesced into one run, exactly as the
  -- Gen 2 path does: the engine's move verbs take a count, and issuing eight
  -- one-tile moves makes the NPC stutter between each.
  local pending, count = nil, 0
  local function flush()
    if not (pending and count > 0) then pending, count = nil, 0 return end
    if index then Commands.move_npc(ctx, index, pending, count)
    else Commands.move_player(ctx, pending, count) end
    pending, count = nil, 0
  end

  for _, row in ipairs(rows) do
    local name = row[1]
    local dir = name:match("^walk_[%a_]-_?(down)$") or name:match("^walk_.*(up)$")
                or name:match("^walk_.*(left)$") or name:match("^walk_.*(right)$")
    if name:match("^walk_") and dir then
      if pending == dir then count = count + 1
      else flush(); pending, count = dir, 1 end
    elseif name:match("^face_") then
      flush()
      local facing = name:match("^face_(%a+)$")
      if facing then
        if index then Commands.face_object(ctx, index, facing)
        else Commands.face(ctx, facing) end
      end
    elseif name:match("^delay_") then
      flush()
      Commands.wait(ctx, tonumber(name:match("(%d+)$")) or 1)
    else
      -- an action the port has no equivalent for: skip the step rather than
      -- guess at it, and let the rest of the movement still play
      flush()
    end
  end
  flush()
end

function Commands.g3_turn(ctx, target, direction)
  local index = objectId(ctx, target)
  local facing = DIRECTIONS[tonumber(direction) or 0]
  if not facing then return end
  if index then Commands.face_object(ctx, index, facing)
  else Commands.face(ctx, facing) end
end

function Commands.g3_show_object(ctx, target)
  local index = objectId(ctx, target)
  if index then Commands.show_object(ctx, index) end
end

function Commands.g3_hide_object(ctx, target)
  local index = objectId(ctx, target)
  if index then Commands.hide_object(ctx, index) end
end

function Commands.g3_place(ctx, target, x, y)
  local index = objectId(ctx, target)
  if index then Commands.place_npc(ctx, index, tonumber(x), tonumber(y)) end
end

-- The "perm" form writes the object's TEMPLATE position, which is where it
-- respawns from on the next map load; the port keeps that on the save so a
-- staged cutscene survives walking out and back in.
function Commands.g3_place_perm(ctx, target, x, y)
  Commands.g3_place(ctx, target, x, y)
  local save = ctx.save
  local mapId = ctx.mapId or (ctx.overworld and ctx.overworld.map and ctx.overworld.map.id)
  if not (save and mapId) then return end
  save.gen3ObjectHomes = save.gen3ObjectHomes or {}
  local perMap = save.gen3ObjectHomes[mapId] or {}
  save.gen3ObjectHomes[mapId] = perMap
  perMap[tonumber(target) or 0] = { x = tonumber(x), y = tonumber(y) }
end

function Commands.g3_movement_type(ctx, target, movementType)
  local index = objectId(ctx, target)
  local npc = index and ctx.overworld and ctx.overworld.npcs
              and ctx.overworld.npcs[index]
  if npc then npc.gen3MovementType = tonumber(movementType) end
end

-- ---------------------------------------------------------------------------
-- items, money, party
-- ---------------------------------------------------------------------------

local function itemId(n) return ("ITEM_G3_%03d"):format(tonumber(n) or 0) end
Gen3Commands.itemId = itemId

function Commands.g3_give_item(ctx, item, quantity)
  Commands.give_item(ctx, itemId(item), tonumber(quantity) or 1)
  setVar(ctx.save, VAR_RESULT, 1)
  setResult(ctx, 1)
end

function Commands.g3_take_item(ctx, item, quantity)
  Commands.take_item(ctx, itemId(item), tonumber(quantity) or 1)
  setVar(ctx.save, VAR_RESULT, 1)
  setResult(ctx, 1)
end

local function bagCount(ctx, item)
  local bag = ctx.save and ctx.save.bag
  if not bag then return 0 end
  local want, total = itemId(item), 0
  for _, pocket in pairs(bag) do
    if type(pocket) == "table" then
      for _, slot in ipairs(pocket) do
        if slot.id == want then total = total + (slot.count or 1) end
      end
    end
  end
  return total
end

function Commands.g3_check_item(ctx, item, quantity)
  local has = bagCount(ctx, item) >= (tonumber(quantity) or 1)
  setVar(ctx.save, VAR_RESULT, has and 1 or 0)
  setResult(ctx, has and 1 or 0)
end

function Commands.g3_check_item_space(ctx)
  setVar(ctx.save, VAR_RESULT, 1)
  setResult(ctx, 1)
end

function Commands.g3_give_pokemon(ctx, species, level, item)
  Commands.give_pokemon(ctx, tonumber(species), tonumber(level), itemId(item))
  setVar(ctx.save, VAR_RESULT, 0)      -- 0 = "it went to the party"
  setResult(ctx, 0)
end

function Commands.g3_give_egg(ctx, species)
  Commands.give_pokemon(ctx, tonumber(species), 5, nil, { egg = true })
  setVar(ctx.save, VAR_RESULT, 0)
end

function Commands.g3_check_party_move(ctx, move)
  local party = ctx.save and ctx.save.party or {}
  local want, slot = tonumber(move), 6
  for index, mon in ipairs(party) do
    for _, m in ipairs(mon.moves or {}) do
      if m == want or (type(m) == "table" and m.id == want) then slot = index - 1 break end
    end
  end
  setVar(ctx.save, VAR_RESULT, slot)
end

function Commands.g3_add_money(ctx, amount)
  Commands.give_money(ctx, tonumber(amount) or 0)
end

function Commands.g3_check_money(ctx, amount)
  local money = (ctx.save and ctx.save.money) or 0
  local ok = money >= (tonumber(amount) or 0)
  setVar(ctx.save, VAR_RESULT, ok and 1 or 0)
  setResult(ctx, ok and 1 or 0)
end

function Commands.g3_check_coins(ctx, var)
  setVar(ctx.save, var, (ctx.save and ctx.save.coins) or 0)
end

function Commands.g3_add_coins(ctx, amount)
  local save = ctx.save
  if save then save.coins = math.max(0, (save.coins or 0) + (tonumber(amount) or 0)) end
end

function Commands.g3_mart(ctx, listPointer)
  Commands.open_mart(ctx, listPointer)
end

-- ---------------------------------------------------------------------------
-- battles
-- ---------------------------------------------------------------------------

local function trainerFlag(n) return ("FLAG_G3_TRAINER_%04X"):format(tonumber(n) or 0) end
Gen3Commands.trainerFlag = trainerFlag

function Commands.g3_trainer_battle(ctx, kind, trainerId)
  ctx.g3Trainer = tonumber(trainerId)
  ctx.g3TrainerKind = tonumber(kind)
  Commands.start_battle(ctx, { trainer = tonumber(trainerId), gen3 = true })
end

function Commands.g3_do_trainer_battle(ctx)
  if ctx.g3Trainer then
    Commands.start_battle(ctx, { trainer = ctx.g3Trainer, gen3 = true })
  end
end

function Commands.g3_check_trainer_flag(ctx, trainerId)
  Commands.check_flag(ctx, trainerFlag(trainerId))
  setResult(ctx, ctx.lastCheck and 1 or 0)
end

function Commands.g3_set_trainer_flag(ctx, trainerId)
  Commands.set_flag(ctx, trainerFlag(trainerId))
end

function Commands.g3_clear_trainer_flag(ctx, trainerId)
  Commands.clear_flag(ctx, trainerFlag(trainerId))
end

function Commands.g3_set_wild(ctx, species, level, item)
  ctx.g3Wild = { species = tonumber(species), level = tonumber(level),
                 item = item and itemId(item) or nil }
end

function Commands.g3_wild_battle(ctx)
  if ctx.g3Wild then Commands.start_battle(ctx, ctx.g3Wild) end
end

-- ---------------------------------------------------------------------------
-- warps
-- ---------------------------------------------------------------------------

local function mapKey(group, number)
  return ("MAP_G%02d_N%02d"):format(tonumber(group) or 0, tonumber(number) or 0)
end
Gen3Commands.mapKey = mapKey

function Commands.g3_warp(ctx, group, number, warpId, x, y)
  local id = mapKey(group, number)
  -- warp id $FF means "use the x/y given"; anything else names a warp on the
  -- destination map and the coordinates are ignored
  if (tonumber(warpId) or 0xFF) ~= 0xFF then
    Commands.warp(ctx, id, nil, nil, nil, { warp = tonumber(warpId) })
  else
    Commands.warp(ctx, id, tonumber(x), tonumber(y))
  end
end

function Commands.g3_set_warp(ctx, group, number, warpId, x, y)
  ctx.save = ctx.save or {}
  ctx.save.gen3Respawn = { map = mapKey(group, number), warp = tonumber(warpId),
                           x = tonumber(x), y = tonumber(y) }
end

function Commands.g3_set_respawn(ctx, index)
  local save = ctx.save
  if save then save.gen3RespawnIndex = tonumber(index) end
end

-- ---------------------------------------------------------------------------
-- world
-- ---------------------------------------------------------------------------

function Commands.g3_set_metatile(ctx, x, y, tile, impassable)
  local ow = ctx.overworld
  if not (ow and ow.map and ow.map.setBlock) then return end
  ow.map:setBlock(tonumber(x), tonumber(y), tonumber(tile), tonumber(impassable) ~= 0)
end

function Commands.g3_set_layout(ctx, layoutId)
  local ow = ctx.overworld
  if ow and ow.map then ow.map.gen3LayoutOverride = tonumber(layoutId) end
end

function Commands.g3_door(ctx, action, x, y)
  local ow = ctx.overworld
  if not ow then return end
  if action == "open" or action == "set_open" then
    if ow.openDoorAt then ow:openDoorAt(tonumber(x), tonumber(y)) end
  elseif ow.closeDoorAt then
    ow:closeDoorAt(tonumber(x), tonumber(y))
  end
end

function Commands.g3_weather(ctx, weather)
  local ow = ctx.overworld
  if ow then ow.gen3Weather = tonumber(weather) end
end

function Commands.g3_field_effect(ctx, id) ctx.g3FieldEffect = tonumber(id) end
function Commands.g3_field_effect_arg(ctx, slot, value)
  ctx.g3FieldEffectArgs = ctx.g3FieldEffectArgs or {}
  ctx.g3FieldEffectArgs[tonumber(slot) or 0] = tonumber(value)
end

function Commands.g3_game_stat(ctx, stat)
  local save = ctx.save
  if not save then return end
  save.gen3Stats = save.gen3Stats or {}
  local key = tonumber(stat) or 0
  save.gen3Stats[key] = (save.gen3Stats[key] or 0) + 1
end

function Commands.g3_create_vobject(ctx, graphicsId, localId, x, y)
  ctx.g3VObjects = ctx.g3VObjects or {}
  ctx.g3VObjects[tonumber(localId) or 0] =
    { graphicsId = tonumber(graphicsId), x = tonumber(x), y = tonumber(y) }
end

function Commands.g3_turn_vobject() end

-- ---------------------------------------------------------------------------
-- menus, buffers, specials
-- ---------------------------------------------------------------------------

function Commands.g3_multichoice(ctx, listId, _ignoreB, default)
  -- The choice lists live in a table the extractor does not resolve yet, so
  -- there is nothing to show.  Write the default (or 127 = "cancelled", which
  -- is what pressing B stores) so the compare that follows takes a real branch
  -- instead of reading a stale VAR_RESULT from an unrelated check.
  setVar(ctx.save, VAR_RESULT, tonumber(default) or 0x7F)
  setResult(ctx, 1)
  Logger.debug("gen3: multichoice list %s not resolved", tostring(listId))
end

function Commands.g3_buffer(ctx, slot, kind, value, quantity)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  local data = game.data
  local text
  if kind == "item" then
    local item = data and data.items and data.items[itemId(value)]
    text = item and item.name
  elseif kind == "species" then
    local list = data and data.pokemon
    text = list and list[tonumber(value)] and list[tonumber(value)].name
  elseif kind == "move" then
    local moves = data and data.moves
    text = moves and moves[tonumber(value)] and moves[tonumber(value)].name
  elseif kind == "number" then
    text = tostring(getVar(ctx.save, value))
  elseif kind == "text" then
    text = data and data.text and data.text[value]
  end
  if text and quantity and (tonumber(quantity) or 1) > 1 then text = text .. "s" end
  game.stringBuffers[(tonumber(slot) or 0) + 1] = text or ""
end

function Commands.g3_show_mon_pic(ctx, species) ctx.g3MonPic = tonumber(species) end
function Commands.g3_hide_mon_pic(ctx) ctx.g3MonPic = nil end

-- `special` calls one of 530 native functions by index.  None are implemented
-- yet; the index is recorded so a missing one is diagnosable from a log rather
-- than showing up as a scene that quietly does nothing.  When a special is
-- given a destination var, VAR_RESULT is left alone rather than zeroed, so a
-- following compare reads the value the script last set rather than a fake 0.
Gen3Commands.SPECIALS = {}

function Commands.g3_special(ctx, index, destVar)
  local id = tonumber(index) or 0
  local fn = Gen3Commands.SPECIALS[id]
  if fn then
    local result = fn(ctx)
    if destVar then setVar(ctx.save, destVar, tonumber(result) or 0) end
    return
  end
  ctx.g3UnhandledSpecials = ctx.g3UnhandledSpecials or {}
  if not ctx.g3UnhandledSpecials[id] then
    ctx.g3UnhandledSpecials[id] = true
    Logger.debug("gen3: special %d not implemented", id)
  end
end

function Commands.g3_std(ctx, index)
  Logger.debug("gen3: std %s has no lowering", tostring(index))
end

function Commands.g3_std_obtain_item(ctx)
  -- Std_ObtainItem / Std_FindItem both end by writing whether the item fit.
  -- The bag has no cap in this port, so it always did.
  setVar(ctx.save, VAR_RESULT, 1)
  setResult(ctx, 1)
end

return Gen3Commands
