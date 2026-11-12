-- Round 10: rooms whose bottom layer is a "special" map (map_bottom_special:
-- the Minish house interiors, ...).  Their metatile map is all $FFFF and
-- the picture is an 8x8 BG screen (0x1000 bytes of screen entries, copied
-- to gMapDataBottomSpecial, $02019EE0) drawn with the room tileset's
-- bottom charblock and the tileset's palettes.  Collision comes from the
-- room's own collision map (Assets:roomMaps collisionOverride).
-- The screen is two 32x32 blocks (see S.build).  The Minish
-- house interiors are 256-colour BGs (8bpp tiles, 64 bytes each, the pixel
-- byte indexes the 256-colour BG palette); a screen whose entries never use
-- the palette bits is taken as 8bpp, else 4bpp.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local S = {}

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

-- round 15: the screen entry index of 8x8 cell (tx, ty): sub_0807C5F4
-- copies the blocks in the order (0,0), (1,0) if wide, (0,1) if tall,
-- (1,1) if both
function S.index(tx, ty, wide)
  local bx, by = tx >= 32 and 1 or 0, ty >= 32 and 1 or 0
  local blk = (bx == 1 and by == 1) and 3 or (by == 1 and (wide and 2 or 1)) or bx
  return blk * 1024 + (ty % 32) * 32 + tx % 32
end

function S.build(room)
  local A = room.assets
  local h = room.maps.header
  local sec = h.sections and h.sections.special1
  if not sec then return nil end
  local info = A:area(room.area)
  local ts = info and info.tilesets and info.tilesets[h.ts]
  if not ts then return nil end
  local blob = A.store:read(h.file) or ""
  local vram = A.store:read(ts.file) or ""
  local pals = A:areaPalettes(room.area, h.ts)
  if not pals then return nil end
  -- round 15: sub_0807C5F4's layout: 32x32 blocks in the order (0,0),
  -- (1,0) if width > $FF, (0,1) if height > $FF, (1,1) if both (the old
  -- code knew one extra block only, so rooms both wide and tall -- $2D:10,
  -- $2D:12 -- lost their lower half)
  local wide, tall = room.width > 0xFF, room.height > 0xFF
  local rows = math.min(tall and 64 or 32, math.ceil(room.height / 8))
  local W = wide and 64 or 32
  -- round 15: LoadRoomGfx sets the 256-colour bit (BG2 control | $80) for
  -- AREA_MINISH_HOUSE_INTERIORS ($20) and AREA_TOWN_MINISH_HOLES ($2D)
  -- only; every other special room (the beanstalk screens, area $0D) is
  -- 4bpp.  (The old guess -- 8bpp when no entry used palette bits --
  -- decoded the beanstalk screens as 8bpp.)
  local bpp8 = room.area == 0x20 or room.area == 0x2D
  -- round 15: the map def's destination says which layer: $02019EE0
  -- (gMapDataBottomSpecial) is BG2 (characters at 0), $02002F00
  -- (gMapDataTopSpecial: the beanstalk screens, area $0D) BG1 (characters
  -- at $4000); Room:drawLayer draws the picture on that layer
  local topLayer = h.sections.special1Dest == 0x02002F00
  room.specialTop = topLayer or nil
  local charBase = topLayer and 0x4000 or 0
  local img, ptr = A.newPixels(W * 8, rows * 8)
  for ty = 0, rows - 1 do
    for tx = 0, W - 1 do
      local idx = S.index(tx, ty, wide)
      local o = sec[1] + idx * 2
      if o + 2 <= sec[1] + sec[2] then
        local se = u16(blob, o)
        local tile = band(se, 0x3FF)
        local hf, vf = band(se, 0x400) ~= 0, band(se, 0x800) ~= 0
        local pal = pals[rshift(se, 12)]
        local tb = charBase + tile * (bpp8 and 64 or 32)
        for py = 0, 7 do
          local sy = vf and (7 - py) or py
          for px = 0, 7 do
            local sx = hf and (7 - px) or px
            local c
            if bpp8 then
              local ci = vram:byte(tb + sy * 8 + sx + 1) or 0
              c = ci ~= 0 and pals[rshift(ci, 4)] and pals[rshift(ci, 4)][band(ci, 15)]
            else
              local byte = vram:byte(tb + sy * 4 + rshift(sx, 1) + 1) or 0
              local ci = (sx % 2 == 0) and band(byte, 15) or rshift(byte, 4)
              c = ci ~= 0 and pal and pal[ci]
            end
            if c then
              A.putPixel(img, ptr, W * 8, tx * 8 + px, ty * 8 + py, c[1], c[2], c[3], 255)
            end
          end
        end
      end
    end
  end
  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")
  return image
end

return S
