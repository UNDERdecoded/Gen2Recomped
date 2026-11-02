-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S BALL CAPSULE SEAL EFFECTS: what a decorated capsule sprays when
-- its Pokemon is sent out (pokeplatinum src/battle_anim/ov12_02235E94.c,
-- BallCapsuleSealEffect, and ov12_02237E54.c), on the effects
-- `ball_particle.narc` holds -- imported as gen4_particles.effects["ball_<n>"]
-- (src/import/Gen4Particle.lua) and run by src/battle/Gen4ParticleSystem.lua.
--
-- READ FROM CODE:
--   * every seal on the capsule (ov12_022360A0, two a frame) loads effect
--     CapsuleMenu_GetSealParticleIndex(type) and creates its emitter 0
--     (ov12_02236430, ParticleSystem_CreateEmitterWithCallback(sys, 0, ...));
--   * each starts after its own delay (ov12_02237EA0): an alphabet seal 8
--     frames, any other {0, 8, 14, 20}[distance from the ball's centre
--     (190, 70) / 20, 3 at 56 or more] -- the seals near the middle first;
--   * where (ov12_022365D4 / ov12_02236520): the battler's position, less the
--     battler type's offset ((10 + v2), (32 + v3)) and plus the seal's own
--     ((x - 190), (70 - y + 30)), all in units of 172 = one pixel;
--   * no capsule: the ball's own burst (ov12_02235F64) -- not drawn here, the
--     ball throw (Gen4BallAnim) already opens.
-- INFERRED: the battler position is the port's battler spot (Gen4Battle.
-- battlerPos / the app's stage); the 3D projection is flattened as
-- everywhere in Gen4ParticleSystem.

local E = {}
E.__index = E

-- capsule_menu/main.c sealTypeValues[].particleIndex, by seal id
E.PARTICLE = { [0] = 37, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 57, 58, 59, 60,
  53, 54, 55, 56, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82,
  83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106,
  107, 108, 109, 110, 111, 112, 113, 114, 115, 116 }
-- ...and .nameIndex (bank 12), for the Seal Club Show
E.NAME = { [0] = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 77, 16, 17, 18, 19, 20, 21, 22, 23,
  24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
  50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75,
  76, 78, 79, 80 }
function E.isAlphabet(id) id = tonumber(id) or 0; return id >= 50 and id <= 77 end

-- ov12_02236520's per-battler-type offsets {v2, v3}
E.TYPE_OFFSET = { [0] = { 0, -16 }, { -15, -25 }, { -8, -12 }, { -14, -25 }, { -8, -12 }, { -16, -29 } }

-- ov12_02237EA0
function E.delay(seal)
  local steps = { [0] = 0, 8, 14, 20, 20, 16, 16 }
  if E.isAlphabet(seal.type) then return steps[1] end
  local SC = require("src.pokemon.Gen4SealCase")
  local d = SC.distance(tonumber(seal.x) or 0, tonumber(seal.y) or 0, SC.CENTER_X, SC.CENTER_Y)
  local k
  if d >= 60 - 4 then k = 3 else k = math.floor((d + 1) / 20); if k >= 3 then k = 3 end end
  return steps[k]
end

-- new(data, capsule, battlerType) -> nil when the capsule has no seals
function E.new(data, capsule, battlerType)
  local PS = require("src.battle.Gen4ParticleSystem")
  local effects = data and data.gen4_particles and data.gen4_particles.effects
  if type(effects) ~= "table" or type(capsule) ~= "table" then return nil end
  local self = setmetatable({ list = {}, frame = 0 }, E)
  local off = E.TYPE_OFFSET[tonumber(battlerType) or 0] or E.TYPE_OFFSET[5]
  for k = 1, 8 do
    local s = capsule.seals and capsule.seals[k]
    local id = s and tonumber(s.type) or 0
    if id > 0 and id <= 80 then
      local entry = effects["ball_" .. E.PARTICLE[id]]
      local sys = entry and entry.emitters and PS.resource(entry.emitters, 0)
      if sys then
        sys:start(1009 * k + id)
        self.list[#self.list + 1] = {
          sys = sys, art = entry.textures, wait = E.delay(s), started = false,
          -- pixels from the battler (+y down): the seal's place on the ball
          -- less the battler type's own correction
          dx = ((tonumber(s.x) or 0) - 190) - (10 + off[1]),
          dy = -((70 - (tonumber(s.y) or 0) + 30) - (32 + off[2])),
        }
      end
    end
  end
  if #self.list == 0 then return nil end
  return self
end

-- one frame; false once every emitter has finished (ov12_022363CC)
function E:update()
  self.frame = self.frame + 1
  local alive = false
  for _, e in ipairs(self.list) do
    if not e.done then
      if not e.started then
        if e.wait <= 0 then e.started = true else e.wait = e.wait - 1 end
        alive = true
      end
      if e.started then
        if e.sys:update() then alive = true else e.done = true end
      end
    end
  end
  self.alive = alive
  return alive
end

function E:isDone() return self.alive == false end

-- draw around the battler at (x, y)
function E:draw(x, y)
  local Assets = require("src.render.Assets")
  local g = love.graphics
  for _, e in ipairs(self.list) do
    if e.started and not e.done then
      e.sys:draw(x + e.dx, y + e.dy, function(texture, px, py, sx, sy, alpha, rot, colour)
        local art = e.art and e.art[(tonumber(texture) or 0) + 1]
        local ok, img = pcall(Assets.image, art and art.path)
        if ok and img then
          local a = math.max(0, math.min(1, tonumber(alpha) or 1))
          if colour then g.setColor((colour[1] or 255) / 255, (colour[2] or 255) / 255, (colour[3] or 255) / 255, a)
          else g.setColor(1, 1, 1, a) end
          local w, h = img:getDimensions()
          g.draw(img, px, py, rot or 0, sx or 1, sy or sx or 1, w / 2, h / 2)
        end
      end)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return E
