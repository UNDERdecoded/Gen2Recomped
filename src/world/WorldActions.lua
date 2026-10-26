-- Supported mutations go through the existing gameplay entry points. Shared
-- guards keep companion UIs out of screens/scripts/transitions that own input.
local GameVersion = require("src.core.GameVersion")
local Map = require("src.world.Map")
local MapIdentity = require("src.core.MapIdentity")
local FieldDefaults = require("src.world.FieldDefaults")
local Party = require("src.pokemon.Party")
local A = {}
local function activeTop(stack)
  return stack.active and stack:active() or stack:top()
end

local METHODS = {
  canReorderParty = true,
  reorderParty = true,
  availableFieldActions = true,
  useFieldAction = true,
  canFly = true,
  flyTo = true,
}
local LOCKS = {
  "transitioning",
  "flyAnim",
  "teleportOut",
  "engaging",
  "emote",
  "pikaHop",
  "healAnim",
  "whirlSpin",
  "gen4Waterfall",
  "gen5SeamPending",
  "gen3Decorate",
  "frameScriptThisTick",
  "_modScriptLock",
}
local pending = setmetatable({}, { __mode = "k" })
local planning = setmetatable({}, { __mode = "k" })
local function integer(v, lo, hi)
  return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end
function A.supports(name)
  return type(name) == "string" and METHODS[name] == true
end

local function ready(game, ow)
  if not (game and game.save) then
    return nil, "no save"
  end
  if not (ow and ow.map and ow.player) then
    return nil, "no overworld"
  end
  local token = pending[game]
  if token and token.state then
    local held = false
    for _, state in ipairs(game.stack and game.stack.states or {}) do
      if state == token.state then
        held = true
      end
    end
    if game.stack and game.stack.top and game.stack:top() == token.state then
      held = true
    end
    if
      not held
      or game.save ~= token.save
      or game.data ~= token.data
      or ow.map ~= token.map
      or ow.player ~= token.player
    then
      pending[game] = nil
    end
  end
  if not (game.stack and game.stack.top and activeTop(game.stack) == ow) then
    return nil, "world is busy"
  end
  if
    pending[game]
    or planning[game]
    or (game.overworld and game.overworld ~= ow)
    or game.linkSession
    or (game.linkNet and not game.linkNet.closed)
  then
    return nil, "world is busy"
  end
  for _, key in ipairs(LOCKS) do
    if ow[key] then
      return nil, "world is busy"
    end
  end
  local player = ow.player
  if player.moving or player.inputLocked or player.stairExit or player.spinning or player.fieldMove then
    return nil, "world is busy"
  end
  if not (ow.runner and type(ow.runner.isRunning) == "function") then
    return nil, "world is busy"
  end
  if ow.runner:isRunning() or #(ow.scriptMoves or {}) > 0 or #(ow.pendingScripts or {}) > 0 then
    return nil, "world is busy"
  end
  return true
end
local function guardedCall(game, fn, ...)
  planning[game] = true
  local result = { pcall(fn, game, ...) }
  planning[game] = nil
  if not result[1] then
    error(result[2], 0)
  end
  return result[2], result[3]
end
local function party(game)
  return game and game.save and game.save.party or {}
end
local function member(game, mon)
  if type(mon) ~= "table" or Party.isEgg(mon) then
    return nil
  end
  for _, p in ipairs(party(game)) do
    if p == mon then
      return mon
    end
  end
end
local function user(game, ow, move)
  if type(ow.partyKnows) ~= "function" then
    return nil
  end
  return member(game, ow:partyKnows(move))
end
local function context(game, ow)
  local p = ow.player
  return {
    save = game.save,
    data = game.data,
    map = ow.map,
    player = p,
    x = p.cellX,
    y = p.cellY,
    facing = p.facing,
    version = GameVersion.get(),
  }
end
local function same(game, ow, c)
  return game.save == c.save
    and game.data == c.data
    and ow.map == c.map
    and ow.player == c.player
    and ow.player.cellX == c.x
    and ow.player.cellY == c.y
    and ow.player.facing == c.facing
    and GameVersion.get() == c.version
end
local function currentWorld(game, ow)
  -- A state replaced while a cut-in was active must not receive its effect.
  return game.stack and game.stack.top and activeTop(game.stack) == ow
end
local function present(game, ow, mon, check, run)
  local c = context(game, ow)
  local called = false
  local token = { save = game.save, data = game.data, map = ow.map, player = ow.player }
  pending[game] = token
  local result, reason
  local function finish()
    if called then
      return
    end
    called = true
    if pending[game] ~= token then
      return
    end
    pending[game] = nil
    if
      not currentWorld(game, ow)
      or not same(game, ow, c)
      or not ready(game, ow)
      or not member(game, mon)
    then
      result, reason = nil, "world changed"
      return
    end
    if not check() then
      result, reason = nil, "action unavailable"
      return
    end
    -- A capability hook invoked by check() may have changed the session.
    if not same(game, ow, c) or not ready(game, ow) then
      result, reason = nil, "world changed"
      return
    end
    local answer = guardedCall(game, run)
    if answer == false then
      result, reason = nil, "action unavailable"
    else
      result = true
    end
  end
  if GameVersion.generation() == 3 then
    -- Never retry an engine callback that threw after invoking finish().
    local ok, shown = pcall(function()
      return require("src.world.Gen3FieldMove").show(game, mon, finish)
    end)
    if not ok then
      pending[game] = nil
      error(shown, 0)
    end
    if shown then
      token.state = game.stack:top()
      return true
    end
  end
  finish()
  return result, reason
end

function A.canReorderParty(game, ow)
  return #party(game) > 1 and ready(game, ow) == true
end
function A.reorderParty(game, ow, from, to)
  local ok, reason = ready(game, ow)
  if not ok then
    return nil, reason
  end
  local p = party(game)
  if
    not integer(from, 1, Party.MAX)
    or not integer(to, 1, Party.MAX)
    or type(p[from]) ~= "table"
    or type(p[to]) ~= "table"
  then
    return nil, "invalid party slot"
  end
  -- Match the native party menus: swap references, never reconstruct mons.
  if from ~= to then
    p[from], p[to] = p[to], p[from]
  end
  return true
end

local function outside(game, ow)
  return Map.isOutside(ow.map.def, FieldDefaults.field(game.data, "outsideTilesets"))
end
local function validSpot(data, id, x, y, gen)
  local def = data and data.maps and data.maps[id]
  if not def or not integer(def.width, 1, 1000000) or not integer(def.height, 1, 1000000) then
    return false
  end
  local tileset = data.tilesets and data.tilesets[def.tileset]
  local cells = tileset and tileset.blockCells or (gen >= 3 and 1 or 2)
  return integer(cells, 1, 1000000)
    and integer(x, 0, def.width * cells - 1)
    and integer(y, 0, def.height * cells - 1)
end
local function flyPlan(game, ow, mapId)
  local gen = GameVersion.generation()
  local data, save = game.data or {}, game.save
  local mon
  if gen >= 4 then
    local F = require("src.world.Gen4FieldMoves")
    for _, p in ipairs(party(game)) do
      if not Party.isEgg(p) and F.knows(p, "FLY") then
        mon = p
        break
      end
    end
    if not mon then
      return nil, "fly unavailable"
    end
    if gen == 5 then
      local Fly = require("src.world.Gen5Fly")
      if not Fly.allowed(ow.map.def) or type(ow.gen4FlyTo) ~= "function" then
        return nil, "fly unavailable"
      end
      for _, loc in ipairs(Fly.destinations(data, save)) do
        local dest = Fly.destination(data, loc)
        if dest and (not mapId or dest.map == mapId) and validSpot(data, dest.map, dest.x, dest.y, gen) then
          return { mon = mon, dest = dest, ds = true }
        end
      end
    else
      local Fly = require("src.world.Gen4Fly")
      local costume = require("src.inventory.Gen4FieldChecks").inCostume(data, save)
      if costume or not Fly.check(data, save, ow.map.def) or type(ow.gen4FlyTo) ~= "function" then
        return nil, "fly unavailable"
      end
      for _, dest in ipairs(Fly.destinations(data, save)) do
        if (not mapId or dest.map == mapId) and validSpot(data, dest.map, dest.x, dest.y, gen) then
          return { mon = mon, dest = { map = dest.map, x = dest.x, y = dest.y }, ds = true }
        end
      end
    end
  else
    mon = user(game, ow, "FLY")
    local travel = gen == 3 and require("src.world.Gen3FieldRules").allowsTravel(ow.map.def)
      or (gen < 3 and outside(game, ow))
    if not mon or not travel or type(ow.flyTo) ~= "function" then
      return nil, "fly unavailable"
    end
    local field = data.field or {}
    for _, id in ipairs(field.flyOrder or {}) do
      local def = data.maps and data.maps[id]
      local spot = field.flyWarps and field.flyWarps[id]
      if
        (not mapId or MapIdentity.same(data, mapId, id))
        and save.visited
        and MapIdentity.savedValue(data, save.visited, id)
        and spot
        and def
        and (Map.isOutdoor(def) or def.tileset == "PLATEAU")
        and validSpot(data, id, spot.x, spot.y, gen)
      then
        return { mon = mon, dest = { map = id, x = spot.x, y = spot.y } }
      end
    end
  end
  return nil, "destination unavailable"
end
function A.canFly(game, ow)
  if not ready(game, ow) then
    return false
  end
  local c = context(game, ow)
  return guardedCall(game, flyPlan, ow) ~= nil and same(game, ow, c) and ready(game, ow) == true
end
function A.flyTo(game, ow, mapId)
  local ok, reason = ready(game, ow)
  if not ok then
    return nil, reason
  end
  if type(mapId) ~= "string" or mapId == "" then
    return nil, "invalid destination"
  end
  local c = context(game, ow)
  local plan, why = guardedCall(game, flyPlan, ow, mapId)
  if not plan then
    return nil, why
  end
  if not same(game, ow, c) or not ready(game, ow) then
    return nil, "world changed"
  end
  return present(game, ow, plan.mon, function()
    local fresh = guardedCall(game, flyPlan, ow, mapId)
    return fresh and fresh.mon == plan.mon and fresh.dest.x == plan.dest.x and fresh.dest.y == plan.dest.y
  end, function()
    if plan.ds then
      return ow:gen4FlyTo(plan.dest, plan.mon)
    end
    return ow:flyTo(plan.dest.map, plan.mon)
  end)
end

local ORDER = { "cut", "surf", "dig", "teleport" }
local function fieldPlan(game, ow, id)
  local gen = GameVersion.generation()
  if gen >= 4 then
    return nil, "DS field actions require a native script adapter"
  end
  if id == "cut" then
    if gen == 3 then
      return nil, "Gen 3 Cut requires an object-script adapter"
    end
    local mon = user(game, ow, "CUT")
    if
      mon
      and type(ow.useCutFieldMove) == "function"
      and ow:useCutFieldMove() == "ok"
      and type(ow.tryCut) == "function"
    then
      return {
        mon = mon,
        run = function()
          local x, y = ow.player:facingCell()
          return ow:tryCut(x, y)
        end,
      }
    end
  elseif id == "surf" then
    local mon = user(game, ow, "SURF")
    if
      mon
      and not ow.player.surfing
      and type(ow.useSurfFieldMove) == "function"
      and ow:useSurfFieldMove() == "ok"
      and type(ow.trySurf) == "function"
    then
      return {
        mon = mon,
        run = function()
          local x, y = ow.player:facingCell()
          return ow:trySurf(x, y, nil, mon)
        end,
      }
    end
  elseif id == "dig" or id == "teleport" then
    local mon = user(game, ow, id:upper())
    if not mon or type(ow.beginTeleportOut) ~= "function" then
      return nil, "field action unavailable"
    end
    local escape = false
    if id == "teleport" then
      local travel = gen == 3 and require("src.world.Gen3FieldRules").allowsTravel(ow.map.def)
        or (gen < 3 and outside(game, ow))
      if not travel or not game.save.lastHeal then
        return nil, "field action unavailable"
      end
    elseif gen == 1 then
      local tiles = { FOREST = true, CEMETERY = true, CAVERN = true, FACILITY = true, INTERIOR = true }
      if not tiles[ow.map.def.tileset] or ow.map.id == "AGATHAS_ROOM" or not game.save.lastHeal then
        return nil, "field action unavailable"
      end
    else
      local point = type(ow.escapePoint) == "function" and ow:escapePoint()
      if not point then
        return nil, "field action unavailable"
      end
      if gen == 3 then
        if not require("src.world.Gen3FieldRules").allowsEscape(ow.map.def, point) then
          return nil, "field action unavailable"
        end
      elseif require("src.core.Gen2Environment").id(ow.map.def) ~= 4
         and require("src.core.Gen2Environment").id(ow.map.def) ~= 7 then
        return nil, "field action unavailable"
      end
      escape = true
    end
    return {
      mon = mon,
      run = function()
        return ow:beginTeleportOut(nil, { escape = escape or nil })
      end,
    }
  end
  return nil, "field action unavailable"
end
function A.availableFieldActions(game, ow)
  local ok, reason = ready(game, ow)
  if not ok then
    return {}, reason
  end
  local c = context(game, ow)
  local out = {}
  for _, id in ipairs(ORDER) do
    if guardedCall(game, fieldPlan, ow, id) then
      out[#out + 1] = { id = id, label = id:upper() }
    end
    if not same(game, ow, c) or not ready(game, ow) then
      return {}, "world changed"
    end
  end
  return out
end
function A.useFieldAction(game, ow, id, opts)
  local ok, reason = ready(game, ow)
  if not ok then
    return nil, reason
  end
  if type(id) ~= "string" then
    return nil, "invalid field action"
  end
  if opts ~= nil and (type(opts) ~= "table" or next(opts) ~= nil or getmetatable(opts) ~= nil) then
    return nil, "unsupported field action options"
  end
  local c = context(game, ow)
  local plan, why = guardedCall(game, fieldPlan, ow, id)
  if not plan then
    return nil, why
  end
  if not same(game, ow, c) or not ready(game, ow) then
    return nil, "world changed"
  end
  return present(game, ow, plan.mon, function()
    local fresh = guardedCall(game, fieldPlan, ow, id)
    return fresh and fresh.mon == plan.mon
  end, plan.run)
end
return A
