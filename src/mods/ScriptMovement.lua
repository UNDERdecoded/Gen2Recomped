-- Closed movement vocabulary over this host's native actor/track services.
local Version = require("src.core.GameVersion")
local unpack = table.unpack or unpack
local M = {
  ARITY = {
    move_player = 3,
    move_npc = 4,
    move_npc_to = 4,
    place_npc = 5,
    face = 2,
    face_object = 4,
    face_npc = 1,
    face_player = 1,
    face_player_dir = 2,
  },
}
local directions = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local function integer(v, max)
  return type(v) == "number" and v == v and v >= 0 and v <= max and v % 1 == 0
end
local function ref(v)
  return type(v) == "string" and #v > 0 and #v <= 256 and not v:find("%c") or integer(v, 1000000)
end
function M.syntax(verb, row, context)
  if (context.generation or Version.generation()) > 3 then
    return nil, "portable movement unavailable for this generation"
  end
  local n = #row
  local minimum = (
    verb == "move_player" and 2
    or verb == "move_npc" and 3
    or verb == "place_npc" and 4
    or verb == "face_object" and 3
  ) or M.ARITY[verb]
  if n < minimum or n > M.ARITY[verb] then
    return nil, "invalid command arity"
  end
  if verb == "move_player" or verb == "move_npc" then
    local at = verb == "move_player" and 2 or 3
    if
      not directions[row[at]]
      or row[at + 1] ~= nil and not integer(row[at + 1], 1024)
      or at == 3 and not ref(row[2])
    then
      return nil, "invalid script movement"
    end
  elseif verb == "place_npc" or verb == "move_npc_to" then
    if
      not ref(row[2])
      or not integer(row[3], 1000000)
      or not integer(row[4], 1000000)
      or row[5] ~= nil and not directions[row[5]]
    then
      return nil, "invalid NPC position"
    end
  elseif verb == "face_object" then
    if not ref(row[2]) or not directions[row[3]] then
      return nil, "invalid object facing"
    end
  elseif verb == "face" or verb == "face_player_dir" then
    if not directions[row[2]] then
      return nil, "invalid facing"
    end
  end
  local out = { row[1], row[2], row[3], row[4], row[5] }
  if verb == "face_object" and row[4] ~= nil then
    if type(row[4]) ~= "table" or getmetatable(row[4]) ~= nil then
      return nil, "invalid facing options"
    end
    out[4] = {}
    for k, v in pairs(row[4]) do
      if k ~= "hold" or not integer(v, 36000) then
        return nil, "invalid facing options"
      end
      out[4][k] = v
    end
  end
  return out
end
function M.actor(world, reference)
  if reference == "player" then
    return world.player
  end
  for _, actor in ipairs(world.npcs or {}) do
    local def = actor.def or {}
    if
      actor.id == reference
      or def.name == reference
      or def.id == reference
      or def.index == reference
      or def.localId == reference
    then
      return actor
    end
  end
end
function M.prepare(world, rows, prevalidated)
  local npc = world.talkNpc or world.runner and world.runner.ctx and world.runner.ctx.npc
  local function target(row)
    local verb = row[1]
    if verb == "move_player" or verb == "face_player_dir" or verb == "face_npc" then
      return world.player
    end
    if verb == "face" or verb == "face_player" then
      return npc
    end
    return M.actor(world, row[2])
  end
  for i, row in ipairs(rows) do
    if not prevalidated and M.ARITY[row[1]] then
      local actor = target(row)
      if not actor then
        return nil, "row " .. i .. ": native movement target unavailable"
      end
      if (row[1] == "face_npc" or row[1] == "face_player") and not npc then
        return nil, "row " .. i .. ": script NPC unavailable"
      end
      if not integer(actor.cellX, 1000000) or not integer(actor.cellY, 1000000) then
        return nil, "invalid actor position"
      end
      if row[1]:match("^move_") and type(world.scriptMove) ~= "function" then
        return nil, "native movement unavailable"
      end
      if
        row[1] == "move_npc_to"
        and (type(world.map.inBounds) ~= "function" or type(world.map.isWalkableCell) ~= "function")
      then
        return nil, "native path unavailable"
      end
    end
  end
  return {
    target = target,
    npc = npc,
    forgetNpc = function()
      npc = nil
    end,
  }
end
function M.path(world, actor, tx, ty)
  -- The native Gen1 command routes around occupied cells; later generations
  -- use their walkable grid. Bound the search independently of map dimensions.
  local map, gen = world.map, Version.generation()
  local function key(x, y)
    return x .. ":" .. y
  end
  local queue, first = { { actor.cellX, actor.cellY } }, 1
  local prev = { [key(actor.cellX, actor.cellY)] = false }
  local dirs = { "up", "down", "left", "right" }
  while queue[first] and first <= 16384 do
    local x, y = unpack(queue[first])
    first = first + 1
    if x == tx and y == ty then
      local path, at = {}, key(x, y)
      while prev[at] do
        table.insert(path, 1, prev[at][2])
        at = prev[at][1]
      end
      return path
    end
    for _, dir in ipairs(dirs) do
      local d = directions[dir]
      local nx, ny = x + d[1], y + d[2]
      local k = key(nx, ny)
      local goal = nx == tx and ny == ty
      if
        prev[k] == nil
        and map:inBounds(nx, ny)
        and (map:isWalkableCell(nx, ny) or gen == 1 and goal)
        and (
          gen ~= 1
          or goal
          or not require("src.world.Collision").occupied(world.entities or {}, nx, ny, actor)
        )
      then
        prev[k] = { key(x, y), dir }
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  return nil, "native movement path unavailable"
end
M.directions = directions
return M
