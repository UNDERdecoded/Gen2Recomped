package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local J=require('src.link.Json')
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local inputs=J.decode(read(assert(arg[1])));local profiles=J.decode(read(assert(arg[2])))
local original=assert(arg[3]);local bytesCompared=0
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
 local manifest=J.decode(read('tools/rom_manifest_'..edition..'.json'))
 local input=inputs[edition];local raw=read(input.path);T.eq(input.sha1,manifest.romSha1)
 local Rom=require('src.import.RomGba');local nativeRom=Rom.new(raw)
 local sourceRom={get=function(_,at)return raw:byte(at+1)end,u16=function(_,at)return nativeRom:u16(at)end}
 local values={};local cache={write=function(_,path,value)values[path]=value end}
 local versions={FIELD_EFFECTS={},FIELD_MOVE_STREAKS=profiles[edition]}
 local env=setmetatable({require=function(name)T.eq(name,'src.import.gba.versions');return versions end},{__index=_G})
 local fn=assert(loadfile(original));setfenv(fn,env);fn().writeExtract(sourceRom,cache,'fx')
 local Art=require('src.import.Gen3FieldMoveArt');local slices=0
 local artwork=assert(Art.extract(nativeRom,manifest,input.sha1,edition,function()slices=slices+1 end));T.eq(slices,20)
 for _,kind in ipairs({'outdoors','indoors'})do
  local source=assert(values['fx/field_effects/field_move_streaks_'..kind..'.rgba'])
  local native=Art.rgba(artwork.strips[kind]);T.eq(native,source,edition..' '..kind..' exact independently decoded RGBA')
  T.eq(#native,81920);bytesCompared=bytesCompared+#native
 end
 local text=require('src.import.LuaWriter').encodeSplit(artwork)
 local decoded=assert(loadstring(text))();T.eq(Art.rgba(decoded.strips.outdoors),Art.rgba(artwork.strips.outdoors),'native cache round trip')
 T.eq(Art.extract(nativeRom,manifest,string.rep('0',40),edition),nil,'foreign bytes cannot use a declared profile')
 local bad={romSha1=manifest.romSha1,fieldMoveStreaks={schema=1,romSha1=manifest.romSha1,strips={outdoors={tiles=-1,palette=0,tilemap=0,tileCount=16}}}}
 T.eq(Art.extract(nativeRom,bad,input.sha1,edition),nil,'out-of-bounds profiles do not emit partial art')
 local Verify=require('src.import.RomVerification');local hash=Verify.sha1;local hashCalls=0
 Verify.sha1=function(bytes)T.eq(bytes,raw);hashCalls=hashCalls+1;return input.sha1 end
 local ex=require('src.import.RomExtractorGen3').new(raw,{id=edition},manifest);local generated={}
 ex._constants={sentinel='retain'};ex.write=function(_,name,value)generated[name]=value end
 ex.fieldEffectRoles=function()return nil,0,0 end
 ex:extractFieldEffects();Verify.sha1=hash
 T.eq(hashCalls,1);T.eq(generated.constants.sentinel,'retain')
 T.eq(Art.rgba(generated.constants.gen3FieldMovePresentation.strips.indoors),Art.rgba(artwork.strips.indoors),'actual import stage emits the same compact artwork')
 print('FIELD_MOVE_ART_EDITION',edition,#text)
end
print('FIELD_MOVE_ART_RGBA_BYTES',bytesCompared)
T.finish('independent five-edition field-move artwork oracle')
