-- Gen 3 / 4 / 5 link battles (docs/online-design.md WS5).
--
-- LinkBattle.new hands a Gen 3+ match here.  The Gen 1/2 lockstep turn in
-- LinkBattle.lua is left exactly as 0.7.x peers run it; this one rides the
-- engine's own turn instead (BattleState.resolveTurn / resolveSwitch /
-- switchPlayerInto), which is what a Hoenn, Sinnoh or Unova battle needs:
-- the turn-scoped flags (Protect, Fake Out, Revenge ...), Quick Claw and
-- Custap, Trick Room, B/W's Pursuit and choice rules, abilities and entry
-- hazards on every send-out.
--
-- Two modes, both run the full engine on both machines from a shared seed:
--
--   lockstep  the two games' battle data match (verdict `full`).  Each turn
--             both sides exchange a component state hash; a fatal split
--             ends the match with a message (the cable-pull draw).
--   host      two games of one family whose data differ (verdict `family`:
--             Platinum vs HeartGold, Emerald vs FireRed, ...).  The host is
--             the authority: it streams its state after every turn, and the
--             guest -- which simulates the turn with its own ROM's data,
--             text and sprites so it has something to show -- adopts that
--             state before anything is decided from it.  A guest whose data
--             computed a different turn is corrected, never desynced.
--
-- Perspective: each machine is "player" for its own Pokemon.  Everything
-- that draws from the shared RNG in a player-then-enemy order is made
-- host-first on the guest through `battle.linkInvertTie` (BattleState reads
-- it in the turn order, Quick Claw, activeBattlers and the end-of-turn
-- sweeps), so the two machines roll the same numbers for the same Pokemon.
--
-- Cartridge rules kept: no experience, no money, no items from the bag;
-- RUN is a forfeit (the runner loses, as the Gen 3-5 link battles ask);
-- a mid-turn replacement (a faint, U-turn, Baton Pass) is the next healthy
-- party member in party order on both machines (the cartridge asks; this
-- is the documented divergence the Gen 1/2 link battle already makes).

local BattleRules = require("src.online.BattleRules")
local Fingerprint = require("src.link.Fingerprint")
local HeldItems = require("src.battle.HeldItems")
local Logger = require("src.core.Logger")
local Protocol = require("src.link.Protocol")
local Runtime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")

local M = {}

-- ------------------------------------------------------------ helpers

local function makeRng(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(a, b)
    s = (s * 16807) % 2147483647
    if a == nil then return s / 2147483647 end
    if b == nil then a, b = 1, a end
    return a + (s % (b - a + 1))
  end
end
M.makeRng = makeRng

local function alive(mon) return mon and (mon.hp or 0) > 0 end

local function firstHealthy(party, except)
  for i, mon in ipairs(party) do
    if alive(mon) and mon ~= except and not (mon.isEgg or mon.egg) then return mon, i end
  end
  return nil
end

local function indexOf(list, x)
  for i, v in ipairs(list) do if v == x then return i end end
  return nil
end

local function displayName(b)
  return b.isPlayer and b.name or ("Enemy " .. tostring(b.name))
end

-- full HP and PP, no status: the Gen 3-5 link battle's copies start fresh
local function heal(data, mon)
  mon.hp = mon.stats and mon.stats.hp or mon.hp
  mon.status, mon.sleepTurns = nil, nil
  local Pokemon = require("src.pokemon.Pokemon")
  for _, mv in ipairs(mon.moves or {}) do
    local def = data.moves and data.moves[mv.id]
    if def then
      local ok, max = pcall(Pokemon.maxPP, def, mv)
      if ok and tonumber(max) then mv.pp = max end
    end
  end
end

-- the rules' team, unpacked through the same clamp on both machines
local function buildTeam(game, packed, rules, strict, errFmt)
  local team = BattleRules.team(rules, packed)
  local out = {}
  for _, p in ipairs(team) do
    local mon, why = Protocol.unpackMon(game.data, p, {
      strict = strict, forceLevel = BattleRules.levelFor(rules, p),
    })
    if mon then
      if rules.heal then heal(game.data, mon) end
      out[#out + 1] = mon
    elseif strict then
      return nil, errFmt(p, why)
    end
  end
  return out
end

-- ------------------------------------------------------------ state hash

local STAGE_SKIP = {}

local function stageStr(b)
  local keys = {}
  for k, v in pairs(b.stages or {}) do
    if type(v) == "number" and v ~= 0 and not STAGE_SKIP[k] then keys[#keys + 1] = k end
  end
  table.sort(keys)
  for i, k in ipairs(keys) do keys[i] = k .. "=" .. tostring(b.stages[k]) end
  return table.concat(keys, ",")
end

local function ppStr(mon)
  local out = {}
  for i, mv in ipairs(mon.moves or {}) do
    out[i] = ("%s=%s"):format(tostring(mv.id), tostring(mv.pp or 0))
  end
  return table.concat(out, ",")
end

-- battler keys that are presentation, or bookkeeping a machine writes for
-- its own menu, and so never part of the shared state
local PRESENTATION = {
  shownHP = true, shownStatus = true, drainFloor = true, name = true,
  isPlayer = true, position = true, fainted = true, faintQueued = true,
  showSpecies = true, shownSpecies = true, picAnim = true, monAnim = true,
  flinched = true, boundTurns = true, sendingOut = true, growIn = true,
  hidden = true, slide = true, lastShownHP = true, actedTurn = true,
  g4aiInTurn = true,
}

local function presentational(k)
  if PRESENTATION[k] then return true end
  return type(k) ~= "string" or k:match("^shown") or k:match("^fx") or k:match("^anim")
    or k:match("^pic") or k:match("^draw") or k:match("^gen4Ball") or k:match("^gen3Ball")
end

local function scalarKeys(b)
  local keys = {}
  for k, v in pairs(b) do
    local t = type(v)
    if (t == "number" or t == "string" or t == "boolean") and not presentational(k) then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  return keys
end

local function off(v) return v == nil or v == false or v == 0 end

local function volStr(b)
  local out = {}
  for _, k in ipairs(scalarKeys(b)) do
    if not off(b[k]) then out[#out + 1] = k .. "=" .. tostring(b[k]) end
  end
  return table.concat(out, ",")
end

local function activeStr(b)
  if not (b and b.mon) then return "-" end
  return ("%s:%d:%s:%s:%s:%s"):format(tostring(b.mon.species), b.mon.hp or 0,
    tostring(b.mon.status), tostring(b.mon.item), stageStr(b), ppStr(b.mon))
end

local function benchStr(party)
  local out = {}
  for i, mon in ipairs(party or {}) do
    out[i] = ("%s:%d:%s:%s:%s"):format(tostring(mon.species), mon.hp or 0,
      tostring(mon.status), tostring(mon.item), ppStr(mon))
  end
  return table.concat(out, "|")
end

local function fieldStr(s)
  local out = {}
  -- the host's side first (side 1 is each machine's own)
  local sides = s.sides or {}
  local hostSide, guestSide = sides[1] or {}, sides[2] or {}
  if s.linkRole ~= "host" then hostSide, guestSide = guestSide, hostSide end
  for _, src in ipairs({ s.field or {}, hostSide, guestSide }) do
    local part = {}
    for _, k in ipairs(scalarKeys(src)) do
      if k ~= "index" and not off(src[k]) then part[#part + 1] = k .. "=" .. tostring(src[k]) end
    end
    out[#out + 1] = table.concat(part, ",")
  end
  return table.concat(out, "/")
end

-- THE CANONICAL FRAME: positions as the HOST numbers them (0 host left,
-- 1 guest left, 2 host right, 3 guest right).  The guest's own numbering is
-- the mirror (its 0 is the host's 1), so position p here is canonical p xor 1
-- there.  Everything compared or streamed is laid out in this frame.
local CANON = { 0, 1, 2, 3 }
local function localPos(s, c)
  if s.linkRole == "host" then return c end
  return (c % 2 == 0) and c + 1 or c - 1
end
M.localPos = localPos

local function canonBattlers(s)
  local out = {}
  for i, c in ipairs(CANON) do out[i] = s:battlerAt(localPos(s, c)) end
  return out
end

-- host-first component digests: `actives` and `bench` decide a match and
-- end it when they split; `volatile` and `field` are noted only (see the
-- Gen 1/2 notes in LinkBattle.lua -- a split there lands in `actives` within
-- a turn when it means anything)
local function stateSig(s)
  local hostParty = s.linkRole == "host" and s.linkMyParty or s.linkTheirParty
  local guestParty = s.linkRole == "host" and s.linkTheirParty or s.linkMyParty
  local act, vol = {}, {}
  local cb = canonBattlers(s)
  for i = 1, 4 do
    local b = cb[i]
    act[i] = activeStr(b)
    vol[i] = b and volStr(b) or "-"
  end
  for i = #act + 1, 4 do act[i], vol[i] = "-", "-" end
  local raw = {
    actives = table.concat(act, "|"),
    volatile = table.concat(vol, "|"),
    bench = benchStr(hostParty) .. "|" .. benchStr(guestParty),
    field = fieldStr(s),
  }
  if M.debugSig then M.debugSig(s, raw) end -- (a test hook: the raw strings)
  return {
    actives = Fingerprint.digest(raw.actives),
    volatile = Fingerprint.digest(raw.volatile),
    bench = Fingerprint.digest(raw.bench),
    field = Fingerprint.digest(raw.field),
  }
end
M.stateSig = stateSig

local PARTS = { "actives", "bench", "volatile", "field" }
local FATAL_PART = { actives = true, bench = true }

-- ------------------------------------------------------------ host state

local function scalarCopy(t)
  local out = {}
  for _, k in ipairs(scalarKeys(t or {})) do out[k] = t[k] end
  return out
end

local function monSnap(mon)
  local pp = {}
  for i, mv in ipairs(mon.moves or {}) do pp[i] = mv.pp or 0 end
  return { hp = mon.hp, status = mon.status, sleepTurns = mon.sleepTurns,
           item = mon.item, pp = pp }
end

local function battlerSnap(b)
  if not (b and b.mon) then return nil end
  local stages = {}
  for k, v in pairs(b.stages or {}) do
    if type(v) == "number" then stages[k] = v end
  end
  return { vars = scalarCopy(b), stages = stages }
end

-- a side's own scalars (Spikes, screens' counters ...), not its slot number
local function sideCopy(side)
  local out = scalarCopy(side)
  out.index = nil
  return out
end

-- the whole shared state in the canonical frame (taken on the host; the
-- guest takes one of its own only to see whether adopting changed anything)
local function snapshot(s)
  local hostParty = s.linkRole == "host" and s.linkMyParty or s.linkTheirParty
  local guestParty = s.linkRole == "host" and s.linkTheirParty or s.linkMyParty
  local function party(list)
    local out = {}
    for i, mon in ipairs(list) do out[i] = monSnap(mon) end
    return out
  end
  local sides = s.sides or {}
  local hostSide, guestSide = sides[1], sides[2]
  if s.linkRole ~= "host" then hostSide, guestSide = guestSide, hostSide end
  local active, battlers = {}, {}
  local cb = canonBattlers(s)
  for i = 1, 4 do
    local b = cb[i]
    local list = (i % 2 == 1) and hostParty or guestParty
    active[i] = b and indexOf(list, b.mon) or 0
    battlers[i] = battlerSnap(b) or false
  end
  return {
    parties = { party(hostParty), party(guestParty) },
    active = active, battlers = battlers,
    field = scalarCopy(s.field),
    sides = { sideCopy(hostSide), sideCopy(guestSide) },
  }
end
M.snapshot = snapshot

local function applyScalars(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return end
  for _, k in ipairs(scalarKeys(dst)) do
    if src[k] == nil then dst[k] = nil end
  end
  for k, v in pairs(src) do
    if type(k) == "string" and not presentational(k) then dst[k] = v end
  end
end

-- the guest adopts the host's state: both parties, who stands where, the
-- active battlers' stages and volatiles, the field and the sides
local function adopt(s, snap)
  local hostParty = s.linkRole == "host" and s.linkMyParty or s.linkTheirParty
  local guestParty = s.linkRole == "host" and s.linkTheirParty or s.linkMyParty
  local function party(list, rows)
    for i, row in ipairs(rows or {}) do
      local mon = list[i]
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
  party(hostParty, snap.parties and snap.parties[1])
  party(guestParty, snap.parties and snap.parties[2])
  local BattleState = require("src.battle.BattleState")
  for i, c in ipairs(CANON) do
    local pos = localPos(s, c)
    local isPlayer = (pos % 2) == 0
    local list = (i % 2 == 1) and hostParty or guestParty
    local idx = tonumber(snap.active and snap.active[i]) or 0
    local cur = s:battlerAt(pos)
    local mon = list[idx]
    if mon and not (cur and cur.mon == mon) then
      cur = BattleState.makeBattler(s.data, mon, isPlayer, nil)
      s:placeBattler(pos, cur)
      s:syncSides()
    end
    local row = snap.battlers and snap.battlers[i]
    if cur and type(row) == "table" then
      applyScalars(cur, row.vars)
      cur.stages = cur.stages or {}
      for k in pairs(cur.stages) do cur.stages[k] = 0 end
      for k, v in pairs(row.stages or {}) do cur.stages[k] = v end
      if cur.shownHP then cur.shownHP = cur.mon.hp end
    end
  end
  if type(snap.field) == "table" and s.field then applyScalars(s.field, snap.field) end
  local sides = s.sides or {}
  local hostSide, guestSide = sides[1], sides[2]
  if s.linkRole ~= "host" then hostSide, guestSide = guestSide, hostSide end
  for i, side in ipairs({ hostSide, guestSide }) do
    local row = snap.sides and snap.sides[i]
    if side and type(row) == "table" then
      local keep = side.index
      applyScalars(side, row)
      side.index = keep
    end
  end
end
M.adopt = adopt

local function snapKey(snap)
  -- a stable text of the snapshot, to tell whether adopting changes anything
  local function canon(v)
    if type(v) ~= "table" then return v end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. ":" .. tostring(type(v[k]) == "table" and canon(v[k]) or v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return canon(snap)
end

-- the guest's own state, in the same canonical frame the host's arrives in
local function guestSnapAsHost(s)
  return snapKey(snapshot(s))
end

-- the pieces the 4-player multi battle (src/online/MultiBattle.lua) shares
M.util = {
  makeRng = makeRng, alive = alive, firstHealthy = firstHealthy, indexOf = indexOf,
  buildTeam = buildTeam, scalarKeys = scalarKeys, scalarCopy = scalarCopy,
  presentational = presentational, monSnap = monSnap, battlerSnap = battlerSnap,
  sideCopy = sideCopy, applyScalars = applyScalars, snapKey = snapKey,
  activeStr = activeStr, benchStr = benchStr, displayName = displayName,
}

-- ------------------------------------------------------------ the battle

-- opts: as LinkBattle.new, plus
--   mode   "lockstep" | "host"   (LinkBattle picks it from the verdict)
--   rules  BattleRules table (else built from opts.forceLevel)
function M.new(game, net, opts)
  local BattleState = require("src.battle.BattleState")
  local GameVersion = require("src.core.GameVersion")
  local role = opts.role
  local theirName = opts.theirName or "FOE"
  local mode = opts.mode == "host" and "host" or "lockstep"
  local gen = GameVersion.generation and GameVersion.generation(GameVersion.get()) or 3
  gen = math.max(3, tonumber(gen) or 3)
  local rules = opts.rules and BattleRules.sanitize(opts.rules, gen)
                or BattleRules.fromForceLevel(opts.forceLevel, gen)
  local strict = opts.strict or false

  local okMine, whyMine = BattleRules.check(rules, BattleRules.team(rules, opts.myParty), game.data)
  if not okMine then return nil, whyMine end
  local okTheirs, whyTheirs = BattleRules.check(rules, BattleRules.team(rules, opts.theirParty), game.data)
  if not okTheirs then return nil, Strings("%s's team:\n%s", theirName, whyTheirs) end

  local myParty, myErr = buildTeam(game, opts.myParty, rules, strict, function(p)
    return Strings("Your %s can't\nbattle on the\nother game.", tostring(p.species))
  end)
  if not myParty then return nil, myErr end
  local theirParty, theirErr = buildTeam(game, opts.theirParty, rules, strict, function(p, why)
    return Strings("Their %s isn't\nin this game.\n(%s)", tostring(p.species), tostring(why))
  end)
  if not theirParty then return nil, theirErr end
  if #myParty == 0 or #theirParty == 0 then
    return nil, Strings("Link battle\ncan't start.")
  end

  -- mods see both parties in the canonical host-first order (as Gen 1/2)
  local function announceReceived(party)
    for _, mon in ipairs(party) do
      Runtime.emit("pokemon.received", { mon = mon, from = "link", peerName = theirName })
    end
  end
  announceReceived(role == "host" and myParty or theirParty)
  announceReceived(role == "host" and theirParty or myParty)

  -- THE ENGINE READS THE PLAYER'S PARTY FROM THE SAVE in a hundred places
  -- (the bench for U-turn and Baton Pass, the replacement menu, the party
  -- screen, B/W's bench).  For the battle's length the save holds the link
  -- copies; `finish` puts the real party back.  Nothing saves mid-battle.
  local realParty = game.save.party
  game.save.party = myParty

  local okNew, self = pcall(BattleState.newWild, game,
    theirParty[1].species, theirParty[1].level or 5)
  if not okNew then
    game.save.party = realParty
    error(self, 0)
  end
  self.kind = "link"
  self.link = true
  self.linkModern = true
  self.linkMode = mode
  self.linkRole = role
  self.linkRules = rules
  self.linkInvertTie = role == "guest" or nil
  self.linkMyParty, self.linkTheirParty = myParty, theirParty
  self.linkRealParty = realParty
  self.bwAutoSwitch = true
  self.net = net
  game.linkNet = net
  self.rng = makeRng(opts.seed or 1)
  self.player = BattleState.makeBattler(game.data, myParty[1], true, nil)
  self.enemy = BattleState.makeBattler(game.data, theirParty[1], false)
  self:syncSides()
  self.enemyParty = theirParty
  self.enemyIndex = 1
  self.playerParty = myParty
  self.opponentName = theirName
  -- the other player's online look (Handshake.hello `look`): their front pic
  -- in the intro (src/online/BattleLook.lua); an older peer sends none
  do
    local ph = opts and opts.peerHello
    local okP, P = pcall(require, "src.online.world.WorldProtocol")
    if okP and type(ph) == "table" and type(ph.look) == "table" then self.peerLook = P.cleanLook(ph.look) end
  end
  self.introText = Strings("%s wants\nto battle!", theirName)
  self.trainerLabel_ = function() return theirName end
  self.remoteHashes, self.localHashes = {}, {}
  self.remoteParts, self.localParts = {}, {}
  self.checkedTurns = {}
  self.hostStates = {}
  self.linkCorrections = 0
  self.linkTheirAction = nil

  -- A DOUBLE BATTLE (the rules' format), when both teams can field two;
  -- otherwise it is a single on both machines alike.  The engine's own
  -- doubles run it: the menu asks for both slots, the turn sorts four.
  local POS = BattleState.POS
  if rules.format == "double" and #myParty >= 2 and #theirParty >= 2 then
    self.double = true
    self:sendOutSecondPair()
    self.linkDouble = self:isDouble() or nil
    -- no experience in a link battle (doubles pay it per fallen slot)
    self.awardExp = function() end
    -- the menu reads its locks off the LEFT battler; while the right slot
    -- is choosing, the right battler's own lock is the one that counts
    local baseMLA, baseFLA = self.menuLockedAction, self.fightLockedAction
    self.menuLockedAction = function(s, b)
      if s.choosingSlot == POS.PLAYER_RIGHT and b == s.player then b = s:battlerAt(POS.PLAYER_RIGHT) end
      return baseMLA(s, b)
    end
    self.fightLockedAction = function(s, b)
      if s.choosingSlot == POS.PLAYER_RIGHT and b == s.player then b = s:battlerAt(POS.PLAYER_RIGHT) end
      return baseFLA(s, b)
    end
  end

  local send = function(msg) net:send(msg) end
  -- A TOURNAMENT SPECTATOR (M.newSpectator) is the host's machine without
  -- the host: it sends nothing, and the host's own choices come off the
  -- relay's copy of the host's traffic
  if opts.spectator then
    send = function() end
    self.linkSpectator = true
    self.spectating = true -- Tournament.lua's marker: no result is reported
    self.specMinePicks = {}
  end

  local function endWith(s, result, text)
    if s.linkEnded then return end
    s.result = result
    s.afterQueue = "finish"
    s.phase = "messages"
    s.linkBlocked = nil
    if text then s:say(text) end
  end

  -- the far side's choices come off the wire, never from an AI
  self.enemyAction = function(s, battler)
    local pos = battler and battler.position
    if pos and s.linkTheirActions and s.linkTheirActions[pos] ~= nil then
      return s.linkTheirActions[pos]
    end
    return s.linkTheirAction
  end

  local function decode(s, msg, battler)
    if not (msg and battler) then return nil end
    if msg.kind == "move" then
      local moves = battler.curMoves or {}
      local slot = math.max(1, math.min(#moves, math.floor(tonumber(msg.slot) or 1)))
      return moves[slot]
    elseif msg.kind == "struggle" then
      return { id = "STRUGGLE", pp = 1, struggle = true }
    elseif msg.kind == "locked" then
      return s:lockedAction(battler)
    end
    return nil
  end

  -- ---------------------------------------------------- desync / authority

  local function reportDesync(s, turn, component, a, b)
    Logger.warn("link: desync turn %s component=%s (%s vs %s)",
                tostring(turn), component, tostring(a), tostring(b))
    Runtime.emit("link.desync", { turn = turn, component = component,
                                  localHash = a, remoteHash = b, fatal = true })
    s.linkDesync = { turn = turn, component = component }
    endWith(s, "draw", Strings(
      "The link was lost:\nthe two games no\nlonger agree.\fThe battle is\ncancelled. (%s)", component))
  end

  local function checkHashes(s)
    if mode == "host" then return end -- the host's state is the truth
    for turn, mine in pairs(s.localParts) do
      local theirs = s.remoteParts[turn]
      if theirs and not s.checkedTurns[turn] then
        s.checkedTurns[turn] = true
        for _, c in ipairs(PARTS) do
          if mine[c] ~= theirs[c] then
            if FATAL_PART[c] then
              reportDesync(s, turn, c, mine[c], theirs[c])
              return
            end
            Logger.warn("link: %s drift on turn %s -- match continues", c, tostring(turn))
            Runtime.emit("link.desync", { turn = turn, component = c,
                                          localHash = mine[c], remoteHash = theirs[c],
                                          fatal = false })
          end
        end
      end
    end
  end

  -- the guest takes the host's state for `turn`; true once it has
  local function tryAdopt(s, turn)
    local snap = s.hostStates[turn]
    if not snap then return false end
    s.hostStates[turn] = nil
    local before = guestSnapAsHost(s)
    local ok, err = pcall(adopt, s, snap)
    if not ok then
      Logger.warn("link: host state for turn %s would not apply: %s", tostring(turn), tostring(err))
      return true
    end
    -- the host's word on who is down: a Pokemon this machine kept standing
    -- that the host knocked out faints now (host's first, as everywhere);
    -- one it knocked out that the host kept standing is back on its feet
    s.nextInsert = 0
    local cb = canonBattlers(s)
    for i = 1, 4 do
      local b = cb[i]
      if b and b.mon then
        if b.mon.hp <= 0 and not b.faintQueued then
          s:onFaint(b)
          -- a double refills (and checks for a beaten side) at the end of
          -- the turn, which has already run here
          if s.linkDouble and not s.linkRefillQueued then
            s.linkRefillQueued = true
            s:act(function() s.linkRefillQueued = nil s:fillEmptySlots() end)
          end
        elseif b.mon.hp > 0 and (b.fainted or b.faintQueued) then
          b.fainted, b.faintQueued = nil, nil
        end
      end
    end
    local after = guestSnapAsHost(s)
    if before ~= after then
      if M.debugCorrect then M.debugCorrect(s, turn, before, after) end
      s.linkCorrections = s.linkCorrections + 1
      Logger.info("link: host mode corrected turn %s", tostring(turn))
      Runtime.emit("link.corrected", { battle = s, turn = turn })
    end
    return true
  end

  -- the end of a turn: hash (lockstep) or stream / wait for the host state
  local function closeTurn(s)
    s:act(function()
      if s.linkEnded or s.result then return end
      local turn = s.turnCount or 0
      if rules.sleepClause then s.linkSleepScan(s) end
      if mode == "host" and role == "guest" then
        if not tryAdopt(s, turn) then s.linkBlocked = turn end
        return
      end
      local parts = stateSig(s)
      s.localParts[turn] = parts
      s.localHashes[turn] = parts.actives
      if mode == "host" then
        send({ type = "state", turn = turn, snap = snapshot(s), parts = parts })
      else
        send({ type = "hash", turn = turn, value = parts.actives, parts = parts })
        checkHashes(s)
      end
    end)
  end

  -- ---------------------------------------------------- send-outs

  -- the far side's Pokemon comes in (a replacement after a faint): the same
  -- steps as the trainer's send-out (BattleState.enemyMonFainted), without
  -- the exp or the SHIFT offer
  local function sendOutEnemy(s, mon, pos)
    pos = pos or POS.OPPONENT_LEFT
    local previous = s:battlerAt(pos)
    -- the battle copy of a MIMICked move leaves with it (switchPlayerInto
    -- does the same on the near side)
    if previous then s:restoreMimicked(previous) end
    if pos == POS.OPPONENT_LEFT then s.enemyIndex = indexOf(theirParty, mon) or s.enemyIndex end
    local incoming = BattleState.makeBattler(s.data, mon, false)
    s:placeBattler(pos, incoming)
    -- the far side's send-out ends every trap on the near side (singles:
    -- the one foe; doubles: both)
    for _, b in ipairs(s:foesOf(incoming)) do
      b.trappingTurns, b.trapMove, b.trapDamage = nil, nil, nil
    end
    if s.player and not s:isDouble() then
      s.player.trappingTurns, s.player.trapMove, s.player.trapDamage = nil, nil, nil
    end
    s:syncSides()
    Runtime.emit("battle.battler_switched", {
      battle = s, side = s.sides[2], battler = incoming, previous = previous,
    })
    s:abilitySwitchOut(previous)
    s.enemySendingOut = true
    s:sayNext(Strings("%s sent\nout %s!", theirName, incoming.name))
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

  local function sendOutPlayer(s, mon)
    s:switchPlayerInto(BattleState.POS.PLAYER_LEFT, mon)
  end

  local function sideOut(party) return firstHealthy(party) == nil end

  -- a faint: the next healthy Pokemon in party order, on both machines; a
  -- side with nobody left loses (both at once: a draw)
  -- BOTH OUT AT ONCE IS A DRAW, which is the cartridges' own rule:
  -- pokeemerald Cmd_checkteamslost ORs B_OUTCOME_LOST and B_OUTCOME_WON
  -- into B_OUTCOME_DREW (3), and pokeplatinum / pokeheartgold
  -- BattleControllerPlayer_CheckBattleOver ORs BATTLE_RESULT_WIN and _LOSE
  -- into BATTLE_RESULT_DRAW.  Black / White have no decomp here; their
  -- double KO is kept a draw (not read from code).
  local function decide(s)
    local mineOut, theirsOut = sideOut(myParty), sideOut(theirParty)
    if mineOut and theirsOut then
      endWith(s, "draw", Strings("Both sides are out\nof POKéMON!\fThe battle is\na draw!"))
    elseif mineOut then
      endWith(s, "lose", Strings("%s is out of\nPOKéMON!\f%s wins!", game.save.player.name, theirName))
    elseif theirsOut then
      endWith(s, "win", Strings("%s is out of\nPOKéMON!\f%s wins!", theirName, game.save.player.name))
    end
    return s.result ~= nil
  end

  -- (playerMonFainted / enemyMonFainted are set with the replacement
  -- rounds, below)

  -- ---------------------------------------------------- doubles

  -- a Pokemon into a slot, either side, through that side's own send-out
  local function placeAt(s, pos, mon)
    if pos % 2 == 0 then
      s:switchPlayerInto(pos, mon)
    else
      sendOutEnemy(s, mon, pos)
    end
  end

  -- a switch chosen in a double (either side's: `linkMon` marks it) is one
  -- of four actions; both machines run it through placeAt, so the near
  -- side's and the far side's switch are the same steps
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

  -- ---------------------------------------------------- replacement rounds
  --
  -- A FAINTED POKEMON'S REPLACEMENT IS CHOSEN, as on the cartridges: each
  -- player picks from their own party screen, the picks cross the wire, and
  -- only once both sides' are in does anybody come out -- the host's slots
  -- first, so both machines run the send-outs (hazards, Intimidate ...) in
  -- one order.  A round opens after the turn's state check (the hash in
  -- lockstep, the host's state in host mode), so both machines open it from
  -- the same state.  A player who does not choose within the time limit
  -- (opts.replaceTimeout seconds, 30 by default) gets the first healthy
  -- Pokemon in party order, which is what the far side then receives.
  --
  -- {type="replace", round=n, picks={[pos]=partyIndex}} carries the
  -- sender's own slots in the sender's numbering (0 left, 2 right).

  local REPLACE_TIMEOUT = tonumber(opts.replaceTimeout) or 30
  self.linkRound = 0
  self.linkRemotePicks = {}

  local function slotList(s)
    return s.linkDouble and { 0, 1, 2, 3 } or { 0, 1 }
  end

  local function onField(s)
    local taken = {}
    for _, p in ipairs(slotList(s)) do
      local b = s:battlerAt(p)
      if b and b.mon and alive(b.mon) then taken[b.mon] = true end
    end
    return taken
  end

  -- the slots that need somebody, in canonical (host-first) order, and only
  -- as many per side as that side has Pokemon left on the bench
  local function emptySlots(s)
    local taken = onField(s)
    local spare = { [0] = 0, [1] = 0 }
    for side = 0, 1 do
      local list = (side == 0) and myParty or theirParty
      for _, mon in ipairs(list) do
        if alive(mon) and not taken[mon] and not (mon.isEgg or mon.egg) then spare[side] = spare[side] + 1 end
      end
    end
    local need = {}
    for _, c in ipairs(slotList(s)) do
      local pos = localPos(s, c)
      local b = s:battlerAt(pos)
      local side = pos % 2
      if (not b or not (b.mon and alive(b.mon))) and spare[side] > 0 then
        spare[side] = spare[side] - 1
        need[#need + 1] = pos
      end
    end
    return need
  end

  local function benchOf(list, taken, chosen)
    for i, mon in ipairs(list) do
      if alive(mon) and not taken[mon] and not chosen[mon] and not (mon.isEgg or mon.egg) then return mon, i end
    end
    return nil
  end

  local function sendPicks(s, round, picks)
    local wire = {}
    for pos, idx in pairs(picks) do wire[tostring(pos)] = idx end
    send({ type = "replace", round = round, picks = wire })
  end

  -- the near side's choices for the open round: the party screen, one slot
  -- at a time; s.linkPickReplacement(mon) is the screen's answer (drivers
  -- and tests call it directly)
  local function askLocal(s, round)
    local open = s.linkRoundOpen
    local pos
    for _, p in ipairs(open.mine) do if not open.minePicks[p] then pos = p break end end
    if not pos then
      sendPicks(s, round, open.minePicks)
      open.mineSent = true
      return
    end
    local function accept(mon)
      if not (s.linkRoundOpen == open and not open.minePicks[pos]) then return false end
      local taken = onField(s)
      local chosen = {}
      for _, i in pairs(open.minePicks) do chosen[myParty[i]] = true end
      local idx = indexOf(myParty, mon)
      if not (idx and alive(mon) and not taken[mon] and not chosen[mon] and not (mon.isEgg or mon.egg)) then
        return false
      end
      open.minePicks[pos] = idx
      open.screen, open.clock = nil, nil
      askLocal(s, round)
      return true
    end
    open.asking = pos
    open.clock = REPLACE_TIMEOUT
    s.linkPickReplacement = function(mon)
      local screen = open.screen
      if accept(mon) and screen and game.stack:top() == screen then game.stack:pop() end
    end
    -- the time limit: the first healthy Pokemon in party order
    open.timeout = function()
      local taken = onField(s)
      local chosen = {}
      for _, i in pairs(open.minePicks) do chosen[myParty[i]] = true end
      local mon = benchOf(myParty, taken, chosen)
      local screen = open.screen
      if mon and accept(mon) and screen and game.stack:top() == screen then game.stack:pop() end
    end
    if s.linkSpectator then
      -- the host's picks, when they have already arrived
      open.clock = nil
      local wire = s.specMinePicks[round]
      if wire then
        s.specMinePicks[round] = nil
        for k, idx in pairs(wire) do open.minePicks[tonumber(k)] = tonumber(idx) end
        open.mineSent = true
      end
      return
    end
    if opts.autoReplace then return end
    local Gen4Battle = require("src.battle.Gen4Battle")
    local ok, screen = pcall(function()
      return s:buildScreen(Gen4Battle.partyScreenId(s) or "PartyMenu", {
        battle = s, forceSwitch = true,
        onSwitch = function(mon)
          -- the screen has closed itself; a refused pick opens it again
          if not accept(mon) and s.linkRoundOpen == open and not open.minePicks[pos] then
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
      -- the clock keeps running while the screen is up (the battle itself
      -- is not updated under it)
      local baseUpdate = screen.update
      screen.update = function(sc, dt, ...)
        if baseUpdate then baseUpdate(sc, dt, ...) end
        if open.clock and s.linkRoundOpen == open then
          open.clock = open.clock - (dt or 0)
          if open.clock <= 0 then open.clock = nil open.timeout() end
        end
      end
      open.screen = screen
      game.stack:push(screen)
    end
  end

  local function remotePicksFor(s, round)
    local open = s.linkRoundOpen
    if #open.theirs == 0 then return {} end
    local wire = s.linkRemotePicks[round]
    if not wire then return nil end
    local out = {}
    for tp, idx in pairs(wire) do
      local p = tonumber(tp)
      if p then out[(p % 2 == 0) and p + 1 or p - 1] = tonumber(idx) end
    end
    return out
  end

  -- everyone comes out, host's slots first
  local function applyRound(s, theirPicks)
    local open = s.linkRoundOpen
    s.linkRoundOpen = nil
    s.linkPickReplacement = nil
    s.nextInsert = 0
    local chosen = {}
    for _, pos in ipairs(open.need) do
      local mine = pos % 2 == 0
      local list = mine and myParty or theirParty
      local idx = mine and open.minePicks[pos] or theirPicks[pos]
      local mon = idx and list[idx]
      local taken = onField(s)
      if not (mon and alive(mon) and not taken[mon] and not chosen[mon]) then
        mon = benchOf(list, taken, chosen)
      end
      if mon then
        chosen[mon] = true
        if s.linkDouble then placeAt(s, pos, mon)
        elseif mine then sendOutPlayer(s, mon)
        else sendOutEnemy(s, mon) end
      end
    end
  end

  -- a round opens here (a queued act): the result first, then who is owed
  local function replacementRound(s)
    s.linkRoundQueued = nil
    if s.result or s.linkRoundOpen then return end
    if decide(s) then return end
    local need = emptySlots(s)
    if #need == 0 then return end
    s.linkRound = s.linkRound + 1
    local open = { round = s.linkRound, need = need, mine = {}, theirs = {}, minePicks = {} }
    for _, pos in ipairs(need) do
      if pos % 2 == 0 then open.mine[#open.mine + 1] = pos else open.theirs[#open.theirs + 1] = pos end
    end
    open.mineSent = #open.mine == 0
    s.linkRoundOpen = open
    s.phase = "messages"
    if #open.mine > 0 then askLocal(s, open.round) end
  end

  local function queueRound(s)
    if s.linkRoundQueued then return end
    s.linkRoundQueued = true
    s:act(function() replacementRound(s) end)
  end

  -- a single's faint lands here (BattleState.onFaint queues it); a double's
  -- reaches it through checkSideBeaten
  self.playerMonFainted = function(s)
    if s.result then return end
    replacementRound(s)
  end
  self.enemyMonFainted = self.playerMonFainted

  -- a double's empty slots wait for the round, after the turn's state check
  if self.linkDouble then
    self.fillEmptySlots = function(s)
      s.pendingReplacements = nil
      queueRound(s)
    end
  end

  -- the round is complete once both sides' picks are in; true while it waits
  self.linkRoundWait = function(s)
    local open = s.linkRoundOpen
    if not open then return false end
    if open.reopen then
      open.reopen = nil
      askLocal(s, open.round)
      return true
    end
    -- (a driver without a screen: the clock runs here)
    if open.clock and not open.screen and game.stack:top() == s then
      open.clock = open.clock - (s.linkDt or 0)
      if open.clock <= 0 then open.clock = nil open.timeout() end
    end
    if not open.mineSent then return true end
    local theirs = remotePicksFor(s, open.round)
    if not theirs then return true end
    applyRound(s, theirs)
    return false
  end

  -- ---------------------------------------------------- sleep clause

  local function asleepByFoe(party)
    for _, mon in ipairs(party) do
      if mon.status == "SLP" and mon.linkSleptByFoe and alive(mon) then return true end
      if mon.status ~= "SLP" then mon.linkSleptByFoe = nil end
    end
    return false
  end

  if rules.sleepClause then
    local baseExecute = self.executeAction
    self.executeAction = function(s, user, target, action)
      s.linkSleepScan(s)
      local mvId = action and not action.special and action.id
      if mvId and user and target and user.mon and alive(user.mon)
         and BattleRules.isSleepMove(s.data, mvId) then
        local foeParty = user.isPlayer and theirParty or myParty
        if asleepByFoe(foeParty) then
          if action.pp and action.pp > 0 then action.pp = action.pp - 1 end
          user.lastMove = mvId
          local def = s.data.moves[mvId]
          s:sayNext(Strings("%s used\n%s!", displayName(user), def and def.name or tostring(mvId)))
          s:sayNext(Strings("But it failed!\n(Sleep Clause)"))
          return
        end
      end
      s.linkLastActor = user
      baseExecute(s, user, target, action)
    end
  end

  -- who put whom to sleep: a move's effect can land in a queued step after
  -- executeAction returns, so new sleep is attributed at the NEXT action
  -- (and at the end of the turn) to whoever acted last.  A Pokemon asleep by
  -- its own doing (REST, Effect Spore on its own attack) is not counted.
  local sleepSeen = {}
  self.linkSleepScan = function(s)
    local actor = s.linkLastActor
    for _, list in ipairs({ myParty, theirParty }) do
      for _, mon in ipairs(list) do
        if mon.status == "SLP" and sleepSeen[mon] ~= "SLP" then
          local ownSide = list == myParty
          if actor and actor.mon ~= mon and (actor.isPlayer and true or false) ~= ownSide then
            mon.linkSleptByFoe = true
          end
        elseif mon.status ~= "SLP" then
          mon.linkSleptByFoe = nil
        end
        sleepSeen[mon] = mon.status
      end
    end
  end

  -- ---------------------------------------------------- the turn

  local function resetTurnFlags(s)
    for _, b in s:activeBattlers() do
      if b then
        b.hurtThisTurn = nil
        b.specialDamageTaken, b.physicalDamageTaken = nil, nil
        b.protecting, b.enduring = nil, nil
        b.turnsOut = (b.turnsOut or 0) + 1
      end
    end
  end

  local function isPursuit(s, action)
    if not s.bw then return false end
    local d = action and action.id and s.data.moves[action.id]
    return d and d.bwEffect == 128 or false
  end

  -- a turn in which one side or both switch: every switch before every
  -- move (the host's first when both do), then the other side's move,
  -- with B/W's Pursuit catching a Pokemon on its way out
  local function switchTurn(s, myMsg, theirMsg)
    s.turnCount = (s.turnCount or 0) + 1
    resetTurnFlags(s)
    local mySwitch = myMsg.kind == "switch" and myParty[myMsg.index] or nil
    local theirIndex = theirMsg.kind == "switch"
      and math.max(1, math.min(#theirParty, math.floor(tonumber(theirMsg.index) or 1))) or nil
    local myAction = (not mySwitch) and myMsg.action or nil
    local theirAction = (not theirIndex) and decode(s, theirMsg, s.enemy) or nil
    Runtime.emit("battle.turn_started", {
      battle = s, turn = s.turnCount, playerAction = myAction, enemyAction = theirAction,
    })
    local function doMine()
      if s.result or not mySwitch then return end
      s:switchPlayerInto(BattleState.POS.PLAYER_LEFT, mySwitch)
    end
    local function doTheirs()
      if s.result or not theirIndex then return end
      local mon = theirParty[theirIndex]
      if not alive(mon) or (s.enemy and s.enemy.mon == mon) then return end
      -- (the trainer's aiSwitch path, which leaves a MIMICked move behind)
      if s.enemy then s:restoreMimicked(s.enemy) end
      s:executeAction(s.enemy, s.player, { special = "aiSwitch", index = theirIndex })
    end
    if mySwitch and theirIndex then
      if role == "host" then s:act(doMine) s:act(doTheirs)
      else s:act(doTheirs) s:act(doMine) end
    elseif mySwitch then
      local leaving = s.player
      if isPursuit(s, theirAction) then
        s:act(function()
          leaving.switchingOut = true
          s:executeAction(s.enemy, leaving, theirAction)
          leaving.switchingOut = nil
        end)
        s:act(function() if alive(leaving.mon) then doMine() end end)
      else
        s:act(doMine)
        s:act(function() s:executeAction(s.enemy, s.player, theirAction) end)
      end
    else
      local leaving = s.enemy
      if isPursuit(s, myAction) then
        s:act(function()
          leaving.switchingOut = true
          s:executeAction(s.player, leaving, myAction)
          leaving.switchingOut = nil
        end)
        s:act(function() if alive(leaving.mon) then doTheirs() end end)
      else
        s:act(doTheirs)
        s:act(function() s:executeAction(s.player, s.enemy, myAction) end)
      end
    end
    s:act(function() s:endOfTurn() end)
  end

  local function resolve(s, myMsg, theirMsg)
    -- RUN is a forfeit: the runner loses (both at once: a draw)
    if myMsg.kind == "run" or theirMsg.kind == "run" then
      if myMsg.kind == "run" and theirMsg.kind == "run" then
        endWith(s, "draw", Strings("Both players\nforfeited.\fThe battle is\na draw!"))
      elseif myMsg.kind == "run" then
        endWith(s, "lose", Strings("%s forfeited\nthe match.", game.save.player.name))
      else
        endWith(s, "win", Strings("%s forfeited\nthe match.", theirName))
      end
      return
    end
    -- the flinch clear both menus make, at the same point on both machines
    s:clearTurnFlinches()
    if s.linkDouble and s:isDouble() then
      local L, R = POS.PLAYER_LEFT, POS.PLAYER_RIGHT
      s.pendingActions = s.pendingActions or {}
      -- my own switches become linkMon actions, the same shape as theirs
      for _, p in ipairs({ L, R }) do
        local a = s.pendingActions[p]
        if a and a.special == "playerSwitch" then
          s.pendingActions[p] = { special = "playerSwitch", linkMon = a.mon }
        end
      end
      -- theirs, from their frame (their left 0 is my 1, their right 2 my 3)
      s.linkTheirActions = {}
      s.chosenTargets = s.chosenTargets or {}
      local acts = type(theirMsg.acts) == "table" and theirMsg.acts or {}
      for _, tp in ipairs({ 0, 2 }) do
        local e = acts[tostring(tp)]
        local mp = tp + 1
        local b = s:battlerAt(mp)
        if type(e) == "table" and b then
          local act
          if e.kind == "switch" then
            local idx = math.max(1, math.min(#theirParty, math.floor(tonumber(e.index) or 1)))
            act = { special = "aiSwitch", linkMon = theirParty[idx] }
          else
            act = decode(s, e, b)
          end
          s.linkTheirActions[mp] = act
          local t = tonumber(e.target)
          if t and t >= 0 and t <= 3 then
            s.chosenTargets[mp] = s:battlerAt((t % 2 == 0) and t + 1 or t - 1)
          end
        end
      end
      BattleState.resolveTurn(s, s.pendingActions[L])
      s.linkTheirActions = nil
    elseif myMsg.kind == "switch" or theirMsg.kind == "switch" then
      s.phase = "messages"
      switchTurn(s, myMsg, theirMsg)
    else
      s.linkTheirAction = decode(s, theirMsg, s.enemy)
      BattleState.resolveTurn(s, myMsg.action)
      s.linkTheirAction = nil
    end
    s.phase = "messages"
    s.afterQueue = "linkNext"
    closeTurn(s)
  end

  self.pendingMyAction, self.remoteAction = nil, nil
  local function tryResolve(s)
    -- a spectator queues both players' choices, turn by turn, and plays one
    -- turn only once it has finished playing the turn before
    if s.linkSpectator then
      local mq, tq = s.specMineQ or {}, s.specTheirQ or {}
      if s.phase ~= "waitRemote" or #mq == 0 or #tq == 0 then return end
      if s.result or s.linkEnded then return end
      local mine = s.linkDecodeMine(s, table.remove(mq, 1))
      resolve(s, mine, table.remove(tq, 1))
      return
    end
    if not s.pendingMyAction or not s.remoteAction then return end
    if s.result or s.linkEnded then return end
    -- a spectator holds both players' next choices until it has finished
    -- playing the turn before (a player's own menu does that for it)
    local mine, theirs = s.pendingMyAction, s.remoteAction
    s.pendingMyAction, s.remoteAction = nil, nil
    resolve(s, mine, theirs)
  end

  local function submit(s, msg, localAction)
    send(msg)
    msg.action = localAction
    s.pendingMyAction = msg
    s.phase = "waitRemote"
    tryResolve(s)
  end

  -- the menu's choice (a move, Struggle, a locked move)
  local function encode(s, b, action, target)
    if not (b and action) then return nil end
    local e = {}
    if action.special == "playerSwitch" then
      e.kind, e.index = "switch", indexOf(myParty, action.mon)
    elseif action.struggle then
      e.kind = "struggle"
    elseif action.special then
      e.kind = "locked"
    else
      for i, mv in ipairs(b.curMoves or {}) do if mv == action then e.slot = i end end
      e.kind = e.slot and "move" or "locked"
    end
    if target and target.position then e.target = target.position end
    return e
  end

  -- the host's own choice, decoded on a spectator (the host's frame is the
  -- spectator's: the host is its "player")
  self.linkDecodeMine = function(s, inner)
    if inner.kind == "double" then
      s.pendingActions, s.chosenTargets = {}, {}
      local acts = type(inner.acts) == "table" and inner.acts or {}
      for _, p in ipairs({ 0, 2 }) do
        local e = acts[tostring(p)]
        local b = s:battlerAt(p)
        if type(e) == "table" and b then
          if e.kind == "switch" then
            local idx = math.max(1, math.min(#myParty, math.floor(tonumber(e.index) or 1)))
            s.pendingActions[p] = { special = "playerSwitch", mon = myParty[idx] }
          else
            s.pendingActions[p] = decode(s, e, b)
          end
          local t = tonumber(e.target)
          if t then s.chosenTargets[p] = s:battlerAt(t) end
        end
      end
      return { type = "action", kind = "double", double = true }
    end
    if inner.kind == "switch" then
      local idx = math.max(1, math.min(#myParty, math.floor(tonumber(inner.index) or 1)))
      return { type = "action", kind = "switch", index = idx }
    end
    if inner.kind == "run" then return { type = "action", kind = "run" } end
    return { type = "action", kind = inner.kind, slot = inner.slot, action = decode(s, inner, s.player) }
  end

  self.resolveTurn = function(s, action)
    if s.linkDouble and s:isDouble() then
      local L, R = POS.PLAYER_LEFT, POS.PLAYER_RIGHT
      s.pendingActions = s.pendingActions or {}
      local pos = s:choosingSlotNow()
      if action and s.pendingActions[pos] ~= action then
        -- a locked slot comes here straight from the menu: file it, and
        -- ask the other slot before anybody moves
        s.pendingActions[pos] = action
        local right = s:battlerAt(R)
        if pos ~= R and right and not right.ally and not s.pendingActions[R] then
          s.choosingSlot = R
          s.phase = "menu"
          s.moveIndex = 1
          return
        end
      end
      s.choosingSlot = nil
      local acts = {}
      for _, p in ipairs({ L, R }) do
        local b = s:battlerAt(p)
        local e = b and encode(s, b, s.pendingActions[p], s.chosenTargets and s.chosenTargets[p])
        if e then acts[tostring(p)] = e end
      end
      submit(s, { type = "action", kind = "double", acts = acts }, { double = true })
      return
    end
    if not action then return end
    local kind, slot
    if action.struggle then
      kind = "struggle"
    elseif action.special then
      kind = "locked"
    else
      for i, mv in ipairs(s.player.curMoves or {}) do
        if mv == action then slot = i end
      end
      kind = slot and "move" or "locked"
    end
    submit(s, { type = "action", kind = kind, slot = slot }, action)
  end

  -- the party screen's choice (BattleState.openParty has already refused a
  -- fainted, egg, already-out or trapped pick)
  self.resolveSwitch = function(s, newMon)
    if s.player and s.player.ingrained and alive(s.player.mon) then
      s:say(Strings("%s anchored\nitself with its\nroots!", s.player.name))
      s.phase = "messages"
      s.afterQueue = "menu"
      return
    end
    local i = indexOf(myParty, newMon)
    if i then submit(s, { type = "action", kind = "switch", index = i }, nil) end
  end

  self.openItems = function(s)
    s:say(Strings("Items can't be\nused in a link\nbattle!"))
    s.phase = "messages"
    s.afterQueue = "menu"
  end

  -- RUN asks first, as the Gen 3-5 link battles do: a forfeit loses
  self.tryRun = function(s)
    s.phase = "messages"
    s.afterQueue = "menu"
    s:sayChoice(Strings("Would you like to\nforfeit the match?"), function(yes)
      if yes then s.afterQueue = "linkForfeit" end
    end)
  end

  -- ---------------------------------------------------- the loop

  local baseUpdate = self.update
  self.update = function(s, dt)
    net:update()
    for _, msg in ipairs(net:poll()) do
      if msg.type == "action" then
        if s.linkSpectator then
          s.specTheirQ = s.specTheirQ or {}
          s.specTheirQ[#s.specTheirQ + 1] = msg
        else
          s.remoteAction = msg
        end
        tryResolve(s)
      elseif msg.type == "hash" then
        local t = tonumber(msg.turn) or 0
        s.remoteHashes[t] = msg.value
        s.remoteParts[t] = type(msg.parts) == "table" and msg.parts or { actives = msg.value }
        checkHashes(s)
      elseif msg.type == "specmine" and s.linkSpectator then
        local inner = msg.msg
        if inner.type == "action" then
          -- decoded when the turn runs, against who is standing then
          s.specMineQ = s.specMineQ or {}
          s.specMineQ[#s.specMineQ + 1] = inner
          tryResolve(s)
        elseif inner.type == "replace" then
          local r = tonumber(inner.round)
          local open = s.linkRoundOpen
          if r and type(inner.picks) == "table" then
            if open and open.round == r then
              for k, idx in pairs(inner.picks) do open.minePicks[tonumber(k)] = tonumber(idx) end
              open.mineSent = true
            else
              s.specMinePicks[r] = inner.picks
            end
          end
        elseif inner.type == "bye" or inner.type == "forfeit" then
          if not s.result then s.linkPeerGone = true end
        end
      elseif msg.type == "replace" then
        local r = tonumber(msg.round)
        if r and type(msg.picks) == "table" then s.linkRemotePicks[r] = msg.picks end
      elseif msg.type == "state" then
        if mode == "host" and role == "guest" and type(msg.snap) == "table" then
          s.hostStates[tonumber(msg.turn) or 0] = msg.snap
        end
      elseif msg.type == "bye" then
        -- the winner's machine can finish first: our own simulation of the
        -- last turn still decides, and only a match that needs the peer
        -- again ends as their leaving (below)
        s.linkPeerGone = true
      elseif msg.type == "forfeit" then
        if not s.result then
          endWith(s, "win", Strings("%s ran out of\ntime!", theirName))
        end
      else
        s.pendingTournamentMessages = s.pendingTournamentMessages or {}
        table.insert(s.pendingTournamentMessages, msg)
      end
    end
    local needsPeer = s.phase == "waitRemote" or s.phase == "menu"
                      or (s.linkBlocked and not s.hostStates[s.linkBlocked])
                      or (s.linkRoundOpen and s.linkRoundOpen.mineSent
                          and not s.linkRemotePicks[s.linkRoundOpen.round])
    if s.linkPeerGone and needsPeer and not s.result and not s.linkEnded then
      endWith(s, "draw", Strings("%s left the\nbattle.", theirName))
    elseif net.closed and needsPeer and not s.linkEnded and not s.result then
      endWith(s, "draw", Strings("The link was\nlost."))
    end
    if s.linkBlocked then
      -- the guest waits for the host's word on the turn before anything is
      -- decided from it (a faint, a send-out, the result)
      s:tickFx()
      if tryAdopt(s, s.linkBlocked) then s.linkBlocked = nil end
      return
    end
    -- a replacement round: both players' picks before anybody comes out
    s.linkDt = dt
    if not s.result and s:linkRoundWait() then
      s:tickFx()
      return
    end
    if s.phase == "waitRemote" then
      s:tickFx()
      if s.linkSpectator then tryResolve(s) end
      return
    end
    if s.phase == "messages" and s.afterQueue == "linkForfeit" then
      s:tickFx()
      if not s:updateQueue() then
        s.afterQueue = "menu"
        submit(s, { type = "action", kind = "run" }, nil)
      end
      return
    end
    if s.phase == "messages" and s.afterQueue == "linkNext" then
      s:tickFx()
      if not s:updateQueue() then
        s.afterQueue = "menu"
        s.phase = "menu"
      end
      return
    end
    -- a spectator never decides anything: between turns it waits for both
    if s.linkSpectator and (s.phase == "menu" or s.phase == "waitRemote") then
      s.phase = "waitRemote"
      s:tickFx()
      tryResolve(s)
      return
    end
    if opts.turnLimit and s.phase == "menu" then
      if not s.turnClockActive then
        s.turnClockActive = true
        s.turnClock = opts.turnLimit
      end
      s.turnClock = s.turnClock - dt
      if s.turnClock <= 0 then
        s.turnClockActive = false
        send({ type = "forfeit" })
        endWith(s, "lose", Strings("Time's up! You\nforfeit the match."))
      end
    elseif opts.turnLimit then
      s.turnClockActive = false
    end
    baseUpdate(s, dt)
  end

  local baseFinish = self.finish
  self.finish = function(s)
    if not s.linkEnded then
      s.linkEnded = true
      send({ type = "bye" })
    end
    if not (opts.keepNetOpen or opts.spectator) then net:close() end
    if game.linkNet == net then game.linkNet = nil end
    if game.save.party == myParty then game.save.party = realParty end
    baseFinish(s)
    -- a finish that pushed or saved anything still sees the real party
    if game.save.party == myParty then game.save.party = realParty end
  end

  local baseExit = self.exit
  self.exit = function(s, ...)
    if game.save.party == myParty then game.save.party = realParty end
    if baseExit then return baseExit(s, ...) end
  end

  return self
end

-- A TOURNAMENT SPECTATOR for a Gen 3+ match: the same battle the host's
-- machine runs, rebuilt from the relay's copy of both players' traffic
-- (pokeserver's `spectate` envelope: { side = "host"|"guest", msg }).  The
-- host's messages drive the near side, the guest's the far side; nothing is
-- sent, and `net` (the tournament connection) is never closed.
-- opts: { hostParty, guestParty, hostName, guestName, seed, verdict,
--         forceLevel, rules, strict }
function M.newSpectator(game, net, opts)
  local view = {}
  view.inbox = net.inbox
  function view.send() end
  function view.close() end
  function view.update() if net.update then net:update() end end
  function view.poll()
    local out = {}
    for _, msg in ipairs(net:poll()) do
      if msg.type == "spectate" and type(msg.msg) == "table" then
        if msg.side == "host" then
          out[#out + 1] = { type = "specmine", msg = msg.msg }
        else
          out[#out + 1] = msg.msg -- the guest's: the far side's traffic
        end
      else
        out[#out + 1] = msg -- bracket updates and the like, kept for Tournament
      end
    end
    return out
  end
  setmetatable(view, { __index = function(_, k)
    if k == "closed" then return net.closed end
    if k == "error" then return net.error end
    return nil
  end })
  local o = {
    role = "host", spectator = true, keepNetOpen = true,
    myParty = opts.hostParty, theirParty = opts.guestParty,
    theirName = opts.guestName or "GUEST", seed = opts.seed,
    verdict = opts.verdict, mode = opts.mode, rules = opts.rules,
    forceLevel = opts.forceLevel, strict = opts.strict,
  }
  local battle, why = M.new(game, view, o)
  if not battle then return nil, why end
  battle.introText = Strings("%s vs %s!", opts.hostName or "HOST", opts.guestName or "GUEST")
  return battle
end

return M
