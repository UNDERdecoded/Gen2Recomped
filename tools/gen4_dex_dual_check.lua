package.path='./?.lua;'..package.path
local checks=0;local function check(v,why) assert(v,why);checks=checks+1 end
local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
local images=require('src.import.Gen4Dex').images(rom)
for _,mode in ipairs({'sinnoh','national'}) do
 for _,name in ipairs({'entry','banner','panel'}) do
  local pic=images['dex/'..name..'_'..mode]
  check(pic and pic.width==256 and pic.height==192,'native '..name..' '..mode..' dimensions')
 end
end
check(images['dex/entry_sinnoh'].rgba==images['dex/entry_national'].rgba,'National mode preserves shared Info window palette rows')
check(images['dex/banner_sinnoh'].rgba~=images['dex/banner_national'].rgba,'National banner differs')
check(images['dex/panel_sinnoh'].rgba==images['dex/panel_national'].rgba,'National mode preserves shared lower panel window palette rows')
for i=0,5 do
 local pic=images[('dex/page_button_%02d'):format(i)]
 check(pic and pic.originX and pic.originY,'native button OAM origin '..i)
 local visible=false;for at=4,#pic.rgba,4 do if pic.rgba:byte(at)>0 then visible=true;break end end
 check(visible,'visible native button '..i)
end
package.loaded['src.core.GameVersion']={get=function() return 'platinum' end,isDualScreen=function() return true end}
package.loaded['src.core.Logger']={warn=function() end,info=function() end}
package.loaded['src.render.Font']={draw=function() end,fit=function(s) return s end,width=function(s) return #s*6 end}
local renderer={uiPresentation={x=10,y=20,w=512,h=384,scaleX=2,scaleY=2}}
package.loaded['src.render.Renderer']=renderer
local cries=0;local stopped=0
package.loaded['src.core.Sound']={playCry=function() cries=cries+1;return {stop=function() stopped=stopped+1 end} end}
local target;local calls={}
love={graphics={setColor=function() end,rectangle=function() end,push=function() end,pop=function() end,
 translate=function() end,scale=function() end,origin=function() end,setScissor=function() end,clear=function() end,
 getCanvas=function() return target end,setCanvas=function(v) target=v end,
 newCanvas=function(w,h) return {w=w,h=h,setFilter=function() end} end,
 draw=function(image,x,y) calls[#calls+1]={path=image.path,target=target,x=x,y=y} end}}
package.loaded['src.render.Assets']={image=function(path)
 local pic=images[path];local w,h=pic and pic.width or 80,pic and pic.height or 80
 return {path=path,setFilter=function() end,getWidth=function() return w end,getHeight=function() return h end,getDimensions=function() return w,h end}
end}
local SS=require('src.ui.SecondScreen');SS._setTransport({available=function() return true end})
local Dex=require('src.ui.Gen4Pokedex')
local data={isGen4Cache=true,constants={gen=4},pokemon={[387]={name='TURTWIG',types={'GRASS'}}},
 gen4_dex={orders={sinnoh={387},national={387}}},gen4_graphics={screens={}}}
for key,pic in pairs(images) do data.gen4_graphics.screens[key]={path=key,originX=pic.originX,originY=pic.originY} end
local game={data=data,save={options={secondScreenMode='display'},pokedex={seen={[387]=true},owned={[387]=true},canDetectForms=true}},stack={pop=function() end}}
local dex=Dex.new(game);dex.page='entry'
game.offerPointer=function(_,method,id,x,y) return dex[method](dex,id,x,y) end
game.touchpressed=function(_,id,x,y) return game:offerPointer('touchpressed',id,x,y) end
dex:draw()
check(game.secondScreenDrawnThisFrame and game.secondScreenCanvas and target==nil,'Dex owns lower surface and restores top target')
local top,panel=false,false
for _,call in ipairs(calls) do
 if call.path=='dex/entry_sinnoh' and call.target==nil then top=true end
 if call.path=='dex/panel_sinnoh' and call.target==game.secondScreenCanvas then panel=true end
end
check(top and panel,'native top and bottom artwork render on separate targets')
check(not dex:touchpressed('mouse',10+68*2,20+24*2) and dex.tab==1,'top-window click cannot select lower-panel Area')
check(SS.injectTouch(game,'touchpressed','finger',68,24) and dex.tab==2,'physical lower panel selects Area')
dex:playCry();check(SS.injectTouch(game,'touchpressed','finger',108,24) and dex.tab==3 and stopped==1,'changing page stops previous cry')
SS.injectTouch(game,'touchpressed','finger',180,131);check(cries==2,'physical Cry replay')
game.touchreleased=function(_,id,x,y) return game:offerPointer('touchreleased',id,x,y) end
SS.injectTouch(game,'touchreleased','finger',180,131)
SS.injectTouch(game,'touchpressed','finger',188,24);check(dex.tab==5,'unlocked physical Forms')
SS.injectTouch(game,'touchpressed','finger',228,24);check(dex.page=='list','native Back button returns to list')
dex.page='entry';game.save.pokedex.owned={};game.save.pokedex.canDetectForms=false;dex.tab=1
SS.injectTouch(game,'touchpressed','finger',148,24);check(dex.tab==1,'physical Size remains capture-only')
SS.injectTouch(game,'touchpressed','finger',188,24);check(dex.tab==1,'physical Forms respects story upgrade')
game.save.options.secondScreenMode='inset'
local x,y,scale=SS.rect(game)
check(dex:touchpressed('mouse',10+(x+68*scale)*2,20+(y+24*scale)*2) and dex.tab==2,'scaled inset mouse uses lower-panel coordinates')
game.save.options.secondScreenMode='swap';game.secondScreenUp=true;dex.tab=1
check(dex:touchpressed('finger',10+108*2,20+24*2) and dex.tab==3,'scaled swapped touch selects Cry')
game.secondScreenUp=false;check(not dex:bottomVisible(),'lowered swap preserves combined single-screen controls')
game.save.options.secondScreenMode='off';check(not dex:bottomVisible(),'single-screen mode retains controls')
game.save.options.secondScreenMode='display';game.save.pokedex.national=true;dex.national=true;dex.tab=1;calls={};dex:draw()
local nationalTop,nationalBottom=false,false
for _,call in ipairs(calls) do
 if call.path=='dex/entry_national' then nationalTop=true end
 if call.path=='dex/panel_national' then nationalBottom=true end
end
check(nationalTop and nationalBottom,'National mode selects both correct palette variants')
check(dex:toggleDex() and not dex.national and game.save.pokedex.national,'regional view preserves National unlock')
check(dex:toggleDex() and dex.national and dex.index==1,'National switching resets cursor like native list')
game.save.pokedex.national=false;check(not dex:toggleDex(),'switching blocked before National upgrade')
game.save.pokedex.national=true;dex.page='list';dex.national=false
game.input={wasPressed=function(_,key) return key=='select' end};dex:update()
check(dex.national and dex.page=='list','native SELECT toggles regional/National listing')

local Search=require('src.ui.Gen4DexSearch')
local orders=require('src.import.Gen4Dex').orders(rom)
check(#Search.DATA_KEYS==47,'native archive carries 47 order/membership lists')
for _,key in ipairs(Search.DATA_KEYS) do check(orders[key] and #orders[key]>0,'native membership '..key) end
for _,mode in ipairs({'sinnoh','national','filtered'}) do
 local pic=images['dex/list_panel_'..mode]
 check(pic and pic.width==256 and pic.height==192,'native scroll companion '..mode)
end
check(images['dex/list_panel_sinnoh'].rgba~=images['dex/list_panel_national'].rgba,'scroll row-three National palette differs')
check(images['dex/list_wheel'].width==256,'native affine wheel dimensions')
for i=0,5 do check(images[('dex/list_button_%02d'):format(i)].originX~=nil,'scroll button OAM origin '..i) end
for _,key in ipairs({'order','name','type','form'}) do check(images['dex/search_'..key].width==256,'native search selection '..key) end
for i=1,14 do check(images[('dex/search_shape_%02d'):format(i)].originX~=nil,'native body silhouette '..i) end
data.gen4_dex.orders=orders;game.save.pokedex.seen={};game.save.pokedex.owned={};game.save.pokedex.national=true
for _,id in ipairs(orders.national) do data.pokemon[id]={name=tostring(id)};game.save.pokedex.seen[id]=true end
dex=Dex.new(game);dex.national=false;dex.entries=dex:listing()
local selection=Search.defaults()
check(#Search.results(dex,selection)==210,'regional numerical search includes all 210 seen species without blanks')
selection[1]=2
local alphabetical=Search.results(dex,selection)
check(#alphabetical==210,'alphabetical search includes seen-only species')
local expected={};local regional={};for _,id in ipairs(orders.sinnoh) do regional[id]=true end
for _,id in ipairs(orders.alphabetical) do if regional[id] then expected[#expected+1]=id end end
check(table.concat(alphabetical,',')==table.concat(expected,','),'alphabetical search preserves native archive ordering')
selection[1]=3;check(#Search.results(dex,selection)==0,'heaviest excludes uncaught')
game.save.pokedex.owned[387]=true;game.save.pokedex.owned[390]=true;game.save.pokedex.owned[393]=true
check(#Search.results(dex,selection)==3,'heaviest includes captured regional starters')
selection=Search.defaults();selection[3]=13
local grass=Search.results(dex,selection);check(#grass==1 and grass[1]==387,'type search is caught-only')
selection[4]=11;check(#Search.results(dex,selection)==0,'two types intersect rather than combine')
selection=Search.defaults();selection[2]=8
local names=Search.results(dex,selection);check(#names>3,'native STU group includes seen-only entries')
selection=Search.defaults();selection[5]=2
local shapes=Search.results(dex,selection);check(#shapes>3,'body shape search includes seen-only entries')

game.input={wasPressed=function() return false end};calls={};dex:draw()
local listPanel=false;for _,call in ipairs(calls) do if call.path=='dex/list_panel_sinnoh' and call.target==game.secondScreenCanvas then listPanel=true end end
check(listPanel and game.secondScreenDrawnThisFrame,'list owns native lower companion instead of overworld watch')
game.touchmoved=function(_,id,x,y) return game:offerPointer('touchmoved',id,x,y) end
game.touchreleased=function(_,id,x,y) return game:offerPointer('touchreleased',id,x,y) end
dex.index=20
SS.injectTouch(game,'touchpressed','wheel',160,104)
check(dex.wheelPointer=='wheel','physical wheel captures one pointer')
check(not dex:touchmoved('second',180,40),'second finger cannot rotate owned wheel')
SS.injectTouch(game,'touchmoved','wheel',180,40)
check(dex.index<20 and (dex.wheelRotation or 0)~=0,'wheel drag scrolls and rotates native wheel')
local index=dex.index
SS.injectTouch(game,'touchreleased','wheel',180,40)
check(not dex.wheelPointer and not dex:touchmoved('wheel',180,60) and dex.index==index,'release ends wheel drag')
SS.injectTouch(game,'touchpressed','wheel',160,104);check(dex:touchreleased('wheel',-100,-100) and not dex.wheelPointer,'outside release clears ownership')
SS.injectTouch(game,'touchpressed','check',48,152);check(dex.page=='entry','native CHECK opens selected seen entry')
dex:backToList();SS.injectTouch(game,'touchpressed','search',48,40);check(dex.page=='search','native SEARCH opens criteria')
SS.injectTouch(game,'touchpressed','criteria',128,48);check(dex.searchSelection[1]==2,'physical native A-to-Z button sets order')
SS.injectTouch(game,'touchreleased','criteria',128,48)
SS.injectTouch(game,'touchpressed','apply',200,176);check(dex.page=='list' and dex.filtered and #dex.entries==210,'physical SEARCH applies compact known results')
check(not dex:toggleDex(),'filtered results hide and reject regional toggle')
SS.injectTouch(game,'touchpressed','cancel',148,8);check(not dex.filtered and dex.page=='list','native CANCEL restores unfiltered list')
dex:openSearch();dex.searchSelection[3]=13;dex.searchSelection[4]=11
local before=dex.entries
check(not dex:applySearch() and dex.page=='search' and dex.searchError=='NONE FOUND' and dex.entries==before,'empty search retains previous list and reports none found')
game.save.options.secondScreenMode='off';dex:openSearch()
check(dex:touchpressed('mouse',10+200*2,20+77*2) and dex.searchField==2 and dex.searchSelection[2]==2,'single-screen native name row has matching touch bounds')
game.input={wasPressed=function(_,key) return key=='b' end};dex:update();check(dex.page=='list','controller cancels criteria')

game.save.options.secondScreenMode='display';dex.index=1
SS.injectTouch(game,'touchpressed','edge',160,104);SS.injectTouch(game,'touchmoved','edge',180,40)
check(dex.index==1,'wheel clamps beginning instead of wrapping to last entry')
check(not dex:touchreleased('other') and dex.wheelPointer=='edge','unrelated release cannot clear wheel owner')
dex:touchreleased('edge')
local owner=game.save.pokedex.seen[orders.sinnoh[1]];local caught=game.save.pokedex.owned[orders.sinnoh[1]]
game.save.pokedex.seen[orders.sinnoh[1]]=nil;game.save.pokedex.owned[orders.sinnoh[1]]=nil
dex.index=10;SS.injectTouch(game,'touchpressed','first',124,64)
check(dex.index==2,'first-arrow skips leading unknown gap like native status array')
game.save.pokedex.seen[orders.sinnoh[1]]=owner
game.save.pokedex.owned[orders.sinnoh[1]]=caught
dex:openSearch();local saved=orders.GRASS;orders.GRASS=nil;dex.searchSelection[3]=13
check(not dex:applySearch() and dex.searchError=='REIMPORT ROM FOR SEARCH DATA','older cache missing membership reports reimport without crashing')
orders.GRASS=saved;dex:backToList();dex.filtered=true
check(dex:openSearch()==false and dex.page=='list','hidden Search button cannot open during results')
dex.filtered=nil;game.save.options.secondScreenMode='inset'
local ix,iy,is=SS.rect(game);dex.index=20
check(dex:touchpressed('mouse',10+(ix+160*is)*2,20+(iy+104*is)*2),'inset mouse begins native wheel capture')
dex:touchmoved('mouse',10+(ix+180*is)*2,20+(iy+40*is)*2)
check(dex.index<20,'scaled inset wheel drag uses logical coordinates')
dex:touchreleased('mouse')

for seq=0,6 do
 for frame=0,3 do check(images[('dex/search_buttons_%02d_%02d'):format(seq,frame)],'native search button frame '..seq..'/'..frame) end
end
for seq=0,13 do
 for frame=0,3 do check(images[('dex/search_button_forms_%02d_%02d'):format(seq,frame)],'native shape button frame '..seq..'/'..frame) end
end
check(images['dex/search_panel'].width==256 and images['dex/search_panel'].height==192,'native companion dimensions')
game.save.options.secondScreenMode='display';dex:openSearch()
local function tap(x,y,id)
 id=id or 'finger';SS.injectTouch(game,'touchpressed',id,x,y);SS.injectTouch(game,'touchreleased',id,x,y)
end
tap(224,80);check(dex.searchField==2,'native Name category position')
tap(48,16);check(dex.searchSelection[2]==2,'ABC native grid selects correct enum')
tap(48,144);check(dex.searchSelection[2]==10,'YZ native grid selects correct enum')
tap(128,144);check(dex.searchSelection[2]==1,'None name clears filter')
tap(224,112);check(dex.searchField==3,'native Type category position')
tap(48,16);tap(128,16);check(dex.searchSelection[3]==2 and dex.searchSelection[4]==3,'two type slots alternate NORMAL/FIGHTING')
local slot=dex.searchTypeSlot;tap(48,16);check(dex.searchTypeSlot==slot and dex.searchSelection[3]==2,'duplicate type tap is ignored')
tap(128,144);check(dex.searchSelection[3]==1 and dex.searchSelection[4]==3,'None clears first type before second')
tap(128,144);check(dex.searchSelection[4]==1 and dex.searchTypeSlot==3,'second None clears second type and resets slot')
tap(24,176);check(dex.searchTypePage==1,'native right arrow changes type page')
tap(48,16);check(dex.searchSelection[3]==11,'second type page first button is FIRE')
tap(128,112);check(dex.searchSelection[4]==18,'second type page last type is DARK')
tap(128,144);check(dex.searchSelection[3]==1,'second-page None is in right column')
tap(24,176);check(dex.searchTypePage==0,'native left arrow restores first type page')
tap(224,144);check(dex.searchField==5,'native Form category position')
for i,value in ipairs(Search.SHAPE_GRID) do
 tap(28+(i-1)%3*56,16+math.floor((i-1)/3)*32)
 check(dex.searchSelection[5]==value+1,'native body grid enum '..i)
end
SS.injectTouch(game,'touchpressed','owner',28,16)
local shape=dex.searchSelection[5]
SS.injectTouch(game,'touchpressed','other',84,16);check(dex.searchSelection[5]==shape,'second finger cannot change held search button')
check(not dex:touchreleased('other') and dex.searchPointer=='owner','other release cannot clear held search button')
check(dex:touchreleased('owner',-10,-10) and not dex.searchPressed,'outside release clears native pressed state')
tap(224,48);dex.searchCursor=7
game.input={wasPressed=function(_,key) return key=='right' end};dex:update()
check(dex.searchCursor==8,'controller right moves to adjacent alphabetical button')
game.input={wasPressed=function(_,key) return key=='a' end};dex:update()
check(dex.searchSelection[1]==2 and dex.page=='search','controller A selects criterion without applying search')
tap(212,16);check(dex.page=='list','native back arrow cancels criteria')
local textArc=require('src.import.NarcArchive').parse(rom:read('/msgdata/pl_msg.narc'))
local Text=require('src.import.Gen4Text');local labelBank=Text.bank(textArc:get(697))
dex.art.labels={};for i=0,labelBank.count-1 do dex.art.labels[i]=Text.render(Text.codes(labelBank,i)) end
dex:openSearch()
local nativeButtons=Search.buttons(dex)
check(nativeButtons[7].label=='Numerical' and nativeButtons[8].label=='A to Z','native order capitalization')
check(Search.label(dex,87,'fallback')=='List by the first letter\nin the name.','native multiline search description')
check(Search.label(dex,93,'fallback')=='No matching Pokémon were found.','native no-results message')
check(Search.label(dex,91,'NONE')=='NONE','blank/unmapped label safely falls back')
dex.searchField=3;nativeButtons=Search.buttons(dex)
check(nativeButtons[8].label=='Fight','native Fighting display name differs from enum')
dex.searchSelection[3]=2;dex.searchSelection[4]=3;dex.searchField=3;dex:changeSearch(1)
check(dex.searchSelection[3]==4 and dex.searchSelection[4]==3,'single-screen type cycling skips duplicate other type')
game.save.options.secondScreenMode='inset';dex:openSearch()
local px,py,ps=SS.rect(game)
check(dex:touchpressed('mouse',10+(px+224*ps)*2,20+(py+80*ps)*2) and dex.searchField==2,'scaled inset mouse selects native Name category')
dex:touchreleased('mouse')
check(dex:touchpressed('mouse',10+(px+48*ps)*2,20+(py+16*ps)*2) and dex.searchSelection[2]==2,'scaled inset mouse selects native ABC cell')
dex:touchreleased('mouse')
game.save.options.secondScreenMode='swap';game.secondScreenUp=true
check(dex:touchpressed('finger',10+224*2,20+144*2) and dex.searchField==5,'raised swap touch selects native Form category')
dex:touchreleased('finger');game.secondScreenUp=false
game.save.options.secondScreenMode='display';calls={};dex:draw()
local lowerSearch=false
for _,call in ipairs(calls) do if call.path=='dex/search_panel' and call.target==game.secondScreenCanvas then lowerSearch=true end end
check(lowerSearch,'search native companion renders on physical lower surface')
for i=0,6 do check(images[('dex/cry_control_%02d'):format(i)].originX~=nil,'native cry control origin '..i) end
check(images['dex/cry_panel'].width==256 and images['dex/cry_panel'].height==192,'native Cry panel dimensions')
check(images['dex/cry_wheel'].width==256 and #images['dex/cry_wheel'].rgba==256*192*4,'offset Cry wheel stays bounded')
dex.page='entry';dex.tab=3;dex.cryLoop=false;dex:stopCry()
local voices=0;local playing=true;local options
package.loaded['src.core.Sound']={playCry=function(_,_,opts)
 voices=voices+1;options=opts;playing=true
 return {stop=function() playing=false end,isPlaying=function() return playing end}
end}
game.input={wasPressed=function() return false end}
local function cryTap(x,y,id)
 id=id or 'cry';SS.injectTouch(game,'touchpressed',id,x,y);SS.injectTouch(game,'touchreleased',id,x,y)
end
cryTap(120,90);check(voices==0,'blank Cry panel tap no longer replays')
cryTap(180,131);check(voices==1 and dex.cryRunning and options.isolated,'native Play requests isolated cry')
cryTap(230,166);check(dex.cryLoop and voices==1,'Loop toggles without double playing')
playing=false
for i=1,9 do dex:update() end
check(voices==1,'native loop preserves ten-frame cooldown')
dex:update();check(voices==2 and playing,'native loop replays after cooldown')
cryTap(180,131);check(not dex.cryRunning and not playing,'Play stops an active loop')
for i=1,20 do dex:update() end
check(voices==2,'stopped loop does not restart itself')
cryTap(230,166);cryTap(180,131);check(not dex.cryLoop and voices==3,'non-loop Play restarts normally')
playing=false;dex:update();check(not dex.cryRunning,'completed one-shot releases active state')
SS.injectTouch(game,'touchpressed','first',230,166)
SS.injectTouch(game,'touchpressed','second',230,166);check(dex.cryLoop and dex.cryPointer=='first','held Loop cannot be toggled by another finger')
check(not dex:touchreleased('second') and dex:touchreleased('first',-20,-20),'Cry pointer ownership and outside release')
cryTap(180,131);dex:setTab(1);check(not dex.cryRunning and not playing,'leaving Cry page stops playback')
print(checks..' total native Dex artwork, search, cry playback and dual-screen checks passed')
