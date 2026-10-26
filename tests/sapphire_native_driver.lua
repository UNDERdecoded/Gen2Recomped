return function(game)
  local U=require('tests.drivers.util')
  local V=require('src.core.GameVersion')
  assert(V.get()=='sapphire')
  assert(game.data.pokemon.TREECKO)
  assert(game.data.font and #game.data.font.pages.normal.widths==254)
  print('[driver] Sapphire native dataset loaded')
  U.newGame(game)
  assert(game.overworld and game.stack:top()==game.overworld,'Sapphire new game did not reach field')
  love.graphics.captureScreenshot('sapphire-new-game.png');U.wait(3)
  -- Walk out through the cartridge's dynamic warp and let the normal
  -- Littleroot/Mom script take the player into the new house.
  U.hold(game,'right',48);U.wait(60)
  for i=1,4000 do
    if i%8==1 then U.tap(game,'a') else U.wait(1) end
    if game.overworld.map.id=='MAP_G01_N00' and game.stack:top()==game.overworld
       and not game.overworld.runner:isRunning() then break end
  end
  assert(game.overworld.map.id=='MAP_G01_N00','truck dynamic warp/Mom scene failed')
  assert(not game.overworld.runner:isRunning(),'opening scene stayed locked')
  local S=require('src.core.SaveData')
  assert(S.save(game.save,game.mods))
  assert(S.saveFileExists('sapphire') and not S.saveFileExists('emerald'))
  local loaded=assert(S.load('sapphire'))
  assert(loaded.version=='sapphire' and loaded.player.name==game.save.player.name)
  love.graphics.captureScreenshot('sapphire-opening-house.png');U.wait(12)
  print('[driver] PASS actual truck exit, Mom scene, own save/reload')
  local C=require('src.script.Gen3Commands')
  local Pokemon=require('src.pokemon.Pokemon')
  assert(game.data.constants.gen3Starters.var==0x4023,'starter choice variable was not read from Sapphire')
  U.teleport(game,'MAP_G00_N16',7,15,'up');U.wait(30)
  local firstBattle=false
  for frame=1,14000 do
    if frame%8==1 then U.tap(game,'a') else U.wait(1) end
    local top=game.stack:top()
    if top and top.enemy and top.enemy.mon and top.enemy.mon.species=='POOCHYENA' then
      if not firstBattle then
        firstBattle=true
        love.graphics.captureScreenshot('sapphire-first-battle.png');U.wait(12)
      end
    end
    if firstBattle and game.overworld.map.id=='MAP_G01_N04' and top==game.overworld
       and not game.overworld.runner:isRunning() then break end
  end
  assert(firstBattle,'real bag interaction did not start the first Poochyena battle')
  assert(game.overworld.map.id=='MAP_G01_N04','starter rescue script did not reach Birch lab')
  local choice=C.getVar(game.save,0x4023)
  assert(game.save.party[1].species==game.data.constants.gen3Starters.species[choice+1],
    'remembered choice and actual starter disagree')
  print('[driver] PASS native bag, starter choice, first battle and Birch lab warp')
  local mon=Pokemon.new(game.data,'MEWTWO',100)
  mon.moves={{id='PSYCHIC',pp=99,maxPp=99}}
  game.save.party={mon}
  U.teleport(game,'MAP_G11_N03',5,3,'up');U.wait(30)
  local battled,complete,shown=false,false,false
  for frame=1,14000 do
    if frame%12==1 then U.tap(game,'a') else U.wait(1) end
    local top=game.stack:top()
    local name=top and top.trainer and tostring(top.trainer.name):upper()
    if top and top.enemy and name and name:find('ROXANNE',1,true) then
      battled=true
      if top.phase=='menu' and not top.showEnemyTrainer and not shown then
        love.graphics.captureScreenshot('sapphire-roxanne-battle.png');U.wait(12);shown=true
      end
    end
    if battled and game.save.flags[C.flagKey(0xA5)] and top==game.overworld and not game.overworld.runner:isRunning() then
      assert(game.save.flags[C.flagKey(0x807)],'Stone Badge missing')
      assert(game.save.inventory.TM39==1,'native TM39 reward missing')
      complete=true;break
    end
  end
  assert(complete,'Roxanne battle/reward did not finish')
  love.graphics.captureScreenshot('sapphire-roxanne-reward.png');U.wait(12)
  local braille=assert(game.data.constants.gen3Braille,'RS braille was not extracted')
  local walls=0
  for _,wall in pairs(braille.messages) do
    walls=walls+1
    assert(not wall.text:find('{',1,true),'unreadable cartridge braille cell')
  end
  assert(walls>=20 and braille.lineHeight==32,'incomplete RS braille profile')
  U.teleport(game,'MAP_G24_N71',5,7,'up');U.wait(30)
  U.tap(game,'a');U.wait(20)
  local wall=assert(game.overworld.brailleBox,'real sign did not open braille')
  assert(wall.wall.text=='ABC','wrong cartridge wall was opened')
  assert(wall.wall.textX==96 and wall.wall.textY==72,'RS text origin was ignored')
  love.graphics.captureScreenshot('sapphire-braille-wall.png');U.wait(12)
  U.tap(game,'b');U.wait(20)
  assert(not game.overworld.brailleBox and not game.overworld.runner:isRunning(),
    'closing braille did not return control')
  print('[driver] PASS cartridge braille, real sign and close/resume')
  love.filesystem.write('edition-result.json',require('src.link.Json').encode({status='pass',edition='sapphire',newGame=true,
    truckExitAndMom=true,saveReload=true,starterAndFirstBattle=true,roxanneBattleAndReward=true,brailleWall=true,
    allModsDisabled=true,fullStoryTested=false}))
  print('[driver] PASS Sapphire native new game')
  love.event.quit(0)
end
