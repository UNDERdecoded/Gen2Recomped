-- Adapted from Gen1Recomp 535a5ec0 native Gen2 ForgetMoveList.
-- Existing project rights/licences remain applicable. Contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- engine/pokemon/learn.asm:135-166

local Chrome = require("src.ui.Gen2Chrome")

local ForgetMoveList = {
  x = 5, y = 2, interiorW = 13, interiorH = 8,
  cursorX = 6, nameX = 7, y0 = 4, step = 2, rows = 4,
}

function ForgetMoveList.rowY(slot)
  return ForgetMoveList.y0 + (slot - 1) * ForgetMoveList.step
end

function ForgetMoveList.label(entry, moveData)
  if not entry then return "-" end
  local def = moveData and moveData[entry.id]
  return (def and def.name) or entry.id
end

function ForgetMoveList.draw(moves, cursor, moveData, palette)
  Chrome.textbox(ForgetMoveList.x, ForgetMoveList.y,
    ForgetMoveList.interiorW, ForgetMoveList.interiorH)
  for slot = 1, ForgetMoveList.rows do
    local ty = ForgetMoveList.rowY(slot)
    local label = ForgetMoveList.label(moves and moves[slot], moveData)
    if palette then
      Chrome.printThrough(label, ForgetMoveList.nameX, ty, palette)
    else
      Chrome.print(label, ForgetMoveList.nameX, ty)
    end
    if slot == cursor then
      if palette then
        Chrome.cursorThrough(ForgetMoveList.cursorX, ty, palette)
      else
        Chrome.cursor(ForgetMoveList.cursorX, ty)
      end
    end
  end
end

return ForgetMoveList
