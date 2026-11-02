-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S DEPTH-FOG WEATHERS, 26..30: the 3D engine's own fog.
--
-- Stark Mountain's caves are weather 28 (D16R0101..R0103), and this port drew
-- nothing for it ("WEATHER_28 has no look").  The cartridge's task for it,
-- ov5_021DB438 (pokeplatinum src/overlay005/ov5_021D5EB8.c), and its four
-- siblings are one call each to ov5_021D9DFC with a slope, an offset and a
-- colour, which turns on the DS's hardware fog:
--
--     26  ov5_021DB3E0   slope 3  offset 26095  GX_RGB(2, 2, 6)
--     27  ov5_021DB40C   slope 2  offset 26415  GX_RGB(13, 25, 30)
--     28  ov5_021DB438   slope 2  offset 26415  GX_RGB(20, 0, 0)   (Stark)
--     29  ov5_021DB460   slope 2  offset 26415  GX_RGB(0, 0, 20)
--     30  ov5_021DB48C   slope 1  offset 19311  GX_RGB(1, 1, 1)
--
-- ov5_021D7384: FogManager_ApplyParameters(enabled, COLOR_ALPHA, slope,
-- offset) and the colour at alpha 31.  On a map loaded with the weather the
-- density table is set at once (ov5_021D74D4 -> ov5_021D7534 with step 1):
-- entry i is 4 * i, so the fog thickens linearly over the 32 entries to
-- 124 / 127.  The hardware reads the entry for a pixel from its depth (the
-- 15-bit z-buffer value) as (depth - offset) >> (10 - slope)... that is, each
-- entry covers 0x400 >> slope depth units, and blends colour and fog by it.
--
-- Here: the pass tells Gen4Model how to turn a fragment's depth back into a
-- distance from the eye, and the shader puts that distance through the
-- cartridge camera's own near / far to get the depth the DS would have
-- fogged by.

local F = {}

F.WEATHERS = {
  [26] = { slope = 3, offset = 26095, rgb = { 2, 2, 6 } },
  [27] = { slope = 2, offset = 26415, rgb = { 13, 25, 30 } },
  [28] = { slope = 2, offset = 26415, rgb = { 20, 0, 0 } },
  [29] = { slope = 2, offset = 26415, rgb = { 0, 0, 20 } },
  [30] = { slope = 1, offset = 19311, rgb = { 1, 1, 1 } },
  -- ...and the particle weathers' own fog (ov5_021D7308 in their init):
  -- snow 0x6F6F + 0x300, heavy snow - 0x200, blizzard - 0x400, the unnamed
  -- heavy snow 21 at 0x6F6F itself, and SLOW_ASHFALL's yellowish haze
  [5]  = { slope = 3, offset = 0x726F, rgb = { 26, 26, 26 } },
  [6]  = { slope = 3, offset = 0x6D6F, rgb = { 24, 24, 24 } },
  [7]  = { slope = 3, offset = 0x6B6F, rgb = { 24, 24, 24 } },
  [21] = { slope = 3, offset = 0x6F6F, rgb = { 24, 24, 24 } },
  [9]  = { slope = 3, offset = 0x6F6F - 0x40, rgb = { 20, 20, 14 } },
}

local function game() return package.loaded["src.core.Game"] end

local function platinum()
  local G = game()
  local data = G and G.data
  local v = data and data.gen4_version
  local ok, GV = pcall(require, "src.core.GameVersion")
  return data and data.isGen4Cache and not (ok and GV.isGen5()) and not (v and v.family == "hgss")
end

-- the fog row the live weather calls for, or nil
function F.current()
  local force = os.getenv and tonumber(os.getenv("G4FOG") or "")
  if force then return F.WEATHERS[force] end
  -- BLACK / WHITE: the weather programs' own fog (src/world/Gen5WeatherFx.lua)
  do
    local okV, GV = pcall(require, "src.core.GameVersion")
    if okV and GV.isGen5() then
      local WX = package.loaded["src.world.Gen5WeatherFx"]
      return WX and WX.depthRow and WX.depthRow() or nil
    end
  end
  if not platinum() then return nil end
  -- A GYM'S OWN FOG (`def.gen4DepthFog`, set by its DynamicMapFeaturesInit:
  -- Hearthome's black room, Canalave's depth fog -- src/world/Gen4GymFx.lua)
  do
    local G = game()
    local ow = G and G.overworld
    local def = ow and ow.map and ow.map.def
    if def and type(def.gen4DepthFog) == "table" then return def.gen4DepthFog end
  end
  -- FOG (14), steady or thinning after Defog (src/world/Gen4FogWeather.lua)
  local FW = package.loaded["src.world.Gen4FogWeather"]
  local fogRow = FW and FW.depthRow and FW.depthRow()
  if fogRow then return fogRow end
  local G = game()
  local raw = G and G.save and tonumber(G.save.gen4WeatherActive)
  return raw and F.WEATHERS[raw] or nil
end

-- begin(ground, mode, a, b): fog the draws that follow.  `mode` says how the
-- pass's depth turns back into eye distance:
--   1  linear:       D = a + ndcZ * b          (the live field pass)
--   2  perspective:  near a, far b             (the free camera)
--   3  orthographic: near a, far b
function F.begin(ground, mode, a, b)
  local Gen4Model = require("src.render.Gen4Model")
  local row = F.current()
  local cam = ground and ground.camera
  if not (row and cam) then Gen4Model.depthFog = nil; return end
  -- (a gym's row may carry the clipping its init sets, Camera_SetClipping)
  local near, far = tonumber(row.near or cam.near) or 150, tonumber(row.far or cam.far) or 900
  Gen4Model.depthFog = {
    a = { mode, a, b, cam.projection == "orthographic" and 1 or 0 },
    b = { near, far, row.offset, 1024 / 2 ^ row.slope },
    c = { row.rgb[1] / 31, row.rgb[2] / 31, row.rgb[3] / 31 },
    shift = row.shift,
    -- the density table's step per entry (4 for the weathers' 4 * i; a gym's
    -- own table: Canalave's 2 * i, Hearthome's flat one)
    step = row.step,
  }
end

-- density(row, ground, eye) -> 0..1: the fog a point `eye` units from the
-- camera gets under `row`, by the same arithmetic as the model shader (the
-- depth the DS would have stored for it through the camera's near / far, the
-- table entry it falls in). For the characters, which are not drawn by the
-- model shader (src/world/Gen4GymFx.lua spriteFog).
function F.density(row, ground, eye)
  if not row then return 0 end
  local step = tonumber(row.step) or 4
  if row.flat then return math.min(1, row.flat / 127) end
  local cam = ground and ground.camera or {}
  local n, f = tonumber(row.near or cam.near) or 150, tonumber(row.far or cam.far) or 900
  local d = tonumber(eye) or tonumber(cam.distance) or 667
  local dz
  if cam.projection == "orthographic" then
    dz = (d - n) / (f - n) * 2 - 1
  else
    dz = (f + n) / (f - n) - 2 * f * n / ((f - n) * math.max(d, 1))
  end
  local depth = (dz * 0.5 + 0.5) * 32767
  local e = (depth - row.offset) / (1024 / 2 ^ row.slope)
  if e < 0 then e = 0 elseif e > 31 then e = 31 end
  return math.min(1, e * step / 127)
end

-- spriteAt(zn) -> r, g, b, density, or nil: the fog the model shader would
-- give a fragment at NDC depth `zn` under the pass's own fog (the
-- Gen4Model.depthFog a `begin` set), the same arithmetic line for line. For a
-- character billboard of the FREE pass (Gen4Ground:freeEntity), where the
-- picture is drawn through the sprite shaders and not the model one -- on the
-- DS a field object is a polygon the hardware fog covers like the map.
function F.spriteAt(zn)
  local Gen4Model = package.loaded["src.render.Gen4Model"]
  local fog = Gen4Model and Gen4Model.depthFog
  zn = tonumber(zn)
  if not (fog and zn) then return nil end
  local mode, a, b, ortho = fog.a[1], fog.a[2], fog.a[3], fog.a[4]
  local d
  if mode < 1.5 then
    d = a + zn * b
  elseif mode < 2.5 then
    d = 2 * a * b / (b + a - zn * (b - a))
  else
    d = a + (zn * 0.5 + 0.5) * (b - a)
  end
  local rn, rf = fog.b[1], fog.b[2]
  local dz
  if ortho > 0.5 then
    dz = (d - rn) / (rf - rn) * 2 - 1
  else
    dz = (rf + rn) / (rf - rn) - 2 * rf * rn / ((rf - rn) * math.max(d, 1))
  end
  local depth = (dz * 0.5 + 0.5) * 32767
  local e = (depth - fog.b[3]) / fog.b[4]
  if e ~= e then e = 0 end
  if e < 0 then e = 0 elseif e > 31 then e = 31 end
  local k = (fog.step and fog.step > 0) and fog.step or 4
  local shift = fog.shift or 0
  local dens
  if e > shift then dens = (e - shift) * k / 127
  elseif shift > 0 and e >= 1 then dens = k / 127
  else dens = e * k / 127 end
  if dens <= 0 then return nil end
  return fog.c[1], fog.c[2], fog.c[3], math.min(1, dens)
end

function F.finish()
  local Gen4Model = package.loaded["src.render.Gen4Model"]

  if Gen4Model then Gen4Model.depthFog = nil end
end

return F
