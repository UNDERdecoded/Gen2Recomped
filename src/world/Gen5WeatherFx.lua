-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S FIELD WEATHER PROGRAMS (overlays 24..28), in place of the
-- borrowed Gen 3 looks. The sprites are src/import/Gen5WeatherArt.lua's.
--
-- READ FROM CODE (Black, ov21's weather framework):
--   * 32 particles of 0x38 bytes (0x021A274C), each a cell actor on the
--     256 x 192 screen moved by its program's per-particle update (record
--     +0x48, called once a field frame by 0x021A27F8); the cell is the frame
--     the program sets (0x0204B908), not animated
--   * the SPAWN TIMER (0x021A2A84 / 0x021A2AB8): { count, interval, count
--     target, interval target, interval step, spawns per count step, count
--     step }; each frame its countdown drops, at 0 the spawner runs `count`
--     times and the countdown restarts at `interval`, which then steps
--     towards its target (and the count towards its own every `per` spawns)
--   * the WRAPPING position (0x021A2654): x past 320 -> x mod 320, under -64
--     -> + 320; y past 256 -> mod 256, under -66 -> + 256
--   * the CAMERA SHIFT (0x021A244C -> 0x021A2564): every particle moves
--     against the camera target's movement since the last frame, converted
--     to screen pixels by the camera's projection; a jump of more than 1000
--     units in x or 100 in z (a warp) is not followed
--   * RAIN (2, ov26 0x021EE740..): timer {1, 8, 2, 0, -4, 2, 1}; a drop
--     (0x021EEA18) is one of three streaks k = r mod 3 (cells 0..2), vy =
--     2 (r mod 20 + 16 (k + 1) [+16 for k 2]), vx = 2 ((r mod 20) / 8 +
--     8 (k + 1) [+8]), at x = (r & 0xFF) + 15k - 72, y = -96, living 1 or 2
--     frames ((r & 1) + 1 against +2 a frame); then 30% (rand 10 >= 7)
--     splash (cell 3) for 4 frames (0x021EE97C); SE 0x691
--   * THUNDERSTORM (6, 0x021EEAEC): timer {1, 15, 2, 0, -3, 1, 1}; a sheet
--     k = r mod 3 (cells 0..2, 96 x 96) falls at vx = vy = (r & 15) + 14 (k +
--     1) (x the gust's tenths, 0x021EFD08 -- 10 here, INFERRED: the gust
--     index is not followed), from x = r mod 384 - 128, y = r mod 40 - 80,
--     until y >= 192 (0x021EEDD8); the rain sheet 0x29 scrolls 9 a frame
--     right and down (0x021EEF0C); SE 0x690. LIGHTNING (0x021EF9B0, mode 2):
--     after rand 3 frames a pattern by rand 100 against {30, 75, 100}
--     (0x021EFCF9): 75% one strike (0x021EFBFC: level rand 3 + 24, then
--     rand 300 + 240 frames, thunder SE 0x692 13 frames after), 25% a run of
--     rand 2 + 1 small flashes (level rand 3 + 18, rand 4 apart, SE 0x693
--     after 10) and a strike (level 30, SE 0x692 after 10) (0x021EFC3C); the
--     sky first darkens to 0x3129 over 4 frames and holds 10 (0x021A2154),
--     each flash goes to colour (level, level, 8) over 4 frames and back over
--     the table 0x021EFD1C[level] (15..40); the gap after the run's last
--     flash is a third (0x021EFAF0)
--   * SNOW (1, ov25 0x021EE740..): timer {1, 18, 1, 16, -3, 1, 0}; a flake
--     (0x021EEA34) shows cell rand 4, falls one pixel each time its counter
--     (+8 a frame) passes its period (rand 8 + 12), sways by the 337-step
--     table (ov25 0x021EF790), from x = rand 414 - 32, y = -8 - rand 20, and
--     is gone between y 212 and 232 (0x021EE980)
--   * BLIZZARD (4, 0x021EEB0C): timer {1, 6, 1, 2, -2, 2, 1}; the wind steps
--     through four bases over 1024 spawns (vx {7, 11, 15, 19}, vy {3, 6, 3,
--     6}, 0x021EF770 / 780); a flake k = rand 4 moves (k + 1) [k 3: + 1]
--     times them, gains the x base and loses 1 of vy (down to 1) every 4
--     frames, for rand 3 + 9 frames, from x = -rand 24, y = rand 168 - 32
--     (0x021EEE04 / 0x021EED78); the sheet 0x2A drifts by the 9-step tables
--     0x021EF765 / 0x021EF75C, a step every 28 frames (0x021EEEE0); SE 0x6E3
--   * HAIL (5, 0x021EEF94): timer {0, 8, 1, 1, -4, 2, 1}; a stone k by rand
--     100 against {30, 95} shows cell 2 - k, falls at vy = r mod 23 + 10 (k +
--     1) [+3], vx = (r mod 23) / 4 + 4 (k + 1) [-2] for (r & 3) + 1 frames
--     from x = r mod 270 + 15k - 64, y = (r & 15) - 8, then BOUNCES (cell +
--     3, vx = vy = 2, up on odd frames, both slowing every 4) for (r mod 4) *
--     2 + 8 frames (0x021EF2D4 / 0x021EF1C4); SE 0x6E4
--   * DIAMOND DUST (8, 0x021EF3BC): timer {1, 16, 20, 2, -2, 4, 2}; a
--     sparkle shows cell (rand 20, or rand 4 off the diagonal band) at x = a
--     mod 384 - 64, y = (b & 0xFF) - 8 for a mod 5 + 7 frames (twice that in
--     the band 50 - x / 3 .. 206 - x / 3); its update counts and computes a
--     drift it never stores, so it stays put (0x021EF634 / 0x021EF5D0)
--   * SANDSTORM (3 / 12, ov27): timer {1, 15, 1, 2, -2, 4, 1}; the wind's
--     strength steps through eight (vx, vy) bases over 320 spawns ({6, 10,
--     10, 6, 10, 12, 20, 12}, {4, 4, 4, 8, 8, 4, 4, 4}, 0x021EEB48 / B68); a
--     grain k = 3 - (rand 20) / 6 moves (k + 1) times them, gaining the x
--     base every 5 frames, for rand 20 + 15 frames, from x = -6 - rand 24, y
--     = rand 192 - 64 (one in a thousand half as fast again, cell 4); the
--     sheet 0x2B scrolls 12 a frame (0x021EEAF4); SE 0x6E3
--   * the hardware FOG every program sets (0x021A22E0 -> the fog block
--     0x021A01A4..: +2 FOG_SHIFT, +4 the OFFSET (both to G3X_SetFog,
--     0x0207DC44), +8 the colour (FOG_COLOR 0x04000358 with alpha +3 = 31,
--     0x021A0170), a linear 32-entry table): the programs give the shift and
--     an offset that fades (0x021A232C, M.FOG); the colour is the weather's
--     light file's (/a/0/6/2, 0x021A2108). Mists 10 / 11 / 13 / 14 take shift
--     and offset from ov28's 0x021EEA80 / 0x021EEAA4 by the zone's camera
--     record (the field camera's +0x10)
--   * STRONG STORM (7, 0x021EEF58): timer {1, 4, 1, 1, -4, 1, 1}, the wind
--     state machine and three kinds below (storm / SPAWN.storm)
-- INFERRED: which cell each storm kind shows; the second sheet's zoom drawn
-- as a plain scale; the camera shift
-- uses the camera's distance to its target, not the eye-target distance
-- (0x0207CF3C) of a moving camera; the fog's depth is Gen4DepthFog's, through
-- the zone camera's near / far; the time of day is the host clock; the sheets' index 0 is clear and they are drawn half blended; the
-- lightning is drawn as an added colour, the darkening as a dim; spawn
-- before update within a frame.

local M = {}

M.POOL = 32
M.PROGRAM = { [1] = "snow", [2] = "rain", [3] = "sand", [4] = "blizzard", [5] = "hail", [6] = "thunder",
  [7] = "storm", [8] = "dust", [9] = "mist", [10] = "mist", [11] = "mist", [12] = "sand",
  [13] = "mist", [14] = "mist" }
M.TIMER = {
  rain = { 1, 8, 2, 0, -4, 2, 1 }, thunder = { 1, 15, 2, 0, -3, 1, 1 }, storm = { 1, 4, 1, 1, -4, 1, 1 },
  snow = { 1, 18, 1, 16, -3, 1, 0 }, sand = { 1, 15, 1, 2, -2, 4, 1 },
  blizzard = { 1, 6, 1, 2, -2, 2, 1 }, hail = { 0, 8, 1, 1, -4, 2, 1 }, dust = { 1, 16, 20, 2, -2, 4, 2 },
}
M.SHEET = { [3] = 0x2B, [12] = 0x2B, [4] = 0x2A, [6] = 0x29, [7] = 0x28 }
M.SHEET_STEP = { [3] = 12, [12] = 12, [6] = 9 }
-- the strong storm's wind (ov26 0x021EF7CC: six gusts by the counter mod 72,
-- 0x021EFD74; 1/8-pixel units) and its second sheet's zoom (0x021EFD3C)
M.STORM_GUST = { { 208, 24 }, { 288, 16 }, { 240, 24 }, { 304, 24 }, { 192, 24 }, { 256, 16 } }
M.STORM_ZOOM = { 0x1100, 0x1200, 0x1300, 0x1300, 0x1300, 0x1200, 0x1100, 0x1000, 0x1000, 0x1200,
  0x1300, 0x1200, 0x1200, 0x1100 }
M.SE = { [2] = 0x691, [6] = 0x690, [7] = 0x690, [3] = 0x6E3, [12] = 0x6E3, [4] = 0x6E3, [5] = 0x6E4 }
-- the fog (0x021A22E0 at start, 0x021A232C fading): { FOG_SHIFT, offset
-- at start, offset faded to, over frames }; its colour is the weather's
-- light file's (M.LIGHT, constants.gen5WeatherArt.lights)
M.FOG = { [1] = { 8, 0x7FDF, 0x7F5F, 90 }, [2] = { 8, 0x7FDF, 0x7F5F, 90 }, [3] = { 8, 0x7FDF, 0x7F5E, 90 },
  [4] = { 4, 0x7FFF, 0x7B18, 90 }, [5] = { 9, 0x7FDF, 0x7F80, 60 }, [6] = { 9, 0x7FDF, 0x7F80, 80 },
  [7] = { 9, 0x7FDF, 0x7F80, 10 }, [8] = { 8, 0x7FFF, 0x7F57, 90 }, [9] = { 9, 0x7FDF, 0x7F78, 90 },
  [10] = { 8, 0x7FDF, 0x7F5F, 90 }, [11] = { 8, 0x7FDF, 0x7F5F, 90 }, [12] = { 8, 0x7FDF, 0x7F5E, 90 },
  [13] = { 8, 0x7FDF, 0x7F5F, 90 }, [14] = { 8, 0x7FDF, 0x7F5F, 90 } }
-- weather -> /a/0/6/2 member (arm9 0x0209E054)
M.LIGHT = { [1] = 8, [2] = 7, [3] = 9, [4] = 8, [5] = 8, [6] = 6, [7] = 0, [8] = 8, [9] = 1, [10] = 4,
  [11] = 2, [12] = 9, [13] = 5, [14] = 3 }
-- the mists 10 / 11 / 13 / 14 by the zone's camera record (ov28 0x021EEA80
-- shifts / 0x021EEAA4 offsets, indexed by the field camera's +0x10 -- the
-- /a/0/6/0 record it loaded, 0x0218E260): 8 / 0x7F5F but for these
M.MIST_BY_CAMERA = { [10] = { 1, 0x0000 }, [24] = { 4, 0x0A08 }, [26] = { 8, 0x7F6F } }
M.MIST_AREA = { [10] = true, [11] = true, [13] = true, [14] = true }
M.FOG_OFFSET, M.FOG_SLOPE = 0x6F6F, 2
M.SAND_VX = { 6, 10, 10, 6, 10, 12, 20, 12 }
M.SAND_VY = { 4, 4, 4, 8, 8, 4, 4, 4 }
M.BLIZ_VX, M.BLIZ_VY = { 7, 11, 15, 19 }, { 3, 6, 3, 6 }
M.BLIZ_TX, M.BLIZ_TY = { 7, 8, 8, 8, 8, 8, 7, 7, 7 }, { 3, 2, 1, 2, 1, 2, 3, 2, 3 }
M.FLASH_FADE = { [18] = 15, [19] = 15, [20] = 15, [21] = 15, [22] = 15, [23] = 20, [24] = 20, [25] = 30,
  [26] = 30, [27] = 35, [28] = 35, [29] = 35, [30] = 40, [31] = 40 }
M.CAM_SCALE = 1

-- its own generator, so the weather never moves the game's random numbers
local gen
local function rng()
  gen = gen or love.math.newRandomGenerator(os.time())
  return gen
end
local function rnd(n) return rng():random(0, n - 1) end
local function rand32() return rng():random(0, 0x3FFFFFFF) end
local function trunc(v) return v < 0 and math.ceil(v) or math.floor(v) end

local function game() return package.loaded["src.core.Game"] end
local function art()
  local G = game()
  local c = G and G.data and G.data.constants
  return c and c.gen5WeatherArt
end

local function wrap(p)
  if p.x > 320 then p.x = p.x % 320 elseif p.x < -64 then p.x = p.x + 320 end
  if p.y > 256 then p.y = p.y % 256 elseif p.y < -66 then p.y = p.y + 256 end
end

local function add(st, p)
  if #st.list >= M.POOL then return nil end
  st.list[#st.list + 1] = p
  return p
end

local SPAWN, UPDATE = {}, {}

function SPAWN.rain(st)
  local r = rand32()
  local k, m = r % 3, r % 20
  local p = add(st, { frame = k, t = 0, state = 0 })
  if not p then return end
  p.vy = m + (k + 1) * 16 + (k == 2 and 16 or 0)
  p.vx = math.floor(m / 8) + (k + 1) * 8 + (k == 2 and 8 or 0)
  p.life = r % 2 + 1
  p.x, p.y = r % 256 + 15 * k - 72, -96
  p.vx, p.vy = p.vx * 2, p.vy * 2
  p.splash = rnd(10)
end
function UPDATE.rain(st, p)
  if p.state == 0 then
    p.x, p.y = p.x + p.vx, p.y + p.vy
    p.t = p.t + 2
    if p.t > p.life then
      if p.splash < 7 then p.state = 2 else p.state, p.t, p.frame = 1, 4, 3 end
    end
  elseif p.state == 1 then
    local was = p.t
    p.t = p.t - 1
    if was <= 0 then p.state = 2 end
  else
    return false
  end
  return true
end

function SPAWN.thunder(st)
  local r = rand32()
  local k = r % 3
  local p = add(st, { frame = k, state = 0 })
  if not p then return end
  local v = (r % 16) + 14 * (k + 1)
  p.vx, p.vy = v, v
  p.x, p.y = r % 384 - 128, r % 40 - 80
end
function UPDATE.thunder(st, p)
  if p.state ~= 0 then return false end
  p.x, p.y = p.x + p.vx, p.y + p.vy
  if p.y >= 192 then p.state = 1 end
  return true
end

function SPAWN.snow(st)
  local p = add(st, { frame = rnd(4), acc = 0, phase = 0, period = rnd(8) + 12 })
  if not p then return end
  p.x, p.y = rnd(414) - 32, -8 - rnd(20)
  wrap(p)
end
function UPDATE.snow(st, p)
  local sway = st.sway
  p.x = p.x + (sway and sway[p.phase + 1] or 0)
  if p.acc > p.period then p.y = p.y + 1; p.acc = p.acc % p.period end
  wrap(p)
  p.acc = p.acc + 8
  p.phase = (p.phase + 1) % 337
  if (p.y > 212 and p.y < 232) or (p.y < -284 and p.y > -296) then return false end
  return true
end

function SPAWN.blizzard(st)
  st.wind = ((st.wind or 0) + 1) % 1024
  local i = math.floor(st.wind / 256) + 1
  local vyb, vxb = M.BLIZ_VY[i], M.BLIZ_VX[i]
  local k = rnd(4)
  local p = add(st, { t = 0, life = rnd(3) + 9, frame = k, state = 0, ax = vxb })
  if not p then return end
  p.vx, p.vy = (k + 1) * vxb, (k + 1) * vyb
  if k == 3 then p.vx, p.vy = p.vx + vxb, p.vy + vyb end
  p.x, p.y = -rnd(24), rnd(168) - 32
end
function UPDATE.blizzard(st, p)
  if p.state ~= 0 then return false end
  p.x, p.y = p.x + p.vx, p.y + p.vy
  local was = p.t
  p.t = p.t + 1
  if was > p.life then p.state = 1 end
  if p.t % 4 == 0 then
    p.vx = p.vx + p.ax
    if p.vy > 1 then p.vy = p.vy - 1 end
  end
  return true
end

function SPAWN.hail(st)
  local r = rand32()
  local m = r % 100
  local k = m < 30 and 0 or (m < 95 and 1 or 2)
  local q = r % 23
  local p = add(st, { t = 0, state = 0, frame = 2 - k, seed = r })
  if not p then return end
  p.vy = q + 10 * (k + 1) + (k == 2 and 3 or 0)
  p.vx = math.floor(q / 4) + 4 * (k + 1) - (k == 2 and 2 or 0)
  p.life = r % 4 + 1
  p.x, p.y = r % 270 + 15 * k - 64, r % 16 - 8
  wrap(p)
end
function UPDATE.hail(st, p)
  if p.state == 0 then
    p.t = p.t + 1
    if p.t > p.life then
      p.state = 1
      p.t = (p.seed % 4) * 2 + 8
      p.vx, p.vy = 2, 2
      p.frame = p.frame + 3
    else
      p.x, p.y = p.x + p.vx, p.y + p.vy
      wrap(p)
    end
  elseif p.state == 1 then
    p.x = p.x + p.vx
    if p.t % 2 == 0 then p.y = p.y + p.vy else p.y = p.y - p.vy end
    if p.t % 4 == 0 then
      if p.vy - 1 >= 0 then p.vy = p.vy - 1 end
      if p.vx - 1 >= 0 then p.vx = p.vx - 1 end
    end
    local was = p.t
    p.t = p.t - 1
    if was <= 0 then p.state = 2 end
  else
    return false
  end
  return true
end

function SPAWN.dust(st)
  local a, b = rand32(), rand32()
  local p = add(st, { t = 0, life = a % 5 + 7, frame = a % 20 })
  if not p then return end
  p.x, p.y = a % 384 - 64, b % 256 - 8
  wrap(p)
  local top = 50 - trunc(p.x / 3)
  local span = 206 - trunc(p.x / 3)
  local bottom
  if span < 0 then bottom = top - (b % -span) else bottom = top + (span > 0 and b % span or 0) end
  if top <= p.y and bottom >= p.y then p.life = p.life * 2 else p.frame = a % 4 end
end
function UPDATE.dust(st, p)
  p.t = p.t + 1
  return p.t < p.life
end

function SPAWN.sand(st)
  st.wind = ((st.wind or 0) + 1) % 320
  local i = math.floor(st.wind / 40) + 1
  local vyb, vxb = M.SAND_VY[i], M.SAND_VX[i]
  local life = rnd(20) + 15
  local k = 3 - math.floor((life - 15) / 6)
  local p = add(st, { t = 0, life = life, state = 0, ax = vxb, frame = k })
  if not p then return end
  p.vy, p.vx = vyb * (k + 1), vxb * (k + 1)
  if rnd(1000) == 777 then p.vy = p.vy + math.floor(p.vy / 2); p.frame = 4 end
  p.x, p.y = -6 - rnd(24), rnd(192) - 64
  wrap(p)
end
function UPDATE.sand(st, p)
  if p.state ~= 0 then return false end
  p.x, p.y = p.x + p.vx, p.y + p.vy
  if p.t % 5 == 0 then p.vx = p.vx + p.ax end
  local was = p.t
  p.t = p.t + 1
  if was > p.life then p.state = 1 end
  wrap(p)
  return true
end

local function timerNew(spec)
  return { count = spec[1], interval = spec[2], countTarget = spec[3], intervalTarget = spec[4],
           intervalStep = spec[5], per = spec[6], countStep = spec[7], countdown = 0, steps = 0 }
end

-- 0x021A2AB8
local function timerTick(t, spawn, st)
  local doneI, doneC = false, false
  if t.intervalStep == 0 then doneI = true
  elseif (t.intervalStep < 0 and t.interval <= t.intervalTarget) or (t.intervalStep > 0 and t.interval >= t.intervalTarget) then
    doneI = true; t.interval = t.intervalTarget
  end
  if t.countStep == 0 then doneC = true
  elseif (t.countStep < 0 and t.count <= t.countTarget) or (t.countStep > 0 and t.count >= t.countTarget) then
    doneC = true; t.count = t.countTarget
  end
  t.countdown = t.countdown - 1
  if t.countdown <= 0 then
    for _ = 1, t.count do spawn(st) end
    t.countdown = t.interval
    if not doneI then t.interval = t.interval + t.intervalStep end
    if not doneC then
      t.steps = t.steps + 1
      if t.steps >= t.per then t.steps = 0; t.count = t.count + t.countStep end
    end
  end
end

-- -------------------------------------------------------------- sound

local function se(id)
  local G = game()
  local ok, Sound = pcall(require, "src.core.Sound")
  if not (ok and Sound and G and G.data) then return nil end
  return Sound, G.data
end

local function startLoop(st)
  local id = M.SE[st.id]
  if not id then return end
  local Sound, data = se(id)
  if not Sound then return end
  local name = Sound.seName and Sound.seName(data, id)
  if name == nil then return end
  if pcall(Sound.startLoop, data, name) then st.loop = name end
end

local function playOnce(id)
  local Sound, data = se(id)
  if Sound and Sound.playSe then pcall(Sound.playSe, data, id) end
end

function M.stop(st)
  if st and st.loop then
    local ok, Sound = pcall(require, "src.core.Sound")
    if ok and Sound and Sound.stopLoop then pcall(Sound.stopLoop, st.loop) end
    st.loop = nil
  end
end

-- -------------------------------------------------------------- lightning

-- the run of flashes (0x021EFBFC / 0x021EFC3C, mode 2's two patterns)
local function strikes()
  local list = {}
  if rnd(100) < 75 then
    list[1] = { level = rnd(3) + 24, gap = rnd(300) + 240, delay = 13, se = 0x692 }
  else
    local n = rnd(2) + 1
    for i = 1, n do list[i] = { level = rnd(3) + 18, gap = rnd(4), delay = 10, se = 0x693 } end
    list[n + 1] = { level = 30, gap = rnd(300) + 240, delay = 10, se = 0x692 }
    -- the gap after the run's last flash is a third (0x021EFAF0)
    list[n + 1].gap = math.floor(list[n + 1].gap / 3)
  end
  return list
end

local function lightning(st)
  local L = st.light
  if not L then
    L = { state = 0, wait = rnd(3), flash = 0, dim = 0 }
    st.light = L
  end
  -- the flash and the dim fade on their own clocks
  if L.flashT then
    L.flashT = L.flashT + 1
    local up, down = 4, M.FLASH_FADE[L.level] or 15
    if L.flashT <= up then L.flash = L.flashT / up
    elseif L.flashT <= up + down then L.flash = 1 - (L.flashT - up) / down
    else L.flash, L.flashT = 0, nil end
  end
  if L.soundIn then
    L.soundIn = L.soundIn - 1
    if L.soundIn <= 0 then playOnce(L.soundId); L.soundIn = nil end
  end
  if L.state == 0 then
    L.wait = L.wait - 1
    if L.wait < 0 then L.state = 1 end
  elseif L.state == 1 then
    L.list, L.at = strikes(), 1
    L.state, L.wait, L.dimT = 2, 10, 0
  elseif L.state == 2 then
    -- darkening to 0x3129 over 4 frames, held 10
    L.dimT = L.dimT + 1
    L.dim = math.min(1, L.dimT / 4)
    L.wait = L.wait - 1
    if L.wait <= 0 then L.state = 3 end
  elseif L.state == 3 then
    local s = L.list[L.at]
    L.level, L.flashT = s.level, 0
    L.soundIn, L.soundId = s.delay, s.se
    L.wait = s.gap
    L.state = 4
  elseif L.state == 4 then
    L.wait = L.wait - 1
    if L.wait <= 0 then
      if L.at < #L.list then L.at = L.at + 1; L.state = 3
      else L.state, L.dim = 1, 0 end
    end
  end
end

-- THE STRONG STORM'S WIND (ov26 0x021EF664 / 0x021EF614 / 0x021EF950):
-- 1 calm (rand 400 + 60 frames; SE 0x71F 24 before its end) -> 3 rising
-- (16; SE 0x720, fog to 0x7F70 over 10) -> 2 the gale (rand 400 + 60; the
-- gust SE 0x71E every rand 16 + 50 frames while 74 or more remain) -> 4
-- falling (16) -> 1 (fog back to 0x7F80 over 10). The wind (+0x16 / +0x18):
-- calm 0 (160 / 16 for its last 9 frames), rising / falling 160 / 16, the
-- gale the six-step table by the counter
local function storm(st)
  local W = st.wind
  if not W then
    W = { state = 1, n = 0, limit = rnd(400) + 60, gx = 0, gy = 0, zoom = 0x1000, gust = 0, gustAt = rnd(16) + 50 }
    st.wind = W
  end
  W.n = W.n + 1
  if W.state == 1 then
    if W.n == W.limit - 24 then playOnce(0x71F) end
    if W.n >= W.limit then
      W.state, W.limit, W.n = 3, 16, 0
      st.fogTo, st.fogFromT = 0x7F70, st.frame
      playOnce(0x720)
    end
  elseif W.state == 2 then
    if W.n == W.limit - 24 then playOnce(0x71F) end
    if W.n <= W.limit - 0x4A then
      W.gust = W.gust + 1
      if W.gust >= W.gustAt then playOnce(0x71E); W.gust, W.gustAt = 0, rnd(16) + 50 end
    end
    if W.n >= W.limit then W.state, W.limit, W.n = 4, 16, 0 end
  elseif W.state == 3 then
    if W.n >= W.limit then W.state, W.limit, W.n = 2, rnd(400) + 60, 0 end
  elseif W.state == 4 then
    if W.n >= W.limit then
      W.state, W.limit, W.n = 1, rnd(400) + 60, 0
      st.fogTo, st.fogFromT = 0x7F80, st.frame
    end
  end
  if W.state == 1 then
    if W.limit - W.n >= 9 then W.gx, W.gy = 0, 0 else W.gx, W.gy = 160, 16 end
    W.zoom = 0x1000
  elseif W.state == 2 then
    local g = M.STORM_GUST[math.floor((W.n % 72) * 6 / 72) + 1]
    W.gx, W.gy = g[1], g[2]
    W.zoom = M.STORM_ZOOM[math.floor((W.n % 224) * 14 / 224) + 1]
  else
    W.gx, W.gy, W.zoom = 160, 16, 0x800
  end
  -- the two sheets (0x021EF830): in a wind 9 / 3 and 9 / 2 a frame, calm 3 / 8
  if W.gx ~= 0 then
    st.sx, st.sy = (st.sx + 9) % 256, (st.sy + 3) % 256
    st.sx2, st.sy2 = ((st.sx2 or 0) + 9) % 256, ((st.sy2 or 0) + 2) % 256
  else
    st.sx, st.sy = (st.sx + 3) % 256, (st.sy + 8) % 256
  end
end

-- the storm's three kinds (spawn 0x021EF364 / 0x021EF454 / 0x021EF58C,
-- update 0x021EF2D8 / 0x021EF3E0 / 0x021EF4D0), in 1/8 pixels; which kind
-- by the wind state (0x021EF220): calm the rain (1), the gale 0 above 50 of
-- 100 else 2 (and only on even draws), rising / falling 2 above 80 else 1
function SPAWN.storm(st)
  local W = st.wind
  local state = W and W.state or 1
  local r = rand32()
  if state == 2 and r % 2 == 1 then return end
  local m = r % 100
  local kind
  if state == 1 then kind = 1
  elseif state == 2 then kind = (m > 50) and 0 or 2
  else kind = (m > 80) and 2 or 1 end
  -- (INFERRED cells: 0 the small debris, 1 the rain streak, 2 the sheet)
  local cell = ({ [0] = 2, [1] = 1, [2] = 0 })[kind]
  local p = add(st, { kind = kind, frame = cell })
  if not p then return end
  if kind == 0 then
    local q = r % 24
    p.vx, p.vy = q + 16, q + 8
    p.wx, p.wy = W and W.gx or 0, W and W.gy or 0
    p.x8, p.y8 = (r % 8 - 8) * 8, (r % 160 - 16) * 8
  elseif kind == 1 then
    local q = r % 43
    p.vx, p.vy = q + 86, q * 2 + 258
    p.x8, p.y8 = (r % 336 - 80) * 8, (r % 40 - 80) * 8
  else
    local q = r % 24
    p.vx, p.vy = q + 80, q + 14
    p.wx, p.wy = p.vx + (W and W.gx or 0), p.vy + (W and W.gy or 0)
    p.x8, p.y8 = (r % 8 - 8) * 8, (r % 160 - 16) * 8
  end
  p.x, p.y = trunc(p.x8 / 8), trunc(p.y8 / 8)
end
function UPDATE.storm(st, p)
  local W = st.wind
  local gx, gy = W and W.gx or 0, W and W.gy or 0
  if p.kind == 0 then
    if gx ~= 0 then p.wx, p.wy = gx, gy end
    p.x8, p.y8 = p.x8 + p.vx + p.wx, p.y8 + p.vy + p.wy
  elseif p.kind == 1 then
    p.x8, p.y8 = p.x8 + p.vx + gx, p.y8 + p.vy + gy
  else
    if gx ~= 0 then p.wx, p.wy = p.vx + gx, p.vy + gy end
    p.x8, p.y8 = p.x8 + p.wx, p.y8 + p.wy
  end
  p.x, p.y = trunc(p.x8 / 8), trunc(p.y8 / 8)
  if p.kind == 1 then return p.x < 254 and p.y < 160 end
  return p.x < 256 and p.y < 192
end

-- -------------------------------------------------------------- the program

function M.start(id)
  local prog = M.PROGRAM[id]
  if not prog then return nil end
  local a = art()
  local st = { id = id, prog = prog, list = {}, scroll = 0, sx = 0, sy = 0, fogT = 0, frame = 0, phase = 0 }
  if prog ~= "mist" then
    local spec = (id == 7) and M.TIMER.storm or M.TIMER[prog]
    st.timer = timerNew(spec)
    st.set = a and a.sets and (a.sets[id] or a.sets[tostring(id)])
    st.sway = a and a.snowSway
    -- already falling when the map is entered (the programs' "start
    -- in progress" callbacks; INFERRED length)
    for _ = 1, (prog == "snow") and 240 or 40 do M.step(st, true) end
  end
  startLoop(st)
  return st
end

-- one field frame
function M.step(st, quiet)
  st.frame = st.frame + 1
  if st.fogT < 90 then st.fogT = st.fogT + 1 end
  local step = M.SHEET_STEP[st.id]
  if step then st.sx = (st.sx + step) % 256; st.sy = (st.sy + step) % 256 end
  if st.prog == "storm" then storm(st) end
  if st.prog == "blizzard" then
    -- 0x021EEEE0: the sheet drifts by the tables, a step every 28 frames
    local i = math.floor(st.phase / 28) + 1
    st.phase = (st.phase + 1) % 252
    st.sx = (st.sx + M.BLIZ_TX[i]) % 256
    st.sy = (st.sy + M.BLIZ_TY[i]) % 256
  end
  if not quiet then
    if st.id == 6 then lightning(st) end
  end
  if not st.timer then return end
  local spawn, update = SPAWN[st.prog], UPDATE[st.prog]
  timerTick(st.timer, spawn, st)
  local keep = {}
  for _, p in ipairs(st.list) do
    if update(st, p) then keep[#keep + 1] = p end
  end
  st.list = keep
end

-- screen pixels per world unit at the camera's target: READ, 0x021A2D30
-- gives the view's width and height there as 2 * distance / the projection's
-- [0][0] / [1][1] (0x02148B54), and 0x021A244C divides them into 256 / 192
-- pixels -- both come to 96 * cot(half fov) / distance (Castelia's camera:
-- 0.70)
function M.camScale(ow)
  local cam = ow and ow.map and ow.map.def and ow.map.def.gen5Camera
  local d, h = cam and tonumber(cam.distance), cam and tonumber(cam.halfFov)
  if not (d and h and d > 0 and h > 0) then return M.CAM_SCALE end
  return 96 / (math.tan(math.rad(h)) * d)
end

-- 0x021A244C / 0x021A2564: everything moves against the camera
local function cameraShift(st, ow)
  local p = ow.player
  local px, py = p and p.px, p and p.py
  if not (px and py) then return end
  local last = st.cam
  st.cam = { px, py, ow.map and ow.map.id }
  if not last or last[3] ~= st.cam[3] then return end
  local dx, dy = px - last[1], py - last[2]
  if math.abs(dx) > 1000 or math.abs(dy) > 100 or (dx == 0 and dy == 0) then return end
  local k = M.camScale(ow)
  local sx, sy = dx * k, dy * k
  for _, q in ipairs(st.list) do q.x, q.y = q.x - sx, q.y - sy end
  st.sx, st.sy = (st.sx - sx) % 256, (st.sy - sy) % 256
end

-- the overworld's tick: follows the zone's weather (Gen5Weather) at 30 Hz
function M.update(ow, dt)
  if not (ow and ow.map) then return end
  require("src.world.Gen5Weather").look(ow)
  local id = ow.gen5WeatherId or 0
  local st = ow.gen5WeatherFx
  if not st or st.id ~= id then
    M.stop(st)
    st = (art() and M.PROGRAM[id]) and M.start(id) or nil
    ow.gen5WeatherFx = st
  end
  if not st then return end
  st.acc = (st.acc or 0) + (tonumber(dt) or 0) * 30
  local n = 0
  while st.acc >= 1 and n < 4 do
    st.acc = st.acc - 1
    cameraShift(st, ow)
    M.step(st)
    n = n + 1
  end
  if st.acc > 4 then st.acc = 0 end
end

-- is this weather drawn by the programs here (rather than the Gen 3 looks)?
function M.active(ow)
  local st = ow and ow.gen5WeatherFx
  return st ~= nil and st.id == (ow.gen5WeatherId or 0)
end

-- the light file's fog colour for now (0x021A07B4: the record whose time
-- follows the clock's)
function M.fogColour(id)
  local a = art()
  local lights = a and a.lights
  local m = M.LIGHT[id]
  local recs = lights and m and (lights[m] or lights[tostring(m)])
  if not recs or not recs[1] then return 0x7FFF end
  local t = os.date("*t")
  local now = (t.hour or 12) * 3600 + (t.min or 0) * 60
  local prev = 0
  for _, r in ipairs(recs) do
    if prev <= now and now < r.t then return r.fog end
    prev = r.t
  end
  return recs[1].fog
end

local function bgr555(c)
  return c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
end

-- the depth-fog row (src/render/Gen4DepthFog.lua) of the weather on screen
function M.depthRow()
  local G = game()
  local ow = G and G.overworld
  local st = ow and ow.gen5WeatherFx
  local fog = st and M.FOG[st.id]
  if not fog then return nil end
  local shift, from, to, frames = fog[1], fog[2], fog[3], fog[4]
  if M.MIST_AREA[st.id] then
    local cam = ow.map and ow.map.def and ow.map.def.gen5Camera
    local idx = cam and tonumber(tostring(cam.id or ""):match("(%d+)$"))
    local m = idx and M.MIST_BY_CAMERA[idx]
    if m then shift, to = m[1], m[2] end
  end
  local k = math.min(1, (st.fogT or 0) / math.max(1, frames))
  local offset = math.floor(from + (to - from) * k)
  if st.fogTo then
    -- the storm's own fades, 10 frames each (0x021EF6C4 / 0x021EF646)
    local k2 = math.min(1, (st.frame - (st.fogFromT or st.frame)) / 10)
    offset = math.floor(offset + (st.fogTo - offset) * k2)
  end
  return { slope = shift, offset = offset, rgb = { bgr555(M.fogColour(st.id)) } }
end

local images = {}
local function image(path)
  if not path then return nil end
  if images[path] == nil then
    local ok, img = pcall(function() return require("src.render.Assets").image(path) end)
    images[path] = ok and img or false
    if ok and img then img:setFilter("nearest", "nearest"); img:setWrap("repeat", "repeat") end
  end
  return images[path] or nil
end

-- Renderer.screenWeather: the 256 x 192 screen scaled to the view's height,
-- centred across its width (as Gen4SnowView)
function M.draw(ow, w, h)
  local st = ow and ow.gen5WeatherFx
  if not st then return false end
  local g = love.graphics
  local s = h / 192
  local left = (w - 256 * s) / 2
  g.push("all")
  g.setColor(1, 1, 1, 1)
  local a = art()
  local tid = M.SHEET[st.id]
  local tex = tid and a and a.textures and (a.textures[tid] or a.textures[tostring(tid)])
  local timg = tex and image(tex.path)
  if timg then
    g.setColor(1, 1, 1, 0.5)
    local q = g.newQuad(-st.sx - left / s, -st.sy, w / s, h / s, timg:getDimensions())
    g.draw(timg, q, 0, 0, 0, s, s)
    g.setColor(1, 1, 1, 1)
  end
  -- the strong storm's second sheet, 0x27, zoomed by the gale (0x021EF908)
  local t2 = st.id == 7 and a and a.textures and (a.textures[0x27] or a.textures[tostring(0x27)])
  local img2 = t2 and image(t2.path)
  if img2 and st.wind and st.wind.gx ~= 0 then
    local z = (st.wind.zoom or 0x1000) / 0x1000
    g.setColor(1, 1, 1, 0.5)
    local q = g.newQuad(-(st.sx2 or 0) - left / s, -(st.sy2 or 0), w / s / z, h / s / z, img2:getDimensions())
    g.draw(img2, q, 0, 0, 0, s * z, s * z)
    g.setColor(1, 1, 1, 1)
  end
  local cells = st.set and st.set.cells
  if cells then
    for _, p in ipairs(st.list) do
      local c = cells[p.frame + 1] or cells[tostring(p.frame + 1)]
      local img = c and image(c.path)
      if img then
        g.draw(img, left + math.floor(p.x + c.x) * s, math.floor(p.y + c.y) * s, 0, s, s)
      end
    end
  end
  local L = st.light
  if L then
    if (L.dim or 0) > 0 then
      g.setColor(9 / 31, 9 / 31, 12 / 31, 0.35 * L.dim)
      g.rectangle("fill", 0, 0, w, h)
    end
    if (L.flash or 0) > 0 and L.level then
      g.setBlendMode("add")
      local v = L.level / 31
      g.setColor(v, v, 8 / 31, 0.6 * L.flash)
      g.rectangle("fill", 0, 0, w, h)
      g.setBlendMode("alpha")
    end
  end
  g.pop()
  return true
end

return M
