-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S GYM FIELD EFFECTS' FLIPBOOK PICTURES, /data/mmodel/fldeff.narc.
-- Written as the cache module `gen4_gym_fx`.
--
-- The models stage reads fldeff.narc's models and its animations, but a
-- texture-pattern animation (BTP0) only gets its pictures decoded when a
-- BUILDING claims it (bm_anime_list); the field effects' own BTP0s claim no
-- building, so the frames below were never written and nothing could play
-- them. READ FROM CODE, member by member (pokeplatinum
-- res/graphics/field_effects, field_effects.naix order):
--
--   111 eterna_gym_fountain.nsbmd   (gym04_hunsui)
--       166 eterna_gym_fountain.nsbtp           gym04_hunsui_a, 18 frames
--       167 eterna_gym_fountain_stopping.nsbtp  gym04_hunsui_b, 27 frames
--       -- ov5_021F4018.c: the running loop and the one-shot stop
--   112 veilstone_gym_tire_stack_toppled.nsbmd (gym07_woodbox)
--       168 veilstone_gym_tire_stack_toppled.nsbtp, 45 frames
--       -- veilstone_gym_object_renderer.c sTireStackAnimIndices 8..11
--
-- Each picture is the model's own TEX0 texture by the name the pattern
-- names, under the palette it names. Out: { models = { [member] =
-- { patternImages = { [texture] = path } } } } -- the same `patternImages`
-- shape the models stage gives a building, merged by Gen4GymFx at run time.

local A = { PATH = "/data/mmodel/fldeff.narc" }

A.MODELS = {
  { model = 111, anims = { 166, 167 } },
  { model = 112, anims = { 168 } },
  -- the Underground's Digger Drill and its smoke (platinum-ug-fx-v1):
  -- 91 ug_ef_drill + 163 ug_ef_drill.nsbtp (ov5_021F5894.c) and
  -- 58 ug_ef_smoke + 162 ug_ef_smoke.nsbtp (ov5_021F55CC.c)
  { model = 91, anims = { 163 } },
  { model = 58, anims = { 162 } },
}

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local arc = assert(Narc.parse(assert(x.rom:read(A.PATH), "no " .. A.PATH)))
  local function member(i)
    local b = assert(arc:get(i), "fldeff member " .. tostring(i))
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local out = { source = "ROM:" .. A.PATH .. " (pokeplatinum res/graphics/field_effects)", models = {} }
  for _, spec in ipairs(A.MODELS) do
    local ok, err = pcall(function()
      local bytes = member(spec.model)
      local texAt = bytes:find("TEX0", 1, true)
      local tex = assert(texAt and Models.parse(bytes, texAt - 1), "no TEX0 in fldeff " .. spec.model)
      local images = {}
      for _, m in ipairs(spec.anims) do
        local data = member(m)
        local parsed = Anim.parse(data)
        local animation = parsed and parsed.animations and parsed.animations[1]
        local pattern = animation and Anim.texturePattern(data, animation)
        for i, texName in ipairs((pattern and pattern.textures) or {}) do
          if images[texName] == nil then
            local pal = (pattern.palettes or {})[i] or (pattern.palettes or {})[1]
            local ti, pi
            for k, t in ipairs(tex.textures) do if t.name == texName then ti = k end end
            for k, p in ipairs(tex.palettes) do if p.name == pal then pi = k end end
            local image = ti and Models.decode(tex, bytes, ti, pi or 1)
            local saved = image and x:saveImage(("gym_fx/m%d_%s"):format(spec.model, texName:gsub("[^%w_%-]", "_")),
                                                image, { texture = texName, palette = pal })
            images[texName] = saved and (type(saved) == "table" and saved.path or saved) or false
          end
        end
      end
      out.models[spec.model] = { patternImages = images }
    end)
    if not ok then
      out.failed = out.failed or {}
      out.failed[spec.model] = tostring(err)
    end
  end
  return out
end

return A
