-- Public engine contract through the real mod loader; no mod assets or ROM.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local services = {
  "src.core.ChipAudio", "src.update.Check", "src.render.ShaderBrowser",
  "src.translation.Service", "src.net.Fetch",
}
local saved = {}
for _, name in ipairs(services) do
  saved[name] = package.loaded[name]
  package.loaded[name] = nil
end

local cold = require("src.core.SessionLifecycle")
for _, name in ipairs(services) do
  T.eq(package.loaded[name], nil, "requiring lifecycle does not load " .. name)
end
-- The first import may happen inside a ModSeams window, as in a portable
-- worker's entry. Retiring that window must keep the fresh engine module.
package.loaded["src.core.SessionLifecycle"] = nil

local run = T.sdk.loadMods({ "mods/worker_probe" }, {
  data = T.fixtures.fresh(),
  fs = T.sdk.memfs({
    ["mods/worker_probe/manifest.json"] = [[{
      "id":"worker_probe", "name":"Worker probe", "version":"1.0.0",
      "api":2, "entry":"main.lua", "affects_link":false
    }]],
    ["mods/worker_probe/main.lua"] = [[
      local mod = ...
      local lifecycle = require("src.core.SessionLifecycle")
      local state = { closed = 0, joined = 0 }
      mod.exports.state = state
      lifecycle.registerProcessShutdown(function()
        state.closed = state.closed + 1
        state.joined = state.joined + 1
      end)
    ]],
  }),
})
T.eq(#run.errors, 0, "a mod can register its worker shutdown during entry")
local Lifecycle = assert(package.loaded["src.core.SessionLifecycle"])
T.check(Lifecycle ~= cold, "the mod performed the first import of its engine owner")
local state = assert(run.loader.exports.worker_probe).state
T.eq(state.joined, 0, "registration does not join a running worker")
require("src.mods.Loader").teardown()
T.eq(state.joined, 0, "returning to launcher retains process workers")
T.eq(package.loaded["src.core.SessionLifecycle"], Lifecycle,
  "mod unwind preserves the engine lifecycle identity")
T.eq(Runtime.currentMod, nil, "teardown has left the mod context")

local order, stops = {}, {}
Lifecycle.registerProcessShutdown(function()
  order[#order + 1] = "failed"
  error("synthetic shutdown failure")
end)
Lifecycle.registerProcessShutdown(function() order[#order + 1] = "survivor" end)
for i, name in ipairs(services) do
  package.loaded[name] = { shutdown = function()
    stops[name] = (stops[name] or 0) + 1
    if i == 1 then error("synthetic service failure") end
  end }
end
T.check(pcall(Lifecycle.endProcess), "a faulty shutdown cannot strand other workers")
T.eq(state.closed, 1, "a retired loader's process callback still closes its worker")
T.eq(state.joined, 1, "a retired loader's process callback still joins its worker")
T.eq(table.concat(order, ","), "failed,survivor", "callbacks keep registration order after failure")
for _, name in ipairs(services) do
  T.eq(stops[name], 1, "native shutdown remains reachable: " .. name)
  package.loaded[name] = nil
end
T.check(pcall(Lifecycle.endProcess), "a process with unused native services can exit")
for _, name in ipairs(services) do
  T.eq(package.loaded[name], nil, "exiting does not start unused " .. name)
  package.loaded[name] = saved[name]
end
T.finish("session_process_shutdown")
