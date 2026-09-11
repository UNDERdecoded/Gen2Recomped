-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The overworld state: renders the current map (plus connected map
-- strips), runs the player, NPCs, warps, connections, encounters, ledges,
-- surfing, Cut trees, trainer sight lines, and dispatches interactions to
-- map scripts (data/scripts/), marts, nurses or extracted text.

local Assets = require("src.render.Assets")
local Camera = require("src.render.Camera")
local Collision = require("src.world.Collision")
local Encounter = require("src.world.Encounter")
local FieldDefaults = require("src.world.FieldDefaults")
local Gen3Elevation = require("src.world.Gen3Elevation")
local Badges = require("src.inventory.Badges")
local Logger = require("src.core.Logger")
local Map = require("src.world.Map")
local MapLoader = require("src.world.MapLoader")
local NPC = require("src.world.NPC")
local PaletteFX = require("src.render.PaletteFX")
local Pipelines = require("src.render.Pipelines")
local Player = require("src.world.Player")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local ScriptRunner = require("src.script.ScriptRunner")
local GameVersion = require("src.core.GameVersion")
local Tilt = require("src.render.Tilt")
local TextBox = require("src.render.TextBox")
local Transition = require("src.render.Transition")
local Warp = require("src.world.Warp")
local Zoom = require("src.render.Zoom")
local Strings = require("src.core.Strings")

-- isOverworld marks the live world state for WorldAPI's stack scan
local OverworldState = { isOpaque = true, isOverworld = true }

local Game -- set on enter (avoids circular require at load time)

local mapScripts -- registry of hand-ported map scripts

local COMPASS = { up = "north", down = "south", left = "west", right = "east" }
local DIRVEC = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- CanEncounterWildMon (37:$7B2E) skips the grass-tile test outright when the
-- map header's environment is CAVE or DUNGEON, which is why Union Cave, the
-- Ruins and Sprout Tower encounter wild mons on bare floor.  Gen1 map records
-- carry no environment byte and keep the firstIndoorMap/tileset rule below.
local CAVE_ENVIRONMENTS = { [4] = true, [7] = true }

-- healing machine ball screen positions (PokeCenterOAMData dbsprite
-- rows are raw shadow-OAM bytes, so the hardware's -8/-16 OAM origin
-- applies: screen = tile*8 + pixel offset - 8/16); [3] = OAM_XFLIP
local HEAL_BALL_XY = {
  { 40, 27 }, { 48, 27, true },
  { 40, 32 }, { 48, 32, true },
  { 40, 37 }, { 48, 37, true },
}

-- the healing machine's flash beat (FlashSprite8Times: rOBP1 ^= $28)
-- swaps the two middle shades of the monitor/ball art in place
local HEAL_FLASH_MAP = { [0] = 0, [1] = 2, [2] = 1, [3] = 3 }

-- Fishing rod placement (FishingRodOAM, engine/overworld/player_animations
-- .asm).  Those dbsprite rows are raw shadow-OAM bytes like HEAL_BALL_XY
-- above (screen = tile*8 + pixel - 8/16), measured against the player
-- sprite's fixed screen spot: ResetPlayerSpriteData parks it at $3c/$40
-- (home/reset_player_sprite.asm), i.e. screen (64,60).  So what ports over
-- is the delta from the sprite's top-left, which SpriteRenderer:draw puts at
-- (px, py - 4).  `tile` indexes the three stacked 8x8 tiles of
-- assets/generated/fx/fishing_rod.png: FishingRodOAM only ever draws $fd
-- (row 0, up/down) and $fe (row 1, left/right), and RIGHT is the LEFT tile
-- x-flipped.  Blitting the whole 8x24 sheet is what drew the rod as a
-- garbage strip (#321).
local ROD_OAM = {
  down  = { dx =  4, dy = 15, tile = 0 },              -- dbsprite  9, 11, 4, 3, $fd
  up    = { dx =  4, dy = -8, tile = 0 },              -- dbsprite  9,  8, 4, 4, $fd
  left  = { dx = -8, dy =  4, tile = 1 },              -- dbsprite  8, 10, 0, 0, $fe
  right = { dx = 16, dy =  4, tile = 1, flip = true }, -- dbsprite 11, 10, 0, 0, $fe, XFLIP
}

-- The map-name sign (engine/events/map_name_sign.asm InitMapNameSign /
-- PlaceMapNameSign).  Entering a map whose LANDMARK differs from the last
-- one pops the landmark's name up in a full-width four-row frame at the top
-- of the screen for 60 frames.  GATE maps report no landmark at all
-- (.not_gate writes -1), and .CheckSpecialMap silences six landmarks
-- outright (constants/landmark_constants.asm ids below).
local MAP_NAME_SIGN_FRAMES = 60
local MAP_NAME_SIGN_GATE = 6 -- GATE, constants/map_data_constants.asm
local MAP_NAME_SIGN_SKIP = {
  [0x00] = true, -- LANDMARK_SPECIAL
  [0x11] = true, -- LANDMARK_RADIO_TOWER
  [0x3a] = true, -- LANDMARK_UNDERGROUND_PATH
  [0x43] = true, -- LANDMARK_POWER_PLANT
  [0x45] = true, -- LANDMARK_LAV_RADIO_TOWER
  [0x59] = true, -- LANDMARK_INDIGO_PLATEAU
}

-- field.darkMaps (home/overworld.asm's dark-map check): the floors that run
-- with wMapPalOffset = 6 until FLASH
local function isDarkMap(mapId)
  if GameVersion.isGen2() then
    -- Gen2 asks the map header instead: a PALETTE_DARK map is the only one
    -- ReplaceTimeOfDayPals sends down .NeedsFlash.  Reading Gen1's pokered
    -- list here matched nothing, so Dark Cave and the Whirl Islands were lit.
    local def = Game.data.maps[mapId]
    local dark = Game.data.field.gen2DarkMaps
    if (def and dark and dark[def.label]) == true then return true end
    -- Fallback when gen2DarkMaps was not extracted (stale cache): maps
    -- using TilesetDarkCave are always dark.  TilesetCave is the lit variant.
    if def and (def.tileset == "TilesetDarkCave") then return true end
    return false
  end
  -- GEN 3 SAYS IT IN THE MAP HEADER, one byte, and nothing read it.
  --
  -- Seven maps in Hoenn need FLASH and they are exactly the seven the byte is
  -- set on -- Granite Cave's two lower floors, the Cave of Origin's three
  -- inner ones, and Victory Road's two.  Without it every cave in the region
  -- was lit and the HM had nothing to do.
  if GameVersion.isGen3() then
    local def = Game.data.maps[mapId]
    return (def and def.requiresFlash) == true
  end

  local darkDef = Game.data.field.darkMaps
  for _, m in ipairs(darkDef and darkDef.maps or {}) do
    if m == mapId then return true end
  end
  return false
end

-- object_event spawn filter (toggleable_objects, items taken, beaten
-- static encounters), shared by the current map's real NPCs and the
-- visual-only ghosts on connected neighbor maps
-- Gen1 object_events carry a name only when a script needs to toggle them.
-- Gen2's are extracted straight from the ROM and have none, so `appear` /
-- `disappear` had no key to write and silently did nothing -- the Cherrygrove
-- rival never walked on and the Elm's Lab officer never walked off.  Fall back
-- to the object's index, which is stable across a save.
local function objectToggleKey(obj)
  return obj.name or (obj.index and string.format("OBJ_%03d", obj.index)) or nil
end
OverworldState.objectToggleKey = objectToggleKey

-- MAPOBJECT_TIMEOFDAY bits, matching the ROM's MORN/DAY/NITE order.
local TOD_BITS = { MORNING = 1, MORN = 1, DAY = 2, NIGHT = 4, NITE = 4 }

-- THE PERIODS ARE THE CARTRIDGE'S, NOT GEN 2's.
--
-- Gold and Crystal have three, and TOD_BITS above is them. Polished Crystal
-- has FOUR: MORN $01 from 05:00, DAY $02 from 09:00, EVE $08 from 17:00 and
-- NITE $04 from 21:00. The extra period is NOT appended past NITE -- it is
-- bit $08 wedged between DAY and NITE on the clock while NITE keeps $04 --
-- so neither the bit nor the boundary can be guessed from the count.
--
-- With the three baked in, every object whose MAPOBJECT_TIMEOFDAY byte is
-- $08 was masked at every hour of the day (floor(8/1), floor(8/2) and
-- floor(8/4) are all even), and the DAY rows stayed up through the evening.
-- field.timeOfDay is read out of the ROM by the importer; absent -- a Gold,
-- Crystal or Gen 1 import -- the Gen 2 default below is unchanged.
local GEN2_DEFAULT_PERIODS = {
  { startHour = 4,  bit = 1, name = "MORNING" },
  { startHour = 10, bit = 2, name = "DAY" },
  { startHour = 18, bit = 4, name = "NITE" },
}

local function todPeriods()
  local field = Game and Game.data and Game.data.field
  local periods = field and field.timeOfDay
  if type(periods) == "table" and #periods > 0 then return periods end
  return GEN2_DEFAULT_PERIODS
end

-- The period covering `hour`, walking the list in clock order. The last entry
-- wraps past midnight, which is why an hour before the FIRST start belongs to
-- it and not to the first.
local function todPeriodAt(hour)
  local periods = todPeriods()
  local found = periods[#periods]
  for _, period in ipairs(periods) do
    if hour >= (tonumber(period.startHour) or 0) then found = period end
  end
  if hour < (tonumber(periods[1].startHour) or 0) then
    found = periods[#periods]
  end
  return found
end

-- The period the CURRENTLY LOADED map's objects were filtered against.
--
-- LoadObjectMasks (09:$454F) walks wMapObjects once, calling GetObjectTimeMask
-- on each, and it has exactly ONE caller in the whole ROM: LoadMapObjects
-- (05:$54DD).  So the time-of-day mask is evaluated at MAP LOAD and never
-- again -- an NPC you can see does not vanish because the clock rolled over
-- while you were standing there; the set changes the next time you walk in.
--
-- Reading the live clock (or self.tod, which the draw pass refreshes) here
-- broke that.  setMap spawns against the period at load; the clock then moves
-- on its own; and the next thing to re-run this filter -- syncObjectVisibility,
-- which fires whenever a Gen2 script finishes, i.e. the after-battle script of
-- the trainer you just beat -- culled every NPC whose MAPOBJECT_TIMEOFDAY byte
-- had gone out of period.  That is the "NPCs are sometimes invisible after I
-- defeat a trainer" report: the trainer is a coincidence, the clock is the
-- cause, and the NPCs that went were the time-gated ones.
--
-- self.tod is also nil for the whole boot/continue spawn pass (it is only ever
-- assigned inside timeOfDay(), which enter() reaches after setMap), so a save
-- continued at night used to come up with the DAY set on its first map.
local function objectTimeOfDay()
  local ow = Game and Game.overworld
  return (ow and (ow.objectTod or ow.tod)) or "DAY"
end

-- The MAPOBJECT_TIMEOFDAY bit for the period the map's objects were frozen
-- against.  This is taken from the HOUR, not from the period NAME: the name
-- is what the palette and encounter tables key off and they only know Gen 2's
-- three, so routing the object filter through it would have thrown the fourth
-- period away again on the way past.
local function objectTodBit()
  local ow = Game and Game.overworld
  local bit = ow and tonumber(ow.objectTodBit)
  if bit then return bit end
  local period = todPeriodAt(tonumber(os.date("%H")) or 12)
  if period and tonumber(period.bit) then return tonumber(period.bit) end
  return TOD_BITS[objectTimeOfDay()] or TOD_BITS.DAY
end

local function objectInTimeOfDay(obj)
  if not obj.timeOfDay then return true end
  return math.floor(obj.timeOfDay / objectTodBit()) % 2 == 1
end

local function objectVisible(save, mapId, obj)
  local toggles = save.objectToggles and save.objectToggles[mapId] or {}
  local toggleKey = objectToggleKey(obj)
  -- constants/event_flags.asm, "Sprite visibility flags": when the event is
  -- cleared the sprite is visible, when set it is hidden.  obj.hidden already
  -- carries InitializeEventsScript's opening state, so it is the whole answer
  -- until a script toggles the flag.  (A Gen2-only override used to force every
  -- in-bounds hidden object visible, to paper over an extractor that stopped
  -- reading `setevent`s at the `variablesprite` block; that read is fixed, and
  -- the override was what kept the DAY-CARE MAN OUTSIDE standing at the fence
  -- with no EGG to hand over.)
  local visible = not obj.hidden
  if toggleKey and toggles[toggleKey] ~= nil then
    visible = toggles[toggleKey]
  end
  -- Gen2's `disappear`/`appear` last only as long as the map is loaded.  They
  -- write the object struct, and every map load rebuilds those structs from
  -- the map's own object_events -- so an object with no event flag is back the
  -- next time you walk in.  A script that means "gone for good" pairs the
  -- disappear with a `setevent` on the object's OWN flag, which is the branch
  -- below.
  --
  -- Recording them in save.objectToggles instead made every one permanent.
  -- Script_WalkToBattleTowerElevator is `follow 2, 0 / applymovement 2 /
  -- disappear 2` -- the Battle Tower receptionist walking you into the lift --
  -- and she has no event flag, so once she had shown you in she was gone from
  -- the lobby desk for the rest of the save.
  local session = save.g2ObjectToggles
  if toggleKey and type(session) == "table" and session.mapId == mapId
     and session[toggleKey] ~= nil then
    visible = session[toggleKey]
  end
  -- Gen2 object_events carry an event flag; the ROM hides the object while
  -- that flag is set (the Elm's Lab officer, the Cherrygrove rival, ...).
  -- obj.hidden already carries the new game state, so only an explicit
  -- set/clear by a script overrides it.
  if obj.eventFlag and save.flags and save.flags[obj.eventFlag] ~= nil then
    visible = not save.flags[obj.eventFlag]
  end
  -- AN OBJECT THE MAP'S OWN SCRIPTS SPAWN IS NOT THERE UNTIL THEY DO.
  --
  -- Emerald's `addobject` is a runtime spawn -- TrySpawnObjectEvent -- and it
  -- does not touch the object's event flag.  So an object a map script
  -- addobjects is one the cartridge expects to be ABSENT when you walk in;
  -- writing the command at all would be pointless otherwise.  The import
  -- resolves those targets (they are usually a scratch variable filled by a
  -- setvar two lines earlier) and lists them per map.
  --
  -- The bedroom is what this is for.  It carries two object events on the
  -- STAIRS CELL -- Mom, and the rival in the other child's clothes -- and both
  -- are addobject targets.  With nothing to say so, both stood on those stairs
  -- from the first moment of the game.
  local spawnList = Game and Game.data and Game.data.map_scripts
                    and Game.data.map_scripts.spawned
  local scripted = spawnList and spawnList[mapId]
  if scripted and obj.index and scripted[obj.index] then
    -- an explicit toggle by a script wins; nothing else does
    local told = obj.eventFlag and save.flags and save.flags[obj.eventFlag]
    local slot = save.gen3Spawned and save.gen3Spawned[mapId]
    local here = slot and obj.index and slot[obj.index]
    if told ~= nil then
      visible = not told
    elseif here ~= nil then
      visible = here
    else
      visible = false
    end
  end
  -- ...AND AN OBJECT WITH NO FLAG OF ITS OWN, TAKEN AWAY FOR THIS VISIT.
  --
  -- Reported from play: "some characters arent disappearing when they should
  -- during events".  Fourteen objects in Hoenn are `removeobject`ed by a
  -- scene, carry no event flag, and are never `addobject`ed -- they are
  -- standing there when you walk in and the scene takes them away.  Nothing
  -- read the answer for those: `gen3Spawned` is consulted only inside the
  -- scripted-spawn branch above, so the removal was written to a table no
  -- reader ever looked at and the actor simply stayed.
  --
  -- SESSION-SCOPED, exactly as the Gen 2 arm above is and for exactly the
  -- same reason: Emerald's RemoveObjectEvent writes the LOADED map's object
  -- struct, and the next map load rebuilds every struct from the map's own
  -- object_events.  A script that means "gone for good" pairs the removal
  -- with its own event flag, which is the branch further up.  Recording these
  -- permanently instead would take an NPC off their spot for the rest of the
  -- save the first time a cutscene walked them out of shot.
  local gen3Session = save.gen3SessionObjects
  if type(gen3Session) == "table" and gen3Session.mapId == mapId
     and obj.index and gen3Session[obj.index] ~= nil
     and not (scripted and scripted[obj.index]) then
    visible = gen3Session[obj.index]
  end
  -- A Gen2 berry tree hands out an item but is scenery: it stays rooted once
  -- picked, where an item ball vanishes.
  if obj.item and not obj.fruitTree and save.itemsTaken
     and save.itemsTaken[mapId .. "_obj_" .. obj.index] then
    visible = false
  end
  if obj.pokemon and save.defeatedTrainers[mapId .. "_obj_" .. obj.index] then
    visible = false
  end
  if visible and not objectInTimeOfDay(obj) then
    visible = false
  end

  -- AN OBJECT WHOSE ART A SCRIPT HAS NOT ASSIGNED YET IS NOT ON THE MAP.
  --
  -- Gen 3's last graphics rows are run-time SLOTS, not characters: a script
  -- picks what goes in one, and until it has, the row holds a placeholder
  -- that the table shares between several slots. Drawn anyway, the placeholder
  -- is a stranger -- a Team Magma grunt standing outside your house, and
  -- twelve of them along one wall of your bedroom.
  --
  -- 337 object events on this cartridge name such a slot. Every one of them
  -- is also flag-gated, so this only decides what happens in the window
  -- between the map loading and the script that fills the slot running.
  --
  -- Ask through Gen3Commands.objectSprite rather than the table directly: an
  -- imported Emerald save fills the vars out of the cartridge's own
  -- SaveBlock without going through setVar, and reading only the cache left
  -- every one of these people missing on a save carried in from a real game.
  if visible and obj.varSprite then
    local ok, filled = pcall(function()
      return require("src.script.Gen3Commands").objectSprite(save,
                                                            obj.varSprite)
    end)
    if not (ok and filled) then visible = false end
  end
  return visible
end
OverworldState.objectVisible = objectVisible -- exposed for tests + reuse

-- NPC instance pool: one NPC object per map object, keyed by the
-- NPC.id format ("<mapId>_obj_<index>").  The same instance serves as
-- a neighbor-map ghost and as the real NPC once that map is entered,
-- so positions/facings carry across connection seams.
-- WHERE AN OBJECT LIVES, as opposed to where the map file says it starts.
--
-- A Gen 3 script can move an object's HOME with `setobjectxyperm` or
-- `copyobjectxytoperm` -- that is how a cutscene that walks somebody to a new
-- spot makes them stay there.  Both wrote `save.gen3ObjectHomes` and NOTHING
-- IN THE ENGINE EVER READ IT, so the home was recorded faithfully on every
-- one of those calls and then ignored the next time the map was built: the
-- NPC was back where they began the moment you left the room and returned.
--
-- The def is shared and must not be edited, so the override is a copy.
-- `save` is passed rather than read off the Game upvalue: this runs while
-- neighbour strips are built too, and a test can hand it a save without
-- standing a whole game up.
local function objectHome(save, mapId, obj)
  save = save or (Game and Game.save)
  local homes = save and save.gen3ObjectHomes and save.gen3ObjectHomes[mapId]
  local home = homes and homes[obj.index]
  if not (home and home.x and home.y) then return obj end
  local moved = {}
  for k, v in pairs(obj) do moved[k] = v end
  moved.x, moved.y = home.x, home.y
  return moved
end
OverworldState.objectHome = objectHome -- exposed for tests

local function pooledNPC(pool, data, mapId, obj)
  local key = mapId .. "_obj_" .. obj.index
  local npc = pool[key]
  if not npc then
    npc = NPC.new(data, mapId, objectHome(nil, mapId, obj))
    -- A BURIED TRAINER IS NOT ON SCREEN UNTIL THEY NOTICE YOU.
    --
    -- MOVEMENT_TYPE_BURIED keeps the sprite invisible; the trainer rises out
    -- of the ground when they spot the player and stays up afterwards.  The
    -- flag lives on the NPC rather than in the save because that is exactly
    -- how long it lasts: leave Route 113 and come back and they are under the
    -- ash again, which is what the cartridge does too.
    npc.buried = obj.buried and true or nil
    -- `hidden` is what the draw pass reads; `buried` is the memory of WHY,
    -- so a trainer already beaten can be brought back up without also
    -- un-hiding something a script deliberately took off screen.
    npc.hidden = npc.buried or npc.hidden
    -- A BERRY PLOT WITH NOTHING IN IT IS SOIL, NOT A TREE.
    --
    -- Reported from play: "berry planting spots are looking like they already
    -- have berries planted when theres nothing there."  They were: all 88 of
    -- Hoenn's plots drew the same tree sprite whatever was -- or was not --
    -- growing in them, and on a fresh save that is nothing at all, because
    -- the cartridge blanks every one of its 128 tree slots at new game.
    --
    -- Hidden rather than absent, which is the same distinction the invisible
    -- KECLEON above needed: the object is still THERE.  It still blocks the
    -- tile and pressing A on it still runs its script -- which is the script
    -- that plants a berry, so an empty plot the player could not reach would
    -- be a plot they could never use.
    --
    -- WHICH OBJECTS ARE TREES is not guessed: the import finds the graphics
    -- ids whose frame table has the berry tree's own shape -- nine frames,
    -- the first three 16x16 and the last six 16x32 -- and there are exactly
    -- three of them, which is how three trees stand on one map.
    local okBerry, treeId = pcall(function()
      local G = require("src.script.Gen3Commands")
      if not G.isBerryTree(data, obj) then return nil end
      local id = tonumber(obj.trainerRange)
      return (id and id > 0) and id or nil
    end)
    if okBerry and treeId then
      npc.berryTreeId = treeId
      -- SetBerryTreesSeen (0x00E1D9x -> AllowBerryTreeGrowth 0x00E1A78): a
      -- tree the new game planted is frozen -- `setberrytree` passes
      -- allowGrowth = FALSE -- until its object comes into view, and the
      -- cartridge unfreezes it by walking the loaded map's object templates
      -- and clearing the bit on every berry tree inside the camera window.
      -- Spawning IS that moment here: an object only reaches this line when
      -- its map is loaded and it is being placed.  Without it Route 104's
      -- trees would be fruiting forever and never regrow after picking.
      pcall(function()
        require("src.script.Gen3Commands")
          .allowBerryTreeGrowth(Game and Game.save, treeId)
      end)
    end
    pool[key] = npc
    if Runtime.wants("world.npc_spawned") then
      Runtime.emit("world.npc_spawned",
        { mapId = mapId, npcId = key, runtime = obj.runtime == true })
    end
  end
  return npc
end
OverworldState.pooledNPC = pooledNPC -- exposed for tests

-- connection hops rendered around the current map: two, so
-- A CONNECTION IS NOT ALWAYS A NEIGHBOUR.
--
-- Gen 3 keeps DIVE and EMERGE in the same connection table as north, south,
-- east and west -- a route's seafloor and a seafloor's route are connections
-- of the map, they are simply not connections in the PLANE.  This walk used
-- to take anything that was not north, south or west as east, so a seafloor
-- map laid its emerge target out to the right of itself and drew it.
--
-- Reported from play as "when I dive sometimes it's showing cities instead of
-- the underwater area": the underwater map beneath SOOTOPOLIS emerges into
-- Sootopolis, so the city was tiled alongside the seafloor and painted over
-- the edge of it.  "Sometimes" is the camera -- it only shows where the
-- misplaced neighbour lands within reach.
-- which of Hoenn's three bubbles an emote index means; 1 is the "!" a
-- trainer puts up when they see you, which is the only one the engine raises
-- on its own
local GEN3_EMOTE_ROLES = { "exclamation", "question", "heart" }

local NEIGHBOUR_DIRS = {
  north = true, south = true, east = true, west = true,
}

-- corner-adjacent maps (connections of connections) don't pop in and
-- out of the survey zoom at the seams (constants.world.neighborHops)
local NEIGHBOR_HOPS = 2

-- Neighbor placement (pure; exposed for tests): walk the connection
-- graph `hops` connections out, composing the strip offsets, deduped
-- by map id (BFS, so a direct connection always wins over a two-hop
-- path).  Offsets are world pixels; connection offsets are in blocks
-- (32 px), the same alignment the connection macro encodes
-- (macros/scripts/maps.asm: _x = offset * -2 walk cells for
-- north/south, _y = offset * -2 for west/east).
-- reachW/reachH (optional, world pixels): with a full zoom-out the view
-- shows far more world than the fixed hop count covers, so any map whose
-- body could overlap the current map's rect inflated by the view
-- half-extents joins the set (and keeps the walk going) regardless of how
-- many connections away it sits -- otherwise far map bodies pop between
-- real tiles and the border filler when a crossing re-roots the BFS.
--
-- A BLOCK IS NOT ALWAYS 32 PIXELS.  This walk multiplied every width, height
-- and offset by 32 because a Game Boy block is 4x4 tiles.  A Gen 3 metatile
-- is 2x2 -- sixteen pixels -- so on Hoenn every neighbour was placed at twice
-- its true distance and Littleroot's routes hung off the world in mid-air.
-- The size travels with the map def, so a dataset that does not say keeps the
-- Game Boy's.
local function blockPx(def)
  return (def and tonumber(def.blockPx)) or 32
end

function OverworldState.computeNeighbors(maps, rootId, hops, reachW, reachH)
  local out = {}
  local rootDef = maps[rootId]
  local placed = { [rootId] = true }
  local queue = { { def = rootDef, ox = 0, oy = 0, hops = 0 } }
  local qi = 1
  local function inReach(def, ox, oy)
    if not (reachW and reachH and rootDef) then return false end
    local rp = blockPx(rootDef)
    local dp = blockPx(def)
    return ox + def.width * dp > -reachW
       and ox < rootDef.width * rp + reachW
       and oy + def.height * dp > -reachH
       and oy < rootDef.height * rp + reachH
  end
  while queue[qi] do
    local cur = queue[qi]
    qi = qi + 1
    -- EVERY connection on an edge, not just the first.
    --
    -- Two edges in Hoenn carry two, and both of their second neighbours are
    -- reached today only by accident of this walk finding them the long way
    -- round -- which composes to the right offset, but breaks the moment the
    -- hop budget or the reach test tightens.  Placing them directly is what
    -- the cartridge's own connection list says to do.
    for dir, first in pairs(cur.def.connections or {}) do
    for _, conn in ipairs(first.list or { first }) do
      local destDef = NEIGHBOUR_DIRS[dir] and maps[conn.map]
      if destDef and not placed[conn.map] then
        placed[conn.map] = true
        local ox, oy
        local cp, dp = blockPx(cur.def), blockPx(destDef)
        if dir == "north" then
          ox, oy = conn.offset * cp, -destDef.height * dp
        elseif dir == "south" then
          ox, oy = conn.offset * cp, cur.def.height * cp
        elseif dir == "west" then
          ox, oy = -destDef.width * dp, conn.offset * cp
        else
          ox, oy = cur.def.width * cp, conn.offset * cp
        end
        ox, oy = cur.ox + ox, cur.oy + oy
        if cur.hops + 1 <= hops or inReach(destDef, ox, oy) then
          table.insert(out, { id = conn.map, ox = ox, oy = oy })
          if cur.hops + 1 < hops or inReach(destDef, ox, oy) then
            table.insert(queue,
                         { def = destDef, ox = ox, oy = oy,
                           hops = cur.hops + 1 })
          end
        end
      end
    end
    end
  end
  return out
end

function OverworldState:enter(mapId, x, y, facing)
  Game = require("src.core.Game")
  Game.overworld = self
  -- The live overworld under BOTH names, and a back-reference to the Game.
  --
  -- `Game.world` is not a second concept: it is `Game.overworld`, published
  -- under the name Gen1Recomp used and every mod written against that engine
  -- reads.  STADIUM2_OVERWORLD_MODELS decides whether it is even on the
  -- Stadium rung with `if V.game and V.game.world and ... then return "A" end`
  -- (lib/Stadium.lua, Stadium.mode) -- so with the field absent it answered
  -- "no rung", Stadium.begin declined, and the in-world 3D battle rendered a
  -- perfect empty stage: 217 frames, no errors, and no Pokemon on it.
  --
  -- `self.game` closes the loop the other way.  The mod's colour atlas reaches
  -- the palette data as `world.game.data...`, and its follower bridge and
  -- compose bridge both walk `world.game` too.  Set here rather than at
  -- construction because this is where the state learns which Game owns it.
  Game.world = self
  self.game = Game
  Collision.load(Game.data) -- tile-pair (elevation) collisions
  Encounter.load(Game.data) -- constants.encounterBuckets
  -- ...and the PC's shape, which is 12x20 in Kanto, 14x20 in Johto and
  -- 14x30 in Hoenn, where it comes off the derived save layout
  require("src.pokemon.Boxes").load(Game.data)
  mapScripts = require("data.scripts.init")
  self.camera = Camera.new()
  self.runner = ScriptRunner.new(Game, self)
  self.scriptMoves = {}
  self.pendingScripts = {}
  self.parallelRunners = {}
  self.parallelQueue = {}
  self.npcMoveLocks = {}
  self.marchers = {}
  -- one-shot trainer-engagement state: must not survive a save/load or
  -- a fresh entry, or a stale flag can freeze player input forever
  self.engaging = false
  self.emote = nil
  -- survives save/load: a loaded game may start inside a building whose
  -- exit mat is a LAST_MAP warp
  self.lastOutdoor = Game.save.lastOutdoor
  -- GSC's wBackupWarp: the warp tile we last stepped through, on any map
  self.backupWarp = Game.save.backupWarp
  self:setMap(mapId, x, y, facing, { via = "boot" })
  -- boot/load: derive the flag from the tile the save left us standing on,
  -- like MapEntryAfterBattle's IsPlayerStandingOnWarp, so a game saved on a
  -- door mat can still walk straight back out (issue #378)
  -- Gen2 daily resets also run here so a continued save whose calendar day
  -- already advanced while the game was closed still clears Kurt / trees /
  -- lottery on the first frame in the overworld.
  if GameVersion.isGen2() and Game.save then
    require("src.script.Gen2Daily").poll(Game.save)
  end
  self:refreshStandingOnWarp()
end

-- Silph Co card key doors + Rocket Hideout elevator gates: the .blk
-- layouts ship with the doorways open; each floor's map script stamps
-- the closed door block on load until its unlock event is set
-- (scripts/SilphCo2F.asm SilphCo2FGateCallbackScript et al., closed
-- blocks $54/$5f/$20; scripts/RocketHideoutB1F.asm +
-- RocketHideoutB4F.asm ...DoorCallbackScript, closed blocks $54/$2d over
-- the lift doorway).  A door opens on its single `event`, or on `events`
-- when every listed flag must be set (Rocket Hideout B4F's lift gate
-- needs both guard trainers beaten -- CheckBothEventsSet).  The callbacks
-- run whenever BIT_CUR_MAP_LOADED_1 is set, which is map load AND the end
-- of a battle on that map (home/trainers.asm EndTrainerBattle), so the
-- gate opens with SFX_GO_INSIDE the moment the last guard falls (#372).
function OverworldState:stampClosedDoors()
  local closedDoors = FieldDefaults.fieldValue(Game.data, "cardKeyDoors",
                                               "closedDoors")
  local floorDoors = self.map and closedDoors and closedDoors[self.map.id]
  if not floorDoors then return end
  local stamped, unlocked = false, false
  for _, door in ipairs(floorDoors) do
    local open
    if door.events then
      open = true
      for _, ev in ipairs(door.events) do
        if not Game.save.flags[ev] then open = false break end
      end
    else
      open = Game.save.flags[door.event]
    end
    local want = open and door.open or door.block
    if self.map:blockAt(door.bx, door.by) ~= want then
      self.map:setBlock(door.bx, door.by, want)
      stamped = true
      if open then unlocked = true end
    end
  end
  if stamped then self.map.renderer:rebuild() end
  if unlocked then require("src.core.Sound").play(Game.data, "Go_Inside") end
end

function OverworldState:setMap(mapId, x, y, facing, opts)
  local fromMapId = self.map and self.map.id
  if fromMapId then
    Runtime.emit("map.exited", { mapId = fromMapId, toMapId = mapId })
  end
  -- ambient choreography is per-map: parallel runners die here, and the
  -- departing map's queued scripts go with them unless the enqueuer
  -- asked to persist across the warp
  if self.parallelRunners then
    for i = #self.parallelRunners, 1, -1 do
      self:killParallel(self.parallelRunners[i])
    end
    self.parallelQueue = {}
  end
  self.marchers = {}
  local queue = self.pendingScripts
  if queue then
    for i = #queue, 1, -1 do
      local entry = queue[i]
      if entry.mapId ~= mapId
         and not (entry.extra and entry.extra.persistAcrossWarp) then
        table.remove(queue, i)
      end
    end
  end
  -- a scripted tile-anim override lasts until map change
  if self.tileAnimOverride then
    self.tileAnimOverride.tileset.animation = self.tileAnimOverride.animation
    self.tileAnimOverride = nil
  end
  -- Every mode that shows hardware colour bakes it into the tileset atlas --
  -- ADVANCED on Gen 1, and ALL of them on Gen 2, which picks the tileset's
  -- DARKNESS palette row off darkWorld -- so the dark-cave shift has to be
  -- armed before that atlas is built for this map (#383); self.dark is settled
  -- below, once the map record is in hand.
  -- ...but NOT on Gen 3, where darkness is a hole rather than a shade: Emerald
  -- draws the cave at full brightness under a black window with a circle cut
  -- out around the player (see Gen3Flash), and shading the atlas as well would
  -- dim the part you can actually see.
  if PaletteFX.setDarkWorld(isDarkMap(mapId) and not GameVersion.isGen3()
                            and not require("src.world.Gen3Flash").lit(Game))
     and PaletteFX.bakesDarkness() then
    MapLoader.invalidateAll()
  end
  -- The map's own PALETTE_* override (map header byte 7, low nibble).  It has
  -- to be armed here for the same reason darkWorld does -- the time-of-day row
  -- is baked into the tileset atlas -- and it is what stops every indoor map
  -- and the Ruins of Alph chambers taking the NITE row after 6pm.
  if GameVersion.isGen2() then
    local paletteDef = Game.data.maps[mapId]
    if PaletteFX.setGen2MapPalette(paletteDef and paletteDef.mapPalette or 0)
       and PaletteFX.usesGen2BgPal() then
      MapLoader.invalidateAll()
    end
  end
  self.map = MapLoader.load(Game.data, mapId)
  -- Every block change is re-derived from the map's callbacks on each load
  -- (GSC rebuilds wOverworldMap from the ROM blockdata), so the previous
  -- visit's patches have to go first: a Ruins of Alph wall that the callback
  -- closed would otherwise stay closed after the puzzle is solved.
  if self.map:clearBlockPatches() then self.map.renderer:rebuild() end
  -- STRENGTH deactivates on every real map load (home/overworld.asm
  -- EnterMap -> ResetUsingStrengthOutOfBattleBit clears BIT_STRENGTH_ACTIVE
  -- of wStatusFlags1).  setMap is the single choke point for every map-id
  -- change -- warps and seamless connection crossings alike -- so an
  -- unconditional reset here reproduces that default clear path.  It is
  -- deliberately NOT part of Game.save: the flag lives in plain WRAM, not
  -- SRAM, so it must not survive a save/load.  Not reset in afterBattle:
  -- pokered keeps STRENGTH across a same-map battle return (EnterMap skips
  -- the reset when BIT_BATTLE_OVER_OR_BLACKOUT is set).
  self.strengthActive = false
  -- Cut trees grow back when the map reloads (like the original)
  if self.cutBlocks and self.cutBlocks[mapId] then
    for _, c in ipairs(self.cutBlocks[mapId]) do
      self.map:setBlock(c.bx, c.by, c.block)
    end
    self.map.renderer:rebuild()
    self.cutBlocks[mapId] = nil
  end
  self:stampClosedDoors()
  -- forced dismount only where riding is disallowed (IsBikeRidingAllowed,
  -- home/overworld.asm: bike_riding_tilesets.asm tilesets plus the
  -- ROUTE_23/INDIGO_PLATEAU map exceptions)
  if Game.save.onBike and not self:bikeAllowed(mapId) then
    Game.save.onBike = false
  end
  -- THE TWO GENERATIONS CLEAR THE CYCLING ROAD IN COMPLETELY DIFFERENT WAYS,
  -- and treating Gen 2 like Gen 1 is why the bike would not come off.
  --
  -- GEN 1 keeps BIT_ALWAYS_ON_BIKE in a bit that SURVIVES a map change; it is
  -- armed by the forced-bike TILE at the top of the road and cleared by the
  -- gate maps' own scripts (scripts/Route16Gate1F.asm / Route18Gate1F.asm
  -- `res BIT_ALWAYS_ON_BIKE`). Naming those maps is the whole mechanism, so
  -- the list below is still exactly right there.
  --
  -- GEN 2 DOES NOT WORK LIKE THAT AT ALL. Both flags live in wBikeFlags, which
  -- is RAM, and HandleNewMap wipes it on EVERY new map before any of that
  -- map's callbacks get to speak (engine/overworld/warp_connection.asm):
  --
  --     HandleNewMap:
  --         call ClearUnusedMapBuffer
  --         call ResetMapBufferEventFlags
  --         call ResetFlashIfOutOfCave
  --         call GetCurrentMapSceneID
  --         call ResetBikeFlags          <-- here
  --         ld a, MAPCALLBACK_NEWMAP
  --         call RunMapCallback
  --
  -- The Cycling Road is then re-armed from scratch every single load, by the
  -- only two maps that ask for it:
  --
  --     Route17AlwaysOnBikeCallback:     setflag ENGINE_ALWAYS_ON_BIKE
  --                                      setflag ENGINE_DOWNHILL
  --     Route16AlwaysOnBikeCallback:     readvar VAR_YCOORD / ifless 5, .CanWalk
  --                                      readvar VAR_XCOORD / ifgreater 13, .CanWalk
  --                                      setflag ENGINE_ALWAYS_ON_BIKE
  --                        .CanWalk:     clearflag ENGINE_ALWAYS_ON_BIKE
  --
  -- Nothing else in the game clears either one -- not the gates, not Route 18,
  -- not Route 16 for DOWNHILL. It does not have to: the reset above already
  -- did it. THIS PORT HAD NO SUCH RESET. It stores those two flags in
  -- `save.flags`, which is persistent AND serialised to disk, and the only
  -- thing that ever cleared them was this list of four gate maps. So the first
  -- load of Route 17 set them, and from then on every map in the game loaded
  -- with ALWAYS_ON_BIKE and DOWNHILL still set: the bike was forced back on
  -- through every door, and the downhill pull dragged the player south on maps
  -- that have no slope -- exactly as reported, and it survived saving and
  -- reloading too.
  --
  -- An internal reload is NOT a new map, and neither is it on the cartridge:
  -- a refresh runs HandleContinueMap, which skips ResetBikeFlags entirely.
  -- Wiping the flags on a palette or time-of-day rebuild would put the player
  -- on foot in the middle of the Cycling Road.
  if GameVersion.isGen2() then
    if not (opts and opts.via == "reload") then
      self:clearBikeFlags()
    end
  else
    -- ...and an EMPTY imported list is not an answer, it is a gap.  The Gen 2
    -- extractor writes `clearMaps = {}` unconditionally, and fieldValue returns
    -- any non-nil data value rather than falling back, so read the defaults
    -- when the import left nothing behind.
    local clearMaps = FieldDefaults.fieldValue(Game.data, "forcedMovement",
                                               "clearMaps")
    if type(clearMaps) ~= "table" or #clearMaps == 0 then
      clearMaps = FieldDefaults.FIELD.forcedMovement.clearMaps
    end
    for _, m in ipairs(clearMaps or {}) do
      if m == mapId then self:clearBikeFlags() break end
    end
  end
  -- leaving the Safari Zone maps ends any running Safari game -- on the
  -- cartridges where the zone IS a set of maps.  In Hoenn it is a mode, and
  -- only ExitSafariMode ends it; clearing it here shut the game down on the
  -- first step past the gate.
  if Game.save.safari and not GameVersion.isGen3()
     and not Map.inRegion(self.map.def, "SAFARI", "SAFARI_ZONE") then
    Game.save.safari = nil
  end
  -- Rock Tunnel darkness (wMapPalOffset, home/overworld.asm): dark
  -- until FLASH is used; the light persists between the tunnel floors
  -- and resets once outside
  if isDarkMap(mapId) then
    -- SetDefaultFlashLevel, on Gen 3: the map header's cave byte plus the
    -- FLASH flag choose a LEVEL, and the level chooses the radius of the hole
    -- the field draws.  The flat shade stays off -- setDark(false) -- because
    -- on this generation the darkness is the window, not the palette.
    if GameVersion.isGen3() then
      local Gen3Flash = require("src.world.Gen3Flash")
      Gen3Flash.defaultFor(Game, true, Gen3Flash.lit(Game))
      self:setDark(false)
    else
      self:setDark(not Game.save.flashLit)
    end
  else
    if GameVersion.isGen3() then
      require("src.world.Gen3Flash").defaultFor(Game, false)
    end
    -- ResetFlashIfOutOfCave (00:$2F1D) only clears the flash bit on a TOWN or
    -- a ROUTE, so the light carries between the floors of a cave system and
    -- across the lit rooms in the middle of one.
    if not (GameVersion.isGen2() and self.map.def.environment
            and self.map.def.environment > 2) then
      if GameVersion.isGen3() then
        require("src.world.Gen3Flash").setLit(Game, false)
      else
        Game.save.flashLit = nil
      end
    end
    self:setDark(false)
  end
  local flyWarps = (Game.data.field or {}).flyWarps or {}
  if flyWarps[mapId] then
    Game.save.visited = Game.save.visited or {}
    Game.save.visited[mapId] = true
  end
  -- NPC instances persist across connection crossings in self.npcPool
  -- (keyed by NPC.id): a neighbor map's wandering ghosts ARE the
  -- objects that become the real NPCs when the player crosses the
  -- seam, so nothing snaps back to its spawn point in view of the
  -- survey zoom.  Warps rebuild from scratch, like the original's
  -- per-entry sprite init (home/overworld.asm LoadMapHeader
  -- .loadSpriteData).
  if not (opts and opts.seamless and self.npcPool) then
    self.npcPool = {}
    -- LoadMapObjects re-reads every object_event from ROM, so a `moveobject`
    -- from the last visit does not survive the reload
    self.npcPlacement = nil
    self.npcResumeCell = nil
  end
  self.npcs = {}
  -- LoadMapObjects is where the ROM evaluates the time-of-day mask, and the
  -- only place it does (LoadObjectMasks has one caller) -- so pin the period
  -- here and let every later filter run answer to THIS value rather than to
  -- the clock, which keeps moving.  See objectInTimeOfDay.
  --
  -- Read from the clock rather than self.tod: on the boot/continue path
  -- timeOfDay() has not run yet and self.tod is still nil.
  local clock = GameVersion.isGen2() and OverworldState.clockTimeOfDay or nil
  self.objectTod = (clock and clock()) or self.tod or "DAY"
  -- ...and the BIT beside it, for the same reason the name is frozen here:
  -- the mask is evaluated once per map load and must not follow the clock
  -- while you are standing on the map.
  self.objectTodBit = OverworldState.clockTimeOfDayBit()
  -- Gen2's `disappear`/`appear` write the object struct, and LoadMapObjects
  -- rebuilds every struct from the map's own object_events -- so a `disappear`
  -- that was not paired with a `setevent` is undone by walking back in.  The
  -- scratch table is keyed by the map it was written on, which made it inert
  -- while you were away and live again the moment you returned: an NPC a
  -- script had walked off stayed gone for the rest of the save.  An internal
  -- reload (a palette/tod atlas rebuild, a `refreshmap`) is not a map load and
  -- must not undo one.
  if not (opts and opts.via == "reload") then
    Game.save.g2ObjectToggles = nil
    -- ...and Gen 3's, which is the same idea for the same reason: a
    -- `removeobject` with no event flag behind it lasts as long as the map
    -- stays loaded and no longer.
    Game.save.gen3SessionObjects = nil
  end
  -- MAPCALLBACK_OBJECTS: ROUTE_34 and DAY_CARE both re-derive their day-care
  -- sprite events from the engine flags every time the map is set up
  if GameVersion.isGen2() and (mapId == "ROUTE_34" or mapId == "DAY_CARE") then
    require("src.pokemon.DayCare").syncObjects(Game.data, Game.save)
  end
  for _, obj in ipairs(self.map.def.objects or {}) do
    if objectVisible(Game.save, mapId, obj) then
      local npc = pooledNPC(self.npcPool, Game.data, mapId, obj)
      npc.frozen = false
      table.insert(self.npcs, npc)
    end
  end
  -- ...and whatever the player has PUT OUT here, which is not in the map's
  -- object list because it was never in the cartridge's either
  self:applyGen3Decorations(mapId)
  -- ...and the rotating gates, which are back at their starting positions
  -- every time you walk in -- the map's own entry copies each gate's default
  -- orientation over whatever you left it turned to
  self:startGen3Gates(mapId)
  if self.player then
    self.player.cellX, self.player.cellY = x, y
    self.player.px, self.player.py = x * 16, y * 16
    self.player.facing = facing or self.player.facing
    self.player.moving = false
    self.player.targetX, self.player.targetY = nil, nil
  else
    self.player = Player.new(Game.data, x, y, facing)
  end
  -- A SCRIPT WAITING ON A WALK THAT THIS MOVE JUST ENDED.
  --
  -- waitmovement yields until the overworld reports the walk finished, and
  -- the report comes from the entity's own step callback.  Changing the map
  -- takes that entity away, so the report never comes: the script never
  -- resumes and the player is frozen for the rest of the session, with
  -- nothing in the log to say why.
  --
  -- The starter hand-over is the scene that reaches this -- it walks Birch,
  -- talks, and then warps to the lab, all from one script -- and "I got
  -- teleported to the lab and then couldn't move" is exactly what it looks
  -- like from the outside.
  --
  -- ...AND THE WALKS THEMSELVES, which is the half that was missing.
  --
  -- Reported from play: "when he catches the ralts and we get teleported back
  -- to the gym the game just freezes", with the watchdog's own line under it:
  --
  --   input has been gated for 10s on MAP_G00_N00 with nothing on screen --
  --   held by: a script is running, 2 scripted move(s) queued, the player is
  --   mid-step
  --
  -- Petalburg Gym's scene (0204AAC) walks Norman, Wally and the player, and
  -- then -- with those walks still in flight -- runs `warp 0 0 255 15 8` and
  -- `waitstate`.  On the cartridge the warp ends every one of them: map load
  -- resets the object events outright.  Here the queue survived, so the
  -- player's leftover steps re-armed on the far side of the warp and the
  -- moves belonging to people who no longer exist sat in the queue for ever
  -- -- and `#scriptMoves > 0` is one of the conditions that gates every
  -- input frame.
  --
  -- Not on a SEAMLESS crossing: walking from one route into the next is one
  -- continuous walk on the cartridge too, and a cutscene that escorts the
  -- player over a map boundary has to keep its queue.
  if not (opts and opts.seamless) then self:releaseScriptMoves(mapId) end
  if GameVersion.isGen3() and self.runner and self.runner.ctx then
    pcall(function()
      require("src.script.Gen3Commands").releaseMapWaits(self.runner.ctx, mapId)
    end)
  end

  -- WHICH LEVEL THE PLAYER ARRIVES ON.
  --
  -- A Gen 3 cell carries an elevation as well as a collision bit, and a step
  -- between two different non-zero elevations is refused -- that is what
  -- keeps a walking trainer off the sea (water is 1, land is 3) and what
  -- separates a bridge from the river under it.  Arriving anywhere -- a warp,
  -- a connection, a load -- takes the elevation of the cell landed on, the
  -- way ObjectEventUpdateElevation does; a map with no elevation data leaves
  -- it nil and every check passes.
  if self.map.cellElevation then
    self.player.elevation = self.map:cellElevation(x, y)
  end
  -- boot only: the original persists the surf state.  wWalkBikeSurfState
  -- (ram/wram.asm) lives inside wMainDataStart..wMainDataEnd, which
  -- engine/menus/save.asm block-copies into sMainData on save and back out
  -- on load (sram.asm declares sMainData as `ds wMainDataEnd -
  -- wMainDataStart`), and Continue never clears it -- the only `xor a /
  -- ld [wWalkBikeSurfState], a` on that path is the cable club's.  Restore
  -- it here, before Music.playMap reads it below and before
  -- PikachuFollower.onMapEntered, matching LoadMapData calling
  -- LoadPlayerSpriteGraphics ahead of PlayDefaultMusic (home/overworld.asm,
  -- home/audio.asm).  Without this the player resumed on foot on a water
  -- cell, which softlocks here: Collision.canMove (src/world/Collision.lua)
  -- picks land tile-pairs whenever mover.surfing is falsy, and land
  -- tile-pairs never permit stepping off a water cell (#536).  Same
  -- boot-only shape as the refreshStandingOnWarp door-mat restore (#378).
  if opts and opts.via == "boot" then
    local ps = Game.save and Game.save.player
    if ps and ps.surfing ~= nil then
      self.player.surfing = ps.surfing and true or false
    else
      -- saves written before #536 carry no flag.  Map:isWaterCell alone is
      -- not self-sufficient (see src/world/Map.lua: water and shore share
      -- one lookup, and no tileset stamps waterTiles, so tile $14 -- a
      -- walkable floor in HOUSE/GATE/LOBBY/MANSION/MUSEUM -- reads as
      -- water), so gate it the way facingIsShoreOrWater does and require a
      -- cell you could not be standing on upright.
      self.player.surfing = self:tilesetHasWater()
        and not self.map:isWalkableCell(x, y)
        and self.map:isWaterCell(x, y)
    end
    -- re-derive from the live party: a reloaded save with the SURF-Pikachu
    -- since deposited should not render the Pikachu sheet.
    -- ponytail: re-derived rather than persisted.
    self:syncSurfingPikachu()
  end
  -- crossConnection re-arms this after setMap; clear so a warp/reload
  -- cannot leave a stale deferred PlayMapMusic pending
  self.pendingSeamMusic = nil
  -- a fresh map owns no leftover extras: start from nothing, then derive
  self.entities = nil
  self:rebuildEntities()
  -- Yellow's companion Pikachu trails the player (never in
  -- self.entities: it does not block movement, pikachu_follow.asm)
  require("src.world.PikachuFollower").onMapEntered(Game, self, opts)

  -- opts.keepMusic: the Oak-escort warp keeps MUSIC_MEET_PROF_OAK
  -- playing into the lab (BIT_NO_MAP_MUSIC in wStatusFlags7);
  -- keepMusicOnce is the play_music opts.keep one-shot of the same bit
  local keepMusic = (opts and opts.keepMusic) or self.keepMusicOnce
  self.keepMusicOnce = nil
  if not keepMusic then
    require("src.core.Music").playMap(Game.data, mapId, Game.save.onBike,
                                      self.player.surfing)
  end

  -- THE MAP'S OWN WEATHER, on every map load.
  --
  -- SetSav1WeatherFromCurrMapHeader, and it runs on the load rather than on a
  -- transition: 90 maps in Hoenn set a weather byte in their header and it
  -- reached maps.lua and stopped there.  The saved value and the ACTIVE one
  -- are two different things in the cartridge and they are two here -- the
  -- header sets both, a script's `setweather` sets only the saved one, and
  -- `doweather` is what makes the saved one active.  That separation is the
  -- whole reason Route 119's rain starts when its transition script says so
  -- and not the instant you step onto the route.
  self:applyMapWeather()
  -- ...and whatever this map's SETUP asks for is applied when the setup
  -- finishes, which is the other half of the load; see the drain in update().
  self.gen3MapWeatherPending = GameVersion.isGen3() or nil

  -- ...AND THE SCRATCH FLAGS GO, on the same load.
  self:clearGen3TempFlags()
  -- ...and so does the ice.
  --
  -- The gym's ON_TRANSITION writes its step counter back to 1 on every single
  -- entry, unconditionally, so the puzzle restarts whenever you walk in.  The
  -- cracked cells have to restart with it: the drawn tiles are rebuilt from
  -- the map layout on a load, so a remembered crack with no cracked tile
  -- under it is ice that looks whole and gives way anyway.
  if GameVersion.isGen3() and Game.save and Game.save.gen3ThinIce then
    Game.save.gen3ThinIce[mapId] = nil
  end
  -- ...and so does the plank that was down, for the same reason
  self.bridgeDown = nil
  -- ...and the log that was under, likewise
  self.logSunk = nil

  -- forced bike/surf tiles fire the moment the player is placed on the
  -- map, like EnterMap's unconditional CheckForceBikeOrSurf farcall
  -- (home/overworld.asm) -- a warp can land directly on one (the Route
  -- 16/18 gate exits), and the scripted door-mat walkout that follows
  -- suppresses onStepComplete, so waiting for a plain step never mounts
  self:checkForcedMovement()
  -- Seafoam B4F's map script pushes off the B3F stair warps every frame
  -- while the upper plugs are out (SeafoamIslandsB4FDefaultScript); the
  -- B3F/B4F force-surf mouths also arm their MOVE_OBJECT current scripts
  -- from CheckForceBikeOrSurf.  Re-check here so a warp-in does not sit
  -- idle on those cells waiting for a player step.
  self:checkSeafoamCurrent()

  -- snap the camera immediately: the overworld doesn't update while a
  -- Transition is on top, so a stale camera would show the new map at
  -- the old scroll position for the whole fade-in
  self.camera:follow(self.player.px, self.player.py,
                     Game.renderer:worldViewSize())

  -- ...AND THE REMATCH ROLL, which happens HERE and not on the step.
  --
  -- TryUpdateRandomTrainerRematches (0x080B21B4) is called from the map-load
  -- path, not from the step counter: the counter fills as you walk, and the
  -- moment it is full, WALKING INTO A MAP rolls every eligible rematch
  -- trainer standing on that map, independently, at thirty-one percent.  The
  -- counter then resets -- whether this visit armed anyone or merely found
  -- someone already waiting.
  if GameVersion.isGen3() then
    local armed = require("src.script.MatchCall")
                    .tryArm(Game.data, Game.save, mapId)
    if armed > 0 then
      Logger.debug("gen3 rematch: %d trainer(s) on %s want a rematch",
                   armed, tostring(mapId))
    end
  end

  -- THE TEMPORARY VARS AND FLAGS GO, and they go BEFORE anything on this map
  -- is asked anything -- the map-entered listeners, the onEnter chain and the
  -- frame table all read them.  ClearTempFieldEventData (0x0009D344) sits at
  -- exactly this point in both of the cartridge's map-load paths.
  if GameVersion.isGen3() and Game and Game.save then
    pcall(function()
      require("src.script.Gen3Commands").clearTempFieldEventData(Game.save)
    end)
  end

  -- fires before the onEnter chain so a listener sees the map in the same
  -- state the map script does
  Runtime.emit("map.entered", {
    mapId = mapId, map = self.map, fromMapId = fromMapId,
    via = (opts and opts.via)
          or (opts and opts.seamless and "connection")
          or (fromMapId and "warp" or "boot"),
  })

  -- StartMap calls InitCallReceiveDelay: arriving anywhere RESTARTS the wait
  -- before the next phone call.  Without it the timer only ever restarted
  -- when a call actually landed, so walking through a door -- which on the
  -- cartridge buys you a fresh twenty minutes -- did nothing, and the calls
  -- came in at a cadence the ROM never produces.
  if GameVersion.isGen2() and Game and Game.save then
    pcall(function()
      require("src.script.Gen2Commands").resetCallDelay(Game.save)
    end)
  end

  -- UpdateRoamMons: hop Raikou/Entei/Suicune when the player changes maps
  -- (only after Burned Tower release sets g2RoamReleased).
  if GameVersion.isGen2() and Game and Game.save then
    pcall(function()
      require("src.script.Gen2Commands").g2_update_roam_positions({
        save = Game.save, game = Game,
      })
    end)
  end

  -- ...AND HOENN'S ONE, which moves on the same beat.
  --
  -- RoamerMove runs on every map load, straight after the location history
  -- is updated -- so the map you have just walked onto is entry one, and the
  -- roamer will not hop onto the map you were on two loads before that.  One
  -- load in sixteen it ignores the graph entirely and turns up anywhere.
  if GameVersion.isGen3() and Game and Game.save then
    pcall(function()
      require("src.world.Gen3Roamers").step(Game.data, Game.save, mapId)
    end)
  end

  -- map-enter hooks (hand-ported map scripts, e.g. Victory Road barriers).
  -- fromMapId lets elevators seed a valid walk-out floor when the ROM
  -- car warps still point at a missing map (Silph's UNUSED_MAP_ED) and
  -- the player B-cancels the floor menu without .UpdateWarp.
  local hooks = mapScripts.get(mapId)
  if hooks and hooks.onEnter then
    hooks.onEnter(Game, self, fromMapId)
  end
  -- CheckUpdatePlayerSprite's .CheckForcedBiking (engine/overworld/map_setup.asm):
  -- with BIKEFLAGS_ALWAYS_ON_BIKE set, wPlayerState is forced to PLAYER_BIKE.
  -- Gen2 arms that flag from the map's own MAPCALLBACK_NEWMAP -- Route 17
  -- unconditionally, Route 16 only on the stretch past (13,5) -- so this has
  -- to run AFTER the callbacks, which is exactly where the ROM runs it
  -- (LoadMapObjects fires the callback; CheckUpdatePlayerSprite comes later
  -- in the same map-setup script).  Without it the Cycling Road let you walk.
  self:applyForcedBike()

  self:rebuildNeighbors()
  self:updateMapNameSign()
  Logger.info("map: %s at (%d,%d)", mapId, x, y)
  -- Route22Gate_Script rewrites wLastMap from the player's Y on entry
  -- too (not only on step), so a save/load mid-gate keeps exits correct
  self:syncLastMapRewrite()
end

-- InitMapNameSign, run on every map entry (warps and connection crossings
-- alike): remember this map's landmark, and pop the sign when it changed.
-- ANNOUNCING THE PLACE YOU HAVE JUST WALKED INTO.
--
-- Gen 2 keys this off a LANDMARK on the map plus the town map's landmark
-- table.  Gen 3 says it in the map header: a region-map SECTION number, and
-- bit 3 of the flag byte for whether to show the sign at all -- which is how
-- stepping out of a house does not re-announce the town, and how a gate
-- announces nothing.
--
-- Both halves were read out of the ROM and neither was ever looked at, so no
-- map in Hoenn announced itself.
function OverworldState:updateMapNameSignGen3()
  local def = self.map and self.map.def
  local section = def and def.regionMapSection
  if not (def and def.showMapName and section) then
    -- a map that shows no sign also does not re-arm: walking from a route
    -- into a building and back out must not announce the route twice
    self.mapNameSign = nil
    return
  end
  if section == self.signLandmark then return end
  self.signLandmark = section
  local names = (Game.data.constants or {}).gen3MapSections
  local name = names and names[section]
  if type(name) ~= "string" or name == "" then
    self.mapNameSign = nil
    return
  end
  self.mapNameSign = {
    name = Strings((name:gsub("[\n\f\v]", " "))),
    frames = MAP_NAME_SIGN_FRAMES,
  }
end

function OverworldState:updateMapNameSign()
  if GameVersion.isGen3() then return self:updateMapNameSignGen3() end
  if not GameVersion.isGen2() then return end
  local def = self.map and self.map.def
  local landmark = def and def.landmark
  -- .CheckNationalParkGate / the GATE environment test: a gate inherits no
  -- landmark, so walking through one never re-announces the route beyond it
  if def and def.environment == MAP_NAME_SIGN_GATE then landmark = nil end
  -- .CheckMovingWithinLandmark: same landmark, no sign (and no re-arm, so
  -- stepping out of a house does not re-announce the town)
  if landmark == self.signLandmark then return end
  self.signLandmark = landmark
  if not landmark or MAP_NAME_SIGN_SKIP[landmark] then
    self.mapNameSign = nil
    return
  end
  local landmarks = ((Game.data.field or {}).townMap or {}).landmarks
  local entry = landmarks and landmarks[landmark]
  local name = entry and entry.name
  if type(name) ~= "string" or name == "" then
    self.mapNameSign = nil
    return
  end
  -- Landmarks store two-line names with an embedded break; the sign has a
  -- single interior text row, so flatten it the way the Pokegear does
  self.mapNameSign = {
    name = Strings((name:gsub("[\n\f\v]", " "))),
    frames = MAP_NAME_SIGN_FRAMES,
  }
end

-- Neighbor maps drawn at the composed connection offsets: at least the
-- configured hop count out (the GB only ever streamed a 32px strip of
-- the single directly connected map -- home/overworld.asm .loadNewMap),
-- widened to everything the current view size can show so a full
-- zoom-out never runs past the rendered set.  Re-run whenever the view
-- grows (zoom/resize), not only on setMap.
--
-- Neighbors are built eagerly here.  A TileRenderer is now a light object --
-- the tile layer draws windowed to the camera, so nothing per-map is
-- constructed up front (see TileRenderer) -- so there is no build cost to
-- amortize and no prefetch race to lose at a seam.  That is what the old
-- one-per-frame streaming queue existed to hide, and it is gone.
-- How far out from the player the neighbour set has to reach, in world
-- pixels, as a HALF-EXTENT either side.
--
-- The flat view answers this for itself: half the visible world plus a tile
-- row of slack is exactly what a 160x144 screen can show past its own edge.
-- A 3D renderer cannot use that answer. A diorama camera pulled back over a
-- route sees several screens in every direction, and what is not in
-- `self.neighbors` is not merely undrawn -- it was never loaded, so the
-- renderer has no map there to mesh and falls back to its own border-block
-- apron. That is the wall of border tiles fencing in a route, and the
-- neighbour that only appears once you have crossed the seam: the set is
-- rebuilt around the new map on arrival, which is the first moment it
-- contains anything you were already looking at.
--
-- So a renderer that sees further says so, by setting `neighborReachW` /
-- `neighborReachH` on the world -- the same shape as `viewW`/`viewH`, and
-- for the same reason: the engine cannot infer another renderer's frustum,
-- and guessing a generous default would load half of Johto for the flat game
-- that never asked. Unset is today's behaviour exactly.
--
-- Widening this is not free -- every neighbour is a loaded Map and a spawned
-- ghost cast -- which is why it is a request from the thing doing the drawing
-- rather than a constant here.
function OverworldState:neighborReach()
  local vw, vh = Game.renderer:worldViewSize()
  local rw = math.floor(vw / 2) + 64
  local rh = math.floor(vh / 2) + 64
  local wantW = tonumber(self.neighborReachW)
  local wantH = tonumber(self.neighborReachH)
  if wantW and wantW > rw then rw = math.floor(wantW) end
  if wantH and wantH > rh then rh = math.floor(wantH) end
  return rw, rh, vw, vh
end

function OverworldState:rebuildNeighbors()
  local mapId = self.map.id
  self.neighbors = {}
  local hops = FieldDefaults.world(Game.data, "neighborHops") or NEIGHBOR_HOPS
  local reachW, reachH, vw, vh = self:neighborReach()
  self.neighborViewW, self.neighborViewH = vw, vh
  -- what the set was actually built for, so the update tick below can notice
  -- a renderer asking for more without re-deriving it
  self.neighborReachBuiltW, self.neighborReachBuiltH = reachW, reachH
  -- resident set the eviction pass must never touch: the current map plus
  -- every drawn neighbor
  local keep = { [mapId] = true }
  for _, n in ipairs(OverworldState.computeNeighbors(Game.data.maps, mapId,
                                                     hops, reachW, reachH)) do
    keep[n.id] = true
    local m = MapLoader.load(Game.data, n.id)
    table.insert(self.neighbors, { map = m, ox = n.ox, oy = n.oy })
  end
  -- bound resident memory: drop maps behind us that are neither current nor
  -- a drawn neighbor, releasing their window batch / border image / atlas
  MapLoader.trim(keep)

  -- visual-only NPCs on connected maps (survey zoom): same spawn filter
  -- as a real map entry, but they never join self.entities -- no sight
  -- lines, triggers, dialogue or player collision.  Instances are
  -- shared with the real-NPC pool, so positions carry across the seam.
  self.ghosts = {}
  for _, nb in ipairs(self.neighbors) do
    local peers = {}
    for _, obj in ipairs(nb.map.def.objects or {}) do
      if objectVisible(Game.save, nb.map.id, obj) then
        local npc = pooledNPC(self.npcPool, Game.data, nb.map.id, obj)
        table.insert(peers, npc)
        table.insert(self.ghosts,
                     { npc = npc, map = nb.map, ox = nb.ox, oy = nb.oy,
                       peers = peers })
      end
    end
  end
end

-- SGB overworld palette (engine/gfx/palettes.asm SetPal_Overworld):
-- towns use their own palette, routes PAL_ROUTE, interiors the town or
-- route they are in (wLastMap = our lastOutdoor), with tileset and
-- Elite Four special cases -- all of it field.palettes now.

-- one rung of the cascade: byMap, then byTileset, then byPrefix.  Returns
-- nil when the map matches nothing, which is what sends the lookup on to
-- the last-outdoor memory.
local function paletteLookup(palettes, mapId, tileset)
  local byMap = palettes.byMap
  if byMap and byMap[mapId] then return byMap[mapId] end
  local byTileset = palettes.byTileset
  if byTileset and tileset and byTileset[tileset] then return byTileset[tileset] end
  for _, row in ipairs(palettes.byPrefix or {}) do
    if row.prefix and mapId:find(row.prefix, 1, true) == 1 then return row.palette end
  end
  return nil
end

-- name -> name so the map.palette chain has a vanilla link to wrap
local function samePalette(name) return name end
local function sameTod(tod) return tod end

-- GetTimeOfDay (5:$4032) reads the GBC clock against .TimeOfDayTable:
-- < 4 NITE, < 10 MORN, < 18 DAY, else NITE.  Gen 1 has no clock at all, so
-- only Gen 2 consults the host one.
local function clockTimeOfDay()
  local hour = tonumber(os.date("%H")) or 12
  if hour < 4 then return "NITE" end
  if hour < 10 then return "MORNING" end
  if hour < 18 then return "DAY" end
  return "NITE"
end
-- Exposed on the module: the object filter is defined ABOVE this local and so
-- cannot see it, and both it and setMap need the raw clock rather than the
-- cached self.tod (see objectInTimeOfDay / the objectTod freeze in setMap).
OverworldState.clockTimeOfDay = clockTimeOfDay

-- The cartridge's MAPOBJECT_TIMEOFDAY bit for the hour on the clock right now.
function OverworldState.clockTimeOfDayBit()
  local period = todPeriodAt(tonumber(os.date("%H")) or 12)
  return (period and tonumber(period.bit)) or TOD_BITS.DAY
end

-- world.tod default: the Gen 2 clock, or always DAY on Gen 1.  A mod returns
-- "NIGHT", "MORNING", etc.; the result is cached on the overworld and handed
-- to map.palette as ctx.tod so palette swaps can key off the period.
-- Gen2 BG palettes are picked per time of day (EnvironmentColorsPointers), and
-- TileRenderer bakes the chosen row into the tileset atlas -- so the clock
-- rolling from DAY into NITE has to drop those atlases and rebuild the visible
-- map, the same way a COLORS change does.  No-op on Gen 1, and in the COLORS
-- modes that do not use the ROM's palettes at all.
function OverworldState:syncGen2Tod(tod)
  local PaletteFX = require("src.render.PaletteFX")
  if not PaletteFX.setGen2Tod(tod) then return end
  if not (GameVersion.isGen2() and PaletteFX.usesGen2BgPal()) then return end
  pcall(function()
    MapLoader.invalidateAll()
    if self.map and self.reloadMap then self:reloadMap(self.map.id, "tod") end
  end)
end

function OverworldState:timeOfDay()
  local tod = GameVersion.isGen2() and clockTimeOfDay() or (self.tod or "DAY")
  if not Runtime.wantsHook("world.tod") then
    if tod ~= self.tod then
      local previous = self.tod
      self.tod = tod
      if previous and Runtime.wants("world.tod_changed") then
        Runtime.emit("world.tod_changed",
          { tod = tod, previous = previous, mapId = self.map and self.map.id })
      end
    end
    self:syncGen2Tod(tod)
    return tod
  end
  local map = self.map
  local nextTod = Runtime.call("world.tod", sameTod, tod, {
    map = map,
    mapId = map and map.id,
    x = self.player and self.player.cellX,
    y = self.player and self.player.cellY,
    steps = self.todSteps or 0,
  })
  if type(nextTod) ~= "string" or nextTod == "" then nextTod = tod end
  if nextTod ~= tod then
    self.tod = nextTod
    if Runtime.wants("world.tod_changed") then
      Runtime.emit("world.tod_changed", {
        tod = nextTod, previous = tod, mapId = map and map.id,
      })
    end
  else
    self.tod = nextTod
  end
  self:syncGen2Tod(self.tod)
  return self.tod
end

function OverworldState:paletteNameFor(map)
  local palettes = FieldDefaults.field(Game.data, "palettes")
  local name = map.def.palette or paletteLookup(palettes, map.id, map.def.tileset)
  if not name then
    -- Interiors inherit the outdoor map they sit in. Before the player has
    -- been outdoors at all, that is wLastMap's zero-fill -- map 0,
    -- PALLET_TOWN -- and NOT the spawn: the vanilla spawn (REDS_HOUSE_2F)
    -- is itself an interior and would fall through to the ROUTE default.
    -- defaultHeal derives the same zero-fill map (wLastBlackoutMap shares
    -- the reasoning) and lets a total conversion redirect it.
    local boot = (Game.data.field and Game.data.field.boot) or {}
    local last = self.lastOutdoor and self.lastOutdoor.id
                 or require("src.core.SaveData").defaultHeal(boot).map
    local lastDef = last and Game.data.maps[last]
    name = (last and paletteLookup(palettes, last, lastDef and lastDef.tileset))
           or palettes.default
  end
  local tod = self:timeOfDay()
  if not Runtime.wantsHook("map.palette") then return name end
  return Runtime.call("map.palette", samePalette, name, map, { tod = tod })
end

-- UI-pass palette (text boxes and menus tint with the current map).  OG RED
-- resolves every name to the one global red BG palette inside PaletteFX.pal,
-- so this needs no mode-specific branch.
--
-- TalkToPikachu's framed frontpic is the one exception: pokeyellow
-- LoadOverworldPikachuFrontpicPalettes loads the map pal as slot 0 and
-- PAL_PIKACHU_PORTRAIT as slot 1, then ATTR_BLK's the 5x5 pic at
-- (7,6)-(11,10) onto slot 1 (engine/gfx/palettes.asm:345-391).  Without
-- that zone the pic wears the route/town palette and looks washed out.
function OverworldState:sgbPalettes()
  local PaletteFX = require("src.render.PaletteFX")
  local mapName = self:paletteNameFor(self.map)
  if self.emote and self.emote.pikaPic then
    local base = PaletteFX.pal(Game.data, mapName)
    if not base then return nil end
    local zones = { PaletteFX.whole(base) }
    local portrait = PaletteFX.pal(Game.data, "PIKACHU_PORTRAIT")
    if portrait then
      zones[#zones + 1] = PaletteFX.zone(portrait, 7, 6, 11, 10)
    end
    return zones
  end
  return PaletteFX.wholeNamed(Game.data, mapName)
end

-- World-pass palette zones in world-canvas pixels: each visible map
-- area keeps its own SGB palette (a deliberate step past the original,
-- which recolored the whole screen per map -- see the survey zoom
-- entry in docs/known-differences.md).  Border fill inherits the
-- current map's palette.
--
-- RED++ true overworld coloring does NOT go through this zone/shader
-- system at all: TileRenderer bakes real per-tile GBC colors straight into
-- a recolored tileset atlas (see TileRenderer's gbcAtlas), and
-- SpriteRenderer bakes sprites' OBP colors the same way, so the world
-- canvas is already final RGB by the time this runs. Returning an EMPTY
-- list here (when the current map has that baked atlas) skips the shader
-- entirely -- Renderer:endFrame's blit sees zoneList[1] == nil and falls
-- back to a plain, unshaded draw. Returning plain `nil` would NOT do this:
-- endFrame treats a nil worldZones as "no world-specific zones, reuse the
-- UI pass's zones" (sgbPalettes' whole-screen named-palette zone), which
-- would re-run the DMG shade-remap over already-true-color pixels using
-- an unrelated 4-color palette -- exactly the "colors are wrong" bug this
-- fixes.
function OverworldState:sgbWorldZones()
  local PaletteFX = require("src.render.PaletteFX")
  if PaletteFX.usesGbcPack() and self.map.renderer and self.map.renderer.gbcAtlas then
    return {}
  end
  -- A WORLD THAT IS ALREADY IN COLOUR TAKES NO COLORIZATION.
  --
  -- The line above is the Gen 1/Gen 2 answer to the same question: under
  -- ADVANCED those maps bake the pack into their atlas, so the screen-space
  -- pass would colour an already-coloured picture and is skipped.  A Gen 3
  -- map bakes nothing -- its metatile sheets come out of the cartridge in
  -- full colour -- so `gbcAtlas` is false and it fell straight through to the
  -- line below, which publishes a WHOLE-SCREEN zone painted from Red's pack.
  -- Emerald's tiles then went through the four-shade remap and Hoenn came out
  -- green.
  --
  -- Except in the modes that ask for a Game Boy on purpose.  OG, OG INV and
  -- CLASSIC are "make this look like the hardware", and a player who picks
  -- one has asked for the remap; taking it away there would make three of the
  -- seven settings do nothing on this cartridge.
  if not PaletteFX.monoMode() and self.map.renderer
      and self.map.renderer.isTrueColor and self.map.renderer:isTrueColor() then
    return {}
  end
  local base = PaletteFX.pal(Game.data, self:paletteNameFor(self.map))
  if not base then return nil end
  local vw, vh = Game.renderer:worldViewSize()
  local cam = self.camera
  local zones = { { colors = base, x = 0, y = 0, w = vw, h = vh } }
  for _, nb in ipairs(self.neighbors) do
    local colors = PaletteFX.pal(Game.data, self:paletteNameFor(nb.map))
    if colors then
      table.insert(zones, { colors = colors,
                            x = math.floor(nb.ox - cam.x),
                            y = math.floor(nb.oy - cam.y),
                            w = nb.map.def.width * blockPx(nb.map.def),
                            h = nb.map.def.height * blockPx(nb.map.def) })
    end
  end
  return zones
end

-- wMapPalOffset, the one piece of state both halves of the darkness read:
-- drawWorld arms PaletteFX.DARK_BGP off self.dark for the shade-remapped
-- modes, and PaletteFX.setDarkWorld feeds the bakes the hardware-colour modes
-- do instead of shading (tileset atlas, sprite sheets) plus their cache keys.
-- A bake cannot be re-shaded in place, so a change there rebuilds every
-- resident map -- every dark floor, not just this one, since FLASH lights them
-- all (#383).
--
-- PaletteFX.bakesDarkness, not usesGbcPack: a Gen 2 game bakes the DARKNESS
-- palette row into its atlas in EVERY hardware-colour mode, so asking only
-- about ADVANCED left FLASH doing nothing whatsoever under SGB -- the default
-- -- because the atlas on screen still had the darkness baked into it.
function OverworldState:setDark(on)
  on = on and true or false
  self.dark = on
  if PaletteFX.setDarkWorld(on) and PaletteFX.bakesDarkness() and self.map then
    MapLoader.invalidateAll()
    self:reloadMap(self.map.id, "dark")
  end
end

function OverworldState:npcByIndex(index)
  for _, n in ipairs(self.npcs) do
    if n.def.index == index then return n end
  end
  return nil
end

-- Bike riding allowlist (field.bikeRiding, from bike_riding_tilesets.asm
-- + IsBikeRidingAllowed's map exceptions); BagMenu's mount check reads
-- the same table.
function OverworldState:bikeAllowed(mapId)
  if GameVersion.isGen2() then
    -- BikeFunction.CheckEnvironment (03:$512E): TOWN, ROUTE, CAVE or GATE.
    -- Gen1's bike_riding_tilesets list names no Gen2 tileset, so consulting
    -- it here refused the bike on every map in the game.
    local def = Game.data.maps[mapId]
    local env = def and def.environment
    return env == 1 or env == 2 or env == 4 or env == 6
  end
  -- ...AND EMERALD PUTS IT IN THE MAP HEADER.  IsBikingAllowedByMap is one
  -- bit -- gMapHeader.allowCycling -- and 165 maps in Hoenn set it.  The
  -- Gen 1 path below is a list of Kanto map ids and Kanto tileset names, so
  -- consulting it here refused the bike on every map in the region, which is
  -- the same failure the Gen 2 arm above was written to fix.
  if GameVersion.isGen3() then
    local def = Game.data.maps[mapId]
    return (def and def.allowCycling) == true
  end
  local br = Game.data.field.bikeRiding
  if not br then return Map.isOutdoor(self.map.def) end
  for _, m in ipairs(br.maps) do
    if m == mapId then return true end
  end
  for _, t in ipairs(br.tilesets) do
    if t == self.map.def.tileset then return true end
  end
  return false
end

-- The battle transition's dungeon wipe uses the explicit map lists in
-- data/maps/dungeon_maps.asm (field.dungeonTransitionMaps): singles plus
-- inclusive map-id ranges -- faithful to the original's omissions
-- (Victory Road 2F/3F, the Rocket Hideout, Diglett's Cave, ... miss out).
function OverworldState:isDungeonTransitionMap()
  local dm = Game.data.field.dungeonTransitionMaps
  if not dm then return false end
  for _, m in ipairs(dm.maps) do
    if m == self.map.id then return true end
  end
  local idx = self.map.def.index
  for _, r in ipairs(dm.ranges) do
    local first = Game.data.maps[r.first]
    local last = Game.data.maps[r.last]
    if first and last and idx >= first.index and idx <= last.index then
      return true
    end
  end
  return false
end

-- Start a battle behind the into-battle transition: flash, then the
-- wipe picked by trainer/level/dungeon (GetBattleTransitionID).
-- The entry wipe, as its own overridable step.
--
-- Split out of pushBattle so a mod can WRAP the transition without having to
-- reimplement everything around it.  That is not hypothetical: a mod that
-- fights on the live 3D map has to suppress the wipe, because the wipe exists
-- to hide the world being replaced and there the world is the thing it is
-- there to show.  STADIUM2_OVERWORLD_MODELS wraps exactly this name and
-- signature (lib/OverworldBattle.lua) -- with no such method the hook never
-- installed, its in-world battle never began, and the fight fell back to the
-- flat scene with nothing logged.
--
-- Returns true when a transition was pushed.  **false means "no wipe -- push
-- the battle yourself"**, which is what a wrapper returns when it has taken
-- responsibility for the presentation.  `onDone` overrides what happens when
-- the wipe finishes; by default that is pushing the battle.
function OverworldState:pushBattleTransition(battle, opts, onDone)
  local BattleTransition = require("src.render.BattleTransition")
  local lead
  for _, mon in ipairs(Game.save.party) do
    if mon.hp > 0 then lead = mon break end
  end
  local enemyLevel = battle and battle.enemy and battle.enemy.mon
    and battle.enemy.mon.level or 0
  -- The fade back in from white on the way out is BattleState:finish()'s
  -- job now -- the one choke point every battle passes through on exit,
  -- guaranteed regardless of which caller pushed the battle -- so this
  -- function only owns the entry wipe.
  Game.stack:push(BattleTransition.new(Game, onDone or function()
    Game.stack:push(battle)
  end, {
    trainer = battle and battle.kind == "trainer",
    stronger = lead ~= nil and enemyLevel >= lead.level + 3,
    dungeon = self:isDungeonTransitionMap(),
    tutorial = opts and opts.tutorial or nil,
    contest = opts and opts.contest or nil,
    safari = opts and opts.safari or nil,
  }))
  return true
end

function OverworldState:pushBattle(battle, opts)
  -- the battle theme starts with the wipe, not after it
  -- (audio/play_battle_music.asm runs before the transition), and it plays
  -- whether or not anything took the transition over
  if battle and battle.computeMusicKind then
    require("src.core.Music").playBattle(Game.data, battle:computeMusicKind())
  end
  if self:pushBattleTransition(battle, opts) == false then
    -- something is presenting this fight itself and skipped the wipe; the
    -- battle still has to go on the stack, or the player is left standing in
    -- the overworld with the battle music playing
    Game.stack:push(battle)
  end
end

-- -------------------------------------------------------------------------
-- update
-- -------------------------------------------------------------------------

-- Queue a script for a map's onEnter hook to run once it is safe to.  A
-- map load (setMap -> onEnter) can happen mid-warp, while the triggering
-- warp command's runner is still suspended-alive; starting a runner there
-- would trip ScriptRunner:run's assert(not isRunning()).  So onEnter stashes
-- the script here and update() drains the FIFO head once the world is
-- idle, one script per idle frame.
-- WHEN THE PLAYER IS SOMEWHERE ELSE, WHICH IS NOT THE SAME AS "TOOK A STEP".
--
-- Reported from play: "areas that push me back like the little girl blocking
-- the route, or birches event or the sandstorm when i dont ahve the glasses
-- can be bypassed if it moves me back and i walk back into it enough".  They
-- could, and every one of those is the same shape: a coord event fires, its
-- script walks the player back off the cell, and the player walks straight in
-- again -- through it this time.
--
-- The coord side remembers which of its rows have fired AT THE CELL THE
-- PLAYER IS ON, so a row cannot run twice for one visit.  It learned about
-- moves from onStep, and onStep is deliberately not called for a SCRIPTED
-- step -- or a cutscene would set off every trigger it walks the player
-- across.  So the walk-BACK was invisible to it: the memory still said "you
-- are on that cell and the row has fired", and the second attempt walked
-- through the fence.
--
-- A counter bumped whenever the player's cell changes, however it changed,
-- is what the memory needs instead of a pair of coordinates.  Warps, ledge
-- hops, scripted walks and ordinary steps all move the player and all bump
-- it; standing still does not.
function OverworldState:noteCellChange()
  local p = self.player
  if not (p and p.cellX and p.cellY) then return end
  if self.lastCellX ~= p.cellX or self.lastCellY ~= p.cellY then
    self.lastCellX, self.lastCellY = p.cellX, p.cellY
    self.cellSerial = (self.cellSerial or 0) + 1
  end
end

-- ROUTE 110'S RUN IS TIMED IN FRAMES, so something has to count them.
--
-- The cartridge subtracts two reads of the vblank counter: `elapsed =
-- gMain.vblankCounter1 - start` (gSpecials[231], 0137E6C).  There is no such
-- counter here, so the run carries its own and the field advances it -- which
-- is the same number, arrived at the same way.  Only while a run is actually
-- on: special 229 starts one and 231 and 232 end it.
function OverworldState:tickCyclingChallenge()
  local run = Game.save and Game.save.gen3Cycling
  if type(run) ~= "table" or not run.active then return end
  run.frames = (run.frames or 0) + 1
end

-- A SCRIPT THAT CANNOT FINISH IS A FROZEN GAME, AND IT LOOKS EXACTLY LIKE ONE.
--
-- Reported from play: "game also freezes after being teleported back to the
-- gym after he catches ralts".  The Wally tutorial's script walks the player
-- home and hands over to the gym's own scene, and somewhere in that handover
-- the runner parks and never wakes: the map draws, the music plays, and no
-- button does anything for the rest of the session.  `runner:isRunning()`
-- gates every input frame in this file, so a coroutine yielded with nothing
-- left to wake it is a total loss with no message.
--
-- The cartridge cannot reach this state -- its script context is torn down by
-- the map change -- so a port that can must at least be able to SAY so.  What
-- counts as progress is everything that legitimately parks a script:
--
--   * a frame wait counting down, or a per-frame poll being asked
--   * a scripted walk in flight, or the player mid-step
--   * a movement wait that is still watching for its walker
--   * anything on top of the field -- a text box, a battle, a menu, a
--     transition -- because the field does not update underneath those, so
--     this function is not even called
--
-- With none of those true for SIX SECONDS the script is not waiting for
-- anything: it is stranded.  That is said out loud, once, with the map on it;
-- and after a further six the runner is put down so the player has their game
-- back.  Recovering is not a fix and is not meant to look like one -- the log
-- line is the fix's starting point -- but a stranded cutscene should cost a
-- scene, not a save.
local STUCK_WARN_FRAMES = 360        -- six seconds at sixty
local STUCK_GIVE_UP_FRAMES = 720

function OverworldState:watchStuckScript()
  local runner = self.runner
  if not runner:isRunning() or self.transitioning
     or runner.waitingFrames or runner.waitingCheck
     or #self.scriptMoves > 0
     or (self.player and self.player.moving)
     or (runner.ctx and runner.ctx.g3Waiting
         and runner.ctx.g3Waiting.waiting) then
    self.stuckFrames = nil
    return
  end
  self.stuckFrames = (self.stuckFrames or 0) + 1
  if self.stuckFrames == STUCK_WARN_FRAMES then
    local ctx = runner.ctx or {}
    local source = ctx.source or {}
    Logger.warn("a script on %s has been parked for %d frames with nothing "
                .. "left to wake it (last row %s, source %s.%s) -- this is "
                .. "the shape a freeze takes; it will be put down in another "
                .. "%d frames",
                tostring(self.map and self.map.id), self.stuckFrames,
                tostring(runner.lastRow or "?"),
                tostring(source.mapId or "?"), tostring(source.hook or "?"),
                STUCK_GIVE_UP_FRAMES - STUCK_WARN_FRAMES)
  elseif self.stuckFrames >= STUCK_GIVE_UP_FRAMES then
    Logger.warn("...putting it down and giving the player back control on %s",
                tostring(self.map and self.map.id))
    local ctx = runner.ctx
    runner.co = nil
    runner.waitingFrames = nil
    runner.waitingCheck = nil
    self.stuckFrames = nil
    if ctx then
      ctx.g3Waiting = nil
      local ok, Gen3Commands = pcall(require, "src.script.Gen3Commands")
      if ok and Gen3Commands and Gen3Commands.restoreFade then
        pcall(Gen3Commands.restoreFade, ctx)
      end
    end
  end
end

function OverworldState:queueScript(script, extra)
  local queue = self.pendingScripts
  if not queue then
    queue = {}
    self.pendingScripts = queue
  end
  queue[#queue + 1] = { script = script, extra = extra,
                        mapId = self.map and self.map.id }
  -- a runaway-loop tripwire, not a hard cap
  if #queue > 16 then
    Logger.warn("queueScript: %d scripts pending on %s",
                #queue, tostring(self.map and self.map.id))
  end
end

function OverworldState:drainPendingScripts()
  local queue = self.pendingScripts
  -- `not self.player.moving` matters as much as the other three.  On the frame
  -- a warp transition finishes, `transitioning` is cleared by the transition's
  -- own completion callback -- which runs LATER in update() than this drain --
  -- so the first frame this could fire is the frame AFTER handleInput has
  -- already had a turn.  A player walking in with UP held therefore got one
  -- free step before the map's scene script started, and the scripted walk
  -- then ran from a cell one tile further on.
  --
  -- Elm's Lab is where that shows: ElmsLabMeetElmScene is `sdefer
  -- ElmsLabWalkUpToElmScript`, and Crystal's ElmsLab_WalkUpToElmMovement is
  -- exactly 7 steps up from the door at (4,11) to (4,4), where the callback has
  -- put ELM at (3,4).  With the free step it was 8, and the player finished one
  -- tile NORTH of Elm facing an empty wall.
  --
  -- The cartridge cannot do this: RunSceneScript (engine/overworld/events.asm)
  -- runs the scene script and its deferred target during map setup, before
  -- JoypadOverworld is polled even once.
  if queue and queue[1] and not self.transitioning
     and not self.runner:isRunning() and #self.scriptMoves == 0
     and not (self.player and self.player.moving) then
    local pending = table.remove(queue, 1)
    self.runner:run(pending.script, pending.extra)
  end
end

-- Gen2 objects are spawned/despawned by their event flag, and a script that
-- sets one (taking a starter ball, the Elm's Lab theft) has to take effect
-- before the next map load -- so re-run the spawn filter once the script
-- that moved the flag has finished.
--
-- `only` restricts the pass to ONE object def, which is what `appear` and
-- `disappear` need.  Script_appear/Script_disappear touch exactly the object
-- they name (UnmaskCopyMapObjectStruct / DeleteObjectStruct); they do not
-- re-derive anyone else's visibility.  Sweeping the whole map on every
-- disappear is what broke the Rocket base boss scene: the script sets Lance's
-- own event flag before the fade (`setevent EVENT_TEAM_ROCKET_BASE_B2F_LANCE`),
-- which the ROM deliberately lets a LIVE object ignore -- and then the very
-- next `disappear` of an unrelated grunt re-ran this filter, saw Lance's flag
-- set, and deleted him.  The matching `clearevent` a few rows later does not
-- re-spawn anything (setevent/clearevent never do, by design), so Lance was
-- simply absent for the whole post-battle scene: every turnobject and
-- applymovement aimed at him did nothing, and he turned up on the next map
-- load wherever the respawn tables happened to put him.  The full sweep is
-- still correct for what it models -- LoadMapObjects, driven by
-- refreshmap/reloadmap -- so it stays available with `only` unset.
-- `entities` IS A DERIVED LIST: the player, then every live NPC.
--
-- It is what the draw loops walk; `npcs` is what collision, talking and the
-- script runner walk. Nothing has ever enforced that the two agree -- setMap
-- builds `entities` from `npcs` once, and after that six separate places keep
-- them in step by hand, plus whatever a mod does with `world.entities`, which
-- both of the voxel mods hold directly.
--
-- Lose an NPC from `entities` alone and it does not error, it does not warn,
-- and it does not go away: it stands there invisible, still solid, still
-- talking when you press A into it. That is the Elite Four report -- beat
-- Will, he stops being drawn, and you can still walk up to nothing and get
-- his post-battle line.
--
-- So the invariant gets asserted in one place instead of maintained in seven.
-- Anything in `entities` that is NEITHER the player NOR a live NPC is kept, in
-- order, after them: a mod's own spawns live in that list too (the roaming
-- wild Pokemon are entities nothing here owns), and rebuilding must not
-- quietly delete somebody else's actor to fix ours.
function OverworldState:rebuildEntities()
  if not self.player then return end
  local mine = {}
  for _, npc in ipairs(self.npcs) do mine[npc] = true end
  local extras = {}
  for _, e in ipairs(self.entities or {}) do
    if e ~= self.player and not mine[e] then extras[#extras + 1] = e end
  end
  local out = { self.player }
  for _, npc in ipairs(self.npcs) do out[#out + 1] = npc end
  for _, e in ipairs(extras) do out[#out + 1] = e end
  self.entities = out
end

-- The same rebuild, but it says something the first time it has to repair a
-- live NPC that had fallen out of the draw list. A silent self-heal would fix
-- the symptom and bury the cause; this names the actor, once per session, so
-- the next report arrives with the culprit attached.
function OverworldState:reassertEntities(why)
  if not self.player then return end
  local present = {}
  for _, e in ipairs(self.entities or {}) do present[e] = true end
  local missing
  for _, npc in ipairs(self.npcs) do
    if not present[npc] then missing = missing or npc end
  end
  self:rebuildEntities()
  if missing and not OverworldState._entityDesyncLogged then
    OverworldState._entityDesyncLogged = true
    Logger.warn("entity list desync repaired (%s): %s was in npcs but not "
                .. "entities -- it would have been invisible but still solid",
                tostring(why or "?"), tostring(missing.id))
  end
end

function OverworldState:syncObjectVisibility(only)
  if not (self.map and self.map.def) then return end
  local mapId = self.map.id
  local wanted = {}
  local scope = only and { only } or (self.map.def.objects or {})
  for _, obj in ipairs(scope) do
    if objectVisible(Game.save, mapId, obj) then
      wanted[mapId .. "_obj_" .. obj.index] = obj
    end
  end
  -- With `only` set, everything outside the scope must be left exactly as it
  -- is, so mark the rest wanted-as-is rather than letting the removal pass
  -- below treat them as unwanted.
  --
  -- BY ID, NOT BY TABLE IDENTITY, and that was a real bug rather than a
  -- tidy-up.  Reported from play: "on route 119 after defeating may shes
  -- still standing there even though she gets on a bike and rides north to
  -- fortree."  She was, and so was every other cutscene actor a script had
  -- ever moved the HOME of.
  --
  -- `objectHome` hands pooledNPC a COPY of the object record whenever the
  -- save carries a `setobjectxyperm` for it -- it has to, because it rewrites
  -- x and y and the map definition is shared.  So an object placed before it
  -- is spawned ends up with an npc whose `def` is that copy, and `npc.def ~=
  -- only` was then true for the very object being hidden: it went into `keep`
  -- and the removal pass stepped over it.
  --
  -- Route 119's rival scene is exactly that shape and in that order:
  --
  --     setobjectxyperm 16, 25, 32     @ beside whichever tile you triggered on
  --     addobject 16                   @ ...so this one is built from a copy
  --     trainerbattle
  --     removeobject 16                @ ...and this could never match it
  --
  -- Seven maps in Hoenn place-perm and later remove the same object, over
  -- twenty-three objects between them, and every one of them was stuck on
  -- screen for good.  The id is what `wanted` is keyed by two lines above,
  -- so keying this the same way makes the two halves agree by construction.
  local keep = nil
  if only then
    -- spelled the way NPC.new spells it, so the two cannot drift
    local onlyId = ("%s_obj_%d"):format(mapId, only.index or -1)
    keep = {}
    for _, npc in ipairs(self.npcs) do
      if npc.id ~= onlyId then keep[npc.id] = true end
    end
  end
  self.npcResumeCell = self.npcResumeCell or {}
  for i = #self.npcs, 1, -1 do
    local npc = self.npcs[i]
    if keep and keep[npc.id] then
      -- out of scope for a targeted appear/disappear
    elseif not wanted[npc.id] then
      -- Remember where it actually stood.  A Gen2 `disappear` is not a
      -- despawn-and-forget: a cutscene routinely hides an object, walks the
      -- player, and shows it again, and the ROM's struct keeps its coordinates
      -- the whole time.  Without this the re-show snapped it back to its
      -- object_event tile and every following applymovement ran from the wrong
      -- origin -- the Gen1 path has recorded this since npcResumeCell was
      -- added (see toggleObject in src/script/Commands.lua); the Gen2 path
      -- never did.
      local key = objectToggleKey(npc.def)
      if key then
        self.npcResumeCell[key] =
          { x = npc.cellX, y = npc.cellY, facing = npc.facing }
      end
      table.remove(self.npcs, i)
      for j = #self.entities, 1, -1 do
        if self.entities[j] == npc then table.remove(self.entities, j) end
      end
    else
      wanted[npc.id] = nil
    end
  end
  for _, obj in pairs(wanted) do
    local npc = pooledNPC(self.npcPool, Game.data, mapId, obj)
    npc.frozen = false
    -- Where does it come back?  `moveobject` first (an explicit relocation the
    -- script asked for), then wherever it was when it went away, then its
    -- object_event tile.  Script_moveobject writes the loaded map's object
    -- struct, so the disappear / moveobject / appear / applymovement idiom --
    -- the Radio Tower director walking in after the last Rocket executive,
    -- Kurt arriving at Slowpoke Well, most cutscene walk-ons -- depends on the
    -- new cell surviving the respawn.  It did not: the object reappeared at
    -- its map-def tile and then walked from there, which puts it through
    -- scenery or off the visible area entirely (an actor with dialogue and no
    -- body).
    local key = objectToggleKey(obj)
    local at = key and ((self.npcPlacement and self.npcPlacement[key])
                        or self.npcResumeCell[key])
    if at then
      npc.cellX, npc.cellY = at.x, at.y
      npc.px, npc.py = at.x * 16, at.y * 16
      npc.facing = at.facing or npc.facing
    end
    -- A pooled entity is reused, so it can still be carrying the half-finished
    -- step it was hidden in the middle of.  Land it on its cell.
    npc.moving = false
    npc.progress = 0
    npc.targetX, npc.targetY = nil, nil
    self.npcs[#self.npcs + 1] = npc
    self.entities[#self.entities + 1] = npc
  end
  -- Every spawn and despawn above touched both lists, and so does every other
  -- site in this file -- and the Elite Four still ended up drawn out of one of
  -- them. This runs at the one point every visibility change passes through,
  -- so whatever did it, the actor is back in the draw list before the frame.
  self:reassertEntities("syncObjectVisibility")
end

-- Start a background script in one of the bounded parallel slots (09
-- §4.6); overflow waits FIFO-style behind the slots.  rowsOrRef is a row
-- array or "MAP_ID/name" naming a map_scripts `scripts` entry.
local PARALLEL_SLOTS = 4

function OverworldState:startParallel(rowsOrRef, extra)
  local rows = rowsOrRef
  if type(rowsOrRef) == "string" then
    local MapScripts = require("src.script.MapScripts")
    local mapId, name = rowsOrRef:match("^([^/]+)/(.+)$")
    rows = mapId and MapScripts.namedScript(mapId, name)
    if not rows then
      Logger.warn("run_parallel: no script '%s'", tostring(rowsOrRef))
      return
    end
    -- a named entry belongs to its contribution: a caller with no
    -- attribution of its own runs it as the owner
    if not (extra and extra.source) then
      local source = MapScripts.namedSource(mapId, name)
      if source then
        extra = extra or {}
        extra.source = source
      end
    end
  end
  local queue = self.parallelQueue
  if not queue then
    queue = {}
    self.parallelQueue = queue
  end
  queue[#queue + 1] = { rows = rows, extra = extra }
  if #queue > 16 then
    Logger.warn("run_parallel: %d scripts waiting for a slot", #queue)
  end
end

function OverworldState:killParallel(runner)
  runner.co = nil
  for i, live in ipairs(self.parallelRunners or {}) do
    if live == runner then
      table.remove(self.parallelRunners, i)
      break
    end
  end
  for entity, holder in pairs(self.npcMoveLocks or {}) do
    if holder == runner then self.npcMoveLocks[entity] = nil end
  end
end

-- Parallel runners tick after the main runner and never touch the input
-- lockout: isRunning() checks consult only self.runner, exactly as
-- before.  Dead runners free their slot and their NPC move locks.
function OverworldState:updateParallel()
  local pool = self.parallelRunners
  if not pool then return end
  for i = #pool, 1, -1 do
    if not pool[i]:isRunning() then
      self:killParallel(pool[i])
    end
  end
  local queue = self.parallelQueue
  while queue and queue[1] and #pool < PARALLEL_SLOTS do
    local next_ = table.remove(queue, 1)
    local runner = ScriptRunner.new(Game, self)
    runner.parallel = true
    pool[#pool + 1] = runner
    runner:run(next_.rows, next_.extra)
  end
  for _, runner in ipairs(pool) do runner:update() end
end

-- CheckSpecialPhoneCall (36:$413E) runs off the overworld's step loop, not
-- the script that armed the call: `specialphonecall` only writes
-- wSpecialPhoneCallID, and the row's condition -- SpecialCallOnlyWhenOutside
-- for Elm's post-Falkner egg call -- decides when the POKeGEAR actually rings.
-- Poll it here, on an idle frame, and hand the caller script to the same
-- pending-script FIFO a warp cutscene uses.
function OverworldState:checkSpecialPhoneCall()
  if not GameVersion.isGen2() then return end
  if Game.save.g2SpecialCall == nil then return end
  if self.transitioning or self.runner:isRunning() or #self.scriptMoves > 0 then
    return
  end
  if self.player and (self.player.moving or self.player.targetX) then return end
  local outside = self.map and self.map.def and Map.isOutdoor(self.map.def)
  local Gen2Commands = require("src.script.Gen2Commands")
  local caller, script =
    Gen2Commands.pendingSpecialCall(Game.data, Game.save, outside)
  if not script then return end
  Game.save.g2SpecialCallActive = Game.save.g2SpecialCall
  Game.save.g2SpecialCall = nil
  -- wCurCaller, which the caller script's `readvar 23` reads back
  Game.save.g2CurCaller = caller
  self:queueScript(script, { phoneCaller = caller,
    onDone = function() Game.save.g2CurCaller = nil end })
end

-- CheckPhoneCall (36:$4074): the random incoming call, rolled on every step
-- the player finishes off a warp tile.  Gen2Commands.rollIncomingCall carries
-- the ROM's own gating -- the receive-call delay, the one-in-two coin flip, the
-- map's phone-service nibble, and the sample of registered contacts whose
-- time-of-day mask covers now and who are not on this map.
--
-- The play clock stands in for the ROM's day/hour/minute countdown: both are
-- "in-game minutes since the last call", and the port has no separate RTC to
-- keep them apart.
function OverworldState:checkIncomingPhoneCall()
  if not GameVersion.isGen2() then return end
  if self.transitioning or self.runner:isRunning() or #self.scriptMoves > 0 then
    return
  end
  if Game.save.g2SpecialCall ~= nil then return end
  if self.pendingScripts and self.pendingScripts[1] then return end
  local p = self.player
  if not (p and self.map) then return end
  -- CheckStandingOnEntrance: no call while the player is on a door or warp
  if self.map:warpAtCell(p.cellX, p.cellY) then return end
  local Gen2Commands = require("src.script.Gen2Commands")
  local minutes = math.floor((tonumber(Game.save.playTime) or 0) / 60)
  local id, script = Gen2Commands.rollIncomingCall(
    Game.data, Game.save, self.map.def, self:timeOfDay(), minutes, false)
  if not script then return end
  Game.save.g2CurCaller = id
  -- Phone_StartRinging (36:$4337) before the script, Phone_CallEnd after it
  pcall(function() require("src.core.Sound").play(Game.data, "Call") end)
  self:queueScript(script, { phoneCaller = id, onDone = function()
    Game.save.g2CurCaller = nil
    pcall(function() require("src.core.Sound").play(Game.data, "Hang_Up") end)
  end })
end

function OverworldState:update(dt)
  -- `earthquake <n>` (Script_earthquake -> EarthquakeMovement 25:$725D):
  -- the BG jolts while the sprites stay put, which is exactly what bgShakeY
  -- already feeds into draw().
  -- the weather's own clock; see drawFieldWeather
  self.weatherFrame = (self.weatherFrame or 0) + 1
  -- ...and the cracked floor's, which runs on the clock rather than on the
  -- steps because that is what makes a step's length decide the fall
  self:tickCrackedFloor()
  -- ...and the logs', which settle and then go under while you stand there
  self:tickPacifidlogLogs()
  -- ...and the PC's screen, which blinks itself on when you use one
  self:tickPcScreen()
  if self.quakeFrames then
    self.quakeFrames = self.quakeFrames - 1
    self.bgShakeY = (math.floor(self.quakeFrames / 2) % 2 == 0) and 2 or -2
    if self.quakeFrames <= 0 then
      self.quakeFrames = nil
      self.bgShakeY = 0
    end
  end
  -- ...and Lilycove's lift, which is the same idea with the cartridge's own
  -- numbers: a PIXEL rather than two, every third frame rather than every
  -- second, and counted in FLIPS rather than frames -- so a trip of four
  -- floors rocks longer than a trip of one without rocking any faster.  See
  -- Gen3Commands.SPECIALS[276]; the script is parked on `waitstate` until the
  -- count runs out.
  local lift = self.gen3Elevator
  if lift then
    lift.frames = (lift.frames or 0) + 1
    if lift.frames >= (lift.period or 3) then
      lift.frames = 0
      lift.shakes = (lift.shakes or 0) - 1
      lift.up = not lift.up
      self.bgShakeY = lift.up and (lift.amplitude or 1)
                      or -(lift.amplitude or 1)
      if lift.shakes <= 0 then
        self.gen3Elevator = nil
        self.bgShakeY = 0
        if lift.resume then lift.resume() end
      end
    end
  end
  -- deferred cutscene launch (see queueScript): run a queued script only
  -- once the triggering warp's transition has finished, its runner has gone
  -- dead, and no scripted walk is mid-step.  This is how the HALL_OF_FAME
  -- room cutscene starts a frame after the Champions Room warp completes.
  self:drainPendingScripts()
  -- ...AND REDRAW WHATEVER IT CHANGED.
  --
  -- `setmetatile` writes a block and says nothing about the screen; the
  -- cartridge redraws with DrawWholeMapView (special 145) once a script has
  -- finished changing things, and that is still what a script does here.  But
  -- a MAP-SETUP callback has nothing to redraw with: on the cartridge it runs
  -- while the map is being built, so its changes are simply what gets drawn.
  -- Queued, it runs a frame or two after the map is on screen, and its
  -- changes were never drawn at all -- which is how a Regi chamber's door
  -- could be shut and still look open, and how the door of every room whose
  -- ON_LOAD closes it looked.  Map:setBlock raises the flag; one rebuild a
  -- frame at most, and only when something actually moved.
  if self.map and self.map.blocksDirty then
    self.map.blocksDirty = nil
    self:redrawBlocks(self.map)
  end
  -- THE MAP'S FRAME TABLE, asked here because that is what its name means.
  --
  -- Gen 3 maps carry two var-gated tables and they are not the same thing:
  -- ON_WARP_INTO_MAP runs once as the map is entered, ON_FRAME_TABLE is
  -- re-asked on the field's frame until a row matches.  Running the frame
  -- table only on entry, through the deferred queue, put its var write one
  -- frame behind the arrival step -- and on Route 101 the arrival step IS
  -- the trigger, so Birch never got chased.
  --
  -- ...BUT NOT BEFORE THE MAP'S OWN ENTRY SCRIPT HAS RUN.  A map's
  -- ON_TRANSITION is QUEUED by setMap and the queue deliberately will not
  -- drain while `transitioning` is true, so during a warp fade the entry
  -- script has not run yet -- and this hook was gated on nothing but the
  -- runner, so the frame table was asked with the map's vars still holding
  -- whatever the last map left in them.
  --
  -- Sootopolis Gym is the case, and it is a bad one.  Its ON_TRANSITION is
  -- `setvar $4022, 1` and its frame table's last row is `$4022 == 0 ->
  -- lockall / applymovement / playse / warphole 15 1` -- the cutscene where
  -- the ice gives way and you drop to the floor below.  The setvar exists for
  -- exactly one reason: so that row cannot match on arrival.  Asked during the
  -- fade it matched every time, and walking through the gym door dropped the
  -- player straight through the floor without touching the ice.
  --
  -- Two maps in Hoenn have a frame row that matches the value their own entry
  -- script is about to overwrite; the cartridge cannot reach either, because
  -- map setup runs ON_TRANSITION before the field runs a single frame.
  if not self.runner:isRunning() and not self.transitioning
     and not (self.pendingScripts and self.pendingScripts[1]) then
    local frameHooks = mapScripts.get(self.map and self.map.id)
    if frameHooks and frameHooks.onFrame then
      frameHooks.onFrame(Game, self)
    end
    -- ...AND THE MAP'S SETUP DECIDES THE WEATHER, which is the last thing a
    -- cartridge map load does (DoCurrentWeather).
    --
    -- Reported from play: "the area raining volcanic ash doesn't have the
    -- weather effects".  It does not, and the reason is a whole class of
    -- weather this port could not see.  A map's ON_TRANSITION is part of its
    -- LOAD, and eleven scripts in Hoenn set the weather from one without ever
    -- calling `doweather` -- because on the cartridge they do not have to:
    -- the load applies whatever the setup left in the save.
    --
    -- Route 113 is the case Cedric hit.  Its header says SUNNY; its
    -- ON_TRANSITION reads the player's x and sets VOLCANIC_ASH only between
    -- 19 and 84, which is why the ash falls over the middle of the route and
    -- not at either end.  Nothing applied it, so the route stood in clear
    -- air.  Routes 119 and 123 are the same shape through a special.
    --
    -- SCOPED TO THE LOAD.  A `setweather` during PLAY still waits for its
    -- `doweather`, which is what makes a scene's rain fade in on the scene's
    -- beat instead of the instant a var flips.
    if self.gen3MapWeatherPending then
      self.gen3MapWeatherPending = nil
      if Game.save then Game.save.gen3WeatherActive = Game.save.gen3Weather end
      self:logGen3Weather()
    end
  end
  self:noteCellChange()
  self:tickCyclingChallenge()
  self:watchStuckScript()
  local scriptWasRunning = self.runner:isRunning()
  self.runner:update()
  -- A SCRIPT THAT JUST FINISHED MAY HAVE CHANGED WHO IS ON THE MAP.
  --
  -- set_flag re-derives the objects gated on THAT flag as it goes, which
  -- covers the ordinary "the rival leaves" case. This is the sweep for
  -- everything else a script can do to the roster, and it was gated to Gen 2
  -- because Gen 1 has no flag-gated objects to sweep.
  --
  -- Gen 3 has 1151 of them, and it runs its map's ON_TRANSITION script on
  -- ENTRY -- after this engine has already built the NPC list. So every
  -- object that a Hoenn map's own entry script hides stayed on screen for the
  -- whole visit, and only went away if the player left and came back.
  if scriptWasRunning and not self.runner:isRunning()
     and (GameVersion.isGen2() or GameVersion.isGen3()) then
    self:syncObjectVisibility()
    -- A COORD EVENT THE PLAYER WAS WALKED ONTO STILL HAS TO FIRE.
    --
    -- Step triggers are checked in onStepComplete, and onStepComplete is
    -- skipped for a SCRIPTED step -- which is right, or a cutscene would set
    -- off every trigger it walks the player across.  But a scene that ENDS
    -- with the player standing on one has to hand over to it, because no
    -- further step is coming: the player is already there.
    --
    -- The moving van is the case.  Its exit is a scripted walk, and the cell
    -- it ends on carries the opening's own coord event -- the one that sets
    -- the respawn point, the dynamic warp home, and the batch of flags that
    -- hides the OTHER child's family from both houses.  With it skipped the
    -- game started with two of everybody, and the extra ones never left.
    self:checkCoordEventHere(GameVersion.isGen3())
  end
  -- .CheckForcedBiking again, now that the map's callbacks have actually run.
  --
  -- The ROM fires MAPCALLBACK_NEWMAP synchronously inside LoadMapAttributes
  -- and only reaches CheckUpdatePlayerSprite afterwards, so by the time it
  -- asks "is ALWAYS_ON_BIKE set?" Route 17's callback has already said yes.
  -- Here the callbacks are QUEUED and run one per frame off the pending-script
  -- FIFO, so the setMap call below them was asking the question before the
  -- answer existed. It only ever looked right because the flag was left over
  -- from the previous visit -- which is the very bug above. With the flags
  -- correctly reset on every map, a single call at setMap would mean the
  -- Cycling Road never forces the bike at all.
  --
  -- Re-asking each frame is what the ROM effectively does anyway: the flag is
  -- a standing instruction ("wPlayerState is PLAYER_BIKE while this is set"),
  -- not an event, and the check is two flag reads.
  self:applyForcedBike()
  self:checkSpecialPhoneCall()
  self:checkBugContestClock()
  -- world.tick: the per-frame seam for mods that simulate something in the
  -- overworld rather than draw it.
  --
  -- There was none, and the workaround mods reached for was to register a
  -- render_pipeline and do the work in its `present` -- "a present pipeline
  -- runs every drawn frame and is an established public path", as
  -- STADIUM2_OVERWORLD_MODELS puts it, running its whole wild-Pokemon AI from
  -- one.  That ties a simulation to the render path's eligibility rules: the
  -- pipeline's level, its `available` gate, whether it has been retired after
  -- a throw, and whether the compositor had a canvas to hand it.  Any one of
  -- those going the wrong way stopped the world ticking, with nothing in any
  -- log, because nothing had failed -- which is exactly how the wild Pokemon
  -- ended up standing around unbattleable.
  --
  -- Emitted from update() rather than the draw path so it keeps ticking while
  -- the frame is skipped, and payload-guarded like every other hot event.
  if Runtime.wants("world.tick") then
    Runtime.emit("world.tick", { dt = dt, mapId = self.map and self.map.id,
                                 overworld = self, scripted = self.runner:isRunning() })
  end
  -- Gen2 daily resets (Kurt balls, fruit trees, radio lottery). Lazy require
  -- keeps Gen2Daily out of the module-load graph so a missing/broken daily
  -- file cannot produce "loop or previous error loading module".
  if GameVersion.isGen2() and Game and Game.save then
    require("src.script.Gen2Daily").poll(Game.save)
  end
  self:updateParallel()
  -- keep the player sprite in sync with the bike state (the drawer
  -- picks the red_bike sheet while riding)
  self.player.onBike = Game.save.onBike
  -- ...AND WHICH BIKE, which is what Collision has been asking for.
  --
  -- `acroTrickPasses` reads `mover.acroBike` and `mover.acroTrick`, and its
  -- own comment noted that nothing set either -- so its five obstacle
  -- behaviours were a wall to everybody.  They are the rider's now.
  local kind = Game.save.onBike and Game.save.bikeKind or nil
  self.player.acroBike = (kind == "acro") or nil
  self.player.machBike = (kind == "mach") or nil
  self:updateAcroBike()
  -- the rendered neighbor set depends on the view size; zooming out (or
  -- resizing) past what setMap computed re-runs the walk in place
  if self.map and (self.neighborViewW or 0) > 0 then
    -- the view growing is one way to need more neighbours; a renderer raising
    -- its own reach is the other, and it can happen without the view moving at
    -- all (a camera mode change, a zoom the 3D pass owns privately)
    local reachW, reachH, vw, vh = self:neighborReach()
    if vw ~= self.neighborViewW or vh ~= self.neighborViewH
       or reachW ~= self.neighborReachBuiltW
       or reachH ~= self.neighborReachBuiltH then
      self:rebuildNeighbors()
    end
  end
  if self.dustAnim then
    local da = self.dustAnim
    da.frames = da.frames - 1
    if da.frames <= 0 then
      self.dustAnim = nil
      if da.onDone then da.onDone() end
    end
  end
  if self.cutAnim then
    local ca = self.cutAnim
    ca.frames = ca.frames - 1
    if ca.frames <= 0 then
      self.cutAnim = nil
      if ca.onDone then ca.onDone() end
    end
  end
  -- PlaceMapNameSign counts wLandmarkSignTimer down each frame and drops
  -- the window (rWY = $90) when it hits zero
  if self.mapNameSign then
    self.mapNameSign.frames = self.mapNameSign.frames - 1
    if self.mapNameSign.frames <= 0 then self.mapNameSign = nil end
  end
  -- fishing pose tail: the rod is already gone, the pose holds for the
  -- frames the original spends unwinding the item menu (#384)
  if self.fishPose then
    self.fishPose = self.fishPose - 1
    if self.fishPose <= 0 then
      self.fishPose = nil
      self.player.fishing = nil
    end
  end
  -- Yellow's companion hopping up onto the Poke Center counter owns the
  -- world for its arc, the same way the heal machine below does (#417)
  if self.pikaHop then
    require("src.world.PikachuFollower").updateHop(self)
    return
  end
  if self.healAnim then
    local ha = self.healAnim
    local ev = OverworldState.stepHealAnim(ha)
    if ev == "ball" then
      require("src.core.Sound").play(Game.data, "Healing_Machine")
    elseif ev == "jingle" then
      -- playOnce restores the map theme when the jingle ends; we no longer
      -- block the fighting-fit text on that (#157).  The label comes from
      -- the role table because gen2 names the same jingle Music_HealPokemon.
      local Music = require("src.core.Music")
      Music.playOnce(Game.data, Music.special(Game.data, "heal"))
    elseif ev == "done" then
      local done = ha.onDone
      self.healAnim = nil
      if done then done() end
    end
    return
  end
  if self.flyAnim then
    self.flyAnim.frames = self.flyAnim.frames - 1
    if self.flyAnim.frames <= 0 then
      self.flyAnim = nil
      self.player.inputLocked = false
      local d = self.flyDest
      self.flyDest = nil
      if d then
        -- the bird carries the player in on landing, with its own
        -- SFX_FLY (EnterMapAnim .flyAnimation)
        self.arriveWarp = "fly"
        self:startWarpTo(d.map, d.x, d.y, "down", nil, { via = "fly" })
      end
      return
    end
  end

  -- Dig/Teleport/Escape-Rope departure spin (beginTeleportOut).  The sprite
  -- spins UP out of the map before the fade (player_animations.asm
  -- _LeaveMapAnim -> PlayerSpinWhileMovingUp + SFX_TELEPORT_EXIT_1), the
  -- mirror of Fly's flyAnim lead-in above.  Only when the spin finishes does
  -- warpToHealPoint push the fade + warp, so the arrival spin-down lands the
  -- player OUTSIDE the last Pokemon Center door (#196).  player.spinFrames
  -- decrements in lockstep in Player:update, so the rising spin ends here too.
  if self.teleportOut then
    self.teleportOut.frames = self.teleportOut.frames - 1
    if self.teleportOut.frames <= 0 then
      local onDone = self.teleportOut.onDone
      local escape = self.teleportOut.escape
      self.teleportOut = nil
      self.player.spinning = false
      self.player.spinFrames = nil
      self.player.spinRise = nil
      self.player.inputLocked = false
      if escape then
        self:warpToEscapePoint(onDone)
      else
        self:warpToHealPoint(onDone, { arrive = "teleport" })
      end
      return
    end
  end

  -- Script_ForcedMovement's whirl (checkGen2Whirlpool): two `step_dig 16`
  -- beats, then `turn_head_<opposite>` drops the player facing back the way
  -- they came.  Input is gated for the whole thing, exactly as applymovement
  -- gates it in the ROM.
  if self.whirlSpin then
    self.whirlSpin.frames = self.whirlSpin.frames - 1
    if self.whirlSpin.frames <= 0 then
      local facing = self.whirlSpin.facing
      local hold = self.whirlSpin.hold
      self.whirlSpin = nil
      self.player.spinning = false
      self.player.spinFrames = nil
      self.player.facing = facing
      self.player.inputLocked = false
      self.whirlHold = hold
    end
  elseif (self.whirlHold or 0) > 0 then
    self.whirlHold = self.whirlHold - 1
  end

  -- delayed one-shot SFX (the teleport-in spin's second note)
  if self.delaySfx then
    self.delaySfx.frames = self.delaySfx.frames - 1
    if self.delaySfx.frames <= 0 then
      require("src.core.Sound").play(Game.data, self.delaySfx.key)
      self.delaySfx = nil
    end
  end

  -- A SCRIPTED SCREEN THAT CLOSED WITHOUT SAYING SO.
  --
  -- Gen3Commands' pushBlocking parks the script runner on a screen and waits
  -- for the screen to call back.  Every screen written for Hoenn does; the
  -- Game Boy ones do not, because they close themselves -- and a push that
  -- falls back to one of those left the runner parked for ever.  This is the
  -- net under that: once the screen has left the stack, the wait is over
  -- whatever the screen did or did not call.
  self:gen3CheckBlockingScreen()

  -- A BRAILLE WALL HOLDS THE WORLD until it is read.
  --
  -- The cartridge writes `braillemessage / waitbuttonpress /
  -- closebraillemessage`, and `waitbuttonpress` is a nop in this engine
  -- because every box here owns its own lifecycle -- so the wait is here.
  -- ScrCmd_braillemessage takes A or B, the same as any box.
  --
  -- ...but not on the frame it went up.  The wall is a SIGN: the press that
  -- read it is still the current press when the script reaches this, and an
  -- unarmed first frame is what stops the box opening and shutting again
  -- inside one A.
  if self.brailleBox then
    if not self.brailleBox.armed then
      self.brailleBox.armed = true
    elseif Game.input:wasPressed("a") or Game.input:wasPressed("b") then
      local done = self.brailleBox.onDone
      self.brailleBox = nil
      if done then done() end
    end
    self.player:update()
    return
  end

  -- the emotion-bubble pause holds the world for a beat
  if self.emote then
    self.emote.frames = self.emote.frames - 1
    -- PikaPicAnimTimerAndJoypad (engine/pikachu/pikachu_pic_animation.asm)
    -- cuts a pikapic beat short on A or B; the "!" bubble hold has no such
    -- check, so only the pikapic marks itself skippable (#424)
    local cut = self.emote.skippable
                and (Game.input:wasPressed("a") or Game.input:wasPressed("b"))
    if cut or self.emote.frames <= 0 then
      local done = self.emote.onDone
      self.emote = nil
      if done then done() end
    end
    self.player:update()
    return
  end

  for _, npc in ipairs(self.npcs) do
    npc:update(self.map, self.entities)
  end
  require("src.world.PikachuFollower").update(Game, self)

  for _, g in ipairs(self.ghosts) do
    g.npc:update(g.map, g.peers)
  end

  -- THE PLAYER TAKES ITS SCRIPTED STEP HERE TOO, with the NPCs.
  --
  -- Reported from play, twice: "when following wally my character doesnt
  -- fully get behind him", and then exactly -- "when wally turns right
  -- towards the route im one block above him instead of behind him".
  --
  -- Petalburg's script walks the two of them with a pair of applymovements
  -- and one waitmovement, and the cartridge's own arithmetic has the player
  -- descend ONE MORE TILE than Wally so that they finish the leg on the same
  -- row, the player directly behind him for the walk east.  So "one block
  -- above him" is the player short of a tile, and the reason was the order of
  -- this frame rather than anything in the movement lists.
  --
  -- An NPC updates ABOVE this line and the queue is topped up BELOW it: on
  -- the frame an NPC's step lands, updateScriptMoves sees it standing still
  -- and starts the next one the same frame.  The player used to update at the
  -- BOTTOM of the frame, after the top-up -- so on the frame its step landed,
  -- the queue had already been asked and looked at a player that was still
  -- moving.  Every scripted step cost the player one frame and cost an NPC
  -- none.  Eight steps into that walk the player is half a tile short; by the
  -- end of the twenty-eight it is nearly two.
  --
  -- The two updates cannot both happen: `handleInput` is the only other thing
  -- that starts a player step and it is gated off whenever the queue is
  -- non-empty, which is exactly when this runs.  So the frame's own step
  -- result travels down to where it was read.
  local playerStepped = nil
  if #self.scriptMoves > 0 and self.player.moving then
    playerStepped = self.player:update()
  end

  self:updateScriptMoves()

  -- emote is included: a cutscene hold queued from a scriptMove onDone
  -- (e.g. Oak's lab Delay3 after his entry walk) is assigned mid-frame,
  -- after the early emote return above already missed it.  Without this,
  -- one frame of handleInput can sneak through -- holding UP during the
  -- escort then walks an extra tile before PlayerEntryMovementRLE, and
  -- the player lands on desk Oak.
  local scripted = self.runner:isRunning() or #self.scriptMoves > 0
                   or self.engaging or self.emote or self.teleportOut
                   or self.whirlSpin
  -- Gen2 bootstrap can arrive with placeholder script state while map data
  -- is still converging; never softlock movement in the bedroom.
  local gen2BootBedroom = GameVersion.isGen2(Game.data)
    and self.map and self.map.id == "PLAYERS_HOUSE2_F"
  if gen2BootBedroom then
    self.player.inputLocked = false
  end
  -- A queued scene script owns the map until it has run: on the cartridge it
  -- runs during map setup, so the player never gets an input frame ahead of it
  -- (see drainPendingScripts).  Without this the step is merely late rather
  -- than prevented -- the drain refuses to start mid-step, so the scripted walk
  -- would begin from the wrong cell a frame later instead.
  if self.pendingScripts and self.pendingScripts[1] then
    scripted = true
  end
  if not scripted and not self.transitioning then
    self:checkTrainerSight()
    -- CheckFightingMapTrainers (home/trainers.asm) zeroes hJoyHeld and
    -- sets wJoyIgnore the instant a trainer engages, before the loop's
    -- direction handling (JoypadOverworld runs the map script first) --
    -- the player can never start another step after being spotted.
    scripted = self.runner:isRunning() or #self.scriptMoves > 0
               or self.engaging or self.emote or self.teleportOut
               or self.whirlSpin
  end
  if (not scripted and not self.transitioning) or gen2BootBedroom then
    self:handleInput()
    self.lockedFrames = nil
  else
    -- THE WATCHDOG, because "I could not walk" is the one bug report this
    -- engine cannot answer.
    --
    -- Seven separate things gate an input frame and every one of them is
    -- invisible: no text box, no cutscene, nothing drawn.  When one of them
    -- sticks the game is simply frozen, and the log says nothing at all --
    -- which is how a stranded scripted move (see updateScriptMoves) could
    -- lock a player in a room with no way to tell it from a hang.
    --
    -- So: after ten seconds of held input with nothing on screen to explain
    -- it, name the condition that is holding it, once.  Ten seconds is far
    -- past any real cutscene beat in either cartridge and still short enough
    -- that the line is in the log next to whatever the player last did.
    self.lockedFrames = (self.lockedFrames or 0) + 1
    if self.lockedFrames == 600 then
      local why = {}
      if self.runner:isRunning() then why[#why + 1] = "a script is running" end
      if #self.scriptMoves > 0 then
        why[#why + 1] = ("%d scripted move(s) queued"):format(#self.scriptMoves)
      end
      if self.engaging then why[#why + 1] = "a trainer is engaging" end
      if self.emote then why[#why + 1] = "an emote bubble is up" end
      if self.teleportOut then why[#why + 1] = "a teleport is playing" end
      if self.whirlSpin then why[#why + 1] = "a whirlpool spin is playing" end
      if self.transitioning then why[#why + 1] = "a map transition is running" end
      if self.pendingScripts and self.pendingScripts[1] then
        why[#why + 1] = ("%d scene script(s) queued and undrained")
                        :format(#self.pendingScripts)
      end
      if self.player and self.player.inputLocked then
        why[#why + 1] = "player.inputLocked is set"
      end
      if self.player and self.player.moving then
        why[#why + 1] = "the player is mid-step"
      end
      Logger.warn("input has been gated for 10s on %s with nothing on screen "
                    .. "-- held by: %s",
                  tostring(self.map and self.map.id),
                  #why > 0 and table.concat(why, ", ") or "nothing this "
                    .. "check knows about, which is itself the finding")
    end
  end

  -- ...and it is not advanced twice: a scripted step taken with the NPCs
  -- above carries its result down here instead of being stepped again, which
  -- would hand the player the one-frame advantage this fix took away from the
  -- NPCs.
  local stepped = playerStepped
  if stepped == nil then stepped = self.player:update() end
  -- the warp-arrival cell goes stale the instant the player's real cell
  -- leaves it, scripted walk-outs included -- pokered re-checks warps
  -- after simulated steps too (CheckWarpsNoCollision), so a forced
  -- door-mat exit must not leave the door permanently inert
  local entry = self.warpEntryCell
  if entry and (self.player.cellX ~= entry.x or self.player.cellY ~= entry.y) then
    self.warpEntryCell = nil
  end
  -- the one-shot coord guard is per CELL, so leaving it re-arms it
  if self.coordFired and self.player.cellX then
    local key = ("%s:%d,%d"):format(self.map.id, self.player.cellX,
                                    self.player.cellY)
    if self.coordFired ~= key then self.coordFired = nil end
  end
  -- deferred PlayMapMusic from crossConnection (issue #93)
  if stepped and self.pendingSeamMusic then
    local mapId = self.pendingSeamMusic
    self.pendingSeamMusic = nil
    if mapId == self.map.id then
      require("src.core.Music").playMap(Game.data, mapId, Game.save.onBike,
                                        self.player.surfing)
    end
  end
  if stepped and not scripted then
    self:onStepComplete()
  end

  self.camera:follow(self.player.px, self.player.py,
                     Game.renderer:worldViewSize())

  -- pan_camera offset rides on top of the follow; the ramp resumes its
  -- runner when it lands
  local pan = self.cameraPan
  if pan then
    if pan.frames then
      pan.t = pan.t + 1
      local k = math.min(1, pan.t / pan.frames)
      pan.ox = pan.fromX + (pan.toX - pan.fromX) * k
      pan.oy = pan.fromY + (pan.toY - pan.fromY) * k
      if pan.t >= pan.frames then
        pan.frames = nil
        local done = pan.onDone
        pan.onDone = nil
        if done then done() end
      end
    end
    self.camera.x = self.camera.x + pan.ox
    self.camera.y = self.camera.y + pan.oy
  end
end

-- any direction currently held (hJoyHeld & PAD_CTRL_PAD)
function OverworldState:dirHeld()
  local input = Game.input
  return input:isDown("up") or input:isDown("down")
      or input:isDown("left") or input:isDown("right")
end

-- BIT_STANDING_ON_WARP (wMovementFlags): the warp under the player's feet may
-- only fire from a collision -- the blocked-step warp (handleInput) and the
-- map-edge exit (checkEdgeExit) -- while this flag is set.  pokered clears it
-- on every completed step, sets it again when that step lands on a warp
-- square, then clears it once more when the square is a warp-activating tile
-- that is not also a door tile (CheckWarpsNoCollisionLoop ->
-- IsPlayerStandingOnDoorTileOrWarpTile, engine/overworld/player_state.asm);
-- onStepComplete maintains it.  ClearVariablesOnEnterMap does not clear
-- wMovementFlags, so the flag rides through the warp itself: a house door
-- tile ($1B) leaves it set, so you land on the interior mat still able to
-- walk back out on that same tile (issue #378), while a staircase tile
-- ($1A/$1C) clears it and cannot bounce you between floors (issue #230).
-- DoPlayerMovement .EdgeWarps (engine/overworld/player_movement.asm): the
-- player is standing ON one of the four COLL_WARP_CARPET_* tiles and is
-- walking on in that carpet's own direction, already facing it.  That is the
-- whole test -- it calls WarpCheck, which unlike CheckWarpTile does NOT run
-- the directional filter, and it does not consult BIT_STANDING_ON_WARP.
--
-- This is the other half of treating carpets as non-immediate (see the
-- coord-event ordering in the step handler).  The collision-warp path next to
-- it cannot stand in for it: refreshStandingOnWarp clears standingOnWarp for
-- exactly these tiles -- a carpet is a warp tile and not a doorway -- so
-- canCollisionWarp is false on every mat in the game, and without this the
-- player could walk onto a Pokemon Center's exit mat and never walk off it.
local GEN2_CARPET_DIR = {
  [0x70] = "down", [0x76] = "left", [0x78] = "up", [0x7E] = "right",
}

function OverworldState:checkGen2CarpetExit(dir)
  if not GameVersion.isGen2() then return false end
  local p = self.player
  if GEN2_CARPET_DIR[self.map:cellTile(p.cellX, p.cellY)] ~= dir then
    return false
  end
  local w = self.map:warpAtCell(p.cellX, p.cellY)
  if not w then return false end
  self:takeWarp(w.def)
  return true
end

-- Put the Cycling Road down, on both generations.
--
-- Gen 1 kept ALWAYS_ON_BIKE in `save.forcedBike`; Gen 2 keeps it -- and
-- DOWNHILL beside it -- in two engine flags the map callbacks write, which
-- live in `save.flags` and are serialised to disk with everything else. Every
-- clear in this file was written for the Gen 1 field alone, so on Gen 2 the
-- ONLY thing that ever put the bike away was a gate map's own `clearflag`.
--
-- Fly, a blackout, Dig, Teleport and Escape Rope all leave the Cycling Road
-- without walking through a gate. Each of them left both flags set, and then
-- applyForcedBike below remounted the player on every subsequent map load
-- while handleInput dragged them south on all of them -- the whole game
-- played downhill on a bike that could not be put away.
--
-- Nothing here is conditional on being ON the Cycling Road: these are the
-- points the ROM itself clears BIT_ALWAYS_ON_BIKE at, and a flag that is
-- already clear is cheap to clear again.
function OverworldState:clearBikeFlags()
  Game.save.forcedBike = nil
  if not GameVersion.isGen2() then return end
  local Flags = require("src.script.Flags")
  local Gen2Flags = require("src.script.Gen2Flags")
  Flags.clear(Game.save, Gen2Flags.bikeFlag("bike"))
  Flags.clear(Game.save, Gen2Flags.bikeFlag("downhill"))
end

-- .CheckForcedBiking.  Gen2 keeps ALWAYS_ON_BIKE in an engine flag the map
-- callbacks write; Gen1 kept it in save.forcedBike, which the gate maps clear.
function OverworldState:applyForcedBike()
  if not GameVersion.isGen2() then return end
  local Flags = require("src.script.Flags")
  local Gen2Flags = require("src.script.Gen2Flags")
  -- ...and only where a bike is allowed at all.  The flag surviving into an
  -- interior used to remount the player inside houses, Centers and dungeons,
  -- which is most of what "it never lets me off the bike" looked like.
  if Flags.get(Game.save, Gen2Flags.bikeFlag("bike"))
     and self:bikeAllowed(self.map and self.map.id) then
    Game.save.onBike = true
  end
end

-- THE SURFACE THE FIELD IS DRAWN ON.
--
-- Whichever state on the stack asks for a native surface sets the size for
-- the frame, and the fit scale is derived from it -- so a state that asks for
-- a bigger one mid-play makes everything, the world included, step DOWN a
-- scale.  The dialogue box has to ask, because Emerald's is twenty-eight
-- tiles and does not fit the Game Boy's 160-pixel canvas; the field asking
-- for the same surface is what stops that from being a zoom-out every time
-- somebody speaks.  Theme owns the answer so the two cannot disagree, and on
-- a dataset whose box fits the classic screen it is the classic screen and
-- nothing changes at all.
function OverworldState:uiSize()
  return require("src.ui.Theme").uiSize()
end

function OverworldState:canCollisionWarp()
  return self.standingOnWarp == true
end

-- Re-derive the flag from the tile under the player, the way a completed step
-- does (and the way MapEntryAfterBattle's IsPlayerStandingOnWarp does after a
-- battle): a door tile keeps it, a stair/ladder warp tile clears it.
function OverworldState:refreshStandingOnWarp()
  local p = self.player
  self.standingOnWarp = false
  if self.map:warpAtCell(p.cellX, p.cellY)
     and not (self.map:isWarpTileCell(p.cellX, p.cellY)
              and not self.map:isDoorTileCell(p.cellX, p.cellY)) then
    self.standingOnWarp = true
  end
end

-- ---------------------------------------------------------------------------
-- THE ROTATING GATES, which the cache has carried unread for a while.
--
-- Nineteen gates over two maps -- Fortree's gym and the Trick House's eighth
-- puzzle -- and not one line of this port ever looked at the record.  With
-- none of them there, the gym is an empty hall you stroll across.
--
-- A gate's pivot is a CORNER, not a cell: the collision test takes the 4x4
-- block from (x-2, y-2) to (x+1, y+1), so the middle of a gate is world pixel
-- (x*16, y*16) and its arms lie on the LINES between cells.  That is why this
-- hangs off the STEP rather than off the destination cell being solid --
-- there is nothing solid to stand on, only a fence to cross.
-- ---------------------------------------------------------------------------

-- ...AND THE CARTRIDGE PUTS THEM BACK ONLY ON ONE OF ITS TWO ENTRIES.
--
-- A gate map keeps two map scripts and they are not the same call.
-- ON_TRANSITION runs `special RotatingGate_InitPuzzle` (204), which loads the
-- puzzle AND copies every gate's default orientation back over whatever you
-- left it turned to; ON_RESUME runs RotatingGate_InitPuzzleAndGraphics (205),
-- which loads the same puzzle and builds its sprites and does NOT touch the
-- orientations -- because coming back from a battle or a menu is not walking
-- in, and a puzzle that reset itself for that would be unsolvable.
--
-- `keep` is that difference, and the two specials are what pass it.
function OverworldState:startGen3Gates(mapId, keep)
  self.gen3Gates = nil
  if not GameVersion.isGen3() then return end
  local ok, Gates = pcall(require, "src.world.Gen3Gates")
  if not ok then return end
  local record = Gates.record(Game.data)
  local puzzle = Gates.puzzleFor(record, mapId or (self.map and self.map.id))
  if not puzzle then return end
  if not keep then Gates.reset(Game.save, record, puzzle) end
  self.gen3Gates = { record = record, puzzle = puzzle }
  return true
end

-- A step into a gate: nothing at all, a turn you walk through, or a wall.
-- Returns true only for the wall, because the cartridge's own answer after a
-- turn is "no collision" -- you push the gate round and walk on in the same
-- step.
function OverworldState:checkGen3Gate(dir)
  local held = self.gen3Gates
  if not held then return false end
  local p = self.player
  local fx, fy = Collision.target(p.cellX, p.cellY, dir)
  -- ...but only when the step would otherwise have been allowed.  The
  -- cartridge asks the gates AFTER the map has said the cell is walkable, so
  -- a gate behind a wall is never asked and never turns.
  if not Collision.canMove(self.map, self.entities, p, dir) then return false end
  local Gates = require("src.world.Gen3Gates")
  local function passable(cx, cy)
    if not self.map:inBounds(cx, cy) then return false end
    return self.map:isWalkableCell(cx, cy)
  end
  local what = Gates.step(held.record, Game.save, held.puzzle, dir, fx, fy,
                          passable)
  if what == "rotated" then
    require("src.core.Sound").play(Game.data, "Collision")
    return false
  end
  if what == "blocked" then
    if (self.bumpCooldown or 0) <= 0 then
      require("src.core.Sound").play(Game.data, "Collision")
      self.bumpCooldown = 16
    end
    return true
  end
  return false
end

-- The picture: one 64-square cell a shape, turned by the orientation.  The
-- sheet is baked against the palette OBJ slot 2 holds on those two maps --
-- the gates carry none of their own -- and the cartridge turns one drawing
-- with an affine animation rather than shipping four, so this rotates too.
function OverworldState:drawGen3Gates(cam)
  local held = self.gen3Gates
  local art = held and held.record.art
  if not (art and art.image) then return end
  if self.gen3GateArt == nil then
    local okArt, img = pcall(require("src.render.Assets").image, art.image)
    self.gen3GateArt = (okArt and img) or false
  end
  local sheet = self.gen3GateArt
  if not sheet then return end
  local Gates = require("src.world.Gen3Gates")
  local cell = math.floor(tonumber(art.cell) or 64)
  if cell < 1 or sheet:getHeight() < cell then return end
  love.graphics.setColor(1, 1, 1, 1)
  for index, gate in ipairs(held.puzzle.gates) do
    local shape = math.floor(tonumber(gate.shape) or 0)
    local quad = self.gen3GateQuads and self.gen3GateQuads[shape + 1]
    if not quad then
      self.gen3GateQuads = self.gen3GateQuads or {}
      quad = love.graphics.newQuad(shape * cell, 0, cell, cell,
                                   sheet:getWidth(), sheet:getHeight())
      self.gen3GateQuads[shape + 1] = quad
    end
    local orientation = Gates.orientation(Game.save, held.record, index - 1)
    -- ONE STEP OF ORIENTATION IS A QUARTER TURN CLOCKWISE.  The shape's own
    -- arm slot i points in world direction (i + orientation) mod 4, counted
    -- up, right, down, left -- so adding one moves every arm one step round
    -- that cycle, and that cycle is clockwise.
    love.graphics.draw(sheet, quad,
                       math.floor(gate.x * 16 - cam.x),
                       math.floor(gate.y * 16 - cam.y),
                       orientation * math.pi / 2, 1, 1, cell / 2, cell / 2)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- DECORATIONS, which are neither map objects nor script objects.
--
-- The DECORATION row of a secret base's PC hands the player a cursor and lets
-- them stand a thing on a cell.  A decoration is stored as an id and one cell
-- -- its BOTTOM-LEFT -- and how it is drawn depends on a permission byte:
-- eighty-one of them are written into the MAP GRID as width*height metatiles,
-- and the forty-five DOLLs and CUSHIONs are OBJECT SPRITES instead.  Both
-- kinds are re-made on every map load out of the save, which is what makes
-- them survive leaving the room, and neither touches the map's own def.
-- ---------------------------------------------------------------------------

-- Rebuild what is standing here after the player has put one out or taken
-- one away.  The cells a decoration owned have to be given back before the
-- next pass claims them, which is why this is not just a second apply.
function OverworldState:refreshGen3Decorations()
  self.npcs = self.npcs or {}
  for _, cell in ipairs(self.gen3DecorCells or {}) do
    if self.map and self.map.clearBlock then
      self.map:clearBlock(cell.x, cell.y)
    end
  end
  self.gen3DecorCells = nil
  for _, npc in ipairs(self.gen3DecorNPCs or {}) do
    for i = #self.npcs, 1, -1 do
      if self.npcs[i] == npc then table.remove(self.npcs, i) end
    end
    for i = #(self.entities or {}), 1, -1 do
      if self.entities[i] == npc then table.remove(self.entities, i) end
    end
    if npc.id then self.npcPool[npc.id] = nil end
  end
  self.gen3DecorNPCs = nil
  self:applyGen3Decorations(self.map and self.map.id)
end

function OverworldState:applyGen3Decorations(mapId)
  self.gen3DecorNPCs = nil
  self.gen3DecorCells = nil
  if not (GameVersion.isGen3() and self.map and Game.data) then return end
  local ok, Decor = pcall(require, "src.world.Gen3Decorations")
  if not ok then return end
  local where = Decor.placeFor(Game.data, Game.save, mapId or self.map.id)
  if not where then return end
  local standing = Decor.standing(Game.data, Game.save, where)
  if #standing == 0 then return end
  local made, cells = {}, {}
  for _, row in ipairs(standing) do
    if Decor.isSprite(Game.data, row.id) then
      local gfx = tonumber(row.def.gfx)
      if gfx then
        local obj = { index = -1000 - row.index, x = row.x, y = row.y,
                      sprite = ("SPRITE_G3_%03d"):format(gfx),
                      facing = "down", runtime = true }
        local npc = pooledNPC(self.npcPool, Game.data,
                              mapId or self.map.id, obj)
        npc.frozen = true
        npc.gen3Decoration = row.id
        table.insert(self.npcs, npc)
        made[#made + 1] = npc
      end
    else
      -- A decoration is something you walk around -- unless it is a MAT,
      -- which is something you stand on (the writer skips its blocked
      -- branch for exactly that one permission).  And a Gen 3 renderer bakes
      -- its window, so a block that changed has to ask for the rebuild --
      -- the same thing the sweeping ash and the cracking ice have to do.
      local blocked = not Decor.walkable(Game.data, row.id)
      for _, cell in ipairs(Decor.footprint(Game.data, row.id, row.x, row.y)) do
        if cell.metatile then
          self.map:setBlock(cell.x, cell.y, cell.metatile, blocked)
          cells[#cells + 1] = { x = cell.x, y = cell.y }
        end
      end
      if #cells > 0 then self:redrawBlocks() end
    end
  end
  self.gen3DecorNPCs = #made > 0 and made or nil
  self.gen3DecorCells = #cells > 0 and cells or nil
end

-- ------- putting one out: the cursor the DECORATE row hands the player

function OverworldState:gen3DecorateBegin(id, onDone)
  local Decor = require("src.world.Gen3Decorations")
  local w, h = Decor.shapeOf(Game.data, id)
  if not (w and h and self.player) then
    if onDone then onDone(false) end
    return false
  end
  self.gen3Decorate = {
    id = id, width = w, height = h,
    x = self.player.cellX, y = self.player.cellY,
    onDone = onDone,
  }
  self.player.inputLocked = true
  return true
end

function OverworldState:gen3DecorateFinish(placed)
  local mode = self.gen3Decorate
  self.gen3Decorate = nil
  if self.player then self.player.inputLocked = false end
  if mode and mode.onDone then mode.onDone(placed and true or false) end
end

-- One frame of the cursor.  Returns true when it has taken the input, which
-- is what keeps the player from walking around underneath it.
function OverworldState:gen3DecorateInput()
  local mode = self.gen3Decorate
  if not mode then return false end
  local input = Game.input
  local dx, dy = 0, 0
  if input:wasPressed("up") then dy = -1 end
  if input:wasPressed("down") then dy = 1 end
  if input:wasPressed("left") then dx = -1 end
  if input:wasPressed("right") then dx = 1 end
  if dx ~= 0 or dy ~= 0 then
    local nx, ny = mode.x + dx, mode.y + dy
    -- the whole footprint has to stay on the map, and the anchor is the
    -- bottom-left, so the top row is (y - height + 1)
    if nx >= 0 and ny - mode.height + 1 >= 0
       and nx + mode.width - 1 < self.map.def.width
       and ny < self.map.def.height then
      mode.x, mode.y = nx, ny
    end
  end
  if input:wasPressed("b") then
    self:gen3DecorateFinish(false)
    return true
  end
  if input:wasPressed("a") then
    local Decor = require("src.world.Gen3Decorations")
    local where = Decor.placeFor(Game.data, Game.save, self.map.id)
    local done, why = false, "place"
    if where then
      done, why = Decor.putOut(Game.data, Game.save, where, mode.id,
                               mode.x, mode.y)
    end
    if done then
      self:gen3DecorateFinish(true)
      self:refreshGen3Decorations()
    else
      Logger.debug("gen3 decorate: %s", tostring(why))
      require("src.core.Sound").play(Game.data, "Collision")
    end
    return true
  end
  return true
end

function OverworldState:handleInput()
  local input = Game.input
  if self.gen3Decorate then return self:gen3DecorateInput() end

  -- the wall-bonk SFX cooldown ticks with any held direction, step or not
  -- (it is a port invention, not part of JoypadOverworld, so the
  -- wWalkCounter gate below must not freeze it mid-step)
  if self:dirHeld() then
    self.bumpCooldown = math.max(0, (self.bumpCooldown or 0) - 1)
  end

  -- OverworldLoop (home/overworld.asm) gates ALL of JoypadOverworld on
  -- wWalkCounter == 0 ("if the player sprite has not yet completed the
  -- walking animation" it jumps straight to .moveAhead): A, START and
  -- direction initiation are only ever ACTED ON while the player stands on
  -- a tile.  Without this gate a mid-step A/START pushed its TextBox/
  -- StartMenu right there and froze Red between tiles, mid-animation
  -- (#286).  Held directions need no buffering -- isDown below picks them
  -- up on the landing frame.
  --
  -- The original defers the poll rather than discarding it, though.  Joypad
  -- (engine/joypad.asm _Joypad) computes hJoyPressed against hJoyLast and
  -- advances hJoyLast only when something calls it; the mid-step path never
  -- does, and vblank's per-frame ReadJoypad refreshes hJoyInput alone.
  -- hJoyLast is frozen for the whole animation, so a button pressed
  -- mid-step and STILL HELD when the step lands reads as a fresh press at
  -- the next poll -- one released before then is genuinely lost.  Dropping
  -- the edge outright made START a coin flip on the Cycling Road roll,
  -- where the pull below re-arms a step on the single idle frame in
  -- bikeStepFrames (#525).
  if self.player.moving then
    local held = self.joyLatch
    if not held then held = {}; self.joyLatch = held end
    if input:wasPressed("a") then held.a = true end
    if input:wasPressed("start") then held.start = true end
    return
  end
  local latch = self.joyLatch
  self.joyLatch = nil

  if input:wasPressed("a") or (latch and latch.a and input:isDown("a")) then
    self:interact()
    return
  end
  if input:wasPressed("start")
     or (latch and latch.start and input:isDown("start")) then
    require("src.core.Sound").play(Game.data, "Start_Menu")
    -- WHICH start menu is the dataset's to say: Emerald's is a different
    -- screen with different rows on a different sized surface, not this one
    -- with the words swapped.
    local boot = Game.data.field and Game.data.field.boot
    local screens = boot and boot.screens or {}
    Screens.push(Game, screens.startMenu or "StartMenu")
    return
  end
  -- SELECT runs the registered key item without opening the pack
  if input:wasPressed("select") and GameVersion.isGen2()
     and require("src.ui.BagMenu").useRegistered(Game) then
    return
  end

  for _, dir in ipairs({ "up", "down", "left", "right" }) do
    if input:isDown(dir) then
      -- .Normal and .Surf both `call .CheckTile` straight after .GetAction
      -- and `ret c`, so the eddy pre-empts turning, stepping, ledges and
      -- warps alike -- and, being a bump, it never lets the player in.
      if self:checkGen2Whirlpool(dir) then return end
      if not self.player.moving and self.player.facing == dir then
        if self:checkGen2CarpetExit(dir) then return end
        if self:checkEdgeExit(dir) then return end
        if self:checkLedgeHop(dir) then return end
        if self:checkBoulderPush(dir) then return end
        if self:checkGen3Gate(dir) then return end
      end
      local result, why = self.player:tryMove(dir, self.map, self.entities)
      -- a collision while standing on a warp square fires the warp when the
      -- extra check passes (CheckWarpsCollision: route-gate doorways, dock
      -- entrances, ...), and only while BIT_STANDING_ON_WARP is set (issue
      -- #230), which the map-edge path guards the same way.
      if result == "blocked" and self:canCollisionWarp() then
        local w = Warp.onCollision(self.map, Game.data.field.warpCarpets,
                                   self.player.cellX, self.player.cellY, dir)
        if w then
          self:takeWarp(w.def)
          return result
        end
      end
      if result == "blocked" and why ~= "entity" then
        if (self.bumpCooldown or 0) <= 0 then
          require("src.core.Sound").play(Game.data, "Collision")
          self.bumpCooldown = 16
          -- ...AND ON THE CYCLING ROAD IT COSTS YOU.  The run's second
          -- number is how many times you hit something, and this is the
          -- moment the cartridge counts one: a step that would not go, into
          -- scenery rather than a person.
          local run = Game.save and Game.save.gen3Cycling
          if type(run) == "table" and run.active then
            run.collisions = (run.collisions or 0) + 1
          end
        end
      end
      return result
    end
  end

  -- .noDirectionButtonsPressed (home/overworld.asm) is the only place that
  -- sets wCheckFor180DegreeTurn, so reaching this line -- a poll that found
  -- no direction held -- is what re-arms the next turn in place.  The early
  -- returns above (mid-step, A, START) skip it exactly as the original's
  -- jumps to .moveAhead and .displayDialogue do (#415).
  self.player.turnArmed = true

  -- Cycling Road's downhill pull: with no d-pad held the bike rolls
  -- south (home/overworld.asm JoypadOverworld's simulated PAD_DOWN).
  -- The mask there is PAD_CTRL_PAD | PAD_B | PAD_A, so HOLDING A or B
  -- brakes exactly like a held direction: what the Route 17 sign
  -- promises ("Press the A or B Button to stay in place") and what the
  -- edge-only wasPressed("a") above can never deliver, since a press
  -- stalls the roll for one frame only (issue #255).
  local fm = Game.data.field.forcedMovement
  -- WHAT COUNTS AS A BRAKE IS NOT THE SAME IN BOTH GENERATIONS.
  --
  -- Gen 2's mask is the d-pad and nothing else (player_movement.asm .GetDPad):
  --
  --     ld hl, wBikeFlags
  --     bit BIKEFLAGS_DOWNHILL_F, [hl]
  --     ret z
  --     ld c, a
  --     and PAD_CTRL_PAD        <-- d-pad only; A and B are not in it
  --     ret nz
  --     ld a, c
  --     or PAD_DOWN
  --
  -- so on Gold, Silver and Crystal holding A or B does NOT stop the roll --
  -- you steer out of it, or you coast. Gen 1's mask does include A and B,
  -- which is what its Route 17 sign promises, so that reading stays.
  -- The d-pad half of that mask is already answered: this line is only
  -- reached on the no-direction-held path, so all that is left to decide is
  -- whether A or B also count -- and on Gen 2 they do not.
  local braking = (not GameVersion.isGen2())
    and (input:isDown("a") or input:isDown("b")) or false
  if Game.save.onBike and not braking and not self.player.moving then
    -- Gen2 arms the same pull from ENGINE_DOWNHILL, set by Route 17's
    -- MAPCALLBACK_NEWMAP alongside ALWAYS_ON_BIKE.  Gen1 named the maps in
    -- field.forcedMovement.slopeMaps instead, and that table is empty on a
    -- Gen2 import -- which is why the Cycling Road had no slope at all.
    local downhill = GameVersion.isGen2()
      and require("src.script.Flags").get(Game.save,
            require("src.script.Gen2Flags").bikeFlag("downhill"))
    if not downhill and fm then
      for _, m in ipairs(fm.slopeMaps or {}) do
        if m == self.map.id then downhill = true break end
      end
    end
    if downhill then
      self.player.facing = "down"
      self.player:tryMove("down", self.map, self.entities)
      return
    end
  end
end

-- Strength boulders (engine/overworld/push_boulder.asm TryPushingBoulder):
-- walking into one with STRENGTH in the party pushes it one cell, but
-- only on the second consecutive push attempt (BIT_TRIED_PUSH_BOULDER);
-- SFX_PUSH_BOULDER when the push starts, dust puff + SFX_CUT after.
function OverworldState:checkBoulderPush(dir)
  local p = self.player
  local fx, fy = Collision.target(p.cellX, p.cellY, dir)
  local npc = self:npcAtCell(fx, fy)
  if not npc or not Map.isPushable(npc.def) or npc.moving then
    self.boulderTried = nil -- pokered resets when no boulder is in front
    return false
  end
  -- Rock-smash rocks share SPRITE_BOULDER with Strength boulders; the
  -- extractor now flags them from MAPOBJECT_MOVEMENT and Map.isPushable
  -- rejects them, so there is nothing to detect here.
  -- BIT_STRENGTH_ACTIVE (wStatusFlags1): set only by the party-menu
  -- STRENGTH action on this map and cleared on every map load.
  -- push_boulder.asm TryPushingBoulder gates on nothing else -- it never
  -- re-checks the party's moves or badges at push time, so once STRENGTH
  -- is activated any party member can push (even if the STRENGTH-knowing
  -- mon is later boxed/swapped out).
  -- WHAT ARMS A PUSH, on a cartridge that keeps it somewhere else.
  --
  -- Gen 1 and Gen 2 hold it in a RAM bit the party menu sets
  -- (BIT_STRENGTH_ACTIVE), which is what self.strengthActive is.  Emerald
  -- holds it in a SAVE FLAG and the BOULDER'S OWN SCRIPT sets it: press A on
  -- the boulder, say yes, and the far arm of the std script does `setflag`.
  -- Nothing in this port ever set the engine bit on a Gen 3 map, so no
  -- boulder in Hoenn could be pushed no matter what the player did -- and
  -- the flag was sitting there in the save the whole time.
  local armed = self.strengthActive
  if not armed and GameVersion.isGen3() then
    local flag = Game.data.constants and Game.data.constants.gen3StrengthFlag
    armed = flag ~= nil and Game.save.flags ~= nil
            and Game.save.flags[("FLAG_G3_%04X"):format(flag)] == true
  end
  if not armed then return false end
  -- The two-attempt arming is Gen 1 only: pokered's BIT_TRIED_PUSH_BOULDER
  -- makes the first bump a no-op, but GSC's .CheckStrengthBoulder -- and
  -- Emerald's TryPushBoulder -- push straight away on the first bump.
  if GameVersion.isGen1() then
    if self.boulderTried ~= npc then
      self.boulderTried = npc
      return false -- first attempt only arms the push
    end
  end
  local bx, by = Collision.target(fx, fy, dir)
  if not self.map:inBounds(bx, by) then self.boulderTried = nil return false end
  if not self.map:isWalkableCell(bx, by) then
    -- boulders may be pushed into holes/switch spots that aren't walkable
    if not self.map:isWarpTileCell(bx, by) then
      self.boulderTried = nil
      return false
    end
  end
  if Collision.occupied(self.entities, bx, by, npc) then
    self.boulderTried = nil
    return false
  end
  require("src.core.Sound").play(Game.data, "Push_Boulder")
  self:scriptMove(npc, dir, 1, function()
    self.boulderTried = nil
    -- dust smoke + SFX_CUT once the boulder settles (DoBoulderDustAnimation)
    self:startDustAnim(fx, fy, function()
      require("src.core.Sound").play(Game.data, "Cut")
    end)
    if self:gen2BoulderIntoPit(npc) then return end
    if self:boulderIntoHole(npc) then return end
    Runtime.emit("world.boulder_moved", { mapId = self.map.id, npcId = npc.id,
                                          x = npc.cellX, y = npc.cellY })
    local hooks = mapScripts.get(self.map.id)
    if hooks and hooks.onBoulderMoved then
      hooks.onBoulderMoved(Game, self, npc)
    end
  end)
  return true
end

-- Gen2's boulder-into-hole, the stone table (CmdQueue_StoneTable /
-- HandleStoneQueue).  A map that has holes registers a
-- `stonetable <warp id>, <object event id>, <script>` row per boulder from
-- its MAPCALLBACK_CMDQUEUE callback (see Commands.g2_stonetable); the ROM
-- polls every object struct each frame for a strength boulder that is
-- standing still on a pit tile and runs the row whose warp and object both
-- match.  That script is what makes the boulder vanish, clears the event
-- hiding its twin on the floor below, shakes the screen and prints "The
-- boulder fell through."  Without it the Ice Path boulders simply parked on
-- the holes and the puzzle could not be finished.
--
-- Ice Path B1F pairs boulders 1-4 with warps 3-6, so matching on both is
-- what keeps a boulder shoved down the wrong hole from opening the wrong
-- floor; the ROM leaves such a boulder sitting there until the player exits
-- and the map's objects respawn where they started.
function OverworldState:gen2BoulderIntoPit(npc)
  if not GameVersion.isGen2() then return false end
  local stones = self.stoneTable
  if not (stones and self.map and stones.mapId == self.map.id) then return false end
  if not Map.gen2IsPit(self.map:cellTile(npc.cellX, npc.cellY)) then return false end
  local warp = self.map:warpAtCell(npc.cellX, npc.cellY)
  if not warp then return false end
  -- object_const_def counts from 2 (0 is the player), while the extractor
  -- numbers object_events from 1 -- the same +1 Gen2Commands.objectSlot undoes.
  local objectId = (npc.def and npc.def.index or 0) + 1
  for _, row in ipairs(stones.rows) do
    if row.warp == warp.index and row.object == objectId then
      local rows = require("src.script.Gen2ScriptVM").compile(Game.data, row.script)
      if not rows then return false end
      self:queueScript(rows, { mapId = self.map.id })
      return true
    end
  end
  return false
end

-- The dust puff (engine/overworld/dust_smoke.asm AnimateBoulderDust):
-- the 8x8 smoke tile drawn as a 2x2 block over the vacated cell,
-- flickering for 8 steps of ~4 frames.
function OverworldState:startDustAnim(cx, cy, onDone)
  self.dustAnim = { x = cx, y = cy, frames = 32, onDone = onDone }
end

-- TWO VOCABULARIES FOR THE SAME FOUR DIRECTIONS, and they never met.
--
-- The tileset's ledge table names its directions the way the CARTRIDGE does:
-- MB_JUMP_EAST, MB_JUMP_SOUTH -- so the extracted table reads
-- `[0x3B] = "south"`.  Movement here names them the way the PLAYER'S INPUT
-- does: up, down, left, right.  The test below compared one against the other
-- and, of course, never matched -- and then took the early return that says
-- "a dataset that names its ledges by behaviour has said all it has to say",
-- so it did not fall through to anything either.
--
-- The result was the exact bug the table was added to fix, still standing
-- with the table in place: every ledge in Hoenn a wall, no route down off any
-- terrace in the region.  Both halves were right on their own and the join
-- was never driven.
--
-- So the join is one function, and it accepts either word.  A dataset or a
-- mod may say "north" or "up" and mean the same thing.
local LEDGE_DIRECTIONS = {
  north = "up", south = "down", west = "left", east = "right",
  up = "up", down = "down", left = "left", right = "right",
}

local function ledgeDirection(word)
  return word and LEDGE_DIRECTIONS[word] or nil
end

-- The eight Gen 3 ledge behaviours, by the direction you must be walking to
-- take them (metatile_behaviors.h). The four diagonals are listed under the
-- axis a cardinal input can satisfy: Emerald lets a diagonal ledge be entered
-- from either of its two components, and up/down is the one this engine's
-- movement can express.
local GEN3_LEDGE_BEHAVIOURS = {
  [0x38] = "right",   -- MB_JUMP_EAST
  [0x39] = "left",    -- MB_JUMP_WEST
  [0x3A] = "up",      -- MB_JUMP_NORTH
  [0x3B] = "down",    -- MB_JUMP_SOUTH
  [0x3C] = "up",      -- MB_JUMP_NORTHEAST
  [0x3D] = "up",      -- MB_JUMP_NORTHWEST
  [0x3E] = "down",    -- MB_JUMP_SOUTHEAST
  [0x3F] = "down",    -- MB_JUMP_SOUTHWEST
}

-- Ledge hops (data/tilesets/ledge_tiles.asm): standing tile + ledge tile
-- in front + matching input direction -> jump two cells.
function OverworldState:checkLedgeHop(dir)
  local p = self.player
  local tileset = self.map.def.tileset
  local standing = self.map:cellTile(p.cellX, p.cellY)
  local fx, fy = Collision.target(p.cellX, p.cellY, dir)
  if not self.map:inBounds(fx, fy) then return false end
  local front = self.map:cellTile(fx, fy)

  -- A GEN 3 LEDGE IS A PROPERTY OF THE TILE IN FRONT, not of a pair.
  --
  -- Gen 1 and Gen 2 decide a hop from (tile you stand on, tile in front,
  -- direction) because their tilesets have no room to say more.  Gen 3 says
  -- it outright: the metatile's behaviour byte IS "you jump this, eastward".
  -- Nothing derived a pair table for Hoenn, so field.ledges was empty and
  -- every ledge in the region was simply a wall -- there was no route down
  -- off any terrace in the game.
  --
  -- cellBehaviour rather than cellTile because a ledge is blocked, and
  -- cellTile answers $FF for anything blocked.
  --
  -- ...AND NOTHING EVER SUPPLIED THE TABLE. `field.ledgeBehaviours` is read
  -- here and written nowhere: no importer produces it and no dataset ships
  -- one, so `byBehaviour` was nil on every map in the game and Hoenn fell
  -- through to the pair tables below -- which are Gen 1 and Gen 2 rows keyed
  -- by tile id, and match nothing on a Gen 3 pair. Every ledge in Hoenn was
  -- a wall you could not hop.
  --
  -- The cartridge's own answer is a fixed run of eight behaviour bytes
  -- (metatile_behaviors.h, MB_JUMP_EAST through MB_JUMP_SOUTHWEST), so it is
  -- stated here rather than derived. A dataset that ships its own table
  -- still wins; this only fills the gap. Gated on the pair shape -- 2x2
  -- tiles to a metatile, one collision cell -- because those byte values
  -- mean something else entirely in Kanto and Johto.
  local byBehaviour = Game.data.field and Game.data.field.ledgeBehaviours
  if not byBehaviour then
    local ts = self.map.tileset
    if ts and tonumber(ts.blockTiles) == 2 and tonumber(ts.blockCells) == 1
       and ts.collision then
      byBehaviour = GEN3_LEDGE_BEHAVIOURS
    end
  end
  if byBehaviour then
    local behaviour = self.map:cellBehaviour(fx, fy)
    if behaviour and ledgeDirection(byBehaviour[behaviour]) == dir then
      return self:startLedgeHop(dir, fx, fy)
    end
    -- a dataset that names its ledges by behaviour has said all it has to
    -- say; the pair tables below are the older generations' answer
    return false
  end
  if self:gen2LedgeAllows(standing, dir) then
    return self:startLedgeHop(dir, fx, fy)
  end
  -- a row without a tileset applies everywhere; the vanilla rows are all
  -- OVERWORLD, which is what the deleted hard gate used to say
  for _, ledge in ipairs(Game.data.field.ledges or {}) do
    if (ledge.tileset or "OVERWORLD") == tileset
       and ledge.facing == dir and ledge.input == dir
       and ledge.standingTile == standing and ledge.ledgeTile == front then
      return self:startLedgeHop(dir, fx, fy)
    end
  end
  return false
end

-- Gen2 puts the hop on the tile the player is STANDING on, not the one in
-- front: DoPlayerMovement.TryJump reads wPlayerTileCollision, and
-- CollisionPermissionTable gives $a0-$af permission $00, so the ledge lip is
-- ordinary walkable ground you step onto first (field.ledgeHops, keyed by
-- collision class).
function OverworldState:gen2LedgeAllows(standing, dir)
  local hops = Game.data.field and Game.data.field.ledgeHops
  local dirs = hops and hops[standing]
  if not dirs then return false end
  for _, allowed in ipairs(dirs) do
    if allowed == dir then return true end
  end
  return false
end

function OverworldState:startLedgeHop(dir, fx, fy)
  local p = self.player
  local lx, ly = Collision.target(fx, fy, dir)
  if not self.map:inBounds(lx, ly) then
    -- The landing is on the CONNECTED map.  pokered never checks where a
    -- hop lands (engine/overworld/ledges.asm HandleLedges just simulates
    -- two presses in the hop direction) and the connection strip is
    -- loaded, so ROUTE_4's bottom-row ledge at (12,17)/(13,17) really
    -- does drop onto ROUTE_3 row 0 (south connection, offset -25 ->
    -- destX = curX + 50; ROUTE_3 (62,0)/(63,0) are walkable $39/$23):
    -- the one-way shortcut off the Mt Moon plaza that the in-bounds gate
    -- was silently refusing, which is issue #223.  Validate the seam
    -- cell the way crossConnection does, hop the first cell onto the
    -- ledge tile, and hand the second to checkEdgeExit, which owns the
    -- crossing.
    local dest, ts, cx, cy = self:connectionLanding(dir)
    if not (dest and Map.defPassable(dest, ts, cx, cy, p.surfing)) then
      return false
    end
    require("src.core.Sound").play(Game.data, "Ledge")
    p.hopFrames, p.hopTotal = 32, 32 -- jump arc (cosmetic)
    self:scriptMove(p, dir, 1, function() self:checkEdgeExit(dir) end)
    return true
  end
  if not Collision.occupied(self.entities, lx, ly, p)
     and self.map:isWalkableCell(lx, ly) then
    require("src.core.Sound").play(Game.data, "Ledge")
    p.hopFrames, p.hopTotal = 32, 32 -- jump arc (cosmetic)
    self:scriptMove(p, dir, 2)
    return true
  end
  return false
end

-- walking off the map edge: connection crossing or edge warp (exit mats)
function OverworldState:checkEdgeExit(dir)
  local p = self.player
  local tx, ty = Collision.target(p.cellX, p.cellY, dir)
  if self.map:inBounds(tx, ty) then return false end

  local w = Warp.onEdge(self.map, p.cellX, p.cellY, dir)
  if w then
    -- ...but only with BIT_STANDING_ON_WARP set: a staircase tile clears it,
    -- so pushing into the edge beside one bonks (SFX + walk-in-place) instead
    -- of bouncing floors (issue #230), while the door mat you warped in on
    -- keeps it and exits on that same tile (issue #378).
    if not self:canCollisionWarp() then return false end
    self:takeWarp(w.def)
    return true
  end

  local conn = self.map:connection(COMPASS[dir])
  if conn then
    return self:crossConnection(dir, conn)
  end
  return false
end

-- Landing cell on the connected map for a step off this map's edge in
-- `dir` (same math as crossConnection).  Returns destDef, tilesetDef, x, y
-- or nil when there is no usable connection.
function OverworldState:connectionLanding(dir)
  -- WHICH connection on this edge, not just the first.
  --
  -- GetIncomingConnection (0x088950) searches for the one whose strip covers
  -- the player's position along the seam.  Route 111's west edge carries two
  -- (Route 113 at offset 0, Route 112 at 20) and so does Route 124's east
  -- (Route 125, then Mossdeep at 40); taking the first left both one-way --
  -- the neighbour was drawn across the seam and could not be entered.
  local horizontal = (dir == "left" or dir == "right")
  local p = self.player
  local coord = horizontal and p.cellY or p.cellX
  -- srcMax and destMax are the map's FULL extent, not extent-1.
  -- IsPosInIncomingConnectingMap (0x080889A8) hands
  -- IsCoordInIncomingConnectingMap the layout's `width`/`height` straight
  -- off the header, and the comparison it makes is `coord <= min(srcMax,
  -- destMax + offset)` -- inclusive.  Taking one off both ends refused the
  -- last cell of every seam.
  local srcMax = horizontal and self.map.heightCells or self.map.widthCells
  local function extentOf(id)
    local m = Game.data.maps[id]
    local mts = m and Game.data.tilesets[m.tileset]
    if not (m and mts) then return nil end
    local c = math.max(1, math.floor(tonumber(mts.blockCells) or 2))
    return (horizontal and m.height or m.width) * c
  end
  local conn = self.map:connectionFor(COMPASS[dir], coord, srcMax, extentOf)
  if not conn then return nil end
  local dest = Game.data.maps[conn.map]
  if not dest then return nil end
  local ts = Game.data.tilesets[dest.tileset]
  if not ts then return nil end
  local p = self.player
  -- A BLOCK IS NOT ALWAYS TWO CELLS.  A Game Boy block is 32 pixels and holds
  -- four 16-pixel cells, so a map `width` in blocks is twice that in cells and
  -- a connection offset counted in blocks doubles too -- which is what these
  -- multiplications are.  A Gen 3 metatile IS the cell, and with the twos
  -- left in, every landing on a connected Hoenn map came out at double the
  -- coordinate, fell outside the destination, failed the passability check
  -- and read as an invisible wall along the seam.  The tileset says how many
  -- cells its blocks hold; a dataset that does not say keeps the Game Boy's.
  local cells = math.max(1, math.floor(tonumber(ts.blockCells) or 2))
  local destW, destH = dest.width * cells, dest.height * cells
  local shift = conn.offset * cells
  local x, y
  if dir == "up" then
    x, y = p.cellX - shift, destH - 1
  elseif dir == "down" then
    x, y = p.cellX - shift, 0
  elseif dir == "left" then
    x, y = destW - 1, p.cellY - shift
  else
    x, y = 0, p.cellY - shift
  end
  -- AND NOTHING IS CLAMPED.
  --
  -- The cartridge has no clamp: a step off the edge that lands outside the
  -- neighbour's strip reads the map's BORDER BLOCK instead, which
  -- MapGridGetCollisionAt (0x080881B0) returns OR'd with the collision mask
  -- -- always impassable.  Clamping instead let the player walk through what
  -- should be a wall on 334 edge cells across nine seams and arrive
  -- displaced by up to forty cells.  Answering nil is that wall.
  if x < 0 or x >= destW or y < 0 or y >= destH then return nil end
  return dest, ts, x, y, conn
end

-- Map connections: the connected map's strip offset is in blocks; arriving
-- coordinates follow destX = curX - offset*2 (see docs/extraction-notes.md).
-- The crossing scrolls continuously: the map data swaps while the player
-- is placed one cell before the entry point (their old world position,
-- which the neighbor strips render identically) and walks the seam step.
function OverworldState:crossConnection(dir, conn)
  -- THE ROW THAT WAS SELECTED, not the first one on the edge.
  --
  -- `checkEdgeExit` hands in `map:connection(dir)`, which is the edge's
  -- FIRST connection -- but `connectionLanding` re-runs the cartridge's
  -- own search and may well pick the second.  Loading the first map at the
  -- second map's landing coordinates is what put the player out of bounds
  -- walking west off Route 111 and east off Route 124: the only two edges
  -- in Hoenn that carry two connections, and the only two that could show
  -- it.  `landed` is the row the coordinates belong to.
  local dest, ts, x, y, landed = self:connectionLanding(dir)
  if not dest then
    Logger.warn("connection to unknown map %s", tostring(conn and conn.map))
    return false
  end
  conn = landed or conn
  local p = self.player
  -- pokered's collision check reads the NEIGHBOR strip's tile bytes, so
  -- stepping off the edge onto a solid tile of the connected map bumps
  -- exactly like an in-map wall. Without this read, Pallet's south
  -- shore (land at x2-3) walked straight onto ROUTE_21 (3,0) -- a
  -- collision tile -- stranding the player on a cell no walk can leave.
  if not Map.defPassable(dest, ts, x, y, p.surfing) then
    return false
  end
  -- keepMusic: defer PlayMapMusic until the seam step lands.  Starting a
  -- new chip song inside setMap used to hitch the render thread (~200ms)
  -- so FixedStep catch-up ate the walk frames (issue #93).  Threaded synth
  -- removed most of that hitch; discarding catch-up + deferring the song
  -- still protects the visible step when neighbor rebuild or the sync
  -- fallback stalls, and avoids the rare one-frame volume spike from a
  -- song swap mid-step.
  -- Yellow's follower crosses the seam as one continuous walk, so hand the
  -- live instance through setMap (which rebuilds self.npcs) instead of
  -- letting it respawn behind the player (#427)
  local PikachuFollower = require("src.world.PikachuFollower")
  local pika = PikachuFollower.current(self)
  local fromX, fromY = p.cellX, p.cellY
  self:setMap(conn.map, x, y, p.facing,
              { seamless = true, keepMusic = true, keepPikachu = pika })
  self.pendingSeamMusic = conn.map
  -- place the player one cell before the seam (their old world spot,
  -- which the neighbor strip renders identically) and start the step
  -- into the new map RIGHT NOW so there is no one-frame stall at the
  -- boundary (updateScriptMoves already ran this frame; kicking the
  -- move here lets player:update animate the first pixel immediately)
  local d = DIRVEC[dir]
  p.cellX, p.cellY = x - d[1], y - d[2]
  p.px, p.py = p.cellX * 16, p.cellY * 16
  -- same translation for the follower and the cell it is chasing
  PikachuFollower.rebase(self, p.cellX - fromX, p.cellY - fromY)
  self.camera:follow(p.px, p.py)
  p.facing = dir
  p.targetX, p.targetY = x, y
  p.moving = true
  p.progress = 0
  -- fresh walk-cycle clock so the seam step always shows leg frames
  -- (mid-cycle stand phase would otherwise look like a slide)
  p.animClock = 0
  p.stepFramesCur = Game.save.onBike
    and (FieldDefaults.world(Game.data, "bikeStepFrames") or 8)
    or (OverworldState.runFrames and OverworldState.runFrames(self))
    or (FieldDefaults.world(Game.data, "stepFrames") or 16)
  require("src.core.FixedStep"):discardCatchup()
  return true
end

-- RUNNING.  Prism is the only game here that has it, and it has no running
-- SHOES either: DoPlayerMovement's .walk branch falls straight through to
-- .run whenever B is held, gated on nothing but ENGINE_POKEMON_MODE
-- (engine/player_movement.asm .maybe_run).  So there is no item to find and
-- no flag to set -- the port simply had no run state, because Gold and
-- Crystal have none to port.
--
-- Returns the run step length, or nil to leave the speed alone.  Riding and
-- surfing answer first at the call site; playing AS a Pokemon is the one
-- case the ROM itself refuses, and it refuses it here for the same reason.
-- WHY THE SHOES DID OR DID NOT WORK, said once per answer.
--
-- Reported from play: "I can sprint without the running shoes".  Four
-- separate things decide it and every one of them is invisible from inside
-- the game, so a run that should have been refused and a refusal that should
-- have been a run look exactly alike.  This names whichever one answered, and
-- only when the answer changes, so a walk across Hoenn is one line and not
-- sixty a second.
function OverworldState:noteRunGate(why)
  if self.runGateSaid == why then return why end
  self.runGateSaid = why
  Logger.debug("gen3 running: %s", why)
  return why
end

function OverworldState:runFrames()
  local frames = FieldDefaults.world(Game.data, "runStepFrames")
  if type(frames) ~= "number" then
    self:noteRunGate("this dataset has no run speed at all")
    return nil
  end
  local ok, GV = pcall(require, "src.core.GameVersion")
  local version = ok and GV and GV.get and GV.get() or nil
  local gen3 = ok and GV and GV.isGen3 and GV.isGen3()

  -- EMERALD HAS RUNNING SHOES, and they are a flag rather than an item.
  --
  -- Two gates, and the cartridge means both of them:
  --
  --   * the SHOES.  Mom hands them over after the lab, and the script that
  --     does it is the only one in the game that prints "switched shoes with
  --     the RUNNING SHOES" -- which is how the extractor finds the flag,
  --     since nothing on the cartridge names it.
  --   * the MAP.  Bit 2 of a map header's flag byte is "you may run here",
  --     and it is not set everywhere: 228 of the region's 519 maps allow it.
  --     Running inside a Pokemon Centre is a Gen 4 thing.
  if gen3 then
    if not (self.map and self.map.def and self.map.def.allowRunning) then
      self:noteRunGate("this map's header does not allow it")
      return nil
    end
    local flagId = (Game.data.constants or {}).gen3RunningShoesFlag
    if flagId then
      local flag = ("FLAG_G3_%04X"):format(flagId)
      if not (Game.save.flags and Game.save.flags[flag]) then
        self:noteRunGate(("the SHOES flag %s is not set"):format(flag))
        return nil
      end
    else
      -- the one case that let a player run before Mom handed them over: with
      -- no flag placed there is nothing to check, and this used to fall
      -- straight through to "yes"
      self:noteRunGate("this cache carries no running-shoes flag, so the "
                       .. "shoes cannot be required -- re-import to place it")
    end
    --   * and the GROUND.  MetatileBehavior_IsRunningDisallowed names seven
    --     behaviours the shoes do not work on: long grass, the hot springs,
    --     the four Pacifidlog logs and the plain no-running marker.  Long
    --     grass is the one that shows -- 1,381 cells of it, and the cartridge
    --     makes you wade through every one.  Read off the cell the player is
    --     STANDING on, which is the cell the cartridge reads.
    if self.map and self.map.runningBlockedAt and self.player
       and self.map:runningBlockedAt(self.player.cellX, self.player.cellY) then
      self:noteRunGate("the ground here is one of the seven the shoes do not "
                       .. "work on")
      return nil
    end
  elseif version ~= "prism" then
    return nil
  end
  if self.player and self.player.surfing then return nil end
  if not (Game.input and Game.input:isDown("b")) then return nil end
  self:noteRunGate("running")
  -- playing AS a Pokemon is Prism's own refusal and does not apply to Hoenn
  if not gen3 then
    local okf, Flags = pcall(require, "src.script.Flags")
    if okf and Flags and Flags.get
       and Flags.get(Game.save, "ENGINE_POKEMON_MODE") then return nil end
  end
  return frames
end

-- ItemUseSurfboard's simulated pad press: step onto the facing cell, or
-- cross a map connection when that cell is off this map's edge (Cinnabar
-- east coast -> Route 20 water, and the reverse dismount ashore).
function OverworldState:stepForwardOrCrossEdge(dir)
  dir = dir or self.player.facing
  local fx, fy = Collision.target(self.player.cellX, self.player.cellY, dir)
  if not self.map:inBounds(fx, fy) then
    return self:checkEdgeExit(dir)
  end
  self:scriptMove(self.player, dir, 1)
  return true
end

-- IsNextTileShoreOrWater across a connection strip: pokered loads the
-- neighbor's tiles into the border, so wTileInFrontOfPlayer is the
-- connected map's tile even when the facing cell is off this map.
-- Shore/water classification still uses THIS map's tileset rules
-- (SHIP_PORT's $32 dock exception), matching the asm.
function OverworldState:facingIsShoreOrWater()
  -- the tileset water-list gate is Gen 1/2's; a Gen 3 map answers from its
  -- own cells and has no such list
  if not (GameVersion.isGen3() or self:tilesetHasWater()) then return false end
  local fx, fy = self.player:facingCell()
  if self.map:inBounds(fx, fy) then
    return self.map:isWaterCell(fx, fy)
  end
  local dest, ts, x, y = self:connectionLanding(self.player.facing)
  if not dest then return false end
  if dest.elevationCells then
    return Map.defIsWaterCell(dest, ts, x, y)
  end
  local tile = Map.defCellTile(dest, ts, x, y)
  if tile == nil then return false end
  return self.map.waterTiles[tile] or false
end

-- tryToStopSurfing land check, including a land landing across a map
-- connection (surf off Cinnabar's east coast water back onto the coast).
function OverworldState:facingIsLandDismount()
  local p = self.player
  local fx, fy = p:facingCell()
  if self.map:inBounds(fx, fy) then
    return self.map:isWalkableCell(fx, fy)
       and Collision.canMove(self.map, self.entities, p, p.facing)
  end
  local dest, ts, x, y = self:connectionLanding(p.facing)
  if not dest then return false end
  if not Map.defIsWalkableCell(dest, ts, x, y) then return false end
  -- IsSpriteInFrontOfPlayer2: no current-map sprite can sit past the edge
  return not Collision.occupied(self.entities, fx, fy, p)
end

-- -------------------------------------------------------------------------
-- interactions
-- -------------------------------------------------------------------------

-- HM field moves are gated by badges like the original
-- (constants.hmBadges; distinct from constants.hmMoves, the forget gate).
-- Gen 1 allows field use from fainted party members (party menu + name
-- lookup for Cut/Surf messages); do not require mon.hp > 0 here.
-- THE BADGE A GEN 3 FIELD MOVE COSTS.
--
-- Hoenn's eight badges are FLAGS, and which flag gates which move is not
-- written down anywhere on the cartridge -- the extractor places the block
-- by reading the three field-move scripts that check one (see
-- fieldMoveGates).  A dataset with no placement charges nothing, so an older
-- import still hands the moves over rather than refusing all eight.
local function gen3BadgeHeld(moveId)
  local gate = Game.data.constants and Game.data.constants.gen3FieldMoves
  local entry = gate and gate[moveId]
  if not (entry and entry.badgeFlag) then return true end
  local key = ("FLAG_G3_%04X"):format(entry.badgeFlag)
  return (Game.save.flags and Game.save.flags[key]) and true or false
end

local function partyKnowsVanilla(moveId)
  -- GEN 3 DOES NOT USE THE GEN 1 BADGE TABLE, and asking it was quietly
  -- fatal: field.hmBadges is R/B's list -- SURF costs the SOULBADGE, CUT the
  -- CASCADEBADGE -- and Badges.has answers for a badge no Hoenn save will
  -- ever hold.  Every HM in the region was refused before the party was even
  -- looked at, which reads exactly like "the prompt does not appear".
  if GameVersion.isGen3() then
    if not gen3BadgeHeld(moveId) then return nil end
  else
    local gate = (FieldDefaults.constant(Game.data, "hmBadges") or {})[moveId]
    local badge = gate and gate.badge
    -- R/B hands badges over as bag items, Gen2 as engine flags; Badges.has
    -- reads either, so this one call covers both
    if badge and not Badges.has(Game.save, { id = badge }) then
      return nil
    end
  end
  for _, mon in ipairs(Game.save.party) do
    for _, mv in ipairs(mon.moves) do
      if mv.id == moveId then return mon end
    end
  end
  return nil
end

function OverworldState:partyKnows(moveId)
  -- a mod may unlock a field move another way (an HM in the bag, a rental
  -- mon); next_ is the whole vanilla check, so calling it first keeps
  -- vanilla answers winning
  if Runtime.wantsHook("fieldmove.eligibility") then
    return Runtime.call("fieldmove.eligibility", partyKnowsVanilla, moveId,
      { save = Game.save, data = Game.data })
  end
  return partyKnowsVanilla(moveId)
end

-- IsSurfingPikachuInParty (home/map_objects.asm): when the SURF-mon
-- is a Pikachu, pose() renders the Pikachu surf sprite.  Called at
-- every surf-state change so a reloaded save picks the right sheet
-- after a party change.  No-op when not surfing.
function OverworldState:syncSurfingPikachu()
  local p = self.player
  if not p then return end
  if not p.surfing then
    p.surfingPikachu = false
    return
  end
  local mon = self:partyKnows("SURF")
  p.surfingPikachu = mon ~= nil and mon.species == "PIKACHU" or false
end

-- The rejection loop shared by the Good and Super Rods
-- (item_effects.asm ItemUseGoodRod .RandomLoop / ReadSuperRodData): an
-- odd random byte is no bite; otherwise a 2-bit pick rerolls until it
-- lands inside the group, so the bite odds are size/(size+4)
-- (1/3 for the Good Rod's pair, up to 1/2 for 4-mon Super Rod groups).
local function rollFishingGroup(group)
  while true do
    local r = love.math.random(0, 255)
    if r % 2 == 1 then return nil end
    local pick = math.floor(r / 2) % 4
    if pick < #group then
      local slot = group[pick + 1]
      return { species = slot.species, level = slot.level }
    end
  end
end

-- Gen2 fishing (engine/events/fish.asm `Fish`), which has nothing to do with
-- the Gen1 rules below it.  The map header carries a FISHGROUP_*; the group
-- carries a bite chance and one row list per rod; a row is
-- { chance, species, level }, walked until the rolled byte is <= chance.  A
-- row with no species names a TimeFishGroups index instead and the mon comes
-- from the day or nite half of that pair.
--
-- Before this existed the Gen2 games ran the Gen1 table in FieldDefaults:
-- the Old Rod always hooked a level 5 MAGIKARP and the Super Rod -- whose
-- Gen1 form is a per-map list this cart does not have -- returned nil, so
-- every Super Rod cast anywhere printed "Not even a nibble!".
-- Keyed by BOTH spellings, because the caller hands over whatever the bag row
-- was and a Gen2 import names its items by NUMBER.  BagMenu does
-- `ow:goFishing(id)` with the item id straight off the row, and on Gold /
-- Silver / Crystal that is ITEM_058 / ITEM_059 / ITEM_061 (OLD_ROD $3a,
-- GOOD_ROD $3b, SUPER_ROD $3d in constants/item_constants.asm) -- never the
-- pokered-style name.
--
-- So this table missed on every cast: `key` came back nil, `entry` with it, and
-- gen2FishingRoll returned "no bite, handled" for EVERY ROD ON EVERY MAP.  That
-- is the "... Not even a nibble!" that survived the FishGroups indexing fix --
-- the roll never reached the group table at all, which is also why fixing that
-- table appeared to change nothing.  The rod animation still played, because
-- goFishing sets self.fishing after the roll regardless of the verdict.
local GEN2_ROD_KEY = {
  OLD_ROD = "old", GOOD_ROD = "good", SUPER_ROD = "super",
  ITEM_058 = "old", ITEM_059 = "good", ITEM_061 = "super",
}

-- A CACHE WITH NO FISH GROUPS IS A CACHE, NOT A ROD THAT MISSES.
--
-- Without field.fishGroups every cast comes back empty, and empty is exactly
-- what a legitimate miss looks like -- so the symptom is "fishing never works
-- here" and there is nothing anywhere to say why.  The usual cause is a cache
-- imported before the fishing stage existed, and the fix is to re-import, so
-- the message says so.  Once per session: a cast is a per-step event and this
-- would otherwise fill the log.
local warnedNoFishGroups = false

local function gen2FishingRoll(data, rod, mapDef, tod)
  local field = data.field
  local groups = field and field.fishGroups
  if not groups then
    if not warnedNoFishGroups then
      warnedNoFishGroups = true
      Logger.warn("fishing: this cache carries no fish groups, so every cast "
                    .. "comes up empty -- re-import the ROM to get them")
    end
    return nil, false
  end
  local key = GEN2_ROD_KEY[rod]
  local entry = key and mapDef and mapDef.fishGroup and groups[mapDef.fishGroup]
  local rows = entry and entry.rods and entry.rods[key]
  if not (rows and #rows > 0) then return nil, true end
  -- `call Random / cp [hl] / jr nc, .no_bite`: the roll must come in UNDER
  -- the group's chance byte.
  if love.math.random(0, 255) >= (entry.chance or 0) then return nil, true end
  local roll = love.math.random(0, 255)
  for _, row in ipairs(rows) do
    if roll <= row.chance then
      if row.timeGroup then
        local pair = field.timeFishGroups and field.timeFishGroups[row.timeGroup]
        local slot = pair and (tod == "NITE" and pair.nite or pair.day)
        if not slot then return nil, true end
        return { species = slot.species, level = slot.level }, true
      end
      return { species = row.species, level = row.level }, true
    end
  end
  return nil, true
end

-- Exposed for the headless drivers: the roll with no UI attached.
OverworldState.rollFishingForTest = function(data, rod, mapDef, tod)
  return (gen2FishingRoll(data, rod, mapDef, tod))
end

-- field.fishing: `always` hooks that catch every time (the Old Rod),
-- `pool` a fixed candidate list, `perMap` the field key holding per-map
-- groups.  The rejection-loop odds above stay engine behavior.
local function fishingPool(data, rod, mapId)
  local def = (FieldDefaults.field(data, "fishing") or {})[rod]
  if not def then return nil end
  if def.pool then return def.pool end
  if def.perMap then
    local groups = data.field[def.perMap]
    return groups and groups[mapId]
  end
  return nil, def.always
end

local function catchFrom(pool, always)
  if always then return { species = always.species, level = always.level } end
  if pool and #pool > 0 then return rollFishingGroup(pool) end
  return nil
end

-- Fishing (engine/items/item_effects.asm FishingInit + engine/overworld):
-- Old Rod always hooks a L5 Magikarp; Good Rod bites ~1/3 for
-- Goldeen/Poliwag L10; Super Rod uses the map's extracted fishing group
-- (no group means "Not even a nibble!").
function OverworldState:goFishing(rod)
  local pool, always = fishingPool(Game.data, rod, self.map.id)
  local enc
  -- Gen2 carts answer from the ROM's own fish groups; `handled` is true as
  -- soon as this import produced them, so a Gen2 no-bite stays a no-bite
  -- rather than falling through to the Gen1 Magikarp.
  local gen2Enc, handled = gen2FishingRoll(Game.data, rod, self.map.def,
    OverworldState.clockTimeOfDay and OverworldState.clockTimeOfDay() or self.tod)
  if Runtime.wantsHook("encounter.fishing") then
    -- the chain may inspect or replace the candidate list before the roll
    enc = Runtime.call("encounter.fishing", function(_, _, candidates)
      if handled then return gen2Enc end
      return catchFrom(candidates, always)
    end, rod, self.map.id, pool)
  elseif handled then
    enc = gen2Enc
  else
    enc = catchFrom(pool, always)
  end
  -- the bobber waits a beat before the verdict (the original's
  -- FishingInit dot animation); the rod pose draws in the meantime
  self.fishing = { facing = self.player.facing }
  self.player.fishing = true
  Game.stack:push(TextBox.new(Game, ". . .", function()
    -- FishingAnim (engine/overworld/player_animations.asm) holds
    -- BIT_LEDGE_OR_FISHING -- the rod OAM and the fishing pose -- through
    -- PrintText and only clears it once the verdict box is done, so the rod
    -- must NOT vanish with the dots box (#321).
    if not enc then
      Game.stack:push(TextBox.new(Game, Strings("Not even a nibble!"), function()
        -- the rod OAM goes out with the verdict box (res BIT_LEDGE_OR_FISHING
        -- straight after PrintText) but the player keeps the patched tiles
        -- until the overworld reloads them a few frames later
        -- (RestoreScreenTilesAndReloadTilePatterns, home/palettes.asm ->
        -- ReloadMapSpriteTilePatterns, home/reload_sprites.asm) -- #384
        self.fishing = nil
        self.fishPose = 10
      end))
      return
    end
    Game.stack:push(TextBox.new(Game, Strings("Oh!\nIt's a bite!"), function()
      -- the bite goes straight into battle, which reloads the sprite tiles
      self.fishing = nil
      self.player.fishing = nil
      local BattleState = require("src.battle.BattleState")
      local battle = BattleState.newWild(Game, enc.species, enc.level, { hooked = true })
      if self:inSafariGame() then
        battle:makeSafari(Game.save.safari)
      end
      battle.onFinish = function(result) self:afterBattle(result, battle) end
      self:pushBattle(battle)
    end))
  end))
end

-- StdScripts row 22 is BugContestResultsWarpScript and row 23 is
-- BugContestResultsScript.  There is no `end` between the two labels in
-- engine/events/std_scripts.asm, so the ROM falls straight from the warp into
-- the results and the decoder produces ONE script for row 22 -- the warp, the
-- judging, the prize, the party hand-back and the scene reset together.  The
-- rows are identical in Gold and Crystal.
local BUG_CONTEST_STD_WARP = 22
local BUG_CONTEST_STD_RESULTS = 23
local BUG_CONTEST_GATE = "ROUTE36_NATIONAL_PARK_GATE"
-- BugContestResultsWarpScript is `warp ROUTE_36_NATIONAL_PARK_GATE, 0, 4` then
-- `step RIGHT / step DOWN / turn_head UP`: (0, 4) is the gate's own west door,
-- so the movement leaves the player standing at (1, 5) facing up.  Only used
-- by the fallback below -- the script does its own warp when it is available.
local BUG_CONTEST_GATE_X, BUG_CONTEST_GATE_Y = 1, 5

-- Compile one of the two contest std scripts, or nil.
local function bugContestStd(index)
  local pool = Game.data and Game.data.map_scripts
  local stds = pool and pool.stds
  if not stds then return nil end
  local label = stds[index] or stds[tostring(index)]
  if type(label) ~= "string" then return nil end
  local ok, rows = pcall(require("src.script.Gen2ScriptVM").compile,
                         Game.data, label)
  return ok and rows or nil
end

-- Leaving the contest -- START menu QUIT, out of Park Balls, or the clock.
--
-- All three are the same three instructions on a cartridge.  StartMenu_Quit
-- (engine/menus/start_menu.asm:411) and both overworld exits queue
-- BugCatchingContestReturnToGateScript, which is
--
--     closetext
--     jumpstd BugContestResultsWarpScript
--
-- so the CARTRIDGE'S OWN BYTECODE does the rest, in an order that matters:
-- warp to the gate, make the other contestants appear, judge, hand over the
-- prize for the placing, give the held party back, put the caught mon in the
-- party, and only then `setscene SCENE_ROUTE36NATIONALPARKGATE_NOOP`.
--
-- Running that script rather than re-implementing it is what makes the prize
-- follow the placing and stops the officer re-arming his "are you finished?"
-- scene.  Nothing is torn down before it runs: judging needs the caught mon
-- and the rolled AI scores still on the save.
--
-- Returns true when the exit was taken.
function OverworldState:bugContestReturnToGate()
  if self.bugContestLeaving then return true end
  local rows = bugContestStd(BUG_CONTEST_STD_WARP)
  if rows then
    self.bugContestLeaving = true
    self:queueScript(rows, { mapId = self.map and self.map.id })
    return true
  end
  -- No decoded std pool (an old cache, or a hack that moved the table): warp
  -- by hand to where the script's movement would have left the player, then
  -- run the results half on its own.  startWarpTo, NOT setMap -- setMap's
  -- signature is (mapId, x, y, facing, opts) and passing an options table as
  -- `x` is what made every exit crash on `attempt to perform arithmetic on
  -- local 'x' (a table value)`.
  if not (Game.data.maps and Game.data.maps[BUG_CONTEST_GATE]) then
    Logger.warn("bug contest: no gate map to return to")
    return false
  end
  self.bugContestLeaving = true
  self:startWarpTo(BUG_CONTEST_GATE, BUG_CONTEST_GATE_X, BUG_CONTEST_GATE_Y,
                   "up", function()
    local results = bugContestStd(BUG_CONTEST_STD_RESULTS)
    if results then
      self:queueScript(results, { mapId = BUG_CONTEST_GATE })
    else
      -- last resort: at least end the run cleanly rather than stranding the
      -- player in a contest with no clock and no way out
      require("src.world.BugContest").finish(Game)
      require("src.world.BugContest").clear(Game.save)
    end
  end)
  return true
end

-- CheckBugContestTimer (04:$54A4) runs from the overworld loop, and
-- BugCatchingContestBattleScript checks wParkBallsRemaining after every
-- battle.  Both end the run the same way, through the script above.
--
-- bugContestLeaving is the re-entry guard the ROM does not need: `timedOut`
-- stays true until the results script clears the deadline, and this is polled
-- every frame, so without it the exit would fire again on the next frame and
-- queue a second copy of the whole results script.
function OverworldState:checkBugContestClock()
  local BugContest = require("src.world.BugContest")
  if not BugContest.active(Game.save) then
    -- the results script has torn the run down: the guard has done its job and
    -- must not survive into the next contest
    self.bugContestLeaving = nil
    return
  end
  if self.bugContestLeaving then return end
  if not BugContest.timedOut(Game.save) then return end
  if self.runner:isRunning() or self.transitioning then return end
  self:bugContestOver("_BugCatchingContestTimeUpText",
                      Strings("ANNOUNCER: BEEEP!\n\nTime's up!"))
end

-- The one line both endings print before the warp, over SFX_ELEVATOR_END
-- (BugCatchingContestOverScript / BugCatchingContestOutOfBallsScript,
-- engine/events/bug_contest/contest.asm:15-30).
function OverworldState:bugContestOver(textLabel, fallback)
  if self.bugContestLeaving then return end
  pcall(function() require("src.core.Sound").play(Game.data, "Elevator_End") end)
  local text = Game.data.text and Game.data.text[textLabel]
  Game.stack:push(TextBox.new(Game, text or fallback, function()
    self:bugContestReturnToGate()
  end))
end

-- Fly to a visited town (called from the party menu).

-- HOENN'S REGION MAP, from wherever asks for it: the Pokemon Centre wall, the
-- PokeNav, FLY, and the cartridge's own FieldShowRegionMap special.  Refuses
-- rather than crashing on a cache imported before the section rectangles were
-- kept, which is every Gen 3 cache built before today.
function OverworldState:openRegionMap(opts)
  if not GameVersion.isGen3() then return false end
  local constants = Game.data.constants or {}
  if not (constants.gen3MapSectionRects and constants.gen3RegionMapPlaces) then
    return false
  end
  local Gen3RegionMap = require("src.ui.Gen3RegionMap")
  Game.stack:push(Gen3RegionMap.new(Game, opts or {}))
  return true
end

-- IS THERE A BIRD TO CARRY THE PLAYER?
--
-- Kanto's fly is a bird sprite that sweeps in, and the player is hidden while
-- it does.  Hoenn's cartridge has one too, but nothing in a retail ROM NAMES
-- it, so a Gen 3 dataset carries no `playerSprites.fly` -- and hiding the
-- player for a bird that never arrives is how FLY came to look like nothing
-- happening at all.  Without one the player stays drawn and rises off the map
-- instead, which is the same departure the Teleport spin already uses.
function OverworldState:hasFlyBird()
  local id = FieldDefaults.fieldValue(Game.data, "playerSprites", "fly")
  return (id and Game.data.sprites and Game.data.sprites[id]) and true or false
end

function OverworldState:flyTo(mapId)
  -- `field` is absent on a Gen 3 cache imported before the heal-location
  -- stage existed, and indexing it was a crash rather than a refusal
  local flyWarps = (Game.data.field or {}).flyWarps or {}
  local spot = flyWarps[mapId]
  if not spot then return end
  require("src.core.Sound").play(Game.data, "Fly")
  Game.save.onBike = false
  self:clearBikeFlags() -- HandleFlyWarpOrDungeonWarp res BIT_ALWAYS_ON_BIKE
  self.player.surfing = false
  self:syncSurfingPikachu()
  -- CLOSE WHATEVER IS STILL OPEN OVER THE MAP.
  --
  -- Reported from play: "when i select fly to a location it doesnt fly until
  -- i close the start menu".  The flight is an OVERWORLD animation and the
  -- overworld does not update while a menu sits on top of it -- and the pick
  -- comes from the region map, which the party menu opened, which the START
  -- MENU opened.  The region map and the party menu close themselves; the
  -- start menu underneath them does not, so the bird sat waiting for the
  -- player to back out of a menu by hand.
  local stack = Game.stack
  local guard = 0
  while stack and stack.top and stack:top() and stack:top() ~= self
        and guard < 8 do
    stack:pop()
    guard = guard + 1
  end
  -- the bird carries the player off westward before the warp
  -- (engine/overworld/player_animations.asm LoadBirdSpriteGraphics)
  self.flyAnim = { frames = 48 }
  -- ...and with no bird, the player is the animation: the same rise the
  -- Teleport departure uses, over the same forty-eight frames, so FLY leaves
  -- the map visibly instead of the screen sitting still until it fades.
  if not self:hasFlyBird() then
    self.player.spinFrames = 48
    self.player.spinTotal = 48
    self.player.spinRise = true
    self.player.spinDrop = nil
  end
  self.player.inputLocked = true
  self.flyDest = { map = mapId, x = spot.x, y = spot.y }
end

-- Dig / Teleport / Escape Rope departure animation, then land OUTSIDE the
-- last Pokemon Center door like Fly (#196).  pokered's _LeaveMapAnim
-- (engine/overworld/player_animations.asm) plays SFX_TELEPORT_EXIT_1 and
-- spins the player while it rises up off the map (PlayerSpinWhileMovingUp)
-- before the palettes fade; Fly's bird lead-in (flyTo/flyAnim) is the
-- analogous departure this mirrors.  When the spin finishes (the teleportOut
-- countdown in OverworldState:update), warpToHealPoint pushes the fade + warp
-- with arrive="teleport" so the sprite spins back DOWN in front of the town
-- PC door.  Shared by the party-menu DIG/TELEPORT action and BagMenu's
-- ESCAPE ROPE so all three animate identically.
function OverworldState:beginTeleportOut(onDone, opts)
  if (opts and opts.escape) and not self:escapePoint() then
    if onDone then onDone() end
    return
  end
  if not (opts and opts.escape) and not Game.save.lastHeal then
    -- a save that has never visited a Pokemon Center has no heal point to
    -- warp to; skip the animation entirely (matches the old guard that did
    -- nothing when lastHeal was absent) instead of spinning into a nil warp
    if onDone then onDone() end
    return
  end
  require("src.core.Sound").play(Game.data, "Teleport_Exit1")
  self.player.surfing = false
  self:syncSurfingPikachu()
  self.player.inputLocked = true
  -- rising spin: the mirror of the arrival spin-drop set in startWarpTo, so
  -- spinRise lifts the sprite (Player:pose) while spinFrames counts down
  self.player.spinning = true
  self.player.spinTimer = 0
  self.player.spinFrames = 48
  self.player.spinTotal = 48
  self.player.spinRise = true
  self.teleportOut = { frames = 48, onDone = onDone,
                      escape = opts and opts.escape or nil }
end

function OverworldState:npcAtCell(cx, cy)
  for _, npc in ipairs(self.npcs) do
    local big = npc.big or (npc.sprite and npc.sprite.big)
      or (npc.def and (npc.def.sprite == "SPRITE_BIG_SNORLAX"
                      or npc.def.sprite == "SPRITE_BIG_LAPRAS"
                      or npc.def.big))
    if big then
      local x, y = npc.cellX, npc.cellY
      if x and y and cx >= x and cx <= x + 1 and cy >= y and cy <= y + 1 then
        return npc
      end
    elseif (npc.cellX == cx and npc.cellY == cy) or
           (npc.targetX == cx and npc.targetY == cy) then
      return npc
    end
  end
  return nil
end

-- what the A press resolved to, for world.interacted's listeners
-- A LINE THE CARTRIDGE ITSELF PRINTS, named by the import rather than typed
-- here.  `constants.gen3<name>` holds a TEXT_ key and the text pool holds the
-- words; either missing (a Gen 1/2 dataset, or an import that could not place
-- the line unambiguously) answers nil, and the caller falls back to this
-- port's own wording.
-- bg_event kind -> the way the player has to be facing for it to answer.
-- SCRIPT (BG_EVENT_PLAYER_FACING_ANY) is absent, so it answers from anywhere.
local GEN3_SIGN_FACING = {
  SCRIPT_UP = "up", SCRIPT_DOWN = "down",
  SCRIPT_RIGHT = "right", SCRIPT_LEFT = "left",
}

local function cartridgeLine(constant)
  if not GameVersion.isGen3() then return nil end
  local constants = Game.data and Game.data.constants
  local key = constants and constants[constant]
  local line = key and Game.data.text and Game.data.text[key]
  return type(line) == "string" and line or nil
end

local function interacted(self, fx, fy, kind, target)
  Runtime.emit("world.interacted", { mapId = self.map.id, x = fx, y = fy,
                                     kind = kind, target = target })
end

function OverworldState:tryPcTile(fx, fy)
  local field = Game.data.field
  -- GSC does not list its PCs anywhere: COLL_PC ($93) IS the PC, and
  -- CheckFacingTileForStdScript runs TileCollisionStdScripts' PCScript off
  -- the collision class alone.  The port only had R/B's hand-listed
  -- field.hiddenExtras.pcTiles, which names a handful of Gen1 rooms and
  -- nothing at all in a Pokemon Center -- so every Gen2 PC was dead.
  if GameVersion.isGen2() and self.map:inBounds(fx, fy)
     and self.map:cellTile(fx, fy) == 0x93 then
    self:openPC()
    return true
  end
  -- ...AND EMERALD'S IS A METATILE TOO, with no object and no script behind
  -- it: the engine reads the behaviour byte and opens the storage system
  -- itself, which is why the script walk never found one and no PC in the
  -- region could be switched on.  cellBehaviour, not cellTile: a PC is
  -- blocked, and cellTile answers $FF for anything blocked.
  if GameVersion.isGen3() and self.map:inBounds(fx, fy)
     and self.map.cellBehaviour then
    -- ...AND SO IS THE ONE IN A SECRET BASE, and it is a DIFFERENT metatile.
    --
    -- Reported from play: "the pc in the secret base room doesnt work".  It
    -- is not the Poke Centre's $83 -- it is $B0 for your own base and $B1 for
    -- someone else's, answered by its own script
    -- (GetInteractedMetatileScript, 0809C734).  Nothing in this port knew
    -- either byte, so pressing A on it fell all the way through to the sign
    -- branch and a sign with no text says nothing.
    do
      local SB = require("src.world.Gen3SecretBase")
      local base = SB.record(Game.data)
      local script = SB.pcScriptFor(base,
                                    self.map:cellBehaviour(fx, fy))
      if script and self:gen3RunFieldScript(script, "secret base PC") then
        return true
      end
    end
    local pc = Game.data.constants and Game.data.constants.gen3PcBehaviour
    if pc and self.map:cellBehaviour(fx, fy) == pc then
      -- ...AND WHAT IT OPENS IS THE CARTRIDGE'S OWN SCRIPT, not this port's
      -- PC menu.  EventScript_PC is what the field runs for this behaviour:
      -- it lights the screen (special 217), asks the four-row question
      -- (special 265) and hands the answer to the storage system (63), the
      -- item PC (253) or the way out (218).  Sending it to openPC instead
      -- was the Game Boy's PC menu in a Hoenn Poke Centre -- and it left the
      -- boxes unreachable from every Poke Centre in the region, because the
      -- row that reaches them is a row of THAT menu.
      local script = ((Game.data.constants or {}).gen3PCMenu
                      or {}).multichoice
      script = script and script.script
      if script and self:gen3RunFieldScript(script, "PC") then return true end
      self:openPC()
      return true
    end
  end
  local extras = field and field.hiddenExtras
  if not extras then return false end
  local facing = self.player.facing
  local mapId = self.map.id
  local pcRows = extras.pcTiles and extras.pcTiles[mapId]
  if not pcRows and GameVersion.isGen2() then
    if mapId == "MAP_G18_N07" then
      pcRows = extras.pcTiles and extras.pcTiles.PLAYERS_HOUSE2_F
    end
  end
  for _, h in ipairs(pcRows or {}) do
    if h.x == fx and h.y == fy and (not h.facing or h.facing == facing) then
      if mapId == "REDS_HOUSE_2F" or mapId == "PLAYERS_HOUSE2_F"
          or mapId == "MAP_G18_N07" then
        require("src.core.Sound").play(Game.data, "Turn_On_PC")
        Screens.push(Game, "PlayerPC")
      else
        self:openPC()
      end
      return true
    end
  end
  return false
end

function OverworldState:interact()
  local p = self.player
  local fx, fy = p:facingCell()

  local npc = self:npcAtCell(fx, fy)
  if not npc and self.map:isCounterCell(fx, fy) then
    -- talk across counters (mart clerks, nurses); uses the tileset's
    -- counter tiles from tileset_headers.asm
    local fx2, fy2 = Collision.target(fx, fy, p.facing)
    npc = self:npcAtCell(fx2, fy2)
  end
  if npc then
    if npc.pikachuFollower then
      -- the companion answers directly (TalkToPikachu), no map text id --
      -- and it answers mid-step too.  pikachu_follow.asm walks the follower
      -- on the player's own step clock, so the original never has it
      -- mid-tile while the player stands; this port's follow is a frame
      -- late (the npc loop runs before Player:update lands the step), so
      -- the not-moving gate used to eat the A press in the frames right
      -- after landing -- exactly when you turn round to face it (#407).
      -- talk() lands the follower on its cell first.
      require("src.world.PikachuFollower").talk(Game, self, npc)
    elseif not npc.moving then
      self:talkTo(npc)
    end
    interacted(self, fx, fy, "npc", npc)
    return
  end

  if self:tryPcTile(fx, fy) then
    interacted(self, fx, fy, "hidden")
    return
  end

  local sign = self.map:signAtCell(fx, fy)
  -- A GEN 3 BG EVENT MAY DEMAND A DIRECTION, and 118 of Hoenn's do.
  --
  -- The cartridge's kinds are BG_EVENT_PLAYER_FACING_ANY, then NORTH, SOUTH,
  -- EAST and WEST -- and the named ones only answer when the player is facing
  -- that way, which is not the same as merely standing next to the tile.  The
  -- collision data says so plainly: for all 118, the cell the required facing
  -- puts the player on is walkable, while the cell on the far side is walled
  -- on 88 of them.  The other 30 are reachable from behind, and those are
  -- exactly the ones this port was answering and the cartridge is not.
  if sign and GEN3_SIGN_FACING[sign.kind] and GameVersion.isGen3()
     and GEN3_SIGN_FACING[sign.kind] ~= self.player.facing then
    sign = nil
  end
  if sign then
    -- A SECRET BASE'S DOOR IS A SIGN, and it is the only sign that is not
    -- words.  Reported from play: "secret power to create secret bases also
    -- arent working it does nothing".  It did nothing because a bg event of
    -- this kind carries a BASE ID instead of text, and the branch below has
    -- only ever known about items and text.
    if sign.secretBaseId and GameVersion.isGen3()
       and self:gen3SecretBaseEntrance(sign) then
      interacted(self, fx, fy, "sign", sign)
      return
    end
    -- Gen2 BGEVENT_ITEM rows are stored as signs with .item set.  Giving the
    -- item here prevents the Cerulean Gym machine part from falling through
    -- to neighboring statue dialogue ("CERULEAN POKeMON GYM / LEADER: MISTY").
    if sign.item then
      local save = Game.save
      local flagKey = sign.eventFlag
      local takenKey = self.map.id .. "_sign_" .. tostring(sign.x) .. "_" .. tostring(sign.y)
      save.hiddenTaken = save.hiddenTaken or {}
      -- ROM: event SET = already taken / not present.  InitializeEventsScript
      -- pre-sets EVENT_FOUND_MACHINE_PART so the gym water is empty until the
      -- Power Plant manager clears the flag.  clearevent stores false.
      local flagSet = flagKey and save.flags and save.flags[flagKey] == true
      local already = flagSet or save.hiddenTaken[takenKey]
      if already then
        interacted(self, fx, fy, "sign", sign)
        return
      end
      local quantity = tonumber(sign.quantity) or 1
      if not require("src.inventory.Bag").add(save, sign.item, quantity, Game.data) then
        Game.stack:push(TextBox.new(Game,
          cartridgeLine("gen3BagFullText")
            or Strings("You can't carry\nany more items!")))
        interacted(self, fx, fy, "sign", sign)
        return
      end
      save.hiddenTaken[takenKey] = true
      if flagKey then
        save.flags = save.flags or {}
        save.flags[flagKey] = true
      end
      local name = Game.data.items[sign.item] and Game.data.items[sign.item].name or sign.item
      require("src.core.Sound").play(Game.data, "Get_Item2")
      -- THE CARTRIDGE'S OWN LINE WHERE THERE IS ONE.  Emerald says "{PLAYER}
      -- found one {VAR2}!" and splices the item name through buffer slot 2,
      -- the same slot every other Gen 3 line reads it from, so the token
      -- expands the way TextBox already expands it everywhere else.
      local found = cartridgeLine("gen3HiddenItemText")
      if found then
        Game.stringBuffers = Game.stringBuffers or {}
        Game.stringBuffers[2] = name
        Game.stack:push(TextBox.new(Game, found))
      else
        Game.stack:push(TextBox.new(Game,
          Strings("%s found\n%s!", save.player.name, name)))
      end
      interacted(self, fx, fy, "sign", sign)
      return
    end
    if sign.text then
      self:showMapText(sign.text, nil)
    end
    interacted(self, fx, fy, "sign", sign)
    return
  end

  -- Silph Co card key doors (engine/events/card_key.asm)
  if self:tryCardKeyDoor(fx, fy) then
    interacted(self, fx, fy, "door")
    return
  end

  -- hidden items / coins / slot machines / PC tiles / bench guys /
  -- gym statues / trash cans (data/events/hidden_events.asm)
  if self:tryHiddenObject(fx, fy) then
    interacted(self, fx, fy, "hidden")
    return
  end

  -- pokered has no overworld A-press hook for field moves: CUT and SURF
  -- (like FLY/FLASH/DIG/TELEPORT/STRENGTH) are only ever chosen from the
  -- party menu's per-mon field-move submenu (start_sub_menus.asm
  -- .outOfBattleMovePointers).  GSC does have one -- TryCutOW and friends --
  -- so Gen2 gets the tree prompt here.
  --
  -- SO DOES EMERALD, and leaving it out of this call is why nobody in Hoenn
  -- could get on the water.  GetInteractedWaterScript is a plain A-press
  -- handler -- face the sea with the badge and a SURF mon and the game asks
  -- -- and this port's Gen 3 arm of tryFieldMoveOW was written and then
  -- never reached, because the call site asked for Gen 2 and only Gen 2.
  -- The suite did not catch it either: it checked that the SOURCE of the
  -- Gen 3 arm existed, which it did.
  if (GameVersion.isGen2() or GameVersion.isGen3())
     and self:tryFieldMoveOW(fx, fy) then
    interacted(self, fx, fy, "hidden")
    return
  end

  -- ...and DIVE, which is the one field move you use on the cell you are
  -- standing on rather than the one you face (see gen3DiveHere).
  if GameVersion.isGen3() and self:tryDiveOW() then
    interacted(self, fx, fy, "hidden")
    return
  end

  -- ...and WATERFALL, which is faced like SURF but is not offered by
  -- tryFieldMoveOW's water arm: the falls are not a cell you may surf onto,
  -- they are one you may ride up.
  if GameVersion.isGen3() and self:tryWaterfallOW() then
    interacted(self, fx, fy, "hidden")
    return
  end

  -- map-script interact hook (hand-ported hidden events like the
  -- museum fossil exhibits)
  local hooks = mapScripts.get(self.map.id)
  if hooks and hooks.onInteract and hooks.onInteract(Game, self, fx, fy) then
    interacted(self, fx, fy, "script")
    return
  end

  -- tileset-generic reads (PrintBookshelfText): facing up into a
  -- bookshelf/statue/shelf tile prints its stock line
  if self:tryBookshelf(fx, fy) then
    interacted(self, fx, fy, "bookshelf")
    return
  end
  interacted(self, fx, fy, "none")
end

-- field.bookshelves (data/tilesets/bookshelf_tile_ids.asm): tileset id +
-- collision tile -> what to show.  Only fires facing up, like the
-- original.  An entry carries `kind` (one of the five vanilla flavors),
-- `text` (a data.text key) or `screen` (a state module to push).
-- EMERALD'S FURNITURE IS A METATILE, like its counter and its PC.
--
-- The two bookshelves, the Pokemon Centre's magazines, the vase, the trash
-- can, the shop shelf and the blueprint are all behaviour bytes the cartridge
-- prints from C -- no object, no script -- so the script walk never saw them
-- and 533 cells across the region did nothing when you pressed A at them.
--
-- The lines are the cartridge's own, placed by RomExtractorGen3:furnitureText
-- from the one contiguous block they live in.  Facing UP only, which is the
-- rule Kanto's shelves already follow and the rule the cartridge uses too:
-- you read a shelf from in front of it, not from the side.
function OverworldState:tryGen3Furniture(fx, fy)
  if not GameVersion.isGen3() then return false end
  if self.player.facing ~= "up" then return false end
  if not (self.map:inBounds(fx, fy) and self.map.cellBehaviour) then
    return false
  end
  local lines = Game.data.constants and Game.data.constants.gen3FurnitureText
  if not lines then return false end
  local key = lines[self.map:cellBehaviour(fx, fy)]
  if not key then return false end
  local line = Game.data.text and Game.data.text[key]
  if not line then return false end
  Game.stack:push(TextBox.new(Game, line))
  return true
end

-- THE FOUR LINES ONLY C CODE CAN REACH (GetInteractedMetatileScript).
--
-- The wall region map, the television and the running-shoes booklet each
-- print one line and do nothing else; the questionnaire asks first.  None of
-- them is a script the region can run -- there is no `msgbox` anywhere in
-- Hoenn's script data pointing at any of these lines, which is exactly how
-- the import finds them (see RomExtractorGen3:metatileScriptText).
--
-- Facing: the cartridge's TV test is MetatileBehavior_IsPlayerFacingTVScreen,
-- which takes the DIRECTION and demands north.  The region map and the
-- booklet have no direction test of their own, but both metatiles are blocked
-- ground, so the only way to press A at one is to be facing it.  Keeping the
-- facing-up rule for all of them therefore matches the cartridge and is what
-- tryBookshelf already does for the furniture.
function OverworldState:tryGen3MetatileScript(fx, fy)
  if not GameVersion.isGen3() then return false end
  if self.player.facing ~= "up" then return false end
  if not (self.map:inBounds(fx, fy) and self.map.cellBehaviour) then
    return false
  end
  local constants = Game.data.constants or {}
  local b = self.map:cellBehaviour(fx, fy)
  if not b then return false end

  local lines = constants.gen3MetatileText
  local key = lines and lines[b]
  local text = Game.data.text or {}
  if key and text[key] then
    -- THE WALL MAP IS NOT JUST A LINE.
    --
    -- EventScript_RegionMap prints "There's a HOENN REGION MAP" and then runs
    -- FieldShowRegionMap, which puts the map itself up.  Only the line was
    -- here, so every Pokemon Centre in Hoenn had a map on the wall that said
    -- there was a map on the wall and did nothing.  The television and the
    -- running-shoes booklet really are only their line, which is why this
    -- hangs off the behaviour rather than off every metatile that speaks.
    local after = nil
    if constants.gen3Behaviours and constants.gen3Behaviours[b] == "REGION_MAP"
       and self.openRegionMap then
      after = function() self:openRegionMap() end
    end
    Game.stack:push(TextBox.new(Game, text[key], after))
    return true
  end

  -- THE QUESTIONNAIRE, which is the one that asks.
  --
  -- The cartridge follows the YES with the Mystery Event phrase entry
  -- (DoQuestionnaire -> the naming screen) and only then prints the thanks.
  -- The phrase itself feeds the Mystery Event system, which this port does
  -- not have, so the entry is skipped and the thanks is printed -- said here
  -- rather than left to be discovered.  The ASK and the two answers are the
  -- cartridge's; what is missing is what the phrase would have been for.
  local quiz = constants.gen3Questionnaire
  local askKey = quiz and quiz.ask
  local thanksKey = quiz and quiz.thanks
  if askKey and thanksKey and text[askKey] and text[thanksKey]
     and quiz.behaviour ~= nil and b == quiz.behaviour then
    local ChoiceBox = require("src.ui.ChoiceBox")
    Game.stack:push(TextBox.new(Game, text[askKey], function()
      Game.stack:push(ChoiceBox.new(Game, function(yes)
        if yes then
          Game.stack:push(TextBox.new(Game, text[thanksKey]))
        end
      end))
    end))
    return true
  end
  return false
end

function OverworldState:tryBookshelf(fx, fy)
  if self:tryGen3Furniture(fx, fy) then return true end
  if self:tryGen3MetatileScript(fx, fy) then return true end
  if self.player.facing ~= "up" then return false end
  if not self.map:inBounds(fx, fy) then return false end
  local shelves = FieldDefaults.field(Game.data, "bookshelves")
  local table_ = shelves and shelves[self.map.def.tileset]
  if not table_ then return false end
  local entry = table_[self.map:cellTile(fx, fy)]
  if not entry then return false end
  local t = Game.data.text
  if entry.text then
    Game.stack:push(TextBox.new(Game, t[entry.text] or entry.text))
    return true
  end
  if entry.screen then
    -- Blue's house shelf opens the TOWN MAP (TownMapText)
    pcall(Screens.push, Game, entry.screen)
    return true
  end
  local kind = entry.kind
  if kind == "books" then
    -- Celadon Mansion's Diglett sculpture (book_or_sculpture.asm):
    -- MANSION tileset + faced cell's top-left tile $38
    if self.map.def.tileset == "MANSION"
       and self.map:tileAt(fx * 2, fy * 2) == 0x38 then
      Game.stack:push(TextBox.new(Game, t._DiglettSculptureText
        or Strings("It's a sculpture\nof DIGLETT.")))
      return true
    end
    Game.stack:push(TextBox.new(Game, t._PokemonBooksText
      or Strings("Crammed full of\nPOKéMON books!")))
  elseif kind == "stuff" then
    Game.stack:push(TextBox.new(Game, t._PokemonStuffText
      or Strings("There's a slew of\nPOKéMON stuff!")))
  elseif kind == "elevator" then
    Game.stack:push(TextBox.new(Game, t._ElevatorText
      or Strings("An elevator!")))
  elseif kind == "statues" then
    -- IndigoPlateauStatues: the plaque, then one of the two lines
    -- keyed by the statue's column (XCoord bit 0)
    local line = (self.player.cellX % 2 == 0) and t._IndigoPlateauStatuesText2
                 or t._IndigoPlateauStatuesText3
    Game.stack:push(TextBox.new(Game,
      (t._IndigoPlateauStatuesText1 or Strings("INDIGO PLATEAU")) .. "\f"
      .. (line or Strings("POKéMON LEAGUE HQ"))))
  end
  return true
end

-- Bench guys are the one hidden-event family whose extracted label is a
-- wrapper rather than the string itself: bench_guys.asm defines e.g.
-- PewterCityPokecenterBenchGuyText:: as `text_far _PewterCityPokecenterGuyText`,
-- so data/generated/field.lua carries the wrapper name while the text sits
-- under the far label.  The two only coincide for Mt Moon and the Celadon
-- hotel, which is why every other bench guy answered with silence (#248).
-- pokered's own names are irregular here (Cerulean/Lavender/Vermilion drop
-- "City", Cinnabar drops "Island"), so this is a table, not a transform.
local BENCH_GUY_TEXT = {
  ViridianCityPokecenterBenchGuyText   = "_ViridianCityPokecenterGuyText",
  PewterCityPokecenterBenchGuyText     = "_PewterCityPokecenterGuyText",
  CeruleanCityPokecenterBenchGuyText   = "_CeruleanPokecenterGuyText",
  LavenderCityPokecenterBenchGuyText   = "_LavenderPokecenterGuyText",
  VermilionCityPokecenterBenchGuyText  = "_VermilionPokecenterGuyText",
  CeladonCityPokecenterBenchGuyText    = "_CeladonCityPokecenterGuyText",
  FuchsiaCityPokecenterBenchGuyText    = "_FuchsiaCityPokecenterGuyText",
  CinnabarIslandPokecenterBenchGuyText = "_CinnabarPokecenterGuyText",
  RockTunnelPokecenterBenchGuyText     = "_RockTunnelPokecenterGuyText",
}

-- SaffronCityPokecenterBenchGuyText is text_asm: he complains about ROCKET
-- until EVENT_BEAT_SILPH_CO_GIOVANNI, then thanks you for clearing them out.
-- Takes data/save rather than reading the Game upvalue so tests can resolve
-- every label in the table without standing a whole overworld up.
function OverworldState.benchGuyText(data, save, label)
  if not label then return nil end
  if label == "SaffronCityPokecenterBenchGuyText" then
    local key = (save and save.flags and save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI)
                and "_SaffronCityPokecenterGuyText2"
                or "_SaffronCityPokecenterGuyText1"
    return data.text[key]
  end
  -- the direct name first, so a cache whose extractor already resolved the
  -- far label keeps working without consulting the table
  return data.text["_" .. label] or data.text[BENCH_GUY_TEXT[label] or ""]
end

-- Hidden events at the faced cell (data/events/hidden_events.asm):
-- HiddenItems give their item once, HiddenCoins fill the COIN CASE,
-- StartSlotMachine seats open the minigame.  Taken spots persist in
-- save.hiddenTaken.
function OverworldState:tryHiddenObject(fx, fy)
  local field = Game.data.field
  local save = Game.save
  local key = self.map.id .. "_" .. fx .. "_" .. fy

  for _, h in ipairs(field.hiddenItems and field.hiddenItems[self.map.id] or {}) do
    if h.x == fx and h.y == fy then
      save.hiddenTaken = save.hiddenTaken or {}
      if save.hiddenTaken[key] then return false end
      if not require("src.inventory.Bag").add(save, h.item, 1, Game.data) then
        Game.stack:push(TextBox.new(Game, Strings("You can't carry\nany more items!")))
        return true
      end
      save.hiddenTaken[key] = true
      local name = Game.data.items[h.item] and Game.data.items[h.item].name or h.item
      -- hidden items always play SFX_GET_ITEM_2 (hidden_items.asm)
      require("src.core.Sound").play(Game.data, "Get_Item2")
      Game.stack:push(TextBox.new(Game,
        Strings("%s found\n%s!", save.player.name, name)))
      return true
    end
  end

  for _, h in ipairs(field.hiddenCoins and field.hiddenCoins[self.map.id] or {}) do
    if h.x == fx and h.y == fy then
      save.hiddenTaken = save.hiddenTaken or {}
      if save.hiddenTaken[key] then return false end
      if not save.inventory.COIN_CASE then return false end
      save.hiddenTaken[key] = true
      save.coins = math.min(9999, (save.coins or 0) + h.coins)
      require("src.core.Sound").play(Game.data, "Get_Item2")
      Game.stack:push(TextBox.new(Game,
        Strings("%s found\n%d coins!", save.player.name, h.coins)))
      return true
    end
  end

  -- broken-machine and can't-play texts are pokered's exact strings
  -- (_GameCornerOutOfOrderText etc., data/text/text_2.asm)
  local txt = Game.data.text or {}
  for seatIndex, h in ipairs(field.slotMachines and field.slotMachines[self.map.id] or {}) do
    if h.x == fx and h.y == fy then
      if h.state == "out_of_order" then
        Game.stack:push(TextBox.new(Game, txt._GameCornerOutOfOrderText
          or Strings("OUT OF ORDER\nThis is broken.")))
      elseif h.state == "out_to_lunch" then
        Game.stack:push(TextBox.new(Game, txt._GameCornerOutToLunchText
          or Strings("OUT TO LUNCH\nThis is reserved.")))
      elseif h.state == "keys" then
        Game.stack:push(TextBox.new(Game, txt._GameCornerSomeonesKeysText
          or Strings("Someone's keys!\nThey'll be back.")))
      elseif not save.inventory.COIN_CASE then
        Game.stack:push(TextBox.new(Game, txt._GameCornerCoinCaseText
          or Strings("A COIN CASE is\nrequired!")))
      elseif (save.coins or 0) == 0 then
        -- AbleToPlaySlotsCheck: a COIN CASE with no coins can't play
        Game.stack:push(TextBox.new(Game, txt._GameCornerNoCoinsText
          or Strings("You don't have\nany coins!")))
      else
        -- one machine per visit is secretly lucky
        -- (wLuckySlotHiddenEventIndex, engine/slots/game_corner_slots.asm)
        Screens.push(Game, "SlotMachine", seatIndex == self.luckySlot)
      end
      return true
    end
  end

  -- Bill's cell-separator PC (data/events/hidden_events.asm: hidden_event
  -- 1,4 BillsHousePC SPRITE_FACING_UP)
  if self.map.id == "BILLS_HOUSE" and fx == 1 and fy == 4
     and self.player.facing == "up" then
    self:billsHousePC()
    return true
  end

  local extras = field.hiddenExtras
  if not extras then return false end
  local facing = self.player.facing

  if self:tryPcTile(fx, fy) then return true end

  -- Bench guys (data/events/bench_guys.asm).  A hidden_event's fourth byte
  -- is wHiddenEventFunctionArgument, not a facing gate -- pokered's own
  -- macro comment says the SPRITE_FACING_* values parked there "do not
  -- actually prevent the player from interacting with them in any
  -- direction" (data/events/hidden_events.asm).  The facing that does decide
  -- a bench guy is PrintBenchGuyText's own test against BenchGuyTextPointers,
  -- SPRITE_FACING_LEFT for all twelve seats, which the manifest carries as
  -- `textFacing`.  Gating on the hidden_event byte instead silenced the four
  -- seats that store SPRITE_FACING_UP (Vermilion, Saffron, Fuchsia,
  -- Cinnabar): (0,4) is the bench wall cell and can only ever be faced from
  -- the right (#488).
  for _, h in ipairs(extras.benchGuys and extras.benchGuys[self.map.id] or {}) do
    local want = h.textFacing or h.facing
    if h.x == fx and h.y == fy and (not want or want == facing) then
      local text = OverworldState.benchGuyText(Game.data, save, h.text)
      if text then
        Game.stack:push(TextBox.new(Game, text))
        return true
      end
    end
  end

  -- gym statues (engine/events/hidden_events/gym_statues.asm): show
  -- the gym plaque; the player's name joins the winners once the
  -- badge is earned
  for _, h in ipairs(extras.gymStatues and extras.gymStatues[self.map.id] or {}) do
    if h.x == fx and h.y == fy and facing == "up" then
      local gym = require("data.scripts.gyms")[self.map.id]
      if gym then
        local key = save.inventory[gym.badge] and "_GymStatueText2" or "_GymStatueText1"
        local text = Game.data.text[key]
                     or Strings("{RAM}\nPOKéMON GYM\nLEADER: {RAM}")
        text = text:gsub("{RAM:wGymCityName}", gym.city)
                   :gsub("{RAM:wGymLeaderName}", gym.leader)
        Game.stack:push(TextBox.new(Game, text))
        return true
      end
    end
  end

  -- PrintTrashText: SS Anne kitchen + Vermilion Gym non-puzzle can
  for _, h in ipairs(extras.printTrash and extras.printTrash[self.map.id] or {}) do
    if h.x == fx and h.y == fy then
      Game.stack:push(TextBox.new(Game, txt._VermilionGymTrashText
        or Strings("Nope, there's\nonly trash here.")))
      return true
    end
  end

  -- the Vermilion Gym trash can lock puzzle
  if self.map.id == "VERMILION_GYM" then
    for _, h in ipairs(extras.trashCans.cans or {}) do
      if h.x == fx and h.y == fy then
        self:trashCanSwitch(h.can)
        return true
      end
    end
  end

  return false
end

-- Card key doors: on the Silph Co maps, facing a locked-door tile with
-- the CARD KEY replaces the door block with the open one
-- (engine/events/card_key.asm PrintCardKeyText).
function OverworldState:tryCardKeyDoor(fx, fy)
  local ck = Game.data.field.cardKeyDoors
  if not ck then return false end
  local onList = false
  for _, m in ipairs(ck.maps or {}) do
    if m == self.map.id then onList = true break end
  end
  if not onList or not self.map:inBounds(fx, fy) then return false end
  local tile = self.map:cellTile(fx, fy)
  local openBlock
  if self.map.id == "SILPH_CO_11F" and ck.silphCo11F then
    if tile == ck.silphCo11F.doorTile then openBlock = ck.silphCo11F.openBlock end
  else
    for _, t in ipairs(ck.doorTiles or {}) do
      if tile == t then openBlock = ck.openBlock break end
    end
  end
  if not openBlock then return false end
  local t = Game.data.text
  if not Game.save.inventory.CARD_KEY then
    Game.stack:push(TextBox.new(Game,
      t._CardKeyFailText or Strings("Darn! It needs a\nCARD KEY!")))
    return true
  end
  require("src.core.Sound").play(Game.data, "Go_Inside")
  local bx, by = math.floor(fx / 2), math.floor(fy / 2)
  self:replaceBlock(bx, by, openBlock)
  -- opened doors stay open across reloads (the per-door unlock events
  -- the floors' gate callbacks check, EVENT_SILPH_CO_n_UNLOCKED_DOOR*)
  local closedDoors = FieldDefaults.fieldValue(Game.data, "cardKeyDoors",
                                               "closedDoors")
  for _, door in ipairs(closedDoors and closedDoors[self.map.id] or {}) do
    if door.bx == bx and door.by == by then
      Game.save.flags[door.event] = true
      break
    end
  end
  Game.stack:push(TextBox.new(Game,
    (t._CardKeySuccessText1 or Strings("Bingo!"))
    .. (t._CardKeySuccessText2 or Strings("\nThe CARD KEY\nopened the door!"))))
  return true
end

-- The Vermilion Gym trash can puzzle
-- (engine/events/hidden_events/vermilion_gym_trash.asm GymTrashScript):
-- the first switch hides in a random even can, rolled on every
-- Vermilion City map load (scripts/VermilionCity.asm VermilionCity_Script
-- .setFirstLockTrashCanIndex -- see M.VERMILION_CITY.onEnter in
-- data/scripts/story.lua) and re-rolled on every failed second-can
-- guess; the second switch is drawn from the GymTrashCans candidate
-- table (bug included).  Opening both unlocks the door block at (2,2)
-- (scripts/VermilionGym.asm VermilionGymSetDoorTile).
function OverworldState:trashCanSwitch(canIndex)
  local t = Game.data.text
  local save = Game.save
  local tc = Game.data.field.hiddenExtras.trashCans
  local trashText = t._VermilionGymTrashText or Strings("Nope, there's\nonly trash here.")
  -- "Don't do the trash can puzzle if it's already been done."
  if save.flags.EVENT_2ND_LOCK_OPENED then
    Game.stack:push(TextBox.new(Game, trashText))
    return
  end
  save.trashPuzzle = save.trashPuzzle or {}
  local puz = save.trashPuzzle
  if puz.opened1 then
    -- migrate mid-puzzle saves from before the port tracked the real
    -- EVENT_1ST_LOCK_OPENED flag
    save.flags.EVENT_1ST_LOCK_OPENED = true
    puz.opened1 = nil
  end
  if not puz.first then
    -- normally rolled by Vermilion City's map load (the only way in);
    -- covers saves from before that hook and debug warps straight in
    puz.first = love.math.random(0, 7) * 2 -- Random & $0e: even cans
  end
  if not save.flags.EVENT_1ST_LOCK_OPENED then
    if canIndex ~= puz.first then
      Game.stack:push(TextBox.new(Game, trashText))
      return
    end
    -- .openFirstLock: SetEvent EVENT_1ST_LOCK_OPENED, then pick where
    -- the second switch hides.  GymTrashCans rows are `mask,
    -- cand1..cand4` where the mask doubles as the candidate count
    -- (2, 3 or 4).  The asm ANDs the mask with a random byte (its
    -- nibble swap is distribution-neutral) and uses `result - 1` as a
    -- byte offset into the candidates:
    --   mask 3: result 1-3 -> candidate 1-3
    --   mask 2: result 2   -> candidate 2 (candidate 1 unreachable)
    --   mask 4: result 4   -> candidate 4 (candidates 1-3 unreachable)
    --   result 0: `dec a` underflows to $ff and the read lands on the
    --   ROM bank's zero padding, so the second switch lands in can 0
    --   regardless of adjacency (the documented GymTrashCans bug)
    save.flags.EVENT_1ST_LOCK_OPENED = true
    local adj = tc.adjacent[puz.first]
    local masked = require("bit").band(love.math.random(0, 255), #adj)
    puz.second = masked == 0 and 0 or adj[masked]
    -- VermilionGymTrashSuccessText1's text_asm tail plays SFX_SWITCH only
    -- after the text has printed (text_far ...; text_asm;
    -- WaitForSoundToFinish; PlaySound SFX_SWITCH; WaitForSoundToFinish),
    -- and DisplayTextID's WaitForTextScrollButtonPress then holds the box
    -- until the player dismisses it -- so the beep belongs on close, not
    -- open.
    Game.stack:push(TextBox.new(Game,
      t._VermilionGymTrashSuccessText1
      or Strings("Hey! There's a\nswitch under the\ntrash!\fThe 1st electric\nlock opened!"),
      function() require("src.core.Sound").play(Game.data, "Switch") end))
    return
  end
  -- .trySecondLock
  if canIndex == puz.second then
    -- .openSecondLock: only VermilionGymTrashSuccessText3 prints
    -- (SuccessText2 is unused in pokered)
    save.flags.EVENT_2ND_LOCK_OPENED = true
    -- the clear floor block opens the doors (VermilionGymSetDoorTile)
    local door = FieldDefaults.fieldValue(Game.data, "hiddenExtras",
                                          "trashCans", "doorBlock")
    self:replaceBlock(door.bx, door.by, door.block)
    -- SuccessText3's text_asm tail plays SFX_GO_INSIDE after the text
    -- prints, so the beep fires as the box closes, not as it opens.
    Game.stack:push(TextBox.new(Game,
      t._VermilionGymTrashSuccessText3
      or Strings("The 2nd electric\nlock opened!\fThe motorized door\nopened!"),
      function() require("src.core.Sound").play(Game.data, "Go_Inside") end))
  else
    -- wrong can: ResetEvent EVENT_1ST_LOCK_OPENED and immediately
    -- re-roll the first switch (Random & $e)
    save.flags.EVENT_1ST_LOCK_OPENED = nil
    puz.first = love.math.random(0, 7) * 2
    puz.second = nil
    -- VermilionGymTrashFailText's text_asm tail plays SFX_DENIED after the
    -- text prints, so the beep fires as the box closes, not as it opens.
    Game.stack:push(TextBox.new(Game,
      t._VermilionGymTrashFailText
      or Strings("Nope! There's\nonly trash here.\fHey! The electric\nlocks were reset!"),
      function() require("src.core.Sound").play(Game.data, "Denied") end))
  end
end

-- Bill's House PC (engine/events/hidden_events/bills_house_pc.asm
-- BillsHousePC).  Check order matches pokered:
--   1) EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING -> Eevee collection list
--   2) EVENT_USED_CELL_SEPARATOR_ON_BILL   -> teleporter monitor text
--   3) EVENT_BILL_SAID_USE_CELL_SEPARATOR  -> cell-separator cutscene
--   4) else                               -> teleporter monitor text
-- Leaving after the SS Ticket (Route25ToggleBillsScript) arms (1).
function OverworldState:billsHousePC()
  local t = Game.data.text
  local flags = Game.save.flags
  if flags.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING then
    self:billsHousePokemonList()
    return
  end
  if flags.EVENT_USED_CELL_SEPARATOR_ON_BILL
     or not flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR then
    Game.stack:push(TextBox.new(Game, t._BillsHouseMonitorText
      or Strings("TELEPORTER is\ndisplayed on the\nPC monitor.")))
    return
  end
  require("src.core.Music").stop()
  Game.stack:push(TextBox.new(Game, t._BillsHouseInitiatedText
    or Strings("{PLAYER} initiated\nTELEPORTER's Cell\nSeparator!"), function()
    flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = true
    require("src.core.Sound").play(Game.data, "Switch")
    self:queueScript({
      { "wait", 32 },
      { "play_sound", "Tink" },
      { "wait", 80 },
      { "play_sound", "Shrink" },
      { "wait", 48 },
      { "play_sound", "Tink" },
      { "wait", 32 },
      { "play_sound", "Get_Item1" },
      { "wait", 30 },
    }, { onDone = function() self:billsHouseBillExits() end })
  end))
end

-- BillsHousePokemonList: EEVEE / FLAREON / JOLTEON / VAPOREON + CANCEL;
-- picking one runs DisplayPokedex (DexEntryMenu) and returns to the list.
function OverworldState:billsHousePokemonList()
  local t = Game.data.text
  local Menu = require("src.ui.Menu")
  local function openList()
    local species = { "EEVEE", "FLAREON", "JOLTEON", "VAPOREON" }
    local items = {}
    for _, id in ipairs(species) do
      local def = Game.data.pokemon[id]
      table.insert(items, {
        label = (def and def.name) or id,
        keepOpen = true,
        onSelect = function()
          local dex = Game.save.pokedex
          if dex then dex.seen[id] = true end
          Screens.push(Game, "DexEntryMenu", id)
        end,
      })
    end
    table.insert(items, { label = Strings("CANCEL") })
    -- TextBoxBorder b=10,c=9 at (0,0) -> total tw=11, th=12
    Game.stack:push(Menu.new(Game, items,
      { tx = 0, ty = 0, tw = 11, th = 12 }))
  end
  Game.stack:push(TextBox.new(Game, t._BillsHousePokemonListText1
    or Strings("BILL's favorite\nPOKéMON list!"), openList))
end

-- BillsHouseBillExitsMachineScript: human Bill appears inside the machine
-- at (1,2) and walks out to his spot at (4,4); the map music resumes and
-- EVENT_MET_BILL / EVENT_MET_BILL_2 arm the SS-Ticket dialogue.  The Eevee
-- PC list arms later, on the first Route 25 load after the ticket
-- (EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING).
function OverworldState:billsHouseBillExits()
  local Commands = require("src.script.Commands")
  local ctx = { game = Game, save = Game.save, overworld = self }
  Commands.show_object(ctx, "BILLS_HOUSE", "BILLSHOUSE_BILL1")
  require("src.world.PikachuFollower").onBillExitedMachine(Game, self)
  local function done()
    Game.save.flags.EVENT_MET_BILL = true
    Game.save.flags.EVENT_MET_BILL_2 = true
    require("src.core.Music").playMap(Game.data, self.map.id,
                                      Game.save.onBike, self.player.surfing)
  end
  local bill
  for _, n in ipairs(self.npcs) do
    if n.def and n.def.name == "BILLSHOUSE_BILL1" then bill = n break end
  end
  if not (bill and self.map.id == "BILLS_HOUSE") then
    done()
    return
  end
  bill.cellX, bill.cellY = 1, 2
  bill.px, bill.py = 16, 32
  bill.facing = "down"
  self:scriptMove(bill, "down", 1, function()
    self:scriptMove(bill, "right", 3, function()
      self:scriptMove(bill, "down", 1, done)
    end)
  end)
end

-- Any hidden item still unfound NEAR the player? (the ITEMFINDER,
-- engine/items/itemfinder.asm HiddenItemNear: coord > clamp0(player-5)
-- and coord <= player+4 (Y) / player+5 (X) -- the clamp excludes
-- coordinate 0 whenever the player coordinate is <= 4, like the original)
function OverworldState:hasHiddenItemLeft()
  local list = Game.data.field.hiddenItems and Game.data.field.hiddenItems[self.map.id]
  if not list then return false end
  local taken = Game.save.hiddenTaken or {}
  local px, py = self.player.cellX, self.player.cellY
  local function near(c, v, hiAdd)
    return v > math.max(c - 5, 0) and v <= c + hiAdd
  end
  for _, h in ipairs(list) do
    if not taken[self.map.id .. "_" .. h.x .. "_" .. h.y]
       and near(py, h.y, 4) and near(px, h.x, 5) then
      return true
    end
  end
  return false
end

function OverworldState:tilesetHasWater()
  -- Gen2: check the tileset's collision-class waterTiles from the ROM's
  -- CollisionPermissionTable (permission == 1 entries), extracted per-tileset.
  -- waterTilesets is empty on Gen2 (it is Gen1's water_tilesets.asm list);
  -- fall back to checking map.waterTiles instead.
  if GameVersion.isGen2() then
    local ts = self.map.def.tileset
    -- if the extractor populated waterTilesets for Gen2 as well, use it
    for _, t in ipairs(Game.data.field.waterTilesets or {}) do
      if t == ts then return true end
    end
    -- otherwise: a Gen2 tileset has water when its waterTiles set is
    -- non-trivial (contains entries beyond the Gen1 fallback 0x14)
    for cls in pairs(self.map.waterTiles) do
      if cls ~= 0x14 then return true end
    end
    return false
  end
  for _, t in ipairs(Game.data.field.waterTilesets or {}) do
    if t == self.map.def.tileset then return true end
  end
  return false
end

-- field.seafoam[map].surfBlocked: cells where SURF is refused until the
-- listed events fire (IsSurfingAllowed's SEAFOAM_ISLANDS_B4F stairs case)
function OverworldState:surfBlockedHere()
  local blocked = FieldDefaults.fieldValue(Game.data, "seafoam", self.map.id,
                                           "surfBlocked")
  if not blocked then return false end
  local p = self.player
  for _, cell in ipairs(blocked) do
    if p.cellX == cell.x and p.cellY == cell.y then
      local cleared = true
      for _, e in ipairs(cell.untilEvents or {}) do
        if not Game.save.flags[e] then cleared = false break end
      end
      if not cleared then return true end
    end
  end
  return false
end

-- Gen 1 has no confirmation prompt: using SURF gets straight on
-- (_SurfingGotOnText, item_effects.asm .surf).  Called from the party
-- menu's SURF action (via useSurfFieldMove) once the facing tile has been
-- confirmed to be water -- there is no overworld A-press hook.  onClose is
-- that menu's own close, called when the got-on text ends (see below).
function OverworldState:trySurf(fx, fy, onClose)
  local mon = self:partyKnows("SURF")
  if not mon then return end
  local name = mon.nickname or Game.data.pokemon[mon.species].name
  local p = self.player
  -- Emerald says "{VAR1} used SURF!" and Gen 1/2 say "{PLAYER} got on X!",
  -- and each is that cartridge's own line rather than a translation of the
  -- other, so the Gen 3 one is asked for first and by its own placeholder.
  local gen3Line = self:gen3FieldText("SURF", "used")
  local text = gen3Line and gen3Line:gsub("{VAR1}", (name:gsub("%%", "%%%%")))
               or (Game.data.text._SurfingGotOnText
                   or Strings("{PLAYER} got on\n{RAM:wNameBuffer}!"))
                  :gsub("{RAM:wNameBuffer}", name)
  -- UseItem prints the got-on text with the party menu still on screen and
  -- GBPalWhiteOutWithDelay3 + .goBackToMap only run after it
  -- (start_sub_menus.asm .surf), so the text reads over the menu and the
  -- blink is the menu closing, not a flashbang on the empty map (#320,
  -- #385).  The mount rides the blink, so nothing paddles on land.
  Game.stack:push(TextBox.new(Game, text, function()
    if onClose then onClose() end
    p.surfing = true
    -- getting on the water means being AT the water's level: on a Gen 3 map
    -- the sea is elevation 1 and the step onto it would otherwise be refused
    -- by the same rule that keeps a walker out of it
    if self.map.cellElevation then
      local fx2, fy2 = p:facingCell()
      p.elevation = self.map:cellElevation(fx2, fy2) or p.elevation
    end
    self:syncSurfingPikachu()
    require("src.core.Music").setSurfing(Game.data, true)
    Game.stack:push(require("src.render.Transition").whiteFlash(Game, nil,
      function() self:stepForwardOrCrossEdge(p.facing) end))
  end))
end

-- GSC's cut is per-tileset (CutTreeBlockPointers) and keyed on the facing
-- cell's COLLISION class rather than a tile id, because a JOHTO tree block
-- and a FOREST one share no ids.  Returns the swap row (before/after/anim)
-- for the block the player is facing, or nil.
function OverworldState:gen2CutSwap(fx, fy)
  if not self.map:inBounds(fx, fy) then return nil end
  if not Map.gen2IsCutTree(self.map:cellTile(fx, fy)) then return nil end
  local table_ = Game.data.field.gen2CutTrees
  local rows = table_ and table_[self.map.def.tileset]
  if not rows then return nil end
  local bx, by = math.floor(fx / 2), math.floor(fy / 2)
  local block = self.map:blockAt(bx, by)
  for _, row in ipairs(rows) do
    if row.before == block then return row, bx, by end
  end
  return nil
end

function OverworldState:tryCut(fx, fy)
  if GameVersion.isGen2() then return self:gen2Cut(fx, fy) end
  -- UsedCut (engine/overworld/cut.asm) gates on the TILESET before
  -- anything else: only OVERWORLD (tree tile $3d) and GYM (plant tile
  -- $50) have cuttable anything. Matching raw block ids alone
  -- false-positives on every other tileset -- block ids are only
  -- meaningful within one tileset, so Route 23 (PLATEAU) had blocks
  -- matching a swap's `before`, and applying it wrote a block id that
  -- does not exist in PLATEAU's block table: the renderer indexed nil
  -- and the game crashed. The same false match is what made the bot
  -- chain-cut "ornamental bushes" around Saffron and Celadon.
  local ts = self.map.def.tileset
  local tile = self.map:cellTile(fx, fy)
  local isGrass = (ts == "OVERWORLD" and tile == 0x52)
  if not ((ts == "OVERWORLD" and tile == 0x3d)
          or (ts == "GYM" and tile == 0x50)
          or isGrass) then
    return false
  end
  local bx, by = math.floor(fx / 2), math.floor(fy / 2)
  local block = self.map:blockAt(bx, by)
  local swap
  for _, sw in ipairs(Game.data.field.cutTreeSwaps or {}) do
    if sw.before == block then swap = sw break end
  end
  if not swap or (not isGrass and self.map:isWalkableCell(fx, fy)) then return false end
  local mon = self:partyKnows("CUT")
  if not mon then return false end
  -- gen 1 confirms nothing (engine/overworld/cut.asm UsedCut): the
  -- _UsedCutText message, then the tree vanishes with dust + SFX_CUT
  local name = mon.nickname or Game.data.pokemon[mon.species].name
  local text = (Game.data.text._UsedCutText or Strings("{RAM:wNameBuffer} hacked\naway with CUT!"))
               :gsub("{RAM:wNameBuffer}", name)
  Game.stack:push(TextBox.new(Game, text, function()
    self.cutBlocks = self.cutBlocks or {}
    self.cutBlocks[self.map.id] = self.cutBlocks[self.map.id] or {}
    table.insert(self.cutBlocks[self.map.id],
                 { bx = bx, by = by, block = block })
    self.map:setBlock(bx, by, swap.after)
    self.map.renderer:rebuild()
    local finish = function()
      require("src.core.Sound").play(Game.data, "Cut")
    end
    if isGrass then
      -- AnimCut .grass: tall grass gets the leaf-swirl / dust puff, not
      -- the tree-split slide
      self:startDustAnim(fx, fy, finish)
    elseif ts == "OVERWORLD" then
      -- the tree splits in half and slides apart (AnimCut .cutTreeLoop);
      -- the GYM plant keeps the shared dust/leaf puff
      self:startCutTreeAnim(fx, fy, finish)
    else
      self:startDustAnim(fx, fy, finish)
    end
  end))
  return true
end

-- CheckHeadbuttTreeTile (00:$1737), CheckWhirlpoolTile / CheckWaterfallTile
-- (00:$1751 / $175A): each Try<Move>OW keys off the facing cell's collision
-- class, and every one of them is a hook R/B simply does not have.
local GEN2_OW_TILES = {
  HEADBUTT  = { [0x15] = true, [0x1D] = true },
  WHIRLPOOL = { [0x24] = true, [0x2C] = true },
  WATERFALL = { [0x33] = true, [0x3B] = true },
}

-- TryWhirlpoolMenu / DisappearWhirlpool (engine/events/overworld.asm): the
-- eddy is a BLOCK swap out of WhirlpoolBlockPointers, exactly like a cut
-- tree, and the player never moves -- the whirlpool simply becomes plain
-- water.  The port used to walk the player forward instead, which shoved
-- them into the current.
function OverworldState:gen2WhirlpoolSwap(fx, fy)
  if not self.map:inBounds(fx, fy) then return nil end
  local table_ = Game.data.field.gen2Whirlpools
  local rows = table_ and table_[self.map.def.tileset]
  if not rows then return nil end
  local bx, by = math.floor(fx / 2), math.floor(fy / 2)
  local block = self.map:blockAt(bx, by)
  for _, row in ipairs(rows) do
    if row.before == block then return row, bx, by end
  end
  return nil
end

-- Surfing into an uncleared whirlpool.  DoPlayerMovement.CheckTile
-- (04:$40B7) runs CheckWhirlpoolTile against wPlayerTileCollision and, on a
-- hit, returns PLAYERMOVEMENT_FORCE_TURN (3) before any of the turn/step/
-- jump/warp handlers get a look in.  PlayerMovementPointers.force_turn
-- (25:$6A53) hands that to Script_ForcedMovement (04:$6904), which reads
-- VAR_FACING and applies one of four movement lists (04:$692B, verified
-- byte-for-byte: `4F 10 24 4F 10 00 47` and its three rotations):
--
--   MovementData_up    step_dig 16, turn_in_down,  step_dig 16, turn_head_down
--   MovementData_down  step_dig 16, turn_in_up,    step_dig 16, turn_head_up
--   MovementData_right step_dig 16, turn_in_left,  step_dig 16, turn_head_left
--   MovementData_left  step_dig 16, turn_in_right, step_dig 16, turn_head_right
--
-- so the eddy costs no ground: it whirls the player for two sixteen-frame
-- beats and spits them out facing back the way they came.  There is no SFX --
-- the ROM script is silent (PlayWhirlpoolSound belongs to the field move).
--
-- The port arms this off the tile being surfed INTO rather than the one
-- underfoot.  CollisionPermissionTable (3E:$74BE) gives $24/$2C the byte $11,
-- whose low nibble GetTileCollision keeps -- so the eddy reads as plain water
-- and nothing in .TrySurf refuses it.  Standing on one would then mean every
-- direction hits .CheckTile forever, i.e. a softlock, which is exactly what
-- the eddy-as-a-bump avoids while keeping the ROM's spin and turn-around.
local GEN2_WHIRLPOOL_SPIN_FRAMES = 32 -- the two `step_dig 16` beats
-- the turn-around has to be readable before a held direction can drive the
-- player straight back into the current
local GEN2_WHIRLPOOL_HOLD_FRAMES = 20
local GEN2_OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

function OverworldState:gen2IsWhirlpool(cx, cy)
  local tile = self.map and self.map:cellTile(cx, cy)
  return tile ~= nil and GEN2_OW_TILES.WHIRLPOOL[tile] == true
end

function OverworldState:checkGen2Whirlpool(dir)
  if self.whirlSpin then return true end
  if (self.whirlHold or 0) > 0 then return true end
  if not GameVersion.isGen2() then return false end
  local p = self.player
  if p.moving then return false end
  local facing = dir or p.facing
  if not self:gen2IsWhirlpool(Collision.target(p.cellX, p.cellY, facing)) then
    -- a save left standing on an eddy still has to be spun back out
    if not self:gen2IsWhirlpool(p.cellX, p.cellY) then return false end
  end
  -- Player:update counts spinFrames down and drops `spinning` for us, so the
  -- controller's own counter only has to own the facing flip + input gate.
  p.facing = facing
  p.spinning = true
  p.spinTimer = 0
  p.spinFrames = GEN2_WHIRLPOOL_SPIN_FRAMES
  p.spinTotal = GEN2_WHIRLPOOL_SPIN_FRAMES
  p.inputLocked = true
  self.whirlSpin = { frames = GEN2_WHIRLPOOL_SPIN_FRAMES,
                     hold = GEN2_WHIRLPOOL_HOLD_FRAMES,
                     facing = GEN2_OPPOSITE[facing] or facing }
  return true
end

-- CheckIceTile (00:$1749) is `cp $23 / ret z / cp $2B / ret z / scf / ret`,
-- so collision classes $23 and $2B are ice.  DoPlayerMovement.TryStep turns
-- any step that LANDS on one into STEP_ICE: the walk repeats in the same
-- direction, ignoring the d-pad, until the player leaves the ice or the next
-- cell is blocked.  Mahogany Gym's floor is the whole puzzle.
local GEN2_ICE_TILES = { [0x23] = true, [0x2B] = true }

-- THE SOOTOPOLIS GYM'S ICE, which is the whole of that gym.
--
-- You walk on it a cell at a time and it CRACKS under you; step on a cell you
-- have already cracked and it breaks, and you drop to the floor below at the
-- same x and y.  It is not the sliding ice above -- you do not slide on it at
-- all -- and it is a different behaviour byte for exactly that reason: the
-- engine has to remember which cells have been stepped on.
--
-- WHERE YOU LAND is derived rather than named: the floor below is the map
-- this one warps to with identical dimensions, which is what makes landing at
-- the same x and y meaningful (see RomExtractorGen3:iceBehaviours).  The Sky
-- Pillar's cracked floor is derived too but has no same-sized neighbour to
-- fall into, so it is recorded and left alone rather than guessed at.
--
-- The cracked cells live on the SAVE, keyed by map, because the puzzle has to
-- survive leaving the room -- which is the only reason it is a puzzle.
function OverworldState:thinIceState(mapId)
  local save = Game.save
  save.gen3ThinIce = save.gen3ThinIce or {}
  save.gen3ThinIce[mapId] = save.gen3ThinIce[mapId] or {}
  return save.gen3ThinIce[mapId]
end

-- ---------------------------------------------------------------------------
-- SWEEPING THE ASH.
--
-- Reported from play: "walking in the grass doesn't change the colour like
-- it's supposed to".  On the three maps under the volcano the tall grass is
-- covered in volcanic ash, and walking a clump sweeps it back to green -- and
-- fills the SOOT SACK, if you are carrying one, which is what the glass
-- workshop trades against.
--
-- This is the cartridge's per-step callback 1, and `setstepcallback` was
-- lowered to a nop, so all seven of them did nothing.  This is the first.
--
-- Nothing is named here: the maps are the ones whose setup script asks for
-- callback 1, the ash is the behaviour placed only on those maps, and what it
-- sweeps back to is the one ordinary grass metatile in the same bank of the
-- same tileset (RomExtractorGen3:ashGrass).
--
-- The sweep is not remembered across a load, and it should not be: the drawn
-- tiles are rebuilt from the map layout on entry, exactly as the ice is, and
-- the cartridge re-lays the ash the same way.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- PACIFIDLOG'S LOGS SINK.
--
-- The town is lashed-together logs floating on open water.  Step on one and
-- it settles; stand there and it goes under; step off and it comes back up.
-- The cartridge's third per-step callback, and it was a nop, so the town was
-- as solid as a pier.
--
-- A LOG IS TWO TILES and both halves move together, so the half you are
-- standing on has to say where the other one is.  It does: each of the four
-- behaviours carries a direction to its partner, read off the town's own
-- layout rather than assigned (RomExtractorGen3:pacifidlogLogs).
--
-- STEPPING FROM ONE END OF A LOG TO THE OTHER IS NOT STEPPING ONTO A NEW LOG.
-- It is the same log and it stays where it is -- which is why the log being
-- held down is remembered by its CELLS rather than by the tile under the
-- player, and why walking the length of one does not make it bob.
-- ---------------------------------------------------------------------------
local function logRecord(map)
  if not GameVersion.isGen3() then return nil end
  local logs = Game.data.constants and Game.data.constants.gen3Logs
  if not (map and logs and logs.partner and logs.swap) then return nil end
  if not (logs.maps and logs.maps[map.id]) then return nil end
  return logs
end

-- Put a log back on the surface.
function OverworldState:floatLog()
  local held = self.logSunk
  local map = self.map
  if not (held and map and map.id == held.mapId and map.setBlock) then
    self.logSunk = nil
    return false
  end
  local logs = logRecord(map)
  local swap = logs and logs.swap and logs.swap[map.def and map.def.tileset]
  if swap then
    for _, cell in ipairs(held.cells) do
      local states = swap[cell.behaviour]
      if states and states[1] then map:setBlock(cell.x, cell.y, states[1]) end
    end
    self:redrawBlocks(map)
  end
  self.logSunk = nil
  return true
end

function OverworldState:checkPacifidlogLogs()
  local map, p = self.map, self.player
  local logs = logRecord(map)
  if not (logs and p and map.cellBehaviour and map.setBlock) then
    if self.logSunk then self:floatLog() end
    return false
  end
  local behaviour = map:cellBehaviour(p.cellX, p.cellY)
  local row = behaviour and logs.partner[behaviour]
  if not row then
    self:floatLog()
    return false
  end
  local cells = {
    { x = p.cellX, y = p.cellY, behaviour = behaviour },
    { x = p.cellX + row.dx, y = p.cellY + row.dy, behaviour = row.other },
  }

  -- the same log, walked end to end, is not a new log
  local held = self.logSunk
  if held and held.mapId == map.id then
    local same = true
    for _, cell in ipairs(cells) do
      local found = false
      for _, was in ipairs(held.cells) do
        if was.x == cell.x and was.y == cell.y then found = true end
      end
      if not found then same = false end
    end
    if same then return false end
  end

  self:floatLog()
  local swap = logs.swap[map.def and map.def.tileset]
  if not swap then return false end
  for _, cell in ipairs(cells) do
    local states = swap[cell.behaviour]
    if states and states[2] then map:setBlock(cell.x, cell.y, states[2]) end
  end
  self:redrawBlocks(map)
  self.logSunk = { mapId = map.id, cells = cells, delay = logs.delay or 8 }
  return true
end

-- AND THEN IT GOES UNDER, on the clock rather than on the steps -- a log
-- settles the moment you land on it and sinks the rest of the way while you
-- stand there, which is a thing you can only express in frames.
function OverworldState:tickPacifidlogLogs()
  local held = self.logSunk
  local map = self.map
  if not (held and map and map.id == held.mapId) then return end
  if (held.delay or 0) <= 0 then return end
  if self.transitioning or self.runner:isRunning() then return end
  held.delay = held.delay - 1
  if held.delay > 0 then return end
  local logs = logRecord(map)
  local swap = logs and logs.swap and logs.swap[map.def and map.def.tileset]
  if not swap then return end
  for _, cell in ipairs(held.cells) do
    local states = swap[cell.behaviour]
    if states and #states >= 2 and map.setBlock then
      map:setBlock(cell.x, cell.y, states[#states])
    end
  end
  self:redrawBlocks(map)
end

-- ---------------------------------------------------------------------------
-- FORTREE'S ROPE BRIDGES SAG.
--
-- Fortree City is built in the trees and joined by rope bridges, and the
-- plank you are standing on drops under your weight and springs back when you
-- step off.  That is the cartridge's second per-step callback; it was a nop,
-- so the bridges were as stiff as the branches they hang from.
--
-- Only one plank is ever down, because only one has anybody on it -- so this
-- keeps exactly one, puts it back before lowering the next, and forgets it on
-- a map change, where the drawn tiles are rebuilt from the layout anyway.
--
-- Neither plank is named: the behaviour is the one placed in Fortree and
-- nowhere else in Hoenn, and the lowered plank is the metatile immediately
-- after a raised one that no map ever places, because it is not a place --
-- it is what the engine draws while you are standing there
-- (RomExtractorGen3:fortreeBridge).
-- ---------------------------------------------------------------------------
function OverworldState:checkFortreeBridge()
  if not GameVersion.isGen3() then return false end
  local map, p = self.map, self.player
  if not (map and p and map.setBlock and map.blockAt) then return false end
  local bridge = Game.data.constants and Game.data.constants.gen3Bridge
  if not (bridge and bridge.maps and bridge.maps[map.id]) then return false end

  -- the plank we just left springs back
  local down = self.bridgeDown
  if down and (down.mapId ~= map.id or down.x ~= p.cellX or down.y ~= p.cellY) then
    if down.mapId == map.id then
      map:setBlock(down.x, down.y, down.raised)
      self:redrawBlocks(map)
    end
    self.bridgeDown = nil
  end

  local swap = bridge.swap and bridge.swap[map.def and map.def.tileset]
  if not swap then return false end
  local here = map:blockAt(p.cellX, p.cellY)
  local lowered = here and swap[here]
  if not lowered then return false end
  map:setBlock(p.cellX, p.cellY, lowered)
  self:redrawBlocks(map)
  self.bridgeDown = { mapId = map.id, x = p.cellX, y = p.cellY, raised = here }
  return true
end

-- ---------------------------------------------------------------------------
-- THE FLOOR THAT GIVES WAY.
--
-- Six maps in Hoenn install the cartridge's seventh per-step callback, and it
-- was a nop, so the Sky Pillar had a cracked stone floor that never cracked --
-- and the Sky Pillar's floor is the only thing between the player and
-- Rayquaza.  Granite Cave, Mt Pyre and the Mirage Tower have the same floor.
--
-- HOW THE CARTRIDGE DOES IT, and why the shape matters.  It keeps TWO cells
-- pending, each with a short countdown.  Stepping onto a cracked floor arms a
-- free one; when a countdown reaches zero, that cell becomes a hole -- and if
-- the player is still standing on it, they go through.
--
-- The countdown is the whole puzzle.  On foot a step is long, so you are
-- still standing there when the floor goes and you drop to the room below;
-- on the bike a step is half as long and you are already moving off it, so
-- you cross.  Nothing here tests the player's SPEED -- the cartridge's own
-- routine does not either.  It falls out of the countdown, which is a much
-- better reason to believe it.
--
-- Neither behaviour is named: the floor and the hole are the two the tileset
-- carries, and the hole is the one whose metatile no map ever places, because
-- it is a state the engine writes (RomExtractorGen3:crackedFloor).
-- ---------------------------------------------------------------------------
local function crackedFloorRecord(map)
  if not GameVersion.isGen3() then return nil end
  local crack = Game.data.constants and Game.data.constants.gen3CrackedFloor
  if not (map and crack and crack.floor and crack.hole) then return nil end
  if not (crack.maps and crack.maps[map.id]) then return nil end
  return crack
end

-- The pending cells, per map: they are the engine's own working state and the
-- cartridge keeps them in its task, so they do not belong in the save and
-- they start empty on every entry.
function OverworldState:crackedFloorSlots(mapId, count)
  local state = self.crackedFloor
  if not state or state.mapId ~= mapId then
    state = { mapId = mapId, slots = {} }
    for i = 1, math.max(1, count or 2) do state.slots[i] = { delay = 0 } end
    self.crackedFloor = state
  end
  return state.slots
end

-- STEPPING ON IT arms a slot; that is all a step does.
function OverworldState:armCrackedFloor()
  local map, p = self.map, self.player
  local crack = crackedFloorRecord(map)
  if not (crack and p and map.cellBehaviour) then return false end
  if map:cellBehaviour(p.cellX, p.cellY) ~= crack.floor then return false end
  local slots = self:crackedFloorSlots(map.id, crack.slots)
  for _, slot in ipairs(slots) do
    if (slot.delay or 0) == 0 then
      slot.x, slot.y, slot.delay = p.cellX, p.cellY, crack.delay or 3
      return true
    end
  end
  return false
end

-- AND THE COUNTDOWN RUNS ON THE CLOCK, not on the steps -- which is the only
-- way a step's LENGTH can decide whether you fall.
function OverworldState:tickCrackedFloor()
  local map, p = self.map, self.player
  local crack = crackedFloorRecord(map)
  if not (crack and p) then return end
  if self.transitioning or self.runner:isRunning() then return end
  local slots = self:crackedFloorSlots(map.id, crack.slots)
  local swap = crack.swap and crack.swap[map.def and map.def.tileset]
  for _, slot in ipairs(slots) do
    if (slot.delay or 0) > 0 then
      slot.delay = slot.delay - 1
      if slot.delay == 0 and slot.x then
        if swap and swap.hole and map.setBlock then
          map:setBlock(slot.x, slot.y, swap.hole)
          self:redrawBlocks(map)
        end
        local under = (p.cellX == slot.x and p.cellY == slot.y)
                      and not p.moving
        slot.x, slot.y = nil, nil
        if under then self:gen3FallThroughFloor() end
      end
    end
  end
end

-- WHAT FALLING IS.  Not a warp: every floor in Hoenn that gives way carries
-- the fall in its own ON_FRAME_TABLE -- a row gated on a var whose script
-- locks the player, plays the slip and warps -- and the engine's whole part
-- in it is setting that var.  The same var and the same reasoning as the
-- Sootopolis ice, which is the other floor that does this.
function OverworldState:gen3FallThroughFloor()
  local map = self.map
  local ice = Game.data.constants and Game.data.constants.gen3Ice
  local trigger = ice and ice.fallTrigger and map and ice.fallTrigger[map.id]
  if not (trigger and trigger.var) then return false end
  require("src.script.Gen3Commands").setVar(Game.save, trigger.var,
                                            trigger.value or 0)
  return true
end

function OverworldState:checkAshGrass()
  if not GameVersion.isGen3() then return false end
  local map, p = self.map, self.player
  if not (map and p and map.cellBehaviour and map.setBlock) then return false end
  local ash = Game.data.constants and Game.data.constants.gen3Ash
  if not (ash and ash.behaviour) then return false end
  if not (ash.maps and ash.maps[map.id]) then return false end
  if map:cellBehaviour(p.cellX, p.cellY) ~= ash.behaviour then return false end

  local swap = ash.swap and ash.swap[map.def and map.def.tileset]
  if not (swap and swap.grass) then return false end
  if map.blockAt and map:blockAt(p.cellX, p.cellY) ~= swap.ash then
    return false
  end
  map:setBlock(p.cellX, p.cellY, swap.grass)
  self:redrawBlocks(map)

  -- WHAT GOES IN THE SACK.  The cartridge counts a clump only while the sack
  -- is in the bag, so a player who has not been given one yet sweeps the
  -- grass and gathers nothing -- which is the state most of the route is in
  -- the first time through.
  local sack = ash.sootSack
  local held = sack and Game.save and Game.save.inventory
               and (Game.save.inventory[sack] or 0) > 0
  if held then
    -- the cartridge stops counting at four nines, which is what the glass
    -- workshop's own totals are measured against
    local ASH_MAX = 9999
    local got = (Game.save.gen3AshGathered or 0) + 1
    Game.save.gen3AshGathered = math.min(got, ASH_MAX)
  end
  return true
end

function OverworldState:checkThinIce()
  if not GameVersion.isGen3() then return false end
  local map, p = self.map, self.player
  if not (map and map.isThinIceCell) then return false end
  if p.surfing then return false end
  if not map:isThinIceCell(p.cellX, p.cellY) then return false end

  local cracked = self:thinIceState(map.id)
  local key = p.cellY * (map.widthCells or 1) + p.cellX

  -- WHAT THE FLOOR LOOKS LIKE AFTERWARDS, which is the whole puzzle.
  --
  -- The gym's floor has three states and the map places only the first: the
  -- engine writes the cracked tile and the hole itself.  Remembering which
  -- cells had been stepped on without ever changing what was drawn made the
  -- puzzle unplayable -- the ice you had already crossed looked exactly like
  -- the ice you had not, so there was no way to see the path you were
  -- supposed to be tracing.
  --
  -- Both tiles are derived, not named (RomExtractorGen3:iceBehaviours): the
  -- cracked one is the unplaced metatile after a thin-ice one, and the hole
  -- is the unplaced metatile carrying the same cracked-floor behaviour the
  -- Sky Pillar's holes carry.
  local ice = Game.data.constants and Game.data.constants.gen3Ice
  local swap = ice and ice.swap and ice.swap[map.def and map.def.tileset]

  if not cracked[key] then
    -- first step: it cracks, and the player walks on
    cracked[key] = true
    if swap and swap.cracked then
      map:setBlock(p.cellX, p.cellY, swap.cracked)
      self:redrawBlocks(map)
    end
    return false
  end
  -- ...and the second step opens it
  if swap and swap.hole then
    map:setBlock(p.cellX, p.cellY, swap.hole)
    self:redrawBlocks(map)
  end

  -- SECOND STEP ON THE SAME CELL: IT GIVES WAY -- and the cartridge does not
  -- warp you, it writes a var.
  --
  -- Every floor in Hoenn that gives way carries the fall in its own
  -- ON_FRAME_TABLE: a row gated on a var whose script is `lockall /
  -- applymovement <the slip> / playse / warphole`.  The C code's whole part
  -- in it is setting that var.  Doing the warp here instead skipped the
  -- lockall, the slip, and the sound, and asked for a "Fall" cue by a name
  -- Gen 1 uses and this cartridge does not have -- so the floor gave way in
  -- silence and the player was simply somewhere else.
  --
  -- The var is derived, not named: it is the row that holds the `warphole`
  -- (see RomExtractorGen3:iceBehaviours).  Seven maps have one and they are
  -- the seven with thin ice or a cracked floor.
  local trigger = ice and ice.fallTrigger and ice.fallTrigger[map.id]
  if trigger and trigger.var then
    require("src.script.Gen3Commands").setVar(Game.save, trigger.var,
                                              trigger.value or 0)
    return true
  end

  -- No row to fire: fall the blunt way rather than leave the player standing
  -- on a floor that just broke.
  local below = ice and ice.fallThrough and ice.fallThrough[map.id]
  if not below then
    Logger.warn("gen3 thin ice: %s has neither a fall script nor a floor "
                  .. "below it -- the player cannot fall through",
                tostring(map.id))
    return false
  end
  p.inputLocked = true
  self:startWarpTo(below, p.cellX, p.cellY, p.facing)
  return true
end

-- HOENN'S WEATHER, in the two states the cartridge keeps it in.
--
--   `save.gen3Weather`       SetSav1Weather -- what the region WILL be
--   `save.gen3WeatherActive` DoCurrentWeather -- what it IS
--
-- Keeping them apart is not pedantry: `setweather` writes the first and
-- `doweather` copies it to the second, and every script in the game that
-- changes the weather does it in that order, usually with a fade between.
-- Collapsing them would start Route 119's rain a beat early and, worse, would
-- make `resetweather` (which restores the map's own) take effect before the
-- scene that asks for it has finished.
--
-- The NAME is what the engine carries from here on; the byte stays in the map
-- data.  A number filed where a name is wanted is this port's most expensive
-- recurring mistake.
function OverworldState:weatherName(value)
  local names = (Game.data.constants or {}).gen3WeatherNames
  local n = tonumber(value)
  return (names and n and names[n]) or nil
end

-- ---------------------------------------------------------------------------
-- THE FLAGS THAT ARE NOT MEANT TO LAST (ClearTempFieldEventData).
--
-- Emerald's first thirty-two flags are SCRATCH.  A scene sets one to remember
-- something for the length of a visit -- which of two people you spoke to
-- first, whether a cutscene has already played this time in the room -- and
-- the cartridge wipes the whole block on every map load, so the next room
-- starts from nothing.
--
-- Nothing here wiped them, and the scripts show exactly what that costs.
-- Flag $02 is used by EIGHT different maps and cleared by only three of them;
-- $01 by four, and never cleared at all.  Seventeen of the nineteen the
-- region uses are never cleared by ANY script, because they are not supposed
-- to be -- the map load is the only thing that resets them.  So the first
-- room to set $02 left it set for the whole save, and the other seven rooms
-- that ask about it took the already-happened branch on arrival, forever.
--
-- The range is the cartridge's and the evidence for it is in the scripts:
-- these ids are reused across maps twice as often as an ordinary flag, which
-- is what a shared scratch register looks like and what a scene's own flag
-- never does.
-- ---------------------------------------------------------------------------
local GEN3_TEMP_FLAG_FIRST = 0x00
local GEN3_TEMP_FLAG_LAST = 0x1F

function OverworldState:clearGen3TempFlags()
  if not GameVersion.isGen3() then return 0 end
  local flags = Game.save and Game.save.flags
  if not flags then return 0 end
  local VM = require("src.script.Gen3ScriptVM")
  local cleared = 0
  for id = GEN3_TEMP_FLAG_FIRST, GEN3_TEMP_FLAG_LAST do
    local key = VM.flagName(id)
    if flags[key] then
      flags[key] = nil
      cleared = cleared + 1
    end
  end
  return cleared
end

function OverworldState:applyMapWeather()
  if not GameVersion.isGen3() then return end
  local def = self.map and self.map.def
  local value = def and tonumber(def.weather)
  if value == nil then return end
  Game.save.gen3Weather = value
  -- the header's weather is active immediately; a script's is not
  Game.save.gen3WeatherActive = value
end

-- ---------------------------------------------------------------------------
-- AND WHAT YOU CAN SEE OF IT.
--
-- applyMapWeather has stored the byte since the map headers went in, and the
-- only thing that ever read it back was battleWeather -- so ninety maps in
-- Hoenn carried a weather that changed nothing you could look at.  Route 113
-- stood in clear air under the volcano, Route 120's fog was not there, and
-- the seafloor had no water in it.
--
-- The frame counter is the overworld's own rather than love's, so a paused
-- field has still weather and a save reloaded on the same map picks the
-- sequence up where it was rather than snapping.
-- ---------------------------------------------------------------------------
function OverworldState:fieldWeather()
  if not GameVersion.isGen3() then return nil end
  return self:weatherName(Game.save.gen3WeatherActive)
end

-- WHICH STEP OF A CYCLING ROUTE'S WEATHER TODAY IS.
--
-- UpdateWeatherPerDay: the cartridge keeps a stage byte in the save and
-- advances it by the number of days that have passed since it last looked --
-- so Route 119's weather is settled for the whole day and changes overnight.
-- This port already reads the real clock for its time of day, so the same
-- rule is the same rule here: today's calendar day against the one the save
-- last saw.
--
-- A save that has never seen a day starts where the cartridge starts, stage
-- 0, rather than at some frame count -- which is what made the rain come and
-- go while you stood still.
function OverworldState:gen3WeatherStage()
  local save = Game.save
  if not save then return 0 end
  local today = math.floor((os.time() or 0) / 86400)
  local seen = tonumber(save.gen3WeatherDay)
  local stage = math.floor(tonumber(save.gen3WeatherStage) or 0)
  if seen and today > seen then stage = stage + (today - seen) end
  if not seen or today ~= seen then
    save.gen3WeatherDay = today
    save.gen3WeatherStage = stage % 4
  end
  return stage % 4
end

-- WHAT THE WEATHER CAME OUT AS, once per map.
--
-- Reported from play: "rain doesnt seem to be working in routes that call for
-- it".  There are four links between a route and its rain -- the header's
-- byte, the transition script that may replace it, the name the dataset gives
-- that byte, and the CYCLE step today falls on -- and no map header in Hoenn
-- sets RAIN at all: the two routes that rain say so through a special, and
-- their cycle is sunny on one day in four (Route 119) or three (Route 123).
-- So "no rain" is four different bugs and one correct answer wearing the same
-- face, and this line is what tells them apart in a log.
function OverworldState:logGen3Weather()
  if not GameVersion.isGen3() then return end
  local save = Game.save
  if not save then return end
  local Gen3Weather = require("src.world.Gen3Weather")
  local value = save.gen3WeatherActive
  local name = self:weatherName(value)
  local stage = self:gen3WeatherStage()
  local resolved = name and Gen3Weather.resolve(name, 0, stage) or nil
  local draws = name and Gen3Weather.draws(name, 0, stage) or false
  Logger.info("gen3 weather: %s header=%s active=%s%s stage=%d -> %s (%s)",
              tostring(self.map and self.map.id),
              tostring(self.map and self.map.def and self.map.def.weather),
              tostring(value),
              name and (" " .. name) or " <this dataset has no name for it>",
              stage, tostring(resolved),
              draws and "drawn" or "nothing to draw")
end

function OverworldState:drawFieldWeather()
  local name = self:fieldWeather()
  if not name then return false end
  local Gen3Weather = require("src.world.Gen3Weather")
  local frame = self.weatherFrame or 0
  local stage = self:gen3WeatherStage()
  if not Gen3Weather.draws(name, frame, stage) then return false end
  local w, h = self:uiSize()
  return Gen3Weather.draw(name, frame, w, h, stage) and true or false
end

-- What a battle begun here starts under.  Only four of the sixteen weathers
-- are weather in the battle sense -- the ash on Mt Chimney, the cave fog, the
-- shade and the underwater bubbles are things you see and nothing more -- and
-- the mapping from the field's sixteen to the battle's four comes from the
-- import rather than being restated here.
function OverworldState:battleWeather()
  if not GameVersion.isGen3() then return nil end
  local name = self:weatherName(Game.save.gen3WeatherActive)
  if not name then return nil end
  -- ...and a CYCLING route names a sequence rather than a weather, so ask it
  -- which step today is before looking the battle weather up.  Route 119 in
  -- the rain has to start a battle in the rain.
  name = require("src.world.Gen3Weather").resolve(name, 0,
                                                  self:gen3WeatherStage())
  local map = (Game.data.constants or {}).gen3BattleWeather
  return map and map[name] or nil
end

-- THE WATER CURRENTS SOUTH OF PACIFIDLOG.
--
-- 4,384 cells over five sea routes, and the whole reason Routes 132, 133 and
-- 134 are a maze rather than open water: a current carries a surfer one cell
-- in its own direction every step, and the westward one is 3,844 of those
-- cells, which is why you cannot simply paddle east back to Slateport.
--
-- Same shape as Johto's Whirl Islands current and Kanto's Seafoam one -- and
-- deliberately NOT routed through checkSeafoamCurrent, which reads a
-- hand-placed coordinate table from field.lua.  Hoenn says it with a
-- behaviour byte on every cell, and there are 4,384 of them.
--
-- The push reuses Collision.canMove, so a current that runs into a rock or
-- the map edge stops the surfer there rather than carrying them into it --
-- which is the cartridge's DoForcedMovement, whose collision check is the
-- ordinary one.
function OverworldState:checkGen3Current()
  if not GameVersion.isGen3() then return false end
  local map, p = self.map, self.player
  if not (map and map.currentAt) then return false end
  -- a current is water: you meet it surfing or not at all
  if not p.surfing then
    self.gen3Current = nil
    return false
  end
  local way = map:currentAt(p.cellX, p.cellY)
  if not way then
    self.gen3Current = nil
    return false
  end
  if not Collision.canMove(map, self.entities, p, way) then
    self.gen3Current = nil
    return false
  end
  self.gen3Current = way
  p.facing = way
  self:scriptMove(p, way, 1, function() self:onStepComplete() end)
  return true
end

-- THE MUDDY SLOPE, which is the other half of Hoenn's bike terrain and the
-- half that is not a wall.
--
-- pret's ForcedMovement_MuddySlope: while you are standing on MB_MUDDY_SLOPE
-- you are pushed SOUTH one cell with your facing LOCKED, unless you are
-- moving north at a speed above 3 -- which only the Mach Bike reaches.  So on
-- foot the slope is climbable one step at a time and un-climbable in effect:
-- you take a step up, the slope takes it back.  That is the whole gate on
-- Route 111's desert approach, Route 115's north shelf and Route 119.
--
-- It is deliberately NOT a wall.  Making it one would look the same from
-- below and be wrong from above: you walk DOWN a muddy slope perfectly well,
-- because the push and the walk agree on the direction.
--
-- The push reuses the same permission check the ice slide does, so a slope
-- whose southern neighbour is blocked (the bottom of the run) stops the
-- player rather than walking them into a wall.
-- ---------------------------------------------------------------------------
-- THE ACRO BIKE, WHICH IS A STATE MACHINE AND WAS A BOOLEAN.
--
-- Reported from play: "make sure the acro and the mach bike both function as
-- they intended and have the bunny hop feature".  The port had B-held mean
-- "hopping" outright, and that is not what the cartridge does at any point.
--
-- PRESSING B STANDS THE BIKE UP.  A tap of B while stationary puts the rider
-- into a WHEELIE -- front wheel off the ground, going nowhere.  Keep B down
-- and a counter runs; only once it passes its threshold does the wheelie
-- become the BUNNY HOP, and only then is the rider hopping.  Letting B go
-- drops back to normal -- unless the cell underneath is a bumpy slope, where
-- the cartridge holds the wheelie rather than dumping the rider off it.
--
-- Holding B while MOVING is the moving wheelie, which is a different thing
-- again: it rides rails but does not hop.
--
-- The threshold is not written here.  extractBike derives it out of the
-- handler that reads it (see constants.gen3Bike.rules.acroHopFrames), along
-- with the two bikes' speeds, and the engine degrades to plain riding if the
-- derivation ever comes back empty.
-- ---------------------------------------------------------------------------
-- BORROWED, like scriptMove above: the bike rules are asked for by tests that
-- drive the state machine on a plain table, before any map has been entered
-- and so before the file-level `Game` upvalue has been bound.
function OverworldState:bikeRules()
  local G = Game or require("src.core.Game")
  local data = G and G.data
  local bike = data and data.constants and data.constants.gen3Bike
  return bike and bike.rules or nil
end

-- The direction a mud ramp may be climbed in.  The cartridge stores it as a
-- movement-direction nibble; the extractor derives the nibble and this is the
-- one place it becomes a word the rest of the engine speaks.
local MUDDY_DIRECTIONS = { [1] = "down", [2] = "up", [3] = "left", [4] = "right" }
local MUDDY_OPPOSITE = { down = "up", up = "down", left = "right", right = "left" }

function OverworldState:machCounterMax()
  local rules = self:bikeRules()
  local ladder = rules and rules.machLadder
  if type(ladder) == "table" and #ladder > 0 then return #ladder - 1 end
  return math.floor(tonumber(rules and rules.machCounterMax) or 2)
end

-- GetPlayerSpeed, in the engine's own terms.  Every arm of it is derived.
function OverworldState:playerSpeed()
  local p, rules = self.player, self:bikeRules()
  if not rules then
    -- with no derivation, only the mach bike is ever given the ramp, and only
    -- once its counter is full -- which is the safe half of the old rule
    return (p.machBike and (p.bikeCounter or 0) >= 2) and 4 or 1
  end
  if p.machBike then
    local ladder = rules.machLadder or {}
    local at = math.min(#ladder, math.floor(p.bikeCounter or 0) + 1)
    return math.floor(tonumber(ladder[at]) or 1)
  end
  if p.acroBike then return math.floor(tonumber(rules.acroSpeed) or 3) end
  if p.surfing then return math.floor(tonumber(rules.surfSpeed) or 2) end
  return math.floor(tonumber(rules.footSpeed) or 1)
end

function OverworldState:updateAcroBike()
  local p = self.player
  if not p.acroBike then
    p.acroState, p.acroTrick, p.acroHold = nil, nil, nil
    return
  end
  local rules = self:bikeRules()
  local frames = math.floor(tonumber(rules and rules.acroHopFrames) or 0)
  local G = Game or require("src.core.Game")
  local input = G and G.input
  local held = (input and input.isDown and input:isDown("b")) and true or false
  local state = p.acroState or "normal"

  if not held then
    -- LETTING GO ON A BUMPY SLOPE KEEPS THE WHEELIE.  Everywhere else the
    -- rider drops back to normal, but the cartridge will not put a rider's
    -- front wheel down on a bumpy slope -- it holds the wheelie instead, so
    -- the cell stays passable and you are not stranded on it.
    if state ~= "normal" and self:acroBumpyHere() then
      state = "wheelieStanding"
    else
      state = "normal"
    end
    p.acroHold = 0
  elseif state == "normal" then
    -- pressing B stands the bike up; it is not a hop yet
    state = "wheelieStanding"
    p.acroHold = 1
  elseif p.moving then
    -- ...AND A WHEELIE UNDER WAY IS NOT COUNTING TOWARDS A HOP.  Only the
    -- standing handler raises the counter on the cartridge, so riding around
    -- with B down must not bank frames that turn into a hop the moment the
    -- rider stops.
    if state == "wheelieStanding" then state = "wheelieMoving" end
    if state ~= "bunnyHop" then p.acroHold = 0 end
  else
    if state == "wheelieMoving" then
      state = "wheelieStanding"
      p.acroHold = 0
    end
    p.acroHold = (p.acroHold or 0) + 1
    if state == "wheelieStanding" and frames > 0 and p.acroHold >= frames then
      state = "bunnyHop"
    end
  end

  p.acroState = state
  -- what the collision test asks for
  if state == "bunnyHop" then p.acroTrick = "hop"
  elseif state == "wheelieStanding" or state == "wheelieMoving" then
    p.acroTrick = "wheelie"
  else p.acroTrick = nil end
end

-- Is the cell the rider is standing on a bumpy slope?  The behaviours come
-- out of the tileset pair, so this asks the map rather than a list.
function OverworldState:acroBumpyHere()
  local map, p = self.map, self.player
  local obstacles = map and map.tileset and map.tileset.acroObstacles
  if not (obstacles and map.blockAt and map.tileset.collision) then return false end
  local block = map:blockAt(p.cellX, p.cellY)
  local behaviour = block and map.tileset.collision[block + 1]
  local row = behaviour and obstacles[behaviour]
  return (row and row.kind == "bumpy_slope") == true
end

function OverworldState:checkMuddySlope()
  if not GameVersion.isGen3() then return false end
  local map, p = self.map, self.player
  if not (map and map.muddySlopeAt) then return false end
  if p.surfing then return false end
  if not map:muddySlopeAt(p.cellX, p.cellY) then
    self.muddySlide = nil
    return false
  end
  -- THE ONE THING THAT BEATS A MUD RAMP is the Mach Bike at the top of its
  -- ladder, going UP.  Both halves are derived: ForcedMovement_MuddySlope
  -- pushes you south unless your movement direction is north AND your speed
  -- is strictly above its own threshold, and the only speed in the game above
  -- that threshold is the mach ladder's last rung (the extractor refuses to
  -- record the rule unless that is still true).
  local rules = self:bikeRules()
  local minSpeed = math.floor(tonumber(rules and rules.muddyMinSpeed) or 3)
  local climb = MUDDY_DIRECTIONS[math.floor(tonumber(rules and rules.muddyDirection) or 2)]
             or "up"
  if p.facing == climb and self:playerSpeed() > minSpeed then
    self.muddySlide = nil
    return false
  end
  -- ...and you are pushed back the way the ramp faces, which is the opposite
  -- of the one direction it can be climbed in
  local slide = MUDDY_OPPOSITE[climb] or "down"
  if not Collision.canMove(map, self.entities, p, slide) then
    self.muddySlide = nil
    return false
  end
  -- facingDirectionLocked: you are pushed back down still looking the way you
  -- were, which is what makes walking up a slope look like walking up a slope
  self.muddySlide = true
  self:scriptMove(p, slide, 1, function() self:onStepComplete() end, true)
  return true
end

function OverworldState:gen2IsIce(cx, cy)
  local tile = self.map and self.map:cellTile(cx, cy)
  return tile ~= nil and GEN2_ICE_TILES[tile] == true
end

-- ICE, WHOEVER'S IT IS.  Johto names it by a collision class and Hoenn by a
-- behaviour byte, and the SLIDE is the same in both -- so the question of
-- which cells are slippery is asked here once and the slide below never has
-- to know which cartridge it is on.  This is why the function that used to
-- be Gen-2-only now is not: Emerald has ice, and checkGen2Ice returned false
-- on sight of a Gen 3 save, so the one sliding floor in the region was
-- ordinary ground.
function OverworldState:isIceCell(cx, cy)
  if not self.map then return false end
  if GameVersion.isGen2() then return self:gen2IsIce(cx, cy) end
  return self.map.isIceCell ~= nil and self.map:isIceCell(cx, cy)
end

function OverworldState:checkGen2Ice()
  if not (GameVersion.isGen2() or GameVersion.isGen3()) then return false end
  local p = self.player
  if p.surfing or not self:isIceCell(p.cellX, p.cellY) then
    self.iceSlide = nil
    return false
  end
  local dir = self.iceSlide or p.facing
  -- Full permission check (bounds, walkable, side walls, pairs, entities).
  -- Ice Path cliffs are LAND with a directional wall; isWalkableCell alone
  -- lets the slide walk straight off them and off the map edge.
  local allowed = Collision.canMove(self.map, self.entities, p, dir)
  if not allowed then
    self.iceSlide = nil
    return false
  end
  self.iceSlide = dir
  p.facing = dir
  self:scriptMove(p, dir, 1, function() self:onStepComplete() end)
  return true
end

-- "<mon> used MOVE!" -- GSC's text_ram command ($01, dw wStringBuffer2) is
-- still raw bytes in the extracted text.
local function gen2MonText(key, fallback, name)
  local text = Game.data.text[key]
  if not text then return fallback end
  return (text:gsub("{BYTE:01}{BYTE:7E}{BYTE:CF}", name):gsub("{RAM:[%w_]+}", name))
end

-- The party menu's field-move entry point.  GSC routes the menu and the
-- overworld A press through the same handlers (SurfFromMenuScript,
-- HeadbuttFromMenuScript), so the tile rules live in one place.  Returns
-- false when the move has nothing to act on, which is the caller's cue to
-- print the refusal.
function OverworldState:gen2FieldMoveAt(move, mon, fx, fy)
  if move == "SWEET_SCENT" then return self:gen2SweetScent() end
  -- RockSmashFunction -> TryRockSmashFromMenu: Rock Smash acts on an OBJECT
  -- (GetFacingObject + SPRITEMOVEDATA_SMASHABLE_ROCK), not on a tile, so it
  -- has no GEN2_OW_TILES row.  Hand off to the rock's own script, which is
  -- AskRockSmashScript / RockSmashScript.
  if move == "ROCK_SMASH" then
    local npc = self:npcAtCell(fx, fy)
    if not (npc and Map.isSmashable(npc.def) and not npc.moving) then
      return false
    end
    self:talkTo(npc)
    return true
  end
  local classes = GEN2_OW_TILES[move]
  if not (classes and self.map:inBounds(fx, fy)
          and classes[self.map:cellTile(fx, fy)]) then
    return false
  end
  self:gen2UseFieldMove(move, mon, fx, fy)
  return true
end

-- SweetScentFromMenu (engine/events/sweet_scent.asm): a guaranteed
-- encounter on the tile the player is standing on, or "Nothing appeared..."
-- where nothing lives.
function OverworldState:gen2SweetScent()
  local p = self.player
  local encDef = Game.data.encounters[self.map.id]
  local slots = encDef and Encounter.atTime(encDef.grass, self:timeOfDay())
  if p.surfing and encDef and encDef.water
     and self.map:isWaterCell(p.cellX, p.cellY) then
    slots = encDef.water
  end
  local enc = slots and self:rollEncounter({ grass = slots }, "grass")
  if not enc then
    Game.stack:push(TextBox.new(Game, Strings("Nothing appeared…")))
    return true
  end
  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(Game, enc.species, enc.level)
  battle.onFinish = function(result) self:afterBattle(result, battle) end
  self:pushBattle(battle)
  return true
end

function OverworldState:tryFieldMoveOW(fx, fy)
  if GameVersion.isGen2() and self:tryCutOW(fx, fy) then return true end
  if not self.map:inBounds(fx, fy) then return false end
  local move
  -- GEN2_OW_TILES is a list of GSC COLLISION CLASSES, and a Gen 3 cell's
  -- `tile` is its metatile BEHAVIOUR byte -- different numbers meaning
  -- different things.  Reading one as the other offers HEADBUTT at a
  -- doorway; the Gen 3 arms below name what they read instead.
  if GameVersion.isGen2() then
    local coll = self.map:cellTile(fx, fy)
    for id, classes in pairs(GEN2_OW_TILES) do
      if classes[coll] then move = id end
    end
  end

  -- Gen2 TrySurfOW: pressing A on a water cell while not surfing asks
  -- whether the player wants to SURF.  Water is detected via isWaterCell
  -- (uses the tileset's extracted waterTiles collision classes) rather than
  -- GEN2_OW_TILES so that all water variants are covered without listing
  -- every possible collision class here.
  if not move and GameVersion.isGen2()
      and self:tilesetHasWater() and self.map:isWaterCell(fx, fy)
      and not self.player.surfing then
    move = "SURF"
  end

  -- GEN 3 OFFERS SURF THE SAME WAY, and needs no tileset list to do it.
  --
  -- GetInteractedWaterScript: press A facing surfable water with the badge
  -- and a Pokemon that knows SURF, and the game asks.  isWaterCell answers
  -- from the cell's elevation on this cartridge, so every pond, sea and
  -- current in the region is covered without naming one of them -- and
  -- shallow water, which you walk through rather than surf, is elevation 3
  -- and correctly not offered.
  if not move and GameVersion.isGen3()
      and self.map:isWaterCell(fx, fy) and not self.player.surfing then
    move = "SURF"
  end

  if not move then return false end
  -- TryHeadbuttOW.no / TryWhirlpoolOW.failed: no eligible mon means no
  -- prompt at all for HEADBUTT, and each water move has its own refusal
  -- (Script_MightyWhirlpool / .DontHaveWaterfall)
  local mon = self:partyKnows(move)
  if not mon then
    if move == "HEADBUTT" then return false end
    if move == "SURF" then return false end  -- no mon -> no prompt for SURF
    if (move == "WHIRLPOOL" or move == "WATERFALL") and not self.player.surfing then
      return false
    end
    local key = (move == "WATERFALL") and "_HugeWaterfallText"
                                       or "_MayPassWhirlpoolText"
    Game.stack:push(TextBox.new(Game,
      Game.data.text[key] or Game.data.text._CantSurfText
        or Strings("You can't use that\nhere.")))
    return true
  end
  -- WHIRLPOOL/WATERFALL only work while surfing; SURF can only be mounted
  -- while NOT surfing (dismount is via the party menu)
  if (move == "WHIRLPOOL" or move == "WATERFALL") and not self.player.surfing then
    return false
  end
  if move == "SURF" then
    -- TrySurfOW (Gen2): check badge + position, then ask yes/no.  Any other
    -- reason is a silent `ret c` in the ROM, so let interact() carry on to
    -- its remaining handlers instead of eating the A press.
    local reason = self:useSurfFieldMove()
    if reason ~= "ok" then return false end
    Game.stack:push(TextBox.new(Game,
      self:gen3FieldText("SURF", "ask")
        or Game.data.text._AskSurfText
        or Strings("The water looks\ndeep. Want to\nSURF?"),
      nil, { choice = function(yes)
        if yes then
          self:trySurf(fx, fy)
        end
      end }))
    return true
  end
  local ask = ({
    HEADBUTT = "_AskHeadbuttText",
    WHIRLPOOL = "_AskWhirlpoolText",
    WATERFALL = "_AskWaterfallText",
  })[move]
  Game.stack:push(TextBox.new(Game, Game.data.text[ask] or Strings("Use %s?", move),
    nil, { choice = function(yes)
      if yes then self:gen2UseFieldMove(move, mon, fx, fy) end
    end }))
  return true
end

function OverworldState:gen2UseFieldMove(move, mon, fx, fy)
  local name = mon.nickname or Game.data.pokemon[mon.species].name
  local used = ({
    HEADBUTT = "_UseHeadbuttText",
    WHIRLPOOL = "_UseWhirlpoolText",
    WATERFALL = "_UseWaterfallText",
  })[move]
  local text = gen2MonText(used, Strings("%s used\n%s!", name, move), name)
  Game.stack:push(TextBox.new(Game, text, function()
    if move == "HEADBUTT" then
      self:gen2Headbutt(fx, fy)
    elseif move == "WHIRLPOOL" then
      -- Script_UsedWhirlpool -> DisappearWhirlpool: the eddy block is
      -- replaced with plain water and the map refreshed.  The player stays
      -- exactly where they are.
      local row, bx, by = self:gen2WhirlpoolSwap(fx, fy)
      if row then
        self.cutBlocks = self.cutBlocks or {}
        self.cutBlocks[self.map.id] = self.cutBlocks[self.map.id] or {}
        table.insert(self.cutBlocks[self.map.id],
                     { bx = bx, by = by, block = row.before })
        self.map:setBlock(bx, by, row.after)
        self.map.renderer:rebuild()
      end
      self:startDustAnim(fx, fy, function()
        require("src.core.Sound").play(Game.data, "Cut")
      end)
    else
      -- WATERFALL climbs while there is still waterfall above (the ROM
      -- re-runs CheckWaterfallTile each step)
      local classes = GEN2_OW_TILES.WATERFALL
      local cx, cy = fx, fy
      local tiles = 0
      while self.map:inBounds(cx, cy) and classes[self.map:cellTile(cx, cy)] do
        tiles = tiles + 1
        cy = cy - 1
      end
      if tiles > 0 then self:scriptMove(self.player, "up", tiles) end
    end
  end))
end

-- GetTreeScore (2E:$4443).  A tree's quality is FIXED for a given save: the
-- coordinate score `((x*y + x + y) / 5) % 10` is compared against the player's
-- own `OT ID % 10`, and the difference picks the tree.  Lua's % is already
-- floored, so this matches the ROM's `sub` plus `add 10` on borrow.
--
-- The port's cell coordinates are not the ROM's wram coordinates, so a GIVEN
-- tree will not be the same quality it is on a cartridge -- but the spread
-- across trees, and the fact that a tree never changes, both hold.
local function gen2TreeScore(fx, fy, otId)
  local coord = math.floor(((fx * fy) + fx + fy) / 5) % 10
  return (coord - ((tonumber(otId) or 0) % 10)) % 10
end

-- SelectTreeMon (2E:$441F): roll 0-99, then walk the table subtracting each
-- row's chance until it goes negative.
local function gen2SelectTreeMon(rows)
  local roll = math.random(0, 99)
  for _, row in ipairs(rows or {}) do
    roll = roll - (tonumber(row.chance) or 0)
    if roll < 0 then return row end
  end
  return nil
end

-- HeadbuttScript: the struck tree rattles (ShakeHeadbuttTree 23:$4A8E) and
-- then either a TreeMon drops out or nothing does.  GetTreeMon (2E:$43E5)
-- turns the tree score into both the odds AND which table is rolled:
--   score 5-9 (bad)  -- 1 in 10, common table
--   score 1-4 (good) -- 5 in 10, common table
--   score 0   (rare) -- 8 in 10, RARE table
--
-- The old code rolled 1-100, gated on `roll <= 50`, then compared that SAME
-- roll against a running total that started at the first row's 50 -- so row
-- one won every time a mon appeared at all (Gold's Forest set opens with
-- CATERPIE), and the rare table was a made-up 1-in-32.
function OverworldState:gen2Headbutt(fx, fy)
  self:startDustAnim(fx, fy, function()
    local trees = Game.data.field.gen2TreeMons
    local set = trees and trees.maps and trees.maps[self.map.def.label]
    local sets = set and trees.sets and trees.sets[set]
    local pick
    if sets then
      local score = gen2TreeScore(fx, fy,
        Game.save and Game.save.player and Game.save.player.id)
      local rows, odds
      if score == 0 then rows, odds = sets.rare, 8
      elseif score < 5 then rows, odds = sets.common, 5
      else rows, odds = sets.common, 1 end
      if rows and math.random(0, 9) < odds then
        pick = gen2SelectTreeMon(rows)
      end
    end
    if not pick then
      Game.stack:push(TextBox.new(Game,
        Game.data.text._HeadbuttNothingText or Strings("Nope. Nothing…")))
      return
    end
    local BattleState = require("src.battle.BattleState")
    local battle = BattleState.newWild(Game, pick.species, pick.level)
    battle.onFinish = function(result) self:afterBattle(result, battle) end
    self:pushBattle(battle)
  end)
end

-- TryCutOW (03:$5193): pressing A into a COLL_CUT_TREE cell.  With a CUT mon
-- and the HIVEBADGE it runs AskCutScript -- "This tree can be CUT! Want to
-- use CUT?" plus a YES/NO -- and otherwise CantCutScript, which only states
-- that the tree can be cut.  R/B had no equivalent, so the port silently did
-- nothing when the player talked to a tree.
function OverworldState:tryCutOW(fx, fy)
  if not self:gen2CutSwap(fx, fy) then return false end
  local t = Game.data.text
  if not self:partyKnows("CUT") then
    Game.stack:push(TextBox.new(Game,
      t._CanCutText or Strings("This tree can be\nCUT!")))
    return true
  end
  Game.stack:push(TextBox.new(Game,
    t._AskCutText or Strings("This tree can be\nCUT!\fWant to use CUT?"),
    nil, { choice = function(yes)
      if yes then self:gen2Cut(fx, fy) end
    end }))
  return true
end

-- CutFunction.DoCut -> CutDownTreeOrGrass (03:$4855): overwrite the block
-- with the table's replacement, then run the sprite animation the row names.
-- The "used CUT!" line is _UseCutText, printed by the script the field move
-- runs, so it shows here exactly like Gen1's _UsedCutText.
function OverworldState:gen2Cut(fx, fy)
  local swap, bx, by = self:gen2CutSwap(fx, fy)
  if not swap then return false end
  local mon = self:partyKnows("CUT")
  if not mon then return false end
  local name = mon.nickname or Game.data.pokemon[mon.species].name
  local text = gen2MonText("_UseCutText", Strings("%s used\nCUT!", name), name)
  Game.stack:push(TextBox.new(Game, text, function()
    self.cutBlocks = self.cutBlocks or {}
    self.cutBlocks[self.map.id] = self.cutBlocks[self.map.id] or {}
    table.insert(self.cutBlocks[self.map.id],
                 { bx = bx, by = by, block = swap.before })
    self.map:setBlock(bx, by, swap.after)
    self.map.renderer:rebuild()
    local finish = function() require("src.core.Sound").play(Game.data, "Cut") end
    if swap.anim == "tree" then
      self:startCutTreeAnim(fx, fy, finish)
    else
      self:startDustAnim(fx, fy, finish)
    end
  end))
  return true
end

-- The cut-tree split (engine/overworld/cut.asm InitCutAnimOAM +
-- engine/overworld/cut2.asm AnimCut): the tree sprite's top half slides
-- +1px and its bottom half -1px per frame for 8 frames, flickering,
-- before the swapped block shows through.  Falls back to the dust puff
-- when the extracted tree sprite is unavailable.
function OverworldState:startCutTreeAnim(cx, cy, onDone)
  local fxDef = Game.data.field.overworldFx
  if not (fxDef and fxDef.cutTree) then
    return self:startDustAnim(cx, cy, onDone)
  end
  self.cutAnim = { x = cx, y = cy, frames = 8, total = 8, onDone = onDone }
end

-- Party-menu SURF entry (start_sub_menus.asm .surf): badge-check SOULBADGE,
-- farcall IsSurfingAllowed, then UseItem(SURFBOARD) -> ItemUseSurfboard
-- (item_effects.asm), which either tries to dismount (already surfing) or
-- runs IsNextTileShoreOrWater on the tile the player is FACING and jumps
-- to SurfingAttemptFailed (_NoSurfingHereText) if it isn't water.  This is
-- a side-effect-free check that reports which text/flow the caller should
-- use; the actual mount happens in trySurf on "ok".  Returns:
--   "no_badge"    -> SOULBADGE missing / no SURF mon (_NewBadgeRequiredText)
--   "forced_bike" -> on the Cycling Road (_CyclingIsFunText)
--   "current"     -> Seafoam B4F stairs before the boulders (_CurrentTooFastText)
--   "dismount"    -> already surfing, facing dry land; caller steps forward
--   "no_place"    -> already surfing, nowhere to land (_SurfingNoPlaceToGetOffText)
--   "no_water"    -> not facing water (_NoSurfingHereText)
--   "ok"          -> facing water; caller may call trySurf(fx, fy)
function OverworldState:useSurfFieldMove()
  if not self:partyKnows("SURF") then return "no_badge" end
  local p = self.player
  -- Gen 3's gate is the BADGE and the water, and nothing else: no forced
  -- bike, no Seafoam stair case, and the dismount is a step onto land rather
  -- than a party-menu action.
  --
  -- The badge is the one the extractor placed by reading the cartridge's own
  -- field-move scripts -- Cut asks for the first badge, Rock Smash the third,
  -- Strength the fourth, and those three agree on where the block of eight
  -- starts.  Surf is the fifth.
  if GameVersion.isGen3() then
    if not gen3BadgeHeld("SURF") then return "no_badge" end
    if p.surfing then
      return self:facingIsLandDismount() and "dismount" or "no_place"
    end
    return self:facingIsShoreOrWater() and "ok" or "no_water"
  end
  -- IsSurfingAllowed (engine/overworld/field_move_messages.asm): surfing
  -- is refused while BIT_ALWAYS_ON_BIKE of wStatusFlags6 is set (the
  -- Cycling Road, armed by the forced-bike tiles and cleared by the
  -- Route 16/18 gate scripts / fly + dungeon warps / blackouts), and on
  -- SEAFOAM_ISLANDS_B4F standing on the stairs square (dbmapcoord 7,11)
  -- until both EVENT_SEAFOAM4_BOULDER*_DOWN_HOLE events are set.
  if Game.save.forcedBike then return "forced_bike" end
  if self:surfBlockedHere() then return "current" end
  if p.surfing then
    -- ItemUseSurfboard .tryToStopSurfing: blocked by a sprite in front
    -- (IsSpriteInFrontOfPlayer2), a water tile-pair collision, or a
    -- facing tile that isn't in the tileset's land-passable list;
    -- otherwise the player walks forward off the water.  Facing a land
    -- cell across a map connection (Cinnabar east coast) counts too --
    -- pokered reads that landing from the connection strip.
    if self:facingIsLandDismount() then
      return "dismount"
    end
    return "no_place"
  end
  -- IsNextTileShoreOrWater, including connection-strip water (issue #125)
  if not self:facingIsShoreOrWater() then
    return "no_water"
  end
  return "ok"
end


-- ---------------------------------------------------------------------------
-- DIVE
--
-- Steven teaches the whole mechanic on the cartridge: "While you're using
-- SURF, you should notice dark patches of water.  Use DIVE if you come to
-- deep water like it.  You'll drop to the seafloor.  When you want to come
-- back up, use DIVE again.  In some places, it won't be possible for you to
-- surface, though."
--
-- Three of those clauses are data, and all three come out of the import:
--
--   * the dark patches are one metatile behaviour (constants.gen3Dive.behaviour);
--   * the seafloor under a route is a whole separate map, named by the route
--     header's own connection list -- direction 5 down, 6 back up -- and the
--     same size to the cell, which is why the warp keeps (x, y) exactly;
--   * the places you cannot surface are two more behaviours, on the seafloor
--     side (constants.gen3Dive.noSurfacing).
--
-- Underwater the player is NOT surfing: the seafloor is elevation 3, the
-- same as dry land, and setMap takes the arrival cell's elevation -- so the
-- walk down there needs nothing special from Collision at all.
-- ---------------------------------------------------------------------------

-- The badge a Gen 3 field move costs, from the block the extractor placed by
-- reading the cartridge's own field-move scripts.  A dataset with no gate
-- charges nothing rather than refusing everything.
function OverworldState:gen3HasBadge(moveId)
  return gen3BadgeHeld(moveId)
end

-- One of the cartridge's own field-move lines, or nil when the import did
-- not place it (an older cache) -- every caller has a fallback.
function OverworldState:gen3FieldText(moveId, slot)
  local placed = Game.data.constants and Game.data.constants.gen3FieldMoveText
  local record = placed and placed[moveId]
  local key = record and record[slot]
  return key and Game.data.text and Game.data.text[key] or nil
end

-- TrySetDiveWarp: which way this cell goes, and where to.  The tile the
-- player is STANDING on, not the one they face -- the deep water is under
-- the surfboard and the shaft of light is directly overhead.
--   "dive"   -> down to the seafloor map
--   "emerge" -> back up to the route
--   nil      -> this cell does neither
-- IS THIS WATER DEEP ENOUGH TO GO DOWN THROUGH?
--
-- Three behaviours are, not one.  The import derives the family from the
-- cartridge's own reciprocal script warps (see diveWarpScripts): $11, $12 and
-- $14, which is MB_INTERIOR_DEEP_WATER, MB_DEEP_WATER and
-- MB_SOOTOPOLIS_DEEP_WATER.  An older cache carries only the single
-- `behaviour`, and that still answers.
local function gen3Diveable(rule, behaviour)
  if behaviour == nil then return false end
  local list = rule.behaviours
  if type(list) == "table" then
    for _, b in ipairs(list) do
      if b == behaviour then return true end
    end
    return false
  end
  return behaviour == rule.behaviour
end

function OverworldState:gen3DiveHere()
  if not GameVersion.isGen3() then return nil end
  local rule = Game.data.constants and Game.data.constants.gen3Dive
  local def = self.map and self.map.def
  local p = self.player
  if not (rule and def and p) then return nil end
  local behaviour = self.map.cellBehaviour
                    and self.map:cellBehaviour(p.cellX, p.cellY)
  local connections = def.connections or {}

  -- THE OTHER HALF OF THE CARTRIDGE'S DIVE.
  --
  -- Reported from play, with a picture: "this is the bottom area of
  -- sootopolis supposed to be divable but isnt".  Emerald says where a dive
  -- goes in two ways and this port read one -- the map header's connection.
  -- The other is a SCRIPT: `setdivewarp` sets gFixedDiveWarp and SetDiveWarp
  -- falls back to it when the header names nothing.  Fourteen places work
  -- that way, and every one was silent: Sootopolis down to the water beneath
  -- it, Route 134 down to the Sealed Chamber's approach, the Marine Cave, the
  -- Seafloor Cavern and four flooded rooms of the Abandoned Ship.
  --
  -- A script warp names an exact CELL as well as a map, which a connection
  -- does not -- a connection keeps you at the same coordinates.
  local scripted = def.diveWarp

  if def.mapType == "UNDERWATER" then
    local up = connections.emerge and connections.emerge.map
    local ux, uy
    if not up and scripted then up, ux, uy = scripted.map, scripted.x, scripted.y end
    if not up then return nil end
    for _, sealed in ipairs(rule.noSurfacing or {}) do
      if behaviour == sealed then return nil end
    end
    return "emerge", up, ux, uy
  end

  local down = connections.dive and connections.dive.map
  local dx, dy
  if not down and scripted then down, dx, dy = scripted.map, scripted.x, scripted.y end
  if not down then return nil end
  if not gen3Diveable(rule, behaviour) then return nil end
  -- deep water is water: you are out there on a Pokemon, not standing on it
  if not p.surfing then return nil end
  return "dive", down, dx, dy
end

-- The A-press.  Refuses out loud when the cell is right and the player is
-- not -- "The sea is deep here.  A POKeMON may be able to go underwater." --
-- which is what the cartridge does, and says nothing at all where the cell
-- is wrong so the press falls through to the rest of interact().
-- WHY A DIVE WAS DECLINED, for the log.
--
-- Reported from play as "dive doesn't work on dive overworld tiles when I hit
-- A", and the four ways gen3DiveHere can answer nothing are indistinguishable
-- on screen: all four are silence, which is right on the cartridge too --
-- deep water you cannot dive from says nothing.  So the engine says which one
-- it was, once per cell, rather than leaving the next report to guess.
function OverworldState:gen3DiveWhyNot()
  local rule = Game.data.constants and Game.data.constants.gen3Dive
  if not rule then return "this dataset has no dive rule -- re-import" end
  local def = self.map and self.map.def
  local p = self.player
  if not (def and p) then return "no map" end
  local behaviour = self.map.cellBehaviour
                    and self.map:cellBehaviour(p.cellX, p.cellY)
  if not gen3Diveable(rule, behaviour) then
    return ("this cell is behaviour %s, and a dive wants one of %s")
           :format(tostring(behaviour),
                   table.concat(rule.behaviours or { rule.behaviour }, "/"))
  end
  local connections = def.connections or {}
  if not ((connections.dive and connections.dive.map) or def.diveWarp) then
    return "the water is deep but this map names nowhere to dive to"
  end
  if not p.surfing then return "you are not on the water" end
  return "the cell reads as diveable -- this should have asked"
end

function OverworldState:tryDiveOW()
  local which, to = self:gen3DiveHere()
  if not which then
    -- only worth a line where the water is deep: everywhere else the silence
    -- is the right answer and always was
    local behaviour = self.map and self.map.cellBehaviour
                      and self.map:cellBehaviour(self.player.cellX,
                                                 self.player.cellY)
    local rule = Game.data.constants and Game.data.constants.gen3Dive
    if rule and gen3Diveable(rule, behaviour) then
      local key = ("%s:%d,%d"):format(tostring(self.map and self.map.id),
                                      self.player.cellX, self.player.cellY)
      self.diveSaidWhy = self.diveSaidWhy or {}
      if not self.diveSaidWhy[key] then
        self.diveSaidWhy[key] = true
        Logger.info("gen3 dive: %s -- %s", key, self:gen3DiveWhyNot())
      end
    end
    return false
  end
  local down = (which == "dive")
  if not (self:partyKnows("DIVE") and self:gen3HasBadge("DIVE")) then
    local refusal = self:gen3FieldText("DIVE", down and "cannot" or "cannotUnder")
    Game.stack:push(TextBox.new(Game, refusal
      or Strings("The sea is deep here.\nA POKéMON may be able\nto go underwater.")))
    return true
  end
  local ask = self:gen3FieldText("DIVE", down and "ask" or "askUnder")
  Game.stack:push(TextBox.new(Game,
    ask or Strings("The sea is deep here.\nWould you like to use\nDIVE?"),
    nil, { choice = function(yes)
      if yes then self:gen3UseDive() end
    end }))
  return true
end

-- FldEff_UseDive -> DoDiveWarp: the same cell on the other map, facing the
-- same way.  Surfing is the difference between the two sides -- you ride
-- across the sea and you walk on the seafloor -- and the elevation follows
-- from the cell setMap lands on.
function OverworldState:gen3UseDive(onClose)
  local which, to, atX, atY = self:gen3DiveHere()
  if not which then
    if onClose then onClose() end
    return false
  end
  local mon = self:partyKnows("DIVE")
  local p = self.player
  -- a CONNECTION keeps your coordinates -- a dive goes straight down -- while
  -- a script warp names the cell to land on
  local x, y, facing = atX or p.cellX, atY or p.cellY, p.facing
  local name = mon and (mon.nickname
    or (Game.data.pokemon[mon.species] and Game.data.pokemon[mon.species].name))
    or (mon and mon.species) or Strings("POKéMON")
  local line = self:gen3FieldText("DIVE", "used")
  local text = line and line:gsub("{VAR1}", (name:gsub("%%", "%%%%")))
               or Strings("%s used DIVE.", name)
  Game.stack:push(TextBox.new(Game, text, function()
    if onClose then onClose() end
    p.surfing = (which == "emerge")
    p.diving = (which == "dive") or nil
    self:startWarpTo(to, x, y, facing)
  end))
  return true
end


-- ---------------------------------------------------------------------------
-- WATERFALL
--
-- GetInteractedWaterScript: face a waterfall and press A, and Emerald either
-- runs EventScript_UseWaterfall or EventScript_CannotUseWaterfall -- "A wall
-- of water is crashing down with a mighty roar."  Both scripts are in the
-- cartridge and both are unreachable from any map, so the import finds them
-- by their shape (see fieldMoveMessages) and the lines below are the
-- cartridge's own.
--
-- Which cells are a waterfall is not written down either: the import finds
-- the one behaviour whose every cell joins one body of water to another
-- vertically (see waterfallTerrain).  Nothing about those cells is blocked
-- -- the falls are passable water at the water's level -- so this A-press IS
-- the mechanism, not a shortcut past one.
--
-- The cartridge's script checks the BADGE and the direction and not the
-- party; the port asks for a Pokemon that knows the move as well, because
-- the alternative is a prompt that says yes and then does nothing.
-- ---------------------------------------------------------------------------

function OverworldState:gen3WaterfallAhead()
  if not GameVersion.isGen3() then return nil end
  local rule = Game.data.constants and Game.data.constants.gen3Waterfall
  if not (rule and rule.behaviour and self.map and self.map.cellBehaviour) then
    return nil
  end
  local fx, fy = self.player:facingCell()
  if self.map:cellBehaviour(fx, fy) ~= rule.behaviour then return nil end
  return fx, fy, rule.behaviour
end

function OverworldState:tryWaterfallOW()
  local fx, fy, behaviour = self:gen3WaterfallAhead()
  if not fx then return false end
  -- IsPlayerSurfingNorth: you climb a waterfall from the water below it,
  -- facing up.  Anything else -- standing on the bank, facing along it --
  -- gets the wall of water instead.
  local p = self.player
  local ready = p.surfing and p.facing == "up" and self:partyKnows("WATERFALL")
  if not ready then
    Game.stack:push(TextBox.new(Game,
      self:gen3FieldText("WATERFALL", "cannot")
        or Strings("A wall of water is\ncrashing down with a\nmighty roar.")))
    return true
  end
  Game.stack:push(TextBox.new(Game,
    self:gen3FieldText("WATERFALL", "ask")
      or Strings("It's a large waterfall.\nWould you like to use\nWATERFALL?"),
    nil, { choice = function(yes)
      if yes then self:gen3UseWaterfall(fx, fy, behaviour) end
    end }))
  return true
end

-- FLDEFF_USE_WATERFALL: the player rides up the column and comes off it on
-- the water above.  The ROM re-tests the cell above on every step, which is
-- the same thing as walking the run to its top here.
function OverworldState:gen3UseWaterfall(fx, fy, behaviour)
  local mon = self:partyKnows("WATERFALL")
  local p = self.player
  local name = mon and (mon.nickname
    or (Game.data.pokemon[mon.species] and Game.data.pokemon[mon.species].name))
    or (mon and mon.species) or Strings("POKéMON")
  local line = self:gen3FieldText("WATERFALL", "used")
  local text = line and line:gsub("{VAR1}", (name:gsub("%%", "%%%%")))
               or Strings("%s used WATERFALL.", name)
  local top = fy
  while self.map:cellBehaviour(fx, top - 1) == behaviour do top = top - 1 end
  -- one more, onto the water at the head of the falls -- unless there is
  -- nothing there to come off onto, in which case stop on the fall itself
  local landing = top - 1
  if not (self.map:inBounds(fx, landing)
          and self.map:isWalkableCell(fx, landing)) then
    landing = top
  end
  local climb = p.cellY - landing
  Game.stack:push(TextBox.new(Game, text, function()
    if climb > 0 then self:scriptMove(p, "up", climb) end
  end))
end

-- Party-menu CUT entry (start_sub_menus.asm .cut -> predef UsedCut,
-- engine/overworld/cut.asm): badge-check CASCADEBADGE then check the tile
-- the player is FACING against the tileset's cut-tree ids; _NothingToCutText
-- (and .loop back to the submenu) if it isn't cuttable.  Side-effect-free
-- check mirroring useSurfFieldMove; tryCut does the actual cut on "ok".
-- Returns:
--   "no_badge" -> CASCADEBADGE missing / no CUT mon (_NewBadgeRequiredText)
--   "nothing"  -> not facing a cuttable tree (_NothingToCutText)
--   "ok"       -> facing a cuttable tree; caller may call tryCut(fx, fy)
function OverworldState:useCutFieldMove()
  if not self:partyKnows("CUT") then return "no_badge" end
  local fx, fy = self.player:facingCell()
  if GameVersion.isGen2() then
    return self:gen2CutSwap(fx, fy) and "ok" or "nothing"
  end
  if not self.map:inBounds(fx, fy) then return "nothing" end
  -- same tileset/tile gate as tryCut (UsedCut, engine/overworld/cut.asm):
  -- a tree BLOCK also contains fence/path cells, and facing those is
  -- "nothing to cut" in vanilla
  local ts = self.map.def.tileset
  local tile = self.map:cellTile(fx, fy)
  local isGrass = (ts == "OVERWORLD" and tile == 0x52)
  if not ((ts == "OVERWORLD" and tile == 0x3d)
          or (ts == "GYM" and tile == 0x50)
          or isGrass) then
    return "nothing"
  end
  local bx, by = math.floor(fx / 2), math.floor(fy / 2)
  local block = self.map:blockAt(bx, by)
  local swap
  for _, sw in ipairs(Game.data.field.cutTreeSwaps or {}) do
    if sw.before == block then swap = sw break end
  end
  if not swap or (not isGrass and self.map:isWalkableCell(fx, fy)) then return "nothing" end
  return "ok"
end

function OverworldState:talkTo(npc)
  npc.frozen = true
  local unfreeze = function() npc.frozen = false end
  local d = npc.def

  -- hand-ported scripts always win -- except an undefeated ROM trainer,
  -- whose script body is the AFTER-battle talk the original only reaches
  -- once the trainer header has shown its seen text and run the battle.
  local pendingTrainer = d.trainerClass and not self:trainerDefeated(npc)
  if not pendingTrainer and mapScripts.talkScript(self.map.id, d.text) then
    self:showMapText(d.text, npc, unfreeze)
    return
  end

  -- Rock Smash needs no special case here any more: the rock's own script
  -- IS AskRockSmashScript (StdScripts entry 15), and now that `callasm`
  -- lowers HasRockSmash the extracted script runs the party check, the
  -- prompt, the shake and `disappear LAST_TALKED` by itself.

  -- A berry/apricorn tree carries an item but is not an item ball: picking it
  -- leaves the tree standing and re-fruits on the daily reset, so it runs
  -- FruitTreeScript rather than the vanish-and-take path below.
  if d.fruitTree then
    npc:facePlayer(self.player)
    self.runner:run({ { "g2_fruittree", d.fruitTree } },
                    { npc = npc, onDone = unfreeze })
    return
  end

  -- item balls (object_event item argument).  A payload id of "0" is
  -- pokered's ITEM_NONE sentinel: the ROM object sets the 0x80 "has item"
  -- bit but names item 0, so it is a plain text object, not an item ball
  -- (e.g. Blue's House wall Town Map / walking Daisy, #11).  Lua treats
  -- the string "0" as truthy, so screen it out and fall through to text.
  if d.item and d.item ~= "0" and d.item ~= 0 then
    if not require("src.inventory.Bag").add(Game.save, d.item, 1, Game.data) then
      Game.stack:push(TextBox.new(Game, Strings("You can't carry\nany more items!")))
      return
    end
    Game.save.itemsTaken = Game.save.itemsTaken or {}
    Game.save.itemsTaken[npc.id] = true
    for i, n in ipairs(self.npcs) do
      if n == npc then table.remove(self.npcs, i) break end
    end
    for i, e in ipairs(self.entities) do
      if e == npc then table.remove(self.entities, i) break end
    end
    local name = Game.data.items[d.item] and Game.data.items[d.item].name or d.item
    local ddef = Game.data.items[d.item]
    require("src.core.Sound").play(Game.data,
      (ddef and ddef.keyItem) and "Get_Key_Item" or "Get_Item1")
    Game.stack:push(TextBox.new(Game,
      Strings("%s found\n%s!", Game.save.player.name, name)))
    return
  end

  -- static wild encounters (object_event species+level args: the
  -- legendary birds, Mewtwo, the Vermilion Machop, ...)
  if d.pokemon then
    npc:facePlayer(self.player)
    -- WHAT IT SAYS BEFORE THE BATTLE, INCLUDING A LINE SOMEBODY TYPED.
    --
    -- `resolveText` answers for a text CONSTANT -- the extractor's
    -- `_TinTowerHoOhText` and the like -- and the map editor writes prose into
    -- the same field, because asking an author to mint a constant for one line
    -- would be absurd. So an editor-made wild encounter resolved to nothing
    -- and roared `Gyaoo!` over whatever it had been given: the author's line
    -- was not missing from the box, it was replaced in it.
    --
    -- Same discriminator and same laid-out prose as the ordinary talk path
    -- (`showMapText`): anything shaped like a key stays a key and still falls
    -- back to the roar, so a genuine porting gap is not papered over.
    local text = select(1, Game.data:resolveText(self.map.def.label, d.text))
    if not text and type(d.text) == "string" and d.text ~= ""
       and not OverworldState.looksLikeTextId(d.text) then
      text = TextBox.fromProse(d.text)
    end
    text = text or Strings("Gyaoo!")
    local BattleState = require("src.battle.BattleState")
    Game.stack:push(TextBox.new(Game, text, function()
      local battle = BattleState.newWild(Game, d.pokemon, d.level)
      battle.onFinish = function(result)
        if result ~= "lose" and result ~= "run" then
          Game.save.defeatedTrainers[npc.id] = true
          for i, n in ipairs(self.npcs) do
            if n == npc then table.remove(self.npcs, i) break end
          end
          for i, e in ipairs(self.entities) do
            if e == npc then table.remove(self.entities, i) break end
          end
        end
        self:afterBattle(result, battle)
        unfreeze()
      end
      self:pushBattle(battle)
    end))
    return
  end

  -- generic trainers (object_event trainer args + extracted headers)
  if d.trainerClass and not self:trainerDefeated(npc) then
    npc:facePlayer(self.player)
    self:engageTrainer(npc, unfreeze)
    return
  end
  if d.trainerClass and self:trainerDefeated(npc) then
    local header = Game.data:trainerHeader(self.map.def.label, d.index)
    local after = header and header.after and Game.data.text[header.after]
    if after then
      npc:facePlayer(self.player)
      Game.stack:push(TextBox.new(Game, after, unfreeze))
      return
    end
  end

  -- marts / nurses / PCs via TX_SCRIPT markers
  local entry = Game.data:textEntry(self.map.def.label, d.text)
  if entry then
    if entry.mart then
      npc:facePlayer(self.player)
      Game.stack:push(TextBox.new(Game, Strings("Hi there!\nMay I help you?"), function()
        Screens.push(Game, "ShopMenu", entry.mart)
        unfreeze()
      end))
      return
    end
    if entry.nurse then
      npc:facePlayer(self.player)
      self:nurseHeal(unfreeze, npc)
      return
    end
    if entry.pc then
      self:openPC(unfreeze)
      return
    end
    if entry.cableClub then
      npc:facePlayer(self.player)
      self:cableClubReceptionist(unfreeze)
      return
    end
  end

  self:showMapText(d.text, npc, unfreeze)
end

local function sameItems(_, items) return items end

-- The Pokémon Center PC: BILL's PC (boxes), the player's item storage,
-- and PROF.OAK's dex rating (engine/menus/players_pc.asm,
-- engine/events/pokedex_rating.asm).  The assembled entries run through
-- the ui.pc.items hook; LOG OFF is appended after it so a mod cannot
-- orphan the exit.
function OverworldState:openPC(onDone)
  require("src.core.Sound").play(Game.data, "Turn_On_PC")
  local Menu = require("src.ui.Menu")
  local done = onDone or function() end
  local flags = Game.save.flags or {}
  local items = {}

  -- the box PC reads "SOMEONE'S PC" until you meet Bill, then "BILL'S PC"
  -- (engine/menus/pokemon_pc.asm gates on EVENT_MET_BILL; we reach that
  -- when Bill hands over the SS Ticket)
  local metBill = flags.EVENT_MET_BILL or flags.EVENT_GOT_SS_TICKET
  table.insert(items, {
    label = metBill and "BILL'S PC" or Strings("SOMEONE'S PC"),
    onSelect = function()
      require("src.core.Sound").play(Game.data, "Enter_PC")
      -- HOENN ASKS FIRST.  Emerald's storage opens on a menu -- WITHDRAW
      -- POKeMON / DEPOSIT POKeMON / MOVE POKeMON / MOVE ITEMS / SEE YA! --
      -- and the grid is what one of those rows opens.  Reported from play as
      -- "for the storage missing deposit, withdrawal, and move pokemon
      -- options": they were missing because this went straight to the grid,
      -- which left DEPOSIT on SELECT and MOVE nowhere at all.
      if GameVersion.isGen3() then
        Screens.push(Game, "StorageMenu")
      else
        Screens.push(Game, "BoxMenu")
      end
      done()
    end,
  })

  -- the player's item storage is always available
  table.insert(items, {
    label = (Game.save.player.name or "RED") .. "'s PC",
    onSelect = function()
      Screens.push(Game, "PlayerPC")
      done()
    end,
  })

  -- Prof. Oak's dex rating only appears once you have the Pokédex
  if flags.EVENT_GOT_POKEDEX then
    table.insert(items, {
      label = Strings("PROF.OAK's PC"),
      onSelect = function()
        self:openOaksPC(done)
      end,
    })
  end

  local hooked = Runtime.call("ui.pc.items", sameItems, Game, items)
  if type(hooked) == "table" then
    items = hooked
  else
    Logger.error("ui.pc.items returned %s; keeping the vanilla items",
                 type(hooked))
  end

  local logOff = function()
    require("src.core.Sound").play(Game.data, "Turn_Off_PC")
    done()
  end
  table.insert(items, { label = Strings("LOG OFF"), onSelect = logOff })
  -- pokered sets BIT_NO_MENU_BUTTON_SOUND for the whole PC session
  -- (engine/overworld/pokecenter_pc.asm / player_pc.asm); DisplayPCMainMenu
  -- calls TextBoxBorder with c=14 (interior width, +2 for the border), so
  -- tw here (total width) is 16
  Game.stack:push(Menu.new(Game, items,
    { tx = 0, ty = 0, tw = 16, th = #items * 2 + 2, onCancel = logOff,
      noSound = true }))
end

-- The PROF. OAK's PC session (engine/menus/oaks_pc.asm OpenOaksPC): the
-- access text, "Want to get your #DEX rated?" with a YES/NO, then the
-- rating, and "Closed link to PROF.OAK's PC." before control returns -- the
-- intro and closing links the launcher skipped, jingle ordering aside (#576).
function OverworldState:openOaksPC(onDone)
  local done = onDone or function() end
  local text = Game.data.text or {}
  local accessed = text._AccessedOaksPCText
    or Strings("Accessed PROF.\nOAK's PC.\fAccessed POKéDEX\nRating System.")
  local rated = text._GetDexRatedText
    or Strings("Want to get your\nPOKéDEX rated?")
  local closed = text._ClosedOaksPCText
    or Strings("Closed link to\nPROF.OAK's PC.")
  local function close()
    Game.stack:push(TextBox.new(Game, closed, done))
  end
  Game.stack:push(TextBox.new(Game, accessed, function()
    -- _GetDexRatedText ends with `done`, so the YES/NO pops as soon as the
    -- text has typed out, with no button wait in between (YesNoChoice)
    Game.stack:push(TextBox.new(Game, rated, nil, {
      choice = function(yes)
        if not yes then
          close()
          return
        end
        self:dexRating(close)
      end,
    }))
  end))
end

-- Prof. Oak's dex rating service (engine/events/pokedex_rating.asm):
-- the completion line with seen AND owned counts, then the per-decade
-- rating text.
function OverworldState:dexRating(onDone)
  local seen, owned = 0, 0
  for _ in pairs(Game.save.pokedex.seen or {}) do seen = seen + 1 end
  for _ in pairs(Game.save.pokedex.owned or {}) do owned = owned + 1 end
  local key
  if owned >= 150 then
    key = "_DexRatingText_Own150To151"
  else
    local lo = math.floor(owned / 10) * 10
    key = ("_DexRatingText_Own%dTo%d"):format(lo, lo + 9)
  end
  local rating = Game.data.text[key] or Strings("Keep it up!")
  local completion = Game.data.text._DexCompletionText
    or Strings("POKéDEX comp-\nletion is:\f{NUM:hDexRatingNumMonsSeen} POKéMON seen\n{NUM:hDexRatingNumMonsOwned} POKéMON owned\fPROF.OAK's\nRating:")
  completion = completion
    :gsub("{NUM:hDexRatingNumMonsSeen[^}]*}", tostring(seen))
    :gsub("{NUM:hDexRatingNumMonsOwned[^}]*}", tostring(owned))
  -- DisplayDexRating prints the completion line, then the tier text, and
  -- only then plays the rating jingle and waits for a button -- the fanfare
  -- must not pre-empt the evaluation it celebrates (#576).  auto.wait hands
  -- the box to the plain A/B path once the jingle has sounded.
  Game.stack:push(TextBox.new(Game, completion .. "\f" .. rating, onDone, {
    auto = { wait = true, sound = function()
      return require("src.core.Sound").play(Game.data, "Pokedex_Rating")
    end },
  }))
end

-- AnimateHealingMachine (engine/overworld/healing_machine.asm): balls
-- every 30 frames, then jingle + FlashSprite8Times (8 x 10).  #157: skip
-- pokered's post-flash .waitLoop2 / DelayFrames 32 so fighting-fit is
-- immediate; jingle still plays and restoreMap runs when it ends.
function OverworldState.stepHealAnim(ha)
  ha.timer = ha.timer + 1
  ha.phase = ha.phase or "balls"
  if ha.phase == "balls" then
    -- .partyLoop: a ball lights with the machine sfx, then 30 frames
    if ha.lit == 0 or ha.timer >= 30 then
      ha.timer = 0
      if ha.lit < ha.balls then
        ha.lit = ha.lit + 1
        return "ball"
      end
      ha.phase = "flash"
      ha.flashes = 0
      return "jingle"
    end
  elseif ha.phase == "flash" then
    -- FlashSprite8Times: xor the OBJ palette every 10 frames, 8 times
    if ha.timer >= 10 then
      ha.timer = 0
      ha.visible = not ha.visible
      ha.flashes = ha.flashes + 1
      if ha.flashes >= 8 then
        ha.visible = true
        ha.phase = "done"
        return "done"
      end
    end
  end
end

-- THE HEALING MACHINE, started by whoever is asking for it.
--
-- Two callers now.  The Game Boy centres reach it through nurseHeal, which is
-- this engine's hand-ported pokecenter.asm; Hoenn's reach it through the
-- cartridge's own script, which runs `dofieldeffect` and then waits -- and
-- until that command did anything, the Emerald counter healed the party in
-- silence with nothing on screen (see Gen3Commands' field-effect handler).
function OverworldState:startHealAnim(onDone)
  self.healAnim = { balls = #(Game.save.party or {}), lit = 0, timer = 0,
                    visible = true,
                    -- map anchor: the player's cell when healing began (the
                    -- GB's fixed screen coords assume it BG-aligned at
                    -- (64,64))
                    px = self.player.cellX * 16,
                    py = self.player.cellY * 16,
                    onDone = onDone }
  return self.healAnim
end

-- Nurse dialogue uses the real engine strings (data/text/text_4.asm via
-- engine/events/pokecenter.asm): welcome (plus "Shall we heal" the first
-- time), a YES/NO, then the machine animation between "we need your
-- POKéMON" and "fighting fit".
function OverworldState:nurseHeal(onDone, npc)
  local t = Game.data.text
  local bye = t._PokemonCenterFarewellText or Strings("We hope to see\nyou again!")
  local hello = t._PokemonCenterWelcomeText
                or Strings("Welcome to our\nPOKéMON CENTER!")
  if not Game.save.usedPokecenter then
    Game.save.usedPokecenter = true -- BIT_USED_POKECENTER
    hello = hello .. "\f"
            .. (t._ShallWeHealYourPokemonText or Strings("Shall we heal your\nPOKéMON?"))
  end
  -- Yellow's companion has its own beat threaded through this sequence
  local Follower = require("src.world.PikachuFollower")
  Game.stack:push(TextBox.new(Game, hello, nil, { choice = function(yes)
    if not yes then
      Game.stack:push(TextBox.new(Game, bye, onDone))
      return
    end
    local need = t._NeedYourPokemonText or Strings("OK. We'll need\nyour POKéMON.")
    -- accepting the heal sends the companion up onto the counter to Nurse
    -- Joy first: pokecenter.asm runs `callfar PikachuWalksToNurseJoy`
    -- between SetLastBlackoutMap and NeedYourPokemonText, and the hop has
    -- to finish before the text box goes up because only the top state
    -- updates.  No follower (or not Yellow) calls straight through (#417).
    Follower.hopToCounter(self, function()
      Game.stack:push(TextBox.new(Game, need, function()
        -- the nurse turns to the machine, the map music stops, and the
        -- party heals before the machine runs (predef HealParty)
        if npc then npc.facing = "left" end
        -- DisablePikachuOverworldSpriteDrawing: Pikachu goes behind the
        -- counter with the party for the machine animation
        Follower.setVisible(self, false)
        require("src.core.Music").stop()
        local Pokemon = require("src.pokemon.Pokemon")
        for _, mon in ipairs(Game.save.party) do
          Pokemon.heal(mon)
        end
        Game.save.lastHeal = { -- SetLastBlackoutMap
          map = self.map.id, x = self.player.cellX, y = self.player.cellY,
          -- the town door of this interior, for LAST_MAP exits after a
          -- blackout/ESCAPE ROPE warp here
          outdoor = self.lastOutdoor
            and { id = self.lastOutdoor.id, x = self.lastOutdoor.x, y = self.lastOutdoor.y }
            or nil,
        }
        self:startHealAnim()
        self.healAnim.onDone = function()
          -- EnablePikachuOverworldSpriteDrawing, before the fighting-fit
          -- line: it comes back on the counter facing the player
          Follower.setVisible(self, true)
          if npc then npc:facePlayer(self.player) end
          self:finishNurseHeal(bye, onDone)
        end
      end))
    end)
  end }))
end

function OverworldState:finishNurseHeal(bye, onDone)
  local t = Game.data.text
  local fit = t._PokemonFightingFitText or Strings("Your POKéMON are\nfighting fit!")
  Game.stack:push(TextBox.new(Game, fit .. "\f" .. bye, onDone))
end

-- The Cable Club link receptionist (TX_SCRIPT_CABLE_CLUB_RECEPTIONIST ->
-- CableClubNPC, engine/link/cable_club_npc.asm): the welcome line, then
-- without the POKéDEX she's still "making preparations"; with it she asks
-- to apply (YES/NO), saves the game (SaveGameData + SFX_SAVE) and opens
-- the link.  The port's enet link menu (src/link/LinkState.lua) stands in
-- for the original serial handshake; declining prints "Please come again!"
function OverworldState:cableClubReceptionist(onDone)
  local t = Game.data.text
  local welcome = t._CableClubNPCWelcomeText or Strings("Welcome to the\nCable Club!")
  if not Game.save.flags.EVENT_GOT_POKEDEX then
    -- CableClubNPC .didNotConnect path before the pokedex
    Game.stack:push(TextBox.new(Game, welcome .. "\f"
      .. (t._CableClubNPCMakingPreparationsText
          or Strings("We're making\npreparations.\vPlease wait.")), onDone))
    return
  end
  local apply = t._CableClubNPCPleaseApplyHereHaveToSaveText
    or Strings("Please apply here.\fBefore opening\nthe link, we have\vto save the game.")
  Game.stack:push(TextBox.new(Game, welcome .. "\f" .. apply, nil,
    { choice = function(yes)
      if not yes then
        Game.stack:push(TextBox.new(Game,
          t._CableClubNPCPleaseComeAgainText or Strings("Please come\nagain!"), onDone))
        return
      end
      Game:writeSave()
      require("src.core.Sound").play(Game.data, "Save")
      local ok, LinkState = pcall(require, "src.link.LinkState")
      if ok and LinkState then
        Game.stack:push(LinkState.new(Game))
      end
      if onDone then onDone() end
    end }))
end

-- -------------------------------------------------------------------------
-- trainers
-- -------------------------------------------------------------------------

function OverworldState:trainerDefeated(npc)
  if Game.save.defeatedTrainers[npc.id] then return true end
  -- A GEN 3 TRAINER IS BEATEN WHEN THEIR OWN FLAG IS SET.
  --
  -- There is no trainer header on this cartridge: the object says it is a
  -- trainer and how far it can see, and WHO it is comes out of the
  -- trainerbattle in its own script.  The flag that battle sets is the whole
  -- record of the fight, so it is also the whole test -- and without it every
  -- trainer in Hoenn would challenge again on sight, forever.
  local trainerId = npc.def and npc.def.gen3TrainerId
  if trainerId then
    local flag = require("src.script.Gen3Commands")
                   .trainerFlag(trainerId, Game.data)
    if flag and Game.save.flags and Game.save.flags[flag] then return true end
    return false
  end
  local header = Game.data:trainerHeader(self.map.def.label, npc.def.index)
  if header and header.event and Game.save.flags[header.event] then
    return true
  end
  return false
end

-- Run the pre-battle text -> battle -> won text -> flags sequence.
function OverworldState:engageTrainer(npc, onDone)
  local d = npc.def
  Runtime.emit("world.trainer_engaged", { npc = npc, trainerClass = d.trainerClass,
                                          partyIndex = d.trainerParty })
  local header = Game.data:trainerHeader(self.map.def.label, d.index)
  local battleText = header and header.battle and Game.data.text[header.battle]
  if not battleText then
    battleText = select(1, Game.data:resolveText(self.map.def.label, d.text))
                 or Strings("I like shorts!\nThey're comfy and\neasy to wear!")
  end
  local wonText = header and header.won and Game.data.text[header.won]

  local BattleState = require("src.battle.BattleState")
  Game.stack:push(TextBox.new(Game, battleText, function()
    -- A TEAM THE AUTHOR BUILT WINS OVER AN INDEX INTO SOMEBODY ELSE'S.
    --
    -- `trainerParty` selects one of the parties the cartridge shipped for
    -- `trainerClass`, which is right for a ported trainer and useless for an
    -- NPC the editor invented -- there is no party for them, so they borrowed
    -- one. `trainerTeam` is the party the author actually typed; when it is
    -- there it is what they meant.
    local battle
    if type(d.trainerTeam) == "table" and #d.trainerTeam > 0 then
      battle = BattleState.newEditorTrainer(Game, d.trainerTeam,
                                            d.trainerClass, d.trainerName)
    end
    battle = battle or BattleState.newTrainer(Game, d.trainerClass,
                                              d.trainerParty)
    -- PrintEndBattleText (home/trainers.asm:341) is called from
    -- TrainerBattleVictory (engine/battle/core.asm:942), i.e. ON the battle
    -- screen once ScrollTrainerPicAfterBattle has brought the beaten trainer
    -- back, and before MoneyForWinningText -- not in the overworld after the
    -- battle screen has torn down.  Handing the line to the battle also
    -- stops a post-battle evolution being sandwiched between two overworld
    -- cuts (#282).  Substituted here because BattleState:say takes finished
    -- text, while TextBox expanded the {PLAYER}/{RIVAL} tokens itself.
    battle.endBattleText = wonText and TextBox.substitute(Game, wonText) or nil
    battle.onFinish = function(result)
      if result == "win" then
        Game.save.defeatedTrainers[npc.id] = true
        if header and header.event then
          Game.save.flags[header.event] = true
        end
        -- checkVictoryRewards pushes the badge/prize box and starts the map's
        -- onVictory script UNDER whatever runs next, so the player still sees
        -- EndBattle (now inside the battle), then the reward, then AfterBattle
        self:checkVictoryRewards(d.trainerClass, d.trainerParty)
        self:afterBattle(result, battle)
        self:runGen2AfterBattle(d.index)
        if onDone then onDone() end
      else
        self:afterBattle(result, battle)
        if onDone then onDone() end
      end
    end
    self:pushBattle(battle)
  end))
end

-- Run the trainer object's own script once its battle is won, the way
-- LoadTrainer/reloadmapafterbattle re-enters it in GSC.  Scripts that only
-- hold an after-battle line open with `endifjustbattled` and stop here; the
-- ones that drive a cutscene (Slowpoke Well, the Rocket hideout) carry on.
function OverworldState:runGen2AfterBattle(objIndex)
  if not (GameVersion.isGen2() and objIndex and self.map) then return end
  local rows = require("src.script.Gen2ScriptVM")
    .afterBattleRows(Game.data, self.map.id, objIndex)
  if rows then
    self:queueScript(rows, { mapId = self.map.id, justBattled = true })
  end
end

-- Badges/items awarded after specific battles (data/scripts/victories.lua).
-- `deactivate` retires unfought gym/dojo trainers the way the originals'
-- SetEvent / SetEventRange do after the leader victory.
-- `hide` is { { mapId, objName }, ... } -- HideObject on those toggles
-- (e.g. Brock victory clears PEWTERCITY_YOUNGSTER / ROUTE22_RIVAL1).
function OverworldState:checkVictoryRewards(trainerClass, partyIndex)
  local victories = require("data.scripts.victories")
  local reward = victories[trainerClass .. "#" .. tostring(partyIndex or 1)]
  if not reward then return self:runVictoryHook() end
  if reward.flag then
    if Game.save.flags[reward.flag] then return self:runVictoryHook() end
    Game.save.flags[reward.flag] = true
  end
  if reward.deactivate then
    for _, flag in ipairs(reward.deactivate) do
      Game.save.flags[flag] = true
    end
  end
  if reward.hide then
    local Commands = require("src.script.Commands")
    local ctx = { game = Game, save = Game.save, overworld = self }
    for _, entry in ipairs(reward.hide) do
      Commands.hide_object(ctx, entry[1], entry[2])
    end
  end
  if reward.badge then
    Game.save.inventory[reward.badge] = 1
  end
  if reward.item then
    local inv = Game.save.inventory
    inv[reward.item] = (inv[reward.item] or 0) + 1
    local idef = Game.data.items[reward.item]
    -- GiveItem -> CopyToStringBuffer for "{RAM:wStringBuffer}" received texts
    Game.stringBuffer = idef and idef.name or reward.item
  end
  local lines = {}
  if reward.dialogue then
    local text = Game.data.text or {}
    for _, label in ipairs(reward.dialogue) do
      if text[label] and text[label] ~= "" then
        table.insert(lines, text[label])
      end
    end
  elseif reward.badge or reward.item then
    if reward.badge then
      local name = Game.data.items[reward.badge] and Game.data.items[reward.badge].name
                   or reward.badge
      table.insert(lines, Strings("%s received\nthe %s!", Game.save.player.name, name))
    end
    if reward.item then
      local name = Game.stringBuffer or reward.item
      table.insert(lines, Strings("%s received\n%s!", Game.save.player.name, name))
    end
  end
  if #lines > 0 then
    Game.stack:push(TextBox.new(Game, table.concat(lines, "\f")))
  end
  self:runVictoryHook()
end

-- pokered reloads the map after every battle, re-running the map
-- script (e.g. LoreleiShowOrHideExitBlock); this hook is the port's
-- equivalent so seals/toggles refresh without leaving the map
function OverworldState:runVictoryHook()
  local hooks = mapScripts.get(self.map.id)
  if hooks and hooks.onVictory then hooks.onVictory(Game, self) end
end

-- pokered player sprite is fixed at screen ($40, $3c).  TrainerEngage reads
-- the NPC's 8-bit SPRITESTATEDATA1 X/Y pixels and CalcDifference; engage
-- distance is stored as range<<4 (pixels).  There is no tile LOS check for
-- interposed NPCs / walls -- but unsigned 8-bit Y makes a sprite exactly 4
-- tiles north of the player sit at Y=$fc, so |$3c-$fc|=$c0 and a range-4
-- DOWN trainer does not engage that tile (Route 9 Bug Catcher / issue #76).
-- Off-screen sprites (IMAGEINDEX=$ff) never engage: without that gate, the
-- same 8-bit wrap makes far same-row trainers look in-range (#153/#183).
local PLAYER_SCREEN_X, PLAYER_SCREEN_Y = 0x40, 0x3c
local function u8(n) return n % 256 end
local function calcDiff(a, b)
  a, b = u8(a), u8(b)
  return a >= b and a - b or b - a
end
local function trainerSightPixelDist(npc, player, horizontal)
  if horizontal then
    return calcDiff(PLAYER_SCREEN_X,
                    u8(PLAYER_SCREEN_X + (npc.cellX - player.cellX) * 16))
  end
  return calcDiff(PLAYER_SCREEN_Y,
                  u8(PLAYER_SCREEN_Y + (npc.cellY - player.cellY) * 16))
end

-- CheckSpriteAvailability (movement.asm): wXCoord/wYCoord = player - 4;
-- visible when sprite is in [wCoord, wCoord + SCREEN_*/2 - 1] (GB 10x9).
local function trainerSpriteOnScreen(npc, player)
  local dx = npc.cellX - player.cellX
  local dy = npc.cellY - player.cellY
  return dx >= -4 and dx <= 5 and dy >= -4 and dy <= 4
end

-- STAY trainers with a facing spot the player crossing their line of
-- sight (range from the extracted trainer headers), walk up and battle.
-- HOW MANY POKEMON COULD FIGHT A DOUBLE BATTLE.
--
-- GetMonsStateToDoubles (0806B5C4) answers 0 for "two or more that are not
-- eggs and are not fainted", and CheckForTrainersWantingBattle will not
-- collect a SECOND trainer unless it does.  With one usable Pokemon the
-- cartridge takes the first spotter and stops, which is an ordinary single
-- battle -- it does not start a double you cannot field.
local function canFieldTwo(save)
  local usable = 0
  for _, mon in ipairs((save and save.party) or {}) do
    if (mon.hp or 0) > 0 and not mon.isEgg then usable = usable + 1 end
  end
  return usable >= 2
end

function OverworldState:checkTrainerSight()
  if self.player.moving or self.engaging then return end
  if Game.stack:top() ~= self then return end
  local p = self.player
  -- the spotters, in the order the scan finds them -- which is object order,
  -- the order the cartridge walks gObjectEvents in
  local spotted = {}
  local gen3 = require("src.core.GameVersion").isGen3()
  local pairUp = gen3 and canFieldTwo(Game.save)
  for _, npc in ipairs(self.npcs) do
    local stop = false
    local d = npc.def
    -- CheckFightingMapTrainers engages ANY aligned trainer sprite,
    -- walkers included (they sight between steps)
    -- A GEN 3 TRAINER IS ONE THE OBJECT EVENT SAYS IS ONE.
    --
    -- 552 objects in Hoenn carry a trainerType and a sight range and nothing
    -- read either, so not one trainer in the region ever noticed anybody --
    -- every battle in the game had to be started by walking up and pressing
    -- A.  The check below is otherwise unchanged: the sight geometry is the
    -- same, and `sightRange` is the field it already keys on.
    --
    -- The talk-script exclusion is Gen 1/2's -- there, an NPC with authored
    -- dialogue is a talker rather than a fighter.  A Gen 3 trainer's script
    -- IS the battle, so it must not exclude itself.
    local isTrainer = d.gen3Trainer or
      (d.trainerClass and (d.trainerObject
                           or not mapScripts.talkScript(self.map.id, d.text)))
    -- A buried trainer you have already beaten is standing in the open: they
    -- came up the first time and they do not go back under.
    if npc.buried and self:trainerDefeated(npc) then
      npc.buried, npc.hidden = nil, nil
    end
    if isTrainer and not npc.moving
       and not self:trainerDefeated(npc)
       and trainerSpriteOnScreen(npc, p) then
      local header = Game.data:trainerHeader(self.map.def.label, d.index)
      -- THE OBJECT'S OWN RANGE WINS OVER THE HEADER'S.
      --
      -- The cartridge files sight range in a trainer header keyed by (map,
      -- object index), so an NPC the map editor invented has no header and
      -- reads 0 -- "never notices anybody". An authored trainer could only
      -- ever be fought by walking up and talking to them.
      --
      -- `sightRange` is the editor's answer, and ABSENT is not the same as
      -- ZERO: absent means "whatever the cartridge said", zero means "talk to
      -- me", which is a real setting the ROM itself uses for gym trainers and
      -- the Karate Master. Tested with `~= nil` for exactly that reason.
      local range = d.sightRange
      if range == nil then range = header and header.range or 0 end
      -- WHICH WAYS THIS ONE LOOKS.
      --
      -- Emerald has three kinds of trainer and only the first looks one way.
      -- TRAINER_TYPE_SEE_ALL_DIRECTIONS and TRAINER_TYPE_BURIED both check
      -- all four, which is GetTrainerApproachDistance's own split.  Ten
      -- objects in Hoenn are the second kind: the two hiding in the ash on
      -- Route 113, and the eight in Lavaridge Gym -- who stand on the gym's
      -- sand-hole tiles, where the player arrives from whichever side they
      -- fell in from, so a single facing would have been meaningless.
      local ways = { npc.facing }
      if (tonumber(d.gen3TrainerType) or 1) >= 2 then
        ways = { "up", "down", "left", "right" }
      end
      for _, way in ipairs(ways) do
      local vec = DIRVEC[way]
      if range > 0 and vec then
        local dist, horizontal
        if vec[1] ~= 0 and npc.cellY == p.cellY then
          dist = (p.cellX - npc.cellX) * vec[1]
          horizontal = true
        elseif vec[2] ~= 0 and npc.cellX == p.cellX then
          dist = (p.cellY - npc.cellY) * vec[2]
          horizontal = false
        end
        -- Screen-pixel range (CheckSpriteCanSeePlayer), not cell count:
        -- same facing-line rule as before, but the $fc Y quirk excludes the
        -- 4-tiles-north tile that cell math would still count as in range.
        if dist and dist >= 1 then
          local pixelDist = trainerSightPixelDist(npc, p, horizontal)
          if pixelDist > 0 and pixelDist <= range * 16 then
            -- a trainer who looks every way turns to face you first, which
            -- is what the cartridge does before the approach walk
            npc.facing = way
            -- TWO OF THEM CAN SPOT YOU AT ONCE.
            --
            -- CheckForTrainersWantingBattle (0B3BE8) does not stop at the
            -- first: it walks every object and collects up to TWO, and
            -- BattleSetup_StartTrainerBattle (0B17E0) then starts the fight
            -- as DOUBLE|TRAINER|TWO_OPPONENTS rather than plain TRAINER.
            -- Returning here was the whole reason a pair of trainers on the
            -- same route never produced a double battle.
            --
            -- Three things stop the scan, and all three are the
            -- cartridge's:
            --
            --   * CheckTrainer (0B3D6E) answers 2 rather than 1 when the
            --     spotter's own trainerbattle mode is 4, 6 or 7 -- "this
            --     one alone is already a double, do not look for a
            --     partner".  The mode is on the object as gen3TrainerKind.
            --   * two collected is enough (`gNoOfApproachingTrainers > 1`).
            --   * GetMonsStateToDoubles must answer 0 -- two Pokemon on
            --     their feet -- before a SECOND is taken at all.  With one
            --     usable mon the cartridge takes the first spotter and
            --     stops, which is a single battle.
            spotted[#spotted + 1] = { npc = npc, dist = dist }
            stop = true
          end
        end
      end
      if stop then break end
      end
    end
    if stop then
      -- ...AND WHETHER TO KEEP LOOKING.
      --
      -- CheckTrainer (0B3D6E) answers 2 rather than 1 when the spotter's own
      -- trainerbattle mode is 4, 6 or 7 -- "this one alone is already a
      -- double battle, stop".  The mode is on the object as
      -- gen3TrainerKind, which the import writes for exactly this.
      local kind = tonumber(npc.def and npc.def.gen3TrainerKind)
      local DOUBLE = require("src.script.Gen3Commands").DOUBLE_KINDS
      local aloneIsDouble = kind and DOUBLE and DOUBLE[kind]
      if aloneIsDouble or #spotted >= 2 or not pairUp then break end
    end
  end
  if #spotted == 0 then return end
  -- Both walk up; the first one spotted leads, and its script is the one
  -- that runs -- which on the cartridge is the synthesized approach that
  -- sets trainer A and then trainer B.
  if #spotted >= 2 then
    self:startTrainerApproach(spotted[1].npc, spotted[1].dist, spotted[2].npc)
    return
  end
  self:startTrainerApproach(spotted[1].npc, spotted[1].dist)
end

-- data/trainers/encounter_types.asm
local FEMALE_TRAINERS = {
  OPP_LASS = true, OPP_JR_TRAINER_F = true, OPP_BEAUTY = true,
  OPP_COOLTRAINER_F = true,
}
local EVIL_TRAINERS = {
  OPP_UNUSED_JUGGLER = true, OPP_GAMBLER = true, OPP_ROCKER = true,
  OPP_JUGGLER = true, OPP_CHIEF = true, OPP_SCIENTIST = true,
  OPP_GIOVANNI = true, OPP_ROCKET = true,
}

-- The sting this trainer spots you to, when the cartridge says which one.
--
-- gen3TrainerId is the trainer the object's own trainerbattle names; the
-- record's encounterMusic is the index, and gen3EncounterMusic is the switch
-- read out of the ROM.  Anything missing along the way returns nil and the
-- caller falls back on the class name.
function OverworldState:trainerEncounterSong(npc)
  local id = npc and npc.def and npc.def.gen3TrainerId
  if not id then return nil end
  local data = Game.data
  local constants = data and data.constants
  local table_ = constants and constants.gen3EncounterMusic
  local stings = table_ and table_.stings
  if not stings then return nil end
  local key = constants.trainerOrder and constants.trainerOrder[id]
  local trainer = key and data.trainers and data.trainers[key]
  local slot = trainer and tonumber(trainer.encounterMusic)
  local row = slot and stings[slot]
  return row and row.song or nil
end

-- `partner` is the SECOND trainer, when two spotted the player together.
-- Both walk up; the first one's script runs, and the pair is handed to the
-- battle through the runner context the way the cartridge hands
-- gTrainerBattleOpponent_B to BattleSetup_StartTrainerBattle.
function OverworldState:startTrainerApproach(npc, dist, partner)
  self.engaging = true
  npc.frozen = true
  if partner then partner.frozen = true end
  -- ...and if they were buried, this is the moment they come up
  if npc.buried then npc.buried, npc.hidden = nil, nil end
  -- THE STING A TRAINER SPOTS YOU TO.
  --
  -- Gen 1 and Gen 2 have no such field, so the class name is all there is to
  -- go on and the three roles below are the whole vocabulary.  A Gen 3
  -- trainer carries the answer in its own record -- byte 2 of struct Trainer
  -- is an index into PlayTrainerEncounterMusic's fourteen-way switch -- so
  -- when that is on hand it is used instead, and Hoenn gets its swimmer,
  -- twins, hiker and Team Aqua stings rather than three of them for everyone.
  local Music = require("src.core.Music")
  local sting = self:trainerEncounterSong(npc)
  if sting then
    Music.play(Game.data, sting)
  else
    local cls = npc.def.trainerClass
    if type(cls) == "string" and not cls:find("RIVAL") then
      local role = EVIL_TRAINERS[cls] and "meetEvil"
                   or FEMALE_TRAINERS[cls] and "meetFemale" or "meetMale"
      Music.play(Game.data, Music.special(Game.data, role))
    end
  end
  local function fight()
    -- A GEN 3 TRAINER'S SCRIPT IS THE FIGHT.
    --
    -- engageTrainer is the Gen 1/2 sequence -- pre-battle text from a trainer
    -- header, the battle, the won text, the flags -- and none of those parts
    -- exist on this cartridge.  Here the object's own script does all four,
    -- starting with the trainerbattle, so the approach hands over to it.
    if npc.def and npc.def.gen3Trainer then
      local rows = mapScripts.talkScript(self.map.id, npc.def.text)
      if rows then
        -- THE SECOND TRAINER RIDES ON THE CONTEXT.
        --
        -- On the cartridge the pair is not expressed in either trainer's
        -- script: CheckForTrainersWantingBattle writes
        -- gTrainerBattleOpponent_A and _B into RAM and the ordinary
        -- trainerbattle in the FIRST one's script then finds both there.
        -- `gen3PartnerTrainer` is that RAM, and it is why the second
        -- trainer's own script is never run.
        local partnerId = partner and partner.def
                          and partner.def.gen3TrainerId or nil
        self.runner:run(rows, { npc = npc, mapId = self.map.id,
                                gen3PartnerTrainer = partnerId,
                                onDone = function()
                                  npc.frozen = false
                                  if partner then partner.frozen = false end
                                  self.engaging = false
                                end })
        return
      end
      npc.frozen = false
      if partner then partner.frozen = false end
      self.engaging = false
      return
    end
    self:engageTrainer(npc, function()
      npc.frozen = false
      self.engaging = false
    end)
  end
  -- the "!" bubble pause before the walk-up (EmotionBubble holds the
  -- world for 60 frames, engine/overworld/emotion_bubbles.asm)
  self.emote = {
    npc = npc, frames = 60,
    onDone = function()
      if dist > 1 then
        self:scriptMove(npc, npc.facing, dist - 1, fight)
      else
        fight()
      end
    end,
  }
end

-- Does this look like a text CONSTANT rather than a line of dialogue?
--
-- Matched against the two shapes the extractor actually writes, which
-- Commands.show_text's own header names: the map's `TEXT_*` pointers, and
-- labels like `_PalletTownGirlText`. Nothing else is a key.
--
-- WHY THE TEST IS THIS NARROW. The obvious version -- "an identifier, so no
-- spaces" -- calls a one-word line of dialogue a constant, and "Hello" is a
-- perfectly ordinary thing for an author to type. Getting that wrong means
-- silence, which is the failure being fixed here.
--
-- The bias is deliberate: when in doubt, SHOW IT. Prose that was really a
-- missing constant appears on screen as `TEXT_FOO`, which explains itself in
-- one glance; a missing constant treated as prose-that-failed shows nothing at
-- all, and nothing is what took a day to diagnose.
function OverworldState.looksLikeTextId(s)
  if type(s) ~= "string" or s == "" then return false end
  if s:find("%s") then return false end
  return s:find("^TEXT_[%u%d_]+$") ~= nil       -- the map's own pointers
      or s:find("^_%u[%w]*$") ~= nil            -- _PalletTownGirlText
      or s:find("^[%u][%u%d_]*$") ~= nil        -- SCREAMING_CASE
end

-- Dispatch a TEXT_* constant: hand-ported script first, then extracted text.
function OverworldState:showMapText(textConst, npc, onDone)
  local mapLabel = self.map.def.label
  local script = mapScripts.talkScript(self.map.id, textConst)
  if script then
    if npc then npc:facePlayer(self.player) end
    if type(script) == "function" then
      -- Lua talk handlers for logic that doesn't fit command rows
      script(Game, self, npc, onDone or function() end)
      return
    end
    -- the winning contribution's rows run as their owner (09 §4.4): mod:
    -- field routing, strict dispatch and error reports all read the source
    self.runner:run(script, { npc = npc, onDone = onDone,
      source = mapScripts.talkSource(self.map.id, textConst) })
    return
  end
  local text, needsAsm = Game.data:resolveText(mapLabel, textConst)
  if text then
    if needsAsm then
      Logger.warn("%s/%s uses text_asm; showing plain text (port a script in data/scripts/)",
                  mapLabel, textConst)
    end
    if npc then npc:facePlayer(self.player) end
    Game.stack:push(TextBox.new(Game, text, onDone))
  else
    -- PROSE IS ITS OWN TEXT.
    --
    -- `textConst` is normally a CONSTANT NAME -- TEXT_AZALEA_GRAMPS, or an
    -- extracted label like _AzaleaTownGrampsText -- looked up in the map's
    -- text pointers. The map editor writes something else into the same
    -- field: the line the author typed, verbatim, because "plain dialogue"
    -- is the common case and asking an author to mint a constant and add it
    -- to a text table would be absurd.
    --
    -- So an editor-authored NPC failed the lookup, warned, and called
    -- `onDone` -- no box, and no `facePlayer` either, since that only
    -- happened on the two success branches. The report was "he doesn't say
    -- anything and doesn't turn to face me", which is one bug, not two.
    --
    -- `Commands.show_text` HAS ALWAYS DONE THIS -- "literal string fallback
    -- for hand-ported scripts", and Data:textEntry's own comment points at
    -- it -- so a line reached through a script worked while the identical
    -- line on an NPC did not. This is the asymmetry, not a new policy.
    --
    -- THE DISCRIMINATOR IS SHAPE, not a flag, because there is no flag to
    -- read: a text constant is an IDENTIFIER by construction (the extractor
    -- writes them), and prose is not. Anything that could be a key is still
    -- reported as missing, so a genuine porting gap does not quietly print
    -- its own constant on screen -- which is the failure this branch exists
    -- to catch.
    if type(textConst) == "string" and not OverworldState.looksLikeTextId(textConst)
    then
      if npc then npc:facePlayer(self.player) end
      -- LAID OUT LIKE THE CARTRIDGE'S OWN, or it does not wait for the
      -- player. Prose carries no `\n`/`\f`, so `paginate` wrapped it to the
      -- box and put every resulting line on ONE page -- and a page does not
      -- stop, it scrolls. `fromProse` puts the page breaks back.
      Game.stack:push(TextBox.new(Game, TextBox.fromProse(textConst), onDone))
      return
    end
    Logger.warn("no text for %s/%s", mapLabel, textConst)
    if onDone then onDone() end
  end
end

-- -------------------------------------------------------------------------
-- step events
-- Field poison (engine/events/poison.asm ApplyOutOfBattlePoisonDamage):
-- every 4th step, 1 HP per poisoned mon; the BG flickers dark with
-- SFX_POISONED; fainted mons get their message; a whole-party faint
-- blacks out like a lost battle.  Returns true when the step should
-- stop (a text box is up).
function OverworldState:applyFieldPoison()
  local save = Game.save
  local interval = FieldDefaults.world(Game.data, "poisonStepInterval") or 4
  save.poisonSteps = ((save.poisonSteps or 0) + 1) % interval
  if save.poisonSteps ~= 0 then return false end
  local damage = FieldDefaults.world(Game.data, "poisonDamage") or 1
  local anyPoisoned, fainted = false, {}
  for _, mon in ipairs(save.party) do
    if mon.status == "PSN" and mon.hp > 0 then
      anyPoisoned = true
      mon.hp = mon.hp - damage
      if mon.hp <= 0 then
        mon.hp = 0
        mon.status = nil -- the original clears status on the faint
        table.insert(fainted, mon)
        -- callfar_ModifyPikachuHappiness PIKAHAPPY_PSNFNT (poison.asm)
        require("src.world.PikachuFollower")
          .modifyHappiness(save, "PSNFNT", mon)
      end
    end
  end
  if not anyPoisoned then return false end
  require("src.core.Sound").play(Game.data, "Poisoned")
  self.poisonFlash = 12
  local queue = {}
  for _, mon in ipairs(fainted) do
    local name = mon.nickname or Game.data.pokemon[mon.species].name
    table.insert(queue, Strings("%s\nfainted!", name))
  end
  local alive = false
  for _, mon in ipairs(save.party) do
    if mon.hp > 0 then alive = true break end
  end
  local function showNext()
    local msg = table.remove(queue, 1)
    if msg then
      Game.stack:push(TextBox.new(Game, msg, showNext))
      return
    end
    if not alive then
      Game.stack:push(TextBox.new(Game,
        Strings("%s blacked\nout!", save.player.name), function()
        local Pokemon = require("src.pokemon.Pokemon")
        for _, mon in ipairs(save.party) do Pokemon.heal(mon) end
        save.money = math.floor(save.money
          / (FieldDefaults.world(Game.data, "blackoutMoneyDivisor") or 2))
        Runtime.emit("world.blacked_out",
          { save = save, healTarget = self:healPoint() })
        self:warpToHealPoint()
      end))
    end
  end
  if #queue > 0 or not alive then
    showNext()
    return true
  end
  return false
end

-- -------------------------------------------------------------------------

-- the two vanilla links the encounter chains wrap, hoisted so an empty
-- chain allocates no closure
local function rollVanilla(encDef, ctx)
  return Encounter.roll(encDef, ctx.rng, ctx.rateMod, ctx.rateOverride)
end
local function sameEncounter(enc) return enc end

-- The wild pick, wrapped in encounter.roll (returns nil to suppress, a
-- table without calling next to force) and then encounter.species (which
-- transforms a non-nil roll before repel filtering).  With no wrapper on
-- either name this is the bare Encounter.roll, same RNG draws and all.
function OverworldState:rollEncounter(encDef, terrain)
  -- THE LEAD POKEMON'S ABILITY, which is the one thing in Hoenn that changes
  -- how often the grass rustles.  Computed once here rather than inside the
  -- roll so a mod's own encounter.roll sees the same number the vanilla path
  -- would have used.
  local rateMod = Encounter.leadRateMod(Game.data, Game.save,
                                        self:fieldWeather())
  -- ...AND GEN II's CLEANSE TAG, which is the other thing that changes it.
  -- It answers in RATES rather than ratios, so it replaces the table's own
  -- and the ability scales what comes out.
  local rateOverride
  local grass = encDef and encDef.grass
  if grass then
    local HeldItems = require("src.battle.HeldItems")
    rateOverride = HeldItems.cleanseTagRate(Game.data, Game.save.party,
                                            grass.rate)
    if rateOverride == grass.rate then rateOverride = nil end
  end
  if not (Runtime.wantsHook("encounter.roll")
          or Runtime.wantsHook("encounter.species")) then
    return Encounter.roll(encDef, nil, rateMod, rateOverride)
  end
  local ctx = { mapId = self.map.id, terrain = terrain, rng = love.math.random,
                rateMod = rateMod, rateOverride = rateOverride }
  local enc = Runtime.call("encounter.roll", rollVanilla, encDef, ctx)
  if enc then
    enc = Runtime.call("encounter.species", sameEncounter, enc, ctx)
  end
  return enc
end

-- DayCareStep.check_egg (01:$73A2): every overworld step decrements each
-- EGG's hatch counter, and the map script hands control to the hatch scene
-- when one runs out.  Returns true while the hatch text owns the screen.
function OverworldState:stepEggs()
  local save = Game.save
  local hatched
  for _, mon in ipairs(save.party or {}) do
    if mon.isEgg then
      mon.eggSteps = (mon.eggSteps or 1) - 1
      if mon.eggSteps <= 0 and not hatched then hatched = mon end
    end
  end
  if not hatched then return false end
  local Pokemon = require("src.pokemon.Pokemon")
  local def = Game.data.pokemon[hatched.species]
  hatched.isEgg = nil
  hatched.eggSteps = nil
  hatched.nickname = nil
  hatched.happiness = 120  -- BaseHappiness after HatchEggs
  -- THE MEMO'S "hatched at".  Emerald writes met level ZERO on a hatch and
  -- the map section the egg cracked open in; zero is not "unknown", it is the
  -- flag the summary screen reads to choose the hatched template over the
  -- caught one.  Written unconditionally, because an egg carries no met data
  -- until this moment.
  hatched.metLevel = 0
  hatched.metLocation = require("src.battle.BattleState").metHere(Game)
  Pokemon.heal(hatched)
  -- HatchEggs (5:$6FB0) is `ld a, [wCurPartySpecies] / cp TOGEPI / jr nz,
  -- .nottogepi / ld de, $0054 / ld b, 1 / EventFlagAction` -- hatching a
  -- TOGEPI, and only a TOGEPI, sets EVENT_TOGEPI_HATCHED.  That is the flag
  -- ElmPhoneCalleeScript tests (`checkevent $2D / iffalse .next / checkevent
  -- $54 / iftrue .egghatched`), so without it ringing Elm after the EGG
  -- hatched could never reach ElmPhoneEggHatchedText.
  if hatched.species == "SPECIES_175" and Game.save.flags then
    Game.save.flags[require("src.script.Gen2Flags").eventFlag(0x54)] = true
  end
  local name = def and def.name or hatched.species
  Game.stack:push(TextBox.new(Game,
    Strings("Huh?\f%s hatched\nfrom the EGG!", name),
    function()
      Runtime.emit("pokemon.egg_hatched", { mon = hatched })
    end))
  return true
end

-- Run the map's step trigger for the cell the player is standing on, once.
--
-- `onStep` is the same hook onStepComplete uses; what is different here is
-- that nobody stepped.  A one-shot guard per cell stops a trigger whose own
-- gate is unconditional from firing again on the next frame the script ends.
-- `again` re-asks a cell that has already been asked once.
--
-- The cell guard is there so a scene ending on a trigger cell does not set
-- that trigger off again, and it is right for Gen 1 and Gen 2, where a
-- trigger either applies when you land on it or never.  Gen 3's do not work
-- that way: a coord event is gated on a VAR, so the same cell can be
-- ineligible when the player lands on it and eligible a moment later once
-- the map's frame table has written the var.  That is exactly Route 101 --
-- the player lands on (10,19), the rescue's coord event wants
-- VAR_ROUTE101_STATE to be 1, and the frame table is what makes it 1.
--
-- Re-asking is safe because the Gen 3 side remembers which of ITS rows have
-- fired at the cell the player is standing on, so a row cannot run twice
-- while the player stands there however often it is asked.
function OverworldState:checkCoordEventHere(again)
  local hooks = mapScripts.get(self.map and self.map.id)
  if not (hooks and hooks.onStep) then return false end
  local p = self.player
  if not (p and p.cellX) then return false end
  local key = ("%s:%d,%d"):format(self.map.id, p.cellX, p.cellY)
  if self.coordFired == key and not again then return false end
  self.coordFired = key
  return hooks.onStep(Game, self, p.cellX, p.cellY) and true or false
end

-- ---------------------------------------------------------------------------
-- The elevation the cartridge would look a sprite's priority up with, and
-- whether that priority puts it on top of the map's covering layer.
--
-- Kept per entity rather than per step because it is per SPRITE on the
-- cartridge: an NPC standing on a bridge is drawn on top of it as surely as
-- the player is, and nothing else in this port tracks an NPC's level.  The
-- update is the cartridge's sticky rule (see Gen3Elevation), so walking under
-- a bridge -- whose cells are marked 15 -- leaves the walker at the level of
-- the ground they came from and safely under the deck.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- THE STORM THAT MOVES.
--
-- The abnormal weather does not sit on its route forever: a thousand steps
-- after it settles the cartridge takes it somewhere else, and the entry that
-- counts them is another link in the same field chain as the PokeNav calls
-- (0813B3B0).  Every number here is read off it -- the two vars, the limit,
-- the routes and the maps the storm is not allowed to end over (see
-- extractAbnormalWeather).
--
-- The three endings are the cartridge's own, in its order: over the cave and
-- the town above it the storm is only MARKED for ending, so it goes when the
-- player leaves; standing on the route it named, its own script runs and ends
-- it in front of you; anywhere else it simply stops being anywhere.
-- ---------------------------------------------------------------------------
-- THE PC's SCREEN, blinking on.
--
-- Special 217 arms this and does not wait for it -- the cartridge's own
-- effect is a task, and the script carries straight on into the menu -- so
-- the blink runs on the field's clock like the quake and the sagging logs.
-- Five swaps six frames apart, starting lit, which is what leaves the screen
-- lit when it stops; every number is the cartridge's (see pcScreenBlink).
function OverworldState:tickPcScreen()
  local blink = self.gen3PcScreen
  if not blink then return end
  if not (self.map and self.map.setBlock) then
    self.gen3PcScreen = nil
    return
  end
  if blink.frames <= 0 then
    self.map:setBlock(blink.x, blink.y, blink.on and blink.lit or blink.dark,
                      true)
    -- a Gen 3 renderer bakes its window, so a block that changes has to ask
    -- for the rebuild -- the same thing the cracked ice and the sagging
    -- planks have to do (see redrawBlocks)
    self:redrawBlocks()
    blink.on = not blink.on
    blink.left = blink.left - 1
    blink.frames = blink.interval
    if blink.left <= 0 then self.gen3PcScreen = nil end
    return
  end
  blink.frames = blink.frames - 1
end

-- THE DOOR OF A SECRET BASE.
--
-- The field answers a secret-base bg event with a script of its own, and only
-- when the player is FACING NORTH into it -- the cartridge tests the facing
-- before it even looks the script up (080C9510), which is why you cannot open
-- a base by standing beside the tree.  The base's id goes into VAR_0x8004
-- first, because the script is the same one for all seventy-five and the id
-- is the only thing that tells them apart.
function OverworldState:gen3SecretBaseEntrance(sign)
  local record = require("src.world.Gen3SecretBase").record(Game.data)
  local script = record and record.script
  if not script then
    Logger.warn("gen3 secret base: this dataset has no entrance script -- it "
                .. "was imported before the bases were read")
    return false
  end
  if self.player and self.player.facing ~= "up" then return false end
  local id = tonumber(sign.secretBaseId)
  if not id or id < 1 then return false end
  require("src.script.Gen3Commands").setVar(Game.save, 0x8004, id)
  return self:gen3RunFieldScript(script, "secret base") and true or false
end

function OverworldState:gen3AbnormalWeatherStep()
  local record = (Game.data and Game.data.constants
                  or {}).gen3AbnormalWeather
  if type(record) ~= "table" then return end
  local Gen3Commands = require("src.script.Gen3Commands")
  local save = Game.save
  if not save then return end
  local where = math.floor(tonumber(
    Gen3Commands.getVar(save, record.varLocation)) or 0)
  if where < 1 then return end

  local steps = math.floor(tonumber(
    Gen3Commands.getVar(save, record.varCounter)) or 0) + 1
  if steps < (tonumber(record.steps) or 1000) then
    Gen3Commands.setVar(save, record.varCounter, steps)
    return
  end
  Gen3Commands.setVar(save, record.varCounter, 0)

  local group, number = self:gen3MapNumber()
  for _, held in ipairs(record.hold or {}) do
    if group == held.group and number and number >= held.from
       and number <= held.to then
      Gen3Commands.setVar(save, record.varEnd, 1)
      return
    end
  end

  local here = record.locations and record.locations[where]
  if here and group == record.group and number == here.mapNumber then
    self:gen3RunFieldScript(record.script, "abnormal weather")
    return
  end
  Gen3Commands.setVar(save, record.varLocation, 0)
end

-- The map's own group and number, back out of the id the import writes them
-- into.  Nothing else in this port needs them apart, which is why they are
-- taken from the name rather than carried on the def.
function OverworldState:gen3MapNumber()
  local id = self.map and self.map.id
  if type(id) ~= "string" then return nil, nil end
  local group, number = id:match("^MAP_G(%d+)_N(%d+)$")
  return tonumber(group), tonumber(number)
end

function OverworldState:gen3DrawElevation(e)
  local map = self.map
  if not (e and e.cellX and map and map.cellElevation) then return nil end
  local ok, at = pcall(map.cellElevation, map, e.cellX, e.cellY)
  if not ok then return e.gen3Elevation end
  e.gen3Elevation = Gen3Elevation.sticky(e.gen3Elevation, at)
  return e.gen3Elevation
end

function OverworldState:gen3AboveTopLayer(e)
  if not (self.map and self.map.renderer
          and self.map.renderer.hasAboveLayer) then
    return false
  end
  local okLayer, has = pcall(self.map.renderer.hasAboveLayer,
                             self.map.renderer)
  if not (okLayer and has) then return false end
  return Gen3Elevation.aboveTop(Game and Game.data,
                                self:gen3DrawElevation(e))
end

function OverworldState:onStepComplete()
  local p = self.player
  -- THE REMATCH STEP COUNTER.
  --
  -- IncrementRematchStepCounter (0x080B215C) runs once per step and only
  -- once you hold five badges; it saturates at 255, and 255 is the threshold
  -- the map-load roll checks.  Nothing here drove it, so no route trainer in
  -- Hoenn ever wanted a rematch -- the whole POKéNAV MATCH CALL list would
  -- have shown a region of trainers with nothing to say.
  if GameVersion.isGen3() then
    require("src.script.MatchCall").step(Game.data, Game.save)
  end
  -- THE MACH BIKE PICKS UP SPEED, and that speed is the only thing that beats
  -- a mud ramp.
  --
  -- IT IS A THREE-RUNG LADDER, not the four-step count that used to be here.
  -- MachBikeTransition_TrySpeedUp raises a COUNTER while it is at or below
  -- its ceiling, and GetPlayerSpeed reads the rung off a table indexed by
  -- that counter -- so the rider is at full speed on the third step of a run,
  -- not the fifth, and the numbers are the cartridge's rather than a guess.
  -- The counter drops to nothing the moment the rider turns or stops.
  --
  -- A FORCED SLIDE IS NOT A STEP THE RIDER TOOK.  Sliding back down the ramp
  -- used to raise the counter as if it were, so the ramp could be climbed by
  -- failing at it repeatedly and then walking up on the speed that failure
  -- had banked.  The slide sets `muddySlide`, and this leaves the counter
  -- alone while it is set.
  if p.machBike then
    if self.muddySlide then
      -- the slide keeps whatever the rider had; it neither earns nor spends
    elseif p.bikeLastDir == p.facing then
      p.bikeCounter = math.min(self:machCounterMax(), (p.bikeCounter or 0) + 1)
    else
      p.bikeCounter = 0
    end
    p.bikeLastDir = p.facing
  else
    p.bikeCounter, p.bikeLastDir = nil, nil
  end
  -- the level the player is now standing at (see setMap): 0 matches
  -- anything, 15 is "under a bridge" and leaves it alone
  if self.map.elevationAfter then
    p.elevation = self.map:elevationAfter(p.elevation, p.cellX, p.cellY)
  end
  self.todSteps = (self.todSteps or 0) + 1
  -- UpdatePikachuHappinessAndMood rides the step counter (poison.asm)
  require("src.world.PikachuFollower").onStep(Game.save)
  -- Gen2's DailyResetHappiness equivalent: StepHappiness bumps every party
  -- mon once per 128 steps (engine/pokemon/mon_stats.asm), which is what
  -- feeds the HAPPINESS evolutions.
  if self.todSteps % 128 == 0 then
    local Evolution = require("src.pokemon.Evolution")
    for _, mon in ipairs(Game.save.party or {}) do
      Evolution.changeHappiness(mon, "WALKING")
    end
  end
  -- re-evaluate day/night so a step-based clock can fire world.tod_changed;
  -- paletteNameFor reads self.tod on the next paint
  if Runtime.wantsHook("world.tod") then
    self:timeOfDay()
  end

  -- hot path: the payload is only built when something is listening
  if Runtime.wants("world.stepped") then
    Runtime.emit("world.stepped", { mapId = self.map.id, x = p.cellX, y = p.cellY,
                                    tile = self.map:cellTile(p.cellX, p.cellY),
                                    tod = self.tod })
  end

  -- dismounting a surf: landing on a walkable cell ends it.
  --
  -- "Walkable" is not enough on a Gen 3 map: there, every behaviour byte is
  -- walkable and the sea is passable ground, so the cell you are surfing ON
  -- answers yes and the surf would end the moment it began.  What ends it is
  -- landing somewhere that is NOT water.
  if p.surfing and self.map:isWalkableCell(p.cellX, p.cellY)
     and not self.map:isWaterCell(p.cellX, p.cellY) then
    p.surfing = false
    self:syncSurfingPikachu()
    require("src.core.Music").setSurfing(Game.data, false)
  end

  -- THE FIELD CONTROLLER'S OWN STEP CHAIN.  Emerald asks a run of questions
  -- on every step and runs the first script that answers (009C9F4); three of
  -- its entries are served here -- Island Cave's lap, the storm that moves
  -- from route to route, and the five step-counted PokeNav calls.  The chain's
  -- own order is kept: the storm's counter sits above the calls in it.
  self:gen3RegiceStep()
  self:gen3AbnormalWeatherStep()
  self:gen3FieldCallStep()

  -- CheckPhoneCall rides this same step, right after the warp checks
  self:checkIncomingPhoneCall()

  -- Route 22 Gate rewrites LAST_MAP by Y before warps/guards fire
  self:syncLastMapRewrite()

  -- A warp square outranks a step trigger standing on it.  CheckTileEvent
  -- (25:$6874) is `CheckWarpTile / jr c, .warp_tile` FIRST and only then
  -- `CheckCoordEventsEnabled / CheckCurrentMapCoordEvents`, so a coord_event
  -- sharing a cell with a warp never gets to eat the exit.
  --
  -- Goldenrod Pokecenter 1F is where that bites: its two coord_events sit on
  -- (3,7) and (4,7), which ARE the two exit carpets (collision $70).  Running
  -- the trigger first and returning meant the door never fired, so the player
  -- walked in and could not walk back out.
  --
  -- ...except a carpet is not an immediate warp.  CheckWarpTile calls
  -- CheckDirectionalWarp, which clears carry on the four COLL_WARP_CARPET_*
  -- classes, so on those CheckTileEvent falls straight through to the
  -- coord-event check -- the player stands on the mat and only leaves when
  -- they walk on in the mat's own direction (DoPlayerMovement .EdgeWarps).
  -- The port already has that second half: a blocked step while standing on
  -- a warp square goes to Warp.onCollision.  Treating the carpet as
  -- immediate is what made Goldenrod's GS BALL scene unreachable -- the two
  -- coord_events it lives on could never run, so the receptionist never
  -- walked over and the whole Celebi chain behind her stayed dead.
  local warpFirst = nil
  do
    local entryCell = self.warpEntryCell
    local onEntryCell = entryCell
      and entryCell.x == p.cellX and entryCell.y == p.cellY
    if not onEntryCell then
      -- The carpet filter is inside Warp.onArrive now -- it is the second
      -- half of CheckWarpTile, so it belongs beside the lookup rather than
      -- being re-stated at each call site. It was stated here and NOT at the
      -- call further down that actually takes the warp, which is exactly how
      -- a doormat became a trapdoor.
      warpFirst = Warp.onArrive(self.map, p.cellX, p.cellY)
    end
  end

  -- AN AUTHORED EVENT THAT DECLARES ITSELF A REPLACEMENT, ahead of the hooks.
  --
  -- The default below is that the cartridge's own scenes own their squares,
  -- and that is right: an authored trigger able to eat one would make a map
  -- the player walks into and cannot walk out of, with nothing to tell the
  -- author they had done it.
  --
  -- But "the editor cannot touch the cartridge's events" is too strong the
  -- other way. A cartridge script is bytecode behind a label -- there is no
  -- reading it back into beats -- so the only honest way to change one is to
  -- stand in front of it, and the author has to be able to say so. `replaces`
  -- is exactly that sentence, set per event in the events menu (MapEvents.adopt),
  -- never by default: an event without it keeps the old ordering entirely.
  --
  -- STILL AFTER THE WARP. That half of the ordering is not about authorship --
  -- it is CheckTileEvent testing the warp tile first -- and an authored event
  -- that swallowed a door would strand the player just as surely.
  if not warpFirst and not self.runner:isRunning() then
    local events = self.map and self.map.def and self.map.def.events
    if type(events) == "table" then
      for _, ev in ipairs(events) do
        if ev.replaces and ev.x == p.cellX and ev.y == p.cellY
           and type(ev.script) == "table" and #ev.script > 0 then
          self.runner:run(ev.script, { event = ev.id })
          return
        end
      end
    end
  end

  -- hand-ported step triggers (Pallet intro, Saffron gate guards, ...)
  local hooks = mapScripts.get(self.map.id)
  if not warpFirst and hooks and hooks.onStep then
    if hooks.onStep(Game, self, p.cellX, p.cellY) then
      return
    end
  end

  -- EVENT TILES FROM THE MAP DATA, which is where an event the editor made
  -- lives.
  --
  -- AFTER THE HAND-PORTED HOOKS AND AFTER THE WARP, deliberately. The ported
  -- scripts are the cartridge's own scenes and they own their squares; a warp
  -- outranks a trigger for the reason spelled out above (CheckTileEvent tests
  -- the warp tile first). An authored event that could eat either would be a
  -- map the player walks into and cannot walk out of, and the author would
  -- have no way of knowing they had done it.
  --
  -- The rows are ordinary script rows -- `MapEvents.lower` emits nothing the
  -- runner does not already walk -- so this is a lookup and a `run`, not a
  -- second interpreter. Whether the event repeats is the SCRIPT's business:
  -- it opens with its own `check_flag`/`jump_if_true` when the author asked
  -- for once-only, which is the same mechanism they use for everything else.
  if not warpFirst and not self.runner:isRunning() then
    local events = self.map and self.map.def and self.map.def.events
    if type(events) == "table" then
      for _, ev in ipairs(events) do
        if ev.x == p.cellX and ev.y == p.cellY and type(ev.script) == "table"
           and #ev.script > 0 then
          self.runner:run(ev.script, { event = ev.id })
          return
        end
      end
    end
  end

  -- spinner arrow tiles (Viridian Gym, Rocket Hideout)
  if self:checkSpinner() then return end

  -- badge-check guards (Route 22 gate / Route 23)
  if self:checkBadgeGate() then return end

  -- forced bike/surf tiles + the Seafoam surf currents
  if self:checkForcedMovement() then return end
  if self:checkSeafoamCurrent() then return end
  if self:checkThinIce() then return end
  -- the ash sweeps under you and does not stop you walking, so it is asked
  -- rather than obeyed
  self:checkAshGrass()
  self:armCrackedFloor()
  self:checkFortreeBridge()
  self:checkPacifidlogLogs()
  if self:checkMuddySlope() then return end
  if self:checkGen3Current() then return end
  if self:checkGen2Ice() then return end

  -- the Safari game step counter (engine/events/hidden_events/safari_game.asm)
  if self:safariStep() then return end

  -- day-care: the boarded Pokémon gains 1 exp per step (like the original)
  if Game.save.daycare and Game.save.daycare.mon then
    Game.save.daycare.steps = (Game.save.daycare.steps or 0)
      + (FieldDefaults.world(Game.data, "daycareExpPerStep") or 1)
  end
  -- Gen2 runs two pens plus the breeding counter (DayCareStep, 01:$735E),
  -- and so does Hoenn: _TryProduceOrHatchEgg walks both pens on every step
  -- and rolls for an egg when the counter's low byte comes round.  Without
  -- this the Route 117 day care took your Pokemon and then stood still --
  -- nothing grew a level and no egg was ever laid.
  if GameVersion.isGen2() or GameVersion.isGen3() then
    require("src.pokemon.DayCare").step(Game.data, Game.save,
      FieldDefaults.world(Game.data, "daycareExpPerStep") or 1)
  end

  -- out-of-battle poison (engine/events/poison.asm): every 4th step
  -- each poisoned mon loses 1 HP, with the screen flicker + sound
  if self:applyFieldPoison() then return end

  -- an EGG one step from hatching owns the screen the same way
  if self:stepEggs() then return end

  self.boulderTried = nil -- a completed step ends any armed boulder push

  -- arriving on a door/warp tile warp; a non-door warp square also fires
  -- when the extra check passes and the d-pad is held
  -- (CheckWarpsNoCollision)
  -- The cell we warped in on is inert until we step off it: standing on it,
  -- or being walked back onto it before leaving, does not re-fire (see
  -- warpEntryCell where it is set). Once we are on any other cell it clears
  -- and every warp is live again.
  local entry = self.warpEntryCell
  if entry and (p.cellX ~= entry.x or p.cellY ~= entry.y) then
    self.warpEntryCell = nil
    entry = nil
  end
  -- The arrival disable is POSITIONAL: warpEntryCell above is the whole
  -- test.  Consuming a completed step with a one-shot "just warped" counter
  -- instead swallowed the warp under the player's feet, which is why a
  -- second ladder one cell from the first did nothing (Seafoam B3F has warp
  -- tiles on (25,3) and (25,4)) -- issue #265.  pokered has no such counter:
  -- every completed step runs CheckWarpsNoCollision (home/overworld.asm).
  -- That same step is where BIT_STANDING_ON_WARP is maintained: cleared
  -- before the check (home/overworld.asm:324), set again while standing on a
  -- warp square, then cleared once more when the square is a warp-activating
  -- tile that is not a door tile (IsPlayerStandingOnDoorTileOrWarpTile).
  self:refreshStandingOnWarp()
  if entry then
    -- still standing on the warp we arrived through; do not re-trigger it
  else
    -- CheckWarpsNoCollision: door/warp tiles fire immediately; otherwise
    -- ExtraWarpCheck must pass AND either a d-pad is held or BIT_FORCED_WARP
    -- is set (Seafoam B3F currents -- home/overworld.asm).
    local w = Warp.onArrive(self.map, p.cellX, p.cellY)
    -- ...and ExtraWarpCheck is a GEN 1 routine with no Gen 2 counterpart.
    -- Gen 2's CheckTileEvent runs CheckWarpTile and nothing else; the only
    -- other way a warp fires there is DoPlayerMovement .CheckWarp, which is
    -- the directional carpet and is handled on the input side.
    --
    -- Leaving this on would put the corner mats back: ExtraWarpCheck falls
    -- back to "is the player facing the map edge", so a LEFT-facing carpet
    -- sitting on the bottom row would still warp somebody who walked down
    -- along it -- the same wrong exit, through a different door.
    local gen2Classes = GameVersion.isGen2()
      and self.map.speaksGen2Collision and self.map:speaksGen2Collision()
    if not w and not gen2Classes and (self:dirHeld() or self.forcedWarp) then
      w = Warp.onCollision(self.map, Game.data.field.warpCarpets,
                           p.cellX, p.cellY, p.facing)
    end
    if w then
      self:takeWarp(w.def)
      return
    end
  end

  if Game.save.repelSteps and Game.save.repelSteps > 0 then
    Game.save.repelSteps = Game.save.repelSteps - 1
    if Game.save.repelSteps == 0 then
      -- no encounter on the exact wear-off step (wild_encounters.asm
      -- .lastRepelStep returns CantEncounter)
      Game.stack:push(TextBox.new(Game, Strings("REPEL's effect\nwore off.")))
      return
    end
  end

  -- TryWildEncounter_BugContest (25:$7D64): while the contest is running the
  -- park rolls its OWN table (ContestMons) and ignores the map's wildmons
  -- entirely.  Guarded on the run being live, so visiting the park outside the
  -- contest still rolls the ordinary National Park slots.
  local BugContest = require("src.world.BugContest")
  if BugContest.active(Game.save)
     and self.map.id == BugContest.contestMap()
     and self.map:isGrassCell(p.cellX, p.cellY) then
    local wild = BugContest.rollEncounter(Game)
    if wild then
      local BattleState = require("src.battle.BattleState")
      local battle = BattleState.newWild(Game, wild.species, wild.level)
      battle:makeBugContest()
      battle.onFinish = function(result) self:afterBattle(result, battle) end
      self:pushBattle(battle)
    end
    return
  end

  -- wild encounters in grass, on water while surfing, or -- on indoor
  -- maps whose tileset is not FOREST -- on EVERY tile
  -- (wild_encounters.asm: caves, towers, the Mansion, Power Plant)
  local encDef = Game.data.encounters[self.map.id]
  local enc
  local indoor = Game.data.field.indoorEncounters
  local env = self.map.def.environment
  -- Gen2 keeps a morn/day/nite slot set per map; the clock decides which
  local land = encDef and { grass = Encounter.atTime(encDef.grass, self:timeOfDay()) }
  local onWater = (p.surfing and self.map:isWaterCell(p.cellX, p.cellY)) or false
  if p.surfing and encDef and encDef.water and self.map:isWaterCell(p.cellX, p.cellY) then
    enc = self:rollEncounter({ grass = encDef.water }, "water")
  -- isEncounterCell IS isGrassCell wherever a tileset does not say otherwise,
  -- so Kanto and Johto read exactly as before.  Hoenn says otherwise: a cave
  -- floor and the desert's deep sand are not grass and a wild Pokemon comes
  -- out of both (see Map:isEncounterCell).
  elseif self.map:isEncounterCell(p.cellX, p.cellY) then
    enc = self:rollEncounter(land, "grass")
  elseif CAVE_ENVIRONMENTS[env] then
    enc = self:rollEncounter(land, "indoor")
  elseif env == nil and indoor and type(self.map.def.index) == "number"
         and self.map.def.index >= indoor.firstIndoorMap
         and self.map.def.tileset ~= indoor.excludedTileset then
    -- `index` is Gen 1's map NUMBER, and a Gen 3 def has none; comparing nil
    -- here raises, which would have taken the step handler down on the first
    -- cave floor rather than merely failing to roll
    enc = self:rollEncounter(land, "indoor")
  end

  -- A battle is where the report puts it: the Elite Four member is drawn
  -- before the fight and not after. Whatever churns the entity list across a
  -- battle -- a mod's spawns being torn down and rebuilt around it is the
  -- obvious candidate, since both voxel mods hold this list -- the actors this
  -- map owns are put back in the draw list here.
  self:reassertEntities("afterBattle")

  -- ------------------------------------------------------ ROAMING BEASTS
  --
  -- ChooseWildEncounter asks CheckEncounterRoamMon BEFORE it rolls a slot,
  -- and a hit jumps straight to .startwildbattle with the beast already
  -- staged -- so a beast REPLACES the encounter this step was going to be
  -- rather than being an extra chance on top of it.
  --
  -- Here that is the same statement made one step later: `enc` being non-nil
  -- is exactly "LoadWildMonDataPointer found a table for this map AND the
  -- encounter-rate roll passed", which is the state the cartridge is in when
  -- it makes the call. What differs is only which numbers come off the RNG,
  -- and nothing in this port is cycle-accurate about that anyway.
  --
  -- It has to sit ABOVE the repel test, because that is where the cartridge
  -- has it -- and a beast is emphatically not exempt from repel (see below).
  local roamer
  if enc and not onWater and GameVersion.isGen3() then
    -- HOENN'S ROAMER IS ONE, NOT THREE, and the roll is its own: the
    -- cartridge asks IsRoamerAt first and only then spends a quarter chance,
    -- so the odds are per-encounter on ITS route and zero everywhere else.
    local Roam = require("src.world.Gen3Roamers")
    if Roam.check(Game.data, Game.save, self.map.id, love.math.random) then
      local one = Roam.encounterFor(Game.data, Game.save)
      if one and one.species then
        enc, roamer = one, "gen3"
      end
    end
  elseif enc and not onWater then
    local RoamMons = require("src.world.RoamMons")
    local name, info = RoamMons.check(Game.save, self.map.id, onWater,
                                      love.math.random)
    if name then
      local beast = RoamMons.encounterFor(name, info)
      if beast and beast.species then
        enc, roamer = beast, name
      end
    end
  end

  if enc then
    -- REPEL blocks wild mons weaker than the lead.
    --
    -- "the lead" is CheckRepelEffect's `Get the first Pokemon in your party
    -- that isn't fainted` -- it walks wPartyMon1HP forward until it finds a
    -- live one -- NOT party slot 1. With a fainted lead this read the wrong
    -- level, and it read `nil.level` and crashed outright on a party whose
    -- first slot is an EGG.
    --
    -- AND THIS IS WHY THE BEASTS WOULD NOT SHOW UP FOR ANYONE HUNTING THEM
    -- WITH MAX REPEL. The comparison is `wCurPartyLevel cp leadLevel /
    -- jr nc, .encounter`: the encounter happens only when the wild level is
    -- at least the lead's. Every beast is level 40. So a repel with anything
    -- above level 40 in front suppresses Raikou, Entei and Suicune along with
    -- everything else -- on the cartridge as much as here. Repel-hunting a
    -- roamer needs a level 40-or-lower lead, which is also the only way it
    -- ever worked on hardware.
    local Party = require("src.pokemon.Party")
    local lead = Party.firstHealthy(Game.save.party) or Game.save.party[1]
    if Game.save.repelSteps and Game.save.repelSteps > 0
       and lead and lead.level and enc.level < lead.level then
      return
    end
    local BattleState = require("src.battle.BattleState")
    -- BATTLETYPE_ROAMING: Music_SuicuneBattle, the one-turn flee, and the
    -- HP that carries between meetings all hang off this.
    local battle = BattleState.newWild(Game, enc.species, enc.level,
      roamer and { battleType = "roaming", roamer = roamer,
                   roamerHP = enc.roamerHP,
                   roamerStatus = enc.roamerStatus,
                   roamerSeed = enc.roamerSeed } or nil)
    -- map.ghostBattles: unidentifiable without the named item (the
    -- Pokemon Tower's Silph Scope)
    local ghost = Map.ghostBattles(self.map.def)
    if ghost and not (ghost.unlessItem and Game.save.inventory[ghost.unlessItem]) then
      battle:makeGhost()
    end
    -- Safari game encounters use the BALL/BAIT/ROCK/RUN menu
    if self:inSafariGame() then
      battle:makeSafari(Game.save.safari)
    end
    battle.onFinish = function(result) self:afterBattle(result, battle) end
    self:pushBattle(battle)
    return
  end
end

-- Spinner arrow tiles (scripts/{ViridianGym,RocketHideoutB2F,B3F}.asm
-- via field.spinners): landing on one plays the arrow SFX and slides the
-- player along the extracted movement list; the landing cell may be
-- another arrow, which chains.
function OverworldState:checkSpinner()
  local list = Game.data.field.spinners and Game.data.field.spinners[self.map.id]
  if not list then return false end
  local p = self.player
  for _, sp in ipairs(list) do
    if sp.x == p.cellX and sp.y == p.cellY then
      require("src.core.Sound").play(Game.data, "Arrow_Tiles")
      self:runSpinnerMoves(sp.moves, 1)
      return true
    end
  end
  return false
end

function OverworldState:runSpinnerMoves(moves, i)
  local mv = moves[i]
  if not mv then
    self.player.spinning = false
    -- Scripted steps skip onStepComplete while they run; once the RLE
    -- finishes, re-enter the normal landing pipeline so chained spinners,
    -- Seafoam currents, and CheckWarpsNoCollision (incl. BIT_FORCED_WARP)
    -- see the tile we stopped on -- same as pokered after simulated joypad.
    self:onStepComplete()
    return
  end
  self.player.spinning = true -- spin the sprite while sliding
  self:scriptMove(self.player, mv.dir, mv.count, function()
    self:runSpinnerMoves(moves, i + 1)
  end)
end

-- Badge-check guards (scripts/Route22Gate.asm, scripts/Route23.asm via
-- field.badgeGates): stepping on a guard row without the badge turns
-- you back; with it, the guard waves you through once.

-- field.lastMapRewrites: maps that rewrite wLastMap from the player's
-- position every frame.  Rules are ordered, first match wins, the last row
-- is the default -- pokered Route22Gate_Script is Y < 4 -> ROUTE_23, else
-- ROUTE_22, which is what makes the gate's north exit leave onto Route 23.
-- All four of its door warps are LAST_MAP.
function OverworldState.rewrittenLastMap(rewrite, cellX, cellY)
  local value = rewrite.axis == "x" and cellX or cellY
  for _, rule in ipairs(rewrite.rules or {}) do
    if (rule.below == nil or value < rule.below)
       and (rule.atLeast == nil or value >= rule.atLeast) then
      return rule.map
    end
  end
  return nil
end

function OverworldState:syncLastMapRewrite()
  if not self.map then return end
  local rewrites = FieldDefaults.field(Game.data, "lastMapRewrites")
  local rewrite = rewrites and rewrites[self.map.id]
  if not rewrite then return end
  local id = OverworldState.rewrittenLastMap(rewrite, self.player.cellX,
                                             self.player.cellY)
  if not id or (self.lastOutdoor and self.lastOutdoor.id == id) then return end
  local warps = Game.data.maps[id] and Game.data.maps[id].warps
  local w = warps and warps[1]
  self:rememberOutdoor(id, w and w.x or 0, w and w.y or 0)
end

-- field.badgeGates is keyed by map; the record's shape picks the rule.
-- `coords` is the Route 22 gate's single checkpoint (one-shot pass text),
-- `guards` the Route 23 ladder of per-row guards.
function OverworldState:checkBadgeGate()
  local gates = Game.data.field.badgeGates
  local g = gates and gates[self.map.id]
  if not g then return false end
  local p = self.player
  local t = Game.data.text

  if g.coords then
    local passedFlag = FieldDefaults.fieldValue(Game.data, "badgeGates",
                                                self.map.id, "passedFlag")
                       or ("PASSED_" .. self.map.id)
    for _, c in ipairs(g.coords) do
      if p.cellX == c.x and p.cellY == c.y then
        if Game.save.inventory[g.badge] then
          if not Game.save.flags[passedFlag] then
            Game.save.flags[passedFlag] = true
            -- Route22GateGuardGoRightAheadText plays sound_get_item_1
            require("src.core.Sound").play(Game.data, "Get_Item1")
            Game.stack:push(TextBox.new(Game,
              t["_" .. g.passText] or Strings("Go right ahead!")))
          end
          return false
        end
        -- Route22GateGuardNoBoulderbadgeText plays SFX_DENIED
        require("src.core.Sound").play(Game.data, "Denied")
        Game.stack:push(TextBox.new(Game,
          (t["_" .. g.failText] or Strings("You don't have the\nBOULDERBADGE yet!"))
          .. (t._Route22GateGuardICantLetYouPassText or ""), function()
            self:scriptMove(p, "down", 1)
          end))
        return true
      end
    end
    return false
  end

  if g.guards then
    for _, guard in ipairs(g.guards) do
      if p.cellY == guard.y and (not guard.maxX or p.cellX <= guard.maxX)
         and not Game.save.flags[guard.event] then
        local badgeName = Game.data.items[guard.badge]
                          and Game.data.items[guard.badge].name or guard.badge
        if Game.save.inventory[guard.badge] then
          Game.save.flags[guard.event] = true
          -- Route23OhThatIsTheBadgeText plays sound_get_item_1
          require("src.core.Sound").play(Game.data, "Get_Item1")
          local text = (t["_" .. g.passText] or
                        Strings("Oh! That is the\n{RAM}!")):gsub("{RAM:wNameBuffer}", badgeName)
          Game.stack:push(TextBox.new(Game, text))
          return false
        end
        -- Route23YouDontHaveTheBadgeYetText plays SFX_DENIED
        require("src.core.Sound").play(Game.data, "Denied")
        local text = (t["_" .. g.failText] or
                      Strings("You don't have the\n{RAM} yet!")):gsub("{RAM:wNameBuffer}", badgeName)
        Game.stack:push(TextBox.new(Game, text, function()
          self:scriptMove(p, "down", 1)
        end))
        return true
      end
    end
  end
  return false
end

-- Forced bike/surf tiles (data/maps/force_bike_surf.asm): the Cycling
-- Road entrances force you onto the BICYCLE (or turn you back without
-- one); the Seafoam current mouths force surfing.
function OverworldState:checkForcedMovement()
  local fm = Game.data.field.forcedMovement
  if not fm then return false end
  local p = self.player
  local forcedTiles = fm.tiles or {}
  for _, tile in ipairs(forcedTiles[self.map.id] or {}) do
    if p.cellX == tile.x and p.cellY == tile.y then
      if tile.mode == "bike" then
        -- CheckForceBikeOrSurf (engine/overworld/player_state.asm) also
        -- sets BIT_ALWAYS_ON_BIKE of wStatusFlags6 here -- the flag
        -- IsSurfingAllowed reads to refuse SURF on the Cycling Road.
        -- Cleared by the Route 16/18 gate scripts, fly/dungeon warps and
        -- blackouts (see setMap / flyTo / warpToHealPoint).
        if Game.save.onBike then
          Game.save.forcedBike = true
          return false
        end
        if (Game.save.inventory.BICYCLE or 0) > 0 then
          -- CheckForceBikeOrSurf mounts silently; _CyclingIsFunText only
          -- exists as IsSurfingAllowed's refusal (engine/overworld/
          -- field_move_messages.asm), never as a mount message.
          Game.save.onBike = true
          Game.save.forcedBike = true
          require("src.core.Music").playMap(Game.data, self.map.id, true)
        else
          Game.stack:push(TextBox.new(Game, Strings("You need a\nBICYCLE for the\nCycling Road!"),
            function()
              local back = ({ up = "down", down = "up",
                              left = "right", right = "left" })[p.facing]
              self:scriptMove(p, back, 1)
            end))
          return true
        end
      elseif tile.mode == "surf" then
        p.surfing = true
        self:syncSurfingPikachu()
        require("src.core.Music").setSurfing(Game.data, true)
      end
      return false
    end
  end
  return false
end

-- The Seafoam Islands surf currents (scripts/SeafoamIslandsB3F/B4F.asm
-- via field.seafoam): while the plug boulders aren't down, the water
-- drags the player along the extracted movement lists; the B4F pool
-- edge pushes you back up until the B3F boulders fall.
function OverworldState:checkSeafoamCurrent()
  local sf = Game.data.field.seafoam and Game.data.field.seafoam[self.map.id]
  if not sf then return false end
  local p = self.player
  local function allSet(events)
    for _, e in ipairs(events or {}) do
      if not Game.save.flags[e] then return false end
    end
    return true
  end

  if sf.forcedExit and p.surfing and not allSet(sf.forcedExit.activeUntilEvents) then
    for _, c in ipairs(sf.forcedExit.coords) do
      if p.cellX == c.x and p.cellY == c.y then
        -- SeafoamIslandsB4FDefaultScript: res BIT_FORCED_WARP before the
        -- push so the B3F stair warps underfoot cannot bounce you back.
        self.forcedWarp = false
        require("src.core.Sound").play(Game.data, "Collision")
        self:scriptMove(p, "up", c.y == 17 and 2 or 1)
        return true
      end
    end
  end

  if not p.surfing then return false end
  local active = {}
  if not allSet(sf.currentsDisabledByEvents) then
    for _, c in ipairs(sf.currents or {}) do table.insert(active, c) end
  end
  if sf.entryCurrent then
    local plugged = true
    for _, h in ipairs((sf.pluggedByHolesOn or {}).holes or {}) do
      if not Game.save.flags[h.boulderEvent] then plugged = false end
    end
    if not plugged then table.insert(active, sf.entryCurrent) end
  end
  for _, c in ipairs(active) do
    if p.cellX == c.x and p.cellY == c.y then
      -- SeafoamIslandsB3F.asm sets BIT_FORCED_WARP before DecodeRLEList so
      -- the south-edge water stairs auto-warp when the current ends.
      if FieldDefaults.fieldValue(Game.data, "seafoam", self.map.id,
                                  "setsForcedWarp") then
        self.forcedWarp = true
      end
      self:runSpinnerMoves(c.moves, 1)
      return true
    end
  end
  return false
end

-- Boulder holes (Seafoam4HolesCoords etc.): a boulder pushed onto a
-- hole falls to the floor below, permanently plugging a current.
function OverworldState:seafoamHolesFor(mapId)
  local out = {}
  for owner, sf in pairs(Game.data.field.seafoam or {}) do
    if owner == mapId then
      for _, h in ipairs(sf.holes or {}) do
        table.insert(out, { hole = h, destMap = sf.holeDestination })
      end
    end
    if sf.pluggedByHolesOn and sf.pluggedByHolesOn.map == mapId then
      for _, h in ipairs(sf.pluggedByHolesOn.holes or {}) do
        table.insert(out, { hole = h, destMap = owner })
      end
    end
  end
  return out
end

-- toggleable_objects.asm names (TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_1)
-- vs object_event const names (SEAFOAMISLANDSB3F_BOULDER1)
local function toggleToObjectName(mapId, toggleName)
  local prefix = "TOGGLE_" .. mapId .. "_"
  if toggleName:sub(1, #prefix) ~= prefix then return nil end
  return mapId:gsub("_", "") .. "_" .. toggleName:sub(#prefix + 1):gsub("_", "")
end

function OverworldState:boulderIntoHole(npc)
  for _, entry in ipairs(self:seafoamHolesFor(self.map.id)) do
    local h = entry.hole
    if npc.cellX == h.x and npc.cellY == h.y then
      require("src.core.Sound").play(Game.data, "Faint_Thud")
      Game.save.flags[h.boulderEvent] = true
      local toggles = Game.save.objectToggles or {}
      Game.save.objectToggles = toggles
      if h.hideObject then
        local name = toggleToObjectName(self.map.id, h.hideObject)
        if name then
          toggles[self.map.id] = toggles[self.map.id] or {}
          toggles[self.map.id][name] = false
        end
      end
      if h.showObject and entry.destMap then
        local name = toggleToObjectName(entry.destMap, h.showObject)
        if name then
          toggles[entry.destMap] = toggles[entry.destMap] or {}
          toggles[entry.destMap][name] = true
        end
      end
      for i = #self.npcs, 1, -1 do
        if self.npcs[i] == npc then table.remove(self.npcs, i) end
      end
      for i = #self.entities, 1, -1 do
        if self.entities[i] == npc then table.remove(self.entities, i) end
      end
      Game.stack:push(TextBox.new(Game, Strings("The boulder fell\nthrough the hole!")))
      return true
    end
  end
  return false
end

-- Safari game step/ball bookkeeping.  502 steps per ¥500 game; running
-- out of steps (or balls, checked after battles) ends the game and
-- returns to the gate (engine/events/hidden_events/safari_game.asm).
-- The oracle gates on EVENT_IN_SAFARI_ZONE, not the current map (see
-- home/overworld.asm:307-310); that flag is set right before the
-- entrance auto-walk off SAFARI_ZONE_GATE and cleared only when the
-- player returns to the gate (or uses an Escape Rope), so every
-- interior Safari Zone map -- the 4 zone quadrants plus the 4 rest
-- houses plus the secret house -- counts, and the gate itself never
-- does.
-- field.safari.stepMaps
-- IS A SAFARI GAME RUNNING HERE?
--
-- Two generations answer it differently and both are the cartridge's own
-- answer.  Kanto and Johto set a flag at the gate and then check the MAP,
-- because the flag survives an escape rope and the map is what says you are
-- still inside.  Emerald checks the MODE and nothing else: gSpecials turns it
-- on at the gate and off at the exit, and the battle type follows the flag.
-- The Hoenn maps are called MAP_G22_N04, so the older test answered no
-- everywhere in the region and the whole zone was ordinary grass.
function OverworldState:inSafariGame()
  if not Game.save.safari then return false end
  if GameVersion.isGen3() then return true end
  return Map.inRegion(self.map.def, "SAFARI", "SAFARI_ZONE")
end

function OverworldState:inSafariStepZone()
  -- every step of a Hoenn game counts: there is no separate list of rooms,
  -- because the mode is not a place
  if GameVersion.isGen3() then return Game.save.safari ~= nil end
  for _, m in ipairs(FieldDefaults.fieldValue(Game.data, "safari", "stepMaps") or {}) do
    if m == self.map.id then return true end
  end
  return false
end

function OverworldState:safariStep()
  local st = Game.save.safari
  if not st or not self:inSafariStepZone() then return false end
  st.steps = st.steps - 1
  if st.steps > 0 then return false end
  local said = self:safariLine("outOfTime")
  self:safariGameOver(said or Strings("PA: Ding-dong!\nTime's up!"),
                      said ~= nil)
  return true
end

-- WHERE A GAME THAT ENDS ON ITS OWN PUTS YOU.
--
-- The same door you would have walked out of: the script that calls
-- ExitSafariMode warps out of the zone in its next command, and the import
-- reads that warp rather than this file naming a map.
function OverworldState:safariExitWarp()
  if GameVersion.isGen3() then
    local record = Game.data.constants and Game.data.constants.gen3Safari
    local warp = record and record.exitWarp
    if not (warp and warp.group and warp.number) then return nil end
    return { map = require("src.script.Gen3Commands").mapKey(warp.group,
                                                             warp.number),
             x = warp.x, y = warp.y }
  end
  return FieldDefaults.fieldValue(Game.data, "safari", "exitWarp")
end

-- WHAT THE ZONE SAYS WHEN A GAME ENDS.
--
-- Neither line is reachable from a map -- the cartridge runs them from the
-- code that notices the last ball or the last step -- so the import finds
-- them by shape instead (see extractSafari). Each is the WHOLE announcement,
-- ending in its own "your SAFARI Game is over", so it replaces both halves of
-- the Game Boy version rather than being pasted in front of one.
function OverworldState:safariLine(which)
  local record = Game.data.constants and Game.data.constants.gen3Safari
  local line = record and record[which]
  return type(line) == "string" and #line > 0 and line or nil
end

function OverworldState:safariGameOver(text, whole)
  require("src.core.Sound").play(Game.data, "Safari_Zone_PA")
  Game.save.safari = nil
  local t = Game.data.text
  Game.stack:push(TextBox.new(Game,
    whole and (text or "")
      or ((text or "") .. "\f"
          .. (t._GameOverText or Strings("PA: Your SAFARI\nGAME is over!"))),
    function()
      local exit_ = self:safariExitWarp()
      if exit_ then
        self:startWarpTo(exit_.map, exit_.x, exit_.y, exit_.facing or "down")
      end
    end))
end

-- Blackouts return to the last heal point; evolutions run after battles.
-- battle is optional; when given, Oak's Lab OPP_RIVAL1 losses skip the
-- blackout (pret HandlePlayerBlackOut) so the map script can HealParty.
function OverworldState:afterBattle(result, battle)
  local lead = Game.save.party[1]
  Logger.info("battle over: %s (lead %s %d/%d)", tostring(result),
              lead and lead.species or "-", lead and lead.hp or 0,
              lead and lead.stats.hp or 0)

  -- ------------------------------------------------------ ROAMING BEASTS
  --
  -- The roam slot is the beast's whole existence: the cartridge keeps its
  -- species, level, map and HP there, and clearing the slot's map group to
  -- GROUP_N_A is how a caught or beaten beast stops existing. So the outcome
  -- of the fight has to land back on the slot, or a caught Raikou keeps
  -- roaming, keeps showing on the Pokegear, and can be caught again.
  --
  -- Escaping writes the HP back instead. That is the point of chasing one:
  -- damage carries between meetings, and a beast on a sliver stays on a
  -- sliver until you finally land the ball.
  if battle and battle.roamer then
    local enemy = battle.enemy
    local hp = enemy and enemy.mon and enemy.mon.hp or 0
    local gone = result == "caught" or result == "win" or hp <= 0
    if battle.roamer == "gen3" then
      -- ...and Hoenn's flees FURTHER than Johto's: UpdateRoamerHPStatus ends
      -- by calling the long hop, so a roamer you have just met is never on
      -- the next route over.
      local Roam = require("src.world.Gen3Roamers")
      if gone then
        Roam.retire(Game.save)
      else
        local status = enemy and enemy.mon and enemy.mon.status
        Roam.remember(Game.data, Game.save, hp, status)
      end
    else
      local RoamMons = require("src.world.RoamMons")
      if gone then
        RoamMons.retire(Game.save, battle.roamer)
      else
        RoamMons.remember(Game.save, battle.roamer, hp)
      end
    end
  end
  local Evolution = require("src.pokemon.Evolution")
  local function evolutions()
    -- Only mons that gained a level this battle (EXP.ALL included).
    -- Scanning the whole party re-offered B-cancelled evolutions forever (#213).
    Evolution.checkParty(Game, nil, battle and battle.leveledUp)
  end
  if result == "lose" then
    local oaksLabRival = battle and battle.oppClass == "OPP_RIVAL1"
      and self.map and self.map.id == "OAKS_LAB"
    if oaksLabRival then
      -- stay in the lab; OaksLabRivalEndBattleScript heals and continues
      evolutions()
      return
    end
    -- BATTLETYPE_CANLOSE: the Battle Tower ends the challenge and warps the
    -- player back to its own lobby, with no blackout and no money lost.
    if battle and battle.canLose then
      evolutions()
      return
    end
    -- blackout: revive the party at the last heal point; half the
    -- money is lost (like the original)
    local Pokemon = require("src.pokemon.Pokemon")
    for _, mon in ipairs(Game.save.party) do
      Pokemon.heal(mon)
    end
    Game.save.money = math.floor(Game.save.money
      / (FieldDefaults.world(Game.data, "blackoutMoneyDivisor") or 2))
    Runtime.emit("world.blacked_out",
      { save = Game.save, healTarget = self:healPoint() })
    self:warpToHealPoint(evolutions)
  else
    -- EndTrainerBattle sets BIT_CUR_MAP_LOADED_1 (home/trainers.asm), which
    -- re-runs the floor's door callback: beating the last Rocket Hideout guard
    -- opens the lift gate without leaving the map (#372)
    self:stampClosedDoors()
    -- throwing the last SAFARI BALL ends the game
    if Game.save.safari and Game.save.safari.balls <= 0 then
      local said = self:safariLine("outOfBalls")
      self:safariGameOver(said or Strings("PA: You're out of\nSAFARI BALLs!"),
                          said ~= nil)
    end
    -- BugCatchingContestBattleScript's tail (contest.asm:8-13):
    --
    --     reloadmapafterbattle
    --     readmem wParkBallsRemaining
    --     iffalse BugCatchingContestOutOfBallsScript
    --
    -- so the OVERWORLD ends the run, not the battle -- which is why a missing
    -- check here let the player keep throwing Park Balls forever after the
    -- twentieth.
    local BugContest = require("src.world.BugContest")
    if BugContest.active(Game.save) and BugContest.ballsLeft(Game.save) <= 0 then
      self:bugContestOver("_BugCatchingContestIsOverText",
                          Strings("ANNOUNCER: The\nContest is over!"))
    end
    evolutions()
  end
end

-- -------------------------------------------------------------------------
-- warps
-- -------------------------------------------------------------------------

-- field.boot: where a save with no heal point of its own returns to.  The
-- lastHeal record wins; otherwise the new game's own spawn cell.
function OverworldState:healPoint()
  -- GEN 3 ANSWERS THIS FROM ITS OWN TABLE.  `setrespawn` is the script
  -- command every Pokemon Centre in Hoenn runs on entry, and its argument is
  -- an INDEX INTO sHealLocations -- so the index the command already stored
  -- and the table the heal-location stage now extracts are the two halves of
  -- the same answer, and neither was any use without the other.  Until this,
  -- `gen3RespawnIndex` was written by the script engine and read by nothing,
  -- and a Hoenn blackout fell through to the boot spawn -- the truck.
  if GameVersion.isGen3() then
    local list = Game.data.constants and Game.data.constants.gen3HealLocations
    local row = list and list[tonumber(Game.save.gen3RespawnIndex or 0) or 0]
    if row then return { map = row.map, x = row.x, y = row.y } end
  end
  local boot = (Game.data.field or {}).boot or {}
  return Game.save.lastHeal or boot.lastHeal
    or { map = boot.startMap, x = boot.startX, y = boot.startY }
end

function OverworldState:takeWarp(warpDef)
  local last = self.lastOutdoor
  if warpDef.destMap == "LAST_MAP" and not last then
    -- old saves / unexpected states: never crash on an exit mat, fall
    -- back to the heal point's town door (or the boot spawn)
    Logger.warn("LAST_MAP warp with no remembered outdoor map; using heal point")
    local heal = self:healPoint()
    last = heal.outdoor or { id = heal.map, x = heal.x, y = heal.y }
  end
  local fromMap = self.map.id
  -- the save goes with it: a Gen 3 door may name the dynamic-warp placeholder,
  -- and where that points is script state, not map data
  local destMap, x, y = Warp.destination(Game.data, warpDef, last,
                                         self.backupWarp, Game.save)
  -- nil means the warp could not be resolved at all -- today that is a Gen 3
  -- door naming the dynamic-warp placeholder before anything set it.  Standing
  -- still with a line in the log beats handing MapLoader an id that does not
  -- exist, which raises under the player's feet.
  if not destMap then return end
  -- EnterMapWarp stores the warp being left through as the backup, so a
  -- LAST_WARP door on the far side comes straight back here
  self.backupWarp = { id = fromMap, x = self.player.cellX, y = self.player.cellY }
  Game.save.backupWarp = self.backupWarp
  -- EnterMapWarp.SaveDigWarp (engine/overworld/warp_connection.asm): stepping
  -- from an OUTDOOR map into an INDOOR one records the warp you came in
  -- through, and that -- not the last Pokemon Center -- is where Gen 2's Dig
  -- and Escape Rope put you back.
  self:rememberDigWarp(fromMap, self.player.cellX, self.player.cellY, destMap)
  Runtime.emit("player.warped", { fromMap = fromMap, toMap = destMap,
                                  x = x, y = y, warp = warpDef })
  -- facing carries across the warp (leaving a gate sideways keeps you
  -- walking sideways; house exit mats are stepped onto facing down)
  local facing = self.player.facing
  -- warp pads and fall-through holes are not doors (WarpFound2
  -- .indoorMaps: IsPlayerStandingOnWarpPadOrHole routes them through
  -- LeaveMapAnim/EnterMapAnim instead of the door SFX)
  local pad = self.map.warpPadOrHoleAt
              and self.map:warpPadOrHoleAt(self.player.cellX, self.player.cellY)
  if pad == "pad" then
    -- teleporter: spin out with the exit SFX, spin back in on arrival
    -- (player_animations.asm _LeaveMapAnim / EnterMapAnim)
    require("src.core.Sound").play(Game.data, "Teleport_Exit1")
    self.player.spinning = true
    self.player.spinTimer = 0
    self.arriveWarp = "teleport"
    self:startWarpTo(destMap, x, y, facing)
    return
  elseif pad == "hole" then
    -- falling through a hole: no door SFX, no walk-out step
    self:startWarpTo(destMap, x, y, facing)
    return
  end
  -- THE ESCALATORS.  All 34 of them already carried a warp event, so the
  -- player was being moved between floors correctly -- through the DOOR path,
  -- which plays the door-opening sound and walks them out of a doorway on
  -- arrival.  The cartridge rides them instead (SE_ESCALATOR,
  -- StartEscalatorWarp): no door, and the player simply arrives.
  local escalator = self.map.escalatorAt
                    and self.map:escalatorAt(self.player.cellX, self.player.cellY)
  if escalator then
    -- Sound.play resolves through the dataset and is a no-op where the name
    -- is not in it, so this is the escalator's sound where the import has one
    -- and silence where it does not -- which is still right, because the
    -- thing that was WRONG is the door sound this arm replaces.
    require("src.core.Sound").play(Game.data, "Escalator")
    self.arriveWarp = "escalator"
    self.escalatorWay = escalator
    self:startWarpTo(destMap, x, y, facing)
    return
  end
  self.doorWarp = true -- door SFX + PlayerStepOutFromDoor walk-out
  self:startWarpTo(destMap, x, y, facing)
end

-- wDigWarpNumber / wDigMapGroup / wDigMapNumber (EnterMapWarp.SaveDigWarp).
--
-- Gen 2 does NOT send Dig and Escape Rope to the last Pokemon Center the way
-- Gen 1 does -- .DoDig copies this straight into wNextWarp, so you come back
-- out of the door you went in by. It is recorded on the way IN, and only when
-- an outdoor map (TOWN/ROUTE) leads to an indoor one
-- (INDOOR/CAVE/DUNGEON/GATE) -- CheckOutdoorMap / CheckIndoorMap, home/map.asm.
-- Environments are 1-based (constants/map_data_constants.asm `const_def 1`).
local DIG_FROM = { [1] = true, [2] = true }              -- TOWN, ROUTE
local DIG_TO = { [3] = true, [4] = true, [6] = true, [7] = true }
-- "outdoor maps within indoor maps": Dig and Escape Rope must not strand the
-- player on either, so entering from one records nothing.
local DIG_EXCLUDED = { MOUNT_MOON_SQUARE = true, TIN_TOWER_ROOF = true }

function OverworldState:rememberDigWarp(fromMap, x, y, destMap)
  if DIG_EXCLUDED[fromMap] then return end
  local maps = Game.data and Game.data.maps
  local from = maps and maps[fromMap]
  local dest = maps and maps[destMap]
  if not (from and dest) then return end
  if not (DIG_FROM[from.environment] and DIG_TO[dest.environment]) then return end
  self.digWarp = { id = fromMap, x = x, y = y }
  Game.save.digWarp = self.digWarp
end

-- Where Escape Rope / Dig return to, or nil when nothing has been recorded --
-- which is .CheckCanDig's zero test, and means the item cannot be used.
function OverworldState:escapePoint()
  return Game.save.digWarp or self.digWarp
end

-- Remember the outdoor side for LAST_MAP exits (pokered's wLastMap).
function OverworldState:rememberOutdoor(id, x, y)
  self.lastOutdoor = { id = id, x = x, y = y }
  Game.save.lastOutdoor = self.lastOutdoor
end

-- EnterMapWarp.SetSpawn (Gen 2, home/map.asm): stepping OUT of a Pokemon
-- Center interior into a TOWN or ROUTE map records that outdoor map as the
-- blackout spawn, and GetWhiteoutSpawn reads the arrival cell out of
-- SpawnPoints.  Gen 2 never sets the spawn from the nurse herself, so
-- without this the only blackout point a Gold save ever had was the ROM's
-- fallback -- spawn 0, the bedroom in New Bark Town.  Gen 1 has no
-- equivalent (its nurse writes lastHeal directly), and map_scripts.spawns
-- only exists in a Gen 2 cache, so this is inert there.
local GEN2_SPAWN_ENVIRONMENTS = { [1] = true, [2] = true } -- TOWN, ROUTE

function OverworldState:noteGen2Spawn(fromId)
  local pool = Game.data.map_scripts
  local spawns = pool and pool.spawns
  if not (spawns and spawns.centers and spawns.centers[fromId]) then return end
  if not GEN2_SPAWN_ENVIRONMENTS[self.map.def.environment] then return end
  local point = spawns.points and spawns.points[self.map.id]
  if not point then return end
  -- no `outdoor`: a Gen 2 spawn IS the town cell outside the centre door,
  -- so LAST_MAP exits have nothing to re-point at
  Game.save.lastHeal = { map = self.map.id, x = point.x, y = point.y }
end

-- Warp to the last heal point (blackout, ESCAPE ROPE, DIG/TELEPORT).
-- The heal point is usually an interior, so LAST_MAP exits are re-pointed
-- at its remembered town door rather than wherever the player left from.
--
-- opts.arrive = "teleport" for Dig/Teleport/Escape Rope (LeaveMapAnim /
-- EnterMapAnim).  Blackouts omit it: pret HandleBlackOut only
-- GBFadeOutToBlack + PrepareForSpecialWarp + SpecialEnterMap, and never
-- sets BIT_FLY_WARP / BIT_DUNGEON_WARP, so EnterMap never runs EnterMapAnim.
function OverworldState:warpToHealPoint(onDone, opts)
  local heal = self:healPoint()
  self.player.surfing = false
  self:syncSurfingPikachu()
  -- HandleFlyWarpOrDungeonWarp + DisplayPlayerBlackedOutText both clear
  -- BIT_ALWAYS_ON_BIKE (home/overworld.asm / home/text_script.asm)
  self:clearBikeFlags()
  local map, x, y = heal.map, heal.x, heal.y
  local teleport = opts and opts.arrive == "teleport"
  if teleport then
    self.arriveWarp = "teleport"
    -- Dig/Teleport/Escape Rope land OUTSIDE at the last Pokemon Center TOWN
    -- door, like Fly (#196) -- NOT the interior heal cell a blackout returns
    -- to.  pret routes escape-warp and blackout both through wLastBlackoutMap
    -- (both appear inside in front of the nurse), but this port has decided
    -- the escape-warp destination is the town PC door.  Prefer the canonical
    -- Fly landing (field.flyWarps, one tile south of the PC door warp), else
    -- the remembered outdoor door cell; fall back to the interior heal cell
    -- only for an old save with no recorded outdoor.
    local out = heal.outdoor
    if out then
      local fw = (Game.data.field.flyWarps or {})[out.id]
      map = out.id
      x = fw and fw.x or out.x
      y = fw and fw.y or out.y
    end
  end
  self:startWarpTo(map, x, y, "down", onDone)
  -- Blackouts land at the interior heal cell, so re-point LAST_MAP exits at
  -- the remembered town door.  The teleport branch already lands ON that
  -- outdoor map, so startWarpTo remembers it on the next exit; re-pointing
  -- here would wrongly steer exits away from where the player now stands.
  if heal.outdoor and not teleport then
    self:rememberOutdoor(heal.outdoor.id, heal.outdoor.x, heal.outdoor.y)
  end
end

-- .DoDig's own warp: back out through the recorded entrance. Landing on that
-- warp tile is safe -- startWarpTo leaves the warp you arrive ON inert until
-- you physically step off it, which is what stops a door bouncing you back.
function OverworldState:warpToEscapePoint(onDone)
  local point = self:escapePoint()
  if not point then
    if onDone then onDone() end
    return
  end
  self.player.surfing = false
  self:syncSurfingPikachu()
  self:clearBikeFlags()
  -- DOOR arrival, not teleport.  The recorded point IS the entrance cell, so
  -- warping to it alone leaves the player standing IN the cave mouth.  The
  -- script ends `newloadmap MAPSETUP_DOOR` (engine/events/overworld.asm:859) --
  -- the same setup a door warp uses -- and that is what steps the player out of
  -- the opening.  Gen2IsDoorway already counts $7B, the cave mouth, alongside
  -- $71, the building door, so PlayerStepOutFromDoor fires for both and obeys
  -- collision on the way.
  --
  -- Deliberately NOT also arriveWarp = "teleport": that is Gen 1's spin-down,
  -- and stacking it here would play two arrival sounds over each other. The
  -- cartridge's own arrival is `return_dig` -- the player emerging from the
  -- ground -- which this port has no animation for either way.
  self.doorWarp = true
  self:startWarpTo(point.id, point.x, point.y, "down", onDone)
end

-- opts.keepMusic: scripted warps mid-cutscene keep the current song
-- playing across the map change, like BIT_NO_MAP_MUSIC (wStatusFlags7)
-- does for the Oak escort (engine/overworld/auto_movement.asm
-- PalletMovementScript_OakMoveLeft sets it; scripts/OaksLab.asm
-- OaksLabFollowedOakScript clears it and calls PlayDefaultMusic).
function OverworldState:startWarpTo(mapId, x, y, facing, onDone, opts)
  -- ANY transition off an outdoor map remembers the outdoor side, so
  -- scripted warps (the Oak walk-in) keep LAST_MAP exits working.
  -- CheckIfInOutsideMap (home/overworld.asm) treats PLATEAU (Route 23 /
  -- Indigo Plateau) as outside too, alongside OVERWORLD -- without it,
  -- LAST_MAP exits taken off Route 23/Indigo Plateau (the Route 22 Gate
  -- back door, the Indigo Plateau lobby doors) resolve against a stale
  -- remembered map instead.
  if Map.isOutside(self.map.def, FieldDefaults.field(Game.data, "outsideTilesets"))
     and mapId ~= self.map.id then
    self:rememberOutdoor(self.map.id, self.player.cellX, self.player.cellY)
  end
  self.transitioning = true
  local doorWarp = self.doorWarp
  self.doorWarp = nil
  local arriveWarp = self.arriveWarp
  self.arriveWarp = nil
  local fromId = self.map.id
  Game.stack:push(Transition.new(Game, function()
    self:setMap(mapId, x, y, facing or "down", opts)
    self:noteGen2Spawn(fromId)
    -- The warp we land ON stays inert for the completed-step check until we
    -- physically step off it, so a warp whose destination cell is itself a
    -- warp cannot bounce us straight back (elevator cars, stacked stair/door
    -- mats).  BIT_STANDING_ON_WARP is deliberately NOT touched here:
    -- ClearVariablesOnEnterMap leaves wMovementFlags alone, so the flag the
    -- departing tile set rides through the warp (issue #378).
    self.warpEntryCell = { x = x, y = y }
    -- Fly/Teleport/Dig/Escape-Rope landings poof the player back in
    -- (player_animations.asm EnterMapAnim).  Blackouts and ordinary
    -- door warps never take this branch.
    if arriveWarp == "fly" then
      require("src.core.Sound").play(Game.data, "Fly")
    elseif arriveWarp == "teleport" then
      require("src.core.Sound").play(Game.data, "Teleport_Enter1")
      -- ENTER_2 caps the spin-down a moment later
      self.delaySfx = { frames = 40, key = "Teleport_Enter2" }
      -- the sprite spins down into place (EnterMapAnim
      -- PlayerSpinWhileMovingDown), not just the SFX
      self.player.spinning = true
      self.player.spinTimer = 0
      self.player.spinFrames = 48
      self.player.spinTotal = 48
      self.player.spinDrop = true
    end
    if doorWarp then
      local outdoor = Map.isOutdoor(self.map.def)
      require("src.core.Sound").play(Game.data,
                                     outdoor and "Go_Outside" or "Go_Inside")
      -- PlayerStepOutFromDoor (engine/overworld/auto_movement.asm): any
      -- warp that lands on a door tile auto-steps south once, indoor or
      -- outdoor. Auto-walk leaves the mat, so the arrival disable
      -- (warpEntryCell) is unnecessary -- and would let you stand on the
      -- door without re-entering if you hold back into it.
      -- The walk-out is a simulated d-pad press (wSimulatedJoypadStates),
      -- not a forced move, so it obeys collision: on a landing with a
      -- solid cell south of the door (the mansion stair landings back
      -- onto shelves) the step bumps and the player stays on the door,
      -- arrival disable intact, instead of clipping into the wall.
      if self.map:isDoorTileCell(self.player.cellX, self.player.cellY) then
        if Collision.canMove(self.map, self.entities, self.player, "down") then
          -- THE ARRIVAL GUARD STAYS UP while the walk-out runs.
          --
          -- It used to be dropped here, on the reasoning that the auto-walk
          -- leaves the mat by itself so nothing can re-fire.  That held only
          -- while this branch was unreachable.  The moment Gen 3 gained a
          -- door list and started taking it, the player was standing ON a
          -- live warp with the guard down for the frames the step takes --
          -- and stepping off a door onto the door's own cell is exactly what
          -- the guard exists to stop.  It clears positionally the moment the
          -- player is somewhere else, which is what the walk does.
          self:scriptMove(self.player, "down", 1)
        else
          self.player.facing = "down"
        end
      end
    end
  end, function()
    self.transitioning = false
    if onDone then onDone() end
  end))
end

-- Re-read a map record after its data changed (WorldAPI:invalidateMap,
-- dev-mode hot reload).  The neighbors go too: their strips render the
-- same tileset.  When the active map is the one that changed, the player
-- is clamped back in bounds, the NPC pool is reused so runtime handles
-- survive, and the tile-pair table is re-read.  keepMusic: a reload is not a
-- map entry.  Its counterpart ReloadMapData (home/reload_tiles.asm) only
-- re-reads the map view and the tileset tile patterns after the Pokedex /
-- start menu / PC clobbered VRAM; map music starts from LoadMapData alone
-- (home/overworld.asm, gated on BIT_NO_MAP_MUSIC).  Whatever is playing
-- belongs to the state on top, so a COLORS cycle during a battle
-- (PaletteFX.setMode reloads the live map to rebuild its baked atlas) must
-- not drop the route theme over the battle song (#484).  The out-of-bounds
-- fallback below is a real map change and keeps its map music.
function OverworldState:reloadMap(mapId, reason)
  MapLoader.invalidate(mapId)
  for _, nb in ipairs(self.neighbors or {}) do MapLoader.invalidate(nb.map.id) end
  if self.map and self.map.id == mapId then
    local p = self.player
    local x, y, facing = p.cellX, p.cellY, p.facing
    Collision.load(Game.data)
    self:setMap(mapId, x, y, facing,
                { seamless = true, via = "reload", keepMusic = true })
    if not self.map:inBounds(x, y) then
      local heal = self:healPoint()
      Logger.warn("map %s reloaded out from under the player; sending to %s",
                  mapId, tostring(heal.map))
      self:setMap(heal.map, heal.x, heal.y, "down", { via = "reload" })
    end
  end
  Runtime.emit("map.reloaded", { mapId = mapId, reason = reason or "invalidate" })
end

-- Append a runtime object to a map record and, when that map is live,
-- instantiate it through the shared pool so it crosses seams like an
-- imported object.  Runtime objects are never serialized into map data.
function OverworldState:addRuntimeObject(mapId, objDef, owner)
  local def = Game.data.maps[mapId]
  if not def then return nil, "unknown map: " .. tostring(mapId) end
  def.objects = def.objects or {}
  local index = 0
  for _, obj in ipairs(def.objects) do
    if (obj.index or 0) > index then index = obj.index end
  end
  objDef.index = index + 1
  objDef.runtime = true
  objDef.owner = owner
  table.insert(def.objects, objDef)
  local npcId = mapId .. "_obj_" .. objDef.index
  if self.map and self.map.id == mapId and self.npcPool then
    local npc = pooledNPC(self.npcPool, Game.data, mapId, objDef)
    npc.frozen = false
    table.insert(self.npcs, npc)
    table.insert(self.entities, npc)
  end
  return npcId
end

-- Drop a runtime object again; imported objects are refused, and so is
-- another mod's.
function OverworldState:removeRuntimeObject(npcId, owner)
  for mapId, def in pairs(Game.data.maps) do
    for i, obj in ipairs(def.objects or {}) do
      if obj.runtime and mapId .. "_obj_" .. obj.index == npcId then
        if owner ~= nil and obj.owner ~= owner then
          return nil, "not owned by " .. tostring(owner)
        end
        table.remove(def.objects, i)
        if self.npcPool then self.npcPool[npcId] = nil end
        for _, list in ipairs({ self.npcs or {}, self.entities or {} }) do
          for j = #list, 1, -1 do
            if list[j].id == npcId then table.remove(list, j) end
          end
        end
        return true
      end
    end
  end
  return nil, "no runtime object " .. tostring(npcId)
end

-- REDRAW A MAP WHOSE BLOCKS A TERRAIN EFFECT JUST CHANGED.
--
-- Reported from play: "the ice in the sootopolis gym isnt cracking when
-- stepped on", and before that "walking in the grass doesn't change the
-- colour like it's supposed to".  Both were this.
--
-- A Gen 3 renderer bakes the visible window into a sprite batch and only
-- rebuilds it when something says so -- which is why the cartridge's own
-- scripts change a metatile with `setmetatile` and then call
-- DrawWholeMapView.  Every terrain effect in Hoenn wrote its new block
-- straight into the map and never asked for the redraw: the ice cracked, the
-- ash swept, the log sank and the plank sagged, all of it recorded and none
-- of it drawn until something else happened to rebuild the window (usually
-- leaving the room).  A puzzle you cannot see the state of is a puzzle you
-- cannot solve.
--
-- Takes the map because two of the callers are putting a cell back on a map
-- the player has already walked off.

-- ---------------------------------------------------------------------------
-- HOENN'S TALL GRASS IS A SPRITE, NOT A LAYER.
--
-- Reported from play: "grass isnt hiding my playing sprite behind it".  On a
-- Game Boy map the trick is a BG overdraw -- drawCellBottom redraws the
-- cell's lower tile row over the character's feet -- and on Gen 3 that call
-- is a silent no-op, because a Gen 3 renderer has no 8x8 tile atlas to draw
-- it out of.  Every Gen 3 metatile's SECOND layer is already drawn above the
-- sprites, which is what puts a character behind a treetop, so the obvious
-- guess is that the grass belongs there -- and it does not: metatile 13, the
-- ordinary tall grass every route in Hoenn is made of, is 256 opaque pixels
-- on the bottom layer and ZERO on the top.  There is nothing there to hide
-- behind.
--
-- Emerald draws the blades as a FIELD EFFECT: a sixteen-square sprite spawned
-- on the cell, drawn over whoever is standing in it, and taken away when they
-- leave.  The art and its palette are read off the cartridge's field-effect
-- template table (constants.gen3TallGrass); the five frames are the rustle,
-- and the last of them is the resting tuft that covers a standing player's
-- legs.
-- ---------------------------------------------------------------------------
function OverworldState:drawGen3Grass(cx, cy, camX, camY, frame)
  local record = Game.data and Game.data.constants
                 and Game.data.constants.gen3TallGrass
  if type(record) ~= "table" or not record.image then return false end
  if self.grassImage == nil or self.grassPath ~= record.image then
    local ok, img = pcall(require("src.render.Assets").image, record.image)
    self.grassImage = (ok and img) or false
    self.grassPath = record.image
    self.grassQuads = nil
  end
  local img = self.grassImage
  if not (img and img.getWidth) then return false end
  local fw = tonumber(record.frameWidth) or 16
  local fh = tonumber(record.frameHeight) or 16
  local count = math.max(1, tonumber(record.frames) or 1)
  frame = math.floor(tonumber(frame) or (count - 1))
  if frame < 0 then frame = 0 elseif frame > count - 1 then frame = count - 1 end
  self.grassQuads = self.grassQuads or {}
  local quad = self.grassQuads[frame]
  if not quad then
    quad = love.graphics.newQuad(0, frame * fh, fw, fh,
                                 img:getWidth(), img:getHeight())
    self.grassQuads[frame] = quad
  end
  love.graphics.setColor(1, 1, 1, 1)
  -- the cell's own pixel origin: a 16-square effect over a 16-square cell,
  -- with no sprite offsets, because it is not a character
  love.graphics.draw(img, quad, cx * 16 - math.floor(camX),
                     cy * 16 - math.floor(camY))
  return true
end

-- Which of the rustle's frames a cell shows.  The cell being LEFT (or stood
-- in) holds the last one, which is the settled tuft; the cell being stepped
-- INTO plays the rustle across the step, which is what the cartridge's
-- animation does to the grass you are pushing through.
function OverworldState.grassFrameFor(count, e, entering)
  count = math.max(1, math.floor(tonumber(count) or 1))
  if not entering then return count - 1 end
  local span = e and (e.stepFramesCur or e.stepFrames) or 16
  span = tonumber(span) or 16
  if span <= 0 then return count - 1 end
  local t = (tonumber(e and e.progress) or 0) / span
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local frame = math.floor(t * count)
  if frame > count - 1 then frame = count - 1 end
  return frame
end

function OverworldState:gen3GrassFrame(e, entering)
  local record = Game.data and Game.data.constants
                 and Game.data.constants.gen3TallGrass
  return OverworldState.grassFrameFor(record and record.frames or 1, e,
                                      entering)
end

function OverworldState:redrawBlocks(map)
  map = map or self.map
  local renderer = map and map.renderer
  if renderer and renderer.rebuild then renderer:rebuild() end
  -- a caller that redrew for itself has answered the dirty flag too, so
  -- update() does not do the same rebuild again on the next frame
  if map then map.blocksDirty = nil end
end

-- Replace a map block (Victory Road barriers, Cut trees) and redraw.
function OverworldState:replaceBlock(bx, by, block)
  self.map:setBlock(bx, by, block)
  self.map.renderer:rebuild()
  self.map.blocksDirty = nil
  Runtime.emit("world.block_replaced",
    { mapId = self.map.id, bx = bx, by = by, block = block })
end

-- A map's `variablesprite` callback usually runs after its objects have been
-- built, so re-resolve everything still pointing at the slot it just filled.
-- Only FIVE of the thirteen wVariableSprites slots reach here as SPRITE_VAR_nn:
-- the extractor names the rest after what they hold (SPRITE_WEIRD_TREE is slot
-- 4, SPRITE_OLIVINE_RIVAL 5, SPRITE_AZALEA_ROCKET 6, SPRITE_COPYCAT 11,
-- SPRITE_JANINE_IMPERSONATOR 12 -- src/import/RomExtractorGen2.lua's
-- GEN2_SPRITE_ID_OVERRIDES).  Matching on the SPRITE_VAR_nn spelling alone
-- therefore missed every named slot, which is every slot a script actually
-- reassigns mid-scene: `variablesprite SPRITE_WEIRD_TREE, SPRITE_TWIN` after
-- Sudowoodo, the Azalea and Olivine rival swaps, Copycat.  Ask NPC.lua which
-- slot an id means instead of re-deriving it here, so the two cannot drift.
function OverworldState:refreshVariableSprite(slot)
  local NPC = require("src.world.NPC")
  local seen = {}
  local function refresh(npc)
    if not (npc and npc.def and npc.def.sprite) or seen[npc] then return end
    if NPC.variableSpriteSlot(npc.def.sprite) == slot then
      seen[npc] = true
      npc:refreshSprite(Game.data)
    end
  end
  for _, npc in pairs(self.npcPool or {}) do refresh(npc) end
  -- npcPool is the session's cache and normally a superset of the live list,
  -- but an NPC built outside it (the Gen1 toggleObject path) is only in npcs.
  for _, npc in ipairs(self.npcs or {}) do refresh(npc) end
end

-- -------------------------------------------------------------------------
-- scripted movement
-- -------------------------------------------------------------------------

-- IS THE QUEUE BEING TORN DOWN?  (see releaseScriptMoves)
--
-- A file-local rather than a method, and declared ABOVE the three functions
-- that use it, for two reasons that both bite: the queue functions are
-- BORROWED -- a headless caller assigns `ow.scriptMove =
-- OverworldState.scriptMove` onto a plain table, where a `self:` call would
-- find nothing -- and a `local` in Lua is only in scope below its own
-- declaration, so one written under its callers would read as a global and
-- come back nil.
local function droppingMove(self, onDone)
  if not self.droppingScriptMoves then return false end
  self.dropDepth = (self.dropDepth or 0) + 1
  -- a chain cannot be longer than a movement script, and a movement script is
  -- tens of bytes; the cap is only here so a cycle cannot spin
  if self.dropDepth <= 512 and onDone then pcall(onDone) end
  return true
end

function OverworldState:scriptMove(entity, dir, tiles, onDone, keepFacing)
  if droppingMove(self, onDone) then return end
  table.insert(self.scriptMoves, {
    entity = entity, dir = dir, remaining = tiles, onDone = onDone,
    keepFacing = keepFacing or nil,
  })
end

-- A step-in-place beat: the entity plays one walk-cycle animation (16
-- frames) without translating, keeping its current facing.  Ports the
-- NPC_CHANGE_FACING movement byte (engine/overworld/movement.asm
-- ChangeFacingDirection -> zero-delta TryWalking), used for Oak marching
-- on the lab door mat at the tail of RLEList_ProfOakWalkToLab.
-- A PAUSE inside a scripted movement, on the same queue as the steps around
-- it. Gen 3 movement scripts are 12% delay bytes -- they are how a cutscene
-- gets its timing, the beat where one actor waits for another to arrive --
-- and a delay that BLOCKS the script runner would serialise the two walks it
-- is there to separate. This one advances on the queue like a step, so the
-- other actor keeps moving through it.
function OverworldState:scriptPause(entity, frames, onDone)
  if droppingMove(self, onDone) then return end
  table.insert(self.scriptMoves, {
    entity = entity, pause = math.max(1, math.floor(frames or 1)),
    remaining = 0, onDone = onDone,
  })
end

function OverworldState:marchInPlace(entity, onDone)
  if droppingMove(self, onDone) then return end
  table.insert(self.scriptMoves, {
    entity = entity, inPlace = true, remaining = 1, onDone = onDone,
  })
end

-- ---------------------------------------------------------------------------
-- A WARP ENDS EVERY WALK THAT WAS IN FLIGHT.
--
-- The cartridge does not have to say so: a map load rebuilds the object
-- events, and whatever they were part-way through simply stops being. Here
-- the queue outlives the map, and a queue that outlives its map is the worst
-- failure shape this file has -- `#scriptMoves > 0` gates every input frame,
-- so one stranded entry locks the player where they stand with nothing on
-- screen to say why.
--
-- Retiring them is not enough on its own: each move's `onDone` is the next
-- link of a movement script's chain, and dropping the chain would leave the
-- `waitmovement` behind it waiting for ever. So the chain is DRAINED instead
-- -- every onDone runs, and `droppingMove` makes each new step retire
-- immediately rather than joining the queue, so the whole movement runs out
-- to its end (which marks its state done and lets the wait resume) without a
-- single step landing on the new map.

function OverworldState:releaseScriptMoves(newMapId)
  -- the first setMap of a session runs before the queue exists
  if type(self.scriptMoves) ~= "table" then return false end
  local queued = #self.scriptMoves
  if queued == 0 then return false end
  self.droppingScriptMoves = true
  self.dropDepth = 0
  local guard = 0
  while #self.scriptMoves > 0 and guard < 512 do
    guard = guard + 1
    local mv = table.remove(self.scriptMoves, 1)
    local e = mv.entity
    -- stop the sprite where it is; the player's cell is about to be assigned
    -- by setMap anyway, and an NPC's belongs to a map that is going away
    if e then
      e.moving = false
      e.marching = false
      e.targetX, e.targetY = nil, nil
    end
    if mv.onDone then pcall(mv.onDone) end
  end
  self.droppingScriptMoves = nil
  self.dropDepth = nil
  self.scriptMoves = {}
  Logger.debug("%d scripted move(s) were still in flight when the map became "
               .. "%s -- the warp ends them, as a map load does on the "
               .. "cartridge", queued, tostring(newMapId))
  return true
end

-- Advance scripted moves in two phases so a chained step (a new move
-- queued by a completing move's onDone) begins the SAME frame the
-- previous one ends -- back-to-back 16-frame tiles like the GB's
-- simulated-joypad / NPC scripted movement, with no idle frame between
-- tiles.  Phase 1 retires finished moves (which may chain new ones);
-- phase 2 then starts every not-yet-moving move.
-- A MOVE WHOSE WALKER IS GONE MUST STILL END.
--
-- `#self.scriptMoves > 0` is one of the conditions that says "a script owns
-- the map": it gates every input frame AND drainPendingScripts.  So a single
-- queued move that can never retire does not slow anything down -- it locks
-- the player where they stand, with no text box, no cutscene and nothing on
-- screen to say why.  That is the worst failure shape this file has.
--
-- Two ways a move gets stranded, and the loop below could retire neither:
--
--   * the entity is nil.  The retirement test reads `not (mv.entity and
--     mv.entity.moving)`, which is TRUE for a nil entity -- but it is paired
--     with `mv.remaining <= 0`, and a fresh move has steps left.  The starting
--     loop then skips it too (both its arms begin `if e and ...`).  Never
--     retired, never stepped.
--
--   * the entity was DESPAWNED mid-step.  syncEventFlagObjects removes an
--     object from `npcs` and `entities` the moment a script hides it, and a
--     cutscene routinely hides someone who is walking.  Nothing then updates
--     that sprite, so `moving` stays true for ever and the first test never
--     passes.
--
-- The cartridge has no equivalent: a despawned object's movement simply stops
-- being anyone's business.  So an orphaned move is retired HERE and its
-- onDone still fires -- which is what lets the chain behind it finish, the
-- `waitmovement` that was waiting on it resume, and the queue drain.
local function moveWalkerIsLive(self, mv)
  local e = mv.entity
  if e == nil then return false end
  if e == self.player then return true end
  -- a pause or an in-place march belongs to whoever queued it and does not
  -- need a live sprite to count frames down
  if mv.pause or mv.inPlace then return true end
  for _, npc in ipairs(self.npcs or {}) do
    if npc == e then return true end
  end
  return false
end

function OverworldState:updateScriptMoves()
  local i = 1
  while i <= #self.scriptMoves do
    local mv = self.scriptMoves[i]
    if not moveWalkerIsLive(self, mv) then
      -- said out loud: this is a scene that did something the port did not
      -- model, and silence here is what made it look like a frozen game
      Logger.warn("scripted move on %s has no live walker (%d step(s) left) "
                    .. "-- retiring it so the queue can drain",
                  tostring(self.map and self.map.id), mv.remaining or 0)
      table.remove(self.scriptMoves, i)
      if mv.onDone then mv.onDone() end
    elseif mv.pause then
      -- ticks only while its own entity is standing still, so a pause queued
      -- behind a walk does not start counting until the walk is done
      if not (mv.entity and mv.entity.moving) then mv.pause = mv.pause - 1 end
      if mv.pause <= 0 then
        table.remove(self.scriptMoves, i)
        if mv.onDone then mv.onDone() end
      else
        i = i + 1
      end
    elseif not (mv.entity and mv.entity.moving) and mv.remaining <= 0 then
      table.remove(self.scriptMoves, i)
      if mv.onDone then mv.onDone() end
      -- don't advance i: a move chained by onDone may now sit at i
    else
      i = i + 1
    end
  end
  for _, mv in ipairs(self.scriptMoves) do
    local e = mv.entity
    -- an entity that has lost its grid position (rebuilt across a map load
    -- while its steps were still queued) is skipped rather than fed to
    -- Collision.target, which would arithmetic on the nil
    if e and not e.moving and mv.remaining > 0 and not (mv.inPlace or e.cellX) then
      -- nothing to walk: retire it so the chain's onDone still fires and the
      -- cutscene does not sit on a move that can never complete
      mv.remaining = 0
    elseif e and not e.moving and mv.remaining > 0 then
      if mv.inPlace then
        e.moving = true
        e.marching = true
        e.progress = 0
      else
        -- facingDirectionLocked (pret): a forced move can carry the walker
        -- without turning them.  The muddy slope is the one that needs it --
        -- you are pushed back down the hill still facing up it, which is what
        -- makes a failed climb read as a failed climb.
        if not mv.keepFacing then e.facing = mv.dir end
        -- A SCRIPTED STEP IS A WALK, whatever the player was doing a moment
        -- ago.
        --
        -- Reported from play: "when following wally my character doesnt fully
        -- get behind him when he turns in town".  A cutscene walks two people
        -- with a pair of applymovements and then `waitmovement 0`, which
        -- waits on the LAST of them -- so the two only stay together while
        -- they move at the same rate.  The player's rate is stepFramesCur,
        -- and nothing reset it between a free step and a scripted one: with
        -- the running shoes on, the player took eight frames a tile against
        -- Wally's sixteen, finished the leg first, and the script moved on
        -- while he was still walking.  The cartridge's movement actions carry
        -- their own speed and the shoes are not part of it.
        if e == self.player then
          -- the walker's own baseline, which Player takes off the dataset
          -- when it is built; the literal is only for a headless stub
          e.stepFramesCur = e.stepFrames or 16
          e.running = false
        end
        local tx, ty = Collision.target(e.cellX, e.cellY, mv.dir)
        e.targetX, e.targetY = tx, ty
        e.moving = true
        e.progress = 0
      end
      mv.remaining = mv.remaining - 1
    end
  end
  -- march_in_place toggles: re-arm the in-place cycle each time it ends.
  -- Not a scriptMove, so an ambient marcher never trips the input lockout.
  for entity in pairs(self.marchers or {}) do
    if not entity.moving then
      entity.moving = true
      entity.marching = true
      entity.progress = 0
    end
  end
end

-- -------------------------------------------------------------------------
-- draw / save
-- -------------------------------------------------------------------------

function OverworldState:draw()
  Game.renderer:beginWorldPass()
  self:drawWorld()
  Game.renderer:endWorldPass()
  self:drawUI()
end

-- The emote sheet is OBJ art (engine/overworld/emotion_bubbles.asm builds the
-- bubble out of shadow OAM), so it renders through OBP0, and GBPalNormal
-- (home/palettes.asm:20-26 `ld a, %11010000 ; 3100 / ldh [rOBP0], a`) holds
-- OBP0 at "3100": OBJ color 1 shows as shade 0, color 2 as shade 1, color 3
-- as shade 3.  Blitting the raw sheet skipped that lift and left the "!"
-- bubble's interior (color 1) at DMG shade 1 grey instead of white (#505).
-- Same CPU-remap bake as SpriteRenderer.getObpImage and PartyMenu's obpIcon,
-- and it resolves through Assets so a mod's emotes.png override still wins.
-- Color 0's alpha (a tRNS entry on the extracted png) is what keys the
-- bubble's corners out, so carry it through untouched.
local function obpEmoteImage(path)
  if not (love.image and love.image.newImageData) then
    return love.graphics.newImage(Assets.resolve(path)) -- headless stub
  end
  local id = Assets.imageData(path)
  id:mapPixel(function(_, _, r, _, _, a)
    local v = 0
    if r > 0.5 then v = 1               -- OBJ colors 0 and 1 -> shade 0
    elseif r > 0.17 then v = 170 / 255  -- OBJ color 2 -> shade 1
    end                                 -- OBJ color 3 -> shade 3
    return v, v, v, a
  end)
  return love.graphics.newImage(id)
end

-- The SGB palette a tilt-mode billboard at flat foot (fx, fy) sits under.
-- World zones are rectangles in flat world-canvas space (the current map's
-- base fills the view; neighbour maps stack on top), so the last zone that
-- contains the foot wins -- the same later-zone-on-top priority the flat
-- blit's scissoring gives.  nil when there are no zones (headless / stale
-- palettes), which leaves the billboard uncolorized.
local function zoneColorsAt(zones, fx, fy)
  if not zones then return nil end
  for i = #zones, 1, -1 do
    local z = zones[i]
    if fx >= z.x and fx < z.x + z.w and fy >= z.y and fy < z.y + z.h then
      return z.colors
    end
  end
  return zones[1] and zones[1].colors or nil
end

-- Draw a standing thing as an upright billboard (tilt mode only).  ONLY the
-- ground tilts: a standing thing draws UPRIGHT and UNSCALED -- pixel-identical
-- to flat mode (same crisp nearest-neighbour art, nothing sheared, resized or
-- clipped).  The single thing tilt changes about it is its on-screen anchor:
-- its foot (fx, fy -- the baseline centre of its cell, in world-canvas
-- pixels) moves to where that ground point projects, Tilt.groundPoint(fx,fy).
-- depthScale is deliberately ignored for sizing.  `colors` is the SGB palette
-- of the map the foot stands on: the flat path colorizes the whole world
-- canvas at blit time, but the upright canvas composites with no zone pass,
-- so each billboard carries its own colorization here.  `keyed` selects the
-- color-0-keyed palette variant (tall-grass feet overdraw, which must show the
-- sprite through the tile's white gaps) over the plain one (sprites, FX
-- overlays).  drawFn issues the actual draws in flat world-canvas coordinates;
-- the transform just slides them from the flat foot onto the projected anchor.
function OverworldState:billboard(fx, fy, vw, vh, colors, keyed, drawFn)
  local sx, sy = Tilt.groundPoint(fx, fy, vw, vh)
  local shader = colors and (keyed and PaletteFX.keyedShader()
                             or PaletteFX.shader()) or nil
  if shader then
    PaletteFX.sendColors(shader, colors)
    love.graphics.setShader(shader)
  end
  love.graphics.push()
  love.graphics.translate(sx - fx, sy - fy)
  drawFn()
  love.graphics.pop()
  if shader then love.graphics.setShader() end
end

-- THE TILESET ATLAS A MAP DRAWS FROM, for a mod that renders the world itself.
--
-- A 3D world pipeline cannot use the finished 2D map canvas: voxel geometry
-- samples the tileset SHEET per face, with its own UVs. So a mod that replaces
-- the world pass needs the same sheet the flat renderer builds its quads from,
-- and the tileset record that says how it is laid out.
--
-- The name is the one Gen1Recomp published and mods were written against
-- (`World:atlasFor`). Without it STADIUM2_OVERWORLD_MODELS fails at
-- `attachRenderer` with "Gold World:atlasFor is unavailable", its renderFrame
-- returns no canvas, and the engine quietly falls back to the flat draw --
-- which reads, from the player's side, as "the 3D world just does not turn on"
-- with an empty log and every option switched on. Providing it is cheap and it
-- is the seam the contract already assumed.
--
-- Returns the RAW sheet, deliberately, plus the tileset record:
--   * a caller doing its own colour work (Gen 2 art is four-shade source, and
--     the palette is chosen per 8x8 tile at bake time) needs the unbaked
--     pixels, and re-baking an already-baked atlas would double-apply it;
--   * `map.renderer.image` -- the baked one -- stays available to anything
--     that wants what the 2D path actually painted.
--
-- `mapDef` is a map DEFINITION (`Game.data.maps.CERULEAN_CITY`), matched
-- against the current map and its loaded neighbours first so the live tileset
-- record (with any runtime normalisation on it) wins; a def for a map that is
-- not resident falls back to the static tileset table.
-- Returns nil when the sheet cannot be resolved -- never raises, because this
-- runs inside a mod's render callback.
function OverworldState:atlasFor(mapDef)
  if type(mapDef) ~= "table" then return nil end

  local map
  if self.map and self.map.def == mapDef then
    map = self.map
  else
    for _, nb in ipairs(self.neighbors or {}) do
      if nb.map and nb.map.def == mapDef then map = nb.map break end
    end
  end

  local tileset = map and map.tileset
  if not tileset then
    local data = Game and Game.data
    local tilesets = data and data.tilesets
    tileset = tilesets and mapDef.tileset and tilesets[mapDef.tileset] or nil
  end

  -- THE GEN 3 ARM.  A Gen 3 map has no tileset sheet, so the check below --
  -- `tileset.image` -- answered nil for every map in Hoenn, and by this
  -- contract's own rule a nil atlas is indistinguishable from "the mod chose
  -- not to draw": the 3D world drew NOTHING, silently, with every option on
  -- and an empty log.
  --
  -- The unit is different too, and that is the part a caller must not have to
  -- guess.  A Gen 1/Gen 2 atlas is 8x8 TILES and the map addresses it with
  -- tile ids out of a block; a Gen 3 pair bakes to 16x16 CELLS addressed by
  -- METATILE id, in TWO sheets -- the half the player walks in front of and
  -- the half they walk behind.  So the Gen 3 answer carries a descriptor
  -- saying so (third return), and the view it hands back as the tileset
  -- states `atlasUnit = "cell"` rather than pretending to be a tile sheet.
  local gen3 = self:gen3WorldFor(mapDef, map, tileset)
  if gen3 then return gen3.bottom, gen3.tileset, gen3 end

  if not (tileset and tileset.image) then return nil end

  local ok, image = pcall(Assets.image, tileset.image)
  if not (ok and image) then return nil end
  return image, tileset
end

-- ---------------------------------------------------------------------------
-- THE GEN 3 WORLD DESCRIPTOR, for a mod that renders the world itself.
--
-- Everything a 3D pipeline needs to build Hoenn as geometry, in one table, and
-- deliberately more than `atlasFor` alone can carry -- because Gen 3 hands a
-- renderer three things Gen 1 and Gen 2 never had, and all three are the
-- difference between a diorama that guesses and one that knows:
--
--   * a BEHAVIOUR byte per metatile.  Gen 2 stores a collision class and the
--     art has to be read to find out what a cell IS; Gen 3 says outright that
--     this cell is tall grass, deep water, a jumpable ledge facing south, a
--     door, a counter, a bookshelf, ice, a log raft.
--   * a LAYER TYPE per metatile, which is the cartridge's own answer to "does
--     the player pass in front of this or behind it".  A voxel renderer spends
--     most of its guessing budget on exactly that question.
--   * an ELEVATION per CELL.  Gen 2 records no height at all -- a terrace and
--     the grass below it are both collision $00, which is why the Johto
--     profile has to infer terraces from floor art.  Gen 3 gives the Y axis
--     directly, and it is what makes Route 110's cycling road stand over the
--     sea rather than lie in it.
--
-- Returns nil on Gen 1 and Gen 2, which is how a caller tests for the arm.
-- Never raises: this runs inside a mod's render callback.
-- ---------------------------------------------------------------------------

-- one line per pair, so the branch is stated once rather than every frame
local gen3AtlasLogged = {}

function OverworldState:gen3WorldFor(mapDef, map, tileset)
  if not GameVersion.isGen3() then return nil end
  if type(mapDef) ~= "table" then return nil end

  if map == nil and tileset == nil then
    if self.map and self.map.def == mapDef then
      map = self.map
    else
      for _, nb in ipairs(self.neighbors or {}) do
        if nb.map and nb.map.def == mapDef then map = nb.map break end
      end
    end
    tileset = map and map.tileset
  end
  local data = Game and Game.data
  if not tileset then
    local tilesets = data and data.tilesets
    tileset = tilesets and mapDef.tileset and tilesets[mapDef.tileset] or nil
  end
  -- `blockTiles == 2` is what a Gen 3 pair record says about itself, and the
  -- same test gen3SheetsFor makes.  A Gen 1/Gen 2 tileset never sets it.
  if not (tileset and tonumber(tileset.blockTiles) == 2) then return nil end

  local TileRenderer = require("src.render.TileRenderer")
  local okSheets, record = pcall(TileRenderer.gen3SheetsFor, tileset, data,
                                 data and data.constants
                                 and data.constants.gen3Layout)
  if not (okSheets and record and record.bottom) then
    if not gen3AtlasLogged[tostring(tileset.id)] then
      gen3AtlasLogged[tostring(tileset.id)] = true
      Logger.warn("gen3 atlas: %s has no baked sheets (%s) -- a world mod will "
                  .. "draw nothing on this map", tostring(tileset.id),
                  okSheets and "bake returned nil" or tostring(record))
    end
    return nil
  end

  local tiles = record.tiles
  local cols = require("src.render.Gen3Tiles").SHEET_COLS

  -- A VIEW over the pair record, not the record itself.  Mutating a shared
  -- tileset record from a render callback is how `attachRenderer` once made a
  -- later TileRenderer pick the wrong palette; this leaves the engine's copy
  -- untouched and still reads through to every field it has.
  local view = setmetatable({
    atlasUnit  = "cell",   -- NOT "tile": the quad edge is 16px, not 8px
    cellPixels = 16,
    cellsPerRow = cols,
    tilesPerRow = cols,    -- same number, said in the name an older reader uses
    tileSize   = 16,
    generation = 3,
    metatileCount = record.metatiles,
  }, { __index = tileset })

  local def = map and map.def or mapDef
  local width = tonumber(def and def.width) or 0
  local collisionCells = def and def.collisionCells
  local elevationCells = def and def.elevationCells

  local function indexOf(cx, cy)
    if not (width > 0) or cx < 0 or cy < 0 or cx >= width then return nil end
    local h = tonumber(def.height) or 0
    if cy >= h then return nil end
    return cy * width + cx + 1
  end

  local world = {
    generation = 3,
    tileset    = view,
    pair       = tileset,
    -- the two baked sheets.  `bottom` is what the player walks ON and in front
    -- of; `top` is the half drawn ABOVE them -- treetops, the upper storey of
    -- a house, the far rail of a bridge.  Both are the same size and both are
    -- addressed by the same quad, so one origin serves both.
    bottom     = record.bottom,
    top        = record.top,
    width      = record.width,
    height     = record.height,
    cols       = cols,
    cell       = 16,
    metatiles  = record.metatiles,
  }

  -- Where a metatile sits on either sheet, in pixels.
  function world.originOf(id)
    id = tonumber(id)
    if not id then return 0, 0 end
    return (id % cols) * 16, math.floor(id / cols) * 16
  end

  -- behaviour byte, layer type.  The behaviour byte is Emerald's MB_* value
  -- and the layer type is 0 NORMAL / 1 COVERED / 2 SPLIT.
  function world.attributes(id)
    local ok, b, l = pcall(tiles.attributes, tiles, tonumber(id) or 0)
    if not ok then return 0, 0 end
    return b or 0, l or 0
  end

  function world.behaviourOf(id)
    local b = world.attributes(id)
    return b
  end

  function world.layerTypeOf(id)
    local _, l = world.attributes(id)
    return l
  end

  -- Does this metatile's top half draw above the player?  The cartridge's own
  -- answer, not a guess from the art: layer type COVERED means the top half is
  -- a second course of GROUND (a carpet over a floor, a path over grass) and
  -- belongs under the sprites.
  function world.topIsAbovePlayer(id)
    if type(tiles.topIsAbovePlayer) ~= "function" then
      return world.layerTypeOf(id) ~= 1
    end
    local ok, v = pcall(tiles.topIsAbovePlayer, tiles, tonumber(id) or 0)
    if not ok then return true end
    return v and true or false
  end

  -- The metatile drawn at a CELL.  A Gen 3 metatile IS one 16px cell, so cell
  -- coordinates index the blockdata directly -- no divide by 2.
  function world.metatileAt(cx, cy)
    if map and map.blockAt then
      local ok, id = pcall(map.blockAt, map, cx, cy)
      if ok then return id end
    end
    return nil
  end

  -- 0 = passable.  Gen 3 puts passability on the CELL, not the tileset: a
  -- house front and its doorway are the same metatile.
  function world.collisionAt(cx, cy)
    if not collisionCells then return nil end
    local i = indexOf(cx, cy)
    return i and collisionCells[i] or nil
  end

  -- 0..15.  3 is ordinary ground, 1 is water the player surfs on, 15 is the
  -- "any level" marker a bridge deck carries, and 0 is a transition cell that
  -- matches whatever it is stepped onto.  This is the Y axis Gen 2 never had.
  function world.elevationAt(cx, cy)
    if not elevationCells then return nil end
    local i = indexOf(cx, cy)
    return i and elevationCells[i] or nil
  end

  world.hasElevation = elevationCells ~= nil
  world.hasCollisionCells = collisionCells ~= nil

  if not gen3AtlasLogged[tostring(tileset.id)] then
    gen3AtlasLogged[tostring(tileset.id)] = true
    Logger.info("gen3 atlas: serving %s to world mods -- %d metatiles, "
                .. "two %dx%d sheets, 16px CELL quads (not 8px tiles)",
                tostring(tileset.id), record.metatiles,
                record.width, record.height)
  end

  return world
end

-- Canvas pixels per world pixel, for a mod placing its own camera.
--
-- The companion to `viewW`/`viewH` above and to `atlasFor`: a renderer that
-- replaces the world pass derives the view it must fill as `window / scale`
-- when the state does not publish a view size directly.  Answering nil there
-- leaves it assuming 1, i.e. the whole window in world pixels, and its camera
-- ends up tens of tiles off the player.
--
-- Zoom is folded in, so this tracks the survey/diorama ladder rather than the
-- fixed fit scale.  Returns nil before the renderer exists (headless, boot).
function OverworldState:zoomScale()
  if not (Game and Game.renderer and Game.renderer.fitScale) then return nil end
  local ok, fit = pcall(Game.renderer.fitScale, Game.renderer)
  if not (ok and tonumber(fit)) then return nil end
  local okZoom, scale = pcall(Zoom.scale, fit)
  if not (okZoom and tonumber(scale)) or tonumber(scale) <= 0 then return nil end
  return tonumber(scale)
end

function OverworldState:drawWorld()
  -- Dark-map BG shade shift, armed for the whole frame before anything draws.
  -- home/fade.asm's LoadGBPal writes ONE rBGP for the screen, so terrain, the
  -- characters standing on it and any dialog over them darken together (#322);
  -- Renderer:beginFrame cleared it, so a battle or a full-screen menu -- which
  -- draws with no map beneath it -- stays lit exactly like
  -- init_battle_variables.asm's `ld [wMapPalOffset], a` leaves the original.
  PaletteFX.setShadeMap(self.dark and PaletteFX.DARK_BGP or nil)
  -- advance the water/flower tile animation (runs under dialogs too).
  -- TileRenderer.tick uses wall-clock 60Hz steps so display refresh rate
  -- does not speed or slow the cycle (issue #4).
  require("src.render.TileRenderer").tick()
  -- let the renderer know whether a spinner puzzle is currently sliding
  -- the player, so it can flicker the arrow tiles between the blur and
  -- static graphic (engine/overworld/spinners.asm LoadSpinnerArrowTiles)
  require("src.render.TileRenderer").setSpinning(self.player.spinning)
  local cam = self.camera
  -- ShakeElevator's oscillation (engine/overworld/elevator.asm) writes
  -- hSCY, which scrolls the BG layer only -- tiles bounce while OAM
  -- sprites stay put.  ElevatorShake drives bgShakeY; zero elsewhere.
  local bgY = cam.y + (self.bgShakeY or 0)
  -- border block tiled behind everything the ring doesn't reach
  local vw, vh = Game.renderer:worldViewSize()
  -- ...and publish it, because a mod that owns the world pass has to place its
  -- own camera and needs the size of the view it is filling.  A voxel renderer
  -- centres on `cam.x + viewW / 2`: hand it the WINDOW size instead and the
  -- camera lands half a window -- 32 by 24 tiles here -- past the player, which
  -- is exactly the "the 3D world is not centred on me" report.  These are the
  -- authoritative numbers (they account for letterboxing; window / scale does
  -- not), refreshed every frame because zoom changes them.
  self.viewW, self.viewH = vw, vh
  -- Only things that actually stand (player, NPCs, ghosts, items and the FX
  -- attached to them) leave the ground canvas to billboard upright in a
  -- separate pass anchored to the projected ground (:billboard).  Everything
  -- else -- map tiles, which includes buildings/trees/fences/signs, since in
  -- Gen 1 those are background tiles rather than sprites -- draws into the
  -- one ground canvas exactly as in flat mode and tilts with it as a single
  -- rigid plane (Renderer projects that whole canvas through the mesh when
  -- tilt is active).  So the ground draw calls below never change with tilt;
  -- only the sprite/FX draw path below them branches.  The sorts below only
  -- reorder (no draws), so they run once for both paths.
  -- A render pipeline (src/render/Pipelines.lua) replaces the ground draw
  -- entirely with geometry of its own, so it is decided before tilt and
  -- wins over it.  It falls back to the tilt/flat path whenever it cannot
  -- run this frame -- headless, a driver with no depth canvas, or a mod
  -- that threw -- so no caller ever sees a blank frame.
  local pipelineId = Pipelines.worldPipeline()
  local tilt = (not pipelineId) and Tilt.active()
  -- the pipeline's finished world image, once it has run; nil keeps every
  -- path below on the vanilla flat/tilt draw
  local override
  if not pipelineId then
    self.map.renderer:drawBorderFill(cam.x, bgY, vw, vh)
    self.map.renderer:draw(cam.x, bgY, vw, vh)
    for _, nb in ipairs(self.neighbors) do
      nb.map.renderer:drawMapOnly(cam.x - nb.ox, bgY - nb.oy, vw, vh)
    end
  end
  -- per-billboard SGB palette source; only needed (and only paid for) when
  -- tilting.  nil headless / on stale palettes -> billboards go uncolorized.
  local zones = tilt and self.sgbWorldZones and self:sgbWorldZones() or nil

  -- ghost NPCs on neighbor maps, y-sorted among themselves
  table.sort(self.ghosts,
             function(a, b) return a.npc.py + a.oy < b.npc.py + b.oy end)
  table.sort(self.entities, function(a, b) return a.py < b.py end)

  -- === shared FX draw bodies ==========================================
  -- Each draws at flat world-canvas offsets; the tilt path wraps the
  -- standing ones in an upright billboard, the flat path calls them inline
  -- in their historical order.  (Bodies are byte-identical to the pre-tilt
  -- inline code, so the flat draw sequence is unchanged.)

  -- the Pokémon Center heal machine (PokeCenterOAMData): the monitor
  -- tile over the machine's screen and one ball per healed mon in two
  -- mirrored columns, all blinking during the jingle flash.  The GB
  -- draws it at fixed screen coords with the player's cell BG-aligned
  -- at (64,64); anchoring those coords to where the player stood keeps
  -- the overlay on the machine at any zoom.
  local function fxHeal()
    if not self.healAnim then return end
    local ha = self.healAnim
    -- HOENN'S MACHINE IS NOT AN OAM TABLE.
    --
    -- Everything below this block is the Game Boy's: two 8x8 tiles out of
    -- field.overworldFx.healMachine at coordinates a table in the ROM gives.
    -- Emerald has no such table -- its machine is a field effect whose two
    -- sprites are created by machine code, and where they go is four
    -- immediates INSIDE that code.  extractHealMachine reads them, and the
    -- record it writes carries the positions already measured from the corner
    -- of the player's own cell, so nothing here has to know where the
    -- cartridge's camera puts anybody.
    if self:drawGen3Heal(ha, cam) then return end
    local fxDef = Game.data.field.overworldFx
    if self.healMachineImg == nil and fxDef and fxDef.healMachine then
      local ok, img = pcall(love.graphics.newImage, fxDef.healMachine.path)
      self.healMachineImg = ok and img or false
    end
    local img = self.healMachineImg
    if img then
      if not self.healMachineQuads then
        local w, h = img:getWidth(), img:getHeight()
        self.healMachineQuads = {
          love.graphics.newQuad(0, 0, 8, 8, w, h), -- monitor ($7c)
          love.graphics.newQuad(0, 8, 8, 8, w, h), -- ball ($7d)
        }
      end
      -- The machine carries its OWN four colours.  HealMachineAnim.LoadPalettes
      -- (04:$6434) copies them over OBJ palette 6 before the animation runs --
      -- which is why every row of its OAM table names palette 6 -- and they are
      -- white / light orange / red / black: a Poke Ball.  Nothing was applying
      -- any palette at all, so the sheet drew in the DMG greys it is decoded
      -- in and a Pokemon Center healed with grey balls.
      local def = fxDef and fxDef.healMachine
      local objPal = def and def.gen2ObjPal
      local basePal = (objPal and objPal[1] and objPal) or PaletteFX.GRAYS
      -- the jingle flash recolors the machine sprites in place
      -- (FlashSprite8Times XORs rOBP1; the sprites never disappear):
      -- ha.visible == false is the flashed half of each beat, drawn with
      -- the light/dark shades swapped instead of skipped
      local shader
      if (not ha.visible) or basePal ~= PaletteFX.GRAYS then
        shader = PaletteFX.shader()
        if shader then
          PaletteFX.sendColors(shader, ha.visible and basePal
            or PaletteFX.permute(basePal, HEAL_FLASH_MAP))
          love.graphics.setShader(shader)
        end
      end
      -- TileRenderer windows with -floor(cam), so the overlay must use the
      -- same snap or a fractional camera (odd fill/tilt view sizes) parks
      -- the balls a pixel off the machine tiles
      local ox = ha.px - 64 - math.floor(cam.x)
      local oy = ha.py - 64 - math.floor(cam.y)
      -- Gen2 puts these sprites somewhere else entirely.  Its
      -- HealMachineAnim.PC_ElmsLab_OAM (04:$63BC) has the monitor at x 26/30
      -- and the balls at x 24/32; Gen1's PokeCenterOAMData has the balls at
      -- 40/48.  The extractor reads that OAM table straight off the cartridge
      -- into field.overworldFx.healMachine, so use it where it exists and keep
      -- the Gen1 constants as the fallback -- drawn at Gen1's offsets the
      -- whole overlay sat a full 16px right of the Gen2 machine.
      local monitor = (def and def.monitor) or { { 44, 20 } }
      local balls = (def and def.balls) or HEAL_BALL_XY
      love.graphics.setColor(1, 1, 1, 1)
      for _, m in ipairs(monitor) do
        love.graphics.draw(img, self.healMachineQuads[1], ox + m[1], oy + m[2])
      end
      for i = 1, math.min(ha.lit, #balls) do
        local b = balls[i]
        if b[3] then -- right column: OAM_XFLIP
          love.graphics.draw(img, self.healMachineQuads[2],
                             ox + b[1] + 8, oy + b[2], 0, -1, 1)
        else
          love.graphics.draw(img, self.healMachineQuads[2],
                             ox + b[1], oy + b[2])
        end
      end
      if shader then love.graphics.setShader() end
    end
  end

  -- the Cut/boulder dust puff: the smoke tile drawn 2x2 over the cell,
  -- flickering (AnimateBoulderDust XORs the OBJ palette every step)
  local function fxDust()
    if not self.dustAnim then return end
    local fxDef = Game.data.field.overworldFx
    local smoke = fxDef and fxDef.smoke
    if smoke then
      if self.smokeImg == nil then
        local ok, img = pcall(love.graphics.newImage, smoke.path)
        self.smokeImg = ok and img or false
      end
      if self.smokeImg then
        local da = self.dustAnim
        local dx = da.x * 16 - cam.x
        local dy = da.y * 16 - cam.y
        local flicker = math.floor(da.frames / 4) % 2 == 0
        love.graphics.setColor(1, 1, 1, flicker and 1 or 0.55)
        for i = 0, 1 do
          for j = 0, 1 do
            love.graphics.draw(self.smokeImg, dx + i * 8, dy + j * 8)
          end
        end
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end

  -- the cut tree splitting apart (AnimCut): top half slides right,
  -- bottom half slides left, 1px per frame, flickering as they go
  local function fxCutTree()
    if not self.cutAnim then return end
    local fxDef = Game.data.field.overworldFx
    local tree = fxDef and fxDef.cutTree
    if not tree then return end
    if self.cutTreeImg == nil then
      local ok, img = pcall(love.graphics.newImage, tree.path)
      self.cutTreeImg = ok and img or false
    end
    local img = self.cutTreeImg
    if not img then return end
    if not self.cutTreeQuads then
      local w, h = img:getWidth(), img:getHeight()
      self.cutTreeQuads = {
        love.graphics.newQuad(0, 0, 16, 8, w, h), -- top half
        love.graphics.newQuad(0, 8, 16, 8, w, h), -- bottom half
      }
    end
    local ca = self.cutAnim
    local off = (ca.total or 8) - ca.frames
    local dx = ca.x * 16 - cam.x
    local dy = ca.y * 16 - cam.y
    local flicker = ca.frames % 2 == 0
    love.graphics.setColor(1, 1, 1, flicker and 1 or 0.55)
    love.graphics.draw(img, self.cutTreeQuads[1], dx + off, dy)
    love.graphics.draw(img, self.cutTreeQuads[2], dx - off, dy + 8)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- the "!" bubble above a trainer who spotted the player
  local function fxEmote()
    if not (self.emote and self.emote.npc) then return end
    -- bubble = false is a silent hold (a Pikachu emotion that plays a
    -- cry with no bubble still pauses the world for its beat)
    if self.emote.bubble == false then return end
    local npc = self.emote.npc
    local ex = npc.px - cam.x + 4
    local ey = npc.py - cam.y - 14
    local bubble = Game.data.field.emotionBubbles
    local drawn = false

    -- HOENN'S OWN BUBBLE, which is not on the Game Boy's sheet.
    --
    -- The "!" over a trainer's head is three 16x16 icons hanging off a sprite
    -- template that only a field-effect script reaches (see extractEmotes) --
    -- which is why every sweep of the field-effect tables missed it.  A Gen 3
    -- dataset that has them draws them; one that does not falls through to
    -- the Game Boy sheet and then to the box below, exactly as before.
    local icons = (Game.data.constants or {}).gen3Emotes
    if icons then
      local role = GEN3_EMOTE_ROLES[self.emote.bubble or 1] or "exclamation"
      local record = icons[role]
      local path = record and record.image
      if path then
        self.gen3EmoteImages = self.gen3EmoteImages or {}
        local held = self.gen3EmoteImages[path]
        if held == nil then
          local okImg, img = pcall(require("src.render.Assets").image, path)
          held = (okImg and img) or false
          self.gen3EmoteImages[path] = held
        end
        if held then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(held, ex, ey)
          drawn = true
        end
      end
    end
    if not drawn and bubble and bubble.path then
      local ok, img = pcall(function()
        self.emoteImg = self.emoteImg or obpEmoteImage(bubble.path)
        return self.emoteImg
      end)
      -- EXCLAMATION_BUBBLE is index 0 -> first crop; the emote command
      -- picks question/happy crops instead
      local bi = self.emote.bubble or 1
      local rect = bubble.bubbles and bubble.bubbles[bi]
      if ok and img and rect then
        love.graphics.setColor(1, 1, 1, 1)
        -- one Quad per bubble crop, cached: this draws every frame the "!"
        -- (or the emote-command crops) is up, so a fresh Quad here churned
        -- the GC.  The bubble set is small and fixed, so the cache is bounded.
        self.emoteQuads = self.emoteQuads or {}
        local q = self.emoteQuads[bi]
        if not q then
          q = love.graphics.newQuad(rect.x, rect.y, rect.w, rect.h,
                                    img:getDimensions())
          self.emoteQuads[bi] = q
        end
        love.graphics.draw(img, q, ex, ey)
        drawn = true
      end
    end
    if not drawn then
      local Font = require("src.render.Font")
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", ex, ey, 10, 12)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("line", ex + 0.5, ey + 0.5, 10, 12)
      Font.draw("!", ex + 1, ey + 2)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- the FLY bird sweeping off with the player
  local function fxBird()
    if not self.flyAnim then return end
    local birdId = FieldDefaults.fieldValue(Game.data, "playerSprites", "fly")
    if not self.birdSprite and birdId and Game.data.sprites[birdId] then
      local SR = require("src.render.SpriteRenderer")
      self.birdSprite = SR.new(Game.data.sprites[birdId])
    end
    if self.birdSprite then
      local t = 48 - self.flyAnim.frames
      local bx = self.player.px - t * 4
      local by = self.player.py - math.floor(t * 1.5)
      love.graphics.setColor(1, 1, 1, 1)
      self.birdSprite:draw(bx, by, cam.x, cam.y, "left",
                           math.floor(t / 4) % 2, false)
    end
  end

  -- fishing pose: the rod tile over the faced water (gfx/fishing.asm)
  local function fxRod()
    if not self.fishing then return end
    local fx = Game.data.field.overworldFx
    local rod = fx and fx.fishingRod
    if rod then
      if self.rodImg == nil then
        local ok, img = pcall(love.graphics.newImage, rod.path)
        self.rodImg = ok and img or false
      end
      if self.rodImg then
        local p = self.player
        local oam = ROD_OAM[self.fishing.facing] or ROD_OAM.down
        if not self.rodQuads then
          -- one quad per 8x8 tile of the stacked sheet (ROD_OAM.tile)
          local iw, ih = self.rodImg:getDimensions()
          self.rodQuads = {}
          for i = 0, math.floor(ih / 8) - 1 do
            self.rodQuads[i] = love.graphics.newQuad(0, i * 8, 8, 8, iw, ih)
          end
        end
        local quad = self.rodQuads[oam.tile]
        -- the sprite's top-left is 4px above its cell (SpriteRenderer:draw)
        local rx = p.px - cam.x + oam.dx
        local ry = p.py - cam.y - 4 + oam.dy
        love.graphics.setColor(1, 1, 1, 1)
        if quad and oam.flip then
          love.graphics.draw(self.rodImg, quad, rx + 8, ry, 0, -1, 1)
        elseif quad then
          love.graphics.draw(self.rodImg, quad, rx, ry)
        end
      end
    end
  end

  if pipelineId then
    -- === PIPELINE PATH: a mod owns the world pass. ======================
    -- It renders terrain and characters however it likes and hands back one
    -- window-resolution image; the field FX stay ordinary 2D draws
    -- composited on top by ctx.drawFx, each anchored to where its ground
    -- point projects under the pipeline's own camera.  That is the direct
    -- analogue of what :billboard does for tilt, and it keeps exactly one
    -- copy of every effect: the closures above are the ones that run.
    -- ctx.width/height are FRAMEBUFFER PIXELS, not LOVE units.
    --
    -- They have to be, because everything else in this contract already is:
    -- `scale` is Zoom.scale over Renderer:fitScale, which measures the
    -- drawable, and Renderer:endFrame composites the returned canvas so that
    -- one canvas pixel is one display pixel.  This line used to read
    -- love.graphics.getDimensions() -- LOVE UNITS -- while calling the result
    -- `pw, ph`, so a pipeline that sized its render target from it paid the DPI
    -- scale TWICE: the canvas came out that much smaller and was then drawn
    -- that much smaller again, landing the whole 3D world in the TOP-LEFT
    -- CORNER at 1/dpi of the screen with black around it.  Invisible on
    -- desktop, where units and pixels are the same thing.  On Android the DPI
    -- scale is the display density, so the world came out roughly a third of
    -- the size in each direction.
    --
    -- DRAMATIC_SHAPE worked around this by asking the GPU itself (its
    -- `sceneSize` helper) rather than trusting the ctx, which is why that mod
    -- looked right on a phone while forks of it made before that fix did not.
    -- Both agree now, so neither double-corrects.
    --
    -- unitWidth/unitHeight are the same window in LOVE units for a pipeline
    -- that genuinely wants them.  On desktop all four numbers are equal.
    local uw, uh = love.graphics.getDimensions()
    local pw, ph = uw, uh
    if love.graphics.getPixelDimensions then
      local gw, gh = love.graphics.getPixelDimensions()
      if gw and gh and gw > 0 and gh > 0 then pw, ph = gw, gh end
    end
    local pscale = Zoom.scale(Game.renderer:fitScale())
    local ctx = {
      state = self, cam = cam, vw = vw, vh = vh, bgY = bgY,
      width = pw, height = ph, scale = pscale,
      pixelWidth = pw, pixelHeight = ph,
      unitWidth = uw, unitHeight = uh,
      level = Pipelines.level(pipelineId),
      -- the SGB world palette a map draws under; nil in the true-colour
      -- modes, whose art is already baked (and must not be re-mapped)
      paletteFor = function(map)
        return PaletteFX.pal(Game.data, self:paletteNameFor(map or self.map))
      end,
      spriteColors = function(map)
        if PaletteFX.usesGbcPack() then return nil end
        return PaletteFX.pal(Game.data, self:paletteNameFor(map or self.map))
      end,
      fx = { heal = fxHeal, dust = fxDust, cutTree = fxCutTree,
             emote = fxEmote, bird = fxBird, rod = fxRod },
    }
    -- Draw every active field FX into the finished scene.  `project(wx, wy)`
    -- maps a world point to canvas pixels (nil when it is behind the
    -- camera) and `scale` is canvas pixels per world pixel; the pipeline
    -- owns the camera, this owns where each effect belongs and how the
    -- closures' flat coordinates are slid onto the projected anchor.
    -- Deliberately unscaled by depth, like :billboard: an effect keeps its
    -- crisp authored size and only its anchor moves.
    ctx.drawFx = function(project, scale)
      scale = scale or pscale
      local colors = ctx.spriteColors()
      local function at(drawFn, wx, wy)
        if not drawFn then return end
        local sx, sy = project(wx, wy)
        if not sx then return end          -- behind the camera
        local shader = colors and PaletteFX.shader() or nil
        if shader then
          PaletteFX.sendColors(shader, colors)
          love.graphics.setShader(shader)
        end
        -- the closures draw relative to the flat foot; slide that onto the
        -- projected anchor, in world-pixel units inside the scaled transform
        local fx, fy = wx - cam.x, wy - cam.y
        love.graphics.push()
        love.graphics.scale(scale, scale)
        love.graphics.translate(sx / scale - fx, sy / scale - fy)
        drawFn()
        love.graphics.pop()
        if shader then love.graphics.setShader() end
      end
      -- ground-hugging effects sit on the cell they belong to
      if self.dustAnim then
        at(fxDust, self.dustAnim.x * 16 + 8, self.dustAnim.y * 16 + 8)
      end
      if self.cutAnim then
        at(fxCutTree, self.cutAnim.x * 16 + 8, self.cutAnim.y * 16 + 16)
      end
      if self.healAnim then
        at(fxHeal, self.healAnim.px + 8, self.healAnim.py + 16)
      end
      -- standing effects anchor at the foot of whoever they belong to
      if self.emote and self.emote.npc then
        at(fxEmote, self.emote.npc.px + 8, self.emote.npc.py + 16)
      end
      if self.flyAnim then
        at(fxBird, self.player.px + 8, self.player.py + 16)
      end
      if self.fishing then
        at(fxRod, self.player.px + 8, self.player.py + 16)
      end
    end
    override = Pipelines.drawWorld(pipelineId, ctx)
    -- world post-processes (a miniature-diorama blur, a colour grade) fold
    -- over the finished scene here, so they never touch the UI drawn on top
    if override then
      override = Pipelines.worldPresent(override, ctx)
    end
    Game.renderer:setWorldOverride(override)
    if not override then
      -- The pipeline declined this frame (nothing to draw, or it threw and
      -- was retired).  The ground pass was skipped on its behalf above, so
      -- draw it now and fall through to the flat path below rather than
      -- compositing an empty canvas.
      self.map.renderer:drawBorderFill(cam.x, bgY, vw, vh)
      self.map.renderer:draw(cam.x, bgY, vw, vh)
      for _, nb in ipairs(self.neighbors) do
        nb.map.renderer:drawMapOnly(cam.x - nb.ox, bgY - nb.oy, vw, vh)
      end
    end
  end

  if override then
    -- the pipeline owns the whole frame; nothing else draws into the world
  elseif not tilt then
    -- === FLAT PATH: everything into the one world canvas, as before =====
    -- OBP-baked sprites replay after the zone pass in OG RED mode, so their
    -- grass feet-overdraw must replay over them too, colorized with the
    -- current map's palette (see PaletteFX.markSpriteRedraw).  SGB no longer
    -- takes that path -- its characters are colorized by the zone just like
    -- the ground under them (#301) -- so there the first overdraw is already
    -- the final one.
    local grassColors = PaletteFX.usesSpriteObp()
      and PaletteFX.pal(Game.data, self:paletteNameFor(self.map)) or nil
    for _, g in ipairs(self.ghosts) do
      g.npc:draw(cam.x - g.ox, cam.y - g.oy)
    end
    -- HIDDEN MEANS HIDDEN, for the player as much as for anybody.
    --
    -- Two Gen 3 things write this and neither had a reader: the
    -- set_invisible / set_visible movement actions, and `hideobjectat
    -- OBJ_EVENT_ID_PLAYER`, which is how the cartridge takes the player off
    -- screen when they step into a doorway (29 scripts do it).  An NPC that
    -- is hidden leaves self.entities outright; the player never can, so the
    -- flag is what has to be honoured here.
    -- ...AND A PLOT'S ANSWER CHANGES WHILE YOU ARE STANDING THERE.  A tree
    -- is planted, grows and is picked without the map reloading, so its
    -- emptiness is asked at draw time rather than remembered at spawn.
    local function plotEmpty(e)
      if not e.berryTreeId then return false end
      local ok, stage = pcall(function()
        return require("src.script.Gen3Commands")
          .berryTreeStage(Game.save, e.berryTreeId)
      end)
      return ok and (stage or 0) <= 0
    end
    local function drawEntity(e)
      if not (self.flyAnim and self:hasFlyBird() and e == self.player)
         and not e.hidden and not plotEmpty(e) then
        e:draw(cam.x, cam.y)
        -- tall grass overdraws the sprite's feet (GB sprite priority);
        -- the overdraw is BG tiles, so it rides the shake offset too
        love.graphics.setColor(1, 1, 1, 1)
        if self.map:isGrassCell(e.cellX, e.cellY) then
          if not self:drawGen3Grass(e.cellX, e.cellY, cam.x, bgY,
                                    self:gen3GrassFrame(e, false)) then
            self.map.renderer:drawCellBottom(e.cellX, e.cellY, cam.x, bgY)
            if grassColors then
              self.map.renderer:markCellBottomRedraw(e.cellX, e.cellY,
                                                     cam.x, bgY, grassColors)
            end
          end
        end
        if e.targetX and self.map:isGrassCell(e.targetX, e.targetY) then
          if not self:drawGen3Grass(e.targetX, e.targetY, cam.x, bgY,
                                    self:gen3GrassFrame(e, true)) then
            self.map.renderer:drawCellBottom(e.targetX, e.targetY, cam.x, bgY)
            if grassColors then
              self.map.renderer:markCellBottomRedraw(e.targetX, e.targetY,
                                                     cam.x, bgY, grassColors)
            end
          end
        end
      end
    end

    -- WHO THE TOP LAYER COVERS, which is not everybody.
    --
    -- Reported from play: "when walking on bridges it makes my character go
    -- under them rather than walking on top of them".  On the cartridge the
    -- covering layer is a background at priority 1 and the sprite's own
    -- priority comes from its elevation, so an object on ordinary ground
    -- (priority 2) is hidden by it and one on a bridge deck (priority 1) is
    -- not -- see extractSpritePriority.  Here that is the same thing as
    -- drawing the deck's walkers AFTER the layer instead of before it.
    local onTop = nil
    for _, e in ipairs(self.entities) do
      if self:gen3AboveTopLayer(e) then
        onTop = onTop or {}
        onTop[#onTop + 1] = e
      else
        drawEntity(e)
      end
    end
    -- The Gen 3 top layer goes on AFTER the entity pass and before the
    -- field effects: it is the half of every metatile the player walks
    -- behind -- treetops, upper storeys, the far rail of a bridge.  On a
    -- Gen 1 or Gen 2 map this returns false and draws nothing, so there is
    -- no generation test at the call site.
    love.graphics.setColor(1, 1, 1, 1)
    self.map.renderer:drawAbove(cam.x, bgY, vw, vh)
    for _, nb in ipairs(self.neighbors) do
      if nb.map.renderer.drawAbove then
        nb.map.renderer:drawAbove(cam.x - nb.ox, bgY - nb.oy, vw, vh)
      end
    end
    for _, e in ipairs(onTop or {}) do drawEntity(e) end

    fxHeal()
    fxDust()
    fxCutTree()
    fxEmote()
    fxBird()
    fxRod()
  else
    -- === TILT PATH: ground-hugging FX stay on the projected ground, all
    -- standing things billboard upright over it in a separate pass. ======
    -- Dust / cut / the Poké Center heal overlay hug the BG (the heal
    -- machine is a tileset graphic; its OAM balls must ride that plane or
    -- they float off the machine once the ground foreshortens).  Flat mode
    -- draws them last, over the sprites, in the same canvas; here the two
    -- layers are separate and composited ground-under-upright, so drawing
    -- them now into the still-active ground canvas is order-equivalent.
    fxHeal()
    fxDust()
    fxCutTree()

    Game.renderer:beginUprightPass()

    -- One y-sorted list of ALL upright billboards -- sprites (player, NPCs,
    -- ghosts) -- keyed on baseline world y (the foot / base row).  Farther
    -- rows project higher/smaller, so back-to-front is just ascending
    -- baseline y.
    local items = {}
    for _, g in ipairs(self.ghosts) do
      items[#items + 1] = { y = g.npc.py + g.oy + 16, kind = "ghost", g = g }
    end
    for _, e in ipairs(self.entities) do
      if not (self.flyAnim and self:hasFlyBird() and e == self.player) then
        items[#items + 1] = { y = e.py + 16, kind = "entity", e = e }
      end
    end
    table.sort(items, function(a, b) return a.y < b.y end)

    for _, it in ipairs(items) do
      if it.kind == "ghost" then
        -- ghosts billboard just like real entities (foot offset folds in the
        -- neighbour map's ox/oy that ghost draws already apply via the camera)
        local g = it.g
        local fx = g.npc.px - cam.x + g.ox + 8
        local fy = g.npc.py - cam.y + g.oy + 16
        self:billboard(fx, fy, vw, vh, zoneColorsAt(zones, fx, fy), false,
                       function() g.npc:draw(cam.x - g.ox, cam.y - g.oy) end)
      else
        local e = it.e
        local fx = e.px - cam.x + 8
        local fy = e.py - cam.y + 16
        local colors = zoneColorsAt(zones, fx, fy)
        self:billboard(fx, fy, vw, vh, colors, false,
                       function() e:draw(cam.x, cam.y) end)
        -- tall-grass feet overdraw glued to the sprite: same anchor + depth
        -- so it keeps hiding the feet, color-0-keyed palette so its white
        -- gaps still show the sprite through (drawCellBottomRaw lets the
        -- billboard own the shader; bgY keeps the elevator-shake offset).
        if self.map:isGrassCell(e.cellX, e.cellY) then
          self:billboard(fx, fy, vw, vh, colors, true, function()
            love.graphics.setColor(1, 1, 1, 1)
            self.map.renderer:drawCellBottomRaw(e.cellX, e.cellY, cam.x, bgY)
          end)
        end
        if e.targetX and self.map:isGrassCell(e.targetX, e.targetY) then
          self:billboard(fx, fy, vw, vh, colors, true, function()
            love.graphics.setColor(1, 1, 1, 1)
            self.map.renderer:drawCellBottomRaw(e.targetX, e.targetY, cam.x, bgY)
          end)
        end
      end
    end

    -- Standing world FX: each billboards at the ground foot of the
    -- character it belongs to, so it stays upright over the tilted ground.
    --   emote bubble  -> the spotting NPC's foot (rides above its head)
    --   fly bird, rod -> the player's foot
    -- (heal machine is ground-hugging -- drawn above with dust/cut)
    if self.emote and self.emote.npc then
      local fx = self.emote.npc.px - cam.x + 8
      local fy = self.emote.npc.py - cam.y + 16
      self:billboard(fx, fy, vw, vh, zoneColorsAt(zones, fx, fy), false, fxEmote)
    end
    if self.flyAnim then
      local fx = self.player.px - cam.x + 8
      local fy = self.player.py - cam.y + 16
      self:billboard(fx, fy, vw, vh, zoneColorsAt(zones, fx, fy), false, fxBird)
    end
    if self.fishing then
      local fx = self.player.px - cam.x + 8
      local fy = self.player.py - cam.y + 16
      self:billboard(fx, fy, vw, vh, zoneColorsAt(zones, fx, fy), false, fxRod)
    end

    Game.renderer:endUprightPass()
  end

  -- LAST IN THE WORLD PASS, over everything the cave contains: the black
  -- window with the circle cut out of it.  It has to be here rather than in
  -- drawUI because it is anchored to the PLAYER, not to the screen -- the
  -- cartridge can put it at a fixed (120,80) because its camera never lets
  -- the player leave the middle, and this port's does at a map edge.
  -- The rotating gates, over the ground and the people standing on it: the
  -- cartridge draws them as sprites at OBJ priority 2, the same band the
  -- objects are in, and sorts within it by subpriority.  This port draws them
  -- last of the world, which is the front of that band -- the honest
  -- simplification, and the one that keeps a fence from swallowing whoever
  -- walks past it.
  self:drawGen3Gates(cam)
  self:drawGen3Flash(cam, vw, vh)
  -- ...and over that, the decoration the player is currently holding.  It is
  -- in the world pass rather than the UI pass for the same reason the flash
  -- is: it is anchored to a CELL, not to the screen.
  self:drawGen3Decorate(cam)
end

-- The cursor the DECORATE row hands the player: the decoration's own
-- footprint, outlined, blinking, anchored at its bottom-left the way the
-- save stores it.
function OverworldState:drawGen3Decorate(cam)
  local mode = self.gen3Decorate
  if not mode then return end
  local blink = math.floor((self.weatherFrame or 0) / 8) % 2 == 0
  local x = mode.x * 16 - cam.x
  local y = (mode.y - mode.height + 1) * 16 - cam.y
  local w, h = mode.width * 16, mode.height * 16
  love.graphics.setColor(1, 1, 1, blink and 0.55 or 0.25)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
  love.graphics.setColor(1, 1, 1, 1)
end

-- THE HOLE, drawn the way the cartridge cuts it: one span a scanline.
--
-- SetFlashScanlineEffectWindowBoundaries fills a per-line table of left/right
-- edges and the hardware window does the rest, so a row-at-a-time fill here is
-- not an approximation of Emerald's circle, it IS Emerald's circle -- and it
-- needs no stencil buffer, which keeps the field draw working on every backend
-- the port runs on.  Two rectangles a row, plus one above and one below.
function OverworldState:drawGen3Flash(cam, vw, vh)
  if not GameVersion.isGen3() then return end
  local Gen3Flash = require("src.world.Gen3Flash")
  local circle = Gen3Flash.circle(Game, vw, vh)
  if not (circle and self.player) then return end
  local radius = tonumber(circle.radius) or 0
  love.graphics.setColor(0, 0, 0, 1)
  if radius <= 0 then
    -- the table's darkest level closes the window completely; the cartridge
    -- never selects it, but a script may
    love.graphics.rectangle("fill", 0, 0, vw, vh)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  -- the middle of the player's own cell, which is (120,80) whenever the view
  -- is the GBA's own 240x160 -- the two numbers the cartridge hard-codes
  local cx = self.player.px - cam.x + 8
  local cy = self.player.py - cam.y + 8
  local top = math.max(0, math.floor(cy - radius))
  local bottom = math.min(vh, math.ceil(cy + radius))
  if top > 0 then love.graphics.rectangle("fill", 0, 0, vw, top) end
  if bottom < vh then
    love.graphics.rectangle("fill", 0, bottom, vw, vh - bottom)
  end
  for y = top, bottom - 1 do
    local dy = y + 0.5 - cy
    local half = math.sqrt(math.max(0, radius * radius - dy * dy))
    local left = cx - half
    local right = cx + half
    if left > 0 then
      love.graphics.rectangle("fill", 0, y, math.min(left, vw), 1)
    end
    if right < vw then
      love.graphics.rectangle("fill", math.max(right, 0), y,
                              vw - math.max(right, 0), 1)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Emerald's healing machine: the monitor over the machine's screen and one
-- glowing ball per healed Pokemon, over a 2x3 grid.  Answers true when it drew,
-- which is what keeps the Game Boy path from drawing its own two tiles on top.
--
-- The monitor has TWO frames and the cartridge flickers between them; `visible`
-- is the same beat the Game Boy path uses to swap the machine's shades, so the
-- two generations blink together off one clock.
function OverworldState:drawGen3Heal(ha, cam)
  if not GameVersion.isGen3() then return false end
  local record = (Game.data.constants or {}).gen3HealMachine
  if not (record and record.monitor and record.glow) then return false end
  self.gen3HealArt = self.gen3HealArt or {}
  local art = self.gen3HealArt
  local function picture(path)
    if art[path] == nil then
      local ok, img = pcall(require("src.render.Assets").image, path)
      art[path] = (ok and img) or false
    end
    return art[path] or nil
  end
  local ox = math.floor(ha.px - cam.x)
  local oy = math.floor(ha.py - cam.y)
  love.graphics.setColor(1, 1, 1, 1)
  local frames = record.monitor.images or {}
  local frame = frames[(ha.visible == false) and 2 or 1] or frames[1]
  local monitor = frame and picture(frame)
  if monitor then
    love.graphics.draw(monitor, ox + record.monitor.x, oy + record.monitor.y)
  end
  local glow = record.glow.image and picture(record.glow.image)
  if glow then
    for i = 1, math.min(ha.lit or 0, #(record.glow.offsets or {})) do
      local at = record.glow.offsets[i]
      love.graphics.draw(glow, ox + record.glow.x + at[1],
                         oy + record.glow.y + at[2])
    end
  end
  return (monitor or glow) ~= nil
end

-- screen-space overlays: drawn to the UI canvas at normal scale
function OverworldState:drawUI()
  -- WEATHER FIRST, so everything else in this pass sits over it: the
  -- cartridge's weather is drawn on the background and window layers below
  -- the text box, and a rain that fell in front of the dialogue would be
  -- the one thing on screen that could not be read through.
  self:drawFieldWeather()

  -- The map-name sign rides the window layer over the top four rows
  -- (HDMATransfer_OnlyTopFourRows), so it sits above the map but under the
  -- poison flash below.  PlaceMapNameFrame draws the frame at hlcoord 0, 0
  -- with two interior rows, and PlaceMapNameCenterAlign centres the name on
  -- the second of them (hlcoord 0, 2 + (SCREEN_WIDTH - len) / 2).
  if self.mapNameSign then
    local Font = require("src.render.Font")
    Font.drawBox(0, 0, 20, 4)
    love.graphics.setColor(0, 0, 0, 1)
    local name = self.mapNameSign.name
    Font.draw(name, math.max(0, math.floor((160 - Font.width(name)) / 2)), 16)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if self.brailleBox then self:drawBrailleBox() end

  -- TalkToPikachu's picture box (engine/pikachu/pikachu_pic_animation.asm
  -- PlacePikapicTextBoxBorder: TextBoxBorder at (6,5) with b,c = 5,5, so a
  -- 7x7 box holding the 5x5 pic at (7,6) -- PikaAnimTilemap_1).  The
  -- script's base frame is ripped as pikachu/pikapic_N.png (#561) but the
  -- pikaframe overlays on top of it are not, so PikachuFollower
  -- .picLift lifts the base on the runs that draw the alternate pose, and the
  -- script's own duration times the beat (#407, #424).  Palette zone
  -- PAL_PIKACHU_PORTRAIT covers (7,6)-(11,10) via sgbPalettes above.
  if self.emote and self.emote.pikaPic then
    require("src.render.Font").drawBox(6, 5, 7, 7)
    -- one image per path, cached: this draws every frame of the hold, and
    -- a mod skin can move the path between talks
    if self.pikaPicPath ~= self.emote.pikaPic then
      local ok, loaded = pcall(love.graphics.newImage, self.emote.pikaPic)
      self.pikaPicImg = ok and loaded or nil
      self.pikaPicPath = self.emote.pikaPic
    end
    local img = self.pikaPicImg
    if img then
      love.graphics.setColor(1, 1, 1, 1)
      local w, h = img:getDimensions()
      local lift = require("src.world.PikachuFollower").picLift(self.emote)
      love.graphics.draw(img, math.floor(56 + (40 - w) / 2),
                         math.floor(48 + (40 - h) / 2) - lift)
    end
  end

  -- poison step flicker (ChangeBGPalColor0_4Frames: dark for two
  -- 4-frame pulses)
  if self.poisonFlash and self.poisonFlash > 0 then
    self.poisonFlash = self.poisonFlash - 1
    local pulse = math.floor(self.poisonFlash / 4) % 2 == 1
    if pulse then
      love.graphics.setColor(0, 0, 0, 0.45)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

-- ---------------------------------------------------------------------------
-- THE BRAILLE WALL, drawn the way ScrCmd_braillemessage draws it.
--
-- Everything here is a number off the cartridge rather than a layout choice:
--
--   * the box is CENTRED -- x = (30 - width) / 2, y = (20 - height) / 2 --
--     and its size comes from the string, not from the six format bytes in
--     front of it, which Emerald skips and never reads;
--   * width is the measured string over 8, capped at 28 tiles; height is 4
--     tiles plus 3 for every line break, capped at 18;
--   * a cell is 16 pixels square and a line is 16 + gFontInfos[6].lineSpacing
--     = 24 apart.
--
-- Those two rules leave the cells flush with the window's left and right
-- edges and eight pixels down from its top -- 24n + 8 pixels of box around
-- 24n - 8 pixels of dots -- so the inset is arithmetic rather than taste.
--
-- What is drawn is DOTS.  The extractor knows perfectly well what each wall
-- says (constants.gen3Braille carries the letters), and printing them would
-- be a parity break: reading the wall is the puzzle.
function OverworldState:drawBrailleBox()
  local box = self.brailleBox
  local wall = box and box.wall
  local record = Game.data and Game.data.constants
                 and Game.data.constants.gen3Braille
  if not (wall and record and record.image) then return end
  if self.brailleImage == nil or self.braillePath ~= record.image then
    local ok, img = pcall(require("src.render.Assets").image, record.image)
    self.brailleImage = (ok and img) or false
    self.braillePath = record.image
    self.brailleQuads = nil
  end
  local img = self.brailleImage
  local Font = require("src.render.Font")
  -- the frame sits OUTSIDE the window the cartridge measures, which is what
  -- DrawStdWindowFrame does
  Font.drawBox(wall.x - 1, wall.y - 1, wall.width + 2, wall.height + 2)
  if not (img and img.getWidth) then return end
  local cell = tonumber(record.cell) or 16
  local perRow = tonumber(record.perRow) or 8
  local advance = tonumber(record.advance) or cell
  local lineHeight = tonumber(record.lineHeight) or (cell + 8)
  self.brailleQuads = self.brailleQuads or {}
  love.graphics.setColor(1, 1, 1, 1)
  for row, line in ipairs(wall.lines or {}) do
    local y = wall.y * 8 + 8 + (row - 1) * lineHeight
    for col, value in ipairs(line) do
      local quad = self.brailleQuads[value]
      if not quad then
        quad = love.graphics.newQuad((value % perRow) * cell,
                                     math.floor(value / perRow) * cell,
                                     cell, cell,
                                     img:getWidth(), img:getHeight())
        self.brailleQuads[value] = quad
      end
      love.graphics.draw(img, quad, wall.x * 8 + (col - 1) * advance, y)
    end
  end
end

-- One step of Island Cave's lap.  Everything it decides is in
-- Gen3Commands.regiceLap, which is gSpecials[498]; this is the caller the
-- cartridge's field controller is, and the door it opens is the script the
-- controller runs.
function OverworldState:gen3RegiceStep()
  if not GameVersion.isGen3() then return end
  local Gen3Regi = require("src.world.Gen3Regi")
  local chamber = Gen3Regi.chamberFor(Game, self.map and self.map.id)
  if not (chamber and chamber.lap) then return end
  local Gen3Commands = require("src.script.Gen3Commands")
  local done = Gen3Commands.regiceLap({ overworld = self, game = Game,
                                        save = Game.save })
  if done then Gen3Regi.open(Game, self, chamber) end
end

-- THE CALLS THAT COME WHILE YOU WALK.
--
-- Five entries in the field controller's step chain are one function copied
-- five times, and every one is a PokeNav call: armed by a flag, counted in
-- OUTDOOR steps only, fired once its own var passes its own threshold, and
-- disarmed by its own script.  constants.gen3FieldCalls carries the five,
-- read off the cartridge by extractFieldCalls.
--
-- Two details matter and both are the cartridge's.  The outdoor set is
-- TOWN/CITY/ROUTE/OCEAN_ROUTE and NOT IsMapTypeOutdoors -- no calls on the
-- seafloor.  And the counters are independent: every armed call advances on
-- a step, and only the first one to pass its threshold runs, so a call that
-- comes due while another is playing is still due afterwards.
function OverworldState:gen3FieldCallStep()
  if not GameVersion.isGen3() then return end
  local record = Game.data and Game.data.constants
                 and Game.data.constants.gen3FieldCalls
  if type(record) ~= "table" then return end
  local save = Game.save
  local flags = save and save.flags
  if not flags then return end
  local Gen3Commands = require("src.script.Gen3Commands")
  local def = self.map and self.map.def
  local outdoors = record.outdoors or {}

  -- The five calls come first in the chain, and every one of them turns
  -- itself away indoors -- so indoors the whole group simply does not count.
  if def and outdoors[def.mapType] then
    for _, call in ipairs(record.calls or {}) do
      if flags[call.flag] then
        local count = (Gen3Commands.getVar(save, call.var) or 0) + 1
        Gen3Commands.setVar(save, call.var, count)
        if count >= (tonumber(call.steps) or math.huge) then
          self:gen3RunFieldScript(call.script, "call")
          -- the chain runs ONE script and returns
          return
        end
      end
    end
  end

  -- ...and the ferry is further down the same chain, which is why it is
  -- asked after them and only when none of them fired.
  self:gen3CruiseStep(record)
end

-- THE FERRY.
--
-- The same shape as a PokeNav call with the map test taken out: boarding
-- runs special 206, which sets the flag and zeroes the counter; every step
-- after that advances it; and 205 steps later the chain runs the
-- announcement script, which calls 207 and disarms the whole thing.  Every
-- number is the cartridge's -- see extractFieldCalls.
function OverworldState:gen3CruiseStep(record)
  local cruise = record and record.cruise
  if type(cruise) ~= "table" then return end
  local save = Game.save
  local flags = save and save.flags
  if not (flags and flags[cruise.flag]) then return end
  local Gen3Commands = require("src.script.Gen3Commands")
  local count = (Gen3Commands.getVar(save, cruise.var) or 0) + 1
  Gen3Commands.setVar(save, cruise.var, count)
  if count < (tonumber(cruise.steps) or math.huge) then return end
  self:gen3RunFieldScript(cruise.script, "ferry")
end

-- One of the field chain's own scripts, by label.  They are roots no map
-- header names -- extractFieldCalls adds them -- so a cache imported before
-- that stage existed simply has not got them, and saying so is better than
-- a silent nothing.
function OverworldState:gen3RunFieldScript(label, what)
  local rows = require("src.script.Gen3ScriptVM").compile(Game.data, label)
  if not rows then
    Logger.warn("gen3 field %s: %s is not in this dataset -- it is due and "
                .. "cannot be run", tostring(what), tostring(label))
    return false
  end
  self:queueScript(rows, { mapId = self.map and self.map.id })
  return true
end

-- The other half of Gen3Commands' pushBlocking: resume a parked runner once
-- the screen it was waiting on is off the stack.  Pure bookkeeping -- the
-- screen's own callback still wins when it has one, and clears the record
-- before this ever sees it.
function OverworldState:gen3CheckBlockingScreen()
  local waiting = self.gen3Blocking
  if not waiting then return end
  local states = Game.stack and Game.stack.states
  if states and #states > waiting.depth then return end
  self.gen3Blocking = nil
  Logger.info("gen3: a scripted screen closed without calling back -- the "
              .. "script was resumed rather than left waiting")
  if waiting.resume then waiting.resume() end
end

function OverworldState:captureSave(save)
  save.player.map = self.map.id
  save.player.x = self.player.cellX
  save.player.y = self.player.cellY
  save.player.facing = self.player.facing
  -- wWalkBikeSurfState (ram/wram.asm) sits inside the wMainDataStart..
  -- wMainDataEnd range engine/menus/save.asm block-copies into sMainData,
  -- so the original saves and restores the surf state; setMap's boot path
  -- reads this back (#536).
  save.player.surfing = self.player.surfing and true or false
end

return OverworldState
