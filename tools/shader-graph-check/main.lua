function love.errorhandler(message)
  io.stderr:write(tostring(message) .. "\n")
  return function()
    return 1
  end
end
local root = love.filesystem.getSource():match("^(.*)/tools/shader%-graph%-check$")
  or love.filesystem.getWorkingDirectory()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Presets = require("src.render.ShaderPresets")
local g = love.graphics
local checks = 0
local function check(v, why)
  checks = checks + 1
  assert(v, why)
end
local function near(a, b, why)
  check(math.abs(a - b) < 2 / 255, why .. " " .. a .. "/" .. b)
end
local function pattern(x, y)
  return (11 * x + 7) / 255, (17 * y + 13) / 255, 0.3, y % 2 == 0 and 1 or 0.5
end
local function run()
  local fs = {
    getDirectoryItems = function()
      return love.filesystem.getDirectoryItems("imports")
    end,
    getInfo = function(p)
      return love.filesystem.getInfo((p:gsub("^shader%-presets", "imports")))
    end,
    read = function(p)
      return love.filesystem.read((p:gsub("^shader%-presets", "imports")))
    end,
  }
  local p = Presets.new({ fs = fs })
  local entry
  for _, e in ipairs(p:list()) do
    if e.name == "GRAPH" then
      entry = e
    end
  end
  check(entry ~= nil, "GRAPH import required")
  check(p:activate(entry.id), "graph activated: " .. tostring(p.error))
  local data = love.image.newImageData(16, 12)
  for y = 0, 11 do
    for x = 0, 15 do
      data:setPixel(x, y, pattern(x, y))
    end
  end
  local image = g.newImage(data)
  image:setFilter("nearest", "nearest")
  local sentinel = g.newCanvas(10, 10)
  local sentinelShader = g.newShader("vec4 effect(vec4 c, Image t, vec2 uv,vec2 px){return Texel(t,uv)*c;}")
  for _, dpi in ipairs({ 1, 2, 2.75 }) do
    for _, factor in ipairs({ 1, 2 }) do
      local scale = 5 * factor * dpi
      local w, h = 80 * factor, 60 * factor
      local input = g.newCanvas(w, h, { dpiscale = dpi })
      input:setFilter("nearest", "nearest")
      input:setWrap("repeat", "repeat")
      g.push("all")
      g.setCanvas(input)
      g.origin()
      g.setShader()
      g.setBlendMode("replace", "premultiplied")
      g.setColor(1, 1, 1, 1)
      g.draw(image, 0, 0, 0, w / 16, h / 12)
      g.pop()
      g.setCanvas()
      for _, gain in ipairs({ 0.5, 0.8 }) do
        check(p:setParameter({}, "gain", gain), "parameter")
        g.setCanvas(sentinel)
        g.setShader(sentinelShader)
        g.setColor(0.4, 0.5, 0.6, 0.7)
        g.setScissor(1, 2, 3, 4)
        g.translate(2, 3)
        local before = g.getStackDepth()
        local output = p:apply(input, scale)
        check(output ~= input and p:active(), "graph survives")
        check(g.getCanvas() == sentinel, "canvas restored")
        check(g.getShader() == sentinelShader, "shader restored")
        check(g.getStackDepth() == before, "stack restored")
        local r, gg, b, a = g.getColor()
        near(r, 0.4, "color")
        local x, y = g.transformPoint(0, 0)
        near(x, 2, "transform x")
        near(y, 3, "transform y")
        local sx, sy, sw, sh = g.getScissor()
        check(sx == 1 and sy == 2 and sw == 3 and sh == 4, "scissor")
        g.setCanvas()
        g.setShader()
        g.setScissor()
        g.origin()
        g.setColor(1, 1, 1, 1)
        local pixels = output:newImageData()
        local pw, ph = pixels:getDimensions()
        check(pw == 16 * scale and ph == 12 * scale, "physical output")
        near(output:getDPIScale(), dpi, "DPI")
        check(p.graph.targets[1]:getWidth() == 16 and p.graph.targets[2]:getWidth() == 32, "per pass scale")
        check(p.graph.targets[3]:getWidth() == pw, "viewport scale")
        for py = 0, ph - 1 do
          for px = 0, pw - 1 do
            local u, v = (px + 0.5) / scale, (py + 0.5) / scale
            -- A pixel exactly on a nearest-sampling boundary can select either texel after GPU rounding.
            if
              math.abs(u - math.floor(u + 0.5)) > 0.00001 and math.abs(v - math.floor(v + 0.5)) > 0.00001
            then
              local pr, pg, pb, pa = pattern(math.floor((px + 0.5) / scale), math.floor((py + 0.5) / scale))
              local ar, ag, ab, aa = pixels:getPixel(px, py)
              -- RGBA8 intermediate passes quantize the first multiplication.
              near(
                ar,
                math.floor(pr * gain * 255 + 0.5) / 255 + pr * 0.25,
                ("source plus original dpi=%s factor=%s gain=%s px=%s py=%s"):format(
                  dpi,
                  factor,
                  gain,
                  px,
                  py
                )
              )
              near(ag, pg, "earlier pass, not source")
              near(ab, 128 / 255 / 2, "LUT and size semantics")
              near(aa, pa, "alpha")
            end
          end
        end
        pixels:release()
        check(p:apply(output, scale) == output, "feedback prevented")
        check(input:getFilter() == "nearest", "borrowed filter")
        check(input:getWrap() == "repeat", "borrowed wrap")
      end
      local targets = p.graph.targets
      p:apply(input, scale)
      check(p.graph.targets == targets, "reuse")
      input:release()
    end
  end
  -- Rejected GPU/decoder candidates preserve the current effect.
  local old = p.graph
  local original = fs.read
  fs.read = function(path)
    if path:match("%.glsl$") then
      return "invalid glsl"
    end
    return original(path)
  end
  check(not p:activate(entry.id), "bad candidate rejected")
  check(p.graph == old and p:active(), "working graph preserved")
  fs.read = original
  p:off()
  check(not p:active(), "OFF")
  image:release()
  data:release()
  sentinel:release()
  sentinelShader:release()
  print(
    "shader graph GPU PASS "
      .. checks
      .. " pixel/state checks | "
      .. table.concat({ g.getRendererInfo() }, " | ")
  )
end
function love.load()
  local ok, why = pcall(function()
    local directory = assert(os.getenv("SHADER_GRAPH_CHECK_DIR"))
    if directory == "imports" then
      assert(love.filesystem.getInfo("imports", "directory"), "staged fixtures present")
      run()
    else
      assert(
        require("src.import.CacheFs").withMounted(directory, "imports", function()
          run()
          return true
        end),
        "mount unavailable"
      )
    end
  end)
  if not ok then
    io.stderr:write(tostring(why) .. "\n")
  end
  love.event.quit(ok and 0 or 1)
end
