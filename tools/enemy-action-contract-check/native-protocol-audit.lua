-- Independently derive the new surface from a clean frozen parent serializer.
-- Argument: frozen parent src/link/Fingerprint.lua; never patch that checkout.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local file = assert(io.open(assert(arg[1]), "rb"))
local source = file:read("*a")
file:close()
local parent = assert(loadstring(source, "@frozen-parent-fingerprint"))()
local data, rows = T.fixtures.fresh(), {}
for _, version in ipairs({ "red", "firered", "gold", "emerald", "diamond", "black" }) do
  V.set(version)
  local before = parent.surface(data, {})
  local after, count = before:gsub("%[native_gba_commands%]19", "[native_gba_commands]20")
  assert(count == (V.isGen3() and 1 or 0), "only the frozen GBA revision token may change")
  local current = require("src.link.Fingerprint")
  assert(current.surface(data, {}) == after, "current serializer differs beyond the derived revision token")
  assert(
    current.compute(data, {}) == parent.digest(after),
    "current digest disagrees with the parent algorithm"
  )
  assert(current.nativePartyRevision() == (V.isGen3() and 1 or nil), "party codec revision stays independent")
  rows[#rows + 1] = {
    version = version,
    previous = parent.digest(before),
    current = parent.digest(after),
    tokenChanges = count,
  }
end
print("FROZEN_NATIVE_PROTOCOL_AUDIT " .. require("src.link.Json").encode(rows))
