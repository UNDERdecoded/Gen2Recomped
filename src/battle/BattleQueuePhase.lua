-- One native queue, with the public Gen2 resolution phase. Earlier shared
-- checkpoints retain their stored spelling until the next native update.
local Version = require("src.core.GameVersion")
local M = {}

function M.name()
  return Version.isGen2() and "resolving" or "messages"
end

function M.active(screen)
  return screen.phase == "messages"
    or (screen.phase == "resolving" and Version.isGen2())
end

return M
