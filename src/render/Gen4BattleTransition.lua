-- PLATINUM'S INTO-BATTLE TRANSITIONS, after pokeplatinum
-- src/overlay005/encounter_effect_core.c and its helpers in encounter_effect.c
-- and screen_fade.c.
--
-- Which of the 31 plays is `Gen4EncounterEffect.cutIn` (src/world). This file
-- plays it. The cartridge builds every one out of the same few parts, and so
-- does this:
--
--   * MASTER BRIGHTNESS (-16 black .. +16 white) per screen -- the flashes;
--   * the captured FIELD, which the effects move around with H-blank tricks:
--     row bands sliding apart (ScreenSlice), the screen shrinking into two
--     corners (ScreenSplit), a sine wave per scanline (water's ScreenShake);
--   * the 3D camera's DISTANCE and FOV, which here become a zoom of the frame
--     about its centre -- distance D becomes a scale of D0 / D, which is what
--     the perspective camera does to everything at the target's depth;
--   * window FADES (circle, blinds, the X, the growing box, the half-dome);
--   * OBJs: the Poke Balls, the Galactic "G", the VS, the mugshots, the
--     League banners -- out of `gen4_encounter_effects`, the NARC's own art;
--   * the gym leaders' scrolling banner on BG3.
--
-- TIME IS THE CARTRIDGE'S: the field runs its tasks once per main-loop pass,
-- which waits for two V-blanks, so every count below is a 30 Hz tick and this
-- advances one every other 60 Hz update.
--
-- The scripts are coroutines that read like the C state machines: `tick()` is
-- one state turn, `wait(n)` is a counter, `spawn` is a parallel SysTask.
--
-- NOT REPRODUCED, and said so rather than approximated into something else:
-- the Elite Four's 3D particle bursts (SPL resources 107/108) and the
-- mythical camera's pitch/yaw snaps (only its FOV, i.e. its zoom, is applied).
-- The mugshots' silhouettes use the mugshot's own palette darkened 14/16, where
-- the cartridge darkens the trainer class's battle palette -- the same colours
-- for every class that has a mugshot.

local Gen4BattleTransition = {}
Gen4BattleTransition.__index = Gen4BattleTransition

local floor, abs, sin, cos, tan, pi = math.floor, math.abs, math.sin, math.cos, math.tan, math.pi

local D0 = 666.922119140625          -- the default field camera's distance
local FOV0 = 0x5C1                    -- ...and its half-FOV, in u16 angle units
local TURN = 0x10000

local function trunc(x) if x >= 0 then return floor(x) end return -floor(-x) end

-- ---------------------------------------------------------------------------
-- The interpolators, exactly as encounter_effect.c computes them: the value is
-- taken with the step count BEFORE it advances, and the update that reports
-- done is the (n+1)th.
-- ---------------------------------------------------------------------------

local function Lin(a, b, n)
  local t = 0
  return function()
    local v = a + trunc((b - a) * t / n)
    if t + 1 <= n then t = t + 1; return v, false end
    return v, true
  end
end
Gen4BattleTransition.Lin = Lin

local function LinF(a, b, n)        -- the fx32 one: no truncation to speak of
  local t = 0
  return function()
    local v = a + (b - a) * t / n
    if t + 1 <= n then t = t + 1; return v, false end
    return v, true
  end
end

local function Quad(a, b, v0, n)
  local acc = 2 * ((b - a) - v0 * n) / (n * n)
  local t = 0
  return function()
    local v = a + v0 * t + acc * t * t / 2
    if t + 1 <= n then t = t + 1; return v, false end
    return v, true
  end
end
Gen4BattleTransition.Quad = Quad

local function zoomFor(distance)
  if distance < 40 then distance = 40 end
  return D0 / distance
end

local function fovZoom(fov)
  return tan(FOV0 / TURN * 2 * pi) / tan(fov / TURN * 2 * pi)
end

-- ---------------------------------------------------------------------------
-- The scheduler.
-- ---------------------------------------------------------------------------

local tick = coroutine.yield
local function wait(n) for _ = 1, n do tick() end end
local function waitFor(f) while not f() do tick() end end

local function spawn(S, fn)
  local h = { done = false }
  local co = coroutine.create(function() fn(h); h.done = true end)
  h.co = co
  S.tasks[#S.tasks + 1] = h
  return h
end

-- drive(interp, apply): run an interpolator to completion, one step a tick.
local function drive(S, interp, apply)
  return spawn(S, function(h)
    while not h.dead do
      local v, done = interp()
      apply(v)
      if done then return end
      tick()
    end
  end)
end

-- EncounterEffect_Flash: the other screen ramps 0 -> `other` over 8 steps for
-- as long as the flash runs; the top goes 0 -> col -> 0 in 3+3 steps, `n`
-- times, with an init tick before each ramp and a finish tick at the end.
local function flash(S, col, other, n)
  return spawn(S, function()
    local o = Lin(0, other, 8)
    local function each() S.other = (o()) end
    each(); tick()                           -- init the other screen's fade
    for _ = 1, n do
      each(); tick()                         -- init the target ramp
      local up = Lin(0, col, 3)
      repeat local v, d = up(); S.bright = v; each(); tick() until d
      each(); tick()                         -- init the ramp back
      local down = Lin(col, 0, 3)
      repeat local v, d = down(); S.bright = v; each(); tick() until d
    end
  end)
end

-- StartScreenFade(FADE_MAIN_ONLY, kind, ..., colour, steps, 1): one step a
-- tick, a cleanup tick, and the screen left in the fade's colour.
local function fade(S, kind, colour, steps)
  return spawn(S, function()
    for k = 1, steps do
      S.fade = { kind = kind, colour = colour, k = k, steps = steps }
      tick()
    end
    S.fade = nil
    S.cover = colour
    S.other = colour == "white" and 16 or -16
  end)
end

local function sprite(S, t)
  t.scale = t.scale or 1
  t.rot = t.rot or 0
  t.alpha = t.alpha or 1
  t.visible = t.visible ~= false
  t.pri = t.pri or 1
  t.serial = #S.sprites + 1
  S.sprites[#S.sprites + 1] = t
  return t
end

local function blackout(S)
  S.cover = "black"
  S.other = -16
end

-- ---------------------------------------------------------------------------
-- The effects, in EncEffectCutIn order.
-- ---------------------------------------------------------------------------

local E = {}

-- 0/1: GRASS. Two flashes, the field's rows slide apart in bands (2 px for the
-- stronger opponent, 5 px for the weaker) after a small recoil, the camera
-- pulls back then lunges in.
local function grass(higher)
  local pps = higher and 2 or 5
  local e1 = higher and -3 or -2
  local cam2, camV2 = higher and -50 or -30, higher and -255 or -100
  return function(S)
    local f = flash(S, higher and 16 or -16, -16, 2)
    waitFor(function() return f.done end)
    S.slice = { pps = pps, x = 0 }
    local slice = drive(S, Quad(0, e1, -12, 7), function(v) S.slice.x = floor(v) end)
    local cam = Quad(D0, D0 + 50, 30, 6)
    local d
    repeat local v; v, d = cam(); S.zoom = zoomFor(v); tick() until d
    slice.dead = true
    slice = drive(S, Quad(e1, 255, 30, 6), function(v) S.slice.x = floor(v) end)
    local base = D0 + 50
    cam = Quad(base, base + cam2, camV2, 6)
    repeat local v; v, d = cam(); S.zoom = zoomFor(v); tick() until d
    waitFor(function() return slice.done end)
    tick()
    blackout(S)
    S.slice = nil
  end
end
E.grass_low, E.grass_high = grass(false), grass(true)

-- 2/3: WATER. The wave starts 11 ticks into the flashes without waiting for
-- them; 13 ticks after that the blinds close.
local function water(higher)
  return function(S)
    flash(S, higher and 16 or -16, -16, 2)
    wait(11)
    S.shake = { inc = higher and 1023 or 682, amp = higher and 15 or 12, pos = 0 }
    spawn(S, function() while true do tick(); S.shake.pos = (S.shake.pos + 8) % 192 end end)
    wait(13)
    local f = fade(S, "blinds", "black", 8)
    waitFor(function() return f.done end)
  end
end
E.water_low, E.water_high = water(false), water(true)

-- 4/5: CAVE. Flashes, then the circle closes while the camera dives.
local function cave(higher)
  return function(S)
    local f = flash(S, higher and 16 or -16, -16, 2)
    waitFor(function() return f.done end)
    tick()
    local c = fade(S, "circle", "black", 12)
    drive(S, Quad(D0, D0 + (higher and -800 or -400), higher and -5 or -2, 12),
          function(v) S.zoom = zoomFor(v) end)
    waitFor(function() return c.done end)
  end
end
E.cave_low, E.cave_high = cave(false), cave(true)

-- 6: TRAINER, GRASS, WEAKER. The big ball spins up from nothing, splits, and
-- its halves leave with the two halves of the screen.
E.trainer_grass_low = function(S)
  local f = flash(S, -16, -16, 2)
  waitFor(function() return f.done end)
  local a = sprite(S, { key = "trainer_high", cell = 0, x = 128, y = 96 })
  local b = sprite(S, { key = "trainer_high", cell = 0, x = 128, y = 96 })
  local sc, rot = Quad(0.01, 1, 2 / 4096, 10), Lin(0, 0xFFFF, 10)
  local d1, d2
  repeat
    local s, r
    s, d1 = sc(); r, d2 = rot()
    a.scale, b.scale = s, s
    a.rot, b.rot = r, r - 0x100
    tick()
  until d1 and d2
  a.rot, b.rot = 0, 0
  a.cell, b.cell = 1, 2
  S.slice = { pps = 96, x = 0 }
  local slice = drive(S, Quad(0, 255, 10, 6), function(v) S.slice.x = floor(v) end)
  drive(S, Quad(0, 255, 10, 6), function(v) a.x = 128 - v; b.x = 128 + v end)
  drive(S, Quad(D0, D0 - 500, -10, 6), function(v) S.zoom = zoomFor(v) end)
  waitFor(function() return slice.done end)
  tick()
  blackout(S)
end

-- 7: TRAINER, GRASS, STRONGER. Two small balls cross, spinning, and the
-- screen splits into its corners.
E.trainer_grass_high = function(S)
  local f = flash(S, 16, -16, 2)
  waitFor(function() return f.done end)
  local a = sprite(S, { key = "trainer_low", cell = 0, x = 320, y = 64 })
  local b = sprite(S, { key = "trainer_low", cell = 0, x = -64, y = 128 })
  local v, r = LinF(-192, 192, 8), Lin(0, 2 * 0xFFFF, 8)
  local d
  repeat
    local x, rr
    x, d = v(); rr = r()
    a.x, b.x = 128 - x, 128 + x
    a.rot, b.rot = rr, -rr
    tick()
  until d
  a.visible, b.visible = false, false
  S.split = { x = 0, y = 0 }
  local sx, sy = Quad(0, 255, 1, 8), Quad(0, 96, 1, 8)
  drive(S, Quad(D0, D0 - 500, -10, 8), function(z) S.zoom = zoomFor(z) end)
  repeat
    local x, y
    x, d = sx(); y = sy()
    S.split.x, S.split.y = floor(x), floor(y)
    tick()
  until d
  tick()
  blackout(S)
end

-- 8: TRAINER, WATER, WEAKER. The interlaced wave, the big ball fades in
-- spinning, then shrinks away as a black box grows from the centre.
E.trainer_water_low = function(S)
  local f = flash(S, -16, -16, 2)
  spawn(S, function()
    wait(12)
    S.shake = { inc = 682, amp = 12, pos = 0, invert = 2 }
    while true do tick(); S.shake.pos = (S.shake.pos + 8) % 192 end
  end)
  waitFor(function() return f.done end)
  local a = sprite(S, { key = "trainer_high", cell = 0, x = 128, y = 96, alpha = 0 })
  local b = sprite(S, { key = "trainer_high", cell = 0, x = 128, y = 96, alpha = 0 })
  local eva, rot = Lin(0, 16, 8), Lin(0, 0xFFFF, 8)
  local de, dr, prev = false, false, 0
  repeat
    if not dr then
      local r; r, dr = rot()
      a.rot, b.rot, prev = r, prev, r
      if dr then a.rot, b.rot = 0, 0 end
    end
    if not de then
      local e; e, de = eva()
      a.alpha, b.alpha = e / 16, e / 16
    end
    tick()
  until de and dr
  a.alpha, b.alpha = 1, 1
  local sc = drive(S, Quad(1, 0.01, 0.1, 8), function(s) a.scale, b.scale = s, s end)
  drive(S, Quad(D0, D0 - 500, -10, 8), function(z) S.zoom = zoomFor(z) end)
  local box = fade(S, "box", "black", 8)
  waitFor(function() return sc.done and box.done end)
  a.visible, b.visible = false, false
end

-- 9 and 11 share it: a ball rising (or falling) over a column of black.
local function column(S, x, y0, y1, rot, rect)
  local b = sprite(S, { key = "trainer_low", cell = 0, x = x, y = y0 })
  return spawn(S, function()
    local y, r, ry = Lin(y0, y1, rect and 6 or 5), Lin(0, rot, rect and 6 or 5),
                     rect and Lin(312, 0, 6)
    local d
    repeat
      local yy; yy, d = y(); b.y = yy; b.rot = (r())
      if ry then
        local cy = ry()
        S.rects[rect] = { x = x - 43, y = cy - 32, w = 86, h = 224 - cy + 32, toBottom = true }
      end
      tick()
    until d
    if not rect then b.visible = false end
  end)
end

-- 9: TRAINER, WATER, STRONGER. Three balls rise, each dragging a black column.
E.trainer_water_high = function(S)
  local f = flash(S, 16, -16, 2)
  spawn(S, function()
    wait(14)
    S.shake = { inc = 682, amp = 12, pos = 0, invert = 2 }
    while true do tick(); S.shake.pos = (S.shake.pos + 8) % 192 end
  end)
  waitFor(function() return f.done end)
  wait(7)
  drive(S, Quad(D0, D0 - 500, -10, 16), function(z) S.zoom = zoomFor(z) end)
  local c1 = column(S, 43, 231, -32, 0xFFFF, 1)
  wait(5)
  local c2 = column(S, 215, 231, -32, -0xFFFF, 2)
  wait(3)
  local c3 = column(S, 129, 231, -32, 0xFFFF, 3)
  waitFor(function() return c1.done and c2.done and c3.done end)
  tick()
  blackout(S)
end

-- 10: TRAINER, CAVE, WEAKER. One ball drops and grows, then the dome closes.
E.trainer_cave_low = function(S)
  local f = flash(S, -16, -16, 2)
  waitFor(function() return f.done end)
  local b = sprite(S, { key = "trainer_low", cell = 0, x = 128, y = -32, scale = 0.1 })
  local y, sc, r = Quad(0, 256, 2, 12), Quad(0.1, 2, 0, 12), Lin(0, 0xFFFF, 12)
  local d
  repeat
    local yy; yy, d = y()
    b.y = -32 + yy; b.scale = (sc()); b.rot = (r())
    tick()
  until d
  b.visible = false
  drive(S, Quad(D0, D0 - 1000, 10, 8), function(z) S.zoom = zoomFor(z) end)
  local c = fade(S, "dome", "black", 8)
  waitFor(function() return c.done end)
end

-- 11: TRAINER, CAVE, STRONGER. Three balls fall, then black blocks stack up
-- from the bottom row, one a tick.
local BLOCK_COLUMNS = { 0, 2, 5, 7, 1, 6, 3, 4 }
Gen4BattleTransition.BLOCK_COLUMNS = BLOCK_COLUMNS
E.trainer_cave_high = function(S)
  local f = flash(S, 16, -16, 2)
  waitFor(function() return f.done end)
  local c1 = column(S, 128, -32, 224, 0xFFFF)
  tick()
  local c2 = column(S, 208, -32, 224, -0xFFFF)
  wait(3)
  local c3 = column(S, 48, -32, 224, 0xFFFF)
  waitFor(function() return c1.done and c2.done and c3.done end)
  drive(S, Quad(D0, D0 - 1000, 10, 64), function(z) S.zoom = zoomFor(z) end)
  for i = 0, 47 do
    local col, row = BLOCK_COLUMNS[i % 8 + 1], floor(i / 8)
    tick()
    S.rects[#S.rects + 1] = { x = 32 * col, y = 160 - 32 * row, w = 32, h = 32 }
  end
  tick()
  blackout(S)
end

-- The VS: three outlines shrinking 2 -> 1 a few ticks apart, then the solid.
local function vsSequence(S, x, y, key)
  return spawn(S, function()
    local tasks = {}
    for i = 0, 3 do
      if i < 3 then
        local s = sprite(S, { key = key or "vs", cell = 1, x = x, y = y, scale = 2, pri = 0 })
        tasks[#tasks + 1] = drive(S, LinF(2, 1, 6), function(v) s.scale = v end)
      else
        sprite(S, { key = key or "vs", cell = 0, x = x, y = y, pri = 0 })
      end
      if i < 3 then wait(3) end
    end
    waitFor(function()
      for _, t in ipairs(tasks) do if not t.done then return false end end
      return true
    end)
  end)
end

-- 12-19: THE GYM LEADERS. One white flash; the banner scrolls in from the
-- right behind a zigzag edge; VS; the mugshot slides in dark, a white flash
-- brings its colours, the field darkens and the name appears; then white.
local function leader(who)
  return function(S, T)
    local f = flash(S, 16, 16, 1)
    waitFor(function() return f.done end)
    S.banner = { key = who .. "/banner", scroll = 0, edge = 255 }
    spawn(S, function() while true do tick(); S.banner.scroll = (S.banner.scroll + 30) % 512 end end)
    local reveal = drive(S, Lin(255, 0, 6), function(v) S.banner.edge = v end)
    waitFor(function() return reveal.done end)
    wait(11)
    local vs = vsSequence(S, 72, 74)
    waitFor(function() return vs.done end)
    local m = sprite(S, { key = who .. "/mugshot", cell = 0, x = 272, y = 66, dark = 14, pri = 0 })
    local slide = drive(S, Quad(272, 214, -64, 4), function(v) m.x = v end)
    waitFor(function() return slide.done end)
    wait(11)
    local up = Lin(0, 16, 3)
    local d
    repeat local v; v, d = up(); S.bright = v; tick() until d
    m.dark = 0
    S.darkField = 14
    S.name = { text = T.trainerName, x = 122, y = 80 }
    local down = Lin(16, 0, 3)
    repeat local v; v, d = down(); S.bright = v; tick() until d
    wait(27)
    local w = fade(S, "bright", "white", 15)
    waitFor(function() return w.done end)
  end
end
for _, who in ipairs({ "leader_roark", "leader_gardenia", "leader_wake", "leader_maylene",
                       "leader_fantina", "leader_candice", "leader_byron", "leader_volkner" }) do
  E[who] = leader(who)
end

-- 20-24: THE ELITE FOUR AND THE CHAMPION. The field freezes darkened; the
-- player and the opponent slide in from either side on their banners; VS;
-- a white flash brings their colours; they shake, then fly apart into white.
local function league(who, panFrames)
  return function(S, T)
    local f = flash(S, 16, 16, 1)
    spawn(S, function() wait(8); S.freeze = true end)
    local girl = T.playerGender == "girl" or T.playerGender == "female"
    local pal = who .. "/banner.NCLR"
    local p = sprite(S, { key = girl and "player_female/mugshot" or "player_male/mugshot",
                          cell = 0, x = -128, y = 92, dark = 14 })
    local r = sprite(S, { key = who .. "/mugshot", cell = 0, x = 384, y = 92, dark = 14 })
    local bp = sprite(S, { key = "league_banner", anim = 1, palette = pal, x = -112, y = 96 })
    local br = sprite(S, { key = "league_banner", anim = 2, palette = pal, x = 368, y = 96 })
    local function place(px, ry)
      p.x, p.y = px, ry or 92
      r.x, r.y = 256 - px, 184 - (ry or 92)
      bp.x, bp.y = p.x + 16, p.y + 4
      br.x, br.y = r.x - 16, r.y + 4
    end
    waitFor(function() return f.done end)
    S.name = { text = T.trainerName, x = 168, y = 104, hidden = true }
    local slide = drive(S, Quad(-128, 56, 80, 6), function(v) place(v) end)
    wait(3)
    S.name.hidden = false
    local vs = vsSequence(S, 128, 96)
    waitFor(function() return slide.done and vs.done end)
    local up = Lin(0, 16, 3)
    local d
    repeat local v; v, d = up(); S.bright = v; tick() until d
    p.dark, r.dark = 0, 0
    bp.speed, br.speed = 2, 2
    local down = Lin(16, 0, 6)
    repeat local v; v, d = down(); S.bright = v; tick() until d
    wait(9)
    local jit = Quad(0, -2, 0, panFrames)
    local cnt = 0
    repeat
      local v; v, d = jit()
      local s = (floor(cnt / 2) % 2 == 0) and 1 or -1
      place(56 + s * v, 92 + s * v)
      cnt = cnt + 1
      tick()
    until d
    S.name = nil
    local w = fade(S, "bright", "white", 8)
    drive(S, Quad(0, 192, 24, 16), function(v) place(56 - v, 92 - v) end)
    waitFor(function() return w.done end)
  end
end
E.elite_four_aaron = league("elite_four_aaron", 32)
E.elite_four_bertha = league("elite_four_bertha", 32)
E.elite_four_flint = league("elite_four_flint", 32)
E.elite_four_lucian = league("elite_four_lucian", 32)
E.champion_cynthia = league("champion_cynthia", 9)

-- 25: MYTHICAL. A white flash, motion blur, sixteen camera snaps.
local MYTHICAL_SNAPS = {
  { 0x5C1, 4 }, { 0x601, 4 }, { 0x691, 4 }, { 0x711, 3 }, { 0x780, 3 }, { 0x751, 3 },
  { 0x800, 3 }, { 0x802, 3 }, { 0x800, 3 }, { 0x751, 3 }, { 0x4C1, 2 }, { 0x3C1, 2 },
  { 0x650, 1 }, { 0x241, 1 }, { 0x500, 1 }, { 0x241, 1 },
}
Gen4BattleTransition.MYTHICAL_SNAPS = MYTHICAL_SNAPS
E.mythical = function(S)
  local f = flash(S, 16, 16, 1)
  waitFor(function() return f.done end)
  S.blur = 3 / 18
  for _, snap in ipairs(MYTHICAL_SNAPS) do
    wait(snap[2] + 1)
    S.zoom = fovZoom(snap[1])
  end
  local w = fade(S, "bright", "white", 10)
  waitFor(function() return w.done end)
end

-- 26: LEGENDARY. A slow widening, a pause, a lunge, a long white.
E.legendary = function(S)
  local f = flash(S, 16, 16, 1)
  waitFor(function() return f.done end)
  S.blur = 5 / 18
  local fov = Lin(FOV0, FOV0 + 0x100, 40)
  local d
  repeat local v; v, d = fov(); S.zoom = fovZoom(v); tick() until d
  local z = S.zoom
  wait(6)
  local dist = Quad(D0, D0 - 2350, 0.5, 8)
  repeat local v; v, d = dist(); S.zoom = z * zoomFor(v); tick() until d
  local w = fade(S, "bright", "white", 60)
  waitFor(function() return w.done end)
end

-- 27: GALACTIC GRUNT. Six balls fly in from all sides to one point, shrinking.
local GRUNT_BALLS = {
  { 260, 128, -30, 0, 100, 20, 4, 2 }, { -16, 128, 30, 160, 100, -20, 3, 1 },
  { 0, 128, 30, -16, 100, 20, 4, -3 }, { 140, 128, -10, 160, 100, -20, 2, -2 },
  { 260, 128, -30, 80, 100, 1, 3, -3 }, { 0, 128, 30, 160, 100, -20, 3, 1 },
}
Gen4BattleTransition.GRUNT_BALLS = GRUNT_BALLS
E.galactic_grunt = function(S)
  local f = flash(S, -16, -16, 2)
  waitFor(function() return f.done end)
  local last
  for _, row in ipairs(GRUNT_BALLS) do
    wait(row[7] + 1)
    local b = sprite(S, { key = "trainer_low", cell = 0, x = row[1], y = row[4], scale = 2 })
    last = spawn(S, function()
      local x, y = Quad(row[1], row[2], row[3], 8), Quad(row[4], row[5], row[6], 8)
      local sc, r = Quad(2, 0.01, -0.4, 8), Lin(0, row[8] * 0xFFFF, 8)
      local d
      repeat
        local xx; xx, d = x(); b.x = xx; b.y = (y()); b.scale = (sc()); b.rot = (r())
        tick()
      until d
      b.visible = false
    end)
  end
  waitFor(function() return last.done end)
  local c = fade(S, "x", "black", 12)
  waitFor(function() return c.done end)
end

-- 28: GALACTIC BOSS. The "G" fades in, then breaks into mosaic while eight
-- black wedges close on the centre.
local WEDGES = { { 0, 23 }, { 45, 22 }, { 45, 68 }, { 90, 67 },
                 { 91, 113 }, { 135, 112 }, { 135, 158 }, { 180, 157 } }
Gen4BattleTransition.WEDGES = WEDGES
E.galactic_boss = function(S)
  local f = flash(S, 16, -16, 2)
  waitFor(function() return f.done end)
  local g = sprite(S, { key = "galactic", cell = 0, x = 128, y = 96, alpha = 0 })
  local eva = Lin(0, 16, 15)
  local d
  repeat local v; v, d = eva(); g.alpha = v / 16; tick() until d
  g.alpha = 1
  wait(16)
  S.wedges = { band = true, list = {} }
  for i, w in ipairs(WEDGES) do S.wedges.list[i] = { w[1], w[1] } end
  local mos, ang = Lin(0, 14, 16), LinF(0, 1, 16)
  repeat
    local m, a
    m, d = mos(); a = ang()
    g.mosaic = m
    for i, w in ipairs(WEDGES) do S.wedges.list[i][2] = w[1] + (w[2] - w[1]) * a end
    tick()
  until d
  blackout(S)
  g.visible = false
end

-- 29: FRONTIER. The big ball fades in, then shrinks as the circle closes.
E.frontier = function(S)
  local f = flash(S, 16, -16, 2)
  waitFor(function() return f.done end)
  local b = sprite(S, { key = "trainer_high", cell = 0, x = 128, y = 96, alpha = 0 })
  local eva = Lin(0, 16, 12)
  local d
  repeat local v; v, d = eva(); b.alpha = v / 16; tick() until d
  b.alpha = 1
  drive(S, Quad(1, 0.1, 2 / 4096, 6), function(v) b.scale = v end)
  local c = fade(S, "circle", "black", 6)
  waitFor(function() return c.done end)
end

-- 30: DOUBLE. Four balls burst outward in a cross, then the X closes.
E.double = function(S)
  local f = flash(S, 16, -16, 2)
  waitFor(function() return f.done end)
  local balls = {}
  for i = 1, 4 do balls[i] = sprite(S, { key = "trainer_low", cell = 0, x = 128, y = 96 }) end
  local d1, d2 = Quad(0, 128, 0.1, 4), Quad(0, 160, 0.1, 4)
  local d
  repeat
    local a, b
    a, d = d1(); b = d2()
    balls[1].y, balls[2].y = 96 - a, 96 + a
    balls[3].x, balls[4].x = 128 - b, 128 + b
    tick()
  until d
  local c = fade(S, "x", "black", 8)
  waitFor(function() return c.done end)
end

Gen4BattleTransition.EFFECTS = E

-- ---------------------------------------------------------------------------
-- The object.
-- ---------------------------------------------------------------------------

-- new(game, onDone, ctx) -- ctx as Gen4EncounterEffect.cutIn takes it, plus
-- trainerName and playerGender.
function Gen4BattleTransition.new(game, onDone, ctx)
  local self = setmetatable({}, Gen4BattleTransition)
  self.game, self.onDone, self.ctx = game, onDone, ctx or {}
  local Choose = require("src.world.Gen4EncounterEffect")
  self.cutIn, self.name, self.pair = Choose.cutIn(self.ctx)
  self.S = { bright = 0, other = 0, zoom = 1, sprites = {}, rects = {}, tasks = {},
             animTick = 0 }
  local script = E[self.name] or E.grass_low
  local S, T = self.S, self.ctx
  self.main = coroutine.create(function() script(S, T) end)
  self.frame = 0
  self.finished = false
  return self
end

function Gen4BattleTransition:step()
  local S = self.S
  -- SysTasks first (the flashes, the interpolations, the scrolls), then the
  -- effect's own state machine, as the field's task list orders them.
  -- (a task spawned during this pass starts on the next, as a SysTask added
  -- mid-frame does)
  local n = #S.tasks
  for i = 1, n do
    local h = S.tasks[i]
    if not h.done and not h.dead then
      local ok, err = coroutine.resume(h.co, h)
      if not ok then error(err) end
      if coroutine.status(h.co) == "dead" then h.done = true end
    end
  end
  local live = {}
  for _, h in ipairs(S.tasks) do
    if not h.done and not h.dead then live[#live + 1] = h end
  end
  S.tasks = live
  S.animTick = S.animTick + 1
  if coroutine.status(self.main) ~= "dead" then
    local ok, err = coroutine.resume(self.main)
    if not ok then error(err) end
  end
  if coroutine.status(self.main) == "dead" then self.finished = true end
end

-- Run to the end without drawing (tests, and a fallback).
function Gen4BattleTransition:runAll(limit)
  local n = 0
  while not self.finished and n < (limit or 2000) do self:step(); n = n + 1 end
  return n
end

function Gen4BattleTransition:update()
  self.frame = self.frame + 1
  if self.frame % 2 == 1 and not self.finished then self:step() end
  if self.finished then
    -- the last state's picture stays for the tick it was set on
    self.hold = (self.hold or 0) + 1
    if self.hold >= 2 then
      self.game.stack:pop()
      if self.onDone then self.onDone() end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Pictures.
-- ---------------------------------------------------------------------------

local cache = setmetatable({}, { __mode = "k" })

local function record(game)
  local data = game and game.data
  return data and data.gen4_encounter_effects
end

local function paletteNameFor(key)
  local base = key:match("^(.-)/mugshot$")
  if base then return base .. "/mugshot.NCLR" end
  base = key:match("^(.-)/banner$")
  if base then return base .. "/banner.NCLR" end
  if key == "trainer_low" or key == "trainer_high" then return ".shared/enc_trainer.NCLR" end
  if key == "galactic" then return ".shared/enc_galactic.NCLR" end
  if key == "vs" or key == "frontier_vs" then return ".shared/vs.NCLR" end
  return nil
end

local function imageFor(game, key, cell, palName, dark, mosaic)
  local rec = record(game)
  if not rec then return nil end
  local list = rec.images[key]
  local im = list and list[(cell or 0) + 1]
  if not im then return nil end
  palName = palName or paletteNameFor(key)
  local pal = palName and rec.palettes[palName]
  if not pal then return nil end
  dark, mosaic = dark or 0, mosaic or 0
  local per = cache[rec] or {}
  cache[rec] = per
  local id = table.concat({ key, cell or 0, palName, dark, mosaic }, "|")
  if per[id] then return per[id], im end
  local data = love.image.newImageData(im.w, im.h)
  local m = mosaic + 1
  local idx = im.idx
  for y = 0, im.h - 1 do
    for x = 0, im.w - 1 do
      local mx, my = x - x % m, y - y % m
      local at = (my * im.w + mx) * 2 + 1
      local v = tonumber(idx:sub(at, at + 1), 16) or 0
      if v ~= 0 then
        local c = pal[v + 1] or pal[v % 16 + 1] or { 0, 0, 0 }
        local k = (16 - dark) / 16
        data:setPixel(x, y, c[1] / 255 * k, c[2] / 255 * k, c[3] / 255 * k, 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  per[id] = img
  return img, im
end
Gen4BattleTransition.imageFor = imageFor

-- The League banner's cell at this tick, from its animation.
local function animCell(game, key, seq, t)
  local rec = record(game)
  local frames = rec and rec.anims[key] and rec.anims[key][seq]
  if not frames or #frames == 0 then return 0 end
  local total = 0
  for _, f in ipairs(frames) do total = total + math.max(1, f.duration or 1) end
  local at = t % total
  for _, f in ipairs(frames) do
    at = at - math.max(1, f.duration or 1)
    if at < 0 then return f.cell end
  end
  return frames[#frames].cell
end

-- ---------------------------------------------------------------------------
-- Drawing, in window pixels: the letterbox (ox, oy, vpw, vph) is the DS's
-- 256x192 at k window pixels each, and the field around it is more of the same
-- top screen.
-- ---------------------------------------------------------------------------

local function scratch(self, w, h, name)
  local c = self[name]
  if not c or c:getWidth() ~= w or c:getHeight() ~= h then
    if c and c.release then c:release() end
    c = love.graphics.newCanvas(w, h)
    c:setFilter("nearest", "nearest")
    self[name] = c
  end
  return c
end

-- THE FIELD, AS THE EFFECT SEES IT: the whole window's frame, zoomed about the
-- top screen's centre (where the camera's target is), with the motion blur
-- and the Elite Four's freeze-frame applied. Window-sized.
local function fieldPicture(self, source, ww, wh, cx, cy)
  local S = self.S
  local g = love.graphics
  if S.freeze and self.frozen then return self.frozen end
  local field = scratch(self, ww, wh, "fieldCanvas")
  g.push("all")
  g.setCanvas(field)
  g.origin()
  g.setScissor()
  local z = S.zoom or 1
  if S.blur and self.blurReady then
    g.setColor(1, 1, 1, S.blur)
  else
    g.clear(0, 0, 0, 1)
    g.setColor(1, 1, 1, 1)
  end
  if z < 1 then
    -- THE CAMERA PULLING BACK shows more of the field on the cartridge; a
    -- captured frame has nothing past its edges, so the frame as it was sits
    -- underneath rather than a black border appearing round a shrinking one.
    g.draw(source, 0, 0)
  end
  g.draw(source, cx, cy, 0, z, z, cx, cy)
  g.pop()
  self.blurReady = S.blur ~= nil
  if S.freeze and not self.frozen then
    -- GX_SetCapture(..., 4, 12) against cleared VRAM: a quarter-bright still.
    local still = love.graphics.newCanvas(ww, wh)
    still:setFilter("nearest", "nearest")
    g.push("all")
    g.setCanvas(still)
    g.origin()
    g.clear(0, 0, 0, 1)
    g.setColor(0.25, 0.25, 0.25, 1)
    g.draw(field, 0, 0)
    g.pop()
    self.frozen = still
    return still
  end
  return field
end

local function fillRect(x, y, w, h)
  if w > 0 and h > 0 then love.graphics.rectangle("fill", x, y, w, h) end
end

-- V is the view: the window's size, the top screen's origin (ox, oy) and k
-- window pixels per DS pixel. Everything is in DS coordinates and carried out
-- to the window's edges, which on a wide window lie outside 0..255 / 0..191.
local function dsLines(V)
  return floor(-V.oy / V.k) - 1, floor((V.wh - V.oy) / V.k) + 1
end

local function drawFade(F, V)
  local g = love.graphics
  local ox, oy, k, ww, wh = V.ox, V.oy, V.k, V.ww, V.wh
  local c = F.colour == "white" and 1 or 0
  g.setColor(c, c, c, 1)
  local t = F.k / F.steps
  local y0, y1 = dsLines(V)
  if F.kind == "bright" then
    g.setColor(c, c, c, t)
    fillRect(0, 0, ww, wh)
  elseif F.kind == "blinds" then
    -- three bands, each closing top to bottom; on a taller window the bands
    -- are thirds of the window
    local bh = wh / 3
    for band = 0, 2 do fillRect(0, band * bh, ww, math.ceil(bh * t)) end
  elseif F.kind == "circle" or F.kind == "dome" then
    local cy = F.kind == "circle" and 96 or 288
    -- the radius starts where it covers the whole window, as 256 covers the DS
    local far = 0
    for _, p in ipairs({ { -ox / k, -oy / k }, { (ww - ox) / k, -oy / k },
                         { -ox / k, (wh - oy) / k }, { (ww - ox) / k, (wh - oy) / k } }) do
      local d = math.sqrt((p[1] - 128) ^ 2 + (p[2] - cy) ^ 2)
      if d > far then far = d end
    end
    local r0 = math.max(F.kind == "circle" and 256 or 512, far)
    local r = r0 * (1 - t)
    for y = y0, y1 do
      local dy = y - cy
      local half = r * r - dy * dy
      local wy = oy + y * k
      if half <= 0 then
        fillRect(0, wy, ww, k)
      else
        local w = math.sqrt(half)
        local x0, x1 = ox + (128 - w) * k, ox + (128 + w) * k
        fillRect(0, wy, x0, k)
        fillRect(x1, wy, ww - x1, k)
      end
    end
  elseif F.kind == "box" then
    -- from the centre out to the window's own edges
    local cx, cy = ox + 128 * k, oy + 96 * k
    local l, r = cx - cx * t, cx + (ww - cx) * t
    local u, d = cy - cy * t, cy + (wh - cy) * t
    fillRect(l, u, r - l, d - u)
  elseif F.kind == "x" then
    local a = (pi / 4) * t
    local ta, tb = tan(a), tan(pi / 2 - a)
    local half = math.max(128, (ox + 128 * k) / k, (ww - ox - 128 * k) / k)
    local cx = ox + 128 * k
    for y = y0, y1 do
      local dy = abs(96 - y - (y >= 96 and 1 or 0))
      local inner = math.min(half, ta * dy)
      local outer = math.min(half, tb * dy)
      local wy = oy + y * k
      fillRect(0, wy, cx - outer * k, k)
      fillRect(cx - inner * k, wy, 2 * inner * k, k)
      fillRect(cx + outer * k, wy, ww - cx - outer * k, k)
    end
  end
end

local function drawWedges(W, V)
  local g = love.graphics
  local ox, oy, k = V.ox, V.oy, V.k
  g.setColor(0, 0, 0, 1)
  if W.band then fillRect(0, oy + 93 * k, V.ww, 7 * k) end
  local R = 4 * (V.ww + V.wh) / k
  for _, w in ipairs(W.list) do
    local a0, a1 = math.rad(w[1]), math.rad(w[2])
    if abs(a1 - a0) > 1e-6 then
      for _, sgn in ipairs({ 1, -1 }) do
        local pts = { ox + 128 * k, oy + 96 * k }
        local steps = 6
        for i = 0, steps do
          local a = a0 + (a1 - a0) * i / steps
          pts[#pts + 1] = ox + (128 - sgn * sin(a) * R) * k
          pts[#pts + 1] = oy + (96 - sgn * cos(a) * R) * k
        end
        for i = 3, #pts - 3, 2 do
          g.polygon("fill", pts[1], pts[2], pts[i], pts[i + 1], pts[i + 2], pts[i + 3])
        end
      end
    end
  end
end

-- drawScreen: the renderer's screenDraw. (ox, oy, vpw, vph) is the letterbox
-- holding the DS's 256x192; the field round it is the same top screen, so
-- every effect runs out to the window's edges.
function Gen4BattleTransition:drawScreen(prog, ww, wh, Sx, Sy, source, ox, oy, vpw, vph)
  local S = self.S
  local g = love.graphics
  ox, oy = ox or 0, oy or 0
  vpw = vpw or ww
  local k = vpw / 256
  local V = { ww = ww, wh = wh, ox = ox, oy = oy, k = k }
  g.setScissor()
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, ww, wh)

  if S.cover then
    local c = S.cover == "white" and 1 or 0
    g.setColor(c, c, c, 1)
    g.rectangle("fill", 0, 0, ww, wh)
    g.setColor(1, 1, 1, 1)
    return
  end

  if source then
    local field = fieldPicture(self, source, ww, wh, ox + 128 * k, oy + 96 * k)
    local fw, fh = field:getWidth(), field:getHeight()
    local y0, y1 = dsLines(V)
    g.setColor(1, 1, 1, 1)
    if S.slice and S.slice.x ~= 0 then
      local pps = S.slice.pps
      for band = floor(y0 / pps), floor(y1 / pps) do
        local top = band * pps
        local off = (band % 2 == 0) and S.slice.x or -S.slice.x
        local q = g.newQuad(0, oy + top * k, fw, pps * k, fw, fh)
        g.draw(field, q, -off * k, oy + top * k)
      end
    elseif S.shake then
      local sh = S.shake
      for y = y0, y1 do
        local e = (sh.pos + y) % 192
        local hofs = sin(sh.inc * e / TURN * 2 * pi) * sh.amp
        if sh.invert and floor(y / sh.invert) % 2 == 1 then hofs = -hofs end
        local q = g.newQuad(0, oy + y * k, fw, k, fw, fh)
        g.draw(field, q, -trunc(hofs) * k, oy + y * k)
      end
    elseif S.split then
      local X, Y = S.split.x, S.split.y
      if X < 255 and Y < 96 then
        local rx, by = ox + (255 - X) * k, oy + (96 - Y) * k
        g.draw(field, g.newQuad(0, 0, rx, by, fw, fh), 0, 0)
        local lx, ty = ox + X * k, oy + (96 + Y) * k
        g.draw(field, g.newQuad(lx, ty, fw - lx, fh - ty, fw, fh), lx, ty)
      end
    else
      g.draw(field, 0, 0)
    end
    if S.darkField and S.darkField > 0 then
      g.setColor(0, 0, 0, S.darkField / 16)
      g.rectangle("fill", 0, 0, ww, wh)
    end
  end

  -- BG3: the leader's banner, revealed right to left behind a zigzag edge,
  -- repeating across the window as the hardware background wraps
  local B = S.banner
  if B then
    local img, im = imageFor(self.game, B.key, 0)
    if img then
      g.setColor(1, 1, 1, 1)
      local w = im.w
      local sx = B.scroll % w
      local first = floor((-ox / k + sx) / w) - 1
      local last = floor(((ww - ox) / k + sx) / w) + 1
      for line = 0, im.h - 1 do
        local y = im.y + line
        local z = (floor(y / 8) % 2 == 0) and 2 * (y % 8) or 16 - 2 * (y % 8)
        local edge = math.max(0, B.edge - z)
        if edge < 256 then
          -- the window's left edge; everything right of it, out to the
          -- window's own right edge, shows the banner
          local wx = (edge > 0) and (ox + edge * k) or 0
          g.setScissor(wx, oy + y * k, ww - wx, k)
          local q = g.newQuad(0, line, w, 1, w, im.h)
          for tile = first, last do
            g.draw(img, q, ox + (tile * w - sx) * k, oy + y * k, 0, k, k)
          end
        end
      end
      g.setScissor()
    end
  end

  g.setColor(0, 0, 0, 1)
  for _, r in pairs(S.rects) do
    local h = r.h
    if r.toBottom then h = (wh - oy) / k - r.y end
    fillRect(ox + r.x * k, oy + r.y * k, r.w * k, h * k)
  end
  if S.wedges then drawWedges(S.wedges, V) end

  -- OBJs: the lower priority number on top, and within one priority the
  -- first made, as OAM orders them
  local order = {}
  for i = 1, #S.sprites do order[i] = S.sprites[i] end
  table.sort(order, function(a, b)
    if a.pri ~= b.pri then return a.pri > b.pri end
    return a.serial > b.serial
  end)
  for _, sp in ipairs(order) do
    if sp.visible then
      local cell = sp.cell
      if sp.anim then
        cell = animCell(self.game, sp.key, sp.anim, floor(S.animTick * (sp.speed or 1)))
      end
      local img, im = imageFor(self.game, sp.key, cell, sp.palette, sp.dark, sp.mosaic)
      if img then
        g.setColor(1, 1, 1, sp.alpha)
        local s = sp.scale * k
        g.draw(img, ox + sp.x * k, oy + sp.y * k, -sp.rot / TURN * 2 * pi, s, s,
               -im.x, -im.y)
      end
    end
  end

  -- the name, on BG2
  local N = S.name
  if N and not N.hidden and N.text then
    local Font = require("src.render.Font")
    local rec = record(self.game)
    local pal = rec and rec.palettes[".shared/enc_fade.NCLR"]
    local function c01(c) return { (c and c[1] or 255) / 255, (c and c[2] or 255) / 255,
                                   (c and c[3] or 255) / 255, 1 } end
    g.push()
    g.translate(ox + N.x * k, oy + N.y * k)
    g.scale(k, k)
    local tone = Font.beginTwoTone and Font.beginTwoTone(c01(pal and pal[2 * 16 + 2]),
                                                          c01(pal and pal[2 * 16 + 3]))
    if not tone then g.setColor(1, 1, 1, 1) end
    Font.draw(tostring(N.text), 0, 0)
    if tone then Font.endTwoTone() end
    g.pop()
  end

  if S.fade then drawFade(S.fade, V) end

  -- master brightness: the top screen is the whole window here. The bottom
  -- screen's own fade (S.other) belongs to whatever draws the bottom screen.
  if S.bright ~= 0 then
    local c = S.bright > 0 and 1 or 0
    g.setColor(c, c, c, math.min(1, abs(S.bright) / 16))
    g.rectangle("fill", 0, 0, ww, wh)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4BattleTransition:draw()
  local r = self.game and self.game.renderer
  if r then
    local me = self
    r.battleWipe = { style = "gen4_" .. tostring(self.name), prog = 0.5, t = self.frame,
                     game = self.game, needsSource = true, transition = self,
                     screenDraw = function(_, prog, ww, wh, Sx, Sy, source, ox, oy, vpw, vph)
                       me:drawScreen(prog, ww, wh, Sx, Sy, source, ox, oy, vpw, vph)
                     end }
  end
end

return Gen4BattleTransition
