local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/invalidate%.lua$")
  local f = dofile(codeRoot .. "/warp.lua").fixture(root, backend, version, "invalidate")
  local Runtime = require("src.mods.Runtime")
  f.reloads, f.loads = 0, {}
  function f:reload(id, why)
    self.reloads = self.reloads + 1
    self.loads[#self.loads + 1] = { id, why }
    if self.reloadError then
      error("reload probe", 0)
    end
    if self.ow.map.id == id then
      self.ow.map = { id = id, def = self.game.data.maps[id] }
    end
  end
  function f.ow:reloadMap(id, why)
    f:reload(id, why)
    Runtime.emit("map.reloaded", { mapId = id, reason = why })
  end
  function f.ow:reloadMapBadWarp()
    f:reload(self.map.id, "invalidate")
  end
  if backend == "gen1" and f.gen == 3 then
    function f.map.load(_, game, id, opts)
      assert(game == f.game and opts.x == f.player.cellX and opts.facing == f.player.facing)
      f:reload(id, "invalidate")
    end
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local report = { invalid = {} }
  for _, id in ipairs({ "", "NO_SUCH_MAP", "HOME\n", 42, false }) do
    local value, why = f.exports.request(id)
    assert(value == nil and why == "unknown map")
    assert(f.reloads == 0 and #f.exports.events() == 0)
    report.invalid[#report.invalid + 1] = why
  end
  local old = f.ow.map
  assert(f.exports.request(f.home))
  assert(f.reloads == 1 and f.ow.map ~= old)
  assert(f.player.cellX == 0 and f.player.cellY == 0 and f.player.facing == "left")
  assert(#f.exports.events() == 1 and f.exports.events()[1].mapId == f.home)
  report.active = f.exports.events()
  f = M.fixture(root, backend, version)
  assert(f.exports.request(f.dest))
  assert(f.ow.map.id == f.home)
  report.inactive = true -- Native inactive notification differences are not normalized.
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
