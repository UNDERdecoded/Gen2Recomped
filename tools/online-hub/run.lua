-- The Link Hub under plain LuaJIT (a Raspberry Pi or VPS without LOVE):
--   luajit tools/online-hub/run.lua [--config FILE] ...
-- Needs the Lua 5.1 C modules `enet` (lua-enet) and `socket` (luasocket)
-- on package.cpath, and the game's src/ tree two folders up (or named by
-- POKEPORT_HUB_ROOT).  See README.md.
local here = (arg and arg[0] or "tools/online-hub/run.lua"):gsub("\\", "/")
local hubDir = here:match("^(.*)/[^/]*$") or "."
local root = (os.getenv("POKEPORT_HUB_ROOT") or (hubDir .. "/../..")):gsub("\\", "/"):gsub("/+$", "")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. hubDir .. "/?.lua;" .. package.path

local okS, socket = pcall(require, "socket")
local args = {}
for i = 1, #arg do args[i] = arg[i] end
local Main = require("src.online.hub.Main")
local code = Main.main(args, { sleep = okS and socket.sleep or nil }, hubDir)
os.exit(code or 0)
