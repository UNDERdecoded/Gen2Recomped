-- #575: HostShell.restart on Android must never reach love.event.quit
-- ("restart") -- the vendored love.cpp loops runlove() in-process on
-- "restart" and the second PHYSFS_init crashes ("already initialized").
-- The fix prefers the love.system.restartApp JNI bridge (which kills the
-- process, so a true return is never observed live) and, on an old APK
-- whose liblove lacks the bridge, falls back to a CLEAN quit with no
-- argument.  Desktop keeps the in-process quit("restart").
--   luajit tests/engine/host_restart_android_bug575.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local HostShell = require("src.core.HostShell")

local quits = {}
love.event = {
  -- record the argument distinctly from "called with none": quit() and
  -- quit("restart") are the whole difference this test pins
  quit = function(...)
    quits[#quits + 1] = { n = select("#", ...), arg = (...) }
  end,
}

local osName = "Android"
local restartCalls = 0
love.system = love.system or {}
love.system.getOS = function() return osName end

-- bridge present and schedulable: restart goes through it, quit untouched
love.system.restartApp = function() restartCalls = restartCalls + 1 return true end
HostShell.restart()
eq(restartCalls, 1, "Android restart prefers the restartApp bridge (#575)")
eq(#quits, 0, "a scheduled relaunch never touches love.event.quit")

-- bridge present but could not schedule: clean quit, never quit("restart")
love.system.restartApp = function() restartCalls = restartCalls + 1 return false end
HostShell.restart()
eq(restartCalls, 2, "the bridge is still tried first")
eq(#quits, 1, "a failed schedule falls back to one quit")
eq(quits[1].n, 0, "and it is a bare quit(), not quit(\"restart\")")

-- old APK, no bridge compiled in: same clean quit fallback
love.system.restartApp = nil
HostShell.restart()
eq(#quits, 2, "a bridge-less APK quits cleanly instead of crashing")
eq(quits[2].n, 0, "again with no restart argument")

-- desktop (no AppImage in a test environment) keeps the in-process restart
if not os.getenv("APPIMAGE") then
  osName = "OS X"
  HostShell.restart()
  eq(quits[3] and quits[3].arg, "restart",
     "non-Android still restarts in-process")
end

T.finish("host_restart_android_bug575")
