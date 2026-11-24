-- Round 33: LIGHT_RAY_MANAGER ($01, src/manager/lightRayManager.c) -- the
-- light rays at the left of Minish Woods (area 0) and the barrel Minish
-- house's light (area $20 room 9).  In R27B.MODULES (spawnManager / frame);
-- drawn from one line in Field:drawWorld (R33.drawWorld).  The zone lists
-- (GetCurrentRoomProperty(type)) and gUnk_085B4180 come from the ROM at
-- import (ExtractR33.lua, r33.bin).
--
-- CARTRIDGE BEHAVIOUR:
--   * Init: BG3 control $1E04 (characters at $4000, map at $F000, priority
--     0), BG3 on, BLDCNT $3648 (BG3 over BG1 / BG2 / OBJ / backdrop),
--     BLDALPHA $1000 (invisible); mode (unk_21) 0, action 1.
--   * Action1: the zone list {mode, x, y, w, h} (tiles from the room's
--     origin); Link in a zone whose mode != the current one: mode 2 / 4 / 6
--     from mode 0 -> fade in (action 2), mode 1 from 2, 5 from 6, 3 from 4 ->
--     fade out (action 3); the new mode is kept, unk_22 = 1 while fading.
--   * Action2 / 3: every 8 frames BLDALPHA = gUnk_08107C1C[timer] (timer up
--     0..9 / down 9..0; after 0 the mode is 0 again).
--   * Each frame gLightRayManagerGfxGroups[mode] is loaded when it changes
--     ($25 for modes 0 / 4, $24 for mode 2) and the mode's function runs:
--       - 2 (sub_080573AC): bg3OffsetX -= $2000, bg3OffsetY -= $1000 a frame;
--         BG3 x / y = ((scroll - origin) >> 1) + the offset; an HBlank DMA
--         writes BG3HOFS per line = gSineTable[(frame + line) & $FF] * amp /
--         256 + x, amp = (gSineTable[(frame & $FF) + $40] >> 5) + 16; not
--         fading: every 32 frames BLDALPHA cycles gUnk_08107C30.
--       - 4 (sub_08057450): BG3 x $10, y = (scroll_y - origin_y) >> 2 (the
--         64-row map of gBG3Buffer, 8 rows a band); the same BLDALPHA cycle;
--         every 8 frames colours $87-$8A / $8C-$8F = gUnk_085B4180[phase *
--         16 + 7 ..] (phase 0-3).
-- SIMPLIFIED: the alpha blend is love's (BG3 at EVA / 16 over the picture);
--   modes 5 / 6 (no room uses them) draw nothing.
local bit = require("bit")
local band, rshift, bor = bit.band, bit.rshift, bit.bor

local M = {}
M.MANAGER = 0x01
local FADE = require("src.zelda.tmc.RomTables").t("R33.FADE") -- gUnk_08107C1C
local CYCLE = require("src.zelda.tmc.RomTables").t("R33.CYCLE")             -- gUnk_08107C30
local GROUPS = require("src.zelda.tmc.RomTables").t("R33.GROUPS")                    -- gLightRayManagerGfxGroups
M.FADE, M.CYCLE, M.GROUPS = FADE, CYCLE, GROUPS

local function sine(i)
  return math.floor(math.sin(band(i, 0xFF) / 256 * 2 * math.pi) * 256 + 0.5)
end
M.sine = sine

-- the zone list of the room (lrm_AA_RR in r33.bin)
function M.zones(A, area, room)
  local e, blob = require("src.zelda.tmc.ExtractR33").table(A, string.format("lrm_%02X_%02X", area, room))
  if not e then return nil end
  local out = {}
  local o = e[2]
  for i = 0, 15 do
    local q = o + 5 * i
    local m = blob:byte(q + 1)
    if not m or m == 0xFF then break end
    out[#out + 1] = { mode = m, x = blob:byte(q + 2), y = blob:byte(q + 3), w = blob:byte(q + 4), h = blob:byte(q + 5) }
  end
  return out
end

-- Dungeon:spawnManager (through R27B)
function M.spawnManager(d, m)
  if m.id ~= M.MANAGER then return nil end
  local f = d.field
  local r = f.room
  if f.lightRay33 and f.lightRay33.room == r then return true end
  f.lightRay33 = { room = r, type = m.type or 0, action = 1, timer = 0, subtimer = 0, gfx = 0, mode = 0, u22 = 0,
                   u23 = 0, u24 = 0, blend = 0x1000, offX = 0, offY = 0,
                   zones = M.zones(f.assets, r.area, r.room) or {} }
  return true
end

-- LightRayManager_Action1
local function action1(f, s)
  local p = f.player
  if not p then return end
  local x, y = math.floor(p.x / 16), math.floor(p.y / 16)
  for _, z in ipairs(s.zones) do
    if z.mode ~= s.mode then
      local dx, dy = x - z.x, y - z.y
      if dy >= 0 and dy < z.h and dx >= 0 and dx < z.w then
        local m = z.mode
        if (m == 1 and s.mode == 2) or (m == 5 and s.mode == 6) or (m == 3 and s.mode == 4) then
          s.action, s.timer = 3, 9
        elseif (m == 2 or m == 6 or m == 4) and s.mode == 0 then
          s.action, s.timer = 2, 0
          if m == 2 then s.gfx = 0 end
        end
        if s.action ~= 1 then
          s.subtimer = 8
          s.mode = m
          s.u22 = 1
          return
        end
      end
    end
  end
end

function M.step(f, s, frame)
  if s.action == 1 then action1(f, s)
  elseif s.action == 2 then
    s.subtimer = s.subtimer - 1
    if s.subtimer == 0 then
      s.subtimer = 8
      s.blend = FADE[s.timer]
      s.timer = s.timer + 1
      if s.timer == 10 then s.action, s.u22 = 1, 0 end
    end
  elseif s.action == 3 then
    s.subtimer = s.subtimer - 1
    if s.subtimer == 0 then
      s.subtimer = 8
      s.blend = FADE[s.timer]
      s.timer = s.timer - 1
      if s.timer < 0 then s.action, s.u22, s.mode = 1, 0, 0 end
    end
  end
  -- gUnk_08107C48[mode]
  if s.mode == 2 then
    s.offX = s.offX - 0x2000
    s.offY = s.offY - 0x1000
    if s.u22 == 0 and band(frame, 0x1F) == 0 then
      s.u24 = band(s.u24 + 1, 7)
      s.blend = CYCLE[s.u24]
    end
  elseif s.mode == 4 then
    if s.u22 == 0 and band(frame, 0x1F) == 0 then
      s.u24 = band(s.u24 + 1, 7)
      s.blend = CYCLE[s.u24]
    end
    if band(frame, 7) == 0 then s.u23 = band(s.u23 + 1, 3) end
  end
  local g = GROUPS[s.mode] or 0
  if g ~= 0 and s.gfx ~= g then s.gfx = g end
end

-- R27B.frame
function M.frame(f)
  local s = f.lightRay33
  if not s then return false end
  if f.room ~= s.room then f.lightRay33 = nil return false end
  M.step(f, s, f.frame or 0)
  return false
end

-- ---------------------------------------------------------------------------
-- the BG3 pictures
-- ---------------------------------------------------------------------------
local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

-- VRAM $0000-$FFFF of the room's tileset with gfx group `g` written over
-- it; the group's EWRAM part (the gBG3Buffer map) returned separately
local function vramWith(r, g)
  local A = r.assets
  local h = r.maps.header
  local info = A:area(r.area)
  local ts = info and info.tilesets and info.tilesets[h.ts]
  if not ts then return nil end
  local lo = A.store:read(ts.file) or ""
  if #lo < 0xC000 then lo = lo .. string.rep("\0", 0xC000 - #lo) else lo = lo:sub(1, 0xC000) end
  local hi = ts.hiFile and A.store:read(ts.hiFile) or string.rep("\0", 0x4000)
  local vram = lo .. hi:sub(1, 0x4000)
  local ewram
  A.gfxBlob = A.gfxBlob or A.store:read("gfxgroups.bin") or ""
  for _, it in ipairs(A.manifest.gfxGroups and A.manifest.gfxGroups[g] or {}) do
    local bytes = A.gfxBlob:sub(it[2] + 1, it[2] + it[3])
    if it[1] >= 0x06000000 and it[1] < 0x06010000 then
      local o = it[1] - 0x06000000
      vram = vram:sub(1, o) .. bytes .. vram:sub(o + #bytes + 1)
    elseif it[1] == 0x02001A40 then
      ewram = bytes
    end
  end
  return vram, ewram
end

local function paint(r, vram, map, rows, pal8)
  local A = r.assets
  local pals = r.atlas and r.atlas.palettes or A:areaPalettes(r.area, r.maps.header.ts)
  local img, ptr = A.newPixels(256, rows * 8)
  for ty = 0, rows - 1 do
    for tx = 0, 31 do
      local se = u16(map, (ty * 32 + tx) * 2)
      local tile = band(se, 0x3FF)
      local hf, vf = band(se, 0x400) ~= 0, band(se, 0x800) ~= 0
      local bank = rshift(se, 12)
      local pal = pals[bank]
      local tb = 0x4000 + tile * 32
      for py = 0, 7 do
        local sy = vf and (7 - py) or py
        for px = 0, 7 do
          local sx = hf and (7 - px) or px
          local byte = vram:byte(tb + sy * 4 + rshift(sx, 1) + 1) or 0
          local ci = (sx % 2 == 0) and band(byte, 15) or rshift(byte, 4)
          if ci ~= 0 then
            local c = (bank == 8 and pal8 and pal8[ci]) or (pal and pal[ci])
            if c then A.putPixel(img, ptr, 256, tx * 8 + px, ty * 8 + py, c[1], c[2], c[3], 255) end
          end
        end
      end
    end
  end
  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")
  image:setWrap("repeat", "repeat")
  return image
end

local function rgb(c)
  local r5, g5, b5 = band(c, 31), band(rshift(c, 5), 31), band(rshift(c, 10), 31)
  return { math.floor(r5 * 255 / 31), math.floor(g5 * 255 / 31), math.floor(b5 * 255 / 31) }
end

-- one picture per mode (mode 4: one per colour phase)
function M.picture(f, s)
  local r = s.room
  r.lightRay33 = r.lightRay33 or {}
  local key = s.mode == 4 and ("4:" .. s.u23) or tostring(s.mode)
  local c = r.lightRay33[key]
  if c ~= nil then return c or nil end
  local ok, img = pcall(function()
    if s.mode == 2 then
      local vram = vramWith(r, 0x24)
      return vram and paint(r, vram, vram:sub(0xF001, 0xF800), 32)
    elseif s.mode == 4 then
      local vram, map = vramWith(r, 0x25)
      if not (vram and map) then return nil end
      -- gUnk_085B4180[phase * 16 + 7 ..]: colours 7-10 and 12-15 of palette 8
      local base = r.atlas and r.atlas.palettes and r.atlas.palettes[8]
      local pal8
      local e, blob = require("src.zelda.tmc.ExtractR33").table(r.assets, "lightRayPal")
      if base and e then
        pal8 = {}
        for i = 0, 15 do pal8[i] = base[i] end
        for i = 0, 3 do
          pal8[7 + i] = rgb(u16(blob, e[2] + 2 * (s.u23 * 16 + 7 + i)))
          pal8[12 + i] = rgb(u16(blob, e[2] + 2 * (s.u23 * 16 + 12 + i)))
        end
      end
      return paint(r, vram, map, 64, pal8)
    end
    return nil
  end)
  r.lightRay33[key] = (ok and img) or false
  if not ok then f.game:log("lightray33: " .. tostring(img)) end
  return r.lightRay33[key] or nil
end

-- Field:drawWorld: BG3 (priority 0) over the picture
function M.drawWorld(f)
  local s = f.lightRay33
  if not s or s.room ~= f.room then return end
  local eva = band(s.blend, 0x1F)
  if eva == 0 or (s.mode ~= 2 and s.mode ~= 4 and s.mode ~= 1 and s.mode ~= 3) then return end
  local shown = s.mode
  if shown == 1 then shown = 2 elseif shown == 3 then shown = 4 end -- (fading out: the last picture, its function no longer runs)
  local st = { room = s.room, mode = shown, u23 = s.u23 }
  local img = M.picture(f, st)
  if not img then return end
  local g = love.graphics
  local camX, camY = math.floor(f.camX or 0), math.floor(f.camY or 0)
  local frame = f.frame or 0
  g.push("all")
  g.setColor(1, 1, 1, math.min(16, eva) / 16)
  s.quad = s.quad or g.newQuad(0, 0, 1, 1, 256, 256)
  if shown == 2 then
    local xo = rshift(camX, 1) + math.floor(s.offX / 65536)
    local yo = rshift(camY, 1) + math.floor(s.offY / 65536)
    s.lineX = s.lineX or {}
    if s.mode == 2 or s.lastFrame == nil then s.lastFrame = frame end
    local fr = s.lastFrame
    local amp = rshift(sine(band(fr, 0xFF) + 0x40), 5) + 0x10
    local vw, vh, vdx = require("src.zelda.tmc.View").screen(f) -- widescreen: the whole field
    for i = 0, vh - 1 do
      local x = math.floor(sine(fr + i) * amp / 256) + xo + vdx
      s.quad:setViewport(x % 256, (i + yo) % 256, vw, 1, 256, 256)
      g.draw(img, s.quad, 0, i)
    end
  else
    local y = rshift(math.max(0, camY), 2)
    local band8 = math.floor(y / 0x40)
    local vw, vh, vdx = require("src.zelda.tmc.View").screen(f) -- widescreen: the whole field
    s.quad:setViewport(0x10 + vdx, band8 * 64 + band(y, 0x3F), vw, vh, 256, 512)
    g.draw(img, s.quad, 0, 0)
  end
  g.pop()
end

return M
