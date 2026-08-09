-- The mon inspector: species, level, DVs and moves for whatever S.editingMon
-- points at (a party slot or a box slot), all recalculated through MonOps so
-- stats stay in sync with the Gen1 formulas.
--
-- This used to be a modal overlay floating over the party list, which hid the
-- roster you were comparing against.  It is now a permanent right-hand column
-- the Party and Boxes panels dock into (rule 1 of the design spec): the list
-- stays visible while you edit, and Escape clears the selection rather than
-- "closing a window".

local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local MonEditor = {}

local DV_KEYS = { "attack", "defense", "speed", "special" }
local STAT_KEYS = {
  { key = "HP", field = "hp" },
  { key = "ATK", field = "attack" },
  { key = "DEF", field = "defense" },
  { key = "SPD", field = "speed" },
  { key = "SPC", field = "special" },
}

-- Front sprites are read straight off the generated cache.  One image per
-- species, cached for the process: the old panel called newImage every frame,
-- which re-decoded a PNG sixty times a second.
local spriteCache = {}
function MonEditor.sprite(S, species)
  if spriteCache[species] ~= nil then return spriteCache[species] or nil end
  local def = S.data.pokemon[species]
  local path = def and def.spriteFront
  if not path or not love.graphics.newImage then
    spriteCache[species] = false
    return nil
  end
  local ok, img = pcall(love.graphics.newImage, path)
  spriteCache[species] = ok and img or false
  return ok and img or nil
end

-- Draw a species sprite fitted into a box, or a dashed placeholder when the
-- cache has no art for it (a modded species, or a headless run).
function MonEditor.drawSprite(S, Kit, species, x, y, size)
  local img = MonEditor.sprite(S, species)
  if img and love.graphics.draw and img.getDimensions then
    local iw, ih = img:getDimensions()
    if iw > 0 and ih > 0 then
      local scale = math.min(size / iw, size / ih)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, x + (size - iw * scale) / 2,
        y + (size - ih * scale) / 2, 0, scale, scale)
      return
    end
  end
  Theme.col(PAL.blue, 0.1)
  love.graphics.rectangle("fill", x, y, size, size, 8 * Kit.scale, 8 * Kit.scale)
  Theme.col(PAL.cardBorder, 0.35)
  Theme.dashed(x, y, size, size, 8 * Kit.scale, 5 * Kit.scale, 4 * Kit.scale)
  Kit.textCenter("micro", (species or "?"):sub(1, 3), x,
    y + size / 2 - Kit.textHeight("micro") / 2, size, PAL.muted)
end

-- Bars are scaled against 400 so a Lv100 legend fills roughly three quarters
-- and the differences between mons stay legible.
local STAT_SCALE = 400

function MonEditor.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  Kit.card(x, y, w, h)
  local mon = S.editingMon
  local pad = 18 * s
  if not mon then
    -- The inspector column is always drawn, so it explains itself rather
    -- than collapsing and reflowing the panel underneath it.
    local tw = math.min(w - 40 * s, 340 * s)
    Kit.textCenter("button",
      "Pick a slot on the left to inspect it. Every change here re-runs the " ..
      "Gen1 stat formulas, so HP and stats stay legal.",
      x + (w - tw) / 2, y + h / 2 - Kit.textHeight("button"), tw, PAL.muted)
    return
  end

  local def = S.data.pokemon[mon.species]
  local cx, cy = x + pad, y + pad
  local inner = w - 2 * pad
  -- Backstop for a window too short for even the compacted rhythm below:
  -- nothing this panel draws may land outside its own card (#497).  Party
  -- draws the inspector last, so no outer clip is lost by the pop at the end.
  Kit.pushClip(x, y, w, h)

  -- ---------------------------------------------------------- header row
  local sprite = 96 * s
  MonEditor.drawSprite(S, Kit, mon.species, cx, cy, sprite)
  local hx = cx + sprite + 18 * s
  local hw = inner - sprite - 18 * s

  Kit.text("title", mon.species, hx, cy, PAL.heading)
  local nameW = Kit.textWidth("title", mon.species)
  Kit.text("tiny", ("#%03d"):format(def and def.dex or 0), hx + nameW + 12 * s,
    cy + Kit.textHeight("title") - Kit.textHeight("tiny") - 2 * s, PAL.caption)

  -- One control instead of a pair of arrows: cycling walked the catalog an
  -- entry at a time (151 taps to cross the dex) and ran a full MonOps
  -- recalculation on every step, including on records the Gen1 formulas
  -- cannot use, which is what crashed the editor (#541).  This opens the
  -- searchable picker; the species name itself is a second, larger target.
  local pickH = 30 * s
  local pickW = math.min(150 * s, math.max(90 * s, hw * 0.6))
  local px = hx + hw - pickW
  local py = cy + (Kit.textHeight("title") - pickH) / 2
  local openPicker = Kit.button(px, py, pickW, pickH, "Change species",
    { kind = "accent", font = "small", radius = 8 * s })
  if not openPicker then
    openPicker = Kit.press(hx, cy, math.max(0, px - hx - 10 * s),
      Kit.textHeight("title"))
  end
  if openPicker then Ops.openSpeciesPicker(S, Kit) end

  -- level stepper: -5 -1 [Lv] +1 +5, matching MonOps.setLevel's 1..100 clamp
  local ly = cy + Kit.textHeight("title") + 14 * s
  local lh = 28 * s
  Kit.caption(hx, ly + (lh - Kit.textHeight("caption")) / 2, "LEVEL")
  local lx = hx + 52 * s
  local bw = 40 * s
  for _, d in ipairs({ { "-5", -5 }, { "-1", -1 } }) do
    if Kit.stepper(lx, ly, bw, lh, d[1], { font = "small", radius = 7 * s }) then
      Ops.setLevel(S, mon, mon.level + d[2])
    end
    lx = lx + bw + 8 * s
  end
  Kit.textCenter("monoBig", tostring(mon.level), lx,
    ly + (lh - Kit.textHeight("monoBig")) / 2, 58 * s, PAL.heading)
  lx = lx + 58 * s + 8 * s
  for _, d in ipairs({ { "+1", 1 }, { "+5", 5 } }) do
    if Kit.stepper(lx, ly, bw, lh, d[1], { font = "small", radius = 7 * s }) then
      Ops.setLevel(S, mon, mon.level + d[2])
    end
    lx = lx + bw + 8 * s
  end
  Kit.text("mono", ("EXP %d"):format(mon.exp or 0), lx + 6 * s,
    ly + (lh - Kit.textHeight("mono")) / 2, PAL.muted)

  -- ------------------------------------------------------- derived stats
  local statsY = cy + sprite + 18 * s
  Kit.caption(cx, statsY, "STATS . recalculated from level + DVs")
  statsY = statsY + Kit.textHeight("caption") + 10 * s
  local gap = 12 * s
  local cellW = (inner - gap * 4) / 5
  -- Everything below the header competes for one vertical budget.  At the
  -- design size it is generous; in a 720px-tall window (a phone held
  -- sideways) it is not, and the DV / move rows used to run past the card and
  -- paint over the status bar (#497).  Shrink the two flexible blocks -- the
  -- stat tiles and the DV / move rows -- instead of overflowing, with floors
  -- that keep every row the 26px target Kit's rule 6 promises.  statsY is
  -- already past the STATS caption here, so only the DVs / MOVES caption is
  -- subtracted.
  local actH = 34 * s
  local rowGap = 8 * s
  local budget = (y + h - pad) - statsY - (Kit.textHeight("caption") + 10 * s)
    - 18 * s - actH - 4 * s
  local cellH = Theme.clamp(budget * 0.3, 46 * s, 68 * s)
  local rowH = Theme.clamp((budget - cellH) / 4 - rowGap, 26 * s, 34 * s)
  for i, st in ipairs(STAT_KEYS) do
    local bx = cx + (i - 1) * (cellW + gap)
    Theme.row(bx, statsY, cellW, cellH, 10 * s, 0.6)
    local value = (mon.stats and mon.stats[st.field]) or 0
    Kit.text("micro", st.key, bx + 12 * s, statsY + 10 * s, PAL.caption)
    Kit.text("stat", tostring(value), bx + 12 * s,
      statsY + 10 * s + Kit.textHeight("micro") + 4 * s, PAL.heading)
    Kit.meter(bx + 12 * s, statsY + cellH - 14 * s, cellW - 24 * s, 5 * s,
      value / STAT_SCALE * 100, PAL.blue)
  end

  -- --------------------------------------------------- DVs | moves split
  local colY = statsY + cellH + 18 * s
  local colGap = 18 * s
  local colW = (inner - colGap) / 2
  local rightX = cx + colW + colGap

  Kit.caption(cx, colY, "DVs")
  Kit.textRight("tiny", ("HP DV auto-derived . %d"):format(mon.dvs.hp or 0),
    cx + colW, colY, PAL.caption)
  Kit.caption(rightX, colY, "MOVES")
  Kit.textRight("tiny", "click a slot to cycle", rightX + colW, colY, PAL.caption)

  local rowY = colY + Kit.textHeight("caption") + 10 * s

  for i, key in ipairs(DV_KEYS) do
    local ry = rowY + (i - 1) * (rowH + rowGap)
    Theme.row(cx, ry, colW, rowH, 10 * s, 0.6)
    local v = mon.dvs[key] or 0
    Kit.text("tiny", key:upper(), cx + 10 * s,
      ry + (rowH - Kit.textHeight("tiny")) / 2, PAL.muted)
    local btn = 26 * s
    local btnX = cx + colW - 10 * s - 3 * btn - 18 * s
    local meterX = cx + 66 * s
    local meterW = math.max(20 * s, btnX - meterX - 34 * s)
    Kit.meter(meterX, ry + (rowH - 8 * s) / 2, meterW, 8 * s, v / 15 * 100,
      v >= 15 and PAL.green or (v >= 10 and PAL.blue or PAL.steel))
    Kit.textRight("monoRow", tostring(v), meterX + meterW + 28 * s,
      ry + (rowH - Kit.textHeight("monoRow")) / 2, PAL.heading)
    if Kit.stepper(btnX, ry + (rowH - btn) / 2, btn, btn, "-") then
      Ops.setDv(S, mon, key, v - 1)
    end
    if Kit.stepper(btnX + btn + 6 * s, ry + (rowH - btn) / 2, btn, btn, "+") then
      Ops.setDv(S, mon, key, v + 1)
    end
    if Kit.button(btnX + 2 * btn + 12 * s, ry + (rowH - btn) / 2, btn, btn,
        "15", { kind = "good", font = "micro", radius = 6 * s }) then
      Ops.setDv(S, mon, key, 15)
    end
  end

  for slot = 1, 4 do
    local ry = rowY + (slot - 1) * (rowH + rowGap)
    Theme.row(rightX, ry, colW, rowH, 10 * s, 0.6)
    local mv = mon.moves and mon.moves[slot]
    local clear = 24 * s
    local clearX = rightX + colW - 10 * s - clear
    local ppText = mv and ("PP %d"):format(mv.pp or 0) or ""
    local ppW = Kit.textWidth("tiny", ppText)
    Kit.text("mono", tostring(slot), rightX + 10 * s,
      ry + (rowH - Kit.textHeight("mono")) / 2, PAL.faint)
    local nameX = rightX + 28 * s
    local nameW2 = math.max(20 * s, clearX - 12 * s - ppW - nameX)
    Kit.text("monoRow", Kit.ellipsize("monoRow", mv and mv.id or "-- --", nameW2),
      nameX, ry + (rowH - Kit.textHeight("monoRow")) / 2,
      mv and PAL.text or PAL.faint)
    Kit.textRight("tiny", ppText, clearX - 10 * s,
      ry + (rowH - Kit.textHeight("tiny")) / 2, PAL.caption)
    -- the row body cycles, the x empties: two targets, no modal picker
    if Kit.press(rightX, ry, clearX - rightX - 4 * s, rowH) then
      Ops.cycleMove(S, mon, slot)
    end
    if Kit.button(clearX, ry + (rowH - clear) / 2, clear, clear, "x",
        { kind = "danger", font = "tiny", radius = 6 * s }) then
      Ops.clearMove(S, mon, slot)
    end
  end

  local actY = rowY + 4 * (rowH + rowGap) + 4 * s
  local actW = (colW - 10 * s) / 2
  if Kit.button(rightX, actY, actW, actH, "Reset to learnset",
      { font = "small", radius = 9 * s }) then
    Ops.resetMoves(S, mon)
  end
  if Kit.button(rightX + actW + 10 * s, actY, actW, actH, "Full heal",
      { kind = "good", font = "small", radius = 9 * s }) then
    Ops.healMon(S, mon)
  end
  Kit.popClip()
end

return MonEditor
