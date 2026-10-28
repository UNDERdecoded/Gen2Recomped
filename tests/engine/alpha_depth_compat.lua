-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local A=require('src.render.AlphaDepthCompat')
local vertex='vec4 position(mat4 m,vec4 v){return m*v;}'
local pixel='vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){vec4 p=Texel(t,uv);if(p.a<0.5)discard;return p*c;}'
local combined=vertex..'\n'..pixel
local adapted,changed=A.source(combined)
T.check(changed,'projected alpha cutout gets a late depth boundary')
T.check(adapted:find(combined,1,true)~=nil,'authored body, alpha test and projection stay byte-identical')
T.check(adapted:find('gl_FragDepth = gl_FragCoord.z;',1,true)~=nil,'depth remains the rasterized source depth')
T.check(adapted:find('pokeportAlphaDepthEffect(color, tex, uv, screen)',1,true)~=nil,'effect executes exactly once through the wrapper')
T.eq(select(2,A.source(adapted)),false,'idempotent through layered compilers')
T.eq(select(2,A.source(pixel)),false,'ordinary 2D pixel program stays untouched')
T.check(select(2,A.source(pixel,true)),'separate projected vertex source admits pixel program')
for _,source in ipairs{
 vertex,
 vertex..'\nvec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){return Texel(t,uv)*c;}',
 combined..'\n// gl_FragDepth is authored below\nvoid depth(){gl_FragDepth=0.5;}',
 combined..'\nvoid depth(){gl_FragDepthEXT=0.5;}',
 '#define POKEPORT_NATIVE_ALPHA_DEPTH 1\n'..combined,
 'void vertexmain(){}\n'..pixel,
 '/*'..vertex..'*/\n'..pixel,
 vertex..'\n// discard\nvec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){return c;}',
}do
 local output,rewritten=A.source(source)
 T.eq(output,source,'unaffected/custom depth program keeps exact source')
 T.eq(rewritten,false,'unaffected/custom depth program is not wrapped')
end
T.check(select(2,A.source('// POKEPORT_NATIVE_ALPHA_DEPTH gl_FragDepth\n'..combined)),
 'comments do not opt out of alpha depth safety')
local graphics,version,filesystem,thread=love.graphics,love.getVersion,love.filesystem,love.thread
for _,backend in ipairs{'OpenGL','Metal'}do
 package.loaded['src.render.AlphaDepthCompat']=nil
 local calls,selected,target,writes,throwDraw={},nil,nil,true,false
 local methods={}
 function methods:hasUniform()assert(not self.released,'released');return true end
 function methods:send(name,value)assert(value~='bad','invalid native uniform');self.values[name]=value;return 'sent',nil,3 end
 methods.sendColor=methods.send
 function methods:release()self.released=true end
 local preceding={send=methods.send,sendColor=methods.sendColor,release=methods.release};local precedingHas=methods.hasUniform
 local function compiler(...)
  local shader=setmetatable({values={}},{__index=methods})
  calls[#calls+1]={args={...},shader=shader};return shader
 end
 local options={defines={OWNED_VALUE=1}}
 love.getVersion=function()return 12,0,0 end
 love.filesystem={getInfo=function(path)if path=='cutout.glsl'then return{}end end,
  read=function()return pixel end}
 love.thread={newChannel=function()local held;return{
  push=function(_,v)held=v end,peek=function()return held end,
  clear=function()held=nil end,release=function()end}end}
 love.graphics={getRendererInfo=function()return backend end,newShader=compiler,
  getShader=function()return selected end,setShader=function(s)selected=s end,
  getCanvas=function()return target end,getDepthMode=function()return 'lequal',writes end,
  getStackDepth=function()return 0 end,present=function()end,
  draw=function()if throwDraw then error('native draw failed',0)end;return selected,nil,7 end,
  validateShader=function()return true end}
 local compat=require('src.render.AlphaDepthCompat')
 T.eq(compat.install(),backend=='Metal',backend..' explicit backend scope')
 T.eq(compat.fragmentDepthTarget(),false,backend..' unobservable target cannot select a depth variant')
 local shader=love.graphics.newShader('cutout.glsl',vertex,options)
 T.eq(shader,calls[1].shader,backend..' returns the real original Shader')
 T.eq(calls[1].args[1],'cutout.glsl',backend..' original file-backed program untouched')
 T.eq(calls[1].args[2],vertex,backend..' original projection body untouched')
 T.eq(calls[1].args[3],options,backend..' exact compile options identity')
 T.eq(#calls,backend=='Metal'and 2 or 1,backend..' bounded companion compilation')
 if backend=='Metal'then
  T.eq(compat.compileNative,compiler,'derivative compiler retains the exact preceding constructor')
  T.check(compat.ownsShaderMethods(methods),'only the actual installed depth method owner is recognized')
  T.check(compat.followsShaderMethods(methods,preceding,precedingHas),'the exact predecessor is attested')
  T.eq(compat.followsShaderMethods(methods,{send=function()end,sendColor=preceding.sendColor,release=preceding.release},precedingHas),false,'an intervening foreign value owner cannot be hidden by a later engine hook')
  local owned=methods.send;methods.send=function(...)return owned(...)end
  T.eq(compat.ownsShaderMethods(methods),false,'a later foreign owner is not mistaken for an engine hook')
  methods.send=owned;T.check(compat.ownsShaderMethods(methods))
  local late=calls[2].shader
  T.check(calls[2].args[1]:find('gl_FragDepth = gl_FragCoord.z;',1,true)~=nil,'late program keeps rasterized depth')
  T.eq(calls[2].args[2],vertex,'separate vertex source preserved')
  T.eq(calls[2].args[3],options,'companion compile options identity')
  local result={shader:send('gain',2)}
  T.eq(result[1],'sent','native send return preserved');T.eq(result[3],3,'send nil-bearing return preserved')
  T.eq(late.values.gain,2,'successful scalar upload mirrored eagerly')
  local ok=pcall(shader.send,shader,'gain','bad')
  T.eq(ok,false,'native validation failure propagated')
  T.eq(late.values.gain,2,'rejected write never corrupts companion')
  shader:sendColor('tint',{1,.5,.2})
  T.eq(late.values.tint,shader.values.tint,'texture/array/colour arguments forwarded directly without retained Lua snapshots')
  selected=shader;target={depthstencil={{getFormat=function()return 'depth24'end}}}
  T.eq(compat.fragmentDepthTarget(),true,'the shared variant seam uses the actual depth binding')
  local actual,empty,last=love.graphics.draw()
  T.eq(actual,late,'explicit depth attachment selects late alpha program')
  T.eq(empty,nil,'draw nil-bearing return preserved');T.eq(last,7,'draw return arity retained')
  T.eq(selected,shader,'original restored immediately after native draw')
  target={getFormat=function()return 'rgba8'end}
  T.eq(compat.fragmentDepthTarget(),false,'colour-only variants never declare fragment depth')
  T.eq(love.graphics.draw(),shader,'colour-only target retains original even with stale depth-write state')
  target=nil;T.eq(love.graphics.draw(),shader,'backbuffer without observable attachment retains original')
  target={depthstencil={{getFormat=function()return 'stencil8'end}}}
  T.eq(love.graphics.draw(),shader,'stencil-only attachment cannot accept fragment depth')
  target={depthstencil={{getFormat=function()return 'depth24'end}}};writes=false
  T.eq(compat.fragmentDepthTarget(),false,'a non-writing native pass selects the colour program')
  T.eq(love.graphics.draw(),shader,'non-writing ghost/transparent pass retains original')
  writes=true;throwDraw=true
  local ok,err=pcall(love.graphics.draw)
  T.eq(ok,false,'native draw failure propagated');T.eq(err,'native draw failed','native draw error retained')
  T.eq(selected,shader,'draw error restores the original shader')
  throwDraw=false;selected=nil;shader:release();love.graphics.present()
  T.check(late.released,'companion retired after public release at an empty native stack')
  T.eq(compat.install(),false,'single installed constructor wrapper')
 end
end
love.graphics,love.getVersion,love.filesystem,love.thread=graphics,version,filesystem,thread
T.finish('Metal alpha-cutout late depth, exact native shader/target/lifetime contracts')
