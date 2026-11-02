-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S FERRY CROSSINGS: the two 3D apps PlayBoatCutscene runs between
-- the harbours (pokeplatinum src/cutscenes/boat_cutscene/canalave_ship.c and
-- snowpoint_ship.c).  Each draws ONE model with its animations, read member by
-- member from its own archive, indexed by the cutscene's travel direction
-- (constants/boat_cutscene.h: 0 SOUTH_TO_NORTH, 1 EAST_TO_WEST,
-- 2 WEST_TO_EAST, 3 NORTH_TO_SOUTH):
--
--   canalave_ship.c  /arc/ship_demo.narc, NUM_ANIMATIONS 4
--       narcMemberIndexes[4] = { 2, {0,1,3,4} }, { 7, {5,6,8,9} },
--                              { 12, {10,11,13,14} }, { 17, {15,16,18,19} }
--   snowpoint_ship.c /arc/ship_demo_pl.narc, NUM_ANIMATIONS 3
--       narcMemberIndexes[4] = { 1, {3,2,0} }, { 5, {7,6,4} },
--                              { 1, {3,2,0} }, { 1, {3,2,0} }
--
-- and FieldTask_PlayBoatTravelCutscene picks the app: EAST_TO_WEST and
-- WEST_TO_EAST the Snowpoint ship, the other two the Canalave one.  So the
-- four crossings the game can reach are
--
--   0 S->N  ship_demo     model  2, anims 0 BCA, 1 BMA, 3 BTA, 4 BTP
--   1 E->W  ship_demo_pl  model  5, anims 7 BCA, 6 BMA, 4 BTA
--   2 W->E  ship_demo_pl  model  1, anims 3 BCA, 2 BMA, 0 BTA
--   3 N->S  ship_demo     model 17, anims 15 BCA, 16 BMA, 18 BTA, 19 BTP
--
-- every track 90 frames; the app fades out when anims[0] reaches its last.
-- Each model is packed the way Gen4SpearPillarArt packs its parts (same
-- Gen4ModelPack + textures, the tracks kept separate in load order), so
-- src/ui/Gen4BoatTravelScene.lua draws it with the Spear Pillar's model path.

local A = { CANALAVE = "/arc/ship_demo.narc", SNOWPOINT = "/arc/ship_demo_pl.narc" }

A.CROSSINGS = {
  [0] = { arc = "CANALAVE", model = 2, anims = { 0, 1, 3, 4 } },
  [1] = { arc = "SNOWPOINT", model = 5, anims = { 7, 6, 4 } },
  [2] = { arc = "SNOWPOINT", model = 1, anims = { 3, 2, 0 } },
  [3] = { arc = "CANALAVE", model = 17, anims = { 15, 16, 18, 19 } },
}

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local Pack = require("src.import.Gen4ModelPack")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local arcs = {}
  for key in pairs({ CANALAVE = true, SNOWPOINT = true }) do
    arcs[key] = assert(Narc.parse(assert(x.rom:read(A[key]), "no " .. A[key])))
  end
  local function member(arcKey, i)
    local b = assert(arcs[arcKey]:get(i), A[arcKey] .. " member " .. tostring(i))
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local out = { source = "ROM:" .. A.CANALAVE .. " + " .. A.SNOWPOINT
                .. " (pokeplatinum src/cutscenes/boat_cutscene)", crossings = {} }
  local written = {}

  local function textureImage(prefix, tex, bytes, name, paletteName)
    local key = prefix .. name .. "/" .. tostring(paletteName)
    if written[key] ~= nil then return written[key] end
    local ti, pi
    for k, t in ipairs(tex.textures) do if t.name == name then ti = k end end
    for k, p in ipairs(tex.palettes) do if p.name == paletteName then pi = k end end
    if not ti then written[key] = false return false end
    local image = Models.decode(tex, bytes, ti, pi or 1)
    local saved = image and x:saveImage(("boat_cutscene/%s%s_%d"):format(prefix, name, pi or 1), image)
    written[key] = saved and (type(saved) == "table" and saved.path or saved) or false
    return written[key]
  end

  local function shapeNodes(ops)
    local map, node = {}, nil
    for _, op in ipairs(ops or {}) do
      if op.op == "node" then node = op.node
      elseif op.op == "shape" and node then map[op.shape] = node end
    end
    return map
  end

  for dir, spec in pairs(A.CROSSINGS) do
    local ok, err = pcall(function()
      local bytes = member(spec.arc, spec.model)
      local parsed = assert(Nsbmd.parse(bytes))
      local packed = Pack.pack(assert(parsed.models[1]))
      local texAt = bytes:find("TEX0", 1, true)
      local tex = texAt and Models.parse(bytes, texAt - 1)
      local prefix = ("%s%d_"):format(spec.arc == "CANALAVE" and "c" or "s", spec.model)
      for _, shape in ipairs(packed.shapes) do
        if shape.texture and tex then
          shape.image = textureImage(prefix, tex, bytes, shape.texture, shape.palette) or nil
        end
      end
      packed.shapeNodes = shapeNodes(packed.ops)
      local part = { model = packed, tracks = {}, member = spec.model, archive = A[spec.arc] }
      for k, m in ipairs(spec.anims) do
        local data = member(spec.arc, m)
        local parsed2 = Anim.parse(data)
        local animation = parsed2 and parsed2.animations and parsed2.animations[1]
        local track = { member = m, kind = parsed2 and parsed2.kind, frames = 1 }
        if animation then
          track.frames = math.max(1, tonumber(animation.frames) or 1)
          local kind = parsed2.kind
          if kind == "BCA0" then
            local motion = { frames = track.frames, tracks = {} }
            for _, joint in ipairs(Anim.jointMatrices(data, animation) or {}) do
              motion.tracks[joint.index] = Anim.packTrack(joint.track)
            end
            track.motion = motion
          elseif kind == "BTA0" then
            track.record = { kind = "BTA0", frames = track.frames, srt = Anim.textureSrt(data, animation) }
          elseif kind == "BTP0" then
            local pattern = Anim.texturePattern(data, animation)
            track.record = { kind = "BTP0", frames = track.frames, pattern = pattern }
            packed.patternImages = packed.patternImages or {}
            for i, texName in ipairs((pattern and pattern.textures) or {}) do
              if packed.patternImages[texName] == nil and tex then
                local pal = (pattern.palettes or {})[i] or (pattern.palettes or {})[1]
                packed.patternImages[texName] = textureImage(prefix, tex, bytes, texName, pal)
              end
            end
          elseif kind == "BMA0" then
            track.record = { kind = "BMA0", frames = track.frames, colour = Anim.materialColour(data, animation) }
          elseif kind == "BVA0" then
            track.visibility = Anim.visibility(data, animation)
          end
        end
        part.tracks[k] = track
      end
      out.crossings[dir] = part
    end)
    if not ok then
      out.failed = out.failed or {}
      out.failed[dir] = tostring(err)
    end
  end
  return out
end

return A
