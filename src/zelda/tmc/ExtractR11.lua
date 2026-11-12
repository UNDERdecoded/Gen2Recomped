-- Round 11: small tables read from the player's ROM at import time
-- (manifest.r11).  Nothing here is shipped: each entry names the ROM
-- address it is read from (USA, BZME).
local ExtractR11 = {}

local function s8(v) return v >= 128 and v - 256 or v end

-- Hitbox {s8 offset_x, s8 offset_y, u8 unk2[4], u8 width, u8 height}
local function hitbox(rom, a)
  if not a or a == 0 or not rom:valid(a + 7) then return nil end
  return { x = s8(rom:u8(a)), y = s8(rom:u8(a + 1)), u = { rom:u8(a + 2), rom:u8(a + 3), rom:u8(a + 4), rom:u8(a + 5) },
           w = rom:u8(a + 6), h = rom:u8(a + 7) }
end

local function boxTable(rom, at, n)
  local t = {}
  for i = 0, n - 1 do t[i] = hitbox(rom, rom:u32(at + i * 4)) or false end
  return t
end

function ExtractR11.run(rom, manifest)
  local t = {}
  -- playerHitbox.c gPlayerHitbox ($08114F88) and player.c sub_08073C80's
  -- sMinishHitbox ($0811BC80)
  t.playerHitbox = hitbox(rom, 0x08114F88)
  t.minishHitbox = hitbox(rom, 0x0811BC80)
  -- npcUtils.c NPCInit gNPCHitboxes ($08114EE4, 6 entries) and
  -- objectDefinitions.c gObjectHitboxes ($08125104, 5 entries)
  t.npcHitboxes = boxTable(rom, 0x08114EE4, 6)
  t.objectHitboxes = boxTable(rom, 0x08125104, 5)
  -- playerUtils.c gPlayerInteractHitboxOffsetNormal / Minish: s8 x, y per
  -- facing (north, east, south, west), at $0811C00C / $0811C014
  local function pairs4(a)
    local o = {}
    for i = 0, 3 do o[i] = { s8(rom:u8(a + i * 2)), s8(rom:u8(a + i * 2 + 1)) } end
    return o
  end
  t.interactNormal = pairs4(0x0811C00C)
  t.interactMinish = pairs4(0x0811C014)
  -- forestMinish.c gUnk_08109C98: FrameStruct {u8 frame, u8 frameIndex},
  -- 16 per own facing (animationState / 2), by look direction (0..31) >> 1
  t.minishLook = {}
  for i = 0, 63 do t.minishLook[i] = { rom:u8(0x08109C98 + i * 2), rom:u8(0x08109C98 + i * 2 + 1) } end
  -- pullableLever.c: PullableLever_InitialOffsets ($081222A8), Link's
  -- place gUnk_081222B8, the pull directions gUnk_081222C0
  local function s8pairs(a)
    local o = {}
    for i = 0, 3 do o[i] = { s8(rom:u8(a + i * 2)), s8(rom:u8(a + i * 2 + 1)) } end
    return o
  end
  t.lever = { initOffsets = s8pairs(0x081222A8), linkOffsets = s8pairs(0x081222B8), pullDirs = {} }
  for i = 0, 3 do t.lever.pullDirs[i] = rom:u8(0x081222C0 + i) end
  -- asm/src/script.s gTransitionTiles ($08016AB4): {act tile, a, b}
  t.layerTiles = {}
  for i = 0, 15 do
    local a = 0x08016AB4 + i * 4
    local act = rom:u16(a)
    if act == 0 then break end
    t.layerTiles[#t.layerTiles + 1] = { act, rom:u8(a + 2), rom:u8(a + 3) }
  end
  -- pushableStatue.c PushableStatue_Init: hitbox gUnk_080FD1F4
  t.statueHitbox = hitbox(rom, 0x080FD1F4)
  if ExtractR11.more then ExtractR11.more(rom, t) end
  manifest.r11 = t
end

return ExtractR11
