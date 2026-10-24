package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local f = dofile(root .. "/tests/follower/fixture.lua").new(root, backend, version, tonumber(api), format)
local rows = dofile(root .. "/tests/follower/cases.lua").run(f)
f.close()
local failed =
  dofile(root .. "/tests/follower/fixture.lua").new(root, backend, version, tonumber(api), format, true)
failed.T.check(#failed.result.errors > 0, "entry failure is recorded")
failed.tick()
failed.T.eq(failed.current() ~= nil, version == "yellow", "entry rollback restores native predicate")
rows[#rows + 1] = { label = "rollback", present = failed.current() ~= nil }
failed.close()
print("FOLLOWER_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable native follower")
