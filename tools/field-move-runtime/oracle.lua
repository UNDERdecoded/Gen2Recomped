-- The immutable original is supplied by a private QA wrapper, never bundled.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
love=require('tests.love_stub')
require('tools.sprite-runtime.cpu-gpu').install(love)
local Native=require('src.world.Gen3FieldMove')
local Source=require('src.core.game3.field_move_show_mon')
local raw=assert(arg[1]);local checks=0
local function original(outdoors)
 local p={startFieldMove=function()end}
 local audio={}
 local mocks={['src.core.game3.player']=p,['src.core.game3.pokemon']={picSpecies=function(n)return n end,isShiny=function(m)return m and m.shiny or false end},
  ['src.core.game3.audio']={playCry=function(...)audio[#audio+1]={...}end}}
 local loaded={['src.core.game3.map']={currentDef=function()return{mapType=outdoors and 3 or 8}end}}
 local env=setmetatable({package={loaded=loaded},require=function(name)return assert(mocks[name],name)end},{__index=_G})
 local fn=assert(loadfile(raw));setfenv(fn,env);return fn(),audio
end
local oldCry=require('src.core.Sound').playCry
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
 for _,outside in ipairs({true,false})do for _,pose in ipairs({true,false})do for _,noDuck in ipairs({true,false})do
  Source.release();local f=require('tools.session-runtime.fixture').new(edition);local g=f.game
  g.data.pokemon={TEST={spriteFront='unused.png',name='TEST'}};g.data.constants.speciesOrder={[1]='TEST'}
  f.map.def.mapType=outside and'ROUTE'or'INDOOR'
  local strip={width=256,height=80,indexed=string.rep('\1',256*80),palette={}}
  for i=1,16 do strip.palette[i]=i end
  g.data.constants.gen3FieldMovePresentation={schema=1,edition=edition,romSha1=require('src.core.GameVersion').info(edition).sha1,strips={outdoors=strip,indoors=strip}}
  -- Use the CPU image loader with real owned construction; this fixture's
  -- front image is arbitrary, the timing oracle never evaluates its pixels.
  local image=love.image.newImageData(64,64,'rgba8')
  local make=love.graphics.newImage
  love.graphics.newImage=function(v)if v=='unused.png'then return make(image)end;return make(v)end
  local base,calls=original(outside);local nativeCries=0;local doneA,doneB=0,0
  require('src.core.Sound').playCry=function()nativeCries=nativeCries+1 end
  base.start({species=1},{pose=pose,noDuck=noDuck},function()doneA=doneA+1 end)
  T.eq(Source.start(1,{pose=pose,noDuck=noDuck},function()doneB=doneB+1 end),true)
  for tick=0,220 do
   local a,b=base._fx,Source._fx
   T.eq(a~=nil,b~=nil,'active frame '..tick)
   if not a then break end
   for _,key in ipairs({'species','picSpecies','shiny','noDuck','outdoors','phase','posed','poseWait','hofs','winL','winT','winB','revealed','cleared','hidden'})do
    T.eq(b[key],a[key],edition..' '..key..' tick '..tick);checks=checks+1
   end
   T.eq(a.sprite~=nil,b.sprite~=nil)
   if a.sprite then for _,key in ipairs({'x','y','state','wait','done'})do T.eq(b.sprite[key],a.sprite[key],key..' tick '..tick);checks=checks+1 end end
   T.eq(nativeCries,#calls);T.eq(doneA,doneB)
   base.step();g.stack:update(1/60)
  end
  T.eq(doneA,1);T.eq(doneB,1)
  love.graphics.newImage=make;image:release();Source.release()
 end end end
end
require('src.core.Sound').playCry=oldCry
print('FIELD_MOVE_ORACLE_VALUES',checks)
T.finish('independent immutable field-move state oracle')
