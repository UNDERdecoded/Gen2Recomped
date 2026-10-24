local mod = ...
mod.exports.api = mod
local h = mod.content.ai_classes
local mode = mod:read("case.txt") or "register"
local out = { operations = {} }
mod.exports.state = out
local function record(value)
  if value == nil then
    return false
  end
  local result = {}
  for _, key in ipairs({
    "kind",
    "uses",
    "chance",
    "item",
    "switch",
    "switchChance",
    "switchBelow",
    "hpBelow",
    "onStatus",
  }) do
    result[key] = value[key]
  end
  for _, key in ipairs({ "brain", "score", "choose" }) do
    result[key] = type(value[key]) == "function"
  end
  return result
end
local id = "PORTABLE_METADATA_CLASS"
local registered = h:register(id, { kind = "class", uses = 2, chance = 256, item = "POTION" })
out.operations[#out.operations + 1] = record(registered)
registered.uses, registered.item = 99, "FULL_RESTORE"
out.writeDetached = h:get(id).uses == 2 and h:get(id).item == "POTION"
if mode == "patch" then
  out.operations[#out.operations + 1] = record(h:patch(id, { item = "FULL_RESTORE", hpBelow = 2 }))
elseif mode == "override" then
  out.operations[#out.operations + 1] =
    record(h:override(id, { kind = "class", uses = 1, item = "FULL_RESTORE", onStatus = true }))
elseif mode == "delete-item" then
  out.operations[#out.operations + 1] = record(h:patch(id, { item = mod.DELETE }))
elseif mode == "brain" then
  out.operations[#out.operations + 1] = record(h:override(id, {
    kind = "brain",
    brain = function()
      return 1
    end,
  }))
elseif mode == "remove" then
  h:remove(id)
elseif mode == "rollback" then
  error("intentional AI class metadata rollback")
end
local value = h:get(id)
out.current = record(value)
if value then
  value.uses, value.item = 55, "UNKNOWN_ITEM"
  out.readDetached = h:get(id).uses ~= 55 and h:get(id).item ~= "UNKNOWN_ITEM"
end
for key, entry in h:each() do
  if key == id then
    out.iterated = record(entry)
    entry.uses = 77
  end
end
out.iterationDetached = h:get(id) == nil or h:get(id).uses ~= 77
