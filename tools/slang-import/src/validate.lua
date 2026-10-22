function love.load()
  local ok, why = pcall(function()
    local s = {}
    for i = 0, 3 do
      s[i + 1] = assert(love.filesystem.read(i .. ".glsl"))
    end
    for _, es in ipairs({ false, true }) do
      local i = es and 3 or 1
      local valid, message = love.graphics.validateShader(es, s[i], s[i + 1])
      assert(valid, (es and "GLES: " or "GL: ") .. tostring(message))
    end
    local renderer, version = love.graphics.getRendererInfo()
    local es = (renderer .. version):find("OpenGL ES", 1, true)
    local i = es and 3 or 1
    local shader = love.graphics.newShader(s[i], s[i + 1])
    local input = love.graphics.newCanvas(3, 5)
    local filter, wrap = love.filesystem.read("settings.txt"):match("(%S+) (%S+)")
    input:setFilter(filter, filter)
    assert(input:setWrap(wrap, wrap), "unsupported preset texture wrapping")
    local sizes = { 3, 5, 1 / 3, 1 / 5 }
    for _, name in ipairs({ "SourceSize", "OriginalSize", "OutputSize", "FinalViewportSize" }) do
      if shader:hasUniform("g2_" .. name) then
        shader:send("g2_" .. name, sizes)
      end
    end
    if shader:hasUniform("g2_Source") then
      shader:send("g2_Source", input)
    end
    for id, value in love.filesystem.read("params.txt"):gmatch("(%S+) (%S+)") do
      if shader:hasUniform(id) then
        shader:send(id, assert(tonumber(value)))
      end
    end
    local output = love.graphics.newCanvas(4, 4)
    love.graphics.setCanvas(output)
    love.graphics.setShader(shader)
    love.graphics.draw(input)
    love.graphics.setShader()
    love.graphics.setCanvas()
    assert(output:newImageData()) -- force completion/readback
    shader:release()
    input:release()
    output:release()
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
