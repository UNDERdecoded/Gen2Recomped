-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT A LOWERED GEN 4 SCRIPT ROW ACTUALLY DOES.
--
-- `Gen4ScriptVM` has lowered Platinum's bytecode into `g4_*` rows since it was
-- written, and NOTHING HAS EVER REGISTERED A HANDLER FOR ONE.  Every row went
-- through `ScriptRunner`'s unknown-command path, which logs and steps over it,
-- so a Sinnoh conversation ran like this:
--
--     [warn] script: unknown command 'g4_lock_all' (skipped)
--     [warn] script: unknown command 'g4_face_player' (skipped)
--     [warn] script: unknown command 'g4_buffer' (skipped)
--     ... show_text ...
--     [warn] script: unknown command 'g4_wait_button' (skipped)
--     [warn] script: unknown command 'g4_check_flag' (skipped)
--     [warn] script: unknown command 'g4_compare_var_value' (skipped)
--
-- which is exactly what was reported: "npcs are appearing for the events but
-- not triggering, npcs are still missing text".  The box opened and shut
-- without waiting, the name placeholders stayed empty, and -- the one that
-- matters most -- every `checkflag` and `comparevar` left the comparison
-- register untouched, so each of the branches after it took whatever the
-- previous script had left there.  A script that is 90% correct and branches
-- at random is not 90% of a conversation.
--
-- This is the other half.  Gen 3's file is the model and a good deal of it is
-- reusable in shape, but the two do NOT share state: Hoenn's vars live in
-- `save.gen3Vars` and Sinnoh's in `save.gen4Vars`, because they are different
-- games with different var maps and one save can hold both.
--
-- THE COMPARISON REGISTER IS THE CARTRIDGE'S, transcribed:
--
--   `Compare(a, b)` (scrcmd.c:879) returns 0 for a<b, **1 for a==b**, 2 for
--   a>b -- note that equality is 1 and not 0 -- and `ScrCmd_GoToIf`
--   (scrcmd.c:1065) indexes `sConditionTable[condition][comparisonResult]`:
--
--        //   <      ==     >
--        { TRUE,  FALSE, FALSE },  // 0  <
--        { FALSE, TRUE,  FALSE },  // 1  ==
--        { FALSE, FALSE, TRUE  },  // 2  >
--        { TRUE,  TRUE,  FALSE },  // 3  <=
--        { FALSE, TRUE,  TRUE  },  // 4  >=
--        { TRUE,  FALSE, TRUE  },  // 5  !=
--
--   `ScrCmd_CheckFlag` writes the FLAG'S OWN VALUE into that register rather
--   than a comparison (scrcmd.c:1105), which is what makes `checkflag` then
--   `gotoif 1` read as "if the flag is set".  Same for `checktrainerflag`.
--
-- VARS ARE IDS FROM 0x4000 (`VARS_START = 16384`, generated/vars_flags.txt),
-- and any operand below that is a literal -- the same rule Hoenn uses, which
-- is why `valueOf` looks familiar.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")

local Gen4Commands = {}

local VARS_START = 0x4000

-- ---------------------------------------------------------------------------
-- vars
-- ---------------------------------------------------------------------------

local function varStore(save)
  if not save then return nil end
  save.gen4Vars = save.gen4Vars or {}
  return save.gen4Vars
end

local function getVar(save, id)
  local store = varStore(save)
  return (store and store[tonumber(id) or 0]) or 0
end

local function setVar(save, id, value)
  local store = varStore(save)
  if store then store[tonumber(id) or 0] = tonumber(value) or 0 end
end

-- WHERE THE VAR RANGE ENDS, which is not at 0xFFFF on any of the three.
-- Each cartridge's var reader returns the operand itself when its pointer
-- lookup gives NULL (Pt FieldSystem_TryGetVar, HGSS FieldSystem_VarGet, BW
-- ov10 0x0215901C), and that lookup is:
--   * Platinum (script_manager.c FieldSystem_GetVarPointer): 0x4000..0x7FFF
--     the save's vars, 0x8000+ ScriptManager_GetMemberPtr(SCRIPT_DATA_START +
--     id - 0x8000), whose switch knows 14 members -- 0x8000..0x800D -- and
--     returns NULL past them;
--   * HGSS (script_manager.c GetVarPointer): the same, through
--     FieldSysGetAttrAddrInternal's 14 SPECIAL_VAR cases (NUM_SPECIAL_VARS);
--   * BW (ov10 0x02158FE0, READ): < 0x4000 NULL, 0x4000..0x7FFF the save's
--     (arm9 0x020143CC, base + (id - 0x4000) * 2), 0x8000..0xBFFF the
--     context's temps (ov10 0x02158FD0, ctx + 0x7C + (id - 0x8000) * 2),
--     0xC000 and up NULL.
-- So 0xFFFF -- BW's "the zone's own weather" (0x136), a setposition height of
-- -1 (0x6D, Z120) -- is a literal everywhere, and so is 0x800E..0xFFFF on
-- Gen 4. (Save vars past the real count, 0x4000 + NUM_VARS .. 0x7FFF, read
-- past the array on the cartridge; here they are ordinary entries.)
local SPECIAL_TOP = { platinum = 0x800D, hgss = 0x800D, bw = 0xBFFF }
local function varTop()
  local ok, GV = pcall(require, "src.core.GameVersion")
  local fam = ok and GV.family and GV.family() or nil
  return SPECIAL_TOP[fam] or 0xFFFF
end

local function isVarId(n)
  n = tonumber(n)
  return n ~= nil and n >= VARS_START and (n < 0x8000 or n <= varTop())
end
Gen4Commands.isVarId = isVarId

-- An operand is a var when it names one and a literal when it does not.
local function valueOf(ctx, n)
  if isVarId(n) then return getVar(ctx.save, n) end
  return tonumber(n) or 0
end

Gen4Commands.getVar, Gen4Commands.setVar = getVar, setVar
Gen4Commands.valueOf = valueOf

-- ---------------------------------------------------------------------------
-- the comparison register
-- ---------------------------------------------------------------------------

-- [condition][result + 1], transcribed from sConditionTable above.
local CONDITION = {
  [0] = { true,  false, false },
  [1] = { false, true,  false },
  [2] = { false, false, true  },
  [3] = { true,  true,  false },
  [4] = { false, true,  true  },
  [5] = { true,  false, true  },
}

local function compare(a, b)
  if a < b then return 0 end
  if a > b then return 2 end
  return 1
end

local function setResult(ctx, result)
  ctx.g4Compare = result
  -- `lastCheck` is what the engine's own `jump_if_true` / `jump_if_false`
  -- read, and a Gen 4 script reaches those through the shared verbs
  -- (`check_flag`, `ask`), so the two registers are kept in step rather than
  -- left to disagree.
  ctx.lastCheck = result == 1
end

local function holds(ctx, condition)
  local row = CONDITION[tonumber(condition) or 1]
  if not row then return false end
  return row[(ctx.g4Compare or 1) + 1] == true
end

Gen4Commands.compare, Gen4Commands.holds = compare, holds

-- BLACK / WHITE'S STACK EXPRESSIONS, run as the cartridge runs them (overlay
-- 10's 0x08 / 0x09 / 0x10 pushes and 0x11's operators: 0 < 1 == 2 > 3 <=
-- 4 >= 5 != 6 OR 7 AND). The program is (kind, value) pairs, postfix. The
-- answer lands in the compare register as "equal" for true and "less" for
-- false, so `g4_jump_if 0` jumps when it fails, like 0x1F 0xFF.
local BW_OPS = {
  [0] = function(a, b) return a < b end, function(a, b) return a == b end,
  function(a, b) return a > b end, function(a, b) return a <= b end,
  function(a, b) return a >= b end, function(a, b) return a ~= b end,
  function(a, b) return a == 1 or b == 1 end, function(a, b) return a == 1 and b == 1 end,
}
function Commands.g4_bw_eval(ctx, ...)
  local program, stack = { ... }, {}
  for i = 1, #program - 1, 2 do
    local kind, value = program[i], program[i + 1]
    if kind == 1 then stack[#stack + 1] = value
    elseif kind == 2 then stack[#stack + 1] = tonumber(valueOf(ctx, value)) or 0
    elseif kind == 3 then
      -- through the shared flag check, which knows the special flags
      Commands.check_flag(ctx, ("FLAG_G4_%04X"):format(value))
      stack[#stack + 1] = ctx.lastCheck and 1 or 0
    elseif kind == 4 then
      local b, a = table.remove(stack) or 0, table.remove(stack) or 0
      local f = BW_OPS[value]
      stack[#stack + 1] = (f and f(a, b)) and 1 or 0
    end
  end
  setResult(ctx, (stack[#stack] == 1) and 1 or 0)
end

-- ---------------------------------------------------------------------------
-- control flow
-- ---------------------------------------------------------------------------

-- `call` lowers to `g4_call <ret>` / `jump <to>` / `label <ret>`, so the row
-- only has to remember where to come back to; the jump beside it does the
-- going.
function Commands.g4_call(ctx, returnLabel)
  ctx.g4Stack = ctx.g4Stack or {}
  ctx.g4Stack[#ctx.g4Stack + 1] = returnLabel
end

function Commands.g4_return(ctx)
  local stack = ctx.g4Stack
  if stack and #stack > 0 then return table.remove(stack) end
  return "end"
end

function Commands.g4_jump_if(ctx, condition, target)
  if holds(ctx, condition) then return target end
end

-- `callif` lowers to `g4_call_if <cond> <ret>` / `jump <to>` / `label <ret>`.
-- When the condition holds this remembers the return and lets the jump below
-- carry the call; when it does not, it has to JUMP PAST that jump, which is
-- the label it was given.
function Commands.g4_call_if(ctx, condition, returnLabel)
  if not holds(ctx, condition) then return returnLabel end
  ctx.g4Stack = ctx.g4Stack or {}
  ctx.g4Stack[#ctx.g4Stack + 1] = returnLabel
end

-- ---------------------------------------------------------------------------
-- comparisons, vars and flags
-- ---------------------------------------------------------------------------

function Commands.g4_compare_var_value(ctx, id, value)
  setResult(ctx, compare(getVar(ctx.save, id), tonumber(value) or 0))
end

function Commands.g4_compare_var_var(ctx, a, b)
  setResult(ctx, compare(getVar(ctx.save, a), getVar(ctx.save, b)))
end

-- WRITING A GRAPHICS VAR HAS TO REACH THE OBJECT THAT READS IT.
--
-- Sixteen graphics ids (101..116) are not pictures but the names of vars, and
-- a map's entry script fills them in -- Lake Verity's counterpart is Dawn or
-- Lucas depending on which the player is not.  `objectHome` resolves the
-- sentinel at SPAWN, and that is one beat too early: a Gen 4 map's entry
-- script is QUEUED rather than run (`setMap -> onEnter` can happen mid-warp
-- while the warp's own runner is still suspended-alive, which would trip
-- `ScriptRunner:run`'s assert), so the overworld drains it AFTER the cast is
-- built.  The var was therefore always empty at the moment it was read.
--
-- So the write pushes back.  This is the same shape as `syncFlagObjects`,
-- which already re-syncs an object when its hide flag is written, for exactly
-- the same reason -- a script changing state the spawn already consumed.
local GFX_VAR_BASE, GFX_VAR_COUNT = 0x4020, 16
local GFX_SENTINEL_FIRST = 101

local function syncGraphicsVarObjects(ctx, id)
  local slot = tonumber(id)
  if not slot then return end
  local index = slot - GFX_VAR_BASE
  if index < 0 or index >= GFX_VAR_COUNT then return end
  local ow = ctx.overworld
  if not (ow and ow.syncObjectVisibility and ow.map and ow.map.def) then return end
  local sentinel = GFX_SENTINEL_FIRST + index
  for _, obj in ipairs(ow.map.def.objects or {}) do
    if tonumber(obj.graphicsId) == sentinel then
      -- `pooledNPC` rebuilds an NPC whose resolved sprite no longer matches the
      -- one it was built with, so re-syncing is enough to replace the
      -- placeholder with the real character.
      pcall(function() ow:syncObjectVisibility(obj) end)
    end
  end
end

function Commands.g4_set_var(ctx, id, value)
  -- SetVar's value is a literal halfword on both Gen 4 cartridges
  -- (ScrCmd_SetVarFromValue / HGSS ScrCmd_SetVar: ScriptReadHalfword), and no
  -- var lives at 0xC000 or above on any of the three: read as a var id,
  -- `SetVar VAR_ELEVATOR_FLOORS_ABOVE, -1` (0xFFFF) wrote 0, and the lift's
  -- current-floor window -- which closes on 0xFFFF -- never closed
  local raw = tonumber(value)
  if raw and raw >= 0xC000 then
    setVar(ctx.save, id, raw)
    syncGraphicsVarObjects(ctx, id)
    return
  end
  setVar(ctx.save, id, valueOf(ctx, value))
  syncGraphicsVarObjects(ctx, id)
end

-- A VALUE THE COMMAND WRITES ITSELF, never read as a var: ScrCmd_530 stores
-- _020FE4A8[n] (0x6208, 0xF229...) straight into 0x4036 + n, and through
-- g4_set_var's valueOf every one of them (>= 0x4000) was taken for a var id
-- and the write came out 0 (Mahogany hideout's generator, scr_seq_0090).
function Commands.g4_set_var_literal(ctx, id, value)
  setVar(ctx.save, id, tonumber(value) or 0)
  syncGraphicsVarObjects(ctx, id)
end

function Commands.g4_copy_var(ctx, dest, src)
  setVar(ctx.save, dest, valueOf(ctx, src))
  syncGraphicsVarObjects(ctx, dest)
end

function Commands.g4_add_var(ctx, id, value)
  setVar(ctx.save, id, getVar(ctx.save, id) + valueOf(ctx, value))
end

function Commands.g4_sub_var(ctx, id, value)
  setVar(ctx.save, id, getVar(ctx.save, id) - valueOf(ctx, value))
end

-- The flag's own value into the register, not a comparison -- see the header.
function Commands.g4_check_flag(ctx, name)
  Commands.check_flag(ctx, name)
  setResult(ctx, ctx.lastCheck and 1 or 0)
end

-- Trainer flags are a separate bank on the cartridge and a separate table
-- here, so a Gen 4 trainer id cannot collide with a Gen 1-3 event flag.
local function trainerFlags(save)
  if not save then return nil end
  save.gen4TrainerFlags = save.gen4TrainerFlags or {}
  return save.gen4TrainerFlags
end

function Commands.g4_set_trainer_flag(ctx, id)
  local t = trainerFlags(ctx.save)
  if t then t[valueOf(ctx, id)] = true end
end

function Commands.g4_clear_trainer_flag(ctx, id)
  local t = trainerFlags(ctx.save)
  if t then t[valueOf(ctx, id)] = nil end
end

function Commands.g4_check_trainer_flag(ctx, id)
  local t = trainerFlags(ctx.save)
  setResult(ctx, (t and t[valueOf(ctx, id)]) and 1 or 0)
end

-- ---------------------------------------------------------------------------
-- the conversation
-- ---------------------------------------------------------------------------

-- `lockall` / `lock` freeze the field while a script talks, and `releaseall` /
-- `release` give it back.  The engine already stops the world for the duration
-- of a script -- `ScriptRunner` owns the turn -- so these are the cartridge's
-- bookkeeping rather than something to reimplement, and the honest handler is
-- the one that records the state the later rows read rather than an empty
-- function that pretends there is nothing to say.
-- ...and the objects' pause itself is src/world/Gen4ObjectLock.lua: LockAll
-- holds every walker where it stands; with a talked-to object
-- (LockLastTalked) that one finishes its step first and the script waits
-- for it, as ScriptContext_Pause / _WaitMovementPauseBeforeMsg do.
function Commands.g4_lock_all(ctx)
  ctx.g4Locked = true
  local ow = ctx.overworld
  if not ow then return end
  local Lock = require("src.world.Gen4ObjectLock")
  local waiting = Lock.lockAll(ow, ctx.npc)
  if waiting and #waiting > 0 and ctx.runner then
    ctx.runner.waitingCheck = function() return not Lock.finishing(waiting) end
    ctx.runner:yield()
  end
end
function Commands.g4_release_all(ctx)
  ctx.g4Locked = false
  if ctx.overworld then require("src.world.Gen4ObjectLock").releaseAll(ctx.overworld) end
  -- ReleaseAll unpauses every map object, including the walking partner.
  -- Elm's starter scene pauses it before switching back to normal following.
  local st = ctx.save and ctx.save.hgssFollowMon
  if st then st.paused = nil end
end
-- LockObject / ReleaseObject (HGSS Lock / Release): one object's pause
local function lockedObject(ctx, id)
  local ow = ctx.overworld
  local want = tonumber(valueOf(ctx, id))
  if not (ow and want) then return nil end
  for _, npc in ipairs(ow.npcs or {}) do
    if (npc.localId or (npc.def and npc.def.localId)) == want then return npc end
  end
  return nil
end
function Commands.g4_lock(ctx, id)
  ctx.g4Locked = true
  require("src.world.Gen4ObjectLock").lockOne(lockedObject(ctx, id))
end
function Commands.g4_release(ctx, id)
  ctx.g4Locked = false
  require("src.world.Gen4ObjectLock").releaseOne(lockedObject(ctx, id))
end

function Commands.g4_face_player(ctx)
  Commands.face_player(ctx)
end

-- `closemessage` takes the box down.  The engine closes its own box when the
-- text is acknowledged, so this only has to clear the pending state -- and it
-- must not be a no-op, because a script that closes and then opens a second
-- box needs the first one gone.
-- `openmessage` -- the half of the pair that was missing, and the reason the
-- other half was clearing a flag nobody set.  Ten sites, nine of them in
-- `scripts_battles.s`, so this is on the path of every trainer battle in the
-- region.
--
-- SAYING WHAT THIS DOES NOT DO: nothing reads `ctx.textOpen` yet.  The engine's
-- `show_text` opens and closes its own box per line, so the cartridge's
-- explicit window lifetime has no consumer here.  The flag is set anyway
-- because the pair being asymmetric is what made the gap invisible: a renderer
-- that later wants to keep one box open across several prints needs the state
-- to already be truthful, and a `close` with no `open` cannot be made truthful
-- after the fact.
function Commands.g4_open_message(ctx)
  ctx.textOpen = true
end

function Commands.g4_close_message(ctx)
  ctx.textOpen = nil
end

-- `waitbutton` is what makes a line stay on screen.  The engine's `show_text`
-- already blocks on the same acknowledgement, so the wait is satisfied by the
-- time this row is reached; skipping it silently was harmless and saying so
-- once is better than warning on every line in Sinnoh.
function Commands.g4_wait_button(ctx)
  -- ...EXCEPT UNDER A PICTURE (DrawPokemonPreview's framed Pokemon), where
  -- no message waited first: there the press is the whole point
  local ow = ctx and ctx.overworld
  local runner = ctx and ctx.runner
  if not (ow and ow.pokepicBox and runner) then return end
  local input = ctx.game and ctx.game.input
  runner.waitingCheck = function()
    return input and input.wasPressed and (input:wasPressed("a") or input:wasPressed("b")) and true or false
  end
  runner:yield()
end

-- ---------------------------------------------------------------------------
-- string buffers
-- ---------------------------------------------------------------------------

-- Platinum's `bufferplayername` and friends fill the slots that a message's
-- own placeholders read.  With no handler every one of those came out empty,
-- which is half of "npcs are still missing text": the line was fetched and
-- printed with a hole in it.
-- A NAME THE SAVE NEVER RECORDED IS STILL A NAME THE CARTRIDGE HAS.
--
-- Reported from the log rather than from play, twice in one session:
--
--   [warn] gen4 text: string slot 0 was never buffered; the line prints with
--   a gap where its name should be
--
-- The buffer WAS called.  `save.player.rival` was the empty string -- a save
-- written before the rival-naming step of Rowan's intro existed, and one this
-- port will keep meeting for as long as anybody continues an old file.  An
-- empty buffer and an unfilled one are indistinguishable downstream, so every
-- `{STRVAR_1 3 0 0}` in Twinleaf printed as a gap mid-sentence.
--
-- The fallback is the CARTRIDGE'S OWN DEFAULT, not one invented here:
-- `gen4_intro.rivalNames` is the preset list the naming screen offers, ripped
-- from the ROM, and its first entry is the "New name!" prompt rather than a
-- name -- so the first non-custom label is the game's own default.  In
-- Platinum that is "Barry".  The player's own name falls back the same way,
-- through `field.boot.namePresets`.
--
-- Read-side only: nothing is written back to the save.  A save that never
-- recorded a rival name should keep saying so, and repairing it here would
-- overwrite a choice the player might yet make in a fresh intro.
local reportedDefaultName = {}

local function defaultName(data, kind)
  if kind == "rival" then
    local rows = data and data.gen4_intro and data.gen4_intro.rivalNames
    for _, row in ipairs(rows or {}) do
      if not row.custom and row.label and row.label ~= "" then return row.label end
    end
    return nil
  end
  local boot = data and data.field and data.field.boot
  local presets = boot and boot.namePresets and boot.namePresets.player
  local first = presets and presets[1]
  if type(first) == "table" then first = first.label end
  return (type(first) == "string" and first ~= "") and first or nil
end

-- FORWARD-DECLARED, and the reason is a crash this file shipped with.
--
-- `itemKey` is defined below, with the bag commands, because that is where it
-- belongs -- but `g4_buffer` reaches for it from up here, in the `itemPlural`
-- fallback and in `tmhmMove`. A file-local referenced ABOVE its `local function`
-- line is not that local at all: Lua resolves the name as a GLOBAL, finds nil,
-- and the buffer raises
--
--     attempt to call a nil value (global 'itemKey')
--
-- the first time a TM's move name is wanted. Declaring the local here and
-- ASSIGNING to it below makes both sites the same upvalue. Caught by running
-- every new command against the real cache rather than by reading them.
local itemKey

-- ScrCmd_BufferValuePaddingDigits reads a literal u32, not a var operand.
function Commands.g4_buffer_padded_number(ctx,slot,value,padding,digits)
  if not ctx.game then return end
  local number=math.floor(tonumber(value) or 0)%4294967296
  local text=string.format('%.0f',number)
  local width=math.max(0,math.min(10,math.floor(tonumber(digits) or 0)))
  padding=tonumber(padding) or 0
  if padding==1 or padding==2 then
    text=string.rep(padding==2 and '0' or ' ',math.max(0,width-#text))..text
  end
  ctx.game.stringBuffers=ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[(tonumber(slot) or 0)+1]=text
end

function Commands.g4_buffer(ctx, slot, kind, value)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  local data = game.data
  local save = ctx.save
  local text
  if kind == "player" then
    text = save and save.player and save.player.name
  elseif kind == "rival" then
    -- `save.player.rival` IS THE KEY, and this read two spellings that nothing
    -- writes.  Gen4RowanIntro's naming screen stores the answer as
    -- `save.player.rival` -- the same field BirchSpeech, the FireRed speech,
    -- Gen2Commands and BattleState all use -- so the rival slot came back
    -- empty every time and the line printed with the token still in it:
    -- "that to my {STRVAR_1 3 1 0}".  The old spellings stay as fallbacks
    -- rather than being deleted, because a save written by some other path is
    -- not worth breaking to tidy this up.
    text = save and ((save.player and (save.player.rival or save.player.rivalName))
                     or save.rivalName)
  elseif kind == "species" then
    local id = valueOf(ctx, value)
    local def = data and data.pokemon and (data.pokemon[id]
                or data.pokemon[("SPECIES_%03d"):format(id)])
    text = def and def.name
  elseif kind == "item" then
    local id = valueOf(ctx, value)
    local def = data and data.items and (data.items[id]
                or data.items[("ITEM_%03d"):format(id)])
    text = def and def.name
  elseif kind == "partyspecies" then
    -- ScrCmd_BufferPartyMonSpecies (scrcmd_strings.c): a PARTY SLOT, and the
    -- species name of whoever stands in it -- read as a species id, slot 0
    -- named nothing and the lab's "received -----" was the result
    local slotIndex = valueOf(ctx, value)
    local mon = save and save.party and save.party[(tonumber(slotIndex) or 0) + 1]
    local def = mon and data and data.pokemon and data.pokemon[mon.species]
    text = def and def.name
  elseif kind == "nickname" then
    local slotIndex = valueOf(ctx, value)
    local mon = save and save.party and save.party[slotIndex + 1]
    local def = mon and data and data.pokemon and data.pokemon[mon.species]
    text = mon and (mon.nickname or (def and def.name))
  elseif kind == "move" then
    local id = valueOf(ctx, value)
    local def = data and data.moves and data.moves[id]
    text = def and def.name
  elseif kind == "number" then
    text = tostring(valueOf(ctx, value))
  elseif kind == "trainerClass" then
    -- WHERE THE CLASS NAMES COME FROM, and they are not a table of their own.
    -- `StringTemplate_SetTrainerClassNameWithArticle` reads a message bank
    -- this port has not indexed by class -- but the TRAINER table carries both
    -- `class` and `className` on all 979 rows, so the map is already in the
    -- cache and only needs inverting.  Built once and cached on the module.
    text = Gen4Commands.trainerClassName(data, valueOf(ctx, value))
  elseif kind == "rivalStarter" or kind == "playerStarter"
         or kind == "counterpartStarter" then
    -- Derived from VAR_PLAYER_STARTER rather than stored -- see the starter
    -- section below, which is where the two `if` ladders live.  Resolved late
    -- (a forward local would have to be declared above this function) through
    -- the module table, which is the same object either way.
    local mine = Gen4Commands.playerStarter(save)
    local id = mine
    if kind == "rivalStarter" then id = Gen4Commands.rivalStarter(mine)
    elseif kind == "counterpartStarter" then
      id = Gen4Commands.counterpartStarter(mine)
    end
    local def = id ~= 0 and data and data.pokemon and data.pokemon[id] or nil
    text = def and def.name
  elseif kind == "pocket" then
    -- `bufferpocketname <slot> <pocket>` -- the BAG POCKET NAMES bank, which
    -- the menu stage already extracts as `gen4_menus.bag.pockets` (eight
    -- entries, in `fieldPocket` order). Bank 395 is the plain list and 396 is
    -- the same eight with a colour code and a pocket glyph in front; the plain
    -- one is what a text box in this engine can print, so the cache's own copy
    -- is preferred and the bank is only the fallback.
    local n = math.floor(valueOf(ctx, value) or 0)
    local menus = data and data.gen4_menus
    local list = menus and menus.bag and menus.bag.pockets
    text = list and list[n + 1]
    if not text then
      -- HeartGold / SoulSilver read msg_0226 (message_format.c), whose names
      -- carry the colour code and pocket glyph in front, as 396 does here
      local hgss = require("src.import.Gen4ScriptBands").family == "hgss"
      local label = require("src.import.Gen4Text").label(hgss and 226 or 395, n)
      text = data and data.text and data.text[label]
      if hgss and text then text = text:gsub("^{COLOR %d+}.-{COLOR 0}", "") end
      -- Black / White: system bank 55, ITEMS .. KEY ITEMS in the pocket order
      -- 0xBB answers (Gen5Data's bwPocket)
      if require("src.import.Gen4ScriptBands").family == "bw" then
        text = data and data.text and data.text[("TEXT_G5S_0055_%05d"):format(n)]
      end
    end
  elseif kind == "itemPlural" then
    -- `bufferitemnameplural` reads a BANK OF ITS OWN (394), not the singular
    -- names with an "s" bolted on -- "Poké Balls" and "TMs & HMs" are both in
    -- it and neither is the singular plus a letter.
    local id = math.floor(valueOf(ctx, value) or 0)
    local label = require("src.import.Gen4Text").label(394, id)
    text = data and data.text and data.text[label]
    if not text or text == "" then
      local def = data and data.items and data.items[itemKey(data, id)]
      text = def and def.name
    end
  elseif kind == "poketchApp" then
    -- `bufferpoketchappname <slot> <appID>`, and THE TWO POKETCH NUMBERINGS
    -- ARE NOT THE SAME ONE.
    --
    -- A script's operand is a `POKETCH_APPID_*`: 0 DIGITAL WATCH, 1
    -- CALCULATOR, 2 MEMO PAD, 3 PEDOMETER... which is exactly the order of
    -- message bank 457. The cache's `gen4_menus.poketch.apps[].id` is a
    -- DIFFERENT index -- the Poketch Co. description bank's order, where 1 is
    -- the Analog Watch and the Calculator is 6 -- because that stage pairs
    -- descriptions with names and numbers them as it goes.
    --
    -- Both joins succeed and only one is right; they agree at 0 and diverge
    -- from 1, which is the worst possible way to be wrong. Bank 457 is the
    -- script's own vocabulary, so it is the one read here.
    local id = math.floor(valueOf(ctx, value) or 0)
    local label = require("src.import.Gen4Text").label(457, id)
    text = data and data.text and data.text[label]
  elseif kind:sub(1, 5) == "bank:" then
    -- A NAME THAT IS JUST A MESSAGE BANK KEYED BY THE OPERAND, which several
    -- of these are: item names with articles (393), contest accessories (386)
    -- and their with-article twin (387), Underground goods (626) and theirs
    -- (627), Underground items (628) and traps (630), and contest backdrops
    -- (388).  One kind rather than eight near-identical branches, because the
    -- only thing that differs is the number.
    --
    -- THE BANK IDS ARE THE LINE NUMBER IN generated/text_banks.txt MINUS ONE,
    -- and that is checked rather than assumed each time: bank 626 reads "PC"
    -- and 627 reads "a {COLOR}PC{COLOR}", which is the pair the right way
    -- round.  The systems behind these names are not built -- what this buys
    -- is that the line reads properly instead of printing a raw token.
    local bank = tonumber(kind:sub(6))
    local id = math.floor(valueOf(ctx, value) or 0)
    local label = bank and require("src.import.Gen4Text").label(bank, id)
    text = label and data and data.text and data.text[label]
  elseif kind == "speciesArticle" then
    -- `buffer...specieswitharticle` reads a BANK OF ITS OWN (413), keyed by
    -- species id and holding the article already -- "a TURTWIG", "an IVYSAUR".
    -- Worth reading rather than composing: choosing between "a" and "an" from
    -- the first letter is a guess about English that the cartridge has already
    -- answered for all 493 rows.  The entries carry {COLOR} markup, so they go
    -- through the same filter a menu line does.
    local id = math.floor(valueOf(ctx, value) or 0)
    -- HeartGold / SoulSilver keep the same rows in bank 238 (msg_0238); their
    -- 413 is other text
    local bank = (require("src.import.Gen4ScriptBands").family == "hgss") and 238 or 413
    local label = require("src.import.Gen4Text").label(bank, id)
    text = data and data.text and data.text[label]
  elseif kind == "tmhmMove" then
    -- `buffertmhmmovename <slot> <item>` -- `Item_MoveForTMHM`, which is a
    -- FLAT ARM9 TABLE (`sTMHMMoves`, 100 u16 in TM01..TM92 then HM01..HM08
    -- order) and is not derivable from the item rows: a TM's own description
    -- is the MOVE's description re-wrapped, and matching on it pairs only 61
    -- of 100 even after the line breaks are normalised, so that join was
    -- measured and thrown away rather than shipped.
    --
    -- The extractor writes the array as `constants.tmhmMoves`, and THE JOIN
    -- FROM AN ITEM TO ITS ENTRY IS NOT MADE HERE ANY MORE.  It used to be:
    -- the index came off the item's NAME, with a literal 92 for where the HM
    -- run starts.  Then the bag needed the same join -- a TM with no record
    -- answered "This isn't the time to use that!" -- and the same derivation
    -- written a second time, with the same 92 in it, is the bug this port
    -- keeps finding.
    --
    -- `ItemEffects.markGen4Machines` owns it now, stamps `def.machine` at
    -- load the way `Item_MoveForTMHM` reads it (the id IS the index), and
    -- reads the split off the items rather than assuming 92.  One join.
    local id = math.floor(valueOf(ctx, value) or 0)
    local def = data and data.items and data.items[itemKey(data, id)]
    local move = def and def.machine and def.machine.move
    local mdef = move and data.moves and data.moves[move]
    text = mdef and mdef.name
    if not text and not Gen4Commands._saidTmhm then
      Gen4Commands._saidTmhm = true
      Logger.warn("gen4 text: item %s carries no machine record, so the move "
                  .. "a TM teaches cannot be named -- re-import to pick up "
                  .. "`fieldUseFunc` and `constants.tmhmMoves`", tostring(id))
    end
  end
  if (text == nil or text == "") and (kind == "player" or kind == "rival") then
    text = defaultName(data, kind)
    if text and not reportedDefaultName[kind] then
      reportedDefaultName[kind] = true
      Logger.warn("gen4 text: this save carries no %s name, so the "
                  .. "cartridge's own default (%s) is printed instead -- a "
                  .. "file written before Rowan's intro asked for it",
                  kind, text)
    end
  end
  -- MARKUP ONCE, FOR EVERY BRANCH.  Several of these read a message bank --
  -- bag pockets (395), item plurals (394), Poketch apps (457), the
  -- with-article species (413) and the `bank:` family -- and those entries
  -- carry control markup of their own.  Two branches ran `gen4Markup` right
  -- after their own read and the rest did not, so a pocket name went into a
  -- string slot with its tokens still on it; the outer line is marked up
  -- BEFORE the slot is spliced in, so nothing downstream would ever have
  -- stripped them.  A value that has no markup is unchanged by this.
  if type(text) == "string" and Commands.gen4Markup then
    text = Commands.gen4Markup(text, game)
  end
  game.stringBuffers[(tonumber(slot) or 0) + 1] = text or ""
end

-- ---------------------------------------------------------------------------
-- items
-- ---------------------------------------------------------------------------
--
-- All four of Platinum's bag commands are `(item, count, destVar)` --
-- `scrcmd_item.c`, and every one of them writes whether it SUCCEEDED into a
-- var the script then compares.  Dropping that destination is the difference
-- between "you got the Potion" and a branch that decides on whatever the last
-- comparison left behind.

itemKey = function(data, id)
  local items = data and data.items
  if not items then return id end
  -- A NUMBER IS NEVER A BAG KEY, and this branch used to hand one over.
  --
  -- `items[id]` succeeding says the id NAMES AN ITEM; it does not say the id
  -- is the form the BAG wants.  On a Gen 4 cache the table is keyed 0..445,
  -- so `items[17]` is a hit and 17 was returned -- and the bag is
  -- string-keyed throughout (`Bag.isBadge` does `id:find("BADGE")`), so
  -- every pickup, gift and Mart purchase in Sinnoh died on
  -- `Bag.lua:59: attempt to index local 'id' (a number value)`.
  --
  -- Measured through this very function: `g4_give_item(ctx, 17, 2)` and
  -- `(ctx, 4, 2)` both raised before this line changed.
  --
  -- Gen 1/2/3 pass strings, so they take the same branch they always did.
  if type(id) ~= "number" and items[id] then return id end
  local named = ("ITEM_%03d"):format(tonumber(id) or 0)
  if items[named] then return named end
  return id
end

-- SILENT, as the cartridge's GiveItem is (scrcmd_item.c: Bag_AddItem and the
-- result into the var). The std scripts around it print "Obtained the X!",
-- play the fanfare and say which pocket; going through the Gen 1/2
-- `give_item` added its own "{PLAYER} got X!" box and jingle in front of
-- every gift in Sinnoh and Johto (Kurt's Fast Ball, reported in the HGSS
-- playthrough).
function Commands.g4_give_item(ctx, item, count, destVar)
  local id = itemKey(ctx.game and ctx.game.data, valueOf(ctx, item))
  -- RUN MODES: FIELD ITEMS & GIFTS (src/runmodes/RunHooks.lua giftItem)
  id = require("src.runmodes.RunHooks").giftItem(ctx.game, id)
  local n = math.max(valueOf(ctx, count), 1)
  pcall(function() require("src.core.Probe").say("item", "give %s x%s", tostring(id), tostring(n)) end)
  local ok = ctx.save and require("src.inventory.Bag").add(ctx.save, id, n, ctx.game and ctx.game.data) and true or false
  ctx.lastCheck = ok
  if destVar then setVar(ctx.save, destVar, ok and 1 or 0) end
  setResult(ctx, ok and 1 or 0)
end

function Commands.g4_take_item(ctx, item, count, destVar)
  local id = itemKey(ctx.game and ctx.game.data, valueOf(ctx, item))
  local n = math.max(valueOf(ctx, count), 1)
  Commands.take_item(ctx, id, n)
  if destVar then setVar(ctx.save, destVar, ctx.lastCheck and 1 or 0) end
end

function Commands.g4_check_item(ctx, item, count, destVar)
  local id = itemKey(ctx.game and ctx.game.data, valueOf(ctx, item))
  local n = math.max(valueOf(ctx, count), 1)
  local held = (ctx.save and ctx.save.inventory and ctx.save.inventory[id]) or 0
  local ok = held >= n
  ctx.lastCheck = ok
  if destVar then setVar(ctx.save, destVar, ok and 1 or 0) end
  setResult(ctx, ok and 1 or 0)
end

-- `Bag_CanFitItem` answers whether there is room.  This port's bag refuses at
-- its configured capacity and has no per-pocket accounting to ask, so the
-- answer is yes unless the bag is full -- which is what `Bag.add` decides, and
-- asking it twice would be the only way to be more honest than this.
--
-- ...and the bag DOES have that accounting now (Gen 4 pocket sizes, 999 a
-- stack, 99 in the TM pocket), so "always yes" was wrong where it matters:
-- Clair's TM59 to a player already holding 99 (D44R0102 / T30GYM0101
-- GoToIfNoItemSpace) printed "Obtained the TM59!", gave nothing and still
-- set FLAG_GOT_TM59_FROM_CLAIR. So the answer is Bag.add's own, asked of a
-- throwaway copy of the inventory: the same rules, nothing written.
function Commands.g4_can_fit_item(ctx, item, count, destVar)
  local fits = 1
  local save = ctx.save
  if save and save.inventory and item ~= nil then
    local data = ctx.game and ctx.game.data
    local id = itemKey(data, valueOf(ctx, item))
    local n = math.max(valueOf(ctx, count) or 1, 1)
    local inv, order = {}, {}
    for k, v in pairs(save.inventory) do inv[k] = v end
    for i, v in ipairs(save.bagOrder or {}) do order[i] = v end
    local trial = setmetatable({ inventory = inv, bagOrder = order }, { __index = save })
    local okA, added = pcall(require("src.inventory.Bag").add, trial, id, n, data)
    if okA and added == false then fits = 0 end
  end
  if destVar then setVar(ctx.save, destVar, fits) end
  setResult(ctx, fits)
end

-- ---------------------------------------------------------------------------
-- the player, and the world
-- ---------------------------------------------------------------------------

function Commands.g4_player_gender(ctx, destVar)
  local save = ctx.save
  local female = save and save.player and save.player.gender == "girl"
  setVar(ctx.save, destVar, female and 1 or 0)
end

-- PlayerAvatar_GetFacingDir: 0 up, 1 down, 2 left, 3 right on the cartridge.
local FACING = { up = 0, down = 1, left = 2, right = 3 }

-- `scrcmd 20D` -- AND THIS ONE WAS A HANG, not a missing feature.
--
--     static BOOL ScrCmd_20D(ScriptContext *ctx) {
--         u8 v0 = ScriptContext_ReadByte(ctx);      -- a MODE, 0..9
--         u16 *v1 = ScriptContext_GetVarPointer(ctx);
--         *v1 = ov6_02243004(ctx->fieldSystem, v0);
--     }
--
-- `ov6_02243004` is a ten-mode switch over one overlay-6 field effect. Eight
-- of the ten start or stop something and fall through to `return 0`. Exactly
-- TWO -- mode 1 and mode 6 -- are completion polls:
--
--     case 1: if (ov6_0223E708(Unk)) { ov6_0223E700(Unk); return 1; }
--             else { return 0; }
--     case 6: if (ov6_0223FCF4(Unk) == 6) { ov6_0223FCE0(Unk); return 1; }
--             else { return 0; }
--
-- and both of those read a staged animation's state counter (`unk_00 == 11`,
-- `unk_00 == 6`) -- "has the effect finished yet".
--
-- The scripts poll them in a BACKWARDS JUMP:
--
--     20d 0x1 0x800C  /  comparevartovalue 0x800C 0x0  /  gotoif 1 -18
--     20d 0x6 0x800C  /  comparevartovalue 0x800C 0x0  /  gotoif 1 -18
--
-- so `g4_no_feature`, which writes 0, meant "not finished" forever and the
-- script span on the spot. Two infinite loops, one in band 236 and one in band
-- 237, on the Spear Pillar path.
--
-- This is the sharpest version of pass 180's lesson. The stub was RIGHT for
-- eight of the ten modes -- the cartridge writes 0 there too -- which is
-- exactly why nobody looked: the row behaved correctly almost everywhere. An
-- effect this port never starts has already finished, so the only non-hanging
-- answer for the two polls is 1, and it is also the true one.
local OV6_EFFECT_POLL_MODES = { [1] = true, [6] = true }
local OV6_EFFECT_MAX_MODE = 9

function Commands.g4_field_effect(ctx, mode, destVar)
  -- the mode is `ScriptContext_ReadByte`, a literal, NOT a var -- so it is not
  -- put through `valueOf`, which would read 0..9 as something else entirely if
  -- a mod ever pointed it at a var id.
  mode = math.floor(tonumber(mode) or -1)
  if mode < 0 or mode > OV6_EFFECT_MAX_MODE then
    -- the cartridge's `default:` is `GF_ASSERT(FALSE)`, so there is no
    -- behaviour to copy; it writes 0 and so do we, loudly.
    require("src.core.Logger").warn(
      "gen4 script: scrcmd 20D mode %d is outside the cartridge's 0-%d "
      .. "switch, which asserts there -- answering 0", mode,
      OV6_EFFECT_MAX_MODE)
    if destVar then setVar(ctx.save, destVar, 0) end
    setResult(ctx, 0)
    return
  end
  local answer = OV6_EFFECT_POLL_MODES[mode] and 1 or 0
  if destVar then setVar(ctx.save, destVar, answer) end
  setResult(ctx, answer)
end

function Commands.g4_player_dir(ctx, destVar)
  local player = ctx.overworld and ctx.overworld.player
  setVar(ctx.save, destVar, FACING[player and player.facing] or 1)
end

-- ---------------------------------------------------------------------------
-- THE SCRIPTS' COORDINATE SPACE IS THE MATRIX'S, NOT THE MAP'S
-- ---------------------------------------------------------------------------
--
-- Sinnoh is ONE grid.  `PlayerAvatar_GetXPos` answers in matrix coordinates,
-- every event in the cartridge is stored in them, and every script compares
-- against them -- Twinleaf's own guitarist scene branches on x == 108..115,
-- which are numbers no 32-wide map could ever produce.
--
-- The import makes events map-local by subtracting the region origin, which is
-- right: the engine walks one map at a time.  But that makes the two sides
-- disagree, and NOTHING was converting between them.  Reported from play:
-- *"the player that's supposed to stop me doesn't walk up to me and push me
-- back I just keep walking backwards 1 block like 5 times"* -- eight branches
-- on the player's x, none of which could match, so every one of them fell
-- through to the last and applied the wrong push-back.
--
-- Twinleaf's origin is (96, 864); an interior's is (0, 0), which is why this
-- was invisible indoors and why adding it cannot change indoor behaviour.
local function mapOrigin(ctx)
  local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
  if not def then
    local data = ctx.game and ctx.game.data
    local mapId = ctx.save and ctx.save.player and ctx.save.player.map
    def = mapId and data and data.maps and data.maps[mapId]
  end
  return tonumber(def and def.originX) or 0, tonumber(def and def.originY) or 0
end
Gen4Commands.mapOrigin = mapOrigin

-- local -> matrix, for the commands that HAND a coordinate to a script
local function toMatrix(ctx, x, z)
  local ox, oy = mapOrigin(ctx)
  return (x or 0) + ox, (z or 0) + oy
end

-- matrix -> local, for the commands that TAKE one from a script
local function toLocal(ctx, x, z)
  local ox, oy = mapOrigin(ctx)
  return (x or 0) - ox, (z or 0) - oy
end
Gen4Commands.toMatrix, Gen4Commands.toLocal = toMatrix, toLocal

function Commands.g4_player_pos(ctx, xVar, zVar)
  local player = ctx.overworld and ctx.overworld.player
  local x, z = toMatrix(ctx, player and player.cellX, player and player.cellY)
  setVar(ctx.save, xVar, x)
  setVar(ctx.save, zVar, z)
  -- SAY WHAT IT ANSWERED, because everything downstream is a branch on it.
  --
  -- Half of Sinnoh's cutscenes are `getplayermappos` followed by six or eight
  -- `comparevartovalue` rows on the result, and EVERY ONE OF THEM FAILING
  -- looks exactly like the scene not being implemented: the script falls
  -- through to its `end`, the trigger's var is never advanced, and the player
  -- walks over the trigger again next step.  Route 201's opening does this and
  -- so does Twinleaf's guitarist.  One line naming the map, the local cell,
  -- the origin and the matrix answer turns "the scene does nothing" into a
  -- number that is either in the script's range or is not.
  local ox, oy = mapOrigin(ctx)
  Logger.debug("gen4 pos: %s local (%s,%s) + origin (%d,%d) -> matrix (%s,%s)",
               tostring(ctx.overworld and ctx.overworld.map and ctx.overworld.map.id),
               tostring(player and player.cellX), tostring(player and player.cellY),
               ox, oy, tostring(x), tostring(z))
end

-- ---------------------------------------------------------------------------
-- the scripted camera
-- ---------------------------------------------------------------------------
--
-- 13 `addfreecamera` sites and 14 `restorecamera` ones, and the whole thing is
-- simpler than it looks.  `ScrCmd_AddFreeCamera(x, z)` stands an INVISIBLE map
-- object at those ground coordinates and points `Camera_TrackTarget` at its
-- position; `ScrCmd_RestoreCamera` deletes it and tracks the player again.
-- Between the two, `ApplyFreeCameraMovement` -- which the assembler expands
-- straight to `ApplyMovement LOCALID_CAMERA` -- walks that invisible body with
-- ordinary movement actions, and the view goes with it.
--
-- So the pan needs no camera code at all: an entity the script can already
-- walk, plus one line in `OverworldState:cameraTarget` deciding who the camera
-- follows.  Lake Verity Low Water's arrival is the first one the player meets
-- (`AddFreeCamera 46, 53` / pan to Cyrus / pan back / `RestoreCamera`).
--
-- HIDDEN AND PASSABLE, because the cartridge's is: `MapObject_SetHidden(...,
-- TRUE)` on the line after it is created, and nothing collides with it.
local function makeCamera(ctx, x, z)
  local ow = ctx.overworld
  if not (ow and ow.map) then return nil end
  local NPC = require("src.world.NPC")
  local cx, cy = toLocal(ctx, valueOf(ctx, x), valueOf(ctx, z))
  local npc = NPC.new(ctx.game.data, ow.map.id, {
    index = 241, localId = 0xF1, x = cx, y = cy, movementType = 0, direction = 1,
  })
  npc.hidden = true
  npc.passable = true
  npc.gen4CameraObject = true
  npc.facing = "down"
  ow.npcs[#ow.npcs + 1] = npc
  ow.entities[#ow.entities + 1] = npc
  ow.gen4Camera = npc
  return npc
end

local function dropCamera(ctx)
  local ow = ctx.overworld
  if not ow then return end
  local cam = ow.gen4Camera
  ow.gen4Camera = nil
  if not cam then return end
  for _, list in ipairs({ ow.npcs or {}, ow.entities or {} }) do
    for i = #list, 1, -1 do
      if list[i] == cam then table.remove(list, i) end
    end
  end
end

-- `addfreecamera <x> <z>`: the camera follows the new body.
function Commands.g4_add_free_camera(ctx, x, z)
  dropCamera(ctx)
  makeCamera(ctx, x, z)
end

-- `addcameraoverrideobject <x> <z>`: the same body, but the cartridge does NOT
-- re-point the land streamer at it -- only the camera.  This engine streams
-- the map from the player's own cell regardless, so the two are the same call
-- here and the difference is recorded rather than invented.
function Commands.g4_camera_override(ctx, x, z)
  dropCamera(ctx)
  local cam = makeCamera(ctx, x, z)
  if cam then cam.gen4CameraOverride = true end
end

-- `restorecamera` / `removecameraoverrideobject`: delete the body, and the
-- camera falls back to the player because `cameraTarget` has nothing else to
-- answer.
function Commands.g4_restore_camera(ctx)
  dropCamera(ctx)
end

function Commands.g4_check_badge(ctx, badge, destVar)
  local n = valueOf(ctx, badge)
  local Badges = require("src.inventory.Badges")
  local list = Badges.list(ctx.game and ctx.game.data) or {}
  local entry = list[n + 1]
  local has = entry and Badges.has(ctx.save, entry) or false
  if destVar then setVar(ctx.save, destVar, has and 1 or 0) end
  setResult(ctx, has and 1 or 0)
end

-- A GEN 4 WARP NAMES A MAP HEADER, NOT A MAP.
--
-- `ScrCmd_Warp` takes `(mapHeaderID, unused, x, z, direction)` and the engine's
-- own `warp` takes a map id -- the string key in `data.maps`.  Every Gen 4 def
-- carries the header it was built from, so the join is a scan, done once and
-- kept: 593 headers against 1,180 maps is not something to redo per warp.
local headerToMap = setmetatable({}, { __mode = "k" })

local function mapForHeader(data, header)
  local maps = data and data.maps
  if not maps then return nil end
  local index = headerToMap[maps]
  if not index then
    -- ...AND THE CARTRIDGE'S OWN SPELLING OF IT.  Data.lua adds an alias copy
    -- of every map under a respelled id (`D31R0207` -> `D_31R_0207`, see
    -- `aliasMap`), and the copy carries the same header.  Taken in `pairs`
    -- order, a warp landed on whichever of the two came last -- a different
    -- one from one boot to the next -- and the alias's id is the one no Gen 4
    -- index knows.  A def with a `sourceId` is the alias; it answers only a
    -- header nothing else does.
    index = {}
    for id, def in pairs(maps) do
      if type(def) == "table" and def.header and not (def.sourceId and index[def.header]) then
        index[def.header] = id
      end
    end
    headerToMap[maps] = index
  end
  return index[tonumber(header) or -1]
end

Gen4Commands.mapForHeader = mapForHeader

local DIRECTION = { [0] = "up", "down", "left", "right" }

function Commands.g4_warp(ctx, header, x, z, direction)
  local data = ctx.game and ctx.game.data
  local mapId = mapForHeader(data, valueOf(ctx, header))
  if not mapId then
    Logger.warn("gen4 script: warp names header %s and no map in this cache "
                .. "was built from it -- the warp is skipped",
                tostring(header))
    return
  end
  local wx, wz = valueOf(ctx, x), valueOf(ctx, z)
  -- BLACK / WHITE names MATRIX tiles: Dragonspiral Tower's summit sends the
  -- player to zone 205 at (179, 146), which is local (19, 18) of a map cut
  -- at (160, 128). A coordinate past the map's own size is taken back by
  -- its origin.
  local def = data.maps[mapId]
  -- ...and so does PLATINUM'S GREAT MARSH: its six areas are 32 x 32 windows
  -- of one matrix (D06R0201 at (32, 32) .. D06R0206 at (64, 96)), and the
  -- gate's desk script (M0129/S0023) sends the player to header 509 at
  -- (68, 116) -- the marsh's own tile, local (4, 20) of D06R0206. Taken as
  -- local it stood the player in the void below the map.
  if def and (def.gen5 or def.originX or def.originY) and def.width
     and (wx >= def.width or wz >= def.height) then
    wx, wz = wx - (def.originX or 0), wz - (def.originY or 0)
  end
  -- THE DISTORTION WORLD'S FLOORS are this port's maps cut out of the floor's
  -- own grid at the floor's offset, and a script names the floor's tile:
  -- Spear Pillar's "Warp MAP_HEADER_DISTORTION_WORLD_1F, 55, 40" is 1F's
  -- (55, 40), the map's (34, 30). Taken as the map's own, the player
  -- arrived in the air beside the island -- reported from play as "when
  -- first entering the distorted world via the story it has you floating in
  -- the middle of the air".
  if def and def.gen4DistWorld then
    local okF, m = pcall(function() return require("src.world.Gen4DistSurface").floorFor(def) end)
    if okF and m then wx, wz = wx - (m.offsetX or 0), wz - (m.offsetZ or 0) end
  end
  return Commands.warp(ctx, mapId, wx, wz, DIRECTION[valueOf(ctx, direction)])
end

-- THE LINE, AND THE BANK IT COMES OUT OF.
--
-- `data.text` is flat and keyed `TEXT_Bnnnn_nnnnn` -- the Gen 4 extractor
-- writes it that way because Gen 1-3 address a string by one id and Gen 4
-- needs a bank AND an index.  A `message` row carries only the index; the bank
-- is the map header's `msgArchiveID`, which rides on the def as `messages`.
--
-- Falls through to the bare id when the map has no bank, which is what a cache
-- imported before that byte was carried looks like: an empty box rather than a
-- crash, and the same empty box it gave before.
-- THE SCRIPT'S OWN MAP'S BANK, not the one the player stands on now:
-- ScriptContext_Load reads the message archive once, when the script starts,
-- so a script that warps the player and keeps talking still reads its home
-- map's lines. Reading the current map's printed TEXT_B labels (Kurt's house
-- scene, entries 15-17, resolved against Azalea Gym's bank).
local function lineFor(ctx, entry)
  local maps = ctx.game and ctx.game.data and ctx.game.data.maps
  local home = ctx.mapId and maps and maps[ctx.mapId]
  local def = (home and home.messages and home) or (ctx.overworld and ctx.overworld.map and ctx.overworld.map.def)
  local bank = def and def.messages
  if not bank then return entry end
  return require("src.import.Gen4Text").label(bank, tonumber(entry) or 0)
end

Gen4Commands.lineFor = lineFor

function Commands.g4_message(ctx, entry)
  return Commands.show_text(ctx, lineFor(ctx, entry))
end

-- ...AND FROM A NAMED BANK, for a block that lives in a shared script file.
--
-- `ScriptContext_Load` takes the file and the bank together, so a common
-- script reads TEXT_BANK_COMMON_STRINGS wherever the player is standing.  The
-- lowering knows which member a block came from and puts the bank in the row,
-- which is why this needs no map at all.
-- `valueOf` rather than `tonumber`, because `messagefrombank` reaches this row
-- too and the cartridge takes BOTH its operands with `ScriptContext_GetVar` --
-- var-or-literal. Safe for the existing callers either way: a bank id is under
-- 724 and an entry under about 2,500, both far below `VARS_START` (0x4000), so
-- a literal can never be mistaken for a var id.
function Commands.g4_message_bank(ctx, bank, entry)
  local Gen4Text = require("src.import.Gen4Text")
  return Commands.show_text(ctx, Gen4Text.label(valueOf(ctx, bank) or 0,
                                                valueOf(ctx, entry) or 0))
end

-- `choosecustommessageword <unused> <resultVar> <destVar>` -- the word-choice
-- screen a TV interview or the Sunyshore house opens so the player can pick a
-- word to put in a sentence. The macro emits a literal 0 for the first operand
-- and pokeplatinum calls it `unused`; the other two are destinations.
--
-- THERE IS NO WORD-CHOICE SCREEN IN THIS ENGINE, so this answers the
-- cartridge's own cancelled path -- and that is a real answer, not a shrug.
-- `ScrCmd_ChooseCustomMessageWord` writes `*destVar = 0xFFFF` BEFORE it starts
-- the task, and the caller branches on `resultVar`:
--
--     ChooseCustomMessageWord VAR_RESULT, VAR_0x8004
--     ...
--     GoToIfEq VAR_RESULT, 0, TVReporterInterviews_ThatsTooBad
--
-- so 0 in `resultVar` means "the player backed out", which the script already
-- has dialogue for. Writing 0 and 0xFFFF takes that branch cleanly; writing
-- nothing left both destinations holding the previous script's values and the
-- interview branched at random on its way to using a word nobody picked.
-- `choosecustommessageword <unused> <resultVar> <destVar>`: the easy-chat
-- screen, one word (src/pokemon/Gen4EasyChat.lua). The word goes in destVar
-- (0xFFFF until one is chosen) and resultVar answers 1, or 0 when the player
-- backs out -- which is what Sunyshore's Julia branches on before her ribbon.
function Commands.g4_choose_message_word(ctx, _unused, resultVar, destVar)
  if destVar then setVar(ctx.save, destVar, 0xFFFF) end
  if resultVar then setVar(ctx.save, resultVar, 0) end
  if not (ctx.game and ctx.game.stack) then return end
  local runner = ctx.runner
  require("src.pokemon.Gen4EasyChat").pick(ctx.game, function(word)
    if word then
      if destVar then setVar(ctx.save, destVar, word) end
      if resultVar then setVar(ctx.save, resultVar, 1) end
    end
    if runner then runner:resume() end
  end)
  if runner then runner:yield() end
end
Commands.meta.g4_choose_message_word = { foreground = true, blocking = true }

-- ...and the two-word form: two picks in a row; backing out of either answers
-- 0, the way the interview's "That's too bad" branch expects
function Commands.g4_choose_two_message_words(ctx, resultVar, dest1, dest2)
  if dest1 then setVar(ctx.save, dest1, 0xFFFF) end
  if dest2 then setVar(ctx.save, dest2, 0xFFFF) end
  if resultVar then setVar(ctx.save, resultVar, 0) end
  if not (ctx.game and ctx.game.stack) then return end
  local runner = ctx.runner
  local EasyChat = require("src.pokemon.Gen4EasyChat")
  EasyChat.pick(ctx.game, function(first)
    if not first then if runner then runner:resume() end return end
    EasyChat.pick(ctx.game, function(second)
      if second then
        if dest1 then setVar(ctx.save, dest1, first) end
        if dest2 then setVar(ctx.save, dest2, second) end
        if resultVar then setVar(ctx.save, resultVar, 1) end
      end
      if runner then runner:resume() end
    end)
  end)
  if runner then runner:yield() end
end
Commands.meta.g4_choose_two_message_words = { foreground = true, blocking = true }

-- `getpartymonconteststat <slot> <type> <dest>`: cool, beauty, cute, smart,
-- tough, then sheen -- MON_DATA_COOL onward
local CONTEST_STATS = { [0] = "cool", "beauty", "cute", "smart", "tough", "sheen" }
function Commands.g4_party_contest_stat(ctx, slot, contestType, destVar)
  local party = (ctx.save and ctx.save.party) or {}
  local mon = party[(math.floor(valueOf(ctx, slot) or 0)) + 1]
  local key = CONTEST_STATS[math.floor(valueOf(ctx, contestType) or 0)]
  local value = mon and key and mon.contest and tonumber(mon.contest[key]) or 0
  setVar(ctx.save, destVar, value)
end

-- `messagevar` takes its entry out of a var rather than out of the row.
-- GetStdMsgNaix (HeartGold / SoulSilver): which shared bank a script prints
-- from next with MsgBoxExtern -- scrcmd_message.c's ov01_022067C8, the
-- day-of-week siblings 752, field moves 211, Cameron the photographer 30 and
-- the shops 435; an index past the table writes 0.
Commands.HGSS_STD_MSG_BANKS = { [0] = 752, 211, 30, 435 }
function Commands.g4_std_msg_bank(ctx, index, destVar)
  setVar(ctx.save, destVar, Commands.HGSS_STD_MSG_BANKS[valueOf(ctx, index)] or 0)
end

-- GenderMsgBox (HeartGold / SoulSilver): the male entry for a boy, the other
-- for anyone else, from the block's bank when it has one.
function Commands.g4_gender_message(ctx, male, female, bank)
  local save = ctx.save
  local entry = (save and save.player and save.player.gender == "girl") and female or male
  if bank then return Commands.g4_message_bank(ctx, bank, entry) end
  return Commands.g4_message(ctx, entry)
end

-- ICIRRUS GYM 0x195 <n> (ov45 0x21F38C4): while ride n's gate holds (its
-- switch group's var 0x4001 + group at the table's state) the player is
-- switched onto the rail under them, and the next press along it rides the
-- chute to its far end (src/world/Gen5IcirrusGym.lua); a shut gate leaves the
-- trigger plain floor. A ride is not a map load: the gym's temporary vars and
-- the arms its switches turned stay as they are.
function Commands.g4_bw_rail_ride(ctx, n)
  local ow = ctx.overworld
  if not (ow and ow.map and ow.map.def and ow.player) then return end
  require("src.world.Gen5IcirrusGym").force(ow, ctx.save, math.floor(valueOf(ctx, n) or 0))
end

-- BLACK / WHITE 0x0DF <mode, species, var>: 1 if the species is in the
-- Pokedex as seen (Cedric Juniper asks after Klink, 599)
function Commands.g4_bw_dex_seen(ctx, species, destVar)
  local id = math.floor(valueOf(ctx, species) or 0)
  local seen = ctx.save and ctx.save.pokedex and ctx.save.pokedex.seen or {}
  setVar(ctx.save, destVar, (seen[id] or seen[tostring(id)]) and 1 or 0)
end

-- DRIFTVEIL GYM: lift n to its other height, the player with it if aboard
-- BLACK / WHITE 0x021: remember entry n for the map the next warp lands on
-- (Gen5PostWarp runs it once the warp is done and this script has ended)
function Commands.g4_bw_queue_entry(ctx, n)
  local ow = ctx.overworld
  if ow then
    -- ...or queued by the map's own load script (Z137's S001F queues its lift,
    -- entry 4): the cartridge reads the queue when the field is built, after
    -- the zone's load scripts, and runs it then in place of the scene check
    -- (READ FROM CODE, ov21 0x0218A584 -> field +0x26, 0x0218A738)
    ow.gen5QueuedEntry = { entry = math.floor(valueOf(ctx, n) or 0), from = ow.map and ow.map.id,
                           sameMap = ow.gen5FieldReturn or ctx.mapCallback or nil }
  end
end

-- BLACK / WHITE 0x0D8 <n, var>: var = whether condition n holds.  The ten
-- rows of overlay 10's table at 0x2170FB0 (0x2159F04 finds a row by n,
-- 0x2159F54 compares): event var 0x4031 + n against its own value
Commands.BW_CONDITIONS = {
  [0] = { 0x4031, 0x1220 }, { 0x4032, 0x0224 }, { 0x4033, 0x0206 }, { 0x4034, 0x1209 }, { 0x4035, 0x0316 },
  { 0x4036, 0x1227 }, { 0x4037, 0x0830 }, { 0x4038, 0x0408 }, { 0x4039, 0x0120 }, { 0x403A, 0x1028 },
}
-- BLACK / WHITE 0x156 <kind>: the game clear (see Gen5ScriptLink). The
-- ending's own art is not imported, so kind 0 records the clear and puts the
-- player back in their room, where the game goes on after the credits
Commands.BW_HOME = { map = "Z391", x = 5, y = 6 }
function Commands.g4_bw_game_clear(ctx, kind)
  local k = math.floor(valueOf(ctx, kind) or 0)
  if ctx.save then
    ctx.save.gen5GameClear = true
    if k == 1 then ctx.save.gen5ChampionClear = true end
    -- (flag 0x960, the post-game gate, is set by script 9601, which the
    -- clear's task runs after this: Gen4ScriptVM's `bwgameclear` lowering;
    -- the marker tells src/world/Gen5ClearReplay.lua this save needs no replay)
    ctx.save.gen5Clear9601 = true
  end
  Logger.info("gen5 game clear (kind %d)", k)
  if k == 0 then
    local G = ctx.game
    local field = G and G.data and G.data.field
    local boot = field and field.boot or field
    local home = Commands.BW_HOME
    Commands.warp(ctx, (boot and boot.startMap) or home.map, (boot and boot.startX) or home.x,
                  (boot and boot.startY) or home.y, "down")
  end
  -- this port's addition: a Mystery Gift picked from a list for each clear
  -- (src/pokemon/Gen5MysteryGift.lua); the script waits for the picker
  local MG = require("src.pokemon.Gen5MysteryGift")
  if ctx.save then MG.recordClear(ctx.save) end
  local game, runner = ctx.game, ctx.runner
  if game and game.stack and ctx.save and MG.owed(ctx.save) >= 1 and #MG.available(ctx.save) > 0 then
    local resumed = false
    MG.offer(game, function()
      resumed = true
      if runner and runner.resume then runner:resume() end
    end)
    if runner and not resumed then runner:yield() end
  end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_bw_game_clear = { foreground = true, blocking = true }

-- BLACK / WHITE 0x17B <var>: 1 unless the last battle was lost
function Commands.g4_bw_battle_ok(ctx, var)
  setVar(ctx.save, tonumber(var), ctx.lastBattleResult == "lose" and 0 or 1)
end

-- BLACK / WHITE 0x121 <var>: the party members able to battle
-- BLACK / WHITE 0x121: the PC's EMPTY SLOTS, not the party. Every one of its
-- six uses reads it that way -- four against 0 (the Box is full), N's Castle
-- before its dragon goes to the Box, and the Poke Transfer Lab's "make room
-- for six Pokemon" against 6 -- and counted as healthy party members it told
-- the lab the PC was full with nothing in it. (The name is kept: the lowering
-- and the cache both spell it.)
function Commands.g4_bw_party_able(ctx, var)
  return Commands.g4_pc_free_slots(ctx, var)
end

-- BLACK / WHITE 0x245 <mode, arg>: N'S CASTLE'S DRAGON INTO THE PARTY (Z278,
-- M0556 S187F). The dragon caught in the throne room goes to the Box when the
-- party is full, and N needs it in the party for his battle:
--   mode 0 <var>   1 when the dragon is already in the party, or there is
--                  room for it
--   mode 1         the dragon from the Box into the party
--   mode 2 <var>   the party Pokemon in slot `var` to the Box, the dragon in
--                  its place ("Send which Pokemon back to your Box?")
-- Reshiram on Black, Zekrom on White; if it is nowhere at all (a save that
-- never caught it) mode 1 gives one at level 50, the battle's own level.
Commands.BW_LEGEND = { black = 643, white = 644 }
local function legendSpecies()
  local GV = require("src.core.GameVersion")
  return Commands.BW_LEGEND[GV.get()] or Commands.BW_LEGEND.black
end
local function legendInBoxes(save, species)
  for b, box in pairs(save.boxes or {}) do
    for slot, mon in pairs(box) do
      if type(mon) == "table" and tonumber(mon.species) == species then return b, slot, mon end
    end
  end
end
function Commands.g4_bw_legend(ctx, mode, arg)
  local save = ctx.save
  if not save then return end
  save.party = save.party or {}
  local party, species = save.party, legendSpecies()
  local inParty = false
  for _, mon in ipairs(party) do if tonumber(mon.species) == species then inParty = true end end
  local m = math.floor(valueOf(ctx, mode) or 0)
  if m == 0 then
    setVar(save, tonumber(arg), (inParty or #party < 6) and 1 or 0)
    return
  end
  if inParty then return end
  local b, slot, mon = legendInBoxes(save, species)
  if m == 2 then
    local pick = math.floor(valueOf(ctx, arg) or -1) + 1
    local out = party[pick]
    if not (out and mon) then return end
    save.boxes[b][slot] = out
    party[pick] = mon
    return
  end
  if mon and #party < 6 then
    save.boxes[b][slot] = nil
    party[#party + 1] = mon
  elseif not mon then
    Commands.g4_give_pokemon(ctx, species, 50, 0, nil)
  end
end

function Commands.g4_bw_condition(ctx, n, var)
  local row = Commands.BW_CONDITIONS[math.floor(valueOf(ctx, n) or -1)]
  local yes = row and getVar(ctx.save, row[1]) == row[2]
  setVar(ctx.save, tonumber(var), yes and 1 or 0)
end

-- BLACK / WHITE 0x1A2: an Elite Four room's lift. The platform carries the
-- player up their own column, past the solid rows, to the first floor tile
-- that has floor beyond it (the lone tile in the shaft, (15, 16), does not)
function Commands.g4_bw_e4_lift(ctx, n)
  local ow = ctx.overworld
  local map = ow and ow.map
  local p = ow and ow.player
  if not (map and p) then return end
  local x = p.cellX
  local function open(cx, cy) return cy >= 0 and map:isWalkableCell(cx, cy) end
  local y, seenSolid = p.cellY - 1, false
  while y > 0 do
    if not open(x, y) then seenSolid = true
    elseif seenSolid and open(x, y - 1) then break end
    y = y - 1
  end
  if y <= 0 then return end
  return Commands.warp(ctx, map.id, x, y, "up")
end

-- OPELUCID GYM (Gen5DragonGym): 0x196, 0x19A <statue, side>, 0x199 <statue>
function Commands.g4_bw_dragon_init(ctx)
  require("src.world.Gen5DragonGym").apply(ctx.overworld, ctx.save)
end
function Commands.g4_bw_dragon_flip(ctx, statue, side)
  require("src.world.Gen5DragonGym").flip(ctx.save, math.floor(valueOf(ctx, statue) or 0),
                                          math.floor(valueOf(ctx, side) or 0))
end
function Commands.g4_bw_dragon_settle(ctx, statue)
  require("src.world.Gen5DragonGym").settle(ctx.overworld, ctx.save, math.floor(valueOf(ctx, statue) or 0))
end

function Commands.g4_bw_lift_move(ctx, n)
  local ow = ctx.overworld
  if ow then require("src.world.Gen5DriftveilGym").move(ow, ctx.save, math.floor(valueOf(ctx, n) or 0)) end
end

-- NIMBASA GYM: turn coaster track n's switch over (the floor switch's
-- 0x180). Kept in the save, as the cartridge keeps it in the gym's block.
function Commands.g4_bw_coaster_switch(ctx, n)
  local save = ctx.save
  if not save then return end
  save.bwCoaster = save.bwCoaster or {}
  local k = tostring(math.floor(valueOf(ctx, n) or 0))
  save.bwCoaster[k] = (save.bwCoaster[k] == 1) and 0 or 1
end

-- BLACK / WHITE'S SEASON: one a month in turn, January spring, so
-- (month - 1) % 4 -- 0 spring, 1 summer, 2 autumn, 3 winter
function Commands.g4_bw_season(ctx, destVar)
  setVar(ctx.save, destVar, ((tonumber(os.date("%m")) or 1) - 1) % 4)
end
-- 0x02B <var, value>: var *= value (the handler's `muls`, kept to a u16)
function Commands.g4_bw_mul_var(ctx, destVar, value)
  setVar(ctx.save, destVar, (getVar(ctx.save, destVar) * valueOf(ctx, value)) % 65536)
end
-- 0x232 <index, dest>: dest = the park-visitor table's entry (constants,
-- read off the handler by RomExtractorGen5)
function Commands.g4_bw_park_visitor(ctx, index, destVar)
  local data = ctx.game and ctx.game.data or (_G.Game and _G.Game.data)
  local t = data and data.constants and data.constants.gen5ParkVisitors
  local i = math.floor(valueOf(ctx, index) or 0)
  setVar(ctx.save, destVar, t and (t[i] or t[tostring(i)]) or 0)
end

-- BLACK / WHITE'S ELEVATORS: the building's floors (Gen5ScriptLink reads the
-- table out of the script file), the menu of every floor but this one, the
-- choice, and the ride -- a warp to the floor's zone at its car's tile.
function Commands.g4_bw_elevator(ctx, floors)
  ctx.bwElevator, ctx.bwElevatorPick = floors or {}, nil
end
function Commands.g4_bw_elevator_floors(ctx)
  local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
  local here = def and tonumber(def.header)
  for i, f in ipairs(ctx.bwElevator or {}) do
    if f.zone ~= here then Commands.g4_menu_entry(ctx, f.label, i - 1) end
  end
end
function Commands.g4_bw_elevator_pick(ctx, var)
  local i = tonumber(valueOf(ctx, var))
  ctx.bwElevatorPick = i and (ctx.bwElevator or {})[i + 1] or nil
end
function Commands.g4_bw_elevator_warp(ctx)
  local f = ctx.bwElevatorPick
  if not f then return end
  return Commands.g4_warp(ctx, f.zone, f.x, f.y, 1)
end

-- BLACK / WHITE 0x049: Black's entry, or White's
function Commands.g4_bw_version_message(ctx, black, white, bank)
  local entry = require("src.core.GameVersion").get() == "white" and white or black
  if bank then return Commands.g4_message_bank(ctx, bank, entry) end
  return Commands.g4_message(ctx, entry)
end

function Commands.g4_message_var(ctx, id, bank)
  if bank then return Commands.g4_message_bank(ctx, bank, getVar(ctx.save, id)) end
  return Commands.g4_message(ctx, getVar(ctx.save, id))
end

-- `messagefromtrainertype` -- NO OPERANDS AT ALL, and the entry is the object's
-- own trainer type:
--
--     u8 trainerType = MapObject_GetTrainerType(*mapObj);
--     ScriptMessage_Show(ctx, ctx->loader, trainerType, TRUE, NULL);
--
-- `*mapObj` is SCRIPT_MANAGER_TARGET_OBJECT, which is `ctx.npc` here, and a
-- Gen 4 object record carries `trainerType` (`Gen4Events` reads it at offset 6
-- of the event row).  The bank came in with the row, resolved at lowering time
-- from the member the block lives in, exactly as `message`'s does.
--
-- WHAT IT IS FOR: a line selected by what KIND of trainer is speaking, so one
-- script serves a whole class of object.  A missing type is 0, which is the
-- bank's first entry -- the same thing the cartridge would print for an object
-- whose type is 0, so there is nothing to invent.
function Commands.g4_message_trainer_type(ctx, bank)
  local def = ctx.npc and ctx.npc.def
  local entry = math.floor(tonumber(def and def.trainerType) or 0)
  if not def and not Gen4Commands._saidTrainerType then
    Gen4Commands._saidTrainerType = true
    Logger.warn("gen4 script: `messagefromtrainertype` ran with no target "
                .. "object, so the line is the bank's entry 0 rather than the "
                .. "speaker's own")
  end
  if bank then return Commands.g4_message_bank(ctx, bank, entry) end
  return Commands.g4_message(ctx, entry)
end

-- `showyesnomenu <destVar>`: the engine's `ask` leaves its answer on the
-- context, and the cartridge's scripts read it out of a var.
--
-- AND YES IS ZERO.  `include/constants/menu.h` is explicit --
-- `MENU_YES 0`, `MENU_NO 1` -- and `ScriptContext_WaitForYesNoResult` writes
-- exactly those two into the destination and nothing else.  A menu numbers its
-- rows from the top, so the FIRST row is 0; the intuitive "1 means yes" is the
-- trap, and this wrote it.
--
-- SO EVERY YES/NO QUESTION IN SINNOH READ BACKWARDS.  Reported from play on
-- Rowan's *"do you truly love Pokemon?"*: answering yes stored 1, the script's
-- first test is `comparevartovalue <var> 0` for the YES branch, that failed,
-- the next test `comparevartovalue <var> 1` matched, and he took the NO branch
-- and asked again.
--
-- MEASURED over the whole cartridge: 511 `showyesnomenu` sites, 496 of them
-- followed IMMEDIATELY by `comparevartovalue` -- 319 testing 0 first and 177
-- testing 1 first.  Both values are compared explicitly somewhere, so there is
-- no convention to get away with: the var has to carry the cartridge's own
-- numbers.
--
-- THE VAR AND THE COMPARISON REGISTER ARE NOT THE SAME NUMBER, which is what
-- this conflated.  The register is the PORT's boolean -- 1 means "the condition
-- holds" for every other command in this file and `holds()` reads it that way
-- -- while the var is the cartridge's menu value.  The cartridge's own handler
-- never touches the register at all; the `comparevartovalue` on the next row
-- sets it.
Gen4Commands.MENU_YES, Gen4Commands.MENU_NO = 0, 1

function Commands.g4_from_yesno(ctx, destVar)
  local said = ctx.lastCheck == true
  if destVar then
    setVar(ctx.save, destVar,
           said and Gen4Commands.MENU_YES or Gen4Commands.MENU_NO)
  end
  setResult(ctx, said and 1 or 0)
end

-- BY LOCAL ID, NOT BY NAME.  The engine's own `show_object` / `hide_object`
-- take a map id and an object NAME, which is how Gen 1-3 scripts address
-- them; a Gen 4 object event carries a numeric `localID` and no name at all,
-- so those two would look up nothing.  Walking the live entities is the join
-- that exists on this side.
local movedNobody = {}

-- TWO OBJECTS CAN SHARE A LOCAL ID, AND THE LOWEST INDEX WINS.
--
-- Twinleaf carries the guitarist at object index 4 and an arrow signpost at
-- index 8, and BOTH have localId 3 -- that is what the cartridge stores, read
-- straight off the `ObjectEvent` struct whose layout matches pret's field for
-- field.  The hardware resolves it by searching its object array in order and
-- taking the first match, so the guitarist wins and the signpost is never
-- addressed by anything (its script id is 0xFFFF -- it has none).
--
-- This walked `overworld.entities`, which is NOT in map-object order -- it is
-- the live cast, pooled and rebuilt, with the player in it -- so the signpost
-- won instead.  `ApplyMovement LOCALID_GUITARIST` then walked a signpost that
-- sits at local y = -8, off its own map: it set off north out of the world and
-- never arrived, `WaitMovement` never returned, and the input gate stayed shut
-- with nothing on screen.  Reported from play as the guitarist never walking
-- over, and caught by the queue watchdog naming it:
--
--   1 scripted move(s) queued: [1] T01_obj_8 dir=up remaining=0 pause=nil
--   moving=true cell=16,-16 target=16,-17
--
-- Ordering by the def's own index is the cartridge's rule, not a tie-break
-- invented here.
--
-- ...AND THREE IDS THAT ARE NOT LOCAL IDS AT ALL.  constants/scrcmd.h:
--
--     #define LOCALID_CAMERA   0xF1
--     #define LOCALID_FOLLOWER 0xF2
--     #define LOCALID_PLAYER   0xFF
--
-- `GetLocalMapObjByIndex` branches on all three BEFORE it searches the object
-- array, so none of them is ever compared against a real `localID`.  Only the
-- player's was known here, and only inside `g4_move`; every other command that
-- takes an object id -- turn, place, show, hide -- searched for an object
-- numbered 242 and found nobody.
local warnedCamera = false

local function objectById(ctx, id)
  local overworld = ctx.overworld
  local wanted = tonumber(id)
  -- AN OBJECT ID OPERAND IS A VAR OR A LITERAL, and this read the literal
  -- only.  Every object-id operand on the cartridge is read with
  -- `ScriptContext_GetVar`, which is `FieldSystem_TryGetVar`: if the number
  -- names a variable, take its value; if it does not, the number IS the
  -- value.  `valueOf` above is already that rule -- it was written for
  -- `g4_set_var` and never reached the object lookup.
  --
  -- WHAT IT COST: `ApplyMovement VAR_0x8007` walked local id **32775**.
  -- Measured in the overworld harness, talking to the Pokemon Centre nurse:
  -- `no object with localId 32775 on T02PC0101 -- the movement is dropped`
  -- (live localIds 0,1,2,3,4).  She never turns to the machine and never
  -- turns back, which is the play report's "does not animate".
  --
  -- 39 of Sinnoh's 2,215 ApplyMovement sites name a var, and 29 of those are
  -- `VAR_LAST_TALKED` -- the ordinary "the person you are talking to moves"
  -- idiom -- so this is not one nurse.
  --
  -- RESOLVED BEFORE the 0xFF/0xF2/0xF1 branches below, because the cartridge
  -- resolves first too and a var can legitimately hold LOCALID_PLAYER.
  -- Cannot collide with a real local id: those are 0..255 plus the three
  -- specials, and `VARS_START` is 0x4000.
  if wanted and ctx.save and isVarId(wanted) then
    wanted = tonumber(valueOf(ctx, wanted)) or wanted
  end
  if not (overworld and overworld.entities and wanted) then return nil end
  if wanted == 0xFF then return overworld.player end
  if wanted == 0xF2 then
    return require("src.world.Gen4Follower").current(overworld)
  end
  if wanted == 0xF1 then
    -- THE SCRIPT CAMERA IS A REAL BODY, and that was the surprise.
    -- `ScrCmd_AddFreeCamera` calls `MapObjectMan_AddMapObject(...,
    -- OBJ_EVENT_GFX_INVISIBLE, ...)` and then `Camera_TrackTarget` on its
    -- position: a scripted pan is an invisible object being WALKED with
    -- ordinary movement actions while the camera follows it.
    -- `ApplyFreeCameraMovement` is not even its own opcode -- the macro
    -- expands to `ApplyMovement LOCALID_CAMERA`.  So one lookup here makes
    -- every camera pan in the game work through the movement path that
    -- already exists.
    if not warnedCamera and not overworld.gen4Camera then
      warnedCamera = true
      Logger.warn("gen4 script: LOCALID_CAMERA (0xF1) was addressed on %s with "
                  .. "no free camera standing -- `addfreecamera` never ran, so "
                  .. "the row is dropped and the view stays on the player",
                  tostring(overworld.map and overworld.map.id))
    end
    return overworld.gen4Camera
  end
  local best, bestIndex, bestHidden
  for _, e in ipairs(overworld.entities) do
    -- On the def, because that is where the extractor writes it; checked on
    -- the entity too so a future spawner that copies it up still matches.
    local localId = e.localId or (e.def and e.def.localId)
    if localId == wanted then
      local index = tonumber(e.def and e.def.index) or math.huge
      -- ...THE ONE STILL THERE before one already taken away: Black / White
      -- spawn a temporary under the same id more than once (Castelia's gym
      -- door, Z031 M0062 S00B0: 251 as Cheren, removed, then 251 again), and
      -- the second `removeobject 251` hid the first one over again -- the
      -- second stood in the gym's doorway for the rest of the session
      local hidden = (e.hidden and not e.buried) and true or false
      if not best or (bestHidden and not hidden)
         or (hidden == bestHidden and index < bestIndex) then
        best, bestIndex, bestHidden = e, index, hidden
      end
    end
  end
  return best
end
Gen4Commands.objectById = objectById

-- THE SAME FOUR NUMBERS, INVERTED. `scrcmd 18C` hands a direction to an
-- object, and the mapping from the cartridge's number to this engine's facing
-- name is the table above read the other way -- derived once, not typed twice,
-- because two spellings of one mapping in two places is this port's recurring
-- bug in its smallest form.
local FACE_NAME = {}
for name, n in pairs(FACING) do FACE_NAME[n] = name end

-- `scrcmd 18C` -- "turn this object to face <dir>", and it was filed as "a
-- Spear Pillar effect" because that is where most of its fifteen sites are.
--
--     static BOOL ScrCmd_18C(ScriptContext *ctx) {
--         u16 localID = ScriptContext_GetVar(ctx);
--         u16 dir     = ScriptContext_GetVar(ctx);
--         MapObject *mapObj = MapObjMan_LocalMapObjByIndex(..., localID);
--         ov5_021ECDFC(mapObj, dir);
--     }
--
-- and `ov5_021ECDFC` is `MapObject_TryFace(mapObj, dir)` plus a shadow nudge
-- for an object mid-jump. `ScrCmd_FaceTargetObject` and `trainer_encounter.c`
-- call the very same function, so this port already does this -- under another
-- name, for another command. Naming a command after the map it appears on is
-- how a bread-and-butter object operation ends up looking like an
-- unimplementable set-piece.
--
-- Fifteen sites across three bands: local ids 5, 3 and 0xFF (LOCALID_PLAYER,
-- which `objectById` already resolves), directions 0 through 3 -- all four.
function Commands.g4_face_dir(ctx, localID, dir)
  local e = objectById(ctx, localID)
  if not e then return end
  local n = math.floor(tonumber(valueOf(ctx, dir)) or -1)
  local name = FACE_NAME[n]
  if not name then
    require("src.core.Logger").warn(
      "gen4 script: scrcmd 18C asked for direction %d, which is not one of "
      .. "DIR_NORTH/SOUTH/WEST/EAST (0-3) -- the object is left as it was", n)
    return
  end
  e.facing = name
end


-- `addobject` / `removeobject`, AND THE FLAG THAT MAKES THEM STICK.
--
-- `ScrCmd_RemoveObject` calls `MapObject_SetFlagAndDeleteObject` -- it SETS the
-- object's own `hiddenFlag` and then deletes the live actor.  The flag is the
-- durable half: `sub_020620C4` spawns an object event only when it has no
-- script or `FieldSystem_CheckFlag(hiddenFlag)` is FALSE, so once the flag is
-- set the object never comes back, on this visit or any later one.
--
-- This port wrote only the live half, so every character a script dismissed was
-- standing there again the next time the player walked in -- and 1,566 of the
-- cartridge's 3,555 object events (44%) carry such a flag.  The flag name is
-- `Gen4ScriptVM.flagName`'s, the same spelling `setflag` and `checkflag` use,
-- and `OverworldController.objectVisible` already reads `obj.eventFlag` out of
-- `save.flags` -- so writing it here is the whole fix on the engine side.
local function setObjectFlag(ctx, entity, hidden)
  local def = entity and entity.def
  local flag = def and def.eventFlag
  if not flag then return end
  ctx.save.flags = ctx.save.flags or {}
  ctx.save.flags[flag] = hidden and true or false
end

-- `addobject` HAS TO BE ABLE TO SPAWN SOMEBODY WHO IS NOT THERE, which is the
-- whole point of it.
--
-- Barry's scene in the player's bedroom is the case that shows why:
--
--     clearflag 0x173 / addobject 0 / applymovement 0 ... / message / ...
--
-- He is HIDDEN when the map loads -- flag 0x173 is one of the 112 the new-game
-- script sets -- so by the time `addobject` runs there is no live actor with
-- localId 0 to find, and a lookup among the spawned entities answers nil.  The
-- `clearflag` before it does re-sync him through `syncFlagObjects`, so the
-- order happens to save this particular script; a script that calls
-- `addobject` without one would still find nothing.
--
-- So the object is looked up in the MAP DEFINITION when it is not on the map,
-- and the overworld is asked to re-derive it.  That is the same call
-- `clearflag` makes, so there is one mechanism rather than two.
local function defByLocalId(ctx, id)
  local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
  local wanted = tonumber(id)
  if not (def and def.objects and wanted) then return nil end
  for _, obj in ipairs(def.objects) do
    if obj.localId == wanted then return obj end
  end
  return nil
end

function Commands.g4_show_object(ctx, id)
  local e = objectById(ctx, id)
  if e then
    e.hidden = nil
    setObjectFlag(ctx, e, false)
    return
  end
  -- Not on the map.  Clear the flag that is keeping it off, then ask the
  -- overworld to spawn it from its own record.
  local def = defByLocalId(ctx, id)
  if not def then return end
  if def.eventFlag then
    ctx.save.flags = ctx.save.flags or {}
    ctx.save.flags[def.eventFlag] = false
  end
  local ow = ctx.overworld
  if ow and ow.syncObjectVisibility then
    pcall(function() ow:syncObjectVisibility(def) end)
  end
end

function Commands.g4_hide_object(ctx, id)
  local e = objectById(ctx, id)
  if not e then return end
  -- A BLACK / WHITE TEMPORARY SPAWNED AGAIN UNDER THE SAME ID whose body is
  -- not up yet: the one found is the earlier, already removed. The later
  -- template is the one this removes (Castelia's gym door, Z031 M0062
  -- S00B0: 251 spawned, removed, spawned again, removed -- the second stood
  -- in the doorway for the rest of the session).
  if e.hidden and e.def and e.def.gen5Temp then
    local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
    for _, o in ipairs(def and def.objects or {}) do
      if o.gen5Temp and o.localId == e.def.localId and not o.hidden then
        o.hidden = true
        local ow = ctx.overworld
        if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(o) end) end
      end
    end
  end
  e.hidden = true
  -- a Black / White temporary (g4_bw_spawn_object) is gone for good
  if e.def and e.def.gen5Temp then e.def.hidden = true end
  setObjectFlag(ctx, e, true)
end

-- HGSS's MakeObjectVisible (on) / ScrCmd_374 (off): the object stops being
-- DRAWN and nothing else -- it stays solid and its event flag is untouched
-- (MAPOBJECTFLAG_VISIBLE is the hide bit; see Gen4ScriptVM's ScrCmd_374 and
-- src/world/HgssModelObjects.lua)
function Commands.g4_object_invisible(ctx, id, on)
  require("src.world.HgssModelObjects").setInvisible(ctx.overworld, objectById(ctx, id), on)
end

-- WHICH WAY AN OBJECT FACES, set by a script rather than by its template.
--
-- Written to the LIVE actor and to its DEF: the def is what a re-entry to the
-- map spawns from, and a map entry script that turns somebody to face the
-- stairs means them to be facing the stairs the next time you walk in too.
local DIRECTION_OF = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }

function Commands.g4_set_object_dir(ctx, id, dir)
  local e = objectById(ctx, id)
  if not e then return end
  local facing = DIRECTION_OF[valueOf(ctx, dir)]
  if not facing then return end
  e.facing = facing
  if e.def then e.def.direction = valueOf(ctx, dir) end
end

-- HOW AN OBJECT BEHAVES WHEN NOBODY IS TALKING TO IT, and this one is honestly
-- partial.
--
-- The cartridge's movement types are its own numbering -- `setobjecteventmove-
-- menttype 0, 14` on the player's house -- and this engine's NPC only knows
-- Gen 3's table, which is a DIFFERENT numbering.  Mapping one onto the other
-- because both are small integers is how an NPC ends up spinning on the spot
-- for no reason.
--
-- So the value is recorded on the def, where it is the cartridge's own number
-- and a future reader gets the right one, and the BEHAVIOUR is not derived.
-- Named rather than silent: this used to go through the unknown-command path,
-- which said nothing about what was missing.
local warnedMovement = false

function Commands.g4_set_object_movement(ctx, id, movementType)
  local e = objectById(ctx, id)
  if not e then return end
  local value = valueOf(ctx, movementType)
  if e.def then e.def.movementType = value end
  if not warnedMovement then
    warnedMovement = true
    Logger.warn("gen4 script: `setobjecteventmovementtype` recorded type %s on "
                .. "an object's template -- the live object keeps the type it "
                .. "spawned with until the map is built again, as on the cartridge",
                tostring(value))
  end
end

-- ...AND THE OTHER MOVEMENT-TYPE COMMAND, WHICH IS A DIFFERENT COMMAND.
--
-- The cartridge has two and they do not do the same thing:
--
--   `setobjecteventmovementtype`  (90 sites)  ScrCmd_SetObjectEventMovementType
--       -> MapHeaderData_SetObjectEventMovementType -- rewrites the map's
--          stored TEMPLATE, which is what the next map build spawns from.
--          That is the one above.
--   `setmovementtype`             (30 sites)  ScrCmd_SetMovementType
--       -> MapObject_SwitchMovementType -- rewrites the LIVE actor, now.
--
-- Only the first was lowered, so all thirty of the live ones went through the
-- unknown-command path.  Eight of those thirty are
-- `MOVEMENT_TYPE_FOLLOW_PLAYER`, and those eight are the whole partner system:
-- Barry out of Twinleaf, Cheryl through Eterna Forest, Riley on Iron Island,
-- Marley through Victory Road, Mira in Wayward Cave, Buck up Stark Mountain,
-- and Amity Square's pet.
--
-- The trailing itself lives in `src/world/Gen4Follower.lua`; this is the seam.
function Commands.g4_switch_movement(ctx, id, movementType)
  local e = objectById(ctx, id)
  if not e then return end
  local value = valueOf(ctx, movementType)
  local Follower = require("src.world.Gen4Follower")
  local ow = ctx.overworld
  if value == Follower.FOLLOW_PLAYER or value == Follower.FOLLOW_PARTNER then
    e.g4Move = nil   -- the follower walks it now, not its old movement type
    Follower.adopt(ctx.save, ow, e)
    return
  end
  -- Switching the follower to anything else is how a script STOPS somebody
  -- following -- Route 201 sends Barry back to LOOK_SOUTH when you insist on
  -- going the wrong way.
  if e.gen4Follower then Follower.release(ctx.save, ow) end
  -- Everything else is the live object's new movement type, run from its
  -- first state (MapObject_SwitchMovementType; src/world/Gen4MovementTypes).
  if e.def then e.def.movementType = value end
  require("src.world.Gen4MovementTypes").switch(e, value)
end

-- `setobjectflagispersistent <localID>, <flag>` -- MAP_OBJ_STATUS_PERSISTENT,
-- the bit `sub_0206184C` consults when it deletes every object whose header id
-- is not the new map's.  Set on a follower it is what carries them across the
-- seam; on anything else it has nothing to do here, because every other object
-- is rebuilt from its own map's template on arrival anyway.
function Commands.g4_set_object_persistent(ctx, id, flag)
  local e = objectById(ctx, id)
  if not e then return end
  local on = valueOf(ctx, flag) ~= 0
  require("src.world.Gen4Follower").setPersistent(ctx.save, ctx.overworld, e, on)
end

-- FLAG_HAS_PARTNER (0x961), the save's own memory of the escort -- and the
-- half that ENDS it.  `ClearHasPartner` appears at 22 sites and at some of
-- them it is the only thing that ends the escort: Lake Verity Low Water clears
-- it and never touches the movement type, because Barry is a real object event
-- on that map and the scene addresses him by his local id from there on.  A
-- release keyed only on the movement type would leave him trailing through the
-- Cyrus scene.
function Commands.g4_set_partner(ctx, on)
  local Follower = require("src.world.Gen4Follower")
  Follower.setPartner(ctx.save, on)
  if not on then Follower.release(ctx.save, ctx.overworld) end
end

function Commands.g4_check_partner(ctx, destVar)
  local Follower = require("src.world.Gen4Follower")
  local yes = Follower.hasPartner(ctx.save) and 1 or 0
  if destVar then setVar(ctx.save, destVar, yes) end
  setResult(ctx, yes)
end

-- `setposition <localID> <x> <z> <dir> <y>` once the VM has put the ground
-- coordinates first.  Both the actor and its def move, for the same reason the
-- facing does.
function Commands.g4_place_object(ctx, id, x, z, dir, height)
  local e = objectById(ctx, id)
  if not e then return end
  -- The script speaks matrix coordinates; the entity lives in map ones.
  local cx, cy = toLocal(ctx, valueOf(ctx, x), valueOf(ctx, z))
  e.cellX, e.cellY = cx, cy
  e.px, e.py = cx * 16, cy * 16
  local facing = DIRECTION_OF[valueOf(ctx, dir)]
  if facing then e.facing = facing end
  if e.def then
    -- ...FOR THIS VISIT ONLY. ScrCmd_MovePersonFacing / SetPosition move the
    -- live MapObject and leave the zone's event template alone, and the next
    -- map load reads the templates from ROM again. The def here is the
    -- shared `data.maps` row, so its own place is kept and put back by
    -- Gen4Commands.restorePlacedObjects on the next load (setMap); left
    -- moved, the Dragon's Den Lance and Clair (parked at (51,2)/(53,2))
    -- stood on the shrine path at (28,34)/(28,33) on every later visit.
    if e.def.g4PlacedFrom == nil then
      e.def.g4PlacedFrom = { x = e.def.x, y = e.def.y, direction = e.def.direction,
                             elevation = e.def.elevation }
    end
    e.def.x, e.def.y = cx, cy
    if facing then e.def.direction = valueOf(ctx, dir) end
    -- BW's 0x6D sign-extends the height (handler 0x021B1950, lsls/asrs #16):
    -- 0xFFFE is two below the ground (Z197's six), not 65534
    if height then
      local h = valueOf(ctx, height)
      if h >= 0x8000 and h <= 0xFFFF then h = h - 0x10000 end
      e.def.elevation = h
    end
  end
end

-- the templates g4_place_object moved, back where the map has them (a fresh
-- map load; an in-place reload keeps the scene's places)
function Gen4Commands.restorePlacedObjects(def)
  for _, obj in ipairs((def and def.objects) or {}) do
    local home = obj.g4PlacedFrom
    if home then
      obj.x, obj.y, obj.direction, obj.elevation = home.x, home.y, home.direction, home.elevation
      obj.g4PlacedFrom = nil
    end
  end
end

-- A WARP AND A SIGN CAN BE PICKED UP AND MOVED TOO.
--
-- `(index, x, z)`, every argument through `ScriptContext_GetVar`, and the
-- coordinates in the matrix's space like everything else a Gen 4 script says.
-- The index is the event's position in the map's own list, zero-based, which
-- is one less than the Lua array slot.
--
-- Written to the map DEF, which is what `warpAtCell` and the sign lookup read.
-- One divergence worth stating: on hardware `MapHeaderData` is rebuilt on every
-- map load, so a moved warp lasts until you leave; here `data.maps` is loaded
-- once and shared, so the move persists for the session.  Nothing in the
-- corpus moves a warp and then relies on it moving back, but that is an
-- observation about 38 sites rather than a guarantee.
local function eventList(ctx, key)
  local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
  local list = def and def[key]
  return type(list) == "table" and list or nil
end

local function moveEvent(ctx, key, index, x, z, what)
  local list = eventList(ctx, key)
  local slot = math.floor(valueOf(ctx, index) or -1) + 1
  local row = list and list[slot]
  if not row then
    Logger.warn("gen4 script: %s %s has no event to move on %s", what,
                tostring(index), tostring(ctx.overworld and ctx.overworld.map
                                          and ctx.overworld.map.id))
    return
  end
  row.x, row.y = toLocal(ctx, valueOf(ctx, x), valueOf(ctx, z))
  -- ...AND THE MAP'S CELL INDEX, which Map.new built from the rows at load:
  -- left stale, a moved warp still answered at its old cell. The S.S. Aqua's
  -- 1F stacks its Olivine and Vermilion gangway warps and its OnResume script
  -- moves the unused one aside (MoveWarp 0 / 12 to 27,20); with the stale
  -- index the Vermilion gangway went back to Olivine. First row wins, as at
  -- load.
  local map = ctx.overworld and ctx.overworld.map
  local w = map and map.widthCells
  if w and (key == "warps" or key == "signs") then
    local index = {}
    for i, r in ipairs(list) do
      local at = r.y * w + r.x
      if index[at] == nil then index[at] = key == "warps" and { index = i, def = r } or r end
    end
    if key == "warps" then map.warpAt = index elseif not map.signLevels then map.signAt = index end
  end
end

function Commands.g4_set_warp_pos(ctx, index, x, z)
  moveEvent(ctx, "warps", index, x, z, "warp")
end

function Commands.g4_set_bg_pos(ctx, index, x, z)
  moveEvent(ctx, "signs", index, x, z, "sign")
end

function Commands.g4_set_object_pos(ctx, id, x, y)
  local e = objectById(ctx, id)
  if not e then return end
  -- Matrix in, map out -- the same crossing `g4_place_object` makes.
  e.cellX, e.cellY = toLocal(ctx, valueOf(ctx, x), valueOf(ctx, y))
  e.px, e.py = e.cellX * 16, e.cellY * 16
  if e.def then e.def.x, e.def.y = e.cellX, e.cellY end
  -- the TEMPLATE's cell, which the cartridge's next spawn takes as the
  -- movement type's initial cell (MapObject xInitial / zInitial)
  if e.g4Move then e.g4Move.originX, e.g4Move.originY = e.cellX, e.cellY end
end

-- ---------------------------------------------------------------------------
-- waits, and the rows that are honestly not implemented
-- ---------------------------------------------------------------------------
--
-- A wait whose subject is already synchronous is a no-op and saying so is the
-- whole handler: the engine's `show_text`, `play_sound` and `play_cry` all
-- block until they are done, so the cartridge's separate wait rows have
-- nothing left to wait for.  These are handlers rather than omissions so they
-- stop going through the unknown-command path, which is what was filling the
-- log.
-- A SIGN IS ITS WORDS, and the frame round them is the engine's own.
--
-- `drawsignpostinstantmessage` and `drawsignpostscrollingmessage` now lower to
-- an ordinary message (see Gen4ScriptVM), because that is what they do on the
-- cartridge -- draw the wooden box AND print the line.  What is left of the
-- sign-box state machine is the box, and this port has one message box already
-- built out of the cartridge's own art, so these two are genuinely nothing to
-- do rather than something skipped.
local function noop() end
Commands.g4_signpost_command = noop
Commands.g4_signpost_wait = noop

-- Which line of a multi-choice sign was picked.  Answering the first is not
-- the same as asking, and it is written into the var the script compares
-- rather than left stale -- a branch on a register the last script wrote is
-- the failure this whole file exists to stop.
function Commands.g4_signpost_input(ctx, destVar)
  if destVar then setVar(ctx.save, destVar, 0) end
  setResult(ctx, 1)
end

-- `waitmovement` -- THE JOIN, and until now a no-op.
--
-- It could afford to be while `applymovement` blocked: by the time the script
-- reached this line the movement had already finished, so waiting for it was
-- waiting for nothing. Now that an apply only QUEUES, this is the line that
-- makes a cutscene wait for its actors, and 2,167 sites across the cartridge
-- depend on it.
--
-- Waits for ALL movements in flight rather than for the one object named.
-- `ScrCmd_WaitMovement` takes an id and waits on that object; the honest
-- version of that needs a per-object handle the queue does not carry yet.
-- Waiting for all of them is the conservative difference: every scene that
-- waits for the right actor still waits long enough, and one that would have
-- run on while a SECOND actor was still walking now holds until they land.
-- That is the old behaviour's timing in the worst case and the cartridge's in
-- the common one -- where the script waits once, after the last apply.
function Commands.g4_wait_move(ctx)
  if (ctx.g4Moving or 0) <= 0 then return end
  local runner = ctx.runner
  if not runner then return end
  ctx.g4MoveJoin = function() runner:resume() end
  runner:yield()
end
function Commands.g4_play_sound(ctx, soundId)
  Commands.play_sound(ctx, valueOf(ctx, soundId))
end

-- `loaddooranimation` / `playdooropenanimation` / `playdoorcloseanimation` /
-- `unloadanimation` -- one handler, because they are one feature with a slot
-- id in common and splitting them would be four places that have to agree
-- about what a tag means.
--
-- THE TAG IS THE STATE, and it lives on the overworld rather than the save:
-- `MapPropOneShotAnimationManager` is a field-system object, so a tag means
-- nothing after a map change, and persisting it into the save would make a
-- door in Jubilife answer for one in Hearthome. 52 loads against 142 plays
-- means a tag outlives the script that set it, so it cannot be script-local
-- either.
--
-- `mapX`/`mapZ` are read as raw halfwords by the cartridge and `tileX`/`tileZ`
-- through `ScriptContext_GetVar`, so only the latter two go through `valueOf`.
-- Three of the 52 load sites pass a var for a tile, which is why that matters.
-- `showmoney` / `hidemoney` / `updatemoneydisplay` -- one handler, one piece
-- of state, for the reason `g4_door_anim` is one handler: three commands with
-- a single window between them.
--
-- THE PANEL IS REBUILT RATHER THAN REFRESHED, and that is the cartridge's
-- shape rather than a shortcut. `FieldMenu_PrintMoneyToWindow` formats the
-- balance into bank 543 entry 19 and prints it; the number is spliced into a
-- cartridge string, so "refresh" means "format it again". Keeping a live
-- reference to `save.money` and formatting at draw time would be faster and
-- would also mean the window changed the instant a script took the money,
-- BEFORE the `updatemoneydisplay` the cartridge puts there -- which is the
-- beat the Game Corner's counter depends on.
--
-- On the overworld rather than the save, like the door tags:
-- `SCRIPT_MANAGER_MONEY_WINDOW` is a field-system slot, so a window does not
-- survive a map change and a saved one would come back on a map that never
-- opened it.
function Commands.g4_money_window(ctx, which, left, top)
  local ow = ctx.overworld
  if not ow then return end
  if which == "hide" then
    ow.gen4MoneyWindow = nil
    return
  end
  local MW = require("src.ui.Gen4MoneyWindow")
  if which == "show" then
    ow.gen4MoneyWindow = MW.panelFor(ctx.game, valueOf(ctx, left),
                                     valueOf(ctx, top))
    return
  end
  -- "update": the same window, where it already is. A refresh with no window
  -- open is not an error on the cartridge either -- the pointer is simply
  -- stale -- so it is a no-op rather than a warning.
  local open = ow.gen4MoneyWindow
  if not open then return end
  ow.gen4MoneyWindow = MW.panelFor(ctx.game, open.left, open.top)
end

function Commands.g4_door_anim(ctx, which, a, b, cc, d, e)
  local ow = ctx.overworld
  if not ow then return end
  local Doors = require("src.world.Gen4Doors")

  if which == "load" then
    local tag = math.floor(tonumber(e) or 0)
    local mapX = math.floor(tonumber(a) or 0)
    local mapZ = math.floor(tonumber(b) or 0)
    local tileX = math.floor(valueOf(ctx, cc) or 0)
    local tileZ = math.floor(valueOf(ctx, d) or 0)
    ow.gen4Doors = ow.gen4Doors or {}
    ow.gen4DoorProps = ow.gen4DoorProps or {}
    local model, why, info = Doors.modelAt(ctx.game and ctx.game.data,
                                           ow.map and ow.map.def,
                                           mapX, mapZ, tileX, tileZ)
    -- A MISS IS REMEMBERED AS A MISS, not left absent: `open` has to be able
    -- to tell "this tag was loaded and the model could not be identified"
    -- from "this tag was never loaded", because the first still gets the
    -- hinged sound and the second is a script fault worth hearing about.
    ow.gen4Doors[tag] = model or false
    -- THE PROP, BY IDENTITY, so the animation can find what to pose.  Kept
    -- beside the name rather than replacing it: the name is what chooses the
    -- sound, and a prop the search could not place still gets one.
    ow.gen4DoorProps[tag] = info and info.object or nil
    if not model then Doors.note(why) end
    return
  end

  if which == "unload" then
    local tag = math.floor(tonumber(a) or 0)
    if ow.gen4Doors then ow.gen4Doors[tag] = nil end
    if ow.gen4DoorProps then ow.gen4DoorProps[tag] = nil end
    -- `unloadanimation` releases the slot on the cartridge too, and it is why
    -- a finished one-shot is kept until now rather than cleared when it
    -- reaches its last frame: that frame is the pose the door holds.
    require("src.world.Gen4PropOneShot").stop(ow, tag)
    return
  end

  local tag = math.floor(tonumber(a) or 0)
  local model = ow.gen4Doors and ow.gen4Doors[tag]
  if model == nil then
    -- Not loaded on this map. The cartridge would have asserted; here the
    -- door still makes a sound, because a silent door is the fault being
    -- fixed and the hinged creak is what the cartridge plays for every model
    -- it does not name specially.
    Doors.note(("tag %d was never loaded on this map"):format(tag))
    model = false
  end
  Doors.play(ctx.game, model or "unknown-door", which)
  -- ...AND THE ANIMATION, on the same tag.  `start` refuses a tag whose
  -- animation cannot be resolved, which is what keeps `waitforanimation` from
  -- hanging on a door this port could not identify.
  require("src.world.Gen4PropOneShot").start(
    ow, tag, model or nil, which,
    ow.gen4DoorProps and ow.gen4DoorProps[tag] or nil)
end
function Commands.g4_play_cry(ctx, species)
  -- Platinum plays immediately. Its second operand is unused, whereas the
  -- shared Gen1/2 command queues a cry for a later text box.
  require('src.core.Sound').playCry(ctx.game.data, valueOf(ctx, species))
end
function Commands.g4_wait_sound(ctx, soundId)
  local Sound=require('src.core.Sound')
  local id = valueOf(ctx, soundId)
  -- WaitSE names one effect. Unrelated effects must not keep an event locked.
  ctx.runner.waitingCheck=function() return not Sound.isPlaying(id) end
  ctx.runner:yield()
end
Commands.g4_wait_fanfare = noop
function Commands.g4_wait_cry(ctx)
  local Sound=require('src.core.Sound')
  ctx.runner.waitingCheck=function() return not Sound.anyPlaying('cry') end
  ctx.runner:yield()
end
function Commands.g4_stop_sound(ctx,id)
  require('src.core.Sound').stop(valueOf(ctx,id))
end
-- `waitforanimation <tag>` -- and the tag was being thrown away.
--
-- Two things were wrong and the second hid the first.  The handler was `noop`,
-- and there were TWO lowerings for the command -- an early one onto
-- `g4_wait_animation` and a later one onto `g4_noop` that silently overwrote
-- it -- so the census filed all 48 sites under "the door animation's wait"
-- and this handler was never reached at all.
--
-- The wait is per-TAG, matching `ScrCmd_WaitForAnimation`'s byte operand, and
-- a tag that is not running is finished -- so this steps over rather than
-- stalling whenever the door could not be identified or its animation not
-- resolved.  That is what the old no-op did by accident and this does on
-- purpose.
function Commands.g4_wait_animation(ctx, tag)
  local ow = ctx.overworld
  if not ow then return end
  local OneShot = require("src.world.Gen4PropOneShot")
  if OneShot.finished(ow, tag) then return end
  ctx.runner.waitingCheck = function() return OneShot.finished(ow, tag) end
  ctx.runner:yield()
end
Commands.g4_wait_fade = noop
-- ...a no-op here (the battle has already handed the field back), except that
-- on Black / White it is the field RELOADING: a 0x021 queued after it (N's
-- Castle, M0556 S09D8: `returntofield; 40B6 = 4; queue entry 15; return`)
-- runs on that reload, with no warp to wait for (Gen5PostWarp)
function Commands.g4_return_to_field(ctx)
  local ow = ctx and ctx.overworld
  if ow and ow.map and ow.map.def and ow.map.def.gen5 then ow.gen5FieldReturn = true end
end
Commands.g4_menu_close = noop

-- PlayFanfare (pokeheartgold unk_02005D10.s 0x02006B24; Platinum's twin)
-- PAUSES the BGM's player and plays the fanfare on its own; the fanfare's end
-- resumes the paused BGM.  So the song a script put on with TempBGM / PlayBGM
-- comes back afterwards, not the map header's: New Bark's Mom scene keeps
-- SEQ_GS_E_TSURETEKE1 under her four SEQ_SE_PL_KIRAKIRA sparkles, where the
-- map-theme restore cut to SEQ_GS_T_WAKABA after the first one.
function Commands.g4_fanfare(ctx, songId)
  local Music = require("src.core.Music")
  local before = Music.current()
  local data = ctx.game and ctx.game.data
  if not Music.playOnce(data, songId, before) then return end
  local runner = ctx.runner
  runner.waitingCheck = function()
    return not Music.oneShotPlaying()
  end
  runner:yield()
end

-- !! THIS READ THE WRONG OPERAND, AND EVERY FADE IN SINNOH WENT ONE WAY.
--
-- `fadescreen` has FOUR operands, and the old lowering passed the first two
-- while this read the first:
--
--     ScrCmd_FadeScreen: transition, frames, type, color
--     StartScreenFade(FADE_BOTH_SCREENS, type, type, color, transition, frames, ...)
--     StartScreenFade(mode,            typeMain, typeSub, color, steps, framesPerStep, ...)
--
-- so operand 1 is the STEP COUNT and the DIRECTION is operand 3. Worse, the
-- old rule read "odd darkens", which is Hoenn's arrangement, not this one:
-- `generated/fade_types.txt` alternates OUT then IN in pairs -- 0
-- BRIGHTNESS_OUT, 1 BRIGHTNESS_IN, 2 DOWNWARD_OUT, 3 DOWNWARD_IN, 16
-- CIRCLE_OUT, 17 CIRCLE_IN, 40 CLAMP_OUT, 41 CLAMP_IN -- so EVEN darkens and
-- ODD brings the picture back.
--
-- MEASURED OVER ALL 736 REACHED SITES: every single one passes `steps = 6`.
-- Six is even, the old rule answered "in" for all 736, and the fade-to-black
-- before a warp or a cutscene never happened anywhere in the game. Against the
-- cartridge's own `type` parity the old reading was wrong on 362 of 736 --
-- 49.2%, which is what reading a constant instead of a variable looks like.
--
-- The other two operands are worth carrying now that they are in hand: total
-- length is steps x framesPerStep (6, 18 or 36 frames across the corpus), and
-- the colour is BGR555, where the only two values that occur are 0 (black) and
-- 32767 = 0x7FFF (white).
function Commands.g4_fade(ctx, fadeType, steps, framesPerStep, colour)
  local t = math.floor(valueOf(ctx, fadeType) or 0)
  local n = math.floor(valueOf(ctx, steps) or 6)
        * math.floor(valueOf(ctx, framesPerStep) or 1)
  if n < 1 then n = 1 end
  local c = (math.floor(valueOf(ctx, colour) or 0) ~= 0) and "white" or "black"
  Commands.fade(ctx, (t % 2 == 0) and "out" or "in", n, c)
end

-- WHAT AN NPC DOES WHILE A SCRIPT WATCHES.
--
-- `steps` is the list `Gen4Movement` decoded out of the script member at
-- import: `{ { action, count }, ... }`.  All 3,025 of the cartridge's
-- `applymovement` sites decode, and between them they are 3,351 walks, 1,705
-- marks-on-the-spot, 893 waits, 503 turns, 201 no-ops, 178 emotes and 177
-- hide/show pairs.  Every one of those was "make the object face the player"
-- until now.
--
-- PLAYED IN SEQUENCE, WHICH THE CARTRIDGE DOES NOT.  `ScrCmd_ApplyMovement`
-- STARTS an animation and lets the script carry on until `waitmovement`, so
-- two objects told to move in consecutive rows move together; here the second
-- waits for the first.  That is a timing difference in a cutscene rather than
-- a wrong one, and the alternative is a scheduler this engine's script runner
-- has no seam for.  Worth knowing before a scene with a crowd looks stilted.
function Commands.g4_move(ctx, id, steps)
  local ow = ctx.overworld
  if not ow then return end
  local Gen4Movement = require("src.import.Gen4Movement")
  -- `objectById` knows LOCALID_PLAYER / LOCALID_FOLLOWER / LOCALID_CAMERA now,
  -- so the player's special case that used to live here is gone -- one lookup
  -- for every command that takes an object id rather than one rule here and a
  -- different one everywhere else.
  local entity = objectById(ctx, id)
  if not entity then
    -- SAY WHO WAS BEING WALKED, once per id per map.
    --
    -- A movement applied to nobody is silent, and it does not fail alone: the
    -- script that queued it goes on to `WaitMovement`, so a cutscene half of
    -- whose cast is missing holds the input gate with nothing on screen --
    -- which is the log's "input has been gated for 10s ... 1 scripted move(s)
    -- queued".  Naming the id turns that into a lookup rather than a guess.
    local key = ("move:%s:%s"):format(tostring(id),
                                      tostring(ow.map and ow.map.id))
    if not movedNobody[key] then
      movedNobody[key] = true
      local seen = {}
      for _, e in ipairs(ow.entities or {}) do
        local lid = e.localId or (e.def and e.def.localId)
        if lid then seen[#seen + 1] = tostring(lid) end
      end
      table.sort(seen)
      Logger.warn("gen4 move: no object with localId %s on %s -- the movement "
                  .. "is dropped and whatever waits on it will wait forever "
                  .. "(live localIds: %s)", tostring(id),
                  tostring(ow.map and ow.map.id), table.concat(seen, ","))
    end
    return
  end

  if type(steps) ~= "table" then
    -- A cache imported before the movement lists were decoded.  Facing the
    -- player is what this did then, and a character talking to a wall is worse
    -- than one that turns round.
    --
    -- AND IT SAYS SO NOW.  This branch is indistinguishable from a working
    -- scene whose characters happen not to walk far, and on a stale cache it
    -- is EVERY applymovement in the game -- 3,025 of them -- which is a whole
    -- class of "the cutscene plays but nobody moves" with no line in the log.
    local key = ("nolist:%s"):format(tostring(ow.map and ow.map.id))
    if not movedNobody[key] then
      movedNobody[key] = true
      Logger.warn("gen4 move: this cache carries no movement list for "
                  .. "applymovement on %s, so every scripted walk here is "
                  .. "replaced by a turn towards the player -- re-import to "
                  .. "fix", tostring(ow.map and ow.map.id))
    end
    if entity ~= ow.player then Commands.face_player(ctx) end
    return
  end

  -- BLACK AND WHITE play their own action table (src/import/Gen5Movement.lua)
  -- through their own executor: speeds, locked facing, jumps, marking time
  if ow.map and ow.map.def and ow.map.def.gen5 then
    local G5 = require("src.script.Gen5MoveExec")
    local dx, dy = G5.net(steps)
    Logger.debug("g5 move: %s id %s from (%s,%s) -- %d step(s), net (%+d,%+d)",
                 tostring(ow.map.id), tostring(id), tostring(entity.cellX),
                 tostring(entity.cellY), #steps, dx, dy)
    return G5.run(ctx, entity, id, steps)
  end

  -- WHERE THIS WALK STARTS, WHICH IS THE HALF A LOG NEVER SHOWS.
  --
  -- A scripted walk that ends somewhere wrong has two possible causes and they
  -- need separating: the list was read wrong, or the walker was not standing
  -- where the cartridge thought.  The list is decoded offline and checked; the
  -- starting cell is only knowable from a running game.
  local fromX, fromY = entity.cellX, entity.cellY
  local netX, netY = 0, 0
  -- HGSS reads its own action table (Gen4Movement.HGSS_ACTIONS: 105..112 are
  -- the beasts' leaps there, Platinum's wall walks here)
  local moveFamily = require("src.core.GameVersion").family()
  for _, step in ipairs(steps) do
    local a = Gen4Movement.action(step.action, moveFamily)
    if a and a.kind == "leaps" then
      local lx, lz = require("src.script.Gen4MoveActions").net(a, step.count)
      netX, netY = netX + lx, netY + lz
    end
    if a and (a.kind == "walk" or a.kind == "jump" or a.kind == "axis"
              or a.kind == "axisJump") and a.dir then
      local n = (a.tiles or 1) * math.max(tonumber(step.count) or 1, 1)
      if a.dir == "up" then netY = netY - n
      elseif a.dir == "down" then netY = netY + n
      elseif a.dir == "left" then netX = netX - n
      elseif a.dir == "right" then netX = netX + n end
    end
  end
  Logger.debug("gen4 move: %s id %s from (%s,%s) -- %d step(s), net (%+d,%+d) "
               .. "-> expect (%s,%s)",
               tostring(ow.map and ow.map.id), tostring(id),
               tostring(fromX), tostring(fromY), #steps, netX, netY,
               tostring((tonumber(fromX) or 0) + netX),
               tostring((tonumber(fromY) or 0) + netY))

  -- QUEUED, NOT PLAYED HERE -- which is what the cartridge does.
  --
  -- Reported from play: *"in oreburg where the npc walks you to the gym it has
  -- me walk to the gym and then the player walks to the gym after i get there
  -- instead of following"*.
  --
  -- `ScrCmd_ApplyMovement` STARTS an animation and lets the script run on to
  -- `waitmovement`. This played the whole list inline through `walkEntity`,
  -- which yields per step -- so two objects told to move in consecutive rows
  -- moved one after the other instead of together. The file said so and called
  -- it a timing difference; it is a timing difference in exactly the scenes
  -- that are ABOUT timing.
  --
  -- MEASURED over the cartridge's 8,567 scripts: 3,025 `applymovement` against
  -- 2,167 `waitmovement`, and 862 of those applies are issued BACK-TO-BACK with
  -- no wait between them -- two or more actors the cartridge moves together.
  -- All 862 were being serialised, so this is 862 scenes rather than one.
  --
  -- The queue the overworld already keeps is the whole mechanism: `scriptMove`,
  -- `scriptPause` and `marchInPlace` all take a completion callback and advance
  -- on their own, and `scriptPause`'s own comment says why -- *"a delay that
  -- BLOCKS the script runner would serialise the two walks it is there to
  -- separate"*. That was already understood one layer down.
  --
  -- NOTHING IN THE CHAIN MAY YIELD. Every link after the first runs from the
  -- overworld's update rather than from inside the script coroutine, so a
  -- `Commands.wait` or `Commands.emote` here -- both of which yield -- would
  -- raise "attempt to yield from outside a coroutine" somewhere far from this
  -- line. The emote is therefore armed directly, the same way `Commands.emote`
  -- arms it, minus the yield.
  Commands.claimMove(ctx, entity)
  local index, finished = 0, false
  local function finish()
    if finished then return end
    finished = true
    if entity ~= ow.player then entity.scriptStepLen = nil end
    -- every cartridge list that locks unlocks again; one cut short (a warp,
    -- a failed step) must not leave the object unable to turn for good
    entity.g4DirLocked = nil
    ctx.g4Moving = math.max(0, (ctx.g4Moving or 1) - 1)
    -- The join, if a `waitmovement` is already parked on it.
    if ctx.g4Moving == 0 and ctx.g4MoveJoin then
      local join = ctx.g4MoveJoin
      ctx.g4MoveJoin = nil
      join()
    end
  end
  local nextStep
  local function advance()
    index = index + 1
    local step = steps[index]
    if not step then return finish() end
    local action = Gen4Movement.action(step.action, moveFamily)
    local count = math.max(tonumber(step.count) or 1, 1)
    if action == nil then
      -- An action nobody has named -- 20 steps in the whole cartridge, all in
      -- the unnamed MOVEMENT_ACTION_1xx range.  Skipped rather than guessed.
      return nextStep()
    elseif require("src.script.Gen4MoveActions").run(ctx, ow, entity, action, count, nextStep) then
      -- the nurse's bow, a held animation, the Distortion World's wall walks,
      -- the beasts' leaps (src/script/Gen4MoveActions.lua)
      return
    elseif action.kind == "walk" then
      -- ...AT THE ACTION'S OWN SPEED.  A Gen 4 movement action names a speed
      -- as well as a direction and the table carries it now; without it a
      -- scene written in WALK_FAST played at a stroll, which is the same fault
      -- Gen 3 had before `MOVE_SPEED` was read.
      --
      -- ...AND FOR PEOPLE TOO. `scriptMove` stamps the rate on
      -- `stepFramesCur`, which only Player reads; an NPC walks on
      -- `scriptStepLen` (NPC:update), so every Sinnoh / Johto NPC strolled
      -- through a WALK_FAST rush at 16 ticks a tile. Set per step, cleared
      -- on a normal step and when the list ends (Gen4MoveExec.stepLen).
      require("src.script.Gen4MoveExec").setStep(entity, ow, action.rate)
      ow:scriptMove(entity, action.dir, (action.tiles or 1) * count,
                    nextStep, entity.g4DirLocked or nil, action.rate)
    elseif action.kind == "jump" then
      -- A SCRIPTED JUMP: the cells at the action's speed, under one arc on
      -- Gen4Jump's table (Player:pose / NPC:pose draw `hopFrames`), as the
      -- Black / White executor already does (src/script/Gen5MoveExec.lua).
      -- Played as a walk it slid the actor with no hop -- the rival's shove
      -- outside Elm's lab ends in a JumpFarSouth the player never made.
      -- ONE JUMP PER REPETITION, each under its own arc with its own sounds:
      -- `JumpFarSouth 2` is two jumps (the count repeats the action), and
      -- InitJump plays SEQ_SE_DP_DANSA at every take-off and Jump_Step1
      -- SUTYA2 at every landing (Gen4MoveActions.takeoff / landing; the
      -- Distortion World's jumps take off silently, SEQ_NONE).
      local MA = require("src.script.Gen4MoveActions")
      local tiles = action.tiles or 1
      local per = math.max(1, math.floor(16 * (action.rate or 1) + 0.5))
      if not entity.g4DirLocked and action.dir then entity.facing = action.dir end
      local left = count
      local function one()
        if left <= 0 then return nextStep() end
        left = left - 1
        entity.hopFrames = per * tiles
        entity.hopTotal = entity.hopFrames
        MA.takeoff(ctx, entity, action)
        require("src.script.Gen4MoveExec").setStep(entity, ow, action.rate)
        ow:scriptMove(entity, action.dir, tiles, function()
          MA.landing(ctx, entity)
          one()
        end, entity.g4DirLocked or nil, action.rate)
      end
      return one()
    elseif action.kind == "hop" then
      -- a jump on the spot: the arc with no step, one per repetition, with
      -- InitJump's take-off and landing sounds (RevealTrainer has neither)
      local MA = require("src.script.Gen4MoveActions")
      if not entity.g4DirLocked and action.dir then entity.facing = action.dir end
      local per = math.max(1, math.floor(16 * (action.rate or 1) + 0.5))
      local left = count
      local landing = false
      local function one()
        if landing and not action.noLanding then MA.landing(ctx, entity) end
        if left <= 0 then return nextStep() end
        left = left - 1
        landing = true
        entity.hopFrames, entity.hopTotal = per, per
        MA.takeoff(ctx, entity, action)
        ow:scriptPause(entity, per, one)
      end
      return one()
    elseif action.kind == "warp" then
      -- WarpOut / WarpIn: the sprite rising out or dropping in, twenty field
      -- frames (src/world/Gen4WarpMove.lua)
      require("src.world.Gen4WarpMove").run(ow, entity, action.dir, nextStep)
    elseif action.kind == "lock" or action.kind == "unlock" then
      -- LockDir / UnlockDir: while set, no step of any list turns the object
      -- (MapObject_SetFacingDirection skips the write) -- a backward shove
      entity.g4DirLocked = action.kind == "lock" or nil
      return nextStep()
    elseif action.kind == "face" then
      if not entity.g4DirLocked then entity.facing = action.dir end
      return nextStep()
    elseif action.kind == "spot" then
      -- Marking time: the sprite animates without moving, which a cutscene
      -- uses as a pause with a facing.  One repetition costs one step, so the
      -- beat is the entity's OWN step duration rather than a number picked
      -- here -- `stepFrames`, which the field defaults put at 16.
      if not entity.g4DirLocked then entity.facing = action.dir end
      -- The beat is one walk cycle, and the on-spot actions carry the same
      -- five speeds the walking ones do -- a fast mark-time is a short beat.
      ow:scriptPause(entity, math.max(1, math.floor(
        (entity.stepFrames or 16) * (action.rate or 1) * count + 0.5)), nextStep)
    elseif action.kind == "wait" then
      -- FIELD FRAMES, not engine ticks: the field runs at 30 a second, so
      -- WAIT_8 is 16 ticks here (Gen4MoveExec.waitTicks)
      ow:scriptPause(entity, require("src.script.Gen4MoveExec").waitTicks(action.frames, count), nextStep)
    elseif action.kind == "hide" and entity == ow.player
           and require("src.core.GameVersion").family() == "hgss" then
      -- THE PLAYER'S SetInvisible IS THE SAME BIT AS ScrCmd_374 / MakeObjectVisible,
      -- and like theirs it lasts only for this map: the cartridge builds the
      -- player afresh on every load. Olivine Lighthouse 4F's window
      -- (scr_seq_D27R0105 000) walks the player out with SetInvisible and
      -- warps; the ledge outside re-hides them on resume and drops them in
      -- with WarpIn + ScrCmd_374. Written to `hidden`, 374 never reached it
      -- and the player stayed invisible for the rest of the lighthouse.
      require("src.world.HgssModelObjects").setInvisible(ow, entity, true)
      return nextStep()
    elseif action.kind == "hide" then
      entity.hidden = true
      return nextStep()
    elseif action.kind == "show" then
      entity.hidden = nil
      if entity == ow.player and entity.gen4Invisible then
        require("src.world.HgssModelObjects").setInvisible(ow, entity, false)
      end
      return nextStep()
    elseif action.kind == "emote" then
      -- EMOTE_EXCLAMATION_MARK is 73 of the cartridge's 1,278 steps -- the "!"
      -- over a trainer who has just spotted you.  Both it and the double mark
      -- are the shock bubble; this engine has three (shock, question, happy)
      -- and Platinum's movement table names no others.
      -- ...and on Sinnoh's own timing and art: 7 frames of bounce and 30 of
      -- hold (Gen4Emotes.FRAMES), "!!" for EMOTE_DOUBLE_EXCLAMATION_MARK, and
      -- the SEQ_SE_DP_DECIDE pop the field effect plays as it appears.
      -- TWO AT ONCE IS ORDINARY, and the slot used to hold one.
      --
      -- Reported from play: leaving Rowan's lab in Sandgem after the Pokedex,
      -- "the exclamation point appears but it freezes there". That scene
      -- (M1059/S057D) gives the player AND object 4 an
      -- EMOTE_EXCLAMATION_MARK in the same breath and then `waitmovement`s
      -- on both. The second bubble overwrote the first in `ow.emote`, so the
      -- first one's `onDone` never ran, its movement never finished, and the
      -- wait held the scene forever. A bubble that arrives while another is
      -- up now runs ALONGSIDE it (`ow.extraEmotes`), as the cartridge's two
      -- field effects do.
      local Gen4Emotes = require("src.import.Gen4Emotes")
      -- HGSS at the field's rate, two engine ticks a frame (Gen4Emotes.framesFor)
      local emoteDef = ow and ow.map and ow.map.def
      local bubble = { npc = entity, frames = Gen4Emotes.FRAMES * Gen4Emotes.ticksFor(emoteDef),
                       totalFrames = Gen4Emotes.FRAMES * Gen4Emotes.ticksFor(emoteDef),
                       bubble = (action.emote == "double_exclamation") and "double" or 1,
                       onDone = nextStep }
      if ow.emote then
        ow.extraEmotes = ow.extraEmotes or {}
        ow.extraEmotes[#ow.extraEmotes + 1] = bubble
      else
        ow.emote = bubble
      end
      pcall(function()
        require("src.core.Sound").play(ctx.game and ctx.game.data, "SEQ_SE_DP_DECIDE")
      end)
    else
      return nextStep()
    end
  end
  -- A STEP THAT RAISES MUST STILL RELEASE THE JOIN.
  --
  -- Every link after the first runs from the overworld's update, outside the
  -- runner's own error handling, and the counter above is only paid back by
  -- `finish`. Without this a single failing step -- an overworld missing one
  -- of the three queue methods, a movement aimed at an object that despawned
  -- -- left `g4Moving` raised for good, and every later `waitmovement` in the
  -- script parked forever: a frozen game instead of one skipped animation.
  -- Found by `gen4_event_completion_check`, whose stub overworld had no
  -- `scriptPause` and froze Roark in the Oreburgh Mine on exactly this.
  nextStep = function()
    local ok, err = pcall(advance)
    if not ok then
      Logger.warn("g4_move: step %d for object %s failed (%s); releasing the "
                  .. "wait on it", index, tostring(id), tostring(err))
      finish()
    end
  end
  ctx.g4Moving = (ctx.g4Moving or 0) + 1
  nextStep()
end

-- THE ONES THAT ARE NOT DONE, and are named rather than silently skipped.
--
-- Each of these needs a system this port has not built for Gen 4 yet -- the
-- trainer battle flow, the shop screen, the sign-box state machine, the
-- scripted menu.  They are registered so they do not go through the
-- unknown-command path, and each says so ONCE per session rather than once per
-- call, because a script that reaches one of these in a loop would otherwise
-- write a megabyte of identical lines.
local said = {}
-- ---------------------------------------------------------------------------
-- the scripted menu
-- ---------------------------------------------------------------------------

-- WHAT A SIGN, A LIFT AND A NURSE ALL USE, AND WHAT IT WAS MISSING.
--
-- `initlocaltextmenu` / `initglobaltextmenu` build the menu and name the var
-- the choice goes into; `addmenuentryimm` adds a line; `showmenu` opens it and
-- the cartridge blocks until the var is written.  Only the middle two were
-- lowered before, so the menu had no destination and no bank -- 186 menus,
-- every one of them branching on a register nothing had written.
--
-- The state rides on `ctx` rather than on the row list because 16 of the 170
-- `show` sites are reached from a different block than their own `init`: the
-- script `goto`s between building the menu and opening it, and a per-block
-- accumulator would lose the destination on exactly those.
local function menuState(ctx)
  ctx.g4Menu = ctx.g4Menu or { rows = {} }
  return ctx.g4Menu
end

-- `<destVar> <canExitWithB> <initialCursorPos> <bank>`.  `bank` is nil for a
-- map's own script, which is resolved per-map at the moment the line is read.
function Commands.g4_menu_init(ctx, destVar, canExitWithB, cursor, bank, anchorX, anchorY)
  ctx.g4Menu = {
    anchorX = tonumber(anchorX), anchorY = tonumber(anchorY),
    destVar = destVar,
    cancelable = (tonumber(canExitWithB) or 0) ~= 0,
    cursor = (tonumber(cursor) or 0) + 1,
    bank = tonumber(bank),
    rows = {},
  }
end

-- THE LINE ITSELF, out of the bank the init chose.
--
-- Substituted here rather than left to the text box, because a menu row is
-- drawn by src/ui/Menu and never passes through `show_text` -- "GIVE {STRVAR_1
-- 0 0 0} A NAME?" on a menu line would otherwise reach the player with the
-- braces still in it.
local function menuLine(ctx, entry)
  local menu = menuState(ctx)
  local label
  if menu.bank then
    label = require("src.import.Gen4Text").label(menu.bank, tonumber(entry) or 0)
  else
    label = lineFor(ctx, entry)
  end
  local data = ctx.game and ctx.game.data
  local text = data and data.text and data.text[label]
  -- `{CURSOR_X n}` moves the printer to n pixels from the row's start -- the
  -- Game Corner's "50 Coins{CURSOR_X 60}$1,000" is a price column -- so the
  -- row is padded out to it rather than the two halves run together
  if type(text) == "string" and text:find("{CURSOR_X", 1, true) then
    local okF, Font = pcall(require, "src.render.Font")
    text = text:gsub("^(.-){CURSOR_X (%d+)}", function(before, px)
      local left = Commands.gen4Markup and Commands.gen4Markup(before, ctx.game) or before
      local want = tonumber(px) or 0
      local guard = 0
      while okF and Font.width and Font.width(left .. " ") <= want and guard < 40 do
        left, guard = left .. " ", guard + 1
      end
      if guard == 0 then left = left .. " " end
      return left
    end, 1)
  end
  text = Commands.gen4Markup and Commands.gen4Markup(text, ctx.game) or text
  -- A line the cache has no string for keeps the label, which names the bank
  -- and the entry: a menu of blank rows says nothing, and a menu that reads
  -- TEXT_B0361_00023 says which entry to go and look at.
  return (type(text) == "string" and text ~= "") and text or label
end

function Commands.g4_menu_entry(ctx, entry, index)
  local menu = menuState(ctx)
  local text = menuLine(ctx, entry)
  -- HGSS's PC rows are two-line strings ("DEPOSIT\nPOKéMON", msg_0191
  -- 67-70) written for the touch screen's buttons; in the one-line field
  -- list the break is a space, not a glyph
  if type(text) == "string" and require("src.import.Gen4ScriptBands").family == "hgss" then
    text = text:gsub("[\n\v\f]+", " ")
  end
  menu.rows[#menu.rows + 1] = {
    text = text,
    value = tonumber(index) or (#menu.rows),
  }
end

-- `addmenuentry` and `addlistmenuentry` take their operands out of vars.
function Commands.g4_menu_entry_var(ctx, entry, index)
  return Commands.g4_menu_entry(ctx, valueOf(ctx, entry), valueOf(ctx, index))
end

-- MENU_CANCEL is -2 (constants/menu.h), written into the var as a u16 when the
-- player backs out of a menu the init marked `canExitWithB`.  Spelled here
-- rather than as a bare 65534 so a script comparing against it is readable.
local MENU_CANCEL = 0xFFFE
Gen4Commands.MENU_CANCEL = MENU_CANCEL

function Commands.g4_menu_show(ctx)
  local menu = ctx.g4Menu
  ctx.g4Menu = nil
  if not (menu and #menu.rows > 0) then
    -- Nothing was added.  The cartridge would show an empty frame and wait for
    -- a button; blocking the script on a box with no rows is worse than
    -- carrying on, so the destination is left alone and the script continues.
    Logger.warn("gen4 script: showmenu with no entries -- skipped")
    return
  end
  local Menu = require("src.ui.Menu")
  local runner = ctx.runner
  local items = {}
  local function pick(value)
    if menu.destVar then setVar(ctx.save, menu.destVar, value) end
    -- `lastChoice` is what the engine's own `choice` leaves behind, kept in
    -- step so a mod reading it sees the same thing on a Gen 4 map.
    ctx.lastChoice = { index = value, label = nil }
    runner:resume()
  end
  for i, row in ipairs(menu.rows) do
    items[i] = { label = row.text, onSelect = function()
      ctx.lastChoice = { index = row.value, label = row.text }
      pick(row.value)
    end }
  end
  -- HGSS draws the window at the script's own tile (x, y), the frame one tile
  -- outside it (ov01_021EDC84 clears both edge-anchor bits at init), so the
  -- Game Corner's menu at (1, 1) sits clear of the coin and money boxes on
  -- the right; Platinum keeps this port's own placement
  local tx, ty
  local menuFamily = require("src.import.Gen4ScriptBands").family
  if menu.anchorX and menu.anchorY and menuFamily == "hgss" then
    tx, ty = math.max(0, menu.anchorX - 1), math.max(0, menu.anchorY - 1)
  elseif menu.anchorX and menu.anchorY and menuFamily == "platinum" then
    -- PLATINUM'S OWN PLACEMENT (pt_cmd audit; field_menu.c
    -- FieldMenuManager_ShowSingleColumnMenu): the window at the script's tile
    -- (x, y), its width the widest row + CURSOR_MARGIN_SIZE (12) in tiles;
    -- SetMenuXOriginToRight / ...YOriginToBottom (ScrCmd_33A / _33B) make x
    -- the RIGHT edge (x -= width) and y the BOTTOM (y -= rows * 2)
    local x, y = menu.anchorX, menu.anchorY
    if menu.anchorRight or menu.anchorBottom then
      local okF, Font = pcall(require, "src.render.Font")
      local widest = 0
      for _, it in ipairs(items) do
        widest = math.max(widest, okF and Font.width and Font.width(it.label or "") or 0)
      end
      if menu.anchorRight then x = x - math.ceil((widest + 12) / 8) end
      if menu.anchorBottom then y = y - #items * 2 end
    end
    tx, ty = math.max(0, x - 1), math.max(0, y - 1)
  end
  local menuState_ = Menu.new(ctx.game, items, {
    tx = tx, ty = ty,
    -- `canExitWithB == 0` means B does nothing at all -- the player is made to
    -- choose.  17 of the cartridge's 186 menus are that kind.
    cancelable = menu.cancelable,
    onCancel = menu.cancelable and function() pick(MENU_CANCEL) end or nil,
    index = menu.cursor,
    onHighlight = menu.onHighlight,
  })
  -- placed in DS tiles, so drawn on the DS surface rather than centred on it
  -- as Game Boy furniture (Game:draw's classicOffset)
  if tx then
    menuState_.uiSize = function() return require("src.ui.Theme").uiSize() end
    -- and as wide as its widest row in PIXELS (ov01_021EDC84: the text width
    -- rounded up to a tile), plus the cursor's column and the frame
    local okF, Font = pcall(require, "src.render.Font")
    if okF and Font.width then
      local widest = 0
      for _, it in ipairs(items) do widest = math.max(widest, Font.width(it.label or "")) end
      menuState_.tw = math.max(4, math.ceil(widest / 8) + 3)
      -- ov01_021EDDD8: the window is the widest row + 12 pixels, the list
      -- cursor (ListMenuCursorNew: glyph 0x011F "‣", ink 1/2) at its x 0
      -- and the text at x 12 -- the arrow had sat against the letters
      menuState_.tw = math.max(4, math.ceil((widest + 12) / 8) + 2)
      -- Menu.new nudged tx left for ITS width guess (characters + 3); with
      -- the real width in hand the window goes back where the script put it,
      -- kept on the DS screen, and the labels follow the frame
      local cols = math.floor(select(1, menuState_.uiSize()) / 8)
      menuState_.tx = math.max(0, math.min(tx, cols - menuState_.tw))
      menuState_.labelX = (menuState_.tx + 1) * 8 + 12
    end
  end
  ctx.game.stack:push(menuState_)
  runner:yield()
end

-- A MENU IS A SCREEN, so it may not be opened from a parallel script -- the
-- same rule `choice` and `ask` already carry.  `g4_move` blocks but does not
-- take the screen, so it is only the second half.
Commands.meta = Commands.meta or {}
Commands.meta.g4_menu_show = { foreground = true, blocking = true }
Commands.meta.g4_move = { blocking = true }

-- A ROW THAT IS REALLY NOTHING TO DO HERE, and says which one it was.
--
-- Not `pending()`: that is for a verb whose feature is coming.  These are rows
-- whose feature this port does not have and is not waiting on -- the size
-- contest's record, the lottery number, the daily level -- and the honest
-- handler for one of those is to do nothing and be able to say so.
local noopSeen = {}

-- `ScrCmd_SetHiddenLocation` -- sets the location's var to its magic number,
-- or clears it. The matrix patches that read it run on the next map load, as
-- the cartridge's do (Gen4HiddenPaths, MapLoader.load).
function Commands.g4_set_hidden_location(ctx, location, enable)
  local Gen4HiddenPaths = require("src.world.Gen4HiddenPaths")
  Gen4HiddenPaths.set(ctx.save, valueOf(ctx, location), (tonumber(enable) or 0) ~= 0)
end

-- DAILY SWARMS (`ScrCmd_EnableSwarms`, `ScrCmd_GetSwarmMapAndSpecies`).
function Commands.g4_enable_swarms(ctx)
  require("src.world.Gen4Swarms").enable(ctx.save)
end
function Commands.g4_swarm_map_species(ctx, mapVar, speciesVar)
  local header, species = require("src.world.Gen4Swarms")
    .mapAndSpecies(ctx.game and ctx.game.data, ctx.save)
  setVar(ctx.save, mapVar, header)
  setVar(ctx.save, speciesVar, species)
end

-- HGSS MASS OUTBREAKS (`ScrCmd_EnableMassOutbreaks`; ScrCmd_211 is
-- GetSwarmInfoFromRand: today's map header and its swarm species).
function Commands.g4_hgss_enable_outbreaks(ctx)
  require("src.world.HgssOutbreaks").enable(ctx.save)
end
function Commands.g4_hgss_outbreak_info(ctx, mapVar, speciesVar)
  local data = ctx.game and ctx.game.data
  local entry = require("src.world.HgssOutbreaks").today(ctx.save)
  local def = entry and data and data.maps and data.maps[entry[1]]
  local area = def and data.encounters and data.encounters[def.encounters or entry[1]]
  local sw = area and area.hgssSwarm or {}
  setVar(ctx.save, mapVar, tonumber(def and def.header) or 0)
  setVar(ctx.save, speciesVar, tonumber(sw[entry and entry[2] or "land"]) or 0)
end

-- THE SAFARI GAME (`ScrCmd_StartEndSafariGame`). Starting one is thirty
-- Safari Balls and a zeroed step count; ending one zeroes both. The flag the
-- cartridge sets is `save.safari` here, the field reads it
-- (`OverworldState:gen4SafariStep`, `:gen4SafariAfterBattle`) and so does the
-- battle (`BattleState:makeSafari`). The catch count is the port's own tally
-- for `getcurrentsafarigamecaughtnum` -- the cartridge reads it off the TV
-- broadcast's Safari record, which counts the same thing.
Commands.SAFARI_BALLS, Commands.SAFARI_STEPS = 30, 500
function Commands.g4_safari_game(ctx, state)
  local mode = math.floor(valueOf(ctx, state) or 0)
  ctx.save = ctx.save or {}
  if mode == 0 then
    ctx.save.safari = { balls = Commands.SAFARI_BALLS, steps = 0, caught = 0, gen4 = true }
  else
    if ctx.save.safari then ctx.save.gen4SafariLastCaught = ctx.save.safari.caught or 0 end
    ctx.save.safari = nil
  end
end
-- `startgreatmarshlookout`: the Great Marsh observatory's binoculars -- five
-- looks over the marsh and home (src/world/Gen4MarshLookout.lua); the script
-- waits for them
function Commands.g4_marsh_lookout(ctx)
  local runner = ctx.runner
  local started = require("src.world.Gen4MarshLookout").run(ctx.game, ctx.overworld, function()
    if runner then runner:resume() end
  end)
  if started and runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_marsh_lookout = { foreground = true, blocking = true }

function Commands.g4_safari_caught(ctx, destVar)
  local st = ctx.save and ctx.save.safari
  local n = st and st.caught or (ctx.save and ctx.save.gen4SafariLastCaught) or 0
  setVar(ctx.save, destVar, n)
end

-- THE TROPHY GARDEN (`ScrCmd_AddTrophyGardenMon`,
-- `ScrCmd_GetTrophyGardenSlot1Species`) -- see src/world/Gen4DailySlots.lua.
function Commands.g4_add_trophy_garden_mon(ctx)
  require("src.world.Gen4DailySlots").addTrophyMon(ctx.game and ctx.game.data, ctx.save)
end
function Commands.g4_trophy_garden_slot1(ctx, destVar)
  setVar(ctx.save, destVar, require("src.world.Gen4DailySlots")
    .trophySlot1Species(ctx.game and ctx.game.data, ctx.save))
end

-- AMITY SQUARE'S STEP COUNT -- see `OverworldState:gen4CountAmityStep`.
local AMITY_STEPS = 0x403A
function Commands.g4_clear_amity_steps(ctx) setVar(ctx.save, AMITY_STEPS, 0) end
function Commands.g4_get_amity_steps(ctx, destVar)
  setVar(ctx.save, destVar, getVar(ctx.save, AMITY_STEPS))
end

-- PARTY FORM CHANGES (pokeplatinum src/scrcmd.c), each followed by the
-- cartridge's `Pokedex_Capture` so the new form is registered as seen.
local function partyForms(ctx, species, apply)
  local Forms = require("src.pokemon.Gen4Forms")
  local Party = require("src.pokemon.Party")
  local data = ctx.game and ctx.game.data
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if Forms.species(mon.species) == species and not Party.isEgg(mon) then
      apply(Forms, data, mon)
      Forms.record(ctx.game, mon.species, mon)
    end
  end
end
function Commands.g4_giratina_form(ctx, form)
  local origin = (tonumber(valueOf(ctx, form)) or 0) ~= 0
  partyForms(ctx, 487, function(Forms, data, mon)
    if origin then Forms.setForm(data, mon, 1)
    else Forms.giratinaByHeldItem(data, mon) end
  end)
end
function Commands.g4_deoxys_form(ctx, form)
  local value = tonumber(valueOf(ctx, form)) or 0
  partyForms(ctx, 386, function(Forms, data, mon) Forms.setForm(data, mon, value) end)
end

function Commands.g4_noop(_, what)
  local key = tostring(what)
  if not noopSeen[key] then
    noopSeen[key] = true
    Logger.info("gen4 script: %s is not implemented; the row is a no-op", key)
  end
end

-- AND IT RETURNS THE HANDLER IT INSTALLED, which is not a convenience.
--
-- There are two spellings of this call in the file -- the bare
-- `pending("g4_use_rock_climb", ...)` and the assigned
-- `Commands.g4_open_hall_of_fame = pending(...)` (the Hall of Fame row, a real
-- screen since pass 34) --
-- and while this returned nothing, the assigned form **overwrote the handler
-- it had just installed with nil**.  Both of them: the PC's Hall of Fame row
-- (pass 173) and the seal capsule editor reached no handler at all, which is
-- not a stepped-over row, it is an unknown verb.
--
-- The assigned form reads better at a call site that wants to say what the row
-- is, so the fix is to make it work rather than to ban it.  One idea, two
-- spellings, one of them silently broken -- the bug this port keeps finding.
local function pending(verb, what)
  local fn = function()
    if said[verb] then return end
    said[verb] = true
    Logger.info("gen4 script: '%s' is decoded and lowered but %s is not built "
                .. "yet -- the row is stepped over", verb, what)
  end
  Commands[verb] = fn
  return fn
end

-- ---------------------------------------------------------------------------
-- THE NEXT LAYER DOWN -- see the matching block in Gen4ScriptVM for why these
-- and not others, and for the `ScrCmd_*` each one is read from.
-- ---------------------------------------------------------------------------

-- WHICH MAP THE PLAYER IS ON, as a HEADER id.
--
-- `mapForHeader` already goes the other way and builds its index off the same
-- `def.header` field, so this is that field read directly rather than a second
-- table that could disagree with it.
function Commands.g4_get_map_id(ctx, destVar)
  local data = ctx.game and ctx.game.data
  -- the map the player stands on NOW (fieldSystem->location->mapId): the
  -- save's position is only as fresh as the last save, and the Wi-Fi Plaza's
  -- way back (Warp VAR_UNK_4056) is this var
  local live = ctx.overworld and ctx.overworld.map and ctx.overworld.map.id
  local mapId = live or (ctx.save and ctx.save.player and ctx.save.player.map)
  local def = mapId and data and data.maps and data.maps[mapId]
  setVar(ctx.save, destVar, tonumber(def and def.header) or 0)
end

-- ---------------------------------------------------------------------------
-- TURNBACK CAVE
-- ---------------------------------------------------------------------------
--
-- `initturnbackcave <varPillarsSeen> <varRoomsVisited>` -- 20 uses, one in the
-- init script of every room of the cave, and the most widely reached unlowered
-- command in the cartridge measured by maps rather than by occurrences.
--
-- WITHOUT IT GIRATINA CANNOT BE REACHED, and not as a matter of degree: every
-- room ships with all four of its exits pointing at the entrance. Measured on
-- `D17R0105` (PILLAR_1_ROOM_1), whose four warps all carry
-- `destHeader = 268` -- the entrance. So the cave is one room you walk out of,
-- for ever, and the Giratina room has no route to it at all.
--
-- The cartridge builds the maze by REWRITING THE LOADED ROOM'S WARPS as the
-- room loads (`ScrCmd_InitTurnbackCave`, src/scrcmd.c): every exit except the
-- one you came in by is pointed at a freshly chosen room.
--
-- THE MAP IDS ARE DERIVED, not guessed, and from two sources that agree.
-- pokeplatinum's `generated/map_headers.txt` gives the header NUMBER for each
-- `MAP_HEADER_TURNBACK_CAVE_*` name by its line (line - 1, zero-based), and
-- every one of our own map defs carries that same number in `def.header` --
-- `D17R0105.header` is 271, which that list calls PILLAR_1_ROOM_1. The two
-- were worked out independently and line up across all 21 rooms.
local TURNBACK_ENTRANCE = 268
local TURNBACK_PILLAR_ROOM = 269
local TURNBACK_GIRATINA = 270

-- The eighteen pillar rooms, in the cartridge's own order: pillar 1 rooms 1-6,
-- then pillar 2, then pillar 3. The split run (271-273 then 518-520) is the
-- cartridge's own numbering and not a transcription slip -- the first three
-- rooms were laid out with the entrance and the rest were appended later.
local TURNBACK_ROOMS = {
  271, 272, 273, 518, 519, 520,
  521, 522, 523, 524, 525, 526,
  527, 528, 529, 530, 531, 532,
}

-- A header number back to the map id that carries it. Built once and kept on
-- the data table rather than recomputed per call: 593 defs is not free, and a
-- room load runs this immediately.
local function mapForHeader(data, header)
  if not (data and data.maps and header) then return nil end
  local index = rawget(data, "_gen4HeaderIndex")
  if not index then
    index = {}
    for id, def in pairs(data.maps) do
      local h = tonumber(def.header)
      -- the alias copy (`sourceId`, Data.lua's `D27R0107` -> `D_27R_0107`)
      -- never wins over its map, as in the `mapForHeader` above this one:
      -- `setspeciallocation` sent the Olivine Lighthouse lift to the copy,
      -- whose scripts no index knows, and Jasmine would not take the potion
      if h and not (def.sourceId and index[h]) then index[h] = id end
    end
    rawset(data, "_gen4HeaderIndex", index)
  end
  return index[math.floor(header)]
end

-- WHICH OF THE FOUR EXITS THE PLAYER CAME IN BY, from where they are standing.
--
-- Transcribed from the cartridge, including the shape of its final `else`:
--
--     if (xPos == 11) { zPos == 1 ? 0 : zPos == 20 ? 2 : 5 }
--     else            { xPos == 20 ? 1 : 3 }
--
-- 5 is not a warp. Four warps are rewritten in a loop over 0..3, so an entry
-- of 5 matches none of them and ALL FOUR are repointed -- which is what
-- happens when the script runs with the player somewhere other than a doorway,
-- and is reproduced rather than tidied away.
local function turnbackEntryWarp(x, z)
  if x == 11 then
    if z == 1 then return 0 end
    if z == 20 then return 2 end
    return 5
  end
  if x == 20 then return 1 end
  return 3
end

function Commands.g4_init_turnback_cave(ctx, varPillars, varRooms)
  local ow = ctx.overworld
  local data = ctx.game and ctx.game.data
  if not (ow and ow.map and data) then return end
  local pillarsSeen = math.floor(valueOf(ctx, varPillars) or 0)
  local roomsVisited = math.floor(valueOf(ctx, varRooms) or 0)

  -- The cartridge's own ladder, in its own order. Three pillars seen is the
  -- way out to Giratina; thirty rooms without finding them puts you back at
  -- the entrance; otherwise a one-in-four chance of a pillar room and
  -- otherwise one of the six rooms belonging to the pillar you are on.
  local header
  if pillarsSeen >= 3 then
    header = TURNBACK_GIRATINA
  elseif roomsVisited >= 30 then
    header = TURNBACK_ENTRANCE
  elseif math.random(0, 99) < 25 then
    header = TURNBACK_PILLAR_ROOM
  else
    -- `pillarRooms[(rand % 6) + pillarsSeen * 6]`. Clamped, because a save
    -- whose counter has gone past 2 would index off the end of the table and
    -- raise under the player rather than putting them somewhere.
    local band = math.min(math.max(pillarsSeen, 0), 2)
    header = TURNBACK_ROOMS[math.random(0, 5) + band * 6 + 1]
  end

  local dest = mapForHeader(data, header)
  if not dest then
    Logger.warn("gen4 turnback cave: no map carries header %s -- this cache "
                .. "predates the Turnback rooms, so the maze cannot be built",
                tostring(header))
    return
  end

  local p = ow.player
  local entry = turnbackEntryWarp(p and p.cellX, p and p.cellY)

  -- HELD ON THE SAVE, NOT WRITTEN INTO THE MAP.
  --
  -- The cartridge edits the loaded map header's warp events, which live only
  -- as long as that load. Here `MapLoader` caches one def per map id and hands
  -- the SAME table to everything -- the renderer, the editor, the next visit --
  -- so writing a destination into it would make one visit's maze permanent and
  -- leak into every other reader of that map.
  --
  -- The save is also where `gen4SpecialLocation` keeps the lifts' dynamic
  -- destination, so this follows the arrangement already there. It survives a
  -- save inside the cave, which the cartridge achieves by re-running this very
  -- script on load.
  ctx.save.gen4Turnback = { map = ow.map.id, dest = dest,
                            keep = (entry <= 3) and (entry + 1) or nil }
  Logger.debug("gen4 turnback cave: %s -- %d pillar(s) seen, %d room(s) "
               .. "visited, player at (%s,%s) came in by warp %d; the other "
               .. "exits now lead to %s",
               tostring(ow.map.id), pillarsSeen, roomsVisited,
               tostring(p and p.cellX), tostring(p and p.cellY), entry,
               tostring(dest))
end

-- `*destVar = LCRNG_Next() % upperBound`.
--
-- A bound of zero is a divide by zero on the cartridge and cannot be what any
-- script means, so it reads as one -- always zero -- rather than raising here.
function Commands.g4_get_random(ctx, destVar, bound)
  local top = math.floor(valueOf(ctx, bound) or 0)
  if top < 1 then top = 1 end
  setVar(ctx.save, destVar, math.random(0, top - 1))
end

-- A BOOLEAN, NOT THE BALANCE.  `currentMoney < value ? FALSE : TRUE`, and the
-- amount is a literal word in the script rather than a var.
function Commands.g4_check_money(ctx, destVar, amount)
  local have = tonumber(ctx.save and ctx.save.money) or 0
  setVar(ctx.save, destVar, have >= (tonumber(amount) or 0) and 1 or 0)
end

function Commands.g4_remove_money(ctx, amount)
  local save = ctx.save
  if not save then return end
  save.money = math.max(0, (tonumber(save.money) or 0) - (tonumber(amount) or 0))
end

-- A SPECIES KEY IS NOT A SPECIES NUMBER.
--
-- The party stores `mon.species` as the cache's own key -- "SPECIES_025" --
-- because that is what indexes `data.pokemon`; every script here compares a
-- NUMBER.  One place, so the two spellings cannot drift apart across the four
-- commands below.
local function speciesNumber(mon)
  local id = mon and mon.species
  if id == nil then return 0 end
  return tonumber(id) or tonumber(tostring(id):match("(%d+)%s*$")) or 0
end

-- `Party_GetPokemonBySlotIndex(*partySlot)` -- BOTH arguments are var ids and
-- the slot is the value held in the first.  Slots are zero-based on the
-- cartridge and one-based in the party table.
function Commands.g4_party_species(ctx, slotVar, destVar)
  local slot = math.floor(valueOf(ctx, slotVar) or 0)
  local mon = ctx.save and ctx.save.party and ctx.save.party[slot + 1]
  -- AN EGG IS SPECIES_NONE, not the species inside it.  The cartridge checks
  -- MON_DATA_IS_EGG first, and a script that asked "what is in slot 0" and got
  -- the unhatched answer would spoil its own surprise.
  if not mon or mon.isEgg then setVar(ctx.save, destVar, 0) return end
  setVar(ctx.save, destVar, speciesNumber(mon))
end

-- `species` comes through `ScriptContext_GetVar`, so it may itself be a var.
function Commands.g4_party_has_species(ctx, destVar, species)
  local want = math.floor(valueOf(ctx, species) or 0)
  local found = 0
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg and speciesNumber(mon) == want then found = 1 break end
  end
  setVar(ctx.save, destVar, found)
end

-- ---------------------------------------------------------------------------
-- the starter
-- ---------------------------------------------------------------------------
--
-- THE SCREEN WAS BUILT AND NOTHING EVER OPENED IT.  `src/ui/Gen4StarterSelect`
-- draws Rowan's briefcase from the cartridge's own `psel_all` model and its
-- 41-frame animation, and a search of the whole tree for its name found the
-- file and no callers.  The seam is one script command:
--
--     startchoosestarterscene     <- opens the app and PAUSES the script
--     savechosenstarter           <- writes the answer to VAR_PLAYER_STARTER
--     returntofield
--     getplayerstarterspecies 0x8000
--     givepokemon 0x8000, 5, 0, 0x800C
--
-- and the first, third and fourth of those were unlowered.  Without them the
-- briefcase never opens, the var stays zero and no Pokemon is handed over --
-- which is every player's first five minutes of the game.
--
-- VAR_PLAYER_STARTER is 0x4030, from the enum walk over
-- `generated/vars_flags.txt` that every Gen 4 var id in this port comes from
-- (the same walk puts VAR_OBJ_GFX_ID_0 at 0x4020, which the overworld already
-- relies on).  It is the cartridge's own storage, so the rival's and the
-- counterpart's starters are DERIVED from it rather than stored -- that is
-- `SystemVars_GetRivalStarter` and `SystemVars_GetPlayerCounterpartStarter`,
-- which are two `if` ladders and no state at all.
local VAR_PLAYER_STARTER = 0x4030

-- 387/390/393, read off `gen4_menus.starter.rows[i].species` -- the same three
-- the briefcase screen offers, ripped from the ROM, not typed in here.
local TURTWIG, CHIMCHAR, PIPLUP = 387, 390, 393

-- `SystemVars_GetRivalStarter`: the one that BEATS yours.
local function rivalStarter(player)
  if player == TURTWIG then return CHIMCHAR end
  if player == CHIMCHAR then return PIPLUP end
  return TURTWIG
end

-- `SystemVars_GetPlayerCounterpartStarter`: the one YOURS beats -- Dawn or
-- Lucas takes the leftover.
local function counterpartStarter(player)
  if player == TURTWIG then return PIPLUP end
  if player == CHIMCHAR then return TURTWIG end
  return CHIMCHAR
end

-- `SystemVars_GetPlayerStarter` -- kept in its own slot rather than derived
-- from the party, because the party can lose the starter and the question is
-- still answerable afterwards.
--
-- The VAR is the cartridge's storage and is read first; `save.gen4Starter` is
-- this port's older mirror and stays as a fallback so a save written before
-- the var was used still answers.
local function playerStarter(save)
  local fromVar = tonumber(getVar(save, VAR_PLAYER_STARTER)) or 0
  if fromVar ~= 0 then return fromVar end
  local id = save and (save.gen4Starter or (save.player and save.player.starter))
  return tonumber(id) or tonumber(tostring(id or ""):match("(%d+)%s*$")) or 0
end
Gen4Commands.playerStarter = playerStarter
Gen4Commands.rivalStarter = rivalStarter
Gen4Commands.counterpartStarter = counterpartStarter

function Commands.g4_catching_tutorial(ctx)
  local game = ctx.game
  local save = {}
  for k, v in pairs(game.save) do save[k] = v end
  local female = game.save.player and game.save.player.gender == "girl"
  save.player = { name = female and "Lucas" or "Dawn", gender = female and "boy" or "girl" }
  save.party = { require("src.pokemon.Pokemon").new(game.data,
    counterpartStarter(playerStarter(game.save)), 5) }
  save.pokedex = { seen = {}, owned = {} }
  save.inventory = { [4] = 20 }
  local demoGame = setmetatable({ save = save }, { __index = game })
  local battle = require("src.battle.BattleState").newWild(demoGame, 399, 2)
  battle:makeDudeDemo(save.player.name)
  battle.counterpartBack = true
  battle.demoBallCount = "x20"
  battle.onFinish = function()
    if ctx.runner then ctx.runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  if ctx.runner then ctx.runner:yield() end
end
Commands.meta.g4_catching_tutorial = { foreground = true, blocking = true }

-- HEARTGOLD / SOULSILVER `CasinoGame`: VOLTORB FLIP until the player quits
function Commands.g4_casino_game(ctx)
  local game = ctx.game
  local VF = require("src.ui.HgssVoltorbFlip")
  if not VF.available(game) then
    Logger.warn("gen4 casino: Voltorb Flip's art is not in this cache (re-import HeartGold / "
                .. "SoulSilver: extractVoltorbFlip) -- the machine does nothing")
    return
  end
  game.stack:push(VF.new(game, function()
    if ctx.runner then ctx.runner:resume() end
  end))
  if ctx.runner then ctx.runner:yield() end
end
Commands.meta.g4_casino_game = { foreground = true, blocking = true }

-- HEARTGOLD / SOULSILVER'S BUG-CATCHING CONTEST (src/world/HgssBugContest.lua;
-- pokeheartgold scrcmd_pokemon_misc.c 1455-1551)
local function BC() return require("src.world.HgssBugContest") end
local function setBuf(ctx, slot, text)
  if not ctx.game then return end
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[(tonumber(slot) or 0) + 1] = tostring(text or "")
end

-- 785 <action, weekday>: 0 starts the run, anything else ends it
function Commands.g4_bug_contest_action(ctx, action, weekday)
  if math.floor(valueOf(ctx, action) or 0) == 0 then
    BC().start(ctx.save, math.floor(valueOf(ctx, weekday) or 0))
  else
    BC().finish(ctx.save)
  end
end

-- 786 <place>: the entrant at that place -- the player's name, or the NPC's
-- name (msg_0246 78 + id) and class; the species and the score
function Commands.g4_bug_contest_winner(ctx, place)
  local s = BC().state(ctx.save)
  if not (s and s.ranking) then return end
  local p = math.floor(valueOf(ctx, place) or 0)
  local c = s.all[s.ranking[p + 1]]
  if not c then return end
  local text = ctx.game.data and ctx.game.data.text or {}
  if p == s.placement then
    setBuf(ctx, 0, ctx.save.player and ctx.save.player.name or "")
  else
    setBuf(ctx, 0, text[("TEXT_B0246_%05d"):format(78 + c.id)] or "")
    setBuf(ctx, 2, BC().CLASSES[c.id] or "")
  end
  Commands.g4_buffer(ctx, 1, "species", c.species)
  setBuf(ctx, 3, tostring(c.score))
end

-- 787 <varPlacement, varPrize, varSpecies>
function Commands.g4_bug_contest_judge(ctx, vPlace, vPrize, vSpecies)
  local place, prize, species = BC().judge(ctx.save)
  setVar(ctx.save, tonumber(vPlace), place or 3)
  setVar(ctx.save, tonumber(vPrize), prize or 295)
  setVar(ctx.save, tonumber(vSpecies), species or 0)
end

-- 788 <slot, varOut>: the caught Pokemon's name; 1 when it goes to the PC
function Commands.g4_bug_contest_mon_nick(ctx, slot, varOut)
  local s = BC().state(ctx.save)
  local mon = s and s.caught
  if not mon then setVar(ctx.save, tonumber(varOut), 0) return end
  local name = mon.nickname or mon.name
  if not name then
    local def = ctx.game.data and ctx.game.data.pokemon and ctx.game.data.pokemon[tonumber(mon.species)]
    name = def and def.name or ""
  end
  setBuf(ctx, slot, name)
  setVar(ctx.save, tonumber(varOut), (s.partyCount or 0) >= 6 and 1 or 0)
end

-- 789 <slot>: the minutes left, never below 1
function Commands.g4_bug_contest_time_left(ctx, slot)
  setBuf(ctx, valueOf(ctx, slot), tostring(BC().minutesLeft(ctx.save)))
end

-- 790 <id, varOut>: whether NPC entrant `id` is in this run
function Commands.g4_bug_contest_registered(ctx, id, varOut)
  local s = BC().state(ctx.save)
  local want = math.floor(valueOf(ctx, id) or -1)
  local yes = 0
  for _, c in ipairs(s and s.contestants or {}) do if c.id == want then yes = 1 end end
  setVar(ctx.save, tonumber(varOut), yes)
end

-- HEARTGOLD / SOULSILVER'S DEMONSTRATION, Route 29: BattleSetup_New_Tutorial
-- (battle_setup.c). The player's side is the friend -- the name is bank 445
-- entry `gender ^ 1`, "Lyra" for a boy -- with a level 5 Marill and twenty
-- Poke Balls, against a wild level 2 Rattata.
function Commands.g4_hgss_catching_tutorial(ctx)
  local game = ctx.game
  local save = {}
  for k, v in pairs(game.save) do save[k] = v end
  local girl = game.save.player and game.save.player.gender == "girl"
  local text = game.data and game.data.text or {}
  local name = text[("TEXT_B0445_%05d"):format(girl and 0 or 1)] or (girl and "Ethan" or "Lyra")
  save.player = { name = name, gender = girl and "boy" or "girl" }
  save.party = { require("src.pokemon.Pokemon").new(game.data, 183, 5) }
  save.pokedex = { seen = {}, owned = {} }
  save.inventory = { [4] = 20 }
  local demoGame = setmetatable({ save = save }, { __index = game })
  local battle = require("src.battle.BattleState").newWild(demoGame, 19, 2)
  battle:makeDudeDemo(save.player.name)
  battle.counterpartBack = true
  battle.demoBallCount = "x20"
  battle.onFinish = function()
    if ctx.runner then ctx.runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  if ctx.runner then ctx.runner:yield() end
end
Commands.meta.g4_hgss_catching_tutorial = { foreground = true, blocking = true }

-- BLACK / WHITE'S DEMONSTRATION, Route 1 (script 0x17D, its routine at
-- 0x0216E95C in Black): the player's side a level 7 Minccino (474 + 0x62)
-- knowing Pound and Growl, against a wild level 2 Patrat (474 + 0x1E)
-- knowing Tackle and Leer -- every number read off the routine. The name on
-- Juniper's side is RECONSTRUCTED: no name bank carries hers on its own.
function Commands.g4_bw_catching_tutorial(ctx)
  local game = ctx.game
  local Pokemon = require("src.pokemon.Pokemon")
  local function withMoves(mon, list)
    mon.moves = {}
    for _, id in ipairs(list) do
      local m = game.data.moves and game.data.moves[id]
      mon.moves[#mon.moves + 1] = { id = id, pp = m and m.pp or 0 }
    end
    return mon
  end
  local save = {}
  for k, v in pairs(game.save) do save[k] = v end
  save.player = { name = "Juniper", gender = "girl" }
  save.party = { withMoves(Pokemon.new(game.data, 572, 7), { 1, 45 }) }
  save.pokedex = { seen = {}, owned = {} }
  save.inventory = { [4] = 20 }
  local demoGame = setmetatable({ save = save }, { __index = game })
  local battle = require("src.battle.BattleState").newWild(demoGame, 504, 2)
  if battle.enemy and battle.enemy.mon then withMoves(battle.enemy.mon, { 33, 43 }) end
  battle:makeDudeDemo(save.player.name)
  -- Juniper's own back pic out of /a/0/7/3, not Gen 1's old man
  battle.demoBackPath = require("src.battle.CatchTutorialDemo").bwThrowerBack(game.data)
  battle.demoBallCount = "x20"
  battle.onFinish = function()
    if ctx.runner then ctx.runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  if ctx.runner then ctx.runner:yield() end
end
Commands.meta.g4_bw_catching_tutorial = { foreground = true, blocking = true }

-- HEARTGOLD / SOULSILVER: ScrCmd_NameRival -> CallTask_NamingScreen(
-- NAME_SCREEN_RIVAL, maxLen PLAYER_NAME_LENGTH = 7) and the result var is the
-- screen's `noInput`. The title is the naming bank's own (249 entry 3, "This
-- boy's name?"), and the name is kept where every reader of the rival looks.
function Commands.g4_name_rival(ctx, destVar)
  setVar(ctx.save, destVar, 1)
  if not (ctx.game and ctx.game.stack) then return end
  local T = require("src.import.Gen4Text")
  local title = ctx.game.data and ctx.game.data.text and ctx.game.data.text[T.label(249, 3)]
  title = type(title) == "string" and title:gsub("%s*{YESNO %d+}", "") or "This boy's name?"
  local runner = ctx.runner
  require("src.ui.Screens").push(ctx.game, "NamingScreen", {
    kind = "rival", maxLen = 7, title = title,
    onDone = function(typed)
      local name = tostring(typed or "")
      if name ~= "" and ctx.save then
        ctx.save.player = ctx.save.player or {}
        ctx.save.player.rival = name
        setVar(ctx.save, destVar, 0)
      end
      if runner then runner:resume() end
    end,
  })
  if runner then runner:yield() end
end
Commands.meta.g4_name_rival = { foreground = true, blocking = true }

-- THE POKEGEAR (scrcmd_c.c): RegisterPokegearCard <0..2> (anything else is
-- card 0), RegisterGearNumber <var> below NUM_PHONE_CONTACTS (75),
-- CheckRegisteredPhoneNumber <var> <dest>, and ScrCmd_804 the town map's
-- unlock level. Kept in `save.hgssPokegear`; nothing draws it yet.
local function pokegear(save)
  if not save then return nil end
  save.hgssPokegear = save.hgssPokegear or { cards = {}, numbers = {}, mapLevel = 0 }
  -- the Pokegear screen's skin choice can create the record first ({ skin })
  local pg = save.hgssPokegear
  pg.cards, pg.numbers, pg.mapLevel = pg.cards or {}, pg.numbers or {}, pg.mapLevel or 0
  return save.hgssPokegear
end
function Commands.g4_pokegear_card(ctx, card)
  local pg = pokegear(ctx.save); if not pg then return end
  local c = math.floor(tonumber(card) or 0)
  if c ~= 1 and c ~= 2 then c = 0 end
  pg.cards[c] = true
end
function Commands.g4_pokegear_number(ctx, number)
  local pg = pokegear(ctx.save); if not pg then return end
  local n = math.floor(valueOf(ctx, number) or 0) % 256
  if n < 75 then pg.numbers[n] = true end
end
function Commands.g4_pokegear_has_number(ctx, number, destVar)
  local pg = pokegear(ctx.save)
  local n = math.floor(valueOf(ctx, number) or 0) % 256
  local has = pg and n < 75 and pg.numbers[n] and 1 or 0
  setVar(ctx.save, destVar, has)
  setResult(ctx, has)
end
function Commands.g4_pokegear_map_level(ctx, level)
  local pg = pokegear(ctx.save); if not pg then return end
  pg.mapLevel = math.floor(tonumber(level) or 0)
end

-- MOM'S SAVINGS: CheckBankBalance <dest> <u32 amount> -> balance >= amount;
-- BankOrWalletIsFull <0 bank / 1 wallet> <dest> -> at MAX_MONEY (999,999).
-- BankTransaction <0 deposit / 1 withdraw> <dest> opens the amount dial and
-- answers 0 done / 1 cancelled (src/world/HgssMomSavings.lua M.transaction).
Gen4Commands.MAX_MONEY = 999999
function Commands.g4_bank_balance_at_least(ctx, destVar, amount)
  local balance = tonumber(ctx.save and ctx.save.hgssMomSavings) or 0
  local yes = balance >= (tonumber(amount) or 0) and 1 or 0
  setVar(ctx.save, destVar, yes)
  setResult(ctx, yes)
end
function Commands.g4_bank_or_wallet_full(ctx, which, destVar)
  local amount = (tonumber(which) == 0) and (tonumber(ctx.save and ctx.save.hgssMomSavings) or 0)
                 or (tonumber(ctx.save and ctx.save.money) or 0)
  local full = amount >= Gen4Commands.MAX_MONEY and 1 or 0
  setVar(ctx.save, destVar, full)
  setResult(ctx, full)
end
-- ScrCmd_GetPersonCoords: the object's X and Z -- MapObject_GetXCoord, the
-- same absolute matrix coordinates GetPlayerCoords answers in. An object
-- not on the map answers 255, 255, as the cartridge does.
function Commands.g4_object_coords(ctx, id, xVar, zVar)
  local who = objectById(ctx, math.floor(valueOf(ctx, id) or 0))
  if not who then
    setVar(ctx.save, xVar, 255)
    setVar(ctx.save, zVar, 255)
    return
  end
  local x, z = toMatrix(ctx, who.cellX, who.cellY)
  setVar(ctx.save, xVar, x)
  setVar(ctx.save, zVar, z)
end

-- THE PHOTO ALBUM (HGSS): Cameron's photos in `save.hgssPhotoAlbum`, each
-- the photo number and the map it was taken on; the album screen is not built
Gen4Commands.PHOTO_ALBUM_MAX = 36
local function photoAlbum(save)
  if not save then return nil end
  save.hgssPhotoAlbum = save.hgssPhotoAlbum or {}
  return save.hgssPhotoAlbum
end
function Commands.g4_take_photo(ctx, number)
  local album = photoAlbum(ctx.save)
  if not album or #album >= Gen4Commands.PHOTO_ALBUM_MAX then return end
  local ow = ctx.overworld
  album[#album + 1] = { photo = math.floor(tonumber(number) or 0),
                        map = ow and ow.map and ow.map.id or nil }
end
function Commands.g4_count_photos(ctx, destVar)
  local album = photoAlbum(ctx.save)
  setVar(ctx.save, destVar, album and #album or 0)
end
function Commands.g4_photo_album_full(ctx, destVar)
  local album = photoAlbum(ctx.save)
  local full = (album and #album >= Gen4Commands.PHOTO_ALBUM_MAX) and 1 or 0
  setVar(ctx.save, destVar, full)
  setResult(ctx, full)
end

-- THE VIOLET GYM LIFT (field/gymmick/violet.c, gymmick_init.c). Build model
-- 111 stands at (0xF8, y, 0x148) -- tile (15.5, 20.5) -- over the 3 x 3 tiles
-- (14..16, 19..21) whose height the dynamic terrain manager pins to the
-- platform's: 32 down, 496 up, 16 a frame between. The state is the save's
-- gymmick (`save.hgssGymmick.violetLift`, 0 down / 1 up); InitVioletGym puts
-- it down on every entry, GymmickInit_Violet then places it.
Gen4Commands.VIOLET_LIFT = { model = 111, x = 0xF8, z = 0x148, down = 32, up = 496, speed = 16,
                             tiles = { x = 14, z = 19, w = 3, h = 3 } }
local function violetLiftAt(ctx, y)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  if not def then return end
  local L = Gen4Commands.VIOLET_LIFT
  -- a fresh list each time, so Gen4Ground re-reads it
  def.gen4RuntimeProps = { { model = L.model, x = L.x, y = y, z = L.z } }
  def.gen4HeightEdits = def.gen4HeightEdits or {}
  for dx = 0, L.tiles.w - 1 do
    for dz = 0, L.tiles.h - 1 do
      def.gen4HeightEdits[(L.tiles.x + dx) .. "," .. (L.tiles.z + dz)] = y
    end
  end
end
function Commands.g4_violet_gym_init(ctx)
  if not ctx.save then return end
  ctx.save.hgssGymmick = { kind = "violet", violetLift = 0 }
  violetLiftAt(ctx, Gen4Commands.VIOLET_LIFT.down)
  Logger.info("gen4 violet gym: lift placed down (model %d at y %d)", Gen4Commands.VIOLET_LIFT.model,
              Gen4Commands.VIOLET_LIFT.down)
end
function Commands.g4_violet_gym_elevator(ctx)
  local L = Gen4Commands.VIOLET_LIFT
  local g = ctx.save and ctx.save.hgssGymmick
  if not (g and g.kind == "violet") then
    Commands.g4_violet_gym_init(ctx)
    g = ctx.save and ctx.save.hgssGymmick
    if not g then return end
  end
  local going = (g.violetLift == 0) and 1 or 0
  local y = (g.violetLift == 0) and L.down or L.up
  local target = (going == 1) and L.up or L.down
  local step = (going == 1) and L.speed or -L.speed
  g.violetLift = going
  local runner = ctx.runner
  if not runner then violetLiftAt(ctx, target) return end
  runner.waitingCheck = function()
    y = y + step
    if (step > 0 and y >= target) or (step < 0 and y <= target) then y = target end
    violetLiftAt(ctx, y)
    return y == target
  end
  runner:yield()
end
Commands.meta.g4_violet_gym_elevator = { blocking = true }

-- BUGSY'S GYM (field/gymmick/azalea.c): four Spinarak carts on twelve
-- stations, two switches choosing their routes. The tables and the cart's
-- motion are src/world/HgssAzaleaGym; the state is the save's gymmick, as
-- the cartridge keeps it (`spiders`, `switches`).
local function azaleaState(ctx)
  local Azalea = require("src.world.HgssAzaleaGym")
  local g = ctx.save and ctx.save.hgssGymmick
  if not (g and g.kind == "azalea") then
    g = Azalea.initialState()
    if ctx.save then ctx.save.hgssGymmick = g end
  end
  return g, Azalea
end
local function azaleaPlace(ctx, override)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  if not def then return end
  local g, Azalea = azaleaState(ctx)
  def.gen4RuntimeProps = Azalea.props(g, override)
end
-- InitAzaleaGym (the gym's init script) resets the save state; the carts
-- are then placed where it says, as GymmickInit_Azalea does on every load
function Commands.g4_azalea_gym_init(ctx)
  if not ctx.save then return end
  ctx.save.hgssGymmick = require("src.world.HgssAzaleaGym").initialState()
  azaleaPlace(ctx)
  Logger.info("gen4 azalea gym: carts at stations 0, 1, 2, 7")
end
function Commands.g4_azalea_gym_switch(ctx, which)
  local g, Azalea = azaleaState(ctx)
  Azalea.flip(g, math.floor(valueOf(ctx, which) or 0))
  azaleaPlace(ctx)
  Logger.info("gen4 azalea gym: switch %s -> state %d", tostring(which), g.switches)
end
-- BeginAzaleaGymSpinarakRide: step onto the cart (up, or down for the
-- stations whose route runs backwards), 4 frames, the ride, then the player
-- is put on the last node's tile, 16 frames (the cartridge's shake and
-- wait), and steps off the same way.
local AZALEA_STEP_FRAMES = 8
function Commands.g4_azalea_gym_spinarak(ctx, station)
  local g, Azalea = azaleaState(ctx)
  local n = math.floor(valueOf(ctx, station) or 0)
  local ride = Azalea.ride(g, n)
  local ow = ctx.overworld
  local p = ow and ow.player
  if not ride then
    Logger.warn("gen4 azalea gym: no cart at station %d (switches %d)", n, g.switches)
    return
  end
  local dz = (ride.stepDir == "down") and 1 or -1
  local function finish()
    g.spiders[ride.spider] = ride.destination
    azaleaPlace(ctx)
  end
  if not (p and ctx.runner) then
    finish()
    return
  end
  local phase, frame = "on", 0
  local startPy = p.py
  p.facing = ride.stepDir
  ctx.runner.waitingCheck = function()
    frame = frame + 1
    if phase == "on" or phase == "off" then
      p.py = startPy + dz * 16 * math.min(frame, AZALEA_STEP_FRAMES) / AZALEA_STEP_FRAMES
      p.animClock = (p.animClock or 0) + 1
      if frame >= AZALEA_STEP_FRAMES then
        p.cellY = p.cellY + dz
        p.px, p.py = p.cellX * 16, p.cellY * 16
        if phase == "off" then return true end
        phase, frame = "wait", 0
      end
    elseif phase == "wait" then
      if frame > 4 then phase, frame = "ride", 0 end
    elseif phase == "ride" then
      local done = Azalea.step(ride)
      azaleaPlace(ctx, { index = ride.spider, x = ride.x, z = ride.z })
      p.px, p.py = ride.x, ride.z + ride.playerZOffset * 16
      if done then
        local last = ride.nodes[#ride.nodes]
        p.cellX, p.cellY = last.x, last.z + ride.playerZOffset
        p.px, p.py = p.cellX * 16, p.cellY * 16
        finish()
        phase, frame = "land", 0
      end
    elseif phase == "land" then
      if frame >= 16 then phase, frame, startPy = "off", 0, p.py end
    end
    return false
  end
  ctx.runner:yield()
end
Commands.meta.g4_azalea_gym_spinarak = { blocking = true }

-- HGSS's battle outcome as the script reads it (constants/battle.h):
-- NONE 0, WIN 1, LOSE 2, DRAW 3, MON_CAUGHT 4, PLAYER_FLED 5
local HGSS_OUTCOME = { win = 1, lose = 2, draw = 3, caught = 4, run = 5, fled = 5 }
function Commands.g4_static_outcome(ctx, destVar)
  setVar(ctx.save, destVar, HGSS_OUTCOME[ctx.lastBattleResult or ""] or 0)
end
-- StaticWildWonOrCaughtCheck: IsBattleResultStaticWildWin, which -- despite
-- the name -- answers TRUE unless the Pokemon was beaten or caught
-- ...`<dest>, 1` reads VAR_BATTLE_RESULT (0x4013, BATTLE_OUTCOME_*) instead of
-- the script's own win flag: a map's ON_LOAD asks that way, from a context
-- that started no battle (IsBattleResultStaticWildWin: WIN 1 / CAUGHT 4 -> 0)
function Commands.g4_static_not_won(ctx, destVar, fromVar)
  if tonumber(fromVar) == 1 then
    local v = getVar(ctx.save, 0x4013)
    setVar(ctx.save, destVar, (v == 1 or v == 4) and 0 or 1)
    return
  end
  local r = ctx.lastBattleResult
  setVar(ctx.save, destVar, (r == "win" or r == "caught") and 0 or 1)
end
-- GetItemQuantity <item> <dest>: Bag_GetQuantity
function Commands.g4_item_quantity(ctx, item, destVar)
  local id = itemKey(ctx.game and ctx.game.data, valueOf(ctx, item))
  setVar(ctx.save, destVar, tonumber(ctx.save and ctx.save.inventory and ctx.save.inventory[id]) or 0)
end
-- AddMoney <u32 literal>: PlayerProfile_AddMoney, capped at 999,999
function Commands.g4_add_money(ctx, amount)
  local save = ctx.save
  if not save then return end
  save.money = math.min(999999, (tonumber(save.money) or 0) + (tonumber(amount) or 0))
end
-- ScrCmd_582 <map> <x> <y>: the special spawn warp (where Dig / an Escape
-- Rope out of the Goldenrod Underground lands), facing south
function Commands.g4_special_spawn(ctx, map, x, y)
  if not ctx.save then return end
  ctx.save.gen4SpecialSpawn = { header = valueOf(ctx, map), x = valueOf(ctx, x), y = valueOf(ctx, y),
                                facing = "down" }
end

-- `ScreenShake ampX, ampY, count, period` (HGSS; ov02_02246548 / _0224663C):
-- the camera's look-at target moves by amp * sin(frame * 360 / period) for
-- `period` frames, `count` times, then is put back. The script waits.
function Commands.g4_screen_shake(ctx, ampX, ampY, count, period)
  local ow = ctx.overworld
  local ax, ay = valueOf(ctx, ampX) or 0, valueOf(ctx, ampY) or 0
  local n, p = math.max(1, valueOf(ctx, count) or 1), math.max(1, valueOf(ctx, period) or 1)
  if ax >= 0x8000 then ax = ax - 0x10000 end
  if ay >= 0x8000 then ay = ay - 0x10000 end
  local runner = ctx.runner
  if not (ow and runner) then return end
  local frame = 0
  runner.waitingCheck = function()
    frame = frame + 1
    if frame >= n * p then
      ow.gen4ShakeOffset = nil
      return true
    end
    local s = math.sin(math.rad((frame % p) * 360 / p))
    ow.gen4ShakeOffset = { ax * s, ay * s }
    return false
  end
  runner:yield()
end
Commands.meta.g4_screen_shake = { blocking = true }

-- `ScrCmd_523 obj, count, step, ampX, ampZ` (HGSS; sub_0205BED8 / _0205BE28):
-- the object's drawn position is offset by (ampX, ampZ) * sin(angle), the
-- angle stepping `step` degrees a frame, `count` turns of 360, then put back.
-- The script waits for it.
function Commands.g4_object_shake(ctx, obj, count, step, ampX, ampZ)
  local npc = objectById(ctx, obj)
  local runner = ctx.runner
  if not (npc and runner) then return end
  local n = math.max(1, math.floor(valueOf(ctx, count) or 1))
  local st = math.max(1, math.floor(valueOf(ctx, step) or 90))
  local ax, az = valueOf(ctx, ampX) or 0, valueOf(ctx, ampZ) or 0
  local angle = 0
  local homeX, homeY = npc.cellX * 16, npc.cellY * 16
  runner.waitingCheck = function()
    local s = math.sin(math.rad(angle))
    npc.px, npc.py = homeX + ax * s, homeY + az * s
    angle = angle + st
    if angle >= 360 then
      angle = 0
      n = n - 1
    end
    if n <= 0 then
      npc.px, npc.py = homeX, homeY
      return true
    end
    return false
  end
  runner:yield()
end
Commands.meta.g4_object_shake = { blocking = true }

-- LOAN POKEMON (HGSS; npc_trade.c): Cianwood's Shuckie (trade 6) and Kenya
-- the Spearow (trade 7, with the Route 35 man's mail), handed over out of the
-- /a/1/1/2 trade table at a level the script gives -- the same record and
-- the same fields `g4_trade_start` builds a traded Pokemon from.
Gen4Commands.KENYA_TRADE = 7
function Commands.g4_give_loan_mon(ctx, trade, level, mapno)
  local id = math.floor(tonumber(trade) or -1)
  local data = ctx.game and ctx.game.data
  local list = data and data.constants and data.constants.gen4Trades
  local row = type(list) == "table" and list[id + 1] or nil
  local party = ctx.save and ctx.save.party
  if not (row and row.species and data and party) then
    Logger.warn("gen4 loan: no trade record %s to lend from", tostring(trade))
    return
  end
  local ok, mon = pcall(function()
    return require("src.pokemon.Pokemon").new(data, row.species, math.floor(tonumber(level) or 20))
  end)
  if not (ok and type(mon) == "table") then return end
  mon.nickname, mon.ot, mon.otId, mon.otGender = row.nickname, row.otName, row.otId, row.otGender
  mon.traded = true
  -- npc_trade.c: the record's language (src/pokemon/Gen45Language.lua)
  if tonumber(row.language) then mon.language = tonumber(row.language) end
  mon.loanTrade = id
  mon.metLocation = tonumber(mapno)
  if row.item and row.item ~= 0 then mon.item = row.item end
  if id == Gen4Commands.KENYA_TRADE then mon.kenyaMail = true end
  if type(row.ivs) == "table" and type(mon.ivs) == "table" then
    local Stats = require("src.pokemon.Stats")
    for i, key in ipairs(Stats.ORDER_GEN3) do
      if row.ivs[i] then mon.ivs[key] = row.ivs[i] end
    end
    local okStats, stats = pcall(Stats.calc, data.pokemon[row.species], mon.level, mon.ivs, mon.evs, mon.nature)
    if okStats and type(stats) == "table" then mon.stats, mon.hp = stats, stats.hp end
  end
  party[#party + 1] = mon
  local save = ctx.save
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.owned = save.pokedex.owned or {}
  save.pokedex.seen[mon.species], save.pokedex.owned[mon.species] = true, true
end
-- NPCTrade_CanGiveUpLoanMon: 0 yes; 1 not the loaned one; 3 has a ball
-- capsule (none here); 4 it would leave fewer than two able Pokemon; 2 it
-- holds an item
function Commands.g4_check_return_loan_mon(ctx, trade, slot, destVar)
  local party = (ctx.save and ctx.save.party) or {}
  local mon = party[(valueOf(ctx, slot) or 0) + 1]
  local id = math.floor(tonumber(trade) or -1)
  local answer
  if not (mon and mon.loanTrade == id) then
    answer = 1
  else
    local able = 0
    for _, m in ipairs(party) do
      if not m.isEgg and (tonumber(m.hp) or 0) > 0 then able = able + 1 end
    end
    if able < 2 then answer = 4
    elseif mon.item and mon.item ~= 0 then answer = 2
    else answer = 0 end
  end
  setVar(ctx.save, destVar, answer)
end
function Commands.g4_return_loan_mon(ctx, slot)
  local party = ctx.save and ctx.save.party
  local i = (valueOf(ctx, slot) or 0) + 1
  if party and party[i] then table.remove(party, i) end
end
-- KenyaCheckPartyOrMailbox: is Kenya's mail still with you (on a party
-- Pokemon -- the mailbox is not built)
function Commands.g4_kenya_mail(ctx, destVar)
  local found = false
  for _, m in ipairs((ctx.save and ctx.save.party) or {}) do
    if m.kenyaMail and m.item and m.item ~= 0 then found = true end
  end
  setVar(ctx.save, destVar, found and 1 or 0)
end

-- ScrCmd_775 <objA> <objB> (HGSS; ov02_022469B4): Lance and his Dragonite
-- fly off the Lake of Rage, and the script hides both straight after. The
-- cartridge's flight path is not transcribed: both rise off the top of the
-- screen, 6 units a frame for 40 frames, and the script waits for it.
function Commands.g4_fly_off_pair(ctx, objA, objB)
  local a, b = objectById(ctx, objA), objectById(ctx, objB)
  local runner = ctx.runner
  if not runner or not (a or b) then return end
  local frames = 0
  runner.waitingCheck = function()
    frames = frames + 1
    for _, o in ipairs({ a, b }) do if o then o.py = o.py - 6 end end
    return frames >= 40
  end
  runner:yield()
end
Commands.meta.g4_fly_off_pair = { blocking = true }

-- LT. SURGE'S GYM (HGSS; gymmick_init.c, field/gymmick/vermilion.c): fifteen
-- cans in a 5 x 3 grid; the first switch is a random can, the second a
-- random neighbour of it. With the Thunder Badge both gates stand open.
-- VermilionGymCanCheck answers 1 / 0 for the first switch, then 2 / 3 for
-- the second once gate 1 is open, and 4 when both are.
Gen4Commands.VERMILION_CAN_NEIGHBOURS = {
  [0] = { 1, 5 }, { 0, 2, 6 }, { 1, 3, 7 }, { 2, 4, 8 }, { 3, 9 },
  { 0, 6, 10 }, { 1, 5, 7, 11 }, { 2, 6, 8, 12 }, { 3, 7, 9, 13 }, { 4, 8, 14 },
  { 5, 11 }, { 6, 10, 12 }, { 7, 11, 13 }, { 8, 12, 14 }, { 9, 13 },
}
local function vermilionState(ctx)
  local g = ctx.save and ctx.save.hgssGymmick
  if not (g and g.kind == "vermilion") then
    g = { kind = "vermilion", switches = { 0, 0 }, gates = { false, false } }
    if ctx.save then ctx.save.hgssGymmick = g end
  end
  return g
end
local function placeVermilionSwitches(g)
  g.switches[1] = math.random(0, 14)
  local n = Gen4Commands.VERMILION_CAN_NEIGHBOURS[g.switches[1]]
  g.switches[2] = n[math.random(1, #n)]
end
function Commands.g4_vermilion_gym_init(ctx)
  if not ctx.save then return end
  local g = { kind = "vermilion", switches = { 0, 0 }, gates = { false, false } }
  ctx.save.hgssGymmick = g
  Commands.g4_check_badge(ctx, 10)        -- BADGE_THUNDER
  if ctx.g4Compare == 1 then
    g.gates = { true, true }
  else
    placeVermilionSwitches(g)
  end
end
function Commands.g4_vermilion_resample(ctx) placeVermilionSwitches(vermilionState(ctx)) end
function Commands.g4_vermilion_can_check(ctx, can, destVar)
  local g = vermilionState(ctx)
  local id = math.floor(tonumber(can) or -1)
  local answer
  if g.gates[1] and g.gates[2] then answer = 4
  elseif g.gates[1] then answer = (id == g.switches[2]) and 2 or 3
  else answer = (id == g.switches[1]) and 1 or 0 end
  setVar(ctx.save, destVar, answer)
end
-- VermilionGymLockAction <lock> <relock>: the gate's three stops (objects
-- 3, 4, 5 for gate 0; 0, 1, 2 for gate 1) run two tiles apart -- the first
-- two left, the third right -- or back together on a relock
function Commands.g4_vermilion_lock_action(ctx, lock, relock)
  local g = vermilionState(ctx)
  local n = math.floor(tonumber(lock) or 0)
  local back = (tonumber(relock) or 0) ~= 0
  g.gates[n + 1] = not back
  local ow = ctx.overworld
  if not (ow and ow.scriptMove) then return end
  local ids = n == 0 and { 3, 4, 5 } or { 0, 1, 2 }
  local moving = 0
  for i, id in ipairs(ids) do
    local e = objectById(ctx, id)
    if e then
      local dir = (i < 3) ~= back and "left" or "right"
      moving = moving + 1
      ow:scriptMove(e, dir, 2, function() moving = moving - 1 end, true, 0.5)
    end
  end
  local runner = ctx.runner
  if runner and moving > 0 then
    runner.waitingCheck = function() return moving <= 0 end
    runner:yield()
  end
end
Commands.meta.g4_vermilion_lock_action = { blocking = true }
-- FuchsiaGymInit / ViridianGymInit set the gymmick and nothing else: Janine's
-- invisible walls are the map's own collision (the gymmick only flashes one
-- when bumped) and Viridian's spin tiles are forced movement
function Commands.g4_kanto_gym_init(ctx, kind)
  if ctx.save then ctx.save.hgssGymmick = { kind = kind } end
end
-- ScrCmd_452 <species> <gender> (DrawPokemonPicFromSpecies at tile (10, 5),
-- an 80 x 80 front picture in a framed window) and ScrCmd_453 (the window
-- goes): Latias / Latios on Vermilion's pier. The dex marks it seen. The
-- script runs on under it, so the window is Gen 2's passive pokepic box
-- (src/ui/PicBox) at the DS's place and size; the script's own message and
-- button wait follow it.
function Commands.g4_show_mon_pic(ctx, species, gender)
  local id = math.floor(valueOf(ctx, species) or 0)
  local save = ctx.save
  if not save or id == 0 then return end
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.seen[id] = true
  local ow, game = ctx.overworld, ctx.game
  if not (ow and game) then return end
  local path = require("src.pokemon.Sprites").path(game.data, id, "front", { kind = "pokepic" })
  if not path then return end
  if ow.pokepicBox then ow.pokepicBox:remove() end
  local box = require("src.ui.PicBox").new(game, {
    path = path, trueColor = true, passive = true, overworld = ow,
    -- the frame at DS tile (9, 4); PicBox's grid is the GB screen centred
    -- in the DS one (6 tiles in, 3 down)
    box = { x = 3, y = 1, w = 12, h = 12 }, picTiles = 10,
  })
  ow.pokepicBox = box
  game.stack:push(box)
end
function Commands.g4_close_mon_pic(ctx)
  local ow = ctx.overworld
  local box = ow and ow.pokepicBox
  if box then box:remove() end
end

-- CLAIR'S GYM (HGSS; field/gymmick/blackthorn.c): InitBlackthornGym on every
-- entry, then the platforms run from the map def's hooks
-- (src/world/HgssBlackthornGym)
function Commands.g4_blackthorn_gym_init(ctx)
  local ow = ctx.overworld
  if ow and ctx.save then require("src.world.HgssBlackthornGym").attach(ow, ctx.save) end
end

-- CHUCK'S GYM (HGSS; field/gymmick/cianwood.c): InitCianwoodGym leaves the
-- winch unturned; CianwoodGymTurnWinch turns it once (answering 1, else 0),
-- saved, while the camera pans 24 frames to (50, 58), the waterfall's props
-- (173..175) play their stopping animation, and it pans 24 back. The prop
-- animations are not played here; the pans and a stand-in for the
-- animation's length are waited out.
function Commands.g4_cianwood_gym_init(ctx)
  if ctx.save then ctx.save.hgssGymmick = { kind = "cianwood", winch = false } end
end
function Commands.g4_cianwood_turn_winch(ctx, destVar)
  local g = ctx.save and ctx.save.hgssGymmick
  local turned = g and g.kind == "cianwood" and not g.winch
  if turned then g.winch = true end
  setVar(ctx.save, destVar, turned and 1 or 0)
  local runner = ctx.runner
  if not (turned and runner) then return end
  local frames = 0
  runner.waitingCheck = function() frames = frames + 1; return frames >= 24 + 30 + 24 end
  runner:yield()
end
Commands.meta.g4_cianwood_turn_winch = { blocking = true }

-- MORTY'S GYM (HGSS) -- src/world/HgssEcruteakGym: the fog, and a light on
-- each medium that follows her and goes out when she is beaten.
local function ecruteakFollow(ow)
  local Game = require("src.core.Game")
  local save = Game and Game.save
  local g = save and save.hgssGymmick
  local def = ow.map and ow.map.def
  if not (g and g.kind == "ecruteak" and def) then return end
  local ground = ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  local heightAt = ground and ground.groundY and function(x, z) return ground:groundY(x, z) end
  local props = require("src.world.HgssEcruteakGym").props(g, ow.npcs, ow.g4CandleDying, heightAt)
  local parts = {}
  for i, p in ipairs(props) do parts[i] = ("%d,%d,%d,%s"):format(p.x, p.z, p.y, tostring(p.scale)) end
  local key = table.concat(parts, ";")
  if key ~= ow.g4CandleKey then
    ow.g4CandleKey = key
    def.gen4RuntimeProps = props
  end
end
function Commands.g4_ecruteak_gym_init(ctx)
  local E = require("src.world.HgssEcruteakGym")
  if ctx.save then ctx.save.hgssGymmick = E.initialState() end
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  if not def then return end
  def.gen4Fog = E.FOG
  def.gen4PropFollow = ecruteakFollow
  ow.g4CandleKey, ow.g4CandleDying = nil, nil
  ecruteakFollow(ow)
  Logger.info("gen4 ecruteak gym: fogged, four candles lit")
end
-- ExtinguishEcruteakGymCandle <talked>: 1 the trainer the player spoke to, 0
-- the one who saw them -- both are the script's own object here
function Commands.g4_ecruteak_candle_out(ctx)
  local E = require("src.world.HgssEcruteakGym")
  local g = ctx.save and ctx.save.hgssGymmick
  local ow, npc = ctx.overworld, ctx.npc
  -- every trainer's shared script asks this after its battle; outside
  -- Morty's gym ScrCmd_ExtinguishEcruteakGymCandle (scrcmd_c.c) answers on
  -- the gymmick type alone and does nothing (Clair's five warned each time)
  if not (g and g.kind == "ecruteak") then return end
  if not (ow and npc and npc.def) then
    Logger.warn("gen4 ecruteak gym: no candle to put out (gymmick %s, trainer object %s)",
                tostring(g and g.kind), tostring(npc and npc.def and npc.def.localId))
    return
  end
  local i = E.candleOf(npc.def.localId)
  if not i or g.candles[i] then return end
  local function out()
    g.candles[i] = true
    ow.g4CandleDying = nil
    local data = ctx.game and ctx.game.data
    local sprite, name = ow.gen4SpriteFor and ow.gen4SpriteFor(data, E.OUT_SPRITE)
    if sprite and npc.refreshSprite then
      local copy = {}
      for k, v in pairs(npc.def) do copy[k] = v end
      copy.sprite, copy.spriteName, copy.graphicsId = sprite, name, E.OUT_SPRITE
      npc.def = copy
      pcall(npc.refreshSprite, npc, data)
    end
    ecruteakFollow(ow)
  end
  local runner = ctx.runner
  if not runner then out() return end
  local frame, factor = 0, 1
  runner.waitingCheck = function()
    frame = frame + 1
    if frame <= 30 then return false end
    if factor >= 4 then out() return true end
    factor = factor + 1
    ow.g4CandleDying = { index = i, factor = factor }
    ecruteakFollow(ow)
    return false
  end
  runner:yield()
end
Commands.meta.g4_ecruteak_candle_out = { blocking = true }

-- WHAT A CONTINUE BUILDS INSTEAD OF RUNNING ON_TRANSITION.
--
-- FieldTask_ContinueGame_Normal (pokeheartgold field_warp_tasks.c) and
-- FieldTask_LoadSavedGameMap (pokeplatinum field_map_change.c) skip the walk
-- in's sub_02053038 / FieldMapChange_UpdateGameData -- so no InitXGym, no
-- Save_Gymmick_Clear, no PersistedMapFeatures_Init -- and the field's own
-- start then builds the room from what the save kept: Gymmick_Init
-- (field/fieldmap.c) reads the HGSS Gymmick, DynamicMapFeatures_Init the
-- Platinum feature slot. This is that read, called by setMap on a continue
-- once the map's objects are up. Answers what it built (for the log).
function Gen4Commands.restoreOnContinue(ctx)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  local save = ctx.save
  if not (def and save) then return nil end
  local g = save.hgssGymmick
  if g and g.kind == "violet" then
    -- GymmickInit_Violet: the lift where the save says
    local L = Gen4Commands.VIOLET_LIFT
    violetLiftAt(ctx, g.violetLift == 1 and L.up or L.down)
    return "violet lift " .. tostring(g.violetLift)
  elseif g and g.kind == "azalea" then
    azaleaPlace(ctx)
    return "azalea carts"
  elseif g and g.kind == "ecruteak" then
    -- GymmickInit_Ecruteak: the fog, a light on each medium whose candle the
    -- save has lit; a medium whose candle went out keeps SPRITE_ITAKO_, which
    -- the cartridge's saved object carries (spriteId) and this port's does not
    local E = require("src.world.HgssEcruteakGym")
    def.gen4Fog = E.FOG
    def.gen4PropFollow = ecruteakFollow
    ow.g4CandleKey, ow.g4CandleDying = nil, nil
    local data = ctx.game and ctx.game.data
    for _, npc in ipairs(ow.npcs or {}) do
      local i = npc.def and E.candleOf(npc.def.localId)
      if i and g.candles and g.candles[i] and ow.gen4SpriteFor then
        local sprite, name = ow.gen4SpriteFor(data, E.OUT_SPRITE)
        if sprite and npc.refreshSprite and npc.def.graphicsId ~= E.OUT_SPRITE then
          local copy = {}
          for k, v in pairs(npc.def) do copy[k] = v end
          copy.sprite, copy.spriteName, copy.graphicsId = sprite, name, E.OUT_SPRITE
          npc.def = copy
          pcall(npc.refreshSprite, npc, data)
        end
      end
    end
    ecruteakFollow(ow)
    return "ecruteak fog and candles"
  elseif g and g.kind == "blackthorn" then
    -- the platforms where the save left them (not InitBlackthornGym's)
    require("src.world.HgssBlackthornGym").attach(ow, save, true)
    return "blackthorn platforms"
  elseif g and g.kind then
    -- Cianwood's winch, Vermilion's cans, Fuchsia, Viridian: state only
    return g.kind .. " (state only)"
  end
  -- Veilstone Gym's bags and stacks where the save left them
  local Veilstone = require("src.world.Gen4VeilstoneGym")
  if Veilstone.isGym(def) and Veilstone.apply(ow, save) then return "veilstone bags and stacks" end
  -- Hearthome Gym's trainer room as the save dealt it (the doors, the clue)
  local Hearthome = require("src.world.Gen4HearthomeGym")
  local DMF = require("src.world.Gen4DynamicMapFeatures")
  if Hearthome.room(def) and save.gen4MapFeature and DMF.buffer(save, DMF.HEARTHOME_GYM) then
    local door = Hearthome.apply(ow, save)
    if door then return "hearthome room, door " .. tostring(door) end
  end
  -- Eterna's clock, Canalave's platforms, Sunyshore's gears: each gym's
  -- DynamicMapFeaturesInit from the slot (src/world/Gen4EternaGym.lua,
  -- Gen4CanalaveGym.lua, Gen4SunyshoreGym.lua)
  if save.gen4MapFeature then
    local Eterna = require("src.world.Gen4EternaGym")
    if Eterna.isGym(def) and Eterna.apply(ow, save) then return "eterna clock" end
    local Canalave = require("src.world.Gen4CanalaveGym")
    if Canalave.isGym(def) and Canalave.apply(ow, save) then return "canalave platforms" end
    local Sunyshore = require("src.world.Gen4SunyshoreGym")
    if Sunyshore.roomOf(def) and Sunyshore.apply(ow, save) then return "sunyshore gears" end
  end
  -- Pastoria Gym's water floor at the save's level
  -- (PastoriaGym_DynamicMapFeaturesInit; src/world/Gen4PastoriaGym.lua)
  local Pastoria = require("src.world.Gen4PastoriaGym")
  if Pastoria.isGym(def) and Pastoria.apply(def, save) then
    return "pastoria water at " .. tostring(def.gen4DynamicPlate.height)
  end
  -- Platinum's slot: only the platform lift builds anything at field start
  -- here (PlatformLift_DynamicMapFeaturesInit: the slab at floorID's height)
  local M = require("src.world.Gen4DynamicMapFeatures")
  local lift = save.gen4MapFeature and M.buffer(save, M.PLATFORM_LIFT_ROOM)
  if lift then
    local Ride = require("src.world.Gen4PlatformLiftRide")
    local cfg = Ride.CONFIG[tonumber(def.header) or -1]
    local data = (ctx.game and ctx.game.data) or (package.loaded["src.core.Game"] or {}).data
    if cfg and lift.floorID then
      def.gen4PlatformLift = { floor = lift.floorID, header = def.header }
      Ride.setHeight(def, data, cfg.floors[lift.floorID + 1])
      return "platform lift at floor " .. tostring(lift.floorID)
    elseif cfg then
      -- a save from before floorID was kept: the floor the player stands on
      local p = ow.player
      local _, pz = toMatrix(ctx, p and p.cellX, p and p.cellY)
      lift.floorID = Ride.place(def, data, pz)
      return "platform lift at floor " .. tostring(lift.floorID) .. " (from the player)"
    end
  end
  return nil
end

-- APRICORNS (HGSS): the trees, the box and Kurt -- src/world/HgssApricorns.
local function apricornTreeOf(ctx)
  local def = ctx.npc and (ctx.npc.def or ctx.npc)
  return def and def.apricornTree
end
-- AnimApricornTree: 1 when the tree had its Apricorn (now shaken off), 0
-- when it was bare or is not a tree; two 16-frame wiggles either way
function Commands.g4_apricorn_tree_shake(ctx, destVar)
  local A = require("src.world.HgssApricorns")
  local idx = apricornTreeOf(ctx)
  local had = idx ~= nil and ctx.save ~= nil and A.treeHasFruit(ctx.save, idx)
  if had then A.pick(ctx.save, idx) end
  setVar(ctx.save, destVar, had and 1 or 0)
  local runner = ctx.runner
  if not (runner and idx) then return end
  local frames = 0
  runner.waitingCheck = function() frames = frames + 1; return frames >= 32 end
  runner:yield()
end
Commands.meta.g4_apricorn_tree_shake = { blocking = true }
function Commands.g4_apricorn_tree_colour(ctx, destVar)
  setVar(ctx.save, destVar, require("src.world.HgssApricorns").treeColour(apricornTreeOf(ctx)))
end
function Commands.g4_apricorn_give(ctx, colour, n, destVar)
  local A = require("src.world.HgssApricorns")
  local ok = ctx.save and A.give(ctx.save, math.floor(valueOf(ctx, colour) or 0), math.floor(valueOf(ctx, n) or 1))
  setVar(ctx.save, destVar, ok and 1 or 0)
end
function Commands.g4_buffer_apricorn(ctx, slot, colour)
  local A = require("src.world.HgssApricorns")
  local c = math.floor(valueOf(ctx, colour) or 0)
  if c < 0 or c >= 7 then c = 0 end
  Commands.g4_buffer(ctx, slot, "bank:" .. A.NAME_BANK, A.NAME_FIRST + c)
end
function Commands.g4_apricorn_total(ctx, destVar)
  setVar(ctx.save, destVar, ctx.save and require("src.world.HgssApricorns").total(ctx.save) or 0)
end
function Commands.g4_kurt_quantity(ctx, destVar)
  setVar(ctx.save, destVar, ctx.save and require("src.world.HgssApricorns").kurtQuantity(ctx.save) or 0)
end
function Commands.g4_kurt_ball(ctx, destVar)
  setVar(ctx.save, destVar, ctx.save and require("src.world.HgssApricorns").kurtBall(ctx.save) or 4)
end
function Commands.g4_kurt_clear(ctx)
  if ctx.save then require("src.world.HgssApricorns").setKurt(ctx.save, 0, 0) end
end
-- ScrCmd_739: the Apricorn Box opened to hand Kurt some -- which colour, how
-- many. A cancel leaves Kurt's quantity 0, which is how the script knows.
function Commands.g4_apricorn_box_for_kurt(ctx)
  local A = require("src.world.HgssApricorns")
  local save, runner = ctx.save, ctx.runner
  if not save then return end
  local data = ctx.game and ctx.game.data or {}
  local Text = require("src.import.Gen4Text")
  local rows = {}
  local function done() if runner then runner:resume() end end
  for c = 0, 6 do
    local n = A.count(save, c)
    if n > 0 then
      local name = data.text and data.text[Text.label(A.NAME_BANK, A.NAME_FIRST + c)] or ("APRICORN " .. c)
      rows[#rows + 1] = { label = ("%s x%d"):format(name, n), onSelect = function()
        ctx.game.stack:push(require("src.ui.QuantityBox").new(ctx.game, { max = n, onDone = function(q)
          if q and q > 0 then A.setKurt(save, c, q) end
          done()
        end }))
      end }
    end
  end
  if #rows == 0 then return end
  ctx.game.stack:push(require("src.ui.Menu").new(ctx.game, rows, { cancelable = true, onCancel = done }))
  if runner then runner:yield() end
end
Commands.meta.g4_apricorn_box_for_kurt = { foreground = true, blocking = true }

-- Save_SysInfo_SetMysteryGiftActive(.., 1); read by the title menu
function Commands.g4_unlock_mystery_gift(ctx)
  if ctx.save then ctx.save.gen4MysteryGiftUnlocked = true end
end

function Commands.g4_bank_transaction(ctx, mode, destVar)
  local ok, err = pcall(function()
    require("src.world.HgssMomSavings").transaction(ctx, math.floor(valueOf(ctx, mode) or 0), destVar,
      function(v) setVar(ctx.save, destVar, v) end)
  end)
  if not ok then
    Logger.warn("gen4 bank: the %s failed (%s) -- answering cancelled",
                tonumber(mode) == 0 and "deposit" or "withdrawal", tostring(err))
    setVar(ctx.save, destVar, 1)
  end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_bank_transaction = { foreground = true, blocking = true }

function Commands.g4_starter_species(ctx, destVar)
  setVar(ctx.save, destVar, playerStarter(ctx.save))
end

-- `startchoosestarterscene` -- `FieldSystem_LaunchChooseStarterApp` followed by
-- `ScriptContext_Pause(ctx, ScriptContext_WaitForApplicationExit)`.  The
-- cartridge parks the answer in a heap block (`ChooseStarterData`) that the
-- NEXT command reads and frees; `ctx.g4StarterChoice` is that block, and it is
-- carried on the script context for exactly the same lifetime.
--
-- The app cannot be cancelled out of -- you are made to choose -- so a cancel
-- here (the screen closing because the cache has no models) leaves the choice
-- unset and `savechosenstarter` writes nothing rather than guessing.
function Commands.g4_choose_starter(ctx)
  local runner = ctx.runner
  local Gen4StarterSelect = require("src.ui.Gen4StarterSelect")
  ctx.g4StarterChoice = nil
  local function finish()
    if runner then runner:resume() end
  end
  ctx.game.stack:push(Gen4StarterSelect.new(ctx.game, {
    onChoose = function(species)
      ctx.g4StarterChoice = tonumber(species)
      finish()
    end,
    onCancel = finish,
  }))
  if runner then runner:yield() end
end

-- `savechosenstarter` -- `SystemVars_SetPlayerStarter(..., data->species)`.
function Commands.g4_save_starter(ctx)
  local species = tonumber(ctx.g4StarterChoice)
  ctx.g4StarterChoice = nil
  if not species or species == 0 then
    Logger.warn("gen4 starter: `savechosenstarter` ran with no choice on the "
                .. "context -- the briefcase was closed without one, so "
                .. "VAR_PLAYER_STARTER is left as it was")
    return
  end
  setVar(ctx.save, VAR_PLAYER_STARTER, species)
  -- The port's own mirror, kept in step so anything still reading it agrees.
  if ctx.save then
    ctx.save.gen4Starter = species
    if ctx.save.player then ctx.save.player.starter = species end
  end
end

Commands.meta = Commands.meta or {}
Commands.meta.g4_choose_starter = { foreground = true, blocking = true }

-- HEARTGOLD / SOULSILVER: Elm's turntable (src/ui/Gen4HgssStarterSelect), and
-- the choice goes STRAIGHT INTO THE PARTY, as CreateStarter does -- level 5,
-- no held item, a Poke Ball -- because the lab script reads party slot 0
-- next and gives nothing itself. The app has no cancel on the cartridge; a
-- cache with no turntable models (imported before the stage) says so and
-- gives nothing.
Gen4Commands.HGSS_STARTERS = { 152, 155, 158 }
function Commands.g4_hgss_choose_starter(ctx)
  local runner = ctx.runner
  local Screen = require("src.ui.Gen4HgssStarterSelect")
  ctx.game.stack:push(Screen.new(ctx.game, {
    species = Gen4Commands.HGSS_STARTERS,
    onChoose = function(species)
      Commands.g4_give_pokemon(ctx, species, 5, 0, nil)
      ctx.g4StarterChoice = tonumber(species)
      if runner then runner:resume() end
    end,
    onCancel = function() if runner then runner:resume() end end,
  }))
  if runner then runner:yield() end
end
Commands.meta.g4_hgss_choose_starter = { foreground = true, blocking = true }

-- BLACK / WHITE: the gift box (0x153 <var>, src/ui/Gen5StarterSelect). The
-- app only ANSWERS 0..2 -- the bedroom script turns that into a species and
-- gives it with 0x10C itself.
function Commands.g4_bw_choose_starter(ctx, destVar)
  local runner = ctx.runner
  ctx.game.stack:push(require("src.ui.Gen5StarterSelect").new(ctx.game, {
    onChoose = function(index)
      setVar(ctx.save, destVar, index)
      if runner then runner:resume() end
    end,
  }))
  if runner then runner:yield() end
end
Commands.meta.g4_bw_choose_starter = { foreground = true, blocking = true }

-- BLACK / WHITE'S SHARED TRAINER SCRIPT (band 3000, member 863):
--   0x097 <trainer, dest>  1 when that trainer is beaten
--   0x092 <trainer, dest>  after a win: 1 when the trainer heals you (its
--        record's byte 0x10, trainer-data field 9), 2 when it has a prize
--        item (0x12, field 11), else 0 -- the handler asks the fields in
--        that order
--   0x066 <dest, object>  that object's movement type; 51..54 are the four
--        that make the script turn the trainer before it speaks
function Commands.g4_bw_trainer_beaten(ctx, trainer, destVar)
  local id = math.floor(valueOf(ctx, trainer) or 0)
  local t = trainerFlags(ctx.save)
  setVar(ctx.save, destVar, (t and t[id]) and 1 or 0)
end
function Commands.g4_bw_trainer_after(ctx, trainer, destVar)
  local id = math.floor(valueOf(ctx, trainer) or 0)
  local data = ctx.game and ctx.game.data
  local rec = data and data.trainers and data.trainers[id]
  local value = 0
  if rec and rec.healer then value = 1 elseif rec and (tonumber(rec.prizeItem) or 0) > 0 then value = 2 end
  setVar(ctx.save, destVar, value)
end
-- BLACK / WHITE 0x069 <x, y, dir, object, sprite, script>: a TEMPORARY
-- object, built on the spot rather than taken from the map's events. Made a
-- def record (the same path `addobject` spawns through) at the matrix tile
-- given, its picture the sheet any map's object of that sprite id uses. A
-- second spawn under the same id replaces the first (Castelia's gym door
-- runs 0xFB as Cheren, then as Burgh); `removeobject` retires it for good,
-- as the cartridge forgets these on the next map load.
local BW_DIR = { [0] = 0, [1] = 1, [2] = 2, [3] = 3 }
local function bwSheetFor(ctx, sprite)
  local data = ctx.game and ctx.game.data or (_G.Game and _G.Game.data)
  local here = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
  for _, o in ipairs(here and here.objects or {}) do
    if o.graphicsId == sprite and o.sprite then return o.sprite, o.spriteName end
  end
  for _, def in pairs(data and data.maps or {}) do
    for _, o in ipairs(type(def) == "table" and def.objects or {}) do
      if o.graphicsId == sprite and o.sprite then return o.sprite, o.spriteName end
    end
  end
  -- ...AND ONE NO MAP PLACES: the sprite table itself (/a/0/4/8, written as
  -- gen5_sprite_table by Gen5Field; every model member has its sheet).
  -- Nine spawn ids in each version are on no map -- Meloetta (123) in
  -- Castelia's cafe, 106 at eight sites, 1, 4, 113, 114, 211, 213, 4380 --
  -- and spawned with no picture they were invisible.
  return Gen4Commands.bwSpriteFromTable(data, sprite)
end
function Gen4Commands.bwSpriteFromTable(data, gfx)
  local okT, tab = pcall(require, "data.generated.gen5_sprite_table")
  local member = okT and type(tab) == "table" and tab[tonumber(gfx) or -1]
  local key = member and ("SPRITE_G4_%03d"):format(member)
  if key and data and data.sprites and data.sprites[key] then return key, ("bw_%03d"):format(member) end
  return nil
end
function Commands.g4_bw_spawn_object(ctx, x, y, dir, object, sprite, script)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  if not (def and def.objects) then return end
  local id, gfx = tonumber(valueOf(ctx, object)), tonumber(valueOf(ctx, sprite))
  if not (id and gfx) then return end
  local maxIndex = 0
  for _, o in ipairs(def.objects) do
    maxIndex = math.max(maxIndex, tonumber(o.index) or 0)
    if o.localId == id and o.gen5Temp and not o.hidden then
      o.hidden = true
      if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(o) end) end
    end
  end
  local ox, oy = mapOrigin(ctx)
  local key, name = bwSheetFor(ctx, gfx)
  local obj = { index = maxIndex + 1, localId = id, graphicsId = gfx, sprite = key, spriteName = name,
    x = (tonumber(valueOf(ctx, x)) or 0) - ox, y = (tonumber(valueOf(ctx, y)) or 0) - oy,
    direction = BW_DIR[tonumber(valueOf(ctx, dir)) or 1] or 1, movementType = 0,
    movementRangeX = 0, movementRangeY = 0, script = tonumber(valueOf(ctx, script)) or 0,
    elevation = 0, gen5 = true, gen5Temp = true }
  def.objects[#def.objects + 1] = obj
  if ow.syncObjectVisibility then pcall(function() ow:syncObjectVisibility(obj) end) end
end

-- PLATINUM: the Distortion World's cast by local id (overlay 9's table, see
-- src/world/Gen4DistPlatforms.lua)
function Commands.g4_dw_cast_add(ctx, localId)
  local id = tonumber(valueOf(ctx, localId))
  if id and ctx.overworld then require("src.world.Gen4DistPlatforms").castAdd(ctx.overworld, id) end
end
-- the scripts' own Giratina shadow (sGiratinaShadowExternal; 1F's flyby) --
-- started, left to fly, and cleared by the finish command
function Commands.g4_dw_shadow_start(ctx, index)
  if ctx.overworld then
    require("src.world.Gen4DistPlatforms").shadowExternal(ctx.overworld, tonumber(valueOf(ctx, index)) or 0)
  end
end
function Commands.g4_dw_shadow_finish(ctx)
  if ctx.overworld then require("src.world.Gen4DistPlatforms").shadowFinish(ctx.overworld) end
end
-- DistWorld_ResetPersistedCameraAngles: the turned camera back to its base
function Commands.g4_dw_reset_camera(ctx)
  local S = require("src.world.Gen4DistSurface")
  S.cam.x, S.cam.y, S.cam.n = 0, 0, 0
end
-- FieldSystem_StartDWWarp: the swirl (src/ui/Gen4DistortionWarp.lua); the
-- script waits for it as the cartridge's child process makes it wait
function Commands.g4_dw_warp(ctx)
  local game = ctx.game or require("src.core.Game")
  local ok, W = pcall(require, "src.ui.Gen4DistortionWarp")
  if not (ok and W and game.stack and ctx.runner) then return end
  game.stack:push(W.new(game, function() ctx.runner:resume() end))
  ctx.runner:yield()
end

function Commands.g4_dw_cast_delete(ctx, localId)
  local id = tonumber(valueOf(ctx, localId))
  if id and ctx.overworld then require("src.world.Gen4DistPlatforms").castDelete(ctx.overworld, id) end
end

function Commands.g4_bw_object_movement(ctx, destVar, object)
  local e = objectById(ctx, object)
  local mt = e and e.def and tonumber(e.def.movementType) or 0
  setVar(ctx.save, destVar, mt)
end

-- BLACK / WHITE 0x025 <flag, dest>: the flag's state into a var -- the flag
-- a var-or-literal (82 sites: "has this already happened" checks that a
-- script then branches on with the direct compare)
function Commands.g4_bw_flag_to_var(ctx, flag, destVar)
  local key = ('FLAG_G4_%04X'):format(math.floor(valueOf(ctx, flag) or 0))
  setVar(ctx.save, destVar, ((ctx.save and ctx.save.flags) or {})[key] and 1 or 0)
end

-- BLACK / WHITE 0x0E0 <var>: the game's version id, a constant in the
-- handler (`movs r1, #0x15`: Black is 21, White 20 -- Gen 5's ids). Scripts
-- pick the version's branch with `if (var == 21)`.
function Commands.g4_bw_version(ctx, destVar)
  local white = require("src.core.GameVersion").get() == "white"
  setVar(ctx.save, destVar, white and 20 or 21)
end

-- BLACK / WHITE 0x0D0 <month var, day var>: today's date, from the clock.
function Commands.g4_bw_date(ctx, monthVar, dayVar)
  setVar(ctx.save, monthVar, tonumber(os.date("%m")) or 1)
  setVar(ctx.save, dayVar, tonumber(os.date("%d")) or 1)
end
-- 0x0D4 <month var, day var>: the birthday in the DS's own user profile, which
-- every nurse compares with today ("Hey! Is today your birthday?"). A PC has
-- no such profile; save.player.birthday = { month, day } supplies one, and
-- without it both read 0 -- no day of the year, so the greeting never fires.
function Commands.g4_bw_birthday(ctx, monthVar, dayVar)
  local b = ctx.save and ctx.save.player and ctx.save.player.birthday
  setVar(ctx.save, monthVar, type(b) == "table" and tonumber(b.month or b[1]) or 0)
  setVar(ctx.save, dayVar, type(b) == "table" and tonumber(b.day or b[2]) or 0)
end

-- BLACK / WHITE 0x110 <dest, slot, u16>: 1 when that party Pokemon carries a
-- nickname (Juniper's "Are you OK with the nickname {VAR1}?" runs on 1, and
-- the loop goes round again after a NO)
function Commands.g4_mon_has_nickname(ctx, destVar, slotVar)
  local slot = math.floor(valueOf(ctx, slotVar) or 0)
  local mon = ctx.save and ctx.save.party and ctx.save.party[slot + 1]
  local data = ctx.game and ctx.game.data
  local def = mon and data and data.pokemon and data.pokemon[mon.species]
  local nick = mon and mon.nickname
  local has = type(nick) == "string" and nick ~= "" and nick ~= (def and def.name)
  setVar(ctx.save, destVar, has and 1 or 0)
end

-- BLACK / WHITE 0x101 <dest, slot>: 1 when that party Pokemon's HP is full
-- (MON_DATA 0xA0 == 0xA1) or it is an Egg (0x4C), else 0 -- Cheren's "you
-- won without your Pokemon's losing any energy" asks it after Bianca's battle
function Commands.g4_mon_hp_full(ctx, destVar, slotVar)
  local slot = math.floor(valueOf(ctx, slotVar) or 0)
  local mon = ctx.save and ctx.save.party and ctx.save.party[slot + 1]
  local full = 0
  if mon then
    local max = mon.stats and tonumber(mon.stats.hp)
    if mon.isEgg or (max and (tonumber(mon.hp) or 0) >= max) then full = 1 end
  end
  setVar(ctx.save, destVar, full)
end

-- `PlaceStarterBallsInElmsLab` (scrcmd_c.c): building model 0x8D, `labo_mb`,
-- at (131, 0, 65), (141, 0, 65) and (136, 0, 72) -- on the machine -- as many
-- as are still there: none after Falkner's TM51, one after meeting the
-- passer-by boy, two once you have a Pokemon, otherwise three.
-- ScrCmd_GetFriendSprite: SPRITE_HERO (0) unless the player is the boy, then
-- SPRITE_HEROINE (97) -- pokeheartgold's constants/sprites.h
function Commands.g4_friend_sprite(ctx, var)
  local girl = ctx.save and ctx.save.player and ctx.save.player.gender == "girl"
  setVar(ctx.save, var, girl and 0 or 97)
end

Gen4Commands.ELMS_LAB_BALLS = { { 131, 0, 65 }, { 141, 0, 65 }, { 136, 0, 72 } }
function Commands.g4_place_starter_balls(ctx)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  if not def then return end
  local function flag(id)
    Commands.check_flag(ctx, ("FLAG_G4_%04X"):format(id))
    return ctx.lastCheck and true or false
  end
  local party = ctx.save and ctx.save.party or {}
  local n = flag(0x73) and 0 or flag(0x99) and 1 or (#party > 0 and 2) or 3
  local props = {}
  for i = 1, n do
    local c = Gen4Commands.ELMS_LAB_BALLS[i]
    props[i] = { model = 0x8D, x = c[1], y = c[2], z = c[3] }
  end
  def.gen4RuntimeProps = props
end

-- `SetStarterChoice <var>`: Save_VarsFlags_SetStarter, the same field
-- `savechosenstarter` writes on Platinum.
function Commands.g4_set_starter_choice(ctx, var)
  local species = math.floor(valueOf(ctx, var) or 0)
  if species == 0 then return end
  setVar(ctx.save, VAR_PLAYER_STARTER, species)
  if ctx.save then
    ctx.save.gen4Starter = species
    if ctx.save.player then ctx.save.player.starter = species end
  end
end

-- `givepokemon <species> <level> <heldItem> <destVar>` -- every one of the
-- first three is a VAR-or-literal (`ScriptContext_GetVar`), which matters here
-- because the starter is handed over as `givepokemon 0x8000, 5, 0, 0x800C`
-- and 0x8000 is a var.  The fourth is where `Pokemon_GiveMonFromScript`'s
-- success answer goes, and a script that reads it decides whether to say "you
-- got it" or "your party is full".
function Commands.g4_give_pokemon(ctx, species, level, heldItem, destVar)
  local id = math.floor(valueOf(ctx, species) or 0)
  local lv = math.max(math.floor(valueOf(ctx, level) or 1), 1)
  local item = math.floor(valueOf(ctx, heldItem) or 0)
  local mons = ctx.game and ctx.game.data and ctx.game.data.pokemon
  if id == 0 or not (mons and mons[id]) then
    Logger.warn("gen4 script: `givepokemon` names species %s, which this "
                .. "dataset does not carry -- nothing is given and the "
                .. "destination var says so", tostring(id))
    if destVar then setVar(ctx.save, destVar, 0) end
    return
  end
  -- NO NICKNAME PROMPT.  `Pokemon_GiveMonFromScript` adds the mon and returns;
  -- Gen 4 asks about a nickname from a separate script path when it asks at
  -- all, and the starter is not one of the times it does.
  local opts = nil
  if item ~= 0 then
    local key = itemKey(ctx.game.data, item)
    if ctx.game.data.items and ctx.game.data.items[key] then
      opts = { heldItem = key }
    end
  end
  Commands.give_pokemon(ctx, id, lv, true, opts)
  if destVar then setVar(ctx.save, destVar, ctx.lastCheck and 1 or 0) end
end

-- `GiveSpikyEarPichu` (pokeheartgold scrcmd_pokemon_misc.c 1099), the Ilex
-- Forest shrine's reward for walking a shiny event Pichu there: a level 30
-- Pichu in form 1 (Spiky-eared), Naughty and female, knowing Helping Hand,
-- Volt Tackle, Swagger and Pain Split, holding a Zap Plate -- into the party
-- only, and nothing when it is full.
Commands.SPIKY_EAR_PICHU = { species = 172, level = 30, form = 1, nature = "NAUGHTY",
  moves = { 270, 344, 207, 220 }, item = 300 }
function Commands.g4_give_spiky_ear_pichu(ctx)
  local save, data = ctx.save, ctx.game and ctx.game.data
  if not (save and data) or #(save.party or {}) >= 6 then return end
  local P = Commands.SPIKY_EAR_PICHU
  local key = itemKey(data, P.item)
  Commands.give_pokemon(ctx, P.species, P.level, true,
    (data.items and data.items[key]) and { heldItem = key } or nil)
  local mon = save.party[#save.party]
  if not (mon and tonumber(mon.species) == P.species) then return end
  mon.form, mon.formIndex = P.form, P.form
  mon.nature, mon.gender = P.nature, "female"
  mon.moves = {}
  local moves = data.moves or {}
  for i, id in ipairs(P.moves) do
    local def = moves[id]
    mon.moves[i] = { id = id, pp = def and def.pp or 0, ppUps = 0 }
  end
end

-- ---------------------------------------------------------------------------
-- small state the opening reads
-- ---------------------------------------------------------------------------
--
-- Each of these is two or three lines on the cartridge and each was going
-- through the unknown-command path, which is worse than it sounds for the
-- ones that write a var: the branch after them reads whatever the LAST
-- comparison left in the register, so an unlowered `countbadgesacquired` does
-- not just fail to count badges, it makes the next `gotoif` decide at random.

-- `PlayerData_SetRunningShoes(playerData, TRUE)`.  Mum hands them over in the
-- player's own house, which is why this one is in the opening at all.
function Commands.g4_running_shoes(ctx)
  local save = ctx.save
  if not save then return end
  save.player = save.player or {}
  save.player.runningShoes = true
  -- The engine's own spelling, so whatever already gates running agrees.
  save.hasRunningShoes = true
end

-- `ScrCmd_CheckRunningShoesAcquired`: `*destVar = PlayerData_HasRunningShoes(playerData)`.
--
-- THE FLAG ABOVE WAS WRITTEN AND READ BY NOTHING -- the sixth time this port has
-- done that, after gen4_species_sprites, gen4_move_anims, gen4_particles,
-- gen4_overworld and the terrain's own area-light byte. The comment on
-- `g4_running_shoes` says it writes both spellings "so whatever already gates
-- running agrees", and nothing did: `OverworldState:runFrames` refused every Gen 4
-- dataset outright, and 0x159 had no lowering at all, so neither the engine nor a
-- script could see the shoes the player had been given.
--
-- `PlayerData_HasRunningShoes` returns TRUE/FALSE, so the var gets 1 or 0 and not
-- a Lua boolean: the comparisons that follow it are numeric.
function Commands.g4_has_running_shoes(ctx, destVar)
  local save = ctx.save
  local shoes = save
    and (save.hasRunningShoes
         or (save.player and save.player.runningShoes))
  setVar(ctx.save, destVar, shoes and 1 or 0)
end

-- `TimeOfDayForHour` (src/rtc.c), transcribed from its 24-entry lookup:
-- 0-3 LATE_NIGHT, 4-9 MORNING, 10-16 DAY, 17-19 TWILIGHT, 20-23 NIGHT.  The
-- values are the 0-based `generated/time_of_day.txt` enum -- MORNING 0, DAY 1,
-- TWILIGHT 2, NIGHT 3, LATE_NIGHT 4 -- and NOT this engine's own Gen 2 period
-- names, which are a different set with a different ordering.
-- DELEGATED, so there is ONE transcription of that lookup rather than two that
-- can drift.  It moved to `Gen4Encounters` because the encounter roll needs the
-- same answer and that module has no requires -- a check can load it alone,
-- which this file is far too entangled to allow.  Required lazily, matching how
-- this file already reaches `Gen4Text`.
local function timeOfDayValue(hour)
  return require("src.import.Gen4Encounters").timeOfDayForHour(hour)
end
Gen4Commands.timeOfDayValue = timeOfDayValue

function Commands.g4_time_of_day(ctx, destVar)
  setVar(ctx.save, destVar, timeOfDayValue(tonumber(os.date("%H"))))
end

-- `countbadgesacquired` walks sBadgeIDs and counts.  This port keeps badges in
-- the save the engine's own way; both spellings are read because a Gen 4 save
-- may carry either.
function Commands.g4_count_badges(ctx, destVar)
  local save = ctx.save
  local badges = save and (save.badges or (save.player and save.player.badges))
  local count = 0
  if type(badges) == "table" then
    for _, has in pairs(badges) do if has then count = count + 1 end end
  elseif type(badges) == "number" then
    local n = math.floor(badges)
    while n > 0 do
      if n % 2 == 1 then count = count + 1 end
      n = math.floor(n / 2)
    end
  end
  setVar(ctx.save, destVar, count)
end

-- `Poketch_IsAppRegistered`.  The watch's own corner of the save is
-- `save.poketch`, which `src/ui/Gen4Poketch` creates on demand.
function Commands.g4_poketch_registered(ctx, appId, destVar)
  local id = math.floor(valueOf(ctx, appId) or 0)
  local store = ctx.save and ctx.save.poketch
  local apps = store and (store.registered or store.apps)
  local yes = 0
  if type(apps) == "table" and apps[id] then yes = 1 end
  setVar(ctx.save, destVar, yes)
  setResult(ctx, yes)
end

-- `getsetnationaldexenabled <getOrSet> <destVar>`: 1 grants the National Dex,
-- 2 asks whether it is held.  The destination is written to ZERO first in both
-- cases, which is what the set branch leaves behind.
function Commands.g4_national_dex(ctx, getOrSet, destVar)
  local mode = math.floor(valueOf(ctx, getOrSet) or 0)
  local dex = ctx.save and ctx.save.pokedex
  local value = 0
  if mode == 1 then
    if dex then dex.national = true end
  elseif mode == 2 then
    value = (dex and dex.national) and 1 or 0
  end
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- ---------------------------------------------------------------------------
-- badges, and the trainer's own class
-- ---------------------------------------------------------------------------

-- `givebadge <n>` -- `TrainerInfo_SetBadge`, zero-based.  Oreburgh's gym leader
-- script is the first one, and without it the Coal Badge is never awarded, so
-- every later gate that counts badges reads one short for the rest of the
-- game.
--
-- WRITTEN TWO WAYS ON PURPOSE.  `save.badges` is the record `g4_count_badges`
-- reads, and `save.inventory` is where every other generation in this engine
-- keeps a badge -- `makeBattler` walks `badgeBoosts` and asks the BAG.  Gen 4
-- awards no stat boost (its `badgeBoosts` list is absent, so the lookup finds
-- nothing either way), but a badge that is not in the bag is a badge the
-- trainer card and the save editor cannot see.
function Commands.g4_give_badge(ctx, badgeNum)
  local save = ctx.save
  if not save then return end
  local n = math.floor(valueOf(ctx, badgeNum) or 0)
  local rows = ctx.game and ctx.game.data and ctx.game.data.constants
               and ctx.game.data.constants.badges
  local row = rows and rows[n + 1]          -- the cartridge counts from zero
  local id = (type(row) == "table" and row.id) or row
  if type(id) ~= "string" then
    Logger.warn("gen4 script: `givebadge %d` names no badge in this cache -- "
                .. "nothing is awarded", n)
    return
  end
  save.badges = save.badges or {}
  save.badges[id] = true
  require('src.inventory.Badges').set(save,row,true,'platinum')
  Logger.info("gen4: awarded %s", id)
end

-- TRAINER CLASS NAMES, INVERTED OUT OF THE TRAINER TABLE.
--
-- The cartridge reads them from a message bank; this port has not indexed that
-- bank by class, but every trainer row carries `class` AND `className`, so the
-- mapping is already in the cache.  Built on first use and kept, because the
-- table is 979 rows and the answer never changes.
local classNames = nil

function Gen4Commands.trainerClassName(data, classId)
  local id = tonumber(classId)
  if not id then return nil end
  if not classNames then
    classNames = {}
    for _, row in pairs((data and data.trainers) or {}) do
      if type(row) == "table" and row.class and type(row.className) == "string"
         and row.className ~= "" and classNames[row.class] == nil then
        classNames[row.class] = row.className
      end
    end
  end
  return classNames[id]
end

-- `capitalizefirstletter <slot>` -- `StringTemplate_CapitalizeArgAtIndex`.
-- Real, and one line: the buffered word is already in hand.
function Commands.g4_capitalize(ctx, slot)
  local buffers = ctx.game and ctx.game.stringBuffers
  local i = (tonumber(slot) or 0) + 1
  local text = buffers and buffers[i]
  if type(text) ~= "string" or text == "" then return end
  buffers[i] = text:sub(1, 1):upper() .. text:sub(2)
end

-- A QUESTION THIS PORT CANNOT ANSWER, ANSWERED HONESTLY AS "NO".
--
-- Distinct from `g4_noop`, which is for a row that does nothing on screen, and
-- from `pending()`, which is for a verb whose feature is on the way.  This is
-- for a command that WRITES A VAR and whose feature does not exist here: the
-- var has to be written, because the `gotoif` behind it would otherwise branch
-- on whatever the previous comparison left in the register.  Zero is both the
-- truthful answer and the one that keeps the script on its ordinary path.
local noFeatureSeen = {}

function Commands.g4_no_feature(ctx, destVar, feature)
  if destVar then setVar(ctx.save, destVar, 0) end
  setResult(ctx, 0)
  local key = tostring(feature)
  if not noFeatureSeen[key] then
    noFeatureSeen[key] = true
    Logger.info("gen4 script: a row asked about %s, which this port does not "
                .. "have -- the answer is no, and the branch behind it takes "
                .. "its ordinary path", key)
  end
end

-- ---------------------------------------------------------------------------
-- the trainer battle
-- ---------------------------------------------------------------------------
--
-- WHAT WAS ACTUALLY MISSING was one shape mismatch and a result register.
--
-- `BattleState.newTrainer(game, oppClass, partyIndex)` reads
-- `trainers[key].parties[i]`, because Gen 1 and Gen 2 put SEVERAL trainers in
-- one class. Gen 4 numbers every trainer individually and gives each one
-- party, so the record sits one level shallower than the reader --
-- `Data:seedDefaults` now exposes `parties = { party }` as a view. Everything
-- else the builder wants, the extractor already wrote: species, level, moves,
-- the IV scale, the battle type, the class name.
--
-- THE OBJECT ALREADY KNOWS WHO IT IS. A trainer's object event carries a
-- script id in the `single_battles` band (3000+) or `double_battles` (5000+),
-- and `Script_GetTrainerID` is `scriptID - offset + 1`. The extractor resolved
-- that at import and hung the answer on the def:
--
--     script = 3231, scriptBand = "single_battles",
--     trainer = { id = 232, name = "David", class = 14,
--                 className = "Black Belt", partySize = 2 }
--
-- so `gettrainerid` is a field read rather than arithmetic this file repeats.
local function trainerOnObject(ctx)
  local npc = ctx.npc
  local def = npc and npc.def
  local rec = def and def.trainer
  return rec and tonumber(rec.id) or nil
end

-- `Script_IsTrainerDoubleBattle`: `battleType ~= BATTLE_TYPE_SINGLES` on the
-- trainer the running script belongs to.  ONE SPELLING, two callers --
-- `g4_check_trainer_double` answers the script's question and
-- `g4_trainer_message_types` picks which of four message rows to use, and the
-- two disagreeing would give a double-battle trainer a single-battle line (or
-- the reverse) with nothing failing.  That shape of bug -- the same test
-- spelled twice in places that never meet -- has cost this port eight
-- separate findings, so the second caller got a helper rather than a copy.
local function trainerIsDouble(ctx, id)
  local trainers = ctx.game and ctx.game.data and ctx.game.data.trainers
  local rec = id and trainers and trainers[id]
  return (rec and (rec.doubleBattle
                   or (tonumber(rec.battleType) or 0) ~= 0)) and true or false
end

-- `Script_GetTrainerBattlerIndex(scriptID)` is `!(scriptID < 5000)` -- which
-- of a double pair this script is, and it is read off the SCRIPT ID BAND
-- rather than off the trainer: the second trainer of a pair is addressed by an
-- id in the `double_battles` band and nothing on the trainer record says so.
-- The extractor already resolved the band onto the object def (417 of them in
-- the cartridge: 407 `single_battles` and 10 `double_battles`), so this is a
-- field read.
local function trainerBattlerIndex(ctx)
  local npc = ctx.npc
  local def = npc and npc.def
  return (def and def.scriptBand == "double_battles") and 1 or 0
end

-- `starttrainerbattle <enemy1> <enemy2>` -- both var-or-literal, and the
-- SECOND is TRAINER_NONE (0) for an ordinary fight. A non-zero second is two
-- opponents at once, which `start_battle` already knows how to build:
-- `trainerBKey` fills the other half of the field from that trainer's own
-- party rather than a second Pokemon from the first's.
-- `extra` is for the ONE caller that needs a different rule -- the Route 201
-- first battle, which may be lost without a blackout. Every other caller
-- passes two operands and gets exactly what it always got.
function Commands.g4_start_battle(ctx, enemy1, enemy2, extra)
  local id = math.floor(valueOf(ctx, enemy1) or 0)
  local other = math.floor(valueOf(ctx, enemy2) or 0)
  local trainers = ctx.game and ctx.game.data and ctx.game.data.trainers
  local rec = trainers and trainers[id]
  -- `parties[1][1]`, not `parties[1]`: an EMPTY party is a live table and
  -- would pass a truthiness test, then take the game down in `makeBattler`
  -- with `data.pokemon[nil]`. Exactly one trainer in the cartridge is empty --
  -- id 0, TRAINER_NONE, which is the value `enemy2` carries for an ordinary
  -- single battle -- so this guard is cheap and the case it catches is real.
  if not (rec and type(rec.parties) == "table" and type(rec.parties[1]) == "table"
          and rec.parties[1][1]) then
    Logger.warn("gen4 battle: trainer %d is not in this cache (or carries no "
                .. "party) -- the battle is skipped and the script carries on "
                .. "as though it were lost", id)
    ctx.g4BattleWon = false
    setResult(ctx, 0)
    return
  end
  -- The defeated flag is the cartridge's own bank (TRAINER_DEFEATED_FLAGS_
  -- START + id), which this port keeps in `save.gen4TrainerFlags` and
  -- `checktrainerflag` already reads. Set on a WIN only, and set HERE because
  -- this is the only place the result arrives.
  ctx.g4Trainer = id
  local opts = { double = (other ~= 0) or rec.doubleBattle or nil }
  -- WHICH BATTLE THE TWO IDS MAKE (Encounter_NewVsTrainer; HGSS
  -- SetupAndStartTrainerBattle is the same test): two DIFFERENT trainers are
  -- a tag battle -- BATTLE_TYPE_TRAINER_WITH_AI_PARTNER when a partner is
  -- named, the partner fighting beside the player; the SAME id twice is
  -- BATTLE_TYPE_TRAINER_DOUBLES, one trainer's own double (the eye script's
  -- doubles branch passes the pair's ids, which are one id); a lone id is
  -- BATTLE_TYPE_TRAINER (made a double by the record's own battle type).
  -- Only the first fields the partner: the other two load the partner's
  -- record into the DTO and never put it on the field, so an escort walking
  -- with you fights only beside two different trainers.
  local tag = other ~= 0 and other ~= id
  if tag and trainers[other] then opts.trainerBKey = other end
  if extra and extra.canLose then opts.canLose = true end
  local ally = tag and ((extra and extra.ally) or Gen4Commands.escortAlly(ctx)) or nil
  if ally then opts.ally, opts.double = ally, true end
  Commands.start_battle(ctx, "trainer", id, 1, opts)
end

-- `checkwonbattle <destVar>` -- `CheckPlayerWonBattle(*battleResult)`.
--
-- `start_battle` leaves its answer in `ctx.lastBattleResult`; reading THAT
-- rather than keeping a second copy is what stops the two disagreeing after a
-- battle the script did not start.
function Commands.g4_check_won_battle(ctx, destVar)
  local won = (ctx.lastBattleResult == "win")
  Logger.debug("gen4 script: the last battle ended %s", tostring(ctx.lastBattleResult))
  -- ...and mark the trainer beaten, once, on the way past. The cartridge does
  -- this in the battle teardown rather than the script -- no Sinnoh script
  -- runs `settrainerflag` after a fight -- so a port that waited for one would
  -- have every trainer in the region challenge you again for ever. Same shape
  -- as the Gen 3 fix in `start_battle`.
  -- ...EXCEPT ON HEARTGOLD / SOULSILVER, whose shared trainer script
  -- (scr_seq_0953) asks GoToIfDefeated right after CheckBattleWon and only
  -- then runs SetTrainerFlag itself: marked here, every first win took the
  -- rematch branch (and its phone-gift rows).
  local hgss = require("src.import.Gen4ScriptBands").family == "hgss"
  -- HGSS's CheckBattleWon is IsBattleResultWin (battle_setup.c): anything but
  -- LOSE or DRAW, so catching or fleeing from a static Pokemon counts --
  -- Route 36's Sudowoodo otherwise white-outs on a catch
  if hgss then
    local r = ctx.lastBattleResult
    won = r ~= "lose" and r ~= "draw"
  end
  if won and ctx.g4Trainer and not hgss then
    local t = trainerFlags(ctx.save)
    if t then t[ctx.g4Trainer] = true end
    ctx.g4Trainer = nil
  elseif hgss then
    ctx.g4Trainer = nil
  end
  local value = won and 1 or 0
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- `checklostbattle <destVar>` -- `CheckPlayerLostBattle`, which reads a
-- DIFFERENT bit of the same result mask.  Not the negation of the above: a
-- battle that ended some third way answers no to both, and the one script that
-- asks is branching on a real loss rather than on "did not win".
function Commands.g4_check_lost_battle(ctx, destVar)
  local value = (ctx.lastBattleResult == "lose") and 1 or 0
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- `gettrainerid <destVar>` -- who the running script belongs to.
function Commands.g4_get_trainer_id(ctx, destVar)
  local id = trainerOnObject(ctx) or ctx.g4Trainer or 0
  if destVar then setVar(ctx.save, destVar, id) end
  setResult(ctx, id)
end

-- The cartridge reads the selected encounter slot, not the script owner.
-- Any nonzero approach number selects the second trainer. This lookup writes
-- only its destination and leaves the last comparison intact.
function Commands.g4_get_approaching_trainer_id(ctx, approachNum, destVar)
  local slot = valueOf(ctx, approachNum) == 0 and 1 or 2
  local trainers = ctx.gen4ApproachingTrainers
  local id = trainers and tonumber(trainers[slot])
  if id == nil and slot == 1 then id = trainerOnObject(ctx) end
  setVar(ctx.save, destVar, id or 0)
end

-- `getrematchtrainerid <trainer> <destVar>` --
-- `VsSeeker_GetRematchTrainerID(fieldSystem, targetObject, trainerID)`, which
-- answers TRAINER_NONE (0) when this object is not armed for a rematch.
--
-- THIS IS ON THE PATH TAKEN EVERY TIME YOU TALK TO A BEATEN TRAINER.
-- `scripts_battles.s` opens with `GoToIfDefeated VAR_0x8004,
-- Battles_TryRematch`, and `Battles_TryRematch` is two lines:
--
--     GetRematchTrainerID VAR_0x8004, VAR_RESULT
--     GoToIfNe VAR_RESULT, TRAINER_NONE, Battles_Rematch
--
-- so an unlowered command left VAR_RESULT holding whatever the previous script
-- put there and the branch was a coin toss: a beaten trainer either greeted you
-- normally or re-challenged you with a rematch party they were never armed
-- with.  One use in the file, and one of the most frequently reached lines in
-- the game -- every beaten trainer you walk past and talk to again.
--
-- THE STORE IS PER MAP OBJECT, NOT PER TRAINER ID, because the same trainer id
-- can appear on two maps; `VsSeeker.rematchFor` is keyed that way already.
-- `trainer` is accepted and not used in the lookup, which is the cartridge's
-- shape too -- it passes the id and resolves by object.
-- `startapproachingtrainertask <approachNum>` -- on the cartridge this spawns
-- the task that walks the trainer up to the player.  Our overworld has already
-- done the walking by the time any script runs, so there is nothing to start.
-- ...EXCEPT FOR THE SECOND OF TWO SEPARATE TRAINERS (VS2), whom the
-- cartridge's eye script walks up only after the first has spoken: the
-- overworld puts the pair on `ctx.gen4Approachers` and this walks the slot
-- that has not come yet (src/world/Gen4TwoTrainers.lua). With no pair on the
-- context it is still the no-op it was.
function Commands.g4_start_approach(ctx, approachNum)
  return require("src.world.Gen4TwoTrainers").startApproach(ctx, approachNum)
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_start_approach = { foreground = true, blocking = true }

-- `checkisapproachingtrainertaskdone <approachNum> <destVar>` -- and this one
-- is NOT cosmetic.  The C's first branch is
--
--     if (*task == NULL) { *destVar = TRUE; return TRUE; }
--
-- and our task is always NULL, because `g4_start_approach` never makes one.
-- So TRUE is the faithful answer and not a shortcut -- it is the same line of
-- the cartridge's own function.
--
-- WRITING IT IS THE WHOLE POINT.  `Battles_WaitTrainerSinglesTaskDone` jumps
-- to itself while this reads FALSE, so a row that wrote nothing left the loop
-- spinning on whatever the previous script put in VAR_RESULT.  That is a hang,
-- not a missing animation, and it is why this is lowered now rather than when
-- the approach band is first dispatched.
function Commands.g4_approach_done(ctx, approachNum, destVar)
  if destVar then setVar(ctx.save, destVar, 1) end
  setResult(ctx, 1)
end

-- `getapproachingtrainertype <destVar>` -- APPROACH_TYPE_SINGLES (0),
-- APPROACH_TYPE_DOUBLES (1) or APPROACH_TYPE_VS2 (2), and the cartridge always
-- reads TRAINER 0's slot even when asking about the pair.
--
-- Derived from the pair the overworld put on the context rather than stored:
-- `gen4ApproachingTrainers` is { id0, id1 } and a non-zero second id is a
-- double.  VS2 -- two trainers who notice you together and fight you one after
-- the other -- is NOT reachable from that state, because our sight scan pairs
-- trainers or takes them singly and has no third arrangement.  Returning
-- SINGLES for it would be wrong rather than incomplete, so when the day comes
-- the scan should set the type and this should read it.
-- ...and it does now: the VS2 run sets `ctx.gen4ApproachType = 2`
-- (src/world/Gen4TwoTrainers.lua), which wins over the derivation.
function Commands.g4_approach_type(ctx, destVar)
  local trainers = ctx.gen4ApproachingTrainers
  local second = trainers and tonumber(trainers[2]) or 0
  local kind = (second ~= 0) and 1 or 0
  if ctx.gen4ApproachType then kind = ctx.gen4ApproachType end
  if destVar then setVar(ctx.save, destVar, kind) end
  setResult(ctx, kind)
end

function Commands.g4_get_rematch_trainer_id(ctx, trainer, destVar)
  local value
  if require("src.import.Gen4ScriptBands").family ~= "hgss" then
    -- Platinum: the armed object's next rung (src/world/Gen4VsSeeker.lua)
    value = require("src.world.Gen4VsSeeker").rematchTrainerId(ctx.save, ctx.overworld, ctx.npc)
  else
    local VsSeeker = require("src.world.VsSeeker")
    value = tonumber(VsSeeker.rematchFor(ctx.save, ctx.overworld, ctx.npc)) or 0
  end
  value = tonumber(value) or 0
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- `setmovecodeforfacingdirection` -- after a battle the cartridge gives the
-- trainer a movement script that leaves them facing the way they were facing
-- when you beat them (`VsSeeker_SetMoveCodeForFacingDirection`), with a special
-- case for the Hearthome Gym's rotating trainers.
--
-- A NO-OP, AND SAYING WHY: our trainers do not walk off and return, so there is
-- no movement code to replace and an NPC keeps the facing it already had.  The
-- cartridge's purpose is served by doing nothing -- which is NOT the same as
-- the row being unlowered.  Unlowered it logged a warning in the middle of
-- every trainer battle in the region and left the next reader unable to tell
-- whether something was missing.  One use, in `Battles_DoTrainerBattle`.
-- ...except that on Platinum it is also where an armed Vs. Seeker trainer (and
-- a double partner) stands down after the rematch.
function Commands.g4_set_move_code_facing(ctx)
  if require("src.import.Gen4ScriptBands").family == "hgss" then return end
  pcall(require("src.world.Gen4VsSeeker").clear, ctx.save, ctx.overworld, ctx.npc)
end

-- `StartVsSeeker <destVar>` (VsSeeker_Start): 0 OK, 1 no battery (missing
-- steps to STRVAR 0), 2 no trainers in range, 3 nobody ready
function Commands.g4_start_vs_seeker(ctx, destVar)
  local V = require("src.world.Gen4VsSeeker")
  local ok, result, missing = pcall(V.use, ctx.game, ctx.overworld)
  if not ok then result = V.RESULT.NO_TRAINERS end
  if result == V.RESULT.NO_BATTERY and ctx.game then
    ctx.game.stringBuffers = ctx.game.stringBuffers or {}
    ctx.game.stringBuffers[1] = tostring(missing or 0)
  end
  if destVar then setVar(ctx.save, destVar, result) end
  setResult(ctx, result)
end

-- GameRecords_AddToRecordValue: record IDs are literal; only the small
-- add command resolves its amount through script variables. The cartridge
-- has 71 u32 counters followed by 77 u16 counters, each with its own limit.
local highRecordLimits = {}
for id = 0, 40 do highRecordLimits[id] = true end
for _, id in ipairs({3, 9, 10, 11}) do highRecordLimits[id] = nil end
for id = 57, 69 do highRecordLimits[id] = true end
for _, id in ipairs({71, 72, 74, 75, 94, 112}) do highRecordLimits[id] = true end
function Commands.g4_add_game_record(ctx, recordId, amount, literal)
  local id = tonumber(recordId)
  if not ctx.save or not id or id < 0 or id >= 148 or id % 1 ~= 0 then return end
  local value = literal and tonumber(amount) or valueOf(ctx, amount)
  value = math.floor(tonumber(value) or 0) % 4294967296
  local limit = id < 71 and (highRecordLimits[id] and 999999999 or 999999)
    or (highRecordLimits[id] and 65535 or 9999)
  local records = ctx.save.gen4GameRecords or {}
  ctx.save.gen4GameRecords = records
  records[id] = math.min(limit, ((tonumber(records[id]) or 0) + value) % 4294967296)
end

-- `checkmetfurniturerequirements <piece> <destVar>`
function Commands.g4_villa_requirements(ctx, piece, destVar)
  local R = require("src.pokemon.Gen4GameRecords")
  local ok = R.villa(ctx.save, valueOf(ctx, piece), function(v) return getVar(ctx.save, v) end)
  local d = tonumber(destVar)
  if d then setVar(ctx.save, d, ok and 1 or 0) end
end

-- `incrementtrainerscore <event>` -- GameRecords_IncrementTrainerScore
-- (src/pokemon/Gen4GameRecords.lua: sTrainerScoreIncrements, capped)
function Commands.g4_trainer_score(ctx, event)
  if not ctx.save then return end
  require("src.pokemon.Gen4GameRecords").score(ctx.save, tonumber(event))
end

-- `checkistrainerdoublebattle <destVar>` -- `battleType != BATTLE_TYPE_SINGLES`
-- on the trainer this script belongs to.
function Commands.g4_check_trainer_double(ctx, destVar)
  local id = trainerOnObject(ctx) or ctx.g4Trainer
  local value = trainerIsDouble(ctx, id) and 1 or 0
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- `gettrainermessagetypes <preVar> <postVar> <notEnoughVar>` --
-- `ScrCmd_GetTrainerMessageTypes`, which answers "which of this trainer's
-- twenty message slots do the three lines in `scripts_battles.s` mean?"
--
-- THE OPERANDS ARE VAR IDS, NOT VAR-OR-LITERALS.  The C takes all three with
-- `ScriptContext_GetVarPointer` rather than `ScriptContext_GetVar`, so they
-- are destinations.  `valueOf` here would read each destination and then write
-- to whatever its contents named -- var 0, three times, on a fresh save -- and
-- the script would go on to print message type 0 for all three lines because
-- that is what an unwritten var reads as.  Which is PRE_BATTLE, so the defeat
-- line would be the challenge line and it would look like a text-table
-- problem rather than an addressing one.
--
-- The four rows live in `Gen4TrainerMessages.SCRIPT_TYPES`; see there for the
-- literal zeroes, which are the cartridge's and not placeholders.
function Commands.g4_trainer_message_types(ctx, preVar, postVar, notEnoughVar,
                                           rematch)
  local Gen4TrainerMessages = require("src.import.Gen4TrainerMessages")
  local table_ = rematch and Gen4TrainerMessages.SCRIPT_TYPES_REMATCH
                 or Gen4TrainerMessages.SCRIPT_TYPES
  local id = trainerOnObject(ctx) or ctx.g4Trainer
  local row
  if not trainerIsDouble(ctx, id) then
    row = table_.singles
  elseif trainerBattlerIndex(ctx) == 0 then
    row = table_.doubles_first
  else
    row = table_.doubles_second
  end
  -- Written unconditionally, including the zeroes: the cartridge writes all
  -- three slots on every call and a script that read a stale one would branch
  -- on the previous trainer's answer.
  if preVar then setVar(ctx.save, preVar, row[1]) end
  if postVar then setVar(ctx.save, postVar, row[2]) end
  if notEnoughVar then setVar(ctx.save, notEnoughVar, row[3]) end
end

-- `printtrainerdialogue <trainer> <messageType>` -- the line itself, and the
-- command whose absence meant no trainer in Sinnoh ever said anything.
--
-- BOTH OPERANDS ARE VAR-OR-LITERAL here, which is the opposite of the command
-- above: `ScrCmd_PrintTrainerDialogue` takes both with `ScriptContext_GetVar`.
-- `scripts_battles.s` passes vars for both in the talk path and a LITERAL
-- message type in the approach path (`PrintTrainerDialogue VAR_0x8004,
-- TRMSG_PRE_BATTLE`), so a lowering that assumed either shape would break one
-- of the two ways every battle in the game starts.
--
-- The string is reached the same way `g4_message_bank` reaches one, through
-- `Gen4Text.label`, because the extractor wrote these 2,497 lines into `text`
-- under exactly those names along with every other bank.  The only thing the
-- new cache table adds is WHICH entry: `gen4_trainer_messages[trainer][type]`.
function Commands.g4_print_trainer_dialogue(ctx, trainer, messageType)
  local Gen4Text = require("src.import.Gen4Text")
  local Gen4TrainerMessages = require("src.import.Gen4TrainerMessages")
  local id = math.floor(valueOf(ctx, trainer) or 0)
  local kind = math.floor(valueOf(ctx, messageType) or 0)
  local data = ctx.game and ctx.game.data
  local rows = data and data.gen4_trainer_messages
  if not rows then
    Logger.warn("gen4 script: this cache has no trainer message index, so trainer %d says nothing (re-import to build it)", id)
    return
  end
  local row = rows[id]
  local entry = row and row[kind]
  if not entry then
    -- NOT AN ERROR, and the common case: 92 of the 928 trainers have no
    -- dialogue at all, and of the rest most carry three or four of the twenty
    -- types.  2,497 pairs exist out of 18,560 possible, so a miss here is what
    -- the cartridge does too -- `Trainer_LoadMessage` clears the string and
    -- prints an empty box.  Debug rather than warn, or every battle in the
    -- region logs.
    Logger.debug("gen4 script: trainer %d has no message of type %d",
                 id, kind)
    return
  end
  -- THE BANK IS THE CARTRIDGE'S: 617 on Platinum, 728 on HeartGold /
  -- SoulSilver (trainer_data.c, msg_0728). HGSS's gym trainers printed their
  -- own label, TEXT_B0617_00134, until this asked.
  local bank = (require("src.import.Gen4ScriptBands").family == "hgss") and 728
               or Gen4TrainerMessages.BANK
  -- Black / White: system bank 189 (RomExtractorGen5's index)
  if require("src.import.Gen4ScriptBands").family == "bw" then
    return Commands.show_text(ctx, ("TEXT_G5S_0189_%05d"):format(entry))
  end
  return Commands.show_text(ctx, Gen4Text.label(bank, entry))
end

-- `checkhastwoalivemons <destVar>` -- `Party_HasTwoAliveMons`, which is what
-- gates a double battle: you cannot be asked into one with a single Pokemon
-- standing.
function Commands.g4_check_two_alive(ctx, destVar)
  local alive = 0
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg and (mon.hp or 0) > 0 then alive = alive + 1 end
  end
  local value = (alive >= 2) and 1 or 0
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- `trainerbattle` is not an opcode on this cartridge; the spelling is kept
-- pointing at the real one so an older lowering cannot fall through the floor.
Commands.g4_trainer_battle = Commands.g4_start_battle

Commands.meta = Commands.meta or {}
Commands.meta.g4_start_battle = { foreground = true, blocking = true }

-- `getmovementtype <destVar> <object>` -- `MapObject_GetMovementType`, and
-- the operands are in THAT order: destination first (GetVarPointer), object
-- second (GetVar).
--
-- WAS A `pending` STUB filed against "the movement-script decoder", which was
-- the wrong dependency: the cartridge does not run a movement script to answer
-- this, it reads the field the object was spawned with, and the extractor has
-- written `movementType` onto every object def since the events stage was
-- built.
--
-- WHAT THE STUB COST, exactly: `scripts_battles.s` opens with
--
--     GetMovementType VAR_0x8001, VAR_LAST_TALKED
--     CallIfEq VAR_0x8001, MOVEMENT_TYPE_DISGUISE_SNOW,  Battles_RevealTrainer
--     CallIfEq VAR_0x8001, MOVEMENT_TYPE_DISGUISE_SAND,  Battles_RevealTrainer
--     CallIfEq VAR_0x8001, MOVEMENT_TYPE_DISGUISE_ROCK,  Battles_RevealTrainer
--     CallIfEq VAR_0x8001, MOVEMENT_TYPE_DISGUISE_GRASS, Battles_RevealTrainer
--
-- so with nothing written to VAR_0x8001 all four tests compared a stale var
-- and no disguised trainer in the region ever stood up.  NINE OBJECTS in the
-- cartridge carry a disguise movement type -- one snow, three sand, five rock,
-- none grass -- so this is nine trainers, countable rather than estimated, and
-- it is the whole of what the stub was costing.
--
-- `MOVEMENT_TYPE_NONE` IS 0, and is the cartridge's answer for an object that
-- is not on the map: it writes NONE first and overwrites only on a hit.  That
-- matters here because 0 is also the real movement type of 2,051 of Sinnoh's
-- objects, so "absent" and "stands still" are deliberately indistinguishable.
function Commands.g4_get_movement_type(ctx, destVar, objectId)
  local e = objectById(ctx, objectId)
  local def = e and e.def or defByLocalId(ctx, valueOf(ctx, objectId))
  local kind = def and tonumber(def.movementType) or 0
  if destVar then setVar(ctx.save, destVar, kind) end
end
-- ---------------------------------------------------------------------------
-- the shop
-- ---------------------------------------------------------------------------
--
-- A SINNOH MART'S STOCK IS DECIDED BY YOUR BADGE COUNT, not by the town.
-- `ScrCmd_PokeMartCommon` ignores its one operand entirely, counts the badges
-- in the save, turns that into a TIER, and then walks one shared table taking
-- every row whose `requiredBadges` is at or below it. Every ordinary Poke Mart
-- in the region sells the same list; what changes is how far down it goes.
--
-- The switch is the cartridge's, transcribed rather than smoothed -- note that
-- it is NOT `tier = badges` and not monotonic in the obvious way: zero badges
-- and one badge give different tiers, then the pairs 1/2, 3/4 and 5/6 share:
--
--     0 -> 1     1,2 -> 2     3,4 -> 3     5,6 -> 4     7 -> 5     8 -> 6
--
-- `constants.martCommon` is that table, already extracted: 19 rows of
-- `{ badges, item }`, which unlock 4 / 10 / 13 / 17 / 18 / 19 deep as the
-- tiers rise. Item 4 is the Poke Ball and 17 the Potion, and both are in the
-- first four -- which is the whole reason this had to be wired before anybody
-- could play past Jubilife.
local MART_TIER = { [0] = 1, 2, 2, 3, 3, 4, 4, 5, 6 }

local function martStock(ctx)
  local data = ctx.game and ctx.game.data
  local rows = data and data.constants and data.constants.martCommon
  if type(rows) ~= "table" then return nil end
  local badges = 0
  local held = ctx.save and (ctx.save.badges
                             or (ctx.save.player and ctx.save.player.badges))
  if type(held) == "table" then
    for _, has in pairs(held) do if has then badges = badges + 1 end end
  end
  local tier = MART_TIER[math.min(badges, 8)] or 1
  local stock = {}
  for _, row in ipairs(rows) do
    local need = tonumber(row.badges) or 1
    local item = row.item
    if tier >= need and item ~= nil and data.items and data.items[item] then
      stock[#stock + 1] = item
    end
  end
  return stock, badges, tier
end

function Commands.g4_pokemart(ctx, martId, kind)
  if kind == 'seal' then return Commands.g4_seal_mart(ctx, martId) end
  local stock, badges, tier
  if kind == 'specialty' then
    stock = ((ctx.game.data.constants or {}).martSpecialties or {})[valueOf(ctx, martId)]
  else stock, badges, tier = martStock(ctx) end
  if not (stock and stock[1]) then
    Logger.warn('gen4 shop: stock is absent for this counter; re-import the ROM')
    return
  end
  Logger.info('gen4 shop: %s counter, %d items', kind or 'common', #stock)
  local runner = ctx.runner
  local Screens = require("src.ui.Screens")
  Screens.push(ctx.game, "ShopMenu", stock, function()
    if runner then runner:resume() end
  end)
  if runner then runner:yield() end
end

Commands.meta = Commands.meta or {}
Commands.meta.g4_pokemart = { foreground = true, blocking = true }

function Commands.g4_heal_animation(ctx, count)
  local ow, runner = ctx.overworld, ctx.runner
  if not (ow and ow.startHealAnim and runner) then return end
  local ground = ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  local animation = ow:startHealAnim(function()
    if ground and ground.setHealingBalls then ground:setHealingBalls(0) end
    runner:resume()
  end)
  animation.gen4 = true
  animation.balls = math.max(0, math.min(6, tonumber(valueOf(ctx, count)) or #(ctx.save.party or {})))
  runner:yield()
end

function Commands.g4_check_flag_var(ctx, operand, dest)
  local key = ('FLAG_G4_%04X'):format(getVar(ctx.save,operand))
  setVar(ctx.save,dest,(ctx.save.flags or {})[key] and 1 or 0)
end

function Commands.g4_set_flag_var(ctx, operand)
  ctx.save.flags = ctx.save.flags or {}
  ctx.save.flags[('FLAG_G4_%04X'):format(getVar(ctx.save,operand))] = true
end

-- BLACK / WHITE's checkflag on a var (0x8002 / 0x8022: the hidden items'
-- and the gift scripts' "is this one already taken"): the flag the var names
function Commands.g4_bw_check_flag_var(ctx, operand)
  Commands.g4_check_flag(ctx, ('FLAG_G4_%04X'):format(getVar(ctx.save, operand) or 0))
end

function Commands.g4_clear_flag_var(ctx, operand)
  ctx.save.flags = ctx.save.flags or {}
  ctx.save.flags[('FLAG_G4_%04X'):format(getVar(ctx.save,operand))] = nil
end

function Commands.g4_open_bag(ctx, mode)
  local runner=ctx.runner
  ctx.g4SelectedItem=0
  local function finish(item)
    ctx.g4SelectedItem=tonumber(item) or 0
    if runner then runner:resume() end
  end
  require('src.ui.Screens').push(ctx.game,'BagMenu',{pick=true,
    pocket=tonumber(mode)==0 and 'ITEMS' or 'BERRIES',
    onPick=finish,onCancel=function() finish(0) end})
  if runner then runner:yield() end
end
function Commands.g4_selected_item(ctx,dest) setVar(ctx.save,dest,ctx.g4SelectedItem or 0) end
Commands.meta.g4_open_bag = { foreground = true, blocking = true }
function Commands.g4_pocket_has_items(ctx,pocket,dest)
  local found=false
  for id,count in pairs(ctx.save.inventory or {}) do
    local def=(ctx.game.data.items or {})[id]
    if count>0 and def and def.fieldPocket==valueOf(ctx,pocket) then found=true; break end
  end
  setVar(ctx.save,dest,found and 1 or 0)
end
function Commands.g4_berry(ctx,operation,operand)
  local B=require('src.world.Gen4BerryPatches')
  local patch=B.target(ctx)
  local value=0
  if operation=='getberrygrowthstage' then value=patch and patch.stage or 0
  elseif operation=='getberryitemid' then value=patch and patch.item or 0
  elseif operation=='getberrymulchtype' then value=patch and patch.mulch or 0
  elseif operation=='getberrymoisture' then
    local moisture=patch and patch.moisture or 0
    value=moisture==0 and 0 or moisture<=50 and 1 or 2
  elseif operation=='getberryyield' then value=patch and patch.yield or 0
  elseif operation=='setberrymulch' then
    local item=valueOf(ctx,operand)
    if patch and patch.stage==0 and item>=95 and item<=98 then patch.mulch=item end
    return
  elseif operation=='plantberry' then
    B.plant(ctx.game,patch,valueOf(ctx,operand))
    require('src.pokemon.Gen4GameRecords').increment(ctx.save,4) -- RECORD_BERRIES_PLANTED
    return
  elseif operation=='setberrywateringstate' then
    if patch and patch.stage>0 and patch.stage<5 then patch.moisture=100 end
    return
  elseif operation=='harvestberry' then
    ctx.lastCheck=B.harvest(ctx.game,patch)
    require('src.pokemon.Gen4GameRecords').score(ctx.save,0) -- TRAINER_SCORE_EVENT_BERRY_HARVESTED
    return
  else return end
  setVar(ctx.save,operand,value)
end
Commands.meta.g4_heal_animation = { foreground = true, blocking = true }

-- ---------------------------------------------------------------------------
-- THE NICKNAME PROMPT
-- ---------------------------------------------------------------------------

-- `openpokemonnamingscreen <slot> <destVar>`, from
-- ScrCmd_OpenPokemonNamingScreen. Five sites, and SANDGEM TOWN is one of them,
-- so this is main-path from the first hour: every gift Pokemon in Sinnoh was
-- handed over without ever being offered a name.
--
-- !! WHAT THE DESTINATION MEANS IS THE OPPOSITE OF THE GUESS. `returnCode` is
-- ZERO when the name CHANGED and ONE when it did not:
--
--     if (String_Compare(textInputStr, startingName) == 0) returnCode = 1;
--     if (returnCode == 0) sub_0203DF68(taskMan);   <- this is what writes it
--     if (dest != NULL) *dest = returnCode;
--
-- so the write happens only on the zero branch, and "1" is the answer for BOTH
-- "you typed the same thing" and "you backed out". Every call site compares
-- against 1 and skips its follow-up, which is the second statement: three of
-- them do `comparevartovalue 0x800C 1` then `callif` the "it is now called X"
-- line. Answering 0 by default would make all five announce a rename that
-- never happened.
--
-- THE SLOT IS ZERO-BASED, which is why the sites compute it as `getpartycount`
-- then `subvar 1` -- the member just handed over. Lua's party is one-based.
function Commands.g4_name_pokemon(ctx, slotArg, destVar)
  -- The safe answer first, so every early return below says "nothing was
  -- renamed" rather than leaving the register holding the last comparison.
  setVar(ctx.save, destVar, 1)

  local slot = valueOf(ctx, slotArg)
  local party = (ctx.save and ctx.save.party) or {}
  local mon = party[slot + 1]
  -- HGSS ScrCmd_NicknameInput: slot 255 is the BUG-CATCHING CONTEST's catch
  -- (contest->mon), not a party slot -- the judge's "Give a nickname to the
  -- SCYTHER you caught?" runs before BugContestAction 1 hands it over, and
  -- with no catch the command does nothing at all
  if slot == 255 then
    local BC = require("src.world.HgssBugContest").state(ctx.save)
    mon = BC and BC.caught or nil
  end
  if not mon then
    Logger.warn("gen4 naming: `openpokemonnamingscreen` asked for party slot "
                .. "%d, which is empty -- nothing was renamed", tonumber(slot) or -1)
    return
  end

  local data = ctx.game and ctx.game.data
  local def = data and data.pokemon and data.pokemon[mon.species]
  local speciesName = (def and def.name) or tostring(mon.species)
  -- An un-nicknamed Pokemon starts the screen on its SPECIES NAME, the way the
  -- cartridge seeds it -- Pokemon_GetValue(MON_DATA_NICKNAME) answers the
  -- species name when no nickname was set, so the comparison afterwards is
  -- against that and not against an empty string.
  local before = tostring(mon.nickname or "")
  if before == "" then before = speciesName end

  local runner = ctx.runner
  local Screens = require("src.ui.Screens")
  -- THE TITLE IS THE NAMING BANK'S OWN, entry 1 "{STRVAR_1}'s nickname?" --
  -- bank 422 on Platinum, 249 on HeartGold / SoulSilver -- with the species
  -- in the slot. Without it the screen asked "YOUR NAME?".
  local T = require("src.import.Gen4Text")
  local bank = (require("src.import.Gen4ScriptBands").family == "hgss") and 249 or 422
  local template = ctx.game.data and ctx.game.data.text and ctx.game.data.text[T.label(bank, 1)]
  -- Black / White: system bank 81, "{VAR1}'s nickname?" (the story bank of
  -- the same number is some town's lines)
  if require("src.import.Gen4ScriptBands").family == "bw" then
    template = ctx.game.data.text and ctx.game.data.text["TEXT_G5S_0081_00001"]
  end
  local title = type(template) == "string"
    and template:gsub("%s*{YESNO %d+}", ""):gsub("{STRVAR_1 [^}]*}", function() return speciesName end)
      :gsub("{VAR1}", function() return speciesName end)
    or nil
  Screens.push(ctx.game, "NamingScreen", {
    kind = "pokemon",
    title = title,
    species = mon.species,
    mon = mon,
    default = before,
    -- MON_NAME_LEN is 10 (constants/string.h), not the trainer's 7.
    maxLen = 10,
    onDone = function(typed)
      local name = tostring(typed or "")
      -- Confirming an empty keyboard is how the cartridge says "no nickname",
      -- and it lands on the species name rather than on nothing.
      if name == "" then name = speciesName end
      if name ~= before then
        mon.nickname = name
        setVar(ctx.save, destVar, 0)
      end
      if runner then runner:resume() end
    end,
  })
  if runner then runner:yield() end
end

Commands.meta.g4_name_pokemon = { foreground = true, blocking = true }

-- ---------------------------------------------------------------------------
-- THE FOUR IN-GAME TRADES
-- ---------------------------------------------------------------------------
--
-- Oreburgh City, Eterna City, Snowpoint City and Route 226. All five commands
-- were unlowered on all four maps, and OREBURGH IS THE THIRD TOWN. The record
-- and the names are src/import/Gen4Trades.lua; the script's shape, and why an
-- unwritten var here does more than fail, is in the lowering.

local function tradeRow(ctx, id)
  local data = ctx.game and ctx.game.data
  local list = data and data.constants and data.constants.gen4Trades
  if type(list) ~= "table" then return nil end
  local row = list[(tonumber(id) or -1) + 1]
  return type(row) == "table" and row or nil
end

-- `initnpctrade <id>` -- NPCTrade_Init. The cartridge allocates a block and
-- hangs it off the script manager; the id is the whole of what it needs to be
-- remembered, so that is what rides on the context -- the same lifetime
-- `g4StarterChoice` uses, and freed by `finishnpctrade` the same way
-- NPCTrade_Free frees the block.
function Commands.g4_trade_init(ctx, id)
  ctx.g4Trade = tonumber(id) or 0
  if not tradeRow(ctx, ctx.g4Trade) then
    Logger.warn("gen4 trade: `initnpctrade %d` ran, but this cache carries no "
                .. "`constants.gen4Trades` -- one more import writes it",
                ctx.g4Trade)
  end
end

function Commands.g4_trade_finish(ctx)
  ctx.g4Trade = nil
end

-- `getnpctradespecies` / `getnpctraderequestedspecies` -- what is on offer and
-- what they will only take for it. BOTH WRITE A VAR AND THE SECOND ONE IS
-- COMPARED AGAINST YOUR CHOICE, so leaving either unwritten decides the branch
-- rather than failing it. Zero is the answer when there is no row: a species
-- number of zero matches nothing in a party, so the trade is refused rather
-- than accepted against a Pokemon nobody checked.
local function tradeSpecies(ctx, destVar, key)
  local row = tradeRow(ctx, ctx.g4Trade)
  local value = tonumber(row and row[key]) or 0
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

function Commands.g4_trade_species(ctx, destVar)
  tradeSpecies(ctx, destVar, "species")
end

function Commands.g4_trade_requested(ctx, destVar)
  tradeSpecies(ctx, destVar, "request")
end

-- `openpartymenufortrade` -- FieldSystem_OpenPartyMenu_SelectForTrade and then
-- a pause. The slot is left on the context for `getselectedpartyslot`, which
-- is what the script reads it with; CANCELLING leaves PARTY_SLOT_NONE there,
-- and the scripts handle that already because it is what the stub answered for
-- as long as this menu did not exist.
function Commands.g4_open_party_for_trade(ctx)
  local runner = ctx.runner
  local Screens = require("src.ui.Screens")
  ctx.g4PartySlot = Gen4Commands.PARTY_SLOT_NONE
  Screens.push(ctx.game, "PartyMenu", {
    pickOnly = true,
    onSwitch = function(mon)
      if mon then
        for i, member in ipairs((ctx.save and ctx.save.party) or {}) do
          -- ZERO-BASED, because that is what getpartymonspecies and
          -- startnpctrade are handed straight afterwards.
          if member == mon then ctx.g4PartySlot = i - 1 break end
        end
      end
      if runner then runner:resume() end
    end,
  })
  if runner then runner:yield() end
end

Commands.meta.g4_open_party_for_trade = { foreground = true, blocking = true }

-- `startnpctrade <slot>` -- FieldTask_StartNPCTrade: build their Pokemon, swap
-- it for yours, and play the trade cutscene. The order is FieldTask_Process-
-- NPCTrade's: state 0 builds the Pokemon and puts it in the party
-- (NPCTrade_ReceiveMon), states 1-3 fade the field out and run the trade
-- sequence application, 4-5 bring the field back. So the swap below happens
-- first and then src/ui/Gen4TradeSequence.lua plays (send, tube, fly-by,
-- wormhole, arrival, reveal, receive -- the cartridge's seven phases, on the
-- cartridge's art), and the script resumes when it is over. HeartGold's
-- Task_NPCTrade (unk_0206793C.s) is the same seven states around overlay 71.
--
-- WHAT THE POKEMON IS, from NPCTrade_CreateMon:
--   * ITS LEVEL IS THE LEVEL OF THE ONE YOU GAVE. Not a stored level -- the
--     record has no level field at all -- `level` is read off the party member
--     being traded away. So a trade is always an even swap in levels, which is
--     also why these four are worth doing at any point in the game.
--   * the nickname and the OT name are bank 370's, and `hasNickname` is TRUE,
--     so the traded Pokemon keeps the name the cartridge gave it.
--   * the six IVs, the held item, the OT id, OT gender and language are the
--     record's; the five contest stats are extracted and not modelled here.
--   * `GF_ASSERT(!Pokemon_IsShiny(mon))` -- the personality/OT-id pairs are
--     chosen so none of the four can be shiny, which is worth knowing before
--     somebody "fixes" a reroll in.
function Commands.g4_trade_start(ctx, slotArg)
  local row = tradeRow(ctx, ctx.g4Trade)
  local slot = (valueOf(ctx, slotArg) or 0) + 1
  local party = (ctx.save or {}).party or {}
  local given = party[slot]
  local data = ctx.game and ctx.game.data
  if not (row and given and row.species and data) then
    Logger.warn("gen4 trade: nothing to swap -- trade %s, slot %d",
                tostring(ctx.g4Trade), slot)
    return
  end

  local ok, mon = pcall(function()
    return require("src.pokemon.Pokemon").new(data, row.species,
                                              given.level or 5)
  end)
  if not (ok and type(mon) == "table") then
    Logger.warn("gen4 trade: could not build species %s", tostring(row.species))
    return
  end
  mon.nickname = row.nickname
  mon.ot = row.otName
  mon.otId = row.otId
  mon.otGender = row.otGender
  -- npc_trade.c: the record's language -- Foppa's Magikarp is German
  if tonumber(row.language) then mon.language = tonumber(row.language) end
  -- boosted exp, and the Name Rater refuses to touch it -- the same flag the
  -- Hoenn trades set, so the two generations' traded Pokemon behave alike.
  mon.traded = true
  if row.item and row.item ~= 0 then mon.item = row.item end

  -- THE IVS LAND BECAUSE Data.lua ALREADY PUTS GEN 4 SPECIES ON THE GEN 3
  -- STAT MODEL -- it fills `evYield` from `evYields`, which is the presence
  -- test `Stats.isGen3` makes -- so a Gen 4 mon carries `ivs` at 0..31 and the
  -- record's six are in the same range. Without that they would be DVs at
  -- 0..15 and these would be nonsense.
  if type(row.ivs) == "table" and type(mon.ivs) == "table" then
    local Stats = require("src.pokemon.Stats")
    for i, key in ipairs(Stats.ORDER_GEN3) do
      if row.ivs[i] then mon.ivs[key] = row.ivs[i] end
    end
  end
  -- ...and the record's PERSONALITY, which fixes the nature, the ability slot,
  -- the gender and the shininess (NPCTrade's Pokemon_InitWith... takes it
  -- whole); applySeed recomputes those and the stats from it and the IVs.
  if row.personality then mon.hp = nil end
  pcall(require("src.pokemon.Pokemon").applySeed, data, mon,
        { personality = row.personality, ivs = mon.ivs })
  if mon.stats and not mon.hp then mon.hp = mon.stats.hp end

  -- The one you were given takes the SLOT of the one you gave:
  -- Party_AddPokemonBySlotIndex (both decomps' npc_trade.c) overwrites
  -- party->pokemon[slot] in place. Then the dex is told.
  party[slot] = mon
  local save = ctx.save
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.owned = save.pokedex.owned or {}
  save.pokedex.seen[mon.species] = true
  save.pokedex.owned[mon.species] = true
  require('src.pokemon.Gen4Forms').record(ctx.game,mon.species,mon)
  -- The slot is spent: a second `getselectedpartyslot` after a swap must not
  -- name a member that has moved.
  ctx.g4PartySlot = nil

  -- THE CUTSCENE, with the two Pokemon NPCTrade_FillAnimationTemplate hands
  -- it: yours as it left, theirs as it arrived, the other trainer's name for
  -- "X will be sent to Y." -- and the time of day for the sky.
  local runner = ctx.runner
  local game = ctx.game
  if game and game.stack and data.gen4_trade_art then
    local okS, err = pcall(function()
      require("src.ui.Screens").push(game, "Gen4TradeSequence", {
        sending = given, receiving = mon, otName = row.otName,
        onDone = function() if runner then runner:resume() end end,
      })
    end)
    if okS then
      if runner then runner:yield() end
    else
      Logger.warn("gen4 trade: the trade cutscene would not start: %s", tostring(err))
    end
  end
end

Commands.meta.g4_trade_start = { foreground = true, blocking = true }

-- ---------------------------------------------------------------------------
-- CHAPTER THREE -- Oreburgh to Eterna
-- ---------------------------------------------------------------------------
--
-- Measured the same way the opening and chapter two were: walk every script
-- block reachable from the Oreburgh gate through Jubilife, Floaroma, the
-- Windworks and Eterna Forest to Gardenia's gym -- 191 entry points, 610
-- blocks, 5,230 instructions -- and ask the lowering about each row. 176
-- unlowered rows across 42 commands, which is a list rather than a survey.
-- The ones below are the ones that change what a player sees.

-- `SetBlackOutWarpId(warpId)` -- FieldOverworldState's blackout destination,
-- an INDEX into a heal-location table this port has not extracted for Gen 4.
-- One site in the whole cartridge (the Eterna cycle shop).
--
-- RECORDED RATHER THAN APPLIED, deliberately: `OverworldState:healPoint`
-- answers from `save.lastHeal`, which a Pokemon Centre already writes, so
-- guessing a map from an index would be strictly worse than the answer the
-- port already has. The id is kept so a later heal-location stage has the
-- script's own value to join against instead of having to re-derive it.
function Commands.g4_set_blackout_warp(ctx, warpId)
  local save = ctx.save
  if not save then return end
  save.gen4BlackoutWarpId = math.floor(valueOf(ctx, warpId) or 0)
  -- ...and applied now that the field has the spawn table (Platinum's
  -- sHealLocations / HGSS's sSpawnMaps, `field.healLocations`): the row's
  -- blackout half, at the counter facing up, as Gen4Blackout.noteEntry writes
  local data = ctx.game and ctx.game.data
  for _, row in ipairs((data and data.field and data.field.healLocations) or {}) do
    local b = row.blackOut
    if tonumber(row.index) == save.gen4BlackoutWarpId and b and b.map and b.x and b.y then
      save.lastHeal = { map = b.map, x = b.x, y = b.y, facing = "up", home = (row.index == 0) or nil }
      break
    end
  end
end

-- `getitempocket <item> <destVar>` -- `Item_LoadParam(item,
-- ITEM_PARAM_FIELD_POCKET)`. 46 sites, all of them in `scripts_common`: this
-- is the "you put the X away in the Y POCKET" line every pickup in the region
-- runs through, so leaving it unlowered left a VAR-WRITER silent and the
-- pocket name behind it printing whatever the last command had left.
--
-- The value is the item row's own `fieldPocket`, which the extractor already
-- writes on all 446 rows (0 ITEMS, 1 MEDICINE, 2 POKE_BALLS, 3 TM_HM,
-- 4 BERRIES, 5 MAIL, 6 BATTLE_ITEMS, 7 KEY_ITEMS -- counted off the cache,
-- not assumed).
function Commands.g4_item_pocket(ctx, item, destVar)
  local data = ctx.game and ctx.game.data
  local id = itemKey(data, math.floor(valueOf(ctx, item) or 0))
  local def = data and data.items and data.items[id]
  local pocket = tonumber(def and (def.bwPocket or def.fieldPocket)) or 0
  if destVar then setVar(ctx.save, destVar, pocket) end
  setResult(ctx, pocket)
end

-- `checkitemisplate <item> <destVar>` -- `item >= ITEM_FLAME_PLATE and
-- item <= ITEM_IRON_PLATE`.
--
-- DERIVED FROM THE NAMES, NOT FROM TWO HARD-CODED IDS. The cartridge's plates
-- are one contiguous run, so the run's ends are what the test needs -- and the
-- cache already carries every item's name, so asking which rows are called
-- "... Plate" reproduces the pair without a second table to keep in step.
-- Built once and kept on the module.
function Gen4Commands.plateRange(data)
  if Gen4Commands._plateLow then
    return Gen4Commands._plateLow, Gen4Commands._plateHigh
  end
  local low, high
  for id, def in pairs((data and data.items) or {}) do
    local n = tonumber(id) or tonumber(def and def.id)
    local name = def and def.name
    if n and type(name) == "string" and name:match("%sPlate$") then
      if not low or n < low then low = n end
      if not high or n > high then high = n end
    end
  end
  -- A cartridge that does not spell them "... Plate" (German Platinum's are
  -- "...tafel") falls back to the cartridge's own pair, ITEM_FLAME_PLATE (298)
  -- .. ITEM_IRON_PLATE (313), the same ids on Platinum, HGSS and the US scan.
  if not low then low, high = 298, 313 end
  Gen4Commands._plateLow = low or 0
  Gen4Commands._plateHigh = high or -1
  return Gen4Commands._plateLow, Gen4Commands._plateHigh
end

function Commands.g4_item_is_plate(ctx, item, destVar)
  local id = math.floor(valueOf(ctx, item) or 0)
  local low, high = Gen4Commands.plateRange(ctx.game and ctx.game.data)
  local yes = (id >= low and id <= high) and 1 or 0
  if destVar then setVar(ctx.save, destVar, yes) end
  setResult(ctx, yes)
end

-- `isitemtmhm <item> <destVar>` -- `Item_IsTMHM`, AND IT IS AN ID RANGE:
--
--     if (item >= ITEM_TM01 && item <= ITEM_HM08) return TRUE;
--
-- not a pocket lookup, which is the obvious alternative and a different test.
-- They were compared rather than assumed: over the cache's 446 items, the id
-- range and `fieldPocket == TM_HM` select the same 100 rows -- 92 TMs plus 8
-- HMs -- with nothing in one and not the other, and the ends are clean (327 is
-- Razor Fang, 428 the Explorer Kit). So either spelling is right on this
-- cartridge; the cartridge's own is the range, so that is what this is.
--
-- THIS IS THE HIGHEST-REACH SCRIPT COMMAND IN THE GAME THAT WAS MISSING.
-- `scripts_visible_items.s` and `scripts_hidden_items.s` are shared bands with
-- 329 and 262 objects behind them -- 591 item balls and hidden items across
-- Sinnoh -- and both end their pickup the same way:
--
--     IsItemTMHM VAR_0x8004, VAR_RESULT
--     GoToIfEq VAR_RESULT, TRUE,  ..._PlayerFoundTMHM
--     GoToIfEq VAR_RESULT, FALSE, ..._PlayerFoundItem
--     End
--
-- Unlowered, VAR_RESULT was never written, so BOTH branches tested whatever
-- the previous script had left there. When that is neither 1 nor 0 -- which it
-- usually is -- neither jump is taken and the script falls into `End`: the item
-- is added (AddItem has already run) and the player is told NOTHING. Six
-- hundred pickups that work and say nothing is not a missing message, it is a
-- game that feels broken, and it is one `GetVarPointer` away.
--
-- Derived from the names like `plateRange` above, for the same reason: the TMs
-- and HMs are one contiguous run, the cache already carries every name, and a
-- second hard-coded pair of ids is a second thing to keep in step.
function Gen4Commands.tmhmRange(data)
  if Gen4Commands._tmhmLow then
    return Gen4Commands._tmhmLow, Gen4Commands._tmhmHigh
  end
  local low, high = nil, nil
  for id, def in pairs((data and data.items) or {}) do
    local n = tonumber(id) or tonumber(def and def.id)
    local name = def and def.name
    -- `^TM%d` and `^HM%d` rather than the pocket, so this stays the id-range
    -- test the cartridge performs even if an item is ever re-pocketed -- OR the
    -- TM_HM pocket, because the names are the cartridge's language: German
    -- Platinum's HMs are "VM01".."VM08", and the names alone would end the
    -- run at TM92.  On the US cache both select the same 100 rows.
    if n and type(name) == "string"
       and (name:match("^TM%d") or name:match("^HM%d") or def.pocket == "TM_HM") then
      if not low or n < low then low = n end
      if not high or n > high then high = n end
    end
  end
  Gen4Commands._tmhmLow = low or 0
  Gen4Commands._tmhmHigh = high or -1
  return Gen4Commands._tmhmLow, Gen4Commands._tmhmHigh
end

function Commands.g4_item_is_tmhm(ctx, item, destVar)
  local id = math.floor(valueOf(ctx, item) or 0)
  local low, high = Gen4Commands.tmhmRange(ctx.game and ctx.game.data)
  local yes = (id >= low and id <= high) and 1 or 0
  if destVar then setVar(ctx.save, destVar, yes) end
  setResult(ctx, yes)
end

-- `trysetunusedcollectedorbflag <item>` -- and pokeplatinum's own name says
-- what it is worth: the flag it sets is read by nothing on the cartridge.
--
--     if (item == ITEM_ADAMANT_ORB || item == ITEM_LUSTROUS_ORB) {
--         Underground_SetUnusedCollectedOrbFlag(underground);
--     }
--
-- Transcribed anyway, with the condition, because it is two lines and because
-- a row that is lowered and does nothing is honest while a row that is not
-- lowered warns on every item pickup in the game -- this sits in
-- `VisibleItems_GiveItem`, which all 329 of them run. The ids are resolved by
-- NAME for the same reason the range above is.
function Commands.g4_try_set_collected_orb_flag(ctx, item)
  local data = ctx.game and ctx.game.data
  local id = math.floor(valueOf(ctx, item) or 0)
  local def = data and data.items and data.items[itemKey(data, id)]
  local name = def and def.name
  if type(name) ~= "string" then return end
  -- by name on an English cache, else by the cartridge's ids (ITEM_ADAMANT_ORB
  -- 135, ITEM_LUSTROUS_ORB 136): a German cache spells them its own way
  if name == "Adamant Orb" or name == "Lustrous Orb" or id == 135 or id == 136 then
    local ug = ctx.save and ctx.save.underground
    if not ug and ctx.save then ug = {}; ctx.save.underground = ug end
    if ug then ug.collectedOrb = true end
  end
end

-- `savetvsegmenthiddenitem <item>` -- files a "breaking news" TV segment about
-- what the player just dug up. There is no TV broadcast system in this engine
-- at all (the `tv_broadcast` band is unlowered entire), so there is nothing to
-- file it with.
--
-- A no-op rather than a `pending`, and the distinction matters: `pending` says
-- "this drives something that is not built", which invites building it. This
-- says the segment is recorded nowhere and nothing would read it if it were.
-- It is lowered because it sits in `HiddenItems_AddItem`, which all 262 hidden
-- items run, and an unlowered row there warns on every one of them.
-- (retired in favour of `g4_save_tv_segment` below, which both TV rows now
-- lower to -- see the note there.)

-- `survivepoison <destVar> <slot>` -- `Pokemon_TrySurvivePoison`, in full:
--
--     if (status & (TOXIC | POISON) && HP == 1) {
--         status = NONE;
--         return TRUE;
--     }
--     return FALSE;
--
-- Poisoned AND at exactly 1 HP: cure it and say so. Anything else is FALSE.
--
-- THE RULE BEHIND IT is that Sinnoh's field poison cannot faint a Pokemon --
-- `Pokemon_DoPoisonDamage` is `if (hp > 1) hp--` -- so arriving at 1 HP is the
-- end of the road and this is what lets go of the status. The engine applies
-- that rule and prints the line itself, in `OverworldState:applyFieldPoison`,
-- because this port does its field-poison messages inline rather than handing
-- off to common script 3. This handler is the half for anything that DOES hand
-- off -- the script band is lowered and reachable, and a row that wrote nothing
-- would make the loop print the survived line for every mon in the party or
-- for none of them, depending on what the last script left in VAR_RESULT.
--
-- Exactly 1, not <= 1: a fainted mon is at 0 and is not cured. `MON_DATA_HP`
-- is the current HP, and the cartridge compares it to the literal 1.
function Commands.g4_survive_poison(ctx, destVar, slot)
  local index = math.floor(valueOf(ctx, slot) or 0)
  local mon = ((ctx.save and ctx.save.party) or {})[index + 1]
  local poisoned = mon and (mon.status == "PSN" or mon.status == "TOX")
  local value = 0
  if poisoned and (mon.hp or 0) == 1 then
    mon.status = nil
    value = 1
  end
  if destVar then setVar(ctx.save, destVar, value) end
end

-- `hatchegg` -- `FieldSystem_HatchEgg`: the FIRST egg in the party
-- (`Party_GetFirstEgg`), then the hatch scene. The common script around it has
-- already shown "Oh?" and faded out, so this is only the hatch and the reveal.
--
-- Through `OverworldState:hatchEgg`, which is the engine's own hatch lifted out
-- of `stepEggs` by this pass for the purpose -- the met-level-zero stamp, the
-- Poketch memory, the Gen 4 origin stamp, the 120 base happiness and the
-- reveal box are thirty lines that must not exist twice.
--
-- NOTE WHICH DOOR IS USED IN PRACTICE: this engine hatches inline, on the step
-- that runs the counter out, so `CommonScript_HatchEgg` is never dispatched
-- and this handler does not normally run. It is here so that the row is not a
-- warning on a path that could be reached, and so the two doors cannot drift.
function Commands.g4_hatch_egg(ctx)
  local ow = ctx.overworld
  if not (ow and ow.hatchEgg) then return end
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if mon.isEgg then return ow:hatchEgg(mon) end
  end
  Logger.debug("gen4 script: `hatchegg` ran with no egg in the party")
end
Commands.meta.g4_hatch_egg = { foreground = true, blocking = true }

-- `getpartycount <destVar>` -- `Party_GetCurrentCount`, EGGS INCLUDED, which
-- is why `countpartynoneggs` exists beside it and is a different number.
function Commands.g4_party_count(ctx, destVar)
  local n = #((ctx.save and ctx.save.party) or {})
  if destVar then setVar(ctx.save, destVar, n) end
  setResult(ctx, n)
end

-- scrcmd_party.c: excluded slot is zero-based and resolved through vars.
-- Box Pokemon count regardless of stored HP; eggs never count on either side.
function Commands.g4_party_alive_except(ctx,destVar,excluded)
  local n=0;local skip=math.floor(valueOf(ctx,excluded) or -1)
  for i,mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if i-1~=skip and not mon.isEgg and (tonumber(mon.hp) or 0)>0 then n=n+1 end
  end
  setVar(ctx.save,destVar,n)
end
function Commands.g4_party_alive_and_boxes(ctx,destVar)
  local n=0
  for _,mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg and (tonumber(mon.hp) or 0)>0 then n=n+1 end
  end
  for _,box in pairs((ctx.save and ctx.save.boxes) or {}) do
    for _,mon in pairs(box) do
      if type(mon)=='table' and (tonumber(mon.species) or 0)>0 and not mon.isEgg then n=n+1 end
    end
  end
  setVar(ctx.save,destVar,n)
end

function Commands.g4_party_non_eggs(ctx, destVar)
  local n = 0
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg then n = n + 1 end
  end
  if destVar then setVar(ctx.save, destVar, n) end
  setResult(ctx, n)
end

-- ------------------------------------------------------------- the Poketch --
--
-- `enablepoketch` and `registerpoketchapp <appID>`. `g4_poketch_registered`
-- has been able to ANSWER this question since the battle pass -- it reads
-- `save.poketch.registered` -- and nothing in the port had ever written it, so
-- every app read as unregistered for ever. The Jubilife scene that hands the
-- watch over is four of the five `registerpoketchapp` sites on the critical
-- path.
function Commands.g4_enable_poketch(ctx)
  local save = ctx.save
  if not save then return end
  save.poketch = save.poketch or {}
  save.poketch.enabled = true
  -- The watch arrives WITH THE DIGITAL WATCH ALREADY ON IT (app 0); the
  -- cartridge registers it in the same handler rather than from the script.
  save.poketch.registered = save.poketch.registered or {}
  save.poketch.registered[0] = true
end

function Commands.g4_register_poketch_app(ctx, appId)
  local save = ctx.save
  if not save then return end
  local id = math.floor(valueOf(ctx, appId) or 0)
  save.poketch = save.poketch or {}
  save.poketch.registered = save.poketch.registered or {}
  save.poketch.registered[id] = true
end

-- ------------------------------------------------------- the player avatar --
--
-- `setplayerstate <bits>` is `PlayerAvatar_TurnOnRequestStateBit` and its
-- operand is a BITMASK, not an enum -- `generated/player_transitions.txt`
-- names ten entries and two of them are called `PLAYER_TRANSITION_x0008` and
-- `x0200`, which is the table telling you its own numbering: 1 WALKING,
-- 2 CYCLING, 4 SURFING, 8, 0x10 WATER_BERRIES, 0x20 FISHING, 0x40 POKETCH,
-- 0x80 SAVE, 0x100 HEALING, 0x200.
--
-- Only two values are ever passed in the whole cartridge: WALKING (6 sites)
-- and HEALING (3). WALKING is a DISMOUNT and is the one that matters -- a
-- script that puts you indoors expects you off the bike. HEALING is the nurse's
-- pose, which this port draws no differently.
Gen4Commands.PLAYER_STATE = { WALKING = 1, CYCLING = 2, SURFING = 4 }

-- The bike song follows a scripted mount or dismount (ScrCmd_SetPlayerBike
-- sets / clears the SEQ_BICYCLE override, pokeplatinum scrcmd.c).
local function bikeMusicAfter(ctx, was)
  local save = ctx.save
  if not (save and ctx.game) or (not was) == (not save.onBike) then return end
  local ok, Music = pcall(require, "src.core.Music")
  if ok and Music.setBike then pcall(Music.setBike, ctx.game.data, save.onBike) end
end

function Commands.g4_player_state(ctx, state)
  local bits = math.floor(tonumber(state) or 0)
  local save = ctx.save
  if not save then return end
  local wasOnBike = save.onBike
  if bits % 2 == 1 then            -- WALKING
    save.onBike = false
  elseif math.floor(bits / 2) % 2 == 1 then  -- CYCLING
    save.onBike = true
  end
  bikeMusicAfter(ctx, wasOnBike)
  -- HGSS: PLAYER_TRANSITION_ROCKET (1 << 10) puts on the Rocket disguise
  -- (the Radio Tower), WALKING takes it off; the sheet follows
  -- (Player:refreshForm)
  if require("src.import.Gen4ScriptBands").family == "hgss" then
    local was = save.hgssRocketCostume
    if math.floor(bits / 1024) % 2 == 1 then save.hgssRocketCostume = true
    elseif bits % 2 == 1 then save.hgssRocketCostume = nil end
    local p = ctx.overworld and ctx.overworld.player
    if was ~= save.hgssRocketCostume and p and p.refreshForm and ctx.game then
      p.walkId = nil
      pcall(p.refreshForm, p, ctx.game.data)
    end
  end
end
-- RocketCostumeFlagAction <on> / RocketCostumeFlagCheck <dest>: the save's
-- own costume flag, which the Radio Tower's guards read
function Commands.g4_rocket_costume_flag(ctx, on)
  if ctx.save then ctx.save.hgssRocketCostumeFlag = (tonumber(on) or 0) ~= 0 or nil end
end
function Commands.g4_rocket_costume_check(ctx, destVar)
  setVar(ctx.save, destVar, (ctx.save and ctx.save.hgssRocketCostumeFlag) and 1 or 0)
end

-- `changeplayerstate` is `PlayerAvatar_RequestChangeState` -- the LATCH that
-- applies whatever bit the previous command set. This port applies it in the
-- setter, so the latch has nothing left to do.

-- `setplayerbike <onOff>` -- one TRUE site and six FALSE ones in the whole
-- cartridge, because the bike itself is a bag item; this is the scripted
-- mount and dismount.
--
-- SAFE ON A CACHE WITH NO BIKE ART: `Player:spriteFor` reads
-- `self.onBike and self.bikeSprite` and falls through to the walking sheet
-- when the second is nil, so a Sinnoh rider walks rather than drawing nothing.
function Commands.g4_player_bike(ctx, on)
  local save = ctx.save
  if not save then return end
  local was = save.onBike
  save.onBike = (math.floor(tonumber(on) or 0) ~= 0)
  bikeMusicAfter(ctx, was)
end

-- `getdayofweek <destVar>` -- `GetDayOfWeek()`, 0 Sunday .. 6 Saturday, which
-- is the same origin `os.date("*t").wday` uses once its 1-based count is
-- shifted. The one site on the critical path is the Windworks' weekday check.
function Commands.g4_day_of_week(ctx, destVar)
  local wday = tonumber(os.date("*t").wday) or 1
  local value = (wday - 1) % 7
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- ------------------------------------------------------------ a tag battle --
--
-- `starttagbattle <partnerTrainer> <enemy1> <enemy2>`. The same
-- `Encounter_NewVsTrainer` as `starttrainerbattle`, with one difference that
-- is the whole point of the command: the ALLY is named by an operand instead
-- of being read from FLAG_HAS_PARTNER.
--
-- THE PARTNER FIGHTS. Their trainer record's own team stands in the
-- player's right-hand slot and picks its moves for itself (src/battle/
-- AllyAI.lua); the player chooses for the left one only. Their Pokemon are
-- theirs -- no experience, nothing written back -- and the fight is lost only
-- when neither side has anybody left, which is the cartridge's multi battle.
--
-- An ally this cache has no team for falls back to the old fight: both of
-- the player's flanks from their own party.
--
-- The alternative was a `pending()` stub, and that is strictly worse: the
-- Jubilife scene reads `CheckWonBattle` immediately afterwards and branches to
-- its blackout on FALSE, so an unlowered battle does not merely skip a fight,
-- it blacks the player out in the middle of a cutscene.
-- the partner trainer's team as an ally record, or nil
function Gen4Commands.allyFor(ctx, allyId)
  local game = ctx.game
  local trainers = game and game.data and game.data.trainers
  local rec = allyId ~= 0 and trainers and trainers[allyId]
  if not (rec and type(rec.parties) == "table" and type(rec.parties[1]) == "table" and rec.parties[1][1]) then
    return nil
  end
  local BattleState = require("src.battle.BattleState")
  local ok, party = pcall(BattleState.buildTrainerParty, game, allyId, 1, rec.parties[1])
  if not (ok and type(party) == "table" and party[1]) then return nil end
  return { party = party, name = rec.name, trainer = allyId, pic = rec.pic }
end

-- ScrCmd_StartTrainerBattle: with FLAG_HAS_PARTNER set (an escort -- Cheryl
-- in Eterna Forest, Riley on Iron Island, Mira in Wayward Cave, Marley on
-- Victory Road, Buck on Stark Mountain), VAR_PARTNER_TRAINER_ID fights at the
-- player's side
Gen4Commands.VAR_PARTNER_TRAINER_ID = 0x403F
function Gen4Commands.escortAlly(ctx)
  local Follower = require("src.world.Gen4Follower")
  if not (Follower.hasPartner and Follower.hasPartner(ctx.save)) then return nil end
  local id = math.floor(tonumber(getVar(ctx.save, Gen4Commands.VAR_PARTNER_TRAINER_ID)) or 0)
  if id == 0 then return nil end
  local ally = Gen4Commands.allyFor(ctx, id)
  if ally then ally.escort = true end
  return ally
end

-- Party_HealAllMembers, which FieldTask_Encounter runs after any battle not
-- lost while a partner walks with the player
function Gen4Commands.healParty(save)
  local Pokemon = require("src.pokemon.Pokemon")
  local Party = require("src.pokemon.Party")
  for _, mon in ipairs(save and save.party or {}) do
    if type(mon) == "table" and mon.stats and not Party.isEgg(mon) then pcall(Pokemon.heal, mon) end
  end
end

function Commands.g4_start_tag_battle(ctx, partner, enemy1, enemy2)
  local allyId = math.floor(valueOf(ctx, partner) or 0)
  local a, b = math.floor(valueOf(ctx, enemy1) or 0),
               math.floor(valueOf(ctx, enemy2) or 0)
  local ally = Gen4Commands.allyFor(ctx, allyId)
  if not ally and allyId ~= 0 and not Gen4Commands._saidTagBattle then
    Gen4Commands._saidTagBattle = true
    Logger.info("gen4 battle: tag partner %d has no team in this cache -- both of "
                .. "the player's flanks are their own party", allyId)
  end
  if not ally then return Commands.g4_start_battle(ctx, a, b) end
  return Commands.g4_start_battle(ctx, a, b, { ally = ally })
end

Commands.meta = Commands.meta or {}
Commands.meta.g4_start_tag_battle = { foreground = true, blocking = true }

-- `giveegg <species> <eggGiver>` -- Cynthia's Togepi at Eterna City is the one
-- on the critical path, and it is missable rather than blocking.
--
-- `Egg_CreateEgg(egg, species, 1, trainer, 3, specialMetLoc)`: level 1, and the
-- second operand is only the MET LOCATION the memo prints, which this port does
-- not keep for Gen 4 -- so it is read and dropped rather than stored somewhere
-- nothing reads. `give_pokemon`'s own `egg` option does the rest: no nickname
-- prompt, an egg-step counter from the species, and no met level until it
-- hatches.
function Commands.g4_give_egg(ctx, species, giver)
  local id = math.floor(valueOf(ctx, species) or 0)
  local mons = ctx.game and ctx.game.data and ctx.game.data.pokemon
  if id == 0 or not (mons and mons[id]) then
    Logger.warn("gen4 script: `giveegg` names species %s, which this dataset "
                .. "does not carry -- no egg is given", tostring(id))
    return
  end
  if #((ctx.save and ctx.save.party) or {}) >= 6 then
    Logger.info("gen4 script: `giveegg` with a full party -- the cartridge "
                .. "drops it too (Party_GetCurrentCount < MAX_PARTY_SIZE)")
    return
  end
  local _ = valueOf(ctx, giver)
  Commands.give_pokemon(ctx, id, 1, true, { egg = true })
end

-- ScrCmd_GiveTogepiEgg (field/scrcmd_pokemon_misc.c): an Egg of Togepi,
-- level 1, with MOVE_EXTRASENSORY (326) in the first empty move slot -- the
-- last one if all four are taken -- and nothing at all with a full party.
function Commands.g4_give_togepi_egg(ctx)
  local party = (ctx.save and ctx.save.party) or {}
  if #party >= 6 then return end
  local before = #party
  Commands.g4_give_egg(ctx, 175, 0)
  local mon = ctx.save and ctx.save.party and ctx.save.party[before + 1]
  if not mon then return end
  mon.moves = mon.moves or {}
  local mdef = ctx.game and ctx.game.data and ctx.game.data.moves and ctx.game.data.moves[326]
  local slot = { id = 326, pp = mdef and mdef.pp or 0 }
  if #mon.moves < 4 then mon.moves[#mon.moves + 1] = slot else mon.moves[4] = slot end
end

-- `startlegendarybattle <species> <level>` -- `Encounter_NewVsSpeciesAtLevel`
-- with the legendary flag on. NOT only legendaries: the one site on the
-- critical path is the DRIFLOON that appears at the Valley Windworks on
-- Fridays, which uses the same command because the command is really "a wild
-- battle against a named species at a named level that cannot be fled".
--
-- The port already carries `opts.legendary`, which `start_battle` passes to
-- the battle and `pushBattleTransition` reads, so this is the existing wild
-- path with the flag set rather than a new kind of battle.
function Commands.g4_legendary_battle(ctx, species, level)
  local id = math.floor(valueOf(ctx, species) or 0)
  local lv = math.max(math.floor(valueOf(ctx, level) or 1), 1)
  local mons = ctx.game and ctx.game.data and ctx.game.data.pokemon
  if id == 0 or not (mons and mons[id]) then
    Logger.warn("gen4 script: `startlegendarybattle` names species %s, which "
                .. "this dataset does not carry -- the battle is skipped",
                tostring(id))
    return
  end
  Commands.start_battle(ctx, "wild", id, lv, { legendary = true })
end

Commands.meta = Commands.meta or {}
Commands.meta.g4_legendary_battle = { foreground = true, blocking = true }

-- ---------------------------------------------------------------------------
-- THE OPENING, WALKED AGAIN AND WIDER
-- ---------------------------------------------------------------------------
--
-- The first opening measurement used a narrow map set and reported zero.
-- Walking the same route with the houses, Rowan's lab and the common-script
-- archive included -- 101 entry points, 484 blocks -- finds 132 rows, which is
-- what a wider net was always going to do. The item-pocket work above accounts
-- for most of them; these are the rest, and the first is the game's FIRST
-- BATTLE.

-- `startfirstbattle <trainer>` -- `Encounter_NewVsFirstBattle`. Six sites, all
-- of them Route 201: Barry's challenge the moment you have a starter, one site
-- per starter per gender.
--
-- IT IS AN ORDINARY TRAINER BATTLE WITH ONE RULE CHANGED: losing it does not
-- black you out. The script says so itself -- `CheckWonBattle` then
-- `Route201_RivalWonLetsGoHome`, a branch that only exists because the story
-- carries on either way. The port already has that rule as `opts.canLose`
-- (the Battle Tower's), and `afterBattle` reads it before the blackout, so
-- this is `g4_start_battle` with the flag set rather than a second battle
-- path.
function Commands.g4_start_first_battle(ctx, trainer)
  return Commands.g4_start_battle(ctx, trainer, 0, { canLose = true })
end

-- `givepokedex` -- `Pokedex_ObtainPokedex`. Rowan hands it over in his lab and
-- NOTHING in this port was told: `Flags.hasPokedex` reads
-- `EVENT_GOT_POKEDEX`/`ENGINE_POKEDEX` off the save's flag table and gates the
-- start menu's Pokedex row and the main menu's continue panel, and no Gen 4
-- script sets either. So the dex row stayed missing for the whole game.
--
-- `ENGINE_POKEDEX` is the port's own generation-neutral spelling, which is why
-- it is the one written here rather than Johto's event name.
function Commands.g4_give_pokedex(ctx)
  local save = ctx.save
  if not save then return end
  save.flags = save.flags or {}
  save.flags.ENGINE_POKEDEX = true
  save.pokedex = save.pokedex or { seen = {}, owned = {} }
end

-- `getlocaldexseencount <destVar>` / `checklocaldexcompleted <destVar>` -- the
-- SINNOH dex, which is a filtered view of the national one and needs the
-- region's own species list to count. The port keeps `save.pokedex.seen` and
-- `.owned` whole rather than per-region, so the honest answer is the count of
-- what has actually been seen, which is right whenever the player has not yet
-- left Sinnoh -- and that is every script that asks.
-- THE SET, SORTED, because two callers want different things from it: the
-- counts below want its size and the News Press wants to pick one member.
-- Walking the dex twice in two places is how the same question gets two
-- answers, so the walk lives here once.
--
-- Sorted rather than in `pairs` order so a pick made from it is reproducible
-- for a given RNG value -- an unordered pick would name a different species
-- run to run on identical input, and a diagnostic nobody can reproduce is not
-- a diagnostic.
local function dexIDs(ctx,field,regional)
  local dex=(ctx.save and ctx.save.pokedex) or {}
  local seen={}
  for key,flag in pairs(dex[field] or {}) do
    if flag==true or (type(flag)=='number' and flag>0) then
      local id=speciesNumber({species=key})
      if id>=1 and id<=493 then seen[id]=true end
    end
  end
  local region={}
  if regional then
    local orders=ctx.game and ctx.game.data and ctx.game.data.gen4_dex
    for _,id in ipairs(orders and orders.orders and orders.orders.sinnoh or {}) do region[tonumber(id) or id]=true end
  end
  local out={}
  for id in pairs(seen) do
    if not regional or region[id] then out[#out+1]=id end
  end
  table.sort(out)
  return out
end

local function dexCount(ctx,field,regional,completion)
  local ids=dexIDs(ctx,field,regional)
  local excluded={ [151]=true,[249]=true,[250]=true,[251]=true,[385]=true,[386]=true,
    [489]=true,[490]=true,[491]=true,[492]=true,[493]=true }
  local count=0
  for _,id in ipairs(ids) do
    if (not completion or regional or not excluded[id]) then count=count+1 end
  end
  return count
end

function Commands.g4_dex_seen_count(ctx,destVar)
  setVar(ctx.save,destVar,dexCount(ctx,'seen',true,false))
end
function Commands.g4_dex_complete(ctx,destVar,national)
  local count=dexCount(ctx,national and 'owned' or 'seen',not national,true)
  setVar(ctx.save,destVar,count>=(national and 482 or 210) and 1 or 0)
end
-- THE POKEMON NEWS PRESS at Solaceon.  Three rows: pick a species, remember a
-- deadline, read the deadline back.
--
-- `getrandomseenspecies` was on `g4_no_feature`, which writes 0 -- and 0 is
-- SPECIES_NONE, so the press named a blank.  This is the goods-PC fault in a
-- different room: the feature it was declining is PRESENT (the port keeps
-- `save.pokedex.seen`, and `g4_dex_seen_count` has filtered it by the Sinnoh
-- dex since before this pass), so the zero was not an absence, it was a wrong
-- answer the script then printed.
--
-- THE DEFAULT IS THE PART TO COPY CAREFULLY.  pret writes it BEFORE the loop:
--
--     u16 seenSpeciesCount = Pokedex_CountSeen_Local(pokedex);
--     u16 random = LCRNG_Next() % seenSpeciesCount;
--     *destVar = SPECIES_PIKACHU;
--     for (u16 species = 1, i = 0; species <= NATIONAL_DEX_COUNT; species++) {
--         if (Pokedex_HasSeenSpecies(pokedex, species) == TRUE
--             && Pokemon_SinnohDexNumber(species) != FALSE) { ... }
--     }
--
-- so a dex with nothing eligible in it still answers a real Pokemon.  Note
-- that the cartridge counts with one predicate and iterates with another: if
-- those ever disagree the loop falls through and Pikachu is what comes out.
-- Answering Pikachu rather than nothing is therefore the cartridge's
-- behaviour on the empty case AND on the inconsistent case, and it is the one
-- species id this command can produce that the player has not necessarily
-- seen.
local NEWS_PRESS_DEFAULT_SPECIES = 25 -- SPECIES_PIKACHU

function Commands.g4_news_press_species(ctx,destVar)
  local ids=dexIDs(ctx,'seen',true)
  local pick=NEWS_PRESS_DEFAULT_SPECIES
  if #ids>0 then
    local r=(love and love.math and love.math.random) or math.random
    pick=ids[r(1,#ids)]
  end
  setVar(ctx.save,destVar,pick)
  setResult(ctx,pick)
end

function Commands.g4_news_press_deadline(ctx,mode,operand)
  local Daily=require("src.script.Gen4Daily")
  if mode=='set' then
    local days=math.floor(valueOf(ctx,operand) or 0)
    if days<0 then days=0 elseif days>0xFFFF then days=0xFFFF end
    setVar(ctx.save,Daily.NEWS_PRESS_DEADLINE_VAR,days)
    return
  end
  -- `get`: the deadline is a system var like any other, so there is no
  -- separate store to read -- which is why a save written before this pass
  -- answers zero rather than nil.
  setVar(ctx.save,operand,Daily.deadline(ctx.save))
end

function Commands.g4_dex_caught_count(ctx,destVar,national)
  setVar(ctx.save,destVar,dexCount(ctx,'owned',not national,false))
end
function Commands.g4_unown_forms_seen(ctx,destVar)
  setVar(ctx.save,destVar,#require('src.pokemon.Gen4Forms').seen(ctx.save.pokedex,201))
end
function Commands.g4_enable_dex_form_detection(ctx)
  ctx.save.pokedex=ctx.save.pokedex or {seen={},owned={}}
  ctx.save.pokedex.canDetectForms=true
end

-- `setstepflag` / `clearstepflag` -- `SystemFlag_SetStep`, the bit that stops
-- the step counter (and with it egg hatching and Poketch pedometer ticks)
-- while a cutscene is running. This port counts no steps during a script
-- because the script owns the input gate, so the bit has nothing to gate.

-- One operand (the slot); the species is derived rather than passed.
function Commands.g4_buffer_counterpart_starter_article(ctx, slot)
  local mine = Gen4Commands.playerStarter(ctx.save)
  local id = Gen4Commands.counterpartStarter(mine)
  return Commands.g4_buffer(ctx, slot, "speciesArticle", id)
end

-- `startdestroyobstacleanimation <kind> <destVar>` -- Roark's Rock Smash
-- demonstration in the Oreburgh Mine and the boulder-clearing flourish
-- elsewhere. PRESENTATION ONLY: the rock is actually removed by the
-- `RemoveObject` on the very next row, which has always been lowered, so the
-- path opens with or without the animation. The destination var is the
-- completion flag, not a handle. overlay006/ov6_02248948.c initializes it
-- to zero and writes ONE after the effect finishes. Roark polls it every
-- frame after removing the rock. Until the native effect is implemented,
-- report completion immediately; leaving zero strands that polling loop.
function Commands.g4_destroy_obstacle_anim(ctx, kind, destVar)
  -- HGSS ScrCmd_560 (ov02_0224E074): the var is zeroed, the obstacle's 3D
  -- animation plays (src/world/Gen4FieldFx.lua) and its task writes 1 when it
  -- ends; with no art in this cache the var is written at once, as before
  local save = ctx.save
  if destVar then setVar(save, destVar, 0) end
  local okFx, started = pcall(function()
    return require("src.world.Gen4FieldFx").start(ctx.overworld, valueOf(ctx, kind), function()
      if destVar then setVar(save, destVar, 1) end
    end)
  end)
  if not (okFx and started) and destVar then setVar(save, destVar, 1) end
end

-- ---------------------------------------------------------------------------
-- `scripts_field_moves.s` -- the other shared script
-- ---------------------------------------------------------------------------
--
-- One file, seventeen entries, and every use of Cut, Rock Smash, Strength,
-- Rock Climb, Surf, Waterfall, Defog and Flash in Sinnoh goes through it --
-- twice over, because each has a "press A on the obstacle" path and a "use it
-- from the party menu" path. Nine of its commands were unlowered, 23 uses.

-- THE THREE FIELD-MOVE FLAGS, in one handler because they are one opcode shape
-- three times over and the cartridge's own difference between them is which
-- flag they touch.
--
-- Sub-functions: 0 CLEAR_ACTIVE, 1 SET_ACTIVE, 2 CHECK_ACTIVE -- and only
-- CHECK carries a destination word, which is why these three are variable
-- length and why the decoder used to stop the walk here (four scripts ended
-- early; see `Gen4ScriptOps.VARIABLE_SPEC`). All six uses in the cartridge are
-- in this one file: SET twice for Strength, once each for Flash and Defog, and
-- CHECK twice for Strength. CLEAR is never used from a script -- the C clears
-- these on its own -- but the opcode defines it, so it is answered.
--
-- THE FLAGS LIVE ON THE SAVE, which is where the cartridge keeps them
-- (`VarsFlags`, via `SystemFlag_HandleStrengthActive` and friends) and, more
-- to the point, is the only way CHECK can read what SET wrote. One store, one
-- source of truth.
--
-- STRENGTH IS ALSO MIRRORED ONTO THE OVERWORLD, deliberately and one way.
-- `OverworldState:tryPushBoulder` reads `self.strengthActive` and nothing
-- else -- it is Gen 1/2's spelling of the same bit, and the comment there
-- records that Hoenn's boulders could not be pushed for exactly this reason:
-- the flag was in the save and the pusher never looked. A Gen 4 save flag that
-- the pusher did not consult would be the same bug a third time, so the mirror
-- is written here rather than hoped for. The save stays the truth; the field is
-- a view of it.
--
-- FLASH AND DEFOG HAVE NO CONSUMER YET, and saying so is the point.
-- `PaletteFX.daytimeFor(mapDef, hour, flashUsed)` takes the flag as its third
-- argument and **has no callers at all** -- nothing in `src/` or `tools/` calls
-- it -- so the dark-cave path it was written for is unwired at the renderer
-- end. Setting the flag is the half that can be done from here; lighting the
-- cave is a separate job, and it will find the flag already correct.
local function fieldMoveFlags(save)
  if not save then return nil end
  save.gen4FieldMoveFlags = save.gen4FieldMoveFlags or {}
  return save.gen4FieldMoveFlags
end

function Commands.g4_field_move_flag(ctx, which, func, destVar)
  local Ops = require("src.import.Gen4ScriptOps")
  local FUNC = Ops.FIELD_MOVE_FUNC
  local store = fieldMoveFlags(ctx.save)
  local f = math.floor(tonumber(func) or -1)
  if f == FUNC.SET_ACTIVE or f == FUNC.CLEAR_ACTIVE then
    local on = (f == FUNC.SET_ACTIVE) or nil
    if store then store[which] = on end
    if which == "strength" and ctx.overworld then
      ctx.overworld.strengthActive = on and true or false
    end
  elseif f == FUNC.CHECK_ACTIVE then
    -- ONLY the destination var, which is what the C writes. The comparison
    -- register is deliberately left alone: `GoToIfEq` expands to an explicit
    -- `CompareVar` followed by `GoToIf 1`, so the branch reads the var rather
    -- than the register, and writing both would be inventing a side effect the
    -- cartridge does not have.
    local value = (store and store[which]) and 1 or 0
    if destVar then setVar(ctx.save, destVar, value) end
  else
    -- `ScrCmd_DoStrengthFunc`'s default arm is `GF_ASSERT(FALSE)`, so a fourth
    -- value is not something to guess at.
    Logger.warn("gen4 script: field-move flag %q got sub-function %d, which is "
                .. "none of CLEAR(0)/SET(1)/CHECK(2)", tostring(which), f)
  end
end

-- ---------------------------------------------------------------------------
-- SAVING
-- ---------------------------------------------------------------------------
--
-- Twelve handlers for one dialogue.  `src/script/Gen4Save.lua` holds the model
-- -- what a save type means, how `fullSaveRequired` is derived, what the extra
-- save blocks become -- and these rows are only the wiring.
--
-- THE WRITE IS NOT HERE.  `src/script/ScriptSave.lua` has it, shared with Gen
-- 3's `special SaveGame`, so the engine has one save path and two
-- presentations of it, which is the arrangement the cartridge has too: its
-- script wraps `SaveData_Save`.

-- `checksavetype <destVar>`.  Four answers, all of them in Gen4Save.
-- !! A COMMAND MUST NOT RETURN ITS ANSWER. ScriptRunner:exec reads a number
-- a command returns as the ROW TO JUMP TO, so `return kind` sent every
-- `Common_SaveGame` back to row `kind` of its script -- the Battle Tower's
-- attendant greeted the player again instead of saving, for ever. The answer
-- goes in the var; the function returns nothing.
function Commands.g4_check_save_type(ctx, destVar)
  local Gen4Save = require("src.script.Gen4Save")
  local kind = Gen4Save.typeFor(ctx.save)
  if destVar then setVar(ctx.save, destVar, kind) end
end

-- `trysavegame <destVar>` -- 1 when the bytes landed, 0 otherwise, which is
-- `FieldSystem_Save`'s `SaveData_Save(...) == SAVE_RESULT_OK`.
--
-- `Gen4Save.markSaved` is the C's success arm: dataExists becomes true,
-- isNewGameData false and fullSaveRequired false.  It runs AFTER the write, so
-- a failed write leaves the next save still reporting FULL_SAVE -- the
-- cartridge's behaviour, and the safe direction to be wrong in.
--
-- It also runs after the write for a second reason: `Game:writeSave` captures
-- the overworld into the save table on its way past, so a stamp taken before
-- it would be a stamp of a table that is about to change.
function Commands.g4_try_save_game(ctx, destVar)
  local wrote = require("src.script.ScriptSave").write(ctx, "gen4")
  if wrote then require("src.script.Gen4Save").markSaved(ctx.save) end
  local answer = wrote and 1 or 0
  if destVar then setVar(ctx.save, destVar, answer) end
  Logger.info("gen4 save: script save %s", wrote and "written" or "declined")
end

-- `storesaveresult <var>` -- hand the result back to whatever started the
-- script.  The cartridge writes through a pointer passed to
-- `ScriptManager_Start`, and `include/script_manager.h` says of it that it is
-- "only defined if ScrCmd_StoreSaveResult is called", so a script started
-- without one simply does not get the write.
--
-- `ctx.saveResultOut` is this port's pointer: whoever starts the save script
-- sets it to a function and reads what it is given.  Nothing sets it yet --
-- the START menu's SAVE row still runs the engine's own flow -- so the value
-- is also left on the context, which is where a C-side caller would look.
function Commands.g4_store_save_result(ctx, var)
  local value = valueOf(ctx, var) or 0
  ctx.gen4SaveResult = value
  if type(ctx.saveResultOut) == "function" then
    local ok, err = pcall(ctx.saveResultOut, value)
    if not ok then
      Logger.warn("gen4 save: the save-result sink raised (%s)", tostring(err))
    end
  end
end

-- `showsavingicon` / `hidesavingicon` -- `Window_AddWaitDial` and
-- `DestroyWaitDial`.  The dial is a sprite this port does not have yet, so the
-- flag is kept and the renderer has something true to read when it does; the
-- write it brackets is synchronous here, so there is no frame in which a
-- player could see it anyway.
function Commands.g4_saving_icon(ctx, on)
  local want = (tonumber(on) or 0) ~= 0
  ctx.gen4SavingIcon = want or nil
  if ctx.overworld then ctx.overworld.gen4SavingIcon = want or nil end
end

-- `waitabpresstime <frames>` -- A or B, or the timeout, whichever comes first
-- (`ScriptContext_DecrementABPressTimer`).  Var-or-literal, because the C
-- reads it with `ScriptContext_GetVar`.
--
-- The 30-frame hold on "<player> saved the game." is the only use in this
-- file, and the difference between this and a plain wait is whether an
-- impatient player can skip it.
function Commands.g4_wait_ab_press_time(ctx, frames)
  local left = math.floor(tonumber(valueOf(ctx, frames)) or 0)
  if left <= 0 then return end
  local runner = ctx.runner
  if not runner then return end
  local input = ctx.game and ctx.game.input
  runner.waitingCheck = function()
    if input and input.wasPressed
       and (input:wasPressed("a") or input:wasPressed("b")) then
      return true
    end
    left = left - 1
    return left <= 0
  end
  runner:yield()
end

-- `opensaveinfo` / `closesaveinfo` -- the panel the player reads before
-- answering.  Built from the cartridge's own bank-534 labels by
-- `Gen4Save.infoPanel` and drawn by `OverworldState:drawUI`.
function Commands.g4_save_info(ctx, on)
  local want = (tonumber(on) or 0) ~= 0
  if not want then
    ctx.gen4SaveInfo = nil
    if ctx.overworld then ctx.overworld.gen4SaveInfo = nil end
    return
  end
  local ok, panel = pcall(require("src.script.Gen4Save").infoPanel,
                          ctx.game, ctx.save)
  if not ok then
    Logger.warn("gen4 save: the save-info panel could not be built (%s)",
                tostring(panel))
    return
  end
  ctx.gen4SaveInfo = panel
  if ctx.overworld then ctx.overworld.gen4SaveInfo = panel end
end

-- 0x258 / 0x259 -- the player's save pose, begun as a task and ended.
--
-- `ov5_021E0F54` RETURNS NULL UNLESS THE PLAYER IS WALKING, so a save from a
-- bicycle or from the water poses nothing at all, and `ov5_021E0FC0` returns
-- immediately on a NULL task so the close is a no-op in exactly those cases.
-- That guard is the behaviour, not an implementation detail: it is why saving
-- on a bike does not drop you off it.
--
-- There is no save-pose sprite for Dawn or the boy in this port yet -- the
-- same reason their sprint frames are deferred until the 3D work lands -- so
-- what this does is record the pose the renderer should be drawing.  The guard
-- is honoured anyway, because a flag that is set in cases the cartridge never
-- sets it in would be a wrong flag rather than an unrendered one.
function Commands.g4_save_pose(ctx, on)
  local ow = ctx.overworld
  if not ow then return end
  if (tonumber(on) or 0) == 0 then
    ow.gen4SavePose = nil
    return
  end
  local onBike = ctx.save and ctx.save.onBike
  local surfing = ow.player and ow.player.surfing
  if onBike or surfing then return end
  ow.gen4SavePose = true
end

-- `saveextradata` / `checkismiscsaveinit` -- the Frontier-records and
-- battle-video sectors, and the flag that says they have been laid down once.
function Commands.g4_save_extra_data(ctx)
  require("src.script.Gen4Save").initMiscSave(ctx.save)
end

function Commands.g4_misc_save_init(ctx, destVar)
  local init = require("src.script.Gen4Save").miscSaveInit(ctx.save)
  local value = init and 1 or 0
  if destVar then setVar(ctx.save, destVar, value) end
end

-- ---------------------------------------------------------------------------
-- THE PC
-- ---------------------------------------------------------------------------

-- `checkishalloffamecorrupted <destVar>` -- the C loads the Hall of Fame block
-- and answers TRUE only for `LOAD_RESULT_CORRUPT`, which is a failed checksum
-- on a save sector.
--
-- THIS ENGINE HAS NO SECTOR TO FAIL.  The Hall of Fame is `save.hallOfFame`,
-- a list inside the one serialised save table, and `SaveData.validate` has
-- already run over it by the time any script can ask -- a malformed entry is
-- repaired or dropped on load, not left to be discovered here.  So the honest
-- answer is FALSE, and that is not a convenience: answering TRUE would send
-- the script to `CommonScript_HallOfFameDataCorrupted` and tell the player
-- their records are damaged when they are not.
--
-- A list that is ABSENT is not corrupt either -- it is a player who has not
-- entered the Hall of Fame, and the menu row that reaches this is behind
-- FLAG_GAME_COMPLETED, so that case cannot arise from the cartridge's own
-- path.
function Commands.g4_hall_of_fame_corrupted(ctx, destVar)
  if destVar then setVar(ctx.save, destVar, 0) end
  setResult(ctx, 0)
end

-- `openpchalloffamescreen` -- the post-game browser for recorded Hall of Fame
-- teams, opened from the PC menu once FLAG_GAME_COMPLETED is set.
--
-- `pending` rather than a no-op, and the distinction is the one
-- `g4_save_tv_segment` draws from the other side: a no-op says "there is
-- nothing to do and nothing would read it", and that is false here.  The data
-- exists -- `Commands.hall_of_fame` has been appending `{species, level,
-- nickname}` rows to `save.hallOfFame` all along -- and what is missing is a
-- screen to read them back.  `src/ui/HallOfFame.lua` is the INDUCTION
-- ceremony: it walks `save.party`, the live team, and has no notion of
-- browsing a record. So this says the screen is unbuilt and leaves the data
-- where a screen will find it.
--
-- The script carries on into `ReturnToField` and back to the PC menu, so the
-- row answers and the player is returned rather than stranded.
-- ...built now: src/ui/Gen4PcHallOfFame.lua, Platinum's and HGSS's browser.
-- The script waits on it, as the cartridge's ScriptContext_Pause does.
function Commands.g4_open_hall_of_fame(ctx)
  local game = ctx.game
  local Screen = require("src.ui.Gen4PcHallOfFame")
  if not (game and game.stack and Screen.available(game)) then return end
  local runner = ctx.runner
  game.stack:push(Screen.new(game, { onDone = function() if runner then runner:resume() end end }))
  if runner then runner:yield() end
end
Commands.meta.g4_open_hall_of_fame = { foreground = true, blocking = true }

-- `givetrap <trapID> <unused> <destVar>` and
-- `givesphere <type> <size> <destVar>` -- the Underground inventory, and the
-- only two of its eight `scripts_common.s` holes that write real state.
--
-- ONE HANDLER, because they are one operation on two 40-slot inventories:
-- `Underground_TryAddTrap` and `_TryAddSphere` differ in which array they
-- search for their zero sentinel and whether a second operand rides along.
-- Writing them twice would be the recurring bug in its favourite shape, and
-- the cap is the part that must not be spelled twice.
--
-- THE DESTINATION VAR IS THE POINT.  Both cartridge handlers end
-- `*destVar = ...TryAdd...(...)`, and every call site follows with a `gotoif`
-- on it -- so the var is not a courtesy, it is the branch.  `valueOf` on the
-- value operands because the cartridge reads both with
-- `ScriptContext_GetVar`: var-or-literal.
function Commands.g4_underground_give(ctx, kind, a, b, destVar)
  local UG = require("src.world.Gen4Underground")
  local ok
  if kind == "sphere" then
    ok = UG.addSphere(ctx.save, valueOf(ctx, a), valueOf(ctx, b))
  elseif kind == "goodPC" then
    -- `sendgoodtopc`'s middle operand is `u16 unused` too, so this reads the
    -- same shape as a trap and drops the same operand.
    ok = UG.addGoodToPC(ctx.save, valueOf(ctx, a))
  else
    -- `givetrap`'s middle operand is `u16 unused` in pokeplatinum; it is read
    -- off the stream and dropped, which is why it is accepted and ignored here
    -- rather than left out of the row.
    ok = UG.addTrap(ctx.save, valueOf(ctx, a))
  end
  local answer = ok and 1 or 0
  if destVar then setVar(ctx.save, destVar, answer) end
  setResult(ctx, answer)
end

-- `checkhasroomforgoodsinpc` -- the QUESTION half of the goods PC, and
-- sixteen of that inventory's seventeen script uses.
--
-- It was on `g4_no_feature`, which writes 0 -- and 0 here means "no room", so
-- every one of those sixteen told the player their PC was full on a save where
-- it holds nothing. An absent feature answering "no" is honest; a present one
-- answering "no" is not.
--
-- `Underground_IsRoomForGoodsInPC(underground, unused)` returns TRUE on the
-- first free slot and never looks at its second argument. Both operands are
-- carried here for the family's sake and both are dropped, which is what the
-- cartridge does with them.
function Commands.g4_underground_room(ctx, kind, _a, _b, destVar)
  local UG = require("src.world.Gen4Underground")
  local room = (kind == "goodsPC") and UG.roomInGoodsPC(ctx.save) or false
  local answer = room and 1 or 0
  if destVar then setVar(ctx.save, destVar, answer) end
  setResult(ctx, answer)
end

-- `opensealcapsuleeditor` -- `CapsuleMenu_StartFieldTask`, the screen where a
-- Ball Capsule's seals are arranged.
--
-- `pending` rather than a no-op, for the reason the Hall of Fame row above
-- states: a no-op claims there is nothing to do, and that is false -- there is a
-- whole screen to build.  Unlike the Hall of Fame there is no data waiting
-- either, which is why `countuniquesealsinsealcase` lowers onto
-- `g4_no_feature` rather than counting something.
Commands.g4_open_seal_capsule_editor = pending("g4_open_seal_capsule_editor",
  "the Ball Capsule seal editor (this port has no seal state at all, which is "
  .. "also why the seal count answers zero)")

-- `savetvsegment*` -- ONE ROW FOR BOTH, which is the point of the change that
-- introduced it.  There is no TV broadcast system in this engine at all, so a
-- segment is recorded nowhere and nothing would read it if it were. That is
-- one fact about the port, and it was being stated in two places.
--
-- A no-op rather than a `pending`: `pending` says "this drives something that
-- is not built", which invites building it. These are lowered because they sit
-- in paths everything runs through -- `HiddenItems_AddItem` on all 262 hidden
-- items, and the PC's storage menu on every visit -- and an unlowered row
-- there warns on every one.
--
-- The segment's NAME is carried so the row is readable in a trace and so a
-- future TV system has the call sites already naming themselves.
function Commands.g4_save_tv_segment(_ctx, _segment, _operand) end

-- 0x0C3 AND 0x0C4, WHICH ARE THE SAME FUNCTION BYTE FOR BYTE in pokeplatinum:
-- both set the overworld weather to OVERWORLD_WEATHER_CLEAR and re-apply it.
-- The script uses one after Flash and the other after Defog, which is the only
-- thing separating them.
--
-- A DARK CAVE AND A FOGGY ROUTE ARE THE SAME MECHANISM ON THIS CARTRIDGE -- an
-- overworld weather state -- so lighting a cave and blowing fog away are one
-- operation. That is why Flash clears *weather* here, which looks wrong until
-- you notice Platinum has no separate darkness concept (Gen 2 bakes darkness
-- into the palette instead, which is what this engine was built expecting).
--
-- AND IT IS READ BACK BY `g4_overworld_weather`, which is the half that makes
-- this worth writing: that command answered from the MAP's weather byte and
-- said so, on the grounds that nothing wrote a saved value. Something does
-- now, so the getter consults it first -- otherwise Defog would clear the fog
-- and the very next `getoverworldweather` would report fog, which is the
-- asymmetry that comment was worried about.
-- ...AND IT HAS TO CLEAR WHAT IS ON SCREEN, not only what the getter reports.
--
-- `applyMapWeather` recomputes the substitution from the persistent field-move
-- flag on every map load, which is the cartridge's own arrangement -- the flag
-- is what makes a lit cave stay lit through the next doorway. But `0C3` and
-- `0C4` run on the map the player is standing on, right after
-- `DoFlashFunc SET_ACTIVE`, and the whole point is that the cave lights up
-- NOW. Setting only the getter's field would have left the darkness drawn
-- until the next load: Flash would have reported success, said its line, and
-- changed nothing the player could see -- which is the fault this pass exists
-- to fix, reintroduced one step further along.
function Commands.g4_clear_overworld_weather(ctx)
  if ctx.save then
    ctx.save.gen4WeatherCleared = true
    ctx.save.gen4WeatherActive = 0
  end
  if ctx.overworld then ctx.overworld.gen4WeatherCleared = true end
end

-- `playhmcutin <slot>` -- nine uses, one in every HM path there is, and the
-- cartridge BLOCKS on it: `ScriptContext_Pause(ctx,
-- ScriptContext_WaitForHMCutInFinished)`.
--
-- Played through `Gen3FieldMove.show`, which is the field-move sweep this
-- engine already has -- the mon's front sprite raised over a coloured band
-- and taken away again. The module is named for the generation it was written
-- for; the beat is not generation-specific.
--
-- IT IS A STAND-IN AND NOT PARITY, stated plainly: Platinum's `HMCutIn` is its
-- own composition on the DS screen and includes the player's sprite (it takes
-- `PlayerAvatar_GetGender`). What is faithful here is the blocking beat and the
-- picture of the Pokemon doing the move; what is not is the layout. Showing
-- Hoenn's sweep is a visible stand-in, which is the kind that gets corrected;
-- showing nothing leaves the script's pause with no reason to exist, which is
-- the kind that does not.
--
-- `show` returns false when there is no picture to draw -- no mon in the slot,
-- or a cache with no front sprite for it -- and then this does nothing rather
-- than blocking on a screen that would draw nothing.
function Commands.g4_hm_cut_in(ctx, slot)
  local game = ctx.game
  if not (game and game.stack) then return end
  local index = math.floor(valueOf(ctx, slot) or 0)
  local mon = ((ctx.save and ctx.save.party) or {})[index + 1]
  if not mon then
    Logger.debug("gen4 script: `playhmcutin` names party slot %d, which is empty",
                 index)
    return
  end
  -- PLATINUM: its own cut-in, HMCutIn_StartTask (src/world/Gen4HMCutIn.lua),
  -- when this cache carries field_cutin's art (gen4_pt_field_fx)
  if require("src.import.Gen4ScriptBands").family ~= "hgss"
     and require("src.world.Gen4HMCutIn").show(game, mon, nil) then
    return
  end
  local Gen3FieldMove = require("src.world.Gen3FieldMove")
  Gen3FieldMove.show(game, mon, nil)
end
Commands.meta.g4_hm_cut_in = { foreground = true, blocking = true }

-- THE THREE THAT MOVE THE PLAYER. Each takes the party slot of the Pokemon
-- doing it and starts a field task the cartridge does not wait for -- the
-- script ends and the task finishes the motion.
--
-- WHY THESE DO NOT PRINT ANYTHING, which is the trap. The script has already
-- printed its own line and closed the box before it gets here:
--
--     Message FieldMoves_Text_PokemonUsedSurf
--     CloseMessage
--     UseSurf VAR_0x8004
--
-- so a handler modelled on the Gen 1-3 mount -- which pushes a TextBox saying
-- "<MON> used SURF!" and rides its fade -- would print the same line twice.
-- That is why this is a separate, smaller path rather than a call into the two
-- inline mounts in `OverworldController` (one around a textbox, one on a
-- force-surf tile): those are the same STATE reached through a different beat.
-- PLATINUM'S MON-RIDE CUT-IN: FieldTask_UseSurf / _UseWaterfall start with
-- NewMonRideCutIn (MonRideTask_Init sets playCutIn TRUE), the HMCutIn task the
-- field-move scripts' PlayHMCutIn plays (src/world/Gen4HMCutIn.lua); the task
-- goes on when it is finished. True when the cut-in is up and `again` will run
-- the command once more after it.
local function ptRideCutInFirst(ctx, slot, again)
  if ctx.__afterRideCutIn then return false end
  if require("src.import.Gen4ScriptBands").family == "hgss" then return false end
  local index = math.floor(tonumber(valueOf(ctx, slot)) or 0)
  local mon = ((ctx.save and ctx.save.party) or {})[index + 1]
  if not (mon and ctx.game) then return false end
  local copy = setmetatable({ __afterRideCutIn = true }, { __index = ctx })
  local ok, shown = pcall(require("src.world.Gen4HMCutIn").show, ctx.game, mon, function() again(copy, slot) end)
  return ok and shown or false
end

function Commands.g4_use_surf(ctx, slot)
  local ow = ctx.overworld
  local p = ow and ow.player
  if not p then return end
  if ptRideCutInFirst(ctx, slot, Commands.g4_use_surf) then return end
  -- ScrCmd_UseSurf clears the Poke Radar chain (scrcmd.c)
  if ow.gen4Radar and ow.gen4Radar.active and ow.gen4RadarEnd then pcall(ow.gen4RadarEnd, ow) end
  -- on a Distortion World surface the water ahead is the platform's own
  if ow.dwSurface then
    require("src.world.Gen4DistSurface").surfMount(ow)
    local okMusic, Music = pcall(require, "src.core.Music")
    if okMusic and ctx.game then Music.setSurfing(ctx.game.data, true) end
    return
  end
  p.surfing = true
  -- SURFING REPLACES CYCLING (PlayerAvatar state): the bike is put away
  local gsave = ctx.game and ctx.game.save
  if gsave and gsave.onBike then
    gsave.onBike, gsave.bikeKind = false, nil
    local okB, MusicB = pcall(require, "src.core.Music")
    if okB and MusicB.setBike then pcall(MusicB.setBike, ctx.game.data, false) end
  end
  -- Being on the water means being at the water's level; the step onto it is
  -- otherwise refused by the rule that keeps a walker out of the sea.
  if ow.map and ow.map.cellElevation then
    local fx, fy = p:facingCell()
    p.elevation = ow.map:cellElevation(fx, fy) or p.elevation
  end
  if ow.syncSurfingPikachu then ow:syncSurfingPikachu() end
  local okMusic, Music = pcall(require, "src.core.Music")
  if okMusic and ctx.game then Music.setSurfing(ctx.game.data, true) end
  -- ...AND ONTO THE WATER: `UseSurf`'s task hops the player onto the tile
  -- ahead (PlayerAvatar_SetSurfMount...).  Setting the flag alone left them
  -- standing on the bank as a surfer (HM sweep, Route 218).
  if ow.map and ow.map.isWaterCell then
    local fx, fy = p:facingCell()
    if ow.map:isWaterCell(fx, fy) then
      if ow.stepForwardOrCrossEdge then pcall(ow.stepForwardOrCrossEdge, ow, p.facing)
      elseif ow.scriptMove then ow:scriptMove(p, p.facing, 1) end
    end
  end
end

-- `usewaterfall <slot>` -- the climb itself already exists for Hoenn
-- (`OverworldState:gen3UseWaterfall`), driven from pressing A on the fall. The
-- Sinnoh script reaches the same motion by a different door, so this hands off
-- to whichever of those the overworld exposes rather than walking the player
-- by hand -- the cell-by-cell climb is the overworld's business and a second
-- copy of it here is how the two end up disagreeing about where you surface.
-- PLATINUM'S CLIMBS, Waterfall and Rock Climb alike: the player is carried
-- straight across the run of climb tiles ahead (the waterfall's 0x13, the wall's
-- ROCK_CLIMB_N_S 0x4B / _E_W 0x4C) and set down on the first tile past it --
-- the field tasks for both walk the same cell-by-cell line.  Returns true when
-- it moved.  An HM sweep found both dead: Waterfall handed off to Hoenn's climb,
-- which needs Hoenn's tiles, and Rock Climb had nothing at all.
local function gen4Climb(ctx, isClimb)
  local ow = ctx.overworld
  local p = ow and ow.player
  local map = ow and ow.map
  -- HEARTGOLD / SOULSILVER TOO: their TILE_BEHAVIOR_WATERFALL (0x13) and
  -- ROCK_CLIMB_NORTH_SOUTH / _EAST_WEST (0x4B / 0x4C) are Platinum's numbers
  -- (pokeheartgold constants/metatile_behavior.h)
  if not (p and map and map.cellBehaviour and map.def and map.def.generation == 4) then return false end
  local Collision = require("src.world.Collision")
  local dir = p.facing
  local x, y = p.cellX, p.cellY
  local n = 0
  while n < 32 do
    local nx, ny = Collision.target(x, y, dir)
    if not map:inBounds(nx, ny) then break end
    if not isClimb(map:cellBehaviour(nx, ny), dir) then break end
    x, y, n = nx, ny, n + 1
  end
  if n == 0 then return false end
  ow:scriptMove(p, dir, n + 1)
  return true
end

function Commands.g4_use_waterfall(ctx, slot)
  local ow = ctx.overworld
  local p = ow and ow.player
  if not (ow and p) then return end
  if ptRideCutInFirst(ctx, slot, Commands.g4_use_waterfall) then return end
  -- HEARTGOLD / SOULSILVER: CallFieldTask_Waterfall -- the HM cut-in, then a
  -- two-tile ride up the fall (src/world/Gen4WaterfallRide.lua)
  if require("src.import.Gen4ScriptBands").family == "hgss" then
    local index = math.floor(tonumber(valueOf(ctx, slot)) or 0)
    local mon = ((ctx.save and ctx.save.party) or {})[index + 1]
    if require("src.world.Gen4WaterfallRide").start(ow, p.facing, mon) then return end
  end
  if gen4Climb(ctx, function(b) return b == 0x13 end) then return end
  if ow.tryWaterfallOW then
    local handled = ow:tryWaterfallOW()
    if handled then return end
  end
  Logger.info("gen4 script: `usewaterfall` had no overworld climb to hand off "
              .. "to, so the player stays where they are")
end

-- `userockclimb <slot>` -- and this one has nothing to hand off to: no
-- generation in this engine climbs a rock wall. Declared rather than faked,
-- because the alternative is a script that reports success and a player who
-- does not move -- and Rock Climb is how Sinnoh gates Route 217 and the
-- Mt. Coronet back routes, so a silent failure there reads as a broken map.
-- Through `pending` rather than a one-shot of its own: that helper exists for
-- exactly this -- "decoded and lowered, the thing it drives is not built" --
-- and a second hand-rolled copy of its say-once logic would be this port's
-- favourite fault in miniature.
function Commands.g4_use_rock_climb(ctx, slot)
  -- PLATINUM: FieldTask_UseRockClimb -- the cut-in, the `rock_ride` mount, the
  -- hop on, the fast climb, the hop off and the debris (Gen4RockClimbRide)
  local RC = require("src.world.Gen4RockClimbRide")
  local ow = ctx.overworld
  if RC.platinum() and ow and ow.player then
    local index = math.floor(tonumber(valueOf(ctx, slot)) or 0)
    local mon = ((ctx.save and ctx.save.party) or {})[index + 1]
    if RC.start(ow, ow.player.facing, mon) then return end
  end
  local ok = gen4Climb(ctx, function(b, dir)
    if dir == "up" or dir == "down" then return b == 0x4B end
    return b == 0x4C
  end)
  if not ok then
    Logger.info("gen4 script: `userockclimb` found no rocky wall ahead -- the player stays put")
  end
end
-- 0x14B. Identical to 0x14A in the cartridge and deliberately NOT sharing its
-- row: 0x14A's handler is a no-op justified by its caller (a lost honey-tree
-- battle, where the teardown has already blacked out), and 0x14B's only caller
-- is `CommonScript_PoisonWhiteout`, where no battle happened. Unreachable under
-- the Gen 4 poison rule (`if (hp > 1) hp--` cannot wipe a party), so declared
-- rather than given a third copy of the whiteout sequence. See the lowering.
pending("g4_blackout_from_battle_2", "a whiteout the Gen 4 poison rule makes unreachable")

-- `buffermapname <slot> <mapHeaderID>` -- `MapHeader_LoadName`, the PLAYER-
-- FACING name from message bank 433, which every header already carries as
-- `label` (see Gen4MapHeaders, where confusing that with the internal name is
-- written up).  `gen4_map_headers` is keyed by header id, which is what the
-- operand is, so this is a field read.
function Commands.g4_buffer_map_name(ctx, slot, header)
  local game = ctx.game
  if not game then return end
  local id = math.floor(valueOf(ctx, header) or 0)
  local headers = game.data and game.data.gen4_map_headers
  local rec = headers and headers[id]
  -- ...BUT `gen4_map_headers` IS NOT KEPT AT RUNTIME (Data loads it only as
  -- the Gen 4 marker), so this read nil on every call and Sandgem's swarm
  -- line said "! They said..." with no place in it (pt_cmd audit). Every map
  -- def built from a header carries the same `label` (RomExtractorGen4).
  if not (rec and rec.label) and game.data then
    local mapId = mapForHeader(game.data, id)
    local def = mapId and game.data.maps and game.data.maps[mapId]
    if def and def.label then rec = { label = def.label } end
  end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[(tonumber(slot) or 0) + 1] = (rec and rec.label) or ""
  if not (rec and rec.label) then
    Logger.warn("gen4 text: `buffermapname` names header %d, which this cache "
                .. "has no label for", id)
  end
end

-- ---------------------------------------------------------------------------
-- CHAPTER FOUR -- Eterna to Veilstone
-- ---------------------------------------------------------------------------
--
-- 271 entry points, 835 blocks, 6,876 instructions across the Cycling Road,
-- Mt. Coronet's south end, Route 208, Hearthome (city, gym and Amity Square),
-- Route 209 and the Lost Tower, Solaceon, Route 210, Route 215 and Veilstone.
-- 138 unlowered rows across 52 commands.
--
-- One of them could stop the player leaving Eterna, and it is the first below.

-- `checkplayeronbike <destVar>` -- `PlayerAvatar_GetPlayerState() ==
-- PLAYER_AVATAR_CYCLING`. THE CYCLING ROAD GATES ARE THE REASON THIS MATTERS:
-- both gate coord events are
--
--     CheckPlayerOnBike VAR_RESULT
--     GoToIfEq VAR_RESULT, TRUE, ...ForceBikingInGateCoordEvent
--     Message ...Text_OpenOnlyToCyclists
--
-- so with the check unlowered VAR_RESULT holds whatever the previous command
-- left, and the gate either turns the player away from the only road south or
-- lets them through on foot depending on a value that has nothing to do with
-- the bike.
function Commands.g4_check_on_bike(ctx, destVar)
  local on = (ctx.save and ctx.save.onBike) and 1 or 0
  if destVar then setVar(ctx.save, destVar, on) end
  setResult(ctx, on)
end

-- `forcebicycling <onOff>` -- `PlayerAvatar_SetOnCyclingRoad`. The Cycling
-- Road puts you on the bike and will not let you off; the port already has
-- that idea for Kanto's Route 17 (`save.forcedBike`, armed by the forced-bike
-- TILE and read by the bag before it lets the BICYCLE be put away), so this is
-- the same flag set from a script instead of from a tile.
function Commands.g4_force_bike(ctx, on)
  local save = ctx.save
  if not save then return end
  local want = math.floor(tonumber(on) or 0) ~= 0
  save.forcedBike = want or nil
  -- HGSS's SetBikeStateLock only LOCKS the state (AVATAR_FLAG_LOCK_BIKE_STATE,
  -- pokeheartgold scrcmd_c.c / player_avatar.c); it never mounts the player
  if require("src.import.Gen4ScriptBands").family == "hgss" then return end
  local was = save.onBike
  if want then save.onBike = true end
  bikeMusicAfter(ctx, was)
end

-- `setcyclingbgm`: the bike song now, whatever the map's own is
function Commands.g4_cycling_bgm(ctx)
  local data = ctx.game and ctx.game.data
  local ok, Music = pcall(require, "src.core.Music")
  if not (ok and data) then return end
  local bike = Music.special(data, "bike")
  if bike then pcall(Music.play, data, bike, nil, { reason = "map" }) end
end

-- `getpreviousmapid <destVar>` -- `FieldOverworldState_GetPrevLocation`, as a
-- HEADER id, which is what `g4_get_map_id` already answers for the current
-- map. One site: the Cycling Road asking which end you came in from.
function Commands.g4_previous_map(ctx, destVar)
  local ow = ctx.overworld
  local data = ctx.game and ctx.game.data
  local prev = ow and (ow.previousMapId or (ow.lastOutdoor and ow.lastOutdoor.id))
  local def = prev and data and data.maps and data.maps[prev]
  setVar(ctx.save, destVar, tonumber(def and def.header) or 0)
end

-- ------------------------------------------------------------ party queries --
--
-- Four commands that read one party slot. `getpartymonfriendship` alone is 143
-- sites across the cartridge -- the third most common unlowered command in the
-- whole corpus -- because every "your Pokemon looks happy" line in the region
-- runs through it.
--
-- WATCH THE OPERAND ORDER: the DESTINATIONS COME FIRST on three of these four
-- and the slot is last, which is the opposite of the way they read aloud.
--   getpartymonfriendship <destVar> <slot>
--   getpartymontype       <type1Var> <type2Var> <slot>
--   checkpartymonhasmove  <destVar> <move> <slot>

local function partyMon(ctx, slot)
  local n = math.floor(valueOf(ctx, slot) or 0)
  return (ctx.save and ctx.save.party or {})[n + 1]
end

-- FRIENDSHIP IS NOT KEPT FOR GEN 4 YET, and this says so once rather than
-- answering zero. `mon.friendship or mon.happiness` is the spelling Gen 3
-- already uses; a Gen 4 mon carries neither, so the species' own
-- `baseFriendship` is the answer -- which is exactly the value a freshly
-- caught Pokemon has on the cartridge, and therefore right until something
-- starts moving the counter.
function Commands.g4_mon_friendship(ctx, destVar, slot)
  local mon = partyMon(ctx, slot)
  local value = mon and tonumber(mon.friendship or mon.happiness)
  if mon and not value then
    local def = (ctx.game and ctx.game.data and ctx.game.data.pokemon or {})[mon.species]
    value = tonumber(def and def.baseFriendship)
    if not Gen4Commands._saidFriendship then
      Gen4Commands._saidFriendship = true
      Logger.info("gen4 party: no friendship counter is kept for Gen 4 yet, so "
                  .. "a species' base friendship is answered -- which is what a "
                  .. "newly caught Pokemon has")
    end
  end
  if destVar then setVar(ctx.save, destVar, value or 0) end
  setResult(ctx, value or 0)
end

-- `typeIds` on the species row is the cartridge's own pair, already extracted.
function Commands.g4_mon_types(ctx, type1Var, type2Var, slot)
  local mon = partyMon(ctx, slot)
  local def = mon and require('src.pokemon.Gen4Forms').definition(
    ctx.game and ctx.game.data,mon)
  local ids = (def and def.typeIds) or {}
  if type1Var then setVar(ctx.save, type1Var, tonumber(ids[1]) or 0) end
  if type2Var then setVar(ctx.save, type2Var, tonumber(ids[2]) or tonumber(ids[1]) or 0) end
end

-- AN EGG ANSWERS NO, and the cartridge checks that before it looks at the move
-- slots -- an egg's move list is real data and would otherwise match.
function Commands.g4_mon_has_move(ctx, destVar, move, slot)
  local mon = partyMon(ctx, slot)
  local want = math.floor(valueOf(ctx, move) or 0)
  local yes = 0
  if mon and not mon.isEgg then
    for _, m in ipairs(mon.moves or {}) do
      local id = tonumber(m) or tonumber(m and m.id)
      if id == want then yes = 1 break end
    end
  end
  if destVar then setVar(ctx.save, destVar, yes) end
  setResult(ctx, yes)
end

-- `getfirstnonegginparty <destVar>` -- the slot, not the Pokemon.
function Commands.g4_first_non_egg(ctx, destVar)
  local slot = 0
  for i, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg then slot = i - 1 break end
  end
  if destVar then setVar(ctx.save, destVar, slot) end
  setResult(ctx, slot)
end

-- `checkpartyhasspecies2 <species> <destVar>` -- `Party_HasSpecies`. Note the
-- order: species first here, destination second, unlike the four above.
function Commands.g4_party_has_species2(ctx, species, destVar)
  local want = math.floor(valueOf(ctx, species) or 0)
  local yes = 0
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if speciesNumber(mon) == want then yes = 1 break end
  end
  if destVar then setVar(ctx.save, destVar, yes) end
  setResult(ctx, yes)
end

local function fatefulSlot(ctx, species)
  local Party=require('src.pokemon.Party')
  for i,mon in ipairs((ctx.save and ctx.save.party) or {}) do
    local marked=mon.fatefulEncounter
    if marked==nil then marked=mon.fateful end
    if not Party.isEgg(mon) and speciesNumber(mon)==species
        and (marked==true or marked==1) then return i-1 end
  end
  return 255
end

function Commands.g4_fateful_slot(ctx,destVar,species)
  setVar(ctx.save,destVar,fatefulSlot(ctx,math.floor(valueOf(ctx,species) or 0)))
end

-- FollowerPokeIsEventTrigger <event, slot, dest> (pokeheartgold scrcmd_c.c
-- 4379 + trainer_memo.c MonMetadataMatchesEvent): 1 when the party Pokemon at
-- `slot` is no egg, carries the fateful-encounter mark, and is the event's
-- species -- 0 Spiky-eared Pichu (Pichu / Pikachu / Raichu, shiny), 1 / 2
-- Arceus, 3 Celebi
local EVENT_SPECIES = { [0] = { [172] = true, [25] = true, [26] = true },
  [1] = { [493] = true }, [2] = { [493] = true }, [3] = { [251] = true } }
function Commands.g4_follower_event_trigger(ctx, event, slot, destVar)
  local e = math.floor(tonumber(event) or -1)
  local i = math.floor(valueOf(ctx, slot) or 0) + 1
  local mon = ((ctx.save and ctx.save.party) or {})[i]
  local yes = 0
  local Party = require('src.pokemon.Party')
  if mon and not Party.isEgg(mon) and EVENT_SPECIES[e] and EVENT_SPECIES[e][speciesNumber(mon)] then
    local marked = mon.fatefulEncounter
    if marked == nil then marked = mon.fateful end
    if marked == true or marked == 1 then
      if e ~= 0 or require('src.pokemon.Pokemon').isShiny(mon) then yes = 1 end
    end
  end
  setVar(ctx.save, destVar, yes)
end

-- BW 0x220: the first party Pokemon of `species` carrying the fateful mark
function Commands.g4_bw_event_mon(ctx, species, slotVar, destVar)
  local slot = fatefulSlot(ctx, math.floor(valueOf(ctx, species) or 0))
  if slotVar then setVar(ctx.save, slotVar, slot == 255 and 0 or slot) end
  setVar(ctx.save, destVar, slot == 255 and 0 or 1)
end

function Commands.g4_fateful_regigigas(ctx,destVar)
  setVar(ctx.save,destVar,fatefulSlot(ctx,486)~=255 and 1 or 0)
end

function Commands.g4_party_pokerus(ctx,destVar)
  local found=0
  for _,mon in ipairs((ctx.save and ctx.save.party) or {}) do
    local virus=tonumber(mon.pokerus or mon.gen4Pokerus or mon.gen3Pokerus) or 0
    if virus~=0 then found=1;break end
  end
  setVar(ctx.save,destVar,found)
end

-- `startwildbattle <species> <level>` -- the plain scripted wild battle, which
-- is `startlegendarybattle` without the flag that makes it unfleeable. Two
-- sites on Route 209 (the Spiritomb well).
function Commands.g4_start_wild_battle(ctx, species, level)
  local id = math.floor(valueOf(ctx, species) or 0)
  local lv = math.max(math.floor(valueOf(ctx, level) or 1), 1)
  local mons = ctx.game and ctx.game.data and ctx.game.data.pokemon
  if id == 0 or not (mons and mons[id]) then
    Logger.warn("gen4 script: `startwildbattle` names species %s, which this "
                .. "dataset does not carry -- the battle is skipped", tostring(id))
    return
  end
  Commands.start_battle(ctx, "wild", id, lv)
end

-- `getnationaldexseencount <destVar>` -- the whole dex rather than Sinnoh's
-- view of it, which is what `save.pokedex.seen` already is.
function Commands.g4_national_dex_seen(ctx, destVar)
  setVar(ctx.save,destVar,dexCount(ctx,'seen',false,false))
end

-- `getselectedpartyslot <destVar>` -- which slot the party menu came back
-- with. PARTY_SLOT_NONE is 0xFF and means CANCELLED, and that is the honest
-- answer while the menus in front of it (the move tutor's) are not built:
-- answering 0 would name the first Pokemon and send the script down a branch
-- the player never chose.
Gen4Commands.PARTY_SLOT_NONE = 0xFF

function Commands.g4_selected_party_slot(ctx, destVar)
  -- ...AND IT ANSWERS FOR REAL WHEN A MENU ACTUALLY RAN. `ctx.g4PartySlot` is
  -- set by the party menus that are built (so far: the trade's) and is nil
  -- everywhere else, which keeps the stub's honest CANCELLED for the ones that
  -- are not. Reading it only when it is present is the whole of the change:
  -- nothing that used to answer NONE stops doing so.
  local slot = ctx.g4PartySlot
  if slot == nil then slot = Gen4Commands.PARTY_SLOT_NONE end
  if destVar then setVar(ctx.save, destVar, slot) end
  setResult(ctx, slot)
end

-- ---------------------------------------------------------------------------
-- CHAPTERS FIVE AND SIX -- Veilstone to Pastoria, and Lake Valor to Canalave
-- ---------------------------------------------------------------------------
--
-- Two walks: Veilstone through Route 214, the Valor Lakefront, Route 213 and
-- the Great Marsh to Crasher Wake's gym (131 roots, 456 blocks), and Lake
-- Valor through Route 212 to Fantina's gym, then Route 218 to Canalave and
-- Byron's (157 roots, 418 blocks). 27 and 26 unlowered rows respectively --
-- the chapter-four work had already covered most of both.

-- `getoverworldweather <destVar>` -- `FieldOverworldState_GetWeather`.
--
-- THE SAVED VALUE, which this used to say the port did not have.
--
-- The paragraph here used to read "the port keeps no saved Gen 4 weather:
-- applyMapWeather is Gen 3 only, and inventing a `save.gen4Weather` that one
-- command writes and nothing else reads would be worse than answering from
-- the map". That was true and it was the right call at the time. It stopped
-- being true when the field weather was wired up: `applyMapWeather` now runs
-- the cartridge's own three steps on every Gen 4 map load -- resolve a
-- calendar id against the date, substitute CLEAR for a weather a field move
-- has turned off, store both -- so there is a saved value and **it is the one
-- the renderer is drawing**.
--
-- Reading the map def instead would be the recurring bug exactly: the script
-- and the picture answering the same question from two places. Route 213 is
-- the case that proves it -- its header carries 33, a CALENDAR id, and
-- `getoverworldweather` has to answer today's resolved weather rather than
-- 33, which is not a weather at all.
--
-- The map def stays as the fallback for a save that has not loaded a map yet,
-- and `gen4WeatherCleared` stays readable because a script may have set it
-- between loads.
--
-- OVERWORLD_WEATHER_CLEAR IS 0, which is also the answer for the 460 maps that
-- carry no weather at all, so "cleared" and "never had any" are deliberately
-- the same value -- as they are on the cartridge, where one enum holds both.
function Commands.g4_overworld_weather(ctx, destVar)
  local ow = ctx.overworld
  local value = ctx.save and tonumber(ctx.save.gen4WeatherActive)
  if value == nil then
    local cleared = (ctx.save and ctx.save.gen4WeatherCleared)
                    or (ow and ow.gen4WeatherCleared)
    local def = ow and ow.map and ow.map.def
    value = cleared and 0 or (tonumber(def and def.weather) or 0)
  end
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- `getpartymonmove <destVar> <slot> <moveSlot>` -- `MON_DATA_MOVE1 + moveSlot`.
function Commands.g4_mon_move(ctx, destVar, slot, moveSlot)
  local mon = partyMon(ctx, slot)
  local index = math.floor(valueOf(ctx, moveSlot) or 0)
  local entry = mon and (mon.moves or {})[index + 1]
  local id = tonumber(entry) or tonumber(entry and entry.id) or 0
  if destVar then setVar(ctx.save, destVar, id) end
  setResult(ctx, id)
end

function Commands.g4_mon_move_count(ctx, destVar, slot)
  local mon = partyMon(ctx, slot)
  local n = 0
  for _, m in ipairs((mon and mon.moves) or {}) do
    local id = tonumber(m) or tonumber(m and m.id) or 0
    if id ~= 0 then n = n + 1 end
  end
  if destVar then setVar(ctx.save, destVar, n) end
  setResult(ctx, n)
end

-- `findpartyslotwithmove <destVar> <move>` -- and THE MISS VALUE IS SIX, not
-- zero: `for (slot = 0, *destVar = MAX_PARTY_SIZE; ...)` seeds the destination
-- with the party size and only overwrites it on a hit, so "nobody knows this
-- move" and "the first Pokemon knows it" are 6 and 0. Answering 0 on a miss
-- would name the lead.
function Commands.g4_find_slot_with_move(ctx, destVar, move)
  local want = math.floor(valueOf(ctx, move) or 0)
  local found = 6
  for i, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg then
      for _, m in ipairs(mon.moves or {}) do
        local id = tonumber(m) or tonumber(m and m.id)
        if id == want then found = i - 1 break end
      end
    end
    if found ~= 6 then break end
  end
  if destVar then setVar(ctx.save, destVar, found) end
  setResult(ctx, found)
end

-- `getpcboxesfreeslotcount <destVar>` -- `MAX_PC_BOXES * MAX_MONS_PER_BOX`
-- minus what is stored. The port's own `Boxes` module answers both halves and
-- already knows the running cartridge's shape, so no constant is hard-coded
-- here. The one site is the Great Marsh gate refusing you when there is
-- nowhere to put a catch -- which is why answering a flat zero would have been
-- actively wrong rather than merely absent.
-- NO pcall AROUND THE REQUIRE, and that is a correction rather than an
-- oversight. The first version wrapped it and fell back to ZERO free slots --
-- which is not "I could not tell", it is "your boxes are full", and it is the
-- one answer that makes the Great Marsh gate turn the player away. A defensive
-- default has to be the harmless one, and here that is the opposite end.
--
-- `src.pokemon.Boxes` is a core module that every generation loads, so a
-- failure to require it is a real fault and should be loud rather than quietly
-- locking a player out of the marsh.
function Commands.g4_pc_free_slots(ctx, destVar)
  local Boxes = require("src.pokemon.Boxes")
  local free = 0
  if ctx.save then
    Boxes.ensure(ctx.save)
    local used = 0
    for _, box in pairs(ctx.save.boxes or {}) do
      used = used + (tonumber(Boxes.used(box)) or 0)
    end
    local total = (tonumber(Boxes.count()) or 0) * (tonumber(Boxes.capacity()) or 0)
    free = math.max(0, total - used)
  end
  if destVar then setVar(ctx.save, destVar, free) end
  setResult(ctx, free)
end

function Commands.g4_storage(ctx, mode)
  -- box_settings.h: PC_MODE_DEPOSIT, _WITHDRAW, _MOVE, _MOVE_ITEMS, _COMPARE
  local modes = { [0] = 'deposit', [1] = 'withdraw', [2] = 'move', [3] = 'items', [4] = 'compare' }
  local done = false
  require('src.ui.Screens').push(ctx.game, 'BoxMenu', {
    mode = modes[valueOf(ctx, mode)] or 'move', onCancel = function() done = true end,
  })
  ctx.runner.waitingCheck = function() return done end
  ctx.runner:yield()
end
local function honeyId(ctx)
 local def=ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
 return require('src.world.Gen4HoneyTrees').treeId(def and def.header)
end
function Commands.g4_honey_slather(ctx) require('src.world.Gen4HoneyTrees').slather(ctx.save,honeyId(ctx)) end
function Commands.g4_honey_status(ctx,dest)
 local id=honeyId(ctx);local status=id~=nil and require('src.world.Gen4HoneyTrees').status(ctx.save,id) or 1
 setVar(ctx.save,dest,status)
end
function Commands.g4_honey_stop(ctx)
 local s=ctx.save.gen4HoneyTrees;local tree=s and s.trees[honeyId(ctx)]
 if tree then tree.shakes=0 end
end
function Commands.g4_honey_battle(ctx)
 local species,level=require('src.world.Gen4HoneyTrees').consume(ctx.game.data,ctx.save,honeyId(ctx))
 -- CreateWildMon_HoneyTree -> CreateWildMon: the lead's Synchronize / Cute Charm
 local L=species and require('src.world.Gen4WildLead').choose(ctx.game.data,ctx.save,
   {{species=species,level=level}},'grass','radar',love.math.random)
 if species then Commands.start_battle(ctx,'wild',species,level,
   L and (L.nature or L.gender) and {nature=L.nature,gender=L.gender} or nil) end
end
Commands.meta.g4_storage = { foreground = true, blocking = true }

-- `checkdidnotcapture <destVar>` -- `CheckPlayerDidNotCaptureWildMon`, asked
-- after a legendary or scripted wild battle so the script knows whether to put
-- the Pokemon back on the map. `start_battle` already leaves the outcome in
-- `ctx.lastBattleResult`, and "caught" is the only result that means captured.
function Commands.g4_did_not_capture(ctx, destVar)
  local value = (ctx.lastBattleResult == "caught") and 0 or 1
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- ---------------------------------------------------------------------------
-- CHAPTERS SEVEN AND EIGHT -- Byron to Candice, and Spear Pillar to the League
-- ---------------------------------------------------------------------------
--
-- Chapter seven (Canalave, Iron Island, Celestic, the Galactic HQ, Routes 216
-- and 217, Snowpoint and Lake Acuity) came in at 196 roots, 560 blocks and only
-- 16 unlowered rows -- the earlier chapters had already covered it.
--
-- Chapter eight (Mt. Coronet's top, Spear Pillar, the Distortion World,
-- Sunyshore, Victory Road and the whole Pokemon League) is 129 roots, 421
-- blocks, 128 rows -- and it contains the end of the game.

-- `getbattleresult <destVar>` -- the raw result MASK, not the won/lost bit that
-- `checkwonbattle` and `checklostbattle` each read one flag out of. The one
-- site is the Distortion World asking how the Giratina fight ended so it can
-- decide whether to put it back.
--
-- The port keeps `ctx.lastBattleResult` as a word, so the mask is rebuilt from
-- it here rather than a fourth field being added to the context.
--
-- AND IT IS A BITMASK, NOT AN ENUM, which is what the old table got wrong.
-- `include/constants/battle.h` builds the compound values out of three bits:
--
--     WIN           1 << 0 = 1
--     LOSE          1 << 1 = 2
--     CAPTURED_MON  1 << 2 = 4
--     DRAW          WIN | LOSE          = 3
--     PLAYER_FLED   CAPTURED_MON | WIN  = 5
--     ENEMY_FLED    CAPTURED_MON | LOSE = 6
--     TRY_FLEE_WAIT 1 << 6 = 64     TRY_FLEE 1 << 7 = 128
--
-- The old table read `{ caught = 5, fled = 3, draw = 4 }` -- the right SET of
-- numbers attached to the wrong three names, a straight three-way rotation of
-- CAPTURED_MON, PLAYER_FLED and DRAW.  That is what guessing an order looks
-- like when the values happen to be small and contiguous.
--
-- ONE SITE, MEASURED over all 8,567 blocks: `getbattleresult` occurs exactly
-- once in the cartridge and it is the Distortion World asking how the Giratina
-- fight ended.  Said plainly because the number matters to the claim: this is
-- a wrong constant with almost no blast radius, unlike the yes/no menu's 511.
-- `checkwonbattle` (197 sites) and `checklostbattle` (1) read their own bit
-- through their own commands and never touch this table.
Gen4Commands.BATTLE_RESULT = {
  win = 1, lose = 2, caught = 4, draw = 3, fled = 5, enemyFled = 6,
}

function Commands.g4_get_battle_result(ctx, destVar)
  local value = Gen4Commands.BATTLE_RESULT[ctx.lastBattleResult or ""] or 0
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- `checkpartyhashelditem <item> <destVar>` -- Mt. Coronet's summit asking
-- whether you are carrying the Adamant or Lustrous Orb.
function Commands.g4_party_has_held_item(ctx, item, destVar)
  local data = ctx.game and ctx.game.data
  local want = itemKey(data, math.floor(valueOf(ctx, item) or 0))
  local yes = 0
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    local held = mon.item or mon.heldItem
    if held and held == want then yes = 1 break end
  end
  if destVar then setVar(ctx.save, destVar, yes) end
  setResult(ctx, yes)
end

-- `setspeciesseen <species>` -- `FieldSystem_WriteSpeciesSeen`. Spear Pillar
-- marks Dialga and Palkia seen as they appear, before either is fought, which
-- is how the dex knows about the one you do not get.
function Commands.g4_set_species_seen(ctx, species)
  local id = math.floor(valueOf(ctx, species) or 0)
  if id == 0 then return end
  local save = ctx.save
  if not save then return end
  save.pokedex = save.pokedex or { seen = {}, owned = {} }
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.seen[id] = true
end

-- `getgameversion <destVar>` -- `GAME_VERSION`, which is VERSION_PLATINUM.
-- Counted off `include/constants/versions.h` rather than assumed, because the
-- enum has three UNUSED holes in it: NONE 0, SAPPHIRE 1, RUBY 2, EMERALD 3,
-- FIRERED 4, LEAFGREEN 5, unused 6, HEARTGOLD 7, SOULSILVER 8, unused 9,
-- DIAMOND 10, PEARL 11, PLATINUM 12. Spear Pillar asks so it knows whether
-- Dialga or Palkia is yours.
Gen4Commands.VERSION_PLATINUM = 12
-- ...and HeartGold / SoulSilver ask it too, on the same enum: the Dragon's Den
-- elder (D44R0103) tells HeartGold "...Never mind" about Lugia (== 7) and
-- SoulSilver the Whirl Islands basin -- every HGSS script was being answered
-- PLATINUM, i.e. "not HeartGold", and took SoulSilver's branch.
Gen4Commands.VERSION_IDS = { heartgold = 7, soulsilver = 8, diamond = 10, pearl = 11, platinum = 12 }

function Commands.g4_game_version(ctx, destVar)
  local value = Gen4Commands.VERSION_IDS[require("src.core.GameVersion").get()]
    or Gen4Commands.VERSION_PLATINUM
  if destVar then setVar(ctx.save, destVar, value) end
  setResult(ctx, value)
end

-- FLAG_GAME_COMPLETED follows FLAG_JOURNAL_ACQUIRED in vars_flags.txt.
-- It is set before the Hall of Fame scene, rather than inferred from credits.
Gen4Commands.GAME_COMPLETED_FLAG = "FLAG_G4_0964"
function Commands.g4_set_game_completed(ctx)
  ctx.save.flags = ctx.save.flags or {}
  Commands.set_flag(ctx, Gen4Commands.GAME_COMPLETED_FLAG)
end
function Commands.g4_game_completed(ctx, destVar)
  local flag = (ctx.save.flags or {})[Gen4Commands.GAME_COMPLETED_FLAG]
  -- Older runtime saves recorded inductions without implementing SetGameCompleted.
  if flag == nil then flag = #((ctx.save and ctx.save.hallOfFame) or {}) > 0 end
  setVar(ctx.save, destVar, flag == true and 1 or 0)
end
function Commands.g4_daycare_has_egg(ctx, destVar)
  -- Daycare_HasEgg: the offspring personality is set (src/pokemon/Gen4DayCare.lua)
  setVar(ctx.save, destVar, require('src.pokemon.Gen4DayCare').hasEgg(ctx.save) and 1 or 0)
end
function Commands.g4_prepare_hall_of_fame(ctx)
  Commands.g4_set_game_completed(ctx)
  Commands.set_flag(ctx, "FLAG_G4_0966") -- communication club access
  local Party = require('src.pokemon.Party')
  for _, mon in ipairs(ctx.save.party or {}) do
    if not Party.isEgg(mon) then
      mon.ribbons = mon.ribbons or {}
      mon.ribbons[32] = true -- Sinnoh Champion, distinct from Hoenn's ribbon 0
    end
  end
end

-- `getleaguevictories <destVar>` counts recorded Hall of Fame inductions.
function Commands.g4_league_victories(ctx, destVar)
  local n = #((ctx.save and ctx.save.hallOfFame) or {})
  if destVar then setVar(ctx.save, destVar, n) end
  setResult(ctx, n)
end

-- `getpartymonevtotal <destVar> <slot>` -- the six EVs added up, which the
-- Sunyshore market reads to decide what it will sell you.
function Commands.g4_mon_ev_total(ctx, destVar, slot)
  local mon = partyMon(ctx, slot)
  local n = 0
  for _, v in pairs((mon and mon.evs) or {}) do n = n + (tonumber(v) or 0) end
  if destVar then setVar(ctx.save, destVar, math.floor(n)) end
  setResult(ctx, math.floor(n))
end

-- RIBBONS, AND TWO SCHEMES THAT DO NOT LINE UP.
--
-- `getpartymonribbon` is the single commonest unlowered command in the whole
-- cartridge -- 178 sites -- and the port already has a ribbon store, but it is
-- HOENN'S: `mon.ribbons` keyed by name, with rank counters, because that is
-- what the contest screen and the POKeNAV read. A Gen 4 script addresses a
-- ribbon by NUMBER, and the map between the two schemes is a table this port
-- does not carry.
--
-- So Gen 4 ribbons are stored under their own NUMERIC keys in the same table.
-- They round-trip exactly (set then get answers yes), they cannot collide with
-- Hoenn's string keys, and `Contest.ribbonCount` walks named keys only, so a
-- Sinnoh ribbon does not silently inflate a Hoenn count. What it does NOT do
-- is show up on the ribbon screen -- that needs the map, and inventing one
-- would put the wrong picture on the right Pokemon.
function Commands.g4_get_mon_ribbon(ctx, destVar, slot, ribbon)
  local mon = partyMon(ctx, slot)
  local id = math.floor(valueOf(ctx, ribbon) or 0)
  local yes = 0
  if mon and type(mon.ribbons) == "table" and mon.ribbons[id] then yes = 1 end
  if destVar then setVar(ctx.save, destVar, yes) end
  setResult(ctx, yes)
end

function Commands.g4_set_mon_ribbon(ctx, slot, ribbon)
  local mon = partyMon(ctx, slot)
  if not mon then return end
  local id = math.floor(valueOf(ctx, ribbon) or 0)
  if type(mon.ribbons) ~= "table" then mon.ribbons = {} end
  mon.ribbons[id] = true
  -- sub_0206DDB8: a ribbon-count milestone is Platinum's TV record
  pcall(function() require("src.script.PtTvRecords").ribbonGiven(ctx.save, mon, id, ctx.game and ctx.game.data) end)
end

-- ---------------------------------------------------------------------------
-- THE SIX LIFTS
-- ---------------------------------------------------------------------------
--
-- Gen4Elevators.lua carries the whole write-up: two notes in this port said
-- something settled, both were wrong, and between them every lift in Sinnoh
-- opened onto nothing. In short -- a warp with destHeaderID 0xfff and
-- destWarpID 0x100 resolves from the SPECIAL LOCATION, six warps carry that
-- pair and all six are lift cars, and `setspeciallocation` (which writes the
-- slot) was lowered to a noop.
--
-- Required for: Jubilife TV, both Hearthome houses, the Veilstone department
-- store, the Resort Area's Ribbon Syndicate and the Vista Lighthouse.

local function elevators() return require("src.import.Gen4Elevators") end

-- `setspeciallocation <mapHeaderID> <warpId> <x> <z> <faceDirection>`.
--
-- Stored in the SAME SHAPE as Gen 3's `gen3DynamicWarp` -- map id, the raw
-- cartridge warp id, coordinates -- so `Warp.resolve` reads the two seams the
-- same way and the "-1 means use the coordinates" rule is written once. Gen 3
-- spells that sentinel 0xFF and Gen 4 0xFFFF, because one is a byte operand
-- and the other a word.
function Commands.g4_special_location(ctx, header, warp, x, z, facing)
  local Elevators = elevators()
  local data = ctx.game and ctx.game.data
  local id = math.floor(valueOf(ctx, header) or 0)
  local mapId = mapForHeader(data, id)
  if not mapId then
    -- Refusing beats writing a slot the warp cannot resolve: the door then
    -- leaves the player standing in the car with the reason in the log, which
    -- is how the Gen 3 seam fails too.
    Logger.warn("gen4 lift: `setspeciallocation` names header %d and no map in "
                .. "this cache was built from it -- the slot is left alone", id)
    return
  end
  local warpId = math.floor(valueOf(ctx, warp) or Elevators.WARP_NONE)
  ctx.save = ctx.save or {}
  ctx.save.gen4SpecialLocation = {
    map = mapId,
    warp = warpId,
    x = math.floor(valueOf(ctx, x) or 0),
    -- the cartridge's second horizontal axis is `z`; this engine calls it y
    y = math.floor(valueOf(ctx, z) or 0),
    -- Kept although the warp path does not read it: the OTHER readers of this
    -- slot do (the Great Marsh puts you back facing the way you came in when
    -- the balls run out), and dropping it here would mean re-deriving it there.
    facing = DIRECTION[math.floor(valueOf(ctx, facing) or 1)] or "down",
  }
end

-- `getfloorsabove <destVar>` -- `FieldMenu_GetFloorsAbove(specialLocation)`.
--
-- THE FLOOR IT ANSWERS ABOUT IS THE ONE YOU GOT ON AT, not the car you are
-- standing in, and that is what `Warp.noteGen4Entrance` keeps the slot up to
-- date for. The two-floor lifts are nothing but this command and a branch.
function Commands.g4_floors_above(ctx, destVar)
  local Elevators = elevators()
  local spot = ctx.save and ctx.save.gen4SpecialLocation
  local above
  -- ...ON HGSS THE SAME SLOT IS ASKED A DIFFERENT QUESTION. Its
  -- GetDynamicWarpFloorNo is lowered onto this op, but it is
  -- `MapNumToFloorNo` -- the boarding floor's own number, default 0 -- not
  -- the floors above it. Answered from Platinum's switch, the Olivine
  -- Lighthouse car heard "1" from both ends and only ever went down, so the
  -- light room was never reachable by lift (Gen4HgssFloorNo has the switch).
  if require("src.core.GameVersion").family() == "hgss" then
    above = require("src.import.Gen4HgssFloorNo").floorNo(spot and spot.map)
    if destVar then setVar(ctx.save, destVar, above) end
    setResult(ctx, above)
    return
  end
  if spot and spot.map then
    above = Elevators.floorsAbove(spot.map)
  else
    -- The cartridge's slot always holds something; an empty one here means the
    -- player reached a lift without passing through its door. The switch's own
    -- default is the honest answer and it is not zero -- 1 is Hearthome's "go
    -- up", so the car still moves.
    above = Elevators.FLOORS_ABOVE_DEFAULT
    Logger.warn("gen4 lift: `getfloorsabove` with no special location set -- "
                .. "answering the switch's default (%d)", above)
  end
  if destVar then setVar(ctx.save, destVar, above) end
  setResult(ctx, above)
end

-- `bufferfloornumber <slot> <floor>` -- `StringTemplate_SetFloorNumber`.
--
-- ZERO IS THE BASEMENT: the operand is an index into the menu-entries bank,
-- not a signed floor, so formatting it as a number would print B1F as "0F".
-- The label is cartridge text (bank 361, "1F" at 116 through "B1F" at 121) and
-- falls back to the English literal only where the cache has no bank.
function Commands.g4_buffer_floor(ctx, slot, floor)
  local Elevators = elevators()
  local game = ctx.game
  if not game then return end
  local n = math.floor(tonumber(floor) or 1)
  local text = require("src.import.Gen4Text")
                 .resolve(game.data, Elevators.FLOOR_BANK,
                          Elevators.floorEntry(n), game)
  if type(text) ~= "string" or text == "" then
    text = Elevators.floorLabel(n)
  end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[(tonumber(slot) or 0) + 1] = text
end

-- `checkisdepartmentstoreregular <destVar>` -- the buy counter against five.
--
-- Read from the var rather than hard-answered "no": the counter is real save
-- state, and the day the specialty counters are stocked it starts climbing
-- without this command changing. Today the shop that would increment it is
-- declined, so a fresh save answers no -- which is also what the cartridge
-- tells a player who has bought nothing.
function Commands.g4_store_regular(ctx, destVar)
  local Elevators = elevators()
  local bought = getVar(ctx.save, Elevators.BUY_COUNT_VAR)
  local yes = (bought >= Elevators.REGULAR_PURCHASES) and 1 or 0
  if destVar then setVar(ctx.save, destVar, yes) end
  setResult(ctx, yes)
end


-- ---------------------------------------------------------------------------
-- THE PLATFORM LIFTS
-- ---------------------------------------------------------------------------
--
-- `checkplatformliftnotusedwhenenteredmap <destVar>` -- five sites, all five
-- Pokemon League elevator rooms.
--
-- The whole of the answer is `PersistedMapFeatures_InitForPlatformLift`: the
-- flag starts TRUE and only the six LEAGUE cases clear it, only when the
-- arrival z is not the room's bottom-floor warp z. So it means DID YOU COME IN
-- AT THE BOTTOM, and the room's coord event -- the lift's trigger -- is live
-- exactly when you did.
--
-- THE COMPARISON IS IN MATRIX COORDINATES. The cartridge reads
-- `location->z`, and Iron Island B2F-left's own constant settles which space
-- that is: `MAP_TILES_COUNT_Z * 1 + 16` is 48 on a 64x64 map, which only a
-- matrix coordinate can be. All nine of these maps happen to sit at origin
-- (0,0) so local and matrix agree today; `toMatrix` is used anyway, so a mod
-- that relocates one of them is right rather than accidentally right.
--
-- Nothing a player sees changes: the trigger this gates is a no-op in this port
-- (see Gen4ScriptVM, and Gen4PlatformLifts for why all nine rooms are walkable
-- without their lift). What changes is that the var is written.
-- `triggerplatformlift` -- PlatformLift_Trigger: the slab and the player on it
-- ride to the other floor (src/world/Gen4PlatformLiftRide.lua); a League lift
-- at the top stays there.
function Commands.g4_platform_lift_ride(ctx)
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  local data = (ctx.game and ctx.game.data) or (package.loaded["src.core.Game"] or {}).data
  local step = def and require("src.world.Gen4PlatformLiftRide").trigger(def, data)
  if not step then return end
  -- PlatformLift_Trigger flips the persisted floorID as the ride starts
  local M = require("src.world.Gen4DynamicMapFeatures")
  local b = M.buffer(ctx.save, M.PLATFORM_LIFT_ROOM)
  if b and def.gen4PlatformLift then b.floorID = def.gen4PlatformLift.floor end
  local runner = ctx.runner
  if not runner then
    repeat until step()
    return
  end
  runner.waitingCheck = step
  runner:yield()
end
Commands.meta.g4_platform_lift_ride = { blocking = true }

function Commands.g4_platform_lift_bottom(ctx, destVar)
  local Lifts = require("src.import.Gen4PlatformLifts")
  local ow = ctx.overworld
  local def = ow and ow.map and ow.map.def
  local player = ow and ow.player
  local _, z = toMatrix(ctx, player and player.cellX, player and player.cellY)
  local header = def and def.header
  local yes = Lifts.notUsedWhenEnteredMap(header, z) and 1 or 0
  if destVar then setVar(ctx.save, destVar, yes) end
  setResult(ctx, yes)
  -- The answer names the map and the z it compared, because every one of the
  -- five sites is a branch on it and a wrong z looks exactly like the room
  -- having no lift at all.
  local row = Lifts.row(header)
  Logger.debug("gen4 platform lift: %s (header %s) at z %s -> entered at the "
               .. "%s, notUsedWhenEnteredMap = %d",
               tostring(row and row.what or (def and def.id)), tostring(header),
               tostring(z), (yes == 1) and "bottom" or "top", yes)
end


-- ---------------------------------------------------------------------------
-- RELEASING A ROAMER
-- ---------------------------------------------------------------------------
--
-- `activateroamingpokemon <slot>` -- `RoamingPokemon_ActivateSlot`, one byte,
-- no destination. Eight sites over three maps, and one of them is VERITY
-- CAVERN: Mesprit is released the moment the player looks into Lake Verity's
-- water, which is main-path and early.
--
-- The operand is a LITERAL byte (the opcode's width is "b", so it is read with
-- ReadByte and not through a var) -- spelled with `tonumber` rather than
-- `valueOf` for that reason, which is also what keeps slot 0 from being read as
-- a var id.
function Commands.g4_release_roamer(ctx, slot)
  local Roamers = require("src.world.Gen4Roamers")
  Roamers.useFamily()   -- HGSS's four slots on a HeartGold / SoulSilver cache
  local data = ctx.game and ctx.game.data
  local id = math.floor(tonumber(slot) or -1)
  local def = Roamers.SLOTS[id]
  if not def then
    Logger.warn("gen4 roamer: `activateroamingpokemon` names slot %d, which is "
                .. "not one of the six -- nothing was released", id)
    return
  end
  -- ALREADY LOOSE, OR ALREADY DEALT WITH. Eterna's south house runs its three
  -- rows TWICE (two script entries reach the same block), and the cartridge's
  -- ActivateSlot would rebuild the roamer both times -- which on hardware means
  -- the second visit re-rolls a legendary the player may have spent hours
  -- chasing. Refusing to overwrite a LIVE one is the behaviour a player wants
  -- and the behaviour the duplicated site implies; a RETIRED one stays retired,
  -- because the cartridge's own `notUsed`-style state is the slot's `active`
  -- flag and a caught Mesprit does not come back.
  local existing = (ctx.save and ctx.save.gen4Roamers or {})[id]
  -- HGSS's CreateRoamer always rebuilds: the Hall of Fame re-creates a
  -- knocked-out beast (T10R0701, VAR_ROAMER_*_STATUS == 2) over its retired record
  if type(existing) == "table" and not existing.active
     and require("src.core.GameVersion").family() == "hgss" then
    existing = nil
  end
  if type(existing) == "table" then
    Logger.info("gen4 roamer: slot %d (%s) is already %s -- left alone",
                id, def.name, existing.active and "roaming" or "retired")
    return
  end
  local it = Roamers.activate(data, ctx.save, id)
  if not it then
    Logger.warn("gen4 roamer: slot %d (%s) could not be released", id, def.name)
    return
  end
  Logger.info("gen4 roamer: %s (species %d, level %d) is loose on %s",
              def.name, def.species, def.level, tostring(it.map))
end


pending("g4_common", "the common-script archive")
-- NOT `pending`, BECAUSE THIS ONE CARRIES THE ANSWER AND pending DROPS IT.
--
-- `Gen4ScriptVM` emits `{ "g4_unimplemented", ins.name }` -- the opcode's
-- own name -- and its comment says exactly why: "a silently dropped command
-- is a script that runs and quietly does the wrong thing, which is far
-- harder to find than one that reports what it could not do".
--
-- `pending`'s closure takes NO ARGUMENTS, so the one thing the row was built
-- to carry was thrown away and every unlowered command in Sinnoh logged the
-- same line: the WRAPPER's name, never the opcode's.  Found from the
-- Jubilife mart -- talking to the clerk produced one line, and which command
-- the mart needed was not in it.
--
-- Once per opcode rather than once for the wrapper, which is the whole
-- point; `said` would have hushed the second distinct opcode for ever.
-- ---------------------------------------------------------------------------
-- THE PERSISTED MAP FEATURES -- one slot, eleven tenants
-- ---------------------------------------------------------------------------
--
-- See src/world/Gen4DynamicMapFeatures.lua for the whole argument: the
-- cartridge keeps `{ int id; u8 buffer[32]; }` in the misc save block, one
-- feature at a time, and the nine `initpersistedmapfeaturesfor*` commands are
-- nine constructors over that one union rather than nine systems.
--
-- ONE HANDLER FOR ALL NINE, which is the point of lowering them together.
-- The twelve rows had been twelve separately-argued no-ops, and the census
-- read them as twelve subjects -- "nine separate implementations" was its
-- phrase. They are one slot, and a single command with a feature id keeps it
-- that way: a tenth feature is a row in the table below, not a tenth handler
-- that might clear the slot differently.
--
-- The collision resolvers are NOT here and the gyms do not yet block; the
-- module's `COLLISION_IS_A_HEIGHT_PROBLEM` block has the measurement that
-- says why (in short: the puzzle is height arithmetic, treating 0x59 as
-- blocked leaves Pastoria with 57 reachable cells and no button in reach, and
-- the gates alone change nothing). What lands here is the STATE -- which is
-- what the save has to carry, what the Great Marsh tram's six branch sites
-- read, and what a resolver will need to exist before it can be written.
function Commands.g4_map_feature_init(ctx, which, operand)
  local M = require("src.world.Gen4DynamicMapFeatures")
  local save = ctx.save
  if which == "pastoria" then
    -- ...and PastoriaGym_DynamicMapFeaturesInit builds the floor from it
    -- (src/world/Gen4PastoriaGym.lua)
    local b = M.initForPastoriaGym(save)
    local ow = ctx.overworld
    if b and ow and ow.map then require("src.world.Gen4PastoriaGym").apply(ow.map.def, save) end
    return b
  end
  if which == "canalave" then
    -- ...and CanalaveGym_DynamicMapFeaturesInit lays the floors and the 24
    -- platforms out from the fresh bits (src/world/Gen4CanalaveGym.lua)
    local b = M.initForCanalaveGym(save)
    if b and ctx.overworld and ctx.overworld.map then
      require("src.world.Gen4CanalaveGym").apply(ctx.overworld, save)
    end
    return b
  end
  if which == "hearthome" then
    -- ...and HearthomeGym_DynamicMapFeaturesInit deals the room from the
    -- fresh slot: the door that leads on, the clue (src/world/Gen4HearthomeGym.lua)
    local b = M.initForHearthomeGym(save)
    if b and ctx.overworld and ctx.overworld.map then
      require("src.world.Gen4HearthomeGym").apply(ctx.overworld, save)
    end
    return b
  end
  if which == "veilstone" then
    -- ...and VeilstoneGym_DynamicMapFeaturesInit lays out the bags and the
    -- tire stacks (src/world/Gen4VeilstoneGym.lua)
    local b = M.initForVeilstoneGym(save)
    if b and ctx.overworld and ctx.overworld.map then
      require("src.world.Gen4VeilstoneGym").apply(ctx.overworld, save)
    end
    return b
  end
  if which == "eterna" then
    -- ...and EternaGym_DynamicMapFeaturesInit reads the clock back from the
    -- var and poses the hands (src/world/Gen4EternaGym.lua)
    local b = M.initForEternaGym(save)
    if b and ctx.overworld and ctx.overworld.map then
      require("src.world.Gen4EternaGym").apply(ctx.overworld, save)
    end
    return b
  end
  if which == "villa" then return M.initForVilla(save) end
  if which == "distortion" then return M.initForDistortionWorld(save) end
  if which == "platformlift" then
    -- ...and the slab put at the floor the player came in on
    -- (src/world/Gen4PlatformLiftRide.lua)
    local ow = ctx.overworld
    local p = ow and ow.player
    local def = ow and ow.map and ow.map.def
    local floor
    if def then
      local _, pz = toMatrix(ctx, p and p.cellX, p and p.cellY)
      floor = require("src.world.Gen4PlatformLiftRide").place(def, (ctx.game and ctx.game.data)
        or (package.loaded["src.core.Game"] or {}).data, pz)
    end
    -- PlatformLiftPersistedData.floorID: the save's copy, which a continue
    -- builds the lift from (restoreOnContinue)
    local b = M.initForPlatformLift(save)
    if b then b.floorID = floor end
    return b
  end
  if which == "greatmarsh" then return M.initForGreatMarsh(save) end
  if which == "sunyshore" then
    -- THE ONLY ONE WITH AN OPERAND, and it needs the player's z as well:
    -- `PersistedMapFeatures_InitForSunyshoreGym(fieldSystem, roomID)` reads
    -- `fieldSystem->location->z` and forces the rotation back to 0 when it
    -- equals the room's entrance z.  The room id is a raw byte operand (the
    -- opcode spec is "b"), so it does not go through `valueOf`.
    local player = ctx.overworld and ctx.overworld.player
    local _, pz = toMatrix(ctx, player and player.cellX, player and player.cellY)
    local b = M.initForSunyshoreGym(save, math.floor(tonumber(operand) or 0), pz)
    -- ...and SunyshoreGym_DynamicMapFeaturesInit lays the room's gears out
    -- at that rotation (src/world/Gen4SunyshoreGym.lua)
    if b and ctx.overworld and ctx.overworld.map then
      require("src.world.Gen4SunyshoreGym").apply(ctx.overworld, save)
    end
    return b
  end
  Logger.warn("gen4 script: no persisted map feature named '%s'", tostring(which))
end

-- `PastoriaGym_PressButton`: the button is whichever of the three models is
-- under the player's own tile, and nothing happens when there is none.
function Commands.g4_pastoria_button(ctx)
  local M = require("src.world.Gen4DynamicMapFeatures")
  local ow = ctx.overworld
  local player = ow and ow.player
  if not player then return end
  -- The search wants the matrix cell and the tile within it, which is the
  -- same decomposition `g4_door_anim` hands `Gen4Doors.modelAt` -- except
  -- that there the script supplies them and here the player's own position
  -- is the hitbox, so they are derived.
  local x, z = toMatrix(ctx, player.cellX, player.cellY)
  local mapX, tileX = math.floor(x / 32), x % 32
  local mapZ, tileZ = math.floor(z / 32), z % 32
  local model, why = M.propModelAt(ctx.game and ctx.game.data,
                                   ow.map and ow.map.def,
                                   mapX, mapZ, tileX, tileZ,
                                   M.PASTORIA_BUTTON_MODELS)
  if not model then
    -- The cartridge's miss is silent: `FieldSystem_FindCollidingLoadedMapProp`
    -- answers false and `PressButton` returns.  Logged once because a script
    -- that pressed nothing and a port that could not find the prop look the
    -- same from the water level.
    Logger.debug("gen4 script: no Pastoria button under the player (%s)",
                 tostring(why))
    return
  end
  if not M.pressPastoriaButton(ctx.save, model) then
    Logger.warn("gen4 script: the Pastoria button at matrix %d,%d tile %d,%d "
                .. "is model %s, which is not one of the three -- the slot "
                .. "holds feature %d",
                mapX, mapZ, tileX, tileZ, tostring(model), M.id(ctx.save))
    return
  end
  Logger.debug("gen4 script: Pastoria water level -> %s",
               tostring(M.pastoriaWaterHeight(ctx.save)))
  -- the water moves to it, a unit a field frame, and the script waits
  -- (FieldTask_InitCall; src/world/Gen4PastoriaGym.lua)
  local step = require("src.world.Gen4PastoriaGym").pressStep(ow.map and ow.map.def, ctx.save)
  if not step then return end
  local runner = ctx.runner
  if not runner then
    repeat until step()
    return
  end
  runner.waitingCheck = step
  runner:yield()
end
Commands.meta.g4_pastoria_button = { blocking = true }

-- VeilstoneGym_HitPunchingBag, run as a field task the field waits on
-- (src/world/Gen4VeilstoneGym.lua; queued by OverworldState:checkBoulderPush)
function Commands.g4_veilstone_hit(ctx, dir)
  local step = require("src.world.Gen4VeilstoneGym").hit(ctx.overworld, dir)
  if not step then return end
  local runner = ctx.runner
  if not runner then
    repeat until step()
    return
  end
  runner.waitingCheck = step
  runner:yield()
end
Commands.meta.g4_veilstone_hit = { blocking = true }

-- Field_ProcessStep -> CanalaveGym_CheckIfPlayerOnPlatform: the platform the
-- step ended on moves, carrying the player, as a field task the field waits
-- on (src/world/Gen4CanalaveGym.lua; queued by OverworldState:onStepComplete)
function Commands.g4_canalave_ride(ctx)
  local runner = ctx.runner
  if not runner then return end
  local step = require("src.world.Gen4CanalaveGym").ride(ctx.overworld, ctx.save)
  if not step then return end
  runner.waitingCheck = step
  runner:yield()
end
Commands.meta.g4_canalave_ride = { blocking = true }

-- `SunyshoreGym_PressButton(fieldSystem, buttonType)` turns the gears, which
-- is the rotation state the room's collision regions are indexed by.  The
-- rotation IS persisted state, so it advances here even though nothing turns
-- on screen yet -- a button that changed nothing would make the room's state
-- depend on which pass you are playing.
function Commands.g4_sunyshore_gear_button(ctx, buttonType)
  local M = require("src.world.Gen4DynamicMapFeatures")
  local b = M.buffer(ctx.save, M.SUNYSHORE_GYM)
  if not b then
    Logger.debug("gen4 script: a Sunyshore gear button ran while the feature "
                 .. "slot holds %d", M.id(ctx.save))
    return
  end
  -- the rotation state moves now and the gears turn, the script waiting on
  -- them (FieldTask_InitCall; src/world/Gen4SunyshoreGym.lua)
  local step = require("src.world.Gen4SunyshoreGym").press(ctx.overworld, ctx.save, buttonType)
  if not step then
    b.pressedButton = math.floor(tonumber(buttonType) or 0)
    return
  end
  local runner = ctx.runner
  if not runner then
    repeat until step()
    return
  end
  runner.waitingCheck = step
  runner:yield()
end
Commands.meta.g4_sunyshore_gear_button = { blocking = true }

-- `advanceeternagymclock`.  `ScrCmd_AdvanceEternaGymClock` DISCARDS
-- `EternaGym_AdvanceClockState`'s result and always returns TRUE, so the
-- refusal at DEFEATED_GYM_LEADER is invisible to the script -- which is why
-- nothing here writes a var the script could branch on, and why the cap is
-- still reproduced: it is what stops the state walking past the end of
-- `sEternaGymClockTimes`.
function Commands.g4_eterna_clock_advance(ctx)
  local M = require("src.world.Gen4DynamicMapFeatures")
  local advanced, state = M.advanceEternaClock(ctx.save)
  if not advanced then return end
  -- `SetEternaGymFlowerClockState` mirrors it into
  -- VAR_ETERNA_GYM_FLOWER_CLOCK_STATE, which is how
  -- `EternaGym_DynamicMapFeaturesInit` poses the hands on a later entry.  No
  -- script in the cartridge reads the var -- all 1,124 members of scr_seq
  -- were scanned for it and none mentions it -- so this is for the engine's
  -- own benefit, and it is written anyway because the buffer is cleared every
  -- time another feature takes the slot and the var is not.
  setVar(ctx.save, M.ETERNA_CLOCK_VAR, state)
  -- ...and FieldTask_EternaGym_AdvanceClockState turns the hands (and, after
  -- the second and third trainers, stops a fountain and says so), the script
  -- waiting on it (src/world/Gen4EternaGym.lua)
  local sweep, after = require("src.world.Gen4EternaGym").advance(ctx.overworld, ctx.save)
  local runner = ctx.runner
  if not (sweep and runner) then return end
  runner.waitingCheck = sweep
  runner:yield()
  if after then
    Commands.show_text(ctx, lineFor(ctx, require("src.world.Gen4EternaGym").TEXT_DROPPED))
    runner.waitingCheck = after
    runner:yield()
  end
end
Commands.meta.g4_eterna_clock_advance = { blocking = true }

-- THE GREAT MARSH TRAM -- three commands, none of which had a lowering, and
-- one of which is the reason this pass happened.
--
-- `checkgreatmarshtramlocation <location>, <destVar>` writes
-- GREAT_MARSH_TRAM_AT_LOCATION (**5**) or NOT_AT_LOCATION (**6**), and every
-- one of its six sites is followed by `comparevartovalue <destVar>, 6` and a
-- `callif` onto `movegreatmarshtram`.  Five and six, not one and zero: a
-- boolean here is wrong at all six sites in the same direction and the tram
-- is never summoned.
function Commands.g4_marsh_tram(ctx, which, a, b)
  local M = require("src.world.Gen4DynamicMapFeatures")
  if which == "init" then
    local buf = M.initForGreatMarsh(ctx.save)
    -- GreatMarshTram_DynamicMapFeaturesInit: the prop at its location
    if buf then
      pcall(function()
        require("src.world.PtGreatMarshTram").place(ctx.game and ctx.game.data, buf.location)
      end)
    end
    return buf
  end
  if which == "check" then
    -- the location is a raw halfword and the destination a var pointer
    local location = math.floor(tonumber(a) or 0)
    setVar(ctx.save, b, M.checkTramLocation(ctx.save, location))
    return
  end
  if which == "move" then
    -- ...and here it is the other way round: `ScrCmd_MoveGreatMarshTram`
    -- reads the destination through `ScriptContext_GetVarPointer` and the
    -- movement type as a raw halfword.  The script sets 0x8005 or 0x8006
    -- immediately before, so reading the operand as a literal would move the
    -- tram to area 0x8005.
    local destination = math.floor(valueOf(ctx, a) or 0)
    local from = M.tramLocation(ctx.save)
    local moved = M.moveTramToLocation(ctx.save, destination)
    if moved == nil then
      Logger.debug("gen4 script: the tram cannot move; the feature slot holds %d",
                   M.id(ctx.save))
      return
    end
    -- The ride itself is a FieldTask that walks the tram prop along the
    -- track and carries the player with it -- and there is no warp after it:
    -- the ride is what moves the player between areas.  PtGreatMarshTram
    -- runs that task (CallTramToPlayer / RideTramToArea) and waits on it.
    Logger.debug("gen4 script: Great Marsh tram -> area %d (movement %s)",
                 moved, tostring(b))
    require("src.world.PtGreatMarshTram").run(ctx, from, moved, math.floor(tonumber(b) or 0))
    return
  end
  Logger.warn("gen4 script: no Great Marsh tram verb '%s'", tostring(which))
end

local saidUnlowered = {}
function Commands.g4_unimplemented(_, name, note)
  local key = tostring(name)
  if saidUnlowered[key] then return end
  saidUnlowered[key] = true
  Logger.info("gen4 script: `%s` is decoded but not lowered%s -- the row is "
              .. "stepped over and the script carries on", key,
              note and (" (" .. tostring(note) .. ")") or "")
end

-- THE SHARD MOVE TUTORS (scrcmd_move_tutor.c) -- see src/import/Gen4MoveTutor.lua.
local function tutorRec(ctx) return ctx.game and ctx.game.data and ctx.game.data.gen4_move_tutor end
local MENU_CANCEL = 65534

-- `selectmovetutorpokemon`: the party, pick one; getselectedpartyslot reads it.
function Commands.g4_select_tutor_mon(ctx)
  return Commands.g4_open_party_for_trade(ctx)
end
Commands.meta.g4_select_tutor_mon = { foreground = true, blocking = true }

function Commands.g4_tutor_has_moves(ctx, slot, location, destVar)
  local T = require("src.import.Gen4MoveTutor")
  local mon = partyMon(ctx, slot)
  local n = mon and #T.learnable(tutorRec(ctx), mon, math.floor(valueOf(ctx, location) or 0)) or 0
  setVar(ctx.save, destVar, n > 0 and 1 or 0)
end

-- ScrCmd_ShowMoveTutorMoveSelectionMenu: the moves this Pokemon can learn
-- here and does not know, in table order, then EXIT.
function Commands.g4_tutor_menu(ctx, slot, location, destVar)
  local T = require("src.import.Gen4MoveTutor")
  local data = ctx.game and ctx.game.data or {}
  local raw = math.floor(valueOf(ctx, slot) or Gen4Commands.PARTY_SLOT_NONE)
  local mon = raw ~= Gen4Commands.PARTY_SLOT_NONE and partyMon(ctx, slot) or nil
  local moves = T.learnable(tutorRec(ctx), mon, math.floor(valueOf(ctx, location) or 0))
  local items = {}
  for _, id in ipairs(moves) do
    local def = data.moves and data.moves[id]
    items[#items + 1] = { value = id, label = (def and def.name) or ("MOVE " .. id) }
  end
  items[#items + 1] = { value = MENU_CANCEL, label = require("src.core.Strings")("EXIT") }
  local runner = ctx.runner
  setVar(ctx.save, destVar, MENU_CANCEL)
  local rows = {}
  for i, item in ipairs(items) do
    rows[i] = { label = item.label, onSelect = function()
      setVar(ctx.save, destVar, item.value)
      if runner then runner:resume() end
    end }
  end
  ctx.game.stack:push(require("src.ui.Menu").new(ctx.game, rows, {
    cancelable = true,
    onCancel = function()
      setVar(ctx.save, destVar, MENU_CANCEL)
      if runner then runner:resume() end
    end,
  }))
  if runner then runner:yield() end
end
Commands.meta.g4_tutor_menu = { foreground = true, blocking = true }

-- HGSS's Frontier tutors (scrcmd_move_tutor.c ScrCmd_652 /
-- MoveTutorChooseMove / TutorMoveGetPrice)
Commands.HGSS_TUTOR_NEXT, Commands.HGSS_TUTOR_CANCEL = 0xFFFD, 0xFFFE
function Commands.g4_hgss_tutor_pages(ctx, slot, tutor, destVar)
  local T = require("src.import.Gen4MoveTutor")
  local mon = partyMon(ctx, slot)
  local n = mon and #T.learnable(tutorRec(ctx), mon, math.floor(valueOf(ctx, tutor) or 0)) or 0
  setVar(ctx.save, destVar, n == 0 and 0 or (n <= 7 and 1 or math.floor(n / 6) + 1))
end

function Commands.g4_hgss_tutor_price(ctx, move, destVar)
  local T = require("src.import.Gen4MoveTutor")
  local row = T.row(tutorRec(ctx), math.floor(valueOf(ctx, move) or 0))
  setVar(ctx.save, destVar, row and row.cost or 0)
end

function Commands.g4_hgss_tutor_menu(ctx, slot, tutor, page, destVar)
  local T = require("src.import.Gen4MoveTutor")
  local data = ctx.game and ctx.game.data or {}
  local rec = tutorRec(ctx)
  local mon = partyMon(ctx, slot)
  local moves = T.learnable(rec, mon, math.floor(valueOf(ctx, tutor) or 0))
  local p = math.floor(valueOf(ctx, page) or 0)
  local list, next = moves, false
  if #moves > 7 then
    list, next = {}, true
    for i = p * 6 + 1, math.min(#moves, p * 6 + 6) do list[#list + 1] = moves[i] end
  end
  -- the cartridge's own words (msg_0748): #0 "<move>  <n> BP", #2 NEXT, #3 QUIT
  local text = data.text or {}
  local function word(n, fallback)
    local t = text[("TEXT_B0748_%05d"):format(n)]
    return type(t) == "string" and t ~= "" and t or fallback
  end
  local items = {}
  for _, id in ipairs(list) do
    local def = data.moves and data.moves[id]
    local row = T.row(rec, id)
    items[#items + 1] = { value = id,
      label = ("%s  %2d BP"):format((def and def.name) or ("MOVE " .. id), row and row.cost or 0) }
  end
  if next then items[#items + 1] = { value = Commands.HGSS_TUTOR_NEXT, label = word(2, "NEXT") } end
  items[#items + 1] = { value = Commands.HGSS_TUTOR_CANCEL, label = word(3, "QUIT") }
  local runner = ctx.runner
  setVar(ctx.save, destVar, Commands.HGSS_TUTOR_CANCEL)
  local rows = {}
  for i, item in ipairs(items) do
    rows[i] = { label = item.label, onSelect = function()
      setVar(ctx.save, destVar, item.value)
      if runner then runner:resume() end
    end }
  end
  ctx.game.stack:push(require("src.ui.Menu").new(ctx.game, rows, {
    cancelable = true,
    onCancel = function()
      setVar(ctx.save, destVar, Commands.HGSS_TUTOR_CANCEL)
      if runner then runner:resume() end
    end,
  }))
  if runner then runner:yield() end
end
Commands.meta.g4_hgss_tutor_menu = { foreground = true, blocking = true }

-- ScrCmd_CheckCanAffordMove: every non-zero cost must be in the bag.
function Commands.g4_tutor_can_afford(ctx, move, destVar)
  local T = require("src.import.Gen4MoveTutor")
  local row = T.row(tutorRec(ctx), math.floor(valueOf(ctx, move) or 0))
  local inv = (ctx.save and ctx.save.inventory) or {}
  local ok = row ~= nil
  if row then
    for colour, item in pairs(T.SHARDS) do
      local cost = row[colour] or 0
      if cost > 0 and (tonumber(inv[item]) or 0) < cost then ok = false end
    end
  end
  setVar(ctx.save, destVar, ok and 1 or 0)
end

-- ScrCmd_PayShardCost
function Commands.g4_tutor_pay(ctx, move)
  local T = require("src.import.Gen4MoveTutor")
  local row = T.row(tutorRec(ctx), math.floor(valueOf(ctx, move) or 0))
  if not row then return end
  local Bag = require("src.inventory.Bag")
  for colour, item in pairs(T.SHARDS) do
    local cost = row[colour] or 0
    if cost > 0 then Bag.remove(ctx.save, item, cost) end
  end
end

-- The summary screen's "forget which move?": a list of the four (B keeps
-- them all -- slot 4, LEARNED_MOVES_MAX).
function Commands.g4_tutor_forget_menu(ctx, slot, move)
  local mon = partyMon(ctx, slot)
  local data = ctx.game and ctx.game.data or {}
  ctx.g4TutorForget = 4
  if not mon then return end
  local items = {}
  for i, mv in ipairs(mon.moves or {}) do
    local id = tonumber(mv) or tonumber(mv and mv.id) or 0
    local def = data.moves and data.moves[id]
    items[#items + 1] = { value = i - 1, label = (def and def.name) or ("MOVE " .. id) }
  end
  local runner = ctx.runner
  local rows = {}
  for i, item in ipairs(items) do
    rows[i] = { label = item.label, onSelect = function()
      ctx.g4TutorForget = item.value
      if runner then runner:resume() end
    end }
  end
  ctx.game.stack:push(require("src.ui.Menu").new(ctx.game, rows, {
    cancelable = true,
    onCancel = function()
      ctx.g4TutorForget = 4
      if runner then runner:resume() end
    end,
  }))
  if runner then runner:yield() end
end
Commands.meta.g4_tutor_forget_menu = { foreground = true, blocking = true }

function Commands.g4_tutor_forget_slot(ctx, destVar)
  setVar(ctx.save, destVar, ctx.g4TutorForget or 4)
end

-- Pokemon_ResetMoveSlot: the move, full PP, no PP Ups.
function Commands.g4_tutor_set_move(ctx, slot, move, moveSlot)
  local mon = partyMon(ctx, slot)
  if not mon then return end
  local id = math.floor(valueOf(ctx, move) or 0)
  local index = math.floor(valueOf(ctx, moveSlot) or 0) + 1
  local def = ctx.game and ctx.game.data and ctx.game.data.moves and ctx.game.data.moves[id]
  mon.moves = mon.moves or {}
  mon.moves[index] = { id = id, pp = def and def.pp or 0, ppUps = 0 }
end

-- TEACHING AND FORGETTING MOVES OUTSIDE BATTLE: the Move Reminder in
-- Pastoria (`openmoveremindermenu`), Grandma Wilma's Draco Meteor on Route 210
-- (`openmovetutormenu`) and the Move Deleter in Canalave
-- (`selectpartymonmove` / `clearpartymonmoveslot`). scrcmd_party_mon_moves.c,
-- move_reminder_data.c and applications/move_reminder.c.
local function learnMoveId(mv) return tonumber(mv) or tonumber(mv and mv.id) or 0 end

-- Item_IsHMMove: the last eight of `sTMHMMoves`.
function Gen4Commands.isHMMove(data, move)
  local list = data and data.constants and data.constants.tmhmMoves
  if not list then return false end
  for i = 93, #list do
    if list[i] == move then return true end
  end
  return false
end

-- MoveReminderData_GetMoves: the first 22 rows of the level-up learnset
-- (MAX_NUMBER_REMINDER_MOVES), those at or below the mon's level that it does
-- not know, each once, in learnset order. Forms read their own learnset.
function Gen4Commands.reminderMoves(data, mon)
  local out = {}
  if not mon then return out end
  local def = require("src.pokemon.Gen4Forms").definition(data, mon)
  local known = {}
  for _, mv in ipairs(mon.moves or {}) do known[learnMoveId(mv)] = true end
  local level = tonumber(mon.level) or 1
  local seen = {}
  local learnset = (def and def.learnset) or {}
  for i = 1, math.min(22, #learnset) do
    local e = learnset[i]
    if e.level <= level and not known[e.move] and not seen[e.move] then
      seen[e.move] = true
      out[#out + 1] = e.move
    end
  end
  -- RUN MODES: MOVE RELEARNER (src/runmodes/RunHooks.lua relearnable)
  return require("src.runmodes.RunHooks").relearnable(mon, out)
end

local function learnMoveName(data, id)
  local def = data and data.moves and data.moves[id]
  return (def and def.name) or ("MOVE " .. id)
end

-- The teach screen. The moves on offer, then -- with four known -- which one
-- to forget; an HM cannot be forgotten in this mode
-- (PokemonSummaryScreen_PrintHMMovesCantBeForgotten), and backing out of the
-- forget list returns to the moves. B on the moves gives up: keepOldMove.
local function openLearnMenu(ctx, mon, moves)
  local game = ctx.game
  local data = game and game.data or {}
  local runner = ctx.runner
  ctx.g4LearnKeepOld = true
  if not (mon and game and #moves > 0) then return end
  local Menu = require("src.ui.Menu")
  local function finish(keepOld)
    ctx.g4LearnKeepOld = keepOld
    if runner then runner:resume() end
  end
  local function teach(index, move)
    local def = data.moves and data.moves[move]
    mon.moves = mon.moves or {}
    mon.moves[index] = { id = move, pp = def and def.pp or 0, ppUps = 0 }
    finish(false)
  end
  local openMoves
  local function openForget(move)
    local rows = {}
    for i, mv in ipairs(mon.moves or {}) do
      local id = learnMoveId(mv)
      if Gen4Commands.isHMMove(data, id) then
        rows[#rows + 1] = { label = learnMoveName(data, id), keepOpen = true }
      else
        rows[#rows + 1] = { label = learnMoveName(data, id), onSelect = function() teach(i, move) end }
      end
    end
    game.stack:push(Menu.new(game, rows, { cancelable = true, onCancel = function() openMoves() end }))
  end
  openMoves = function()
    local rows = {}
    for _, move in ipairs(moves) do
      rows[#rows + 1] = { label = learnMoveName(data, move), onSelect = function()
        local count, free = 0, nil
        for i = 1, 4 do
          local id = learnMoveId((mon.moves or {})[i])
          if id ~= 0 then count = count + 1 elseif not free then free = i end
        end
        if count < 4 then teach(free, move) else openForget(move) end
      end }
    end
    game.stack:push(Menu.new(game, rows, {
      cancelable = true, maxVisible = math.min(#rows, 7),
      onCancel = function() finish(true) end,
    }))
  end
  openMoves()
  if runner then runner:yield() end
end

-- `openmovetutormenu <partySlot> <move>`: the teach screen with one move.
function Commands.g4_open_move_tutor_menu(ctx, slot, move)
  openLearnMenu(ctx, partyMon(ctx, slot), { math.floor(valueOf(ctx, move)) })
end
Commands.meta.g4_open_move_tutor_menu = { foreground = true, blocking = true }

-- `openmoveremindermenu <partySlot>`
function Commands.g4_open_move_reminder_menu(ctx, slot)
  local mon = partyMon(ctx, slot)
  openLearnMenu(ctx, mon, Gen4Commands.reminderMoves(ctx.game and ctx.game.data, mon))
end
Commands.meta.g4_open_move_reminder_menu = { foreground = true, blocking = true }

-- `checklearnedtutormove` / `checklearnedremindermove <destVar>`: 0 when a
-- move was learned, 0xFF when the old moves were kept.
function Commands.g4_learned_move(ctx, destVar)
  setVar(ctx.save, destVar, ctx.g4LearnKeepOld == false and 0 or 0xFF)
  ctx.g4LearnKeepOld = nil
end

-- `checkhaslearnableremindermoves <destVar> <partySlot>`
function Commands.g4_has_reminder_moves(ctx, destVar, slot)
  local mon = partyMon(ctx, slot)
  local moves = Gen4Commands.reminderMoves(ctx.game and ctx.game.data, mon)
  setVar(ctx.save, destVar, #moves > 0 and 1 or 0)
end

-- `selectpartymonmove <partySlot>`: the summary screen's move cursor, any
-- move (HMs included -- the deleter's whole point); B is slot 4, which
-- `getselectedpartymonmove` answers as MOVE_NOT_SELECTED (0xFF).
function Commands.g4_select_party_mon_move(ctx, slot)
  local mon = partyMon(ctx, slot)
  local game = ctx.game
  local data = game and game.data or {}
  local runner = ctx.runner
  ctx.g4SelectedMoveSlot = 4
  if not (mon and game) then return end
  local rows = {}
  for i, mv in ipairs(mon.moves or {}) do
    local id = learnMoveId(mv)
    if id ~= 0 then
      rows[#rows + 1] = { label = learnMoveName(data, id), onSelect = function()
        ctx.g4SelectedMoveSlot = i - 1
        if runner then runner:resume() end
      end }
    end
  end
  game.stack:push(require("src.ui.Menu").new(game, rows, {
    cancelable = true,
    onCancel = function()
      ctx.g4SelectedMoveSlot = 4
      if runner then runner:resume() end
    end,
  }))
  if runner then runner:yield() end
end
Commands.meta.g4_select_party_mon_move = { foreground = true, blocking = true }

function Commands.g4_selected_party_mon_move(ctx, destVar)
  local v = ctx.g4SelectedMoveSlot or 4
  setVar(ctx.save, destVar, v == 4 and 0xFF or v)
  ctx.g4SelectedMoveSlot = nil
end

-- `clearpartymonmoveslot <partySlot> <moveSlot>`: Pokemon_ClearMoveSlot --
-- the moves below shift up, PP and PP Ups with them, and the last is empty.
function Commands.g4_clear_move_slot(ctx, slot, moveSlot)
  local mon = partyMon(ctx, slot)
  if not (mon and mon.moves) then return end
  local index = math.floor(valueOf(ctx, moveSlot)) + 1
  if index < 1 or index > 4 then return end
  table.remove(mon.moves, index)
end

-- `bufferpartymovename <buffer> <partySlot> <moveSlot>`
function Commands.g4_buffer_party_move(ctx, buffer, slot, moveSlot)
  local mon = partyMon(ctx, slot)
  local mv = mon and (mon.moves or {})[math.floor(valueOf(ctx, moveSlot)) + 1]
  return Commands.g4_buffer(ctx, buffer, "move", learnMoveId(mv))
end

-- THE SOLACEON DAY CARE (scrcmd_daycare.c) -- see src/pokemon/Gen4DayCare.lua.
local function setBuffer(ctx, slot, text)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[(tonumber(slot) or 0) + 1] = text or ""
end

local function dcMonName(ctx, mon)
  local data = ctx.game and ctx.game.data or {}
  local reg = data.pokemon or {}
  local def = mon and (reg[mon.species] or reg[require("src.pokemon.Gen4DayCare").speciesOf(mon)])
  return mon and (mon.nickname or (def and def.name)) or ""
end

-- ov5_021E72BC: buffer 0 the first mon, 2 its OT, 1 the second.
function Commands.g4_daycare_names(ctx)
  local DC = require("src.pokemon.Gen4DayCare")
  local a, b = DC.slot(ctx.save, 0), DC.slot(ctx.save, 1)
  if a and a.mon then
    setBuffer(ctx, 0, dcMonName(ctx, a.mon))
    setBuffer(ctx, 2, a.mon.otName or (ctx.save.player and ctx.save.player.name) or "")
  end
  if b and b.mon then setBuffer(ctx, 1, dcMonName(ctx, b.mon)) end
end

function Commands.g4_daycare_state(ctx, destVar)
  setVar(ctx.save, destVar, require("src.pokemon.Gen4DayCare").state(ctx.save))
end

function Commands.g4_daycare_reset_egg(ctx)
  local dc = require("src.pokemon.Gen4DayCare").store(ctx.save, true)
  dc.personality, dc.counter = 0, 0
end

function Commands.g4_daycare_give_egg(ctx)
  require("src.pokemon.Gen4DayCare").giveEgg(ctx.game, ctx.save)
end

-- `movemontopartyfromdaycareslot <destVar> <slot>`: buffer 0 the nickname,
-- answer the species.
function Commands.g4_daycare_withdraw(ctx, destVar, slot)
  local DC = require("src.pokemon.Gen4DayCare")
  local i = math.floor(valueOf(ctx, slot))
  local s = DC.slot(ctx.save, i)
  if s and s.mon then setBuffer(ctx, 0, dcMonName(ctx, s.mon)) end
  setVar(ctx.save, destVar, DC.withdraw(ctx.game.data, ctx.save, i))
end

-- `bufferdaycarepricebyslot <destVar> <slot>`: buffer 0 the name, 1 the price.
function Commands.g4_daycare_price(ctx, destVar, slot)
  local DC = require("src.pokemon.Gen4DayCare")
  local i = math.floor(valueOf(ctx, slot))
  local s = DC.slot(ctx.save, i)
  local price = DC.price(ctx.game.data, ctx.save, i)
  if s and s.mon then setBuffer(ctx, 0, dcMonName(ctx, s.mon)) end
  setBuffer(ctx, 1, tostring(price))
  setVar(ctx.save, destVar, price)
end

-- `bufferdaycaregainedlevelsbyslot <destVar> <slot>`: buffer 0 the name, 1 the levels.
function Commands.g4_daycare_gained(ctx, destVar, slot)
  local DC = require("src.pokemon.Gen4DayCare")
  local i = math.floor(valueOf(ctx, slot))
  local s = DC.slot(ctx.save, i)
  local n = 0
  if s and s.mon then
    n = DC.gainedLevels(ctx.game.data, ctx.save, i)
    setBuffer(ctx, 1, tostring(n))
    setBuffer(ctx, 0, dcMonName(ctx, s.mon))
  end
  setVar(ctx.save, destVar, n)
end

-- `bufferpartymonnicknamereturnspecies <unused> <partySlot> <destVar>`
function Commands.g4_buffer_nickname_species(ctx, slot, destVar)
  local mon = partyMon(ctx, slot)
  setBuffer(ctx, 0, dcMonName(ctx, mon))
  setVar(ctx.save, destVar, mon and require("src.pokemon.Gen4DayCare").speciesOf(mon) or 0)
end

-- HGSS GetTailDaycareMonSpeciesAndNick <var>: the second Pokemon when there
-- are two, else the first -- its species to `var`, its name to buffer 0
function Commands.g4_daycare_tail(ctx, destVar)
  local DC = require("src.pokemon.Gen4DayCare")
  local a, b = DC.slot(ctx.save, 0), DC.slot(ctx.save, 1)
  local s = (b and b.mon) and b or a
  if s and s.mon then
    setBuffer(ctx, 0, dcMonName(ctx, s.mon))
    setVar(ctx.save, destVar, DC.speciesOf(s.mon) or 0)
  else
    setVar(ctx.save, destVar, 0)
  end
end

function Commands.g4_daycare_store(ctx, slot)
  require("src.pokemon.Gen4DayCare").deposit(ctx.game.data, ctx.save, math.floor(valueOf(ctx, slot)))
end

-- Daycare_BufferNicknameLevelGender: the level with the banked EXP, and no
-- gender sign for an un-nicknamed Nidoran (the sign is in its name).
function Commands.g4_daycare_name_level_gender(ctx, nick, level, gender, slot)
  local DC = require("src.pokemon.Gen4DayCare")
  local s = DC.slot(ctx.save, math.floor(valueOf(ctx, slot)))
  if not (s and s.mon) then return end
  local data = ctx.game.data
  setBuffer(ctx, valueOf(ctx, nick), dcMonName(ctx, s.mon))
  setBuffer(ctx, valueOf(ctx, level), tostring(DC.levelWithSteps(data, s)))
  local g = DC.gender(data, s.mon)
  local sp = DC.speciesOf(s.mon)
  if (sp == 29 or sp == 32) and not s.mon.nickname then g = "none" end
  setBuffer(ctx, valueOf(ctx, gender), g == "male" and "♂" or g == "female" and "♀" or "")
end

function Commands.g4_daycare_compatibility(ctx, destVar)
  setVar(ctx.save, destVar, require("src.pokemon.Gen4DayCare").compatibilityLevel(ctx.game.data, ctx.save))
end

-- `checkmoney2 <destVar> <amount>` -- the amount through ScriptContext_GetVar.
function Commands.g4_check_money_var(ctx, destVar, amount)
  return Commands.g4_check_money(ctx, destVar, valueOf(ctx, amount))
end

-- `openpartymenufordaycare` / `getdaycarepartymenuresult <slotVar> <summaryVar>`:
-- the party pick; the SUMMARY exit never comes back from this port's picker,
-- so the second answer is always FALSE.
function Commands.g4_daycare_party_menu(ctx)
  return Commands.g4_open_party_for_trade(ctx)
end
Commands.meta.g4_daycare_party_menu = { foreground = true, blocking = true }

function Commands.g4_daycare_party_result(ctx, slotVar, summaryVar)
  setVar(ctx.save, slotVar, ctx.g4PartySlot or Gen4Commands.PARTY_SLOT_NONE)
  setVar(ctx.save, summaryVar, 0)
end

-- `setmonsummary <slot>` / `getmonpartyslot <destVar>`: the summary screen
-- and the slot it was left on -- the one it opened on, here.
function Commands.g4_set_mon_summary(ctx, slot)
  ctx.g4SummarySlot = math.floor(valueOf(ctx, slot))
end

function Commands.g4_get_mon_party_slot(ctx, destVar)
  setVar(ctx.save, destVar, ctx.g4SummarySlot or 0)
  ctx.g4SummarySlot = nil
end

-- ScrCmd_TryRevertPokemonForm: a held Griseous Orb goes back to the bag (0xFF
-- when it will not fit), and Giratina, Rotom and Shaymin go to their base forms.
function Commands.g4_try_revert_form(ctx, slot, destVar)
  setVar(ctx.save, destVar, 0)
  local raw = math.floor(valueOf(ctx, slot))
  if raw == 0xFF then return end
  local mon = partyMon(ctx, slot)
  if not mon then return end
  local item = tonumber(mon.item or mon.heldItem) or 0
  if item == 112 then
    local Bag = require("src.inventory.Bag")
    if Bag.add(ctx.save, 112, 1, ctx.game.data) == false then
      setVar(ctx.save, destVar, 0xFF)
      return
    end
    mon.item, mon.heldItem = nil, nil
  end
  local sp = require("src.pokemon.Gen4DayCare").speciesOf(mon)
  if (tonumber(mon.form) or 0) > 0 and (sp == 487 or sp == 479 or sp == 492) then
    require("src.pokemon.Gen4Forms").setForm(ctx.game.data, mon, 0)
  end
end

-- `checkpoketchenabled <destVar>`
function Commands.g4_poketch_enabled(ctx, destVar)
  local p = ctx.save and ctx.save.poketch
  setVar(ctx.save, destVar, (p and p.enabled) and 1 or 0)
end

-- `checkpartyhasbadegg <destVar>`: an egg that failed its checksum. This port
-- keeps no checksum, so only an egg explicitly marked bad counts.
function Commands.g4_party_has_bad_egg(ctx, destVar)
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if mon.isEgg and (mon.isBadEgg or mon.badEgg) then setVar(ctx.save, destVar, 1) return end
  end
  setVar(ctx.save, destVar, 0)
end

-- ScrCmd_IncreasePartyMonFriendship <value> <slot>: a Soothe Bell makes it
-- 150%, a Luxury Ball and being in the place it hatched add one each; capped
-- at 255.
function Commands.g4_increase_friendship(ctx, value, slot)
  local mon = partyMon(ctx, slot)
  if not mon then return end
  local v = math.floor(valueOf(ctx, value))
  if v > 0 then
    if tonumber(mon.item or mon.heldItem) == 218 then v = math.floor(v * 150 / 100) end
    if tonumber(mon.ball) == 11 or mon.ball == "LUXURY_BALL" then v = v + 1 end
    local here = ctx.overworld and ctx.overworld.map and ctx.overworld.map.id
    if here and mon.eggLocation and mon.eggLocation == here then v = v + 1 end
  end
  local f = tonumber(mon.happiness or mon.friendship) or 0
  mon.happiness = math.max(0, math.min(255, f + v))
end

-- THE VEILSTONE GAME CORNER (scrcmd_coins.c, scrcmd_game_corner_prize.c) --
-- see src/import/Gen4GameCorner.lua. Coins live in save.coins, which the
-- Coin Case already reads.
local function GC() return require("src.import.Gen4GameCorner") end

function Commands.g4_coin_window(ctx, which, left, top)
  local ow = ctx.overworld
  if not ow then return end
  if which == "hide" then ow.gen4CoinWindow = nil return end
  local MW = require("src.ui.Gen4MoneyWindow")
  if which == "show" then
    ow.gen4CoinWindow = MW.coinPanelFor(ctx.game, valueOf(ctx, left), valueOf(ctx, top))
  elseif ow.gen4CoinWindow then
    ow.gen4CoinWindow = MW.coinPanelFor(ctx.game, ow.gen4CoinWindow.left, ow.gen4CoinWindow.top)
  end
end

-- HGSS's POINTS BOX (overlay_22.c ScrCmd_116 / 117 / 118 -> ov01_021EEC00 /
-- EEC68 / EEC7C): a 10 x 2 window at (x, y) holding, by `kind`, the coins
-- (msg_0191 #193), the Battle Points (#220) or the Pokeathlon's athlete points
-- (#223), the number in five space-padded digits right-aligned in 80 px --
-- Platinum's coin window in all but the bank and the three kinds.
Commands.HGSS_POINTS = { [0] = 193, [1] = 220, [2] = 223 }
function Commands.g4_points_window(ctx, which, kind, left, top)
  local ow = ctx.overworld
  if not ow then return end
  if which == "hide" then ow.gen4CoinWindow = nil return end
  local was = ow.gen4CoinWindow
  if which == "update" and not was then return end
  local k = math.floor(valueOf(ctx, kind) or 0)
  local save = ctx.save or {}
  local n
  if k == 1 then n = require("src.pokemon.Gen4BattleTower").bp(save)
  elseif k == 2 then n = tonumber(save.hgssAthletePoints) or 0
  else n = GC().coins(save) end
  local digits = tostring(math.floor(n))
  local amount = (" "):rep(math.max(0, 5 - #digits)) .. digits
  local game = ctx.game or {}
  local saved = game.stringBuffers and game.stringBuffers[1]
  local Text = require("src.import.Gen4Text")
  Text.buffer(game, amount)
  local line = Text.resolve(game.data, 191, Commands.HGSS_POINTS[k] or 193, game)
  if game.stringBuffers then game.stringBuffers[1] = saved end
  if type(line) ~= "string" or line == "" then line = amount end
  ow.gen4CoinWindow = {
    left = which == "show" and math.floor(valueOf(ctx, left) or 0) or was.left,
    top = which == "show" and math.floor(valueOf(ctx, top) or 0) or was.top,
    amount = line, coins = true, tilesW = 10, tilesH = 2,
  }
end

-- HGSS MomGiftCheck: 1 while Mom's gift queue holds anything
function Commands.g4_mom_gift_check(ctx, destVar)
  local q = ctx.save and ctx.save.hgssMomGifts
  setVar(ctx.save, destVar, (type(q) == "table" and #q > 0) and 1 or 0)
end

-- HGSS ScrCmd_840: the map's kind by header id -- the 25 rows of
-- sPokemonCenterMaps (MAP_EVERYWHERE, 0, included) answer 1, the Pokemon
-- League's entrance (MAP_T10R0101, 300) answers 2
Commands.HGSS_POKECENTERS = { [501] = true, [475] = true, [428] = true, [434] = true,
  [358] = true, [393] = true, [482] = true, [508] = true, [407] = true, [69] = true,
  [158] = true, [166] = true, [236] = true, [185] = true, [226] = true, [81] = true,
  [246] = true, [293] = true, [514] = true, [511] = true, [466] = true, [169] = true,
  [528] = true, [534] = true, [0] = true }
function Commands.g4_hgss_map_kind(ctx, mapId, destVar)
  local id = math.floor(valueOf(ctx, mapId) or -1)
  local kind = Commands.HGSS_POKECENTERS[id] and 1 or (id == 300 and 2 or 0)
  setVar(ctx.save, destVar, kind)
end

-- HGSS's Magikarp length record -- see src/pokemon/HgssSizeRecord.lua
function Commands.g4_size_record(ctx, op, a, b, c)
  local S = require("src.pokemon.HgssSizeRecord")
  local data = ctx.game and ctx.game.data
  local save = ctx.save or {}
  local function buffer(slot, text)
    if not ctx.game then return end
    ctx.game.stringBuffers = ctx.game.stringBuffers or {}
    ctx.game.stringBuffers[(tonumber(slot) or 0) + 1] = text
  end
  if op == "compare" then
    setVar(save, a, S.compare(data, save, partyMon(ctx, b)))
  elseif op == "update" then
    local mon = partyMon(ctx, a)
    if mon then save.hgssSizeRecord = S.hash(mon) end
  elseif op == "mon" then
    local mon = partyMon(ctx, c)
    if not mon then return end
    local whole, tenth = S.format(data, tonumber(mon.species) or 0, S.hash(mon))
    buffer(valueOf(ctx, a), whole)
    buffer(valueOf(ctx, b), tenth)
  elseif op == "record" then
    local whole, tenth = S.format(data, math.floor(valueOf(ctx, c) or 0), S.record(save))
    buffer(valueOf(ctx, a), whole)
    buffer(valueOf(ctx, b), tenth)
  end
end

-- a string slot filled with entry <entry> of message bank <bank>, markup run
function Commands.g4_buffer_bank_line(ctx, slot, bank, entry)
  if not ctx.game then return end
  local T = require("src.import.Gen4Text")
  local data = ctx.game.data
  local text = data and data.text and data.text[T.label(tonumber(bank) or 0, math.floor(valueOf(ctx, entry) or 0))]
  if Commands.gen4Markup then text = Commands.gen4Markup(text, ctx.game) end
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[(tonumber(slot) or 0) + 1] = type(text) == "string" and text or ""
end

-- BUENA'S PASSWORD (sys_vars.c Save_VarsFlags_UpdateBuenasPasswordSet, run by
-- the new-day handler): VAR_BUENAS_PASSWORD_SET (0x4033) is rerolled once a
-- day to LCRandom() % 30, never the same set twice running; the show reads
-- category line msg_0066 #40 + 3 * (set / 3) and password set % 3
-- (the day's set, rolled on its first ask -- the radio show announces this
-- same set, HgssGearRadio, so the show and Buena's desk must share it)
function Gen4Commands.buenasPasswordSet(save)
  save = save or {}
  local today = require("src.world.HgssApricorns").today()
  if save.hgssBuenasDay ~= today then
    local old = tonumber(getVar(save, 0x4033)) or 0
    local new = love.math.random(0, 29)
    if new == old then new = (new + 1) % 30 end
    setVar(save, 0x4033, new)
    save.hgssBuenasDay = today
  end
  return (tonumber(getVar(save, 0x4033)) or 0) % 30
end

function Commands.g4_buenas_password(ctx, msgVar, indexVar)
  local save = ctx.save or {}
  local set = Gen4Commands.buenasPasswordSet(save)
  setVar(save, msgVar, 40 + 3 * math.floor(set / 3))
  setVar(save, indexVar, set % 3)
end

-- HGSS's walking Pokemon -- see src/world/HgssFollowMon.lua
function Commands.g4_follow(ctx, op, a)
  local F = require("src.world.HgssFollowMon")
  local game, ow = ctx.game, ctx.overworld
  if not (game and F.active(game)) then
    if op == "active" then setVar(ctx.save, a, 0)
    elseif op == "inactive" then setVar(ctx.save, a, 1)
    elseif op == "tall" or op == "slot" then setVar(ctx.save, a, 0) end
    return
  end
  if op == "active" then setVar(ctx.save, a, F.isActive(game, ow) and 1 or 0)
  elseif op == "inactive" then setVar(ctx.save, a, F.isActive(game, ow) and 0 or 1)
  elseif op == "slot" then
    local _, i = F.lead(ctx.save)
    setVar(ctx.save, a, i and (i - 1) or 0)
  elseif op == "tall" then
    local mon = F.lead(ctx.save)
    setVar(ctx.save, a, (mon and not F.allowedIndoors(game, mon)) and 1 or 0)
  elseif op == "mood" then
    local mon = F.lead(ctx.save)
    local d = math.floor(valueOf(ctx, a) or 0)
    if d >= 128 then d = d - 256 end
    if mon then mon.hgssMood = math.max(-127, math.min(127, (tonumber(mon.hgssMood) or 0) + d)) end
  elseif op == "movement" then
    -- 56 hides it (tracking the player), 48 / 55 trail as usual
    local t = math.floor(valueOf(ctx, a) or 48)
    F.command(game, ow, t == 56 and "recall" or "unrecall")
  elseif op == "talk" then
    local npc = ow and F.current(ow)
    if npc and not npc.hidden then F.talk(game, ow, npc) end
  else
    F.command(game, ow, op, a and valueOf(ctx, a))
  end
end

-- HEARTGOLD / SOULSILVER `AlphPuzzle <n>` (ScrCmd_AlphPuzzle): the sliding
-- puzzle, which sets FLAG_SYS_ALPH_PUZZLE_* itself when solved
function Commands.g4_alph_puzzle(ctx, which)
  local game = ctx.game
  local AP = require("src.ui.HgssAlphPuzzle")
  if not (game and game.stack and AP.available(game)) then
    Logger.warn("hgss alph puzzle: the art is not in this cache (re-import HeartGold / "
                .. "SoulSilver: hgss_screens) -- the slab does nothing")
    return
  end
  game.stack:push(AP.new(game, math.floor(valueOf(ctx, which) or 0), function()
    if ctx.runner then ctx.runner:resume() end
  end))
  if ctx.runner then ctx.runner:yield() end
end
Commands.meta.g4_alph_puzzle = { foreground = true, blocking = true }

-- ---------------------------------------------------------------------------
-- HEARTGOLD / SOULSILVER'S CERTIFICATES AND THE POKEATHLON'S NUMBERS
-- ---------------------------------------------------------------------------

-- ShowCertificate <id> (certificates_app.c): blocks until the sheet closes
function Commands.g4_hgss_certificate(ctx, which)
  local game = ctx.game
  local Cert = require("src.ui.HgssCertificate")
  local id = math.floor(valueOf(ctx, which) or 0)
  if not (game and game.stack and Cert.available(game, id)) then
    Logger.warn("hgss certificate: the art is not in this cache (re-import HeartGold / "
                .. "SoulSilver: hgss_screens) -- nothing is shown")
    return
  end
  game.stack:push(Cert.new(game, id, function()
    if ctx.runner then ctx.runner:resume() end
  end))
  if ctx.runner then ctx.runner:yield() end
end
Commands.meta.g4_hgss_certificate = { foreground = true, blocking = true }

-- PokeathlonSave_Add/SubAthletePoints clamp to 0..99999; CheckAthletePoints
-- answers TRUE when the points reach `amount`
Commands.ATHLETE_POINTS_MAX = 99999
function Commands.g4_athlete_points(ctx, op, amount, destVar)
  local save = ctx.save
  if not save then return end
  local have = tonumber(save.hgssAthletePoints) or 0
  local n = math.floor(valueOf(ctx, amount) or 0)
  if op == "give" then
    save.hgssAthletePoints = math.min(Commands.ATHLETE_POINTS_MAX, have + n)
  elseif op == "take" then
    save.hgssAthletePoints = math.max(0, have - n)
  else
    setVar(save, destVar, have >= n and 1 or 0)
  end
end

-- ScrCmd_724 / 725 (field/scrcmd_pokemon_misc.c): the Pokeathlon save's
-- records -- 0..9 the per-event tallies (unk44[]), 10..17 the totals
-- (unk8, unk70, unk4, unk14, unk1C, unk24, unk2C, unk30); a read is capped at
-- 0xFFFF and an unknown index reads 0. 725 adds to / takes from record 11
-- (unk70), clamped to 0..0xFFFF.
function Commands.g4_athlon_record(ctx, op, a, b)
  local save = ctx.save
  if not save then return end
  save.hgssPokeathlonRecords = save.hgssPokeathlonRecords or {}
  local rec = save.hgssPokeathlonRecords
  if op == "get" then
    local which = math.floor(valueOf(ctx, a) or 0) % 256
    local v = (which <= 17) and (tonumber(rec[which]) or 0) or 0
    setVar(save, b, math.min(0xFFFF, v))
  else
    local n = math.floor(valueOf(ctx, b) or 0)
    local cur = tonumber(rec[11]) or 0
    if math.floor(tonumber(a) or 0) == 0 then cur = math.min(0xFFFF, cur + n)
    else cur = math.max(0, cur - n) end
    rec[11] = cur
  end
end

-- ScrCmd_405: TRUE when at least `n` of Accessory `id` are in the case
function Commands.g4_has_accessories(ctx, id, n, destVar)
  local have = Gen4Commands.accessoryCount(ctx.save, math.floor(valueOf(ctx, id) or 0))
  setVar(ctx.save, destVar, math.floor(valueOf(ctx, n) or 0) <= have and 1 or 0)
end

-- ScrCmd_553: TRUE when LCRandom() % 101 <= limit (limit capped at 100)
function Commands.g4_percent_roll(ctx, limit, destVar)
  local lim = math.min(100, math.floor(valueOf(ctx, limit) or 0))
  local roll = love and love.math and love.math.random(0, 100) or math.random(0, 100)
  setVar(ctx.save, destVar, roll <= lim and 1 or 0)
end

-- ScrCmd_622: an object's facing as DIR_*, DIR_NORTH when it is not there
function Commands.g4_object_facing(ctx, id, destVar)
  local e = objectById(ctx, id)
  setVar(ctx.save, destVar, e and (FACING[e.facing] or 0) or 0)
end

-- THE GOLDENROD UNDERGROUND'S ACCESSORY LOTTERY (overlay_02_02251E74.c):
-- ov02_02253D54's 39 Accessories and the 14 backdrops
Commands.HGSS_LOTTERY_ACCESSORIES = { 47, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
  70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 95, 96 }
Commands.HGSS_BACKDROPS = 14
function Commands.g4_hgss_accessory_lottery(ctx, op, destVar)
  local save = ctx.save
  if not save then return end
  local list = Commands.HGSS_LOTTERY_ACCESSORIES
  local owned = save.gen4Backdrops or {}
  local function rnd(n) return love and love.math and love.math.random(0, n - 1) or math.random(0, n - 1) end
  local v = 0
  if op == "soldOut" then
    v = 1
    for _, id in ipairs(list) do
      if Gen4Commands.canFitAccessory(save, id, 1) then v = 0 break end
    end
  elseif op == "draw" then
    v = list[rnd(#list) + 1]
  elseif op == "allBackdrops" then
    v = 1
    for i = 0, Commands.HGSS_BACKDROPS - 1 do if not owned[i] then v = 0 break end end
  else
    local missing = {}
    for i = 0, Commands.HGSS_BACKDROPS - 1 do if not owned[i] then missing[#missing + 1] = i end end
    v = #missing > 0 and missing[rnd(#missing) + 1] or 0
  end
  setVar(save, destVar, v)
end

-- ---------------------------------------------------------------------------
-- HEARTGOLD / SOULSILVER'S FIELD MOVES (scr_seq_0146's tail)
-- ---------------------------------------------------------------------------
-- (the file's own `speciesOf` / `lcrng` are declared further down)
local function speciesOf(mon) return require("src.pokemon.Gen4DayCare").speciesOf(mon) end
local function lcrng(n) return love and love.math and love.math.random(0, n - 1) or math.random(0, n - 1) end

-- Capitalize <slot>: MessageFormat_UpperFirstChar
function Commands.g4_capitalize(ctx, slot)
  local bufs = ctx.game and ctx.game.stringBuffers
  local i = math.floor(valueOf(ctx, slot) or 0) + 1
  local s = bufs and bufs[i]
  if type(s) ~= "string" or s == "" then return end
  -- past any leading markup ({COLOR 255}a Potion -> {COLOR 255}A Potion)
  local at = 1
  while s:sub(at, at) == "{" do
    local close = s:find("}", at, true)
    if not close then break end
    at = close + 1
  end
  if at <= #s then bufs[i] = s:sub(1, at - 1) .. s:sub(at, at):upper() .. s:sub(at + 1) end
end

-- the lead Pokemon's ability, by name
local function leadAbility(ctx)
  local data = ctx.game and ctx.game.data
  local mon = ((ctx.save and ctx.save.party) or {})[1]
  if not (mon and data and data.pokemon) or mon.isEgg then return nil end
  local def = data.pokemon[speciesOf(mon)]
  local list = def and def.abilities or {}
  local a = list[tonumber(mon.abilitySlot) or 1]
  if a == nil or a == 0 or a == "NONE" then a = list[1] end
  return a
end

-- EncounterSlot_WildMonLevelRoll: a level in the slot's range
local function rollLevel(slot)
  local lo, hi = tonumber(slot.minLevel) or 1, tonumber(slot.maxLevel) or 1
  if hi < lo then lo, hi = hi, lo end
  return lo + lcrng(hi - lo + 1)
end

-- EncounterGen_DoesRepelSuppressEncounter: a Repel in effect turns away
-- anything below the lead's level
local function repelled(ctx, level)
  local save = ctx.save
  if not (save and (tonumber(save.repelSteps) or 0) > 0) then return false end
  for _, mon in ipairs(save.party or {}) do
    if not mon.isEgg then return level < (tonumber(mon.level) or 0) end
  end
  return false
end

local function fieldMoveData(ctx)
  return ctx.game and ctx.game.data and ctx.game.data.gen4_hgss_field_moves
end

local function headerOf(ctx)
  local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
  return def and tonumber(def.header), def
end

-- Whirlpool <slot>: carried across the whirlpool's run, as Waterfall climbs
-- its own (TILE_BEHAVIOR_WHIRLPOOL, 0x11)
function Commands.g4_use_whirlpool(ctx)
  local ow = ctx.overworld
  local p = ow and ow.player
  local map = ow and ow.map
  if not (p and map and map.cellBehaviour) then return end
  local Collision = require("src.world.Collision")
  local x, y, n = p.cellX, p.cellY, 0
  while n < 8 do
    local nx, ny = Collision.target(x, y, p.facing)
    if not map:inBounds(nx, ny) or map:cellBehaviour(nx, ny) ~= 0x11 then break end
    x, y, n = nx, ny, n + 1
  end
  if n > 0 and ow.scriptMove then ow:scriptMove(p, p.facing, n + 1) end
end

-- TryHeadbuttEncounter <var> (field/headbutt.c): the tree in front -- one
-- further when the walking Pokemon stands there -- picks the table by the
-- tree's index and the trainer id's last digit (sRareTreeLUT_*): common, rare,
-- secret or none; then a 50/15/15/10/5/5 slot and a level in its range
local TREE_LUT = {
  [1] = { [0] = { 0 }, { 1 }, { 0 }, { 1 }, { 0 }, { 1 }, { 0 }, { 1 }, { 0 }, { 1 } },
  [2] = { [0] = { 0, 1 }, { 1, 0 }, { 0, 1 }, { 1, 0 }, { 0, 1 }, { 1, 0 }, { 0, 1 }, { 1, 0 }, { 0, 1 }, { 1, 0 } },
  [3] = { [0] = { 0, 1, -1 }, { 0, -1, 1 }, { 1, 0, -1 }, { 1, -1, 0 }, { -1, 0, 1 },
          { -1, 1, 0 }, { 0, 1, -1 }, { 0, -1, 1 }, { 1, 0, -1 }, { 1, -1, 0 } },
  [4] = { [0] = { -1, 0, 0, 1 }, { 1, -1, 0, 0 }, { 1, 1, -1, 0 }, { 0, 1, 1, -1 }, { 0, 0, 1, 1 },
          { -1, 0, 1, 0 }, { 1, -1, 0, 1 }, { 0, 1, -1, 0 }, { 1, 0, 1, -1 }, { 0, 1, 0, 1 } },
  [5] = { [0] = { -1, 0, 0, 1, 1 }, { 1, -1, 0, 0, 1 }, { 1, 1, -1, 0, 0 }, { 0, 1, 1, -1, 0 },
          { 0, 0, 1, 1, -1 }, { -1, 0, 1, 0, 1 }, { 1, -1, 0, 1, 0 }, { 0, 1, -1, 0, 1 },
          { 1, 0, 1, -1, 0 }, { 0, 1, 0, 1, -1 } },
}
Gen4Commands.HEADBUTT_TREE_LUT = TREE_LUT

function Gen4Commands.headbuttTreeType(rec, trainerId, x, y)
  local reg = (rec.regular or 0) * 6
  for i = 1, reg do
    local c = rec.trees[i]
    if c and c[1] == x and c[2] == y then
      local which = math.floor((i - 1) / 6)
      local digit = (tonumber(trainerId) or 0) % 10
      local n = rec.regular
      if n >= 5 then return TREE_LUT[5][digit][which % 5 + 1] end
      return TREE_LUT[n][digit][which + 1]
    end
  end
  for i = reg + 1, reg + (rec.secret or 0) * 6 do
    local c = rec.trees[i]
    if c and c[1] == x and c[2] == y then return 2 end
  end
  return -1
end

local function headbuttSlot()
  local r = lcrng(100)
  if r < 50 then return 1 elseif r < 65 then return 2 elseif r < 80 then return 3
  elseif r < 90 then return 4 elseif r < 95 then return 5 end
  return 6
end

function Commands.g4_hgss_headbutt(ctx, destVar)
  setVar(ctx.save, destVar, 0)
  local all = fieldMoveData(ctx)
  local header = headerOf(ctx)
  local rec = all and all.headbutt and header and all.headbutt[header]
  local ow = ctx.overworld
  local p = ow and ow.player
  if not (rec and p) then return end
  local fx, fy = p:facingCell()
  -- GetCoordsOfFacingTree: past the walking Pokemon when it is the one ahead
  local okF, F = pcall(require, "src.world.HgssFollowMon")
  local npc = okF and F.current and F.current(ow)
  if npc and not npc.hidden and npc.cellX == fx and npc.cellY == fy then
    fx, fy = require("src.world.Collision").target(fx, fy, npc.facing or p.facing)
  end
  local gx, gy = toMatrix(ctx, fx, fy)
  local pl = ctx.save.player or {}
  local tid = ((tonumber(pl.id) or 0) % 65536) + ((tonumber(pl.secretId) or 0) % 65536) * 65536
  local kind = Gen4Commands.headbuttTreeType(rec, tid, gx, gy)
  if kind < 0 then return end
  local slots = (kind == 0 and rec.common) or (kind == 1 and rec.rare) or rec.secretSlots
  -- FieldSystem_PerformHeadbuttEncounterCheck -> GenerateRegularEncounter:
  -- the lead's Magnet Pull / Static slot, its level roll, Keen Eye /
  -- Intimidate -- and NOT Repel (isRepel is set only by the step check)
  local enc = require("src.script.Gen4FieldEncounters").headbutt(ctx, slots, headbuttSlot, rollLevel)
  if not enc then return end
  setVar(ctx.save, destVar, 1)
  Commands.start_battle(ctx, "wild", enc.species, enc.level)
end
Commands.meta.g4_hgss_headbutt = { foreground = true, blocking = true }

-- RockSmashItemCheck <followUsed, foundVar, itemVar> (field/rock_smash_item.c):
-- the map's rock smash encounter first (its rate, slots 80 / 20), else an item
-- -- the map's odds (+5 each for Suction Cups, Magnet Pull, Keen Eye and the
-- walking Pokemon doing it, at most 100), then a 25/20/10/10/10/10/10/5 draw
-- from the map's table, one further for Serene Grace or Super Luck
local ROCK_SMASH_ITEMS = {
  heartgold = {
    [0] = { 39, 28, 93, 72, 73, 75, 74, 91 },      -- Max Ether .. Star Piece
    { 72, 74, 101, 39, 73, 75, 103, 29 },          -- Ruins of Alph (Helix Fossil)
    { 39, 88, 89, 72, 74, 100, 100, 106 },         -- Cliff Cave (Claw Fossil)
  },
  soulsilver = {
    [0] = { 39, 28, 93, 72, 73, 75, 74, 91 },
    { 73, 75, 102, 39, 72, 74, 103, 29 },          -- Ruins of Alph (Dome Fossil)
    { 39, 88, 89, 73, 75, 99, 99, 106 },           -- Cliff Cave (Root Fossil)
  },
}
Gen4Commands.ROCK_SMASH_ITEMS = ROCK_SMASH_ITEMS

local function rockSmashIndex()
  local r = lcrng(100)
  if r < 25 then return 0 elseif r < 45 then return 1 elseif r < 55 then return 2
  elseif r < 65 then return 3 elseif r < 75 then return 4 elseif r < 85 then return 5
  elseif r < 95 then return 6 end
  return 7
end

function Commands.g4_hgss_rock_smash(ctx, followUsed, foundVar, itemVar)
  setVar(ctx.save, foundVar, 0)
  setVar(ctx.save, itemVar, 0)
  local data = ctx.game and ctx.game.data
  local header, def = headerOf(ctx)
  -- the encounter (FieldSystem_PerformRockSmashEncounterCheck)
  local enc = data and data.encounters and def and data.encounters[def.encounters]
  local rs = enc and enc.rockSmash
  -- ApplyAbilityEffectToEncounterRate on the rate, then the regular
  -- generator (lead abilities; Repel does not apply)
  local FE = require("src.script.Gen4FieldEncounters")
  -- the save's weather: Snow Cloak halves it in WEATHER_SNOW (5)
  local rate = FE.rockSmashRate(ctx, rs and tonumber(rs.rate) or 0,
    (tonumber(ctx.save and ctx.save.gen4WeatherActive) == 5) and "snow" or nil)
  if rate > 0 and lcrng(100) < rate then
    local smash = FE.rockSmash(ctx, rs.slots, rollLevel)
    if smash then
      Commands.start_battle(ctx, "wild", smash.species, smash.level)
      return
    end
  end
  -- the item (CheckRockSmashItemDrop / Task_GetRockSmashItem)
  local all = fieldMoveData(ctx)
  local odds = all and all.rockSmash and header and all.rockSmash[header]
  if not odds or (odds.odds or 0) == 0 then return end
  local chance = odds.odds
  local ability = leadAbility(ctx)
  if ability == "SUCTION_CUPS" or ability == "MAGNET_PULL" or ability == "KEEN_EYE" then chance = chance + 5 end
  if math.floor(valueOf(ctx, followUsed) or 0) ~= 0 then chance = chance + 5 end
  if chance > 100 then chance = 100 end
  if lcrng(100) >= chance then return end
  local idx = rockSmashIndex()
  if (ability == "SERENE_GRACE" or ability == "SUPER_LUCK") and idx < 7 then idx = idx + 1 end
  local version = require("src.core.GameVersion").get and require("src.core.GameVersion").get() or "heartgold"
  local tables = ROCK_SMASH_ITEMS[version] or ROCK_SMASH_ITEMS.heartgold
  local list = tables[odds.type]
  local item = list and list[idx + 1]
  if not item then return end
  setVar(ctx.save, foundVar, 1)
  setVar(ctx.save, itemVar, item)
end
Commands.meta.g4_hgss_rock_smash = { foreground = true, blocking = true }

-- GetPlayerState <var>: PlayerAvatar_GetState -- 0 walking, 1 cycling,
-- 2 surfing (constants/global_fieldmap.h)
function Commands.g4_get_player_state(ctx, destVar)
  local p = ctx.overworld and ctx.overworld.player
  local state = 0
  if p and p.surfing then state = 2
  elseif ctx.save and ctx.save.onBike then state = 1 end
  setVar(ctx.save, destVar, state)
end

-- CountAliveMonsAndPC <var>: party Pokemon with HP that are not eggs, plus
-- every Pokemon in the boxes (PCStorage_CountMonsInAllBoxes)
function Commands.g4_count_alive_and_pc(ctx, destVar)
  local n = 0
  for _, mon in ipairs(ctx.save and ctx.save.party or {}) do
    local hp = tonumber(mon.hp or mon.currentHp) or 1
    if not mon.isEgg and hp ~= 0 then n = n + 1 end
  end
  if ctx.save then
    local Boxes = require("src.pokemon.Boxes")
    Boxes.ensure(ctx.save)
    for _, box in pairs(ctx.save.boxes or {}) do
      n = n + (tonumber(Boxes.used(box)) or 0)
    end
  end
  setVar(ctx.save, destVar, n)
end

-- PartyCountEgg <var>
function Commands.g4_party_egg_count(ctx, destVar)
  local n = 0
  for _, mon in ipairs(ctx.save and ctx.save.party or {}) do
    if mon.isEgg then n = n + 1 end
  end
  setVar(ctx.save, destVar, n)
end

-- CountTranformedRotomsInParty <count, firstSlot>: Rotom in a form other
-- than the base one, not eggs; the first such slot or 255
function Commands.g4_count_rotom_forms(ctx, countVar, firstVar)
  local n, first = 0, 255
  for i, mon in ipairs(ctx.save and ctx.save.party or {}) do
    local species = require("src.pokemon.Gen4DayCare").speciesOf(mon)
    if species == 479 and (tonumber(mon.form) or 0) ~= 0 and not mon.isEgg then
      if first == 255 then first = i - 1 end
      n = n + 1
    end
  end
  setVar(ctx.save, countVar, n)
  setVar(ctx.save, firstVar, first)
end

-- MonAddContestValue <slot, attribute, amount>: Cool..Tough, Sheen (0..5),
-- capped at 255 and left alone once Sheen is maxed
function Commands.g4_add_contest_value(ctx, slot, attribute, amount)
  local keys = { [0] = "cool", "beauty", "cute", "smart", "tough", "sheen" }
  local key = keys[math.floor(valueOf(ctx, attribute) or 99)]
  local mon = ((ctx.save and ctx.save.party) or {})[math.floor(valueOf(ctx, slot) or 0) + 1]
  if not (key and mon) then return end
  mon.contest = mon.contest or {}
  if (tonumber(mon.contest.sheen) or 0) == 255 then return end
  local v = (tonumber(mon.contest[key]) or 0) + math.floor(valueOf(ctx, amount) or 0)
  mon.contest[key] = math.min(255, v)
end

function Commands.g4_add_coins(ctx, amount)
  GC().add(ctx.save, math.floor(valueOf(ctx, amount)))
end

function Commands.g4_subtract_coins(ctx, amount)
  GC().subtract(ctx.save, math.floor(valueOf(ctx, amount)))
end

function Commands.g4_get_coins(ctx, destVar)
  setVar(ctx.save, destVar, GC().coins(ctx.save))
end

function Commands.g4_can_add_coins(ctx, destVar, amount)
  setVar(ctx.save, destVar, GC().canAdd(ctx.save, math.floor(valueOf(ctx, amount))) and 1 or 0)
end

-- `hascoinsfromvar` / `hascoinsfromvalue <destVar> <amount>`
function Commands.g4_has_coins(ctx, destVar, amount)
  setVar(ctx.save, destVar, GC().coins(ctx.save) >= math.floor(valueOf(ctx, amount)) and 1 or 0)
end

-- `getgamecornerprizedata <index> <itemVar> <priceVar>`
function Commands.g4_prize_data(ctx, index, itemVar, priceVar)
  local rec = ctx.game and ctx.game.data and ctx.game.data.gen4_game_corner
  local row = rec and rec.prizes and rec.prizes[math.floor(valueOf(ctx, index)) + 1]
  setVar(ctx.save, itemVar, row and row.item or 0)
  setVar(ctx.save, priceVar, row and row.price or 0)
end

-- `checkbonusroundstreak`: ten consecutive bonus-round wins or more.
function Commands.g4_bonus_streak(ctx, destVar)
  setVar(ctx.save, destVar, (tonumber(ctx.save and ctx.save.gen4BonusRoundStreak) or 0) >= 10 and 1 or 0)
end

-- `showlistmenuremembercursor <offsetVar> <cursorVar>`: the list opens where
-- it was left and writes the cursor back as it moves.
function Commands.g4_menu_show_remember(ctx, offsetVar, cursorVar)
  local menu = ctx.g4Menu
  if menu then
    menu.cursor = math.floor(getVar(ctx.save, offsetVar) or 0) + math.floor(getVar(ctx.save, cursorVar) or 0) + 1
    menu.onHighlight = function(i)
      setVar(ctx.save, offsetVar, 0)
      setVar(ctx.save, cursorVar, i - 1)
    end
  end
  return Commands.g4_menu_show(ctx)
end
Commands.meta.g4_menu_show_remember = { foreground = true, blocking = true }

-- `buffervarpaddingdigits <slot> <var> <padding> <digits>`
function Commands.g4_buffer_padded_var(ctx, slot, value, padding, digits)
  return Commands.g4_buffer_padded_number(ctx, slot, valueOf(ctx, value), padding, digits)
end

-- `buffertypename <slot> <type>`: bank 624, TEXT_BANK_POKEMON_TYPE_NAMES.
function Commands.g4_buffer_type_name(ctx, slot, typeVar)
  local t = math.floor(valueOf(ctx, typeVar))
  local Gen4Text = require("src.import.Gen4Text")
  local data = ctx.game and ctx.game.data
  -- HeartGold / SoulSilver keep the type names in their own bank (735,
  -- Gen4Versions' typeName); their bank 624 is an NPC's dialogue
  local bank = 624
  if require("src.import.Gen4ScriptBands").family == "hgss" then
    local okV, V = pcall(require, "src.import.Gen4Versions")
    bank = okV and V.OVERRIDES.heartgold.bank.typeName or 735
  end
  -- through the shared resolve, so the name lands in the slot without markup
  local text = Gen4Text.resolve(data, bank, t)
  -- Black / White: the constants stage's own type names (Gen 5's order)
  if require("src.import.Gen4ScriptBands").family == "bw" then
    local types = data and data.constants and data.constants.types
    text = types and types[t]
  end
  if not ctx.game then return end
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[(tonumber(slot) or 0) + 1] = text or ""
end

-- ScrCmd_CalcHiddenPowerType <partySlot> <destVar>: the low IV bits; 0xFFFF
-- for the sixteen species that cannot learn it.
local NO_HIDDEN_POWER = { [10] = true, [11] = true, [13] = true, [14] = true, [129] = true,
  [132] = true, [202] = true, [235] = true, [265] = true, [266] = true, [268] = true,
  [360] = true, [374] = true, [412] = true, [415] = true, [401] = true }
function Gen4Commands.hiddenPowerType(ivs)
  ivs = ivs or {}
  local function bit(k) return math.floor(tonumber(ivs[k]) or 0) % 2 end
  local n = bit("hp") + 2 * bit("attack") + 4 * bit("defense") + 8 * bit("speed")
            + 16 * bit("spatk") + 32 * bit("spdef")
  local t = math.floor(n * 15 / 63) + 1
  if t >= 9 then t = t + 1 end   -- TYPE_MYSTERY
  return t
end
function Commands.g4_hidden_power_type(ctx, slot, destVar)
  local mon = partyMon(ctx, slot)
  if not mon then return end
  local sp = require("src.pokemon.Gen4DayCare").speciesOf(mon)
  if not mon.isEgg and NO_HIDDEN_POWER[sp] then setVar(ctx.save, destVar, 0xFFFF) return end
  setVar(ctx.save, destVar, Gen4Commands.hiddenPowerType(mon.ivs))
end

-- `buffercustommessageword <slot> <word>` (StringTemplate_SetEasyChatWord)
function Commands.g4_buffer_message_word(ctx, slot, word)
  if not ctx.game then return end
  local text = require("src.pokemon.Gen4EasyChat").toString(ctx.game.data, valueOf(ctx, word))
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[math.floor(valueOf(ctx, slot)) + 1] = text
end

-- `bufferribbonname <slot> <ribbon>`: bank 535 (TEXT_BANK_RIBBON_NAMES), whose
-- entry for each of the 80 ribbons is its own id (sRibbonDataTable.nameID).
function Commands.g4_buffer_ribbon_name(ctx, slot, ribbon)
  if not ctx.game then return end
  local T = require("src.import.Gen4Text")
  local data = ctx.game.data
  local text = data and data.text and data.text[T.label(535, math.floor(valueOf(ctx, ribbon)))]
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[(tonumber(slot) or 0) + 1] = text or ""
end

-- THE OREBURGH MUSEUM (scrcmd_fossil.c): sFossilItemToSpeciesMapping, in order.
Gen4Commands.FOSSILS = {
  { item = 103, species = 142 },  -- Old Amber -> Aerodactyl
  { item = 101, species = 138 },  -- Helix Fossil -> Omanyte
  { item = 102, species = 140 },  -- Dome Fossil -> Kabuto
  { item = 99, species = 345 },   -- Root Fossil -> Lileep
  { item = 100, species = 347 },  -- Claw Fossil -> Anorith
  { item = 104, species = 410 },  -- Armor Fossil -> Shieldon
  { item = 105, species = 408 },  -- Skull Fossil -> Cranidos
}
local function bagCount(save, item)
  local inv = save and save.inventory or {}
  return tonumber(inv[item]) or tonumber(inv[tostring(item)]) or 0
end

function Commands.g4_fossil_count(ctx, destVar)
  local n = 0
  for _, f in ipairs(Gen4Commands.FOSSILS) do n = n + bagCount(ctx.save, f.item) end
  setVar(ctx.save, destVar, n)
end

function Commands.g4_species_from_fossil(ctx, destVar, item)
  local id = math.floor(valueOf(ctx, item))
  local species = 0
  for _, f in ipairs(Gen4Commands.FOSSILS) do
    if f.item == id then species = f.species break end
  end
  setVar(ctx.save, destVar, species)
end

-- `findfossilatthreshold <itemVar> <indexVar> <threshold>`: the running total
-- in table order, and the first fossil at which it reaches the threshold.
function Commands.g4_fossil_at_threshold(ctx, itemVar, indexVar, threshold)
  local want = math.floor(valueOf(ctx, threshold))
  setVar(ctx.save, itemVar, 0)
  setVar(ctx.save, indexVar, 0)
  local n = 0
  for i, f in ipairs(Gen4Commands.FOSSILS) do
    n = n + bagCount(ctx.save, f.item)
    if n >= want then
      setVar(ctx.save, itemVar, f.item)
      setVar(ctx.save, indexVar, i - 1)
      return
    end
  end
end

-- `getpartyrotomcountandfirst <countVar> <slotVar>`: Rotom not in its base form.
function Commands.g4_party_rotom_forms(ctx, countVar, slotVar)
  local n, first = 0, Gen4Commands.PARTY_SLOT_NONE
  for i, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    local sp = require("src.pokemon.Gen4DayCare").speciesOf(mon)
    if sp == 479 and (tonumber(mon.form) or 0) ~= 0 and not mon.isEgg then
      if first == Gen4Commands.PARTY_SLOT_NONE then first = i - 1 end
      n = n + 1
    end
  end
  setVar(ctx.save, countVar, n)
  setVar(ctx.save, slotVar, first)
end

-- `loadpokedexrating <national> <destVar>` (Pokedex_GetRatingMessageID_*): the
-- entry in Rowan's or Oak's rating bank (pokedex_ratings, the map's own).
local LOCAL_RATING = { { 15, 6 }, { 30, 7 }, { 45, 8 }, { 60, 9 }, { 80, 10 }, { 100, 11 },
  { 120, 12 }, { 140, 13 }, { 160, 14 }, { 180, 15 }, { 200, 16 }, { 209, 17 } }
local NATIONAL_RATING = { { 39, 22 }, { 59, 23 }, { 89, 24 }, { 119, 25 }, { 149, 26 },
  { 189, 27 }, { 229, 28 }, { 269, 29 }, { 309, 30 }, { 349, 31 }, { 379, 32 }, { 409, 33 },
  { 429, "gender410" }, { 449, 36 }, { 459, 37 }, { 469, 38 }, { 475, 39 }, { 481, 40 } }
function Gen4Commands.dexRating(national, count, female, eterna)
  if not national then
    for _, r in ipairs(LOCAL_RATING) do if count <= r[1] then return r[2] end end
    return eterna and 4 or 5
  end
  for _, r in ipairs(NATIONAL_RATING) do
    if count <= r[1] then
      if r[2] == "gender410" then return female and 35 or 34 end
      return r[2]
    end
  end
  return female and 42 or 41
end
function Commands.g4_dex_rating(ctx, national, destVar)
  local nat = (tonumber(national) or 0) ~= 0
  local count = nat and dexCount(ctx, "owned", false, true) or dexCount(ctx, "seen", true, false)
  local female = ctx.save and ctx.save.player and ctx.save.player.gender == "girl"
  local eterna = ctx.save and ctx.save.flags and ctx.save.flags.FLAG_G4_09BB
  setVar(ctx.save, destVar, Gen4Commands.dexRating(nat, count, female, eterna))
end

-- `gethour <destVar>` (FieldSystem_GetHour)
function Commands.g4_get_hour(ctx, destVar)
  setVar(ctx.save, destVar, tonumber(os.date("*t").hour) or 0)
end

function Commands.g4_count_party_eggs(ctx, destVar)
  local n = 0
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do if mon.isEgg then n = n + 1 end end
  setVar(ctx.save, destVar, n)
end

-- ScrCmd_TryRevertPartyPokemonForms: every held Griseous Orb back to the bag
-- (0xFF when they will not fit), then Giratina, Rotom and Shaymin revert.
function Commands.g4_try_revert_party_forms(ctx, destVar)
  setVar(ctx.save, destVar, 0)
  local party = (ctx.save and ctx.save.party) or {}
  local orbs = 0
  for _, mon in ipairs(party) do if tonumber(mon.item or mon.heldItem) == 112 then orbs = orbs + 1 end end
  if orbs > 0 then
    if require("src.inventory.Bag").add(ctx.save, 112, orbs, ctx.game and ctx.game.data) == false then
      setVar(ctx.save, destVar, 0xFF)
      return
    end
    for _, mon in ipairs(party) do
      if tonumber(mon.item or mon.heldItem) == 112 then mon.item, mon.heldItem = nil, nil end
    end
  end
  for _, mon in ipairs(party) do
    local sp = require("src.pokemon.Gen4DayCare").speciesOf(mon)
    if (tonumber(mon.form) or 0) > 0 and (sp == 487 or sp == 479 or sp == 492) then
      require("src.pokemon.Gen4Forms").setForm(ctx.game and ctx.game.data, mon, 0)
    end
  end
end

-- `findpartyslotwithnature <destVar> <nature>`: first non-egg, else 0xFF.
function Commands.g4_party_slot_with_nature(ctx, destVar, nature)
  local want = math.floor(valueOf(ctx, nature))
  for i, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg and mon.personality and math.floor(tonumber(mon.personality)) % 25 == want then
      setVar(ctx.save, destVar, i - 1)
      return
    end
  end
  setVar(ctx.save, destVar, 0xFF)
end

-- THE REGI RUINS' DOTS (ScrCmd_ActivateRegiRuinsDot): standing on one of
-- the seven dots of the ruin sets its bit; all seven is state 260.
Gen4Commands.REGI_DOTS = {
  [588] = { { 4, 7 }, { 5, 5 }, { 5, 9 }, { 7, 7 }, { 9, 5 }, { 9, 9 }, { 10, 7 } },   -- Iron
  [590] = { { 3, 7 }, { 5, 7 }, { 7, 5 }, { 7, 7 }, { 7, 9 }, { 9, 7 }, { 11, 7 } },   -- Iceberg
  [592] = { { 5, 5 }, { 5, 7 }, { 5, 9 }, { 7, 7 }, { 9, 5 }, { 9, 7 }, { 9, 9 } },    -- Rock Peak
}
function Commands.g4_regi_dot(ctx, destVar, dotType, x, z)
  local dots = Gen4Commands.REGI_DOTS[math.floor(valueOf(ctx, dotType))]
  if not dots then return end
  local v = math.floor(getVar(ctx.save, destVar) or 0)
  local px, pz = math.floor(valueOf(ctx, x)), math.floor(valueOf(ctx, z))
  for i, d in ipairs(dots) do
    if d[1] == px and d[2] == pz then
      local bit = 2 ^ (i - 1)
      if math.floor(v / bit) % 2 == 0 then v = v + bit end
      pcall(function() require("src.core.Sound").play(ctx.game and ctx.game.data, "SEQ_SE_PL_JUMP2") end)
      break
    end
  end
  if v == 0x7F then v = 260 end
  setVar(ctx.save, destVar, v)
end

-- THE BALL SEALS (ball_seal_info.c) -- see src/import/Gen4Seals.lua.
local function Seals() return require("src.import.Gen4Seals") end

-- `pokemartseal <day>`: Sunyshore Market's seal counter, the day's stock
-- (SunyshoreMarketDailyStocks, Monday = 0) on the shop screen, BUY / SEE YA!
-- only, priced and named by the seal table, into the Seal Case.
function Commands.g4_seal_mart(ctx, day)
  local data = ctx.game and ctx.game.data
  local rec = data and data.gen4_seals
  local stock = rec and rec.stocks and rec.stocks[math.floor(valueOf(ctx, day)) + 1]
  if not stock then
    Logger.warn("gen4 shop: no seal stock for this day; re-import the ROM")
    return
  end
  local T = require("src.import.Gen4Text")
  local full = data.text and data.text[T.label(543, 14)]
  local goods = {
    def = function(id)
      local name = Seals().name(data, id)
      return name and { name = name, price = Seals().price(data, id), description = "" } or nil
    end,
    owned = function(id) return Seals().count(ctx.save, id) end,
    canAdd = function(id, qty) return Seals().canChange(ctx.save, id, qty) end,
    add = function(id, qty) Seals().change(ctx.save, id, qty) end,
    fullMessage = full,
    ownedLabel = "In Case: ",
  }
  local runner = ctx.runner
  require("src.ui.Screens").push(ctx.game, "ShopMenu", stock, function()
    if runner then runner:resume() end
  end, goods)
  if runner then runner:yield() end
end
Commands.meta.g4_seal_mart = { foreground = true, blocking = true }

-- `giveortakeseal <seal> <quantity>`: the quantity is an s16, so a var
-- holding 0xFFFF takes one away.
function Commands.g4_give_or_take_seal(ctx, seal, quantity)
  local q = math.floor(valueOf(ctx, quantity))
  if q >= 0x8000 then q = q - 0x10000 end
  Seals().change(ctx.save, math.floor(valueOf(ctx, seal)), q)
end

function Commands.g4_count_seal(ctx, seal, destVar)
  setVar(ctx.save, destVar, Seals().count(ctx.save, math.floor(valueOf(ctx, seal))))
end

function Commands.g4_count_unique_seals(ctx, destVar)
  setVar(ctx.save, destVar, Seals().unique(ctx.save))
end

function Commands.g4_buffer_seal_name(ctx, slot, seal, plural)
  if not ctx.game then return end
  local name = Seals().name(ctx.game.data, math.floor(valueOf(ctx, seal)), plural)
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[(tonumber(slot) or 0) + 1] = name or ""
end

-- `findpartyslotwithspecies <destVar> <species>`: the first non-egg, else 0xFF.
function Commands.g4_party_slot_with_species(ctx, destVar, species)
  local want = math.floor(valueOf(ctx, species))
  for i, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg and require("src.pokemon.Gen4DayCare").speciesOf(mon) == want then
      setVar(ctx.save, destVar, i - 1)
      return
    end
  end
  setVar(ctx.save, destVar, 0xFF)
end

-- `getpartymonform <slot> <destVar>` (Pokemon_GetForm)
function Commands.g4_party_mon_form(ctx, slot, destVar)
  setVar(ctx.save, destVar, require("src.pokemon.Gen4Forms").index(partyMon(ctx, slot)))
end

-- THE ROUTE 224 TABLET (Oak's Letter): `openshaymintabletnamingscreen <destVar>`
-- is the naming screen of type SHAYMIN_TABLET -- ten characters under bank 422
-- #6, "Thank who?" -- whose text the cartridge keeps in the misc save block
-- (MiscSaveBlock_SetTabletName) and `buffertabletname` reads back. The var gets
-- the screen's returnCode: 0 for a name, 1 for nothing entered.
function Commands.g4_tablet_naming(ctx, destVar)
  setVar(ctx.save, destVar, 1)
  if not (ctx.game and ctx.game.stack) then return end
  local T = require("src.import.Gen4Text")
  local title = ctx.game.data and ctx.game.data.text and ctx.game.data.text[T.label(422, 6)]
  title = type(title) == "string" and title:gsub("{YESNO %d+}", "") or "Thank who?"
  local runner = ctx.runner
  require("src.ui.Screens").push(ctx.game, "NamingScreen", {
    kind = "tablet", maxLen = 10, title = title,
    onDone = function(typed)
      local name = tostring(typed or "")
      if name ~= "" then
        ctx.save.gen4TabletName = name
        setVar(ctx.save, destVar, 0)
      end
      if runner then runner:resume() end
    end,
  })
  if runner then runner:yield() end
end
Commands.meta.g4_tablet_naming = { foreground = true, blocking = true }

function Commands.g4_buffer_tablet_name(ctx, slot)
  if not ctx.game then return end
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[(tonumber(slot) or 0) + 1] = ctx.save and ctx.save.gen4TabletName or ""
end

-- THE POFFIN HOUSE AND THE POFFIN CASE -- src/pokemon/Gen4Poffin.lua.
-- `checkcancookpoffin <destVar>`: 1 with no Berries, 2 with a full case, else 0.
function Commands.g4_can_cook_poffin(ctx, destVar)
  local P = require("src.pokemon.Gen4Poffin")
  if #P.berries(ctx.game and ctx.game.data, ctx.save) == 0 then setVar(ctx.save, destVar, 1)
  elseif P.empty(ctx.save) <= 0 then setVar(ctx.save, destVar, 2)
  else setVar(ctx.save, destVar, 0) end
end

-- `openpoffincooking <mode>`: FALSE is cooking alone, TRUE the group the
-- Wireless Club gathered (g4_link_club below).
function Commands.g4_open_poffin_cooking(ctx, mode)
  if not (ctx.game and ctx.game.stack) then return end
  local group = math.floor(valueOf(ctx, mode)) ~= 0 and (ctx.game.gen4LinkGroup or 2) or nil
  local runner = ctx.runner
  ctx.game.stack:push(require("src.ui.Gen4PoffinCooking").new(ctx.game, {
    group = group,
    onDone = function() if runner then runner:resume() end end,
  }))
  if runner then runner:yield() end
end

-- `startbattleserver / startbattleclient <mode> ... <dest>`. PORT ADDITION:
-- Platinum gathers 2-4 DSes for mode 6 (Poffin cooking); with no link the
-- port asks how many will cook and fills the other places with local cooks
-- who stir alongside the player. COMM_CLUB_RET_0 (0) when gathered,
-- _CANCEL (1) on B, _ERROR (3) for every other mode.
function Commands.g4_link_club(ctx, mode, dest)
  local game = ctx.game
  if math.floor(valueOf(ctx, mode)) ~= 6 or not (game and game.stack) then
    setVar(ctx.save, dest, 3)
    return
  end
  local runner = ctx.runner
  local function answer(v, n)
    game.gen4LinkGroup = n
    setVar(ctx.save, dest, v)
    if runner then runner:resume() end
  end
  local rows = {}
  for n = 2, 4 do
    rows[#rows + 1] = { label = require("src.core.Strings")("%d cooks", n), onSelect = function() answer(0, n) end }
  end
  game.stack:push(require("src.ui.Menu").new(game, rows, {
    cancelable = true, onCancel = function() answer(1, nil) end,
  }))
  if runner then runner:yield() end
end
Commands.meta.g4_link_club = { foreground = true, blocking = true }

function Commands.g4_end_communication(ctx)
  if ctx.game then ctx.game.gen4LinkGroup = nil end
end
Commands.meta.g4_open_poffin_cooking = { foreground = true, blocking = true }

function Commands.g4_poffin_case_has_room(ctx, destVar)
  setVar(ctx.save, destVar, require("src.pokemon.Gen4Poffin").empty(ctx.save) > 0 and 1 or 0)
end

function Commands.g4_poffin_case_empty_slots(ctx, destVar)
  setVar(ctx.save, destVar, require("src.pokemon.Gen4Poffin").empty(ctx.save))
end

-- `givepoffin <destVar> <spicy> <dry> <sweet> <bitter> <sour> <smoothness>`:
-- the type made, or POFFIN_NONE (0xFFFF) when the case is full.
function Commands.g4_give_poffin(ctx, destVar, a, b, c, d, e, smooth)
  local P = require("src.pokemon.Gen4Poffin")
  local flavors = {}
  for i, v in ipairs({ a, b, c, d, e }) do flavors[i] = math.floor(valueOf(ctx, v)) % 256 end
  local p = P.make(flavors, math.floor(valueOf(ctx, smooth)) % 256, false)
  setVar(ctx.save, destVar, P.add(ctx.save, p) and p.type or 0xFFFF)
end

-- `playtrainerencounterbgm <trainer>` -- Sound_SwapBGM(FieldBGM_GetEyesMeetForTrainer):
-- the trainer's class theme, at once.
-- THE JOURNAL (src/pokemon/Gen4Journal.lua). `givejournal` sets the
-- acquired flag, takes today's page and writes its title from where the
-- player stands (ScrCmd_GiveJournal + sub_02053494); `createjournalevent`
-- writes the Game Corner / Safari / item / field move / Frontier rows.
function Commands.g4_give_journal(ctx)
  local J = require("src.pokemon.Gen4Journal")
  local s = J.state(ctx.save)
  if not s then return end
  s.acquired = true
  local ow = ctx.overworld
  J.title(ctx.save, ow and ow.map and ow.map.def and ow.map.def.header)
end

function Commands.g4_journal_event(ctx, eventType, param)
  require("src.pokemon.Gen4Journal").fromScript(ctx.save, valueOf(ctx, eventType), valueOf(ctx, param))
end

function Commands.g4_trainer_encounter_bgm(ctx, trainer)
  local data = ctx.game and ctx.game.data
  local seq = require("src.import.Gen4TrainerMusic").forTrainer(data, math.floor(valueOf(ctx, trainer)))
  ctx.g4LastEncounterBgm = seq
  if seq then require("src.core.Music").play(data, seq) end
end

-- THE BGM FADES (scrcmd_sound.c), on the DS player's levels in src/core/Music.lua.
-- `fadeoutbgm <targetVolume> <frames>` and `fadeinbgm <frames>` (from zero to
-- 127) both wait for the fade, as ScriptContext_IsSoundFadeFinished does.
local function waitFade(ctx)
  local Music = require("src.core.Music")
  local runner = ctx.runner
  if not (runner and Music.dsFading()) then return end
  runner.waitingCheck = function() return not Music.dsFading() end
  runner:yield()
end

function Commands.g4_fade_out_bgm(ctx, target, frames)
  local Music = require("src.core.Music")
  if Music.dsFading() then return waitFade(ctx) end   -- Sound_FadeOutBGM: an active fade is kept
  Music.dsFade(math.max(0, math.min(127, tonumber(target) or 0)) / 127, tonumber(frames) or 0)
  return waitFade(ctx)
end

function Commands.g4_fade_in_bgm(ctx, frames)
  require("src.core.Music").dsFade(1, tonumber(frames) or 0, 0)
  return waitFade(ctx)
end

-- `setplayervolume <volume>` -- NNS_SndPlayerSetPlayerVolume(PLAYER_FIELD, v).
function Commands.g4_set_player_volume(ctx, volume)
  require("src.core.Music").setPlayerLevel(math.floor(valueOf(ctx, volume)) / 127)
end

-- THE SUPER CONTEST (scrcmd_contests.c, contest.c) -- src/pokemon/Gen4Contest.lua
-- holds the rules; the running contest lives on the game (SCRIPT_MANAGER_DATA_PTR),
-- not in the save.
local function Contest() return require("src.pokemon.Gen4Contest") end
local function current(ctx) return ctx.game and ctx.game.gen4Contest end

local function setBuf(ctx, slot, text)
  if not ctx.game then return end
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[math.floor(valueOf(ctx, slot)) + 1] = text or ""
end

local function contestText(ctx, bank, n)
  local T = require("src.import.Gen4Text")
  local data = ctx.game and ctx.game.data
  return data and data.text and data.text[T.label(bank, n)]
end

-- CheckContestEligibility (party_menu/main.c): not an egg, not fainted, at
-- least `rank` of the type's ribbons, and two moves or more.
function Gen4Commands.contestEligible(mon, rank, contestType)
  if not mon or mon.isEgg or (tonumber(mon.hp) or 1) <= 0 then return false end
  local ribbons = 0
  for r = 0, 3 do
    if mon.ribbons and mon.ribbons[Contest().ribbonId(contestType, r)] then ribbons = ribbons + 1 end
  end
  local moves = 0
  for i = 1, 4 do
    local mv = (mon.moves or {})[i]
    local id = tonumber(mv) or tonumber(mv and mv.id) or 0
    if id == 0 then break end
    moves = moves + 1
  end
  return rank <= ribbons and moves >= 2
end

-- `openpartymenuforcontest <slot> <rank> <type> <useDefaultRank>` /
-- `getcontestpartymenuresult <slotVar> <summaryVar>`
function Commands.g4_contest_party_menu(ctx, _slot, rank, contestType)
  local game = ctx.game
  local runner = ctx.runner
  ctx.g4ContestSlot = Gen4Commands.PARTY_SLOT_NONE
  local r, t = math.floor(valueOf(ctx, rank)), math.floor(valueOf(ctx, contestType))
  local rows = {}
  for i, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    local def = game.data.pokemon and game.data.pokemon[mon.species]
    local ok = Gen4Commands.contestEligible(mon, r, t)
    rows[#rows + 1] = {
      label = ("%s  %s"):format(mon.isEgg and "EGG" or (mon.nickname or (def and def.name) or "?"), ok and "ABLE" or "NOT ABLE"),
      keepOpen = not ok,
      onSelect = ok and function()
        ctx.g4ContestSlot = i - 1
        if runner then runner:resume() end
      end or nil,
    }
  end
  game.stack:push(require("src.ui.Menu").new(game, rows, {
    cancelable = true,
    onCancel = function() if runner then runner:resume() end end,
  }))
  if runner then runner:yield() end
end
Commands.meta.g4_contest_party_menu = { foreground = true, blocking = true }

function Commands.g4_contest_party_result(ctx, slotVar, summaryVar)
  setVar(ctx.save, slotVar, ctx.g4ContestSlot or Gen4Commands.PARTY_SLOT_NONE)
  setVar(ctx.save, summaryVar, 0)
end

-- `newcontest <rank> <type> <competition> <partySlot>` (ScrCmd_NewContest)
function Commands.g4_new_contest(ctx, rank, contestType, competition, slot)
  local game = ctx.game
  local s = math.floor(valueOf(ctx, slot))
  local save = ctx.save
  game.gen4Contest = Contest().new({
    data = game.data,
    rank = math.floor(valueOf(ctx, rank)), type = math.floor(valueOf(ctx, contestType)),
    competition = math.floor(valueOf(ctx, competition)), partySlot = s,
    mon = save.party and save.party[s + 1],
    playerName = save.player and save.player.name,
    playerGender = (save.player and save.player.gender == "girl") and 1 or 0,
    -- isGameCompleted and isNatDexObtained
    postgame = (save.flags and save.flags.FLAG_G4_0964 and save.pokedex and save.pokedex.national) and true or false,
    seed = os.time() % 65536,
  })
end

function Commands.g4_run_contest(ctx)
  local c = current(ctx)
  if not c then return end
  local runner = ctx.runner
  ctx.game.stack:push(require("src.ui.Gen4ContestScreen").new(ctx.game, c, function()
    if runner then runner:resume() end
  end))
  if runner then runner:yield() end
end
Commands.meta.g4_run_contest = { foreground = true, blocking = true }

-- Contest_EndContest, then Contest_Free.
function Commands.g4_end_contest(ctx)
  local c = current(ctx)
  if not c then return end
  local C = Contest()
  local single = c.competition == C.VISUAL or c.competition == C.DANCE or c.competition == C.ACTING
  if not C.isPractice(c.competition) and not single and c.placement then
    local mon = c.contestants[0].mon
    local won = c.placement[0] == 0
    local save = ctx.save
    if won then
      if c.rank >= C.MASTER and c.competition == C.OFFICIAL then
        save.gen4ContestMaster = save.gen4ContestMaster or {}
        save.gen4ContestMaster[c.type] = true
      end
      mon.ribbons = mon.ribbons or {}
      mon.ribbons[C.ribbonId(c.type, c.rank)] = true
      pcall(function()
        require("src.script.PtTvRecords").ribbonGiven(save, mon, C.ribbonId(c.type, c.rank), ctx.game and ctx.game.data)
      end)
      -- contest.c: the winner's contest photo for this type (the Contest
      -- Hall lobby's frames, 0A8): src/pokemon/Gen4Photos.lua
      pcall(function() require("src.pokemon.Gen4Photos").contestWon(save, c) end)
      -- Pokemon_UpdateFriendship(FRIENDSHIP_EVENT_CONTEST_WIN): +3 / +2 / +1 by
      -- tier (under 100, under 200, above), then Luxury Ball +1, Soothe Bell x1.5
      local f = tonumber(mon.happiness or mon.friendship) or 0
      local gain = f < 100 and 3 or f < 200 and 2 or 1
      if tonumber(mon.ball) == 11 or mon.ball == "LUXURY_BALL" then gain = gain + 1 end
      if tonumber(mon.item or mon.heldItem) == 218 then gain = math.floor(gain * 150 / 100) end
      mon.happiness = math.min(255, f + gain)
    end
    -- TVBroadcast_SetContestHallShowInfo: the Contest Hall interview's pending state
    pcall(function()
      require("src.script.PtTvRecords").contestShown(save, mon, c.type, c.rank, (c.placement[0] or 0) + 1)
    end)
    save.gen4ContestRecords = save.gen4ContestRecords or { entered = 0, won = 0 }
    save.gen4ContestRecords.entered = save.gen4ContestRecords.entered + 1
    if won then save.gen4ContestRecords.won = save.gen4ContestRecords.won + 1 end
  end
  ctx.game.gen4Contest = nil
end

-- the buffers
function Commands.g4_contest_buffer(ctx, kind, a, b)
  local c = current(ctx)
  if not c then return end
  local C = Contest()
  local data = ctx.game.data
  local function monName(e)
    local def = data.pokemon and data.pokemon[e.mon and e.mon.species]
    return (e.mon and e.mon.nickname) or (def and def.name) or "?"
  end
  if kind == "judge" then
    local j = data.gen4_contest.judges[c.judges[math.floor(valueOf(ctx, a)) + 1]]
    setBuf(ctx, b, j and contestText(ctx, C.JUDGE_NAMES, j.nameId))
  elseif kind == "trainer" or kind == "mon" then
    local e = c.contestants[C.entryToId(math.floor(valueOf(ctx, a)))]
    if e then setBuf(ctx, b, kind == "trainer" and e.trainer or monName(e)) end
  elseif kind == "entry" then
    setBuf(ctx, b, tostring(math.floor(valueOf(ctx, a))))
  elseif kind == "rank" then
    -- Contest_GetContestRankTitleMessageID: practice, or the rank's name
    -- (bank 204: NORMAL..MASTER RANK 46..49, PRACTICE 50)
    setBuf(ctx, a, contestText(ctx, C.TEXT_BANK, C.isPractice(c.competition) and 50 or 46 + c.rank))
  elseif kind == "type" then
    -- Contest_GetFullContestTypeMessageID: COOL..TOUGH CONTEST 41..45, or plain
    -- CONTEST (52) for the practice Dance
    setBuf(ctx, a, contestText(ctx, C.TEXT_BANK, c.competition == C.PRACTICE_DANCE and 52 or 41 + c.type))
  elseif kind == "winTrainer" or kind == "winMon" then
    local e = c.contestants[C.winner(c)]
    setBuf(ctx, a, kind == "winTrainer" and e.trainer or monName(e))
  elseif kind == "ribbon" then
    setBuf(ctx, a, contestText(ctx, 535, C.ribbonId(c.type, c.rank)))
  end
end

-- the queries
function Commands.g4_contest_query(ctx, kind, a, b)
  local c = current(ctx)
  local C = Contest()
  if kind == "true" then return setVar(ctx.save, a, 1) end
  if not c then return end
  if kind == "placement" then setVar(ctx.save, a, c.placement and c.placement[0] or 0)
  elseif kind == "winner" then setVar(ctx.save, a, C.idToEntry(C.winner(c)))
  elseif kind == "entry" then setVar(ctx.save, a, C.idToEntry(0))
  elseif kind == "gfx" then
    local e = c.contestants[C.entryToId(math.floor(valueOf(ctx, a)))]
    local g = e and e.gfx
    if g == "player_m" then g = 0 elseif g == "player_f" then g = 97
    elseif g == "player_m_contest" then g = 186 elseif g == "player_f_contest" then g = 187 end
    setVar(ctx.save, b, tonumber(g) or 0)
  elseif kind == "fame" then
    local e = c.contestants[C.entryToId(math.floor(valueOf(ctx, a)))]
    setVar(ctx.save, b, e and e.fame or 1)
  elseif kind == "mode" then setVar(ctx.save, a, C.mode(c))
  elseif kind == "ribbon" then
    local mon = c.contestants[0].mon
    setVar(ctx.save, a, (mon and mon.ribbons and mon.ribbons[C.ribbonId(c.type, c.rank)]) and 1 or 0)
  elseif kind == "firstWin" then
    if not c.placement or c.placement[0] ~= 0 then return setVar(ctx.save, a, 0xFFFF) end
    local acc = C.FIRST_WIN_ACCESSORY[c.type][c.rank]
    setVar(ctx.save, a, Gen4Commands.canFitAccessory(ctx.save, acc, 1) and acc or 0xFFFF)
  elseif kind == "skipCeremony" then
    local single = c.competition == C.VISUAL or c.competition == C.DANCE or c.competition == C.ACTING
    local skip = C.isPractice(c.competition) or single or C.winner(c) ~= 0
    setVar(ctx.save, a, skip and 1 or 0)
  end
end

function Commands.g4_contest_info(ctx, rankVar, typeVar, compVar, slotVar)
  local c = current(ctx)
  if not c then return end
  setVar(ctx.save, rankVar, c.rank)
  setVar(ctx.save, typeVar, c.type)
  setVar(ctx.save, compVar, c.competition)
  setVar(ctx.save, slotVar, c.partySlot or 0)
end

-- THE FASHION CASE'S ACCESSORIES (unk_020298BC.c): ids below 61
-- (NON_UNIQUE_ACCESSORY_COUNT) stack to 9, the rest to 1.
function Gen4Commands.accessoryCount(save, id)
  return tonumber(save and save.gen4Accessories and save.gen4Accessories[id]) or 0
end
function Gen4Commands.canFitAccessory(save, id, n)
  local cap = id < 61 and 9 or 1
  return Gen4Commands.accessoryCount(save, id) + n <= cap
end
function Commands.g4_add_accessory(ctx, id, n)
  local a, k = math.floor(valueOf(ctx, id)), math.floor(valueOf(ctx, n))
  ctx.save.gen4Accessories = ctx.save.gen4Accessories or {}
  local cap = a < 61 and 9 or 1
  ctx.save.gen4Accessories[a] = math.min(cap, Gen4Commands.accessoryCount(ctx.save, a) + k)
end
function Commands.g4_can_fit_accessory(ctx, id, n, destVar)
  setVar(ctx.save, destVar, Gen4Commands.canFitAccessory(ctx.save, math.floor(valueOf(ctx, id)), math.floor(valueOf(ctx, n))) and 1 or 0)
end

-- `hidepoketch` / `showpoketch` (SystemFlag_Set/ClearPoketchHidden)
function Commands.g4_poketch_hidden(ctx, hidden)
  ctx.save.poketch = ctx.save.poketch or {}
  ctx.save.poketch.hidden = hidden or nil
end


-- ---------------------------------------------------------------------------
-- MYSTERY GIFTS (src/scrcmd_mystery_gift.c ScrCmd_MysteryGiftGive), the
-- deliveryman's commands over src/pokemon/Gen4MysteryGift.lua.
-- ---------------------------------------------------------------------------

-- `mysterygiftgive <stage> [dest] [dest2]`
function Commands.g4_mystery_gift(ctx, stage, a, b)
  local MG = require("src.pokemon.Gen4MysteryGift")
  local save, game = ctx.save, ctx.game
  stage = math.floor(tonumber(stage) or 0)
  local g = MG.current(save)
  if stage == 1 then                                   -- CHECK_AVAILABLE_PGT
    setVar(save, a, g and 1 or 0)
  elseif stage == 2 then                               -- GET_PGT_TYPE
    setVar(save, a, MG.currentType(save))
  elseif stage == 3 then                               -- CHECK_CAN_RECEIVE
    setVar(save, a, MG.canReceive(game, save) and 1 or 0)
  elseif stage == 4 then                               -- GIVE, then free the slot
    MG.give(game, save, setVar)
  elseif stage == 5 or stage == 6 then                 -- RECEIVED / CANT_RECEIVE
    if not g then return end
    local items = game and game.data and game.data.items or {}
    local itemName = g.item and items[g.item] and items[g.item].name or ""
    local player = (save.player and save.player.name) or save.playerName or ""
    game.stringBuffers = game.stringBuffers or {}
    local id
    -- a Pokemon gift's line names the species where an item's names the item
    if g.species then
      local def = game.data and game.data.pokemon and game.data.pokemon[g.species]
      itemName = def and def.name or itemName
    end
    local T = MG.text()
    if stage == 5 then
      id = g.text
      game.stringBuffers[1], game.stringBuffers[2] = player, itemName
    else
      id = g.item and T.CANNOT_TOO_MANY or T.CANNOT_PARTY_FULL
      game.stringBuffers[1] = itemName
    end
    setVar(save, a, MG.bank())
    setVar(save, b, id)
  end
  -- 0 LOAD, 7 / 8 the UNLOADs: the save's gift block, which needs no loading here
end
Commands.meta = Commands.meta or {}

-- `checkdistributionevent <event> <dest>`: SystemVars_CheckDistributionEvent,
-- the event var holding its magic number
function Commands.g4_check_distribution_event(ctx, event, dest)
  local MG = require("src.pokemon.Gen4MysteryGift")
  local e = math.floor(valueOf(ctx, event) or 0)
  local magic = MG.MAGIC[e]
  local on = magic ~= nil and getVar(ctx.save, MG.DISTRIBUTION_VAR + e) == magic
  setVar(ctx.save, dest, on and 1 or 0)
  setResult(ctx, on and 1 or 0)
end

-- After the Hall of Fame: this port's offer of one gift per induction
-- (src/pokemon/Gen4MysteryGift.lua). The script waits for the picker.
function Commands.g4_mystery_gift_offer(ctx)
  local runner, game = ctx.runner, ctx.game
  local MG = require("src.pokemon.Gen4MysteryGift")
  if not (game and game.stack) or MG.owed(ctx.save) < 1 or #MG.available(ctx.save) == 0 then return end
  local resumed = false
  MG.offer(game, function()
    resumed = true
    if runner and runner.resume then runner:resume() end
  end)
  if runner and not resumed then runner:yield() end
end
Commands.meta.g4_mystery_gift_offer = { foreground = true, blocking = true }


-- `cleargame` -- ClearGame (src/clear_game.c), Platinum's own end:
--   1. the Hall of Fame app (src/ui/Gen4HallOfFame.lua)
--   2. [this port's addition] the Mystery Gift offer, one per induction
--   3. "Saving... Don't turn off the power." (bank 213 #15), the party
--      healed, the induction recorded, the save, "{player} saved the game."
--      (#16)
--   4. the end credits (src/ui/Gen4Credits.lua), START skipping them only if
--      the game had been cleared before this time
--   5. OS_ResetSystem: the cartridge reboots, so this returns to the title
--      and the script never resumes
-- HEARTGOLD / SOULSILVER reach it as `HOFCredits <vsTrainerRed>`
-- (game_clear.c, CallTask_GameClear): the same flag (0x964) and order, the
-- saving lines out of msg_0040 (15, 16) rather than 213, and after Red on
-- Mt. Silver (vsTrainerRed 1) no Hall of Fame screen and no entry -- the
-- save and the credits only.
function Commands.g4_clear_game(ctx, vsTrainerRed)
  local game, save, runner = ctx.game, ctx.save, ctx.runner
  local hgss = require("src.import.Gen4ScriptBands").family == "hgss"
  local vsRed = hgss and (tonumber(vsTrainerRed) or 0) ~= 0
  -- clear_game.c: RECORD_TIMES_ENTERED_HALL_OF_FAME
  if not vsRed then require("src.pokemon.Gen4GameRecords").increment(save, 73) end
  local flag = (save.flags or {})[Gen4Commands.GAME_COMPLETED_FLAG]
  local clearedBefore = flag == true or #((save and save.hallOfFame) or {}) > 0
  Commands.g4_prepare_hall_of_fame(ctx)
  local T = require("src.import.Gen4Text")
  local TextBox = require("src.render.TextBox")
  local function line(n)
    T.buffer(game, (save.player and save.player.name) or "")
    return T.resolve(game.data, hgss and 40 or 213, n, game) or ""
  end
  local function credits()
    game.stack:push(require("src.ui.Gen4Credits").new(game, {
      canSkip = clearedBefore,
      onDone = function() if game.returnToTitle then game:returnToTitle() end end,
    }))
  end
  local function saveGame()
    local Pokemon = require("src.pokemon.Pokemon")
    for _, mon in ipairs(save.party or {}) do pcall(Pokemon.heal, mon) end
    local SaveData = require("src.core.SaveData")
    local boot = game.data.field and game.data.field.boot or {}
    pcall(SaveData.applyPostGameHome, save, boot)
    if game.overworld then game.overworld.lastOutdoor = save.lastOutdoor end
    -- the one save write every script save goes through (ScriptSave); the
    -- capture puts the player back where they stand, so the post-game home is
    -- applied again after it and that save written as it stands
    local allowed = require("src.script.ScriptSave").write(ctx, "hall of fame")
    pcall(SaveData.applyPostGameHome, save, boot)
    -- HGSS (game_clear.c): Location_SetToPlayerRoom(dynamicWarp) +
    -- SetFlag966, which the next continue walks in at
    -- (src/world/Gen4HgssContinue.lua); the room is where a new game starts
    -- (Gen4HgssField, sLocation_PlayerRoom). PLATINUM's is the same pair
    -- (clear_game.c: special location = sPlayerStartLocation, the house 2F
    -- at (4,6) facing up; SystemFlag_SetCommunicationClubAccessible, 0x966),
    -- which FieldTask_LoadSavedGameMap walks in at
    -- (Gen4BattleTowerCommands.applySpecialLocation)
    if save.player then
      require("src.world.Gen4HgssContinue").mark(save, boot.startMap or save.player.map,
        boot.startX or save.player.x, boot.startY or save.player.y, hgss and "down" or "up")
    end
    if allowed then pcall(SaveData.save, save) end
  end
  local party = {}
  for _, mon in ipairs(save.party or {}) do party[#party + 1] = mon end
  if vsRed then
    if save.flags then save.flags[Gen4Commands.GAME_COMPLETED_FLAG] = true end
    game.stack:push(TextBox.new(game, line(15), function()
      saveGame()
      game.stack:push(TextBox.new(game, line(16), credits))
    end))
    if runner then runner:yield() end
    return
  end
  game.stack:push(require("src.ui.Gen4HallOfFame").new(game, {
    party = party,
    onDone = function()
      -- the induction (HallOfFame_AddEntry), which the gift offer counts
      save.hallOfFame = save.hallOfFame or {}
      -- what the PC's Hall of Fame browser shows (Gen4PcHallOfFame,
      -- HallOfFame_GetEntryPokemonData): name, species, level, gender, form,
      -- OT and moves, and the entry's date
      local entry = {}
      local now = os.date("*t")
      entry.date = { year = now.year, month = now.month, day = now.day }
      for _, mon in ipairs(party) do
        local moves = {}
        for i, mv in ipairs(mon.moves or {}) do
          moves[i] = type(mv) == "table" and (mv.id or mv.move or mv.name) or mv
        end
        entry[#entry + 1] = { species = mon.species, level = mon.level, nickname = mon.nickname,
          gender = require("src.pokemon.Pokemon").genderOf(game.data, mon), form = mon.form,
          shiny = mon.shiny or nil, personality = mon.personality,
          otName = mon.otName or mon.ot or (save.player or {}).name, moves = moves }
      end
      table.insert(save.hallOfFame, entry)
      local function afterGift()
        game.stack:push(TextBox.new(game, line(15), function()
          saveGame()
          game.stack:push(TextBox.new(game, line(16), credits))
        end))
      end
      -- this port's addition, the gift offer (Platinum's list or HGSS's,
      -- src/pokemon/Gen4MysteryGift.lua); the marts' deliveryman delivers
      require("src.pokemon.Gen4MysteryGift").offer(game, afterGift)
    end,
  }))
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_clear_game = { foreground = true, blocking = true }

-- the Battle Tower and Battle Points (src/script/Gen4BattleTowerCommands.lua)
-- THE FLAGS AND VARS THAT LAST ONE VISIT (ClearTempFieldEventData).
--
-- `field_warp_tasks.c` calls it on every warp and every connection, and it
-- zeroes the 64 map-local flags (the bytes from MAPTEMP_FLAG_BASE, so flags
-- 0x00..0x3F) and the 32 temp vars 0x4000..0x401F (script_manager.c:399).
--
-- Reported from play: Dawn on Route 202 kept saying "did you tell your
-- family?", and Mom never gave anything.  Mom's talk script (Twinleaf house
-- 1F) asks `checkflag 2` FIRST and takes her rest-and-heal branch while it is
-- set -- and that branch ends with `setflag 2`.  The cartridge wipes it on
-- the next map load; nothing here did, so after one heal she healed forever,
-- never reached the Journal branch, and its `setflag 143` (the flag Dawn's
-- trigger checks) never happened.
-- (`lastFlag`: Black / White's local flags run to 0x63 -- ov10 0x21589F4)
function Gen4Commands.clearTempFieldEventData(save, lastFlag)
  if not save then return end
  if save.flags then
    for id = 0x00, lastFlag or 0x3F do save.flags[("FLAG_G4_%04X"):format(id)] = nil end
  end
  local vars = save.gen4Vars
  if vars then
    for id = 0x4000, 0x401F do vars[id] = nil end
  end
end

package.loaded["src.script.Gen4Commands"] = Gen4Commands
require("src.script.Gen4BattleTowerCommands")
require("src.script.Gen4BattleHallLobby")

-- `legendcutscene*` -- the Kimono Girls' dance (src/world/HgssLegendCutscene.lua).
-- The four ScrCmds that return TRUE after TaskManager_Call (the eye glimmer,
-- the camera-pan wait, the bird's approach, Lugia's camera pan) hold the
-- script until their task is done; the shimmer yields one frame.
function Commands.g4_legend(ctx, op, arg)
  local LC = require("src.world.HgssLegendCutscene")
  local runner = ctx.runner
  local function holdUntil(done)
    if not (runner and runner.yield) or done() then return end
    runner.waitingCheck = function() return done() end
    runner:yield()
  end
  if op == "begin" then LC.begin()
  elseif op == "finish" then LC.finish()
  elseif op == "rise" then LC.riseFromBag()
  elseif op == "shimmer" then
    LC.shimmer(valueOf(ctx, arg))
    if runner and runner.yield then runner.waitingFrames = 1; runner:yield() end
  elseif op == "glimmer" then LC.eyeGlimmer(); holdUntil(LC.glimmerDone)
  elseif op == "move" then LC.moveCamera(valueOf(ctx, arg))
  elseif op == "pan" then LC.panCamera(valueOf(ctx, arg))
  elseif op == "waitpan" then holdUntil(LC.panDone)
  elseif op == "bird" then LC.birdFinalApproach(); holdUntil(LC.birdDone)
  elseif op == "fxbegin" then LC.wavesOrLeavesBegin()
  elseif op == "fxend" then LC.wavesOrLeavesEnd()
  elseif op == "lugiabegin" then LC.lugiaArrivesBegin()
  elseif op == "lugiaend" then LC.lugiaArrivesEnd()
  elseif op == "lugiapan" then LC.lugiaArrivesPan(); holdUntil(LC.panDone)
  elseif op == "fieldrebuild" then
    LC.fieldRebuilt()
    -- ...and the field that comes back runs its map's ON_LOAD / ON_RESUME
    -- (fieldmap.c, as after a battle): the Whirl Islands' resume script hides
    -- the five SPRITE_STOP barriers round Lugia (MakeObjectVisible) that the
    -- scene ShowPerson'd just before `Cinematic 1`; without it they stood on
    -- screen through Lugia's arrival and after
    local ow = ctx.overworld
    if ow and ow.gen4FieldResumed then pcall(ow.gen4FieldResumed, ow) end
  end
end

-- `submoneyvar <amount var>` (scrcmd_money.c): PlayerProfile_SubMoney, floored at 0
function Commands.g4_sub_money_var(ctx, amount)
  Commands.g4_remove_money(ctx, valueOf(ctx, amount))
end

-- `checknationaldexcomplete <dest>` (HGSS pokedex.c): every species owned but
-- the nine mythicals -- Mew, Celebi, Jirachi, Deoxys, Phione, Manaphy,
-- Darkrai, Shaymin, Arceus. Lugia and Ho-Oh count here, unlike Platinum.
local HGSS_MYTHICALS = { [151] = true, [251] = true, [385] = true, [386] = true, [489] = true,
  [490] = true, [491] = true, [492] = true, [493] = true }
function Commands.g4_hgss_national_complete(ctx, destVar)
  local owned = (ctx.save and ctx.save.pokedex and ctx.save.pokedex.owned) or {}
  local n = 0
  for sp = 1, 493 do
    if owned[sp] and not HGSS_MYTHICALS[sp] then n = n + 1 end
  end
  setVar(ctx.save, destVar, n >= 493 - 9 and 1 or 0)
end

-- HGSS's dex counts: national ids the save marks `field`, the Johto ones
-- filtered by the Johto Dex order (gen4_hgss_dex_art.orders.johto)
local function hgssDexIds(ctx, region, field)
  local list = {}
  local johto
  if region == "johto" then
    local art = ctx.game and ctx.game.data and ctx.game.data.gen4_hgss_dex_art
    local order = art and art.orders and art.orders.johto
    johto = {}
    if order then for _, id in ipairs(order) do johto[tonumber(id)] = true end
    else for id = 1, 251 do johto[id] = true end end
  end
  for _, id in ipairs(dexIDs(ctx, field, false)) do
    if not johto or johto[id] then list[#list + 1] = id end
  end
  return list
end
function Commands.g4_hgss_dex_count(ctx, region, field, destVar)
  setVar(ctx.save, destVar, #hgssDexIds(ctx, region, field))
end

-- (for the Pokegear phone's Oak, src/ui/HgssPhoneScripts.lua)
Gen4Commands.hgssDexIds = hgssDexIds
local HGSS_JOHTO_MYTHICALS = { [151] = true, [251] = true }
local function ownedExcludingMythicals(ctx, region)
  local skip = region == "johto" and HGSS_JOHTO_MYTHICALS or HGSS_MYTHICALS
  local n = 0
  for _, id in ipairs(hgssDexIds(ctx, region, "owned")) do if not skip[id] then n = n + 1 end end
  return n
end
Gen4Commands.hgssOwnedNoMythicals = ownedExcludingMythicals
function Commands.g4_hgss_johto_complete(ctx, destVar)
  setVar(ctx.save, destVar, ownedExcludingMythicals(ctx, "johto") >= 256 - 2 and 1 or 0)
end

-- GetOakJohtoDexRating / GetOakNationalDexRating (unk_0205BB1C.s): the band
-- each count falls in names a line of msg_0666; past the last band the dex is
-- complete -- the line by the player's gender and SEQ_ME_HYOUKA6 for HYOUKA1
Commands.HGSS_OAK_JOHTO = { 9, 19, 34, 49, 64, 79, 94, 109, 124, 139, 154, 169, 184, 199, 214, 229, 244, 253 }
Commands.HGSS_OAK_NATIONAL = { 100, 150, 200, 250, 300, 350, 400, 435, 465, 475, 483 }
Commands.SEQ_ME_HYOUKA1, Commands.SEQ_ME_HYOUKA6 = 1194, 1199
function Gen4Commands.hgssOakRating(national, count, female)
  local bands = national and Commands.HGSS_OAK_NATIONAL or Commands.HGSS_OAK_JOHTO
  local first = national and 46 or 28
  for i, top in ipairs(bands) do
    if count <= top then return first + i - 1, Commands.SEQ_ME_HYOUKA1 end
  end
  local done = national and 24 or 22
  return done + (female and 1 or 0), Commands.SEQ_ME_HYOUKA6
end
function Commands.g4_hgss_dex_eval(ctx, kind, msgVar, fanfareVar)
  local national = math.floor(tonumber(kind) or 0) ~= 0
  local count = ownedExcludingMythicals(ctx, national and "national" or "johto")
  local female = ctx.save and ctx.save.player and ctx.save.player.gender == "girl"
  local msg, fanfare = Gen4Commands.hgssOakRating(national, count, female)
  setVar(ctx.save, msgVar, msg)
  setVar(ctx.save, fanfareVar, fanfare)
end

-- FlashEffect: LocalFieldData's weather to WEATHER_FLASH_2, live
function Commands.g4_hgss_flash_effect(ctx)
  if ctx.save then ctx.save.gen4WeatherActive = 12 end
end

-- `checkseenallletterunown <dest>` (scrcmd_pokemon_misc.c): all twenty-six
-- letters seen; forms 26 and 27 (! and ?) are not letters
function Commands.g4_seen_all_letter_unown(ctx, destVar)
  local forms = require("src.pokemon.Gen4Forms").seen(ctx.save and ctx.save.pokedex, 201) or {}
  local letters = {}
  for _, f in ipairs(forms) do
    local form = tonumber(f)
    if form and form >= 0 and form < 26 then letters[form] = true end
  end
  local n = 0
  for _ in pairs(letters) do n = n + 1 end
  setVar(ctx.save, destVar, n >= 26 and 1 or 0)
end

-- THE HGSS SAFARI ZONE (src/world/HgssSafariZone.lua)
function Commands.g4_hgss_safari(ctx, action, set)
  if not ctx.save then return end
  require("src.world.HgssSafariZone").action(ctx.save, math.floor(valueOf(ctx, action) or 0),
    math.floor(valueOf(ctx, set) or 0))
end
function Commands.g4_hgss_safari_igt(ctx)
  require("src.world.HgssSafariObjects").markIgt(ctx.save)
end
function Commands.g4_hgss_safari_challenge(ctx, n, destVar)
  local done = require("src.world.HgssSafariZone").challengeDone(ctx.game and ctx.game.data, ctx.save,
    math.floor(valueOf(ctx, n) or 0))
  setVar(ctx.save, destVar, done and 1 or 0)
end
-- NatDexFlagAction <action> <dest>: 1 sets the National Dex (the dex's flag
-- and the trainer's), 2 reads it; dest is 0 otherwise
function Commands.g4_natdex_flag(ctx, action, destVar)
  local a = math.floor(valueOf(ctx, action) or 0)
  local dex = ctx.save and ctx.save.pokedex
  setVar(ctx.save, destVar, 0)
  if a == 1 then
    if dex then dex.national = true end
  elseif a == 2 then
    setVar(ctx.save, destVar, (dex and dex.national) and 1 or 0)
  end
end

-- ---------------------------------------------------------------------------
-- PLATINUM'S SMALL QUERIES (pokeplatinum, function by function)
-- ---------------------------------------------------------------------------
local function speciesOf(mon) return require("src.pokemon.Gen4DayCare").speciesOf(mon) end
local function lcrng(n) return love and love.math and love.math.random(0, n - 1) or math.random(0, n - 1) end

-- GetPartyMonLevel <dest, slot>: 0 for an egg
function Commands.g4_party_mon_level(ctx, destVar, slot)
  local mon = partyMon(ctx, slot)
  setVar(ctx.save, destVar, (mon and not mon.isEgg) and (tonumber(mon.level) or 0) or 0)
end
-- GetPartyMonNature <dest, slot>: Hardy (0) past the party or for an egg
function Commands.g4_party_mon_nature(ctx, destVar, slot)
  local mon = partyMon(ctx, slot)
  local nature = 0
  if mon and not mon.isEgg and mon.personality then nature = math.floor(mon.personality) % 25 end
  setVar(ctx.save, destVar, nature)
end
-- BufferNatureName <slot, nature>: TEXT_BANK_NATURE_NAMES (202)
function Commands.g4_buffer_nature_name(ctx, slot, nature)
  Commands.g4_buffer_bank_line(ctx, slot, 202, nature)
end
-- BufferMonNicknameFromPC <slot, boxSlotIndex>: box = index / 30, slot = % 30
function Commands.g4_buffer_pc_nickname(ctx, slot, index)
  local n = math.floor(valueOf(ctx, index) or 0)
  local box = ((ctx.save and ctx.save.boxes) or {})[math.floor(n / 30) + 1] or {}
  local mon = box[n % 30 + 1]
  local name = ""
  if mon then
    local def = ctx.game and ctx.game.data and ctx.game.data.pokemon and ctx.game.data.pokemon[speciesOf(mon)]
    name = mon.nickname or (def and def.name) or ""
  end
  setBuf(ctx, slot, name)
end
-- CheckHasSeenSpecies <species, dest>
function Commands.g4_has_seen_species(ctx, species, destVar)
  local sp = math.floor(valueOf(ctx, species) or 0)
  local seen = ctx.save and ctx.save.pokedex and ctx.save.pokedex.seen or {}
  setVar(ctx.save, destVar, seen[sp] and 1 or 0)
end
-- CountRepeatedSpeciesInParty <dest, species>: species 0 asks "any two alike?"
function Commands.g4_count_repeated_species(ctx, destVar, species)
  local want = math.floor(valueOf(ctx, species) or 0)
  local count, seen = 0, {}
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg then
      local sp = speciesOf(mon)
      if want == 0 then
        if seen[sp] then setVar(ctx.save, destVar, 1) return end
        seen[sp] = true
      elseif sp == want then
        count = count + 1
      end
    end
  end
  setVar(ctx.save, destVar, count)
end
-- CheckHasAllLegendaryTitansInParty <dest>: Regirock, Regice, Registeel
function Commands.g4_has_all_titans(ctx, destVar)
  local have = {}
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do have[speciesOf(mon)] = true end
  setVar(ctx.save, destVar, (have[377] and have[378] and have[379]) and 1 or 0)
end
-- GetRotomFormsInSave <heat, wash, frost, fan, mow>: party, day care, boxes
function Commands.g4_rotom_forms_in_save(ctx, heat, wash, frost, fan, mow)
  local forms = {}
  local function look(mon)
    if mon and not mon.isEgg and speciesOf(mon) == 479 then forms[tonumber(mon.form) or 0] = true end
  end
  local save = ctx.save or {}
  for _, mon in ipairs(save.party or {}) do look(mon) end
  for _, slot in ipairs(((save.gen4DayCare or {}).mons) or {}) do look(slot.mon or slot) end
  -- by slot: a box's emptied slots are holes, and ipairs stopped at the first
  for _, box in ipairs(save.boxes or {}) do for k = 1, 30 do look(box[k]) end end
  for i, dest in ipairs({ heat, wash, frost, fan, mow }) do setVar(save, dest, forms[i] and 1 or 0) end
end
-- SetRotomForm <partySlot, moveSlot, unused, form> (Pokemon_SetRotomForm):
-- the form's move takes the old form move's slot, else an empty one, else
-- the chosen slot; with no form move the old ones go; an empty first slot
-- gets Thunder Shock
local ROTOM_MOVES = { [0] = 0, 315, 56, 59, 403, 437 }
function Commands.g4_set_rotom_form(ctx, partySlot, moveSlot, _unused, form)
  local mon = partyMon(ctx, partySlot)
  if not (mon and speciesOf(mon) == 479) then return end
  local f = math.floor(valueOf(ctx, form) or 0)
  local data = ctx.game and ctx.game.data or {}
  local function reset(i, id)
    local m = data.moves and data.moves[id]
    mon.moves[i] = { id = id, pp = m and m.pp or 5, ppUps = 0 }
  end
  mon.moves = mon.moves or {}
  local newMove = ROTOM_MOVES[f] or 0
  local isForm = {}
  for k = 1, 5 do isForm[ROTOM_MOVES[k]] = true end
  local i = 1
  while i <= 4 do
    local m = mon.moves[i]
    if m and isForm[tonumber(m.id) or -1] then
      if newMove ~= 0 then reset(i, newMove); newMove = 0
      else table.remove(mon.moves, i); i = i - 1 end
    end
    i = i + 1
  end
  if newMove ~= 0 then
    if #mon.moves < 4 then reset(#mon.moves + 1, newMove)
    else reset(math.floor(valueOf(ctx, moveSlot) or 0) + 1, newMove) end
  end
  if #mon.moves == 0 then reset(1, 84) end
  require("src.pokemon.Gen4Forms").setForm(data, mon, f)
  local dex = ctx.save and ctx.save.pokedex
  if dex then dex.seen[479], dex.owned[479] = true, true end
end
-- CountPartyRibbons <dest>: how many different ribbons the party holds
function Commands.g4_count_party_ribbons(ctx, destVar)
  local kinds = {}
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if not mon.isEgg and type(mon.ribbons) == "table" then
      for id, on in pairs(mon.ribbons) do if on then kinds[id] = true end end
    end
  end
  local n = 0
  for _ in pairs(kinds) do n = n + 1 end
  setVar(ctx.save, destVar, n)
end
-- CheckPartyCombeeGenderCount <dest>: 2 both, 1 one, 0 none
function Commands.g4_combee_genders(ctx, destVar)
  local male, female = false, false
  local Pokemon = require("src.pokemon.Pokemon")
  for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    if speciesOf(mon) == 415 and not mon.isEgg then
      local g = Pokemon.genderOf(ctx.game and ctx.game.data, mon)
      if g == "male" then male = true elseif g == "female" then female = true end
    end
  end
  setVar(ctx.save, destVar, (male and female) and 2 or ((male or female) and 1 or 0))
end
-- CheckShouldShowGhost <percent, dest>: LCRNG % 101 <= percent
function Commands.g4_should_show_ghost(ctx, percent, destVar)
  local p = math.min(100, math.floor(valueOf(ctx, percent) or 0))
  setVar(ctx.save, destVar, lcrng(101) <= p and 1 or 0)
end
-- the daily level (VAR_DAILY_RANDOM_LEVEL 0x4041): 2..99, rolled each day
Commands.VAR_DAILY_RANDOM_LEVEL = 0x4041
function Commands.g4_daily_level_init(ctx)
  setVar(ctx.save, Commands.VAR_DAILY_RANDOM_LEVEL, lcrng(98) + 2)
end
function Commands.g4_daily_level(ctx, destVar)
  setVar(ctx.save, destVar, getVar(ctx.save, Commands.VAR_DAILY_RANDOM_LEVEL) or 0)
end
-- CheckIsPartyMonOutsider <slot var, dest>: OT id against the trainer's
function Commands.g4_party_mon_outsider(ctx, slotVar, destVar)
  local mon = partyMon(ctx, slotVar)
  local tid = tonumber(ctx.save and ctx.save.player and ctx.save.player.id) or 0
  local ot = mon and (tonumber(mon.otId) or tid) or tid
  setVar(ctx.save, destVar, (ot % 65536) == (tid % 65536) and 0 or 1)
end
-- TurnOnPokedexLanguageDetection
function Commands.g4_dex_language_detection(ctx)
  local dex = ctx.save and ctx.save.pokedex
  if dex then dex.canDetectLanguages = true end
end
-- JudgeStats <slot, total, best message, best value>: the IV judge; ties
-- broken by a coin flip, the message one of BattleTower_Text_BestPotential*
local JUDGE_KEYS = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
local JUDGE_MESSAGES = { 122, 123, 124, 127, 125, 126 }
function Commands.g4_judge_stats(ctx, slot, totalVar, indexVar, valueVar)
  local mon = partyMon(ctx, slot)
  local ivs = (mon and mon.ivs) or {}
  local values, total = {}, 0
  for i, k in ipairs(JUDGE_KEYS) do values[i] = tonumber(ivs[k]) or 0; total = total + values[i] end
  local best = 1
  for i = 2, 6 do
    if values[best] < values[i] then best = i
    elseif values[best] == values[i] and lcrng(2) == 0 then best = i end
  end
  setVar(ctx.save, totalVar, total)
  setVar(ctx.save, indexVar, JUDGE_MESSAGES[best])
  setVar(ctx.save, valueVar, values[best])
end
-- GetCurrentBGM <dest>: the sequence playing
function Commands.g4_current_bgm(ctx, destVar)
  local cur = require("src.core.Music").current()
  setVar(ctx.save, destVar, tonumber(cur) or 0)
end
-- CheckABPress <dest>: A or B held
function Commands.g4_ab_held(ctx, destVar)
  local input = ctx.game and ctx.game.input
  local held = input and input.isDown and (input:isDown("a") or input:isDown("b"))
  setVar(ctx.save, destVar, held and 1 or 0)
end
-- GetGBACartridgeVersion <dest>: no Game Boy Advance slot here
function Commands.g4_gba_cartridge(ctx, destVar) setVar(ctx.save, destVar, 0) end
-- SetFavoriteMon: the lead's species, form and egg-ness
function Commands.g4_set_favorite_mon(ctx)
  local mon = partyMon(ctx, 0)
  if mon and ctx.save then
    ctx.save.gen4FavoriteMon = { species = speciesOf(mon), form = tonumber(mon.form) or 0, isEgg = mon.isEgg and true or false }
  end
end
-- BufferTrainerName <slot, trainer>
function Commands.g4_buffer_trainer_name(ctx, slot, trainer)
  local id = math.floor(valueOf(ctx, trainer) or 0)
  local rec = ctx.game and ctx.game.data and ctx.game.data.trainers and ctx.game.data.trainers[id]
  setBuf(ctx, slot, rec and rec.name or "")
end
-- JUBILIFE'S LOTTERY (scrcmd_jubilife_lottery.c / system_vars.c). The
-- cartridge's own setter writes the HIGH half into the LOW var and never
-- touches the high one; this keeps that, since the scripts read the low var.
Commands.VAR_LOTTERY_LOW = 0x403C
function Commands.g4_lottery_set(save, id)
  setVar(save, Commands.VAR_LOTTERY_LOW, math.floor((tonumber(id) or 0) / 65536) % 65536)
end
function Commands.g4_lottery_randomize(ctx)
  Commands.g4_lottery_set(ctx.save, lcrng(65536) * 65536 + lcrng(65536))
end
function Commands.g4_lottery_id(ctx, destVar)
  setVar(ctx.save, destVar, getVar(ctx.save, Commands.VAR_LOTTERY_LOW) or 0)
end
local function lotteryDigits(win, ot)
  local n = 0
  for _ = 1, 5 do
    if win % 10 ~= ot % 10 then break end
    win, ot, n = math.floor(win / 10), math.floor(ot / 10), n + 1
  end
  return n
end
function Commands.g4_lottery_winner(ctx, indexVar, digitsVar, inBoxVar, lotteryId)
  local win = math.floor(valueOf(ctx, lotteryId) or 0)
  local save = ctx.save or {}
  local pBest, pIdx, bBest, bIdx = 0, 0, 0, 0
  for i, mon in ipairs(save.party or {}) do
    if not mon.isEgg then
      local d = lotteryDigits(win, (tonumber(mon.otId) or 0) % 65536)
      if d > 0 and pBest < d then pBest, pIdx = d, i - 1 end
    end
  end
  -- BY SLOT, not ipairs: a box keeps its empty slots as holes (Boxes.used),
  -- and ipairs stopped at the first one -- every mon after a gap went unread
  for b, box in ipairs(save.boxes or {}) do
    for k = 1, 30 do
      local mon = box[k]
      if mon and not mon.isEgg then
        local d = lotteryDigits(win, (tonumber(mon.otId) or 0) % 65536)
        if d > 0 and bBest < d then bBest, bIdx = d, (b - 1) * 30 + (k - 1) end
      end
    end
  end
  if pBest == 0 and bBest == 0 then
    setVar(save, indexVar, 0); setVar(save, digitsVar, 0); setVar(save, inBoxVar, 0)
  elseif pBest >= bBest then
    setVar(save, indexVar, pIdx); setVar(save, digitsVar, pBest); setVar(save, inBoxVar, 0)
  else
    setVar(save, indexVar, bIdx); setVar(save, digitsVar, bBest); setVar(save, inBoxVar, 1)
  end
end
-- TOUGH WORDS (easy_chat_words.c): unlocked one at random from those locked
local function toughCount(ctx)
  local c = require("src.pokemon.Gen4EasyChat").counts(ctx.game and ctx.game.data)
  return c[10] or 0
end
function Commands.g4_all_tough_words(ctx, destVar)
  local unlocked = (ctx.save and ctx.save.gen4ToughWords) or {}
  local all = toughCount(ctx) > 0
  for e = 0, toughCount(ctx) - 1 do if not unlocked[e] then all = false break end end
  setVar(ctx.save, destVar, all and 1 or 0)
end
function Commands.g4_unlock_tough_word(ctx, destVar, slot)
  if not ctx.save then return end
  ctx.save.gen4ToughWords = ctx.save.gen4ToughWords or {}
  local locked = {}
  for e = 0, toughCount(ctx) - 1 do if not ctx.save.gen4ToughWords[e] then locked[#locked + 1] = e end end
  if #locked == 0 then setVar(ctx.save, destVar, 0xFFFF) return end
  local entry = locked[lcrng(#locked) + 1]
  ctx.save.gen4ToughWords[entry] = true
  setVar(ctx.save, destVar, entry)
  local EasyChat = require("src.pokemon.Gen4EasyChat")
  local word = EasyChat.word(ctx.game and ctx.game.data, 10, entry)
  Commands.g4_buffer_message_word(ctx, slot, word)
end

-- ROUTE 222'S SIZE CONTEST (pokeplatinum overlay005/size_contest.c). The
-- size factor, the uniform-to-normal table and the inch rounding are
-- HeartGold's Magikarp record's too, so the arithmetic is HgssSizeRecord's;
-- the record is a var here (VAR_SIZE_CONTEST_RECORD 0x4035), seeded 33280.
Commands.VAR_SIZE_CONTEST_RECORD = 0x4035
local function sizeRecord(ctx)
  local v = getVar(ctx.save, Commands.VAR_SIZE_CONTEST_RECORD)
  return tonumber(v) or 0
end
local function sizeTenths(ctx, species, factor)
  local S = require("src.pokemon.HgssSizeRecord")
  local h = S.heightOf(ctx.game and ctx.game.data, species)
  return S.imperial(S.size(h, factor))
end
function Commands.g4_size_contest_init(ctx)
  setVar(ctx.save, Commands.VAR_SIZE_CONTEST_RECORD, 33280)
end
function Commands.g4_size_contest_buffer(ctx, intSlot, fracSlot, which, kind)
  local S = require("src.pokemon.HgssSizeRecord")
  local species, factor
  if kind == "record" then
    species, factor = math.floor(valueOf(ctx, which) or 0), sizeRecord(ctx)
  else
    local mon = partyMon(ctx, which)
    species, factor = mon and speciesOf(mon) or 0, mon and S.hash(mon) or 0
  end
  local tenths = sizeTenths(ctx, species, factor)
  setBuf(ctx, valueOf(ctx, intSlot), tostring(math.floor(tenths / 10)))
  setBuf(ctx, valueOf(ctx, fracSlot), tostring(tenths % 10))
end
-- 0 smaller, 1 the same, 2 larger (SIZE_CONTEST_SMALLER / SAME_SIZE / LARGER)
function Commands.g4_size_contest_result(ctx, destVar, slot)
  local S = require("src.pokemon.HgssSizeRecord")
  local mon = partyMon(ctx, slot)
  if not mon then setVar(ctx.save, destVar, 0) return end
  local sp = speciesOf(mon)
  local mine, best = sizeTenths(ctx, sp, S.hash(mon)), sizeTenths(ctx, sp, sizeRecord(ctx))
  setVar(ctx.save, destVar, mine == best and 1 or (mine > best and 2 or 0))
  -- a new record is Platinum's TV record (size_contest.c -> sub_0206DC6C)
  if mine > best then
    pcall(function() require("src.script.PtTvRecords").sizeRecord(ctx, mon, mine) end)
  end
end
function Commands.g4_size_contest_update(ctx, slot)
  local mon = partyMon(ctx, slot)
  if mon then setVar(ctx.save, Commands.VAR_SIZE_CONTEST_RECORD, require("src.pokemon.HgssSizeRecord").hash(mon)) end
end

-- StartFatefulEncounter <species, level>
function Commands.g4_fateful_encounter(ctx, species, level)
  local id = math.floor(valueOf(ctx, species) or 0)
  local lv = math.max(1, math.floor(valueOf(ctx, level) or 1))
  local mons = ctx.game and ctx.game.data and ctx.game.data.pokemon
  if id == 0 or not (mons and mons[id]) then return end
  Commands.start_battle(ctx, "wild", id, lv, { legendary = true, fateful = true })
end
-- DrawPokemonPreview <species, gender>: the framed picture (tile 10, 5),
-- the species seen; RemovePokemonPreview takes it down
function Commands.g4_pokemon_preview(ctx, species, gender)
  local id = math.floor(valueOf(ctx, species) or 0)
  local dex = ctx.save and ctx.save.pokedex
  if dex and id > 0 then dex.seen[id] = true end
  local ow, game = ctx.overworld, ctx.game
  if not (ow and game and game.stack and (game.data.pokemon or {})[id]) then return end
  local path, trueColor = require("src.pokemon.Sprites").path(game.data, id, "front", { kind = "pokepic" })
  if not path then return end
  if ow.pokepicBox then ow.pokepicBox:remove() end
  local box = require("src.ui.PicBox").new(game, {
    path = path, trueColor = trueColor and true or false, passive = true, overworld = ow,
    box = { x = 10, y = 5, w = 12, h = 12 }, picTiles = 10,
  })
  ow.pokepicBox = box
  game.stack:push(box)
end
function Commands.g4_pokemon_preview_remove(ctx)
  local ow = ctx.overworld
  local box = ow and ow.pokepicBox
  if not box then return end
  ow.pokepicBox = nil
  box:remove()
end
-- the frames a MapObject_Shake / _Flicker task runs, held
function Commands.g4_object_effect_wait(ctx, times, speed)
  local n = math.max(1, math.floor(valueOf(ctx, times) or 1) * math.max(1, math.floor(valueOf(ctx, speed) or 1)))
  Commands.wait(ctx, math.min(n, 600))
end

-- ---------------------------------------------------------------------------
-- JUBILIFE TV 3F'S PASSWORDS, THE BATTLEGROUND, THE MASSAGE GIRL
-- ---------------------------------------------------------------------------
local function band8(a, b) -- a & b on bytes, arithmetic so any Lua runs it
  local r, bit = 0, 1
  for _ = 1, 8 do
    if a % 2 == 1 and b % 2 == 1 then r = r + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return r
end
local function bxor8(a, b)
  local r, bit = 0, 1
  for _ = 1, 8 do
    if a % 2 ~= b % 2 then r = r + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return r
end
-- wallpaper_passwords.c RotateBits: the array as one big-endian number,
-- rotated right a bit at a time
local function rotateBits(arr, length, iterations)
  for _ = 1, iterations do
    local carry = arr[length] % 2
    for i = length, 2, -1 do
      arr[i] = math.floor(arr[i] / 2) + (arr[i - 1] % 2) * 128
    end
    arr[1] = math.floor(arr[1] / 2) + carry * 128
  end
end

Gen4Commands.MAX_UNLOCKABLE_WALLPAPERS = 8

-- WallpaperPasswords_CheckPassword: the wallpaper (0..7) the four words
-- unlock for this trainer id, or -1
function Gen4Commands.wallpaperPassword(bank, trainerId, w1, w2, w3, w4)
  if type(bank) ~= "table" or #bank == 0 then return -1 end
  local function find(w)
    for i, v in ipairs(bank) do if v == w then return i - 1 end end
    return -1
  end
  local idx = { find(w1), find(w2), find(w3), find(w4) }
  local bits = {}
  for i = 1, 4 do
    if idx[i] < 0 then return -1 end
    local d
    if i > 1 then
      if idx[i] >= idx[i - 1] then d = idx[i] - idx[i - 1]
      else d = #bank - (idx[i - 1] - idx[i]) end
    else
      d = idx[1]
    end
    if d > 255 then return -1 end
    bits[i] = d
  end
  rotateBits(bits, 4, 5)
  local key = math.floor(bits[4] / 16) + band8(bits[4], 0xF0)
  for i = 1, 3 do bits[i] = bxor8(bits[i], key % 256) end
  rotateBits(bits, 3, bits[4] % 16)
  if bits[1] % 16 >= Gen4Commands.MAX_UNLOCKABLE_WALLPAPERS then return -1 end
  bits[2] = bxor8(bits[2], bits[1])
  bits[3] = bxor8(bits[3], bits[1])
  if bits[2] * 256 + bits[3] == (tonumber(trainerId) or 0) % 65536
     and math.floor(bits[1] / 16) == 6
     and bits[4] == ((bits[1] + bits[2]) * bits[3]) % 256 then
    return bits[1] % 16
  end
  return -1
end

-- GetWallpaperFromCustomMessageWords <dest, w1..w4>: 0xFF wrong password, 0
-- already unlocked, else wallpaper + 1 (PCBoxes.unlockedWallpapers, a mask)
function Commands.g4_wallpaper_password(ctx, destVar, w1, w2, w3, w4)
  local save = ctx.save
  if not save then return end
  local consts = ctx.game and ctx.game.data and ctx.game.data.constants or {}
  local function v(x) return math.floor(valueOf(ctx, x) or 0xFFFF) end
  local wp = Gen4Commands.wallpaperPassword(consts.passwordWords, save.player and save.player.id,
    v(w1), v(w2), v(w3), v(w4))
  if wp < 0 or wp > Gen4Commands.MAX_UNLOCKABLE_WALLPAPERS - 1 then
    setVar(save, destVar, 0xFF)
    return
  end
  local mask = tonumber(save.gen4UnlockedWallpapers) or 0
  local bit = 2 ^ wp
  if math.floor(mask / bit) % 2 == 1 then
    setVar(save, destVar, 0)
  else
    save.gen4UnlockedWallpapers = mask + bit
    setVar(save, destVar, wp + 1)
  end
end

-- CheckIsMysteryGiftPhrase <dest, w1..w4>: the four words, laid out as the
-- bank's CustomMessageWords entry lays them, against "EVERYONE HAPPY /
-- WI-FI CONNECTION" (TEXT_BANK_MYSTERY_GIFT_PHRASE, 372)
Commands.MYSTERY_GIFT_PHRASE_BANK = 372
function Commands.g4_mystery_gift_phrase(ctx, destVar, w1, w2, w3, w4)
  local data = ctx.game and ctx.game.data
  local EasyChat = require("src.pokemon.Gen4EasyChat")
  local T = require("src.import.Gen4Text")
  local want = data and data.text and data.text[T.label(Commands.MYSTERY_GIFT_PHRASE_BANK, 0)]
  local ok = false
  if want then
    local w = {}
    for i, x in ipairs({ w1, w2, w3, w4 }) do w[i] = EasyChat.toString(data, valueOf(ctx, x)) end
    ok = (w[1] .. " " .. w[2] .. "\n" .. w[3] .. " " .. w[4]) == want  -- strings: comparing phrases
  end
  setVar(ctx.save, destVar, ok and 1 or 0)
end

-- GetRandomBattlegroundTrainers <d1..d4>: three different gym leaders and
-- one of the five stat trainers, as OBJ_EVENT_GFX ids; the second and
-- third leader, and the stat trainer, may be absent (0xFFF)
Commands.BATTLEGROUND_LEADERS = { 126, 127, 128, 129, 130, 131, 132, 133 }
Commands.BATTLEGROUND_STAT_TRAINERS = { 141, 142, 143, 144, 145 }
Commands.BATTLEGROUND_NONE = 0xFFF
local function battlegroundPick(n, a, b, c, d)
  local tries = 0
  while true do
    local r = lcrng(n + 1)
    if r == n then return r end
    tries = tries + 1
    if tries >= 8 then return n end
    if r ~= a and r ~= b and r ~= c and r ~= d then return r end
  end
end
function Commands.g4_battleground_trainers(ctx, d1, d2, d3, d4)
  local L, S, NONE = Commands.BATTLEGROUND_LEADERS, Commands.BATTLEGROUND_STAT_TRAINERS, Commands.BATTLEGROUND_NONE
  for _, d in ipairs({ d1, d2, d3, d4 }) do setVar(ctx.save, d, NONE) end
  local t1 = lcrng(#L)
  setVar(ctx.save, d1, L[t1 + 1])
  local t2 = battlegroundPick(#L, t1, NONE, NONE, NONE)
  if t2 ~= #L then setVar(ctx.save, d2, L[t2 + 1]) end
  local t3 = battlegroundPick(#L, t1, t2, NONE, NONE)
  if t3 ~= #L then setVar(ctx.save, d3, L[t3 + 1]) end
  local t4 = battlegroundPick(#S, NONE, NONE, NONE, NONE)
  if t4 ~= #S then setVar(ctx.save, d4, S[t4 + 1]) end
end

-- TryGetRandomMassageGirlAccessory <dest>: one of Pretty Dewdrop (34) ..
-- Glitter Powder (49) the Fashion Case still has room for, or 0xFFFF
Commands.MASSAGE_FIRST, Commands.MASSAGE_COUNT = 34, 16
function Commands.g4_massage_accessory(ctx, destVar)
  local open = {}
  for i = 0, Commands.MASSAGE_COUNT - 1 do
    if Gen4Commands.canFitAccessory(ctx.save, Commands.MASSAGE_FIRST + i, 1) then
      open[#open + 1] = Commands.MASSAGE_FIRST + i
    end
  end
  if #open == 0 then
    setVar(ctx.save, destVar, 0xFFFF)
    return
  end
  setVar(ctx.save, destVar, open[lcrng(#open) + 1])
end

-- CountPartyMonsBelowLevelThreshold <dest, threshold>: non-eggs at or
-- below the level (the Union Room's level-30 rooms)
function Commands.g4_party_below_level(ctx, destVar, threshold)
  local limit = math.floor(valueOf(ctx, threshold) or 0)
  local n = 0
  for _, mon in ipairs(ctx.save and ctx.save.party or {}) do
    if not mon.isEgg and (tonumber(mon.level) or 0) <= limit then n = n + 1 end
  end
  setVar(ctx.save, destVar, n)
end

-- GetPlayer3DPos <x, y, z>: MapObject x, y / 2 and z -- in the Distortion
-- World the tracked world tile (Gen4DistSurface.position, y the altitude in
-- tiles), elsewhere the matrix cell at height 0
function Commands.g4_player_3d_pos(ctx, xVar, yVar, zVar)
  local ow = ctx.overworld
  local p = ow and ow.player
  local x, y, z
  local okS, S = pcall(require, "src.world.Gen4DistSurface")
  local m = okS and ow and ow.map and S.floorFor(ow.map.def)
  if m then
    local ok, px, py, pz = pcall(S.position, ow, m)
    if ok then x, y, z = px, py, pz end
  end
  if not x then
    x, z = toMatrix(ctx, p and p.cellX, p and p.cellY)
    y = 0
  end
  setVar(ctx.save, xVar, math.floor(tonumber(x) or 0) % 65536)
  setVar(ctx.save, yVar, math.floor(tonumber(y) or 0) % 65536)
  setVar(ctx.save, zVar, math.floor(tonumber(z) or 0) % 65536)
end

-- the Fashion Case's backdrops (FashionCase_HasBackdrop / _AddBackdrop)
function Commands.g4_add_backdrop(ctx, id)
  if not ctx.save then return end
  ctx.save.gen4Backdrops = ctx.save.gen4Backdrops or {}
  ctx.save.gen4Backdrops[math.floor(valueOf(ctx, id) or 0)] = true
end
function Commands.g4_check_backdrop(ctx, id, destVar)
  local set = ctx.save and ctx.save.gen4Backdrops
  setVar(ctx.save, destVar, (set and set[math.floor(valueOf(ctx, id) or 0)]) and 1 or 0)
end

-- GetCapturedFlagCount <dest>: secret-base flags taken (a link feature, so
-- whatever the save says, else 0) -- Eterna's Underground Man reads it
function Commands.g4_captured_flag_count(ctx, destVar)
  local ug = ctx.save and ctx.save.underground
  setVar(ctx.save, destVar, tonumber(ug and ug.capturedFlags) or 0)
end

-- CheckIsTodayPlayerBirthday <dest>: the DS profile's birthday against the
-- RTC; save.player.birthday = { month, day } stands in for the profile
function Commands.g4_is_birthday(ctx, destVar)
  local b = ctx.save and ctx.save.player and ctx.save.player.birthday
  local today = os.date("*t")
  local yes = type(b) == "table" and tonumber(b.month or b[1]) == today.month
    and tonumber(b.day or b[2]) == today.day
  setVar(ctx.save, destVar, yes and 1 or 0)
end

-- GetPartyMonFootprintType <hasPrint, type, slot> (footprint_type.c): the
-- overlay table in constants.footprintTypes (type + 8 * hasPrint); Origin
-- Forme Giratina leaves no print
function Commands.g4_footprint_type(ctx, hasVar, typeVar, slot)
  local mon = partyMon(ctx, slot)
  local species = mon and speciesOf(mon) or 0
  local consts = ctx.game and ctx.game.data and ctx.game.data.constants or {}
  local rec = tonumber((consts.footprintTypes or {})[species]) or 0
  local has = math.floor(rec / 8) % 2
  if species == 487 and (tonumber(mon.form) or 0) == 1 then has = 0 end
  setVar(ctx.save, hasVar, has)
  setVar(ctx.save, typeVar, rec % 8)
end

-- DrawPokemonPreviewFromPartySlot <slot>: Chatot's recording booth shows the
-- party Pokemon itself
function Commands.g4_pokemon_preview_party(ctx, slot)
  local mon = partyMon(ctx, slot)
  if not mon then return end
  Commands.g4_pokemon_preview(ctx, speciesOf(mon), 0)
end

-- PokeMartDecor <martID> (MART_TYPE_DECOR): Veilstone 4F's goods counters.
-- Stock constants.martDecor, prices constants.goodPrices (Good_GetMoneyPrice),
-- names / descriptions TEXT_BANK_UNDERGROUND_GOODS (626: name at the good id,
-- description at 139 + id - 1); one at a time, sent to the PC's 200 slots
Commands.GOODS_BANK, Commands.GOODS_DESCRIPTIONS = 626, 139
function Commands.g4_decor_mart(ctx, martId)
  local data = ctx.game and ctx.game.data
  local consts = data and data.constants or {}
  local stock = (consts.martDecor or {})[math.floor(valueOf(ctx, martId) or 0)]
  if not (stock and stock[1]) then
    Logger.warn("gen4 shop: no decor stock for this counter; re-import the ROM")
    return
  end
  local T = require("src.import.Gen4Text")
  local UG = require("src.world.Gen4Underground")
  local function text(entry) return data.text and data.text[T.label(Commands.GOODS_BANK, entry)] end
  local function name(id) return ((text(id) or ""):gsub("\n", " ")) end
  local goods = {
    single = true,
    def = function(id)
      return { name = name(id), price = tonumber((consts.goodPrices or {})[id]) or 0,
               description = text(Commands.GOODS_DESCRIPTIONS + id - 1) or "" }
    end,
    owned = function(id)
      local n = 0
      for _, g in ipairs(UG.goodsPC(ctx.save)) do if g == id then n = n + 1 end end
      return n
    end,
    canAdd = function() return UG.roomInGoodsPC(ctx.save) end,
    add = function(id) UG.addGoodToPC(ctx.save, id) end,
    fullMessage = data.text and data.text[T.label(543, 12)],
    thanks = function(id)
      local line = data.text and data.text[T.label(543, 11)]
      return line and (line:gsub("{STRVAR_1 10 0 0}", name(id))) or "Thank you!"
    end,
  }
  local runner = ctx.runner
  require("src.ui.Screens").push(ctx.game, "ShopMenu", stock, function()
    if runner then runner:resume() end
  end, goods)
  if runner then runner:yield() end
end
Commands.meta.g4_decor_mart = { foreground = true, blocking = true }

-- HEARTGOLD / SOULSILVER GROUPS (scrcmd_8.c ScrCmd_465, friend_group.h): six
-- slots, 0 the group the player made, 1 the group they are in, 2..5 groups
-- met through record mixing (never filled here: no wireless). A slot is
-- { name, leader, gender, id } in save.hgssGroups[slot + 1].
--   0 <slot, dest>   slot is filled            1 <slot, dest>  slot == the joined one
--   2 <slot, buf>    group name to buffer      3 <slot, buf>   leader to buffer
--   4 <dest>         name the group (msg_0249 #5): 0 named, 1 blank, 2 name in use
--   5 <slot>         join that group           6               lead slot 0, join it
--   7 <dest>         four or more other groups known
local function hgssGroups(save)
  save.hgssGroups = save.hgssGroups or {}
  return save.hgssGroups
end

local function sameGroup(a, b)
  return a and b and a.name == b.name and a.leader == b.leader and a.id == b.id or false
end

function Commands.g4_hgss_group(ctx, mode, a, b)
  local save = ctx.save
  if not save then return end
  local groups = hgssGroups(save)
  mode = math.floor(tonumber(mode) or 0)
  if mode == 0 or mode == 1 then
    local slot = math.floor(valueOf(ctx, a))
    local g = groups[slot + 1]
    local r = mode == 0 and (g and 1 or 0) or (sameGroup(g, groups[2]) and 1 or 0)
    setVar(save, b, r)
  elseif mode == 2 or mode == 3 then
    local g = groups[math.floor(valueOf(ctx, a)) + 1]
    setBuffer(ctx, math.floor(valueOf(ctx, b)), g and (mode == 2 and g.name or g.leader) or "")
  elseif mode == 4 then
    setVar(save, a, 1)
    if not (ctx.game and ctx.game.stack) then return end
    local T = require("src.import.Gen4Text")
    local title = ctx.game.data and ctx.game.data.text and ctx.game.data.text[T.label(249, 5)]
    title = type(title) == "string" and title:gsub("%s*{YESNO %d+}", "") or "Group name?"
    local runner = ctx.runner
    require("src.ui.Screens").push(ctx.game, "NamingScreen", {
      kind = "group", maxLen = 7, title = title,
      onDone = function(typed)
        local name = tostring(typed or "")
        local r = 1
        if name ~= "" then
          r = 0
          for i = 2, 6 do if groups[i] and groups[i].name == name then r = 2 end end
          if r == 0 then
            groups[1] = groups[1] or {}
            groups[1].name = name
          end
        end
        setVar(save, a, r)
        if runner then runner:resume() end
      end,
    })
    if runner then runner:yield() end
  elseif mode == 5 then
    local g = groups[math.floor(valueOf(ctx, a)) + 1]
    if g then
      local c = {}
      for k, v in pairs(g) do c[k] = v end
      groups[2] = c
    end
  elseif mode == 6 then
    local p = save.player or {}
    local g = groups[1] or {}
    g.leader = p.name or ""
    g.gender = p.gender == "girl" and 1 or 0
    g.id = math.random(0, 0x7FFFFFFF)
    groups[1] = g
    local c = {}
    for k, v in pairs(g) do c[k] = v end
    groups[2] = c
  elseif mode == 7 then
    local n = 0
    for i = 1, 6 do
      if groups[i] and not sameGroup(groups[i], groups[2]) then n = n + 1 end
    end
    setVar(save, a, n >= 4 and 1 or 0)
  end
end
Commands.meta.g4_hgss_group = { foreground = true, blocking = true }

-- HGSS ScrCmd_706 / ScrCmd_642 <dest>: 1 when a Hall of Fame record exists
function Commands.g4_hof_exists(ctx, destVar)
  local hof = ctx.save and ctx.save.hallOfFame
  local n = type(hof) == "table" and #hof or math.floor(tonumber(hof) or 0)
  setVar(ctx.save, destVar, n > 0 and 1 or 0)
end

-- HGSS ScrCmd_289 <choice>: the trainer's Union Room avatar
function Commands.g4_hgss_set_avatar(ctx, choice)
  if not ctx.save then return end
  ctx.save.player = ctx.save.player or {}
  ctx.save.player.avatar = math.floor(valueOf(ctx, choice))
end

return Gen4Commands
