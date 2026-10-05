-- Run:  texlua tools/gen4_bike_slope_check.lua <cache dir>
--
-- PLATINUM'S BIKE SLOPES, AND WHERE THE BEHAVIOUR BYTE COMES FROM.
--
-- Two reports, one missing input between them:
--
--   *"walking directly into the cave entrance still doesnt work"*
--   *"the mudslides above oreburge city that usually require a bike to get up
--    arent working properly ... cant be walked up without the right bike"*
--
-- The directional cave entrances were implemented and correct, and did
-- nothing, because the only thing that carries an outdoor map's behaviour
-- bytes is the land chunk's permission block -- and the renderer read it from
-- a binary side-car written by an IMPORT nobody had re-run. The same data has
-- been in every Gen 4 cache since the first one, under `gen4_map_permissions`.
--
-- The bike slopes were not implemented at all.

package.path = './?.lua;./?/init.lua;./tools/save-editor/?.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local SLOPE_TOP, SLOPE_BOTTOM = 0xD9, 0xDA   -- pokeplatinum enum TileBehavior
local TILES = 32

-- ================== 1. THE BEHAVIOUR BYTE, WITH NO SIDE-CAR ANYWHERE
--
-- This is the section that would have caught the first report. It drives the
-- shipping call on an install shaped exactly like the one that reported it:
-- `terrain.permissionFile` absent, no `love`, nothing but the cache.
local Ground = require('src.render.Gen4Ground')
local cacheDir = arg and arg[1]
local perms
if cacheDir and cacheDir ~= '' then
  local ok, got = pcall(function()
    return assert(loadfile(cacheDir .. '/gen4_map_permissions.lua'))()
  end)
  perms = ok and got or nil
end

if not perms then
  print('note: no cache given, skipping the real-permission section')
else
  local function groundOn(land)
    return setmetatable({
      def = {}, perms = perms,
      terrain = { chunkTiles = TILES, chunks = {} },   -- NO permissionFile
      grid = { width = 1, height = 1, land = { land } },
      offsetX = 0, offsetY = 0,
    }, { __index = Ground })
  end

  -- THE SHAPE OF THE DATA, measured rather than assumed. 666 chunks of exactly
  -- 2048 bytes is 32x32 tiles of u16; the FIRST byte is the behaviour and the
  -- second is only ever 0x00 or 0x80, the blocked flag.
  local chunks, bytes, second = 0, 0, {}
  for _, s in pairs(perms) do
    chunks = chunks + 1
    bytes = bytes + #s
    for i = 2, #s, 2 do second[s:byte(i)] = true end
  end
  check(chunks > 600, 'the cache must carry a permission block per chunk, got ' .. chunks)
  check(bytes == chunks * TILES * TILES * 2,
        ('each block must be %d bytes; got %.1f on average')
          :format(TILES * TILES * 2, bytes / math.max(chunks, 1)))
  local distinct = 0
  for _ in pairs(second) do distinct = distinct + 1 end
  check(distinct <= 2 and second[0x00] ~= nil,
        'the second byte must be the blocked flag alone, got ' .. distinct .. ' values')

  -- ...AND READ BACK THROUGH THE SHIPPING CALL. Point `permBlockFor` at the
  -- side-car again and this section fails on real data, which is the whole
  -- reason it reads the cache rather than the string.
  local NAMED = { [0x62] = true, [0x63] = true, [0x64] = true, [0x65] = true,
                  [0x67] = true, [0x6E] = true,
                  [SLOPE_TOP] = true, [SLOPE_BOTTOM] = true }
  local read, slopes, wrong = 0, 0, 0
  for land, s in pairs(perms) do
    local hits = {}
    for i = 1, #s - 1, 2 do
      local v = s:byte(i)
      if NAMED[v] then
        local cell = (i - 1) / 2
        hits[#hits + 1] = { tx = cell % TILES, ty = math.floor(cell / TILES), want = v }
      end
    end
    if #hits > 0 then
      local g = groundOn(land)
      for _, h in ipairs(hits) do
        if g:behaviourAt(h.tx, h.ty) ~= h.want then wrong = wrong + 1 end
        if h.want == SLOPE_TOP or h.want == SLOPE_BOTTOM then slopes = slopes + 1 end
        read = read + 1
      end
    end
  end
  check(read > 400,
        'the sample must be big enough to mean something, got ' .. read)
  check(wrong == 0,
        ('every behaviour must read back with no side-car; %d of %d were wrong')
          :format(wrong, read))
  -- THE CONTROL: if the region carried no slope tiles there is nothing to fix
  -- and section 3 is grading an empty rule.
  check(slopes > 0, 'Sinnoh must actually carry bike-slope tiles, found ' .. slopes)
  print(('   real permissions: %d chunks, %d named behaviour tiles, %d of them slopes')
    :format(chunks, read, slopes))
end

-- ============================== 2. WHICH TILES ARE SLOPES, AND ON WHICH GAME
local Map = require('src.world.Map')
local function fakeMap(generation, behaviour)
  return setmetatable({
    def = { generation = generation },
    cellBehaviour = function() return behaviour end,
  }, { __index = Map })
end
check(Map.gen4BikeSlopeAt(fakeMap(4, SLOPE_TOP), 0, 0) == true,
      'BIKE_SLOPE_TOP must be a slope')
check(Map.gen4BikeSlopeAt(fakeMap(4, SLOPE_BOTTOM), 0, 0) == true,
      'BIKE_SLOPE_BOTTOM must be a slope')
for _, b in ipairs({ 0x00, 0x62, 0x67, 0xD8, 0xDB, 0xFF }) do
  check(Map.gen4BikeSlopeAt(fakeMap(4, b), 0, 0) == false,
        ('0x%02X must NOT be a slope'):format(b))
end
-- These bytes mean something else on every earlier cartridge.
for _, gen in ipairs({ 1, 2, 3 }) do
  check(Map.gen4BikeSlopeAt(fakeMap(gen, SLOPE_TOP), 0, 0) == false,
        ('generation %d must not read 0xD9 as a bike slope'):format(gen))
end

-- ================================= 3. WHAT GETS YOU UP ONE
local OW = require('src.world.OverworldController')
local Collision = require('src.world.Collision')
local GameMod = require('src.core.Game')
-- Stubbed because the SUBJECT is the slope rule, not collision: a real
-- `canMove` against a stub map answers about a map that does not exist.
local realCanMove = Collision.canMove
Collision.canMove = function() return true end
GameMod.save = GameMod.save or {}

local function state(o)
  local moved = {}
  local self = setmetatable({
    map = setmetatable({ def = { generation = 4 } }, {
      __index = function(_, k)
        if k == 'gen4BikeSlopeAt' then
          return function() return o.onSlope ~= false end
        end
        return Map[k]
      end,
    }),
    player = { cellX = 5, cellY = 5, facing = o.facing or 'up',
               gen4Gear = o.gear, gen4Speed = o.speed, surfing = o.surfing },
    entities = {},
    moved = moved,
    scriptMove = function(_, _, dir) moved[#moved + 1] = dir end,
  }, { __index = OW })
  GameMod.save.onBike = o.onBike
  return self, moved
end

-- THE ONE WAY UP: cycling, fast gear, ladder full, going north.
do
  local s, moved = state({ onBike = true, gear = 1, speed = 3, facing = 'up' })
  check(s:checkGen4BikeSlope() == false,
        'the fast gear at full speed must be let up the ramp')
  check(#moved == 0, 'and must not be pushed anywhere')
  check(s.muddySlide == nil, 'and must not be left mid-slide')
end

-- ...AND EVERY OTHER WAY IS A SLIDE BACK DOWN.
local REFUSALS = {
  { why = 'on foot',                 onBike = false, gear = 1, speed = 3 },
  { why = 'in the slow gear',        onBike = true,  gear = 0, speed = 3 },
  { why = 'with no gear set at all', onBike = true,  gear = nil, speed = 3 },
  { why = 'one rung short',          onBike = true,  gear = 1, speed = 2 },
  { why = 'from a standing start',   onBike = true,  gear = 1, speed = 0 },
  { why = 'facing down',             onBike = true,  gear = 1, speed = 3, facing = 'down' },
  { why = 'facing left',             onBike = true,  gear = 1, speed = 3, facing = 'left' },
}
for _, r in ipairs(REFUSALS) do
  local s, moved = state(r)
  check(s:checkGen4BikeSlope() == true, 'the ramp must refuse a rider ' .. r.why)
  check(moved[1] == 'down', ('and push them back down (%s)'):format(r.why))
  check(s.player.gen4Speed == 0,
        ('and a failed climb must cost the run (%s)'):format(r.why))
end

-- Off a slope it must answer for nothing at all, or every tile in Sinnoh is a
-- ramp.
do
  local s, moved = state({ onSlope = false, onBike = true, gear = 1, speed = 0 })
  check(s:checkGen4BikeSlope() == false, 'ordinary ground must not be a ramp')
  check(#moved == 0, 'and must push nobody')
end
-- Surfing is not cycling.
do
  local s = state({ onBike = true, gear = 1, speed = 3, surfing = true })
  check(s:checkGen4BikeSlope() == false, 'a surfer must not meet the ramp rule')
end

-- THE THRESHOLD IS NOT HOENN'S. Hoenn asks for a speed STRICTLY above 3
-- because the Mach ladder's top rung is 4; Platinum's ladder tops out AT 3, so
-- the same comparison would make every ramp in Sinnoh impassable.
do
  local s = state({ onBike = true, gear = 1, speed = 3 })
  check(s:checkGen4BikeSlope() == false,
        'a speed of exactly 3 must be enough -- Hoenn\'s `> 3` would refuse it')
end

-- ======================================= 4. HOW THE LADDER IS EARNED
do
  local s = setmetatable({ player = {} }, { __index = OW })
  s.player.gen4Gear = 1
  for i = 1, 6 do s:gen4BankStep() end
  check(s.player.gen4Speed == 3,
        'the fast gear must bank one rung per step and cap at 3, got '
          .. tostring(s.player.gen4Speed))

  local slow = setmetatable({ player = { gen4Gear = 0 } }, { __index = OW })
  for i = 1, 6 do slow:gen4BankStep() end
  check((slow.player.gen4Speed or 0) == 0,
        'the SLOW gear must never earn a rung -- that is the whole of "the '
          .. 'right bike"; got ' .. tostring(slow.player.gen4Speed))

  -- A ramp that paid you for the push-back would hand you the climb on the
  -- second attempt.
  local sliding = setmetatable(
    { player = { gen4Gear = 1, gen4Speed = 0 }, muddySlide = true },
    { __index = OW })
  sliding:gen4BankStep()
  check(sliding.player.gen4Speed == 0,
        'the slide\'s own step must not be paid for')
end

Collision.canMove = realCanMove

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
