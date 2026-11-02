-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S FERRY: `PlayBoatCutscene <travelDir> <exitDir> <mapHeader> <x> <z>`
-- (0x23D, "bbwww" -- two bytes and three halfwords, all literal), the
-- TakeShipFrom*/TakeShipTo* macros of asm/macros/scrcmd.inc:
--
--   TakeShipFromCanalave e, map, x, z   travelDir 3 NORTH_TO_SOUTH
--   TakeShipFromSnowpoint e, map, x, z  travelDir 2 WEST_TO_EAST
--   TakeShipToCanalave                  travelDir 0, DIR_WEST, CANALAVE, 44, 750
--   TakeShipToSnowpoint                 travelDir 1, DIR_NORTH, SNOWPOINT, 356, 246
--
-- FieldSystem_PlayBoatCutscene (pokeplatinum src/cutscenes/boat_cutscene/
-- boat_cutscene.c), ported state for state.  On setting off FROM Canalave or
-- Snowpoint the ship you boarded sails out on the field first:
--
--   NORTH_TO_SOUTH  the `regular_ship` prop colliding with a hitbox at the
--                   player (+1, -3, 3 x 6 tiles); goal 25 tiles; the
--                   Canalave drawbridges (`canalave_bridge_left` /
--                   `_right`) loaded as one-shots (1 loop) and played once
--                   the ship has gone 14 tiles, with SEQ_SE_DP_SHIP03; the
--                   camera pans x +1 a frame up to 2 tiles; SEQ_SE_DP_SHIP02
--   WEST_TO_EAST    the `screw_steamship_spiral` prop at (-2, +2, 6 x 3);
--                   goal 12 tiles; the camera pans z +1/2 a frame up to 3
--   the other two   straight to the fade
--
-- MoveBoatToGoal, a field frame each: the prop (MapProp_SetPosition) and the
-- camera's target (Camera_TrackTarget on a copy of the player's position,
-- released from the player) move together by `speed` along the travel axis
-- -- z decreasing for NORTH_TO_SOUTH and x increasing for WEST_TO_EAST --
-- `speed` starting at 1/4 and, after 24 frames, one unit more (it is then >=
-- 1 and stays); done once the distance travelled reaches the goal (with the
-- bridges, also once both bridges' one loop has ended).  Then:
--
--   FADE_OUT_START  StartScreenFade(out, black, 6, 1); Sound_FadeOutBGM(0, 6)
--   FADE_OUT_END    both done: the bridge one-shots unloaded, the map finished
--   PLAY_TRAVEL     the app (src/ui/Gen4BoatTravelScene.lua) until it returns
--   MAP_TRANSITION  FieldTask_ChangeMapToLocation(map, -1, x, z, exitDir)
--   FADE_IN         FieldBGM_PlayForMapHeader; the new map faded in
--
-- (CheckBridgeReached is called with its two distances swapped, so "reached"
-- reads distanceTraveled >= bridgeDistance -- the ship clears 14 tiles.)
-- The scene's BGM is left as it is: Sound_SetSceneAndPlayBGM(SUB_64,
-- SEQ_NONE) loads the sub-scene's sounds and starts no song.
--
-- Installed by Gen4ScriptVM (`install`), after the row it replaces.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}
M.TICKS_PER_FRAME = 2
M.TILE = 16                                   -- MAP_OBJECT_TILE_SIZE, world units
M.S2N, M.E2W, M.W2E, M.N2S = 0, 1, 2, 3       -- constants/boat_cutscene.h
M.SHIP = "regular_ship.nsbmd"
M.STEAMSHIP = "screw_steamship_spiral.nsbmd"
M.BRIDGES = { "canalave_bridge_left.nsbmd", "canalave_bridge_right.nsbmd" }
M.FALLBACK = { ["regular_ship.nsbmd"] = 34, ["screw_steamship_spiral.nsbmd"] = 538,
               ["canalave_bridge_left.nsbmd"] = 31, ["canalave_bridge_right.nsbmd"] = 32 }
-- TerrainCollisionHitbox_Init(x, z, xOffset, zOffset, width, depth)
M.HITBOX = { [3] = { 1, -3, 3, 6 }, [2] = { -2, 2, 6, 3 } }
M.GOAL = { [3] = 25, [2] = 12 }               -- tiles
M.BRIDGE_AT = 14                              -- tiles, NORTH_TO_SOUTH only
M.FADE = 6                                    -- StartScreenFade 6 steps x 1
M.SE_DEPART = "SEQ_SE_DP_SHIP02"
M.SE_BRIDGE = "SEQ_SE_DP_SHIP03"

local function gameData(ctx)
  return (ctx.game and ctx.game.data) or (package.loaded["src.core.Game"] or {}).data
end
local function se(ctx, name)
  local data = gameData(ctx)
  pcall(function() require("src.core.Sound").playSe(data, name) end)
end
local function groundOf(ctx)
  local ow = ctx and ctx.overworld
  return ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground or nil
end
function M.propId(name)
  local okA, A = pcall(require, "src.import.Gen4Archives")
  local id = okA and A.find and A.find("/fielddata/build_model/build_model.narc", name) or nil
  return id or M.FALLBACK[name]
end

-- every placed object of `model` with its MAP-unit position (16 a tile, from
-- the map's top-left) -- the inverse of Gen4Ground:runtimePropsFor
function M.placed(ground, model)
  local out = {}
  local grid, terrain = ground and ground.grid, ground and ground.terrain
  local chunks = terrain and terrain.chunks
  if not (grid and grid.land and chunks) then return out end
  local U = terrain.chunkUnits or 512
  for i = 1, #grid.land do
    local land = grid.land[i]
    local cx, cy = (i - 1) % grid.width, math.floor((i - 1) / grid.width)
    local record = chunks[land]
    local objects = (record and record.objects) or {}
    for k = 1, #objects do
      local o = objects[k]
      if o.archive ~= "fldeff" and o.model == model then
        out[#out + 1] = { object = o,
          x = (o.x or 0) + cx * U + U / 2 - (ground.offsetX or 0),
          z = (o.z or 0) + cy * U + U / 2 - (ground.offsetY or 0) }
      end
    end
  end
  return out
end

-- FieldSystem_FindCollidingLoadedMapPropByModelID: the prop of `model` nearest
-- the hitbox's centre, inside a few tiles of it
function M.findBoat(ground, model, px, pz, box)
  local cx = px + (box[1] + box[3] / 2) * M.TILE
  local cz = pz + (box[2] + box[4] / 2) * M.TILE
  local best, bestD
  for _, p in ipairs(M.placed(ground, model)) do
    local d = math.abs(p.x - cx) + math.abs(p.z - cz)
    if not bestD or d < bestD then best, bestD = p, d end
  end
  if best and bestD <= 16 * M.TILE then return best end
  return nil
end

-- block the script on `step`, called once per FIELD frame until it says done
local function waitFrames(ctx, step)
  local runner = ctx.runner
  if not runner then
    for _ = 1, 100000 do if step() then return end end
    return
  end
  local tick = 0
  runner.waitingCheck = function()
    tick = tick + 1
    if tick % M.TICKS_PER_FRAME ~= 0 then return false end
    return step() and true or false
  end
  runner:yield()
end

-- the field half's state, for probes
M.last = nil

-- the ship sailing out (states START_WITH/WITHOUT_BRIDGE); returns when it is
-- time to fade
local function sailOut(ctx, ow, ground, travelDir, log)
  local model = M.propId(travelDir == M.N2S and M.SHIP or M.STEAMSHIP)
  local p = ow.player
  local px, pz = (p.cellX or 0) * M.TILE + 8, (p.cellY or 0) * M.TILE + 8
  local boat = ground and M.findBoat(ground, model, px, pz, M.HITBOX[travelDir])
  if not boat then
    -- GF_ASSERT(FALSE): the cartridge frees the task and the script runs on
    Logger.warn("boat cutscene: no %s prop at the player on %s -- the ship does not sail out",
      tostring(model), tostring(ow.map and ow.map.id))
    log.noBoat = true
    return false
  end
  local object = boat.object
  local live = { dx = 0, dy = 0, dz = 0 }
  object.live = live
  log.boat = { model = model, x = boat.x, z = boat.z }
  -- Camera_ReleaseTarget + Camera_TrackTarget(&cameraPos), cameraPos a copy
  -- of the player's position
  local cam = { cellX = p.cellX, cellY = p.cellY, px = p.px or p.cellX * M.TILE,
                py = p.py or p.cellY * M.TILE, hidden = true, boatCamera = true }
  ow.gen4Camera = cam
  local goal = M.GOAL[travelDir] * M.TILE
  local speed, speedTick, travelled, adjust = 1 / 4, 0, 0, 0
  local bridges
  if travelDir == M.N2S then
    -- FieldSystem_LoadCanalaveBridgeAnimation: tags 1 and 2, one loop each
    bridges = {}
    local OneShot = require("src.world.Gen4PropOneShot")
    for i, name in ipairs(M.BRIDGES) do
      local id = M.propId(name)
      local placed = ground and M.placed(ground, id)[1]
      local records = ground and require("src.script.Gen4LiftCommands").records(ground, id)
      local record = records and records[1]
      if placed and record then
        bridges[i] = { object = placed.object, record = record, tag = "boatBridge" .. i }
      else
        Logger.warn("boat cutscene: no %s on %s", name, tostring(ow.map and ow.map.id))
      end
    end
    bridges.slots = OneShot.all(ow)
    se(ctx, M.SE_DEPART)
  end
  local reached = false
  local frames = 0
  log.bridges = bridges and #bridges or 0
  waitFrames(ctx, function()
    frames = frames + 1
    -- BoatCutscene_PanStartingCamera
    if travelDir == M.N2S then
      if adjust < M.TILE * 2 then cam.px = cam.px + 1; adjust = adjust + 1 end
    elseif travelDir == M.W2E then
      if adjust < M.TILE * 3 then cam.py = cam.py + 0.5; adjust = adjust + 0.5 end
    end
    -- BoatCutscene_MoveBoatToGoal
    if travelDir == M.N2S then live.dz = live.dz - speed; cam.py = cam.py - speed
    elseif travelDir == M.W2E then live.dx = live.dx + speed; cam.px = cam.px + speed
    elseif travelDir == M.S2N then live.dz = live.dz + speed; cam.py = cam.py + speed
    else live.dx = live.dx - speed; cam.px = cam.px - speed end
    if speed < 1 then
      speedTick = speedTick + 1
      if speedTick >= 24 then speed = speed + 1; speedTick = 0 end
    end
    travelled = travelled + speed
    local goalReached = goal <= travelled
    if not bridges then return goalReached end
    if not reached then
      if travelled >= M.BRIDGE_AT * M.TILE then
        reached = true
        log.bridgeAt = frames
        for i = 1, 2 do
          local b = bridges[i]
          if b then
            bridges.slots[b.tag] = { tag = b.tag, model = "boatBridge", action = "raise", object = b.object,
              animation = b.record.member, frames = math.max(1, math.floor(tonumber(b.record.frames) or 1)), frame = 0 }
          end
        end
        se(ctx, M.SE_BRIDGE)
      end
      return false
    end
    local done = goalReached
    for i = 1, 2 do
      local slot = bridges[i] and bridges.slots[bridges[i].tag]
      if slot and slot.frame < slot.frames then done = false end
    end
    return done
  end)
  log.sailFrames = frames
  log.travelled = travelled
  return true, object, bridges
end

function Commands.g4_boat_cutscene(ctx, travelDir, exitDir, header, x, z)
  local ow = ctx.overworld
  if not ow then return end
  -- every operand is a literal (ScriptContext_ReadByte / _ReadHalfWord)
  travelDir = math.floor(tonumber(travelDir) or 0)
  local log = { travelDir = travelDir, from = ow.map and ow.map.id }
  M.last = log
  local ground = groundOf(ctx)
  local object, bridges
  if travelDir == M.N2S or travelDir == M.W2E then
    local _
    _, object, bridges = sailOut(ctx, ow, ground, travelDir, log)
  end
  -- FADE_OUT_START / FADE_OUT_END
  pcall(function() require("src.core.Music").dsFade(0, M.FADE) end)
  Commands.fade(ctx, "out", M.FADE, "black")
  -- the bridges' one-shots unloaded; FieldTransition_FinishMap leaves the map
  -- (the ship's and the camera's positions die with it: put them back on the
  -- ground this port keeps across visits)
  if bridges and bridges.slots then
    for i = 1, 2 do if bridges[i] then bridges.slots[bridges[i].tag] = nil end end
  end
  if object then object.live = nil end
  if ow.gen4Camera and ow.gen4Camera.boatCamera then ow.gen4Camera = nil end
  -- PLAY_TRAVEL_CUTSCENE
  local game = ctx.game
  local Scene = require("src.ui.Gen4BoatTravelScene")
  local runner = ctx.runner
  if game and game.stack and Scene.available(game, travelDir) then
    log.scene = true
    game.stack:push(Scene.new(game, travelDir, function() if runner then runner:resume() end end))
    if runner then runner:yield() end
  else
    Logger.warn("boat cutscene: no crossing %d in this cache (re-import Platinum) -- the sea is skipped", travelDir)
  end
  -- MAP_TRANSITION, FADE_IN
  log.to = { header = tonumber(header), x = tonumber(x), z = tonumber(z), dir = tonumber(exitDir) }
  require("src.script.Gen4Commands")
  Commands.g4_warp(ctx, tonumber(header) or 0, tonumber(x) or 0, tonumber(z) or 0, tonumber(exitDir) or 0)
  Commands.fade(ctx, "in", M.FADE, "black")
  log.done = true
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_boat_cutscene = { foreground = true, blocking = true }

function M.install(L)
  L.playboatcutscene = function(ins, s)
    local a = ins.args
    s.out[#s.out + 1] = { "g4_boat_cutscene", a[1], a[2], a[3], a[4], a[5] }
  end
end

return M
