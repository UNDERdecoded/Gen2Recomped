local mod = ...
assert(mod.content.pokemon:patch("MEW", { baseStats = { hp = 199 } }))
mod.events:on("mod.portable.probe", function()
  error("failed subscription leaked")
end)
error("intentional API 3 rollback")
