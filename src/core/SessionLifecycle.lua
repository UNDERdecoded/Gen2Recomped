-- Process lifetime is longer than a mounted game or mod loader. A download
-- worker may still need joining after its owning mod has been unloaded.
-- Keep this registry in the engine, and call it only after the host accepts
-- a real process exit. Requiring it must not start audio or worker services.
local SessionLifecycle = {}
local processShutdowns = {}

function SessionLifecycle.registerProcessShutdown(fn)
  assert(type(fn) == "function", "process shutdown hook must be a function")
  processShutdowns[#processShutdowns + 1] = fn
end

-- Retire the native loader before changing the read path. It owns the mod
-- buses, wrapper journal, viewport, jobs and compatibility resource holders.
-- Using that owner also keeps process services alive for the next cartridge.
function SessionLifecycle.endMountedSession(version)
  require("src.mods.Loader").teardown()
  if version then require("src.import.CacheFs").unmountVersion(version) end
  require("src.core.Data"):unloadGenerated()
end

local function flushEditorModules()
  local fs = love and love.filesystem
  for name in pairs(package.loaded) do
    if type(name) == "string" then
      local editorPath = name:find("save%-editor") ~= nil
      local flat = not name:find("[./]")
      local editorFile = flat and fs and fs.getInfo and (
        fs.getInfo("tools/save-editor/" .. name .. ".lua")
        or fs.getInfo("tools/save-editor/panels/" .. name .. ".lua"))
      if editorPath or editorFile then package.loaded[name] = nil end
    end
  end
end

function SessionLifecycle.endEditorSession(opts)
  opts = opts or {}
  if opts.app and opts.app.unload then pcall(opts.app.unload) end
  flushEditorModules()
  if opts.version then SessionLifecycle.endMountedSession(opts.version) end
end

-- These services already belonged to the native love.quit path. Never require
-- an unused service just to stop it, and let one broken callback/worker leave
-- the remaining shutdowns reachable. Game/launcher transitions do not join
-- these workers: the next game still shares this process.
local services = {
  "src.core.ChipAudio",
  "src.update.Check",
  "src.render.ShaderBrowser",
  "src.translation.Service",
  "src.net.Fetch",
}

function SessionLifecycle.endProcess()
  local count = #processShutdowns
  for i = 1, count do pcall(processShutdowns[i]) end
  for _, name in ipairs(services) do
    local service = package.loaded[name]
    if service and type(service.shutdown) == "function" then
      pcall(service.shutdown)
    end
  end
end

return SessionLifecycle
