-- Execute the native quit callback; no app, ROM or real worker is started.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local Lifecycle = require("src.core.SessionLifecycle")
local calls = 0
Lifecycle.registerProcessShutdown(function() calls = calls + 1 end)
local file = assert(io.open("main.lua", "rb"))
local source = file:read("*a"); file:close()
local function extractQuit(text)
  return assert(text:gsub("\r\n", "\n"):match("\nfunction love%.quit%(%).-\nend\n"))
end
local quit = extractQuit(source)
T.eq(extractQuit(source:gsub("\r\n", "\n"):gsub("\n", "\r\n")), quit,
  "native quit fixture accepts Windows CRLF checkouts")
local function attempt(editor, veto)
  calls = 0
  local nativeStops = 0
  local key = "src.core.ChipAudio"
  local saved = package.loaded[key]
  package.loaded[key] = { shutdown = function() nativeStops = nativeStops + 1 end }
  local env = setmetatable({
    love = {}, editorMode = editor,
    EditorApp = { quit = function() return veto end },
    walkerTick = function() end,
    BootTrace = { finish = function() end },
    require = function(name)
      if name == "src.core.SessionLifecycle" then return Lifecycle end
      if name == "src.core.DiscordPresence" then return { shutdown = function() end } end
      return require(name)
    end,
  }, { __index = _G })
  local chunk = assert(loadstring(quit, "@native-quit-callback"))
  setfenv(chunk, env); chunk()
  local result = env.love.quit()
  package.loaded[key] = saved
  return result, calls, nativeStops
end
for _, editor in ipairs({ false, true }) do
  local result, hooks, workers = attempt(editor, false)
  T.eq(result, nil, "accepted exit is not vetoed (editor=" .. tostring(editor) .. ")")
  T.eq(hooks, 1, "accepted exit reaches registered shutdowns")
  T.eq(workers, 1, "accepted exit reaches native worker shutdowns")
end
local result, hooks, workers = attempt(true, true)
T.eq(result, true, "unsaved editor may veto exit")
T.eq(hooks, 0, "editor veto retains registered workers")
T.eq(workers, 0, "editor veto retains native workers")
T.finish("native process quit routing")
