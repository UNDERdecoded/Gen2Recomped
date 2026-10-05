-- Run:  texlua tools/gen4_double_jump_check.lua <cache dir>
--
-- THE DISTORTION WORLD'S DOUBLE JUMP IS THREE TILES AND SILENT.
--
-- `JUMP_*_TWICE` (0x5A..0x5D) starts MOVEMENT_ACTION_JUMP_DISTORTION_WORLD_*,
-- whose Step0 (pokeplatinum src/unk_020655F4.c) moves FX32_CONST(2) a frame
-- for 8 * 3 frames -- 48 units, three tiles -- with SEQ_NONE for its sound. An
-- ordinary ledge's JUMP_FAR moves for 16 frames: two tiles, with the DANSA
-- landing sound. The port read the TWICE tiles as ordinary ledges.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_double_jump_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')

local maps = assert(loadfile(cacheDir .. '/maps.lua'))()
local layouts = assert(loadfile(cacheDir .. '/map_layouts.lua'))()
local Map = require('src.world.Map')
local MapLoader = require('src.world.MapLoader')
local ts = require('src.import.Gen4Tileset').pair()
local data = { maps = maps, map_layouts = layouts }

-- ============================ 1. on the cartridge's own rooms, three is right
local DIRS = { [0x5A] = { 0, -1 }, [0x5B] = { 0, 1 }, [0x5C] = { -1, 0 }, [0x5D] = { 1, 0 } }
local tiles, landThree, landTwo = 0, 0, 0
for id, def in pairs(maps) do
  if def.generation == 4 and type(def.behaviorCells) == 'string' and id:match('^D34') then
    local m = Map.new(MapLoader.resolveBlocks(data, def), ts)
    for y = 0, def.height - 1 do
      for x = 0, def.width - 1 do
        local d = DIRS[m:cellBehaviour(x, y) or -1]
        if d then
          tiles = tiles + 1
          -- the jump tile is the one stepped INTO; the player stands one
          -- before it, so two past the tile is three from the player
          if m:isWalkableCell(x + d[1] * 2, y + d[2] * 2) then landThree = landThree + 1 end
          if m:isWalkableCell(x + d[1], y + d[2]) then landTwo = landTwo + 1 end
        end
      end
    end
  end
end
print(('double-jump tiles: %d; walkable landing at 3 tiles: %d, at 2 tiles: %d')
      :format(tiles, landThree, landTwo))
check(tiles >= 200, 'the Distortion World must carry its double jumps, got ' .. tiles)
check(landThree > landTwo * 2,
      'three tiles must be where the double jump lands -- the cartridge built the '
      .. 'rooms for it')

-- ============================ 2. the hop takes the cartridge's distance
local OW = require('src.world.OverworldController')
local function hopper(behaviour)
  local moved, sounds = {}, 0
  package.loaded['src.core.Sound'] = { play = function() sounds = sounds + 1 end }
  local s = setmetatable({
    player = { cellX = 1, cellY = 5, facing = 'up' },
    entities = {},
    map = setmetatable({
      def = { generation = 4, width = 3, height = 8 }, widthCells = 3, heightCells = 8,
      tileset = { ledgeBehaviours = { [0x3A] = 'north', [0x5A] = 'north' } },
      cellBehaviour = function(_, x, y) return (x == 1 and y == 4) and behaviour or 0 end,
      cellTile = function() return 0 end,
      inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 3 and y < 8 end,
      isWalkableCell = function() return true end,
    }, { __index = Map }),
    scriptMove = function(_, _, dir, n) moved[#moved + 1] = n end,
  }, { __index = OW })
  return s, moved, function() return sounds end
end
-- The controller keeps `Game` as a file-local set by `enter`; outside a
-- session it is nil, so hand the hop the one field it reads.
for i = 1, 200 do
  local name = debug.getupvalue(OW.startLedgeHop, i)
  if name == nil then break end
  if name == 'Game' then debug.setupvalue(OW.startLedgeHop, i, { data = {} }) break end
end
local s, moved, sounds = hopper(0x5A)
check(s:checkLedgeHop('up') == true, 'a double-jump tile must be jumped')
check(moved[1] == 3, 'three tiles, got ' .. tostring(moved[1]))
check(sounds() == 0, 'and silently -- SEQ_NONE')
s, moved, sounds = hopper(0x3A)
check(s:checkLedgeHop('up') == true and moved[1] == 2,
      'an ordinary ledge is still two tiles, got ' .. tostring(moved[1]))
check(sounds() == 1, 'with its landing sound')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
