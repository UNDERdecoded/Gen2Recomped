-- Run:  texlua tools/gen4_entrance_warp_check.lua <cache dir>
--
-- GEN 4 DOORS ARE DIRECTIONAL, AND THEY FIRE ON THE PRESS.
--
-- Reported from play: *"i cant walk directly into the cave it wont warp me,
-- but if i walk to the cave and walk horizontally while on the tile in front
-- of it it will warp me"*. One missing rule, both halves of that sentence.
--
-- Platinum puts the behaviour on the mat the player STANDS on, and it names
-- the direction that opens the door. `PlayerAvatar_WillWarp`
-- (pokeplatinum src/player_move.c) reads the behaviour under the player and
-- switches on the direction pressed, each case a single equality:
--
--     DIR_NORTH -> TileBehavior_IsWarpEntranceNorth(behaviour)
--
-- So entering is a press ON the mat, never a step ONTO it -- which is why
-- walking into a Platinum building takes two presses.

package.path = './?.lua;./?/init.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_entrance_warp_check.lua <cache dir>')
  os.exit(2)
end
local maps = assert(loadfile(cacheDir .. '/maps.lua'))()

-- The cartridge's own four bytes.
local EAST, WEST, NORTH, SOUTH = 0x62, 0x63, 0x64, 0x65

-- ================= 1. the cartridge really marks its doors with these bytes
--
-- If it did not, the whole rule would be a fiction and every assertion below
-- would be about nothing.
local withEntrance, onWarps, total = 0, 0, 0
local sample
for id, def in pairs(maps) do
  local cells = def.behaviorCells
  if type(cells) == 'string' and def.warps then
    for _, w in ipairs(def.warps) do
      if w.x and w.y and def.width then
        local b = cells:byte(w.y * def.width + w.x + 1)
        total = total + 1
        if b == EAST or b == WEST or b == NORTH or b == SOUTH then
          onWarps = onWarps + 1
          if not sample then sample = { id = id, x = w.x, y = w.y, b = b } end
        end
      end
    end
    for i = 1, #cells do
      local b = cells:byte(i)
      if b == EAST or b == WEST or b == NORTH or b == SOUTH then
        withEntrance = withEntrance + 1
        break
      end
    end
  end
end
-- MEASURED, not guessed at. 792 warps sit on maps that carry a behaviour grid
-- of their own, and 103 of those warps are on an entrance byte across 78 maps.
-- The first thresholds here were round numbers I had invented and they failed
-- on the real cache, which is the only reason these are the cartridge's
-- numbers and not mine.
check(total >= 700, 'the cache must carry Platinum warps to test, got ' .. total)
check(onWarps >= 90,
      'and a hundred-odd of them must sit on an entrance behaviour -- if none '
      .. 'do, this rule is about nothing; got ' .. onWarps .. ' of ' .. total)
check(withEntrance >= 70,
      'across many maps, got ' .. withEntrance)
-- THE SHAPE OF THAT HUNDRED IS THE POINT, and it is why the outdoor half of
-- the report needs more than this rule: they are almost all 0x65, the mat you
-- press DOWN on to leave a building. Not one warp in the cache sits on a
-- press-NORTH mat, because the maps that would carry one -- the outdoor side,
-- where you walk up into a cave mouth -- hold no behaviour grid at all. Their
-- behaviour lives in the chunk permission block, which the importer parses and
-- has never written to the cache.
check(sample, 'a sample entrance must be findable')

-- ============================ 2. the behaviour readers answer the right way
local Map = require('src.world.Map')
local function fakeMap(generation, behaviour)
  return setmetatable({
    def = { generation = generation, width = 4, height = 4 },
    widthCells = 4, heightCells = 4,
    cellBehaviour = function() return behaviour end,
  }, { __index = Map })
end

-- THE PRESS TABLE IS `Field_CheckMapTransition`'s, all eight bytes of it --
-- entrances, plain warps and staircases. The first version of this rule had
-- only the four entrance bytes, and the Route 208 cave mouth is a plain
-- WARP_WEST, so it was not in it.
local PRESS = {
  [0x5E] = 'right', [0x5F] = 'left',                  -- WARP_STAIRS_E/W
  [0x62] = 'right', [0x63] = 'left', [0x65] = 'down', -- WARP_ENTRANCE_E/W/S
  [0x6C] = 'right', [0x6D] = 'left', [0x6F] = 'down', -- WARP_E/W/S
}
for b, want in pairs(PRESS) do
  check(Map.gen4PressWarpDir(fakeMap(4, b), 0, 0) == want,
        ('0x%02X must be opened by pressing %s'):format(b, want))
end
-- North is NOT a press: the cartridge takes it on arrival.
for _, b in ipairs({ NORTH, 0x6E, 0x00, 0x69, 0x67 }) do
  check(Map.gen4PressWarpDir(fakeMap(4, b), 0, 0) == nil,
        ('0x%02X must not be a press warp'):format(b))
end
-- ...and `Field_CheckTransition`'s arrival list, exactly.
local ARRIVE = { [0x64] = true, [0x67] = true, [0x6A] = true, [0x6B] = true,
                 [0x6E] = true }
for b = 0, 255 do
  check(Map.gen4ArrivalWarpAt(fakeMap(4, b), 0, 0) == (ARRIVE[b] == true),
        ('0x%02X arrival must be %s'):format(b, tostring(ARRIVE[b] == true)))
end
check(Map.gen4ArrivalWarpAt(fakeMap(4, nil), 0, 0) == nil,
      'a cell with no behaviour must answer nil, not false')

-- EVERY EARLIER CARTRIDGE IS UNTOUCHED, which is not a nicety: 0x62 is an
-- ordinary tile id in Kanto, and reading it as a door there would disable real
-- ones. *"Make sure your additions dont break crystal, gold silver or prism"*.
for _, gen in ipairs({ 1, 2, 3 }) do
  for b in pairs(PRESS) do
    check(Map.gen4PressWarpDir(fakeMap(gen, b), 0, 0) == nil,
          'generation ' .. gen .. ' must read byte ' .. string.format('0x%02X', b)
          .. ' as nothing of the kind')
  end
  check(Map.gen4ArrivalWarpAt(fakeMap(gen, 0x6E), 0, 0) == nil,
        'generation ' .. gen .. ' must not be gated by the Gen 4 arrival list')
end

-- ============ 3. a completed step fires only the cartridge's arrival warps
local Warp = require('src.world.Warp')
local function stepMap(behaviour, warp)
  return {
    def = { generation = 4 },
    warpAtCell = function() return warp end,
    isWarpTileCell = function() return true end,
    isStepWarpCell = function() return true end,
    gen4ArrivalWarpAt = function(_, cx, cy)
      return Map.gen4ArrivalWarpAt(fakeMap(4, behaviour), cx, cy)
    end,
  }
end
local w = { def = { destMap = 'SOMEWHERE' } }
for b in pairs(PRESS) do
  for _, d in ipairs({ 'up', 'down', 'left', 'right' }) do
    check(Warp.onArrive(stepMap(b, w), 1, 1, d) == nil,
          ('a step onto 0x%02X must fire nothing, walking %s'):format(b, d))
  end
end
for _, d in ipairs({ 'up', 'down', 'left', 'right' }) do
  check(Warp.onArrive(stepMap(0x6E, w), 1, 1, d) == w,
        'a step onto WARP_NORTH fires from any direction (' .. d .. ')')
  check(Warp.onArrive(stepMap(0x69, w), 1, 1, d) == nil,
        'a step onto a door fires nothing (' .. d .. ')')
end
-- ...while a cell with no behaviour to read keeps the old answer, or every
-- door in every earlier game stops working.
check(Warp.onArrive(stepMap(nil, w), 1, 1, 'up') == w,
      'a warp cell with no behaviour must still fire from a step')

-- ================================== 4. and the press opens it
--
-- Asserted on the controller's own source: the rule has to be ASKED on the
-- press, beside the Gen 3 arrow rule, or it never runs. A function nothing
-- calls is the shape of bug this port has shipped before.
local ow = io.open('src/world/OverworldController.lua'):read('a')
check(ow:match('function OverworldState:checkGen4EntranceWarp'),
      'the press rule must exist')
local calls = select(2, ow:gsub('self:checkGen4EntranceWarp%(dir%)', ''))
check(calls == 2,
      'and must be asked at BOTH press sites, beside the Gen 3 arrow rule -- '
      .. 'got ' .. calls)

-- ============= 5. the outdoor world must HAVE a behaviour to answer with
--
-- The rule above is necessary and was not sufficient, and the gap is the whole
-- reason the cave stayed shut. Only 302 of 593 map defs carry a `behaviorCells`
-- grid; the other 291 are the outdoor maps. Their behaviour lives in the land
-- chunk's PERMISSION block, which `Gen4Terrain.chunk` has parsed since the map
-- work and `append` never wrote -- so outdoors `cellBehaviour` answered nil and
-- every rule keyed on one was off, not wrong.
local withGrid, withoutGrid = 0, 0
for _, def in pairs(maps) do
  if type(def.behaviorCells) == 'string' then withGrid = withGrid + 1
  else withoutGrid = withoutGrid + 1 end
end
check(withGrid >= 300 and withoutGrid >= 280,
      'the split must still be about 302 / 291 -- if every map grew a grid this '
      .. 'whole side-car is unnecessary; got ' .. withGrid .. ' / ' .. withoutGrid)

local imp = io.open('src/import/Gen4Terrain.lua'):read('a')
check(imp:match('entry%.permAt = state%.permsAt'),
      'the importer must carry each chunk\'s permission block into the index')
check(imp:match('entry%.permBytes = #chunk%.permissions'), 'with its length')
check(imp:match('concat%(state%.perms%)'), 'and emit the blob')
local rx = io.open('src/import/RomExtractorGen4.lua'):read('a')
check(rx:match('terrain/permissions%.bin'),
      'and the extractor must save it beside heights.bin')
check(rx:match('out%.permissionFile'), 'naming it in the cache')

local gsrc = io.open('src/render/Gen4Ground.lua'):read('a')
check(gsrc:match('function Gen4Ground:behaviourAt'),
      'the ground must read a tile\'s behaviour back out')
check(gsrc:match('terrain%.permissionFile'), 'from the side-car the cache names')
-- The low byte is the behaviour; bit 15 is the blocked flag and is not part of
-- it. Reading the whole u16 as a behaviour would make every blocked tile a
-- behaviour in the 0x80xx range, which matches nothing and silently disables
-- the rule on exactly the tiles a wall sits on.
check(gsrc:match('return word %% 256'),
      'taking the LOW BYTE -- the high bit is the blocked flag, not behaviour')
-- Bounds, DRIVEN rather than scanned: a read past this chunk's own block
-- answers another tile with complete confidence, which is worse than answering
-- nothing. A text scan could not see this move when the block stopped being a
-- slice of a side-car and became a string.
local G4 = require('src.render.Gen4Ground')
local function withBlock(block)
  return setmetatable({
    def = {}, perms = { [7] = block },
    terrain = { chunkTiles = 32, chunks = {} },
    grid = { width = 1, height = 1, land = { 7 } },
    offsetX = 0, offsetY = 0,
  }, { __index = G4 })
end
local FULL = string.rep('\000\000', 32 * 32)
check(withBlock(FULL):permissionWordAt(31, 31) == 0,
      'the last tile of a full block must still be readable')
-- One tile short, which is what a truncated or half-written block looks like.
local SHORT = string.rep('\000\000', 32 * 32 - 1)
-- pcall because the two ways of getting this wrong look different from here:
-- without the bound the read either returns a neighbouring tile's bytes or
-- raises on the half pair at the end, and a check that only tested one of
-- them would call the other a pass.
local okShort, gotShort = pcall(function()
  return withBlock(SHORT):permissionWordAt(31, 31)
end)
check(okShort and gotShort == nil,
      'a tile past the end of the block must answer nothing, not another '
        .. 'tile\'s bytes -- got '
        .. (okShort and tostring(gotShort) or ('a raise: ' .. tostring(gotShort))))
check(withBlock(SHORT):permissionWordAt(30, 31) == 0,
      'while the tile before it still reads')
check(gsrc:match('self%.permFile = nil'),
      'and the handle must be released with the map\'s others')

local msrc = io.open('src/world/Map.lua'):read('a')
check(msrc:match('renderer%.gen4Ground'),
      'and cellBehaviour must fall back to it for maps with no grid')
check(msrc:match('pcall%(ground%.behaviourAt'),
      'through pcall, so a cache written before this answers as it always did')
-- The fallback must come AFTER the def's own grid, or 302 maps start reading
-- the chunk under them instead of the behaviour they carry.
local cb = msrc:match('function Map:cellBehaviour.-\nend')
check(cb, 'cellBehaviour must be findable')
if cb then
  -- COMMENT LINES STRIPPED FIRST. This assertion passed with the fallback
  -- moved ABOVE the grid, because the comment explaining the fallback names
  -- `behaviorCells` -- so the scan found the word first and called the order
  -- right. A prose scan defeated by prose about its own subject.
  local code = {}
  for line in cb:gmatch('[^\n]*') do
    if not line:match('^%s*%-%-') then code[#code + 1] = line end
  end
  code = table.concat(code, '\n')
  local gridAt = code:find('self.def.behaviorCells', 1, true)
  local groundAt = code:find('renderer.gen4Ground', 1, true)
  check(gridAt and groundAt and gridAt < groundAt,
        'the map\'s own grid must be READ first -- 302 maps carry one, and a '
        .. 'fallback that wins would have them reading the chunk under them '
        .. 'instead of the behaviour they state')
end

-- ===================== 6. THE DOOR AND THE MAT, through the shipping rule
--
-- `Field_CheckMapTransition`, in its own order: wall ahead first, then a door
-- ahead, then the mat underfoot in its own direction. Graded on stubs so every
-- branch is reached; section 7 drives the same rule over the real maps.
local DOOR = 0x69
check(Map.gen4DoorAt(fakeMap(4, DOOR), 0, 0) == true, 'a door must be a door')
for _, b in ipairs({ 0x00, 0x62, 0x65, 0x67, 0x68, 0x6A }) do
  check(Map.gen4DoorAt(fakeMap(4, b), 0, 0) == false,
        ('0x%02X must NOT be a door'):format(b))
end
for _, gen in ipairs({ 1, 2, 3 }) do
  check(Map.gen4DoorAt(fakeMap(gen, DOOR), 0, 0) == false,
        ('generation %d must not read 0x69 as a door'):format(gen))
end

local OW = require('src.world.OverworldController')
-- A 3x3 world: the player at (1,1) standing on `under`, `cells` naming the
-- behaviour of the others, `walls` the terrain-blocked ones and `warps` the
-- cells that carry a warp event.
local function presser(under, cells, walls, warps)
  local taken = {}
  local function key(x, y) return x .. ',' .. y end
  local map = setmetatable({
    def = { generation = 4, width = 3, height = 3 },
    widthCells = 3, heightCells = 3,
    cellBehaviour = function(_, x, y)
      if x == 1 and y == 1 then return under end
      return cells[key(x, y)] or 0
    end,
    gen4TerrainBlocked = function(_, x, y) return walls[key(x, y)] == true end,
    warpAtCell = function(_, x, y)
      local d = warps[key(x, y)]
      return d and { def = d } or nil
    end,
  }, { __index = Map })
  return setmetatable({
    player = { cellX = 1, cellY = 1 },
    map = map,
    takeWarp = function(_, def) taken[#taken + 1] = def end,
  }, { __index = OW }), taken
end
local ALL_WALLS = { ['1,0'] = true, ['1,2'] = true, ['0,1'] = true, ['2,1'] = true }

-- A door ahead opens on the press into it, and on nothing else.
do
  local s, taken = presser(0, { ['1,0'] = DOOR }, ALL_WALLS, { ['1,0'] = 'DOOR' })
  check(s:checkGen4EntranceWarp('up') == true and taken[1] == 'DOOR',
        'pressing INTO a door must take the warp sitting ON the door')
  for _, d in ipairs({ 'down', 'left', 'right' }) do
    local s2, t2 = presser(0, { ['1,0'] = DOOR }, ALL_WALLS, { ['1,0'] = 'DOOR' })
    check(s2:checkGen4EntranceWarp(d) == false and #t2 == 0,
          'pressing away from a door must not open it (' .. d .. ')')
  end
end
do
  local s = presser(0, { ['1,0'] = DOOR }, ALL_WALLS, {})
  check(s:checkGen4EntranceWarp('up') == false,
        'a door carrying no warp event must be refused quietly')
end

-- A mat underfoot opens on the press its behaviour names and on no other --
-- the Route 208 mouth, WARP_WEST, and the Mt. Coronet exit, WARP_EAST.
for b, want in pairs(PRESS) do
  for _, d in ipairs({ 'up', 'down', 'left', 'right' }) do
    local s, taken = presser(b, {}, ALL_WALLS, { ['1,1'] = 'MAT' })
    local got = s:checkGen4EntranceWarp(d)
    check(got == (d == want) and #taken == ((d == want) and 1 or 0),
          ('0x%02X underfoot, pressing %s: want %s'):format(b, d,
            tostring(d == want)))
  end
end
-- ...but only into a wall. A press toward open ground is a step.
for b, want in pairs(PRESS) do
  local s, taken = presser(b, {}, {}, { ['1,1'] = 'MAT' })
  check(s:checkGen4EntranceWarp(want) == false and #taken == 0,
        ('0x%02X with open ground %s must step, not warp'):format(b, want))
end
-- North is arrival-only; plain ground under a warp event is a script's.
for _, b in ipairs({ 0x6E, NORTH, 0x00 }) do
  for _, d in ipairs({ 'up', 'down', 'left', 'right' }) do
    local s, taken = presser(b, {}, ALL_WALLS, { ['1,1'] = 'MAT' })
    check(s:checkGen4EntranceWarp(d) == false and #taken == 0,
          ('0x%02X underfoot must not open on a press %s'):format(b, d))
  end
end
-- Standing ON a door, any press into a wall takes it.
do
  local s, taken = presser(DOOR, {}, ALL_WALLS, { ['1,1'] = 'ON_DOOR' })
  check(s:checkGen4EntranceWarp('left') == true and taken[1] == 'ON_DOOR',
        'standing on a door, a press into a wall takes it')
end

-- ======================= 7. THE REPORTED CAVE, ON THE CARTRIDGE'S OWN MAPS
--
-- Route 208's Mt. Coronet mouth and the exit inside, read out of the cache and
-- driven through the shipping `Map`, `Warp.onArrive` and press rule. These are
-- the coordinates from the report; if the cache moves them, this says so.
local okData, layouts = pcall(function()
  return assert(loadfile(cacheDir .. '/map_layouts.lua'))()
end)
check(okData, 'the cache must carry map_layouts.lua')
if okData then
  local MapLoader = require('src.world.MapLoader')
  local ts = require('src.import.Gen4Tileset').pair()
  local data = { maps = maps, map_layouts = layouts }
  local built = {}
  local function real(id)
    built[id] = built[id] or Map.new(MapLoader.resolveBlocks(data, maps[id]), ts)
    return built[id]
  end
  local function press(id, x, y, d)
    local taken = {}
    local s = setmetatable({
      player = { cellX = x, cellY = y }, map = real(id),
      takeWarp = function(_, def) taken[#taken + 1] = def end,
    }, { __index = OW })
    return s:checkGen4EntranceWarp(d), taken[1]
  end

  -- OUTSIDE: (8,20) is WARP_WEST, the wall (7,20) is the mouth.
  local r208 = real('R208')
  check(r208:gen4PressWarpDir(8, 20) == 'left',
        'Route 208 (8,20) must be the WARP_WEST mouth')
  local ok, def = press('R208', 8, 20, 'left')
  check(ok and def and def.destMap == 'D05R0101',
        'standing on the mouth and pressing LEFT must enter Mt. Coronet')
  for _, d in ipairs({ 'up', 'down', 'right' }) do
    check(press('R208', 8, 20, d) == false,
          'and pressing ' .. d .. ' on it must not')
  end
  for _, d in ipairs({ 'up', 'down', 'left', 'right' }) do
    check(Warp.onArrive(r208, 8, 20, d) == nil,
          'walking ' .. d .. ' ONTO the mouth must not warp by itself')
  end
  check(press('R208', 9, 20, 'left') == false,
        'the tile beside the mouth is open ground: the press is a step')
  -- THE ROOT OF THE REPORT. The Gen 4 stand-in tileset says its warps are
  -- events, so the Gen 3 arrow rule ran here too -- and Hoenn's 0x6D is
  -- MB_WATER_SOUTH_ARROW_WARP. The mouth opened on DOWN and refused LEFT.
  check(r208:arrowWarpDirAt(8, 20) == nil,
        'the Gen 3 arrow rule must not read a Sinnoh tile (0x6D is not "down")')
  for _, d in ipairs({ 'up', 'down', 'left', 'right' }) do
    local s = setmetatable({
      player = { cellX = 8, cellY = 20 }, map = r208,
      takeWarp = function() error('the Gen 3 arrow rule warped on Gen 4') end,
    }, { __index = OW })
    check(s:checkGen3ArrowWarp(d) == false,
          'and the Gen 3 press rule must not fire on the mouth (' .. d .. ')')
  end

  -- INSIDE: (27,20) is WARP_EAST, the wall (28,20) is the way out.
  local cave = real('D05R0101')
  check(cave:gen4PressWarpDir(27, 20) == 'right',
        'Mt. Coronet (27,20) must be the WARP_EAST exit')
  ok, def = press('D05R0101', 27, 20, 'right')
  check(ok and def and def.destMap == 'R208',
        'standing on the exit and pressing RIGHT must leave for Route 208')
  for _, d in ipairs({ 'up', 'down', 'left', 'right' }) do
    check(Warp.onArrive(cave, 27, 20, d) == nil,
          'walking ' .. d .. ' onto the exit must NOT throw the player out')
  end
  for _, at in ipairs({ { 27, 19, 'down' }, { 27, 21, 'up' } }) do
    check(press('D05R0101', at[1], at[2], at[3]) == false,
          ('pressing %s from (%d,%d) next to the exit must not leave')
            :format(at[3], at[1], at[2]))
  end

  -- AND EVERY WARP IN SINNOH IS STILL REACHABLE under the two rules: a door
  -- is a wall to press into, and a mat has a wall in the direction it names.
  local DX = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local doors, doorsShut, mats, matsShut, arrivals = 0, 0, 0, 0, 0
  for id, d in pairs(maps) do
    local okM, m = pcall(real, id)
    if okM and d.warps then
      for _, wp in ipairs(d.warps) do
        if m:gen4DoorAt(wp.x, wp.y) then
          doors = doors + 1
          if m:gen4TerrainBlocked(wp.x, wp.y) then doorsShut = doorsShut + 1 end
        end
        local pd = m:gen4PressWarpDir(wp.x, wp.y)
        if pd then
          mats = mats + 1
          local v = DX[pd]
          if m:gen4TerrainBlocked(wp.x + v[1], wp.y + v[2]) then
            matsShut = matsShut + 1
          end
        end
        if m:gen4ArrivalWarpAt(wp.x, wp.y) then arrivals = arrivals + 1 end
      end
    end
  end
  -- MEASURED on the Rev 1 cache: 177 doors, 670 mats and stairs, 309 arrival.
  check(doors >= 150 and doorsShut == doors,
        ('every door must be a wall to press into: %d of %d'):format(doorsShut, doors))
  check(mats >= 600 and matsShut == mats,
        ('every directional warp must face a wall: %d of %d'):format(matsShut, mats))
  check(arrivals >= 250, 'and the arrival warps must still exist, got ' .. arrivals)
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
