-- Owned native CPU workload. Sprite construction is a deterministic seam;
-- map collision and actor updates use the production engine.
local Contract = require("tests.api3_contract.npcs")
local Profile = require("src.core.FrameProfile")
local Json = require("src.link.Json")
local Native = require("src.world.WorldAPI")
local file = assert(io.open(assert(os.getenv("DECODED_PROFILE_BASELINE")), "rb"))
local Original = assert(loadstring(file:read("*a"), "@baseline/WorldAPI.lua"))()
file:close()
local phase, frame, fixture, total = 1, 0, nil, 0
local results, WINDOW, WARMUP = {}, 120, 120
local function start()
	Profile.setEnabled(false)
	package.loaded["src.world.WorldAPI"] = phase == 1 and Original or Native
	fixture = Contract.fixture("tests/fixtures/legacy_npc_controls", "gen2", "gold", "legacy")
	fixture.loader._game = function()
		return fixture.live
	end
	-- Bind the actual API-2 loader facade before restoring the global module.
	assert(fixture.exports.npc(fixture.home, "IMPORTED"))
	package.loaded["src.world.WorldAPI"] = Native
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
		end
		local label = phase == 3 and "npc.controls + native updates (64)" or "npc.lookup + legacy calls (64)"
		local close = Profile.section(label)
		local began = love.timer.getTime()
		for _ = 1, 64 do
			local h = assert(fixture.exports.npc(fixture.home, "IMPORTED"))
			if phase == 3 then
				assert(h:placeAt(1, 1, "right"))
				assert(h:canStep("right"))
				assert(h:setPassable(true))
				assert(h:stepNow("right"))
				assert(h:isMoving())
				for _ = 1, 16 do
					fixture.imported:update(fixture.ow.map, fixture.ow.entities)
				end
				assert(not h:isMoving())
				assert(h:setAppearance("ALT"))
			else
				h:position()
				h:face("left")
			end
		end
		if frame >= WARMUP then
			total = total + love.timer.getTime() - began
		end
		close()
		love.graphics.clear(0.03, 0.04, 0.06)
		love.graphics.present()
		if frame >= WARMUP then
			Profile.frame()
		end
		frame = frame + 1
		if frame == WINDOW + WARMUP then
			results[phase] = {
				mode = ({ "before", "native", "controls" })[phase],
				frames = WINDOW,
				operationMeanMs = total / WINDOW * 1000,
			}
			fixture.restoreRenderer()
			if phase == 3 then
				print("M6_NATIVE_RESULT " .. Json.encode({
					phases = results,
					renderer = love.graphics.getRendererInfo(),
					os = love.system.getOS(),
					arch = jit and jit.arch or "unknown",
					scope = "Actual LÖVE host, production API-2 loader, native Map collision and NPC updates over owned data; deterministic sprite construction, no rendered artwork or cartridge scene",
				}))
				return 0
			end
			phase = phase + 1
			start()
		end
	end
end
