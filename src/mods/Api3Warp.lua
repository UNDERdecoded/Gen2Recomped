-- API-3 warp admission and callback lifetime over the native overworld path.
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Actions = require("src.world.WorldActions")
local W = {}
local contexts = setmetatable({}, { __mode = "k" })
local observers = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })
local dirs = { up = true, down = true, left = true, right = true }
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
local function integer(n)
  return type(n) == "number" and n == n and n >= 0 and n < math.huge and n % 1 == 0
end
local function retire(token)
  token.done = true
  token.callback = nil
  if pending[token.game] == token then
    pending[token.game] = nil
  end
end
function W.cancelAll(loader, owner)
  for candidate, context in pairs(contexts) do
    if not loader or candidate == loader then
      if owner then
        context.owners[owner] = nil
      else
        contexts[candidate] = nil
      end
    end
  end
  for _, token in pairs(pending) do
    if (not loader or token.loader == loader) and (not owner or token.owner == owner) then
      retire(token)
    end
  end
end
local function inspect(loader)
  for _, token in pairs(pending) do
    if token.loader == loader and not token.valid() then
      retire(token)
    end
  end
end
local function observe(loader)
  local old = observers[loader]
  if old and old[1] == loader.hooks then
    return
  end
  observers[loader] = setmetatable({ loader.hooks }, { __mode = "v" })
  -- Installed at facade creation, never spliced into a dispatching hook chain.
  loader.hooks:wrap("input.step", function(nextFn, ...)
    if next(pending) == nil then
      return nextFn(...)
    end
    inspect(loader)
    local result = pack(pcall(nextFn, ...))
    inspect(loader)
    if not result[1] then
      error(result[2], 0)
    end
    return unpack(result, 2, result.n)
  end, math.huge, "engine:api3_warp")
  for _, event in ipairs({ "map.entered", "map.exited" }) do
    local name = event
    loader.events:on(name, function(payload)
      for _, token in pairs(pending) do
        if token.loader == loader then
          if not token.valid() then
            retire(token)
          elseif name == "map.entered" then
            if token.entered or payload.mapId ~= token.destination then
              retire(token)
            else
              token.entered = true
            end
          elseif token.entered then
            retire(token)
          end
        end
      end
    end, math.huge, "engine:api3_warp")
  end
end
-- Pure destination validation shared by public warps and portable scripts.
function W.plan(game, ow, generation, mapId, x, y, facing)
  if type(mapId) ~= "string" or #mapId == 0 or #mapId > 256 or mapId:find("%c") then
    return nil, "invalid map id"
  end
  local maps = game.data and game.data.maps
  local destination = mapId
  if generation == 3 and maps and not maps[destination] then
    local prefix = ({ ruby = "RU_", sapphire = "SA_", emerald = "EM_" })[Version.get()] or "FR_"
    if maps[prefix .. destination] then
      destination = prefix .. destination
    end
  end
  local def = maps and maps[destination]
  if not def then
    return nil, "unknown map: " .. mapId
  end
  if not integer(x) or not integer(y) then
    return nil, "invalid coordinates"
  end
  local scale = generation == 3 and 1 or 2
  if not integer(def.width) or def.width == 0 or not integer(def.height) or def.height == 0 then
    return nil, "invalid map dimensions"
  end
  if x >= def.width * scale or y >= def.height * scale then
    return nil, "coordinates out of bounds"
  end
  if facing ~= nil and not dirs[facing] then
    return nil, "invalid facing"
  end
  return {
    mapId = destination,
    x = x,
    y = y,
    facing = facing or (generation ~= 1 and ow.player.facing) or "down",
    def = def,
  }
end
function W.new(loader, owner, generation, current, native)
  local context = contexts[loader]
  if not context then
    context = { owners = {} }
    contexts[loader] = context
  end
  local lease = {}
  context.owners[owner] = lease
  local function licensed()
    return contexts[loader] == context and context.owners[owner] == lease
  end
  observe(loader)
  local function warp(mapId, x, y, facing, options)
    if not licensed() then
      return nil, "warp facade is retired"
    end
    local game = current()
    if not game then
      return nil, "no game"
    end
    local api = native(game)
    local ow = api:overworld()
    if not ow then
      return nil, "no overworld"
    end
    local ready, why = Actions.ready(game, ow)
    if not ready then
      return nil, why
    end
    inspect(loader)
    if pending[game] or ow.gen3Locked or #(ow.parallelRunners or {}) > 0 or #(ow.parallelQueue or {}) > 0 then
      return nil, "world is busy"
    end
    local plan, reason = W.plan(game, ow, generation, mapId, x, y, facing)
    if not plan then
      return nil, reason
    end
    local destination = plan.mapId
    if options ~= nil and (type(options) ~= "table" or getmetatable(options) ~= nil) then
      return nil, "invalid options"
    end
    local opts = {}
    for key, value in pairs(options or {}) do
      if key == "arrive" then
        if value ~= "fly" and value ~= "teleport" then
          return nil, "invalid arrival"
        end
      elseif key == "onDone" then
        if type(value) ~= "function" then
          return nil, "invalid callback"
        end
      elseif key == "keepMusic" or key == "fade" then
        if type(value) ~= "boolean" then
          return nil, "invalid options"
        end
        if key == "fade" and generation ~= 3 then
          return nil, "unsupported fade"
        end
      else
        return nil, "unknown warp option: " .. tostring(key)
      end
      opts[key] = value
    end
    facing = plan.facing
    local hooks, events = Runtime.hooks, Runtime.events
    local token =
      { game = game, loader = loader, owner = owner, destination = destination, callback = opts.onDone }
    local save, data, stack, player, version = game.save, game.data, game.stack, ow.player, Version.get()
    function token.valid()
      return not token.done
        and licensed()
        and current() == game
        and game.save == save
        and game.data == data
        and game.stack == stack
        and ow.player == player
        and Version.get() == version
        and Runtime.hooks == hooks
        and Runtime.events == events
        and native(game):overworld() == ow
    end
    local accepted, deferred
    local function finish(...)
      if token.done then
        return
      end
      if accepted == nil then
        if not deferred then
          deferred = pack(...)
        end
        return
      end
      local valid = token.valid() and ow.map and ow.map.id == destination
      local callback = valid and token.callback
      retire(token)
      if not accepted or not callback then
        return
      end
      local previous = Runtime.currentMod
      Runtime.currentMod = owner
      local result = pack(pcall(callback, ...))
      Runtime.currentMod = previous
      if not result[1] then
        Runtime.reportError(owner, "world warp callback failed: " .. tostring(result[2]))
      end
    end
    pending[game] = token
    local arrival = ow.arriveWarp
    if opts.arrive then
      ow.arriveWarp = opts.arrive
    end
    local called, result, detail = pcall(
      ow.startWarpTo,
      ow,
      destination,
      x,
      y,
      facing,
      finish,
      { via = "warp", keepMusic = opts.keepMusic, fade = opts.fade }
    )
    -- The native controller is a void method. Explicit false/refusal and errors
    -- never count as admission; a callback fired before that result is deferred.
    accepted = called and result ~= false and not (result == nil and detail ~= nil)
    if not accepted then
      retire(token)
      ow.arriveWarp = arrival
      if not called then
        return nil, "world operation failed: " .. tostring(result)
      end
      return nil, detail or "world operation failed"
    end
    if deferred then
      finish(unpack(deferred, 1, deferred.n))
    end
    return true
  end
  -- Synchronous API-3 edits share this owner lease and loader lifecycle.
  return warp, licensed
end
return W
