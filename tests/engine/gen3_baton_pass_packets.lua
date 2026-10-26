package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Copy = require("src.mods.Merge").deepCopy
local C, B = require("src.link.Gen3BatonChoice"), require("src.battle.Gen3BatonPass")
for _, stat in ipairs({ "spatk", "spdef" }) do
  local changed = { stages = { [stat] = 2 } }
  T.neq(B.signature(changed), B.signature({}), "native active hashes include transferred " .. stat)
end
T.eq(
  B.signature({ leechSeedSource = { position = 0 } }, "host"),
  B.signature({ leechSeedSource = { position = 1 } }, "guest"),
  "seed-source ownership hashes in host coordinates"
)
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.baton_pass").fixture(".", "gen2", version)
  local H = require("src.link.Handshake")
  local current, old = H.hello(f.game, "battle"), H.hello(f.game, "battle")
  old.nativeBattleRevision = 2
  T.eq(H.checkCompat(current, old), "subset", "pre-choice native rules cannot enter a battle")
  T.eq(H.checkCompat(old, current), "subset", "pre-choice native guard is symmetric")
  local function fresh(spectator)
    local b = f.fresh("TACKLE", { enemy = true }).battle
    b:syncSides()
    b.turnCount = 1
    local mine, theirs = { b.player.mon }, { b.enemy.mon }
    for i = 2, 3 do
      mine[i], theirs[i] = Copy(mine[1]), Copy(theirs[1])
    end
    local errors, sent = {}, {}
    C.attach(b, {
      role = "host",
      spectator = spectator,
      mine = mine,
      theirs = theirs,
      invalid = function(why)
        errors[#errors + 1] = why
      end,
      send = function(packet)
        sent[#sent + 1] = packet
      end,
    })
    return b, errors, sent, mine, theirs
  end
  local function pending(b, user)
    local candidates, party = B.candidates(b, user)
    local p = { user = user, party = party, candidates = candidates, offered = {} }
    for _, i in ipairs(candidates) do
      p.offered[i] = party[i]
    end
    b._gen3BatonPending = p
    return p
  end
  local packet = { type = "baton_pass", turn = 1, serial = 1, actor = "guest", index = 3 }
  local b, errors = fresh()
  T.check(C.receive(b, packet), "reliable early choice can arrive before native command")
  local p = pending(b, b.enemy)
  T.eq(b:_gen3BatonRequest(p), true, "remote actor waits for a wire choice")
  T.eq(p.choice, 3, "early non-first choice is consumed without fallback")
  T.check(C.receive(b, Copy(packet)), "identical retransmission is idempotent")
  T.eq(#errors, 0, "valid early and duplicate choices remain accepted")
  local conflict = Copy(packet)
  conflict.index = 2
  T.eq(C.receive(b, conflict), false, "conflicting replay is refused")
  T.eq(#errors, 1, "conflicting replay reaches the controller failure path")
  T.eq(p.choice, 3, "replay does not change the accepted mon")
  for _, edit in ipairs({
    { "turn", 0 },
    { "turn", 2 },
    { "serial", 0 },
    { "serial", 65 },
    { "serial", 1.5 },
    { "index", 0 },
    { "index", 7 },
    { "index", 0 / 0 },
    { "actor", "host" },
    { "actor", "other" },
    { "index", "3" },
  }) do
    local bad = Copy(packet)
    bad[edit[1]] = edit[2]
    local battle, invalid = fresh()
    T.eq(C.receive(battle, bad), false, "malformed or unauthorized choice is refused")
    T.eq(#invalid, 1, "malformed choice cannot leave the controller waiting")
  end
  local battle, invalid = fresh(true)
  T.eq(C.receive(battle, packet, "host"), false, "spectator authenticates the relayed actor")
  T.eq(#invalid, 1, "wrong relay side ends spectator choice processing")
  local spec, bad = fresh(true)
  T.check(C.receive(spec, packet, "guest"), "spectator buffers authenticated choice")
  local remote = pending(spec, spec.enemy)
  T.eq(spec:_gen3BatonRequest(remote), true, "spectator never needs a personal picker")
  T.eq(remote.choice, 3, "spectator resumes with the real remote selection")
  T.eq(#bad, 0, "authenticated spectator choice has no controller error")
  local localBattle, localErrors, sent = fresh()
  local localPending = pending(localBattle, localBattle.player)
  T.eq(localBattle:_gen3BatonRequest(localPending), false, "local owner needs a picker")
  T.check(B.select(localBattle, localPending, 3), "local selection is validated before sending")
  T.eq(#sent, 1, "exactly one native choice is sent")
  T.same(
    sent[1],
    { type = "baton_pass", turn = 1, serial = 1, actor = "host", index = 3 },
    "wire carries turn, order, owner and actual choice"
  )
  T.eq(B.select(localBattle, localPending, 2), false, "local callback cannot send twice")
  T.eq(#localErrors, 0, "valid local choice has no controller error")
  local stale, failures, _, _, party = fresh()
  local waiting = pending(stale, stale.enemy)
  stale:_gen3BatonRequest(waiting)
  party[3].hp = 0
  C.receive(stale, packet)
  T.eq(waiting.choice, nil, "wire cannot choose a newly fainted replacement")
  T.eq(#failures, 1, "stale native choice reaches controller failure")
  f.close()
end
T.finish("native Baton Pass packet validation and buffered choices")
