local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_travel%.lua$")
  local f = dofile(codeRoot .. "/script_motion.lua").fixture(root, backend, version, "script_travel")
  f.game.data.tilesets = f.game.data.tilesets or {}
  f.game.data.tilesets.FIX = f.tiles
  for _, def in pairs(f.game.data.maps) do
    if def.midLayout then
      def.midLayout.width, def.midLayout.height = def.width, def.height
    end
  end
  local dest = f.game.data.maps[f.dest]
  dest.objects = {
    {
      index = 1,
      localId = 1,
      name = "IMPORTED",
      sprite = "PROBE",
      x = 4,
      y = 4,
      movement = "STAY",
      range = "DOWN",
    },
  }
  local arrive = f.arrive
  function f:arrive(id)
    arrive(self, id)
    local def = self.game.data.maps[id or self.dest]
    if not def then
      return
    end
    if backend == "gen1" and f.gen == 2 then
      self.ow.map = require("src.world.gen2.Map").new(def, self.tiles)
    elseif not (backend == "gen1" and f.gen == 3) then
      self.ow.map = require("src.world.Map").new(def, self.tiles)
    end
    if backend == "gen1" and f.gen > 1 then
      self.ow.runner = {
        isRunning = function()
          return false
        end,
        update = function() end,
      }
    else
      self.ow.runner = require("src.script.ScriptRunner").new(self.game, self.ow)
    end
    self.imported.cellX, self.imported.cellY = 4, 4
    self.imported.def = def.objects[1]
    if self.byId then
      require("src.core.game3.objects")._defs = def.objects
    end
  end
  function f:drain()
    for _ = 1, 150 do
      if self.exports.result().done > 0 then
        return
      end
      if self.destination and self.ow.transitioning then
        self:arrive()
        self:completeWarp()
      end
      if self.pending and self.pending.actor.moving then
        self:complete()
      end
      self:tick()
    end
    error("travel script did not finish")
  end
  -- npc fixture's complete belongs to movement; preserve the warp seam separately.
  function f:completeWarp()
    self.busy, self.ow.transitioning = false, false
    if self.callback then
      self.callback()
    end
  end
  local dispatch = f.dispatch
  function f:dispatch(...)
    local movementComplete = self.complete
    self.complete = self.completeWarp
    local called, a, b = pcall(dispatch, self, ...)
    self.complete = movementComplete
    if not called then
      error(a, 0)
    end
    return a, b
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local ok, why = f.exports.queue({
    { "remember_outdoor", f.home, 1, 1 },
    { "warp", f.dest, 2, 2, "right" },
    { "move_player", "left" },
    { "move_npc", 1, "down" },
    { "face_object", 1, "up" },
    { "set_flag", "mod:after" },
  })
  assert(ok, why)
  assert(f.exports.result().done == 0)
  f:drain()
  assert(f.exports.result().success and f.exports.get("mod:after"))
  assert(f.ow.map.id == f.dest and f.player.cellX == 1 and f.player.cellY == 2 and f.imported.cellY == 5)
  local report = {
    map = f.ow.map.id,
    player = { f.player.cellX, f.player.cellY },
    npc = { f.imported.cellX, f.imported.cellY, f.imported.facing },
    complete = true,
  }
  f.restoreRenderer()
  f = M.fixture(root, backend, version)
  local value, reason = f.exports.queue({ { "face_player_dir", "up" }, { "warp", "UNKNOWN", 0, 0 } })
  assert(value == nil and type(reason) == "string" and f.player.facing == "left" and #f.trace == 0)
  report.preflight = true
  f.restoreRenderer()
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
