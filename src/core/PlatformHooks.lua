-- Shared process-lifecycle boundary for portable launcher integrations.
local Runtime = require("src.mods.Runtime")
local PlatformHooks = {}

function PlatformHooks.quitToLauncher(vanilla)
  return Runtime.call("core.quit_to_launcher", vanilla)
end

return PlatformHooks
