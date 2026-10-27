-- Asymmetric GPU oracle for the actual world compositor, UI and field FX.
-- POKEPORT_DRIVER=<absolute path> in a fresh, fused Red test preview.
-- PALETTE_GPU_OUT must name an existing isolated results directory.
love.errorhandler=function(err)
 local f=assert(io.open(assert(os.getenv('PALETTE_GPU_OUT'))..'/driver-error.txt','w'));f:write(debug.traceback(tostring(err)));f:close()
 return function()return 1 end
end
return function(game)
 local U={wait=function(n)for _=1,n do coroutine.yield()end end};local Json=require('src.link.Json');local g=love.graphics
 local Frame=require('src.render.WindowFrame');local Renderer=require('src.render.Renderer');local Overworld=require('src.world.OverworldController');local Version=require('src.core.GameVersion')
 assert(os.getenv('POKEPORT_ISOLATED_TESTING')=='1','Run only in an explicitly isolated test process')
 assert(love.filesystem.isFused()and love.filesystem.getIdentity():match('^Gen2Recomp%-NativePreview%-'))
 assert(Version.get()=='red'and not next(game.mods.mods),'Use a separate Red import without mods')
 local out=assert(os.getenv('PALETTE_GPU_OUT'));local R=setmetatable({},{__index=Renderer});R:init()
 local report={backend=g.getRendererInfo(),cases={}}
 local negative=os.getenv('POKEPORT_ORIENTATION_NEGATIVE')=='1';report.negativeControl=negative or nil
 local function save()local f=assert(io.open(out..'/orientation-pixels.json','w'));f:write(Json.encode(report));f:close()end
 local shader=g.newShader((negative and "#define POKEPORT_NATIVE_CLIP_SPACE 1\n" or "")..[[
  vec4 position(mat4 matrix,vec4 p){
   // A LÖVE 11 custom 3D shader: author projected Y-up then pre-flipped
   // its render-target clip Y. LÖVE 12 will normalize clip Y again.
   vec4 clip=vec4(p.x/32.0-1.0,1.0-p.y/32.0,0.0,1.0);
   clip.y=-clip.y;return clip;
  }
 ]])
 local vertices={}
 local function quad(y,h,r,gg,b)
  for _,v in ipairs({{0,y},{64,y},{64,y+h},{0,y},{64,y+h},{0,y+h}})do vertices[#vertices+1]={v[1],v[2],0,0,r,gg,b,1}end
 end
 quad(0,32,1,0,0);quad(32,32,0,1,0)
 local mesh=g.newMesh(vertices,'triangles','static');local world=g.newCanvas(64,64,{dpiscale=1});world:setFilter('nearest','nearest')
 local originalDraw=love.draw
 local function colour(data,x,y,want,label)
  local r,gg,b=data:getPixel(x,y);local actual={r,gg,b}
  for i=1,3 do assert(math.abs(actual[i]-want[i])<.08,label..' channel '..i..': '..actual[i])end
  return actual
 end
 for _,case in ipairs({
  {name='legacy-3d',version='red',legacy=true},
  {name='native-2d',version='red',pipeline={worldOrientation='native'}},
  {name='portable-gen3',version='emerald',pipeline={worldFormat='renderData.v1'}},
  {name='native-gen4',version='platinum'},
 })do
  local completed=false;local metrics
  love.draw=function()
    Version.set(case.version);R:beginFrame();g.push('all');g.setCanvas(world);g.origin();g.setShader();g.setScissor();g.setColor(1,1,1,1);g.clear(0,0,0,1)
    if case.legacy then g.setShader(shader);g.draw(mesh);g.setShader()
    else g.setColor(1,0,0,1);g.rectangle('fill',0,0,64,32);g.setColor(0,1,0,1);g.rectangle('fill',0,32,64,32)end
    Overworld.withOverrideMirror(function()
     g.setColor(1,1,0,1);g.rectangle('fill',4,10,8,2)
     g.setColor(1,0,1,1);g.rectangle('fill',4,12,3,5)
    end,case.pipeline)
    g.setCanvas(R.canvas);g.origin();g.setShader();g.clear(0,0,0,0);g.setColor(0,0,1,1);g.rectangle('fill',70,2,20,8);g.pop()
    R:setWorldOverride(world,case.pipeline);metrics=R:endFrame();Version.set('red')
  end
  Frame.observe(function(data)
    local w,h=data:getDimensions();local points={}
    points.worldTop=colour(data,math.floor(w*.8),math.floor(h*.2),{1,0,0},'red top '..case.name)
    points.worldBottom=colour(data,math.floor(w*.8),math.floor(h*.8),{0,1,0},'green bottom '..case.name)
    points.fxTop=colour(data,math.floor(w*8/64),math.floor(h*11/64),{1,1,0},'yellow FX cap '..case.name)
    points.fxStem=colour(data,math.floor(w*5/64),math.floor(h*14/64),{1,0,1},'magenta FX stem '..case.name)
    local dpiX=w/metrics.width;local dpiY=h/metrics.height
    points.uiTop=colour(data,math.floor((metrics.gameX+80*metrics.scale/dpiX)*dpiX),math.floor((metrics.gameY+5*metrics.scale/dpiY)*dpiY),{0,0,1},'blue upright UI '..case.name)
    if not completed then local f=assert(io.open(out..'/'..case.name..'.png','wb'));f:write(data:encode('png'):getString());f:close();report.cases[#report.cases+1]={name=case.name,passed=true,pixels=points};save();completed=true end
  end)
  U.wait(3);assert(completed,'No GPU readback for '..case.name)
 end
 Frame.observe(nil);love.draw=originalDraw;Version.set('red');report.passed=true;save()
end
