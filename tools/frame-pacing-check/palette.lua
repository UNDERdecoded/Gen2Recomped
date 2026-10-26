local Version = require("src.core.GameVersion")
local Performance = require("src.core.Performance")
local Renderer = require("src.render.Renderer")
local Palette = require("src.render.PaletteFX")
local Profile = require("src.core.FrameProfile")
local Cap = require("src.core.FrameCap")
local Json = require("src.link.Json")
local g = love.graphics
local colors = { { 255, 230, 200 }, { 180, 120, 80 }, { 50, 100, 150 }, { 5, 10, 15 } }
local other = { { 210, 240, 180 }, { 110, 160, 90 }, { 20, 70, 120 }, { 0, 0, 0 } }
local pixels = love.image.newImageData(32, 24)
pixels:mapPixel(function(x, y)
	local shade = (math.floor(x / 2) + math.floor(y / 3)) % 4 / 3
	return shade, shade, shade, (x + y) % 7 == 0 and 0.5 or 1
end)
local image = g.newImage(pixels)
image:setFilter("nearest", "nearest")
local function makeSource(density, filter)
	local source = g.newCanvas(32, 24, { dpiscale = density })
	source:setFilter(filter or "nearest", filter or "nearest")
	g.setCanvas(source)
	g.origin()
	g.clear(0, 0, 0, 0)
	g.setColor(1, 1, 1, 1)
	g.setBlendMode("replace")
	g.draw(image)
	g.setBlendMode("alpha")
	return source
end
local source = makeSource(1)
local highSource = makeSource(2)
local linearSource = makeSource(1, "linear")
local zones = {
	{ x = 0, y = 0, w = 32, h = 8, colors = colors },
	{ x = 0, y = 8, w = 32, h = 8, colors = colors },
	{ x = 0, y = 16, w = 32, h = 8, colors = colors },
	{ x = 5.2, y = 4.1, w = 15.6, h = 10.7, colors = other },
	{ x = 10.5, y = 9.5, w = 5.2, h = 7.3, colors = false },
	{ x = -3, y = -4, w = 8, h = 6, colors = colors },
	{ x = 30, y = 21, w = 8, h = 6, colors = colors },
}
local checked, quadCases, fallbackCases = 0, 0, 0
local cases = {}
for _, density in ipairs({ 1, 1.25, 2.625 }) do
	for _, scale in ipairs({ 1, 1.75, 2.625 }) do
		for _, origin in ipairs({ 0, 3.2 }) do
			cases[#cases + 1] = { density = density, scale = scale, x = origin, y = origin + 1.1 }
		end
	end
end
for _, kind in ipairs({ "anisotropic", "translate", "rotate", "highSource", "linearSource", "flip" }) do
	cases[#cases + 1] = { density = 1.25, scale = 1.75, x = 3.2, y = 4.1, kind = kind }
end
for _, density in ipairs({ 1, 1.25, 2.625 }) do
	cases[#cases + 1] = { density = density, scale = 3 / density, x = 2 / density, y = 3 / density }
end
local originalShader = Palette.shader
local function pixelChecks()
	for _, version in ipairs({ "red", "gold" }) do
		Version.set(version)
		for _, mode in ipairs({ "gbc", "gbc_inv", "og_inv", "classic" }) do
			Palette.mode = mode
			for _, shade in ipairs({ false, { [0] = 2, [1] = 3, [2] = 3, [3] = 3 } }) do
				Palette.setShadeMap(shade or nil)
				for index, c in ipairs(cases) do
					local target = g.newCanvas(96, 80, { dpiscale = c.density })
					local selected = c.kind == "highSource" and highSource
						or c.kind == "linearSource" and linearSource
						or source
					local xScale = c.kind == "flip" and -c.scale or c.scale
					local dpiY = c.kind == "anisotropic" and c.density * 1.05 or c.density
					local before
					local quadCount = 0
					for _, enabled in ipairs({ false, true }) do
						Performance.paletteZoneCache = enabled
						g.setCanvas(target)
						g.origin()
						g.clear(0.1, 0.2, 0.3, 1)
						g.setColor(1, 1, 1, 1)
						if c.kind == "translate" then
							g.translate(1.2, 2.3)
						end
						if c.kind == "rotate" then
							g.rotate(0.07)
						end
						local actualDraw = Renderer._drawZoneQuad
						Renderer._drawZoneQuad = function(self, ...)
							quadCount = quadCount + 1
							return actualDraw(self, ...)
						end
						Renderer:blitCanvas(
							selected,
							xScale,
							c.scale,
							zones,
							c.scale,
							c.scale,
							c.x,
							c.y,
							2.3,
							3.1,
							75.7,
							58.8,
							c.density,
							dpiY
						)
						Renderer._drawZoneQuad = actualDraw
						g.setCanvas()
						g.origin()
						local data = target:newImageData()
						local bytes = data:getString()
						data:release()
						if not enabled then
							before = bytes
						else
							if before ~= bytes then
								local changed = 0
								for i = 1, #bytes do
									if bytes:byte(i) ~= before:byte(i) then
										changed = changed + 1
									end
								end
								error(
									("zone pixel mismatch %s/%s/shade=%s/case=%d/%s, %d bytes"):format(
										version,
										mode,
										tostring(shade ~= false),
										index,
										c.kind or "native",
										changed
									)
								)
							end
						end
					end
					target:release()
					checked = checked + 1
					if quadCount > 0 then
						quadCases = quadCases + 1
					else
						fallbackCases = fallbackCases + 1
					end
				end
			end
		end
	end
	assert(quadCases > 0 and fallbackCases > 0, "both optimized and compatibility geometry paths must be exercised")
	Palette.mode = "gbc"
	Palette.setShadeMap(nil)
	Version.set("red")
end
local phase, frame, deadline, started, cpuStarted = 1, 0, 0, 0, 0
local WARMUP, WINDOW = 120, 120
local drawTotal, drawMax, heapStart = 0, 0, 0
local results = {}
local _, _, mode = love.window.getMode()
Cap.current = tonumber(mode.refreshrate) or 60
if Cap.current <= 0 then
	Cap.current = 60
end
Cap.vsyncPacing = true
local repeated = {}
for y = 0, 11 do
	for x = 0, 7 do
		repeated[#repeated + 1] = { x = x * 4, y = y * 2, w = 4, h = 2, colors = colors }
	end
end
local function draw()
	g.origin()
	g.clear(0.1, 0.2, 0.3, 1)
	g.setColor(1, 1, 1, 1)
	Renderer:blitCanvas(source, 4, 4, repeated, 4, 4, 32, 32, 32, 32, 128, 96, 1, 1)
	Profile.frame()
end
local function startPhase()
	Profile.setEnabled(false)
	Performance.paletteZoneCache = phase == 2
	collectgarbage("restart")
	frame, drawTotal, drawMax = 0, 0, 0
	deadline = love.timer.getTime()
end
local function finishPhase()
	results[phase] = {
		enabled = Performance.paletteZoneCache,
		frames = WINDOW,
		seconds = love.timer.getTime() - started,
		drawMeanMs = drawTotal / WINDOW * 1000,
		drawMaxMs = drawMax * 1000,
		processCpuMsPerFrame = (os.clock() - cpuStarted) / WINDOW * 1000,
		heapGrowthKiB = collectgarbage("count") - heapStart,
	}
	collectgarbage("restart")
	if phase == 2 then
		Palette.shader = originalShader
		print("P5_NATIVE_RESULT " .. Json.encode({
			os = love.system.getOS(),
			arch = jit and jit.arch or "unknown",
			renderer = g.getRendererInfo(),
			refresh = mode.refreshrate,
			vsync = love.window.getVSync(),
			cap = Cap.current,
			pixelCases = checked,
			quadCases = quadCases,
			fallbackCases = fallbackCases,
			zones = #repeated,
			phases = results,
			scope = "Exact GPU pixel comparisons over owned generated source; timed 96-zone native blits; GC stopped in measured windows, no ROM/mod/game scene",
		}))
		return true
	end
	phase = 2
	startPhase()
end
function love.run()
	pixelChecks()
	startPhase()
	return function()
		love.event.pump()
		for name in love.event.poll() do
			if name == "quit" then
				return 1
			end
		end
		if frame == WARMUP then
			collectgarbage("collect")
			collectgarbage("stop")
			Profile.setEnabled(true)
			heapStart = collectgarbage("count")
			started, cpuStarted = love.timer.getTime(), os.clock()
		end
		local before = love.timer.getTime()
		draw()
		if frame >= WARMUP then
			local elapsed = love.timer.getTime() - before
			drawTotal, drawMax = drawTotal + elapsed, math.max(drawMax, elapsed)
		end
		local close = Profile.section("present (GPU wait / vsync)")
		g.present()
		close()
		deadline = Cap.pace(love.timer, love.window, true, deadline)
		frame = frame + 1
		if frame == WARMUP + WINDOW and finishPhase() then
			return 0
		end
	end
end
