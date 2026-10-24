-- Same public consumer on both SDKs. Labels select the game's native prose;
-- the mod never imports an engine module or replaces a renderer.
local mod = ...
local prose = mod.content.rom_text
mod.exports.api = mod
mod.exports.available = prose.available == true
if not mod.exports.available then
  return
end
local mode = mod:read("case.txt") or "replace"
local label = mod:read("label.txt") or "gText_WithdrawPokemon"
local value = mod:read("source.txt") or "TAKE POKéMON"
mod.exports.before = prose:get(label)
if mode == "remove" then
  prose:remove(label)
elseif mode == "register" then
  mod.exports.value, mod.exports.reason = prose:register(label, value)
elseif mode == "patch" then
  mod.exports.value, mod.exports.reason = prose:patch(label, value)
elseif mode == "delete" then
  prose:patch(label, mod.DELETE)
else
  mod.exports.value, mod.exports.reason = prose:override(label, value)
end
if mode == "storage-all" then
  local labels =
    { "gText_WithdrawPokemon", "gText_DepositPokemon", "gText_MovePokemon", "gText_MoveItems", "gText_SeeYa" }
  local descriptions = {
    "gText_WithdrawMonDescription",
    "gText_DepositMonDescription",
    "gText_MoveMonDescription",
    "gText_MoveItemsDescription",
    "gText_SeeYaDescription",
  }
  for i, id in ipairs(labels) do
    prose:override(id, "MOD_ROW_" .. i)
  end
  for i, id in ipairs(descriptions) do
    prose:override(id, "MOD_DESC_" .. i)
  end
end
mod.exports.after = prose:get(label)
if mod:read("script.txt") then
  mod.exports.scriptBefore = mod.content.text:get(label)
  mod.content.text:register(label, mod:read("script.txt"))
  mod.exports.scriptAfter = mod.content.text:get(label)
end
if mode == "namespace-prefix" then
  local id = "__portable_script_text__:" .. label
  mod.content.text:register(id, "AUTHORED PREFIX")
  mod.exports.prefixValue = mod.content.text:get(id)
end
if mode == "rollback" then
  error("intentional ROM-prose entry rollback")
end
