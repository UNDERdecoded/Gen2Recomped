-- Real native loader/data owners; ROM mount and editor UI are device seams.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Lifecycle = require("src.core.SessionLifecycle")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Assets = require("src.render.Assets")
local Data = require("src.core.Data")
local originalVersion = Version.get()
local cache = require("src.import.CacheFs")
local originalUnmount = cache.unmountVersion
local unmounted, processStops = {}, 0
cache.unmountVersion = function(version) unmounted[#unmounted + 1] = version; return true end
Lifecycle.registerProcessShutdown(function() processStops = processStops + 1 end)
local function loadProbe(version)
  Version.set(version)
  local data = T.fixtures.fresh()
  data.constants.generation = Version.generation()
  local run = T.sdk.loadMods({ "mods/session_probe" }, {
    data = data,
    fs = T.sdk.memfs({
      ["mods/session_probe/manifest.json"] = [[{
        "id":"session_probe", "name":"Session probe", "version":"1.0.0",
        "api":2, "entry":"main.lua", "affects_link":false
      }]],
      ["mods/session_probe/main.lua"] = [[
        local mod = ...
        mod.hooks:wrap("core.update", function(nextFn, ...) return nextFn(...) end)
        local Assets = require("src.render.Assets")
        local previous = Assets.exists
        Assets.exists = function(path)
          if path == "session-probe-only" then return true end
          return previous(path)
        end
      ]],
    }),
  })
  T.eq(#run.errors, 0, version .. ": probe loads through native SDK")
  T.check(Runtime.wantsHook("core.update"), "session owns its live hook")
  T.check(Assets.loader ~= nil, "session owns its asset bridge")
  T.eq(Assets.exists("session-probe-only"), true, "session owns its engine wrapper")
  package.loaded["data.generated.maps"] = { previousVersion = version }
  package.loaded["data.generated.gen4_map_headers"] = { previousVersion = version }
  return run
end
local function clean(version)
  T.eq(Runtime.wantsHook("core.update"), false, version .. ": old hook is retired")
  T.eq(Runtime.errors, nil, "old error feed is detached")
  T.eq(Assets.loader, nil, "old asset bridge is detached")
  T.eq(Assets.exists("session-probe-only"), false, "engine wrapper is restored")
  T.eq(package.loaded["data.generated.maps"], nil, "old generated maps are evicted")
  T.eq(package.loaded["data.generated.gen4_map_headers"], nil, "edition markers are evicted")
  T.eq(package.loaded["src.core.Data"], Data, "native data owner retains its identity")
  T.eq(processStops, 0, "mounted-session teardown does not stop process workers")
end
for _, version in ipairs({ "gold", "silver", "crystal", "red", "emerald", "firered" }) do
  local run = loadProbe(version)
  Lifecycle.endMountedSession(version)
  clean(version)
  T.eq(unmounted[#unmounted], version, "correct cartridge read path is unmounted")
  local count = #unmounted
  Lifecycle.endMountedSession(nil)
  T.eq(#unmounted, count, "no-version cleanup does not guess a cartridge")
  clean(version)
  run.release()
end

-- Discover editor panels instead of leaving new panels stale until a list is
-- updated. Exercise the real host Close callback, including unload failure.
local fs = love.filesystem
local originalInfo = fs.getInfo
fs.getInfo = function(path, ...)
  if path == "tools/save-editor/App.lua"
      or path == "tools/save-editor/panels/FuturePanel.lua" then return { type = "file" } end
  return originalInfo(path, ...)
end
local f = assert(io.open("main.lua", "rb"));local source = f:read("*a");f:close()
local function extractClose(text)
  return assert(text:gsub("\r\n", "\n"):match("\nfunction closeEditor%(%).-\nend\n"))
end
local closeSource = extractClose(source)
T.eq(extractClose(source:gsub("\r\n", "\n"):gsub("\n", "\r\n")), closeSource,
  "native editor Close fixture accepts Windows CRLF checkouts")
for _, failUnload in ipairs({ false, true }) do
  local run = loadProbe("crystal")
  package.loaded.App, package.loaded.FuturePanel = {}, {}
  package.loaded["tools.save-editor.panels.FuturePanel"] = {}
  package.loaded.Unrelated = {}
  local unrelated = package.loaded.Unrelated
  local unloads, restores, notices = 0, 0, 0
  local host = { savesChanged = function(_, version)
    T.eq(version, "crystal", "host refresh uses the ended cartridge")
    notices = notices + 1
  end }
  local env = setmetatable({
    editorMode = true, editorVersion = "crystal", editorHost = host,
    EditorApp = { unload = function()
      unloads = unloads + 1
      if failUnload then error("synthetic editor unload failure") end
    end },
    restoreWindow = function() restores = restores + 1 end,
  }, { __index = _G })
  local chunk = assert(loadstring(closeSource, "@native-editor-close"))
  setfenv(chunk, env); chunk()
  T.check(pcall(env.closeEditor), "native Close remains usable after unload failure")
  T.eq(unloads, 1, "editor unload is called once")
  T.eq(restores, 1, "host restores its window once")
  T.eq(notices, 1, "host refreshes its saves once")
  T.eq(env.editorMode, false, "editor input routing is released")
  T.eq(rawget(env, "editorVersion"), nil, "editor cartridge is released")
  T.eq(rawget(env, "EditorApp"), nil, "editor app is released")
  T.eq(env.Importer, host, "launcher owner is restored")
  T.eq(package.loaded.App, nil, "flat editor app is evicted")
  T.eq(package.loaded.FuturePanel, nil, "new editor panel is discovered and evicted")
  T.eq(package.loaded["tools.save-editor.panels.FuturePanel"], nil, "path editor module is evicted")
  T.eq(package.loaded.Unrelated, unrelated, "unrelated flat modules survive")
  clean("crystal")
  run.release()
end
fs.getInfo, cache.unmountVersion = originalInfo, originalUnmount
package.loaded.Unrelated = nil
Version.set(originalVersion)
T.finish("native mounted and editor session teardown")
