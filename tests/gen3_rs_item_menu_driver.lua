-- Native RS bag action grids, actual inputs and explicit inventory fixtures.
return function(game)
 io.stdout:setvbuf('no');local fs=love.filesystem
 assert(fs.getIdentity():match('^gen2recomp%-qa%-'))
 local U=require('tests.drivers.util');local V=require('src.core.GameVersion');local edition=V.get()
 assert(edition=='ruby'or edition=='sapphire');local J=require('src.link.Json')
 local Bag=require('src.ui.Gen3BagMenu');local ItemMenu=require('src.ui.Gen3ItemMenu')
 local menu=assert(game.data.constants.gen3ItemMenu);assert(menu.columns==2 and menu.register==4 and not menu.deselect)
 local Cache=require('src.import.CacheFs');local Importer=require('src.import.RomImporter')
 assert(Cache.rootReport().kind~='portable'and Importer.readyReport(edition).ok)
 local raw=assert(fs.read(edition..'/rom-cache.complete'));assert(raw:find('rs%-item%-menu%-v4:'))
 local old,n=raw:gsub('rs%-item%-menu%-v4:','rs-field-window-v3:',1);assert(n==1)
 local read=Cache.read;Cache.read=function(path,...)if path=='rom-cache.complete'then return old end;return read(path,...)end
 local ok,ready=pcall(Importer.readyReport,edition);Cache.read=read;assert(ok and not ready.ok and Importer.readyReport(edition).ok)
 U.teleport(game,'MAP_G00_N16',10,12,'up');local world=game.stack:top()
 game.save.party={require('src.pokemon.Pokemon').new(game.data,'TREECKO',12)}
 local tm;for key,def in pairs(game.data.items)do if def.pocket=='TM_HM'and def.machine then tm=key;break end end
 assert(tm and game.data.items.CHERI_BERRY and game.data.items.MACH_BIKE,'Missing native item fixture')
 game.save.inventory={REPEL=2,POKE_BALL=3,MACH_BIKE=1,CHERI_BERRY=2,[tm]=1}
 game.save.bagOrder={'REPEL','POKE_BALL',tm,'CHERI_BERRY','MACH_BIKE'};game.save.repelSteps=0;game.save.registeredItem=nil
 local initial=J.encode(game.save.inventory);local party=J.encode(game.save.party)
 local function press(key)game.input:overlayPressed(key);U.wait(1);game.input:overlayReleased(key);U.wait(1)end
 local function until_(fn,seconds,label)local stop=love.timer.getTime()+seconds;repeat U.wait(1);assert(love.timer.getTime()<stop,label)until fn()end
 local function shot(name,state)
  local g=love.graphics;local c=g.newCanvas(240,160,{dpiscale=1});local depth=g.getStackDepth()
  g.push('all');local yes,why=xpcall(function()g.setCanvas(c);g.origin();g.setShader();g.setScissor();g.clear(0,0,0,0);state:draw()end,debug.traceback)
  while g.getStackDepth()>depth do g.pop()end;assert(yes,why)
  local im=c:newImageData();assert(fs.write(name..'.png',im:encode('png')));im:release();c:release()
 end
 local screen=Bag.new(game,{});game.stack:push(screen);local grids={};local expected={ITEM={'use','give','toss','cancel'},BALL={'give','blank','toss','cancel'},TM_HM={'use','give','blank','cancel'},BERRY={'checkTag','blank','use','give','toss','cancel'},KEY_ITEM={'use','register','blank','cancel'}}
 for _=1,5 do
  local key=screen.pockets[screen.pocket].key;assert(screen:selected().id)
  local rng=love.math.getRandomState();press('a');local action=game.stack:top();assert(getmetatable(action)==ItemMenu,'Native bag skipped action menu for '..key)
  assert(#action.entries==#expected[key]);local kinds={}
  for i,row in ipairs(action.entries)do assert(row.kind==expected[key][i],key..' action cell '..i);kinds[i]=row.kind end
  assert(action.columns==2 and action.rows==#expected[key]/2)
  if key=='BALL'then
   press('down');assert(action.index==3 and action.entries[action.index].kind=='toss')
   press('right');assert(action.index==4 and action.entries[action.index].kind=='cancel')
  elseif key=='BERRY'then
   press('down');assert(action.index==3 and action.entries[action.index].kind=='use')
   press('right');assert(action.index==4 and action.entries[action.index].kind=='give')
  end
  shot('rs-item-actions-'..key,action);grids[key]=kinds;press('b');assert(game.stack:top()==screen)
  assert(J.encode(game.save.inventory)==initial and J.encode(game.save.party)==party,'Native action cancellation changed items/team')
  assert(love.math.getRandomState()==rng,'Drawing/input-only action menu consumed game RNG')
  press('right')
 end
 local function pocket(key)
  for _=1,5 do if screen.pockets[screen.pocket].key==key then return end;press('right')end
  error('Native pocket not found '..key)
 end
 pocket('KEY_ITEM');press('a');local action=game.stack:top();press('right');assert(action.index==2 and action.entries[2].kind=='register');press('a')
 assert(game.stack:top()==screen and game.save.registeredItem=='MACH_BIKE'and Bag.canRegister(game,'MACH_BIKE'),'Native REGISTER did not store key item')
 press('a');action=game.stack:top();assert(action.entries[2].label==menu.labels[menu.register],'RS changed REGISTER into an invented DESELECT label')
 press('right');press('a');assert(not game.save.registeredItem and game.stack:top()==screen,'Native REGISTER did not toggle off')
 pocket('BALL');press('a');press('down');assert(game.stack:top().entries[game.stack:top().index].kind=='toss');press('a')
 assert(getmetatable(game.stack:top())==require('src.ui.QuantityBox'));press('b');assert(game.stack:top()==screen and J.encode(game.save.inventory)==initial,'Native quantity cancellation consumed balls')
 pocket('ITEM');assert(screen:selected().id=='REPEL');press('a');assert(game.stack:top().entries[1].kind=='use');press('a')
 assert(game.save.inventory.REPEL==1 and game.save.repelSteps==100,'Native USE did not consume exactly one Repel')
 until_(function()local top=game.stack:top();if top==screen then return true end;if top.done then press('a')end;return game.stack:top()==screen end,20,'Native USE message did not return to bag')
 assert(J.encode(game.save.party)==party and game.save.inventory.POKE_BALL==3 and game.save.inventory[tm]==1)
 press('b');assert(game.stack:top()==world)
 local w,h=require('src.ui.Theme').uiSize();assert(w==240 and h==160 and game.data.constants.gen3FieldMessageWindow.width==26)
 assert(fs.write('edition-result.json',J.encode({status='pass',edition=edition,nativeNoMods=true,
  actualPocketActionGrids=grids,nativeColumnMajorPositions=true,nativeDirectionalInput=true,nativeRegisterToggle=true,
  rsRegisterLabelPreserved=true,nativeQuantityCancel=true,nativeRepelUse=true,unchangedOtherItemsAndTeam=true,
  oldV3CacheRejected=true,freshV4CacheReady=true,fieldWindowPreserved=true,
  originalRSBagArtworkPorted=false,berryTagScreenImplemented=false,fullRSUI=false,fullStory=false,physicalIOSDeviceTested=false})))
 print('PASS_NATIVE_RS_ITEM_MENU '..edition);love.event.quit(0)
end
