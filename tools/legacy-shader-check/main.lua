-- ROM-free GPU acceptance for mixed legacy 3D / ordinary 2D render targets.
function love.errorhandler(err)
  io.stderr:write(tostring(err) .. '\n')
  return function() return 1 end
end
local root = love.filesystem.getSource():match('^(.*)/tools/legacy%-shader%-check$')
  or love.filesystem.getWorkingDirectory()
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local Compat = require('src.render.LegacyShaderCompat')
if os.getenv('POKEPORT_SHADER_CHECK_NEGATIVE') == '1' then
  Compat.source = function(source) return source, false end
end
Compat.install()
local g = love.graphics
local checks, cases = 0, {}
local major = love.getVersion()
local function check(ok, why) checks = checks + 1; assert(ok, why) end
local function read(canvas)
  if g.readbackTexture then return g.readbackTexture(canvas) end
  return canvas:newImageData()
end
local function pixel(data, x, y, want, why)
  local r, green, b = data:getPixel(x, y)
  for i, actual in ipairs({r, green, b}) do
    check(math.abs(actual - want[i]) < 2/255, why .. ' channel ' .. i .. ': ' .. actual)
  end
end
local vertices = {}
local function band(y, r, green)
  for _,p in ipairs({{0,y},{64,y},{64,y+32},{0,y},{64,y+32},{0,y+32}}) do
    vertices[#vertices + 1] = {p[1],p[2],0,0,r,green,0,1}
  end
end
band(0,1,0); band(32,0,1)
local sources = {
  {name='legacy-3d', code='vec4 position(mat4 m,vec4 p){return vec4(p.x/32.-1.,p.y/32.-1.,0.,1.);}'},
  {name='2d-parameter', code='vec4 position(mat4 m,vec4 p){return m*p;}'},
  {name='2d-global', code='vec4 position(mat4 m,vec4 p){return TransformProjectionMatrix*p;}'},
  {name='2d-projection', code='vec4 position(mat4 m,vec4 p){return ProjectionMatrix*TransformMatrix*p;}'},
  {name='2d-alias', code='vec4 position(mat4 m,vec4 p){return ClipSpaceFromLocal*p;}'},
}
if major >= 12 then
  sources[#sources+1] = {name='native-opt-out', code=[[#define POKEPORT_NATIVE_CLIP_SPACE 1
    vec4 position(mat4 m,vec4 p){return vec4(p.x/32.-1.,1.-p.y/32.,0.,1.);}]]}
  sources[#sources+1] = {name='native-low-level', code=[[layout(location=0) in vec4 VertexPosition;
    out vec4 VaryingTexCoord; out vec4 VaryingColor;
    void vertexmain(){VaryingTexCoord=vec4(0.);VaryingColor=vec4(1.);love_Position=vec4(VertexPosition.x/32.-1.,1.-VertexPosition.y/32.,0.,1.);}]],
    -- Raw entry points own their vertex colour/UV varyings too.
    pixel='vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){return sc.y<32.?vec4(1,0,0,1):vec4(0,1,0,1);}'}
end
local function render(mesh, canvas, shader, attachment)
  g.push('all'); g.setShader(shader); g.setCanvas(attachment or canvas)
  g.origin(); g.clear(0,0,0,1); g.setColor(1,1,1,1); g.setMeshCullMode('none')
  g.draw(mesh); g.setShader()
  -- A readable asymmetric F-shaped HUD painted *into* the 3D canvas.
  g.setColor(0,0,1,1)
  g.rectangle('fill',4,4,20,3); g.rectangle('fill',4,7,3,10)
  g.rectangle('fill',7,10,10,3)
  g.pop()
end
function love.load()
  local mesh = g.newMesh(vertices,'triangles','static')
  for _,fixture in ipairs(sources) do
    local ok, message = g.validateShader(false,fixture.code,fixture.pixel)
    check(ok,'validate ' .. fixture.name .. ': ' .. tostring(message))
    local shader = g.newShader(fixture.code,fixture.pixel)
    local canvas = g.newCanvas(64,64,{dpiscale=1})
    for _,attachment in ipairs({canvas,{canvas}}) do
      render(mesh,canvas,shader,attachment)
      local data = read(canvas)
      pixel(data,50,10,{1,0,0},fixture.name .. ' red top')
      pixel(data,50,50,{0,1,0},fixture.name .. ' green bottom')
      pixel(data,10,5,{0,0,1},fixture.name .. ' HUD top')
      pixel(data,5,15,{0,0,1},fixture.name .. ' HUD stem')
      pixel(data,15,11,{0,0,1},fixture.name .. ' HUD arm')
      pixel(data,15,15,{1,0,0},fixture.name .. ' HUD gap')
    end
    if fixture.name ~= 'native-low-level' then
      -- These expectations were independently measured on stock LÖVE 11.5.
      for _,winding in ipairs({'cw','ccw'}) do
        for _,cull in ipairs({'front','back'}) do
          g.push('all');g.setCanvas(canvas);g.origin();g.clear(0,0,0,1)
          g.setColor(1,1,1,1);g.setFrontFaceWinding(winding);g.setMeshCullMode(cull)
          g.setShader(shader);g.draw(mesh);g.pop()
          local data, n = read(canvas), 0
          for y=0,63 do for x=0,63 do
            local r,green,b=data:getPixel(x,y)
            if r+green+b>.2 then n=n+1 end
          end end
          local visible = (winding=='cw' and cull=='back') or (winding=='ccw' and cull=='front')
          check(n==(visible and 4096 or 0),fixture.name .. ' culling ' .. winding .. '/' .. cull .. ': ' .. n)
        end
      end
    end
    -- Restoring the target and bound shader through pop must restore its ABI.
    g.push('all'); g.setCanvas(canvas); g.setShader(shader)
    local inner = g.newCanvas(64,64,{dpiscale=1})
    g.push('all');g.setCanvas(inner);g.pop()
    g.origin();g.clear(0,0,0,1);g.setColor(1,1,1,1);g.setMeshCullMode('none');g.draw(mesh);g.pop()
    pixel(read(canvas),50,10,{1,0,0},fixture.name .. ' restored target')
    cases[#cases+1]=fixture.name
  end
  print(('PASS legacy shader GPU: %d checks, %d cases, LOVE %d, %s'):format(checks,#cases,major,g.getRendererInfo()))
  love.event.quit(0)
end
