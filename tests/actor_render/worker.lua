package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api = assert(arg[1]), assert(arg[2]), assert(arg[3]), tonumber(arg[4]) or 2
local f
if backend == "gen1" then
  f = dofile(root .. "/tests/actor_render/gen1_fixture.lua").new(root, version, api)
else
  f = dofile(root .. "/tests/actor_render/fixture.lua").new(root, version, api)
  function f.setPose(facing, phase, step)
    f.player.facing = facing
    f.player.animClock = (phase == 1 and 8 or 0) + (step and 16 or 0)
  end
end
local exports = assert(f.result.loader.exports.actor_reference)
local reports = {}
for _, facing in ipairs({ "down", "up", "left", "right" }) do
  for _, phase in ipairs({ 0, 1 }) do
    for _, step in ipairs({ false, true }) do
      f.setPose(facing, phase, step)
      local before = f.player.animDrawn
      local observation = assert(exports.observe("A"))
      assert(f.player.animDrawn == before, "sampling must not record a native draw")
      reports[#reports + 1] = observation
    end
  end
end
f.player.hidden = true
reports[#reports + 1] = assert(exports.observe("A"))
assert(#reports[#reports].scene.actors == 3)
assert(exports.observe("stale") == nil, "stale map must fail")
for _, r in ipairs(reports) do
  for _, s in pairs(r.sheets) do
    s.bytes = (s.bytes:gsub(".", function(c)
      return ("%02x"):format(c:byte())
    end))
  end
end
print("ACTOR_RENDER " .. require("src.link.Json").encode(reports))
