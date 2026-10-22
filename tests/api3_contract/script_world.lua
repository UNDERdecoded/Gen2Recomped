local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_world%.lua$")
  local f = dofile(codeRoot .. "/world_edits.lua").fixture(root, backend, version, "script_world")
  f.loader.game = f.game
  f.ow.runner.update = function() end
  if f.field then
    function f.field.lock(token)
      f.field._locks[token] = true
    end
    function f.field.unlock(token)
      f.field._locks[token] = nil
    end
  end
  if f.gen == 1 then
    local native = f.ow.setMap
    function f.ow:setMap(...)
      local old = self.map
      native(self, ...)
      self.map = require("src.world.Map").new(old.def, old.tileset)
      self.map.renderer = old.renderer
      self.runner = require("src.script.ScriptRunner").new(f.game, self)
    end
  end
  function f:tick()
    if backend == "gen1" then
      self.loader.hooks:call("core.update", function() end, self.game, 1 / 60)
    else
      self.loader.hooks:call("input.step", function()
        self.ow.runner:update()
      end, self.game, 1 / 60)
    end
  end
  function f:drain()
    for _ = 1, 100 do
      if self.exports.result().done > 0 then
        return
      end
      self:tick()
    end
    error("world edit script did not finish")
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  assert(f.exports.queue({
    { "hide_object", f.home, "NPC" },
    { "show_object", f.home, "NPC" },
    { "replace_block", 0, 0, 8 },
    { "wait", 1 },
    { "set_flag", "mod:after" },
  }))
  f:drain()
  assert(f.exports.result().success == true and f.exports.get("mod:after") == true)
  assert(f.visible.NPC == true and f.exports.read(f.home, 0, 0) == 8)
  local report =
    { events = f.exports.result().events, visible = f.visible.NPC, block = f.exports.read(f.home, 0, 0) }
  f = M.fixture(root, backend, version)
  local value, why = f.exports.queue({ { "hide_object", f.home, "NPC" }, { "replace_block", 99, 0, 8 } })
  assert(value == nil and type(why) == "string" and f.visible.NPC and #f.exports.result().events == 0)
  report.preflight = true
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
