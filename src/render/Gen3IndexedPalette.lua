-- Native indexed-backdrop lookup follows src/battle/Gen3Battle.lua (Cedric).
-- Copyright (c) 2026 Cedric. Existing Gen2Recomped licence remains applicable.
-- Bank factoring and packed-colour helpers: copyright (c) 2026 Roxas2712.
-- See LICENSE-ROXAS2712.md for those original contributions.
-- Each consumer owns its bank. Sharing shader uniforms across a native draw
-- and a source draw would corrupt the caller even after restoring its shader.
local bit=require('bit')
local M={}
local unpack=table.unpack or unpack
local zero={0,0,0}
function M.rgb(value)
 value=tonumber(value)or 0
 return bit.band(value,31),bit.band(bit.rshift(value,5),31),bit.band(bit.rshift(value,10),31)
end
function M.pack(r,g,b)
 return bit.bor(bit.band(r or 0,31),bit.lshift(bit.band(g or 0,31),5),bit.lshift(bit.band(b or 0,31),10))
end
function M.blend5(r,g,b,coefficient,tr,tg,tb)
 local c=tonumber(coefficient)or 0
 return r+math.floor((tr-r)*c/16),g+math.floor((tg-g)*c/16),b+math.floor((tb-b)*c/16)
end
function M.gray5(r,g,b)local c=math.floor((r+g+b)/3);return c,c,c end
function M.blendColor(value,coefficient,target)
 local r,g,b=M.rgb(value);local tr,tg,tb=M.rgb(target)
 return M.pack(M.blend5(r,g,b,coefficient,tr,tg,tb))
end
function M.new(opts)
 opts=opts or{}
 local bank={cutout=opts.cutout==true,paletteAlpha=opts.paletteAlpha==true,vectors={}}
 for i=1,16 do bank.vectors[i]={0,0,0,1}end
 function bank:shader()
  if self.program then return self.program end
  if self.failed then return nil,self.failed end
  if not(love and love.graphics and love.graphics.newShader)then return nil,'native shader compiler unavailable'end
  local choices={}
  for i=0,15 do choices[#choices+1]=(i==0 and 'if'or'else if')..(' (index<%d.5)chosen=pal[%d];'):format(i,i)end
  local source=[[
extern vec4 pal[16];
vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen) {
 vec4 px=Texel(tex,uv);
]]..(self.cutout and ' if(px.a<0.5)return vec4(0.0);\n'or'')..[[
 float index=floor(px.r*15.0+0.5);
 vec4 chosen=pal[0];
]]..table.concat(choices,'\n')..'\n'..(self.cutout and ''or' chosen.a*=px.a;\n')..[[
 return chosen*colour;
}
]]
  local ok,shader=pcall(love.graphics.newShader,source)
  if not ok then self.failed=tostring(shader);return nil,self.failed end
  self.program=shader;return shader
 end
 function bank:sendNormalized(colours)
  assert(type(colours)=='table','indexed palette requires normalized colours')
  local shader,why=self:shader();if not shader then return nil,why end
  for i=1,16 do
   local c,v=colours[i]or zero,self.vectors[i]
   v[1],v[2],v[3]=c[1]or 0,c[2]or 0,c[3]or 0
   v[4]=self.paletteAlpha and(c[4]==nil and 1 or c[4])or 1
  end
  shader:send('pal',unpack(self.vectors));return shader
 end
 function bank:release()
  if self.program and self.program.release then self.program:release()end
  self.program,self.failed=nil,nil
 end
 return bank
end
return M
