-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Real imported content and native Game/Overworld; fixed 60 Hz simulation.
return function(game)
  local U = require("tests.drivers.util")
  local Json = require("src.link.Json")
  local FP = require("src.core.FrameProfile")
  local P = require("src.core.Performance")
  local Logger = require("src.core.Logger")
  local mode = assert(os.getenv("PERF_MODE"))
  local out = assert(os.getenv("PERF_OUT"))
  assert(love.filesystem.getIdentity():match("^oasc%-gen2recomp%-qa%-perf%-"))
  local renderer, api, vendor, device = love.graphics.getRendererInfo()
  assert(renderer:lower() == (os.getenv("PERF_BACKEND") or "metal") and not device:lower():find("software"))
  local report = {
    passed = false,
    mode = mode,
    edition = "emerald",
    runtime = { love.getVersion() },
    architecture = jit.arch,
    gpu = { renderer = renderer, api = api, vendor = vendor, device = device },
    simulationHz = 60,
    phases = {},
    timing = "FrameProfile wall time; GPU submission, no completion fence; no screenshots inside intervals",
    limitations = {
      "sequential off/on samples; no causal whole-game speedup claim",
      "Emerald does not exercise DS Nitro synthesis or GB palette uniforms",
      "LOW native UI quad menus are covered by their separate allocation fixture",
    },
    measurement = { warmupNative = 240, warmupVoxel = 1500, perSwitchWarmup = 180, samples = 240, profileWindow = 120 },
  }
  U.freshSave(game)
  game.save.options.performance = "high"
  game.save.options.fpsCap = 240
  game.save.options.pipelines = game.save.options.pipelines or {}
  game.save.options.pipelines.voxel = mode == "voxel" and 3 or 0
  game:applyOptions()
  local _, _, flags = love.window.getMode()
  flags.vsync = 0
  flags.highdpi = true
  assert(love.window.setMode(640, 480, flags))
  require("src.core.FrameCap").apply(240)
  U.teleport(
    game,
    os.getenv("PERF_MAP") or "MAP_G00_N15",
    tonumber(os.getenv("PERF_X")) or 10,
    tonumber(os.getenv("PERF_Y")) or 10,
    "down"
  )
  local V
  if mode == "voxel" then
    V = assert(_G.__DRAMATIC_SHAPE_V, "native loader did not load the unmodified mod")
    V.require("Water").setting:sync("full")
    V.require("RenderScale").setting:sync(1)
    V.require("DayNight").setting:sync("day")
  end
  U.wait(mode == "voxel" and 1500 or 240)
  if V then
    local mesher = V.require("ChunkMesher")
    local deadline, waited = love.timer.getTime() + 180, 0
    while
      mesher.pending() > 0 or not (mesher.peek(game.overworld.map, false) or mesher.peek(game.overworld.map, true))
    do
      assert(not mesher.buildFailure(game.overworld.map.id), "native terrain build failed")
      assert(love.timer.getTime() < deadline, "native terrain did not become quiescent")
      U.wait(60)
      waited = waited + 60
    end
    report.measurement.readyWaitFrames = waited
    U.wait(240)
  end
  local active
  local world, worldUpdate = game.overworld, game.overworld.update
  world.update = function(self, ...)
    worldUpdate(self, ...)
    if active and active.card == "P7" then
      -- Keep native simulation/draw, and exercise camera-driven invalidation.
      self.camera.x = self.camera.x + #active.presentMs * 0.25
    end
  end
  local modPerf, count
  if V then
    modPerf = V.require("Perf")
    count = modPerf.count
    modPerf.count = function(name, n)
      if active and name:sub(1, 7) == "shadow." then
        active.shadowCasts[name] = (active.shadowCasts[name] or 0) + (n or 1)
      end
      return count(name, n)
    end
  end
  local present = love.graphics.present
  love.graphics.present = function(...)
    local t = love.timer.getTime()
    local result = present(...)
    if active then
      active.presentMs[#active.presentMs + 1] = (love.timer.getTime() - t) * 1000
      if active.previousPresent then
        active.intervalsMs[#active.intervalsMs + 1] = (t - active.previousPresent) * 1000
      end
      active.previousPresent = t
    end
    return result
  end
  local original = Logger.report
  Logger.report = function(fmt, ...)
    if active then
      local args = { ... }
      if fmt:match("^frame profile:") then
        active.windows = active.windows + 1
      end
      if fmt:find("%-34s", 1, true) then
        local name, value = args[1], args[2]
        local row = active.sections[name] or { sumMs = 0, windows = 0 }
        row.sumMs = row.sumMs + value
        row.windows = row.windows + 1
        active.sections[name] = row
      end
    end
    return original(fmt, ...)
  end
  local function setCard(card, on)
    if card == "P1" then
      require("src.core.FrameCap").vsyncPacing = on
    elseif card == "P2" then
      P.gcBudget = on
      collectgarbage("setpause", on and 120 or 200)
      collectgarbage("setstepmul", on and 300 or 200)
    elseif card == "P3" then
      P.hotPathHoist = on
    elseif card == "P4" then
      P.worldDrawHoist = on
    elseif card == "P5" then
      P.paletteZoneCache = on
    elseif card == "P6" then
      P.audioWorkerOptimization = on
    elseif card == "P7" then
      V.shadowWorldAnchor = on
      V.require("ShadowMap").invalidate()
    elseif card == "P8" then
      V.renderBudget = on
    elseif card == "P9" then
      P.lowTierBudget = on
      game.save.options.performance = "low"
      game:applyOptions()
      require("src.core.FrameCap").apply(240)
    end
  end
  local cards = mode == "native" and { "P1", "P2", "P3", "P4", "P5", "P6", "P9" } or { "P7", "P8" }
  for _, card in ipairs(cards) do
    for _, on in ipairs({ false, true }) do
      setCard(card, on)
      local paced = card == "P1"
      love.window.setVSync(paced and 1 or 0)
      require("src.core.FrameCap").apply(paced and 60 or 240)
      U.wait(180)
      collectgarbage("collect")
      active = {
        card = card,
        enabled = on,
        windows = 0,
        sections = {},
        vsync = love.window.getVSync(),
        presentMs = {},
        intervalsMs = {},
        fpsCap = require("src.core.FrameCap").current,
        shadowCasts = {},
        cameraMotion = card == "P7" and "controlled 0.25 world-pixel pan per update" or "native camera follow",
      }
      FP.setEnabled(true)
      FP.reset()
      local start = love.timer.getTime()
      U.wait(240)
      FP.setEnabled(false)
      local phase = active
      active = nil
      phase.elapsedSeconds = love.timer.getTime() - start
      assert(phase.windows == 2 and #phase.presentMs == 240, "missing measured frames or FrameProfile windows")
      assert(phase.sections["frame pacing: sleep"], "native pacing path was bypassed")
      if card == "P7" then
        assert(
          phase.sections["    voxel: sun pass"] and phase.sections["    voxel: sun pass"].windows == 2,
          "shadow measurement reached an unready fallback frame"
        )
        assert(next(phase.shadowCasts), "native shadow passes did not execute")
      end
      for _, row in pairs(phase.sections) do
        row.meanMs = row.sumMs / row.windows
        row.sumMs = nil
      end
      local function distribution(values)
        table.sort(values)
        local sum = 0
        for _, v in ipairs(values) do
          sum = sum + v
        end
        return {
          samples = #values,
          meanMs = sum / #values,
          p50Ms = values[math.ceil(#values * 0.5)],
          p95Ms = values[math.ceil(#values * 0.95)],
          p99Ms = values[math.ceil(#values * 0.99)],
        }
      end
      phase.present = distribution(phase.presentMs)
      phase.intervals = distribution(phase.intervalsMs)
      phase.presentMs, phase.intervalsMs, phase.previousPresent = nil, nil, nil
      phase.world = game.overworld.map.id
      phase.stack = require("src.core.StateStack").describe(game.stack:top())
      if V then
        phase.voxelLevel = V.require("VoxelState").level
        assert(phase.voxelLevel > 0)
      end
      report.phases[#report.phases + 1] = phase
      print("PERF_PHASE", card, tostring(on), phase.elapsedSeconds)
    end
    setCard(card, true)
  end
  love.graphics.present = present
  world.update = worldUpdate
  if modPerf then
    modPerf.count = count
  end
  Logger.report = original
  report.passed = true
  local f = assert(io.open(out .. "/report.json", "w"))
  f:write(Json.encode(report))
  f:close()
end
