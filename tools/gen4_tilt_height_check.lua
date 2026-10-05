-- Run:  texlua tools/gen4_tilt_height_check.lua
--
-- THE TILT LADDER, AND WHAT A TILE WITH NO PLATE IS WORTH.
--
-- Three reports, two faults:
--
--   *"the tilted camera seems to be stretching things again"*
--   *"the player seems to fall beneath raised terrain not walking up with it"*
--   *"i cant walk through some cave entrances on raised terrain ... to go
--    through i have to walk into the warp at a weird angle"*
--
-- The last two are one fault seen twice -- once as a picture and once as
-- collision.

package.path = './?.lua;./?/init.lua;./tools/save-editor/?.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end
local function near(a, b, eps)
  return type(a) == 'number' and math.abs(a - b) <= (eps or 1e-9)
end

local Camera = require('src.render.Gen4Camera')

-- ======================================== 1. a rung is an ANGLE, not a stretch
--
-- `heightPitch` is what `scales()` reads as `cot(heightPitch)` to decide how
-- tall to draw whatever stands on the ground. A rung that writes it does not
-- tilt the camera -- it stretches every tree, sign and building in the world,
-- which is exactly what was reported, twice, a fix apart.
local DEF = { cameraType = 0 }
Camera.chosen = 1
Camera.externalTilt = nil
local base = Camera.forMap(DEF)
check(type(base) == 'table', 'the cartridge rung must answer a config')
local baseGround, baseHeight = Camera.scales(base)

-- Every numeric rung, against the cartridge's own height scale.
local RUNGS = {}
for i, rung in ipairs(Camera.TILTS) do
  if tonumber(rung) then RUNGS[#RUNGS + 1] = { i = i, pitch = tonumber(rung) } end
end
-- SEVEN: 78, 72, 66, 60, 53, 47, 41 -- the cartridge's own pitch range, which
-- section 4 grades. Counted from the ladder rather than asserted at a number I
-- guessed, but pinned so that losing a rung is a failure rather than a quietly
-- shorter loop. The COUNT is what `save.options.gen4CameraTilt` indexes into,
-- so it is the part that may not drift even when the angles do.
check(#RUNGS == 7, 'the ladder must still have its seven numeric rungs, got ' .. #RUNGS)

for _, r in ipairs(RUNGS) do
  Camera.chosen = r.i
  local cfg = Camera.forMap(DEF)
  local _, height = Camera.scales(cfg)
  check(near(height, baseHeight, 1e-9),
        ('rung %d must draw heights exactly as the cartridge does -- a rung '
         .. 'that changes the height scale is stretching, not tilting; '
         .. 'cartridge %.6f, rung %.6f'):format(r.pitch, baseHeight, height))
  -- ...AND THE GROUND PLANE IS UNTOUCHED TOO, which is the containment that
  -- lets every pick, sprite and tile-row answer stay as it was.
  local ground = Camera.scales(cfg)
  check(near(ground, baseGround, 1e-9),
        ('rung %d must leave the ground plane alone'):format(r.pitch))
end

-- ...BUT THE ANGLE MUST STILL ARRIVE. Removing the stretch without giving the
-- angle another way through would flatten the ladder instead: every rung the
-- same picture, which is the failure the stretch was hiding.
for _, r in ipairs(RUNGS) do
  Camera.chosen = r.i
  local cfg = Camera.forMap(DEF)
  check(cfg.rungPitch == r.pitch,
        ('rung %d must carry its own angle in `rungPitch`, got %s')
          :format(r.pitch, tostring(cfg.rungPitch)))
  check(Camera.mode() == 'field3d',
        ('rung %d must select a real camera'):format(r.pitch))
end

-- The cartridge rung names no angle of its own and keeps the oblique pass.
Camera.chosen = 1
local cart = Camera.forMap(DEF)
check(cart.rungPitch == nil, 'the cartridge rung must name no rung angle')
check(Camera.mode() == nil, 'and must keep the oblique pass')

-- The free rungs are not angles and must not invent one.
for i, rung in ipairs(Camera.TILTS) do
  if rung == 'third' or rung == 'first' then
    Camera.chosen = i
    local cfg = Camera.forMap(DEF)
    check(cfg.rungPitch == nil, rung .. ' must name no rung angle')
    local _, h = Camera.scales(cfg)
    check(near(h, baseHeight, 1e-9), rung .. ' must not stretch either')
  end
end
Camera.chosen = 1

-- AND THE GROUND MUST READ THE NEW FIELD. A rung angle nothing consumes is the
-- flattened ladder with extra steps.
local gsrc = io.open('src/render/Gen4Ground.lua'):read('a')
check(gsrc:match('self%.camera%.rungPitch'),
      'applyCamera must hand the rung angle to the 3D view')
check(gsrc:find('useConfig', 1, true), 'through useConfig')

-- ================================ 2. a tile with no plate is not a hole
--
-- `heightsAt` states it: *"Empty means no plate, which is the chunk's base
-- rather than a hole"*. `heightAt` turned that into 0 -- the bottom of the
-- world -- so a character standing on an unplated tile beside raised ground
-- dropped out of it, and a step onto that tile from raised ground became a
-- step down a cliff.
--
-- MEASURED over all 666 chunks: 161,182 of 681,984 tiles (23.6%) carry no
-- plate. 148,799 of those have no plated neighbour either and are void -- 0 is
-- free there. The 12,383 that DO sit beside plated ground are the ones that
-- bite, and 7,778 of those neighbours are at a non-zero height.
local Ground = require('src.render.Gen4Ground')

-- DRIVEN THROUGH THE REAL `heightsAt`, with no stub of it and none of
-- `heightAt`. The plates are supplied as editor height overrides, which
-- `heightsAt` consults first and answers as a one-entry list -- the same shape
-- a BDHC plate produces. A fake `heightsAt` would be this check grading its
-- own mirror, which is how the last harness here missed a real fault.
local function groundWith(plated)
  local edits = {}
  for _, p in ipairs(plated) do
    edits[p[1] .. ',' .. p[2]] = p[3]
  end
  return setmetatable({
    def = { gen4HeightEdits = edits },
    -- `chunks` present and empty so the BDHC fall-through finds no chunk and
    -- answers {} rather than raising -- an unplated tile, which is the case
    -- under test.
    terrain = { chunkTiles = 32, tileUnits = 16, chunkUnits = 512, chunks = {} },
    grid = { width = 4, height = 4, land = { 1, 2, 3, 4, 5, 6, 7, 8,
                                             9, 10, 11, 12, 13, 14, 15, 16 } },
    offsetX = 0, offsetY = 0,
  }, { __index = Ground })
end

-- A doorway tile with no plate, with raised ground to its west.
local g = groundWith({ { 4, 4, 48 } })
check(Ground.heightAt(g, 4, 4) == 48, 'a plated tile answers its own height')
check(Ground.heightAt(g, 5, 4) == 48,
      'an unplated tile beside raised ground must take that ground rather '
      .. 'than dropping to 0 -- got ' .. tostring(Ground.heightAt(g, 5, 4)))
check(Ground.heightAt(g, 3, 4) == 48, 'from either side')
check(Ground.heightAt(g, 4, 5) == 48, 'and from north or south')

-- THE HIGHEST neighbour, not the first one found: a threshold between a raised
-- floor and the void takes the floor.
local g2 = groundWith({ { 9, 9, 16 }, { 11, 9, 96 } })
check(Ground.heightAt(g2, 10, 9) == 96,
      'the highest plated neighbour wins, got ' .. tostring(Ground.heightAt(g2, 10, 9)))

-- VOID STAYS VOID. Two tiles out from anything plated must still answer the
-- default -- otherwise this fallback would quietly raise the whole map and
-- every unreachable tile would read as standable ground.
check(Ground.heightAt(g, 7, 7) == Ground.DEFAULT_HEIGHT,
      'a tile with no plated neighbour must keep the default, got '
      .. tostring(Ground.heightAt(g, 7, 7)))
check(Ground.heightAt(groundWith({}), 2, 2) == Ground.DEFAULT_HEIGHT,
      'and a map with no plates at all must not raise')

-- ONE RING, NO RECURSION. A neighbour is asked with `heightsAt`, never with
-- `heightAt` -- otherwise an unplated region walks the chunk looking for
-- ground, at a cost per tile that grows with the size of the hole, every frame
-- the player moves.
-- ANCHORED ON THE SIGNATURE, not the name: `heightAt` is a PREFIX of
-- `heightAtPixel`, so a pattern on the bare name matches whichever comes first
-- in the file. It matched the wrong function the moment the pixel sampler was
-- added, and reported the recursion rule broken by a call that is not one.
local src = gsrc:match('function Gen4Ground:heightAt%(tileX, tileY%).-\nend')
check(src, 'heightAt must be findable')
if src then
  check(not src:find('self:heightAt', 1, true),
        'heightAt must not call itself -- one ring, no recursion')
  check(src:find('self:heightsAt', 1, true), 'it asks neighbours with heightsAt')
end

-- The list is still returned as the second answer, and it is still the TILE'S
-- OWN list: a caller picking the surface nearest its own height -- the walker
-- under a bridge -- must not be handed a neighbour's plates as if they were
-- under its feet.
local _, list = Ground.heightAt(g, 5, 4)
check(type(list) == 'table' and #list == 0,
      'the returned list must stay the tile\'s own, empty when it has no plate')
local h2, list2 = Ground.heightAt(g, 4, 4)
check(h2 == 48 and #list2 == 1, 'and a plated tile still returns its own list')

-- ================== 3. a slope is walked UP, not stepped up at its boundary
--
-- Reported twice: *"the player seems to fall beneath raised terrain not walking
-- up with it"* -- at a tilt rung, and then at the CARTRIDGE rung too, which is
-- what ruled the camera out and pointed here.
--
-- `heightsAt` asks the BDHC at the TILE'S CENTRE, so it answers one height for
-- the whole tile. A BDHC plate is a PLANE -- `y = -(nx*x + nz*z + c) / ny` --
-- and the mesh drawn from it rises continuously, so a character placed by the
-- tile centre is below the ground they are on for most of every step across a
-- sloped tile, then jumps at the boundary. 11.2% of the cartridge's 8,974
-- plates are sloped, and they are every ramp and hill path in Sinnoh.
--
-- DRIVEN THROUGH THE REAL `Gen4Bdhc`. The plate below is built by hand so the
-- slope is known exactly, but every piece of arithmetic under test -- the plane
-- evaluation, the chunk lookup, the offset -- is the shipping code's.
local Bdhc = require('src.import.Gen4Bdhc')
check(type(Bdhc.heightOn) == 'function', 'the BDHC must evaluate a plate plane')

-- A single plate covering one chunk, rising 1 unit per unit of z.
-- normal (0, 1, -1) with constant 0 gives y = -(0*x + -1*z + 0) / 1 = z.
-- INDICES ARE 0-BASED and the plate's fields are `normal` and `constant` --
-- taken from `plateBox`/`heightOn` rather than guessed. A fixture with the
-- wrong field names makes `plateBox` answer nil, every lookup miss, and the
-- assertions below pass or fail for reasons that have nothing to do with the
-- code under test.
local SLOPE = {
  points = { { x = -256, z = -256 }, { x = 256, z = 256 } },
  normals = { { x = 0, y = 1, z = -1 } },
  constants = { 0 },
  plates = { { first = 0, second = 1, normal = 0, constant = 0 } },
  strips = {}, access = {},
}
local probe = Bdhc.heightsAt(SLOPE, 0, 0)
check(probe and #probe == 1, 'the hand-built plate must cover the chunk centre')
if probe and probe[1] then
  check(math.abs(probe[1].height - 0) < 1e-6,
        'and must read y = z at the centre, got ' .. tostring(probe[1].height))
end
local up = Bdhc.heightsAt(SLOPE, 0, 64)
check(up and up[1] and math.abs(up[1].height - 64) < 1e-6,
      'and y = z further along, got ' .. tostring(up and up[1] and up[1].height))

local sloped = setmetatable({
  def = {},
  terrain = { chunkTiles = 32, tileUnits = 16, chunkUnits = 512, chunks = {} },
  grid = { width = 1, height = 1, land = { 7 } },
  offsetX = 0, offsetY = 0,
  chunkPx = 512,
  bdhc = { [7] = SLOPE },
}, { __index = Ground })

check(Ground.heightAtPixel(sloped, 256, 256) ~= nil,
      'the exact sampler must find the plate')

-- THE PROPERTY: moving ACROSS one tile must change the height continuously.
-- Under the tile-centre rule every sample inside a tile is identical, which is
-- precisely what put the character under the ramp.
local tileX = 16 * 8            -- somewhere mid-chunk, tile 8
local a = Ground.heightAtPixel(sloped, tileX, 16 * 8)
local bMid = Ground.heightAtPixel(sloped, tileX, 16 * 8 + 8)
local c = Ground.heightAtPixel(sloped, tileX, 16 * 8 + 15)
check(a and bMid and c, 'three samples across one tile must all resolve')
if a and bMid and c then
  check(a < bMid and bMid < c,
        'the height must RISE across a single sloped tile -- a character who '
        .. 'gets one height per tile sinks into the ramp and steps up at its '
        .. 'edge; got ' .. tostring(a) .. ', ' .. tostring(bMid) .. ', '
        .. tostring(c))
  check(math.abs((c - a) - 15) < 1e-6,
        'by the plate\'s own gradient, got ' .. tostring(c - a))
end

-- ...AND `rise` MUST CARRY THAT THROUGH, since that is what the sprite uses.
sloped.heightScale = 0.5
local r1 = Ground.rise(sloped, tileX, 16 * 8)
local r2 = Ground.rise(sloped, tileX, 16 * 8 + 15)
check(r2 > r1,
      'the sprite lift must rise across the tile too, got ' .. tostring(r1)
      .. ' then ' .. tostring(r2))
check(math.abs((r2 - r1) - 15 * 0.5) < 1e-6,
      'scaled by the camera\'s own height factor, got ' .. tostring(r2 - r1))

-- `groundY` is what the FREE camera places sprites with, and it must agree with
-- `rise` exactly -- they shared a cache before precisely so they could not
-- disagree, and they must still not.
local g1 = Ground.groundY(sloped, tileX, 16 * 8 + 15)
check(math.abs(g1 * 0.5 - r2) < 1e-6,
      'groundY and rise must read the same ground, got ' .. tostring(g1)
      .. ' vs ' .. tostring(r2 / 0.5))

-- A CACHE WOULD REINTRODUCE THE BUG. The old one was keyed per tile, which is
-- the quantising itself.
local gsrc2 = io.open('src/render/Gen4Ground.lua'):read('a')
local riseBody = gsrc2:match('function Gen4Ground:rise%(px, py%).-\nend')
check(riseBody, 'rise must be findable')
if riseBody then
  check(not riseBody:find('riseCache', 1, true),
        'rise must not cache per tile -- caching a value that varies within a '
        .. 'tile IS the slope bug')
  check(riseBody:find('heightAtPixel', 1, true), 'it samples the exact point')
end

-- The editor's per-tile override still wins, and is flat by construction.
local edited = setmetatable({
  def = { gen4HeightEdits = { ['8,8'] = 120 } },
  terrain = { chunkTiles = 32, tileUnits = 16, chunkUnits = 512, chunks = {} },
  grid = { width = 1, height = 1, land = { 7 } },
  offsetX = 0, offsetY = 0, chunkPx = 512, bdhc = { [7] = SLOPE },
}, { __index = Ground })
check(Ground.heightAtPixel(edited, 16 * 8, 16 * 8) == 120,
      'an edited cell must still answer the height the editor painted')
check(Ground.heightAtPixel(edited, 16 * 8 + 15, 16 * 8 + 15) == 120,
      'across the whole cell -- a painted height is flat by construction')
check(Ground.heightAtPixel(edited, 16 * 9, 16 * 9) ~= 120,
      'and the cell next to it must go back to the cartridge\'s own plate')

-- ============ 4. THE LADDER STAYS INSIDE THE CARTRIDGE'S OWN PITCH RANGE
--
-- Reported from play, a third time and after the two faults above were fixed:
-- *"the vertical stretching with the different camera angles when i press 3
-- its stretiching things"*.
--
-- The camera matrix is exact at every rung -- measured through
-- `Gen4View:project`, one world unit is 1.0000 screen pixels across the ground
-- and cos(pitch) up it. So this report is not the renderer, it is the LADDER:
-- it offered angles the cartridge never draws at.
--
-- The world's on-screen height is cos(pitch) while an overworld character is a
-- camera-facing BILLBOARD and is not foreshortened at all. That billboard is
-- ROM PARITY -- the cartridge uses the same unforeshortened sprite art across
-- its whole pitch range -- so what a rung really moves is the sprite-to-world
-- height ratio, and a rung outside the cartridge's range leaves every picture
-- the ROM has behind. At 90 the world has ZERO height: every building collapses
-- while a character stands full size on top of it. And "3" CYCLES the ladder,
-- so 90 and 80 were the first two things a press of it produced.
local lo, hi = nil, nil
for _, row in pairs(Camera.TYPES or {}) do
  local p = tonumber(row and row.pitch)
  if p then
    if not lo or p < lo then lo = p end
    if not hi or p > hi then hi = p end
  end
end
-- 40.5890 (row 9) .. 78.3765 (row 14, HALL_OF_ORIGIN), over all 17 rows.
check(lo and hi and hi > lo, 'the camera rows must state a pitch range at all')
check(near(lo, 40.5890, 1e-3), 'the shallowest row must still be 40.5890, got ' .. tostring(lo))
check(near(hi, 78.3765, 1e-3), 'the steepest row must still be 78.3765, got ' .. tostring(hi))

local steep, shallow = nil, nil
for _, r in ipairs(RUNGS) do
  -- Half a degree of slack, and only that: the rungs are whole degrees and the
  -- range ends are not, so a rung may round one tick past the end it came from.
  check(r.pitch >= lo - 0.5 and r.pitch <= hi + 0.5,
        ('rung %d is outside the pitch range the cartridge uses (%.4f..%.4f)')
          :format(r.pitch, lo, hi))
  -- THE ONE THAT WAS REPORTED. cos(90) is 0 and a world with no height at all
  -- is not a camera angle, it is a missing world.
  local c = math.cos(math.rad(r.pitch))
  check(c > 0.15,
        ('rung %d draws world height at %.4f per unit -- too flat to stand '
         .. 'anything up in'):format(r.pitch, c))
  if not steep or r.pitch > steep then steep = r.pitch end
  if not shallow or r.pitch < shallow then shallow = r.pitch end
end
-- THE ENDS ARE THE CARTRIDGE'S OWN, not merely inside it -- otherwise a ladder
-- clamped to 60..61 would pass everything above while offering no tilt at all.
check(near(steep, hi, 0.5), ('the steepest rung must be the ROM\'s own %.4f, got %s')
  :format(hi, tostring(steep)))
check(near(shallow, lo, 0.5), ('the shallowest rung must be the ROM\'s own %.4f, got %s')
  :format(lo, tostring(shallow)))

-- AND THE PARALLAX INTERPOLATION MUST START AT THE TOP OF *THIS* LADDER.
--
-- It used the literal 90, which was the top only while the ladder started
-- there. Left alone, the steepest rung would begin with parallax the map header
-- never asks for -- and an orthographic room, whose whole point is that it has
-- none, would have got some on every rung.
local steepIndex
for _, r in ipairs(RUNGS) do if r.pitch == steep then steepIndex = r.i end end
check(steepIndex ~= nil, 'the steepest rung must be findable on the ladder')
if steepIndex then
  Camera.chosen = steepIndex
  local persp = Camera.forMap({ cameraType = 0 })
  local row = Camera.forType(0)
  check(near(persp.spreadDistance, row.distance, 1e-6),
        ('at the steepest rung the eye must still be at the header\'s own '
         .. 'distance %.3f, got %s'):format(row.distance, tostring(persp.spreadDistance)))
  -- The orthographic headers are the ones this protects: a camera at infinity
  -- has no parallax, and the steepest rung must leave it that way.
  local orthoId
  for id = 0, 16 do
    local c = Camera.forType(id)
    if c and c.projection == 'orthographic' then orthoId = id break end
  end
  check(orthoId ~= nil, 'the cartridge must still have an orthographic header')
  if orthoId then
    local ortho = Camera.forMap({ cameraType = orthoId })
    check(ortho.spreadDistance == nil,
          'an orthographic room must have NO spread at the steepest rung, got '
            .. tostring(ortho.spreadDistance))
  end
end


print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
