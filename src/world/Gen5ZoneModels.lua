-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S ZONE OVERLAY MODELS: the Abyssal Ruins' bubbles, light
-- shafts and water surface (script command 0x135, overlay 57).
--
-- READ FROM CODE (Black; src/import/Gen5ZoneModels.lua has the addresses):
-- 0x135 takes no operands and starts ov57's zone effect, which loads the
-- three models of /a/1/9/0, plays each one's texture scroll (and the
-- bubbles' material fade) one frame a field frame for ever, and draws all
-- three at field position (256, 0, 256). The effect lives until the field
-- is torn down (0x021BB990's slot), so here it is the map's: three props on
-- `def.gen4RuntimeProps` in a new archive, "bwZone", that Gen4Ground:building
-- and Gen4Ground:animationsFor resolve through this module.
-- INFERRED: the field position is the matrix's corner-relative world
-- position Gen4Ground places every prop in (0x02047A60 takes it as is).

local M = {}

M.ARCHIVE = "bwZone"

local function set(ground)
  local def = ground and ground.def
  return def and def.gen5ZoneModels or nil
end

-- the packed model for prop `index` (0-based) of the map's zone models
function M.packed(ground, index)
  local s = set(ground)
  return s and s.models and s.models[(tonumber(index) or -1) + 1] or nil
end

-- its clock-driven animations (Gen4TexAnim records), or nil
function M.animations(ground, index)
  local s = set(ground)
  local list = s and s.records and s.records[(tonumber(index) or -1) + 1]
  if type(list) ~= "table" or #list == 0 then return nil end
  local packed = M.packed(ground, index)
  local images = packed and packed.patternImages
  if not require("src.render.Gen4TexAnim").animates(list, images) then return nil end
  return list, images
end

-- THE TEXTURES ARE TRANSLUCENT (a3i5 / a5i3: the light shafts' texels are at
-- most 58 / 255, the bubbles' 214), blended on the cartridge; the model draws
-- them with their own alpha (Gen4Model.softAlpha) rather than the 0.5 cut,
-- which dropped every texel of all three
function M.soft(model)
  local Gen4Model = require("src.render.Gen4Model")
  local draw = model.draw
  model.draw = function(self, ...)
    local was = Gen4Model.softAlpha
    Gen4Model.softAlpha = true
    local ok, a, b = pcall(draw, self, ...)
    Gen4Model.softAlpha = was
    if not ok then error(a, 0) end
    return a, b
  end
  return model
end

-- place the models on `def` (idempotent: the map's scripts run it on every load)
function M.place(def, models)
  if not (def and type(models) == "table" and type(models.models) == "table") then return false end
  local keep = {}
  for _, p in ipairs(type(def.gen4RuntimeProps) == "table" and def.gen4RuntimeProps or {}) do
    if p.archive ~= M.ARCHIVE then keep[#keep + 1] = p end
  end
  local pos = models.position or { 256, 0, 256 }
  local ox, oz = (def.originX or 0) * 16, (def.originY or 0) * 16
  for i = 1, #models.models do
    keep[#keep + 1] = { model = i - 1, archive = M.ARCHIVE, x = pos[1] - ox, y = pos[2], z = pos[3] - oz }
  end
  def.gen5ZoneModels = models
  def.gen4RuntimeProps = keep
  return true
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
function Commands.g5_zone_models(ctx)
  local ow = ctx and ctx.overworld
  local def = ow and ow.map and ow.map.def
  local data = ctx and ctx.game and ctx.game.data
  local models = data and data.constants and data.constants.gen5ZoneModels
  if def and models and M.place(def, models) then
    -- a ground already baked before the script ran re-splits its props
    local g = ow.map.renderer and ow.map.renderer.gen4Ground
    if g and g.dropBakes then g:dropBakes() end
  end
end

function M.install(L)
  L.bwzonemodels = L.bwzonemodels or function(ins, s) s.out[#s.out + 1] = { "g5_zone_models" } end
end

return M
