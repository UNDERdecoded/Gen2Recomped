-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- N'S PORTRAIT, /a/1/8/7 -> constants.gen5NPortrait (+ bw_nportrait/*.png).
--
-- READ FROM CODE (Black, overlay 82, loaded by 0x1D3 -- ov10 0x02164910):
-- N's last words in his castle are spoken over a full-screen picture, not
-- the field. 0x021F53B4 builds it on the main screen:
--   BG2 (priority 2): chars member 4 + mode, screen member 8 + mode,
--        palette member 0 + mode (0x140 bytes) -- mode is 0x1D3's first
--        operand: 0 a sunlit hall, 1 the throne room's light, 2 all white
--   BG3 (priority 1): N himself, chars member 7, screen member 11, in the
--        same palette
--   the 3D field (BG0) is pushed under both (priority 3)
-- and two tile animations run on BG3 (0x021F5748, copied in at VBlank by
-- 0x021F57D8): the EYES, six by two cells at (13, 8), tiles 0x160 + 12 * f
-- in the order 0,1,2,1,0 (table 0x021F58E0), and the MOUTH, four by two at
-- (14, 11), tiles 0x184 + 8 * f in the order 1,2,1,0 (table 0x021F58D0).
-- The face is the same in all three palettes (checked), so it is written
-- once; each frame patch is its own small image.

local M = {}

M.PATH = "/a/1/8/7"
M.EYES = { x = 13, y = 8, w = 6, h = 2, base = 0x160, per = 12, frames = 3 }
M.MOUTH = { x = 14, y = 11, w = 4, h = 2, base = 0x184, per = 8, frames = 3 }

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local G = require("src.import.Gen4Graphics")
  local Lz = require("src.import.Gen5Lz")
  local ok, bytes = pcall(function() return rom:read(M.PATH) end)
  if not (ok and bytes) then return nil, "no " .. M.PATH end
  local arc = require("src.import.NarcArchive").parse(bytes)
  local function member(i)
    local b = assert(arc:get(i))
    if Lz.isCompressed(b) then return assert(Lz.decompress(b)) end
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local out = { bg = {}, eyes = {}, mouth = {}, eyeAt = { M.EYES.x * 8, M.EYES.y * 8 },
                mouthAt = { M.MOUTH.x * 8, M.MOUTH.y * 8 }, source = "ROM:" .. M.PATH }
  for mode = 0, 2 do
    local pal = assert(G.palette(member(mode)))
    local pic = assert(G.compose(assert(G.tilemap(member(8 + mode))), assert(G.tiles(member(4 + mode))), pal))
    out.bg[mode] = x:saveImage("bw_nportrait/bg" .. mode, pic)
  end
  local pal = assert(G.palette(member(1)))
  local sheet = assert(G.tiles(member(7)))
  local face = assert(G.tilemap(member(11)))
  local pic = assert(G.compose(face, sheet, pal))
  out.face = x:saveImage("bw_nportrait/face", pic)
  -- a frame patch: the tiles base + per * f laid out w x h in reading order
  local function patch(spec, f)
    local cells = {}
    for k = 0, spec.w * spec.h - 1 do
      cells[k + 1] = { tile = spec.base + spec.per * f + k, palette = 0, flipX = false, flipY = false }
    end
    return G.compose({ width = spec.w * 8, height = spec.h * 8, cells = cells, linear = true }, sheet, pal)
  end
  for f = 0, M.EYES.frames - 1 do out.eyes[f] = x:saveImage("bw_nportrait/eyes" .. f, assert(patch(M.EYES, f))) end
  for f = 0, M.MOUTH.frames - 1 do out.mouth[f] = x:saveImage("bw_nportrait/mouth" .. f, assert(patch(M.MOUTH, f))) end
  return out
end

return M
