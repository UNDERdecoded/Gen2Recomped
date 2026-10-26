-- Fresh native RS import with every mod disabled. Only own explicit fixtures.
return function(game)
 io.stdout:setvbuf('no');assert(love.filesystem.getIdentity():match('^gen2recomp%-qa%-'))
 local Json=require('src.link.Json');local edition=require('src.core.GameVersion').get()
 assert(edition=='ruby'or edition=='sapphire');assert(next(game.mods.exports)==nil,'Native ball test loaded mod exports')
 local P=require('src.render.Pipelines');for _,r in ipairs(P.list())do if not P.isInternal(r.id)then P.setLevel(r.id,0)end end
 local record=assert(game.data.constants.gen3BallAnim);assert(record.timing.sendOut and record.source:find('matching RS',1,true))
 local Assets=require('src.render.Assets');local balls=Assets.image(record.images.balls);local particles=Assets.image(record.images.particles)
 assert(balls:getWidth()==48 and balls:getHeight()==192 and particles:getWidth()==64 and particles:getHeight()==8)
 assert(record.sounds.caught==371 and record.sounds.click==nil)
 assert(love.window.setMode(1200,800,{resizable=true,highdpi=false,vsync=0}))
 local observe=function()end
 local function wait(n)for _=1,n do coroutine.yield();observe()end end
 local function press(k)game.input:overlayPressed(k);wait(1);game.input:overlayReleased(k);wait(1)end
 game.stack:init();game.stack:push(game.overworld,'MAP_G00_N17',40,11,'up');wait(2)
 local wanted={};for id,tr in pairs(game.data.trainers)do local p=tr.parties and tr.parties[1]
  if tr.picIndex==2 and not tr.doubleBattle and p and #p>0 then wanted[#wanted+1]=id end
 end
 local function level(id)local l=0;for _,m in ipairs(game.data.trainers[id].parties[1])do l=math.max(l,m.level)end;return l end
 table.sort(wanted,function(a,b)local x,y=level(a),level(b);return x<y or x==y and a<b end);local trainer=assert(wanted[1])
 local Battle=require('src.battle.BattleState');local Pokemon=require('src.pokemon.Pokemon');local cases={}
 for _,gender in ipairs{'boy','girl'}do
  game.save.player.gender=gender
  local mon=Pokemon.new(game.data,'BULBASAUR',20)
  -- Explicit non-shiny fixture: this test asserts the base 39-frame path.
  mon.personality=0;mon.otId=0x1000;mon.shiny=false;mon.moves={{id='GROWL',pp=40}};mon.ball='ULTRA_BALL';game.save.party={mon}
  local b=Battle.newTrainer(game,trainer,1);game.stack:push(b);local seen={};local list={};local views={}
  observe=function()
   local ball=b.gen3Ball
   if ball and b.gen3BallPlaying and not seen[ball]then seen[ball]=true;list[#list+1]={ball=ball,side=ball.battler==b.player and'player'or'enemy'}end
   if ball and ball.phase=='release'and ball.particles and ball.particles.age>=6 and not views[ball.battler]then
    local g=love.graphics;local frame=b.frame;local age=ball.frame
    local prefix='native-ball-'..gender..'-'..(ball.battler==b.player and'player'or'enemy')
    local function capture(name)
     local c=g.newCanvas(240,160,{dpiscale=1});local depth=g.getStackDepth()
     g.push('all');local ok,why=xpcall(function()g.setCanvas(c);g.origin();g.setShader();g.clear(0,0,0,0);b:draw()end,debug.traceback)
     while g.getStackDepth()>depth do g.pop()end;if not ok then c:release();error(why)end
     local data=c:newImageData();local bytes=data:getString();assert(love.filesystem.write(prefix..name..'.png',data:encode('png')));data:release();c:release()
     assert(b.frame==frame and ball.frame==age,'Native drawing advanced the actual ball');return bytes
    end
    local positive=capture('')
    for _,entry in ipairs{{'ball',balls},{'particles',particles}}do
     local draw=g.draw;local suppressed=0
     g.draw=function(image,...)if image==entry[2]then suppressed=suppressed+1;return end;return draw(image,...)end
     local ok,negative=xpcall(function()return capture('-'..entry[1]..'-negative')end,debug.traceback);g.draw=draw;assert(ok,negative)
     assert(suppressed>0 and positive~=negative,'Actual native '..entry[1]..' texture was invisible')
     assert(capture('-'..entry[1]..'-restored')==positive,'Native texture did not restore exactly')
    end
    views[ball.battler]=true
   end
  end
  local deadline=love.timer.getTime()+45
  repeat
   assert(love.timer.getTime()<deadline,'Native RS send-out timed out')
   if b.phase~='menu'and(b.msgWaiting or b.msgPrompt)then press('a')else wait(1)end
  until b.phase=='menu'and not b.showPlayerBack and not b.showEnemyTrainer and not b.sendingOut and not b.enemySendingOut and not b.gen3BallPlaying
  assert(#list==2 and views[b.player]and views[b.enemy],'Actual native ball/particle draw absent')
  local frames={}
  for _,e in ipairs(list)do assert(e.ball:isDone()and e.ball.frame==(e.side=='player'and 39 or 30));frames[e.side]=e.ball.frame end
  assert(list[2].ball.ball==3,'Native ULTRA item-to-sheet map failed')
  observe=function()end
  cases[#cases+1]={gender=gender,actualBallFrames=frames,realNativeParticles=true,visibleBallNegative=true,visibleParticlesNegative=true,restoreExact=true,nativeUltraSheet=3,modsDisabled=true,drawNoClockAdvance=true}
  game.stack:pop()
 end
 assert(love.filesystem.write('edition-result.json',Json.encode({status='pass',edition=edition,cases=cases,ballSource=record.source,physicalIOSDeviceTested=false,fullFeatureParity=false})))
 print('PASS_RS_NATIVE_BALLS',edition,'mods disabled, real native send-out and release, both genders, 39/30 native frames');love.event.quit(0)
end
