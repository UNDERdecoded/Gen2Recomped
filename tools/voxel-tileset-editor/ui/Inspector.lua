-- ONE PANEL.
--
-- What was here before: eight tabs, each with its own layout, most of them
-- empty most of the time, and the setting you wanted in whichever one you
-- were not looking at.  Worse, the profile has keys none of them touched --
-- `figures`, `mounted`, `rail_face`, `bookcase_relief`, the `can_*` family,
-- `column_foot` -- carried faithfully through every export and editable
-- nowhere.
--
-- This is one scrolling column of collapsible sections, always in the same
-- place, in the order you actually work: what is selected, what shape it is,
-- what its faces wear, what its class means, what rules name it, and then
-- EVERYTHING ELSE -- generated from `core/Schema.lua`, which asks the live
-- profile what is in it rather than being told.  A fork that invents a key
-- gets an editor for it with nothing to update in this file.
--
-- Sections remember whether they are open, so the two you use are the two
-- that are open, and the rest is one line each.

local Theme = require("ui.Theme")
local W = require("ui.Widgets")
local Doc = require("core.Doc")
local Schema = require("core.Schema")
local Classes = require("core.Classes")
local Panels = require("ui.Panels")

local I = {}

I.open = { here = true, shape = true, faces = false, class = false,
           rules = false, objects = false, other = false }

-- ------------------------------------------------------------ helpers

local function line(app, text, x, y, colour)
  W.text(text, x, y, colour or Theme.dim, Theme.fonts.small)
  return y + Theme.fonts.small:getHeight() + Theme.m(2)
end

-- How many tiles of this tileset resolve to a class.  Measured once per
-- (class, tileset) rather than per frame: it is a scan of up to 3,500 tiles.
local function reachOf(app, class)
  local key = tostring(class) .. "/" .. tostring(app.tsId)
  app._reach = app._reach or {}
  if app._reachKey ~= key then
    app._reachKey = key
    app._reachN = (class and app.geom)
        and Doc.classReach(app.shapeOf, app.geom.count, class) or 0
  end
  return app._reachN or 0
end

-- ------------------------------------------------------------- sections

-- WHAT IS SELECTED, and what it already resolves to.  First, because every
-- other section is an edit to this and an edit you make without reading this
-- is a guess.
local function here(app, x, y, w)
  local M, small = Theme.m, Theme.fonts.small
  local Viewport = require("ui.Viewport")
  local h = Viewport.hereInfo(app.viewport, app)
  local shape = (h and h.shape) or app.shapeOf(app.tile)
  local y0 = y

  if shape then
    W.text(("%s   h=%s   %s"):format(tostring(shape.class), tostring(shape.h),
           tostring(shape.art)), x, y, Theme.text, small)
    y = y + small:getHeight() + M(2)
    y = line(app, "via " .. tostring(shape.source or "?"), x, y, Theme.faint)
  end
  if app.tile then
    y = line(app, ("tile $%02X"):format(app.tile)
        .. (h and (("   square %d,%d"):format(h.tx, h.ty)) or ""), x, y)
  end
  if h then
    if h.detTile and h.detTile ~= h.tile then
      y = line(app, ("the detector re-tiles it as $%02X"):format(h.detTile), x, y)
    end
    local r = h.run
    if r then
      y = line(app, ("in a measured volume: h=%s%s%s"):format(tostring(r.h),
               r.rise and ("  roof +" .. tostring(r.rise)) or "",
               r.unit and ("  template " .. tostring(r.unit)) or ""),
               x, y, Theme.accent)
    end
    if h.group then
      y = line(app, "part of object: " .. tostring(h.group.name or "?"), x, y,
               Theme.accent)
    end
    if h.place then
      local pl = h.place
      y = line(app, ("override on THIS square: %s%s%s"):format(
               pl.art and (tostring(pl.art) .. " ") or "",
               pl.h and ("h=" .. tostring(pl.h) .. " ") or "",
               pl.fold and ("fold=" .. tostring(pl.fold)) or ""),
               x, y, Theme.warn)
    end
    if h.skipped then
      y = line(app, "the detector draws this square as part of an object",
               x, y, Theme.faint)
    end
  end

  local n = #app:selectedTileIds()
  local sq = #app:selectedSquares()
  y = line(app, ("%d tile%s and %d square%s selected"):format(
           n, n == 1 and "" or "s", sq, sq == 1 and "" or "s"),
           x, y, Theme.accent)

  -- CLEARING ONE SQUARE'S OVERRIDE belongs here, next to the line that says
  -- it has one.  It used to be a tab of its own, which meant reading about
  -- the override in one place and undoing it in another.
  if h and h.place then
    if W.button("clrplace", x, y, w, Theme.btnH, "clear this square's override",
                { font = small }) then
      app:record("map", app.viewport.mapId, "clear square")
      Doc.setMapEdit(app.doc, app.viewport.mapId, h.tx, h.ty, nil)
      Viewport.placeChanged(app.viewport, h.tx, h.ty)
      app:commitEdit()
      app.shapeCache = {}
    end
    y = y + Theme.btnH + M(4)
  end
  if y == y0 then y = line(app, "nothing selected", x, y, Theme.faint) end
  return y
end

-- THE SHAPE: what the square is, how it folds, how tall it stands.  Three
-- controls, and every one of them says what it will reach before it reaches.
local function shapeSection(app, x, y, w)
  local M, small = Theme.m, Theme.fonts.small
  local shape = app.shapeOf(app.tile)
  local e = app.doc.tilesets[app.tsId]
  local pinned = e and e.pins and e.pins[app.tile]
  local resolved = shape and shape.class
  local vocab = app.bridge.classInfo or Classes.FALLBACK

  -- height, typed, with its reach
  W.text("height (px)", x, y, Theme.dim, small)
  y = y + M(13)
  local fieldW, btnW = M(58), M(46)
  if W.state.typing ~= "heightfield" then
    app.heightText = tostring(math.floor((shape and shape.h) or 0))
  end
  local typed, submitted = W.field("heightfield", x, y, fieldW, Theme.btnH,
                                   app.heightText or "", "0", { numeric = true })
  app.heightText = typed
  local parsed = tonumber(typed)
  local okNum = parsed ~= nil and parsed >= -16 and parsed <= 128
  local hit = W.button("seth", x + fieldW + M(6), y, btnW, Theme.btnH, "set",
                       { font = small, disabled = not okNum })
  if not okNum and typed ~= "" and typed ~= "-" then
    W.text("-16 to 128", x + fieldW + btnW + M(14), y + M(4), Theme.bad, small)
  end
  y = y + Theme.btnH + M(4)

  app.heightHow = app.heightHow or "tile"
  local nT, nS = #app:selectedTileIds(), #app:selectedSquares()
  y = W.chips("hreach", x, y, w, {
    { id = "square", label = ("this square (%d)"):format(nS),
      hint = "a coordinate override on the selected squares of THIS map and"
          .. " nowhere else" },
    { id = "tile", label = ("these tiles (%d)"):format(nT),
      hint = "the selected drawings, everywhere they appear.  Touches no"
          .. " class and no pin, so the map is not re-measured" },
    { id = "class", label = ("class %s (%d)"):format(tostring(resolved or "?"),
                                                     reachOf(app, resolved)),
      hint = "moves EVERY tile of that class in the tileset" },
  }, function(r) return app.heightHow == r.id end,
     function(r) app.heightHow = r.id end)
  if okNum and (hit or submitted) then
    app:heightSelection(math.floor(parsed), app.heightHow)
    app._reachKey = nil
  end
  y = y + M(4)

  -- fold
  local fold = e and e.folds and e.folds[app.tile]
  local effFold = fold or (shape and shape.art)
  W.text(fold and "fold (set here)" or "fold (from the mod)", x, y,
         fold and Theme.accent or Theme.dim, small)
  y = y + M(14)
  y = W.chips("fold", x, y, w, Classes.FOLDS,
              function(f) return effFold == f.id end,
              function(f) app:foldSelection(fold == f.id and nil or f.id) end)

  -- class.  The list highlights what it RESOLVES to, not only what we pinned.
  W.text("class", x, y, Theme.dim, small)
  y = y + M(14)
  local items = {}
  for _, name in ipairs(app.classNames or {}) do
    local info = vocab[name] or {}
    local note = tostring(info.h) .. "  " .. tostring(info.art)
    if name == pinned then note = note .. "   * pinned here"
    elseif name == resolved then
      note = note .. "   * from " .. tostring(shape and shape.source or "the mod")
    end
    items[#items + 1] = { label = name, value = name, sub = note,
                          color = name == pinned and Theme.accent or nil }
  end
  local listH = M(150)
  local chosen = W.list("classlist", x, y, w, listH, items, pinned or resolved,
                        { rowH = Theme.rowH, font = small })
  if chosen then
    if chosen == pinned then
      app:record("tileset", app.tsId, "unpin")
      Doc.unpin(app.doc, app.tsId, app.tile)
      app:commitEdit()
      app:invalidate({ tiles = { app.tile } })
    else
      app:pinSelection(chosen)
    end
    app._reachKey = nil
  end
  y = y + listH + M(6)

  local halfW = (w - M(6)) / 2
  if W.button("clearpin", x, y, halfW, Theme.btnH, "revert tile",
              { font = small }) then
    app:record("tileset", app.tsId, "revert tile")
    Doc.unpin(app.doc, app.tsId, app.tile)
    Doc.clearSculpt(app.doc, app.tsId, app.tile)
    Doc.clearBands(app.doc, app.tsId, app.tile)
    app:commitEdit()
    app:invalidate({ tiles = { app.tile } })
  end
  if W.button("makeobj", x + halfW + M(6), y, halfW, Theme.btnH,
              "make an object", { font = small }) then
    app:makeObjectFromSelection()
  end
  if W.state.hot == "makeobj" then
    W.state.tip = "names the selection's arrangement as one thing, so every"
        .. " other place those tiles sit together answers the same way"
  end
  return y + Theme.btnH + M(4)
end

-- WHAT A CLASS MEANS, with the reach in the heading because this is the
-- widest edit in the tool.
local function classSection(app, x, y, w)
  local M, small = Theme.m, Theme.fonts.small
  local shape = app.shapeOf(app.tile)
  local cls = shape and shape.class
  if not cls then return line(app, "no class resolved", x, y, Theme.faint) end
  local vocab = app.bridge.classInfo or Classes.FALLBACK
  local info = vocab[cls] or {}
  local over = Doc.classHeight(app.doc, app.tsId, cls)
  local n = reachOf(app, cls)

  y = line(app, ("%s: the mod says h=%s, %s"):format(cls, tostring(info.h),
           tostring(info.art)), x, y, Theme.text)
  if over then
    y = line(app, ("this document says h=%d for this tileset"):format(over),
             x, y, Theme.accent)
  end
  y = line(app, ("%d tile%s in this tileset resolve as %s"):format(
           n, n == 1 and "" or "s", cls), x, y, Theme.warn)
  y = y + M(2)

  -- the class height, which is a REAL export: `heights[class]` is per
  -- tileset and the mod already reads it
  W.text("class height", x, y, Theme.dim, small)
  y = y + M(13)
  local fw = M(58)
  local id = "clsh"
  if W.state.typing ~= id then
    app.classHText = tostring(math.floor(over or info.h or 0))
  end
  local typed, sub = W.field(id, x, y, fw, Theme.btnH, app.classHText or "0",
                             "0", { numeric = true })
  app.classHText = typed
  local v = tonumber(typed)
  local okv = v ~= nil and v >= -16 and v <= 128
  local set = W.button("clshset", x + fw + M(6), y, M(46), Theme.btnH, "set",
                       { font = small, disabled = not okv })
  if okv and (set or sub) then
    app:record("tileset", app.tsId, "class height")
    Doc.setHeight(app.doc, app.tsId, cls, math.floor(v))
    app:commitEdit()
    app:invalidate()
    app:say(("class %s is %dpx here -- %d tile%s move"):format(cls,
            math.floor(v), n, n == 1 and "" or "s"), "warn")
  end
  if over and W.button("clshclr", x + fw + M(58), y, M(56), Theme.btnH,
                       "revert", { font = small }) then
    app:record("tileset", app.tsId, "revert class height")
    Doc.setHeight(app.doc, app.tsId, cls, nil)
    app:commitEdit()
    app:invalidate()
  end
  y = y + Theme.btnH + M(6)

  -- THE ART MODE IS NOT A PROFILE KEY.  `TileShape.CLASS_INFO` is global and
  -- lives in the mod's source, so "make this class a billboard" cannot be
  -- said in `voxel_heights.lua` at all.  What CAN be said is the same thing
  -- one level down: a fold on every tile of the class, which exports.  So
  -- that is what this offers, named for what it does.
  W.text("fold every tile of this class", x, y, Theme.dim, small)
  y = y + M(14)
  y = W.chips("clsfold", x, y, w, Classes.FOLDS,
              function(f) return false end,
              function(f) app:foldClass(cls, f.id) end)
  y = line(app, "a class's art mode is global to the mod and not a profile"
      .. " key; setting the fold of its tiles is the same statement in the"
      .. " place the profile can actually carry it.", x, y, Theme.faint)
  return y
end

-- EVERYTHING ELSE: generated, not written.
local function otherSection(app, x, y, w)
  local M, small = Theme.m, Theme.fonts.small
  -- THE PROFILE'S OWN ENTRY FOR THIS TILESET.  `bridge.profile` is the whole
  -- of `data/voxel_heights.lua`; the per-tileset entries live under
  -- `.tilesets`, which is the shape `Shape.mergeProfile` reads and therefore
  -- the shape this has to read too.
  local prof = app.bridge.profile
  local base = (prof and prof.tilesets and prof.tilesets[app.tsId]) or {}
  local docE = app.doc.tilesets[app.tsId]
  local vocab = app.bridge.classInfo or Classes.FALLBACK
  local fields = Schema.sideFields(base, docE, vocab)
  local tile = app.tile

  y = line(app, "every key in this tileset's profile entry that is not a"
      .. " class.  Read from the live profile, so a fork's own keys appear"
      .. " here too.", x, y, Theme.faint)
  y = y + M(2)

  for _, f in ipairs(fields) do
    local touched = docE and docE.extra and docE.extra[f.key] ~= nil
    local mentions = Schema.mentions(f, tile)
    local right = (f.count and (f.count .. " entries") or tostring(f.value))
    W.text(f.key, x, y + M(3), touched and Theme.accent or Theme.text, small)
    W.textRight(("%s  %s"):format(f.kind, right), x + w - M(4), y + M(3),
                Theme.faint, small)
    y = y + M(17)

    local bw = (w - M(12)) / 3
    if f.kind == "tileList" then
      if W.button("sl" .. f.key, x, y, bw * 2, M(18),
                  mentions and ("remove $%02X"):format(tile or 0)
                           or ("add $%02X"):format(tile or 0),
                  { font = small, disabled = tile == nil }) then
        app:record("tileset", app.tsId, f.key)
        Doc.setListMember(app.doc, app.tsId, f.key, f.value, tile, not mentions)
        app:commitEdit()
        app:invalidate({ tiles = { tile } })
      end
    elseif f.kind == "tileMap" then
      local cur = mentions and f.value[tile] or nil
      local fid = "sm" .. f.key
      if W.state.typing ~= fid then
        app.extraText = app.extraText or {}
        app.extraText[f.key] = cur and tostring(cur) or ""
      end
      app.extraText = app.extraText or {}
      local t, subm = W.field(fid, x, y, bw, M(18),
                              app.extraText[f.key] or "", "value",
                              { numeric = true })
      app.extraText[f.key] = t
      local vnum = tonumber(t)
      if (subm or W.button("smb" .. f.key, x + bw + M(6), y, bw, M(18), "set",
                           { font = small, disabled = tile == nil })) then
        app:record("tileset", app.tsId, f.key)
        Doc.setMapMember(app.doc, app.tsId, f.key, f.value, tile, vnum)
        app:commitEdit()
        app:invalidate({ tiles = { tile } })
      end
      W.text(mentions and ("$%02X -> %s"):format(tile, tostring(cur))
                       or "not named here",
             x + bw * 2 + M(12), y + M(3), Theme.faint, small)
    elseif f.kind == "number" then
      local fid = "sn" .. f.key
      if W.state.typing ~= fid then
        app.extraText = app.extraText or {}
        app.extraText[f.key] = tostring(f.value)
      end
      app.extraText = app.extraText or {}
      local t, subm = W.field(fid, x, y, bw, M(18), app.extraText[f.key] or "",
                              "0", { numeric = true })
      app.extraText[f.key] = t
      if subm and tonumber(t) then
        app:record("tileset", app.tsId, f.key)
        Doc.setExtra(app.doc, app.tsId, f.key, tonumber(t))
        app:commitEdit()
        app:invalidate()
      end
    elseif f.kind == "flag" then
      if W.button("sf" .. f.key, x, y, bw, M(18),
                  f.value and "true" or "false",
                  { font = small, on = f.value and true or false }) then
        app:record("tileset", app.tsId, f.key)
        Doc.setExtra(app.doc, app.tsId, f.key, not f.value)
        app:commitEdit()
        app:invalidate()
      end
    else
      -- ruleMap, templates, numberMap, opaque: things with a purpose-built
      -- editor elsewhere, or things this cannot safely guess the shape of.
      -- Saying which is honest; pretending an opaque table is a tile list
      -- would corrupt it.
      W.text(mentions and "names this tile -- edited in its own section below"
                       or "not named by this tile",
             x, y + M(3), Theme.faint, small)
    end
    y = y + M(22)

    if touched and W.button("sx" .. f.key, x + w - M(56), y - M(20), M(52),
                            M(18), "revert", { font = small }) then
      app:record("tileset", app.tsId, "revert " .. f.key)
      Doc.setExtra(app.doc, app.tsId, f.key, nil)
      app:commitEdit()
      app:invalidate()
    end
  end
  return y
end

-- --------------------------------------------------------------- the panel

-- NO SCROLL OF ITS OWN.
--
-- The right dock already scrolls, and a scrolling column inside a scrolling
-- column is two things fighting over the wheel and a hit test that is off by
-- whichever offset you forgot.  So this lays out from `y`, returns the
-- bottom it reached, and lets the dock be the one thing that scrolls.
function I.draw(app, x, y, w)
  local M = Theme.m
  local bx, cw = x, w
  local cy = y

  if not (app.tsId and app.geom) then
    W.text("no tileset loaded", bx, cy, Theme.faint, Theme.fonts.small)
    return cy + M(20)
  end

  -- Each body lays out from the y it is given and returns the y it reached,
  -- so a collapsed section costs one header row and an open one costs exactly
  -- what it drew.
  local function section(id, label, right, body)
    local open
    open, cy = W.section(id, bx, cy, cw, label, I.open[id], right)
    I.open[id] = open
    if open then cy = body(app, bx, cy, cw) + M(4) end
    return cy
  end

  local stats = Doc.stats(app.doc)
  section("here", "here", nil, here)
  section("shape", "shape", nil, shapeSection)
  section("faces", "side faces",
          (stats.bands > 0) and (stats.bands .. " painted") or "the void",
          function(a, sx, sy, sw) Panels.faces(a, sx, sy, sw, M(300)) return sy + M(300) end)
  section("class", "what this class means", nil, classSection)
  section("rules", "rules", (stats.cond > 0) and (stats.cond .. " set") or nil,
          function(a, sx, sy, sw) Panels.conditional(a, sx, sy, sw, M(260)) return sy + M(260) end)
  section("objects", "objects",
          (stats.groups > 0) and (stats.groups .. " named") or nil,
          function(a, sx, sy, sw) Panels.groups(a, sx, sy, sw, M(240)) return sy + M(240) end)
  section("other", "everything else",
          (stats.extra > 0) and (stats.extra .. " changed") or nil,
          otherSection)

  return cy
end

return I
