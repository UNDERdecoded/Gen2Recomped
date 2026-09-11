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
local Strings = require("src.core.Strings")

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
-- VAR_LAST_TALKED: the local id of the object the player just interacted
-- with.  Std_FindItem removes it -- that is how the ball on the ground
-- goes away -- so it has to hold the right id by the time the script runs.
local VAR_LAST_TALKED = 0x800F
-- $800C IS THE PLAYER'S OWN FACING, and nothing in this port was filling it
-- in.  It is read in 104 places across the cartridge and written by NONE of
-- the 6897 scripts, which is what says it is native rather than scripted --
-- and every one of those 104 compares it against 1, 2, 3 or 4 and nothing
-- else, ever, while VAR_RESULT next door ranges over the whole 16 bits.  A
-- var no script writes, only ever compared against exactly four values, is a
-- direction; the four are the same ones `g3_turn` below was already using.
--
-- Left at zero it matches none of them, so every scene that branches on which
-- way the player is standing took none of its branches -- which is why May
-- comes upstairs and then says nothing at all.
local VAR_FACING = 0x800C

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

-- THE SIXTEEN VARS THAT SAY WHO AN OBJECT IS.
--
-- Reported from play: "after getting my starter from elm im supposed to meet
-- may in the route above oldale town but shes not there".  She is on Route
-- 103 in the map data, at (10,3), and her flag is clear -- but her graphics
-- id is 240, which is OBJ_EVENT_GFX_VAR_0: not a character at all, a SLOT
-- that a script fills.  Route 103's ON_TRANSITION opens with
-- `call Common_EventScript_SetupRivalGfxId`, and that is what decides whether
-- the child waiting for you is Brendan or May.
--
-- The port already refused to draw an object whose slot was unfilled -- and
-- rightly, because the placeholder art in those rows is a stranger.  What it
-- had was a reader with no writer: NOTHING in the engine ever put anything
-- into save.gen3ObjectSprites, so all 337 objects that name a slot were
-- invisible for the whole game.  Every one of the fifty-four writes the
-- cartridge makes goes through here.
local VAR_OBJ_GFX_FIRST, VAR_OBJ_GFX_LAST = 0x4010, 0x401F

-- THE SIXTEEN VARS AND THIRTY-TWO FLAGS A MAP LOAD THROWS AWAY.
--
-- ClearTempFieldEventData, 0x0009D344, is four instructions long and says
-- exactly how much is temporary:
--
--     r0 = *gSaveBlock1Ptr                 (0x03005D8C)
--     str  0 -> [r0 + 0x1270]              the first FOUR flag bytes
--     memset(r0 + 0x139C, 0, 32)           the first THIRTY-TWO var bytes
--
-- Four bytes of flags is 32 flags -- $000-$01F -- and thirty-two bytes of
-- vars is SIXTEEN vars, $4000-$400F.  It is called from both map-load paths
-- (0x00850D8 and 0x00851C0), so every warp, every door and every connection
-- crossing empties them.
--
-- THE BOUNDARY CLOSES ON ITSELF: the sixteen object-graphics slots begin at
-- $4010, immediately after the run, and those obviously must NOT be cleared
-- -- a map load that forgot who was standing where would empty Hoenn.  The
-- memset stopping exactly where VAR_OBJ_GFX_ID_0 starts is the proof that
-- 32 bytes is 16 vars and not something else.
--
-- Reported from play: "when going to the contest in slateport, i get a
-- looping error, in recognition for 3-win streak we award you this prize.
-- even though ive never done the contest."  The Battle Tent's lobby is an
-- ON_FRAME table gated on VAR_TEMP_0 -- value 0 is the ordinary arrival,
-- value 3 is the three-win prize -- and this port never cleared the var, so
-- whatever the last map to use it as scratch left behind decided which of
-- the five scripts ran on the way in.
local VAR_TEMP_FIRST, VAR_TEMP_LAST = 0x4000, 0x400F
local FLAG_TEMP_FIRST, FLAG_TEMP_LAST = 0x000, 0x01F

function Gen3Commands.clearTempFieldEventData(save)
  if type(save) ~= "table" then return end
  local vars = save.gen3Vars
  if type(vars) == "table" then
    for id = VAR_TEMP_FIRST, VAR_TEMP_LAST do vars[id] = nil end
  end
  local flags = save.flags
  if type(flags) == "table" then
    for id = FLAG_TEMP_FIRST, FLAG_TEMP_LAST do
      flags[("FLAG_G3_%04X"):format(id)] = nil
    end
  end
end


local function setVar(save, id, value)
  id = tonumber(id) or 0
  local store = varStore(save)
  if store then store[id] = tonumber(value) or 0 end
  if save and id >= VAR_OBJ_GFX_FIRST and id <= VAR_OBJ_GFX_LAST then
    local graphics = tonumber(value) or 0
    save.gen3ObjectSprites = save.gen3ObjectSprites or {}
    -- zero is the slot's empty state, not a graphics id: `setvar VAR_OBJ_GFX_
    -- ID_0, 0` is a scene putting the slot back, and the object goes with it
    save.gen3ObjectSprites[id - VAR_OBJ_GFX_FIRST] =
      graphics > 0 and graphics or nil
  end
end

Gen3Commands.getVar = getVar
Gen3Commands.setVar = setVar
Gen3Commands.VAR_OBJ_GFX_FIRST = VAR_OBJ_GFX_FIRST
Gen3Commands.VAR_OBJ_GFX_LAST = VAR_OBJ_GFX_LAST

-- WHO IS IN A SLOT, asked by the two places that need it: the spawn filter
-- (an object whose slot is empty is not on the map) and the sprite lookup
-- (which sheet it wears once it is).
--
-- The var IS the answer, and it is the fallback rather than the primary for
-- one reason: an IMPORTED Emerald save fills gen3Vars straight out of the
-- cartridge's own SaveBlock without going through setVar, so a save carried
-- in from a real game already knows who is standing where and would
-- otherwise arrive with every one of these people missing.
function Gen3Commands.objectSprite(save, slot)
  slot = tonumber(slot)
  if not (save and slot and slot >= 0
          and slot <= VAR_OBJ_GFX_LAST - VAR_OBJ_GFX_FIRST) then
    return nil
  end
  local cached = save.gen3ObjectSprites
                 and tonumber(save.gen3ObjectSprites[slot])
  if cached and cached > 0 then return cached end
  local fromVar = getVar(save, VAR_OBJ_GFX_FIRST + slot)
  return fromVar > 0 and fromVar or nil
end
Gen3Commands.VAR_RESULT = VAR_RESULT
Gen3Commands.VAR_FACING = VAR_FACING

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

-- EVERY CRUMBLING FLOOR IN HOENN DROPPED THE PLAYER ON ARRIVAL.
--
-- The cartridge's ScrCmd_copyvar (0x099745) takes GetVarPointer on BOTH
-- operands, and GetVarPointer (0x09D648) answers NULL below $4000 -- so a
-- LITERAL source reads *(u16 *)0, which on a GBA is the BIOS's read
-- protection value and is never zero.  Ten of the cartridge's 788 copyvars
-- have a literal source, and six of them are the line
--
--     copyvar VAR_ICE_STEP_COUNT, 1
--
-- in the ON_TRANSITION of Mirage Tower 2F and 3F, Granite Cave B1F, Mt. Pyre
-- 2F, and Sky Pillar 2F and 4F.  Each of those maps also carries an
-- ON_FRAME_TABLE row that fires EventScript_FallDownHole when that same var
-- reads ZERO.  The line exists to make sure it does not.
--
-- Reading var 1 -- which nothing in the game ever writes -- gave exactly 0,
-- so the transition ARMED the fall it was written to disarm and the frame
-- table dropped the player through the floor on the first idle frame after
-- the map came up, before a step was taken.  Sootopolis Gym is the only one
-- of the seven that worked, because its transition spells the same intent
-- `setvar` instead.  The Root and Claw Fossils, Rayquaza, and Mt. Pyre's
-- upper floors were all unreachable behind this one line.
--
-- So take the literal, the way `setorcopyvar` next door already does, which
-- is what the script means either way.  isVarId covers $4000-$41FF and the
-- $8000 temporaries, so all 778 genuine var-to-var copies are unchanged.
function Commands.g3_copyvar(ctx, dest, src)
  setVar(ctx.save, dest, valueOf(ctx, src))
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

-- WHERE THE GENDER ACTUALLY LIVES, and it was not here.  This read
-- `save.playerGender`, which nothing in the engine ever writes -- not the
-- save importer, which decodes it to `save.player.gender` as "boy"/"girl",
-- and not the new game, which writes the same field from the Birch speech's
-- boy-or-girl question.  So every player was a boy, silently: the truck the
-- game starts in branches on this, and the girl's branch was unreachable.
function Commands.g3_check_gender(ctx)
  local player = ctx.save and ctx.save.player
  local g = player and player.gender
  local female = (g == "girl" or g == "female" or g == 1)
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

local DIRECTIONS = { [1] = "down", [2] = "up", [3] = "left", [4] = "right" }
local FACING_VALUE = { down = 1, up = 2, left = 3, right = 4 }

-- TURNING WHOEVER THE SCRIPT MEANT, which for $FF is the PLAYER.
--
-- Commands.face is Gen 1 and Gen 2's, and there it means "the NPC whose
-- script this is turns that way" -- it writes ctx.npc.facing.  Everywhere a
-- Gen 3 script names $FF it means the player, so routing the player case
-- into Commands.face turned the person being TALKED TO instead of the
-- person talking, or, in a scene with no ctx.npc at all, nobody.
--
-- That is the whole of "during events my character doesn't face the right
-- direction".  `turnobject OBJ_EVENT_ID_PLAYER, DIR_NORTH` is how Emerald
-- turns the player toward whoever has just walked up to them, and the first
-- one in the game is Birch's lab: its entry table is one command long and it
-- is exactly this.
local function turnTo(ctx, index, dir)
  if not dir then return end
  if index then
    Commands.face_object(ctx, index, dir)
  else
    Commands.face_player_dir(ctx, dir)
  end
end

-- Which way `from` has to turn to look at `to` -- or away from it.  The
-- bigger separation wins, which is what makes a diagonal read as the
-- direction it mostly is rather than always picking one axis.
local function towards(from, to, away)
  if not (from and to and from.cellX and to.cellX) then return nil end
  local dx = (to.cellX or 0) - (from.cellX or 0)
  local dy = (to.cellY or 0) - (from.cellY or 0)
  if away then dx, dy = -dx, -dy end
  if math.abs(dx) > math.abs(dy) then
    return dx < 0 and "left" or "right"
  elseif dy ~= 0 then
    return dy < 0 and "up" or "down"
  end
  return dx < 0 and "left" or (dx > 0 and "right" or nil)
end

-- `lock` is where a talk script begins, and it is where the cartridge's own
-- facing var has to be true: the branches that read it come a few commands
-- later.  Scripts that never lock -- map transitions, callbacks -- do not
-- branch on it either, because there is no player standing anywhere in
-- particular when they run.
function Commands.g3_lock(ctx)
  ctx.g3Locked = true
  local player = ctx.overworld and ctx.overworld.player
  local facing = player and player.facing
  setVar(ctx.save, VAR_FACING, FACING_VALUE[facing] or 1)
  -- ...and WHO was talked to, which is a var like any other on this
  -- cartridge.  Std_FindItem removes the object VAR_LAST_TALKED names --
  -- that is the mechanism by which a Poke Ball on the ground disappears once
  -- you pick it up -- and plenty of ordinary scripts move or turn "the one
  -- you are talking to" the same way.
  local npc = ctx.npc
  local index = npc and npc.def and npc.def.index
  if index then setVar(ctx.save, VAR_LAST_TALKED, index) end
end

function Commands.g3_release(ctx) ctx.g3Locked = nil end

-- APPLYMOVEMENT STARTS A WALK. IT DOES NOT WAIT FOR ONE.
--
-- This is the difference between a cutscene and a queue. Emerald writes "the
-- rival leads you to the lab" as
--
--     applymovement RIVAL, Movement_WalkToLab
--     applymovement OBJ_EVENT_ID_PLAYER, Movement_FollowHim
--     waitmovement 0
--
-- and the two walks run TOGETHER, which is the whole point: the player is
-- alongside. Lowering applymovement to a blocking move made them run one
-- after the other -- the rival walked the full route, and only once he had
-- stopped did the player set off after him. Every led-by-the-hand scene in
-- the game played as two solos.
--
-- So a movement is started here and chained step to step through
-- scriptMove's own onDone (which updateScriptMoves is written to support:
-- a step queued by a completing step begins the SAME frame). Nothing yields.
-- waitmovement is what blocks, and it blocks on the object it names.
-- ONE STEP OF A MOVEMENT SCRIPT, read off its name.
--
-- Every action's name is `<kind>_<direction>` -- `walk_down`, `jump_right`,
-- `walk_fast_up`, `in_place_left` -- whether it was named by hand (ids
-- $00-$18) or derived from the cartridge (the direction quartets). So the
-- reader parses the two halves rather than keeping a list, and an action
-- named later needs no change here.
--
--   walk / walk_slow / walk_fast / jump   one tile that way
--   jump2                                 two tiles
--   face                                  turn on the spot
--   in_place                              turn, and play the walk cycle
--                                         without leaving the cell
--   delay_N                               N frames
--
-- An action still without a name is skipped rather than guessed at, and it is
-- 213 of the cartridge's 5581 steps rather than the 1380 it was before the
-- quartets were derived.
local DIRECTIONS4 = { down = true, up = true, left = true, right = true }

local MOVE_TILES = {
  walk = 1, walk_slow = 1, walk_fast = 1, walk_fastest = 1,
  jump = 1, jump2 = 2, jump_in_place = 0,
}

local startMovement

local function movementSteps(rows)
  local steps = {}
  local pending, count = nil, 0
  local function flush()
    if pending and count > 0 then
      steps[#steps + 1] = { kind = "walk", dir = pending, count = count }
    end
    pending, count = nil, 0
  end
  for _, row in ipairs(rows) do
    local name = row[1]
    local kind, dir = name:match("^(.-)_(%a+)$")
    if kind and dir and DIRECTIONS4[dir] and MOVE_TILES[kind] then
      local tiles = MOVE_TILES[kind]
      if tiles > 0 then
        -- consecutive identical steps coalesce: the engine's move verbs take
        -- a count, and issuing eight one-tile moves makes the walk stutter
        if pending == dir then count = count + tiles
        else flush(); pending, count = dir, tiles end
      else
        flush()
        steps[#steps + 1] = { kind = "face", facing = dir }
      end
    elseif kind == "face" and DIRECTIONS4[dir] then
      flush()
      steps[#steps + 1] = { kind = "face", facing = dir }
    elseif kind == "in_place" and DIRECTIONS4[dir] then
      -- turns and plays the walk cycle without leaving the cell; the engine
      -- has exactly that, and facing first is what makes it read as a turn
      flush()
      steps[#steps + 1] = { kind = "face", facing = dir }
      steps[#steps + 1] = { kind = "march" }
    elseif name:match("^delay_") then
      flush()
      steps[#steps + 1] = { kind = "pause",
                            frames = tonumber(name:match("(%d+)$")) or 1 }
    elseif name == "face_player" or name == "face_away_player" then
      -- A TURN, not a flourish.  An NPC that should face you during a scene
      -- and does not reads as the scene being broken.
      flush()
      steps[#steps + 1] = { kind = "facePlayer",
                            away = (name == "face_away_player") }
    elseif name == "face_original_direction" then
      flush()
      steps[#steps + 1] = { kind = "faceOriginal" }
    elseif name == "bow_down" or name == "rock_smash_break"
           or name == "cut_tree" then
      -- animations this port has no picture for; the BEAT is kept so the
      -- next line does not land on top of the moment it belongs to
      flush()
      steps[#steps + 1] = { kind = "pause", frames = 24 }
    elseif name == "affine_anim_start" or name == "affine_anim_clear" then
      -- a sprite transform, not a movement: nothing to do and nothing to wait
      -- for, so it is recognised and costs no time
      flush()
    elseif name == "set_invisible" or name == "set_visible" then
      -- NOT COSMETIC.  These are how a script makes somebody vanish or
      -- appear mid-scene, and set_invisible is the most-used unnamed action
      -- on the cartridge -- dropping it left objects standing exactly where
      -- the script meant them to be gone.
      flush()
      steps[#steps + 1] = { kind = "visible", on = (name == "set_visible") }
    elseif name == "lock_facing" or name == "unlock_facing" then
      flush()
      steps[#steps + 1] = { kind = "lockFacing",
                            on = (name == "lock_facing") }
    elseif name:match("^emote_") then
      -- the bubble itself is a sprite this port has not extracted, so the
      -- BEAT is kept and the picture is not: a scene that pauses where the
      -- cartridge pauses still reads, where one that skips the pause runs
      -- its next line on top of the moment it was reacting to
      flush()
      steps[#steps + 1] = { kind = "pause", frames = 32 }
    else
      -- an action the port has no equivalent for: skip the step rather than
      -- guess at it, and let the rest of the movement still play.  It is
      -- LOGGED, though -- silently dropping one is how set_invisible went
      -- eighty-one uses without anybody noticing.
      flush()
      if name:match("^movement_") then
        Logger.warn("gen3 movement: %s has no equivalent -- step dropped",
                    name)
      end
    end
  end
  flush()
  return steps
end

local function movementKey(index) return index or "player" end

-- One walk step of the camera object: sixteen pixels in that direction,
-- ramped over the frames a walked tile takes, laid on cameraPan.  Declared
-- here rather than beside the specials because g3_move is its only caller and
-- the two have to agree about what a step is.
local GEN3_CAMERA_OBJECT_ID = 127          -- OBJ_EVENT_ID_CAMERA
local GEN3_CAMERA_TILE = 16                -- pixels in one metatile
local GEN3_CAMERA_FRAMES = 8               -- ...and frames to cross one
local CAMERA_DELTA = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}

local function cameraMove(ctx, ow, steps)
  local pan = ow.cameraPan or { ox = 0, oy = 0 }
  ow.cameraPan = pan
  local at = 0
  local state = { done = false, entity = false, index = GEN3_CAMERA_OBJECT_ID }
  local key = "camera"
  ctx.g3Moving = ctx.g3Moving or {}
  ctx.g3Moving[key] = state
  ctx.g3LastMoved = key

  local function advance()
    at = at + 1
    local step = steps[at]
    if not step then
      state.done = true
      if state.waiting then
        state.waiting = false
        if ctx.g3Waiting == state then ctx.g3Waiting = nil end
        ctx.runner:resume()
      end
      return
    end
    local delta = step.kind == "walk" and CAMERA_DELTA[step.dir]
    if not delta then
      -- a pause, a turn, an emote: the camera has no body to do it with, so
      -- the step costs its frames and nothing else
      local frames = step.frames or 0
      if frames > 0 then
        pan.fromX, pan.fromY = pan.ox, pan.oy
        pan.toX, pan.toY = pan.ox, pan.oy
        pan.t, pan.frames, pan.onDone = 0, frames, advance
      else
        advance()
      end
      return
    end
    local count = step.count or 1
    pan.fromX, pan.fromY = pan.ox, pan.oy
    pan.toX = pan.ox + delta[1] * GEN3_CAMERA_TILE * count
    pan.toY = pan.oy + delta[2] * GEN3_CAMERA_TILE * count
    pan.t = 0
    pan.frames = GEN3_CAMERA_FRAMES * count
    pan.onDone = advance
  end
  advance()
end

-- The key every map in this dataset is filed under.  Declared HERE rather
-- than beside the warp commands that also use it because a `local function`
-- is only in scope BELOW its own declaration: `elsewhereThan` sits above the
-- warps, and reading it from down there would have found a global and nil.
local function mapKey(group, number)
  return ("MAP_G%02d_N%02d"):format(tonumber(group) or 0, tonumber(number) or 0)
end
Gen3Commands.mapKey = mapKey

-- THE MAP AN "AT" COMMAND NAMES, or nil when it names none.  Returns true
-- when the command is talking about somewhere else, which is the whole point:
-- `applymovementat` and `waitmovementat` carry a map, and the port used to
-- throw it away and act on the object of the SAME index on whatever map the
-- player is standing on -- a different person entirely.  A cutscene staging
-- someone in another room then walked a bystander here, and the
-- `waitmovementat` behind it waited on that bystander's walk.
--
-- The cartridge does nothing visible for an object on a map that is not
-- loaded, so neither does this.
local function elsewhereThan(ctx, group, number)
  if group == nil or number == nil then return false end
  local g, n = tonumber(group), tonumber(number)
  if not (g and n) then return false end
  local ow = ctx.overworld
  local here = ow and ow.map and ow.map.id
  if type(here) ~= "string" then return false end
  return here ~= mapKey(g, n)
end

-- WHERE A PAIRED WALK STARTS FROM, said out loud once per scene.
--
-- Reported from play, twice, and the second time exactly: "when wally turns
-- right towards the route im one block above him instead of behind him".
-- Petalburg's script walks the two of them with two applymovements and one
-- waitmovement, and the cartridge's own arithmetic has the PLAYER descend one
-- more tile than Wally -- seven against eight -- so they finish the leg on
-- the same row with the player directly behind him for the walk east.
--
-- The movement lists are read correctly and the steps are executed
-- correctly, so a whole tile of error has to come from where somebody was
-- STANDING when the scene began -- and that is the one number no screenshot
-- shows and no test here can guess.  So the port says it: when a second
-- applymovement joins one already in flight, both walkers' cells and both
-- lists' net displacement go in the log, once, with the map.  The next report
-- of a scene walking wrong arrives with the measurement attached instead of
-- needing another round of questions.
local GEN3_STEP_DELTA = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}

local function movementNet(steps)
  local dx, dy, tiles = 0, 0, 0
  for _, step in ipairs(steps) do
    local d = step.kind == "walk" and GEN3_STEP_DELTA[step.dir]
    if d then
      dx = dx + d[1] * step.count
      dy = dy + d[2] * step.count
      tiles = tiles + step.count
    end
  end
  return dx, dy, tiles
end

-- published so the suite can check the arithmetic the log line prints
Gen3Commands.movementNet = movementNet

local function notePairedWalk(ctx, ow, entity, index, label, steps)
  local moving = ctx.g3Moving
  if not moving then return end
  -- the other half of the pair: something already walking that is not this
  local other, otherKey = nil, nil
  for key, state in pairs(moving) do
    if not state.done and state.entity and state.entity ~= entity then
      other, otherKey = state, key
    end
  end
  if not other then return end
  local function cellOf(e)
    return ("(%s,%s)"):format(tostring(e and e.cellX), tostring(e and e.cellY))
  end
  local dx, dy, tiles = movementNet(steps)
  local odx, ody, otiles = movementNet(other.steps or {})
  Logger.info("gen3 paired walk on %s: %s at %s takes %s net (%+d,%+d) over "
              .. "%d tile(s); %s at %s takes %s net (%+d,%+d) over %d tile(s)"
              .. " -- gap changes by (%+d,%+d)",
              tostring(ow.map and ow.map.id),
              tostring(otherKey), cellOf(other.entity),
              tostring(other.label), odx, ody, otiles,
              tostring(index or "player"), cellOf(entity), tostring(label),
              dx, dy, tiles, dx - odx, dy - ody)
end

function Commands.g3_move(ctx, target, movementLabel, group, number)
  if elsewhereThan(ctx, group, number) then return end
  local pool = ctx.game and ctx.game.data and ctx.game.data.map_scripts
  local rows = pool and pool.movements and pool.movements[movementLabel]
  local ow = ctx.overworld
  if not (rows and ow) then return end
  local index = objectId(ctx, target)

  -- THE CAMERA IS NOT A PERSON, but the cartridge walks it like one.  When
  -- SpawnCameraObject is up, applymovement on the camera's object id pans the
  -- view instead of moving anybody: each walk step becomes sixteen pixels of
  -- cameraPan, ramped over the same frames a walk takes, so the pan and a
  -- person's walk in the same scene stay in step.
  if index == GEN3_CAMERA_OBJECT_ID and ctx.g3CameraObject then
    return cameraMove(ctx, ow, movementSteps(rows))
  end

  local entity = index and ow:npcByIndex(index) or (not index and ow.player)
  if not entity then return end
  return startMovement(ctx, ow, entity, index, movementLabel, rows)
end

-- The tail of g3_move, from the point the actor is known.  ON ITS OWN because
-- the rotating tile puzzle (below) starts walks on objects it found by what
-- they are STANDING ON rather than by an object id a script named, and a
-- second copy of the bookkeeping below is a second place for waitmovement to
-- go wrong.
function startMovement(ctx, ow, entity, index, movementLabel, rows)
  local steps = movementSteps(rows)
  local key = movementKey(index)
  ctx.g3Moving = ctx.g3Moving or {}
  -- waitmovement with no object named waits on the last one started, which is
  -- what `waitmovement 0` means on the cartridge
  ctx.g3LastMoved = key

  -- the entity and its index travel with the wait so g3_wait_move can tell
  -- whether the thing it would be waiting for is still there
  local state = { done = false, entity = entity, index = index,
                  steps = steps, label = movementLabel }
  notePairedWalk(ctx, ow, entity, index, movementLabel, steps)
  ctx.g3Moving[key] = state

  local at = 0
  local function advance()
    at = at + 1
    local step = steps[at]
    if not step then
      state.done = true
      if state.waiting then
        state.waiting = false
        if ctx.g3Waiting == state then ctx.g3Waiting = nil end
        ctx.runner:resume()
      end
      return
    end
    if step.kind == "walk" then
      ow:scriptMove(entity, step.dir, step.count, advance)
    elseif step.kind == "pause" then
      ow:scriptPause(entity, step.frames, advance)
    elseif step.kind == "march" then
      if ow.marchInPlace then ow:marchInPlace(entity, advance) else advance() end
    elseif step.kind == "visible" then
      entity.hidden = not step.on
      if index and ow.syncObjectVisibility then
        pcall(ow.syncObjectVisibility, ow, entity)
      end
      advance()
    elseif step.kind == "lockFacing" then
      entity.facingLocked = step.on or nil
      advance()
    elseif step.kind == "facePlayer" then
      local player = ow.player
      local dir = player and towards(entity, player, step.away)
      turnTo(ctx, index, dir)
      advance()
    elseif step.kind == "faceOriginal" then
      -- the facing the map def gave it, which is where it was standing before
      -- the scene started moving it about
      local home = entity.def and entity.def.facing or entity.spawnFacing
      turnTo(ctx, index, home)
      advance()
    else
      turnTo(ctx, index, step.facing)
      advance()
    end
  end
  advance()
end

-- `waitmovement 0` names no object and waits on the last applymovement's.
-- A WAIT THAT CANNOT END IS A PLAYER WHO CANNOT MOVE.
--
-- waitmovement yields until the movement it names reports done, and the
-- report comes from the overworld's own step callback.  If the thing that was
-- walking stops existing before it finishes -- the map changed under it, a
-- flag hid it, a scene removed it -- that callback never fires, the script
-- never resumes, and the field is frozen for the rest of the session with no
-- error anywhere.
--
-- So the wait records which map it was made on, and anything that changes the
-- map settles it (see releaseMapWaits).  It also refuses to wait at all on an
-- entity that is not on the map any more, which is the same failure caught a
-- moment earlier.
function Commands.g3_wait_move(ctx, target, group, number)
  if elsewhereThan(ctx, group, number) then return end
  local raw = tonumber(target) or 0
  local key
  if raw == 0 then key = ctx.g3LastMoved
  else key = movementKey(objectId(ctx, target)) end
  local state = key and ctx.g3Moving and ctx.g3Moving[key]
  if not state or state.done then return end

  local ow = ctx.overworld
  if state.entity and ow then
    local gone = state.entity.removed or state.entity.despawned
    if type(state.index) == "number" and ow.npcByIndex
       and ow:npcByIndex(state.index) ~= state.entity then
      gone = true
    end
    if gone then
      state.done = true
      return
    end
  end

  state.waiting = true
  state.mapId = ow and ow.map and ow.map.id
  ctx.g3Waiting = state
  ctx.runner:yield()
end

-- Called when the map changes.  Anything still waiting on a movement that
-- belonged to the old map is settled: the walk it was waiting for cannot
-- finish now, and a script that never resumes is a locked player.
function Gen3Commands.releaseMapWaits(ctx, newMapId)
  local state = ctx and ctx.g3Waiting
  if not (state and state.waiting) then return false end
  if state.mapId and newMapId and state.mapId == newMapId then return false end
  state.waiting = false
  state.done = true
  ctx.g3Waiting = nil
  Logger.debug("gen3: a waitmovement on %s was settled by the move to %s",
               tostring(state.mapId), tostring(newMapId))
  if ctx.runner and ctx.runner.resume then ctx.runner:resume() end
  return true
end

function Commands.g3_turn(ctx, target, direction)
  local index = objectId(ctx, target)
  local facing = DIRECTIONS[tonumber(direction) or 0]
  if not facing then return end
  turnTo(ctx, index, facing)
end

-- ADDOBJECT / REMOVEOBJECT, and why Mom stood at the top of the stairs
-- for the rest of the game.
--
-- These used to hand off to Commands.show_object / hide_object, which are the
-- Gen 1/2 pair -- and their signature is (ctx, mapId, objName).  The object
-- INDEX was going in as the map id and the name was going in as nil, so every
-- addobject and every removeobject in Hoenn wrote a toggle for a map that does
-- not exist under a name that is not there, and did nothing at all.
--
-- The clock scene is where it shows.  Its script is
--
--     setvar VAR_0x8008, 14      @ Mom's local id in the bedroom
--     addobject VAR_0x8008
--     applymovement VAR_0x8008 ...   @ she walks in, talks, walks out
--     ...
--     removeobject VAR_0x8008
--
-- so the LAST thing that scene does is take her away again.  With
-- removeobject inert she stayed exactly where the map table puts her, which
-- is the cell at the top of the stairs, and there was no way past.
--
-- A GEN 3 OBJECT IS AN INDEX, not a name, and what decides whether it is on
-- the map is its own event flag -- set means hidden, which is the polarity
-- the spawn branch and InitEventData between them settle.  So this writes
-- that flag and re-syncs the live list, which is the same pair of things the
-- map load does, and the change survives walking out and back in.
local function gen3Toggle(ctx, target, visible)
  local index = objectId(ctx, target)
  if not index then
    -- $FF IS THE PLAYER HERE TOO, and 29 scripts rely on it: the cartridge
    -- takes the player off screen with `hideobjectat OBJ_EVENT_ID_PLAYER`
    -- whenever they step into a doorway, and puts them back afterwards.
    -- There is no object record to gate, and there does not need to be --
    -- the player is never removed from the entity list, so the flag on the
    -- entity is the whole of it.
    if tonumber(target) == PLAYER_OBJECT then
      local player = ctx.overworld and ctx.overworld.player
      if player then player.hidden = (not visible) or nil end
      return
    end
    -- otherwise almost always an unset scratch variable: the script said
    -- `removeobject VAR_0x8008` and nothing had put an id in it
    Logger.info("gen3: %s object %s resolved to nothing -- an unset variable?",
                visible and "add" or "remove", tostring(target))
    return
  end
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  local obj
  for _, o in ipairs((def and def.objects) or {}) do
    if o.index == index then obj = o break end
  end
  if not obj then
    Logger.info("gen3: no object %s on this map to %s", tostring(index),
                visible and "add" or "remove")
    return
  end
  local save = ctx.save
  local mapId = (ow and ow.map and ow.map.id) or ctx.mapId
  if save and obj.eventFlag then
    save.flags = save.flags or {}
    -- EXPLICIT BOTH WAYS, not "set or absent".  An object the map's own
    -- scripts spawn starts hidden whatever its flag says (see objectVisible),
    -- so `addobject` has to record a positive "yes, this one is here" rather
    -- than merely clearing the flag back to its default.
    save.flags[obj.eventFlag] = not visible
  end
  -- ...and for an object with no flag of its own, the same answer per map
  if save and mapId then
    save.gen3Spawned = save.gen3Spawned or {}
    save.gen3Spawned[mapId] = save.gen3Spawned[mapId] or {}
    save.gen3Spawned[mapId][index] = visible
  end
  -- AN OBJECT WITH NO FLAG IS TAKEN AWAY FOR THIS VISIT ONLY.
  --
  -- `gen3Spawned` above is read only for objects a map script SPAWNS -- see
  -- objectVisible -- so an object that is simply standing there and is
  -- removed by a scene had its removal written where nothing would read it,
  -- and stayed on screen.  Fourteen objects in Hoenn are that shape.
  --
  -- Session-scoped, because that is what the cartridge does: RemoveObjectEvent
  -- writes the loaded map's object struct and the next map load rebuilds every
  -- struct from the map's own object_events.  A script that means "gone for
  -- good" sets the object's own event flag, which is the branch above.
  if save and mapId and not obj.eventFlag then
    local session = save.gen3SessionObjects
    if type(session) ~= "table" or session.mapId ~= mapId then
      session = { mapId = mapId }
      save.gen3SessionObjects = session
    end
    session[index] = visible and true or false
  end
  if not ow then return end
  -- A REMOVED OBJECT MUST NOT BE LEFT WALKING.  removeobject lands in the
  -- middle of a cutscene, and an entity taken off the map with steps still in
  -- the queue leaves those steps to tick against nothing.
  if not visible then
    local npc = ow.npcByIndex and ow:npcByIndex(index)
    if npc then
      npc.moving, npc.marching = false, nil
      npc.targetX, npc.targetY = nil, nil
      for i = #(ow.scriptMoves or {}), 1, -1 do
        if ow.scriptMoves[i].entity == npc then
          table.remove(ow.scriptMoves, i)
        end
      end
    end
  end
  if ow.syncObjectVisibility then ow:syncObjectVisibility(obj) end
end

function Commands.g3_show_object(ctx, target)
  gen3Toggle(ctx, target, true)
end

function Commands.g3_hide_object(ctx, target)
  gen3Toggle(ctx, target, false)
end

-- SETOBJECTXY $FF IS "PUT THE PLAYER THERE", and it was being dropped.
--
-- objectId answers nil for $FF because nil means "the player" everywhere else
-- in this file -- applymovement, waitmovement, turnobject all read it that
-- way.  Here nil meant "do nothing", so every script that teleports the
-- player before a scene starts silently left them where they were standing
-- and the scene played out around the wrong spot.
--
-- The starter scene is the one that shows.  Route 101's bag script opens
--
--     removeobject LOCALID_ZIGZAGOON
--     setobjectxy OBJ_EVENT_ID_PLAYER, 6, 13
--     applymovement OBJ_EVENT_ID_PLAYER, ...
--
-- placing the player at the bag before walking them up to it.  Without the
-- placement the walk starts from wherever they happened to press A.
function Commands.g3_place(ctx, target, x, y)
  local index = objectId(ctx, target)
  if index then
    Commands.place_npc(ctx, index, tonumber(x), tonumber(y))
    return
  end
  local player = ctx.overworld and ctx.overworld.player
  local cx, cy = tonumber(x), tonumber(y)
  if not (player and cx and cy) then return end
  player.cellX, player.cellY = cx, cy
  player.px, player.py = cx * 16, cy * 16
  player.moving = false
  player.targetX, player.targetY = nil, nil
  local map = ctx.overworld.map
  if map and map.cellElevation then
    player.elevation = map:cellElevation(cx, cy) or player.elevation
  end
end

-- The "perm" form writes the object's TEMPLATE position, which is where it
-- respawns from on the next map load; the port keeps that on the save so a
-- staged cutscene survives walking out and back in.
-- WHERE AN OBJECT LIVES, as opposed to where it happens to be standing.
--
-- `setobjectxyperm` and `copyobjectxytoperm` do not move anything for the
-- scene in front of you: they change where the object will BE the next time
-- the map is built.  A cutscene that walks somebody to a new spot ends with
-- one of these, and without it they are back where they started the moment
-- you leave the room and come back.
--
-- Both halves of this were broken, which is why it never worked rather than
-- worked badly.  `copyobjectxytoperm` was not lowered at all, so it was
-- dropped.  And the store `setobjectxyperm` wrote had NO READER anywhere in
-- the engine -- the home was recorded faithfully and then ignored on every
-- map load.  See objectHome in OverworldController for the other half.
local function rememberHome(ctx, target, x, y)
  local save = ctx.save
  local mapId = ctx.mapId
    or (ctx.overworld and ctx.overworld.map and ctx.overworld.map.id)
  if not (save and mapId and x and y) then return end
  save.gen3ObjectHomes = save.gen3ObjectHomes or {}
  local perMap = save.gen3ObjectHomes[mapId] or {}
  save.gen3ObjectHomes[mapId] = perMap
  perMap[tonumber(target) or 0] = { x = math.floor(x), y = math.floor(y) }
end

function Commands.g3_place_perm(ctx, target, x, y)
  Commands.g3_place(ctx, target, x, y)
  rememberHome(ctx, target, tonumber(x), tonumber(y))
end

-- ...and this one takes the position the object is standing on RIGHT NOW,
-- which is the whole point: a script that has just walked somebody somewhere
-- does not want to restate the coordinates it walked them to.
function Commands.g3_copy_xy_to_perm(ctx, target)
  local index = objectId(ctx, target)
  local ow = ctx.overworld
  local entity = index and ow and ow:npcByIndex(index)
                 or (not index and ow and ow.player)
  if not entity then return end
  rememberHome(ctx, index or 0, entity.cellX, entity.cellY)
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

-- THE ITEM NUMBER A SCRIPT SAYS, TURNED INTO THE KEY THE BAG USES.
--
-- This used to format "ITEM_G3_063" and hand that to the bag.  Nothing is
-- keyed that way: the items module is keyed by name -- HP_UP, MYSTICTICKET,
-- TM38 -- with the cartridge's number in an `index` field.  So every additem
-- and every removeitem in Hoenn asked for a key that does not exist and
-- silently did nothing: the 302 pickups, the mart, the TMs, the held item on
-- a gift Pokemon.  It is the identical mistake `givemon` was making with
-- species numbers, and it takes the identical fix -- the extractor's own
-- number-to-name map, built while it reads the table.
--
-- A number with no entry answers nil rather than a made-up key, so a
-- dataset without the map degrades to "no such item" instead of handing the
-- bag something it will choke on.  ITEM_NONE (0) is a real value scripts
-- pass -- `givemon` with no held item -- and it is not an item.
local function itemIdFor(data, n)
  n = tonumber(n)
  if not n or n <= 0 then return nil end
  local order = data and data.constants and data.constants.itemOrder
  local id = order and order[n]
  return type(id) == "string" and id or nil
end
-- ...and the operand may name a VAR rather than be a number.  `additem
-- VAR_0x8000, VAR_0x8001` is how every item the std scripts hand over is
-- written, so resolving the var is not an edge case, it is the common case.
local function itemId(ctx, n)
  return itemIdFor(ctx and ctx.game and ctx.game.data, valueOf(ctx, n))
end
Gen3Commands.itemId = itemIdFor

function Commands.g3_give_item(ctx, item, quantity)
  local id = itemId(ctx, item)
  if id then Commands.give_item(ctx, id, tonumber(quantity) or 1) end
  setVar(ctx.save, VAR_RESULT, 1)
  setResult(ctx, 1)
end

function Commands.g3_take_item(ctx, item, quantity)
  local id = itemId(ctx, item)
  if id then Commands.take_item(ctx, id, tonumber(quantity) or 1) end
  setVar(ctx.save, VAR_RESULT, 1)
  setResult(ctx, 1)
end

-- HOW MANY OF AN ITEM THE PLAYER IS CARRYING.
--
-- THIS READ THE WRONG TABLE, and it read it silently.  `save.bag` is not a
-- field this engine has ever had -- the bag is `save.inventory`, a flat
-- id -> count map that Bag.add and Commands.take_item both write -- so the
-- lookup found nil, returned 0, and EVERY `checkitem` in every Hoenn script
-- answered "you do not have one."
--
-- Reported from play twice over, and they are the same bug:
--
--   "the lady you give the harbor mail to in mauville city for the coin case
--    isnt working i cant give her the harbor mail even though i have it in my
--    bag"  -- S0210C5D: checkitem HARBOR_MAIL / compare VAR_RESULT, 1.
--
--   "nobody in the gamecorner is recognizing that i have a coin case"
--    -- seventeen scripts in Mauville open with checkitem COIN_CASE, and the
--    prize counters, the coin sellers and both slot machines all sit behind
--    one of them.
--
-- Badges live in the same table and are not carryable items, so they are
-- skipped the way the bag itself skips them.
local function bagCount(ctx, item)
  local inv = ctx.save and ctx.save.inventory
  if type(inv) ~= "table" then return 0 end
  local want = itemId(ctx, item)
  if type(want) ~= "string" then return 0 end
  if require("src.inventory.Bag").isBadge(want) then return 0 end
  return tonumber(inv[want]) or 0
end
Gen3Commands.bagCount = bagCount

function Commands.g3_check_item(ctx, item, quantity)
  local has = bagCount(ctx, item) >= (tonumber(quantity) or 1)
  setVar(ctx.save, VAR_RESULT, has and 1 or 0)
  setResult(ctx, has and 1 or 0)
end

function Commands.g3_check_item_space(ctx)
  setVar(ctx.save, VAR_RESULT, 1)
  setResult(ctx, 1)
end

-- A SCRIPT NAMES A SPECIES BY NUMBER; THE DATASET IS KEYED BY NAME.
--
-- `givemon 155` is the cartridge's internal species index.  Every table in
-- this port is keyed by the dataset's own id -- "CYNDAQUIL", "TREECKO" --
-- and `constants.speciesOrder` is the bridge between the two, exactly as
-- Player:refreshForm uses it for sprites.  Handing the raw number straight to
-- give_pokemon reached `data.pokemon[155]`, which is nil on a Gen 3 cache, and
-- every `givemon` in Hoenn died on the lookup.  The whole-cartridge smoke test
-- is what surfaced it: 805 raises across four verbs, all of them this.
local function speciesId(data, n)
  n = tonumber(n)
  if not n then return nil end
  local order = data and data.constants and data.constants.speciesOrder
  return (order and order[n]) or n
end
Gen3Commands.speciesId = speciesId

function Commands.g3_give_pokemon(ctx, species, level, item)
  local id = speciesId(ctx.game and ctx.game.data, species)
  if not id then return end
  -- The fourth argument is skipNickname, not the held item -- passing the
  -- item there threw the item away.  And it is TRUE: Emerald has no naming
  -- prompt of its own to suppress.
  --
  -- THIS IS A GENERATION DIFFERENCE, not a missing feature.  Gen 2's
  -- AddPartyMon asks "Give a nickname to X?" the moment a Pokemon is handed
  -- over, so `give_pokemon` asks by default and every Gen 2 gift is right.
  -- Emerald's ScriptGiveMon does not ask at all; naming is a separate script
  -- step, which is why the cartridge carries a shared script for it --
  --
  --     setvar VAR_0x8004, 0        @ which party slot
  --     call <common naming script> @ fadescreen / special 161 / waitstate
  --
  -- and why all seven `givemon` sites in Hoenn are followed by a msgbox
  -- asking the question the port was asking for them.  Left on, the keyboard
  -- came up the instant Birch's bag was opened, on Route 101, with the
  -- Poochyena still standing over him -- instead of in the lab where Birch
  -- offers it.
  Commands.give_pokemon(ctx, id, tonumber(level), true,
                        { heldItem = itemId(ctx, item) })
  setVar(ctx.save, VAR_RESULT, 0)      -- 0 = "it went to the party"
  setResult(ctx, 0)
end

function Commands.g3_give_egg(ctx, species)
  local id = speciesId(ctx.game and ctx.game.data, species)
  if not id then return end
  -- an egg, and it really is one: give_pokemon takes the flag now rather
  -- than ignoring a fifth argument it never had
  Commands.give_pokemon(ctx, id, 5, true, { egg = true })
  setVar(ctx.save, VAR_RESULT, 0)
end

-- DOES ANYONE IN THE PARTY KNOW THIS MOVE, and which of them.
--
-- This is the gate in front of every field move on the cartridge.  The Cut
-- tree script is the shape they all share:
--
--     checkflag FLAG_BADGE01_GET     @ no badge, no cutting
--     checkpartymove MOVE_CUT
--     compare VAR_RESULT, PARTY_SIZE @ 6 means nobody
--     goto_if eq, "it looks like it could be cut down"
--     setfieldeffectargument 0, VAR_RESULT   @ ...which one of them
--
-- so VAR_RESULT is not a yes/no: it is the PARTY SLOT, zero based, and 6 is
-- the answer that means no.  The slot is then used to name the Pokemon in
-- the message and to animate the right one.
--
-- It was comparing the cartridge's move NUMBER against the entries in
-- mon.moves, and those are keyed by name -- POUND, CUT -- exactly like the
-- items were.  So the answer was always 6 and there was no cutting, no
-- smashing and no strength anywhere in Hoenn.  The first slot wins, which is
-- also what the cartridge does; the old loop let a later party member
-- overwrite an earlier one.
function Commands.g3_check_party_move(ctx, move)
  local save = ctx.save
  local party = (save and save.party) or {}
  local data = ctx.game and ctx.game.data
  local order = data and data.constants and data.constants.moveOrder
  local n = tonumber(move)
  local want = (order and n and order[n]) or n

  local slot = 6
  for index, mon in ipairs(party) do
    for _, m in ipairs(mon.moves or {}) do
      local id = (type(m) == "table") and m.id or m
      if id == want or id == n then
        slot = index - 1
        break
      end
    end
    if slot ~= 6 then break end
  end
  setVar(save, VAR_RESULT, slot)
  setResult(ctx, slot)
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

-- OPENING A SHOP.
--
-- Commands.open_mart is Gen 1 and Gen 2's: it looks the stock up by TEXT
-- CONSTANT, through the map's own text table, because that is where those
-- games keep it.  A Gen 3 `pokemart` carries a POINTER instead, and the list
-- behind it is the shop -- so handing the pointer to a lookup keyed by text
-- constants found nothing, and every counter in Hoenn opened onto an empty
-- shop.  No Poke Balls, no Potions, no Repels, for the whole game.
--
-- The extractor now follows those pointers and writes the lists beside the
-- scripts, so this is a lookup rather than a read.
function Commands.g3_mart(ctx, listPointer)
  local at = tonumber(listPointer)
  local pool = ctx.game and ctx.game.data and ctx.game.data.map_scripts
  local marts = pool and pool.marts
  local stock = at and marts and marts[("M%07X"):format(at - 0x08000000)]
  if not stock or #stock == 0 then
    Logger.warn("gen3: no stock list for the mart at %s -- the counter is "
                  .. "skipped rather than opening an empty shop",
                tostring(listPointer))
    return
  end
  local runner = ctx.runner
  local ok = pcall(function()
    require("src.ui.Screens").push(ctx.game, "ShopMenu", stock, function()
      if runner then runner:resume() end
    end)
  end)
  if not ok then return end
  if runner then runner:yield() end
end

-- THE FURNITURE COUNTERS.
--
-- Reported from play: "Also make sure the marts have all the proper items
-- theyre supposed to have for pokemon emerald as well as all merchants
-- throughout the game like fortree and slateport that arent in marts but
-- sell items."
--
-- The twenty-seven `pokemart` counters were already stocked; these ten were
-- not, because they sell decorations and a decoration id run through the item
-- table is a different object entirely.  The import reads each list against
-- gDecorations now, so they can open.
--
-- NO BUY/SELL MENU, and that is the cartridge's own shape: mode 0 builds the
-- three-row BUY / SELL / QUIT menu at 0x00DFA8E, and modes 1 and 2 branch
-- straight past it (0x00DFA8C) into the list.  You cannot sell furniture back.
function Commands.g3_decoration_mart(ctx, listPointer, shopMode)
  local at = tonumber(listPointer)
  local pool = ctx.game and ctx.game.data and ctx.game.data.map_scripts
  local shops = pool and pool.decorMarts
  local shop = at and shops and shops[("D%07X"):format(at - 0x08000000)]
  if not (shop and type(shop.items) == "table" and #shop.items > 0) then
    Logger.warn("gen3: no decoration list for the counter at %s -- it is "
                  .. "skipped rather than opening an empty shop",
                tostring(listPointer))
    return
  end
  local runner = ctx.runner
  local ok = pcall(function()
    local Gen3ShopMenu = require("src.ui.Gen3ShopMenu")
    ctx.game.stack:push(Gen3ShopMenu.new(ctx.game, {
      mode = "buy", kind = "decoration", stock = shop.items,
      shopMode = tonumber(shopMode) or shop.mode or 1,
      onQuit = function() if runner then runner:resume() end end,
    }))
  end)
  if not ok then return end
  if runner then runner:yield() end
end

-- ---------------------------------------------------------------------------
-- battles
-- ---------------------------------------------------------------------------

-- THE FLAG THAT SAYS A TRAINER HAS BEEN BEATEN, UNDER THE CARTRIDGE'S OWN
-- NUMBER.
--
-- This used to answer "FLAG_G3_TRAINER_0109" -- a namespace of its own, which
-- was self-consistent and reached nothing.  Emerald has no separate trainer
-- namespace: a trainer's flag is an ORDINARY flag at TRAINER_FLAGS_START + id,
-- in the same bit array as every other flag, which is why the region's scripts
-- can leave the whole block alone and the battle setup can own it.
--
-- The cost of the private name was in the SAVE.  Gen3Save round-trips flags by
-- walking the bit array and spelling each one "FLAG_G3_%04X"; a key shaped any
-- other way is not in that walk.  So importing a real Emerald save dropped
-- every trainer the player had beaten -- all 855 of them re-challenged on
-- sight -- and exporting one wrote a save that had beaten nobody.
--
-- The base is the import's, derived and corroborated there (see
-- RomExtractorGen3:fieldMoveGates).  With no base in the data there is no
-- honest answer, so this says so rather than inventing one.
local function trainerFlagBase(data)
  local constants = data and data.constants
  return constants and tonumber(constants.gen3TrainerFlagBase)
end

local function trainerFlag(n, data)
  local base = trainerFlagBase(data)
  if not base then return nil end
  return ("FLAG_G3_%04X"):format(base + (tonumber(n) or 0))
end
Gen3Commands.trainerFlag = trainerFlag

-- STARTING A BATTLE, and the two things that were wrong with it.
--
-- start_battle's first argument is the STRING "wild" or "trainer"; it decides
-- which of the two constructors runs and everything after it is positional.
-- Both of these were handing it a TABLE, which is neither string, so every
-- scripted battle in Hoenn -- the rival on Route 103, every gym leader, every
-- legendary -- went down the trainer branch with no trainer and no party, and
-- newTrainer asserts on that.  A raise inside a script command aborts the
-- command, and a script that aborts never reaches its release.
--
-- The second is the bridge.  `trainerbattle 0, 418` is how the cartridge
-- names a trainer, and the trainers module is keyed by NAME -- 418 is
-- MADELINE_438's index, not her key -- so even reaching the right branch with
-- the raw number finds nothing.  Same shape as the species, item, move and
-- ability bridges; same fix.
local function trainerIdFor(data, n)
  n = tonumber(n)
  if not n then return nil end
  local order = data and data.constants and data.constants.trainerOrder
  local id = order and order[n]
  return type(id) == "string" and id or nil
end
Gen3Commands.trainerIdFor = trainerIdFor

-- THE THREE MODES THAT ARE A DOUBLE BATTLE ON THEIR OWN.
--
-- 4 and 7 are TRAINER_BATTLE_DOUBLE and its rematch; 6 and 8 are the
-- continue-script doubles.  BattleSetup_ConfigureTrainerBattle (0B1430)
-- routes all four to sDoubleBattleParams or its continue-script twin, and
-- CheckTrainer (0B3D6E) reads the same mode byte off the object's script to
-- decide that one such trainer alone is already a double and no partner
-- should be looked for.
local DOUBLE_KINDS = { [4] = true, [6] = true, [7] = true, [8] = true }
Gen3Commands.DOUBLE_KINDS = DOUBLE_KINDS

local function startTrainer(ctx, trainerId, opts)
  local data = ctx.game and ctx.game.data
  local id = trainerIdFor(data, trainerId)
  if not id then
    Logger.warn("gen3: no trainer %s in this dataset -- the battle is skipped "
                  .. "rather than raising", tostring(trainerId))
    return
  end
  -- the second trainer, when two walked up: the same lookup, so a partner
  -- the dataset does not carry drops the pairing rather than raising
  if opts and opts.trainerB then
    opts.trainerBKey = trainerIdFor(data, opts.trainerB)
    if not opts.trainerBKey then
      Logger.warn("gen3: the second trainer %s is not in this dataset -- the "
                    .. "battle is fought against the first one alone",
                  tostring(opts.trainerB))
    end
  end
  -- a Gen 3 trainer is one record with one team, so the party index is 1
  Commands.start_battle(ctx, "trainer", id, 1, opts)
end
Gen3Commands.startTrainer = startTrainer

-- ---------------------------------------------------------------------------
-- AND WHAT HAPPENS WHEN YOU WIN.
--
-- A trainerbattle record carries, for four of its ten types, a POINTER TO THE
-- SCRIPT THAT RUNS ON A WIN -- and the import used to read the record only
-- far enough to get the type and the trainer, so that pointer went in the
-- bin.  117 of Hoenn's 565 trainer battles have one, and the eight gym
-- leaders are among them: ROXANNE's whole visible script is a trainerbattle,
-- and everything that happens after you beat her -- the STONE BADGE, the TM,
-- the words -- lives behind that pointer.
--
-- That is why the region's scripts CHECK the eight badge flags forty times
-- and SET them not once, and why no HM in Hoenn could ever be used.
--
-- start_battle yields until the battle is over, so by the time it returns the
-- result is known and the continuation can simply run here -- which is what
-- TRAINER_BATTLE_CONTINUE_SCRIPT means: execution continues THERE.
-- WHICH MODES ASK "HAVE I ALREADY LOST TO YOU?"
--
-- `trainerbattle` does not test the flag itself.  What it does is RETURN a
-- script, and it is that script which tests it.  Nine of the twelve modes
-- return one of two scripts and both of them open the same way:
--
--   EventScript_TryDoNormalTrainerBattle  0827_1362  (modes 0,1,2,9,12)
--   EventScript_TryDoDoubleTrainerBattle  0827_138A  (modes 4,6,8)
--       lock / faceplayer / the "!" bubble
--       specialvar VAR_RESULT, $39      -- GetTrainerFlag: FlagGet($500+id)
--       compare VAR_RESULT, 0
--       goto_if NE  ->  gotopostbattlescript
--
-- Mode 3 -- the no-intro variant -- returns 0827_13C2, which has NO check:
-- it is used where the script has already decided to fight.  Modes 5 and 7
-- return the rematch scripts, which gate on rematch readiness (special $3D)
-- rather than on the beaten flag, so they are left alone here too.
local FLAG_CHECKED_KINDS = {
  [0] = true, [1] = true, [2] = true, [4] = true,
  [6] = true, [8] = true, [9] = true, [12] = true,
}

-- ...AND THE ONE MODE THAT DOES NOT STOP WHEN YOU WIN.
--
-- Reported from play: "After battling may in the route below fortree city her
-- sprite stays there even though she drives away on her bike".  She does ride
-- away -- eleven commands after the battle -- and none of them ran.
--
-- There are TWO jumps out of a trainer battle and they do not go to the same
-- place.  `gotobeatenscript` ($5F) goes to the record's own continuation
-- pointer, and to `release / end` when the mode has none; `gotopostbattlescript`
-- ($5E) goes to the byte AFTER the record, which is the next command of the
-- script that ran the battle.  Modes 0, 1, 2 and the doubles end with the
-- first, which is why beating an ordinary trainer stops there and their line
-- waits for you to talk to them again.
--
-- MODE 3 ENDS WITH THE SECOND.  Its engine script is
--
--     0827_13C2  applymovement VAR_LAST_TALKED, reveal_trainer
--                waitmovement 0
--                special $3B
--                dotrainerbattle          $5D
--                gotopostbattlescript     $5E     <-- the byte after the record
--
-- and its record is ten bytes with no continuation pointer at all -- the
-- resume address is the cursor past the record, which TrainerBattleLoadArgs
-- stores through parameter type 6.  So mode 3 is the mode a CUTSCENE uses:
-- the intro is already on screen, the battle happens in the middle of the
-- script, and the script carries on.  Treating it like the others ended the
-- rival's scene the instant she was beaten, leaving her standing on Route 119
-- with her bike, her goodbye, HM02 and Scott all unreached.
local FALL_THROUGH_KINDS = { [3] = true }
Gen3Commands.FALL_THROUGH_KINDS = FALL_THROUGH_KINDS

-- AND WHERE `gotopostbattlescript` GOES.
--
-- Not to a pointer in the record: BattleSetup_GetScriptAddrAfterBattle
-- (0B1AF8) returns sTrainerBattleEndScript, and TrainerBattleLoadArgs stores
-- into that (0B13EC) THE CURSOR AFTER THE WHOLE RECORD -- the very next
-- instruction of the trainer's own script.  So on a re-talk the cartridge
-- simply falls through to the line after the trainerbattle, which is the
-- msgbox every beaten trainer says.  In this port those rows are already
-- sitting in the same compiled list, so falling through IS the behaviour:
-- returning nothing lets the runner advance to them.
--
-- What was happening instead: nothing read the flag on the talk path at all
-- (the SIGHT path was gated, which is why only talking re-triggered), so
-- every trainer in Hoenn fought you again, forever, every time you spoke to
-- them.
function Commands.g3_trainer_battle(ctx, kind, trainerId, winScript)
  ctx.g3Trainer = tonumber(trainerId)
  ctx.g3TrainerKind = tonumber(kind)
  local k = tonumber(kind) or 0
  if FLAG_CHECKED_KINDS[k] then
    local name = trainerFlag(ctx.g3Trainer, ctx.game and ctx.game.data)
    if name and (ctx.save or {}).flags and ctx.save.flags[name] == true then
      -- beaten already: gotopostbattlescript, i.e. run on into the next row
      return
    end
  end
  -- AND WHETHER THIS ONE IS A DOUBLE.
  --
  -- Modes 4, 6, 7 and 8 are doubles by the mode alone, and the script that
  -- each of them returns asks first whether you can field one: special 64,
  -- compare VAR_RESULT, 0, refuse on non-zero.  A trainer whose own
  -- doubleBattle byte is set is a double whatever the mode says, and that
  -- is decided further in, where the trainer record is in hand.
  -- ...OR BECAUSE TWO OF THEM WALKED UP TOGETHER.
  --
  -- CheckForTrainersWantingBattle (0B3BE8) collects up to two spotters and
  -- BattleSetup_StartTrainerBattle (0B17E0) then sets
  -- DOUBLE|TRAINER|TWO_OPPONENTS -- 0x8009 -- rather than plain TRAINER.
  -- The pair is not written into either trainer's script: it goes into
  -- gTrainerBattleOpponent_A and _B, and the ordinary trainerbattle in the
  -- FIRST one's script finds both there.  `gen3PartnerTrainer` on the
  -- context is that RAM.
  local partner = ctx.gen3PartnerTrainer
  local isDouble = DOUBLE_KINDS[k] or partner ~= nil
  if isDouble then
    local state = Gen3Commands.SPECIALS[64] and Gen3Commands.SPECIALS[64](ctx)
    setVar(ctx.save, VAR_RESULT, tonumber(state) or 0)
    if (tonumber(state) or 0) ~= 0 then
      -- EventScript_NoDoubleTrainerBattle: he says he needs you to have two,
      -- and no battle happens
      Logger.debug("gen3: trainer %s wants a double battle and the party "
                     .. "cannot field one -- no battle",
                   tostring(ctx.g3Trainer))
      return
    end
  end
  startTrainer(ctx, ctx.g3Trainer,
               isDouble and { double = true, trainerB = partner } or nil)
  if ctx.lastBattleResult == "win" and not FALL_THROUGH_KINDS[k] then
    -- ON A WIN THE CARTRIDGE DOES NOT FALL THROUGH.
    --
    -- dotrainerbattle always lands on `gotobeatenscript` (0827_1491), and
    -- BattleSetup_GetTrainerPostBattleScript (0B1B10) answers the record's
    -- OWN continuation for the four modes that carry one, and
    -- EventScript_ReleaseEnd (0827_42E6) for the rest.  Either way the bytes
    -- after the record -- the beaten trainer's line -- are NOT run on the
    -- turn you beat them; they are what you get when you come back.  The
    -- port used to run the continuation and then fall through as well, so a
    -- gym leader handed you the badge and then said her post-battle line in
    -- the same breath.
    if type(winScript) == "string" then
      Gen3Commands.runWinScript(ctx, winScript)
    end
    return "end"
  end
end

-- Compile the continuation and run it inside the script already running --
-- the runner cannot be re-entered, and it does not need to be: this is a
-- continuation of the same script rather than a new one.
function Gen3Commands.runWinScript(ctx, label)
  local runner = ctx.runner
  local data = ctx.game and ctx.game.data
  if not (runner and runner.exec and data) then return false end
  local ok, rows = pcall(function()
    return require("src.script.Gen3ScriptVM").compile(data, label)
  end)
  if not (ok and type(rows) == "table" and #rows > 0) then
    Logger.warn("gen3: the win script %s is not in this dataset -- the battle "
                  .. "stands, but whatever it handed over is skipped",
                tostring(label))
    return false
  end
  runner:exec(rows, ctx)
  return true
end

function Commands.g3_do_trainer_battle(ctx)
  if ctx.g3Trainer then startTrainer(ctx, ctx.g3Trainer) end
end

function Commands.g3_check_trainer_flag(ctx, trainerId)
  local name = trainerFlag(trainerId, ctx.game and ctx.game.data)
  if name then Commands.check_flag(ctx, name) else ctx.lastCheck = false end
  setResult(ctx, ctx.lastCheck and 1 or 0)
end

function Commands.g3_set_trainer_flag(ctx, trainerId)
  local name = trainerFlag(trainerId, ctx.game and ctx.game.data)
  if name then Commands.set_flag(ctx, name) end
end

-- THE FLAG THE CARTRIDGE SETS AND THE SCRIPT DOES NOT.
--
-- 566 scripts in Hoenn run `trainerbattle`; not one runs `settrainerflag`.
-- On the cartridge the battle setup sets it on a win, so nothing in this port
-- ever marked a trainer beaten and trainerDefeated -- the whole test for
-- whether they challenge you -- answered no forever.  Named rather than
-- inlined in start_battle so it can be exercised on its own.
function Gen3Commands.markTrainerBeaten(ctx, trainerId)
  if not (ctx and tonumber(trainerId)) then return false end
  local name = trainerFlag(trainerId, ctx.game and ctx.game.data)
  if not name then return false end
  Commands.set_flag(ctx, name)
  return true
end

function Commands.g3_clear_trainer_flag(ctx, trainerId)
  local name = trainerFlag(trainerId, ctx.game and ctx.game.data)
  if name then Commands.clear_flag(ctx, name) end
end

-- `setwildbattle SPECIES_KYOGRE, 45` -- the species is a NUMBER, and the
-- Pokemon module is keyed by name, so this needs the same bridge everything
-- else does.  Without it every scripted encounter in the game -- the
-- legendaries, the Wally tutorial's Ralts, the Sootopolis pair -- asked for a
-- species that is not there.
function Commands.g3_set_wild(ctx, species, level, item)
  local data = ctx.game and ctx.game.data
  ctx.g3Wild = { species = speciesId(data, species),
                 level = tonumber(level),
                 item = item and itemId(ctx, item) or nil }
end

function Commands.g3_wild_battle(ctx)
  local wild = ctx.g3Wild
  if not wild then return end
  if not wild.species then
    Logger.warn("gen3: dowildbattle with no species -- skipped")
    return
  end
  Commands.start_battle(ctx, "wild", wild.species, wild.level or 5,
                        wild.item and { heldItem = wild.item } or nil)
end

-- ---------------------------------------------------------------------------
-- warps
-- ---------------------------------------------------------------------------

-- WHERE A NAMED WARP LANDS.
--
-- `warp MAP, <id>, x, y` names a warp ON THE DESTINATION and the coordinates
-- beside it are ignored -- but Commands.warp takes CELLS, and hands back a
-- skipped warp for anything else ("the instruction did not decode").  So the
-- id has to be turned into the cell it stands on before the warp is asked
-- for; passing an options table it does not take is the same as passing
-- nothing, which is what this used to do.
--
-- The index is the port's, not the cartridge's: a map's warps are a Lua array
-- and the extractor already stores a map warp's destination +1 for exactly
-- this reason.
local function warpCell(ctx, mapId, index)
  local data = ctx.game and ctx.game.data
  local def = data and data.maps and data.maps[mapId]
  local list = def and def.warps
  local w = list and list[math.floor(tonumber(index) or 0)]
  if not w then return nil end
  return tonumber(w.x), tonumber(w.y)
end
Gen3Commands.warpCell = warpCell

function Commands.g3_warp(ctx, group, number, warpId, x, y)
  local id = mapKey(group, number)
  -- warp id $FF means "use the x/y given"; anything else names a warp on the
  -- destination map and the coordinates are ignored
  local named = tonumber(warpId) or 0xFF
  if named ~= 0xFF then
    local wx, wy = warpCell(ctx, id, named + 1)
    if wx and wy then
      Commands.warp(ctx, id, wx, wy)
      return
    end
    Logger.warn("gen3 warp: %s has no warp %d -- falling back to the "
                .. "coordinates beside it", tostring(id), named)
  end
  Commands.warp(ctx, id, tonumber(x), tonumber(y))
end

-- THE HOLE WARP, which is a slot of its own and not the respawn point.
--
-- A cave with a floor you can fall through records where the fall LANDS with
-- setholewarp, and the fall itself -- warphole -- reads it.  Emerald keeps
-- the player's own x and y across the fall, which is what makes the hole feel
-- like a hole rather than a staircase.
function Commands.g3_set_hole_warp(ctx, group, number, warpId, x, y)
  ctx.save = ctx.save or {}
  ctx.save.gen3HoleWarp = { map = mapKey(group, number), warp = tonumber(warpId),
                            x = tonumber(x), y = tonumber(y) }
end

function Commands.g3_warp_hole(ctx, group, number)
  local g, n = tonumber(group), tonumber(number)
  local player = ctx.overworld and ctx.overworld.player
  local px = player and player.cellX
  local py = player and player.cellY
  local id
  if g == 0xFF or n == 0xFF then
    -- MAP_UNDEFINED: the destination is whatever setholewarp last named
    local slot = ctx.save and ctx.save.gen3HoleWarp
    id = slot and slot.map
    if slot and slot.x and slot.y and slot.x ~= 0 then px, py = slot.x, slot.y end
    -- ...AND IF NOTHING NAMED ONE, THE MAP STILL KNOWS.
    --
    -- `setholewarp` runs in a map-script callback, so the slot is empty until
    -- that callback has fired -- and a save loaded standing on a Sky Pillar
    -- floor is exactly the case where it has not.  The import reads the same
    -- command out of every such map at build time (constants.gen3Ice.
    -- holeBelow), so the floor below is known without waiting for the
    -- callback, and the alternative is a hole that does nothing.
    if not id then
      local here = ctx.overworld and ctx.overworld.map
      local ice = ((ctx.game and ctx.game.data or {}).constants or {}).gen3Ice
      id = here and here.id and ice and ice.holeBelow
            and ice.holeBelow[here.id] or nil
      if id then
        Logger.debug("gen3 warphole: nothing had named a floor below, so %s "
                     .. "used the one its own map script names (%s)",
                     tostring(here.id), tostring(id))
      end
    end
  else
    id = mapKey(g, n)
  end
  if not (id and px and py) then
    Logger.warn("gen3: warphole with no destination (%s,%s) and no recorded "
                  .. "hole warp -- skipped", tostring(group), tostring(number))
    return
  end
  Commands.warp(ctx, id, px, py)
end

-- `setwarp` NAMES THE NEXT WARP; it does not take it.
--
-- The destination was being written into `gen3Respawn` and read by nobody --
-- a slot the script engine filled in and the world never looked at.  Its one
-- consumer is special 302, which is the door of every contest hall: the five
-- scripts that lead into one are `setwarp 25 <n> 255 7 5 / special 302 /
-- waitstate` and nothing else, so with the special unimplemented the
-- destination was recorded and then discarded and the doors did nothing at
-- all.  The name follows the job now, and the group and number travel with it
-- so the taker can resolve a named warp the same way `warp` does.
function Commands.g3_set_warp(ctx, group, number, warpId, x, y)
  ctx.save = ctx.save or {}
  ctx.save.gen3PendingWarp = {
    map = mapKey(group, number),
    group = tonumber(group), number = tonumber(number),
    warp = tonumber(warpId), x = tonumber(x), y = tonumber(y),
  }
end

-- THE DYNAMIC WARP, which is a different thing from the one above and was
-- being written into the same slot.
--
-- Emerald's map group 127, map 127 is not a map.  It is a placeholder that
-- means "wherever setdynamicwarp last pointed", and a warp event naming it
-- resolves through gSaveBlock1Ptr->dynamicWarp at the moment it is taken.
--
-- This is not an obscure corner.  The truck a new game starts inside has
-- three warps and ALL THREE name it: the coord event under the player sets
-- the destination -- Littleroot Town, and a different doorstep depending on
-- the boy-or-girl answer -- and the door then reads it.  Without this, the
-- first door in the game leads to a map id no dataset has.
function Commands.g3_set_dynamic_warp(ctx, group, number, warpId, x, y)
  ctx.save = ctx.save or {}
  ctx.save.gen3DynamicWarp = { map = mapKey(group, number),
                               warp = tonumber(warpId),
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

-- ---------------------------------------------------------------------------
-- THE ROTATING TILE PUZZLE -- the Trick House's seventh room and, more to the
-- point, the MOSSDEEP GYM.  Four opcodes, all four of them stubs until now,
-- and a badge on the other side of the second set.
--
-- The floor is painted with arrows and every arrow metatile says two things
-- at once: which BUTTON it answers to and which WAY it points, packed as
-- `base + puzzle * stride + direction`.  Press a button and everything
-- standing on one of that puzzle's arrows walks one tile the way its arrow
-- points; then each of them turns to face the way its NEW arrow points, and
-- that second half is what makes them read as being rotated by the floor
-- rather than walked across it.
--
-- Every number here -- the two bases, the stride, the direction order, the
-- eight movement scripts -- is derived in RomExtractorGen3:extractRotatingTiles
-- and arrives as data.constants.gen3RotatingTiles; nothing is written down
-- here.  The one thing this file knows on its own is what "right" means.
--
-- WHERE THE OBJECT IS, not where it looks like it is.  The cartridge moves
-- the object's TEMPLATE the moment the walk starts and reads the new arrow
-- back out of the template, so the turn is decided before the walk animation
-- has played a frame.  Reading the entity's live cell instead would make the
-- turn depend on whether `waitmovement 0` -- which waits on ONE of the walks
-- -- happened to be the last of them to land.  So the destination is recorded
-- here at the moment the walk is started, exactly as the cartridge does.
--
-- The walk scripts open and close with actions $94 and $95, which freeze and
-- release an object's idle animation while it slides.  This engine has no
-- idle-animation lock to freeze, so the movement reader passes them over --
-- which is the whole of the difference between the two.
local ROTATE_STEP = {
  right = { 1, 0 }, left = { -1, 0 }, down = { 0, 1 }, up = { 0, -1 },
}

local function rotatingTiles(ctx)
  local data = ctx.game and ctx.game.data
  local constants = data and data.constants
  local spec = constants and constants.gen3RotatingTiles
  if not (spec and spec.stride and spec.order and spec.walk and spec.face) then
    return nil
  end
  return spec
end

local function rotatingMovement(ctx, label)
  local data = ctx.game and ctx.game.data
  local pool = data and data.map_scripts
  return label and pool and pool.movements and pool.movements[label]
end

-- Which arrow, if any, is under a cell: the puzzle it belongs to and the way
-- it points, or nil for ordinary floor.
local function arrowAt(spec, map, base, x, y)
  if not (x and y and map.blockAt) then return nil end
  local ok, tile = pcall(map.blockAt, map, x, y)
  if not (ok and type(tile) == "number") then return nil end
  if tile < (spec.minTile or base) then return nil end
  local rel = tile - base
  if rel < 0 then return nil end
  local puzzle = math.floor(rel / spec.stride)
  local dir = rel - puzzle * spec.stride
  -- the arrow set is bounded at BOTH ends: the low end is the `metatile >
  -- base - 1` guard the cartridge opens with, and the high end is the two
  -- ceilings it checks before it will move anything.  Past either of them the
  -- id is some other tileset's floor and not an arrow at all.
  if puzzle >= (spec.puzzles or 0) then return nil end
  if dir >= (spec.directions or #spec.order) then return nil end
  return puzzle, dir
end

function Commands.g3_rotate_init(ctx, isTrickHouse)
  ctx.g3RotatingTiles = {
    trick = (valueOf(ctx, isTrickHouse) or 0) ~= 0,
    objects = {},
  }
end

-- FreeRotatingTilePuzzle also frees the movement queue, which here is the
-- engine's own and outlives no map; dropping the record is the whole of it.
function Commands.g3_rotate_free(ctx)
  ctx.g3RotatingTiles = nil
end

function Commands.g3_rotate_move(ctx, puzzle)
  local state = ctx.g3RotatingTiles
  local spec = rotatingTiles(ctx)
  local ow = ctx.overworld
  local map = ow and ow.map
  if not (state and spec and map) then return end
  local base = state.trick and spec.trickBase or spec.gymBase
  if not base then return end
  local want = valueOf(ctx, puzzle) or 0

  for _, npc in ipairs(ow.npcs or {}) do
    local at, dir = arrowAt(spec, map, base, npc.cellX, npc.cellY)
    if at == want and dir then
      local step = ROTATE_STEP[spec.order[dir + 1]]
      local rows = rotatingMovement(ctx, spec.walk[dir + 1])
      if step then
        state.objects[#state.objects + 1] = {
          entity = npc, index = npc.def and npc.def.index, from = dir,
          x = npc.cellX + step[1], y = npc.cellY + step[2],
        }
        if rows then
          startMovement(ctx, ow, npc, npc.def and npc.def.index,
                        spec.walk[dir + 1], rows)
        end
      end
    end
  end
end

-- HOW FAR IT TURNED, the cartridge's own arithmetic.  The arrow ids run in
-- clockwise order (the extractor checks that they do), so the difference
-- between the arrow it left and the arrow it landed on IS the number of
-- quarter turns -- and the cartridge resolves the two ways a half turn could
-- go by the sign it came out with, which is what these branches are.
local function rotationOf(delta, quarters)
  if delta < 0 or delta == quarters - 1 then
    if delta == -(quarters - 1) then return 1 end
    return -1
  end
  if delta > 0 then return 1 end
  return 0
end

function Commands.g3_rotate_turn(ctx)
  local state = ctx.g3RotatingTiles
  local spec = rotatingTiles(ctx)
  local ow = ctx.overworld
  local map = ow and ow.map
  if not (state and spec and map) then return end
  local base = state.trick and spec.trickBase or spec.gymBase
  if not base then return end
  local quarters = #spec.order

  for _, record in ipairs(state.objects) do
    local npc = record.entity
    local _, dir = arrowAt(spec, map, base, record.x, record.y)
    local facing = npc and npc.facing
    local at
    for k, name in ipairs(spec.order) do if name == facing then at = k end end
    if dir and at then
      local turn = rotationOf(dir - record.from, quarters)
      if turn ~= 0 then
        local to = (at - 1 + turn) % quarters + 1
        local rows = rotatingMovement(ctx, spec.face[to])
        if rows then
          startMovement(ctx, ow, npc, record.index, spec.face[to], rows)
        end
      end
    end
  end
end

-- setflashlevel: Overworld_SetFlashLevel, clamp and all (Gen3Flash.setLevel
-- refuses anything outside 0..gMaxFlashLevel by answering 0, which is the
-- cartridge's own out-of-range answer and means "no darkness").
function Commands.g3_set_flash_level(ctx, level)
  local game = ctx.game
  if not game then return end
  require("src.world.Gen3Flash").setLevel(game, valueOf(ctx, level))
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

-- setweather / resetweather.  SetSav1Weather: it sets what the region WILL
-- be and changes nothing on screen.  `doweather` below is what makes it so,
-- and every script in the game uses them in that order.
function Commands.g3_weather(ctx, weather)
  local save = ctx.save
  if save then save.gen3Weather = tonumber(weather) end
  local ow = ctx.overworld
  if ow then ow.gen3Weather = tonumber(weather) end
end

-- doweather -> DoCurrentWeather: the saved weather becomes the active one.
function Commands.g3_do_weather(ctx)
  local save = ctx.save
  if save then save.gen3WeatherActive = save.gen3Weather end
end

-- `dofieldeffect <id>` -- and the one of them this port can run.
--
-- Reported from play: "the pokemon center healing animation doesnt play and
-- the jingle doesnt play".  This stored the number on the context and nothing
-- read it, so all eight of Hoenn's scripted field effects were recorded and
-- none of them happened; `waitfieldeffect` beside it is a no-op, so the script
-- did not even pause where the cartridge pauses -- the nurse said "we need
-- your POKeMON" and "they're fighting fit" in consecutive frames.
--
-- The healing machine is the one this engine already has, because the Game
-- Boy centres have run it since Gen 1.  Which id it is comes from the import,
-- which finds it by the company it keeps: the one effect id whose script also
-- calls HealPlayerParty (RomExtractorGen3:fieldEffectRoles).
--
-- BLOCKING, because the row after it is `waitfieldeffect`: the animation
-- places one ball per party member, plays the jingle, and only then does the
-- script go on.
function Commands.g3_field_effect(ctx, id)
  id = tonumber(id)
  ctx.g3FieldEffect = id
  local data = ctx.game and ctx.game.data
  local roles = data and data.constants and data.constants.gen3FieldEffects
  local ow, runner = ctx.overworld, ctx.runner
  if not (roles and id and id == roles.pokecenterHeal) then return end
  if not (ow and ow.startHealAnim and runner) then return end
  local resumed = false
  ow:startHealAnim(function()
    if resumed then return end
    resumed = true
    runner:resume()
  end)
  runner:yield()
end
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

-- ---------------------------------------------------------------------------
-- THE 282 QUESTIONS NOBODY WAS ASKED.
--
-- `multichoice x, y, <list>, <ignoreB>` is how Hoenn asks you to pick from a
-- list -- which bike, which shard, which floor of the department store, which
-- of the Trick Master's answers, every YES / NO / INFO -- and there are two
-- hundred and eighty-two of them.  The lowering was here and the runtime had
-- nothing to show, so it wrote the default and let the script carry on: the
-- branch after it took an arm the player never chose, silently, every time.
--
-- The lists are in the cartridge (constants.gen3Multichoice, 114 of them off
-- sMultichoiceLists) and the answer the scripts read is the INDEX, zero
-- based.  Pressing B stores 127 -- MULTI_B_PRESSED -- which several of the
-- scripts compare against explicitly, and `ignoreB` is the flag that says
-- the question cannot be backed out of at all.
--
-- BLOCKING: the cartridge stops the script while the menu is up and resumes
-- it on the choice, and the row after a multichoice is almost always the
-- compare that reads the answer.
Gen3Commands.MULTI_B_PRESSED = 0x7F

-- ONE LIST, PUT UP AND WAITED ON.
--
-- `multichoice` and the menus a special builds for itself (the PC's own, for
-- one) differ only in where the rows come from: both write the chosen row's
-- INDEX into VAR_RESULT, both answer 127 when the player backs out, and both
-- park the script while the menu is up.  Sharing the half that does that is
-- what keeps a special's menu behaving like the cartridge's.
local function askChoices(ctx, options, opts)
  opts = opts or {}
  local game, runner = ctx.game, ctx.runner
  local fallback = tonumber(opts.default) or Gen3Commands.MULTI_B_PRESSED
  local function giveUp()
    setVar(ctx.save, VAR_RESULT, fallback)
    setResult(ctx, 1)
  end
  if not (type(options) == "table" and #options > 0
          and game and game.stack and runner) then
    giveUp()
    return
  end
  local okMenu, Menu = pcall(require, "src.ui.Menu")
  if not okMenu then
    giveUp()
    return
  end

  -- WHAT THE ROW IS WORTH is not always its index.  Most callers want the
  -- cartridge's plain "row 0, row 1, row 2"; the ones whose own row zero has
  -- to answer something else -- the STORYTELLER's list of tales, where a
  -- chosen row answers 1 and the EXIT row answers 0 -- pass `answer`, which
  -- is handed the 1-based row (or nil for B) and says what to store.
  local translate = type(opts.answer) == "function" and opts.answer or nil
  local answered = false
  local function answer(value)
    if answered then return end
    answered = true
    setVar(ctx.save, VAR_RESULT, value)
    setResult(ctx, 1)
    runner:resume()
  end
  local function pick(index)
    answer(translate and translate(index)
           or (index and index - 1) or fallback)
  end

  local items, widest = {}, 0
  for index, label in ipairs(options) do
    if #label > widest then widest = #label end
    items[index] = {
      label = label,
      onSelect = function() pick(index) end,
    }
  end
  -- the cartridge sizes the window to its widest option; two tiles of border
  -- and one of cursor
  local tw = math.max(6, math.floor(widest / 2) + 4)
  local cancel = nil
  if not (opts.ignoreB == true or tonumber(opts.ignoreB) == 1) then
    cancel = function()
      if translate then return pick(nil) end
      answer(Gen3Commands.MULTI_B_PRESSED)
    end
  end
  local pushed = pcall(game.stack.push, game.stack,
                       Menu.new(game, items,
                                { tx = 0, ty = 0, tw = tw,
                                  th = #items * 2 + 2, onCancel = cancel }))
  if not pushed then
    giveUp()
    return
  end
  runner:yield()
end


function Commands.g3_multichoice(ctx, listId, ignoreB, default)
  local id = tonumber(listId)
  local data = ctx.game and ctx.game.data
  local lists = data and data.constants and data.constants.gen3Multichoice
  local options = id and type(lists) == "table" and lists[id + 1] or nil
  local game, runner = ctx.game, ctx.runner
  if not (type(options) == "table" and #options > 0
          and game and game.stack and runner) then
    -- no list, or nowhere to show it: keep the old definite answer so the
    -- compare that follows still takes a real branch
    setVar(ctx.save, VAR_RESULT, tonumber(default) or Gen3Commands.MULTI_B_PRESSED)
    setResult(ctx, 1)
    Logger.debug("gen3: multichoice list %s not shown", tostring(listId))
    return
  end

  return askChoices(ctx, options, { ignoreB = ignoreB, default = default })
end

-- THE STRING BUFFERS, and the same number-for-a-name mistake three more times.
--
-- `bufferspeciesname 0, SPECIES_TREECKO` fills {STR_VAR_1} for the line that
-- follows.  The species, move and item tables are all keyed by NAME, and all
-- three lookups here were indexing them with the cartridge's NUMBER, so every
-- one of these came out empty -- a sentence with a hole where the Pokemon's
-- name should be.  The same fix each time: the extractor's own order map.
--
-- The operand may also name a var rather than be a literal; `bufferitemname
-- 0, VAR_0x8000` is how the std item scripts do it, which is to say it is the
-- common case rather than the exception.
local function moveIdFor(data, n)
  n = tonumber(n)
  if not n then return nil end
  local order = data and data.constants and data.constants.moveOrder
  local id = order and order[n]
  return type(id) == "string" and id or nil
end
Gen3Commands.moveIdFor = moveIdFor

function Commands.g3_buffer(ctx, slot, kind, value, quantity)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  local data = game.data
  local resolved = valueOf(ctx, value)
  local text
  if kind == "item" then
    local item = data and data.items and data.items[itemIdFor(data, resolved)]
    text = item and item.name
  elseif kind == "species" then
    local list = data and data.pokemon
    local def = list and list[speciesId(data, resolved)]
    text = def and def.name
  elseif kind == "move" then
    local moves = data and data.moves
    local def = moves and moves[moveIdFor(data, resolved)]
    text = def and def.name
  elseif kind == "party" then
    -- the party SLOT, zero based -- what checkpartymove answers
    local mon = ctx.save and ctx.save.party
                and ctx.save.party[(tonumber(resolved) or 0) + 1]
    local list = data and data.pokemon
    local def = mon and list and list[mon.species]
    text = mon and (mon.nickname or (def and def.name))
  elseif kind == "lead" then
    local mon = ctx.save and ctx.save.party and ctx.save.party[1]
    local list = data and data.pokemon
    local def = mon and list and list[mon.species]
    text = def and def.name
  elseif kind == "decoration" then
    text = require("src.world.Gen3Decorations").name(data, resolved)
  elseif kind == "number" then
    text = tostring(valueOf(ctx, value))
  elseif kind == "text" then
    text = data and data.text and data.text[value]
  end
  if text and quantity and (tonumber(valueOf(ctx, quantity)) or 1) > 1 then
    text = text .. "s"
  end
  game.stringBuffers[(tonumber(slot) or 0) + 1] = text or ""
end

-- ---------------------------------------------------------------------------
-- FADING THE SCREEN, AND FADING IT BACK.
--
-- `fadescreen <mode>` where mode is FROM_BLACK 0, TO_BLACK 1, FROM_WHITE 2,
-- TO_WHITE 3.  The odd ones darken; the even ones bring the picture back.
--
-- WHO FADES BACK IN is the part that is not in the script.  Route 101's
-- rescue is the clearest case:
--
--     fadescreen 1 / removeobject 4 / setobjectxy 255 / applymovement 255 /
--     waitmovement / special 159 / waitstate / applymovement 2 / ...
--
-- The screen goes black so the professor's bag and the player can be moved
-- without the player seeing it happen, the starter screen takes the whole
-- display, and then the scene carries on in daylight -- with no `fadescreen
-- 0` anywhere.  On the cartridge the fade back belongs to the RETURN TO THE
-- FIELD, which is what `waitstate` waits for, and the census says so: of the
-- 126 fades to black in Hoenn, 85 end at a waitstate and 17 at a fade of
-- their own.
--
-- The remaining 24 hand over to a full-screen scene and then end the script
-- outright.  Those are caught by restoreFade below, which the runner calls
-- when a script finishes -- a missing fade is a blemish, a screen that stays
-- black is indistinguishable from a crash, and this port has to be able to
-- carry on either way.
function Commands.g3_fade_screen(ctx, mode)
  local m = math.floor(tonumber(mode) or 0)
  local color = (m == 2 or m == 3) and "white" or "black"
  if m % 2 == 1 then
    ctx.g3FadedOut = true
    Commands.fade(ctx, "out", color)
  else
    ctx.g3FadedOut = nil
    Commands.fade(ctx, "in", color)
  end
end

function Commands.g3_wait_state(ctx)
  Gen3Commands.restoreFade(ctx)
end

-- ---------------------------------------------------------------------------
-- THE BRAILLE WALLS.
--
-- `braillemessage` used to lower to `message`, and the pointer it carries is
-- not in the text table -- the text scan skips it, a braille string being
-- six-dot cells rather than charmap bytes -- so twenty-two walls in Hoenn
-- opened an empty box.  Two of them gate legendaries: the Sealed Chamber's
-- back wall, which is the only place the cartridge says which two Pokemon
-- open the Regi chambers, and each chamber's own wall, which is the only
-- place it says what to DO once you are inside.
--
-- The cells, the sheet they are drawn from and the box they go in are read
-- off the cartridge by extractBraille; this parks the runner while the wall
-- is up.  The cartridge's own shape is
--
--     braillemessage <wall> / waitbuttonpress / closebraillemessage
--
-- and `waitbuttonpress` is a nop in this engine because every box here owns
-- its own lifecycle -- so the WAIT has to live here, or the script would run
-- straight past its own wall.  The overworld clears the box on A or B and
-- resumes; `closebraillemessage` clears it too, for the scripts that put one
-- up and take it down without waiting.
function Commands.g3_braille(ctx, at)
  local ow = ctx.overworld
  local record = Gen3Commands.brailleWall(ctx, at)
  if not (ow and record) then
    if not record then
      Logger.warn("gen3 braille: no wall was read for %s -- nothing shown",
                  tostring(at))
    end
    return
  end
  local runner = ctx.runner
  ow.brailleBox = {
    wall = record,
    onDone = function()
      if runner and runner.resume then runner:resume() end
    end,
  }
  if runner and runner.yield then runner:yield() end
end

function Commands.g3_braille_close(ctx)
  local ow = ctx.overworld
  if not (ow and ow.brailleBox) then return end
  ow.brailleBox = nil
end

-- The wall the address names.  The extractor keys them by the address the
-- script carries, which is a GBA pointer; a dataset that ever stores the flat
-- offset instead is accepted too, so the lookup cannot go quiet on a detail
-- of how the number was written down.
function Gen3Commands.brailleWall(ctx, at)
  local data = ctx and ctx.game and ctx.game.data
  local braille = data and data.constants and data.constants.gen3Braille
  local messages = braille and braille.messages
  if type(messages) ~= "table" then return nil end
  local key = tonumber(at)
  if not key then return messages[at] end
  return messages[key] or messages[key + 0x08000000]
         or messages[key - 0x08000000]
end

-- Bring the picture back if this script darkened it and nothing has brought
-- it back yet.
--
-- IT DOES NOT WAIT, and that is deliberate.  Commands.fade yields the runner
-- until the ramp lands, and the ramp only advances while the overlay is the
-- state on TOP -- so a fade-in started somewhere the overlay is NOT on top
-- (behind a text box, at the very end of a script, from the runner's own
-- completion block) would hold the runner "running" for ever, and a runner
-- that never finishes is a player who can never move again.  A wait that can
-- deadlock is worse than a scene that carries on while the screen brightens,
-- so the ramp is started and the script goes on.
function Gen3Commands.restoreFade(ctx)
  if not ctx.g3FadedOut then return end
  ctx.g3FadedOut = nil
  local ow = ctx.overworld
  local overlay = ow and ow.fadeOverlay
  if not overlay then return end
  overlay.ramp = { from = overlay.alpha or 1, to = 0, frames = 12, t = 0 }
end

-- ---------------------------------------------------------------------------
-- `showmonpic <species> <x> <y>` / `hidemonpic` -- THE FRAMED PICTURE.
--
-- The species number was being written into a field on the context and read
-- by nothing, so the three scripts that use this drew no picture at all.
-- What they are is Birch's SECOND gift: after the Hall of Fame he offers a
-- Johto starter, and each of the three branches is
--
--     showmonpic <species> 10 3
--     msgbox "PROF. BIRCH: The FIRE POKeMON CYNDAQUIL caught your eye!" YESNO
--     ... givemon ... hidemonpic
--
-- so the picture is the whole point of the scene -- it is what the player is
-- being asked about.  Without it the question names a Pokemon and shows
-- nothing.
--
-- NEITHER COMMAND BLOCKS, which is the same shape Gen 2's `pokepic` has: the
-- script keeps running under the open box (the yes/no arrives next), and the
-- wait belongs to the message rather than to the picture.  PicBox already
-- handles that by ticking the script runner from its own update, because the
-- state stack only updates the state on top.
--
-- The GEOMETRY is the script's own.  `10 3` is the window's tile position and
-- a Gen 3 front pic is 64x64 -- eight tiles, not the Game Boy's seven -- so
-- the frame is drawn one tile outside that and PicBox is told both rather
-- than keeping its Game Boy constants.
function Commands.g3_show_mon_pic(ctx, species, x, y)
  ctx.g3MonPic = tonumber(species)
  local ow, game = ctx.overworld, ctx.game
  if not (ow and game and game.stack) then return end
  local id = speciesId(game.data, species)
  if not (id and (game.data.pokemon or {})[id]) then return end
  local path, trueColor =
    require("src.pokemon.Sprites").path(game.data, id, "front",
                                        { kind = "pokepic" })
  if not path then return end
  if ow.pokepicBox then ow.pokepicBox:remove() end
  local tx = math.floor(tonumber(x) or 10)
  local ty = math.floor(tonumber(y) or 3)
  local PIC_TILES = 8
  local box = require("src.ui.PicBox").new(game, {
    path = path, trueColor = trueColor and true or false,
    passive = true, overworld = ow,
    -- the frame sits one tile outside the window the script names
    box = { x = tx - 1, y = ty - 1, w = PIC_TILES + 2, h = PIC_TILES + 2 },
    picTiles = PIC_TILES,
  })
  ow.pokepicBox = box
  game.stack:push(box)
end

function Commands.g3_hide_mon_pic(ctx)
  ctx.g3MonPic = nil
  local ow = ctx.overworld
  local box = ow and ow.pokepicBox
  if not box then return end
  ow.pokepicBox = nil
  -- no wait here: the cartridge's hidemonpic frees the window and carries on,
  -- and the button press the player makes belongs to the message above it
  box:remove()
end

-- `special` calls one of 530 native functions by index.  None are implemented
-- yet; the index is recorded so a missing one is diagnosable from a log rather
-- than showing up as a scene that quietly does nothing.  When a special is
-- given a destination var, VAR_RESULT is left alone rather than zeroed, so a
-- following compare reads the value the script last set rather than a fake 0.
-- ---------------------------------------------------------------------------
-- SPECIALS
--
-- A `special` is a call out of the script into the game's own C. Emerald's
-- scripts make 2452 of them across 421 distinct ids, and the table is a
-- function pointer array with no names anywhere on the cartridge -- so each
-- one has to be IDENTIFIED before it can be written, and the only honest way
-- to identify one is from what the scripts around it do.
--
-- An id with no entry here is a no-op that logs once. That is deliberate and
-- it is not free: the script carries on as if the call had happened, so
-- whatever the special was going to do simply does not. Better than guessing
-- -- a special that does the WRONG thing corrupts a save -- but the gap is
-- real and gen3_scriptvm_test records its size rather than letting it hide.
--
-- Each entry below says how it was identified.
Gen3Commands.SPECIALS = {}

-- 157: THE WALL CLOCK.
--
-- The bedroom clock is a BG event whose entire script is
--
--     fadescreen 1 / special 157 / waitstate
--
-- and on the far side of it the story var advances and the flags that bring
-- mum upstairs are set. A screen that fades out, hands over to one special
-- and waits for a state change, gated in front of the clock-setting step of
-- the new game, is the clock. Nothing else it could be.
--
-- BLOCKING, because the script's `waitstate` is what the cartridge uses to
-- wait for it and the row after this one must not run until the player has
-- answered.
-- 470 and 508: THE SOOTOPOLIS CUTSCENE.
--
-- Reported from play: "Make sure the cutscene for groudon, kyogre and
-- rayquaza appears after going to the tower and making rayquaza flee and
-- returning to sootopolis".
--
-- HOW IT WAS IDENTIFIED, and it did not need the name list.  Sootopolis
-- City's ON_FRAME_TABLE has exactly two rows -- one gated on the city's own
-- state var, one on the var the Sky Pillar sets when Rayquaza flies off --
-- and both of their scripts were decoded command by command.  Every opcode in
-- them is lowered by the VM and every special they call is implemented,
-- except this one.  The scene fades out, sets gSpecialVar_0x8004, calls it,
-- and waits: everything the player is supposed to SEE in that gap is inside
-- the special.  A script that removes Kyogre and Groudon, adds Rayquaza, and
-- hands over to one call before crying Rayquaza's cry is not ambiguous about
-- what that call is.
--
-- gSpecials[470] and gSpecials[508] share a pointer -- the importer finds
-- that pair on its own evidence, knowing no names -- so both indices land
-- here.
--
-- 0x8004 IS WHICH HALF.  The cartridge's own Script_DoRayquazaScene reads it
-- and passes it straight through as the index the scene's step table starts
-- at, with the other argument saying whether the advance stops after the
-- first screen.  Sootopolis sets it to 0 before the Groudon and Kyogre scene
-- and 1 before Rayquaza's, and that is the whole of the difference.
--
-- BLOCKING, because the script's next command is `waitstate` and the
-- cartridge uses it to wait for exactly this.
local function doRayquazaScene(ctx)
  local game, runner = ctx.game, ctx.runner
  if not (game and game.stack) then return end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return end
  local okScene, Gen3Cutscene = pcall(require, "src.ui.Gen3Cutscene")
  -- A DATASET WITHOUT THE ART MUST NOT PARK THE SCRIPT.  An older cache has
  -- no cutscene record, and a screen that draws nothing and waits for a key
  -- would strand the save at the one point in the story it cannot go round.
  if not (okScene and Gen3Cutscene.record(game)) then return end
  local part = tonumber(getVar(ctx.save, 0x8004)) or 0
  local pushed = pcall(Screens.push, game, "Gen3Cutscene", {
    part = part,
    onDone = function() if runner then runner:resume() end end,
  })
  if pushed and runner then runner:yield() end
end
Gen3Commands.SPECIALS[470] = doRayquazaScene
Gen3Commands.SPECIALS[508] = doRayquazaScene

-- ---------------------------------------------------------------------------
-- THE GAME CORNER
-- ---------------------------------------------------------------------------
--
-- Reported from play: "Also make sure the slots game art and code is properly
-- working in emerald."  The script command was `stubResult("playslotmachine",
-- 0)` -- it did nothing at all and told the script the machine had paid
-- nothing -- so Mauville's twelve seats were furniture and special 288, which
-- picks which seat you sat down at, was not implemented either.
--
-- Every Mauville slot script is the same three lines:
--
--     special GetSlotMachineId       @ 288, into VAR_RESULT
--     copyvar VAR_0x8004, VAR_RESULT
--     playslotmachine VAR_0x8004
--
-- so the pair has to arrive together or neither is any use.
--
-- 288: WHICH MACHINE.  On the cartridge this is not simply the seat: a table
-- is shuffled once a day so the machine that pays is a different one each
-- morning, and the id it answers decides how hard the reels are to stop on a
-- win.  THE PORT DOES NOT MODEL THAT BIAS AT ALL (see src/ui/Gen3Slots.lua),
-- so the id it answers is the seat itself -- the object's own local id, which
-- is what the cartridge starts from before it shuffles.  It is honest about
-- being cosmetic rather than pretending to a luck it does not have.
Gen3Commands.SPECIALS[288] = function(ctx)
  local seat = tonumber(getVar(ctx.save, VAR_LAST_TALKED)) or 0
  setVar(ctx.save, VAR_RESULT, math.max(0, seat))
end

-- ...AND SITTING DOWN AT IT.  Blocking, because the command's own next line
-- is what happens when you stand up.
function Commands.g3_play_slots(ctx, var)
  local game, runner = ctx.game, ctx.runner
  if not (game and game.stack) then return end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return end
  local okSlots, Gen3Slots = pcall(require, "src.ui.Gen3Slots")
  -- A DATASET WITHOUT THE MACHINE MUST NOT PARK THE SCRIPT.  A cache imported
  -- before the slot stage existed carries no reels, and a screen with nothing
  -- to spin that waits for a key would trap the player in the chair.
  if not (okSlots and Gen3Slots.record(game)) then
    Logger.debug("gen3: this dataset carries no slot machine -- the seat does "
                   .. "nothing rather than trapping the player")
    return
  end
  local machineId = var and tonumber(getVar(ctx.save, var)) or 0
  local pushed = pcall(Screens.push, game, "Gen3Slots", {
    machineId = machineId,
    onDone = function() if runner then runner:resume() end end,
  })
  if pushed and runner then runner:yield() end
end

-- ---------------------------------------------------------------------------
-- 165: THE ROULETTE, which is the other half of the same room.
--
-- Its two scripts (0x02A5AB1 and 0x02A5ADF) open with `checkitem COIN_CASE`
-- exactly as the slot seats do, put the table number in VAR_0x8004, add 128
-- when the Game Corner's service day is on, and then call this and wait --
-- so like `playslotmachine` it is blocking, and the line after it is what
-- happens when you stand up.
--
-- The selector is passed straight through: the screen reads its low bit for
-- which table and bit 7 for the service day, which is what sMinBets is
-- indexed by at 0x0142AA6.
-- ---------------------------------------------------------------------------
Gen3Commands.SPECIALS[165] = function(ctx)
  local game, runner = ctx.game, ctx.runner
  if not (game and game.stack) then return end
  local okScreens, Screens = pcall(require, "src.ui.Screens")
  if not okScreens then return end
  local okWheel, Gen3Roulette = pcall(require, "src.ui.Gen3Roulette")
  -- a cache from before the roulette stage existed carries no board, and a
  -- table with nothing on it that waits for a key would trap the player in
  -- the chair -- the same rule the slot seats follow
  if not (okWheel and Gen3Roulette.record(game)) then
    Logger.debug("gen3: this dataset carries no roulette board -- the table "
                   .. "does nothing rather than trapping the player")
    return
  end
  local pushed = pcall(Screens.push, game, "Gen3Roulette", {
    selector = tonumber(getVar(ctx.save, 0x8004)) or 0,
    onDone = function() if runner then runner:resume() end end,
  })
  if pushed and runner then runner:yield() end
end

Gen3Commands.SPECIALS[157] = function(ctx)
  local game = ctx.game
  local runner = ctx.runner
  if not (game and game.stack) then return end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return end
  local pushed = pcall(Screens.push, game, "Gen3WallClock", {
    onDone = function() if runner then runner:resume() end end,
  })
  if pushed and runner then runner:yield() end
end


-- 159: CHOOSE STARTER, and 0: HEAL PLAYER PARTY.
--
-- HOW THESE TWO WERE IDENTIFIED, because it is not the obvious way.  The
-- cartridge carries no names for its specials, and when this was written
-- pokeemerald's list looked as though it could not be indexed into safely --
-- its 527 names against this table's 530 entries, and a name transplanted by
-- an index that is off by one is a wrong answer wearing a right one's
-- clothes.
--
-- So the match is on SHAPE instead, which no renumbering can move.  (The
-- list CAN be indexed into: three pairs of entries in the cartridge's own
-- table share a function pointer, the importer finds those three pairs
-- knowing no names at all, and they fall on exactly the three repeated names
-- in pret's file.  src/script/Gen3Specials.lua carries the alignment and the
-- proof, and every derivation below turned out to agree with it -- which is
-- what makes it a proof rather than a hope.  The shape argument is left
-- standing because it is what established these two, and because it is the
-- check the alignment was tested against.)  Route
-- 101's rescue script decodes here as
--
--     fadescreen 1 / removeobject 4 / setobjectxy 255 / applymovement 255 /
--     waitmovement / special 159 / waitstate / applymovement 2 /
--     waitmovement / msgbox "PROF. BIRCH: Whew..." / special 0
--
-- and pokeemerald's Route101_EventScript_BirchsBag is that same sequence
-- command for command, with `special ChooseStarter` and `special
-- HealPlayerParty` in those two positions.  A sequence of ten commands
-- agreeing exactly, around a line of dialogue that only occurs once, is an
-- identification; the index it happens to sit at is not.
--
-- WHY IT MATTERS: there is no `givemon` anywhere in that script.  The whole
-- of choosing a starter lives inside the special, so without it the player
-- reaches Birch's lab having never been given a Pokemon and the game cannot
-- move.  It is the single most load-bearing call in Hoenn.
--
-- THE WHOLE SCENE IS INSIDE THE SPECIAL, and that is why three separate
-- things a player expects were missing at once.  Route 101's script is
--
--     special 159 / waitstate / applymovement 2 / msgbox "PROF. BIRCH:
--     Whew..." / special 0
--
-- so between the call and Birch thanking you there is not one script command.
-- Everything the cartridge does in that gap is C, and all of it belongs here:
--
--   THE CHOICE, with its confirm box -- the picture and "Do you choose this
--   POKeMON?" -- which Gen3StarterSelect draws.
--
--   THE FIRST BATTLE.  The Pokemon that jumped Birch is fought immediately,
--   before the screen ever returns to the route: pokeemerald hands the
--   starter over and then goes straight into a battle rather than back to
--   the overworld.  It is the only battle in the game the player cannot
--   lose to -- the script's very next commands after Birch's line are
--   `special 0`, HealPlayerParty -- which is why `canLose` is set from the
--   same record rather than guessed.
--
--   AND NOT THE NICKNAME.  Emerald never asks for one when a Pokemon is
--   handed over; naming is always a separate script step.  Birch asks in his
--   lab, several rooms and one warp later, and that script is the one that
--   calls the naming screen (special 161).  Asking here put the keyboard up
--   on Route 101 with a Poochyena still standing over the professor.
Gen3Commands.SPECIALS[159] = function(ctx)
  local game, runner = ctx.game, ctx.runner
  local record = game and (game.data.constants or {}).gen3Starters
  local list = record and record.species
  if not (game and game.stack and type(list) == "table" and list[1]) then
    return
  end
  local level = math.max(1, math.floor(tonumber(record.level) or 5))

  -- Handing the starter over is the same three steps whichever screen asked,
  -- so both paths land here.  skipNickname is TRUE and not an oversight: see
  -- the note above.
  -- WHICH ONE YOU PICKED HAS TO BE WRITTEN DOWN.
  --
  -- Reported from play: "it also seems like whoever i pick may still gets
  -- torchic instead of it changing based on my starter".  She did.  The
  -- SCRIPT does not record the choice -- it is `special ChooseStarter /
  -- waitstate` and nothing else -- because the cartridge writes it inside the
  -- special: CB2_GiveStarter opens with `*GetVarPointer(VAR_STARTER_MON) =
  -- gSpecialVar_Result` before it hands the Pokemon over.  Every script that
  -- later asks what you started with reads that var, and with nothing writing
  -- it they all read zero: the rival's party, her Route 103 battle, the
  -- Pokemon she carries in every scene after it.
  --
  -- The value is the POSITION in the cartridge's own three, counted from
  -- zero, and the var number is read off that instruction by the import.
  local function remember(species)
    local var = tonumber(record.var)
    if not var then return end
    for i, id in ipairs(list) do
      if id == species then
        Gen3Commands.setVar(ctx.save, var, i - 1)
        -- ...and gSpecialVar_Result holds it too on the way out, which is
        -- what the cartridge's own callback read it from
        Gen3Commands.setVar(ctx.save, Gen3Commands.VAR_RESULT, i - 1)
        return
      end
    end
  end

  local function accept(species)
    if not species then return end
    remember(species)
    Commands.give_pokemon(ctx, species, level, true)
    Gen3Commands.firstBattle(ctx)
  end

  local items = {}
  for _, species in ipairs(list) do
    local mon = game.data.pokemon and game.data.pokemon[species]
    items[#items + 1] = {
      label = (mon and mon.name) or tostring(species),
      onSelect = function()
        ctx.g3StarterChosen = species
        if runner then runner:resume() end
      end,
    }
  end
  -- THE CARTRIDGE'S OWN SCREEN, when the dataset carries it.
  --
  -- Emerald does not ask this with a list.  It draws three Poke Balls on a
  -- patch of grass with a hand you move between them and the Pokemon's
  -- picture above the one you are pointing at, and the extractor now finds
  -- that whole screen -- grass, balls, hand, positions -- from sStarterMon.
  -- The text menu below stays as the answer for a cache imported before that
  -- existed: an older import should still be able to hand over a starter.
  --
  -- THE CHOICE IS MADE OUTSIDE THE COROUTINE AND ACTED ON INSIDE IT.  The
  -- screen's callback runs from the UI, where `coroutine.yield` is an error
  -- and start_battle -- which yields -- cannot be called at all.  So the
  -- callback records the answer and resumes; everything that has to yield
  -- happens below, back on the script's own coroutine.
  local okScreen, StarterSelect = pcall(require, "src.ui.Gen3StarterSelect")
  local pushed = false
  if okScreen and StarterSelect and StarterSelect.available(game) then
    local screen = StarterSelect.new(game, list, function(chosen)
      ctx.g3StarterChosen = chosen
      if runner then runner:resume() end
    end)
    if screen then
      game.stack:push(screen)
      pushed = true
    end
  end

  if not pushed then
    local ok, Menu = pcall(require, "src.ui.Menu")
    if not ok then return end
    -- NOT cancelable: the cartridge does not let you leave this without one,
    -- and a script that carries on with an empty party is the bug this whole
    -- special exists to prevent
    local menu = Menu.new(game, items, { cancelable = false })
    game.stack:push(menu)
  end

  ctx.g3StarterChosen = nil
  if runner then runner:yield() end
  accept(ctx.g3StarterChosen)
  ctx.g3StarterChosen = nil
end

-- THE FIRST BATTLE, fought from inside the starter special.
--
-- Split out so the test can drive it without a UI, and so the one place that
-- decides whether it happens is the presence of the record the extractor
-- derived -- species, level, and the fact that a loss is survivable.  With no
-- record the scene keeps the shortened form it had: the choice happens, the
-- battle does not, and the script warps to the lab either way.
function Gen3Commands.firstBattle(ctx)
  local game = ctx.game
  local record = game and (game.data.constants or {}).gen3FirstBattle
  if type(record) ~= "table" then return false end
  local species = record.species
  if not (species and (game.data.pokemon or {})[species]) then
    Logger.warn("gen3: the first battle's %s is not in this dataset",
                tostring(species))
    return false
  end
  local level = math.max(1, math.floor(tonumber(record.level) or 2))
  Commands.start_battle(ctx, "wild", species, level, {
    -- BATTLE_TYPE_FIRST_BATTLE: there is nowhere to run to and nothing to
    -- black out to, and the script heals the party two commands later
    noRun = true,
    canLose = record.canLose and true or false,
  })
  return true
end

-- 161: NAME THE POKEMON IN SLOT VAR_0x8004.
--
-- IDENTIFIED FROM THE SHARED SCRIPT THAT WRAPS IT.  Nine map scripts across
-- Hoenn `call` the same four-command routine, and it is these four:
--
--     fadescreen 1 / special 161 / waitstate / return
--
-- Every one of the nine sits immediately after either a `givemon` or Birch's
-- "why not give a nickname to..." yes/no, and every one is preceded by
-- `setvar VAR_0x8004, <party slot>`.  A special that is only ever called
-- behind a fade, only ever after a Pokemon is handed over, and only ever with
-- a slot number in $8004, is the naming screen; nothing else on the cartridge
-- has that shape.
--
-- The fade and the `waitstate` are the script's, not this function's -- the
-- screen yields the runner and the fade is already down when it opens.
Gen3Commands.SPECIALS[161] = function(ctx)
  local game, runner = ctx.game, ctx.runner
  local save = ctx.save
  local slot = math.floor(getVar(save, 0x8004)) + 1
  local mon = save and save.party and save.party[slot]
  if not mon then
    -- $8004 out of range is a script the port has mis-set, not a cartridge
    -- fault; say so rather than opening a keyboard onto nothing
    Logger.warn("gen3: special 161 was asked to name party slot %d, and the "
                  .. "party has %d", slot,
                #((save and save.party) or {}))
    return
  end
  if not (game and game.stack) then return end
  local Screens = require("src.ui.Screens")
  Screens.push(game, "NamingScreen", {
    title = Strings("NICKNAME?"),
    maxLen = 10,
    default = mon.nickname,
    onDone = function(nick)
      if nick and #nick > 0 then mon.nickname = nick end
      if runner then runner:resume() end
    end,
  })
  if runner then runner:yield() end
end

-- Identified with 159 above, from the same shape match: the special
-- immediately after Birch's "Whew..." line.  The engine already knows how to
-- heal a party, so this is a name being attached to an existing verb.
Gen3Commands.SPECIALS[0] = function(ctx)
  Commands.heal_party(ctx)
end

-- 151: WHAT THE NEIGHBOURS CALL YOU.
--
-- Shape match again, and a short one this time because the shape is short:
-- May's house has an NPC whose whole script decodes as
--
--     lock / faceplayer / special 151 / msgbox "Hi, neighbor! Do you already
--     have your own POKeMON?" / release / end
--
-- and pokeemerald's RivalsHouse_1F_EventScript_RivalSibling is that script
-- exactly, with `special GetPlayerBigGuyGirlString` in the one slot.  The
-- line of dialogue occurs once on the cartridge, which is what makes a
-- six-command shape enough.
--
-- The two words are the CARTRIDGE'S, not pokeemerald's: they are stored one
-- after the other in the text region, and being adjacent is what identifies
-- them as a pair.  Worth saying because the obvious guess is wrong -- they
-- are capitalised, and searching for the lowercase form finds nothing.
Gen3Commands.SPECIALS[151] = function(ctx)
  local game = ctx.game
  local titles = game and (game.data.constants or {}).gen3PlayerTitles
  if type(titles) ~= "table" then return end
  local player = (ctx.save or {}).player or {}
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[1] = (player.gender == "girl" and titles.girl)
                          or titles.boy or ""
end

-- 152: WHAT THE RIVAL'S PARENT CALLS THEIR CHILD.
--
-- Shape match, and a long one.  The scene in the rival's house decodes as
-- lockall / playse / applymovement (an exclamation-mark emote) / waitmovement
-- / applymovement (a delay) / waitmovement / applymovement the player /
-- applymovement the NPC / waitmovement / special 152 / msgbox "Oh, hello. And
-- you are? ..." / setflag / setvar / releaseall / end, and pokeemerald's
-- LittlerootTown_BrendansHouse_1F_EventScript_YoureNewNeighbor is that same
-- fifteen-command sequence with `special GetRivalSonDaughterString` in the
-- one slot.
--
-- It corroborated something else on the way past: pokeemerald says that first
-- applymovement is an EXCLAMATION-MARK EMOTE, and the movement action in that
-- slot here is the one this port named `emote_exclamation` from the cartridge
-- alone.  Two independent readings agreeing on one frame of animation.
--
-- The word is the OPPOSITE gender to the player's: a boy's rival is May, and
-- May is somebody's daughter.
Gen3Commands.SPECIALS[152] = function(ctx)
  local game = ctx.game
  local titles = game and (game.data.constants or {}).gen3PlayerTitles
  if type(titles) ~= "table" or not titles.rivalBoy then return end
  local player = (ctx.save or {}).player or {}
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[1] = (player.gender == "girl" and titles.rivalBoy)
                          or titles.rivalGirl
end

-- ---------------------------------------------------------------------------
-- 40 AND 41: THE PARTY GOES AWAY AND COMES BACK.
--
-- These two were identified from the CARTRIDGE'S OWN CODE rather than from
-- the scripts around them, because getting them the wrong way round destroys
-- the player's team and the script evidence was only suggestive (58 scripts
-- call 40 and 95 call 41, which is not the tidy pairing a save/restore pair
-- ought to have).
--
-- gSpecials[40] and gSpecials[41] are mirror images.  Both walk six slots,
-- both call memcpy with r2 = 100 -- which is sizeof(struct Pokemon) -- and
-- both move a count byte alongside.  The literal pools are the same two
-- addresses in the opposite order:
--
--   40:  gPlayerParty      -> saveblock + 0x238,  count -> saveblock + 0x234
--   41:  saveblock + 0x238 -> gPlayerParty,       count <- saveblock + 0x234
--
-- So 40 is the SAVE and 41 is the RESTORE, and the script order agrees: 40
-- opens the Wally tutorial and every Frontier challenge, 41 closes them --
-- nine times immediately before special 0, which is HealPlayerParty.
--
-- The stash is on the SAVE, not in memory, exactly as the cartridge's is: a
-- Frontier challenge can be saved and resumed in the middle.
Gen3Commands.SPECIALS[40] = function(ctx)
  local save = ctx.save
  if not save then return end
  local stash = {}
  for i, mon in ipairs(save.party or {}) do stash[i] = mon end
  save.gen3PartyStash = stash
end

Gen3Commands.SPECIALS[41] = function(ctx)
  local save = ctx.save
  if not save then return end
  local stash = save.gen3PartyStash
  if not stash then return end
  local party = {}
  for i, mon in ipairs(stash) do party[i] = mon end
  save.party = party
  save.gen3PartyStash = nil
end

-- ---------------------------------------------------------------------------
-- 228..232: THE CYCLING ROAD
--
-- Route 110's downhill run is timed, and none of it worked: the five specials
-- behind it had no handlers, so the sign never had a record to read out, the
-- gate never started a run, and the finish never wrote one down.
--
-- ALL FIVE ARE SHORT ENOUGH TO READ WHOLE, and every number below is theirs:
--
-- The five are GetRecordedCyclingRoadResults, Special_BeginCyclingRoadChallenge,
-- GetPlayerAvatarBike, FinishCyclingRoadChallenge and UpdateCyclingRoadState,
-- in that order:
--
--   228 (0137EFC)  the record: VAR $4028 and $4029 are one 32-bit TIME in
--                  frames and VAR $4027 the collisions.  A zero time means
--                  there is no record yet, which is the 0 the sign tests.
--   229 (0137D0C)  the run starts: a flag, a zeroed collision count and the
--                  frame counter's current value, all in RAM rather than the
--                  save -- a run does not survive a reset on the cartridge
--                  either.
--   230 (0137D34)  WHICH BIKE: `& 4` first, so the ACRO answers 1 and the
--                  MACH 2, and being off a bike answers 0.  The order is not
--                  alphabetical and it is not the flag order; it is this.
--   231 (0137E6C)  the run ends: elapsed = now - start, and the pair is
--                  written down if it beats what is there.
--   232 (0137F44)  and leaving clears a run in progress -- states 2 and 3
--                  go back to 0, which is what stops a half-finished run
--                  counting when you come back.
--
-- THE TIME IS IN FRAMES, as the cartridge's is (it subtracts two reads of the
-- vblank counter), so the field ticks it; see tickCyclingChallenge.
Gen3Commands.CYCLING = {
  VAR_COLLISIONS = 0x4027,
  VAR_TIME_LO = 0x4028,
  VAR_TIME_HI = 0x4029,
  -- the state var the scripts themselves compare against
  VAR_STATE = 0x40A9,
  ACRO = 1, MACH = 2, ON_FOOT = 0,
  -- 60 frames a second, which is what turns the stored count into a time
  FRAMES_PER_SECOND = 60,
}

-- What the record says, or nil when there is not one.
function Gen3Commands.cyclingRecord(save)
  local C = Gen3Commands.CYCLING
  local lo = getVar(save, C.VAR_TIME_LO) or 0
  local hi = getVar(save, C.VAR_TIME_HI) or 0
  local frames = lo + hi * 65536
  if frames <= 0 then return nil end
  return frames, getVar(save, C.VAR_COLLISIONS) or 0
end

Gen3Commands.SPECIALS[228] = function(ctx)
  local frames, hits = Gen3Commands.cyclingRecord(ctx.save)
  if not frames then return 0 end
  -- the sign reads the record out of the string buffers the cartridge fills
  -- here, so they are filled here too
  local C = Gen3Commands.CYCLING
  local game = ctx.game
  if game then
    game.stringBuffers = game.stringBuffers or {}
    local total = math.floor(frames / C.FRAMES_PER_SECOND)
    game.stringBuffers[1] = ("%d:%02d.%d"):format(
      math.floor(total / 60), total % 60,
      math.floor((frames % C.FRAMES_PER_SECOND) * 10 / C.FRAMES_PER_SECOND))
    game.stringBuffers[2] = tostring(hits)
  end
  return 1
end

Gen3Commands.SPECIALS[229] = function(ctx)
  local save = ctx.save
  if not save then return end
  -- IN MEMORY, not in the save: the cartridge keeps the running total in
  -- three bytes of RAM and only the RECORD goes in the save block, so a run
  -- abandoned by a reset is a run that never happened.
  save.gen3Cycling = { active = true, frames = 0, collisions = 0 }
end

Gen3Commands.SPECIALS[230] = function(ctx)
  local C = Gen3Commands.CYCLING
  local save = ctx.save
  if not (save and save.onBike) then return C.ON_FOOT end
  if save.bikeKind == "acro" then return C.ACRO end
  if save.bikeKind == "mach" then return C.MACH end
  return C.ON_FOOT
end

Gen3Commands.SPECIALS[231] = function(ctx)
  local save = ctx.save
  local run = save and save.gen3Cycling
  if not (save and type(run) == "table") then return end
  local C = Gen3Commands.CYCLING
  local frames = math.max(1, math.floor(tonumber(run.frames) or 0))
  local hits = math.max(0, math.floor(tonumber(run.collisions) or 0))
  save.gen3Cycling = nil
  local best = Gen3Commands.cyclingRecord(save)
  if not best or frames < best then
    setVar(save, C.VAR_TIME_LO, frames % 65536)
    setVar(save, C.VAR_TIME_HI, math.floor(frames / 65536))
    setVar(save, C.VAR_COLLISIONS, math.min(0xFFFF, hits))
  end
  -- the finish text reads the run just made, not the record
  local game = ctx.game
  if game then
    game.stringBuffers = game.stringBuffers or {}
    local total = math.floor(frames / C.FRAMES_PER_SECOND)
    game.stringBuffers[1] = ("%d:%02d.%d"):format(
      math.floor(total / 60), total % 60,
      math.floor((frames % C.FRAMES_PER_SECOND) * 10 / C.FRAMES_PER_SECOND))
    game.stringBuffers[2] = tostring(hits)
  end
end

Gen3Commands.SPECIALS[232] = function(ctx)
  local save = ctx.save
  if not save then return end
  local C = Gen3Commands.CYCLING
  local state = getVar(save, C.VAR_STATE) or 0
  if state == 2 or state == 3 then setVar(save, C.VAR_STATE, 0) end
  save.gen3Cycling = nil
end

-- ---------------------------------------------------------------------------
-- 303 AND 160: THE CATCHING TUTORIAL, both read off the cartridge.
--
-- gSpecials[303] builds a Pokemon and then makes four SetMonData calls whose
-- field ids are 13, 14, 15 and 16 -- the four move slots.  Its arguments are
-- species 288 at level 7, move slot 1 is 33 and the other three are zero.
-- Through this cartridge's own species and move ordering that reads
-- ZIGZAGOON, level 7, knowing TACKLE and nothing else, which is exactly the
-- Pokemon Wally borrows.
--
-- gSpecials[160] then creates species 392 at level 5 into 0x02024744 and
-- starts a battle.  392 is RALTS, and 0x02024744 is 600 bytes -- one whole
-- party -- past the address special 41 writes to, so it is the ENEMY party.
-- A level 5 Ralts on the far side of a battle you are about to be shown how
-- to catch.
--
-- Between them they are Petalburg's catching tutorial, and the scene around
-- them says the same thing: "Please watch me and see if I can catch one
-- properly. ...Whoa!" on one side and "WALLY: I did it... It's my... My
-- POKeMON!" on the other.
--
-- 303 replaces the party, which is why 40 runs before it and 41 after.
Gen3Commands.SPECIALS[303] = function(ctx)
  local game, save = ctx.game, ctx.save
  if not (game and save) then return end
  local data = game.data
  local species = speciesId(data, 288)
  local move = (data.constants or {}).moveOrder
               and data.constants.moveOrder[33]
  -- speciesId falls back to the NUMBER when the order table cannot place it,
  -- so the real test is whether the dataset has that Pokemon
  if not (species and (data.pokemon or {})[species]) then
    Logger.warn("gen3: the catching tutorial's Pokemon is not in this "
                  .. "dataset -- the party is left alone")
    return
  end
  local mon = require("src.pokemon.Pokemon").new(data, species, 7)
  if not mon then return end
  -- the cartridge sets move slot 1 and blanks the other three, so this
  -- Zigzagoon knows TACKLE and nothing else however the level-up table
  -- would otherwise have filled it in
  if move then
    local def = (data.moves or {})[move]
    mon.moves = { { id = move, pp = (def and def.pp) or 35,
                    maxPp = (def and def.pp) or 35 } }
  end
  save.party = { mon }
end

-- The thrower's name.  BATTLE_TYPE_WALLY_TUTORIAL is the only battle type
-- Emerald builds around a trainer who is not the player, and every string
-- that would otherwise read the player's name reads WALLY's instead, so the
-- name has to come out of the dataset rather than a literal -- a translated
-- cartridge says whatever its own trainer table says.  Index 519 is the
-- tutorial Wally; the later WALLY_65x entries are the rematches.
function Gen3Commands.wallyName(data)
  local rec = (data and data.trainers or {}).WALLY
  return (rec and rec.name) or "WALLY"
end

Gen3Commands.SPECIALS[160] = function(ctx)
  local game = ctx.game
  local data = game and game.data
  local species = speciesId(data, 392)
  if not (species and (data.pokemon or {})[species]) then
    Logger.warn("gen3: the catching tutorial's target is not in this dataset")
    return
  end
  -- THE TUTORIAL IS A DEMO, NOT A BATTLE YOU FIGHT.
  --
  -- BATTLE_TYPE_WALLY_TUTORIAL (include/constants/battle.h) never reads the
  -- pad: HandleInputChooseAction's tutorial arm plays a recorded script
  -- instead (battle_controller_player.c), the bag opens itself, the ball is
  -- thrown for you and it cannot miss.  Nothing is kept either -- the Ralts
  -- Wally walks away with is given by the Petalburg script afterwards, not
  -- by this battle -- so the catch bookkeeping never runs.
  --
  -- Starting an ORDINARY wild battle here got all three of those wrong at
  -- once: the player drove Wally's turns, the capture went through the real
  -- catch path, and that path asked whether to nickname a Pokemon the player
  -- does not own.  The port already has this exact machinery for Gen1's old
  -- man and Gen2's DUDE -- a simulated cursor, a one-entry bag, a throw that
  -- always catches, nothing stored -- and makeDudeDemo is the arm of it that
  -- keeps the player's side of the screen occupied, which is what Emerald
  -- shows: Wally's borrowed ZIGZAGOON (special 303) is out on the field.
  local BattleState = require("src.battle.BattleState")
  local runner = ctx.runner
  local battle = BattleState.newWild(game, species, 5)
  battle:makeDudeDemo(Gen3Commands.wallyName(data))
  -- Like CatchTutorial's wPlayerName swap: anything that still reads the
  -- save mid-battle has to say WALLY too, and the real name goes back on
  -- the way out however the battle ends.
  local player = game.save and game.save.player
  local realName = player and player.name
  if player then player.name = battle.demoName end
  battle.onFinish = function(result)
    if player then player.name = realName end
    ctx.lastBattleResult = result
    if runner then runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then
    ctx.overworld:pushBattle(battle)
  else
    game.stack:push(battle)
  end
  -- `waitstate` follows on the cartridge; here the script is parked until
  -- onFinish resumes it, which is what stops the rest of the tutorial from
  -- running while the battle is still on screen.
  if runner then runner:yield() end
end

-- ---------------------------------------------------------------------------
-- 134: HOW MANY POKEMON ARE IN THE PARTY.
--
-- Read off gSpecials[134], which is short enough to be unambiguous:
--
--     count = 0
--     while count <= 5 and GetMonData(&gPlayerParty[count], 11) != 0:
--         count++
--     return count
--
-- Field 11 is the species, and 0x020244EC is the address special 41 restores
-- the party to.  So it walks the six slots from the front and stops at the
-- first empty one -- which is the party count, recomputed rather than read
-- off the stored byte.
--
-- IT MATTERS because the scripts compare its answer against 6: the Day Care
-- on Route 117 asks before it will take a Pokemon, and with the special
-- unimplemented it answered 0 -- an empty party -- to every one of them.
Gen3Commands.SPECIALS[134] = function(ctx)
  local party = (ctx.save or {}).party or {}
  local n = 0
  for _, mon in ipairs(party) do
    if not mon or not mon.species then break end
    n = n + 1
    if n >= 6 then break end
  end
  return n
end



-- ---------------------------------------------------------------------------
-- 326 AND 327: THE TWO ROUTES THAT RAIN.
--
-- Reported as a question rather than a bug: where does Route 119 and Route
-- 123's rain come from?  Not from the map header.  Every Hoenn map carries a
-- weather byte, this port reads it, and the byte on both of those routes --
-- and on Route 120, and on Route 113 under the volcano -- says SUNNY.  Six
-- distinct values appear in 519 headers and none of them is rain.
--
-- It comes from HERE.  Both routes call a special from their ON_TRANSITION,
-- and pret's checked list names them for what they do: SetRoute119Weather and
-- SetRoute123Weather.  Each sets a weather of its own -- not a fixed one, a
-- CYCLE, which is why the two sit at 20 and 21 with a gap under the sixteen
-- ordinary ones, and why the byte in the header could never have carried it.
--
-- The rest was already here and had nothing to feed it: the renderer has both
-- cycles, the map load applies whatever the setup leaves in the save (which
-- is how Route 113's ash arrives), and the number for each name is read off
-- the weather table rather than typed in.  This is the join.
-- ---------------------------------------------------------------------------

function Gen3Commands.weatherValue(ctx, name)
  local data = ctx and ctx.game and ctx.game.data
  local names = data and data.constants and data.constants.gen3WeatherNames
  if type(names) ~= "table" then return nil end
  for value, named in pairs(names) do
    if named == name then return tonumber(value) end
  end
  return nil
end

function Gen3Commands.setCycleWeather(ctx, name)
  local value = Gen3Commands.weatherValue(ctx, name)
  if not value then
    Logger.warn("gen3: this dataset has no number for %s, so the route keeps "
                  .. "the clear sky its header asks for", name)
    return false
  end
  -- SetSav1Weather, exactly as `setweather` does it: what the region WILL be.
  -- The map load is what makes it so, and these two are called from the load.
  if ctx.save then ctx.save.gen3Weather = value end
  if ctx.overworld then ctx.overworld.gen3Weather = value end
  return true
end

Gen3Commands.SPECIALS[326] = function(ctx)
  Gen3Commands.setCycleWeather(ctx, "ROUTE119_CYCLE")
end

Gen3Commands.SPECIALS[327] = function(ctx)
  Gen3Commands.setCycleWeather(ctx, "ROUTE123_CYCLE")
end

-- ---------------------------------------------------------------------------
-- 208 AND 209: THE SAFARI GAME.
--
-- Hoenn's Safari Zone was an ordinary patch of grass, and not for want of the
-- machinery: this port has the BALL / BAIT / ROCK / RUN menu, the bait and
-- rock factors, the ball and step counters and the PA announcement when
-- either runs out.  What it did not have was anything to turn them ON.
--
-- Every one of those gates asks the question the Game Boy games answer -- IS
-- THIS MAP IN THE SAFARI ZONE -- and answers it from the map's NAME.  A Hoenn
-- map is called MAP_G22_N04, so the answer was no everywhere in the region.
--
-- EMERALD DOES NOT ASK IT.  Safari mode is a mode: these two specials turn it
-- on and off, the battle type follows the flag, and the ground has nothing to
-- do with it.  So this is the whole switch, and what the game is worth --
-- thirty balls, off the gate's own line -- is read (constants.gen3Safari).
-- ---------------------------------------------------------------------------

function Gen3Commands.safariRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  local record = data and data.constants and data.constants.gen3Safari
  return type(record) == "table" and record or nil
end

Gen3Commands.SPECIALS[208] = function(ctx)
  local save = ctx.save
  if not save then return end
  local record = Gen3Commands.safariRecord(ctx)
  if not record then
    Logger.warn("gen3: the safari game's terms were not read, so the zone "
                  .. "stays ordinary ground")
    return
  end
  save.safari = { balls = tonumber(record.balls) or 0,
                  steps = tonumber(record.steps) or 0 }
end

Gen3Commands.SPECIALS[209] = function(ctx)
  if ctx.save then ctx.save.safari = nil end
end

-- ---------------------------------------------------------------------------
-- 499: THE NATIONAL DEX.
--
-- gSpecials[499] writes 0xDA into a byte of the save block and nothing else
-- of consequence -- and 218 is not a count of anything.  It is the magic
-- number the Pokedex's national flag is set to, and the script around it
-- agrees: it runs immediately after "{PLAYER}'s POKeDEX was upgraded to the
-- NATIONAL Mode!" and a fanfare.
Gen3Commands.SPECIALS[499] = function(ctx)
  local save = ctx.save
  if not save then return end
  save.nationalDex = true
end

-- ---------------------------------------------------------------------------
-- THE MAIN GAME'S OWN SPECIALS
--
-- Naming the specials by call count is misleading until they are named at
-- all: 54% of Hoenn's 2452 special calls are the Battle Frontier's six
-- dispatchers, which are one system and a post-game one.  Of what is left,
-- the main game's share is a long tail whose largest member is fifty-two
-- calls, and the ones below are that tail's head -- each cheap, each with a
-- visible cost while it is missing.
-- ---------------------------------------------------------------------------

-- 145: DRAW THE MAP AGAIN.
--
-- `setmetatile` writes a block and says nothing about the screen; the
-- cartridge's scripts change several and then call DrawWholeMapView once, and
-- THAT is the redraw.  Unimplemented, every scripted change to the world --
-- the Petalburg gym doors, the Mauville barriers, the Sootopolis ice, a
-- staircase appearing -- was written into the map and not drawn until
-- something else happened to rebuild it, usually leaving the room.
--
-- Fifty-two scripts call it, which is more than any other special the main
-- game uses.
-- ---------------------------------------------------------------------------
-- SLATEPORT'S TRAINER FAN CLUB: 166, 167, 168 and 173.
--
-- Sixty-four call sites in one building, and all four were unimplemented, so
-- the club said "I'm a big fan of ." to everyone and never had a fan to count.
-- The state and the rules are Gen3FanClub's; these are the four questions the
-- scripts ask of it.
--
-- A script names a BIT rather than a member -- the cartridge shifts its one
-- halfword by whatever is in $8004 -- so 8 to 15 is what arrives here.
-- ---------------------------------------------------------------------------

Gen3Commands.SPECIALS[166] = function(ctx)
  local FanClub = require("src.world.Gen3FanClub")
  local answer = FanClub.isFan(ctx.save, getVar(ctx.save, 0x8004)) and 1 or 0
  setVar(ctx.save, VAR_RESULT, answer)
  setResult(ctx, answer)
  return answer
end

Gen3Commands.SPECIALS[167] = function(ctx)
  local FanClub = require("src.world.Gen3FanClub")
  local n = FanClub.count(ctx.game)
  setVar(ctx.save, VAR_RESULT, n)
  setResult(ctx, n)
  return n
end

Gen3Commands.SPECIALS[168] = function(ctx)
  local FanClub = require("src.world.Gen3FanClub")
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[1] =
    FanClub.nameFor(game, getVar(ctx.save, 0x8004)) or ""
end

-- 173: something the club noticed.  $8004 says WHAT, and the four amounts it
-- can be worth are the cartridge's own.
Gen3Commands.SPECIALS[173] = function(ctx)
  local FanClub = require("src.world.Gen3FanClub")
  local gained = FanClub.gain(ctx.game, getVar(ctx.save, 0x8004)) and 1 or 0
  setVar(ctx.save, VAR_RESULT, gained)
  setResult(ctx, gained)
  return gained
end

-- 302: DoContestHallWarp -- the door of every contest hall.
--
-- The five scripts that lead into one are three rows long: `setwarp` names
-- the hall, this takes it, and `waitstate` waits for the screen.  Every one of
-- them recorded a destination and then stood still, because this was not
-- implemented -- so all five contest halls in Hoenn were behind doors that did
-- nothing when you walked into them.
--
-- The cartridge's own version fades the music out, fades the screen, plays
-- SE_EXIT and hands the warp to a task; here `warp` owns the transition, so
-- what is left is naming the destination the same way `warp` would.
Gen3Commands.SPECIALS[302] = function(ctx)
  local pending = ctx.save and ctx.save.gen3PendingWarp
  if not (pending and pending.group and pending.number) then
    Logger.warn("gen3: the contest hall warp was asked for with no setwarp "
                .. "before it -- the door is left where it is")
    return
  end
  Commands.g3_warp(ctx, pending.group, pending.number, pending.warp,
                   pending.x, pending.y)
end

-- ---------------------------------------------------------------------------
-- 154 AND 155: THE CABLE CAR, which is the one way up Mt. Chimney.
--
-- Both stations run the same three rows -- `setvar $8004, <which> / special
-- 154 / special 155 / waitstate` -- and neither special had a handler, so
-- walking into the car incremented a game statistic and left the player
-- standing on the platform.  Route 112's platform is where the story is
-- supposed to turn.
--
-- 154 is SetWarpDestination and nothing else: it branches on VAR_0x8004 and
-- names one of the two stations, both at the same cell.  155 is the ride --
-- the cartridge locks the field, runs the car across the mountain as its own
-- scene, and takes the warp at the end of it.
--
-- THE SCENE IS NOT HERE, and saying so is better than pretending: what this
-- does is the half that matters, which is arriving.  The ride's own art --
-- the car, the parallax mountain, the two-minute pan -- is a separate piece
-- of work, and a cable car that does not move is still a cable car you can
-- take, while one that does nothing is a wall.
Gen3Commands.SPECIALS[154] = function(ctx)
  local record = (ctx.game and ctx.game.data and ctx.game.data.constants
                  or {}).gen3CableCar
  if type(record) ~= "table" or type(record.ends) ~= "table" then
    Logger.warn("gen3 cable car: this dataset has no ride in it -- it was "
                .. "imported before the stations were read")
    return
  end
  local which = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  -- the cartridge's own branch: zero is the ride UP, and it is the arm that
  -- names the OTHER station
  local dest = record.ends[which] or record.ends[0]
  if not dest then return end
  ctx.save = ctx.save or {}
  ctx.save.gen3PendingWarp = {
    map = dest,
    group = tonumber(record.group),
    number = tonumber(dest:match("_N(%d+)$")),
    warp = tonumber(record.warp),
    x = tonumber(record.x), y = tonumber(record.y),
  }
end

Gen3Commands.SPECIALS[155] = function(ctx)
  local pending = ctx.save and ctx.save.gen3PendingWarp
  if not (pending and pending.group and pending.number) then
    Logger.warn("gen3 cable car: the ride was asked for with no destination "
                .. "set before it -- the car stays where it is")
    return
  end
  Commands.g3_warp(ctx, pending.group, pending.number, pending.warp,
                   pending.x, pending.y)
end

-- 127: BufferMonNickname -- the Pokemon in $8004, by the name its trainer
-- gave it.  The Name Rater asks for it before every line it says, so without
-- it the whole conversation had a hole where the nickname goes.
Gen3Commands.SPECIALS[127] = function(ctx)
  Commands.g3_buffer(ctx, 0, "party", 0x8004)
end

Gen3Commands.SPECIALS[145] = function(ctx)
  local ow = ctx.overworld
  local map = ow and ow.map
  local renderer = map and map.renderer
  if renderer and renderer.rebuild then renderer:rebuild() end
end

-- ---------------------------------------------------------------------------
-- MAUVILLE GYM: 142, 143 AND 147, AND THE THIRD BADGE.
--
-- Wattson's gym is a maze of electric beams with four floor switches, and
-- pressing one flips every beam in the room.  The whole puzzle is three
-- specials and, unimplemented, the gym was NOT MERELY DECORATIVE -- it was
-- shut.  The shipped layout has the beams across row 7 raised, which is the
-- full width of the corridor between the door and Wattson, so the third gym
-- could be entered and not crossed.
--
-- Everything below is the cartridge's, and two independent readings agree on
-- it.  pokeemerald's sMauvilleGymSwitchCoords is (0,15), (4,12), (3,9),
-- (8,9); the four coord events the ROM puts in this map sit on exactly those
-- cells, and the shipped layout has METATILE_MauvilleGym_RaisedSwitch at all
-- four.  That is the alignment proof, and it is worth having because the
-- rest is a table of 24 metatile ids.
--
-- 143 MauvilleGymPressSwitch presses the one in 0x8004 and raises the other
-- three.  142 MauvilleGymSetDefaultBarriers is misnamed on the cartridge
-- too: it TOGGLES every beam in the window -- green on becomes green off,
-- off becomes on, a vertical beam becomes its own pole and back -- which is
-- why pressing any switch changes the whole room.  147
-- MauvilleGymDeactivatePuzzle presses all four and turns everything off,
-- which is what a returning champion walks into.
--
-- WHY THE FLAG ON EACH ROW MATTERS.  MapGridSetMetatileIdAt writes the
-- metatile and the collision bits in one halfword, so every one of these
-- assignments states passability: the bare form is "you may walk here" and
-- the `| MAPGRID_IMPASSABLE` form is "you may not".  A beam's TOP half is
-- always passable and its BOTTOM half is the wall, which is why the H3/H4
-- rows carry the flag and H1/H2 never do.
--
-- The table is checkable rather than trusted.  The gym's own ON_LOAD can
-- reach a script of 26 `setmetatile` rows -- the cartridge's second beam
-- layout, written out by hand -- and running 142 over the shipped layout
-- reproduces it exactly, tile for tile and flag for flag.  The suite does
-- that against the ROM.
-- ---------------------------------------------------------------------------

Gen3Commands.MAUVILLE = {
  SWITCHES = { { 0, 15 }, { 4, 12 }, { 3, 9 }, { 8, 9 } },
  X0 = 0, X1 = 8, Y0 = 5, Y1 = 16,
  RAISED_SWITCH = 0x205,
  PRESSED_SWITCH = 0x206,
  FLOOR = 0x21A,
  GREEN_V1 = 0x240,
  GREEN_V2 = 0x248,
  RED_V2 = 0x249,
}

-- metatile -> { metatile it becomes, impassable }
local MAUVILLE_TOGGLE = {
  [0x220] = { 0x230, false }, [0x221] = { 0x231, false },   -- green H, on
  [0x228] = { 0x238, false }, [0x229] = { 0x239, false },
  [0x230] = { 0x220, false }, [0x231] = { 0x221, false },   -- green H, off
  [0x238] = { 0x228, true },  [0x239] = { 0x229, true },
  [0x222] = { 0x232, false }, [0x223] = { 0x233, false },   -- red H, on
  [0x22A] = { 0x23A, false }, [0x22B] = { 0x23B, false },
  [0x232] = { 0x222, false }, [0x233] = { 0x223, false },   -- red H, off
  [0x23A] = { 0x22A, true },  [0x23B] = { 0x22B, true },
  [0x240] = { 0x242, true },                                -- green V1 -> pole
  [0x248] = { 0x21A, false },                               -- green V2 -> floor
  [0x241] = { 0x243, true },                                -- red V1 -> pole
  [0x249] = { 0x21A, false },                               -- red V2 -> floor
  [0x242] = { 0x240, true },                                -- pole -> green V1
  [0x243] = { 0x241, true },                                -- pole -> red V1
  [0x251] = { 0x250, true },                                -- pole top, off->on
  [0x250] = { 0x251, false },
}

-- the same window with only the "turn it off" half, for 147
local MAUVILLE_OFF = {
  [0x220] = { 0x230, false }, [0x221] = { 0x231, false },
  [0x228] = { 0x238, false }, [0x229] = { 0x239, false },
  [0x222] = { 0x232, false }, [0x223] = { 0x233, false },
  [0x22A] = { 0x23A, false }, [0x22B] = { 0x23B, false },
  [0x240] = { 0x242, true },  [0x241] = { 0x243, true },
  [0x248] = { 0x21A, false }, [0x249] = { 0x21A, false },
  [0x250] = { 0x251, false },
}

local function mauvilleMap(ctx)
  local map = ctx.overworld and ctx.overworld.map
  if map and map.blockAt and map.setBlock then return map end
  return nil
end

-- The window every one of these walks, in the cartridge's own order: rows
-- outermost, so a tile that asks about the one ABOVE it is asking about a
-- row that has already been rewritten.  That is not incidental -- the floor
-- tile in a vertical beam decides which COLOUR of beam to become from what
-- the toggle just did to the pole above it.
local function mauvilleSweep(ctx, table_, floorCase)
  local map = mauvilleMap(ctx)
  if not map then return 0 end
  local M = Gen3Commands.MAUVILLE
  local changed = 0
  for y = M.Y0, M.Y1 do
    for x = M.X0, M.X1 do
      local id = map:blockAt(x, y)
      local to = id and table_[id]
      if to then
        map:setBlock(x, y, to[1], to[2])
        changed = changed + 1
      elseif floorCase and id == M.FLOOR then
        local above = map:blockAt(x, y - 1)
        map:setBlock(x, y,
                     (above == M.GREEN_V1) and M.GREEN_V2 or M.RED_V2, true)
        changed = changed + 1
      end
    end
  end
  return changed
end
Gen3Commands.mauvilleSweep = mauvilleSweep

-- 143: press the switch named by 0x8004 and raise the other three
Gen3Commands.SPECIALS[143] = function(ctx)
  local map = mauvilleMap(ctx)
  if not map then return end
  local M = Gen3Commands.MAUVILLE
  local pressed = tonumber(getVar(ctx.save, 0x8004))
  for i, at in ipairs(M.SWITCHES) do
    map:setBlock(at[1], at[2],
                 (i - 1 == pressed) and M.PRESSED_SWITCH or M.RAISED_SWITCH,
                 false)
  end
end

-- 142: flip every beam in the room
Gen3Commands.SPECIALS[142] = function(ctx)
  return mauvilleSweep(ctx, MAUVILLE_TOGGLE, true)
end

-- 147: the puzzle is over -- every switch down, every beam out
Gen3Commands.SPECIALS[147] = function(ctx)
  local map = mauvilleMap(ctx)
  if not map then return end
  local M = Gen3Commands.MAUVILLE
  for _, at in ipairs(M.SWITCHES) do
    map:setBlock(at[1], at[2], M.PRESSED_SWITCH, false)
  end
  return mauvilleSweep(ctx, MAUVILLE_OFF, false)
end

-- 183: DID YOU WIN?
--
-- gBattleOutcome, which the script then compares against B_OUTCOME_WON.  The
-- engine already records the answer -- ctx.lastBattleResult, set by
-- start_battle's onFinish -- so this is a name being attached to it and a
-- translation into the cartridge's own numbering.
--
-- It matters more than thirty-six calls sounds: an unimplemented special
-- answers zero, and zero is not any of the outcomes, so every one of those
-- thirty-six branches was taking the arm for "none of the above".
local GEN3_BATTLE_OUTCOME = {
  win = 1,          -- B_OUTCOME_WON
  lose = 2,         -- B_OUTCOME_LOST
  draw = 3,         -- B_OUTCOME_DREW
  run = 4,          -- B_OUTCOME_RAN
  flee = 6,         -- B_OUTCOME_MON_FLED
  caught = 7,       -- B_OUTCOME_CAUGHT
}
Gen3Commands.GEN3_BATTLE_OUTCOME = GEN3_BATTLE_OUTCOME

Gen3Commands.SPECIALS[183] = function(ctx)
  local outcome = GEN3_BATTLE_OUTCOME[ctx.lastBattleResult] or 0
  -- gSpecialVar_Result, whether or not the script named a destination: the
  -- cartridge's own writes it there and most of the callers use the bare
  -- `special` form and then `compare VAR_RESULT, B_OUTCOME_WON`.
  setVar(ctx.save, VAR_RESULT, outcome)
  return outcome
end

-- 312: SHAKE THE SCREEN.
--
-- The engine already has the jolt -- `earthquake` in Gen 2 feeds
-- overworld.quakeFrames, which draw() turns into a background offset while
-- the sprites stay put -- so this is the same effect under Hoenn's name.
-- Twenty-three scenes ask for it: the Weather Institute, Mt Chimney, the
-- Sealed Chamber, Groudon and Kyogre waking up.
--
-- The cartridge takes the shake's size and duration in vars 0x8004..0x8007;
-- what is honoured here is the DURATION, because that is the part the port's
-- jolt has a knob for and inventing an amplitude scale it does not have would
-- be a number this port chose.
local GEN3_SHAKE_DEFAULT = 32
Gen3Commands.SPECIALS[312] = function(ctx)
  local ow = ctx.overworld
  if not ow then return end
  local frames = getVar(ctx.save, 0x8006)
  if not frames or frames <= 0 or frames > 600 then
    frames = GEN3_SHAKE_DEFAULT
  end
  ow.quakeFrames = frames
end

-- 297 and 298: FACE ME, AND LET GO.
--
-- Script_FacePlayer is `faceplayer` as a special rather than as an opcode --
-- the scripts that use it are ones where the turn has to happen partway
-- through rather than at the top -- and Script_ClearHeldMovement drops a
-- held movement so the NPC stops repeating it.  Both already exist as verbs.
Gen3Commands.SPECIALS[297] = function(ctx)
  Commands.face_player(ctx)
end

Gen3Commands.SPECIALS[298] = function(ctx)
  local npc = ctx.npc
  if not npc then return end
  npc.heldMovement = nil
  npc.facingLocked = nil
end

-- 52: ANY BERRIES AT ALL?
--
-- Asked before the berry-blending and the Berry Master's scripts will go on.
-- The bag knows; nothing was asking it.
Gen3Commands.SPECIALS[52] = function(ctx)
  local data = ctx.game and ctx.game.data
  local items = data and data.items
  -- ...and the bag is save.inventory, not save.bag -- see bagCount above.
  local inv = (ctx.save or {}).inventory
  if type(inv) ~= "table" then return 0 end
  local function isBerry(id)
    local def = items and items[id]
    if type(def) ~= "table" then return false end
    if def.pocket == "BERRIES" or def.pocket == "BERRY" then return true end
    return type(id) == "string" and id:find("BERRY", 1, true) ~= nil
  end
  for id, count in pairs(inv) do
    if (tonumber(count) or 0) > 0 and isBerry(id) then return 1 end
  end
  return 0
end

-- 233: HOW MUCH THE LEAD MON LIKES YOU, in the cartridge's six bands.
--
-- GetLeadMonFriendshipScore returns 0..5 and the scripts compare against
-- those bands directly, so the bands are the answer rather than the raw
-- friendship byte.  The thresholds are pokeemerald's; what makes them
-- checkable here is the ORDER -- a higher friendship never returns a lower
-- score -- which the suite asserts across the whole 0..255 range.
local GEN3_FRIENDSHIP_BANDS = { 255, 200, 150, 100, 50, 1 }
Gen3Commands.SPECIALS[233] = function(ctx)
  local lead = ((ctx.save or {}).party or {})[1]
  local friendship = lead and tonumber(lead.friendship or lead.happiness) or 0
  for i, threshold in ipairs(GEN3_FRIENDSHIP_BANDS) do
    if friendship >= threshold then return #GEN3_FRIENDSHIP_BANDS + 1 - i end
  end
  return 0
end

-- 146 and 289: WHERE THE PLAYER IS AND WHICH WAY THEY ARE LOOKING.
--
-- StorePlayerCoordsInVars writes x and y into 0x8004 and 0x8005; the scenes
-- that use it put an NPC or an effect exactly where the player is standing.
Gen3Commands.SPECIALS[146] = function(ctx)
  local p = ctx.overworld and ctx.overworld.player
  if not p then return end
  setVar(ctx.save, 0x8004, p.cellX or p.x or 0)
  setVar(ctx.save, 0x8005, p.cellY or p.y or 0)
end

Gen3Commands.SPECIALS[289] = function(ctx)
  local p = ctx.overworld and ctx.overworld.player
  return FACING_VALUE[p and p.facing] or 1
end

-- 330: IS THE ONE THEY PICKED AN EGG?
--
-- Asked after ChoosePartyMon by the Day Care, the move relearner and the
-- Move Deleter, all of which refuse an egg.  The chosen slot is in 0x8004.
Gen3Commands.SPECIALS[330] = function(ctx)
  local slot = getVar(ctx.save, 0x8004)
  local mon = ((ctx.save or {}).party or {})[(slot or 0) + 1]
  local egg = mon and (mon.isEgg or mon.egg or mon.species == "EGG")
  return egg and 1 or 0
end

-- ---------------------------------------------------------------------------
-- 278 AND 279: THE CAMERA COMES OFF THE PLAYER.
--
-- Emerald pans a cutscene by SPAWNING AN OBJECT for the camera to follow and
-- then walking that object with applymovement, exactly as if it were a
-- person; RemoveCameraObject puts the camera back on the player.  Twenty-eight
-- scripts do it -- the Mt Chimney meteorite scene, Slateport's harbour, the
-- Weather Institute, Sootopolis -- and with the pair unimplemented the
-- applymovement that follows names an object that does not exist, so it was
-- silently dropped and the camera never moved.
--
-- The port already has the second half: cameraPan is a pixel offset laid on
-- top of the follow, with a frame ramp and a callback, and `pan_camera` uses
-- it.  So the camera object is not a new mechanism -- it is a virtual entity
-- whose walk steps are that offset, which is why it lives beside g3_move
-- rather than inside the overworld.
Gen3Commands.CAMERA_OBJECT = GEN3_CAMERA_OBJECT_ID

Gen3Commands.SPECIALS[278] = function(ctx)
  local ow = ctx.overworld
  if not ow then return end
  ow.cameraPan = ow.cameraPan or { ox = 0, oy = 0 }
  ctx.g3CameraObject = true
end

Gen3Commands.SPECIALS[279] = function(ctx)
  ctx.g3CameraObject = nil
  local ow = ctx.overworld
  if ow then ow.cameraPan = nil end
end

-- 254: THE MAP, FROM A SCRIPT.
--
-- FieldShowRegionMap is what the wall map's own script runs after its line,
-- and what the PokeNav's map option runs.  The screen is the overworld's, so
-- this is a name being attached to it.
Gen3Commands.SPECIALS[254] = function(ctx)
  local ow = ctx.overworld
  if ow and ow.openRegionMap then ow:openRegionMap() end
end

-- ---------------------------------------------------------------------------
-- THE QUESTIONS SCRIPTS ASK ABOUT THE PARTY, and the two screens they open.
--
-- Everything below is named rather than guessed at: src/script/Gen3Specials.lua
-- carries pret's list with the alignment PROVED against the cartridge's own
-- three duplicated function pointers, and every special this file had already
-- identified by the shape of its script agrees with it.  So these are not
-- "special 306 probably does X" -- they are ScriptCheckFreePokemonStorageSpace
-- and the rest, by name.
--
-- WHY THIS GROUP FIRST.  An unimplemented special answers ZERO, which is the
-- right kind of answer -- definite, repeatable -- but for these it is the
-- WRONG one, and wrong in the direction that stops a game:
--
--   * ScriptCheckFreePokemonStorageSpace answering 0 means "the boxes are
--     full", and the scripts that ask are the ones about to HAND YOU A
--     POKEMON.  Every gift and every in-game trade in Hoenn was refusing
--     itself on a box system with 420 free slots.
--   * IsStarterInParty answering 0 means "you left it behind".
--   * CountPartyAliveNonEggMons answering 0 means "you have nothing that can
--     fight", which is the arm that sends you home.
--
-- The counts are the cartridge's own definitions: an EGG is not a Pokemon for
-- any of them, and "alive" is a non-zero HP.
-- ---------------------------------------------------------------------------

-- how many storage slots the boxes have left; used by 306 below
local function partyList(ctx)
  return (ctx.save or {}).party or {}
end

local function isEggMon(mon)
  return mon ~= nil
         and (mon.isEgg or mon.egg or mon.species == "EGG") and true or false
end

-- 135: CountPartyNonEggMons, and 522: CountPartyAliveNonEggMons.
--
-- The pair the scripts use before anything that needs a Pokemon that can
-- actually do something -- the Battle Frontier's entry checks, the contest
-- halls, the tutorial battle.  136 is the same count with one slot skipped,
-- which is how the Day Care asks "how many will I have LEFT if I take this
-- one", and the slot it skips is in 0x8004.
Gen3Commands.SPECIALS[135] = function(ctx)
  local n = 0
  for _, mon in ipairs(partyList(ctx)) do
    if mon and mon.species and not isEggMon(mon) then n = n + 1 end
  end
  return n
end

Gen3Commands.SPECIALS[136] = function(ctx)
  local skip = (getVar(ctx.save, 0x8004) or 0) + 1
  local n = 0
  for i, mon in ipairs(partyList(ctx)) do
    if i ~= skip and mon and mon.species and not isEggMon(mon)
       and (mon.hp or 0) > 0 then
      n = n + 1
    end
  end
  return n
end

Gen3Commands.SPECIALS[522] = function(ctx)
  local n = 0
  for _, mon in ipairs(partyList(ctx)) do
    if mon and mon.species and not isEggMon(mon) and (mon.hp or 0) > 0 then
      n = n + 1
    end
  end
  return n
end

-- 64: HasEnoughMonsForDoubleBattle -- AND ZERO IS THE YES.
--
-- Two that can fight, and eggs do not count.  The trainers who ask are the
-- ones who would otherwise start a double battle you cannot field.
--
-- But the answer is not a boolean, and it is not the way round it reads.
-- GetMonsStateToDoubles (0806B5C4) counts the party's non-egg mons with HP
-- and returns a STATE:
--
--     0  two or more can fight        -- PLAYER_HAS_TWO_USABLE_MONS
--     1  the party holds exactly one  -- PLAYER_HAS_ONE_MON
--     2  fewer than two can fight     -- PLAYER_HAS_ONE_USABLE_MON
--
-- and 080F92F8 copies that straight into VAR_RESULT.  Both of its call sites
-- in the region -- 0827_13A1 and 0827_1408, the two double-battle
-- approaches -- read it as
--
--     special 64 / compare VAR_RESULT, 0 / goto_if NE -> "you need two"
--
-- so NON-ZERO refuses.  Answering 1 for "yes" turns both of those scripts
-- inside out: they would refuse the double battle exactly when you can field
-- one, and start it when you cannot.
Gen3Commands.SPECIALS[64] = function(ctx)
  local usable = Gen3Commands.SPECIALS[522](ctx)
  if usable >= 2 then return 0 end
  local party = ctx.save and ctx.save.party
  if type(party) == "table" and #party == 1 then return 1 end
  return 2
end

-- 304: IsStarterInParty.
--
-- Asked by the scenes that hand the story back to Birch.  The three species
-- are the cartridge's own (constants.gen3Starters, read from ChooseStarter's
-- table), so this does not name a Pokemon that Emerald does not.
Gen3Commands.SPECIALS[304] = function(ctx)
  local data = ctx.game and ctx.game.data
  local starters = data and data.constants and data.constants.gen3Starters
  if type(starters) ~= "table" then return 0 end
  local want = {}
  for _, species in ipairs(starters) do
    if type(species) == "string" then want[species] = true end
  end
  for _, mon in ipairs(partyList(ctx)) do
    if mon and want[mon.species] then return 1 end
  end
  return 0
end

-- 301: IsGrassTypeInParty, and 310: IsPokerusInParty.
--
-- The first gates Sootopolis' cave-of-origin errand; the second is the
-- Pokemon Centre nurse noticing the virus.  Both are a walk over the party.
Gen3Commands.SPECIALS[301] = function(ctx)
  local data = ctx.game and ctx.game.data
  local dex = data and data.pokemon or {}
  for _, mon in ipairs(partyList(ctx)) do
    local def = mon and mon.species and dex[mon.species]
    local types = def and (def.types or { def.type1, def.type2 }) or {}
    for _, t in ipairs(types) do
      if t == "GRASS" then return 1 end
    end
  end
  return 0
end

Gen3Commands.SPECIALS[310] = function(ctx)
  for _, mon in ipairs(partyList(ctx)) do
    if mon and (mon.pokerus or mon.pokerusDays) then return 1 end
  end
  return 0
end

-- 329: ScriptGetPartyMonSpecies.
--
-- Writes the species of the slot in 0x8004 where the scripts can compare it.
-- Emerald's species NUMBER is what the cartridge compares against, so that is
-- what goes in the var -- the port keeps the order in constants.speciesOrder.
Gen3Commands.SPECIALS[329] = function(ctx)
  local slot = (getVar(ctx.save, 0x8004) or 0) + 1
  local mon = partyList(ctx)[slot]
  local data = ctx.game and ctx.game.data
  local order = data and data.constants and data.constants.speciesOrder
  if not (mon and mon.species and type(order) == "table") then return 0 end
  for number, id in ipairs(order) do
    if id == mon.species then return number end
  end
  return 0
end

-- 306: ScriptCheckFreePokemonStorageSpace.
--
-- THE ONE THAT WAS STOPPING THINGS.  Every script that is about to give you a
-- Pokemon asks this first, and an unimplemented special answered 0 -- no room
-- -- so the gifts and the in-game trades all refused themselves.  TRUE is
-- "there is somewhere to put it", which means a free party slot or a free box
-- slot.
Gen3Commands.SPECIALS[306] = function(ctx)
  local party = partyList(ctx)
  local n = 0
  for _, mon in ipairs(party) do
    if mon and mon.species then n = n + 1 end
  end
  if n < 6 then return 1 end
  local boxes = (ctx.save or {}).boxes
  if type(boxes) ~= "table" then return 1 end
  for _, box in pairs(boxes) do
    if type(box) == "table" then
      for slot = 1, 30 do
        if not box[slot] then return 1 end
      end
    end
  end
  return 0
end

-- 425: IsBadEggInParty, and 426: ValidateSavedWonderCard.
--
-- Neither can be true of a save this port writes -- it makes no bad eggs and
-- has no Mystery Gift -- and answering "no" OUT LOUD is worth the two lines:
-- a special with a handler is a decision, and one without is a gap that
-- happens to read the same.
--
-- (This pair is also the one that caught the naming mistake it exists to
-- prevent.  It went in as a single handler on 426 labelled IsBadEggInParty,
-- which is 425; 426 is the wonder card.  The suite now checks the name of
-- EVERY implemented special against Gen3Specials, so an off-by-one cannot
-- sit there being plausible.)
Gen3Commands.SPECIALS[425] = function() return 0 end
Gen3Commands.SPECIALS[426] = function() return 0 end

-- ---------------------------------------------------------------------------
-- 144: ShowFieldMessageStringVar4.
--
-- The scripts that build a line out of pieces -- the Day Care's "{MON} grew
-- by {NUM} levels", the berry trees, the TV -- assemble it in gStringVar4 and
-- then call this to put it on screen.  Unimplemented, the assembling still
-- happened and the box never came up: the script fell silently through the
-- one row that was the whole point of the preceding five.
--
-- BLOCKING: the cartridge follows it with `waitmessage`, and show_text is
-- already the port's blocking box.
Gen3Commands.SPECIALS[144] = function(ctx)
  local buffers = ctx.game and ctx.game.stringBuffers
  local line = buffers and buffers[4]
  if type(line) ~= "string" or line == "" then return end
  Commands.show_text(ctx, line)
end

-- ---------------------------------------------------------------------------
-- 162: ChoosePartyMon.
--
-- The party menu, opened by a script so it can act on what you picked: the
-- Day Care takes one, the Move Deleter and the Move Relearner work on one,
-- the in-game trades want one.  The chosen SLOT goes in 0x8004, and backing
-- out writes PARTY_NOTHING_CHOSEN, which the cartridge spells 255 and every
-- one of those scripts compares against.
--
-- With it unimplemented, 0x8004 kept whatever was in it and the script went
-- on to act on slot zero -- your lead Pokemon -- or, more often, compared
-- against 255, matched nothing, and ran the "you picked one" arm having
-- shown no menu at all.
--
-- BLOCKING, because the row after it is `waitstate`.
Gen3Commands.PARTY_NOTHING_CHOSEN = 255

Gen3Commands.SPECIALS[162] = function(ctx)
  local game, runner = ctx.game, ctx.runner
  local party = (ctx.save or {}).party or {}
  if not (game and game.stack and runner) then
    setVar(ctx.save, 0x8004, Gen3Commands.PARTY_NOTHING_CHOSEN)
    return
  end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then
    setVar(ctx.save, 0x8004, Gen3Commands.PARTY_NOTHING_CHOSEN)
    return
  end
  local picked
  local pushed = pcall(Screens.push, game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon; runner:resume() end,
  })
  if not pushed then
    setVar(ctx.save, 0x8004, Gen3Commands.PARTY_NOTHING_CHOSEN)
    return
  end
  runner:yield()
  local slot = nil
  for i, mon in ipairs(party) do
    if mon == picked then slot = i - 1 break end
  end
  setVar(ctx.save, 0x8004,
         slot or Gen3Commands.PARTY_NOTHING_CHOSEN)
end

-- ---------------------------------------------------------------------------
-- 477: ChooseMonForMoveTutor -- NINE TUTORS, ALL OF THEM DEAD.
--
-- Hoenn has nine one-time move tutors -- Slateport, Mauville, Lavaridge,
-- Fallarbor, Verdanturf, Fortree, Lilycove, Mossdeep and Sootopolis -- and
-- every one of them ran its script to the end having taught nothing.
--
-- The var protocol is the scripts' own, not a guess.  Every tutor reads:
--
--     special 477
--     waitstate
--     compare VAR_RESULT, 0
--     goto_if 1 -> "come back if you change your mind"
--     ...
--     copyvar 0x8004, 0x8008
--     special 459
--
-- so 477 answers TWICE: VAR_RESULT is 0 when you back out and non-zero when
-- you pick, and the slot itself goes in 0x8008 -- which the script then
-- copies into 0x8004 for the teach.  Writing only one of the two leaves the
-- other holding whatever the last script put there.
--
-- 0x081B892C opens the party menu in mode 12 and hands it a callback; the
-- answer is written when the menu CLOSES, not when the special returns,
-- which is why the row after it is `waitstate`.  This is the same picker
-- 162 and 222 already use, yielded the same way.
--
-- BLOCKING, for the same reason as 162.
Gen3Commands.SPECIALS[477] = function(ctx)
  local game, runner = ctx.game, ctx.runner
  local party = (ctx.save or {}).party or {}
  local function refuse()
    setVar(ctx.save, VAR_RESULT, 0)
    setVar(ctx.save, 0x8008, Gen3Commands.PARTY_NOTHING_CHOSEN)
  end
  if not (game and game.stack and runner) then return refuse() end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return refuse() end
  local picked
  local pushed = pcall(Screens.push, game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon; runner:resume() end,
  })
  if not pushed then return refuse() end
  runner:yield()
  local slot = nil
  for i, mon in ipairs(party) do
    if mon == picked then slot = i - 1 break end
  end
  if not slot then return refuse() end
  setVar(ctx.save, VAR_RESULT, 1)
  setVar(ctx.save, 0x8008, slot)
end

-- ---------------------------------------------------------------------------
-- THE MOVE DELETER AND THE MOVE RELEARNER (222 to 227).
--
-- Two counters, six specials, and between them the only way in Emerald to
-- take an HM off a Pokemon or to put a level-up move back on one.  Both open
-- early -- Fallarbor and Lilycove -- and with the six unimplemented both ran
-- their scripts to the end having done nothing: the deleter's
-- MoveDeleterChooseMoveToForget left 0x8005 holding whatever the previous
-- script put there, and the very next row compares that against
-- MAX_MON_MOVES, so the house either looped back to the party menu forever
-- or deleted a move nobody had picked.
--
-- The var protocol is not guessed.  It is read off the cartridge's own
-- scripts.  Lilycove's deleter (S021EA3B, S021EAB0):
--
--     special 162 / waitstate           -- ChoosePartyMon -> 0x8004
--     compare 0x8004, 255               -- PARTY_NOTHING_CHOSEN: backed out
--     special 330 / compare RESULT, 1   -- IsSelectedMonEgg
--     special 226 / compare RESULT, 1   -- knows only one move
--     fadescreen 1 / special 223 / fadescreen 0
--     compare 0x8005, 4                 -- MAX_MON_MOVES: backed out
--     special 225                       -- nickname -> STR_VAR_1, move -> 2
--     ... YES/NO ...
--     special 521 / compare RESULT, 1   -- IsLastMonThatKnowsSurf
--     special 224 / playfanfare 378
--
-- and Fallarbor's relearner (S02013D6 and S020140C):
--
--     special 222 / waitstate           -- ChooseMonForMoveRelearner
--     compare 0x8004, 255               -- backed out
--     special 330                       -- an EGG remembers nothing
--     compare 0x8005, 0                 -- NOTHING TO REMEMBER
--     ...
--     special 227 / waitstate           -- TeachMoveRelearnerMove
--     compare 0x8004, 0                 -- 0 = they did not learn it
--     removeitem 111, 1                 -- the HEART SCALE, paid on success
--
-- Two of those would have been wrong as guesses.  222 is ChoosePartyMon and
-- then a COUNT into 0x8005 -- the script branches on it before it ever shows
-- a move list -- and 227 answers in 0x8004, not in VAR_RESULT, because the
-- relearner screen is the thing that overwrites the slot it was handed.
-- Which is also why 227 has to read the slot before it writes the answer.

-- the party slot 0x8004 names -- what all six of these act on
local function selectedMon(ctx)
  local slot = tonumber(getVar(ctx.save, 0x8004)) or 0
  return ((ctx.save or {}).party or {})[slot + 1]
end

Gen3Commands.MAX_MON_MOVES = 4

local function moveNameOf(data, entry)
  local id = (type(entry) == "table") and entry.id or entry
  if not id then return nil, nil end
  local def = data and data.moves and data.moves[id]
  return (def and def.name) or tostring(id), id
end

-- GetMoveRelearnerMoves (party_menu.c): the mon's OWN level-up list up to its
-- current level, minus what it already knows, deduplicated, in table order.
-- Not egg moves and not TMs -- the relearner gives back only what the
-- Pokemon could have learnt by growing up.
function Gen3Commands.relearnableMoves(ctx, mon)
  local out = {}
  local data = ctx.game and ctx.game.data
  local def = mon and data and data.pokemon and data.pokemon[mon.species]
  if not def then return out end
  local known, seen = {}, {}
  for _, m in ipairs(mon.moves or {}) do
    local id = (type(m) == "table") and m.id or m
    if id then known[id] = true end
  end
  local level = tonumber(mon.level) or 1
  for _, entry in ipairs(def.learnset or {}) do
    local id = entry.move or entry[2]
    local at = tonumber(entry.level or entry[1]) or 1
    if id and at <= level and not known[id] and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return out
end

-- A BLOCKING list of labels, answered with the 1-based row, or nil for B and
-- for the CANCEL row.  The same menu g3_multichoice puts up, which is this
-- port's stand-in for the cartridge's own list windows; the answer comes back
-- as a return value rather than a callback because everything that follows a
-- pick here -- the learn message, the make-room screen -- blocks in turn, and
-- a menu callback does not run inside the script coroutine.
-- `visible` is how many rows show at once, for a list longer than the box:
-- the scrolling multichoice carries the cartridge's own number for each of
-- its thirteen lists, and everything else keeps the six this always used.
function Gen3Commands.listPick(ctx, labels, cancelLabel, visible)
  local game, runner = ctx.game, ctx.runner
  if not (game and game.stack and runner and #labels > 0) then return nil end
  local okMenu, Menu = pcall(require, "src.ui.Menu")
  if not okMenu then return nil end
  local answered, picked = false, nil
  local function answer(row)
    if answered then return end
    answered = true
    picked = row
    runner:resume()
  end
  local items = {}
  for i, label in ipairs(labels) do
    items[i] = { label = label, onSelect = function() answer(i) end }
  end
  if cancelLabel then
    items[#items + 1] = { label = cancelLabel,
                          onSelect = function() answer(nil) end }
  end
  local pushed = pcall(game.stack.push, game.stack,
                       Menu.new(game, items,
                                { tx = 0, ty = 0,
                                  maxVisible = math.min(#items,
                                                        visible or 6),
                                  onCancel = function() answer(nil) end }))
  if not pushed then return nil end
  runner:yield()
  return picked
end

-- 226: GetNumMovesSelectedMonHas.  One is the refusal case: a Pokemon cannot
-- be left with no moves at all.
Gen3Commands.SPECIALS[226] = function(ctx)
  local mon = selectedMon(ctx)
  local n = 0
  for _, m in ipairs((mon and mon.moves) or {}) do
    if ((type(m) == "table") and m.id or m) then n = n + 1 end
  end
  return n
end

-- 223: MoveDeleterChooseMoveToForget.  The SLOT goes in 0x8005 and
-- MAX_MON_MOVES means they backed out -- which is why "no answer" cannot be
-- spelled zero here, zero is the first move.
Gen3Commands.SPECIALS[223] = function(ctx)
  local mon = selectedMon(ctx)
  local data = ctx.game and ctx.game.data
  setVar(ctx.save, 0x8005, Gen3Commands.MAX_MON_MOVES)
  if not mon then return end
  local labels = {}
  for _, m in ipairs(mon.moves or {}) do
    labels[#labels + 1] = moveNameOf(data, m) or ""
  end
  if #labels == 0 then return end
  local picked = Gen3Commands.listPick(ctx, labels, Strings("CANCEL"))
  if picked then setVar(ctx.save, 0x8005, picked - 1) end
end

-- 225: BufferMoveDeleterNicknameAndMove -- STR_VAR_1 the nickname, STR_VAR_2
-- the move in the slot 0x8005 names.  The "knows only one move" arm calls
-- this before 223 has ever run, exactly as the cartridge does, and that text
-- uses only STR_VAR_1; a slot with nothing in it leaves the second buffer
-- empty rather than inventing a move.
Gen3Commands.SPECIALS[225] = function(ctx)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  local data = game.data
  local mon = selectedMon(ctx)
  local def = mon and data and data.pokemon and data.pokemon[mon.species]
  game.stringBuffers[1] = (mon and (mon.nickname or (def and def.name)))
                          or (mon and mon.species) or ""
  local slot = (tonumber(getVar(ctx.save, 0x8005)) or 0) + 1
  local entry = mon and (mon.moves or {})[slot]
  game.stringBuffers[2] = (entry and moveNameOf(data, entry)) or ""
end

-- 224: MoveDeleterForgetMove.  SetMonMoveSlot(MOVE_NONE), RemoveMonPPBonus
-- for that slot, then ShiftMoveSlot for every slot above it: the cartridge
-- closes the gap so a forgotten move never leaves a hole.  This port's move
-- list is dense and each entry carries its own ppUps, so one table.remove is
-- all three of those.
Gen3Commands.SPECIALS[224] = function(ctx)
  local mon = selectedMon(ctx)
  local slot = (tonumber(getVar(ctx.save, 0x8005)) or 0) + 1
  if mon and mon.moves and mon.moves[slot] then
    table.remove(mon.moves, slot)
  end
end

-- 222: ChooseMonForMoveRelearner -- the party menu, and then the count the
-- script reads to decide whether this Pokemon has anything to remember.
Gen3Commands.SPECIALS[222] = function(ctx)
  Gen3Commands.SPECIALS[162](ctx)
  local mon = selectedMon(ctx)
  local n = 0
  if mon then n = #Gen3Commands.relearnableMoves(ctx, mon) end
  setVar(ctx.save, 0x8005, n)
end

-- 227: TeachMoveRelearnerMove.  0x8004 answers -- 1 if a move was actually
-- learnt, 0 otherwise -- and the script pays the HEART SCALE only on the 1.
-- A Pokemon that already knows four goes through the port's own make-room
-- screen, the one the TM counter and every level-up learn already use, and
-- abandoning there is a 0: no move, no scale.
Gen3Commands.SPECIALS[227] = function(ctx)
  local game, runner = ctx.game, ctx.runner
  local data = game and game.data
  local mon = selectedMon(ctx)        -- 0x8004 is still the SLOT here
  setVar(ctx.save, 0x8004, 0)         -- and from here it is the answer
  if not (mon and data and runner) then return end
  local moves = Gen3Commands.relearnableMoves(ctx, mon)
  if #moves == 0 then return end
  local labels = {}
  for i, id in ipairs(moves) do labels[i] = moveNameOf(data, id) end
  local picked = Gen3Commands.listPick(ctx, labels, Strings("CANCEL"))
  local id = picked and moves[picked]
  if not id then return end
  local mdef = (data.moves or {})[id]
  local pdef = (data.pokemon or {})[mon.species]
  local name = mon.nickname or (pdef and pdef.name) or tostring(mon.species)
  mon.moves = mon.moves or {}
  if #mon.moves < Gen3Commands.MAX_MON_MOVES then
    table.insert(mon.moves, { id = id, pp = (mdef and mdef.pp) or 5 })
    setVar(ctx.save, 0x8004, 1)
    Commands.show_text(ctx, Strings("%s learned\n%s!", name,
                                    (mdef and mdef.name) or tostring(id)))
    return
  end
  local okScreens, Screens = pcall(require, "src.ui.Screens")
  if not okScreens then return end
  local learned = false
  local pushed = pcall(Screens.push, game, "MoveLearnMenu", mon, id,
                       function(ok)
                         learned = ok and true or false
                         runner:resume()
                       end)
  if not pushed then return end
  runner:yield()
  setVar(ctx.save, 0x8004, learned and 1 or 0)
end

-- ---------------------------------------------------------------------------
-- 200 AND 201: CAN YOU AFFORD IT, AND TAKE IT.
--
-- The cost is in 0x8005 and the pair is how every SCRIPTED purchase in Hoenn
-- is done -- the ones that are not a mart counter: the Berry Blender's entry
-- fee, the Game Corner's coins, the Lilycove vendors, the Battle Frontier's
-- own tills.  IsEnoughForCostInVar0x8005 answering zero means "you cannot
-- afford this", which is the arm that refuses the sale, so with it
-- unimplemented every one of those was refused however much money you had.
--
-- Emerald reads the cost as a plain halfword out of the var, so a price over
-- 65535 is not something the mechanism can express and not something to
-- invent a wider one for.
local function costInVar(ctx)
  return getVar(ctx.save, 0x8005) or 0
end

Gen3Commands.SPECIALS[200] = function(ctx)
  local money = (ctx.save and ctx.save.money) or 0
  return money >= costInVar(ctx) and 1 or 0
end

Gen3Commands.SPECIALS[201] = function(ctx)
  local save = ctx.save
  if not save then return 0 end
  local cost = costInVar(ctx)
  local money = save.money or 0
  if money < cost then return 0 end
  save.money = money - cost
  return 1
end

-- ---------------------------------------------------------------------------
-- 252 AND 253: THE TWO PCs.
--
-- BedroomPC is the one in your own room -- item storage and nothing else --
-- and PlayerPC is the full menu in a Pokemon Centre.  Emerald reaches the
-- Centre's through a metatile behaviour, which this port already answers
-- (tryPcTile), but the bedroom's is a script: `special BedroomPC / waitstate`
-- on a BG event.  With the special unimplemented the PC in the room the game
-- starts you in did nothing at all.
--
-- BLOCKING, like the wall clock: the script's `waitstate` waits for the
-- screen to close.
-- BLOCKING, and it has to be blocking SAFELY.
--
-- `pcall(Screens.push, ...)` answers true when the push did not RAISE, which
-- is not the same as the screen having taken the callback.  A screen that
-- ignores `onDone` -- and every Game Boy screen does, because the ones
-- written for those generations close themselves -- left the runner parked
-- for ever: the player used the PC, closed it, and stood in a room they
-- could not walk out of, with the watchdog's "input has been gated for 10s
-- with nothing on screen" as the only sign.  Reported from play, from the
-- bedroom PC in the house the game starts in.
--
-- So the park is registered with the overworld as well.  If the screen ever
-- leaves the stack without calling back, OverworldState:update resumes the
-- runner itself (see gen3CheckBlockingScreen) -- a scripted screen can no
-- longer hang the game however it is written.
local function pushBlocking(ctx, screen, opts)
  local game, runner = ctx.game, ctx.runner
  if not (game and game.stack) then return end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return end
  local ow = ctx.overworld
  local done = false
  local function finish()
    if done then return end
    done = true
    if ow then ow.gen3Blocking = nil end
    if runner then runner:resume() end
  end
  opts = opts or {}
  opts.onDone = finish
  local depth = #(game.stack.states or {})
  local pushed = pcall(Screens.push, game, screen, opts)
  if not pushed then return end
  -- nothing actually went on the stack: there is no screen to wait for
  if #(game.stack.states or {}) <= depth then return end
  if ow then ow.gen3Blocking = { depth = depth, resume = finish } end
  if runner then runner:yield() end
end

-- The bedroom PC shows all four rows; the one in a Poke Centre shows three.
-- Which rows each lists is the cartridge's (see pcMenuOrders), and the same
-- screen serves both.
Gen3Commands.SPECIALS[252] = function(ctx)
  pushBlocking(ctx, "PlayerPC", { order = "bedroom" })
end

-- 253 IS THE ITEM PC, not the whole PC.  The Poke Centre's outer menu is a
-- script multichoice and the Pokemon storage is its own row (special 63), so
-- routing this one at the Game Boy's PC -- which put the boxes back in the
-- same menu -- was wrong twice over.
Gen3Commands.SPECIALS[253] = function(ctx)
  pushBlocking(ctx, "PlayerPC", { order = "player" })
end

-- 158: Special_ViewWallClock -- the same face as 157, with nothing to set.
-- The clock on the wall is read as often as it is set, and reading it used to
-- do nothing.
Gen3Commands.SPECIALS[158] = function(ctx)
  pushBlocking(ctx, "Gen3WallClock", { view = true })
end

-- ---------------------------------------------------------------------------
-- THE BERRY TREES: 44 TO 51, AND THE THREE THAT KEEP THEIR BOOKS.
--
-- Eighty-eight of them stand along Hoenn's routes, Route 102 and 104 are
-- lined with them, and every one was inert.  They are also all SOIL: the
-- cartridge's `ClearBerryTrees` blanks every slot at new game and no script
-- in the region plants one, so a tree in Hoenn is empty until the player
-- fills it.  That is the whole shape of the feature -- plant, water, wait,
-- pick -- and the numbers it runs on are gBerries, which the import now
-- reads (constants.gen3Berries).
--
-- WHICH TREE.  A berry tree's object event carries its id in the byte the
-- extractor calls `trainerRange` -- the cartridge's field is
-- `trainer_sight_or_berry_tree_id` and it is one or the other depending on
-- what the object is.  All 88 of Hoenn's trees run one script, and it is that
-- byte that tells them apart.
--
-- THE CLOCK.  Growth is minutes of real time, exactly as on the cartridge:
-- each stage lasts the berry's own stageDuration in hours, the fruiting stage
-- lasts four times that, and a tree left for more than seventy-one stage
-- durations is gone.  BerryTreeTimeUpdate below is that function line for
-- line.  It is ticked when the player looks at a tree rather than on a timer,
-- which is the same thing while the trees all wear one sprite; when the art
-- follows the stage it will have to move to map entry, and this is the note
-- saying so.
local GEN3_BERRY_STAGE = {
  NONE = 0, PLANTED = 1, SPROUTED = 2, TALLER = 3, FLOWERING = 4, BERRIES = 5,
}
local GEN3_WATER_STAGES = 4       -- NUM_WATER_STAGES
local GEN3_BERRY_GONE = 71        -- stage durations away before a tree dies
local GEN3_BERRY_REGROWTHS = 10   -- ...and how many times one comes back

Gen3Commands.BERRY_STAGE = GEN3_BERRY_STAGE

local function berryList(ctx)
  local data = ctx.game and ctx.game.data
  local list = data and data.constants and data.constants.gen3Berries
  return type(list) == "table" and list or nil
end

local function berryInfo(ctx, number)
  local list = berryList(ctx)
  local row = list and list[tonumber(number) or 0]
  return type(row) == "table" and row or nil
end

-- item -> berry number, the cartridge's ItemIdToBerryType
local function berryNumberOf(ctx, itemId)
  local list = berryList(ctx)
  if not list then return nil end
  for n, row in ipairs(list) do
    if row.item == itemId then return n end
  end
  return nil
end

local function stageMinutes(ctx, number)
  local info = berryInfo(ctx, number)
  return info and (info.hours or 0) * 60 or 0
end

local function berryTrees(save)
  if not save then return nil end
  save.gen3BerryTrees = save.gen3BerryTrees or {}
  return save.gen3BerryTrees
end

local function blankTree()
  return { berry = 0, stage = GEN3_BERRY_STAGE.NONE, minutes = 0,
           yield = 0, regrowth = 0, watered = {} }
end

local function treeAt(ctx, id)
  local trees = berryTrees(ctx.save)
  if not (trees and id) then return nil end
  trees[id] = trees[id] or blankTree()
  return trees[id]
end

-- the object the player is standing in front of; its berry-tree id
local function treeIdFor(ctx)
  local def = ctx.npc and ctx.npc.def
  local id = def and tonumber(def.trainerRange)
  if id and id > 0 then return id end
  return nil
end

-- ---------------------------------------------------------------------------
-- WHAT AN EMPTY PLOT LOOKS LIKE
-- ---------------------------------------------------------------------------
--
-- Reported from play: "berry planting spots are looking like they already
-- have berries planted when theres nothing there."  They were.  All 88 of
-- Hoenn's plots drew the same tree sprite whatever was -- or was not --
-- growing in them, because nothing told the overworld that a plot with
-- stage NONE has nothing to draw.
--
-- On the cartridge the object's own movement handler hides it while the
-- stage is zero, and that is the whole of why an empty plot looks like
-- empty soil rather than a tree.
--
-- WHICH OBJECTS ARE TREES is not guessed either.  The import finds the
-- graphics ids whose frame table has the berry tree's own shape -- nine
-- frames, the first three 16x16 and the last six 16x32 -- and there are
-- exactly THREE of them, which is how three trees can stand on one map.
function Gen3Commands.isBerryTree(data, obj)
  local trees = data and data.constants and data.constants.gen3Berries
                and data.constants.gen3Berries.trees
  local ids = trees and trees.graphicsIds
  local want = obj and tonumber(obj.graphicsId)
  if not (type(ids) == "table" and want) then return false end
  for _, id in ipairs(ids) do
    if id == want then return true end
  end
  return false
end

-- ...and what is growing in one, without planting anything by asking.
function Gen3Commands.berryTreeStage(save, id)
  id = tonumber(id)
  local trees = save and save.gen3BerryTrees
  local tree = (type(trees) == "table" and id) and trees[id] or nil
  return (type(tree) == "table" and tonumber(tree.stage)) or 0
end

local function stagesWatered(tree)
  local n = 0
  for i = 1, GEN3_WATER_STAGES do
    if tree.watered and tree.watered[i] then n = n + 1 end
  end
  return n
end

-- CalcBerryYieldInternal, to the line: with nothing watered you get the
-- minimum, and each watered stage widens the band the roll comes out of.
local function calcYield(ctx, tree)
  local info = berryInfo(ctx, tree.berry)
  if not info then return 1 end
  local min, max = info.minYield or 1, info.maxYield or 1
  local water = stagesWatered(tree)
  if water == 0 then return min end
  local randMin = (max - min) * (water - 1)
  local randMax = (max - min) * water
  local roll = (love and love.math and love.math.random)
               and love.math.random(0, randMax - randMin)
               or math.random(0, randMax - randMin)
  local rand = randMin + roll
  local extra
  if (rand % GEN3_WATER_STAGES) >= GEN3_WATER_STAGES / 2 then
    extra = math.floor(rand / GEN3_WATER_STAGES) + 1
  else
    extra = math.floor(rand / GEN3_WATER_STAGES)
  end
  return extra + min
end

-- PlantBerryTree(id, berry, stage, allowGrowth) -- 0x00E191C, to the line.
--
-- The struct is eight bytes and the disassembly names every field it touches:
--
--     +0  berry            strb of the berry number
--     +1  bits 0-6 stage, BIT 7 stopGrowth
--     +2  minutesUntilNextStage (halfword)
--     +4  berryYield
--
-- ...and the shape of the routine is: blank the record from the empty
-- template at 0x0858ABD0, write the berry, ask
-- GetStageDurationByBerryType for the countdown, merge the stage into the
-- low seven bits of byte 1, and then two conditionals --
--
--     if stage == BERRY_STAGE_BERRIES:  yield = CalcBerryYield();
--                                       minutes = minutes * 4
--     if not allowGrowth:               stopGrowth = TRUE
--
-- THE SECOND ONE IS WHY HOENN'S PRE-PLANTED TREES STAY FRUITING.  The
-- `setberrytree` command always passes allowGrowth = FALSE, so a tree the
-- new game plants is frozen where it was put until the player actually walks
-- past it -- see allowBerryTreeGrowth below.  Without that bit the eighty
-- seeded trees would tick down from the title screen and be back to sprouts
-- before Route 104 was ever reached.
local function plantTree(ctx, tree, number, stage, allowGrowth)
  for k, v in pairs(blankTree()) do tree[k] = v end
  tree.berry = number
  tree.minutes = stageMinutes(ctx, number)
  tree.stage = stage
  if stage == GEN3_BERRY_STAGE.BERRIES then
    tree.yield = calcYield(ctx, tree)
    tree.minutes = tree.minutes * 4
  end
  if not allowGrowth then tree.stopGrowth = true end
  return tree
end

-- AllowBerryTreeGrowth (0x00E1A78): clears bit 7 of byte 1, nothing else.
--
-- SetBerryTreesSeen (0x00E1D9x) calls it for every berry tree object whose
-- template coordinates fall inside the camera window, which is the cartridge
-- saying "the player can see this one now, let it grow."  The port's
-- overworld knows the same thing at spawn time -- an entity only gets a
-- berryTreeId when its object is actually placed on the loaded map -- so
-- that is where this is called from.
function Gen3Commands.allowBerryTreeGrowth(save, id)
  id = tonumber(id)
  local trees = save and save.gen3BerryTrees
  local tree = (type(trees) == "table" and id) and trees[id] or nil
  if type(tree) == "table" then tree.stopGrowth = nil end
end

-- ScrCmd_setberrytree: PlantBerryTree(tree, berry, stage, FALSE).
--
-- This was `nop` and that is the whole reason Hoenn opened with eighty empty
-- plots: the command that puts the region's berries in the ground was in the
-- bytecode table, was decoded correctly, and then did nothing.
--
-- A berry of 0 means "whatever this plot's default berry is" on the
-- cartridge; no script in Emerald passes 0, so a 0 here plants nothing
-- rather than inventing a default the ROM did not give us.
function Commands.g3_set_berry_tree(ctx, id, berry, stage)
  local tree = treeAt(ctx, tonumber(id))
  berry, stage = tonumber(berry), tonumber(stage)
  if not (tree and berry and berry > 0 and stage) then return end
  plantTree(ctx, tree, berry, stage, false)
end

-- BerryTreeGrow: the flowering stage is where the yield is decided, and the
-- fruiting stage falls back to SPROUTED rather than dying -- ten times, and
-- then the tree is gone.
local function berryTreeGrow(ctx, tree)
  if tree.stopGrowth then return false end
  local stage = tree.stage
  if stage == GEN3_BERRY_STAGE.NONE then return false end
  if stage == GEN3_BERRY_STAGE.BERRIES then
    tree.watered = {}
    tree.yield = 0
    tree.stage = GEN3_BERRY_STAGE.SPROUTED
    tree.regrowth = (tree.regrowth or 0) + 1
    if tree.regrowth >= GEN3_BERRY_REGROWTHS then
      for k, v in pairs(blankTree()) do tree[k] = v end
    end
    return true
  end
  if stage == GEN3_BERRY_STAGE.FLOWERING then
    tree.yield = calcYield(ctx, tree)
  end
  tree.stage = stage + 1
  return true
end

-- BerryTreeTimeUpdate(minutes), for every tree at once.
function Gen3Commands.berryTreeTimeUpdate(ctx, minutes)
  minutes = math.floor(tonumber(minutes) or 0)
  if minutes <= 0 then return end
  local trees = berryTrees(ctx.save)
  if not trees then return end
  for _, tree in pairs(trees) do
    if (tree.berry or 0) > 0 and (tree.stage or 0) > 0 and not tree.stopGrowth then
      local duration = stageMinutes(ctx, tree.berry)
      if duration <= 0 then
        -- a berry the dataset does not have: leave it alone rather than
        -- dividing by a number nobody read
      elseif minutes >= duration * GEN3_BERRY_GONE then
        for k, v in pairs(blankTree()) do tree[k] = v end
      else
        local time = minutes
        local guard = 0
        while time > 0 and guard < 64 do
          guard = guard + 1
          if (tree.minutes or 0) > time then
            tree.minutes = tree.minutes - time
            break
          end
          time = time - (tree.minutes or 0)
          tree.minutes = duration
          if not berryTreeGrow(ctx, tree) then break end
          if tree.stage == GEN3_BERRY_STAGE.BERRIES then
            tree.minutes = tree.minutes * 4
          end
        end
      end
    end
  end
end

-- how long since the last tick, in real minutes
local function berryTick(ctx)
  local save = ctx.save
  if not save then return end
  local now = (os and os.time and os.time()) or nil
  if not now then return end
  local last = save.gen3BerryClock
  save.gen3BerryClock = now
  if not last then return end
  Gen3Commands.berryTreeTimeUpdate(ctx, math.floor((now - last) / 60))
end
Gen3Commands.berryTick = berryTick

local function bufferBerryName(ctx, tree)
  local info = berryInfo(ctx, tree and tree.berry)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[1] = info and info.name or ""
end

-- GetBerryCountString: the berry's NAME and then one of two words, singular
-- or plural by how many are on the tree.  The NUMBER is not in this string --
-- the tree's own line is "You found {VAR2} {VAR1}!", and VAR2 comes out of
-- 0x8006 -- so putting one here would print it twice.
--
-- Both words are the cartridge's: the singular is the suffix all 43 berry
-- items share, the plural is the name of the pocket they go in
-- (RomExtractorGen3:extractBerries derives the pair).
local function bufferBerryCount(ctx, tree, count)
  local info = berryInfo(ctx, tree and tree.berry)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  if not info then game.stringBuffers[1] = "" return end
  local words = (berryList(ctx) or {}).word
  local word = words and ((count or 0) > 1 and words.many or words.one)
  game.stringBuffers[1] = word and (info.name .. " " .. word) or info.name
end

-- 44: ObjectEventInteractionGetBerryTreeData.
--
-- The tree's stage goes in 0x8004 and the script branches on it: 0 is bare
-- soil and asks to plant, 1 to 5 are the growth stages, and the name of what
-- is growing is in the first string buffer for the line that follows.
Gen3Commands.SPECIALS[44] = function(ctx)
  berryTick(ctx)
  local tree = treeAt(ctx, treeIdFor(ctx))
  if not tree then
    setVar(ctx.save, 0x8004, GEN3_BERRY_STAGE.NONE)
    setVar(ctx.save, 0x8005, 0)
    setVar(ctx.save, 0x8006, 0)
    return
  end
  -- THREE VARS, not one.  0x8004 is the stage the script branches on, 0x8005
  -- is how many stages the tree was watered at, and 0x8006 is how many
  -- berries are on it -- which the script buffers into VAR2 for "You found
  -- {VAR2} {VAR1}!".  Writing only the stage left the other two holding
  -- whatever the last unrelated script had put there.
  local count = tree.yield or 0
  setVar(ctx.save, 0x8004, tree.stage or GEN3_BERRY_STAGE.NONE)
  setVar(ctx.save, 0x8005, stagesWatered(tree))
  setVar(ctx.save, 0x8006, count)
  bufferBerryCount(ctx, tree, count)
end

-- 45: the berry's bare NAME, and 46: the name with BERRY or BERRIES after
-- it.  Two different strings into the same buffer, which is why the cartridge
-- has both: "Want to water the {VAR1} with the WAILMER PAIL?" reads the bare
-- name, "One {VAR1} was planted here." reads the other.
Gen3Commands.SPECIALS[45] = function(ctx)
  bufferBerryName(ctx, treeAt(ctx, treeIdFor(ctx)))
end

Gen3Commands.SPECIALS[46] = function(ctx)
  local tree = treeAt(ctx, treeIdFor(ctx))
  bufferBerryCount(ctx, tree, tree and tree.yield or 0)
end

-- 47: Bag_ChooseBerry -- the bag, opened at the BERRIES pocket, handing one
-- back.  The chosen item goes in 0x800E, which is what the script removes and
-- what special 48 plants; zero is "backed out", and the script checks for it.
--
-- BLOCKING: the row after it is `waitstate`.
Gen3Commands.SPECIALS[47] = function(ctx)
  local game, runner = ctx.game, ctx.runner
  setVar(ctx.save, 0x800E, 0)
  if not (game and game.stack and runner) then return end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return end
  local data = game.data
  local order = data and data.constants and data.constants.itemOrder
  local pushed = pcall(Screens.push, game, "Gen3BagMenu", {
    pick = true,
    pocket = "BERRY",
    onCancel = function() runner:resume() end,
    onPick = function(itemId)
      local number = 0
      for n, id in ipairs(order or {}) do
        if id == itemId then number = n break end
      end
      setVar(ctx.save, 0x800E, number)
      runner:resume()
    end,
  })
  if pushed then runner:yield() end
end

-- 48: ObjectEventInteractionPlantBerryTree -- PlantBerryTree(id, berry,
-- BERRY_STAGE_PLANTED, TRUE), then re-read the data the way the cartridge
-- does, so the line after it describes what was just put in the ground.
Gen3Commands.SPECIALS[48] = function(ctx)
  local tree = treeAt(ctx, treeIdFor(ctx))
  if not tree then return end
  local data = ctx.game and ctx.game.data
  local order = data and data.constants and data.constants.itemOrder
  local itemId = order and order[getVar(ctx.save, 0x800E) or 0]
  local number = itemId and berryNumberOf(ctx, itemId)
  if not number then return end
  -- the special's own call passes allowGrowth = TRUE: a tree the player
  -- planted with their own hands is not frozen waiting to be noticed
  plantTree(ctx, tree, number, GEN3_BERRY_STAGE.PLANTED, true)
  setVar(ctx.save, 0x8004, tree.stage)
  setVar(ctx.save, 0x8005, 0)
  setVar(ctx.save, 0x8006, 0)
  bufferBerryCount(ctx, tree, 0)
end

-- 49: ObjectEventInteractionPickBerryTree -- the berries go in the bag and
-- 0x8004 says whether they fitted, which is the arm the script branches on.
Gen3Commands.SPECIALS[49] = function(ctx)
  local tree = treeAt(ctx, treeIdFor(ctx))
  local info = tree and berryInfo(ctx, tree.berry)
  if not (tree and info and info.item) then
    setVar(ctx.save, 0x8004, 0)
    return
  end
  local count = math.max(1, tree.yield or 1)
  local ok = pcall(function()
    return require("src.inventory.Bag").add(ctx.save, info.item, count,
                                            ctx.game and ctx.game.data)
  end)
  setVar(ctx.save, 0x8004, ok and 1 or 0)
end

-- 50: ObjectEventInteractionRemoveBerryTree -- back to bare soil.
Gen3Commands.SPECIALS[50] = function(ctx)
  local tree = treeAt(ctx, treeIdFor(ctx))
  if not tree then return end
  for k, v in pairs(blankTree()) do tree[k] = v end
end

-- 51: ObjectEventInteractionWaterBerryTree -- the flag for the stage the tree
-- is IN, which is why watering a tree twice at the same stage is worth
-- nothing and watering it at every stage is worth the most.
Gen3Commands.SPECIALS[51] = function(ctx)
  local tree = treeAt(ctx, treeIdFor(ctx))
  if not tree then return 0 end
  local stage = tree.stage or 0
  if stage < GEN3_BERRY_STAGE.PLANTED or stage > GEN3_BERRY_STAGE.FLOWERING then
    return 0
  end
  tree.watered = tree.watered or {}
  tree.watered[stage] = true
  return 1
end

-- 97: DoWateringBerryTreeAnim -- the watering can's own animation, which is
-- drawn by a task and is not in the script.  Named so it is a decision.
Gen3Commands.SPECIALS[97] = function() end

-- 350 and 351: IncrementDailyPlantedBerries / IncrementDailyPickedBerries.
-- Counters the TV shows read; kept so the numbers exist when something asks.
Gen3Commands.SPECIALS[350] = function(ctx)
  local save = ctx.save
  if not save then return end
  save.gen3Daily = save.gen3Daily or {}
  save.gen3Daily.planted = (save.gen3Daily.planted or 0) + 1
end

Gen3Commands.SPECIALS[351] = function(ctx)
  local save = ctx.save
  if not save then return end
  save.gen3Daily = save.gen3Daily or {}
  save.gen3Daily.picked = (save.gen3Daily.picked or 0) + 1
end

-- 53: IsEnigmaBerryValid -- the e-Reader berry, which no save this port
-- writes can have.
Gen3Commands.SPECIALS[53] = function() return 0 end

-- ---------------------------------------------------------------------------
-- 255, 256, 257, 258: THE FOUR PEOPLE WHO WILL SWAP A POKEMON WITH YOU.
--
-- Their script is one shape, and reading it is what says what each special
-- has to do:
--
--     setvar 0x8008, <trade>          the trade's index
--     copyvar 0x8004, 0x8008
--     specialvar VAR_RESULT, GetInGameTradeSpeciesInfo
--     copyvar 0x8009, VAR_RESULT      <- what they want
--     msgbox "Would you like to trade me a {VAR1} for my {VAR2}?"
--     special ChoosePartyMon / waitstate
--     copyvar 0x8005, 0x800A          <- the slot you picked
--     specialvar VAR_RESULT, GetTradeSpecies
--     compare_var_to_var VAR_RESULT, 0x8009
--     goto_if NE <"I don't intend to trade for anything but a {VAR1}">
--     special CreateInGameTradePokemon
--     special DoInGameTradeScene / waitstate
--
-- So 255 answers with the species they WANT (and fills the two names for the
-- line), 258 answers with the species of the slot you chose, 256 builds what
-- you are being given, and 257 makes the swap.  The record for all four
-- trades is constants.gen3Trades, read out of the cartridge's own table.
--
-- The line is the reason the two names go where they do: "trade me a {VAR1}
-- for my {VAR2}" -- VAR1 is what they are asking you for, VAR2 is what is on
-- offer.  Putting them the other way round reads as a completely different
-- and much worse deal.
local function tradeList(ctx)
  local data = ctx.game and ctx.game.data
  local list = data and data.constants and data.constants.gen3Trades
  return type(list) == "table" and list or nil
end

local function tradeAt(ctx, index)
  local list = tradeList(ctx)
  local row = list and list[(tonumber(index) or -1) + 1]
  return type(row) == "table" and row or nil
end

-- the cartridge's own species NUMBER, which is what the scripts compare
local function speciesNumber(ctx, id)
  local data = ctx.game and ctx.game.data
  local order = data and data.constants and data.constants.speciesOrder
  if not (type(order) == "table" and type(id) == "string") then return 0 end
  for number, name in ipairs(order) do
    if name == id then return number end
  end
  return 0
end

local function speciesName(ctx, id)
  local data = ctx.game and ctx.game.data
  local def = data and data.pokemon and data.pokemon[id]
  return (def and def.name) or id or ""
end

Gen3Commands.SPECIALS[255] = function(ctx)
  local trade = tradeAt(ctx, getVar(ctx.save, 0x8004))
  if not trade then return 0 end
  local game = ctx.game
  if game then
    game.stringBuffers = game.stringBuffers or {}
    game.stringBuffers[1] = speciesName(ctx, trade.request)
    game.stringBuffers[2] = speciesName(ctx, trade.species)
  end
  return speciesNumber(ctx, trade.request)
end

Gen3Commands.SPECIALS[258] = function(ctx)
  local slot = (getVar(ctx.save, 0x8005) or 0) + 1
  local mon = ((ctx.save or {}).party or {})[slot]
  return mon and speciesNumber(ctx, mon.species) or 0
end

-- ---------------------------------------------------------------------------
-- THE DAY CARE (184 to 195), AND BREEDING.
--
-- Twelve specials, one building on Route 117, and with none of them
-- implemented every conversation there ran the same arm: GetDaycareState
-- answered zero, so both keepers said "we are not looking after any Pokemon"
-- forever and no Pokemon in Hoenn could be boarded, levelled or bred.
--
-- The protocol is the cartridge's own scripts.  The man outside (S0291C18)
-- and the lady inside (S0291D11) both open with `specialvar VAR_RESULT,
-- GetDaycareState` and branch on 1, 2 and 3, which fixes the answer: an egg
-- waiting outranks everything and is 1, and otherwise it is the NUMBER OF
-- BOARDED POKEMON PLUS ONE, so 2 and 3.  Zero is nobody, and it is the only
-- value that reaches the "shall we raise one for you?" offer.
--
-- The rest falls out of the same two scripts:
--
--   deposit  191 ChooseSendDaycareMon -> 0x8004, then 189 for the cry and the
--            nickname, then 190 to hand it over
--   report   184 buffers both nicknames, 193 the levels one of them gained,
--            188 the verdict on the pair (shown by 144, which is why it
--            writes STR_VAR_4 and not STR_VAR_1)
--   withdraw 192 picks which, 194 prices it, 200/201 take the money, and 195
--            hands it back and answers with its SPECIES so the script can
--            play its cry
--   the egg  185 = 1, then 187 to accept it or 186 to refuse
--
-- WHAT IS ALREADY HERE.  The breeding engine is not new -- src/pokemon/
-- DayCare.lua has run two pens, an egg roll, egg-group and gender checks,
-- inherited moves and banked step exp since Gen 2 -- so this is the Hoenn
-- wiring onto it, plus the two rules Hoenn does differently: gender comes off
-- the personality rather than a DV, and compatibility is a percentage rolled
-- against directly rather than a five-tier table.
-- ---------------------------------------------------------------------------

local function dayCare()
  return require("src.pokemon.DayCare")
end

-- the two pens, in the cartridge's order
local function dayCareSlot(index)
  local DC = dayCare()
  return (index == 0) and DC.MAN or DC.LADY
end

local function dayCareMon(ctx, index)
  return dayCare().mon(ctx.save, dayCareSlot(index))
end

local function dayCareCount(ctx)
  local n = 0
  for i = 0, 1 do if dayCareMon(ctx, i) then n = n + 1 end end
  return n
end

local function dayCareEgg(ctx)
  local breed = dayCare().store(ctx.save, false)
  return breed and breed.egg or nil
end

-- the name a keeper calls a boarded Pokemon by
local function dayCareName(ctx, mon)
  if not mon then return "" end
  return mon.nickname or speciesName(ctx, mon.species)
end

-- levels gained by the mon in the pen 0x8004 names, which is what both the
-- report line and the price are built from
local function dayCareLevelsGained(ctx, index)
  local DC = dayCare()
  local slot = DC.slot(ctx.save, dayCareSlot(index))
  if not (slot and slot.mon) then return 0 end
  local level = DC.pendingLevel(ctx.game and ctx.game.data, slot)
  return math.max(0, (level or slot.mon.level or 0)
                       - (slot.depositLevel or slot.mon.level or 0))
end
Gen3Commands.dayCareLevelsGained = dayCareLevelsGained

-- GetDaycareCost: a hundred, and another hundred for every level it grew
local function dayCareCost(ctx, index)
  return 100 + 100 * dayCareLevelsGained(ctx, index)
end
Gen3Commands.dayCareCost = dayCareCost

-- 184: GetDaycareMonNicknames -- both pens into STR_VAR_1 and STR_VAR_2
Gen3Commands.SPECIALS[184] = function(ctx)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  for i = 0, 1 do
    game.stringBuffers[i + 1] = dayCareName(ctx, dayCareMon(ctx, i))
  end
end

-- 185: GetDaycareState.  1 an egg is waiting, else the count plus one.
Gen3Commands.SPECIALS[185] = function(ctx)
  if dayCareEgg(ctx) then return 1 end
  local n = dayCareCount(ctx)
  return n > 0 and (n + 1) or 0
end

-- 186: RejectEggFromDayCare -- the egg is left behind and forgotten
Gen3Commands.SPECIALS[186] = function(ctx)
  local breed = dayCare().store(ctx.save, false)
  if breed then breed.egg = nil end
end

-- 187: GiveEggFromDaycare
Gen3Commands.SPECIALS[187] = function(ctx)
  local breed = dayCare().store(ctx.save, false)
  local egg = breed and breed.egg
  if not egg then return end
  local save = ctx.save
  save.party = save.party or {}
  if #save.party >= 6 then return end
  breed.egg = nil
  table.insert(save.party, egg)
end

-- 188: SetDaycareCompatibilityString -- STR_VAR_4, shown by 144.
--
-- The four lines are the cartridge's, found by the import: six strings in the
-- ROM open "The two " and exactly one window of four has its addresses laid
-- out together, which is sCompatibilityMessages.
Gen3Commands.SPECIALS[188] = function(ctx)
  local game = ctx.game
  if not game then return end
  local data = game.data
  local score = dayCare().gen3Score(data, ctx.save)
  local rows = data and data.constants and data.constants.gen3Daycare
               and data.constants.gen3Daycare.compatibility
  local line = rows and rows[score] and data.text and data.text[rows[score]]
  if not line then
    -- the dataset did not carry them; say the same four things
    if score >= 70 then line = Strings("The two seem to get along\nvery well.")
    elseif score >= 50 then line = Strings("The two seem to get along.")
    elseif score >= 20 then
      line = Strings("The two don't seem to like\neach other much.")
    else
      line = Strings("The two prefer to play with\nother POKEMON than each other.")
    end
  end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[4] = line
end

-- 189: GetSelectedMonNicknameAndSpecies -- the party slot in 0x8004
Gen3Commands.SPECIALS[189] = function(ctx)
  local mon = ((ctx.save or {}).party or {})[(getVar(ctx.save, 0x8004) or 0) + 1]
  local game = ctx.game
  if game then
    game.stringBuffers = game.stringBuffers or {}
    game.stringBuffers[1] = mon and dayCareName(ctx, mon) or ""
  end
  return mon and speciesNumber(ctx, mon.species) or 0
end

-- 190: StoreSelectedPokemonInDaycare -- the chosen party mon moves in
Gen3Commands.SPECIALS[190] = function(ctx)
  local save = ctx.save
  local party = (save or {}).party or {}
  local slot = (getVar(save, 0x8004) or 0) + 1
  local mon = party[slot]
  if not mon then return end
  local free = nil
  for i = 0, 1 do if not dayCareMon(ctx, i) then free = i break end end
  if free == nil then return end
  table.remove(party, slot)
  dayCare().deposit(save, dayCareSlot(free), mon)
end

-- 191: ChooseSendDaycareMon -- the party menu, answering in 0x8004
Gen3Commands.SPECIALS[191] = function(ctx)
  return Gen3Commands.SPECIALS[162](ctx)
end

-- 192: ShowDaycareLevelMenu -- which of the two, with what it would come back
-- as; VAR_RESULT takes the pen, or 2 for backing out, which is the value the
-- script compares against
Gen3Commands.MENU_DAYCARE_CANCEL = 2

Gen3Commands.SPECIALS[192] = function(ctx)
  local DC = dayCare()
  local data = ctx.game and ctx.game.data
  local labels, pens = {}, {}
  for i = 0, 1 do
    local slot = DC.slot(ctx.save, dayCareSlot(i))
    if slot and slot.mon then
      local level = DC.pendingLevel(data, slot) or slot.mon.level or 1
      labels[#labels + 1] = ("%s Lv. %d"):format(dayCareName(ctx, slot.mon),
                                                 level)
      pens[#pens + 1] = i
    end
  end
  if #labels == 0 then
    setVar(ctx.save, VAR_RESULT, Gen3Commands.MENU_DAYCARE_CANCEL)
    return
  end
  local picked = Gen3Commands.listPick(ctx, labels, Strings("CANCEL"))
  setVar(ctx.save, VAR_RESULT,
         (picked and pens[picked]) or Gen3Commands.MENU_DAYCARE_CANCEL)
end

-- 193: GetNumLevelsGainedFromDaycare, for the pen in 0x8004
Gen3Commands.SPECIALS[193] = function(ctx)
  local n = dayCareLevelsGained(ctx, getVar(ctx.save, 0x8004) or 0)
  local game = ctx.game
  if game then
    game.stringBuffers = game.stringBuffers or {}
    game.stringBuffers[2] = tostring(n)
  end
  return n
end

-- 194: GetDaycareCostAndPrepareString -- the price into 0x8005, where the
-- till pair (200 and 201) reads it, and into STR_VAR_1 for the line
Gen3Commands.SPECIALS[194] = function(ctx)
  local cost = dayCareCost(ctx, getVar(ctx.save, 0x8004) or 0)
  setVar(ctx.save, 0x8005, cost)
  local game = ctx.game
  if game then
    game.stringBuffers = game.stringBuffers or {}
    game.stringBuffers[1] = tostring(cost)
  end
  return cost
end

-- 195: TakePokemonFromDaycare -- it comes back grown, and the answer is its
-- SPECIES so the script can play its cry.
--
-- The exp banked while it walked is cashed in HERE and not before: that is
-- what makes the price quoted a moment ago the price of what you get, and it
-- is the same order the Gen 2 counter takes.
Gen3Commands.SPECIALS[195] = function(ctx)
  local DC = dayCare()
  local save, data = ctx.save, ctx.game and ctx.game.data
  local index = getVar(save, 0x8004) or 0
  local pen = dayCareSlot(index)
  local slot = DC.slot(save, pen)
  local mon = slot and slot.mon
  if not mon then return 0 end
  local startLevel = slot.depositLevel or mon.level or 1
  local newLevel, exp = DC.pendingLevel(data, slot)
  DC.withdraw(save, pen)
  local def = data and data.pokemon and data.pokemon[mon.species]
  if newLevel and def then
    mon.exp = exp
    mon.level = newLevel
    local okStats, Stats = pcall(require, "src.pokemon.Stats")
    if okStats and Stats.calc then
      mon.stats = Stats.calc(def, mon.level, mon.ivs or mon.dvs, mon.statExp,
                             mon.evs, mon.nature)
      if mon.stats and mon.stats.hp then
        mon.hp = math.min(mon.hp or mon.stats.hp, mon.stats.hp)
      end
    end
    local okP, Pokemon = pcall(require, "src.pokemon.Pokemon")
    if okP and Pokemon.learnMovesFromDayCare then
      Pokemon.learnMovesFromDayCare(data, mon, def, startLevel, newLevel)
    end
  end
  save.party = save.party or {}
  table.insert(save.party, mon)
  local game = ctx.game
  if game then
    game.stringBuffers = game.stringBuffers or {}
    game.stringBuffers[1] = dayCareName(ctx, mon)
  end
  return speciesNumber(ctx, mon.species)
end

-- 256: CreateInGameTradePokemon.
--
-- The mon you are given arrives at the LEVEL OF THE ONE YOU GAVE -- the
-- cartridge reads it off the party slot before the swap -- and wears the
-- trade's own nickname, trainer, ID and IVs.  It is built here and handed
-- over by 257, because the cartridge builds it into gEnemyParty first and
-- only swaps once the scene has run.
Gen3Commands.SPECIALS[256] = function(ctx)
  local trade = tradeAt(ctx, getVar(ctx.save, 0x8004))
  local slot = (getVar(ctx.save, 0x8005) or 0) + 1
  local party = (ctx.save or {}).party or {}
  local given = party[slot]
  local data = ctx.game and ctx.game.data
  ctx.g3TradeMon, ctx.g3TradeSlot = nil, nil
  if not (trade and given and trade.species and data) then return end
  local ok, mon = pcall(function()
    return require("src.pokemon.Pokemon").new(data, trade.species,
                                              given.level or 5)
  end)
  if not (ok and type(mon) == "table") then return end
  mon.nickname = trade.nickname
  mon.ot = trade.otName
  mon.otId = trade.otId
  mon.otGender = trade.otGender
  mon.traded = true            -- boosted exp, and the Name Rater refuses it
  if trade.item then mon.item = trade.item end
  if type(trade.ivs) == "table" and type(mon.ivs) == "table" then
    local Stats = require("src.pokemon.Stats")
    for i, key in ipairs(Stats.ORDER_GEN3) do
      if trade.ivs[i] then mon.ivs[key] = trade.ivs[i] end
    end
    local def = data.pokemon[trade.species]
    local okStats, stats = pcall(Stats.calc, def, mon.level, mon.ivs,
                                 mon.evs, mon.nature)
    if okStats and type(stats) == "table" then
      mon.stats, mon.hp = stats, stats.hp
    end
  end
  ctx.g3TradeMon, ctx.g3TradeSlot = mon, slot
end

-- 257: DoInGameTradeScene -- the swap itself.  The mon you gave leaves the
-- party and the one you were given joins at the END of it, which is where
-- RemovePokemon and AddPartyMon put it on the cartridge, and the Pokedex is
-- told about the new one.
Gen3Commands.SPECIALS[257] = function(ctx)
  local mon, slot = ctx.g3TradeMon, ctx.g3TradeSlot
  local party = (ctx.save or {}).party
  ctx.g3TradeMon, ctx.g3TradeSlot = nil, nil
  if not (mon and slot and party and party[slot]) then return end
  table.remove(party, slot)
  party[#party + 1] = mon
  local save = ctx.save
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.owned = save.pokedex.owned or {}
  save.pokedex.seen[mon.species] = true
  save.pokedex.owned[mon.species] = true
end

-- ---------------------------------------------------------------------------
-- 174: RockSmashWildEncounter.
--
-- Forty-four rocks stand in Hoenn's caves and passes, and every one of them
-- runs the same script: the badge is checked, the party is asked for ROCK
-- SMASH, the rock shakes and is removed -- and then the cartridge rolls the
-- map's ROCK table for something living under it.  The port already reads
-- that table (the encounter header's third list, 60/30/5/4/1) and nothing
-- was rolling it, so a smashed rock in Hoenn was always empty.
--
-- The script's shape says what has to come back: `special 174` and then
-- `compare VAR_RESULT, 0` -- TRUE means a battle started and the waitstate
-- after it is waiting for that battle; FALSE means the rock was just a rock.
Gen3Commands.SPECIALS[174] = function(ctx)
  setVar(ctx.save, VAR_RESULT, 0)
  local ow = ctx.overworld
  local data = ctx.game and ctx.game.data
  local mapId = ow and ow.map and ow.map.id
  local encDef = mapId and data and data.encounters and data.encounters[mapId]
  local rocks = encDef and encDef.rock
  if not rocks then return 0 end
  local ok, Encounter = pcall(require, "src.world.Encounter")
  if not ok then return 0 end
  local enc = Encounter.rollTable(rocks)
  if not (enc and enc.species) then return 0 end
  setVar(ctx.save, VAR_RESULT, 1)
  Commands.start_battle(ctx, "wild", enc.species, enc.level or 5)
  return 1
end

-- ---------------------------------------------------------------------------
-- 300: TryUpdateRusturfTunnelState -- the one rock in Hoenn that is a door.
--
-- The rock-smash script runs it right after `removeobject`, and the order is
-- the whole mechanism: removing an object SETS its own flag (the cartridge's
-- RemoveObjectEventByLocalIdAndMap does, and so does this port), so by the
-- time this is asked, the rock that was just smashed is the one whose flag is
-- set.  Which of the two it was decides which state the tunnel moves to, and
-- the map's frame table is waiting on exactly those two numbers.
--
-- Answering TRUE also tells the script to SKIP the wild encounter: a Rusturf
-- rock hides a scene, not a Pokemon.
--
-- The map, the var, both values and both flags are read out of the cartridge
-- (constants.gen3Rusturf); the derivation is in RomExtractorGen3:rusturfTunnel
-- and turns on these two rocks being the only smashable rocks in the region
-- whose hide flag is a SAVED one rather than a per-map scratch flag.
--
-- WHAT IS NOT MODELLED, said out loud: the cartridge guards all of this with
-- FLAG_RUSTURF_TUNNEL_OPENED, and this port cannot yet name that flag.  It
-- costs nothing here, because the only way to reach this function is to smash
-- a rock, and once the tunnel is open both rocks are long gone -- there is
-- nothing left on that map to smash.
Gen3Commands.SPECIALS[300] = function(ctx)
  setVar(ctx.save, VAR_RESULT, 0)
  local data = ctx.game and ctx.game.data
  local rule = data and data.constants and data.constants.gen3Rusturf
  local ow = ctx.overworld
  local here = ow and ow.map and ow.map.id
  if not (type(rule) == "table" and here and here == rule.map) then return 0 end
  local flags = (ctx.save and ctx.save.flags) or {}
  for i, flag in ipairs(rule.rocks or {}) do
    if flags[flag] then
      setVar(ctx.save, rule.var, (rule.states or {})[i] or 0)
      setVar(ctx.save, VAR_RESULT, 1)
      return 1
    end
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- 314: BattleSetup_StartLegendaryBattle -- and it is a wild battle.
--
-- Seven scripts on the cartridge run it, and they are the seven that matter:
-- RAYQUAZA on the Sky Pillar, KYOGRE and GROUDON in the Cave of Origin and
-- the Seafloor Cavern, the three REGIS, and LATIOS.  Every one of them has
-- the same shape --
--
--     playmoncry <species> / setwildbattle <species> <level> <item>
--     special BattleSetup_StartLegendaryBattle / waitstate
--     specialvar VAR_RESULT, GetBattleOutcome
--
-- -- so the mon has ALREADY been made by `setwildbattle`, which this port
-- implements, and this special is `dowildbattle` under another name.  What
-- the cartridge adds is BATTLE_TYPE_LEGENDARY, which changes the music and
-- the terrain and nothing about the fight.
--
-- Unimplemented, the whole line was dead: the cry played, the script fell
-- through to GetBattleOutcome, read whatever an unrelated battle had left
-- there, and the legend stood in front of you having done nothing.
Gen3Commands.SPECIALS[314] = function(ctx)
  Commands.g3_wild_battle(ctx)
end

-- ---------------------------------------------------------------------------
-- 315: the three REGIS, and it is the same wild battle 314 is.
--
-- Three scripts on the cartridge call it, one per chamber, and all three are
-- the same twenty-one lines with one species changed --
--
--     playmoncry 401 / setwildbattle 401 40 0
--     setflag 2241 / special 315 / waitstate / clearflag 2241
--     specialvar VAR_RESULT, GetBattleOutcome
--
-- -- 401, 402, 403 being REGIROCK, REGICE and REGISTEEL.  The mon is already
-- built by `setwildbattle`, exactly as it is in front of 314, so this is
-- `dowildbattle` under a third name; what the cartridge adds on top is the
-- Regi battle background, which is scenery.
--
-- Unimplemented it failed the way 314 did: the cry played, the chamber went
-- quiet, and GetBattleOutcome read a stale result off an unrelated fight.
Gen3Commands.SPECIALS[315] = function(ctx)
  Commands.g3_wild_battle(ctx)
end

-- ---------------------------------------------------------------------------
-- 482: setwildbattle, but with the species in variables.
--
-- Six scripts call it and every one of them writes the same three vars in the
-- same order immediately above the call and nothing else --
--
--     setvar VAR_0x8004, <species>
--     setvar VAR_0x8005, <level>
--     setvar VAR_0x8006, <item>
--     special 482
--
-- -- so the special reads 0x8004..0x8006 and builds the enemy mon.  The two
-- shapes it comes in on the cartridge are MEW on Faraway Island (151, level
-- 30, no item, and 314 follows two lines later) and LATIAS (407, level 50,
-- holding SOUL DEW, item 191) set up as a subroutine that ends in `return`
-- for the roamer to pick up.  That is `setwildbattle` with its operands
-- indirected, and this port already has `setwildbattle`.
--
-- Unimplemented, Mew's battle inherited whatever ctx.g3Wild was left over
-- from the last scripted encounter, and Latias was never made at all.
Gen3Commands.SPECIALS[482] = function(ctx)
  local save = ctx.save
  Commands.g3_set_wild(ctx, getVar(save, 0x8004), getVar(save, 0x8005),
                       getVar(save, 0x8006))
end

-- ---------------------------------------------------------------------------
-- 410: show the map name popup again.
--
-- Two scripts call it and they are the same three lines --
--
--     special 410 / setvar 0x400F, 0 / end
--
-- -- both sitting in an ON_FRAME_TABLE entry that fires when 0x400F is 1 and
-- clears it on the way out.  So this is a one-shot: something earlier in the
-- scene set 0x400F, and the frame table's job is to put the sign back up once
-- and disarm.  (The two maps that do it are the ones a cutscene warps you
-- into, where the ordinary announcement on entry was eaten by the fade.)
--
-- This port already reads the sign out of the cartridge --
-- OverworldState:updateMapNameSignGen3, which takes the name from the map's
-- own regionMapSection -- and it already suppresses a repeat by remembering
-- the section it last announced.  That memory is exactly what stands between
-- these scripts and the sign, because the scene left the player on the map
-- whose name it wants shown.  Forgetting it and asking again is the whole
-- special.
Gen3Commands.SPECIALS[410] = function(ctx)
  local ow = ctx.overworld
  if not (ow and ow.updateMapNameSignGen3) then return end
  ow.signLandmark = nil
  ow:updateMapNameSignGen3()
end

-- ---------------------------------------------------------------------------
-- THE SEALED CHAMBER: 282, 307 and 317.
--
-- One script on the cartridge, the back wall of the Sealed Chamber's inner
-- room (MAP_G24_N72), and it is all three of these in a row:
--
--     braillemessage <the wall> / waitbuttonpress / closebraillemessage
--     checkflag 228 / goto_if 1 <done>
--     specialvar VAR_RESULT, 282
--     compare VAR_RESULT, 0 / goto_if 1 <done>
--     fadeoutbgm / playse 49 / special 307 / waitstate / delay 40
--     ( special 317 / waitstate / playse 8 / delay 40 ) x3
--     "It sounded as if a door opened somewhere far away."
--     setflag 228
--
-- -- so 282 is the gate, 307 is the long rumble that answers it, and 317 is
-- the three short knocks, one per Regi chamber.  Unimplemented, the wall was
-- a dead end: the braille was read, the check returned nothing, VAR_RESULT
-- compared equal to 0, and the script went straight to `releaseall / end`.
-- The three chambers could never be opened, which puts REGIROCK, REGICE and
-- REGISTEEL out of the game entirely.
--
-- WHAT THE WALL ASKS FOR is not a guess.  gSpecials[282] is eight
-- instructions long and reads, in order:
--
--     GetMonData(&gPlayerParty[0], MON_DATA_SPECIES)
--     cmp against #0x9D << 1 = 314          -- WAILORD
--     CalculatePlayerPartyCount()
--     GetMonData(&gPlayerParty[count - 1], MON_DATA_SPECIES)
--     cmp against the literal 0x017D = 381  -- RELICANTH
--
-- and returns 1 only if both compares hold.  The wall's own braille says the
-- same thing in as many words -- "FIRST COMES WAILORD. LAST COMES RELICANTH."
-- -- so the cartridge states the rule twice and this port takes it from
-- there rather than from folklore, which has the two the other way round.
local SEALED_FIRST = 314    -- WAILORD, from the cmp in gSpecials[282]
local SEALED_LAST = 381     -- RELICANTH, from the same function's literal
Gen3Commands.SPECIALS[282] = function(ctx)
  local party = (ctx.save or {}).party
  if type(party) ~= "table" or #party < 2 then return 0 end
  local data = ctx.game and ctx.game.data
  local first = speciesId(data, SEALED_FIRST)
  local last = speciesId(data, SEALED_LAST)
  local head = party[1]
  local tail = party[#party]
  if not (head and tail) then return 0 end
  if head.species ~= first then return 0 end
  if tail.species ~= last then return 0 end
  return 1
end

-- 307 and 317: the wall shaking, and the two are the same task with different
-- numbers in it.
--
-- Both build gTasks entries pointing at the same function and fill in three
-- fields; the function then does exactly this, once a frame:
--
--     data[1]++ ; if data[1] % data[5] ~= 0 then return end
--     data[1] = 0 ; data[2]++ ; data[4] = -data[4]
--     SetCameraPanning(0, data[4])
--     if data[2] == data[6] then DestroyTask(...) end
--
-- -- so data[4] is the camera's offset in PIXELS and it flips sign, data[5]
-- is how many frames each side is held, and data[6] is how many flips the
-- shake lasts.  The two specials set them to
--
--     307:  data[4] = 2   data[5] = 5   data[6] = 50
--     317:  data[4] = 3   data[5] = 5   data[6] = 2
--
-- -- 250 frames of a two-pixel rumble, then three bursts of ten frames of a
-- three-pixel knock.  This port's jolt (OverworldState.quakeFrames, which
-- `special 312` already drives) takes a DURATION and picks its own
-- amplitude, so the frame counts are what carry across; the amplitudes are
-- recorded here because they are what the cartridge says, not because
-- anything reads them yet.
Gen3Commands.SEALED_SHAKE = {
  [307] = { pixels = 2, period = 5, flips = 50 },
  [317] = { pixels = 3, period = 5, flips = 2 },
}
local function sealedShake(ctx, which)
  local ow = ctx.overworld
  if not ow then return end
  local shake = Gen3Commands.SEALED_SHAKE[which]
  ow.quakeFrames = shake.period * shake.flips
end

Gen3Commands.SPECIALS[307] = function(ctx) sealedShake(ctx, 307) end
Gen3Commands.SPECIALS[317] = function(ctx) sealedShake(ctx, 317) end

-- ---------------------------------------------------------------------------
-- 498: ISLAND CAVE'S LAP -- "STAY CLOSE TO THE WALL. RUN AROUND ONE LAP."
--
-- ShouldDoBrailleRegicePuzzle, and it is a STEP test wearing a special's
-- clothes.  The wall's own script calls it once --
--
--     braillemessage <the wall> / setflag 2 / special 498
--
-- -- having set flag 2 to say a lap is under way, and the field controller
-- calls it again on every step (the call at 09CA7C, which runs the door
-- script at 0238EAF when it answers 1).  Each call does the same four
-- things, read straight off 0179A04:
--
--     refuse unless the map is Island Cave, the chamber flag is clear,
--       flag 2 is set and flag 3 (the lap is broken) is not;
--     find the player's tile in the 36-entry path and set its bit, sixteen
--       bits to a var across 403B, 403C and 403D;
--     if the player is not on the path at all: set flag 3, clear flag 2;
--     answer 1 only when every bit is set AND the player is back on the
--       tile the wall is on.
--
-- So a lap that is interrupted is not merely un-finished, it is BROKEN, and
-- re-reading the wall is what arms a new one -- which is exactly what the
-- wall's script does with its `setflag 2`.
Gen3Commands.SPECIALS[498] = function(ctx)
  return Gen3Commands.regiceLap(ctx) and 1 or 0
end

function Gen3Commands.regiceLap(ctx)
  local ow = ctx.overworld
  local game = ctx.game
  local player = ow and ow.player
  local map = ow and ow.map
  if not (game and player and map) then return false end
  local Gen3Regi = require("src.world.Gen3Regi")
  local chamber, lap = Gen3Regi.lapOf(game, map.id)
  if not (chamber and lap) then return false end
  local save = ctx.save or game.save
  local flags = save and save.flags
  if not flags then return false end
  if flags[chamber.flag] then return false end
  local running = Gen3Commands.flagKey(lap.running)
  local broken = Gen3Commands.flagKey(lap.broken)
  if not flags[running] then return false end
  if flags[broken] then return false end

  local index = Gen3Regi.pathIndex(lap, player.cellX, player.cellY)
  if not index then
    -- off the path: the lap is over, and only the wall can start another
    flags[broken] = true
    flags[running] = nil
    return false
  end
  local bits = require("bit")
  local var, bit = Gen3Regi.bitFor(lap, index)
  if var then
    setVar(save, var, bits.bor(getVar(save, var) or 0, bits.lshift(1, bit)))
  end
  for _, entry in ipairs(Gen3Regi.masks(lap)) do
    if bits.band(getVar(save, entry.var) or 0, entry.mask) ~= entry.mask then
      return false
    end
  end
  local finish = lap.finish or {}
  return player.cellX == finish[1] and player.cellY == finish[2]
end

-- Flags 2 and 3 are ordinary numbered flags, and this port spells a numbered
-- flag the way its save walk does.
function Gen3Commands.flagKey(n)
  return ("FLAG_G3_%04X"):format(tonumber(n) or 0)
end

-- ---------------------------------------------------------------------------
-- 206 and 207: THE FERRY.
--
-- SetSSTidalFlag and ResetSSTidalFlag, and between them they are the whole
-- SS TIDAL ride.  gSpecials[206] is four instructions --
--
--     FlagSet($88D) ; *VarPointer($404A) = 0
--
-- -- and gSpecials[207] is one, FlagClear($88D).  The step counter in the
-- field controller's chain (0137FC0) guards on that same flag and counts
-- that same var, and its script (0823C050) branches on var $40B4, which is
-- what the two boarding scripts set to 2 or 7.  So: boarding arms the ride
-- and zeroes the count, the ride is measured in steps, and 205 steps later
-- the announcement comes and 207 disarms it.
--
-- Unimplemented, the flag was never set, so the counter never counted and
-- the ferry never arrived: the boarding scripts printed their line, set
-- $40B4, and the ride simply did not happen.  Every one of the numbers above
-- is read off the cartridge by extractFieldCalls and travels in
-- constants.gen3FieldCalls.cruise.
local function cruiseRecord(ctx)
  local data = ctx.game and ctx.game.data
  local record = data and data.constants and data.constants.gen3FieldCalls
  return record and record.cruise or nil
end

Gen3Commands.SPECIALS[206] = function(ctx)
  local cruise = cruiseRecord(ctx)
  local save = ctx.save
  if not (cruise and save) then
    Logger.warn("gen3: this dataset has no ferry, so boarding arms nothing")
    return
  end
  local flags = save.flags
  if flags then flags[cruise.flag] = true end
  setVar(save, cruise.var, 0)
end

Gen3Commands.SPECIALS[207] = function(ctx)
  local cruise = cruiseRecord(ctx)
  local save = ctx.save
  if not (cruise and save) then return end
  local flags = save.flags
  if flags then flags[cruise.flag] = nil end
end

-- 519: PlayerFaceTrainerAfterBattle.
--
-- Sixty scripts call it, all of them the same beat: the battle is over, the
-- player is standing wherever the approach left them, and the line that
-- follows is the trainer talking to their face.  297 is the other half of
-- the same courtesy (the trainer turning to the player) and was already
-- here; this is the player turning back.
Gen3Commands.SPECIALS[519] = function(ctx)
  local ow = ctx.overworld
  local npc = ctx.npc
  local player = ow and ow.player
  if not (npc and player) then return end
  local dx = (npc.cellX or 0) - (player.cellX or 0)
  local dy = (npc.cellY or 0) - (player.cellY or 0)
  if dx == 0 and dy == 0 then return end
  if math.abs(dx) >= math.abs(dy) then
    player.facing = dx > 0 and "right" or "left"
  else
    player.facing = dy > 0 and "down" or "up"
  end
end

-- 286: WaitWeather.
--
-- `special WaitWeather / waitstate` is how a script holds while the
-- cartridge's weather CROSSFADES from one kind to another.  This port's
-- weather changes on the frame it is told to, so there is nothing to wait
-- for -- and a handler that says so is worth the two lines, because the
-- alternative is a log line every time the sky changes.
Gen3Commands.SPECIALS[286] = function() end

-- 334: Script_FadeOutMapMusic -- the fade the port already has, named.
Gen3Commands.SPECIALS[334] = function(ctx)
  local ok, Music = pcall(require, "src.core.Music")
  if ok and Music and Music.fadeOut then pcall(Music.fadeOut, 8) end
end

-- 521: IsLastMonThatKnowsSurf.
--
-- Asked before a Pokemon is taken away or made to forget SURF: if it is the
-- only one carrying the move, the cartridge refuses, because a player left
-- on an island with no way off is a softlock rather than a mistake.  The
-- slot in question is in 0x8004.
Gen3Commands.SPECIALS[521] = function(ctx)
  local data = ctx.game and ctx.game.data
  local order = data and data.constants and data.constants.moveOrder
  local moves = data and data.constants and data.constants.gen3FieldMoves
  local surf = moves and moves.SURF and moves.SURF.move
  local want = surf and order and order[surf] or "SURF"
  local slot = (getVar(ctx.save, 0x8004) or 0) + 1
  local party = (ctx.save or {}).party or {}
  local knows, chosenKnows = 0, false
  for index, mon in ipairs(party) do
    for _, m in ipairs(mon.moves or {}) do
      local id = (type(m) == "table") and m.id or m
      if id == want then
        knows = knows + 1
        if index == slot then chosenKnows = true end
        break
      end
    end
  end
  return (chosenKnows and knows <= 1) and 1 or 0
end

-- WHICH BARE `special` STILL ANSWERS.
--
-- `specialvar` names the var to put the answer in, and this file has always
-- honoured that.  A bare `special` names none -- but on the cartridge that
-- does not mean the answer is thrown away: the special FUNCTION writes
-- gSpecialVar_Result (0x020375F0) itself, and the script's very next
-- instruction is usually `compare VAR_RESULT, n / goto_if`.
--
-- gSpecials sits at 081DBA64, immediately after the 22-entry gSpecialVars
-- table at 081DBA0C -- which is how VAR_RESULT is known to be script id
-- $800D at 0x020375F0 in the first place.  Walking all 527 entries and
-- looking for a store to that address gives the list below: 57 write it in
-- the special's own body, 7 more through a helper they always call.
--
-- The rest must NOT write it.  Thirty-five specials write $8004..$8007
-- instead -- GetSecretBaseTypeInFrontOfPlayer is one of them -- and five
-- only READ VAR_RESULT, so writing it for them would clobber the value the
-- script is about to compare.  That is why this is a list and not a rule.
local RESULT_SPECIALS = {}
for _, id in ipairs({
  7, 11, 12, 17, 18, 23, 30, 64, 66, 67, 70, 87, 100, 101, 103, 105, 108,
  109, 117, 118, 119, 123, 125, 128, 130, 132, 174, 178, 210, 226, 228, 231,
  249, 260, 265, 301, 309, 328, 330, 342, 347, 364, 365, 372, 388, 405, 408,
  416, 417, 418, 422, 427, 428, 430, 446, 449, 451, 472, 500, 501, 514, 516,
  521, 523,
  -- ...and the ones this port answers now.  A bare `special` writes
  -- VAR_RESULT only for ids on this list, so a special that returns a number
  -- and is not here answers into nothing -- which is what left the rematch
  -- branch and the contest entry check reading a stale result.
  60, 61, 91, 137, 140, 163, 280, 342, 398, 399, 404,
}) do RESULT_SPECIALS[id] = true end
Gen3Commands.RESULT_SPECIALS = RESULT_SPECIALS

function Commands.g3_special(ctx, index, destVar)
  local id = tonumber(index) or 0
  local fn = Gen3Commands.SPECIALS[id]
  if fn then
    local result = fn(ctx)
    if destVar then
      setVar(ctx.save, destVar, tonumber(result) or 0)
    elseif RESULT_SPECIALS[id] and tonumber(result) then
      -- no destination named, but this one answers into VAR_RESULT on the
      -- cartridge, and the next row is the compare that reads it
      setVar(ctx.save, VAR_RESULT, tonumber(result))
    end
    return
  end
  -- AN UNIMPLEMENTED SPECIAL STILL HAS TO ANSWER, when it was asked.
  --
  -- This file already makes the argument, a hundred lines below, about the
  -- opcodes that were unlowered: a dropped question leaves the branch that
  -- follows reading whatever the last unrelated check happened to put in the
  -- comparison register, so the script takes an arm at random.  Leaving the
  -- destination var alone here is the same mistake in the same shape, and it
  -- is not a small one: 243 places in the region write a special's answer
  -- into a var, 218 of them compare it within three instructions, and every
  -- one of those 218 was branching on a stale value.
  --
  -- Zero, because it is the answer that means no, none, zero of them, and
  -- not yet -- which is the arm a script that has not reached its
  -- precondition should take.  A wrong DEFINITE answer is still a bug, but it
  -- is a repeatable one that shows up the same way every run; a stale one is
  -- a different bug each time the player takes a different route to it.
  -- ...AND THE SAME IS TRUE OF A BARE ONE, which is the half this missed.
  --
  -- `specialvar` names the var and is handled above.  A bare `special` names
  -- none -- but sixty-four of the cartridge's specials write
  -- gSpecialVar_Result themselves, and the script's next instruction is the
  -- compare that reads it.  RESULT_SPECIALS is that list.  Answering for the
  -- ones this port HAS was only half the job: an unimplemented one on that
  -- list still left VAR_RESULT holding whatever the last unrelated check
  -- put there, and 73 sites in Hoenn branch on exactly that -- the quiz
  -- lady's bag menu, the contest entry, the Lilycove ferry's destination
  -- list, the Dewford painting, and thirty-seven others.
  --
  -- Zero for the same reason as above: it is the answer that means no, none
  -- and not yet, which is the arm a script that cannot reach its
  -- precondition should take -- and it is the same arm every run, rather
  -- than a different one depending on how the player got here.
  if destVar then
    setVar(ctx.save, destVar, 0)
  elseif RESULT_SPECIALS[id] then
    setVar(ctx.save, VAR_RESULT, 0)
  end
  ctx.g3UnhandledSpecials = ctx.g3UnhandledSpecials or {}
  if not ctx.g3UnhandledSpecials[id] then
    ctx.g3UnhandledSpecials[id] = true
    -- named, not numbered: see src/script/Gen3Specials.lua for why the
    -- cartridge's table can be indexed into after all
    local ok, Gen3Specials = pcall(require, "src.script.Gen3Specials")
    Logger.debug("gen3: special %s not implemented",
                 ok and Gen3Specials.label(id) or tostring(id))
  end
end

-- ---------------------------------------------------------------------------
-- THE REST OF THE OPCODE TABLE
--
-- Everything below was previously unlowered, which is not the same as being
-- unsupported: an unlowered op is DROPPED, so a `checkdecorspace` followed by
-- `goto_if 1` branched on whatever happened to be in the comparison register
-- from the last unrelated check. Answering the question -- even with "no" --
-- is what keeps the script's shape.
--
-- Three kinds here, and they are labelled as such rather than blurred:
--
--   ANSWERED    the port has a real answer and gives it.
--   STUBBED     the port has no such feature (contests, the slot machine,
--               the rotating-tile puzzles, the Pokenav). The op is
--               RECOGNISED, sets whatever the following branch reads, and
--               logs once. The script continues down its "not now" path
--               instead of down a random one.
--   RECORDED    a setter with nowhere to put its value yet; kept on the save
--               so nothing is silently lost and a later feature can read it.
-- ---------------------------------------------------------------------------

local function once(ctx, key, fmt, ...)
  ctx.g3Told = ctx.g3Told or {}
  if ctx.g3Told[key] then return end
  ctx.g3Told[key] = true
  Logger.debug(fmt, ...)
end

-- ANSWERED --------------------------------------------------------------

-- Decorations.  These two used to answer "you own none, and there is room" to
-- everything, because there was no catalogue and no inventory -- so every
-- script that hands one over could hand it over again, and every line that
-- thanked you for having one never ran.  `checkdecor` answers from what the
-- player actually holds; `checkdecorspace` answers from the per-category caps
-- extractMauvilleMan reads off SetDecorationInventoriesPointers, and still
-- says yes for a dataset imported before that stage existed.
function Commands.g3_check_decor(ctx, id)
  local Decor = require("src.world.Gen3Decorations")
  local owned = Decor.owns(ctx.save, valueOf(ctx, id)) and 1 or 0
  setVar(ctx.save, VAR_RESULT, owned)
  setResult(ctx, owned)
end

function Commands.g3_check_decor_space(ctx, id)
  local Decor = require("src.world.Gen3Decorations")
  local data = ctx.game and ctx.game.data
  local room = Decor.roomFor(data, ctx.save, valueOf(ctx, id)) and 1 or 0
  setVar(ctx.save, VAR_RESULT, room)
  setResult(ctx, room)
end

function Commands.g3_check_pc_item(ctx, item, quantity)
  setVar(ctx.save, VAR_RESULT, 0)
  setResult(ctx, 0)
end

function Commands.g3_check_item_type(ctx, item)
  setVar(ctx.save, VAR_RESULT, 0)
  setResult(ctx, 0)
end

-- No POKeNAV news feed, so there is never any.
function Commands.g3_pokenews_active(ctx)
  setVar(ctx.save, VAR_RESULT, 0)
  setResult(ctx, 0)
end

-- Obedience is a traded-mon rule the battle model does not implement; a mon
-- the script asks about is always obedient, which is the harmless answer.
function Commands.g3_check_obedience(ctx)
  setVar(ctx.save, VAR_RESULT, 1)
  setResult(ctx, 1)
end

function Commands.g3_check_fateful(ctx)
  setVar(ctx.save, VAR_RESULT, 0)
  setResult(ctx, 0)
end

-- erasebox clears a region of the text window; the port has one text box and
-- closing it is the same observable thing.
function Commands.g3_erase_box(ctx)
  if Commands.close_text then return Commands.close_text(ctx) end
end

-- RECORDED --------------------------------------------------------------

local function record(save, bucket, key, value)
  if not save then return end
  save.gen3 = save.gen3 or {}
  save.gen3[bucket] = save.gen3[bucket] or {}
  save.gen3[bucket][key] = value
end

-- COUNTS, NOT FLAGS.  Emerald lets you own several of the same decoration --
-- the inventory is an array per category, not a set -- and the old boolean
-- meant a second BALL POSTER overwrote the first and removing one removed
-- them all.  Both also set VAR_RESULT, which is what the giving scripts read
-- to decide whether to print "there is no room".
function Commands.g3_add_decoration(ctx, id)
  local Decor = require("src.world.Gen3Decorations")
  local ok = Decor.give(ctx.save, valueOf(ctx, id))
  setVar(ctx.save, VAR_RESULT, ok and 1 or 0)
  setResult(ctx, ok and 1 or 0)
end

function Commands.g3_remove_decoration(ctx, id)
  local Decor = require("src.world.Gen3Decorations")
  local ok = Decor.take(ctx.save, valueOf(ctx, id))
  setVar(ctx.save, VAR_RESULT, ok and 1 or 0)
  setResult(ctx, ok and 1 or 0)
end

function Commands.g3_set_obedient(ctx, slot)
  record(ctx.save, "obedient", tonumber(slot) or 0, true)
end

function Commands.g3_set_met_location(ctx, slot, location)
  record(ctx.save, "metLocation", tonumber(slot) or 0, tonumber(location) or 0)
end

function Commands.g3_set_fateful(ctx, slot)
  record(ctx.save, "fateful", tonumber(slot) or 0, true)
end

-- STUBBED ---------------------------------------------------------------

function Commands.g3_unimplemented(ctx, what)
  once(ctx, "op:" .. tostring(what),
       "gen3: %s has no implementation in this port yet", tostring(what))
end

-- A minigame the port does not have still has to answer the question the
-- script asks afterwards, or the branch reads a stale register.
function Commands.g3_unimplemented_result(ctx, what, result)
  Commands.g3_unimplemented(ctx, what)
  local value = tonumber(result) or 0
  setVar(ctx.save, VAR_RESULT, value)
  setResult(ctx, value)
end

function Commands.g3_std(ctx, index)
  Logger.debug("gen3: std %s has no lowering", tostring(index))
end

-- OBTAINING AN ITEM IS THE STD SCRIPT'S JOB, and it was not being done.
--
-- `giveitem` and `finditem` are macros.  Neither of them adds anything: they
-- put the item in VAR_0x8000 and the count in VAR_0x8001 and then call a std
-- script, and the std script is where the additem lives.  Decoded from the
-- cartridge:
--
--   std 0  Std_ObtainItem   additem VAR_0x8000, VAR_0x8001 / ...
--   std 1  Std_FindItem     lock / faceplayer / copyvar $8004,$8000 /
--                           copyvar $8005,$8001 / checkitemspace / ...
--                           and on the arm that fits:
--                           removeobject VAR_LAST_TALKED /
--                           additem VAR_0x8004, VAR_0x8005
--
-- This wrote VAR_RESULT = 1 and stopped, so all 302 item pickups in Hoenn --
-- 139 gifts and 163 balls on the ground -- played their whole "you found
-- one!" sequence and handed over nothing.  The ball even stayed on the
-- ground, because removing it is part of the same std script.
--
-- The two copies ($8000 -> $8004) are the cartridge's own, and they matter:
-- the text that follows reads the item name out of $8004.
function Commands.g3_std_obtain_item(ctx, which)
  local save = ctx.save
  local item = getVar(save, 0x8000)
  local count = getVar(save, 0x8001)
  if (tonumber(count) or 0) < 1 then count = 1 end

  if tonumber(which) == 1 then
    -- Std_FindItem: the ball on the ground.  It copies first, then takes the
    -- object away -- and removeobject is what sets the object's event flag,
    -- so the ball is gone for good and not just for this visit.
    setVar(save, 0x8004, item)
    setVar(save, 0x8005, count)
    local last = getVar(save, VAR_LAST_TALKED)
    if (tonumber(last) or 0) ~= 0 then
      Commands.g3_hide_object(ctx, VAR_LAST_TALKED)
    end
  end

  local id = itemIdFor(ctx.game and ctx.game.data, item)
  if id then Commands.give_item(ctx, id, count) end
  -- the bag has no cap in this port, so it always fits
  setVar(save, VAR_RESULT, 1)
  setResult(ctx, 1)
end

-- ---------------------------------------------------------------------------
-- 175-182: GABBY AND TY, the pair with the camera
--
-- Reported from play, straight out of the log:
--
--     gen3: special 177 (GabbyAndTyBeforeInterview) not implemented
--     gen3: special 182 (GetGabbyAndTyLocalIds) not implemented
--     gen3: special 176 (GabbyAndTyAfterInterview) not implemented
--
-- 182 IS THE ONE THAT BREAKS THINGS.  The interview script does not know
-- which two people it is talking to -- the reporters move from route to route
-- as they are beaten -- so it asks, and the special writes their two object
-- local ids into VAR_0x8004 and VAR_0x8005.  Every `applymovement` that
-- follows names those vars.  Unimplemented, both read zero, and local id
-- ZERO IS THE PLAYER: the player walked the reporters' choreography while
-- Gabby and Ty stood still.
--
-- WHICH PAIR is a battle counter folded so it never runs off the end
-- (GabbyAndTyGetBattleNum, 080EC504): the counter itself up to five, and
-- 6 + (n mod 3) after that, so the last three routes cycle forever.  The
-- eight id pairs and the three numbers of that fold are read off the
-- cartridge by extractGabbyAndTy; FALLBACK below is the same data, for a
-- dataset extracted before that stage existed.
--
-- WHAT THE INTERVIEW ASKS ABOUT is the battle you just had -- Gabby's line
-- changes depending on whether your Pokemon was hurt, fainted, was healed, or
-- whether you threw a Ball.  The cartridge counts all four in gBattleResults
-- as the battle runs; this port keeps no such record, so the same four facts
-- are read as the DIFFERENCE the battle made to the party and the bag (see
-- Gen3Commands.battleSnapshot).  It answers the same questions from the other
-- end: a Pokemon that lost HP was damaged, one at zero fainted, a Ball that
-- left the bag was thrown, and anything else that left it was used on a
-- Pokemon -- which is what "healing item" means in a battle.
-- ---------------------------------------------------------------------------

local GABBY_FALLBACK = {
  pairs = { { gabby = 14, ty = 13 }, { gabby = 5, ty = 6 },
            { gabby = 18, ty = 17 }, { gabby = 21, ty = 22 },
            { gabby = 8, ty = 9 }, { gabby = 19, ty = 20 },
            { gabby = 23, ty = 24 }, { gabby = 10, ty = 11 } },
  fold = { above = 5, modulo = 3, offset = 6 },
  count = 8,
}
-- the counter stops rather than wrapping, exactly as the cartridge's does
local GABBY_COUNTER_MAX = 255
-- valA/valB bit numbers, in the order GabbyAndTyBeforeInterview writes them
local GABBY_DAMAGED, GABBY_FAINTED, GABBY_HEALED, GABBY_BALL = 0, 1, 2, 3
local GABBY_ON_AIR = 4

local function gabbyRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  local record = (data and data.constants or {}).gen3GabbyAndTy
  return record or GABBY_FALLBACK
end

local function gabbyData(save)
  save.gen3GabbyAndTy = save.gen3GabbyAndTy
    or { battleNum = 0, valA = 0, valB = 0 }
  return save.gen3GabbyAndTy
end

local function gabbyBit(value, n)
  return math.floor((tonumber(value) or 0) / 2 ^ n) % 2 == 1
end

local function gabbySet(value, n, on)
  value = tonumber(value) or 0
  if gabbyBit(value, n) == (on and true or false) then return value end
  return on and (value + 2 ^ n) or (value - 2 ^ n)
end

-- The counter the two tables are indexed with.
function Gen3Commands.gabbyBattleNum(ctx)
  local record = gabbyRecord(ctx)
  local fold = record.fold or GABBY_FALLBACK.fold
  local n = math.floor(tonumber(gabbyData(ctx.save).battleNum) or 0)
  if n > (tonumber(fold.above) or 5) then
    return (n % (tonumber(fold.modulo) or 3)) + (tonumber(fold.offset) or 6)
  end
  return n
end

-- WHAT THE BATTLE DID, as the difference it made.  Taken at the start of
-- every battle in Hoenn and read back when it ends; nothing outside the
-- interview looks at it, so a battle nobody asks about costs one table.
function Gen3Commands.battleSnapshot(save)
  if type(save) ~= "table" then return nil end
  local party = {}
  for i, mon in ipairs(save.party or {}) do
    party[i] = tonumber(mon.hp) or 0
  end
  local bag = {}
  for id, count in pairs(save.inventory or {}) do bag[id] = count end
  return { party = party, bag = bag }
end

function Gen3Commands.battleFacts(save, before, data)
  local facts = { damaged = false, fainted = false, healed = false,
                  ball = false }
  if type(save) ~= "table" or type(before) ~= "table" then return facts end
  for i, mon in ipairs(save.party or {}) do
    local was = before.party[i]
    if was then
      local now = tonumber(mon.hp) or 0
      if now < was then facts.damaged = true end
      if now == 0 and was > 0 then facts.fainted = true end
    end
  end
  local items = data and data.items or {}
  for id, count in pairs(before.bag) do
    local now = (save.inventory or {})[id] or 0
    if now < count then
      local def = items[id]
      local pocket = def and tostring(def.pocket or ""):upper() or ""
      if pocket == "BALL" then
        facts.ball = true
      elseif pocket ~= "KEY_ITEM" then
        -- an item that left the bag mid-battle was used on a Pokemon
        facts.healed = true
      end
    end
  end
  return facts
end

-- 177: the interview begins.  The counter moves here, not after -- which is
-- why the very first interview is battle one and reaches the first pair.
Gen3Commands.SPECIALS[177] = function(ctx)
  local save = ctx.save
  if not save then return end
  local held = gabbyData(save)
  local n = math.floor(tonumber(held.battleNum) or 0)
  if n < GABBY_COUNTER_MAX then held.battleNum = n + 1 end

  local facts = ctx.lastBattleFacts or {}
  local valA = tonumber(held.valA) or 0
  valA = gabbySet(valA, GABBY_DAMAGED, facts.damaged)
  valA = gabbySet(valA, GABBY_FAINTED, facts.fainted)
  valA = gabbySet(valA, GABBY_HEALED, facts.healed)
  valA = gabbySet(valA, GABBY_BALL, facts.ball)
  held.valA = valA

  -- The two Pokemon the show would name.  The cartridge takes them from
  -- gBattleResults -- the first two the player SENT OUT -- and this port has
  -- no such record, so the front of the party stands in.  Nothing reads them
  -- yet: the TV is not built, and this is here so the interview has something
  -- to have recorded when it is.
  local party = save.party or {}
  held.mon1 = party[1] and party[1].species or held.mon1
  held.mon2 = party[2] and party[2].species or nil
end

-- 176: the interview is over.  The four battle bits are copied into the set
-- the trivia line reads, and the show is marked as being on the air.
Gen3Commands.SPECIALS[176] = function(ctx)
  local save = ctx.save
  if not save then return end
  local held = gabbyData(save)
  local valA = tonumber(held.valA) or 0
  local valB = tonumber(held.valB) or 0
  for _, n in ipairs({ GABBY_DAMAGED, GABBY_FAINTED, GABBY_HEALED,
                       GABBY_BALL }) do
    valB = gabbySet(valB, n, gabbyBit(valA, n))
  end
  held.valB = valB
  held.valA = gabbySet(valA, GABBY_ON_AIR, true)
end

-- 175: the folded counter itself, which a script compares to pick its line
Gen3Commands.SPECIALS[175] = function(ctx)
  local n = Gen3Commands.gabbyBattleNum(ctx)
  setVar(ctx.save, VAR_RESULT, n)
  return n
end

-- 179: is their show on the air?
Gen3Commands.SPECIALS[179] = function(ctx)
  local on = gabbyBit(gabbyData(ctx.save).valA, GABBY_ON_AIR) and 1 or 0
  setVar(ctx.save, VAR_RESULT, on)
  return on
end

-- 180: the quote the player gave last time, said back to them ONCE -- the
-- cartridge clears it as it reads it.  The quote is picked on the easy-chat
-- screen, which this port does not have yet (special 98), so there is nothing
-- to say and the script's own branch skips the line.
Gen3Commands.SPECIALS[180] = function(ctx)
  local held = gabbyData(ctx.save)
  local quote = held.quote
  if quote == nil then
    setVar(ctx.save, VAR_RESULT, 0)
    return 0
  end
  local game = ctx.game
  if game then
    game.stringBuffers = game.stringBuffers or {}
    game.stringBuffers[1] = tostring(quote)
  end
  held.quote = nil
  setVar(ctx.save, VAR_RESULT, 1)
  return 1
end

-- 181: WHICH remark Gabby makes about the battle.  The order is the
-- cartridge's own (080EC58C) and it is a ladder, not a table: an undamaged
-- Pokemon is remarked on before anything else, then a Ball, then a healing
-- item, then a faint.
Gen3Commands.SPECIALS[181] = function(ctx)
  local valB = tonumber(gabbyData(ctx.save).valB) or 0
  local answer
  if not gabbyBit(valB, GABBY_DAMAGED) then answer = 1
  elseif gabbyBit(valB, GABBY_BALL) then answer = 2
  elseif gabbyBit(valB, GABBY_HEALED) then answer = 3
  elseif gabbyBit(valB, GABBY_FAINTED) then answer = 4
  else answer = 0 end
  setVar(ctx.save, VAR_RESULT, answer)
  return answer
end

-- 182: who the script is talking to.
Gen3Commands.SPECIALS[182] = function(ctx)
  local record = gabbyRecord(ctx)
  local list = record.pairs or GABBY_FALLBACK.pairs
  local n = Gen3Commands.gabbyBattleNum(ctx)
  local who = list[n]
  if not who then
    -- battle zero: they have never been fought, so there is no pair to name
    -- and the cartridge writes nothing either
    return
  end
  setVar(ctx.save, 0x8004, who.gabby)
  setVar(ctx.save, 0x8005, who.ty)
end

-- ---------------------------------------------------------------------------
-- 491/492: THE ABNORMAL WEATHER
--
-- Reported from play as part of the weather round.  After the legendary wakes,
-- a storm settles over ONE route in Hoenn and the cave under it opens --
-- Marine Cave or Terra Cave, whichever holds the one still out there.  None of
-- it ever happened here, and the reason was not the routes: thirty-six places
-- in Hoenn already compare VAR_ABNORMAL_WEATHER_LOCATION and put the weather
-- and the cave mouth on the map when it names them.  The var was never set.
--
-- 491 sets it.  Which half of the table it picks is the cartridge's own test
-- (0813B2E4): one flag sends the player to the first cave, the other to the
-- second, and with neither set a coin decides -- and then eight spots inside
-- that half, two on each of four routes.
--
-- 492 is what the script asks when it wants to SAY where the storm is: it
-- buffers the route's name and answers which cave it means.
--
-- The sixteen locations, the two vars, the step limit and the split all come
-- off the cartridge (extractAbnormalWeather); FALLBACK is what the port knows
-- without them, which is nothing but the var numbers -- a location table
-- guessed here would put the cave on the wrong route.
-- ---------------------------------------------------------------------------

-- the two flags 491 tests, in the order it tests them
local ABNORMAL_FLAGS = { 0x1BE, 0x1BF }

local function abnormalRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  return (data and data.constants or {}).gen3AbnormalWeather
end

Gen3Commands.SPECIALS[491] = function(ctx)
  local record = abnormalRecord(ctx)
  local save = ctx.save
  if not (record and save) then return end
  local split = math.floor(tonumber(record.split) or 8)
  local count = math.floor(tonumber(record.count) or 16)
  setVar(save, record.varCounter, 0)

  local flags = save.flags or {}
  local half
  if flags[Gen3Commands.flagKey(ABNORMAL_FLAGS[1])] then
    half = 0
  elseif flags[Gen3Commands.flagKey(ABNORMAL_FLAGS[2])] then
    half = split
  else
    -- neither has been dealt with, so the cartridge tosses for it
    half = math.random(0, 1) == 1 and split or 0
  end
  local spots = half == 0 and split or (count - split)
  setVar(save, record.varLocation, half + math.random(1, math.max(1, spots)))
end

Gen3Commands.SPECIALS[492] = function(ctx)
  local record = abnormalRecord(ctx)
  local save = ctx.save
  if not (record and save) then return 0 end
  local where = record.locations
                and record.locations[getVar(save, record.varLocation)]
  if not where then
    setVar(save, VAR_RESULT, 0)
    return 0
  end
  local data = ctx.game and ctx.game.data
  local sections = (data and data.constants or {}).gen3MapSections or {}
  local name = sections[where.section]
  if type(name) == "string" and #name > 0 and ctx.game then
    ctx.game.stringBuffers = ctx.game.stringBuffers or {}
    ctx.game.stringBuffers[1] = name
  end
  -- the first cave answers zero, which is what the compare after the call
  -- branches on
  local answer = (tonumber(where.cave) or 1) > 1 and 1 or 0
  setVar(save, VAR_RESULT, answer)
  return answer
end

-- ---------------------------------------------------------------------------
-- 63, 217 AND 218: THE REST OF THE PC
--
-- Three gaps left over from the bedroom PC, and one of them was not cosmetic.
--
-- 63 IS "SOMEONE'S PC".  The PC in a Poke Centre is a script multichoice --
-- SOMEONE'S PC / {PLAYER}'s PC / HALL OF FAME / LOG OFF -- and the first row
-- runs special 63, which was unimplemented: the whole box system was
-- unreachable from every Poke Centre in Hoenn.  It opens the same storage
-- menu the bedroom PC's box row does.
--
-- 217 AND 218 ARE THE SCREEN.  Reported from play as a log line on every PC:
-- "special 217 (DoPCTurnOnEffect) not implemented".  The cartridge swaps the
-- metatile of the tile the player is facing back and forth five times, six
-- frames apart, ending lit; turning it off is the same swap done once.  Both
-- metatile sets, the blink's interval and count and the step from the player
-- to the screen are read off the cartridge (see pcScreenBlink), and WHICH
-- pair is used is VAR_0x8004's -- the script sets it before it calls.
-- ---------------------------------------------------------------------------

Gen3Commands.SPECIALS[63] = function(ctx)
  pushBlocking(ctx, "StorageMenu")
end

-- the facing the cartridge reads, as this port spells it
local PC_SCREEN_FACING = { down = 1, up = 2, left = 3, right = 4 }

-- Where the screen is, and which pair of metatiles it wears.  Returns nil
-- when the record is not in this dataset or the player is facing a way the
-- cartridge has no step for (south -- you cannot use a PC from below it).
local function pcScreenAt(ctx)
  local data = ctx.game and ctx.game.data
  local screen = ((data and data.constants or {}).gen3PCMenu or {}).screen
  local ow = ctx.overworld
  local player = ow and ow.player
  if not (type(screen) == "table" and player and player.cellX) then return nil end
  local dir = PC_SCREEN_FACING[player.facing] or 1
  local step = screen.step and screen.step[dir]
  if not step then return nil end
  local kind = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0) + 1
  if not (screen.on[kind] and screen.off[kind]) then return nil end
  return screen, player.cellX + step.dx, player.cellY + step.dy, kind
end

-- The metatile write itself.  The cartridge ors the collision bits into the
-- id it writes, which is what `impassable` is here: a PC is a wall whether
-- its screen is lit or not.
local function pcScreenSet(ctx, screen, x, y, tile)
  local ow = ctx.overworld
  if not (ow and ow.map and ow.map.setBlock) then return end
  ow.map:setBlock(x, y, tile, true)
  -- and ask for the redraw, or the block changes and nothing shows it
  if ow.redrawBlocks then ow:redrawBlocks() end
end

Gen3Commands.SPECIALS[217] = function(ctx)
  local screen, x, y, kind = pcScreenAt(ctx)
  if not screen then return end
  local ow = ctx.overworld
  -- the blink is the overworld's to run: the script does not wait for it
  ow.gen3PcScreen = {
    x = x, y = y,
    frames = 0,
    left = math.floor(tonumber(screen.blinks) or 5),
    interval = math.max(1, math.floor(tonumber(screen.interval) or 6)),
    lit = screen.on[kind],
    dark = screen.off[kind],
    -- the cartridge's task starts with the LIT frame and toggles from there,
    -- so an odd count ends lit
    on = true,
  }
end

Gen3Commands.SPECIALS[218] = function(ctx)
  local screen, x, y, kind = pcScreenAt(ctx)
  if not screen then return end
  local ow = ctx.overworld
  if ow then ow.gen3PcScreen = nil end
  pcScreenSet(ctx, screen, x, y, screen.off[kind])
end

Gen3Commands.pcScreenSet = pcScreenSet

-- ---------------------------------------------------------------------------
-- 265: THE MENU A PC OPENS WITH
--
-- A PC is a METATILE, not an object: the field picks a script by the tile's
-- behaviour and runs it, and the first thing that script does is ask this
-- question.  The port had no rows for it, so every Poke Centre PC in Hoenn
-- fell through to the Game Boy's PC menu -- the same complaint the bedroom's
-- PC drew ("I get the gen1 menus").
--
-- The rows are built rather than listed, which is why they are a special and
-- not a multichoice list: the first is SOMEONE'S PC until you have met
-- Lanette and LANETTE'S PC afterwards, and HALL OF FAME only exists once the
-- game is cleared.  Both flags and all five labels are the cartridge's (see
-- pcMultichoice).
--
-- THE ANSWER IS THE ROW INDEX, raw -- the input task writes what the menu
-- returns and nothing remaps it -- so with no HALL OF FAME row, LOG OFF is
-- row 2 and the script's own `checkflag` on the HALL OF FAME arm is what
-- sends it to the log-off script instead.  That is the cartridge's guard, and
-- keeping the raw index is what lets it work.
-- ---------------------------------------------------------------------------

local PC_MULTI_FALLBACK = {
  someone = "SOMEONE'S PC", lanette = "LANETTE'S PC",
  player = "{PLAYER}'s PC", hallOfFame = "HALL OF FAME", logOff = "LOG OFF",
  lanetteFlag = 0x8AB, hallFlag = 0x864,
}

function Gen3Commands.pcMenuRows(ctx)
  local data = ctx.game and ctx.game.data
  local record = ((data and data.constants or {}).gen3PCMenu or {}).multichoice
                 or PC_MULTI_FALLBACK
  local flags = (ctx.save and ctx.save.flags) or {}
  local rows = {}
  rows[#rows + 1] = flags[Gen3Commands.flagKey(record.lanetteFlag)]
                    and record.lanette or record.someone
  rows[#rows + 1] = record.player
  if flags[Gen3Commands.flagKey(record.hallFlag)] then
    rows[#rows + 1] = record.hallOfFame
  end
  rows[#rows + 1] = record.logOff
  return rows
end

-- ---------------------------------------------------------------------------
-- 263 and 264: THE TRICK HOUSE NUGGET.
--
-- The last two unserved specials in the whole thirteen-map Trick House, and
-- between them they are one flag.  Both handlers do the same three things:
-- put the flag number in VAR_0x8004, then 264 sets it and 263 clears it --
-- the entrance room's NUGGET, hidden once it has been picked up and put back
-- when the house moves on to its next puzzle.  The flag comes out of the two
-- handlers' own literal pools, which agree, and the extractor keeps them
-- only when they do.
local NUGGET_VAR = 0x8004

local function trickHouseNugget(ctx, set)
  local data = ctx.game and ctx.game.data
  local record = ((data and data.constants or {}).gen3TrickHouseNugget)
  local flag = record and record.flag
  if not flag then return end
  setVar(ctx.save, NUGGET_VAR, flag)
  local flags = ctx.save and ctx.save.flags
  if not flags then return end
  flags[Gen3Commands.flagKey(flag)] = set or nil
end

Gen3Commands.SPECIALS[263] = function(ctx) trickHouseNugget(ctx, false) end
Gen3Commands.SPECIALS[264] = function(ctx) trickHouseNugget(ctx, true) end

Gen3Commands.SPECIALS[265] = function(ctx)
  local rows = Gen3Commands.pcMenuRows(ctx)
  -- {PLAYER} is the only placeholder any of them carries
  local name = ctx.save and ctx.save.player and ctx.save.player.name
  for i, row in ipairs(rows) do
    rows[i] = tostring(row):gsub("{PLAYER}", tostring(name or "PLAYER"))
  end
  askChoices(ctx, rows)
end

-- ---------------------------------------------------------------------------
-- SECRET BASES: 6, 7, 8, 9, 10, 18, 21, 24 and 332
--
-- Reported from play: "secret power to create secret bases also arent working
-- it does nothing when i have the move taught to my pokemon and hit a on a
-- secret base area".  Seventy-five entrances in the region, every one of them
-- carrying its own base id, and not one handler between them.
--
-- The flow is the cartridge's own script (S02759F1, which the field runs for
-- a secret-base bg event -- see extractSecretBases), and these are the
-- specials it calls, in the order it calls them:
--
--     21  which kind of spot is in front of you   -> VAR_0x8007
--      7  do you already have a base              -> VAR_RESULT
--      6  this one is yours now
--      8  go in
--     18  put the furniture out
--
-- ...and the way out is 9, 10 or 332, which all warp back to where you came
-- in.  That last part needs nothing new: the room's one exit names map 127 of
-- group 127, the cartridge's "wherever you came from" placeholder, and this
-- port already resolves it through save.gen3DynamicWarp (the truck a new game
-- starts in is built out of the same pair).
--
-- WHAT THIS SLICE DOES NOT DO is furnish the room.  18 is a deliberate
-- no-op with its name on it rather than a missing special, because a base you
-- can walk into and out of is worth having before the decorations exist.
-- ---------------------------------------------------------------------------

local VAR_SECRET_BASE_ID = 0x8004     -- what the bg event hands the script
local VAR_SPOT_KIND = 0x8007          -- ...and what 21 answers into

local function secretBaseRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  return require("src.world.Gen3SecretBase").record(data)
end

-- 21: GetSecretBaseTypeInFrontOfPlayer.
--
-- THE WRONG NUMBER, ASKED OF THE RIGHT TABLE.
--
-- The cartridge's GetSecretBaseTypeInFrontOfPlayer (080E8BF8) steps one cell
-- ahead and calls MapGridGetMetatileBehaviorAt (080882BC), then compares six
-- pairs of BEHAVIOUR bytes: 90/91 red cave, 92/93 brown, 9A/9B blue, 94/95
-- yellow, 96/97 and 9C/9D tree, 98/99 shrub.  The record extracted from that
-- code is keyed 144..157 for exactly that reason.
--
-- This asked `blockAt`, which answers the METATILE ID -- 0..1023, and at the
-- 75 entrance cells in Hoenn it is one of 38, 39, 416, 424, 432, 520, 625.
-- Not one of those is in 144..157, so `kindOf` answered nil on every secret
-- base spot in the game, VAR_0x8007 came out 0, and all six branches of
-- 0827_59F1 missed and fell to its `end`.  Pressing A did nothing, whether
-- or not anyone in the party knew SECRET POWER -- the script never reached
-- the `checkpartymove` at all.
--
-- `cellBehaviour` is the accessor that answers a behaviour byte, and the
-- Gen 3 tileset stage fills that table with `word % 256` for this purpose.
-- Zero stays a real answer: it means "not a secret base spot", and the
-- script's own branches all missing is then correct.
Gen3Commands.SPECIALS[21] = function(ctx)
  local SB = require("src.world.Gen3SecretBase")
  local ow = ctx.overworld
  local player = ow and ow.player
  local kind = 0
  if player and player.facingCell and ow.map and ow.map.cellBehaviour then
    local okCell, fx, fy = pcall(player.facingCell, player)
    if okCell and fx then
      local okB, behaviour = pcall(ow.map.cellBehaviour, ow.map, fx, fy)
      if okB then
        kind = SB.kindOf(secretBaseRecord(ctx), behaviour) or 0
      end
    end
  end
  setVar(ctx.save, VAR_SPOT_KIND, kind)
  return kind
end

-- 7: CheckPlayerHasSecretBase -- one byte in the save on the cartridge, and
-- one table here.
Gen3Commands.SPECIALS[7] = function(ctx)
  local has = require("src.world.Gen3SecretBase").mine(ctx.save) and 1 or 0
  setVar(ctx.save, VAR_RESULT, has)
  return has
end

-- 6: SetPlayerSecretBase.  The id is the one the entrance handed the script;
-- where the player is standing goes with it, because that is what the room's
-- exit has to put them back on.
Gen3Commands.SPECIALS[6] = function(ctx)
  local save = ctx.save
  if not save then return end
  local id = math.floor(tonumber(getVar(save, VAR_SECRET_BASE_ID)) or 0)
  local ow = ctx.overworld
  local player = ow and ow.player
  require("src.world.Gen3SecretBase").claim(save, id,
                                            ow and ow.map and ow.map.id,
                                            player and player.cellX,
                                            player and player.cellY)
end

local function enterSecretBase(ctx)
  local SB = require("src.world.Gen3SecretBase")
  local save = ctx.save
  local record = secretBaseRecord(ctx)
  if not save then return end
  local mine = SB.mine(save)
  local id = mine and mine.id or getVar(save, VAR_SECRET_BASE_ID)
  local room = SB.roomFor(record, id)
  if not room or not room.map then
    Logger.warn("gen3 secret base: no room for base %s -- this dataset was "
                .. "imported before the rooms were read", tostring(id))
    return
  end
  local ow = ctx.overworld
  local player = ow and ow.player
  SB.remember(save, ow and ow.map and ow.map.id,
              player and player.cellX, player and player.cellY, record)
  local wx, wy = warpCell(ctx, room.map,
                          math.max(1, math.floor(tonumber(room.warp) or 1)))
  if not (wx and wy) then
    Logger.warn("gen3 secret base: %s has no entrance warp in this dataset",
                tostring(room.map))
    return
  end
  Commands.warp(ctx, room.map, wx, wy)
end

Gen3Commands.SPECIALS[8] = enterSecretBase

-- 24: EnterNewlyCreatedSecretBase, AND IT IS NOT ANOTHER 8.
--
-- Reported from play: "after making a secret base when i try and exit it puts
-- me right back in the secret base room".  This port aliased 24 to the same
-- function as 8, and 8's first act is to record where you are standing as the
-- way back out.  But 8 runs OUTSIDE, on the route, with the outdoor map still
-- current -- and 24 runs INSIDE, after 8 has already put you in the room and
-- the "make this yours?" script has said yes.  Running 8's body there records
-- the BASE ROOM as the way out of the base room, and the one exit dutifully
-- takes you back in.
--
-- The cartridge's 24 (080E91F8 -> 080E9168) never touches the dynamic warp at
-- all.  What it does is warp you to the room you are already in, at the two
-- coordinate bytes on the room's own row -- which is how the scene resets
-- with the base now furnished and the entrance under your feet.  It is the
-- absence of the write that matters, and no guard on the write could have
-- supplied it: only splitting the two specials apart does.
Gen3Commands.SPECIALS[24] = function(ctx)
  local SB = require("src.world.Gen3SecretBase")
  local save = ctx.save
  if not save then return end
  local record = secretBaseRecord(ctx)
  local mine = SB.mine(save)
  local id = mine and mine.id or getVar(save, VAR_SECRET_BASE_ID)
  local room, wx, wy = SB.entranceFor(record, id)
  if not room then
    -- a dataset imported before the entrance coordinates were read: standing
    -- still is right, because the player is already in the room 8 put them in
    Logger.debug("gen3 secret base: no entrance cell for base %s -- the "
                 .. "newly-made enter leaves the player where they are",
                 tostring(id))
    return
  end
  Commands.warp(ctx, room.map, wx, wy)
end

-- 9 / 10 / 332: GIVING THE BASE UP, which is not the same as leaving it.
--
-- Walking out is a warp and nothing else -- the room's exit names the
-- come-back-out marker and this port already resolves that.  These three are
-- the base PC's RETIRE row and the "move my base here" flow, and what they do
-- is CLEAR the record (080E9A90 zeroes it): 9 and 10 clear it and walk you
-- out, and 332 clears it while you are standing outside, which is why it is
-- the one the move-your-base script calls and why it must not warp.
local function leaveSecretBase(ctx)
  local SB = require("src.world.Gen3SecretBase")
  local save = ctx.save
  SB.giveUp(save)
  local back = save and save.gen3DynamicWarp
  if not (back and back.map) then
    Logger.warn("gen3 secret base: asked to leave with no way back recorded")
    return
  end
  Commands.warp(ctx, back.map, back.x, back.y)
end

Gen3Commands.SPECIALS[9] = leaveSecretBase
Gen3Commands.SPECIALS[10] = leaveSecretBase

-- ...and the one that clears it from OUTSIDE, which stays where it is
Gen3Commands.SPECIALS[332] = function(ctx)
  require("src.world.Gen3SecretBase").giveUp(ctx.save)
end

-- 18: InitSecretBaseDecorationSprites.  The forty-five DOLLs and CUSHIONs are
-- drawn as object sprites rather than written into the map grid, and the
-- cartridge spawns them here because its map has already been built by the
-- time this special runs.  This port builds them WITH the map instead --
-- OverworldState:applyGen3Decorations, off the same save rows -- so by the
-- time a script can call this they are already standing, and doing it twice
-- would double them.
Gen3Commands.SPECIALS[18] = function() end

-- ---------------------------------------------------------------------------
-- THE BASE'S OWN PC: specials 11 to 17, 22, 26 and 352.
--
-- Reported from play: "the pc in the secret base room doesnt work".  Two
-- separate things were wrong and the first hid the second.  The PC is a
-- METATILE -- behaviour $B0 -- not an object and not a bg event, so no press
-- ever reached its script (that half is fixed in OverworldState:tryPcTile).
-- And behind that script sit nine specials, every one of which was missing:
-- the menu it puts up asks CheckSecretBaseRegistryFlag, its rows call the
-- decoration screen, the registry and the retire flow, and its way out turns
-- the screen off.  With none of them answering, even a reachable PC would
-- have shown a menu whose every row did nothing.
--
-- WHAT EACH ONE IS, read off the cartridge:
--
--   11  is this base someone else's?   compares secretBases[0].id with the
--                                      one you walked into (080E9744)
--   12  the registry state of it       (080E9BDC -> 080E9878)
--   13  toggle that state              flips bits 6-7 of the byte after the
--                                      id (080E9C2C)
--   14  the DECORATION screen          (080E9C74)
--   15  the REGISTRY screen            (080E9C88)
--   16  the visit's battle set-up      (080EA2E4)
--   17  the owner and whether you have
--       already fought them today      (080EA354)
--   22  the owner's sprite for a visit (080E95D4)
--   26  turn the PC off                (080FA57C)
--  352  the base's own vars, zeroed    four of them (080EB1AC)
--
-- SIX OF THOSE ARE ABOUT OTHER PLAYERS' BASES, which a save with no link
-- cable never has one of.  They answer honestly -- no, empty, nothing to do
-- -- rather than pretending, and the rows of the menu that depend on them
-- behave exactly as they do on a cartridge that has never been traded with.
-- ---------------------------------------------------------------------------

local VAR_CURRENT_BASE = 0x4054       -- which of the twenty slots is loaded
local VAR_BASE_OWNER_GFX = 0x401F     -- ...and the sprite its owner wears

-- 11: is the base you are standing in someone else's?  The cartridge asks it
-- of ONE byte -- your own base's id against the one the entrance handed the
-- script -- so a save that owns no base answers "yes, someone else's", which
-- is what sends the script down the visitor branch.
Gen3Commands.SPECIALS[11] = function(ctx)
  local SB = require("src.world.Gen3SecretBase")
  local save = ctx.save
  local mine = SB.mine(save)
  local here = math.floor(tonumber(getVar(save, VAR_SECRET_BASE_ID)) or 0)
  local other = (not mine or math.floor(tonumber(mine.id) or -1) ~= here)
                and 1 or 0
  setVar(save, VAR_RESULT, other)
  return other
end

-- 12 / 13: the registry, which is the list of other players whose bases you
-- keep.  Nothing in a single-player save ever puts a row in it, so 12 answers
-- "not registered" and 13 has nothing to flip -- and both say so through the
-- same table the friend's-base PC would fill.
Gen3Commands.SPECIALS[12] = function(ctx)
  local SB = require("src.world.Gen3SecretBase")
  local slot = getVar(ctx.save, VAR_CURRENT_BASE)
  local state = SB.registryState(ctx.save, slot) and 1 or 0
  setVar(ctx.save, VAR_RESULT, state)
  return state
end

Gen3Commands.SPECIALS[13] = function(ctx)
  local SB = require("src.world.Gen3SecretBase")
  local slot = getVar(ctx.save, VAR_CURRENT_BASE)
  local now = SB.toggleRegistry(ctx.save, slot)
  setVar(ctx.save, VAR_RESULT, now and 1 or 0)
  return now and 1 or 0
end

-- 15: the REGISTRY screen.  It lists the bases you have registered; there are
-- none, and the honest form of that is the cartridge's own empty list rather
-- than a menu with no rows.
Gen3Commands.SPECIALS[15] = function(ctx)
  local SB = require("src.world.Gen3SecretBase")
  local options = {}
  for _, row in ipairs(SB.registered(ctx.save)) do
    options[#options + 1] = tostring(row.name or "SECRET BASE")
  end
  if #options == 0 then
    return Gen3Commands.secretBasePCReturn(ctx)
  end
  options[#options + 1] = "CANCEL"
  Gen3Commands.pcMenu(ctx, options, function()
    Gen3Commands.secretBasePCReturn(ctx)
  end, function() Gen3Commands.secretBasePCReturn(ctx) end)
end

-- 16 / 17 / 22: the three that only mean something when the base you are
-- standing in belongs to somebody else -- setting up the owner's party for a
-- battle, dropping records that are not yours, and putting the owner's sprite
-- on screen.  With no registry there is no owner and no party; the sprite var
-- is cleared rather than left holding the last thing that wrote it, because a
-- stale gfx id there is a stranger standing in your own base.
Gen3Commands.SPECIALS[16] = function() end
-- 17 answers TWO things and they are not the same var: VAR_0x8004 gets the
-- owner's class and VAR_RESULT gets the bit that says you have already
-- battled them today (080EA3A8 / 080EA3C2).  With no owner both are zero,
-- and saying so is what keeps the visitor script from offering a rematch
-- against nobody.
Gen3Commands.SPECIALS[17] = function(ctx)
  setVar(ctx.save, 0x8004, 0)
  setVar(ctx.save, VAR_RESULT, 0)
  return 0
end
Gen3Commands.SPECIALS[22] = function(ctx)
  setVar(ctx.save, VAR_BASE_OWNER_GFX, 0)
  return 0
end

-- 352: the four vars the base's battle queue uses, zeroed together.
Gen3Commands.SPECIALS[352] = function(ctx)
  for id = 0x40EC, 0x40EF do setVar(ctx.save, id, 0) end
end

-- 26: the way out of the PC.  The script's last three rows are `special 26 /
-- closemessage / releaseall`, and what 26 does is put the screen back to
-- black -- the field effect the first row switched on.
Gen3Commands.SPECIALS[26] = function(ctx)
  local ow = ctx.overworld
  if ow then ow.gen3PcScreen = nil end
end

-- Re-open the PC after a screen it launched has closed.  The cartridge's
-- decoration and registry screens both return to it, and the script itself
-- cannot: its row ends with `end` because the screen owns what happens next.
function Gen3Commands.secretBasePCReturn(ctx)
  local SB = require("src.world.Gen3SecretBase")
  local base = SB.record(ctx.game and ctx.game.data)
  local arm = base and base.pc and base.pc.own
  local ow = ctx.overworld
  if not (arm and arm.script and ow and ow.gen3RunFieldScript) then return end
  ow:gen3RunFieldScript(arm.script, "secret base PC")
end

-- 14: THE DECORATION SCREEN, which is the row that matters.
--
-- Four rows, read off the cartridge with them (08126BB6): DECORATE, PUT AWAY,
-- TOSS and CANCEL.  DECORATE picks something you own and hands the player a
-- cursor; PUT AWAY takes one back off the floor; TOSS throws one out for
-- good.  All three work on the same save rows the room is rebuilt from, so
-- anything put out is still there next time you walk in.
-- A MENU THAT DOES NOT WAIT ON THE SCRIPT.  Every one of the PC's rows ends
-- its script with `end` rather than releasing the player, because on the
-- cartridge the SCREEN it opened owns what happens next and eventually walks
-- back into the PC script itself.  askChoices is the wrong shape for that --
-- it suspends the runner and resumes it with an answer -- so these push their
-- own menu and drive the rest with callbacks.
function Gen3Commands.pcMenu(ctx, options, onPick, onCancel)
  local game = ctx.game
  local okMenu, Menu = pcall(require, "src.ui.Menu")
  if not (okMenu and game and game.stack and #options > 0) then
    if onCancel then onCancel() end
    return false
  end
  local items, widest = {}, 0
  for index, label in ipairs(options) do
    if #label > widest then widest = #label end
    items[index] = { label = label,
                     onSelect = function() onPick(index, label) end }
  end
  local tw = math.max(6, math.floor(widest / 2) + 4)
  local pushed = pcall(game.stack.push, game.stack,
                       Menu.new(game, items,
                                { tx = 0, ty = 0, tw = tw,
                                  th = #items * 2 + 2, onCancel = onCancel }))
  if not pushed and onCancel then onCancel() end
  return pushed
end

-- ...AND IT IS NOT ONLY THE SECRET BASE'S.
--
-- Reported from play: "the lady in the game corner that is supposed to give
-- you a doll doesnt give you anything".  She does -- the thousand coins come
-- off and the DOLL lands in the decoration inventory -- but her line is
-- "we'll send it to your PC at home", and the PC at home said DECORATION was
-- not built.  So the screen is opened from BOTH: the secret base's PC, which
-- is what special 14 is, and the bedroom's, which is a screen and not a
-- script.  `onExit` is the only thing that differs between them.
function Gen3Commands.decorationPC(ctx, onExit)
  local Decor = require("src.world.Gen3Decorations")
  local data = ctx.game and ctx.game.data
  local rows = (Decor.record(data) or {}).menu
  onExit = onExit or function() Gen3Commands.secretBasePCReturn(ctx) end
  if type(rows) ~= "table" or #rows == 0 then
    Logger.warn("gen3 decorations: this dataset has no decoration menu -- "
                .. "imported before it was read")
    return onExit()
  end
  local options = {}
  for i, row in ipairs(rows) do options[i] = row.name end
  local function back() Gen3Commands.decorationPC(ctx, onExit) end
  Gen3Commands.pcMenu(ctx, options, function(index)
    Gen3Commands.decorationRow(ctx, index, back, onExit)
  end, onExit)
end

Gen3Commands.SPECIALS[14] = function(ctx)
  return Gen3Commands.decorationPC(ctx)
end

-- ------- the three rows that do something
--
-- DECORATE lists what you own that will fit, PUT AWAY lists what is standing
-- in the room, TOSS lists what you own; CANCEL goes back to the PC.  All four
-- return here rather than to the field, which is what the cartridge's own
-- screen does.
function Gen3Commands.decorationRow(ctx, row, back, onExit)
  onExit = onExit or function() Gen3Commands.secretBasePCReturn(ctx) end
  local Decor = require("src.world.Gen3Decorations")
  local data = ctx.game and ctx.game.data
  local save = ctx.save
  local ow = ctx.overworld
  local where = ow and ow.map
                and Decor.placeFor(data, save, ow.map.id) or nil
  if row == 1 and where then                       -- DECORATE
    local held, ids = {}, {}
    for _, own in ipairs(Decor.held(data, save)) do
      if Decor.shapeOf(data, own.def.id) then
        held[#held + 1] = ("%s x%d"):format(own.def.name, own.count)
        ids[#ids + 1] = own.def.id
      end
    end
    if #held == 0 then return back() end
    held[#held + 1] = "CANCEL"
    Gen3Commands.pcMenu(ctx, held, function(index)
      if not ids[index] then return back() end
      ow:gen3DecorateBegin(ids[index], function() back() end)
    end, back)
    return
  end
  if row == 2 and where then                       -- PUT AWAY
    local rows, indices = {}, {}
    for _, standing in ipairs(Decor.standing(data, save, where)) do
      rows[#rows + 1] = standing.def.name
      indices[#indices + 1] = standing.index
    end
    if #rows == 0 then return back() end
    rows[#rows + 1] = "CANCEL"
    Gen3Commands.pcMenu(ctx, rows, function(index)
      if indices[index] then
        Decor.putAway(data, save, where, indices[index])
        if ow.refreshGen3Decorations then ow:refreshGen3Decorations() end
      end
      back()
    end, back)
    return
  end
  if row == 3 then                                 -- TOSS
    local names, ids = {}, {}
    for _, own in ipairs(Decor.held(data, save)) do
      names[#names + 1] = ("%s x%d"):format(own.def.name, own.count)
      ids[#ids + 1] = own.def.id
    end
    if #names == 0 then return back() end
    names[#names + 1] = "CANCEL"
    Gen3Commands.pcMenu(ctx, names, function(index)
      if ids[index] then Decor.take(save, ids[index], 1) end
      back()
    end, back)
    return
  end
  onExit()
end

-- ---------------------------------------------------------------------------
-- 299: THE ONE THAT WON'T STAND STILL.
--
-- Beat the league and the television names a Pokemon seen over Hoenn, and
-- the scene calls this to put it in the air.  There was no handler, and
-- `src/world/RoamMons.lua` is Crystal's three-beast byte roll keyed by names
-- a Hoenn save has none of -- so the whole system was a legendary the game
-- announces and that is nowhere in the region.
--
-- WHICH one is VAR_0x8004's to say: CreateInitialRoamerMon (08161B94)
-- branches on it and loads one species number in each arm.  Everything else
-- -- the level, the fixed IV, the twenty places it can be -- is the record's,
-- read off that same function.
-- ---------------------------------------------------------------------------
Gen3Commands.SPECIALS[299] = function(ctx)
  local Roam = require("src.world.Gen3Roamers")
  local which = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  local it = Roam.release(ctx.game and ctx.game.data, ctx.save, which)
  if not it then
    Logger.warn("gen3 roamer: nothing to release -- this dataset was "
                .. "imported before the roamer was read")
    return 0
  end
  Logger.info("gen3 roamer: %s is loose, starting on %s", tostring(it.species),
              tostring(it.map))
  return 1
end

-- ---------------------------------------------------------------------------
-- MATCH CALL AND REMATCHES: specials 60, 61, 62, 489, and the registration
-- that happens without a script asking.
--
-- THREE FUNCTIONS THAT LOOK THE SAME AND ARE NOT.  A script uses 60 to pick
-- what the trainer SAYS and 61 to decide whether the fight happens, and the
-- two deliberately disagree:
--
--   60  ShouldTryRematchBattle   armed now, OR ever rematched before
--   61  IsTrainerReadyForRematch armed now
--
-- so a trainer you have already rematched still offers, and only a trainer
-- the overworld has actually armed will fight.  Reading 60 as 61 -- the
-- obvious simplification -- makes every rematch trainer in Hoenn silent
-- between arms instead of offering and declining.
--
-- 62 is the fight itself, and WHICH of the five trainers on the row it is
-- comes from the defeat flags rather than from a counter: the first of the
-- five you have not beaten.
-- ---------------------------------------------------------------------------

local function matchCall()
  return require("src.script.MatchCall")
end

-- gTrainerBattleOpponent_A: the trainer the running script is about.
local function currentTrainer(ctx)
  return tonumber(ctx.g3Trainer)
end

Gen3Commands.SPECIALS[60] = function(ctx)
  local MC = matchCall()
  local data = ctx.game and ctx.game.data
  local id = currentTrainer(ctx)
  if not (data and id) then return 0 end
  local index = MC.rowForFirst(data, id)
  if not index then return 0 end
  if MC.isReady(data, ctx.save, index) then return 1 end
  -- WasSecondRematchWon: the second id on the row has been beaten, which
  -- means this trainer has been rematched at least once
  local row = MC.rematchRows(data)[index + 1]
  local second = row and row.trainers[2]
  return (second and MC.beaten(ctx.save, second)) and 1 or 0
end

Gen3Commands.SPECIALS[61] = function(ctx)
  local MC = matchCall()
  local data = ctx.game and ctx.game.data
  local id = currentTrainer(ctx)
  if not (data and id) then return 0 end
  -- ...and THIS one matches any of the five, not just the first
  local index = MC.rowForAny(data, id)
  if not index then return 0 end
  return MC.isReady(data, ctx.save, index) and 1 or 0
end

Gen3Commands.SPECIALS[62] = function(ctx)
  local MC = matchCall()
  local data = ctx.game and ctx.game.data
  local id = currentTrainer(ctx)
  if not (data and id) then return end
  local index = MC.rowForFirst(data, id) or MC.rowForAny(data, id)
  local fight = MC.rematchTrainer(data, ctx.save, id)
  startTrainer(ctx, fight)
  if ctx.lastBattleResult == "win" then
    -- ClearTrainerWantRematchState: the row disarms on the win, and the
    -- overworld has to roll it again before this trainer will fight once more
    if index then MC.clearReady(ctx.save, index) end
    Gen3Commands.markTrainerBeaten(ctx, fight)
  end
end

-- SetMatchCallRegisteredFlag, and the automatic registration behind it.
--
-- The special is the SCRIPTED registration -- Mr. Stone handing you his
-- number -- and it takes the trainer in VAR_0x8004.  The one that matters
-- more is not a special at all: RegisterTrainerInMatchCall runs off the end
-- of every trainer battle you win, gated on flag $12F, and it is what puts
-- the route trainers in your POKeNAV without anybody saying so.
local MATCH_CALL_GATE = 0x12F

function Gen3Commands.registerTrainerInMatchCall(ctx, trainerId)
  local MC = matchCall()
  local data = ctx.game and ctx.game.data
  if not (data and tonumber(trainerId)) then return false end
  if (ctx.save.flags or {})[Gen3Commands.flagKey(MATCH_CALL_GATE)] ~= true then
    return false
  end
  local index = MC.rowForFirst(data, tonumber(trainerId))
  if not index then return false end
  ctx.save.flags = ctx.save.flags or {}
  ctx.save.flags[MC.registeredFlag(data, index)] = true
  return true
end

Gen3Commands.SPECIALS[489] = function(ctx)
  local MC = matchCall()
  local data = ctx.game and ctx.game.data
  local id = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  if not data then return end
  local index = MC.rowForFirst(data, id)
  if not index then return end
  ctx.save.flags = ctx.save.flags or {}
  ctx.save.flags[MC.registeredFlag(data, index)] = true
end

-- 497: IsTrainerRegistered -- "have I got this one's number?"
--
-- gSpecials[497] (013B4E0) is three steps and no more:
--
--     idx = GetRematchIdxByTrainerIdx(gSpecialVar_0x8004)
--     if (idx < 0) return 0
--     return FlagGet(174 * 2 + idx) == 1
--
-- 174*2 is 348, which is the same base SetMatchCallRegisteredFlag writes to
-- and the same one the import placed on the record -- two derivations meeting
-- on one number, which is what says it is read right.  The lookup is
-- GetRematchIdxByTrainerIdx (81D15CC): it compares the FIRST id of each of
-- the 78 rematch rows, not every id in them, so a trainer who only appears
-- as a later rung of somebody else's ladder answers "not a rematch trainer"
-- rather than borrowing that row's flag.
--
-- WHAT ASKS.  Three route trainers, and all three ask the same way: battle,
-- then `setvar VAR_0x8004,<id> / specialvar VAR_RESULT,497 / goto_if 0` to
-- the branch that offers you their number.  Answering zero for everybody
-- meant every one of them offered it again, every time, forever.
Gen3Commands.SPECIALS[497] = function(ctx)
  local MC = matchCall()
  local data = ctx.game and ctx.game.data
  local id = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  if not data then return 0 end
  local index = MC.rowForFirst(data, id)
  if not index then return 0 end
  return MC.isRegistered(data, ctx.save, index) and 1 or 0
end

-- ---------------------------------------------------------------------------
-- THE CLOCK, AND THE SEVEN SPECIALS THAT ASK IT SOMETHING
--
-- gLocalTime.days is "days since the cartridge's clock was set", which on a
-- new game is days since it began.  There is no RTC here; the port's clock is
-- os.time() in whole days, which is already what the weather stage and the
-- berry trees run on, so this is that same clock with the save's own first
-- day taken off it.  A save that has never asked starts at zero today.
function Gen3Commands.dayNumber(save)
  if not save then return 0 end
  local now = (os and os.time and os.time()) or 0
  local today = math.floor(now / 86400)
  save.gen3Day0 = tonumber(save.gen3Day0) or today
  return today - save.gen3Day0
end

-- 259: GetWeekCount -- gLocalTime.days / 7, capped at 9999 (0813 8BDC: the
-- divide, then `cmp r0, 0x270F / bls`).  The cap is the cartridge's and it
-- matters: the number is printed, and a save left running for thirty years
-- would print six digits into a five-digit box.
Gen3Commands.SPECIALS[259] = function(ctx)
  local weeks = math.floor(Gen3Commands.dayNumber(ctx.save) / 7)
  if weeks < 0 then weeks = 0 end
  return math.min(9999, weeks)
end

-- 335 / 336: the Pacifidlog TM, which is given once a week.
--
-- SetPacifidlogTMReceivedDay (0139754) is `VarSet(VAR_PACIFIDLOG_TM_RECEIVED_
-- DAY, gLocalTime.days)` and answers the same number.  Its partner
-- (013970C) is the countdown:
--
--     since = gLocalTime.days - VarGet(0x40C2)
--     if (since > 6) return 0        -- a week has passed; you may have it
--     if (gLocalTime.days < 0) return 8   -- the clock has been wound back
--     return 7 - since
--
-- Zero is the arm that hands the TM over, which is why an unimplemented
-- special answering zero looked right and was not: it handed one over every
-- single day.
local VAR_PACIFIDLOG_TM_DAY = 0x40C2

Gen3Commands.SPECIALS[335] = function(ctx)
  local days = Gen3Commands.dayNumber(ctx.save)
  setVar(ctx.save, VAR_PACIFIDLOG_TM_DAY, days)
  return days
end

Gen3Commands.SPECIALS[336] = function(ctx)
  local days = Gen3Commands.dayNumber(ctx.save)
  local since = days - math.floor(tonumber(getVar(ctx.save,
                                                  VAR_PACIFIDLOG_TM_DAY)) or 0)
  if since > 6 then return 0 end
  if days < 0 then return 8 end
  return 7 - since
end

-- 318: FoundBlackGlasses -- one FlagGet, of flag 149*4 = 596 (0139634:
-- `mov r0,#149 / lsl r0,r0,#2 / bl FlagGet`).
Gen3Commands.SPECIALS[318] = function(ctx)
  return (ctx.save.flags or {})[Gen3Commands.flagKey(596)] == true and 1 or 0
end

-- ---------------------------------------------------------------------------
-- THE DEX, ASKED FROM A SCRIPT
--
-- 215: ScriptGetPokedexInfo (0137A4C).  VAR_0x8004 picks which dex -- zero is
-- Hoenn, anything else is national -- 0x8005 takes SEEN, 0x8006 takes CAUGHT,
-- and the special itself answers IsNationalPokedexEnabled().  The Hall of
-- Fame's script and the game-clear sequence both read all three.
--
-- The Hoenn count is over the LISTING and not over the species table, which
-- is the same distinction the dex screen makes: a Kanto Pokemon caught with
-- the national dex on does not raise the Hoenn number.
local function dexCounts(ctx, national)
  local save = ctx.save or {}
  local dex = save.pokedex
  if not dex then return 0, 0 end
  local data = ctx.game and ctx.game.data or {}
  local record = (data.constants or {}).gen3HoennDex
  local seen, owned = 0, 0
  if national then
    for id in pairs(dex.seen or {}) do if id then seen = seen + 1 end end
    for id in pairs(dex.owned or {}) do if id then owned = owned + 1 end end
    return seen, owned
  end
  local numbers = (type(record) == "table") and record.numbers or nil
  if type(numbers) ~= "table" then return 0, 0 end
  local native = tonumber(record.native) or 0
  for id, n in pairs(numbers) do
    if n >= 1 and n <= native then
      if (dex.seen or {})[id] then seen = seen + 1 end
      if (dex.owned or {})[id] then owned = owned + 1 end
    end
  end
  return seen, owned
end

-- MATCH CALL BORROWS THIS.  PROF. BIRCH's phone call is the same two numbers
-- read the same way, so it asks here rather than counting the dex a second
-- time with its own idea of what "Hoenn" means.
Gen3Commands.dexCounts = dexCounts

Gen3Commands.SPECIALS[215] = function(ctx)
  local national = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0) ~= 0
  local seen, owned = dexCounts(ctx, national)
  setVar(ctx.save, 0x8005, seen)
  setVar(ctx.save, 0x8006, owned)
  return (ctx.save and ctx.save.nationalDex) and 1 or 0
end

-- 337: HasAllHoennMons (0C08E4).  Hoenn numbers ONE to TWO HUNDRED, every one
-- of them caught -- not 202.  The last two rows of the Hoenn dex are JIRACHI
-- and DEOXYS, which no ordinary save can reach, and the cartridge's loop
-- stops before them (`cmp r0,#199 / bls`).  Counting all 202 would make the
-- diploma unobtainable, which is the sort of gate nobody would ever debug.
Gen3Commands.SPECIALS[337] = function(ctx)
  local dex = ctx.save and ctx.save.pokedex
  if not dex then return 0 end
  local data = ctx.game and ctx.game.data or {}
  local record = (data.constants or {}).gen3HoennDex
  local numbers = (type(record) == "table") and record.numbers or nil
  if type(numbers) ~= "table" then return 0 end
  local byNumber = {}
  for id, n in pairs(numbers) do
    if n >= 1 and n <= 200 then byNumber[n] = id end
  end
  for n = 1, 200 do
    local id = byNumber[n]
    if not (id and (dex.owned or {})[id]) then return 0 end
  end
  return 1
end

-- 341: DoesPartyHaveEnigmaBerry (0F9370) -- does any party member hold item
-- 175, and if so put the berry's own name in the first string buffer.
local ITEM_ENIGMA_BERRY = 175

Gen3Commands.SPECIALS[341] = function(ctx)
  local data = ctx.game and ctx.game.data or {}
  local items = data.items or {}
  local want
  for id, def in pairs(items) do
    if tonumber(def and def.index) == ITEM_ENIGMA_BERRY then want = id break end
  end
  if not want then return 0 end
  for _, mon in ipairs((ctx.save or {}).party or {}) do
    if mon.item == want then
      if ctx.game then
        ctx.game.stringBuffers = ctx.game.stringBuffers or {}
        ctx.game.stringBuffers[1] = (items[want] or {}).name or want
      end
      return 1
    end
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- 212: IsMirageIslandPresent
--
-- The rarest thing in Hoenn, and it is one comparison: the island is there if
-- ANY Pokemon in the party has a personality whose low sixteen bits equal
-- VAR_MIRAGE_RND_H.  013793C walks the six slots, stops at the first empty
-- one, and compares `personality & 0xFFFF` against `GetMirageRnd() >> 16`,
-- which 0137890 builds as `VarGet(0x4024) << 16 | VarGet(0x4025)` -- so the
-- half that is compared is 0x4024 on its own.
--
-- WHAT ROLLS IT is not a special: the cartridge rerolls both vars once a day
-- out of the overworld's own day handler.  There is no such handler here yet,
-- so this rolls them on the first read of each new day -- which gives the
-- same behaviour where it is observable (a fixed answer for a whole day, one
-- day in sixty-five thousand per Pokemon) and is stated as reconstructed
-- rather than left at zero, which would have made the island unreachable.
local VAR_MIRAGE_RND_H, VAR_MIRAGE_RND_L = 0x4024, 0x4025

Gen3Commands.SPECIALS[212] = function(ctx)
  local save = ctx.save
  if not save then return 0 end
  local day = Gen3Commands.dayNumber(save)
  if save.gen3MirageDay ~= day then
    save.gen3MirageDay = day
    local r = (love and love.math and love.math.random) or math.random
    setVar(save, VAR_MIRAGE_RND_H, r(0, 65535))
    setVar(save, VAR_MIRAGE_RND_L, r(0, 65535))
  end
  local want = math.floor(tonumber(getVar(save, VAR_MIRAGE_RND_H)) or 0)
  for _, mon in ipairs(save.party or {}) do
    if not mon.species then break end
    local p = tonumber(mon.personality)
    if p and (math.floor(p) % 65536) == want then return 1 end
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- 122 / 123 / 124 / 125: THE TWO SIZE-RECORD HOUSES
--
-- A brother in Sootopolis judges SEEDOTs and his sister judges LOTADs, and
-- both run the same eight rows of script:
--
--     special 122            -- fill the buffers with the standing record
--     ... msgbox ...
--     special 162            -- ChoosePartyMon
--     waitstate
--     copyvar VAR_RESULT, VAR_0x8004
--     compare VAR_RESULT, 255 / goto_if eq   -- you backed out
--     special 123                            -- measure it
--     compare VAR_RESULT, 1 / goto_if eq     -- that is not a SEEDOT
--     compare VAR_RESULT, 2 / goto_if eq     -- not big enough
--     compare VAR_RESULT, 3 / goto_if eq     -- a new record
--
-- HOW BIG A POKEMON IS is not its level or its species height on its own.
-- GetMonSizeHash (0F97C8) folds the personality and the six IVs into sixteen
-- bits, and GetMonSize (0F989C) runs that through a fourteen-row piecewise
-- table -- the one the import rips -- scaled by the species' dex height:
--
--     i     = the last row whose `from` the hash has passed
--     units = row.size + (hash - row.from) / row.step
--     size  = units * heightInDecimetres / 10        (millimetres)
--
-- The table's middle rows step by 150 hash units and its ends by one, which
-- is what makes a giant rare rather than merely uncommon.
--
-- WHAT IS STORED is the winning HASH, not the size, so the house can
-- re-measure an old record; and its untouched value is 0x8000, dead centre.
-- A save that has never been asked holds zero, which is off the bottom of the
-- table, so zero is READ AS the default here -- otherwise the first SEEDOT
-- anybody showed would be a record whatever it was.
-- ---------------------------------------------------------------------------

local function sizeRecordData(ctx)
  local data = ctx.game and ctx.game.data
  local record = (data and data.constants or {}).gen3SizeRecords
  if type(record) ~= "table" or type(record.rows) ~= "table" then return nil end
  return record
end

local function sizeRecordFor(ctx, special)
  local record = sizeRecordData(ctx)
  if not record then return nil, nil end
  for _, row in ipairs(record.records or {}) do
    if row.info == special or row.compare == special then
      return record, row
    end
  end
  return record, nil
end

-- eight-bit exclusive or, without a bit library: both sides are bytes here
-- (an IV product is at most 225 and a personality byte at most 255).
local function xor8(a, b)
  local out, p = 0, 1
  a, b = math.floor(a) % 256, math.floor(b) % 256
  for _ = 1, 8 do
    if (a % 2) ~= (b % 2) then out = out + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return out
end

-- GetMonSizeHash (0F97C8), instruction for instruction: the IVs are taken
-- four bits at a time and the personality only sixteen.
function Gen3Commands.monSizeHash(mon)
  local ivs = (type(mon) == "table") and mon.ivs or nil
  local function iv(key)
    return math.floor(tonumber(ivs and ivs[key]) or 0) % 16
  end
  local p = math.floor(tonumber(mon and mon.personality) or 0) % 65536
  local hi = xor8(xor8(iv("attack"), iv("defense")) * iv("hp"), p % 256)
  local lo = xor8(iv("speed") * xor8(iv("spatk"), iv("spdef")),
                  math.floor(p / 256) % 256)
  return (hi * 256 + lo) % 65536
end

-- GetMonSize (0F989C): the table lookup, then the species' own height.
function Gen3Commands.monSizeFromHash(record, heightDecimetres, hash)
  local rows = record and record.rows
  if type(rows) ~= "table" or #rows == 0 then return 0 end
  hash = math.floor(tonumber(hash) or 0) % 65536
  -- TranslateBigMonSizeTableIndex: the last row the hash has reached
  local pick = rows[1]
  for i = 2, #rows do
    if hash < rows[i].from then break end
    pick = rows[i]
  end
  local step = math.max(1, math.floor(tonumber(pick.step) or 1))
  local units = math.floor(tonumber(pick.size) or 0)
                + math.floor((hash - math.floor(tonumber(pick.from) or 0)) / step)
  local height = math.floor(tonumber(heightDecimetres) or 0)
  return math.floor(units * height / 10)
end

-- FormatMonSizeRecord (0F9910): millimetres to INCHES with one decimal --
-- which is why the sign says "19.6-inch giant" and not a number of metres.
function Gen3Commands.formatMonSize(size)
  local tenths = math.floor(math.floor(tonumber(size) or 0) * 10 / 25.4)
  return ("%d.%d"):format(math.floor(tenths / 10), tenths % 10)
end

local function heightOf(ctx, species)
  local data = ctx.game and ctx.game.data
  local def = data and data.pokemon and data.pokemon[species]
  -- the cache keeps metres, and the cartridge's field is decimetres
  return math.floor((tonumber(def and def.height) or 0) * 10 + 0.5)
end

local function storedRecord(ctx, record, row)
  local held = math.floor(tonumber(getVar(ctx.save, row.var)) or 0)
  -- zero is "never asked", and the cartridge's untouched value is 0x8000
  if held == 0 then return math.floor(tonumber(record.default) or 0x8000) end
  return held
end

local function buffer(ctx, n, text)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[n] = text
end

local function sizeRecordInfo(ctx, special)
  local record, row = sizeRecordFor(ctx, special)
  if not (record and row) then return end
  local held = storedRecord(ctx, record, row)
  local size = Gen3Commands.monSizeFromHash(record,
                                            heightOf(ctx, row.species), held)
  local data = ctx.game and ctx.game.data
  local def = data and data.pokemon and data.pokemon[row.species]
  buffer(ctx, 1, (def and def.name) or row.species)
  buffer(ctx, 3, Gen3Commands.formatMonSize(size))
  -- the standing record's holder: the cartridge's own name until the player
  -- takes it off him
  if held == math.floor(tonumber(record.default) or 0x8000) then
    buffer(ctx, 2, record.defaultHolder or "")
  else
    buffer(ctx, 2, ((ctx.save or {}).player or {}).name or "")
  end
end

local function compareMonSize(ctx, special)
  local record, row = sizeRecordFor(ctx, special)
  if not (record and row) then return 0 end
  local slot = math.floor(tonumber(getVar(ctx.save, VAR_RESULT)) or 0)
  if slot == Gen3Commands.PARTY_NOTHING_CHOSEN then return 0 end
  local mon = ((ctx.save or {}).party or {})[slot + 1]
  if not mon then return 0 end
  if require("src.pokemon.Party").isEgg(mon) then return 1 end
  if mon.species ~= row.species then return 1 end
  local height = heightOf(ctx, row.species)
  local hash = Gen3Commands.monSizeHash(mon)
  local mine = Gen3Commands.monSizeFromHash(record, height, hash)
  local best = Gen3Commands.monSizeFromHash(record, height,
                                            storedRecord(ctx, record, row))
  buffer(ctx, 2, Gen3Commands.formatMonSize(mine))
  if mine > best then
    setVar(ctx.save, row.var, hash)
    return 3
  end
  return 2
end

Gen3Commands.SPECIALS[122] = function(ctx) return sizeRecordInfo(ctx, 122) end
Gen3Commands.SPECIALS[124] = function(ctx) return sizeRecordInfo(ctx, 124) end
Gen3Commands.SPECIALS[123] = function(ctx) return compareMonSize(ctx, 123) end
Gen3Commands.SPECIALS[125] = function(ctx) return compareMonSize(ctx, 125) end

-- ---------------------------------------------------------------------------
-- 204 / 205: THE ROTATING GATES' TWO MAP SCRIPTS
--
-- Fortree Gym and the Trick House's eighth puzzle each keep two entries and
-- they call different specials:
--
--   ON_TRANSITION -> 204 RotatingGate_InitPuzzle
--       RotatingGate_LoadPuzzleConfig, then
--       RotatingGate_ResetAllGateOrientations
--   ON_RESUME     -> 205 RotatingGate_InitPuzzleAndGraphics
--       the gfx, RotatingGate_LoadPuzzleConfig, then the sprites -- and NO
--       reset (080FBED0 does not call 080FB818)
--
-- That difference is the whole of it: walking in puts the puzzle back to its
-- starting position, and coming back from a battle or a menu does not.  The
-- port reset on every map entry, which was right for one of the two and had
-- no way to be asked for the other.
Gen3Commands.SPECIALS[204] = function(ctx)
  local ow = ctx.game and ctx.game.overworld
  if ow and ow.startGen3Gates then ow:startGen3Gates(nil, false) end
end

Gen3Commands.SPECIALS[205] = function(ctx)
  local ow = ctx.game and ctx.game.overworld
  if ow and ow.startGen3Gates then ow:startGen3Gates(nil, true) end
end

-- ---------------------------------------------------------------------------
-- THE LEAD POKEMON, which is not simply the first slot.
--
-- GetLeadMonIndex (0139688) walks the party and takes the first member that
-- is a real Pokemon, is not an EGG and still has HP; only if none of them
-- qualifies does it fall back to slot zero.  Every special below that says
-- "the lead" means that one, and an EGG in the front slot is exactly the case
-- that tells the two readings apart.
function Gen3Commands.leadMon(ctx)
  local party = ((ctx and ctx.save) or {}).party or {}
  local Party = require("src.pokemon.Party")
  for _, mon in ipairs(party) do
    if mon and mon.species and not Party.isEgg(mon)
       and (tonumber(mon.hp) or 0) > 0 then
      return mon
    end
  end
  return party[1]
end

-- ---------------------------------------------------------------------------
-- 268..272: THE CONTEST JUDGE AT SLATEPORT'S FAN CLUB
--
-- Five specials, one shape: CheckLeadMonCool (0139004) reads the lead's own
-- COOL byte and answers whether it is over 199.  The other four are the same
-- function against the other four conditions, and 199 is the cartridge's own
-- compare -- a Pokemon fed almost to the top of one flavour, not merely fed.
local GEN3_CONDITION_FLOOR = 199
local GEN3_CONDITION_SPECIALS = {
  [268] = "cool", [269] = "beauty", [270] = "cute",
  [271] = "smart", [272] = "tough",
}
for index, key in pairs(GEN3_CONDITION_SPECIALS) do
  Gen3Commands.SPECIALS[index] = function(ctx)
    local lead = Gen3Commands.leadMon(ctx)
    if not lead then return 0 end
    local Contest = require("src.pokemon.Contest")
    return Contest.get(lead, key) > GEN3_CONDITION_FLOOR and 1 or 0
  end
end

-- ---------------------------------------------------------------------------
-- 290..293: THE ABANDONED SHIP'S FOUR ROOM KEYS
--
-- Each is two instructions and no more: put the key's own hidden-item flag in
-- VAR_0x8004 and answer FlagGet of it.  The var matters as much as the
-- answer -- the script that follows uses it to hide the item once it has been
-- taken -- and the four flags are consecutive but for one, which is why they
-- are listed rather than counted from a base.
local GEN3_SHIP_KEY_FLAGS = { [290] = 531, [291] = 532, [292] = 533,
                              [293] = 534 }
for index, flag in pairs(GEN3_SHIP_KEY_FLAGS) do
  Gen3Commands.SPECIALS[index] = function(ctx)
    setVar(ctx.save, 0x8004, flag)
    return (ctx.save.flags or {})[Gen3Commands.flagKey(flag)] == true and 1 or 0
  end
end

-- ---------------------------------------------------------------------------
-- 294 / 295 / 296: THE EFFORT RIBBON
--
-- The woman in Slateport's fan club hands out a ribbon for a Pokemon whose
-- effort values are full.  Three specials and each is one fact:
--
--   296 Special_AreLeadMonEVsMaxedOut: GetMonEVCount(lead) > 509.  The
--       cartridge's compare is `> 0x1FD` and not `>= 510`, which is the same
--       thing said in the way the hardware said it.
--   295 GiveLeadMonEffortRibbon: a fanfare, flag 0x89B, and the ribbon.
--   294 LeadMonHasEffortRibbon: does it carry one.
local GEN3_MAX_EVS = 509                  -- the compare, not the cap
local GEN3_EFFORT_RIBBON_FLAG = 0x89B

local function evTotal(mon)
  local evs = (type(mon) == "table") and mon.evs or nil
  if type(evs) ~= "table" then return 0 end
  local total = 0
  for _, key in ipairs(require("src.pokemon.Stats").ORDER_GEN3) do
    total = total + math.floor(tonumber(evs[key]) or 0)
  end
  return total
end

Gen3Commands.SPECIALS[296] = function(ctx)
  local lead = Gen3Commands.leadMon(ctx)
  return (lead and evTotal(lead) > GEN3_MAX_EVS) and 1 or 0
end

Gen3Commands.SPECIALS[294] = function(ctx)
  local lead = Gen3Commands.leadMon(ctx)
  local ribbons = lead and lead.ribbons
  return (type(ribbons) == "table" and ribbons.effort) and 1 or 0
end

Gen3Commands.SPECIALS[295] = function(ctx)
  local lead = Gen3Commands.leadMon(ctx)
  ctx.save.flags = ctx.save.flags or {}
  ctx.save.flags[Gen3Commands.flagKey(GEN3_EFFORT_RIBBON_FLAG)] = true
  if not lead then return 0 end
  lead.ribbons = lead.ribbons or {}
  lead.ribbons.effort = true
  pcall(function()
    require("src.core.Sound").playFanfare(ctx.game and ctx.game.data,
                                          "Fanfare_ObtainedItem")
  end)
  return 1
end

-- ---------------------------------------------------------------------------
-- 427: HasAtLeastOneBerry -- the berry-blender queue's own question.
--
-- The cartridge walks its berry range and stops at the first one the bag
-- holds.  A berry is a POCKET here, which is the same set said the way this
-- port already keeps it, so the walk is over that pocket.
Gen3Commands.SPECIALS[427] = function(ctx)
  local Bag = require("src.inventory.Bag")
  local data = ctx.game and ctx.game.data
  local ok, held = pcall(Bag.pocketSlots, ctx.save, "BERRY", data)
  return (ok and (tonumber(held) or 0) > 0) and 1 or 0
end

-- 430: IsDodrioInParty -- the Dodrio Berry Picking gate, which is one
-- species walk over the party (0027A5C, species 85).
Gen3Commands.SPECIALS[430] = function(ctx)
  local data = ctx.game and ctx.game.data
  local order = (data and data.constants or {}).speciesOrder
  local want = type(order) == "table" and order[85] or "DODRIO"
  for _, mon in ipairs((ctx.save or {}).party or {}) do
    if mon and mon.species == want then return 1 end
  end
  return 0
end

-- 150: GetPlayerTrainerIdOnesDigit -- the visible half of the trainer id,
-- modulo ten (0138AF0 reads the two low bytes and divides by 10).
Gen3Commands.SPECIALS[150] = function(ctx)
  local player = ((ctx.save or {}).player) or {}
  local id = math.floor(tonumber(player.trainerId or player.id) or 0)
  return (id % 65536) % 10
end

-- 281: GetSecretBaseNearbyMapName -- the section named by VAR_0x4026, put in
-- the first string buffer (0139200 is one GetMapName call and nothing else).
Gen3Commands.SPECIALS[281] = function(ctx)
  local data = ctx.game and ctx.game.data
  local sections = (data and data.constants or {}).gen3MapSections or {}
  local sec = math.floor(tonumber(getVar(ctx.save, 0x4026)) or 0)
  local name = sections[sec]
  if type(name) == "string" and ctx.game then
    ctx.game.stringBuffers = ctx.game.stringBuffers or {}
    ctx.game.stringBuffers[1] = name
  end
end

-- ---------------------------------------------------------------------------
-- 72 / 128 / 338: THE NAME RATER, and the three separate ways he says no.
--
-- The man on Slateport's second floor asks three questions before he will
-- change a nickname, and Emerald spends a special on each rather than one on
-- all three, because each is asked at a different point in his script and
-- prints a different line.
--
--   72  IsLeadMonNicknamedOrNotEnglish (080EF8F8)
--         GetLeadMonIndex, then 080EF88C: read MON_DATA_NICKNAME(2) into
--         gStringVar1 and MON_DATA_LANGUAGE(3); if the language is not 2
--         (English) answer 1 straight away, and otherwise compare the
--         nickname against gSpeciesNames[MON_DATA_SPECIES(11)] -- eleven
--         bytes a name, at 083185C8 -- answering 1 when they differ.
--
--       So "nicknamed" is not a bit on the Pokemon: the cartridge keeps no
--       such bit.  It is the nickname failing to match the species name,
--       which is why a MUDKIP called MUDKIP counts as un-nicknamed and why
--       this port, which stores nil for an un-nicknamed mon, answers the
--       same question by asking whether that field is there at all.
--
--       THE LANGUAGE HALF HAS NO PORT EQUIVALENT.  A retail cartridge can
--       hold a Pokemon traded in from a Japanese game and the rater refuses
--       to touch it; nothing in this port ever produces a mon of another
--       language, so that branch is unreachable rather than unimplemented.
--
--   128 IsMonOTIDNotPlayers (080EFF9C)
--         GetPlayerTrainerId() against GetMonData(party[VAR_0x8004],
--         MON_DATA_OT_ID(1)).  The id, not the name -- two players both
--         called MAY are exactly the case this compare exists to separate.
--
--   338 MonOTNameNotPlayer (08139770)
--         MON_DATA_LANGUAGE(3) first again, then MON_DATA_OT_NAME(7) into
--         gStringVar1 and StringCompare against saveBlock2's playerName.
--
-- 128 and 338 both read the party slot out of VAR_0x8004, which the rater's
-- script fills from the party menu he opens; 72 reads the LEAD, because it
-- is asked before the menu, on the way in.
local function raterMon(ctx)
  local slot = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  return ((ctx.save or {}).party or {})[slot + 1]
end

Gen3Commands.SPECIALS[72] = function(ctx)
  local lead = Gen3Commands.leadMon(ctx)
  if not lead then return 0 end
  local nick = lead.nickname
  if nick == nil or nick == "" then return 0 end
  local data = ctx.game and ctx.game.data
  local def = data and data.pokemon and data.pokemon[lead.species]
  local name = def and def.name
  -- no species name to compare against: a stored nickname is a nickname
  if not name then return 1 end
  return (nick ~= name) and 1 or 0
end

Gen3Commands.SPECIALS[128] = function(ctx)
  local mon = raterMon(ctx)
  if not mon then return 0 end
  local player = ((ctx.save or {}).player) or {}
  local mine = tonumber(player.trainerId or player.id)
  local theirs = tonumber(mon.otId)
  -- a mon with no id recorded is one this save made: saves from before
  -- OT stamping are backfilled with the player's on load, and until then
  -- the honest answer is "yours"
  if mine == nil or theirs == nil then return 0 end
  return (theirs ~= mine) and 1 or 0
end

Gen3Commands.SPECIALS[338] = function(ctx)
  local mon = raterMon(ctx)
  if not mon then return 0 end
  local player = ((ctx.save or {}).player) or {}
  if mon.ot == nil or player.name == nil then return 0 end
  return (mon.ot ~= player.name) and 1 or 0
end

-- ---------------------------------------------------------------------------
-- 343: SetChampionSaveWarp -- seven instructions and a whole behaviour.
--
--     ldr r0,=0x03005d90 ; ldr r2,[r0] ; ldrb r1,[r2,#9]
--     mov r0,#128 ; orr r0,r1 ; strb r0,[r2,#9] ; bx lr
--
-- saveBlock2 byte 9 is specialSaveWarpFlags and bit 7 is CHAMPION_SAVEWARP.
-- The Hall of Fame script sets it and then saves, so the save on the cart
-- records a player standing in the Hall of Fame -- and the NEXT continue
-- reads the bit, clears it, and puts the player in their own bedroom
-- instead.  That is why beating the Elite Four and resuming wakes you up at
-- home rather than back at the Pokemon League with nowhere to walk.
--
-- The bit alone would be a fact nothing reads, so the continue half is in
-- SaveData/Game with it (SaveData.setChampionSaveWarp and
-- SaveData.applyChampionSaveWarp); this special is only the setting of it.
Gen3Commands.SPECIALS[343] = function(ctx)
  local save = ctx.save
  if not save then return end
  require("src.core.SaveData").setChampionSaveWarp(save)
end

-- ---------------------------------------------------------------------------
-- 412: SetMirageTowerVisibility -- the coin flip Route 111 makes on entry.
--
-- 081BE79C, and it is a coin flip in the plainest sense:
--
--     if VarGet($40CB) ~= 0    -> FlagClear($14E) and stop
--     visible = Random() & 1
--     if FlagGet($9D) == TRUE  -> visible = TRUE
--     visible ? FlagSet($14E) + 081BE6B8 : FlagClear($14E)
--
-- $14E (334) is the flag every Mirage Tower object event on Route 111 hangs
-- its own visibility on, so setting it IS the tower appearing; the port's
-- flag-object sync is what makes that happen on the map already standing,
-- which is why this goes through Commands.set_flag rather than writing the
-- table directly.
--
-- $40CB is the tower's own progress var: once the player has been inside and
-- the thing has crumbled, the roll stops being made and the answer is always
-- "gone".  $9D is the override that pins it visible for the scripted visit.
--
-- 081BE6B8 is the shimmer -- a blend pulse it only starts when the player is
-- standing on Route 111's layout, purely so the tower fades in rather than
-- popping.  Cosmetic, and not ported.
local GEN3_MIRAGE_TOWER = { var = 0x40CB, visible = 334, forced = 157 }

Gen3Commands.SPECIALS[412] = function(ctx)
  local save = ctx.save
  if not save then return end
  save.flags = save.flags or {}
  local key = Gen3Commands.flagKey(GEN3_MIRAGE_TOWER.visible)
  if math.floor(tonumber(getVar(save, GEN3_MIRAGE_TOWER.var)) or 0) ~= 0 then
    Commands.clear_flag(ctx, key)
    return
  end
  local shown = (math.random(0, 1) == 1)
  if save.flags[Gen3Commands.flagKey(GEN3_MIRAGE_TOWER.forced)] == true then
    shown = true
  end
  if shown then Commands.set_flag(ctx, key) else Commands.clear_flag(ctx, key) end
end

-- ---------------------------------------------------------------------------
-- 428: IsPokemonJumpSpeciesInParty -- the rope-skipping minigame's doorman.
--
-- 0802C920 walks the six party slots, and for each one that has a species
-- (MON_DATA_SANITY_HAS_SPECIES, 5) it reads MON_DATA_SPECIES2 (65) -- the
-- reading that answers EGG for an egg, which is how eggs are turned away
-- without a second check -- and asks IsSpeciesInJumpTable (0802C908).  That
-- is a search of sPokemonJumpSpecies at 082FB464, a hundred rows of
-- {u16 species, u16 kind}, and it answers the INDEX, so the caller's test is
-- `>= 0` written as `mvn / lsr #31`.
--
-- The hundred is not a terminator count -- the table has no terminator -- it
-- is the loop's own bound, and it is the reason the roster travels as data:
-- extractPokemonJump reads those rows off the cartridge into
-- constants.gen3PokemonJump, kinds keyed by species id.
Gen3Commands.SPECIALS[428] = function(ctx)
  local data = ctx.game and ctx.game.data
  local record = data and data.constants and data.constants.gen3PokemonJump
  local kinds = record and record.kinds
  if type(kinds) ~= "table" then
    Logger.warn("gen3: this dataset has no Pokemon Jump roster, so the "
                .. "minigame turns every party away")
    return 0
  end
  local Party = require("src.pokemon.Party")
  for _, mon in ipairs((ctx.save or {}).party or {}) do
    if mon and mon.species and kinds[mon.species] ~= nil
       and not Party.isEgg(mon) then
      return 1
    end
  end
  return 0
end


-- ---------------------------------------------------------------------------
-- 487 / 488: "BOX WAS FULL", and how two specials say it between them.
--
--   487 GetPCBoxToSendMon (0813B210) is three instructions -- a byte read at
--       0203AB6F -- and that byte is written in exactly one place: the top of
--       SendMonToPC, from VarGet($4036).  So it holds where the LAST send
--       went, captured a moment before this one moves it on.
--
--   488 ShouldShowBoxWasFullMessage (0813B21C):
--
--           if FlagGet($8D7)                     -> 0
--           if StorageGetCurrentBox() == VarGet($4036) -> 0
--           FlagSet($8D7) ; return 1
--
--       -- the box the player is looking at against the box the mon actually
--       landed in, latched so the line prints once.
--
-- Neither special moves a Pokemon.  Boxes.deposit does that, and it is what
-- writes the two facts (see recordGen3Send there); these read them back.
Gen3Commands.SPECIALS[487] = function(ctx)
  local save = ctx.save or {}
  local was = tonumber(save.gen3PcBoxToSendMon)
  if was then return math.floor(was) end
  -- nothing has been sent this session: the cartridge's byte is whatever
  -- $4036 last said, which is the same answer read the long way
  return math.floor(tonumber(getVar(save, 0x4036)) or 0)
end

Gen3Commands.SPECIALS[488] = function(ctx)
  local save = ctx.save
  if not save then return 0 end
  local Boxes = require("src.pokemon.Boxes")
  local key = Boxes.GEN3_BOX_FULL_FLAG
  save.flags = save.flags or {}
  if save.flags[key] == true then return 0 end
  local current = math.floor(tonumber(save.currentBox) or 1) - 1
  local sent = math.floor(tonumber(getVar(save, Boxes.GEN3_BOX_SENT_VAR)) or 0)
  if current == sent then return 0 end
  Commands.set_flag(ctx, key)
  return 1
end


-- ---------------------------------------------------------------------------
-- 414: BufferTMHMMoveName -- what a TM teaches, in the first string buffer.
--
-- 081398C0 is a range test and a lookup: `(VAR_0x8004 - 0x121) > 57` refuses
-- anything that is not one of the fifty-eight machines -- ITEM_TM01 is 0x121
-- and HM08 is fifty-seven above it -- and then it puts
-- gMoveNames[ItemIdToBattleMoveId(VAR_0x8004)] in gStringVar1.
--
-- The port does not need the item NUMBER for this: extractMachines already
-- hangs a `machine` record off every TM and HM item ({kind, number, move}),
-- so the same question is asked of the item the var names.
Gen3Commands.SPECIALS[414] = function(ctx)
  local data = ctx.game and ctx.game.data
  local id = itemIdFor(data, getVar(ctx.save, 0x8004))
  local def = id and data and data.items and data.items[id]
  local machine = def and def.machine
  local move = machine and data.moves and data.moves[machine.move]
  if not move then
    -- the cartridge answers 0 for an item that is not a machine, and the
    -- script's next line reads the buffer, so leaving it stale would put the
    -- LAST machine's name in this one's sentence
    buffer(ctx, 1, "")
    return 0
  end
  buffer(ctx, 1, move.name or machine.move)
  return 1
end

-- ---------------------------------------------------------------------------
-- 434: BufferVarsForIVRater -- the man in Mossdeep who judges a Pokemon.
--
-- 08139D98 reads the six individual values off party[VAR_0x8004] --
-- MON_DATA 39 through 44, which is HP, ATTACK, DEFENSE, SPEED, SP.ATK,
-- SP.DEF, the same order this port keeps them in -- and answers three vars,
-- not one:
--
--     VAR_0x8005 = the six added together     (his overall verdict)
--     VAR_0x8006 = WHICH of them is highest   (the stat he names)
--     VAR_0x8007 = that value                 (how emphatic he is about it)
--
-- and the tie is broken by a coin flip: the walk keeps the running best and
-- replaces it on a draw only when `Random() & 1`.  So asking him twice about
-- a Pokemon with two equal-best stats can name either one, and that is the
-- cartridge's behaviour rather than a rounding of it.
local GEN3_IV_ORDER_FALLBACK = { "hp", "attack", "defense", "speed",
                                 "spatk", "spdef" }

Gen3Commands.SPECIALS[434] = function(ctx)
  local save = ctx.save
  local slot = math.floor(tonumber(getVar(save, 0x8004)) or 0)
  local mon = ((save or {}).party or {})[slot + 1]
  local ivs = mon and mon.ivs
  if type(ivs) ~= "table" then
    setVar(save, 0x8005, 0)
    setVar(save, 0x8006, 0)
    setVar(save, 0x8007, 0)
    return 0
  end
  local okOrder, Stats = pcall(require, "src.pokemon.Stats")
  local order = (okOrder and Stats.ORDER_GEN3) or GEN3_IV_ORDER_FALLBACK
  local total, best, bestAt = 0, -1, 0
  for i, key in ipairs(order) do
    local value = math.floor(tonumber(ivs[key]) or 0)
    total = total + value
    if value > best then
      best, bestAt = value, i - 1
    elseif value == best and math.random(0, 1) == 1 then
      bestAt = i - 1
    end
  end
  setVar(save, 0x8005, total)
  setVar(save, 0x8006, bestAt)
  setVar(save, 0x8007, best)
  return total
end

-- ---------------------------------------------------------------------------
-- 454: ShowNatureGirlMessage -- and the reason her lines are a rip, not a
-- table of twenty-five sentences written out.
--
-- 0813A7B8: a slot over five means the lead, then GetNature of that Pokemon
-- indexes sNatureGirlMessages and shows the line.  Twenty-five pointers, ten
-- distinct lines -- see extractNatureGirl, which is where the count is
-- argued -- and the port had none of them, so she said nothing at all.
Gen3Commands.SPECIALS[454] = function(ctx)
  local save = ctx.save
  local slot = math.floor(tonumber(getVar(save, 0x8004)) or 0)
  if slot > 5 then
    slot = 0
    setVar(save, 0x8004, 0)
  end
  local mon = ((save or {}).party or {})[slot + 1]
  local data = ctx.game and ctx.game.data
  local record = data and data.constants and data.constants.gen3NatureGirl
  local lines = record and record.lines
  if type(lines) ~= "table" then
    Logger.warn("gen3: this dataset has no nature girl lines, so she is "
                .. "left silent")
    return 0
  end
  -- GetNature is `personality % 25` and nothing else, so that is the reading
  -- when the Pokemon carries a personality value.  A mon built without one --
  -- a test's, or an older save's -- still has its nature by name, and
  -- natureOrder is the same twenty-five in the same order.
  local index = nil
  if mon and tonumber(mon.personality) then
    index = math.floor(tonumber(mon.personality)) % 25
  else
    local natures = (data.constants or {}).natureOrder
    if type(natures) == "table" and mon and mon.nature then
      for i, id in ipairs(natures) do
        if id == mon.nature then index = i - 1 break end
      end
    end
  end
  local line = lines[((index or 0) % #lines) + 1]
  if line then Commands.show_text(ctx, line) end
  return 1
end

-- ---------------------------------------------------------------------------
-- 486: ChangeBoxPokemonNickname -- 161's twin, aimed at the PC.
--
-- 080EFEC4 opens the same keyboard on GetBoxedMonPtr(gSpecialVar_MonBoxId,
-- gSpecialVar_MonBoxPos) -- the box and slot SendMonToPC wrote the moment it
-- found room -- which is why this one is asked right after "it was sent to
-- BOX n" and not from the storage screen.  Boxes.deposit records both.
Gen3Commands.SPECIALS[486] = function(ctx)
  local game, runner, save = ctx.game, ctx.runner, ctx.save
  local Boxes = require("src.pokemon.Boxes")
  local boxes = save and Boxes.ensure(save)
  local box = boxes and boxes[math.floor(tonumber(save.gen3MonBox) or -1) + 1]
  local mon = box and box[math.floor(tonumber(save.gen3MonBoxPos) or -1) + 1]
  if not mon then
    Logger.warn("gen3: special 486 was asked to name box %s slot %s, and "
                .. "there is no Pokemon there",
                tostring(save and save.gen3MonBox),
                tostring(save and save.gen3MonBoxPos))
    return
  end
  if not (game and game.stack) then return end
  local Screens = require("src.ui.Screens")
  Screens.push(game, "NamingScreen", {
    title = Strings("NICKNAME?"),
    maxLen = 10,
    default = mon.nickname,
    onDone = function(nick)
      if nick and #nick > 0 then mon.nickname = nick end
      if runner then runner:resume() end
    end,
  })
  if runner then runner:yield() end
end

-- ---------------------------------------------------------------------------
-- 520: ResetHealLocationFromDewford -- one `if` that stops a stranding.
--
--     if saveBlock1->lastHealLocation is (group 0, map 11)
--         SetLastHealLocationWarp(3)
--
-- (group 0, map 11) is DEWFORD TOWN and heal location 3 is PETALBURG CITY.
-- Dewford is reached only by boat, so a save whose blackout point is the
-- island and whose ferry is no longer running has nowhere to wake up; the
-- script that leaves Dewford for good runs this on the way out.
--
-- This port keeps the same fact as an INDEX -- `setrespawn` stores it and
-- OverworldState:healPoint resolves it against the extracted sHealLocations
-- -- so the compare is done on the map that index names rather than on a
-- warp record the port does not keep.
local GEN3_DEWFORD = { group = 0, number = 11 }
local GEN3_HEAL_AFTER_DEWFORD = 3

Gen3Commands.SPECIALS[520] = function(ctx)
  local save = ctx.save
  local data = ctx.game and ctx.game.data
  local list = data and data.constants and data.constants.gen3HealLocations
  if not (save and type(list) == "table") then return end
  local row = list[math.floor(tonumber(save.gen3RespawnIndex) or 0)]
  if not row then return end
  if row.map ~= mapKey(GEN3_DEWFORD.group, GEN3_DEWFORD.number) then return end
  save.gen3RespawnIndex = GEN3_HEAL_AFTER_DEWFORD
  local moved = list[GEN3_HEAL_AFTER_DEWFORD]
  if moved then
    save.lastHeal = { map = moved.map, x = moved.x, y = moved.y }
  end
end


-- ---------------------------------------------------------------------------
-- THE POKéNAV TUTORIAL, AND THE LOOP IT USED TO BE.
--
-- Reported from play: "after the lab assistant gives me the pokenav and tells
-- me to call mr stone, i do so but after i exit he keeps asking me to please
-- select the pokenav and i cant get out of the loop".
--
-- TWO SPECIALS, AND ONLY ONE OF THEM OPENS THE POKéNAV.  Both were written as
-- "just show it", and that is what made the loop: the assistant's script is
--
--     "Please select the POKéNAV."
--     special 472          <- the START MENU, not the POKeNAV
--     waitstate
--     goto back to the top unless VAR_RESULT is 3
--
-- and 472 never wrote VAR_RESULT at all.  So whatever the last script left in
-- it came back, it was not 3, and the assistant asked again -- for ever, with
-- no way out, because the only exit from that script is picking the right row.
--
-- WHY THREE.  472 draws the eight-row START MENU with POKéNAV fourth --
-- POKéDEX, POKéMON, BAG, POKéNAV -- and answers the row you picked.  So three
-- is the POKéNAV's own index, and B answers 127 like every other menu here.
-- It draws all eight rows whether or not you can use them, because it is a
-- teaching prop and not the real menu; the labels are the cartridge's own,
-- out of the same record the real start menu reads.
--
-- 471 is the one that opens the POKéNAV, and it always was.
Gen3Commands.SPECIALS[471] = function(ctx)
  pushBlocking(ctx, "Gen3Pokenav")
end

Gen3Commands.POKENAV_TUTORIAL_ROW = 3

Gen3Commands.SPECIALS[472] = function(ctx)
  local data = ctx.game and ctx.game.data
  local record = (data and data.constants or {}).gen3StartMenu
  local labels = record and record.items
  if type(labels) ~= "table" or #labels == 0 then
    -- With no menu to show, ANSWER THE ROW THE SCRIPT IS WAITING FOR rather
    -- than leaving VAR_RESULT alone.  A dataset with no labels must not be a
    -- dataset where the tutorial cannot be finished.
    Logger.warn("gen3 pokenav tutorial: this dataset carries no start menu "
                .. "labels -- the row is answered so the tutorial can end")
    setVar(ctx.save, VAR_RESULT, Gen3Commands.POKENAV_TUTORIAL_ROW)
    return
  end
  local rows = {}
  for i, label in ipairs(labels) do
    -- the player's own name is the one row whose label is not a word
    rows[i] = tostring(label):gsub("{PLAYER}",
      tostring(((ctx.save or {}).player or {}).name or "PLAYER"))
  end
  -- ...AND A MENU THAT CANNOT BE SHOWN ANSWERS THE ROW TOO.  B answering 127
  -- is the cartridge's own behaviour and the script asking again is correct;
  -- a listPick that declines because there is no screen stack to push onto is
  -- NOT the player pressing B, and answering 127 for it would rebuild exactly
  -- the loop this special was written to end.
  if not (ctx.game and ctx.game.stack and ctx.runner) then
    Logger.warn("gen3 pokenav tutorial: there is no screen stack to show the "
                .. "menu on -- the row is answered so the tutorial can end")
    setVar(ctx.save, VAR_RESULT, Gen3Commands.POKENAV_TUTORIAL_ROW)
    return
  end
  local picked = Gen3Commands.listPick(ctx, rows, nil, #rows)
  setVar(ctx.save, VAR_RESULT,
         picked and (picked - 1) or Gen3Commands.SCROLL_MULTI_CANCEL)
end

-- ---------------------------------------------------------------------------
-- POKeBLOCKS
-- ---------------------------------------------------------------------------
local function pokeblocks()
  return require("src.inventory.Pokeblocks")
end

-- GetFirstFreePokeblockSlot: the LOWEST empty slot, or -1.  Zero-based,
-- because the script compares it against -1.
Gen3Commands.SPECIALS[163] = function(ctx)
  local data = ctx.game and ctx.game.data
  local slot = pokeblocks().firstFree(ctx.save, data)
  return slot and (slot - 1) or -1
end

-- GetPokeblockNameByMonNature: which colour of block the Pokemon in
-- VAR_0x8004 likes, buffered for the line that is about to print it.
Gen3Commands.SPECIALS[280] = function(ctx)
  local data = ctx.game and ctx.game.data
  local slot = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0) + 1
  local mon = (ctx.save.party or {})[slot]
  local colour, word = pokeblocks().favourite(data, mon and mon.nature)
  if word then
    ctx.save.buffers = ctx.save.buffers or {}
    ctx.save.buffers[1] = word .. " POKéBLOCK"
  end
  return colour or 0
end

-- ---------------------------------------------------------------------------
-- CONTESTS
--
-- Three script commands and a dozen specials, and between them they are the
-- whole of Hoenn's other half.  Every one of them was a stub: the lobby
-- receptionist took your entry, `startcontest` did nothing, and the results
-- script printed a standings table that had never been filled in.
--
-- THE STATE LIVES ON THE SAVE, not on the context, because the contest runs
-- across a screen push: the lobby script sets the category and the rank in
-- VAR_0x8011 and VAR_0x8010, `choosecontestmon` writes the party slot into
-- VAR_0x8004, `startcontest` runs the five appeal rounds, and the results
-- script -- a different script, on a different map -- reads what it left.
-- ---------------------------------------------------------------------------
local VAR_CONTEST_RANK = 0x8010
local VAR_CONTEST_CATEGORY = 0x8011

local function contestRun()
  return require("src.contest.ContestRun")
end

local function contestState(ctx)
  ctx.save.contest = ctx.save.contest or {}
  return ctx.save.contest
end
Gen3Commands.contestState = contestState

local function contestCategory(ctx)
  local data = ctx.game and ctx.game.data
  local r = (data and data.constants or {}).gen3Contests
  local list = (r and r.categories) or { "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH" }
  local n = math.floor(tonumber(getVar(ctx.save, VAR_CONTEST_CATEGORY)) or 0)
  return (list[n + 1] or list[1]):lower()
end

local function contestRank(ctx)
  return math.max(0, math.min(3,
    math.floor(tonumber(getVar(ctx.save, VAR_CONTEST_RANK)) or 0)))
end

-- `choosecontestmon`: the party, in pick-only mode, answering into VAR_0x8004
-- exactly as ChooseMonForMoveTutor does -- and 255 when you back out.
function Commands.g3_choose_contest_mon(ctx)
  local game, runner = ctx.game, ctx.runner
  local party = (ctx.save or {}).party or {}
  if not (game and game.stack and runner) then
    setVar(ctx.save, 0x8004, Gen3Commands.PARTY_NOTHING_CHOSEN)
    return
  end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then
    setVar(ctx.save, 0x8004, Gen3Commands.PARTY_NOTHING_CHOSEN)
    return
  end
  local picked
  local pushed = pcall(Screens.push, game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon; runner:resume() end,
  })
  if not pushed then
    setVar(ctx.save, 0x8004, Gen3Commands.PARTY_NOTHING_CHOSEN)
    return
  end
  runner:yield()
  local slot
  for i, mon in ipairs(party) do
    if mon == picked then slot = i - 1 break end
  end
  setVar(ctx.save, 0x8004, slot or Gen3Commands.PARTY_NOTHING_CHOSEN)
end

-- `startcontest`: the five appeal rounds, blocking, and the standings kept
-- for the results script that follows.
function Commands.g3_start_contest(ctx)
  local game = ctx.game
  local slot = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0) + 1
  local mon = (ctx.save.party or {})[slot]
  if not (game and mon) then
    Logger.warn("gen3 contest: no Pokemon in slot %d -- the contest is "
                  .. "skipped rather than raising", slot)
    return
  end
  local state = contestState(ctx)
  state.category = contestCategory(ctx)
  state.rank = contestRank(ctx)
  state.slot = slot
  pushBlocking(ctx, "Gen3Contest", {
    mon = mon,
    category = state.category,
    rank = state.rank,
    -- the nine gated opponents of each rank only appear after the Hall of
    -- Fame, which this port spells as the game-clear flag
    postGame = (ctx.save.flags or {})[Gen3Commands.flagKey(0x864)] == true,
    onResult = function(result)
      state.place = result.place
      state.total = result.total
      state.won = result.won
      state.artist = result.artist
      state.standings = {}
      state.conditions = {}
      state.names = {}
      for i, c in ipairs(result.run.contestants) do
        state.standings[i] = c.place
        state.conditions[i] = c.condition
        state.names[i] = c.mon and (c.mon.nickname or c.mon.species) or "?"
      end
    end,
  })
end

function Commands.g3_contest_results(ctx)
  -- The screen prints them on its own last page; this is what a script that
  -- asks for them separately gets, and it is the same numbers.
  local state = contestState(ctx)
  setVar(ctx.save, VAR_RESULT, state.place or 4)
end

function Commands.g3_contest_painting(ctx)
  local state = contestState(ctx)
  Logger.debug("gen3 contest: showing the %s painting",
               tostring(state.category))
end

-- 87 TryEnterContestMon.  Five answers, and TWO of them let you in: the
-- receptionist turns you away when your ribbon count is BELOW the rank (you
-- have not cleared the one under it), and lets you through both when it
-- matches and when you have already won here.
Gen3Commands.SPECIALS[87] = function(ctx)
  local slot = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0) + 1
  local mon = (ctx.save.party or {})[slot]
  local CR = contestRun()
  local answer = CR.eligibility(mon, contestCategory(ctx), contestRank(ctx))
  if CR.mayEnter(answer) then
    local state = contestState(ctx)
    state.category, state.rank, state.slot =
      contestCategory(ctx), contestRank(ctx), slot
  end
  return answer
end

-- 91 HasMonWonThisContestBefore
Gen3Commands.SPECIALS[91] = function(ctx)
  local slot = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0) + 1
  local mon = (ctx.save.party or {})[slot]
  local have = math.floor(tonumber(((mon or {}).ribbons or {})[contestCategory(ctx)]) or 0)
  return have > contestRank(ctx) and 1 or 0
end

-- 90 GetContestMonCondition and 85 GetContestMonConditionRanking, both
-- answering about the contestant named in VAR_0x8006 and both writing their
-- answer into VAR_0x8004 rather than returning it.
Gen3Commands.SPECIALS[90] = function(ctx)
  local state = contestState(ctx)
  local who = math.floor(tonumber(getVar(ctx.save, 0x8006)) or 0) + 1
  setVar(ctx.save, 0x8004, (state.conditions or {})[who] or 0)
end

Gen3Commands.SPECIALS[85] = function(ctx)
  local state = contestState(ctx)
  local who = math.floor(tonumber(getVar(ctx.save, 0x8006)) or 0) + 1
  local mine = (state.conditions or {})[who] or 0
  local rank = 0
  for _, v in pairs(state.conditions or {}) do
    if mine < v then rank = rank + 1 end
  end
  setVar(ctx.save, 0x8004, rank)
end

-- 88 GetContestantNamesAtRank: the name of whoever placed VAR_0x8006-th.
Gen3Commands.SPECIALS[88] = function(ctx)
  local state = contestState(ctx)
  local want = math.floor(tonumber(getVar(ctx.save, 0x8006)) or 0) + 1
  for i, place in pairs(state.standings or {}) do
    if place == want then
      ctx.save.buffers = ctx.save.buffers or {}
      ctx.save.buffers[1] = tostring((state.names or {})[i] or "")
      return
    end
  end
end

-- 79 GetContestWinnerId
Gen3Commands.SPECIALS[79] = function(ctx)
  local state = contestState(ctx)
  for i, place in pairs(state.standings or {}) do
    if place == 1 then setVar(ctx.save, 0x8005, i - 1) return end
  end
  setVar(ctx.save, 0x8005, 0)
end

-- 92 GiveMonContestRibbon.  First place only, and the counter advances by one
-- and never past four.  The screen already awarded it when the run ended, so
-- this is idempotent by construction -- Contest.giveContestRibbon refuses a
-- second advance at the same rank.
Gen3Commands.SPECIALS[92] = function(ctx)
  local state = contestState(ctx)
  if not state.won then return end
  local mon = (ctx.save.party or {})[state.slot or 1]
  require("src.pokemon.Contest")
    .giveContestRibbon(mon, state.category or "cool", state.rank or 0)
end

-- 94 GiveMonArtistRibbon and 137 ShouldReadyContestArtist share one gate:
-- Master Rank, first place, and more than 799 points.
Gen3Commands.SPECIALS[94] = function(ctx)
  local state = contestState(ctx)
  if not state.artist then return end
  local mon = (ctx.save.party or {})[state.slot or 1]
  local ribbons = require("src.pokemon.Contest").ribbons(mon)
  if ribbons then ribbons.artist = true end
end

Gen3Commands.SPECIALS[137] = function(ctx)
  setVar(ctx.save, 0x8004, contestState(ctx).artist and 1 or 0)
end

-- 138 SaveMuseumContestPainting / 139 DoesContestCategoryHaveMuseumPainting /
-- 140 CountPlayerMuseumPaintings.  The museum keeps one painting per
-- category, indexed by the category and nothing else.
local function paintings(ctx)
  ctx.save.museum = ctx.save.museum or {}
  return ctx.save.museum
end

Gen3Commands.SPECIALS[138] = function(ctx)
  local state = contestState(ctx)
  local mon = (ctx.save.party or {})[state.slot or 1]
  if not mon then return end
  paintings(ctx)[state.category or "cool"] = {
    species = mon.species,
    nickname = mon.nickname,
    rank = state.rank,
    trainer = (ctx.save.player or {}).name,
  }
end

Gen3Commands.SPECIALS[139] = function(ctx)
  setVar(ctx.save, 0x8004,
         paintings(ctx)[contestCategory(ctx)] and 1 or 0)
end

Gen3Commands.SPECIALS[140] = function(ctx)
  local n = 0
  for _ in pairs(paintings(ctx)) do n = n + 1 end
  return n
end

-- 342 GenerateContestRand: one number the whole contest shares, so every
-- script that asks gets the same answer.
Gen3Commands.SPECIALS[342] = function(ctx)
  local state = contestState(ctx)
  state.rand = state.rand or love.math.random(0, 65535)
  return state.rand
end

-- ---------------------------------------------------------------------------
-- 164 DoBerryBlending, 211 OpenPokeblockCaseOnFeeder, and the Contest Lady.
--
-- 164 is the machine itself: the script has already put the number of
-- participants in VAR_0x8004 (StartBlender takes 1, 2 or 3 and blends with
-- two, three or four), and the player picks the berry they are throwing in.
-- The NPCs' berries are the cartridge's own -- it hands each of them one from
-- the set the machine's owner carries -- and this picks them at random from
-- the berries the player is not using, which keeps the RING SUBTRACTION
-- meaningful: four of the same berry really does come out black.
-- ---------------------------------------------------------------------------
Gen3Commands.SPECIALS[164] = function(ctx)
  local game, runner = ctx.game, ctx.runner
  local PB = require("src.inventory.Pokeblocks")
  if not (game and game.stack and runner) then return end
  local players = math.max(2, math.min(4,
    math.floor(tonumber(getVar(ctx.save, 0x8004)) or 1) + 1))

  -- WHICH BERRY.  The bag, in its BERRIES pocket, answering with an item.
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return end
  local chosen
  local pushed = pcall(Screens.push, game, "BagMenu", {
    pick = true,
    pocket = "BERRY",
    onCancel = function() runner:resume() end,
    onPick = function(id) chosen = id; runner:resume() end,
  })
  if not pushed then return end
  runner:yield()
  if not chosen then return end

  local mine = PB.berryFlavours(game.data, chosen)
  if not mine then
    Logger.warn("gen3 blender: %s is not a berry -- nothing was blended",
                tostring(chosen))
    return
  end
  require("src.inventory.Bag").remove(ctx.save, chosen, 1)

  -- the other participants' berries, drawn from the whole table so the
  -- flavours differ -- which is what the ring subtraction needs
  local pool = {}
  for id, def in pairs(game.data.items or {}) do
    local flavours = PB.berryFlavours(game.data, id)
    if flavours and id ~= chosen then pool[#pool + 1] = flavours end
  end
  local berries = { mine }
  for _ = 2, players do
    if #pool == 0 then break end
    berries[#berries + 1] = table.remove(pool, love.math.random(1, #pool))
  end

  pushBlocking(ctx, "Gen3BerryBlender", { berries = berries })
end

Gen3Commands.SPECIALS[211] = function(ctx)
  pushBlocking(ctx, "Gen3PokeblockCase", {})
end

-- ---------------------------------------------------------------------------
-- THE LILYCOVE CONTEST LADY, specials 398-405.
--
-- She asks for a Pokeblock, remembers the best flavour anybody has ever
-- brought her in HER category, and goes on the air once five have been given.
-- The category is rolled when she resets, which is why she is asking about
-- something different the next time round.
-- ---------------------------------------------------------------------------
local function contestLady(ctx)
  local save = ctx.save
  if type(save.contestLady) ~= "table" then
    local data = ctx.game and ctx.game.data
    local r = (data and data.constants or {}).gen3Contests
    local categories = (r and r.categories) or { "COOL" }
    save.contestLady = {
      category = math.floor(love.math.random(1, #categories)),
      good = 0, given = 0, best = 0,
    }
  end
  return save.contestLady
end

local function ladyCategoryKey(ctx)
  local data = ctx.game and ctx.game.data
  local r = (data and data.constants or {}).gen3Contests
  local list = (r and r.categories) or { "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH" }
  return (list[contestLady(ctx).category] or list[1]):lower()
end

-- 398 ShouldContestLadyShowGoOnAir
Gen3Commands.SPECIALS[398] = function(ctx)
  local lady = contestLady(ctx)
  return (lady.good > 4 or lady.given > 4) and 1 or 0
end

-- 399: has she already been spoken to today
Gen3Commands.SPECIALS[399] = function(ctx)
  return contestLady(ctx).spoken and 1 or 0
end

-- 400 Script_BufferContestLadyCategoryAndMonName
Gen3Commands.SPECIALS[400] = function(ctx)
  local data = ctx.game and ctx.game.data
  local r = (data and data.constants or {}).gen3Contests
  local lady = contestLady(ctx)
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[1] = (r and r.lady and r.lady.words
                         and r.lady.words[lady.category]) or ""
  ctx.save.buffers[2] = (r and r.lady and r.lady.mons
                         and r.lady.mons[lady.category]) or ""
end

-- 401 OpenPokeblockCaseForContestLady -- she takes one, and which flavour it
-- carries in HER category is the only thing she remembers about it
Gen3Commands.SPECIALS[401] = function(ctx)
  local lady = contestLady(ctx)
  local key = ladyCategoryKey(ctx)
  local FLAVOUR = { cool = "spicy", beauty = "dry", cute = "sweet",
                    smart = "bitter", tough = "sour" }
  pushBlocking(ctx, "Gen3PokeblockCase", {
    pickOnly = true,
    onPick = function(slot, block)
      local PB = require("src.inventory.Pokeblocks")
      PB.remove(ctx.save, slot)
      local v = math.floor(tonumber(block[FLAVOUR[key]]) or 0)
      if v ~= 0 then
        if v >= (lady.best or 0) then lady.best = v end
        lady.good = (lady.good or 0) + 1
      else
        lady.given = (lady.given or 0) + 1
      end
    end,
  })
end

-- 402 SetContestLadyGivenPokeblock
Gen3Commands.SPECIALS[402] = function(ctx)
  contestLady(ctx).spoken = true
end

-- 403 GetContestLadyMonSpecies
Gen3Commands.SPECIALS[403] = function(ctx)
  local data = ctx.game and ctx.game.data
  local r = (data and data.constants or {}).gen3Contests
  local lady = contestLady(ctx)
  local species = r and r.lady and r.lady.species and r.lady.species[lady.category]
  local order = (data and data.constants or {}).speciesOrder or {}
  local number = 0
  for i, id in pairs(order) do if id == species then number = i break end end
  setVar(ctx.save, 0x8005, number)
end

-- 404 GetContestLadyCategory
Gen3Commands.SPECIALS[404] = function(ctx)
  return contestLady(ctx).category - 1
end

-- 405 PutLilycoveContestLadyShowOnTheAir: she resets, and picks a new
-- category on her way out.
Gen3Commands.SPECIALS[405] = function(ctx)
  local data = ctx.game and ctx.game.data
  local r = (data and data.constants or {}).gen3Contests
  local categories = (r and r.categories) or { "COOL" }
  local lady = contestLady(ctx)
  lady.onAir = { good = lady.good, best = lady.best }
  lady.good, lady.given, lady.best, lady.spoken = 0, 0, 0, nil
  lady.category = math.floor(love.math.random(1, #categories))
end

-- ---------------------------------------------------------------------------
-- THE MAUVILLE OLD MAN, and the decoration TRADER (100, and 116 to 121).
--
-- The house east of Mauville's gym holds one of five men, and which one it is
-- was decided the moment the save was rolled: `(trainer id % 10) / 2` indexes
-- SetMauvilleOldMan's five-armed jump table -- Bard, Hipster, TRADER,
-- Storyteller, Giddy.  His script opens
--
--     special 100 / copyvar 0x8000, VAR_RESULT
--     compare 0x8000, 0 / goto_if eq <bard>       ... and so on to four
--
-- and with 100 unimplemented VAR_RESULT still held whatever the LAST script
-- put there, so the house dispatched on a stale number: the man in it stood
-- silent, or answered as somebody he was not.
--
-- WHY IT IS COMPUTED RATHER THAN STORED AT NEW GAME.  The cartridge rolls it
-- once and writes the answer into SaveBlock1; this derives it from the
-- trainer id the first time anybody asks.  Those are the same answer -- the
-- id never changes -- and doing it on demand is what lets a save made before
-- this existed find its man too, instead of defaulting everybody to the Bard.
-- A save imported from a real cartridge brings the block with it and this
-- never runs.
--
-- THE TRADER, then.  He carries four decorations that belonged to four other
-- people, will swap any one of them for one of yours, and writes YOUR name
-- against whatever you hand him -- so the next person to meet him is told it
-- was yours.  His script (S028E4D4 and the four it reaches) is:
--
--     special 100 / ... / goto <trader>
--     "Want to trade decorations with me?" / YES/NO
--     special 117            -- have we traded before
--     special 116 / waitstate
--     compare 0x8004, 0      -- nothing to show
--     compare 0x8004, 65535  -- backed out
--     "That decorative item once belonged to {STR_VAR_1}." / YES/NO
--     special 118            -- you own nothing to give
--     "Okay, pick the decoration that you'll trade to me."
--     special 120 / waitstate
--     compare 0x8006, 0 / compare 0x8006, 65535
--     special 119            -- his would not fit in your PC
--     "so we'll trade my {STR_VAR_3} for your {STR_VAR_2}?" / YES/NO
--     special 121            -- the swap
--
-- Every var in that listing is the cartridge's own: 0x8004 is HIS decoration,
-- 0x8005 the slot it came out of, 0x8006 YOURS, and the three string buffers
-- are filled in the order the lines read them.  0xFFFF is the cancel row,
-- which is why backing out of either list has its own arm.
-- ---------------------------------------------------------------------------

local MAUVILLE_CANCEL = 0xFFFF

local function mauvilleRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  local r = data and data.constants and data.constants.gen3MauvilleMan
  return (type(r) == "table" and type(r.trader) == "table") and r or nil
end

-- Who lives in the house, and what he is carrying.  Seeded on first ask; see
-- the header for why that is the same answer as seeding it at new game.
function Gen3Commands.mauvilleMan(ctx)
  local save = ctx and ctx.save
  local record = mauvilleRecord(ctx)
  if not (save and record) then return nil end
  local state = save.gen3MauvilleMan
  if type(state) ~= "table" then
    local pick = record.pick or {}
    local modulus = math.floor(tonumber(pick.modulus) or 10)
    local divisor = math.floor(tonumber(pick.divisor) or 2)
    local id = math.floor(tonumber((save.player or {}).id) or 0)
    if modulus < 1 then modulus = 1 end
    if divisor < 1 then divisor = 1 end
    state = { man = math.floor((id % modulus) / divisor) }
    save.gen3MauvilleMan = state
  end
  if state.man == record.trader.man and type(state.trader) ~= "table" then
    local trader = { traded = false, decorations = {}, names = {} }
    for i, id in ipairs(record.trader.decorations or {}) do
      trader.decorations[i] = id
    end
    for i, name in ipairs(record.trader.names or {}) do
      trader.names[i] = name
    end
    state.trader = trader
  end
  return state
end

-- His four slots, or nothing at all when the house holds somebody else.
local function traderState(ctx)
  local state = Gen3Commands.mauvilleMan(ctx)
  return state and state.trader or nil
end

-- 100: Script_GetCurrentMauvilleMan.
Gen3Commands.SPECIALS[100] = function(ctx)
  local state = Gen3Commands.mauvilleMan(ctx)
  return state and state.man or 0
end

-- 107: SetMauvilleOldManObjEventGfx.  His map object is graphics id 240 with
-- varSprite 0 -- the sprite comes out of a VARIABLE -- so with this dead the
-- var held zero and the house drew sprite zero instead of an old man.  All
-- five men look the same, which is why one special serves the lot.
Gen3Commands.SPECIALS[107] = function(ctx)
  local record = mauvilleRecord(ctx)
  local gfx = record and record.gfx
  if not (gfx and gfx.var and gfx.graphicsId) then return end
  setVar(ctx.save, gfx.var, gfx.graphicsId)
end

-- 117: GetTraderTradedFlag.  One means he has already taken something of
-- yours, which is the arm that says "speak up" instead of introducing
-- himself again.
Gen3Commands.SPECIALS[117] = function(ctx)
  local trader = traderState(ctx)
  return (trader and trader.traded) and 1 or 0
end

-- 118: DoesPlayerHaveNoDecorations.  The cartridge walks all eight categories
-- and answers ONE only if every one of them is empty -- so the refusal is
-- "you own nothing at all", not "nothing in this category".
Gen3Commands.SPECIALS[118] = function(ctx)
  local Decor = require("src.world.Gen3Decorations")
  local data = ctx.game and ctx.game.data
  return (#Decor.held(data, ctx.save) == 0) and 1 or 0
end

-- 119: IsDecorationCategoryFull.  His decoration has to land somewhere, and the
-- cartridge only checks when the two are in DIFFERENT categories -- yours
-- leaves a slot behind that his can take, so a swap within one category can
-- never fail.  STR_VAR_1 names the category that is full.
Gen3Commands.SPECIALS[119] = function(ctx)
  local Decor = require("src.world.Gen3Decorations")
  local data = ctx.game and ctx.game.data
  local his = Decor.categoryOf(data, getVar(ctx.save, 0x8004))
  local yours = Decor.categoryOf(data, getVar(ctx.save, 0x8006))
  if not (his and yours) or his == yours then return 0 end
  if Decor.firstEmptySlot(data, ctx.save, his) then return 0 end
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[1] = Decor.name(data, getVar(ctx.save, 0x8004)) or ""
  return 1
end

-- 116: TraderMenuGetDecoration -- his four, by name.  The name reads
-- backwards until you read the code: this is the one you GET a decoration
-- from, and 120 is the one that shows yours.  0x8004 takes the
-- decoration, 0x8005 the SLOT it came out of (121 needs that to write your
-- name into the right one) and STR_VAR_1 the person it belonged to.
Gen3Commands.SPECIALS[116] = function(ctx)
  local Decor = require("src.world.Gen3Decorations")
  local data = ctx.game and ctx.game.data
  local trader = traderState(ctx)
  if not trader then
    setVar(ctx.save, 0x8004, 0)
    return
  end
  local labels, ids = {}, {}
  for slot, id in ipairs(trader.decorations) do
    labels[#labels + 1] = Decor.name(data, id) or tostring(id)
    ids[#ids + 1] = { id = id, slot = slot }
  end
  if #labels == 0 then
    setVar(ctx.save, 0x8004, 0)
    return
  end
  local picked = Gen3Commands.listPick(ctx, labels, Strings("CANCEL"))
  local row = picked and ids[picked]
  if not row then
    setVar(ctx.save, 0x8004, MAUVILLE_CANCEL)
    return
  end
  setVar(ctx.save, 0x8004, row.id)
  setVar(ctx.save, 0x8005, row.slot - 1)
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[1] = tostring(trader.names[row.slot] or "")
end

-- 120: TraderShowDecorationMenu -- yours, by name.  0x8006 takes it, and both
-- names are buffered here because the line that follows reads them together:
-- STR_VAR_2 is yours and STR_VAR_3 is his.
Gen3Commands.SPECIALS[120] = function(ctx)
  local Decor = require("src.world.Gen3Decorations")
  local data = ctx.game and ctx.game.data
  local labels, ids = {}, {}
  for _, own in ipairs(Decor.held(data, ctx.save)) do
    labels[#labels + 1] = own.count > 1
                          and ("%s x%d"):format(own.def.name, own.count)
                          or own.def.name
    ids[#ids + 1] = own.def.id
  end
  if #labels == 0 then
    setVar(ctx.save, 0x8006, 0)
    return
  end
  local picked = Gen3Commands.listPick(ctx, labels, Strings("CANCEL"))
  local id = picked and ids[picked]
  if not id then
    setVar(ctx.save, 0x8006, MAUVILLE_CANCEL)
    return
  end
  setVar(ctx.save, 0x8006, id)
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[2] = Decor.name(data, id) or ""
  ctx.save.buffers[3] = Decor.name(data, getVar(ctx.save, 0x8004)) or ""
end

-- 121: TraderDoDecorationTrade.  Yours leaves the PC, his arrives in it, and
-- the slot he took it out of now holds yours under YOUR name -- which is the
-- whole point of him, and why the flag is set at the same time.
Gen3Commands.SPECIALS[121] = function(ctx)
  local Decor = require("src.world.Gen3Decorations")
  local data = ctx.game and ctx.game.data
  local trader = traderState(ctx)
  if not trader then return end
  local mine = math.floor(tonumber(getVar(ctx.save, 0x8006)) or 0)
  local his = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  local slot = math.floor(tonumber(getVar(ctx.save, 0x8005)) or 0) + 1
  if mine <= 0 or his <= 0 or mine == MAUVILLE_CANCEL
     or his == MAUVILLE_CANCEL then
    return
  end
  Decor.take(ctx.save, mine, 1)
  Decor.give(ctx.save, his, 1)
  if trader.decorations[slot] then
    trader.decorations[slot] = mine
    trader.names[slot] = tostring((ctx.save.player or {}).name or "")
  end
  trader.traded = true
  local ow = ctx.overworld
  if ow and ow.refreshGen3Decorations then ow:refreshGen3Decorations() end
  Logger.info("gen3 trader: swapped %s for %s in slot %d",
              tostring(Decor.name(data, mine)), tostring(Decor.name(data, his)),
              slot)
end


-- ---------------------------------------------------------------------------
-- LILYCOVE'S LIFT (276 and 433, with 308 and 525 alongside).
--
-- The department store's panel is five maps and one multichoice, and it asked
-- two questions nothing was answering:
--
--     special 308 / message "Which floor?" / specialvar RESULT, 433
--     compare 0x8000, 0 .. 4  ->  multichoicedefault 0, 0, 57, <row>, 0
--     ... setdynamicwarp / call <the ride>
--     the ride: special 525 / applymovement / waitse / special 276 /
--               waitstate
--
-- 433 says WHICH ROW the cursor opens on, so that the floor you called the
-- lift from is the one already highlighted.  Unimplemented it answered zero,
-- and zero is the TOP floor -- so the panel offered 5F from the ground floor,
-- every time.
--
-- 276 is the ride: the screen rocks by a pixel every few frames for as long
-- as the trip is far, and a chime says you have arrived.  Both the distance
-- table and the two sounds come off the cartridge (extractElevator); the trip
-- is measured between 0x8005, the floor you are on, and 0x8006, the one you
-- picked, which is why the panel sets both before it calls.
--
-- 308 and 525 put the little floor indicator up in the corner and take it
-- down again.  They are not served here -- that is a window with its own art
-- -- and an unserved special is silent rather than wrong: the panel and the
-- ride both work without it.
-- ---------------------------------------------------------------------------

local function elevatorRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  local r = data and data.constants and data.constants.gen3Elevator
  return type(r) == "table" and r or nil
end

-- WHICH FLOOR THE LIFT IS ON, and it is NOT the map you are standing on.
--
-- Both of these read gSaveBlock1Ptr->dynamicWarp -- the slot `setdynamicwarp`
-- writes, which each floor's own arm sets as you pick it.  That is worth
-- being exact about: reading the current map instead would be right most of
-- the time and would quietly disagree with the cartridge the first time you
-- walked in off the street, where the dynamic warp still names wherever it
-- last named and the panel opens on the top floor.
local function elevatorFloorIndex(ctx, record)
  local warp = (ctx.save or {}).gen3DynamicWarp
  local data = ctx.game and ctx.game.data
  local def = warp and warp.map and data and data.maps and data.maps[warp.map]
  if not (record and def) then return nil end
  local number = tonumber(def.number)
  if tonumber(def.group) ~= record.group or not number then return nil end
  local index = number - record.firstNumber
  if index < 0 then return nil end
  return index
end

-- 219: SetDeptStoreFloor.  Run once, the first time the panel is used, and
-- the number it writes is NOT the menu row -- it is the cartridge's own floor
-- id, and the roof is not the one after the top floor.  MoveElevator
-- subtracts one of these from another, so a guess here makes the ride the
-- wrong length.
Gen3Commands.SPECIALS[219] = function(ctx)
  local record = elevatorRecord(ctx)
  local floor = record and record.floorVar
  if not floor then return end
  local index = elevatorFloorIndex(ctx, record)
  local id = (index and index < floor.floors and floor.ids[index + 1])
             or floor.ids[1]
  setVar(ctx.save, floor.var, id)
end

-- 433: GetDeptStoreDefaultFloorChoice.
Gen3Commands.SPECIALS[433] = function(ctx)
  local record = elevatorRecord(ctx)
  local index = elevatorFloorIndex(ctx, record)
  if not (record and index) or index >= record.floors then return 0 end
  -- the rows run TOP FLOOR FIRST, which is why this is a lookup and not the
  -- index itself
  return record.rows[index + 1] or 0
end

-- 276: MoveElevator.  BLOCKING, because the row after it is `waitstate`.
Gen3Commands.SPECIALS[276] = function(ctx)
  local record = elevatorRecord(ctx)
  local ride = record and record.ride
  local ow, runner = ctx.overworld, ctx.runner
  if not (ride and ow and runner) then return end
  local from = math.floor(tonumber(getVar(ctx.save, 0x8005)) or 0)
  local to = math.floor(tonumber(getVar(ctx.save, 0x8006)) or 0)
  local distance = math.abs(from - to)
  if distance > ride.clamp then distance = ride.clamp end
  local shakes = ride.counts[distance + 1] or ride.counts[1]
  local done = false
  local function finish()
    if done then return end
    done = true
    ow.gen3Elevator = nil
    ow.bgShakeY = 0
    if ride.arriveSound then
      Commands.play_sound(ctx, ("SONG_%03X"):format(ride.arriveSound))
    end
    runner:resume()
  end
  if ride.startSound then
    Commands.play_sound(ctx, ("SONG_%03X"):format(ride.startSound))
  end
  ow.gen3Elevator = { shakes = shakes, frames = 0,
                      period = Gen3Commands.ELEVATOR_PERIOD,
                      amplitude = 1, resume = finish }
  runner:yield()
end

-- The cartridge's task flips the background a pixel every third frame and
-- counts the flips, which is what makes a long trip take longer than a short
-- one without the shake itself getting faster.
Gen3Commands.ELEVATOR_PERIOD = 3


-- ---------------------------------------------------------------------------
-- THE SCROLLING MULTICHOICE (446).
--
-- The ordinary `multichoice` opcode draws a fixed list out of a table the
-- import already reads.  This is the other one -- a list too long for the
-- screen, drawn by a task that scrolls -- and thirteen counters in Hoenn open
-- one.  Every one of them is written the same way:
--
--     setvar 0x8004, <list id> / special 446 / waitstate
--     copyvar 0x8000, VAR_RESULT
--     compare 0x8000, 0 ... n, and 127 for backing out
--
-- so the special's whole job is to answer WHICH ROW, and the script does the
-- rest -- which is why two shops nobody could reach are fixed by a list and a
-- number: Lavaridge's herb shop and Fallarbor's glass workshop both sell
-- through this and neither is a `pokemart`.
--
-- THE CANCEL ROW IS ALREADY IN THE LIST.  Every one of these ends in EXIT and
-- the scripts branch on it by index, so this must NOT add a row of its own --
-- pressing B answers 127, which is the value the scripts compare against
-- beside the real rows.
-- ---------------------------------------------------------------------------

Gen3Commands.SCROLL_MULTI_CANCEL = 127

Gen3Commands.SPECIALS[446] = function(ctx)
  local data = ctx.game and ctx.game.data
  local record = data and data.constants
                 and data.constants.gen3ScrollMultichoice
  local id = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  local list = record and record.lists and record.lists[id]
  local rows = list and list.rows
  if type(rows) ~= "table" or #rows == 0 then
    Logger.warn("gen3 scrolling list: this dataset has no list %d, so the "
                  .. "counter is backed out of rather than answered wrong", id)
    return Gen3Commands.SCROLL_MULTI_CANCEL
  end
  local picked = Gen3Commands.listPick(ctx, rows, nil,
                                       tonumber(list.visible))
  if not picked then return Gen3Commands.SCROLL_MULTI_CANCEL end
  return picked - 1
end


-- ---------------------------------------------------------------------------
-- BERRY POWDER, and the man in MAUVILLE who sells for it.
--
-- The vendor's counter is `special 446` -- the scrolling list -- and that has
-- worked since it was written, so the list opened, twelve rows deep, and
-- every one of them did nothing: 463, 464, 465, 466 and 467 were all unserved
-- and the buy branch fell straight through.
--
-- THE COUNTER IS XORED.  Powder lives at SaveBlock2 + 500 masked with the
-- word at +172, the same key money and coins use, which is why a reader that
-- takes it at face value sees six digits on a fresh file.  extractBerryPowder
-- derives both offsets out of gSpecials[465]'s own code and refuses to write
-- the record unless the key offset matches the save layout's -- so the codec
-- below can just carry a number and let Gen3Save do the masking.
--
-- FOUR OF THE FIVE ARE SMALL once the number exists.  463 and 467 put the
-- total on screen and 464 takes it away again; this port draws the money and
-- coin counters the same way -- which is to say it does not, because the
-- message window already says the price -- so they are nops with a name,
-- exactly like `showmoneybox`.  The two that matter are 465, which decides
-- whether the row can be bought at all, and 466, which takes the powder.
-- ---------------------------------------------------------------------------

function Gen3Commands.berryPowder(save)
  return math.max(0, math.floor(tonumber(save and save.berryPowder) or 0))
end

function Gen3Commands.setBerryPowder(save, amount)
  if not save then return end
  amount = math.floor(tonumber(amount) or 0)
  -- the cartridge caps it at 999999, the width of its own counter window
  save.berryPowder = math.max(0, math.min(999999, amount))
end

-- 463 DisplayBerryPowderVendorMenu / 467 PrintPlayerBerryPowderAmount /
-- 464 RemoveBerryPowderVendorMenu -- the counter window, which this port does
-- not draw for money or coins either.
Gen3Commands.SPECIALS[463] = function() end
Gen3Commands.SPECIALS[467] = function() end
Gen3Commands.SPECIALS[464] = function() end

-- 465 HasEnoughBerryPowder: `GetBerryPowder() >= VAR_0x8004`.
Gen3Commands.SPECIALS[465] = function(ctx)
  local want = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  return Gen3Commands.berryPowder(ctx.save) >= want and 1 or 0
end

-- 466 TakeBerryPowder: the same test again, and only then the subtraction --
-- the cartridge asks twice on purpose, because the script shows a menu
-- between the two and the answer can have changed.
Gen3Commands.SPECIALS[466] = function(ctx)
  local want = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  local have = Gen3Commands.berryPowder(ctx.save)
  if have < want then return 0 end
  Gen3Commands.setBerryPowder(ctx.save, have - want)
  return 1
end


-- ---------------------------------------------------------------------------
-- THE BARD, and the screen nineteen scripts open.
--
-- The first of MAUVILLE's five old men, and the first this port can answer:
-- he sings six EASY CHAT WORDS, and you can hand him six of your own.  His
-- half of the five-man union at SaveBlock1 + $2E28 is the song at +2, an
-- audition copy at +14, the name and trainer id of whoever last rewrote it,
-- and a byte at +$29 saying whether anybody ever has.
--
-- THREE SPECIALS AND A SCREEN.  106 sings (VAR_0x8004 picks his own song or
-- the one being auditioned), 101 says whether it has ever been changed, 102
-- commits the audition -- and gSpecials[98], the easy chat screen, is what
-- fills the audition in.  98's arm for the bard copies his current song into
-- the audition slot first, so the picker opens on what he is already singing
-- rather than on six blanks.
--
-- THAT SCREEN IS CALLED FROM NINETEEN PLACES, so it is served by mode here
-- rather than by feature: an unserved mode answers "backed out", which is
-- what every one of those scripts already handles, instead of leaving
-- VAR_RESULT holding whatever the last check put there.
-- ---------------------------------------------------------------------------

Gen3Commands.EASY_CHAT_EMPTY = 0xFFFF
Gen3Commands.EASY_CHAT_BARD = 6

-- WHICH NUMBER EACH MAN IS comes off the import, which proves the five arms
-- of SetMauvilleOldMan are numbered nought to four in order and anchors that
-- on the TRADER -- found by a different route entirely.  Reading it from
-- there rather than writing 0 here is the difference between the BARD and
-- whoever happens to sit at index nought.
local function manNumber(ctx, who)
  local data = ctx and ctx.game and ctx.game.data
  local man = (data and data.constants or {}).gen3MauvilleMan
  local names = man and man.who
  return names and names[who] or nil
end

local function bardRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  local man = (data and data.constants or {}).gen3MauvilleMan
  return man and man.bard or nil
end

-- His song, seeded the way SetupBard seeds it: the cartridge's own six words.
-- Only when the house actually holds him -- the man is rolled off the trainer
-- id once and never again.
function Gen3Commands.bard(ctx)
  local record = bardRecord(ctx)
  local state = Gen3Commands.mauvilleMan(ctx)
  local who = manNumber(ctx, "bard")
  if not (record and state and who) then return nil end
  if state.man ~= who then return nil end
  if type(state.bard) ~= "table" then
    local song = {}
    for i, w in ipairs(record.default or {}) do song[i] = w end
    state.bard = { song = song, temp = {}, changed = false }
  end
  return state.bard, record
end

-- 106 PlayBardSong.  The cartridge sings it with a note animation; this port
-- has no singing scene, so the words go in the message window -- which is
-- where the player reads them either way.
Gen3Commands.SPECIALS[106] = function(ctx)
  local bard, record = Gen3Commands.bard(ctx)
  if not bard then return end
  local which = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  local words = (which == 1 and #(bard.temp or {}) > 0) and bard.temp
                or bard.song
  local EasyChat = require("src.script.EasyChat")
  local text = EasyChat.phrase(ctx.game and ctx.game.data, words,
                               record.perLine or 2)
  if text == "" then return end
  -- BLOCKING, like every other box: the row after it is `delay 60`, and the
  -- song has to be on screen before the question that follows it.
  local game, runner = ctx.game, ctx.runner
  local okBox, TextBox = pcall(require, "src.render.TextBox")
  if not (okBox and game and game.stack and runner) then return end
  local pushed = pcall(game.stack.push, game.stack,
                       TextBox.new(game, text, function() runner:resume() end))
  if pushed then runner:yield() end
end

-- 101 HasBardSongBeenChanged
Gen3Commands.SPECIALS[101] = function(ctx)
  local bard = Gen3Commands.bard(ctx)
  return (bard and bard.changed) and 1 or 0
end

-- 102 SaveBardSongLyrics: the audition becomes the song, and it remembers who
-- taught it to him -- which is what his line reads back on a cartridge that
-- has mixed records with somebody.
Gen3Commands.SPECIALS[102] = function(ctx)
  local bard = Gen3Commands.bard(ctx)
  if not (bard and type(bard.temp) == "table" and #bard.temp > 0) then return end
  local song = {}
  for i, w in ipairs(bard.temp) do song[i] = w end
  bard.song = song
  bard.name = tostring((ctx.save.player or {}).name or "")
  bard.ot = math.floor(tonumber((ctx.save.player or {}).id) or 0)
  bard.changed = true
end

-- ---------------------------------------------------------------------------
-- THE HIPSTER, and where a TRENDY SAYING comes from.
--
-- The picker offers seventeen groups you can use from the first minute and
-- one you cannot: the thirty-three TRENDY SAYINGS start LOCKED, and this man
-- is the only way they open -- one per conversation, at random, out of the
-- ones you do not know yet.  A save that has never met him can pick none of
-- them, which is why the group does not even appear on his screen until it
-- has something in it.
--
-- HIS COUNTER IS THE BYTE THE OTHER MEN USE TOO.  All five share the record,
-- so +1 is "has he taught you one" for him and a tale counter for GIDDY --
-- the same byte meaning different things because only one of them lives
-- there.
local function hipsterRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  local man = (data and data.constants or {}).gen3MauvilleMan
  return man and man.hipster or nil
end

function Gen3Commands.hipster(ctx)
  local record = hipsterRecord(ctx)
  local state = Gen3Commands.mauvilleMan(ctx)
  local who = manNumber(ctx, "hipster")
  if not (record and state and who) then return nil end
  if state.man ~= who then return nil end
  if type(state.hipster) ~= "table" then state.hipster = { taught = false } end
  return state.hipster, record
end

-- 103 HasHipsterTaughtWord / 104 SetHipsterTaughtWord
Gen3Commands.SPECIALS[103] = function(ctx)
  local hipster = Gen3Commands.hipster(ctx)
  return (hipster and hipster.taught) and 1 or 0
end

Gen3Commands.SPECIALS[104] = function(ctx)
  local hipster = Gen3Commands.hipster(ctx)
  if hipster then hipster.taught = true end
end

-- 105 HipsterTryTeachWord: one of the ones you do not know, at random, and
-- ZERO when you know them all -- which is a real answer his script handles,
-- not a failure.
Gen3Commands.SPECIALS[105] = function(ctx)
  local hipster, record = Gen3Commands.hipster(ctx)
  if not hipster then return 0 end
  local EasyChat = require("src.script.EasyChat")
  local save, data = ctx.save, ctx.game and ctx.game.data
  local locked = {}
  for i = 0, (tonumber(record.count) or 0) - 1 do
    if not EasyChat.knowsPhrase(save, i) then locked[#locked + 1] = i end
  end
  if #locked == 0 then return 0 end
  local pick = locked[math.floor(love.math.random(1, #locked))]
  EasyChat.learnPhrase(save, pick)
  local word = (tonumber(record.base) or 0) + pick
  save.buffers = save.buffers or {}
  save.buffers[1] = EasyChat.text(data, word) or ""
  return 1
end


-- ---------------------------------------------------------------------------
-- GIDDY, who talks and talks and talks.
--
-- The only one of the five who says something different every time without
-- you touching a picker: ten tales in a row, and each one is either one of
-- eight canned questions or a sentence built round a random easy chat word --
-- "<word> is so darling!" with "Don't you agree?" under it.  After the tenth
-- he stops until you come back.
--
-- HIS WORDS COME FROM SIX GROUPS and the cartridge weights the draw by how
-- big each group is, which is why he says a POKeMON's name far more often
-- than a LIFESTYLE word: two of his six groups are species lists of two
-- hundred and two and two hundred and fifty-one.  Drawing a group first and
-- then a word inside it would be a different man entirely.
local function giddyRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  local man = (data and data.constants or {}).gen3MauvilleMan
  return man and man.giddy or nil
end

function Gen3Commands.giddy(ctx)
  local record = giddyRecord(ctx)
  local state = Gen3Commands.mauvilleMan(ctx)
  local who = manNumber(ctx, "giddy")
  if not (record and state and who) then return nil end
  if state.man ~= who then return nil end
  if type(state.giddy) ~= "table" then
    state.giddy = { tale = 0, asked = 0, tales = {}, order = {} }
  end
  return state.giddy, record
end

-- GiddyFillRandomWords: ten slots, each either a question marker or a word
-- drawn from the six groups -- weighted by group size, the way the cartridge
-- draws it -- and the eight questions come round in a shuffled order.
local function giddyFill(ctx, state, record)
  local EasyChat = require("src.script.EasyChat")
  local data = ctx.game and ctx.game.data
  local pool, total = {}, 0
  for _, g in ipairs(record.groups or {}) do
    local words = EasyChat.words(data, g, ctx.save)
    if #words > 0 then
      pool[#pool + 1] = words
      total = total + #words
    end
  end
  local order = {}
  for i = 1, record.questionCount do order[i] = i end
  for i = #order, 2, -1 do
    local j = math.floor(love.math.random(1, i))
    order[i], order[j] = order[j], order[i]
  end
  local tales, asked = {}, 0
  for i = 1, record.tales do
    local question = total == 0
                     or (asked < record.questionCount
                         and love.math.random(1, 10) <= 3)
    if question and asked < record.questionCount then
      asked = asked + 1
      tales[i] = { question = order[asked] }
    else
      local pick = math.floor(love.math.random(1, math.max(1, total)))
      for _, words in ipairs(pool) do
        if pick <= #words then tales[i] = { word = words[pick].id } break end
        pick = pick - #words
      end
      tales[i] = tales[i] or { question = order[1] }
    end
  end
  state.tales, state.order, state.tale, state.asked = tales, order, 0, 0
end

-- 108 GenerateGiddyLine
Gen3Commands.SPECIALS[108] = function(ctx)
  local state, record = Gen3Commands.giddy(ctx)
  if not state then return end
  if (state.tale or 0) == 0 or type(state.tales) ~= "table"
     or #state.tales == 0 then
    giddyFill(ctx, state, record)
  end
  local slot = state.tales[(state.tale or 0) + 1]
  if not slot then return end
  local text
  if slot.question then
    text = record.questions[slot.question] or ""
  else
    local EasyChat = require("src.script.EasyChat")
    local word = EasyChat.text(ctx.game and ctx.game.data, slot.word) or ""
    local suffix = record.suffixes[math.floor(
      love.math.random(1, #record.suffixes))] or ""
    text = word .. (record.join or "") .. suffix .. (record.tail or "")
  end
  state.tale = (state.tale or 0) + 1
  local game, runner = ctx.game, ctx.runner
  local okBox, TextBox = pcall(require, "src.render.TextBox")
  if not (okBox and game and game.stack and runner and text ~= "") then return end
  local pushed = pcall(game.stack.push, game.stack,
                       TextBox.new(game, text, function() runner:resume() end))
  if pushed then runner:yield() end
end

-- 109 GiddyShouldTellAnotherTale: ten and then he stops, and the counter goes
-- back to nought so the next visit starts him over.
Gen3Commands.SPECIALS[109] = function(ctx)
  local state, record = Gen3Commands.giddy(ctx)
  if not state then return 0 end
  if (state.tale or 0) >= (tonumber(record.tales) or 10) then
    state.tale = 0
    return 0
  end
  return 1
end


-- ---------------------------------------------------------------------------
-- THE STORYTELLER, the fourth of Mauville's five old men -- and the only one
-- of the five whose material is YOU.
--
-- The other four have something of their own to say: a song, a saying, a
-- decoration to trade, ten tales of nothing at all.  The Storyteller has
-- none.  Everything he knows he read off the player's own game statistics,
-- and every line he speaks is one of them read back with a flourish: "This
-- TRAINER saved the game 214 times!  A more cautious TRAINER than {PLAYER}
-- one will never find!"
--
-- HE KEEPS FOUR TALES and each one is a snapshot, not a live reading -- the
-- statistic AS IT STOOD when he wrote it down, plus the name of the TRAINER
-- it belonged to.  That is what makes the second half of his script work:
-- come back later, have him tell the same tale, and if the counter has moved
-- since he is impressed all over again and writes the new figure down.  A
-- port that read the statistic live would never surprise him.
--
-- ZERO MEANS EMPTY, which is the one thing here that looks like a mistake and
-- is not.  A free slot is a stat id of zero, so the statistic whose real id
-- IS zero -- the save counter, his first and most famous tale -- cannot be
-- stored as itself; the cartridge files it under another number and maps it
-- back when it reads the counter.  The extractor derives both the renaming
-- and the number.
-- ---------------------------------------------------------------------------
local function storytellerRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  return (data and data.constants or {}).gen3Storyteller
end

function Gen3Commands.storyteller(ctx)
  local record = storytellerRecord(ctx)
  local state = Gen3Commands.mauvilleMan(ctx)
  local who = manNumber(ctx, "storyteller")
  if not (record and state and who) then return nil end
  if state.man ~= who then return nil end
  if type(state.storyteller) ~= "table" then
    state.storyteller = { tales = {}, recorded = false, picked = 0 }
  end
  local told = state.storyteller
  if type(told.tales) ~= "table" then told.tales = {} end
  return told, record
end

-- The row for a statistic.  A statistic with no row of its own reads back as
-- the LAST row, which is the cartridge's own answer for a miss -- its search
-- runs off the end of the table and returns whatever it stopped on.
local function storyStat(record, id)
  local rows = (record and record.stats) or {}
  for _, row in ipairs(rows) do
    if row.id == id then return row end
  end
  return rows[#rows]
end

local function storyTales(record)
  local shape = record and record.record
  return math.floor(tonumber(shape and shape.tales) or 4)
end

-- What the player's counter for one of his statistics says, through the
-- renaming described above.
local function storyCount(ctx, record, id)
  local alias = (record and record.alias) or {}
  local key = alias[id] or alias[tostring(id)] or id
  local stats = ctx.save and ctx.save.gen3Stats
  return math.floor(tonumber(stats and stats[key]) or 0)
end

-- StorytellerRecordNewStat: the slot takes the statistic, the name of whoever
-- it belongs to and the counter as it stands -- and the two buffers the
-- "birth of a new legend" line reads back.
local function storyWrite(ctx, told, record, slot, id)
  local row = storyStat(record, id)
  local count = storyCount(ctx, record, id)
  told.tales[slot] = {
    stat = id, value = count,
    name = tostring(((ctx.save or {}).player or {}).name or ""),
  }
  local save = ctx.save
  if not save then return end
  save.buffers = save.buffers or {}
  save.buffers[1] = tostring(count)
  save.buffers[2] = row and row.action or ""
end

-- 110 StorytellerGetFreeStorySlot.  His script reads this before anything
-- else and treats ZERO as "he has no tales at all", which is why an empty
-- record has to answer 0 rather than the number of slots.
Gen3Commands.SPECIALS[110] = function(ctx)
  local told, record = Gen3Commands.storyteller(ctx)
  if not told then return 0 end
  local tales = storyTales(record)
  for i = 1, tales do
    if type(told.tales[i]) ~= "table" then return i - 1 end
  end
  return tales
end

-- 111 Script_StorytellerDisplayStory.  BLOCKING: the rows after it are
-- `waitmessage` and `waitbuttonpress`, so the tale has to be on screen before
-- the special that judges it runs.
Gen3Commands.SPECIALS[111] = function(ctx)
  local told, record = Gen3Commands.storyteller(ctx)
  if not told then return end
  local tale = told.tales[(tonumber(told.picked) or 0) + 1]
  local row = tale and storyStat(record, tale.stat)
  if not (row and row.tale) then return end
  local save = ctx.save
  if save then
    save.buffers = save.buffers or {}
    save.buffers[1] = tostring(tale.value or 0)
    save.buffers[2] = row.action or ""
    save.buffers[3] = tale.name or ""
  end
  local game, runner = ctx.game, ctx.runner
  local okBox, TextBox = pcall(require, "src.render.TextBox")
  if not (okBox and game and game.stack and runner) then return end
  local pushed = pcall(game.stack.push, game.stack,
                       TextBox.new(game, row.tale,
                                   function() runner:resume() end))
  if pushed then runner:yield() end
end

-- 112 StorytellerStoryListMenu: the tales he has, by title, and a row to
-- leave by.  The cartridge answers 1 for a tale and 0 for the way out --
-- which is why this one does not use the plain row index.
Gen3Commands.SPECIALS[112] = function(ctx)
  local told, record = Gen3Commands.storyteller(ctx)
  if not told then
    setVar(ctx.save, VAR_RESULT, 0)
    return
  end
  local rows, slots = {}, {}
  for i = 1, storyTales(record) do
    local tale = told.tales[i]
    local row = tale and storyStat(record, tale.stat)
    if row then
      rows[#rows + 1] = row.title or ""
      slots[#slots + 1] = i
    end
  end
  rows[#rows + 1] = record.exit or "EXIT"
  askChoices(ctx, rows, {
    answer = function(index)
      local slot = index and slots[index]
      if not slot then return 0 end
      told.picked = slot - 1
      return 1
    end,
  })
end

-- 113 StorytellerUpdateStat: has the counter behind the tale he just told
-- moved since he wrote it down?  If it has he writes the new figure down --
-- and the buffers that go with it, because the line that follows reads them.
Gen3Commands.SPECIALS[113] = function(ctx)
  local told, record = Gen3Commands.storyteller(ctx)
  if not told then return 0 end
  local slot = (tonumber(told.picked) or 0) + 1
  local tale = told.tales[slot]
  if not tale then return 0 end
  local now = storyCount(ctx, record, tale.stat)
  if now <= (tonumber(tale.value) or 0) then return 0 end
  storyWrite(ctx, told, record, slot, tale.stat)
  return 1
end

-- 114 Script_StorytellerInitializeRandomStat: he looks through everything he
-- could take an interest in, IN A SHUFFLED ORDER -- so which tale he takes
-- from a player who qualifies for several is not the order of the table --
-- and stops at the first that is not already one of his and is above its own
-- threshold.  When all four slots are full the new tale goes over the one
-- that was just being told, which is the cartridge's own answer.
Gen3Commands.SPECIALS[114] = function(ctx)
  local told, record = Gen3Commands.storyteller(ctx)
  if not told then return 0 end
  local rows = record.stats or {}
  local order = {}
  for i = 1, #rows do order[i] = i end
  for i = #order, 2, -1 do
    local j = math.floor(love.math.random(1, i))
    order[i], order[j] = order[j], order[i]
  end
  local tales = storyTales(record)
  for _, k in ipairs(order) do
    local row = rows[k]
    local held = false
    for i = 1, tales do
      if (told.tales[i] or {}).stat == row.id then held = true break end
    end
    if not held and storyCount(ctx, record, row.id)
       >= (tonumber(row.least) or 1) then
      told.recorded = true
      local slot
      for i = 1, tales do
        if type(told.tales[i]) ~= "table" then slot = i break end
      end
      storyWrite(ctx, told, record,
                 slot or ((tonumber(told.picked) or 0) + 1), row.id)
      return 1
    end
  end
  return 0
end

-- 115 HasStorytellerAlreadyRecorded.  Once he has taken a tale off you he
-- stops asking for another in the same conversation.
Gen3Commands.SPECIALS[115] = function(ctx)
  local told = Gen3Commands.storyteller(ctx)
  return (told and told.recorded) and 1 or 0
end


-- 98 ShowEasyChatScreen.  VAR_0x8004 is which caller it is.
--
-- BLOCKING: every one of the nineteen callers follows it with `waitstate`.
Gen3Commands.SPECIALS[98] = function(ctx)
  local mode = math.floor(tonumber(getVar(ctx.save, 0x8004)) or -1)
  setVar(ctx.save, VAR_RESULT, 0)
  local game, runner = ctx.game, ctx.runner
  if mode ~= Gen3Commands.EASY_CHAT_BARD then
    Logger.debug("gen3 easy chat: mode %d is not served yet, so the script "
                   .. "is told the player backed out", mode)
    return
  end
  local bard, record = Gen3Commands.bard(ctx)
  local ok, Screen = pcall(require, "src.ui.Gen3EasyChat")
  if not (bard and ok and game and game.stack and runner) then return end
  local opened = Screen.open(game, {
    count = record.words or 6,
    words = bard.song,
    onDone = function(words)
      local temp = {}
      for i, w in ipairs(words) do
        if w ~= Gen3Commands.EASY_CHAT_EMPTY then temp[#temp + 1] = w end
      end
      bard.temp = temp
      setVar(ctx.save, VAR_RESULT, #temp > 0 and 1 or 0)
      runner:resume()
    end,
    onCancel = function()
      setVar(ctx.save, VAR_RESULT, 0)
      runner:resume()
    end,
  })
  if opened then runner:yield() end
end


-- ---------------------------------------------------------------------------
-- LILYCOVE'S CONTEST LOBBY, and the woman in it.
--
-- There are three of them -- the QUIZ LADY, the FAVOR LADY and the CONTEST
-- LADY -- and only one lives in any given save.  WHICH ONE IS YOUR TRAINER
-- ID: InitLilycoveLady reads the public id, takes it modulo six and halves
-- it, so 0 is the quiz, 1 the favour and 2 the contest.  The same shape as
-- the Mauville old man's `(id % 10) / 2`, and worth saying out loud, because
-- it means two players in three never meet the FAVOR LADY at all.
--
-- gSpecials[365] is the lobby's whole dispatch and it was unserved, so the
-- script branched on whatever VAR_RESULT happened to hold and the room was
-- non-deterministic.  Serving it makes the lobby answer the same way twice.
--
-- WHAT THE FAVOR LADY WANTS is one of six adjectives -- slippery, roundish,
-- wham-ish, shiny, sticky, pointy -- and each one names a list of items she
-- will accept.  FIVE liked things satisfy her, and then she hands over one of
-- six premium prizes: a LUXURY BALL, a NUGGET, a PROTEIN, a HEART SCALE, a
-- RARE CANDY or a PP MAX.  extractFavorLady finds all four tables by
-- requiring them to tile -- the lists are packed behind the adjectives and
-- the pointer table starts exactly where the last one ends -- so nothing here
-- is addressed by hand.
--
-- WHAT THIS DOES NOT CARRY is the other players' half.  On a cartridge the
-- record travels through record mixing, which is how somebody else's name
-- ends up on the item she is holding; 368 and 370 read that name, and with no
-- link there is never one, so she asks you instead.  That is the same answer
-- a cartridge that has never mixed gives.
-- ---------------------------------------------------------------------------

local function favorRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  return (data and data.constants or {}).gen3FavorLady
end

-- Roll a new favour, the way InitFavorLady does: the adjective at random, and
-- then one item off ITS list as the example she names.
local function rollFavor(state, record)
  local favors = math.max(1, math.floor(tonumber(record.favors) or 6))
  state.favor = math.floor(love.math.random(1, favors))
  local list = (record.lists or {})[state.favor] or {}
  state.hint = #list > 0 and list[math.floor(love.math.random(1, #list))] or nil
end

function Gen3Commands.lilycoveLady(ctx)
  local save = ctx and ctx.save
  local record = favorRecord(ctx)
  if not save then return nil end
  local state = save.gen3LilycoveLady
  if type(state) ~= "table" then
    local mod = math.floor(tonumber(record and record.pickMod) or 6)
    local div = math.floor(tonumber(record and record.pickDiv) or 2)
    if mod < 1 then mod = 1 end
    if div < 1 then div = 1 end
    local id = math.floor(tonumber((save.player or {}).id) or 0)
    state = { id = math.floor((id % mod) / div),
              phase = 0, liked = false, given = 0 }
    save.gen3LilycoveLady = state
    if record and state.id == (tonumber(record.lady) or 1) then
      rollFavor(state, record)
    end
  end
  return state
end

-- ...and her half of it, or nothing at all when the lobby holds someone else.
local function favorLady(ctx)
  local record = favorRecord(ctx)
  local state = Gen3Commands.lilycoveLady(ctx)
  if not (record and state) then return nil end
  if state.id ~= (tonumber(record.lady) or 1) then return nil end
  if not state.favor then rollFavor(state, record) end
  return state, record
end

-- 364 SetLilycoveLadyGfx: the lobby's object is OBJ_EVENT_GFX_VAR_0, so who
-- is standing there is a VARIABLE and not three objects with three flags.
Gen3Commands.SPECIALS[364] = function(ctx)
  local record = favorRecord(ctx)
  local state = Gen3Commands.lilycoveLady(ctx)
  local gfx = record and state and (record.gfx or {})[state.id]
  if gfx then setVar(ctx.save, 0x4010, math.floor(gfx)) end
end

-- 365 Script_GetLilycoveLadyId -- the dispatch the whole room hangs off.
Gen3Commands.SPECIALS[365] = function(ctx)
  local state = Gen3Commands.lilycoveLady(ctx)
  setVar(ctx.save, VAR_RESULT, state and math.floor(state.id) or 0)
end

-- 366 GetFavorLadyState: two is "she owes you a prize", one is "she has
-- already thanked you", zero is "still collecting".
Gen3Commands.SPECIALS[366] = function(ctx)
  local state = favorLady(ctx)
  local phase = state and math.floor(tonumber(state.phase) or 0) or 0
  if phase == 2 then return 2 end
  return phase == 1 and 1 or 0
end

-- 367 BufferFavorLadyRequest: the adjective, into {VAR1}.
Gen3Commands.SPECIALS[367] = function(ctx)
  local state, record = favorLady(ctx)
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[1] = (state and record
                         and (record.words or {})[state.favor]) or ""
end

-- 368 HasAnotherPlayerGivenFavorLadyItem: only ever true on a save that has
-- mixed records with somebody.
Gen3Commands.SPECIALS[368] = function(ctx)
  local state = favorLady(ctx)
  local name = state and state.name
  if type(name) ~= "string" or name == "" then return 0 end
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[3] = name
  return 1
end

-- 369 BufferFavorLadyItemName into {VAR2}, 370 BufferFavorLadyPlayerName
-- into {VAR3}.
Gen3Commands.SPECIALS[369] = function(ctx)
  local state = favorLady(ctx)
  local data = ctx.game and ctx.game.data
  local id = state and Gen3Commands.itemId(data, state.item)
  local def = id and (data.items or {})[id]
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[2] = (def and def.name) or id or ""
end

Gen3Commands.SPECIALS[370] = function(ctx)
  local state = favorLady(ctx)
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[3] = (state and state.name) or ""
end

-- 371 DidFavorLadyLikeItem
Gen3Commands.SPECIALS[371] = function(ctx)
  local state = favorLady(ctx)
  return (state and state.liked) and 1 or 0
end

-- 372 Script_FavorLadyOpenBagMenu -- the bag, any pocket, handing one item
-- back.  The cartridge parks the choice in gSpecialVar_ItemId for 373 to read
-- a row later; this port has no such global, and since the two calls are
-- adjacent in the script the pick is simply kept on her record instead.
--
-- BLOCKING: the row after it is `waitstate`.
Gen3Commands.SPECIALS[372] = function(ctx)
  local game, runner = ctx.game, ctx.runner
  local state = favorLady(ctx)
  setVar(ctx.save, VAR_RESULT, 0)
  if state then state.pick = nil end
  if not (game and game.stack and runner and state) then return end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return end
  local order = (game.data and game.data.constants or {}).itemOrder
  local pushed = pcall(Screens.push, game, "Gen3BagMenu", {
    pick = true,
    onCancel = function() runner:resume() end,
    onPick = function(itemId)
      for n, id in ipairs(order or {}) do
        if id == itemId then state.pick = n break end
      end
      setVar(ctx.save, VAR_RESULT, state.pick and 1 or 0)
      runner:resume()
    end,
  })
  if pushed then runner:yield() end
end


-- 373 Script_DoesFavorLadyLikeItem -- and note everything it writes even when
-- the answer is NO: she remembers the item, who gave it and that she was
-- given something at all, which is what her "thank you for last time" line
-- reads back.  Only the COUNT moves on a like.
Gen3Commands.SPECIALS[373] = function(ctx)
  local state, record = favorLady(ctx)
  if not state then return 0 end
  local item = math.floor(tonumber(state.pick) or 0)
  state.pick = nil
  if item <= 0 then return 0 end
  local list = (record.lists or {})[state.favor] or {}
  local liked = false
  for _, id in ipairs(list) do if id == item then liked = true break end end
  state.phase = 1
  state.item = item
  state.name = tostring((ctx.save.player or {}).name or "")
  state.liked = liked
  if liked then state.given = math.floor(tonumber(state.given) or 0) + 1 end
  -- the bag loses it either way: she keeps what she is handed
  local id = Gen3Commands.itemId(ctx.game and ctx.game.data, item)
  if id then pcall(Commands.take_item, ctx, id, 1) end
  return liked and 1 or 0
end

-- 374 IsFavorLadyThresholdMet: five liked things, not four.
Gen3Commands.SPECIALS[374] = function(ctx)
  local state, record = favorLady(ctx)
  if not state then return 0 end
  local want = math.floor(tonumber(record.threshold) or 5)
  return (math.floor(tonumber(state.given) or 0) >= want) and 1 or 0
end

-- 375 FavorLadyGetPrize: the prize her ADJECTIVE earns, and the phase moves
-- to two so a bag that was full when she offered it still owes you one.
Gen3Commands.SPECIALS[375] = function(ctx)
  local state, record = favorLady(ctx)
  if not state then return 0 end
  state.phase = 2
  return math.floor(tonumber((record.prizes or {})[state.favor]) or 0)
end

-- 376 SetFavorLadyState_Complete: a clean slate and a NEW adjective, then
-- phase one -- which is the "thank you for last time" she greets you with
-- until whatever resets her comes round.
Gen3Commands.SPECIALS[376] = function(ctx)
  local state, record = favorLady(ctx)
  if not state then return end
  state.liked, state.given, state.item, state.name = false, 0, nil, nil
  rollFavor(state, record)
  state.phase = 1
end

-- ---------------------------------------------------------------------------
-- THE QUIZ LADY, the first of Lilycove's three -- and the one who needed the
-- easy chat picker before she could exist at all.
--
-- She asks one of sixteen questions written in EASY CHAT WORDS and wants one
-- word back.  Get it right and you take the item she was holding for that
-- quiz; get it wrong and she keeps it.  Then she offers you the other half of
-- her: pick a prize out of your own bag, write nine words and an answer, and
-- she holds your prize until somebody else gets it right.
--
-- HER RECORD IS THE SAME UNION as the Favor Lady's, at the same offset, and
-- which of the three women is in the lobby is your trainer id -- so two
-- players in three never meet her either.
--
-- THREE STATES, and her script reads them in this order: 0 is "I have a quiz
-- for you", 1 is "somebody has already answered it", 2 is "you won, come and
-- take your prize".  The numbers are the cartridge's own -- the two specials
-- that write them write different values to the same byte, which is how the
-- extractor identifies it.
-- ---------------------------------------------------------------------------
local function quizRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  return (data and data.constants or {}).gen3QuizLady
end

function Gen3Commands.quizLady(ctx)
  local record = quizRecord(ctx)
  local state = Gen3Commands.lilycoveLady(ctx)
  if not (record and state) then return nil end
  if state.id ~= (tonumber(record.lady) or 0) then return nil end
  if type(state.quiz) ~= "table" then
    state.quiz = { state = 0, answer = 0 }
  end
  if not state.quiz.which then Gen3Commands.quizPick(ctx, state.quiz, record) end
  return state.quiz, record
end

-- QuizLadyPickNewQuestion: one of the sixteen, at random, and everything that
-- goes with it -- the words, the word that wins and the item she holds.  A
-- quiz the PLAYER wrote is left alone; picking a new one is what clears it.
function Gen3Commands.quizPick(ctx, quiz, record)
  local list = record.quizzes or {}
  if #list == 0 then return end
  local pick = math.floor(love.math.random(1, #list))
  local row = list[pick]
  quiz.which = pick
  quiz.words = {}
  for i, id in ipairs(row.words or {}) do quiz.words[i] = id end
  quiz.correct = math.floor(tonumber(row.answer) or 0)
  quiz.prize = math.floor(tonumber(row.prize) or 0)
  quiz.answer = 0
  quiz.author = nil
  quiz.state = 0
end

-- 377 GetQuizLadyState
Gen3Commands.SPECIALS[377] = function(ctx)
  local quiz, record = Gen3Commands.quizLady(ctx)
  if not quiz then return 0 end
  local states = (record.record or {}).states or {}
  local now = math.floor(tonumber(quiz.state) or 0)
  if now == (tonumber(states.prize) or 2) then return 2 end
  return now == (tonumber(states.complete) or 1) and 1 or 0
end

-- 378 GetQuizAuthor: 0 is you, 1 is the lady herself, 2 is somebody whose
-- record you mixed with.  With no link cable there is no third answer.
Gen3Commands.SPECIALS[378] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  if not quiz then return 1 end
  local mine = tostring((ctx.save.player or {}).name or "")
  if quiz.author == nil then return 1 end
  return quiz.author == mine and 0 or 2
end

-- 379 IsQuizLadyWaitingForChallenger / 394 QuizLadySetWaitingForChallenger
Gen3Commands.SPECIALS[379] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  return (quiz and quiz.waiting) and 1 or 0
end
Gen3Commands.SPECIALS[394] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  if quiz then quiz.waiting = true end
end

-- 380 QuizLadyShowQuizQuestion: the question on screen, and the one word you
-- answer it with.  VAR_0x8004 is which caller it is, exactly as the easy chat
-- screen's own special uses it -- 0 is answering, the higher one is writing.
--
-- BLOCKING: the row after it is `waitstate`.
Gen3Commands.SPECIALS[380] = function(ctx)
  local quiz, record = Gen3Commands.quizLady(ctx)
  local game, runner = ctx.game, ctx.runner
  setVar(ctx.save, VAR_RESULT, 0)
  if not (quiz and game and runner) then return end
  local ok, Screen = pcall(require, "src.ui.Gen3EasyChat")
  if not ok then return end

  -- THE QUESTION HAS TO BE ON SCREEN, and her script never prints it: on the
  -- cartridge the easy chat screen draws the question above the slot you are
  -- filling in.  This port's picker is a menu with no room for a line of its
  -- own, so the question is read out first and the picker opens behind it --
  -- which is the same two beats in the same order, and means the player is
  -- never asked to answer a question they have not been shown.
  local function pick()
    local opened = Screen.open(game, {
      count = 1,
      onDone = function(words)
        quiz.answer = math.floor(tonumber((words or {})[1]) or 0)
        setVar(ctx.save, VAR_RESULT, 1)
        runner:resume()
      end,
      onCancel = function()
        setVar(ctx.save, VAR_RESULT, 0)
        runner:resume()
      end,
    })
    if not opened then runner:resume() end
  end

  local question = Gen3Commands.quizText(ctx, quiz, record)
  local okBox, TextBox = pcall(require, "src.render.TextBox")
  if okBox and game.stack and question ~= "" then
    local shown = pcall(game.stack.push, game.stack,
                        TextBox.new(game, question, pick))
    if not shown then pick() end
  else
    pick()
  end
  runner:yield()
end

-- Her question as a line of words, which is what the picker shows above the
-- slot.  Blank words are the padding a shorter question is written with.
function Gen3Commands.quizText(ctx, quiz, record)
  local EasyChat = require("src.script.EasyChat")
  local data = ctx.game and ctx.game.data
  local parts = {}
  for _, id in ipairs((quiz and quiz.words) or {}) do
    local word = EasyChat.text(data, id)
    if word and word ~= "" then parts[#parts + 1] = word end
  end
  return table.concat(parts, " ")
end

-- 381 QuizLadyGetPlayerAnswer -- the cartridge reads the picker's own buffer
-- here; this port put the word straight on the record when the picker closed,
-- so there is nothing left to fetch.
Gen3Commands.SPECIALS[381] = function() end

-- 382 IsQuizAnswerCorrect
Gen3Commands.SPECIALS[382] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  if not quiz then return 0 end
  local mine = math.floor(tonumber(quiz.answer) or 0)
  return (mine ~= 0 and mine == math.floor(tonumber(quiz.correct) or 0))
         and 1 or 0
end

-- 383 BufferQuizPrizeItem: the item id into VAR_0x8004, which is what the
-- `giveitem` after it reads.
Gen3Commands.SPECIALS[383] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  setVar(ctx.save, 0x8004, quiz and math.floor(tonumber(quiz.prize) or 0) or 0)
end

-- 384 SetQuizLadyState_Complete / 386 SetQuizLadyState_GivePrize
Gen3Commands.SPECIALS[384] = function(ctx)
  local quiz, record = Gen3Commands.quizLady(ctx)
  if quiz then
    quiz.state = math.floor(tonumber((record.record or {}).states.complete) or 1)
  end
end
Gen3Commands.SPECIALS[386] = function(ctx)
  local quiz, record = Gen3Commands.quizLady(ctx)
  if quiz then
    quiz.state = math.floor(tonumber((record.record or {}).states.prize) or 2)
  end
end

-- 385 BufferQuizAuthorNameAndCheckIfLady: her own quiz answers 1 and puts her
-- title in the buffer; a quiz somebody wrote answers 0 and puts their name.
Gen3Commands.SPECIALS[385] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  if not quiz then return 1 end
  ctx.save.buffers = ctx.save.buffers or {}
  if quiz.author == nil then
    ctx.save.buffers[1] = "QUIZ LADY"
    return 1
  end
  ctx.save.buffers[1] = tostring(quiz.author)
  return 0
end

-- 387 ClearQuizLadyPlayerAnswer / 389 ClearQuizLadyQuestionAndAnswer
Gen3Commands.SPECIALS[387] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  if quiz then quiz.answer = 0 end
end
Gen3Commands.SPECIALS[389] = function(ctx)
  local quiz, record = Gen3Commands.quizLady(ctx)
  if not quiz then return end
  quiz.answer, quiz.correct = 0, 0
  quiz.words = {}
  for i = 1, math.floor(tonumber(record.words) or 9) do quiz.words[i] = 0 end
end

-- 388 Script_QuizLadyOpenBagMenu -- the prize for a quiz you are writing comes
-- out of your own bag, and she keeps it until somebody wins it.
--
-- BLOCKING: the row after it is `waitstate`.
Gen3Commands.SPECIALS[388] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  local game, runner = ctx.game, ctx.runner
  setVar(ctx.save, VAR_RESULT, 0)
  if not (quiz and game and game.stack and runner) then return end
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return end
  local order = (game.data and game.data.constants or {}).itemOrder
  local pushed = pcall(Screens.push, game, "Gen3BagMenu", {
    pick = true,
    onCancel = function() runner:resume() end,
    onPick = function(itemId)
      for n, id in ipairs(order or {}) do
        if id == itemId then quiz.pick = n break end
      end
      setVar(ctx.save, VAR_RESULT, quiz.pick and 1 or 0)
      runner:resume()
    end,
  })
  if pushed then runner:yield() end
end

-- 390 QuizLadySetCustomQuestion: nine words for the question and one for the
-- answer, on the same picker the quiz itself is shown on.
Gen3Commands.SPECIALS[390] = function(ctx)
  local quiz, record = Gen3Commands.quizLady(ctx)
  local game, runner = ctx.game, ctx.runner
  setVar(ctx.save, VAR_RESULT, 0)
  if not (quiz and game and runner) then return end
  local ok, Screen = pcall(require, "src.ui.Gen3EasyChat")
  if not ok then return end
  local count = math.floor(tonumber(record.words) or 9)
  local opened = Screen.open(game, {
    count = count,
    words = quiz.words,
    onDone = function(words)
      quiz.words = {}
      for i = 1, count do
        quiz.words[i] = math.floor(tonumber((words or {})[i]) or 0)
      end
      setVar(ctx.save, VAR_RESULT, 1)
      runner:resume()
    end,
    onCancel = function()
      setVar(ctx.save, VAR_RESULT, 0)
      runner:resume()
    end,
  })
  if opened then runner:yield() end
end

-- 391 QuizLadyTakePrizeForCustomQuiz -- she takes the item off you now, not
-- when somebody wins it.
Gen3Commands.SPECIALS[391] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  if not (quiz and quiz.pick) then return end
  local id = Gen3Commands.itemId(ctx.game and ctx.game.data, quiz.pick)
  if id then pcall(Commands.take_item, ctx, id, 1) end
end

-- 392 GetMysteryGiftCardStat -- the wonder card's own counter, and there is
-- no wonder card in this port.
Gen3Commands.SPECIALS[392] = function() return 0 end

-- 393 QuizLadyRecordCustomQuizData: the quiz becomes yours -- your prize,
-- your answer, your name on it.
Gen3Commands.SPECIALS[393] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  if not quiz then return end
  quiz.correct = math.floor(tonumber(quiz.answer) or 0)
  quiz.answer = 0
  quiz.prize = math.floor(tonumber(quiz.pick) or 0)
  quiz.pick = nil
  quiz.author = tostring((ctx.save.player or {}).name or "")
  quiz.waiting = true
  quiz.state = 0
end

-- 395 BufferQuizCorrectAnswer -- the word she reveals when you get it wrong.
Gen3Commands.SPECIALS[395] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  if not quiz then return end
  local EasyChat = require("src.script.EasyChat")
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[3] =
    EasyChat.text(ctx.game and ctx.game.data, quiz.correct) or ""
end

-- 396 BufferQuizPrizeName
Gen3Commands.SPECIALS[396] = function(ctx)
  local quiz = Gen3Commands.quizLady(ctx)
  if not quiz then return end
  local data = ctx.game and ctx.game.data
  local id = Gen3Commands.itemId(data, quiz.prize)
  local def = id and ((data or {}).items or {})[id]
  ctx.save.buffers = ctx.save.buffers or {}
  ctx.save.buffers[1] = (def and def.name) or id or ""
end

-- 397 QuizLadyPickNewQuestion
Gen3Commands.SPECIALS[397] = function(ctx)
  local quiz, record = Gen3Commands.quizLady(ctx)
  if quiz then
    quiz.waiting = nil
    Gen3Commands.quizPick(ctx, quiz, record)
  end
end



-- ---------------------------------------------------------------------------
-- 132: GetDewfordHallPaintingNameIndex -- the hall on DEWFORD's north side.
--
-- The painting is named after the town's TREND, the two easy-chat words
-- everybody there is repeating, and the two words are ADDED rather than
-- concatenated before the low three bits pick which of four descriptions the
-- script reads out.  Unserved, VAR_RESULT stayed whatever it was and the hall
-- fell through every branch.
--
-- ZERO IS A REAL ANSWER, not a placeholder: before anyone in DEWFORD has said
-- anything the cartridge's own two words are zero and the index is zero.  An
-- imported save brings its trend across, so a file that HAS a trend hangs the
-- painting that trend earned.
Gen3Commands.SPECIALS[132] = function(ctx)
  local data = ctx.game and ctx.game.data
  local record = data and data.constants
                 and data.constants.gen3DewfordPainting
  local mask = math.floor(tonumber(record and record.mask) or 7)
  local trend = ctx.save and ctx.save.gen3DewfordTrend
  local a = math.floor(tonumber(type(trend) == "table" and trend[1]) or 0)
  local b = math.floor(tonumber(type(trend) == "table" and trend[2]) or 0)
  setVar(ctx.save, VAR_RESULT, (a + b) % (mask + 1))
end


-- ---------------------------------------------------------------------------
-- 504: ShouldDistributeEonTicket, and 503: SetMewAboveGrass.
--
-- Both belong to EVENT DISTRIBUTIONS, and both have an honest answer here.
--
-- 504 is one line in the cartridge -- `VarGet($403F) != 0` -- and that var is
-- set by a Mystery Gift the machine never received, so a retail cartridge
-- with no event answers FALSE too.  Serving it as the read it is means a save
-- that DOES carry the var gets the ticket, which is the parity that matters.
--
-- 503 is FARAWAY ISLAND's Mew, and all it does is clear and set the object's
-- subpriority bit so the sprite draws over the tall grass rather than under
-- it.  This port draws overworld objects on one plane, so there is no bit to
-- set -- and the island itself needs the Old Sea Map, which is the same
-- distribution 504 is waiting on.  A nop with its reason written down beats
-- an invented elevation.
Gen3Commands.EON_TICKET_VAR = 0x403F

Gen3Commands.SPECIALS[504] = function(ctx)
  local id = Gen3Commands.EON_TICKET_VAR
  return (math.floor(tonumber(getVar(ctx.save, id)) or 0) ~= 0) and 1 or 0
end

-- ---------------------------------------------------------------------------
-- THE SS TIDAL, Hoenn's ferry -- two specials that only work as a pair.
--
-- 500 builds the list of places the ship will take you FROM WHERE YOU ARE
-- STANDING, and 501 turns the row you picked back into a place.  Both were
-- unserved, so the sailor's menu came up empty and the branch after it read
-- whatever VAR_RESULT was last left holding.
--
-- THE ROW IS NOT THE DESTINATION.  Every destination is appended only if you
-- can go there, so the menu is a different length in different saves and the
-- third row means a different island depending on which tickets are in the
-- bag.  That is the whole reason for the second special, and why serving one
-- without the other would be worse than serving neither.
--
-- WHAT EACH ONE COSTS is derived (see extractSSTidal): the first two are the
-- port's own two, gated on where you are standing and one flag; the four
-- ISLANDS each want a TICKET IN THE BAG and the flag that opens the place;
-- and the last row is always there because it is the way out.
--
-- THE ONE-SHOT ARM.  Standing at the OTHER dock, an island is offered only
-- while its own second flag is clear -- and offering it sets that flag.  That
-- is the cartridge's own arm and it is kept: it is what stops the far dock
-- listing an island you have already been told about from there.
-- THE FOUR NAMES BELOW HANG OFF THE MODULE TABLE rather than being file
-- locals.  This chunk is already at Lua's 200-local ceiling and one more at
-- file scope will not load -- the limit counts locals live at that point, so
-- a `do` block does not buy anything here either.  Same reason
-- RomExtractorGen3 keeps its constants on its own table.
Gen3Commands.TIDAL_PORT_VAR = 0x8004
Gen3Commands.TIDAL_CANCEL = 127

function Gen3Commands.tidalRecord(ctx)
  local data = ctx and ctx.game and ctx.game.data
  return (data and data.constants or {}).gen3SSTidal
end

-- Which destinations this save can reach from this dock, in the cartridge's
-- own order.  `commit` is what the far dock's one-shot arm needs: asking is
-- not free there, so the flags are only written when the menu is really
-- being built.
function Gen3Commands.tidalDestinations(ctx, commit)
  local record = Gen3Commands.tidalRecord(ctx)
  if not record then return nil end
  local save = ctx.save
  local flags = (save and save.flags) or {}
  local here = math.floor(tonumber(getVar(save, Gen3Commands.TIDAL_PORT_VAR)) or 0)
  local out = {}
  for _, row in ipairs(record.destinations or {}) do
    local ok
    if #(row.flags or {}) == 0 and not row.item then
      -- the port's own row and the way out: the first is only offered from
      -- the near dock, and the last from either
      ok = (row.id == 0) and here == 0 or (row.id == (record.size or 7) - 1)
    elseif not row.item then
      ok = here == 0 and flags[Gen3Commands.flagKey(row.flags[1])] == true
    else
      local held = Gen3Commands.tidalHasTicket(ctx, row.item)
      local open = flags[Gen3Commands.flagKey(row.flags[1])] == true
      if held and open then
        if here == 0 then
          ok = true
        elseif row.flags[2] then
          local key = Gen3Commands.flagKey(row.flags[2])
          if flags[key] ~= true then
            ok = true
            if commit and save then
              save.flags = save.flags or {}
              save.flags[key] = true
            end
          end
        end
      end
    end
    if ok then out[#out + 1] = row end
  end
  return out, record
end

-- Is one of the four tickets in the bag?  The bag is keyed by item name --
-- the same key `checkitem` uses -- and the derivation carries both that name
-- and the cartridge's own number for it.
function Gen3Commands.tidalHasTicket(ctx, name)
  if not name then return false end
  local bag = (ctx.save or {}).inventory or {}
  return (tonumber(bag[name]) or 0) > 0
end

-- 500 ScriptMenu_CreateLilycoveSSTidalMultichoice.  BLOCKING: the row after
-- it is `waitstate`.
--
-- When every destination is available the cartridge does not draw the menu
-- itself -- it hands a numbered SCROLLING list to the same routine thirteen
-- other counters use.  That list's rows are the same seven words, so this
-- serves both cases off the one derivation and only differs in how many rows
-- go on the screen.
Gen3Commands.SPECIALS[500] = function(ctx)
  local list, record = Gen3Commands.tidalDestinations(ctx, true)
  if not list or #list == 0 then
    setVar(ctx.save, VAR_RESULT, Gen3Commands.TIDAL_CANCEL)
    return
  end
  local labels, ids = {}, {}
  for i, row in ipairs(list) do
    labels[i] = tostring(row.name or "")
    ids[i] = row.id
  end
  -- the picked ROW is kept for 501, which is the special that resolves it
  ctx.save.gen3Tidal = { rows = ids }
  local scroll = (ctx.game.data.constants or {}).gen3ScrollMultichoice
  local entry = scroll and scroll.lists and scroll.lists[record.list]
  local visible = entry and tonumber(entry.visible) or nil
  local picked = Gen3Commands.listPick(ctx, labels, nil, visible)
  setVar(ctx.save, VAR_RESULT, picked and (picked - 1) or Gen3Commands.TIDAL_CANCEL)
end

-- 501 GetLilycoveSSTidalSelection: the row becomes the place.  A cancelled
-- menu is left alone, because 127 is what the script compares against.
Gen3Commands.SPECIALS[501] = function(ctx)
  local row = math.floor(tonumber(getVar(ctx.save, VAR_RESULT)) or 0)
  if row == Gen3Commands.TIDAL_CANCEL then return end
  local kept = (ctx.save or {}).gen3Tidal
  local id = kept and kept.rows and kept.rows[row + 1]
  if id == nil then
    -- nothing was built this session: answer the row unchanged rather than
    -- an island the player never chose
    return
  end
  setVar(ctx.save, VAR_RESULT, id)
end


-- ---------------------------------------------------------------------------
-- THE BATTLE FRONTIER'S THIRTEEN DISPATCHERS.
--
-- These are NOT implementations and are not pretending to be.  Each facility
-- is a whole game mode and none of them is ported.  What they replace is
-- worse than nothing: an unserved arm used to reach the generic "special 234
-- not implemented", six hundred and forty-nine times, the same three words
-- for twenty-three different functions -- so a report of "the Battle
-- Frontier does not work" could not be turned into anything actionable.
--
-- A dispatcher takes a function NUMBER in VAR_0x8004 and jumps through a
-- table; extractBattleFrontier reads all thirteen tables and records which
-- arms the region's scripts actually reach.  With that in hand these can say
-- WHICH facility and WHICH of its functions was asked for, answer the
-- neutral zero the scripts compare against, and get out of the way.
--
-- They answer 0 rather than leaving VAR_RESULT alone deliberately: a script
-- that branches on a stale VAR_RESULT walks somewhere the player cannot get
-- out of, and zero is the "no / not yet / none" arm of every one of these.
function Gen3Commands.frontierCall(ctx, facility)
  local data = ctx.game and ctx.game.data
  local record = (data and data.constants or {}).gen3Frontier
  local entry = record and record.facilities and record.facilities[facility]
  local arg = math.floor(tonumber(getVar(ctx.save,
    (record and record.argVar) or 0x8004)) or 0)
  if entry then
    local known = false
    for _, arm in ipairs(entry.used or {}) do if arm == arg then known = true end end
    Logger.debug("gen3 frontier: %s function %d is not ported%s",
                 facility, arg,
                 known and "" or " (and no script in the region asks for it)")
  else
    Logger.debug("gen3 frontier: %s function %d is not ported", facility, arg)
  end
  setVar(ctx.save, VAR_RESULT, 0)
  return 0
end

-- the loop's own two names are block-scoped: this chunk is at Lua's
-- 200-local ceiling (see the SS Tidal above)
Gen3Commands.FRONTIER_FACILITIES = {
  [234] = "frontierUtil", [235] = "battleTower", [236] = "battleDome",
  [237] = "battlePalace", [240] = "battleArena", [241] = "battleFactory",
  [242] = "battlePike", [243] = "battlePyramid", [245] = "verdanturfTent",
  [246] = "fallarborTent", [247] = "slateportTent", [407] = "apprentice",
  [507] = "trainerHill",
}

Gen3Commands.installFrontierDispatchers = function()
  for special, facility in pairs(Gen3Commands.FRONTIER_FACILITIES) do
    Gen3Commands.SPECIALS[special] = function(ctx)
      return Gen3Commands.frontierCall(ctx, facility)
    end
  end
end
Gen3Commands.installFrontierDispatchers()

-- ---------------------------------------------------------------------------
-- THE LINK, ANSWERED THE WAY A CARTRIDGE WITH NOTHING PLUGGED IN ANSWERS IT.
--
-- Sixty-odd call sites across Hoenn belong to hardware this port does not
-- have and is not pretending to have: a serial cable and a wireless adapter.
-- The port DOES have link play -- src/link/LinkState.lua, peer to peer over
-- the network -- but it is a different thing reached by its own route, not a
-- reimplementation of the GBA's serial handshake, and no script on this
-- cartridge knows about it.
--
-- SO THE HONEST ANSWER IS THE ONE THE CARTRIDGE ITSELF GIVES with nothing
-- attached, and the scripts prove that is a real, supported state rather than
-- a hole -- every one of them already has the arm for it:
--
--     specialvar VAR_RESULT, 415        <- IsWirelessAdapterConnected
--     compare_var_to_value VAR_RESULT, 0
--     goto_if 1, <the rest of the conversation>
--
-- That branch is not an error path.  It is what the shop assistant says when
-- you have not bought the adapter, and until now the port never reached it:
-- an unimplemented special left VAR_RESULT holding whatever the last script
-- put there, so the answer to "have you got an adapter" was a coin toss.
--
-- WHAT IS *NOT* IN THIS BLOCK is anything that would leave the player stuck.
-- The two cable-club warps are served properly further down, because the room
-- they lead to is a real map with a real door.
-- ---------------------------------------------------------------------------

-- The two contest questions are the same function twice over: one byte of
-- link-contest flags, and a single bit of it each.  Nothing in a game with no
-- partner ever sets that byte, so both are nought -- but they are named here
-- rather than lumped in with the no-ops because they ANSWER, and a question
-- left unanswered keeps whatever the last script left in VAR_RESULT.
Gen3Commands.LINK_ABSENT = 0

-- the loop's own two names live inside a function, because this chunk is at
-- Lua's 200-local ceiling (see the SS Tidal and the Frontier dispatchers)
Gen3Commands.LINK_QUESTIONS = {
  415,  -- IsWirelessAdapterConnected
  439,  -- IsWirelessContest
  443,  -- IsContestWithRSPlayer
  437,  -- LinkContestTryShowWirelessIndicator (answers, and shows nothing)
}

Gen3Commands.installLinkAnswers = function()
  for _, id in ipairs(Gen3Commands.LINK_QUESTIONS) do
    if Gen3Commands.SPECIALS[id] == nil then
      Gen3Commands.SPECIALS[id] = function(ctx)
        setVar(ctx.save, VAR_RESULT, Gen3Commands.LINK_ABSENT)
        return Gen3Commands.LINK_ABSENT
      end
    end
  end
  for _, id in ipairs(Gen3Commands.LINK_SILENT) do
    if Gen3Commands.SPECIALS[id] == nil then
      Gen3Commands.SPECIALS[id] = function() end
    end
  end
end

-- ...and the ones that DO something to a link rather than asking about one.
-- With no link there is nothing to close, hide, clear, retire or repaint, and
-- every one of these is followed in its own script either by nothing at all
-- or by a branch that the untouched variables already take.
--
-- These are no-ops in the same sense `showmoneybox` is: the cartridge does
-- something visible and this port does not, and saying so once here is better
-- than sixty warnings a session from scripts that are behaving correctly.
Gen3Commands.LINK_SILENT = {
  32,   -- CloseLink
  27,   -- RecordMixingPlayerSpotTriggered
  33,   -- ColosseumPlayerSpotTriggered
  34,   -- PlayerEnteredTradeSeat
  416,  -- TryBecomeLinkLeader
  417,  -- TryJoinLinkGroup
  438,  -- LinkContestTryHideWirelessIndicator
  444,  -- ClearLinkContestFlags
  453,  -- SetBattleTowerLinkPlayerGfx
  505,  -- LinkRetireStatusWithBattleTowerPartner
  517,  -- LoadLinkContestPlayerPalettes
}

Gen3Commands.installLinkAnswers()

-- ---------------------------------------------------------------------------
-- THE CABLE CLUB'S OWN TWO WARPS, which are not link at all.
--
-- Above the counter of every POKeMON CENTER there is a room, and it is a real
-- map with real furniture whether or not anybody is at the other end of a
-- cable.  Walking up to it is these two specials and nothing else:
--
--     special 1        <- SetCableClubWarp: remember where I came from
--     setwarp <room>   <- name the destination
--     special 2        <- DoCableClubWarp: take it
--     waitstate
--
-- With 2 unimplemented the destination was named and then dropped, and the
-- stairs did nothing -- the same shape of bug the contest hall doors had
-- before special 302 was written, and this takes the warp the same way.
--
-- Some of the five call sites use `warp` rather than `setwarp`, which this
-- port takes on the spot; there is nothing pending by the time 2 runs, and
-- doing nothing is right rather than warping the player a second time.
Gen3Commands.SPECIALS[1] = function(ctx)
  local save = ctx.save
  local player = save and save.player
  if not (player and player.map) then return end
  save.gen3CableClubReturn = { map = player.map, x = player.x, y = player.y }
end

Gen3Commands.SPECIALS[2] = function(ctx)
  local pending = ctx.save and ctx.save.gen3PendingWarp
  if not (pending and pending.group and pending.number) then
    -- the call sites that use `warp` have already arrived
    Logger.debug("gen3 cable club: nothing pending, so the warp was taken by "
                 .. "the script itself")
    return
  end
  Commands.g3_warp(ctx, pending.group, pending.number, pending.warp,
                   pending.x, pending.y)
end

-- ---------------------------------------------------------------------------
-- CHOOSING A TEAM: 248, 42 and 251 -- the doors into the Battle Frontier.
--
-- gSpecials[248] was the most-called unserved special on the cartridge: 34
-- sites, one at the entrance of every Frontier facility and both Battle
-- Tents.  gSpecials[42] is the same screen for the link colosseum, and
-- gSpecials[251] is what happens to your party afterwards.
--
-- HOW MANY IS NOT IN EITHER SPECIAL.  Both compute an argument and hand it to
-- a function that discards it; the real answer is in two little functions
-- further in, one saying the most the screen will take and the other the
-- fewest it will accept, and the import derives both (see
-- RomExtractorGen3:partyChoice).  The rule:
--
--     the facility variable is 8 or 9   -- a multi battle -- fixed numbers
--     otherwise                         -- whatever the script put in
--                                          VAR_0x8005, which every one of
--                                          the 34 sites sets immediately
--                                          before the call
--
-- WHAT THE SCRIPT DOES NEXT is compare VAR_RESULT against zero, so a screen
-- that closed without answering would send the player straight back out of a
-- door they just opened.  One is "they chose"; nought is "they walked away".
Gen3Commands.PARTY_CHOICE_FALLBACK = 3

function Gen3Commands.partyChoiceRecord(ctx)
  local data = ctx.game and ctx.game.data
  return (data and data.constants or {}).gen3PartyChoice
end

-- The two bounds, for the facility this save is standing in.
function Gen3Commands.partyChoiceBounds(ctx)
  local record = Gen3Commands.partyChoiceRecord(ctx)
  if type(record) ~= "table" then return nil end
  local facility = math.floor(tonumber(
    getVar(ctx.save, record.facilityVar or 0x40CF)) or 0)
  local most = (record.fixed or {})[facility]
  local least = (record.least or {})[facility]
  if not most then
    most = math.floor(tonumber(getVar(ctx.save, record.countVar or 0x8005))
                      or 0)
    least = most
  end
  if not (most and most > 0) then
    -- a script that opened the door without saying how many is the one case
    -- the cartridge cannot reach; three is what every ordinary facility asks
    most = Gen3Commands.PARTY_CHOICE_FALLBACK
    least = most
  end
  local slots = math.floor(tonumber(record.slots) or most)
  if most > slots then most = slots end
  if not least or least < 1 then least = 1 end
  if least > most then least = most end
  return most, least, record
end

function Gen3Commands.chooseParty(ctx)
  local most, least, record = Gen3Commands.partyChoiceBounds(ctx)
  local game, runner = ctx.game, ctx.runner
  if not (most and game and game.stack and runner) then
    -- NO SCREEN TO OPEN IS NOT "THEY CHOSE".  Answering nought sends the
    -- script back out of the door, which is where a player who cannot be
    -- shown the menu belongs -- answering one would walk them into a
    -- facility with a team nobody picked.
    Logger.warn("gen3 party choice: there is no screen to choose on -- the "
                .. "door is answered as declined")
    setVar(ctx.save, VAR_RESULT, 0)
    return
  end
  local answered = false
  local function done(slots)
    if answered then return end
    answered = true
    if slots and #slots > 0 then
      ctx.save.gen3SelectedOrder = slots
      setVar(ctx.save, VAR_RESULT, 1)
    else
      ctx.save.gen3SelectedOrder = nil
      setVar(ctx.save, VAR_RESULT, 0)
    end
    runner:resume()
  end
  local Screens = require("src.ui.Screens")
  local pushed = pcall(function()
    Screens.push(game, "PartyMenu", {
      chooseOrder = { most = most, least = least,
                      messages = (record or {}).messages },
      onOrder = done,
    })
  end)
  if not pushed then
    setVar(ctx.save, VAR_RESULT, 0)
    return
  end
  runner:yield()
end

-- 248: ChoosePartyForBattleFrontier
Gen3Commands.SPECIALS[248] = function(ctx)
  Gen3Commands.chooseParty(ctx)
end

-- 42: ChooseHalfPartyForBattle.  The one thing it does before opening the
-- same screen is set the facility variable, and the number it sets is one of
-- the two the counters special-case -- which is what makes "half your party"
-- a number off the cartridge rather than three guessed from six.
Gen3Commands.SPECIALS[42] = function(ctx)
  local record = Gen3Commands.partyChoiceRecord(ctx)
  if type(record) == "table" and record.halfParty then
    setVar(ctx.save, record.facilityVar or 0x40CF, record.halfParty)
  end
  Gen3Commands.chooseParty(ctx)
end

-- 251: ReducePlayerPartyToSelectedMons.
--
-- The party becomes the chosen team, in the chosen order, and the rest are
-- put aside -- the cartridge stashes them in the save the same way specials
-- 40 and 41 do around every Frontier challenge, which is why this one is
-- always preceded by a 40.  With it unimplemented the door opened, the team
-- was chosen, and six Pokemon walked in.
Gen3Commands.SPECIALS[251] = function(ctx)
  local save = ctx.save
  local order = save and save.gen3SelectedOrder
  if not (save and type(order) == "table" and #order > 0) then
    Logger.warn("gen3 party choice: nothing was chosen, so the party is "
                .. "left as it stands")
    return
  end
  local party, kept = save.party or {}, {}
  for _, slot in ipairs(order) do
    local mon = party[math.floor(tonumber(slot) or 0)]
    if mon then kept[#kept + 1] = mon end
  end
  if #kept == 0 then
    Logger.warn("gen3 party choice: none of the chosen slots holds a "
                .. "Pokemon -- the party is left as it stands")
    return
  end
  save.party = kept
  save.gen3SelectedOrder = nil
end

-- ---------------------------------------------------------------------------
-- THE FRONTIER'S FRONT DESK -- the part of it that needs no facility at all.
--
-- None of the seven facilities is ported, and the census that says how much
-- work that is has been in `constants.gen3Frontier` for a while.  But the
-- lobby is not a facility: the exchange corner sells things, the two counters
-- show a number, and a man near the door shouts at you about whichever
-- challenge you last picked.  Sixty-odd call sites, none of which needs a
-- single battle to be fought -- and all of which refused, because the number
-- underneath them had nowhere to live.
--
-- BATTLE POINTS ARE A PLAIN SAVEBLOCK2 HALFWORD.  Three specials add, take
-- and read them, and every one of the three carries the same offset in its
-- own constant pool -- which is how the import found it and why it is sure.
-- The adder's own `cmp` gives the cap; the taker's own `bcs` gives the floor.
-- Nothing XORs them, unlike the money beside them.
Gen3Commands.BP_DEFAULT_CAP = 9999

function Gen3Commands.battlePoints(ctx)
  return math.floor(tonumber((ctx.save or {}).gen3BattlePoints) or 0)
end

function Gen3Commands.battlePointsCap(ctx)
  local data = ctx.game and ctx.game.data
  local record = (data and data.constants or {}).gen3BattlePoints
  return math.floor(tonumber(record and record.cap)
                    or Gen3Commands.BP_DEFAULT_CAP)
end

function Gen3Commands.setBattlePoints(ctx, n)
  if not ctx.save then return 0 end
  local capped = math.max(0, math.min(Gen3Commands.battlePointsCap(ctx),
                                      math.floor(n)))
  ctx.save.gen3BattlePoints = capped
  return capped
end

-- 458: GiveFrontierBattlePoints -- BP += VAR_0x8004, stopping at the cap
Gen3Commands.SPECIALS[458] = function(ctx)
  local add = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  return Gen3Commands.setBattlePoints(ctx,
                                      Gen3Commands.battlePoints(ctx) + add)
end

-- 459: TakeFrontierBattlePoints -- BP -= VAR_0x8004, stopping at nothing.
-- The cartridge does not subtract past zero; it stores zero, which is what
-- lets a shop charge more than you have without the counter wrapping to
-- sixty-five thousand.
Gen3Commands.SPECIALS[459] = function(ctx)
  local take = math.floor(tonumber(getVar(ctx.save, 0x8004)) or 0)
  return Gen3Commands.setBattlePoints(ctx,
                                      Gen3Commands.battlePoints(ctx) - take)
end

-- 460: GetFrontierBattlePoints.  Read with `specialvar`, so the value is
-- both returned and left in VAR_RESULT -- the shops compare against it and
-- the counter prints it.
Gen3Commands.SPECIALS[460] = function(ctx)
  local n = Gen3Commands.battlePoints(ctx)
  setVar(ctx.save, VAR_RESULT, n)
  return n
end

-- 455/456/457 and 461/462: the two little windows -- the BP counter and the
-- exchange corner's item icon.
--
-- NO-OPS, and deliberately the same no-op `showmoneybox` already is in this
-- port's script VM.  The cartridge draws a floating window over the map; this
-- engine does not draw one for money either, and a counter that appeared for
-- Battle Points and not for cash would be the odd one out rather than the
-- fix.  What matters is that they are SERVED: an unserved special leaves the
-- script warning on every frame it is called from, and 455 and 457 bracket
-- every purchase in the exchange corner.
Gen3Commands.SPECIALS[455] = function() end   -- ShowBattlePointsWindow
Gen3Commands.SPECIALS[456] = function() end   -- UpdateBattlePointsWindow
Gen3Commands.SPECIALS[457] = function() end   -- CloseBattlePointsWindow
Gen3Commands.SPECIALS[461] = function() end   -- ShowExchangeCornerItemIcon
Gen3Commands.SPECIALS[462] = function() end   -- CloseExchangeCornerItemIcon

-- 469: ShowFrontierGamblerGoMessage.
--
-- Twelve lines, one per challenge the Frontier offers, picked by the variable
-- that remembers which one you took.  He is the only thing in the lobby that
-- says something DIFFERENT depending on what you did, so with this
-- unimplemented he stood there mute in front of a script that had already
-- decided what he should say.
--
-- BLOCKING: the cartridge follows it with `waitmessage`.
Gen3Commands.SPECIALS[469] = function(ctx)
  local data = ctx.game and ctx.game.data
  local record = (data and data.constants or {}).gen3FrontierGambler
  local lines = record and record.messages
  if type(lines) ~= "table" or #lines == 0 then
    Logger.warn("gen3 Frontier gambler: this dataset carries none of his "
                .. "lines -- he is passed over rather than left mid-script")
    return
  end
  local pick = math.floor(tonumber(getVar(ctx.save, record.var or 0x4031))
                          or 0)
  local line = lines[pick + 1]
  if not line then
    -- a variable outside the table is the save having taken a challenge this
    -- dataset does not know; the cartridge would index past the table, and
    -- the honest thing is to say the first line rather than read rubbish
    Logger.warn("gen3 Frontier gambler: challenge %d is not one of his %d "
                .. "lines -- the first is used", pick, #lines)
    line = lines[1]
  end
  Commands.show_text(ctx, line)
end


Gen3Commands.SPECIALS[503] = function() end


-- ---------------------------------------------------------------------------
-- 275: GameClear -- BEATING THE GAME, and the flag the rest of Hoenn waits on.
--
-- The champion's room ends `setrespawn / fadescreenspeed / special 275 /
-- waitstate / releaseall`, and with 275 unserved beating the league changed
-- nothing that lasts.  Two of the things it does are what the post-game is
-- gated on, and this port read that flag in two places and wrote it in none:
--
--     HealPlayerParty()
--     if (!FlagGet(FLAG_SYS_GAME_CLEAR)) ... ; FlagSet(FLAG_SYS_GAME_CLEAR)
--
-- so a finished playthrough stayed permanently unfinished -- no HALL OF FAME
-- row on the PC, and every script that asks whether the league is behind you
-- still answering no.
--
-- ...AND THE CHAMPION RIBBON.  GameClear walks the party and sets the one-bit
-- CHAMPION ribbon on each of them, which is what puts the first entry on the
-- POKeNAV's RIBBONS page -- the page that refuses to open with no ribbon
-- anywhere in the party or the boxes.
--
-- WHAT THIS DOES NOT DO is show Emerald's Hall of Fame.  The port has a Hall
-- of Fame screen and it is the GAME BOY's -- its own music, its own dex
-- rating boxes, its own player pic -- so running it here would put Kanto's
-- ceremony at the end of Hoenn.  Emerald's is its own screen with its own
-- art, and it is its own piece of work; the state above is the half the rest
-- of the game actually reads.
-- ---------------------------------------------------------------------------
Gen3Commands.SPECIALS[275] = function(ctx)
  local data = ctx.game and ctx.game.data
  local record = data and data.constants and data.constants.gen3GameClear
  Commands.heal_party(ctx)
  local flag = record and tonumber(record.flag)
  if not flag then
    Logger.warn("gen3 game clear: this dataset has no game-clear flag, so "
                .. "the league is behind you and nothing in Hoenn knows it")
    return
  end
  local save = ctx.save
  save.flags = save.flags or {}
  local first = save.flags[Gen3Commands.flagKey(flag)] ~= true
  save.flags[Gen3Commands.flagKey(flag)] = true
  local okContest, Contest = pcall(require, "src.pokemon.Contest")
  local ribboned = 0
  if okContest then
    for _, mon in ipairs(save.party or {}) do
      local ribbons = Contest.ribbons(mon)
      if ribbons and not ribbons.champion then
        ribbons.champion = true
        ribboned = ribboned + 1
      end
    end
  end
  -- HALL OF FAME No. n.  The cartridge keeps up to fifty induction records in
  -- the save and the ceremony prints which one you are looking at; the
  -- records themselves are a save-block feature this port does not carry, but
  -- the COUNT is what is on screen, so it is what is kept.
  save.hallOfFame = math.floor(tonumber(save.hallOfFame) or 0) + 1
  Logger.info("gen3 game clear: flag %04X set%s, %d champion ribbon(s) given, "
                .. "HALL OF FAME No. %d",
              flag, first and " for the first time" or " again", ribboned,
              save.hallOfFame)

  -- ...AND THEN THE CEREMONY, which is what GameClear's last act is: the
  -- screen goes to the Hall of Fame, the Hall of Fame hands it to the
  -- credits, and the credits put you down at home.
  --
  -- BLOCKING, because the row after this is `waitstate` -- and the row after
  -- THAT is `releaseall`, which is why the walk home has to happen before the
  -- script is let go rather than after it.  The script already chose where
  -- home is: the `setrespawn` two rows above this one is the player's own
  -- bedroom, one index per gender, and OverworldState:healPoint is what turns
  -- that index into a place.
  local game, runner = ctx.game, ctx.runner
  local okHof, Gen3HallOfFame = pcall(require, "src.ui.Gen3HallOfFame")
  local ceremony = okHof and game and game.stack
                   and Gen3HallOfFame.new(game, function()
                         Gen3Commands.goHomeAfterLeague(ctx)
                         if runner then runner:resume() end
                       end) or nil
  if not (ceremony and runner) then
    Logger.warn("gen3 game clear: no ceremony in this dataset -- the league "
                  .. "ends where it was won")
    Gen3Commands.goHomeAfterLeague(ctx)
    return
  end
  game.stack:push(ceremony)
  runner:yield()
end

-- WHERE THE CREDITS PUT YOU DOWN.  The champion's room script sets the
-- respawn to the player's own bedroom before it calls GameClear -- one index
-- per gender -- and that index is the same one a blackout returns to, so this
-- asks the overworld for it rather than naming a map here.
function Gen3Commands.goHomeAfterLeague(ctx)
  local ow = ctx.overworld
  local save = ctx.save
  if not (ow and save) then return end
  local ok, home = pcall(ow.healPoint, ow)
  if not (ok and type(home) == "table" and home.map) then
    Logger.warn("gen3 game clear: nowhere to go home to, so the league ends "
                  .. "where it was won")
    return
  end
  save.lastHeal = { map = home.map, x = home.x, y = home.y }
  -- the same warp a blackout takes, which is the one that knows how to put
  -- the player down facing the right way and clear the bike behind them
  if ow.warpToHealPoint then
    pcall(ow.warpToHealPoint, ow)
  else
    save.player = save.player or {}
    save.player.map, save.player.x, save.player.y = home.map, home.x, home.y
  end
  Logger.info("gen3 game clear: home is %s (%s,%s)", tostring(home.map),
              tostring(home.x), tostring(home.y))
end


return Gen3Commands
