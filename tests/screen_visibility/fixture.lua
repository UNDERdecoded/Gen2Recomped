local M = {}
function M.new(root, backend, version, api, format, noMod)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local generation = Version.generation()
  local files = {}
  for _, path in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_screen_visibility/" .. path, "rb"))
    files["mods/portable_screen_visibility/" .. path] = file:read("*a")
    file:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/portable_screen_visibility/manifest.json"]))
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_screen_visibility/manifest.json"] = Json.encode(manifest)
  local data = T.fixtures.fresh()
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_screen_visibility" }, {
    data = data,
    generation = generation,
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  local StateStack = require("src.core.StateStack")
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local module = backend == "gen1" and generation == 2 and "src.core.Game2" or "src.core.Game"
  local Game = require(module)
  local g = setmetatable({
    stack = stack,
    mods = result.loader,
    data = data,
    save = { options = {} },
    inFillBoot = function()
      return false
    end,
    letterbox = function() end,
    paintBattleSurround = function() end,
  }, { __index = Game })
  local trace, zones, worldZones, clearWorld = {}, nil, nil, nil
  local externalDraws = 0
  local Renderer = require("src.render.Renderer")
  local Touch = require("src.core.TouchControls")
  local saved = { Renderer.setUISize, Renderer.uiSize, Renderer.beginFrame, Renderer.endFrame, Touch.draw }
  local width, height = Renderer.WIDTH, Renderer.HEIGHT
  Renderer.setUISize = function(_, w, h)
    width, height = w, h
  end
  Renderer.uiSize = function()
    return width, height
  end
  Renderer.beginFrame = function(_, world)
    clearWorld = world
  end
  Renderer.endFrame = function(_, z, wz)
    zones, worldZones = z, wz
    return {}
  end
  Touch.draw = function() end
  local Input = require("src.core.Input")
  Input:init()
  local function state(id, opaque)
    return {
      screenId = id,
      isOpaque = opaque,
      updates = 0,
      presses = 0,
      palettes = 0,
      draw = function()
        trace[#trace + 1] = id
      end,
      update = function(self)
        self.updates = self.updates + 1
        if Input:wasPressed("a") then
          self.presses = self.presses + 1
        end
      end,
      sgbPalettes = function(self)
        self.palettes = self.palettes + 1
        return id .. " zones"
      end,
    }
  end
  local base, menu, overlay = state("Base", true), state("BagMenu", true), state("TextBox", false)
  g.overworld = base
  g.world = {
    map = {},
    fitScale = function()
      return 4
    end,
    draw = function()
      externalDraws = externalDraws + 1
    end,
  }
  local function frame(states)
    trace, zones, worldZones, clearWorld = {}, nil, nil, nil
    externalDraws = 0
    stack.states = states
    if backend == "gen1" and generation == 2 then
      g:drawScene(640, 576)
    elseif backend == "gen1" then
      g:draw()
    else
      g:_draw()
    end
    return trace, zones, worldZones, clearWorld
  end
  local exports = result.loader.exports.portable_screen_visibility
  return {
    T = T,
    result = result,
    game = g,
    stack = stack,
    base = base,
    menu = menu,
    overlay = overlay,
    stackFrame = function(states)
      trace = {}
      stack.states = states
      stack:draw()
      return trace
    end,
    frame = frame,
    state = state,
    input = Input,
    backend = backend,
    generation = generation,
    palettePath = backend ~= "gen1" or generation == 1,
    stateIdentity = backend ~= "gen1" or api < 3,
    externalDraws = function()
      return externalDraws
    end,
    api = api,
    format = format,
    exports = exports,
    public = exports and exports.api,
    close = function()
      Renderer.setUISize, Renderer.uiSize, Renderer.beginFrame, Renderer.endFrame, Touch.draw =
        saved[1], saved[2], saved[3], saved[4], saved[5]
      if result.loader._closeModInput then
        result.loader:_closeModInput()
      end
      result.release()
    end,
  }
end
return M
