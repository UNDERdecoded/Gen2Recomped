-- The Legend of Zelda: The Minish Cap (USA, BZME) -- game module.
-- Interface: docs/zelda/CONTRACT.md.  Parity notes: docs/zelda/minishcap.md.
local Layout = require("src.zelda.tmc.Layout")
local Extract = require("src.zelda.tmc.Extract")

local M = {
  id = "minishcap",
  cacheVersion = Extract.CACHE_VERSION,
}

function M.detect(header)
  return Layout.detect(header)
end

-- runs in the import worker: (romPath or nil, cache root, progress, ctx)
function M.extract(romPath, root, progress, ctx)
  local ok, err = Extract.run(romPath, root, progress, ctx)
  if not ok then error(err or "Minish Cap import failed", 0) end
  return true
end

function M.isReady(root)
  local ok, ready = pcall(Extract.isReady, root)
  if ok and ready then return true end
  return false, "the Minish Cap cache is incomplete -- import the ROM again"
end

function M.newGame(opts)
  return require("src.zelda.tmc.Game").new(opts or {})
end

return M
