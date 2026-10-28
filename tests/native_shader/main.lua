-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- QA foundation only: qualify native resource leases before an adapter exists.
io.stdout:setvbuf('no')
local engine=os.getenv('SHADER_TEST_ENGINE')or(love.filesystem.getSource()..'/../..')
package.path=engine..'/?.lua;'..engine..'/?/init.lua'
local count=0
local function check(value,label)count=count+1;assert(value,label);print('CHECK',count,label)end
local function pack(...)return{n=select('#',...),...}end
local function equalReturns(a,b)
 if a.n~=b.n then return false end
 for i=1,a.n do if a[i]~=b[i]then return false end end
 return true
end
local code=[[
uniform vec4 tint;
vec4 effect(vec4 color,Image image,vec2 uv,vec2 pixel){return tint;}
]]
local function tests()
 local g=love.graphics
 check(type(g.getStackDepth)=='function','actual native stack-depth query exists')
 local start=g.getStackDepth()
 check(start==0,'fresh native graphics stack is empty')
 local channel=love.thread.newChannel()
 local shader=g.newShader(code)
 local original=tostring(shader)
 channel:push(shader)
 check(channel:peek()==shader,'lease preserves live userdata identity')
 local sendReturns=pack(shader:send('tint',{1,0,0,1}))
 print('NATIVE_SEND_RETURNS',sendReturns.n,tostring(sendReturns[1]))
 check(shader:release()==true,'first native release succeeds')
 check(shader:release()==false,'repeated native release returns false')
 check(not pcall(shader.hasUniform,shader,'tint'),'released interface is unusable')
 local alias=channel:peek()
 check(alias~=shader,'lease reconstructs a fresh valid userdata')
 check(tostring(alias)==original,'fresh alias owns the same C shader')
 check(alias:hasUniform('tint'),'shader remains live after original release')
 check(equalReturns(pack(alias:send('tint',{1,0,0,1})),sendReturns),'lease preserves actual native send arity and values')
 local weak=setmetatable({alias},{__mode='v'})
 alias=nil;collectgarbage('collect');collectgarbage('collect')
 check(weak[1]==nil,'C lease does not keep Lua userdata alive')
 alias=channel:peek()
 check(alias:hasUniform('tint'),'C lease survives Lua collection')
 local other=g.newShader(code);other:send('tint',{0,1,0,1})
 local rawPush,rawPop=g.push,g.pop
 g.setShader(alias);rawPush('all');g.setShader(other)
 check(g.getStackDepth()==start+1,'native push is visible without wrapper counters')
 alias:release();channel:clear();rawPop()
 local rebound=g.getShader()
 check(rebound:hasUniform('tint'),'native C stack retains shader after all Lua leases release')
 check(tostring(rebound)==original,'native pop restores original C shader')
 check(g.getStackDepth()==start,'native pop returns to empty stack')
 g.setShader();rebound:release();other:release();channel:release()
 check(type(shader.getReferenceCount)~='function','do not depend on an unavailable reference-count API')

 -- Sampler values are C-owned after send. A future adapter must either replay
 -- updates eagerly or fall back, rather than resending a released Lua Texture.
 local target=g.newCanvas(4,4,{dpiscale=1})
 local imageData=love.image.newImageData(1,1);imageData:setPixel(0,0,.25,.5,.75,1)
 local texture=g.newImage(imageData);imageData:release()
 local sample=g.newShader('uniform Image sampleImage; vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){return Texel(sampleImage,vec2(.5));}')
 local samplerReturns=pack(sample:send('sampleImage',texture))
 check(equalReturns(samplerReturns,sendReturns),'native sampler and numeric send return contracts agree')
 texture:release()
 check(not pcall(sample.send,sample,'sampleImage',texture),'released sampler cannot be replayed from Lua')
 g.setCanvas(target);g.setShader(sample);g.setBlendMode('replace','premultiplied');g.setColor(1,1,1,1);g.rectangle('fill',0,0,4,4)
 g.setCanvas();g.setShader()
 local pixels=target:newImageData();local r,b,c,a=pixels:getPixel(1,1)
 check(math.abs(r-.25)<1/255 and math.abs(b-.5)<1/255 and math.abs(c-.75)<1/255 and a==1,'C-owned sampler still draws correct pixels after Lua release')
 check(math.abs(r-.75)>1/255,'wrong-color negative is observable')
 pixels:release();target:release();sample:release()
 check(g.getStackDepth()==start,'fixture leaves no native graphics scope')
 print('SHADER_CONTRACT_PASS',count)
end
local function adapterTests()
 local g=love.graphics
 local hasLegacy,legacy=pcall(require,'src.render.LegacyShaderCompat')
 if hasLegacy then legacy.install()end
 local hasAlpha,alpha=pcall(require,'src.render.AlphaDepthCompat')
 if hasAlpha then alpha.install()end
 if os.getenv('QA_SHADER_WRONG_COMPILER')=='1'then
  assert(hasLegacy,'projection negative requires actual canvas compatibility adapter')
  legacy.compileNative=g.newShader
 end
 local rawGet,rawSet,rawPush,rawPop=g.getShader,g.setShader,g.push,g.pop
 local temporary=g.newShader(code);local nativeSend=debug.getmetatable(temporary).__index.send;temporary:release()
 if os.getenv('QA_SHADER_MULTIPLE_RETURNS')=='1'then
  local temporary=g.newShader(code);local methods=debug.getmetatable(temporary).__index
  local send,sendColor=methods.send,methods.sendColor
  methods.send=function(self,...)send(self,...);return nil,'native-owner',nil,42 end
  methods.sendColor=function(self,...)sendColor(self,...);return false,nil,'native-color-owner',nil end
  temporary:release()
 end
 local S=require('src.render.ShaderSpecialization')
 check(S.install(),'native Metal adapter installs explicitly for QA')
 check(not S.install(),'native adapter install is idempotent')
 local code=[[
uniform LOVE_HIGHP_OR_MEDIUMP float gate;
uniform vec4 colors[3];
uniform vec4 tint;
uniform mat4 sceneMatrix;
#ifdef VERTEX
uniform Image vertexOnly;
vec4 independentPosition(mat4 supplied,vec4 vertex){vec4 clip=sceneMatrix*vertex;clip.x+=Texel(vertexOnly,vec2(.5)).r*.0001;return clip;}
vec4 position(mat4 supplied,vec4 vertex){vec4 clip=independentPosition(supplied,vertex);clip.y=-clip.y;return clip;}
#endif
#ifdef PIXEL
uniform Image ownedTexture;
vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){
 vec4 base=(colors[0]+colors[1]+colors[2]+tint)*.25;
 if(gate>.5){base+=Texel(ownedTexture,uv)*.125;}
 return base;
}
#endif
]]
 local reference=g.newShader(code)
 local candidate=g.newShader(code..string.rep(' \n',32768))
 check(type(candidate)=='userdata'and candidate:typeOf('Shader'),'optimized source keeps real Shader userdata')
 check(candidate:hasUniform('gate'),'original uniform interface is retained')
 check(S.status().sources==1,'only the large source is admitted')
 local function send(method,name,...)
  local native=pack(reference[method](reference,name,...))
  local adapted=pack(candidate[method](candidate,name,...))
  check(equalReturns(native,adapted),'actual native '..method..' return arity/values are preserved')
 end
 local image=love.image.newImageData(1,1);image:setPixel(0,0,.25,.5,.75,1)
 local texture=g.newImage(image);image:release()
 send('send','ownedTexture',texture)
 send('send','vertexOnly',texture)
 send('send','sceneMatrix','row',{.25,0,0,-1,0,.25,0,-1,0,0,1,0,0,0,0,1})
 send('send','colors',{1,0,0,1},{0,1,0,1},{0,0,1,1})
 send('send','colors',{.5,.25,0,1})
 local mutable={.25,.5,.75,1};send('sendColor','tint',mutable)
 mutable[1],mutable[2],mutable[3]=1,1,1
 send('send','gate',0)
 local target=g.newCanvas(8,8,{dpiscale=1})
 local function compare(rightShader)
  g.setCanvas(target);g.origin();g.setBlendMode('replace','premultiplied');g.setColor(1,1,1,1)
  g.clear(0,0,0,0)
  g.setShader(reference);g.rectangle('fill',0,1,4,2)
  g.setShader(rightShader or candidate);g.rectangle('fill',4,1,4,2)
  local real,visible=rawGet(),g.getShader()
  g.setCanvas();g.setShader()
  local data=target:newImageData();local same=true
  for y=0,7 do for x=0,3 do
   local a={data:getPixel(x,y)};local b={data:getPixel(x+4,y)}
   for i=1,4 do if a[i]~=b[i]then same=false end end
  end end
  data:release();return same,real,visible
 end
 local same,actual,visible=compare()
 check(same,'initial partial-array history and mutable sendColor snapshot are pixel exact')
 check(visible==candidate and actual~=candidate,'public shader identity maps actual compiled variant to original')
 check(S.status().compiled==1,'first actual native variant compiled')
 send('send','gate',1)
 check(compare(),'new branch replays old array tails and color snapshot exactly')
 check(S.status().compiled==2,'second branch has an independent compiled program')
 candidate:send('gate',0)
 check(not compare(),'deliberately wrong branch is detected by independent native pixel oracle')
 send('send','gate',1);check(compare(),'restored branch restores original pixels')
 send('send','colors',{.125,0,0,1})
 check(compare(),'eager prefix update preserves untouched array tail in existing variant')
 texture:release()
 send('send','gate',0);check(compare(),'previously compiled zero branch survives sampler Lua release')
 send('send','gate',1);check(compare(),'previously compiled sampled branch retains C texture ownership')
 check(not pcall(candidate.send,candidate,'ownedTexture',texture),'native invalid released resource error propagates')
 check(compare(),'rejected native send does not corrupt prior variant uniforms')
 check(S.status().failures==0,'qualified native compiler and replay have no errors')
 -- A raw native push bypasses adapter Lua wrappers. Its hidden C reference
 -- must keep the variant-to-original mapping alive through explicit release.
 g.setCanvas(target);g.setShader(candidate);g.rectangle('fill',0,0,8,4)
 rawPush('all');rawSet();check(candidate:release(),'original explicit release preserves native success return')
 check(not candidate:release(),'original repeated release preserves native false return')
 rawPop()
 local alias=g.getShader()
 check(alias~=candidate and alias:hasUniform('gate'),'hidden C-stack variant restores valid original alias')
 g.rectangle('fill',0,0,8,4)
 check(rawGet()==alias,'released source forces original C shader at next draw')
 g.setCanvas();g.setShader();g.present()
 check(S.status().sources==0 and S.status().variants==0,'empty native stack releases disabled programs and C leases')
 alias:release();reference:release();target:release()
 local alpha=package.loaded['src.render.AlphaDepthCompat']
 if alpha and alpha.fragmentDepthTarget and alpha.compileNative then
  -- Keep an earlier admitted program alive when the first cutout lazily
  -- adds the native depth method owner to this shared Shader class.
  local carryText=[[
uniform float gate;uniform vec4 tint;
vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){if(gate>.5)return tint;return vec4(1.)-tint;}
]]
  local carried=g.newShader(carryText..string.rep(' \n',32768))
  local carryReference=g.newShader(carryText)
  carried:send('gate',1);carried:send('tint',{.1,.2,.3,1})
  target=g.newCanvas(8,8,{dpiscale=1});g.setCanvas(target);g.setShader(carried);g.rectangle('fill',0,0,8,8);g.setCanvas();g.setShader()
  local transformed=os.getenv('QA_SHADER_FOREIGN_BEFORE_DEPTH')=='1'
  if transformed then
   local methods=debug.getmetatable(carried).__index;local preceding=methods.send
   methods.send=function(self,name,value,...)
    if name=='tint'and type(value)=='table'then value={value[1]*.5,value[2]*.5,value[3]*.5,value[4]}end
    return preceding(self,name,value,...)
   end
  end
  local vertex=[[
uniform mat4 sceneMatrix;
#ifdef VERTEX
vec4 independentPosition(mat4 supplied,vec4 vertex){return sceneMatrix*vertex;}
vec4 position(mat4 supplied,vec4 vertex){vec4 clip=independentPosition(supplied,vertex);clip.y=-clip.y;return clip;}
#endif
]]
  local fragment=[[
uniform float gate;
uniform Image ownedTexture;
#ifdef PIXEL
vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){
 vec4 pixel=Texel(ownedTexture,uv);if(gate<.5)pixel.rgb=vec3(0.,0.,1.);
 if(pixel.a<.5)discard;
 DEPTH_WRITE
 return pixel;
}
#endif
]]
  local plain=vertex..fragment:gsub('DEPTH_WRITE','')
  reference=g.newShader(plain)
  -- Independent explicit-depth oracle, without the adapter's source helper.
  local depthReference=g.newShader(vertex..fragment:gsub('DEPTH_WRITE','gl_FragDepth=gl_FragCoord.z;'))
  candidate=g.newShader(plain..string.rep(' \n',32768))
  local depth=g.newCanvas(8,8,{format='depth24stencil8',readable=true,dpiscale=1})
  local pixels=love.image.newImageData(2,1);pixels:setPixel(0,0,0,1,0,0);pixels:setPixel(1,0,0,1,0,1)
  local cutout=g.newImage(pixels);pixels:release();cutout:setFilter('nearest','nearest')
  local matrix={.25,0,0,-1,0,.25,0,-1,0,0,1,0,0,0,0,1}
  send('send','sceneMatrix','row',matrix);send('send','gate',1);send('send','ownedTexture',cutout)
  depthReference:send('sceneMatrix','row',matrix);depthReference:send('gate',1);depthReference:send('ownedTexture',cutout)
  local behind=g.newShader(vertex..[[
#ifdef PIXEL
vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){return vec4(1.,0.,0.,1.);}
#endif
]])
  behind:send('sceneMatrix','row',matrix)
  local beforeCompiled=S.status().compiled;local beforeCompanions=alpha.status().compiled
  check(S.status().sources==2,'the native cutout and preceding program remain admitted')
  local function render(withDepth)
   g.setCanvas(withDepth and{target,depthstencil=depth}or target);g.origin()
   g.setBlendMode('replace','premultiplied');g.setColor(1,1,1,1);g.clear(0,0,0,0,0,1)
   g.setDepthMode('always',withDepth)
   check(alpha.fragmentDepthTarget()==withDepth,'actual native colour/depth attachments select the matching path')
   g.setShader(withDepth and depthReference or reference);g.draw(cutout,0,0,0,2,8)
   g.setShader(candidate);g.draw(cutout,4,0,0,2,8)
   check(g.getShader()==candidate,'depth and colour variants retain original public identity')
   if withDepth then
    g.setDepthMode('less',true);g.setShader(behind);g.rectangle('fill',0,0,8,8)
   end
   g.setCanvas();g.setShader();g.setDepthMode('always',false)
   local data=love.graphics.readbackTexture(target)
   local same=true
   for y=0,7 do for x=0,3 do
    local a={data:getPixel(x,y)};local b={data:getPixel(x+4,y)}
    for i=1,4 do if a[i]~=b[i]then same=false end end
   end end
   check(same,'target-specific variants match independent native pixels')
   if withDepth then
    local r,green,blue,a=data:getPixel(4,4);check(r==1 and green==0 and blue==0 and a==1,'discarded front texels leave the later rear geometry visible')
    r,green,blue,a=data:getPixel(7,4);check(r==0 and green==1 and blue==0 and a==1,'opaque front texels retain depth occlusion')
   end
   data:release()
  end
  render(false);render(true);render(false)
  for key,value in pairs(S.status())do print('DEPTH_VARIANT_STATUS',key,value)end
  local cutoutReference=reference;reference=carryReference
  carryReference:send('gate',1);carryReference:send('tint',{.4,.2,.8,1});carried:send('tint',{.4,.2,.8,1})
  check(compare(carried),'an earlier live program retains exact mutable uniforms across the owned hook interposition')
  carried:send('tint',{1,0,0,1});check(not compare(carried),'earlier-program pixel comparison detects a wrong-value control')
  carried:send('tint',{.4,.2,.8,1});check(compare(carried),'earlier native variant remains reusable after the owned interposition')
  if transformed then
   check(S.status().compiled==beforeCompiled,'an intervening foreign owner keeps its original native programs')
   check(S.status().unsupported>=2,'a later native hook cannot hide the foreign value owner of either live program')
  else
   check(S.status().compiled==beforeCompiled+2,'one colour and one depth variant are reused across target changes')
   check(S.status().depthUses>0,'the native depth variant is actually drawn')
   check(S.status().unsupported==0,'the known native depth owner does not retire earlier programs')
  end
  check(alpha.status().compiled==beforeCompanions,'variants do not manufacture duplicate depth companions')
  reference=cutoutReference
  candidate:release();reference:release();depthReference:release();behind:release();cutout:release();carried:release();carryReference:release();target:release();depth:release();g.present()
  check(S.status().sources==0,'depth variants retire at the actual native empty-stack boundary')
  if transformed then print('SHADER_ADAPTER_PASS',count);return end
 end
 -- Mutable native Data is a supported source API, but is intentionally not a
 -- replayable adapter value. Its original C send and original pixels survive.
 local dataCode=[[
uniform float gate;
uniform vec4 tint;
vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){if(gate>.5)return tint;return vec4(1.0)-tint;}
]]
 reference=g.newShader(dataCode);candidate=g.newShader(dataCode..string.rep(' \n',32768))
 target=g.newCanvas(8,8,{dpiscale=1})
 send('send','gate',0);send('send','tint',{.2,.4,.6,.8});check(compare(),'second native source has an exact compiled baseline')
 local bytes=love.data.newByteData(love.data.pack('string','ffff',.1,.3,.5,.7))
 send('send','tint',bytes)
 check(compare(),'mutable Data send falls back to original C shader with exact pixels')
 check(S.status().unsupported==1,'unsupported replay is counted separately from shader compiler failure')
 bytes:release();g.setShader();g.present()
 reference:release();candidate:release();target:release()
 -- Actual GC of the original userdata must not be defeated by adapter maps.
 local weak=setmetatable({},{__mode='v'})
 do
  local shader=g.newShader(code..string.rep(' \n',32768))
  weak[1]=shader
 end
 collectgarbage('collect');collectgarbage('collect');g.present()
 check(weak[1]==nil,'adapter retains no dead original Lua userdata')
 check(S.status().sources==0,'orphan source is retired at a native empty-stack boundary')
 local held={}
 for i=1,17 do held[i]=g.newShader(code..string.rep(' \n',32768))end
 check(S.status().sources==16,'hard source cap is enforced')
 g.setShader(held[17]);g.rectangle('fill',0,0,4,4)
 check(rawGet()==held[17]and g.getShader()==held[17],'source beyond the cap draws with its exact original C shader')
 g.setShader();for _,shader in ipairs(held)do shader:release()end;g.present()
 check(S.status().sources==0 and S.status().variants==0,'capped source leases retire without lingering programs')
 reference=g.newShader(dataCode);candidate=g.newShader(dataCode..string.rep(' \n',32768));target=g.newCanvas(8,8,{dpiscale=1})
 send('send','gate',0);send('send','tint',{.2,.4,.6,.8});check(compare(),'foreign-method fixture starts with a compiled exact baseline')
 local methods=debug.getmetatable(candidate).__index;local ownedSend=methods.send
 methods.send=nativeSend
 reference:send('tint',{.9,.1,.2,1});candidate:send('tint',{.9,.1,.2,1})
 local exact,actual=compare()
 check(exact and actual==candidate,'late foreign send owner falls back to original values and pixels')
 methods.send=ownedSend;g.setShader();g.present()
 reference:release();candidate:release();target:release()
 g.present()
 -- A macro may declare a local with the uniform's spelling. Its first
 -- argument has no preceding type/comma, so a token-only guard misses it.
 local macroCode=[[
uniform float gate;
float globalValue(){float value=gate*.25;return value;}
#define DECLARE_LOCAL(a,b) float a=0.0,b=1.0
vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){
 vec4 pixel=vec4(globalValue(),0.0,0.0,1.0);
 DECLARE_LOCAL(gate,other);
 if(gate>.5){pixel.g=.5;}
 return pixel;
}
]]
 reference=g.newShader(macroCode);candidate=g.newShader(macroCode..string.rep(' \n',32768))
 target=g.newCanvas(8,8,{dpiscale=1})
 send('send','gate',0);check(compare(),'macro-local shadow preserves independent native pixels at global zero')
 send('send','gate',1);check(compare(),'macro-local shadow preserves independent native pixels at global one')
 check(S.status().sources==0,'macro-local declarations retain the original native program')
 reference:release();candidate:release();target:release();g.present()
 check(g.getStackDepth()==0,'native adapter fixture leaves no graphics scope')
 print('SHADER_ADAPTER_PASS',count)
end
function love.load()
 local ok,why=xpcall(function()tests();if os.getenv('QA_NATIVE_SHADER_ADAPTER')=='1'then adapterTests()end end,debug.traceback)
 if not ok then print('SHADER_CONTRACT_FAIL',why)end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(why)
 print('SHADER_CONTRACT_ERROR',debug.traceback(tostring(why)))
 return function()return 1 end
end
