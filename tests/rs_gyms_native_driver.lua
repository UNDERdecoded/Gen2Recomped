return function(game)
  local U=require('tests.drivers.util')
  local V=require('src.core.GameVersion')
  local C=require('src.script.Gen3Commands')
  local Pokemon=require('src.pokemon.Pokemon')
  local edition=V.get();assert(edition=='ruby' or edition=='sapphire')
  U.newGame(game)
  local mon=Pokemon.new(game.data,'MEWTWO',100)
  mon.moves={{id='PSYCHIC',pp=99,maxPp=99}};game.save.party={mon}
  C.setVar(game.save,0x4093,0)
  U.teleport(game,'MAP_G10_N00',0,10,'up');U.wait(30)
  assert(#game.data.constants.gen3MauvilleGym.SWITCHES==3)
  U.hold(game,'up',8);U.wait(40)
  assert(C.getVar(game.save,0x4093)==1,'walking onto RS switch did not run its script')
  local map=game.overworld.map
  assert(map:blockAt(0,9)==0x206,'actual RS switch not pressed')
  assert(map:blockAt(4,8)==0x238 and map:cellCollision(4,8)==0,'beam did not become passable')
  assert(game.save.flags[C.flagKey(0x63)],'barrier state flag missing')
  love.graphics.captureScreenshot(edition..'-mauville-switch.png');U.wait(12)
  -- Re-enter through the normal map setup; its ON_LOAD must reconstruct the
  -- pressed switch and alternate beam state from the script's own save vars.
  U.teleport(game,'MAP_G10_N00',0,10,'up');U.wait(30)
  assert(game.overworld.map:blockAt(0,9)==0x206,'pressed switch lost on re-entry')
  assert(game.overworld.map:blockAt(4,8)==0x238,'beam state lost on re-entry')
  U.teleport(game,'MAP_G10_N00',4,4,'up');U.wait(30)
  local battled=false
  for frame=1,14000 do
    if frame%12==1 then U.tap(game,'a') else U.wait(1) end
    local top=game.stack:top()
    if top and top.enemy and top.trainer and tostring(top.trainer.name):upper():find('WATTSON',1,true) then battled=true end
    if battled and game.save.flags[C.flagKey(0xA7)] and top==game.overworld
       and not game.overworld.runner:isRunning() then break end
  end
  assert(battled and game.save.flags[C.flagKey(0x809)],'Dynamo Badge missing')
  assert(game.save.flags[C.flagKey(0xA7)] and game.save.inventory.TM34==1,'Shock Wave reward missing')
  for _,at in ipairs(game.data.constants.gen3MauvilleGym.SWITCHES) do
    assert(game.overworld.map:blockAt(at[1],at[2])==0x206,'victory did not press every RS switch')
  end
  assert(game.overworld.map:blockAt(4,8)==0x238,'victory did not disable beam')
  print('[driver] PASS real RS switch, re-entry, Wattson and reward/deactivation')
  C.setVar(game.save,0x4085,6)
  U.teleport(game,'MAP_G08_N01',4,82,'up');U.wait(30)
  map=game.overworld.map
  assert(map:blockAt(1,104)==0x21C,'ON_LOAD did not unlock entrance doors')
  assert(map:blockAt(1,78)==0x218,'unbeaten speed-room door not closed')
  local frames,original={},map.setBlock
  map.setBlock=function(self,x,y,tile,...)
    if x==1 and y==78 then frames[#frames+1]=tile end
    return original(self,x,y,tile,...)
  end
  battled=false
  for frame=1,14000 do
    if frame%12==1 then U.tap(game,'a') else U.wait(1) end
    local top=game.stack:top()
    if top and top.enemy and top.trainer and tostring(top.trainer.name):upper():find('RANDALL',1,true) then battled=true end
    if battled and map:blockAt(1,78)==0x21C and top==game.overworld
       and not game.overworld.runner:isRunning() then break end
  end
  map.setBlock=original
  assert(battled and not game.overworld.runner:isRunning(),'Randall door script did not finish')
  for i=1,5 do assert(frames[i]==0x217+i,'sliding door skipped a native animation frame') end
  assert(map:blockAt(1,79)==0x224 and map:blockAt(7,78)==0x21C,'both door halves/pairs were not opened')
  love.graphics.captureScreenshot(edition..'-petalburg-doors.png');U.wait(12)
  print('[driver] PASS Petalburg ON_LOAD and real trainer battle, five-frame doors and resume')
  love.filesystem.write('edition-result.json',require('src.link.Json').encode({status='pass',edition=edition,
    realMauvilleSwitch=true,mauvilleReentry=true,wattsonBattleAndReward=true,petalburgDoors=true,
    allModsDisabled=true,strongPartyFixture=true,fullStoryTested=false}))
  love.event.quit(0)
end
