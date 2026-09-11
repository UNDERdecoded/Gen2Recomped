-- PC storage: Bill's PC (engine/pokemon/bills_pc.asm).  Gen1 is 12 boxes of
-- 20 (wBoxDataStart); Gen2 is 14 -- NUM_BOXES is 14 there, sBox1..sBox7 in
-- SRAM bank 2 and sBox8..sBox14 in bank 3, which is why the save file splits
-- the box region across two banks at all.  Older saves with a single `box`
-- list are migrated into box 1.

local GameVersion = require("src.core.GameVersion")

local Boxes = {}

Boxes.COUNT = 12        -- Gen1; call Boxes.count() for the running game
Boxes.GEN2_COUNT = 14
Boxes.CAPACITY = 20

-- ...AND EMERALD'S PC IS A DIFFERENT SHAPE AGAIN: 14 boxes of THIRTY.
--
-- That is not a constant to type in either -- the save layout derives it,
-- because the box region has to close exactly on the storage size (see
-- RomExtractorGen3's save-layout checks), so `boxCount` and `boxCapacity`
-- come off the cartridge like everything else.  Without this a Hoenn save
-- had Kanto's twelve boxes of twenty: 180 slots of a full PC unreachable,
-- and a box that reported itself full at 20 of 30.
--
-- Collision.load's idiom -- the overworld hands the dataset over on entry --
-- so this file keeps no Data reference of its own.
local shape = nil

function Boxes.load(data)
  local layout = data and data.save_layout
  local storage = layout and layout.fields and layout.fields.storage
  local count = storage and tonumber(storage.boxCount)
  local capacity = storage and tonumber(storage.boxCapacity)
  if count and capacity and count > 0 and capacity > 0 then
    shape = { count = count, capacity = capacity }
  else
    shape = nil
  end
  return shape
end

function Boxes.count()
  if shape then return shape.count end
  return GameVersion.isGen2() and Boxes.GEN2_COUNT or Boxes.COUNT
end

-- How many fit in one.  Gen 1 and Gen 2 both hold twenty and neither says so
-- anywhere, so they keep the literal; a dataset that states its own wins.
function Boxes.capacity()
  if shape then return shape.capacity end
  return Boxes.CAPACITY
end

function Boxes.ensure(save)
  local count = Boxes.count()
  if not save.boxes then
    save.boxes = {}
    save.currentBox = 1
    if save.box then -- migrate pre-12-box saves
      save.boxes[1] = {}
      for _, mon in ipairs(save.box) do
        table.insert(save.boxes[1], mon)
      end
      save.box = nil
    end
  end
  -- a save made under one generation (or trimmed by a mod) just grows: the
  -- extra Gen2 boxes appear empty rather than being unreachable
  for i = 1, count do
    if save.boxes[i] == nil then save.boxes[i] = {} end
  end
  save.currentBox = math.max(1, math.min(count, save.currentBox or 1))
  return save.boxes
end

function Boxes.active(save)
  return Boxes.ensure(save)[save.currentBox]
end

-- A BOX HAS HOLES IN IT, AND `#` CANNOT SEE THEM.
--
-- The engine's own storage fills from slot 1 and never leaves a gap, so for
-- years a box was a dense list and `#box` was how many were in it.  An
-- IMPORTED Emerald save is not like that: the cartridge keeps a mon at the
-- slot it was put in, so a real PC routinely reads {[3]=..., [7]=..., [20]=...}
-- with nothing at 1.  Lua's `#` on a table like that is 0 -- not "three", and
-- not an error either -- and every question the engine asked about a box was
-- being answered by it:
--
--   * the box counter drew "0/30" over a box with thirty Pokemon in it;
--   * `#box + 1` picked a slot by walking off a border Lua is free to put
--     anywhere, so putting a mon away could land it at slot 31, past the end
--     of the box, where nothing can ever see it again;
--   * and Boxes.deposit read a full box as empty.
--
-- So the two questions get asked by SLOT instead.  Both walk 1..capacity,
-- which is thirty numbers and is not worth caching.
function Boxes.used(box)
  if type(box) ~= "table" then return 0 end
  local used = 0
  for slot = 1, Boxes.capacity() do
    if box[slot] ~= nil then used = used + 1 end
  end
  return used
end

-- The lowest empty slot, which is where the cartridge puts one too, or nil
-- when the box is full.
function Boxes.firstFree(box)
  if type(box) ~= "table" then return nil end
  for slot = 1, Boxes.capacity() do
    if box[slot] == nil then return slot end
  end
  return nil
end

-- Deposit into the current box; overflows into the next box with room
-- (divergence: the original refuses the catch when the box is full --
-- docs/known-differences.md).  Returns the box number used, or nil.
-- EMERALD KEEPS TWO FACTS EITHER SIDE OF THIS WALK, and two of its specials
-- are nothing but readings of them.  SendMonToPC (0806B490):
--
--     SetPCBoxToSendMon(VarGet($4036))      @ where the LAST one went
--     boxId = StorageGetCurrentBox()
--     ...walk boxes and slots until one is free...
--     if GetPCBoxToSendMon() != boxId: FlagClear($8D7)
--     VarSet($4036, boxId)                  @ where THIS one went
--
-- so $4036 is the box the most recent send used, the byte behind
-- GetPCBoxToSendMon (special 487) is what $4036 said BEFORE it, and $8D7 is
-- a show-it-once latch that a send into a different box re-arms.  That is
-- what lets the script say "BOX <old> was full, so it went to BOX <new>"
-- with two specials and no state of its own.
--
-- The port keeps them here rather than at either call site because this
-- function is the only place that knows both boxes, and because the catch
-- path and the gift path both come through it.
local GEN3_BOX_SENT_VAR = 0x4036
local GEN3_BOX_FULL_FLAG = "FLAG_G3_08D7"

local function recordGen3Send(save, boxUsed, slotUsed)
  if not GameVersion.isGen3() then return end
  save.gen3Vars = save.gen3Vars or {}
  local was = math.floor(tonumber(save.gen3Vars[GEN3_BOX_SENT_VAR]) or 0)
  save.gen3PcBoxToSendMon = was
  if was ~= boxUsed then
    save.flags = save.flags or {}
    save.flags[GEN3_BOX_FULL_FLAG] = false
  end
  save.gen3Vars[GEN3_BOX_SENT_VAR] = boxUsed
  -- gSpecialVar_MonBoxId / gSpecialVar_MonBoxPos, which SendMonToPC writes
  -- the moment it finds the slot.  Special 486 renames exactly this one.
  save.gen3MonBox = boxUsed
  save.gen3MonBoxPos = slotUsed
end

Boxes.GEN3_BOX_SENT_VAR = GEN3_BOX_SENT_VAR
Boxes.GEN3_BOX_FULL_FLAG = GEN3_BOX_FULL_FLAG

function Boxes.deposit(save, mon)
  local boxes = Boxes.ensure(save)
  local count = Boxes.count()
  for off = 0, count - 1 do
    local i = ((save.currentBox - 1 + off) % count) + 1
    local slot = Boxes.firstFree(boxes[i])
    if slot then
      boxes[i][slot] = mon
      -- the cartridge counts boxes from zero and its scripts read them that
      -- way, so what is recorded is the index, not this port's number
      recordGen3Send(save, i - 1, slot - 1)
      return i, slot
    end
  end
  return nil
end

return Boxes
