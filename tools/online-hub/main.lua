-- The Link Hub under LOVE (headless; see conf.lua):
--   love tools/online-hub [--config FILE] ...      (lovec on Windows for a console)
-- The game's own src/ tree must sit two folders up (the repo layout), or be
-- named by POKEPORT_HUB_ROOT.  See README.md.
local hubDir = (love.filesystem.getSource() or "."):gsub("\\", "/"):gsub("/+$", "")
local root = os.getenv("POKEPORT_HUB_ROOT") or (hubDir .. "/../..")
root = root:gsub("\\", "/"):gsub("/+$", "")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. hubDir .. "/?.lua;" .. package.path

-- never an error window: say it and stop
function love.errorhandler(msg)
  io.stderr:write("Link Hub error: " .. tostring(msg) .. "\n" .. debug.traceback() .. "\n")
  io.stderr:flush()
  os.exit(1)
end

function love.run()
  local args = love.arg and love.arg.parseGameArguments and love.arg.parseGameArguments(arg) or {}
  local code
  local ok, err = xpcall(function()
    local Main = require("src.online.hub.Main")
    code = Main.main(args, { sleep = love.timer and love.timer.sleep }, hubDir)
  end, debug.traceback)
  if not ok then
    io.stderr:write("Link Hub error: " .. tostring(err) .. "\n")
    code = 1
  end
  io.stdout:flush()
  return function() return code or 0 end
end
