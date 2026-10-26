local root = assert(os.getenv("DECODED_PROFILE_REPO"))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
function love.errorhandler(message)
	print(debug.traceback(tostring(message), 2))
	return function()
		return 1
	end
end
local Version = require("src.core.GameVersion")
Version.set("firered")
local Native = require("src.script.ScriptRunner")
local baseline = assert(io.open(assert(os.getenv("DECODED_PROFILE_BASELINE")), "rb"))
local original = assert(loadstring(baseline:read("*a"), "@baseline/ScriptRunner.lua"))()
baseline:close()
local Profile = require("src.core.FrameProfile")
local Runtime = require("src.mods.Runtime")
local Loader = require("src.mods.Loader")
local SDK = require("tests.modkit.sdk")
local Json = require("src.link.Json")
local Compiler = require("src.script.Gen3ScriptVM")
local source = [[return function(mod)
 mod.hooks:wrap('script.command',function(next,ctx,op,row)return next(ctx,op,row)end)
end]]
local phase, frame, runner, rows, game, started, total = 1, 0, nil, nil, nil, 0, 0
local results, WINDOW, WARMUP = {}, 120, 120
local function start()
	Profile.setEnabled(false)
	local data = require("tests.fixtures.upstream_mods.data").fresh()
	local files = {
		["mods/probe/manifest.json"] = Json.encode({ id = "probe", name = "Probe", version = "1.0.0", entry = "main.lua" }),
		["mods/probe/main.lua"] = source,
		["options.lua"] = "return {mods={probe=true}}",
	}
	local loader =
		Loader.new({ fs = SDK.memfs(files), dev = false, callbackProfiles = { probe = phase == 3 and "decoded"
			or "native" } })
	assert(loader:load(data))
	local ir = {}
	for i = 1, 64 do
		ir[i] = { "setvar", 0x4000 + i, i }
	end
	ir[#ir + 1] = { "end" }
	data.map_scripts = { source = "RomExtractorGen3", scripts = { ENTRY = ir }, maps = {} }
	game = { data = data, save = { gen3Vars = {}, flags = {}, party = {} }, mods = loader }
	runner = (phase == 1 and original or Native).new(game, {})
	rows = Compiler.compile(data, "ENTRY")
	frame, total = 0, 0
end
function love.run()
	start()
	return function()
		love.event.pump()
		for name in love.event.poll() do
			if name == "quit" then
				return 1
			end
		end
		if frame == WARMUP then
			Profile.setEnabled(true)
			started = love.timer.getTime()
		end
		local close = Profile.section("script.exec (64 writes + end)")
		local t = love.timer.getTime()
		runner:exec(rows, runner:makeContext())
		if frame >= WARMUP then
			total = total + love.timer.getTime() - t
		end
		close()
		assert(game.save.gen3Vars[0x4040] == 64)
		love.graphics.clear(0.03, 0.04, 0.06)
		love.graphics.present()
		if frame >= WARMUP then
			Profile.frame()
		end
		frame = frame + 1
		if frame == WINDOW + WARMUP then
			results[phase] = {
				mode = ({ "before", "native", "decoded" })[phase],
				frames = WINDOW,
				scriptMeanMs = total / WINDOW * 1000,
				seconds = love.timer.getTime() - started,
			}
			if phase == 3 then
				print(
					"M5_NATIVE_RESULT "
						.. Json.encode({
							phases = results,
							renderer = love.graphics.getRendererInfo(),
							os = love.system.getOS(),
							arch = jit and jit.arch or "unknown",
							scope = "Native LÖVE ScriptRunner and actual per-mod Loader profile over 65 test-owned commands per frame; no world scene or cartridge gameplay",
						})
				)
				return 0
			end
			phase = phase + 1
			start()
		end
	end
end
