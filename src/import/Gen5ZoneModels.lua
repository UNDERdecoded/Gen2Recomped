-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ABYSSAL RUINS' OVERLAY MODELS, /a/1/9/0 -> constants.gen5ZoneModels.
--
-- READ FROM CODE (Black): script command 0x135 (ov21 0x021CFA58, no
-- operands; the Ruins' map scripts M0482..M0488 run it on load) starts the
-- zone effect overlay 57 through 0x021BB990 with the record at ov57
-- 0x021F3900 = { 0x80, work 0x44, init 0x021F36C0, exit 0x021F37BC,
-- update 0x021F381C, draw 0x021F3858 }:
--   init: archive 0xBE (/a/1/9/0) members in the order of 0x021F38A8
--         {1, 3, 5, 2, 4, 6, 0}: three BMD0 (with their own TEX0, uploaded
--         0x02046FF8), three BTA0, one BMA0; models 0..2 = members 1 / 3 / 5
--         (0x021F387C); the four animations bind (0x02047564) model
--         {0, 1, 2, 0} (0x021F3888) to member {2, 4, 6, 0} (0x021F3898), and
--         render object 0 plays animations 0 and 3 (its BTA and the BMA),
--         1 plays 1, 2 plays 2 (0x020477A4)
--   update: every animation steps 0x1000 (one frame) a field frame
--         (0x02047910)
--   draw: all three at the fixed position 0x021F38C4 = fx32 (256, 0, 256),
--         scale 1, no rotation (0x021F38D0..0x021F38FC), through 0x02047A60
-- Packed the way Gen4HgssFieldFx packs its parts: each model through
-- Gen4ModelPack with its own textures (written under bw_zone_models/), its
-- animations as Gen4TexAnim records.

local M = {}

M.PATH = "/a/1/9/0"
-- { model member, { animation members } }, model order = render order
M.PARTS = { { 1, { 2, 0 } }, { 3, { 4 } }, { 5, { 6 } } }
M.POSITION = { 256, 0, 256 }

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local Pack = require("src.import.Gen4ModelPack")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local arc = assert(Narc.parse(assert(rom:read(M.PATH))))
  local function member(i)
    local b = assert(arc:get(i))
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local out = { source = "ROM:" .. M.PATH .. " (ov57 0x021F36C0, script 0x135)", position = M.POSITION,
                models = {}, records = {} }
  for pi, part in ipairs(M.PARTS) do
    local bytes = member(part[1])
    local parsed = assert(Nsbmd.parse(bytes))
    local packed = Pack.pack(assert(parsed.models[1]))
    local texAt = bytes:find("TEX0", 1, true)
    local tex = texAt and Models.parse(bytes, texAt - 1)
    local written = {}
    for _, shape in ipairs(packed.shapes) do
      local name = shape.texture
      if name and tex then
        local key = name .. "/" .. tostring(shape.palette)
        if written[key] == nil then
          local ti, pal
          for k, t in ipairs(tex.textures) do if t.name == name then ti = k end end
          for k, p in ipairs(tex.palettes or {}) do if p.name == shape.palette then pal = k end end
          local image = ti and Models.decode(tex, bytes, ti, pal or 1)
          local saved = image and x.saveImage and x:saveImage(("bw_zone_models/m%d_%s_%d"):format(part[1],
            name:gsub("[^%w_%-]", "_"), pal or 1), image)
          written[key] = saved and (type(saved) == "table" and saved.path or saved) or false
        end
        shape.image = written[key] or nil
      end
    end
    packed.member = part[1]
    out.models[pi] = packed
    local records = {}
    for _, a in ipairs(part[2]) do
      local data = member(a)
      local p = Anim.parse(data)
      local animation = p and p.animations and p.animations[1]
      if animation then
        local frames = tonumber(animation.frames) or 0
        if p.kind == "BTA0" then
          records[#records + 1] = { kind = "BTA0", member = a, frames = frames, srt = Anim.textureSrt(data, animation) }
        elseif p.kind == "BMA0" then
          records[#records + 1] = { kind = "BMA0", member = a, frames = frames, colour = Anim.materialColour(data, animation) }
        end
      end
    end
    out.records[pi] = records
  end
  return out
end

return M
