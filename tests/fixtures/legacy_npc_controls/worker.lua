package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version = assert(arg[1]), assert(arg[2]), assert(arg[3])
love = require("tests.love_stub")
local f = dofile(root .. "/tests/api3_contract/npcs.lua").fixture(
	root .. "/tests/fixtures/legacy_npc_controls",
	backend,
	version,
	"legacy"
)
f.loader._game = function()
	return f.live
end
local result = f.exports.sample(f.home, "IMPORTED", "ALT")
assert(result.x == 3 and result.y == 4 and result.allowed and result.moving and result.stopped)
f.restoreRenderer()
print("LEGACY_NPC_RESULT " .. require("src.link.Json").encode(result))
