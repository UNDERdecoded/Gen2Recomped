-- Installation-wide preferences. Dependencies are enforced by Loader:_order;
-- this module only ranks otherwise eligible mods and never edits manifests.
local LoadOrder = {}

function LoadOrder.normalize(value)
  local out, seen = {}, {}
  if type(value) ~= "table" then return out end
  for _, id in ipairs(value) do
    if type(id) == "string" and id ~= "" and not seen[id] then
      out[#out + 1], seen[id] = id, true
    end
  end
  return out
end

-- Keep absent/disabled ids, so reinstalling or changing games does not lose
-- their positions. Newly discovered ids follow in the original priority order.
function LoadOrder.materialize(saved, entries)
  local out = LoadOrder.normalize(saved)
  local seen, tail = {}, {}
  for _, id in ipairs(out) do seen[id] = true end
  for _, entry in ipairs(entries or {}) do
    local m = entry.manifest or entry
    if not seen[m.id] then
      seen[m.id] = true
      tail[#tail + 1] = m
    end
  end
  table.sort(tail, function(a, b)
    local pa, pb = tonumber(a.priority) or 0, tonumber(b.priority) or 0
    if pa ~= pb then return pa < pb end
    return a.id < b.id
  end)
  for _, m in ipairs(tail) do out[#out + 1] = m.id end
  return out
end

function LoadOrder.rank(saved, entries)
  local rank = {}
  for i, id in ipairs(LoadOrder.materialize(saved, entries)) do rank[id] = i end
  return rank
end

-- Move among visible installed ids, leaving hidden and absent ids in place.
function LoadOrder.move(saved, entries, visible, id, delta)
  local full = LoadOrder.materialize(saved, entries)
  local shown, slots, ids, at = {}, {}, {}
  for _, row in ipairs(visible or entries or {}) do
    local m = row.manifest or row
    shown[m.id] = true
  end
  for i, candidate in ipairs(full) do
    if shown[candidate] then
      slots[#slots + 1], ids[#ids + 1] = i, candidate
      if candidate == id then at = #ids end
    end
  end
  if not at or (delta ~= -1 and delta ~= 1) then return full, false end
  local to = at + delta
  if to < 1 or to > #ids then return full, false end
  ids[at], ids[to] = ids[to], ids[at]
  for i, slot in ipairs(slots) do full[slot] = ids[i] end
  return full, true
end

function LoadOrder.same(a, b, entries)
  local left, right = LoadOrder.materialize(a, entries), LoadOrder.materialize(b, entries)
  if #left ~= #right then return false end
  for i, id in ipairs(left) do if id ~= right[i] then return false end end
  return true
end

return LoadOrder
