-- Round 34: worldEvent5.c's BG3 cloud overlay in the world-event view
-- (Fusion32.lua calls start / frame / draw) -- the clouds over Hyrule Field
-- and the castle garden that a type 5 fusion clears.
--
-- CARTRIDGE BEHAVIOUR (src/worldEvent/worldEvent5.c):
--   * WorldEvent_5_0: ptr = gUnk_080FF1D4[(entity_idx & $F) * 3] {gfx group,
--     BG3 x, BG3 y}: LoadGfxGroup (the BG3 map at $F000; the tiles are the
--     room's at $4000), BG3 offsets = ptr[1] / ptr[2], control $1E05 (char
--     base 1, screen base 30, priority 1), BLDCNT $3648, BLDALPHA $10 (the
--     clouds alone), BG3 on; sub_0801876C(id, 1) (the room as fused, under
--     the clouds); sub_08055B70: the KINSTONE_SPARK; fade in; storyPanel 0,
--     timer 60, step 0.
--   * _1: the fade done and room flag $FF (the spark's script sets it).
--   * _2: 60 frames -> SFX_EVAPORATE; then every 8 frames BLDALPHA =
--     gUnk_080FF204[step++] ($10, $10F .. $F01, $1000) until $FFFF: BG3 off,
--     BLDALPHA $1000, timer 120, SFX_SECRET_BIG (not EU).
--   * _3: 120 frames, then the subtask's end.
-- SIMPLIFIED: the KINSTONE_SPARK and its script are not run; room flag $FF
--   is taken as set after SPARK_FRAMES frames.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}
local SFX_EVAPORATE, SFX_SECRET_BIG = 0xF6, 0x73
M.SPARK_FRAMES = 60

local function tables(f)
  local P = require("src.zelda.tmc.Ppu")
  local self = { A = f.assets }
  return P.table(self, "we5Bg3"), P.table(self, "we5Alpha")
end

-- the BLDALPHA list (to $FFFF)
function M.alphaList(t)
  local out = {}
  if not t then return out end
  for i = 0, 31 do
    local v = t.u16(t.base + 2 * i)
    out[#out + 1] = v
    if v == 0xFFFF then break end
  end
  return out
end

function M.start(c, f)
  local bg, al = tables(f)
  if not bg then return false end
  local idx = band(c.we.entity or 0, 0xF)
  local a = bg.base + idx * 6
  local group, xo, yo = bg.s16(a), bg.s16(a + 2), bg.s16(a + 4)
  local ok, img = pcall(require("src.zelda.tmc.Bg3").build, c.room, 0x18, 0, group)
  c.we5 = { img = ok and img or nil, group = group, xo = xo, yo = yo, blend = 0x10, step = 1,
            alpha = M.alphaList(al), phase = 0, timer = 60, wait = M.SPARK_FRAMES }
  return true
end

-- one frame; true while the overlay holds the event
function M.frame(c, f)
  local w = c.we5
  if not w or w.phase == 3 then return false end
  if w.phase == 0 then
    if c.black > 0 then return true end -- the fade in
    w.wait = w.wait - 1
    if w.wait <= 0 then w.phase = 1 end
  elseif w.phase == 1 then
    if w.timer > 0 then
      w.timer = w.timer - 1
      if w.timer == 0 then f:sound(SFX_EVAPORATE) end
    elseif band(c.t, 7) == 0 then
      local v = w.alpha[w.step]
      if v and v ~= 0xFFFF then
        w.blend = v
        w.step = w.step + 1
      else
        w.blend, w.off = 0x1000, true
        w.phase = 2
        w.timer = 120
        f:sound(SFX_SECRET_BIG)
      end
    end
  elseif w.phase == 2 then
    w.timer = w.timer - 1
    if w.timer <= 0 then w.phase = 3 return false end
  end
  return true
end

-- after the room's top layer (BG3 priority 1 over BG1 / BG2 / the sprites)
function M.draw(c, f)
  local w = c.we5
  if not w or w.off or not w.img then return end
  local eva = math.min(16, band(w.blend, 0x1F))
  local evb = math.min(16, band(rshift(w.blend, 8), 0x1F))
  local g = love.graphics
  w.quad = w.quad or g.newQuad(0, 0, 240, 160, 256, 256)
  w.quad:setViewport(w.xo % 256, w.yo % 256, 240, 160, 256, 256)
  g.push("all")
  if evb < 16 then g.setColor(0, 0, 0, (16 - evb) / 16); g.draw(w.img, w.quad, 0, 0) end
  if eva > 0 then
    g.setBlendMode("add")
    g.setColor(eva / 16, eva / 16, eva / 16, 1)
    g.draw(w.img, w.quad, 0, 0)
  end
  g.pop()
end

return M
