package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local X=require('src.import.RomExtractorGen3')
local Rom=require('src.import.RomGba')
local function le(n,k)local s=''for _=1,k do s=s..string.char(n%256);n=math.floor(n/256)end;return s end
local bytes={};for i=1,1024 do bytes[i]='\0'end
local function put(at,s)for i=1,#s do bytes[at+i]=s:sub(i,i)end end
local function ptr(at,v)put(at,le(0x08000000+v,4))end
ptr(16,64);ptr(20,128)
for _,a in ipairs({64,128})do
 put(a,le(3,4)..le(2,4));ptr(a+8,256);ptr(a+12,512);ptr(a+16,160);ptr(a+20,192)
end
put(64+24,string.char(1,2));put(128+24,string.char(0,0))
put(256,le(5,2)..le(6,2)..le(7,2)..le(8,2))
for i=0,5 do put(512+i*2,le(i+(i%4)*1024+6*4096,2))end
local x=setmetatable({rom=Rom.new(table.concat(bytes)),manifest={metatileAttributes={bytes=4}},
 symbols={gMapLayouts=16},layout={numMapLayouts=2}},X)
x.beginStage=function()end;x.tick=function()end
local out;x.write=function(_,name,records)T.eq(name,'map_layouts');out=records end
x:extractMapLayouts()
T.eq(out[1].border,le(5,2)..le(6,2)..le(7,2)..le(8,2),'native border representation unchanged')
T.eq(out[1].sourceBorder,le(5,2)..le(6,2),'actual source dimensions retain their own bytes')
T.eq(out[1].sourceBorderWidth,1);T.eq(out[1].sourceBorderHeight,2)
T.eq(out[2].border,out[1].border,'unused source metadata does not change native extraction')
T.eq(out[2].sourceBorder,nil,'unused zero-sized source border is unavailable')
T.eq(out[2].sourceBorderWidth,0);T.eq(out[2].sourceBorderHeight,0)
for i=1,6 do T.eq(out[1].collisionCells[i],(i-1)%4);T.eq(out[1].elevationCells[i],6)end
T.finish('original map borders without native layout changes')
