local mod = ...
mod.exports.api = mod
local available = mod.supports and mod:supports("content", "marts")
  or (not mod.supports and mod.generation == 2 and mod.content.marts ~= nil)
mod.exports.available = available == true
if not available then
  return
end
local m = mod.content.marts
local mode = mod:read("case.txt") or "replace"
if mode == "replace" or mode == "rollback" or mode == "stack" then
  m:patch("0", { "ULTRA_BALL" })
  m:patch("bargain", { { item = "NUGGET", price = 500 } })
elseif mode == "empty" then
  m:patch("0", {})
  m:patch("bargain", {})
elseif mode == "remove" then
  m:remove("0")
  m:remove("bargain")
elseif mode == "register" then
  m:remove("33")
  m:register("33", { "ULTRA_BALL", "POTION" })
elseif mode == "price" then
  mod.content.items:patch("POTION", { price = 7 })
elseif mode == "zero" or mode == "maximum" then
  m:override("bargain", { { item = "NUGGET", price = mode == "zero" and 0 or 65535 } })
elseif mode == "delete" then
  m:override("0", mod.DELETE)
elseif mode == "invalid" then
  m:patch("0", { [2] = "POTION" })
end
if mode == "rollback" then
  error("intentional mart entry rollback")
end
