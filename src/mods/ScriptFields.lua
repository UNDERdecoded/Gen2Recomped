-- Data-only field writes; no executable values or namespace escape.
local F = { ARITY = { set_field = 3, set_option = 3 } }
local function copy(value, state, depth)
  state.nodes = state.nodes + 1
  if state.nodes > 1024 or depth > 16 then
    error("script field data limit", 0)
  end
  local kind = type(value)
  if kind == "nil" or kind == "boolean" then
    return value
  end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("invalid field number", 0)
    end
    return value
  end
  if kind == "string" then
    state.bytes = state.bytes + #value
    if state.bytes > 32768 then
      error("script field string limit", 0)
    end
    return value
  end
  if kind ~= "table" or getmetatable(value) ~= nil or state.seen[value] then
    error("script fields require acyclic plain data", 0)
  end
  state.seen[value] = true
  local out = {}
  for k, v in pairs(value) do
    if type(k) ~= "string" and not (type(k) == "number" and k >= 1 and k % 1 == 0 and k < math.huge) then
      error("invalid field data key", 0)
    end
    local key = copy(k, state, depth + 1)
    out[key] = copy(v, state, depth + 1)
  end
  state.seen[value] = nil
  return out
end
local function snapshot(value)
  local state = { nodes = 0, bytes = 0, seen = {} }
  return copy(value, state, 0), state
end
function F.syntax(verb, row, context)
  if (context.generation or require("src.core.GameVersion").generation()) > 3 then
    return nil, "portable fields unavailable for this generation"
  end
  local key = row[2]
  if
    #row < 2
    or #row > 3
    or type(key) ~= "string"
    or #key == 0
    or #key > 256
    or key:find("%c")
    or key:match("^mod%.")
    or key == "mod:"
    or key:find(":", 1, true) and not key:match("^mod:.+")
    or verb == "set_field" and key == "modData"
  then
    return nil, "invalid or foreign script field"
  end
  local ok, value = pcall(snapshot, row[3])
  if not ok then
    return nil, value
  end
  return { verb, key, value }
end
local function plain(value)
  return value == nil or type(value) == "table" and getmetatable(value) == nil
end
function F.prepare(game, owner, rows)
  local bytes, nodes = 0, 0
  local options = game.save.options
  local function stores(row, plannedOptions)
    if row[1] == "set_option" then
      if not plain(plannedOptions) then
        return nil, "invalid options store"
      end
    elseif row[2]:match("^mod:") then
      local data = game.save.modData
      if not plain(data) or data and not plain(data[owner]) then
        return nil, "invalid mod save store"
      end
    end
    return true
  end
  for i, row in ipairs(rows) do
    if F.ARITY[row[1]] then
      local _, size = snapshot(row[3])
      bytes, nodes = bytes + size.bytes, nodes + size.nodes
      if bytes > 131072 or nodes > 8192 then
        return nil, "aggregate script field data limit"
      end
      local ok, why = stores(row, options)
      if not ok then
        return nil, "row " .. i .. ": " .. why
      end
      if row[1] == "set_field" and row[2] == "options" then
        options = row[3]
      end
    end
  end
  return function(_, row)
    local ok, why = stores(row, game.save.options)
    if not ok then
      error(why, 0)
    end
    -- Copy again on each dispatch: loops and post-run save mutations never
    -- expose or mutate the compiled program's snapshot.
    local value = snapshot(row[3])
    if row[1] == "set_option" then
      game.save.options = game.save.options or {}
      game.save.options[row[2]] = value
    else
      local private = row[2]:match("^mod:(.+)$")
      if private then
        game.save.modData = game.save.modData or {}
        game.save.modData[owner] = game.save.modData[owner] or {}
        game.save.modData[owner][private] = value
      else
        game.save[row[2]] = value
      end
    end
  end
end
return F
