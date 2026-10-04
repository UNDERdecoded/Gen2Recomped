-- Run:  texlua tools/gen4_terrain_paint_check.lua <cache dir>
--
-- PAINTING SINNOH'S GROUND -- the TERRAIN tool, the catalogue behind it, and
-- the two-array invariant it has to keep.
--
-- Reported: *"the map painter tiles arent working at all for platinum nothing
-- shows"*, then *"since gen4 doesnt have a tileset we need a way to paint
-- terrain textures too"*.
--
-- The empty palette was correct. `Tiles.blockCount` answers 0 for a stand-in
-- tileset, and the stand-in is synthesised artwork with no `blocks` table --
-- offering its 256 reported metatiles as brushes meant 256 swatches that wrote
-- block ids into a map whose picture is a mesh and never reads them. What was
-- missing was not a fix to that palette; it was the OTHER palette.
--
-- Section 1 is the measurement everything else rests on, taken over the real
-- cache rather than assumed, and it is also the defect's own description: if
-- the relationship between the two arrays is not what it says, the painter is
-- writing something the cartridge does not mean.

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
local Terrain4 = require('tools.map-editor.Gen4Terrain')
local Edits = require('tools.map-editor.MapEdits')
local Behaviors = require('src.import.Gen4Behaviors')
local Gen4Maps = require('src.import.Gen4Maps')

-- ======================================================= 1. the cartridge's rule
--
-- `blocks[i] == 255`  <=>  the cell is blocked
-- `blocks[i] == behaviorCells[i]`  otherwise
--
-- A CHECK THAT CANNOT FIND ITS SUBJECT FAILS. The cache is this section's
-- subject; without it the invariant is unmeasured and saying so as a pass
-- would be the measurement that cannot fail.
local maps
if cacheDir then
  local f = loadfile(cacheDir .. '/maps.lua')
  if f then local ok, t = pcall(f); if ok then maps = (t.maps or t) end end
end
check(type(maps) == 'table',
      'no map cache at ' .. tostring(cacheDir) .. '/maps.lua -- section 1 is '
      .. 'the measurement the painter is built on and cannot be skipped')

if type(maps) == 'table' then
  local nmaps, cells, viol, collBit, blocked255 = 0, 0, 0, 0, 0
  local behaviours = {}
  for _, def in pairs(maps) do
    if type(def) == 'table' and type(def.blocks) == 'string'
       and type(def.behaviorCells) == 'string' and def.width and def.height then
      nmaps = nmaps + 1
      for i = 1, def.width * def.height do
        local lo, hi = def.blocks:byte(2 * i - 1, 2 * i)
        local bb = def.behaviorCells:byte(i)
        if lo and hi and bb then
          local u16 = lo + hi * 256
          local mt = u16 % 1024
          cells = cells + 1
          if u16 >= 0x8000 then collBit = collBit + 1 end
          if mt == Gen4Maps.BLOCKED_CELL then blocked255 = blocked255 + 1
          elseif mt ~= bb then viol = viol + 1 end
          behaviours[bb] = true
        end
      end
    end
  end
  check(nmaps >= 300, 'the cache must carry the behaviour array on at least '
        .. '300 maps, or this is not the Platinum cache; got ' .. nmaps)
  check(cells > 800000, 'and over 800,000 cells to measure over; got ' .. cells)
  check(viol == 0, 'THE INVARIANT: every cell must be either metatile 255 or '
        .. 'equal to its behaviour byte. ' .. viol .. ' cells are neither, so '
        .. 'MapEdits.writeTerrainCell is deriving the wrong picture')
  check(blocked255 > cells * 0.4,
        'and blocking must be common enough for 255 to be the real marker -- '
        .. 'got ' .. blocked255 .. ' of ' .. cells)
  -- THE TRAP. `Gen4Maps.COLLISION` exists and is never used, so a painter that
  -- toggled it would be a control with no effect anywhere. Measured, because
  -- "the field exists" is exactly the evidence that would mislead.
  check(collBit == 0, 'Gen4Maps.COLLISION (0x8000) must be set on ZERO cells -- '
        .. 'if the cartridge does use the bit then blocking is not metatile 255 '
        .. 'alone and the painter is wrong; got ' .. collBit)
  local distinct = 0
  for _ in pairs(behaviours) do distinct = distinct + 1 end
  check(distinct >= 90, 'and the cartridge must use at least 90 distinct '
        .. 'behaviours, which is why the palette is grouped rather than flat; '
        .. 'got ' .. distinct)
end

-- ================================================================ 2. the palette
local offered = 0
for b = 0, 255 do if Terrain4.offers(b) then offered = offered + 1 end end
check(offered == 108, 'the palette must offer the 108 named behaviours -- the '
      .. 'other 148 are UNUSED_xNN placeholders and a swatch nobody can '
      .. 'explain is a brush nobody should reach for; got ' .. offered)
check(not Terrain4.offers(0x3A) or not (Behaviors.name(0x3A) or ''):match('^UNUSED'),
      'and must never offer a behaviour whose name starts UNUSED')

local groups = Terrain4.groups()
check(#groups >= 14, 'the palette must be grouped by terrain class, got ' .. #groups)
local total, seen = 0, {}
for _, g in ipairs(groups) do
  check(#g.entries > 0, 'class ' .. tostring(g.name) .. ' must not be an empty '
        .. 'heading -- a caption over no swatches reads as a palette that '
        .. 'failed to load')
  for _, e in ipairs(g.entries) do
    total = total + 1
    check(not seen[e.behaviour], 'behaviour ' .. e.behaviour .. ' appears in two '
          .. 'classes -- one brush in two places is two brushes to the user')
    seen[e.behaviour] = true
  end
end
check(total == offered, 'every offered behaviour must land in exactly one group: '
      .. 'grouped ' .. total .. ' of ' .. offered .. ' -- a behaviour in no '
      .. 'group is a brush that exists and cannot be reached')
check(#Terrain4.entries() == offered, 'and the flat list must agree with the '
      .. 'grouped one, or "the next brush" skips entries')

-- The swatch colour and the artwork colour are the SAME table, which is the
-- point: picking green must paint the green the editor then draws.
local Tileset = require('src.import.Gen4Tileset')
local r, g2, b2 = Terrain4.colorOf(2)                       -- TALL_GRASS
local cls = Tileset.classOf(2)
check(cls and cls.name == 'grass', 'TALL_GRASS must classify as grass')
check(math.abs(r - cls.color[1] / 255) < 1e-9
      and math.abs(g2 - cls.color[2] / 255) < 1e-9
      and math.abs(b2 - cls.color[3] / 255) < 1e-9,
      'the palette swatch must be the stand-in artwork\'s own class colour, '
      .. 'not a second table that happens to match today')
check(Terrain4.label(2) == 'TALL_GRASS', 'and the label must be the cartridge\'s '
      .. 'own name, so it can be looked up in pokeplatinum; got '
      .. tostring(Terrain4.label(2)))

-- ============================================== 3. the writer keeps both arrays
local function freshDef(w, h, behaviour)
  local blocks, behav = {}, {}
  for _ = 1, w * h do
    blocks[#blocks + 1] = string.char(behaviour % 256, 0)
    behav[#behav + 1] = string.char(behaviour % 256)
  end
  return { id = 'T01', width = w, height = h, generation = 4,
           blocks = table.concat(blocks),
           behaviorCells = table.concat(behav) }
end

local def = freshDef(4, 4, 0)
check(Terrain4.appliesTo(def), 'a def with both arrays must be paintable')
local bb, blk = Terrain4.readCell(def, 1, 1)
check(bb == 0 and blk == false, 'and read back as behaviour 0, unblocked')

check(Edits.writeTerrainCell(def, 1, 1, 21, false), 'writing WATER_SEA must work')
bb, blk = Terrain4.readCell(def, 1, 1)
check(bb == 21, 'the behaviour array must carry it, got ' .. tostring(bb))
check(blk == false, 'and the cell must still be passable')
local at = (1 * 4 + 1) * 2 + 1
local lo, hi = def.blocks:byte(at, at + 1)
check((lo + hi * 256) % 1024 == 21,
      'and the PICTURE array must carry it too -- this is the pair that must '
      .. 'never disagree, got ' .. tostring((lo + hi * 256) % 1024))

-- Block it, and the behaviour must survive: a blocked water cell is still
-- water, and unblocking must give the water back rather than bare ground.
check(Edits.writeTerrainCell(def, 1, 1, 21, true), 'blocking must work')
bb, blk = Terrain4.readCell(def, 1, 1)
check(blk == true, 'the cell must now be blocked')
check(bb == 21, 'and its behaviour must be KEPT under the block, got ' .. tostring(bb))
lo, hi = def.blocks:byte(at, at + 1)
check((lo + hi * 256) % 1024 == 255,
      'and the picture must be metatile 255, which is how Sinnoh blocks a cell')
check((lo + hi * 256) < 0x8000,
      'and the 0x8000 collision bit must NOT be set -- the cartridge never '
      .. 'sets it, so a painter that does is writing a state no map has')
check(Edits.writeTerrainCell(def, 1, 1, 21, false), 'unblocking must work')
lo, hi = def.blocks:byte(at, at + 1)
check((lo + hi * 256) % 1024 == 21,
      'and must restore the water rather than leaving bare ground')

-- Out of range is refused, not appended: a write past the end would grow the
-- string and leave a hole the renderer reads as a nil cell.
check(not Edits.writeTerrainCell(def, 4, 0, 1, false), 'x past the edge refused')
check(not Edits.writeTerrainCell(def, 0, 4, 1, false), 'y past the edge refused')
check(not Edits.writeTerrainCell(def, -1, 0, 1, false), 'negative x refused')
check(#def.behaviorCells == 16 and #def.blocks == 32,
      'and neither array may change length, got '
      .. #def.behaviorCells .. '/' .. #def.blocks)
-- A map with no behaviour array cannot be painted, and must say so rather than
-- half-writing the picture.
check(not Edits.writeTerrainCell({ width = 2, height = 2,
                                   blocks = string.rep('\0', 8) }, 0, 0, 1, false),
      'a def with no behaviour array must refuse the write outright')

-- ====================================== 4. the store, and the re-import promise
local store = {}
check(Edits.setTerrain(store, 'platinum', 'T01', 3, 2, 33, false),
      'storing a terrain edit must work')
local sb, sk = Edits.terrainAt(store, 'platinum', 'T01', 3, 2)
check(sb == 33 and sk == false, 'and read back, got ' .. tostring(sb))
check(Edits.terrainAt(store, 'platinum', 'T01', 0, 0) == nil,
      'an unpainted cell must read nil, not "ground, passable" -- a caller that '
      .. 'took the default would paint the whole map on the first click')

-- MERGED, not replaced. Painting then blocking is two calls about one cell and
-- neither may discard the other's decision.
check(Edits.setTerrain(store, 'platinum', 'T01', 3, 2, nil, true), 'blocking it')
sb, sk = Edits.terrainAt(store, 'platinum', 'T01', 3, 2)
check(sb == 33, 'the behaviour must survive a blocking edit, got ' .. tostring(sb))
check(sk == true, 'and the block must be recorded')
check(Edits.setTerrain(store, 'platinum', 'T01', 3, 2, 21, nil), 'repainting it')
sb, sk = Edits.terrainAt(store, 'platinum', 'T01', 3, 2)
check(sb == 21 and sk == true,
      'and repainting must not silently unblock the cell, got '
      .. tostring(sb) .. '/' .. tostring(sk))

-- ...AND IT COMES BACK ONTO A FRESHLY EXTRACTED MAP. This is the whole promise
-- of the patch store: a ROM re-import must not lose the edit.
local reimported = freshDef(4, 4, 12)
Edits.applyToMap(store, 'platinum', 'T01', reimported)
bb, blk = Terrain4.readCell(reimported, 3, 2)
check(bb == 21, 'a stored terrain edit must survive a re-import, got ' .. tostring(bb))
check(blk == true, 'blocking included')
local a2 = (2 * 4 + 3) * 2 + 1
lo, hi = reimported.blocks:byte(a2, a2 + 1)
check((lo + hi * 256) % 1024 == 255,
      'and applyToMap must keep the invariant, not just the behaviour array')
bb = Terrain4.readCell(reimported, 0, 0)
check(bb == 12, 'and must leave every unpainted cell alone, got ' .. tostring(bb))

-- An edit counts as an edit, or the "edited" filter and the unsaved-work
-- warning both lie about a map that has been painted.
check(Edits.count(store, 'platinum', 'T01') >= 1,
      'a terrain edit must count toward the map\'s edit total, or the picker\'s '
      .. '"edited" filter and the unsaved-changes prompt both miss it')

-- ====================== 4b. blocking a cell nobody painted (a planted-fault find)
--
-- `setBlocked` has no behaviour to offer -- blocking a cell says nothing about
-- what it is made of -- so it calls through with nil. The first version of
-- that path resolved the pair with an `and`/`or` chain and CRASHED on a cell
-- with no prior edit, which is every cell the first time it is walled off.
-- Found by a planted fault that was aimed at something else.
local s2 = {}
local okBlock = pcall(Edits.setTerrain, s2, 'platinum', 'T01', 1, 1, nil, true)
check(okBlock, 'blocking a cell that was never painted must not raise -- this '
      .. 'is the first click on every wall the user draws')
local b4, k4 = Edits.terrainAt(s2, 'platinum', 'T01', 1, 1)
check(k4 == true, 'and must record the block')
check(b4 == nil, 'and must NOT invent a behaviour for it: storing 0 would pin '
      .. 'the cell to NONE and flatten the terrain under every wall, got '
      .. tostring(b4))

-- ...and on the way back out, the nil must mean "keep what the cartridge has".
local walled = freshDef(4, 4, 21)                           -- a map of WATER_SEA
Edits.applyToMap(s2, 'platinum', 'T01', walled)
local wb, wk = Terrain4.readCell(walled, 1, 1)
check(wk == true, 'the wall must apply to a freshly extracted map')
check(wb == 21, 'and the water under it must be KEPT -- a blocked river cell is '
      .. 'still a river, and a re-import must not turn it into bare ground; got '
      .. tostring(wb))

-- The same at the writer, directly: nil behaviour reads the def.
local keep = freshDef(2, 2, 161)                            -- SNOW_DEEP
check(Edits.writeTerrainCell(keep, 0, 0, nil, true),
      'writeTerrainCell must accept a nil behaviour')
local kb, kk = Terrain4.readCell(keep, 0, 0)
check(kb == 161 and kk == true,
      'and must block the cell while keeping the snow, got '
      .. tostring(kb) .. '/' .. tostring(kk))

local function slurp(p)
  local f = io.open(p, 'rb'); if not f then return '' end
  local s = f:read('*a'); f:close(); return s
end
local pan = slurp('tools/map-editor/panels/Terrain.lua')

-- =============================================== 4c. the height override layer
--
-- Gen 4 heights are BDHC PLANES -- a height is evaluated at a point, never
-- stored -- so there is no array to patch and the editor adds an override
-- layer. Measured over all 666 chunks before any of it was written: 8,974
-- plates, 88.8% flat, heights -96..480, every common value a multiple of 8
-- (half a tile at tileUnits 16). The panel's step and clamp are those numbers.
local Panel = require('tools.map-editor.panels.Terrain')
local Ground = require('src.render.Gen4Ground')

check(Panel.HEIGHT_STEP == 8, 'the height step must be the cartridge\'s own 8 '
      .. 'world units -- half a tile, and the gcd of every common BDHC height; '
      .. 'got ' .. tostring(Panel.HEIGHT_STEP))
check(Panel.HEIGHT_MIN == -96 and Panel.HEIGHT_MAX == 480,
      'and the range must be the measured -96..480, not a round number someone '
      .. 'liked; got ' .. tostring(Panel.HEIGHT_MIN) .. '..'
      .. tostring(Panel.HEIGHT_MAX))

check(Edits.MAP_FIELDS.gen4HeightEdits == 'table',
      'gen4HeightEdits must be in MAP_FIELDS or the allow-list refuses every '
      .. 'height edit silently -- which is exactly how the `mat` field was lost')

-- The override is consulted by the renderer, on the LIST as well as the single
-- answer: `heightAt` returns `list[1]`, so an override honoured only there
-- would leave a walker that asked for the list reading the cartridge.
-- CARRIES THE BDHC PATH'S OWN FIELDS TOO, so that removing the override from
-- `heightsAt` makes this assertion FAIL rather than raise. A fake that crashes
-- when the subject regresses is still a detection, but it reports "error in
-- Gen4Ground" instead of naming the rule that broke.
local g = setmetatable({ def = { gen4HeightEdits = { ['3,4'] = 64 } },
                         offsetX = 0, offsetY = 0,
                         terrain = { chunkTiles = 32, tileUnits = 16,
                                     chunkUnits = 512 },
                         grid = { width = 0, height = 0, land = {} } },
                       { __index = Ground })
check(g:heightOverride(3, 4) == 64, 'heightOverride must read the sparse table')
check(g:heightOverride(3, 5) == nil, 'and answer nil off the edited cell')
local list = Ground.heightsAt(g, 3, 4)
check(type(list) == 'table' and list[1] == 64 and #list == 1,
      'heightsAt must answer the override BEFORE touching the BDHC, as one '
      .. 'surface; got ' .. tostring(list and list[1]) .. ' / ' .. tostring(list and #list))
local one = Ground.heightAt(g, 3, 4)
check(one == 64, 'and heightAt must agree with it, got ' .. tostring(one))

-- A def with no edits must not be changed by the existence of the layer: the
-- override must be invisible on every unedited cell, which is 100% of a
-- freshly imported map.
-- The fall-through fake carries the fields the BDHC path reads, so that what
-- is being tested is the override returning nil and NOT an early error: a
-- `pcall` around a bare table would pass for the wrong reason.
local plain = setmetatable({ def = {}, offsetX = 0, offsetY = 0,
                             terrain = { chunkTiles = 32, tileUnits = 16,
                                         chunkUnits = 512 },
                             grid = { width = 0, height = 0, land = {} } },
                           { __index = Ground })
check(plain:heightOverride(3, 4) == nil,
      'a map with no height edits must have no override -- the layer must cost '
      .. 'an unedited map nothing')
local okFall, fell = pcall(Ground.heightsAt, plain, 3, 4)
check(okFall and type(fell) == 'table' and #fell == 0,
      'and must fall through to the BDHC path rather than returning the '
      .. 'override early; got ' .. tostring(okFall) .. '/' .. tostring(fell))

-- The per-tile cache holds the OLD height, so an edit has to drop it.
local cached = setmetatable({ def = {}, riseCache = { [1] = 7 } },
                            { __index = Ground })
check(Ground.dropHeightCache(cached) == cached, 'dropHeightCache returns self')
check(cached.riseCache == nil, 'and must clear the per-tile height cache, or '
      .. 'the sprite stays at the previous height until something else drops it')

-- A height edit must survive a re-import, through the same field models use.
local hs = {}
check(Edits.setMapField(hs, 'platinum', 'T01', 'gen4HeightEdits',
                        { ['1,1'] = 32 }),
      'storing a height map must be accepted by the allow-list')
local hdef = freshDef(4, 4, 0)
Edits.applyToMap(hs, 'platinum', 'T01', hdef)
check(type(hdef.gen4HeightEdits) == 'table' and hdef.gen4HeightEdits['1,1'] == 32,
      'and must come back onto a freshly extracted map, got '
      .. tostring(hdef.gen4HeightEdits and hdef.gen4HeightEdits['1,1']))

-- The panel must offer height controls at all, and must say what they move:
-- BDHC lifts what STANDS on the ground, not the drawn mesh, and a control
-- named "height" that silently meant half of that would read as broken.
check(pan:match('T%.setHeight'), 'the panel must expose a height setter')
check(pan:match('dropHeightCache'),
      'and must drop the renderer\'s height cache after writing one')
check(pan:match('NSBMD'), 'and must state in the file that BDHC moves what '
      .. 'stands on the ground rather than the drawn hill -- the name promises '
      .. 'more than the layer does')

-- ============================== 4d. the panel, DRIVEN -- not read as source text
--
-- THE SECTION THAT CAUGHT A SHIPPED BUG, and the reason it exists.
--
-- `S.pvCell` is written in exactly one place, `Preview.lua`, as
-- `{ cx = cx, cy = cy }`. The first version of this panel read `cell.x`. That
-- is nil, so the header printed nothing, both buttons acted on cell nil and
-- the height controls never drew -- the tool was inert. It got through a
-- 200-check pass because every assertion about the panel was a source-text
-- match, and `pan:match('T%.setHeight')` is perfectly true of a file that
-- calls `T.setHeight(S, nil, nil, ...)`.
--
-- A NAME IS NOT A CALL, and a call is not a CORRECT call. The only assertion
-- that could see this is one that presses the button and looks at the cell.
local pressed = {}
local function fakeKit(wantButton, wantStepper)
  local K = { scale = 1, texts = {} }
  K.textHeight = function() return 12 end
  K.text = function(_, msg) K.texts[#K.texts + 1] = tostring(msg) end
  K.caption = function(_, _, msg) K.texts[#K.texts + 1] = tostring(msg) end
  K.card = function() end
  K.row = function() end
  K.press = function() return false end
  K.hit = function() return false end
  K.blockClicks = function() end
  K.pushClip = function() end
  K.popClip = function() end
  K.button = function(_, _, _, _, label)
    if label == wantButton then pressed[label] = true; return true end
    return false
  end
  K.stepper = function(_, _, _, _, label)
    if label == wantStepper then pressed['step' .. label] = true; return true end
    return false
  end
  return K
end

local function panelState()
  local d = freshDef(8, 8, 0)
  return { mapId = 'T01', version = 'platinum', mapEdits = {},
           pvCell = { cx = 3, cy = 5 }, terrainBrush = 21,
           data = { maps = { T01 = d }, tilesets = {}, constants = {} } }, d
end

-- The header must name the cell the user picked. If `cell.cx` were read as
-- `cell.x` this raises inside string.format on a nil, which is itself the
-- detection -- so the assertion is that drawing SUCCEEDS and says 3, 5.
local S1, d1 = panelState()
local K1 = fakeKit(nil, nil)
local okDraw, drawErr = pcall(Panel.draw, S1, K1, 0, 0, 300, 600)
check(okDraw, 'drawing the panel with a selected cell must not raise: '
      .. tostring(drawErr))
local said = table.concat(K1.texts, ' | ')
check(said:match('CELL 3, 5'),
      'the panel must name the picked cell -- S.pvCell is {cx,cy} and reading '
      .. 'it as {x,y} gives nil. Said: ' .. said:sub(1, 160))

-- PAINT must write the brush to THAT cell and no other.
local S2, d2 = panelState()
local okP = pcall(Panel.draw, S2, fakeKit('Paint cell', nil), 0, 0, 300, 600)
check(okP, 'pressing Paint cell must not raise')
check(pressed['Paint cell'], 'and the harness must actually have pressed it, or '
      .. 'the assertion below proves nothing')
check(Terrain4.readCell(d2, 3, 5) == 21,
      'Paint cell must write the brush to the picked cell (3,5), got '
      .. tostring(Terrain4.readCell(d2, 3, 5)))
check(Terrain4.readCell(d2, 0, 0) == 0,
      'and must leave every other cell alone, got '
      .. tostring(Terrain4.readCell(d2, 0, 0)))

-- BLOCK must block that cell, and keep what is under it.
local S3, d3 = panelState()
Edits.writeTerrainCell(d3, 3, 5, 21, false)
local okB = pcall(Panel.draw, S3, fakeKit('Block cell', nil), 0, 0, 300, 600)
check(okB, 'pressing Block cell must not raise')
local b3, k3 = Terrain4.readCell(d3, 3, 5)
check(k3 == true, 'Block cell must block the picked cell')
check(b3 == 21, 'and keep the water under it, got ' .. tostring(b3))

-- NO CELL PICKED is a normal state and must draw, not raise.
local S4 = select(1, panelState()); S4.pvCell = nil
local okN, nErr = pcall(Panel.draw, S4, fakeKit(nil, nil), 0, 0, 300, 600)
check(okN, 'the panel must draw with no cell picked: ' .. tostring(nErr))

-- A map with no terrain layer must draw its explanation, and must still fill
-- the body -- the early-return path is the one most likely to leave a band.
local S5 = select(1, panelState())
S5.data.maps.T01 = { id = 'T01', width = 4, height = 4 }
local K5 = fakeKit(nil, nil)
local okE = pcall(Panel.draw, S5, K5, 0, 0, 300, 600)
check(okE, 'a map with no behaviour array must still draw')
check(table.concat(K5.texts, ' '):match('no terrain layer'),
      'and must say so rather than showing an empty palette')

-- ====================== 4e. a map with no terrain layer at all (a new map)
--
-- Reported while creating a new Platinum map: TERRAIN said "this map has no
-- terrain layer yet" and offered nothing to do about it. For a map the editor
-- INVENTED that message was also misleading -- it told the author to re-import
-- the ROM, and no re-import can ever help a map that has no `map_layouts`
-- entry behind it to resolve a behaviour array FROM.
local blank = { id = 'NEW', width = 6, height = 4, blocks = {} }
for i = 1, 24 do blank.blocks[i] = 0 end
check(not Terrain4.appliesTo(blank),
      'a created map must not look paintable before it has a layer')

local cstore = {}
local okNew, whyNew = Edits.createTerrainLayer(cstore, 'platinum', 'NEW', blank)
check(okNew, 'creating a terrain layer must work: ' .. tostring(whyNew))
check(Terrain4.appliesTo(blank), 'and the map must then be paintable')
check(#blank.behaviorCells == 24, 'with one behaviour byte per cell, got '
      .. #blank.behaviorCells)
check(#blank.blocks == 48, 'and two picture bytes per cell, got ' .. #blank.blocks)
local nb, nk = Terrain4.readCell(blank, 3, 2)
check(nb == 0 and nk == false,
      'every cell must start as NONE and walkable -- that is what the '
      .. 'cartridge\'s own open ground is, not a guess; got '
      .. tostring(nb) .. '/' .. tostring(nk))
-- and it is immediately paintable, which is the whole point
check(Edits.writeTerrainCell(blank, 3, 2, 21, false), 'and paintable at once')
check(Terrain4.readCell(blank, 3, 2) == 21, 'with the paint landing')

-- REFUSING THE DESTRUCTIVE CASE. Rebuilding over a painted map would flatten
-- every cell back to bare ground, which is the worst thing this function could
-- do, so it must decline rather than succeed quietly.
local okAgain, whyAgain = Edits.createTerrainLayer(cstore, 'platinum', 'NEW', blank)
check(not okAgain, 'creating a layer twice must be refused')
check(tostring(whyAgain):find('already'), 'and say why, got ' .. tostring(whyAgain))
check(Terrain4.readCell(blank, 3, 2) == 21,
      'and must not have touched the paint that was already there')

-- A created map IS its stored record, so the layer has to land there too or it
-- lasts exactly until the next load.
-- A SEPARATE DEF TABLE, NOT THE STORED RECORD ITSELF.
--
-- The first version of this handed `g.newMaps[id]` in as the def, so the
-- function writing `def.behaviorCells` set the stored record by identity and
-- the assertion passed whether or not the write-back existed -- deleting the
-- write-back left it green. Shape 6a: setup that mirrors the subject grades
-- the mirror. The live def and the stored record are two tables in the editor,
-- so the test uses two.
local cs2 = { games = { platinum = { newMaps = { NEW2 = { width = 2, height = 2 } } } } }
local liveDef = { id = 'NEW2', width = 2, height = 2 }
check(Edits.createTerrainLayer(cs2, 'platinum', 'NEW2', liveDef),
      'creating a layer on a stored new map')
check(type(liveDef.behaviorCells) == 'string', 'the live def must carry it')
check(type(cs2.games.platinum.newMaps.NEW2.behaviorCells) == 'string',
      'and so must the STORED record -- a created map is its record, so a '
      .. 'layer written only to the live def lasts until the next load')
check(type(cs2.games.platinum.newMaps.NEW2.blocks) == 'string',
      'both halves of it, or the stored map comes back with a behaviour array '
      .. 'and no picture')

-- ...and it must survive the allow-list. `blocks` is a packed STRING on Gen
-- 3/4 and an array on Gen 1/2; the allow-list said "table", so every Gen 4
-- grid that went through typedCopy was dropped silently.
local kept = Edits.createMap({}, 'platinum',
  { name = 'T', width = 2, height = 2,
    blocks = string.rep(string.char(0, 0), 4),
    behaviorCells = string.rep(string.char(0), 4) })
check(kept ~= nil, 'createMap must accept a Gen 4 spec')
local _, spec = Edits.createMap({}, 'platinum',
  { name = 'T', width = 2, height = 2,
    blocks = string.rep(string.char(0, 0), 4),
    behaviorCells = string.rep(string.char(0), 4) })
check(type(spec.behaviorCells) == 'string',
      'behaviorCells must survive the allow-list, or a created Gen 4 map is '
      .. 'given a layer and loses it on the next round trip')
check(type(spec.blocks) == 'string' and #spec.blocks == 8,
      'and the packed STRING grid must survive it too -- the allow-list said '
      .. '"table", which is the Gen 1/2 shape, so every Gen 4 grid that went '
      .. 'through typedCopy was dropped and silently rebuilt as flat fill; got '
      .. type(spec.blocks) .. ' of ' .. tostring(#tostring(spec.blocks)))

-- A map with no size cannot have a layer, and must say so rather than
-- allocating a zero-length one that looks valid.
check(not Edits.createTerrainLayer({}, 'platinum', 'X', { width = 0, height = 0 }),
      'a map with no size must be refused')
check(not Edits.createTerrainLayer({}, 'platinum', 'X',
                                   { width = 99999, height = 99999 }),
      'and an absurd one must be refused rather than allocating gigabytes')

-- ================================= 4f. the texture painter, and its mode switch
--
-- The behaviour byte says what a cell IS; the texture says what it LOOKS like.
-- They are two edits on one cell, so the panel has one switch rather than two
-- tools -- and the map-view brush has to follow it, or a drag paints something
-- other than what the panel says it is painting.
local pdef = freshDef(8, 8, 0)
local S6 = { mapId = 'T01', version = 'platinum', mapEdits = {},
             pvCell = { cx = 2, cy = 3 }, terrainTexture = 'grass01',
             data = { maps = { T01 = pdef }, tilesets = {}, constants = {} } }

check(Panel.paintAt ~= nil, 'the panel must expose one entry point for the '
      .. 'map-view brush')
S6.terrainMode = 'behaviour'
S6.terrainBrush = 21
check(Panel.paintAt(S6, 2, 3), 'painting in ground-rules mode must work')
check(Terrain4.readCell(pdef, 2, 3) == 21,
      'and must write the behaviour byte, got '
      .. tostring(Terrain4.readCell(pdef, 2, 3)))
check(Terrain4.textureAt(pdef, 2, 3) == nil,
      'and must NOT touch the texture')

S6.terrainMode = 'texture'
check(Panel.paintAt(S6, 4, 5), 'painting in texture mode must work')
check(Terrain4.textureAt(pdef, 4, 5) == 'grass01',
      'and must write the texture, got '
      .. tostring(Terrain4.textureAt(pdef, 4, 5)))
check(Terrain4.readCell(pdef, 4, 5) == 0,
      'and must NOT change what the ground IS -- a path through grass is still '
      .. 'walkable ground; got ' .. tostring(Terrain4.readCell(pdef, 4, 5)))

-- The panel must offer the switch at all, and the map view must route through
-- the dispatcher rather than straight at the behaviour painter.
check(pan:match('TEXTURES'), 'the panel must offer a TEXTURES mode')
check(pan:match('GROUND RULES'), 'and name the other one')
check(pan:match('Gen4Terrain%.textures%(S%.data, def%)'),
      'and list the cartridge\'s textures to paint with')
local prev2 = slurp('tools/map-editor/panels/Preview.lua')
check(prev2:match('Terrain%.paintAt%(S, cx, cy%)'),
      'the map view must route through paintAt, or a drag always paints the '
      .. 'behaviour byte however the panel is set')

-- ================================================ 5. the tool is actually wired
local side = slurp('tools/map-editor/Sidebar.lua')
check(side:match('id%s*=%s*"terrain"'),
      'Sidebar.TOOLS must carry the terrain tool, or nothing can open it')
local app = slurp('tools/save-editor/App.lua')
check(app:match('terrain%s*=%s*TerrainPanel'),
      'App must register the panel under that id -- Sidebar.toolsFor drops a '
      .. 'tool whose panel is absent, so an unregistered panel is an invisible '
      .. 'tool rather than an error')
check(app:match('panels%.Terrain'), 'and must require it')
local prev = slurp('tools/map-editor/panels/Preview.lua')
check(prev:match('openId%(S%)%s*==%s*"terrain"'),
      'the map view must route a click to the terrain brush, or the palette '
      .. 'picks a brush that can only be applied from the sidebar button')
check(prev:match('Terrain%.paintCell%s*%(S'),
      'and must call it as a statement, not merely name it')

-- fillsBody is the contract that produced the drawer's own black bar. A panel
-- that declares it and does not use the shared region is the next one.
check(pan:match('fillsBody%s*=%s*true'), 'the panel must declare fillsBody')
check(pan:match('BodyFill%.region%s*%('),
      'and must fill the body through the shared region -- declaring the flag '
      .. 'and then flowing is exactly what left an unpainted band under MODELS')
check(pan:match('MapKind%.meshGround'),
      'and must key availability on MapKind.meshGround, not on the behaviour '
      .. 'array: only 302 of 593 defs carry that string before resolveBlocks '
      .. 'runs, so the array would hide the tool on half of Sinnoh')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
