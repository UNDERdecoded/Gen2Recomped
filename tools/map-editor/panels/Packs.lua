-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- The map packs installed, what each claims, and who wins where they overlap.
--
-- A MODAL RAISED BY IMPORT, not a tool on the drawer rail. Adding a pack and
-- living with the ones already there are the same job -- you press IMPORT to
-- find out what is installed as often as to install something -- and splitting
-- them across a button and a tool meant the list nobody could find was the one
-- that answered "why does this map look wrong".
--
-- WHY ANY OF THIS IS NEEDED. A pack is an ordinary mod and two of them may
-- patch the same map. The registry folds both claims and the last one loaded
-- wins -- a defined answer, but not one anybody chose, and invisible: the only
-- way to discover it was to open the map and not recognise it. Everything
-- shown here is a reading of provenance the registry already kept (see
-- MapPacks); this adds no format and no second source of truth.
--
-- REMOVING A PACK is how the cartridge's own maps come back: with nothing
-- patching a map, the fold is the base value, and the base value is the ROM's.

local MapPacks = require("tools.map-editor.MapPacks")

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, green = { 120, 210, 140 },
  text = { 226, 232, 245 },
}
local okKit, KitModule = pcall(require, "Kit")
if not okKit then KitModule = nil end

local Packs = {}

function Packs.raise(S)
  if not S then return false end
  S.packsOpen = true
  S.packsCache, S.packsConflicts = nil, nil
  S.packsRemoveArm = nil
  return true
end

function Packs.close(S)
  if not S then return end
  S.packsOpen = nil
  S.packsRemoveArm = nil
  if KitModule and KitModule.forgetModal then
    KitModule.forgetModal("map-packs")
  end
end

-- Rebuilt when raised and after anything changes, not per frame: `list` walks
-- every claimed id in the registry, and this dialog is open while somebody
-- reads it rather than while the world runs.
local function packs(S)
  if not S.packsCache then S.packsCache = MapPacks.list(S) end
  return S.packsCache
end

local function conflicts(S)
  if not S.packsConflicts then S.packsConflicts = MapPacks.conflicts(S) end
  return S.packsConflicts
end

local function invalidate(S)
  S.packsCache, S.packsConflicts = nil, nil
end

function Packs.draw(S, Kit)
  if not (S and S.packsOpen) then return false end
  local s = Kit.scale
  local winW, winH = love.graphics.getDimensions()
  local pad = 16 * s
  local btnH = 34 * s
  local rowH = 26 * s
  local lineH = 15 * s

  local haveRegistry = MapPacks.registry(S) ~= nil
  local list = haveRegistry and packs(S) or {}
  local clashes = haveRegistry and conflicts(S) or {}

  local pw = math.max(380 * s, math.min(560 * s, winW - 40 * s))
  local x = math.floor((winW - pw) / 2)
  local w = pw - 2 * pad

  -- MEASURED BEFORE IT IS DRAWN, so the card is the height of its own content
  -- rather than a constant somebody has to keep in step with every edit. The
  -- same arithmetic runs again below to place things; keeping the two in one
  -- function would mean drawing before the height is known.
  local ph = pad + Kit.textHeight("caption") + 8 * s
  if not haveRegistry then
    ph = ph + 2 * lineH + 10 * s
  else
    if #clashes > 0 then
      ph = ph + lineH + 6 * s
      for _, row in ipairs(clashes) do
        ph = ph + 18 * s + rowH + 8 * s
      end
      ph = ph + 8 * s
    end
    ph = ph + Kit.textHeight("caption") + 6 * s
    if #list == 0 then
      ph = ph + 2 * lineH
    else
      for _, pack in ipairs(list) do
        ph = ph + 18 * s + 16 * s + 18 * s + btnH + 14 * s
        if S.packsRemoveArm == pack.id then ph = ph + 16 * s end
      end
    end
  end
  if S.packsNotice then ph = ph + 18 * s end
  ph = ph + btnH + pad
  ph = math.min(ph, winH - 24 * s)
  local y = math.max(12 * s, math.floor((winH - ph) / 2))

  -- The guard runs BEFORE any widget of this dialog: `Kit.tapAway` swallows
  -- the click on the frame it goes up, and it can only do that for widgets
  -- drawn after it. Asking at the bottom would let ADD take the very click
  -- that opened the dialog.
  local tappedAway = Kit.tapAway("map-packs", x, y, pw, ph)

  love.graphics.setColor(0.03, 0.04, 0.11, 0.62)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", x, y, pw, ph, 10 * s, 10 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(x, y, pw, ph)

  local tx, ty = x + pad, y + pad
  Kit.caption(tx, ty, "MAP PACKS")
  ty = ty + Kit.textHeight("caption") + 8 * s

  if not haveRegistry then
    Kit.text("small", "This session has no mod loader, so no packs", tx, ty,
             PAL.muted)
    ty = ty + lineH
    Kit.text("small", "can be listed.", tx, ty, PAL.muted)
    ty = ty + lineH + 10 * s
  else
    -- --------------------------------------------------------- conflicts
    --
    -- FIRST, because it is the only part that is a question. The list below is
    -- reference; this is the thing waiting on an answer, and putting it under
    -- a scroll is how it stays unanswered.
    if #clashes > 0 then
      Kit.text("small", "two packs edit these -- pick the one to keep",
               tx, ty, PAL.yellow)
      ty = ty + lineH + 6 * s
      for _, row in ipairs(clashes) do
        Kit.text("small", row.map, tx, ty + 3 * s, PAL.text)
        ty = ty + 18 * s
        local n = #row.owners
        local bw = (w - (n - 1) * 6 * s - 90 * s) / math.max(1, n)
        for i, owner in ipairs(row.owners) do
          local bx = tx + (i - 1) * (bw + 6 * s)
          if Kit.chip(bx, ty, bw, rowH, Kit.ellipsize("small", owner, bw - 10 * s),
                      row.winner == owner) then
            -- Pressing the winner again CLEARS the choice rather than doing
            -- nothing: "I do not want to decide this" has to be reachable, and
            -- load order is what no-decision means.
            MapPacks.prefer(S, row.map, row.winner == owner and nil or owner)
            invalidate(S)
          end
        end
        Kit.text("small", row.winner and "kept" or "load order",
                 tx + w - 84 * s, ty + 6 * s,
                 row.winner and PAL.green or PAL.muted)
        ty = ty + rowH + 8 * s
      end
      ty = ty + 8 * s
    end

    -- -------------------------------------------------------- the pack list
    Kit.caption(tx, ty, "INSTALLED")
    ty = ty + Kit.textHeight("caption") + 6 * s

    if #list == 0 then
      Kit.text("small", "No map pack is installed.", tx, ty, PAL.muted)
      ty = ty + lineH
      Kit.text("small", "ADD A PACK below installs one.", tx, ty, PAL.muted)
      ty = ty + lineH
    else
      for _, pack in ipairs(list) do
        Kit.text("body", Kit.ellipsize("body", pack.name, w), tx, ty)
        ty = ty + 18 * s
        -- THREE STATES, NOT TWO, and they want different words.
        --
        -- A pack that is patching maps can say how many. One installed a
        -- moment ago has not loaded -- the mod set is built once a boot -- and
        -- one that is switched off never will. Collapsing those into "0 maps"
        -- is what made an install read as a failure.
        local count = #pack.maps
        local plural = count == 1 and "" or "s"
        local state, col
        if pack.active then
          state = string.format("%d map%s", count, plural)
          col = PAL.muted
        elseif not pack.enabled then
          state = "switched off in the launcher"
          col = PAL.red
        elseif count > 0 then
          -- The count comes from the manifest here, not from claims: the pack
          -- is on disk and has not loaded, so this is what it SAYS it has.
          state = string.format("%d map%s - restart the game to load", count,
                                plural)
          col = PAL.yellow
        else
          state = "restart the game to load it"
          col = PAL.yellow
        end
        Kit.text("small", string.format("%s%s  -  %s", pack.id,
                 pack.version and (" " .. pack.version) or "", state),
                 tx, ty, col)
        ty = ty + 16 * s

        -- The first few map ids, because "12 maps" does not tell you whether
        -- this is the pack you meant to remove and the ids do.
        if #pack.maps > 0 then
          local shown = {}
          for i = 1, math.min(4, #pack.maps) do shown[#shown + 1] = pack.maps[i] end
          if #pack.maps > #shown then
            shown[#shown + 1] = "+" .. (#pack.maps - #shown) .. " more"
          end
          Kit.text("small", Kit.ellipsize("small", table.concat(shown, ", "), w),
                   tx, ty, PAL.muted)
        end
        ty = ty + 18 * s

        -- ARMED, THEN CONFIRMED. Removing a pack throws away every map in it
        -- and there is no undo short of the original .zip.
        local armed = (S.packsRemoveArm == pack.id)
        if armed then
          Kit.text("small", "its maps go back to the cartridge's", tx, ty,
                   PAL.yellow)
          ty = ty + 16 * s
        end
        local half = (w - 8 * s) / 2
        if Kit.button(tx, ty, armed and half or w, btnH,
                      armed and "CONFIRM - REMOVE" or "REMOVE PACK",
                      { font = "small" }) then
          if armed then
            local ok, why = MapPacks.remove(S, pack.id)
            S.packsNotice = ok
              and (pack.id .. " removed - restart to load without it")
              or ("could not remove: " .. tostring(why))
            S.packsRemoveArm = nil
            invalidate(S)
          else
            S.packsRemoveArm = pack.id
          end
        end
        if armed and Kit.button(tx + half + 8 * s, ty, half, btnH, "KEEP IT",
                                { font = "small" }) then
          S.packsRemoveArm = nil
        end
        ty = ty + btnH + 14 * s
      end
    end
  end

  if S.packsNotice then
    Kit.text("small", Kit.ellipsize("small", S.packsNotice, w), tx, ty,
             PAL.yellow)
    ty = ty + 18 * s
  end

  -- ------------------------------------------------------------- the answers
  local half = (w - 8 * s) / 2
  local closed = false
  if Kit.button(tx, ty, half, btnH, "ADD A PACK...",
                { font = "small", kind = "accent" }) then
    -- The picker is the platform's own, and on a phone it answers later --
    -- MapPacks owns both shapes so this button does not have to know which.
    if MapPacks.beginAdd(S) then invalidate(S) end
  end
  if Kit.button(tx + half + 8 * s, ty, half, btnH, "DONE",
                { font = "small" }) then
    closed = true
  end
  if tappedAway then closed = true end
  if closed then Packs.close(S) end
  return true
end

function Packs.keypressed(S, key)
  if not (S and S.packsOpen) then return false end
  if key == "escape" or key == "return" or key == "kpenter" then
    Packs.close(S)
    return true
  end
  return true
end

return Packs
