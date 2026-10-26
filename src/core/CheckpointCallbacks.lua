-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Provenance for small native completion operations. Arbitrary callbacks remain
-- opaque; their closures and captured object graphs never enter checkpoint data.
local C = {}
local records = setmetatable({}, { __mode = "k" })
function C.bind(fn, record)
  records[fn] = record
  return fn
end
function C.capture(fn, clone)
  if fn == nil then
    return nil
  end
  return clone((assert(records[fn], "completion callback is opaque")))
end
function C.valid(record)
  return record == nil
    or (
      type(record) == "table"
      and type(record.npc) == "string"
      and (record.clearEngaging == nil or type(record.clearEngaging) == "boolean")
    )
end
function C.actor(world, id)
  for _, npc in ipairs(world.npcs or {}) do
    if npc.id == id then
      return npc
    end
  end
  error("native continuation actor is absent", 0)
end
function C.build(world, record)
  if record == nil then
    return nil
  end
  assert(C.valid(record), "invalid native completion")
  local npc = C.actor(world, record.npc)
  return C.bind(function()
    npc.frozen = false
    if record.clearEngaging then
      world.engaging = false
    end
  end, record)
end
return C
