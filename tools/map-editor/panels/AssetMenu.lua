-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- The asset library, as a popup over the whole window.
--
-- OVER THE WINDOW, NOT INSIDE A PANEL, because its button is in the title bar
-- and its contents belong to the PROJECT rather than to whichever map is open.
-- App paints it after the entire frame -- Kit has no z-order, so "on top" and
-- "drawn last" are the same statement -- and raises the click shield for the
-- rest of the frame while it is up.
--
-- WHAT IT IS FOR. Saving a building out of one map and stamping it into
-- another. The list is the choosing; placing happens on the map, because that
-- is where you can see whether it lands in the right place.

local MapAssets = require("tools.map-editor.MapAssets")

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, caption = { 160, 175, 205 },
}

local AssetMenu = {}

AssetMenu.ROWS = 8

local function store(S)
  if not S.mapEdits then
    S.mapEdits = (require("tools.map-editor.MapEdits").load())
  end
  return S.mapEdits
end

-- The cells the map has selected, which is what SAVE captures.
local function selection(S)
  local ok, Preview = pcall(require, "tools.map-editor.panels.Preview")
  if ok and type(Preview) == "table" and Preview.selection then
    local okS, list = pcall(Preview.selection, S)
    if okS and type(list) == "table" then return list end
  end
  return {}
end

function AssetMenu.draw(S, Kit)
  if not (S and S.assetMenuOpen) then return false end
  local s = Kit.scale
  local winW, winH = love.graphics.getDimensions()
  local pad = 14 * s
  local fieldH = 30 * s
  local rowH = 40 * s

  local st = store(S)
  local game = MapAssets.gameOf(S)
  local names = MapAssets.list(st, game)

  local pw = math.max(300 * s, math.min(460 * s, winW - 40 * s))
  local bodyRows = math.min(math.max(#names, 1), AssetMenu.ROWS)
  local ph = math.min(winH - 40 * s,
                      pad * 2 + 150 * s + bodyRows * rowH + fieldH)
  -- ANCHORED UNDER ITS BUTTON, which is at the right end of the title bar, so
  -- the list drops out of the thing that opened it rather than appearing in
  -- the middle of the screen with no connection to it.
  local px0 = math.max(8 * s, winW - pw - 22 * s)
  local py0 = math.min(74 * s, winH - ph - 8 * s)

  -- THE CLICK THAT OPENED IT IS STILL THIS FRAME'S CLICK, and the button that
  -- opened it is outside this rectangle -- so without a guard the test below
  -- reads it as a tap outside and shuts the list in the frame it went up.
  -- This carried its own flag until four other modals turned out to have no
  -- guard at all; the question has one answer now, in Kit.
  if Kit.tapAway("asset-menu", px0, py0, pw, ph) then
    S.assetMenuOpen = false
    return true
  end

  love.graphics.setColor(0.03, 0.04, 0.11, 0.45)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", px0, py0, pw, ph, 10 * s, 10 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(px0, py0, pw, ph)

  local x = px0 + pad
  local w = pw - 2 * pad
  local y = py0 + pad
  Kit.caption(x, y, "ASSETS")
  local closeW = 28 * s
  if Kit.button(px0 + pw - pad - closeW, y - 4 * s, closeW, 24 * s, "x",
                { font = "small", radius = 6 * s }) then
    S.assetMenuOpen = false
    return true
  end
  y = y + Kit.textHeight("caption") + 6 * s
  Kit.text("small", "a saved piece of map - blocks, heights, NPCs and doors",
           x, y, PAL.muted)
  y = y + 18 * s

  -- ----------------------------------------------------------- saving one
  local sel = selection(S)
  S.assetName = S.assetName or ""
  S.assetName = Kit.textfield("asset-name", x, y, w - 90 * s, fieldH,
                              S.assetName, "name this one...")
  local canSave = #sel > 0 and S.mapId ~= nil
  if Kit.button(x + w - 86 * s, y, 86 * s, fieldH,
                canSave and ("SAVE " .. #sel) or "SAVE",
                { font = "small", kind = canSave and "accent" or "disabled",
                  enabled = canSave }) and canSave then
    local name, why = MapAssets.capture(S, sel, S.assetName)
    if name then
      S.assetName = ""
      S.assetNotice = string.format("saved \"%s\" - %d cells", name, #sel)
    else
      S.assetNotice = tostring(why)
    end
  end
  y = y + fieldH + 4 * s
  Kit.text("small", #sel > 0
    and string.format("%d cell%s selected on %s", #sel,
          #sel == 1 and "" or "s", tostring(S.mapId))
    or "select cells on the map to save a new asset",
    x, y, #sel > 0 and PAL.yellow or PAL.muted)
  y = y + 20 * s

  -- ------------------------------------------------------------- the list
  local maxScroll = math.max(0, #names - AssetMenu.ROWS)
  S.assetScroll = math.max(0, math.min(S.assetScroll or 0, maxScroll))
  local bodyH = (py0 + ph - pad - 22 * s) - y

  if #names == 0 then
    Kit.text("small", "nothing saved yet.", x, y, PAL.muted)
    y = y + 16 * s
    Kit.text("small", "select a building on the map and press SAVE.",
             x, y, PAL.muted)
  else
    Kit.pushClip(x, y, w, bodyH)
    local ry = y
    for i = S.assetScroll + 1,
            math.min(#names, S.assetScroll + AssetMenu.ROWS) do
      local name = names[i]
      local asset = MapAssets.get(st, game, name) or {}
      local armed = S.assetPlacing == name
      local delW = 28 * s
      if Kit.press(x, ry, w - delW - 4 * s, rowH - 4 * s) then
        -- PICK, THEN CLICK. Arming closes the library, because the next thing
        -- to do is look at the map and there is no point in a list covering it.
        if MapAssets.arm(S, name) then S.assetMenuOpen = false end
      end
      Kit.row(x, ry, w - delW - 4 * s, rowH - 4 * s, armed)
      Kit.text("body", Kit.ellipsize("body", name, w - delW - 90 * s),
               x + 8 * s, ry + 4 * s)
      -- WHAT IS IN IT, on the row: an asset's name is whatever somebody typed,
      -- and "house" tells you nothing about whether it carries its doors.
      local bits = {}
      bits[#bits + 1] = string.format("%dx%d", asset.w or 0, asset.h or 0)
      local nv = 0
      for _ in pairs(asset.voxels or {}) do nv = nv + 1 end
      for _ in pairs(asset.tiles or {}) do nv = nv + 1 end
      if nv > 0 then bits[#bits + 1] = nv .. " shaped" end
      if #(asset.objects or {}) > 0 then
        bits[#bits + 1] = #asset.objects .. " npc"
      end
      if #(asset.warps or {}) > 0 then
        bits[#bits + 1] = #asset.warps .. " door"
      end
      bits[#bits + 1] = tostring(asset.tileset or "?")
      Kit.text("small", Kit.ellipsize("small", table.concat(bits, "  -  "),
                                      w - delW - 16 * s),
               x + 8 * s, ry + 21 * s, PAL.muted)
      if Kit.button(x + w - delW, ry, delW, rowH - 4 * s, "x",
                    { font = "small", radius = 6 * s }) then
        MapAssets.delete(st, game, name)
        if S.assetPlacing == name then MapAssets.disarm(S) end
        S.mapEditsDirty = true
        S.assetNotice = name .. " deleted"
      end
      ry = ry + rowH
    end
    Kit.popClip()
  end

  if maxScroll > 0 then
    Kit.text("small", string.format("%d more - scroll", maxScroll),
             x, py0 + ph - pad - 16 * s, PAL.muted)
  elseif S.assetNotice then
    Kit.text("small", Kit.ellipsize("small", S.assetNotice, w),
             x, py0 + ph - pad - 16 * s, PAL.yellow)
  end
  return true
end

function AssetMenu.wheelmoved(S, dy)
  if not (S and S.assetMenuOpen) then return false end
  S.assetScroll = math.max(0, (S.assetScroll or 0) - (dy or 0))
  return true
end

function AssetMenu.keypressed(S, key)
  if not S then return false end
  if key == "escape" then
    if S.assetMenuOpen then
      S.assetMenuOpen = false
      return true
    end
    if S.assetPlacing then
      MapAssets.disarm(S)
      return true
    end
  end
  return false
end

return AssetMenu
