-- Boxes panel: the 12 PC boxes as a real grid rather than the old 20-row
-- text list.  Three columns:
--   box strip   which boxes have room, so you can see where a deposit lands
--   the grid    5 x 4 = Boxes.CAPACITY, empty cells are dashed and clickable
--   party dock  the deposit source and withdraw target, both in one place
--
-- Selecting a slot points S.editingMon at it, so switching to the Party tab
-- keeps inspecting the same mon.

local BoxesMod = require("src.pokemon.Boxes")
local PartyMod = require("src.pokemon.Party")
local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local M = {}

local COLS = 5
local ROWS = math.ceil(BoxesMod.CAPACITY / COLS)

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local gap = 20 * s
  local pad = 16 * s

  S.selectedBox = Ops.clamp(S.selectedBox or 1, 1, BoxesMod.COUNT)
  S.save.currentBox = S.selectedBox
  local boxes = Ops.boxes(S)
  local box = boxes[S.selectedBox]

  local stripW = math.max(150 * s, math.min(200 * s, w * 0.16))
  local dockW = math.max(220 * s, math.min(300 * s, w * 0.22))
  local gridX = x + stripW + gap
  local gridW = w - stripW - dockW - 2 * gap

  -- ------------------------------------------------------------ box strip
  Kit.card(x, y, stripW, h)
  Kit.caption(x + pad, y + pad, ("BOXES . %d"):format(BoxesMod.COUNT))
  local stripTop = y + pad + Kit.textHeight("caption") + 10 * s
  local stripInner = stripW - 2 * pad
  local bRowH = math.min(30 * s, math.max(22 * s,
    (h - (stripTop - y) - pad - (BoxesMod.COUNT - 1) * 6 * s) / BoxesMod.COUNT))
  for i = 1, BoxesMod.COUNT do
    local ry = stripTop + (i - 1) * (bRowH + 6 * s)
    if ry + bRowH > y + h - pad then break end
    if Kit.row(x + pad, ry, stripInner, bRowH, i == S.selectedBox, PAL.blue, 9 * s) then
      Ops.selectBox(S, i)
    end
    local fill = #boxes[i]
    Kit.text("mono", ("Box %d"):format(i), x + pad + 10 * s,
      ry + (bRowH - Kit.textHeight("mono")) / 2, PAL.text)
    local countW = Kit.textWidth("tiny", tostring(fill))
    Kit.textRight("tiny", tostring(fill), x + pad + stripInner - 10 * s,
      ry + (bRowH - Kit.textHeight("tiny")) / 2, PAL.caption)
    local mx = x + pad + stripInner - 10 * s - countW - 8 * s - 44 * s
    Kit.meter(mx, ry + (bRowH - 5 * s) / 2, 44 * s, 5 * s,
      fill / BoxesMod.CAPACITY * 100, fill >= BoxesMod.CAPACITY and PAL.yellow or PAL.blue)
  end

  -- ------------------------------------------------------------- the grid
  Kit.card(gridX, y, gridW, h)
  local gpad = 18 * s
  local gx = gridX + gpad
  local ginner = gridW - 2 * gpad
  local headH = 30 * s
  Kit.text("tab", ("Box %d"):format(S.selectedBox), gx,
    y + gpad + (headH - Kit.textHeight("tab")) / 2, PAL.heading)
  local titleW = Kit.textWidth("tab", ("Box %d"):format(S.selectedBox))
  Kit.text("mono", ("%d/%d"):format(#box, BoxesMod.CAPACITY),
    gx + titleW + 14 * s, y + gpad + (headH - Kit.textHeight("mono")) / 2, PAL.caption)
  local navW = 34 * s
  if Kit.stepper(gx + ginner - 2 * navW - 8 * s, y + gpad, navW, headH, "<",
      { radius = 8 * s }) then
    Ops.stepBox(S, -1)
  end
  if Kit.stepper(gx + ginner - navW, y + gpad, navW, headH, ">",
      { radius = 8 * s }) then
    Ops.stepBox(S, 1)
  end

  local actH = 34 * s
  local actY = y + h - gpad - actH
  local gridTop = y + gpad + headH + 14 * s
  local gridH = actY - 14 * s - gridTop
  local cellGap = 10 * s
  local cellW = (ginner - cellGap * (COLS - 1)) / COLS
  local cellH = math.min((gridH - cellGap * (ROWS - 1)) / ROWS, 110 * s)

  for i = 1, BoxesMod.CAPACITY do
    local cc = (i - 1) % COLS
    local cr = math.floor((i - 1) / COLS)
    local bx = gx + cc * (cellW + cellGap)
    local by = gridTop + cr * (cellH + cellGap)
    local mon = box[i]
    local selected = (i == S.selectedBoxSlot) and mon ~= nil
    if mon then
      if Kit.row(bx, by, cellW, cellH, selected, PAL.green, 11 * s) then
        Ops.selectBoxSlot(S, i)
      end
      Kit.text("micro", tostring(i), bx + 10 * s, by + 8 * s, PAL.faint)
      Kit.textRight("micro", ("Lv%d"):format(mon.level), bx + cellW - 10 * s,
        by + 8 * s, PAL.caption)
      Kit.textCenter("mono",
        Kit.ellipsize("mono", mon.species, cellW - 12 * s), bx,
        by + cellH / 2 - Kit.textHeight("mono") / 2, cellW, PAL.text)
    else
      -- empty slots are dashed and clickable: clicking one adds a mon there
      Theme.col(PAL.cardBorder, Kit.hover(bx, by, cellW, cellH) and 0.6 or 0.32)
      Theme.dashed(bx, by, cellW, cellH, 11 * s, 6 * s, 5 * s)
      Kit.text("micro", tostring(i), bx + 10 * s, by + 8 * s, PAL.faint)
      Kit.textCenter("micro", "+", bx, by + cellH / 2 - Kit.textHeight("micro") / 2,
        cellW, PAL.faint)
      if Kit.press(bx, by, cellW, cellH) then
        S.selectedBoxSlot = math.min(i, #box + 1)
        Ops.boxAdd(S)
      end
    end
  end

  local wdW = 170 * s
  if Kit.button(gx, actY, wdW, actH, "Withdraw to party",
      { font = "small", radius = 9 * s,
        enabled = #S.save.party < PartyMod.MAX }) then
    Ops.withdraw(S)
  end
  if Kit.button(gx + wdW + 10 * s, actY, 140 * s, actH, "+ Add mon here",
      { font = "small", radius = 9 * s,
        enabled = #box < BoxesMod.CAPACITY }) then
    Ops.boxAdd(S)
  end
  local relW = 110 * s
  if Kit.button(gx + ginner - relW, actY, relW, actH,
      Ops.armLabel(S, "box-release", "Release"),
      { kind = "danger", font = "small", radius = 9 * s }) then
    Ops.release(S)
  end

  -- ----------------------------------------------------------- party dock
  local dx = gridX + gridW + gap
  Kit.card(dx, y, dockW, h)
  Kit.caption(dx + pad, y + pad, "PARTY DOCK")
  Kit.textRight("mono", ("%d/%d"):format(#S.save.party, PartyMod.MAX),
    dx + dockW - pad, y + pad, PAL.caption)
  local dTop = y + pad + Kit.textHeight("caption") + 10 * s
  local dInner = dockW - 2 * pad
  local dRowH = 34 * s
  for i, mon in ipairs(S.save.party) do
    local ry = dTop + (i - 1) * (dRowH + 7 * s)
    if Kit.row(dx + pad, ry, dInner, dRowH, S.editingMon == mon, PAL.green, 9 * s) then
      Ops.selectParty(S, i)
    end
    local lv = ("Lv%d"):format(mon.level)
    local lvW = Kit.textWidth("tiny", lv)
    Kit.textRight("tiny", lv, dx + pad + dInner - 10 * s,
      ry + (dRowH - Kit.textHeight("tiny")) / 2, PAL.caption)
    Kit.text("mono", Kit.ellipsize("mono", mon.species, dInner - 30 * s - lvW),
      dx + pad + 10 * s, ry + (dRowH - Kit.textHeight("mono")) / 2, PAL.text)
  end
  if #S.save.party == 0 then
    Kit.emptyBox(dx + pad, dTop, dInner, 70 * s, "Party is empty.")
  end

  local depY = dTop + math.max(#S.save.party, 2) * (dRowH + 7 * s) + 6 * s
  if Kit.button(dx + pad, depY, dInner, 36 * s, "Deposit selected slot",
      { kind = "accent", font = "small", radius = 9 * s,
        enabled = #S.save.party > 0 }) then
    Ops.deposit(S)
  end
  local noteY = depY + 36 * s + 10 * s
  local noteH = y + h - pad - noteY
  if noteH > Kit.textHeight("tiny") * 2 then
    Kit.textCenter("tiny",
      "Deposit fills the current box first, then the next box with room, and " ..
      "the status bar says where the mon landed.",
      dx + pad, noteY, dInner, PAL.caption)
  end
end

return M
