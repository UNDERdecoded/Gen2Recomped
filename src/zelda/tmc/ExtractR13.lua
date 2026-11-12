-- Round 13: small tables read from the player's ROM at import time
-- (manifest.r13).  Nothing here is shipped: each entry names the ROM
-- address it is read from (USA, BZME).
local ExtractR13 = {}

function ExtractR13.run(rom, manifest)
  local t = {}
  -- holeManager.c gHoleTransitions ($08108764, 61 x 20 bytes): type,
  -- area, room, layer, u16 x, u16 y, hole x / y / width / height (tiles),
  -- two pointers (parallax art, not used here)
  t.holes = {}
  for i = 0, 60 do
    local a = 0x08108764 + i * 20
    if not rom:valid(a + 19) then break end
    t.holes[i] = { type = rom:u8(a), area = rom:u8(a + 1), room = rom:u8(a + 2), layer = rom:u8(a + 3),
                   x = rom:u16(a + 4), y = rom:u16(a + 6), hx = rom:u8(a + 8), hy = rom:u8(a + 9),
                   hw = rom:u8(a + 10), hh = rom:u8(a + 11) }
  end
  if ExtractR13.more then ExtractR13.more(rom, t) end
  manifest.r13 = t
end

return ExtractR13
