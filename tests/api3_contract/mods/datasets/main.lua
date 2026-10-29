local mod = ...
mod.exports.inspect = function(version)
  local view, why = mod.datasets:open(version)
  if not view then
    return nil, why
  end
  local row = assert(view.content.pokemon:get("MEW"))
  local before = row.baseStats.hp
  row.baseStats.hp = 250
  assert(view.content.pokemon:get("MEW").baseStats.hp == before)
  assert(view.content.pokemon:has("MEW") and not view.content.pokemon:has("MISSING"))
  local found = false
  for id, value in view.content.pokemon:each() do
    if id == "MEW" then
      found = value.baseStats.hp == before
    end
  end
  assert(found and view.content.pokemon.patch == nil and view.content.pokemon.register == nil)
  return {
    version = view.version,
    generation = view.generation,
    id = row.id,
    hp = before,
    special = view.content.pokemon:get("MEW").baseStats.special,
    detached = true,
    readonly = true,
    path = type(view.assets:path("assets/generated/probe.png")) == "string",
    size = view.assets:info("assets/generated/probe.png").size,
  }
end
mod.exports.open = function(version)
  return mod.datasets:open(version)
end
