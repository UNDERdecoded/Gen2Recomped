package.path = './?.lua;' .. package.path
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
package.loaded['src.render.Assets'] = { image = function() return nil end, register = function() end }
package.loaded['src.render.Font'] = { draw = function() end, width = function(s) return #s * 6 end }
package.loaded['src.core.Logger'] = { warn = function() end, info = function() end }
package.loaded['src.core.Strings'] = function(s) return s end
package.loaded['src.core.GameVersion'] = { isGen2 = function() return false end,
  isGen3 = function() return false end, get = function() return 'platinum' end }
package.loaded['src.ui.SecondScreen'] = { toLocal = function(_, x, y)
  if x >= 0 and x < 256 and y >= 0 and y < 192 then return x, y end
end }
love = { math = { random = math.random } }
local P = require('src.ui.Gen4Poketch')
local game = { save = { inventory = {}, money = 5000 }, data = { gen4_menus = {
 poketch = { apps = { {name='Counter'}, {name='Calculator'}, {name='Memo Pad'},
 {name='Stopwatch'}, {name='Kitchen Timer'} } } } }, stack = { pop = function() end } }
local watch = P.new(game)
check(watch:touchpressed(1, 114, 128) and game.save.poketch.counter == 1, 'counter touch')
watch:touchreleased(1)
watch:touchpressed(1, 240, 120)
check(watch.index == 2, 'next bezel button')
watch:touchreleased(1)
watch:calculate('8'); watch:calculate('/'); watch:calculate('2'); watch:calculate('=')
check(game.save.poketch.calculator.display == '4', 'calculator divide')
watch:calculate('/'); watch:calculate('0'); watch:calculate('=')
check(game.save.poketch.calculator.display == 'ERROR', 'divide by zero')
check(not watch:touchpressed(1, 300, 20), 'outside panel falls through')
watch.index = 3; watch:touchpressed(7, 30, 30); watch:touchmoved(7, 40, 40)
check(next(game.save.poketch.memo) ~= nil, 'memo drag persists')
check(not watch:touchmoved(8, 40, 40), 'unclaimed finger ignored')
check(watch:touchreleased(7), 'release claimed finger')
watch.index = 4; watch:activate()
game.input = { wasPressed = function() return false end }
watch:update(0.5)
require('src.pokemon.Gen4PoketchState').tick(game, 0.5)
check(game.save.poketch.stopwatch == 0.5, 'stopwatch advances')
watch.index = 5; watch:activate(); watch:update(1)
require('src.pokemon.Gen4PoketchState').tick(game, 1)
check(game.save.poketch.timer == 59, 'timer counts down')
local Shop = require('src.ui.Gen4ShopMenu')
game.data.items = { [4]={name='Poke Ball',price=200}, [12]={name='Premier Ball',price=0},
 [17]={name='Potion',price=300}, [428]={name='Explorer Kit',price=0,fieldPocket=7} }
game.data.constants = { bagSize = 20 }
local shop = Shop.new(game, {4,17})
shop:choose(); shop:choose(); shop.qty = 10; shop:choose(); shop:choose()
check(game.save.inventory[4] == 10 and game.save.money == 3000, 'numeric item purchase')
check(game.save.inventory[12] == 1, 'Premier Ball bonus')
-- SELL is Platinum's Bag (BAG_MODE_SELL_ITEMS): the shop opens the Bag in pick
-- mode and sells what it hands back, so the item arrives through sellItem
-- rather than a list drawn on the counter
local bagOpened
local realScreens = package.loaded['src.ui.Screens']
package.loaded['src.ui.Screens'] = { push = function(_, id, opts) bagOpened = { id = id, opts = opts } end }
shop:back(); shop.cursor = 2; shop:choose()
package.loaded['src.ui.Screens'] = realScreens
check(shop.mode == 'sell' and bagOpened and bagOpened.id == 'BagMenu' and bagOpened.opts.pick,
 'SELL opens the Bag to pick from')
shop:sellItem(4); shop.qty = 2; shop:choose(); shop:choose()
check(game.save.inventory[4] == 8 and game.save.money == 3200, 'sell transaction')
game.save.inventory[428] = 1
shop:sellItem(428)
check(shop.mode == 'sell' and shop.item ~= 428, 'key item cannot be sold')
local VM = require('src.script.Gen4ScriptVM')
local rows = VM.lower({{name='messagevar',args={32772}}, {name='playpokecenterhealinganimation',args={32774}}},
 {member=211,bankFor=function() return 361 end})
check(rows[1][1] == 'g4_message_var' and rows[1][3] == 361, 'nurse shared message bank preserved')
check(rows[2][1] == 'g4_heal_animation', 'healing animation is lowered')
game.data.isGen4Cache = true
local pushed, quit = nil, false
game.stack.push = function(_, screen) pushed = screen end
local Screens = require('src.ui.Screens')
local screen = Screens.push(game, 'ShopMenu', {4,17}, function() quit = true end)
check(screen == pushed and screen.screenId == 'Gen4ShopMenu', 'Platinum shop alias')
-- SEE YA! says "Please come again!" first (shop_menu.c); the counter ends,
-- and the script resumes, at finish
screen:close()
check(not quit and screen.mode == 'exit', 'SEE YA! shows the parting line before the counter closes')
screen:finish()
check(quit, 'positional shop callback preserved so script resumes')
local scissors = {}
love.graphics = { setColor=function() end, rectangle=function() end, setLineWidth=function() end,
 getScissor=function() return 0,0,512,384 end,
 transformPoint=function(x,y) return x*2+100,y*2+50 end,
 setScissor=function(...) scissors[#scissors+1]={...} end }
watch.index = 1; watch:drawWatch()
check(scissors[1][1] == 132 and scissors[1][2] == 82 and scissors[1][3] == 384,
 'LCD scissor follows inset/scale transform')
check(scissors[#scissors][3] == 512, 'outer scissor restored')
for _, name in ipairs({'Gen4Model','Gen4TexAnim','Gen4Camera','Gen4Shade','Gen4View'}) do
  package.loaded['src.render.' .. name] = {}
end
local Ground = require('src.render.Gen4Ground')
local Archives = require('src.import.Gen4Archives')
local machine = Archives.find('/fielddata/build_model/build_model.narc', 'pokecenter_healing_machine.nsbmd')
local ball = Archives.find('/fielddata/build_model/build_model.narc', 'pokecenter_healing_machine_mini_pokeball.nsbmd')
check(machine ~= nil and ball ~= nil, 'native healing models are indexed')
local dropped = 0
local ground = setmetatable({ def={}, grid={land={10}}, terrain={chunks={ [10]={objects={
  {model=machine,x=20,y=30,z=40} }}}},
  dropBakes=function() dropped=dropped+1 end,
  signpostsFor=function() return {} end }, {__index=Ground})
ground:setHealingBalls(6, true)
check(#ground.healingProps[10] == 6 and ground.healingProps[10][1].model == ball,
 'six native party balls')
check(ground.healingProps[10][1].x == 15.5 and ground.healingProps[10][6].z == 44.5,
 'healing props use console-relative coordinates')
ground:setHealingBalls(6, true)
check(dropped == 1, 'unchanged healing frame does not rebake')
check(#ground:objectsFor(10, ground.terrain.chunks[10]) == 7, 'healing props join map geometry')
ground:setHealingBalls(0)
check(ground.healingProps == nil and dropped == 2, 'healing props cleared')
game.data.type_chart = {matchups={
 {attacker='FIRE',defender='GRASS',multiplier=20},
 {attacker='FIRE',defender='WATER',multiplier=5},
 {attacker='NORMAL',defender='GHOST',multiplier=0} }}
game.save.poketch.moveTester = {2,5,3}
check(watch:moveEffectiveness() == 1, 'dual-type resistance and weakness cancel')
game.save.poketch.moveTester = {2,5,5}
check(watch:moveEffectiveness() == 2, 'duplicate defender type applied once')
game.save.poketch.moveTester = {1,14,18}
check(watch:moveEffectiveness() == 0, 'Move Tester immunity')
local State = require('src.pokemon.Gen4PoketchState')
game.save.poketch.history = nil
for i=1,14 do State.remember(game,{species=i,level=i}) end
check(#game.save.poketch.history == 12 and game.save.poketch.history[1].species == 14,
 'history keeps the twelve latest successful acquisitions')
State.remember(game,{species=99,isEgg=true})
check(game.save.poketch.history[1].species == 14, 'unhatched egg omitted from history')
local acquired = {species=15}; State.remember(game,acquired); acquired.species=16
check(game.save.poketch.history[1].species == 15, 'history snapshot survives evolution')
game.data.pokemon = {[1]={name='A',genderRatio=127,eggGroups={1,1}},
 [2]={name='B',genderRatio=127,eggGroups={1,1}},
 [132]={name='Ditto',genderRatio=255,eggGroups={13,13}},
 [3]={name='Baby',genderRatio=127,eggGroups={15,15}}}
local a,b = {species=1,personality=0,otId=1},{species=1,personality=255,otId=2}
check(State.compatibility(game.data,a,b)==70, 'same species, different trainers')
b.otId=1
check(State.compatibility(game.data,a,b)==50, 'same species, same trainer')
b.species=2
check(State.compatibility(game.data,a,b)==20, 'different species, same trainer')
b.personality=0
check(State.compatibility(game.data,a,b)==0, 'same genders incompatible')
b.species=132
check(State.compatibility(game.data,a,b)==20, 'numeric Platinum Ditto ignores gender and groups')
b.species=3
check(State.compatibility(game.data,a,b)==0, 'undiscovered egg group cannot breed')
game.save.poketch.timer=1; game.save.poketch.timerRunning=true
State.tick(game,2)
check(game.save.poketch.timerFinished and not game.save.poketch.timerRunning,
 'timer finishes with watch closed')
game.save.party = {a,b,{species=2,personality=255,otId=1}, {species=3,isEgg=true}}
game.data.gen4_menus.poketch.apps[#watch.apps+1] = {name='Matchup Checker'}
watch.index=#watch.apps
watch:touchpressed(1,48,144); watch:touchreleased(1)
check(game.save.poketch.matchup[1]==3 and game.save.poketch.matchup[2]==2,
 'Matchup selection skips the other Pokemon and eggs')
watch:touchpressed(1,112,144); watch:touchreleased(1)
check(game.save.poketch.compatibility==0, 'Matchup check uses selected party pair')
package.loaded['src.script.Commands'] = {meta={}}
require('src.script.Gen4Commands')
local commands = package.loaded['src.script.Commands']
local yielded,resumed=0,0
game.data.constants.martSpecialties = {[7]={17}}
game.save.gen4Vars = {[0x8004]=7}
commands.g4_pokemart({game=game,save=game.save,runner={
 yield=function() yielded=yielded+1 end,resume=function() resumed=resumed+1 end}},0x8004,'specialty')
check(pushed.stock[1]==17 and yielded==1, 'specialty clerk resolves variable stock ID and waits')
pushed:close()
pushed:finish()
check(resumed==1, 'specialty clerk resumes after closing shop')
local seal = VM.lower({{name='pokemartseal',args={0x8004}}},{})
check(seal[1][3]=='seal', 'seal inventory is not treated as specialty bag items')
local berryText=VM.lower({{name='bufferberryname',args={2,149,1}}},{})
check(berryText[1][2]==2 and berryText[1][3]=='item' and berryText[1][4]==149,
 'berry text buffer preserves slot and item argument order')
local oldRenderer=package.loaded['src.render.Renderer']
package.loaded['src.render.Renderer']={uiPresentation={x=100,y=50,w=512,h=384,scaleX=2,scaleY=2}}
local touchShop=Shop.new(game,{17})
local function tap(x,y) return touchShop:touchpressed(1,100+x*2,50+y*2) end
check(not touchShop:touchpressed(1,90,60),'shop rejects touches outside presented UI')
-- BUY / SELL / SEE YA! is the framed window at tile (1, 1) over the field
tap(40,12)
check(touchShop.mode=='buy','scaled touch selects buy')
-- the counter takes input once the field camera has slid over (Shop_MoveCamera)
check(not touchShop:counterUp(),'the counter waits for the camera')
touchShop.camStep=touchShop:cameraTarget()
check(touchShop:counterUp(),'the counter is up once the camera arrives')
tap(120,20)
check(touchShop.mode=='quantity','scaled touch selects stock item')
-- the cartridge's own windows (shop_menu.c): the quantity window at (19, 13)
-- with its up/down marks at x 162, then YES / NO at (23, 13)
tap(160,104)
check(touchShop.qty==2,'touch quantity plus')
tap(200,112)
check(touchShop.mode=='confirm','touch quantity confirmation')
local money=game.save.money
tap(200,104)
check(game.save.money==money-600 and touchShop.mode=='buy','touch purchase completes once')
tap(220,176)
check(touchShop.mode=='menu','touch back returns to shop menu')
package.loaded['src.render.Renderer']=oldRenderer
local Map=require('src.import.Gen4PoketchMap')
game.data.constants.gen4PoketchRoutes={[342]={x=47,y=150},[343]={x=56,y=144}}
game.save.gen4Roamers={[0]={active=true,route=0},[1]={active=false,route=1},
 [3]={active=true,map='R202'}}
local roaming=Map.roamers(game)
check(#roaming==2,'map shows active roamers including older map-name saves')
game.save.gen4Roamers[0].route=1
for _,at in ipairs(Map.roamers(game)) do check(at.x==56 and at.y==144,'map follows current roamer route') end
game.save.gen4Roamers[0].active=false
check(#Map.roamers(game)==1,'retired roamer disappears from map')
local iconCalls,boxes={},{}
local oldIcon=watch.drawMonIcon
watch.drawMonIcon=function(_,mon,x,y) iconCalls[#iconCalls+1]={mon,x,y}; return true end
local oldRectangle=love.graphics.rectangle
love.graphics.rectangle=function(_,x,y,w,h) boxes[#boxes+1]={x,y,w,h} end
game.save.party={}
for i=1,6 do game.save.party[i]={species=1,hp=5,stats={hp=10},friendship=100} end
watch:drawPartyStatus()
check(#iconCalls==6 and #boxes==12,'party screen renders six icons and HP bars')
for _,b in ipairs(boxes) do
 check(b[1]>=16 and b[1]+b[3]<=208 and b[2]>=16 and b[2]+b[4]<=176,
 'party HP bars fit LCD')
end
iconCalls={}; watch:drawFriendship()
check(#iconCalls==6,'friendship screen renders party icons')
game.save.daycare={breed={{mon=game.save.party[1]},{mon=game.save.party[2]}}}
iconCalls={}; watch:drawDaycare()
check(#iconCalls==2,'daycare screen renders deposited Pokemon icons')
watch.drawMonIcon=oldIcon
love.graphics.rectangle=oldRectangle
local oldPokemon=game.data.pokemon
game.data.pokemon=nil
check(not watch:drawMonIcon({species=999},24,24),'missing icon and species table fall back safely')
game.data.pokemon=oldPokemon
game.overworld={map={id='test',def={signs={
 {x=10,y=10,script=8000,pickup={kind='hidden',range=0}},
 {x=11,y=10,script=8001,pickup={kind='hidden',range=1}},
 {x=18,y=10,script=8002,pickup={kind='hidden',range=2}}}}},
 player={cellX=10,cellY=10}}
game.save.flags={}
local scan=State.dowsing(game,112,101)
check(scan.kind==2 and #scan.items==2,'tap detects items inside their own ROM ranges')
scan=State.dowsing(game,104,101)
check(#scan.items==2,'eight-pixel detection boundary is inclusive')
scan=State.dowsing(game,103,101)
check(#scan.items==1,'range-zero item disappears beyond eight pixels')
scan=State.dowsing(game,80,101)
check(scan.kind==1 and #scan.items==0,'distant tap yields faint signal without exact markers')
scan=State.dowsing(game,24,24)
check(scan.kind==0 and #scan.items==0,'unrelated tap does not expose map-wide hidden items')
game.save.flags.FLAG_G4_02DA=true
scan=State.dowsing(game,112,101)
check(#scan.items==1,'collected ROM flag excludes hidden item from scan')
game.save.flags.FLAG_G4_02DB=true
check(State.dowsing(game,112,101).kind==0,'out-of-range tile and collected items yield no signal')
watch.apps[#watch.apps+1]={name='Dowsing Machine'}; watch.index=#watch.apps
watch:touchpressed(1,80,101); watch:touchreleased(1)
check(watch.dowsingResult.x==80 and watch.dowsingResult.y==101,'scan uses actual LCD tap coordinates')
watch:activate()
check(watch.dowsingResult.x==112 and watch.dowsingResult.y==101,'button scan targets player center')
watch.apps[#watch.apps+1]={name='Coin Toss'}; watch.index=#watch.apps
watch:activate()
local toss=watch.coinAnimation
check(toss and toss.y==144 and toss.speed==-10.5,'coin toss starts at native resting position and speed')
watch:activate()
check(watch.coinAnimation==toss,'touches during toss do not restart animation')
watch:updateCoin(1/60)
check(toss.y==133.5 and toss.ticks==1,'coin rises on first animation tick')
watch:updateCoin(5)
check(not watch.coinAnimation,'coin settles after damped bounces')
local Sprites=require('src.import.Gen4PoketchSprites')
local spin={{cell=5,duration=2},{cell=9,duration=3}}
check(Sprites.spinCell(spin,0)==5 and Sprites.spinCell(spin,2)==9
 and Sprites.spinCell(spin,5)==5,'coin animation obeys ROM durations and loops')
watch.apps[#watch.apps+1]={name='Marking Map'}; watch.index=#watch.apps
local markers,order=watch:mapMarkers()
check(#markers==6 and #order==6,'map initializes six persistent draggable markers')
watch:touchpressed(3,32,164)
check(watch.activeMapMarker==1 and order[6]==1,'touch selects marker and raises its priority')
watch:touchmoved(3,100,80)
check(markers[1].x==100 and markers[1].y==80,'held touch drags map marker')
watch:touchmoved(4,120,90)
check(markers[1].x==100,'unrelated touch cannot drag selected marker')
watch:touchmoved(3,220,180)
check(markers[1].x==200 and markers[1].y==168,'drag clamps marker inside map display')
watch:touchreleased(3)
check(not watch.activeMapMarker and watch:mapMarkers()==markers,'release retains position and clears drag')
watch:touchpressed(3,90,90)
check(not watch.activeMapMarker,'empty-map tap does not create arbitrary dots')
watch:touchreleased(3)
local function app(name)
  for i,a in ipairs(watch.apps) do if a.name==name then watch.index=i; return end end
  watch.apps[#watch.apps+1]={name=name}; watch.index=#watch.apps
end
local function tap(x,y) watch:touchpressed('mouse',x,y); watch:touchreleased('mouse') end
app('Calculator'); game.save.poketch.calculator=nil
tap(144,64); tap(48,64); tap(144,96); tap(112,128); tap(160,160)
check(game.save.poketch.calculator.display=='10','calculator painted keys work through mouse pointer ID')
app('Memo Pad'); game.save.poketch.memo={}; game.save.poketch.memoErasing=false
tap(100,100); local memo=game.save.poketch.memo
check(next(memo)~=nil,'memo drawing accepts mouse click')
tap(112,152); tap(100,100)
check(next(memo)==nil,'memo eraser deletes touched pixels')
tap(112,152); tap(100,100); tap(176,152)
check(next(game.save.poketch.memo)==nil,'memo clear touch empties drawing')
app('Dot Artist'); game.save.poketch.dots={}
tap(20,20); tap(20,20)
check(game.save.poketch.dots[0]==2,'dot artist repeated clicks cycle pixel shades')
app('Stopwatch'); game.save.poketch.stopwatch=5; game.save.poketch.stopwatchRunning=false
tap(112,112); check(game.save.poketch.stopwatchRunning,'stopwatch start text is clickable')
tap(112,144); check(game.save.poketch.stopwatch==0 and not game.save.poketch.stopwatchRunning,'stopwatch reset text is clickable')
app('Kitchen Timer'); game.save.poketch.timerDuration=60; game.save.poketch.timerRunning=false
tap(88,104); tap(136,104)
check(game.save.poketch.timerDuration==121,'timer digits adjust minutes and seconds')
tap(112,144); check(game.save.poketch.timerRunning,'timer start label is clickable')
tap(112,144); check(not game.save.poketch.timerRunning,'timer stop label is clickable')
app('Alarm Clock'); game.save.poketch.alarmHour=0; game.save.poketch.alarmMinute=0; game.save.poketch.alarmEnabled=false
tap(88,112); tap(136,112); tap(112,152)
check(game.save.poketch.alarmHour==1 and game.save.poketch.alarmMinute==1 and game.save.poketch.alarmEnabled,'alarm digits and on/off text are clickable')
app('Move Tester'); game.save.poketch.moveTester={1,1,18}
tap(28,128); tap(116,128); tap(108,40); tap(196,40); tap(108,72); tap(196,72)
check(game.save.poketch.moveTester[1]==1 and game.save.poketch.moveTester[2]==1
 and game.save.poketch.moveTester[3]==18,'all six native Move Tester arrows wrap both directions')
tap(152,40)
check(game.save.poketch.moveTester[2]==1,'type label does not trigger an unrelated arrow')
app('Counter'); game.save.poketch.counter=5; tap(114,128)
check(game.save.poketch.counter==6,'native counter button accepts mouse click')
app('Pedometer'); game.save.poketch.steps=5; tap(114,128)
check(game.save.poketch.steps==0,'pedometer reset accepts touch')
app('Color Changer'); watch:touchpressed('mouse',48,140); watch:touchmoved('mouse',183,140); watch:touchreleased('mouse')
check(game.save.poketch.color==7,'color slider responds to mouse dragging')
local cries={}; package.loaded['src.core.Sound']={playCry=function(_,species) cries[#cries+1]=species end}
app('Pokémon List'); tap(48,48)
app('Pokémon History'); tap(32,32)
app('Friendship Checker'); tap(32,40)
check(#cries==3 and watch.friendshipTouch,'Pokemon icon apps accept clicks and give feedback')
app('Calendar')
local now=os.date('*t'); local first=((now.wday-1)-(now.day-1)%7)%7
local cell=first+now.day-1; local dateKey=('%04d-%02d-%02d'):format(now.year,now.month,now.day)
game.save.poketch.calendar={}
tap(33+(cell%7)*20,43+math.floor(cell/7)*14)
check(game.save.poketch.calendar[dateKey],'calendar date cell accepts click')
app('Roulette'); tap(112,96)
check(type(game.save.poketch.roulette)=='number','roulette accepts click')
-- Execute the actual desktop callbacks without POKEPORT_TOUCH enabled.
local file=assert(io.open('main.lua','rb')); local source=file:read('*a'); file:close()
local callbacks={}
for _,name in ipairs({'mousepressed','mousereleased','mousemoved'}) do
 callbacks[#callbacks+1]=assert(source:match('function love%.'..name..'.-\nend'))
end
local events={}
local fakeGame={hasPointerScreen=function() return true end,
 cameraLook=function() error('camera must not intercept an interactive screen drag') end,
 touchpressed=function(_,id) events[#events+1]='press:'..id end,
 touchreleased=function(_,id) events[#events+1]='release:'..id end,
 touchmoved=function(_,id) events[#events+1]='move:'..id end}
love.mouse={isDown=function() return true end}
assert(loadstring('local Game=...; local mouseTouch=false; '..table.concat(callbacks,'\n')))(fakeGame)
love.mousepressed(100,100,1,false); love.mousemoved(101,100,1,0); love.mousereleased(101,100,1)
check(events[1]=='press:mouse' and events[2]=='move:mouse' and events[3]=='release:mouse','desktop mouse callbacks work without environment flag')
love.mousepressed(100,100,1,true)
check(#events==3,'synthetic mouse press does not double-fire a touch')
for _, file in ipairs({'src/ui/Gen4Poketch.lua','src/ui/Gen4ShopMenu.lua',
 'src/import/Gen4Screens.lua','src/import/RomExtractorGen4.lua','src/import/RomImporter.lua',
 'src/inventory/Bag.lua','src/script/Gen4Commands.lua','src/script/Gen4ScriptVM.lua',
 'src/ui/Screens.lua','src/render/Gen4Ground.lua','src/world/OverworldController.lua',
 'src/pokemon/Gen4PoketchState.lua','src/pokemon/DayCare.lua','src/core/Game.lua',
 'src/battle/BattleState.lua','src/script/Commands.lua','src/import/Gen4Mart.lua',
 'src/render/Renderer.lua','src/import/Gen4PoketchMap.lua','src/import/Gen4PoketchSprites.lua',
 'src/ui/SecondScreen.lua','main.lua'}) do
 check(loadfile(file) ~= nil, 'syntax: ' .. file)
end
local priorPokemon,priorBattle=package.loaded['src.pokemon.Pokemon'],package.loaded['src.battle.BattleState']
package.loaded['src.pokemon.Pokemon']={new=function(_,species,level) return {species=species,level=level} end}
local tutorial
package.loaded['src.battle.BattleState']={newWild=function(g,species,level)
 tutorial={game=g,species=species,level=level,makeDudeDemo=function(b,name) b.demoName=name end}
 return tutorial
end}
local demoSave={party={{species=387}},inventory={[4]=3},player={name='PLAYER',gender='boy'},
 gen4Starter=387,pokedex={seen={},owned={}}}
local demoYield,demoResume=0,0
local demoGame={save=demoSave,data={},stack={push=function(_,b) check(b==tutorial,'tutorial pushed to battle stack') end}}
commands.g4_catching_tutorial({game=demoGame,save=demoSave,runner={
 yield=function() demoYield=demoYield+1 end,resume=function() demoResume=demoResume+1 end}})
check(tutorial.species==399 and tutorial.level==2,'tutorial target is level 2 Bidoof')
check(tutorial.game.save.party[1].species==393 and tutorial.game.save.party[1].level==5,'Dawn uses counterpart starter')
check(tutorial.demoName=='Dawn' and tutorial.game.save.inventory[4]==20,'tutorial name and twenty demo balls')
check(demoYield==1 and demoResume==0,'dialogue waits for demo battle')
tutorial.onFinish()
check(demoResume==1 and demoSave.party[1].species==387 and demoSave.inventory[4]==3
 and demoSave.player.name=='PLAYER','demo finishes without changing player party, bag or name')
package.loaded['src.pokemon.Pokemon'],package.loaded['src.battle.BattleState']=priorPokemon,priorBattle
print(checks .. ' checks passed')
