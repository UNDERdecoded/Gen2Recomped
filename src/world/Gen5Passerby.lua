-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PASSERBY ANALYTICS (Castelia, Z042, member 84): the survey requests.
--
-- On the cartridge the HQ hands out survey REQUESTS whose answers come from
-- the people the player passes with the C-Gear's tag mode. Offline nobody is
-- passed, so no answer is ever counted -- but the HQ's scripts still ask the
-- save what request is running, how it stands and how long it has left, and
-- every one of those questions is answered here the way the cartridge
-- answers them for a player who has passed nobody. The tables (requests,
-- questions, answers) are src/import/Gen5Passerby.lua's.
--
-- THE SAVE (READ FROM CODE, arm9; save block 0x34 via 0x0200C0F0, block 0x3F
-- via 0x0200E394):
--   block 0x34 +0x44 u8   the HQ's rank (0..5)
--              +0x46 u8   the running request (0 none)
--              +0x47 u8[3] its questions (0xFF none)
--              +0x4A u16[3] answers counted for them while it runs
--              +0x50 u64  when it started (RTC seconds)
--              +0x18 / +0x1C u32  two lifetime tallies (99,999 at most)
--   block 0x3F +q*2 u16 / +0xDC+q*4 u32  answers to question q today / ever
--              +0x3C+i u8 / +0x154+i*2 u16  each answer's today / ever
-- THE COMMANDS (READ FROM CODE, ov10 unless noted):
--   0x210 <id, q1, q2, q3>  start a request: id, questions, counts 0, the
--         start time (0x0216B63C)
--   0x211                   end it: id 0, questions 0xFF (0x0216B6DC)
--   0x212 <dest>            the running request (0x0216B578)
--   0x213 <d1, d2, d3>      its three questions (0x0216B5AC)
--   0x214 <q, dest>         question q's most given answer (today + ever,
--         the first of equals; 0x0216B720)
--   0x215 <id, dest>        a request's standing (0x0216B81C):
--         kind 0: 1 when every question has `target` answers ever, else 2
--         kind 1, running: 3 while inside its hours; then 1 when every
--                 question got an answer during it, else 4
--         kind 1, not running: 1 when every question is at 999,999, else 3
--   0x216 <dest>            what is left of the running one: kind 0 the
--         target minus the fewest answers, kind 1 the hours left
--   0x217 <dest>            hours since it started (24 at most; 0x0216BB18)
--   0x21A / 0x21B <slot>    the +0x1C / +0x18 tally into a string slot
--         (ov21 0x021AFC38 / 0x021AFC88)
--   0x21E <dest>            the rank; 0x21F the rank up one (to 5 at most)
--   0x063 <slot, value>     answer <value>'s name (system bank 0) into a
--         string slot (ov21 0x021AFB90 -> 0x0201F1B0)
--   0x218 / 0x219 <dest>    the C-Gear greeting / thanks phrase typed on the
--         keyboard (ov21 0x021CD2A4, mode 5 / 6: overlay 194, the naming
--         keyboard, prompt bank 81 #5 / #6, eight characters, the current
--         phrase from block 0x34 +0x20 / +0x32); dest 1 when it was entered,
--         0 when cancelled, and an entered phrase is saved (0x021CD3A4)
--   0x21C <question, answer> the player's own answer to a survey question
--         (ov10 0x0216B7B0 -> block 0x3F +0xD2, bit-packed, 0x0200E3E8)
-- NOT PORTED: 0x21D runs an app (0x021670F8) that nothing waits a value
-- from -- skipped. INFERRED: this port's keyboard has no cancel, so an empty
-- phrase or the old one unchanged counts as cancelled.
-- INFERRED: offline every tally stays 0 (nothing is passed); time is the
-- host clock's seconds.

local M = {}

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local function tables(game)
  local c = game and game.data and game.data.constants
  return c and c.gen5Passerby
end

function M.save(save)
  save.gen5Passerby = save.gen5Passerby or { rank = 0, request = 0, q = { 255, 255, 255 },
    counts = { 0, 0, 0 }, start = 0, tally18 = 0, tally1C = 0 }
  return save.gen5Passerby
end

-- answers to question q today / ever (none offline)
function M.questionToday(p, q) return p.today and p.today[q] or 0 end
function M.questionEver(p, q) return p.ever and p.ever[q] or 0 end
function M.answerTotal(p, q, a) return (p.answers and p.answers[q] and p.answers[q][a]) or 0 end

function M.questionTotal(p, q)
  return math.min(999999, M.questionToday(p, q) + M.questionEver(p, q))
end

function M.now() return os.time() end

-- hours since the running request started (0x0216BB18)
function M.elapsed(p)
  if (p.request or 0) == 0 then return 0 end
  local d = M.now() - (p.start or 0)
  if d < 0 then d = 0 end
  if d >= 86400 then return 24 end
  return math.floor(d / 3600)
end

function M.status(game, p, id)
  local t = tables(game)
  local r = t and t.requests and (t.requests[id] or t.requests[tostring(id)])
  if not r then return 0 end
  if r.kind == 0 then
    for k = 1, r.n do if M.questionTotal(p, r.q[k]) < r.target then return 2 end end
    return 1
  elseif r.kind == 1 then
    if id == p.request then
      if (r.hours or 0) > M.elapsed(p) then return 3 end
      for k = 1, r.n do if (p.counts[k] or 0) == 0 then return 4 end end
      return 1
    end
    for k = 1, r.n do if M.questionTotal(p, r.q[k]) < 999999 then return 3 end end
    return 1
  end
  return 0
end

function M.remaining(game, p)
  local t = tables(game)
  local r = t and t.requests and (t.requests[p.request] or t.requests[tostring(p.request)])
  if not r then return 0 end
  if r.kind == 0 then
    local least = 0xF694E
    for k = 1, r.n do least = math.min(least, M.questionTotal(p, r.q[k])) end
    return (r.target - least) % 65536
  end
  return math.max(0, (r.hours or 0) - M.elapsed(p))
end

function M.topAnswer(game, p, q)
  local t = tables(game)
  local ids = t and t.questions and (t.questions[q] or t.questions[tostring(q)])
  if not ids then return 0 end
  local best, which = -1, 0
  for i, a in ipairs(ids) do
    local v = M.answerTotal(p, q, i)
    if v > best then best, which = v, a end
  end
  return which
end

local function G4() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end
local function set(ctx, dest, v) G4().setVar(ctx.save, dest, math.floor(v or 0) % 65536) end
local function buffer(ctx, slot, text)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[(tonumber(slot) or 0) + 1] = text or ""
end

function Commands.g5_passerby_start(ctx, id, q1, q2, q3)
  local p = M.save(ctx.save)
  p.request = val(ctx, id) % 256
  p.q = { val(ctx, q1) % 256, val(ctx, q2) % 256, val(ctx, q3) % 256 }
  p.counts = { 0, 0, 0 }
  p.start = M.now()
end
function Commands.g5_passerby_end(ctx)
  local p = M.save(ctx.save)
  p.request, p.q = 0, { 255, 255, 255 }
end
function Commands.g5_passerby_request(ctx, dest) set(ctx, dest, M.save(ctx.save).request) end
function Commands.g5_passerby_questions(ctx, d1, d2, d3)
  local p = M.save(ctx.save)
  set(ctx, d1, p.q[1]); set(ctx, d2, p.q[2]); set(ctx, d3, p.q[3])
end
function Commands.g5_passerby_top_answer(ctx, q, dest)
  set(ctx, dest, M.topAnswer(ctx.game, M.save(ctx.save), val(ctx, q)))
end
function Commands.g5_passerby_status(ctx, id, dest)
  set(ctx, dest, M.status(ctx.game, M.save(ctx.save), val(ctx, id) % 256))
end
function Commands.g5_passerby_remaining(ctx, dest) set(ctx, dest, M.remaining(ctx.game, M.save(ctx.save))) end
function Commands.g5_passerby_elapsed(ctx, dest) set(ctx, dest, M.elapsed(M.save(ctx.save))) end
function Commands.g5_passerby_tally(ctx, slot, which)
  local p = M.save(ctx.save)
  buffer(ctx, slot, tostring(which == 0x18 and p.tally18 or p.tally1C or 0))
end
function Commands.g5_passerby_rank(ctx, dest) set(ctx, dest, M.save(ctx.save).rank or 0) end
function Commands.g5_passerby_rank_up(ctx)
  local p = M.save(ctx.save)
  if (p.rank or 0) < 5 then p.rank = (p.rank or 0) + 1 end
end
M.PHRASE = { [5] = { key = "greeting", prompt = 5 }, [6] = { key = "thanks", prompt = 6 } }
M.PHRASE_LEN = 8
function Commands.g5_passerby_word(ctx, dest, mode)
  local game = ctx.game
  local spec = M.PHRASE[tonumber(mode) or 5] or M.PHRASE[5]
  local p = M.save(ctx.save)
  set(ctx, dest, 0)
  if not (game and game.stack) then return end
  local okN, Naming = pcall(require, "src.ui.Gen5NamingScreen")
  if not okN then return end
  local data = game.data
  local title = data and data.text and data.text[require("src.import.Gen5Text").label("system", 81, spec.prompt)]
  local runner = ctx.runner
  local old = p[spec.key] or ""
  game.stack:push(Naming.new(game, { title = title, maxLen = M.PHRASE_LEN, default = old,
    onDone = function(text)
      if type(text) == "string" and text ~= "" and text ~= old then
        p[spec.key] = text
        set(ctx, dest, 1)
      end
      if runner then runner:resume() end
    end }))
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g5_passerby_word = { blocking = true, foreground = true }
function Commands.g5_passerby_answer(ctx, q, answer)
  local p = M.save(ctx.save)
  p.own = p.own or {}
  p.own[val(ctx, q) % 256] = val(ctx, answer)
end
function Commands.g5_answer_name(ctx, slot, value)
  local v = val(ctx, value) % 256
  local text = ""
  if v <= 0x91 then
    local data = ctx.game and ctx.game.data
    text = data and data.text and data.text[require("src.import.Gen5Text").label("system", 0, v)] or ""
  end
  buffer(ctx, slot, text)
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  local function a(ins, k) return ins.args[k] end
  L.bwpasserbystart = L.bwpasserbystart or function(ins, s) emit(s, { "g5_passerby_start", a(ins, 1), a(ins, 2), a(ins, 3), a(ins, 4) }) end
  L.bwpasserbyend = L.bwpasserbyend or function(_, s) emit(s, { "g5_passerby_end" }) end
  L.bwpasserbyrequest = L.bwpasserbyrequest or function(ins, s) emit(s, { "g5_passerby_request", a(ins, 1) }) end
  L.bwpasserbyquestions = L.bwpasserbyquestions or function(ins, s) emit(s, { "g5_passerby_questions", a(ins, 1), a(ins, 2), a(ins, 3) }) end
  L.bwpasserbytopanswer = L.bwpasserbytopanswer or function(ins, s) emit(s, { "g5_passerby_top_answer", a(ins, 1), a(ins, 2) }) end
  L.bwpasserbystatus = L.bwpasserbystatus or function(ins, s) emit(s, { "g5_passerby_status", a(ins, 1), a(ins, 2) }) end
  L.bwpasserbyremaining = L.bwpasserbyremaining or function(ins, s) emit(s, { "g5_passerby_remaining", a(ins, 1) }) end
  L.bwpasserbyelapsed = L.bwpasserbyelapsed or function(ins, s) emit(s, { "g5_passerby_elapsed", a(ins, 1) }) end
  L.bwpasserbytally1c = L.bwpasserbytally1c or function(ins, s) emit(s, { "g5_passerby_tally", a(ins, 1), 0x1C }) end
  L.bwpasserbytally18 = L.bwpasserbytally18 or function(ins, s) emit(s, { "g5_passerby_tally", a(ins, 1), 0x18 }) end
  L.bwpasserbyrank = L.bwpasserbyrank or function(ins, s) emit(s, { "g5_passerby_rank", a(ins, 1) }) end
  L.bwpasserbyrankup = L.bwpasserbyrankup or function(_, s) emit(s, { "g5_passerby_rank_up" }) end
  L.bwpasserbyword = L.bwpasserbyword or function(ins, s)
    emit(s, { "g5_passerby_word", a(ins, 1), ins.op == 0x219 and 6 or 5 })
  end
  L.bwpasserbyanswer = L.bwpasserbyanswer or function(ins, s) emit(s, { "g5_passerby_answer", a(ins, 1), a(ins, 2) }) end
  L.bwanswername = L.bwanswername or function(ins, s) emit(s, { "g5_answer_name", a(ins, 1), a(ins, 2) }) end
end

return M
