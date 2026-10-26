local T = require("tests.harness")
love = require("tests.love_stub")
local Version = require("src.core.GameVersion")
local Performance = require("src.core.Performance")
local P = require("src.render.PaletteFX")
local Renderer = require("src.render.Renderer")
local base = { { 255, 240, 220 }, { 180, 150, 120 }, { 80, 50, 30 }, { 5, 3, 1 } }
local function shader()
	local records = {}
	local methods = {
		typeOf = function(_, kind)
			return kind == "Shader"
		end,
		send = function(_, name, value)
			records[#records + 1] = { name, { value[1], value[2], value[3] }, value }
		end,
	}
	local object = methods
	if newproxy then
		object = newproxy(true)
		getmetatable(object).__index = methods
	end
	return object, records
end
for _, version in ipairs({ "red", "gold" }) do
	Version.set(version)
	for _, mode in ipairs(P.MODES) do
		P.mode = mode
		for _, map in ipairs({ false, { [0] = 0, [1] = 3, [2] = 1, [3] = 2 } }) do
			P.setShadeMap(map or nil)
			local expected = P.effectiveColors(base)
			local sh, records = shader()
			local state = { rows = { {}, {}, {}, {} } }
			P._sendColorsInBatch(sh, base, state)
			for i = 1, 4 do
				T.eq(records[i][1], "c" .. (i - 1), "uniform names remain unchanged")
				for channel = 1, 3 do
					T.eq(records[i][2][channel], expected[i][channel] / 255, version .. "/" .. mode .. " row mapping")
				end
			end
			P._sendColorsInBatch(sh, base, state)
			T.eq(#records, 4, "unchanged twelve floats skip redundant uploads")
		end
	end
end
Version.set("red")
P.mode = "gbc"
P.setShadeMap(nil)
local sh, records = shader()
local state = { rows = { {}, {}, {}, {} } }
P._sendColorsInBatch(sh, base, state)
base[2][1] = 181
P._sendColorsInBatch(sh, base, state)
T.eq(#records, 5, "in-place palette mutation invalidates the affected row")
T.eq(records[5][1], "c1", "only changed row is uploaded")
local custom = P.effectiveColors
P.effectiveColors = function(c)
	return { c[4], c[3], c[2], c[1] }
end
P._sendColorsInBatch(sh, base, state)
T.eq(records[#records][2][1], base[1][1] / 255, "public effectiveColors override is honored")
P.effectiveColors = custom
local oldPermute = P.permute
P.permute = function(c)
	return { c[4], c[3], c[2], c[1] }
end
P._sendColorsInBatch(sh, base, state)
T.eq(records[#records][2][1], base[1][1] / 255, "public permute override is honored")
P.permute = oldPermute
local plain, plainRecords = shader()
Performance.paletteZoneCache = true
P.sendColors(plain, base)
P.sendColors(plain, base)
T.eq(#plainRecords, 8, "public calls always resend after possible external shader writes")
local fake = {
	send = function(self, name, value)
		self[#self + 1] = value
	end,
}
P.sendColors(fake, base)
P.sendColors(fake, base)
T.check(fake[1] ~= fake[5], "consumer-provided send callbacks retain fresh public vectors")
local shaderFactory = P.shader
P.shader = function()
	return sh
end
local zones = {
	{ x = 0, y = 0, w = 16, h = 16, colors = base },
	{ x = 0, y = 0, w = 16, h = 16, colors = base },
	{
		x = 0,
		y = 0,
		w = 16,
		h = 16,
		colors = base,
	},
}
local canvas = love.graphics.newCanvas(16, 16)
local function blit()
	Renderer:blitCanvas(canvas, 1, 1, zones, 1, 1, 0, 0, 0, 0, 16, 16, 1, 1)
end
records = {}
local count = 0
local sender = P.sendColors
P.sendColors = function(...)
	count = count + 1
	return sender(...)
end
blit()
T.eq(count, 3, "public sendColors wrapper is still called for every original zone")
P.sendColors = sender
local real, sent = shader()
P.shader = function()
	return real
end
Performance.paletteZoneCache = true
blit()
local perBlit = newproxy and 4 or 12
T.eq(#sent, perBlit, "native contiguous blit skips repeated rows only on real shader-shaped userdata")
real:send("c0", { 0.4, 0.5, 0.6 })
blit()
T.eq(#sent, perBlit * 2 + 1, "new blit resets validity after external raw shader writes")
T.same(
	sent[perBlit + 2][2],
	{ base[1][1] / 255, base[1][2] / 255, base[1][3] / 255 },
	"first upload restores the native palette"
)
Performance.paletteZoneCache = false
local before = #sent
blit()
T.eq(#sent - before, 12, "P5 off restores four sends for every zone")
Performance.paletteZoneCache = true
local oldDraw = love.graphics.draw
love.graphics.draw = function(...)
	return oldDraw(...)
end
before = #sent
blit()
T.eq(#sent - before, 12, "a graphics callback override disables cache assumptions")
love.graphics.draw = oldDraw
P.shader = shaderFactory
local q = {
	setViewport = function(self, ...)
		self.viewport = { ... }
	end,
}
local draw = love.graphics.draw
local drawn
love.graphics.draw = function(...)
	drawn = { ... }
end
Renderer:_drawZoneQuad(q, canvas, 2, 2, 2, 2, 0, 0, 3, 5, 20, 20, 1, 1, { x = 0, y = 0, w = 16, h = 16 })
T.same(q.viewport, { 1.5, 2.5, 10, 10, 16, 16 }, "quad viewport crops source coordinates to the original clip")
T.eq(drawn[3], 3, "cropped quad retains horizontal origin mapping")
T.eq(drawn[4], 5, "cropped quad retains vertical origin mapping")
love.graphics.draw = draw
T.finish("palette uploads and zone quads")
