-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native semantic actor state. Renderer resources, mod caches and callbacks
-- stay outside the payload; native factories recreate their owning objects.
local NPC = require("src.world.NPC")
local A = {}
local DIR = { up = true, down = true, left = true, right = true }
local function names(words)
  local out = {}
  for key in words:gmatch("%S+") do
    out[key] = true
  end
  return out
end
local ACTOR = names([[
 cellX cellY px py facing spawnFacing moving progress stepFlip frozen timer
 wanders spins roamDirs roamOriginX roamOriginY roamRangeX roamRangeY turns
 looksAround rotates sequence sequenceAt gen3MovementType gen3Elevation elevation
 fixedFrame hidden gen3Hidden big buried passable reflects reflectStill
 stepDir targetX targetY stepFrames stepFramesCur stepFramesPrev scriptStepLen
 hopStep marching sliding shiftPx spriteOffset hopFrames hopTotal
 shakeFrames goalX goalY idle idleClock optionalFollower follower pikachuFollower
 gen3ScriptFrozen gen3Decoration berryTreeId berryVisualEmpty followKey followSpecies
 running g4DirLocked g4Paused gen4Follower hgssFollowMon vsSeekerReady
]])
local PLAYER = names([[
acroBike acroHopClock acroTrick animClock bikeId bikeStepFrames blobImage blobPath blobQuads
bobTimer bumpFrames cellX cellY compatWalkInPlace facing fieldMove fieldMoveId fieldMovePose
fieldMoveSprite fishing freeInput freeWalking gen4Fish hopClock hopFrames hopTotal inputLocked
marching moving onBike player progress px py reflectProbeTick reflectStill reflects runId runSprite
runStepFrames running shadowGen3 spinDrop spinFrames spinRise spinTimer spinTotal spinning stairExit
stepFlip stepFrames stepFramesCur stepLanded surfId surfing surfingPikachu targetX targetY turnArmed
turnFrames turnTimer underId underwaterSprite walkId
]])
local WORLD = names([[
BugContest Collision Encounter FieldDefaults Gen2EncounterRules Gen2MomShopping Gen2PhoneService
Gen2PlayerState Gen2StepEvents Gen3Decorations Gen3Elevation Gen3FieldMove Gen3FieldRules Gen3Flash
Gen3Gates Gen3MapPopup Gen3MapPreviewFRLG Gen3MirageTower Gen3Regi Gen3Roamers Gen3ScreenFx
Gen3SecretBase Gen3SweetScent Gen3Weather Gen4AreaPopup Gen4BerryPatches Gen4BikeRamp Gen4Blackout
Gen4CyclingRoad Gen4DistPlatforms Gen4DistSurface Gen4EmoteDraw Gen4FieldFx Gen4FieldMoves
Gen4Fishing Gen4FishingTask Gen4Fly Gen4FogWeather Gen4Follower Gen4HoneyTrees Gen4MovementTypes
Gen4PalPark Gen4PropOneShot Gen4Radar Gen4Roamers Gen4Snow Gen4StrengthPush Gen4SurfMount
Gen4TileScripts Gen4Underground Gen4VsSeeker Gen4WaterfallRide Gen4WildLead Gen5Dowsing
Gen5DriftveilGym Gen5FieldRules Gen5FishingLure Gen5Phenomena Gen5PostWarp Gen5Quicksand Gen5Warps
Gen5WildTables HgssApricorns HgssBugContest HgssDowsing HgssFollowMon HgssLegendCutscene
HgssModelObjects HgssPartnerFacings LiveMaps Map MapLoader NPC OptionalFollower PikachuFollower
Player RoamMons VsSeeker Warp _reflectFrom _reflectSeen _reflectSet _rippleLife _rippleSprite
_sparkleShow _sparkleSprite _worldAim _worldCover _worldDrawEntity _worldEntityLoop _worldFxBird
_worldFxCutTree _worldFxDust _worldFxEmote _worldFxHeal _worldFxRadar _worldFxRod
_worldFxSSAnneSmoke _worldFxSSAnneWake _worldFxSparkle _worldFxWater _worldReflectors _worldRise
actors arriveWarp attributes backupWarp battleActive behaviourOf berryClock bgShakeY birdSprite
blacked_out block_replaced blocks_replaced boulderTried boulder_moved brailleBox brailleImage
braillePath brailleQuads bridgeDown bugContestLeaving bugContestNotice builtFor bumpCooldown
cameraPan castStore cellSerial checkLedgeHop collisionAt continuingSave coordAskedSerial coordFired
course crackedFloor cutAnim cutBlocks cutTreeImg cutTreeQuads dark def delaySfx digWarp diveSaidWhy
doorWarp dropDepth droppingScriptMoves dustAnim dwFloor dwPose dwSurface elevationAt elevationFrom
elevationHeights elevationLayers elevationLevels emote emoteImg emoteQuads engaging escalatorWay
extraEmotes fieldTasks fishPose fishing flyAnim flyBirdImg flyBirdQuads flyDest flyMonImg forcedWarp
frameScriptThisTick frlgFloorWindow frlgSpin frlgSpinMap g2MomCallPending g3MirageCrumbles
g3MirageTower g3Orb g3Shake g4WildDefeated gen2CoordVisit gen2EncounterVisit gen2StepVisit
gen3Blocking gen3CastReport gen3Current gen3DecorCells gen3DecorNPCs gen3Decorate gen3DrawElevation
gen3Elevator gen3EmoteImages gen3EmoteQuads gen3GateArt gen3GateQuads gen3GateSwing gen3Gates
gen3HealArt gen3Locked gen3MapWeatherPending gen3PcScreen gen4Camera gen4CoinWindow gen4Continuing
gen4EmoteImages gen4EncounterAttempts gen4FieldFx gen4FieldFxShake gen4FieldResumed gen4FollowTrail
gen4MoneyWindow gen4Radar gen4RoamerSlot gen4SaveInfo gen4Shadows gen4ShakeOffset
gen4ShardCostWindow gen4Waterfall gen4WeatherUnnamed gen5ArrivalMap gen5ArrivalX gen5ArrivalY
gen5Dowsing gen5LiftRun gen5QueuedEntry gen5SeamPending gen5Spot grassImage grassPath grassQuads
gymDoorSlide hasCollisionCells hasElevation healAnim healMachineImg healMachineQuads heightAt
heightCells heldDir hgssContestWarned hgssDowsing hgssFollowFrozen hgssFollowPending hgssFollowTalk
hgssFollowTick hgssFollowTrail hgssLastFacing hgssStepsCounted hgssTurnFrames iceSlide interacted
joyLatch keepMusicOnce lastCellMapId lastCellX lastCellY lastOutdoor lavaridgeLaunch layerAt layerOf
layerTypeOf legendLeavesDraw lockedFrames logSunk luckySlot mapId mapNameSign marchers metatileAt
muddySlide ndsWarpLanding neighborHops neighborReachBuiltH neighborReachBuiltW neighborReachH
neighborReachW neighborViewH neighborViewW noWildEncounters npcMoveLocks npcPlacement npcResumeCell
npc_spawned objectTod objectTodBit openRegionMap originOf parallelQueue parallelRunners partyKnows
pendingLiftAttach pendingScripts pendingSeamMusic pikaHop pikaPicImg pikaPicPath pikachuBillsScene
playerAt poisonFlash quakeFrames reflectProbe reflectProbe2 reloadMap reportedOffMapWalk rippleCells
ripples rodImg rodQuads runGateSaid scriptMove scriptMoves sgbWorldZones signLandmark smokeImg
snowDraw snowWarned sparkles spinSlide spotHush ssAnneDepartureFx ssAnneSmokeImg ssAnneSmokeQuads
ssAnneWakeImg ssAnneWakeQuads standingOnWarp stepped stoneTable strengthActive stuckFrames talk
teleportOut tick tileAnimOverride tod todSteps tod_changed topIsAbovePlayer trainer_engaged
transitioning turningDirection viewH viewW warpEntryCell waterAnim weatherAt weatherDraw
weatherFrame weatherName weatherShown weatherStage whirlHold whirlSpin widthCells wildCooldown
]])
local BOOLEANS = names([[
 moving stepFlip frozen wanders looksAround hidden gen3Hidden big buried passable reflects reflectStill
 hopStep marching sliding optionalFollower follower pikachuFollower gen3ScriptFrozen
 berryVisualEmpty running g4DirLocked g4Paused gen4Follower hgssFollowMon vsSeekerReady
 turnArmed inputLocked surfing
]])
local TABLES = names("roamDirs turns sequence idle spriteOffset")
local STRINGS = names("facing spawnFacing stepDir spins rotates berryTreeId gen3Decoration followKey followSpecies")
local function typed(state)
  for key, value in pairs(state) do
    if key == "followSpecies" or key == "gen3Decoration" or key == "berryTreeId" then
      if type(value) ~= "number" and type(value) ~= "string" then
        return false
      end
    elseif BOOLEANS[key] then
      if type(value) ~= "boolean" then
        return false
      end
    elseif TABLES[key] then
      if type(value) ~= "table" then
        return false
      end
    elseif STRINGS[key] then
      if type(value) ~= "string" then
        return false
      end
    elseif type(value) ~= "number" then
      return false
    end
  end
  for _, key in ipairs({ "facing", "spawnFacing", "stepDir" }) do
    if state[key] ~= nil and not DIR[state[key]] then
      return false
    end
  end
  for _, key in ipairs({ "roamDirs", "turns", "sequence" }) do
    if state[key] then
      for _, dir in ipairs(state[key]) do
        if not DIR[dir] then
          return false
        end
      end
    end
  end
  if state.spins and not ({ SPIN_CW = true, SPIN_CCW = true, SPIN_SLOW = true, SPIN_FAST = true })[state.spins] then
    return false
  end
  if state.rotates and state.rotates ~= "cw" and state.rotates ~= "ccw" then
    return false
  end
  if state.idle then
    local idle = state.idle
    if
      not ({ wait = true, bounce = true, walk = true, shuffle = true, spin = true })[idle.kind]
      or type(idle.frames) ~= "number"
    then
      return false
    end
    for _, key in ipairs({ "tick", "phase" }) do
      if idle[key] ~= nil and type(idle[key]) ~= "number" then
        return false
      end
    end
  end
  return true
end
local function semantic(object, keys, clone)
  local out = {}
  for key in pairs(keys) do
    local v = rawget(object, key)
    if v ~= nil and type(v) ~= "function" then
      local ok, detached = pcall(clone, v)
      if ok then
        out[key] = detached
      end
    end
  end
  return out
end
function A.detach(world)
  for key in pairs(WORLD) do
    if type(rawget(world, key)) ~= "function" then
      world[key] = nil
    end
  end
end
local function selected(object, keys)
  local out = {}
  for key in pairs(keys) do
    out[key] = object[key]
  end
  return out
end
local function assign(object, values, keys)
  for key in pairs(keys) do
    if type(rawget(object, key)) ~= "function" then
      object[key] = values[key]
    end
  end
end
local function array(list, fn)
  local out = {}
  for i, v in ipairs(list or {}) do
    out[i] = fn(v)
  end
  return out
end
local function integer(v)
  return type(v) == "number" and v % 1 == 0 and math.abs(v) <= 1000000
end
local function values(v, keys)
  if type(v) ~= "table" then
    return false
  end
  for key in pairs(v) do
    if not keys[key] then
      return false
    end
  end
  return true
end
local function position(v)
  return integer(v.cellX)
    and integer(v.cellY)
    and type(v.px) == "number"
    and type(v.py) == "number"
    and DIR[v.facing] == true
    and type(v.moving) == "boolean"
    and type(v.progress) == "number"
    and (not v.moving or (integer(v.targetX) and integer(v.targetY)))
end
local function definition(def)
  return type(def) == "table"
    and integer(def.index)
    and type(def.sprite) == "string"
    and integer(def.x)
    and integer(def.y)
end

function A.capture(game, clone)
  local world = game.overworld
  local records, seen = {}, {}
  local Yellow = require("src.world.PikachuFollower")
  local function actor(npc)
    if seen[npc] then
      return seen[npc]
    end
    assert(
      getmetatable(npc) == NPC and type(npc.id) == "string" and definition(npc.def),
      "actor has no native reconstruction factory"
    )
    assert(not npc.shakeDone and not npc.onDone, "actor has an opaque pending callback")
    local id = npc.id
    assert(not records[id], "duplicate native actor identity")
    seen[npc], records[id] = id, true
    local mapId, index = id:match("^(.*)_obj_(%d+)$")
    assert(mapId and tonumber(index) == npc.def.index and game.data.maps[mapId], "actor home map is unavailable")
    local factory = "npc"
    if Yellow._checkpointOwns and Yellow._checkpointOwns(npc) then
      factory = "yellow"
    elseif npc.optionalFollower then
      factory = "optional"
    else
      assert(rawget(npc, "walkPhase") == nil, "actor has an opaque pose override")
    end
    local state = selected(npc, ACTOR)
    assert(position(state), "actor motion is inconsistent")
    local g4 = npc.g4Move and {}
    if g4 then
      for k, v in pairs(npc.g4Move) do
        if k ~= "row" and k ~= "leader" then
          g4[k] = v
        end
      end
    end
    records[id] = {
      map = mapId,
      def = npc.def,
      state = state,
      factory = factory,
      g4 = g4,
      leader = npc.g4Move and npc.g4Move.leader and actor(npc.g4Move.leader),
      appearance = npc.sprite and npc.sprite.def and npc.sprite.def.id,
    }
    seen[npc] = id
    return id
  end
  local pool = {}
  for id, npc in pairs(world.npcPool or {}) do
    assert(id == npc.id, "native pool identity differs")
    pool[id] = actor(npc)
  end
  local locals = array(world.npcs, actor)
  local entities = array(world.entities, function(v)
    return v == world.player and "@player" or actor(v)
  end)
  local neighbors = array(world.neighbors, function(nb)
    return { map = nb.map.id, ox = nb.ox, oy = nb.oy, peers = array(nb.peers, actor) }
  end)
  local ghosts = array(world.ghosts, function(g)
    return { actor = actor(g.npc), map = g.map.id, ox = g.ox, oy = g.oy }
  end)
  local maps = {}
  local function remember(map)
    maps[map.id] = {
      blockPatch = map.blockPatch,
      gridRevision = map.gridRevision,
      collisionPatch = map.collisionPatch,
      elevationPatch = map.elevationPatch,
      shutCells = map.shutCells,
      layoutOutside = map.layoutOutside,
      gen3LayoutOverride = map.gen3LayoutOverride,
    }
  end
  remember(world.map)
  for _, nb in ipairs(world.neighbors or {}) do
    remember(nb.map)
  end
  local snapshot = clone({
    maps = maps,
    schema = 1,
    movementRng = { seed = require("src.world.Gen4MovementTypes")._checkpointSeed() },
    records = records,
    pool = pool,
    locals = locals,
    entities = entities,
    neighbors = neighbors,
    ghosts = ghosts,
    follower = world.follower and actor(world.follower),
    followerTrail = world.followerTrail,
    pikachuTrail = world.pikachuTrail,
    sharedTrail = world.followerTrail ~= nil and world.followerTrail == world.pikachuTrail,
    player = semantic(world.player, PLAYER, clone),
    world = semantic(world, WORLD, clone),
  })
  assert(A.validate(game, snapshot), "native actor state has unsupported fields")
  return snapshot
end

function A.validate(game, snapshot)
  if
    type(snapshot) ~= "table"
    or snapshot.schema ~= 1
    or type(snapshot.records) ~= "table"
    or type(snapshot.pool) ~= "table"
    or not values(snapshot.player, PLAYER)
    or (snapshot.movementRng and (type(snapshot.movementRng) ~= "table" or (snapshot.movementRng.seed ~= nil and (type(
      snapshot.movementRng.seed
    ) ~= "number" or snapshot.movementRng.seed % 1 ~= 0 or snapshot.movementRng.seed < 0 or snapshot.movementRng.seed >= 4294967296))))
    or not position(snapshot.player)
    or snapshot.player.moving
    or not values(snapshot.world, WORLD)
  then
    return false
  end
  for _, key in ipairs({ "engaging", "strengthActive", "noWildEncounters", "standingOnWarp" }) do
    local value = snapshot.world[key]
    if value ~= nil and type(value) ~= "boolean" then
      return false
    end
  end
  if type(snapshot.maps) ~= "table" then
    return false
  end
  for id, patch in pairs(snapshot.maps) do
    local def = game.data.maps[id]
    if not def or type(patch) ~= "table" then
      return false
    end
    if patch.gridRevision ~= nil and not integer(patch.gridRevision) then
      return false
    end
    for _, key in ipairs({ "blockPatch", "collisionPatch", "elevationPatch" }) do
      if type(patch[key]) ~= "table" then
        return false
      end
      for cell, value in pairs(patch[key]) do
        if
          not integer(cell)
          or cell < 1
          or cell > (def.width or 0) * (def.height or 0)
          or not integer(value)
          or value < 0
        then
          return false
        end
      end
    end
  end
  for id, r in pairs(snapshot.records) do
    if
      type(id) ~= "string"
      or type(r) ~= "table"
      or not definition(r.def)
      or (r.appearance and not (game.data.sprites and game.data.sprites[r.appearance]))
      or not game.data.maps[r.map]
      or not values(r.state, ACTOR)
      or not typed(r.state)
      or not position(r.state)
      or (r.factory ~= "npc" and r.factory ~= "yellow" and r.factory ~= "optional")
    then
      return false
    end
    if r.leader and (not r.g4 or not snapshot.records[r.leader]) then
      return false
    end
    if r.g4 then
      for key, value in pairs(r.g4) do
        if key == "family" then
          if type(value) ~= "string" then
            return false
          end
        elseif key == "started" or key == "done" or key == "back" then
          if type(value) ~= "boolean" then
            return false
          end
        elseif type(value) ~= "number" then
          return false
        end
      end
    end
    local map, index = id:match("^(.*)_obj_(%d+)$")
    if map ~= r.map or tonumber(index) ~= r.def.index then
      return false
    end
    if r.factory == "yellow" and require("src.core.GameVersion").generation() ~= 1 then
      return false
    end
    if r.g4 and (type(r.g4) ~= "table" or not require("src.world.Gen4MovementTypes").row(r.g4.type, r.g4.family)) then
      return false
    end
  end
  local function refs(list, player)
    if type(list) ~= "table" then
      return false
    end
    local n = 0
    for i, id in pairs(list) do
      n = n + 1
      if
        type(i) ~= "number"
        or i % 1 ~= 0
        or i < 1
        or i > #list
        or not (snapshot.records[id] or (player and id == "@player"))
      then
        return false
      end
    end
    return n == #list
  end
  if not refs(snapshot.locals) or not refs(snapshot.entities, true) then
    return false
  end
  for id, ref in pairs(snapshot.pool) do
    if id ~= ref or not snapshot.records[ref] then
      return false
    end
  end
  if snapshot.follower and not snapshot.records[snapshot.follower] then
    return false
  end
  if type(snapshot.neighbors) ~= "table" or type(snapshot.ghosts) ~= "table" then
    return false
  end
  for _, nb in ipairs(snapshot.neighbors) do
    if not game.data.maps[nb.map] or type(nb.ox) ~= "number" or type(nb.oy) ~= "number" or not refs(nb.peers) then
      return false
    end
  end
  for _, g in ipairs(snapshot.ghosts) do
    if
      not snapshot.records[g.actor]
      or not game.data.maps[g.map]
      or type(g.ox) ~= "number"
      or type(g.oy) ~= "number"
    then
      return false
    end
  end
  return true
end

function A.apply(game, snapshot, clone)
  assert(A.validate(game, snapshot), "invalid native actor snapshot")
  local world = game.overworld
  -- Detach before assigning: native update code must never mutate caller data.
  snapshot = clone(snapshot)
  local actors = {}
  for id, r in pairs(snapshot.records) do
    local npc
    if r.factory == "yellow" then
      npc = require("src.world.PikachuFollower")._checkpointCreate(game, world, r.def.x, r.def.y, r.state.facing)
    elseif r.factory == "optional" then
      npc = require("src.world.OptionalFollower")._checkpointCreate(game, world)
    else
      local def = clone(r.def)
      def.sprite = r.appearance or def.sprite
      npc = NPC.new(game.data, r.map, def)
    end
    npc.id, npc.def = id, r.def
    assign(npc, r.state, ACTOR)
    npc.g4Move = r.g4
    if r.g4 then
      r.g4.row = assert(require("src.world.Gen4MovementTypes").row(r.g4.type, r.g4.family))
    end
    actors[id] = npc
  end
  for id, r in pairs(snapshot.records) do
    if r.leader then
      assert(actors[id].g4Move, "native partner state is missing").leader = assert(actors[r.leader])
    end
  end
  local function get(id)
    return id == "@player" and world.player or assert(actors[id])
  end
  world.npcPool = {}
  for id, ref in pairs(snapshot.pool) do
    world.npcPool[id] = get(ref)
  end
  world.npcs = array(snapshot.locals, get)
  world.entities = array(snapshot.entities, get)
  local byMap = {}
  for i, nb in ipairs(snapshot.neighbors) do
    local fresh = world.neighbors[i]
    assert(
      fresh and fresh.map.id == nb.map and fresh.ox == nb.ox and fresh.oy == nb.oy,
      "native connection topology changed"
    )
    fresh.peers = array(nb.peers, get)
    byMap[nb.map] = fresh
  end
  assert(#world.neighbors == #snapshot.neighbors, "native connection topology changed")
  world.ghosts = array(snapshot.ghosts, function(g)
    local nb = assert(byMap[g.map], "ghost has no native connection")
    return { npc = get(g.actor), map = nb.map, ox = g.ox, oy = g.oy, nb = nb, peers = nb.peers }
  end)
  world.follower = snapshot.follower and get(snapshot.follower) or nil
  world.followerTrail, world.pikachuTrail = snapshot.followerTrail, snapshot.pikachuTrail
  if snapshot.sharedTrail then
    world.pikachuTrail = world.followerTrail
  end
  assign(world.player, snapshot.player, PLAYER)
  assign(world, snapshot.world, WORLD)
  local maps = { [world.map.id] = world.map }
  for _, nb in ipairs(world.neighbors) do
    maps[nb.map.id] = nb.map
  end
  for id, values in pairs(snapshot.maps or {}) do
    local map = assert(maps[id], "native patched map is absent")
    for _, key in ipairs({
      "blockPatch",
      "collisionPatch",
      "elevationPatch",
      "shutCells",
      "layoutOutside",
      "gen3LayoutOverride",
    }) do
      map[key] = values[key]
    end
    -- Older native map owners rebuild directly without a revision service.
    if map.noteGridChange then map:noteGridChange() end
    map.gridRevision = values.gridRevision
    map.renderer:rebuild()
  end
  world.cast = nil
  require("src.world.Gen4MovementTypes")._checkpointReset(snapshot.movementRng and snapshot.movementRng.seed)
end
return A
