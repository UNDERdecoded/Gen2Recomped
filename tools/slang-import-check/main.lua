-- Run after importing PROBE and WRAP from tools/slang-import/fixtures.
-- Optional LCD3X and ZFAST LCD imports are compared against independent CPU equations.
local root = love.filesystem.getSource():match("^(.*)/tools/slang%-import%-check$")
  or love.filesystem.getWorkingDirectory()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Presets = require("src.render.ShaderPresets")
local Json = require("src.link.Json")
local CacheFs = require("src.import.CacheFs")
local g = love.graphics
local checks, panels = 0, {}
local function check(v, why)
  checks = checks + 1
  assert(v, why)
end
local function near(a, b, why)
  check(math.abs(a - b) < 1.6 / 255, why .. (" (%.5f / %.5f)"):format(a, b))
end
local function pattern(x, y)
  return { (x * 11 + 7) / 255, (y * 17 + 13) / 255, ((x + y) * 7 + 3) / 255, y % 2 == 0 and 1 or 0.5 }
end
local function input(w, h, dpi)
  local data = love.image.newImageData(16, 12)
  for y = 0, 11 do
    for x = 0, 15 do
      data:setPixel(x, y, unpack(pattern(x, y)))
    end
  end
  local image = g.newImage(data)
  image:setFilter("nearest", "nearest")
  local canvas = g.newCanvas(w, h, { dpiscale = dpi })
  canvas:setFilter("nearest", "nearest")
  g.push("all")
  g.setCanvas(canvas)
  g.origin()
  g.setShader()
  g.setColor(1, 1, 1, 1)
  g.setBlendMode("replace", "premultiplied")
  g.draw(image, 0, 0, 0, w / 16, h / 12)
  g.pop()
  image:release()
  data:release()
  return canvas
end
local function oracle(name, x, y, pw, ph, gain)
  local u, v = (x + 0.5) / pw, (y + 0.5) / ph
  local c = pattern(math.floor(u * 16), math.floor(v * 12))
  if name == "PROBE" then
    return { c[1] * gain, 16 / 64, ph * 2 / 512, c[4] }
  end
  if name == "WRAP" then
    return { (pattern(0, 0)[1] + pattern(15, 0)[1]) / 2 }
  end
  if name == "LCD3X" then
    local ay, ax = v * 12 * 2 * math.pi, u * 16 * 2 * math.pi
    local yf = (16 + math.sin(ay)) / 17
    for i = 1, 3 do
      c[i] = c[i] * yf * (4 + math.sin(ax + math.pi / 2 - (i - 1) * 2 * math.pi / 3)) / 5
    end
    c[4] = 1
    return c
  end
  if name == "ZFAST LCD" then
    local dx, dy = math.abs(math.floor(u * 16) + 0.5 - u * 16), math.abs(math.floor(v * 12) + 0.5 - v * 12)
    local yy = math.max(dx, dy) ^ 2
    local weight = 1 - 14 * (yy ^ 2 - 2.7 * yy ^ 3)
    for i = 1, 3 do
      c[i] = c[i] * weight
      c[i] = c[i] * (0.6 + 0.4 * c[i])
    end
    c[4] = 1
    return c
  end
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
  local entries = {}
  for _, e in ipairs(p:list()) do
    if e.imported then
      entries[e.name] = e
    end
  end
  check(entries.PROBE and entries.WRAP, "import the PROBE and WRAP fixtures first")
  for _, name in ipairs({ "PROBE", "WRAP", "LCD3X", "ZFAST LCD" }) do
    local entry = entries[name]
    if entry then
      check(p:activate(entry.id), name .. " activation")
      -- Validate exactly the files loaded by the game for both shader dialects.
      for _, es in ipairs({ false, true }) do
        local fragment = fs.read("shader-presets/" .. (es and entry.esShader or entry.shader))
        local vertex = fs.read("shader-presets/" .. (es and entry.esVertex or entry.vertex))
        local ok, why = g.validateShader(es, fragment, vertex)
        check(ok, name .. " dialect: " .. tostring(why))
      end
      local gain = 0.5
      for _, dpi in ipairs({ 1, 2, 2.75 }) do
        -- Also exercise render-target replacement on resize.
        for _, w in ipairs({ 64, 80 }) do
          local h = w * 3 / 4
          local canvas = input(w, h, dpi)
          local inputFilter = canvas:getFilter()
          g.setColor(0.2, 0.3, 0.4, 0.6)
          local output = p:apply(canvas, w * dpi / 16)
          check(output ~= canvas and p:active(), name .. " processed")
          check(output:getWidth() == w and output:getDPIScale() == dpi, "output dimensions/DPI")
          check(p.importInput:getWidth() == 16 and p.importInput:getHeight() == 12, "native source grid")
          check(canvas:getFilter() == inputFilter, "input texture state unchanged")
          local r, green, b, a = g.getColor()
          near(r, 0.2, "red state")
          near(green, 0.3, "green state")
          near(b, 0.4, "blue state")
          near(a, 0.6, "alpha state")
          local data = output:newImageData()
          local pw, ph = data:getDimensions()
          for y = 0, ph - 1 do
            for x = 0, pw - 1 do
              local expected = oracle(name, x, y, pw, ph, gain)
              local actual = { data:getPixel(x, y) }
              local tx, ty = (x + 0.5) * 16 / pw, (y + 0.5) * 12 / ph
              -- Exact nearest-sampling ties can fall on either texel after varying interpolation.
              local tie = math.abs(tx - math.floor(tx + 0.5)) < 0.00001
                or math.abs(ty - math.floor(ty + 0.5)) < 0.00001
              if name == "WRAP" or not tie then
                for i, n in ipairs(expected) do
                  near(
                    actual[i],
                    n,
                    name .. " dpi=" .. dpi .. " w=" .. w .. " pixel " .. x .. "," .. y .. " channel " .. i
                  )
                end
              end
            end
          end
          if dpi == 1 and w == 64 then
            local preview = g.newImage(data)
            preview:setFilter("nearest", "nearest")
            panels[#panels + 1] = { name, preview }
          end
          data:release()
          if name == "PROBE" then
            local opts = {}
            check(p:setParameter(opts, "gain", 0.8), "parameter update")
            check(opts.shaderPresetParams[entry.id].gain > 0.79, "parameter persisted by public ID")
            gain = 0.8
          end
          canvas:release()
        end
      end
      p:off()
      check(p.importInput == nil, "private source released on OFF")
    end
  end
  -- A bad imported vertex must preserve the last working effect and saved choice.
  check(p:activate("builtin:warm"), "working fallback")
  local shader = p.shader
  local oldRead = fs.read
  fs.read = function(path)
    if path:find("-v.glsl", 1, true) then
      return "THIS IS NOT A VERTEX SHADER"
    end
    return oldRead(path)
  end
  local opts = { shaderPreset = "builtin:warm" }
  check(not p:select(opts, entries.PROBE.id), "invalid vertex rejected")
  check(p.shader == shader and opts.shaderPreset == "builtin:warm", "working effect and save preserved")
  p:off()
  local shot = os.getenv("SLANG_IMPORT_CHECK_SHOT")
  if shot then
    local sheet = g.newCanvas(640, 480)
    g.push("all")
    g.setCanvas(sheet)
    g.origin()
    g.setShader()
    g.clear(0.08, 0.08, 0.1, 1)
    g.setColor(1, 1, 1, 1)
    for i, panel in ipairs(panels) do
      local x, y = ((i - 1) % 2) * 320 + 16, math.floor((i - 1) / 2) * 240 + 12
      g.print(panel[1], x, y)
      g.draw(panel[2], x, y + 24, 0, 4, 4)
    end
    g.pop()
    local png = sheet:newImageData():encode("png")
    local f = assert(io.open(shot, "wb"))
    f:write(png:getString())
    f:close()
    sheet:release()
  end
  for _, panel in ipairs(panels) do
    panel[2]:release()
  end
  print(checks .. " GPU checks passed (slang import)")
  return true
end
function love.load()
  local ok, why = pcall(function()
    local directory = assert(os.getenv("SLANG_IMPORT_CHECK_DIR"))
    if directory == "imports" then
      -- Distribution LÖVE builds need not export the PhysFS FFI symbols.
      -- CI stages these generated fixtures in this test source, so the real
      -- virtual filesystem can read them without an external-directory mount.
      check(love.filesystem.getInfo("imports", "directory"), "staged fixtures present")
      check(run(), "staged fixture checks completed")
    else
      check(CacheFs.withMounted(directory, "imports", run), "fixture directory mounted")
    end
  end)
  if not ok then
    io.stderr:write(tostring(why) .. "\n")
  end
  love.event.quit(ok and 0 or 1)
end
function love.errorhandler(message)
  io.stderr:write(tostring(message) .. "\n")
  return function()
    return 1
  end
end
