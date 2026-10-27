-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
require('src.core.ModCompat').install()
local V=require('src.core.GameVersion')
local P=require('src.render.PaletteFX');local G=require('src.render.GbcPalette')
local TR=require('src.render.TileRenderer');local SR=require('src.render.SpriteRenderer')
local ML=require('src.world.MapLoader');local Assets=require('src.render.Assets')
local Data=require('src.core.Data');local Game=require('src.core.Game')
local Battle=require('src.battle.BattleState')
local assetChanges=0
Assets.register(function()assetChanges=assetChanges+1 end)
local A={{255,255,255},{201,53,71},{43,157,89},{0,0,0}}
local B={{245,239,227},{31,97,193},{167,59,131},{7,13,19}}
local R={{231,219,207},{181,151,111},{101,67,37},{23,17,11}}
local GRAY={{255,255,255},{170,170,170},{85,85,85},{0,0,0}}
local function buffer(w,h,source)
 local b={w=w,h=h,pixels={}}
 function b:getDimensions()return self.w,self.h end
 function b:getWidth()return self.w end;function b:getHeight()return self.h end
 function b:getPixel(x,y)
  local p=self.pixels[y*self.w+x];if p then return unpack(p)end
  local n=source and 1-x%4/3 or 0;return n,n,n,source and 1 or 0
 end
 function b:setPixel(x,y,...)self.pixels[y*self.w+x]={...}end
 function b:mapPixel(f)for y=0,self.h-1 do for x=0,self.w-1 do self:setPixel(x,y,f(x,y,self:getPixel(x,y)))end end end
 function b:setFilter()end;function b:setWrap()end;function b:release()end
 return b
end
love.image={newImageData=function(w,h)return buffer(w,h)end}
love.graphics.newImage=function(b)return b end
local function source(path)
 if path=='display-tiles' then return buffer(16,8,true)end
 if path=='display-roof' then return buffer(8,8,true)end
 return buffer(16,96,true)
end
Assets.image=source;Assets.imageData=source
local function pixels(image,colors,start,keyed,label)
 for i=1,4 do
  local r,g,b,a=image:getPixel((start or 0)+i-1,0)
  if keyed and i==1 then T.eq(a,0,label..' OBJ shade zero remains transparent')
  else T.same({r,g,b,a},{colors[i][1]/255,colors[i][2]/255,colors[i][3]/255,1},label..' shade '..i)end
 end
end
local function fixture()
 local d=T.fixtures.fresh()
 local ts={id='DISPLAY',image='display-tiles',tilesPerRow=2,palMap={0,1},palColorsByTod={DAY={A,B},NITE={B,A},DARK={A,B}},
  animatedTiles={{tile=0,kind='hshift',offsets={0,1},period=20}},blockCells=2,blocks={{0,1,0,1}},walkable={0},grassTiles={},waterTiles={}}
 d.tilesets={DISPLAY=ts}
 d.maps={DISPLAY={id='DISPLAY',label='DISPLAY',width=1,height=1,blocks={0},tileset='DISPLAY',environment=1,mapPalette=1,group=1,number=1}}
 d.pokemon={TEST={id='TEST',name='TEST',index=1,dex=1,palette='QA_TEST',spriteFront='display-mon'}}
 d.palettes={palettes={QA_TEST=A,MEWMON=A,GRAYMON=GRAY,BLACK={{0,0,0},{0,0,0},{0,0,0},{0,0,0}}},pokemon={TEST='QA_TEST'}}
 d.field.gen2Roofs={tilesets={DISPLAY=true},byGroup={[1]=0},images={[0]='display-roof'},slot=1,count=1,palIndex=1,
  colors={[1]={DAY={{53,63,73},{83,93,103}}}}}
 Data.publishGen2Palettes(d)
 return d,ts
end
for _,edition in ipairs({'gold','silver','crystal'})do
 V.set(edition);P.setDisplay('gbc',nil);P.setShadeMap(nil);P.setDarkWorld(false);P.setGen2MapPalette(1);P.setGen2Tod('DAY')
 local d,ts=fixture();ML.invalidateAll()
 local mon={species='TEST',dvs={attack=1,defense=1,speed=1,special=1}}
 local battle=setmetatable({data=d,game={save={party={}}}},Battle)
 local factory
 for i=1,100 do local name,value=debug.getupvalue(Battle.speciesSprite,i);if name=='getImage'then factory=value;break end end
 assert(factory,'native battle image factory unavailable')
 local originalPic=factory('display-mon',{name='QA_TEST',colors=A},false)
 local sprite=SR.new({id='DISPLAY',image='display-sprite',gen2ObjPal=A})
 local reloads=0
 Game.overworld={map=ML.load(d,'DISPLAY'),reloadMap=function(self,id,reason)
  T.eq(reason,'colors',edition..' native map reload identifies display change')
  self.map=ML.load(d,id);self.tiles=TR.new(self.map,d);reloads=reloads+1
 end}
 for _,choice in ipairs({{'gbc',A},{'dmg',GRAY},{'classic',GRAY},{'custom',R}})do
  local name,wanted=choice[1],choice[2]
  local oldMap=Game.overworld.map
  if name=='custom' then P.setDisplay(name,R)else P.setDisplay(name,nil)end
  T.eq(G.mode,name,edition..' native/public mode agrees '..name)
  T.eq(G.customRamp,name=='custom'and R or nil,edition..' public ramp is actual native ramp')
  if name~='gbc' then T.neq(Game.overworld.map,oldMap,edition..' current map cache replaced '..name)end
  local tiles=TR.new(ML.load(d,'DISPLAY'),d)
  pixels(tiles.image,wanted,0,false,edition..' actual atlas '..name)
  local roof=name=='gbc'and{B[1],{53,63,73},{83,93,103},B[4]}or wanted
  pixels(tiles.image,roof,8,false,edition..' actual roof '..name)
  T.check(tiles.anims and tiles.anims[1],edition..' native water animation exists')
  pixels(tiles.anims[1].textures[1],wanted,0,false,edition..' actual animated tile '..name)
  pixels(sprite:resolveImage(),wanted,0,true,edition..' retained native sprite '..name)
  pixels(battle:picImage(originalPic),wanted,0,false,edition..' retained native battle picture '..name)
  battle.fx={bgp={[0]=3,2,1,0}}
  pixels(battle:picImage(originalPic),{wanted[4],wanted[3],wanted[2],wanted[1]},0,false,edition..' battle fade after display '..name)
  battle.fx=nil;battle.blackedOut=true
  pixels(battle:picImage(originalPic),{wanted[4],wanted[4],wanted[4],wanted[4]},0,false,edition..' battle blackout '..name)
  battle.blackedOut=false
  if name=='classic' then T.eq(G.presentColors(),P.CLASSIC,edition..' Classic has one final green ramp')
  else T.eq(G.presentColors(),nil,edition..' mode has no extra green pass '..name)end
 end
 local count=reloads;local assetCount=assetChanges;G.setCustomRamp(R);T.eq(reloads,count,edition..' identical ramp avoids reload')
 T.eq(assetChanges,assetCount,edition..' identical ramp avoids shared asset churn')
 local oldKey=P.displayKey();R[2][1]=R[2][1]+1;G.setCustomRamp(R)
 T.neq(P.displayKey(),oldKey,edition..' edited ramp changes native cache key')
 T.eq(reloads,count+1,edition..' reapplying edited ramp refreshes current map once')
 T.eq(assetChanges,assetCount+1,edition..' edited ramp notifies registered external caches once')
 pixels(sprite:resolveImage(),R,0,true,edition..' sprite rebakes edited ramp')
 G.setBgp(0xff)
 pixels(TR.new(ML.load(d,'DISPLAY'),d).image,R,0,false,edition..' transient BGP never baked into atlas')
 G.setBgp(nil);P.setDarkWorld(true)
 pixels(sprite:resolveImage(),{R[3],R[4],R[4],R[4]},0,true,edition..' custom world darkness preserved')
 P.setDarkWorld(false)
 T.eq(G.cycle(), 'dmg',edition..' custom cycle returns to native ladder')
 T.eq(G.customRamp,nil,edition..' cycling removes custom ramp')
 T.eq(G.cycle(),'classic',edition..' DMG advances to Classic')
 T.eq(G.cycle(),'gbc',edition..' Classic advances to GBC')
 T.eq(G.cycle(-1),'classic',edition..' backward cycle supported')
 count=reloads;assetCount=assetChanges;G.applyOptions({color='custom',palette='m:80a0c0'})
 T.eq(reloads,count+1,edition..' saved mode and palette applied atomically')
 T.eq(assetChanges,assetCount+1,edition..' saved mode and palette flush shared assets once')
 T.same(G.customRamp,{{128,160,192},{92,115,138},{49,61,73},{15,19,23}},edition..' saved RGB palette reaches native owner')
 local opts={color='custom',colors='custom',palette='m:80a0c0'}
 P.writeColorOption(opts,P.cycleMode());T.eq(opts.palette,nil,edition..' manual cycle clears saved palette')
 T.eq(opts.color,'dmg',edition..' legacy option tracks actual new mode');T.eq(opts.colors,'og',edition..' native option tracks same mode')
 G.applyOptions(opts);T.eq(G.mode,'dmg',edition..' reapply cannot revive stale custom selection')
 local menuGame={data=d,save={options=opts}}
 local menu=require('src.ui.OptionsMenu').new(menuGame)
 local row;for _,candidate in ipairs(menu.rows)do if candidate.id=='colors'then row=candidate end end
 T.check(row,edition..' actual native options has display row')
 T.eq(row.value(menuGame),'DMG',edition..' options reports actual native selection')
 row.step(menuGame,1)
 T.eq(opts.color,'classic',edition..' options persists legacy Classic selection')
 T.eq(opts.colors,'classic',edition..' options persists same native selection')
 T.eq(G.mode,'classic',edition..' actual options changes native renderer mode')
 T.eq(row.value(menuGame),'CLASSIC',edition..' options reports switched mode')
 row.step(menuGame,-1);G.applyOptions(opts)
 T.eq(G.mode,'dmg',edition..' backwards options choice survives apply')
 Game.overworld=nil
end
V.set('emerald');P.setDisplay('classic',R);T.eq(P.displayColors(A),A,'Gen3 palette behavior preserved');T.eq(P.presentColors(),nil,'Gen3 receives no Classic pass')
V.set('red');P.setDisplay('classic',nil);T.eq(P.displayColors(A),P.CLASSIC,'Gen1 Classic remains its original palette path')
T.finish('native Gen2 modes, cached atlas/roof/animation/OBJ/battle bakes and saved options')
