-- The panels.
--
-- Kept in one file because they share one selection and one document, and a
-- selection that lives in three files is a selection that goes out of sync
-- in two of them.

local Theme = require("ui.Theme")
local W = require("ui.Widgets")
local Cache = require("core.Cache")
local StructBridge = require("core.StructBridge")
local Classes = require("core.Classes")
local Doc = require("core.Doc")

local P = {}

-- ------------------------------------------------------------- the sheet

-- The whole atlas, with every tile's resolved class shown as a tint.  The
-- tint is the point: it is how you see at a glance that the counter tiles and
-- the wall tiles are being answered differently, which is the question this
-- editor exists to ask.
--
-- IT SCROLLS, AND IT HAS TO.  A Gen 1 sheet is 128x48 and fits anywhere; a
-- Gen 3 pair composites to 128x2336, which is 292 rows of tiles.  A panel
-- that scaled that to fit would show each tile a third of a pixel high.  So:
-- fit the WIDTH, scroll the height, and clip.
function P.sheet(app, x, y, w, h)
  W.panel(x, y, w, h, "sheet")
  local ts, geom = app.ts, app.geom
  if not (ts and geom) then
    W.text("no tileset loaded", x + 10, y + 26, Theme.faint)
    return
  end
  local ix, iy = x + 6, y + 22
  local iw, ih = w - 12, h - 28
  local zoom = math.max(1, math.floor(iw / geom.atlasW))
  app.sheetZoom = zoom
  local dw, dh = geom.atlasW * zoom, geom.atlasH * zoom
  local ox = ix + math.floor((iw - dw) / 2)

  local scrollId = "sheetscroll"
  local st = W.state.scroll[scrollId] or 0
  local maxScroll = math.max(0, dh - ih)
  if W.hit(ix, iy, iw, ih) and maxScroll > 0 then
    W.claimWheel(ix, iy, iw, ih)
    if W.state.wheel ~= 0 then st = st - W.state.wheel * 8 * zoom end
  end
  st = math.max(0, math.min(maxScroll, st))
  W.state.scroll[scrollId] = st
  local oy = iy - st
  app.sheetRect = { ox, oy, dw, dh, zoom }

  W.scissorIn(ix, iy, iw, ih)
  love.graphics.setColor(0, 0, 0, 0.4)
  love.graphics.rectangle("fill", ox - 2, oy - 2, dw + 4, dh + 4)
  if app.atlasImage then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(app.atlasImage, ox, oy, 0, zoom, zoom)
  else
    W.text("no atlas art for this tileset", ix + 6, iy + 6, Theme.warn,
           Theme.fonts.small)
  end

  -- Only the rows on screen are tinted and gridded.  On a 3,500-tile Gen 3
  -- sheet, doing all of them is a shape lookup per tile per frame.
  local firstRow = math.max(0, math.floor(st / (8 * zoom)))
  local lastRow = math.min(geom.rows - 1,
                           math.floor((st + ih) / (8 * zoom)))

  if app.showClassTint then
    for row = firstRow, lastRow do
      for col = 0, geom.perRow - 1 do
        local tile = row * geom.perRow + col
        if tile < geom.count then
          local sp = app.shapeOf(tile)
          if sp then
            local r, g, b = Theme.heightColor(sp.h or 0, 32)
            love.graphics.setColor(r, g, b, sp.authored and 0.42 or 0.16)
            love.graphics.rectangle("fill", ox + col * 8 * zoom,
                                    oy + row * 8 * zoom, 8 * zoom, 8 * zoom)
          end
        end
      end
    end
  end

  love.graphics.setLineWidth(1)
  for i = 0, geom.perRow do
    love.graphics.setColor(i % 2 == 0 and Theme.gridCell or Theme.grid)
    love.graphics.line(ox + i * 8 * zoom, oy + firstRow * 8 * zoom,
                       ox + i * 8 * zoom, oy + (lastRow + 1) * 8 * zoom)
  end
  for j = firstRow, lastRow + 1 do
    love.graphics.setColor(j % 2 == 0 and Theme.gridCell or Theme.grid)
    love.graphics.line(ox, oy + j * 8 * zoom, ox + dw, oy + j * 8 * zoom)
  end

  local function box(tile, col, lw)
    local tx = (tile % geom.perRow) * 8 * zoom
    local ty = math.floor(tile / geom.perRow) * 8 * zoom
    love.graphics.setLineWidth(lw or 2)
    love.graphics.setColor(col)
    love.graphics.rectangle("line", ox + tx - 1, oy + ty - 1,
                            8 * zoom + 2, 8 * zoom + 2)
  end
  for tile in pairs(app.tileSel or {}) do box(tile, { 0.4, 0.8, 1, 0.7 }, 2) end
  if app.tile then box(app.tile, Theme.accent, 2) end

  if W.hit(ix, iy, iw, ih) and W.hit(ox, oy, dw, dh) then
    local tx = math.floor((W.state.mx - ox) / (8 * zoom))
    local ty = math.floor((W.state.my - oy) / (8 * zoom))
    local tile = ty * geom.perRow + tx
    if tile >= 0 and tile < geom.count then
      box(tile, { 1, 1, 1, 0.4 }, 1)
      app.hoverTile = tile
      if W.state.clicked then
        if love.keyboard.isDown("lshift", "rshift") then
          app.tileSel = app.tileSel or {}
          app.tileSel[tile] = not app.tileSel[tile] or nil
        else
          app.tileSel = {}
        end
        app:selectTile(tile)
      end
    end
  end
  W.scissorOut()

  if maxScroll > 0 then
    local bh = math.max(20, ih * (ih / dh))
    local by = iy + (st / maxScroll) * (ih - bh)
    love.graphics.setColor(Theme.line)
    love.graphics.rectangle("fill", x + w - 8, by, 4, bh, 2, 2)
  end

  -- JUMP TO A TILE ID.  On a 3,500-tile sheet, scrolling to $0AF4 is not a
  -- gesture anyone should have to make.
  W.textRight(("%d tiles"):format(geom.count), x + w - 14, y + 6, Theme.faint,
              Theme.fonts.small)
end

-- --------------------------------------------------------- the tile canvas

-- One tile at 1:1 and one blown up big enough to hit a texel with a mouse.
-- Painting happens here and nowhere else.
function P.tileCanvas(app, x, y, w, h)
  W.panel(x, y, w, h, "tile " .. tostring(app.tile)
      .. (app.tile and ("  ($" .. string.format("%02X", app.tile) .. ")") or ""))
  if not (app.tile and app.atlasImage) then
    W.text("pick a tile", x + 10, y + 26, Theme.faint)
    return
  end
  local geom = app.geom
  local ax = (app.tile % geom.perRow) * 8
  local ay = math.floor(app.tile / geom.perRow) * 8

  -- 1:1, for the pixels themselves
  local q = love.graphics.newQuad(ax, ay, 8, 8, geom.atlasW, geom.atlasH)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(app.atlasImage, q, x + w - 40, y + 6, 0, 4, 4)

  local pad = 12
  local top = y + 44
  local size = math.min(w - pad * 2, h - (top - y) - pad)
  local zoom = math.max(1, math.floor(size / 8))
  local dw = 8 * zoom
  local ox = x + math.floor((w - dw) / 2)
  local oy = top
  app.canvasRect = { ox, oy, dw, dw, zoom }

  love.graphics.setColor(0.06, 0.07, 0.08)
  love.graphics.rectangle("fill", ox - 3, oy - 3, dw + 6, dw + 6, 3, 3)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(app.atlasImage, q, ox, oy, 0, zoom, zoom)

  local sculpt = Doc.hasSculpt(app.doc, app.tsId, app.tile)
  local shape = app.shapeOf(app.tile)

  -- the height overlay: what the reader has sculpted, over the art
  if sculpt and app.showHeights then
    local res = sculpt.res
    local step = dw / res
    for j = 0, res - 1 do
      for i = 0, res - 1 do
        local hv = sculpt.h[j * res + i + 1] or 0
        if hv ~= 0 then
          local r, g, b = Theme.heightColor(hv, 32)
          love.graphics.setColor(r, g, b, 0.45)
          love.graphics.rectangle("fill", ox + i * step, oy + j * step, step, step)
        end
      end
    end
  end

  -- selection
  if app.sel and next(app.sel) then
    love.graphics.setColor(Theme.sel)
    for k in pairs(app.sel) do
      local i, j = k % 8, math.floor(k / 8)
      love.graphics.rectangle("fill", ox + i * zoom, oy + j * zoom, zoom, zoom)
    end
    love.graphics.setColor(1, 1, 1, 0.65)
    love.graphics.setLineWidth(1)
    for k in pairs(app.sel) do
      local i, j = k % 8, math.floor(k / 8)
      if not app.sel[k - 1] or i == 0 then
        love.graphics.line(ox + i * zoom, oy + j * zoom, ox + i * zoom, oy + (j + 1) * zoom)
      end
      if not app.sel[k + 1] or i == 7 then
        love.graphics.line(ox + (i + 1) * zoom, oy + j * zoom, ox + (i + 1) * zoom, oy + (j + 1) * zoom)
      end
      if not app.sel[k - 8] then
        love.graphics.line(ox + i * zoom, oy + j * zoom, ox + (i + 1) * zoom, oy + j * zoom)
      end
      if not app.sel[k + 8] then
        love.graphics.line(ox + i * zoom, oy + (j + 1) * zoom, ox + (i + 1) * zoom, oy + (j + 1) * zoom)
      end
    end
  end

  -- texel grid
  love.graphics.setLineWidth(1)
  for i = 0, 8 do
    love.graphics.setColor(i % 4 == 0 and Theme.gridCell or Theme.grid)
    love.graphics.line(ox + i * zoom, oy, ox + i * zoom, oy + dw)
    love.graphics.line(ox, oy + i * zoom, ox + dw, oy + i * zoom)
  end

  -- hover readout + painting
  if W.hit(ox, oy, dw, dw) then
    local i = math.floor((W.state.mx - ox) / zoom)
    local j = math.floor((W.state.my - oy) / zoom)
    if i >= 0 and j >= 0 and i < 8 and j < 8 then
      app.hoverTexel = { i, j }
      love.graphics.setColor(1, 1, 1, 0.8)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", ox + i * zoom, oy + j * zoom, zoom, zoom)
      if love.mouse.isDown(1) then app:paintTexel(i, j) end
      if W.state.clicked and app.tool == "wand" then app:wand(i, j) end
    end
  end

  -- the readout under the canvas
  local ry = oy + dw + 8
  if app.hoverTexel then
    local i, j = app.hoverTexel[1], app.hoverTexel[2]
    local r, g, b, a = app.pixel(app.tile, i, j)
    local shadeName = r and Classes.shadeClass(math.min(r, g, b)) or "?"
    local hv = sculpt and sculpt.h[j * (sculpt.res or 8) + i + 1]
    W.text(("texel %d,%d   %s%s"):format(i, j, shadeName,
           hv and ("   h=" .. hv) or ""), ox, ry, Theme.dim, Theme.fonts.small)
  end
  if shape then
    W.text(("class %s   h=%s   fold %s"):format(tostring(shape.class),
           tostring(shape.h), tostring(shape.art)),
           ox, ry + 14, Theme.text, Theme.fonts.small)
    W.text("via " .. tostring(shape.source or "?"), ox, ry + 28,
           Theme.faint, Theme.fonts.small)
  end
end

-- --------------------------------------------------------------- the tools

-- The 2D brushes, for work that is easier done on a magnified tile than in
-- the world -- picking out a window pane, wanding a shade.  Everything here
-- writes the same height field the viewport's drag handles do.
function P.toolbar(app, x, y, w, h)
  local M = Theme.m
  W.panel(x, y, w, h, "2D brushes")
  local bx, by = x + 8, y + 24
  local cw = w - 16

  local tools = {
    { id = "pick",   label = "pick",   hint = "read a texel; click the sheet or the world to change tile" },
    { id = "height", label = "height", hint = "paint the brush height into this tile's height field" },
    { id = "lasso",  label = "lasso",  hint = "drag to add texels to the selection" },
    { id = "wand",   label = "wand",   hint = "select every texel of the clicked shade (shift: contiguous, ctrl: add)" },
    { id = "erase",  label = "erase",  hint = "put the selection back to the tile's own height" },
    { id = "pane",   label = "pane",   hint = "sink the selection one voxel: a window keeps a thin face instead of becoming a block" },
  }
  by = W.chips("tool", bx, by, cw, tools,
               function(t) return app.tool == t.id end,
               function(t) app.tool = t.id end)

  by = by + 4
  W.text("brush height", bx, by, Theme.dim, Theme.fonts.small)
  app.brushHeight = math.floor(W.slider("brush", bx + 82, by - 2, cw - 130, 16,
      app.brushHeight, -8, 48, { step = 1 }) + 0.5)
  W.textRight(tostring(app.brushHeight) .. "px", x + w - 8, by, Theme.text,
              Theme.fonts.small)
  by = by + 22

  by = W.chips("hp", bx, by, cw, Classes.HEIGHT_PRESETS,
               function(p) return app.brushHeight == p.h end,
               function(p) app.brushHeight = p.h end)

  by = by + M(4)
  local nsel = #app:selectedTileIds()
  if W.button("applyh", bx, by, cw, Theme.btnH,
              ("set %d selected to %dpx"):format(nsel, app.brushHeight),
              { font = Theme.fonts.small, disabled = nsel == 0 }) then
    app:heightSelection(app.brushHeight)
  end
  if W.state.hot == "applyh" then
    W.state.tip = "sets the height of the selected DRAWINGS, everywhere they"
        .. " appear -- or, with the world scope on THIS SQUARE, of the"
        .. " selected squares only.  The shape panel's height field can also"
        .. " reach the whole class."
  end
  by = by + Theme.btnH + M(6)

  by = by + 4
  local half = (cw - 6) / 2
  if W.button("selall", bx, by, half, 20, "select all",
              { font = Theme.fonts.small }) then
    app.sel = {}
    for k = 0, 63 do app.sel[k] = true end
  end
  if W.button("selnone", bx + half + 6, by, half, 20, "clear selection",
              { font = Theme.fonts.small }) then
    app.sel = {}
  end
  by = by + 26

  W.text("the world view has its own handles: face, edge and vertex drags on"
      .. " the same height field. Q W E R T switch between them.",
      bx, by, Theme.faint, Theme.fonts.small)
end

-- --------------------------------------------------- the conditional editor

function P.conditional(app, x, y, w, h)
  W.panel(x, y, w, h, "conditional pins on tile " .. tostring(app.tile))
  local bx, ry = x + 8, y + 26
  if not (app.tsId and app.tile) then
    W.text("pick a tileset and a tile first", bx, ry, Theme.faint)
    return
  end
  local e = Doc.entry(app.doc, app.tsId)
  local list = e.cond[app.tile] or {}

  W.text("a rule fires when the named tiles are drawn on the side it names;"
      .. " the first that matches wins, and none matching falls through to"
      .. " the tile's own pin.", bx, ry, Theme.faint, Theme.fonts.small)
  ry = ry + 30

  for i, rule in ipairs(list) do
    local desc
    if rule.side == "cell" then
      desc = ("cell is %swalkable -> %s"):format(rule.walkable and "" or "not ",
                                                 rule.class)
    else
      local ids = {}
      for _, t in ipairs(rule.ids or {}) do ids[#ids + 1] = string.format("$%02X", t) end
      desc = ("%s %s rows: %s -> %s"):format(rule.side, tostring(rule.rows or 1),
                                             table.concat(ids, " "), rule.class)
    end
    W.text(desc, bx, ry, Theme.text, Theme.fonts.small)
    if W.button("delcond" .. i, x + w - 30, ry - 2, 22, 18, "x",
                { font = Theme.fonts.small }) then
      Doc.removeCondition(app.doc, app.tsId, app.tile, i)
      app:invalidate({ tiles = { app.tile } })
    end
    ry = ry + 20
  end

  ry = ry + 6
  W.text("new rule: neighbours are the tiles currently shift-selected on the"
      .. " sheet (" .. tostring(app.tileSelCount or 0) .. " picked)",
      bx, ry, Theme.dim, Theme.fonts.small)
  ry = ry + 20

  local M = Theme.m
  local cw = w - M(16)
  ry = W.chips("cond", bx, ry, cw,
    { { label = "above" }, { label = "below" },
      { label = "cell-walk" }, { label = "cell-block" } },
    function() return false end,
    function(item)
      local side = item.label
      app:record("tileset", app.tsId, "add condition")
      local class = app.brushClass or "wall"
      if side == "above" or side == "below" then
        local ids = {}
        for t in pairs(app.tileSel or {}) do ids[#ids + 1] = t end
        table.sort(ids)
        if #ids > 0 then
          Doc.addCondition(app.doc, app.tsId, app.tile,
            { side = side, ids = ids, rows = app.condRows or 1, class = class })
        else
          app:say("shift-click the neighbour tiles on the sheet first")
        end
      else
        Doc.addCondition(app.doc, app.tsId, app.tile,
          { side = "cell", walkable = side == "cell-walk", class = class })
      end
      app:commitEdit()
      app:invalidate({ tiles = { app.tile } })
    end)

  ry = ry + M(4)
  W.text("rows", bx, ry, Theme.dim, Theme.fonts.small)
  app.condRows = math.floor(W.slider("condrows", bx + M(38), ry - M(2),
      cw - M(90), M(15), app.condRows or 1, 1, 4, { step = 1 }) + 0.5)
  W.textRight(tostring(app.condRows) .. (app.condRows == 2 and " (a cell)" or ""),
              x + w - M(8), ry, Theme.text, Theme.fonts.small)
  ry = ry + M(20)
  W.text("class: " .. tostring(app.brushClass or "wall")
      .. " -- set it by clicking a class on the shape tab",
      bx, ry, Theme.faint, Theme.fonts.small)
end

-- ------------------------------------------------------------- the groups

-- A tree, a house front, a statue: several tiles that are ONE thing.
--
-- THE REPETITION CAP IS WHY THIS EXISTS.  Pinned tile by tile, a 2x2 tree
-- is four boxes; folded as one volume with no cap, a border forest forty
-- rows deep is one three-hundred-pixel monolith.  The cap says how many
-- times the group may repeat before the next copy starts its own object,
-- which is the difference between a stand of trees and a cliff made of
-- bark.
-- ------------------------------------------------------------ the faces

-- THE TEXTURE PAINTER, for the art on the sides of things.
--
-- Raising a tile makes real geometry with no art that belongs on it: with no
-- measured volume and no upright fold, every 8px band of the new wall wears
-- the tile's own drawing, so a patch of grass raised to 40px becomes five
-- bands of grass standing on end.  That is the void this fills.
--
-- One row per exposed band, each showing the drawing that band wears now and
-- where that came from.  `paint` takes the tile currently picked on the sheet
-- -- so the gesture is: click the wall drawing on the sheet, then click the
-- band it belongs on.
function P.faces(app, x, y, w, h)
  local M = Theme.m
  local small = Theme.fonts.small
  W.panel(x, y, w, h, "side faces")
  local bx = x + M(8)
  local ry = y + M(24)
  local cw = w - M(16)
  if not (app.tsId and app.tile and app.geom) then
    W.text("pick a tile", bx, ry, Theme.faint, small)
    return
  end

  local tile = app.tile
  local bands = Doc.bands(app.doc, app.tsId, tile)
  local n = app:bandCount(tile)
  local sp = app.shapeOf(tile)

  W.text(("tile $%02X stands %spx tall -- %d band%s of side face")
         :format(tile, tostring(sp and sp.h or 0), n, n == 1 and "" or "s"),
         bx, ry, Theme.text, small)
  ry = ry + M(15)
  if n == 0 then
    W.text("nothing is exposed at this height: raise it and the faces appear",
           bx, ry, Theme.faint, small)
    return
  end

  -- WHAT THE PAINT WILL BE.  The tile picked on the sheet, drawn at 1:1 so
  -- there is no doubt which drawing is about to go on a wall.
  W.text("paint with", bx, ry, Theme.dim, small)
  local swatchZ = M(4)
  local geom = app.geom
  local function swatch(t, sx, sy)
    if not (app.atlasImage and t) then return end
    local ax = (t % geom.perRow) * 8
    local ay = math.floor(t / geom.perRow) * 8
    local q = love.graphics.newQuad(ax, ay, 8, 8, geom.atlasW, geom.atlasH)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(app.atlasImage, q, sx, sy, 0, swatchZ, swatchZ)
    love.graphics.setColor(Theme.line)
    love.graphics.rectangle("line", sx - 0.5, sy - 0.5,
                            8 * swatchZ + 1, 8 * swatchZ + 1)
  end
  local brush = app.faceBrush
  if brush == nil then brush = tile end
  swatch(brush, bx, ry + M(12))
  W.text(("$%02X"):format(brush), bx + 8 * swatchZ + M(6), ry + M(12),
         Theme.text, small)
  if W.button("facegrab", bx + 8 * swatchZ + M(40), ry + M(11),
              M(96), Theme.btnH, "use sheet tile", { font = small }) then
    app.faceBrush = app.tile
  end
  if W.state.hot == "facegrab" then
    W.state.tip = "takes whatever is picked on the sheet as the paint --"
        .. " click a wall drawing there, then come back and click a band"
  end
  ry = ry + M(12) + 8 * swatchZ + M(8)

  -- AUTO, which is a GUESS and says so.
  if W.button("faceauto", bx, ry, cw, Theme.btnH,
              "auto-fill the exposed faces", { font = small }) then
    app:autoFillBands()
  end
  if W.state.hot == "faceauto" then
    W.state.tip = "a guess, in three rules: the tile below this one inside its"
        .. " own 16x16 cell, then whatever the map draws south of the selected"
        .. " square if that resolves wall-like, then the tileset's commonest"
        .. " wall drawing.  Everything it fills stays editable."
  end
  ry = ry + Theme.btnH + M(8)

  -- ALL BANDS, then the bands themselves.  -1 first because it is the one
  -- that dresses a plain wall in a single click.
  local rowH = math.max(Theme.rowH, 8 * swatchZ + M(4))
  local function bandRow(idx, label)
    local cur = bands and bands[idx]
    local shown = cur
    local via
    if cur then via = "painted"
    elseif bands and bands[-1] and idx ~= -1 then
      shown = bands[-1] via = "from all bands"
    else
      shown = tile via = "its own drawing -- the void"
    end
    W.text(label, bx, ry + M(4), cur and Theme.accent or Theme.dim, small)
    swatch(shown, bx + M(58), ry)
    W.text(("$%02X  %s"):format(shown or 0, via),
           bx + M(58) + 8 * swatchZ + M(6), ry + M(4),
           cur and Theme.text or Theme.faint, small)
    if W.button("bp" .. idx, x + w - M(62), ry, M(26), M(18), "set",
                { font = small }) then
      app:paintBand(tile, idx, brush)
    end
    if cur and W.button("bx" .. idx, x + w - M(32), ry, M(22), M(18), "x",
                        { font = small }) then
      app:paintBand(tile, idx, nil)
    end
    ry = ry + rowH + M(2)
  end

  bandRow(-1, "all bands")
  ry = ry + M(4)
  for b = 0, math.min(n, 16) - 1 do
    bandRow(b, ("band %d"):format(b))
  end

  ry = ry + M(4)
  W.text("band 0 is the bottom 8px and each band above it is the next 8."
      .. "  A partial band crops the art rather than stretching it, which is"
      .. " the mesher's own rule and not something painted here.",
      bx, ry, Theme.faint, small)
  ry = ry + M(34)
  W.text("Side-face art is an EDITOR AND SIDECAR extension: pins, folds,"
      .. " heights and place edits are read by the shipped mod, and this is"
      .. " not -- it ships in the versioned sidecar for a mesher that wants"
      .. " it, and is ignored by one that does not.",
      bx, ry, Theme.warn, small)
end

function P.groups(app, x, y, w, h)
  W.panel(x, y, w, h, "multi-tile objects")
  local bx, ry = x + 8, y + 26
  if not (app.tsId and app.tile) then
    W.text("pick a tileset and a tile first", bx, ry, Theme.faint)
    return
  end
  local e = Doc.entry(app.doc, app.tsId)

  for i, g in ipairs(e.groups) do
    local ids = {}
    for _, t in ipairs(g.tiles or {}) do ids[#ids + 1] = string.format("$%02X", t) end
    W.text(("%s  %dx%d  %s  cap %s"):format(tostring(g.name or ("group " .. i)),
           g.w or 0, g.h or 0, tostring(g.class), tostring(g.cap or "none")),
           bx, ry, Theme.text, Theme.fonts.small)
    W.text(table.concat(ids, " "), bx, ry + 13, Theme.faint, Theme.fonts.small)
    if W.button("delgrp" .. i, x + w - 30, ry - 2, 22, 18, "x",
                { font = Theme.fonts.small }) then
      app:record("tileset", app.tsId, "remove object")
      local reach = {}
      for _, t in ipairs(g.tiles or {}) do reach[#reach + 1] = t end
      Doc.removeGroup(app.doc, app.tsId, i)
      app:commitEdit()
      app:invalidate({ tiles = reach })
    end
    if W.button("usegrp" .. i, x + w - 60, ry - 2, 26, 18, "eye",
                { font = Theme.fonts.small }) then
      app.previewGroup = (app.previewGroup == i) and nil or i
      app.preview.dirty = true
    end
    ry = ry + 32
  end

  ry = ry + 6
  local n = app.tileSelCount or 0
  W.text(("shift-click tiles on the sheet, then say how they are laid out."
      .. "  %d picked."):format(n), bx, ry, Theme.dim, Theme.fonts.small)
  ry = ry + 20

  local M = Theme.m
  local cw = w - M(16)
  local function row(label, id, value, lo, hi, suffix)
    W.text(label, bx, ry, Theme.dim, Theme.fonts.small)
    local lw = M(70)
    local v = math.floor(W.slider(id, bx + lw, ry - M(2), cw - lw - M(34),
        M(15), value, lo, hi, { step = 1 }) + 0.5)
    W.textRight(tostring(v) .. (suffix or ""), x + w - M(8), ry, Theme.text,
                Theme.fonts.small)
    ry = ry + M(20)
    return v
  end

  app.groupW = row("across", "gw", app.groupW or 2, 1, 4)
  app.groupH = row("down", "gh", app.groupH or 2, 1, 4)
  app.groupCap = row("repeat cap", "gcap", app.groupCap or 1, 1, 8, "x")
  if W.state.hot == "gcap" then
    app.tip = "how many times this drawing may repeat before the next copy"
        .. " becomes its own object -- 1 keeps a canopy a canopy"
  end
  ry = ry + M(6)

  if W.button("mkgroup", bx, ry, cw, Theme.btnH, "make object from picks",
              { font = Theme.fonts.small,
                disabled = n ~= app.groupW * app.groupH }) then
    local ids = {}
    for t in pairs(app.tileSel) do ids[#ids + 1] = t end
    table.sort(ids)
    app:record("tileset", app.tsId, "make object")
    Doc.addGroup(app.doc, app.tsId, {
      name = "object " .. (#e.groups + 1),
      w = app.groupW, h = app.groupH, tiles = ids,
      class = app.brushClass or "cylinder", cap = app.groupCap,
    })
    for _, t in ipairs(ids) do Doc.pin(app.doc, app.tsId, t, app.brushClass or "cylinder") end
    app:commitEdit()
    app:invalidate({ tiles = ids })
    app:say(("object made from %d tiles as %s"):format(#ids,
            app.brushClass or "cylinder"))
  end
  if n ~= app.groupW * app.groupH then
    W.text(("pick exactly %d tiles for a %dx%d object"):format(
           app.groupW * app.groupH, app.groupW, app.groupH),
           bx, ry + Theme.btnH + M(4), Theme.faint, Theme.fonts.small)
  end
end

-- ------------------------------------------------------------- the report

function P.report(app, x, y, w, h)
  W.panel(x, y, w, h, "validation report")
  local v = app.validation
  if not v then
    W.text("run validate to check every pin against the loaded tileset",
           x + 10, y + 26, Theme.faint, Theme.fonts.small)
    return
  end
  local ry = y + 26
  love.graphics.setFont(Theme.fonts.small)
  local function rows(list, col, label)
    if #list == 0 then return end
    W.text(label .. " (" .. #list .. ")", x + 8, ry, col, Theme.fonts.small)
    ry = ry + 16
    for _, m in ipairs(list) do
      if ry > y + h - 14 then return end
      local line = "[" .. tostring(m.tileset) .. "] " .. m.msg
      love.graphics.setColor(Theme.dim)
      love.graphics.printf(line, x + 12, ry, w - 24)
      local _, lines = Theme.fonts.small:getWrap(line, w - 24)
      ry = ry + #lines * 12 + 2
    end
    ry = ry + 6
  end
  rows(v.errors, Theme.bad, "errors")
  rows(v.warnings, Theme.warn, "warnings")
  rows(v.info, Theme.dim, "notes")
  if v.ok and #v.warnings == 0 then
    W.text("nothing to report -- every pin resolves against a tile this"
        .. " tileset has", x + 10, y + 26, Theme.good, Theme.fonts.small)
  end
end

-- -------------------------------------------------------------- the maps

-- EVERY MAP IN THE CACHE, not just the ones drawn with the tileset you
-- happen to have open.
--
-- Filtering to the current tileset is a reasonable default and a terrible
-- only option: the way you find the map you want is usually to search for
-- it, and then the tileset follows from the map rather than the other way
-- round.  So the list is everything, the filter is a chip, and picking a map
-- switches the tileset for you.
function P.mapBrowser(app, x, y, w, h)
  local M = Theme.m
  local bx, ry = x + M(4), y
  local cw = w - M(8)

  app.mapSearch = W.field("mapsearch", bx, ry, cw - M(78), Theme.btnH + M(1),
                          app.mapSearch or "", "search maps")
  if W.button("mapfilter", bx + cw - M(74), ry, M(74), Theme.btnH + M(1),
              app.mapFilterTs and "this set" or "all sets",
              { on = app.mapFilterTs, font = Theme.fonts.small }) then
    app.mapFilterTs = not app.mapFilterTs
  end
  if W.state.hot == "mapfilter" then
    W.state.tip = "limit the list to maps drawn with the tileset that is open"
  end
  ry = ry + Theme.btnH + M(6)

  local list = app.cache and Cache.mapList(app.cache) or {}
  local q = (app.mapSearch or ""):lower()
  local items = {}
  for _, m in ipairs(list) do
    local keep = true
    if app.mapFilterTs and app.tsId and m.tileset ~= app.tsId then keep = false end
    if keep and q ~= "" then
      keep = (m.id:lower():find(q, 1, true) ~= nil)
          or (tostring(m.label):lower():find(q, 1, true) ~= nil)
    end
    if keep then
      local edits = app.doc.maps and app.doc.maps[m.id]
      local n = 0
      if edits then for _ in pairs(edits.tiles or {}) do n = n + 1 end end
      items[#items + 1] = {
        label = m.label ~= m.id and m.label or m.id,
        value = m.id,
        sub = n > 0 and (n .. " edits") or (m.w .. "x" .. m.h),
        subColor = n > 0 and Theme.accent or Theme.faint,
        color = (m.tileset == app.tsId) and Theme.text or nil,
      }
    end
  end

  local lh = math.max(M(90), h - (ry - y) - M(6))
  local chosen = W.list("mapbrowse", bx, ry, cw, lh, items,
                        app.viewport and app.viewport.mapId,
                        { rowH = Theme.rowH, font = Theme.fonts.small })
  if chosen then app:openMap(chosen) end
  if #items == 0 then
    W.text(app.cache and "nothing matches" or "no cache loaded",
           bx + M(8), ry + M(8), Theme.faint, Theme.fonts.small)
  end
  return ry + lh
end

-- ----------------------------------------------------------- the detector

function P.detector(app, x, y, w, h)
  local M = Theme.m
  W.panel(x, y, w, h, "detector")
  local vp = app.viewport
  local rows = StructBridge.report(app.bridge, vp and vp.scene and vp.scene.S,
                                   { tsId = app.tsId })
  local ry = y + M(24)
  local font = Theme.fonts.small
  love.graphics.setFont(font)
  for _, r in ipairs(rows) do
    if ry > y + h - M(14) then break end
    local col = r.kind == "bad" and Theme.bad or r.kind == "warn" and Theme.warn
        or r.kind == "good" and Theme.good or Theme.dim
    if r.label ~= "" then
      W.text(r.label, x + M(8), ry, Theme.faint, font)
    end
    local vx = x + M(8) + math.min(M(150), w * 0.45)
    love.graphics.setColor(col)
    love.graphics.printf(r.value, vx, ry, w - (vx - x) - M(8))
    local _, lines = font:getWrap(r.value, w - (vx - x) - M(8))
    ry = ry + math.max(font:getHeight(), #lines * font:getHeight()) + M(2)
  end

  if ry < y + h - M(30) then
    ry = ry + M(6)
    if W.button("redetect", x + M(8), ry, w - M(16), Theme.btnH,
                "re-run the detector", { font = font }) then
      StructBridge.invalidate(app.bridge, vp and vp.mapId)
      if vp then vp.dirty = true end
      app:say("detector cache dropped -- re-analysing")
    end
  end
end

-- ----------------------------------------------------------- the buildings

-- THE MOD'S BUILDING TEMPLATES, AS THEY ARE, AND EDITABLE.
--
-- `profile.buildings[tilesetId]` is a list of hand-authored claims that
-- `lib/Buildings.lua` stamps wherever their tile arrangement occurs -- the
-- roof courses, the eave, the slab, and often a `parts` list naming
-- individual panels of the drawing.  It is the single biggest lever in the
-- profile and until now the editor did not even show that it existed.
--
-- The massing numbers are sliders; everything else is carried through
-- untouched, because a `parts` list is a measurement of one specific drawing
-- and a slider is not entitled to invent one.
local BUILDING_FIELDS = {
  { "roofRows",   0, 64, "how many drawn rows of the facade are ROOF" },
  { "roofBack",   0, 16, "courses the roof rises behind the eave" },
  { "roofFront",  0, 16, "courses it rises in front of it" },
  { "slab",       0, 16, "the plinth the building stands on" },
  { "frontEave",  0, 16, "how far the eave overhangs the front" },
  { "depth",      0, 16, "how deep the body is, where it is not measured" },
}

function P.buildings(app, x, y, w, h)
  local M = Theme.m
  W.panel(x, y, w, h, "buildings")
  local bx, ry = x + M(8), y + M(24)
  local cw = w - M(16)
  if not app.tsId then
    W.text("pick a tileset", bx, ry, Theme.faint, Theme.fonts.small)
    return
  end

  local base = app.bridge.profile and app.bridge.profile.buildings
      and app.bridge.profile.buildings[app.tsId] or {}
  local e = app.doc.tilesets[app.tsId]
  local patches = (e and e.buildings) or {}

  local items = {}
  for _, t in ipairs(base) do
    local id = t.id or ("#" .. #items + 1)
    local rows = (type(t.tiles) == "table") and #t.tiles or 0
    local cols = (rows > 0 and type(t.tiles[1]) == "table") and #t.tiles[1] or 0
    items[#items + 1] = { label = id, value = id,
      sub = ("%dx%d"):format(cols, rows),
      color = patches[id] and Theme.accent or nil,
      subColor = patches[id] and Theme.accent or Theme.faint }
  end
  for id, pch in pairs(patches) do
    local found = false
    for _, it in ipairs(items) do if it.value == id then found = true end end
    if not found then
      items[#items + 1] = { label = id .. "  (new)", value = id, sub = "yours",
                            color = Theme.good, subColor = Theme.good }
    end
  end

  if #items == 0 then
    W.text("this tileset has no building templates in the profile."
        .. "  Select a rectangle in the world and make one.",
        bx, ry, Theme.faint, Theme.fonts.small)
    ry = ry + M(34)
  else
    local lh = math.min(M(150), math.max(M(60), #items * Theme.rowH + M(8)))
    local chosen = W.list("blist", bx, ry, cw, lh, items, app.buildingId,
                          { rowH = Theme.rowH, font = Theme.fonts.small })
    if chosen then app.buildingId = chosen end
    ry = ry + lh + M(6)
  end

  local id = app.buildingId
  local tmpl = nil
  for _, t in ipairs(base) do if t.id == id then tmpl = t end end
  local patch = patches[id]

  if id and (tmpl or patch) then
    local function valueOf(field)
      if patch and patch[field] ~= nil then return patch[field] end
      if tmpl and tmpl[field] ~= nil then return tmpl[field] end
      return 0
    end
    for _, f in ipairs(BUILDING_FIELDS) do
      local name, lo, hi, hint = f[1], f[2], f[3], f[4]
      W.text(name, bx, ry, Theme.dim, Theme.fonts.small)
      local v = math.floor(W.slider("bf" .. name, bx + M(76), ry - M(2),
          cw - M(112), M(15), valueOf(name), lo, hi, { step = 1 }) + 0.5)
      W.textRight(tostring(v), x + w - M(8), ry, Theme.text, Theme.fonts.small)
      if W.state.hot == "bf" .. name then W.state.tip = hint end
      if v ~= valueOf(name) then
        app:record("tileset", app.tsId, "building " .. name, "bslide")
        Doc.setBuilding(app.doc, app.tsId, id, { [name] = v })
        app:invalidate()
      end
      ry = ry + M(19)
    end

    ry = ry + M(4)
    if patch then
      if W.button("brevert", bx, ry, cw, Theme.btnH, "revert this template",
                  { font = Theme.fonts.small }) then
        app:record("tileset", app.tsId, "revert building")
        Doc.setBuilding(app.doc, app.tsId, id, nil)
        app:commitEdit()
        app:invalidate()
      end
      ry = ry + Theme.btnH + M(6)
    end
  end

  local vp = app.viewport
  local n = vp and vp.selCount or 0
  if W.button("bnew", bx, ry, cw, Theme.btnH,
              "new template from selection (" .. n .. ")",
              { font = Theme.fonts.small, disabled = n == 0 }) then
    app:makeBuilding()
  end
  if W.state.hot == "bnew" then
    W.state.tip = "capture the selected rectangle's tile arrangement as a"
        .. " template -- Buildings then stamps it wherever that arrangement"
        .. " occurs, on every map in the game"
  end
end

return P
