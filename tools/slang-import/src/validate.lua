function love.errorhandler(message)
  io.stderr:write(tostring(message) .. "\n")
  return function()
    return 1
  end
end
function love.load()
  local ok, why = pcall(function()
    local Graph, Json = require("ShaderGraph"), require("Json")
    local raw = Json.decode(assert(love.filesystem.read("graph.json")))
    local spec = assert(Graph.validate(raw))
    local values = {}
    for _, p in ipairs(raw.parameters) do
      values[p.id] = p.default
    end
    local graph, err = Graph.new(spec, function(name, limit)
      local info = assert(love.filesystem.getInfo(name))
      assert(info.size <= limit, "oversized graph resource")
      return assert(love.filesystem.read(name))
    end, love.graphics, values, love.filesystem.newFileData)
    assert(graph, err)
    graph:release()
    print("GL+GLES graph validation and native GPU readback PASS")
  end)
  if not ok then
    io.stderr:write(tostring(why) .. "\n")
  end
  love.event.quit(ok and 0 or 1)
end
