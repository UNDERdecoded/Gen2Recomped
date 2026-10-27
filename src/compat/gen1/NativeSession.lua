-- Resolve the live owner without bootstrapping Game or keeping a retired world.
local Version = require('src.core.GameVersion')
local M = {}
local entering=setmetatable({},{__mode='k'})
local unpack=table.unpack or unpack
local function pack(...)return {n=select('#',...),...}end
function M.withWorld(game,world,fn,...)
  local owner,why=M.game(game);assert(owner,why)
  assert(type(world)=='table'and world.isOverworld and world.map and world.player
    and owner.data and owner.data.maps and owner.data.maps[world.map.id]==world.map.def,'foreign native world scope')
  local previous=entering[owner];entering[owner]=world
  local result=pack(pcall(fn,...));entering[owner]=previous
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
end
function M.game(game)
  local explicit = game ~= nil
  local facade = package.loaded['src.core.Game3']
  if type(facade) == 'table' and type(facade.native) == 'function' then
    game = facade.native(game)
    if explicit and game == nil then return nil, 'native Game3 facade retired' end
  end
  game = game or package.loaded['src.core.Game']
  local info = Version.info(Version.get())
  if type(game) ~= 'table' or not info or info.generation ~= 3 then
    return nil, 'no native GBA session'
  end
  return game
end
function M.data(game)
  local owner,why=M.game(game);if not owner then return nil,why end
  local data=owner.data
  if type(data)~='table'or type(data.tilesets)~='table'or type(data.map_tilesets)~='table'
      or type(data.constants)~='table'or type(data.constants.gen3Layout)~='table'then
    return nil,'native GBA tileset data unavailable'
  end
  return owner,data
end
-- Admission lookup is also used by map readers that can run before a player
-- is constructed. Edition/data validation stays with each typed consumer.
function M.world(game)
  if type(game)~='table'then return nil end
  local states = game.stack and game.stack.states
  local world=entering[game]
  if not world and type(states) == 'table' then
    for i = #states, 1, -1 do
      if states[i].isOverworld then world = states[i]; break end
    end
    -- The physical list can contain overlays only. Its persistent world is
    -- still a real native admission, independently of the convenience pointer.
    if not world then world=game.stack.worldState end
  elseif not world then
    world = game.overworld
  end
  return world and world.isOverworld and world or nil
end
function M.resolve(game)
  local why;game,why=M.game(game);if not game then return nil,why end
  local world=M.world(game)
  if not (world and world.isOverworld and world.player and world.map) then
    return nil, 'no active native player'
  end
  if not (game.data and game.data.maps and world.map.def
      and game.data.maps[world.map.id] == world.map.def) then
    return nil, 'native world belongs to a retired dataset'
  end
  return game, world, world.player
end
function M.acceptsInput(game, world, player)
  local owner, current, actor = M.resolve(game)
  if owner ~= game or current ~= world or actor ~= player then return false end
  local states = game.stack and game.stack.states
  if type(states)=='table' then
    local active=type(game.stack.active)=='function' and game.stack:active() or states[#states]
    if active~=world then return false end
  end
  return not world.battleActive and not (world.busy and world:busy())
end
return M
