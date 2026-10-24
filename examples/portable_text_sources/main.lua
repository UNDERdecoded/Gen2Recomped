-- One source file for both engines: no engine imports or generation branches.
local mod = ...
local text = mod.content.text
mod.exports.api = mod
local mode = mod:read("case.txt") or "example"
local id = mod:read("id.txt") or "PORTABLE_TEXT"
local source = mod:read("source.txt") or "Hello, {PLAYER}!\\nA portable dialogue.\\pSee you!"
mod.exports.before = text:get(id)
if mode == "corpus" then
  mod.exports.corpus = {}
  local i = 1
  while mod:read("corpus/" .. i) do
    local key = "CORPUS_" .. i
    text:override(key, "seed")
    local value, reason = text:override(key, mod:read("corpus/" .. i))
    mod.exports.corpus[i] = { accepted = reason == nil, value = value, read = text:get(key) }
    i = i + 1
  end
elseif mode == "remove" then
  text:remove(id)
elseif mode == "delete" then
  text:override(id, mod.DELETE)
elseif mode == "patch-delete" then
  text:patch(id, mod.DELETE)
elseif mode == "patch" then
  mod.exports.result, mod.exports.reason = text:patch(id, source)
elseif mode == "register" or mode == "example" then
  mod.exports.result, mod.exports.reason = text:register(id, source)
else
  mod.exports.result, mod.exports.reason = text:override(id, source)
end
mod.exports.after = text:get(id)
mod.exports.ids = {}
if mod:read("enumerate.txt") == "yes" then
  for key in text:each() do
    mod.exports.ids[#mod.exports.ids + 1] = key
  end
end
if mode == "rollback" then
  error("intentional portable text rollback")
end
