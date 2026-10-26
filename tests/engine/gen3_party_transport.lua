package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local P, H = require("src.link.Protocol"), require("src.link.Handshake")
local Copy, Json = require("src.mods.Merge").deepCopy, require("src.link.Json")
local C = require("src.link.Gen3Party")
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.party_codec").fixture(".", "gen2", version, "translated")
  local Stats, Pokemon = require("src.pokemon.Stats"), require("src.pokemon.Pokemon")
  Stats.setNatures(f.data.constants.natures)
  local function mon(pid, slot)
    local m = Pokemon.new(f.data, f.codecIds[60], 30)
    m.evs = { hp = 252, attack = 0, defense = 6, speed = 252, spatk = 0, spdef = 0 }
    Pokemon.applySeed(
      f.data,
      m,
      { personality = pid, ivs = { hp = 31, attack = 29, defense = 27, speed = 25, spatk = 23, spdef = 21 } }
    )
    m.abilitySlot, m.ot, m.otId, m.secretId, m.otSecretId = slot, "TRAINER", 1234, 5678, 5678
    m.moves = { { id = f.ids.TACKLE, pp = 10, ppUps = 3 } }
    m.nickname, m.extra = "PÖKEMON", { consumer = { marker = version } }
    return m
  end
  local original = mon(100001, 2)
  local packed = P.packMon(original)
  local decoded = assert(P.unpackMon(f.data, Json.decode(Json.encode(packed)), { strict = true }))
  T.same(decoded.ivs, original.ivs, "actual packet preserves IVs")
  T.same(decoded.evs, original.evs, "actual packet preserves EVs")
  T.same(decoded.stats, original.stats, "party reconstructed with its original native stats")
  T.eq(decoded.abilitySlot, 2, "explicit alternate ability survives independently of PID")
  T.eq(decoded.otSecretId, 5678, "public shiny reader receives the secret ID alias")
  T.eq(
    require("src.mods.Api3Records").shiny(decoded, 3),
    require("src.pokemon.IdentityRolls").nativeGen3Shiny(original.personality, 1234, 5678),
    "public identity agrees after transport"
  )
  local saved = require("src.core.SaveSerializer").decode(
    require("src.core.SaveSerializer").encode({ party = { decoded } })
  )
  T.same(saved.party[1].ivs, original.ivs, "received genetics survive save reload")
  decoded.ivs.hp = 0
  decoded.extra.consumer.marker = "changed"
  T.eq(original.ivs.hp, 31, "received genotype is detached")
  T.eq(original.extra.consumer.marker, version, "received extension namespace is detached")
  local cases = {
    {
      "codec",
      function(p)
        p.gen3Codec = nil
      end,
    },
    {
      "PID",
      function(p)
        p.personality = 4294967296
      end,
    },
    {
      "NaN",
      function(p)
        p.personality = 0 / 0
      end,
    },
    {
      "infinity",
      function(p)
        p.personality = math.huge
      end,
    },
    {
      "nature",
      function(p)
        p.nature = 24
      end,
    },
    {
      "gender",
      function(p)
        p.gender = "female"
      end,
    },
    {
      "IVs",
      function(p)
        p.ivs.hp = 32
      end,
    },
    {
      "EVs",
      function(p)
        p.evs.hp = 256
      end,
    },
    {
      "EV sum",
      function(p)
        p.evs.defense = 7
      end,
    },
    {
      "ability",
      function(p)
        p.abilitySlot = 3
      end,
    },
    {
      "species",
      function(p)
        p.species = "MISSING"
      end,
    },
    {
      "moves",
      function(p)
        p.moves = {}
      end,
    },
    {
      "duplicate",
      function(p)
        p.moves[2] = Copy(p.moves[1])
      end,
    },
    {
      "PP",
      function(p)
        p.moves[1].pp = 999
      end,
    },
    {
      "PP Ups",
      function(p)
        p.moves[1].ppUps = 4
      end,
    },
    {
      "OT",
      function(p)
        p.secretId = 65536
      end,
    },
    {
      "level",
      function(p)
        p.level = 0
      end,
    },
    {
      "exp",
      function(p)
        p.exp = 0
      end,
    },
    {
      "name",
      function(p)
        p.ot = "A\nB"
      end,
    },
    {
      "item",
      function(p)
        p.item = "MISSING"
      end,
    },
  }
  for _, case in ipairs(cases) do
    local p = Copy(packed)
    case[2](p)
    local ok, got, why = pcall(P.unpackMon, f.data, p, { strict = true })
    T.eq(ok, true, "malformed " .. case[1] .. " returns without crashing")
    T.eq(got, nil, "malformed " .. case[1] .. " is refused")
    T.check(type(why) == "string", "refusal explains malformed " .. case[1])
  end
  for _, status in ipairs({ "SLP", "PSN", "PAR", "BRN", "FRZ" }) do
    local p = Copy(packed)
    p.status, p.toxic, p.sleepTurns = status, true, 7
    local m = assert(P.unpackMon(f.data, p, { strict = true }))
    T.eq(m.status, status, "party retains status")
    T.eq(m.toxic, status == "PSN" and true or nil, "only poison retains strong-poison identity")
    local forced = assert(P.unpackMon(f.data, p, { strict = true, forceLevel = 50 }))
    T.eq(forced.status, nil, "auto-level clears status")
    T.eq(forced.sleepTurns, nil, "auto-level clears sleep count")
    T.eq(forced.toxic, nil, "auto-level clears toxic identity")
    T.eq(forced.hp, forced.stats.hp, "auto-level starts full")
    T.eq(forced.personality, original.personality, "auto-level retains personality")
  end
  local a, b =
    P.TradeSession.new(f.data, { original }, { strict = true }),
    P.TradeSession.new(f.data, { mon(100024, 1) }, { strict = true })
  local ao, bo = a:opening(), b:opening()
  a:handle(bo)
  b:handle(ao)
  local ap, bp = a:pick(1), b:pick(1)
  a:handle(bp)
  b:handle(ap)
  local ac, bc = a:confirm(true), b:confirm(true)
  a:handle(bc)
  b:handle(ac)
  T.eq(a.stage, "done", "real trade controller completes")
  T.eq(b.stage, "done", "both trade roles complete")
  T.same(b.theirParty[1].ivs, original.ivs, "actual trade receives six native IVs")
  T.eq(b.theirParty[1].abilitySlot, 2, "actual trade keeps selected ability")
  local received = b:apply()
  T.eq(received, b.party[1], "actual trade apply files the received party member")
  T.eq(received.traded, true, "received native mon retains traded identity")
  T.same(received.ivs, original.ivs, "trade application keeps all native IVs")
  T.same(received.evs, original.evs, "trade application keeps all native EVs")
  local persisted =
    require("src.core.SaveSerializer").decode(require("src.core.SaveSerializer").encode({ party = b.party }))
  T.eq(persisted.party[1].otSecretId, 5678, "applied trade retains secret ID through save reload")
  local bad = P.TradeSession.new(f.data, { original }, { strict = true })
  local packet = P.packParty({ original, original })
  packet[1].ivs.hp = -1
  bad:handle({ type = "party", mons = packet })
  T.eq(bad.stage, "cancelled", "invalid row cancels instead of sliding later slots")
  local hello = H.hello({ data = f.data, save = { player = { name = "RULES" } } }, "trade")
  local old = Copy(hello)
  old.nativePartyRevision = nil
  for _, pair in ipairs({ { hello, old }, { old, hello } }) do
    T.eq(H.checkCompat(pair[1], pair[2]), "refused", "old native party codec is refused in both roles")
    for _, mode in ipairs({ "trade", "battle" }) do
      local state = setmetatable(
        { game = f.game, myHello = pair[1], peerHello = pair[2] },
        { __index = require("src.link.LinkState") }
      )
      state:decideCompat(mode, true)
      T.eq(state.stage, "notice", "actual controller stops unsafe " .. mode)
      T.eq(state.noticeExits, true, "unsafe codec cannot enter party exchange")
    end
  end
  T.link.prepare(f.data)
  local ga = T.link.fakeGame(f.data, f.codecIds[60], { name = "A", level = 30 })
  local gb = T.link.fakeGame(f.data, f.codecIds[60], { name = "B", level = 30 })
  ga.save.party, gb.save.party = { original }, { mon(100024, 1) }
  local result = T.link.lockstep(ga, gb, { seed = 327, maxFrames = 60000 })
  T.eq(result.completed, true, "full native-genetics link mirror completes")
  T.eq(result.agreed, true, "native-genetics turn hashes agree")
  for _, m in ipairs({ result.battleA.player.mon, result.battleB.enemy.mon }) do
    T.same(m.ivs, original.ivs, "local and remote battle receive original IVs")
    T.same(m.evs, original.evs, "local and remote battle receive original EVs")
    T.eq(m.personality, original.personality, "local and remote battle receive original PID")
    T.eq(m.abilitySlot, 2, "local and remote battle retain alternate ability")
  end
  for turn, hash in pairs(result.battleA.localHashes) do
    if result.battleB.localHashes[turn] then
      T.eq(hash, result.battleB.localHashes[turn], "every completed turn agrees")
      T.same(
        result.battleA.localParts[turn],
        result.battleB.localParts[turn],
        "every completed state component agrees"
      )
    end
  end
  local signature = C.signature(original)
  for _, key in ipairs({ "personality", "abilitySlot", "level", "exp", "otId", "otSecretId" }) do
    local changed = Copy(original)
    changed[key] = (changed[key] or 0) + 1
    T.neq(C.signature(changed), signature, "state signature detects altered " .. key)
  end
  for _, kind in ipairs({ "ivs", "evs" }) do
    local changed = Copy(original)
    changed[kind].hp = changed[kind].hp + 1
    T.neq(C.signature(changed), signature, "state signature detects altered " .. kind)
  end
  Stats.setNatures(nil)
  f.close()
end
require("src.core.GameVersion").set("red")
local classic = T.fixtures.fresh()
local original = require("src.pokemon.Pokemon").new(classic, "FIXMON_A", 20)
local packed = P.packMon(original)
T.eq(packed.gen3Codec, nil, "older-game packet keeps its existing shape")
T.eq(packed.ivs, nil, "older games do not acquire GBA genetics")
T.same(assert(P.unpackMon(classic, packed)).dvs, original.dvs, "classic DV codec remains intact")
T.finish("native GBA party transport, trade and link")
