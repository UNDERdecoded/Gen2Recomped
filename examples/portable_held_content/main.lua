local mod = ...
-- Older SDKs expose the generation and registry, without supports().
local available = mod.supports and mod:supports("content", "held_items")
  or (not mod.supports and mod.generation == 2 and mod.content.held_items ~= nil)
local state = { available = available, calls = 0 }
mod.exports.api, mod.exports.state = mod, state
if not state.available then
  return
end
local held = mod.content.held_items
local mode = mod:read("case.txt") or "berry"
if mode == "berry" or mode == "rollback" or mode == "stack" then
  held:override("LEFTOVERS", { heldEffect = "HELD_BERRY", heldParameter = 7 })
elseif mode == "patch" then
  held:patch("LEFTOVERS", { heldParameter = 13 })
elseif mode == "remove" then
  held:remove("LEFTOVERS")
elseif mode == "register" then
  mod.content.items:register(
    "PORTABLE_ITEM",
    { id = "PORTABLE_ITEM", index = 240, name = "PORTABLE ITEM", price = 100 }
  )
  held:register("PORTABLE_ITEM", { heldEffect = "HELD_BERRY", heldParameter = 11 })
elseif mode == "omitted" then
  held:override("LEFTOVERS", { heldEffect = "HELD_NONE" })
elseif mode == "custom" then
  held:override("LEFTOVERS", { heldEffect = "HELD_PORTABLE", heldParameter = 9 })
  mod.hooks:wrap("held_item.trigger", function(next, ctx)
    state.calls = state.calls + 1
    if ctx.effect == "HELD_PORTABLE" then
      return "HELD_BERRY", ctx.parameter
    end
    return next(ctx)
  end)
elseif mode == "price" then
  mod.content.items:patch("LEFTOVERS", { price = 999 })
  held:override("LEFTOVERS", { heldEffect = "HELD_BERRY", heldParameter = 17 })
elseif mode == "noop_modern" then
  held:patch("BERRY", {})
elseif mode == "modern" then
  held:override("BERRY", { heldEffect = "HELD_BERRY", heldParameter = 7 })
elseif mode == "dragon" then
  held:override("DRAGON_FANG", { heldEffect = "HELD_NONE", heldParameter = 0 })
elseif mode == "delete_parameter" then
  held:patch("LEFTOVERS", { heldParameter = mod.DELETE })
elseif mode == "invalid" then
  held:override("LEFTOVERS", { heldEffect = "HELD_BERRY", heldParameter = 256 })
end
state.initial = held:get("LEFTOVERS")
if mode == "rollback" then
  error("intentional held-content entry rollback")
end
