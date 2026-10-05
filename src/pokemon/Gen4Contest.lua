-- PLATINUM'S SUPER CONTEST, the model (pokeplatinum src/contest.c,
-- src/unk_02094EDC.c, overlay017's visual and final scoring).
--
-- A contest is four contestants -- the player (contestant id 0) and three
-- NPCs from contest_data (Gen4ContestData) -- three judges, a visual theme,
-- and per-round raw scores:
--
--   visualStat   ov17_0223F374: the type's stat + (its two neighbours +
--                sheen) / 2, then x1.10 / x1.05 for the matching Scarves
--   visualDress  ov17_02252A70: each worn accessory's worth in the theme's
--                table (contest_data member 3 + theme)
--   dance        the Dance competition's score   (unk_118[].unk_04)
--   acting       the Acting competition's score  (unk_118[].unk_06)
--
-- VISUAL POINTS are sub_02095928 + sub_0209598C: the stat score against the
-- rank's eight thresholds (stars) plus the dress-up score against three
-- (hearts). FINAL SCORING (ov17_02251930 / ov17_02250744): each round is
-- scaled so its best contestant gets the round's weight -- 33.33% each for an
-- official contest, all of it for a single-round one -- turned into bar
-- lengths of (192 x weight + 5000) / 10000 pixels, and summed; placement is
-- the total, ties broken by a random draw.
--
-- ENTRY NUMBERS run the other way from contestant ids (3 - id); the script
-- talks in entry numbers.

local Contest = {}

Contest.COOL, Contest.BEAUTY, Contest.CUTE, Contest.SMART, Contest.TOUGH = 0, 1, 2, 3, 4
Contest.NORMAL, Contest.GREAT, Contest.ULTRA, Contest.MASTER, Contest.LINK = 0, 1, 2, 3, 4
-- competition types (constants/contests.h)
Contest.ACTING_ONLY_UNK0, Contest.DANCE_ONLY_UNK1, Contest.OFFICIAL = 0, 1, 2
Contest.PRACTICE_VISUAL, Contest.VISUAL, Contest.PRACTICE_DANCE = 3, 4, 5
Contest.DANCE, Contest.PRACTICE_ACTING, Contest.ACTING = 6, 7, 8
Contest.MODE_OFFICIAL, Contest.MODE_LINK, Contest.MODE_PRACTICE = 0, 1, 2

Contest.TEXT_BANK = 204
Contest.OPPONENT_NAMES = 205
Contest.JUDGE_NAMES = 207

-- the stat a type is judged on, and its two neighbours (ov17_0223F374)
local STATS = {
  [0] = { "cool", "tough", "beauty" }, [1] = { "beauty", "cool", "cute" },
  [2] = { "cute", "beauty", "smart" }, [3] = { "smart", "cute", "tough" },
  [4] = { "tough", "smart", "cool" },
}
-- the Scarves: item ids 260..264 are Red, Blue, Pink, Green, Yellow
local RED, BLUE, PINK, GREEN, YELLOW = 260, 261, 262, 263, 264
local SCARVES = {
  [0] = { [RED] = 110, [BLUE] = 105, [YELLOW] = 105 },
  [1] = { [BLUE] = 110, [RED] = 105, [PINK] = 105 },
  [2] = { [PINK] = 110, [BLUE] = 105, [GREEN] = 105 },
  [3] = { [GREEN] = 110, [PINK] = 105, [YELLOW] = 105 },
  [4] = { [YELLOW] = 110, [GREEN] = 105, [RED] = 105 },
}
Contest.SCARVES = SCARVES

-- sub_02095928 / sub_0209598C
local STAR_THRESHOLDS = {
  [0] = { 10, 20, 30, 40, 50, 60, 70, 80 }, [1] = { 90, 110, 130, 150, 170, 190, 210, 230 },
  [2] = { 170, 200, 230, 260, 290, 320, 350, 380 }, [3] = { 320, 360, 400, 440, 480, 520, 560, 600 },
  [4] = { 100, 200, 300, 400, 450, 500, 550, 600 },
}
local HEART_THRESHOLDS = {
  [0] = { 3, 5, 8 }, [1] = { 5, 10, 15 }, [2] = { 7, 15, 23 }, [3] = { 10, 20, 30 }, [4] = { 10, 20, 30 },
}

-- ------------------------------------------------------------------ rng --
-- LCRNG_Next: seed = seed * 0x41C64E6D + 0x6073, the high half returned.
local function mul32(a, b)
  local alo, ahi = a % 65536, math.floor(a / 65536)
  local lo = alo * b
  local hi = (ahi * (b % 65536)) % 65536 * 65536
  return (lo + hi) % 4294967296
end

function Contest.rng(seed)
  local r = { seed = (tonumber(seed) or 0) % 4294967296 }
  function r.next()
    r.seed = (mul32(r.seed, 0x41C64E6D) + 0x6073) % 4294967296
    return math.floor(r.seed / 65536)
  end
  return r
end

local function speciesOf(mon)
  return require("src.pokemon.Gen4DayCare").speciesOf(mon)
end

-- CalcMonContestFame: one plus each rank's ribbon of this type held, from Normal up.
function Contest.fame(mon, contestType)
  local fame = 1
  local ribbons = mon and mon.ribbons or {}
  for rank = 0, 3 do
    if not ribbons[33 + contestType * 4 + rank] then break end
    fame = fame + 1
  end
  return fame
end

-- the ribbon this contest awards (RIBBON_COOL + rank, ...): 33 + type x 4 + rank
function Contest.ribbonId(contestType, rank) return 33 + contestType * 4 + rank end

-- sub_02095A74: the visual theme. Master (and link) draw from all twelve;
-- lower ranks from a growing list.
function Contest.theme(rank, rng)
  if rank >= Contest.MASTER then return rng.next() % 12 end
  local list = { 2, 3, 4 }
  if rank >= Contest.GREAT then list[#list + 1] = 0; list[#list + 1] = 1; list[#list + 1] = 5 end
  if rank >= Contest.ULTRA then list[#list + 1] = 6; list[#list + 1] = 7; list[#list + 1] = 8 end
  return list[rng.next() % #list + 1]
end

function Contest.isPractice(competition)
  return competition == Contest.PRACTICE_VISUAL or competition == Contest.PRACTICE_DANCE
      or competition == Contest.PRACTICE_ACTING
end

local function isSingleRound(competition)
  return competition == Contest.VISUAL or competition == Contest.DANCE or competition == Contest.ACTING
end

-- sub_02094F04: the NPC contestants for slots 1..3.
function Contest.pickOpponents(rec, contestType, rank, competition, postgame, rng)
  local practice, single = Contest.isPractice(competition), isSingleRound(competition)
  local pool = {}
  for i = 0, #rec.opponents do
    local o = rec.opponents[i]
    if o and o.rank == rank then
      local ok = true
      if postgame then ok = o.postgame ~= 1 else ok = o.postgame ~= 2 and o.postgame ~= 3 end
      if ok then
        if practice then ok = o.practice == 1
        elseif single then ok = o.official == 1
        else ok = o.practice ~= 1 and o.official ~= 1 end
      end
      if ok and o.types[contestType + 1] then pool[#pool + 1] = i end
    end
  end
  local picked = {}
  if single then
    for k = 1, 4 do picked[k - 1] = pool[k] end
    return picked
  end
  local guests = {}
  for _, i in ipairs(pool) do if rec.opponents[i].postgame == 3 then guests[#guests + 1] = i end end
  local guest
  if #guests > 0 then guest = guests[rng.next() % #guests + 1] end
  local slot = 1
  while slot <= 3 do
    local k = rng.next() % #pool + 1
    local id = pool[k]
    if rec.opponents[id].postgame == 3 then
      -- drawn again: the guest is placed below
    else
      picked[slot] = id
      table.remove(pool, k)
      slot = slot + 1
    end
  end
  if guest then picked[1 + rng.next() % 3] = guest end
  return picked
end

-- sub_020954F0: two regular judges of the rank and type, and one head judge
-- drawn at random; the head judge then trades places with judge 1.
function Contest.pickJudges(rec, contestType, rank, rng)
  local regular, head = {}, {}
  for i = 0, #rec.judges do
    local j = rec.judges[i]
    if j and j.rank == rank then
      local mark = j.types[contestType + 1]
      if mark > 1 then head[#head + 1] = i elseif mark == 1 then regular[#regular + 1] = i end
    end
  end
  local judges = { regular[1], regular[2], head[rng.next() % #head + 1] }
  judges[2], judges[3] = judges[3], judges[2]
  return judges
end

-- Contest_Init. `opts` = { rank, type, competition, mon, partySlot, playerName,
-- playerGender, postgame, seed, data }.
function Contest.new(opts)
  local data = opts.data
  local rec = data.gen4_contest
  local rng = Contest.rng(opts.seed or os.time())
  local c = {
    rank = opts.rank, type = opts.type, competition = opts.competition,
    partySlot = opts.partySlot, rng = rng, contestants = {},
  }
  c.theme = Contest.theme(opts.rank, rng)
  c.judges = Contest.pickJudges(rec, opts.type, opts.rank, rng)
  local mon = opts.mon
  c.contestants[0] = {
    player = true, mon = mon, trainer = opts.playerName or "", gender = opts.playerGender or 0,
    fame = Contest.fame(mon, opts.type),
    gfx = Contest.isPractice(opts.competition) and (opts.playerGender == 1 and "player_f" or "player_m")
          or (opts.playerGender == 1 and "player_f_contest" or "player_m_contest"),
    accessories = {},
  }
  local picked = Contest.pickOpponents(rec, opts.type, opts.rank, opts.competition, opts.postgame, rng)
  local T = require("src.import.Gen4Text")
  for id = 1, 3 do
    local o = rec.opponents[picked[id]]
    local names = data.text or {}
    local entrant = {
      mon = {
        species = o.species, level = 10,
        nickname = names[T.label(Contest.OPPONENT_NAMES, o.nameId)],
        moves = { { id = o.moves[1] }, { id = o.moves[2] }, { id = o.moves[3] }, { id = o.moves[4] } },
        contest = { cool = o.cool, beauty = o.beauty, cute = o.cute, smart = o.smart, tough = o.tough, sheen = o.sheen },
      },
      trainer = names[T.label(Contest.OPPONENT_NAMES, o.otNameId)] or "",
      gender = o.gender, fame = o.fame, gfx = o.gfx, record = picked[id], opponent = o,
      accessories = (rec.dressups[o.dress[c.theme]] or { items = {} }).items,
    }
    c.contestants[id] = entrant
  end
  c.scores = {}
  for id = 0, 3 do c.scores[id] = { visualStat = 0, visualDress = 0, dance = 0, acting = 0 } end
  return c
end

-- ov17_0223F374
function Contest.visualStatScore(c, mon)
  local stats = (mon and mon.contest) or {}
  local s = STATS[c.type]
  local item = tonumber(mon and (mon.item or mon.heldItem)) or 0
  local mod = SCARVES[c.type][item] or 100
  local score = (tonumber(stats[s[1]]) or 0)
      + math.floor(((tonumber(stats[s[2]]) or 0) + (tonumber(stats[s[3]]) or 0) + (tonumber(stats.sheen) or 0)) / 2)
  return math.floor(score * mod / 100)
end

-- ov17_02252A70: the worn accessories' worth in this theme.
function Contest.dressScore(c, data, accessories)
  local tbl = data.gen4_contest.themes[c.theme]
  local n = 0
  for _, a in ipairs(accessories or {}) do n = n + (tbl[a.accessory] or 0) end
  return n
end

function Contest.scoreVisual(c, data)
  for id = 0, 3 do
    local e = c.contestants[id]
    c.scores[id].visualStat = Contest.visualStatScore(c, e.mon)
    c.scores[id].visualDress = Contest.dressScore(c, data, e.accessories)
  end
end

-- sub_02095928 + sub_0209598C
function Contest.stars(c, id)
  local t = STAR_THRESHOLDS[c.rank]
  local v, n = c.scores[id].visualStat, 0
  for k = 1, 8 do if v < t[k] then return n end; n = n + 1 end
  return n
end

function Contest.hearts(c, id)
  local v = c.scores[id].visualDress
  if v == 0 then return 0 end
  local t = HEART_THRESHOLDS[c.rank]
  local n = 1
  for k = 1, 3 do if v <= t[k] then return n end; n = n + 1 end
  return n
end

function Contest.visualPoints(c, id) return Contest.stars(c, id) + Contest.hearts(c, id) end

-- ov17_02251860: each round's weight (x100).
function Contest.weight(c, round)
  local t = c.competition
  if t == Contest.ACTING_ONLY_UNK0 then return round == 0 and 6000 or round == 2 and 4000 or 0 end
  if t == Contest.DANCE_ONLY_UNK1 then return round == 0 and 7000 or round == 1 and 3000 or 0 end
  if t == Contest.OFFICIAL then return 3333 end
  if t == Contest.PRACTICE_VISUAL or t == Contest.VISUAL then return round == 0 and 10000 or 0 end
  if t == Contest.PRACTICE_DANCE or t == Contest.DANCE then return round == 1 and 10000 or 0 end
  if t == Contest.PRACTICE_ACTING or t == Contest.ACTING then return round == 2 and 10000 or 0 end
  return 0
end

local function raw(c, id, round)
  if round == 0 then return Contest.visualPoints(c, id) end
  if round == 1 then return c.scores[id].dance end
  return c.scores[id].acting
end

-- ov17_02251930 alone: one round's points, scaled so the best gets the
-- round's weight (x100). The Acting order after a Dance round sorts on these.
function Contest.roundPoints(c, round)
  local w = Contest.weight(c, round)
  local out, best = {}, 0
  for id = 0, 3 do best = math.max(best, raw(c, id, round)) end
  local unit = best > 0 and math.floor(w / best) or 0
  for id = 0, 3 do out[id] = math.floor((raw(c, id, round) * unit + 50) / 100) end
  return out
end

-- ov17_02251930 + ov17_02251A1C + the placement sort.
function Contest.finalScores(c)
  local bars = {}
  for id = 0, 3 do bars[id] = { 0, 0, 0, total = 0 } end
  for round = 0, 2 do
    local w = Contest.weight(c, round)
    if w > 0 then
      local best = 0
      for id = 0, 3 do best = math.max(best, raw(c, id, round)) end
      local unit = best > 0 and math.floor(w / best) or 0
      local scaled, top = {}, 0
      for id = 0, 3 do
        scaled[id] = math.floor((raw(c, id, round) * unit + 50) / 100)
        top = math.max(top, scaled[id])
      end
      local len = math.floor((192 * w + 5000) / 10000)
      for id = 0, 3 do
        local pct = top > 0 and math.floor(100 * scaled[id] / top) or 0
        bars[id][round + 1] = math.floor(len * pct / 100)
      end
    end
  end
  for id = 0, 3 do bars[id].total = bars[id][1] + bars[id][2] + bars[id][3] end
  return bars
end

function Contest.place(c)
  local bars = Contest.finalScores(c)
  local order, tie = {}, {}
  for id = 0, 3 do order[#order + 1] = id; tie[id] = c.rng.next() end
  table.sort(order, function(a, b)
    if bars[a].total ~= bars[b].total then return bars[a].total > bars[b].total end
    return tie[a] > tie[b]
  end)
  c.placement = {}
  for k, id in ipairs(order) do c.placement[id] = k - 1 end
  c.bars = bars
  return c.placement
end

-- ------------------------------------------------------------- accessors --
function Contest.entryToId(entry) return 3 - entry end
function Contest.idToEntry(id) return 3 - id end

function Contest.winner(c)
  for id = 0, 3 do if c.placement and c.placement[id] == 0 then return id end end
  return 0
end

function Contest.mode(c) return Contest.isPractice(c.competition) and Contest.MODE_PRACTICE or Contest.MODE_OFFICIAL end

-- Contest_CalcFirstTimeVictoryAccessoryReward, by type then rank (accessory
-- ids are bank 386's entries; accessories.txt has a NON_UNIQUE_ACCESSORY_COUNT
-- line in the middle, so its line numbers run one ahead): the barrette, the balloons, the
-- Ultra prize and the Master stage of the type's colour.
Contest.FIRST_WIN_ACCESSORY = {
  [0] = { [0] = 73, 78, 83, 88 },   -- Red Barrette, Red Balloons, Top Hat, Gold Pedestal
  [1] = { [0] = 74, 79, 84, 89 },   -- Blue Barrette, Blue Balloons, Silk Veil, Glass Stage
  [2] = { [0] = 72, 77, 82, 87 },   -- Pink Barrette, Pink Balloon, Lace Headdress, Flower Stage
  [3] = { [0] = 76, 81, 86, 91 },   -- Green Barrette, Green Balloons, Professor Hat, Cube Stage
  [4] = { [0] = 75, 80, 85, 90 },   -- Yellow Barrette, Yellow Balloons, Heroic Headband, Award Podium
}

return Contest
