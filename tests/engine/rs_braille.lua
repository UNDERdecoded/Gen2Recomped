package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local X=require('src.import.RomExtractorGen3')
-- A synthetic font: interleaved dot bits, explicit nonzero tile mapping,
-- one-pixel unraised dots and 3x3 raised dots. No cartridge bytes are used.
local raw,base,map,wall={},0x2000,0x1000,0x4000
local function tile(code,halfRow) return (code*2+1-halfRow)%256 end
for code=0,127 do
  for halfRow=0,1 do raw[map+code*2+halfRow]=tile(code,halfRow) end
  local value=code%64
  local half=math.floor(code/64)
  for y=0,15 do
    local word=0
    for x=0,7 do
      local ink=false
      for dot=0,5 do
        local cx,cy=(dot%2==0 and 2 or 10),2+math.floor(dot/2)*5
        local dx,dy=x+half*8-cx,y-cy
        local raised=math.floor(value/2^dot)%2==1
        if (dx==0 and dy==0) or (raised and math.abs(dx)<=1 and math.abs(dy)<=1) then ink=true end
      end
      if ink then word=word+2^(7-x) end
    end
    raw[base+tile(code,math.floor(y/8))*8+y%8]=word
  end
end
for i,v in ipairs({9,6,19,13,12,9,1,5,3,0xFE,0x3F,0xFF}) do raw[wall+i-1]=v end
local function extractor(profile)
  return setmetatable({manifest={braille=profile},symbols={gFontBrailleLatinGlyphs=base},
    rom={u8=function(_,a)return raw[a] or 0 end},
    _scriptPool={scripts={wall={{'braillemessage',0x08000000+wall}}}},
    beginStage=function()end,fontSheet=function()return nil end,
    write=function(self,key,value)self.output=value end},X)
end
local profile={bits=1,glyphMap=map,halfCodeOffset=64,frameFromHeader=true,lineHeight=32}
local x=extractor(profile)
local a=x:brailleGlyph(base,1)
T.eq(a[3][3],2,'raised dot retains its common center')
T.eq(a[2][2],1,'MSB-first left half raises the first dot')
T.eq(a[2][10],3,'A does not raise the top right dot')
T.eq(a[3][11],2,'right half retains the unraised dot')
x:extractBraille()
local b=assert(x.output and x.output.gen3Braille)
local w=b.messages[0x08000000+wall]
T.eq(w.text,'ABC\n{3F}','dot identities decode letters from the actual masks')
T.eq(w.x,10,'frame left comes from header')
T.eq(w.y,7,'frame top comes from header')
T.eq(w.width,9,'frame right comes from header')
T.eq(w.height,6,'frame bottom comes from header')
T.eq(w.textX,96,'text x is independent of frame x')
T.eq(w.textY,72,'text y is independent of frame y')
T.eq(b.lineHeight,32,'RS newline includes its extra two tiles')
-- A font which violates the all-64-pattern proof must not create a wall.
raw[base+tile(63,0)*8]=1
local broken=extractor(profile)
broken:extractBraille()
T.eq(broken.output,nil,'unrelated or corrupt font is rejected')
T.finish('RS 1bpp braille masks and header window')
