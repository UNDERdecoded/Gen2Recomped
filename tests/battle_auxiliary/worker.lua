package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local f = dofile(root .. "/tests/battle_auxiliary/shared.lua").new(root, backend, version, api, format)
local e, T = f.exports, f.T
T.eq(f.ready(), true, "actual native menu settled")
local rows = {}
for _, claim in ipairs({ false, true, false }) do
  e.claim(claim)
  f.index(1)
  f.game.input.pressed = { start = true, right = true }
  local calls = e.seen.calls
  f.update()
  T.eq(e.seen.calls, calls + 1, "one native dispatch")
  T.eq(f.index(), claim and 1 or 2, "native claim/fallthrough")
  T.eq(e.seen.context.kind, "trainer", "shared trainer context")
  rows[#rows + 1] = { claim = claim, index = f.index(), kind = e.seen.context.kind }
end
e.stop()
f.index(1)
f.game.input.pressed = { start = true, right = true }
local calls = e.seen.calls
f.update()
T.eq(e.seen.calls, calls, "unsubscribe stops native hook")
T.eq(f.index(), 2, "unsubscribe preserves native navigation")
f.close()
print("BATTLE_AUXILIARY_CONTRACT " .. require("src.link.Json").encode(rows))
T.finish("portable battle.menu_auxiliary shared native contract")
