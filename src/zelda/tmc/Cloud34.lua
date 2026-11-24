-- Round 34: CLOUD_OVERLAY_MANAGER ($18, src/manager/cloudOverlayManager.c)
-- -- the cloud shadows drifting over Hyrule Field (area 3, every room).  In
-- R34.MODULES (spawnManager / frame / drawWorld).
--
-- CARTRIDGE BEHAVIOUR:
--   * Main, action 0: ENT_PERSIST, timer 0, subtimer 8, field_0x20 =
--     gUnk_0810865C[0] ($F01); RegisterTransitionHandler (OnEnterRoom) unless
--     one is registered already (then the new manager deletes itself: the
--     one from the first field room lives on across the area's rooms).
--   * Each frame: while gUnk_0810865C[timer] != 0, every 4 frames (8 the
--     first time) the next value -> BLDALPHA ($F01, $E02, $E03, $E04, then
--     it stays); bg3OffsetX -= $2000, bg3OffsetY -= $1000; BG3 x = scroll_x
--     + bg3OffsetX.HI, y = scroll_y + bg3OffsetY.HI.
--   * OnEnterRoom: BG3 control screen base 30 ($F000), char base 1 ($4000),
--     priority 1; BLDCNT BG3 over BG1 / BG2 / OBJ / backdrop (blend).
-- The blend is done as the GBA's (BG3 * EVA + below * EVB) / 16 (two passes).
local bit = require("bit")
local band = bit.band

local M = {}
M.MANAGER = 0x18
M.STEPS = require("src.zelda.tmc.RomTables").t("Cloud34.STEPS") -- gUnk_0810865C

function M.spawnManager(d, m)
  if m.id ~= M.MANAGER then return nil end
  local f = d.field
  local c = f.cloud34
  if c and c.area == f.room.area then c.room = f.room return true end -- the persistent one
  f.cloud34 = { area = f.room.area, room = f.room, timer = 0, subtimer = 8, blend = M.STEPS[0], offX = 0, offY = 0 }
  return true
end

-- CloudOverlayManager_Main's frame
function M.step(c)
  if M.STEPS[c.timer] ~= 0 then
    c.subtimer = c.subtimer - 1
    if c.subtimer == 0 then
      c.subtimer = 4
      c.timer = c.timer + 1
      if M.STEPS[c.timer] ~= 0 then c.blend = M.STEPS[c.timer] end
    end
  end
  c.offX = c.offX - 0x2000
  c.offY = c.offY - 0x1000
end

function M.frame(f)
  local c = f.cloud34
  if not c then return false end
  if not f.room or f.room.area ~= c.area then f.cloud34 = nil return false end
  if f.transition then return false end
  M.step(c)
  return false
end

local function image(f)
  local r = f.room
  if r.cloud34Img == nil then
    local ok, img = pcall(require("src.zelda.tmc.Bg3").build, r, M.MANAGER, 0)
    r.cloud34Img = ok and img or false
  end
  return r.cloud34Img or nil
end

-- the BG3 scroll for the field's camera
function M.offsets(f, c)
  local r = f.room
  local cx, cy = f.camX or 0, f.camY or 0
  if f._realCam then cx, cy = f._realCam[1], f._realCam[2] end
  local hx, hy = math.floor(c.offX / 65536), math.floor(c.offY / 65536)
  return (r.x or 0) + math.floor(cx) + hx, (r.y or 0) + math.floor(cy) + hy
end

function M.drawWorld(f)
  local c = f.cloud34
  if not c or not f.room or f.room.area ~= c.area then return end
  local eva = band(c.blend, 0x1F)
  if eva == 0 then return end
  local img = image(f)
  if not img then return end
  local g = love.graphics
  local xo, yo = M.offsets(f, c)
  c.quad = c.quad or g.newQuad(0, 0, 1, 1, 256, 256)
  local vw, vh, vdx, vdy = require("src.zelda.tmc.View").screen(f) -- widescreen: the whole field
  c.quad:setViewport((xo + vdx) % 256, (yo + vdy) % 256, vw, vh, 256, 256)
  -- BLDALPHA: picture = BG3 * EVA / 16 + below * EVB / 16 where BG3 has a
  -- pixel: darken below to EVB / 16 (black at alpha (16 - EVB) / 16), then
  -- add BG3 * EVA / 16 (the 240 x 160 screen: Field:drawWorld is in screen
  -- space)
  local evb = math.min(16, band(bit.rshift(c.blend, 8), 0x1F))
  g.push("all")
  if evb < 16 then
    g.setColor(0, 0, 0, (16 - evb) / 16)
    g.draw(img, c.quad, 0, 0)
  end
  g.setBlendMode("add")
  local k = math.min(16, eva) / 16
  g.setColor(k, k, k, 1)
  g.draw(img, c.quad, 0, 0)
  g.pop()
end

return M
