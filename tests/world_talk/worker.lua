package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local Fixture = dofile(root .. "/tests/world_talk/fixture.lua")
local f = Fixture.new(root, backend, version, api, format)
local rows
if backend == "gen1" and f.gen == 2 then
  local before = #f.calls
  f.interact()
  f.T.eq(#f.calls, before + 1, "native Gold conversation runs")
  f.T.eq(f.exports.seen.calls, 0, "native Gold has no world.talk producer despite catalog")
  rows = { { label = "reference boundary", native = 1 } }
else
  rows = dofile(root .. "/tests/world_talk/cases.lua").run(f)
end
f.close()
for _, failing in ipairs({ false, true }) do
  local bare = Fixture.new(root, backend, version, api, format, not failing, failing)
  bare.T.eq(
    require("src.mods.Runtime").wantsHook("world.talk"),
    false,
    "no-mod / entry rollback unsubscribed"
  )
  local before = #bare.calls
  bare.interact()
  bare.T.eq(#bare.calls, before + 1, "no-mod / entry rollback keeps native interaction")
  if failing then
    bare.T.check(#bare.result.errors > 0, "entry error reported")
  end
  bare.close()
end
print("WORLD_TALK_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable world.talk contract")
