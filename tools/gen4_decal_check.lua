-- Run:  texlua tools/gen4_decal_check.lua <cache dir>
--
-- THE PER-CELL GROUND TEXTURE LAYER -- the packing and the grouping.
--
-- Sinnoh has no per-cell texture ids and its ground is not cell-aligned:
-- measured over 60 chunks and 73,601 triangles, 64,386 of them (87.5%)
-- straddle a cell boundary. So per-cell texturing cannot be done by splitting
-- the mesh, and is done instead by laying a textured quad on the ground.
--
-- The quad has to be packed in exactly the vertex format `Gen4Model` reads, and
-- that format was taken off its own decoder rather than guessed. This file
-- checks the packing by DECODING it the same way the engine will -- a packer
-- checked against its own constants would agree with itself and with nothing
-- else.

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end
local function near(a, b, eps)
  return type(a) == 'number' and math.abs(a - b) <= (eps or 1e-6)
end

local D = require('src.render.Gen4Decals')

-- ============================================ 1. the format, against the engine
--
-- `Gen4Model`'s own reader, written out here, is the authority. If this and
-- the packer ever disagree the world comes back as confetti with no error
-- anywhere -- which is the failure the model loader's own comments describe.
local function engineS16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local v = a + b * 256
  if v >= 32768 then v = v - 65536 end
  return v
end

check(D.VERTEX_BYTES == 16, 'a vertex must be the 16 bytes the engine reads')
local v = D.vertex(0, 0, 0, 0, 0)
check(#v == D.VERTEX_BYTES, 'and one packed vertex must be exactly that long, got ' .. #v)

-- Position round-trips through the engine's decode.
for _, world in ipairs({ 0, 1, -1, 16, 255.5, -256, 256 }) do
  local packed = D.packPosition(world)
  local back = engineS16(packed, 0) / D.FX16 * D.POS_SCALE
  check(near(back, world, 0.02),
        ('position %s must survive the engine\'s own decode, got %s')
          :format(tostring(world), tostring(back)))
end

-- THE RANGE, which is what POS_SCALE is for. A chunk is 512 across, so its
-- coordinates run +-256; a scale that cannot reach them folds the far half of
-- every decal back on itself.
check(near(D.packPosition(256) and engineS16(D.packPosition(256), 0) / D.FX16 * D.POS_SCALE, 256, 0.02),
      'the chunk\'s far corner must be representable')
check(engineS16(D.packPosition(256), 0) < 32767,
      'without saturating the s16 -- a clamped coordinate is a silently moved '
      .. 'vertex; got ' .. engineS16(D.packPosition(256), 0))
check(engineS16(D.packPosition(-256), 0) > -32768, 'at both ends')

-- UV is in texels times UV_UNITS, which is what the engine divides back out.
check(engineS16(D.packUV(16), 0) / D.UV_UNITS == 16,
      'a texel coordinate must survive the UV decode')

-- The normal must be +Y: a ground decal faces up, and one lit as a wall would
-- be a bright patch on a dark floor.
check(v:byte(14) == 0 and v:byte(15) == 127 and v:byte(16) == 0,
      'the packed normal must be straight up (0, 127, 0), got '
      .. tostring(v:byte(14)) .. ',' .. tostring(v:byte(15)) .. ','
      .. tostring(v:byte(16)))
-- ...and the colour defaults to white, or every decal is tinted by whatever
-- happened to be in those bytes.
check(v:byte(11) == 255 and v:byte(12) == 255 and v:byte(13) == 255,
      'and the colour must default to white')

-- ================================================= 2. the quad, and the lift
local rec = D.build({ { x = 0, z = 0, texture = 't', image = 'a.png', w = 32, h = 32, y = 8 } })
check(rec ~= nil, 'one painted cell must build a record')
check(rec.posScale == D.POS_SCALE, 'carrying the scale the engine will multiply by')
check(#rec.shapes == 1, 'one texture is one shape, got ' .. #rec.shapes)
local sh = rec.shapes[1]
check(sh.vertexCount == 4, 'a cell is four vertices, got ' .. tostring(sh.vertexCount))
check(sh.triangleCount == 2, 'and two triangles, got ' .. tostring(sh.triangleCount))
check(#sh.vertices == 4 * D.VERTEX_BYTES, 'and the buffer must match the count')
check(#sh.indices == 6 * 2, 'six 16-bit indices')
check(sh.image == 'a.png', 'the shape must name the picture the engine loads')

-- The four corners, decoded back. A cell is `unit` across and sits at the
-- height it was given, lifted off the ground.
local function corner(i)
  local at = i * D.VERTEX_BYTES
  return D.readPosition(sh.vertices, at),
         D.readPosition(sh.vertices, at + 2),
         D.readPosition(sh.vertices, at + 4)
end
local x1, y1, z1 = corner(0)
local x2, _, z2 = corner(1)
local x3, _, z3 = corner(2)
local x4, _, z4 = corner(3)
check(near(x1, 0, 0.02) and near(z1, 0, 0.02), 'corner 1 is the cell origin')
check(near(x2, 16, 0.02) and near(z2, 0, 0.02), 'corner 2 is one cell east')
check(near(x3, 16, 0.02) and near(z3, 16, 0.02), 'corner 3 is the far corner')
check(near(x4, 0, 0.02) and near(z4, 16, 0.02), 'corner 4 closes the quad')
check(y1 > 8 and y1 < 8.5,
      'and the quad must sit just ABOVE the ground it decorates -- coplanar '
      .. 'with the terrain the depth test z-fights and the cell shimmers as '
      .. 'the camera moves; got ' .. tostring(y1))

-- A SLOPED CELL takes its four corners from the plate's plane, so a decal on a
-- hillside lies on the hill rather than hovering level over it.
local slope = D.build({ { x = 0, z = 0, image = 'a.png', w = 16, h = 16,
                          y = 0, y2 = 8, y3 = 16, y4 = 8 } })
local s2 = slope.shapes[1]
local _, cy1 = (function() local at = 0
  return D.readPosition(s2.vertices, at), D.readPosition(s2.vertices, at + 2) end)()
local _, cy3 = (function() local at = 2 * D.VERTEX_BYTES
  return D.readPosition(s2.vertices, at), D.readPosition(s2.vertices, at + 2) end)()
check(cy3 - cy1 > 15 and cy3 - cy1 < 17,
      'a sloped cell\'s corners must differ by the slope, got '
      .. tostring(cy3 - cy1))

-- ============================================ 3. grouping, which is the cost
--
-- A shape binds ONE texture, so cells sharing a picture must share a shape --
-- otherwise a route painted in one texture is one draw call per cell.
local many = {}
for i = 0, 99 do
  many[#many + 1] = { x = i * 16, z = 0, image = (i % 2 == 0) and 'a.png' or 'b.png',
                      w = 16, h = 16, y = 0 }
end
local grouped = D.build(many)
check(#grouped.shapes == 2,
      '100 cells in 2 textures must be 2 shapes, not 100 -- got '
      .. #grouped.shapes)
local total = 0
for _, s in ipairs(grouped.shapes) do total = total + s.triangleCount end
check(total == 200, 'with every cell still present as two triangles, got ' .. total)
for _, s in ipairs(grouped.shapes) do
  check(s.vertexCount == 50 * 4, 'each group holds its own cells, got ' .. s.vertexCount)
  check(#s.indices == s.triangleCount * 3 * 2, 'and an index per corner')
end

-- INDICES MUST BE LOCAL TO THEIR SHAPE and must never point past its vertices:
-- an index into another group's vertices is a triangle stretched across the
-- map, which is the classic symptom of a grouped mesh built with global ids.
for _, s in ipairs(grouped.shapes) do
  local worst = -1
  for i = 0, s.triangleCount * 3 - 1 do
    local a, b = s.indices:byte(i * 2 + 1, i * 2 + 2)
    local idx = a + b * 256
    if idx > worst then worst = idx end
  end
  check(worst == s.vertexCount - 1,
        'the highest index must be the last vertex of its OWN shape -- got '
        .. worst .. ' with ' .. s.vertexCount .. ' vertices')
end

-- ================================================== 4. nothing painted costs nothing
check(D.build({}) == nil, 'an unpainted map must build no record at all')
check(D.build(nil) == nil, 'and nil must be accepted')
check(D.build({ { x = 0, z = 0, y = 0 } }) == nil,
      'a cell with no picture names nothing to draw and must be skipped '
      .. 'rather than producing a shape with no texture')

-- ====================================== 5. the catalogue, the store, the routing
local Terrain4 = require('tools.map-editor.Gen4Terrain')
local Edits = require('tools.map-editor.MapEdits')
local Ground = require('src.render.Gen4Ground')

local cacheDir = arg and arg[1]
local terrain
if cacheDir then
  local f = loadfile(cacheDir .. '/gen4_terrain.lua')
  if f then local ok, t = pcall(f); if ok then terrain = t end end
end
check(type(terrain) == 'table',
      'no gen4_terrain.lua at ' .. tostring(cacheDir) .. ' -- the catalogue is '
      .. 'built from the cartridge\'s own texture sets and cannot be checked '
      .. 'without them')

if type(terrain) == 'table' then
  local data = { gen4_terrain = terrain }
  local def = { id = 'C01', sourceId = 'C01' }
  local list = Terrain4.textures(data, def)
  check(#list > 1000, 'the catalogue must offer the cartridge\'s textures, got '
        .. #list)
  local dupes, noPath = 0, 0
  local seen = {}
  for _, e in ipairs(list) do
    if seen[e.texture] then dupes = dupes + 1 end
    seen[e.texture] = true
    if type(e.path) ~= 'string' or not e.width or not e.height then
      noPath = noPath + 1
    end
  end
  check(dupes == 0, 'a texture must appear once -- a name in two sets is one '
        .. 'brush, not two; got ' .. dupes .. ' duplicates')
  check(noPath == 0, 'and every entry must carry the path and size the decal '
        .. 'needs, got ' .. noPath .. ' without')

  -- THE MAP'S OWN SET FIRST, which is the whole ordering: a route is painted
  -- out of the textures its own chunks already use far more often than out of
  -- the other seventy-three sets.
  local ownSet = Terrain4.setIdFor(data, def)
  if ownSet ~= nil then
    check(list[1] and list[1].own == true,
          'the map\'s own set must come first in the palette')
    local firstForeign
    for i, e in ipairs(list) do
      if not e.own then firstForeign = i break end
    end
    check(firstForeign and firstForeign > 1,
          'with every one of its textures ahead of the rest')
  end

  -- A record found by name must be the one the decal will load.
  -- EVERY ENTRY, not a sample: a name repeats across sets with different
  -- palettes, and the lookup walked `pairs` -- an order that changes between
  -- runs -- so a single sample passed or failed by luck. The editor's lookup
  -- and the renderer's must both land on the copy the palette offered.
  local fakeGround = setmetatable({ terrain = terrain,
    set = ownSet ~= nil and terrain.sets[ownSet] or nil }, { __index = Ground })
  local editorWrong, gameWrong = 0, 0
  for _, e in ipairs(list) do
    local rec = Terrain4.textureRecord(data, e.texture, def)
    if not (rec and rec.path == e.path) then editorWrong = editorWrong + 1 end
    local live = fakeGround:textureNamed(e.texture)
    if not (live and live.path == e.path) then gameWrong = gameWrong + 1 end
  end
  check(editorWrong == 0,
        'textureRecord must agree with the catalogue about every texture\'s '
        .. 'path, got ' .. editorWrong .. ' disagreeing')
  check(gameWrong == 0,
        'and so must the renderer -- what the editor shows is what the game '
        .. 'draws -- got ' .. gameWrong .. ' disagreeing')
end

-- The store: a painted cell round-trips, and clearing removes it rather than
-- recording a blank.
local st, pdef = {}, { id = 'C01', width = 8, height = 8 }
check(Edits.setCellTexture(st, 'platinum', 'C01', 2, 3, 'grass01', pdef),
      'painting a cell texture must work')
check(Terrain4.textureAt(pdef, 2, 3) == 'grass01',
      'and read back off the live def, got '
      .. tostring(Terrain4.textureAt(pdef, 2, 3)))
check(Edits.cellTextureAt(st, 'platinum', 'C01', 2, 3) == 'grass01',
      'and out of the store')
check(Terrain4.textureAt(pdef, 0, 0) == nil, 'leaving other cells alone')
Edits.setCellTexture(st, 'platinum', 'C01', 2, 3, nil, pdef)
check(Terrain4.textureAt(pdef, 2, 3) == nil,
      'clearing must REMOVE the override so the cell goes back to the '
      .. 'cartridge\'s own ground, rather than pinning it to whatever it '
      .. 'happens to look like today')
check(Edits.MAP_FIELDS.gen4TextureEdits == 'table',
      'and the field must be in the allow-list or every paint is dropped')

-- ...and it survives onto a freshly extracted map, which is the re-import
-- promise. Names rather than paths is what makes that possible.
Edits.setCellTexture(st, 'platinum', 'C01', 1, 1, 'grass01', pdef)
local fresh = { id = 'C01', width = 8, height = 8 }
Edits.applyToMap(st, 'platinum', 'C01', fresh)
check(Terrain4.textureAt(fresh, 1, 1) == 'grass01',
      'a painted cell must survive a re-import')

-- ============================= 6. a painted cell lands in the right chunk
--
-- The routing is map cell -> matrix tile -> chunk, and it is the one piece of
-- arithmetic here that can be wrong without anything raising: a cell routed to
-- the wrong chunk simply paints somewhere else.
local function groundAt(offsetX, offsetY, edits)
  return setmetatable({
    def = { gen4TextureEdits = edits },
    terrain = { chunkTiles = 32, tileUnits = 16, chunkUnits = 512,
                sets = { s = { textures = { grass01 =
                  { texture = 'grass01', path = 'g.png', width = 16, height = 16 } } } } },
    set = nil,
    grid = { width = 4, height = 4,
             land = { 10, 11, 12, 13, 20, 21, 22, 23,
                      30, 31, 32, 33, 40, 41, 42, 43 } },
    offsetX = offsetX, offsetY = offsetY,
    heightAt = function() return 0 end,
  }, { __index = Ground })
end

-- A map whose corner is the matrix origin: cell (0,0) is chunk (0,0) = land 10.
local g1 = groundAt(0, 0, { ['0,0'] = 'grass01' })
check(Ground.decalModelFor(g1, 11) == nil,
      'a cell in chunk 0 must not be routed to chunk 1')
-- `Gen4Model.new` needs a shader, which this harness has not got, so the model
-- itself cannot be built here -- the ROUTING is what is under test, and a
-- `false` cached against the right land id is the routing having found it.
Ground.decalModelFor(g1, 10)
-- `decalCells`, NOT `decalModels`. The model is `false` both when no cell
-- routed here and when the cells routed here but the model would not build --
-- and this harness has no shader, so it is always the second. An assertion on
-- `decalModels[land] ~= nil` passed under a planted routing fault because
-- `false ~= nil`: it could not see the thing it was named after.
check((g1.decalCells or {})[10] == 1,
      'the cell must be found on chunk 0, which is land 10; routed '
      .. tostring((g1.decalCells or {})[10]))

-- A map starting 32 tiles in: its cell (0,0) is matrix tile (32,0), chunk
-- (1,0) = land 11. This is the offset term, and it is the one a map cropped
-- out of the middle of Sinnoh depends on.
local g2 = groundAt(32 * 16, 0, { ['0,0'] = 'grass01' })
Ground.decalModelFor(g2, 11)
check((g2.decalCells or {})[11] == 1,
      'a map offset one chunk east must route its cell 0,0 to land 11, routed '
      .. tostring((g2.decalCells or {})[11]))
local g2b = groundAt(32 * 16, 0, { ['0,0'] = 'grass01' })
Ground.decalModelFor(g2b, 10)
check((g2b.decalCells or {})[10] == 0,
      'and NOT to the chunk its corner would have been in with no offset -- '
      .. 'routed ' .. tostring((g2b.decalCells or {})[10]) .. ' there')

-- An unpainted map must cost nothing at all.
local g3 = groundAt(0, 0, nil)
check(Ground.decalModelFor(g3, 10) == nil, 'an unpainted map builds nothing')
check(Ground.decalModelFor(groundAt(0, 0, {}), 10) == nil, 'nor an empty table')

-- A texture name the cartridge does not have must be skipped, not crash.
local g4 = groundAt(0, 0, { ['0,0'] = 'no_such_texture' })
check(pcall(Ground.decalModelFor, g4, 10),
      'an unknown texture name must not raise -- a cache re-extracted without '
      .. 'a texture a map was painted with is an ordinary thing to meet')

-- Dropping the bakes must drop these, or a painted cell does not appear until
-- the game is restarted.
local g5 = groundAt(0, 0, { ['0,0'] = 'grass01' })
g5.baked, g5.order, g5.canopies, g5.animated, g5.depthModels = {}, {}, {}, {}, {}
Ground.decalModelFor(g5, 10)
check(g5.decalModels ~= nil, 'the decal cache must exist once built')
Ground.dropBakes(g5)
check(g5.decalModels == nil and g5.decalCells == nil,
      'and must be dropped with the bakes -- a decal is baked INTO the chunk '
      .. 'canvas, so a cached model outliving that canvas means an edit does '
      .. 'not show')

-- ================ 7. the height is sampled in the EDITOR'S coordinate space
--
-- THE TRAP THIS SECTION EXISTS FOR. `decalModelFor` calls its map cells
-- `mx, my` and its matrix tiles `tx, ty`. `heightsAt` and `signpostsFor`, in
-- the same file, use `mx, my` for the MATRIX TILES. So the same two letters
-- mean different spaces in neighbouring functions, and `heightAt(mx, my)`
-- reads correct in both of them while being right in only one -- `heightsAt`
-- adds the map's offset itself, so it wants MAP-LOCAL tiles.
--
-- Nothing above could see this: section 6 hands its ground a
-- `heightAt = function() return 0 end`, which answers the same number for
-- every coordinate in either space. A fake that cannot distinguish the two
-- answers grades its own mirror -- so this section fakes NOTHING on the path
-- under test and drives the real `heightAt` -> `heightsAt` ->
-- `heightOverride` chain, keyed the way the panel's own `setHeight` keys it.
--
-- A wrong space does not raise and does not look wrong in isolation: the quad
-- is simply built at some other cell's height, which on Sinnoh means buried
-- under the hill or floating over it -- invisible either way, and reported as
-- *"it doesnt seem to paint them onto the world"*.
local function groundWithHeights(offsetX, offsetY, texEdits, heightEdits)
  return setmetatable({
    def = { gen4TextureEdits = texEdits, gen4HeightEdits = heightEdits },
    -- `chunks` PRESENT AND EMPTY, because the real `heightsAt` falls
    -- through to the BDHC when no override covers the tile and indexes
    -- `terrain.chunks` on the way. Leaving it out raises there, which the
    -- `pcall` below would swallow into an empty cell list -- making the
    -- control assertion pass for the wrong reason.
    terrain = { chunkTiles = 32, tileUnits = 16, chunkUnits = 512, chunks = {},
                sets = { s = { textures = { grass01 =
                  { texture = 'grass01', path = 'g.png',
                    width = 16, height = 16 } } } } },
    grid = { width = 4, height = 4,
             land = { 10, 11, 12, 13, 20, 21, 22, 23,
                      30, 31, 32, 33, 40, 41, 42, 43 } },
    offsetX = offsetX, offsetY = offsetY,
  }, { __index = Ground })
end

-- The cells are handed to `Gen4Decals.build`, which is reached through
-- `require` -- so swapping the loaded module for a recorder reads the real
-- arithmetic's own output without touching it. `build` returning nil is the
-- ordinary "nothing to draw" path, so the caller stays on its feet.
local realDecals = package.loaded['src.render.Gen4Decals']
local function cellsFor(g, land)
  local seen
  package.loaded['src.render.Gen4Decals'] =
    { build = function(cells) seen = cells return nil end }
  pcall(Ground.decalModelFor, g, land)
  package.loaded['src.render.Gen4Decals'] = realDecals
  return seen or {}
end

-- A map one chunk east, with the panel's own height edit on its cell (0,0).
-- `T.setHeight` keys `gen4HeightEdits` by MAP CELL, so this is the key the
-- editor writes and the decal must read with.
local EDIT = 96
local gh = groundWithHeights(32 * 16, 0, { ['0,0'] = 'grass01' },
                             { ['0,0'] = EDIT })
local got = cellsFor(gh, 11)
check(#got == 1, 'the painted cell must reach the decal builder, got ' .. #got)
check(got[1] and got[1].y == EDIT,
      'and must carry the height the EDITOR wrote for that map cell -- '
      .. 'sampling in matrix-tile space instead reads some other cell\'s '
      .. 'height and buries or floats the quad; wanted ' .. EDIT .. ', got '
      .. tostring(got[1] and got[1].y))

-- THE CONTROL, which is what makes the assertion above mean anything: the
-- same height written at the MATRIX-TILE key must NOT be found. Without this,
-- a decal that read the right number for the wrong reason -- or a chain that
-- answered `EDIT` for every coordinate -- would pass.
local gw = groundWithHeights(32 * 16, 0, { ['0,0'] = 'grass01' },
                             { ['32,0'] = EDIT })
local wrong = cellsFor(gw, 11)
check(wrong[1] and wrong[1].y == Ground.DEFAULT_HEIGHT,
      'a height written against the MATRIX tile must not be picked up -- if it '
      .. 'is, the two spaces are being confused somewhere and this check '
      .. 'cannot tell them apart; got ' .. tostring(wrong[1] and wrong[1].y))

-- ...and the real module must be back, or every check after this one is
-- grading a stub.
check(package.loaded['src.render.Gen4Decals'] == realDecals
      and type(D.build) == 'function',
      'the recorder must be removed again')

-- ====================================== 8. a decal that will not draw SAYS SO
--
-- Every stage before `Gen4Model.new` can be checked without a graphics driver
-- and is checked above. That one cannot, and it was also the stage that threw
-- its reason away -- so a painted cell that did not appear produced no log
-- line, no counter and no error, and the only report available was *"it
-- doesnt seem to paint them onto the world"*. These assertions are about
-- OBSERVABILITY rather than correctness: they fail if the diagnosis goes
-- quiet again.
local ground = io.open('src/render/Gen4Ground.lua'):read('a')
check(ground:match('self%.decalWhy%[land%] = why'),
      'the reason a decal did not build must be kept, not discarded')
check(ground:match('Gen4Model%.new raised'),
      'and must separate "raised" from "returned nil"')
check(ground:match('build made no record'),
      'and both of those from "the builder made nothing"')
check(ground:match('function Gen4Ground:decalReport'),
      'and there must be a one-liner for the editor to show')
-- `painted` and `routed` are different numbers and the difference is the whole
-- diagnosis: paint in the store with nothing routed is a routing fault, and
-- routed with nothing drawn is a build fault.
check(ground:match('painted %%d, routed %%d over %%d chunks, drawn %%d'),
      'reporting painted, routed and drawn separately -- one total cannot tell '
      .. 'a routing fault from a build fault')
check(ground:match('self%.decalModels, self%.decalCells, self%.decalWhy = nil, nil, nil'),
      'and the kept reason must be dropped with the bakes, or a failure from '
      .. 'before an edit is still being reported after it')

local g6 = groundWithHeights(0, 0, { ['0,0'] = 'grass01' }, nil)
Ground.decalModelFor(g6, 10)
check(type(g6.decalWhy) == 'table' and g6.decalWhy[10] ~= nil,
      'a chunk whose decal did not build must record why -- this harness has '
      .. 'no shader, so it never can')
local said = Ground.decalReport(g6)
check(said:match('painted 1') and said:match('routed 1'),
      'the report must count the paint and the routing, got ' .. said)
check(said:match('drawn 0') and said:find('--', 1, true),
      'and must say it was not drawn, with the reason, got ' .. said)

-- An unpainted map must report cleanly rather than with an empty reason.
local g7 = groundWithHeights(0, 0, nil, nil)
check(Ground.decalReport(g7):match('painted 0, routed 0 over 0 chunks, drawn 0'),
      'an unpainted map must report nothing painted, got '
      .. Ground.decalReport(g7))

-- ============================= 9. the painter's previews, and the clip lesson
local terrain = io.open('tools/map-editor/panels/Terrain.lua'):read('a')
-- THE SAME LOADER AS THE DECAL. A swatch drawn through a second image loader
-- could show a picture the painter cannot find, which is a preview that lies
-- about the only thing it is for.
check(terrain:match('pcall%(require, "src%.render%.Assets"%)'),
      'the swatch must load through Assets, which is what Gen4Model.new uses '
      .. 'for shape.image -- a second loader is a second answer')
check(terrain:match('local TEXROWH'), 'a texture row needs its own height')
-- ONE NAME FOR THE ROW PITCH. The row loop and the scrollable height it is
-- measured against disagreeing by a few pixels per row is how a 1,500-row
-- list stops reaching its own end -- and 1,502 is the real palette size.
local rowUses = select(2, terrain:gsub('TEXROWH', ''))
check(rowUses >= 4,
      'and that name must be used by both the row loop and `measured`, got '
      .. rowUses .. ' mentions')
check(not terrain:match('#textures %* %(ROWH'),
      'the measured height must not still be using the behaviour row height')
-- HOVER IS DEFERRED. This is the model picker's bug, twice reported, and the
-- texture list is the next list in the same tool.
check(terrain:match('function T%.drawDeferred'),
      'the enlarged preview must be drawn after the frame, outside the clip')
check(terrain:match('S%.terrainTexHover = nil'),
      'and the hover must be cleared every frame, or the preview outlives the '
      .. 'pointer')
local loopAt = terrain:find('for _, t in ipairs%(textures%) do')
-- PLAIN FIND. `+` is a quantifier in a Lua pattern, so 'ry = ry + TEXROWH'
-- as a pattern asks for spaces where the source has a literal plus, matches
-- nothing, and reports the loop as missing rather than the anchor as wrong.
local loopEnd = terrain:find('ry = ry + TEXROWH', 1, true)
check(loopAt and loopEnd and loopEnd > loopAt, 'the texture row loop must be findable')
if loopAt and loopEnd then
  local body = terrain:sub(loopAt, loopEnd)
  check(body:find('S.terrainTexHover = {', 1, true),
        'the row must RECORD the hover rather than draw the enlargement')
  check(not body:find('Kit.card', 1, true),
        'and must not open a card inside the clipped region')
end
-- ...and something must actually call it, which is the half the model picker
-- needed App for.
local app = io.open('tools/save-editor/App.lua'):read('a')
check(app:match('PANELS%.terrain%.drawDeferred'),
      'App must paint the terrain panel\'s deferred layer, or the preview is '
      .. 'written and never shown')
check(terrain:match('groundOf') and terrain:match('pcall%(Loader%.load'),
      'and the panel must reach the live ground through pcall -- Loader.load '
      .. 'asserts on an unregistered map, which is the REDS_HOUSE_2F crash '
      .. 'this tool already shipped once')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
