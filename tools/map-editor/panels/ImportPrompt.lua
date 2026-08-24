-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- "This map pack needs these cartridges."
--
-- WHY THIS IS A DIALOG AND NOT A STATUS LINE.
--
-- It was a status line: one row of small text at the foot of the window,
-- saying `installed MAP_EDITS_CRYSTAL - It uses maps from Pokemon Red, which
-- you have imported...`. Everything in it was true and it is the wrong weight
-- for what it says. A map pack that names another cartridge is not
-- self-contained -- it draws its maps out of an import the reader has to keep
-- -- and that is a condition on everything they do with it afterwards, learned
-- once, at install, and never surfaced again. A line that shares the bottom of
-- the screen with "8 x 8 cells - drag to pan" is read as chrome.
--
-- ONE ROW PER CARTRIDGE, ANSWERED INDEPENDENTLY. The interesting case is a
-- pack built from two ROMs where the reader has one of them: told "some
-- cartridges are missing" they go and check both, having already got one. A
-- tick against Red and a cross against Blue is a shorter sentence and a more
-- useful one.
--
-- THE TWO ENDINGS ARE DIFFERENT ADVICE, which is why they are not one string
-- with a word swapped. Present means "keep it -- this is a dependency you now
-- have"; absent means "import it -- until you do, this pack cannot draw". The
-- first is a caution about the future and the second is an instruction for
-- now.
--
-- OVER THE WHOLE WINDOW, painted after the frame, for the reason TilesetPrompt
-- is: Kit has no z-order, so "on top" and "drawn last" are the same sentence.

local okKit, KitModule = pcall(require, "Kit")
if not okKit then KitModule = nil end

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, green = { 120, 210, 130 },
  caption = { 160, 175, 205 }, text = { 226, 232, 245 },
}

local ImportPrompt = {}

-- Raise it on the result of `ModImport.install`.
--
-- RAISED EVEN WHEN EVERY CARTRIDGE IS PRESENT, and even when the pack needs
-- none: an install is a thing the reader just asked for and a dialog that only
-- appears on bad news teaches them that silence means it worked -- which is
-- the same lesson that made the old status line invisible.
function ImportPrompt.raise(S, result)
  if not (S and type(result) == "table") then return false end
  S.importAsk = {
    id = result.id,
    needs = result.needs or {},
  }
  return true
end

function ImportPrompt.close(S)
  if S then
    S.importAsk = nil
    if KitModule and KitModule.forgetModal then
      KitModule.forgetModal("import-ask")
    end
  end
end

-- Of the declared cartridges, the ones that are not imported.
function ImportPrompt.missing(ask)
  local out = {}
  for _, row in ipairs((ask and ask.needs) or {}) do
    if not row.imported then out[#out + 1] = row end
  end
  return out
end

function ImportPrompt.draw(S, Kit)
  local ask = S and S.importAsk
  if not ask then return false end

  local s = Kit.scale
  local winW, winH = love.graphics.getDimensions()
  local pad = 16 * s
  local btnH = 34 * s
  local lineH = 15 * s
  local rowH = 30 * s

  local pw = math.max(360 * s, math.min(520 * s, winW - 40 * s))
  local x = math.floor((winW - pw) / 2)
  local w = pw - 2 * pad

  local missing = ImportPrompt.missing(ask)
  local needs = ask.needs or {}

  -- MEASURED BEFORE IT IS DRAWN, so the card is the height of its own text
  -- rather than a number that has to be kept in step with every edit.
  local head
  if #needs == 0 then
    head = string.format("%s is installed. It uses only this game's own maps, "
                         .. "so it needs nothing else.", tostring(ask.id))
  elseif #missing == 0 then
    head = string.format(
      "%s is installed, and it draws its maps out of the cartridges below. "
      .. "You have them all. Keep them imported -- if one goes, this pack's "
      .. "maps stop drawing.", tostring(ask.id))
  else
    head = string.format(
      "%s is installed but CANNOT DRAW ITS MAPS YET. It borrows art from the "
      .. "cartridges below, and the ones marked NOT IMPORTED are not here. "
      .. "Import them and the pack works -- nothing needs reinstalling.",
      tostring(ask.id))
  end
  local headLines = Kit.wrap("small", head, w)

  local ph = pad + Kit.textHeight("caption") + 8 * s
           + #headLines * lineH + 12 * s
           + #needs * rowH + (#needs > 0 and 10 * s or 0)
           + btnH + pad
  local y = math.max(20 * s, math.floor((winH - ph) / 2))

  -- THE GUARD RUNS BEFORE ANY WIDGET OF THIS DIALOG IS DRAWN. `Kit.tapAway`
  -- swallows the click on the frame the dialog goes up, and it can only do
  -- that for widgets drawn after it -- asking at the bottom would let the OK
  -- button take the very click that opened the dialog and dismiss it unread.
  local tappedAway = Kit.tapAway("import-ask", x, y, pw, ph)

  love.graphics.setColor(0.03, 0.04, 0.11, 0.62)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", x, y, pw, ph, 10 * s, 10 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(x, y, pw, ph)

  local tx = x + pad
  local ty = y + pad
  Kit.caption(tx, ty, (#missing > 0) and "ONE MORE STEP" or "MAP PACK INSTALLED")
  ty = ty + Kit.textHeight("caption") + 8 * s

  for _, line in ipairs(headLines) do
    Kit.text("small", line, tx, ty, (#missing > 0) and PAL.text or PAL.muted)
    ty = ty + lineH
  end
  ty = ty + 12 * s

  -- ------------------------------------------------------ one row per ROM
  for _, row in ipairs(needs) do
    Kit.row(tx, ty, w, rowH - 4 * s, false)
    Kit.text("body", Kit.ellipsize("body", tostring(row.name), w - 140 * s),
             tx + 8 * s, ty + 5 * s)
    -- The STATE and the ADVICE in one phrase, per cartridge: a bare tick
    -- leaves the reader to work out what to do about it, and the whole point
    -- of a row per cartridge is that the two rows want different things.
    local mark = row.imported and "IMPORTED - keep it" or "NOT IMPORTED"
    local col = row.imported and PAL.green or PAL.red
    Kit.text("small", mark, tx + w - 130 * s, ty + 7 * s, col)
    ty = ty + rowH
  end
  if #needs > 0 then ty = ty + 10 * s end

  -- ---------------------------------------------------------------- answers
  local result = nil
  if #missing > 0 then
    -- CLOSE THE EDITOR TO GET AT THE IMPORTER, because that is where importing
    -- a cartridge happens and there is no second door to it from in here.
    -- Offered rather than done: the reader may have unsaved map edits, and a
    -- button that leaves without asking would be the worse bug.
    local halfW = (w - 8 * s) / 2
    if Kit.button(tx, ty, halfW, btnH, "CLOSE EDITOR & IMPORT",
                  { font = "small", kind = "accent" }) then
      result = "leave"
    end
    if Kit.button(tx + halfW + 8 * s, ty, halfW, btnH, "LATER",
                  { font = "small" }) then
      result = "ok"
    end
  else
    if Kit.button(tx, ty, w, btnH, "OK", { font = "small", kind = "accent" }) then
      result = "ok"
    end
  end

  if not result and tappedAway then result = "ok" end

  if result == "leave" then
    ImportPrompt.close(S)
    -- ASKED FOR, NOT DONE HERE. `App.close` is the editor's own way out and it
    -- carries the unsaved-map-edits guard; calling the host's `onClose`
    -- directly from a panel would walk straight past that and lose the work
    -- this dialog just interrupted. The flag is read by App right after this
    -- draw, where `App.close` is in scope.
    S.importLeave = true
  elseif result then
    ImportPrompt.close(S)
  end
  return true
end

function ImportPrompt.keypressed(S, key)
  if not (S and S.importAsk) then return false end
  if key == "escape" or key == "return" or key == "kpenter"
     or key == "space" then
    ImportPrompt.close(S)
    return true
  end
  return true      -- a modal swallows the rest rather than letting it through
end

return ImportPrompt
