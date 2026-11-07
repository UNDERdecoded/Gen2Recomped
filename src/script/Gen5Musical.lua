-- src/script/Gen5Musical.lua -- THE POKEMON MUSICAL, RUN.
--
-- Nimbasa's Musical Theater (Z077; the receptionists are the shared file
-- 892, scripts 10440-10455) talks to the facility through these commands,
-- each read out of overlay 10 (scrcmd_musical.c):
--
--   0x167 <slot var, u8 mode>  mode 0 / 1: the musical itself -- dress-up,
--        the stage, the results (0x0215D34C -> musical_event.c); mode 2:
--        the Musical Photo saved last time
--   0x168 <slot var>   Dress Up alone (the changing room, the story's first
--        visit; 0x0215D468)
--   0x169 <u8 fn, arg, dest>  the queries (0x0215D504, a switch of 0x28)
--   0x16A <fan, u8 kind, dest> a fan in the lobby: 0 its sprite, 1 / 2 its
--        line without / with a gift, 3 its state, 4 its prop (0x0215D7D4)
--   0x16B <fn, a, b, dest>  the event's work and the wireless lounge
--        (0x0215DB38); 0x16C <prop> a prop into the Prop Case (0x0215D864);
--        0x16D <fan> the fan's gift handed over (0x0215DADC); 0x16E
--        <result, slot> choose the Pokemon (0x0215DB00)
--   0x05D <u8 kind, u8 buffer, value>  a Musical word into a string buffer
--        (0x0215D884): 1 / 8 a prop's name (bank 79 / 282), 3 / 4 a word of
--        bank 75, 7 the outfit's verdict ("cool", "cute" ... "balanced")
--
-- THE SAVE is the cartridge's block 0x2A (0x2A4 bytes; arm9 0x0200A544
-- makes it), kept as save.gen5Musical:
--   +0x1B0  the last outfit (8 x 6 bytes, byte 0 = 0x0A for empty)
--   +0x1E0  ten fans { u8 sprite type (4 = none), u8 state, u16 prop }
--   +0x252  musicals played, +0x254 musicals won, +0x256 points earned
--   +0x258  the props owned (one bit each, 100), +0x278 the new ones
--   +0x298  the last outfit's props by type (4 bytes), +0x29C the last
--           score, +0x29D the show chosen, +0x29E a downloaded show
--
-- THE SCORE is musical_program.c's: the show's weights (/a/1/1/x member 0,
-- [1..4]) plus a bonus pool dealt out in 5s at random (0x02157028), then
-- each type's weight divided among every prop of that type on stage
-- (0x02157174: a prop of a type nobody else wears is worth the whole
-- weight), each performer scoring its own props; a prop held in hand and
-- used on stage scores its value again (ov132 0x021F99F4). The fans
-- (0x02156530): the points earned so far plus this show's against the
-- thresholds 12000 .. 0 give 0..10 fans, each with a (score)% chance of a
-- prop from the show's list the player lacks. The record (0x02156420):
-- played + 1, won + 1 when the player's score is the top one, the props
-- counted by type, the score added to the points.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}

M.TYPES = 4
M.FANS = 10
M.SLOTS = 9          -- ears L / R, head, eyes, face, body, waist, hand L / R
M.POSITIONS = { [0] = "ears", "ears", "head", "eyes", "face", "body", "waist", "hand", "hand" }
-- the position bit (props' mask, byte 6) of each slot
M.SLOT_BIT = { [0] = 0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x40 }

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return G4().valueOf(ctx, n) end
local function store(ctx, dest, value)
  dest = tonumber(dest)
  if dest and dest >= 0x4000 then G4().setVar(ctx.save, dest, math.floor(tonumber(value) or 0) % 65536) end
end
local function rand(n)
  n = math.max(1, math.floor(n))
  return (love and love.math and love.math.random(0, n - 1)) or math.random(0, n - 1)
end

function M.rec(data)
  local r = data and data.constants and data.constants.gen5Musical
  return type(r) == "table" and r or nil
end

-- ------------------------------------------------------------- the save --

function M.save(save)
  save.gen5Musical = save.gen5Musical or {}
  local s = save.gen5Musical
  if not s.made then
    -- arm9 0x0200A544: fans none, the fifteen props a new save owns
    s.made = true
    s.props, s.newProps = s.props or {}, s.newProps or {}
    -- (Game was read as an undeclared global here, so it was always nil and
    -- the ROM's own start props were never used)
    local okG, Game = pcall(require, "src.core.Game")
    local rec = okG and type(Game) == "table" and Game.data and M.rec(Game.data)
    for _, p in ipairs(rec and rec.startProps or { 0x30, 0x46, 0x53, 0x4B, 0, 1, 0x0A, 0x1C, 8, 0x3B, 0x3F, 0x42, 0x10, 0x59, 0x4C }) do
      s.props[p] = true
    end
  end
  s.props, s.newProps = s.props or {}, s.newProps or {}
  s.fans = s.fans or {}
  for i = 0, M.FANS - 1 do s.fans[i] = s.fans[i] or { type = 4, state = 0, prop = 0 } end
  s.typeCounts = s.typeCounts or { [0] = 0, 0, 0, 0 }
  s.outfit = s.outfit or {}
  s.played, s.won, s.points = s.played or 0, s.won or 0, s.points or 0
  s.lastScore, s.show, s.dlShow = s.lastScore or 0, s.show or 0, s.dlShow or 0
  return s
end

function M.hasProp(save, p) return M.save(save).props[tonumber(p) or -1] == true end
function M.addProp(save, p)
  p = tonumber(p)
  if not p or p < 0 or p >= 100 then return end
  local s = M.save(save)
  s.props[p], s.newProps[p] = true, true
end
function M.propCount(save)
  local n = 0
  for p in pairs(M.save(save).props) do if p >= 0 and p < 100 then n = n + 1 end end
  return n
end

-- may this Pokemon play Dress Up? Any that is not an egg. READ: 0x16E
-- (ov10 0x0215A168) opens the party list (overlay 91, pokelist.c) in mode
-- 0x19; that mode's plate check (ov91 0x021B8392) asks ov112 0x021F6744,
-- which is `PP_Get(pp, 0xAA) != 1` and nothing else (0xAA taken as the egg
-- flag, INFERRED from the use). /a/0/4/8 is not the Musical's: field code
-- reads it (ov10 0x0216E280 opens arc 0x30); every species has a pose.
function M.eligible(data, mon)
  if not mon then return false end
  return not require("src.pokemon.Party").isEgg(mon)
end

-- ---------------------------------------------------------- the program --

-- 0x02157028: the show's program -- weights, the bonus pool dealt out, three
-- performers among those the points earned have unlocked
function M.program(data, showIndex, points)
  local rec = M.rec(data)
  local show = rec and rec.shows and (rec.shows[showIndex] or rec.shows[0])
  if not show then return nil end
  local prog = { show = show, index = show.index or showIndex, weights = {}, value = {} }
  for t = 0, 3 do prog.weights[t] = show.weights[t] or 0 end
  local pool = math.floor((show.bonus or 0) / 5)
  while pool > 0 do
    local t = rand(4)
    local n = math.min(pool, rand(3) + 1)
    prog.weights[t] = prog.weights[t] + n * 5
    pool = pool - n
  end
  local open = {}
  for k = 0, 5 do
    local p = show.performers[k]
    if p and (p.threshold or 0) <= (points or 0) then open[#open + 1] = k end
  end
  if #open < 3 then open = { 0, 1, 2 } end
  for _ = 1, 30 do
    local a, b = rand(#open) + 1, rand(#open) + 1
    open[a], open[b] = open[b], open[a]
  end
  prog.npcs = { open[1], open[2], open[3] }
  return prog
end

-- the program's type: the heaviest weight (0x021572C0, the first on a tie)
function M.programType(prog)
  local best, at = 0, 0
  for t = 0, 3 do if prog.weights[t] > best then best, at = prog.weights[t], t end end
  return at
end

local function propType(rec, id) local p = rec and rec.props and rec.props[id] return p and p.type or 0 end

-- 0x02157174: each type's weight shared among every prop of that type on
-- stage; each performer's points are its props' worth (a byte per type)
function M.score(data, prog, performers)
  local rec = M.rec(data)
  local total = { [0] = 0, 0, 0, 0 }
  for _, pf in ipairs(performers) do
    pf.counts = { [0] = 0, 0, 0, 0 }
    for _, item in pairs(pf.props) do
      if item and item.id then
        local t = propType(rec, item.id)
        pf.counts[t] = pf.counts[t] + 1
        total[t] = total[t] + 1
      end
    end
  end
  for t = 0, 3 do prog.value[t] = total[t] > 0 and math.floor(prog.weights[t] / total[t]) or 0 end
  for _, pf in ipairs(performers) do
    pf.points, pf.bonus = 0, pf.bonus or 0
    for t = 0, 3 do pf.points = pf.points + (prog.value[t] * pf.counts[t]) % 256 end
  end
end

-- ov132 0x021F99F4: an appeal with the prop in `slot` -- its value again
function M.appeal(data, prog, pf, slot)
  local item = pf.props[slot]
  if not (item and item.id) or pf.used[slot] then return 0 end
  pf.used[slot] = true
  local v = prog.value[propType(M.rec(data), item.id)] or 0
  pf.bonus = (pf.bonus or 0) + v
  return v
end

function M.total(pf) return math.min(255, (pf.points or 0) + (pf.bonus or 0)) end

-- the performers: the player's Pokemon (its outfit) and the show's three
function M.performers(data, prog, mon, outfit)
  local list = { { player = true, species = tonumber(mon and mon.species) or 0, mon = mon,
                   props = outfit or {}, used = {} } }
  for _, k in ipairs(prog.npcs) do
    local p = prog.show.performers[k]
    local props = {}
    for _, q in ipairs(p.props or {}) do
      if q.pos and q.pos >= 0 and q.pos < M.SLOTS then props[q.pos] = { id = q.id } end
    end
    list[#list + 1] = { species = p.species, personality = p.personality, nameId = p.name,
                        props = props, used = {}, npc = k }
  end
  return list
end

-- the ranking, best first (ties keep the lineup's order)
function M.rank(performers)
  local order = {}
  for i = 1, #performers do order[i] = i end
  table.sort(order, function(a, b)
    local ta, tb = M.total(performers[a]), M.total(performers[b])
    if ta ~= tb then return ta > tb end
    return a < b
  end)
  return order
end

-- 0x02156530: the fans, before the record takes this show's points
function M.makeFans(data, save, prog, player)
  local rec, s = M.rec(data), M.save(save)
  for i = 0, M.FANS - 1 do s.fans[i] = { type = 4, state = 0, prop = 0 } end
  local score = M.total(player)
  local total = (s.points or 0) + score
  local n = 0
  local th = rec and rec.fanThresholds
  for i = 0, 9 do
    if th and th[i] and th[i] <= total then n = 10 - i break end
  end
  local candidates = {}
  local gifts = rec and rec.fanGifts and rec.fanGifts[prog.index or 0]
  for _, p in ipairs(gifts or {}) do if not s.props[p] then candidates[#candidates + 1] = p end end
  local order = {}
  for i = 0, 9 do order[i + 1] = i end
  for _ = 1, 10 do
    for k = 1, 10 do
      local j = rand(10) + 1
      order[k], order[j] = order[j], order[k]
    end
  end
  local kind = M.programType(prog)
  for k = 1, n do
    local f = s.fans[order[k]]
    f.type = kind
    if rand(100) < score and #candidates > 0 then
      local j = rand(#candidates) + 1
      f.state, f.prop = 1, table.remove(candidates, j)
    end
  end
  Logger.info("bw musical: %d fan(s) at %d points (%d earned before)", n, total, s.points or 0)
  return n
end

-- 0x02156420: the record of the show
function M.record(data, save, player, top)
  local rec, s = M.rec(data), M.save(save)
  local score = M.total(player)
  s.played = math.min(0xFFFF, s.played + 1)
  if score == M.total(top) and score ~= 0 then s.won = math.min(0xFFFF, s.won + 1) end
  s.lastScore = score
  s.points = math.min(0xFFFF, s.points + score)
  s.typeCounts = { [0] = 0, 0, 0, 0 }
  s.outfit = {}
  for slot = 0, M.SLOTS - 1 do
    local item = player.props[slot]
    if item and item.id then
      local t = propType(rec, item.id)
      s.typeCounts[t] = s.typeCounts[t] + 1
      s.outfit[slot] = item.id
    end
  end
end

-- the outfit's verdict words (0x05D kind 7): the counts sorted, the top type
-- ("balanced" when the top three tie), then the next two
function M.verdict(save)
  local s = M.save(save)
  local c, t = {}, {}
  for i = 0, 3 do c[i + 1], t[i + 1] = s.typeCounts[i] or 0, i end
  for pass = 1, 3 do
    for i = 1, 4 - pass do
      if c[i] < c[i + 1] then c[i], c[i + 1] = c[i + 1], c[i]; t[i], t[i + 1] = t[i + 1], t[i] end
    end
  end
  local w = {}
  if c[1] == c[2] and c[1] == c[3] then w[1], w[2] = 9, 8
  else
    w[1] = 4 + t[1]
    w[2] = (c[2] == c[3]) and 8 or (4 + t[2])
  end
  if c[2] == c[4] then w[3] = 4 + t[2] elseif c[3] == c[4] then w[3] = 4 + t[3] else w[3] = 4 + t[4] end
  return w
end

-- ------------------------------------------------------------- commands --

local function word(data, n)
  local rec = M.rec(data)
  local s = rec and rec.words and rec.words[n]
  if not s then s = data and data.text and data.text[require("src.import.Gen5Text").label("system", 75, n)] end
  return s or ""
end
local function setBuffer(ctx, slot, text)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[(tonumber(slot) or 0) + 1] = text or ""
end

-- 0x05D <kind, buffer, value>
function Commands.g5_musical_word(ctx, kind, buffer, value)
  local data = ctx.game and ctx.game.data
  local rec = M.rec(data)
  kind = tonumber(kind) or 0
  local v = valueOf(ctx, value)
  if kind == 1 or kind == 8 then
    local p = rec and rec.props and rec.props[v]
    setBuffer(ctx, buffer, p and ((kind == 8 and p.nameA) or p.name) or "")
  elseif kind == 3 then setBuffer(ctx, buffer, word(data, v))
  elseif kind == 4 then setBuffer(ctx, buffer, word(data, v + 4))
  elseif kind == 7 then
    local w = M.verdict(ctx.save)
    for k = 1, 3 do setBuffer(ctx, k - 1, word(data, w[k])) end
  elseif kind == 0 then setBuffer(ctx, buffer, "")   -- a downloaded show's title: none here
  else
    -- 2 the show's name, 5 / 6 a performer's trainer / Pokemon (backstage;
    -- src/script/Gen5MusicalBackstage.lua) -- nobody outside a show
    setBuffer(ctx, buffer, require("src.script.Gen5MusicalBackstage").word(ctx, kind, v) or "")
  end
end

-- 0x169 <fn, arg, dest>
local Q = {}
M.Q = Q
Q[0x00] = function(ctx) return M.save(ctx.save).played end
Q[0x01] = function(ctx) return M.save(ctx.save).won end
Q[0x02] = function(ctx) return M.save(ctx.save).lastScore end
local function typeIndex(save, pick)
  local c = M.save(save).typeCounts
  return pick(c)
end
Q[0x03] = function(ctx) -- the type worn most (4 on a tie for the top)
  return typeIndex(ctx.save, function(c)
    local best, at = 0, 4
    for i = 0, 3 do
      if c[i] > best then best, at = c[i], i elseif c[i] == best then at = 4 end
    end
    return at
  end)
end
Q[0x04] = function(ctx) return M.save(ctx.save).show end
Q[0x05] = function(ctx, a) M.save(ctx.save).show = tonumber(a) or 0 return nil end
Q[0x06] = function(ctx) -- any prop worn last time?
  local c = M.save(ctx.save).typeCounts
  for i = 0, 3 do if (c[i] or 0) ~= 0 then return 1 end end
  return 0
end
Q[0x07] = function(ctx) return M.save(ctx.save).photo and 1 or 0 end
Q[0x08] = function(ctx) -- the type worn least (the last of a tie)
  return typeIndex(ctx.save, function(c)
    local low, at = 0xFF, 4
    for i = 0, 3 do if c[i] <= low then low, at = c[i], i end end
    return at
  end)
end
Q[0x09] = function(ctx) -- the type worn most (the first of a tie)
  return typeIndex(ctx.save, function(c)
    local best, at = 0, 4
    for i = 0, 3 do if c[i] > best then best, at = c[i], i end end
    return at
  end)
end
Q[0x0A] = function(ctx) -- the runner-up (ov10 0x0215D696, read literally)
  return typeIndex(ctx.save, function(c)
    local first, prev, second, best = 4, 0, 4, 0
    for i = 0, 3 do
      if c[i] > best then
        local r
        if prev == best then r = 4 else prev = best r = first end
        second, best, first = r, c[i], i
      end
    end
    return second
  end)
end
Q[0x0B] = function(ctx) -- Pokemon in the party that can play Dress Up
  local n = 0
  for _, mon in ipairs(ctx.save.party or {}) do if M.eligible(ctx.game.data, mon) then n = n + 1 end end
  return n
end
Q[0x0C] = function(ctx, a)
  local mon = (ctx.save.party or {})[(tonumber(a) or 0) + 1]
  return M.eligible(ctx.game.data, mon) and 1 or 0
end
Q[0x0D] = function(ctx) -- the last Dress Up wore something
  for _ in pairs(M.save(ctx.save).outfit or {}) do return 1 end
  return 0
end
Q[0x0E] = function(ctx) return M.save(ctx.save).dlShow == 1 and 1 or 0 end
Q[0x0F] = function(ctx, a) return M.hasProp(ctx.save, a) and 1 or 0 end
-- 0x1E-0x27: the last show's work (the lounge's results)
local function work(ctx) return ctx.game and ctx.game.gen5Musical end
Q[0x1E] = function(ctx) local w = work(ctx) return w and w.playerIndex or 0 end
Q[0x1F] = function(ctx)
  local w, best = work(ctx), 0
  for _, pf in ipairs(w and w.performers or {}) do best = math.max(best, M.total(pf)) end
  return best
end
Q[0x20] = function(ctx)
  local w, low = work(ctx), 0xFF
  for _, pf in ipairs(w and w.performers or {}) do low = math.min(low, M.total(pf)) end
  return low
end
Q[0x21] = function(ctx, a) local w = work(ctx) local pf = w and w.performers and w.performers[(tonumber(a) or 0) + 1] return pf and M.total(pf) or 0 end
Q[0x23] = function(ctx, a) local w = work(ctx) return w and w.lineup and w.lineup[tonumber(a) or 0] or 0 end
Q[0x22] = function() return nil end   -- 0x0215D7CE: nothing stored
Q[0x24] = function(ctx) local w = work(ctx) return w and w.prog and M.programType(w.prog) or 0 end
-- READ, ov10 0x0215D504 -> 0x0215699C / 0x021569A4 (the work's byte
-- +0x48 + a; a performer's four u16 at +0x4C). 0x25 <k>: the performer the
-- owner's review (Z078, member 156 S0707) speaks of k-th, counting 3 down
-- to 0 -- taken as the k-th place of the ranking (INFERRED: the writer of
-- +0x48 is not read). 0x26 <a>: performer a's type worn most, 4 on a tie
-- for the top
Q[0x25] = function(ctx, a)
  local w = work(ctx)
  local order = w and w.performers and M.rank(w.performers)
  return order and order[(tonumber(a) or 0) + 1] and order[(tonumber(a) or 0) + 1] - 1 or 0
end
Q[0x26] = function(ctx, a)
  local w = work(ctx)
  local pf = w and w.performers and w.performers[(tonumber(a) or 0) + 1]
  local c = pf and pf.counts
  if not c then return 4 end
  -- as written: a new top keeps the OLD top in the tie word, so "1" there
  -- (a tie, or a top of 1 overtaken) answers 4
  local best, at, flag = 0, 0, 0
  for t = 0, 3 do
    local n = c[t] or 0
    if best < n then flag, best, at = best, n, t elseif best == n then flag = 1 end
  end
  return flag == 1 and 4 or at
end
Q[0x27] = function(ctx, a) return require("src.script.Gen5MusicalBackstage").sprite(ctx, a) end

function Commands.g5_musical_query(ctx, fn, arg, dest)
  fn = tonumber(fn) or 0
  local q = Q[fn]
  local v
  if q then v = q(ctx, valueOf(ctx, arg)) else v = 0 end
  if os.getenv and os.getenv("BW_MUSICAL_TRACE") then
    print(("[musical] 0x169 fn 0x%02X(%s) -> %s"):format(fn, tostring(valueOf(ctx, arg)), tostring(v)))
  end
  if v ~= nil then store(ctx, dest, v) end
end

-- 0x16A <fan, kind, dest>
function Commands.g5_musical_fan(ctx, fan, kind, dest)
  local s = M.save(ctx.save)
  local rec = M.rec(ctx.game.data)
  local i = valueOf(ctx, fan)
  local f = s.fans[i] or { type = 4, state = 0, prop = 0 }
  kind = tonumber(kind) or 0
  local v
  if kind == 0 then
    local sprites = (rec and rec.fanSprite) or { [0] = 0x18, 0x0F, 0x2D, 0x0C }
    v = sprites[f.type] or 0
  elseif kind == 1 then v = i + 5
  elseif kind == 2 then v = i + 15
  elseif kind == 3 then v = f.state
  elseif kind == 4 then v = f.prop end
  store(ctx, dest, v or 0)
end
-- 0x16D <fan>: the gift handed over
function Commands.g5_musical_fan_done(ctx, fan)
  local s = M.save(ctx.save)
  local f = s.fans[valueOf(ctx, fan)]
  if f then f.state = 0 end
end
-- 0x16C <prop>
function Commands.g5_musical_add_prop(ctx, prop) M.addProp(ctx.save, valueOf(ctx, prop)) end

-- 0x16E <result var, slot var>: choose the Pokemon
function Commands.g5_musical_pick(ctx, resultVar, slotVar)
  local runner = ctx.runner
  local data = ctx.game.data
  if os.getenv and os.getenv("BW_MUSICAL_AUTOPICK") then
    for i, mon in ipairs(ctx.save.party or {}) do
      if M.eligible(data, mon) then store(ctx, resultVar, 1) store(ctx, slotVar, i - 1) return end
    end
    store(ctx, resultVar, 0)
    return
  end
  local banned = {}
  for _, mon in ipairs(ctx.save.party or {}) do
    if not M.eligible(data, mon) then banned[tonumber(mon.species) or 0] = true end
  end
  local PM = require("src.ui.Gen4PartyMenu")
  local done = false
  ctx.game.stack:push(PM.new(ctx.game, { select = {
    count = 1, banlist = banned,
    onDone = function(slots)
      if type(slots) == "table" and slots[1] then
        store(ctx, resultVar, 1)
        store(ctx, slotVar, slots[1] - 1)
      else
        store(ctx, resultVar, 0)
      end
      done = true
      if runner then runner:resume() end
    end,
  } }))
  if runner and not done then runner:yield() end
end

-- the event's work (0x16B 0 makes it, 1 frees it)
function Commands.g5_musical_event(ctx, fn, a, b, dest)
  fn = tonumber(fn) or 0
  local v
  if fn == 0x00 then ctx.game.gen5Musical = ctx.game.gen5Musical or {}
  elseif fn == 0x01 then ctx.game.gen5Musical = nil
  elseif fn == 0x12 then
    -- the lobby asks it (M0892 S06AA / S06F4, arg 0 / 1) and reads 5 / 6:
    -- the wireless lounge's state -- nobody here (the photo is kept by
    -- g5_musical_show)
    v = 0
  elseif fn == 0x0E or fn == 0x11 then
    require("src.script.Gen5MusicalBackstage").event(ctx, fn, valueOf(ctx, a))
  elseif fn == 0x13 or fn == 0x14 then v = 0   -- the wireless lounge: nobody
  elseif fn == 0x15 then v = 0
  end
  if v ~= nil then store(ctx, dest, v) end
  local _ = a or b
end

-- the screens, pushed and waited for
local function runScreen(ctx, screen)
  return M.runScreen(ctx, screen)
end
function M.runScreen(ctx, screen)
  local runner = ctx.runner
  local done = false
  local onDone = screen.onDone
  screen.onDone = function(...)
    done = true
    if onDone then onDone(...) end
    if runner then runner:resume() end
  end
  ctx.game.stack:push(screen)
  if runner and not done then runner:yield() end
end

-- 0x168 <slot var>: Dress Up alone
function Commands.g5_musical_dressup(ctx, slotVar)
  local slot = valueOf(ctx, slotVar)
  local mon = (ctx.save.party or {})[slot + 1]
  local D = require("src.ui.Gen5MusicalDressUp")
  local s = M.save(ctx.save)
  runScreen(ctx, D.new(ctx.game, { mon = mon, startOnFinish = true, onDone = function(outfit)
    s.outfit = {}
    for k, item in pairs(outfit or {}) do if item and item.id then s.outfit[k] = item.id end end
    Logger.info("bw musical: Dress Up done, %d prop(s)", (function() local n = 0 for _ in pairs(s.outfit) do n = n + 1 end return n end)())
  end }))
end

-- AFTER THE SHOW the cartridge plays the curtain call in Z078 (zone 78's
-- entry 5: the performers walk out, the owner's word on the scores, then the
-- lobby's fans: `16A <i, 0>` and flag 670..674 / 752..756 set for an empty
-- seat, cleared for a fan; flag 326 cleared so the receptionist has her say;
-- flag 327 only after a wireless show). The walk-out is not played here; its
-- effect on the save is.
M.FAN_FLAGS = { [0] = 670, 671, 672, 673, 674, 752, 753, 754, 755, 756 }
function M.afterShow(ctx)
  local s = M.save(ctx.save)
  for i = 0, M.FANS - 1 do
    local name = ("FLAG_G4_%04X"):format(M.FAN_FLAGS[i])
    if (s.fans[i].type or 4) >= 4 then Commands.set_flag(ctx, name) else Commands.clear_flag(ctx, name) end
  end
  Commands.clear_flag(ctx, ("FLAG_G4_%04X"):format(326))
  local ow = ctx.overworld
  if ow and ow.syncObjectVisibility then pcall(ow.syncObjectVisibility, ow) end
end

-- the musical app's photo prompt (system bank 78 #3, YES / NO)
function M.askPhoto(ctx, photo)
  local s = M.save(ctx.save)
  if os.getenv and os.getenv("BW_MUSICAL_PHOTO") then
    if os.getenv("BW_MUSICAL_PHOTO") ~= "no" then s.photo = photo end
    return
  end
  local game, runner = ctx.game, ctx.runner
  local text = game and game.data and game.data.text
    and game.data.text[require("src.import.Gen5Text").label("system", 78, 3)]
  if not (game and game.stack and type(text) == "string") then s.photo = photo return end
  local done = false
  game.stack:push(require("src.render.TextBox").new(game, text, nil, { choice = function(yes)
    if yes then s.photo = photo end
    done = true
    if runner then runner:resume() end
  end }))
  if runner and not done then runner:yield() end
end

-- 0x167 <slot var, mode>
function Commands.g5_musical_show(ctx, slotVar, mode)
  mode = tonumber(mode) or 0
  local data, save = ctx.game.data, ctx.save
  local s = M.save(save)
  if mode == 2 then
    if s.photo then
      local St = require("src.ui.Gen5MusicalStage")
      runScreen(ctx, St.photo(ctx.game, s.photo))
    end
    return
  end
  local slot = valueOf(ctx, slotVar)
  local mon = (save.party or {})[slot + 1]
  local prog = M.program(data, s.show or 0, s.points)
  if not (prog and mon) then
    Logger.warn("bw musical: no show to play (program %s, Pokemon %s)", tostring(prog ~= nil), tostring(mon ~= nil))
    return
  end
  local w = ctx.game.gen5Musical or {}
  ctx.game.gen5Musical = w
  w.prog = prog
  -- READ (ov10 0x02155A98, the event's work): the program and the lineup are
  -- made before anything is shown; the Dress Up comes later, backstage
  local performers = M.performers(data, prog, mon, {})
  -- the lineup: the four in a random order (ov10 0x02155BA2)
  local lineup = { 1, 2, 3, 4 }
  for _ = 1, 10 do
    for k = 1, 4 do local j = rand(4) + 1 lineup[k], lineup[j] = lineup[j], lineup[k] end
  end
  local ordered = {}
  for k = 1, 4 do ordered[k] = performers[lineup[k]] end
  w.performers, w.lineup = ordered, {}
  for k = 1, 4 do
    w.lineup[k - 1] = k - 1
    if ordered[k].player then w.playerIndex = k - 1 end
  end
  -- BACKSTAGE (zone 78; src/script/Gen5MusicalBackstage.lua, the event's
  -- states READ): the welcome, the Dress Up, the call to the stage, the
  -- stage, the review, back to the lobby -- when the cache has Z078's scripts
  if require("src.script.Gen5MusicalBackstage").start(ctx, w) then return end
  local D = require("src.ui.Gen5MusicalDressUp")
  local outfit
  runScreen(ctx, D.new(ctx.game, { mon = mon, show = prog.show, onDone = function(o) outfit = o end }))
  M.dress(w, outfit)
  M.score(data, prog, ordered)
  local St = require("src.ui.Gen5MusicalStage")
  runScreen(ctx, St.new(ctx.game, { prog = prog, performers = ordered }))
  M.finishShow(ctx, w)
end

-- the Dress Up's outfit onto the player's performer
function M.dress(w, outfit)
  for _, pf in ipairs(w.performers or {}) do
    if pf.player then pf.props, pf.used = outfit or {}, {} end
  end
end

-- after the stage: the fans, the record, the photo (both ways of getting
-- there: straight from 0x167, or from the backstage's 0x16B 0x11)
function M.finishShow(ctx, w)
  local data, save = ctx.game.data, ctx.save
  local s = M.save(save)
  local prog, ordered = w.prog, w.performers
  local order = M.rank(ordered)
  local player = ordered[(w.playerIndex or 0) + 1]
  local top = ordered[order[1]]
  M.makeFans(data, save, prog, player)
  M.record(data, save, player, top)
  w.photo = { show = prog.index, species = player.species, outfit = s.outfit, score = M.total(player) }
  -- the photo frame by the lobby's door (sign 1, M0154 S0359: 0x169 7, then
  -- 0x167 mode 2) shows "the Musical Photo saved from last time". No
  -- script stores one -- the lobby's only 0x16B 0x12 calls read the
  -- wireless lounge (5 / 6) -- so the musical app asks, in its own system
  -- bank 78: #3 "Do you want to display your Musical Photo in the Musical
  -- Theater?" #4 YES / #5 NO. READ: overlay 112 opens bank 78 (0x021F46F4),
  -- prints #3 in state 1 when its work +0xC is 1 (0x021F438A). +0xC is the
  -- app's first launch parameter (init 0x021F4284 from 0x021F391E): mode 1
  -- asks, any other mode only shows the photo (the lobby frame); which
  -- launcher passes 1 is not traced -- taken as the show's end. YES copies the
  -- 0x1B0-byte photo into the save (0x021F43D0); NO keeps the old one
  M.askPhoto(ctx, w.photo)
  M.afterShow(ctx)
  local parts = {}
  for k, pf in ipairs(ordered) do parts[k] = ("%s%d:%d+%d"):format(pf.player and "*" or "", pf.species, pf.points or 0, pf.bonus or 0) end
  Logger.info("bw musical: show %d (weights %d/%d/%d/%d) -- %s; played %d, won %d, points %d",
    prog.index, prog.weights[0], prog.weights[1], prog.weights[2], prog.weights[3], table.concat(parts, " "),
    s.played, s.won, s.points)
  if os.getenv and os.getenv("BW_MUSICAL_TRACE") then
    print(("[musical] show %d result %s"):format(prog.index, table.concat(parts, " ")))
  end
end

for _, name in ipairs({ "g5_musical_show", "g5_musical_dressup", "g5_musical_pick", "g5_musical_event" }) do
  Commands.meta = Commands.meta or {}
  Commands.meta[name] = { foreground = true, blocking = true }
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwmusicalshow = function(ins, s) emit(s, { "g5_musical_show", ins.args[1], ins.args[2] }) end
  L.bwmusicaldressup = function(ins, s) emit(s, { "g5_musical_dressup", ins.args[1] }) end
  L.bwmusicalquery = function(ins, s) emit(s, { "g5_musical_query", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwmusicalfan = function(ins, s) emit(s, { "g5_musical_fan", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwmusicalevent = function(ins, s) emit(s, { "g5_musical_event", ins.args[1], ins.args[2], ins.args[3], ins.args[4] }) end
  L.bwmusicaladdprop = function(ins, s) emit(s, { "g5_musical_add_prop", ins.args[1] }) end
  L.bwmusicalfandone = function(ins, s) emit(s, { "g5_musical_fan_done", ins.args[1] }) end
  L.bwmusicalpick = function(ins, s) emit(s, { "g5_musical_pick", ins.args[1], ins.args[2] }) end
  L.bwmusicalword = function(ins, s) emit(s, { "g5_musical_word", ins.args[1], ins.args[2], ins.args[3] }) end
end

return M
