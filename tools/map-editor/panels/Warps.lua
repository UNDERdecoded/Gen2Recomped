-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Warps: the doors between maps, and the maps to put doors into.
--
-- WHY THIS PANEL VALIDATES INSTEAD OF JUST EDITING. A Gen 2 warp is not
-- self-sufficient. `Map:warpAtCell` refuses to return a warp whose cell is not
-- an ENTRANCE collision class ($60, $68, $70-$7F) -- that is how the Ruins of
-- Alph chambers and the Ice Path holes stay shut with their warp_events still
-- in the table. So a warp placed on plain floor is inert: it saves, it loads,
-- it shows up in the list, and the player walks over it forever. There is no
-- error anywhere in that chain. The only place that can be caught is here,
-- before the player goes looking for a bug in the engine, so every warp in the
-- list carries the verdict and the ones that are broken say why.
--
-- The other half of the same problem is the destination. `Warp.destination`
-- has careful fallbacks for a `destWarp` that does not exist -- it lands the
-- player at the destination's way back, then its first warp, then its centre --
-- because Prism's Battle Tower ships exactly that and means it. Those
-- fallbacks are right for cartridge data and wrong as a silent response to a
-- typo, so a dangling destination is flagged here too rather than left to
-- resolve into "somewhere".
--
-- MAKE DOOR copies a door this map already has rather than inventing one. The
-- warp cell's quadrant parity decides which of a block's four collision
-- classes is read, so a block that is a doorway in the top-left cell is a wall
-- in the bottom-right one; and a door block that fits ROUTE_1 looks nothing
-- like a door in a HOUSE. An existing warp on the same map with the same
-- parity is a block that is known to work AND known to look right, which is
-- more than any rule could derive.
--
-- LINK BACK writes the return trip. A door with no door behind it is the most
-- common way a hand-made map traps the player, and it is tedious enough to do
-- by hand (add a warp over there, point it back here, then come back and point
-- this one at its index) that it would mostly not get done.

local MapEdits = require("tools.map-editor.MapEdits")
-- The palette, for the two kinds of text this file now draws: guidance in
-- muted grey, and the open cartridge's name in the colour that means "this is
-- a state you are in".
--
-- GUARDED, because this panel is loaded by harnesses that put only
-- tools/map-editor on the path -- Theme lives with the save editor's Kit. A
-- missing palette is a colour, not a feature, so it falls back rather than
-- taking the whole panel down with it.
local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, caption = { 160, 175, 205 },
}

local Warps = {}


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

local function isGen2(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  if ok and GV and type(GV.isGen2) == "function" then
    local ok2, r = pcall(GV.isGen2)
    if ok2 then return r and true or false end
  end
  return true
end

local function def(S, id)
  return S.data and S.data.maps and S.data.maps[id or S.mapId]
end

local function warpsOf(S, id)
  local d = def(S, id)
  return (d and d.warps) or {}
end

local function markDirty(S) S.mapEditsDirty = true end

-- ---------------------------------------------------------------------------
-- the collision question
-- ---------------------------------------------------------------------------

-- The collision class under a cell, or nil when the map's tileset is not
-- loaded. Mirrors Map:cellTile exactly rather than approximating it: an
-- approximation here would pass a cell the engine then rejects, which is the
-- failure this panel exists to prevent.
local function cellClass(S, d, cx, cy)
  if not (d and d.blocks and d.width and d.height) then return nil end
  local ts = S.data and S.data.tilesets and S.data.tilesets[d.tileset]
  local coll = ts and ts.collision
  if not coll then return nil end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local blockId
  if bx < 0 or by < 0 or bx >= d.width or by >= d.height then
    blockId = d.borderBlock or 0
  else
    blockId = d.blocks[by * d.width + bx + 1] or 0
  end
  return coll[blockId * 4 + (cx % 2) + (cy % 2) * 2 + 1]
end

local function isEntrance(cls)
  if cls == nil then return nil end
  local ok, Map = pcall(require, "src.world.Map")
  if ok and Map and type(Map.gen2IsEntrance) == "function" then
    return Map.gen2IsEntrance(cls)
  end
  return cls == 0x60 or cls == 0x68 or (cls >= 0x70 and cls <= 0x7F)
end


-- THE SOUTH-WEST TILE OF A CELL, which is what a map with no collision table
-- answers with instead of a class byte (Map:cellTile's second branch).
local function cellTileId(S, d, cx, cy)
  local ts = S.data and S.data.tilesets and S.data.tilesets[d and d.tileset]
  if not (ts and type(ts.blocks) == "table"
          and d.blocks and d.width and d.height) then return nil end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local blockId
  if bx < 0 or by < 0 or bx >= d.width or by >= d.height then
    blockId = d.borderBlock or 0
  else
    blockId = d.blocks[by * d.width + bx + 1] or 0
  end
  local block = ts.blocks[blockId + 1]
  if type(block) ~= "table" then return nil end
  return block[((cy % 2) * 2 + 1) * 4 + (cx % 2) * 2 + 1]
end

local function inList(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

-- WILL THE ENGINE FIRE A WARP ON THIS CELL? true / false / nil for "cannot
-- tell", plus a phrase for the panel.
--
-- Two alphabets, because Map:cellTile speaks two. A tileset with a collision
-- table answers in Gen 2 CLASSES and the entrance range decides it. An
-- ADOPTED one -- a Gen 1 set the importer brought across whole -- has no
-- collision table and answers in TILE IDS, and there the decision is its own
-- doorTiles/warpTiles lists, which came across with it.
--
-- Reading only the first of those is why every imported map's doors reported
-- "tileset not loaded - cannot check the cell". The tileset was loaded. It
-- simply had nothing called `collision` in it, and never will.
local function cellEntrance(S, d, cx, cy)
  local cls = cellClass(S, d, cx, cy)
  if cls ~= nil then
    return isEntrance(cls) == true, string.format("$%02X", cls)
  end
  local ts = S.data and S.data.tilesets and S.data.tilesets[d and d.tileset]
  if not ts then return nil, nil end
  local t = cellTileId(S, d, cx, cy)
  if t == nil then return nil, nil end
  return (inList(ts.doorTiles, t) or inList(ts.warpTiles, t)),
         string.format("tile $%02X", t)
end

-- A short verdict for one warp: nil when it is fine, otherwise the reason.
local function problemWith(S, d, warp, i)
  if warp.removed then return "blank" end
  if warp.x == nil or warp.y == nil then return "no cell" end
  -- TWO WARPS ON ONE CELL. `Map.warpAt` is a cell-keyed table built by
  -- iterating the warp list, so the later entry overwrites the earlier one and
  -- the earlier warp can never fire again. Nothing complains -- both records
  -- are well-formed and both are in the table -- so this is the only place it
  -- can be seen.
  if i and d and d.warps then
    for j, other in ipairs(d.warps) do
      if j ~= i and not other.removed
         and other.x == warp.x and other.y == warp.y then
        if j < i then return "hidden by warp #" .. j end
        return "hides warp #" .. j
      end
    end
  end
  if d and d.width and (warp.x < 0 or warp.y < 0
      or warp.x >= d.width * 2 or warp.y >= d.height * 2) then
    return "off map"
  end
  local dest = warp.destMap
  if dest == nil then
    return "no destination"
  elseif dest ~= "LAST_MAP" and dest ~= "LAST_WARP" then
    local dd = def(S, dest)
    if not dd then
      return "unknown map"
    elseif not (dd.warps and dd.warps[warp.destWarp or 1]) then
      return "dest warp #" .. tostring(warp.destWarp or 1) .. " missing"
    end
  end
  if isGen2(S) then
    local fires = cellEntrance(S, d, warp.x, warp.y)
    if fires == false then
      return string.format("inert - cell is $%02X, not a door", cls)
    end
  end
  return nil
end

-- A block id that puts an entrance class under (cx,cy). Prefers one this map
-- already uses for a working warp at the same parity -- see the header.
local function doorBlockFor(S, d, cx, cy)
  local q = (cx % 2) + (cy % 2) * 2
  for _, w in ipairs(d.warps or {}) do
    if w.x and w.y and not w.removed
       and (w.x % 2) + (w.y % 2) * 2 == q
       and cellEntrance(S, d, w.x, w.y) == true then
      local bx, by = math.floor(w.x / 2), math.floor(w.y / 2)
      if bx >= 0 and by >= 0 and bx < d.width and by < d.height then
        local id = d.blocks[by * d.width + bx + 1]
        if id then return id, "copied from warp on this map" end
      end
    end
  end
  local ts = S.data and S.data.tilesets and S.data.tilesets[d.tileset]
  if not ts then return nil end
  local coll = ts.collision
  if coll then
    local blocks = math.floor(#coll / 4)
    for id = 0, blocks - 1 do
      if isEntrance(coll[id * 4 + q + 1]) then
        return id, "first door block in " .. tostring(d.tileset)
      end
    end
    return nil
  end
  -- No class table: the adopted-tileset case. A block is a door here when the
  -- tile in this cell's SOUTH-WEST corner is one the set itself names as a
  -- door or a warp -- the same test the engine will make on it.
  if type(ts.blocks) ~= "table" then return nil end
  local slot = ((q >= 2) and 1 or 0)
  slot = (slot * 2 + 1) * 4 + (q % 2) * 2 + 1
  for id = 0, #ts.blocks - 1 do
    local block = ts.blocks[id + 1]
    local t = type(block) == "table" and block[slot] or nil
    if t ~= nil and (inList(ts.doorTiles, t) or inList(ts.warpTiles, t)) then
      return id, "first door block in " .. tostring(d.tileset)
    end
  end
  return nil
end

-- Where to put a warp nobody has placed yet. A SPARE DOOR CELL if the map has
-- one -- that is a warp that works the moment it is created -- and otherwise
-- the first cell with no warp on it.
--
-- Emphatically NOT the selected warp's cell, which is the obvious-looking
-- choice and is wrong: `Map.warpAt` is keyed by cell and built by walking the
-- list, so a second warp on the same cell overwrites the first and the first
-- stops firing. "Add a warp" would have quietly broken the door next to it.
-- Where a new warp goes.
--
-- THE SELECTED CELL FIRST, when there is one and nothing is already there.
-- The reader has just clicked the door they mean; searching the map for the
-- first free entrance instead puts the warp somewhere else entirely and leaves
-- them to walk it back with two steppers.  The search below is what happens
-- when nothing is selected, or when the selection is already a warp.
--
-- Clamped by the bounds test rather than by arithmetic: a selection made on a
-- route and carried into a small house is simply not on this map, and falling
-- through to the search is a better answer than pinning it to an edge.
local function freeCell(S, d)
  if not (d and d.width and d.height) then return 0, 0 end
  local taken = {}
  for _, w in ipairs(d.warps or {}) do
    if w.x and w.y then taken[w.y * d.width * 2 + w.x] = true end
  end
  local sel = S.pvCell
  if sel and sel.cx and sel.cy
     and sel.cx >= 0 and sel.cy >= 0
     and sel.cx < d.width * 2 and sel.cy < d.height * 2
     and not taken[sel.cy * d.width * 2 + sel.cx] then
    return sel.cx, sel.cy, cellEntrance(S, d, sel.cx, sel.cy) == true
  end
  local firstFree
  for cy = 0, d.height * 2 - 1 do
    for cx = 0, d.width * 2 - 1 do
      if not taken[cy * d.width * 2 + cx] then
        if cellEntrance(S, d, cx, cy) == true then return cx, cy, true end
        if not firstFree then firstFree = { cx, cy } end
      end
    end
  end
  if firstFree then return firstFree[1], firstFree[2], false end
  return 0, 0, false
end

-- ---------------------------------------------------------------------------
-- mutations
-- ---------------------------------------------------------------------------

-- Cartridge warps are patched by index; editor-added ones are rewritten in
-- their slot. Same split as objects, same reason.
local function writeField(S, warp, i, key, value)
  local st, g = store(S), game(S)
  warp[key] = value
  if warp.added and warp.editorSlot then
    local m = MapEdits.bucket(st, g, S.mapId, true)
    local slot = m.addedWarps and m.addedWarps[warp.editorSlot]
    if slot then slot[key] = value end
  else
    MapEdits.setWarp(st, g, S.mapId, i, { [key] = value })
  end
  markDirty(S)
end

local function addWarp(S, template)
  local d = def(S)
  if not d then return end
  d.warps = d.warps or {}
  local slot = MapEdits.addWarp(store(S), game(S), S.mapId, template)
  if not slot then return end
  local live = {}
  for k, v in pairs(template) do live[k] = v end
  live.added = true
  live.editorSlot = slot
  d.warps[#d.warps + 1] = live
  S.warpSelected = #d.warps
  markDirty(S)
  return #d.warps, live
end

-- A cartridge warp is BLANKED, never removed from the list, because every
-- other map's destWarp is an index into this list -- compacting it would
-- redirect every door that arrives here by one. An editor-added warp at the
-- end of the list can go, but only if nothing was added after it, for the
-- same reason.
local function deleteWarp(S, i)
  local d = def(S)
  local warp = d and d.warps and d.warps[i]
  if not warp then return end
  local st, g = store(S), game(S)
  if warp.added and warp.editorSlot then
    local m = MapEdits.bucket(st, g, S.mapId, true)
    if m.addedWarps then
      table.remove(m.addedWarps, warp.editorSlot)
      for _, other in ipairs(d.warps) do
        if other.added and other.editorSlot and other.editorSlot > warp.editorSlot then
          other.editorSlot = other.editorSlot - 1
        end
      end
    end
    table.remove(d.warps, i)
    S.warpSelected = nil
    S.warpNotice = "warp removed"
  else
    MapEdits.removeWarp(st, g, S.mapId, i, true)
    d.warps[i] = { x = -1, y = -1, destWarp = 1, removed = true }
    S.warpNotice = "warp blanked (slot kept so other maps' warp ids still point right)"
  end
  markDirty(S)
end

-- The return trip. Adds a warp on the destination standing where this one
-- lands, pointing back at this warp's own index -- and then points this warp
-- at the new one, so both directions are finished in one press.
local function linkBack(S, i, warp)
  local destId = warp.destMap
  local dd = def(S, destId)
  if not dd then return false, "no such destination map" end
  if destId == S.mapId then return false, "that would link the map to itself" end
  dd.warps = dd.warps or {}

  local target = dd.warps[warp.destWarp or 1]
  local x = (target and target.x) or 0
  local y = (target and target.y) or 0

  local slot = MapEdits.addWarp(store(S), game(S), destId,
    { x = x, y = y, destMap = S.mapId, destWarp = i })
  if not slot then return false, "could not write the return warp" end
  local live = { x = x, y = y, destMap = S.mapId, destWarp = i,
                 added = true, editorSlot = slot }
  dd.warps[#dd.warps + 1] = live
  writeField(S, warp, i, "destWarp", #dd.warps)
  markDirty(S)
  return true, string.format("%s warp #%d now returns to warp #%d here",
                             tostring(destId), #dd.warps, i)
end

local function makeDoor(S, warp)
  local d = def(S)
  if not (d and warp and warp.x and warp.y) then return false, "no cell" end
  local id, how = doorBlockFor(S, d, warp.x, warp.y)
  if not id then
    return false, "no block in " .. tostring(d.tileset) .. " is a door at this cell"
  end
  local bx, by = math.floor(warp.x / 2), math.floor(warp.y / 2)
  MapEdits.setBlock(store(S), game(S), S.mapId, bx, by, id)
  if d.blocks and bx < d.width and by < d.height then
    d.blocks[by * d.width + bx + 1] = id
  end
  markDirty(S)
  return true, string.format("block %d laid at %d,%d (%s)", id, bx, by, how)
end

-- ---------------------------------------------------------------------------
-- new maps
-- ---------------------------------------------------------------------------

-- ONLY tilesets this import actually has, and no hardcoded fallback list.
--
-- `MapLoader.build` asserts on a tileset it cannot resolve, so a map carrying
-- a name that is merely plausible does not fail at creation -- it fails the
-- first time the player walks through the door into it, as a crash, in a
-- build where the editor is long closed. A chooser that can only offer real
-- names is the whole fix; there is nothing sensible to fall back TO.
local function tilesetNames(S)
  if S.warpTilesets then return S.warpTilesets end
  local out = {}
  for name in pairs((S.data and S.data.tilesets) or {}) do out[#out + 1] = name end
  table.sort(out)
  S.warpTilesets = out
  return out
end

-- The tileset a new map should start on: the one the player is looking at.
-- It is guaranteed to resolve, and a room being added to a house or a route
-- being added to a region almost always wants the neighbouring tileset.
local function defaultTileset(S)
  local d = def(S)
  if d and d.tileset and S.data.tilesets and S.data.tilesets[d.tileset] then
    return d.tileset
  end
  return tilesetNames(S)[1]
end

-- THE BLOCK A NEW MAP IS FLOORED WITH.
--
-- It used to be the border block, which is block 0 unless the maker says
-- otherwise. The border block is the thing drawn OUTSIDE the map, so in the
-- sets people actually start from it is solid -- and a map floored with a
-- solid block reads as collision class `wall` in every cell, which the voxel
-- view then stands up at 16px. That is the reported "a new map's floor sits
-- at 16px instead of 0": nothing was wrong with the height, the fill was
-- never a floor. Being solid is the border block's job; using it as the
-- interior fill was the mistake.
--
-- So: the lowest block whose four collision quadrants are all walkable, which
-- is a floor by the only definition the data carries. $00 is COLL_FLOOR and
-- is preferred outright; $01 is accepted on a second pass for the tilesets
-- that floor themselves with it. If a tileset offers neither -- an all-solid
-- set, or one whose collision table did not import -- the old behaviour is
-- what is left, and that is correct: there is no floor to pick.
local function floorBlock(S, tilesetId)
  local ts = S.data and S.data.tilesets and S.data.tilesets[tilesetId]
  local coll = ts and ts.collision
  if type(coll) ~= "table" then return nil end
  local count = (ts.blocks and #ts.blocks) or math.floor(#coll / 4)
  for _, walkable in ipairs({ { [0x00] = true },
                              { [0x00] = true, [0x01] = true } }) do
    for id = 0, count - 1 do
      local all = true
      for q = 1, 4 do
        if not walkable[coll[id * 4 + q] or -1] then all = false; break end
      end
      if all then return id end
    end
  end
  return nil
end

-- Injected through applyAll rather than built here, so a map created in this
-- session is exactly the map the next launch will build from the same store.
-- App.load only calls Data:load() once per editor session, so without this the
-- new map would not appear until a restart.
local function createMap(S, spec)
  local st, g = store(S), game(S)
  local id = MapEdits.createMap(st, g, spec)
  if not id then return nil, "could not create the map" end
  MapEdits.applyAll(st, g, S.data.maps, S.data.tilesets, S.data.sprites)
  S.warpMapIds = nil
  markDirty(S)
  return id
end

local function mapIds(S)
  if S.warpMapIds then return S.warpMapIds end
  local out = {}
  for id in pairs((S.data and S.data.maps) or {}) do out[#out + 1] = id end
  table.sort(out)
  S.warpMapIds = out
  return out
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- text too long for its column
-- ---------------------------------------------------------------------------
--
-- CERULEAN_GYM_BADGE_SPEECH_HOUSE is thirty-one characters and the warp list
-- is about twenty wide. Drawn plainly it ran straight out of its column and
-- over the panel beside it -- which is not a cosmetic problem: it printed
-- through the NEW MAP form's fields, so two unrelated things were legible in
-- the same pixels and neither was readable.
--
-- TRIMMED IN PLACE, AND SCROLLED WHEN POINTED AT. A trim alone loses the end
-- of the name, and these names differ at the END --
-- CERULEAN_POKECENTER1_F against CERULEAN_POKECENTER_2_F -- so a list of them
-- trimmed to the same width is a list of identical rows. Hovering plays the
-- rest past the window, which is the one gesture that costs nothing when you
-- do not need it.
--
-- TIME-BASED, NOT FRAME-BASED, so it reads at the same speed whatever the
-- viewport is doing -- and it is the frame timer, not a counter, because a
-- counter would make a heavy map scroll text slowly.
local MARQUEE_PPS = 34          -- pixels a second
local MARQUEE_HOLD = 0.6        -- seconds parked at each end

local function marquee(Kit, font, str, x, y, w, colour, key, hovered)
  str = tostring(str or "")
  local full = Kit.textWidth and Kit.textWidth(font, str) or 0
  if full <= w or not hovered then
    local shown = str
    if full > w and Kit.ellipsize then shown = Kit.ellipsize(font, str, w) end
    Kit.text(font, shown, x, y, colour)
    return false
  end

  -- how far it has to travel, and where it is now
  local over = full - w
  local t = (love and love.timer and love.timer.getTime
             and love.timer.getTime()) or 0
  local travel = over / MARQUEE_PPS
  local period = travel * 2 + MARQUEE_HOLD * 2
  local phase = period > 0 and (t % period) or 0
  local off
  if phase < MARQUEE_HOLD then
    off = 0
  elseif phase < MARQUEE_HOLD + travel then
    off = (phase - MARQUEE_HOLD) * MARQUEE_PPS
  elseif phase < MARQUEE_HOLD * 2 + travel then
    off = over
  else
    off = over - (phase - MARQUEE_HOLD * 2 - travel) * MARQUEE_PPS
  end
  off = math.max(0, math.min(over, off))

  -- CLIPPED TO ITS OWN COLUMN, or a scrolling name is exactly the overflow
  -- this exists to stop -- just moving.
  if Kit.pushClip then Kit.pushClip(x, y - 2, w, 20 * (Kit.scale or 1)) end
  Kit.text(font, str, x - off, y, colour)
  if Kit.popClip then Kit.popClip() end
  return true
end

Warps.marquee = marquee

local function warpLabel(S, i, warp)
  local dest = warp.destMap or "-"
  return string.format("%2d  %3d,%-3d  %s : %s", i,
    warp.x or -1, warp.y or -1, tostring(dest), tostring(warp.destWarp or 1))
end

-- THE CARTRIDGE'S OWN MAP LIST.
--
-- Paged rather than flowed: a Gen 2 cartridge carries two hundred and fifty of
-- these, and a flowed list would make the drawer's page ten thousand pixels
-- tall -- past the cap, and unusable long before it. The search box is how you
-- narrow it and the wheel is how you walk it.
local ROM_ROWS = 9

local function drawRomList(S, Kit, RMI, x, y, w, bottom)
  local s = Kit.scale
  local pad = 16 * s
  local fieldH = 30 * s
  local inner = w - 2 * pad
  local session = S.romImport

  Kit.text("small", "FROM " .. tostring(session.name), x + pad, y, PAL.yellow)
  y = y + 16 * s
  -- WHICH FILE THESE CAME OUT OF. Reading the wrong version's cache is silent
  -- by nature -- it opens, it parses, it is full of maps -- so the path is the
  -- one fact that turns "these are the wrong maps" from baffling into
  -- diagnosable.
  local line = "read from " .. tostring(session.path or "its imported data")
  if Kit.ellipsize then line = Kit.ellipsize("small", line, inner) end
  Kit.text("small", line, x + pad, y, PAL.muted)
  y = y + 18 * s

  S.romQuery = Kit.textfield("rom-q", x + pad, y, inner, fieldH,
                             S.romQuery or "", "search its maps...")
  y = y + fieldH + 6 * s

  local rows = S.romRows
  if not rows or S.romRowsFor ~= session then
    rows = RMI.list(session)
    S.romRows, S.romRowsFor = rows, session
  end
  local hits = {}
  for _, row in ipairs(rows) do
    if RMI.matches(row, S.romQuery or "") then hits[#hits + 1] = row end
  end

  local rowH = 34 * s
  local maxScroll = math.max(0, #hits - ROM_ROWS)
  S.romScroll = math.max(0, math.min(S.romScroll or 0, maxScroll))
  -- for the wheel; see Warps.wheelmoved
  S._romListRect = { x, y, w, ROM_ROWS * rowH }

  Kit.text("small", string.format("%d of %d maps", #hits, #rows),
           x + pad, y - 2 * s, PAL.muted)
  y = y + 14 * s

  for i = S.romScroll + 1, math.min(#hits, S.romScroll + ROM_ROWS) do
    local row = hits[i]
    local ry = y + (i - S.romScroll - 1) * rowH
    if Kit.press(x + pad, ry, inner, rowH - 4 * s) then
      local id, report = RMI.importMap(S, session, row)
      if id then
        S.mapId = id
        S.warpSelected = nil
        S.newMapOpen = false
        S.romImport, S.romRows, S.romRowsFor = nil, nil, nil
        S.warpMapIds, S.warpTilesets = nil, nil
        markDirty(S)
        S.warpNotice = string.format("%s: %d blocks, %d warps, %d objects - %s",
          id, report.blocks, report.warps, report.objects,
          table.concat(report.notes or {}, "; "))
      else
        S.warpNotice = tostring(report)
      end
    end
    Kit.row(x + pad, ry, inner, rowH - 4 * s, false)
    local hoveredRow = Kit.hit and Kit.hit(x + pad, ry, inner, rowH - 4 * s)
      or false
    marquee(Kit, "body", row.id or row.label, x + pad + 8 * s, ry + 3 * s,
            inner - 24 * s, nil, "rom" .. i, hoveredRow)
    -- the TILESET is the thing that decides whether this can come across at
    -- all, so it is on the row rather than behind a click
    Kit.text("small", Kit.ellipsize("small",
               string.format("%dx%d  -  %s", row.w or 0, row.h or 0,
                             tostring(row.tileset or "?")),
               inner - 20 * s),
             x + pad + 8 * s, ry + 18 * s, PAL.muted)
  end
  y = y + ROM_ROWS * rowH + 4 * s

  if #hits == 0 then
    Kit.text("small", "no map matches that", x + pad, y - ROM_ROWS * rowH,
             PAL.muted)
  elseif maxScroll > 0 then
    Kit.text("small", string.format("%d more - scroll or search", maxScroll),
             x + pad, y, PAL.muted)
    y = y + 16 * s
  end

  Kit.text("small", "blocks, size, tileset, warps and objects come across.",
           x + pad, y, PAL.muted)
  y = y + 15 * s
  Kit.text("small", "encounters, scripts and dialogue do not - a script is",
           x + pad, y, PAL.muted)
  y = y + 15 * s
  Kit.text("small", "bytecode against THAT game's addresses.",
           x + pad, y, PAL.muted)
  y = y + 20 * s

  local btnH = 34 * s
  if Kit.button(x + pad, y, inner, btnH, "PICK A DIFFERENT GAME") then
    S.romImport, S.romRows, S.romRowsFor = nil, nil, nil
  end
  return y + btnH + 8 * s
end

local function drawNewMap(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 16 * s
  local fieldH = 30 * s
  local fy = y + pad
  S.newMap = S.newMap
    or { name = "", width = "10", height = "9", tileset = defaultTileset(S) }

  Kit.caption(x + pad, fy, "NEW MAP")
  fy = fy + Kit.textHeight("caption") + 10 * s
  local inner = w - 2 * pad
  local labelW = 60 * s

  -- ------------------------------------------------------- from a cartridge
  --
  -- A BLANK MAP IS THE HARD WAY TO GET A MAP.
  --
  -- Everything below this makes an empty rectangle of border block that you
  -- then paint, cell by cell, into a route. Most of the time what somebody
  -- actually wants already exists on a cartridge -- Gold's Route 47, a Silver
  -- interior, the gym layout from the other version -- and the difference
  -- between the two is an afternoon.
  --
  -- Reads the cartridge directly rather than running the importer: a full
  -- import wipes this build's cache and rebuilds every dataset from that ROM,
  -- which would end with you editing the OTHER game. See RomMapImport's header.
  local okRMI, RMI = pcall(require, "tools.map-editor.RomMapImport")
  if okRMI and type(RMI) == "table" then
    if S.romImport then
      fy = drawRomList(S, Kit, RMI, x, fy, w, y + h)
      return
    end
    -- A DROPDOWN OF GAMES ALREADY IMPORTED, not a file picker.
    --
    -- The picker blocked the loop while it was open and then parsed a two-
    -- megabyte cartridge inside the draw call that followed -- which is a
    -- hang, and it was work the importer had already done. An imported game
    -- has its maps decoded on disk; these are those games.
    local all = RMI.sources(S)
    local sources = {}
    for _, r in ipairs(all) do
      if r.ready then sources[#sources + 1] = r end
    end
    if #sources == 0 then
      Kit.text("small", "no other game is imported yet.", x + pad, fy,
               PAL.muted)
      fy = fy + 16 * s
      Kit.text("small", "import one in the launcher and it appears here.",
               x + pad, fy, PAL.muted)
      fy = fy + 20 * s
    else
      Kit.text("small", "COPY A MAP FROM", x + pad, fy, PAL.muted)
      fy = fy + 16 * s
      -- One button per game rather than a cycling dropdown: there are at most
      -- a handful of Gen 2 versions, and a list you can read is better than a
      -- control you have to press until the right word appears.
      local bw = (inner - (#sources - 1) * 6 * s) / #sources
      for i, srcRow in ipairs(sources) do
        -- A GAME OF ANOTHER GENERATION IS SHOWN, not hidden -- its maps name
        -- tilesets this build does not have, so the import refuses them BY
        -- NAME, which says what is wrong. Marked so the refusal is not a
        -- surprise.
        if Kit.button(x + pad + (i - 1) * (bw + 6 * s), fy, bw, 30 * s,
                      Kit.ellipsize("button", srcRow.label, bw - 12 * s),
                      { kind = srcRow.foreign and "ghost" or "accent",
                        font = "small" }) then
          local session, why = RMI.open(S, srcRow.version)
          if session then
            S.romImport = session
            S.romQuery, S.romScroll = "", 0
            S.romRows, S.romRowsFor = nil, nil
            S.warpNotice = nil
          else
            S.warpNotice = tostring(why)
          end
        end
      end
      fy = fy + 30 * s + 4 * s
      local anyForeign = false
      for _, r in ipairs(sources) do
        if r.foreign then anyForeign = true end
      end
      if anyForeign then
        Kit.text("small", "greyed ones are another generation - their",
                 x + pad, fy, PAL.muted)
        fy = fy + 14 * s
        Kit.text("small", "tilesets come across with the map",
                 x + pad, fy, PAL.muted)
        fy = fy + 16 * s
      end
    end

    -- WHAT IS NOT OFFERED, AND WHY.
    --
    -- An absent row is indistinguishable from a version this build never
    -- heard of, an import that half finished, and a bug in the list -- which
    -- is exactly the question "why is Red not there?" and the panel could not
    -- answer it. Naming them costs two lines and ends the guessing.
    do
      local missing = {}
      for _, r in ipairs(all) do
        if not r.ready then missing[#missing + 1] = r.label end
      end
      if #missing > 0 then
        -- `Kit.ellipsize` where the host provides it: the warps harness drives
        -- this panel with a lighter Kit than the app's, and a trim is a
        -- nicety while a nil call is the end of the panel.
        local line = "not imported: " .. table.concat(missing, ", ")
        if Kit.ellipsize then line = Kit.ellipsize("small", line, inner) end
        Kit.text("small", line, x + pad, fy, PAL.muted)
        fy = fy + 14 * s
        Kit.text("small", "import them in the launcher to copy their maps",
                 x + pad, fy, PAL.muted)
        fy = fy + 18 * s
      end
    end
    Kit.text("small", "or make an empty one:", x + pad, fy, PAL.muted)
    fy = fy + 18 * s
  end

  Kit.text("body", "NAME", x + pad, fy + 7 * s)
  S.newMap.name = Kit.textfield("nm-name", x + pad + labelW, fy,
                                inner - labelW, fieldH, S.newMap.name, "Route 47")
  fy = fy + fieldH + 6 * s

  Kit.text("body", "WIDTH", x + pad, fy + 7 * s)
  S.newMap.width = Kit.textfield("nm-w", x + pad + labelW, fy, 70 * s, fieldH,
                                 S.newMap.width, "10")
  Kit.text("body", "HIGH", x + pad + labelW + 80 * s, fy + 7 * s)
  S.newMap.height = Kit.textfield("nm-h", x + pad + labelW + 130 * s, fy,
                                  70 * s, fieldH, S.newMap.height, "9")
  fy = fy + fieldH + 6 * s

  Kit.text("body", "TILESET", x + pad, fy + 7 * s)
  local list = tilesetNames(S)
  if Kit.button(x + pad + labelW, fy, inner - labelW, fieldH,
                tostring(S.newMap.tileset or "-- none --")) and #list > 0 then
    local at = 0
    for i, v in ipairs(list) do if v == S.newMap.tileset then at = i break end end
    S.newMap.tileset = list[(at % #list) + 1]
  end
  fy = fy + fieldH + 8 * s

  -- Sizes are in BLOCKS, the unit `width`/`height` are actually stored in --
  -- saying "cells" here would have every new map come out twice the size the
  -- player asked for.
  Kit.text("small", "size is in 32px blocks - a Gen 2 route is 20 x 18", x + pad, fy)
  fy = fy + 18 * s
  Kit.text("small", "the map starts filled with this tileset's floor; lay doors", x + pad, fy)
  fy = fy + 15 * s
  Kit.text("small", "with MAKE DOOR once a warp is on it", x + pad, fy)
  fy = fy + 22 * s

  local btnH = 34 * s
  local halfW = (inner - 8 * s) / 2
  local tsOk = S.newMap.tileset ~= nil
    and (S.data.tilesets or {})[S.newMap.tileset] ~= nil
  if not tsOk then
    Kit.text("small", "pick a tileset this import has before creating",
             x + pad, fy - 6 * s)
  end
  if Kit.button(x + pad, fy, halfW, btnH, "CREATE") and tsOk then
    local wB = math.max(1, math.floor(tonumber(S.newMap.width) or 10))
    local hB = math.max(1, math.floor(tonumber(S.newMap.height) or 9))
    local floor = floorBlock(S, S.newMap.tileset)
    local blocks = nil
    if floor then
      blocks = {}
      for i = 1, wB * hB do blocks[i] = floor end
    end
    local id, err = createMap(S, {
      name = (S.newMap.name ~= "" and S.newMap.name) or "New map",
      width = wB,
      height = hB,
      tileset = S.newMap.tileset,
      blocks = blocks,
    })
    if id then
      S.mapId = id
      S.warpSelected = nil
      S.newMapOpen = false
      S.warpNotice = "created " .. id .. " - it is now the selected map"
    else
      S.warpNotice = tostring(err)
    end
  end
  if Kit.button(x + pad + halfW + 8 * s, fy, halfW, btnH, "CANCEL") then
    S.newMapOpen = false
  end

  local d = def(S)
  if d and d.editorCreated then
    -- Under CREATE/CANCEL rather than at the foot of the page, for the same
    -- reason every other action row in these tools moved: the foot of a page
    -- taller than the drawer is below the bottom of the screen.
    local dy = fy + btnH + 12 * s
    if Kit.button(x + pad, dy, inner, btnH, "DELETE THIS MAP") then
      local gone = S.mapId
      MapEdits.deleteMap(store(S), game(S), gone)
      S.data.maps[gone] = nil
      S.warpMapIds = nil
      S.mapId = nil
      S.warpSelected = nil
      markDirty(S)
      S.warpNotice = gone .. " deleted"
    end
  end
end

function Warps.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad, gap = 16 * s, 20 * s
  local sideW = math.max(260 * s, math.min(340 * s, w * 0.34))
  local listX, listW = x, w - sideW - gap
  local sideX = x + listW + gap

  if S.newMapOpen then
    Kit.card(sideX, y, sideW, h)
    drawNewMap(S, Kit, sideX, y, sideW, h)
  end

  if not S.mapId then
    Kit.card(listX, y, listW, h)
    Kit.emptyBox(listX + pad, y + pad, listW - 2 * pad, h - 2 * pad,
                 "Pick a map on the MAPS tab, or create one here.")
    if not S.newMapOpen then
      Kit.card(sideX, y, sideW, h)
      if Kit.button(sideX + pad, y + pad, sideW - 2 * pad, 34 * s, "NEW MAP...") then
        S.newMapOpen = true
      end
    end
    -- nothing to scroll to: the page shrinks back rather than keeping the
    -- height the last map's list measured
    local okSB, Sidebar = pcall(require, "tools.map-editor.Sidebar")
    if okSB and type(Sidebar) == "table" and Sidebar.reportHeight then
      Sidebar.reportHeight(S, 0)
    end
    return
  end

  local d = def(S)
  local warps = warpsOf(S)

  -- ---------------------------------------------------------------- list
  Kit.card(listX, y, listW, h)
  Kit.caption(listX + pad, y + pad,
    string.format("WARPS - %s (%d)", tostring(S.mapId), #warps))
  local top = y + pad + Kit.textHeight("caption") + 10 * s
  local rowH = 30 * s
  local footH = 34 * s
  local listBottom = y + h - pad - footH - 8 * s
  local perPage = math.max(1, math.floor((listBottom - top) / rowH))
  S.warpScroll = math.max(0, math.min(S.warpScroll or 0,
                                      math.max(0, #warps - perPage)))

  if #warps == 0 then
    Kit.text("body", "This map has no warps. Add one, put it on a door", listX + pad, top)
    Kit.text("body", "cell, and point it at another map.", listX + pad, top + 18 * s)
  end

  local shown = math.max(0, math.min(perPage, #warps - S.warpScroll))
  for r = 1, shown do
    local i = r + S.warpScroll
    local warp = warps[i]
    local ry = top + (r - 1) * rowH
    local rw = listW - 2 * pad
    if Kit.press(listX + pad, ry, rw, rowH - 4 * s) then S.warpSelected = i end
    Kit.row(listX + pad, ry, rw, rowH - 4 * s, S.warpSelected == i)
    -- the label gets what is left after the problem/added tag on the right
    local labelW = rw - 16 * s - 62 * s
    local hovered = Kit.hit
      and Kit.hit(listX + pad, ry, rw, rowH - 4 * s) or false
    marquee(Kit, "body", warpLabel(S, i, warp), listX + pad + 8 * s,
            ry + 6 * s, labelW, nil, "warp" .. i, hovered)
    local why = problemWith(S, d, warp, i)
    if why then
      Kit.textRight("small", why, listX + pad + rw - 8 * s, ry + 8 * s)
    elseif warp.added then
      Kit.textRight("small", "added", listX + pad + rw - 8 * s, ry + 8 * s)
    end
  end

  -- ------------------------------------------------- add, under the list
  --
  -- FLOWED UNDER THE LAST WARP, not pinned to the foot of the page.
  --
  -- + WARP has been here all along; what was missing was any way to SEE it.
  -- Pinned was right when this was a full tab, where the foot of the page and
  -- the bottom of the window were the same line.  In the drawer the panel is
  -- handed a page taller than the drawer, so the foot is somewhere below the
  -- bottom of the screen, and the whole row -- + WARP, NEW MAP..., SAVE --
  -- went with it.  On a map with two warps the list plainly ended and there
  -- was nothing under it, so there was no way to add a door at all.
  --
  -- Two rows of clearance when the list is empty, because the empty state is
  -- two lines of text telling you to add one.
  local fy = top + math.max(shown, 2) * rowH + 10 * s
  local third = (listW - 2 * pad - 16 * s) / 3
  if Kit.button(listX + pad, fy, third, footH, "+ WARP") then
    local cx, cy, onDoor = freeCell(S, d)
    -- No destination on purpose. A new warp defaulting to THIS map would be a
    -- door that loops back on itself and passes every check; leaving it unset
    -- makes the list say "no destination" until it is pointed somewhere.
    addWarp(S, { x = cx, y = cy, destWarp = 1 })
    S.warpNotice = onDoor
      and string.format("warp added on the door at %d,%d - now give it a destination", cx, cy)
      or string.format("warp added at %d,%d - set its destination, then MAKE DOOR",
                       cx, cy)
  end
  if Kit.button(listX + pad + third + 8 * s, fy, third, footH, "NEW MAP...") then
    S.newMapOpen = not S.newMapOpen
  end
  if Kit.button(listX + pad + 2 * (third + 8 * s), fy, third, footH, "SAVE") then
    local ok, err = MapEdits.save(store(S))
    S.mapEditsDirty = not ok or nil
    S.warpNotice = ok and "saved" or ("save failed: " .. tostring(err))
  end
  local listFlowH = (fy + footH + 20 * s) - y

  -- WHERE THE LIST IS, for the wheel.  See Warps.wheelmoved: a notch over the
  -- list scrolls the list, and a notch over the EDITOR has to fall through to
  -- the drawer, or the editor column can never be scrolled at all.  The rows
  -- AS DRAWN, down to the footer -- measured against the page-tall card, a
  -- notch aimed at empty space below a two-warp list still counted as "over
  -- the list" and the drawer stayed stuck.
  S._warpListRect = { listX, top, listW, (fy + footH) - top }

  local function report(used)
    local okSB, Sidebar = pcall(require, "tools.map-editor.Sidebar")
    if okSB and type(Sidebar) == "table" and Sidebar.reportHeight then
      -- THE TALLER OF THE TWO COLUMNS: a forty-warp list beside a selected
      -- warp with six fields is the list.
      Sidebar.reportHeight(S, math.max(listFlowH, used or 0))
    end
  end

  if S.newMapOpen then report(0) return end

  -- ------------------------------------------------------------ the warp
  Kit.card(sideX, y, sideW, h)
  local i = S.warpSelected or 0
  local warp = warps[i]
  if not warp then
    Kit.emptyBox(sideX + pad, y + pad, sideW - 2 * pad, h - 2 * pad,
                 "Select a warp.")
    if S.warpNotice then
      Kit.text("small", S.warpNotice, sideX + pad, y + h - pad - 16 * s)
    end
    -- the list is all there is to see, so it is the whole measurement
    report(0)
    return
  end

  local inner = sideW - 2 * pad
  local fieldH = 30 * s
  local ey = y + pad
  Kit.caption(sideX + pad, ey, "WARP " .. tostring(i))
  ey = ey + Kit.textHeight("caption") + 10 * s

  local maxX = (d and d.width or 1) * 2 - 1
  local maxY = (d and d.height or 1) * 2 - 1
  local function coord(label, key, maxV)
    Kit.text("body", label, sideX + pad, ey + 7 * s)
    if Kit.stepper(sideX + pad + 56 * s, ey, 28 * s, fieldH, "-") then
      writeField(S, warp, i, key, math.max(0, (warp[key] or 0) - 1))
    end
    Kit.textCenter("body", tostring(warp[key] or 0), sideX + pad + 84 * s,
                   ey + 7 * s, 48 * s)
    if Kit.stepper(sideX + pad + 132 * s, ey, 28 * s, fieldH, "+") then
      writeField(S, warp, i, key, math.min(maxV, (warp[key] or 0) + 1))
    end
    Kit.text("small", string.format("of %d", maxV), sideX + pad + 168 * s, ey + 8 * s)
    ey = ey + fieldH + 6 * s
  end
  coord("X", "x", maxX)
  coord("Y", "y", maxY)

  -- The class actually under the warp, named. "$3C" is the whole diagnosis:
  -- it is not in the entrance range, so the engine will not fire this warp.
  local fires, what = cellEntrance(S, d, warp.x or 0, warp.y or 0)
  if fires == nil then
    Kit.text("small", "tileset has no block or collision data - cannot check",
             sideX + pad, ey)
  elseif fires then
    Kit.text("small", string.format("cell is %s - a door, this warp fires", what),
             sideX + pad, ey)
  else
    Kit.text("small", string.format("cell is %s - NOT a door, this warp is inert", what),
             sideX + pad, ey)
  end
  ey = ey + 20 * s

  -- destination map, searchable: a Gen 2 import has hundreds of map ids and a
  -- cycle button through them is not a chooser, it is a punishment.
  Kit.text("body", "TO", sideX + pad, ey + 7 * s)
  if Kit.button(sideX + pad + 34 * s, ey, inner - 34 * s, fieldH,
                tostring(warp.destMap or "-- none --")) then
    S.warpMapOpen = not S.warpMapOpen
    S.warpMapQuery = ""
  end
  ey = ey + fieldH + 6 * s
  if S.warpMapOpen then
    S.warpMapQuery = Kit.textfield("wp-map", sideX + pad, ey, inner, fieldH,
                                   S.warpMapQuery or "", "search maps...")
    ey = ey + fieldH + 4 * s
    -- LAST_MAP and LAST_WARP are not maps; they are how an interior says
    -- "back where they came from" and are the correct destination for most
    -- building exits, so they are offered alongside the real ids.
    local shown = 0
    local function offer(id)
      shown = shown + 1
      if shown <= 6 then
        if Kit.button(sideX + pad, ey, inner, fieldH - 4 * s, id) then
          writeField(S, warp, i, "destMap", id)
          S.warpMapOpen = false
        end
        ey = ey + fieldH - 2 * s
      end
    end
    local q = (S.warpMapQuery or ""):lower()
    for _, id in ipairs({ "LAST_MAP", "LAST_WARP" }) do
      if q == "" or id:lower():find(q, 1, true) then offer(id) end
    end
    for _, id in ipairs(mapIds(S)) do
      if q == "" or id:lower():find(q, 1, true) then offer(id) end
    end
    if shown == 0 then
      Kit.text("small", "no map matches", sideX + pad, ey)
      ey = ey + 16 * s
    elseif shown > 6 then
      Kit.text("small", string.format("%d more - keep typing", shown - 6),
               sideX + pad, ey)
      ey = ey + 16 * s
    end
  end

  Kit.text("body", "WARP #", sideX + pad, ey + 7 * s)
  if Kit.stepper(sideX + pad + 56 * s, ey, 28 * s, fieldH, "-") then
    writeField(S, warp, i, "destWarp", math.max(1, (warp.destWarp or 1) - 1))
  end
  Kit.textCenter("body", tostring(warp.destWarp or 1), sideX + pad + 84 * s,
                 ey + 7 * s, 48 * s)
  if Kit.stepper(sideX + pad + 132 * s, ey, 28 * s, fieldH, "+") then
    writeField(S, warp, i, "destWarp", (warp.destWarp or 1) + 1)
  end
  ey = ey + fieldH + 6 * s

  -- Where that lands, spelled out. A warp id is an index into a list on
  -- another map, which is impossible to check by eye and trivial to check here.
  local dd = def(S, warp.destMap)
  if dd then
    local target = dd.warps and dd.warps[warp.destWarp or 1]
    if target then
      Kit.text("small", string.format("lands at %d,%d on %s",
        target.x or -1, target.y or -1, tostring(warp.destMap)), sideX + pad, ey)
    else
      Kit.text("small", string.format("%s has %d warps - #%d does not exist",
        tostring(warp.destMap), #(dd.warps or {}), warp.destWarp or 1),
        sideX + pad, ey)
    end
  elseif warp.destMap == "LAST_MAP" or warp.destMap == "LAST_WARP" then
    Kit.text("small", "returns to the map the player came from", sideX + pad, ey)
  end
  ey = ey + 22 * s

  local btnH = 32 * s
  local halfW = (inner - 8 * s) / 2
  if Kit.button(sideX + pad, ey, halfW, btnH, "MAKE DOOR") then
    local _ok, msg = makeDoor(S, warp)
    S.warpNotice = msg
  end
  if Kit.button(sideX + pad + halfW + 8 * s, ey, halfW, btnH, "LINK BACK") then
    local _ok, msg = linkBack(S, i, warp)
    S.warpNotice = msg
  end
  ey = ey + btnH + 8 * s

  if Kit.button(sideX + pad, ey, halfW, btnH,
                warp.added and "DELETE" or "BLANK") then
    deleteWarp(S, i)
  end
  if not warp.added then
    if Kit.button(sideX + pad + halfW + 8 * s, ey, halfW, btnH, "REVERT") then
      MapEdits.setWarp(store(S), game(S), S.mapId, i, nil)
      MapEdits.removeWarp(store(S), game(S), S.mapId, i, false)
      markDirty(S)
      S.warpNotice = "reverted on next reload"
    end
  end

  local note = S.warpNotice or (S.mapEditsDirty and "unsaved changes" or nil)
  if note then Kit.text("small", note, sideX + pad, y + h - pad - 16 * s) end

  -- HOW TALL THIS DREW, so the drawer sizes its page to fit rather than to a
  -- constant.  From the FLOWED bottom: this column's buttons already flow, so
  -- `ey` is the honest end of it.
  report((ey + btnH + 30 * s) - y)
end

-- TRUE when this panel took the notch, FALSE when it did not.
--
-- It used to scroll the warp LIST wherever the pointer was, and Sidebar offers
-- the open panel the wheel first -- so with this tool open the drawer could
-- not scroll, and the editor column on the right, which runs to MAKE DOOR,
-- LINK BACK, DELETE and REVERT, had no way to be scrolled either.  The list
-- keeps the wheel over the list.
function Warps.wheelmoved(S, dy)
  -- THE CARTRIDGE LIST FIRST, wherever the pointer is: it is what is being
  -- looked at while it is open, and it is the one list here with two hundred
  -- and fifty rows in it.
  if S.romImport and S._romListRect then
    S.romScroll = math.max(0, (S.romScroll or 0) - (dy or 0))
    return true
  end
  local r = S._warpListRect
  if r then
    local okK, Kit = pcall(require, "Kit")
    if okK and type(Kit) == "table" and Kit.mouseX then
      if not (Kit.mouseX >= r[1] and Kit.mouseX <= r[1] + r[3]
              and Kit.mouseY >= r[2] and Kit.mouseY <= r[2] + r[4]) then
        return false
      end
    end
  end
  S.warpScroll = math.max(0, (S.warpScroll or 0) - (dy or 0))
  return true
end

function Warps.keypressed(S, key)
  if key == "delete" and S.warpSelected then deleteWarp(S, S.warpSelected) end
end

return Warps
