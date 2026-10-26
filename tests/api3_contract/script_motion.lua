local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_motion%.lua$")
  local f = dofile(codeRoot .. "/npcs.lua").fixture(root, backend, version, "script_motion")
  f.loader.game = f.game
  f.ow.runner.update = function() end
  function f.ow:npcByIndex(id)
    return id == 1 and f.imported
  end
  function f.ow:objectEntity(id)
    return id == 0 and f.player or id == 1 and f.imported
  end
  if f.field then
    function f.field.lock(token)
      f.field._locks[token] = true
    end
    function f.field.unlock(token)
      f.field._locks[token] = nil
    end
  end
  if backend == "gen1" and f.gen == 2 then
    function f.ow:beginMovement(id, bytes, callback)
      local dir = ({ [0x0C] = "down", [0x0D] = "up", [0x0E] = "left", [0x0F] = "right" })[bytes[1]]
      return f:begin(id == 0 and f.player or f.imported, "move", assert(dir), #bytes - 1, callback)
    end
    function f.ow:moveObject(id, x, y)
      local actor = assert(self:objectEntity(id))
      actor.cellX, actor.cellY = x, y
    end
  elseif backend == "gen1" and f.gen == 3 then
    local objects = require("src.core.game3.objects")
    objects._defs = { f.imported.def }
    objects.find = function(id)
      return id == 0xFF and f.player or f.byId[id]
    end
    objects.setObjectXY = function(id, x, y)
      local actor = assert(objects.find(id))
      actor.cellX, actor.cellY = x, y
    end
    objects.applyMovement = function(id, bytes, callback)
      local dir = ({ [0x10] = "down", [0x11] = "up", [0x12] = "left", [0x13] = "right" })[bytes[1]]
      return f:begin(assert(objects.find(id)), "move", assert(dir), #bytes - 1, callback)
    end
    local collision = require("src.core.game3.collision")
    collision.inBounds = function(x, y)
      return x >= 0 and y >= 0 and x < 8 and y < 8
    end
    collision.isWalkable = function()
      return true
    end
  end
  function f:tick()
    local hook = backend == "gen1" and "core.update" or "input.step"
    self.loader.hooks:call(hook, function()
      if backend == "gen2" then
        self.ow.runner:update()
      end
    end, self.game, 1 / 60)
  end
  function f:drain()
    for _ = 1, 100 do
      if self.exports.result().done > 0 then
        return
      end
      if self.pending and self.pending.actor.moving then
        self:complete()
      end
      self:tick()
    end
    error("movement script did not finish")
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  assert(f.exports.queue({
    { "face_player_dir", "up" },
    { "move_player", "left", 2 },
    { "place_npc", 1, 2, 2, "left" },
    { "move_npc", 1, "right", 2 },
    { "move_npc_to", 1, 4, 4 },
    { "face_object", 1, "up" },
    { "set_flag", "mod:after" },
  }))
  f:drain()
  assert(f.exports.result().success and f.exports.get("mod:after"))
  assert(
    f.player.cellX == 5
      and f.player.cellY == 7
      and f.imported.cellX == 4
      and f.imported.cellY == 4
      and f.imported.facing == "up"
  )
  local report = {
    player = { f.player.cellX, f.player.cellY },
    npc = { f.imported.cellX, f.imported.cellY, f.imported.facing },
    complete = true,
  }
  f.restoreRenderer()
  f = M.fixture(root, backend, version)
  local ok, why = f.exports.queue({ { "face_player_dir", "up" }, { "move_npc", 99, "left", 1 } })
  assert(ok == nil and type(why) == "string" and f.player.facing == "left")
  report.preflight = true
  f.restoreRenderer()
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
