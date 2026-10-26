package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local Sheets=require('src.import.Gen3ObjectSheets')
local Rom=require('src.import.RomGba')
T.eq(package.loaded['src.core.Game'],nil,'sheet decoder is independent of live sessions')
local function fixture(w,h,wide)
  local memory={}
  for i=1,8192 do memory[i]=0 end
  local function u8(at,v) memory[at+1]=v%256 end
  local function u16(at,v) u8(at,v);u8(at+1,math.floor(v/256)) end
  local function u32(at,v) u16(at,v);u16(at+2,math.floor(v/65536)) end
  local function ptr(at,v) u32(at,0x8000000+v) end
  ptr(0x100,0x300)
  ptr(0x200,0x280);u16(0x204,123)
  for i=0,15 do u16(0x280+i*2,i*1057) end
  u16(0x300,65535);u16(0x302,123);u16(0x304,65535)
  u16(0x308,w);u16(0x30a,h);u8(0x30c,2)
  ptr(0x318,0x500);ptr(0x31c,0x400)
  ptr(0x400,0x600);u16(0x404,w*h/2)
  for tile=0,w*h/64-1 do for i=0,31 do u8(0x600+tile*32+i,(tile+1)*17) end end
  local function rom()
    local s={};for i,v in ipairs(memory) do s[i]=string.char(v) end
    return Rom.new(table.concat(s))
  end
  return {rom=rom,u8=u8,u16=u16,u32=u32,ptr=ptr,spec={gfxTable=0x100,count=1,paletteTable=0x200,paletteCount=2,wideSubsprites=wide}}
end
local f=fixture(16,16)
local result=Sheets.extract(f.rom(),f.spec);local r=assert(result.objects[0])
T.eq(result.schema,Sheets.SCHEMA);T.eq(r.width,16);T.eq(r.height,16);T.eq(r.frameCount,1)
T.eq(r.paletteTag,123);T.eq(r.paletteSlot,2);T.eq(#r.indexed,256)
for y=0,15 do for x=0,15 do
  T.eq(r.indexed:byte(y*16+x+1),math.floor(y/8)*2+math.floor(x/8)+1,'tiled bytes become row-major indices')
end end
local rgba=Sheets.rgba(r);T.eq(#rgba,1024)
local encoded=require('src.import.LuaWriter').encodeSplit(result)
local decoded=assert((loadstring or load)(encoded))()
T.same(decoded,result,'compact bytes and zero-based palettes survive the actual cache writer')
T.eq(rgba:sub(1,4),string.char(8,8,8,255),'BGR555 uses exact 5-bit expansion')
T.eq(rgba:sub(8*4+1,8*4+4),string.char(16,16,16,255))
T.eq(rgba:sub(16*8*4+1,16*8*4+4),string.char(25,25,25,255))
local blank={width=8,height=8,frameCount=1,indexed=string.rep('\0',64),palette={[0]=32767}}
T.eq(Sheets.rgba(blank),string.rep('\0',256),'palette index zero is transparent even when colored')
local high={width=8,height=8,frameCount=1,indexed=string.rep('\1',64),palette={[1]=65535}}
T.eq(Sheets.rgba(high),string.rep(string.char(255,255,255,255),64),'BGR bit 15 does not affect color')
local avatar=fixture(16,16)
avatar.spec.avatarTables={player=0x1800,player_states=2,rival=0x1810,rival_states=1,
  stateNames={'NORMAL','SURFING'},link_frlg=0x1820,link_rs=0x1822,state_flags=0x1830,state_flag_count=1}
for i,v in ipairs({0,89,2,92})do avatar.u8(0x17ff+i,v)end
avatar.u8(0x1810,5);avatar.u8(0x1811,6)
avatar.u8(0x1820,10);avatar.u8(0x1821,11);avatar.u8(0x1822,12);avatar.u8(0x1823,13)
avatar.u8(0x1830,0);avatar.u8(0x1831,1);avatar.u8(0x1832,89);avatar.u8(0x1833,2)
local av=Sheets.extract(avatar.rom(),avatar.spec).avatars
T.same(av,{player={{state='NORMAL',male=0,female=89},{state='SURFING',male=2,female=92}},
  rival={{state='NORMAL',male=5,female=6}},linkFrlg={male=10,female=11},linkRs={male=12,female=13},
  stateFlags={male={{gfx=0,flag=1}},female={{gfx=89,flag=2}}}},'independent avatar roles and state flags')
avatar.spec.avatarTables.player=8192
T.raises(function()Sheets.extract(avatar.rom(),avatar.spec)end,'outside cartridge','out-of-range avatar metadata declines')
T.raises(function()Sheets.rgba({width=8,height=8,frameCount=1,indexed='x'})end,'invalid indexed','invalid sheet sizes decline')
-- Original picture-table order and noncontiguous frame pointers survive.
f.ptr(0x408,0x1400);f.u16(0x40c,128)
for i=0,127 do f.u8(0x1400+i,0xee) end
r=Sheets.extract(f.rom(),f.spec).objects[0]
T.eq(r.frameCount,2);T.eq(r.indexed:sub(257),string.rep('\14',256))
f.ptr(0x410,0x1600);f.u16(0x414,256)
for i=0,255 do f.u8(0x1600+i,0xff) end
r=Sheets.extract(f.rom(),f.spec).objects[0]
T.eq(r.frameCount,3,'mixed-height picture tables retain all stage slots')
T.eq(r.indexed:sub(513),string.rep('\0',256),'foreign-size stage does not consume adjacent art')
f.u32(0x410,0)
-- Another info record can name the immediately following image list.
f.spec.count=2;f.ptr(0x104,0x340)
f.u16(0x340,65535);f.u16(0x342,123);f.u16(0x348,16);f.u16(0x34a,16)
f.ptr(0x358,0x500);f.ptr(0x35c,0x408)
result=Sheets.extract(f.rom(),f.spec)
T.eq(result.objects[0].frameCount,1,'another image-table start is a hard frame boundary')
T.eq(result.objects[1].indexed,string.rep('\14',256))
f.u16(0x348,7);result=Sheets.extract(f.rom(),f.spec)
T.eq(result.objects[1],nil);T.check(result.unavailable[1]~=nil,'invalid info is reported, not replaced with unrelated art')
-- Both cartridge layouts produce the same two-piece OAM arrangement.
for _,wide in ipairs({false,true}) do
  local q=fixture(32,16,wide);q.ptr(0x314,0x1000);q.u8(0x1000,2);q.ptr(0x1004,0x1100)
  local stride=wide and 8 or 4
  for i=0,1 do
    local at=0x1100+i*stride
    if wide then q.u16(at,i*16-16);q.u16(at+2,-8);q.u16(at+4,4+i*64)
    else q.u8(at,i*16-16);q.u8(at+1,-8);q.u16(at+2,4+i*64) end
  end
  local s=Sheets.extract(q.rom(),q.spec).objects[0]
  T.eq(s.drawOffX,0);T.eq(s.drawOffY,0)
  for y=0,15 do for x=0,31 do
    local tile=math.floor(x/16)*4+math.floor(y/8)*2+math.floor((x%16)/8)
    T.eq(s.indexed:byte(y*32+x+1),tile+1,'subsprite tile allocation is distinct from logical row order')
  end end
end
-- Cache readiness asks for the additive data only on GBA datasets.
love=require('tests.love_stub')
local Importer=require('src.import.RomImporter')
local Cache=require('src.import.CacheFs')
local read,exists,rootReport=Cache.read,Cache.exists,Cache.rootReport
Cache.rootReport=function()return {kind='save'}end
local function currentMarker(edition)
  if Importer.datasetContract then return Importer.datasetContract(edition).marker end
  -- Fixture-only access to the real format producer on older public hosts.
  -- Do not invent a marker or expose a new production API just for this test.
  for i=1,100 do
    local name,fn=debug.getupvalue(Importer.readyReport,i)
    if name=='markerFor' then return fn(edition) end
    if name==nil then break end
  end
  error('native cache marker producer unavailable')
end
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire','red','yellow','gold','silver','crystal'}) do
  local marker=currentMarker(edition)
  local present=require('src.core.GameVersion').generation(edition)==3
  T.eq(marker:find('original-object-sheets-v'..Sheets.SCHEMA..':',1,true)~=nil,present,'schema marker applies only to GBA')
  Cache.read=function(path)
    if path=='rom-cache.complete' then return marker end
    if path=='data/generated/tilesets.lua' then return 'return {TilesetPlayersHouse={},TilesetHouse={}}' end
  end
  Cache.exists=function(path)return path~='data/generated/gen3_object_sheets.lua' end
  local ready=Importer.readyReport(edition)
  T.eq(ready.ok,not present,'cache upgrade is scoped to GBA: '..edition)
  if present then T.same(ready.missing,{'data/generated/gen3_object_sheets.lua'}) end
  Cache.exists=function()return true end
  T.eq(Importer.readyReport(edition).ok,true,'a completed upgrade becomes ready without a format bump')
  if present then
    local oldMarker=marker:gsub('original%-object%-sheets%-v'..Sheets.SCHEMA..':','original-object-sheets-v1:')
    Cache.read=function(path)if path=='rom-cache.complete'then return oldMarker end end
    T.eq(Importer.readyReport(edition).ok,false,'previous object schema requests automatic cache regeneration')
  end
end
Cache.read,Cache.exists,Cache.rootReport=read,exists,rootReport
T.finish('compact original object sheets')
