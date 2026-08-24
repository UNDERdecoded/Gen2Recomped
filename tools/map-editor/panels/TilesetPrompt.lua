-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- "That block is from another tileset. Add it to this map?"
--
-- WHY THERE IS A QUESTION HERE AT ALL, when the editor could simply copy the
-- art and say nothing. Because it is not free and it is not local. Painting a
-- block from another tileset appends its sixteen tile graphics to THIS map's
-- tileset atlas and mints a block pointing at them -- and a Gen 2 tileset is
-- shared: thirty maps draw from `TilesetJohto`, so growing it for one of them
-- grows it for all thirty, and the growth is permanent in the sense that
-- nothing in the editor walks it back. A tileset also has a ceiling; block ids
-- are a byte, and there are only so many rows of atlas before a map stops
-- loading. None of that is a reason to refuse -- it is a reason to ASK ONCE.
--
-- ONCE IS THE WHOLE DESIGN. The first block from a new tileset is a decision.
-- The second is the middle of laying a floor, and a dialog there is an
-- obstacle, not a safeguard. So the answer is remembered against the MAP
-- (`MapEdits.addMapTileset`) and everything afterwards paints straight
-- through.
--
-- OVER THE WHOLE WINDOW, painted after the frame, for the reason AssetMenu is:
-- Kit has no z-order, so "on top" and "drawn last" are the same sentence, and
-- this has to be on top of the palette that raised it.

local MapEdits = require("tools.map-editor.MapEdits")

-- Only for `forgetModal` on close. The Kit every draw call uses is the one it
-- is HANDED -- the panels are driven with a stub in the tests -- so this is a
-- guarded second reference rather than a replacement for the parameter.
local okKit, KitModule = pcall(require, "Kit")
if not okKit then KitModule = nil end

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, caption = { 160, 175, 205 },
}

local TilesetPrompt = {}

local function store(S)
  if not S.mapEdits then S.mapEdits = (MapEdits.load()) end
  return S.mapEdits
end

local function game(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring(S.version or v or "unknown")
end

-- ---------------------------------------------------------------------------
-- raising it
-- ---------------------------------------------------------------------------

-- Ask about `tilesetId`, on behalf of a click on `blockId` (quadrant `q`).
--
-- RETURNS FALSE WHEN THERE IS NOTHING TO ASK -- the tileset is the map's own,
-- or it is already on the map's list -- so the caller can use the return value
-- as "did I need to stop", rather than testing the same two conditions itself
-- and drifting out of step with this file.
function TilesetPrompt.ask(S, tilesetId, blockId, q, ownId)
  if not (S and S.mapId and tilesetId) then return false end
  if ownId == nil then
    local def = S.data and S.data.maps and S.data.maps[S.mapId]
    ownId = def and def.tileset
  end
  if tilesetId == ownId then return false end
  if MapEdits.mapUsesTileset(store(S), game(S), S.mapId, tilesetId, ownId) then
    return false
  end
  S.tilesetAsk = { tileset = tilesetId, own = ownId, mapId = S.mapId,
                   block = blockId, q = q }
  return true
end

function TilesetPrompt.close(S)
  if S then
    S.tilesetAsk = nil
    -- Say so, rather than letting the "was it drawn last frame" test infer it
    -- -- the next time this question goes up its first frame is then exact.
    if KitModule and KitModule.forgetModal then
      KitModule.forgetModal("tileset-ask")
    end
  end
end

-- ---------------------------------------------------------------------------
-- answering it
-- ---------------------------------------------------------------------------

-- Shared by the button and by anything that wants to answer without drawing
-- (the asset stamper does). `keep` false copies the one block and leaves the
-- tileset off the list.
function TilesetPrompt.accept(S, ask, keep)
  ask = ask or S.tilesetAsk
  if not ask then return false, "nothing was asked" end
  local st, g = store(S), game(S)
  if keep then
    local ok, why = MapEdits.addMapTileset(st, g, ask.mapId, ask.tileset,
                                           ask.own)
    -- "already on this map" is a success from where the caller stands: the
    -- state it wanted is the state that now holds.
    if not ok and not tostring(why or ""):find("already") then
      return false, why
    end
    S.mapEditsDirty = true
    S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  end
  -- and hand the click that raised this back to the painter, so answering the
  -- question also does the thing the question interrupted
  if ask.block ~= nil then
    local okT, Tiles = pcall(require, "tools.map-editor.panels.Tiles")
    if okT and type(Tiles) == "table" and Tiles.usePick then
      local live, why = Tiles.usePick(S, ask.tileset, ask.block, ask.q)
      if not live then return false, why end
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- drawing it
-- ---------------------------------------------------------------------------

function TilesetPrompt.draw(S, Kit)
  local ask = S and S.tilesetAsk
  if not ask then return false end
  -- The map moved out from under an open question -- answering it would add a
  -- tileset to a map nobody was looking at.
  if ask.mapId ~= S.mapId then
    TilesetPrompt.close(S)
    return false
  end

  local s = Kit.scale
  local winW, winH = love.graphics.getDimensions()
  local pad = 16 * s
  local btnH = 34 * s

  local pw = math.max(320 * s, math.min(440 * s, winW - 40 * s))
  local x = math.floor((winW - pw) / 2)
  local w = pw - 2 * pad

  -- MEASURED BEFORE IT IS DRAWN, so the card is the height of its own text
  -- rather than a number somebody guessed and then had to keep in step with
  -- every edit to the wording.
  local body = string.format(
    "Block %s belongs to %s. This map is drawn with %s.",
    tostring(ask.block), tostring(ask.tileset), tostring(ask.own or "?"))
  local how = "Adding it copies the art you paint into " ..
    tostring(ask.own or "this map's tileset") ..
    " as you use it, and stops this question coming back."
  local bodyLines = Kit.wrap("small", body, w)
  local howLines = Kit.wrap("small", how, w - 46 * s)
  local lineH = 15 * s
  local ph = pad + Kit.textHeight("caption") + 8 * s
            + #bodyLines * lineH + 10 * s
            + math.max(40 * s, #howLines * lineH) + 12 * s
            + btnH * 2 + 8 * s + 26 * s + pad
  local y = math.max(20 * s, math.floor((winH - ph) / 2))

  -- THE GUARD RUNS BEFORE ANY WIDGET OF THIS DIALOG IS DRAWN.
  --
  -- Order is the whole of it. `Kit.tapAway` swallows the click on the frame
  -- the dialog goes up, and it can only do that for widgets drawn AFTER it --
  -- so asking at the bottom, after the three buttons, left the buttons taking
  -- the very click that opened the dialog. The palette swatch that raised this
  -- is under the pointer, the dialog is centred, and whichever button landed
  -- there answered the question before the reader saw it.
  local tappedAway = Kit.tapAway("tileset-ask", x, y, pw, ph)

  love.graphics.setColor(0.03, 0.04, 0.11, 0.62)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", x, y, pw, ph, 10 * s, 10 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(x, y, pw, ph)

  local tx = x + pad
  local ty = y + pad
  Kit.caption(tx, ty, "ANOTHER TILESET")
  ty = ty + Kit.textHeight("caption") + 8 * s

  for _, line in ipairs(bodyLines) do
    Kit.text("small", line, tx, ty)
    ty = ty + lineH
  end
  ty = ty + 10 * s

  -- WHAT YOU CLICKED, drawn. A block id is a number and the palette it came
  -- out of is now behind a dim sheet, so without the swatch the question is
  -- about something the reader can no longer see.
  local sw = 40 * s
  do
    local okT, Tiles = pcall(require, "tools.map-editor.panels.Tiles")
    local sets = S.data and S.data.tilesets or {}
    local ts = sets[ask.tileset]
    local drew = false
    if okT and type(Tiles) == "table" and Tiles.drawBlock and Tiles.atlasFor
       and ts and ask.block then
      local image = Tiles.atlasFor(S, ts, ask.tileset)
      if image then
        love.graphics.setColor(1, 1, 1, 1)
        drew = Tiles.drawBlock(ts, image, ask.block, tx, ty, sw / 32)
      end
    end
    if not drew then
      love.graphics.setColor(1, 1, 1, 0.08)
      love.graphics.rectangle("fill", tx, ty, sw, sw)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  local hy = ty
  for _, line in ipairs(howLines) do
    Kit.text("small", line, tx + 46 * s, hy, PAL.muted)
    hy = hy + lineH
  end
  ty = math.max(ty + sw, hy) + 12 * s

  -- ---------------------------------------------------------------- answers
  local result = nil
  if Kit.button(tx, ty, w, btnH,
                "ADD " .. tostring(ask.tileset) .. " TO THIS MAP",
                { font = "small", kind = "accent" }) then
    result = "add"
  end
  ty = ty + btnH + 8 * s

  -- THE MIDDLE ANSWER, and the reason this is not a yes/no. Wanting one
  -- drawing out of a tileset is the commonest case by a distance -- one sign,
  -- one bit of roof -- and forcing that through "add the whole tileset" makes
  -- the list meaningless within an afternoon.
  local halfW = (w - 8 * s) / 2
  if Kit.button(tx, ty, halfW, btnH, "JUST THIS BLOCK",
                { font = "small" }) then
    result = "once"
  end
  if Kit.button(tx + halfW + 8 * s, ty, halfW, btnH, "CANCEL",
                { font = "small" }) then
    result = "cancel"
  end
  ty = ty + btnH + 6 * s

  local n = #MapEdits.mapTilesets(store(S), game(S), S.mapId)
  Kit.text("small", n == 0
    and "this map paints from its own tileset only"
    or string.format("this map already paints from %d other tileset%s",
                     n, n == 1 and "" or "s"),
    tx, ty, PAL.muted)

  -- ESCAPE AND A TAP OUTSIDE BOTH MEAN CANCEL, which is the safe answer: it is
  -- the only one of the three that changes nothing.
  -- A tap outside is a cancel, decided at the top of this function and applied
  -- here so a button press this frame outranks it.
  if not result and tappedAway then result = "cancel" end

  if result == "cancel" then
    TilesetPrompt.close(S)
  elseif result then
    local ok, why = TilesetPrompt.accept(S, ask, result == "add")
    S.tileNotice = ok
      and (result == "add"
           and (tostring(ask.tileset) .. " added - paint from it freely")
           or "copied one block - it is now the painting block")
      or tostring(why)
    TilesetPrompt.close(S)
  end
  return true
end

function TilesetPrompt.keypressed(S, key)
  if not (S and S.tilesetAsk) then return false end
  if key == "escape" then
    TilesetPrompt.close(S)
    return true
  end
  -- Return is the accent button, the same as pressing it.
  if key == "return" or key == "kpenter" then
    local ask = S.tilesetAsk
    local ok, why = TilesetPrompt.accept(S, ask, true)
    S.tileNotice = ok and (tostring(ask.tileset) .. " added") or tostring(why)
    TilesetPrompt.close(S)
    return true
  end
  return true      -- a modal swallows the rest rather than letting it through
end

return TilesetPrompt
