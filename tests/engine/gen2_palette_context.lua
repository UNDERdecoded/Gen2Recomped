-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
require('src.core.ModCompat').install()
local P=require('src.world.gen2.Palettes');local Data=require('src.core.Data')
local W=require('src.world.gen2.World');local TR=require('src.render.TileRenderer')
local Context=require('src.render.Gen2PaletteContext');local Assets=require('src.render.Assets')
local Map=require('src.world.Map');local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local saved={mode=P.mode,dark=P.darkWorld(),tod=P.gen2Tod(),palette=P.gen2MapPalette(),map=W.map,game=W.game,worldDark=W.dark,
 image=Assets.image,imageData=Assets.imageData,loveImage=love.image,newImage=love.graphics.newImage,date=os.date}
os.date=function(format,...)if format=='%H'then return '20'end;return saved.date(format,...)end
local slot,oldGame
for i=1,100 do local name,value=debug.getupvalue(W.setDark,i);if name=='Game'then slot=i;oldGame=value;break end end
assert(slot)
local function buffer(w,h,source)
 local b={w=w,h=h,pixels={}}
 function b:getDimensions()return self.w,self.h end
 function b:getWidth()return self.w end
 function b:getHeight()return self.h end
 function b:getPixel(x,y)
  local p=self.pixels[y*self.w+x]
  if p then return unpack(p)end
  local c=source and(1-x%4/3)or 0;return c,c,c,1
 end
 function b:setPixel(x,y,...)self.pixels[y*self.w+x]={...}end
 function b:setFilter()end
 function b:setWrap()end
 function b:release()end
 return b
end
love.image={newImageData=function(w,h)return buffer(w,h)end}
love.graphics.newImage=function(value)assert(type(value)=='table');return value end
Assets.image=function()return buffer(16,8,true)end
Assets.imageData=function()return buffer(16,8,true)end
local function palette(seed)
 local set={}
 for slot=1,8 do set[slot]={};for c=1,4 do set[slot][c]={seed+slot+c,slot*10+c,c*20}end end
 return set
end
local function fixture(version)
 local d=T.fixtures.fresh();local rows={}
 for i,row in ipairs({'MORN','DAY','NITE','DARK'})do rows[row]=palette(i*20)end
 local ts={id='QA_CONTEXT',image='qa-context-'..version,tilesPerRow=2,palMap={0,6},palColorsByTod=rows,
  animatedTiles={},blockCells=2,blocks={{0,1,0,1}},walkable={0},grassTiles={},waterTiles={}}
 d.tilesets={QA_CONTEXT=ts}
 d.maps={}
 for id,p in pairs({AUTO=0,ROOM=1,NIGHT=2,MORNING=3,CAVE=4,UNUSED=7})do
  d.maps[id]={id=id,label=id,width=1,height=1,blocks={0},tileset=ts.id,environment=1,mapPalette=p,group=1,number=1}
 end
 d.maps.CENTER={id='CENTER',label='CENTER',width=1,height=1,blocks={0},tileset=ts.id,environment=3,mapPalette=1,group=2,number=1}
 d.field.gen2MapPalettes={rules={{kind='map',group=2,number=1,set='CENTER'},{kind='landmark',landmark=99,set='OTHER'}},
  sets={CENTER={DAY=palette(120)},OTHER={ALL=palette(160)}}}
 d.field.gen2Roofs={tilesets={[ts.id]=true},byGroup={[1]=0},images={[0]='synthetic-roof'},slot=10,count=0,palIndex=6,
  colors={[1]={DAY={{201,2,3},{204,5,6}},NITE={{211,12,13},{214,15,16}},DARK={{221,22,23},{224,25,26}}}}}
 Data.publishGen2Palettes(d)
 return d,ts,rows
end
local function samePixels(renderer,colors,label)
 for tile,slot in ipairs({1,7})do
  for c=1,4 do
   local r,g,b=renderer.image:getPixel((tile-1)*8+c-1,0)
   T.same({r,g,b},{colors[slot][c][1]/255,colors[slot][c][2]/255,colors[slot][c][3]/255},label..' native baked tile '..tile..' shade '..c)
  end
 end
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version);P.setMode('gbc');P.setGen2Tod('NITE');P.setGen2MapPalette(1);P.setGen2FlashUsed(false);P.setDarkWorld(false)
 local d,ts,rows=fixture(version)
 T.eq(d.maps.AUTO.palette,'PALETTE_AUTO',version..' publishes native clock identity')
 T.eq(d.maps.ROOM.palette,'PALETTE_DAY',version..' publishes forced room identity')
 T.eq(rawget(d.maps.ROOM,'palette'),nil,version..' projection never serializes a copied palette field')
 d.maps.ROOM.mapPalette=3;T.eq(d.maps.ROOM.palette,'PALETTE_MORN',version..' byte edit updates public identity immediately')
 d.maps.ROOM.palette='PALETTE_DAY';T.eq(Context.id(d.maps.ROOM),1,version..' explicit authored identity remains authoritative')
 d.maps.ROOM.mapPalette=1
 local authored={mapPalette=1,palette='CUSTOM'};Context.publish(authored);T.eq(authored.palette,'CUSTOM','authored non-native name preserved')
 local meta={__index={other=7}};local custom=setmetatable({mapPalette=2},meta)
 T.eq(Context.publish(custom),false,'authored lookup metatable is not replaced');T.eq(getmetatable(custom),meta,'authored metatable identity retained')
 T.eq(P.daytimeFor(d.maps.ROOM,20,false),'DAY',version..' pinned room remains day')
 T.eq(P.daytimeFor(d.maps.CAVE,12,false),'DARK',version..' neighbouring cave is dark before entry')
 P.setDarkWorld(true)
 T.eq(P.daytimeFor(d.maps.AUTO,12,false),'DAY',version..' outdoor neighbour cannot inherit current cave darkness')
 T.eq(P.daytimeFor(d.maps.ROOM,20,false),'DAY',version..' pinned neighbour cannot inherit current cave darkness')
 T.eq(P.daytimeFor(d.maps.CAVE,12,true),'NITE',version..' explicit Flash lights queried cave')
 P.setDarkWorld(false)
 P.setGen2MapPalette(4,d.maps.CAVE)
 T.eq(P.gen2RowFor(d.maps.CAVE),'NITE',version..' current-map query retains actual native presentation overrides')
 T.eq(P.gen2RowFor(d.maps.ROOM),'DAY',version..' neighbour query still uses own header')
 T.eq(P.daytimeFor(d.maps.AUTO,nil,false),'NITE',version..' absent hour reads RTC outside a pinned current map')
 P.setGen2Tod('MORN');P.setGen2MapPalette(1,d.maps.ROOM)
 T.eq(P.gen2RowFor(d.maps.AUTO),'NITE',version..' pinned room cannot pass an unused morning override to outdoor neighbours')
 P.setGen2MapPalette(0,d.maps.AUTO)
 T.eq(P.gen2RowFor({mapPalette=0}),'MORN',version..' outdoor neighbours still share current AUTO presentation')
 P.setGen2Tod('NITE')
 P.setGen2MapPalette(1)
 for id,row in pairs({AUTO='NITE',ROOM='DAY',NIGHT='NITE',MORNING='MORN',CAVE='DARK',UNUSED='NITE',CENTER='DAY'})do
  local def=d.maps[id];local map=Map.new(def,ts)
  local colors,chosen=P.bgSet(d.gen2Palettes,def,P.gen2RowFor(def))
  T.eq(chosen,row,version..' native header row '..id)
  local renderer=TR.new(map,d)
  T.eq(renderer.trueColor,true,version..' native constructor bakes actual colours '..id)
  samePixels(renderer,colors,version..' '..id)
  if id=='CENTER'then T.eq(colors[1][1][1],d.field.gen2MapPalettes.sets.CENTER.DAY[1][1][1],version..' Center special rule reaches public query')end
 end
 local before=rows.NITE[7][2]
 local set=P.bgSet(d.gen2Palettes,d.maps.AUTO,'NITE')
 T.same(set[7][2],{211,12,13},version..' native roof writes only imported middle pair')
 T.eq(rows.NITE[7][2],before,version..' public roof query does not modify shared tileset')
 T.eq(set[7][1],rows.NITE[7][1],version..' roof preserves endpoint zero')
 T.eq(set[7][4],rows.NITE[7][4],version..' roof preserves endpoint three')
 d.field.gen2Roofs.colors[1].NITE[1]={231,32,33}
 T.same(P.bgSet(d.gen2Palettes,d.maps.AUTO,'NITE')[7][2],{231,32,33},version..' metadata view sees live roof replacements')
 TR.invalidate()
 samePixels(TR.new(Map.new(d.maps.AUTO,ts),d),P.bgSet(d,d.maps.AUTO,'NITE'),version..' native invalidation observes changed roof')
 d.field.gen2MapPalettes.rules[1].set='MISSING';d.maps.CENTER.landmark=99
 T.eq(P.bgSet(d,d.maps.CENTER,'DAY')[1],rows.DAY[1],version..' unavailable first rule does not fall through to later match')
 d.field.gen2MapPalettes.rules[1].set='CENTER'
 local game={data=d,save={flags={}}};debug.setupvalue(W.setDark,slot,game)
 W.map=Map.new(d.maps.CAVE,ts)
 P.setGen2MapPalette(4,d.maps.CAVE)
 -- Keep the actual presentation setter while controlling only reload IO.
 local reload=W.reloadMap;W.reloadMap=function()end
 W:setDark(true)
 T.eq(W.daytime,'DARK',version..' public world reflects actual native darkness')
 T.eq(W.flashUsed,false,version..' public Flash view reads canonical save state')
 require('src.script.Gen2Commands')
 require('src.script.Commands').g2_blinding_flash({game=game,save=game.save,overworld=W})
 T.eq(game.save.flashLit,true,version..' original native Flash writer sets actual save bit')
 T.eq(W.flashUsed,true,version..' public Flash view follows native script write')
 T.eq(P.gen2RowFor(d.maps.CAVE),'NITE',version..' native neighbour context follows script Flash write')
 T.eq(W.daytime,'NITE',version..' world view follows actual lit-cave palette bake')
 W.reloadMap=reload
 local oldView=d.gen2Palettes;Data.publishGen2Palettes(d)
 T.eq(P.bgSet(oldView,d.maps.ROOM,'DAY'),nil,version..' retired published view cannot mix old/new metadata')
 local files={['mods/context/manifest.json']=Json.encode({id='context',name='Synthetic context',version='1.0.0',api=2,entry='main.lua',affects_link=false}),
  ['mods/context/main.lua']=[[
   local mod=...;local Palettes=require('src.world.gen2.Palettes')
   mod.exports.query=function(world,map)
    local row=Palettes.daytimeFor(map.def,20,world.flashUsed)
    local current=world.map
    local same=current.id==map.id
    local clock=current.def.palette=='PALETTE_AUTO'and map.def.palette=='PALETTE_AUTO'
    if(same or clock)and Palettes.DAYTIME_ID[world.daytime]then row=world.daytime end
    return Palettes.bgSet(world.game.data.gen2Palettes,map.def,row),row
   end
  ]]}
 local r=T.sdk.loadMods({'mods/context'},{data=d,fs=T.sdk.memfs(files)})
 T.eq(#r.errors,0,version..' real Loader imports public atlas context')
 W.game=game;W.map=Map.new(d.maps.AUTO,ts);P.setGen2MapPalette(0);P.setGen2Tod('NITE');W:setDark(false)
 local query=r.loader.exports.context.query
 local colors,row=query(W,Map.new(d.maps.ROOM,ts))
 T.eq(row,'DAY',version..' actual loaded public consumer keeps neighbouring room pinned')
 T.same(colors,P.bgSet(d,d.maps.ROOM,'DAY'),version..' loaded consumer uses same native roof selection')
 colors,row=query(W,W.map);T.eq(row,W.daytime,version..' loaded consumer uses actual current bake')
 W:syncGen2Tod('NITE')
 T.eq(P.gen2RowFor(d.maps.CAVE),'NITE',version..' native clock sync rebinds canonical Flash after mod reload')
 Loader.teardown();r.release()
 T.eq(P.gen2RowFor(d.maps.CAVE),'DARK',version..' teardown retires Flash presentation state')
end
Assets.image,Assets.imageData=saved.image,saved.imageData;love.image=saved.loveImage;love.graphics.newImage=saved.newImage
os.date=saved.date
W.map=saved.map;W.game=saved.game;W.dark=saved.worldDark;debug.setupvalue(W.setDark,slot,oldGame)
P.setMode(saved.mode);P.setGen2MapPalette(saved.palette);P.setGen2Tod(saved.tod);P.setDarkWorld(saved.dark);P.setGen2FlashUsed(false);V.set(original)
T.finish('native Gen2 map context, roof/special rows, world views and actual CPU atlas bake')
