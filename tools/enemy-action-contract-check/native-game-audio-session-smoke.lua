-- Development probe: real game/mounted-session teardown with owned initialized
-- game state. No Game:load, ROM boot, GPU, device, or normal filesystem writes.
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.modkit")
local root, backend, version, variant = unpack(arg)
local native = backend == "gen1"
local shared = variant == "shared"
-- CPU-only OS service for the actual launcher constructor. All filesystem
-- operations remain on tests.modkit's in-memory LOVE filesystem.
love.system = love.system
  or {
    getOS = function()
      return "Linux"
    end,
    getProcessorCount = function()
      return 1
    end,
  }
local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
local h = dofile(root .. "/tests/native_bgm/streams.lua").install(root, backend, version, f)
if shared then
  h.override("file")
end
local ids, calls = h.fanfares(), {}
for _, name in ipairs({ "music.started", "music.stopped" }) do
  f.e.api.events:on(name, function(event)
    calls[#calls + 1] = { name = name, song = event.song }
  end)
end
require("src.mods.Runtime").emit("music.started", { song = "OWNED_BEFORE_EXIT" })
assert(#calls == 1, "old public listener is live before teardown")
local runner = h.start({
  { "playbgm", h.ids[2], 1 },
  { "savebgm", h.ids[3] },
  { "playfanfare", ids[1] },
  { "waitfanfare" },
  { "end" },
})
h.update()
assert(runner:isRunning(), "old fanfare VM must be waiting before real session exit")
local teardown = {}
if native then
  local Game = dofile("src/core/Game3.lua")
  local game = Game.new()
  game.data, game.mods, game.session = f.data, f.result.loader, require("src.core.game3.runtime").session
  local lifecycle = require("src.core.SessionLifecycle")
  lifecycle.endGameSession(game)
  assert(
    game.data == nil and game.mods == nil and game.session == nil,
    "actual Game3:reset must complete, including its final holder release"
  )
  teardown.gameReset = true
  lifecycle.endMountedSession(version)
  teardown.mountedSessionEnded = true
else
  -- Load the actual main chunk without love.load: it registers the real
  -- launcher return closure. Supply its current Game through the closure's
  -- existing upvalue; teardown and launcher construction remain production.
  dofile("main.lua")
  local shell = require("src.core.HostShell")
  local hook
  for index = 1, 20 do
    local name, value = debug.getupvalue(shell.toLauncher, index)
    if not name then
      break
    end
    if name == "launcherHook" then
      hook = value
      break
    end
  end
  assert(type(hook) == "function", "actual main launcher hook registered")
  local found = false
  for index = 1, 30 do
    local name = debug.getupvalue(hook, index)
    if not name then
      break
    end
    if name == "Game" then
      debug.setupvalue(hook, index, f.game)
      found = true
    end
  end
  assert(found, "main owns the initialized old Game")
  local Game = dofile("src/core/Game.lua")
  Game.returnToLauncher(f.game)
  for index = 1, 30 do
    local name, value = debug.getupvalue(hook, index)
    if not name then
      break
    end
    if name == "Game" then
      assert(value == nil, "main releases old Game")
    end
    if name == "Importer" then
      assert(
        type(value) == "table" and value.launcher == true,
        "actual production launcher construction completed"
      )
      teardown.launcherConstructed = true
    end
  end
  assert(teardown.launcherConstructed)
  teardown.gameReleased = true
end
if native then
  runner:tick()
else
  runner:update()
end
assert(not runner:isRunning(), "real session exit finishes the old audio VM")
local Runtime = require("src.mods.Runtime")
local oldCalls = #calls
Runtime.emit("music.started", { song = "OWNED_AFTER_EXIT" })
Runtime.emit("music.stopped", { song = "OWNED_AFTER_EXIT" })
assert(#calls == oldCalls, "old public mod listeners must be detached before fresh entry")
local function oldInventory()
  local state = h.state()
  for _, voice in ipairs(state.native.voices) do
    assert(voice.playing == false, "old static Source remains stopped")
  end
  for _, queue in ipairs(state.queues) do
    assert(queue.playing == false, "old native queue remains stopped")
  end
  -- h.state().native also reads the process's current controller, which may
  -- already belong to the fresh session. Only these hardware lists retain
  -- the actual old Source objects across entry.
  return { staticSources = state.native.voices, queues = state.queues }
end
local frames = { { phase = "after-exit", old = oldInventory(), controller = h.state().native } }
-- main.bootGame invalidates the asset bus before loading the next Game.
-- Verify this production entry stage before fixture close/install can reset
-- any music state and conceal a saved/map-song leak.
require("src.render.Assets").invalidate()
local entryState = h.state().native
assert(
  entryState.savedSong == nil and entryState.mapSong == nil,
  "the production cache-entry stage releases previous map/saved music"
)
frames[#frames + 1] = { phase = "before-entry", old = oldInventory(), controller = entryState }
-- Observe source retirement before fixture restoration can stop anything.
-- Fresh entry loads the same public API-3 consumer through a new real Loader.
h.close()
f.close()
local fresh = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
local nextAudio = dofile(root .. "/tests/native_bgm/streams.lua").install(root, backend, version, fresh)
local freshCalls = 0
fresh.e.api.events:on("music.started", function()
  freshCalls = freshCalls + 1
end)
local nextIds = nextAudio.fanfares()
local nextRunner = nextAudio.start({ { "playfanfare", nextIds[2] }, { "waitfanfare" }, { "end" } })
for tick = 0, 6 do
  if tick > 0 then
    nextAudio.update()
    if native then
      nextRunner:tick()
    else
      nextRunner:update()
    end
  end
  Runtime.emit("music.started", { song = "OWNED_FRESH_ENTRY" })
  assert(freshCalls == tick + 1, "fresh public mod listener is installed and runs exactly once")
  assert(#calls == oldCalls, "new mod session cannot revive old listeners")
  if native then
    runner:tick()
  else
    runner:update()
  end
  assert(not runner:isRunning(), "new session cannot revive the old VM")
  assert(nextAudio.state().native.savedSong == nil, "previous session's saved song cannot leak")
  frames[#frames + 1] = {
    phase = "fresh",
    tick = tick,
    old = oldInventory(),
    current = nextAudio.state(),
    fanfare = nextAudio.fanfareState(nextIds),
    running = nextRunner:isRunning(),
  }
end
assert(not nextRunner:isRunning(), "fresh session fanfare wait completes")
nextAudio.close()
fresh.close()
print("NATIVE_GAME_AUDIO_SESSION " .. require("src.link.Json").encode({
  backend = backend,
  version = version,
  variant = variant,
  teardown = teardown,
  frames = frames,
  oldCallbacks = calls,
  oldCallbacksAfterExit = oldCalls,
  freshCallbacks = freshCalls,
}))
