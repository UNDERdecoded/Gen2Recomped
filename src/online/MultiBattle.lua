-- 4-PLAYER MULTI LINK BATTLES (two players a side, one slot each).
--
-- The cartridges' multi link battles: Emerald / FireRed / LeafGreen's Cable
-- Club and wireless multi (four GBAs), Platinum / HeartGold / SoulSilver's
-- 2F Colosseum MULTI, Black / White's link multi and the Battle Subway's
-- Wireless Multi Train (two players against two subway trainers).
--
--   MultiBattle.open(game, session, opts, onDone)   the whole thing: the
--       lobby (src/online/MultiLobby.lua: gather four by a host code, a
--       world or a link-room session, the leader sets the teams, everyone
--       picks their Pokemon), then the battle; onDone(result) with result
--       "win" | "lose" | "draw" | "cancelled" | "failed" (and a reason).
--   MultiBattle.newBattle(game, net, opts)          one battle on a ready
--       star (src/online/MultiNet.lua); returns a BattleState to push.
--
-- SEATS.  The four players are seats 0..3, which are the battle's positions
-- as the cartridge numbers its battlers: team A is seats 0 and 2 (the
-- leader on the left), team B seats 1 and 3.  Every machine draws its own
-- team at the bottom: a team-A machine sees the battle exactly as seated, a
-- team-B machine sees it mirrored (position xor 1) -- the same frame the
-- 2-player link battle's guest uses (src/online/LinkBattleModern.lua), so
-- `battle.linkInvertTie` makes every machine sweep the four battlers, roll
-- Quick Claw and sort the turn in seat order 0,1,2,3.  Each player's own
-- Pokemon stand in a fixed place, the left one or the right one, as on the
-- cartridge (pokeemerald battle_controllers.c: a link multi gives players 0
-- and 3 the left position and 1 and 2 the right, by link id; INFERRED for
-- Gen 4/5, which keep the leader on the left).
--
-- HOST-AUTHORITATIVE OVER A STAR.  Every player picks for their own slot
-- and sends the choice to the host; the host relays each one to that
-- player's partner at once (the partner's choice shows on the standby
-- line), and once every slot standing has a choice it deals the turn to
-- everyone: {type="mb_turn", turn, acts={[seat]=choice}}.  All four run the
-- engine's own turn from a shared seed; at the end of every turn the host
-- streams its state ({type="mb_state"}) and the others adopt it before
-- anything is decided from it, so a machine whose data computed something
-- else is corrected, never split (`battle.linkCorrections` counts them).
-- Replacement rounds are per player: each fallen slot's owner chooses from
-- their own party screen ({type="mb_pick"} to the host), the host deals
-- the round ({type="mb_picks"}) and everyone sends them out in seat order.
-- A player who leaves ends the battle for all four ("X left the battle.",
-- a draw, as the cartridge's link error does).  Seats may be the computer
-- (`ai`): the host chooses for them (the Battle Subway's trainers).
--
-- The cartridge rules kept: no experience, no money, no bag; RUN is a
-- forfeit for the runner's whole team; the teams are copies (heal=true).

local BattleRules = require("src.online.BattleRules")
local LBM = require("src.online.LinkBattleModern")
local HeldItems = require("src.battle.HeldItems")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")

local U = LBM.util
local alive, indexOf = U.alive, U.indexOf

local M = {}

M.PARTNER = { [0] = 2, [1] = 3, [2] = 0, [3] = 1 }
M.SEATS = { 0, 1, 2, 3 }
M.REPLACE_TIMEOUT = 30

function M.teamOf(seat) return (tonumber(seat) or 0) % 2 end

-- canonical seat <-> local position on a machine sitting at `mySeat`
function M.localPos(mySeat, c)
  if (tonumber(mySeat) or 0) % 2 == 0 then return c end
  return (c % 2 == 0) and c + 1 or c - 1
end

local function benchOf(list, taken, chosen)
  for i, mon in ipairs(list or {}) do
    if alive(mon) and not taken[mon] and not (chosen and chosen[mon]) and not (mon.isEgg or mon.egg) then
      return mon, i
    end
  end
  return nil
end

-- the comparison that counts corrections leaves out the computer's own
-- bookkeeping (aiLayer2 ...): only the host runs the AI, so only the host
-- writes it, and adopting it changes nothing anybody sees
local function snapKey(snap)
  for _, row in ipairs(snap.battlers or {}) do
    if type(row) == "table" and type(row.vars) == "table" then
      for k in pairs(row.vars) do
        if type(k) == "string" and (k:match("^ai") or k:match("^g4ai")) then row.vars[k] = nil end
      end
    end
  end
  return U.snapKey(snap)
end

-- "Hilbert and Cheren"
local function pair(a, b)
  if not b or b == "" then return a end
  if not a or a == "" then return b end
  return Strings("%s and %s", a, b)
end
M.pairNames = pair

-- ------------------------------------------------------------ the battle

-- opts:
--   mySeat     0..3
--   seats      { [0..3] = { name, party = packed mons, ai = bool } }
--   seed, rules (BattleRules; format "multi"), strict, replaceTimeout,
--   autoReplace (drivers: no party screen), keepNetOpen (the Subway train
--   keeps its star between cars)
function M.newBattle(game, net, opts)
  local BattleState = require("src.battle.BattleState")
  local GameVersion = require("src.core.GameVersion")
  local POS = BattleState.POS
  local gen = GameVersion.generation and GameVersion.generation(GameVersion.get()) or 3
  gen = math.max(3, tonumber(gen) or 3)
  local rules = BattleRules.sanitize(opts.rules or BattleRules.multi(gen), gen)
  local mySeat = math.floor(tonumber(opts.mySeat) or 0) % 4
  local isHost = net.role == "host"
  local mirror = mySeat % 2 == 1
  local function lp(c) return M.localPos(mySeat, c) end
  local cp = lp -- the mapping is its own inverse
  local mySlot = lp(mySeat)
  local partnerSeat = M.PARTNER[mySeat]
  local partnerSlot = lp(partnerSeat)
  local myTeam = mySeat % 2

  -- every seat's team, through the rules' clamp, identically everywhere
  local parties, names, ai = {}, {}, {}
  for c = 0, 3 do
    local seat = opts.seats and opts.seats[c]
    if type(seat) ~= "table" then return nil, Strings("Multi battle needs\nfour players.") end
    names[c] = tostring(seat.name or ("PLAYER " .. (c + 1)))
    ai[c] = seat.ai and true or nil
    local packed = seat.party or {}
    local ok, why = BattleRules.check(rules, BattleRules.team(rules, packed), game.data)
    if not ok then return nil, Strings("%s's team:\n%s", names[c], why) end
    local team, err = U.buildTeam(game, packed, rules, opts.strict, function(p, why2)
      return Strings("%s's %s isn't\nin this game.\n(%s)", names[c], tostring(p.species), tostring(why2))
    end)
    if not team then return nil, err end
    if #team == 0 then return nil, Strings("%s has no\nPOKéMON to battle.", names[c]) end
    parties[c] = team
  end
  local myParty = parties[mySeat]
  local function partyAt(pos) return parties[cp(pos)] end
  local function nameAt(pos) return names[cp(pos)] end

  for c = 0, 3 do
    for _, mon in ipairs(parties[c]) do
      Runtime.emit("pokemon.received", { mon = mon, from = "link", peerName = names[c] })
    end
  end

  local realParty = game.save.party
  game.save.party = myParty

  local foeL = partyAt(POS.OPPONENT_LEFT)[1]
  local okNew, self = pcall(BattleState.newWild, game, foeL.species, foeL.level or 5)
  if not okNew then
    game.save.party = realParty
    error(self, 0)
  end
  self.kind = "link"
  self.link = true
  self.linkModern = true
  self.linkMulti = true
  self.linkMode = "host"
  self.linkRole = isHost and "host" or "guest"
  self.linkRules = rules
  self.linkInvertTie = mirror or nil
  self.linkMyParty = myParty
  self.linkRealParty = realParty
  self.multiSeat = mySeat
  self.multiParties = parties
  self.multiNames = names
  self.bwAutoSwitch = true
  self.net = net
  self.rng = U.makeRng(opts.seed or 1)
  self.double = true
  self.linkDouble = true
  self.enemyParty = partyAt(POS.OPPONENT_LEFT)
  self.enemyPartyB = partyAt(POS.OPPONENT_RIGHT)
  self.enemyIndex = 1
  self.playerParty = myParty
  self.ally = { party = partyAt(partnerSlot), name = names[partnerSeat], linkPartner = true }
  self.awardExp = function() end
  self.linkCorrections = 0
  self.hostStates = {}
  self.mbTurn = 0
  self.mbBundle, self.mbCollected = {}, {}
  self.mbPicksIn, self.mbPicks = {}, {}
  self.mbAiRng = U.makeRng((opts.seed or 1) + 7919)
  local foeTeam = 1 - myTeam
  local foeNames = pair(names[foeTeam], names[foeTeam + 2])
  self.opponentName = foeNames
  self.introText = Strings("%s\nwant to battle!", foeNames)
  self.trainerLabel_ = function() return foeNames end

  -- THE PLACES.  Every battler is made with no save (no badge boosts: a
  -- link battle has none) and the partner's carries `ally`, which is what
  -- keeps the menu off it (choosingSlotNow) and names its send-outs.
  local basePlace = self.placeBattler
  self.placeBattler = function(s, pos, b)
    if b then
      b.badges = nil
      b.ally = (pos == partnerSlot) or nil
    end
    return basePlace(s, pos, b)
  end
  for pos = 0, 3 do
    local mon = partyAt(pos)[1]
    self:placeBattler(pos, BattleState.makeBattler(game.data, mon, pos % 2 == 0, nil))
  end
  self:syncSides()

  -- each slot's bench is its own player's party
  self.benchFor = function(_, isPlayer, position)
    position = tonumber(position) or (isPlayer and POS.PLAYER_LEFT or POS.OPPONENT_LEFT)
    return partyAt(position) or {}
  end
  self.sideCanContinue = function(s, isPlayer)
    for _, pos in ipairs(isPlayer and { 0, 2 } or { 1, 3 }) do
      local b = s:battlerAt(pos)
      if b and b.mon and alive(b.mon) then return true end
      for _, mon in ipairs(partyAt(pos)) do
        if alive(mon) and not (mon.isEgg or mon.egg) then return true end
      end
    end
    return false
  end
  -- the menu reads its locks off the LEFT battler; my slot may be the right
  local baseMLA, baseFLA = self.menuLockedAction, self.fightLockedAction
  -- (only for the menu: the turn asks about each battler by name, and the
  -- partner standing left must answer for itself -- s.mbExact)
  local function mine(s, b)
    if not s.mbExact and b == s.player and mySlot == POS.PLAYER_RIGHT then return s:battlerAt(mySlot) or b end
    return b
  end
  self.menuLockedAction = function(s, b) return baseMLA(s, mine(s, b)) end
  self.fightLockedAction = function(s, b) return baseFLA(s, mine(s, b)) end
  -- "Go! X!" is mine; the partner's Pokemon are sent out by the partner
  local baseSendOutText = self.sendOutText
  self.sendOutText = function(s, name)
    if s.mbPartnerSending then return Strings("%s sent\nout %s!", names[partnerSeat], name) end
    return baseSendOutText(s, name)
  end

  -- every message carries the battle's id, so a star that runs battle after
  -- battle (the Subway's cars) never hands one battle another's traffic
  local BID = opts.battleId
  local function tag(msg) msg.bid = BID return msg end
  local send = function(msg) net:broadcast(tag(msg)) end

  local function endWith(s, result, text)
    if s.linkEnded or s.result then return end
    s.result = result
    s.afterQueue = "finish"
    s.phase = "messages"
    s.linkBlocked = nil
    if text then s:say(text) end
  end

  -- ---------------------------------------------------- choices
  -- the wire form of a choice: { kind = move|struggle|locked|switch|run|
  -- none, slot, index, target = canonical seat }

  local function decode(s, e, b)
    if not (e and b) then return nil end
    if e.kind == "locked" then
      local was = s.mbExact
      s.mbExact = true
      local a = s:lockedAction(b)
      s.mbExact = was
      return a
    end
    if e.kind == "move" then
      local moves = b.curMoves or {}
      if #moves == 0 then return nil end
      local slot = math.max(1, math.min(#moves, math.floor(tonumber(e.slot) or 1)))
      return moves[slot]
    elseif e.kind == "struggle" then
      return { id = "STRUGGLE", pp = 1, struggle = true }
    end
    return nil
  end

  local function encode(s, b, action, target)
    if not (b and action) then return { kind = "none" } end
    local e = {}
    if action.special == "playerSwitch" or action.special == "aiSwitch" then
      e.kind = "switch"
      local list = partyAt(b.position)
      e.index = action.mon and indexOf(list, action.mon) or tonumber(action.index)
    elseif action.struggle then
      e.kind = "struggle"
    elseif action.special then
      e.kind = "locked"
    else
      for i, mv in ipairs(b.curMoves or {}) do if mv == action then e.slot = i end end
      e.kind = e.slot and "move" or "locked"
    end
    if target and target.position then e.target = cp(target.position) end
    return e
  end
  M.encode = encode

  -- a choice in words, for the partner's standby line
  local function describe(s, seat, e)
    if type(e) ~= "table" then return nil end
    local b = s:battlerAt(lp(seat))
    if e.kind == "switch" then
      local mon = parties[seat][tonumber(e.index) or 0]
      return Strings("%s: switch to\n%s", names[seat], mon and (mon.nickname or tostring(mon.species)) or "?")
    elseif e.kind == "run" then
      return Strings("%s: forfeit", names[seat])
    elseif e.kind == "move" and b then
      local mv = (b.curMoves or {})[tonumber(e.slot) or 0]
      local def = mv and s.data.moves[mv.id]
      local t = tonumber(e.target)
      local tb = t and s:battlerAt(lp(t))
      return Strings("%s: %s%s", names[seat], def and def.name or "?", tb and ("\n-> " .. tostring(tb.name)) or "")
    elseif e.kind == "none" then
      return nil
    end
    return Strings("%s: ready", names[seat])
  end

  -- ---------------------------------------------------- send-outs

  local function sendOutEnemy(s, mon, pos)
    local previous = s:battlerAt(pos)
    if previous then s:restoreMimicked(previous) end
    if pos == POS.OPPONENT_LEFT then s.enemyIndex = indexOf(partyAt(pos), mon) or s.enemyIndex end
    local incoming = BattleState.makeBattler(s.data, mon, false)
    s:placeBattler(pos, incoming)
    for _, b in ipairs(s:foesOf(incoming)) do
      b.trappingTurns, b.trapMove, b.trapDamage = nil, nil, nil
    end
    s:syncSides()
    Runtime.emit("battle.battler_switched", {
      battle = s, side = s.sides[2], battler = incoming, previous = previous,
    })
    s:abilitySwitchOut(previous)
    s.enemySendingOut = true
    s:sayNext(Strings("%s sent\nout %s!", nameAt(pos), incoming.name))
    s:actNext(function()
      s.enemySendingOut = false
      s:startGrowIn(incoming)
      s:shinyAnim(incoming, true)
      s:actNext(function()
        require("src.core.Sound").playCry(s.data, incoming.mon.species)
        HeldItems.onEntry(s, incoming)
      end)
    end)
    s:actNext(function() s:abilitySwitchIn(incoming) end)
  end

  local function placeAt(s, pos, mon)
    if pos % 2 == 0 then
      s.mbPartnerSending = (pos == partnerSlot) or nil
      s:switchPlayerInto(pos, mon)
      s.mbPartnerSending = nil
    else
      sendOutEnemy(s, mon, pos)
    end
  end

  local baseExecuteAction = self.executeAction
  self.executeAction = function(s, user, target, action)
    if action and action.linkMon then
      if s.result or not (user and user.mon) or (user.mon.hp or 0) <= 0 then return end
      local mon = action.linkMon
      if not alive(mon) then return end
      for _, b in s:activeBattlers() do if b and b.mon == mon then return end end
      user.actedTurn = s.turnCount
      placeAt(s, user.position, mon)
      return
    end
    return baseExecuteAction(s, user, target, action)
  end

  -- ---------------------------------------------------- who is out

  local function seatOut(c)
    for _, mon in ipairs(parties[c]) do
      if alive(mon) and not (mon.isEgg or mon.egg) then return false end
    end
    return true
  end
  local function teamOut(t) return seatOut(t) and seatOut(t + 2) end

  local function decide(s)
    if s.result then return true end
    local mineOut, theirsOut = teamOut(myTeam), teamOut(foeTeam)
    local mineNames = pair(names[myTeam], names[myTeam + 2])
    if mineOut and theirsOut then
      endWith(s, "draw", Strings("Both sides are out\nof POKéMON!\fThe battle is\na draw!"))
    elseif mineOut then
      endWith(s, "lose", Strings("%s are out of\nPOKéMON!\f%s win!", mineNames, foeNames))
    elseif theirsOut then
      endWith(s, "win", Strings("%s are out of\nPOKéMON!\f%s win!", foeNames, mineNames))
    end
    return s.result ~= nil
  end
  self.multiDecide = decide

  -- ---------------------------------------------------- state

  local function sideOfTeam(s, t)
    local sides = s.sides or {}
    if t == myTeam then return sides[1] end
    return sides[2]
  end

  local function snapshot(s)
    local snap = { parties = {}, active = {}, battlers = {} }
    for c = 0, 3 do
      local rows = {}
      for i, mon in ipairs(parties[c]) do rows[i] = U.monSnap(mon) end
      snap.parties[c + 1] = rows
      local b = s:battlerAt(lp(c))
      -- (a fainted Pokemon still on its place is nobody standing there)
      if b and not (b.mon and alive(b.mon)) then b = nil end
      snap.active[c + 1] = (b and b.mon and indexOf(parties[c], b.mon)) or 0
      snap.battlers[c + 1] = U.battlerSnap(b) or false
    end
    snap.field = U.scalarCopy(s.field)
    snap.sides = { U.sideCopy(sideOfTeam(s, 0) or {}), U.sideCopy(sideOfTeam(s, 1) or {}) }
    return snap
  end
  self.multiSnapshot = snapshot

  local function adopt(s, snap)
    for c = 0, 3 do
      for i, row in ipairs((snap.parties or {})[c + 1] or {}) do
        local mon = parties[c][i]
        if mon and type(row) == "table" then
          mon.hp = math.max(0, math.min(tonumber(row.hp) or 0, mon.stats and mon.stats.hp or 999))
          mon.status = row.status
          mon.sleepTurns = row.sleepTurns
          mon.item = row.item
          for j, pp in ipairs(row.pp or {}) do
            if mon.moves[j] then mon.moves[j].pp = tonumber(pp) or mon.moves[j].pp end
          end
        end
      end
    end
    for c = 0, 3 do
      local pos = lp(c)
      local idx = tonumber(snap.active and snap.active[c + 1]) or 0
      local cur = s:battlerAt(pos)
      local mon = parties[c][idx]
      if mon and alive(mon) and not (cur and cur.mon == mon) then
        cur = BattleState.makeBattler(s.data, mon, pos % 2 == 0, nil)
        s:placeBattler(pos, cur)
        s:syncSides()
      end
      local row = snap.battlers and snap.battlers[c + 1]
      if cur and type(row) == "table" then
        U.applyScalars(cur, row.vars)
        cur.stages = cur.stages or {}
        for k in pairs(cur.stages) do cur.stages[k] = 0 end
        for k, v in pairs(row.stages or {}) do cur.stages[k] = v end
        if cur.shownHP then cur.shownHP = cur.mon.hp end
        cur.ally = (pos == partnerSlot) or nil
        cur.badges = nil
      end
    end
    if type(snap.field) == "table" and s.field then U.applyScalars(s.field, snap.field) end
    for t = 0, 1 do
      local side, row = sideOfTeam(s, t), snap.sides and snap.sides[t + 1]
      if side and type(row) == "table" then
        local keep = side.index
        U.applyScalars(side, row)
        side.index = keep
      end
    end
  end

  local function tryAdopt(s, turn)
    local snap = s.hostStates[turn]
    if not snap then return false end
    s.hostStates[turn] = nil
    local before = snapKey(snapshot(s))
    local ok, err = pcall(adopt, s, snap)
    if not ok then
      Logger.warn("multi: host state for turn %s would not apply: %s", tostring(turn), tostring(err))
      return true
    end
    s.nextInsert = 0
    for c = 0, 3 do
      local b = s:battlerAt(lp(c))
      if b and b.mon then
        if b.mon.hp <= 0 and not b.faintQueued then
          s:onFaint(b)
          if not s.linkRefillQueued then
            s.linkRefillQueued = true
            s:act(function() s.linkRefillQueued = nil s:fillEmptySlots() end)
          end
        elseif b.mon.hp > 0 and (b.fainted or b.faintQueued) then
          b.fainted, b.faintQueued = nil, nil
        end
      end
    end
    local after = snapKey(snapshot(s))
    if before ~= after then
      if M.debugCorrect then M.debugCorrect(s, turn, before, after) end
      s.linkCorrections = s.linkCorrections + 1
      Logger.info("multi: host corrected turn %s", tostring(turn))
      Runtime.emit("link.corrected", { battle = s, turn = turn })
    end
    return true
  end

  local function closeTurn(s)
    s:act(function()
      if s.linkEnded or s.result then return end
      local turn = s.mbTurn
      if isHost then
        send({ type = "mb_state", turn = turn, snap = snapshot(s) })
      elseif not tryAdopt(s, turn) then
        s.linkBlocked = turn
      end
    end)
  end

  -- ---------------------------------------------------- replacement rounds

  local REPLACE_TIMEOUT = tonumber(opts.replaceTimeout) or M.REPLACE_TIMEOUT
  self.linkRound = 0

  local function onField(s)
    local taken = {}
    for p = 0, 3 do
      local b = s:battlerAt(p)
      if b and b.mon and alive(b.mon) then taken[b.mon] = true end
    end
    return taken
  end

  -- the seats whose slot needs somebody and who still have somebody
  local function emptySeats(s)
    local taken = onField(s)
    local need = {}
    for c = 0, 3 do
      local b = s:battlerAt(lp(c))
      if not (b and b.mon and alive(b.mon)) and benchOf(parties[c], taken) then
        need[#need + 1] = c
      end
    end
    return need
  end

  local function pickedSet(open)
    local chosen = {}
    for c, idx in pairs(open.picks) do chosen[parties[c][idx] or false] = true end
    return chosen
  end

  -- the host: every seat in the round has its pick -> deal it
  local function hostDeal(s)
    local open = s.linkRoundOpen
    if not (isHost and open) or open.dealt then return end
    local inbox = s.mbPicksIn[open.round] or {}
    for _, c in ipairs(open.need) do
      if open.picks[c] == nil then
        if ai[c] then
          local _, i = benchOf(parties[c], onField(s), pickedSet(open))
          open.picks[c] = i or 0
        elseif c ~= mySeat and inbox[c] then
          open.picks[c] = inbox[c]
        end
      end
    end
    for _, c in ipairs(open.need) do if open.picks[c] == nil then return end end
    local wire = {}
    for c, idx in pairs(open.picks) do wire[tostring(c)] = idx end
    open.dealt = true
    s.mbPicks[open.round] = wire
    send({ type = "mb_picks", round = open.round, picks = wire })
  end

  local function applyRound(s, wire)
    local open = s.linkRoundOpen
    s.linkRoundOpen = nil
    s.linkPickReplacement = nil
    s.nextInsert = 0
    local chosen = {}
    for _, c in ipairs(open.need) do
      local list = parties[c]
      local mon = list[tonumber(wire[tostring(c)]) or 0]
      local taken = onField(s)
      if not (mon and alive(mon) and not taken[mon] and not chosen[mon]) then
        mon = benchOf(list, taken, chosen)
      end
      if mon then
        chosen[mon] = true
        placeAt(s, lp(c), mon)
      end
    end
  end

  local function pickMine(s, open, idx)
    open.picks[mySeat] = idx
    open.mineSent = true
    if isHost then hostDeal(s)
    else net:send(tag({ type = "mb_pick", round = open.round, idx = idx })) end
  end

  local function askLocal(s)
    local open = s.linkRoundOpen
    local function accept(mon)
      if not (s.linkRoundOpen == open and open.picks[mySeat] == nil) then return false end
      local idx = indexOf(myParty, mon)
      if not (idx and alive(mon) and not onField(s)[mon] and not (mon.isEgg or mon.egg)) then return false end
      open.screen, open.clock = nil, nil
      pickMine(s, open, idx)
      return true
    end
    -- (the time limit runs on across a screen asked again)
    open.clock = open.clock or REPLACE_TIMEOUT
    s.linkPickReplacement = function(mon)
      local screen = open.screen
      if accept(mon) and screen and game.stack:top() == screen then game.stack:pop() end
    end
    open.timeout = function()
      local mon = benchOf(myParty, onField(s))
      local screen = open.screen
      if mon and accept(mon) and screen and game.stack:top() == screen then game.stack:pop() end
    end
    if opts.autoReplace then return end
    local Gen4Battle = require("src.battle.Gen4Battle")
    local ok, screen = pcall(function()
      return s:buildScreen(Gen4Battle.partyScreenId(s) or "PartyMenu", {
        battle = s, forceSwitch = true,
        onSwitch = function(mon)
          if not accept(mon) and s.linkRoundOpen == open and open.picks[mySeat] == nil then
            if mon and not alive(mon) then
              s.nextInsert = 0
              s:sayNext(Strings("There's no will\nto fight!"))
            end
            open.reopen = true
          end
        end,
      })
    end)
    if ok and screen then
      local baseUpd = screen.update
      screen.update = function(sc, dt, ...)
        if baseUpd then baseUpd(sc, dt, ...) end
        if open.clock and s.linkRoundOpen == open then
          open.clock = open.clock - (dt or 0)
          if open.clock <= 0 then open.clock = nil open.timeout() end
        end
      end
      open.screen = screen
      game.stack:push(screen)
    end
  end

  local function replacementRound(s)
    s.linkRoundQueued = nil
    if s.result or s.linkRoundOpen then return end
    if decide(s) then return end
    local need = emptySeats(s)
    if #need == 0 then return end
    s.linkRound = s.linkRound + 1
    local open = { round = s.linkRound, need = need, picks = {} }
    s.linkRoundOpen = open
    s.phase = "messages"
    local mineNeeded = false
    for _, c in ipairs(need) do if c == mySeat then mineNeeded = true end end
    open.mineSent = not mineNeeded
    if mineNeeded then askLocal(s) end
    if isHost then hostDeal(s) end
  end

  local function queueRound(s)
    if s.linkRoundQueued then return end
    s.linkRoundQueued = true
    s:act(function() replacementRound(s) end)
  end

  self.playerMonFainted = function(s) if not s.result then replacementRound(s) end end
  self.enemyMonFainted = self.playerMonFainted
  self.fillEmptySlots = function(s)
    s.pendingReplacements = nil
    queueRound(s)
  end

  -- true while a round waits for its picks
  self.linkRoundWait = function(s)
    local open = s.linkRoundOpen
    if not open then return false end
    if open.reopen then
      open.reopen = nil
      askLocal(s)
      return true
    end
    -- a party screen that closed without a pick (backed out, or popped by
    -- something else): ask again, so the round can never wait on a screen
    -- that is gone
    if open.screen and game.stack:top() == s then
      open.screen = nil
      if open.picks[mySeat] == nil and not open.mineSent then
        askLocal(s)
        return true
      end
    end
    if open.clock and not open.screen and game.stack:top() == s then
      open.clock = open.clock - (s.linkDt or 0)
      if open.clock <= 0 then open.clock = nil open.timeout() end
    end
    if isHost then hostDeal(s) end
    local wire = s.mbPicks[open.round]
    if not wire then return true end
    s.mbPicks[open.round] = nil
    applyRound(s, wire)
    return false
  end

  -- ---------------------------------------------------- the turn

  -- the host chooses for a computer seat (its own RNG: the shared one must
  -- roll the same numbers on every machine)
  local function aiChoice(s, c)
    local pos = lp(c)
    local b = s:battlerAt(pos)
    if not (b and b.mon and alive(b.mon)) then return { kind = "none" } end
    local keep = s.rng
    s.rng = s.mbAiRng
    s.mbExact = true
    local ok, act = pcall(function()
      local locked = s:lockedAction(b)
      if locked then return locked end
      if pos % 2 == 0 then return require("src.battle.AllyAI").choose(s, b, s.rng) end
      return s:vanillaEnemyAction(b)
    end)
    s.rng = keep
    s.mbExact = nil
    if not ok then Logger.warn("multi: AI for seat %d failed: %s", c, tostring(act)) act = nil end
    if not act then
      for i, mv in ipairs(b.curMoves or {}) do
        if (mv.pp or 0) > 0 then return { kind = "move", slot = i } end
      end
      return { kind = "struggle" }
    end
    local target = (s.chosenTargets or {})[pos]
    if not target and not act.special then
      target = s:defaultTargetFor(b)
    end
    return encode(s, b, act, target)
  end

  local function resolve(s, turn, acts)
    s.mbTurn = turn
    s.mbPartnerChoice = nil
    -- RUN: the runner's whole team forfeits
    local ran = {}
    for c = 0, 3 do
      local e = acts[tostring(c)]
      if type(e) == "table" and e.kind == "run" then ran[c % 2] = c end
    end
    if ran[0] or ran[1] then
      if ran[0] and ran[1] then
        endWith(s, "draw", Strings("Both teams\nforfeited.\fThe battle is\na draw!"))
      elseif ran[myTeam] then
        endWith(s, "lose", Strings("%s forfeited\nthe match.", names[ran[myTeam]]))
      else
        endWith(s, "win", Strings("%s forfeited\nthe match.", names[ran[foeTeam]]))
      end
      return
    end
    s:clearTurnFlinches()
    s.mbExact = true
    local actions, targets = {}, {}
    for c = 0, 3 do
      local pos = lp(c)
      local b = s:battlerAt(pos)
      local e = acts[tostring(c)]
      if b and b.mon and alive(b.mon) then
        local act
        if type(e) == "table" and e.kind == "switch" then
          local list = parties[c]
          local idx = math.max(1, math.min(#list, math.floor(tonumber(e.index) or 1)))
          act = { special = (pos % 2 == 0) and "playerSwitch" or "aiSwitch", linkMon = list[idx] }
        elseif type(e) == "table" then
          act = decode(s, e, b)
        end
        if not act then
          act = s:lockedAction(b)
          if not act then
            for _, mv in ipairs(b.curMoves or {}) do
              if (mv.pp or 0) > 0 then act = mv break end
            end
          end
          act = act or { id = "STRUGGLE", pp = 1, struggle = true }
        end
        actions[pos] = act
        local t = type(e) == "table" and tonumber(e.target)
        if t and t >= 0 and t <= 3 then targets[pos] = s:battlerAt(lp(t)) end
      end
    end
    s.mbExact = nil
    s.mbActs = actions
    s.pendingActions = {}
    s.chosenTargets = targets
    BattleState.resolveTurn(s, actions[POS.PLAYER_LEFT])
    s.mbActs = nil
    s.phase = "messages"
    s.afterQueue = "linkNext"
    closeTurn(s)
  end

  self.enemyAction = function(s, b)
    local pos = b and b.position
    return pos and s.mbActs and s.mbActs[pos] or nil
  end
  self.actionFor = function(s, b)
    return b and s.mbActs and s.mbActs[b.position] or nil
  end

  -- the host: deal the turn once every slot standing has its choice
  local function hostTry(s)
    if not isHost or s.result or s.linkEnded then return end
    if s.phase ~= "waitRemote" then return end
    local turn = s.mbTurn + 1
    local got = s.mbCollected[turn] or {}
    local acts = {}
    for c = 0, 3 do
      local b = s:battlerAt(lp(c))
      if b and b.mon and alive(b.mon) then
        if ai[c] then
          got[c] = got[c] or aiChoice(s, c)
        elseif got[c] == nil then
          s.mbCollected[turn] = got
          return
        end
        acts[tostring(c)] = got[c]
      elseif type(got[c]) == "table" and got[c].kind == "run" then
        acts[tostring(c)] = got[c] -- a forfeit counts from an empty slot too
      end
    end
    s.mbCollected[turn] = nil
    send({ type = "mb_turn", turn = turn, acts = acts })
    resolve(s, turn, acts)
  end

  -- a player's choice reaching the host (its own included)
  local function collect(s, seat, turn, e)
    if type(e) ~= "table" then return end
    turn = tonumber(turn) or 0
    if turn <= s.mbTurn then return end
    s.mbCollected[turn] = s.mbCollected[turn] or {}
    s.mbCollected[turn][seat] = e
    -- the partner sees it at once
    local partner = M.PARTNER[seat]
    if not ai[partner] then
      if partner == mySeat then
        s.mbPartnerChoice = describe(s, seat, e)
      else
        net:sendTo(partner, tag({ type = "mb_partner", seat = seat, turn = turn, e = e }))
      end
    end
    hostTry(s)
  end

  local function tryResolve(s)
    if isHost then return hostTry(s) end
    if s.phase ~= "waitRemote" or s.result or s.linkEnded then return end
    local turn = s.mbTurn + 1
    local acts = s.mbBundle[turn]
    if not acts then return end
    s.mbBundle[turn] = nil
    resolve(s, turn, acts)
  end

  local function submit(s, e)
    s.phase = "waitRemote"
    s.choosingSlot = nil
    local turn = s.mbTurn + 1
    if isHost then collect(s, mySeat, turn, e)
    else net:send(tag({ type = "mb_act", turn = turn, e = e })) end
    tryResolve(s)
  end
  self.multiSubmit = submit

  self.resolveTurn = function(s, action)
    s.pendingActions = s.pendingActions or {}
    local a = s.pendingActions[mySlot]
    if a == nil and action ~= nil then a = action end
    local b = s:battlerAt(mySlot)
    if not (b and b.mon and alive(b.mon)) then
      submit(s, { kind = "none" })
      return
    end
    if not a then
      -- nothing chosen for my own slot yet: back to the menu
      s.choosingSlot = mySlot
      s.phase = "menu"
      return
    end
    local e = encode(s, b, a, s.chosenTargets and s.chosenTargets[mySlot])
    s.pendingActions = {}
    submit(s, e)
  end

  self.resolveSwitch = function(s, newMon)
    s:chooseAction({ special = "playerSwitch", mon = newMon })
  end

  self.openItems = function(s)
    s:say(Strings("Items can't be\nused in a link\nbattle!"))
    s.phase = "messages"
    s.afterQueue = "menu"
  end

  self.tryRun = function(s)
    s.phase = "messages"
    s.afterQueue = "menu"
    s:sayChoice(Strings("Would you like to\nforfeit the match?"), function(yes)
      if yes then s.afterQueue = "linkForfeit" end
    end)
  end

  -- ---------------------------------------------------- the intro

  local baseEnter = self.enter
  self.enter = function(s, ...)
    -- the left player-side Pokemon is the partner's when I stand right
    s.mbPartnerSending = (mySlot == POS.PLAYER_RIGHT) or nil
    local r = baseEnter(s, ...)
    s.mbPartnerSending = nil
    -- the two right-hand Pokemon (the intro sends the left ones)
    local foeR = s:battlerAt(POS.OPPONENT_RIGHT)
    if foeR then s:say(Strings("%s sent\nout %s!", nameAt(POS.OPPONENT_RIGHT), foeR.name)) end
    local mineR = s:battlerAt(POS.PLAYER_RIGHT)
    if mineR then
      if mySlot == POS.PLAYER_RIGHT then s:say(baseSendOutText(s, mineR.name))
      else s:say(Strings("%s sent\nout %s!", names[partnerSeat], mineR.name)) end
    end
    return r
  end

  -- ---------------------------------------------------- the loop

  -- anything not the battle's own (the Subway train's next car ...) is kept
  -- for whoever runs the star after the battle: battle.mbOther
  local OWN = { mb_act = true, mb_pick = true, mb_gone = true, bye = true, mb_turn = true,
                mb_state = true, mb_picks = true, mb_partner = true, mb_end = true }
  self.mbOther = {}
  local function handle(s, from, msg)
    local t = msg.type
    if not OWN[t] then
      s.mbOther[#s.mbOther + 1] = { from = from, msg = msg }
      return
    end
    if t ~= "mb_gone" and msg.bid ~= BID then return end -- another battle's
    if isHost then
      if t == "mb_act" then
        collect(s, from, msg.turn, msg.e)
      elseif t == "mb_pick" then
        local r = tonumber(msg.round)
        if r then
          s.mbPicksIn[r] = s.mbPicksIn[r] or {}
          s.mbPicksIn[r][from] = tonumber(msg.idx)
          hostDeal(s)
        end
      elseif t == "mb_gone" then
        if not s.result and not s.linkEnded and not (s.mbBye and s.mbBye[from]) then
          send({ type = "mb_end", reason = Strings("%s left the\nbattle.", names[from]) })
          endWith(s, "draw", Strings("%s left the\nbattle.", names[from]))
        end
      elseif t == "bye" then
        s.mbBye = s.mbBye or {}
        s.mbBye[from] = true
      end
      return
    end
    if t == "mb_turn" then
      local turn = tonumber(msg.turn)
      if turn and type(msg.acts) == "table" then s.mbBundle[turn] = msg.acts end
    elseif t == "mb_state" then
      local turn = tonumber(msg.turn)
      if turn and type(msg.snap) == "table" then s.hostStates[turn] = msg.snap end
    elseif t == "mb_picks" then
      local r = tonumber(msg.round)
      if r and type(msg.picks) == "table" then s.mbPicks[r] = msg.picks end
    elseif t == "mb_partner" then
      local seat = tonumber(msg.seat)
      if seat == partnerSeat and tonumber(msg.turn) == s.mbTurn + 1 then
        s.mbPartnerChoice = describe(s, seat, msg.e)
      end
    elseif t == "mb_end" then
      endWith(s, "draw", type(msg.reason) == "string" and msg.reason or Strings("The link was\nlost."))
    elseif t == "bye" then
      s.linkPeerGone = true
    elseif t == "mb_gone" then
      s.linkPeerGone = true
      s.linkLost = true
    end
  end

  local baseUpdate = self.update
  self.update = function(s, dt)
    net:update()
    for _, item in ipairs(net:poll()) do handle(s, item.from, item.msg) end
    local needsPeer = s.phase == "waitRemote" or s.phase == "menu"
      or (s.linkBlocked and not s.hostStates[s.linkBlocked])
      or (s.linkRoundOpen and s.linkRoundOpen.mineSent and not s.mbPicks[s.linkRoundOpen.round])
    if not isHost and s.linkPeerGone and needsPeer and not s.result and not s.linkEnded then
      endWith(s, "draw", s.linkLost and Strings("The link was\nlost.")
        or Strings("%s left the\nbattle.", names[0]))
    end
    if s.linkBlocked then
      s:tickFx()
      if tryAdopt(s, s.linkBlocked) then s.linkBlocked = nil end
      return
    end
    s.linkDt = dt
    if not s.result and s:linkRoundWait() then
      s:tickFx()
      return
    end
    if s.phase == "waitRemote" then
      s:tickFx()
      tryResolve(s)
      return
    end
    if s.phase == "messages" and s.afterQueue == "linkForfeit" then
      s:tickFx()
      if not s:updateQueue() then
        s.afterQueue = "menu"
        submit(s, { kind = "run" })
      end
      return
    end
    if s.phase == "messages" and s.afterQueue == "linkNext" then
      s:tickFx()
      if not s:updateQueue() then
        s.afterQueue = "menu"
        s.phase = "menu"
        s.choosingSlot = nil
      end
      return
    end
    if s.phase == "menu" and not s.result then
      local b = s:battlerAt(mySlot)
      if not (b and b.mon and alive(b.mon)) then
        submit(s, { kind = "none" })
        return
      end
      s.choosingSlot = mySlot
      if mySlot == POS.PLAYER_RIGHT and not s:battlerAt(POS.PLAYER_LEFT) then
        -- (BattleState's "only the tag partner is left" skip must not fire
        -- for a player standing on the right)
        local keep = s.ally
        s.ally = nil
        baseUpdate(s, dt)
        s.ally = keep
        return
      end
    end
    baseUpdate(s, dt)
  end

  -- the standby line: who is still choosing, and the partner's choice
  local baseDraw = self.draw
  self.draw = function(s, ...)
    local r = baseDraw(s, ...)
    if s.phase == "waitRemote" and not s.result and not opts.noStandby then
      pcall(function()
        local WorldUi = require("src.ui.online.WorldUi")
        local st = s.mbStyle or WorldUi.style(game)
        s.mbStyle = st
        local w, h = 240, 160
        if s.uiSize then w, h = s:uiSize() end
        local text = Strings("Link standby...")
        if s.mbPartnerChoice then text = text .. "\n" .. s.mbPartnerChoice end
        -- over the message box, where the cartridge prints its standby line
        local lines = 1
        for _ in text:gmatch("\n") do lines = lines + 1 end
        local boxH = lines * (st:lineHeight() + 1) + 12
        WorldUi.drawText(st, 4, h - boxH - 4, w - 8, text)
      end)
    end
    return r
  end

  local baseFinish = self.finish
  self.finish = function(s)
    if not s.linkEnded then
      s.linkEnded = true
      if not opts.keepNetOpen then send({ type = "bye" }) end
    end
    if not opts.keepNetOpen then net:close() end
    if game.save.party == myParty then game.save.party = realParty end
    baseFinish(s)
    if game.save.party == myParty then game.save.party = realParty end
  end

  local baseExit = self.exit
  self.exit = function(s, ...)
    if game.save.party == myParty then game.save.party = realParty end
    if baseExit then return baseExit(s, ...) end
  end

  return self
end

-- ------------------------------------------------------------ the whole flow

-- session: nil (host code / join code screens), or
--   { role = "host", transport = t | source = src, channels = {...} }
--   { role = "join", channel = ch }
--   { world = true, role = "host"|"join" } (the world's "multi" service)
-- opts: { role = "host"|"join", rules, need = 4, coop = {...}, title }
-- M.defaults: merged under every open's opts (harnesses: autoTeam, invite,
-- connector, joinOptions); M.onLobby(lobby): told about every lobby opened
M.defaults = {}
local function withDefaults(opts)
  local o = {}
  for k, v in pairs(M.defaults or {}) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  return o
end
M.withDefaults = withDefaults

function M.open(game, session, opts, onDone)
  local lobby = require("src.online.MultiLobby").open(game, session, withDefaults(opts), onDone)
  if M.onLobby then pcall(M.onLobby, lobby) end
  return lobby
end

-- ------------------------------------------------------------ the counters

-- THE ENTRY POINT FOR A SCRIPT ROW (the link-room scripts call it): the
-- room's whole multi battle from the counter -- LEADER / JOIN, the code,
-- the gathering, the teams, the battle -- parking the script until it is
-- over.  Returns "win" | "lose" | "draw" | "cancelled" | "failed".
--   ctx    the script context (ctx.game, ctx.runner)
--   opts   { role = "host"|"join" (else asked), rules, preset, title }
function M.clubEntry(ctx, opts)
  local game = ctx and ctx.game
  if not (game and game.stack) then return "failed" end
  local o = withDefaults(opts)
  if o.askRole == nil and not o.role then o.askRole = true end
  local LinkRooms = require("src.online.LinkRooms")
  local result, why = nil, nil
  LinkRooms.await(ctx, function(done)
    M.open(game, o.role and { role = o.role } or nil, o, function(r, w)
      result, why = r, w
      done(r)
    end)
  end)
  M.lastClub = { result = result, why = why }
  if why and (result == "failed" or result == "cancelled") then
    Logger.info("multi: counter ends %s (%s)", tostring(result), tostring(why))
  end
  return result or "failed"
end

return M
