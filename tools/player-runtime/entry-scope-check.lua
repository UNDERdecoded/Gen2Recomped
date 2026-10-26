package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local Native=require('src.compat.gen1.NativeSession')
T.eq(package.loaded['src.core.Game'],nil)
love=require('tests.love_stub')
for _,edition in ipairs({'firered','emerald'})do
  local f=require('tools.player-runtime.fixture').new(edition)
  f.game.stack={states={}}
  local nested={isOverworld=true,map=f.map,player=f.player}
  local first,second,third=Native.withWorld(f.game,f.world,function()
    T.eq(select(2,Native.resolve()),f.world)
    Native.withWorld(f.game,nested,function()T.eq(select(2,Native.resolve()),nested)end)
    T.eq(select(2,Native.resolve()),f.world)
    return 1,nil,3
  end)
  T.eq(first,1);T.eq(second,nil);T.eq(third,3)
  T.eq(Native.resolve(),nil,'entry scope ends before the world is published')
  T.raises(function()Native.withWorld(f.game,f.world,function()error('entry failed')end)end,'entry failed')
  T.eq(Native.resolve(),nil,'failed entry cannot leak a native-world scope')
  T.raises(function()Native.withWorld(f.game,{isOverworld=true,map={id='OTHER',def={}},player=f.player},function()end)end,'foreign native world')
end
T.finish('native entry-world scopes')
