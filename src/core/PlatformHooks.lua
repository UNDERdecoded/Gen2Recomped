-- Shared frame boundary for mods that poll host state or pause simulation.
-- Match Gen1Recomp's main.lua -> PlatformHooks.update contract.
local Runtime = require("src.mods.Runtime")
local PlatformHooks = {}

-- Hoisted: forwarding needs no per-frame closure or payload allocation.
-- Native Game:update results are deliberately discarded, as in Gen1.
local function vanillaUpdate(game, dt)
  game:update(dt)
end

function PlatformHooks.update(game, dt)
  return Runtime.call("core.update", vanillaUpdate, game, dt)
end

return PlatformHooks
