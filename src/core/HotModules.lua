-- Lazy dependency upvalues shared by native update/draw sites. Public require
-- paths stay intact; replacing/clearing package.loaded remains observable.
local Performance = require("src.core.Performance")
local Hot = {}
local _modules = {}

function Hot.get(name)
	if Performance.hotPathHoist then
		local module = _modules[name]
		if module and package.loaded[name] == module then
			return module
		end
		module = require(name)
		_modules[name] = module
		return module
	end
	return require(name)
end

function Hot.optional(name)
	if Performance.hotPathHoist then
		local module = _modules[name]
		if module and package.loaded[name] == module then
			return true, module
		end
	end
	local ok, module = pcall(require, name)
	if ok and Performance.hotPathHoist then
		_modules[name] = module
	end
	return ok, module
end

return Hot
