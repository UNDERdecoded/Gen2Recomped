-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- TERRAIN -- the Gen 4 ground tool.
--
-- Reported: *"the map painter tiles arent working at all for platinum nothing
-- shows"*, then *"since gen4 doesnt have a tileset we need a way to paint
-- terrain textures too"*.
--
-- TILES is absent on a Sinnoh map, correctly: `Tiles.actsOn` needs a block
-- space to paint from and Gen 4 has none -- the ground is an NSBMD mesh, there
-- is no metatile, and the stand-in tileset is synthesised artwork with no
-- `blocks` table. A palette of 256 checkerboard swatches that wrote block ids
-- nothing reads was the previous behaviour and was worse than an empty one.
--
-- This is what painting a Gen 4 map actually is: the cell's BEHAVIOUR byte,
-- plus whether the cell is blocked. Between them they are the ground's whole
-- editable surface on this cartridge -- what it looks like in the editor, what
-- the encounter tables consult, whether you can surf on it, whether a ledge
-- throws you south, and whether you can stand there at all.
--
-- See `tools/map-editor/Gen4Terrain.lua` for the catalogue and the reader, and
-- `MapEdits.writeTerrainCell` for the measured two-array invariant. The split
-- is deliberate: this file is a panel and owns no facts.

local Edits = require("tools.map-editor.MapEdits")
local BodyFill = require("tools.map-editor.BodyFill")
local MapKind = require("tools.map-editor.MapKind")
local Gen4Terrain = require("tools.map-editor.Gen4Terrain")

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 226, 96, 96 }, accent = { 120, 200, 255 },
}

local T = { fillsBody = true }

local function store(S)
  if not S.mapEdits then S.mapEdits = (Edits.load()) end
  return S.mapEdits
end

local function game(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring(S.version or v or "unknown")
end

local function markEdited(S)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
end

local function mapDef(S)
  return S.data and S.data.maps and S.data.maps[S.mapId or ""] or nil
end

-- WHAT THIS PANEL CAN ACT ON -- and NOT `Gen4Terrain.appliesTo`, which is the
-- trap this tool's neighbour already fell into and documented.
--
-- `appliesTo` requires the behaviour string to be ON the def, and only 302 of
-- Platinum's 593 map defs carry it directly: the other 291 receive it from
-- their shared layout in `MapLoader.resolveBlocks`, which has not necessarily
-- run when Sidebar builds the tool list. Keying availability on it would hide
-- this tool on half of Sinnoh -- present on Twinleaf, absent on the route next
-- to it, for no reason the user could see.
--
-- `MapKind.meshGround` is the one place that knows the three signals of a
-- mesh-ground map. `appliesTo` still guards every WRITE below, where the
-- string either exists or the edit honestly cannot be made.
function T.actsOn(S, def)
  return MapKind.meshGround(S, def)
end

-- THE BRUSH. One behaviour, held across maps on purpose: painting the same
-- terrain onto three connected routes is the normal job, and a brush that
-- reset on every map change would make it three trips to the palette.
function T.brush(S)
  local b = S.terrainBrush
  if type(b) ~= "number" then return 0 end
  return math.floor(b) % 256
end

-- PAINT ONE CELL, written twice like every other edit in this editor: into the
-- live def so the next frame draws it, and into the store so it survives the
-- session and a re-import.
--
-- The live write and the stored write go through the SAME function in opposite
-- directions -- `writeTerrainCell` for the def, `setTerrain` for the store --
-- and the store is the one that merges, so painting a behaviour onto a blocked
-- cell leaves it blocked. A cell is blocked or not for reasons (a wall, a
-- cliff) that have nothing to do with what it is made of.
function T.paintCell(S, cx, cy, behaviour)
  local def = mapDef(S)
  if not Gen4Terrain.appliesTo(def) then return false end
  behaviour = behaviour == nil and T.brush(S) or behaviour
  local _, blocked = Gen4Terrain.readCell(def, cx, cy)
  if blocked == nil then return false end
  if not Edits.writeTerrainCell(def, cx, cy, behaviour, blocked) then
    return false
  end
  Edits.setTerrain(store(S), game(S), S.mapId, cx, cy, behaviour, nil)
  markEdited(S)
  -- The renderer holds the old ground, and on a Gen 4 map it holds it as BAKED
  -- CANVASES keyed per chunk -- so the eviction is not optional housekeeping,
  -- it is the difference between a painted cell appearing and nothing
  -- happening at all.
  pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
  return true
end

-- BLOCK OR UNBLOCK ONE CELL, keeping the behaviour under it.
--
-- `Gen4Maps.COLLISION` (0x8000) is NOT touched: measured over 813,056 cells in
-- the Platinum cache it is set exactly zero times -- Sinnoh blocks a cell with
-- metatile 255 and nothing else -- so a control that toggled the bit would
-- have no effect anywhere. `writeTerrainCell` writes the 255.
function T.setBlocked(S, cx, cy, blocked)
  local def = mapDef(S)
  if not Gen4Terrain.appliesTo(def) then return false end
  local behaviour = Gen4Terrain.readCell(def, cx, cy)
  if behaviour == nil then return false end
  if not Edits.writeTerrainCell(def, cx, cy, behaviour, blocked) then
    return false
  end
  Edits.setTerrain(store(S), game(S), S.mapId, cx, cy, nil, blocked and true or false)
  markEdited(S)
  pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
  return true
end

-- ------------------------------------------------------------ the ground's LOOK
--
-- Asked for repeatedly: *"the terrain painter seems to paint terrain rules but
-- not the actual textures themselves - we need a tile texture painter"*. The
-- behaviour byte says what a cell IS; this says what it LOOKS like, and they
-- are genuinely two edits -- a path through grass is still walkable ground.
--
-- Sinnoh has no per-cell texture ids and its ground is an irregular
-- triangulation (87.5% of its triangles straddle a cell boundary), so a
-- painted cell is drawn as a decal quad laid on the terrain rather than by
-- re-texturing the cartridge's mesh. See `src/render/Gen4Decals.lua`.
function T.paintTexture(S, cx, cy, texture)
  local def = mapDef(S)
  if type(def) ~= "table" then return false end
  texture = texture == nil and S.terrainTexture or texture
  if texture == "" then texture = nil end
  Edits.setCellTexture(store(S), game(S), S.mapId, cx, cy, texture, def)
  markEdited(S)
  -- The decal is baked INTO the chunk canvas, so the bake has to go or the
  -- paint does not appear. `evict` drops the whole map, which takes the bakes
  -- with it -- the same hammer the behaviour painter uses, for the same reason.
  pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
  return true
end

-- THE MAP-VIEW BRUSH, dispatched on the mode the panel is in.
--
-- One entry point so `Preview` does not have to know which of the two edits
-- the panel is currently making -- it knows where the click landed, which is
-- its own business, and nothing else. Without this a drag on the map always
-- painted the behaviour byte however the panel was set, which is a control
-- that silently does something other than what the panel says it does.
function T.paintAt(S, cx, cy)
  if S.terrainMode == "texture" then return T.paintTexture(S, cx, cy, nil) end
  return T.paintCell(S, cx, cy, nil)
end

-- ----------------------------------------------------------------- the heights
--
-- MEASURED FROM THE CARTRIDGE, all 666 chunks of it: 8,974 BDHC plates, 88.8%
-- of them flat, heights running -96 to 480 world units, and every common value
-- a multiple of 8 -- half a tile at `tileUnits = 16`. (The 12.2% that are not
-- multiples of 8 are the sloped plates sampled at their centre, which is the
-- 11.2% that are not flat: the two numbers are the same plates.)
--
-- So the step is 8 and the range is the cartridge's own. None of it is chosen.
T.HEIGHT_STEP = 8
T.HEIGHT_MIN = -96
T.HEIGHT_MAX = 480

-- WHAT THIS MOVES, said plainly because the name promises more than it does.
--
-- BDHC is the height field that sprites, the camera, the ledges and the surf
-- checks read -- "how far off the chunk's floor is this cell". The hill you can
-- SEE is NSBMD geometry in the chunk model and is a separate thing. Raising a
-- cell here lifts what stands on it and leaves the drawn ground where it was,
-- which is right for a ledge or a bridge deck and is not a replacement for
-- sculpting the mesh.
function T.heightAt(S, cx, cy)
  local def = mapDef(S)
  local edits = def and def.gen4HeightEdits
  if type(edits) == "table" then
    local v = edits[math.floor(cx) .. "," .. math.floor(cy)]
    if type(v) == "number" then return v, true end
  end
  -- NOT 0 AS THE FALLBACK. The cartridge's own height under this cell is the
  -- honest baseline, and it is what the renderer will go back to if the
  -- override is removed -- showing 0 would make every unedited cell look like
  -- it had been flattened.
  local okM, Loader = pcall(require, "src.world.MapLoader")
  if okM then
    local okL, map = pcall(Loader.load, S.data, S.mapId)
    local ground = okL and map and map.renderer and map.renderer.gen4Ground
    if ground and ground.heightAt then
      local okH, h = pcall(ground.heightAt, ground, cx, cy)
      if okH and type(h) == "number" then return h, false end
    end
  end
  return nil, false
end

function T.setHeight(S, cx, cy, height)
  local def = mapDef(S)
  if type(def) ~= "table" then return false end
  height = math.max(T.HEIGHT_MIN, math.min(T.HEIGHT_MAX,
                    math.floor((tonumber(height) or 0) / T.HEIGHT_STEP + 0.5)
                    * T.HEIGHT_STEP))
  def.gen4HeightEdits = type(def.gen4HeightEdits) == "table"
                        and def.gen4HeightEdits or {}
  def.gen4HeightEdits[math.floor(cx) .. "," .. math.floor(cy)] = height
  -- The whole table, through the field `gen4ModelEdits` already proved: the
  -- store keeps a sparse map and `applyToMap` copies it onto a freshly
  -- extracted def, so a ROM re-import does not lose the sculpt.
  Edits.setMapField(store(S), game(S), S.mapId, "gen4HeightEdits",
                    def.gen4HeightEdits)
  markEdited(S)
  -- The per-tile height cache holds the OLD number, and it is the one thing an
  -- edit here must invalidate -- without this the sprite stays at the previous
  -- height until something else happens to drop the cache.
  local okM, Loader = pcall(require, "src.world.MapLoader")
  if okM then
    local okL, map = pcall(Loader.load, S.data, S.mapId)
    local ground = okL and map and map.renderer and map.renderer.gen4Ground
    if ground and ground.dropHeightCache then
      pcall(ground.dropHeightCache, ground)
    end
  end
  return true
end

-- Remove the override and go back to the cartridge's own height. A separate
-- action rather than "set it to the BDHC value", which would leave an override
-- that happens to agree today and would not follow a re-import.
function T.clearHeight(S, cx, cy)
  local def = mapDef(S)
  local edits = def and def.gen4HeightEdits
  if type(edits) ~= "table" then return false end
  local key = math.floor(cx) .. "," .. math.floor(cy)
  if edits[key] == nil then return false end
  edits[key] = nil
  Edits.setMapField(store(S), game(S), S.mapId, "gen4HeightEdits", edits)
  markEdited(S)
  local okM, Loader = pcall(require, "src.world.MapLoader")
  if okM then
    local okL, map = pcall(Loader.load, S.data, S.mapId)
    local ground = okL and map and map.renderer and map.renderer.gen4Ground
    if ground and ground.dropHeightCache then
      pcall(ground.dropHeightCache, ground)
    end
  end
  return true
end

-- ------------------------------------------------------------------ the layout
--
-- Measured rather than guessed, because `fillsBody` means the drawer reserves
-- the whole body for this panel and the region needs a content height. A
-- height computed from the same loop that draws cannot disagree with it.
local SW = 22              -- swatch side, before scale
-- A TEXTURE ROW IS TALLER THAN A BEHAVIOUR ROW, because it carries a picture.
--
-- *"make the list have medium sized entries in the list so the user can
-- actually see the model"* was said about the model picker; it is the same
-- complaint waiting to happen here, and a 16x16 swatch in a 26px row is a
-- thumbnail nobody can read. Named once and used by BOTH the row loop and the
-- `measured` height it scrolls against -- those two disagreeing by a few
-- pixels per row is how a 1,500-row list stops reaching its own end.
local TEXROWH = 44

-- THE TEXTURE THUMBNAILS, THROUGH THE DECAL'S OWN LOADER.
--
-- Reported from play: *"we need previews for the textures as well when
-- hovering over them"*.
--
-- `Assets.image` is the same call `Gen4Model.new` makes on `shape.image` to
-- put the picture on the ground, and using it here is deliberate rather than
-- incidental: a swatch that draws proves the painter's half of the lookup
-- resolves too, so the preview and the paint cannot disagree about whether a
-- texture exists. A second loader in this file would be a second answer to
-- the same question -- which is the shape of nearly every bug in this tool.
--
-- `Assets.image` keeps its own cache and falls back to a placeholder rather
-- than raising, so this holds no cache of its own: a second cache in front of
-- a cache is just a way for the two to hold different pictures.
local assetsOnce
local function textureImage(rec)
  if type(rec) ~= "table" or type(rec.path) ~= "string" then return nil end
  if assetsOnce == nil then
    local okA, Assets = pcall(require, "src.render.Assets")
    assetsOnce = (okA and type(Assets) == "table" and Assets.image) and Assets
                 or false
  end
  if not assetsOnce then return nil end
  local okI, image = pcall(assetsOnce.image, rec.path)
  if not okI or not image then return nil end
  -- NEAREST, like every other 16-pixel picture in this project: a terrain
  -- texture smoothed up to 40 pixels is a blur, and the thing the user is
  -- trying to judge is exactly its pixels.
  pcall(image.setFilter, image, "nearest", "nearest")
  return image
end

-- Draw a texture into a box, letter-boxed. Returns false when there was no
-- picture to draw, so the caller can say so rather than leaving a blank hole.
local function drawTexture(image, bx, by, box)
  if not image then return false end
  local okD = pcall(function()
    local iw, ih = image:getDimensions()
    local scale = box / math.max(iw, ih, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, bx + (box - iw * scale) / 2,
                       by + (box - ih * scale) / 2, 0, scale, scale)
  end)
  return okD and true or false
end

-- THE LIVE GROUND, IF THERE IS ONE -- and always through `pcall`.
--
-- `Loader.load` ASSERTS on a map that is not in the registry, and calling it
-- bare from a panel's draw is exactly the crash this tool already shipped
-- once: *"src/world/MapLoader.lua:120: unknown map: REDS_HOUSE_2F"*, every
-- frame, from a sibling panel. Resolved at most once per draw and only when
-- something actually wants it.
local function groundOf(S)
  local okM, Loader = pcall(require, "src.world.MapLoader")
  if not okM then return nil end
  local okL, map = pcall(Loader.load, S.data, S.mapId)
  if not okL then return nil end
  return map and map.renderer and map.renderer.gen4Ground or nil
end

local ROWH = 26            -- a palette row, before scale

local function contentHeight(Kit, groups, used)
  local s = Kit.scale
  local h = 6 * s
  if #used > 0 then
    h = h + Kit.textHeight("caption") + 4 * s + #used * (ROWH * s + 3 * s) + 10 * s
  end
  for _, g in ipairs(groups) do
    h = h + Kit.textHeight("caption") + 4 * s
    h = h + #g.entries * (ROWH * s + 3 * s) + 8 * s
  end
  return h
end

-- One palette row: the class colour, the cartridge's name, the byte. The
-- colour is `Gen4Terrain.colorOf`, which is the SAME table the stand-in
-- artwork draws the cell from -- so the swatch and the square it paints are
-- the same colour by construction and not by two tables agreeing.
local function swatchRow(Kit, cx, cy, cw, behaviour, label, on, note)
  local s = Kit.scale
  local row = ROWH * s
  if Kit.row then Kit.row(cx, cy, cw, row, on) end
  local g = love and love.graphics
  if g and g.setColor then
    local r, gg, b = Gen4Terrain.colorOf(behaviour)
    g.setColor(r, gg, b, 1)
    g.rectangle("fill", cx + 5 * s, cy + (row - SW * s) / 2, SW * s, SW * s,
                3 * s, 3 * s)
    g.setColor(1, 1, 1, 1)
  end
  Kit.text("small", label, cx + (SW + 14) * s, cy + 6 * s)
  Kit.text("small", note or string.format("0x%02X", behaviour),
           cx + cw - 52 * s, cy + 6 * s, PAL.muted)
  return Kit.press(cx, cy, cw, row)
end

function T.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local def = mapDef(S)
  local row = 30 * s
  local hy = y

  if not Gen4Terrain.appliesTo(def) then
    -- OFFERED BUT NOT WRITABLE, which is a real state and not a bug: the tool
    -- list is built from `MapKind.meshGround`, and a cache imported before the
    -- terrain stage is a Gen 4 map with no behaviour array. Say which it is
    -- rather than drawing an empty palette -- an empty palette is what this
    -- whole tool exists to stop being the answer.
    --
    -- THROUGH `BodyFill.region` LIKE EVERY OTHER PATH IN THIS PANEL, and the
    -- layout check is why. The first version drew three lines of text and
    -- returned, which on a 600px body left 550px of unpainted drawer -- the
    -- exact bar this editor has now been bitten by twice. `fillsBody` is a
    -- promise about the whole rectangle and an early return does not get an
    -- exemption from it: the message is short, so the branch that draws the
    -- LEAST is the one most likely to leave a band.
    BodyFill.region(S, Kit, "terrain", x, y, w, math.max(0, (y + h) - y),
                    0, function(cx, cy, cw)
      -- TWO DIFFERENT CAUSES, AND ONLY ONE OF THEM IS THE USER'S TO FIX.
      --
      -- A map the editor CREATED has no `map_layouts` entry behind it, so
      -- nothing could ever resolve a behaviour array for it -- there is no
      -- re-import that would help, and telling the author to re-import is
      -- sending them to do something that cannot work. That map needs a layer
      -- made, which is one button.
      --
      -- A CARTRIDGE map with no layer is the other case: the cache was built
      -- before the terrain stage, and a re-import is exactly right.
      local created = not not (def and def.originMap == nil
                               and type(def.blocks) == "table")
      Kit.text("small", created
               and "This map was created here, so it has no ground yet."
               or "This Platinum map has no terrain layer yet.",
               cx + 4 * s, cy + 6 * s, PAL.yellow)
      if created then
        Kit.text("small", "Give it a blank Sinnoh ground - every cell walkable,",
                 cx + 4 * s, cy + 26 * s, PAL.muted)
        Kit.text("small", "nothing blocked - and the palette appears here.",
                 cx + 4 * s, cy + 42 * s, PAL.muted)
        if Kit.button(cx + 4 * s, cy + 66 * s, 200 * s, 30 * s,
                      "Create terrain layer") then
          local ok, why = Edits.createTerrainLayer(store(S), game(S), S.mapId, def)
          S.terrainNotice = ok and "terrain layer created" or tostring(why)
          if ok then
            markEdited(S)
            pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
          end
        end
      else
        Kit.text("small", "Re-import the ROM with the terrain stage enabled",
                 cx + 4 * s, cy + 26 * s, PAL.muted)
        Kit.text("small", "and the ground palette appears here.",
                 cx + 4 * s, cy + 42 * s, PAL.muted)
      end
      if S.terrainNotice then
        Kit.text("small", tostring(S.terrainNotice), cx + 4 * s, cy + 104 * s,
                 PAL.muted)
      end
    end)
    S.terrainMaxScroll = 0
    return
  end

  -- THE SELECTED CELL, AND WHAT IT IS NOW. The brush is useless without it:
  -- "water" means nothing until you can see that the cell you are about to
  -- paint is currently MOUNTAIN_FLOOR and blocked.
  -- `cx`/`cy`, NOT `x`/`y`. `S.pvCell` is written in exactly one place --
  -- `Preview.lua` -- as `{ cx = cx, cy = cy }`, and every other panel reads it
  -- that way. The first version of this file read `cellX`, which is nil: the
  -- header printed nothing, both buttons acted on cell nil and the height
  -- controls never appeared. This tree's recurring bug, one more time: the
  -- same thing spelled differently in two places that never meet.
  --
  -- It survived a 200-check pass because every assertion about this panel was a
  -- source-text match, and `pan:match('T%.setHeight')` is true of a file that
  -- calls it with nil. The section that caught it drives `T.draw` with a real
  -- cell instead -- see `gen4_terrain_paint_check.lua`.
  local cell = S.pvCell
  local cellX = cell and cell.cx
  local cellY = cell and cell.cy
  local curB, curBlocked
  if cellX then curB, curBlocked = Gen4Terrain.readCell(def, cellX, cellY) end

  if curB then
    Kit.caption(x, hy, string.format("CELL %d, %d", cellX, cellY))
    hy = hy + Kit.textHeight("caption") + 2 * s
    Kit.text("small", Gen4Terrain.label(curB)
             .. (curBlocked and "   (blocked)" or ""),
             x, hy + 4 * s, curBlocked and PAL.red or nil)
    hy = hy + row
    if Kit.button(x, hy, w / 2 - 4 * s, row,
                  curBlocked and "Unblock cell" or "Block cell") then
      T.setBlocked(S, cellX, cellY, not curBlocked)
    end
    if Kit.button(x + w / 2 + 4 * s, hy, w / 2 - 4 * s, row,
                  (S.terrainMode == "texture") and "Paint texture"
                  or "Paint cell") then
      if S.terrainMode == "texture" then
        T.paintTexture(S, cellX, cellY, nil)
      else
        T.paintCell(S, cellX, cellY, nil)
      end
    end
    hy = hy + row + 4 * s

    -- HEIGHT, on the same cell and in the cartridge's own step of 8.
    local hv, overridden = T.heightAt(S, cellX, cellY)
    Kit.text("small", hv and string.format("height %d%s", hv,
                                           overridden and "  (edited)" or "")
                      or "height unavailable - no terrain loaded",
             x, hy + 6 * s, overridden and PAL.accent or PAL.muted)
    if hv then
      for i, sign in ipairs({ -1, 1 }) do
        if Kit.stepper(x + w - (3 - i) * 36 * s, hy, 32 * s, row,
                       sign < 0 and "-" or "+") then
          T.setHeight(S, cellX, cellY, hv + sign * T.HEIGHT_STEP)
        end
      end
    end
    hy = hy + row + 4 * s
    if overridden and Kit.button(x, hy, w, row, "Reset height to cartridge") then
      T.clearHeight(S, cellX, cellY)
    end
    if overridden then hy = hy + row + 2 * s end
    hy = hy + 4 * s
  else
    Kit.text("small", "Pick a cell on the map to paint it.", x, hy + 4 * s,
             PAL.muted)
    hy = hy + row
  end

  -- WHAT THE BRUSH PAINTS. Two different edits on the same cell -- what the
  -- ground IS, and what it LOOKS like -- so one switch rather than two tools:
  -- the cell you have picked and the map you are looking at are the same in
  -- both, and a second tool would mean re-picking the cell to change its look.
  local mode = S.terrainMode or "behaviour"
  local mw = (w - 8 * s) / 2
  if Kit.button(x, hy, mw, row, "GROUND RULES",
                { kind = mode == "behaviour" and "accent" or "ghost",
                  font = "small" }) then
    S.terrainMode = "behaviour"
  end
  if Kit.button(x + mw + 8 * s, hy, mw, row, "TEXTURES",
                { kind = mode == "texture" and "accent" or "ghost",
                  font = "small" }) then
    S.terrainMode = "texture"
  end
  hy = hy + row + 6 * s

  Kit.caption(x, hy, mode == "texture"
              and ("TEXTURE: " .. tostring(S.terrainTexture or "none"))
              or ("BRUSH: " .. Gen4Terrain.label(T.brush(S))))
  hy = hy + Kit.textHeight("caption") + 6 * s

  -- WHAT THE PAINTER ACTUALLY DID, IN THE PANEL THAT DID IT.
  --
  -- Reported from play: *"it doesnt seem to paint them onto the world when i
  -- click with one selected"* -- and from a screenshot that is all anyone can
  -- say. There are four separate things that look identical on screen: the
  -- click never reached the painter, the store took the edit but no cell
  -- routed to a drawn chunk, the cells routed but the decal would not build,
  -- or it built and is behind something. These two lines tell those apart --
  -- the first is this map's own store, the second is the renderer's own count
  -- and the reason it kept, if it has one.
  if mode == "texture" then
    local painted = 0
    for _ in pairs(type(def.gen4TextureEdits) == "table"
                   and def.gen4TextureEdits or {}) do
      painted = painted + 1
    end
    local at = S.pvCell
    local here = at and Gen4Terrain.textureAt(def, at.cx, at.cy) or nil
    Kit.text("small", ("store: %d cell%s painted%s"):format(
             painted, painted == 1 and "" or "s",
             here and (", this cell " .. tostring(here)) or ""),
             x, hy, painted > 0 and PAL.accent or PAL.muted)
    hy = hy + Kit.textHeight("small") + 2 * s
    local ground = groundOf(S)
    local report = ground and ground.decalReport
                   and select(2, pcall(ground.decalReport, ground)) or nil
    Kit.text("small", "ground: " .. tostring(report or "no gen4 ground here"),
             x, hy, PAL.muted)
    hy = hy + Kit.textHeight("small") + 6 * s
  end

  -- ------------------------------------------------- the body, filled exactly
  local groups = Gen4Terrain.groups()
  local used = Gen4Terrain.usedIn(def)
  local textures = mode == "texture" and Gen4Terrain.textures(S.data, def) or nil
  local bodyY = hy
  local bodyH = math.max(0, (y + h) - bodyY)
  local measured = textures
    and (#textures * (TEXROWH * s + 3 * s) + 16 * s)
    or contentHeight(Kit, groups, used)
  local _, maxScroll = BodyFill.region(S, Kit, "terrain", x, bodyY, w, bodyH,
                                       measured,
                                       function(cx, cy, cw)
    local ry = cy + 5 * s
    local pick = T.brush(S)

    -- ------------------------------------------------------- the textures
    if textures then
      -- A FULL BODY OF SLACK EITHER SIDE, for the reason the model picker
      -- carries it: the region paints at `y - scroll`, so an exact band and
      -- that offset disagreeing by one row SKIPS rows that are on screen --
      -- and skipped is not drawn, not merely clipped. 1,150 rows still
      -- collapse to a few dozen.
      local top, bottom = bodyY - bodyH, bodyY + bodyH * 2
      -- NOTHING HOVERED UNTIL A ROW SAYS SO, cleared every frame. Left
      -- standing, the floating preview outlives the pointer and sticks to
      -- the screen -- which is the model picker's reported bug in the other
      -- direction.
      S.terrainTexHover = nil
      local box = (TEXROWH - 8) * s
      for _, t in ipairs(textures) do
        local rh = TEXROWH * s
        if ry + rh >= top and ry <= bottom then
          local on = S.terrainTexture == t.texture
          if Kit.row then Kit.row(cx, ry, cw, rh, on) end
          -- THE SWATCH, and a word when there is not one.
          --
          -- A texture whose picture will not load is a texture the painter
          -- cannot put on the ground either -- same loader -- so saying so
          -- here is the one place the user finds out before painting with
          -- it rather than after.
          local bx, by = cx + 6 * s, ry + 4 * s
          if not drawTexture(textureImage(t), bx, by, box) then
            Kit.text("small", "?", bx + box / 2 - 3 * s, by + box / 2 - 6 * s,
                     PAL.yellow)
          end
          local tx = bx + box + 8 * s
          Kit.text("small", t.texture, tx, ry + 8 * s)
          Kit.text("small", ("%dx%d"):format(t.width or 16, t.height or 16),
                   tx, ry + 24 * s, PAL.muted)
          -- The map's OWN set is marked, because those are the textures the
          -- ground around this cell is already drawn with -- the ones that
          -- will look like they belong.
          Kit.text("small", t.own and "this map" or tostring(t.set),
                   cx + cw - 70 * s, ry + 8 * s,
                   t.own and PAL.accent or PAL.muted)
          -- HOVER IS RECORDED, NOT DRAWN HERE. The enlargement has to land
          -- on top of the rows below it and outside this region's clip, so
          -- it is painted by `T.drawDeferred` after the whole frame -- the
          -- same arrangement the model picker's popup uses, and for the same
          -- reason: Kit has no z-order.
          if Kit.hover and Kit.hover(cx, ry, cw, rh) then
            S.terrainTexHover = { rec = t, x = cx, y = ry, w = cw, h = rh }
          end
          if Kit.press(cx, ry, cw, rh) then
            S.terrainTexture = t.texture
            -- AND THE MODE, SAID OUT LOUD. Picking a texture while the
            -- brush is still set to GROUND RULES is a click that paints a
            -- behaviour byte -- the panel showing a texture name the whole
            -- time. The list is only reachable in texture mode today, so
            -- this is belt and braces rather than a fix; it costs one
            -- assignment and removes a way for the two to drift apart.
            S.terrainMode = "texture"
          end
        end
        ry = ry + TEXROWH * s + 3 * s
      end
      return
    end

    -- ON THIS MAP, FIRST. The palette is 108 entries and a map uses a handful
    -- -- Twinleaf Town uses five. Without this row, picking the terrain
    -- already next to you means hunting the full list for it.
    if #used > 0 then
      Kit.caption(cx, ry, "ON THIS MAP")
      ry = ry + Kit.textHeight("caption") + 4 * s
      for _, e in ipairs(used) do
        if swatchRow(Kit, cx, ry, cw, e.behaviour,
                     e.label .. (e.named and "" or "  ?"),
                     e.behaviour == pick,
                     string.format("%d", e.count)) then
          S.terrainBrush = e.behaviour
        end
        ry = ry + ROWH * s + 3 * s
      end
      ry = ry + 10 * s
    end

    for _, g in ipairs(groups) do
      Kit.caption(cx, ry, string.upper(g.name))
      ry = ry + Kit.textHeight("caption") + 4 * s
      for _, e in ipairs(g.entries) do
        if swatchRow(Kit, cx, ry, cw, e.behaviour, e.label,
                     e.behaviour == pick) then
          S.terrainBrush = e.behaviour
        end
        ry = ry + ROWH * s + 3 * s
      end
      ry = ry + 8 * s
    end
  end)

  S.terrainMaxScroll = maxScroll
end

-- THE HOVERED TEXTURE, ENLARGED, OVER THE WHOLE FRAME.
--
-- Reported from play: *"we need previews for the textures as well when
-- hovering over them"*.
--
-- DRAWN FROM HERE RATHER THAN FROM THE ROW, which is the lesson the model
-- picker paid for twice: *"when i hover over an option all options below it
-- dissapear"*, and *"when i scroll and hover over an area that should mask
-- the list it acts like im hovering over the list still showing over my
-- buttons in the UI"*. The rows are drawn inside `BodyFill.region`'s clip and
-- Kit has no z-order, so anything big drawn from inside a row is either
-- clipped away or painted over the panel's own chrome.
--
-- This one is cheaper than the model picker's: a texture is a PNG, so there
-- is no render target to switch and no canvas to cache. That is also why the
-- row loop can draw its own swatch inline -- an ordinary 2D draw does not
-- take the scissor with it, and a render-target switch does.
local PREVIEW = 128

function T.drawDeferred(S, Kit)
  local hv = S and S.terrainTexHover
  if type(hv) ~= "table" or type(hv.rec) ~= "table" then return end
  local image = textureImage(hv.rec)
  if not image then return end
  local s = Kit.scale
  local box = PREVIEW * s
  local pad = 10 * s
  -- BESIDE THE ROW, and pushed back inside the window when that would put it
  -- off the edge. The panel sits on the left, so the preview goes to its
  -- right; a row near the bottom would otherwise hang off the screen.
  local ww, wh = love.graphics.getDimensions()
  local px = hv.x + hv.w + pad
  local py = hv.y - pad
  if px + box + pad * 2 > ww then px = hv.x - box - pad * 2 end
  if py + box + pad * 3 > wh then py = wh - box - pad * 3 end
  if py < pad then py = pad end
  Kit.card(px, py, box + pad * 2, box + pad * 3)
  drawTexture(image, px + pad, py + pad, box)
  Kit.text("small", tostring(hv.rec.texture), px + pad, py + box + pad + 2 * s)
end

function T.wheelmoved(S, dy)
  return BodyFill.wheel(S, "terrain", dy, S and S.terrainMaxScroll or 0)
end

return T
