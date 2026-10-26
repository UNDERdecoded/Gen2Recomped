local T = require("tests.harness")
local Performance = require("src.core.Performance")
local Hot = require("src.core.HotModules")
local name = "tests.hot_module_probe"
local originalRequire = require
local calls, loads = 0, 0
package.preload[name] = function()
	loads = loads + 1
	return { generation = loads }
end
_G.require = function(path, ...)
	calls = calls + 1
	return originalRequire(path, ...)
end
Performance.hotPathHoist = true
local first = Hot.get(name)
T.eq(loads, 1, "cold dependency is loaded once")
T.eq(Hot.get(name), first, "warm module retains identity")
T.eq(calls, 1, "warm path avoids require dispatch")
first.liveField = "changed"
T.eq(Hot.get(name).liveField, "changed", "module field mutations remain live")
local replacement = { generation = 20 }
package.loaded[name] = replacement
T.eq(Hot.get(name), replacement, "explicit package.loaded replacement is observed")
package.loaded[name] = nil
T.eq(Hot.get(name).generation, 2, "clearing package.loaded reloads the dependency")
Performance.hotPathHoist = false
local before = calls
Hot.get(name)
Hot.get(name)
T.eq(calls - before, 2, "P3 disabled restores normal require dispatch")
Performance.hotPathHoist = true
package.loaded[name] = nil
package.preload[name] = function()
	error("deliberate optional load failure")
end
local ok = Hot.optional(name)
T.eq(ok, false, "optional dependency errors remain contained")
package.loaded[name] = nil
package.preload[name] = function()
	return replacement
end
local value
ok, value = Hot.optional(name)
T.check(ok and value == replacement, "failed loads are not memoized as successful modules")
before = calls
ok, value = Hot.optional(name)
T.check(ok and value == replacement, "optional warm module retains its result")
T.eq(calls, before, "optional warm path avoids pcall/require dispatch")
_G.require = originalRequire
package.loaded[name], package.preload[name] = nil, nil
T.finish()
