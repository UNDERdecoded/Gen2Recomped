local T = require("tests.harness")
love = require("tests.love_stub")
local Performance = require("src.core.Performance")
local Version = require("src.core.GameVersion")
Version.set("red")
local Renderer = require("src.render.Renderer")
local Game = require("src.core.Game")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local Stack = require("src.core.StateStack")
local w, h = 640, 480
love.graphics.getDimensions = function()
	return w, h
end
love.graphics.getPixelDimensions = function()
	return w, h
end
Renderer:init()
local function present(private)
	Renderer:beginFrame()
	if private then
		return Renderer:_endFrameForEngine()
	end
	return Renderer:endFrame()
end
for _, enabled in ipairs({ false, true }) do
	Performance.hotPathHoist = enabled
	w, h = 640, 480
	local first = present()
	local oldUI = Renderer.uiPresentation
	w, h = 800, 600
	local second = present()
	T.check(first ~= second, "public endFrame returns detached records with P3 " .. tostring(enabled))
	T.eq(first.width, 640, "retained public viewport keeps its original width")
	T.eq(second.width, 800, "next public viewport has current width")
	T.eq(oldUI == Renderer.uiPresentation, enabled, "existing renderer-owned UI view follows the switch")
end
Performance.hotPathHoist = true
local first = present(true)
T.eq(present(true), first, "unobserved native result can reuse private storage")
local foreign = { custom = true }
Renderer.uiPresentation = foreign
present()
T.check(Renderer.uiPresentation ~= foreign, "engine does not reuse a replacement owned by a mod")
T.eq(foreign.x, nil, "replacement supplied by a mod is not mutated")
local realBlit = Renderer.blitCanvas
local forwarded
Renderer.blitCanvas = function(self, ...)
	forwarded = { self, ... }
	return "forwarded"
end
local canvas, zones = {}, {}
T.eq(
	Renderer:_blitAtDpi(1.5, 2, canvas, 3, 4, zones, 5, 6, 7, 8, 9, 10, 11, 12),
	"forwarded",
	"hoisted blit preserves the public return"
)
T.eq(forwarded[1], Renderer, "hoisted blit preserves the public receiver")
T.eq(forwarded[2], canvas, "hoisted blit preserves canvas identity")
T.eq(forwarded[5], zones, "hoisted blit preserves zone identity")
T.eq(forwarded[14], 1.5, "hoisted blit keeps horizontal DPI in the original position")
T.eq(forwarded[15], 2, "hoisted blit keeps vertical DPI in the original position")
Renderer.blitCanvas = realBlit

local hooks = Hooks.new()
Runtime.hooks = hooks
local state = { draw = function() end }
local stack = setmetatable({ states = { state } }, { __index = Stack })
local fake = setmetatable(
	{ stack = stack, overworld = {}, data = require("tests.modkit.fixtures").fresh(), save = { options = {} } },
	{ __index = Game }
)
local received = {}
hooks:wrap("render.hud", function(nextFn, game, viewport)
	T.eq(game, fake, "HUD receives the original game")
	received[#received + 1] = viewport
	return nextFn(game, viewport)
end, 0, "retention")
w, h = 640, 480
fake:_draw()
w, h = 800, 600
fake:_draw()
T.check(received[1] ~= received[2], "HUD never receives recycled private results")
T.eq(received[1].width, 640, "retained HUD viewport remains unchanged")
T.eq(received[2].width, 800, "next HUD viewport receives current geometry")
local original = Renderer.endFrame
local wrapped, offered = 0, nil
Renderer.endFrame = function(self, ...)
	wrapped = wrapped + 1
	offered = original(self, ...)
	offered.modField = "kept"
	return offered
end
fake:_draw()
T.eq(wrapped, 1, "existing public endFrame wrapper is not bypassed")
T.eq(received[#received], offered, "wrapper record is forwarded without replacing its identity")
T.eq(received[#received].modField, "kept", "wrapper-added fields remain available")
Renderer.endFrame = original
hooks:removeOwner("retention")
received = {}
local installed = false
hooks:wrap("render.compose", function(nextFn, ...)
	if not installed then
		installed = true
		hooks:wrap("render.hud", function(nextHud, game, viewport)
			received[#received + 1] = viewport
			return nextHud(game, viewport)
		end, 0, "late-hud")
	end
	return nextFn(...)
end, 0, "late-compose")
w, h = 640, 480
fake:_draw()
w, h = 800, 600
fake:_draw()
T.check(received[1] ~= received[2], "a HUD registered during compose also receives detached records")
T.eq(received[1].width, 640, "late registration does not leak mutable native metrics")
hooks:removeOwner("late-hud")
hooks:removeOwner("late-compose")
-- Window UI is absent from this engine base; the fork exercises that path.
T.finish()
