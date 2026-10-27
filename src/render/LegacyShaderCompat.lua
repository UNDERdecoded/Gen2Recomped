-- The engine and its high-level shader API were authored for LÖVE 11.
-- That runtime used a different clip-space convention on canvases.
-- Adapt the vertex entry point, before 2D artwork and HUDs join the image.
-- Mirroring a completed image cannot correct a mixture of 2D and 3D draws.
local Compat = {}
local shaders = setmetatable({}, { __mode = "k" })
local installed
local uniform = "pokeportLegacyCanvasY"
local markers = { POKEPORT_NATIVE_CLIP_SPACE = true, POKEPORT_LEGACY_CLIP_SPACE_ADAPTED = true }

-- LÖVE accepts named defines and an array of preprocessor definitions.
-- Presence is what matters, including a value of 0 or false: #ifdef agrees.
local function nativeOptions(options)
  if type(options) ~= "table" then return false end
  local defines = rawget(options, "defines")
  if type(defines) ~= "table" then return false end
  for name in pairs(markers) do if rawget(defines, name) ~= nil then return true end end
  for key, value in next, defines do
    if type(key) == "number" and key >= 1 and key % 1 == 0 and type(value) == "string" then
      local name = value:match("^%s*([%a_][%w_]*)")
      if markers[name] then return true end
    end
  end
  return false
end

local function uncomment(source)
  local out, at = {}, 1
  while at <= #source do
    local start = source:find("/", at, true)
    if not start then out[#out + 1] = source:sub(at); break end
    out[#out + 1] = source:sub(at, start - 1)
    local pair = source:sub(start, start + 1)
    local finish
    if pair == "//" then
      finish = source:find("\n", start + 2, true) or (#source + 1)
    elseif pair == "/*" then
      local close = source:find("*/", start + 2, true)
      finish = close and close + 2 or (#source + 1)
    end
    if finish then
      out[#out + 1] = source:sub(start, finish - 1):gsub("[^\n]", " ")
      at = finish
    else
      out[#out + 1] = "/"; at = start + 1
    end
  end
  return table.concat(out)
end

local prefix = [[
#if !defined(POKEPORT_NATIVE_CLIP_SPACE) && !defined(POKEPORT_LEGACY_CLIP_SPACE_ADAPTED)
#define POKEPORT_LEGACY_CLIP_SPACE_ADAPTED 1
#define POKEPORT_LEGACY_CANVAS_Y_ACTIVE 1
#ifdef VERTEX
uniform float pokeportLegacyCanvasY;
mat4 pokeportLegacyMatrix(mat4 m) {
  m[0].y *= pokeportLegacyCanvasY;
  m[1].y *= pokeportLegacyCanvasY;
  m[2].y *= pokeportLegacyCanvasY;
  m[3].y *= pokeportLegacyCanvasY;
  return m;
}
// Global matrix names and the position() argument must expose the same
// legacy projection. LÖVE's generated main precedes this user source.
mat4 pokeportLegacyProjection() {
  return pokeportLegacyMatrix(ProjectionMatrix);
}
#undef ProjectionMatrix
#define ProjectionMatrix pokeportLegacyProjection()
#define position pokeportLegacyPosition
#endif
#endif
#line 1
]]
local suffix = [[

#if defined(VERTEX) && defined(POKEPORT_LEGACY_CANVAS_Y_ACTIVE)
#undef position
vec4 position(mat4 matrix, vec4 vertex) {
  vec4 clip = pokeportLegacyPosition(pokeportLegacyMatrix(matrix), vertex);
  clip.y *= pokeportLegacyCanvasY;
  return clip;
}
#endif
]]

-- Some producers already adapt their independent projection to current
-- canvas coordinates. Recognize only the complete forwarding wrapper, not
-- a sign in arbitrary projection arithmetic or a comment. Applying another
-- legacy transform to this wrapper reflects its world a second time.
local function nativeCanvasWrapper(code)
  for matrix, vertex, body in code:gmatch("vec4%s+position%s*%(%s*mat4%s+([%w_]+)%s*,%s*vec4%s+([%w_]+)%s*%)%s*(%b{})") do
    local compact = body:gsub("%s+", "")
    local clip, helper, m, v, rest = compact:match("^%{vec4([%w_]+)=([%w_]+)%(([%w_]+),([%w_]+)%)%;(.*)%}$")
    if clip and m == matrix and v == vertex and helper ~= "position"
        and rest == clip .. ".y=-" .. clip .. ".y;return" .. clip .. ";"
        and code:find("vec4%s+" .. helper .. "%s*%(") then return true end
  end
  return false
end

-- Modern low-level entry points and explicitly current-coordinate shaders
-- remain untouched. The high-level 2D matrix path cancels both reflections.
function Compat.source(source, options)
  if type(source) ~= "string" or nativeOptions(options) then return source, false end
  local code = uncomment(source)
  if code:find("#%s*define%s+POKEPORT_NATIVE_CLIP_SPACE%f[^%w_]")
      or code:find("#%s*define%s+POKEPORT_LEGACY_CLIP_SPACE_ADAPTED%f[^%w_]")
      or code:find("void%s+vertexmain%s*%(")
      or not code:find("vec4%s+position%s*%(")
      or nativeCanvasWrapper(code) then
    return source, false
  end
  return prefix .. source .. suffix, true
end

function Compat.install()
  local g = love and love.graphics
  if installed or not (love and love.getVersion and love.getVersion() >= 12
      and g and g.newShader and g.getShader and g.getCanvas) then return false end
  installed = true
  local newShader, validateShader = g.newShader, g.validateShader
  -- Engine-owned derivative programs already use the admitted source's clip
  -- convention. Re-analyzing their modified forwarding entry would adapt it
  -- twice. Keep the exact preceding constructor, without injecting a macro
  -- which could change the producer's preprocessor branches.
  Compat.compileNative = newShader
  local setShader, setCanvas, pop = g.setShader, g.setCanvas, g.pop

  local function sync(shader)
    if shader and shaders[shader] then
      local y = g.getCanvas() and -1 or 1
      if shaders[shader] ~= y then shader:send(uniform, y); shaders[shader] = y end
    end
  end
  local function source(arg, preserve)
    -- Keep file names, FileData and source strings intact for an explicitly
    -- native compile. No redundant file read, comment scan or source copy.
    if preserve then return arg, false end
    local text = arg
    if type(arg) == "string" and not arg:find("\n", 1, true) then
      local fs = love.filesystem
      if fs and fs.getInfo and fs.getInfo(arg, "file") then text = fs.read(arg) end
    elseif type(arg) == "userdata" and arg.typeOf and arg:typeOf("FileData") then
      text = arg:getString()
    end
    local adapted, changed = Compat.source(text)
    return changed and adapted or arg, changed
  end
  g.newShader = function(a, b, c)
    local changed, changed2
    local preserve = nativeOptions(type(b) == "table" and b or c)
    a, changed = source(a, preserve); b, changed2 = source(b, preserve)
    local shader = newShader(a, b, c)
    if (changed or changed2) and shader:hasUniform(uniform) then
      shaders[shader] = true
      sync(shader)
    end
    return shader
  end
  if validateShader then
    g.validateShader = function(es, a, b, c)
      local preserve = nativeOptions(type(b) == "table" and b or c)
      a = source(a, preserve); b = source(b, preserve)
      return validateShader(es, a, b, c)
    end
  end
  g.setShader = function(...)
    setShader(...)
    sync(g.getShader())
  end
  g.setCanvas = function(...)
    setCanvas(...)
    sync(g.getShader())
  end
  g.pop = function(...)
    pop(...)
    sync(g.getShader())
  end
  return true
end

return Compat
