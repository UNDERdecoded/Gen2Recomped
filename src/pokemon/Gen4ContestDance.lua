-- PLATINUM'S DANCE COMPETITION, the rules (pokeplatinum overlay017:
-- ov17_0223DAD0.c drives the round, ov17_0224CFB8.c judges, ov17_0224E930.c
-- is the computer dancers, ov17_0224A0FC.c scores). Times are frames at 60 Hz
-- from the moment the song starts.
--
-- THE SONG (Unk_ov17_02253084, picked by Unk_ov17_0225312C[rank][type]):
-- a step is 1800 / BPM frames, a measure 16 steps (layout 0) or 12 (layout
-- 1). Four rounds, each contestant leading once in id order 3, 2, 1, 0 --
-- the player last -- for two measures each. Round r's first measure starts at
-- 2r x measure + (intro + r x (intro + gap)) x step.
--
-- A MEASURE: the lead dances in the first half -- up to the song's moves, while
-- t < measure/2 - step/4 -- and the three behind copy in the second half,
-- while measure/2 <= t < measure - step/4. After a move a dancer cannot move
-- again for step - 2 frames.
--
-- THE JUDGE (ov17_0224DDE4 / ov17_0224DD90): t snaps to the nearest half step
-- (the earlier one on a tie) and the distance in whole frames is held against
-- the song's thresholds: <= t1 EXCELLENT (2 points), <= t3 GOOD (1), else MISS.
-- The lead is judged on timing alone. A back dancer's move counts only if the
-- lead made one exactly half a measure earlier (ov17_0224DE54), and in the
-- same direction -- otherwise it is a miss, a wrong move.
--
-- THE COMPUTER DANCERS: a skill 0..3 from their contest_data record (bits 14-15,
-- higher is sloppier). Leading (ov17_0224E990): the song's moves on whole
-- steps (Normal, Great) or half steps never side by side, an off-beat one kept
-- half the time (Ultra, Master), never the first slot; each a few frames off
-- ({1,2,3,4}[skill] x2 / x1 / /2 / /3 by rank); the first direction random,
-- each next one repeating the last {90,40,0,0}[rank]% of the time, the last
-- always random. Copying (ov17_0224EE90): on time give or take
-- {1,2,3,4}[skill] x {2,2,1.5,1}[rank] frames, and wrong that many percent of
-- the time plus the move's difficulty x the same: +3 for the skill's weak
-- direction, +8 for a change of direction, +2 for a change of beat, +5 after
-- a long gap.
--
-- Points add up over all four rounds, leading and following, into the
-- contest's `dance` score (unk_118[].unk_04), which the final scoring scales.

local Contest = require("src.pokemon.Gen4Contest")

local Dance = {}

Dance.BANK = 206
Dance.JUMP, Dance.FRONT, Dance.LEFT, Dance.RIGHT = 1, 2, 3, 4
Dance.EXCELLENT, Dance.GOOD, Dance.MISS = 0, 1, 2

-- { seq, bpm, measures per lead, moves, intro steps, gap steps, thresholds }
Dance.SONGS = {
  [0] = { seq = 0x499, bpm = 120, measures = 2, moves = 3, intro = 4, gap = 4, judge = { 2, 2, 3, 3 } },
  [1] = { seq = 0x49B, bpm = 120, measures = 2, moves = 4, intro = 4, gap = 4, judge = { 2, 2, 3, 3 } },
  [2] = { seq = 0x4B5, bpm = 100, measures = 2, moves = 4, intro = 3, gap = 3, judge = { 1, 1, 2, 2 } },
  [3] = { seq = 0x4B9, bpm = 60, measures = 2, moves = 4, intro = 3, gap = 3, judge = { 2, 2, 3, 3 } },
  [4] = { seq = 0x4B7, bpm = 150, measures = 2, moves = 4, intro = 4, gap = 4, judge = { 1, 1, 2, 2 } },
  [5] = { seq = 0x4B6, bpm = 132, measures = 2, moves = 4, intro = 4, gap = 4, judge = { 1, 1, 2, 2 } },
  [6] = { seq = 0x4B8, bpm = 140, measures = 2, moves = 4, intro = 4, gap = 4, judge = { 1, 1, 2, 2 } },
}
-- Unk_ov17_02252FC4: steps a measure, the bar's width in tiles
Dance.LAYOUTS = { [0] = { steps = 16, barTiles = 32 }, [1] = { steps = 12, barTiles = 30 } }

-- Unk_ov17_0225312C: { song, layout } by rank, then type
function Dance.pick(rank, contestType)
  if rank == Contest.NORMAL then return 0, 0 end
  if rank == Contest.GREAT or rank == Contest.LINK then return 1, 0 end
  local t = ({ [0] = { 2, 1 }, { 3, 1 }, { 4, 0 }, { 5, 0 }, { 6, 0 } })[contestType] or { 1, 0 }
  return t[1], t[2]
end

local function rankIndex(rank)
  if rank == Contest.LINK then return 1 end
  return math.max(0, math.min(3, rank or 0))
end

function Dance.new(c, rng)
  local song, layout = Dance.pick(c.rank, c.type)
  local s, L = Dance.SONGS[song], Dance.LAYOUTS[layout]
  local d = {
    c = c, rng = rng or c.rng, songIndex = song, song = s, layout = layout,
    step = 1800 / s.bpm, steps = L.steps, moves = s.moves, rank = rankIndex(c.rank),
    points = { [0] = 0, 0, 0, 0 },
  }
  d.hs = d.step / 2
  d.measure = d.step * d.steps
  d.half = d.measure / 2
  return d
end

function Dance.rand(d, n) return d.rng.next() % n end

-- the stage order for round r (unk_05, rotated left a round): slot 1 leads
function Dance.order(r)
  local o = { 3, 2, 1, 0 }
  for _ = 1, r do table.insert(o, table.remove(o, 1)) end
  return o
end
function Dance.leader(r) return 3 - r end

function Dance.roundStart(d, r)
  return 2 * r * d.measure + (d.song.intro + r * (d.song.intro + d.song.gap)) * d.step
end
function Dance.measureStart(d, r, m) return Dance.roundStart(d, r) + m * d.measure end
function Dance.finish(d) return Dance.measureStart(d, 3, d.song.measures) end

function Dance.canLead(d, t, count) return t >= 0 and t < d.half - d.step / 4 and count < d.moves end
function Dance.canCopy(d, t, count) return t >= d.half and t < d.measure - d.step / 4 and count < d.moves end
function Dance.cooldown(d) return math.floor(d.step) - 2 end

-- ov17_0224DDE4 + ov17_0224DD90: the half-step grid point and the verdict
function Dance.judge(d, t)
  local g = math.floor(t / d.hs)
  local rem = t - g * d.hs
  local dist
  if rem > d.hs / 2 then g, dist = g + 1, d.hs - rem else dist = rem end
  dist = math.floor(dist)
  local th = d.song.judge
  if dist <= th[2] then return g, Dance.EXCELLENT end
  if dist <= th[4] then return g, Dance.GOOD end
  return g, Dance.MISS
end

Dance.POINTS = { [0] = 2, 1, 0 }

-- a measure's bookkeeping
function Dance.newMeasure(d, r, m)
  return { round = r, measure = m, start = Dance.measureStart(d, r, m), lead = Dance.leader(r),
    leadMoves = {}, counts = { [0] = 0, 0, 0, 0 } }
end

-- the lead's move at measure time t
function Dance.leadMove(d, ms, t, dir)
  local g, q = Dance.judge(d, t)
  local move = { grid = g, dir = dir, quality = q, t = t, id = ms.lead }
  ms.leadMoves[#ms.leadMoves + 1] = move
  ms.counts[ms.lead] = ms.counts[ms.lead] + 1
  d.points[ms.lead] = d.points[ms.lead] + Dance.POINTS[q]
  return move
end

-- a back dancer's move at measure time t
function Dance.copyMove(d, ms, id, t, dir)
  local g, q = Dance.judge(d, t)
  local wrong = false
  if q ~= Dance.MISS then
    local match
    for _, l in ipairs(ms.leadMoves) do if l.grid == g - d.steps then match = l end end
    if not match then q = Dance.MISS
    elseif match.dir ~= dir then q, wrong = Dance.MISS, true end
  end
  ms.counts[id] = ms.counts[id] + 1
  d.points[id] = d.points[id] + Dance.POINTS[q]
  return { grid = g, dir = dir, quality = q, wrong = wrong, t = t, id = id }
end

local function skillOf(d, id)
  local e = d.c.contestants[id]
  local o = e and e.opponent
  return math.max(0, math.min(3, tonumber(o and o.unk14) or 0))
end

-- ov17_0224E990: a computer lead's moves for one measure, { t, dir }
function Dance.npcLead(d, id)
  local rank = d.rank
  local slots = {}
  if rank <= 1 then
    for k = 1, d.steps / 2 - 1 do slots[#slots + 1] = k * 2 end
  else
    for k = 1, d.steps - 1 do slots[#slots + 1] = k end
  end
  local chosen, taken = {}, {}
  local tries = 0
  while #chosen < d.moves and tries < 400 do
    tries = tries + 1
    local g = slots[Dance.rand(d, #slots) + 1]
    local ok = not taken[g]
    if ok and rank >= 2 then
      if taken[g - 1] or taken[g + 1] then ok = false end
      if ok and g % 2 == 1 and Dance.rand(d, 256) < 128 then ok = false end
    end
    if ok and g * d.hs >= d.half - d.step / 4 then ok = false end
    if ok then taken[g] = true; chosen[#chosen + 1] = g end
  end
  table.sort(chosen)
  local j = ({ 1, 2, 3, 4 })[skillOf(d, id) + 1]
  j = ({ [0] = j * 2, j, math.floor(j / 2), math.floor(j / 3) })[rank]
  local limit = (d.layout == 0 and d.step / 4 or d.step / 6)
  local repeatPct = ({ [0] = 90, 40, 0, 0 })[rank]
  local out, last = {}, nil
  for i, g in ipairs(chosen) do
    local jitter = Dance.rand(d, 2 + j) - (1 + math.floor(j / 2))
    jitter = math.max(-(limit - 1), math.min(limit - 1, jitter))
    local dir
    if last and i < #chosen and Dance.rand(d, 100) < repeatPct then dir = last
    else dir = Dance.rand(d, 4) + 1 end
    out[#out + 1] = { t = math.max(0, g * d.hs + jitter), dir = dir }
    last = dir
  end
  return out
end

-- the skill's weak direction (ov17_0224ECC4)
Dance.WEAK = { [0] = Dance.JUMP, Dance.FRONT, Dance.RIGHT, Dance.LEFT }

-- ov17_0224EE90: a computer back dancer's copies of the lead's moves
function Dance.npcCopy(d, id, leadMoves)
  local skill, rank = skillOf(d, id), d.rank
  local scale = ({ [0] = 2, 2, 1.5, 1 })[rank]
  local j2 = math.floor(({ 1, 2, 3, 4 })[skill + 1] * scale)
  local out = {}
  for n, l in ipairs(leadMoves) do
    local prev = leadMoves[n - 1]
    local err = 0
    if l.dir == Dance.WEAK[skill] then err = err + 3 end
    if prev then
      if prev.dir ~= l.dir then err = err + 8 end
      if prev.grid % 2 ~= l.grid % 2 then err = err + 2 end
      if l.grid - prev.grid >= 8 then err = err + 5 end
    end
    err = math.floor(err * scale)
    local dir = l.dir
    if Dance.rand(d, 100) < j2 + err then
      dir = (l.dir + Dance.rand(d, 3)) % 4 + 1     -- one of the other three
    end
    local jitter = Dance.rand(d, 2 + j2) - (1 + math.floor(j2 / 2))
    out[#out + 1] = { t = (l.grid + d.steps) * d.hs + jitter, dir = dir }
  end
  return out
end

-- the scores, into the contest
function Dance.record(d)
  for id = 0, 3 do d.c.scores[id].dance = d.points[id] end
end

-- the standings after the Dance (unk_156): the Visual and the Dance points
-- scaled as the final scoring does, best first
function Dance.leading(d)
  local v = Contest.roundPoints(d.c, 0)
  local p = Contest.roundPoints(d.c, 1)
  local best, bestId = -1, 0
  for id = 0, 3 do
    local s = (v[id] or 0) + (p[id] or 0)
    if s > best then best, bestId = s, id end
  end
  return bestId
end

return Dance
