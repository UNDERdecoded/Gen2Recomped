-- Pokedex panel: a completion header with seen / owned meters and the bulk
-- actions, then a four-column species grid where each row carries two
-- independent toggle chips.
--
-- The game's implications are enforced in Ops (owning implies seen, un-seeing
-- clears owned), so a hand-edited dex can never end up in a state the running
-- game would reject.

local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local M = {}

local COLS = 4

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 20 * s
  local dex = Ops.dex(S)
  local species = S.cat.species
  local seen, owned, total = Ops.dexCounts(S)

  Kit.card(x, y, w, h)
  local cx = x + pad
  local inner = w - 2 * pad

  -- ------------------------------------------------------------- header
  Kit.caption(cx, y + pad, "POKEDEX")
  Kit.text("headline", ("%d / %d owned"):format(owned, total), cx,
    y + pad + Kit.textHeight("caption") + 4 * s, PAL.heading)
  local headH = Kit.textHeight("caption") + 4 * s + Kit.textHeight("headline")
  local headW = math.max(Kit.captionWidth("POKEDEX"),
    Kit.textWidth("headline", ("%d / %d owned"):format(owned, total)))

  -- bulk actions, laid out from the right edge inward
  local actH = 34 * s
  local actY = y + pad + (headH - actH) / 2
  local buttons = {
    { label = "Own party + boxes", kind = "ghost", fn = Ops.dexStamp },
    { label = "See all", kind = "accent", fn = Ops.dexSeeAll },
    { label = "Own all", kind = "good", fn = Ops.dexOwnAll },
  }
  local rightEdge = cx + inner
  local clearLabel = Ops.armLabel(S, "dex-clear", "Wipe dex")
  local clearW = Kit.textWidth("small", clearLabel) + 32 * s
  rightEdge = rightEdge - clearW
  if Kit.button(rightEdge, actY, clearW, actH, clearLabel,
      { kind = "danger", font = "small", radius = 9 * s }) then
    Ops.dexClear(S)
  end
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    local bw = Kit.textWidth("small", b.label) + 32 * s
    rightEdge = rightEdge - 10 * s - bw
    if Kit.button(rightEdge, actY, bw, actH, b.label,
        { kind = b.kind, font = "small", radius = 9 * s }) then
      b.fn(S)
    end
  end

  -- the two completion meters fill whatever the header leaves between the
  -- headline and the button cluster
  local meterX = cx + headW + 24 * s
  local meterW = rightEdge - 24 * s - meterX
  if meterW > 120 * s then
    local my = y + pad
    Kit.text("tiny", "SEEN", meterX, my, PAL.caption)
    Kit.textRight("tiny", ("%d/%d"):format(seen, total), meterX + meterW, my, PAL.caption)
    Kit.meter(meterX, my + Kit.textHeight("tiny") + 4 * s, meterW, 7 * s,
      seen / math.max(total, 1) * 100, PAL.blue)
    local my2 = my + Kit.textHeight("tiny") + 4 * s + 7 * s + 10 * s
    Kit.text("tiny", "OWNED", meterX, my2, PAL.caption)
    Kit.textRight("tiny", ("%d/%d"):format(owned, total), meterX + meterW, my2, PAL.caption)
    Kit.meter(meterX, my2 + Kit.textHeight("tiny") + 4 * s, meterW, 7 * s,
      owned / math.max(total, 1) * 100, PAL.green)
  end

  -- --------------------------------------------------------- species grid
  local pagerH = 30 * s
  local pagerY = y + h - pad - pagerH
  local gridTop = y + pad + headH + 18 * s
  local rowH = 38 * s
  local rowGap = 8 * s
  local colGap = 16 * s
  local colW = (inner - colGap * (COLS - 1)) / COLS
  local perCol = math.max(1, math.floor((pagerY - 12 * s - gridTop) / (rowH + rowGap)))
  local perPage = perCol * COLS
  S.dexOffset = Ops.clamp(S.dexOffset or 0, 0, math.max(0, #species - perPage))

  local chipW = 46 * s
  local chipH = 22 * s
  for i = 1, math.min(perPage, #species - S.dexOffset) do
    local id = species[S.dexOffset + i]
    local ci = (i - 1) % COLS
    local ri = math.floor((i - 1) / COLS)
    local rx = cx + ci * (colW + colGap)
    local ry = gridTop + ri * (rowH + rowGap)
    local isSeen = dex.seen[id] == true
    local isOwned = dex.owned[id] == true

    Theme.row(rx, ry, colW, rowH, 9 * s, 0.6)
    local def = S.data.pokemon[id]
    Kit.text("micro", ("%03d"):format(def and def.dex or 0), rx + 10 * s,
      ry + (rowH - Kit.textHeight("micro")) / 2, PAL.faint)
    local nameX = rx + 44 * s
    local nameW = colW - 10 * s - 2 * (chipW + 6 * s) - (nameX - rx)
    Kit.text("mono", Kit.ellipsize("mono", id, nameW), nameX,
      ry + (rowH - Kit.textHeight("mono")) / 2,
      isOwned and PAL.text or (isSeen and PAL.muted or PAL.faint))

    local sx = rx + colW - 10 * s - 2 * chipW - 6 * s
    if Kit.chip(sx, ry + (rowH - chipH) / 2, chipW, chipH, "SEEN", isSeen,
        PAL.blue, PAL.steel) then
      Ops.dexSeen(S, id, not isSeen)
    end
    if Kit.chip(sx + chipW + 6 * s, ry + (rowH - chipH) / 2, chipW, chipH, "OWN",
        isOwned, PAL.green, PAL.steel) then
      Ops.dexOwned(S, id, not isOwned)
    end
  end

  S.dexOffset = Kit.pager(cx, pagerY, inner, S.dexOffset, #species, perPage)
end

return M
