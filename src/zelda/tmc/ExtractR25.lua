-- Round 25: tables read from the player's ROM at import time (manifest.r25).
-- Nothing here is shipped; each entry names where it is read from (USA, BZME).
local ExtractR25 = {}

-- data/const/enemy/gleerok.s: gUnk_080CD7C4 .. gUnk_080CD884 (+31) -- the
-- neck's sprite priorities, the intro's and the death's neck moves
-- (gUnk_080CD7F8), the phase health thresholds (gUnk_080CD844), the
-- weighted waits (gUnk_080CD850 / 854 / 858..867) and the plug's palette
-- steps (gUnk_080CD884).  Kept as the raw bytes of the whole block.
ExtractR25.GLEEROK_LO, ExtractR25.GLEEROK_HI = 0x080CD7C4, 0x080CD8A4
function ExtractR25.gleerok(rom)
  local t = {}
  for a = ExtractR25.GLEEROK_LO, ExtractR25.GLEEROK_HI - 1 do t[#t + 1] = rom:u8(a) end
  return t
end

function ExtractR25.run(rom, manifest)
  manifest.r25 = { gleerok = ExtractR25.gleerok(rom) }
end

-- a reader over the block: u8 at a ROM address (nil manifest: nil)
function ExtractR25.gleerokTables(manifest)
  local t = manifest and manifest.r25 and manifest.r25.gleerok
  if not t then return nil end
  local function u8(a) return t[a - ExtractR25.GLEEROK_LO + 1] or 0 end
  return { u8 = u8, s8 = function(a) local v = u8(a) return v >= 128 and v - 256 or v end }
end

return ExtractR25
