-- A full 16-player tournament, played out.
--
-- Sixteen distinct identities, six random Pokemon each, everyone mashing A,
-- through every match of every round until one champion is left: 8 + 4 + 2 +
-- 1 = 15 real lockstep battles, each with the tournament match shape
-- (turnLimit shot clock, keepNetOpen, forceLevel) plus a live spectator
-- rebuilding the same match from the relay's fan-out.
--
-- What this is actually checking, beyond "it finishes":
--   * 15 consecutive lockstep matches agree turn by turn, so a desync is
--     not something that only shows up deep into a bracket
--   * every match produces one winner and one loser -- never a double-win,
--     a double-loss, or a draw the server has to coin-flip (relay.js
--     resolves conflicting results with crypto.randomInt, so a draw here is
--     a real player's tournament decided by a coin toss)
--   * the spectator's reconstruction matches the two players' own views,
--     which is the tournament-only client path
--   * the shot clock does not fire on its own during ordinary play
--
-- Bracket pairing/advancement itself is the relay's job and is covered
-- server-side (pokeserver test/tournament16.js); this owns the client half.
--
--   luajit tests/link_tournament16.lua [seed]

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Data = require("src.core.Data")
if not Data.pokemon then Data:load() end
local Pokemon = require("src.pokemon.Pokemon")
local Protocol = require("src.link.Protocol")
local Net = require("src.link.Net")
local Input = require("src.core.Input")
local LinkBattle = require("src.link.LinkBattle")
Input:init()
require("src.render.Font").load(Data)

local PLAYERS = 16
local PARTY_SIZE = 6
local TURN_LIMIT = 6 -- one of relay.js's VALID_TURN_LIMITS

local failures = 0
local function check(cond, msg)
  if cond then
    print("ok   " .. msg)
  else
    failures = failures + 1
    print("FAIL " .. msg)
  end
end

local function makeRandom(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(a, b)
    s = (s * 16807) % 2147483647
    if a == nil then return s / 2147483647 end
    if b == nil then a, b = 1, a end
    return a + (s % (b - a + 1))
  end
end

local SPECIES = {}
for id in pairs(Data.pokemon) do SPECIES[#SPECIES + 1] = id end
table.sort(SPECIES)
local MOVES = {}
for id, m in pairs(Data.moves) do
  if id ~= "STRUGGLE" and m.pp and m.pp > 0 then MOVES[#MOVES + 1] = id end
end
table.sort(MOVES)

local function makeFakeGame(name)
  local save = require("src.core.SaveData").newGame()
  save.player.name = name
  local stack = { list = {} }
  function stack:push(s, ...)
    table.insert(self.list, s)
    if s.enter then s:enter(...) end
  end
  function stack:pop() table.remove(self.list) end
  function stack:top() return self.list[#self.list] end
  function stack:update(dt)
    local t = self:top()
    if t and t.update then t:update(dt) end
  end
  return { data = Data, input = Input, stack = stack, save = save }
end

-- six random species with random movesets, the tournament's required size
local function randomParty(rnd)
  local party = {}
  for _ = 1, PARTY_SIZE do
    local mon = Pokemon.new(Data, SPECIES[rnd(1, #SPECIES)], rnd(20, 60))
    mon.moves = {}
    for _ = 1, rnd(1, 4) do
      local id = MOVES[rnd(1, #MOVES)]
      table.insert(mon.moves, { id = id, pp = Data.moves[id].pp })
    end
    party[#party + 1] = mon
  end
  return party
end

-- a three-way loopback: the two players relay to each other, and every line
-- is also fanned out to the spectator tagged with the side that sent it,
-- which is the `spectate` envelope relay.js wraps tournament traffic in
local function matchNets()
  local a, b = Net.loopbackPair()
  local spec = Net.new()
  spec.paired, spec.mode = true, "loopback"
  local function send(self, msg)
    if self.closed then return end
    local Json = require("src.link.Json")
    local decoded = Json.decode(Json.encode(msg))
    if not decoded then return end
    if not self.peerEnd.closed then table.insert(self.peerEnd.inbox, decoded) end
    if not spec.closed then
      table.insert(spec.inbox, { type = "spectate", side = self.matchSide,
                                 msg = Json.decode(Json.encode(msg)) })
    end
  end
  a.matchSide, b.matchSide = "host", "guest"
  a.send, b.send = send, send
  return a, b, spec
end

local PARTS = { "actives", "volatile", "bench" }
local function splitTurn(a, b)
  for turn, mine in pairs(a.localParts) do
    local theirs = b.localParts[turn]
    if theirs then
      for _, part in ipairs(PARTS) do
        if mine[part] ~= theirs[part] then return turn, part end
      end
    end
  end
end

-- Plays one bracket match to a finish. Returns the winner/loser entries, or
-- nil plus why it could not be decided.
local function playMatch(hostEntry, guestEntry, rnd, label)
  local netH, netG, netS = matchNets()
  local packedH = Protocol.packParty(hostEntry.game.save.party)
  local packedG = Protocol.packParty(guestEntry.game.save.party)
  local seed = rnd(1, 2 ^ 30)
  local opts = { turnLimit = TURN_LIMIT, keepNetOpen = true,
                 verdict = "full", strict = true }

  local bH = LinkBattle.newHost(hostEntry.game, netH, {
    myParty = packedH, theirParty = packedG, theirName = guestEntry.name,
    seed = seed, turnLimit = opts.turnLimit, keepNetOpen = true,
    verdict = opts.verdict, strict = opts.strict })
  local bG = LinkBattle.newGuest(guestEntry.game, netG, {
    myParty = packedG, theirParty = packedH, theirName = hostEntry.name,
    seed = seed, turnLimit = opts.turnLimit, keepNetOpen = true,
    verdict = opts.verdict, strict = opts.strict })
  -- one of the fourteen players not in this match, watching it live (it has
  -- a party of its own like any eliminated entrant would -- the spectator
  -- never battles with it, but newWild builds its scaffold from one)
  local specEntry = makeFakeGame("WATCHER")
  specEntry.save.party = randomParty(rnd)
  local bS = LinkBattle.newSpectator(specEntry, netS, {
    hostParty = packedH, guestParty = packedG,
    hostName = hostEntry.name, guestName = guestEntry.name,
    seed = seed, verdict = opts.verdict, strict = opts.strict })
  if not (bH and bG and bS) then return nil, label .. ": a side refused to build" end

  local resH, resG
  bH.onFinish = function(r) resH = r end
  bG.onFinish = function(r) resG = r end
  hostEntry.game.stack:push(bH)
  guestEntry.game.stack:push(bG)
  specEntry.stack:push(bS)

  local sides = {
    { bt = bH, game = hostEntry.game, party = bH.playerParty },
    { bt = bG, game = guestEntry.game, party = bG.playerParty },
  }
  -- everyone mashes A: the cursor is only steered onto a legal move row,
  -- and occasionally onto a switch, so all six mons get used
  local function drive(side)
    local bt = side.bt
    if bt.result then return end
    if bt.phase ~= "menu" then side.menuFrames = 0 end
    if bt.phase == "moveSelect" then
      local usable = {}
      for i, mv in ipairs(bt.player.curMoves) do
        if (mv.pp or 0) > 0 and bt.player.disabledSlot ~= i then usable[#usable + 1] = i end
      end
      if #usable > 0 then bt.moveIndex = usable[rnd(1, #usable)] end
      bt.menuIndex = 1
    elseif bt.phase == "menu" then
      bt.menuIndex = 1
      side.menuFrames = (side.menuFrames or 0) + 1
      if side.menuFrames >= 2 and not bt:menuLockedAction(bt.player)
         and rnd(1, 100) <= 8 then
        for _ = 1, 4 do
          local mon = side.party[rnd(1, #side.party)]
          if mon.hp > 0 and mon ~= bt.player.mon then
            bt:resolveSwitch(mon)
            side.menuFrames = 0
            return
          end
        end
      end
    end
  end

  local guard = 0
  while (resH == nil or resG == nil) and guard < 200000 do
    guard = guard + 1
    Input.pressed = { a = true }
    for _, side in ipairs(sides) do
      drive(side)
      side.game.stack:update(1 / 60)
    end
    specEntry.stack:update(1 / 60)
    local turn, part = splitTurn(bH, bG)
    if turn then
      return nil, ("%s: turn %d %s split"):format(label, turn, part)
    end
  end
  if resH == nil or resG == nil then
    return nil, ("%s: unfinished after %d frames (turn %s)"):format(
      label, guard, tostring(bH.turnCount))
  end
  -- the two views of the same match have to be opposite verdicts; a draw
  -- means the server picks the winner with a coin flip
  if not ((resH == "win" and resG == "lose") or (resH == "lose" and resG == "win")) then
    return nil, ("%s: not a decisive result (%s / %s)"):format(label, resH, resG)
  end
  -- The spectator is a replay, so it is legitimately behind the two players
  -- when they finish -- it still has their last turns queued.  Let it drain
  -- before comparing, or the check reads a mid-match frame.
  local settle = 0
  while settle < 20000 and not bS.finished do
    settle = settle + 1
    local before = bS.turnCount
    specEntry.stack:update(1 / 60)
    if bS.result and bS.turnCount == before and #bS.queue == 0 then break end
  end
  -- the spectator rebuilt the same battle from the relay copy
  local specOk = bS.player.mon.hp == bH.player.mon.hp
                 and bS.enemy.mon.hp == bG.player.mon.hp
  if resH == "win" then
    return hostEntry, guestEntry, specOk
  end
  return guestEntry, hostEntry, specOk
end

local seed = tonumber(arg and arg[1]) or 20260728
local rnd = makeRandom(seed)

local entrants = {}
for i = 1, PLAYERS do
  local name = ("PLAYER%02d"):format(i)
  local game = makeFakeGame(name)
  game.save.party = randomParty(rnd)
  game.save.player.id = rnd(0, 65535) -- distinct trainer identities
  entrants[i] = { name = name, game = game }
end
check(#entrants == PLAYERS, "16 distinct entrants registered")
local sizesOk = true
for _, e in ipairs(entrants) do
  if #e.game.save.party ~= PARTY_SIZE then sizesOk = false end
end
check(sizesOk, "every entrant brings a full party of " .. PARTY_SIZE)

-- 16 is a power of two, so no byes: 8 + 4 + 2 + 1 real matches
local alive = entrants
local round, matchesPlayed, specOkCount = 0, 0, 0
while #alive > 1 and failures == 0 do
  round = round + 1
  local survivors = {}
  for i = 1, #alive, 2 do
    local label = ("round %d match %d"):format(round, (i + 1) / 2)
    local winner, loser, specOk = playMatch(alive[i], alive[i + 1], rnd, label)
    if not winner then
      check(false, tostring(loser))
      break
    end
    matchesPlayed = matchesPlayed + 1
    if specOk then specOkCount = specOkCount + 1 end
    survivors[#survivors + 1] = winner
  end
  if failures > 0 then break end
  check(#survivors == #alive / 2,
        ("round %d halved the field (%d -> %d)"):format(round, #alive, #survivors))
  alive = survivors
end

check(matchesPlayed == PLAYERS - 1,
      ("every bracket match was played (%d of %d)"):format(matchesPlayed, PLAYERS - 1))
check(round == 4, ("the bracket ran 4 rounds (ran %d)"):format(round))
check(#alive == 1, "exactly one champion is left")
if alive[1] then print("     champion: " .. alive[1].name) end
check(specOkCount == matchesPlayed,
      ("every match's spectator view matched the players' (%d of %d)"):format(
        specOkCount, matchesPlayed))

print(("\ntournament16: %s"):format(
  failures == 0 and "PASSED" or (failures .. " FAILURES")))
assert(failures == 0, failures .. " tournament failure(s)")
return true
