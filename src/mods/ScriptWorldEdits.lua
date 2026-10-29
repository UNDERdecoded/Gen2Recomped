-- Pure plans plus guarded native object/block effects inside an owned script.
local E = require("src.mods.Api3WorldEdits")
local Version = require("src.core.GameVersion")
local W = { ARITY = { show_object = 3, hide_object = 3, replace_block = 4 } }
local function id(value)
  return type(value) == "string" and #value > 0 and #value <= 256 and not value:find("%c")
end
local function integer(value)
  return type(value) == "number" and value == value and value >= 0 and value < math.huge and value % 1 == 0
end
function W.syntax(verb, row, context)
  if (context.generation or Version.generation()) > 3 then
    return nil, "portable world edits unavailable for this generation"
  end
  if #row ~= W.ARITY[verb] then
    return nil, "invalid command arity"
  end
  if verb == "replace_block" then
    if not integer(row[2]) or not integer(row[3]) or not integer(row[4]) then
      return nil, "invalid script block"
    end
  elseif not id(row[2]) or not (id(row[3]) or integer(row[3])) then
    return nil, "invalid script object"
  end
  return { row[1], row[2], row[3], row[4] }
end
function W.prepare(game, world, owner, rows, prevalidated)
  local needed = false
  for _, row in ipairs(rows) do
    needed = needed or W.ARITY[row[1]] ~= nil
  end
  if not needed then
    return function() end
  end
  local gen = Version.generation()
  local api = require("src.world.WorldAPI").new(game, owner)
  local function plan(row)
    if row[1] == "replace_block" then
      return E.plan(game, api, gen, require, "replaceBlock", row[2], row[3], row[4])
    end
    local mapId = row[2]
    local maps = game.data.maps or {}
    if gen == 3 and not maps[mapId] then
      local prefix = Version.get() == "emerald" and "EM_" or "FR_"
      if maps[prefix .. mapId] then
        mapId = prefix .. mapId
      end
    end
    local def = maps[mapId]
    local found = false
    for _, object in ipairs(def and def.objects or {}) do
      if
        object.name == row[3]
        or object.id == row[3]
        or object.index == row[3]
        or object.localId == row[3]
      then
        found = true
        break
      end
    end
    if not found then
      return nil, "native object unavailable: " .. tostring(row[3])
    end
    return E.plan(game, api, gen, require, "toggleObject", mapId, row[3], row[1] == "show_object")
  end
  for i, row in ipairs(rows) do
    if not prevalidated and W.ARITY[row[1]] then
      local operation, reason = plan(row)
      if not operation then
        return nil, "row " .. i .. ": " .. reason
      end
    end
  end
  return function(row, mutate)
    local operation, reason = plan(row)
    if not operation then
      return nil, reason
    end
    return mutate(function()
      return E.run(game, operation)
    end)
  end
end
return W
