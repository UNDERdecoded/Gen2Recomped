-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Run:  texlua tools/map_editor_layout_check.lua [platinum data/generated] [emerald data/generated]
--
-- The map editor's LAYOUT, measured instead of argued about.
--
-- WHY THIS CANNOT BE A UNIT TEST OF A FUNCTION. `render_offline.py`'s header
-- states the lesson this file is built on:
--
--   > The 3D viewport shipped four times without ever drawing a frame, and
--   > every one of those times the tests passed ... because both are only
--   > visible in the PICTURE.
--
-- The faults below are that class. "MODELS declares `fillsBody` and then
-- flows" is not a wrong return value anywhere -- every function in it returns
-- exactly what it means to. It is a shape: two thirds of the rectangle the
-- drawer handed over were painted by nobody, so the drawer's own plate showed
-- through as a flat band under the last stepper. The only way to see that
-- without LOVE is to drive the real layout code with a Kit that RECORDS the
-- rectangles it is asked to paint, and then assert over the rectangles. Which
-- is what this does: the stub below is a recorder, not a mock, and every panel
-- under test is the shipping file.
--
-- NO CARTRIDGE AND NO CACHE. Every fixture here is a map def built from the
-- fields the IMPORTERS emit -- a Gen 1/2 tileset with a `blocks` table, a Gen 3
-- half-bank pair with `blockTiles == 2` and a `metatileCount`, a Gen 4 layout
-- with a `behaviorCells` byte string and no tileset at all. That is deliberate:
-- a layout assertion that needs a ROM is a layout assertion nobody runs.
--
-- WHAT IT CHECKS, and each one is a fault that shipped:
--
--   1. Every panel that declares `fillsBody` paints the whole body and scrolls
--      inside it. THE SET IS DERIVED by reading the panels directory, not
--      listed here -- a list would pass a new panel that declared the flag and
--      flowed, which is precisely the bug.
--   2. Every tool the drawer offers for a generation draws something for it.
--      Measured per generation against the same panel, so "needs a selection"
--      (SCRIPTS, on every cartridge) is told apart from "nothing to edit on
--      this one" (TILES on Platinum, 3D PROPS on Crystal).
--   3. A tool withheld from a generation is withheld by the PANEL's own
--      `actsOn`, never by accident. A panel whose require failed, or a chip
--      quietly dropped, looks the same from outside as a tool that is absent
--      on purpose; this tells them apart.
--   4. The two allow-list measurements stage 1 was asked to take, pinned
--      whichever way they came out: `MapEdits` has no field for a Gen 3
--      metatile ATTRIBUTE and none for a Gen 4 BEHAVIOUR byte, so an edit of
--      either is written and dropped -- the removed `mat` field's exact fate.
--      When stage 4 or 5 adds one, this check fails and says so, which is the
--      point: the finding is pinned, not assumed.

package.path = "tools/save-editor/?.lua;" .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then
    PASS = PASS + 1
  else
    FAIL = FAIL + 1
    print("FAIL: " .. label)
  end
end

-- ---------------------------------------------------------------------------
-- the recording Kit
-- ---------------------------------------------------------------------------

-- Every call that puts ink on the screen records its rectangle. Two sources,
-- because the panels use both: Kit's widgets, and `love.graphics` directly
-- (the tile palette draws its swatches that way, and so does every rail).
local REC = { rects = {}, empties = 0, lastEmpty = nil, clips = {} }
local function noop() end

-- THE RECORDER HONOURS THE CLIP STACK, and the first cut did not -- which cost
-- a plant. Shrinking a `fillsBody` panel's region to a third of the body left
-- two thirds of it bare on screen and this check passed, because the panel's
-- content rows were recorded at the coordinates it ASKED to paint them,
-- including the ones LOVE would have scissored away. A row drawn outside its
-- clip is not on screen, so counting it as coverage measures the layout code's
-- intention rather than the picture -- the exact mistake `render_offline.py`
-- exists to stop. Every rectangle is intersected with the clip in force.
local function put(src, x, y, w, h)
  if type(x) ~= "number" or type(y) ~= "number" then return end
  w, h = tonumber(w) or 8, tonumber(h) or 8
  local clip = REC.clips[#REC.clips]
  if clip then
    local x0 = math.max(x, clip.x)
    local y0 = math.max(y, clip.y)
    local x1 = math.min(x + w, clip.x + clip.w)
    local y1 = math.min(y + h, clip.y + clip.h)
    -- Entirely scissored away: it is not on screen, so it is not coverage.
    if x1 <= x0 or y1 <= y0 then return end
    x, y, w, h = x0, y0, x1 - x0, y1 - y0
  end
  REC.rects[#REC.rects + 1] = { x = x, y = y, w = w, h = h, src = src }
end

local G = {}
G.rectangle = function(mode, x, y, w, h) put("love.rect", x, y, w, h) end
G.draw = function(img, q, x, y) put("love.draw", x, y, 16, 16) end
G.newQuad = function() return {} end
G.getWidth = function() return 1280 end
G.getHeight = function() return 720 end
love = {
  graphics = setmetatable(G, { __index = function() return noop end }),
  timer = { getTime = function() return 0 end },
  mouse = { getPosition = function() return -1, -1 end,
            isDown = function() return false end },
  keyboard = { isDown = function() return false end },
  window = setmetatable({}, { __index = function() return noop end }),
  system = { getOS = function() return "Linux" end },
  -- DELIBERATELY NO `love.filesystem`. `MapEdits.load` reads the save
  -- directory through it, so leaving it nil is what keeps this check from
  -- touching anyone's real edit store.
  filesystem = nil,
}

local Kit = { scale = 1, blockClicks = false, blockRect = nil,
              mouseClicked = false, focus = nil, time = 0, wheelY = 0 }
local function box(src)
  return function(x, y, w, h) put(src, x, y, w, h); return false end
end
Kit.card = box("card")
Kit.row = box("row")
Kit.meter = box("meter")
Kit.button = box("button")
Kit.chip = box("chip")
Kit.stepper = box("stepper")
Kit.press = box("press")
Kit.checkbox = box("checkbox")
Kit.emptyBox = function(x, y, w, h, message)
  put("emptyBox", x, y, w, h)
  REC.empties = REC.empties + 1
  REC.lastEmpty = tostring(message)
  return false
end
Kit.textfield = function(id, x, y, w, h, v) put("textfield", x, y, w, h); return v or "" end
Kit.textarea = function(id, x, y, w, h, v) put("textarea", x, y, w, h); return v or "" end
Kit.textareaValue = function() return nil end
Kit.text = function(n, s, x, y) put("text", x, y, 8, 12) end
Kit.textRight = function(n, s, x, y) put("text", x, y, 8, 12) end
Kit.textCenter = function(n, s, x, y, w) put("text", x, y, w or 8, 12) end
Kit.caption = function(x, y) put("caption", x, y, 8, 16) end
Kit.textHeight = function() return 14 end
Kit.textWidth = function(n, s) return #tostring(s or "") * 6 end
Kit.captionWidth = function(s) return #tostring(s or "") * 8 end
Kit.ellipsize = function(n, s) return tostring(s or "") end
Kit.wrap = function(n, s) return { tostring(s or "") } end
Kit.safeText = function(s) return tostring(s or "") end
-- `pushClip` is recorded but NOT counted as paint: a clip reserves a region,
-- it does not fill one, and counting it would let a panel satisfy the coverage
-- test by clipping to a rectangle it then leaves blank.
-- `pushClip` NESTS, as the real one does: an inner clip can only shrink the
-- region, never widen it, so a panel cannot escape its own scissor by pushing
-- a bigger rectangle inside a smaller one.
Kit.pushClip = function(x, y, w, h)
  put("pushClip", x, y, w, h)
  local outer = REC.clips[#REC.clips]
  local r = { x = x or 0, y = y or 0, w = w or 0, h = h or 0 }
  if outer then
    local x0 = math.max(r.x, outer.x)
    local y0 = math.max(r.y, outer.y)
    r = { x = x0, y = y0,
          w = math.max(0, math.min(r.x + r.w, outer.x + outer.w) - x0),
          h = math.max(0, math.min(r.y + r.h, outer.y + outer.h) - y0) }
  end
  REC.clips[#REC.clips + 1] = r
end
Kit.popClip = function()
  REC.clips[#REC.clips] = nil
end
Kit.hit = function() return true end
Kit.hover = function() return false end
Kit.tapAway = function() return false end
Kit.forgetModal = noop
Kit.blur = noop
Kit.pager = function() return 0 end
Kit.scroll = function(x, y, w, h, o) put("scroll", x, y, w, h); return o or 0 end
Kit.beginFrame = noop
Kit.endFrame = noop
Kit.layout = noop
Kit.pointerBlocked = function() return false end

local function reset()
  REC.rects, REC.empties, REC.lastEmpty, REC.clips = {}, 0, nil, {}
end

local BODY_W, BODY_H = 400, 600

-- COVERAGE IS MEASURED OVER THE CONTENT COLUMN, NOT THE WHOLE WIDTH, and the
-- first cut of this file got that wrong in a way worth recording: removing the
-- one line of `BodyFill.region` that paints the region -- the whole black-bar
-- fix -- changed the md5 and failed nothing, because the region's own SCROLL
-- RAIL is a 6 px tall-as-the-body rectangle down the right edge, and a band
-- measured across the full width is covered by it from top to bottom. A rail
-- is not content. So the band is looked for in the left 85 per cent, which is
-- where a reader would see one.
local COL_W = BODY_W * 0.85
local STEP = 2

-- The widest horizontal band of the content column that no recorded rectangle
-- overlaps.
local function worstGap()
  local worst, at, run = 0, nil, nil
  local yy = 0
  while yy < BODY_H do
    local covered = false
    for i = 1, #REC.rects do
      local r = REC.rects[i]
      if r.src ~= "pushClip" and r.y < yy + STEP and r.y + r.h > yy
         and r.x < COL_W and r.x + r.w > 0 then
        covered = true
        break
      end
    end
    if not covered then
      if run then run[2] = yy + STEP else run = { yy, yy + STEP } end
    elseif run then
      if run[2] - run[1] > worst then worst, at = run[2] - run[1], run end
      run = nil
    end
    yy = yy + STEP
  end
  if run and run[2] - run[1] > worst then worst, at = run[2] - run[1], run end
  return worst, at
end

local function lowestPainted()
  local m = -1
  for i = 1, #REC.rects do
    local r = REC.rects[i]
    if r.src ~= "pushClip" and r.x < COL_W and r.x + r.w > 0 then
      m = math.max(m, r.y + r.h)
    end
  end
  return m
end

-- WHERE things were painted, as one comparable string: two draws that differ
-- only in scroll offset produce different fingerprints, which is how "it
-- scrolls" becomes a measurement rather than "it has a wheelmoved".
local function fingerprint()
  local t = {}
  for i = 1, #REC.rects do
    local r = REC.rects[i]
    t[#t + 1] = ("%s@%d,%d"):format(r.src, math.floor(r.x), math.floor(r.y))
  end
  table.sort(t)
  return table.concat(t, ";")
end

-- A WHOLE-BODY EMPTY BOX AND NOTHING ELSE: the panel drew its "nothing here"
-- placeholder across the rectangle and painted no control at all. That is the
-- shape of a tab that opens an empty panel.
local function drewNothing()
  local bigEmpty, other = false, 0
  for i = 1, #REC.rects do
    local r = REC.rects[i]
    if r.src == "emptyBox" and r.w >= BODY_W * 0.9 and r.h >= BODY_H * 0.9 then
      bigEmpty = true
    elseif r.src ~= "pushClip" then
      other = other + 1
    end
  end
  return bigEmpty and other == 0
end

-- ---------------------------------------------------------------------------
-- the fixtures: one map per generation, from what the importers emit
-- ---------------------------------------------------------------------------

local Loader = require("src.world.MapLoader")
Loader.evict = noop
local realResolve = Loader.resolveBlocks

local function gen2Tileset()
  local blocks = {}
  for i = 1, 64 do
    local b = {}
    for k = 1, 16 do b[k] = k - 1 end
    blocks[i] = b
  end
  local coll = {}
  for i = 1, 256 do coll[i] = 1 end
  return { id = "TilesetJohto", blocks = blocks, collision = coll,
           tilesPerRow = 16 }
end

-- A Gen 3 half-bank PAIR record, as RomExtractorGen3 emits one
-- (`blockTiles = 2`, `blockCells = 1`, `metatileCount`, `collision`) -- the
-- shape `Tiles.blockCount` and `MapCollision` both read.
local function gen3Tileset()
  local coll = {}
  for i = 1, 736 * 4 do coll[i] = 1 end
  return { id = "TILESET_PAIR", blockTiles = 2, blockCells = 1,
           metatileCount = 736, collision = coll, attributes = string.rep("\0", 736 * 2) }
end

local FIXTURES = {}

FIXTURES[1] = { label = "gen 1/2 (Crystal)", generation = 2, build = function()
  local def = { id = "ROUTE_29", generation = 2, width = 10, height = 9,
                tileset = "TilesetJohto", blocks = {},
                objects = { { index = 1, sprite = "SPRITE_GRAMPS", x = 1, y = 1 } },
                warps = {} }
  for i = 1, 90 do def.blocks[i] = 0 end
  return { version = "crystal", mapId = "ROUTE_29", pvCell = { cx = 2, cy = 2 },
           data = { maps = { ROUTE_29 = def },
                    tilesets = { TilesetJohto = gen2Tileset() },
                    constants = {}, sprites = {}, trainers = {} },
           mapEdits = { games = {} } }, def
end }

FIXTURES[2] = { label = "gen 3 (Emerald)", generation = 3, build = function()
  local def = { id = "ROUTE_101", generation = 3, width = 20, height = 20,
                tileset = "TILESET_PAIR", blocks = string.rep("\7\0", 400),
                objects = { { index = 1, sprite = "SPRITE_GRAMPS", x = 1, y = 1 } },
                warps = {} }
  return { version = "emerald", mapId = "ROUTE_101", pvCell = { cx = 2, cy = 2 },
           data = { maps = { ROUTE_101 = def },
                    tilesets = { TILESET_PAIR = gen3Tileset() },
                    constants = {}, sprites = {}, trainers = {} },
           mapEdits = { games = {} } }, def
end }

-- THE GEN 4 MAP CARRIES A TILESET, AND THE FIRST VERSION OF THIS FIXTURE DID
-- NOT -- which is why stage 1 reported a tool list the shipping editor did not
-- produce. All 593 Platinum maps name `TILESET_GEN4_STANDIN`: a synthesised
-- record (src/import/Gen4Tileset.lua:285) that reports `blockTiles = 2`,
-- `blockCells = 1`, `metatileCount = 256` and a 256-entry `collision` table,
-- and marks itself `standIn = true` because Gen 4 has no 2D tileset in the
-- cartridge. A fixture without it hands the availability rules a world in
-- which they are trivially right. Shape taken from the real cache and asserted
-- against it below, so it cannot drift again.
local function gen4StandIn()
  local coll = {}
  for i = 1, 256 do coll[i] = 1 end
  return { id = "TILESET_GEN4_STANDIN", standIn = true,
           blockTiles = 2, blockCells = 1, metatileCount = 256,
           collision = coll, primaryKey = "GEN4_STANDIN",
           image = "assets/generated/gen4/tileset/standin.png",
           behaviourBytes = true, warpsAreEvents = true,
           source = "synthesised stand-in; Gen 4 has no 2D tileset in the cartridge" }
end

FIXTURES[3] = { label = "gen 4 (Platinum)", generation = 4, build = function()
  local def = { id = "T01", generation = 4, width = 64, height = 64,
                originX = 128, originY = 736, blockPx = 16,
                tileset = "TILESET_GEN4_STANDIN",
                blocks = string.rep("\0\0", 64 * 64),
                behaviorCells = string.rep("\0", 64 * 64),
                borderBlock = 255,
                objects = { { index = 1, sprite = "SPRITE_GRAMPS", x = 1, y = 1 } },
                warps = {} }
  return { version = "platinum", mapId = "T01", pvCell = { cx = 4, cy = 4 },
           data = { maps = { T01 = def },
                    tilesets = { TILESET_GEN4_STANDIN = gen4StandIn() },
                    constants = {}, sprites = {}, trainers = {} },
           mapEdits = { games = {} } }, def
end }

-- A chunk with enough props on it that the prop list is taller than the body:
-- the scroll test needs something to scroll, and twenty is what a real Sinnoh
-- town chunk carries.
--
-- THE CHUNK MATRIX IS SIZED FROM THE DEF, not fixed at one chunk. C01's real
-- origin is (128, 736) inside the Sinnoh matrix, so the cell the fixture
-- selects lands in chunk (4, 23) -- and a one-entry grid answered nil for it,
-- which made `Models` draw its "select a cell on a rendered Platinum map" box
-- and the coverage test skip the only panel it was written for. Every chunk
-- maps to the same terrain record, which is a matrix a real import can
-- produce and is the shape `context` reads.
local function gen4Ground(def, props)
  local objects = {}
  for i = 1, (props or 20) do
    objects[i] = { model = i, x = i * 8 - 128, y = 0, z = 0,
                   scaleX = 1, scaleY = 1, scaleZ = 1 }
  end
  local CHUNK = 32
  local gw = math.ceil((((def and def.originX) or 0)
                        + ((def and def.width) or 1)) / CHUNK) + 1
  local gh = math.ceil((((def and def.originY) or 0)
                        + ((def and def.height) or 1)) / CHUNK) + 1
  local land = {}
  for i = 1, gw * gh do land[i] = 0 end
  return { grid = { land = land, width = gw },
           terrain = { chunks = { [0] = { objects = objects } } },
           buildingSet = { models = { { member = 40 } } } }
end

-- Drive one panel on one fixture. The loader is stubbed per draw, because
-- `Models` asks it for the built map and the real one wants a cache.
local function drawOn(panel, fixture, props)
  local S, def = fixture.build()
  Loader.load = function()
    local ground = (def.behaviorCells ~= nil) and gen4Ground(def, props) or nil
    return { def = def, renderer = { gen4Ground = ground },
             widthCells = def.width * 2, heightCells = def.height * 2 }
  end
  Loader.resolveBlocks = function(_, d) return d end
  reset()
  local ok, err = pcall(panel.draw, S, Kit, 0, 0, BODY_W, BODY_H)
  Loader.resolveBlocks = realResolve
  return ok, err, S, def
end

-- ---------------------------------------------------------------------------
-- 1. the panels, DERIVED from the directory
-- ---------------------------------------------------------------------------

local function panelFiles()
  local dir = "tools/map-editor/panels"
  local out = {}
  local okLfs, lfs = pcall(require, "lfs")
  if okLfs and lfs and lfs.dir then
    for entry in lfs.dir(dir) do
      if entry:match("%.lua$") then out[#out + 1] = entry:sub(1, -5) end
    end
  elseif love and love.filesystem and love.filesystem.getDirectoryItems then
    for _, entry in ipairs(love.filesystem.getDirectoryItems(dir)) do
      if entry:match("%.lua$") then out[#out + 1] = entry:sub(1, -5) end
    end
  elseif io.popen then
    local pipe = io.popen("ls " .. dir)
    if pipe then
      for line in pipe:lines() do
        if line:match("%.lua$") then out[#out + 1] = line:sub(1, -5) end
      end
      pipe:close()
    end
  end
  table.sort(out)
  return out
end

local FILES = panelFiles()
-- A DERIVATION THAT FOUND NOTHING IS NOT A PASS. Without this the whole first
-- section would report "every fillsBody panel is fine" on an empty list, which
-- is the shape of assertion `check_design_lessons` calls one that cannot fail.
check(#FILES >= 8, ("the panels directory enumerates at least 8 modules "
  .. "(found %d) -- the derivation of the fillsBody set depends on it")
  :format(#FILES))

local PANELS, FILLS = {}, {}
for _, name in ipairs(FILES) do
  local ok, P = pcall(require, "tools.map-editor.panels." .. name)
  if ok and type(P) == "table" then
    PANELS[name] = P
    if P.fillsBody == true and type(P.draw) == "function" then
      FILLS[#FILLS + 1] = name
    end
  end
end

-- Every panel in the directory must LOAD. A panel loads through pcall in the
-- shell and is dropped if its require fails, so a syntax error in one does not
-- break the editor -- it removes a tool, silently, which is the hardest break
-- in this tree to notice from the outside.
for _, name in ipairs(FILES) do
  check(PANELS[name] ~= nil,
    ("panels/%s.lua loads -- a panel whose require fails is dropped by the "
     .. "shell, so a break here shows up as a MISSING TOOL"):format(name))
end

check(#FILLS >= 2, ("at least two panels declare fillsBody (found %d): TILES "
  .. "has always, and MODELS was the one that declared it and flowed")
  :format(#FILLS))

-- ---------------------------------------------------------------------------
-- 2. a fillsBody panel fills the body, and scrolls inside it
-- ---------------------------------------------------------------------------

-- SLACK, and why it is this size. Ordinary row spacing leaves 4-8 px gaps
-- between controls and those are not holes. The fault being measured left
-- 232 px of a 600 px body unpainted, so the threshold has two orders of
-- headroom either way: a gap wider than 48 px is a band, not a gutter.
local GAP_SLACK = 48
-- The FOOT gets the same slack as any other band, and it has to: a palette
-- lays whole rows, so the last row's bottom lands wherever the row height
-- divides -- TILES on a 600 px body ends at y=574, a 26 px gutter that is
-- arithmetic rather than a hole. Measured against 24 it failed; the fault this
-- is looking for was 232 px, which is five times the threshold either way.
local FOOT_SLACK = GAP_SLACK

for _, name in ipairs(FILLS) do
  local panel = PANELS[name]
  local anyDrew, scrolled = false, false
  for _, fixture in ipairs(FIXTURES) do
    local ok, err = drawOn(panel, fixture)
    check(ok, ("%s.draw does not raise on a %s map (%s)")
      :format(name, fixture.label, tostring(err)))
    if ok and not drewNothing() then
      anyDrew = true
      local gap, at = worstGap()
      local low = lowestPainted()
      -- THE BLACK BAR, AS AN INVARIANT. A panel that says `fillsBody` is handed
      -- the body exactly -- no virtual page, no outer scroll, no outer rail --
      -- so anything it does not paint is painted by nobody and shows as a band
      -- of the drawer's own plate.
      check(gap <= GAP_SLACK,
        ("%s declares fillsBody and leaves a %dpx band of a %dpx body "
         .. "unpainted on a %s map (y=%d..%d). A fillsBody panel is handed the "
         .. "body exactly: whatever it does not paint, nobody does, and it "
         .. "shows as a bar. Hand the remaining rectangle to BodyFill.region.")
        :format(name, gap, BODY_H, fixture.label,
                at and at[1] or -1, at and at[2] or -1))
      check(low >= BODY_H - FOOT_SLACK,
        ("%s declares fillsBody but the lowest pixel it painted on a %s map is "
         .. "y=%d of %d -- the %dpx under it is unpainted drawer, which is the "
         .. "black bar. BodyFill.region paints the rectangle it is given.")
        :format(name, fixture.label, low, BODY_H, BODY_H - low))

      -- AND IT MUST SCROLL ITSELF. `fillsBody` suppresses the OUTER scroll, so
      -- a panel that overflows without an inner one has rows that are
      -- visible-but-cut and reachable from neither scrollbar -- which is the
      -- tile palette "going past the bottom of the screen".
      --
      -- ONE STATE, DRAWN TWICE, WITH A NOTCH IN BETWEEN -- not two fixtures.
      -- A panel's scroll offset lives on `S`, so the wheel has to be fed to
      -- the same `S` that is then redrawn; rebuilding the fixture would hand
      -- the second draw a fresh offset of zero and the comparison would say
      -- "it scrolled" about nothing.
      if type(panel.wheelmoved) == "function" then
        local S, def = fixture.build()
        Loader.load = function()
          local ground = (def.behaviorCells ~= nil) and gen4Ground(def, nil) or nil
          return { def = def, renderer = { gen4Ground = ground },
                   widthCells = def.width * 2, heightCells = def.height * 2 }
        end
        Loader.resolveBlocks = function(_, d) return d end
        reset()
        local okFirst = pcall(panel.draw, S, Kit, 0, 0, BODY_W, BODY_H)
        local first = fingerprint()
        pcall(panel.wheelmoved, S, -4)
        reset()
        local okAfter = pcall(panel.draw, S, Kit, 0, 0, BODY_W, BODY_H)
        Loader.resolveBlocks = realResolve
        if okFirst and okAfter and fingerprint() ~= first then
          scrolled = true
        end
      end
    end
  end
  check(anyDrew, ("%s declares fillsBody and draws real controls for at least "
    .. "one generation -- a panel that only ever draws an empty box has no "
    .. "body to fill and should not claim the flag"):format(name))
  check(scrolled, ("%s declares fillsBody and its own wheel notch moves what "
    .. "it painted. fillsBody suppresses the OUTER scroll, so without an inner "
    .. "one anything past the body is reachable from neither scrollbar. Use "
    .. "BodyFill.region + BodyFill.wheel."):format(name))
end

-- ---------------------------------------------------------------------------
-- 3. the tool list is generation-aware, and withholding is deliberate
-- ---------------------------------------------------------------------------

local Sidebar = require("tools.map-editor.Sidebar")
check(type(Sidebar.toolsFor) == "function",
  "Sidebar.toolsFor exists -- the tool list has to be DERIVED from the map, "
  .. "or a tool that cannot act on it is offered anyway and reads as broken")
-- STOP HERE RATHER THAN CRASH. Without the derivation there is nothing below
-- to measure, and a check that dies without printing its verdict is reported
-- as an ERROR -- which reads as "the check is broken" rather than "the thing
-- it checks is gone".
if type(Sidebar.toolsFor) ~= "function" then
  print(("%d checks, %d failed"):format(PASS + FAIL, FAIL))
  os.exit(1)
end

local BY_ID = {}
for _, name in ipairs(FILES) do
  local P = PANELS[name]
  if P then BY_ID[name:lower()] = P end
end

-- The catalogue's ids against the panels the directory produced: a tool naming
-- a panel that is not there is a chip that opens "this tool is not in this
-- build".
for _, tool in ipairs(Sidebar.TOOLS) do
  check(BY_ID[tool.id] ~= nil,
    ("Sidebar.TOOLS names %q and panels/ has a module for it"):format(tool.id))
end

check(Sidebar.toolFor("models") ~= nil,
  "the catalogue carries a MODELS tool of its own. Tiles.draw used to "
  .. "delegate to Models for generation 4, which is why Gen 4 had no tile "
  .. "editor: the name was taken")

-- The Gen 4 delegation must be GONE, and the first cut of this assertion was
-- the trap `check_design_lessons` section 3e names: it searched the file for
-- the delegating sentence, and the comment that EXPLAINS the delegation is
-- gone -- which quotes the sentence -- satisfied it. So the comments come off
-- first and the match runs against CODE.
do
  local handle = io.open("tools/map-editor/panels/Tiles.lua", "rb")
  local text = handle and handle:read("*a") or ""
  if handle then handle:close() end
  check(#text > 1000, "panels/Tiles.lua is readable from the repo root")
  local code = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if not line:match("^%s*%-%-") then code[#code + 1] = line end
  end
  code = table.concat(code, "\n")
  check(code:find("function Tiles%.draw"),
    "and the comment strip left Tiles.draw's own line behind, so the match "
    .. "below is running against code rather than against nothing")
  local delegates = code:find("panels%.Models")
  check(not delegates,
    "Tiles.lua's CODE no longer names panels.Models. While Tiles.draw "
    .. "delegated to it for generation 4, the TILES tool on a Platinum map WAS "
    .. "the prop placer, so Gen 4 could never have a tile editor: the name was "
    .. "taken")
end

-- The matrix: for each fixture, which tools are offered and which panels draw
-- something. `panels` is passed as the shell passes it.
local MATRIX = {}
for f, fixture in ipairs(FIXTURES) do
  local S = fixture.build()
  S.panels = BY_ID
  local offered = {}
  for _, t in ipairs(Sidebar.toolsFor(S, BY_ID)) do offered[t.id] = true end
  local draws = {}
  for _, tool in ipairs(Sidebar.TOOLS) do
    local panel = BY_ID[tool.id]
    if panel and panel.draw then
      local ok = drawOn(panel, fixture)
      draws[tool.id] = ok and not drewNothing()
    end
  end
  MATRIX[f] = { offered = offered, draws = draws, label = fixture.label }
end

for _, tool in ipairs(Sidebar.TOOLS) do
  -- A PANEL THAT DRAWS NOTHING ANYWHERE needs a SELECTION, not a generation:
  -- SCRIPTS asks for an object on every cartridge there is. Counting that as a
  -- dead tool would make the rule unusable, so the two are told apart by
  -- whether any generation gets real controls out of it.
  local anywhere = false
  for f = 1, #FIXTURES do
    if MATRIX[f].draws[tool.id] then anywhere = true end
  end
  for f = 1, #FIXTURES do
    local m = MATRIX[f]
    if anywhere and m.offered[tool.id] then
      check(m.draws[tool.id],
        ("%s is offered on a %s map and its panel draws nothing but an empty "
         .. "box there. An inert tool reads as broken rather than absent -- "
         .. "give panels/%s.lua an actsOn that answers false for this map")
        :format(tool.title, m.label, tool.id))
    end
    -- AND THE OTHER DIRECTION. A tool can only be WITHHELD by the panel saying
    -- so. Without this, a panel whose require failed, or a chip dropped by a
    -- layout change, is indistinguishable from a tool absent on purpose.
    if anywhere and m.draws[tool.id] and not m.offered[tool.id] then
      check(type(BY_ID[tool.id].actsOn) == "function",
        ("%s is not offered on a %s map but panels/%s.lua declares no actsOn "
         .. "-- a tool must be withheld by an explicit panel predicate, never "
         .. "by accident"):format(tool.title, m.label, tool.id))
    end
  end
end

-- The measured consequence, stated so a regression names itself. These three
-- are the ones stage 1 moved, and each is backed by a consumer that does not
-- exist on Platinum: `Tiles` needs a tileset block table, `Voxels` writes
-- `def.voxelEdits` which only a voxel mod's `TileShape` reads, and
-- `MapCollision.paint` answers "this map has no tileset to edit".
local G4 = MATRIX[3].offered
check(not G4.tiles, "TILES is not offered on a Platinum map: there is no "
  .. "metatile to paint, the ground is an NSBMD mesh")
check(not G4.voxels, "VOXELS is not offered on a Platinum map: def.voxelEdits "
  .. "is read by a voxel mod's TileShape and never by Gen4Ground, so the edit "
  .. "would save, reload and change nothing")
check(not G4.collision, "WALKABLE is not offered on a Platinum map: a "
  .. "collision class lives in a tileset and MapCollision.paint refuses every "
  .. "map that has none")
check(G4.models, "3D PROPS is offered on a Platinum map")
check(G4.warps and G4.objects and G4.wilds,
  "WARPS, NPCs and WILDS are still offered on a Platinum map")

-- GEN 1/2 AND GEN 3 LOSE NOTHING. The editor is shared across four
-- generations and this is the half of the change that must not move.
for f = 1, 2 do
  local m = MATRIX[f]
  for _, id in ipairs({ "warps", "objects", "scripts", "voxels", "wilds",
                        "tiles", "collision" }) do
    check(m.offered[id], ("%s is still offered on a %s map -- the seven tools "
      .. "a block-grid cartridge has today must not move"):format(id, m.label))
  end
  check(not m.offered.models,
    ("3D PROPS is not offered on a %s map: there is no Gen 4 terrain chunk to "
     .. "put a model on"):format(m.label))
end

-- WITH NO MAP SELECTED there is nothing to derive from, so the whole set is
-- offered and the buttons say "pick a map first". A rail that fills in as you
-- pick a map is not a rail anyone can learn.
do
  local S = { data = { maps = {}, tilesets = {} }, panels = BY_ID }
  check(#Sidebar.toolsFor(S, BY_ID) == #Sidebar.TOOLS,
    "with no map selected every tool is offered -- there is nothing to derive "
    .. "availability from, and the buttons already say to pick a map")
end

-- ONE LIST, TWO NAMES. The drawer's chips spell it `id` and Preview's buttons
-- spell it `tab`; the two were separate literals and had already drifted
-- (WALKABLE was a chip with no button). Entries carry both.
do
  local S = FIXTURES[1].build()
  local list = Sidebar.toolsFor(S, BY_ID)
  local bothNames = #list > 0
  for _, t in ipairs(list) do
    if t.id == nil or t.tab ~= t.id then bothNames = false end
  end
  check(bothNames, "every offered tool carries id and tab with the same value "
    .. "-- the drawer reads one and Preview's buttons read the other, and two "
    .. "separate literals is how WALKABLE ended up a chip with no button")
  local okPrev, Preview = pcall(require, "tools.map-editor.panels.Preview")
  check(okPrev and type(Preview) == "table" and #(Preview.TOOLS or {}) == #Sidebar.TOOLS,
    "Preview.TOOLS is derived from Sidebar.TOOLS and has the same length, so "
    .. "a tool added to the catalogue gets a button without a second edit")
end

-- ---------------------------------------------------------------------------
-- 4. the allow-list measurements, pinned
-- ---------------------------------------------------------------------------

local MapEdits = require("tools.map-editor.MapEdits")

-- The one Gen 4 field that IS in the allow-list, and the reason prop edits
-- survive a reload at all.
check(MapEdits.MAP_FIELDS.gen4ModelEdits == "table",
  "MAP_FIELDS carries gen4ModelEdits -- it is the only Gen 4 field in the "
  .. "allow-list and the reason a prop edit survives")

-- STAGE 4 LANDED, SO THIS ASSERTION TURNED ROUND -- as its own last sentence
-- told the next reader to do.
--
-- It used to pin the ABSENCE of a Gen 4 behaviour field: `setMapField` was
-- refused by typedCopy and nothing was stored, so a behaviour edit would have
-- been written and dropped exactly as the removed `mat` field was. That was
-- the right thing to measure while the painter did not exist. Now that it
-- does, the same assertion held the other way would hold the tree at the old
-- answer -- shape 2d, an assertion whose subject is a to-do item has to be
-- inverted once the item is done.
--
-- What matters now is the ROUND TRIP: an edit goes in, comes back out, and
-- lands on a freshly extracted map. Measured through the real store rather
-- than by reading MAP_FIELDS, which would restate the table beside it.
do
  local store = { games = {} }
  check(MapEdits.MAP_FIELDS.behaviorCells == "string",
    "MAP_FIELDS must carry behaviorCells now that the Gen 4 ground can be "
    .. "painted -- without it a created map is given a terrain layer and "
    .. "loses it on the next round trip")
  local ok = MapEdits.setTerrain(store, "platinum", "T01", 2, 1, 21, false)
  local got, blocked = MapEdits.terrainAt(store, "platinum", "T01", 2, 1)
  check(ok and got == 21 and blocked == false,
    "a terrain edit must round-trip through the store: got "
    .. tostring(got) .. "/" .. tostring(blocked))
  -- ...and onto a freshly extracted map, which is the promise a re-import has
  -- to keep.
  local fresh = { id = "T01", width = 4, height = 2,
                  blocks = string.rep(string.char(0, 0), 8),
                  behaviorCells = string.rep(string.char(0), 8) }
  MapEdits.applyToMap(store, "platinum", "T01", fresh)
  check(fresh.behaviorCells:byte(1 * 4 + 2 + 1) == 21,
    "and must apply onto a freshly extracted map, which is what makes a ROM "
    .. "re-import non-destructive")
end

do
  local store = { games = {} }
  local kept = {}
  for _, key in ipairs({ "attr", "attribute", "attributes", "metatileAttr",
                         "metatileAttributes", "behavior", "behaviour" }) do
    MapEdits.setVoxel(store, "emerald", "ROUTE_101", 1, 1, { [key] = 36 })
    local cell = store.games.emerald and store.games.emerald.maps
                 and store.games.emerald.maps.ROUTE_101
                 and store.games.emerald.maps.ROUTE_101.voxels
                 and store.games.emerald.maps.ROUTE_101.voxels["1,1"]
    if cell and cell[key] ~= nil then kept[#kept + 1] = key end
    if MapEdits.MAP_FIELDS[key] ~= nil then kept[#kept + 1] = "map." .. key end
  end
  check(#kept == 0,
    ("STAGE 1 MEASUREMENT, PINNED: MapEdits has NO field for a Gen 3 metatile "
     .. "ATTRIBUTE under any of seven spellings -- the attribute array is "
     .. "extracted (a Gen 3 tileset record carries `attributes`, two bytes per "
     .. "metatile) but an edit of it is refused by typedCopy and dropped. "
     .. "Stage 5 must add the field with its consumer. Kept: %s")
    :format(table.concat(kept, ", ")))
end

-- AND THE GEN 3 PAINT PATH, which DOES work -- the other half of the stage 1
-- measurement, asserted so a regression in it is not read as "Gen 3 never
-- could".
do
  local Tiles = require("tools.map-editor.panels.Tiles")
  local Map = require("src.world.Map")
  local S, def = FIXTURES[2].build()
  local before = Map.blockArray(def)[1 * def.width + 1 + 1]
  local painted = Tiles.paintCell(S, 1, 1, 321, nil, nil)
  local after = Map.blockArray(def)[1 * def.width + 1 + 1]
  check(painted and before == 7 and after == 321,
    ("STAGE 1 MEASUREMENT: a Gen 3 block CAN be painted today. paintCell sees "
     .. "blockTiles == 2, routes to Tiles.paint, and writePackedBlock writes "
     .. "the 10-bit metatile id into the packed u16 string. Measured %s -> %s")
    :format(tostring(before), tostring(after)))
  check(S.mapEdits.games.emerald
        and S.mapEdits.games.emerald.maps.ROUTE_101.blocks
        and S.mapEdits.games.emerald.maps.ROUTE_101.blocks["1,1"] == 321,
    "and the Gen 3 paint is recorded in the store, so it survives a re-import")
  -- What it CANNOT do, which is the gap stage 5 inherits.
  local live, why = Tiles.usePick(S, "OTHER_PAIR", 42, nil)
  check(live == nil and type(why) == "string",
    ("STAGE 1 MEASUREMENT: Gen 3 cannot BORROW from another tileset -- "
     .. "usePick declines with %q, because borrowLive wants a `blocks` table "
     .. "and a Gen 3 pair carries a metatile count and two composited "
     .. "half-banks instead"):format(tostring(why)))
end

-- ---------------------------------------------------------------------------
-- 5. the shared helper itself
-- ---------------------------------------------------------------------------

local BodyFill = require("tools.map-editor.BodyFill")
do
  reset()
  local innerW, maxScroll = BodyFill.region({}, Kit, "probe", 0, 0,
                                            BODY_W, BODY_H, 2000, function() end)
  local gap = worstGap()
  check(gap == 0 and lowestPainted() >= BODY_H,
    ("BodyFill.region paints the whole rectangle it is handed even when the "
     .. "content callback paints nothing -- that one line is the black-bar fix "
     .. "and it has to hold for the next panel too (worst gap %dpx)"):format(gap))
  check(maxScroll == 2000 - BODY_H,
    "and reports the scroll its content needs, so wheelmoved and the rail "
    .. "agree with the region instead of each computing it")
  check(innerW < BODY_W,
    "and takes the rail's width OUT of the content width -- a rail drawn over "
    .. "the last column makes that column unclickable, which is how the tile "
    .. "palette's right-hand swatches became visible-but-unselectable")

  local S = {}
  check(BodyFill.wheel(S, "probe", -1, 0) == false,
    "BodyFill.wheel returns FALSE when there is nowhere to scroll -- taking "
    .. "every notch is what killed the drawer's own scroll on the voxel tool")
  check(BodyFill.wheel(S, "probe", -1, 500) == true
        and BodyFill.scrollOf(S, "probe") > 0,
    "and takes it when there is")
  BodyFill.wheel(S, "other", -1, 500)
  check(BodyFill.scrollOf(S, "probe") ~= nil
        and BodyFill.scrollOf(S, "other") == BodyFill.scrollOf(S, "probe"),
    "two regions in one panel keep two offsets, keyed by name")
end

-- ---------------------------------------------------------------------------
-- 6. the map VIEWPORT, and the camera that walked off the end of the map
-- ---------------------------------------------------------------------------

-- THE OTHER BLACK BAR, and the one Cedric actually reported. It is in the
-- central map viewport, not the tools drawer.
--
-- `Preview` computed the map's size in cells as `def.width * 2`,
-- `def.height * 2`. The engine derives the same number from the tileset --
-- `Map.lua:443` reads `tonumber(tilesetDef.blockCells) or 2` -- and
-- `blockCells` is 1 for a Gen 3 half-bank pair and 1 for Gen 4's stand-in,
-- because a metatile IS the cell there. So on every Gen 3 and Gen 4 map the
-- editor believed the map was twice as big as it is, and
-- `centerOn(wCells / 2, hCells / 2)` aimed the camera at the bottom-right
-- CORNER rather than the middle.
--
-- The arithmetic is exact and independent of the zoom and the viewport height:
-- with `hCells` doubled, `camY` is `worldH - window/2`, so the window is
-- `[worldH - window/2, worldH + window/2]` and the map fills exactly the top
-- HALF. Below it is the plate `Preview` paints first (`PAL.bgBot`), never
-- drawn over, because the tile batch has no quads past the end of the map.
--
-- Asserted as the arithmetic rather than as a picture, because the picture
-- needs a built Map and a GPU. `centerOn`'s formula is restated here from
-- Preview.lua:391-392; if that moves, the fixture below stops agreeing with it
-- and the restatement is what has to be re-derived.
local MapKind = require("tools.map-editor.MapKind")
local CELL = 16

local function viewportCoverage(S, def, vh, zoom)
  local wCells, hCells = MapKind.cellsOf(S, def)
  local worldH = hCells * CELL
  local window = vh / zoom
  local camY = (hCells / 2) * CELL - vh / (2 * zoom)
  local on = math.max(0, math.min(worldH, camY + window) - math.max(0, camY))
  return (window > 0) and (on / window) or 0, hCells, camY
end

-- THE STAND-IN AS A BORROW SOURCE, which is a path a reader can reach: the
-- TILES panel's FROM list offers every tileset the import carries, and in an
-- install with both Crystal and Platinum imported that list contains
-- `TILESET_GEN4_STANDIN`. Picking it must say there is nothing in it, not lay
-- out 256 swatches of a sheet that does not exist.
--
-- This is also the only observable for `blockCount`'s own stand-in guard:
-- `Tiles.actsOn` asks `MapKind.editableTileset` first and returns before
-- `blockCount` is reached on a Gen 4 map, so removing that guard changed
-- nothing measurable until this case existed. A guard with no measurement is a
-- guard that rots.
do
  local Tiles = require("tools.map-editor.panels.Tiles")
  local S, def = FIXTURES[1].build()         -- a Crystal map...
  local g4 = FIXTURES[3].build()
  local standIn = g4.data.tilesets.TILESET_GEN4_STANDIN
  S.data.tilesets.TILESET_GEN4_STANDIN = standIn   -- ...with Platinum imported
  S.tileSource = "TILESET_GEN4_STANDIN"            -- ...and the stand-in picked
  check(Tiles.actsOn(S, def) == true,
    "the Crystal map is still editable with a foreign stand-in merely present "
    .. "in the tileset list -- availability is about the MAP's tileset")
  reset()
  local ok = pcall(Tiles.draw, S, Kit, 0, 0, BODY_W, BODY_H)
  check(ok, "TILES draws with the Gen 4 stand-in selected as the FROM tileset")
  local swatches = 0
  for i = 1, #REC.rects do
    if REC.rects[i].src == "press" then swatches = swatches + 1 end
  end
  check(swatches == 0,
    ("with the Gen 4 stand-in picked as the source, the palette offers no "
     .. "swatches (offered %d). It reports metatileCount = 256 and has no "
     .. "`blocks` table at all, so every one of those would be a click on a "
     .. "picture that cannot be built"):format(swatches))
end

-- AND THE VIEWPORT MUST ACTUALLY USE THE DERIVATION. The assertion above
-- grades `MapKind.cellsOf`; this one grades the call site, because a correct
-- helper nobody calls is the shape of a fix that is not applied. Comments are
-- stripped first for the reason the Tiles assertion above explains: the
-- comment that records the old `* 2` quotes it.
do
  local handle = io.open("tools/map-editor/panels/Preview.lua", "rb")
  local text = handle and handle:read("*a") or ""
  if handle then handle:close() end
  check(#text > 1000, "panels/Preview.lua is readable from the repo root")
  local code = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if not line:match("^%s*%-%-") then code[#code + 1] = line end
  end
  code = table.concat(code, "\n")
  check(code:find("MapKind%.cellsOf"),
    "Preview's CODE asks MapKind.cellsOf for the map's size in cells. A "
    .. "literal `* 2` there is the Gen 1/2 block-to-cell ratio applied to "
    .. "every cartridge, and it put the camera on the map's bottom-right "
    .. "corner on every Gen 3 and Gen 4 map -- which is the black bar in the "
    .. "map viewport")
  check(not code:find("width%)%s*or%s*0%)%s*%*%s*2"),
    "and no longer carries the hardcoded `(def.width or 0) * 2`")
end

-- ---------------------------------------------------------------------------
-- 7. the REAL cache: the availability answer must come from real defs
-- ---------------------------------------------------------------------------

-- WHY THIS SECTION EXISTS AT ALL, and it is the most expensive lesson of this
-- pass. Stage 1 asserted the tool list against synthetic fixtures and reported
-- that Platinum offers five tools. The shipping editor offered all eight,
-- because a real Platinum map NAMES A TILESET -- the stand-in -- which reports
-- `metatileCount = 256` and carries a 256-entry `collision` table, and the
-- fixture had no tileset in it at all. The measurement agreed with the code
-- because the measurement supplied the world the code expected.
--
-- So the AVAILABILITY answer is taken from real defs whenever a cache is
-- reachable, and the fixtures are asserted to AGREE with those defs so they
-- cannot drift away from the data again. The mechanics above stay synthetic on
-- purpose: a layout assertion that needs a cache is one nobody runs.

local function loadCache(dir)
  if not dir or dir == "" then return nil end
  if dir:sub(-1) ~= "/" and dir:sub(-1) ~= "\\" then dir = dir .. "/" end
  local okM, maps = pcall(dofile, dir .. "maps.lua")
  local okT, sets = pcall(dofile, dir .. "tilesets.lua")
  if not (okM and okT and type(maps) == "table" and type(sets) == "table") then
    return nil
  end
  return { dir = dir, maps = maps, tilesets = sets }
end

-- The caches the suite hands over, plus the GEN 1/2 one DERIVED from where the
-- Platinum one is: the runner has no flag for it, and a hardcoded absolute
-- path would be the one thing this file is not allowed to contain. An install
-- keeps its games side by side -- `<root>/platinum/data/generated` beside
-- `<root>/crystal/data/generated` -- so the siblings are found by substitution
-- rather than guessed.
local CACHES = {}
local function addCache(label, dir, want)
  local c = loadCache(dir)
  if c then c.label, c.want = label, want; CACHES[#CACHES + 1] = c end
  return c
end

addCache("platinum", arg and arg[1], "gen4")
addCache("emerald", arg and arg[2], "gen3")
do
  local base = (arg and arg[1]) or ""
  for _, name in ipairs({ "crystal", "gold", "silver" }) do
    if #CACHES > 0 and base ~= "" then
      for _, from in ipairs({ "platinum", "plat167", "plat" }) do
        local try = base:gsub(from, name, 1)
        if try ~= base and addCache(name, try, "gen12") then break end
      end
    end
  end
end

-- `maps.lua` carries a `_romInfo` sidecar beside the maps, so "every value in
-- the table" is not "every map". Measured: 519 entries in the Emerald cache,
-- 518 of them maps.
local function realMaps(cache)
  local out = {}
  for id, def in pairs(cache.maps) do
    if type(def) == "table" and tonumber(def.width) and tonumber(def.height)
       and def.tileset ~= nil then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  return out
end

local WANT = {
  -- TERRAIN JOINED THIS LIST IN PASS 195, and re-pinning it is the point of
  -- the assertion rather than an annoyance it causes: the tool list is the
  -- thing under test, so every legitimate change to it has to be stated here
  -- deliberately. The alternative -- deriving the expectation from
  -- `Sidebar.TOOLS` -- would be a check that grades the subject against
  -- itself and passes whatever the list becomes.
  --
  -- Gen 4 gets TERRAIN and does NOT get TILES: `Tiles.actsOn` needs a block
  -- space to paint from and Sinnoh's ground is a mesh. The two are offered on
  -- exactly complementary sets of maps, which is asserted below.
  gen4 = { warps = true, objects = true, scripts = true, wilds = true,
           models = true, terrain = true },
  gen3 = { warps = true, objects = true, scripts = true, voxels = true,
           wilds = true, tiles = true, collision = true },
  gen12 = { warps = true, objects = true, scripts = true, voxels = true,
            wilds = true, tiles = true, collision = true },
}

-- A CHECK CANNOT DEMAND AN INPUT IT DECLARES OPTIONAL -- the layout half above
-- has to run with no cache at all, which is most of this file. But it must
-- never SILENTLY ignore one it was given: a cache path that was supplied and
-- did not load is a failure, not a skip, because that is how a real-data
-- section comes to be permanently not running while the check reports green.
local SUPPLIED = ((arg and arg[1]) or "") ~= "" or ((arg and arg[2]) or "") ~= ""
if SUPPLIED then
  check(#CACHES >= 1,
    ("a cache path was supplied (%s) and at least one of them loads. The "
     .. "availability answer has to come from real map defs: stage 1 graded it "
     .. "against a fixture with no stand-in tileset in it and reported a Gen 4 "
     .. "tool list the shipping editor did not produce")
    :format(tostring((arg and arg[1]) or arg and arg[2])))
else
  print("NOTE: no cache path given, so the real-data section below did not "
        .. "run. Pass the Platinum data/generated as the first argument (the "
        .. "suite does) to grade the availability rule against real defs.")
end

for _, cache in ipairs(CACHES) do
  local ids = realMaps(cache)
  check(#ids > 0, ("%s: maps.lua yields at least one real map def (the table "
    .. "also carries a _romInfo sidecar, which is not a map)"):format(cache.label))

  -- EVERY map, not a sample. The rule is cheap and a per-map exception is
  -- exactly what a sample would miss.
  local want = WANT[cache.want]
  local wrong, wrongId, seen = nil, nil, 0
  local badCells, badCellsId = nil, nil
  local badPair, badPairId = nil, nil
  local badView, badViewId = nil, nil
  for _, id in ipairs(ids) do
    local S = { version = cache.label, mapId = id,
                data = { maps = cache.maps, tilesets = cache.tilesets,
                         constants = {} } }
    local def = cache.maps[id]
    local got = {}
    for _, t in ipairs(Sidebar.toolsFor(S, BY_ID)) do got[t.id] = true end
    seen = seen + 1
    -- A GROUND TOOL, AND EXACTLY ONE. TILES and TERRAIN are the same job on
    -- different cartridges, and the two failures either way are both real
    -- reports: offering neither is "the map painter tiles arent working at all
    -- for platinum nothing shows", and offering both would put two buttons on
    -- one map that paint the same cells through different stores.
    if not badPair then
      local n = (got.tiles and 1 or 0) + (got.terrain and 1 or 0)
      if n ~= 1 then
        badPair, badPairId = (n == 0 and "neither" or "both"), id
      end
    end
    if not wrong then
      for k in pairs(want) do if not got[k] then wrong, wrongId = k .. " missing", id end end
      for k in pairs(got) do if not want[k] then wrong, wrongId = k .. " offered", id end end
    end
    -- the cell count, against the engine's own derivation
    local n = tonumber((cache.tilesets[def.tileset] or {}).blockCells) or 2
    local w, h = MapKind.cellsOf(S, def)
    if not badCells and (w ~= def.width * n or h ~= def.height * n) then
      badCells, badCellsId = ("%dx%d, expected %dx%d")
        :format(w, h, def.width * n, def.height * n), id
    end
    -- and the viewport: the default camera must leave the map covering the
    -- whole viewport on any map at least a viewport tall
    local frac, hCells = viewportCoverage(S, def, 560, 2.0)
    if not badView and hCells * CELL >= 560 / 2.0 and frac < 0.999 then
      badView, badViewId = frac, id
    end
  end
  check(wrong == nil, ("%s: every one of the %d real map defs is offered "
    .. "exactly %s. First disagreement: %s on %s")
    :format(cache.label, seen, (function()
      local t = {} for k in pairs(want) do t[#t + 1] = k end
      table.sort(t) return table.concat(t, " ")
    end)(), tostring(wrong), tostring(wrongId)))
  check(badPair == nil, ("%s: every one of the %d real map defs is offered "
    .. "exactly ONE ground tool -- TILES where there are blocks to paint, "
    .. "TERRAIN where the ground is a mesh. %s offered on %s")
    :format(cache.label, seen, tostring(badPair), tostring(badPairId)))
  check(badCells == nil, ("%s: MapKind.cellsOf agrees with the engine's "
    .. "`def.width * (tilesetDef.blockCells or 2)` on all %d real maps. First "
    .. "disagreement: %s on %s -- this is the arithmetic that put the camera "
    .. "off the end of the map"):format(cache.label, seen,
      tostring(badCells), tostring(badCellsId)))
  check(badView == nil, ("%s: with the cell count derived, the default camera "
    .. "leaves the map covering the WHOLE viewport on all %d real maps. First "
    .. "disagreement: %s covered %.0f%% -- the uncovered part is the plate "
    .. "Preview paints first, which is the black bar in the map view")
    :format(cache.label, seen, tostring(badViewId),
            100 * (tonumber(badView) or 1)))
end

-- THE FIXTURES MUST AGREE WITH THE CACHE. This is the assertion that stops
-- stage 1's failure repeating: a synthetic tileset that no longer looks like
-- the real one is a measurement about nothing.
for _, cache in ipairs(CACHES) do
  local fixture = ({ gen4 = FIXTURES[3], gen3 = FIXTURES[2],
                     gen12 = FIXTURES[1] })[cache.want]
  if fixture then
    local S, def = fixture.build()
    local fts = S.data.tilesets[def.tileset] or {}
    -- one real map's tileset record, whichever comes first
    local ids = realMaps(cache)
    local rts = ids[1] and cache.tilesets[cache.maps[ids[1]].tileset] or {}
    check((fts.blockCells or false) == (rts.blockCells or false),
      ("the %s fixture's blockCells (%s) matches the real cache's (%s) -- the "
       .. "block-to-cell ratio is the fact the viewport bar came from")
      :format(fixture.label, tostring(fts.blockCells), tostring(rts.blockCells)))
    check((fts.standIn or false) == (rts.standIn or false),
      ("the %s fixture's standIn (%s) matches the real cache's (%s) -- stage 1 "
       .. "reported a Gen 4 tool list the editor did not produce because its "
       .. "fixture had no stand-in in it")
      :format(fixture.label, tostring(fts.standIn), tostring(rts.standIn)))
    check((fts.collision ~= nil) == (rts.collision ~= nil),
      ("the %s fixture carries a collision table iff the real one does (%s/%s) "
       .. "-- the stand-in HAS one, which is why WALKABLE offered itself on "
       .. "Sinnoh"):format(fixture.label, tostring(fts.collision ~= nil),
                           tostring(rts.collision ~= nil)))
  end
end

-- THE TWO SPELLINGS THAT ARE NOT A BUG, pinned so the next reader does not go
-- looking for a prefix strip that does not exist. `maps.lua` names
-- `TILESET_GEN4_STANDIN`; `map_tilesets.lua` is keyed `GEN4_STANDIN`. Those
-- are two different tables, and `tilesets.lua` -- the one read as
-- `data.tilesets` -- is keyed the long way and links to the art record through
-- `primaryKey`, exactly as a Gen 3 pair links to its half-banks.
for _, cache in ipairs(CACHES) do
  if cache.want == "gen4" then
    local ids = realMaps(cache)
    local def = ids[1] and cache.maps[ids[1]]
    local ts = def and cache.tilesets[def.tileset]
    check(ts ~= nil, ("%s: the tileset a real map names (%s) resolves in "
      .. "tilesets.lua -- nothing strips a TILESET_ prefix and nothing needs "
      .. "to, so `blockCount` answering 256 was a real answer about the "
      .. "stand-in and not a failed lookup")
      :format(cache.label, tostring(def and def.tileset)))
    check(ts and ts.standIn == true,
      ("%s: that tileset marks itself standIn, which is the flag every "
       .. "availability rule now reads through MapKind"):format(cache.label))
    check(ts and ts.primaryKey ~= nil and ts.primaryKey ~= def.tileset,
      ("%s: and it links to its art record by primaryKey (%s), which is the "
       .. "short key map_tilesets.lua holds -- two tables, not two spellings "
       .. "of one"):format(cache.label, tostring(ts and ts.primaryKey)))
  end
end


-- ---------------------------------------------------------------------------
-- the camera bound
-- ---------------------------------------------------------------------------
--
-- The ratio fix above stopped `centerOn` aiming at the map's corner. It did
-- NOT stop the camera from being moved there afterwards: `centerOn`, the
-- right-drag and the arrow keys all write `pvCamX/Y` and none of the three
-- bounded it, so a drag past the edge put the plate back on screen -- and on a
-- map smaller than the viewport the whole remainder sat at one side.
--
-- `Preview.clampCam` is that rule, split out of the draw so this can EXECUTE
-- it rather than read it. Driven here on three shapes: larger than the window,
-- smaller than it, and the real Platinum map from the screenshot.
do
  local okP, Preview = pcall(require, "tools.map-editor.panels.Preview")
  check(okP and type(Preview) == "table" and type(Preview.clampCam) == "function",
    "Preview.clampCam is missing, so the camera is unbounded again and the "
    .. "black bar comes back on the first drag")

  if okP and type(Preview) == "table" and type(Preview.clampCam) == "function" then
    local CELL = 16

    -- A MAP LARGER THAN THE WINDOW: the camera may not leave the world.
    -- 64 x 64 cells at zoom 2 in a 560 x 560 viewport -> world 1024,
    -- window 280, so the last legal camera is 744.
    local S = { pvZoom = 2, pvViewW = 560, pvViewH = 560, pvCamX = 9e9, pvCamY = 9e9 }
    local cx, cy = Preview.clampCam(S, 64, 64)
    check(cx == 1024 - 280 and cy == 1024 - 280,
      ("a camera driven past the bottom-right of a 64x64 map settled at %s,%s; "
       .. "the last legal corner is %d,%d"):format(tostring(cx), tostring(cy),
        1024 - 280, 1024 - 280))

    S.pvCamX, S.pvCamY = -9e9, -9e9
    cx, cy = Preview.clampCam(S, 64, 64)
    check(cx == 0 and cy == 0,
      ("a camera driven past the top-left settled at %s,%s, not 0,0")
        :format(tostring(cx), tostring(cy)))

    -- ...AND THE MIDDLE IS LEFT ALONE. A clamp that moved a legal camera
    -- would fight every drag.
    S.pvCamX, S.pvCamY = 300, 400
    cx, cy = Preview.clampCam(S, 64, 64)
    check(cx == 300 and cy == 400,
      ("a camera already inside the world was moved to %s,%s"):format(
        tostring(cx), tostring(cy)))

    -- A MAP SMALLER THAN THE WINDOW IS CENTRED, and the remainder is SPLIT.
    -- 8 x 8 cells -> world 128, window 280, so the camera is -76 and the
    -- margins are equal. Pinned as the symmetry rather than the number,
    -- because a letterbox all on one side is what the report looked like.
    S.pvCamX, S.pvCamY = 0, 0
    cx, cy = Preview.clampCam(S, 8, 8)
    local marginTop, marginBottom = -cy, (280 - 128) + cy
    check(cx == (128 - 280) / 2 and cy == (128 - 280) / 2,
      ("a map smaller than the window centred at %s,%s, not %s"):format(
        tostring(cx), tostring(cy), tostring((128 - 280) / 2)))
    check(math.abs(marginTop - marginBottom) < 1e-9,
      ("the empty margins above and below a small map are %s and %s; a "
       .. "letterbox all on one side is what the black bar looked like")
        :format(tostring(marginTop), tostring(marginBottom)))

    -- THE REAL MAP FROM THE REPORT. C01 is 64 x 64 blocks with blockCells 1,
    -- so the whole viewport is covered at zoom 2 and there is no band at all.
    local worldH = 64 * CELL
    S.pvCamX, S.pvCamY = 0, 0
    local _, camY = Preview.clampCam(S, 64, 64)
    check(camY + 280 <= worldH,
      ("the bottom of the viewport sits at world y %s on C01, past the map's "
       .. "%d -- that is the black bar"):format(tostring(camY + 280), worldH))

    -- AND THE DRAW ACTUALLY CALLS IT. A correct helper nobody calls is a fix
    -- that is not applied -- the same trap the cell-count assertion above
    -- guards against. Comments stripped first, so the paragraph explaining
    -- the clamp cannot satisfy the test for the clamp (shape 3e).
    local f = io.open("tools/map-editor/panels/Preview.lua", "rb")
    local src = f and f:read("*a") or ""
    if f then f:close() end
    local code = src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " ")
    -- A NAME IS NOT A CALL (shape 3b), and this assertion was written wrong
    -- the first time: `Preview%.clampCam%s*%(%s*S%s*,` is satisfied by
    -- `function Preview.clampCam(S, wCells, hCells)` -- the DEFINITION -- so
    -- deleting the only call site passed. Found by the plant, not by reading.
    -- A call is a STATEMENT here, so the line must begin with it.
    local calls = 0
    for line in code:gmatch("[^\r\n]+") do
      if line:match("^%s*Preview%.clampCam%s*%(") then calls = calls + 1 end
    end
    check(calls >= 1,
      "nothing in Preview.lua's CODE calls Preview.clampCam as a statement -- "
      .. "the helper is correct and unreached, so the camera is still "
      .. "unbounded in the draw")
    check(code:find("function%s+Preview%.clampCam"),
      "the comment strip left no clampCam definition behind, so the assertion "
      .. "above is matching nothing")
  end
end

print(("%d checks, %d failed"):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
