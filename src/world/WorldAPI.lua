-- mod.world: the supported way for mod code to act on the running
-- overworld.  Every method resolves the live OverworldState by scanning
-- the state stack for the isOverworld marker and returns nil, "no
-- overworld" when none is up -- called from the title screen this is a
-- quiet no-op, never a crash.  Reaching into OverworldState internals
-- stays unsupported; anything a mod legitimately needs belongs here.

local Logger = require("src.core.Logger")
local MapLoader = require("src.world.MapLoader")
local Gen3Elevation = require("src.world.Gen3Elevation")
local Runtime = require("src.mods.Runtime")

local WorldAPI = {}
WorldAPI.__index = WorldAPI

local NO_OVERWORLD = "no overworld"

function WorldAPI.new(game, modId)
  return setmetatable({ game = game, modId = modId }, WorldAPI)
end

-- the live overworld, or nil.  Game.overworld is the fast path; the stack
-- scan is the authority, so a state pushed over the world (a battle, a
-- menu) still resolves to the world underneath it.
function WorldAPI:overworld()
  local game = self.game
  local stack = game and game.stack
  if stack and stack.worldOwner then return stack.worldState end
  local states = stack and stack.states
  if states then
    for i = #states, 1, -1 do
      if states[i].isOverworld then return states[i] end
    end
  end
  local ow = game and game.overworld
  if ow and ow.isOverworld and ow.map then return ow end
  return nil
end

function WorldAPI:current()
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  local p = ow.player
  -- `elevation` is the level the player is STANDING AT, which is not always
  -- the level of the cell under them: 0 and 15 do not replace what is held
  -- (Gen3Elevation.sticky), so a player crossing under a bridge keeps the
  -- ground's level the whole way.  A mod placing a character in 3D wants this
  -- one and not elevationAt(x, y).  nil on a dataset with no elevation.
  local elevation = p and p.elevation
  return { mapId = ow.map.id, x = p and p.cellX, y = p and p.cellY,
           facing = p and p.facing,
           -- ...and where they are BETWEEN cells, in pixels on the map's own
           -- 16px grid.  x/y jump a whole cell at a time, which is fine for a
           -- script and useless for a camera: a mod drawing the field smoothly
           -- needs the same numbers the engine's own camera follows.
           px = p and p.px, py = p and p.py,
           elevation = elevation,
           layer = Gen3Elevation.layerOf(self.game and self.game.data,
                                         elevation) }
end

-- opts.arrive = "fly" | "teleport" picks the arrival FX; anything else
-- lands the player without one, like a scripted warp.
function WorldAPI:warpTo(mapId, x, y, facing, opts)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if not self.game.data.maps[mapId] then
    return nil, "unknown map: " .. tostring(mapId)
  end
  if opts and (opts.arrive == "fly" or opts.arrive == "teleport") then
    ow.arriveWarp = opts.arrive
  end
  ow:startWarpTo(mapId, x, y, facing or "down", opts and opts.onDone,
                 { via = "warp", keepMusic = opts and opts.keepMusic })
  return true
end

-- save.objectToggles is the same store the spawn filter reads, so a toggle
-- on an inactive map takes effect the next time it is entered.
function WorldAPI:toggleObject(mapId, objName, visible)
  local save = self.game and self.game.save
  if not save then return nil, "no save" end
  save.objectToggles = save.objectToggles or {}
  save.objectToggles[mapId] = save.objectToggles[mapId] or {}
  save.objectToggles[mapId][objName] = visible and true or false
  Runtime.emit("world.object_toggled",
    { mapId = mapId, objName = objName, visible = visible and true or false })
  local ow = self:overworld()
  if ow and ow.map and ow.map.id == mapId then
    ow:setMap(mapId, ow.player.cellX, ow.player.cellY, ow.player.facing,
              { seamless = true, via = "reload", keepMusic = true })
  end
  return true
end

function WorldAPI:setFlag(name, value)
  local save = self.game and self.game.save
  if not save or not save.flags then return nil, "no save" end
  save.flags[name] = value
  return true
end

function WorldAPI:getFlag(name)
  local save = self.game and self.game.save
  return save and save.flags and save.flags[name]
end

-- active map only: this mutates the runtime Map and rebuilds the renderer.
-- A layout change that must survive a reload belongs in a maps patch.
function WorldAPI:replaceBlock(bx, by, block)
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  ow:replaceBlock(bx, by, block)
  return true
end

-- objDef uses the same shape as maps[].objects.  Runtime objects are not
-- serialized: a permanent NPC belongs in a maps patch, this is for
-- scripted and dynamic actors the mod re-spawns on map.entered.
function WorldAPI:spawnNpc(mapId, objDef)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if type(objDef) ~= "table" then return nil, "objDef must be a table" end
  local copy = {}
  for k, v in pairs(objDef) do copy[k] = v end
  return ow:addRuntimeObject(mapId, copy, self.modId)
end

function WorldAPI:removeNpc(npcId)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  return ow:removeRuntimeObject(npcId, self.modId)
end

-- THE SHAPE OF THE GROUND, which until now nothing outside the engine could
-- ask about.
--
-- Reported of a mod that draws the field in 3D: "it doesnt recognize height of
-- the terrain or character, which places me underground in some areas where
-- the ground is raised".  It could not recognize either, because neither was
-- on this surface -- `current()` gave x, y and a facing, and there was no way
-- at all to read a cell.  Reaching into ow.map to get at it is exactly the
-- unsupported poking the header warns about, and it is also how a mod ends up
-- reading def.elevationCells with the wrong stride: a Gen 3 block IS one 16px
-- walk cell (blockCells = 1) and a Gen 1/2 block is four, so the same
-- arithmetic is right in one dataset and silently wrong in the other.
--
-- Everything below is in WALK CELLS in the named map's own coordinates, which
-- is the same space current() and Handle:position() report in.

local NO_ELEVATION = "map carries no elevation"

-- The named map, or the active one when mapId is nil.  A LOADED NEIGHBOUR
-- resolves too -- the world keeps the maps across each seam resident so it can
-- draw them (OverworldState:rebuildNeighbors), and a mod meshing the visible
-- field needs the same set -- but a map that is merely in the dataset does
-- not: loading one costs a tileset and an atlas, and a per-frame call is not
-- the place to pay it.  loadedMaps() below says which ids will answer.
function WorldAPI:_mapNamed(mapId)
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  if mapId == nil or mapId == ow.map.id then return ow.map, ow, 0, 0 end
  for _, nb in ipairs(ow.neighbors or {}) do
    if nb.map and nb.map.id == mapId then
      return nb.map, ow, nb.cx or 0, nb.cy or 0
    end
  end
  return nil, "map is not loaded: " .. tostring(mapId)
end

-- every map the world currently holds, with each one's offset from the active
-- map's origin in cells -- the frame a mod needs to place a neighbour's
-- terrain against the one the player is standing on
function WorldAPI:loadedMaps()
  local ow = self:overworld()
  if not ow or not ow.map then return nil, NO_OVERWORLD end
  local out = { { mapId = ow.map.id, x = 0, y = 0, active = true,
                  width = ow.map.widthCells, height = ow.map.heightCells } }
  for _, nb in ipairs(ow.neighbors or {}) do
    if nb.map then
      out[#out + 1] = { mapId = nb.map.id, x = nb.cx or 0, y = nb.cy or 0,
                        active = false, width = nb.map.widthCells,
                        height = nb.map.heightCells }
    end
  end
  return out
end

-- What a caller has to know before it reads a single cell: whether this
-- dataset carries elevation at all (no Gen 1 or Gen 2 map does), how big the
-- grid is, and what the two values that are NOT levels mean.
function WorldAPI:elevationInfo(mapId)
  local map, err = self:_mapNamed(mapId)
  if not map then return nil, err end
  local data = self.game and self.game.data
  return {
    mapId = map.id,
    supported = (map.def and map.def.elevationCells) ~= nil,
    width = map.widthCells,
    height = map.heightCells,
    -- levels run 0..layers-1, bottom first (see Gen3Elevation.layerTable)
    layers = Gen3Elevation.layerCount(data),
    -- "any level": ordinary ground, and it never changes what a mover holds
    wildcard = 0,
    -- "under a bridge": also not a level, and also sticky
    underBridge = 15,
    -- the two levels worth naming: Hoenn's dry land and its water
    ground = 3,
    water = 1,
  }
end

-- elevation, layer.  nil plus a reason off the map, on a map with no
-- elevation, or with no world up -- never an error.
function WorldAPI:elevationAt(x, y, mapId)
  local map, err = self:_mapNamed(mapId)
  if not map then return nil, err end
  if not (map.def and map.def.elevationCells) then return nil, NO_ELEVATION end
  local e = map:cellElevation(x, y)
  if e == nil then return nil, "off the map" end
  return e, Gen3Elevation.layerOf(self.game and self.game.data, e)
end

-- Everything about one cell in a single call, so a mesh builder is not making
-- four crossings per cell.  `layer` is the one to build height from; `raw` is
-- the cartridge's nibble for a caller that wants to reason about it itself.
function WorldAPI:terrainAt(x, y, mapId)
  local map, err = self:_mapNamed(mapId)
  if not map then return nil, err end
  local has = (map.def and map.def.elevationCells) ~= nil
  local e = has and map:cellElevation(x, y) or nil
  if has and e == nil then return nil, "off the map" end
  local function try(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, map, ...)
    if ok then return v end
    return nil
  end
  return {
    mapId = map.id, x = x, y = y,
    raw = e,
    elevation = e,
    layer = Gen3Elevation.layerOf(self.game and self.game.data, e),
    wildcard = e == 0,
    underBridge = e == 15,
    water = try(map.isWaterCell, x, y) and true or false,
    walkable = try(map.isWalkableCell, x, y) and true or false,
    behaviour = try(map.cellBehaviour, x, y),
  }
end

-- HOW HIGH A LEVEL IS ON THIS MAP, in world pixels.
--
-- `layer` (above) ranks a level against the cartridge's draw order, which has
-- three rungs everywhere.  This ranks the levels THIS MAP actually uses and
-- spaces them a metatile apart, which is what a renderer building terrain
-- needs: Route 119 uses three levels and Victory Road six, and three rungs
-- cannot separate six.  Ordinary ground (elevation 3) is the datum and comes
-- out at 0.  See src/world/Gen3Elevation.lua for the derivation.
--
-- Returns { heights = {[elevation] = pixels}, levels = n, course = 16,
--           ground = 3, wildcard = 0, underBridge = 15, water = 1 }.
function WorldAPI:elevationRanks(mapId)
  local map, err = self:_mapNamed(mapId)
  if not map then return nil, err end
  local cells = map.def and map.def.elevationCells
  if not cells then return nil, NO_ELEVATION end
  local heights, levels, course = Gen3Elevation.ranks(cells)
  if not heights then return nil, NO_ELEVATION end
  return { mapId = map.id, heights = heights, levels = levels,
           course = course, ground = 3, wildcard = 0, underBridge = 15,
           water = 1 }
end

-- The height of one cell, in the same world pixels.
--
-- nil, plus a reason, on the two values that are NOT levels: a wildcard (0)
-- takes the height of whatever it joins, and a deck (15) is at a different
-- height for the walker ON it than for the walker UNDER it -- that is the
-- whole mechanism of Fortree's span and Route 110's cycling road.  Guessing
-- either one puts somebody underground, so this declines rather than guesses,
-- and `reason` is "transition cell" or "bridge cell" so a caller can branch.
function WorldAPI:heightAt(x, y, mapId)
  local ranks, err = self:elevationRanks(mapId)
  if not ranks then return nil, err end
  local e = select(1, self:elevationAt(x, y, mapId))
  if e == nil then return nil, "off the map" end
  if e == 0 then return nil, "transition cell" end
  if e == 15 then return nil, "bridge cell" end
  local h = ranks.heights[e]
  if h == nil then return nil, "no level for elevation " .. tostring(e) end
  return h, e
end

-- A RECTANGLE OF CELLS IN ONE CALL, because the per-cell reader is the wrong
-- shape for the job that prompted all of this: a route is 80x80 and a mod
-- rebuilding its terrain every time the map changes should cross into the
-- engine once, not 6,400 times.
--
-- opts = { mapId, x, y, width, height }.  Defaults cover the whole map, and
-- the rectangle is clipped to it, so the returned width/height are what you
-- actually got.  `cells` holds the raw nibbles and `layers` the levels, both
-- row-major from (x, y) and both 1-based: index = (row * width + col) + 1.
function WorldAPI:elevationGrid(opts)
  opts = opts or {}
  local map, err = self:_mapNamed(opts.mapId)
  if not map then return nil, err end
  if not (map.def and map.def.elevationCells) then return nil, NO_ELEVATION end
  local mw, mh = map.widthCells, map.heightCells
  local x0 = math.max(0, math.floor(tonumber(opts.x) or 0))
  local y0 = math.max(0, math.floor(tonumber(opts.y) or 0))
  local w = math.floor(tonumber(opts.width) or (mw - x0))
  local h = math.floor(tonumber(opts.height) or (mh - y0))
  w = math.max(0, math.min(w, mw - x0))
  h = math.max(0, math.min(h, mh - y0))
  local layerOf = Gen3Elevation.layerTable(self.game and self.game.data)
  local cells, layers, n = {}, {}, 0
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      n = n + 1
      local e = map:cellElevation(x, y) or 0
      cells[n] = e
      layers[n] = layerOf[e + 1] or 0
    end
  end
  return { mapId = map.id, x = x0, y = y0, width = w, height = h,
           cells = cells, layers = layers }
end

-- a handle onto a live NPC: scriptMove / marchInPlace / face, which is
-- everything the scripted-movement queue exposes
local Handle = {}
Handle.__index = Handle

function Handle:scriptMove(dir, tiles, onDone)
  self.ow:scriptMove(self.npc, dir, tiles or 1, onDone)
  return true
end

function Handle:marchInPlace(onDone)
  self.ow:marchInPlace(self.npc, onDone)
  return true
end

function Handle:face(dir)
  self.npc.facing = dir
  return true
end

-- x, y, elevation.  The third return is new; a caller that wanted two still
-- gets the same two.
function Handle:position()
  return self.npc.cellX, self.npc.cellY, self:elevation()
end

-- the level this NPC is standing at, kept sticky the same way the player's is
function Handle:elevation()
  local ow = self.ow
  if ow and ow.gen3DrawElevation then
    local ok, e = pcall(ow.gen3DrawElevation, ow, self.npc)
    if ok then return e end
  end
  return self.npc.gen3Elevation
end

function WorldAPI:npc(mapId, indexOrName)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  if ow.map and ow.map.id ~= mapId then return nil, "map is not active" end
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def.index == indexOrName or npc.def.name == indexOrName
       or npc.id == indexOrName then
      return setmetatable({ ow = ow, npc = npc, id = npc.id }, Handle)
    end
  end
  return nil, "no such object: " .. tostring(indexOrName)
end

-- FIFO queueing is owned by the script runner; until it lands this runs
-- the rows when nothing else is running and refuses otherwise, so a mod
-- never silently loses a script.
function WorldAPI:queueScript(rows, extra)
  local ow = self:overworld()
  if not ow or not ow.runner then return nil, NO_OVERWORLD end
  if ow.runner:isRunning() then return nil, "a script is already running" end
  ow.runner:run(rows, extra)
  return true
end

-- drop a map's cached instance so the next load re-reads its record; when
-- it is the active map the world reloads around the player in place
function WorldAPI:invalidateMap(mapId)
  local ow = self:overworld()
  if not ow then
    local had = MapLoader.invalidate(mapId)
    Runtime.emit("map.reloaded", { mapId = mapId, reason = "invalidate" })
    return had
  end
  local ok, err = pcall(ow.reloadMap, ow, mapId, "invalidate")
  if not ok then
    Logger.warn("[%s] invalidateMap %s failed: %s", tostring(self.modId),
                tostring(mapId), tostring(err))
    return nil, tostring(err)
  end
  return true
end

return WorldAPI
