-- Construct/query the input facade without a live Game, Input or LOVE runtime.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
love = nil
local Loader = require("src.mods.Loader")
local Json = require("src.link.Json")
local manifest = Json.encode({
  id = "headless_input",
  name = "Headless Input",
  version = "1.0.0",
  api = 2,
  entry = "main.lua",
})
local files = {
  ["mods/headless_input/manifest.json"] = manifest,
  ["mods/headless_input/main.lua"] = [[
    local mod = ...
    mod.exports.input = mod.input
    mod.exports.hasHandle = type(mod.input.tap) == "function"
      and type(mod.input.press) == "function" and type(mod.input.release) == "function"
  ]],
}
local fs = {
  read = function(path)
    return files[path]
  end,
  load = function(path)
    return loadstring(files[path], path)
  end,
  getInfo = function(path)
    if path == "mods" or path == "mods/headless_input" then
      return { type = "directory" }
    end
    if files[path] then
      return { type = "file" }
    end
  end,
  getDirectoryItems = function(path)
    return path == "mods" and { "headless_input" } or {}
  end,
}
local oldGame, oldInput = package.loaded["src.core.Game"], package.loaded["src.core.Input"]
local loader = Loader.new({ fs = fs, dev = true })
loader._game = function()
  error("mod.input must not bootstrap Game")
end
T.check(loader:load({ pokemon = {} }), "headless native API loads")
T.eq(#loader.errors, 0, "no load-time error")
local e = assert(loader.exports.headless_input)
T.eq(e.hasHandle, true, "complete facade available inside entry chunk")
for _, method in ipairs({ "tap", "press" }) do
  for _, game in ipairs({ false, 1, "game", {}, { input = {} } }) do
    T.raises(function()
      e.input[method](e.input, game, "a")
    end, "mod.input needs the live game", "invalid game rejected before Input work")
  end
end
T.eq(e.input:release({}), false, "unknown token is safe before Game exists")
T.eq(e.input:release(nil), false, "missing token is safe before Game exists")
T.eq(package.loaded["src.core.Game"], oldGame, "does not import Game")
T.eq(package.loaded["src.core.Input"], oldInput, "does not import Input")
T.eq(love, nil, "does not install LOVE globals")
loader:_closeModInput()
T.finish("headless mod.input")
