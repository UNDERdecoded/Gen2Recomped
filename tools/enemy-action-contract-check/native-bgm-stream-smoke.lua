package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.modkit")
local root, backend, version = unpack(arg)
local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
local cases = {
  { name = "startup", ticks = 3 },
  { name = "finite-carrier", ticks = 3, finite = true },
  { name = "outgoing", ticks = 80, command = "fadeoutbgm" },
  { name = "incoming", ticks = 80, command = "fadeinbgm" },
  { name = "restart-mid-out", ticks = 80, command = "fadeoutbgm", replaceAt = 3 },
  { name = "default", ticks = 144, default = true },
  { name = "file-override-default", ticks = 144, default = true, override = "file" },
  { name = "chip-override-default", ticks = 144, default = true, override = "chip" },
  { name = "option-outgoing", ticks = 80, command = "fadeoutbgm", options = true },
}
local rows = {}
for _, case in ipairs(cases) do
  local h = dofile(root .. "/tests/native_bgm/streams.lua").install(root, backend, version, f, case)
  if case.override then
    h.override(case.override)
  end
  local script = {}
  if case.default then
    script[#script + 1] = { "playbgm", h.ids[2], 1 }
    script[#script + 1] = { "fadedefaultbgm" }
  elseif case.command then
    script[#script + 1] = { case.command, 4 }
  end
  script[#script + 1] = { "end" }
  local runner = h.start(script)
  local frames = {}
  for tick = 0, case.ticks do
    h.tick(tick)
    if tick == case.replaceAt then
      runner = h.start({ { "playbgm", h.ids[1], 0 }, { "end" } })
    end
    if case.options and (tick == 2 or tick == 4 or tick == 6) then
      h.options(tick == 2 and 4 or tick == 4 and 0 or 7)
    end
    local state = h.state()
    state.tick, state.running = tick, runner:isRunning()
    frames[#frames + 1] = state
    h.update()
  end
  rows[#rows + 1] = { case = case.name, frames = frames, trace = h.trace() }
  h.close()
end
f.close()
print("NATIVE_BGM_STREAMS " .. require("src.link.Json").encode(rows))
