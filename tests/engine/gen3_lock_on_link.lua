package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local L, Copy = require("src.battle.Gen3LockOn"), require("src.mods.Merge").deepCopy
local target = { lockOnTurns = 2, lockOnBy = true, lockOnByPos = 0 }
T.eq(
  L.signature(target, "host"),
  L.signature({ lockOnTurns = 2, lockOnBy = false, lockOnByPos = 1 }, "guest"),
  "native ownership hashes in canonical host coordinates"
)
for _, key in ipairs({ "lockOnTurns", "lockOnBy", "lockOnByPos" }) do
  local changed = Copy(target)
  if key == "lockOnBy" then
    changed[key] = false
  else
    changed[key] = target[key] + 1
  end
  T.neq(L.signature(changed), L.signature(target), "native active signature detects " .. key)
end
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.lock_on").fixture(".", "gen2", version)
  local H = require("src.link.Handshake")
  local current = H.hello(f.game, "battle")
  local oldRules = Copy(current)
  oldRules.nativeBattleRevision = 1
  T.eq(
    H.checkCompat(current, oldRules),
    "subset",
    "older native rules cannot battle even with the same custom fingerprint"
  )
  T.eq(H.checkCompat(oldRules, current), "subset", "native rule gate is symmetric")
  for _, host in ipairs({ false, true }) do
    local state = setmetatable(
      { game = f.game, myHello = current, peerHello = oldRules },
      { __index = require("src.link.LinkState") }
    )
    state:decideCompat("battle", host)
    T.eq(state.stage, "notice", "actual controller refuses older native rule revision")
    T.eq(state.noticeExits, true, "old native rules cannot enter battle setup")
  end
  local def = f.data.pokemon.CHARMANDER
  def.evYield = {}
  def.baseStats.spatk, def.baseStats.spdef = 50, 50
  T.link.prepare(f.data)
  local ga = T.link.fakeGame(f.data, "CHARMANDER", { name = "A", level = 30 })
  local gb = T.link.fakeGame(f.data, "CHARMANDER", { name = "B", level = 30 })
  for _, game in ipairs({ ga, gb }) do
    game.save.party[1].moves =
      { { id = f.ids.LOCK_ON, pp = 20 }, { id = f.ids.TACKLE, pp = f.data.moves[f.ids.TACKLE].pp } }
  end
  local P, Net, Link = require("src.link.Protocol"), require("src.link.Net"), require("src.link.LinkBattle")
  local na, nb = Net.loopbackPair()
  local pa, pb = P.packParty(ga.save.party), P.packParty(gb.save.party)
  local a = assert(
    Link.newHost(
      ga,
      na,
      { myParty = pa, theirParty = pb, theirName = "B", seed = 327, verdict = "full", strict = true }
    )
  )
  local b = assert(
    Link.newGuest(
      gb,
      nb,
      { myParty = pb, theirParty = pa, theirName = "A", seed = 327, verdict = "full", strict = true }
    )
  )
  local ra, rb, seenA, seenB = nil, nil, {}, {}
  a.onFinish = function(v)
    ra = v
  end
  b.onFinish = function(v)
    rb = v
  end
  ga.stack:push(a)
  gb.stack:push(b)
  local function capture(battle, seen)
    for turn in pairs(battle.localHashes) do
      if not seen[turn] then
        seen[turn] = { player = battle.player.lockOnTurns, enemy = battle.enemy.lockOnTurns }
      end
    end
  end
  local frames = 0
  while (not ra or not rb) and frames < 60000 do
    frames = frames + 1
    require("src.core.Input").pressed = { a = true }
    -- Drive the real controller: aim once, then select the damaging move.
    a.moveIndex = (a.turnCount or 0) > 0 and 2 or 1
    b.moveIndex = (b.turnCount or 0) > 0 and 2 or 1
    ga.stack:update(1 / 60)
    capture(a, seenA)
    gb.stack:update(1 / 60)
    capture(b, seenB)
  end
  T.check(ra ~= nil and rb ~= nil, "complete native sure-hit link mirror finishes")
  T.check(seenA[1] ~= nil and seenB[1] ~= nil, "first native turn is captured on both peers")
  if seenA[1] and seenB[1] then
    T.eq(seenA[1].player, 1, "host mark survives the first residual")
    T.eq(seenA[1].enemy, 1, "remote mark survives the first residual")
    T.same(seenA[1], seenB[1], "both actual link roles retain their timed bindings")
  end
  if seenA[2] and seenB[2] then
    T.eq(seenA[2].player, nil, "host mark expires after the next turn")
    T.eq(seenA[2].enemy, nil, "remote mark expires after the next turn")
    T.same(seenA[2], seenB[2], "both actual roles expire the binding together")
  else
    T.check(false, "second turn must complete")
  end
  local compared = 0
  for turn, hash in pairs(a.localHashes) do
    if b.localHashes[turn] then
      compared = compared + 1
      T.eq(hash, b.localHashes[turn], "complete native turn hash agrees")
      T.same(a.localParts[turn], b.localParts[turn], "native owner/duration components agree")
    end
  end
  T.check(compared >= 2, "native mirror compares multiple full turns")
  f.close()
end
require("src.core.GameVersion").set("red")
local old = {
  player = { name = "PLAYER", isPlayer = true, mon = { hp = 10 } },
  enemy = { name = "ENEMY", isPlayer = false, mon = { hp = 10 } },
}
require("src.battle.Gen3MoveEffects").primary.LOCK_ON_EFFECT(old, old.player, old.enemy)
T.eq(old.player.lockedOn, old.enemy, "older games keep their existing one-use pointer producer")
T.eq(old.enemy.lockOnTurns, nil, "older games do not acquire a native timer")
T.finish("native Lock-On link mirrors and ownership signatures")
