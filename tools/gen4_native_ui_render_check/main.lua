function love.load(args)
 package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
 local ok,why=pcall(function()
  local dataset,output=assert(args[1]),assert(args[2])
  local function load(name) return assert(loadfile(dataset..'/data/generated/'..name..'.lua'))() end
  local images={};package.loaded['src.render.Assets']={register=function() end,resolve=function(p) return p end,image=function(path)
   if images[path] then return images[path] end
   local f=assert(io.open(dataset..'/'..path,'rb'));local bytes=f:read('*a');f:close()
   images[path]=love.graphics.newImage(love.filesystem.newFileData(bytes,path));return images[path]
  end}
  package.loaded['src.core.Strings']=function(s) return s end
  package.loaded['src.core.Logger']={warn=function() end,info=function() end}
  package.loaded['src.core.Sound']={play=function() end,playCry=function() end}
  package.loaded['src.core.GameVersion']={isGen4=function() return true end,isGen3=function() return false end,isGen2=function() return false end}
  require('src.render.Font').load({font=load('font')})
  local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
  local resources=require('src.import.Gen4UIResources').images(rom)
  local data={moves=load('moves'),pokemon=load('pokemon'),items=load('items'),constants=load('constants'),gen4_graphics=load('gen4_graphics'),gen4_dex=load('gen4_dex'),gen4_menus=load('gen4_menus'),icons=load('gen4_species_sprites').icons}
  data.text=load('text')
  data.gen4_species_sprites=load('gen4_species_sprites')
  data.gen4_models={sets={opening={models={}}}}
  local G=require('src.import.Gen4Graphics')
  local B=require('src.import.Gen4Nsbmd')
  local T=require('src.import.Gen4Models')
  local arc=assert(require('src.import.NarcArchive').parse(rom:read('/demo/title/op_demo.narc')))
  local function member(i) local b=arc:get(i);return G.isCompressed(b) and G.decompress(b) or b end
  local textureCount=0
  for _,i in ipairs({100,101,103,104,105,106,107,108,110,111}) do
   local bytes=member(i)
   local textureBytes=member(i<103 and 102 or i<110 and 109 or 112)
   local bank=assert(T.parse(textureBytes))
   for _,model in ipairs(assert(B.parse(bytes)).models) do
    local packed=require('src.import.Gen4ModelPack').pack(model)
    for _,shape in ipairs(packed.shapes) do
     if shape.texture then
      local ti,pi
      for n,t in ipairs(bank.textures) do if t.name==shape.texture then ti=n end end
      for n,p in ipairs(bank.palettes) do if p.name==shape.palette then pi=n end end
      assert(ti,'unbound opening texture '..shape.texture)
      local pic=assert(T.decode(bank,textureBytes,ti,pi or 1))
      local key='opening-model/'..model.name..'/'..shape.texture
      images[key]=love.graphics.newImage(love.image.newImageData(pic.width,pic.height,'rgba8',pic.rgba))
      shape.image=key;textureCount=textureCount+1
     end
    end
    table.insert(data.gen4_models.sets.opening.models,packed)
   end
  end
  assert(textureCount>100,'opening textures not bound')
  local count=0
  local P=require('src.import.Gen4Particle')
  local particleArc=assert(require('src.import.NarcArchive').parse(rom:read(P.ARCHIVE_FIELD)))
  local particleBytes=particleArc:get(4)
  local particles={textures={},emitters=assert(P.emitters(particleBytes))}
  assert(#particles.emitters>=12,'opening particle resources missing')
  for index,texture in ipairs(assert(P.textures(particleBytes))) do
   local pic=assert(P.rgba(texture));local key='opening-particle/'..index
   images[key]=love.graphics.newImage(love.image.newImageData(pic.width,pic.height,'rgba8',pic.rgba))
   particles.textures[index]={path=key,width=pic.width,height=pic.height}
  end
  data.gen4_particles={effects={opening_4=particles}}
  for key,pic in pairs(resources) do
   images[key]=love.graphics.newImage(love.image.newImageData(pic.width,pic.height,'rgba8',pic.rgba));data.gen4_graphics.screens[key]={path=key,originX=pic.originX,originY=pic.originY,sequences=pic.sequences};count=count+1
  end
  assert(count>=546,'missing native supplementary UI resources: '..count)
  for id=0,79 do assert(resources[('summary/ribbon_%02d'):format(id)],'missing ribbon '..id) end
  assert(resources['summary/ribbon_33'].rgba~=resources['summary/ribbon_37'].rgba,
    'contest ribbons with different palette indices must not share their colors')
  assert(resources['summary/sheen_00'],'missing native sheen sprite')
  for id=1,6 do assert(resources[('summary/status_%02d'):format(id)],'missing status badge '..id) end
  for _,key in ipairs({'summary/special_00','summary/special_01','summary/pokerus_active'}) do assert(resources[key],key) end
  for id=1,16 do
    local pic=assert(resources[('summary/ball_%02d'):format(id)],'missing caught ball '..id)
    local visible=false
    for at=4,#pic.rgba,4 do if pic.rgba:byte(at)>0 then visible=true;break end end
    assert(visible,'transparent caught ball '..id)
  end
  for sequence=0,15 do
    local pic=assert(resources[('summary/tab_%02d'):format(sequence)],'missing summary tab '..sequence)
    local visible=false
    for at=4,#pic.rgba,4 do if pic.rgba:byte(at)>0 then visible=true;break end end
    assert(visible,'transparent summary tab '..sequence)
  end
  for _,key in ipairs({'shop/cursor_00','shop/scroll_00','shop/scroll_01'}) do assert(resources[key],key) end
  local function capture(name,fn)
   local c=love.graphics.newCanvas(256,192);love.graphics.setCanvas(c);love.graphics.clear();love.graphics.origin();fn();love.graphics.setCanvas()
   local f=assert(io.open(output..'/'..name..'.png','wb'));f:write(c:newImageData():encode('png'):getString());f:close()
  end
  capture('summary-tab-art',function()
    love.graphics.setColor(1,1,1,1)
    for i=0,15 do love.graphics.draw(images[('summary/tab_%02d'):format(i)],i%8*32,math.floor(i/8)*32) end
  end)
  for _,key in ipairs({'storage/main','storage/wallpaper_00','evolution/background','dex/footprint_387','opening/first_top','opening/first_bottom','opening/first_overlay'}) do
   capture(key:gsub('/','-'),function() love.graphics.setColor(1,1,1,1);love.graphics.draw(images[key],0,0) end)
  end
  for key in pairs(resources) do
   if key:find('^opening/') then
    capture(key:gsub('/','-'),function() love.graphics.setColor(1,1,1,1);love.graphics.draw(images[key],0,0) end)
   end
  end
  local game={data=data,save={party={{species=387,level=5,hp=20,moves={{id=33,pp=35},{id=110,pp=40}},stats={hp=20,attack=13,defense=12,spAttack=10,spDefense=12,speed=8}}},inventory={},money=3000,pokedex={seen={[387]=true},owned={[387]=true}}},stack={pop=function() end},input={wasPressed=function() return false end}}
  local intro=require('src.ui.Gen4Intro').new(game)
  for _,frame in ipairs({640,710,740,800,900,945,975,1100,1189,1193,1250,1450,1650,1950,2025,2035,2100,2140,2150,2252,2300,2342,2424}) do
   intro.openingFrame=frame
   capture('montage-top-'..frame,function() require('src.ui.Gen4Opening').draw(intro,false) end)
   if frame==740 then
    assert(#intro.movieParticles.systems==3)
    local alive=0;for _,system in ipairs(intro.movieParticles.systems) do alive=alive+system:total() end
    assert(alive>0,'logo particles must be alive')
   end
   local before=intro.movieParticles.frame
   capture('montage-bottom-'..frame,function() require('src.ui.Gen4Opening').draw(intro,true) end)
   capture('montage-pair-'..frame,function() require('src.ui.Gen4Opening').drawPair(intro) end)
   assert(intro.movieParticles.frame==before,'dual/single rendering must not advance simulation twice')
  end
  local pc=require('src.ui.Gen4BoxMenu').new(game,{mode='move'})
  game.save.boxes[1][1]={species=390,level=8};game.save.boxes[1][30]={species=393,level=8}
  capture('storage-screen',function() pc:draw() end)
  local shop=require('src.ui.Gen4ShopMenu').new(game,{4,17})
  shop:choose();assert(shop:description()==data.items[4].description);capture('shop-screen',function() shop:draw() end)
  shop.stock={4,17,18,19,20,21,22,23};shop:step(6)
  assert(shop.cursor==7 and shop.scroll==0);capture('shop-seventh-row',function() shop:draw() end)
  shop:step(1);assert(shop.scroll==1);capture('shop-scrolled',function() shop:draw() end)
  shop.cursor=1;shop.scroll=0;shop:choose();capture('shop-quantity',function() shop:draw() end)
  local dex=require('src.ui.Gen4Pokedex').new(game);dex.page='entry'
  for i,id in ipairs(dex.entries) do if id==387 then dex.index=i end end
  for i=1,5 do dex.tab=i;capture('dex-page-'..i,function() dex:draw() end) end
  dex.tab=4;dex.sizeWeight=true;capture('dex-weight',function() dex:draw() end)
  capture('dex-lower-sinnoh',function() dex:drawBottom() end)
  dex.tab=3
  capture('dex-cry-lower',function() dex:drawBottom() end)
  dex.cryLoop=true;dex.cryRunning=true
  capture('dex-cry-lower-loop-playing',function() dex:drawBottom() end)
  dex.cryLoop=false;dex.cryRunning=false;dex.tab=1
  game.save.pokedex.national=true
  local nationalDex=require('src.ui.Gen4Pokedex').new(game);nationalDex.page='entry'
  for i,id in ipairs(nationalDex.entries) do if id==387 then nationalDex.index=i end end
  capture('dex-national-info',function() nationalDex:drawDetails() end)
  capture('dex-lower-national',function() nationalDex:drawBottom() end)
  game.save.pokedex.national=nil
  local listDex=require('src.ui.Gen4Pokedex').new(game)
  listDex.art.orders=require('src.import.Gen4Dex').orders(rom)
  local textArc=require('src.import.NarcArchive').parse(rom:read('/msgdata/pl_msg.narc'))
  local Text=require('src.import.Gen4Text');local labelBank=Text.bank(textArc:get(697))
  listDex.art.labels={}
  for i=0,labelBank.count-1 do listDex.art.labels[i]=Text.render(Text.codes(labelBank,i)) end
  capture('dex-list-lower',function() listDex:drawListBottom() end)
  listDex.wheelRotation=math.rad(45)
  capture('dex-list-wheel-rotated',function() listDex:drawListBottom() end)
  listDex.national=true
  capture('dex-list-lower-national',function() listDex:drawListBottom() end)
  listDex:openSearch()
  capture('dex-search-top',function() listDex:drawSearch(false) end)
  capture('dex-search-lower',function() listDex:drawSearch(true) end)
  listDex.searchField=2
  capture('dex-search-name-lower',function() listDex:drawSearch(true) end)
  listDex.searchField=3;listDex.searchSelection[3]=2;listDex.searchSelection[4]=3
  capture('dex-search-type-lower',function() listDex:drawSearch(true) end)
  listDex.searchTypePage=1
  capture('dex-search-type-second-lower',function() listDex:drawSearch(true) end)
  listDex.searchSelection[5]=2;listDex.searchField=5
  capture('dex-search-body',function() listDex:drawSearch(false) end)
  capture('dex-search-body-lower',function() listDex:drawSearch(true) end)
  local summary=require('src.ui.Gen4SummaryMenu').new(game,game.save.party[1])
  summary.mon.personality=3
  summary.mon.ivs={hp=31,attack=31,defense=31,speed=31,spAttack=31,spDefense=31}
  summary.mon.metLevel=5;summary.mon.metLocation='Route 201'
  summary.mon.metDate={year=2026,month=10,day=1}
  summary.mon.contest={cool=255,beauty=192,cute=64,smart=0,tough=128,sheen=255}
  summary.mon.status='PSN'
  summary.mon.ball='POKE_BALL'
  summary.mon.shiny=true;summary.mon.pokerus=16
  summary.mon.ribbons={[32]=true,[37]=true,[53]=true,[59]=true,[65]=true,[69]=true,[79]=true}
  for i=1,#summary.pages do summary.page=i;capture('summary-page-'..i,function() summary:draw() end) end
  for i,page in ipairs(summary.pages) do if page.key=='memo' then summary.page=i end end
  game.save.player={id=123,name='Cedric'};summary.mon.otId=456;summary.mon.fatefulEncounter=true
  capture('summary-traded-fateful-memo',function() summary:draw() end)
  summary.mon.hatched=true;summary.mon.eggLocation='Day-Care Couple';summary.mon.eggDate={year=26,month=9,day=30}
  summary.mon.metLocation='Route 209';summary.mon.metLevel=0
  capture('summary-hatched-fateful-memo',function() summary:draw() end)
  summary.mon.hatched=nil;summary.mon.fatefulEncounter=nil;summary.mon.metLevel=5
  for i,page in ipairs(summary.pages) do if page.key=='ribbons' then summary.page=i end end
  summary.ribbonMode=true;summary.ribbonIndex=2
  capture('summary-ribbon-detail',function() summary:draw() end)
  summary.ribbonMode=nil
  for i,page in ipairs(summary.pages) do if page.key=='moves' then summary.page=i end end
  summary.moveMode=true;summary.moveIndex=1
  capture('summary-move-detail',function() summary:draw() end)
  summary.moveIndex=2;capture('summary-status-move-detail',function() summary:draw() end)
  local eggSummary=require('src.ui.Gen4SummaryMenu').new(game,{species=387,isEgg=true,eggCycles=5,
    eggLocation='Solaceon Town',eggDate={year=2026,month=10,day=1}})
  capture('summary-egg-memo',function() eggSummary:draw() end)
  assert(eggSummary:pictureArt(),'ordinary egg picture missing')
  eggSummary.mon.species=490
  assert(eggSummary:pictureArt(),'Manaphy egg picture missing')
  capture('summary-manaphy-egg-memo',function() eggSummary:draw() end)
  local evolution=require('src.ui.Gen4EvolutionState').new(game,game.save.party[1],388)
  capture('evolution-opening',function() evolution:draw() end)
  evolution.phase='morph';evolution.t=75
  capture('evolution-morph',function() evolution:draw() end)
  rom:close()
  print(count..' ROM UI resources, shop icon/quantity/scroll layouts, summary pages/details and two evolution frames rendered')
 end)
 love.graphics.setCanvas();if not ok then print(why) end
 love.event.quit(ok and 0 or 1)
end
