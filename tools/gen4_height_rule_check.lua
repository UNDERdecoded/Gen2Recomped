-- tools/gen4_height_rule_check.lua
--
-- A DS MAP OBJECT CANNOT STEP BETWEEN TWO GROUNDS 20 UNITS APART.
--
--   python tools/run_lua_check.py tools/gen4_height_rule_check.lua \
--     G:/Gen2Recomped/heartgold/data/generated \
--     G:/Gen2Recomped/platinum/data/generated
--
-- Reported from play (HeartGold): in Falkner's gym the player walked from the
-- floor straight up onto the walkway the lift serves, and off the walkway's
-- edge at the top. The cartridge refuses a step whose ground is 20 or more
-- units from the walker's own (src/world/Gen4HeightRule.lua). This checks:
--
--   1. THE WIRING: Collision's verdict asks the rule, the free walk (third /
--      first person) asks the same verdict, the rule is off Black / White and
--      the Distortion World.
--   2. THE RULE ITSELF on made-up grounds: 19 passes, 20 stops, the nearest
--      plate of a bridge is the one stood on, a tile with no plate is not
--      judged.
--   3. FALKNER'S GYM (T22GYM0101), with the lift down and up (the 3 x 3 tiles
--      Gen4Commands.VIOLET_LIFT pins): the walkway is not reached from the
--      floor, the lift's tiles reach it when up, the walkway's edge and the
--      lift's sides are walls from the top, and the door reaches Falkner only
--      through the lift.
--   4. EVERY LANDING STILL HAS A WAY OUT on foot with the rule on: a landing
--      whose walk (without the rule) reaches its own warp cell back or any
--      other warp must still reach one. The maps where the rule takes ground
--      away are listed -- those are the raised floors it fixed.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or require('tests.love_stub')

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end
local function read(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local s = f:read('*a'); f:close()
  return s
end

local caches = {}
for i = 1, #(arg or {}) do
  if arg[i] and arg[i] ~= '' then caches[#caches + 1] = arg[i] end
end
local VERBOSE = os.getenv('VERBOSE')

-- ============================================================ 1. wiring
local coll = read('src/world/Collision.lua') or ''
check(coll:match('require%("src%.world%.Gen4HeightRule"%)%.blocks%(map, mover, tx, ty%)'),
      "Collision's verdict must ask Gen4HeightRule.blocks")
local player = read('src/world/Player.lua') or ''
local free = player:match('function Player:freeWalk(.-)\nfunction Player:update')
check(free and select(2, free:gsub('Collision%.mayEnter%(', '')) >= 2,
      'the free walk (third / first person) must ask Collision.mayEnter on both axes')
local ow = read('src/world/OverworldController.lua') or ''
check(ow:match('function OverworldState:orbitalGroundFor%(%)') and ow:match('self%.player%.freeInput = '),
      'the orbital camera modes must walk through Player:freeWalk')
local fm = read('mods/DRAMATIC_SHAPE/lib/FreeMove.lua')
if fm then
  check(fm:match('def%.generation%s*==%s*4 then%s+FreeMove%.drop%(%)%s+return inner%(self%)'),
        "DRAMATIC_SHAPE's FreeMove must hand Gen 4/5 maps back to the engine's walk")
end

-- ============================================================ 2. the rule
local R = require('src.world.Gen4HeightRule')
local Collision = require('src.world.Collision')
do
  local grounds = {
    ['0,0'] = { 0 }, ['1,0'] = { 19 }, ['2,0'] = { 39 }, ['3,0'] = {},
    ['4,0'] = { 40, 0 }, ['5,0'] = { 0 }, ['6,0'] = { 40 },
  }
  local map = { def = { generation = 4 }, gen4HeightsAt = function(x, y) return grounds[x .. ',' .. y] or {} end }
  local m = { cellX = 0, cellY = 0 }
  check(not R.blocks(map, m, 1, 0), 'a step up 19 units is a step')
  m.cellX = 1
  check(R.blocks(map, m, 2, 0), 'a step up 20 units is a wall')
  m.cellX = 2
  check(R.blocks(map, m, 1, 0), 'a step down 20 units is a wall')
  check(not R.blocks(map, m, 3, 0), 'a tile with no plate is not judged')
  local under = { cellX = 5, cellY = 0 }
  check(not R.blocks(map, under, 4, 0), 'walking under a bridge takes the path, not the deck')
  under.cellX = 4
  check(R.blocks(map, under, 6, 0), '...and stays under it (the deck is 40 above)')
  local deck = { cellX = 6, cellY = 0 }
  check(not R.blocks(map, deck, 4, 0), 'walking onto a bridge takes the deck')
  deck.cellX = 4
  check(R.blocks(map, deck, 5, 0), '...and stays on it (the path is 40 below)')
  check(not R.blocks({ def = { generation = 4, gen5 = true }, gen4HeightsAt = map.gen4HeightsAt },
                     { cellX = 1, cellY = 0 }, 2, 0), 'Black / White are not judged')
  check(not R.blocks({ def = { generation = 4, gen4DistWorld = true }, gen4HeightsAt = map.gen4HeightsAt },
                     { cellX = 1, cellY = 0 }, 2, 0), 'the Distortion World is not judged')
  check(not R.blocks({ def = { generation = 4 } }, { cellX = 1, cellY = 0 }, 2, 0),
        'a map with no height source is not judged')
end

-- ============================================================ 3 + 4. caches
local Map = require('src.world.Map')
local GameVersion = require('src.core.GameVersion')
local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local ORDER = { 'up', 'down', 'left', 'right' }

-- breadth-first over the engine's own verdict, carrying the walker's height:
-- a state is a cell AND the level stood at, so the path under a bridge and
-- the deck over it are walked separately (Goldenrod Gym's walkways cross the
-- floor paths into the middle and to Whitney). Answers the cells reached.
local CLIMB = { [0x13] = true, [0x4B] = true, [0x4C] = true }
local LEDGES
local LEDGE_DIR = { east = 'right', west = 'left', north = 'up', south = 'down',
                    right = 'right', left = 'left', up = 'up', down = 'down' }
local function waterAt(m, x, y)
  local ok, w = pcall(m.gen4WaterAt, m, x, y)
  return ok and w and true or false
end
-- `hm`: the walk also surfs (onto water, as a surfer: the same verdict) and
-- climbs (Rock Climb walls and waterfalls, 0x4B / 0x4C / 0x13: over the run of
-- them to the first cell past), as a player with the HMs does
local function walk(m, x0, y0, h0, limit, hm)
  local function lk(x, y, h) return (x * 4096 + y) .. ':' .. math.floor((h or 0) / 8 + 0.5) end
  local h1 = R.standingY(m, { cellX = x0, cellY = y0, gen4Height = h0, gen4HeightMap = m })
  local seen, cells, q, head = { [lk(x0, y0, h1)] = true }, { [x0 * 4096 + y0] = true }, { { x0, y0, h1 } }, 1
  local n = 1
  local function add(x, y, h)
    if seen[lk(x, y, h)] then return end
    seen[lk(x, y, h)] = true
    if not cells[x * 4096 + y] then cells[x * 4096 + y] = true; n = n + 1 end
    q[#q + 1] = { x, y, h }
  end
  while head <= #q and head < (limit or 40000) do
    local c = q[head]; head = head + 1
    for _, d in ipairs(ORDER) do
      local nx, ny = c[1] + DIRS[d][1], c[2] + DIRS[d][2]
      local mover = { cellX = c[1], cellY = c[2], facing = d, gen4Height = c[3], gen4HeightMap = m,
                      gen4HeightX = c[1], gen4HeightY = c[2],
                      surfing = hm and (waterAt(m, c[1], c[2]) or waterAt(m, nx, ny)) or nil }
      local ok, yes = pcall(Collision.canMove, m, {}, mover, d)
      if ok and yes then
        local step = { cellX = nx, cellY = ny, gen4Height = mover.gen4Height, gen4HeightMap = m,
                       gen4HeightX = c[1], gen4HeightY = c[2] }
        add(nx, ny, R.standingY(m, step))
      end
      -- (a waterfall is surfed onto and still climbed / ridden past: the HM
      -- carries the player over the run whatever the step said)
      if ok and yes and not (hm and m:inBounds(nx, ny) and CLIMB[m:cellBehaviour(nx, ny) or -1]) then
        -- the step was the whole move
      elseif LEDGES and m:inBounds(nx, ny) and LEDGE_DIR[LEDGES[m:cellBehaviour(nx, ny) or -1] or ''] == d then
        -- a LEDGE is a refused step the engine turns into a hop
        -- (OverworldState:checkLedgeHop): two cells on, three for the
        -- Distortion World's double jumps
        local lb = m:cellBehaviour(nx, ny)
        local far = (lb >= 0x5A and lb <= 0x5D) and 3 or 2
        local lx, ly = c[1] + DIRS[d][1] * far, c[2] + DIRS[d][2] * far
        if m:inBounds(lx, ly) and m:isWalkableCell(lx, ly) then
          add(lx, ly, R.standingY(m, { cellX = lx, cellY = ly, gen4Height = c[3], gen4HeightMap = m }))
        end
      elseif hm and m:inBounds(nx, ny) and CLIMB[m:cellBehaviour(nx, ny) or -1] then
        local x, y, guard = nx, ny, 0
        while m:inBounds(x, y) and CLIMB[m:cellBehaviour(x, y) or -1] and guard < 32 do
          x, y, guard = x + DIRS[d][1], y + DIRS[d][2], guard + 1
        end
        if m:inBounds(x, y) and (m:isWalkableCell(x, y) or waterAt(m, x, y)) then
          local list = m.gen4HeightsAt and m.gen4HeightsAt(x, y) or {}
          add(x, y, list[1] or c[3])
        end
      end
    end
  end
  return cells, n
end

-- THE LIFTS, as the walk meets them: Falkner's (Gen4Commands.VIOLET_LIFT) and
-- Platinum's nine platform lifts (src/world/Gen4PlatformLiftRide.lua). The
-- slab's tiles carry the floor the lift stands at; a walk that reaches the slab
-- may ride it to the other floor (not down, for the League's six) and walks on
-- from there. Answers the cells reached over every floor.
local Ride = require('src.world.Gen4PlatformLiftRide')
local Lifts = require('src.import.Gen4PlatformLifts')
local function liftOf(def)
  if def.cameraFamily == 'hgss' then
    if (def.sourceId or def.id) ~= 'T22GYM0101' then return nil end
    local L = require('src.script.Gen4Commands').VIOLET_LIFT
    local tiles = {}
    for dx = 0, L.tiles.w - 1 do for dz = 0, L.tiles.h - 1 do tiles[#tiles + 1] = { L.tiles.x + dx, L.tiles.z + dz } end end
    return { tiles = tiles, floors = { L.down, L.up }, down = true, start = 1 }
  end
  local cfg, row = Ride.CONFIG[tonumber(def.header) or -1], Lifts.row(def.header)
  if not (cfg and row) then return nil end
  local tiles = {}
  for dx = 0, Lifts.SIZE_X - 1 do for dz = 0, Lifts.SIZE_Y - 1 do tiles[#tiles + 1] = { row.start[1] + dx, row.start[2] + dz } end end
  return { tiles = tiles, floors = cfg.floors, down = cfg.down }
end
local function walkLifted(m, x0, y0, hm)
  local def = m.def
  local lift = m.gen4HeightsAt and liftOf(def)
  if not lift then return walk(m, x0, y0, nil, nil, hm) end
  local saved = def.gen4HeightEdits
  local function at(fl)
    def.gen4HeightEdits = {}
    for _, t in ipairs(lift.tiles) do def.gen4HeightEdits[t[1] .. ',' .. t[2]] = lift.floors[fl] end
  end
  -- the floor it stands at on arrival: Platinum's by the arrival z, Violet's down
  local fl = lift.start or (Lifts.floorId(def.header, y0 + (def.originY or 0)) + 1)
  local all, n, starts = {}, 0, { { x0, y0 } }
  for _ = 1, 4 do
    at(fl)
    local onSlab = {}
    for _, st in ipairs(starts) do
      local cells = walk(m, st[1], st[2], lift.floors[fl], nil, hm)
      for k in pairs(cells) do
        if not all[k] then all[k] = true; n = n + 1 end
        for _, t in ipairs(lift.tiles) do
          if k == t[1] * 4096 + t[2] then onSlab[#onSlab + 1] = t end
        end
      end
    end
    local other = (fl == 1) and 2 or 1
    if #onSlab == 0 or (other == 1 and not lift.down) then break end
    fl, starts = other, onSlab
  end
  def.gen4HeightEdits = saved
  return all, n
end

-- LANDINGS THE RULE LEAVES WITH ONLY THE WAY BACK, each the cartridge's own
-- design (the Platinum map ids do not occur in HeartGold / SoulSilver)
local KNOWN = {}
for _, id in ipairs({ 'C10R0102', 'C10R0104', 'C10R0106', 'C10R0108', 'C10R0110' }) do
  KNOWN[id .. ':4,2'] = "a League lift's top floor: the lift never goes down (preventGoingDown), the way out is the door in"
end
KNOWN['C10R0111:8,2'] = "the Champion's room from the Hall of Fame side: its lift never goes down"
KNOWN['R221R0101:7,7'] = "Pal Park's exit hall: PalParkLobby_OnFrame_ExitPalPark walks the player out past the worker (script movement)"

-- PEOPLE / SIGNS THE RULE PUTS OUT OF A WALK'S REACH, each the cartridge's
-- own layout (map:x,y)
local KNOWN_CUT = {}

for _, dir in ipairs(caches) do
  local function load(name) local f = loadfile(dir .. '/' .. name .. '.lua') return f and f() end
  local maps, tilesets = load('maps'), load('tilesets')
  local terrain, heights = load('gen4_terrain'), load('gen4_map_heights')
  check(maps and tilesets and terrain and heights, dir .. ': maps, tilesets, gen4_terrain and gen4_map_heights must load')
  if maps and tilesets and terrain and heights then
    local hgss = false
    for _, def in pairs(maps) do
      if type(def) == 'table' and def.cameraFamily == 'hgss' then hgss = true break end
    end
    pcall(GameVersion.set, hgss and 'heartgold' or 'platinum')
    local layouts = load('map_layouts')
    LEDGES = tilesets.TILESET_GEN4_STANDIN and tilesets.TILESET_GEN4_STANDIN.ledgeBehaviours
    local function build(id, withHeights)
      local def = maps[id]
      if not (type(def) == 'table' and def.generation == 4) or def.gen5 then return nil end
      if not def.blocks and layouts then
        pcall(require('src.world.MapLoader').resolveBlocks, { map_layouts = layouts }, def)
      end
      if not def.blocks then return nil end
      local ok, m = pcall(Map.new, def, tilesets[def.tileset] or tilesets.TILESET_GEN4_STANDIN)
      if not ok then return nil end
      if withHeights then m.gen4HeightsAt = R.cacheSource(def, terrain, heights) end
      return m
    end

    -- ------------------------------------------------- 3. Falkner's gym
    if maps.T22GYM0101 then
      local def = maps.T22GYM0101
      local L = require('src.script.Gen4Commands').VIOLET_LIFT
      local function liftAt(y)
        def.gen4HeightEdits = {}
        for dx = 0, L.tiles.w - 1 do
          for dz = 0, L.tiles.h - 1 do def.gen4HeightEdits[(L.tiles.x + dx) .. ',' .. (L.tiles.z + dz)] = y end
        end
      end
      local saved = def.gen4HeightEdits
      local m = build('T22GYM0101', true)
      local function can(x, y, d, h)
        local mover = { cellX = x, cellY = y, gen4Height = h, gen4HeightMap = m, gen4HeightX = x, gen4HeightY = y }
        return (Collision.canMove(m, {}, mover, d)) and true or false
      end
      liftAt(L.down)
      check(not can(15, 19, 'up', L.down), 'Violet gym, lift down: the floor (15,19) does not step up onto the walkway (15,18)')
      check(not can(9, 19, 'up', L.down), 'Violet gym, lift down: nor anywhere along row 19 (9,19)')
      check(not can(15, 18, 'down', L.up), 'Violet gym, lift down: the walkway (15,18) does not step down to the lift tiles')
      check(can(13, 20, 'right', L.down), 'Violet gym, lift down: the floor walks onto the lift (13,20) -> (14,20)')
      check(can(15, 21, 'up', L.down), 'Violet gym, lift down: (15,21) -> (15,20), the lift trigger')
      local door = def.warps and def.warps[1]
      local seen = walk(m, door.x, door.y, nil)
      check(not seen[15 * 4096 + 5], 'Violet gym, lift down: the door does not reach Falkner (15,5) on foot')
      check(seen[15 * 4096 + 20], 'Violet gym, lift down: the door reaches the lift (15,20)')
      liftAt(L.up)
      check(can(15, 19, 'up', L.up), 'Violet gym, lift up: the lift (15,19) steps onto the walkway (15,18)')
      check(not can(14, 20, 'left', L.up), 'Violet gym, lift up: the lift side (14,20) is a wall to the floor (13,20)')
      check(not can(15, 21, 'down', L.up), 'Violet gym, lift up: the lift front (15,21) is a wall to the floor (15,22)')
      check(not can(13, 20, 'right', L.down), 'Violet gym, lift up: the floor (13,20) does not step onto the raised lift')
      local top = walk(m, 15, 20, L.up)
      check(top[15 * 4096 + 5], 'Violet gym, lift up: the lift reaches Falkner (15,5)')
      check(not top[15 * 4096 + 26] and not top[door.x * 4096 + door.y],
            'Violet gym, lift up: the walkway does not reach the floor or the door')
      local off = 0
      for k in pairs(top) do
        local x, y = math.floor(k / 4096), k % 4096
        local list = m.gen4HeightsAt(x, y)
        if list[1] and list[1] < L.up - 20 then off = off + 1 end
      end
      check(off == 0, ('Violet gym, lift up: every cell reached from the top is at the top (%d below it)'):format(off))
      def.gen4HeightEdits = saved
    end

    -- ------------------------------------------------- 4. every landing
    local landings, order = {}, {}
    for id, def in pairs(maps) do
      if type(def) == 'table' and def.generation == 4 and not def.gen5 then
        for _, w in ipairs(def.warps or {}) do
          local dest = w.destMap and maps[w.destMap]
          local to = dest and dest.warps and dest.warps[tonumber(w.destWarp) or -1]
          if to and to.x and to.y then
            local key = w.destMap .. '#' .. w.destWarp
            if not landings[key] then landings[key] = { map = w.destMap, x = to.x, y = to.y }; order[#order + 1] = key end
          end
        end
      end
    end
    table.sort(order)
    local cacheA, cacheB = {}, {}
    local judged, lost, changed = 0, 0, {}
    local unionA, unionB = {}, {}
    for _, key in ipairs(order) do
      local L = landings[key]
      cacheA[L.map] = cacheA[L.map] or build(L.map, false) or false
      cacheB[L.map] = cacheB[L.map] or build(L.map, true) or false
      local a, b = cacheA[L.map] or nil, cacheB[L.map] or nil
      if a and b and b.gen4HeightsAt and a:inBounds(L.x, L.y) then
        judged = judged + 1
        local without, na = walk(a, L.x, L.y, nil)
        local with, nb = walkLifted(b, L.x, L.y)
        unionA[L.map] = unionA[L.map] or {}
        unionB[L.map] = unionB[L.map] or {}
        -- (a landing already inside the union adds nothing new to it)
        local key = L.x * 4096 + L.y
        if not unionA[L.map][key] then
          for k in pairs((walk(a, L.x, L.y, nil, nil, true))) do unionA[L.map][k] = true end
        end
        if not unionB[L.map][key] then
          for k in pairs((walkLifted(b, L.x, L.y, true))) do unionB[L.map][k] = true end
        end
        -- PASTORIA'S GYM MOVES ITS FLOOR: the water plate stands at 0, 32 or 64
        -- by the button last pressed (Gen4PastoriaGym.apply), so what the
        -- player can reach is the union over the three levels, not the bare
        -- BDHC the walk above sees.
        if L.map == 'C06GYM0101' then
          local DMF = require('src.world.Gen4DynamicMapFeatures')
          local def = b.def
          -- The buttons are pressed from anywhere reached, so each level's walk
          -- also starts from every cell an earlier level reached, until nothing
          -- new turns up.
          local levelSeen = { [0] = {}, [32] = {}, [64] = {} }
          local grew = true
          while grew do
            grew = false
            for _, height in ipairs({ 0, 32, 64 }) do
              def.gen4DynamicPlate = { x = DMF.PASTORIA_PLATE_X, y = DMF.PASTORIA_PLATE_Z,
                                       w = DMF.PASTORIA_PLATE_W, h = DMF.PASTORIA_PLATE_H, height = height }
              def.gen4PastoriaGates = DMF.PASTORIA_GATE_OPENS_AT
              local seen = levelSeen[height]
              local starts = { [L.x * 4096 + L.y] = true }
              for k in pairs(unionB[L.map]) do starts[k] = true end
              for k in pairs(starts) do
                if not seen[k] then
                  local sx, sy = math.floor(k / 4096), k % 4096
                  if b:isWalkableCell(sx, sy) then
                    for c in pairs((walkLifted(b, sx, sy, true))) do
                      seen[c] = true
                      if not unionB[L.map][c] then unionB[L.map][c] = true; grew = true end
                    end
                  end
                  seen[k] = true
                end
              end
            end
          end
          def.gen4DynamicPlate, def.gen4PastoriaGates = nil, nil
        end
        -- the OTHER warps each walk reaches (on the cell or beside it)
        local function warps(seen, m)
          local n = 0
          for _, w in ipairs(m.def.warps or {}) do
            if not (w.x == L.x and w.y == L.y) then
              local onOrBeside = seen[w.x * 4096 + w.y]
              for _, d in ipairs(ORDER) do
                onOrBeside = onOrBeside or seen[(w.x - DIRS[d][1]) * 4096 + (w.y - DIRS[d][2])]
              end
              if onOrBeside then n = n + 1 end
            end
          end
          return n
        end
        -- ...or the HM ways on from a reached cell: water to surf, a rock wall
        -- or a waterfall to climb (Route 47's lowest Cliff Cave mouth opens on
        -- a beach under the bridge, left by Surf)
        local function hmWays(seen, m)
          for k in pairs(seen) do
            local x, y = math.floor(k / 4096), k % 4096
            for _, d in ipairs(ORDER) do
              local tx, ty = x + DIRS[d][1], y + DIRS[d][2]
              if m:inBounds(tx, ty) then
                local okW, water = pcall(m.gen4WaterAt, m, tx, ty)
                local bt = m:cellBehaviour(tx, ty)
                if (okW and water) or bt == 0x13 or bt == 0x4B or bt == 0x4C then return 1 end
              end
            end
          end
          return 0
        end
        local wa, wb = warps(without, a), warps(with, b)
        if wb < 1 and wa >= 1 then wb = hmWays(with, b) end
        if nb < na then
          changed[#changed + 1] = { L.map, L.x, L.y, na, nb }
        end
        -- a landing whose walk reached another warp still reaches one
        local known = KNOWN[L.map .. ':' .. L.x .. ',' .. L.y]
        if wa >= 1 and wb < 1 and known then
          print(('  known: %s (%d,%d) -- %s'):format(L.map, L.x, L.y, known))
        elseif wa >= 1 and wb < 1 then
          lost = lost + 1
          check(false, ('%s: landing %s (%d,%d) reached %d warps on foot and none with the height rule')
                :format(dir, L.map, L.x, L.y, wa))
        end
      end
    end
    -- EVERY PERSON AND SIGN STILL IN REACH: over all of a map's landings, one
    -- the walk without the rule could stand beside must still be stood beside
    -- with it (talked to across a counter too: two cells away in a line)
    local function beside(set, x, y)
      if set[x * 4096 + y] then return true end
      for _, d in ipairs(ORDER) do
        for n = 1, 2 do
          if set[(x + DIRS[d][1] * n) * 4096 + (y + DIRS[d][2] * n)] then return true end
        end
      end
      return false
    end
    -- ...and from the map's own edges, where the next map's ground joins it
    -- (the overworld is one matrix; a route is walked into across a seam)
    local matrices = load('gen4_map_matrices') or {}
    local function seamed(def)
      if def.connections and next(def.connections) then return true end
      -- the outdoor matrix only (routes, towns, cities): a dungeon's floors
      -- may share one matrix without a single walkable seam between them
      local name = tostring(def.sourceId or def.id)
      if not name:match('^[RTC]%d') then return false end
      local mx = def.layout and matrices[def.layout]
      local seen, n = {}, 0
      for _, h in ipairs(type(mx) == 'table' and mx.headers or {}) do
        if h ~= 0 and h ~= 0xFFFF and not seen[h] then seen[h] = true; n = n + 1 end
      end
      return n > 1
    end
    for id, A in pairs(unionA) do
      local a, b = cacheA[id] or nil, cacheB[id] or nil
      if a and b and seamed(maps[id]) then
        local B = unionB[id]
        local w, h = a.widthCells, a.heightCells
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            if (x == 0 or y == 0 or x == w - 1 or y == h - 1) and a:isWalkableCell(x, y) then
              local key = x * 4096 + y
              if not A[key] then for k in pairs((walk(a, x, y, nil, nil, true))) do A[k] = true end end
              if not B[key] then for k in pairs((walkLifted(b, x, y, true))) do B[k] = true end end
            end
          end
        end
      end
    end
    local cut = 0
    for id, A in pairs(unionA) do
      local B, def = unionB[id], maps[id]
      for _, kind in ipairs({ 'objects', 'signs' }) do
        for _, o in ipairs(def[kind] or {}) do
          if o.x and o.y and beside(A, o.x, o.y) and not beside(B, o.x, o.y) then
            local why = KNOWN_CUT[id .. ':' .. o.x .. ',' .. o.y]
            if why then
              if VERBOSE then print(('  known cut: %s %s (%d,%d) -- %s'):format(id, kind, o.x, o.y, why)) end
            else
              cut = cut + 1
              check(false, ('%s: %s %s at (%d,%d) (%s) is in reach on foot and not with the height rule')
                    :format(dir, id, kind, o.x, o.y, tostring(o.spriteName or o.script)))
            end
          end
        end
      end
    end
    print(('%s: %d people / signs cut off by the rule'):format(dir, cut))
    table.sort(changed, function(p, q) return (p[4] - p[5]) > (q[4] - q[5]) end)
    print(('%s: %d landings walked, %d lose ground to the height rule, %d left with no way out')
          :format(dir, judged, #changed, lost))
    local seenMap = {}
    for i, c in ipairs(changed) do
      if not seenMap[c[1]] and (VERBOSE or i <= 40) then
        seenMap[c[1]] = true
        print(('  %-12s landing (%d,%d): %d cells on foot -> %d with the rule'):format(c[1], c[2], c[3], c[4], c[5]))
      end
    end
  end
end

print(('gen4_height_rule_check: %d passed, %d failed'):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
