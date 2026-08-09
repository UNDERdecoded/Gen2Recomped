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

function Boxes.count()
  return GameVersion.isGen2() and Boxes.GEN2_COUNT or Boxes.COUNT
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

-- Deposit into the current box; overflows into the next box with room
-- (divergence: the original refuses the catch when the box is full --
-- docs/known-differences.md).  Returns the box number used, or nil.
function Boxes.deposit(save, mon)
  local boxes = Boxes.ensure(save)
  local count = Boxes.count()
  for off = 0, count - 1 do
    local i = ((save.currentBox - 1 + off) % count) + 1
    if #boxes[i] < Boxes.CAPACITY then
      table.insert(boxes[i], mon)
      return i
    end
  end
  return nil
end

return Boxes
