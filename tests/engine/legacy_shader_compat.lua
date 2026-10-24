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
love.filesystem={getInfo=function(p)return p=='legacy.glsl'and{}or nil end,read=function()return vertex end}
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
love=savedLove
T.finish('legacy shader compatibility')
