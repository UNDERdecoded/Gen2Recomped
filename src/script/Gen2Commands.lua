
-- Runtime commands for the Gen2 script VM.
--
-- Gen2ScriptVM lowers ROM bytecode into ScriptRunner rows.  Most rows are
-- ordinary engine commands (show_text, set_flag, warp, ...); the handful that
-- have no Gen1 equivalent live here under a `g2_` prefix so they never collide
-- with the hand-ported vocabulary in data/scripts/.
--
-- The two that matter structurally are g2_call and g2_return: Gen2's `scall`
-- pushes a return address and `end` pops it, which ScriptRunner's flat program
-- counter has no notion of.  The compiler emits an explicit push/jump pair and
-- `end` becomes g2_return, so a script that is scall'd from three places still
-- exists once in the compiled row list.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen2Commands = {}

local function scriptVar(ctx)
  return ctx.g2Var or 0
end

-- A text const resolved to finished text, the way show_text would print it.
-- BattleState:say takes text that is already expanded, not a label.
local function resolvedText(ctx, textId)
  local data = ctx.game.data
  local text = data.text[textId]
  if not text and ctx.overworld then
    text = data:resolveText(ctx.overworld.map.def.label, textId)
  end
  text = text or textId
  if type(text) ~= "string" then return nil end
  return require("src.render.TextBox").substitute(ctx.game, text)
end

-- ---------------------------------------------------------------------------
-- control flow
-- ---------------------------------------------------------------------------

function Commands.g2_call(ctx, returnLabel)
  ctx.g2Stack = ctx.g2Stack or {}
  ctx.g2Stack[#ctx.g2Stack + 1] = returnLabel
end

function Commands.g2_return(ctx)
  local stack = ctx.g2Stack
  if stack and #stack > 0 then return table.remove(stack) end
  return "end"
end

-- Script_endifjustbattled: ends the script when it was re-entered straight
-- from a won battle rather than by talking to the trainer afterwards.
function Commands.g2_endifjustbattled(ctx)
  if ctx.justBattled then return "end" end
end

-- Script_variablesprite: wVariableSprites[slot] = sprite.  Object events whose
-- sprite byte is $F0 or more read the slot back, so any object already built
-- from that slot has to pick the new sheet up.
function Commands.g2_variablesprite(ctx, slot, sprite)
  slot, sprite = tonumber(slot), tonumber(sprite)
  if not (ctx.save and slot and sprite) then return end
  ctx.save.gen2VarSprites = ctx.save.gen2VarSprites or {}
  ctx.save.gen2VarSprites[slot] = sprite
  local ow = ctx.overworld
  if ow and ow.refreshVariableSprite then ow:refreshVariableSprite(slot) end
end

local COMPARE = {
  eq = function(a, b) return a == b end,
  ne = function(a, b) return a ~= b end,
  gt = function(a, b) return a > b end,
  lt = function(a, b) return a < b end,
}

function Commands.g2_compare(ctx, op, value)
  local fn = COMPARE[op]
  ctx.lastCheck = fn and fn(scriptVar(ctx), value or 0) or false
end

function Commands.g2_setvar(ctx, value)
  ctx.g2Var = value or 0
end

function Commands.g2_addvar(ctx, value)
  ctx.g2Var = scriptVar(ctx) + (value or 0)
end

function Commands.g2_random(ctx, bound)
  ctx.g2Var = math.random(0, math.max((bound or 1) - 1, 0))
end

-- ---------------------------------------------------------------------------
-- map scenes
--
-- A scene id is the ROM's per-map "which cutscene state am I in" byte
-- (wMapScenes).  Callbacks and coord events are gated on it, so it has to
-- persist in the save exactly like an event flag.
-- ---------------------------------------------------------------------------

local function sceneStore(ctx)
  ctx.save.g2Scenes = ctx.save.g2Scenes or {}
  return ctx.save.g2Scenes
end

local function sceneMapId(ctx, mapId)
  if type(mapId) == "string" and mapId ~= "" then return mapId end
  return ctx.overworld and ctx.overworld.map and ctx.overworld.map.id
end

function Gen2Commands.getScene(save, mapId)
  return (save.g2Scenes or {})[mapId] or 0
end

function Commands.g2_set_scene(ctx, mapId, scene)
  local id = sceneMapId(ctx, mapId)
  if id then sceneStore(ctx)[id] = scene or 0 end
end

function Commands.g2_check_scene(ctx, mapId)
  local id = sceneMapId(ctx, mapId)
  ctx.g2Var = id and Gen2Commands.getScene(ctx.save, id) or 0
  ctx.lastCheck = ctx.g2Var ~= 0
end

-- ---------------------------------------------------------------------------
-- objects
--
-- appear/disappear are the transient half of Gen2 visibility: the persistent
-- half is a plain setevent/clearevent that the same script almost always runs
-- alongside them, and set_flag already re-syncs the live map.
-- ---------------------------------------------------------------------------

-- Gen2 script object ids are not list positions.  Every map's object constants
-- are emitted with `const_def 2`, so the first object_event is id 2, and the
-- ids below that are engine slots: 0 is the player.  Translating an id back to
-- a 1-based index into map.def.objects is therefore `id - 1`, and an id of 0
-- has to be steered at the player instead of an NPC -- Elm's lab walks you to
-- the professor with `applymovement 0`, which silently did nothing while these
-- ids were treated as plain list positions.
local GEN2_FIRST_OBJECT_ID = 2

local function isPlayerId(index)
  return index == 0 or index == "player"
end

local function objectSlot(index)
  if type(index) ~= "number" or index < GEN2_FIRST_OBJECT_ID then return nil end
  return index - 1
end

local function objectByIndex(ctx, index)
  local slot = objectSlot(index)
  if not slot then return nil, nil end
  local ow = ctx.overworld
  if not ow or not ow.map or not ow.map.def then return nil, nil end
  local objects = ow.map.def.objects
  if type(objects) ~= "table" then return nil, nil end
  return objects[slot], ow.map.id, slot
end

-- LAST_TALKED ($fe): `disappear LAST_TALKED` is how RockSmashScript removes
-- the rock you just smashed and how a dozen NPCs walk off after their line.
-- It is not a list position, so objectSlot rejected it and the row silently
-- did nothing -- the smashed rock stayed put.
local GEN2_LAST_TALKED = 0xFE

function Commands.g2_object(ctx, index, visible)
  local obj, mapId
  if index == GEN2_LAST_TALKED or index == "last" then
    local npc = ctx.npc
    obj = npc and npc.def
    mapId = ctx.overworld and ctx.overworld.map and ctx.overworld.map.id
  else
    obj, mapId = objectByIndex(ctx, index)
  end
  if not obj or not mapId then return end
  local OverworldState = require("src.world.OverworldController")
  local name = OverworldState.objectToggleKey(obj)
  if not name then return end
  if visible then
    Commands.show_object(ctx, mapId, name)
  else
    Commands.hide_object(ctx, mapId, name)
  end
end

-- CheckPartyMove (engine/overworld/overworld.asm): scan the party for the
-- move, leaving carry set when nobody has it.  HasRockSmash and friends
-- report that through wScriptVar as 1 = lacks, 0 = has, which the std script
-- then branches on -- so without this every `AskRockSmashScript` fell through
-- to the yes/no prompt whether or not the party could smash anything.
function Commands.g2_party_move(ctx, moveId)
  local ow = ctx.overworld
  local mon = ow and ow.partyKnows and ow:partyKnows(moveId) or nil
  ctx.g2FieldMon = mon
  ctx.g2Var = mon and 0 or 1
  ctx.lastCheck = mon ~= nil
end

-- TryStrengthOW: 1 = no STRENGTH mon or no PLAINBADGE (BouldersMayMoveText),
-- 2 = BIKEFLAGS_STRENGTH_ACTIVE already set (BouldersMoveText), 0 = ask.
function Commands.g2_try_strength(ctx)
  local ow = ctx.overworld
  local mon = ow and ow.partyKnows and ow:partyKnows("STRENGTH") or nil
  ctx.g2FieldMon = mon
  if not mon then
    ctx.g2Var = 1
  elseif ow.strengthActive then
    ctx.g2Var = 2
  else
    ctx.g2Var = 0
  end
  ctx.lastCheck = ctx.g2Var ~= 0
end

-- SetStrengthFlag: arms BIKEFLAGS_STRENGTH_ACTIVE, the sole gate
-- .CheckStrengthBoulder reads, and loads the mon's nickname for the text.
function Commands.g2_strength_on(ctx)
  local ow = ctx.overworld
  if ow then ow.strengthActive = true end
  Commands.g2_party_nickname(ctx)
end

-- GetPartyNickname: copies wCurPartyMon's nickname into wStringBuffer1, which
-- the following text_ram prints.
function Commands.g2_party_nickname(ctx)
  local mon = ctx.g2FieldMon
  if not mon then return end
  local def = ctx.game.data.pokemon[mon.species]
  ctx.game.stringBuffer = mon.nickname or (def and def.name) or mon.species
end

-- Movement is Gen2's second bytecode language: applymovement points at a list
-- of step/turn commands terminated by step_end.  Everything the overworld can
-- actually animate is a directional step or a head turn, so collapse the list
-- into runs of walk_npc / face_object and drop the presentation-only rows
-- (sliding flags, emotes, fixed facing).
local MOVEMENT_STEP = {
  slow_step = true, step = true, big_step = true, slow_slide_step = true,
  slide_step = true, fast_slide_step = true, slow_jump_step = true,
  jump_step = true, fast_jump_step = true,
}
-- `turn_step` reads like a step but is not one: Movement_turn_step_down
-- (1:$538F) is byte-for-byte Movement_turn_head_down, and
-- ApplyMovementToFollower's `cp 8 / ret c` drops movement indices 0-7 --
-- turn_head AND turn_step -- precisely because neither moves the object.
-- Walking those rows is what sent the rival through the wall instead of
-- turning him back to the lab window.
local MOVEMENT_TURN = {
  turn_head = true, turn_in = true, turn_away = true,
  turn_step = true, turn_waterfall = true,
}

-- Commands.face turns the NPC being talked to; Gen2's object id 0 is the player.
local function facePlayer(ctx, dir)
  local player = ctx.overworld and ctx.overworld.player
  if player then player.facing = dir end
end

local function movementParts(name)
  local verb, dir = name:match("^(.-)_(down)$")
  if not verb then verb, dir = name:match("^(.-)_(up)$") end
  if not verb then verb, dir = name:match("^(.-)_(left)$") end
  if not verb then verb, dir = name:match("^(.-)_(right)$") end
  return verb, dir
end

-- Follow (StartFollow 1:$5779, ApplyMovementToFollower 1:$5457,
-- GetFollowerNextMovementIndex 1:$5485).  Every step the LEADER is given is
-- pushed onto wFollowMovementQueue, and the follower pops that queue one beat
-- later -- so the follower retraces the leader's exact path, always exactly
-- one tile behind.  It does NOT walk alongside in lockstep, which is what the
-- port did and what made the Cherrygrove guide's escort read wrong.
--
-- QueueFollowerFirstStep (2:$4A7A) seeds the queue with the single step that
-- closes the gap -- x is compared before y -- so the follower's opening move
-- is onto the tile the leader is vacating.  Turns are never queued
-- (ApplyMovementToFollower's `cp 8 / ret c` drops every movement index below
-- the step block), so only steps count here.
local function followerFirstStep(follower, leader)
  if leader.cellX < follower.cellX then return "left" end
  if leader.cellX > follower.cellX then return "right" end
  if leader.cellY < follower.cellY then return "up" end
  if leader.cellY > follower.cellY then return "down" end
  return nil
end

-- The whole follower run goes in up front: updateScriptMoves starts every
-- idle entity's next queued move on the same frame, so a sequence shifted by
-- one step keeps the pair exactly one tile apart without the script having to
-- interleave the two walks.
local function queueFollower(ow, follower, leader, dirs)
  local first = followerFirstStep(follower, leader)
  local steps = {}
  if first then steps[1] = first end
  -- ...then the leader's own steps, minus however many the seed consumed
  for i = 1, #dirs - #steps do steps[#steps + 1] = dirs[i] end

  local run, runDir = 0, nil
  for _, dir in ipairs(steps) do
    if runDir and runDir ~= dir then
      ow:scriptMove(follower, runDir, run)
      run = 0
    end
    runDir, run = dir, run + 1
  end
  if runDir and run > 0 then ow:scriptMove(follower, runDir, run) end
end

function Commands.g2_move(ctx, target, movementLabel)
  local data = ctx.game and ctx.game.data
  local store = data and data.map_scripts
  local rows = store and store.movements and store.movements[movementLabel]
  if not rows then return end

  local index
  if isPlayerId(target) then
    index = nil
  elseif type(target) == "number" then
    local _, _, slot = objectByIndex(ctx, target)
    if not slot then return end
    index = slot
  else
    local npc = ctx.npc
    index = npc and npc.def and npc.def.index or nil
  end

  local ow = ctx.overworld
  if ow and ctx.g2FollowLeader ~= nil and ctx.g2FollowLeader == target then
    local t = ctx.g2FollowTarget
    local follower
    if isPlayerId(t) then
      follower = ow.player
    elseif type(t) == "number" then
      local slot = objectSlot(t)
      follower = slot and ow:npcByIndex(slot) or nil
    end
    local leader = index and ow:npcByIndex(index) or ow.player
    if follower and leader then
      local dirs = {}
      for _, row in ipairs(rows) do
        local verb, dir = movementParts(row[1])
        if verb and dir and MOVEMENT_STEP[verb] then dirs[#dirs + 1] = dir end
      end
      queueFollower(ow, follower, leader, dirs)
    end
  end

  local pending, pendingDir = 0, nil
  -- movement_fix_facing pins the sprite's frame so a scripted walk keeps
  -- looking the way it started (the Ilex Forest bird, the gatehouse guards).
  -- The port has no per-step facing lock, so re-assert the pinned facing
  -- after each run of steps instead.
  local fixedFacing = nil
  local function entity()
    if index then return ow and ow:npcByIndex(index) end
    return ow and ow.player
  end
  local function flush()
    if pending > 0 and pendingDir then
      if index then
        Commands.move_npc(ctx, index, pendingDir, pending)
      else
        Commands.move_player(ctx, pendingDir, pending)
      end
      if fixedFacing then
        local e = entity()
        if e then e.facing = fixedFacing end
      end
    end
    pending, pendingDir = 0, nil
  end

  for _, row in ipairs(rows) do
    local verb, dir = movementParts(row[1])
    if verb and dir and MOVEMENT_STEP[verb] then
      if pendingDir and pendingDir ~= dir then flush() end
      pendingDir = dir
      pending = pending + 1
    elseif verb and dir and MOVEMENT_TURN[verb] then
      flush()
      if index then
        Commands.face_object(ctx, index, dir)
      else
        facePlayer(ctx, dir)
      end
    elseif row[1] == "tree_shake" or row[1] == "rock_smash" then
      flush()
      Commands.g2_shake(ctx, index)
    elseif row[1] == "fix_facing" then
      flush()
      local e = entity()
      fixedFacing = e and e.facing or nil
    elseif row[1] == "remove_fixed_facing" then
      flush()
      fixedFacing = nil
    elseif row[1] == "set_sliding" or row[1] == "remove_sliding" then
      -- movement_set_sliding drops the walk animation so the object glides,
      -- which is how the Ice Path boulders and the Kimono Girls move.
      flush()
      local e = entity()
      if e then e.sliding = row[1] == "set_sliding" or nil end
    else
      -- movement_step_sleep <n>: the extractor bakes the operand into the
      -- name, so the row carries no argument to read
      local sleep = tonumber(row[1]:match("^step_sleep_(%d+)$"))
      if sleep then
        flush()
        Commands.wait(ctx, sleep * 16)
      end
    end
  end
  flush()
end

-- The one movement row that animates without moving: the object rattles in
-- place and the script waits it out, like every other applymovement.
function Commands.g2_shake(ctx, index)
  local ow = ctx.overworld
  local npc = ow and index and ow:npcByIndex(index) or nil
  if not npc or not npc.shake then return end
  local runner = ctx.runner
  npc:shake(32, function() runner:resume() end)
  runner:yield()
end

local DIRS = { [0] = "down", "up", "left", "right" }

function Commands.g2_turn(ctx, index, facing)
  local dir = DIRS[facing or 0] or "down"
  if isPlayerId(index) then
    facePlayer(ctx, dir)
    return
  end
  local _, _, slot = objectByIndex(ctx, index)
  if slot then Commands.face_object(ctx, slot, dir) end
end

function Commands.g2_place(ctx, index, x, y)
  local obj, _, slot = objectByIndex(ctx, index)
  if obj then Commands.place_npc(ctx, slot, x, y) end
end

-- showemote emote, object, frames -- the alert bubble that fires just before
-- the Cherrygrove rival and the Route 29 catching tutorial run at you
local EMOTES = { [0] = "shock", "question", "happy", "sad", "heart", "bolt", "sleep", "fish" }

function Commands.g2_emote(ctx, index, emote, frames)
  local bubble = EMOTES[emote or 0] or "shock"
  local target = isPlayerId(index) and "player" or select(3, objectByIndex(ctx, index))
  if not target then return end
  Commands.emote(ctx, target, bubble, frames or 15)
end

-- ---------------------------------------------------------------------------
-- battles
-- ---------------------------------------------------------------------------

function Commands.g2_load_trainer(ctx, group, id)
  ctx.g2Trainer = { group = group, id = id }
  ctx.g2Wild = nil
end

function Commands.g2_load_wild(ctx, species, level)
  ctx.g2Wild = { species = species, level = level }
  ctx.g2Trainer = nil
end

function Commands.g2_winloss(ctx, winText, lossText)
  ctx.g2WinText, ctx.g2LossText = winText, lossText
end

-- wBattleResult -> wScriptVar, the way Script_startbattle leaves it
-- (`ld a, [wBattleResult] / and $3f / ld [wScriptVar], a`): WIN 0, LOSE 1,
-- DRAW 2.  DRAW is "nobody won" -- the player ran, or the wild mon fled.
-- Catching sets a HIGH bit of wBattleResult that `and $3f` strips, so a
-- caught mon still reads as a win.
Commands.G2_BATTLE_RESULT = { win = 0, caught = 0, lose = 1, run = 2 }

function Commands.g2_start_battle(ctx)
  local wild, trainer = ctx.g2Wild, ctx.g2Trainer
  local battleType = ctx.g2BattleType
  -- DoBattleTransitionAndInitBattleVariables clears wBattleType, so it only
  -- ever applies to the one battle the loadvar preceded
  ctx.g2BattleType = nil
  if wild then
    ctx.g2Wild = nil
    Commands.start_battle(ctx, "wild", wild.species, wild.level,
      { shiny = battleType == Commands.G2_BATTLETYPE_SHINY })
  elseif trainer then
    -- winlosstext's first pointer is the beaten trainer's own line, and
    -- TrainerBattleVictory prints it ON the battle screen just before
    -- MoneyForWinningText.  Leaving it to the trailing reloadmapafterbattle
    -- put the rival's "…Humph!" after the prize money and after the battle
    -- had already torn down.
    local won = ctx.g2WinText
    ctx.g2WinText = nil
    Commands.start_battle(ctx, "trainer", trainer.group, trainer.id,
      { endBattleText = won and resolvedText(ctx, won) or nil })
  else
    return
  end
  -- wBattleResult feeds wScriptVar, which is what the `ifequal $2` some
  -- scripts put after a startbattle branches on: 0 won, 1 lost, 2 drew.
  ctx.g2Var = Commands.G2_BATTLE_RESULT[ctx.lastBattleResult] or 0
  -- ...and `iftrue`/`iffalse` read the SAME wScriptVar, so after a Gen2
  -- startbattle they mean "did NOT win", not "won".  Commands.start_battle
  -- left lastCheck set the Gen 1 way (`result == "win"`), which is exactly
  -- inverted: the Mahogany hideout Electrodes (RocketElectrode1-3,
  -- 45:$4DB9/$4DE4/$4E0F) are `startbattle` + `iftrue .done` + `disappear`,
  -- so running away made them vanish and beating them left them standing.
  ctx.lastCheck = ctx.g2Var ~= 0
  -- A loss whites the player out to a Pokemon Center, so the rest of the
  -- script -- the win text, the badge, the TM -- must never run.  Running
  -- from or catching a scripted wild mon still continues it.
  if ctx.lastBattleResult == "lose" then return "end" end
end

function Commands.g2_after_battle(ctx)
  if ctx.g2WinText then Commands.show_text(ctx, ctx.g2WinText) end
end

-- ---------------------------------------------------------------------------
-- odds and ends
-- ---------------------------------------------------------------------------

function Commands.g2_warp(ctx, mapId, x, y, facing)
  if type(mapId) ~= "string" or mapId == "" then return end
  Commands.warp(ctx, mapId, x, y, facing)
end

-- `blackoutmod <map>`: the blackout spawn.  GetWhiteoutSpawn resolves the
-- named map through SpawnPoints (map_scripts.spawns.points) for the arrival
-- cell, so a map with no spawn row leaves the old point standing rather than
-- stranding the player on coordinates the ROM never had.
function Commands.g2_blackout_point(ctx, mapId)
  if type(mapId) ~= "string" or mapId == "" then return end
  local pool = ctx.game.data.map_scripts
  local point = pool and pool.spawns and pool.spawns.points
                and pool.spawns.points[mapId]
  if not point then
    Logger.warn("gen2 script: no spawn point for %s", mapId)
    return
  end
  ctx.save.lastHeal = { map = mapId, x = point.x, y = point.y }
end

-- yesorno reuses the box the preceding writetext opened; the compiler hands
-- us that text const so the prompt reads the same as the ROM's
function Commands.g2_yesno(ctx, textId)
  -- ask() parks the runner and writes the answer to ctx.lastCheck itself
  Commands.ask(ctx, textId)
end

-- `cry <species>`: PlayMonCry, standalone.  Unlike Gen1's play_cry this
-- must not arm the next text box (see Gen2ScriptVM's L.cry).
function Commands.g2_cry(ctx, species)
  require("src.core.Sound").playCry(ctx.game.data, species)
end

-- `pokemart MARTTYPE_*, MART_*`: the item list lives in map_scripts.marts,
-- read straight out of the ROM's Marts pointer table.
function Commands.g2_mart(ctx, index)
  local pool = ctx.game.data.map_scripts
  local stock = pool and pool.marts and pool.marts[index]
  if type(stock) ~= "table" or #stock == 0 then
    Logger.warn("gen2 script: no mart %s", tostring(index))
    return
  end
  local runner = ctx.runner
  local Screens = require("src.ui.Screens")
  Screens.push(ctx.game, "ShopMenu", stock, function() runner:resume() end)
  runner:yield()
end

-- checktime's operand is the MORN/DAY/NITE bitmask the overworld already
-- filters time-restricted objects with.
local TOD_BITS = { MORNING = 1, MORN = 1, DAY = 2, NIGHT = 4, NITE = 4 }

function Commands.g2_checktime(ctx, mask)
  local ow = ctx.overworld
  local tod = ow and ow.timeOfDay and ow:timeOfDay() or "DAY"
  local bit = TOD_BITS[tod] or TOD_BITS.DAY
  ctx.lastCheck = math.floor((mask or 0) / bit) % 2 == 1
end

function Commands.g2_false(ctx)
  ctx.lastCheck = false
end

-- ---------------------------------------------------------------------------
-- money, bag and party predicates
-- ---------------------------------------------------------------------------

-- CheckMoney writes wScriptVar, not the carry: 0 richer, 1 exact, 2 short.
-- Every caller branches with `ifequal 2`, so lastCheck alone is not enough.
function Commands.g2_check_money(ctx, amount)
  local have = ctx.save.money or 0
  amount = amount or 0
  ctx.g2Var = have > amount and 0 or (have == amount and 1 or 2)
  ctx.lastCheck = have >= amount
end

function Commands.g2_pocket_full(ctx)
  local Bag = require("src.inventory.Bag")
  -- In Gen2, pocketisfull checks the current item's pocket, not total bag
  -- capacity (GetPocketCapacity 03:$528E).  Without per-item context here,
  -- approximate by checking whether ANY non-TM/HM pocket has 20 items.
  -- give_item's Bag.add enforces the real per-pocket limit.
  local save = ctx.save
  local data = ctx.game and ctx.game.data or nil
  local full = Bag.pocketSlots(save, "ITEM",     data) >= 20
            or Bag.pocketSlots(save, "BALL",     data) >= 20
            or Bag.pocketSlots(save, "KEY_ITEM", data) >= 20
  ctx.g2Var = full and 1 or 0
  ctx.lastCheck = full
end

-- `giveitem item, qty` (ReceiveItem) is SILENT: it fills the bag and sets the
-- carry, nothing else.  The jingle and the "received" line belong to whoever
-- called it -- `jumpstd receiveitemstd` before it, or `verbosegiveitem`
-- instead of it.  Routing this to Gen1's give_item played a second fanfare
-- over the script's own `playsound` and opened a box the ROM never shows
-- (MrPokemon's MYSTERY EGG, Elm's aide and her POKe BALLs).
function Commands.g2_giveitem(ctx, itemId, count)
  local game = ctx.game
  local ok = require("src.inventory.Bag").add(
    ctx.save, itemId, count or 1, game.data)
  if ok then Commands.g2_getitemname(ctx, itemId) end
  ctx.lastCheck = ok and true or false
end

-- GetItemName / GetPokemonName copy a name into a string buffer that a later
-- writetext splices back out ("{RAM:wStringBuffer1}").  The port keeps one
-- buffer, so the buffer index operand is dropped.  Left unlowered these lines
-- printed whatever was named last, several scenes ago.
function Commands.g2_getitemname(ctx, itemId)
  local def = ctx.game.data.items[itemId]
  ctx.game.stringBuffer = def and def.name or itemId
end

function Commands.g2_getmonname(ctx, species)
  local def = ctx.game.data.pokemon[species]
  ctx.game.stringBuffer = def and def.name or species
end

function Commands.g2_check_poke(ctx, species)
  for _, mon in ipairs(ctx.save.party or {}) do
    if mon.species == species then
      ctx.lastCheck = true
      ctx.g2Var = 1
      return
    end
  end
  ctx.lastCheck = false
  ctx.g2Var = 0
end

-- `giveegg species, level`: GiveEgg adds a party member whose is_egg bit is
-- set and whose hatch counter rides in the happiness byte.  The counter comes
-- from the species' own egg cycles (base_stats byte 16), so ELM's TOGEPI EGG
-- takes its ROM-accurate ten cycles rather than a flat five.
function Commands.g2_give_egg(ctx, species, level)
  local Party = require("src.pokemon.Party")
  local Pokemon = require("src.pokemon.Pokemon")
  local DayCare = require("src.pokemon.DayCare")
  local mon = Pokemon.new(ctx.game.data, species, level or 5)
  mon.isEgg = true
  mon.nickname = "EGG"
  mon.eggSteps = DayCare.eggSteps(ctx.game.data, species)
  ctx.lastCheck = Party.add(ctx.save.party, mon) and true or false
  ctx.g2Var = ctx.lastCheck and 0 or 1
end

-- ---------------------------------------------------------------------------
-- POKéGEAR phone book (wPhoneList)
-- ---------------------------------------------------------------------------

local function phoneList(save)
  save.g2Phone = save.g2Phone or {}
  return save.g2Phone
end

function Gen2Commands.phoneList(save)
  return phoneList(save)
end

-- GetCallerName (36:$439D) prints the trainer's own name for any contact with
-- a nonzero trainer class and otherwise indexes NonTrainerCallerNames with the
-- contact id -- MOM, BIKE SHOP, BILL, PROF.ELM.  The extractor stores the
-- class/id pair rather than a baked string, so resolve it against the trainer
-- roster here and the two can never drift apart.
function Gen2Commands.phoneName(data, id)
  local pool = data and data.map_scripts
  local entry = pool and pool.phone and pool.phone[id]
  if type(entry) ~= "table" then return nil end
  if entry.name then return entry.name end
  -- the roster carries a scaffold placeholder for every unused class index,
  -- so prefer the one that actually has a roster of named trainers
  local best
  for _, def in pairs(data.trainers or {}) do
    if type(def) == "table" and def.index == entry.class then
      if def.partyNames and def.partyNames[entry.trainer] then
        best = def
        break
      end
      best = best or def
    end
  end
  if not best then return nil end
  local names = best.partyNames
  return (names and names[entry.trainer]) or best.name, best.name
end

-- The row's second `dba` is the script PhoneCall (36:$4298) runs when the
-- player rings the contact; the first is the one they run when they ring in.
-- Both are walked into map_scripts.scripts by the extractor, so hand back the
-- decoded rows rather than a label the caller would have to resolve itself.
--
-- Through Gen2ScriptVM.compile, not straight out of the pool: map_scripts
-- holds ROM opcodes (`writetext`, `checkevent`, `sjump`), and ScriptRunner
-- only speaks the lowered rows -- handing it the raw list makes every command
-- an "unknown command (skipped)" warning and the call plays as nothing at all.
local function phoneScript(data, id, field)
  local pool = data and data.map_scripts
  local entry = pool and pool.phone and pool.phone[id]
  local label = type(entry) == "table" and entry[field] or nil
  if not label then return nil end
  return require("src.script.Gen2ScriptVM").compile(data, label)
end

function Gen2Commands.phoneCallScript(data, id)
  return phoneScript(data, id, "call")
end

function Gen2Commands.phoneReceiveScript(data, id)
  return phoneScript(data, id, "receive")
end

-- ---------------------------------------------------------------------------
-- specialphonecall
--
-- Script_specialphonecall just parks the SPECIALCALL_* id in
-- wSpecialPhoneCallID; CheckSpecialPhoneCall (36:$413E) runs off the overworld
-- step loop and only rings once the row's condition holds -- which for the
-- post-Falkner egg call is SpecialCallOnlyWhenOutside, so Elm waits until you
-- are back on the town map.  Mirror that with a pending id on the save and a
-- poll in OverworldState:update rather than firing inside the gym script.
-- ---------------------------------------------------------------------------

function Commands.g2_special_call(ctx, id)
  if type(id) ~= "number" then return end
  -- SPECIALCALL_NONE cancels whatever was armed, and it is how the caller
  -- script itself signs off, so it clears the in-flight id too
  ctx.save.g2SpecialCall = id ~= 0 and id or nil
  if id == 0 then ctx.save.g2SpecialCallActive = nil end
end

-- wSpecialPhoneCallID stays set while the caller script runs -- that is how
-- ElmPhoneCallerScript's `readvar 20` knows which of its five lines to say.
-- checkSpecialPhoneCall disarms g2SpecialCall as it fires so the poll cannot
-- ring twice, so the id it fired lives on here until the script signs off.
-- DOWN/UP/LEFT/RIGHT, the order _GetVarAction.PlayerFacing produces:
-- `ld a, [wPlayerDirection] / and $0c / rrca / rrca`.
local GEN2_FACING = { down = 0, up = 1, left = 2, right = 3 }

local function countKeys(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

function Commands.g2_readvar(ctx, var)
  if var == 1 then
    ctx.g2Var = #(ctx.save.party or {})
  elseif var == 20 then
    ctx.g2Var = ctx.save.g2SpecialCallActive or ctx.save.g2SpecialCall or 0
  elseif var == 9 then
    local player = ctx.overworld and ctx.overworld.player
    ctx.g2Var = GEN2_FACING[player and player.facing] or 0
  elseif var == 5 then
    ctx.g2Var = countKeys(ctx.save.pokedex and ctx.save.pokedex.owned)
  elseif var == 6 then
    ctx.g2Var = countKeys(ctx.save.pokedex and ctx.save.pokedex.seen)
  elseif var == 10 then
    ctx.g2Var = tonumber(os.date("%H")) or 0
  elseif var == 11 then
    ctx.g2Var = tonumber(os.date("%w")) or 0
  elseif var == 16 then
    -- BoxFreeSpace: the port never fills a box, so every script that
    -- branches on "is the box full" must take the not-full path
    ctx.g2Var = 20
  elseif var == 7 then
    -- CountBadges (03:$41BE) is `ld hl, wBadges / ld b, 2 / CountSetBits`,
    -- i.e. both badge bytes.  This used to walk a `save.badges` table that
    -- nothing ever writes -- Gen2 gyms run `setflag ENGINE_<X>BADGE`, which
    -- Flags puts in save.flags under the badge id -- so it always answered 0.
    -- MahoganyGymPryceScript is `readvar 7 / scall MahoganyGymActivateRockets`
    -- (`ifequal 7 -> RadioTowerRocketsScript`), so a stuck 0 meant beating
    -- Pryce never armed Elm's takeover call (specialphonecall 4) nor set
    -- ENGINE_ROCKETS_IN_RADIO_TOWER -- the Goldenrod Rocket event never began.
    ctx.g2Var = require("src.inventory.Badges")
                  .count(ctx.game and ctx.game.data, ctx.save)
  elseif var == 14 then
    -- UnownCaught (engine/events/unown_walls.asm): how many distinct UNOWN
    -- letters are in the dex.  The port has no per-letter model, so a caught
    -- UNOWN counts once -- enough for the Ruins researcher's `ifgreater 2`
    -- to stay shut until the player has actually been catching them.
    local dex = ctx.save.pokedex
    local owned = dex and dex.unownForms
    local n = 0
    for _ in pairs(owned or {}) do n = n + 1 end
    ctx.g2Var = n
  else
    ctx.g2Var = 0
  end
end

-- `loadvar 3, n` writes wBattleType ($D119).  BATTLETYPE_SHINY is 7; the
-- byte is consumed by the next startbattle and cleared with the rest of the
-- battle variables afterwards, so it is deliberately NOT saved.
Commands.G2_BATTLETYPE_SHINY = 7

function Commands.g2_loadvar(ctx, var, value)
  if var == 3 then ctx.g2BattleType = tonumber(value) or 0 end
end

-- Returns the caller's PHONE_* id and the decoded script for the armed call,
-- or nil when nothing is pending or its condition has not come round yet.
function Gen2Commands.pendingSpecialCall(data, save, outside)
  local id = save and save.g2SpecialCall
  if type(id) ~= "number" then return nil end
  local pool = data and data.map_scripts
  local row = pool and pool.specialCalls and pool.specialCalls[id]
  if type(row) ~= "table" then return nil end
  if row.outside and not outside then return nil end
  local script = row.script
    and require("src.script.Gen2ScriptVM").compile(data, row.script) or nil
  if not script then return nil end
  return row.caller, script
end

function Commands.g2_cellnum(ctx, id, add)
  if type(id) ~= "number" then return end
  phoneList(ctx.save)[id] = add and true or nil
  ctx.lastCheck = add and true or false
end

function Commands.g2_check_cellnum(ctx, id)
  ctx.lastCheck = phoneList(ctx.save)[id] == true
  ctx.g2Var = ctx.lastCheck and 1 or 0
end

-- AskForPhoneNumber writes wScriptVar: 0 saved, 1 declined, 2 list full.
-- The prompt rides the box the preceding writetext already opened, exactly
-- like yesorno.
function Commands.g2_ask_cellnum(ctx, id, textId)
  if type(id) ~= "number" then
    ctx.g2Var = 1
    return
  end
  local list = phoneList(ctx.save)
  if list[id] then
    ctx.g2Var = 0
    ctx.lastCheck = true
    return
  end
  Commands.ask(ctx, textId)
  if ctx.lastCheck then
    list[id] = true
    ctx.g2Var = 0
  else
    ctx.g2Var = 1
  end
end

-- ---------------------------------------------------------------------------
-- follow / stopfollow
--
-- `follow leader, follower` (Script_follow -> StartFollow, b = leader,
-- c = follower) only records the pair; the walking itself happens on the
-- leader's next applymovement, in g2_move above.
-- ---------------------------------------------------------------------------

function Commands.g2_follow(ctx, leader, follower)
  if leader == nil then
    ctx.g2FollowLeader, ctx.g2FollowTarget = nil, nil
    return
  end
  ctx.g2FollowLeader, ctx.g2FollowTarget = leader, follower
end

-- specials and std scripts are engine calls; the port implements the ones it
-- needs elsewhere, so log the rest once rather than aborting the script
local warned = {}
local function warnOnce(kind, id)
  local key = kind .. tostring(id)
  if warned[key] then return end
  warned[key] = true
  Logger.warn("gen2 script: unhandled %s %s", kind, tostring(id))
end

function Commands.g2_special(ctx, id)
  warnOnce("special", id)
  ctx.lastCheck = false
end

-- UnownPuzzle (SpecialsPointers row 41).  The chamber scripts run
-- `setval <picture>` first, so the picture rides in on wScriptVar, and the
-- caller branches on `iftrue` -- i.e. on ctx.lastCheck -- to open the wall.
function Commands.g2_unown_puzzle(ctx)
  local game = ctx.game
  local runner = ctx.runner
  if not (game and game.stack and runner) then
    ctx.lastCheck = false
    return
  end
  local picture = scriptVar(ctx)
  local UnownPuzzle = require("src.ui.UnownPuzzle")
  game.stack:push(UnownPuzzle.new(game, picture, function(solved)
    ctx.lastCheck = solved and true or false
    runner:resume()
  end))
  runner:yield()
end

function Commands.g2_std(ctx, id)
  warnOnce("std script", id)
end

-- ---------------------------------------------------------------------------
-- Mania's SHUCKIE (GiveShuckle 01:$73E1, ReturnShuckie 01:$7452)
--
-- Not a `givepoke`: the special stamps a fixed OT ("MANIA", ID $0206),
-- nickname and held BERRY, and ReturnShuckie recognises its own mon by
-- exactly that stamp -- species, OT id AND OT name all have to match or the
-- player is told they don't have it.
-- ---------------------------------------------------------------------------

local SHUCKIE_OT, SHUCKIE_OT_ID = "MANIA", 0x0206

function Commands.g2_give_shuckle(ctx)
  local Party = require("src.pokemon.Party")
  if #ctx.save.party >= Party.MAX then
    ctx.g2Var, ctx.lastCheck = 0, false
    return
  end
  local mon = require("src.pokemon.Pokemon").new(ctx.game.data, "SPECIES_213", 15)
  mon.nickname = "SHUCKIE"
  mon.ot, mon.otId, mon.traded = SHUCKIE_OT, SHUCKIE_OT_ID, true
  mon.item = "ITEM_173" -- BERRY
  Party.add(ctx.save.party, mon)
  -- $D968 bit 5, the flag ManiaScript's `checkflag 84` reads to decide
  -- whether he is willing to ask for it back yet
  require("src.script.Flags").set(ctx.save, "FLAG_G2_0084")
  ctx.g2Var, ctx.lastCheck = 1, true
end

-- wScriptVar: 0 that isn't my mon, 1 you backed out, 2 handed back,
-- 3 it likes you too much to leave (happiness >= 150), 4 it is the only
-- thing you have left to battle with (CheckCurPartyMonFainted).
function Commands.g2_return_shuckie(ctx)
  local game, runner = ctx.game, ctx.runner
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()

  local function result(n)
    ctx.g2Var, ctx.lastCheck = n, n ~= 0
  end
  if not picked then return result(1) end
  if picked.species ~= "SPECIES_213" or picked.otId ~= SHUCKIE_OT_ID
     or picked.ot ~= SHUCKIE_OT then
    return result(0)
  end
  local Party = require("src.pokemon.Party")
  local othersHealthy = false
  for _, mon in ipairs(ctx.save.party) do
    if mon ~= picked and not Party.isEgg(mon) and (mon.hp or 0) > 0 then
      othersHealthy = true
    end
  end
  if not othersHealthy then return result(4) end
  if (picked.happiness or 0) >= 150 then return result(3) end
  for i, mon in ipairs(ctx.save.party) do
    if mon == picked then table.remove(ctx.save.party, i) break end
  end
  result(2)
end

-- ---------------------------------------------------------------------------
-- audio
--
-- The importer keys audio.musicIndex/sfxIndex by the ROM row a MUSIC_* or
-- SFX_* constant names, so a script operand is a direct lookup.  Row 0 of the
-- Music table is Music_Nothing, i.e. MUSIC_NONE: silence.
-- ---------------------------------------------------------------------------

local function audioName(ctx, table_, id)
  local data = ctx.game and ctx.game.data
  local index = data and data.audio and data.audio[table_]
  return index and index[tostring(id)] or nil
end

function Commands.g2_music(ctx, id)
  local Music = require("src.core.Music")
  if id == 0 then return Music.stop() end
  local song = audioName(ctx, "musicIndex", id)
  if not song then return warnOnce("music", id) end
  Music.play(ctx.game.data, song, nil, { reason = "script" })
end

function Commands.g2_sfx(ctx, id)
  local name = audioName(ctx, "sfxIndex", id)
  if not name then return warnOnce("sfx", id) end
  require("src.core.Sound").play(ctx.game.data, name)
end

function Commands.g2_sfx_name(ctx, name)
  if ctx.game then require("src.core.Sound").play(ctx.game.data, name) end
end

function Commands.g2_mapmusic(ctx)
  local ow = ctx.overworld
  local game = ctx.game
  if not game then return end
  require("src.core.Music").playMap(game.data, ow and ow.map and ow.map.id,
    game.save and game.save.onBike,
    ow and ow.player and ow.player.surfing)
end

-- `musicfadeout MUSIC, frames`: the ROM fades the current song out over
-- `frames` and queues the new one; the port fades and starts it, since
-- Music.fadeOut stops the source when it reaches silence.
function Commands.g2_musicfade(ctx, id, frames)
  local Music = require("src.core.Music")
  Music.fadeOut(frames)
  if id and id ~= 0 then
    local song = audioName(ctx, "musicIndex", id)
    if song then Music.play(ctx.game.data, song, nil, { reason = "script" }) end
  end
end

function Commands.g2_keepmusic(ctx)
  local ow = ctx.overworld
  if ow then ow.keepMusicOnce = true end
end

function Commands.g2_nop() end

-- ---------------------------------------------------------------------------
-- world / bookkeeping opcodes
-- ---------------------------------------------------------------------------

-- FruitTreeScript (17:$4000).  GetFruitTreeItem indexes FruitTreeItems by
-- wCurFruitTree - 1; GetFruitTreeFlag remembers the pick so the tree is bare
-- until the next daily reset.
function Commands.g2_fruittree(ctx, tree)
  local game = ctx.game
  local save = ctx.save
  local t = game.data.text
  save.g2FruitTrees = save.g2FruitTrees or {}
  local itemId = ((game.data.field or {}).gen2FruitTrees or {})[tree]
  -- CheckFruitTree: a picked tree (or one the table has no row for) is just
  -- scenery until TryResetFruitTrees clears the flags
  if save.g2FruitTrees[tree] or not itemId then
    return Commands.show_text(ctx,
      t._FruitBearingTreeText or "It's a fruit-\nbearing tree.")
  end
  local def = game.data.items[itemId]
  local name = def and def.name or itemId
  -- GetFruitTreeItem -> CopyToStringBuffer runs BEFORE the first box, and
  -- both ROM texts splice the name in themselves ("{RAM:wStringBuffer3}").
  -- Appending it again printed the previous gift's name plus this one.
  game.stringBuffer = name
  Commands.show_text(ctx, t._HeyItsFruitText or ("Hey! It's\n" .. name .. "!"))
  if not require("src.inventory.Bag").add(save, itemId, 1, game.data) then
    -- .packisfull: the fruit stays on the tree, so the flag is NOT set
    return Commands.show_text(ctx,
      t._FruitPackIsFullText or "But the PACK is\nfull…")
  end
  save.g2FruitTrees[tree] = true
  ctx.textOpts = ctx.textOpts or {}
  ctx.textOpts.auto = {
    sound = function() return require("src.core.Sound").play(game.data, "Get_Item1") end,
    wait = true,
  }
  Commands.show_text(ctx, t._ObtainedFruitText or ("Obtained\n" .. name .. "!"))
end

-- refreshmap / reloadmap / newloadmap / reanchormap: redraw the loaded map.
function Commands.g2_refreshmap(ctx)
  local ow = ctx.overworld
  if ow and ow.map and ow.map.renderer then ow.map.renderer:rebuild() end
end

-- warpcheck re-tests the tile the player is standing on, so a floor a script
-- just opened swallows them immediately instead of on the next step.
function Commands.g2_warpcheck(ctx)
  local ow = ctx.overworld
  if not (ow and ow.map and ow.player and ow.refreshStandingOnWarp) then return end
  ow:refreshStandingOnWarp()
  local warp = ow.map:warpAtCell(ow.player.cellX, ow.player.cellY)
  -- only a stair/ladder/hole tile swallows the player where they stand; a
  -- door warp still waits for the step that walks into it
  if warp and ow.map:isWarpTileCell(ow.player.cellX, ow.player.cellY)
     and not ow.map:isDoorTileCell(ow.player.cellX, ow.player.cellY) then
    ow:takeWarp(warp)
  end
end

-- earthquake <duration>: the screen shake the Rocket hideout and the
-- Sudowoodo route use as punctuation.
function Commands.g2_earthquake(ctx, duration)
  local ow = ctx.overworld
  if ow then ow.quakeFrames = duration or 32 end
end

-- setlasttalked retargets applymovementlasttalked / faceplayer at an object
-- the player never spoke to.
function Commands.g2_setlasttalked(ctx, index)
  local ow = ctx.overworld
  if not ow then return end
  local slot = objectSlot(index)
  local npc = slot and ow:npcByIndex(slot) or nil
  if npc then ctx.npc = npc end
end

-- The COIN CASE balance lives in save.coins -- the same field the COIN CASE
-- item and the slot machine screen read.  Gen2 used to keep its own g2Coins,
-- so the Game Corner paid into a balance the prize counters could not see.
local function coins(save)
  if save.g2Coins and not save.coins then save.coins = save.g2Coins end
  return save.coins or 0
end

function Commands.g2_check_coins(ctx, amount)
  ctx.lastCheck = coins(ctx.save) >= (amount or 0)
  -- CheckCoins also reports the comparison through the script var, which is
  -- what the prize vendors branch on
  ctx.g2Var = coins(ctx.save) >= (amount or 0) and 0 or 1
end

function Commands.g2_give_coins(ctx, amount)
  local save = ctx.save
  save.coins = math.max(0, math.min(9999, coins(save) + (amount or 0)))
  save.g2Coins = nil
end

-- `special DisplayCoinCaseBalance` / `DisplayMoneyAndCoinBalance`: the ROM
-- opens a corner window over the vendor's menu.  There is no such window
-- here, so this only has to leave the balance where the menu can show it.
function Commands.g2_show_coins(ctx)
  ctx.game.coinDisplay = coins(ctx.save)
end

-- The port has no swarm table; record the request so a save that already
-- triggered one keeps reporting it rather than silently losing it.
function Commands.g2_swarm(ctx, kind, mapId)
  ctx.save.g2Swarm = { kind = kind, map = mapId }
end

-- `special NameRater` (_NameRater, 3E:$77F7).  The whole conversation lives
-- inside the special, so leaving it a warn-once stub is why the NAME RATER
-- stood there silently: the surrounding script is opentext/special/closetext
-- and nothing else.
function Commands.g2_name_rater(ctx)
  local game, save = ctx.game, ctx.save
  local t = game.data.text
  local runner = ctx.runner
  local Party = require("src.pokemon.Party")
  local function nickOf(mon)
    return mon.nickname or (game.data.pokemon[mon.species] or {}).name
           or mon.species
  end

  Commands.ask(ctx, t._NameRaterHelloText or "Would you like me\nto rate names?")
  if not ctx.lastCheck then
    return Commands.show_text(ctx, t._NameRaterComeAgainText
      or "OK, then. Come\nagain sometime.")
  end

  Commands.show_text(ctx, t._NameRaterWhichMonText
    or "Which POKéMON's\nnickname should I\vrate for you?")
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()
  if not picked then
    return Commands.show_text(ctx, t._NameRaterComeAgainText
      or "OK, then. Come\nagain sometime.")
  end
  if Party.isEgg(picked) then
    return Commands.show_text(ctx, t._NameRaterEggText
      or "Whoa… That's just\nan EGG.")
  end

  game.stringBuffer = nickOf(picked)
  -- .traded: a mon whose OT is not the player can't be renamed, and the rater
  -- covers for himself by declaring the name it already has perfect
  local ot = picked.otName or picked.ot
  if ot and ot ~= (save.player and save.player.name) then
    return Commands.show_text(ctx, t._NameRaterPerfectNameText
      or "Hm… {RAM:wStringBuffer1}?\nWhat a great name!")
  end
  Commands.ask(ctx, t._NameRaterBetterNameText
    or "Hm… {RAM:wStringBuffer1}? A better name?")
  if not ctx.lastCheck then
    return Commands.show_text(ctx, t._NameRaterComeAgainText
      or "OK, then. Come\nagain sometime.")
  end

  Commands.show_text(ctx, t._NameRaterWhatNameText
    or "All right. What\nname should we\vgive it, then?")
  local chosen
  game.stack:push(require("src.ui.NamingScreen").new(game, {
    title = Strings("%s's NICKNAME?", nickOf(picked)),
    maxLen = 10,
    default = nickOf(picked),
    onDone = function(name) chosen = name runner:resume() end,
  }))
  runner:yield()

  -- .samename: the rater still congratulates himself when the new name is
  -- the one it already had
  if not chosen or chosen == "" or chosen == nickOf(picked) then
    game.stringBuffer = nickOf(picked)
    return Commands.show_text(ctx, t._NameRaterSameNameText
      or "It might look the\nsame as before,\fbut this new name\nis much better!")
  end
  picked.nickname = chosen
  game.stringBuffer = chosen
  Commands.show_text(ctx, t._NameRaterNamedText
    or "All right. This\nPOKéMON is now\vnamed {RAM:wStringBuffer1}.")
  Commands.show_text(ctx, t._NameRaterFinishedText
    or "That's a better\nname than before!\fWell done!")
end

-- ---------------------------------------------------------------------------
-- DAY-CARE (engine/events/daycare.asm)
--
-- The Route 34 DAY-CARE is driven entirely from specials: the MAN inside is
-- `special DayCareMan` (SpecialsPointers row $1E), the LADY `special
-- DayCareLady` ($1F), the MAN OUTSIDE $20, and the two mons in the yard $44 /
-- $45.  All five were warn-once stubs, so every one of those NPCs opened a
-- text box and immediately closed it again -- the day-care did nothing at all.
--
-- The conversation is the ROM's: intro -> pick -> deposit, or grown-report ->
-- fee -> hand back.  wDayCareMonBoxLevel (slot.depositLevel) is the fee
-- baseline and has to survive a declined retrieve, and the banked step exp is
-- only cashed in when the mon actually leaves.
-- ---------------------------------------------------------------------------

-- Methods rather than chunk locals: this file is close to Lua's
-- 200-locals-per-chunk ceiling (see FLOOR_NAMES below).
function Gen2Commands.dayCareName(game, mon)
  local def = game.data.pokemon[mon.species]
  return mon.nickname or (def and def.name) or mon.species
end

function Gen2Commands.dayCareDeposit(ctx, which, introText, leftText)
  local game, save, runner = ctx.game, ctx.save, ctx.runner
  local t = game.data.text
  local Party = require("src.pokemon.Party")
  local DayCare = require("src.pokemon.DayCare")

  Commands.ask(ctx, introText)
  if not ctx.lastCheck then
    return Commands.show_text(ctx, t._ComeAgainText or "Come again.")
  end
  -- .only_one: the last party member can never be boarded
  if #save.party < 2 then
    return Commands.show_text(ctx, t._OnlyOneMonText
      or "Oh? But you have\njust one #MON.")
  end

  Commands.show_text(ctx, t._WhatShouldIRaiseText
    or "What should I\nraise for you?")
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()
  if not picked then
    return Commands.show_text(ctx, t._ComeAgainText or "Come again.")
  end
  if Party.isEgg(picked) then
    return Commands.show_text(ctx, t._CantAcceptEggText
      or "Sorry, but I can't\naccept an EGG.")
  end
  if picked.mail then
    return Commands.show_text(ctx, t._RemoveMailText
      or "Remove the MAIL\nfrom that #MON.")
  end
  -- .last_healthy: boarding the only mon that can still battle is refused
  local healthy = 0
  for _, mon in ipairs(save.party) do
    if not Party.isEgg(mon) and (mon.hp or 0) > 0 then healthy = healthy + 1 end
  end
  if healthy <= 1 and (picked.hp or 0) > 0 and not Party.isEgg(picked) then
    return Commands.show_text(ctx, t._LastHealthyMonText
      or "That's your last\nhealthy #MON.")
  end

  for i, mon in ipairs(save.party) do
    if mon == picked then table.remove(save.party, i) break end
  end
  DayCare.deposit(save, which, picked)
  game.stringBuffer = Gen2Commands.dayCareName(game, picked)
  Commands.show_text(ctx, t._IllRaiseYourMonText
    or "Fine, I'll raise\nyour #MON.")
  Commands.show_text(ctx, leftText, { RAM = game.stringBuffer })
end

function Gen2Commands.dayCareWithdraw(ctx, which)
  local game, save = ctx.game, ctx.save
  local t = game.data.text
  local Party = require("src.pokemon.Party")
  local Stats = require("src.pokemon.Stats")
  local Growth = require("src.pokemon.Growth")
  local Pokemon = require("src.pokemon.Pokemon")
  local DayCare = require("src.pokemon.DayCare")

  local slot = DayCare.slot(save, which)
  local mon = slot.mon
  local def = game.data.pokemon[mon.species]
  local startLevel = slot.depositLevel or mon.level
  local newLevel, exp = DayCare.pendingLevel(game.data, slot)
  if newLevel >= 100 and def then
    exp = Growth.expForLevel(def.growthRate, 100)
  end
  local levelsGrown = math.max(0, newLevel - startLevel)
  local fee = 100 + levelsGrown * 100
  local name = Gen2Commands.dayCareName(game, mon)
  game.stringBuffer = name

  if levelsGrown > 0 then
    Commands.show_text(ctx, t._YourMonHasGrownText
      or "Your #MON has\ngrown a lot!\fBy level, it's\ngrown by {NUM:wDayCareNumLevelsGrown}!",
      { RAM = name, NUM = tostring(levelsGrown) })
    Commands.show_text(ctx, t._AreWeGeniusesText
      or "Aren't we\ngeniuses?")
  else
    Commands.show_text(ctx, t._BackAlreadyText
      or "Back already?\nYour #MON needs\nmore time with me.",
      { RAM = name })
  end

  Commands.ask(ctx, Strings("That'll be \194\165%d.\nOK?", fee))
  if not ctx.lastCheck then
    return Commands.show_text(ctx, t._OhFineThenText or "Oh, fine then.")
  end
  if #save.party >= Party.MAX then
    return Commands.show_text(ctx, t._HaveNoRoomText
      or "You have no room\nfor it.")
  end
  if (save.money or 0) < fee then
    return Commands.show_text(ctx, t._NotEnoughMoneyText
      or "You don't have\nenough money.")
  end

  save.money = save.money - fee
  DayCare.withdraw(save, which)
  mon.exp = exp
  mon.level = newLevel
  if def then
    mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
    mon.hp = math.min(mon.hp or mon.stats.hp, mon.stats.hp)
    -- WriteMonMoves with wLearningMovesFromDayCare: the levels it grew
    -- through are taught in order, oldest move pushed out first
    Pokemon.learnMovesFromDayCare(game.data, mon, def, startLevel, newLevel)
  end
  table.insert(save.party, mon)
  Commands.show_text(ctx, t._PerfectHeresYourMonText
    or "Perfect! Here's\nyour #MON!")
  Commands.show_text(ctx, t._GotBackMonText
    or "{PLAYER} got\n{RAM:wStringBuffer} back!", { RAM = name })
end

-- `special DayCareMan` ($1E) -- wBreedMon1, the pen on the left.
function Commands.g2_daycare_man(ctx)
  local DayCare = require("src.pokemon.DayCare")
  local t = ctx.game.data.text
  if DayCare.mon(ctx.save, DayCare.MAN) then
    return Gen2Commands.dayCareWithdraw(ctx, DayCare.MAN)
  end
  local intro = DayCare.introduce(ctx.save, DayCare.MAN)
    and (t._DayCareManIntroEggText or t._DayCareManIntroText)
    or t._DayCareManIntroText
  return Gen2Commands.dayCareDeposit(ctx, DayCare.MAN,
    intro or "I'm the DAY-CARE\nMAN. Want me to\nraise a #MON?",
    t._LeftWithDayCareManText
      or "{RAM:wStringBuffer} was left with\nthe DAY-CARE MAN.")
end

-- `special DayCareLady` ($1F) -- wBreedMon2, the pen on the right.
function Commands.g2_daycare_lady(ctx)
  local DayCare = require("src.pokemon.DayCare")
  local t = ctx.game.data.text
  if DayCare.mon(ctx.save, DayCare.LADY) then
    return Gen2Commands.dayCareWithdraw(ctx, DayCare.LADY)
  end
  local intro = DayCare.introduce(ctx.save, DayCare.LADY)
    and (t._DayCareLadyIntroEggText or t._DayCareLadyIntroText)
    or t._DayCareLadyIntroText
  return Gen2Commands.dayCareDeposit(ctx, DayCare.LADY,
    intro or "I'm the DAY-CARE\nLADY. Want me to\nraise a #MON?",
    t._LeftWithDayCareLadyText
      or "{RAM:wStringBuffer} was left with\nthe DAY-CARE LADY.")
end

-- `special DayCareManOutside` ($20) -- the handover.  DayCareStep already
-- parked the EGG in save.daycare.breed.egg; this is only the conversation.
--
-- DayCareManScript_Outside branches on what the special leaves in wScriptVar,
-- so this has to answer in the ROM's currency (05:$6B8C):
--
--   .PartyFull -> 1   the man stays put, come back with room
--   accepted   -> 0   \  both fall into `clearflag ENGINE_DAY_CARE_MAN_HAS_EGG`
--   .Declined  -> 0   /  and the applymovement that walks him back inside
--
-- Without it ctx.g2Var kept whatever the last opcode had left, so the walk --
-- and with it the `disappear` that hands Route 34 back to the empty state --
-- was a coin toss.  Declining really does throw the EGG away: the ROM only
-- ever holds one in wEggMon and the script clears the flag either way.
function Commands.g2_daycare_outside(ctx)
  local game, save = ctx.game, ctx.save
  local t = game.data.text
  local Party = require("src.pokemon.Party")
  local DayCare = require("src.pokemon.DayCare")
  local breed = DayCare.store(save, false)
  local egg = breed and breed.egg
  ctx.g2Var = 1
  if not egg then
    return Commands.show_text(ctx, t._DayCareManOutsideNotYetText
      or t["DayCareManOutside.NotYetText"]
      or "Ah, it's you!\nYour #MON aren't\nlooking after an\nEGG yet.")
  end
  Commands.ask(ctx, t._FoundAnEggText
    or "Ah, it's you!\nWe were raising\nyour #MON, and\fmy goodness, we\nfound an EGG!\fDo you want it?")
  if not ctx.lastCheck then
    breed.egg = nil
    DayCare.syncFlags(save)
    ctx.g2Var = 0
    return Commands.show_text(ctx, t._IllKeepItThanksText
      or "Well then, I'll\nkeep it. Thanks!")
  end
  if #save.party >= Party.MAX then
    return Commands.show_text(ctx, t._NoRoomForEggText
      or "You have no room\nin your party.")
  end
  breed.egg = nil
  DayCare.syncFlags(save)
  Party.add(save.party, egg)
  ctx.g2Var = 0
  Commands.show_text(ctx, t._ReceivedEggText or "{PLAYER} received\nthe EGG!")
  Commands.show_text(ctx, t._TakeGoodCareOfEggText
    or "Take good care of\nit!")
end

-- `special DayCareMon1/2` ($44/$45) -- the two mons wandering the yard.  The
-- object's sprite byte is $E0/$E1 (SPRITE_MON_BREED_1/2); talking to one
-- plays its cry and names it, and the keeper's read on the pair rides along
-- as DayCareMonCompatibilityText.
function Gen2Commands.dayCareYardMon(ctx, which)
  local game = ctx.game
  local t = game.data.text
  local DayCare = require("src.pokemon.DayCare")
  local mon = DayCare.mon(ctx.save, which)
  if not mon then
    ctx.lastCheck = false
    return
  end
  local name = Gen2Commands.dayCareName(game, mon)
  game.stringBuffer = name
  ctx.pendingCry = mon.species
  Commands.show_text(ctx, t.Text_BreedHuh or t._BreedHuhText or "Huh?",
    { RAM = name })
  local tiers = {
    [0] = t._BreedNoInterestText,
    [1] = t._BreedShowsInterestText,
    [2] = t._BreedAppearsToCareForText,
    [3] = t._BreedFriendlyText or t._BreedAppearsToCareForText,
    [4] = t._BreedBrimmingWithEnergyText,
  }
  local tier = DayCare.compatibility(game.data, ctx.save)
  if DayCare.pair(game.data, ctx.save) and tiers[tier] then
    Commands.show_text(ctx, tiers[tier])
  end
  ctx.lastCheck = true
end

function Commands.g2_daycare_mon1(ctx)
  return Gen2Commands.dayCareYardMon(ctx, 1)
end

function Commands.g2_daycare_mon2(ctx)
  return Gen2Commands.dayCareYardMon(ctx, 2)
end

-- ---------------------------------------------------------------------------
-- elevators and script menus
-- ---------------------------------------------------------------------------

-- ElevatorFloorNames (04:$7945), indexed by the floor byte in the elevator's
-- data block.  A class field rather than a chunk local: this file is close to
-- Lua's 200-locals-per-chunk ceiling.
Gen2Commands.FLOOR_NAMES = {
  [0] = "B4F", "B3F", "B2F", "B1F", "1F", "2F", "3F", "4F", "5F", "6F",
  "7F", "8F", "9F", "10F", "11F", "ROOF",
}

-- `elevator <ptr>`: the extractor resolves the pointer into the floor list
-- (db floor, db warp, db group, db number per row).  Without a lowering the
-- opcode compiled to nothing at all, which is why the panel did nothing: the
-- car's two door tiles are LAST_WARP, so cancelling the (never shown) menu
-- always dropped the player back on the floor they got in from.
--
-- Elevator_GoToFloor copies the chosen row straight into wBackupWarpNumber /
-- wBackupMapGroup / wBackupMapNumber -- the very store LAST_WARP reads -- so
-- re-pointing backupWarp is the whole of the ROM's behaviour.
function Commands.g2_elevator(ctx, floors)
  local game, runner = ctx.game, ctx.runner
  ctx.lastCheck = false
  if type(floors) ~= "table" or #floors == 0 then
    Logger.warn("gen2 script: elevator with no floor data")
    return
  end
  -- Elevator.FindCurrentFloor skips the row whose map is the one we are on
  local ow = ctx.overworld
  local here = ow and ow.backupWarp and ow.backupWarp.id
  local chosen
  local items = {}
  for _, floor in ipairs(floors) do
    if floor.map and floor.map ~= here then
      items[#items + 1] = {
        label = Gen2Commands.FLOOR_NAMES[floor.floor] or tostring(floor.floor),
        onSelect = function() chosen = floor runner:resume() end,
      }
    end
  end
  if #items == 0 then return end

  Commands.show_text(ctx, (game.data.text or {})._AskFloorElevatorText
    or Strings("Which floor?"))
  game.stack:push(require("src.ui.Menu").new(game, items, {
    onCancel = function() runner:resume() end,
  }))
  runner:yield()
  if not chosen then return end

  local def = game.data.maps[chosen.map]
  local warp = def and def.warps and def.warps[chosen.warp]
  if not warp then
    Logger.warn("gen2 script: elevator warp %s#%s missing",
                tostring(chosen.map), tostring(chosen.warp))
    return
  end
  local backup = { id = chosen.map, x = warp.x, y = warp.y }
  if ow then ow.backupWarp = backup end
  ctx.save.backupWarp = backup
  ctx.lastCheck = true
end

-- `loadmenu <ptr>` arms a MenuHeader; the extractor already turned it into
-- the list of MenuData labels.  `verticalmenu` runs it and writes the 1-based
-- choice into the script var (0 = cancelled), which is what the Game Corner
-- prize counters branch on with `ifequal 1/2/3`.  Both were unlowered, so the
-- vendors printed their greeting and then stood there.
function Commands.g2_loadmenu(ctx, menu)
  if type(menu) ~= "table" or #menu == 0 then
    ctx.g2Menu = nil
    Logger.warn("gen2 script: loadmenu header was not resolved")
    return
  end
  ctx.g2Menu = menu
end

function Commands.g2_verticalmenu(ctx)
  local menu = ctx.g2Menu
  ctx.g2Menu = nil
  if not menu then
    ctx.g2Var, ctx.lastCheck = 0, false
    return
  end
  local game, runner = ctx.game, ctx.runner
  local picked = 0
  local items = {}
  for index, label in ipairs(menu) do
    items[index] = {
      label = label,
      onSelect = function() picked = index runner:resume() end,
    }
  end
  game.stack:push(require("src.ui.Menu").new(game, items, {
    onCancel = function() runner:resume() end,
  }))
  runner:yield()
  ctx.g2Var = picked
  ctx.lastCheck = picked ~= 0
end

-- `special SlotMachine`: the `setval 0/1` ahead of it marks the one machine
-- Slots_InitBias makes generous.  Nothing follows in the script but
-- closetext/end, so this does not have to yield.
function Commands.g2_slots(ctx)
  require("src.ui.Screens").push(ctx.game, "Gen2Slots", scriptVar(ctx) == 1)
end

-- `special CardFlip`: takes no argument, and like the slots nothing follows it
-- in the script but closetext/end, so it does not have to yield.
function Commands.g2_card_flip(ctx)
  require("src.ui.Screens").push(ctx.game, "Gen2CardFlip")
end

return Gen2Commands
