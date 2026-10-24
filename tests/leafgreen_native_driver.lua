-- Native rendered smoke after an actual ROM import, with all mods disabled.
return function()
  local G = require('src.core.Game')
  local V = require('src.core.GameVersion')
  local U = require('tests.drivers.util')
  local function frames(n) for _=1,n do coroutine.yield() end end
  assert(V.get() == 'leafgreen')
  assert(G.data.constants.gen == 3 or G.data.constants.gen3Bag)
  local title = assert(G.data.constants.gen3FRLGTitle)
  assert(title.effect == 'leaves' and title.cry == 'VENUSAUR')
  assert(#title.streakY == 8)
  assert(title.images.flames.frames == 11)
  assert(G.data.pokemon.BULBASAUR and G.data.pokemon.VENUSAUR)
  assert(G.data.maps and next(G.data.maps))
  print('[driver] LeafGreen imported native dataset and title')
  U.tap(G,'start') -- leave the native boot movie
  frames(220)
  assert(getmetatable(G.stack:top()) == require('src.ui.Gen3TitleFRLG'))
  love.graphics.captureScreenshot('leafgreen-title.png')
  frames(3)
  U.tap(G,'a');frames(120)
  assert(getmetatable(G.stack:top()) == require('src.ui.Gen3MainMenu'))
  U.tap(G,'a')
  for _=1,1500 do
    U.tap(G,'a');frames(2)
    if G.overworld and G.stack:top()==G.overworld then break end
  end
  assert(G.overworld and G.stack:top()==G.overworld,'Oak speech/naming did not reach field')
  love.graphics.captureScreenshot('leafgreen-new-game.png');frames(3)
  local beforeX,beforeY=G.overworld.player.cellX,G.overworld.player.cellY
  U.hold(G,'down',30);frames(20)
  assert(beforeX~=G.overworld.player.cellX or beforeY~=G.overworld.player.cellY,'field movement did not advance')
  local S=require('src.core.SaveData')
  assert(S.save(G.save,G.mods))
  assert(S.saveFileExists('leafgreen'))
  assert(not S.saveFileExists('firered'),'LeafGreen wrote another edition save')
  local loaded=assert(S.load('leafgreen'))
  assert(loaded.player.name==G.save.player.name and loaded.version=='leafgreen')
  print('[driver] PASS new game, Oak speech, naming, movement, isolated save/reload')
  -- A real map-script interaction and native battle/reward chain. The party
  -- is a deliberate QA fixture so the test does not need hours of grinding.
  local C=require('src.script.Gen3Commands')
  local Pokemon=require('src.pokemon.Pokemon')
  local mon=Pokemon.new(G.data,'MEWTWO',100)
  mon.moves={{id='PSYCHIC',pp=99,maxPp=99}}
  G.save.party={mon}
  U.teleport(G,'MAP_G06_N02',6,6,'up');frames(30)
  local battled,completed=false,false
  for frame=1,14000 do
    if frame%12==1 then U.tap(G,'a') else frames(1) end
    local top=G.stack:top()
    local name=top and top.trainer and tostring(top.trainer.name):upper()
    if top and top.enemy and name and name:find('BROCK',1,true) and not battled then
      battled=true;frames(180)
      love.graphics.captureScreenshot('leafgreen-brock-battle.png');frames(3)
    end
    if battled and G.save.flags[C.flagKey(0x254)] and top==G.overworld and not G.overworld.runner:isRunning() then
      assert(G.save.flags[C.flagKey(0x820)],'Boulder Badge missing')
      assert(G.save.inventory.TM39==1 and G.save.inventory.TM_CASE==1,'native TM reward chain failed')
      completed=true;break
    end
  end
  assert(completed,'Brock battle/reward script did not complete')
  love.graphics.captureScreenshot('leafgreen-brock-reward.png');frames(3)
  local result={status='pass',edition=V.get(),stage='native-import-and-title',
    allModsDisabled=true,newGame=true,movement=true,saveReload=true,brockBattleAndReward=true,
    physicalIOSDeviceTested=false,fullStoryTested=false}
  love.filesystem.write('edition-result.json',require('src.link.Json').encode(result))
  print('[driver] PASS LeafGreen native import and rendered title')
  love.event.quit(0)
end
