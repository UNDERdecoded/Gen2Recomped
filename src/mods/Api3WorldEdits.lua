-- Validated API-3 object/block edits over this host's native runtime paths.
local Actions = require("src.world.WorldActions")
local Reads = require("src.mods.WorldReads")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local E = {}
local running = setmetatable({}, { __mode = "k" })
local function integer(value, maximum)
  return type(value) == "number"
    and value == value
    and value >= 0
    and value < math.huge
    and value % 1 == 0
    and (not maximum or value <= maximum)
end
local function identifier(value)
  return type(value) == "string" and #value > 0 and #value <= 256 and not value:find("%c")
end
local function store(value)
  return value == nil or type(value) == "table"
end
local function toggle(game, ow, api, gen, req, mapId, ref, visible)
  if not identifier(mapId) or not (identifier(ref) or integer(ref)) or type(visible) ~= "boolean" then
    return nil, "invalid object toggle"
  end
  local maps = game.data and game.data.maps
  local id = mapId
  if gen == 3 and maps and not maps[id] then
    local prefix = ({ ruby = "RU_", sapphire = "SA_", emerald = "EM_" })[Version.get()] or "FR_"
    if maps[prefix .. id] then
      id = prefix .. id
    end
  end
  local def = maps and maps[id]
  if not def then
    return nil, "unknown map: " .. mapId
  end
  local save = game.save
  if not store(save.objectToggles) or not store(save.objectToggles and save.objectToggles[id]) then
    return nil, "invalid object toggle store"
  end
  if not store(save.flags) then
    return nil, "invalid flag store"
  end
  if gen == 1 then
    -- Gen 1 permits off-map keys and resolves their visibility on map load.
    return api:toggleObject(id, ref, visible)
  end
  if ow.map.id ~= id then
    return nil, "map is not active: " .. mapId
  end
  local objects = ow.map.def and ow.map.def.objects
  if type(objects) ~= "table" then
    return nil, "map has no objects"
  end
  local object
  for i, candidate in ipairs(objects) do
    local numeric = gen == 2 and i or tonumber(candidate.localId or candidate.index)
    if numeric == ref or candidate.name == ref or gen == 3 and candidate.id == ref then
      object = candidate
      break
    end
  end
  if not object then
    return nil, "no such object: " .. tostring(ref)
  end
  if type(ow.syncObjectVisibility) ~= "function" then
    return nil, "object runtime unavailable"
  end
  local ctx = { game = game, save = save, overworld = ow, mapId = id }
  if gen == 2 then
    if not store(save.g2ObjectToggles) then
      return nil, "invalid object toggle store"
    end
    req("src.script.Gen2Commands").setObjectVisibility(ctx, object, id, visible)
  else
    local index = object.index
    if not integer(index, 254) or index == 0 then
      return nil, "invalid object definition"
    end
    if
      not store(save.gen3Spawned)
      or not store(save.gen3Spawned and save.gen3Spawned[id])
      or not store(save.gen3SessionObjects)
    then
      return nil, "invalid object toggle store"
    end
    req("src.script.Gen3Commands")
    local commands = req("src.script.Commands")
    local command = visible and commands.g3_show_object or commands.g3_hide_object
    command(ctx, index)
  end
  Runtime.emit("world.object_toggled", { mapId = id, objName = ref, visible = visible })
  return true
end
local function replace(game, ow, api, gen, req, bx, by, block)
  if not integer(block, gen == 3 and 1023 or 255) then
    return nil, "invalid block id"
  end
  local present, metadata = Reads.activeBlockAt(ow.map, ow.map.id, bx, by)
  if present == nil then
    return nil, metadata
  end
  local cells = gen == 3 and 1 or 2
  if ow.map.blockCells ~= cells then
    return nil, "unsupported block geometry"
  end
  if gen ~= 3 and not (ow.map.tileset and ow.map.tileset.blocks and ow.map.tileset.blocks[block + 1]) then
    return nil, "unknown block id"
  end
  local renderer = ow.map.renderer
  if not renderer or type(renderer.rebuild) ~= "function" then
    return nil, "block renderer unavailable"
  end
  if gen ~= 3 then
    return api:replaceBlock(bx, by, block)
  end
  -- Like Gen1's Gen3 Field.setMetatile default, use the native non-impassable
  -- metatile command; it replaces the old collision override as well.
  req("src.script.Gen3Commands")
  req("src.script.Commands").g3_set_metatile(
    { game = game, save = game.save, overworld = ow },
    bx,
    by,
    block,
    0
  )
  renderer:rebuild()
  ow.map.blocksDirty = nil
  Runtime.emit("world.block_replaced", { mapId = ow.map.id, bx = bx, by = by, block = block })
  return true
end
-- Shared admission/commit guard for synchronous API-3 world mutations.
function E.ready(game, ow)
  local ok, reason = Actions.ready(game, ow)
  if not ok then
    return nil, reason
  end
  if running[game] or ow.gen3Locked or #(ow.parallelRunners or {}) > 0 or #(ow.parallelQueue or {}) > 0 then
    return nil, "world is busy"
  end
  return true
end
function E.run(game, operation, ...)
  running[game] = true
  local called, value, why = pcall(operation, ...)
  running[game] = nil
  if not called then
    error(value, 0)
  end
  return value, why
end
function E.call(game, api, generation, req, name, ...)
  local ow = api:overworld()
  if not ow then
    return nil, "no overworld"
  end
  local ok, reason = E.ready(game, ow)
  if not ok then
    return nil, reason
  end
  local operation = name == "toggleObject" and toggle or replace
  return E.run(game, operation, game, ow, api, generation, req, ...)
end
return E
