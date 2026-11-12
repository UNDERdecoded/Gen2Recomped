-- Round 12: small tables read from the player's ROM at import time
-- (manifest.r12).  Nothing here is shipped: each entry names the ROM
-- address it is read from (USA, BZME).
local ExtractR12 = {}

local function s8(v) return v >= 128 and v - 256 or v end

-- a zero-terminated KeyValuePair list {u16 key, u16 value}
local function kvList(rom, a)
  local out = {}
  if not a or not rom:valid(a + 3) then return out end
  for i = 0, 31 do
    local k = rom:u16(a + i * 4)
    if k == 0 then break end
    out[#out + 1] = { k, rom:u16(a + i * 4 + 2) }
  end
  return out
end

function ExtractR12.run(rom, manifest)
  local t = {}
  -- playerUtils.c: ledge jumping (sub_08079550 / sub_08079FD4):
  -- gUnk_0811C100 probe offsets (s8 x, y by facing), gUnk_0811C1E8 the
  -- act tile -> new 8-way facing + 1 lists, gUnk_080082DC the collision
  -- values ($10+) a jump carries on over
  t.ledge = { offsets = {}, jump = {}, coll = {} }
  for i = 0, 3 do t.ledge.offsets[i] = { s8(rom:u8(0x0811C100 + i * 2)), s8(rom:u8(0x0811C100 + i * 2 + 1)) } end
  for i = 0, 3 do t.ledge.jump[i] = kvList(rom, rom:u32(0x0811C1E8 + i * 4)) end
  for i = 0, 0x2F do t.ledge.coll[i] = rom:u8(0x080082DC + i) end
  -- pushableStatue.c sub_0808965C: the statue's fixed gfx per area from
  -- AREA_40 (gUnk_08120CCC, u16 x $50); below AREA_40 it is 233
  t.statueGfx = {}
  for i = 0, 0x4F do t.statueGfx[i] = rom:u16(0x08120CCC + i * 2) end
  if ExtractR12.more then ExtractR12.more(rom, t) end
  manifest.r12 = t
end

return ExtractR12
