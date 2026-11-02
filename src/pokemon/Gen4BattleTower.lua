-- PLATINUM'S BATTLE TOWER: the challenge itself (pokeplatinum unk_02049D08.c,
-- unk_0204AEE8.c, unk_020494DC.c, overlay104's ov104_022394A4.c and
-- frscrcmd_battle_tower.c, ov104_0223A0C4.c's party builder).
--
-- The field scripts drive everything -- the lobby's attendants, the elevator,
-- the corridor and the battle room -- through `callbattletowerfunction`, and
-- this module is the BattleTower struct those calls read and write. One is
-- made by `initbattletower` and dropped by `freebattletower`; what outlives a
-- challenge is in save.gen4Frontier:
--
--   bp          Battle Points (WifiBattleTowerRecord.battlePoints, 0..9999)
--   flags       the record's 16 bit flags -- 8 + mode is "a streak is alive"
--   rooms[m]    the room (sets of seven) a streak in mode m has reached
--   rng         the record's RNG state (sub_0206C02C advances it)
--   stats[i]    BattleFrontierSave stats: mode * 2 the best streak, + 1 the
--               current one
--   victories, challenges   the two game records the tower adds to
--   tower       WifiBattleTowerSave: the challenge in progress after "Rest"
--               { inProgress, mode, next, slots, trainers, seed }
--
-- Wi-Fi, link and the partners' multi battles are not here; single and
-- double are.

local BT = {}

BT.SINGLE, BT.DOUBLE, BT.MULTI, BT.LINK_MULTI, BT.WIFI, BT.MODE_5, BT.MODE_6 = 0, 1, 2, 3, 4, 5, 6
BT.OPPONENTS = 7
BT.PALMER_SILVER, BT.PALMER_GOLD = 305, 306
BT.BATTLE_ROOM_TEXT = 305
-- the frontier trainers' names and lines (BattleTower_GetTrainerMessagesBankID):
-- Platinum's banks 21 / 614, HeartGold / SoulSilver's 27 / 724 -- read by
-- family, since one process can boot both
BT.BANKS = { platinum = { TRAINER_NAMES = 21, TRAINER_MESSAGES = 614 },
             hgss = { TRAINER_NAMES = 27, TRAINER_MESSAGES = 724 } }
setmetatable(BT, { __index = function(_, k)
  local okB, Bands = pcall(require, "src.import.Gen4ScriptBands")
  local banks = BT.BANKS[(okB and Bands.family == "hgss") and "hgss" or "platinum"]
  return banks[k]
end })

-- enum BattleTowerFunction
BT.FN = {
  CHECK_ENOUGH_VALID_POKEMON = 1, RESET_SYSTEM = 2, UNK_03 = 3, UNK_04 = 4,
  SET_COMMUNICATION_CLUB_ACCESSIBLE = 5, CLEAR_COMMUNICATION_CLUB_ACCESSIBLE = 6,
  UNK_08 = 8, UNK_09 = 9, UNK_10 = 10, UNK_11 = 11, UNK_12 = 12, UNK_14 = 14, UNK_15 = 15, UNK_16 = 16,
  UNK_30 = 30, UNK_31 = 31, CHECK_DUPLICATE_SPECIES_AND_HELD_ITEMS = 32, GET_NEXT_OPPONENT_NUM = 33,
  UNK_34 = 34, HAS_DEFEATED_SEVEN_TRAINERS = 35, UNK_36 = 36, UPDATE_GAME_RECORDS = 37,
  UPDATE_GAME_RECORDS_AND_JOURNAL = 38, UNK_39 = 39, SET_OPPONENT_TEAMS = 40, GET_OPPONENT_OBJECT_ID = 41,
  UNK_42 = 42, GET_CHALLENGE_MODE = 43, SET_BEAT_PALMER = 44, GET_BEAT_PALMER = 45, UNK_46 = 46,
  UNK_47 = 47, UNK_48 = 48, UNK_49 = 49, SET_PARTNER_ID = 50, GET_PARTNER_ID = 51, UNK_52 = 52,
  GET_SLOT_INDEX = 53, UNK_54 = 54, GET_PARTNER_PARAM = 55, UNK_56 = 56, UNK_57 = 57, UNK_58 = 58,
  UNK_59 = 59, CHECK_IS_NULL = 100,
}

-- Pokemon_IsOnBattleFrontierBanlist
BT.BANLIST = { [150] = true, [151] = true, [249] = true, [250] = true, [251] = true, [382] = true,
  [383] = true, [384] = true, [385] = true, [386] = true, [483] = true, [484] = true, [487] = true,
  [489] = true, [490] = true, [491] = true, [492] = true, [493] = true }

-- sBattleTowerTrainerRangesPerRoom / sBattleTowerBossTrainerRangesPerRoom
-- (generated/frontier_trainers.txt, from 0)
BT.RANGES = { { 0, 99 }, { 80, 119 }, { 100, 139 }, { 120, 159 }, { 140, 179 }, { 160, 199 },
              { 180, 219 }, { 200, 299 } }
BT.BOSS_RANGES = { { 100, 119 }, { 120, 139 }, { 140, 159 }, { 160, 179 }, { 180, 199 },
                   { 200, 219 }, { 220, 239 }, { 200, 299 } }

-- sTrainerClassToObjectID, numbered (generated/trainer_classes.txt ->
-- generated/object_events_gfx.txt); anything else is OBJ_EVENT_GFX_SCHOOL_KID_M
BT.CLASS_GFX = { [90] = 141, [91] = 142, [92] = 143, [93] = 144, [94] = 145, [2] = 4, [3] = 6,
  [60] = 3, [61] = 8, [32] = 62, [33] = 63, [4] = 52, [5] = 53, [44] = 1, [45] = 2, [20] = 15,
  [21] = 16, [81] = 59, [26] = 60, [16] = 9, [17] = 12, [83] = 23, [84] = 22, [71] = 41, [18] = 42,
  [12] = 38, [13] = 39, [14] = 51, [10] = 7, [27] = 17, [35] = 37, [49] = 70, [50] = 70, [39] = 11,
  [40] = 14, [24] = 11, [25] = 14, [53] = 68, [54] = 69, [29] = 11, [6] = 5, [28] = 1, [19] = 45,
  [11] = 54, [46] = 56, [9] = 20, [48] = 50, [52] = 10, [37] = 19, [57] = 31, [41] = 29, [34] = 36,
  [59] = 40, [58] = 43, [38] = 34, [51] = 62, [30] = 14, [80] = 55, [36] = 13, [7] = 12, [85] = 35,
  [15] = 44, [22] = 71 }
BT.GFX_SCHOOL_KID_M, BT.GFX_PLAYER_M, BT.GFX_PLAYER_F = 3, 0, 97

-- Unk_020EBD50: what a team that could not avoid a repeated item holds instead
BT.RESERVED_ITEMS = { 213, 157, 234, 217 }   -- BrightPowder, Lum Berry, Leftovers, Quick Claw

-- ------------------------------------------------------------ 32-bit maths --

local TWO32 = 4294967296
local function mul32(a, b)
  local al, ah = a % 65536, math.floor(a / 65536)
  return (al * b + (ah * b % 65536) * 65536) % TWO32
end
BT.mul32 = mul32
-- Pokemon_IsPersonalityShiny: the four halves xored together under 8
local function xor16(a, b)
  local r, bitv = 0, 1
  for _ = 1, 16 do
    if (a % 2) ~= (b % 2) then r = r + bitv end
    a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
  end
  return r
end
function BT.shiny(otId, pid)
  local v = xor16(xor16(math.floor(otId / 65536), otId % 65536), xor16(math.floor(pid / 65536), pid % 65536))
  return v < 8
end
function BT.next(x) return (mul32(x, 48828125) + 1) % TWO32 end      -- sub_0206BFF0
function BT.next2(x) return (mul32(x, 1566083941) + 1) % TWO32 end   -- sub_0206BFFC

-- ---------------------------------------------------------------- the save --

function BT.record(save)
  if type(save) ~= "table" then return nil end
  local r = save.gen4Frontier
  if not r then
    r = { bp = 0, flags = 0, rooms = {}, stats = {}, victories = 0, challenges = 0,
          rng = math.random(0, 65535) * 65536 + math.random(0, 65535), tower = {} }
    save.gen4Frontier = r
  end
  r.rooms, r.stats, r.tower = r.rooms or {}, r.stats or {}, r.tower or {}
  return r
end

-- WifiBattleTowerRecord_UpdateBitFlag: op 0 read, 1 set, 2 clear
function BT.flag(r, bit, op)
  local mask = 2 ^ bit
  local on = math.floor((r.flags or 0) / mask) % 2 == 1
  if op == 1 and not on then r.flags = (r.flags or 0) + mask
  elseif op == 2 and on then r.flags = (r.flags or 0) - mask end
  return op == 0 and on
end

-- WifiBattleTowerRecord_UpdateRoomNum: op 0 read, 2 reset, 3 add one
function BT.room(r, mode, op)
  if mode == BT.MODE_5 then return 0 end
  local k = (mode == BT.MODE_6) and 5 or mode
  if op == 2 then r.rooms[k] = 0
  elseif op == 3 and (r.rooms[k] or 0) < 65534 then r.rooms[k] = (r.rooms[k] or 0) + 1 end
  return r.rooms[k] or 0
end

function BT.stat(r, i) return r.stats[i] or 0 end
function BT.setStat(r, i, v) v = math.min(9999, v); r.stats[i] = v; return v end
function BT.setIfBetter(r, i, v) if v > (r.stats[i] or 0) then r.stats[i] = math.min(9999, v) end return r.stats[i] or 0 end

-- WifiBattleTowerRecord_UpdateBattlePoints
function BT.addBP(save, n)
  local r = BT.record(save)
  n = tonumber(n) or 0
  r.bp = math.max(0, math.min(9999, (r.bp or 0) + n))
  -- RECORD_BATTLE_POINTS_RECEIVED / _SPENT: every route that gives or takes
  -- BP on the cartridge adds to one of the two
  local R = require("src.pokemon.Gen4GameRecords")
  if n > 0 then R.add(save, R.ID.BATTLE_POINTS_RECEIVED, n)
  elseif n < 0 then R.add(save, R.ID.BATTLE_POINTS_SPENT, -n) end
  return r.bp
end
function BT.bp(save) return BT.record(save).bp or 0 end

-- ------------------------------------------------------------ the struct --

function BT.partySize(mode)
  if mode == BT.SINGLE or mode == BT.WIFI or mode == BT.MODE_5 then return 3 end
  if mode == BT.DOUBLE then return 4 end
  return 2
end

-- BattleTower_Init: resume = 1 picks the saved challenge back up
function BT.init(save, resume, mode)
  local r = BT.record(save)
  local bt = { save = save, rec = r, slots = {}, trainers = {}, opponents = {}, seed = 0,
               defeated = 0, streakBase = 0, beatPalmer = 0, partnerID = 0, roomNum = 0 }
  local ts = r.tower
  ts.inProgress = false
  if (tonumber(resume) or 0) == 0 then
    bt.mode = tonumber(mode) or 0
    bt.next = 1
    r.tower = { mode = bt.mode }
    ts = r.tower
  else
    bt.mode = tonumber(ts.mode) or 0
    bt.next = tonumber(ts.next) or 1
    bt.defeated = bt.next - 1
    for k, v in pairs(ts.slots or {}) do bt.slots[k] = v end
    for k, v in pairs(ts.trainers or {}) do bt.trainers[k] = v end
    bt.seed = tonumber(ts.seed) or 0
    -- sub_0204B404: the partner's team as it was drawn
    bt.partnerID = tonumber(ts.partnerID) or 0
    if type(ts.partner) == "table" then
      bt.partners = { [bt.partnerID] = BT.copyTable(ts.partner) }
    end
  end
  bt.size = BT.partySize(bt.mode)
  local p = save.player or {}
  bt.female = (p.gender == 1 or p.gender == "female" or p.gender == "girl")
  if bt.mode ~= BT.MODE_5 and BT.flag(r, 8 + bt.mode, 0) then
    bt.streakBase = BT.stat(r, 1 + bt.mode * 2)
    bt.roomNum = BT.room(r, bt.mode, 0)
  end
  return bt
end

function BT.copyTable(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = BT.copyTable(v) end
  return c
end

-- BattleTower_GetRandom: the struct's own LCG, then `/ 65535` cut to u16
function BT.random(bt)
  bt.seed = BT.next(bt.seed)
  return math.floor(bt.seed / 65535) % 65536
end

-- BattleTower_GetTrainerIDForRoomAndOpponentNum
function BT.trainerFor(bt, room, n)
  if bt.mode == BT.SINGLE then
    if room == 2 and n == BT.OPPONENTS - 1 then return BT.PALMER_SILVER end
    if room == 6 and n == BT.OPPONENTS - 1 then return BT.PALMER_GOLD end
  end
  local range
  if room < 7 then
    range = (n == BT.OPPONENTS - 1) and BT.BOSS_RANGES[room + 1] or BT.RANGES[room + 1]
  else
    range = BT.RANGES[8]
  end
  return range[1] + BT.random(bt) % (range[2] - range[1] + 1)
end

function BT.isMulti(mode)
  return mode == BT.MULTI or mode == BT.LINK_MULTI or mode == BT.MODE_6
end

-- sub_0204A4C8: the seven, none twice -- or in the multi modes fourteen,
-- a pair for each opponent number (trainerIDs[n] is opponent n / 2)
function BT.chooseTrainers(bt)
  local multi = BT.isMulti(bt.mode)
  local count = multi and BT.OPPONENTS * 2 or BT.OPPONENTS
  for n = 0, count - 1 do
    local id
    repeat
      id = BT.trainerFor(bt, bt.roomNum, multi and math.floor(n / 2) or n)
      local used = false
      for k = 0, n - 1 do if bt.trainers[k] == id then used = true end end
    until not used
    bt.trainers[n] = id
  end
end

-- sub_0204ABF4: seed the struct from the record -- a fresh draw for a new
-- streak, or the streak's own sequence run on 24 a room
function BT.seedFromRecord(bt)
  local r = bt.rec
  if not BT.flag(r, 8 + bt.mode, 0) then
    r.rng = BT.next2(r.rng or 0)
    bt.seed = BT.next(r.rng)
  else
    local v = BT.next(r.rng or 0)
    for _ = 1, BT.room(r, bt.mode, 0) * 24 do v = BT.next(v) end
    bt.seed = v
  end
  r.tower.seed = bt.seed
  return math.floor(bt.seed / 65535) % 65536
end

-- BattleTower_GetIVsFromTrainerID
function BT.ivsFor(id)
  if id < 100 then return 3 elseif id < 120 then return 6 elseif id < 140 then return 9
  elseif id < 160 then return 12 elseif id < 180 then return 15 elseif id < 200 then return 18
  elseif id < 220 then return 21 end
  return 31
end

-- sub_02049EC4: can `need` different-species, different-item members be
-- found in the party at all
function BT.enoughValid(save, need)
  local seen = {}
  for _, mon in ipairs(save.party or {}) do
    local egg = require("src.pokemon.Party").isEgg(mon)
    local sp, item = tonumber(mon.species) or 0, tonumber(mon.item) or 0
    if not egg and not BT.BANLIST[sp] then
      local dup = false
      for _, e in ipairs(seen) do if e.species == sp and e.item == item then dup = true end end
      if not dup then seen[#seen + 1] = { species = sp, item = item } end
    end
  end
  if #seen < need then return false end
  -- sub_02049DB4: some `need` of them with no species or item repeated
  local function ok(pick)
    for a = 1, #pick do
      for b = a + 1, #pick do
        if pick[a].species == pick[b].species then return false end
        if pick[a].item ~= 0 and pick[a].item == pick[b].item then return false end
      end
    end
    return true
  end
  local function search(start, pick)
    if #pick == need then return ok(pick) end
    for i = start, #seen do
      pick[#pick + 1] = seen[i]
      if search(i + 1, pick) then return true end
      pick[#pick] = nil
    end
    return false
  end
  return search(1, {})
end

-- BattleTower_CheckDuplicateSpeciesAndHeldItems: 1 species, 2 items
function BT.checkDuplicates(bt)
  local party = bt.save.party or {}
  local sp, it = {}, {}
  for i = 1, bt.size do
    local mon = party[(bt.slots[i - 1] or 0) + 1] or {}
    sp[i], it[i] = tonumber(mon.species) or 0, tonumber(mon.item) or 0
    for j = 1, i - 1 do
      if sp[i] == sp[j] then return 1 end
      if it[i] ~= 0 and it[i] == it[j] then return 2 end
    end
  end
  return 0
end

-- ------------------------------------------------------ the opponent's team --

-- BattleTower_CreateRandomTrainerParty / sub_0204B470 / sub_0204B1E8, into
-- plain records: { species, form, item, moves, ivs, evs = {6}, nature,
-- personality, ability slot, friendship }.  `avoidSpecies` / `avoidItems`
-- are the cartridge's species and items arguments: the first opponent's
-- for a multi room's second, the player's chosen pair for a partner -- a
-- species there is never taken, an item only while fewer than 50 draws have
-- been thrown out over items.
function BT.createParty(bt, data, trainerId, size, avoidSpecies, avoidItems)
  local rec = data and data.gen4_battle_tower
  local tr = rec and rec.trainers and rec.trainers[trainerId]
  if not (tr and tr.sets and #tr.sets > 0) then return nil end
  local picked, fails = {}, 0
  local guard = 0
  while #picked < size and guard < 10000 do
    guard = guard + 1
    local setID = tr.sets[BT.random(bt) % #tr.sets + 1]
    local cur = rec.sets[setID]
    local bad = false
    for _, id in ipairs(picked) do if rec.sets[id].species == cur.species then bad = true end end
    for _, sp in ipairs(avoidSpecies or {}) do if sp == cur.species then bad = true end end
    if not bad and fails < 50 then
      for _, id in ipairs(picked) do
        local it = rec.sets[id].item
        if it ~= 0 and it == cur.item then bad = true end
      end
      for _, it in ipairs(avoidItems or {}) do
        if it ~= 0 and it == cur.item then bad = true end
      end
      if bad then fails = fails + 1 end
    end
    if not bad then picked[#picked + 1] = setID end
  end
  local reserved = fails >= 50
  local ivs = BT.ivsFor(trainerId)
  local otId = BT.random(bt) + BT.random(bt) * 65536
  local out = {}
  for i, setID in ipairs(picked) do
    out[i] = BT.monFromSet(rec.sets[setID], setID, ivs, otId, function() return BT.random(bt) end)
    if reserved then out[i].item = BT.RESERVED_ITEMS[i] end
  end
  return out
end

-- FrontierPokemon_Init: a set as a party entry -- a personality of the set's
-- nature (never shiny for this OT), its EVs split over the flagged stats,
-- friendship 0 if it knows Frustration. `rand16` is the facility's 16-bit roll.
function BT.monFromSet(s, setID, ivs, otId, rand16)
  local pid
  repeat
    pid = rand16() + rand16() * 65536
  until pid % 25 == s.nature and not BT.shiny(otId, pid)
  local evCount = 0
  for k = 0, 5 do if math.floor(s.evFlags / 2 ^ k) % 2 == 1 then evCount = evCount + 1 end end
  local ev = (evCount > 0) and math.min(255, math.floor(510 / evCount)) or 0
  local evs = {}
  for k = 0, 5 do evs[k + 1] = (math.floor(s.evFlags / 2 ^ k) % 2 == 1) and ev or 0 end
  local friendship = 255
  for _, m in ipairs(s.moves) do if m == 218 then friendship = 0 end end   -- Frustration
  return {
    setID = setID, species = s.species, form = s.form, item = s.item,
    moves = { s.moves[1], s.moves[2], s.moves[3], s.moves[4] },
    ivs = ivs, evs = evs, nature = s.nature, personality = pid, otId = otId,
    abilityBit = pid % 2, friendship = friendship,
  }
end

local function opponentFor(bt, data, id, avoidSpecies, avoidItems)
  local rec = data and data.gen4_battle_tower
  local tr = rec and rec.trainers and rec.trainers[id]
  return { id = id, class = tr and tr.class or 0,
           party = BT.createParty(bt, data, id, bt.size, avoidSpecies, avoidItems) or {} }
end

-- BattleTower_CreateOpponentParties: the next opponent's trainer and team;
-- in the multi modes the next PAIR, the second kept clear of the first's
-- species and items
function BT.setOpponent(bt, data)
  bt.opponents = {}
  if BT.isMulti(bt.mode) then
    local a, b = bt.trainers[(bt.next - 1) * 2], bt.trainers[(bt.next - 1) * 2 + 1]
    if not (a and b) then bt.opponent = nil return nil end
    bt.opponents[0] = opponentFor(bt, data, a)
    local sp, it = {}, {}
    for i, p in ipairs(bt.opponents[0].party) do sp[i], it[i] = p.species, p.item end
    bt.opponents[1] = opponentFor(bt, data, b, sp, it)
  else
    local id = bt.trainers[bt.next - 1]
    if not id then bt.opponent = nil return nil end
    bt.opponents[0] = opponentFor(bt, data, id)
  end
  bt.opponent = bt.opponents[0]
  return bt.opponent
end

function BT.opponentGfx(bt, n)
  local o = (bt.opponents and bt.opponents[tonumber(n) or 0]) or bt.opponent
  return (o and BT.CLASS_GFX[o.class]) or BT.GFX_SCHOOL_KID_M
end

-- --------------------------------------------------------- the partners --

-- the Battle Salon's five: FRONTIER_TRAINER_TRAINER_CHERYL_CHERYL + partner
-- id, in BT_PARTNER_* order -- Cheryl, Mira, Riley, Marley, Buck
BT.PARTNER_FIRST, BT.PARTNERS = 300, 5

-- sub_0204A97C (BT_FUNC_UNK_56, on entering the Salon): a team for each,
-- clear of the species and items the player chose (sub_0204A378 keeps them)
function BT.partnerTeams(bt, data)
  bt.partners = {}
  for i = 0, BT.PARTNERS - 1 do
    local id = BT.PARTNER_FIRST + i
    bt.partners[i] = opponentFor(bt, data, id, bt.chosenSpecies, bt.chosenItems)
  end
  return bt.partners
end

function BT.partner(bt)
  return bt.partners and bt.partners[bt.partnerID or 0]
end

-- BattleTower_GetPartnerParam: 0 the player's sprite, 1 the partner's, 2 who
BT.PARAM_PLAYER_GFX, BT.PARAM_PARTNER_GFX, BT.PARAM_PARTNER_ID = 0, 1, 2
function BT.partnerParam(bt, param)
  param = tonumber(param) or 0
  if param == BT.PARAM_PARTNER_ID then return bt.partnerID or 0 end
  if param == BT.PARAM_PARTNER_GFX then
    if bt.mode == BT.MULTI then
      local class = BT.PARTNER_CLASSES[bt.partnerID or 0]
      return BT.CLASS_GFX[class] or BT.GFX_SCHOOL_KID_M
    end
    return bt.partnerFemale and BT.GFX_PLAYER_F or BT.GFX_PLAYER_M
  end
  return bt.female and BT.GFX_PLAYER_F or BT.GFX_PLAYER_M
end
-- pl_btdtr 300..304's trainer classes, in partner order
BT.PARTNER_CLASSES = { [0] = 90, 94, 91, 92, 93 }

-- ---------------------------------------------------------- the records --

-- ov104_022395B4 (BT_FUNC_UNK_34): one more beaten, the next number
function BT.advance(bt)
  bt.defeated = bt.defeated + 1
  if bt.mode ~= BT.MODE_6 then bt.seed = BT.next(bt.seed) end
  bt.next = bt.next + 1
  return bt.next
end

function BT.streak(bt) return math.min(65535, bt.streakBase + bt.defeated) end

function BT.hasDefeatedSeven(bt)
  if bt.defeatedSeven then return true end
  if bt.next > 7 then bt.defeatedSeven = true return true end
  return false
end

-- BattleTower_UpdateGameRecords: the streak ends here
function BT.endStreak(bt)
  local r = bt.rec
  if bt.mode == BT.MODE_5 then return end
  local i = bt.mode * 2
  local before = r.stats[i] or 0
  local best = BT.setIfBetter(r, i, BT.streak(bt))
  -- ...and sub_0204A5A0: a single / double best of 2 or more, new or a
  -- multiple of 7 met again, is a TV record (src/script/PtTvRecords.lua)
  if best > 1 and (before < best or (before == best and best % 7 == 0))
     and (bt.mode == BT.SINGLE or bt.mode == BT.DOUBLE) then
    pcall(function()
      require("src.script.PtTvRecords").towerRecord(bt.save, best,
        (bt.save.party or {})[(bt.slots[0] or 0) + 1], bt.mode == BT.SINGLE)
    end)
  end
  BT.setStat(r, i + 1, BT.streak(bt))
  -- sub_0204A5EC: the Battle Tower Corner's pending outcome, lost at streak + 1
  pcall(function() require("src.script.PtTvRecords").towerOutcome(bt.save, false, BT.streak(bt) + 1, bt.mode) end)
  BT.flag(r, 8 + bt.mode, 2)
  r.victories = (r.victories or 0) + bt.defeated
  BT.room(r, bt.mode, 2)
  r.challenges = (r.challenges or 0) + 1
  local R = require("src.pokemon.Gen4GameRecords")
  R.add(bt.save, R.ID.BATTLE_TOWER_VICTORIES, bt.defeated)
  R.add(bt.save, R.ID.BATTLE_TOWER_CHALLENGES, 1)
  if bt.mode ~= BT.SINGLE and BT.streak(bt) >= 50 then bt.ribbonEarned = true end
end

-- BattleTower_UpdateGameRecordsAndJournal: seven won, the streak goes on
function BT.winRound(bt)
  local r = bt.rec
  if bt.mode == BT.MODE_5 then return end
  local i = bt.mode * 2
  local cur = BT.setStat(r, i + 1, BT.streak(bt))
  -- sub_0204A5EC: the Battle Tower Corner's pending outcome, a round won
  pcall(function() require("src.script.PtTvRecords").towerOutcome(bt.save, true, cur, bt.mode) end)
  BT.flag(r, 8 + bt.mode, 1)
  BT.setIfBetter(r, i, cur)
  r.victories = (r.victories or 0) + 7
  BT.room(r, bt.mode, 3)
  r.challenges = (r.challenges or 0) + 1
  local R = require("src.pokemon.Gen4GameRecords")
  R.add(bt.save, R.ID.BATTLE_TOWER_VICTORIES, 7)
  R.add(bt.save, R.ID.BATTLE_TOWER_CHALLENGES, 1)
  if bt.mode ~= BT.SINGLE and BT.streak(bt) >= 50 then bt.ribbonEarned = true end
end

-- BattleTower_GiveBattlePointsReward
BT.SOLO_BP = { [0] = 0, 3, 3, 4, 4, 5, 5, 7 }
function BT.reward(bt)
  if bt.mode == BT.MODE_5 then return 0 end
  local room = BT.room(bt.rec, bt.mode, 0)
  local bp
  if bt.beatPalmer ~= 0 then bp = 20
  elseif room >= 7 then bp = 7
  else bp = BT.SOLO_BP[room] or 0 end
  BT.addBP(bt.save, bp)
  return bp
end

-- sub_0204A8C8 (BT_FUNC_UNK_39): "Rest" -- the challenge as it stands
function BT.suspend(bt)
  local ts = bt.rec.tower
  ts.mode, ts.next, ts.seed = bt.mode, bt.next, bt.seed
  ts.slots, ts.trainers = {}, {}
  for k, v in pairs(bt.slots) do ts.slots[k] = v end
  for k, v in pairs(bt.trainers) do ts.trainers[k] = v end
  -- WifiBattleTowerSave fields 6/7/9: the partner, and their two sets as drawn
  ts.partnerID = bt.partnerID
  local partner = BT.partner(bt)
  ts.partner = partner and BT.copyTable(partner) or nil
  ts.inProgress = true
end

-- sub_0204A064 (BT_FUNC_UNK_14): quit without saving -- the streak is lost
function BT.forfeitUnsaved(save)
  local r = BT.record(save)
  local mode = tonumber(r.tower.mode) or 0
  if mode == BT.MODE_5 then return mode end
  BT.flag(r, 8 + mode, 2)
  BT.room(r, mode, 2)
  BT.setStat(r, 1 + mode * 2, 0)
  if mode ~= BT.WIFI and mode ~= BT.MODE_6 then r.rng = BT.next2(r.rng or 0) end
  return mode
end

-- sub_02049FF8 (BT_FUNC_UNK_08): the current streak a lobby sign shows
function BT.currentStreak(save, mode)
  if mode == BT.MODE_5 then return 0 end
  return BT.stat(BT.record(save), 1 + mode * 2)
end

-- sub_0204AB68 / sub_0204ABA0: the ribbons; true if any was new
-- the ribbon ids of src/ui/Gen4RibbonData.lua: 53 Ability, 54 Great Ability,
-- 55 Double, 56 Multi, 57 Pair, 58 World
BT.RIBBONS = { [1] = 53, [2] = 54 }
function BT.ribbonFor(bt)
  if bt.mode == BT.SINGLE then return BT.RIBBONS[bt.beatPalmer] end
  if not bt.ribbonEarned then return nil end
  return ({ [BT.DOUBLE] = 55, [BT.MULTI] = 56, [BT.LINK_MULTI] = 57, [BT.WIFI] = 58 })[bt.mode]
end
function BT.giveRibbon(bt, key)
  if not key then return 0 end
  local party, any = bt.save.party or {}, false
  for i = 0, bt.size - 1 do
    local mon = party[(bt.slots[i] or 0) + 1]
    if mon then
      mon.ribbons = mon.ribbons or {}
      if not mon.ribbons[key] then
        mon.ribbons[key] = true; any = true
        pcall(function() require("src.script.PtTvRecords").ribbonGiven(bt.save, mon, key) end)
      end
    end
  end
  return any and 1 or 0
end

return BT
