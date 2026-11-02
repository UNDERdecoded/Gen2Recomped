-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- PLATINUM'S UNDERGROUND TOP SCREEN, single player: the map of the passages
-- with the player, the Secret Base and the radar's blips (pokeplatinum
-- src/underground/top_screen.c, manager.c 888-1003, mining.c 1033-1092 and
-- 2921-3118, spheres.c 522-582, traps.c 2709-2836).
--
-- READ FROM CODE:
--   * a marker sits at (60 + mx * 138 / 448, 9 + mz * 128 / 416), mx = x - 32,
--     mz = z - 64 (top_screen.c 3-9, 293-306; underground/defs.h 23-30), and
--     nothing is drawn for a point in a Secret Base or outside the passages
--     (UndergroundMan_AreCoordinatesInSecretBase, manager.c 888-896);
--   * the player: MARKER_ANIM_CURRENT_PLAYER, kept 60 frames after they go
--     into a base (FetchPlayerPositions 262-292);
--   * the base: index 16, MARKER_ANIM_SECRET_BASE at the entrance while the
--     base is active (manager.c 916-976);
--   * the radar (manager.c 980-1003): NORMAL on arrival and whenever a menu
--     or a PC radar closes outside a closed base, none inside one;
--       NORMAL: standing still, frames 20..27 of stillness each fill blip
--       0..7 with a random mining spot within 80 tiles (or nothing), kept
--       until overwritten (mining.c 3078-3118, 1033-1092);
--       SPHERE: a window of 16 of the 100 buried-sphere slots starting at
--       timer / 2, the timer 0..100 from 100 (spheres.c 522-582);
--       TRAP: 16 of 80 results (own placed + spawned traps, one a frame)
--       from timer / 2, the timer 0..160 (traps.c 2709-2836);
--       TREASURE: 16 of 83 results (every third mining spot, one a frame)
--       from the timer, 0..83 from 73 (mining.c 2939-3036);
--     each timer's wrap plays SEQ_SE_PL_UG_006;
--   * a marker's animation restarts only when its animation changes
--     (DrawRadarAndBaseMarkers 331-361); the sequences loop.
-- The pictures are gen4_ug_top_art's (src/import/Gen4UgTopArt.lua).
-- INFERRED: the field-message log the cartridge prints on this screen (other
-- players digging, trapped, ...) is not drawn -- single player queues none of
-- its own; a cache without the art draws plain dots.

local M = {}

M.MAP_X, M.MAP_Y, M.MAP_W, M.MAP_H = 60, 9, 138, 128
M.AREA_X, M.AREA_Z = 32, 64
M.AREA_W, M.AREA_D = 479 - 32, 479 - 64
M.ANIM = { link = 0, player = 1, base = 3, sphere = 9, trap = 11, spot = 12 }
M.NORMAL_BLIPS, M.BLIPS = 8, 16

local function W() return require("src.world.Gen4UgWorld") end
local function B() return require("src.world.Gen4UgBase") end

local function se(game, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, game.data, name) end
end

-- UndergroundMan_AreCoordinatesInSecretBase: also anything out of bounds
function M.inBase(x, z)
  return not (x > M.AREA_X and z > M.AREA_Z and x < 479 and z < 479)
end

function M.state(game)
  game.ugTop = game.ugTop or { radar = "normal", t = 0, sub = 0, normal = {}, normalTimer = 0,
                               player = { x = 0, z = 0, life = 0 }, blip = {} }
  return game.ugTop
end

-- the PC's radars and the plain one (UndergroundMan_Set*RadarActive)
function M.setRadar(game, kind)
  local st = M.state(game)
  st.radar = kind
  st.results, st.resultIndex = nil, 0
  if kind == "sphere" then st.timer = 100
  elseif kind == "trap" then st.timer = 0; st.results = {}
  elseif kind == "treasure" then st.timer = 83 - 10; st.results = {}
  else st.timer = 0 end
end

-- the source lists the PC radars read
local function trapSources(save)
  local out = {}
  for _, t in ipairs(W().placedTraps(save)) do out[#out + 1] = { t.x, t.z } end
  for _, t in ipairs(W().spawnedTraps(save)) do out[#out + 1] = { t.x, t.z } end
  return out
end
local function treasureSources(save)
  local out = {}
  for i, s in ipairs((save.underground or {}).spots or {}) do
    if (i - 1) % 3 == 0 then out[#out + 1] = { s.x, s.z } end
  end
  return out
end

-- Mining_GetRandomNearbyMiningSpotIndex (its bounds' bugs kept)
function M.nearbySpot(save, x, z, rand)
  if M.inBase(x, z) then return nil end
  local minZ, maxZ, minX, maxX = z - 80, z + 80, x - 80, x + 80
  if minX < 64 then minX = 64 end
  if maxX > 479 + 33 then maxX = 479 + 33 end
  if minZ < 32 then minZ = 32 end
  if maxZ > 479 + 1 then maxZ = 479 + 1 end
  local spots = (save.underground or {}).spots or {}
  local inRange = {}
  for _, s in ipairs(spots) do
    if not (s.z < minZ or s.z > maxZ) and s.x > minX and s.x < maxX then inRange[#inRange + 1] = s end
  end
  if #inRange == 0 then return nil end
  return inRange[(rand or function(n) return math.random(0, n - 1) end)(#inRange) + 1]
end

-- one field frame (30 Hz)
local function fieldFrame(game, ow, st)
  local save = game.save
  local p = ow and ow.player
  st.t = st.t + 1
  -- the player's marker
  if p then
    if not M.inBase(p.cellX, p.cellY) then
      st.player.x, st.player.z, st.player.life = p.cellX - M.AREA_X, p.cellY - M.AREA_Z, 60
    elseif st.player.life > 0 and st.player.x >= 0 then
      st.player.life = st.player.life - 1
    end
  end
  local kind = st.radar
  if kind == "normal" then
    -- CommPlayer_GetMovementTimer: any step (or a warp) starts the count again
    local cell = p and (p.cellX .. "," .. p.cellY)
    if p and (p.moving or cell ~= st.normalCell) then
      st.normalTimer = 0
      st.normalCell = cell
    elseif p and st.normalTimer < 28 then
      st.normalTimer = st.normalTimer + 1
      if st.normalTimer >= 20 then
        local s = M.nearbySpot(save, p.cellX, p.cellY)
        st.normal[st.normalTimer - 20 + 1] = s and { s.x, s.z } or { 0, 0 }
      end
    end
  elseif kind == "sphere" then
    st.timer = st.timer + 1
    if st.timer > 100 then se(game, "SEQ_SE_PL_UG_006"); st.timer = 0 end
  elseif kind == "trap" then
    local src = trapSources(save)
    if #src > 0 then
      st.resultIndex = (st.resultIndex or 0) % #src + 1
      st.results[(#st.results % 80) + 1] = src[st.resultIndex]
    end
    st.timer = st.timer + 1
    if st.timer > 160 then se(game, "SEQ_SE_PL_UG_006"); st.timer = 0 end
  elseif kind == "treasure" then
    local src = treasureSources(save)
    if #src > 0 and #st.results < 83 then
      st.resultIndex = (st.resultIndex or 0) % #src + 1
      st.results[#st.results + 1] = src[st.resultIndex]
    end
    st.timer = st.timer + 1
    if st.timer > 83 then se(game, "SEQ_SE_PL_UG_006"); st.timer = 0 end
  end
end

-- called once per engine tick while the Underground is up: by the field, and
-- by the PC's radar while it covers the field (never both in one tick)
function M.tick(game, ow)
  local st = M.state(game)
  st.sub = (st.sub or 0) + 1
  if st.sub % 2 == 0 then fieldFrame(game, ow, st) end
end

-- the radar item i (0-based) -> x, z, anim (UndergroundMan_GetRadarItem*)
function M.item(game, i)
  local st = M.state(game)
  local save = game.save
  if i >= M.BLIPS then
    local b = B().base(save)
    if b and b.active and b.entranceX then return b.entranceX, b.entranceZ, M.ANIM.base end
    return 0, 0, 0
  end
  local kind = st.radar
  if kind == "normal" then
    if i < M.NORMAL_BLIPS then
      local r = st.normal[i + 1]
      return r and r[1] or 0, r and r[2] or 0, M.ANIM.spot
    end
    return 0, 0, M.ANIM.sphere
  elseif kind == "sphere" then
    local buried = W().buried(save)
    local idx = (math.floor(st.timer / 2) + i) % 100
    local b = buried[idx + 1]
    return b and b.x or 0, b and b.z or 0, M.ANIM.sphere
  elseif kind == "trap" then
    local idx = (math.floor(st.timer / 2) + i) % 80
    local r = st.results and st.results[idx + 1]
    return r and r[1] or 0, r and r[2] or 0, M.ANIM.trap
  elseif kind == "treasure" then
    local idx = (st.timer + i) % 83
    local r = st.results and st.results[idx + 1]
    return r and r[1] or 0, r and r[2] or 0, M.ANIM.spot
  end
  return 0, 0, 0
end

function M.screenPos(mx, mz)
  return M.MAP_X + math.floor(mx * M.MAP_W / (M.AREA_W + 1)),
         M.MAP_Y + math.floor(mz * M.MAP_H / (M.AREA_D + 1))
end

-- ------------------------------------------------------------------ draw --

local images = {}
local function image(game, rec)
  if not (rec and rec.path) then return nil end
  if images[rec.path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, rec.path)
    images[rec.path] = ok and img or false
    if images[rec.path] then images[rec.path]:setFilter("nearest", "nearest") end
  end
  return images[rec.path] or nil
end

local function art(game) return game and game.data and game.data.gen4_ug_top_art end

-- the frame of sequence `seq` `age` field frames in, looped
local function frameOf(a, seq, age)
  local frames = a and a.sequences and a.sequences[seq]
  if not frames or #frames == 0 then return nil end
  local total = 0
  for _, f in ipairs(frames) do total = total + math.max(1, f.duration or 1) end
  local at = age % total
  for _, f in ipairs(frames) do
    at = at - math.max(1, f.duration or 1)
    if at < 0 then return a.sprites[f.key] end
  end
  return a.sprites[frames[#frames].key]
end

local DOT = { [1] = { 1, 0.5, 0.2 }, [3] = { 1, 0.2, 0.2 }, [9] = { 0.4, 0.8, 1 }, [11] = { 1, 0.9, 0.3 }, [12] = { 1, 0.6, 0.2 } }

local function marker(game, a, seq, age, sx, sy)
  local g = love.graphics
  local rec = frameOf(a, seq, age)
  local img = rec and image(game, rec)
  if img then
    g.setColor(1, 1, 1, 1)
    g.draw(img, sx + (rec.originX or -8), sy + (rec.originY or -8))
  else
    local c = DOT[seq] or { 1, 1, 1 }
    g.setColor(c[1], c[2], c[3], 1)
    g.rectangle("fill", sx - 1, sy - 1, 3, 3)
    g.setColor(1, 1, 1, 1)
  end
end

-- the 256 x 192 screen at (ox, oy)
function M.draw(game, ox, oy)
  local g = love.graphics
  ox, oy = ox or 0, oy or 0
  local st = M.state(game)
  local a = art(game)
  local bg = a and a.background and image(game, a.background)
  g.push()
  g.translate(ox, oy)
  if bg then
    -- the backdrop under BG0's transparent cells (INFERRED: black)
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(1, 1, 1, 1)
    M.quad = M.quad or love.graphics.newQuad(0, 0, 256, 192, bg:getWidth(), bg:getHeight())
    g.draw(bg, M.quad, 0, 0)
  else
    g.setColor(0.36, 0.45, 0.30, 1); g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(0.75, 0.78, 0.6, 1); g.rectangle("fill", M.MAP_X, M.MAP_Y, M.MAP_W, M.MAP_H)
  end
  st.blip = st.blip or {}
  for i = 0, M.BLIPS do
    local x, z, anim = M.item(game, i)
    local b = st.blip[i] or {}
    st.blip[i] = b
    local mx, mz = 0, 0
    if not M.inBase(x, z) then mx, mz = x - M.AREA_X, z - M.AREA_Z else anim = 0 end
    if anim ~= b.anim then b.anim = anim; b.start = st.t end
    if mx ~= 0 and anim ~= 0 then
      local sx, sy = M.screenPos(mx, mz)
      marker(game, a, anim, st.t - (b.start or 0), sx, sy)
    end
  end
  if st.player.life > 0 then
    local sx, sy = M.screenPos(st.player.x, st.player.z)
    marker(game, a, M.ANIM.player, st.t, sx, sy)
  end
  g.pop()
  g.setColor(1, 1, 1, 1)
end

-- is there another screen showing it (a device panel, or both screens in one
-- window)? With one screen the PC's radar shows it in the field's place.
function M.onOtherScreen(game)
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  if not ok then return false end
  local okM, mode = pcall(SS.mode, game)
  local okC, combined = pcall(SS.combined, game)
  return (okM and mode == "display") or (okC and combined) or false
end

-- is the Underground's top screen what the other screen shows now?
function M.active(game)
  local ow = game and game.overworld
  if not (ow and ow.map) then return false end
  local okU, UG = pcall(require, "src.world.Gen4Underground")
  return okU and UG.isUnderground(ow) and true or false
end

return M
