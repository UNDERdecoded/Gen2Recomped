package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local C = require('src.render.LegacyShaderCompat')
local vertex = 'vec4 position(mat4 m, vec4 v){return m*v;}'
local pixel = 'vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){return Texel(t,uv)*c;}'
for _,source in ipairs({pixel, '// '..vertex..'\n'..pixel, '/* '..vertex..' */\n'..pixel,
 '#define POKEPORT_NATIVE_CLIP_SPACE 1\n'..vertex, 'void vertexmain(){love_Position=vec4(0.);}',
 '// /*\n'..pixel..'\n// */'}) do
 local actual,changed=C.source(source);T.eq(actual,source,'native/pixel/comment text preserved');T.eq(changed,false)
end
for _,source in ipairs({vertex, '#pragma language glsl3\n'..vertex..'\n'..pixel,
 '// /* ignored\n'..vertex, '/* // ignored */\n'..vertex,
 '// #define POKEPORT_NATIVE_CLIP_SPACE 1\n'..vertex}) do
 local actual,changed=C.source(source);T.eq(changed,true,'real position adapted');T.check(actual:find(source,1,true)~=nil,'source bytes retained')
 local again,twice=C.source(actual);T.eq(again,actual,'adaptation idempotent');T.eq(twice,false)
end
for _,marker in ipairs({'POKEPORT_NATIVE_CLIP_SPACE','POKEPORT_LEGACY_CLIP_SPACE_ADAPTED'})do
 for _,value in ipairs({0,1,false,'0'})do
  local actual,changed=C.source(vertex,{defines={[marker]=value}})
  T.eq(actual,vertex,'named compiler marker preserves source identity');T.eq(changed,false)
 end
 local actual,changed=C.source(vertex,{defines={marker}})
 T.eq(actual,vertex,'array compiler marker preserves source');T.eq(changed,false)
 for _,defines in ipairs({{[marker..'_EXTRA']=1},{marker..'_EXTRA'},{OTHER=marker}})do
  local _,changed=C.source(vertex,{defines=defines});T.eq(changed,true,'unrelated compiler definition is not a marker')
 end
 local _,changed=C.source('#define '..marker..'_EXTRA 1\n'..vertex)
 T.eq(changed,true,'underscore suffix is part of GLSL identifier')
end
local poison=setmetatable({},{__index=function()error('option metatable must not execute')end})
T.eq(select(2,C.source(vertex,poison)),true,'compatibility inspection does not execute option metatable')
local converted = [[
vec4 canvasProject(mat4 matrix,vec4 vertex){return vec4(vertex.xy,0.,1.);}
vec4 position(mat4 matrix,vec4 vertex){vec4 clip=canvasProject(matrix,vertex);clip.y=-clip.y;return clip;}
]]
local preserved, adapted = C.source(converted)
T.eq(preserved,converted,'producer canvas conversion is preserved byte for byte');T.eq(adapted,false)
for _,source in ipairs({converted:gsub('clip%.y=%-clip%.y;', ''),
 converted:gsub('return clip;', 'clip.x+=1.;return clip;'),
 converted:gsub('canvasProject%(matrix,vertex%)', 'canvasProject(vertex,matrix)'),
 '// '..converted:gsub('\n',' ')..'\n'..vertex}) do
 T.eq(select(2,C.source(source)),true,'partial, different or commented conversion retains legacy adaptation')
end
local savedLove=love
local shader,canvas,stack=nil,nil,{}
local creations,validations,sends={},{},{}
local g={}
function g.newShader(a,b,c)
 local s={a=a,b=b,c=c}
 function s:hasUniform(name)return type(self.a)=='string'and self.a:find('pokeportLegacyCanvasY',1,true)~=nil or type(self.b)=='string'and self.b:find('pokeportLegacyCanvasY',1,true)~=nil end
 function s:send(name,y)sends[#sends+1]={self,name,y}end
 creations[#creations+1]=s;return s
end
function g.validateShader(es,a,b,c)validations[#validations+1]={es,a,b,c};return true,'compiler message'end
function g.getCanvas()return canvas end
function g.setCanvas(c)if c=='bad'then error('invalid target')end;canvas=c end
function g.getShader()return shader end
function g.setShader(s)shader=s end
function g.push()stack[#stack+1]={canvas,shader}end
function g.pop()local s=table.remove(stack);canvas,shader=s[1],s[2]end
love={graphics=g,getVersion=function()return 11,5,0 end}
T.eq(C.install(),false,'LOVE11 left untouched')
love.getVersion=function()return 12,0,0 end
local reads=0
love.filesystem={getInfo=function(p)return p=='legacy.glsl'and{}or nil end,read=function()reads=reads+1;return vertex end}
T.eq(C.install(),true);T.eq(C.install(),false,'installed once')
local options={defines={TEST=1}};local a=g.newShader(vertex,options)
T.eq(a.b,options,'compile options passed by identity');T.eq(#sends,1);T.eq(sends[1][3],1,'backbuffer factor')
g.setShader(a);T.eq(#sends,1,'unchanged factor not resent')
g.setCanvas({});T.eq(sends[#sends][3],-1,'canvas factor');T.eq(#sends,2)
g.push();g.setCanvas();T.eq(sends[#sends][3],1);g.pop();T.eq(sends[#sends][3],-1,'pop restores target factor')
g.push();g.setShader();g.setCanvas();g.pop();T.eq(g.getShader(),a);T.eq(sends[#sends][3],-1,'pop restores shader and target')
T.eq(pcall(g.setCanvas,'bad'),false,'target errors not swallowed')
local n=#sends;g.newShader(pixel);T.eq(#sends,n,'pixel-only shaders require no extra uniform')
local b=g.newShader(pixel,vertex,options);T.eq(b.a,pixel);T.eq(b.c,options);T.check(b.b:find('pokeportLegacyCanvasY',1,true)~=nil,'separate vertex adapted')
local f=g.newShader('legacy.glsl');T.check(f.a:find('pokeportLegacyCanvasY',1,true)~=nil,'file source adapted')
local missing=g.newShader('missing.glsl');T.eq(missing.a,'missing.glsl','missing file left for runtime error')
local ok,msg=g.validateShader(true,pixel,vertex,options);T.eq(ok,true);T.eq(msg,'compiler message');T.eq(validations[1][1],true);T.eq(validations[1][4],options)
T.check(validations[1][3]:find('pokeportLegacyCanvasY',1,true)~=nil,'validation uses same source')
for _,defines in ipairs({{POKEPORT_NATIVE_CLIP_SPACE=1},{POKEPORT_NATIVE_CLIP_SPACE=false},{'POKEPORT_NATIVE_CLIP_SPACE'}})do
 local nativeOptions={defines=defines};local n=#sends
 local native=g.newShader(vertex,nativeOptions)
 T.eq(native.a,vertex,'native compile source bytes unchanged');T.eq(native.b,nativeOptions,'native compile options retain identity');T.eq(#sends,n,'native compile has no compatibility uniform')
 local split=g.newShader(pixel,vertex,nativeOptions)
 T.eq(split.a,pixel);T.eq(split.b,vertex);T.eq(split.c,nativeOptions,'split shader options retain identity')
 local beforeReads=reads;local fromFile=g.newShader('legacy.glsl',nativeOptions)
 T.eq(fromFile.a,'legacy.glsl','native shader file delegated without a redundant read')
 T.eq(reads,beforeReads,'native compile avoids extra file IO')
 g.validateShader(true,pixel,vertex,nativeOptions)
 local last=validations[#validations];T.eq(last[2],pixel);T.eq(last[3],vertex);T.eq(last[4],nativeOptions,'validator retains native compile options')
end
love=savedLove
local beforeNative=#sends;local derived=C.compileNative(vertex,options)
T.eq(derived.a,vertex,'derived native source bypasses repeated clip adaptation')
T.eq(derived.b,options,'native compiler seam preserves options')
T.eq(#sends,beforeNative,'native compiler seam has no legacy uniform ownership')
T.finish('legacy shader compatibility')
