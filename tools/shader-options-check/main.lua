-- Compare compatibility compilation with the runtime's unwrapped constructor.
io.stdout:setvbuf("no")
function love.errorhandler(err)
  io.stderr:write(debug.traceback(tostring(err), 2) .. "\n")
  return function() return 1 end
end
local root = assert(os.getenv("SHADER_OPTIONS_ENGINE"))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local g = love.graphics
local rawShader, rawValidate = g.newShader, g.validateShader
local Compat = require("src.render.LegacyShaderCompat")
assert(Compat.install())
local checks, comparisons = 0, 0
local function check(ok, why) checks = checks + 1; assert(ok, why) end
local vertex = [[#pragma language glsl3
#if !defined(POKEPORT_NATIVE_CLIP_SPACE) && !defined(POKEPORT_LEGACY_CLIP_SPACE_ADAPTED)
#error native option missing
#endif
vec4 position(mat4 m, vec4 p) {
  return vec4(p.x/32.-1.,1.-p.y/32.,0.,1.);
}
]]
local pixel = "vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc){return c;}"
local nativeVertex = "vec4 position(mat4 m,vec4 p){return vec4(p.x/32.-1.,1.-p.y/32.,0.,1.);}"
local legacyVertex = "vec4 position(mat4 m,vec4 p){return vec4(p.x/32.-1.,p.y/32.-1.,0.,1.);}"
local dimensions = { { 64, 64, 1 }, { 113, 79, 1 }, { 79, 113, 2 }, { 321, 179, 2 } }
local vertices = {}
for _, band in ipairs({ { 0, 1, 0 }, { 32, 0, 1 } }) do
  for _, p in ipairs({ { 0, 0 }, { 64, 0 }, { 64, 32 }, { 0, 0 }, { 64, 32 }, { 0, 32 } }) do
    vertices[#vertices + 1] = { p[1], p[2] + band[1], 0, 0, band[2], band[3], 0, 1 }
  end
end
local function read(canvas)
  return g.readbackTexture and g.readbackTexture(canvas) or canvas:newImageData()
end
local function render(mesh, shader, target)
  g.push("all"); g.setCanvas(target); g.origin(); g.setShader(shader)
  g.clear(0, 0, 0, 1); g.setColor(1, 1, 1, 1); g.setMeshCullMode("none")
  g.draw(mesh); g.setShader()
  g.setColor(0, 0, 1, 1); g.rectangle("fill", 4, 4, 20, 3); g.rectangle("fill", 4, 7, 3, 10)
  g.pop()
end
local function create(ctor, kind, source, opts)
  if kind == "split" then return ctor(pixel, source, opts) end
  return ctor(source, opts)
end
local function save(data, name)
  local out = os.getenv("SHADER_OPTIONS_OUT")
  if not out then return end
  local bytes = data:encode("png")
  local file = assert(io.open(out .. "/" .. name, "wb")); file:write(bytes:getString()); file:close(); bytes:release()
end
function love.load()
  local mesh = g.newMesh(vertices, "triangles", "static")
  local fixtures = {
    { "map", { defines = { POKEPORT_NATIVE_CLIP_SPACE = 1 } } },
    { "map-zero", { defines = { POKEPORT_NATIVE_CLIP_SPACE = 0 } } },
    { "map-false", { defines = { POKEPORT_NATIVE_CLIP_SPACE = false } } },
    { "array", { defines = { "POKEPORT_NATIVE_CLIP_SPACE" } } },
    { "already-adapted-option", { defines = { POKEPORT_LEGACY_CLIP_SPACE_ADAPTED = 1 } } },
    { "inherited-options", setmetatable({}, { __index = function(_, key)
      if key == "defines" then return { POKEPORT_NATIVE_CLIP_SPACE = 1 } end
    end }) },
  }
  for _, fixture in ipairs(fixtures) do
    local name, opts = fixture[1], fixture[2]
    for _, kind in ipairs({ "combined", "split", "file", "filedata" }) do
      local source = vertex
      if kind == "file" then
        check(love.filesystem.write("native-options.glsl", vertex), "own QA shader source written")
        source = "native-options.glsl"
      elseif kind == "filedata" then source = love.filesystem.newFileData(vertex, "native-options.glsl") end
      local baseline = create(rawShader, kind, source, opts)
      local shader = create(g.newShader, kind, source, opts)
      -- Compiler options are part of the shader's coordinate contract.
      check(not shader:hasUniform("pokeportLegacyCanvasY"), name .. "/" .. kind .. " native shader was rewritten")
      local ok, why
      if kind == "split" then ok, why = g.validateShader(false, pixel, source, opts)
      else ok, why = g.validateShader(false, source, opts) end
      check(ok, name .. "/" .. kind .. " validation: " .. tostring(why))
      local invalid = "#error test_shader_failure\n" .. vertex
      local expectedOk = rawValidate(false, invalid, opts)
      local actualOk = g.validateShader(false, invalid, opts)
      check(expectedOk == false and actualOk == expectedOk, "invalid native shader retains compiler failure")
      for _, size in ipairs(dimensions) do
        local a = g.newCanvas(size[1], size[2], { dpiscale = size[3], format = "rgba8" })
        local b = g.newCanvas(size[1], size[2], { dpiscale = size[3], format = "rgba8" })
        for _, wrapped in ipairs({ false, true }) do
          render(mesh, baseline, wrapped and { a } or a)
          render(mesh, shader, wrapped and { b } or b)
          local expected, actual = read(a), read(b)
          local r, green, blue = expected:getPixel(expected:getWidth() - 2, math.floor(expected:getHeight() / 4))
          check(r == 1 and green == 0 and blue == 0, name .. "/" .. kind .. " independent reference is upright")
          check(actual:getString() == expected:getString(), name .. "/" .. kind .. " native RGBA changed")
          if name == "map" and kind == "combined" and not wrapped and size[1] == 79 then
            save(actual, "native-portrait.png"); save(expected, "reference-portrait.png")
          end
          comparisons = comparisons + 1
          expected:release(); actual:release()
        end
        a:release(); b:release()
      end
      baseline:release(); shader:release()
      if kind == "filedata" then source:release() end
    end
  end
  -- Legacy correction must remain active for unrelated or similarly named
  -- definitions. Its expected pixels come from the unwrapped native path.
  for _, fixture in ipairs({
    { "legacy-default", nil, legacyVertex },
    { "legacy-unrelated-value", { defines = { OTHER = "POKEPORT_NATIVE_CLIP_SPACE" } }, legacyVertex },
    { "legacy-map-prefix", { defines = { POKEPORT_NATIVE_CLIP_SPACE_EXTRA = 1 } }, legacyVertex },
    { "legacy-array-prefix", { defines = { "POKEPORT_NATIVE_CLIP_SPACE_EXTRA" } }, legacyVertex },
    { "legacy-source-prefix", nil, "#define POKEPORT_NATIVE_CLIP_SPACE_EXTRA 1\n" .. legacyVertex },
    { "matrix-2d", nil, "vec4 position(mat4 m,vec4 p){return m*p;}" },
  }) do
    local baseline = rawShader(fixture[1] == "matrix-2d" and fixture[3] or nativeVertex, fixture[2])
    local shader = g.newShader(fixture[3], fixture[2])
    for _, size in ipairs(dimensions) do
      local a = g.newCanvas(size[1], size[2], { dpiscale = size[3], format = "rgba8" })
      local b = g.newCanvas(size[1], size[2], { dpiscale = size[3], format = "rgba8" })
      for _, wrapped in ipairs({ false, true }) do
        render(mesh, baseline, wrapped and { a } or a); render(mesh, shader, wrapped and { b } or b)
        local expected, actual = read(a), read(b)
        check(actual:getString() == expected:getString(), fixture[1] .. " legacy/matrix RGBA changed")
        comparisons = comparisons + 1; expected:release(); actual:release()
      end
      a:release(); b:release()
    end
    baseline:release(); shader:release()
  end
  mesh:release()
  print(("PASS shader options GPU: %d checks, %d exact RGBA pairs, %s"):format(checks, comparisons, g.getRendererInfo()))
  love.event.quit(0)
end
