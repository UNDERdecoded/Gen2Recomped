-- Gen1Recomp-derived code: GPLv3 plus Additional Terms; see
-- compat/gen1-gsc/LICENSE.MD and provenance.json. Existing rights retained.
-- GSC byte arithmetic and sine from Gen1Recomp's AnimObjects/SpriteAnims at
-- 535a5ec0. Existing source rights/licences remain under compat/gen1-gsc/LICENSE.MD.
-- This is arithmetic only; the native VM still owns its objects and clock.
local bit = require('bit')
local M = {}
function M.u8(value) return value % 256 end
local function s8(value)
  value = value % 256
  return value < 0x80 and value or value - 256
end
function M.sra(value) return M.u8(math.floor(s8(value) / 2)) end
function M.swap(value)
  value = M.u8(value)
  return bit.bor(bit.rshift(value,4), bit.band(bit.lshift(value,4),0xf0))
end
local sine = {}
for i=0,31 do sine[i] = math.floor(math.sin(i*math.pi/32)*256+0.5) end
function M.sine(angle, amplitude)
  angle = angle % 64
  local negative = angle >= 32
  if negative then angle = angle - 32 end
  local product = (amplitude % 256) * sine[angle] % 0x10000
  local result = math.floor(product / 256)
  if negative then result = -result end
  return result % 256
end
function M.cosine(angle, amplitude) return M.sine(angle+0x10,amplitude) end
return M
