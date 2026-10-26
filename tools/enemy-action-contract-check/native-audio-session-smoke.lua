-- Owned audio-service teardown/re-entry, not the complete game/mod lifecycle.
-- Arguments: host checkout, backend, version. Native endSession and host reload
-- stay unchanged. Complete old queue inventories intentionally retain allocation differences.
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.modkit")
local root, backend, version = unpack(arg)
local native = backend == "gen1"
local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
local rows = {}
local function step(runner)
  if native then
    runner:tick()
  else
    runner:update()
  end
end
local function snapshot(h, ids, runner)
  local state = h.state().native
  state.physicalSong = nil
  return { state = state, fanfare = h.fanfareState(ids), running = runner:isRunning() }
end
for _, shared in ipairs({ false, true }) do
  for _, fanfare in ipairs({ false, true }) do
    local h = dofile(root .. "/tests/native_bgm/streams.lua").install(root, backend, version, f)
    if shared then
      h.override("file")
    end
    local ids = h.fanfares()
    local script = { { "playbgm", h.ids[2], 1 }, { "savebgm", h.ids[3] } }
    if fanfare then
      script[#script + 1] = { "playfanfare", ids[1] }
      script[#script + 1] = { "waitfanfare" }
    end
    script[#script + 1] = { "end" }
    local runner = h.start(script)
    h.update()
    local frames = { snapshot(h, ids, runner) }
    if native then
      require("src.core.game3.audio").endSession()
    else
      require("src.core.Music").reload()
    end
    step(runner)
    frames[#frames + 1] = snapshot(h, ids, runner)
    assert(not runner:isRunning(), "old VM must finish at the ended audio session")
    h.close()
    local fresh = dofile(root .. "/tests/native_bgm/streams.lua").install(root, backend, version, f)
    local freshIds = fresh.fanfares()
    local nextRunner = fresh.start({ { "playfanfare", freshIds[2] }, { "waitfanfare" }, { "end" } })
    local function observeFresh(tick)
      local frame = snapshot(fresh, freshIds, nextRunner)
      frame.tick, frame.oldSources, frame.oldQueues = tick, {}, {}
      for _, voice in ipairs(h.state().native.voices) do
        frame.oldSources[#frame.oldSources + 1] = voice.playing
        assert(voice.playing == false, "old static Source cannot resume in the new session")
      end
      for _, voice in ipairs(h.state().queues) do
        frame.oldQueues[#frame.oldQueues + 1] = voice.playing
        assert(voice.playing == false, "old native queue cannot resume in the new session")
      end
      return frame
    end
    frames[#frames + 1] = observeFresh(0)
    assert(not runner:isRunning(), "fresh fanfare cannot revive old VM")
    for tick = 1, 6 do
      fresh.update()
      step(nextRunner)
      frames[#frames + 1] = observeFresh(tick)
    end
    assert(not nextRunner:isRunning(), "fresh session wait must complete")
    rows[#rows + 1] =
      { case = (shared and "shared" or "native") .. (fanfare and "-fanfare" or "-bgm"), frames = frames }
    fresh.close()
  end
end
f.close()
print("NATIVE_AUDIO_SESSION_OBSERVATIONS " .. require("src.link.Json").encode(rows))
