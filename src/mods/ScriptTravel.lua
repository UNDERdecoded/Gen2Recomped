-- Destination preflight, including later world rows against destination data.
local Warp = require("src.mods.Api3Warp")
local Movement = require("src.mods.ScriptMovement")
local Edits = require("src.mods.ScriptWorldEdits")
local Version = require("src.core.GameVersion")
local copy = require("src.mods.Merge").deepCopy
local T = { ARITY = { warp = 5, remember_outdoor = 4 } }
function T.syntax(verb, row, context)
  if (context.generation or Version.generation()) > 3 then
    return nil, "portable travel unavailable for this generation"
  end
  if #row < 4 or #row > T.ARITY[verb] then
    return nil, "invalid command arity"
  end
  -- Destination names, coordinates, dimensions and facing are validated with
  -- the same pure planner as the public API once a save/world is available.
  return { row[1], row[2], row[3], row[4], row[5] }
end
local function future(game, world, plan, cache)
  local tiles = game.data.tilesets and game.data.tilesets[plan.def.tileset]
  local map = cache[plan.mapId]
  if map then
  elseif tiles then
    map = require("src.world.Map").new(copy(plan.def), copy(tiles))
  else
    map = { id = plan.mapId, def = plan.def }
  end
  map.renderer = { rebuild = function() end }
  cache[plan.mapId] = map
  local view = {
    isOverworld = true,
    map = map,
    player = { cellX = plan.x, cellY = plan.y, facing = plan.facing },
    npcs = {},
    syncObjectVisibility = world.syncObjectVisibility,
    scriptMove = world.scriptMove,
  }
  for _, def in ipairs(plan.def.objects or {}) do
    view.npcs[#view.npcs + 1] =
      { def = def, id = plan.mapId .. "_obj_" .. tostring(def.index), cellX = def.x, cellY = def.y }
  end
  local proxy = {
    data = game.data,
    save = game.save,
    overworld = view,
    stack = {
      top = function()
        return view
      end,
      states = { view },
    },
  }
  return proxy, view
end
function T.prepare(game, world, owner, rows)
  local gen = Version.generation()
  local model, modelGame = world, game
  local cache = {}
  for i, row in ipairs(rows) do
    local verb = row[1]
    if T.ARITY[verb] then
      local plan, why = Warp.plan(game, model, gen, row[2], row[3], row[4], row[5])
      if not plan then
        return nil, "row " .. i .. ": " .. why
      end
      if verb == "warp" then
        if type(world.startWarpTo) ~= "function" then
          return nil, "native warp unavailable"
        end
        modelGame, model = future(game, world, plan, cache)
      end
    elseif Edits.ARITY[verb] then
      local edit, why = Edits.prepare(modelGame, model, owner, { row })
      if not edit then
        return nil, "row " .. i .. ": " .. why
      end
    elseif Movement.ARITY[verb] then
      local movement, why = Movement.prepare(model, { row })
      if not movement then
        return nil, "row " .. i .. ": " .. why
      end
    end
  end
  return function(row)
    return Warp.plan(game, world, gen, row[2], row[3], row[4], row[5])
  end
end
return T
