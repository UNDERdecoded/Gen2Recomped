-- Real native Game/StateStack/player phase with synthetic session metadata.
local F={}
function F.new(edition)
  local f=require('tools.player-runtime.fixture').new(edition)
  local Identity=require('src.compat.gen1.MapIdentity')
  local prefix=({firered='FR',leafgreen='FR',emerald='EM',ruby='RU',sapphire='SA'})[edition]
  local canonical=prefix and(prefix..((edition=='firered'or edition=='leafgreen')and'_PALLET_TOWN'or'_LITTLEROOT_TOWN'))
  local _,group,number=Identity.lookup(edition,canonical or'')
  f.canonical=canonical;f.map.def.group,f.map.def.number=group,number
  local g=f.game;g.mods={exports={runtime_probe={}}}
  g.save.player={map='TEST',x=4,y=4,facing='right',name='NATIVE',rival='RIVAL',id=37,gender=0}
  g.save.playTime=3661.25;g.save.options={};g.save.modData={};g.save.money=300;g.save.coins=4
  g.stack=setmetatable({states={f.world}},{__index=require('src.core.StateStack')})
  f.nativeUpdates,f.inputSteps=0,0
  function f.world:update(dt)f.nativeUpdates=f.nativeUpdates+1;self:stepBody(false)end
  function f.input:step()f.inputSteps=f.inputSteps+1 end
  g.audioAccum=0
  return f
end
return F
