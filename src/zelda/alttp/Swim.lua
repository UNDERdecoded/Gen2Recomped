-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DEEP WATER AND THE FLIPPERS (round 26, team A), outdoors. The SNES
-- routines the GBA keeps (zelda3 names), the GBA's own tables (OFF):
--
--   walking in            Link_HandleCardinalCollision: the middle probe in
--                         the walking direction on deep water (0x08) while
--                         not in it: from shallow water (0x09 under Link)
--                         with the flippers (not a bunny) Link swims at once;
--                         else Link_HopInOrOutOfWater_Y/X hops him in
--                         (kRecoilVelY / Z[2] outdoors: 16 / 24 in 1/16 px,
--                         z falling 2 a frame, incapacitated 16; pose yt 5).
--   landing               Link_SplashUponLanding: deep water -> swimming,
--                         or without the flippers (or as a bunny)
--                         CheckAbilityToSwim -> Module09_2A_RecoverFromDrowning:
--                         2 px a frame back to where he stood
--                         (link_x/y_coord_cached), then countdown_for_blink
--                         0x90 -- no damage.
--   swimming              PlayerHandler_04_Swimming / Link_HandleSwimMovements
--                         / Link_SetMomentum / Link_SetTheMaxAccel /
--                         Link_HandleSwimAccels / HandleSwimStrokeAndSubpixels:
--                         per axis the speed swimcoll_var7 (1/256 px) moves
--                         by kSwimmingTab4[var5] (+8 on, -12 off, -8 turning)
--                         up to var9 (240; a stroke -- B, A or R newly
--                         pressed -- raises it by 160 to 384 or to the
--                         kSwimmingTab3 step above the speed); the stroke
--                         lasts 5 x 8 frames (link_maybe_swim_faster).
--                         Pictures (LinkOam_Main): 0x11 still (steps & 1,
--                         flipping every 16 frames), 0x13 moving (rt =
--                         kSwimmingTab1[steps], every 8), 0x12 the stroke.
--   leaving               shallow water under (x + 8, y + 20) ends it
--                         (TileDetect_MainHandler 0); the three probes ahead
--                         all on plain ground hop him out (the same hop);
--                         vertical ledges stop a swimmer.
--
-- OURS: no splash / ripple ancillae, no sounds; indoor water (the Swamp
-- Palace) is not handled here; the hop's arc uses the recoil code's z
-- model (Escape.lua); diagonal hops use the vertical rule.

local bit = require("bit")
local band, bor, bnot, rshift = bit.band, bit.bor, bit.bnot, bit.rshift
local Link = require("src.zelda.alttp.Link")

local SW = {}

SW.OFF = { tab1 = 0x167E0A, tab2 = 0x167E10, tab3 = 0x167E14, tab4 = 0x167E26, recoilY = 0x167ED0, recoilZ = 0x167ED3 }
SW.DEEP, SW.SHALLOW = 0x08, 0x09

function SW.extract(rom, R, check)
  local O = SW.OFF
  local t = { tab1 = rom:bytesU8(O.tab1, 4), tab2 = rom:bytesU16(O.tab2, 2), tab3 = rom:bytesU16(O.tab3, 9),
              tab4 = rom:bytesU16(O.tab4, 12), recoilY = rom:bytesU8(O.recoilY, 3), recoilZ = rom:bytesU8(O.recoilZ, 3) }
  for i = 1, 12 do if t.tab4[i] >= 32768 then t.tab4[i] = t.tab4[i] - 65536 end end
  check(t.tab4[1] == 8 and t.tab4[2] == -12 and t.tab4[3] == -8 and t.tab3[9] == 384 and t.tab1[1] == 2
        and t.tab2[1] == 32 and t.recoilY[3] == 16 and t.recoilZ[3] == 24, "kSwimmingTab1-4, kRecoilVelY / Z")
  return t
end

local function T(game) return game.data.t and game.data.t.swim end
local function attr(game, x, y) return game.ow:attrAt(game.link.world, x, y) end
local function hasFlippers(game) return require("src.zelda.alttp.DarkWorld").hasFlippers(game) end
local function bunny(game) return game.isBunny and game:isBunny() end

local function newSwim()
  return { v1 = { 0, 0 }, v3 = { 0, 0 }, v5 = { 0, 0 }, v7 = { 0, 0 }, v9 = { 0, 0 }, v11 = { 0, 0 },
           hard = 0, faster = 0, cd = 0, counter = 0, anim = 0, cc = 0, dirBits = 0, ldir = 0 }
end
local function resetAccel(s)
  for i = 1, 2 do s.v1[i], s.v3[i], s.v5[i], s.v7[i], s.v9[i] = 0, 0, 0, 0, 0 end
end

function SW.enter(game)
  local lk = game.link
  lk.swim = newSwim()
  lk.swimGame = game
  lk.waterHop = nil
  game.swims = (game.swims or 0) + 1
  require("src.zelda.alttp.Dash").cancel(game)
  game.swing, game.bowUse = nil, nil
  if game.dropCarry then game:dropCarry() end
end

function SW.leave(game)
  local lk = game.link
  lk.swim = nil
  lk.swimGame = nil
end

-- Link_HopInOrOutOfWater (outdoors: kRecoilVelY / Z [2])
function SW.hop(game, dx, dy, into)
  local tb = T(game)
  local lk = game.link
  lk.waterHop = { vx = dx * tb.recoilY[3], vy = dy * tb.recoilY[3], vz = tb.recoilZ[3], sx = 0, sy = 0, fz = 0,
                  t = 16, into = into }
  lk.swimGame = game
  lk.z = 0
  if into then game.waterHops = (game.waterHops or 0) + 1 end
end

-- the joypad direction bits (up 8, down 4, left 2, right 1)
local function joy(input)
  return (input.up and 8 or 0) + (input.down and 4 or 0) + (input.left and 2 or 0) + (input.right and 1 or 0)
end

-- one frame of the hop (LinkState_Recoil / Link_HandleRecoilAndTimer)
local function hopFrame(game, lk, attrFn)
  local h = lk.waterHop
  h.sx, h.sy = h.sx + h.vx, h.sy + h.vy
  local mx = (h.sx >= 0) and math.floor(h.sx / 16) or -math.floor(-h.sx / 16)
  local my = (h.sy >= 0) and math.floor(h.sy / 16) or -math.floor(-h.sy / 16)
  h.sx, h.sy = h.sx - mx * 16, h.sy - my * 16
  local O = require("src.zelda.alttp.Overworld")
  local function free(x, y)
    for _, p in ipairs({ { 1, 8 }, { 14, 8 }, { 1, 23 }, { 14, 23 } }) do
      local a = attrFn(lk.world, x + p[1], y + p[2])
      if a ~= SW.DEEP and (O.isSolid(a) or O.LEDGE[a]) then return false end
    end
    return true
  end
  if mx ~= 0 and free(lk.x + mx, lk.y) then lk.x = lk.x + mx end
  if my ~= 0 and free(lk.x, lk.y + my) then lk.y = lk.y + my end
  h.fz = h.fz + h.vz
  local mz = (h.fz >= 0) and math.floor(h.fz / 16) or -math.floor(-h.fz / 16)
  h.fz = h.fz - mz * 16
  lk.z = math.max(0, (lk.z or 0) + mz)
  h.vz = h.vz - 2
  h.t = h.t - 1
  if h.t > 0 or not ((lk.z or 0) <= 0 and h.vz < 0) then return end
  -- Link_SplashUponLanding
  lk.z = 0
  lk.waterHop = nil
  lk.swimGame = nil
  local a = attr(game, lk.x + 8, lk.y + 20)
  if a == SW.DEEP then
    if hasFlippers(game) and not bunny(game) then return SW.enter(game) end
    -- CheckAbilityToSwim -> Module09_2A_RecoverFromDrowning
    game.drowning = { x = game.safeX or lk.x, y = game.safeY or lk.y }
    game.drownings = (game.drownings or 0) + 1
  end
end

-- one frame of swimming (PlayerHandler_04_Swimming)
local function swimFrame(game, lk, input, attrFn)
  local tb = T(game)
  local s = lk.swim
  local j = joy(input)
  if not hasFlippers(game) then return end
  -- the strokes' animation
  if s.v7[1] == 0 and s.v7[2] == 0 then
    if s.v5[1] ~= 2 and s.v5[2] ~= 2 then resetAccel(s) end
    s.anim = band(s.anim, 1)
    s.counter = s.counter + 1
    if s.counter >= 16 then s.counter = 0; s.cc = 0; s.anim = bit.bxor(band(s.anim, 1), 1) end
  else
    s.counter = s.counter + 1
    if s.counter >= 8 then s.counter = 0; s.anim = band(s.anim + 1, 3); s.cc = tb.tab1[s.anim + 1] end
  end
  local function accels()
    -- Link_HandleSwimAccels
    local mask = 12
    for i = 1, 2 do
      if band(j, mask) ~= 0 then
        if s.v7[i] ~= 0 and s.v9[i] >= 384 then
          local t
          for k = 1, 9 do t = tb.tab3[k]; if t >= s.v7[i] then break end end
          s.v9[i] = t
        else
          local t = s.v9[i]
          if t ~= 0 then s.v9[i] = math.min(384, t + 160) else s.v7[i] = 1; s.v9[i] = 240 end
        end
      end
      mask = rshift(mask, 2)
    end
  end
  local skip = false
  if s.hard == 0 then
    if (s.v7[1] == 0 and s.v7[2] == 0) or not input.stroke then
      skip = true
    else
      s.hard, s.faster, s.cd = 1, 1, 7
      accels()
      game.swimStrokes = (game.swimStrokes or 0) + 1
    end
  end
  if not skip then
    s.cd = s.cd - 1
    if s.cd < 0 then
      s.cd = 7
      s.faster = s.faster + 1
      if s.faster == 5 then s.faster = 0; s.hard = 0 end
    end
  end
  -- Link_HandleSwimMovements
  if j ~= 0 then
    if j ~= s.dirBits then s.dirBits = j; lk.subX, lk.subY = 0, 0 end
    -- Link_SetMomentum (link_flag_moving 0)
    local mask, bitv = 12, 8
    for i = 1, 2 do
      if band(j, mask) ~= 0 then
        s.v3[i] = 32
        if band(bor(s.dirBits, s.ldir), mask) == mask then
          s.v5[i] = 2
        else
          s.v11[i] = (band(j, bitv) ~= 0) and 0 or 1
          s.v5[i] = 0
        end
        if s.v9[i] == 0 then s.v9[i] = 240 end
      end
      mask, bitv = rshift(mask, 2), rshift(bitv, 2)
    end
    -- Link_SetTheMaxAccel
    if s.hard == 0 then
      mask = 12
      for i = 1, 2 do
        if band(j, mask) ~= 0 and s.v5[i] ~= 2 then
          if s.v1[i] ~= 0 or (s.v7[i] >= 240 and s.v7[i] >= s.v9[i]) then
            s.v5[i] = 0
            if s.v7[i] >= 240 then s.v1[i], s.v5[i] = 1, 1 else s.v9[i], s.v1[i] = 240, 0 end
          end
        else
          s.v9[i], s.v1[i] = 240, 0
        end
        mask = rshift(mask, 2)
      end
    end
    -- the facing follows the held direction
    if band(j, 8) ~= 0 then lk.facing = Link.UP elseif band(j, 4) ~= 0 then lk.facing = Link.DOWN
    elseif band(j, 2) ~= 0 then lk.facing = Link.LEFT elseif band(j, 1) ~= 0 then lk.facing = Link.RIGHT end
  end
  -- HandleSwimStrokeAndSubpixels
  local S = { 0, 0 }
  local clear = { bnot(0xC), bnot(3) }
  local setb = { [0] = 8, 4, 2, 1 }
  for i = 2, 1, -1 do
    s.v3[i] = s.v3[i] - 1
    if s.v3[i] < 0 then s.v3[i] = 0; s.v5[i] = 1 end
    local sum = s.v7[i] + (tb.tab4[s.v5[i] + 1] or 0)
    if sum <= 0 then
      s.ldir = band(s.ldir, clear[i])
      if s.v5[i] == 2 then s.v5[i], s.v9[i], s.v7[i] = 0, 240, 2
      else s.v5[i], s.v9[i], s.v7[i] = 0, 0, 0 end
    else
      s.ldir = bor(s.ldir, setb[s.v11[i] + (i - 1) * 2])
      if sum >= s.v9[i] then sum = s.v9[i] end
      s.v7[i] = sum
    end
    S[i] = s.v7[i]
    if s.v11[i] == 0 then S[i] = -S[i] end
  end
  -- Player_SomethingWithVelocity_TiredOrSwim: 8.8 fixed point, then the walls
  local O = require("src.zelda.alttp.Overworld")
  local function blockedDir(dir, x, y)
    local hit, all = false, true
    for _, p in ipairs(Link.PROBES[dir]) do
      local a = attrFn(lk.world, x + p[1], y + p[2])
      if a == SW.DEEP or a == SW.SHALLOW then all = false
      elseif O.isSolid(a) or O.LEDGE[a] then hit = true; all = false end
    end
    return hit, all
  end
  local function axis(key, subKey, vel, negDir, posDir, dx, dy)
    if vel == 0 then return end
    local tmp = lk[subKey] + vel + lk[key] * 256
    local nv = math.floor(tmp / 256)
    local nsub = tmp % 256
    local dir = vel < 0 and negDir or posDir
    local nx, ny = lk.x, lk.y
    if key == "x" then nx = nv else ny = nv end
    local hit, land = blockedDir(dir, nx, ny)
    if hit then lk[subKey] = 0; return end
    if land then
      -- all three ahead on plain ground: hop out
      local sx, sy = (dir == Link.LEFT and -1 or dir == Link.RIGHT and 1 or 0), (dir == Link.UP and -1 or dir == Link.DOWN and 1 or 0)
      SW.leave(game)
      game.swimExits = (game.swimExits or 0) + 1
      return SW.hop(game, sx, sy, false)
    end
    lk[key], lk[subKey] = nv, nsub
  end
  axis("x", "subX", S[2], Link.LEFT, Link.RIGHT)
  if lk.swim then axis("y", "subY", S[1], Link.UP, Link.DOWN) end
  lk.moving = (s.v7[1] ~= 0 or s.v7[2] ~= 0)
  -- shallow water under Link ends the swim
  if lk.swim and attr(game, lk.x + 8, lk.y + 20) == SW.SHALLOW then
    SW.leave(game)
    game.swimExits = (game.swimExits or 0) + 1
  end
end

-- the walk into deep water (before Link's own walk)
local function tryEnter(game, lk, input, attrFn)
  local dx = (input.right and 1 or 0) - (input.left and 1 or 0)
  local dy = (input.down and 1 or 0) - (input.up and 1 or 0)
  local dir
  if dy ~= 0 then dir = dy < 0 and Link.UP or Link.DOWN
  elseif dx ~= 0 then dir = dx < 0 and Link.LEFT or Link.RIGHT end
  if not dir then return false end
  local p = Link.PROBES[dir][2]
  local nx, ny = lk.x + ((dir == Link.LEFT) and -1 or (dir == Link.RIGHT) and 1 or 0),
                 lk.y + ((dir == Link.UP) and -1 or (dir == Link.DOWN) and 1 or 0)
  if attrFn(lk.world, nx + p[1], ny + p[2]) ~= SW.DEEP then return false end
  lk.facing = dir
  if attr(game, lk.x + 8, lk.y + 20) == SW.SHALLOW and hasFlippers(game) and not bunny(game) then
    lk.x, lk.y = nx, ny
    SW.enter(game)
    return true
  end
  local sx, sy = (dir == Link.LEFT and -1 or dir == Link.RIGHT and 1 or 0), (dir == Link.UP and -1 or dir == Link.DOWN and 1 or 0)
  game.safeX, game.safeY = lk.x, lk.y            -- link_x / y_coord_cached
  SW.hop(game, sx, sy, true)
  return true
end

function SW.install(G)
  local L0 = Link.update
  function Link:update(input, attrFn)
    local game = self.swimGame
    if game and self.waterHop then return hopFrame(game, self, attrFn) end
    if game and self.swim then return swimFrame(game, self, input, attrFn) end
    local g = self.owGame
    if g and g.state == "play" and not self.hop and T(g) and not g.dash and tryEnter(g, self, input, attrFn) then return end
    return L0(self, input, attrFn)
  end

  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    local lk = self.link
    lk.owGame = self
    -- Module09_2A_RecoverFromDrowning: 2 px a frame back to land
    local d = self.drowning
    if d then
      local function step(v, to) if v == to then return v end local s = v < to and 1 or -1; v = v + s; if v ~= to then v = v + s end return v end
      lk.x, lk.y = step(lk.x, d.x), step(lk.y, d.y)
      lk.moving, lk.steps = false, 0
      if lk.x == d.x and lk.y == d.y then self.drowning = nil; self.blink = 0x90 end
      return true
    end
    if lk.swim or lk.waterHop then
      -- no sword, items or actions in the water (button masks cleared)
      inp.stroke = inp.a or inp.b or inp.y
      inp.a, inp.b, inp.y = false, false, false
      if self.swing then self.swing = nil end
    end
    return owFrame(self, inp)
  end

  local pose0 = G.linkPose
  function G:linkPose()
    local lk = self.link
    if lk.waterHop and lk.waterHop.into ~= nil then return 5, 0 end
    local s = lk.swim
    if s then
      if s.faster ~= 0 then return 0x12, s.faster - 1 end
      if lk.moving or s.v7[1] ~= 0 or s.v7[2] ~= 0 then return 0x13, s.cc end
      return 0x11, band(s.anim, 1)
    end
    return pose0(self)
  end

  -- a room or another world ends the swim
  local enter0 = G.enterRoom
  function G:enterRoom(e)
    SW.leave(self); self.link.waterHop = nil; self.drowning = nil
    return enter0(self, e)
  end
end

return SW
