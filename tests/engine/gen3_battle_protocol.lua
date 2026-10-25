package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, F, H =
  require("src.core.GameVersion"), require("src.link.Fingerprint"), require("src.link.Handshake")
local Copy = require("src.mods.Merge").deepCopy
local data, before = T.fixtures.fresh(), V.get()
-- Legacy hash retained; native hash independently audits revision 12 -> 13 only.
local LEGACY = "e33d251961f2a41d"
local NATIVE = "beacb71804a6af34"
for _, version in ipairs({ "red", "firered", "gold", "emerald", "diamond", "firered", "black" }) do
  V.set(version)
  local gba = V.isGen3()
  T.eq(
    F.compute(data, {}),
    gba and NATIVE or LEGACY,
    "runtime command revision participates in cached fingerprints"
  )
  T.eq(F.nativeBattleRevision(), gba and 13 or nil, "only GBA advertises the new command revision")
  local game = { data = data, save = { player = { name = "RULES" } } }
  local current = H.hello(game, "battle")
  local legacy = Copy(current)
  legacy.nativeBattleRevision, legacy.fingerprint = nil, LEGACY
  T.eq(H.checkCompat(current, Copy(current)), "full", "identical native rules admit lockstep")
  T.eq(
    H.checkCompat(current, legacy),
    gba and "subset" or "full",
    "old wire digest cannot admit changed GBA battles"
  )
  T.eq(H.checkCompat(legacy, current), gba and "subset" or "full", "the wire mismatch is symmetric")
  T.eq(
    H.checkCompat(current, {}),
    gba and "refused" or "vanilla_peer",
    "legacy unversioned peers remain safe"
  )
  if gba then
    for _, host in ipairs({ false, true }) do
      local state = setmetatable(
        { game = game, myHello = current, peerHello = legacy },
        { __index = require("src.link.LinkState") }
      )
      state:decideCompat("battle", host)
      T.eq(state.stage, "notice", "actual link controller stops before battle setup")
      T.eq(state.noticeExits, true, "mismatched commands cannot start a battle")
    end
    local message = table.concat(H.describe(current, legacy, "subset", "battle"), " ")
    T.check(message:find("engine versions", 1, true) ~= nil, "rule mismatch names the needed engine update")
    for field, value in pairs({
      index = 999,
      gen3Effect = 6,
      secondaryChance = 100,
      target = 8,
      flags = 0,
      protectAffected = false,
    }) do
      local changed = Copy(data)
      changed.moves.FIX_TACKLE[field] = value
      T.neq(F.compute(changed, {}), NATIVE, "native " .. field .. " changes the full link surface")
      T.neq(
        F.records(changed, "moves").FIX_TACKLE,
        F.records(data, "moves").FIX_TACKLE,
        "native " .. field .. " changes move compatibility"
      )
      V.set("red")
      T.eq(F.compute(changed, {}), LEGACY, "native-only move fields retain old game digests")
      V.set(version)
    end
    local Protocol = require("src.link.Protocol")
    local mon = require("src.pokemon.Pokemon").new(data, "FIXMON_A", 20)
    mon.status, mon.toxic = "PSN", true
    local Serializer = require("src.core.SaveSerializer")
    local saved = Serializer.decode(Serializer.encode({ party = { mon } }))
    T.eq(saved.party[1].toxic, true, "native save representation preserves the toxic marker")
    local packed = Protocol.packMon(mon)
    local restored = Protocol.unpackMon(data, packed, { strict = true })
    T.eq(packed.toxic, true, "native party wire preserves the toxic marker")
    T.eq(restored.toxic, true, "native party decode preserves the toxic marker")
    packed.toxic = "true"
    T.eq(
      Protocol.unpackMon(data, packed, { strict = true }).toxic,
      nil,
      "wire marker requires an actual boolean"
    )
    -- The content/trade record digest remains independent of runtime revision.
    local records = F.records(data, "pokemon")
    V.set("red")
    T.same(F.records(data, "pokemon"), records, "shared Pokemon trade definitions are retained")
    V.set(version)
  end
end
for _, version in ipairs({ "firered", "emerald" }) do
  V.set(version)
  local simulated = T.fixtures.fresh()
  local loaded = T.sdk.loadNone({ data = simulated })
  T.eq(#loaded.errors, 0, "link mirror fixture loads")
  require("src.battle.TypeChart").load(simulated)
  T.link.prepare(simulated)
  local a = T.link.fakeGame(simulated, "FIXMON_A", { name = "A", level = 20 })
  local b = T.link.fakeGame(simulated, "FIXMON_B", { name = "B", level = 20 })
  a.save.party[1].status, a.save.party[1].toxic = "PSN", true
  local result = T.link.lockstep(a, b, { maxFrames = 60000, seed = 327 })
  T.eq(result.completed, true, "native runtime mirror completes a full synthetic link battle")
  T.eq(result.agreed, true, "native runtime mirror has no state hash split")
  T.eq(result.battleA.player.mon.hp, result.battleB.enemy.mon.hp, "host HP matches peer view")
  T.eq(result.battleA.enemy.mon.hp, result.battleB.player.mon.hp, "guest HP matches peer view")
  T.eq(result.battleA.player.mon.toxic, true, "host battle retains its toxic marker")
  T.eq(result.battleB.enemy.mon.toxic, true, "guest battle retains the remote toxic marker")
  local compared = 0
  for turn, hash in pairs(result.battleA.localHashes) do
    if result.battleB.localHashes[turn] then
      compared = compared + 1
      T.eq(hash, result.battleB.localHashes[turn], "each paired turn hash agrees")
      T.same(
        result.battleA.localParts[turn],
        result.battleB.localParts[turn],
        "each paired state component agrees"
      )
    end
  end
  T.check(compared >= 2, "link mirror compares several completed turns")
  loaded.release()
end
V.set(before)
T.finish("native GBA battle protocol revision")
