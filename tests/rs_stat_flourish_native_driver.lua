-- Fresh native RS import, all mods disabled. Controlled animation fixtures;
-- real input/party/story acceptance is a separate test.
return function(game)
 io.stdout:setvbuf('no')
 local V=require('src.core.GameVersion');local edition=V.get();assert(edition=='ruby'or edition=='sapphire')
 local Json=require('src.link.Json');local Battle=require('src.battle.BattleState');local Move=require('src.battle.Gen3MoveAnim')
 local function wait(n)for _=1,n do coroutine.yield();assert(#game.mods.errors==0,Json.encode(game.mods.errors))end end
 local function press(k)game.input:overlayPressed(k);wait(1);game.input:overlayReleased(k);wait(1)end
 assert(love.window.setMode(960,640,{highdpi=false,vsync=0}))
 game.stack:init();game.stack:push(game.overworld,'MAP_G00_N17',40,11,'up');wait(2)
 game.save.party={require('src.pokemon.Pokemon').new(game.data,'BULBASAUR',40)}
 local b=Battle.newWild(game,'POOCHYENA',30);game.stack:push(b);local deadline=love.timer.getTime()+45
 while b.phase~='menu'or b.showPlayerBack or b.sendingOut or b.enemySendingOut or b.gen3BallPlaying do
  assert(love.timer.getTime()<deadline,'Native intro did not finish')
  if b.phase=='messages'and(b.msgWaiting or b.msgPrompt)then press('a')else wait(1)end
 end
 wait(60)
 local host=b.gen3Anim;local rows={}
 local function pixels(name)
  local g=love.graphics;local target=g.newCanvas(240,160);local frame,age,queue=b.frame,b.gen3Anim.frame,#b.queue
  local save,rng=Json.encode(game.save),love.math.getRandomState();local depth=g.getStackDepth()
  g.push('all');local ok,err=xpcall(function()g.setCanvas(target);g.origin();g.setShader();g.clear(0,0,0,0);b:draw()end,debug.traceback)
  while g.getStackDepth()>depth do g.pop()end;assert(ok,err)
  local image=target:newImageData();local raw=image:getString()
  if name then assert(love.filesystem.write(name..'.png',image:encode('png')))end
  image:release();target:release()
  assert(frame==b.frame and age==b.gen3Anim.frame and queue==#b.queue and save==Json.encode(game.save)and rng==love.math.getRandomState(),'Draw advanced native state')
  return raw
 end
 for _,key in ipairs{'HARDEN','IRON_DEFENSE'}do for _,player in ipairs{true,false}do
  local shape=assert(game.data.moves[key].anim.flourish);assert(shape.life==64 and shape.laps==2 and shape.alpha==.5)
  local anim=assert(Move.new(game.data));b.gen3Anim=anim;b.gen3AnimPlaying=true
  assert(anim:start(key,player,player and 0 or 1,player and 1 or 0,{},b))
  for _=1,32 do anim:update()end
  local actor=player and b.player or b.enemy;assert(anim:flourishLayer(actor))
  local name='stat-'..key:lower()..'-'..(player and'player'or'enemy')
  local positive=pixels(name);assert(pixels()==positive,'Native draw not idempotent')
  local live=anim.flourish;anim.flourish=nil;local negative=pixels(name..'-layer-off');anim.flourish=live
  assert(negative~=positive,'Native stat layer invisible');assert(pixels(name..'-restored')==positive,'Native stat layer did not restore')
  for _=33,64 do anim:update()end;assert(anim:flourishLayer(actor)==nil,'RS played a third lap')
  rows[#rows+1]={move=key,player=player,life=shape.life,laps=shape.laps,visible=true,restoreExact=true,source=shape.source}
  anim:release();b.gen3Anim=host;b.gen3AnimPlaying=false;wait(1)
 end end
 game.stack:pop();assert(love.filesystem.write('edition-result.json',Json.encode({edition=edition,status='pass',modsEnabled=false,cases=rows,physicalIOSTested=false})))
 print('PASS_NATIVE_RS_STAT_FLOURISH',edition,#rows,'real ROM import, both sides, visible negative, exact restore, 64-frame terminal');love.event.quit(0)
end
