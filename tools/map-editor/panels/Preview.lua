-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The map editor's home screen: pick an area, look at it, then choose a tool.
--
-- WHY THIS EXISTS RATHER THAN REUSING THE SAVE EDITOR'S MAP TAB. MapBrowser
-- answers a save's questions -- where is the player, where do they heal, which
-- cell should the spawn move to -- and every one of those needs a save file.
-- The map editor has none, and should not need one: editing New Bark Town's
-- doors has nothing to do with anybody's party. So this is the same idea
-- pointed at the map instead of the player: the overlays are the things that
-- are being EDITED, and the buttons are the tools that edit them.
--
-- The preview is the game's own renderer (MapLoader + TileRenderer), not a
-- schematic. An editor that draws its own approximation of the world teaches
-- you to trust a picture the player will never see -- and the two drift the
-- first time a tileset changes. What is on screen here is what boots.
--
-- Clicking a cell SELECTS it, and the selection is shared with every tool:
-- the WARPS panel adds its next warp there, OBJECTS drops its next NPC there,
-- VOXELS paints there. That is the whole reason to have a preview at all --
-- otherwise every tool needs its own coordinate entry and the map is a number
-- you type rather than a place you point at.

local MapEdits = require("tools.map-editor.MapEdits")
local VoxelClasses = require("tools.map-editor.VoxelClasses")
local ModShapes = require("tools.map-editor.ModShapes")
-- Optional: without it the tools go back to being tabs and this panel still
-- draws. Required lazily through pcall for the same reason App does -- a
-- checkout that does not carry the file must lose the drawer, not the editor.
local okSidebar, Sidebar = pcall(require, "tools.map-editor.Sidebar")
if not okSidebar then Sidebar = nil end
local okHistory, History = pcall(require, "tools.map-editor.History")
if not okHistory then History = nil end
local okExport, ModExport = pcall(require, "tools.map-editor.ModExport")
if not okExport then ModExport = nil end
local okVP, Viewport3D = pcall(require, "tools.map-editor.Viewport3D")
if not okVP then Viewport3D = nil end
-- The view presets, or an empty list when the viewport module is absent, so
-- the header can be laid out without testing for it on every button.
local Viewport3D_VIEWS = (Viewport3D and Viewport3D.VIEWS) or {}
local MapLoader = require("src.world.MapLoader")
local Theme = require("Theme")
local PAL = Theme.PAL

local Preview = {}

local CELL = 16   -- one walk cell of map art, the unit MapBrowser uses too

-- The tools, in the order they are used: put a door somewhere, put a person
-- next to it, give the person something to say, then shape the ground.
Preview.TOOLS = {
  { tab = "warps",   title = "WARPS",
    blurb = "doors, stairs and cave mouths; make new maps" },
  { tab = "objects", title = "NPCs & ITEMS",
    blurb = "people, items, trainers and their teams" },
  { tab = "scripts", title = "SCRIPTS",
    blurb = "what an object does when you talk to it" },
  { tab = "voxels",  title = "VOXELS",
    blurb = "per-cell height and shape for the 3D mods" },
  { tab = "wilds",   title = "WILDS",
    blurb = "what lives in the grass, the water and on a hook" },
  { tab = "tiles",   title = "TILES",
    blurb = "paint the ground itself, block by block" },
}

-- Bump on every edit. `mapEditsDirty` says THAT something changed; the stamp
-- says WHEN, which is what the 3D viewport needs to know its mesh is stale.
-- A boolean cannot answer that: it is already true from the last edit, so a
-- mesh keyed on it would build once and then show the map as it was.
local function markEdited(S)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
end

local function game(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring(S.version or v or "unknown")
end

local function store(S)
  if not S.mapEdits then S.mapEdits = (MapEdits.load()) end
  return S.mapEdits
end

-- ---------------------------------------------------------------------------
-- the voxel view
-- ---------------------------------------------------------------------------

-- DRAMATIC_SHAPE's shape profile: `heights` maps an art class to a height in
-- world pixels, `collision` maps a Gen 2 collision class to an art class.
-- The class vocabulary for this map's tileset, cached per tileset so the
-- preview and the VOXELS tab always offer the same forty names.
local function classInfo(S)
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  -- Keyed on the SOURCE as well as the tileset. Switching mods has to change
  -- the answers, and a cache keyed on the tileset alone would keep showing the
  -- previous mod's heights under the new mod's name.
  local key = tostring(def and def.tileset or "-") .. "|"
    .. tostring(S.voxelSource or "-")
  if S.pvClassesFor == key then return S.pvClassNames, S.pvClassInfo end
  local names, info = VoxelClasses.list(def and def.tileset, S.voxelSource)
  S.pvClassNames, S.pvClassInfo, S.pvClassesFor = names, info, key
  return names, info
end

local function profile(S)
  if S.pvProfile ~= nil then return S.pvProfile or nil end
  local ok, p = pcall(function()
    return require("mods.DRAMATIC_SHAPE.data.voxel_heights")
  end)
  S.pvProfile = (ok and type(p) == "table") and p or false
  return S.pvProfile or nil
end

-- The class and height this cell would take, and where that answer came from.
--
-- THIS IS THE PROFILE'S RULES, NOT THE MESHER'S. voxel_heights.lua documents
-- its own resolution order -- a pinned tileset group, then water, then a
-- walkable cell, then the tile-level fallback -- and rules 1 and 4 need the
-- tileset pin lists and the map's own walkable set, which this cannot see. So
-- rules 2 and 3 are what is implemented, plus the Gen 2 collision map, which
-- is the part that carries the real semantics (the ROM itself distinguishes a
-- tree from a wall).
--
-- Which means: this view is a READING of the terrain, good enough to see
-- relief and to place an override against, and it is NOT a preview of the
-- mesh. Saying so here rather than letting the difference be discovered as a
-- bug -- the runtime detector measures heights off the artwork and will
-- disagree with this on anything it was not told about.
local function voxelAt(S, def, cx, cy, cls)
  local edits = MapEdits.bucket(store(S), game(S), S.mapId, false)
  local o = edits and edits.voxels and edits.voxels[cx .. "," .. cy]
  if o then
    return tostring(o.art or "ground"), tonumber(o.h) or 0, "override"
  end
  local p = profile(S)
  if not p then return "ground", 0, "no profile" end
  local class = p.collision and cls and p.collision[cls]
  if not class then
    -- rule 3 then rule 4: an entrance or a walkable-looking class is ground,
    -- anything else stands up as wall. The engine's own walkable set is per
    -- tileset and not reachable here, so this is the coarse version.
    if cls == nil then class = "void"
    elseif cls == 0x00 or cls == 0x01 or (cls >= 0x60 and cls <= 0x7F) then
      class = "ground"
    else
      class = "wall"
    end
  end
  -- Height from the shared vocabulary rather than from the profile's own
  -- `heights`: the two disagree on twelve classes, and the one the RENDERER
  -- resolves against is TileShape's.
  local _, info = classInfo(S)
  local spec = info[class]
  local h = (spec and spec.h) or (p.heights and p.heights[class]) or 0
  return class, h, "profile"
end

-- ---------------------------------------------------------------------------
-- the map list
-- ---------------------------------------------------------------------------

-- Gen 2 map ids are MAP_G<group>_N<number> before the aliases resolve, and
-- readable names after. Both sort into something usable, so the grouping is
-- taken from the id's leading word rather than invented: ROUTE_29 and
-- ROUTE_29_ROUTE_46_GATE land together, and so do every ...S_HOUSE.
local function areaOf(id)
  local head = id:match("^(MAP_G%x+)") or id:match("^([A-Z0-9]+)")
  return head or id
end

-- HOW MANY MAPS THERE ARE, which is the cheap half of "has the set changed".
--
-- Both lists below cache their SORTED result, and the sort is the expensive
-- part -- the walk that produces this number is the same walk the list itself
-- does. So counting costs nothing next to what is saved, and it is the one
-- key that cannot be forgotten.
local function mapCount(S)
  local n = 0
  for _ in pairs((S.data and S.data.maps) or {}) do n = n + 1 end
  return n
end

-- THE CACHE KEY HAS TO INCLUDE THE SET, NOT JUST THE QUERY.
--
-- It was keyed on the search box alone. Creating a map does not change the
-- search box, so the AREAS list handed back the list it had built before the
-- map existed -- for the rest of the session. The new map WAS created, WAS in
-- the store and WAS in `data.maps`; it simply never appeared on the left.
--
-- And the way that presented is worth writing down, because it sent me looking
-- in the wrong place: making a second map looked like it REPLACED the first.
-- It did not. Creating one selects it, so the header changed to the new name
-- while the list stayed exactly as it was -- and from outside, one name
-- turning into another is a replacement.
--
-- Keyed on the count and the edit stamp rather than invalidated at each call
-- site, for the reason History.lua gives for snapshots over an action log: a
-- key cannot be forgotten by a tool that does not know it exists, and there
-- are already three places that add a map.
local function listKey(S)
  return (S.pvQuery or "") .. "|" .. mapCount(S)
    .. "|" .. tostring(S.mapEditsStamp or 0)
end

local function mapList(S)
  local key = listKey(S)
  if S.pvList and S.pvListFor == key then return S.pvList end
  local q = (S.pvQuery or ""):lower()
  local out = {}
  for id, def in pairs((S.data and S.data.maps) or {}) do
    if q == "" or id:lower():find(q, 1, true)
       or (def.name and tostring(def.name):lower():find(q, 1, true)) then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  S.pvList, S.pvListFor = out, key
  return out
end

local function areaList(S)
  -- The areas are derived from the map ids, so they go stale for exactly the
  -- same reason and were cached with no key at all -- a new map's area never
  -- appeared in the filter either.
  local key = mapCount(S) .. "|" .. tostring(S.mapEditsStamp or 0)
  if S.pvAreas and S.pvAreasFor == key then return S.pvAreas end
  local seen, out = {}, {}
  for id in pairs((S.data and S.data.maps) or {}) do
    local a = areaOf(id)
    if not seen[a] then seen[a] = true; out[#out + 1] = a end
  end
  table.sort(out)
  table.insert(out, 1, "ALL AREAS")
  S.pvAreas, S.pvAreasFor = out, key
  return out
end

Preview.mapList = mapList
Preview.areaList = areaList

-- ---------------------------------------------------------------------------
-- the preview
-- ---------------------------------------------------------------------------

local function centerOn(S, cx, cy)
  local vw, vh = S.pvViewW or 480, S.pvViewH or 432
  S.pvCamX = cx * CELL - vw / (2 * (S.pvZoom or 2))
  S.pvCamY = cy * CELL - vh / (2 * (S.pvZoom or 2))
end
Preview.centerOn = centerOn

-- The collision class under a cell, read exactly the way Map:cellTile does.
local function cellClass(S, def, cx, cy)
  local ts = S.data and S.data.tilesets and S.data.tilesets[def.tileset]
  local coll = ts and ts.collision
  if not (coll and def.blocks and def.width and def.height) then return nil end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local id
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then
    id = def.borderBlock or 0
  else
    id = def.blocks[by * def.width + bx + 1] or 0
  end
  return coll[id * 4 + (cx % 2) + (cy % 2) * 2 + 1], id
end

-- Takes the map's size in cells rather than a built Map, so pointing at the
-- world does not depend on the renderer having succeeded. That is not a
-- convenience for the tests: a map whose tileset will not resolve still has
-- coordinates, and being able to pan and select on it is how you get to the
-- controls that fix it.
local function cellAtScreen(S, wCells, hCells, Kit, vx, vy, vw, vh)
  local mx, my = Kit.mouseX, Kit.mouseY
  if mx < vx or my < vy or mx > vx + vw or my > vy + vh then return nil end
  local z = S.pvZoom or 2
  local worldY = (my - vy) / z

  -- The FLAT fallback's inverse. The real 3D viewport picks by ray-marching
  -- its own height field and never comes through here.
  --
  -- Two terms, both needed. `cos` undoes the tilt; `mid` undoes the
  -- recentring the draw does so the map does not slide off the top of the
  -- viewport. Leaving `mid` out of one side of that pair puts the click a
  -- third of a map from the pointer, which reads as a broken selection rather
  -- than a mismatched projection.
  --
  -- Height is ignored on purpose: a screen row is `y*cos - h*sin` and `h` is
  -- the thing being asked for, so the ground plane is what gets inverted. The
  -- pointer picks the cell whose FLOOR is under it -- exact on flat ground,
  -- off by the lean on something tall, and the footer says so.
  if S.pvView == "voxel" then
    local cosA = math.max(0.15, math.cos(math.rad(S.pvAngle or 35)))
    local mid = vh / (2 * z)
    worldY = (worldY - mid) / cosA + mid
  end

  local cx = math.floor(((mx - vx) / z + (S.pvCamX or 0)) / CELL)
  local cy = math.floor((worldY + (S.pvCamY or 0)) / CELL)
  if cx < 0 or cy < 0 or cx >= wCells or cy >= hCells then return nil end
  return cx, cy
end

-- ---------------------------------------------------------------------------
-- the 3D view
-- ---------------------------------------------------------------------------
--
-- A real projection of the voxel world, not a heightmap. The first version of
-- this coloured each cell by its height and called itself VOXEL, which told
-- you where the relief was and nothing about what it would look like -- the
-- one question a voxel preview exists to answer.
--
-- THE CAMERA IS THE GAME'S. VoxelState's ladder is 15 / 35 / 50 / 75 degrees
-- and FULL is 35; the angle is the camera's pitch away from straight down, so
-- 0 is the flat map and 75 is a diorama shot from about table height. A point
-- at (x, y, h) lands at:
--
--     screen x = x
--     screen y = y * cos(angle) - h * sin(angle)
--
-- which is why the first version looked wrong rather than merely rough: it
-- used cos = 1 and sin = 1, i.e. no foreshortening at all. The ground never
-- compressed, so nothing receded and every box leaned the same distance
-- whatever its height. With the real terms the map lies down under the camera
-- and heights stand up out of it, the way the mode actually looks.
--
-- Read from VoxelState when the mod is reachable, so the ladder here is the
-- ladder the player has.
local VOX_ANGLES = { 15, 35, 50, 75 }
do
  local ok, VS = pcall(require, "mods.STADIUM2_OVERWORLD_MODELS.lib.VoxelState")
  if ok and type(VS) == "table" and type(VS.ANGLES_DEG) == "table" then
    local seen, list = {}, {}
    for _, deg in ipairs(VS.ANGLES_DEG) do
      -- 0 is OFF (the flat map, which is what the 2D view already is) and the
      -- ladder repeats 35 and 75 for rungs that differ by more than angle.
      if deg > 0 and not seen[deg] then seen[deg] = true; list[#list + 1] = deg end
    end
    table.sort(list)
    if #list > 0 then VOX_ANGLES = list end
  end
end

-- WHAT THIS IS NOT: the mod's mesher. Structures.lua carves per-pixel hulls,
-- measures heights off the artwork, groups connected drawings and folds every
-- face; this stands one box per cell and folds the south face. The camera and
-- the relief match the game; the fine carving does not, which is the honest
-- shape of a preview that has to run inside an editor.
local VOX_SIDE_SHADE = { 0.55, 0.58, 0.66 }

-- Which of four ways to draw a class. The names come from TileShape's ART
-- table; anything it folds per-pixel (cylinder, post, canopy, planter,
-- bookcase) is drawn here as a standee, because a box would be wronger than a
-- plate for a thing that is mostly holes.
local VOX_FORM = {
  flat = "flat", top = "top", upright = "upright",
  billboard = "standee", post = "standee", cylinder = "standee",
  canopy = "standee", planter = "standee", bookcase = "upright",
  relief = "flat", grass = "flat", flower = "flat", stair = "upright",
}

-- ONE CELL, drawn the way the 3D view would draw it, into a box of its own.
--
-- This is what the ART button was missing. Cycling through forty class names
-- with nothing on screen but the name is a guess per press: `terrace` and
-- `roof` are both 16-plus and art-on-top, `wall` and `tree` are both 16 and
-- upright, and the difference only shows up in the world. So the picker
-- renders the CELL'S OWN ARTWORK under each candidate class -- the same
-- artwork, the same folds, the same camera -- and the choice becomes a
-- comparison instead of a memory test.
--
-- Shares VOX_FORM and the band rule with drawVoxel3D deliberately: a swatch
-- that showed a different shape from the view it is choosing for would be
-- worse than no swatch.
local function drawCellSwatch(S, map, cx, cy, class, h, bx, by, bw, bh)
  local renderer = map.renderer
  local image, quads = renderer and renderer.image, renderer and renderer.quads
  if not (image and quads) then return false end
  local _, info = classInfo(S)
  local spec = info[class]
  local form = VOX_FORM[(spec and spec.art) or "upright"] or "upright"

  local rad = math.rad(S.pvAngle or 35)
  local cosA, sinA = math.cos(rad), math.sin(rad)
  local scale = math.max(1, math.floor(math.min(bw / CELL, bh / 32)))
  local tx0, ty0 = cx * 2, cy * 2
  -- The cell sits on the floor of the swatch so a taller class grows UPWARD
  -- out of a fixed baseline; a swatch that recentred per class would make
  -- every height look the same.
  local ox = bx + (bw - CELL * scale) / 2
  local oy = by + bh - 4 - CELL * cosA * scale

  local function q(tx, ty)
    local tile = map:tileAt(tx, ty)
    return tile and quads[tile]
  end

  local lift = h * sinA
  if h > 0 and form ~= "flat" then
    local bands = math.max(1, math.ceil(h / 8))
    for b = 0, bands - 1 do
      local bandH = math.min(8, h - b * 8)
      if bandH > 0 then
        local srcRow = (form == "upright") and (1 - (b % 2)) or 1
        local shade = VOX_SIDE_SHADE[math.min(#VOX_SIDE_SHADE, b + 1)]
        for i = 0, 1 do
          local quad = q(tx0 + i, ty0 + srcRow)
          if quad then
            love.graphics.setColor(shade, shade, shade * 1.02, 1)
            love.graphics.draw(image, quad,
              ox + i * 8 * scale,
              oy + (CELL * cosA - lift + b * 8 * sinA) * scale,
              0, scale, ((bandH / 8) * sinA) * scale)
          end
        end
      end
    end
  end
  for row = 0, 1 do
    for i = 0, 1 do
      local quad = q(tx0 + i, ty0 + row)
      if quad then
        love.graphics.setColor(1, 1, 1, 1)
        if form == "standee" and h > 0 then
          love.graphics.draw(image, quad, ox + i * 8 * scale,
            oy + (CELL * cosA - lift - (2 - row) * 8 * sinA) * scale,
            0, scale, sinA * scale)
        else
          love.graphics.draw(image, quad, ox + i * 8 * scale,
            oy + (row * 8 * cosA - lift) * scale, 0, scale, cosA * scale)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

local function drawVoxel3D(S, map, viewW, viewH)
  local renderer = map.renderer
  local image, quads = renderer and renderer.image, renderer and renderer.quads
  if not (image and quads) then return false end
  local def = map.def
  local camX, camY = S.pvCamX or 0, S.pvCamY or 0
  local z = S.pvZoom or 2
  local _, info = classInfo(S)

  local deg = S.pvAngle or 35
  local rad = math.rad(deg)
  local cosA, sinA = math.cos(rad), math.sin(rad)

  -- COMPRESS ABOUT THE MIDDLE OF THE VIEW, not about its top edge.
  --
  -- `(worldY - camY) * cos` scales every row toward SCREEN ZERO, so the whole
  -- map slides up and out of the viewport as the angle steepens -- at 40
  -- degrees a third of it is above the top edge and there is nothing on screen
  -- to say where it went. The camera's own centre row has to stay put, which
  -- means compressing about it and putting it back.
  local mid = viewH / (2 * z)
  local function screenY(worldY)
    return (worldY - camY - mid) * cosA + mid
  end

  -- The band of cells that can reach the viewport. Deliberately generous to
  -- the NORTH: a 32px cliff four cells above the top edge still leans into
  -- view, and clipping it to the visible rows made tall things pop in as you
  -- panned down onto them.
  local firstX = math.max(0, math.floor(camX / CELL))
  local lastX = math.min(map.widthCells - 1, firstX + math.ceil(viewW / (CELL * z)) + 1)
  local firstY = math.max(0, math.floor(camY / CELL) - 4)
  local lastY = math.min(map.heightCells - 1, math.floor(camY / CELL)
                         + math.ceil(viewH / (CELL * z)) + 1)

  local function tileQuad(tx, ty)
    local tile = map:tileAt(tx, ty)
    return tile and quads[tile]
  end

  -- PAINTER'S ORDER, north to south. In this projection a box leans up and
  -- back, so the cell in front of it is drawn after and covers the part that
  -- should be hidden. Drawing in any other order puts the far wall over the
  -- near floor.
  for cy = firstY, lastY do
    for cx = firstX, lastX do
      local cls = cellClass(S, def, cx, cy)
      local class, h = voxelAt(S, def, cx, cy, cls)
      local spec = info[class]
      local form = VOX_FORM[(spec and spec.art) or "upright"] or "upright"

      -- The ground plane recedes by cos(angle) and height rises by sin(angle).
      -- `py` is where this cell's FLOOR sits once the plane is laid down;
      -- `lift` is how far its top stands above that.
      local px = cx * CELL - camX
      local py = screenY(cy * CELL)
      local lift = h * sinA
      local tx0, ty0 = cx * 2, cy * 2

      -- SIDE FACE. Drawn first and below the top, from the cell's own artwork
      -- folded upright: an 8px band of the drawing per 8px of height, which is
      -- the mesher's own rule and the reason a wall looks like the wall that
      -- is drawn there rather than like a grey slab.
      if h > 0 and form ~= "flat" then
        local bands = math.max(1, math.ceil(h / 8))
        for b = 0, bands - 1 do
          local bandH = math.min(8, h - b * 8)
          if bandH > 0 then
            -- the artwork's bottom row folds up first, so the band nearest
            -- the ground is the bottom of the drawing
            local srcRow = (form == "upright") and (1 - (b % 2)) or 1
            local shade = VOX_SIDE_SHADE[math.min(#VOX_SIDE_SHADE, b + 1)]
            for i = 0, 1 do
              local q = tileQuad(tx0 + i, ty0 + srcRow)
              if q then
                love.graphics.setColor(shade, shade, shade * 1.02, 1)
                -- A side face is VERTICAL in the world, so it is not
                -- foreshortened by the ground plane -- it is scaled by
                -- sin(angle) instead. At a steep angle the sides all but
                -- vanish, which is exactly what a top-down camera shows.
                love.graphics.draw(image, q, px + i * 8,
                                   py + CELL * cosA - lift + b * 8 * sinA,
                                   0, 1, (bandH / 8) * sinA)
              end
            end
          end
        end
      end

      -- TOP FACE: the cell's own 2x2 of artwork, unrotated, lifted by h.
      if form == "standee" and h > 0 then
        -- a plate standing in the middle of the cell rather than a box: the
        -- drawing upright at its full height, which is what a fence post, a
        -- potted plant or a shelf actually is
        -- A standee stands UPRIGHT, so it keeps its full drawn height and is
        -- only pulled up by the lift; it does not lie down with the ground.
        for row = 0, 1 do
          for i = 0, 1 do
            local q = tileQuad(tx0 + i, ty0 + row)
            if q then
              love.graphics.setColor(1, 1, 1, 1)
              love.graphics.draw(image, q, px + i * 8,
                                 py + CELL * cosA - lift - (2 - row) * 8 * sinA,
                                 0, 1, sinA)
            end
          end
        end
      else
        -- A top face lies IN the ground plane, so it takes the plane's
        -- foreshortening.
        for row = 0, 1 do
          for i = 0, 1 do
            local q = tileQuad(tx0 + i, ty0 + row)
            if q then
              love.graphics.setColor(1, 1, 1, 1)
              love.graphics.draw(image, q, px + i * 8,
                                 py + row * 8 * cosA - lift, 0, 1, cosA)
            end
          end
        end
      end

      -- An authored cell is tinted so overrides are findable in a view whose
      -- whole point is that it looks like the world.
      local edits = MapEdits.bucket(store(S), game(S), S.mapId, false)
      if edits and edits.voxels and edits.voxels[cx .. "," .. cy] then
        love.graphics.setColor(0.5, 0.35, 1, 0.22)
        love.graphics.rectangle("fill", px, py - lift, CELL, CELL * cosA)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- The flat height reading, kept as the fallback for when the renderer has no
-- atlas to draw from (a map whose tileset would not build). Colour is height,
-- so the relief still reads even with no artwork available.
local VOXEL_LO, VOXEL_HI = -4, 32
local function drawVoxelHeights(S, map, viewW, viewH)
  local def = map.def
  local camX, camY = S.pvCamX or 0, S.pvCamY or 0
  local z = S.pvZoom or 2
  local firstX = math.max(0, math.floor(camX / CELL))
  local firstY = math.max(0, math.floor(camY / CELL))
  local lastX = math.min(map.widthCells - 1, firstX + math.ceil(viewW / (CELL * z)) + 1)
  local lastY = math.min(map.heightCells - 1, firstY + math.ceil(viewH / (CELL * z)) + 1)

  for cy = firstY, lastY do
    for cx = firstX, lastX do
      local cls = cellClass(S, def, cx, cy)
      local class, h, from = voxelAt(S, def, cx, cy, cls)
      local t = math.max(0, math.min(1, (h - VOXEL_LO) / (VOXEL_HI - VOXEL_LO)))
      local shade = 0.18 + t * 0.72
      if class == "water" then
        love.graphics.setColor(0.16, 0.34, shade + 0.25, 1)
      elseif from == "override" then
        love.graphics.setColor(shade * 0.65, shade * 0.5, shade + 0.2, 1)
      else
        love.graphics.setColor(shade, shade * 0.96, shade * 0.88, 1)
      end
      love.graphics.rectangle("fill", cx * CELL - camX, cy * CELL - camY,
                              CELL, CELL)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawVoxelView(S, map, viewW, viewH)
  if not drawVoxel3D(S, map, viewW, viewH) then
    drawVoxelHeights(S, map, viewW, viewH)
  end
end

-- ---------------------------------------------------------------------------
-- NPC sprites on the map
-- ---------------------------------------------------------------------------

-- The people, drawn as the people they are.
--
-- Objects used to be translucent white squares -- which says WHERE something
-- is and nothing about WHAT, so a map with a dozen of them was a dozen
-- identical boxes and the only way to tell the shopkeeper from the rival was
-- to click each one. The sheet is right there and the map is drawn at exactly
-- the scale it is drawn at in game, so there is no reason to show a box.
--
-- THE SHEET COMES FROM NPC.resolveSpriteDef, not from a name lookup. That
-- function is a pile of hard-won special cases -- Copycat is never a real
-- sheet, Sudowoodo's row is $52, variable-sprite ids resolve through their
-- slot, some imports key sheets only as SPRITE_%02X -- and looking the name up
-- directly would show a placeholder for every one of them. Same rule as the
-- voxel work this session: ask the thing that already knows.
local spriteCache = {}

-- WHICH ROW OF THE SHEET IS WHICH WAY.
--
-- The cartridge's layout (src/render/SpriteRenderer.lua): 16px frames stacked
-- down -- stand down, stand up, stand left, then the three walk frames. There
-- is no RIGHT row: the engine draws the LEFT frame mirrored, and so does this.
local FACE_ROW = { DOWN = 0, UP = 1, LEFT = 2, RIGHT = 2 }

-- The sheet, the frame for a facing, and whether that frame has to be
-- mirrored.
--
-- FACING USED TO BE MISSING FROM THIS ENTIRELY. It answered frame 0 for every
-- object and cached one entry per sprite id -- so every person on the map
-- faced down, and turning one in the NPC drawer changed the field, the panel's
-- own preview and the running game while the map beside it did not move. The
-- editor was disagreeing with the game about the one thing the reader had just
-- changed, which reads as the setting not working.
--
-- THE FACING IS PART OF THE CACHE KEY. It was not, and adding the frame
-- without the key would have been worse than the bug: the first object drawn
-- would have decided the pose for every other object sharing its sheet.
local function spriteQuadFor(S, spriteId, facing)
  -- `range` IS THE FACING ONLY FOR A STAY OBJECT. On a walker the same field
  -- is its wander area (ANY_DIR, UP_DOWN, LEFT_RIGHT) and on a spinner it is
  -- the spin kind, so anything that is not one of the four directions falls
  -- back to DOWN -- which is exactly what NPC.lua's FACING_FROM_RANGE does, so
  -- the map shows what the game will.
  local dir = tostring(facing or "DOWN"):upper()
  if FACE_ROW[dir] == nil then dir = "DOWN" end
  local key = tostring(spriteId) .. "|" .. dir
  local hit = spriteCache[key]
  if hit ~= nil then
    if hit == false then return nil end
    return hit.image, hit.quad, hit.w, hit.h, hit.flip
  end

  local okNPC, NPC = pcall(require, "src.world.NPC")
  local def = nil
  if okNPC and type(NPC) == "table" and NPC.resolveSpriteDef then
    local okD, d = pcall(NPC.resolveSpriteDef, S.data, spriteId)
    def = okD and d or nil
  end
  -- The plain lookup as a fallback, for a build whose NPC.lua predates the
  -- line above. Wrong for the special cases and right for the other 90%,
  -- which beats drawing nothing.
  if not (def and def.image) then
    def = S.data and S.data.sprites and S.data.sprites[spriteId] or nil
  end
  if not (def and def.image) then
    spriteCache[key] = false
    return nil
  end

  -- IN COLOUR, which means going through SpriteRenderer rather than reading
  -- the sheet off disk.
  --
  -- A Gen 2 overworld sheet is four SHADES, not four colours: the hardware
  -- carries the OBJ palette separately (MapObjectPals, picked by the sprite's
  -- palette field) and applies it at draw time. Loading the .png and blitting
  -- it gives you exactly what is in the file -- grey people -- which is what
  -- the map editor was showing while the game beside it showed a colour world.
  -- `SpriteRenderer:resolveImage` is the resolver that answers this, and it is
  -- published for precisely this reason: so a pipeline can texture its own
  -- geometry from the very same image the 2D path draws.
  local image = nil
  local okSR, SR = pcall(require, "src.render.SpriteRenderer")
  if okSR and type(SR) == "table" and SR.new then
    local okMake, sr = pcall(SR.new, def)
    if okMake and sr then
      local okImg, img = pcall(sr.resolveImage, sr)
      if okImg and img and img.getDimensions then image = img end
    end
  end
  -- The raw sheet if the recolour cannot be had -- a partial import, a palette
  -- mode the editor has not set up. Grey is worse than colour and far better
  -- than nothing.
  if not image then
    local okI, raw = pcall(function()
      return require("src.render.Assets").image(def.image)
    end)
    image = (okI and raw and raw.getDimensions) and raw or nil
  end
  if not image then
    spriteCache[key] = false
    return nil
  end
  local iw, ih = image:getDimensions()
  -- Frame 0 is the standing frame facing DOWN -- SpriteRenderer builds its
  -- frame list as newQuad(0, f * 16, 16, 16), so frame 0 is the top of the
  -- sheet. A still map wants a still pose, and down is the one every sheet
  -- has.
  --
  -- A BIG DOLL (Snorlax, Lapras) is 32x32 over a 2x2 footprint. Sheets that
  -- ship as a 16-wide strip carry only the left half, mirrored at draw time;
  -- here that half is drawn as-is rather than reconstructed, so one of those
  -- reads as half a Snorlax instead of as a wrong Snorlax.
  local w = (def.big and iw >= 32) and 32 or 16
  local h = (def.big and ih >= 32) and 32 or 16
  w, h = math.min(w, iw), math.min(h, ih)

  -- THE ROW THE SHEET ACTUALLY HAS. A fruit tree, a boulder and a Slowpoke are
  -- one frame; asking for row 2 of a one-row sheet reads off the end, and
  -- newQuad throws on that. A sheet with no facings keeps the pose it has --
  -- which is right, because it has no other.
  local rows = math.max(1, math.floor(ih / h))
  local row = FACE_ROW[dir] or 0
  local flip = 1
  if row >= rows then row = 0 end
  -- Mirrored only when the LEFT row is the one being shown: a sheet that
  -- fell back to row 0 is facing down, and drawing it backwards would be a
  -- second wrong answer on top of the first.
  if dir == "RIGHT" and row == FACE_ROW.RIGHT then flip = -1 end

  local okQ, quad = pcall(love.graphics.newQuad, 0, row * h, w, h, iw, ih)
  if not okQ then
    spriteCache[key] = false
    return nil
  end
  spriteCache[key] = { image = image, quad = quad, w = w, h = h, flip = flip }
  return image, quad, w, h, flip
end

-- Dropped when the data changes under us -- a re-import replaces every sheet,
-- and a cached Image from the old one is a picture of the last cartridge.
function Preview.forgetSprites()
  spriteCache = {}
end

-- Published for the 3D viewport, which draws the same people as billboards.
-- Handed over rather than reimplemented there: two caches of the same images
-- in one process is two chances to be showing the last cartridge's art.
Preview.spriteQuadFor = spriteQuadFor
if Viewport3D then Viewport3D.spriteResolver = spriteQuadFor end

-- WHICH OBJECT IS ON A CELL, if any.
--
-- Clicking a person on the map and getting a cell selection is the editor
-- telling you it saw the click and did not understand it: the person is the
-- most specific thing at that coordinate, and the tools that act on one are
-- the tools you reached for by clicking them. Later objects win, matching the
-- draw order -- the one on top is the one you pointed at.
local function objectAt(S, cx, cy)
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  local hit = nil
  for i, o in ipairs((def and def.objects) or {}) do
    if o.x == cx and o.y == cy then hit = i end
  end
  return hit
end

-- ---------------------------------------------------------------------------
-- selecting more than one cell
-- ---------------------------------------------------------------------------

-- SHIFT-CLICK EXTENDS THE SELECTION.
--
-- Every cell tool -- height, class, block, the voxel brush -- worked on
-- exactly one cell, so raising a wall six cells long was six identical trips
-- through the same three controls, and getting one of them wrong is invisible
-- until you look at it in 3D. A selection is the obvious answer and costs the
-- tools nothing: they ask for the selection and get a list, which for a plain
-- click is a list of one.
--
-- `pvCell` stays the PRIMARY -- what the cell inspector reads and what the
-- camera orbits -- and the set is what the bulk actions walk. Keeping both
-- means nothing that already worked had to learn about sets.
local function selKey(cx, cy) return cx .. "," .. cy end

function Preview.selection(S)
  local out = {}
  for key in pairs(S.pvSel or {}) do
    local kx, ky = key:match("^(-?%d+),(-?%d+)$")
    if kx then out[#out + 1] = { cx = tonumber(kx), cy = tonumber(ky) } end
  end
  -- The primary is always IN the selection, even when the set is empty: a
  -- plain click leaves no set at all, and a bulk action that then did nothing
  -- would look like the tool being broken rather than the set being empty.
  if #out == 0 and S.pvCell then
    out[1] = { cx = S.pvCell.cx, cy = S.pvCell.cy }
  end
  table.sort(out, function(a, b)
    if a.cy ~= b.cy then return a.cy < b.cy end
    return a.cx < b.cx
  end)
  return out
end

function Preview.selectionCount(S)
  local n = 0
  for _ in pairs(S.pvSel or {}) do n = n + 1 end
  if n == 0 then return S.pvCell and 1 or 0 end
  return n
end

function Preview.clearSelection(S)
  S.pvSel = nil
end

-- THE TILE PAINTER'S CLICK, when that tool is the one that is open.
--
-- Routed here rather than from the panel because the panel does not own the
-- map -- this one does, and it is the only place that knows which cell a click
-- landed on in both 2D and 3D. A click is a paint only while the TILES drawer
-- is open and a block is picked; otherwise it means what it always meant.
function Preview.paintAt(S, cx, cy)
  -- AN ARMED ASSET TAKES THE CLICK FIRST, whatever tool is open.
  --
  -- Placing is not a tool -- it is a thing you are HOLDING, armed from the
  -- library in the title bar, and it outranks whatever drawer happens to be
  -- open underneath. Routed through here rather than added as a fourth branch
  -- in the map's click handling because this is the one function that already
  -- knows which cell a click landed on in both 2D and 3D.
  local okA, MapAssets = pcall(require, "tools.map-editor.MapAssets")
  if okA and type(MapAssets) == "table" then
    local asset, name = MapAssets.armed(S)
    if asset then
      local report, why = MapAssets.place(S, asset, cx, cy)
      if report then
        local bits = { string.format("%s: %d cells", name, report.cells) }
        if report.voxels + report.tiles > 0 then
          bits[#bits + 1] = (report.voxels + report.tiles) .. " shaped"
        end
        if report.objects > 0 then bits[#bits + 1] = report.objects .. " npc" end
        if report.warps > 0 then bits[#bits + 1] = report.warps .. " door" end
        for _, n in ipairs(report.notes or {}) do bits[#bits + 1] = n end
        S.pvNotice = table.concat(bits, " - ")
      else
        S.pvNotice = tostring(why)
      end
      -- STILL HELD after placing, because a row of fence posts is the same
      -- asset put down six times. Escape or the library puts it down.
      return true
    end
  end
  -- THE COLLISION BRUSH, when that tool is the open one. Before the tile
  -- painter's test rather than after it, because the two are different tools
  -- and only one drawer is open at a time -- ordering them by which is checked
  -- first is what keeps a click meaning one thing.
  if Sidebar and Sidebar.openId(S) == "collision" then
    local okC, Collision = pcall(require, "tools.map-editor.panels.Collision")
    if okC and type(Collision) == "table" and Collision.paintAt then
      return Collision.paintAt(S, cx, cy)
    end
    return false
  end
  if not (Sidebar and Sidebar.openId(S) == "tiles") then return false end
  local ok, Tiles = pcall(require, "tools.map-editor.panels.Tiles")
  if not (ok and type(Tiles) == "table") then return false end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]

  if S.tileMode == "pick" then
    -- THE EYEDROPPER. Matching ground you can see beats hunting the palette
    -- for it, and on a tileset of two hundred blocks it is the difference
    -- between a tool and a puzzle.
    if def and def.blocks then
      S.tilePick = def.blocks[by * def.width + bx + 1]
      -- and the QUADRANT under the pointer with it, so the eyedropper hands
      -- back the 16px square you pointed at rather than the 32px block it
      -- happens to sit in -- which is the unit the brush paints in.
      S.tilePickQ = (cx % 2) + (cy % 2) * 2
      -- WHAT WAS PICKED IS NOW A BLOCK OF THIS MAP'S OWN TILESET, whatever it
      -- was picked FROM before. Leaving the foreign marker on would keep the
      -- palette ringing a swatch in another tileset while the brush carried a
      -- local id -- the two disagreeing is exactly the state this field exists
      -- to prevent.
      S.tilePickSrc = nil
      S.tileNotice = string.format("picked block %s, %s cell",
        tostring(S.tilePick), ({ [0] = "NW", "NE", "SW", "SE" })[S.tilePickQ])
    end
    return true
  end
  if S.tilePick == nil then
    S.pvNotice = "pick a block in the TILES palette first"
    return true
  end
  if S.tileMode == "fill" then
    -- Fill stays at BLOCK granularity whatever the paint grain is: it is the
    -- bulk tool, and a flood that had to mint a block per cell would mint four
    -- hundred of them for one room.
    local n = Tiles.fill(S, bx, by, S.tilePick)
    S.tileNotice = string.format("filled %d blocks", n)
  elseif (S.tileGrain or "cell") == "cell" then
    -- THE CELL UNDER THE POINTER, not the block around it. Painting a block
    -- changed a 2x2 area snapped to the block grid, so a click at cell (5,3)
    -- repainted cells (4..5, 2..3) -- up and to the left of the pointer.
    Tiles.paintCell(S, cx, cy, S.tilePick, nil, S.tilePickQ)
  else
    Tiles.paint(S, bx, by, S.tilePick)
  end
  return true
end

-- Is a left-drag a paint stroke rather than a pan?
--
-- Only while the painter is the open tool and in PAINT mode. Fill on a drag
-- would flood once per cell crossed, which on a route is a hundred floods and
-- an editor that has stopped responding; pick on a drag would end holding
-- whatever the pointer happened to be over when it stopped.
function Preview.painting(S)
  -- NOT while holding an asset: a drag would stamp a house per cell crossed,
  -- which on a route is two hundred houses and an editor that has stopped
  -- responding. One click, one building.
  if S.assetPlacing then return false end
  -- A COLLISION EDIT IS A STROKE TOO. Walling off a cliff edge is thirty
  -- cells in a line, and clicking each one is the difference between a tool
  -- and a chore.
  if Sidebar and Sidebar.openId(S) == "collision" then return true end
  return Sidebar and Sidebar.openId(S) == "tiles"
    and (S.tileMode or "paint") == "paint" and S.tilePick ~= nil
end

-- CTRL-CLICK TAKES EVERYTHING LIKE IT THAT TOUCHES IT.
--
-- Selecting a lake, a plaza or the inside of a room a cell at a time is the
-- kind of work that makes a tool not worth reaching for -- and the region is
-- already there in the data: a flood over cells drawing the same BLOCK is
-- exactly the shape somebody means by "this bit of ground".
--
-- On the block, not on the voxel class or the collision byte: the block is
-- what the map is made of and what the eye is reading. Four-neighbour, because
-- two areas meeting at a corner are two areas -- the same rule the structure
-- flood uses, for the same reason.
--
-- Capped at the map's own area, so a bug can stop rather than hang.
function Preview.selectLike(S, cx, cy)
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  if not (def and def.blocks and def.width and def.height) then return 0 end
  local wB, hB = def.width, def.height
  local wC, hC = wB * 2, hB * 2
  if cx < 0 or cy < 0 or cx >= wC or cy >= hC then return 0 end
  local function blockAt(px, py)
    return def.blocks[math.floor(py / 2) * wB + math.floor(px / 2) + 1]
  end
  local want = blockAt(cx, cy)
  if want == nil then return 0 end

  S.pvSel = S.pvSel or {}
  local seen, stack, n = {}, { { cx, cy } }, 0
  seen[cy * wC + cx] = true
  local cap = wC * hC
  while #stack > 0 and n < cap do
    local p = table.remove(stack)
    local px, py = p[1], p[2]
    if blockAt(px, py) == want then
      S.pvSel[selKey(px, py)] = true
      n = n + 1
      local nb = { { px + 1, py }, { px - 1, py }, { px, py + 1 }, { px, py - 1 } }
      for _, q in ipairs(nb) do
        local qx, qy = q[1], q[2]
        if qx >= 0 and qy >= 0 and qx < wC and qy < hC
           and not seen[qy * wC + qx] then
          seen[qy * wC + qx] = true
          stack[#stack + 1] = q
        end
      end
    end
  end
  S.pvCell = { cx = cx, cy = cy }
  return n
end

-- `additive` is the shift key. Without it a click REPLACES the selection,
-- which is what a click means everywhere else; with it the cell is toggled, so
-- the same gesture that adds a cell takes one back out.
function Preview.selectCell(S, cx, cy, additive)
  if not additive then
    S.pvSel = nil
    S.pvCell = { cx = cx, cy = cy }
    return
  end
  S.pvSel = S.pvSel or {}
  -- the primary joins the set the moment a second cell does, or extending a
  -- selection would silently drop the cell it started from
  if S.pvCell then S.pvSel[selKey(S.pvCell.cx, S.pvCell.cy)] = true end
  local key = selKey(cx, cy)
  if S.pvSel[key] then
    S.pvSel[key] = nil
    if S.pvCell and S.pvCell.cx == cx and S.pvCell.cy == cy then
      -- the primary was removed: hand it to whatever is left, or to nothing
      local rest = Preview.selection(S)
      S.pvCell = rest[1]
    end
  else
    S.pvSel[key] = true
    S.pvCell = { cx = cx, cy = cy }
  end
  if next(S.pvSel) == nil then S.pvSel = nil end
end

-- A DOUBLE CLICK ON A DOOR WALKS THROUGH IT.
--
-- Warps are the one thing on a map that point somewhere else, and following
-- one meant reading its destination off the warp list, finding that name in a
-- hundred-entry area list, and clicking it -- for the operation the map itself
-- is a picture of. Double-clicking a door is what everybody tries first.
--
-- The destination WARP is selected on arrival too, not just the map: a door
-- leads to a specific doorway, and landing on the far map with nothing chosen
-- leaves you hunting for the other end of the thing you just followed.
local function warpAtCell(S, cx, cy)
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  for i, wp in ipairs((def and def.warps) or {}) do
    if wp.x == cx and wp.y == cy and wp.x >= 0 and wp.y >= 0 then
      return i, wp
    end
  end
  return nil
end

local function followWarp(S, cx, cy)
  local i, wp = warpAtCell(S, cx, cy)
  if not wp then return false end
  local dest = wp.destMap
  if not dest or dest == "" then
    S.pvNotice = string.format("warp %d has no destination yet", i)
    return true
  end
  if not (S.data and S.data.maps and S.data.maps[dest]) then
    -- NAMED BUT NOT PRESENT is a real state -- a warp into a map this import
    -- does not carry -- and saying so is more use than doing nothing.
    S.pvNotice = string.format("warp %d points at %s, which is not in this import",
                               i, tostring(dest))
    return true
  end
  Preview.select(S, dest)
  S.warpSelected = tonumber(wp.destWarp) or 1
  -- ...and put the camera on the doorway we arrived at, so the far side of the
  -- door is what is on screen rather than the middle of the map.
  local ddef = S.data.maps[dest]
  local dw = ddef.warps and ddef.warps[S.warpSelected]
  if dw and dw.x and dw.y and dw.x >= 0 then
    S.pvCell = { cx = dw.x, cy = dw.y }
    centerOn(S, dw.x, dw.y)
    S._pvCenteredFor = dest
  end
  S.pvNotice = string.format("followed warp %d to %s", i, tostring(dest))
  return true
end

-- Clicking a person selects that person -- and opens the tool that edits one.
--
-- The drawer is opened rather than merely armed because the click has already
-- said what it wants: you pointed at an NPC. Opening the NPC tool is the
-- answer to that, and having to then find the button is the editor making you
-- say it twice. If the drawer is already showing another tool it is left
-- alone -- someone who is on SCRIPTS and clicks a person is picking WHOSE
-- script, not asking to leave.
local function selectObjectAt(S, cx, cy)
  local i = objectAt(S, cx, cy)
  if not i then return false end
  S.objSelected = i
  S.objScroll = math.max(0, i - 4)
  if Sidebar then
    local open = Sidebar.openId(S)
    if open == nil then
      Sidebar.open(S, "objects")
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- flying the camera
-- ---------------------------------------------------------------------------
--
-- WASD MOVES THROUGH THE SCENE; the mouse still orbits and the arrows still
-- turn. The orbit is right for looking AT something and wrong for getting
-- somewhere: a map is twenty blocks across and the only way over there was to
-- pan with the right button, in screen space, at whatever angle the camera
-- happened to be at.
--
-- POLLED, NOT KEY-EVENTS. A held key repeats at whatever rate the OS decides
-- -- typically a pause and then a burst -- so movement built on `keypressed`
-- lurches. This asks which keys are down once a frame and moves by dt, which
-- is the difference between flying and stuttering.
--
-- IT MOVES THE FOCUS, NOT THE EYE. The camera is an orbit: a focus point, a
-- distance and two angles. Translating the focus carries the eye with it and
-- leaves the framing alone, so flying forward does not also tilt or spin --
-- and `F` still frames the selection afterwards, because the selection did not
-- move.
local FLY_SPEED = 260          -- world px/s, about sixteen cells a second
local FLY_FAST = 3.0           -- shift
local FLY_SLOW = 0.25          -- alt, for placing the camera exactly

local function flyCamera(S, Kit)
  if not (S.pv3DActive and S.pvFocus) then return false end
  local kb = love.keyboard and love.keyboard.isDown
  if not kb then return false end
  -- A FOCUSED TEXT FIELD OWNS THE LETTERS. Typing a map name into the new-map
  -- form must not fly the camera across the world, and Kit is the only thing
  -- that knows whether a field has focus.
  if Kit.focus ~= nil then return false end

  local fwd, strafe, lift = 0, 0, 0
  if kb("w") then fwd = fwd + 1 end
  if kb("s") then fwd = fwd - 1 end
  if kb("d") then strafe = strafe + 1 end
  if kb("a") then strafe = strafe - 1 end
  -- E and Q rise and fall, which is the other half of getting somewhere in a
  -- world with height in it -- and the pair every editor with a fly camera
  -- uses for it.
  if kb("e") then lift = lift + 1 end
  if kb("q") then lift = lift - 1 end
  if fwd == 0 and strafe == 0 and lift == 0 then return false end

  local dt = (love.timer and love.timer.getDelta and love.timer.getDelta()) or 0
  -- CLAMPED. A frame that took a second -- the first one after a mesh rebuild,
  -- or the window coming back from being dragged -- would otherwise throw the
  -- camera a quarter of the way across the map in one step.
  dt = math.max(0, math.min(dt, 1 / 15))
  local speed = FLY_SPEED
  if kb("lshift", "rshift") then speed = speed * FLY_FAST end
  if kb("lalt", "ralt") then speed = speed * FLY_SLOW end
  local step = speed * dt

  -- ON THE GROUND PLANE. `Viewport3D.basis` gives the true forward, which
  -- points DOWN at the pitch the camera is at -- so flying forward would also
  -- fly into the floor, and holding W would end underground. The heading is
  -- the yaw alone; E and Q are what move you up.
  local yaw = S.pvYaw or 0
  local fx, fz = -math.sin(yaw), -math.cos(yaw)
  local rx, rz = -fz, fx

  local f = S.pvFocus
  f.x = (f.x or 0) + (fx * fwd + rx * strafe) * step
  f.z = (f.z or 0) + (fz * fwd + rz * strafe) * step
  f.y = (f.y or 0) + lift * step
  -- a moved camera is no longer looking from one of the named presets
  S.pvViewName = nil
  return true
end

Preview.flyCamera = flyCamera

-- Everything the editor can change, drawn over the map it changes. Order is
-- deliberate and the same one MapBrowser uses: the selection is painted last
-- so it always wins, because it is the thing being pointed at right now.
-- THE WALKABLE WASH AND THE EVENT TILES, ON THE 3D PICTURE.
--
-- Projected per cell through the same camera the viewport rendered with, and
-- painted at the height the cell stands at rather than on the ground: a wash
-- at y = 0 under a building is under the building, and the one thing an
-- overlay has to do is be visible over the thing it describes.
--
-- ONLY THE CELLS THAT MATTER. A route is 40x36 and projecting every one of
-- them every frame is 1440 matrix multiplies for a picture that is mostly
-- walkable floor nobody asked to see -- so the blocked cells are drawn and the
-- open ones only when they were asked for.
local function drawOverlays3D(S, built, vx, vy, vw, vh)
  if not (built and love.graphics.polygon) then return end
  local okV, Viewport3D = pcall(require, "tools.map-editor.Viewport3D")
  if not (okV and type(Viewport3D) == "table" and Viewport3D.cellQuad) then
    return
  end

  if S.collShow then
    local okC, MapCollision = pcall(require, "tools.map-editor.MapCollision")
    local grid = okC and type(MapCollision) == "table" and MapCollision.grid(S)
      or nil
    if grid then
      for cy = 0, grid.h - 1 do
        for cx = 0, grid.w - 1 do
          local open = grid.walk[cy * grid.w + cx]
          if (not open) or S.collShowOpen then
            local q = Viewport3D.cellQuad(S, built, cx, cy, vx, vy, vw, vh)
            if q then
              if open then
                love.graphics.setColor(0.30, 0.85, 0.45, 0.20)
              else
                love.graphics.setColor(0.95, 0.28, 0.32, 0.38)
              end
              love.graphics.polygon("fill", q)
            end
          end
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  local okE, MapEvents = pcall(require, "tools.map-editor.MapEvents")
  if okE and type(MapEvents) == "table" and MapEvents.cartridgeEvents then
    local okC, cart = pcall(MapEvents.cartridgeEvents, S, S.mapId)
    for _, c in ipairs((okC and type(cart) == "table") and cart or {}) do
      if c.kind == "coord" and c.x and c.y then
        local q = Viewport3D.cellQuad(S, built, c.x, c.y, vx, vy, vw, vh)
        if q then
          love.graphics.setColor(0.35, 0.62, 1.0, 0.24)
          love.graphics.polygon("fill", q)
          love.graphics.setColor(0.45, 0.70, 1.0, 0.75)
          love.graphics.polygon("line", q)
        end
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  if okE and type(MapEvents) == "table" and MapEvents.list then
    local okL, list = pcall(MapEvents.list, S, S.mapId)
    for _, ev in ipairs((okL and type(list) == "table") and list or {}) do
      if ev.x and ev.y then
        local q = Viewport3D.cellQuad(S, built, ev.x, ev.y, vx, vy, vw, vh)
        if q then
          local live = #(ev.beats or {}) > 0
          if live then
            love.graphics.setColor(0.72, 0.45, 1.0, 0.34)
            love.graphics.polygon("fill", q)
          end
          love.graphics.setColor(0.78, 0.55, 1.0, live and 0.95 or 0.55)
          love.graphics.setLineWidth(2)
          love.graphics.polygon("line", q)
          love.graphics.setLineWidth(1)
        end
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
end

local function drawOverlays(S, map, Kit)
  local function rect(cx, cy)
    return cx * CELL - (S.pvCamX or 0), cy * CELL - (S.pvCamY or 0), CELL, CELL
  end
  local def = map.def

  -- WHERE THE PLAYER CAN WALK, under everything else.
  --
  -- FIRST, so warps, NPCs and the selection all read over it: this is a tint
  -- on the ground, not a thing standing on it. Only the cells actually on
  -- screen are painted -- a route is 40x36 cells and filling all of them every
  -- frame while panning is a lot of rectangles for a picture that is mostly
  -- off the edge.
  --
  -- BLOCKED IS THE ONE THAT IS PAINTED SOLID. A map is mostly walkable, so
  -- tinting the walkable half would put a wash over the whole screen and hide
  -- the art the collision is supposed to be checked against. The walls are the
  -- answer being looked for.
  if S.collShow then
    local okC, MapCollision = pcall(require, "tools.map-editor.MapCollision")
    local grid = okC and type(MapCollision) == "table" and MapCollision.grid(S)
      or nil
    if grid then
      local camX, camY = S.pvCamX or 0, S.pvCamY or 0
      local z = S.pvZoom or 2
      local vw = (S._pvViewW or 640) / z
      local vh = (S._pvViewH or 480) / z
      local x0 = math.max(0, math.floor(camX / CELL))
      local y0 = math.max(0, math.floor(camY / CELL))
      local x1 = math.min(grid.w - 1, x0 + math.ceil(vw / CELL) + 1)
      local y1 = math.min(grid.h - 1, y0 + math.ceil(vh / CELL) + 1)
      for cy = y0, y1 do
        for cx = x0, x1 do
          local open = grid.walk[cy * grid.w + cx]
          local rx, ry, rw, rh = rect(cx, cy)
          if open then
            if S.collShowOpen then
              love.graphics.setColor(0.30, 0.85, 0.45, 0.16)
              love.graphics.rectangle("fill", rx, ry, rw, rh)
            end
          else
            love.graphics.setColor(0.95, 0.28, 0.32, 0.34)
            love.graphics.rectangle("fill", rx, ry, rw, rh)
            -- AND AN EDGE WHERE THE BOUNDARY IS. A flat wash says which cells
            -- are blocked; the line says where the WALL is, which is the thing
            -- being drawn when somebody maps a boundary.
            love.graphics.setColor(0.95, 0.28, 0.32, 0.75)
            if grid.walk[cy * grid.w + cx - 1] or cx == 0 then
              love.graphics.line(rx, ry, rx, ry + rh)
            end
            if grid.walk[cy * grid.w + cx + 1] or cx == grid.w - 1 then
              love.graphics.line(rx + rw, ry, rx + rw, ry + rh)
            end
            if grid.walk[(cy - 1) * grid.w + cx] or cy == 0 then
              love.graphics.line(rx, ry, rx + rw, ry)
            end
            if grid.walk[(cy + 1) * grid.w + cx] or cy == grid.h - 1 then
              love.graphics.line(rx, ry + rh, rx + rw, ry + rh)
            end
          end
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- EVENT TILES, drawn the way warps are and for the same reason.
  --
  -- AN EVENT TILE IS NOT A TILE. Nothing about the ground changes -- exactly
  -- as a warp changes nothing about the square it sits on -- so there is
  -- nothing to see unless the editor draws it, and an invisible trigger is a
  -- map that behaves in ways nobody can account for by looking at it. Shown
  -- always, not only while the event tool is open: walking a map and finding
  -- out where its triggers are is the commonest reason to want them drawn, and
  -- that happens while some other tool is in hand.
  do
    local okE, MapEvents = pcall(require, "tools.map-editor.MapEvents")
    -- THE CARTRIDGE'S OWN TRIGGERS, in a colour of their own and under the
    -- authored ones. Azalea Town has three; nothing in the editor said so, and
    -- placing an event tile on top of one is how you get two scripts fighting
    -- over the same square with no sign that anything is wrong.
    if okE and type(MapEvents) == "table" and MapEvents.cartridgeEvents then
      local okC, cart = pcall(MapEvents.cartridgeEvents, S, S.mapId)
      for _, c in ipairs((okC and type(cart) == "table") and cart or {}) do
        if c.kind == "coord" and c.x and c.y then
          local rx, ry, rw, rh = rect(c.x, c.y)
          love.graphics.setColor(0.35, 0.62, 1.0, 0.20)
          love.graphics.rectangle("fill", rx, ry, rw, rh)
          love.graphics.setColor(0.45, 0.70, 1.0, 0.70)
          love.graphics.rectangle("line", rx + 1, ry + 1, rw - 2, rh - 2)
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
    if okE and type(MapEvents) == "table" and MapEvents.list then
      local okL, list = pcall(MapEvents.list, S, S.mapId)
      if okL and type(list) == "table" then
        for _, ev in ipairs(list) do
          if ev.x and ev.y then
            local rx, ry, rw, rh = rect(ev.x, ev.y)
            local live = #(ev.beats or {}) > 0
            -- AN EVENT WITH NO BEATS IS DRAWN DIFFERENTLY, because it is the
            -- commonest half-finished state -- a tile placed and not yet
            -- filled in -- and it does nothing at all when the player crosses
            -- it. A hollow marker says "not wired up" without a word.
            if live then
              love.graphics.setColor(0.72, 0.45, 1.0, 0.30)
              love.graphics.rectangle("fill", rx, ry, rw, rh)
            end
            love.graphics.setColor(0.78, 0.55, 1.0, live and 0.95 or 0.55)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", rx + 1, ry + 1, rw - 2, rh - 2)
            love.graphics.setLineWidth(1)
            -- and the one being edited, ringed, so the popup and the map are
            -- pointing at the same square
            if S.eventEditing == ev.id then
              love.graphics.setColor(1, 0.95, 0.4, 1)
              love.graphics.setLineWidth(2)
              love.graphics.rectangle("line", rx - 2, ry - 2, rw + 4, rh + 4)
              love.graphics.setLineWidth(1)
            end
          end
        end
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end

  -- THE GHOST OF WHAT IS BEING HELD, at the cell under the pointer.
  --
  -- Drawn FIRST so everything else -- warps, NPCs, the selection -- still
  -- reads over it: this is a preview of a thing that is not there yet, and it
  -- must not hide what is. Every cell of the footprint is outlined rather than
  -- just its bounding box, because an asset can be L-shaped and the difference
  -- between "this covers the corner" and "this does not" is the whole reason
  -- to look before clicking.
  if S.assetPlacing and S.pvHover then
    local okA, MapAssets = pcall(require, "tools.map-editor.MapAssets")
    local asset = okA and MapAssets.armed(S) or nil
    if asset then
      local hx, hy = S.pvHover.cx, S.pvHover.cy
      for key in pairs(asset.cells or {}) do
        local dx, dy = key:match("^(%-?%d+),(%-?%d+)$")
        if dx then
          local rx, ry, rw, rh = rect(hx + tonumber(dx), hy + tonumber(dy))
          love.graphics.setColor(0.35, 0.9, 1, 0.28)
          love.graphics.rectangle("fill", rx, ry, rw, rh)
          love.graphics.setColor(0.35, 0.9, 1, 0.8)
          love.graphics.rectangle("line", rx, ry, rw, rh)
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- block edits: the ground itself was changed here
  local m = MapEdits.bucket(store(S), game(S), S.mapId, false)
  if S.pvShowVoxels == false then m = nil end
  for key in pairs((m and m.blocks) or {}) do
    local bx, by = key:match("^(-?%d+),(-?%d+)$")
    if bx then
      love.graphics.setColor(1, 0.55, 0.1, 0.22)
      love.graphics.rectangle("fill",
        tonumber(bx) * 2 * CELL - (S.pvCamX or 0),
        tonumber(by) * 2 * CELL - (S.pvCamY or 0), CELL * 2, CELL * 2)
    end
  end

  -- voxel overrides
  for key in pairs((m and m.voxels) or {}) do
    local cx, cy = key:match("^(-?%d+),(-?%d+)$")
    if cx then
      love.graphics.setColor(0.6, 0.4, 1, 0.35)
      love.graphics.rectangle("fill", rect(tonumber(cx), tonumber(cy)))
    end
  end

  -- warps. A blanked warp is parked off-map at -1,-1 on purpose, so it is
  -- skipped rather than drawn in the corner where it would look like a door.
  for i, w in ipairs(S.pvShowWarps ~= false and (def.warps or {}) or {}) do
    if w.x and w.y and w.x >= 0 and w.y >= 0 then
      love.graphics.setColor(0.27, 0.59, 1, w.added and 0.95 or 0.6)
      love.graphics.rectangle("line", rect(w.x, w.y))
      if (S.pvZoom or 2) >= 2 then
        love.graphics.setColor(0.27, 0.59, 1, 0.9)
        love.graphics.print(tostring(i), w.x * CELL - (S.pvCamX or 0) + 2,
                            w.y * CELL - (S.pvCamY or 0) + 1)
      end
    end
  end

  -- objects, filled so they read as things standing on the map rather than
  -- regions of it; an edited or added one is brighter than a cartridge one
  for i, o in ipairs(S.pvShowObjects ~= false and (def.objects or {}) or {}) do
    if o.x and o.y then
      local ox, oy = rect(o.x, o.y)
      local image, quad, sw, sh, flip = spriteQuadFor(S, o.sprite, o.range)
      if image then
        -- A sprite taller than a cell stands ON its cell rather than in it:
        -- that is where the game puts it, and an editor that centres it
        -- instead would have every NPC a row north of where it really is.
        love.graphics.setColor(1, 1, 1, 1)
        -- RIGHT is LEFT mirrored, which is a negative x scale -- and the
        -- origin travels with it, or the sprite draws one width to the left of
        -- the cell it stands on.
        local sx = (flip or 1) < 0 and -1 or 1
        local dx = ox + (CELL - sw) / 2 + (sx < 0 and sw or 0)
        love.graphics.draw(image, quad, dx, oy + CELL - sh, 0, sx, 1)
      else
        -- No sheet: the old box, which at least says something is here. A
        -- missing sprite is a real state -- a partial import, a mod's own id
        -- -- and drawing nothing would hide an object you can still click.
        love.graphics.setColor(1, 1, 1, 0.32)
        love.graphics.rectangle("fill", ox, oy, CELL, CELL)
      end
      -- A RING ONLY WHERE IT SAYS SOMETHING. It used to be drawn round every
      -- object, white, on every one the cartridge shipped -- so a town was a
      -- grid of white boxes with people faintly inside them, and the ring that
      -- was supposed to mean "this one is edited" meant nothing because
      -- everything had one. Added and edited keep theirs; a cartridge object
      -- is just the person.
      if o.added then
        love.graphics.setColor(0.24, 0.88, 0.54, 0.95)
        love.graphics.rectangle("line", ox, oy, CELL, CELL)
      elseif o.edited then
        love.graphics.setColor(1, 0.8, 0.02, 0.9)
        love.graphics.rectangle("line", ox, oy, CELL, CELL)
      end
      -- and the one being edited gets its number, so the NPC drawer's list and
      -- the map agree about which person is which
      if S.objSelected == i then
        love.graphics.setColor(0.24, 0.88, 0.54, 1)
        love.graphics.rectangle("line", ox - 1, oy - 1, CELL + 2, CELL + 2)
      end
    end
  end

  -- THE WHOLE SELECTION, IN YELLOW, ALL OF IT.
  --
  -- A faint outline on the extras and a bright one on the primary read as one
  -- selected cell and some hover marks -- which is exactly wrong when the
  -- point of the set is that a bulk action is about to change every one of
  -- them. They are filled as well as ringed: on a busy town an outline is lost
  -- among the artwork, and "which cells am I about to raise" is a question
  -- that has to be answerable at a glance.
  for key in pairs(S.pvSel or {}) do
    local kx, ky = key:match("^(-?%d+),(-?%d+)$")
    if kx then
      local rx, ry, rw, rh = rect(tonumber(kx), tonumber(ky))
      love.graphics.setColor(1, 1, 0.35, 0.28)
      love.graphics.rectangle("fill", rx, ry, rw, rh)
      love.graphics.setColor(1, 1, 0.35, 0.9)
      love.graphics.rectangle("line", rx, ry, rw, rh)
    end
  end
  if S.pvCell then
    local rx, ry, rw, rh = rect(S.pvCell.cx, S.pvCell.cy)
    -- The primary is the same yellow with a second ring inside it, not a
    -- different colour: it is one OF the selection, and colouring it apart
    -- would say it is a different kind of thing.
    love.graphics.setColor(1, 1, 0.35, 0.28)
    love.graphics.rectangle("fill", rx, ry, rw, rh)
    love.graphics.setColor(1, 1, 0.35, 1)
    love.graphics.rectangle("line", rx, ry, rw, rh)
    if S.pvSel and next(S.pvSel) then
      love.graphics.rectangle("line", rx + 2, ry + 2, rw - 4, rh - 4)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- the selected cell
-- ---------------------------------------------------------------------------

-- Writing a block writes it twice, to the live def and to the store, for the
-- same reason every other panel does: the live table is what the next frame
-- draws and what MapLoader will build from, and the store is what survives.
local function setBlock(S, bx, by, id)
  local def = S.data.maps[S.mapId]
  if not (def and def.blocks and bx >= 0 and by >= 0
          and bx < def.width and by < def.height) then
    return false
  end
  MapEdits.setBlock(store(S), game(S), S.mapId, bx, by, id)
  def.blocks[by * def.width + bx + 1] = id
  markEdited(S)
  -- The map is cached by MapLoader and its renderer holds the old blocks, so
  -- the change would not appear until the map was reopened. Evicting is the
  -- only honest response: an editor that shows you yesterday's ground while
  -- you paint today's is worse than one that stutters.
  pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
  S._pvCenteredFor = S.mapId   -- keep the camera; only the art changed
  return true
end

-- EVERY SELECTED CELL, and by the same STEP rather than to the same value.
--
-- The cell card in the tools column wrote to `S.pvCell` and nothing else, so
-- shift-selecting six cells and pressing HEIGHT moved one of them -- the last
-- one clicked -- and left the other five where they were. The selection was
-- being drawn, the bulk buttons on the voxel tab honoured it, and this, the
-- control nearest to hand, quietly did not.
--
-- Stepping rather than assigning matters as much as looping does: a run of
-- stairs selected together should stay a run of stairs when it is nudged up.
-- Levelling a selection is what the class picker and the brush are for.
local function setVoxelAll(S, patch, delta)
  local cells = Preview.selection(S)
  if #cells == 0 then return 0 end
  local st, g = store(S), game(S)
  local m = MapEdits.bucket(st, g, S.mapId, false)
  for _, c in ipairs(cells) do
    if patch == nil then
      MapEdits.setVoxel(st, g, S.mapId, c.cx, c.cy, nil)
    else
      local own = m and m.voxels and m.voxels[c.cx .. "," .. c.cy]
      local next_ = { art = patch.art, h = patch.h }
      if delta then
        -- each cell moves from ITS OWN height, which is the whole point of a
        -- step; a cell with no override of its own starts from what the
        -- profile resolves it to rather than from the primary's number
        local base = own and tonumber(own.h)
        if not base then
          local _, ph = voxelAt(S, S.data.maps[S.mapId], c.cx, c.cy, nil)
          base = ph or 0
        end
        next_.h = base + delta
        next_.art = (own and own.art) or patch.art
      end
      MapEdits.setVoxel(st, g, S.mapId, c.cx, c.cy, next_)
    end
  end
  markEdited(S)
  return #cells
end

local function setVoxel(S, cx, cy, patch)
  MapEdits.setVoxel(store(S), game(S), S.mapId, cx, cy, patch)
  markEdited(S)
end

-- The four 8px tile slots a 16px CELL occupies inside its 32x32 block, and the
-- collision slot that goes with them.
--
-- A block is a 4x4 grid of tiles indexed `(ty % 4) * 4 + (tx % 4) + 1` (that is
-- Map:tileAt), and its four collision classes are in NW/NE/SW/SE order at
-- `blockId * 4 + (cx % 2) + (cy % 2) * 2 + 1` (Map:cellTile). A cell is one
-- quadrant of that: two tile columns by two tile rows.
local function cellSlots(cx, cy)
  local qx, qy = cx % 2, cy % 2
  local slots = {}
  for r = 0, 1 do
    for c = 0, 1 do
      slots[#slots + 1] = (qy * 2 + r) * 4 + (qx * 2 + c) + 1
    end
  end
  return slots, qx + qy * 2 + 1
end

-- Repaint ONE CELL by minting a block that differs only in that quadrant.
--
-- The map has no per-cell art -- it stores a block id per 32x32 block -- so
-- stepping the block id repainted all four cells, which is the "+ changes a
-- 4x4 square" this fixes. Copying the block and swapping one quadrant gives
-- the cell its own drawing while its three neighbours keep theirs, because
-- they are still the same drawing; only the block carrying them is new.
--
-- `dir` steps every tile in the quadrant by one, which is what a nudge through
-- a tileset means when the unit is a group of four 8px tiles.
local function stepCellArt(S, cx, cy, dir)
  local def = S.data.maps[S.mapId]
  local ts = S.data and S.data.tilesets and S.data.tilesets[def.tileset]
  if not (ts and type(ts.blocks) == "table") then
    S.pvNotice = "this tileset has no block table to edit"
    return false
  end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then return false end
  local blockId = def.blocks[by * def.width + bx + 1] or 0
  local block = ts.blocks[blockId + 1]
  if not block then
    S.pvNotice = "block " .. tostring(blockId) .. " is not in this tileset"
    return false
  end

  local tiles, coll = {}, {}
  for i = 1, 16 do tiles[i] = block[i] or 0 end
  for q = 1, 4 do
    coll[q] = (ts.collision and ts.collision[blockId * 4 + q]) or 0
  end

  local maxTile = math.max(0, math.floor(
    ((ts.imageWidth or 128) / 8) * ((ts.imageHeight or 128) / 8)) - 1)
  local slots, cq = cellSlots(cx, cy)
  for _, i in ipairs(slots) do
    tiles[i] = math.max(0, math.min(maxTile, (tiles[i] or 0) + dir))
  end

  local key = MapEdits.mintBlock(store(S), game(S), def.tileset, tiles, coll)
  if not key then
    S.pvNotice = "could not mint a tile for this cell"
    return false
  end
  MapEdits.setBlock(store(S), game(S), S.mapId, bx, by, key)
  -- Live side: append it here too so the very next frame draws it. applyAll
  -- would do the same on the next load, and doing both is what keeps the
  -- editor showing the thing it just saved.
  local copy = {}
  for i = 1, 16 do copy[i] = tiles[i] end
  ts.blocks[#ts.blocks + 1] = copy
  local newId = #ts.blocks - 1
  if type(ts.collision) == "table" then
    for q = 1, 4 do ts.collision[newId * 4 + q] = coll[q] end
  end
  def.blocks[by * def.width + bx + 1] = newId
  markEdited(S)
  pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
  S.pvNotice = string.format("cell %d,%d now uses minted block %d (quadrant %d)",
                             cx, cy, newId, cq)
  return true
end

-- How many blocks this map's tileset actually has, so the stepper cannot walk
-- off the end into an id the renderer has no metatile for.
local function blockCount(S, def)
  local ts = S.data and S.data.tilesets and S.data.tilesets[def.tileset]
  -- Each `or` falls through on an EMPTY table as well as a missing one. A
  -- tileset whose collision array is empty gave a count of zero, so the
  -- stepper's ceiling was -1 and pressing + wrote block -1 into the map --
  -- an id no metatile answers to, clamped to nothing, saved to the store.
  local n = (ts and ts.blocks and #ts.blocks) or 0
  if n == 0 then n = (ts and ts.collision and math.floor(#ts.collision / 4)) or 0 end
  if n == 0 then n = 256 end
  return n
end

function Preview.drawCellCard(S, Kit, x, y, w)
  local s = Kit.scale
  local fieldH = 28 * s
  Kit.caption(x, y, "SELECTED CELL")
  y = y + Kit.textHeight("caption") + 8 * s

  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  if not (def and S.pvCell) then
    Kit.text("small", "click a cell on the map to edit it", x, y, PAL.muted)
    return y + 26 * s
  end

  local cx, cy = S.pvCell.cx, S.pvCell.cy
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local cls, blockId = cellClass(S, def, cx, cy)

  if S.pvView == "voxel" then
    -- The voxel view edits the CELL; the 2D view edits the BLOCK under it.
    -- Same selection, different unit, because that is what each view is
    -- showing: a block is four cells and painting one from the voxel view
    -- would move three cells nobody pointed at.
    local class, h, from = voxelAt(S, def, cx, cy, cls)
    local edits = MapEdits.bucket(store(S), game(S), S.mapId, false)
    local o = edits and edits.voxels and edits.voxels[cx .. "," .. cy]

    Kit.text("small", string.format("cell %d,%d  -  %s", cx, cy,
             from == "override" and "your override" or "from the profile"),
             x, y, PAL.muted)
    y = y + 18 * s

    local names, info = classInfo(S)
    Kit.text("body", "ART", x, y + 6 * s)
    if Kit.button(x + 54 * s, y, w - 54 * s, fieldH, tostring(class)) then
      S.pvClassOpen = not S.pvClassOpen
      S.pvClassQuery = ""
      S.pvClassScroll = 0
    end
    y = y + fieldH + 4 * s
    do
      local spec = info[class]
      Kit.text("small", spec
        and string.format("folds %s, class height %d%s", spec.art, spec.h,
              spec.tileset and " (this tileset)" or "")
        or "TileShape does not know this class", x, y, PAL.muted)
      y = y + 16 * s + 4 * s
    end

    -- THE PICKER IS A POPUP, AND IT IS DEFERRED. See Preview.drawDeferred.
    --
    -- It used to open INSIDE this card: five rows, everything below pushed
    -- down, and the rest of the forty classes behind "N more - keep typing".
    -- Three things were wrong with that and they are one thing. The list could
    -- not be scrolled, so a class you could not name was a class you could not
    -- reach. It grew the card while the column below it -- the notice, SAVE
    -- ALL EDITS -- is anchored to the bottom of the panel, so the rows printed
    -- straight through them. And five of forty is not a picker, it is a
    -- search box with a preview.
    --
    -- Anchored under the button rather than centred: this list is the answer
    -- to "what is that button set to", and a modal in the middle of the screen
    -- loses the connection to the thing being changed.
    if S.pvClassOpen then
      S._pvClassMenu = { x = x, y = y, w = w, cx = cx, cy = cy,
                         class = class, h = h }
    else
      S._pvClassMenu = nil
      S.pvClassScroll = 0
    end

    local nSel = Preview.selectionCount(S)
    Kit.text("body", "HEIGHT", x, y + 6 * s)
    if Kit.stepper(x + 54 * s, y, 26 * s, fieldH, "-") then
      setVoxelAll(S, { art = class }, -2)
    end
    Kit.textCenter("body", tostring(h), x + 80 * s, y + 6 * s, 44 * s)
    if Kit.stepper(x + 124 * s, y, 26 * s, fieldH, "+") then
      setVoxelAll(S, { art = class }, 2)
    end
    if (o or nSel > 1)
       and Kit.button(x + 158 * s, y, w - 158 * s, fieldH, "CLEAR") then
      setVoxelAll(S, nil)
    end
    y = y + fieldH + 6 * s
    -- SAYING SO, because a control that quietly acts on six things when the
    -- panel above it is describing one is the same surprise in the other
    -- direction.
    if nSel > 1 then
      Kit.text("small", string.format(
        "%d cells selected - height and class move all of them", nSel),
        x, y, PAL.yellow)
      y = y + 16 * s
    end
    return y + 6 * s
  end

  Kit.text("small", string.format("cell %d,%d  -  block %d,%d  -  class %s",
           cx, cy, bx, by, cls and string.format("$%02X", cls) or "?"),
           x, y, PAL.muted)
  y = y + 18 * s

  -- TILE ART on the SELECTED CELL, not on the block around it. Stepping mints
  -- a block that differs only in this cell's quadrant, so the three cells
  -- sharing the block keep their drawing.
  Kit.text("body", "TILE", x, y + 6 * s)
  if Kit.stepper(x + 54 * s, y, 26 * s, fieldH, "-") then
    stepCellArt(S, cx, cy, -1)
  end
  local _, cq = cellSlots(cx, cy)
  Kit.textCenter("body", "q" .. tostring(cq), x + 80 * s, y + 6 * s, 44 * s)
  if Kit.stepper(x + 124 * s, y, 26 * s, fieldH, "+") then
    stepCellArt(S, cx, cy, 1)
  end
  Kit.text("small", "this cell only", x + 156 * s, y + 7 * s, PAL.muted)
  y = y + fieldH + 6 * s

  -- The whole BLOCK, still steppable, because repainting all four cells at
  -- once is the right tool for laying ground and the wrong one only when it
  -- is the only tool. Named for what it does so the two are not confused.
  local maxBlock = blockCount(S, def) - 1
  Kit.text("body", "BLOCK", x, y + 6 * s)
  if Kit.stepper(x + 54 * s, y, 26 * s, fieldH, "-") then
    setBlock(S, bx, by, math.max(0, (blockId or 0) - 1))
  end
  Kit.textCenter("body", tostring(blockId or 0), x + 80 * s, y + 6 * s, 44 * s)
  if Kit.stepper(x + 124 * s, y, 26 * s, fieldH, "+") then
    setBlock(S, bx, by, math.min(maxBlock, (blockId or 0) + 1))
  end
  Kit.text("small", "all 4 cells", x + 156 * s, y + 7 * s, PAL.muted)
  y = y + fieldH + 6 * s

  -- COPY / PASTE, because stepping to a block you can see somewhere else on
  -- the map is otherwise a hunt through several hundred ids.
  local halfW = (w - 8 * s) / 2
  if Kit.button(x, y, halfW, fieldH, "COPY TILE") then
    S.pvClip = blockId
    S.pvNotice = "copied block " .. tostring(blockId)
  end
  if Kit.button(x + halfW + 8 * s, y, halfW, fieldH,
                S.pvClip and ("PASTE " .. S.pvClip) or "PASTE") then
    if S.pvClip then
      setBlock(S, bx, by, S.pvClip)
    else
      S.pvNotice = "copy a tile first"
    end
  end
  y = y + fieldH + 10 * s

  -- BORDERS. `borderBlock` is what fills every cell outside the rectangle, so
  -- it is what the player sees past the edge of the map -- and until now there
  -- was no way to set it on a map that came out of the ROM.
  Kit.caption(x, y, "BORDER")
  y = y + Kit.textHeight("caption") + 6 * s
  Kit.text("small", string.format("currently block %d", def.borderBlock or 0),
           x, y, PAL.muted)
  y = y + 18 * s
  if Kit.button(x, y, halfW, fieldH, "SET FROM CELL") then
    MapEdits.setMapField(store(S), game(S), S.mapId, "borderBlock", blockId or 0)
    def.borderBlock = blockId or 0
    markEdited(S)
    pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
    S.pvNotice = "border is now block " .. tostring(blockId or 0)
  end
  -- A ring of the border block around the inside edge. What it is FOR: a map
  -- the editor created is a flat rectangle the player can walk straight off,
  -- and the border block outside it is scenery, not a wall -- Gen 2 stops the
  -- player with collision, and collision comes from the blocks in the map. So
  -- a new route needs its own edge laid inside the rectangle.
  if Kit.button(x + halfW + 8 * s, y, halfW, fieldH, "EDGE RING") then
    local id = def.borderBlock or 0
    local n = 0
    for ex = 0, def.width - 1 do
      if setBlock(S, ex, 0, id) then n = n + 1 end
      if setBlock(S, ex, def.height - 1, id) then n = n + 1 end
    end
    for ey = 1, def.height - 2 do
      if setBlock(S, 0, ey, id) then n = n + 1 end
      if setBlock(S, def.width - 1, ey, id) then n = n + 1 end
    end
    S.pvNotice = string.format("%d edge blocks set to %d", n, id)
  end
  return y + fieldH + 12 * s
end

-- ---------------------------------------------------------------------------
-- draw
-- ---------------------------------------------------------------------------

function Preview.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad, gap = 16 * s, 18 * s
  S.pvQuery = S.pvQuery or ""
  S.pvZoom = math.max(1, math.min(4, S.pvZoom or 2))
  S.pvArea = S.pvArea or "ALL AREAS"


  -- The profile edits made on the VOXELS tab have to reach the MESHER, and the
  -- mesher reads VoxelClasses. Binding here is what makes a class height
  -- changed on that tab show up in this viewport rather than only in the row
  -- it was typed into. Idempotent -- the (store, game) pair is compared.
  VoxelClasses.bind(store(S), game(S))

  -- THE VIEWPORT IS THE SAME RECTANGLE AT ALL TIMES.
  --
  -- It used to move whenever anything else did: narrower in 2D than in 3D,
  -- narrower again while a tool was open, and different once more with the
  -- area list hidden. Every one of those is the thing you are looking at
  -- changing size because of something you did somewhere else -- you lose your
  -- place, the camera reframes, and in 3D the canvas and its depth buffer are
  -- thrown away and rebuilt at the new size.
  --
  -- So the columns are sized from the SAME constants whatever the state, the
  -- viewport is what is left over, and hiding a column frees space around it
  -- rather than growing it. `listW` is what the list occupies right now (a
  -- narrow spine when hidden); `listSlot` is the room the layout always
  -- reserves for it, and only the second one moves the map.
  local listSlot = math.max(210 * s, math.min(280 * s, w * 0.21))
  local toolW = math.max(230 * s, math.min(300 * s, w * 0.23))
  local SPINE = 26 * s
  local listW = S.pvListHidden and SPINE or listSlot
  local viewX = x + listSlot + gap
  local viewW = w - listSlot - toolW - 2 * gap

  -- ...and with the list hidden the map slides into the space it left, keeping
  -- its width. That is the one move worth making: it is what the reader asked
  -- for by hiding the list, and the viewport is still the size it was.
  if S.pvListHidden then
    viewX = x + SPINE + gap
  end

  -- ---------------------------------------------------------------- list
  --
  -- HIDEABLE, down to a spine with a chevron on it. The list is how you get to
  -- a map and is dead weight once you are on one -- and on a laptop it is a
  -- fifth of the window spent on a control you last touched five minutes ago.
  Kit.card(x, y, listW, h)
  if S.pvListHidden then
    -- The spine: one tall button, so the whole strip is the target rather than
    -- a chevron you have to hit.
    if Kit.button(x, y, listW, h, ">", { font = "small" }) then
      S.pvListHidden = false
    end
    -- the label runs down the spine's top so the strip says what it opens
    Kit.text("small", "AREAS", x + 3 * s, y + 34 * s, PAL.muted)
  else

  Kit.caption(x + pad, y + pad, "AREAS")
  if Kit.button(x + listW - pad - 24 * s, y + pad - 4 * s, 24 * s, 24 * s, "<",
                { font = "small", radius = 6 * s }) then
    S.pvListHidden = true
  end
  local ly = y + pad + Kit.textHeight("caption") + 8 * s

  -- The area filter is a cycle rather than a second list: a Gen 2 import has
  -- well over a hundred groups, and a list of lists costs more room than it
  -- saves. Typing in the search box is the fast path; this is for browsing.
  local areas = areaList(S)
  if Kit.button(x + pad, ly, listW - 2 * pad, 30 * s,
                Kit.ellipsize("body", S.pvArea, listW - 2 * pad - 20 * s)) then
    local at = 1
    for i, a in ipairs(areas) do if a == S.pvArea then at = i break end end
    S.pvArea = areas[(at % #areas) + 1]
    S.pvScroll = 0
  end
  ly = ly + 30 * s + 6 * s

  S.pvQuery = Kit.textfield("pv-q", x + pad, ly, listW - 2 * pad, 30 * s,
                            S.pvQuery, "search maps...")
  ly = ly + 30 * s + 8 * s

  local ids = {}
  for _, id in ipairs(mapList(S)) do
    if S.pvArea == "ALL AREAS" or areaOf(id) == S.pvArea then
      ids[#ids + 1] = id
    end
  end

  local rowH = 26 * s
  -- The list stops short of the NEW AREA button at the foot, or the last row
  -- of maps is drawn underneath it and is both unreadable and unclickable.
  local listFoot = y + h - pad - 30 * s - 8 * s
  local perPage = math.max(1, math.floor((listFoot - ly) / rowH))
  S.pvScroll = math.max(0, math.min(S.pvScroll or 0, math.max(0, #ids - perPage)))
  for r = 1, math.min(perPage, #ids - S.pvScroll) do
    local id = ids[r + S.pvScroll]
    local ry = ly + (r - 1) * rowH
    if Kit.press(x + pad, ry, listW - 2 * pad, rowH - 3 * s) then
      Preview.select(S, id)
    end
    Kit.row(x + pad, ry, listW - 2 * pad, rowH - 3 * s, id == S.mapId)
    local n = MapEdits.count(store(S), game(S), id)
    local label = Kit.ellipsize("small", id,
      listW - 2 * pad - 14 * s - (n > 0 and 26 * s or 0))
    Kit.text("small", label, x + pad + 7 * s, ry + 5 * s)
    if n > 0 then
      Kit.textRight("small", tostring(n), x + listW - pad - 7 * s, ry + 5 * s,
                    PAL.yellow)
    end
  end
  if #ids == 0 then
    Kit.text("small", "no map matches", x + pad, ly + 4 * s)
  end

  -- NEW AREA, at the foot of the list of areas -- which is where somebody
  -- looking for "the areas, and one more" would look for it. The form itself
  -- lives in the WARPS tool, because a new map with no door into it is a room
  -- nobody can reach, and that tool is where doors are made.
  do
    local addH = 30 * s
    local ay2 = y + h - pad - addH
    if Kit.button(x + pad, ay2, listW - 2 * pad, addH, "+ NEW AREA") then
      if Sidebar then Sidebar.open(S, "warps") else S.tab = "warps" end
      S.newMapOpen = true
    end
  end

  end   -- if S.pvListHidden ... else

  -- ------------------------------------------------------------- viewport
  Kit.card(viewX, y, viewW, h)
  local vpad = 14 * s
  local headH = 26 * s
  local vx0 = viewX + vpad
  local vinner = viewW - 2 * vpad

  if not S.mapId then
    Kit.emptyBox(vx0, y + vpad, vinner, h - 2 * vpad,
                 "Pick an area on the left to start editing it.")
  else
    Kit.text("monoBig", tostring(S.mapId), vx0,
             y + vpad + (headH - Kit.textHeight("monoBig")) / 2, PAL.heading)


    -- UNDO / REDO LIVE IN THE MAP'S OWN HEADER.
    --
    -- They were in the tools column, which the drawer covers entirely -- so
    -- the moment you opened the tool whose edits you most wanted to take back,
    -- the button that takes them back was underneath it and shielded. They
    -- have to be reachable without a keyboard too: this editor runs on Android
    -- and the Switch, where Ctrl-Z is not a gesture anybody has.
    --
    -- Greyed rather than hidden when there is nothing to undo: a control that
    -- comes and goes is a control you have to look for.
    if History then
      local uW, uH = 62 * s, headH
      local ux = vx0 + Kit.textWidth("monoBig", tostring(S.mapId)) + 14 * s
      local nUndo, nRedo = History.depth(S)
      if Kit.button(ux, y + vpad, uW, uH,
                    nUndo > 0 and ("< " .. nUndo) or "<",
                    { font = "small", kind = "ghost", enabled = nUndo > 0 }) then
        S.pvNotice = History.undo(S) and "undone" or "nothing to undo"
      end
      if Kit.button(ux + uW + 4 * s, y + vpad, uW, uH,
                    nRedo > 0 and (nRedo .. " >") or ">",
                    { font = "small", kind = "ghost", enabled = nRedo > 0 }) then
        S.pvNotice = History.redo(S) and "redone" or "nothing to redo"
      end
    end

    -- THE HEADER, laid out in ONE right-to-left pass.
    --
    -- It was two: the view presets measured inward from the right edge while
    -- the 2D/3D pair was positioned by its own arithmetic from the same edge,
    -- and the two overlapped -- PERSP printed over 2D, TOP over 3D. Buttons
    -- drawn on top of each other are also stacked HIT TARGETS, so the top one
    -- silently eats the other's clicks. One cursor, one pass, no arithmetic
    -- that has to agree with arithmetic somewhere else.
    local cur = vx0 + vinner
    local function headerButton(label, wpx, active, onPress)
      cur = cur - wpx
      if Kit.button(cur, y + vpad, wpx, headH, label,
                    { kind = active and "accent" or "ghost", font = "small" }) then
        onPress()
      end
      cur = cur - 4 * s
    end

    -- THE WORLD TOGGLE, FIRST IN THE PASS so it takes the rightmost slot.
    --
    -- It was measured from the right edge with arithmetic of its own, which
    -- put it straight on top of the zoom controls -- and two buttons drawn on
    -- top of each other are two stacked HIT TARGETS, so one silently eats the
    -- other's clicks. That is the exact bug the note above this function
    -- describes, and it caught me one function later: measuring from an edge
    -- that something else is already measuring from is the mistake, not the
    -- particular pair of buttons that collided.
    headerButton(S.pvWorld and "BACK TO MAP" or "WORLD",
                 S.pvWorld and 88 * s or 62 * s, S.pvWorld, function()
      S.pvWorld = not S.pvWorld
      S._pvWorldKey = nil
      -- OPENS ON THE REGION YOU ARE IN. The focus is remembered while the view
      -- is up so panning between regions sticks, and dropped when it is closed
      -- -- otherwise reopening it after moving to another region shows the
      -- region you left, with your map nowhere on screen.
      S._pvWorldFocus = nil
      S._pvWorldZoom = nil
      S._pvWorldPan = nil
    end)

    -- THE VOXEL DATA SOURCE, on the left beside the map name.
    --
    -- Which mod's heights are being edited is not a detail: two installed mods
    -- pin the same tile to different classes on purpose, so a height shown
    -- without saying whose it is might belong to a world the player is not
    -- running.
    -- The voxel-source button is DEFERRED to after the right-to-left pass.
    --
    -- It used to be drawn here, measured from the LEFT with a width of its
    -- own, while the preset buttons measured inward from the right -- and on a
    -- narrow viewport the two met in the middle and printed over each other,
    -- "VOXELS: STADIUM2 OVERWORLD MODELS" running straight through TOP, FRONT
    -- and SIDE. That is the same two-passes-from-two-edges bug this header
    -- already fixed once for the presets themselves. Nothing measures from the
    -- left until everything measuring from the right has finished, and then it
    -- takes what is actually left.
    local srcBtn = nil
    if S.pvView == "voxel" then
      for i = #Viewport3D_VIEWS, 1, -1 do
        local v = Viewport3D_VIEWS[i]
        headerButton(v.label, 44 * s, S.pvViewName == v.id, function()
          if Viewport3D then Viewport3D.setView(S, v.id) end
        end)
      end
      cur = cur - 6 * s
      headerButton(S.pvOrtho and "ORTHO" or "PERSP", 52 * s, false, function()
        S.pvOrtho = not S.pvOrtho
      end)
      local SHADES = { "textured", "solid", "wire" }
      local shading = S.pvShading or "textured"
      headerButton(shading:upper(), 62 * s, false, function()
        local at = 0
        for i, m in ipairs(SHADES) do if m == shading then at = i break end end
        S.pvShading = SHADES[(at % #SHADES) + 1]
      end)
      cur = cur - 6 * s
    else
      local zBtn = 26 * s
      cur = cur - zBtn
      if Kit.stepper(cur, y + vpad, zBtn, headH, "+") then
        S.pvZoom = math.min(4, S.pvZoom + 0.5)
      end
      cur = cur - 48 * s
      Kit.textCenter("mono", ("%.1fx"):format(S.pvZoom), cur,
                     y + vpad + (headH - Kit.textHeight("mono")) / 2, 48 * s,
                     PAL.muted)
      cur = cur - zBtn
      if Kit.stepper(cur, y + vpad, zBtn, headH, "-") then
        S.pvZoom = math.max(1, S.pvZoom - 0.5)
      end
      cur = cur - 10 * s
    end

    -- The view switch last, so it sits leftmost of the cluster and never
    -- collides with whatever the mode above it drew.
    headerButton("3D", 40 * s, S.pvView == "voxel", function()
      S.pvView = "voxel"
    end)
    headerButton("2D", 40 * s, S.pvView ~= "voxel", function()
      S.pvView = "2d"
    end)

    -- THE VOXEL SOURCE MOVED OUT OF THE HEADER.
    --
    -- It was measured from the left while the view presets measured in from
    -- the right, and on a narrow viewport the two met in the middle. It also
    -- belongs with SAVE and EXPORT rather than with the camera: those three
    -- are what you do to the WORK, and the header is what you do to the VIEW.
    -- The list it opens is still deferred and drawn last -- see the note at
    -- the foot of this file -- because Kit has no z-order.

    local vy0 = y + vpad + headH + 10 * s
    local vh0 = (y + h - vpad - 22 * s) - vy0
    S.pvViewW, S.pvViewH = vinner, vh0

    -- The map's size in cells, from the RECORD rather than from a built Map.
    -- Everything that positions the camera or turns a click into a coordinate
    -- uses these, so panning and selecting work on a map the renderer could
    -- not build -- which is exactly the state you are in when you most need to
    -- reach the controls that fix it.
    local mapDef = S.data and S.data.maps and S.data.maps[S.mapId]
    local wCells = ((mapDef and mapDef.width) or 0) * 2
    local hCells = ((mapDef and mapDef.height) or 0) * 2

    if S._pvCenteredFor ~= S.mapId then
      S._pvCenteredFor = S.mapId
      centerOn(S, wCells / 2, hCells / 2)
    end

    -- MapLoader.build asserts on a map whose tileset will not resolve, and an
    -- editor-created map is exactly where that can happen.
    -- THE LIVE OVERRIDES, ON THE DEF, BEFORE THE MAP IS BUILT.
    --
    -- Data:load applied the store it read off disk, once, at boot. The editor
    -- writes into its own in-memory store, and until this line the two never
    -- met: a height set on the voxel tab was saved correctly, reloaded
    -- correctly, and had no effect until the game was restarted. Published
    -- here rather than at the point of edit because a map can be opened before
    -- it has a bucket at all, and the bucket is created by the first change.
    local liveDef = S.data and S.data.maps and S.data.maps[S.mapId]
    if liveDef then
      MapEdits.publishVoxels(store(S), game(S), S.mapId, liveDef)
    end

    -- HOW THIS MAP LOOKED WHEN IT WAS FIRST OPENED, for RESET MAP's fallback.
    -- Cheap and once per map: it only copies the two arrays the editor mutates
    -- in place, and only for a map it has not already remembered.
    pcall(function()
      require("tools.map-editor.MapReset").remember(S, S.mapId, liveDef)
    end)

    local ok, map = pcall(MapLoader.load, S.data, S.mapId)
    if not ok then
      -- Caught, and NOT a `return`. Bailing out of the whole panel here took the tools
      -- column and the SAVE button with it, so the one situation where you
      -- most need to pick a different map -- or save the edits you already
      -- made -- was the one where the controls for it were not drawn.
      Kit.text("small", "Cannot open this map: " .. tostring(map),
               vx0, vy0 + 8 * s, PAL.red)
      Kit.text("small", "Pick another map on the left.", vx0, vy0 + 26 * s, PAL.muted)
      -- and drop the published map: a stale one from the PREVIOUS map would
      -- have the class swatches drawing another map's artwork.
      S._pvMap = nil
    else

    Theme.col(PAL.bgBot, 1)
    love.graphics.rectangle("fill", vx0, vy0, vinner, vh0, 10 * s, 10 * s)
    Theme.stroke(vx0, vy0, vinner, vh0, 10 * s, PAL.cardBorder, 0.28, 1)

    -- love_stub (headless tests) has no push/scale/scissor. The render is
    -- skipped there and every hit test below still runs, which is what lets
    -- this panel be driven by a test at all.
    -- The built Map, published for the class picker's swatches: they draw
    -- this cell's real artwork, which needs the renderer's atlas.
    S._pvMap = map

    -- THE REAL 3D VIEWPORT, when the driver can give us one. Drawn outside
    -- the 2D translate/scale below: it has its own camera and its own canvas,
    -- and running it inside a 2D transform would apply the pan and zoom twice.
    local drew3D = false
    if S.pvView == "voxel" and Viewport3D and Viewport3D.available() then
      local key = table.concat({ S.mapId, tostring(S.mapEditsStamp or 0),
                                 tostring(S.voxelSource or "-") }, "|")
      -- NOT WHILE A STROKE IS IN PROGRESS.
      --
      -- The mesh is the mod's own ChunkMesher over the whole map -- every
      -- structure flooded, every hull cut, every prop carved -- which is a
      -- fraction of a second on a route. Rebuilding it once per painted cell
      -- meant a drag rebuilt it forty times, and the editor spent the whole
      -- stroke building worlds nobody would see. It rebuilds when the button
      -- comes up, which is the first moment the result is worth looking at.
      local mid = S.pvDrag and S.pvDrag.paint
      if S.pv3DKey ~= key and not mid then
        -- DROP THE MOD'S CACHES FIRST. TileShape caches its resolved shapes
        -- per tileset id and Structures caches its whole analysis per map id,
        -- and both are right to: in the game a map's drawing never changes
        -- under them. The editor is the one place it does. Without this the
        -- viewport rebuilt from a cache that still held the pre-edit world and
        -- the picture lagged the change by a map switch -- which reads exactly
        -- like the edit having done nothing.
        ModShapes.invalidate(S.mapId)
        -- and the voxel panel's handle ON those caches. It holds a resolver
        -- built from them to answer "how tall is this tile really", which is
        -- the seed every sub-height edit starts from -- so a stale one seeds
        -- new sculpting at the pre-edit world's heights.
        pcall(function()
          local V = require("tools.map-editor.panels.Voxels")
          if V and V.forgetResolver then V.forgetResolver(S) end
        end)
        if S.pv3D and S.pv3D.mesh and S.pv3D.mesh.release then
          pcall(S.pv3D.mesh.release, S.pv3D.mesh)
        end
        S.pv3D = Viewport3D.build(S, map)
        S.pv3DKey = key
      end
      if S.pv3D then
        -- FRAME IT ON ARRIVAL, from the field of view rather than a guessed
        -- distance. REDS_HOUSE_2F is 4x4 blocks and a route is 20x18; one
        -- fixed distance puts one of them off the edges and the other in the
        -- middle distance as a speck.
        if S.pvFocus == nil or S.pvDist == nil then
          Viewport3D.frame(S, S.pv3D, nil)
          -- ON by default the first time a map is opened in 3D. Six lines of
          -- state at the top of the viewport is a small price next to another
          -- round of guessing at what the renderer decided, and G/D turn the
          -- furniture off once it has answered.
          if S.pvDiag == nil then S.pvDiag = true end
        end
        -- NO SCISSOR AROUND THIS. The viewport renders into a canvas of
        -- exactly this size and blits it here, so its own edges are the clip
        -- -- and a scissor set in SCREEN coordinates would still be active
        -- when the canvas is bound, where the same numbers mean a rectangle
        -- offset by the panel's position. That clipped the top-left off every
        -- frame and left it not matching the grid drawn over it.
        drew3D = Viewport3D.draw(S, S.pv3D, vx0, vy0, vinner, vh0, Kit)
        if drew3D then
          -- THE OVERLAYS THE FLAT VIEW DRAWS, projected onto this one.
          --
          -- `drawOverlays` runs only when the 3D viewport did NOT draw -- it
          -- paints cell rectangles into the 2D transform, and there is no 2D
          -- transform here. So every marker the editor puts on the map was
          -- simply absent in the 3D view: turning the walkable overlay on did
          -- nothing at all, which reads as the switch being dead rather than
          -- as the picture being the wrong one to look at.
          drawOverlays3D(S, S.pv3D, vx0, vy0, vinner, vh0)
          -- bottom-left, out of the way of the readout on the right
          Viewport3D.drawGizmo(S, vx0 + 10 * s, vy0 + vh0 - 74 * s, 64 * s)

          -- D toggles a readout of what the viewport is ACTUALLY doing.
          --
          -- Every round of this feature that moved forward did so because a
          -- screenshot carried a fact I could not otherwise get -- the render
          -- target's real size, whether depth is attached, what the display's
          -- DPI ratio is. Guessing at those cost four rounds; printing them
          -- costs eight lines.
          if S.pvDiag and Viewport3D.lastStats then
            local st = Viewport3D.lastStats
            -- The CLASS CENSUS first, because it is the line that has actually
            -- explained things: "64 cells, all wall" says the walkability
            -- lookup failed, and a floor that resolved to wall is a raised
            -- slab with side faces -- a room floating over its own grid.
            local census = {}
            for i, e in ipairs(st.census or {}) do
              if i > 4 then break end
              census[#census + 1] = string.format("%s %d", e[1], e[2])
            end
            local bmin, bmax = st.bmin or { 0, 0, 0 }, st.bmax or { 0, 0, 0 }
            local lines = {
              string.format("%d x %d cells   classes: %s", st.W or 0, st.H or 0,
                table.concat(census, ", ")),
              -- The mesh's real extent. The map should span x 0..W*16,
              -- z 0..H*16 and sit at y 0 -- anything else is geometry that is
              -- not where the camera is being pointed.
              string.format("mesh x %.0f..%.0f  y %.0f..%.0f  z %.0f..%.0f",
                bmin[1], bmax[1], bmin[2], bmax[2], bmin[3], bmax[3]),
              string.format("rect %dx%d  canvas %dx%d  dpi %.2f",
                st.rectW, st.rectH, st.canvasW, st.canvasH, st.dpi),
              string.format("depth %s   %s   %d tris",
                st.depth, st.ortho and "ortho" or "persp", st.tris or 0),
              string.format("dist %.0f  pitch %.1f  yaw %.2f",
                st.dist or 0, st.angle or 0, S.pvYaw or 0),
              string.format("carved %s   truncated %s   voxels from %s",
                tostring(st.carved), tostring(st.truncated),
                tostring((VoxelClasses.sourceFor(S.voxelSource) or {}).label)),
              -- WHOSE ANSWER THIS PICTURE IS. Either the mod's own TileShape
              -- and Structures resolved it -- in which case the shapes are the
              -- game's by construction -- or this file worked them out, which
              -- is a good approximation and not the same thing. Every round of
              -- "that is not what it looks like in game" would have been one
              -- line long if this had been on the screen.
              Viewport3D.lastResolver
                and ("shapes: " .. tostring(Viewport3D.lastResolver)
                     .. "'s own TileShape"
                     .. (Viewport3D.lastRun and " + Structures"
                         or "  (no Structures - buildings measured here)"))
                or ("shapes: this editor's own - "
                    .. tostring(Viewport3D.lastResolverWhy or "no mod selected")),
              -- and WHOSE GEOMETRY. The line above says what the cells are;
              -- this says what built them. They can differ -- a mod whose
              -- ChunkMesher will not load still resolves shapes correctly and
              -- is then drawn as boxes -- and telling the two apart is the
              -- difference between "the heights are wrong" and "the heights
              -- are right and the shapes are mine".
              Viewport3D.lastGeometry
                and ("geometry: " .. tostring(Viewport3D.lastGeometry)
                     .. "'s own ChunkMesher")
                or "geometry: this editor's boxes and plates",
            }
            for i, line in ipairs(lines) do
              Kit.text("small", line, vx0 + 12 * s,
                       vy0 + 10 * s + (i - 1) * 15 * s, PAL.yellow)
            end
          end
        end
      end
    end
    S.pv3DActive = drew3D

    -- FLY THE CAMERA, once the viewport has said whether there is one.
    --
    -- Polled here rather than in `keypressed` because a held key repeats at
    -- whatever rate the OS decides; movement built on key events lurches. It
    -- runs after `pv3DActive` is set so it can never fly a camera that is not
    -- being drawn -- in the 2D view WASD means nothing and must stay meaning
    -- nothing.
    flyCamera(S, Kit)

    -- WHY THERE IS NO 3D, said IN THE VIEWPORT. The footer is one line at the
    -- bottom of a tall panel and it is the first thing a full-screen view
    -- pushes out of sight; the reason a 3D button produced a flat picture has
    -- to be where the picture is.
    if S.pvView == "voxel" and not drew3D then
      -- ONE question, asked of the viewport. This was an `or` chain, and it
      -- lied: `Viewport3D and Viewport3D.unavailableReason()` is nil when the
      -- module is present AND working, so the fallback fired and reported "the
      -- 3D module is not installed" about a module that was installed, loaded
      -- and available. The real failure -- a Shader:send raising inside the
      -- render -- had no way to reach the screen at all.
      local why = Viewport3D and Viewport3D.whyNoPicture()
        or "tools/map-editor/Viewport3D.lua could not be loaded"
      Kit.text("small", "3D viewport unavailable - showing a flat projection",
               vx0 + 12 * s, vy0 + 10 * s, PAL.yellow)
      Kit.text("small", tostring(why), vx0 + 12 * s, vy0 + 26 * s, PAL.muted)
    end

    if (not drew3D) and love.graphics.push then
      love.graphics.setScissor(math.floor(vx0), math.floor(vy0),
                               math.ceil(vinner), math.ceil(vh0))
      love.graphics.push()
      love.graphics.translate(vx0, vy0)
      love.graphics.scale(S.pvZoom, S.pvZoom)
      -- The viewport's size in world pixels, for anything that wants to paint
      -- only the part of the map on screen -- the collision overlay does.
      S._pvViewW, S._pvViewH = vinner, vh0
      -- AND WHERE IT IS, not only how big. The world view is painted over
      -- this rectangle from `drawDeferred` -- after the whole frame, so it
      -- covers the map and the tools column both -- and an overlay that knows
      -- a size but not an origin can only guess where to land.
      S._pvViewX, S._pvViewY = vx0, vy0
      if S.pvView == "voxel" then
        drawVoxelView(S, map, vinner, vh0)
      else
        map.renderer:draw(S.pvCamX or 0, S.pvCamY or 0)
      end
      drawOverlays(S, map, Kit)
      love.graphics.pop()
      love.graphics.setScissor()
    end

    end   -- the render; the pointer handling below runs either way

    -- DRAG TO PAN, SELECT ON A PRESS THAT DID NOT MOVE.
    --
    -- The two cannot both fire on press: a drag starts with a press inside the
    -- viewport and so does a selection, and committing the selection there
    -- means every drag also re-aims all four tools at whatever cell the drag
    -- happened to start on. So a press only ARMS, and the release decides --
    -- the same rule the launcher's tab bar uses for the same reason.
    --
    -- Falls back to select-on-press where love.mouse cannot be polled (the pad
    -- cursor, a touch screen): there is no drag to conflict with there, and a
    -- viewport that only responds to a gesture the device cannot make would be
    -- inert.
    -- ALL THREE BUTTONS, not just the left one. App.mousepressed only records
    -- button 1, so a middle or right drag never reaches a panel through Kit --
    -- the state has to be polled here.
    local canPoll = love.mouse and love.mouse.isDown
    -- THE SHIELD APPLIES HERE TOO, and this is the one place it was missed.
    --
    -- Everything else goes through `Kit.press`, which honours the block rect
    -- an overlay puts up. This does not -- it polls the buttons itself,
    -- because Kit only records button 1 and the orbit and pan drags need the
    -- other two -- so a click inside the tool drawer went straight past the
    -- drawer and landed on the map underneath it: pressing a button in the
    -- panel also painted a block, or moved the selection, wherever the button
    -- happened to sit over the world.
    local blocked = (Kit.blockClicks and true or false)
      or (Kit.pointerBlocked and Kit.pointerBlocked()) or false
    local inside = not blocked
               and Kit.mouseX >= vx0 and Kit.mouseX <= vx0 + vinner
               and Kit.mouseY >= vy0 and Kit.mouseY <= vy0 + vh0

    -- THE CELL UNDER THE POINTER, every frame, not only on a click.
    --
    -- Only worked out while something is being HELD: it costs a ray pick in
    -- 3D, and paying that on every frame of every session to serve a ghost
    -- nobody is looking at is the kind of cost that shows up later as "the
    -- editor feels heavy". Cleared when nothing is held so a stale square does
    -- not hang over the map.
    if S.assetPlacing and inside then
      local hx, hy
      if S.pv3DActive and Viewport3D then
        hx, hy = Viewport3D.pick(S, S.pv3D, Kit.mouseX, Kit.mouseY,
                                 vx0, vy0, vinner, vh0)
      else
        hx, hy = cellAtScreen(S, wCells, hCells, Kit, vx0, vy0, vinner, vh0)
      end
      S.pvHover = hx and { cx = hx, cy = hy } or nil
    else
      S.pvHover = nil
    end
    if canPoll then
      -- LOVE numbers them 1 = left, 2 = RIGHT, 3 = MIDDLE. Named by position
      -- rather than by number, because "middle orbits" and "right orbits" are
      -- indistinguishable from reading the digit.
      local lmb = love.mouse.isDown(1)
      local rightDown = love.mouse.isDown(2) or false
      local middleDown = love.mouse.isDown(3) or false
      local down = lmb or rightDown or middleDown
      if down and (S.pvDrag or inside) then
        if S.pvDrag then
          local dx = Kit.mouseX - S.pvDrag.lastX
          local dy = Kit.mouseY - S.pvDrag.lastY
          -- A PAINT STROKE, not a pan. With the painter open a left-drag lays
          -- block after block across the cells it crosses, which is how a road
          -- or a wall gets drawn -- one click per block for a twenty-block
          -- route is not a tool, it is a chore. The other two buttons still
          -- pan and orbit, so getting around never stops working.
          if S.pvDrag.paint then
            local pcx, pcy
            if S.pv3DActive and Viewport3D then
              pcx, pcy = Viewport3D.pick(S, S.pv3D, Kit.mouseX, Kit.mouseY,
                                         vx0, vy0, vinner, vh0)
            else
              pcx, pcy = cellAtScreen(S, wCells, hCells, Kit,
                                      vx0, vy0, vinner, vh0)
            end
            if pcx then Preview.paintAt(S, pcx, pcy) end
            S.pvDrag.lastX, S.pvDrag.lastY = Kit.mouseX, Kit.mouseY
            if math.abs(Kit.mouseX - S.pvDrag.x) > 3
               or math.abs(Kit.mouseY - S.pvDrag.y) > 3 then
              S.pvDrag.moved = true
            end
          elseif dx ~= 0 or dy ~= 0 then
            if S.pv3DActive then
              -- ORBIT by default, PAN with shift or the middle button -- the
              -- convention every 3D tool shares. In a perspective view "drag
              -- the map" has no single meaning (the ground is at an angle and
              -- how far a pixel moves depends how far away it is), so orbit is
              -- the safe default and pan is the one you ask for.
              local panning = S.pvDrag.pan
              if panning and Viewport3D and S.pv3D then
                Viewport3D.pan(S, S.pv3D, dx, dy, vh0)
              else
                S.pvYaw = (S.pvYaw or 0) + dx * 0.006
                S.pvAngle = math.max(1.5, math.min(88.5,
                                     (S.pvAngle or 35) + dy * 0.25))
                S.pvViewName = nil   -- no longer on a preset
              end
            else
              S.pvCamX = (S.pvCamX or 0) - dx / S.pvZoom
              S.pvCamY = (S.pvCamY or 0) - dy / S.pvZoom
            end
            S.pvDrag.lastX, S.pvDrag.lastY = Kit.mouseX, Kit.mouseY
          end
          -- Measured from where the press STARTED, not from the last frame: a
          -- slow drag moves a pixel at a time and would never trip a
          -- per-frame threshold, so it would end as a selection.
          if math.abs(Kit.mouseX - S.pvDrag.x) > 3
             or math.abs(Kit.mouseY - S.pvDrag.y) > 3 then
            S.pvDrag.moved = true
          end
        else
          local kb = love.keyboard and love.keyboard.isDown
          -- MIDDLE orbits, RIGHT pans, and shift-left pans too because that is
          -- the convention the other half of the world has in its fingers.
          S.pvDrag = { x = Kit.mouseX, y = Kit.mouseY,
                       lastX = Kit.mouseX, lastY = Kit.mouseY, moved = false,
                       button = (middleDown and "middle")
                         or (rightDown and "right") or "left",
                       pan = (rightDown or (lmb and kb and kb("lshift", "rshift")))
                         and true or false,
                       -- decided ONCE, at the press: a stroke that started as
                       -- a paint stays one even if the palette changes
                       -- underneath it, and one that started as a pan does not
                       -- turn into a paint halfway across the map
                       paint = (lmb and not rightDown and not middleDown
                                and not (kb and kb("lshift", "rshift"))
                                and Preview.painting(S)) or false }
        end
      elseif S.pvDrag then
        -- Only the LEFT button selects. A right-drag that happened not to
        -- move would otherwise re-aim every tool at wherever the pan started.
        if not S.pvDrag.moved and inside and S.pvDrag.button == "left" then
          local cx, cy
          if S.pv3DActive and Viewport3D then
            cx, cy = Viewport3D.pick(S, S.pv3D, Kit.mouseX, Kit.mouseY,
                                     vx0, vy0, vinner, vh0)
          else
            cx, cy = cellAtScreen(S, wCells, hCells, Kit, vx0, vy0, vinner, vh0)
          end
          if cx then
            -- A SECOND CLICK ON THE SAME CELL, quickly, is a double click.
            -- Tracked here rather than asked of LOVE because the viewport
            -- polls the buttons itself for the orbit and pan drags, and never
            -- sees love.mousepressed's own click count.
            local now = (love.timer and love.timer.getTime and love.timer.getTime())
              or 0
            local last = S._pvLastClick
            local isDouble = last and last.cx == cx and last.cy == cy
              and (now - last.t) < 0.4
            S._pvLastClick = { cx = cx, cy = cy, t = now }

            local kb2 = love.keyboard and love.keyboard.isDown
            local ctrl = kb2 and (kb2("lctrl", "rctrl") or kb2("lgui", "rgui"))
            if Preview.paintAt(S, cx, cy) then
              -- the painter took the click; a paint is not a selection
            elseif ctrl then
              local n = Preview.selectLike(S, cx, cy)
              S.pvNotice = string.format("%d cells like that one", n)
            else
              Preview.selectCell(S, cx, cy,
                kb2 and kb2("lshift", "rshift") or false)
              S.pvNotice = nil
            end
            -- NOT A `return`. Bailing out of the panel here would take the
            -- tools column and SAVE with it for the rest of the frame -- the
            -- same mistake a failed map load made once, and the reason that
            -- one is caught rather than returned from.
            local followed = isDouble and followWarp(S, cx, cy)
            if followed then
              S._pvLastClick = nil
            else
              selectObjectAt(S, cx, cy)
            end
            -- Orbit around what is being worked on. Without this the camera
            -- keeps circling the middle of the map while the cell you are
            -- editing swings across the screen.
            if S.pv3DActive and S.pv3D then
              local hs = S.pv3D.heights and S.pv3D.heights[cy * S.pv3D.W + cx]
              S.pvFocus = { x = cx * 16 + 8, y = hs or 0, z = cy * 16 + 8 }
            end
          end
        end
        S.pvDrag = nil
      end
    elseif Kit.mouseClicked and inside then
      local cx, cy = cellAtScreen(S, wCells, hCells, Kit, vx0, vy0, vinner, vh0)
      if cx then
        local now = (love.timer and love.timer.getTime and love.timer.getTime())
          or 0
        local last = S._pvLastClick
        local isDouble = last and last.cx == cx and last.cy == cy
          and (now - last.t) < 0.4
        S._pvLastClick = { cx = cx, cy = cy, t = now }
        local kb3 = love.keyboard and love.keyboard.isDown
        local ctrl3 = kb3 and (kb3("lctrl", "rctrl") or kb3("lgui", "rgui"))
        if Preview.paintAt(S, cx, cy) then
          -- painted
        elseif ctrl3 then
          local n = Preview.selectLike(S, cx, cy)
          S.pvNotice = string.format("%d cells like that one", n)
        else
          Preview.selectCell(S, cx, cy, kb3 and kb3("lshift", "rshift") or false)
          S.pvNotice = nil
        end
        if not (isDouble and followWarp(S, cx, cy)) then
          selectObjectAt(S, cx, cy)
        end
      end
    end

    local ly2 = y + h - vpad - 14 * s
    local footer
    if S.pvView == "voxel" and S.pv3DActive then
      -- The state of the mesh is part of what the view means. Carved off is a
      -- world of flat floors, and truncated is a world with the far side
      -- missing -- both look like a bug in the map rather than a limit that
      -- was reached, unless the panel says which.
      local note = ""
      if S.pv3D and not S.pv3D.carved then
        note = "  -  tileset art unreadable, nothing carved"
      elseif S.pv3D and S.pv3D.truncated then
        note = "  -  TOO LARGE, mesh stops partway"
      end
      footer = string.format("%s  -  %ddeg  -  WASD flies, QE up/down, shift fast, orbit drag/MMB, wheel zooms, F frame, G grid, F3 diag  -  %d tris%s",
        S.pvCell and string.format("cell %d,%d", S.pvCell.cx, S.pvCell.cy)
          or string.format("%d x %d cells", wCells, hCells),
        math.floor(S.pvAngle or 35), (S.pv3D and S.pv3D.count) or 0, note)
    elseif S.pvView == "voxel" then
      -- WHY, not just that. A viewport that quietly shows a flat picture is
      -- indistinguishable from one that is broken, and the reason is always
      -- something the reader can act on -- a driver without depth buffers, or
      -- a shader the compiler rejected, with the compiler's own words.
      -- Same one question. `A and A.f() or "..."` reports the fallback
      -- whenever f() answers nil, which for a "why did this fail" function is
      -- precisely when nothing is wrong with A.
      local why = Viewport3D and Viewport3D.whyNoPicture()
        or "tools/map-editor/Viewport3D.lua could not be loaded"
      footer = "flat projection - " .. tostring(why)
    elseif S.assetPlacing then
      -- HOLDING SOMETHING SAYS SO, and says how to put it down. A mode where a
      -- click on the map drops a whole building is the loudest surprise this
      -- editor has, and it must never be a state you are in without knowing.
      footer = string.format(
        "HOLDING \"%s\"  -  click the map to place it  -  Esc puts it down",
        tostring(S.assetPlacing))
    elseif Preview.painting(S) then
      -- THE ARMED PAINTER SAYS SO. A mode where a click on the map does
      -- something quite different from what it does the rest of the time has
      -- to announce itself, or the first surprise is a block of grass in the
      -- middle of somebody's kitchen.
      footer = string.format(
        "PAINTING block %s  -  click or drag the map  -  right-drag still pans",
        tostring(S.tilePick))
    elseif S.pvCell then
      footer = string.format("cell %d,%d  -  %d x %d cells  -  drag to pan",
        S.pvCell.cx, S.pvCell.cy, wCells, hCells)
    else
      footer = string.format("%d x %d cells  -  drag to pan, click a cell to aim the tools",
        wCells, hCells)
    end
    Kit.text("small", footer, vx0, ly2, PAL.muted)
  end

  -- ---------------------------------------------------------------- tools
  local toolX = viewX + viewW + gap
  Kit.card(toolX, y, toolW, h)
  Kit.caption(toolX + pad, y + pad, "TOOLS")
  local ty = y + pad + Kit.textHeight("caption") + 10 * s
  local inner = toolW - 2 * pad

  -- `S.tools` is the subset the shell actually loaded -- it drops a panel whose
  -- require failed rather than offering a button that opens nothing. Falling
  -- back to the full list keeps this panel drawable on its own in a test.
  -- Two across rather than a full-width stack: the cell inspector below needs
  -- the vertical room more than the buttons need the width, and the four
  -- titles are short enough to read at half a column.
  local btnH = 40 * s
  local half = (inner - 8 * s) / 2
  local tools = S.tools or Preview.TOOLS
  for i, tool in ipairs(tools) do
    local bx = toolX + pad + ((i - 1) % 2) * (half + 8 * s)
    local by = ty + math.floor((i - 1) / 2) * (btnH + 8 * s)
    -- Pressed with no map selected, the button says why instead of doing
    -- nothing: a dead control is indistinguishable from a broken one.
    local open = Sidebar and Sidebar.openId(S) == tool.tab
    if Kit.button(bx, by, half, btnH, tool.title,
                  open and { kind = "accent" } or nil) then
      if not S.mapId then
        S.pvNotice = "pick a map first - the tools all work on one map"
      elseif Sidebar then
        -- A DRAWER OVER THE MAP, not a tab instead of it. Every one of these
        -- tools works on the cell that is selected, and a tab hid the one
        -- thing you need to see while using it. Pressing the same button
        -- again closes it, so the button is a toggle rather than a control
        -- that appears to do nothing the second time.
        Sidebar.open(S, tool.tab)
      else
        S.tab = tool.tab
      end
    end
  end
  ty = ty + math.ceil(#tools / 2) * (btnH + 8 * s) + 8 * s

  -- WHAT THE MAP SHOWS.
  --
  -- Every marker on the map is a claim about something you cannot see in the
  -- artwork -- a door, a person, a painted cell -- and on a town with a dozen
  -- of each they cover the drawing they are annotating. Turning them off is
  -- how you check the thing underneath, and it is also how you take a picture
  -- of a map without the editor's furniture all over it.
  --
  -- `~= false` throughout, so everything is on until it is explicitly turned
  -- off: a fresh session shows the whole map, not an empty one.
  Kit.caption(toolX + pad, ty, "SHOW")
  ty = ty + Kit.textHeight("caption") + 6 * s
  do
    local chipH = 24 * s
    local CHIPS = {
      { key = "pvShowWarps",   label = "WARPS" },
      { key = "pvShowObjects", label = "NPCs" },
      { key = "pvShowVoxels",  label = "EDITS" },
      { key = "pvGrid",        label = "GRID" },
    }
    local cw3 = (inner - 3 * 5 * s) / 4
    for i, c in ipairs(CHIPS) do
      local cx3 = toolX + pad + (i - 1) * (cw3 + 5 * s)
      if Kit.chip(cx3, ty, cw3, chipH, c.label, S[c.key] ~= false) then
        -- `(S[key] == false) or nil` was wrong in the one direction that
        -- mattered: from ON (nil) it evaluated `(nil == false)` -> false, then
        -- `false or nil` -> nil, so pressing a lit chip left it lit. The
        -- toggle only ever turned things back on.
        S[c.key] = (S[c.key] == false)
        -- the 3D view bakes nothing about markers into its mesh, so there is
        -- no rebuild to ask for -- only the 2D overlay and the billboards,
        -- both of which read these every frame
      end
    end
    ty = ty + chipH + 10 * s
  end

  ty = Preview.drawCellCard(S, Kit, toolX + pad, ty, inner)

  Kit.caption(toolX + pad, ty, "THIS MAP")
  ty = ty + Kit.textHeight("caption") + 8 * s
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  if def then
    local m = MapEdits.bucket(store(S), game(S), S.mapId, false)
    local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
    local lines = {
      string.format("%d warps", #(def.warps or {})),
      string.format("%d objects", #(def.objects or {})),
      string.format("tileset %s", tostring(def.tileset)),
      string.format("%d x %d blocks", def.width or 0, def.height or 0),
      string.format("%d edits stored", MapEdits.count(store(S), game(S), S.mapId)),
    }
    if def.editorCreated then
      lines[#lines + 1] = "created in this editor"
    end
    if count(m and m.voxels) > 0 then
      lines[#lines + 1] = string.format("%d voxel cells painted", count(m.voxels))
    end
    for _, line in ipairs(lines) do
      Kit.text("small", line, toolX + pad, ty)
      ty = ty + 16 * s
    end
  else
    Kit.text("small", "no map selected", toolX + pad, ty)
  end

  local actH = 34 * s
  local ay = y + h - pad - actH
  if Kit.button(toolX + pad, ay, inner, actH, "SAVE ALL EDITS") then
    local okSave, err = MapEdits.save(store(S))
    S.mapEditsDirty = not okSave or nil
    S.pvNotice = okSave and "every edit saved" or ("save failed: " .. tostring(err))
  end
  -- THE VOXEL SOURCE, SAVE-AS-A-MOD AND SAVE MOVED TO THE TITLE BAR.
  --
  -- All three say what happens to the WORK rather than to the view, and this
  -- column scrolls, gets covered by a drawer and disappears entirely on a
  -- narrow window.  The title bar is the one strip nothing covers, and it
  -- already holds Save.  SAVE ALL EDITS stays here as well: it is two clicks
  -- from anywhere in this panel and the duplicate costs nothing.
  --
  -- The list the title-bar button opens is still deferred -- see
  -- Preview.drawDeferred at the foot of this file, which App paints last.

  local note = S.pvNotice or (S.mapEditsDirty and "unsaved changes" or nil)
  if note then Kit.text("small", note, toolX + pad, ay - 18 * s, PAL.muted) end

end

-- THE VOXEL-SOURCE LIST, painted after the entire frame.
--
-- Split out of `draw` when its button moved to the title bar.  Drawn from the
-- end of Preview.draw it was over the viewport and under everything painted
-- later -- the drawer, the species picker -- and a list that drops out of the
-- title bar crosses all of them.  Kit paints in call order and has no
-- z-order, so "on top" and "drawn last" are the same statement, and the only
-- place that can say it is App.draw's last line.
-- THE CLASS PICKER, over the whole window, after the entire frame.
--
-- Every class, scrollable, each row drawing THIS cell's own artwork under that
-- class -- so choosing between `terrace` and `roof`, both tall and both
-- art-on-top, is looking at two pictures rather than recalling what two words
-- did last time. That was always the idea; what was missing was room for it.
local function drawClassMenu(S, Kit)
  local menu = S._pvClassMenu
  if not menu then return false end
  local s = Kit.scale
  local fieldH = 28 * s
  local rowH = 42 * s
  local swatchW = 44 * s
  local winW, winH = love.graphics.getDimensions()

  local names, info = classInfo(S)
  local q = (S.pvClassQuery or ""):lower()
  local hits = {}
  for _, name in ipairs(names) do
    if q == "" or name:lower():find(q, 1, true) then hits[#hits + 1] = name end
  end

  -- Sized to what is left BELOW the button, floored so a button near the
  -- bottom of the screen still gets a usable list -- lifted up the screen
  -- rather than squeezed into four pixels of it.
  local pw = math.max(200 * s, menu.w)
  local pad = 8 * s
  local wantH = fieldH + 6 * s + math.min(#hits, 12) * rowH + 2 * pad
  local ph = math.max(160 * s, math.min(wantH, winH - 40 * s))
  local px0 = math.max(8 * s, math.min(menu.x, winW - pw - 8 * s))
  local py0 = menu.y
  if py0 + ph > winH - 8 * s then py0 = math.max(8 * s, winH - 8 * s - ph) end

  -- TAP OUTSIDE TO CLOSE, dispatched before anything inside it -- except on
  -- the frame the button opened it, which is still holding that same click.
  -- The flag this used to carry worked; it is gone because four other modals
  -- had no guard at all and the question is better with one answer.
  if Kit.tapAway("pv-class-menu", px0, py0, pw, ph) then
    S.pvClassOpen, S._pvClassMenu = false, nil
    return true
  end

  -- Opaque, over a scrim: a modal that does not stop the light leaves the
  -- reader looking at two things at once and reading neither.
  love.graphics.setColor(0.03, 0.04, 0.11, 0.45)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", px0, py0, pw, ph, 10 * s, 10 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(px0, py0, pw, ph)

  local iy = py0 + pad
  S.pvClassQuery = Kit.textfield("pv-class-q", px0 + pad, iy, pw - 2 * pad,
                                 fieldH, S.pvClassQuery or "",
                                 "search classes...")
  iy = iy + fieldH + 6 * s

  local bodyH = (py0 + ph - pad) - iy
  local perPage = math.max(1, math.floor(bodyH / rowH))
  local maxScroll = math.max(0, #hits - perPage)
  S.pvClassScroll = math.max(0, math.min(S.pvClassScroll or 0, maxScroll))
  local off = S.pvClassScroll

  local map = S._pvMap
  Kit.pushClip(px0, iy, pw, bodyH)
  local ry = iy
  for i = off + 1, math.min(#hits, off + perPage) do
    local name = hits[i]
    local spec = info[name]
    if Kit.press(px0 + pad, ry, pw - 2 * pad, rowH - 3 * s) then
      -- A CLASS IS ASSIGNED, NOT STEPPED: every selected cell becomes that
      -- class at that class's own height, which is what levelling a selection
      -- means.
      setVoxelAll(S, { art = name, h = spec and spec.h or menu.h })
      S.pvClassOpen, S._pvClassMenu = false, nil
    end
    Kit.row(px0 + pad, ry, pw - 2 * pad, rowH - 3 * s, name == menu.class)
    if map then
      drawCellSwatch(S, map, menu.cx, menu.cy, name, (spec and spec.h) or 0,
                     px0 + pad + 3 * s, ry + 2 * s, swatchW, rowH - 7 * s)
    end
    Kit.text("body", name, px0 + pad + swatchW + 8 * s, ry + 6 * s)
    Kit.text("small", spec and string.format("h %d  %s", spec.h, spec.art)
             or "TileShape does not know this class",
             px0 + pad + swatchW + 8 * s, ry + 22 * s, PAL.muted)
    ry = ry + rowH
  end
  Kit.popClip()

  if #hits == 0 then
    Kit.text("small", "no class matches", px0 + pad, iy + 4 * s, PAL.muted)
  elseif maxScroll > 0 then
    -- A RAIL, so "there are more below" is something you can see rather than
    -- something you find out by accident. This list is forty rows on most
    -- mods and the search box is a filter, not the only way through it.
    local railW = 4 * s
    local rx = px0 + pw - railW - 3 * s
    Theme.col(PAL.cardBorder, 0.18)
    love.graphics.rectangle("fill", rx, iy, railW, bodyH, railW, railW)
    local thumb = math.max(20 * s, bodyH * (perPage / #hits))
    local ty = iy + (bodyH - thumb) * (off / maxScroll)
    Theme.col(PAL.cardBorder, 0.6)
    love.graphics.rectangle("fill", rx, ty, railW, thumb, railW, railW)
    love.graphics.setColor(1, 1, 1, 1)
  end
  return true
end

-- THE OVERWORLD, AS ONE PICTURE.
--
-- Every map reachable from the open one by CONNECTIONS, drawn where it
-- actually sits -- see tools/map-editor/WorldAtlas.lua for the arithmetic and
-- why it comes out of the engine's own crossing rule rather than a second
-- guess at it.
--
-- BLOCKS, NOT A THUMBNAIL OF THE ART. Rendering every map's tiles would mean
-- building several hundred maps to look at a layout, which is minutes of work
-- for a picture about SHAPE. A filled rectangle per map, named, with the open
-- one lit, answers "does this line up" and "what is north of here" -- which
-- are the questions a single-map view cannot answer at all.
function Preview.drawWorld(S, Kit, x, y, w, h)
  local s = Kit.scale
  local okWA, WorldAtlas = pcall(require, "tools.map-editor.WorldAtlas")
  if not okWA then return end

  -- Rebuilt when the map or the edit stamp moves: connections are editable,
  -- and a cached layout would keep showing the world as it was before.
  -- EVERY REGION, NOT THE ONE THIS MAP HAPPENS TO BE IN.
  --
  -- This was `WorldAtlas.build(S.data, S.mapId)`, which walks out from the
  -- open map along its connections -- so it drew the connected COMPONENT the
  -- map is in and stopped. Johto and Kanto touch only through indoor maps and
  -- are two components; Gen 1's Kanto has islands of its own; Prism's world
  -- has a shape nothing here can assume. From inside Azalea Town the view had
  -- no way even to know Kanto was there, which is what "it only shows part of
  -- the map" is.
  --
  -- `WorldAtlas.world` finds every component and packs them into one picture.
  -- Keyed on the edit stamp ALONE now, not on the map: the world does not
  -- change when you open a different map in it, and rebuilding a few hundred
  -- placements on every selection was work done to produce the same answer.
  local key = tostring(S.mapEditsStamp or 0) .. "|"
    .. tostring(S.data and S.data.version or "")
  if S._pvWorldKey ~= key then
    S._pvWorldKey = key
    S._pvWorldAtlas = WorldAtlas.world(S.data)
    S._pvWorldZoom = nil
    -- WHAT IT FOUND, IN THE LOG, ONCE PER REBUILD.
    --
    -- A region is a connected component, and which components an import falls
    -- into is not something the picture can explain: two maps somebody joined
    -- while trying something out look exactly like a two-map island a map pack
    -- brought in. Naming each region's anchor and size is the difference
    -- between "there is rubble between Johto and Kanto" and knowing which maps
    -- it is.
    pcall(function()
      local a = S._pvWorldAtlas
      if not a then return end
      local Logger = require("src.core.Logger")
      Logger.info("map editor world: %d region(s)", #a.regions)
      for i, r in ipairs(a.regions) do
        Logger.info("  %d. %-28s %3d map(s)  anchor=%s%s", i, r.name, r.count,
                    tostring(r.anchor), r.minor and "  [minor]" or "")
      end
    end)
  end
  local atlas = S._pvWorldAtlas

  love.graphics.setColor(0.03, 0.04, 0.11, 0.97)
  love.graphics.rectangle("fill", x, y, w, h, 8 * s, 8 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(x, y, w, h)

  if not atlas or not next(atlas.maps) then
    Kit.text("small", "no map in this import connects to another one - there "
             .. "is no overworld to draw", x + 12 * s, y + 12 * s, PAL.muted)
    return
  end

  local b = atlas.bounds
  local pad = 16 * s
  local chipH = 24 * s
  -- ONE FRAME BEHIND, and that is fine: the chips wrap according to their own
  -- widths, which are not known until they are laid out, and a body measured
  -- from last frame's row count settles after one frame rather than fighting
  -- itself. Seeded at one row so the first frame is never wrong by more than
  -- a row height.
  local rows = S._pvWorldChipRows or 1
  local viewX, viewY = x + pad, y + pad + rows * chipH + (rows - 1) * 4 * s + 6 * s
  local viewW = w - 2 * pad
  local viewH = (y + h - pad - 20 * s) - viewY

  -- WHICH REGION THE VIEW IS ON.
  --
  -- Fitting the WHOLE packed world into the card was right when there was one
  -- region and useless with three: every map ends up four pixels across and
  -- the reader is looking at a diagram of nothing. So the view frames ONE
  -- region -- by default the one holding the open map, which is the region
  -- they were just working in -- and zooming out reaches the rest.
  local focus = S._pvWorldFocus
  if not (focus and atlas.regions[focus]) then
    focus = atlas.byMap[S.mapId or ""] or 1
    S._pvWorldFocus = focus
  end
  local fr = atlas.regions[focus]

  local fitW = math.max(1, fr.w)
  local fitH = math.max(1, fr.h)
  local fit = math.min(viewW / fitW, viewH / fitH)
  local zoom = S._pvWorldZoom or fit
  S._pvWorldZoom = zoom
  -- CENTRED ON THE FRAMED REGION, not on the whole picture: at fit they are
  -- the same and at any other zoom they are not, and it is the region the
  -- reader asked for that has to stay under the pointer.
  local fcx = fr.x + fr.w / 2
  local fcy = fr.y + fr.h / 2
  local pan = S._pvWorldPan or { 0, 0 }
  S._pvWorldPan = pan
  local ox = viewX + viewW / 2 - (fcx - b.x0) * zoom + pan[1]
  local oy = viewY + viewH / 2 - (fcy - b.y0) * zoom + pan[2]

  -- ---------------------------------------------------------------- panning
  --
  -- RIGHT OR MIDDLE, which is what the flat map and the big-tile view in the
  -- voxel drawer already take, and what a hand that has used either arrives
  -- here expecting. LEFT is not offered: in this view left-click opens the map
  -- under the pointer, and a drag that both pans and opens something is the
  -- kind of control that gets used once.
  --
  -- Polled rather than event-driven for the same reason the viewport polls:
  -- this is drawn from inside a frame, and there is no press/release pair to
  -- hang a drag on.
  if love.mouse and love.mouse.isDown then
    local inside = Kit.mouseX >= x and Kit.mouseX <= x + w
                   and Kit.mouseY >= y and Kit.mouseY <= y + h
    local held = love.mouse.isDown(2) or love.mouse.isDown(3)
    local drag = S._pvWorldDrag
    if held and (drag or inside) then
      if drag then
        pan[1] = pan[1] + (Kit.mouseX - drag[1])
        pan[2] = pan[2] + (Kit.mouseY - drag[2])
      end
      S._pvWorldDrag = { Kit.mouseX, Kit.mouseY }
    else
      S._pvWorldDrag = nil
    end
  end

  -- CLAMPED TO THE PICTURE. Without this a fast drag walks the whole world off
  -- the card and leaves an empty box with no way back except closing the view
  -- -- and "it disappeared" is not a state anybody guesses their way out of.
  local spanW = (b.x1 - b.x0) * zoom
  local spanH = (b.y1 - b.y0) * zoom
  local limitX = math.max(viewW, spanW)
  local limitY = math.max(viewH, spanH)
  pan[1] = math.max(-limitX, math.min(limitX, pan[1]))
  pan[2] = math.max(-limitY, math.min(limitY, pan[2]))
  ox = viewX + viewW / 2 - (fcx - b.x0) * zoom + pan[1]
  oy = viewY + viewH / 2 - (fcy - b.y0) * zoom + pan[2]

  -- ------------------------------------------------------- the region chips
  --
  -- The list of regions IS the answer to "where is the rest of the world" --
  -- so it is on screen whether or not anybody presses it.
  local chipRows = 1
  do
    -- WRAPPED, NOT TRUNCATED. This used to `break` at the right-hand edge, so
    -- a world with four regions showed three chips and the fourth was
    -- unreachable -- the same class of bug as a tab that never draws: the
    -- feature is there and there is no way to press it.
    local cx2, cy2 = x + 12 * s, y + pad - 4 * s
    for i, r in ipairs(atlas.regions) do
      -- THE TAIL IS WHAT TELLS TWO REGIONS APART, and an ellipsis eats it.
      -- Ten scratch maps called NEW_BARK_TOWN_2..11 all draw as "NEW BARK
      -- T...", which is ten identical chips over ten different regions. Where
      -- the name will not fit, keep its END.
      local label = string.format("%s (%d)", r.name, r.count)
      local cw = math.min(200 * s, Kit.textWidth("small", label) + 20 * s)
      local room = cw - 12 * s
      if Kit.textWidth("small", label) > room then
        local tail = label
        while #tail > 4 and Kit.textWidth("small", "..." .. tail) > room do
          tail = tail:sub(2)
        end
        label = "..." .. tail
      end
      if cx2 > x + 12 * s and cx2 + cw > x + w - 12 * s then
        cx2, cy2 = x + 12 * s, cy2 + chipH + 4 * s
        chipRows = chipRows + 1
      end
      if Kit.chip(cx2, cy2, cw, chipH, label, i == focus) then
        S._pvWorldFocus = i
        S._pvWorldZoom = nil        -- a new region is framed, not inherited
        S._pvWorldPan = nil
      end
      cx2 = cx2 + cw + 6 * s
    end
    S._pvWorldChipRows = chipRows
  end

  Kit.pushClip(x, y, w, h)

  -- ONE PLATE PER REGION, UNDER ITS MAPS, so the packing reads as an
  -- arrangement of separate worlds rather than as one continent with odd gaps
  -- in it. The space between two regions is not geography and must not look
  -- like it.
  for _, r in ipairs(atlas.regions or {}) do
    local rx = ox + (r.x - b.x0) * zoom
    local ry = oy + (r.y - b.y0) * zoom
    local pad2 = 3 * s
    Theme.col(PAL.cardBorder, 0.10)
    love.graphics.rectangle("fill", rx - pad2, ry - pad2,
                            r.w * zoom + 2 * pad2, r.h * zoom + 2 * pad2,
                            4 * s, 4 * s)
    Theme.stroke(rx - pad2, ry - pad2, r.w * zoom + 2 * pad2,
                 r.h * zoom + 2 * pad2, 4 * s, PAL.cardBorder, 0.35, 1)
    local cap = string.format("%s  -  %d map%s%s", r.name, r.count,
                             r.count == 1 and "" or "s",
                             r.minor and "  (a pair, not a region)" or "")
    Kit.text("small", Kit.ellipsize("small", cap, r.w * zoom),
             rx, ry - 15 * s, PAL.caption)
  end

  for _, id in ipairs(atlas.order) do
    local m = atlas.maps[id]
    local mx = ox + (m.x - b.x0) * zoom
    local my = oy + (m.y - b.y0) * zoom
    local mw, mh = m.w * zoom, m.h * zoom
    local here = (id == S.mapId)
    -- The open map is lit; everything else is the same weight, because the
    -- point of the picture is the SHAPE of the world rather than a ranking.
    if here then
      Theme.col(PAL.blue, 0.30)
    else
      Theme.col(PAL.rowBg, 0.75)
    end
    love.graphics.rectangle("fill", mx, my, mw, mh, 2 * s, 2 * s)
    Theme.stroke(mx, my, mw, mh, 2 * s, here and PAL.blue or PAL.cardBorder,
                 here and 0.9 or 0.45, here and 2 * s or 1)
    if mw > 46 * s and mh > 16 * s then
      Kit.text("small", Kit.ellipsize("small", id, mw - 6 * s),
               mx + 3 * s, my + 3 * s, here and PAL.heading or PAL.muted)
    end
    -- CLICK TO GO THERE. Walking the world and opening what you are looking at
    -- is the whole reason to draw it.
    if Kit.press(mx, my, mw, mh) and not here then
      S.mapId = id
      S._pvCenteredFor = nil
      S.pvNotice = "opened " .. id
    end
  end
  Kit.popClip()

  -- ---------------------------------------------------------- what is wrong
  --
  -- Reported, because these two are invisible from inside a single map and
  -- both are real authoring mistakes rather than curiosities.
  local fy = y + h - 18 * s
  -- A SEAM THAT DRIFTS BY A BLOCK IS THE CARTRIDGE, NOT A MISTAKE.
  --
  -- This said "its connections disagree about where it sits" in warning
  -- yellow for every double placement, which reads as something the author
  -- broke and should fix. Most of them are Gen 2's own Kanto: its cycles do
  -- not close -- Celadon to Route 14 the long way round lands one block from
  -- Celadon to Route 14 the short way -- and every edge involved is symmetric
  -- with an exact offset. The game never draws two branches at once, so it
  -- never has to reconcile them. Nothing is wrong and there is nothing to do.
  --
  -- So the two are separated: a real problem still interrupts, and the
  -- cartridge's own arithmetic is reported as the footnote it is.
  local worst, drift = nil, 0
  local seams = 0
  for _, c in ipairs(atlas.conflicts) do
    local d = c.missing and math.huge or (WorldAtlas.conflictDrift(c) or 0)
    if d <= WorldAtlas.SEAM_DRIFT then
      seams = seams + 1
    elseif d > drift then
      worst, drift = c, d
    end
  end
  if worst then
    local msg
    if worst.missing then
      msg = string.format("%s connects %s to %s, which this import does not "
                          .. "have", tostring(worst.from), tostring(worst.dir),
                          tostring(worst.id))
    else
      msg = string.format("%s is placed twice, %d blocks apart - its "
                          .. "connections disagree about where it sits",
                          tostring(worst.id), drift)
    end
    Kit.text("small", Kit.ellipsize("small", msg, w - 24 * s),
             x + 12 * s, fy, PAL.yellow)
  elseif seams > 0 then
    local n = 0
    for _ in pairs(atlas.maps) do n = n + 1 end
    local rn = #(atlas.regions or {})
    Kit.text("small", Kit.ellipsize("small", string.format(
      "%d map%s in %d region%s  -  %d seam%s drift by a block or two, which "
      .. "is the cartridge's own arithmetic and not something to fix  -  "
      .. "right-drag to pan", n, n == 1 and "" or "s", rn,
      rn == 1 and "" or "s", seams, seams == 1 and "" or "s"), w - 24 * s),
      x + 12 * s, fy, PAL.muted)
  else
    local n = 0
    for _ in pairs(atlas.maps) do n = n + 1 end
    local rn = #(atlas.regions or {})
    -- SAYS WHAT THE GAPS ARE. Inside a region every offset is the engine's own
    -- arithmetic; between regions there is none, because the cartridge never
    -- puts two regions in one space. A reader who takes the packing for
    -- geography will "fix" a seam that was never there.
    Kit.text("small", Kit.ellipsize("small", string.format(
      "%d map%s in %d region%s%s  -  click one to open it, right-drag to pan "
      .. "-  regions sit side by side in the cartridge's own order; only the "
      .. "layout INSIDE one is real",
      n, n == 1 and "" or "s", rn, rn == 1 and "" or "s",
      atlas.truncated and " (stopped at the walk limit)" or ""), w - 24 * s),
      x + 12 * s, fy, PAL.muted)
  end
end

function Preview.drawDeferred(S, Kit)
  local s = Kit.scale
  -- THE WORLD VIEW, OVER THE VIEWPORT.
  --
  -- Painted here rather than in `draw` because the map render and the tools
  -- column are one function: an early return that skipped the map would take
  -- the tool buttons and the map list with it, which is the half of the panel
  -- you need in order to turn this back off.
  --
  -- Over the whole viewport rectangle, so it reads as "the viewport is showing
  -- the world now" rather than as a floating window.
  if S.pvWorld and S._pvViewX then
    Preview.drawWorld(S, Kit, S._pvViewX, S._pvViewY,
                      S._pvViewW or 640, S._pvViewH or 480)
  end
  -- THE SCULPTING SURFACE IS NOT DRAWN HERE.
  --
  -- It was, over this same viewport, and that was wrong twice. It covered the
  -- map -- which is where cells are PICKED, so sculpting hid the thing you
  -- sculpt from -- and Kit has no z-order, so the map underneath went on
  -- taking every click that landed on the overlay. A panel drawn over live hit
  -- targets is worse than one not drawn at all: it looks like it works.
  --
  -- It lives in the voxel drawer's own right-hand pane instead, in place of
  -- the cell grid, which is the half of the drawer that was showing numbers
  -- about cells you are not editing. See Voxels.drawSculpt.
  drawClassMenu(S, Kit)
  local menu = S._pvSourceMenu
  if menu then
    -- its own backing plate, or the world shows through the gaps between rows
    Kit.card(menu.x - 4 * s, menu.y - 4 * s, menu.w + 8 * s,
             #menu.srcs * menu.h + 8 * s)
    local ry = menu.y
    for _, src in ipairs(menu.srcs) do
      if Kit.button(menu.x, ry, menu.w, menu.h - 4 * s, src.label,
                    { kind = (menu.cur and src.id == menu.cur.id) and "accent"
                        or "ghost", font = "small" }) then
        S.voxelSource = src.id
        -- Everything derived from the old source has to go: the class table,
        -- the mesh, and the VOXELS tab's own cached list. A stale mesh would
        -- show the previous mod's world under the new mod's name.
        S.pvClassesFor, S.pv3DKey, S.pvSourceOpen = nil, nil, false
        S.voxClasses, S.voxClassesFor = nil, nil
        S._pvSourceMenu = nil
      end
      ry = ry + menu.h
    end
  end
end

-- Selecting a map has to clear the per-map selections every tool keeps, or the
-- WARPS panel opens pointing at warp 7 of a map that has two.
function Preview.select(S, id)
  if S.mapId == id then return end
  S.mapId = id
  S.pvCell = nil
  -- The built mesh belongs to the map it was built from. Dropped by hand
  -- rather than left for the key check: a mesh is GPU memory, and keeping the
  -- previous map's alive until the next 3D frame happens to notice is a leak
  -- for anyone browsing maps in the 2D view.
  if S.pv3D and S.pv3D.mesh and S.pv3D.mesh.release then
    pcall(S.pv3D.mesh.release, S.pv3D.mesh)
  end
  S.pv3D, S.pv3DKey, S.pvFocus, S.pvDist = nil, nil, nil, nil
  S.warpSelected, S.warpScroll, S.warpMapOpen = nil, 0, false
  S.objSelected, S.objScroll = nil, 0
  S.scrSelected, S.scrScroll, S.scrProblems = nil, 0, nil
  S.pvNotice = nil
end

function Preview.wheelmoved(S, dy)
  -- THE WORLD VIEW TAKES THE WHEEL WHILE IT IS UP. Zooming the map underneath
  -- a picture of the world is a control acting on something nobody can see.
  if S.pvWorld then
    local z = S._pvWorldZoom
    if z then
      S._pvWorldZoom = math.max(0.4, math.min(24, z * (1 + 0.12 * (dy or 0))))
    end
    return true
  end

  -- AN OPEN PICKER OWNS THE WHEEL, wherever the pointer is. It is what the
  -- reader is looking at, and it is the one list here with forty rows in it --
  -- without this the notch went to the camera behind the popup, so the class
  -- list could only ever show the rows that happened to fit.
  if S.pvClassOpen then
    S.pvClassScroll = math.max(0, (S.pvClassScroll or 0) - (dy or 0))
    return
  end
  -- In the 3D viewport the wheel is the camera's distance -- multiplicative,
  -- because a fixed step is a crawl when you are far out and a jump when you
  -- are close in. Everywhere else it scrolls the map list.
  if S.pv3DActive then
    local step = 1.15 ^ (-(dy or 0))
    S.pvDist = math.max(24, math.min(20000, (S.pvDist or 400) * step))
    return
  end
  S.pvScroll = math.max(0, (S.pvScroll or 0) - (dy or 0))
end

function Preview.keypressed(S, key)
  if S.pv3DActive then
    if key == "left" then S.pvYaw = (S.pvYaw or 0) - 0.12; S.pvViewName = nil end
    if key == "right" then S.pvYaw = (S.pvYaw or 0) + 0.12; S.pvViewName = nil end
    if key == "up" then
      S.pvAngle = math.max(1.5, (S.pvAngle or 35) - 3); S.pvViewName = nil
    end
    if key == "down" then
      S.pvAngle = math.min(88.5, (S.pvAngle or 35) + 3); S.pvViewName = nil
    end
    -- F frames the selection, Home frames the map. Getting lost in an orbit is
    -- easy and there is no horizon to get back to, so both ways back are one
    -- key -- the same two keys, and roughly the same behaviour, as every other
    -- 3D tool.
    if key == "f" and Viewport3D and S.pv3D then
      Viewport3D.frame(S, S.pv3D, S.pvCell)
    end
    if key == "home" and Viewport3D and S.pv3D then
      Viewport3D.frame(S, S.pv3D, nil)
    end
    if key == "5" or key == "kp5" then S.pvOrtho = not S.pvOrtho end
    if Viewport3D then
      if key == "7" or key == "kp7" then Viewport3D.setView(S, "top") end
      if key == "1" or key == "kp1" then Viewport3D.setView(S, "front") end
      if key == "3" or key == "kp3" then Viewport3D.setView(S, "side") end
      if key == "0" or key == "kp0" then Viewport3D.setView(S, "user") end
    end
    if key == "g" then S.pvGrid = (S.pvGrid == false) end
    -- DIAGNOSTICS MOVED OFF `D`, which is now strafe-right.
    --
    -- WASD is what every 3D tool means by "move the camera", and half of it
    -- collided with a debug toggle. F3 is what every 3D tool means by "show me
    -- the numbers", so the two swap and neither is a surprise. `d` is kept as
    -- a second binding only while a modifier is held, so the old habit still
    -- works and never fires mid-flight.
    if key == "f3" then S.pvDiag = not S.pvDiag end
    if key == "d" then
      local kb = love.keyboard and love.keyboard.isDown
      if kb and (kb("lctrl", "rctrl") or kb("lgui", "rgui")) then
        S.pvDiag = not S.pvDiag
      end
    end
    return
  end
  -- WASD PANS THE FLAT VIEW TOO, not only the 3D one.
  --
  -- The fly camera has taken WASD since it existed, so the hand that learned
  -- it in the voxel view arrives in the flat one and finds nothing there --
  -- and "the keys stopped working" is the same complaint whether the cause is
  -- a focused text box or a binding that only exists in one view.
  local step = 32
  -- THE LETTERS ONLY WHEN NOTHING IS HELD. Ctrl+S is Save, and App dispatches
  -- to this panel whether or not it handled the key itself -- so an unguarded
  -- `s` would save the map AND scroll it, which is a surprise attached to the
  -- one shortcut that writes to disk.
  local bare = true
  do
    local kb = love and love.keyboard and love.keyboard.isDown
    if kb and (kb("lctrl", "rctrl") or kb("lgui", "rgui")
               or kb("lalt", "ralt")) then
      bare = false
    end
  end
  local function letter(k) return bare and key == k end
  if key == "left" or letter("a") then S.pvCamX = (S.pvCamX or 0) - step end
  if key == "right" or letter("d") then S.pvCamX = (S.pvCamX or 0) + step end
  if key == "up" or letter("w") then S.pvCamY = (S.pvCamY or 0) - step end
  if key == "down" or letter("s") then S.pvCamY = (S.pvCamY or 0) + step end
end

return Preview
