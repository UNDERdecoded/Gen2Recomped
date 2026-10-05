-- PLATINUM'S ACTING COMPETITION, the rules (pokeplatinum overlay017:
-- ov17_0223B140.c the turn flow, ov17_02245F14.c the scoring steps and the
-- 24 contest effects, ov17_02243AC4.c the Voltage table and the reorder,
-- ov17_02246ECC.c the NPCs' choices).
--
-- Four turns. Each turn every contestant picks a move and one of the three
-- judges, then they perform in ORDER; each performance is scored in steps
-- (ov17_0223C100), every step starting with ov17_02246090 ("step" below):
--
--   1. base appeal      the move's contest effect's appeal (x10 points)
--   2. effect           category-3 effects run now (most of them)
--   3. carry            a Double Next Turn from last turn adds the score so far
--   4. Voltage          the move's type against the contest's type moves the
--                       judge's Voltage +10 / 0 / -10; reaching 50 pays 50,
--                       80 from the head judge (judge 1), and resets it to 0
--
-- After all four (ov17_0223C350): every contestant earns +30/20/10/0 for
-- sharing the judge with 0/1/2/3 others, the judge-dependent effects run
-- (category 5), then Pity Points (category 6). The turn's scores add to the
-- totals and set the next order (ov17_02243B0C): lowest turn score first,
-- ties to whoever performed later, overridden by Perform First / Last and
-- Random Order. Points are kept x10 as the cartridge keeps them; a heart is 10.
--
-- The Acting score that the final scoring reads (unk_118[].unk_06) is the
-- total.

local Acting = {}

Acting.TURNS = 4
Acting.HEAD_JUDGE = 1          -- contest.c: unk_10E = 1
Acting.MAX_VOLTAGE = 50
Acting.TEXT_BANK = 204         -- contest_text
Acting.EFFECT_TEXT = 211       -- contest_acting_competition (effect results)
Acting.EFFECT_DESC = 210       -- contest_effects (the move menu's two lines)

local E = {
  NONE = 0, FIRST_NEXT_TURN = 1, LAST_NEXT_TURN = 2, DOUBLED_JUDGE = 3, HEARTS_WHEN_VOLTAGE_UP = 4,
  BASIC = 5, UNIQUE_JUDGE = 6, CONSECUTIVE_USE = 7, VOLTAGE = 8, ALL_SAME_JUDGE = 9,
  LOWERS_VOLTAGE = 10, DOUBLE_NEXT_TURN = 11, STEAL_VOLTAGE = 12, SUPPRESS_VOLTAGE = 13,
  RANDOM_ORDER = 14, DOUBLE_FINAL_ACT = 15, LOW_VOLTAGE_ADV = 16, FIRST_PERF_ADV = 17,
  FINAL_PERF_ADV = 18, NO_VOLTAGE_DOWN = 19, TWO_VOLTAGE_IN_A_ROW = 20, HIGH_SCORE_LATER = 21,
  MAX_VOLTAGE_ADV = 22, PITY = 23,
}
Acting.EFFECT = E

-- Unk_ov17_02253AF8: when each effect runs (3 during the performance, 5 after
-- the judge shares, 6 last) and whether it announces itself before scoring.
local CATEGORY = {}
for e = 0, 23 do CATEGORY[e] = 3 end
CATEGORY[E.DOUBLED_JUDGE], CATEGORY[E.UNIQUE_JUDGE], CATEGORY[E.ALL_SAME_JUDGE] = 5, 5, 5
CATEGORY[E.PITY] = 6
local ANNOUNCES = { [E.UNIQUE_JUDGE] = true, [E.ALL_SAME_JUDGE] = true }
Acting.CATEGORY = CATEGORY

-- Unk_ov17_022539C8 [contest type][move's contest type]
local VOLTAGE = {
  [0] = { [0] = 10, 0, -10, -10, 0 }, [1] = { [0] = 0, 10, 0, -10, -10 },
  [2] = { [0] = -10, 0, 10, 0, -10 }, [3] = { [0] = -10, -10, 0, 10, 0 },
  [4] = { [0] = 0, -10, -10, 0, 10 },
}
Acting.VOLTAGE = VOLTAGE

-- ov17_02243AE4: the judge share by how many others chose the same judge
local SHARE = { [0] = 30, 20, 10, 0 }
-- the reorder's overrides (Unk_ov17_022539C0 / B0 / B8)
local FIRST_KEY = { [0] = -30000, -29990, -29980, -29970 }
local LAST_KEY = { [0] = 29970, 29980, 29990, 30000 }
local RANDOM_KEY = { [0] = -10000, -500, 500, 10000 }
-- ov17_02246F9C: the chance (/256) an NPC with no judge preference avoids
-- the player's judge, by rank
local AVOID_PLAYER = { [0] = 230, 128, 51, 0 }

local function moveDef(data, id) return data.moves and data.moves[tonumber(id) or 0] end
local function moveEffect(data, id) local m = moveDef(data, id) return m and tonumber(m.contestEffect) or 0 end
local function moveType(data, id) local m = moveDef(data, id) return m and tonumber(m.contestType) or 0 end

function Acting.appeal(data, effect)
  local t = data.gen4_contest and data.gen4_contest.effects
  local e = t and t[effect]
  return e and e.appeal or 0
end

function Acting.voltageDelta(contestType, mvType) return VOLTAGE[contestType][mvType] or 0 end

-- ------------------------------------------------------------- setup --
-- The first turn's order (unk_156): after a Dance round, best Visual +
-- Dance points first (ov17_0223EEB8); otherwise ids 0..3, reversed for a
-- practice (Contest_Init).
function Acting.initialOrder(c, hadDance)
  local C = require("src.pokemon.Gen4Contest")
  local order = {}
  if hadDance then
    local v, d = C.roundPoints(c, 0), C.roundPoints(c, 1)
    local key = {}
    for id = 0, 3 do order[id + 1] = id; key[id] = v[id] + d[id] end
    for i = 1, 3 do                               -- the cartridge's bubble sort, stable on ties
      for j = 4, i + 1, -1 do
        if key[order[j - 1]] < key[order[j]] then order[j - 1], order[j] = order[j], order[j - 1] end
      end
    end
  elseif C.isPractice(c.competition) then
    order = { 3, 2, 1, 0 }
  else
    order = { 0, 1, 2, 3 }
  end
  return order
end

function Acting.new(c, data, opts)
  opts = opts or {}
  local s = {
    c = c, data = data, type = c.type, rank = c.rank, rng = c.rng,
    turn = 0,                                     -- unk_00
    order = opts.order or Acting.initialOrder(c, opts.hadDance),   -- unk_01, ids by position
    totals = { [0] = 0, 0, 0, 0 },                 -- unk_12
    turnScore = { [0] = 0, 0, 0, 0 },              -- unk_1A
    voltage = { [0] = 0, 0, 0 },                   -- unk_22
    lastMove = { [0] = 0, 0, 0, 0 },               -- unk_26
    -- unk_30, what the last turn left behind
    saved = { carry = { [0] = 0, 0, 0, 0 }, repeatMove = { [0] = 0, 0, 0, 0 }, carryApplied = { [0] = 0, 0, 0, 0 } },
    log = {},
  }
  return s
end

-- ov17_02243A98: a move may not be used twice in a row unless it was a
-- Consecutive Use move that worked last turn.
function Acting.canUse(s, id, move)
  move = tonumber(move) or 0
  if move == 0 then return false end
  if move == s.lastMove[id] and s.saved.repeatMove[id] ~= move then return false end
  return true
end

function Acting.positionOf(s, id)
  for p = 1, 4 do if s.order[p] == id then return p - 1 end end
  return 0
end

-- ---------------------------------------------------------------- AI --
-- Unk_ov17_02253BBC: the 28 conditions. `m` is the NPC's four usable moves,
-- `marks` the three judges a condition points at.
local function anyEffect(m, e) for k = 1, 4 do if m[k].effect == e then return true end end return false end
local function anyType(m, t) for k = 1, 4 do if m[k].type == t then return true end end return false end
local function markVoltage(s, marks, test)
  local n = 0
  for j = 0, 2 do if test(s.voltage[j]) then marks[j] = 1; n = n + 1 end end
  return n
end
local function lowestTotal(s, id)
  for v = 0, 3 do if s.totals[id] > s.totals[v] then return false end end
  return true
end

local COND = {
  [1] = function(s) return s.turn == 4 end,
  [2] = function(s, id) return s.saved.carryApplied[id] ~= E.NONE end,
  [3] = function(s, id, m) return anyEffect(m, E.BASIC) end,
  [4] = function(s, id, m) return anyEffect(m, E.ALL_SAME_JUDGE) end,
  [5] = function(s, id, m) return anyEffect(m, E.STEAL_VOLTAGE) end,
  [6] = function(s, id, m) return anyEffect(m, E.DOUBLE_FINAL_ACT) end,
  [7] = function(s, id, m) return anyEffect(m, E.FIRST_PERF_ADV) end,
  [8] = function(s, id, m) return anyEffect(m, E.FINAL_PERF_ADV) end,
  [9] = function(s, id, m) return anyEffect(m, E.NO_VOLTAGE_DOWN) end,
  [10] = function(s, id, m) return anyEffect(m, E.TWO_VOLTAGE_IN_A_ROW) end,
  [11] = function(s, id, m) return anyEffect(m, E.HIGH_SCORE_LATER) end,
  [12] = function(s, id) return lowestTotal(s, id) end,
  [13] = function(s, id) return s.turn == 4 and lowestTotal(s, id) end,
  [14] = function(s, id, m)
    for k = 1, 4 do if m[k].effect == E.HEARTS_WHEN_VOLTAGE_UP and m[k].type == s.type then return true end end
    return false
  end,
  [15] = function(s, id, m) return anyType(m, s.type) end,
  [16] = function(s, id, m, marks)
    if not anyType(m, s.type) then return false end
    return markVoltage(s, marks, function(v) return v == 40 end) > 0
  end,
  [17] = function(s, id, m, marks)
    if not anyType(m, s.type) then return false end
    return markVoltage(s, marks, function(v) return v == 30 end) > 0
  end,
  [18] = function(s, id, m) return anyEffect(m, E.VOLTAGE) end,
  [19] = function(s, id, m) return anyEffect(m, E.SUPPRESS_VOLTAGE) end,
  [20] = function(s, id, m, marks) return markVoltage(s, marks, function(v) return v == 40 end) > 0 end,
  [21] = function(s, id, m, marks) return markVoltage(s, marks, function(v) return v == 30 end) > 0 end,
  [22] = function(s, id, m, marks) return markVoltage(s, marks, function(v) return v <= 10 end) > 0 end,
  [23] = function(s, id, m, marks)
    for j = 0, 2 do if s.voltage[j] < 20 then return false end end
    for j = 0, 2 do marks[j] = 1 end
    return true
  end,
  [24] = function(s, id, m, marks)
    for j = 0, 2 do if s.voltage[j] > 20 then return false end end
    for j = 0, 2 do marks[j] = 1 end
    return true
  end,
  [25] = function(s, id, m, marks) return markVoltage(s, marks, function(v) return v <= 20 end) == 1 end,
  [26] = function(s, id, m, marks) return markVoltage(s, marks, function(v) return v == 40 end) == 2 end,
  [27] = function(s, id, m, marks) return markVoltage(s, marks, function(v) return v == 0 end) == 1 end,
  [28] = function(s, id, m, marks)
    if not anyType(m, s.type) then return false end
    return markVoltage(s, marks, function(v) return v == 40 end) > 0
  end,
}
Acting.COND = COND

-- ov17_02246F9C. `moves` is the NPC's four move ids, `level` its AI level
-- (contest_data's 2-bit field, unk_FC), `playerJudge` the judge the player
-- picked this turn. Returns move, judge.
function Acting.chooseNpc(s, id, moves, level, playerJudge)
  local data = s.data
  local rows = data.gen4_contest and data.gen4_contest.actingAI or {}
  level = tonumber(level) or 0
  local m = {}
  for k = 1, 4 do
    local mv = tonumber(moves[k]) or 0
    if not Acting.canUse(s, id, mv) then mv = 0 end
    m[k] = { id = mv, score = 0, judge = { [0] = 0, 0, 0 },
             effect = mv ~= 0 and moveEffect(data, mv) or 0, type = mv ~= 0 and moveType(data, mv) or 0 }
  end
  local pos = Acting.positionOf(s, id) + 1
  for _, row in ipairs(rows) do
    if row.position == pos then
      local marks = { [0] = 0, 0, 0 }
      local fn = COND[row.cond]
      if fn and fn(s, id, m, marks) then
        if row.mode == 0 then marks = { [0] = 0, 0, 0 }
        elseif row.mode == 2 or row.mode == 3 then for j = 0, 2 do marks[j] = 1 - marks[j] end end
        local w = row.weights[level] or 0
        if level ~= 0 then w = w + (row.weights[0] or 0) end
        for k = 1, 4 do
          local hit
          if row.target == 240 then hit = m[k].type == s.type
          elseif row.target == 241 then hit = Acting.appeal(data, m[k].effect) >= 20
          else hit = m[k].effect == row.target end
          if hit then
            m[k].score = m[k].score + w
            for j = 0, 2 do if marks[j] == 1 then m[k].judge[j] = m[k].judge[j] + w end end
          end
        end
      end
    end
  end
  local r8, r9 = {}, {}
  for k = 1, 4 do r8[k] = s.rng.next() end
  for j = 0, 2 do r9[j] = s.rng.next() end
  local best
  for k = 1, 4 do
    if m[k].id ~= 0 then
      if not best or m[k].score > m[best].score or (m[k].score == m[best].score and r8[k] > r8[best]) then best = k end
    end
  end
  if not best then return 0, 0 end
  local pick = m[best]
  local zero = pick.judge[0] == 0 and pick.judge[1] == 0 and pick.judge[2] == 0
  if zero and playerJudge then
    local roll = s.rng.next() % 256
    if roll < (AVOID_PLAYER[s.rank] or 0) then pick.judge[playerJudge] = pick.judge[playerJudge] - 100 end
  end
  local judge = 0
  for j = 1, 2 do
    if pick.judge[j] > pick.judge[judge] or (pick.judge[j] == pick.judge[judge] and r9[j] > r9[judge]) then judge = j end
  end
  return pick.id, judge
end

-- -------------------------------------------------------------- turn --
-- ov17_02245F44: the turn's working state from everyone's choices.
-- `choices[id] = { move = , judge = }`.
function Acting.beginTurn(s, choices)
  local t = { p = {}, B0 = {}, B3 = {}, A0 = {}, events = {} }
  for id = 0, 3 do
    t.A0[id] = { effect = s.saved.carry[id], move = 0 }
  end
  for id = 0, 3 do
    local ch = choices[id]
    t.p[id] = {
      move = tonumber(ch.move) or 0, judge = tonumber(ch.judge) or 0,
      score = 0, s1A = 0, s1C = 0, b1E = 0, bonus = 0,
      suppress = false, noDown = false, orderFlag = 0, slot = 0, carry = 0,
    }
    t.p[id].effect = moveEffect(s.data, t.p[id].move)
    t.p[id].mtype = moveType(s.data, t.p[id].move)
  end
  for id = 0, 3 do
    local n = -1
    for v = 0, 3 do if t.p[v].judge == t.p[id].judge then n = n + 1 end end
    t.p[id].others = n
  end
  for j = 0, 2 do t.B0[j] = s.voltage[j]; t.B3[j] = s.voltage[j] end
  s.t = t
  return t
end

-- ov17_02246090
local function step(t, id)
  local p = t.p[id]
  p.s1A = p.score
  p.b1E = 0
  for j = 0, 2 do t.B0[j] = t.B3[j] end
  t.record = nil
end

-- ov17_02245F14: the line an effect leaves for the screen
local function record(t, id, effect, variant, a, b, move, num)
  t.record = { kind = "effect", id = id, effect = effect, variant = variant, a = a, b = b, move = move, num = num }
end

local function flush(t, list)
  if t.record then list[#list + 1] = t.record; t.record = nil end
end

-- the 24 effect routines: (s, t, self, position) -> worked
local FX = {}
FX[E.NONE] = function() return true end
FX[E.BASIC] = FX[E.NONE]

FX[E.FIRST_NEXT_TURN] = function(s, t, me, pos)
  local v0, prevFirst = {}, nil
  for id = 0, 3 do
    local p = t.p[id]
    if p.orderFlag == 0 then v0[id] = false
    else
      if p.orderFlag == 1 and p.slot == 0 then prevFirst = id end
      v0[id] = p.slot
    end
  end
  v0[me] = false
  for slot = 0, 3 do
    local hit
    for id = 0, 3 do
      if v0[id] and v0[id] == slot and v0[id] == t.p[id].slot then v0[id] = v0[id] + 1; hit = true; break end
    end
    if not hit then break end
  end
  for id = 0, 3 do if v0[id] then t.p[id].slot = v0[id] % 4 end end
  t.p[me].orderFlag, t.p[me].slot = 1, 0
  if prevFirst then record(t, me, t.p[me].effect, 1, me, prevFirst) else record(t, me, t.p[me].effect, 0, me) end
  return true
end

FX[E.LAST_NEXT_TURN] = function(s, t, me, pos)
  local v2, prevLast = {}, nil
  for id = 0, 3 do
    local p = t.p[id]
    if p.orderFlag == 0 then v2[id] = false
    else
      if p.orderFlag == 2 and p.slot == 3 then prevLast = id end
      v2[id] = p.slot
    end
  end
  v2[me] = false
  for slot = 3, 0, -1 do
    local hit
    for id = 0, 3 do
      if v2[id] and v2[id] == slot and v2[id] == t.p[id].slot then
        v2[id] = v2[id] - 1
        if v2[id] < 0 then v2[id] = false end      -- u8 0xFF is the "no slot" mark
        hit = true
        break
      end
    end
    if not hit then break end
  end
  for id = 0, 3 do if v2[id] then t.p[id].slot = v2[id] end end
  t.p[me].orderFlag, t.p[me].slot = 2, 3
  if prevLast then record(t, me, t.p[me].effect, 1, me, prevLast) else record(t, me, t.p[me].effect, 0, me) end
  return true
end

FX[E.DOUBLED_JUDGE] = function(s, t, me)
  local p = t.p[me]
  p.b1E = p.b1E + p.others * 20
  record(t, me, p.effect, math.min(p.others, 3), me)
  return true
end

FX[E.HEARTS_WHEN_VOLTAGE_UP] = function(s, t, me)
  local p = t.p[me]
  if VOLTAGE[s.type][p.mtype] > 0 and not p.suppress then
    p.b1E = p.b1E + 20
    record(t, me, p.effect, 0, me, nil, p.move)
    return true
  end
  return false
end

FX[E.UNIQUE_JUDGE] = function(s, t, me)
  local p = t.p[me]
  if p.others == 0 then p.b1E = p.b1E + 30; record(t, me, p.effect, 0, me)
  else record(t, me, p.effect, 1, me) end
  return true
end

FX[E.CONSECUTIVE_USE] = function(s, t, me)
  local p = t.p[me]
  if p.move ~= s.lastMove[me] then
    t.A0[me].move = p.move
    record(t, me, p.effect, 0, me)
    return true
  end
  return false
end

FX[E.VOLTAGE] = function(s, t, me)
  local p = t.p[me]
  local v = t.B0[p.judge]
  p.b1E = p.b1E + v
  record(t, me, p.effect, 0, nil, nil, nil, math.floor(v / 10))
  return true
end

FX[E.ALL_SAME_JUDGE] = function(s, t, me)
  local p = t.p[me]
  if p.others == 3 then p.b1E = p.b1E + 150; record(t, me, p.effect, 0, me)
  else record(t, me, p.effect, 1, me) end
  return true
end

FX[E.LOWERS_VOLTAGE] = function(s, t, me)
  local p = t.p[me]
  if p.noDown then return false end
  local any = false
  for j = 0, 2 do if t.B3[j] ~= 0 then any = true end end
  if not any then return false end
  for j = 0, 2 do if t.B3[j] > 0 then t.B3[j] = t.B3[j] - 10 end end
  record(t, me, p.effect, 0)
  return true
end

FX[E.DOUBLE_NEXT_TURN] = function(s, t, me)
  t.p[me].carry = t.p[me].effect
  return true
end

FX[E.STEAL_VOLTAGE] = function(s, t, me, pos)
  if pos == 0 then return false end
  local prev = s.order[pos]
  if t.p[prev].bonus == 0 then return false end
  t.p[me].b1E = t.p[me].b1E + t.p[prev].bonus
  record(t, me, t.p[me].effect, 0, me, prev)
  return true
end

FX[E.SUPPRESS_VOLTAGE] = function(s, t, me, pos)
  for v = pos, 3 do t.p[s.order[v + 1]].suppress = true end
  record(t, me, t.p[me].effect, 0)
  return true
end

FX[E.RANDOM_ORDER] = function(s, t, me)
  local slotOf, free = {}, { [0] = true, true, true, true }
  for k = 0, 3 do
    local r = s.rng.next() % (4 - k)
    for id = 0, 3 do
      if free[id] then
        if r == 0 then slotOf[id] = k; free[id] = false; break end
        r = r - 1
      end
    end
  end
  for id = 0, 3 do t.p[id].orderFlag = 3; t.p[id].slot = slotOf[id] end
  record(t, me, t.p[me].effect, 0)
  return true
end

FX[E.DOUBLE_FINAL_ACT] = function(s, t, me, pos)
  if pos ~= 3 then return false end
  local p = t.p[me]
  p.b1E = p.b1E + p.score
  record(t, me, p.effect, 0, nil, nil, nil, math.floor(p.score / 10))
  return true
end

local LOW_VOLTAGE = { [0] = 40, 30, 20, 10, 0, 0 }
FX[E.LOW_VOLTAGE_ADV] = function(s, t, me)
  local p = t.p[me]
  local add = LOW_VOLTAGE[math.floor(t.B0[p.judge] / 10)] or 0
  p.b1E = p.b1E + add
  record(t, me, p.effect, 0, nil, nil, nil, math.floor(add / 10))
  return true
end

FX[E.FIRST_PERF_ADV] = function(s, t, me, pos)
  if pos ~= 0 then return false end
  t.p[me].b1E = t.p[me].b1E + 20
  record(t, me, t.p[me].effect, 0)
  return true
end

FX[E.FINAL_PERF_ADV] = function(s, t, me, pos)
  if pos ~= 3 then return false end
  t.p[me].b1E = t.p[me].b1E + 20
  record(t, me, t.p[me].effect, 0)
  return true
end

FX[E.NO_VOLTAGE_DOWN] = function(s, t, me, pos)
  for v = pos, 3 do t.p[s.order[v + 1]].noDown = true end
  record(t, me, t.p[me].effect, 0)
  return true
end

FX[E.TWO_VOLTAGE_IN_A_ROW] = function(s, t, me, pos)
  if pos == 0 then return false end
  local prev = s.order[pos]
  if t.p[me].suppress or t.p[prev].suppress then return false end
  if VOLTAGE[s.type][t.p[prev].mtype] > 0 and VOLTAGE[s.type][t.p[me].mtype] > 0 then
    t.p[me].b1E = t.p[me].b1E + 30
    record(t, me, t.p[me].effect, 0, me, prev)
    return true
  end
  return false
end

local LATER = { [0] = 10, 20, 30, 40 }
FX[E.HIGH_SCORE_LATER] = function(s, t, me, pos)
  t.p[me].b1E = t.p[me].b1E + LATER[pos]
  record(t, me, t.p[me].effect, math.min(pos, 3), me)
  return true
end

FX[E.MAX_VOLTAGE_ADV] = function(s, t, me, pos)
  if pos == 0 then return false end
  local prev = s.order[pos]
  if t.p[prev].bonus >= 50 then
    t.p[me].b1E = t.p[me].b1E + 30
    record(t, me, t.p[me].effect, 0, me)
    return true
  end
  return false
end

FX[E.PITY] = function(s, t, me)
  for v = 0, 3 do
    if v ~= me and t.p[v].s1A < t.p[me].s1C then return false end
  end
  t.p[me].b1E = t.p[me].b1E + 30
  record(t, me, t.p[me].effect, 0, me)
  return true
end
Acting.FX = FX

-- ov17_0223C068 .. ov17_0223C100 + ov17_02246018: the performer at `pos`.
-- Returns the events for the screen.
function Acting.perform(s, pos)
  local t = s.t
  local id = s.order[pos + 1]
  local p = t.p[id]
  local ev = {}
  local already = false
  for k = 0, pos - 1 do if t.p[s.order[k + 1]].judge == p.judge then already = true end end
  ev[#ev + 1] = { kind = "performed", id = id, judge = p.judge, move = p.move, already = already }
  -- ov17_022460DC: Unique Judge / All Same Judge say what they will do
  step(t, id)
  if ANNOUNCES[p.effect] then record(t, id, p.effect, 4, id); flush(t, ev) end
  -- ov17_02245FB4
  for j = 0, 2 do t.B0[j] = s.voltage[j]; t.B3[j] = s.voltage[j] end
  -- ov17_02246138: base appeal
  step(t, id)
  p.base = Acting.appeal(s.data, p.effect)
  p.score = p.base
  ev[#ev + 1] = { kind = "appeal", id = id, points = p.base }
  -- ov17_02246160: the effect
  step(t, id)
  if CATEGORY[p.effect] == 3 then
    local before = p.score
    FX[p.effect](s, t, id, pos)
    p.score = p.score + p.b1E
    flush(t, ev)
    if p.score ~= before then ev[#ev + 1] = { kind = "bonus", id = id, points = p.score - before } end
  end
  -- ov17_02246228: last turn's Double Next Turn
  step(t, id)
  if t.A0[id].effect ~= E.NONE then
    local v = p.score
    p.b1E = p.b1E + v
    record(t, id, t.A0[id].effect, 0, id, nil, nil, math.floor(v / 10))
    flush(t, ev)
    if v ~= 0 then ev[#ev + 1] = { kind = "bonus", id = id, points = v } end
  end
  p.score = p.score + p.b1E
  -- ov17_022463C4: Voltage
  step(t, id)
  local j = p.judge
  local d = VOLTAGE[s.type][p.mtype]
  if d > 0 and not p.suppress then
    t.B3[j] = math.min(t.B3[j] + d, Acting.MAX_VOLTAGE)
  elseif d < 0 and not p.noDown and t.B3[j] > 0 then
    t.B3[j] = math.max(t.B3[j] + d, 0)
  else
    d = 0
  end
  if t.B3[j] >= Acting.MAX_VOLTAGE then p.bonus = (j == Acting.HEAD_JUDGE) and 80 or 50 end
  if d ~= 0 then ev[#ev + 1] = { kind = "voltage", id = id, judge = j, delta = d, mtype = p.mtype, level = t.B3[j], bonus = p.bonus } end
  p.score = p.score + p.bonus
  -- ov17_02246018
  for k = 0, 2 do
    s.voltage[k] = t.B3[k]
    if s.voltage[k] >= Acting.MAX_VOLTAGE then s.voltage[k] = 0 end
  end
  return ev
end

-- ov17_0223C350 + ov17_0223C888: after the fourth performance.
function Acting.endTurn(s)
  local t = s.t
  local ev = {}
  -- ov17_02246518: the judge shares, by contestant id
  for id = 0, 3 do
    step(t, id)
    t.p[id].score = t.p[id].score + SHARE[t.p[id].others]
  end
  -- the judges' impressions, busiest judge first (stable on ties)
  local count, byJudge, judges = { [0] = 0, 0, 0 }, { [0] = {}, {}, {} }, { 0, 1, 2 }
  for pos = 1, 4 do
    local id = s.order[pos]
    local j = t.p[id].judge
    count[j] = count[j] + 1
    byJudge[j][#byJudge[j] + 1] = id
  end
  for i = 1, 2 do
    for k = 3, i + 1, -1 do
      if count[judges[k - 1]] < count[judges[k]] then judges[k - 1], judges[k] = judges[k], judges[k - 1] end
    end
  end
  for _, j in ipairs(judges) do
    if count[j] > 0 then ev[#ev + 1] = { kind = "judge", judge = j, count = count[j], ids = byJudge[j] } end
  end
  -- category 5, by position
  for pos = 0, 3 do
    local id = s.order[pos + 1]
    step(t, id)
    if CATEGORY[t.p[id].effect] == 5 then
      FX[t.p[id].effect](s, t, id, pos)
      t.p[id].score = t.p[id].score + t.p[id].b1E
      flush(t, ev)
    end
  end
  -- ov17_022460C8, then category 6
  for id = 0, 3 do t.p[id].s1C = t.p[id].score end
  for pos = 0, 3 do
    local id = s.order[pos + 1]
    step(t, id)
    if CATEGORY[t.p[id].effect] == 6 then
      FX[t.p[id].effect](s, t, id, pos)
      t.p[id].score = t.p[id].score + t.p[id].b1E
      flush(t, ev)
    end
  end
  -- ov17_02246044
  for id = 0, 3 do
    s.totals[id] = s.totals[id] + t.p[id].score
    s.turnScore[id] = t.p[id].score
  end
  local overridden = 0
  for id = 0, 3 do if t.p[id].orderFlag ~= 0 then overridden = overridden + 1 end end
  if s.turn < Acting.TURNS - 1 and overridden < 4 then ev[#ev + 1] = { kind = "lowestFirst" } end
  Acting.reorder(s)
  for id = 0, 3 do
    s.lastMove[id] = t.p[id].move
    s.saved.carry[id] = t.p[id].carry
    s.saved.repeatMove[id] = t.A0[id].move
    s.saved.carryApplied[id] = t.A0[id].effect
  end
  s.turn = s.turn + 1
  return ev
end

-- ov17_02243B0C
function Acting.reorder(s)
  local t = s.t
  local key, ids, prevPos = {}, {}, {}
  for id = 0, 3 do
    key[id + 1] = s.turnScore[id]
    ids[id + 1] = id
    prevPos[id + 1] = Acting.positionOf(s, id)
    local p = t and t.p[id]
    if p then
      if p.orderFlag == 1 then key[id + 1] = FIRST_KEY[p.slot]
      elseif p.orderFlag == 2 then key[id + 1] = LAST_KEY[p.slot]
      elseif p.orderFlag == 3 then key[id + 1] = RANDOM_KEY[p.slot] end
    end
  end
  for i = 1, 3 do
    for j = 4, i + 1, -1 do
      if key[j - 1] > key[j] or (key[j - 1] == key[j] and prevPos[j - 1] < prevPos[j]) then
        key[j - 1], key[j] = key[j], key[j - 1]
        ids[j - 1], ids[j] = ids[j], ids[j - 1]
        prevPos[j - 1], prevPos[j] = prevPos[j], prevPos[j - 1]
      end
    end
  end
  s.order = ids
end

function Acting.done(s) return s.turn >= Acting.TURNS end

-- A whole turn without a screen: the player's choice plus the NPCs' own.
function Acting.playTurn(s, choices, npc)
  local ch = {}
  for id = 0, 3 do ch[id] = choices[id] end
  for id = 0, 3 do
    if not ch[id] and npc and npc[id] then
      local mv, j = Acting.chooseNpc(s, id, npc[id].moves, npc[id].level, ch[0] and ch[0].judge)
      ch[id] = { move = mv, judge = j }
    end
  end
  Acting.beginTurn(s, ch)
  local events = {}
  for pos = 0, 3 do for _, e in ipairs(Acting.perform(s, pos)) do events[#events + 1] = e end end
  for _, e in ipairs(Acting.endTurn(s)) do events[#events + 1] = e end
  return events, ch
end

return Acting
