-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER: THE MYSTRI STAGE GYMMICK at the Sinjoh Ruins
-- (pokeheartgold src/field/gymmick/sinjoh.c), on map D51R0201.
--
-- READ FROM CODE
--   * MystriStageGymmickInit (FieldSystem_InitMystriStageGymmick): the save's
--     gymmick becomes GYMMICK_SINJOH with choice 0 -- here save.hgssSinjoh.
--   * GymmickInit_Sinjoh on the map: three models out of /a/1/7/4 (101, 104,
--     107, animations 102/103, 105/106, 108/109) at (200, 16, 248),
--     (328, 16, 248), (264, 16, 136), every animation at frame 0.
--   * SysTask_SinjohGymmick, every field frame: each model's two animations
--     advance one frame; at 30 (idle, animId 0) or 60 (animId 1) the model
--     takes its next animId -- 1 for the chosen one (choice 1..3 = model
--     1..3), else 0 -- and restarts at 30 or 0. A pass whose LAST model
--     wrapped ends the "active" wait.
--   * ScrCmd_820 <choice> (SinjohGymmick_SetChosenLegend): the choice into
--     the save and the script waits until that wrap; ScrCmd_819
--     (SinjohGymmick_FreezeAllModels): the three stop drawing.
-- Drawn in Gen4Ground's live and free passes (hooks beside HgssHideoutFx's).

local M = {}

M.MAP = "D51R0201"
M.PARTS = { "sinjoh1", "sinjoh2", "sinjoh3" }
M.POS = { { 200, 16, 248 }, { 328, 16, 248 }, { 264, 16, 136 } }
M.TICKS_PER_FRAME = 2

M.objects = nil   -- { { part, frame, animId, x, y, z } x3 } while on the map

local function art(data)
  local a = data and data.gen4_legend_art
  return type(a) == "table" and type(a.parts) == "table" and a.parts or nil
end

function M.init(save)
  save.hgssSinjoh = { choice = 0 }
end

-- GymmickInit_Sinjoh / GymmickFree_Sinjoh with the map
function M.onMapEntered(game, ow)
  M.objects, M.tick, M.waiting = nil, 0, nil
  local save = game and game.save
  if not (ow and ow.map and ow.map.id == M.MAP and save and type(save.hgssSinjoh) == "table") then return end
  local parts = art(game.data)
  if not (parts and parts.sinjoh1) then return end
  M.objects = {}
  for i, name in ipairs(M.PARTS) do
    local p = M.POS[i]
    M.objects[i] = { part = name, frame = 0, animId = 0, x = p[1], y = p[2], z = p[3], active = true }
  end
end

-- one field frame of SysTask_SinjohGymmick
local function step(save)
  local choice = (save.hgssSinjoh or {}).choice or 0
  local finished = false
  for i, o in ipairs(M.objects) do
    local want = (choice == i) and 1 or 0
    local endFrame = (o.animId ~= 0) and 60 or 30
    local ended = o.frame + 1 >= endFrame
    o.frame = o.frame + 1
    if ended then
      o.animId = want
      o.frame = (o.animId ~= 0) and 30 or 0
    end
    finished = ended   -- the cartridge keeps only the last model's answer
  end
  if finished then M.waiting = nil end
end

function M.update(game, ow)
  if not M.objects then return end
  if ow and ow.map and ow.map.id ~= M.MAP then M.objects = nil return end
  M.tick = (M.tick or 0) + 1
  if M.tick % M.TICKS_PER_FRAME == 0 then step(game.save) end
end

-- ScrCmd_820: true while the script must wait
function M.choose(game, choice)
  local save = game.save
  save.hgssSinjoh = save.hgssSinjoh or { choice = 0 }
  save.hgssSinjoh.choice = math.floor(tonumber(choice) or 0)
  if not M.objects then return false end
  M.waiting = true
  return true
end

-- ScrCmd_819
function M.freeze()
  for _, o in ipairs(M.objects or {}) do o.active = false end
end

-- -------------------------------------------------- the two cutscenes --
-- READ FROM CODE (src/field/event_cutscene_sinjoh.c), both placed on the
-- following Pokemon (Arceus; FollowMon_GetMapObject's position), every
-- animation one frame per field frame and stopping at its end
-- (FrameAdvanceAndCheck):
--   UnownCircle (Task_SinjohCutscene): white flash out / load / in; the two
--     Unown rings animate at once; the light (model 85) shows; after 100
--     frames it animates too; 150 frames later a white fade out, the models
--     go. The script's Cinematic follows. (The flashes are 2-step brightness
--     fades.)
--   ScrCmd_817 <legend> (Task_SinjohGetEggCutscene): flash out / load / in;
--     egg 0..2 (Dialga / Palkia / Giratina) plays its four animations to the
--     end, then goes.
M.cut = nil

local function partFrames(data, name)
  local parts = art(data)
  local p = parts and parts[name]
  return p and math.max(1, math.floor(tonumber(p.frames) or 1)) or 1
end

local function followPos(game, ow)
  local npc
  local ok, F = pcall(require, "src.world.HgssFollowMon")
  if ok and F and F.current then npc = F.current(ow) end
  if not npc then
    -- obj_partner_poke (253), the object the following Pokemon is
    for _, n in ipairs((ow and ow.npcs) or {}) do
      local lid = n.localId or (n.def and n.def.localId)
      if lid == 253 and not n.hidden then npc = n break end
    end
  end
  local who = npc or (ow and ow.player)
  local x, z = ((who and who.px) or 0) + 8, ((who and who.py) or 0) + 8
  local ground = ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  local y = ground and ground.groundY and ground:groundY(x, z) or 0
  return x, y, z
end

function M.cutsceneLoad(game, ow, kind, legend)
  local data = game.data
  local parts = art(data)
  local x, y, z = followPos(game, ow)
  local function obj(name, running)
    return { part = name, frame = 0, frames = partFrames(data, name), x = x, y = y, z = z,
             active = parts and parts[name] ~= nil, running = running }
  end
  if kind == "unown" then
    local light = obj("sinjohLight", false)
    light.active = false
    M.cut = { kind = kind, n = 0, objs = { obj("sinjohUnown1", true), obj("sinjohUnown2", true), light }, light = light }
  else
    M.cut = { kind = kind, n = 0, objs = { obj("sinjohEgg" .. math.max(0, math.min(2, math.floor(tonumber(legend) or 0))), true) } }
  end
  M.cut.tick = 0
end

-- one field frame; true when the cutscene's own part is over
local function stepCut()
  local c = M.cut
  if not c then return true end
  local allEnded = true
  for _, o in ipairs(c.objs) do
    if o.running then
      if o.frame < o.frames - 1 then o.frame = o.frame + 1 end
      if o.frame < o.frames - 1 then allEnded = false end
    end
  end
  c.n = c.n + 1
  if c.kind == "unown" then
    if c.n == 1 then c.light.active = true end
    if c.n == 100 then c.light.running = true end
    return c.n >= 250
  end
  return allEnded
end

function M.cutsceneTick()
  local c = M.cut
  if not c then return true end
  c.tick = c.tick + 1
  if c.tick % M.TICKS_PER_FRAME ~= 0 then return false end
  return stepCut()
end

function M.cutsceneFree() M.cut = nil end

function M.drawing() return M.objects ~= nil or M.cut ~= nil end

-- ------------------------------------------------------------- drawing --
local models = {}
local function modelFor(parts, name)
  if models[name] ~= nil then return models[name] or nil end
  local part = parts[name]
  local ok, m = false, nil
  if part then ok, m = pcall(require("src.render.Gen4Model").new, part.model) end
  models[name] = ok and m or false
  return ok and m or nil
end

local function poseAndMaterials(mdl, part, frame)
  local Anim = require("src.import.Gen4Anim")
  local motion = part.motion
  local f = math.min(frame, math.max(0, (motion and motion.frames or 1) - 1))
  local pose = motion and mdl:posed(function(node)
    local track = motion.tracks[node]
    return track and Anim.unpackFrame(track, f) or nil
  end) or nil
  local mats = require("src.render.Gen4TexAnim").materials(part.records, frame, part.model.patternImages)
  return pose, mats
end

local function gameData()
  local G = package.loaded["src.core.Game"]
  return G and G.data
end

local function drawList()
  local out = {}
  for _, o in ipairs(M.objects or {}) do out[#out + 1] = o end
  for _, o in ipairs((M.cut and M.cut.objs) or {}) do out[#out + 1] = o end
  return out
end

function M.drawLive(ground, left, top, vw, vh)
  local parts = art(gameData())
  if not (M.drawing() and parts) then return end
  local Gen4Ground = require("src.render.Gen4Ground")
  for _, o in ipairs(drawList()) do
    local mdl, part = o.active and modelFor(parts, o.part), parts[o.part]
    if mdl and part then
      local pose, mats = poseAndMaterials(mdl, part, o.frame)
      local half = ground.half or 0
      local base = ground:screenMatrix(o.x + (ground.offsetX or 0) - left - half,
                                       o.z + (ground.offsetY or 0) - top - half, vw, vh)
      local m = Gen4Ground.liftMatrix(base, o.y)
      local spread = Gen4Ground.liftedSpread and Gen4Ground.liftedSpread(ground.spread, o.y) or ground.spread
      mdl:draw(m, pose, mats, nil, spread)
    end
  end
end

function M.drawFree(ground, vp)
  local parts = art(gameData())
  if not (M.drawing() and parts) then return end
  local Gen4Model = require("src.render.Gen4Model")
  for _, o in ipairs(drawList()) do
    local mdl, part = o.active and modelFor(parts, o.part), parts[o.part]
    if mdl and part then
      local pose, mats = poseAndMaterials(mdl, part, o.frame)
      local m = Gen4Model.multiply(vp, { 1, 0, 0, o.x + (ground.offsetX or 0), 0, 1, 0, o.y,
                                         0, 0, 1, o.z + (ground.offsetY or 0), 0, 0, 0, 1 })
      mdl:draw(m, pose, mats)
    end
  end
end

return M
