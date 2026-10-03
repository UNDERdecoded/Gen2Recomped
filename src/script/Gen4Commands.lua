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

local function isVarId(n)
  n = tonumber(n)
  return n ~= nil and n >= VARS_START
end

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
  setVar(ctx.save, id, valueOf(ctx, value))
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
function Commands.g4_lock_all(ctx) ctx.g4Locked = true end
function Commands.g4_release_all(ctx) ctx.g4Locked = false end
function Commands.g4_lock(ctx, _) ctx.g4Locked = true end
function Commands.g4_release(ctx, _) ctx.g4Locked = false end

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
function Commands.g4_wait_button() end

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
      local label = require("src.import.Gen4Text").label(395, n)
      text = data and data.text and data.text[label]
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
    -- (627).  One kind rather than five near-identical branches, because the
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
    local label = require("src.import.Gen4Text").label(413, id)
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

function Commands.g4_give_item(ctx, item, count, destVar)
  local id = itemKey(ctx.game and ctx.game.data, valueOf(ctx, item))
  local n = math.max(valueOf(ctx, count), 1)
  Commands.give_item(ctx, id, n)
  if destVar then setVar(ctx.save, destVar, 1) end
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
function Commands.g4_can_fit_item(ctx, _, _, destVar)
  if destVar then setVar(ctx.save, destVar, 1) end
  setResult(ctx, 1)
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
    index = {}
    for id, def in pairs(maps) do
      if type(def) == "table" and def.header then index[def.header] = id end
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
  return Commands.warp(ctx, mapId, valueOf(ctx, x), valueOf(ctx, z),
                       DIRECTION[valueOf(ctx, direction)])
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
local function lineFor(ctx, entry)
  local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
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
function Commands.g4_choose_message_word(ctx, _unused, resultVar, destVar)
  if destVar then setVar(ctx.save, destVar, 0xFFFF) end
  if resultVar then setVar(ctx.save, resultVar, 0) end
end

-- `messagevar` takes its entry out of a var rather than out of the row.
function Commands.g4_message_var(ctx, id, bank)
  if bank then return Commands.g4_message_bank(ctx, bank, getVar(ctx.save, id)) end
  return Commands.g4_message(ctx, getVar(ctx.save, id))
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
  local best, bestIndex
  for _, e in ipairs(overworld.entities) do
    -- On the def, because that is where the extractor writes it; checked on
    -- the entity too so a future spawner that copies it up still matches.
    local localId = e.localId or (e.def and e.def.localId)
    if localId == wanted then
      local index = tonumber(e.def and e.def.index) or math.huge
      if not best or index < bestIndex then best, bestIndex = e, index end
    end
  end
  return best
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
  e.hidden = true
  setObjectFlag(ctx, e, true)
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
                .. "an object, but Gen 4's movement types are not decoded -- "
                .. "the object keeps the behaviour it spawned with",
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
    Follower.adopt(ctx.save, ow, e)
    return
  end
  -- Switching the follower to anything else is how a script STOPS somebody
  -- following -- Route 201 sends Barry back to LOOK_SOUTH when you insist on
  -- going the wrong way.
  if e.gen4Follower then Follower.release(ctx.save, ow) end
  -- Everything else is a behaviour this engine does not derive (see the note
  -- on the template command above), so the number is recorded and the actor
  -- keeps what it has.
  if e.def then e.def.movementType = value end
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
    e.def.x, e.def.y = cx, cy
    if facing then e.def.direction = valueOf(ctx, dir) end
    if height then e.def.elevation = valueOf(ctx, height) end
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

Commands.g4_wait_move = noop
function Commands.g4_play_sound(ctx, soundId)
  Commands.play_sound(ctx, valueOf(ctx, soundId))
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
Commands.g4_wait_animation = noop
Commands.g4_wait_fade = noop
Commands.g4_return_to_field = noop
Commands.g4_menu_close = noop

function Commands.g4_fanfare(ctx, songId)
  Commands.play_once(ctx, songId)
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

  -- WHERE THIS WALK STARTS, WHICH IS THE HALF A LOG NEVER SHOWS.
  --
  -- A scripted walk that ends somewhere wrong has two possible causes and they
  -- need separating: the list was read wrong, or the walker was not standing
  -- where the cartridge thought.  The list is decoded offline and checked; the
  -- starting cell is only knowable from a running game.
  local fromX, fromY = entity.cellX, entity.cellY
  local netX, netY = 0, 0
  for _, step in ipairs(steps) do
    local a = Gen4Movement.action(step.action)
    if a and a.kind == "walk" and a.dir then
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

  for _, step in ipairs(steps) do
    local action = Gen4Movement.action(step.action)
    local count = math.max(tonumber(step.count) or 1, 1)
    if action == nil then
      -- An action nobody has named -- 20 steps in the whole cartridge, all in
      -- the unnamed MOVEMENT_ACTION_1xx range.  Skipped rather than guessed.
    elseif action.kind == "walk" then
      -- ...AT THE ACTION'S OWN SPEED.  A Gen 4 movement action names a speed
      -- as well as a direction and the table carries it now; without it a
      -- scene written in WALK_FAST played at a stroll, which is the same fault
      -- Gen 3 had before `MOVE_SPEED` was read.
      Commands.walkEntity(ctx, entity, action.dir, (action.tiles or 1) * count,
                          action.rate)
    elseif action.kind == "face" then
      entity.facing = action.dir
    elseif action.kind == "spot" then
      -- Marking time: the sprite animates without moving, which a cutscene
      -- uses as a pause with a facing.  One repetition costs one step, so the
      -- beat is the entity's OWN step duration rather than a number picked
      -- here -- `stepFrames`, which the field defaults put at 16.
      entity.facing = action.dir
      -- The beat is one walk cycle, and the on-spot actions carry the same
      -- five speeds the walking ones do -- a fast mark-time is a short beat.
      Commands.wait(ctx, math.max(1, math.floor(
        (entity.stepFrames or 16) * (action.rate or 1) * count + 0.5)))
    elseif action.kind == "wait" then
      Commands.wait(ctx, (action.frames or 1) * count)
    elseif action.kind == "hide" then
      entity.hidden = true
    elseif action.kind == "show" then
      entity.hidden = nil
    elseif action.kind == "emote" then
      -- EMOTE_EXCLAMATION_MARK is 73 of the cartridge's 1,278 steps -- the "!"
      -- over a trainer who has just spotted you.  Both it and the double mark
      -- are the shock bubble; this engine has three (shock, question, happy)
      -- and Platinum's movement table names no others.
      local target = (entity == ow.player) and "player"
        or (entity.def and entity.def.index)
      if target then Commands.emote(ctx, target, "shock") end
    end
  end
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
function Commands.g4_menu_init(ctx, destVar, canExitWithB, cursor, bank)
  ctx.g4Menu = {
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
  text = Commands.gen4Markup and Commands.gen4Markup(text, ctx.game) or text
  -- A line the cache has no string for keeps the label, which names the bank
  -- and the entry: a menu of blank rows says nothing, and a menu that reads
  -- TEXT_B0361_00023 says which entry to go and look at.
  return (type(text) == "string" and text ~= "") and text or label
end

function Commands.g4_menu_entry(ctx, entry, index)
  local menu = menuState(ctx)
  menu.rows[#menu.rows + 1] = {
    text = menuLine(ctx, entry),
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
  ctx.game.stack:push(Menu.new(ctx.game, items, {
    -- `canExitWithB == 0` means B does nothing at all -- the player is made to
    -- choose.  17 of the cartridge's 186 menus are that kind.
    cancelable = menu.cancelable,
    onCancel = menu.cancelable and function() pick(MENU_CANCEL) end or nil,
    index = menu.cursor,
  }))
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

function Commands.g4_noop(_, what)
  local key = tostring(what)
  if not noopSeen[key] then
    noopSeen[key] = true
    Logger.info("gen4 script: %s is not implemented; the row is a no-op", key)
  end
end

local function pending(verb, what)
  Commands[verb] = function()
    if said[verb] then return end
    said[verb] = true
    Logger.info("gen4 script: '%s' is decoded and lowered but %s is not built "
                .. "yet -- the row is stepped over", verb, what)
  end
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
  local mapId = ctx.save and ctx.save.player and ctx.save.player.map
  local def = mapId and data and data.maps and data.maps[mapId]
  setVar(ctx.save, destVar, tonumber(def and def.header) or 0)
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
  battle.demoBallCount = "x20"
  battle.onFinish = function()
    if ctx.runner then ctx.runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  if ctx.runner then ctx.runner:yield() end
end
Commands.meta.g4_catching_tutorial = { foreground = true, blocking = true }

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
  save.inventory = save.inventory or {}
  save.inventory[id] = save.inventory[id] or 1
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
  if other ~= 0 and trainers[other] then opts.trainerBKey = other end
  if extra and extra.canLose then opts.canLose = true end
  Commands.start_battle(ctx, "trainer", id, 1, opts)
end

-- `checkwonbattle <destVar>` -- `CheckPlayerWonBattle(*battleResult)`.
--
-- `start_battle` leaves its answer in `ctx.lastBattleResult`; reading THAT
-- rather than keeping a second copy is what stops the two disagreeing after a
-- battle the script did not start.
function Commands.g4_check_won_battle(ctx, destVar)
  local won = (ctx.lastBattleResult == "win")
  -- ...and mark the trainer beaten, once, on the way past. The cartridge does
  -- this in the battle teardown rather than the script -- no Sinnoh script
  -- runs `settrainerflag` after a fight -- so a port that waited for one would
  -- have every trainer in the region challenge you again for ever. Same shape
  -- as the Gen 3 fix in `start_battle`.
  if won and ctx.g4Trainer then
    local t = trainerFlags(ctx.save)
    if t then t[ctx.g4Trainer] = true end
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
Commands.g4_start_approach = noop

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
function Commands.g4_approach_type(ctx, destVar)
  local trainers = ctx.gen4ApproachingTrainers
  local second = trainers and tonumber(trainers[2]) or 0
  local kind = (second ~= 0) and 1 or 0
  if destVar then setVar(ctx.save, destVar, kind) end
  setResult(ctx, kind)
end

function Commands.g4_get_rematch_trainer_id(ctx, trainer, destVar)
  local VsSeeker = require("src.world.VsSeeker")
  local id = VsSeeker.rematchFor(ctx.save, ctx.overworld, ctx.npc)
  local value = tonumber(id) or 0
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
Commands.g4_set_move_code_facing = noop

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
  return Commands.show_text(ctx,
    Gen4Text.label(Gen4TrainerMessages.BANK, entry))
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
  if kind == 'seal' then
    Logger.warn('gen4 shop: seal counters need the seal inventory and pricing system')
    return
  end
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
  elseif operation=='plantberry' then B.plant(ctx.game,patch,valueOf(ctx,operand)); return
  elseif operation=='setberrywateringstate' then
    if patch and patch.stage>0 and patch.stage<5 then patch.moisture=100 end
    return
  elseif operation=='harvestberry' then ctx.lastCheck=B.harvest(ctx.game,patch); return
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
  Screens.push(ctx.game, "NamingScreen", {
    kind = "pokemon",
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
-- it for yours, and play the trade cutscene. THE CUTSCENE IS NOT BUILT and is
-- not faked -- there is no trade animation anywhere in this port -- so the swap
-- happens and the scene does not. Said out loud rather than left to be noticed:
-- the alternative is a trade that silently does nothing, which is what was
-- happening before.
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
    local def = data.pokemon[row.species]
    local okStats, stats = pcall(Stats.calc, def, mon.level, mon.ivs,
                                 mon.evs, mon.nature)
    if okStats and type(stats) == "table" then
      mon.stats, mon.hp = stats, stats.hp
    end
  end

  -- The one you gave leaves and the one you were given joins at the END, which
  -- is where Party_AddPokemonBySlotIndex puts it, and the dex is told.
  table.remove(party, slot)
  party[#party + 1] = mon
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
end

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
  local pocket = tonumber(def and def.fieldPocket) or 0
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
    -- test the cartridge performs even if an item is ever re-pocketed.
    if n and type(name) == "string"
       and (name:match("^TM%d") or name:match("^HM%d")) then
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
  if name == "Adamant Orb" or name == "Lustrous Orb" then
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

function Commands.g4_player_state(ctx, state)
  local bits = math.floor(tonumber(state) or 0)
  local save = ctx.save
  if not save then return end
  if bits % 2 == 1 then            -- WALKING
    save.onBike = false
  elseif math.floor(bits / 2) % 2 == 1 then  -- CYCLING
    save.onBike = true
  end
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
  save.onBike = (math.floor(tonumber(on) or 0) ~= 0)
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
-- WHAT THIS PORT ACTUALLY FIELDS, stated plainly because it is not the
-- cartridge's fight: the two foes are real and the battle is a real double,
-- but the ally trainer is NOT on the field -- both of the player's flanks come
-- from the player's own party, because an AI-driven battler on the player's
-- side is a battle-engine feature this port does not have. The fight is
-- therefore harder than Sinnoh's, and winnable, which is the trade that keeps
-- the scene finishable. Losing it runs the script's own blackout branch, as it
-- does on the cartridge.
--
-- The alternative was a `pending()` stub, and that is strictly worse: the
-- Jubilife scene reads `CheckWonBattle` immediately afterwards and branches to
-- its blackout on FALSE, so an unlowered battle does not merely skip a fight,
-- it blacks the player out in the middle of a cutscene.
function Commands.g4_start_tag_battle(ctx, partner, enemy1, enemy2)
  local ally = math.floor(valueOf(ctx, partner) or 0)
  if ally ~= 0 and not Gen4Commands._saidTagBattle then
    Gen4Commands._saidTagBattle = true
    Logger.info("gen4 battle: a tag battle names trainer %d as the player's "
                .. "ally; this port has no ally-trainer battler, so both of "
                .. "the player's flanks are their own party", ally)
  end
  local a, b = math.floor(valueOf(ctx, enemy1) or 0),
               math.floor(valueOf(ctx, enemy2) or 0)
  return Commands.g4_start_battle(ctx, a, b)
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
local function dexCount(ctx,field,regional,completion)
  local dex=(ctx.save and ctx.save.pokedex) or {}
  local ids={}
  for key,flag in pairs(dex[field] or {}) do
    if flag==true or (type(flag)=='number' and flag>0) then
      local id=speciesNumber({species=key})
      if id>=1 and id<=493 then ids[id]=true end
    end
  end
  local region={}
  if regional then
    local orders=ctx.game and ctx.game.data and ctx.game.data.gen4_dex
    for _,id in ipairs(orders and orders.orders and orders.orders.sinnoh or {}) do region[tonumber(id) or id]=true end
  end
  local excluded={ [151]=true,[249]=true,[250]=true,[251]=true,[385]=true,[386]=true,
    [489]=true,[490]=true,[491]=true,[492]=true,[493]=true }
  local count=0
  for id in pairs(ids) do
    if (not regional or region[id]) and (not completion or regional or not excluded[id]) then count=count+1 end
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
function Commands.g4_destroy_obstacle_anim(ctx, _, destVar)
  if destVar then setVar(ctx.save, destVar, 1) end
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
function Commands.g4_check_save_type(ctx, destVar)
  local Gen4Save = require("src.script.Gen4Save")
  local kind = Gen4Save.typeFor(ctx.save)
  if destVar then setVar(ctx.save, destVar, kind) end
  return kind
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
  return answer
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
  return value
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
  return value
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
  return 0
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
Commands.g4_open_hall_of_fame = pending("g4_open_hall_of_fame",
  "the PC's Hall of Fame browser is not built; save.hallOfFame holds the "
  .. "records and src/ui/HallOfFame.lua is the induction ceremony, not a viewer")

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
function Commands.g4_clear_overworld_weather(ctx)
  if ctx.save then ctx.save.gen4WeatherCleared = true end
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
function Commands.g4_use_surf(ctx)
  local ow = ctx.overworld
  local p = ow and ow.player
  if not p then return end
  p.surfing = true
  -- Being on the water means being at the water's level; the step onto it is
  -- otherwise refused by the rule that keeps a walker out of the sea.
  if ow.map and ow.map.cellElevation then
    local fx, fy = p:facingCell()
    p.elevation = ow.map:cellElevation(fx, fy) or p.elevation
  end
  if ow.syncSurfingPikachu then ow:syncSurfingPikachu() end
  local okMusic, Music = pcall(require, "src.core.Music")
  if okMusic and ctx.game then Music.setSurfing(ctx.game.data, true) end
end

-- `usewaterfall <slot>` -- the climb itself already exists for Hoenn
-- (`OverworldState:gen3UseWaterfall`), driven from pressing A on the fall. The
-- Sinnoh script reaches the same motion by a different door, so this hands off
-- to whichever of those the overworld exposes rather than walking the player
-- by hand -- the cell-by-cell climb is the overworld's business and a second
-- copy of it here is how the two end up disagreeing about where you surface.
function Commands.g4_use_waterfall(ctx)
  local ow = ctx.overworld
  local p = ow and ow.player
  if not (ow and p) then return end
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
pending("g4_use_rock_climb", "a rock-climb motion")
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
  if want then save.onBike = true end
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
-- THE PORT KEEPS NO SAVED GEN 4 WEATHER: `applyMapWeather` is Gen 3 only, and
-- inventing a `save.gen4Weather` that one command writes and nothing else
-- reads would be worse than answering from the map. The map's own `weather`
-- byte is extracted on 592 of 593 rows and is what the cartridge seeds the
-- saved value FROM on every load, so on the map you are standing on the two
-- agree. Route 213's two sites are asking about the beach they are on.
--
-- ...AND SOMETHING WRITES ONE NOW, so the paragraph above needed its other
-- half. `g4_clear_overworld_weather` (opcodes 0x0C3 and 0x0C4) is what Flash
-- and Defog call, and it sets `gen4WeatherCleared`. Without this arm, Defog
-- would blow the fog away and the very next `getoverworldweather` would report
-- fog -- the exact asymmetry the reasoning above was guarding against, arrived
-- at from the other direction.
--
-- OVERWORLD_WEATHER_CLEAR IS 0, which is also the answer for the 592 maps that
-- carry no weather at all, so "cleared" and "never had any" are deliberately
-- the same value -- as they are on the cartridge, where one enum holds both.
function Commands.g4_overworld_weather(ctx, destVar)
  local ow = ctx.overworld
  local cleared = (ctx.save and ctx.save.gen4WeatherCleared)
                  or (ow and ow.gen4WeatherCleared)
  local def = ow and ow.map and ow.map.def
  local value = cleared and 0 or (tonumber(def and def.weather) or 0)
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
  local modes = { [0] = 'deposit', [1] = 'withdraw', [2] = 'move', [3] = 'items' }
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
 if species then Commands.start_battle(ctx,'wild',species,level) end
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

function Commands.g4_game_version(ctx, destVar)
  local value = Gen4Commands.VERSION_PLATINUM
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
  local breed = require('src.pokemon.DayCare').store(ctx.save, false)
  setVar(ctx.save, destVar, breed and breed.egg ~= nil and 1 or 0)
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
local saidUnlowered = {}
function Commands.g4_unimplemented(_, name, note)
  local key = tostring(name)
  if saidUnlowered[key] then return end
  saidUnlowered[key] = true
  Logger.info("gen4 script: `%s` is decoded but not lowered%s -- the row is "
              .. "stepped over and the script carries on", key,
              note and (" (" .. tostring(note) .. ")") or "")
end

return Gen4Commands
