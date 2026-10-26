package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.modkit")
local root, backend, version = unpack(arg)
local native = backend == "gen1"
local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
local rows = {}
for _, case in ipairs({ "native-wait", "deferred-default", "replacement", "repeat", "new-bgm", "stop-bgm" }) do
  local h = dofile(root .. "/tests/native_bgm/streams.lua").install(root, backend, version, f)
  local ids = h.fanfares()
  assert(h.soundData.staticInputs == 0, "fanfare setup must not prewarm a static source")
  if native then
    assert(next(require("src.core.game3.audio")._fanfareSd) == nil, "native SoundData cache starts cold")
  end
  h.clear()
  h.update()
  local script = {}
  if case == "deferred-default" then
    script[#script + 1] = { "playbgm", h.ids[2], 0 }
  end
  script[#script + 1] = { "playfanfare", ids[1] }
  if case == "deferred-default" then
    script[#script + 1] = { "fadedefaultbgm" }
  end
  script[#script + 1] = { "waitfanfare" }
  script[#script + 1] = { "setvar", 0x4001, 1 }
  script[#script + 1] = { "end" }
  local runner = h.start(script)
  assert(h.soundData.staticInputs > 0, "public cold fanfare must create a source from userdata PCM")
  local frames, completed = {}, nil
  for tick = 0, 12 do
    h.tick(tick)
    if tick == 2 then
      local action
      if case == "replacement" then
        action = { "playfanfare", ids[2] }
      elseif case == "repeat" then
        action = { "playfanfare", ids[1] }
      elseif case == "new-bgm" then
        action = { "playbgm", h.ids[2], 0 }
      elseif case == "stop-bgm" then
        action = { "playbgm", 0, 0 }
      end
      if action then
        h.start({ action, { "end" } })
      end
    end
    if tick > 0 then
      if native then
        runner:tick()
      else
        runner:update()
      end
    end
    local state = h.state()
    state.fanfare = h.fanfareState(ids)
    state.tick, state.running, state.value = tick, runner:isRunning(), h.value(runner)
    if state.value == 1 then
      completed = completed or tick
    end
    frames[#frames + 1] = state
    h.update()
  end
  rows[#rows + 1] = {
    case = case,
    completed = completed,
    frames = frames,
    trace = h.trace(),
    coldFanfareSource = true,
  }
  h.close()
end
f.close()
print("NATIVE_FANFARE_STREAMS " .. require("src.link.Json").encode(rows))
