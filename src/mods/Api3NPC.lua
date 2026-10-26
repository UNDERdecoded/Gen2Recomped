-- Public API-3 NPC handles. Engine objects never cross the handle boundary.
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Edits = require("src.mods.Api3WorldEdits")
local Collision = require("src.world.Collision")
local copy = require("src.mods.Merge").deepCopy
local N = {}
local services = setmetatable({}, { __mode = "k" })
local observers = setmetatable({}, { __mode = "k" })
local moves = {}
local dirs = { up = true, down = true, left = true, right = true }
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
local function integer(n, minimum, maximum)
  return type(n) == "number"
    and n == n
    and n >= (minimum or 0)
    and n < math.huge
    and n % 1 == 0
    and (not maximum or n <= maximum)
end
local function message(value)
  local ok, text = pcall(tostring, value)
  return ok and text or "unprintable error"
end
local function identifier(s)
  return type(s) == "string" and #s > 0 and #s <= 256 and not s:find("%c")
end
local function reference(v)
  return identifier(v) or integer(v)
end
-- Bounded data-only copy, including extra generation-native definition fields.
local function definition(value)
  local visiting, nodes, bytes = {}, 0, 0
  local function clone(v, depth)
    nodes = nodes + 1
    if nodes > 4096 or depth > 16 then
      error("NPC definition too large", 0)
    end
    local t = type(v)
    if t == "string" then
      bytes = bytes + #v
      if #v > 4096 or bytes > 65536 then
        error("NPC definition too large", 0)
      end
      return v
    elseif t == "number" then
      if v ~= v or v == math.huge or v == -math.huge then
        error("invalid NPC definition", 0)
      end
      return v
    elseif t == "nil" or t == "boolean" then
      return v
    elseif t ~= "table" or getmetatable(v) ~= nil or visiting[v] then
      error("invalid NPC definition", 0)
    end
    visiting[v] = true
    local out, count = {}, 0
    for k, item in pairs(v) do
      count = count + 1
      if count > 256 or type(k) ~= "string" and not integer(k) then
        error("invalid NPC definition", 0)
      end
      out[clone(k, depth + 1)] = clone(item, depth + 1)
    end
    visiting[v] = nil
    return out
  end
  if type(value) ~= "table" then
    return nil, "invalid NPC definition"
  end
  local ok, result = pcall(clone, value, 0)
  if not ok then
    return nil, result
  end
  if not integer(result.x, 0, 1000000) or not integer(result.y, 0, 1000000) then
    return nil, "invalid NPC coordinates"
  end
  for _, key in ipairs({ "name", "sprite" }) do
    if result[key] ~= nil and not identifier(result[key]) then
      return nil, "invalid NPC " .. key
    end
  end
  if result.facing ~= nil and not dirs[result.facing] then
    return nil, "invalid NPC facing"
  end
  return result
end
local function removeFrom(list, predicate)
  for i = #(list or {}), 1, -1 do
    if predicate(list[i]) then
      table.remove(list, i)
    end
  end
end
local function retire(move)
  move.done = true
  moves[move] = nil
  move.callback = nil
  local removed = false
  removeFrom(move.world.scriptMoves, function(entry)
    if move.entries[entry] then
      removed = true
      return true
    end
  end)
  if removed then
    local foreign = false
    for _, entry in ipairs(move.world.scriptMoves or {}) do
      if entry.entity == move.actor then
        foreign = true
      end
    end
    if not foreign then
      move.actor.moving, move.actor.marching = false, false
      move.actor.targetX, move.actor.targetY = nil, nil
      move.actor.px, move.actor.py = move.actor.cellX * 16, move.actor.cellY * 16
    end
  end
end
local function removeSpawn(token)
  -- Scoped by exact native record identity, even after Game/provider changes.
  local rows = token.data.maps and token.data.maps[token.mapId]
  local removed = false
  removeFrom(rows and rows.objects, function(row)
    if row == token.record then
      removed = true
      return true
    end
  end)
  local function owned(actor)
    return actor
      and (
        actor == token.actor
        or actor.def == token.record
        or removed and actor.id == token.mapId .. "_obj_" .. tostring(token.record.index)
      )
  end
  removeFrom(token.world.npcs, owned)
  removeFrom(token.world.entities, owned)
  removeFrom(token.world.ghosts, function(g)
    return owned(g.npc)
  end)
  for id, actor in pairs(token.world.npcPool or {}) do
    if owned(actor) then
      token.world.npcPool[id] = nil
    end
  end
end
function N.cancelAll(loader, owner)
  for service in pairs(services) do
    if (not loader or loader == service.loader) and (not owner or owner == service.owner) then
      service.closed = true
      for move in pairs(moves) do
        if move.service == service then
          retire(move)
        end
      end
      for _, token in ipairs(service.spawned) do
        removeSpawn(token)
      end
      service.spawned = {}
      services[service] = nil
    end
  end
end
local function inspect(loader)
  for move in pairs(moves) do
    if move.service.loader == loader then
      local ok, valid = pcall(move.valid)
      if not ok or not valid then
        retire(move)
      end
    end
  end
end
local function observe(loader)
  if observers[loader] and observers[loader][1] == loader.hooks then
    return
  end
  observers[loader] = setmetatable({ loader.hooks }, { __mode = "v" })
  loader.hooks:wrap("input.step", function(nextFn, ...)
    if next(moves) == nil then
      return nextFn(...)
    end
    inspect(loader)
    local result = pack(pcall(nextFn, ...))
    inspect(loader)
    if not result[1] then
      error(result[2], 0)
    end
    return unpack(result, 2, result.n)
  end, math.huge, "engine:api3_npc")
  for _, event in ipairs({ "map.exited", "map.entered" }) do
    loader.events:on(event, function()
      for move in pairs(moves) do
        if move.service.loader == loader then
          retire(move)
        end
      end
    end, math.huge, "engine:api3_npc")
  end
end
function N.new(loader, owner, gen, current, native, licensed, req)
  local service = { loader = loader, owner = owner, spawned = {} }
  services[service] = true
  observe(loader)
  local function alive()
    return not service.closed and licensed()
  end
  local function resolveGame()
    if not alive() then
      return nil, nil, "world facade is retired"
    end
    local game = current()
    if not game then
      return nil, nil, "no game"
    end
    local ow = native(game):overworld()
    if not ow then
      return nil, nil, "no overworld"
    end
    return game, ow
  end
  local function mapId(game, id)
    if gen == 3 and not (game.data.maps or {})[id] then
      local prefix = ({ ruby = "RU_", sapphire = "SA_", emerald = "EM_" })[Version.get()] or "FR_"
      if (game.data.maps or {})[prefix .. id] then
        return prefix .. id
      end
    end
    return id
  end
  local function actorAt(ow, id, ref)
    local function matches(actor)
      local def = actor.def or {}
      return actor.id == ref or def.index == ref or def.name == ref
    end
    if ow.map and ow.map.id == id then
      for _, actor in ipairs(ow.npcs or {}) do
        if matches(actor) then
          return actor, ow.map, ow.cast or ow.entities
        end
      end
      return nil, "no such object: " .. tostring(ref)
    end
    for _, g in ipairs(ow.ghosts or {}) do
      local actor = g.npc
      local map = g.map
      if map and map.id == id and actor and matches(actor) then
        local peers = g.nb and g.nb.cast or g.peers
        if not peers then
          peers = {}
          for _, sibling in ipairs(ow.ghosts) do
            if sibling.map == map then
              peers[#peers + 1] = sibling.npc
            end
          end
        end
        return actor, map, peers, true
      end
    end
    return nil, "map is not live"
  end
  local function sprite(game, id)
    return game.data and game.data.sprites and game.data.sprites[id]
  end
  local function queue(game, ow, actor, valid, name, a, b, callback)
    local hooks, events = Runtime.hooks, Runtime.events
    local move = { service = service, world = ow, actor = actor, entries = {}, callback = callback }
    local save, data, stack, map, version, fastWorld =
      game.save, game.data, game.stack, ow.map, Version.get(), game.overworld
    function move.valid()
      return alive()
        and current() == game
        and game.save == save
        and game.data == data
        and game.stack == stack
        and game.overworld == fastWorld
        and ow.map == map
        and Version.get() == version
        and Runtime.hooks == hooks
        and Runtime.events == events
        and valid()
    end
    local accepted, deferred
    local function finish(...)
      if move.done then
        return
      end
      if accepted == nil then
        if not deferred then
          deferred = pack(...)
        end
        return
      end
      local checked, valid = pcall(move.valid)
      local fn = accepted and checked and valid and move.callback
      retire(move)
      if not fn then
        return
      end
      local previous = Runtime.currentMod
      Runtime.currentMod = owner
      local ok, why = pcall(fn, ...)
      Runtime.currentMod = previous
      if not ok then
        Runtime.reportError(owner, "NPC movement callback failed: " .. message(why))
      end
    end
    local before = {}
    for _, entry in ipairs(ow.scriptMoves or {}) do
      before[entry] = true
    end
    moves[move] = true
    local called, result, detail
    if name == "scriptMove" then
      called, result, detail = pcall(ow.scriptMove, ow, actor, a, b or 1, finish)
    else
      called, result, detail = pcall(ow.marchInPlace, ow, actor, finish)
    end
    for _, entry in ipairs(ow.scriptMoves or {}) do
      if not before[entry] and entry.entity == actor then
        move.entries[entry] = true
      end
    end
    accepted = called and result ~= false and not (result == nil and detail ~= nil)
    if accepted then
      local checked, valid = pcall(move.valid)
      accepted = checked and valid and not move.done
    end
    if not accepted then
      retire(move)
      return nil,
        called and (detail or "NPC movement failed") or "world operation failed: " .. message(result)
    end
    local drain = deferred and function()
      finish(unpack(deferred, 1, deferred.n))
    end
    return true, nil, drain
  end
  local function handle(game, ow, id, ref)
    local actor, map = actorAt(ow, id, ref)
    if not actor then
      return nil, map
    end
    local publicId = actor.id
    if not identifier(publicId) then
      return nil, "NPC identity unavailable"
    end
    local save, data, version, fastWorld = game.save, game.data, Version.get(), game.overworld
    local function live()
      if
        not alive()
        or current() ~= game
        or game.save ~= save
        or game.data ~= data
        or game.overworld ~= fastWorld
        or Version.get() ~= version
        or native(game):overworld() ~= ow
      then
        return
      end
      local found, activeMap, peers, ghost = actorAt(ow, id, publicId)
      if found ~= actor or activeMap ~= map then
        return
      end
      return actor, activeMap, peers, ghost
    end
    local out = { id = publicId }
    local function invoke(name, a, b, c)
      if not alive() then
        return nil, "world facade is retired"
      end
      local npc, onMap, peers, ghost = live()
      if not npc then
        return nil, "NPC handle is stale"
      end
      if name == "position" then
        return npc.cellX, npc.cellY
      end
      if name == "isMoving" then
        return not not npc.moving
      end
      if name == "canStep" or name == "stepNow" or name == "face" or name == "scriptMove" then
        if not dirs[a] then
          return nil, "invalid direction"
        end
      end
      if name == "canStep" then
        return not not Collision.canMove(onMap, peers or {}, npc, a)
      end
      if
        name == "scriptMove" and (b ~= nil and not integer(b, 1, 1024) or c ~= nil and type(c) ~= "function")
      then
        return nil, "invalid movement"
      end
      if name == "marchInPlace" and a ~= nil and type(a) ~= "function" then
        return nil, "invalid callback"
      end
      if
        name == "placeAt"
        and (not integer(a, 0, 1000000) or not integer(b, 0, 1000000) or c ~= nil and not dirs[c])
      then
        return nil, "invalid coordinates"
      end
      if name == "setPassable" and type(a) ~= "boolean" then
        return nil, "invalid passability"
      end
      if name == "setAppearance" and not identifier(a) then
        return nil, "invalid sprite id"
      end
      local ok, why = Edits.ready(game, ow)
      if not ok then
        return nil, why
      end
      if ghost and (name == "scriptMove" or name == "marchInPlace") then
        return nil, "movement tracks require the active map"
      end
      local drain
      local value, detail = Edits.run(game, function()
        if name == "scriptMove" or name == "marchInPlace" then
          local value, why
          local callback = a
          if name == "scriptMove" then
            callback = c
          end
          value, why, drain = queue(game, ow, npc, live, name, a, b, callback)
          return value, why
        elseif name == "face" then
          npc.facing = a
        elseif name == "stepNow" then
          if npc.moving then
            return nil, "already moving"
          end
          npc.facing = a
          npc.targetX, npc.targetY = Collision.target(npc.cellX, npc.cellY, a)
          npc.moving, npc.progress = true, 0
        elseif name == "placeAt" then
          npc.moving, npc.marching, npc.progress = false, false, 0
          npc.targetX, npc.targetY = nil, nil
          npc.cellX, npc.cellY, npc.px, npc.py = a, b, a * 16, b * 16
          if c then
            npc.facing = c
          end
        elseif name == "setPassable" then
          npc.passable = a
        elseif name == "setAppearance" then
          if not sprite(game, a) then
            return nil, "unknown sprite: " .. a
          end
          local proxy = { id = npc.id, def = copy(npc.def) }
          proxy.def.sprite = a
          proxy.def.graphicsId, proxy.def.graphics, proxy.def.graphicsVar, proxy.def.varSprite =
            nil, nil, nil, nil
          req("src.world.NPC").refreshSprite(proxy, game.data)
          npc.def, npc.sprite, npc.appearance = proxy.def, proxy.sprite, a
          npc.big = proxy.sprite and proxy.sprite.big or false
        end
        return true
      end)
      if drain then
        drain()
      end
      return value, detail
    end
    for _, name in ipairs({
      "position",
      "isMoving",
      "canStep",
      "scriptMove",
      "marchInPlace",
      "face",
      "stepNow",
      "placeAt",
      "setPassable",
      "setAppearance",
    }) do
      local method = name
      out[method] = function(_, ...)
        local previous = Runtime.currentMod
        Runtime.currentMod = nil
        local result = pack(pcall(invoke, method, ...))
        Runtime.currentMod = previous
        if not result[1] then
          return nil, "world operation failed: " .. message(result[2])
        end
        return unpack(result, 2, result.n)
      end
    end
    return out
  end
  return function(name, a, b)
    local game, ow, why = resolveGame()
    if not game then
      return nil, why
    end
    if name == "npc" then
      if not identifier(a) or not reference(b) then
        return nil, "invalid NPC reference"
      end
      return handle(game, ow, mapId(game, a), b)
    end
    local ok, reason = Edits.ready(game, ow)
    if not ok then
      return nil, reason
    end
    return Edits.run(game, function()
      if name == "spawnNpc" then
        if not identifier(a) or type(b) ~= "table" then
          return nil, "invalid NPC definition"
        end
        local id = mapId(game, a)
        local mapDef = game.data.maps and game.data.maps[id]
        if not mapDef then
          return nil, "unknown map: " .. a
        end
        local row, err = definition(b)
        if not row then
          return nil, err
        end
        if row.sprite and not sprite(game, row.sprite) then
          return nil, "unknown sprite: " .. row.sprite
        end
        local before = {}
        for _, item in ipairs(mapDef.objects or {}) do
          before[item] = true
        end
        local called, value, detail = pcall(native(game).spawnNpc, native(game), id, row)
        for _, item in ipairs(mapDef.objects or {}) do
          if not before[item] and item.runtime and item.owner == owner then
            local publicId = id .. "_obj_" .. tostring(item.index)
            local actor = actorAt(ow, id, publicId)
            local token = { data = game.data, world = ow, mapId = id, record = item, actor = actor }
            if not called or not value then
              removeSpawn(token)
            else
              service.spawned[#service.spawned + 1] = token
            end
          end
        end
        if not called then
          return nil, "world operation failed: " .. message(value)
        end
        return value, detail
      end
      if not reference(a) or gen == 3 and not identifier(a) then
        return nil, "invalid NPC id"
      end
      local value, err = native(game):removeNpc(a)
      if value then
        for i = #service.spawned, 1, -1 do
          local token = service.spawned[i]
          if token.mapId .. "_obj_" .. tostring(token.record.index) == a then
            table.remove(service.spawned, i)
          end
        end
      end
      return value, err
    end)
  end
end
return N
