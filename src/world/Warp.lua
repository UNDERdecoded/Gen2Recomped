-- Warp resolution.  A warp fires when:
--   * the player finishes a step onto a warp cell whose collision tile is a
--     door tile or warp tile (stairs, doors, mats, cave entrances), or
--   * the player stands on a warp cell and tries to walk off the map edge
--     (exit carpets at the bottom of interiors), or
--   * the player stands on a warp cell and the "extra" check passes -- on
--     arrival with the d-pad held, or on a blocked step (route-gate
--     doorways, the Vermilion dock entrance, ...).
-- This mirrors pokered's CheckWarpsNoCollision / CheckWarpsCollision /
-- ExtraWarpCheck (home/overworld.asm).

local Runtime = require("src.mods.Runtime")

local Warp = {}

-- Returns the warp entry to take when arriving at (cx,cy), or nil.
--
-- This is CheckWarpTile (home/map.asm) whole, and the second half is the part
-- that used to be missing here:
--
--     CheckWarpTile::
--         call GetDestinationWarpNumber   ; is there a warp on this cell?
--         ret nc
--         push bc
--         farcall CheckDirectionalWarp    ; ...and may it fire from a STEP?
--         pop bc
--         ret nc
--         call CopyWarpData
--         scf
--         ret
--
-- CheckDirectionalWarp (engine/overworld/tile_events.asm) is four comparisons
-- and a cleared carry:
--
--     ; If directional warp, clear carry (requires button press to activate).
--     ; Otherwise, set carry (warps immediately).
--         cp COLL_WARP_CARPET_DOWN / cp COLL_WARP_CARPET_LEFT
--         cp COLL_WARP_CARPET_UP   / cp COLL_WARP_CARPET_RIGHT
--
-- So a DOOR, staircase, cave or warp panel takes you the instant you step on
-- it, and a CARPET never does: it waits until you walk on in the carpet's own
-- direction, already facing that way (DoPlayerMovement .CheckWarp, which the
-- overworld's checkGen2CarpetExit implements).
--
-- Without it, a mat is a trapdoor. Every doormat in the game is at least two
-- cells wide, and the arrival cell is only inert until you leave it -- so
-- taking one step ALONG the mat, from one carpet cell to its neighbour,
-- landed on a live warp and fired it. That is the reported "walk down and it
-- warps you without you ever walking into the building", and it is every
-- Center, Mart, gym and house in both regions.
--
-- The test belongs HERE, next to the warp lookup it qualifies, rather than at
-- the call sites: the step handler was already filtering carpets out of the
-- copy it uses to outrank coord events, and the copy it actually warps on --
-- a second Warp.onArrive a hundred lines further down -- was not.
function Warp.onArrive(map, cx, cy, dir)
  local w = map:warpAtCell(cx, cy)
  if not (w and map:isWarpTileCell(cx, cy)) then return nil end
  -- ...AND THE BEHAVIOUR HAS TO BE ONE THAT OPENS, which on this cartridge
  -- is a separate question from whether a warp event is here.
  --
  -- Reported from play, about the TRICK HOUSE: "hitting a on it is supposed
  -- to unlock the door, the door is just unlocked at the moment."  The
  -- entrance's way in is a warp event on ORDINARY FLOOR, and this port took
  -- it the moment the player stood on the tile -- so the scroll, the Trick
  -- Master and the whole of finding him were optional.
  --
  -- IsWarpMetatileBehavior is the test TryStartWarpEventScript makes first,
  -- and ordinary ground fails it: a warp event sitting there is a SCRIPT'S
  -- DESTINATION and nothing else.  About a tenth of Hoenn's warp events are
  -- that shape.  Which behaviours pass is derived at import rather than named
  -- here (Map:isStepWarpCell, RomExtractorGen3:warpBehaviours), and every
  -- older dataset answers true, so nothing before Gen 3 changes.
  --
  -- The arrow rule below is the OTHER half of the same law -- the arrow
  -- behaviours are deliberately left out of IsWarpMetatileBehavior -- and it
  -- is kept separate because it is directional and this one is not.
  if map.isStepWarpCell and not map:isStepWarpCell(cx, cy) then return nil end
  -- GEN 4 TAKES A WARP FROM A STEP ONLY WHERE THE CARTRIDGE DOES.
  --
  -- `Field_CheckTransition` (pokeplatinum src/overlay005/field_control.c) is
  -- the arrival path, and it opens a warp event for exactly five behaviours:
  -- the two escalators, WARP_ENTRANCE_NORTH, WARP_NORTH and WARP_PANEL -- see
  -- `Map:gen4ArrivalWarpAt`. Everything else is reached by a PRESS into the
  -- wall ahead (`OverworldState:checkGen4EntranceWarp`) or not at all.
  --
  -- Reported from play inside Mt. Coronet: the exit off Route 208 is (27,20),
  -- WARP_EAST, and stepping onto it from the tile above or below threw the
  -- player out. In the cartridge that step just lands on the exit; the press
  -- right that follows is what leaves.
  --
  -- A whitelist rather than a list of refusals, because the refusals were how
  -- this went wrong: they named the entrance mats and the door, and every
  -- other directional warp fell through to "fire".
  if map.gen4ArrivalWarpAt then
    local arrival = map:gen4ArrivalWarpAt(cx, cy)
    if arrival ~= nil then return arrival and w or nil end
  end
  local Map = require("src.world.Map")
  local GameVersion = require("src.core.GameVersion")
  -- GEN 3'S CARPET IS AN ARROW, and it is the paragraph above one cartridge
  -- later.  Reported from play: "when i walk through a door into the pokemon
  -- center or any area really indoors, when i walk left or right onto the
  -- warp tiles it warps me back outside, it should only do this if walk back
  -- out facing the exit".  ANY POKEMON CENTER'S TWO-CELL EXIT MAT is the
  -- situation -- (8,8) and (9,8) on MAP_G01_N00, both MB_SOUTH_ARROW_WARP,
  -- both carrying the warp back to the town -- and so is the truck the game
  -- opens inside, whose three stacked MB_EAST_ARROW_WARP cells threw the
  -- player out on the first step in any direction.
  --
  -- TryArrowWarp (field_control_avatar.c) is where the cartridge keeps this,
  -- and the arrow behaviours are deliberately left OUT of
  -- IsWarpMetatileBehavior so that TryStartWarpEventScript -- the completed
  -- step, which is this function -- never fires one.  So the comparison
  -- below is the whole of it.  Ladders, escalators, the non-animated door
  -- and staircase, Lavaridge's holes, the Aqua Hideout's and Mossdeep's pads
  -- are all in that list and all still fire from a step taken any which way,
  -- because in the game they do.
  --
  -- Written as `arrow ~= dir` rather than a flat refusal for two reasons: it
  -- says what the rule IS, and on a mod's map where the cell in the arrow's
  -- own direction is walkable -- which no cell in Hoenn is (derived, all 535
  -- of them) -- the step through the arrow is the one that should still work.
  -- A caller that passes no direction gets the refusal, which is the safe way
  -- round: the exit is still there on the input side (see
  -- OverworldState:checkGen3ArrowWarp), and a warp that will not fire is a
  -- door you walk through twice, where one that fires unasked is the bug.
  if map.arrowWarpDirAt then
    local arrow = map:arrowWarpDirAt(cx, cy)
    if arrow and arrow ~= dir then return nil end
  end
  -- Only where the cell answers in collision CLASSES. On a tile-id map those
  -- four numbers mean nothing, and reading them as carpets would silently
  -- disable real doors -- see Map:speaksGen2Collision.
  if GameVersion.isGen2() and map.speaksGen2Collision and map:speaksGen2Collision()
     and Map.gen2IsDirectionalCarpet(map:cellTile(cx, cy)) then
    return nil
  end
  return w
end

local function inList(list, v)
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

-- ExtraWarpCheck: may the player standing at (cx,cy) facing dir warp
-- without a door/warp tile underfoot?  On the carpet maps/tilesets the
-- tile in FRONT of the player must be a warp-carpet tile for the facing
-- direction (IsWarpTileInFrontOfPlayer; SS_ANNE_BOW tests one hardcoded
-- tile instead); everywhere else the player must face the map edge
-- (IsPlayerFacingEdgeOfMap).  carpets = field.warpCarpets.
function Warp.extraCheck(map, carpets, cx, cy, dir)
  -- FIRERED'S DIRECTIONAL WARPS, which this is the whole trigger for.
  --
  -- TryArrowWarp takes the arrow panels, the interior exit mats and the side
  -- staircases, and it takes them only when the player is walking in the
  -- behaviour's own direction -- never on arrival, which is what
  -- Map:isWarpTileCell now refuses for exactly these cells.  Whether the step
  -- is blocked by the building's wall or would have left the map makes no
  -- difference on the cartridge, so neither is asked about here.
  if map.frlgWarpDirection and map:frlgWarpDirection(cx, cy) == dir
     and map:warpAtCell(cx, cy) then
    return true
  end
  -- FireRed has no pokered-style "face the map edge" fallback here.  Its
  -- non-arrival input warp is TryArrowWarp above; ordinary completed-step
  -- warps are filtered by Map:isWarpTileCell, and a north press into a WARP_DOOR
  -- reaches that door through the normal movement/door path.  Falling through
  -- to ExtraWarpCheck made plain-floor script destinations live whenever they
  -- happened to sit at a map edge.
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.get() == "firered" then return false end
  local Collision = require("src.world.Collision")
  local facingEdge =
    (dir == "up" and cy == 0)
    or (dir == "down" and cy == map.heightCells - 1)
    or (dir == "left" and cx == 0)
    or (dir == "right" and cx == map.widthCells - 1)
  if not carpets then return facingEdge end
  -- the map exceptions are tested before the tileset (ExtraWarpCheck)
  local useCarpet
  if inList(carpets.edgeMaps, map.id) then
    useCarpet = false
  elseif inList(carpets.function2Maps, map.id) then
    useCarpet = true
  else
    useCarpet = inList(carpets.function2Tilesets, map.def.tileset)
  end
  if not useCarpet then return facingEdge end
  local tx, ty = Collision.target(cx, cy, dir)
  local front = map:cellTile(tx, ty)
  if map.id == carpets.ssAnneBow.map then
    return front == carpets.ssAnneBow.tile
  end
  return inList(carpets.tiles[dir], front)
end

-- Returns the warp entry when standing on (cx,cy) and the extra check
-- passes toward dir (fired from a blocked step, or on arrival with the
-- d-pad held).
function Warp.onCollision(map, carpets, cx, cy, dir)
  local w = map:warpAtCell(cx, cy)
  if w and Warp.extraCheck(map, carpets, cx, cy, dir) then
    return w
  end
  return nil
end

-- Returns the warp entry when standing on (cx,cy) and moving toward dir
-- takes the player out of bounds.
function Warp.onEdge(map, cx, cy, dir)
  local w = map:warpAtCell(cx, cy)
  if not w then return nil end
  local Collision = require("src.world.Collision")
  local tx, ty = Collision.target(cx, cy, dir)
  if not map:inBounds(tx, ty) then
    return w
  end
  return nil
end

-- Resolve a warp's destination to map id + cell.  LAST_MAP destinations
-- (returning from an interior) resolve against the remembered outdoor
-- map; the landing cell is that map's warp entry named by the warp id
-- (wDestinationWarpID placement -- two-sided route gates land you on
-- the side you exit, not where you entered).
-- GEN 3'S DYNAMIC WARP.  Map group 127, map 127 is not a map: it is the
-- placeholder Emerald uses for "wherever setdynamicwarp last pointed", and a
-- door naming it resolves through the save at the moment it is taken.
--
-- The truck a new game starts inside is built out of exactly that pair -- the
-- coord event under the player sets the destination (Littleroot Town, at a
-- different doorstep depending on the boy-or-girl answer) and all three of the
-- truck's warps name the placeholder.  Unresolved, the first door in the game
-- leads to an id no dataset has, which is the REDS_HOUSE_2F crash again one
-- room later.
local GEN3_DYNAMIC_MAP = "MAP_G127_N127"

-- GEN 4 HAS THE SAME SEAM AND THE PORT READ IT AS A HOLE.  A warp event whose
-- destination header is 0xfff and whose anchor is 0x100 does not go nowhere:
-- field_control.c 1011 resolves it from the SPECIAL LOCATION, exactly as Gen 3
-- resolves map group 127.  Six warps in Sinnoh carry that pair and all six are
-- LIFT CARS -- Jubilife TV, both Hearthome houses, the Veilstone department
-- store, the Resort Area and the Vista Lighthouse -- so with the pair unread
-- and `setspeciallocation` lowered to a noop, every lift in the region opened
-- onto nothing.  The extractor now marks them with this id; see
-- src/import/Gen4Elevators.lua.
local GEN4_DYNAMIC_MAP = "GEN4_SPECIAL_LOCATION"

-- WARP_ID_NONE is -1 (include/location.h) in a u16 operand: the slot's warp is
-- not a warp and its coordinates are.  Gen 3 spells the same rule 0xFF because
-- there the operand is a byte.
local GEN4_WARP_NONE = 0xFFFF

local function resolve(data, warpDef, lastMap, backupWarp, save)
  local destMap = warpDef.destMap

  -- TURNBACK CAVE REPOINTS ITS OWN EXITS, every time a room loads.
  --
  -- `ScrCmd_InitTurnbackCave` rewrites the loaded room's warp events so that
  -- every exit except the one you came in by leads to a freshly chosen room;
  -- that is the whole maze, and without it every room's four warps lead back to
  -- the entrance as shipped and Giratina cannot be reached.
  --
  -- READ HERE RATHER THAN WRITTEN INTO THE DEF. `MapLoader` caches one def per
  -- map and hands the same table to the renderer, the editor and the next
  -- visit, so a destination written into it would outlive the visit that chose
  -- it. Same reason `gen4SpecialLocation` above is consulted rather than baked.
  --
  -- MATCHED BY TABLE IDENTITY, which is what makes this safe without changing
  -- every caller's signature to pass the source map: `warpDef` came out of some
  -- def's `warps` list, and it is this room's warp N only if that def's slot N
  -- IS this table. A warp of the same index on another map is a different
  -- table and does not match.
  local turnback = save and save.gen4Turnback
  if turnback and turnback.dest and turnback.map then
    local src = data and data.maps and data.maps[turnback.map]
    local index = tonumber(warpDef.index)
    if src and src.warps and index and src.warps[index] == warpDef
       and index ~= turnback.keep then
      destMap = turnback.dest
    end
  end
  if destMap == GEN4_DYNAMIC_MAP then
    local spot = save and save.gen4SpecialLocation
    if spot and spot.map and data.maps[spot.map] then
      local destDef = data.maps[spot.map]
      -- the warp id places you and the coordinates are then overwritten from
      -- it (field_map_change.c 226); the Veilstone store's middle floors name
      -- warp 2 where its top and basement name warp 1, so this is not cosmetic
      local id = tonumber(spot.warp)
      local dw = id and id ~= GEN4_WARP_NONE and destDef.warps
                 and destDef.warps[id + 1]
      if dw then return spot.map, dw.x, dw.y end
      if spot.x and spot.y then return spot.map, spot.x, spot.y end
    end
    -- Same refusal as Gen 3 below, and for the same reason: handing MapLoader
    -- an id no dataset has raises under the player's feet, where standing
    -- still leaves them in the car with the reason in the log.
    require("src.core.Logger").warn(
      "gen4 dynamic warp taken with no special location set -- the lift's "
      .. "`setspeciallocation` has not run")
    return nil
  end
  if destMap == GEN3_DYNAMIC_MAP then
    local dyn = save and save.gen3DynamicWarp
    if dyn and dyn.map and data.maps[dyn.map] then
      local destDef = data.maps[dyn.map]
      -- a warp id of $FF means "use the coordinates"; anything else names a
      -- warp on the destination and the coordinates are ignored
      local id = tonumber(dyn.warp)
      local dw = id and id ~= 0xFF and destDef.warps and destDef.warps[id + 1]
      if dw then return dyn.map, dw.x, dw.y end
      if dyn.x and dyn.y then return dyn.map, dyn.x, dyn.y end
    end
    -- NOTHING SET, so there is nowhere to go.  Returning a placeholder id
    -- here would hand MapLoader a map no dataset has, which is a hard error
    -- on a door the player is standing on; refusing the warp leaves them
    -- where they are, with the reason in the log.
    require("src.core.Logger").warn(
      "gen3 dynamic warp taken with nothing set -- the script that should "
      .. "have set it has not run")
    return nil
  end
  -- Gen2 warp id $FF: land back on the warp tile we last stepped through,
  -- whatever map that was (EnterMapWarp's wBackupWarp).
  if destMap == "LAST_WARP" then
    if backupWarp and data.maps[backupWarp.id] then
      return backupWarp.id, backupWarp.x, backupWarp.y
    end
    destMap = "LAST_MAP"
  end
  if destMap == "LAST_MAP" then
    assert(lastMap, "LAST_MAP warp with no remembered outdoor map")
    destMap = lastMap.id
    local destDef = data.maps[destMap]
    local dw = destDef and destDef.warps[warpDef.destWarp]
    if dw then
      return destMap, dw.x, dw.y
    end
    -- out-of-range data: fall back to where the player entered
    return destMap, lastMap.x, lastMap.y
  end
  local destDef = data.maps[destMap]
  if not destDef then
    -- Gen2 alias not yet resolved: warn and stay at current position
    require("src.core.Logger").warn("warp to unknown map %s (alias not resolved)", tostring(destMap))
    local fallback = (lastMap and lastMap.id) or destMap
    local fb = data.maps[fallback]
    return fallback, (fb and fb.warps and fb.warps[1] and fb.warps[1].x) or 3,
                    (fb and fb.warps and fb.warps[1] and fb.warps[1].y) or 3
  end
  local dw = destDef.warps[warpDef.destWarp]
  if not dw then
    -- AN OUT-OF-RANGE WARP ID IS REAL DATA, not corruption.  Prism's
    -- Battle Tower is the case: BattleTowerHallway's first warp names
    -- warp 3 of BATTLE_TOWER_ELEVATOR and the elevator has two, because
    -- that door is script-driven -- the elevator's own trigger warps you
    -- on, so the id in the table is never meant to be honoured.
    --
    -- Landing at the map's geometric CENTRE, which is what this did,
    -- puts the player wherever that happens to be -- and in a 2x2-block
    -- elevator that is not a tile you can walk off, which is being
    -- locked in the tower.  Prefer the destination's own way BACK: the
    -- warp that returns to the map being left, then its first warp,
    -- and only then the centre.  All three are walkable by
    -- construction -- a warp tile is somewhere the player stands.
    local from = warpDef.sourceMap or (lastMap and lastMap.id)
    local back
    if from then
      for _, w in ipairs(destDef.warps or {}) do
        if w.destMap == from then back = w break end
      end
    end
    back = back or (destDef.warps and destDef.warps[1])
    if back then return destMap, back.x, back.y end
    return destMap, destDef.width * 2 / 2, destDef.height * 2 / 2
  end
  return destMap, dw.x, dw.y
end

-- the resolved destination passes through warp.destination, so a mod can
-- reroute one door without owning the warp table (ctx carries the warp
-- record and the remembered outdoor side the resolution used)
local function warped(mapId, x, y) return mapId, x, y end

-- THE LIFT REMEMBERS THE FLOOR YOU GOT ON AT, and it is the same slot.
--
--     if (warpEvent->destWarpID == 0x100) {
--         *specialLocation = *entranceLocation;
--     }
--
-- -- field_map_change.c 232, run on ARRIVAL: stepping into a car overwrites
-- the slot with the door you just left.  That is the whole of how the
-- two-floor lifts work, because Hearthome's cars and the Vista Lighthouse's
-- have no panel at all -- they ask `getfloorsabove` about the special location
-- and warp you to the other floor.  It is also what makes walking straight
-- back out of any car return you to the floor you came from instead of
-- wherever the last lift in the game was sent.
--
-- Called from the warp the player is TAKING, with the map being left, because
-- the port resolves a destination rather than loading a header and then asking
-- which warp it arrived at.  The stored warp id is the cartridge's zero-based
-- event index, which is what `resolve` above adds one to.
function Warp.noteGen4Entrance(data, save, warpDef, destMap, fromMap, x, y, facing)
  if not (data and save and warpDef and destMap and fromMap) then return end
  local destDef = data.maps and data.maps[destMap]
  local arrival = destDef and destDef.warps and destDef.warps[warpDef.destWarp]
  if not (arrival and arrival.destMap == GEN4_DYNAMIC_MAP) then return end
  save.gen4SpecialLocation = {
    map = fromMap,
    warp = (tonumber(warpDef.index) or 1) - 1,
    x = x, y = y, facing = facing,
  }
end

function Warp.destination(data, warpDef, lastMap, backupWarp, save)
  local destMap, x, y = resolve(data, warpDef, lastMap, backupWarp, save)
  if destMap == nil then return nil end
  if not Runtime.wantsHook("warp.destination") then return destMap, x, y end
  return Runtime.call("warp.destination", warped, destMap, x, y,
                      { warp = warpDef, lastMap = lastMap, data = data })
end

return Warp
