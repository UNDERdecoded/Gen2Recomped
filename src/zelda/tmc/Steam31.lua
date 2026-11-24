-- Round 31: the Cave of Flames' steam overlay (STEAM_OVERLAY_MANAGER $14,
-- src/manager/steamOverlayManager.c).  R31.spawnManager / R31.frame /
-- R31.drawWorld call here.
--
-- CARTRIDGE BEHAVIOUR:
--   * Init: one per room set (EntityHasDuplicateID), ENT_PERSIST; BG3
--     control $1E04 (characters at $4000, screen map at VRAM $F000,
--     priority 0: over everything), BG3 on, BLDCNT $3E48 (BG3 the first
--     target, alpha, BG1-OBJ + backdrop the second), BLDALPHA $1000 (EVA
--     0: invisible), action 4.
--   * Action4, every 4th frame: in rooms 0 / 8 / 9 / $17 the blend steps up
--     gUnk_08108588 ($1000, $F01 .. $808, EVA + EVB = 16) and, at $808,
--     unk_22 = 0 (the shimmer); other rooms step it back down to $1000;
--     room 1 with local flag $16 clear stays, set or room 7 -> deleted
--     (blend off).
--   * sub_0805A1D8 every frame: bg3OffsetX / Y -= $1000 (one pixel every
--     16 frames, the steam drifts up-left); with BG3 on, sub_0805A114(6,
--     unk_20 >> 1): an HBlank DMA writes BG3HOFS per scanline = xOffset +
--     (gSineTable[(phase + t) & $FF] * 6 >> 8) with t = line + yOffset
--     rounded to 8 (16 on its 2nd and 8th 8-line band, -8 on the 5th);
--     shimmer (unk_22 0): every 32 ticks BLDALPHA cycles gUnk_0810859A
--     ($808, $907, $A06, $907).
-- SIMPLIFIED: the alpha blend is love's (overlay at EVA / 16 over the
--   picture), drawn over the world but under the HUD (BG3 priority 0 is
--   under the HUD's BG0 / window on the cartridge as well).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local S = {}
S.MANAGER = 0x14
S.AREA_COF = 0x50
local FADE = require("src.zelda.tmc.RomTables").t("Steam31.FADE") -- gUnk_08108588
local SHIMMER = require("src.zelda.tmc.RomTables").t("Steam31.SHIMMER")                                  -- gUnk_0810859A
S.FADE, S.SHIMMER = FADE, SHIMMER

local function steamRoom(room)
  return room == 0 or room == 8 or room == 9 or room == 0x17
end

-- Dungeon:spawnManager (through R26 / R27B / R31)
function S.spawn(f, m)
  if f.steam31 and not f.steam31.deleted then return true end -- EntityHasDuplicateID
  f.steam31 = { action = 4, timer = 0, subtimer = 4, u20 = 0, u22 = 1, u24 = 0, blend = 0x1000,
                offX = 0, offY = 0, area = f.room and f.room.area }
  return true
end

local function off(f) f.steam31 = nil end

local function action4(f, s)
  s.subtimer = s.subtimer - 1
  if s.subtimer ~= 0 then return end
  s.subtimer = 4
  local room = f.room.room
  local on
  if room == 1 then
    if f:dungeon():check(0x16) then on = false else off(f) return end
  elseif room == 7 then off(f) return
  else on = steamRoom(room) end
  if on then
    if FADE[s.timer] ~= 0x808 then
      s.u22, s.u24 = 1, 0
      s.timer = s.timer + 1
      s.blend = FADE[s.timer]
    else
      s.u22 = 0
    end
  else
    s.u22 = 1
    if FADE[s.timer] ~= 0x1000 then s.timer = s.timer - 1; s.blend = FADE[s.timer] end
  end
end

-- R31.frame (Field:update)
function S.frame(f)
  local s = f.steam31
  if not s then return end
  if not f.room or f.room.area ~= s.area then off(f) return end -- left the dungeon (ENT_PERSIST is per area)
  s.u20 = (s.u20 + 1) % 0x10000
  if s.action == 4 then action4(f, s) end
  if not f.steam31 then return end
  -- sub_0805A1D8
  s.offX = s.offX - 0x1000
  s.offY = s.offY - 0x1000
  if s.u22 == 0 and band(f.frame or 0, 0x1F) == 0 then
    s.u24 = band(s.u24 + 1, 3)
    s.blend = SHIMMER[s.u24]
  end
end

-- the scanline's BG3 x offset (sub_0805A114)
function S.lineX(s, i, sine)
  local xo, yo = math.floor(s.offX / 65536), math.floor(s.offY / 65536)
  local t = i + yo
  local band8 = band(rshift(t, 3), 7)
  if band8 == 4 then t = band(t - 8, 0xF8)
  elseif band8 == 1 or band8 == 7 then t = band(t, 0xF0)
  else t = band(t, 0xF8) end
  local ph = band(rshift(s.u20, 1) + t, 0xFF)
  local sv = sine and sine(ph) or math.floor(math.sin(ph / 256 * 2 * math.pi) * 256)
  return xo + math.floor(sv * 6 / 256) -- (gSineTable * 6) >> 8, arithmetic
end

local function image(f)
  local r = f.room
  if r.steam31Img == nil then
    local ok, img = pcall(require("src.zelda.tmc.Bg3").build, r, 0x14, 0)
    r.steam31Img = ok and img or false
  end
  return r.steam31Img or nil
end

-- R31.drawWorld (after the world's priority passes): BG3 over the picture
function S.draw(f)
  local s = f.steam31
  if not s or not f.room then return end
  local eva = band(s.blend, 0x1F)
  if eva == 0 then return end
  local img = image(f)
  if not img then return end
  local g = love.graphics
  local yo = math.floor(s.offY / 65536)
  s.quad = s.quad or g.newQuad(0, 0, 1, 1, 256, 256)
  g.push("all")
  g.setColor(1, 1, 1, math.min(16, eva) / 16)
  -- the 240 x 160 screen (the cartridge's view): rows 0..159 from the camera
  for i = 0, 159 do
    s.quad:setViewport(S.lineX(s, i), (i + yo) % 256, 240, 1, 256, 256)
    g.draw(img, s.quad, 0, i)
  end
  g.pop()
end

return S
