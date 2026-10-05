-- Run:  texlua tools/gen4_canopy_cut_check.lua <cache dir> [assets dir]
--
-- THE CANOPY CUT, AND WHAT "HEAD HEIGHT" IS MEASURED FROM.
--
-- Reported from play:
--
--   *"using the cartridges camera view makes sprites dissapear when walking
--    on an area that has a higher terrain probably under the map"*
--
-- The canopy pass paints world geometry ABOVE a cut over the sprites, so that
-- a character walking under a treetop or behind a wall is hidden by it. The
-- cut was the constant 32 -- how high a character reaches -- stated as an
-- ABSOLUTE world height. That is only ever right at sea level: climb a hill
-- and the floor underfoot is itself above 32, so the pass paints the ground
-- out from under the player and takes the player with it.
--
-- The same mistake sat in the prop branch, where `SORTED_BELOW` asked "is
-- this prop shorter than a character" but compared the prop's ALTITUDE.
--
-- Both are one fault: an absolute world height used where an elevation
-- RELATIVE one is meant.

package.path = './?.lua;./?/init.lua;./tools/save-editor/?.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end
local function near(a, b, eps)
  return type(a) == 'number' and math.abs(a - b) <= (eps or 1e-6)
end

local Ground = require('src.render.Gen4Ground')
local Bdhc = require('src.import.Gen4Bdhc')

local CANOPY_Y = 32          -- the head height the source states
local CHUNK, HALF, UNIT = 512, 256, 16

-- THE SOURCE, WITH ITS COMMENTS STRIPPED.
--
-- Twice now a scan has been defeated by prose about its own subject: a test
-- for `walkEntity` matched the comment explaining that the call was removed,
-- and a test for the behaviour-cell ordering matched the comment describing
-- the fallback. A comment is not a call, so the comments go.
local function sourceOf(path)
  local f = assert(io.open(path, 'rb'))
  local raw = f:read('*a'); f:close()
  local out = {}
  for line in (raw:gsub('\r\n', '\n')):gmatch('([^\n]*)\n?') do
    if not line:match('^%s*%-%-') then out[#out + 1] = line end
  end
  return table.concat(out, '\n')
end
local SRC = sourceOf('src/render/Gen4Ground.lua')

-- A flat BDHC plate covering the whole chunk at a stated height.
local function flatAt(h)
  return {
    points = { { x = -HALF, z = -HALF }, { x = HALF, z = HALF } },
    normals = { { x = 0, y = 1, z = 0 } },
    constants = { -h },
    plates = { { first = 0, second = 1, normal = 0, constant = 0 } },
    strips = {}, access = {},
  }
end
-- THE FIXTURE IS VERIFIED BEFORE IT IS TRUSTED. A hand-built plate that does
-- not read back the height it was built for grades nothing.
do
  local probe = Bdhc.heightsAt(flatAt(96), 0, 0)
  check(probe and #probe == 1 and near(probe[1].height, 96),
        'the hand-built flat plate must read back its own height')
end

local function groundWith(plates, sinP)
  return setmetatable({
    def = {},
    terrain = { chunkTiles = 32, tileUnits = UNIT, chunkUnits = CHUNK, chunks = {} },
    grid = { width = 1, height = 1, land = { 7 } },
    offsetX = 0, offsetY = 0, chunkPx = CHUNK,
    groundScale = sinP or 1,
    bdhc = { [7] = plates },
    canopies = {},
  }, { __index = Ground })
end

-- ===================================== 1. ONE PLACE THE PLAYER IS DERIVED
--
-- `camX/camY` is the viewport's corner and the overworld keeps the player at
-- its centre, so the centre IS the player. That identity was written out four
-- separate times -- the short-prop sort, the height spread's datum, the free
-- camera's eye and the canopy cut -- and four copies of one derivation is the
-- shape every bug in this file has had: the same thing spelled differently in
-- two places that never meet.
check(SRC:match('function Gen4Ground:viewCentre'),
      'there must be one named derivation of where the player is')
local hand = select(2, SRC:gsub('%(2 %* sinP%)', ''))
check(hand == 1,
      'the eye row must be derived ONCE, found ' .. tostring(hand) .. ' copies')

local g1 = groundWith(flatAt(0), 1)
local ex, ey = g1:viewCentre(100, 200, 40, 60)
check(near(ex, 120), 'the centre is half a viewport right of the corner')
check(near(ey, 230), 'and half a viewport down it when the ground is unleaned')
-- LEAN-AWARE, because the ground is compressed by sin(pitch): the row half way
-- down the CANVAS is further than half a viewport away in the WORLD.
local g2 = groundWith(flatAt(0), 0.5)
local _, ey2 = g2:viewCentre(100, 200, 40, 60)
check(near(ey2, 260), 'a leaned ground pushes the eye row further out, not less')
check(ey2 > ey, 'and never nearer than the unleaned one')

-- ================================== 2. THE CUT IS GROUND PLUS HEAD HEIGHT
--
-- At sea level it is still 32 and nothing about the old behaviour moves.
local sea = groundWith(flatAt(0), 1)
check(near(sea:canopyCut(0, 0, 32, 32), CANOPY_Y),
      'at sea level the cut must still be exactly head height')
-- On a plateau it must RISE WITH THE FLOOR. This is the whole fix: a cut that
-- does not move is a cut that paints the plateau over whoever stands on it.
for _, h in ipairs({ 16, 48, 96, 160, 320 }) do
  local up = groundWith(flatAt(h), 1)
  local cut = up:canopyCut(0, 0, 32, 32)
  check(near(cut, h + CANOPY_Y),
        ('a floor at %d must cut at %d, got %s'):format(h, h + CANOPY_Y, tostring(cut)))
  check(cut > h, ('and the cut must CLEAR the floor at %d'):format(h))
end

-- A CORRECT CUT THAT NOTHING CALLS IS THE FAULT WITH EXTRA STEPS, so the
-- pass that actually runs -- the live one, which the play logs show as
-- `drew LIVE` -- must be the one taking it.
check(SRC:match('livePass%(camX, camY, lw, lh,%s*self:canopyCut'),
      'the live canopy pass must take the ground-relative cut')
check(not SRC:match('livePass%([^)]-CANOPY_Y%s*%)'),
      'and must not hand the height cut the bare constant')
check(SRC:match('canopyFor%(land, cut%)'),
      'the baked fallback must be given the same cut')

-- ============================ 3. THE BAKED FALLBACK CAN INVALIDATE ITSELF
--
-- A baked canopy holds the cut it was baked with. Without invalidation the
-- fallback path keeps a sea-level canopy for the life of the map, and the fix
-- lands only on machines that can run the live pass.
do
  local gb = groundWith(flatAt(0), 1)
  local sentinel = { release = function() end }
  gb.canopies[7] = sentinel
  gb.canopyCutUsed = CANOPY_Y
  gb.canopyBudget = 0
  gb:canopyFor(7, CANOPY_Y)
  check(gb.canopies[7] == sentinel,
        'an unchanged cut must KEEP the canopy it already baked')
  gb:canopyFor(7, 160 + CANOPY_Y)
  check(gb.canopies[7] == nil,
        'a cut that moved must drop the canopy baked at the old one')
  -- Quantised to one tile unit, or walking a slope re-bakes every frame.
  gb.canopies[7] = sentinel
  gb.canopyCutUsed = math.floor(((160 + CANOPY_Y) / UNIT) + 0.5) * UNIT
  gb:canopyFor(7, 160 + CANOPY_Y + 1)
  check(gb.canopies[7] == sentinel,
        'a sub-tile wobble in the cut must NOT throw the bake away')
end

-- ======================== 4. A SHORT PROP IS SHORT, NOT MERELY LOW-LYING
--
-- `SORTED_BELOW` asks whether a prop is shorter than a character, and its own
-- comment measures it that way: *"338 of them top out below CANOPY_Y"* is a
-- statement about MODELS. Compared against the prop's altitude instead, every
-- prop standing high enough is forced down the TALL branch however short it
-- really is -- and its cut then comes out at or below zero, which paints the
-- WHOLE prop over the sprites.
local cmp = SRC:match('local%s+([%w_]+)%s*=%s*([^\n]-)\n%s*if%s+%1%s*<=%s*SORTED_BELOW')
local _, cmpExpr = SRC:match('local%s+([%w_]+)%s*=%s*([^\n]-)\n%s*if%s+%1%s*<=%s*SORTED_BELOW')
check(cmp ~= nil, 'the short-prop test must compare a named local')
check(cmpExpr and cmpExpr:match('topY'),
      'and that local must be built from the model\'s own top')
check(cmpExpr and not cmpExpr:match('object%.y'),
      'but NOT from the prop\'s lift: ' .. tostring(cmpExpr))

-- ================================= 5. REAL SINNOH, THROUGH THE REAL CALL
--
-- Sections 2 and 4 grade the rule. This one grades it against the ground the
-- cartridge actually ships, driving `canopyCut` itself: revert it to a
-- constant and this section fails on real data rather than on a text match.
local CACHE, ASSETS = arg[1], arg[2]
if not (CACHE and ASSETS) then
  print('note: no cache/assets given, skipping the real-terrain section')
else
  local ok, t = pcall(function() return assert(loadfile(CACHE .. '/gen4_terrain.lua'))() end)
  local hf = io.open(ASSETS .. '/gen4/terrain/heights.bin', 'rb')
  if not (ok and t and t.chunks and hf) then
    print('note: terrain cache or heights.bin unreadable, skipping')
  else
    local lands = {}
    for land in pairs(t.chunks) do lands[#lands + 1] = land end
    table.sort(lands)
    local N = 60
    local tiles, oldFailed, newFailed, raised = 0, 0, 0, 0
    local VW, VH = 256, 192
    for i = 1, N do
      local land = lands[math.floor(i * #lands / N)]
      local rec = land and t.chunks[land]
      if rec and rec.heightBytes and rec.heightBytes > 0 then
        hf:seek('set', rec.heightAt)
        local good, bdhc = pcall(Bdhc.parse, hf:read(rec.heightBytes))
        if good and bdhc then
          local gr = groundWith(bdhc, 1)
          for tz = 0, 31, 2 do
            for tx = 0, 31, 2 do
              local mx, my = (tx + 0.5) * UNIT, (tz + 0.5) * UNIT
              local recs = Bdhc.heightsAt(bdhc, mx - HALF, my - HALF) or {}
              if #recs > 0 then
                local h = recs[1].height
                for _, r in ipairs(recs) do if r.height > h then h = r.height end end
                tiles = tiles + 1
                if h > CANOPY_Y then raised = raised + 1 end
                -- The OLD rule: a constant, which the floor itself outgrows.
                if CANOPY_Y <= h then oldFailed = oldFailed + 1 end
                -- The NEW rule, through the shipping call, with the camera
                -- placed so the view's centre lands on this very tile.
                local cut = gr:canopyCut(mx - VW / 2, my - VH / 2, VW, VH)
                if not (cut > h) then newFailed = newFailed + 1 end
              end
            end
          end
        end
      end
    end
    hf:close()
    print(('   real terrain: %d plated tiles, %d (%.1f%%) standing above %d')
      :format(tiles, raised, tiles > 0 and raised / tiles * 100 or 0, CANOPY_Y))
    check(tiles > 10000, 'the sample must be big enough to mean something, got ' .. tiles)
    -- THE FAULT IS REAL AND THIS IS THE CONTROL: if the old constant cleared
    -- every tile there was nothing to fix and this check is theatre.
    check(oldFailed > 0,
          'the old absolute cut must demonstrably fail on real ground')
    check(raised / math.max(tiles, 1) > 0.05,
          ('raised ground must be common, not a corner case: %.1f%%')
            :format(raised / math.max(tiles, 1) * 100))
    check(newFailed == 0,
          ('the ground-relative cut must clear the floor on EVERY tile, %d failed')
            :format(newFailed))
  end
end

-- ===================== THE GROUND BEHIND THE PLAYER IS NOT PAINTED OVER THEM
--
-- Reported from play on Route 207: *"The mud slides are over my character
-- when i walk up to them when they shouldnt be"*. Two faults, measured on the
-- cartridge's own slope at (18,15) with the view centred three tiles north of
-- the player -- which is where the overworld's background offset put it:
-- 46 of the sprite's pixels were painted over, against 16 (one row of tile
-- edge) after.
--
-- 1. The cut was measured from the VIEW CENTRE, not the player.
do
  local g = setmetatable({ groundScale = 1, focusX = 300, focusZ = 260 },
                         { __index = Ground })
  local fx, fz = g:focus(0, 0, 256, 192)
  check(fx == 300 and fz == 260,
        'the canopy must be measured from the player the overworld hands it')
  g.focusX, g.focusZ = nil, nil
  local vx, vz = g:focus(0, 0, 256, 192)
  check(vx == 128 and vz == 96, 'and fall back to the view centre otherwise')
end
local ow = io.open('src/world/OverworldController.lua'):read('a')
check(ow:find('g4.focusX, g4.focusZ = feetX - ox, feetZ - oy', 1, true),
      'the overworld must hand each ground the player\'s feet before its canopy')
-- 2. A height rule alone paints a ramp rising BEHIND the player over them.
local gsrc = io.open('src/render/Gen4Ground.lua'):read('a')
check(gsrc:find('Gen4Model.zKeep = { playerZ - KEEP_BEHIND - chunkZ', 1, true),
      'the cut pass must leave the band just behind the player unpainted')
check(gsrc:find('Gen4Model.zKeep = nil', 1, true),
      'and clear it before the props, which keep their own rule')
local msrc = io.open('src/render/Gen4Model.lua'):read('a')
check(msrc:find('if (vModelZ > zKeep.x && vModelZ <= zKeep.y) { discard; }', 1, true),
      'the shader must discard that band')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
