-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT A TRAINER SAYS, AND WHY NOBODY IN SINNOH SAID ANYTHING.
--
-- `scripts_battles.s` is the one script every trainer battle in Platinum runs
-- through -- `Battles_Trainer` when you walk up to one, `Battles_Approaching
-- Trainer` when one spots you -- and its opening is three commands long:
--
--     OpenMessage
--     GetTrainerMessageTypes VAR_0x8000, VAR_0x8001, VAR_0x8002
--     PrintTrainerDialogue VAR_0x8004, VAR_0x8000
--
-- Not one of the three was lowered, so all three took the unknown-command
-- path: logged, stepped over.  The battle then began on the next line.  Every
-- trainer in the region fought in SILENCE -- no challenge, no defeat line, no
-- "you do not have two Pokemon" refusal -- and because nothing errored and the
-- battle itself worked, there was nothing to go looking for.
--
-- THE TEXT WAS ALREADY IN THE CACHE.  All 2,497 trainer lines have been in
-- `text.lua` under `TEXT_B0617_00000` and up since the first import, written by
-- `extractText` along with every other bank.  What was missing was the INDEX:
-- which of those entries belongs to which trainer, and as what.  That index is
-- two cartridge files this extractor never opened.
--
-- THE MECHANISM, read from `Trainer_LoadMessage` (pokeplatinum
-- src/trainer_data.c) rather than reasoned out from shapes:
--
--   /poketool/trmsg/trtblofs.narc  member 0 -- one u16 per trainer id: the
--                                  BYTE offset into the table below at which
--                                  that trainer's run of records begins.
--   /poketool/trmsg/trtbl.narc     member 0 -- a flat array of 4-byte records,
--                                  { u16 trainerId, u16 messageType }.
--   bank 617 of /msgdata/pl_msg.narc  the strings themselves, and the entry
--                                  index of the record at byte `offset` is
--                                  `offset / 4`.
--
-- So a record's own position in the table IS its string's index -- there is no
-- third table pairing them.  The walk is the cartridge's, and BOTH of its
-- break conditions carry weight:
--
--     offset = trtblofs[trainerId]
--     while offset ~= size do
--       t, mt = the record at offset
--       if t == trainerId and mt == wanted then return offset / 4 end
--       if t ~= trainerId then break end     -- walked off the end of the run
--       offset = offset + 4
--     end
--
-- AND ZERO IS NOT A VALID START.  `trtblofs[0]` is 0 -- and so is the entry
-- for trainers 5, 6, 7, 8 and 87 others: 92 of the 928 trainers in the
-- cartridge have no messages at all.  Record 0 belongs to trainer 247.  A
-- reading that took "offset 0" to mean "starts at the beginning of the table"
-- would therefore hand TRAINER_NONE -- and ninety-one real trainers --
-- somebody else's dialogue, which is a bug that produces fluent, plausible,
-- completely wrong text.  The `t ~= trainerId` test is the whole reason 0
-- means "none", and it is why this walks rather than slices.
--
-- WHY THIS IS KNOWN TO BE RIGHT.  Three counts, taken three different ways,
-- agree, and none of them had to:
--
--   * trtbl member 0 is 9,988 bytes, so it holds 2,497 records.
--   * walking all 928 trainers reaches 2,497 records -- every one of them,
--     each exactly once, none left unreachable.
--   * bank 617 declares 2,497 strings.
--
-- A wrong offset base, a wrong stride, or an off-by-one anywhere in the walk
-- breaks the middle number away from the other two.  And the text that comes
-- out reads: trainer 1 says "You're a Pokemon Trainer, and so am I! / Our eyes
-- met, so battle we must!", which is what a Youngster on Route 202 says.
--
-- TRMSG_WIN IS 100, AND APPEARS NOWHERE IN THIS TABLE.  The enum runs 0..19
-- and then jumps to 100 for it, and the field table holds no record of that
-- type at all -- the battle system loads it directly rather than through a
-- field script.  A reader that assumed the enum was dense would size an array
-- eighty slots too long for a type this file will never produce.
--
-- WHAT THE SPREAD LOOKS LIKE, measured over the cartridge, because the shape
-- of it is itself a check on the walk: 516 trainers have a PRE_BATTLE line,
-- 812 a DEFEAT line, 516 a POST_BATTLE line and 382 a REMATCH line.  More
-- trainers speak when beaten than when challenged, which is right: the gym
-- leaders and the rivals get their challenges from their own map scripts.

local Gen4TrainerMessages = {}

Gen4TrainerMessages.TABLE_PATH = "/poketool/trmsg/trtbl.narc"
Gen4TrainerMessages.OFFSET_PATH = "/poketool/trmsg/trtblofs.narc"

-- Bank 617 of pl_msg.narc.  Bank 618 is the trainer NAMES and 619 the class
-- names; the three sit together and are a byte apart in the only place the
-- order is written down (`generated/text_banks.txt`, where the line number is
-- the bank index plus one), so this is the easiest of the three to get wrong
-- by one and the easiest to notice: off-by-one here renders names as dialogue.
Gen4TrainerMessages.BANK = 617

-- Record stride and the implied record count divisor.
Gen4TrainerMessages.RECORD_BYTES = 4

-- `enum TrainerMessageType`, transcribed from
-- pokeplatinum generated/trainer_message_types.txt.  Written as explicit
-- indices rather than as a sequence because of the jump to 100 at the end: in
-- Lua an array constructor would quietly renumber WIN to 20.
Gen4TrainerMessages.TYPES = {
  [0] = "pre_battle",
  [1] = "defeat",
  [2] = "post_battle",
  [3] = "pre_double_battle_1",
  [4] = "double_battle_defeat_1",
  [5] = "post_double_battle_1",
  [6] = "double_battle_not_enough_pokemon_1",
  [7] = "pre_double_battle_2",
  [8] = "double_battle_defeat_2",
  [9] = "post_double_battle_2",
  [10] = "double_battle_not_enough_pokemon_2",
  [11] = "not_morning_unused",
  [12] = "not_night_unused",
  [13] = "first_damage",
  [14] = "active_battler_half_hp",
  [15] = "last_battler",
  [16] = "last_battler_half_hp",
  [17] = "rematch",
  [18] = "double_battle_rematch_1",
  [19] = "double_battle_rematch_2",
  [100] = "win",
}

Gen4TrainerMessages.TYPE_IDS = {}
for id, name in pairs(Gen4TrainerMessages.TYPES) do
  Gen4TrainerMessages.TYPE_IDS[name] = id
end

-- The four `GetTrainerMessageTypes` answers, from `ScrCmd_GetTrainerMessage
-- Types` and its rematch twin (pokeplatinum src/scrcmd_trainer.c).  Each row is
-- { preBattle, postBattle, notEnoughPokemon } for one (doubles?, battlerIndex)
-- pair, and the ZEROES ARE THE CARTRIDGE'S: in the singles cases it writes a
-- literal 0 into the "not enough Pokemon" slot and the rematch command writes a
-- literal 0 into the "post battle" slot.  0 is PRE_BATTLE, not "none", so those
-- slots name a real message type -- a faithful quirk, kept rather than tidied
-- into nil, because the scripts that could read them are gated on the doubles
-- branch and never do.  A nil here would be a difference from the cartridge
-- that no script exposes, which is exactly the kind that survives for years.
Gen4TrainerMessages.SCRIPT_TYPES = {
  singles = { 0, 2, 0 },
  doubles_first = { 3, 5, 6 },
  doubles_second = { 7, 9, 10 },
}
Gen4TrainerMessages.SCRIPT_TYPES_REMATCH = {
  singles = { 17, 0, 0 },
  doubles_first = { 18, 0, 6 },
  doubles_second = { 19, 0, 10 },
}

local floor = math.floor

local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end

-- `trtblofs[trainerId]`, or nil past the end of the table.
function Gen4TrainerMessages.offsetFor(offsetBytes, trainerId)
  if type(offsetBytes) ~= "string" then return nil end
  local id = tonumber(trainerId)
  if not id or id < 0 or id % 1 ~= 0 then return nil end
  return u16(offsetBytes, id * 2)
end

-- How many trainers the offset table covers.  928 on Platinum, which is also
-- the number of entries in the name bank and the number of members in
-- trdata.narc -- three readings of "how many trainers are there" that agree.
function Gen4TrainerMessages.trainerCount(offsetBytes)
  if type(offsetBytes) ~= "string" then return 0 end
  return floor(#offsetBytes / 2)
end

function Gen4TrainerMessages.recordCount(tableBytes)
  if type(tableBytes) ~= "string" then return 0 end
  return floor(#tableBytes / Gen4TrainerMessages.RECORD_BYTES)
end

-- THE CARTRIDGE'S WALK, and the only place it is spelled.  `forTrainer` and
-- `find` both go through this so the two cannot drift apart: a lookup that
-- disagreed with the table it was built from is the failure this file is here
-- to make impossible.
--
-- `visit(messageType, entryIndex)` is called once per record in the run, in
-- cartridge order.  Returning a non-nil value stops the walk and `walk`
-- returns it, which is how `find` short-circuits exactly where the C does.
function Gen4TrainerMessages.walk(tableBytes, offsetBytes, trainerId, visit)
  local size = type(tableBytes) == "string" and #tableBytes or 0
  local offset = Gen4TrainerMessages.offsetFor(offsetBytes, trainerId)
  if not offset or size == 0 then return nil end
  local id = tonumber(trainerId)
  local stride = Gen4TrainerMessages.RECORD_BYTES
  -- `while offset ~= size` is the cartridge's condition verbatim.  `<` would
  -- be the safer-looking spelling and would also be a different program: the
  -- records are 4-aligned and `size` is a multiple of 4, so the two agree on
  -- this cartridge, and a table where they did not agree is one this walk
  -- should refuse rather than quietly read past.  `offset > size` is treated
  -- as the end for exactly that reason.
  while offset < size do
    local t = u16(tableBytes, offset)
    local mt = u16(tableBytes, offset + 2)
    if not t or not mt then return nil end
    if t ~= id then return nil end
    local stop = visit(mt, floor(offset / stride))
    if stop ~= nil then return stop end
    offset = offset + stride
  end
  return nil
end

-- `Trainer_LoadMessage`: the bank 617 entry index for one (trainer, type), or
-- nil when that trainer has no line of that type -- which is the common case.
-- 2,497 pairs exist out of 928 x 20 possible.
function Gen4TrainerMessages.find(tableBytes, offsetBytes, trainerId, messageType)
  local wanted = tonumber(messageType)
  if not wanted then return nil end
  return Gen4TrainerMessages.walk(tableBytes, offsetBytes, trainerId,
    function(mt, index)
      if mt == wanted then return index end
      return nil
    end)
end

-- `Trainer_HasMessageType`, which is the same walk with the answer thrown away.
function Gen4TrainerMessages.has(tableBytes, offsetBytes, trainerId, messageType)
  return Gen4TrainerMessages.find(tableBytes, offsetBytes, trainerId,
                                  messageType) ~= nil
end

-- One trainer's whole run, as { [messageType] = entryIndex }, or nil when the
-- trainer has none.  Nil rather than an empty table so the extractor writes 836
-- rows instead of 928, 92 of which would be empty tables that still cost a line
-- of cache each and read as "has messages" to anything doing a truth test.
function Gen4TrainerMessages.forTrainer(tableBytes, offsetBytes, trainerId)
  local out, n = {}, 0
  Gen4TrainerMessages.walk(tableBytes, offsetBytes, trainerId,
    function(mt, index)
      -- First record wins on a repeat, which is what the C does: its walk
      -- returns on the first match.  No trainer in the cartridge repeats a
      -- type, and `all`'s report counts it if one ever does.
      if out[mt] == nil then out[mt] = index; n = n + 1 end
      return nil
    end)
  if n == 0 then return nil end
  return out, n
end

-- Every trainer, plus a report whose numbers are the controls described in the
-- header: `records` and `reached` must be equal, and both must equal the entry
-- count of bank 617.
function Gen4TrainerMessages.all(tableBytes, offsetBytes)
  local out = {}
  local trainers = Gen4TrainerMessages.trainerCount(offsetBytes)
  local records = Gen4TrainerMessages.recordCount(tableBytes)
  local seen, reached, pairsCount, withMessages, duplicates = {}, 0, 0, 0, 0
  local maxType = -1
  for id = 0, trainers - 1 do
    local row, n = Gen4TrainerMessages.forTrainer(tableBytes, offsetBytes, id)
    if row then
      out[id] = row
      withMessages = withMessages + 1
      pairsCount = pairsCount + n
      for mt, index in pairs(row) do
        if mt > maxType then maxType = mt end
        if seen[index] then duplicates = duplicates + 1 end
        if not seen[index] then seen[index] = true; reached = reached + 1 end
      end
    end
  end
  return out, {
    trainers = trainers,
    withMessages = withMessages,
    withoutMessages = trainers - withMessages,
    records = records,
    reached = reached,
    unreachable = records - reached,
    pairs = pairsCount,
    duplicates = duplicates,
    maxType = maxType,
    bank = Gen4TrainerMessages.BANK,
  }
end

return Gen4TrainerMessages
