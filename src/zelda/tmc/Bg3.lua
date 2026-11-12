-- Round 15: the BG3 backgrounds set up by background managers (the skies
-- and clouds behind the room's two layers).  Without them the parts of
-- BG2 left transparent showed the backdrop (Cloud Tops, the beanstalk
-- tops, the Palace of Winds, Mt. Crenel's peak, Veil Falls' top, ...).
--
-- CARTRIDGE BEHAVIOUR (src/manager/*.c):
-- * ANIMATED_BACKGROUND_MANAGER ($1D, animatedBackgroundManager.c): BG3
--   control $1E07 (characters at $4000, screen map at screenblock 30 =
--   VRAM $F000, priority 3, 256x256).  Type 0 does not scroll; type 1
--   scrolls with the camera plus bg3OffsetX += $2000 per frame (one pixel
--   per 8 frames).
-- * POW_BACKGROUND_MANAGER ($19, powBackgroundManager.c): control
--   BGCNT_PRIORITY(3) | BGCNT_SCREENBASE(30) (characters at 0), x = scroll_x
--   + bg3OffsetX.HI with bg3OffsetX -= $2000 per frame, y = scroll_y.
-- * STATIC_BACKGROUND_MANAGER ($1B, staticBackgroundManager.c):
--   LoadStaticBackground(type) loads gfx group gUnk_08108C5C[type] (a BG3
--   screen map for $F000), control $1E07; scroll gUnk_08108C28[type * 4 +
--   1] picks sub_0805B448 (x = (scroll_x - origin_x) >> 2, y = ((scroll_y -
--   origin_y) >> 1) + max(0, $100 - height) + (s8)tmp[2]) or sub_0805B474.
-- The screen map is whatever VRAM $F000 holds: the room's tileset loads it
-- (tileset def at $600F000, Extract's tshi_*.bin) and a static
-- background's gfx group replaces it.
-- NOT ported: the Minish Paths' parallax BG1 / BG3 (blended, from gfx
-- groups into gMapDataTopSpecial), the rafters, light rays, cloud / steam
-- overlays, the Temple of Droplets' and Vaati's backgrounds.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local B = {}
B.ANIMATED, B.POW, B.STATIC = 0x1D, 0x19, 0x1B
local STATIC_GROUPS = { [0] = 0x14, 0x15, 0x14, 0x2F, 0x4B, 0x4E, 0x4D, 0 }
local STATIC_TAB = { [0] = { 0, 0 }, { 0, 0 }, { 0, -0x28 }, { 0, 0x70 }, { 0, 0 }, { 0, 0 }, { 1, 0 } }

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

-- the 256x256 picture: screen map at VRAM $F000 (32x32 entries), 4bpp
-- characters from charBase, the room's BG palettes
function B.build(room, kind, typ)
  local A = room.assets
  local h = room.maps.header
  local info = A:area(room.area)
  local ts = info and info.tilesets and info.tilesets[h.ts]
  if not ts then return nil end
  local vram = A.store:read(ts.file) or ""
  local hi = ts.hiFile and A.store:read(ts.hiFile) or string.rep("\0", 0x4000)
  local screen = hi:sub(0x3001, 0x3800) -- $F000 - $C000
  if kind == B.STATIC then
    local g = STATIC_GROUPS[typ or 0]
    local list = A.manifest.gfxGroups and A.manifest.gfxGroups[g]
    if list then
      A.gfxBlob = A.gfxBlob or A.store:read("gfxgroups.bin") or ""
      for _, it in ipairs(list) do
        if it[1] == 0x0600F000 then
          local bytes = A.gfxBlob:sub(it[2] + 1, it[2] + it[3])
          screen = bytes .. screen:sub(#bytes + 1)
        end
      end
    end
  end
  local any = false
  for i = 0, 1023 do if u16(screen, i * 2) ~= 0 then any = true break end end
  if not any then return nil end
  local charBase = kind == B.POW and 0 or 0x4000
  local pals = room.atlas and room.atlas.palettes or A:areaPalettes(room.area, h.ts)
  local img, ptr = A.newPixels(256, 256)
  for ty = 0, 31 do
    for tx = 0, 31 do
      local se = u16(screen, (ty * 32 + tx) * 2)
      local tile = band(se, 0x3FF)
      local hf, vf = band(se, 0x400) ~= 0, band(se, 0x800) ~= 0
      local pal = pals[rshift(se, 12)]
      local tb = charBase + tile * 32
      for py = 0, 7 do
        local sy = vf and (7 - py) or py
        for px = 0, 7 do
          local sx = hf and (7 - px) or px
          local byte = vram:byte(tb + sy * 4 + rshift(sx, 1) + 1) or 0
          local ci = (sx % 2 == 0) and band(byte, 15) or rshift(byte, 4)
          local c = ci ~= 0 and pal and pal[ci]
          if c then A.putPixel(img, ptr, 256, tx * 8 + px, ty * 8 + py, c[1], c[2], c[3], 255) end
        end
      end
    end
  end
  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")
  image:setWrap("repeat", "repeat")
  return image
end

-- a background manager in the room's lists: set the room up (Dungeon
-- spawnManager); true when handled
function B.spawn(field, m)
  local r = field.room
  if not r or r.bg3 then return true end
  local ok, img = pcall(B.build, r, m.id, m.type)
  if not ok then field.game:log("bg3: " .. tostring(img)) return true end
  if img then r.bg3 = { img = img, kind = m.id, type = m.type or 0, off = 0 } end
  return true
end

-- a room drawn around the current one (View.lua): its own lists' manager
function B.forRoom(room)
  room.bg3 = false
  for _, l in pairs(room.entities or {}) do
    for _, d in ipairs(l) do
      if d.kind == 9 and (d.id == B.ANIMATED or d.id == B.POW or d.id == B.STATIC) then
        local ok, img = pcall(B.build, room, d.id, d.paramA)
        if ok and img then room.bg3 = { img = img, kind = d.id, type = d.paramA or 0, off = 0 } end
        return room.bg3
      end
    end
  end
  return false
end

-- once per frame (bg3OffsetX's $2000 steps)
function B.update(field)
  local b = field.room and field.room.bg3
  if not b then return end
  if b.kind == B.ANIMATED and b.type == 1 then b.off = b.off + 0x2000
  elseif b.kind == B.POW then b.off = b.off - 0x2000 end
end

-- the BG3 scroll for camera (camX, camY) in room coordinates
function B.offsets(r, b, camX, camY)
  if b.offsetsFn then return b.offsetsFn(r, b, camX, camY) end -- round 26b: Gyorg's drifting sky (BossGyorg.lua)
  local sx, sy = r.x + camX, r.y + camY -- gRoomControls.scroll_x / _y
  local hiOff = math.floor(b.off / 65536)
  if b.kind == B.ANIMATED then
    if b.type == 1 then return sx + hiOff, sy end
    return 0, 0
  elseif b.kind == B.POW then
    return sx + hiOff, sy
  else
    local t = STATIC_TAB[b.type] or STATIC_TAB[0]
    if t[1] == 0 then
      local s8 = t[2]
      return math.floor(camX / 4), math.floor(camY / 2) + math.max(0, 0x100 - r.height) + s8
    end
    local tmp = math.floor(camY * 0x60 / math.max(1, r.height - 160))
    return sx - math.floor((r.width - 0x100) / 2), r.y + tmp
  end
end

-- draw BG3 over the room area the view shows (priority pass 3)
function B.draw(f, r, camX, camY)
  local b = r.bg3
  if not b then return end
  -- the scroll comes from the cartridge camera: the field's own when this
  -- is the current room (zoomed out, camX / camY are the view's corner),
  -- the room's top-left for a room drawn around it
  local cx, cy = camX, camY
  if f and r == f.room and f._realCam then cx, cy = f._realCam[1], f._realCam[2]
  elseif f and r ~= f.room then cx, cy = 0, 0 end
  local xo, yo = B.offsets(r, b, cx, cy)
  -- room pixel (cx + s) shows BG3 pixel (s + xo) mod 256
  local ax, ay = math.floor(cx) - xo, math.floor(cy) - yo
  local g = love.graphics
  -- shown over the room's own area (and the screen around a room smaller
  -- than it): zoomed out, not over the rooms around
  local rx0, ry0 = math.min(0, math.floor((r.width - 240) / 2)), math.min(0, math.floor((r.height - 160) / 2))
  local rx1, ry1 = math.max(r.width, rx0 + 240), math.max(r.height, ry0 + 160)
  local sx0, sy0 = g.transformPoint(rx0 - math.floor(camX), ry0 - math.floor(camY))
  local sx1, sy1 = g.transformPoint(rx1 - math.floor(camX), ry1 - math.floor(camY))
  g.push("all")
  g.intersectScissor(math.floor(sx0), math.floor(sy0), math.max(0, math.ceil(sx1 - sx0)), math.max(0, math.ceil(sy1 - sy0)))
  b.quad = b.quad or g.newQuad(0, 0, 256, 256, 256, 256)
  local x0 = ax + math.floor((-ax) / 256) * 256 - 256
  local y0 = ay + math.floor((-ay) / 256) * 256 - 256
  local w = math.max(r.width, 240) + 512
  local hgt = math.max(r.height, 160) + 512
  b.quad:setViewport(0, 0, w, hgt, 256, 256)
  g.draw(b.img, b.quad, x0 - math.floor(camX), y0 - math.floor(camY))
  g.pop()
end

return B
