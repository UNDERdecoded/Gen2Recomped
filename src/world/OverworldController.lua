-- The overworld state: renders the current map (plus connected map
-- strips), runs the player, NPCs, warps, connections, encounters, ledges,
-- surfing, Cut trees, trainer sight lines, and dispatches interactions to
-- map scripts (data/scripts/), marts, nurses or extracted text.

local Assets = require("src.render.Assets")
local Camera = require("src.render.Camera")
local Collision = require("src.world.Collision")
local Encounter = require("src.world.Encounter")
local FieldDefaults = require("src.world.FieldDefaults")
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

local function objectInTimeOfDay(obj)
  if not obj.timeOfDay then return true end
  local tod = Game and Game.overworld and Game.overworld.tod or "DAY"
  local bit = TOD_BITS[tod] or TOD_BITS.DAY
  return math.floor(obj.timeOfDay / bit) % 2 == 1
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
  -- Gen2 object_events carry an event flag; the ROM hides the object while
  -- that flag is set (the Elm's Lab officer, the Cherrygrove rival, ...).
  -- obj.hidden already carries the new game state, so only an explicit
  -- set/clear by a script overrides it.
  if obj.eventFlag and save.flags and save.flags[obj.eventFlag] ~= nil then
    visible = not save.flags[obj.eventFlag]
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
  return visible
end
OverworldState.objectVisible = objectVisible -- exposed for tests + reuse

-- NPC instance pool: one NPC object per map object, keyed by the
-- NPC.id format ("<mapId>_obj_<index>").  The same instance serves as
-- a neighbor-map ghost and as the real NPC once that map is entered,
-- so positions/facings carry across connection seams.
local function pooledNPC(pool, data, mapId, obj)
  local key = mapId .. "_obj_" .. obj.index
  local npc = pool[key]
  if not npc then
    npc = NPC.new(data, mapId, obj)
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
function OverworldState.computeNeighbors(maps, rootId, hops, reachW, reachH)
  local out = {}
  local rootDef = maps[rootId]
  local placed = { [rootId] = true }
  local queue = { { def = rootDef, ox = 0, oy = 0, hops = 0 } }
  local qi = 1
  local function inReach(def, ox, oy)
    if not (reachW and reachH and rootDef) then return false end
    return ox + def.width * 32 > -reachW
       and ox < rootDef.width * 32 + reachW
       and oy + def.height * 32 > -reachH
       and oy < rootDef.height * 32 + reachH
  end
  while queue[qi] do
    local cur = queue[qi]
    qi = qi + 1
    for dir, conn in pairs(cur.def.connections or {}) do
      local destDef = maps[conn.map]
      if destDef and not placed[conn.map] then
        placed[conn.map] = true
        local ox, oy
        if dir == "north" then
          ox, oy = conn.offset * 32, -destDef.height * 32
        elseif dir == "south" then
          ox, oy = conn.offset * 32, cur.def.height * 32
        elseif dir == "west" then
          ox, oy = -destDef.width * 32, conn.offset * 32
        else
          ox, oy = cur.def.width * 32, conn.offset * 32
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
  return out
end

function OverworldState:enter(mapId, x, y, facing)
  Game = require("src.core.Game")
  Game.overworld = self
  Collision.load(Game.data) -- tile-pair (elevation) collisions
  Encounter.load(Game.data) -- constants.encounterBuckets
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
  -- ADVANCED bakes colour into the tileset atlas, so the dark-cave shift has
  -- to be armed before that atlas is built for this map (#383); self.dark is
  -- settled below, once the map record is in hand.
  if PaletteFX.setDarkWorld(isDarkMap(mapId) and not Game.save.flashLit)
     and PaletteFX.usesGbcPack() then
    MapLoader.invalidateAll()
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
  -- the Route 16/18 gate map scripts clear the Cycling Road's
  -- BIT_ALWAYS_ON_BIKE every frame (scripts/Route16Gate1F.asm /
  -- Route18Gate1F.asm `res BIT_ALWAYS_ON_BIKE`); entering the gate is
  -- the walking exit from the forced-bike stretch
  for _, m in ipairs(FieldDefaults.fieldValue(Game.data, "forcedMovement",
                                              "clearMaps") or {}) do
    if m == mapId then Game.save.forcedBike = nil break end
  end
  -- leaving the Safari Zone maps ends any running Safari game
  if Game.save.safari and not Map.inRegion(self.map.def, "SAFARI", "SAFARI_ZONE") then
    Game.save.safari = nil
  end
  -- Rock Tunnel darkness (wMapPalOffset, home/overworld.asm): dark
  -- until FLASH is used; the light persists between the tunnel floors
  -- and resets once outside
  if isDarkMap(mapId) then
    self:setDark(not Game.save.flashLit)
  else
    -- ResetFlashIfOutOfCave (00:$2F1D) only clears the flash bit on a TOWN or
    -- a ROUTE, so the light carries between the floors of a cave system and
    -- across the lit rooms in the middle of one.
    if not (GameVersion.isGen2() and self.map.def.environment
            and self.map.def.environment > 2) then
      Game.save.flashLit = nil
    end
    self:setDark(false)
  end
  local flyWarps = Game.data.field.flyWarps or {}
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
  if self.player then
    self.player.cellX, self.player.cellY = x, y
    self.player.px, self.player.py = x * 16, y * 16
    self.player.facing = facing or self.player.facing
    self.player.moving = false
    self.player.targetX, self.player.targetY = nil, nil
  else
    self.player = Player.new(Game.data, x, y, facing)
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
  self.entities = { self.player }
  for _, n in ipairs(self.npcs) do table.insert(self.entities, n) end
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

  -- fires before the onEnter chain so a listener sees the map in the same
  -- state the map script does
  Runtime.emit("map.entered", {
    mapId = mapId, map = self.map, fromMapId = fromMapId,
    via = (opts and opts.via)
          or (opts and opts.seamless and "connection")
          or (fromMapId and "warp" or "boot"),
  })

  -- map-enter hooks (hand-ported map scripts, e.g. Victory Road barriers).
  -- fromMapId lets elevators seed a valid walk-out floor when the ROM
  -- car warps still point at a missing map (Silph's UNUSED_MAP_ED) and
  -- the player B-cancels the floor menu without .UpdateWarp.
  local hooks = mapScripts.get(mapId)
  if hooks and hooks.onEnter then
    hooks.onEnter(Game, self, fromMapId)
  end

  self:rebuildNeighbors()
  self:updateMapNameSign()
  Logger.info("map: %s at (%d,%d)", mapId, x, y)
  -- Route22Gate_Script rewrites wLastMap from the player's Y on entry
  -- too (not only on step), so a save/load mid-gate keeps exits correct
  self:syncLastMapRewrite()
end

-- InitMapNameSign, run on every map entry (warps and connection crossings
-- alike): remember this map's landmark, and pop the sign when it changed.
function OverworldState:updateMapNameSign()
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
function OverworldState:rebuildNeighbors()
  local mapId = self.map.id
  self.neighbors = {}
  local hops = FieldDefaults.world(Game.data, "neighborHops") or NEIGHBOR_HOPS
  local vw, vh = Game.renderer:worldViewSize()
  self.neighborViewW, self.neighborViewH = vw, vh
  -- resident set the eviction pass must never touch: the current map plus
  -- every drawn neighbor
  local keep = { [mapId] = true }
  for _, n in ipairs(OverworldState.computeNeighbors(Game.data.maps, mapId,
                                                     hops,
                                                     math.floor(vw / 2) + 64,
                                                     math.floor(vh / 2) + 64)) do
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

-- world.tod default: the Gen 2 clock, or always DAY on Gen 1.  A mod returns
-- "NIGHT", "MORNING", etc.; the result is cached on the overworld and handed
-- to map.palette as ctx.tod so palette swaps can key off the period.
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
                            w = nb.map.def.width * 32,
                            h = nb.map.def.height * 32 })
    end
  end
  return zones
end

-- wMapPalOffset, the one piece of state both halves of the darkness read:
-- drawWorld arms PaletteFX.DARK_BGP off self.dark for the shade-remapped
-- modes, and PaletteFX.setDarkWorld feeds the bakes ADVANCED does instead of
-- shading (tileset atlas, sprite sheets) plus their cache keys.  A bake cannot
-- be re-shaded in place, so a change there rebuilds every resident map --
-- every dark floor, not just this one, since FLASH lights them all (#383).
function OverworldState:setDark(on)
  on = on and true or false
  self.dark = on
  if PaletteFX.setDarkWorld(on) and PaletteFX.usesGbcPack() and self.map then
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
function OverworldState:pushBattle(battle)
  local BattleTransition = require("src.render.BattleTransition")
  local lead
  for _, mon in ipairs(Game.save.party) do
    if mon.hp > 0 then lead = mon break end
  end
  local enemyLevel = battle.enemy and battle.enemy.mon and battle.enemy.mon.level or 0
  -- the battle theme starts with the wipe, not after it
  -- (audio/play_battle_music.asm runs before the transition)
  if battle.computeMusicKind then
    require("src.core.Music").playBattle(Game.data, battle:computeMusicKind())
  end

  -- The fade back in from white on the way out is BattleState:finish()'s
  -- job now -- the one choke point every battle passes through on exit,
  -- guaranteed regardless of which caller pushed the battle -- so this
  -- function only owns the entry wipe.
  Game.stack:push(BattleTransition.new(Game, function()
    Game.stack:push(battle)
  end, {
    trainer = battle.kind == "trainer",
    stronger = lead ~= nil and enemyLevel >= lead.level + 3,
    dungeon = self:isDungeonTransitionMap(),
  }))
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
  if queue and queue[1] and not self.transitioning
     and not self.runner:isRunning() and #self.scriptMoves == 0 then
    local pending = table.remove(queue, 1)
    self.runner:run(pending.script, pending.extra)
  end
end

-- Gen2 objects are spawned/despawned by their event flag, and a script that
-- sets one (taking a starter ball, the Elm's Lab theft) has to take effect
-- before the next map load -- so re-run the spawn filter once the script
-- that moved the flag has finished.
function OverworldState:syncObjectVisibility()
  if not (self.map and self.map.def) then return end
  local mapId = self.map.id
  local wanted = {}
  for _, obj in ipairs(self.map.def.objects or {}) do
    if objectVisible(Game.save, mapId, obj) then
      wanted[mapId .. "_obj_" .. obj.index] = obj
    end
  end
  for i = #self.npcs, 1, -1 do
    local npc = self.npcs[i]
    if not wanted[npc.id] then
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
    self.npcs[#self.npcs + 1] = npc
    self.entities[#self.entities + 1] = npc
  end
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
  self:queueScript(script, { phoneCaller = caller })
end

function OverworldState:update(dt)
  -- `earthquake <n>` (Script_earthquake -> EarthquakeMovement 25:$725D):
  -- the BG jolts while the sprites stay put, which is exactly what bgShakeY
  -- already feeds into draw().
  if self.quakeFrames then
    self.quakeFrames = self.quakeFrames - 1
    self.bgShakeY = (math.floor(self.quakeFrames / 2) % 2 == 0) and 2 or -2
    if self.quakeFrames <= 0 then
      self.quakeFrames = nil
      self.bgShakeY = 0
    end
  end
  -- deferred cutscene launch (see queueScript): run a queued script only
  -- once the triggering warp's transition has finished, its runner has gone
  -- dead, and no scripted walk is mid-step.  This is how the HALL_OF_FAME
  -- room cutscene starts a frame after the Champions Room warp completes.
  self:drainPendingScripts()
  local scriptWasRunning = self.runner:isRunning()
  self.runner:update()
  if scriptWasRunning and not self.runner:isRunning() and GameVersion.isGen2() then
    self:syncObjectVisibility()
  end
  self:checkSpecialPhoneCall()
  self:updateParallel()
  -- keep the player sprite in sync with the bike state (the drawer
  -- picks the red_bike sheet while riding)
  self.player.onBike = Game.save.onBike
  -- the rendered neighbor set depends on the view size; zooming out (or
  -- resizing) past what setMap computed re-runs the walk in place
  if self.map and (self.neighborViewW or 0) > 0 then
    local vw, vh = Game.renderer:worldViewSize()
    if vw ~= self.neighborViewW or vh ~= self.neighborViewH then
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
      self.teleportOut = nil
      self.player.spinning = false
      self.player.spinFrames = nil
      self.player.spinRise = nil
      self.player.inputLocked = false
      self:warpToHealPoint(onDone, { arrive = "teleport" })
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
  end

  local stepped = self.player:update()
  -- the warp-arrival cell goes stale the instant the player's real cell
  -- leaves it, scripted walk-outs included -- pokered re-checks warps
  -- after simulated steps too (CheckWarpsNoCollision), so a forced
  -- door-mat exit must not leave the door permanently inert
  local entry = self.warpEntryCell
  if entry and (self.player.cellX ~= entry.x or self.player.cellY ~= entry.y) then
    self.warpEntryCell = nil
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

function OverworldState:handleInput()
  local input = Game.input

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
    Screens.push(Game, "StartMenu")
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
        if self:checkEdgeExit(dir) then return end
        if self:checkLedgeHop(dir) then return end
        if self:checkBoulderPush(dir) then return end
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
  local braking = input:isDown("a") or input:isDown("b")
  if fm and Game.save.onBike and not braking and not self.player.moving then
    for _, m in ipairs(fm.slopeMaps or {}) do
      if m == self.map.id then
        self.player.facing = "down"
        self.player:tryMove("down", self.map, self.entities)
        return
      end
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
  if not self.strengthActive then return false end
  -- The two-attempt arming is Gen 1 only: pokered's BIT_TRIED_PUSH_BOULDER
  -- makes the first bump a no-op, but GSC's .CheckStrengthBoulder pushes
  -- straight away on the first bump.
  if not GameVersion.isGen2() then
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

-- Ledge hops (data/tilesets/ledge_tiles.asm): standing tile + ledge tile
-- in front + matching input direction -> jump two cells.
function OverworldState:checkLedgeHop(dir)
  local p = self.player
  local tileset = self.map.def.tileset
  local standing = self.map:cellTile(p.cellX, p.cellY)
  local fx, fy = Collision.target(p.cellX, p.cellY, dir)
  if not self.map:inBounds(fx, fy) then return false end
  local front = self.map:cellTile(fx, fy)
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
  local conn = self.map:connection(COMPASS[dir])
  if not conn then return nil end
  local dest = Game.data.maps[conn.map]
  if not dest then return nil end
  local ts = Game.data.tilesets[dest.tileset]
  if not ts then return nil end
  local p = self.player
  local destW, destH = dest.width * 2, dest.height * 2
  local x, y
  if dir == "up" then
    x, y = p.cellX - conn.offset * 2, destH - 1
  elseif dir == "down" then
    x, y = p.cellX - conn.offset * 2, 0
  elseif dir == "left" then
    x, y = destW - 1, p.cellY - conn.offset * 2
  else
    x, y = 0, p.cellY - conn.offset * 2
  end
  x = math.max(0, math.min(destW - 1, x))
  y = math.max(0, math.min(destH - 1, y))
  return dest, ts, x, y, conn
end

-- Map connections: the connected map's strip offset is in blocks; arriving
-- coordinates follow destX = curX - offset*2 (see docs/extraction-notes.md).
-- The crossing scrolls continuously: the map data swaps while the player
-- is placed one cell before the entry point (their old world position,
-- which the neighbor strips render identically) and walks the seam step.
function OverworldState:crossConnection(dir, conn)
  local dest, ts, x, y = self:connectionLanding(dir)
  if not dest then
    Logger.warn("connection to unknown map %s", tostring(conn and conn.map))
    return false
  end
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
    or (FieldDefaults.world(Game.data, "stepFrames") or 16)
  require("src.core.FixedStep"):discardCatchup()
  return true
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
  if not self:tilesetHasWater() then return false end
  local fx, fy = self.player:facingCell()
  if self.map:inBounds(fx, fy) then
    return self.map:isWaterCell(fx, fy)
  end
  local dest, ts, x, y = self:connectionLanding(self.player.facing)
  if not dest then return false end
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
local function partyKnowsVanilla(moveId)
  local gate = (FieldDefaults.constant(Game.data, "hmBadges") or {})[moveId]
  local badge = gate and gate.badge
  -- R/B hands badges over as bag items, Gen2 as engine flags; Badges.has
  -- reads either, so this one call covers both
  if badge and not Badges.has(Game.save, { id = badge }) then
    return nil
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
  if Runtime.wantsHook("encounter.fishing") then
    -- the chain may inspect or replace the candidate list before the roll
    enc = Runtime.call("encounter.fishing", function(_, _, candidates)
      return catchFrom(candidates, always)
    end, rod, self.map.id, pool)
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
      if Game.save.safari and Map.inRegion(self.map.def, "SAFARI", "SAFARI_ZONE") then
        battle:makeSafari(Game.save.safari)
      end
      battle.onFinish = function(result) self:afterBattle(result, battle) end
      self:pushBattle(battle)
    end))
  end))
end

-- Fly to a visited town (called from the party menu).
function OverworldState:flyTo(mapId)
  local flyWarps = Game.data.field.flyWarps or {}
  local spot = flyWarps[mapId]
  if not spot then return end
  require("src.core.Sound").play(Game.data, "Fly")
  Game.save.onBike = false
  Game.save.forcedBike = nil -- HandleFlyWarpOrDungeonWarp res BIT_ALWAYS_ON_BIKE
  self.player.surfing = false
  self:syncSurfingPikachu()
  -- the bird carries the player off westward before the warp
  -- (engine/overworld/player_animations.asm LoadBirdSpriteGraphics)
  self.flyAnim = { frames = 48 }
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
function OverworldState:beginTeleportOut(onDone)
  if not Game.save.lastHeal then
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
  self.teleportOut = { frames = 48, onDone = onDone }
end

function OverworldState:npcAtCell(cx, cy)
  for _, npc in ipairs(self.npcs) do
    if (npc.cellX == cx and npc.cellY == cy) or
       (npc.targetX == cx and npc.targetY == cy) then
      return npc
    end
  end
  return nil
end

-- what the A press resolved to, for world.interacted's listeners
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
  if sign then
    self:showMapText(sign.text, nil)
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
  if GameVersion.isGen2() and self:tryFieldMoveOW(fx, fy) then
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
function OverworldState:tryBookshelf(fx, fy)
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
  local text = (Game.data.text._SurfingGotOnText or Strings("{PLAYER} got on\n{RAM:wNameBuffer}!"))
               :gsub("{RAM:wNameBuffer}", name)
  -- UseItem prints the got-on text with the party menu still on screen and
  -- GBPalWhiteOutWithDelay3 + .goBackToMap only run after it
  -- (start_sub_menus.asm .surf), so the text reads over the menu and the
  -- blink is the menu closing, not a flashbang on the empty map (#320,
  -- #385).  The mount rides the blink, so nothing paddles on land.
  Game.stack:push(TextBox.new(Game, text, function()
    if onClose then onClose() end
    p.surfing = true
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

function OverworldState:gen2IsIce(cx, cy)
  local tile = self.map and self.map:cellTile(cx, cy)
  return tile ~= nil and GEN2_ICE_TILES[tile] == true
end

function OverworldState:checkGen2Ice()
  if not GameVersion.isGen2() then return false end
  local p = self.player
  if p.surfing or not self:gen2IsIce(p.cellX, p.cellY) then
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
  if self:tryCutOW(fx, fy) then return true end
  if not self.map:inBounds(fx, fy) then return false end
  local coll = self.map:cellTile(fx, fy)
  local move
  for id, classes in pairs(GEN2_OW_TILES) do
    if classes[coll] then move = id end
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
      Game.data.text._AskSurfText or Strings("The water looks\ndeep. Want to\nSURF?"),
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

-- HeadbuttScript: the struck tree rattles (ShakeHeadbuttTree 23:$4A8E) and
-- then either a TreeMon drops out or nothing does.  GetTreeMon rolls the
-- rare table only when the tree's coordinate score says so; the port rolls
-- it at the same 1-in-32 the score works out to on an average tree.
function OverworldState:gen2Headbutt(fx, fy)
  self:startDustAnim(fx, fy, function()
    local trees = Game.data.field.gen2TreeMons
    local set = trees and trees.maps and trees.maps[self.map.def.label]
    local rows = set and trees.sets and trees.sets[set]
    rows = rows and (math.random(32) == 1 and rows.rare or rows.common)
    -- the leading byte is the table's total chance out of 100
    local roll = rows and math.random(100)
    local pick
    if roll and roll <= (rows.rate or 50) then
      local acc = 0
      for _, row in ipairs(rows) do
        acc = acc + row.chance
        if row.chance == 255 or roll <= acc then pick = row break end
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
    local text = select(1, Game.data:resolveText(self.map.def.label, d.text))
                 or Strings("Gyaoo!")
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
      Screens.push(Game, "BoxMenu")
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
        self.healAnim = { balls = #Game.save.party, lit = 0, timer = 0,
                          visible = true,
                          -- map anchor: the player's cell when healing
                          -- began (the GB's fixed screen coords assume it
                          -- BG-aligned at (64,64))
                          px = self.player.cellX * 16,
                          py = self.player.cellY * 16 }
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
    local battle = BattleState.newTrainer(Game, d.trainerClass, d.trainerParty)
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
function OverworldState:checkTrainerSight()
  if self.player.moving or self.engaging then return end
  if Game.stack:top() ~= self then return end
  local p = self.player
  for _, npc in ipairs(self.npcs) do
    local d = npc.def
    -- CheckFightingMapTrainers engages ANY aligned trainer sprite,
    -- walkers included (they sight between steps)
    if d.trainerClass and not npc.moving
       and not self:trainerDefeated(npc)
       and (d.trainerObject
            or not mapScripts.talkScript(self.map.id, d.text))
       and trainerSpriteOnScreen(npc, p) then
      local header = Game.data:trainerHeader(self.map.def.label, d.index)
      local range = header and header.range or 0
      local vec = DIRVEC[npc.facing]
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
            self:startTrainerApproach(npc, dist)
            return
          end
        end
      end
    end
  end
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

function OverworldState:startTrainerApproach(npc, dist)
  self.engaging = true
  npc.frozen = true
  -- the encounter sting (PlayTrainerMusic): evil / female / male by
  -- class; rivals and gym leaders keep their own music
  local cls = npc.def.trainerClass
  if cls and not cls:find("RIVAL") then
    local Music = require("src.core.Music")
    local role = EVIL_TRAINERS[cls] and "meetEvil"
                 or FEMALE_TRAINERS[cls] and "meetFemale" or "meetMale"
    Music.play(Game.data, Music.special(Game.data, role))
  end
  local function fight()
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
local function rollVanilla(encDef, ctx) return Encounter.roll(encDef, ctx.rng) end
local function sameEncounter(enc) return enc end

-- The wild pick, wrapped in encounter.roll (returns nil to suppress, a
-- table without calling next to force) and then encounter.species (which
-- transforms a non-nil roll before repel filtering).  With no wrapper on
-- either name this is the bare Encounter.roll, same RNG draws and all.
function OverworldState:rollEncounter(encDef, terrain)
  if not (Runtime.wantsHook("encounter.roll")
          or Runtime.wantsHook("encounter.species")) then
    return Encounter.roll(encDef)
  end
  local ctx = { mapId = self.map.id, terrain = terrain, rng = love.math.random }
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
  Pokemon.heal(hatched)
  local name = def and def.name or hatched.species
  Game.stack:push(TextBox.new(Game,
    Strings("Huh?\f%s hatched\nfrom the EGG!", name),
    function()
      Runtime.emit("pokemon.egg_hatched", { mon = hatched })
    end))
  return true
end

function OverworldState:onStepComplete()
  local p = self.player
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

  -- dismounting a surf: landing on a walkable cell ends it
  if p.surfing and self.map:isWalkableCell(p.cellX, p.cellY) then
    p.surfing = false
    self:syncSurfingPikachu()
    require("src.core.Music").setSurfing(Game.data, false)
  end

  -- Route 22 Gate rewrites LAST_MAP by Y before warps/guards fire
  self:syncLastMapRewrite()

  -- hand-ported step triggers (Pallet intro, Saffron gate guards, ...)
  local hooks = mapScripts.get(self.map.id)
  if hooks and hooks.onStep then
    if hooks.onStep(Game, self, p.cellX, p.cellY) then
      return
    end
  end

  -- spinner arrow tiles (Viridian Gym, Rocket Hideout)
  if self:checkSpinner() then return end

  -- badge-check guards (Route 22 gate / Route 23)
  if self:checkBadgeGate() then return end

  -- forced bike/surf tiles + the Seafoam surf currents
  if self:checkForcedMovement() then return end
  if self:checkSeafoamCurrent() then return end
  if self:checkGen2Ice() then return end

  -- the Safari game step counter (engine/events/hidden_events/safari_game.asm)
  if self:safariStep() then return end

  -- day-care: the boarded Pokémon gains 1 exp per step (like the original)
  if Game.save.daycare and Game.save.daycare.mon then
    Game.save.daycare.steps = (Game.save.daycare.steps or 0)
      + (FieldDefaults.world(Game.data, "daycareExpPerStep") or 1)
  end
  -- Gen2 runs two pens plus the breeding counter (DayCareStep, 01:$735E)
  if GameVersion.isGen2() then
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
    if not w and (self:dirHeld() or self.forcedWarp) then
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

  -- wild encounters in grass, on water while surfing, or -- on indoor
  -- maps whose tileset is not FOREST -- on EVERY tile
  -- (wild_encounters.asm: caves, towers, the Mansion, Power Plant)
  local encDef = Game.data.encounters[self.map.id]
  local enc
  local indoor = Game.data.field.indoorEncounters
  local env = self.map.def.environment
  -- Gen2 keeps a morn/day/nite slot set per map; the clock decides which
  local land = encDef and { grass = Encounter.atTime(encDef.grass, self:timeOfDay()) }
  if p.surfing and encDef and encDef.water and self.map:isWaterCell(p.cellX, p.cellY) then
    enc = self:rollEncounter({ grass = encDef.water }, "water")
  elseif self.map:isGrassCell(p.cellX, p.cellY) then
    enc = self:rollEncounter(land, "grass")
  elseif CAVE_ENVIRONMENTS[env] then
    enc = self:rollEncounter(land, "indoor")
  elseif env == nil and indoor and self.map.def.index >= indoor.firstIndoorMap
         and self.map.def.tileset ~= indoor.excludedTileset then
    enc = self:rollEncounter(land, "indoor")
  end
  if enc then
    -- REPEL blocks wild mons weaker than the lead
    local lead = Game.save.party[1]
    if Game.save.repelSteps and Game.save.repelSteps > 0
       and lead and enc.level < lead.level then
      return
    end
    local BattleState = require("src.battle.BattleState")
    local battle = BattleState.newWild(Game, enc.species, enc.level)
    -- map.ghostBattles: unidentifiable without the named item (the
    -- Pokemon Tower's Silph Scope)
    local ghost = Map.ghostBattles(self.map.def)
    if ghost and not (ghost.unlessItem and Game.save.inventory[ghost.unlessItem]) then
      battle:makeGhost()
    end
    -- Safari game encounters use the BALL/BAIT/ROCK/RUN menu
    if Game.save.safari and Map.inRegion(self.map.def, "SAFARI", "SAFARI_ZONE") then
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
function OverworldState:inSafariStepZone()
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
  self:safariGameOver(Strings("PA: Ding-dong!\nTime's up!"))
  return true
end

function OverworldState:safariGameOver(text)
  require("src.core.Sound").play(Game.data, "Safari_Zone_PA")
  Game.save.safari = nil
  local t = Game.data.text
  Game.stack:push(TextBox.new(Game,
    (text or "") .. "\f" .. (t._GameOverText or Strings("PA: Your SAFARI\nGAME is over!")),
    function()
      local exit_ = FieldDefaults.fieldValue(Game.data, "safari", "exitWarp")
      self:startWarpTo(exit_.map, exit_.x, exit_.y, exit_.facing or "down")
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
      self:safariGameOver(Strings("PA: You're out of\nSAFARI BALLs!"))
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
  local boot = Game.data.field.boot or {}
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
  local destMap, x, y = Warp.destination(Game.data, warpDef, last, self.backupWarp)
  -- EnterMapWarp stores the warp being left through as the backup, so a
  -- LAST_WARP door on the far side comes straight back here
  self.backupWarp = { id = fromMap, x = self.player.cellX, y = self.player.cellY }
  Game.save.backupWarp = self.backupWarp
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
  self.doorWarp = true -- door SFX + PlayerStepOutFromDoor walk-out
  self:startWarpTo(destMap, x, y, facing)
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
  Game.save.forcedBike = nil
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
          self.warpEntryCell = nil
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

-- Replace a map block (Victory Road barriers, Cut trees) and redraw.
function OverworldState:replaceBlock(bx, by, block)
  self.map:setBlock(bx, by, block)
  self.map.renderer:rebuild()
  Runtime.emit("world.block_replaced",
    { mapId = self.map.id, bx = bx, by = by, block = block })
end

-- A map's `variablesprite` callback usually runs after its objects have been
-- built, so re-resolve everything still pointing at the slot it just filled.
function OverworldState:refreshVariableSprite(slot)
  local id = string.format("SPRITE_VAR_%02d", slot)
  for _, npc in pairs(self.npcPool or {}) do
    if npc.def and npc.def.sprite == id then npc:refreshSprite(Game.data) end
  end
end

-- -------------------------------------------------------------------------
-- scripted movement
-- -------------------------------------------------------------------------

function OverworldState:scriptMove(entity, dir, tiles, onDone)
  table.insert(self.scriptMoves, {
    entity = entity, dir = dir, remaining = tiles, onDone = onDone,
  })
end

-- A step-in-place beat: the entity plays one walk-cycle animation (16
-- frames) without translating, keeping its current facing.  Ports the
-- NPC_CHANGE_FACING movement byte (engine/overworld/movement.asm
-- ChangeFacingDirection -> zero-delta TryWalking), used for Oak marching
-- on the lab door mat at the tail of RLEList_ProfOakWalkToLab.
function OverworldState:marchInPlace(entity, onDone)
  table.insert(self.scriptMoves, {
    entity = entity, inPlace = true, remaining = 1, onDone = onDone,
  })
end

-- Advance scripted moves in two phases so a chained step (a new move
-- queued by a completing move's onDone) begins the SAME frame the
-- previous one ends -- back-to-back 16-frame tiles like the GB's
-- simulated-joypad / NPC scripted movement, with no idle frame between
-- tiles.  Phase 1 retires finished moves (which may chain new ones);
-- phase 2 then starts every not-yet-moving move.
function OverworldState:updateScriptMoves()
  local i = 1
  while i <= #self.scriptMoves do
    local mv = self.scriptMoves[i]
    if not mv.entity.moving and mv.remaining <= 0 then
      table.remove(self.scriptMoves, i)
      if mv.onDone then mv.onDone() end
      -- don't advance i: a move chained by onDone may now sit at i
    else
      i = i + 1
    end
  end
  for _, mv in ipairs(self.scriptMoves) do
    local e = mv.entity
    if not e.moving and mv.remaining > 0 then
      if mv.inPlace then
        e.moving = true
        e.marching = true
        e.progress = 0
      else
        e.facing = mv.dir
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
      -- the jingle flash recolors the machine sprites in place
      -- (FlashSprite8Times XORs rOBP1; the sprites never disappear):
      -- ha.visible == false is the flashed half of each beat, drawn with
      -- the light/dark shades swapped instead of skipped
      local shader
      if not ha.visible then
        shader = PaletteFX.shader()
        if shader then
          PaletteFX.sendColors(shader,
            PaletteFX.permute(PaletteFX.GRAYS, HEAL_FLASH_MAP))
          love.graphics.setShader(shader)
        end
      end
      -- TileRenderer windows with -floor(cam), so the overlay must use the
      -- same snap or a fractional camera (odd fill/tilt view sizes) parks
      -- the balls a pixel off the machine tiles
      local ox = ha.px - 64 - math.floor(cam.x)
      local oy = ha.py - 64 - math.floor(cam.y)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, self.healMachineQuads[1], ox + 44, oy + 20)
      for i = 1, math.min(ha.lit, #HEAL_BALL_XY) do
        local b = HEAL_BALL_XY[i]
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
    if bubble and bubble.path then
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
    local pw, ph = love.graphics.getDimensions()
    local pscale = Zoom.scale(Game.renderer:fitScale())
    local ctx = {
      state = self, cam = cam, vw = vw, vh = vh, bgY = bgY,
      width = pw, height = ph, scale = pscale,
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
    for _, e in ipairs(self.entities) do
      if not (self.flyAnim and e == self.player) then
        e:draw(cam.x, cam.y)
        -- tall grass overdraws the sprite's feet (GB sprite priority);
        -- the overdraw is BG tiles, so it rides the shake offset too
        love.graphics.setColor(1, 1, 1, 1)
        if self.map:isGrassCell(e.cellX, e.cellY) then
          self.map.renderer:drawCellBottom(e.cellX, e.cellY, cam.x, bgY)
          if grassColors then
            self.map.renderer:markCellBottomRedraw(e.cellX, e.cellY,
                                                   cam.x, bgY, grassColors)
          end
        end
        if e.targetX and self.map:isGrassCell(e.targetX, e.targetY) then
          self.map.renderer:drawCellBottom(e.targetX, e.targetY, cam.x, bgY)
          if grassColors then
            self.map.renderer:markCellBottomRedraw(e.targetX, e.targetY,
                                                   cam.x, bgY, grassColors)
          end
        end
      end
    end
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
      if not (self.flyAnim and e == self.player) then
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

end

-- screen-space overlays: drawn to the UI canvas at normal scale
function OverworldState:drawUI()
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
