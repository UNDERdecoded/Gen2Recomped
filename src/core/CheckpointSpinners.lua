-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Semantic continuation for native stationary spinners; no actor objects or
-- script closures cross the checkpoint boundary.
local S = {}
local FACING = { up = true, down = true, left = true, right = true }
local KINDS = { SPIN_CW = true, SPIN_CCW = true, SPIN_SLOW = true, SPIN_FAST = true }

local function kind(def)
  return def and def.movement == "SPIN" and (def.range or "SPIN_SLOW") or nil
end

local function valid(value)
  return type(value) == "table"
    and KINDS[value.mode] == true
    and type(value.x) == "number"
    and value.x % 1 == 0
    and type(value.y) == "number"
    and value.y % 1 == 0
    and FACING[value.facing] == true
    and type(value.timer) == "number"
    and value.timer % 1 == 0
    and value.timer >= 1
    and value.timer <= 128
end

function S.admit(actor, world)
  local mode = kind(actor.def)
  if
    not KINDS[mode]
    or actor.spins ~= mode
    or not valid({ mode = mode, x = actor.cellX, y = actor.cellY, facing = actor.facing, timer = actor.timer })
  then
    return false
  end
  -- A stale pooled actor from a previous connection may not be rebuilt by
  -- native enter. Only the current cast and its visible neighbours qualify.
  for _, npc in ipairs(world.npcs or {}) do
    if npc == actor then
      return world.npcPool[actor.id] == actor
    end
  end
  for _, ghost in ipairs(world.ghosts or {}) do
    if ghost.npc == actor then
      return world.npcPool[actor.id] == actor
    end
  end
  return false
end

function S.capture(world)
  local values
  for id, actor in pairs(world.npcPool or {}) do
    if actor.spins then
      values = values or {}
      values[id] = { mode = actor.spins, x = actor.cellX, y = actor.cellY, facing = actor.facing, timer = actor.timer }
    end
  end
  return values
end

function S.validate(data, values)
  if values == nil then
    return true
  end
  if type(values) ~= "table" or next(values) == nil then
    return false
  end
  for id, value in pairs(values) do
    if type(id) ~= "string" or not valid(value) then
      return false
    end
    for key in pairs(value) do
      if key ~= "facing" and key ~= "timer" and key ~= "mode" and key ~= "x" and key ~= "y" then
        return false
      end
    end
    local mapId, index = id:match("^(.*)_obj_(%d+)$")
    local map = mapId and data.maps and data.maps[mapId]
    local installed
    for _, def in ipairs(map and map.objects or {}) do
      if def.index == tonumber(index) and kind(def) == value.mode and def.x == value.x and def.y == value.y then
        installed = true
        break
      end
    end
    if not installed then
      return false
    end
  end
  return true
end

function S.apply(world, values)
  if values == nil then
    return
  end -- Original static-only format-1 payload.
  local found = {}
  for id, actor in pairs(world.npcPool or {}) do
    if actor.spins then
      local value = assert(values[id], "checkpoint spinner is missing")
      assert(
        S.admit(actor, world) and actor.spins == value.mode and actor.cellX == value.x and actor.cellY == value.y,
        "native spinner cannot be reconstructed"
      )
      actor.facing, actor.timer = value.facing, value.timer
      found[id] = true
    end
  end
  for id in pairs(values) do
    assert(found[id], "checkpoint spinner is absent from the reconstructed cast")
  end
end

return S
