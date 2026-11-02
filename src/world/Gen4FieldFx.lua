-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S OBSTACLE ANIMATIONS: the tree cut, the rock
-- breaking, the tree shaking under a Headbutt (ScrCmd_560).
--
-- ScrCmd_560 <kind, var> (scrcmd_c.c) -> ov02_0224E074: zeroes the var,
-- builds the kind's 3D object (src/import/Gen4HgssFieldFx.lua: /a/1/3/4) on
-- the facing tile's centre at the player's height (ov02_0224D044), plays its
-- sound, and runs a SysTask that advances every animation one frame a field
-- frame until all have ended -- then writes 1 to the var (ov02_0224E020). The
-- field-move script (scr_seq_0146) spins `Wait 1` until the var is nonzero, so
-- the script resumes exactly when the animation is over.
--
-- HEADBUTT also jolts the camera (ov02_0224DB9C): two beats of two frames,
-- the look-at position and target moved 8 units toward the player's facing
-- (Camera_OffsetLookAtPosAndTarget) and then put back.

local M = {}

M.KINDS = {
  [0] = { part = "cut", se = "SEQ_SE_DP_FW015" },
  [3] = { part = "cut", se = "SEQ_SE_DP_FW015" },
  [1] = { part = "rockSmash", se = "SEQ_SE_DP_FW088" },
  [2] = { part = "rockSmash", se = "SEQ_SE_DP_FW088" },
  [4] = { part = "headbutt", se = "SEQ_SE_GS_ZUTUKI", shake = true },
  [5] = { part = "headbutt", se = "SEQ_SE_GS_ZUTUKI", shake = true },
}
M.SHAKE_UNITS, M.SHAKE_BEATS = 8, 2
M.TICKS_PER_FRAME = 2

local function Game() return package.loaded["src.core.Game"] end

local function art()
  local G = Game()
  -- ...or Platinum's (src/import/Gen4PtFieldFx.lua: /graphic/hiden_effect.narc,
  -- ScrCmd_StartDestroyObstacleAnimation kinds 0 cut, 1 / 2 rock smash -- the
  -- same members, sounds and placement as HGSS's kinds 0..2)
  -- ...or Black / White's scripted objects, Zorua's illusion and N's Castle's
  -- (src/import/Gen5IllusionFx.lua, played by src/world/Gen5IllusionFx.lua)
  return G and G.data and (G.data.gen4_hgss_field_fx or G.data.gen4_pt_field_fx
    or (G.data.constants and G.data.constants.gen5FieldFx))
end

local models = {}
local function modelFor(name)
  if models[name] ~= nil then return models[name] or nil end
  local a = art()
  local part = a and a.parts and a.parts[name]
  local ok, m = false, nil
  if part then ok, m = pcall(require("src.render.Gen4Model").new, part.model) end
  models[name] = ok and m or false
  return ok and m or nil
end

local function groundOf(ow)
  return ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
end

local function playSe(key)
  local G = Game()
  pcall(function() require("src.core.Sound").playSe(G.data, key) end)
end

-- the headbutt jolt: the look-at offset (map pixels; Gen4 units are pixels)
-- for the facing, as OverworldState:followCamera reads gen4ShakeOffset
function M.shakeVector(facing)
  local u = M.SHAKE_UNITS
  if facing == "up" then return 0, u
  elseif facing == "down" then return 0, -u
  elseif facing == "left" then return -u, 0 end
  return u, 0
end

-- the camera beat at field frame `f` (ov02_0224DB9C's toggle): true while the
-- offset is applied
function M.shakeOn(f)
  if f >= M.SHAKE_BEATS * 4 then return false end
  return f % 4 < 2
end

-- ScrCmd_560: true when an animation started (the var is written when it
-- ends); false when this cache has no art for it (the caller writes the var)
function M.start(ow, kind, onDone)
  local spec = M.KINDS[math.floor(tonumber(kind) or -1)]
  local a = art()
  local part = spec and a and a.parts and a.parts[spec.part]
  local p = ow and ow.player
  if not (part and p and modelFor(spec.part)) then return false end
  local fx, fy = p:facingCell()
  local ground = groundOf(ow)
  local y = ground and ground:groundY((p.px or 0) + 8, (p.py or 0) + 8) or 0
  ow.gen4FieldFx = ow.gen4FieldFx or {}
  local fxs = ow.gen4FieldFx
  fxs[#fxs + 1] = { part = spec.part, frame = 0, tick = 0, frames = math.max(1, part.frames or 1),
                    x = fx * 16 + 8, z = fy * 16 + 8, y = y, onDone = onDone, se = spec.se,
                    shake = spec.shake and { M.shakeVector(p.facing) } or nil }
  return true
end

-- one more object of `partName` at map pixels (x, z), height y, tagged so its
-- owner can take it away (Platinum's Rock Climb debris, Gen4RockClimbRide)
function M.spawn(ow, partName, x, z, y, se, tag)
  local a = art()
  local part = a and a.parts and a.parts[partName]
  if not (ow and part and modelFor(partName)) then return false end
  ow.gen4FieldFx = ow.gen4FieldFx or {}
  local fxs = ow.gen4FieldFx
  fxs[#fxs + 1] = { part = partName, frame = 0, tick = 0, frames = math.max(1, part.frames or 1),
                    x = x, z = z, y = y, se = se, tag = tag }
  return true
end

-- every object carrying `tag` goes at once (no onDone)
function M.clear(ow, tag)
  local fxs = ow and ow.gen4FieldFx
  if not fxs then return end
  for i = #fxs, 1, -1 do
    if fxs[i].tag == tag then table.remove(fxs, i) end
  end
  if #fxs == 0 then ow.gen4FieldFx = nil end
end

-- every engine tick (OverworldState:update)
-- (`objectsOnly`: from OverworldState:animate, the field under a message --
-- the objects play on, the Rock Climb ride does not)
function M.tick(ow, objectsOnly)
  -- Platinum's Rock Climb places its debris from here (Gen4RockClimbRide)
  if ow and ow.gen4RockClimb and not objectsOnly then require("src.world.Gen4RockClimbRide").tick(ow) end
  local fxs = ow and ow.gen4FieldFx
  if not fxs then return end
  local shake
  for i = #fxs, 1, -1 do
    local e = fxs[i]
    e.tick = e.tick + 1
    -- the sound with the first frame the field draws it (a cut-in still on
    -- screen holds the field, and so the object, back)
    if e.tick == 1 and e.se then playSe(e.se) end
    if e.tick % M.TICKS_PER_FRAME == 0 then
      e.frame = e.frame + 1
      -- an owner's per-frame move (BW's 0x255 carry, Gen5IllusionFx)
      if e.onFrame then pcall(e.onFrame, e) end
    end
    if e.shake and M.shakeOn(e.frame) then shake = e.shake end
    if e.frame >= e.frames then
      table.remove(fxs, i)
      if e.onDone then pcall(e.onDone) end
    end
  end
  -- the jolt, without stepping on a script's own ScreenShake
  if shake then
    ow.gen4FieldFxShake = true
    ow.gen4ShakeOffset = { shake[1], shake[2] }
  elseif ow.gen4FieldFxShake then
    ow.gen4FieldFxShake = nil
    ow.gen4ShakeOffset = nil
  end
  if #fxs == 0 then ow.gen4FieldFx = nil end
end

local function poseAndMaterials(mdl, e)
  local a = art()
  local part = a.parts[e.part]
  local Anim = require("src.import.Gen4Anim")
  local frame = math.min(e.frame, e.frames - 1)
  local motion = part.motion
  local pose = motion and mdl:posed(function(node)
    local track = motion.tracks[node]
    return track and Anim.unpackFrame(track, math.min(frame, (motion.frames or 1) - 1)) or nil
  end) or nil
  local mats = require("src.render.Gen4TexAnim").materials(part.records, frame, part.model.patternImages)
  return pose, mats
end

local function current()
  local G = Game()
  local ow = G and G.overworld
  return ow and ow.gen4FieldFx and ow or nil
end

-- the field camera's live pass (Gen4Ground, beside the surf mount)
function M.drawLive(ground, left, top, vw, vh)
  -- Platinum's Rock Climb mount (`rock_ride`, Gen4RockClimbRide)
  local Gm = Game()
  if Gm and Gm.overworld and Gm.overworld.gen4RockClimb then
    require("src.world.Gen4RockClimbRide").drawLive(ground, left, top, vw, vh)
  end
  local ow = current()
  if not ow then return end
  local Gen4Model = require("src.render.Gen4Model")
  local Gen4Ground = require("src.render.Gen4Ground")
  local half = ground.half or 0
  for _, e in ipairs(ow.gen4FieldFx) do
    local mdl = modelFor(e.part)
    if mdl then
      local pose, mats = poseAndMaterials(mdl, e)
      local base = ground:screenMatrix(e.x + (ground.offsetX or 0) - left - half,
                                       e.z + (ground.offsetY or 0) - top - half, vw, vh)
      local m = Gen4Ground.liftMatrix(base, e.y)
      local spread = Gen4Ground.liftedSpread and Gen4Ground.liftedSpread(ground.spread, e.y) or ground.spread
      mdl:draw(m, pose, mats, nil, spread)
    end
  end
end

-- the 3D view's pass (Gen4Ground:drawFree)
function M.drawFree(ground, vp)
  local Gm = Game()
  if Gm and Gm.overworld and Gm.overworld.gen4RockClimb then
    require("src.world.Gen4RockClimbRide").drawFree(ground, vp)
  end
  local ow = current()
  if not ow then return end
  local Gen4Model = require("src.render.Gen4Model")
  for _, e in ipairs(ow.gen4FieldFx) do
    local mdl = modelFor(e.part)
    if mdl then
      local pose, mats = poseAndMaterials(mdl, e)
      local m = Gen4Model.multiply(vp, { 1, 0, 0, e.x + (ground.offsetX or 0),
                                         0, 1, 0, e.y,
                                         0, 0, 1, e.z + (ground.offsetY or 0),
                                         0, 0, 0, 1 })
      mdl:draw(m, pose, mats)
    end
  end
end

return M
