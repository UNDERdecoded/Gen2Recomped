local F={}
function F.new(edition)
  local f=require('tools.map-runtime.fixture').new(edition)
  local picture=require('tools.native-atlas.fixture').new(edition)
  local data=f.game.data;local previous=data.map_tilesets
  picture.pair.primary.address=previous.P.address
  picture.pair.secondary.address=previous.S.address
  local secondary={};for key,value in pairs(picture.pair.secondary)do secondary[key]=value end
  secondary.address=previous.T.address
  data.map_tilesets={P=picture.pair.primary,S=picture.pair.secondary,T=secondary}
  data.constants.gen3Layout=picture.layout
  f.world.player=nil -- atlas prewarming must not require a spawned avatar
  package.loaded['src.core.Game']=f.game
  f.picture=picture
  return f
end
return F
