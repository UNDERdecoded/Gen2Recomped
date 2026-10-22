-- Real loaders/native public adapters with native actor/map/timing seams.
local M = {}
local unpack = table.unpack or unpack
function M.fixture(root, backend, version, modId)
  local codeRoot = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)/npcs%.lua$")
  local f = dofile(codeRoot .. "/warp.lua").fixture(root, backend, version, modId or "npcs")
  local Runtime = require("src.mods.Runtime")
  love = love or require("tests.love_stub")
  -- Render construction has no bearing on the public state contract.
  local Renderer = require("src.render.SpriteRenderer")
  local savedRenderer = Renderer.new
  Renderer.new = function(def)
    return { def = def, big = false }
  end
  f.restoreRenderer = function()
    Renderer.new = savedRenderer
  end
  local game, ow = f.game, f.ow
  game.data.sprites = {
    PROBE = { image = "fixture.png", frames = 6, walker = true },
    ALT = { image = "alt.png", frames = 6, walker = true },
  }
  game.data.gen2Sprites = game.data.sprites
  ow.game, ow.sprites = game, game.data.sprites
  local tiles = {
    blocks = { [2] = {} },
    walkable = { 0 },
    collision = { [2] = { 0, 0, 0, 0 } },
    blockCells = f.gen == 3 and 1 or 2,
    blockTiles = f.gen == 3 and 2 or 4,
  }
  f.tiles = tiles
  for i = 1, 16 do
    tiles.blocks[2][i] = 0
  end
  if not (backend == "gen1" and f.gen == 2) then
    tiles.collision = nil
  end
  for _, id in ipairs({ f.home, f.dest }) do
    local def = game.data.maps[id]
    def.width, def.height, def.objects, def.blocks = 8, 8, {}, {}
    for i = 1, 64 do
      def.blocks[i] = 1
    end
  end
  local base = {
    index = 1,
    localId = 1,
    name = "IMPORTED",
    sprite = "PROBE",
    x = 6,
    y = 6,
    movement = "STAY",
    range = "DOWN",
  }
  game.data.maps[f.home].objects = { base }
  if backend == "gen1" and f.gen == 2 then
    ow.map = require("src.world.gen2.Map").new(game.data.maps[f.home], tiles)
  elseif not (backend == "gen1" and f.gen == 3) then
    ow.map = require("src.world.Map").new(game.data.maps[f.home], tiles)
  end
  ow.npcs, ow.entities, ow.npcPool = {}, { f.player }, {}
  f.player.cellX, f.player.cellY = 7, 7
  function f:make(id, row)
    local actor
    if backend == "gen1" and self.gen == 2 then
      actor = require("src.world.gen2.Npc").new(id, row, game.data.sprites[row.sprite])
    elseif backend == "gen1" and self.gen == 3 then
      actor = require("src.core.game3.object_prepare").instance(row, { mapId = id })
      actor.id, actor.publicId = id .. "_obj_" .. row.index, id .. "_obj_" .. row.index
    else
      actor = require("src.world.NPC").new(game.data, id, row)
    end
    function actor:queueApiMoves(_, callback)
      f:begin(self, "march", nil, 1, callback)
      return true
    end
    return actor
  end
  f.imported = f:make(f.home, base)
  ow.npcs[1] = f.imported
  ow.entities[2] = f.imported
  ow.npcPool[f.imported.id] = f.imported
  function f:begin(actor, kind, dir, count, callback)
    self.pending = { actor = actor, kind = kind, dir = dir, count = count, callback = callback }
    self.busy = true
    actor.moving = true
    if backend == "gen2" or self.gen == 1 then
      local entry =
        { entity = actor, dir = dir, remaining = count, onDone = callback, inPlace = kind == "march" }
      ow.scriptMoves[#ow.scriptMoves + 1] = entry
    end
    if self.synchronous then
      self:complete("sync", nil, "tail")
    end
    if self.failMovement then
      return false, "movement refused"
    end
    return true
  end
  function ow:scriptMove(actor, dir, count, callback)
    return f:begin(actor, "move", dir, count, callback)
  end
  function ow:marchInPlace(actor, callback)
    return f:begin(actor, "march", nil, 1, callback)
  end
  function ow:beginMovement(objectId, bytes, callback)
    local actor
    for _, candidate in ipairs(self.npcs) do
      if candidate.def.index + 1 == objectId then
        actor = candidate
      end
    end
    local dir = ({ [0x0C] = "down", [0x0D] = "up", [0x0E] = "left", [0x0F] = "right" })[bytes[1]]
    return f:begin(assert(actor), "move", assert(dir), #bytes - 1, callback)
  end
  function ow:applySpritePalette(actor)
    f.paletteActor = actor
  end
  function f:complete(...)
    local pending = self.pending
    assert(pending, "no pending move")
    local actor = pending.actor
    if pending.kind == "move" then
      local delta = ({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } })[pending.dir]
      actor.cellX, actor.cellY =
        actor.cellX + delta[1] * pending.count, actor.cellY + delta[2] * pending.count
    end
    actor.moving, actor.marching = false, false
    actor.px, actor.py = actor.cellX * 16, actor.cellY * 16
    self.busy = false
    ow.scriptMoves = {}
    if pending.callback then
      pending.callback(...)
    end
  end
  function f:spawn(id, row, owner)
    local def = assert(game.data.maps[id])
    local index = 0
    for _, existing in ipairs(def.objects) do
      index = math.max(index, existing.index)
    end
    row.index, row.localId, row.runtime, row.owner = index + 1, index + 1, true, owner
    def.objects[#def.objects + 1] = row
    local publicId = id .. "_obj_" .. row.index
    if id == self.home then
      local actor = self:make(id, row)
      ow.npcs[#ow.npcs + 1] = actor
      ow.entities[#ow.entities + 1] = actor
      ow.npcPool[publicId] = actor
      if self.byId then
        self.byId[row.localId] = actor
        self.order[#self.order + 1] = row.localId
      end
    end
    return publicId
  end
  function ow:addRuntimeObject(id, row, owner)
    return f:spawn(id, row, owner)
  end
  function f:remove(id, owner)
    for _, def in pairs(game.data.maps) do
      for i, row in ipairs(def.objects or {}) do
        if row.runtime and def.id .. "_obj_" .. row.index == id then
          if row.owner ~= owner then
            return nil, "not owned by " .. tostring(owner)
          end
          table.remove(def.objects, i)
          for _, list in ipairs({ ow.npcs, ow.entities }) do
            for j = #list, 1, -1 do
              if list[j].id == id then
                table.remove(list, j)
              end
            end
          end
          ow.npcPool[id] = nil
          if self.byId then
            self.byId[row.localId] = nil
            for j = #self.order, 1, -1 do
              if self.order[j] == row.localId then
                table.remove(self.order, j)
              end
            end
          end
          return true
        end
      end
    end
    return nil, "no runtime object " .. tostring(id)
  end
  function ow:removeRuntimeObject(id, owner)
    return f:remove(id, owner)
  end
  if backend == "gen1" and f.gen == 3 then
    f.byId, f.order = { [1] = f.imported }, { 1 }
    package.loaded["src.core.game3.objects"] = {
      _byId = f.byId,
      _order = f.order,
      addRuntimeObject = function(id, row, owner)
        return f:spawn(id, row, owner)
      end,
      removeRuntimeObject = function(id, owner)
        return f:remove(id, owner)
      end,
      scriptFace = function(actor, dir)
        actor.facing = dir
      end,
      scriptStep = function(actor, dir)
        local delta = ({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } })[dir]
        actor.facing = dir
        actor.targetX = actor.cellX + delta[1]
        actor.targetY = actor.cellY + delta[2]
        actor.moving = true
      end,
      startTrack = function(id, actions, callback)
        local count = 0
        for _, action in ipairs(actions) do
          if action.kind == "step" then
            count = count + 1
          end
        end
        return f:begin(f.byId[id], count > 0 and "move" or "march", actions[1].dir, count, callback)
      end,
    }
    package.loaded["src.core.game3.collision"] = {
      canEnter = function()
        return true
      end,
      isWater = function()
        return false
      end,
    }
  end
  function f:update()
    return self.loader.hooks:call("input.step", function()
      return "updated", nil, "tail"
    end, game, 0)
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local ex = f.exports
  local report = { invalid = {}, actions = {} }
  local function refused(value, why)
    assert(value == nil and type(why) == "string" and #why > 0, tostring(why))
  end
  refused(ex.spawn("UNKNOWN", { x = 0, y = 0 }))
  refused(ex.spawn(f.home, { x = -1, y = 0 }))
  refused(ex.spawn(f.home, { x = 0.5, y = 0 }))
  refused(ex.npc(f.home, false))
  refused(ex.remove(false))
  assert(#f.game.data.maps[f.home].objects == 1 and #f.ow.npcs == 1)
  local definition = { name = "RUNTIME", sprite = "PROBE", x = 0, y = 0, movement = "STAY", range = "DOWN" }
  local id = assert(ex.spawn(f.home, definition))
  local handle = assert(ex.npc(f.home, id))
  assert(handle.id == id and ex.npc(f.home, "RUNTIME").id == id)
  definition.x, definition.sprite = 99, "changed"
  local actor = f.ow.npcPool[id]
  assert(actor.cellX == 0 and actor.def.sprite == "PROBE")
  for _, method in ipairs({ "scriptMove", "face", "stepNow", "canStep" }) do
    refused(handle[method](handle, "north"))
  end
  refused(handle:scriptMove("right", 0))
  refused(handle:scriptMove("right", 1025))
  refused(handle:scriptMove("right", 1, false))
  refused(handle:marchInPlace(false))
  refused(handle:placeAt(-1, 0))
  refused(handle:setPassable("yes"))
  refused(handle:setAppearance(""))
  assert(handle:face("right"))
  local allowed, blocked = handle:canStep("right")
  assert(allowed == true, tostring(allowed) .. ": " .. tostring(blocked))
  assert(handle:setPassable(true) and actor.passable == true)
  assert(handle:setAppearance("ALT"))
  assert(handle:position() == 0 and handle:isMoving() == false)
  assert(handle:stepNow("right"))
  assert(handle:isMoving() == true and actor.targetX == 1)
  refused(handle:stepNow("right"))
  assert(handle:placeAt(2, 2, "up"))
  assert(handle:isMoving() == false and actor.px == 32 and actor.py == 32)
  local x, y = handle:position()
  assert(x == 2 and y == 2)
  assert(handle:scriptMove("right", 2, ex.done))
  assert(ex.result().calls == 0)
  f:complete("done", nil, "tail")
  x, y = handle:position()
  assert(x == 4 and y == 2)
  assert(ex.result().calls == 1 and ex.result().args.n == 3 and ex.result().args.third == "tail")
  assert(handle:marchInPlace(ex.done))
  f:complete("march")
  x, y = handle:position()
  assert(x == 4 and y == 2 and ex.result().calls == 2)
  assert(handle:scriptMove("left"))
  f:complete()
  assert(handle:position() == 3 and ex.result().calls == 2)
  assert(handle:marchInPlace())
  f:complete()
  assert(handle:placeAt(4, 2))
  local imported = assert(ex.npc(f.home, "IMPORTED"))
  refused(ex.remove(imported.id))
  local other = f:spawn(f.home, { name = "OTHER", sprite = "PROBE", x = 5, y = 5 }, "other")
  refused(ex.remove(other))
  assert(ex.remove(id))
  refused(ex.npc(f.home, id))
  assert(ex.npc(f.home, other) and ex.npc(f.home, imported.id))
  report.actions = {
    x = x,
    y = y,
    passable = actor.passable,
    callbacks = ex.result().calls,
    definitionCopied = true,
    ownedRemoval = true,
  }
  report.invalid = true
  assert(#f.loader.errors == 0)
  f.restoreRenderer()
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
