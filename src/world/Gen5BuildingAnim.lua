-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S SCRIPTED BUILDING ANIMATIONS -- the badge gates' bars, the
-- doors a script opens, the gyms' lifts.  The data is the building packs'
-- own (src/import/Gen5BuildingAnim.lua); this is the controller, READ FROM
-- CODE in ov21 (Black):
--
-- A BUILDING IS FOUND by the scripts' model id (the record kind through
-- 0x021D3DC4) and a cell: 0x0218C654 builds the box x +- 2 cells, z +- 3
-- cells around (x * 16, z * 16) world units (0x0218C9C4) and takes the first
-- placed building of that model inside it (0x0218C584 / 0x0218C638).
--
-- EVERY ANIMATION OBJECT HAS A STATUS (0x0218C3E0, the type-2 command;
-- 0x0218C1C4, its per-frame step) -- slot k of a record plays its animation
-- objects k * perSet .. k * perSet + perSet - 1:
--   cmd 0  stop all, then the set from frame 0 forward once   -> status 3
--   cmd 1  stop all, then the set from its LAST frame backward -> status 4
--   cmd 2  stop all, then the set from frame 0, looping        -> status 1
--   cmd 3  every running object of the set holds where it is   -> status 2
--   cmd 4  stop all (nothing attached: the model's rest pose)  -> status 0
-- Per field frame: 1 steps and wraps, 3 steps forward and becomes 2 at the
-- end, 4 steps back and becomes 2 at frame 0. "Finished" (0x0218C43C) is
-- status 0 or 2.
--
-- TWO OWNERS of that state:
--   * the RECORD's own, shared by every placement of it (mgr + 0x1D8, one
--     per loaded building type) -- 0x12B and 0x12E drive this one;
--   * an INSTANCE (0x127, 0x0218C724): a copy of one placed building with its
--     own state, starting at rest, the original hidden until 0x128 deletes
--     the copy (0x0218C54C / 0x0218C860); at most 7 (handles 0xFFF0 | i,
--     0x0218BA98 / 0x0218BACC).
--
--   0x127 <dest, model, x, z>  the instance; its handle (0 when no building
--                              matches) into dest
--   0x128 <handle>             delete it
--   0x129 <handle, slot>       cmd 0 on that slot, and the kind's SE for the
--                              slot (0x021D3D88, 0x0218C990)
--   0x12A <handle>             wait: the slot's object finished (then cmd 3)
--                              and that SE no longer playing (0x021B2E80)
--   0x12B <model, x, z>        the record's slot 0: cmd 1 then cmd 3 -- shown
--                              at its last frame (a badge gate already open)
--   0x12C <handle>             cmd 3 on the instance's slot
--   0x12E <model, x, z>        the record's slot 0: cmd 2 (looping)
--
-- STATE IS THE FIELD'S: it lives on the overworld and is dropped on a warp
-- (OverworldState:setMap), as the cartridge's manager is rebuilt on a map
-- load.
-- INFERRED: the step rate -- one animation frame per FIELD frame at 30 Hz,
-- as Gen 4's (Gen4PropClock); the exact last frame a forward one-shot shows
-- (frames - 1); the order placements are searched in (chunk by chunk, row
-- by row).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local Import = require("src.import.Gen5BuildingAnim")

local M = {}
M.FIELD_HZ = 30
M.INSTANCES = 7
M.HANDLE = 0xFFF0
-- a script waiting on an animation never waits longer than this (ticks):
-- not the cartridge's, a guard so a mis-resolved building cannot hang a cutscene
M.WAIT_CAP = 900

local function Game() return package.loaded["src.core.Game"] end
local function ground(ow) return ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground or nil end

-- (OverworldState:setMap drops ow.bwBuildingAnim on every load that is not
-- a seam crossing)
function M.store(ow)
  if type(ow) ~= "table" then return nil end
  local st = ow.bwBuildingAnim
  if not st then
    st = { types = {}, inst = {}, byObject = {}, hidden = {}, acc = 0 }
    ow.bwBuildingAnim = st
  end
  local g = ground(ow)
  if g then g.bwBuildingAnim = st end
  return st
end

local function infoOf(g, id)
  local bw = g and g.buildingSet and g.buildingSet.bw
  return bw and bw[id] or nil
end

local function recordOf(g, member)
  return member and g and g.animsByMember and g.animsByMember[member] or nil
end

-- find(g, model, x, z) -> object, recordId  (0x0218C654)
function M.find(g, model, x, z)
  if not (g and g.grid and g.terrain and g.terrain.chunks) then return nil end
  local grid, terrain = g.grid, g.terrain
  local cu = terrain.chunkUnits or 512
  local unit = cu / (terrain.chunkTiles or 32)
  local x0, x1 = x * unit - 2 * unit, x * unit + 2 * unit
  local z0, z1 = z * unit - 3 * unit, z * unit + 3 * unit
  for cy = math.max(0, math.floor(z0 / cu)), math.min(grid.height - 1, math.floor(z1 / cu)) do
    for cx = math.max(0, math.floor(x0 / cu)), math.min(grid.width - 1, math.floor(x1 / cu)) do
      local land = grid.land[cy * grid.width + cx + 1]
      local record = land and terrain.chunks[land]
      -- the drawn list: the placements and the doors they spawn
      local list = record and (g.objectsFor and g:objectsFor(land, record, cx, cy) or record.objects) or {}
      for _, o in ipairs(list) do
        local info = o.archive == nil and infoOf(g, o.model)
        if info and info.model == model then
          local bx, bz = cx * cu + cu / 2 + (o.x or 0), cy * cu + cu / 2 + (o.z or 0)
          if bx >= x0 and bx <= x1 and bz >= z0 and bz <= z1 then return o, o.model, bx / unit, bz / unit end
        end
      end
    end
  end
  return nil
end

-- THE PACK A ZONE LOADS (READ FROM CODE, ov21 0x0218BC1C, called by the
-- building manager's setup 0x0218B8AC on a field load): area >= 210 ->
-- indoor pack area - 210, else outdoor pack (area - 2) / 4; the setup also
-- (0x0218BB78) points every record id the pack lacks at its default record,
-- 21 outdoors (rock_01, a 2-triangle quad in all 52 packs) or 20 indoors
-- (dust01) -- an unknown id is drawn as that, not dropped.
M.DEFAULT_RECORD = { outdoor = 21, indoor = 20 }
function M.packOf(area)
  area = math.floor(tonumber(area) or 0)
  if area >= 210 then return "indoor", area - 210 end
  if area < 2 then return "outdoor", 0 end
  return "outdoor", math.floor((area - 2) / 4)
end

-- the stand-in for a placement whose id this map's pack lacks: the pack's
-- default record (READ, above). Only the map's OWN pack is consulted: the
-- pack is bound to the field when it is built -- field +0xD0 (the zone) is
-- written only at 0x02188066, and 0x0218B8AC, the one pack loader, runs only
-- from the field's setup (0x021882E6) -- so a neighbouring zone's chunk seen
-- from this map's field resolves its ids in this map's pack too.
local function substitute(g, land, o)
  local G = Game()
  local data = G and G.data
  local own = g.buildingSet
  local trec = data and data.gen4_terrain and data.gen4_terrain.maps and g.def
               and (data.gen4_terrain.maps[g.def.sourceId or g.def.id] or data.gen4_terrain.maps[g.def.id])
  local rec = trec and M.DEFAULT_RECORD[trec.buildingKind]
  if rec and own.models[rec + 1] then
    return { model = rec, x = o.x, y = o.y, z = o.z, rotY = o.rotY, gen5 = true, bwSubFor = o }
  end
  return nil
end

-- doorsFor(g, land, own) -> what this chunk's placements add (cached per
-- land so the objects keep their identity -- an instance, 0x127, is keyed
-- by it):
--   * the doors its buildings stand beside (0x0218B974: each placement whose
--     record names a door adds that door at the placement plus the record's
--     offset -- the offset not turned, the door given the building's own
--     rotation -- right after the building itself);
--   * for a placement whose id this map's pack lacks, the default record
--     (substitute, above).
function M.doorsFor(g, land, own)
  local bw = g and g.buildingSet and g.buildingSet.bw
  if not (bw and land and own) then return nil end
  g.bwDoors = g.bwDoors or {}
  local cached = g.bwDoors[land]
  if cached ~= nil and cached.from == own then return cached.list end
  local list = nil
  local models = g.buildingSet.models or {}
  for _, o in ipairs(own) do
    local info = o.archive == nil and o.model and bw[o.model]
    local door = info and info.door
    if door and models[door.id + 1] then
      list = list or {}
      list[#list + 1] = { model = door.id, x = (o.x or 0) + door.x, y = (o.y or 0) + door.y,
                          z = (o.z or 0) + door.z, rotY = o.rotY, gen5 = true, bwDoorOf = o }
    end
    if o.archive == nil and o.model and not o.bwDoorOf and not models[o.model + 1] then
      local sub = substitute(g, land, o)
      if sub then list = list or {}; list[#list + 1] = sub end
    end
  end
  g.bwDoors[land] = { from = own, list = list or false }
  return list
end

local function framesOf(g, info, k)
  local r = recordOf(g, info.members[k])
  return r and math.max(1, math.floor(tonumber(r.frames) or 1)) or nil
end

-- command(g, owner, info, set, cmd)  (0x0218C3E0)
function M.command(g, owner, info, set, cmd)
  if not (owner and info) or info.type ~= 2 then return end
  set = math.floor(tonumber(set) or 0)
  if set < 0 or set >= 4 then set = 0 end
  local per = info.perSet or 1
  local objs = owner.objs
  if cmd == 3 then
    for j = 0, per - 1 do
      local o = objs[set * per + j]
      if o and o.status ~= 0 then o.status = 2 end
    end
    return
  end
  for k in pairs(objs) do objs[k] = nil end
  if cmd == 4 then return end
  for j = 0, per - 1 do
    local k = set * per + j
    local frames = framesOf(g, info, k)
    if frames then
      if cmd == 0 then objs[k] = { status = 3, frame = 0, frames = frames }
      elseif cmd == 1 then objs[k] = { status = 4, frame = frames, frames = frames }
      elseif cmd == 2 then objs[k] = { status = 1, frame = 0, frames = frames } end
    end
  end
end

-- one field frame of an owner (0x0218C1C4)
local function step(owner)
  for _, o in pairs(owner.objs) do
    if o.status == 1 then o.frame = (o.frame + 1) % o.frames
    elseif o.status == 3 then
      o.frame = o.frame + 1
      if o.frame >= o.frames - 1 then o.frame = o.frames - 1; o.status = 2 end
    elseif o.status == 4 then
      o.frame = o.frame - 1
      if o.frame <= 0 then o.frame = 0; o.status = 2 end
    end
  end
end

-- finished(owner, k)  (0x0218C43C): status 0 or 2
function M.finished(owner, k)
  local o = owner and owner.objs[k]
  return not o or o.status == 0 or o.status == 2
end

function M.update(ow, dt)
  local st = ow and ow.bwBuildingAnim
  -- handed to the renderer each tick (it holds no overworld), and taken back
  -- from a cached map's ground once the state is dropped
  -- a warp's landing on a doorstep: the door opens and closes behind
  local landing = ow and ow.ndsWarpLanding
  if type(landing) == "table" and ow.bwArrivalFor ~= landing then
    ow.bwArrivalFor = landing
    -- a new field: the last one's door camera went with it
    M.camClear()
    M.recClear()
    if ow.map and landing[1] == ow.map.id then pcall(M.exitDoor, ow, landing[2], landing[3]) end
    st = ow.bwBuildingAnim
  end
  local g = ground(ow)
  if g and g.bwBuildingAnim ~= st then g.bwBuildingAnim = st end
  if not st then return end
  st.acc = st.acc + (tonumber(dt) or 0) * M.FIELD_HZ
  while st.acc >= 1 do
    st.acc = st.acc - 1
    for _, owner in pairs(st.types) do step(owner) end
    for _, inst in pairs(st.inst) do step(inst.owner) end
    M.camStep()
    M.recStep(ow)
  end
end

local function typeOwner(st, id)
  local owner = st.types[id]
  if not owner then owner = { objs = {} } st.types[id] = owner end
  return owner
end

local function handleOf(v)
  v = math.floor(tonumber(v) or 0)
  if v - (v % 16) ~= M.HANDLE then return nil end
  local i = v % 16
  if i >= M.INSTANCES then return nil end
  return i
end

function M.instance(st, handle)
  local i = handleOf(handle)
  return i and st and st.inst[i] or nil
end

-- --------------------------------------------- the door a warp goes through --
--
-- READ FROM CODE (ov21). The door is an instance of the model-1 building at
-- the warp (0x021A8214 -> 0x0218C7D8, as 0x127 makes one); slot 0 opens it
-- with the kind's SE (0x021A8278), slot 1 closes it (0x021A82A8), 0x021A8244
-- waits for either (0x0218C8D8). Two field tasks run them as a list of steps
-- (0x021A81EC / 0x021A8200 walk the list at task +0x2C):
--
--   GOING IN (0x021A7E3C, steps 0x021A7F38; list 0x021A7EB4 -- with a door
--   0,3,1,2,5,6,7, without 0,1,2,5,6,7):  0 the door camera effect starts
--   (0x021BDCC8) / 3 the door OPENS (no wait for it) / 1 the effect's
--   second part / 2 wait for the field (0x021C6E48), sometimes 16 frames
--   more / 5 the player STEPS ONE CELL on in its facing (ov10 0x021618E0,
--   run to its end) / 6 / 7 the fade and the map change (0x021BE8D4) --
--   the door is never closed on this side.
--
--   COMING OUT (0x021A7B20, steps 0x021A7CE8; list 0x021A7B88 -- with a door
--   0,1,2,3,4,5,6,7, or 0,1,5,2,3,4,6,7 for a warp kind 0/1):  0 the
--   player HIDDEN (0x02185B88 -> 0x0216DAC8, 1) / 1 the fade in (0x021BE92C)
--   / 2 the door OPENS / 3 WAIT for it / 4 the player SHOWN and STEPPING ONE
--   CELL out (0x021618E0, run to its end) / 5 the camera effect ends / 6 the
--   door CLOSES / 7 WAIT for it / 8 done.
--
-- INFERRED: the port has no door camera effect, so its waits (step 2 going
-- in, the 16-frame hold) are not reproduced; the step is the player's own
-- step length; the port lands the player on the warp cell (the doorway) and
-- the step out moves them to the cell in front; only a door within a cell
-- and a half of the warp is the warp's (the scripts' box is wider).

local function doorNear(g, def, x, y)
  if not (g and def) then return nil end
  local gx, gy = (def.originX or 0) + x, (def.originY or 0) + y
  local object, id, cx, cz = M.find(g, 1, gx, gy)
  if not (object and object.bwDoorOf) then return nil end
  if math.abs(cx - (gx + 0.5)) > 1.5 or math.abs(cz - (gy + 0.5)) > 1.5 then return nil end
  return object, id
end

local function newInstance(st, object, id)
  for i = 0, M.INSTANCES - 1 do
    if not st.inst[i] then
      local inst = { object = object, id = id, slot = 0xFFFF, owner = { objs = {} } }
      st.inst[i] = inst
      st.byObject[object] = inst.owner
      return i, inst
    end
  end
  return nil
end

local function playSlot(ow, g, inst, slot)
  inst.slot = slot
  M.command(g, inst.owner, infoOf(g, inst.id), slot, 0)
  local se = nil
  local info = infoOf(g, inst.id)
  local row = info and Import.SOUNDS[info.kind]
  se = row and row[slot + 1]
  if se and se ~= 0 and Commands.play_sound then
    local G = Game()
    pcall(Commands.play_sound, { overworld = ow, game = G, save = G and G.save }, se)
  end
end

local function free(st, i, ow)
  local inst = st.inst[i]
  if not inst then return end
  st.inst[i] = nil
  if st.byObject[inst.object] == inst.owner then st.byObject[inst.object] = nil end
  if ow then M.setHidden(ow, inst.object, false) end
end

local function stepTicks(p) return (p and (p.stepFramesCur or p.stepFrames)) or 16 end

-- ------------------------------------------------------ the door camera --
--
-- READ FROM CODE (ov21 0x021BDC94, the door camera effect; its variant is
-- picked by 0x021BDCC8: going in 0x021BDDC0, coming out 0x021BDEB4, and
-- 0x021BDFB0 / 0x021BE068 in their place when the zone has a camera record of
-- its own, 0x021BE1A0 -> /a/1/7/9 via 0x021BE148). The "kind" is the
-- player's facing, 0x021A3050 -> 0x0216D5F8, 0 up 1 down 2 left 3 right (the
-- step tables ov10 0x021713EC.. hold moves 0x0F, 0x0E, 0x0D, 0x0C):
--   going in, facing left / right: the camera turns to yaw +0x0A09 / -0x0A09
--     (14.1 degrees) over 10 frames and the sequence waits for it (step 2,
--     0x021C6E48); facing up / down: no effect
--   coming out, facing down: the camera is put 180 units farther at once
--     (distance + 0x2D << 14) and comes back over 10 frames, started before
--     the door opens; facing left / right: put at yaw -0x0A09 / +0x0A09 at
--     once and brought back over 10 frames after the step out; up: none
-- The move is the camera controller's (0x0219014C: five commands over the
-- effect's frame count) -- INFERRED linear. Played on the field3d camera's
-- yaw (Gen4View.surfaceAngles) and distance (the kept look's zoom); the
-- other camera modes are not moved. The zone records (/a/1/7/9) are not
-- read: every door takes the default variants.
M.DOOR_YAW = 0x0A09 / 65536 * 360
M.DOOR_DISTANCE = 0x2D * 16384 / 4096
M.DOOR_FRAMES = 10
local FACING = { up = 0, down = 1, left = 2, right = 3 }

local function view() local ok, V = pcall(require, "src.render.Gen4View") return ok and V or nil end

-- the offset now in force (process-wide, as Gen4View's look is)
M.camState = nil

local function camApply(yaw, extra)
  local V = view()
  local c = M.camState
  if not (V and c) then return end
  c.yaw, c.extra = yaw, extra
  if c.angles == nil or V.surfaceAngles ~= c.angles then
    c.angles = { yaw = yaw, pitch = 0 }
    V.surfaceAngles = c.angles
  end
  c.angles.yaw = yaw
  local d = c.distance or 512
  V.look.zoom = (c.baseZoom or 1) * (d + extra) / d
end

function M.camClear()
  local c = M.camState
  if not c then return end
  M.camState = nil
  local V = view()
  if V then
    if V.surfaceAngles == c.angles then V.surfaceAngles = nil end
    V.look.zoom = c.baseZoom
  end
end

-- camera offset (yaw degrees, extra distance) set at once
function M.camSet(ow, yaw, extra)
  local V = view()
  if not V then return end
  if not M.camState then
    local g = ground(ow)
    M.camState = { baseZoom = V.look.zoom, yaw = 0, extra = 0,
                   distance = g and g.camera and tonumber(g.camera.distance) or 512 }
  end
  M.camState.move = nil
  camApply(yaw, extra)
end
-- ...or moved to over `frames` field frames
function M.camMove(ow, yaw, extra, frames)
  if not M.camState then M.camSet(ow, 0, 0) end
  local c = M.camState
  if not c then return end
  c.move = { y0 = c.yaw or 0, e0 = c.extra or 0, y1 = yaw, e1 = extra, frames = frames, t = 0 }
end
function M.camBusy() return M.camState ~= nil and M.camState.move ~= nil end
-- one field frame of the move; back at no offset, the camera is let go
function M.camStep()
  local c = M.camState
  local mv = c and c.move
  if not mv then return end
  mv.t = mv.t + 1
  local k = math.min(1, mv.t / math.max(1, mv.frames))
  camApply(mv.y0 + (mv.y1 - mv.y0) * k, mv.e0 + (mv.e1 - mv.e0) * k)
  if k >= 1 then
    c.move = nil
    if mv.y1 == 0 and mv.e1 == 0 then M.camClear() end
  end
end

-- THE ZONE RECORDS' CAMERA (0x021BDFB0 going in / 0x021BE068 coming out,
-- READ FROM CODE): a warp whose transition type is 7 or more takes its
-- camera from /a/1/7/9 (src/import/Gen5DoorCameras.lua) instead of the
-- facing rule above -- absolute angles, distance and an offset of the point
-- looked at, moved over the record's frames (0 frames: set at once, and the
-- sequence holds 16 frames, 0x021BDD48 -> step 9 / 10). Going in it is used
-- when [12] is set, the camera moving from the map's own to the record;
-- coming out when [13] is set, the camera put at the record at once and
-- brought back. Played through Gen4View.scripted (pitch / yaw / distance /
-- offset). INFERRED: the record coming out is the one of the warp taken; a
-- record's own point ([4] = 1, one record) is not used (the player is).
M.recState = nil

function M.doorCamera(warpDef)
  local t = warpDef and tonumber(warpDef.transition)
  if not t or t < 7 then return nil end
  local G = Game()
  local cams = G and G.data and G.data.constants and G.data.constants.gen5DoorCameras
  return cams and (cams[t] or cams[tostring(t)]) or nil
end

local function recBase(ow)
  local g = ground(ow)
  local cam = g and g.camera or {}
  return { pitch = tonumber(cam.pitch) or 53, yaw = 0, distance = tonumber(cam.distance) or 512, offset = { 0, 0, 0 } }
end

local function recApply(c)
  local V = view()
  local r = M.recState
  if not (V and r) then return end
  r.cur = c
  if r.scripted == nil or V.scripted ~= r.scripted then
    r.scripted = {}
    V.scripted = r.scripted
  end
  r.scripted.pitch, r.scripted.yaw, r.scripted.distance = c.pitch, c.yaw, c.distance
  r.scripted.offset = { c.offset[1], c.offset[2], c.offset[3] }
end

local function lerp(a, b, k)
  local o = {}
  for _, key in ipairs({ "pitch", "yaw", "distance" }) do o[key] = a[key] + (b[key] - a[key]) * k end
  o.offset = {}
  for i = 1, 3 do o.offset[i] = a.offset[i] + (b.offset[i] - a.offset[i]) * k end
  return o
end

local function recordView(rec)
  return { pitch = rec.pitch, yaw = rec.yaw, distance = rec.distance,
           offset = { rec.offset[1], rec.offset[2], rec.offset[3] } }
end

-- to the record (going in) or back from it (coming out); frames 0 = at once
function M.recTo(ow, target, frames, delay)
  M.recState = M.recState or {}
  local r = M.recState
  local from = r.cur or recBase(ow)
  if (tonumber(frames) or 0) <= 0 and not delay then
    r.move = nil
    recApply(target)
    r.hold = 16
    return
  end
  r.move = { from = from, to = target, frames = math.max(1, frames), t = 0, delay = delay or 0 }
end
function M.recSet(ow, target)
  M.recState = M.recState or {}
  M.recState.move = nil
  recApply(target)
end
function M.recBusy()
  local r = M.recState
  return r ~= nil and (r.move ~= nil or (r.hold or 0) > 0)
end
function M.recStep(ow)
  local r = M.recState
  if not r then return end
  if (r.hold or 0) > 0 then r.hold = r.hold - 1 end
  local mv = r.move
  if not mv then return end
  if mv.delay > 0 then mv.delay = mv.delay - 1 return end
  mv.t = mv.t + 1
  local k = math.min(1, mv.t / mv.frames)
  recApply(lerp(mv.from, mv.to, k))
  if k >= 1 then
    r.move = nil
    if mv.back then M.recClear() end
  end
end
function M.recClear()
  local r = M.recState
  if not r then return end
  M.recState = nil
  local V = view()
  if V and V.scripted == r.scripted then V.scripted = nil end
end
-- back to the map's own camera from the record
function M.recBack(ow, frames, delay)
  M.recTo(ow, recBase(ow), frames, delay)
  if M.recState and M.recState.move then M.recState.move.back = true
  else M.recClear() end
end

-- a transparent state that holds the field while `run(self)` returns false
local function hold(ow, run)
  local G = Game()
  if not (G and G.stack) then return false end
  local S = { name = "Gen5BuildingAnim door", isOpaque = false, tick = 0 }
  function S:update()
    self.tick = self.tick + 1
    M.update(ow, 1 / 60)
    if run(self) then
      if G.stack:top() == self then G.stack:pop() end
      if self.after then self.after() end
    end
  end
  function S:draw() end
  G.stack:push(S)
  return S
end

-- enterDoor(ow, warpDef, tx, ty) -> true when the door sequence has the warp
-- (0x021A7E3C: effect set up, door opens, camera move, wait for it, step in,
-- fade and map change)
function M.enterDoor(ow, warpDef, tx, ty)
  local def = ow and ow.map and ow.map.def
  if not (def and def.gen5 and warpDef) then return false end
  local g = ground(ow)
  local object, id = doorNear(g, def, tx, ty)
  local rec = M.doorCamera(warpDef)
  if rec and not rec.goingIn then rec = nil end
  -- no door: the sequence still runs for a zone record (list 0,1,2,5,6,7)
  if not object and not rec then return false end
  local st = M.store(ow)
  local i, inst
  if object then
    i, inst = newInstance(st, object, id)
    if not i then return false end
  end
  local p = ow.player
  local kind = FACING[p.facing or "up"] or 0
  if inst then playSlot(ow, g, inst, 0) end
  ow.bwLastWarp = warpDef
  if rec then
    M.recTo(ow, recordView(rec), rec.frames)
  elseif kind == 2 or kind == 3 then
    M.camMove(ow, kind == 2 and M.DOOR_YAW or -M.DOOR_YAW, 0, M.DOOR_FRAMES)
  end
  local x0, y0 = p.cellX * 16, p.cellY * 16
  local dx, dy = tx - p.cellX, ty - p.cellY
  local len = stepTicks(p)
  local t0 = nil
  local S = hold(ow, function(self)
    -- step 2: the camera has finished turning
    if not t0 then
      if (M.camBusy() or M.recBusy()) and self.tick < 240 then return false end
      t0 = self.tick
    end
    -- step 5: the step into the doorway
    local k = math.min(1, (self.tick - t0) / len)
    p.px, p.py = x0 + dx * 16 * k, y0 + dy * 16 * k
    p.moving = k < 1 or nil
    return k >= 1
  end)
  if not S then if i then free(st, i) end M.camClear() M.recClear() return false end
  S.after = function()
    p.moving = nil
    p.px, p.py = x0, y0
    ow:takeWarp(warpDef)
  end
  return true
end

-- exitDoor(ow, x, y): a landing outside a door (0x021A7B20): hidden, the
-- door opens, the player steps out of the doorway, the door closes; the
-- camera comes back from its offset
function M.exitDoor(ow, x, y)
  local def = ow and ow.map and ow.map.def
  if not (def and def.gen5) then return end
  local g = ground(ow)
  local p = ow.player
  if not p then return end
  -- the doorway: the cell the player faces away from
  local back = { up = { 0, 1 }, down = { 0, -1 }, left = { 1, 0 }, right = { -1, 0 } }
  local d = back[p.facing or "down"] or { 0, -1 }
  local object, id = doorNear(g, def, x + d[1], y + d[2])
  local rec = M.doorCamera(ow.bwLastWarp)
  if rec and not rec.comingOut then rec = nil end
  local len = stepTicks(p)
  if not object then
    -- no door (list 0,1,4,5,8): the record's camera at once, back after the
    -- step out -- the port's landing is not moved
    if rec then
      M.recSet(ow, recordView(rec))
      M.recBack(ow, rec.frames, math.floor(len / 2))
    end
    return
  end
  local st = M.store(ow)
  local i, inst = newInstance(st, object, id)
  if not i then return end
  local kind = FACING[p.facing or "down"] or 1
  local camLater
  if rec then
    -- 0x021BE068: the record at once; back over its frames after the step
    M.recSet(ow, recordView(rec))
    camLater = "record"
  else
    -- step 1: the offset at once (0x021BDEB4, applied by 0x0218FEC0)
    if kind == 1 then M.camSet(ow, 0, M.DOOR_DISTANCE)
    elseif kind == 2 then M.camSet(ow, -M.DOOR_YAW, 0)
    elseif kind == 3 then M.camSet(ow, M.DOOR_YAW, 0) end
    camLater = (kind == 2 or kind == 3)
    -- facing up / down run step 5 (the move back) before the door opens
    if kind == 1 then M.camMove(ow, 0, 0, M.DOOR_FRAMES) end
  end
  local x1, y1 = x * 16, y * 16
  local phase, t0 = "open", 0
  -- the step out is a walk: nothing steps into a person or a wall
  local tx, ty = x - d[1], y - d[2]
  local map = ow.map
  local okC, Collision = pcall(require, "src.world.Collision")
  local free_ = map and map.isWalkableCell and map:isWalkableCell(tx, ty)
                and not (okC and Collision.occupied and Collision.occupied(ow.entities or {}, tx, ty, p))
  if not free_ then len = 0 end
  p.hidden = true
  playSlot(ow, g, inst, 0)
  local S = hold(ow, function(self)
    local cur = st.inst[i]
    if not cur then p.hidden = nil return true end
    if phase == "open" then
      if M.finished(cur.owner, 0) or self.tick > 240 then phase, t0 = "step", self.tick; p.hidden = nil end
    end
    if phase == "step" then
      -- out of the doorway (the port lands the player on the warp, the
      -- doorway's own cell) onto the cell in front
      local k = len > 0 and math.min(1, (self.tick - t0) / len) or 1
      local dd = len > 0 and 1 or 0
      p.px, p.py = x1 - d[1] * 16 * k * dd, y1 - d[2] * 16 * k * dd
      p.moving = k < 1 or nil
      if k >= 1 then
        phase = "close"; p.moving = nil
        if len > 0 then p.cellX, p.cellY = tx, ty end
        p.px, p.py = p.cellX * 16, p.cellY * 16
        -- step 5 for left / right: the camera comes back now
        if camLater == "record" then M.recBack(ow, rec.frames)
        elseif camLater then M.camMove(ow, 0, 0, M.DOOR_FRAMES) end
        playSlot(ow, g, cur, 1)
      end
    elseif phase == "close" then
      if M.finished(cur.owner, 1) or self.tick > 600 then free(st, i, ow) return true end
    end
    return false
  end)
  if not S then p.hidden = nil free(st, i) M.camClear() M.recClear() end
end

-- ------------------------------------------------------- the renderer side --

local function ownerFor(g, object)
  local st = g and g.bwBuildingAnim
  if not (st and object) then return nil end
  return st.byObject[object] or st.types[object.model]
end

-- pose(g, object, building) -> pose | nil: the joint animations an owner has
-- attached, at their frames (nil = the rest pose / no owner)
function M.pose(g, object, building)
  local owner = ownerFor(g, object)
  if not (owner and next(owner.objs)) then return nil end
  local info = infoOf(g, object.model)
  if not info then return nil end
  local Anim, byJoint
  for k, o in pairs(owner.objs) do
    local r = recordOf(g, info.members[k])
    if r and r.kind == "BCA0" then
      if r.bca and not r.tracks then require("src.render.Gen4PropClock").inflate(r) end
      if r.tracks then
        Anim = Anim or require("src.import.Gen4Anim")
        local at = math.max(0, math.min(o.frames - 1, math.floor(o.frame)))
        for _, track in ipairs(r.tracks) do
          byJoint = byJoint or {}
          if byJoint[track.index] == nil then
            local f = at
            if track.frames and f >= track.frames then f = track.frames - 1 end
            byJoint[track.index] = Anim.unpackFrame(track.matrices, f)
          end
        end
      end
    end
  end
  if not byJoint then return nil end
  return building:posed(function(node) return byJoint[node] end)
end

-- materials(g, object, mats) -> mats: the texture animations an owner has
-- attached merged over what the clock gave
function M.materials(g, object, mats)
  local owner = ownerFor(g, object)
  if not (owner and next(owner.objs)) then return mats end
  local info = infoOf(g, object.model)
  if not info then return mats end
  local TexAnim = require("src.render.Gen4TexAnim")
  local packed = g.buildingSet and g.buildingSet.models and g.buildingSet.models[object.model + 1]
  for k, o in pairs(owner.objs) do
    local r = recordOf(g, info.members[k])
    if r and r.kind ~= "BCA0" then
      local at = math.max(0, math.min(o.frames - 1, math.floor(o.frame)))
      local one = TexAnim.materials({ r }, at, packed and packed.patternImages)
      if one then
        mats = mats or {}
        for name, state in pairs(one) do
          local into = mats[name] or {}
          for key, value in pairs(state) do into[key] = value end
          mats[name] = into
        end
      end
    end
  end
  return mats
end

-- ------------------------------------------------------------ the commands --

local function C() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(C().valueOf(ctx, v)) or 0) end
local function log(fmt, ...) pcall(function(...) require("src.core.Logger").info(fmt, ...) end, ...) end

local function located(ctx, model, x, z)
  local ow = ctx.overworld
  local st, g = M.store(ow), ground(ow)
  if not (st and g) then return nil end
  local m, cx, cz = val(ctx, model), val(ctx, x), val(ctx, z)
  local object, id = M.find(g, m, cx, cz)
  log("gen5 building: model %d at (%d, %d) -> %s", m, cx, cz, object and ("record " .. tostring(id)) or "none")
  if not object then return nil end
  return st, g, object, id, infoOf(g, id)
end

-- 0x127
function Commands.g5_bld_instance(ctx, dest, model, x, z)
  local st, g, object, id, info = located(ctx, model, x, z)
  local handle = 0
  if st then
    for i = 0, M.INSTANCES - 1 do
      if not st.inst[i] then
        local inst = { object = object, id = id, slot = 0xFFFF, owner = { objs = {} } }
        st.inst[i] = inst
        st.byObject[object] = inst.owner
        handle = M.HANDLE + i
        break
      end
    end
  end
  C().setVar(ctx.save, dest, handle)
end

-- 0x128
function Commands.g5_bld_free(ctx, handle)
  local st = M.store(ctx.overworld)
  local i = handleOf(val(ctx, handle))
  local inst = i and st and st.inst[i]
  if not inst then return end
  st.inst[i] = nil
  if st.byObject[inst.object] == inst.owner then st.byObject[inst.object] = nil end
  -- 0x0218C860 shows the original again (0x0218C54C flag 1), whatever 0x12D
  -- had done to it
  M.setHidden(ctx.overworld, inst.object, false)
end

local function soundFor(g, inst)
  local info = infoOf(g, inst.id)
  local row = info and Import.SOUNDS[info.kind]
  if not row or inst.slot >= 4 then return nil end
  local se = row[inst.slot + 1]
  return (se and se ~= 0) and se or nil
end

-- 0x129
function Commands.g5_bld_play(ctx, handle, slot)
  local ow = ctx.overworld
  local st, g = M.store(ow), ground(ow)
  local inst = M.instance(st, val(ctx, handle))
  if not (inst and g) then return end
  inst.slot = val(ctx, slot)
  M.command(g, inst.owner, infoOf(g, inst.id), inst.slot, 0)
  local se = soundFor(g, inst)
  if se and Commands.play_sound then pcall(Commands.play_sound, ctx, se) end
end

-- 0x12A
function Commands.g5_bld_wait(ctx, handle)
  local ow = ctx.overworld
  local st, g = M.store(ow), ground(ow)
  local h = val(ctx, handle)
  local ticks = 0
  local function done()
    local inst = M.instance(st, h)
    if not inst then return true end
    ticks = ticks + 1
    if ticks > M.WAIT_CAP then return true end
    if not M.finished(inst.owner, inst.slot) then return false end
    M.command(g, inst.owner, infoOf(g, inst.id), inst.slot, 3)
    local se = soundFor(g, inst)
    local okS, Sound = pcall(require, "src.core.Sound")
    if se and okS and Sound.isPlaying and Sound.isPlaying(se) then return false end
    return true
  end
  if done() then return end
  ctx.runner.waitingCheck = done
  ctx.runner:yield()
end

-- 0x12C
function Commands.g5_bld_stop(ctx, handle)
  local ow = ctx.overworld
  local st, g = M.store(ow), ground(ow)
  local inst = M.instance(st, val(ctx, handle))
  if inst and g then M.command(g, inst.owner, infoOf(g, inst.id), inst.slot, 3) end
end

-- setHidden(ow, object, on): a placement drawn or not (0x0218C54C: flag 0
-- empties the building's slot in the field's map-object table -- model -1,
-- which the draw loop ov10 0x02169738 skips and nothing else reads -- and
-- flag 1 puts the model back). Collision is the tiles', untouched.
function M.setHidden(ow, object, on)
  local st = M.store(ow)
  if not (st and object) then return end
  local was = st.hidden[object] or false
  st.hidden[object] = on and true or nil
  local g = ground(ow)
  if g and was ~= (on and true or false) and g.dropBakes then pcall(g.dropBakes, g) end
end

-- 0x12D <model, x, z, flag>
function Commands.g5_bld_show(ctx, model, x, z, flag)
  local st, _, object = located(ctx, model, x, z)
  if not st then return end
  M.setHidden(ctx.overworld, object, val(ctx, flag) == 0)
end

-- 0x12B
function Commands.g5_bld_hold_open(ctx, model, x, z)
  local st, g, _, id, info = located(ctx, model, x, z)
  if not st then return end
  local owner = typeOwner(st, id)
  M.command(g, owner, info, 0, 1)
  M.command(g, owner, info, 0, 3)
end

-- 0x12E
function Commands.g5_bld_loop(ctx, model, x, z)
  local st, g, _, id, info = located(ctx, model, x, z)
  if not st then return end
  M.command(g, typeOwner(st, id), info, 0, 2)
end

function M.install(L)
  local function emit(s, t) s.out[#s.out + 1] = t end
  local a = function(ins, k) return ins.args and ins.args[k] end
  L.bwbuildinginstance = L.bwbuildinginstance or function(ins, s) emit(s, { "g5_bld_instance", a(ins, 1), a(ins, 2), a(ins, 3), a(ins, 4) }) end
  L.bwbuildingfree = L.bwbuildingfree or function(ins, s) emit(s, { "g5_bld_free", a(ins, 1) }) end
  L.bwbuildingplay = L.bwbuildingplay or function(ins, s) emit(s, { "g5_bld_play", a(ins, 1), a(ins, 2) }) end
  L.bwbuildingwait = L.bwbuildingwait or function(ins, s) emit(s, { "g5_bld_wait", a(ins, 1) }) end
  L.bwbuildingholdopen = L.bwbuildingholdopen or function(ins, s) emit(s, { "g5_bld_hold_open", a(ins, 1), a(ins, 2), a(ins, 3) }) end
  L.bwbuildingstop = L.bwbuildingstop or function(ins, s) emit(s, { "g5_bld_stop", a(ins, 1) }) end
  L.bwbuildingshow = L.bwbuildingshow or function(ins, s) emit(s, { "g5_bld_show", a(ins, 1), a(ins, 2), a(ins, 3), a(ins, 4) }) end
  L.bwbuildingloop = L.bwbuildingloop or function(ins, s) emit(s, { "g5_bld_loop", a(ins, 1), a(ins, 2), a(ins, 3) }) end
end

return M
