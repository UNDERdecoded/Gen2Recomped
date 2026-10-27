-- Actual native map records, bank decoder, world renderer and source facade;
-- all artwork and actors are synthetic and independent of any ROM or profile.
local F={}
function F.new(edition)
  local Version=require('src.core.GameVersion');Version.set(edition)
  local original=package.loaded['src.core.Game']
  local scene=require('tests.world_draw.fixture').new(3)
  local native=require('tools.native-atlas/session-fixture').new(edition)
  package.loaded['src.core.Game']=scene.game
  local game,world=scene.game,scene.world
  game.data=native.game.data;game.data.field={overworldFx={}}
  for _,bank in pairs(game.data.map_tilesets)do
    bank.sourceBehaviorMask=(edition=='firered'or edition=='leafgreen')and 511 or 255
  end
  game.data.constants.gen3Flash={maxLevel=4,radii={200,72,56,40,24},screen={240,160},lit=0,dark=4}
  game.save={options={},flags={},gen3FlashLevel=0};game.mods={exports={}}
  world.map=native.map;world.isOverworld=true
  world.neighbors={{map=native.neighbor,ox=48,oy=-16}}
  world.camera={x=0,y=0};world.player=world.entities[1]
  world.enter=function()end -- this synthetic map/actor admission is already assembled
  world.player.px,world.player.py=16,16;world.player.spinning=nil
  world.map.renderer=require('src.render.TileRenderer').new(world.map,game.data)
  native.neighbor.renderer=require('src.render.TileRenderer').new(native.neighbor,game.data)
  local Stack=require('src.core.StateStack')
  game.stack=setmetatable({},{__index=Stack});game.stack:init()
  if game.stack.setWorldOwner then game.stack:setWorldOwner({})end
  game.stack:push(world)
  game.overworld=world
  world.drawGen3Flash=require('src.world.OverworldController').drawGen3Flash
  local f={game=game,world=world,native=native,scene=scene,original=original}
  function f:release()
    require('src.core.game3.field_view').release();require('src.core.game3.map').release()
    world.map.renderer:release();native.neighbor.renderer:release();native.views:release()
    require('src.core.game3.tileset_native').release();package.loaded['src.core.Game']=original
  end
  return f
end
return F
