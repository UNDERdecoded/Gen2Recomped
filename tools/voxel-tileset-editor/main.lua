-- Voxel Tileset Editor.
--
-- A standalone desktop tool for turning Game Boy tilesets into voxel
-- geometry, and for saving those decisions as a profile the Dramatic Shape
-- voxel mod already knows how to read.
--
-- THE VIEW IS THE EDITOR.  The sheet and the tile canvas are reference
-- material down the sides; the middle of the window is a 3D world you can
-- drag, and an edit made there lands on the TILE, so every cell drawn with
-- that tile moves at once and you watch it happen.
--
-- IT NEVER OPENS A CARTRIDGE, NEVER TOUCHES A SAVE, AND CHANGES NOTHING
-- ABOUT HOW THE GAME PLAYS.  It reads the ROM cache the game already wrote,
-- asks the installed voxel mod's own TileShape what a tile is, and writes
-- tile ids and class names back out.

local Fs = require("core.Fs")
local Paths = require("core.Paths")
local Cache = require("core.Cache")
local Gen3Bridge = require("core.Gen3Bridge")
local ModBridge = require("core.ModBridge")
local Classes = require("core.Classes")
local Shape = require("core.Shape")
local StructBridge = require("core.StructBridge")
local Doc = require("core.Doc")
local History = require("core.History")
local Validate = require("core.Validate")
local Export = require("core.Export")
local Serialize = require("core.Serialize")

local Theme = require("ui.Theme")
local W = require("ui.Widgets")
local Panels = require("ui.Panels")
local Inspector = require("ui.Inspector")
local Viewport = require("ui.Viewport")

local app = {
  tool = "pick",
  brushHeight = 16,
  brushClass = "wall",
  sel = {},
  tileSel = {},
  messages = {},
  showClassTint = true,
  showHeights = true,
  condRows = 1,
  tab = "shape",
  mode = "tileset",
  mapFilterTs = false,
  mapSearch = "",
  docks = { left = true, right = true, log = true },
  open = { cache = true, tilesets = true, sheet = true, export = false,
           canvas = true, maps = true },
}

-- ------------------------------------------------------------- undo / redo

-- Every mutation goes through here first.  `record` takes the BEFORE picture
-- of the slot about to change; `commitEdit` ends a coalescing run so the next
-- gesture starts its own entry.  A drag records once and then writes freely.
function app:record(kind, id, label, coalesce)
  if not id then return end
  History.record(self.history, self.doc, kind, id, label, coalesce)
end

function app:commitEdit()
  History.commit(self.history)
end

local function afterHistory(self, entry, what)
  if not entry then
    self:say("nothing to " .. what)
    return
  end
  -- A restored slot can differ from the live one in ways only a re-resolve
  -- can find -- a pin came back, a class height moved -- so this is the full
  -- invalidation rather than the cheap one.
  Doc.touch(self.doc)
  self:invalidate()
  if entry.kind == "map" and self.viewport then self.viewport.dirty = true end
  self:say(what .. ": " .. tostring(entry.label))
end

function app:undo()
  afterHistory(self, History.undoOnce(self.history, self.doc), "undo")
end

function app:redo()
  afterHistory(self, History.redoOnce(self.history, self.doc), "redo")
end

function app:say(msg, kind)
  table.insert(self.messages, 1, { text = msg, kind = kind or "info",
                                   t = love.timer.getTime() })
  while #self.messages > 10 do table.remove(self.messages) end
end

-- ---------------------------------------------------------- window fitting

-- FIT THE WINDOW TO THE SCREEN THAT EXISTS.
--
-- love.conf cannot ask how big the desktop is -- there is no window yet -- so
-- the size written there is a guess, and a guess of 1600 wide is off the
-- right-hand edge of a 1080p display the moment the OS is set to 125%.  What
-- that looks like from the outside is a panel with its options "cut off",
-- and no amount of scrolling reaches them because they are not on the screen.
--
-- So: measure the desktop, take a margin off it for the taskbar and the
-- window chrome, and never open larger than that.  A size the reader has
-- chosen before is honoured, clamped the same way.
function app:fitWindow(settings)
  local dw, dh = 1280, 720
  if love.window and love.window.getDesktopDimensions then
    local ok, w, h = pcall(love.window.getDesktopDimensions)
    if ok and w and w > 0 then dw, dh = w, h end
  end

  -- 6% off each dimension leaves room for a taskbar and a title bar without
  -- having to know how tall either of them is on this machine.
  local maxW = math.floor(dw * 0.94)
  local maxH = math.floor(dh * 0.92)

  local want = settings.window or {}
  local w = math.min(tonumber(want.w) or 1600, maxW)
  local h = math.min(tonumber(want.h) or 940, maxH)

  local cur = { love.graphics.getDimensions() }
  if math.abs(cur[1] - w) > 2 or math.abs(cur[2] - h) > 2 then
    pcall(love.window.setMode, w, h, {
      resizable = true, vsync = 1, depth = 24, highdpi = false,
      minwidth = 820, minheight = 560,
    })
  end

  -- THE UI SCALE FOLLOWS THE SHORT SIDE, because vertical room is what runs
  -- out first: the docks are lists and lists are tall.  A 1080p screen gets
  -- slightly smaller type so a whole panel fits rather than most of one.
  self.uiScale = tonumber(want.scale)
  if not self.uiScale then
    if h <= 800 then self.uiScale = 0.82
    elseif h <= 1000 then self.uiScale = 0.9
    else self.uiScale = 1.0 end
  end
  self.uiScale = math.max(0.7, math.min(1.6, self.uiScale))
end

function app:setScale(v)
  self.uiScale = math.max(0.7, math.min(1.6, v))
  Theme.load(self.uiScale)
  self.settingsDirty = false
  self:saveSettings()
  self:say(("interface scale %d%%"):format(math.floor(self.uiScale * 100 + 0.5)))
end

function app:saveSettings()
  local w, h = love.graphics.getDimensions()
  local s = self.settings or {}
  s.window = { w = w, h = h, scale = self.uiScale }
  self.settings = s
  pcall(love.filesystem.write, "settings.lua",
        "return " .. Serialize.value(s) .. "\n")
end

-- A drag-resize fires this many times a second, and writing a settings file
-- per frame of a drag is a lot of disk for a number nobody reads until the
-- next launch.  Mark it and write once, on the way out.
function love.resize()
  app.settingsDirty = true
end

function love.quit()
  if app.settingsDirty then app:saveSettings() end
end

-- ------------------------------------------------------------- settings

local function loadSettings()
  if not (love.filesystem.getInfo and love.filesystem.getInfo("settings.lua")) then
    return {}
  end
  local chunk = love.filesystem.load("settings.lua")
  local ok, v = pcall(chunk)
  return (ok and type(v) == "table") and v or {}
end

-- --------------------------------------------------------------- loading

function app:openCache(idx)
  local entry = self.paths.cacheRoots[idx]
  if not entry then return end
  local c, err = Cache.open(entry.root, entry.version)
  if not c then
    self:say("cache " .. entry.version .. ": " .. tostring(err), "bad")
    return
  end
  self.cacheIdx = idx
  self.cache = c

  -- GEN 3 NEEDS A HARNESS BEFORE ITS TILESETS MEAN ANYTHING.  A Hoenn record
  -- names a pair and carries no art; the mod's own Gen3 module composites it,
  -- and it needs Game.data and one engine function to do that.  Installed
  -- here, once per cache, and reported either way -- "Emerald is missing" and
  -- "Emerald is here but has no art" are different problems.
  self.gen3 = false
  local anyGen3 = false
  for _, id in ipairs(c.ids) do
    if Gen3Bridge.isGen3Record(c.tilesets[id]) then anyGen3 = true break end
  end
  if anyGen3 then
    local ok, why = Gen3Bridge.install(c, self.paths.gameDir, self.bridge)
    self.gen3 = ok and true or false
    if not ok then
      self:say("Gen 3 art unavailable: " .. tostring(why), "warn")
    end
  end

  self:say(("loaded %d tilesets from the %s cache%s"):format(#c.ids, c.version,
           anyGen3 and (self.gen3 and " (Gen 3 pairs composited)"
                                 or " (Gen 3, no art)") or ""))
  self:selectTileset(c.ids[1])
end

function app:selectTileset(id)
  if not (self.cache and id) then return end
  local ts = self.cache.tilesets[id]
  if not ts then return end
  self.tsId = id
  self.ts = ts
  self.gen = Cache.generationOf(ts)

  local geom, data, shapeData
  if self.gen == 3 then
    geom = Gen3Bridge.geometry(ts)
    if geom then
      data = Gen3Bridge.imageData(ts)
      shapeData = Gen3Bridge.shapeData(ts)
    end
    if not geom then
      geom = Cache.tileGeometry(ts)
      self:say(id .. ": no Gen 3 atlas -- geometry only", "warn")
    end
  else
    geom = Cache.tileGeometry(ts)
    data = Cache.imageData(self.cache, ts)
  end
  self.geom = geom
  self.atlasData = data
  self.shapeData = shapeData
  self.atlasImage = nil
  if data then
    local ok, img = pcall(love.graphics.newImage, data)
    if ok then
      img:setFilter("nearest", "nearest")
      self.atlasImage = img
    end
  end

  -- THE PIXEL READER THE SHAPE PASSES USE.  On Gen 3 that is the SHAPE
  -- surface, not the texture atlas: the two are laid out identically and
  -- differ only in alpha, and alpha is the whole point -- the ground is cut
  -- out of it, so a silhouette pass sees a real outline instead of a
  -- wall-to-wall opaque rectangle that carves to nothing.
  local g = geom
  local src = shapeData or data
  self.pixel = function(tile, px, py)
    if not src then return nil end
    local ax = (tile % g.perRow) * 8 + (px % 8)
    local ay = math.floor(tile / g.perRow) * 8 + (py % 8)
    if ax < 0 or ay < 0 or ax >= g.atlasW or ay >= g.atlasH then return nil end
    local ok, r, gg, b, a = pcall(src.getPixel, src, ax, ay)
    if not ok then return nil end
    return r, gg, b, a
  end
  self.meshCtx = { perRow = g.perRow, atlasW = g.atlasW, atlasH = g.atlasH,
                   pixel = self.pixel }

  self.resolver = Shape.newResolver(self.bridge, ts, id, self.doc)
  self.classNames = Classes.sortedNames(self.bridge.classInfo or Classes.FALLBACK)
  self.groundTile = (ts.walkable and ts.walkable[1]) or 0
  self.tileSel = {}
  self.sel = {}
  self.mapList = nil
  self:selectTile(self:firstDrawnTile())
  Viewport.useTiles(self.viewport, self)
end

-- OPEN ON A TILE THAT IS A PICTURE OF SOMETHING.
--
-- Tile 0 is blank in most tilesets and solid black in several -- it is the
-- void filler.  Opening on it means the whole world is textured black, which
-- looks exactly like a renderer that has failed and is really a correct
-- picture of a black tile.  So: the first tile with more than one shade in
-- it.  Capped, because a Gen 3 pair has thousands and this runs on every
-- tileset change.
function app:firstDrawnTile()
  if not (self.pixel and self.geom) then return 0 end
  local limit = math.min(self.geom.count, 512)
  for tile = 0, limit - 1 do
    local first, varied = nil, false
    for py = 0, 7 do
      for px = 0, 7 do
        local r, g, b = self.pixel(tile, px, py)
        if r then
          local v = math.floor(math.min(r, g, b) * 8)
          if first == nil then first = v elseif v ~= first then varied = true end
        end
      end
      if varied then break end
    end
    if varied then return tile end
  end
  return 0
end

-- OPEN A MAP, WHATEVER TILESET IT IS DRAWN WITH.
--
-- The map is the thing being looked for; the tileset follows from it.  Making
-- the reader find the tileset first and then the map is the wrong way round
-- and is why the map view was hard to find at all.
function app:openMap(mapId)
  if not self.cache then return end
  local def = Cache.map(self.cache, mapId)
  if not def then self:say("no such map: " .. tostring(mapId), "bad") return end
  if def.tileset and def.tileset ~= self.tsId then
    if self.cache.tilesets[def.tileset] then
      self:selectTileset(def.tileset)
    else
      self:say(("%s is drawn with %s, which is not in this cache")
               :format(mapId, tostring(def.tileset)), "warn")
      return
    end
  end
  self.mode = "map"
  if Viewport.useMap(self.viewport, self, mapId) then
    self:say(("%s -- %dx%d blocks, %s"):format(mapId, def.width or 0,
             def.height or 0, tostring(def.tileset)))
  end
end

function app:setMode(mode)
  self.mode = mode
  if mode == "map" then
    if not (self.viewport.mapId and self.viewport.source == "map") then
      -- land somewhere real rather than on an empty view: the first map drawn
      -- with the tileset that is open, and failing that the first map at all
      local list = self.cache and Cache.mapList(self.cache) or {}
      local pick
      for _, m in ipairs(list) do
        if m.tileset == self.tsId then pick = m.id break end
      end
      pick = pick or (list[1] and list[1].id)
      if pick then self:openMap(pick)
      else self:say("this cache has no maps to open", "warn") end
    else
      self.viewport.source = "map"
      self.viewport.dirty = true
    end
  else
    Viewport.useTiles(self.viewport, self)
  end
end

function app:selectTile(tile)
  self.tile = tile
  self.sel = {}
  self.shapeCache = {}
  if self.viewport and self.viewport.source == "tile" then
    self.viewport.dirty = true
  end
end

-- A profile change: the resolver has to re-resolve, and everything drawn
-- changes.  A fold or a sculpt does not come through here -- see Doc.touch.
-- A PROFILE CHANGE, AS NARROWLY AS IT CAN BE STATED.
--
-- `opts.tiles` is the list of tile ids the edit actually named.  A pin is a
-- statement about a DRAWING, so only the squares drawn with those ids (and
-- their neighbours, which can see them) have changed -- on a Hoenn route that
-- is a few dozen squares out of two thousand, and re-meshing all two thousand
-- is what "it reloads the whole map instead of just the tiles I am editing"
-- was.  Without `opts.tiles` -- an undo, a loaded document, a new building
-- template -- the reach is genuinely unknown and everything goes.
--
-- Note what is NOT here any more: `viewport.dirty`.  That is a full rebuild
-- -- new grid, new reference plane, a fresh measurement of the whole map --
-- and none of those three things is changed by a pin.
function app:invalidate(opts)
  opts = opts or {}
  if self.resolver then self.resolver:syncTo(self.doc) end
  self.shapeCache = {}
  local vp = self.viewport
  if not vp then return end

  if opts.tiles and #opts.tiles > 0 then
    local Viewport_ = require("ui.Viewport")
    for _, t in ipairs(opts.tiles) do Viewport_.tileIdChanged(vp, t) end
  else
    vp.scene:invalidateAll()
  end

  -- A PIN CHANGES WHAT THE DETECTOR MEASURES.  Structures reads TileShape on
  -- its way to deciding what is a volume and what is a tree, so its cached
  -- analysis is downstream of the profile and has to go with it -- but it is
  -- marked stale here and re-run once the gesture settles, not on this frame.
  StructBridge.invalidate(self.bridge, vp.mapId)
  require("ui.Viewport").markStructStale(vp)
end

function app.shapeOf(tile)
  local self = app
  if not self.resolver then return nil end
  self.shapeCache = self.shapeCache or {}
  local hit = self.shapeCache[tile]
  if hit ~= nil then return hit ~= false and hit or nil end
  local s = self.resolver:tile(tile)
  self.shapeCache[tile] = s or false
  return s
end

-- --------------------------------------------------------------- painting

function app:paintTexel(i, j)
  if not (self.tsId and self.tile) then return end
  if self.tool == "lasso" then self.sel[j * 8 + i] = true return end
  -- one history entry per STROKE, not per texel
  self:record("tileset", self.tsId, self.tool .. " brush", "brush")

  local shape = app.shapeOf(self.tile)
  local base = shape and shape.h or 0

  if self.tool == "height" then
    local s = Doc.sculpt(self.doc, self.tsId, self.tile, 8, base)
    if next(self.sel) then
      for k in pairs(self.sel) do s.h[k + 1] = self.brushHeight end
    else
      s.h[j * 8 + i + 1] = self.brushHeight
    end
    self:sculptChanged()
    return
  end
  if self.tool == "erase" then
    local s = Doc.hasSculpt(self.doc, self.tsId, self.tile)
    if s then
      if next(self.sel) then
        for k in pairs(self.sel) do s.h[k + 1] = base end
      else
        s.h[j * 8 + i + 1] = base
      end
      local any = false
      for _, v in ipairs(s.h) do if v ~= base then any = true break end end
      if not any then Doc.clearSculpt(self.doc, self.tsId, self.tile) end
      self:sculptChanged()
    end
    return
  end
  if self.tool == "pane" then
    -- A window pane is not a shorter wall: it is the wall's own face with one
    -- voxel taken out of it, so the glass keeps a thin face and the frame
    -- around it stays where it was drawn.
    local s = Doc.sculpt(self.doc, self.tsId, self.tile, 8, base)
    local keys = next(self.sel) and self.sel or { [j * 8 + i] = true }
    for k in pairs(keys) do s.h[k + 1] = math.max(0, base - 1) end
    self:sculptChanged()
    return
  end
end

function app:sculptChanged()
  Doc.touchSculpt(self.doc)
  self.shapeCache = {}
  if self.viewport then Viewport.tileIdChanged(self.viewport, self.tile) end
end

function app:wand(i, j)
  local r, g, b = self.pixel(self.tile, i, j)
  if not r then return end
  local want = Classes.shadeClass(math.min(r, g, b))
  local contiguous = love.keyboard.isDown("lshift", "rshift")
  local function shadeAt(x, yy)
    local rr, gg, bb = self.pixel(self.tile, x, yy)
    if not rr then return nil end
    return Classes.shadeClass(math.min(rr, gg, bb))
  end
  if not love.keyboard.isDown("lctrl", "rctrl") then self.sel = {} end
  if contiguous then
    local q, seen = { { i, j } }, { [j * 8 + i] = true }
    local qi = 1
    while qi <= #q do
      local p = q[qi] qi = qi + 1
      self.sel[p[2] * 8 + p[1]] = true
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = p[1] + d[1], p[2] + d[2]
        local k = ny * 8 + nx
        if nx >= 0 and ny >= 0 and nx < 8 and ny < 8 and not seen[k]
           and shadeAt(nx, ny) == want then
          seen[k] = true
          q[#q + 1] = { nx, ny }
        end
      end
    end
  else
    for yy = 0, 7 do
      for xx = 0, 7 do
        if shadeAt(xx, yy) == want then self.sel[yy * 8 + xx] = true end
      end
    end
  end
  self:say(("wand: %s%s"):format(want, contiguous and " (contiguous)" or ""))
end

-- A BUILDING TEMPLATE FROM WHAT IS SELECTED.
--
-- The selection's bounding box is the arrangement, exactly as it is for an
-- object -- but a building is claimed by `lib/Buildings.lua` rather than
-- resolved by TileShape, so it carries massing numbers instead of a class.
-- Everything starts at zero: a template that claimed a roof it had not been
-- told the height of would be a worse answer than the detector's own.
function app:makeBuilding()
  local vp = self.viewport
  if not (vp and vp.grid and self.tsId and (vp.selCount or 0) > 0) then return end
  local x0, y0, x1, y1
  for _, e in pairs(vp.sel) do
    x0 = math.min(x0 or e.tx, e.tx) x1 = math.max(x1 or e.tx, e.tx)
    y0 = math.min(y0 or e.ty, e.ty) y1 = math.max(y1 or e.ty, e.ty)
  end
  local rows = {}
  for j = y0, y1 do
    local row = {}
    for i = x0, x1 do row[#row + 1] = vp.grid:tileAt(i, j) end
    rows[#rows + 1] = row
  end
  local n = 1
  local id
  repeat
    id = ("custom_%02d"):format(n)
    n = n + 1
  until not Doc.building(self.doc, self.tsId, id)

  self:record("tileset", self.tsId, "new building template")
  Doc.setBuilding(self.doc, self.tsId, id, {
    tiles = rows, roofRows = 0, roofBack = 0, roofFront = 0,
    roofCycle = { 0, 0 }, slab = 0, frontEave = 0, depth = 0,
  })
  self:commitEdit()
  self.buildingId = id
  self.tab = "buildings"
  self:invalidate()
  self:say(("building template %s: %dx%d tiles -- set its roof and slab on"
            .. " the buildings tab"):format(id, x1 - x0 + 1, y1 - y0 + 1))
end

-- WHAT AN EDIT APPLIES TO.
--
-- Three selections exist and they are not the same thing: faces picked in the
-- WORLD, tiles picked on the SHEET, and the one tile that is currently open.
-- The first version only ever looked at the last two, so selecting twenty
-- faces in the world and clicking a class changed one tile -- which reads
-- exactly like multi-select not working, because from the outside it is not.
--
-- The world selection wins when there is one, because it is the one you are
-- looking at.
function app:selectedSquares()
  local vp = self.viewport
  local out = {}
  if not (vp and vp.sel and vp.grid) then return out end
  local seen = {}
  for _, e in pairs(vp.sel) do
    local k = e.tx .. "," .. e.ty
    if not seen[k] then
      seen[k] = true
      out[#out + 1] = { e.tx, e.ty }
    end
  end
  return out
end

function app:selectedTileIds()
  local ids, list = {}, {}
  local function add(t)
    if t and not ids[t] then ids[t] = true list[#list + 1] = t end
  end
  local vp = self.viewport
  if vp and vp.grid then
    for _, sq in ipairs(self:selectedSquares()) do
      add(vp.grid:tileAt(sq[1], sq[2]))
    end
  end
  if #list == 0 then
    for t in pairs(self.tileSel or {}) do add(t) end
  end
  if #list == 0 then add(self.tile) end
  table.sort(list)
  return list
end

function app:pinSelection(class)
  self.brushClass = class
  if not self.tsId then return end

  -- With the world scope set to THIS SQUARE, a class names the squares that
  -- are selected rather than the drawings under them.
  local vp = self.viewport
  local Viewport_ = require("ui.Viewport")
  local squares = self:selectedSquares()
  if vp and vp.source == "map" and vp.mapId and #squares > 0
     and Viewport_.scopeNow(vp) == "place" then
    self:record("map", vp.mapId, "class on " .. #squares .. " square(s)")
    for _, sq in ipairs(squares) do
      Doc.setMapEdit(self.doc, vp.mapId, sq[1], sq[2], { art = class })
      Viewport_.placeChanged(vp, sq[1], sq[2])
    end
    self:commitEdit()
    self.shapeCache = {}
    self:say(("%d square(s) are now %s -- here only"):format(#squares, class))
    return
  end

  local targets = self:selectedTileIds()
  self:record("tileset", self.tsId, "pin " .. tostring(class))
  for _, t in ipairs(targets) do Doc.pin(self.doc, self.tsId, t, class) end
  self:commitEdit()
  self:invalidate({ tiles = targets })
  self:say(("pinned %d tile%s to %s -- everywhere they are drawn")
           :format(#targets, #targets == 1 and "" or "s", class))
end

-- The same reach for a FOLD, which is the other half of "the type of
-- rendering of the voxel": the class decides what a square is, the fold
-- decides how its drawing is worn.
function app:foldSelection(fold)
  if not self.tsId then return end
  local vp = self.viewport
  local Viewport_ = require("ui.Viewport")
  local squares = self:selectedSquares()
  if vp and vp.source == "map" and vp.mapId and #squares > 0
     and Viewport_.scopeNow(vp) == "place" then
    self:record("map", vp.mapId, "fold on " .. #squares .. " square(s)")
    for _, sq in ipairs(squares) do
      Doc.setMapEdit(self.doc, vp.mapId, sq[1], sq[2],
                     { fold = fold or false })
      Viewport_.placeChanged(vp, sq[1], sq[2])
    end
    self:commitEdit()
    self.shapeCache = {}
    self:say(("%d square(s) fold as %s"):format(#squares, tostring(fold)))
    return
  end

  local targets = self:selectedTileIds()
  self:record("tileset", self.tsId, "fold")
  for _, t in ipairs(targets) do
    Doc.setFold(self.doc, self.tsId, t, fold)
    if vp then Viewport_.tileIdChanged(vp, t) end
  end
  self:commitEdit()
  self.shapeCache = {}
  self:say(("%d tile%s fold as %s"):format(#targets,
           #targets == 1 and "" or "s", tostring(fold)))
end

-- And a height, straight onto whatever is selected -- the fastest way to say
-- "all of this is a roof" without dragging each one.
-- SET A HEIGHT, AT ONE OF THREE REACHES.
--
--   "square"  the selected squares of THIS map, and nowhere else
--   "tile"    the selected DRAWINGS, everywhere they appear -- the default,
--             because "these four tiles are 68 tall" is what selecting four
--             tiles and typing a height means
--   "class"   the class those drawings resolve to, which moves every tile of
--             that class in the tileset
--
-- The default used to be `class`, silently, and that is how selecting four
-- bridge tiles and asking for 68 moved four hundred squares: the bridge
-- resolved as `ground`, and `ground` is most of a route.  Class is still
-- reachable and still useful -- "every wall in this tileset is 40" is one
-- edit -- but it is now something you choose rather than something you get.
function app:heightSelection(h, how)
  if not self.tsId then return end
  local vp = self.viewport
  local Viewport_ = require("ui.Viewport")
  local squares = self:selectedSquares()

  -- the world scope chip still forces the narrowest reach, as it always has
  if how == nil and vp and vp.source == "map"
     and Viewport_.scopeNow(vp) == "place" then
    how = "square"
  end
  how = how or "tile"

  if how == "square" then
    if not (vp and vp.source == "map" and vp.mapId and #squares > 0) then
      self:say("no squares selected -- pick some in the world first", "warn")
      return
    end
    self:record("map", vp.mapId, "height on " .. #squares .. " square(s)")
    for _, sq in ipairs(squares) do
      Doc.setMapEdit(self.doc, vp.mapId, sq[1], sq[2], { h = h, sub = false })
      Viewport_.placeChanged(vp, sq[1], sq[2])
    end
    self:commitEdit()
    self.shapeCache = {}
    self:say(("%d square(s) at %dpx -- here only"):format(#squares, h))
    return
  end

  local targets = self:selectedTileIds()
  if #targets == 0 then
    self:say("nothing selected", "warn")
    return
  end

  if how == "tile" then
    -- A PER-TILE HEIGHT TOUCHES NO CLASS AND NO PIN, so nothing downstream of
    -- the profile is rebuilt and the map does not have to be measured again.
    -- It is the cheapest edit in the tool as well as the narrowest.
    self:record("tileset", self.tsId, "tile height")
    for _, t in ipairs(targets) do
      Doc.setTileHeight(self.doc, self.tsId, t, h)
      if vp then Viewport_.tileIdChanged(vp, t) end
    end
    self:commitEdit()
    self.shapeCache = {}
    self:say(("%d tile%s at %dpx -- everywhere %s drawn"):format(#targets,
             #targets == 1 and "" or "s", h,
             #targets == 1 and "it is" or "they are"))
    return
  end

  -- class
  local classes, order = {}, {}
  for _, t in ipairs(targets) do
    local shape = app.shapeOf(t)
    local class = shape and shape.class
    if class and not classes[class] then
      classes[class] = true
      order[#order + 1] = class
    end
  end
  if #order == 0 then self:say("no class to set", "warn") return end
  self:record("tileset", self.tsId, "class height")
  for _, class in ipairs(order) do
    Doc.setHeight(self.doc, self.tsId, class, h)
  end
  self:commitEdit()
  -- A CLASS HEIGHT REACHES FURTHER THAN THE SELECTION, so the narrow
  -- invalidation would be a lie here and this one goes wide.
  self:invalidate()
  local reach = 0
  if self.geom then
    reach = Doc.classReach(app.shapeOf, self.geom.count, order[1])
    for i = 2, #order do
      reach = reach + Doc.classReach(app.shapeOf, self.geom.count, order[i])
    end
  end
  self:say(("class %s now %dpx -- %d tile%s in this tileset")
           :format(table.concat(order, ", "), h, reach,
                   reach == 1 and "" or "s"), "warn")
end

-- EVERY TILE OF A CLASS GETS THIS FOLD.
--
-- The nearest expressible thing to "make this class look like a billboard".
-- A class's art mode lives in `TileShape.CLASS_INFO`, which is the mod's
-- source and not a profile key, so it cannot be said in `voxel_heights.lua`
-- at all -- but a fold on each of the class's tiles can, and does export.
function app:foldClass(class, fold)
  if not (self.tsId and self.geom and class) then return end
  local hits = {}
  for t = 0, self.geom.count - 1 do
    local sp = app.shapeOf(t)
    if sp and sp.class == class then hits[#hits + 1] = t end
  end
  if #hits == 0 then self:say("no tiles resolve as " .. class, "warn") return end
  self:record("tileset", self.tsId, "fold class " .. class)
  local Viewport_ = require("ui.Viewport")
  for _, t in ipairs(hits) do
    Doc.setFold(self.doc, self.tsId, t, fold)
    if self.viewport then Viewport_.tileIdChanged(self.viewport, t) end
  end
  self:commitEdit()
  self.shapeCache = {}
  self:say(("%d tile%s of class %s now fold as %s"):format(#hits,
           #hits == 1 and "" or "s", class, tostring(fold)), "warn")
end

function app:makeObjectFromSelection()
  local vp = self.viewport
  if not vp then return end
  require("ui.Viewport").makeObject(vp, self)
end

-- ----------------------------------------------------------- band art

-- HOW MANY BANDS A DRAWING EXPOSES.  A face 8 pixels tall is one band, so a
-- tile standing 40px above its lowest neighbour shows five.  This is what the
-- painter lists, and it is a fact about the SHAPE, not about the art.
function app:bandCount(tile)
  local sp = app.shapeOf(tile)
  local h = (sp and sp.h) or 0
  return math.max(0, math.ceil(h / 8))
end

-- PAINT ONE BAND, or all of them.
--
-- `band` is the band index; -1 means "every band that has no entry of its
-- own", which is the one-click fill for a plain wall.  `src` nil clears it.
function app:paintBand(tile, band, src)
  if not (self.tsId and tile) then return end
  self:record("tileset", self.tsId, "band art")
  Doc.setBand(self.doc, self.tsId, tile, band, src)
  self:commitEdit()
  self.shapeCache = {}
  if self.viewport then
    require("ui.Viewport").tileIdChanged(self.viewport, tile)
  end
end

-- A GUESS AT THE RIGHT SIDE ART, which is what "paints in the correct tiles"
-- has to mean when the tool has no way to know what a drawing is of.
--
-- Three rules in order, each of them something an artist actually did when
-- these tilesets were drawn:
--
--   1. THE TILE BELOW IT IN ITS OWN CELL.  A 16x16 cell is 2x2 tiles and the
--      bottom row of a cell is, overwhelmingly, the face you see when the
--      thing stands up -- the cliff face under the cliff top, the wall under
--      the roof.  On a Gen 1 tileset with 8px cells there is no below and
--      this rule does not fire.
--   2. WHAT THE MAP DRAWS SOUTH OF IT.  If this square has a neighbour to the
--      south whose drawing the mod already answers as a wall-like class, that
--      neighbour IS the face -- the map is showing you the answer.
--   3. THE TILESET'S OWN COMMONEST WALL.  Failing everything else, the tile
--      most often resolved as a wall class is a better wall than a smear of
--      grass on its end.
--
-- It is a heuristic and the panel says so.  Every band it fills stays
-- editable, because a guess you cannot correct is worse than no guess.
local WALLISH = { wall = true, cliff = true, ledge = true, building = true,
                  fence = true, counter = true, bookcase = true,
                  stair = true, bridge = true }

function app:guessBandTile(tile, tx, ty)
  local geom = self.geom
  if not geom then return nil end

  -- 1. the tile below it inside its own 16x16 cell
  local perRow = geom.perRow or 16
  local cellTiles = (self.ts and tonumber(self.ts.blockTiles)) or 4
  if cellTiles >= 4 then
    local below = tile + perRow
    if below < geom.count then
      local sp = app.shapeOf(below)
      -- only if it is a DIFFERENT drawing doing a different job; a tile whose
      -- neighbour below resolves the same way has told us nothing
      if sp and sp.class ~= (app.shapeOf(tile) or {}).class then
        return below, "the tile below it in its own cell"
      end
    end
  end

  -- 2. what the map draws south of this square
  local vp = self.viewport
  if tx and ty and vp and vp.grid then
    local south = vp.grid:tileAt(tx, ty + 1)
    if south and south ~= tile then
      local sp = app.shapeOf(south)
      if sp and WALLISH[sp.class] then
        return south, "the tile the map draws south of it"
      end
    end
  end

  -- 3. the tileset's commonest wall-like drawing
  if self.commonWallFor ~= self.tsId then
    local best, bestN = nil, 0
    local tally = {}
    for t = 0, geom.count - 1 do
      local sp = app.shapeOf(t)
      if sp and WALLISH[sp.class] then
        tally[sp.class] = (tally[sp.class] or 0) + 1
        if tally[sp.class] > bestN then bestN = tally[sp.class] best = t end
      end
    end
    self.commonWall = best
    self.commonWallFor = self.tsId
  end
  if self.commonWall then
    return self.commonWall, "the tileset's commonest wall drawing"
  end
  return nil
end

-- Fill every exposed band of the selected drawings with the guess.
function app:autoFillBands()
  local targets = self:selectedTileIds()
  if #targets == 0 then self:say("nothing selected", "warn") return end
  local vp = self.viewport
  local sq = self:selectedSquares()
  local tx, ty = sq[1] and sq[1][1], sq[1] and sq[1][2]

  self:record("tileset", self.tsId, "auto band art")
  local filled, why = 0, nil
  for _, t in ipairs(targets) do
    local src, reason = self:guessBandTile(t, tx, ty)
    if src then
      why = why or reason
      -- band -1 is the fallback for every band, so one entry dresses the
      -- whole wall however tall it turns out to be
      Doc.setBand(self.doc, self.tsId, t, -1, src)
      filled = filled + 1
      if vp then require("ui.Viewport").tileIdChanged(vp, t) end
    end
  end
  self:commitEdit()
  self.shapeCache = {}
  if filled == 0 then
    self:say("no wall-like drawing to fill these faces with -- pick one from"
             .. " the sheet instead", "warn")
  else
    self:say(("filled the side faces of %d tile%s from %s"):format(filled,
             filled == 1 and "" or "s", tostring(why)))
  end
end

-- ------------------------------------------------------------- doc + export

function app:docPath()
  return Fs.join(self.paths.saveDir or ".", "voxel_editor_doc.lua")
end

function app:saveDoc()
  local ok, err = Fs.write(self:docPath(), Doc.serialise(self.doc))
  if ok then
    self.doc._dirty = false
    self:say("saved " .. self:docPath(), "good")
  else
    self:say("save failed: " .. tostring(err), "bad")
  end
end

function app:loadDoc()
  if not Fs.exists(self:docPath()) then return end
  local v = Fs.loadLua(self:docPath())
  if type(v) == "table" then
    self.doc = Doc.adopt(v)
    self:say("loaded authoring from " .. self:docPath())
    self:invalidate()
  end
end

function app:exportDir()
  local d = Fs.join(self.paths.saveDir or ".", "exports")
  Fs.mkdirp(d)
  return d
end

function app:exportProfile(full)
  local src = Export.profileLua(self.bridge, self.doc, { full = full })
  local path = Fs.join(self:exportDir(),
      full and "voxel_heights_full.lua" or "voxel_heights_partial.lua")
  local ok, err = Fs.write(path, src)
  self:say(ok and ("wrote " .. path) or ("write failed: " .. tostring(err)),
           ok and "good" or "bad")
end

function app:installProfile()
  local root = self.bridge.roots and self.bridge.roots[1]
  if not root then self:say("no mod install to write into", "bad") return end
  local src = Export.profileLua(self.bridge, self.doc, { full = true })
  local dir = Fs.join(root, "data")
  Fs.mkdirp(dir)
  local path = Fs.join(dir, "voxel_heights.lua")
  local backup = Fs.join(dir, "voxel_heights.backup.lua")
  if Fs.exists(path) and not Fs.exists(backup) then
    local old = Fs.read(path)
    if old then Fs.write(backup, old) end
  end
  local ok, err = Fs.write(path, src)
  self:say(ok and ("installed into " .. path .. " (original kept as .backup.lua)")
              or ("install failed: " .. tostring(err)), ok and "good" or "bad")
end

function app:exportPack(withSculpts)
  local blob, plan = Export.pack(self.bridge, self.doc, { self.cache },
      { sculpts = withSculpts and true or false, priority = 150 })
  local path = Fs.join(self:exportDir(),
      (self.doc.id:gsub("[^%w_%-]", "_")) .. ".zip")
  local ok, err = Fs.write(path, blob)
  if ok then
    self:say(("wrote %s -- %d pins over %d map(s)"):format(path,
             plan.counts.pins, plan.counts.maps), "good")
    for _, n in ipairs(plan.notes) do self:say(n, "warn") end
  else
    self:say("pack failed: " .. tostring(err), "bad")
  end
end

function app:runValidate()
  self.validation = Validate.run(self.doc, { self.cache }, self.bridge)
  self.tab = "validate"
  self.docks.right = true
  self:say("validate: " .. Validate.summary(self.validation),
           self.validation.ok and "good" or "bad")
end

-- ------------------------------------------------------------------ love

function love.load(argv)
  for _, a in ipairs(argv or {}) do
    if a == "--test" or a == "-t" then
      local okAll = require("tests.selftest").run()
      love.event.quit(okAll and 0 or 1)
      return
    end
  end

  app.settings = loadSettings()
  app:fitWindow(app.settings)
  Theme.load(app.uiScale)
  app.paths = Paths.discover(app.settings.paths)
  app.bridge = ModBridge.open(app.paths.modRoots, app.paths.modId)
  app.doc = Doc.new()
  app.history = History.new()
  app.viewport = Viewport.new()

  for _, n in ipairs(app.paths.notes) do app:say(n, "warn") end
  for _, n in ipairs(app.bridge.warnings) do app:say(n, "warn") end
  if app.bridge.live then
    local n = 0
    for _ in pairs(app.bridge.classInfo) do n = n + 1 end
    app:say(("voxel mod loaded: %s %s -- %d classes"):format(
        tostring(app.bridge.modName or app.bridge.id),
        tostring(app.bridge.version or "?"), n), "good")
  end

  if #app.paths.cacheRoots > 0 then app:openCache(1) end
  app:loadDoc()
end

function love.update(dt)
  Viewport.update(app.viewport, app, dt)
end

local clicked = false
local wheel = 0

function love.mousepressed(_, _, button)
  if button == 1 then clicked = true end
  app._pressed = button
end

function love.mousereleased(_, _, button)
  Viewport.mousereleased(app.viewport, app, button)
  -- a brush stroke ends when the button comes up, and the next one is its own
  -- undo step
  if button == 1 then app:commitEdit() end
end

function love.wheelmoved(_, dy) wheel = dy end
function love.textinput(t) W.state.typed = W.state.typed .. t end

function love.keypressed(key)
  if W.state.typing then
    -- RETURN COMMITS, ESCAPE ABANDONS, and the field has to be able to tell
    -- the two apart -- otherwise typing a height and pressing enter is
    -- indistinguishable from typing one and giving up.  The field clears
    -- `submitted` when it reads it.
    if key == "return" or key == "kpenter" then
      W.state.submitted = W.state.typing
    elseif key == "escape" then
      W.state.typing = nil
      W.state.submitted = nil
    end
    if key == "backspace" then W.state.backspace = true end
    return
  end
  if key == "f1" then app.docks.left = not app.docks.left return end
  if key == "f2" then app.docks.right = not app.docks.right return end
  if key == "f3" then app.docks.log = not app.docks.log return end
  if key == "f4" then
    app:setMode(app.mode == "map" and "tileset" or "map")
    return
  end
  if key == "f11" then
    app.docks.left = not app.docks.left
    app.docks.right = app.docks.left
    app.docks.log = app.docks.left
    return
  end
  if not love.keyboard.isDown("lctrl", "rctrl")
     and Viewport.keypressed(app.viewport, app, key) then
    return
  end
  if key == "escape" then app.sel = {} end
  local ctrl = love.keyboard.isDown("lctrl", "rctrl")
  if ctrl and key == "s" then app:saveDoc() return end
  if ctrl and key == "z" then
    if love.keyboard.isDown("lshift", "rshift") then app:redo() else app:undo() end
    return
  end
  if ctrl and key == "y" then app:redo() return end
  if key == "1" then app.tool = "pick" end
  if key == "2" then app.tool = "height" end
  if key == "3" then app.tool = "lasso" end
  if key == "4" then app.tool = "wand" end
  if key == "5" then app.tool = "erase" end
  if key == "6" then app.tool = "pane" end
  if key == "v" then app.viewport.wire = not app.viewport.wire end
  if app.tile and app.geom then
    if key == "left" then app:selectTile(math.max(0, app.tile - 1)) end
    if key == "right" then app:selectTile(math.min(app.geom.count - 1, app.tile + 1)) end
    if key == "up" then app:selectTile(math.max(0, app.tile - app.geom.perRow)) end
    if key == "down" then
      app:selectTile(math.min(app.geom.count - 1, app.tile + app.geom.perRow))
    end
  end
end

-- ------------------------------------------------------------------ chrome

local function header(x, y, w, h)
  local M = Theme.m
  W.panel(x, y, w, h)
  local narrow = w < M(900)
  W.text(narrow and "VTE" or "VOXEL TILESET EDITOR", x + M(10), y + M(4),
         Theme.text, Theme.fonts.body)

  -- THE MODE SWITCH, and it is two buttons rather than a chip in a toolbar
  -- because the last version hid map mode behind the twelfth control in a row
  -- that ran off the side of the screen, and a mode you cannot find is a mode
  -- you do not have.
  local sx = x + (narrow and M(46) or M(180))
  local mw = M(70)
  for _, m in ipairs({ { "tileset", "TILESET" }, { "map", "MAP" } }) do
    if W.button("mode" .. m[1], sx, y + M(4), mw, h - M(8), m[2],
                { on = app.mode == m[1], font = Theme.fonts.small }) then
      app:setMode(m[1])
    end
    if W.state.hot == "mode" .. m[1] then
      app.tip = m[1] == "tileset"
        and "one tile on a patch of ground -- what the drawing is, on its own"
        or "a window of a real map, edited in place and re-meshed as you drag"
    end
    sx = sx + mw + M(3)
  end
  sx = sx + M(10)

  local b = app.bridge
  if w > M(620) then
    W.text(b.live and ("host " .. tostring(b.version or "?"))
                   or "no host",
           sx, y + M(8), b.live and Theme.good or Theme.warn, Theme.fonts.small)
    sx = sx + M(110)
  end
  if w > M(900) then
    local line
    if app.mode == "map" and app.viewport and app.viewport.mapId then
      line = tostring(app.viewport.mapId) .. "  " .. tostring(app.tsId)
    elseif app.tsId then
      line = ("%s  gen %d  %d tiles"):format(app.tsId, app.gen or 1,
             app.geom and app.geom.count or 0)
    end
    if line then
      W.text(line, sx, y + M(8), Theme.dim, Theme.fonts.small)
    end
  end

  -- THE INTERFACE SCALE, ON THE TITLE BAR.
  --
  -- Buried in a settings panel it would be the one control a reader cannot
  -- reach when the interface is too big to navigate -- which is exactly when
  -- they need it.  So it lives here, where it is visible at any size.
  local bw, bh = M(20), h - M(8)
  local rx = x + w - M(10) - bw
  if W.button("scaleup", rx, y + M(4), bw, bh, "+", { font = Theme.fonts.small }) then
    app:setScale(app.uiScale + 0.05)
  end
  rx = rx - M(42)
  W.text(("%d%%"):format(math.floor(app.uiScale * 100 + 0.5)), rx + M(4),
         y + M(5), Theme.dim, Theme.fonts.small)
  rx = rx - bw - M(2)
  if W.button("scaledown", rx, y + M(4), bw, bh, "-", { font = Theme.fonts.small }) then
    app:setScale(app.uiScale - 0.05)
  end
  if W.state.hot == "scaleup" or W.state.hot == "scaledown" then
    app.tip = "interface scale -- everything, type and spacing together"
  end

  rx = rx - M(30)
  if W.button("redo", rx, y + M(4), M(26), bh, ">",
              { font = Theme.fonts.small,
                disabled = not History.canRedo(app.history) }) then
    app:redo()
  end
  rx = rx - M(28)
  if W.button("undo", rx, y + M(4), M(26), bh, "<",
              { font = Theme.fonts.small,
                disabled = not History.canUndo(app.history) }) then
    app:undo()
  end
  if W.state.hot == "undo" then
    app.tip = "undo (ctrl-Z)" ..
      (History.peek(app.history) and (" -- " .. History.peek(app.history)) or "")
  elseif W.state.hot == "redo" then
    app.tip = "redo (ctrl-shift-Z)"
  end

  rx = rx - M(52)
  if W.button("fitwin", rx, y + M(4), M(46), bh, "fit",
              { font = Theme.fonts.small }) then
    app.settings.window = nil
    app:fitWindow(app.settings)
    Theme.load(app.uiScale)
    app:say("window fitted to the desktop")
  end
  if W.state.hot == "fitwin" then
    app.tip = "resize the window to fit this screen, and pick a scale to match"
  end

  if w > M(1100) then
    local st = Doc.stats(app.doc)
    W.textRight(("%d pins  %d folds  %d cond  %d sculpts  %s")
        :format(st.pins, st.folds, st.cond, st.sculpt,
                app.doc._dirty and "UNSAVED" or "saved"),
        rx - M(12), y + M(5),
        app.doc._dirty and Theme.warn or Theme.faint, Theme.fonts.small)
  elseif app.doc._dirty then
    W.textRight("UNSAVED", rx - M(12), y + M(5), Theme.warn, Theme.fonts.small)
  end
end

local function leftDock(x, y, w, h)
  local M = Theme.m
  W.panel(x, y, w, h)
  W.beginScroll("leftdock", x + 2, y + 2, w - 4, h - 4)
  local cx, cy = x + M(8), y + M(8)
  local cw = w - M(22)
  local bh = Theme.btnH

  app.open.cache, cy = W.section("sec_cache", cx, cy, cw, "rom cache",
                                 app.open.cache,
                                 app.cache and app.cache.version or nil)
  if app.open.cache then
    local bw = (cw - M(6)) / 2
    for i, entry in ipairs(app.paths.cacheRoots) do
      local col = (i - 1) % 2
      local row = math.floor((i - 1) / 2)
      if W.button("cache" .. i, cx + col * (bw + M(6)), cy + row * (bh + M(2)),
                  bw, bh, entry.version,
                  { on = app.cacheIdx == i, font = Theme.fonts.small }) then
        app:openCache(i)
      end
    end
    cy = cy + math.ceil(#app.paths.cacheRoots / 2) * (bh + M(2)) + M(6)
  end

  if app.mode == "map" then
    app.open.maps, cy = W.section("sec_maps", cx, cy, cw, "maps",
        app.open.maps, app.viewport and app.viewport.mapId or nil)
    if app.open.maps then
      local bh2 = math.max(M(160), math.min(M(300), h * 0.42))
      cy = Panels.mapBrowser(app, cx, cy, cw, bh2) + M(6)
    end
  end

  app.open.tilesets, cy = W.section("sec_ts", cx, cy, cw, "tilesets",
      app.open.tilesets, app.cache and (#app.cache.ids .. "") or nil)
  if app.open.tilesets then
    local items = {}
    for _, id in ipairs((app.cache and app.cache.ids) or {}) do
      local e = app.doc.tilesets[id]
      local n = 0
      if e then for _ in pairs(e.pins or {}) do n = n + 1 end end
      items[#items + 1] = { label = id, value = id,
        sub = n > 0 and (n .. " pins")
              or ("g" .. Cache.generationOf(app.cache.tilesets[id])),
        subColor = n > 0 and Theme.accent or Theme.faint }
    end
    local rowH = Theme.rowH
    local lh = math.min(M(240), math.max(M(80), #items * rowH + M(8)))
    local chosen = W.list("tslist", cx, cy, cw, lh, items, app.tsId,
                          { rowH = rowH, font = Theme.fonts.small })
    if chosen and chosen ~= app.tsId then app:selectTileset(chosen) end
    cy = cy + lh + M(6)
  end

  app.open.sheet, cy = W.section("sec_sheet", cx, cy, cw, "sheet",
                                  app.open.sheet)
  if app.open.sheet then
    local sh = math.min(M(320), cw * 1.5)
    Panels.sheet(app, cx, cy, cw, sh)
    cy = cy + sh + M(6)
  end

  app.open.export, cy = W.section("sec_export", cx, cy, cw, "export",
                                   app.open.export)
  if app.open.export then
    app.doc.name = W.field("docname", cx, cy, cw, bh + M(1), app.doc.name,
                           "pack name")
    cy = cy + bh + M(5)
    app.doc.id = W.field("docid", cx, cy, cw, bh + M(1), app.doc.id, "PACK_ID")
    cy = cy + bh + M(7)
    local rows = {
      { "expprof", "profile .lua (changed only)", function() app:exportProfile(false) end,
        "the tilesets you touched, to merge into a fork by hand" },
      { "expfull", "profile .lua (full, drop-in)", function() app:exportProfile(true) end,
        "the whole profile, ready to replace the mod's own" },
      { "install", "install into this mod", function() app:installProfile() end,
        "write it straight into the install that actually runs, keeping the original as .backup.lua" },
      { "exppack", "pack .zip (shareable)", function() app:exportPack(false) end,
        "an installable mod that states its pins the way a SECOND mod has to: on the maps, where the runtime reads them" },
      { "exppacks", "pack .zip + sculpts", function() app:exportPack(true) end,
        "as above plus per-texel sculpts, written square by square" },
    }
    for _, r in ipairs(rows) do
      if W.button(r[1], cx, cy, cw, bh + M(1), r[2],
                  { font = Theme.fonts.small }) then
        r[3]()
      end
      if W.state.hot == r[1] then W.state.tip = r[4] end
      cy = cy + bh + M(4)
    end
    cy = cy + M(4)
    local half = (cw - M(6)) / 2
    if W.button("validate", cx, cy, half, bh + M(1), "validate",
                { font = Theme.fonts.small }) then app:runValidate() end
    if W.button("savedoc", cx + half + M(6), cy, half, bh + M(1), "save work",
                { font = Theme.fonts.small }) then app:saveDoc() end
    cy = cy + bh + M(5)
  end

  W.endScroll("leftdock", x + 2, y + 2, w - 4, h - 4, cy)
end

local function rightDock(x, y, w, h)
  local M = Theme.m
  W.panel(x, y, w, h)
  W.beginScroll("rightdock", x + 2, y + 2, w - 4, h - 4)
  local cx, cy = x + M(8), y + M(8)
  local cw = w - M(22)
  local bh = Theme.btnH

  app.open.canvas, cy = W.section("sec_canvas", cx, cy, cw, "tile",
      app.open.canvas,
      app.tile and ("$" .. string.format("%02X", app.tile)) or nil)
  if app.open.canvas then
    local ch = cw + M(70)
    Panels.tileCanvas(app, cx, cy, cw, ch)
    cy = cy + ch + M(6)
    -- THE BRUSHES LIVE WITH THE CANVAS THEY PAINT ON.  They used to be a tab
    -- of their own, one click away from the thing they act on, which is
    -- exactly the arrangement this rebuild is undoing.
    local bph = M(150)
    Panels.toolbar(app, cx, cy, cw, bph)
    cy = cy + bph + M(6)
  end

  -- FOUR TABS.
  --
  -- There were eight, each a different layout, most of them empty most of the
  -- time, and the setting you wanted in whichever one you were not looking
  -- at.  `edit` is now one scrolling column of collapsible sections covering
  -- everything about the selection -- shape, faces, class, rules, objects,
  -- and every other profile key, generated.  The three that remain are the
  -- ones a generic editor would be WORSE at: a building template is a shape
  -- with named parts, the detector tab reports rather than edits, and the
  -- report is a report.
  local tabs = { { "edit", "edit" },
                 { "buildings", "buildings" }, { "detector", "detector" },
                 { "validate", "report" } }
  local KNOWN = { edit = true, buildings = true, detector = true,
                  validate = true }
  if not KNOWN[app.tab] then app.tab = "edit" end
  local perRow = (cw >= M(300)) and math.min(#tabs, 5) or 3
  local tw = (cw - (perRow - 1) * M(3)) / perRow
  for i, t in ipairs(tabs) do
    local col = (i - 1) % perRow
    local row = math.floor((i - 1) / perRow)
    if W.button("tab" .. t[1], cx + col * (tw + M(3)), cy + row * (bh + M(2)),
                tw, bh, t[2],
                { on = app.tab == t[1], font = Theme.fonts.small }) then
      app.tab = t[1]
    end
  end
  cy = cy + math.ceil(#tabs / perRow) * (bh + M(2)) + M(4)

  -- THE EDIT PANEL SIZES ITSELF.  Sections collapse, so its height is a fact
  -- about what is open rather than a number to pick; the three that remain
  -- are framed panels of a fixed size, as they were.
  local ph = M(430)
  if app.tab == "edit" then
    cy = Inspector.draw(app, cx, cy, cw) + M(6)
  else
    if app.tab == "buildings" then Panels.buildings(app, cx, cy, cw, ph)
    elseif app.tab == "detector" then Panels.detector(app, cx, cy, cw, ph)
    else Panels.report(app, cx, cy, cw, ph) end
    cy = cy + ph + M(6)
  end

  W.endScroll("rightdock", x + 2, y + 2, w - 4, h - 4, cy)
end

function love.draw()
  local sw, sh = love.graphics.getDimensions()
  love.graphics.setBackgroundColor(Theme.bg)
  app.tip = nil
  W.state.tip = nil
  app.hoverTile = nil
  app.hoverTexel = nil
  local n = 0
  for _ in pairs(app.tileSel or {}) do n = n + 1 end
  app.tileSelCount = n

  W.beginFrame(love.mouse.getX(), love.mouse.getY(),
               love.mouse.isDown(1), clicked, wheel)

  local M = Theme.m
  local pad = M(6)
  local hdrH = M(30)
  header(pad, pad, sw - pad * 2, hdrH)

  local top = pad + hdrH + pad
  local logH = app.docks.log and M(76) or 0
  local bodyH = sh - top - logH - pad * (logH > 0 and 2 or 1)

  -- HOW THE DOCKS GIVE WAY.
  --
  -- A narrow window has room for fewer controls, not for the same controls
  -- drawn narrower and then clipped.  So each dock has a width it is worth
  -- having at, and the moment the viewport would be squeezed below a usable
  -- size the LEFT dock goes first -- its content, the cache and tileset lists
  -- and the sheet, is reference material -- and then the right.  Nothing is
  -- ever drawn half off the screen: it is either there at a size you can use
  -- it at, or folded away with a key that brings it straight back.
  local minView = M(380)
  local lw = app.docks.left
      and math.max(M(215), math.min(M(300), math.floor(sw * 0.21))) or 0
  local rw = app.docks.right
      and math.max(M(250), math.min(M(340), math.floor(sw * 0.23))) or 0
  local function viewWidth()
    return sw - pad * 2 - lw - rw - (lw > 0 and pad or 0) - (rw > 0 and pad or 0)
  end
  app.autoHid = nil
  if viewWidth() < minView and lw > 0 then lw = 0 app.autoHid = "left" end
  if viewWidth() < minView and rw > 0 then rw = 0 app.autoHid = "both" end

  if lw > 0 then leftDock(pad, top, lw, bodyH) end
  if rw > 0 then rightDock(sw - pad - rw, top, rw, bodyH) end

  local vx = pad + (lw > 0 and (lw + pad) or 0)
  local vw = sw - pad - vx - (rw > 0 and (rw + pad) or 0)
  Viewport.draw(app.viewport, app, vx, top, vw, bodyH)

  if logH > 0 then
    local ly = top + bodyH + pad
    W.panel(pad, ly, sw - pad * 2, logH)
    love.graphics.setFont(Theme.fonts.small)
    local lineH = Theme.fonts.small:getHeight() + 1
    local lines = math.max(2, math.floor((logH - M(10)) / lineH))
    for i, m in ipairs(app.messages) do
      if i > lines then break end
      local col = m.kind == "bad" and Theme.bad or m.kind == "warn" and Theme.warn
          or m.kind == "good" and Theme.good or Theme.dim
      love.graphics.setColor(col)
      love.graphics.printf(m.text, pad + M(8), ly + M(5) + (i - 1) * lineH,
                           sw - pad * 2 - M(16))
    end
  end

  if app.autoHid then
    W.text(app.autoHid == "both"
           and "docks folded away for width -- F1 / F2 force them back"
           or "left dock folded away for width -- F1 forces it back",
           vx + M(8), top + bodyH - M(15), Theme.faint, Theme.fonts.small)
  end

  local tip = app.tip or W.state.tip
  if tip then W.tooltip(tip, W.state.mx + M(14), W.state.my + M(18)) end

  if clicked then Viewport.mousepressed(app.viewport, app, 1) end

  clicked = false
  wheel = 0
end
