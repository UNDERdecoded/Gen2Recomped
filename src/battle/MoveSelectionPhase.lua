-- One native move-selection state, with the public Gen2 screen spelling.
-- Accept earlier shared-controller checkpoints without a second controller
-- or a temporary phase rewrite around presentation callbacks.
local Version = require("src.core.GameVersion")
local M = {}

function M.name()
  return Version.isGen2() and "moves" or "moveSelect"
end

function M.active(screen)
  return screen.phase == "moveSelect"
    or (screen.phase == "moves" and Version.isGen2())
end

return M
