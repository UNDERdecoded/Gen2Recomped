-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ROYAL UNOVA (Z052, scripts member 104): Castelia's evening cruise.
-- Everything below is READ FROM CODE in Black unless it says otherwise.
--
-- THE CRUISE'S WORK (ov21 0x021C8608, 0x1B8 bytes, made by script op 0x1A5
-- when the field has none and freed by 0x1A6):
--   +0   pending horn        +4 s16 the clock in field frames
--   +6   trainers today      +8 segments done
--   +0x0C + 0x1C * room      fifteen cabins: { index in its kind, trainer,
--                            sprite, kind (0 trainer, 1 talker, 2 sleeper),
--                            message 0, message 1, beaten }
--   +0x1B0..+0x1B3           trainers in the rooms whose side / door bits
--                            (the 15 x { u32, u32 } table ov36 0x021F3AD4)
--                            are 0 / 1 / 0 / 1
--   +0x1B4                   the clock stopped (0x1AC)
--
-- THE CABINS (ov36 0x021F36C0, loaded for the call): the weekday picks how
-- many trainers sail -- Sunday 7, Monday 4, Tuesday 3, Wednesday 4, Thursday
-- 5, Friday 4, Saturday 6 -- and the cartridge's random draw (0x020056EC)
-- picks which of the ten trainers (table 0x021F3B4C: sprite, trainer,
-- before / after lines), which two of five sleepers (0x021F3A98) and which
-- of the fifteen talkers (0x021F3BEC) fill which cabin. The cabin order is
-- 0x021F3980's: one of rooms 9..14 first, then one of 4..8 / 13 / 14 or of
-- 0..3 / 9..12 (chosen by the side bit of the table row the FIRST draw's
-- index names -- the index, not the room, as the cartridge has it), then the
-- other thirteen in random order; the trainers take the first N.
--
-- THE CLOCK (ov21 0x021C868C from the field's event check, so it runs while
-- the player is free): one tick a frame unless stopped; every 1350 frames a
-- segment ends -- the horn (SE 0x6DD, 0x021C8660) and the count goes up --
-- and once 5400 have passed with four segments done the field runs the
-- zone's script 1 ("This cruise ship will arrive in Castelia City shortly").
-- The port counts its own field frames (60 a second) for the cartridge's.
--
-- The work is RAM on the cartridge and here: it is kept on the Game table,
-- not in the save.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

M.SEGMENT, M.SEGMENTS, M.HORN, M.ZONE = 1350, 4, 0x6DD, 52
M.TRAINERS_BY_WEEKDAY = { [0] = 7, 4, 3, 4, 5, 4, 6 }
-- ov36 0x021F3AD4: per room { u32 a, u32 b } (the +0x1B0.. counters)
M.ROOMS = { [0] = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 1, 0 }, { 1, 0 }, { 1, 0 }, { 1, 0 },
            { 1, 0 }, { 0, 1 }, { 0, 1 }, { 0, 1 }, { 0, 1 }, { 1, 1 }, { 1, 1 } }
M.FIRST = { [0] = 9, 10, 11, 12, 13, 14 }                  -- 0x021F3A7C
M.SECOND_A = { [0] = 4, 5, 6, 7, 8, 13, 14 }               -- 0x021F3A82
M.SECOND_B = { [0] = 0, 1, 2, 3, 9, 10, 11, 12 }           -- 0x021F3A90
-- 0x021F3B4C: { sprite, trainer, message 0, message 1 }
M.TRAINERS = { [0] = { 52, 169, 17, 18 }, { 30, 206, 21, 22 }, { 31, 205, 25, 26 }, { 11, 146, 29, 30 },
               { 15, 207, 34, 35 }, { 13, 208, 38, 39 }, { 17, 209, 42, 43 }, { 44, 211, 47, 48 },
               { 45, 210, 52, 53 }, { 65, 543, 57, 58 } }
-- 0x021F3A98: { sprite, message 0, message 1 } (kind 2)
M.SLEEPERS = { [0] = { 52, 15, 16 }, { 15, 32, 33 }, { 44, 45, 46 }, { 45, 50, 51 }, { 20, 55, 56 } }
-- 0x021F3BEC: { sprite, message 0, message 1 } (kind 1)
M.TALKERS = { [0] = { 52, 14, 14 }, { 30, 19, 19 }, { 30, 20, 20 }, { 31, 23, 23 }, { 31, 24, 24 },
              { 11, 27, 27 }, { 11, 28, 28 }, { 15, 31, 31 }, { 13, 36, 36 }, { 13, 37, 37 },
              { 17, 40, 40 }, { 17, 41, 41 }, { 44, 44, 44 }, { 45, 49, 49 }, { 20, 54, 54 } }

local function Game() return package.loaded["src.core.Game"] end
local function rand(n) return (n and n > 0) and math.random(0, n - 1) or 0 end
local function G4() return require("src.script.Gen4Commands") end

-- 0x021F38AC: k distinct of 0..n-1 (a swap-remove draw)
local function pick(n, k)
  local pool, out = {}, {}
  for i = 0, n - 1 do pool[i] = i end
  for i = 0, k - 1 do
    local r = rand(n)
    out[i] = pool[r]
    pool[r] = pool[n - 1]
    n = n - 1
  end
  return out
end

-- 0x021F3980: the fifteen cabins in the order they are filled
local function roomOrder()
  local pool, last = {}, 14
  for i = 0, 14 do pool[i] = i end
  local function take(room)
    for i = 0, last do
      if pool[i] == room then pool[i] = pool[last]; last = last - 1; return true end
    end
    return false
  end
  local order = {}
  local x = rand(6)
  local first = M.FIRST[x]
  take(first)
  order[0] = first
  local second
  if M.ROOMS[x][1] == 0 then second = M.SECOND_A[rand(7)] else second = M.SECOND_B[rand(8)] end
  take(second)
  order[1] = second
  local left = 13
  for i = 0, left - 1 do
    local r = rand(left - i)
    order[2 + i] = pool[r]
    pool[r] = pool[last]; last = last - 1
  end
  return order
end

function M.weekday()
  local okS, St = pcall(require, "src.script.Gen5Stadium")
  local t = okS and St.clock and St.clock() or os.date("*t")
  return ((t.wday or 1) - 1) % 7
end

-- ov21 0x021C8608 + ov36 0x021F36C0
function M.new(weekday)
  local n = M.TRAINERS_BY_WEEKDAY[weekday or M.weekday()] or 0
  local s = { pending = 0, clock = 0, trainers = n, segments = 0, stopped = false,
              counts = { [0] = 0, 0, 0, 0 }, rooms = {} }
  local order = roomOrder()
  local who = pick(10, n)
  local sleepers = pick(5, 2)
  local talkers = pick(15, 15 - (n + 2))
  for i = 0, n - 1 do
    local room = order[i]
    local r = M.ROOMS[room]
    if r[1] == 0 then s.counts[0] = s.counts[0] + 1 else s.counts[1] = s.counts[1] + 1 end
    if r[2] == 0 then s.counts[2] = s.counts[2] + 1 else s.counts[3] = s.counts[3] + 1 end
  end
  local k = 0
  for i = 0, n - 1 do
    local t = M.TRAINERS[who[i]]
    s.rooms[order[k]] = { index = who[i], trainer = t[2], sprite = t[1], kind = 0, msg = { [0] = t[3], t[4] }, beaten = false }
    k = k + 1
  end
  for i = 0, 1 do
    local t = M.SLEEPERS[sleepers[i]]
    s.rooms[order[k]] = { index = i, trainer = 0, sprite = t[1], kind = 2, msg = { [0] = t[2], t[3] }, beaten = false }
    k = k + 1
  end
  for i = 0, 15 - (n + 2) - 1 do
    local t = M.TALKERS[talkers[i]]
    s.rooms[order[k]] = { index = i, trainer = 0, sprite = t[1], kind = 1, msg = { [0] = t[2], t[3] }, beaten = false }
    k = k + 1
  end
  return s
end

function M.get() local G = Game() return G and G.gen5RoyalUnova end
function M.set(s) local G = Game() if G then G.gen5RoyalUnova = s end end

-- 0x1A9 <room, kind, b, dest> (ov10 0x02166734): kinds 0..3 answer 0; 4 the
-- cabin's sprite (10 with no cruise -- the zone's transition script asks
-- before 0x1A5 has run), 5 its kind, 6 its trainer, 7 message b, 8 beaten
function M.roomQuery(s, room, kind, b)
  if kind == 4 and not s then return 10 end
  local r = s and s.rooms[room]
  if not r then return 0 end
  if kind == 4 then return r.sprite
  elseif kind == 5 then return r.kind
  elseif kind == 6 then return r.trainer
  elseif kind == 7 then return r.msg[b] or 0
  elseif kind == 8 then return r.beaten and 1 or 0 end
  return 0
end

-- 0x1A7 <kind, dest> (ov21 0x021C8738): 0..3 the side / door counters, 4 the
-- trainers aboard, 5 how many cabins are marked beaten
function M.query(s, kind)
  if not s then return 0 end
  if kind >= 0 and kind <= 3 then return s.counts[kind] or 0 end
  if kind == 4 then return s.trainers end
  if kind == 5 then
    local n = 0
    for room = 0, 14 do if s.rooms[room] and s.rooms[room].beaten then n = n + 1 end end
    return n
  end
  return 0
end

-- 0x1A8 <halves, toEnd> (ov21 0x021C86E8): time passes, 30 frames a unit.
-- Past the segment's end: toEnd 1 stops one frame short of it (the next
-- tick blows the horn), toEnd 0 starts the next segment without one
function M.advance(s, units, toEnd)
  if not s then return end
  local seg = M.SEGMENT
  local rem = (s.clock % seg) + 30 * units
  if rem >= seg then
    if toEnd ~= 0 then
      s.clock = (s.segments + 1) * seg - 1
    else
      s.segments = s.segments + 1
      s.clock = s.segments * seg
    end
  else
    s.clock = s.clock + 30 * units
  end
end

-- the field's frame: 0x021C868C (only while the player is free) and
-- 0x021C8660 (every frame) -> 1 to run the zone's script 1
function M.tick(s, free)
  if not s or s.stopped then return nil end
  local arrive
  if free then
    s.clock = s.clock + 1
    if s.clock >= M.SEGMENT * M.SEGMENTS and s.segments >= M.SEGMENTS then
      arrive = true
    elseif s.clock % M.SEGMENT == 0 then
      s.pending = 1
    end
  end
  if s.pending ~= 0 then
    local G = Game()
    if G and G.data then pcall(function() require("src.core.Sound").play(G.data, M.HORN) end) end
    s.segments = s.segments + 1
    s.pending = 0
  end
  return arrive
end

local function busy(ow)
  return (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
      or (ow.pendingScripts and #ow.pendingScripts > 0)
      or ow.warping or ow.transition or ow.gen5QueuedEntry
end

-- called by the overworld once a frame
function M.update(ow, dt)
  local s = M.get()
  if not s then return end
  local def = ow.map and ow.map.def
  if not (def and def.gen5 and def.header == M.ZONE) then return end
  s.frac = (s.frac or 0) + (dt or (1 / 60)) * 60
  while s.frac >= 1 do
    s.frac = s.frac - 1
    if M.tick(s, not busy(ow)) then
      s.frac = 0
      local G = Game()
      local ms = G and G.data and G.data.map_scripts
      local rec = ms and ms.maps and ms.maps[ow.map.id]
      local label = rec and rec.entries and rec.entries[1]
      local rows = label and require("src.script.Gen4ScriptVM").compile(G.data, label)
      if rows then
        require("src.core.Logger").info("royal unova: the cruise is over (%s)", label)
        ow.runner:run(rows, { mapId = ow.map.id })
      end
      return
    end
  end
end

-- ------------------------------------------------------------- commands --

function Commands.g5_ship_init()
  if not M.get() then
    M.set(M.new())
    local s = M.get()
    local t = {}
    for room = 0, 14 do local r = s.rooms[room] t[#t + 1] = ("%d:%d/%d"):format(room, r.kind, r.trainer) end
    require("src.core.Logger").info("royal unova: %d trainers, weekday %d [%s]", s.trainers, M.weekday(), table.concat(t, " "))
  end
end
function Commands.g5_ship_free() M.set(nil) end
function Commands.g5_ship_stop() local s = M.get() if s then s.stopped = true end end
function Commands.g5_ship_count(ctx, kind, dest)
  G4().setVar(ctx.save, dest, M.query(M.get(), math.floor(tonumber(kind) or 0)))
end
function Commands.g5_ship_advance(ctx, units, toEnd)
  M.advance(M.get(), math.floor(tonumber(units) or 0), math.floor(tonumber(toEnd) or 0))
end
function Commands.g5_ship_room(ctx, room, kind, b, dest)
  local C = G4()
  local v = M.roomQuery(M.get(), math.floor(tonumber(C.valueOf(ctx, room)) or -1),
    math.floor(tonumber(kind) or 0), math.floor(tonumber(C.valueOf(ctx, b)) or 0))
  C.setVar(ctx.save, dest, v)
end
-- 0x1AA <room, kind, _, value> (ov21 0x021C88EC): only kind 8 is written --
-- the cabin marked beaten when value is 1
function Commands.g5_ship_set(ctx, room, kind, value)
  local C = G4()
  local s = M.get()
  local r = s and s.rooms[math.floor(tonumber(C.valueOf(ctx, room)) or -1)]
  if r and math.floor(tonumber(kind) or 0) == 8 then r.beaten = C.valueOf(ctx, value) == 1 end
end
-- 0x1AB <dest> (ov10 0x021667E0): the observation deck's scenery, an app
-- (proc 0xCB) handed the clock; dest = 1 when the cruise ended inside it,
-- and the clock comes back from it. NOT PORTED: the app is not, so the
-- deck answers 0 and the clock is left as it was (inferred minimum)
function Commands.g5_ship_deck(ctx, dest) G4().setVar(ctx.save, dest, 0) end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwshipinit = L.bwshipinit or function(_, s) emit(s, { "g5_ship_init" }) end
  L.bwshipfree = L.bwshipfree or function(_, s) emit(s, { "g5_ship_free" }) end
  L.bwshipstop = L.bwshipstop or function(_, s) emit(s, { "g5_ship_stop" }) end
  L.bwshipcount = L.bwshipcount or function(ins, s) emit(s, { "g5_ship_count", ins.args[1], ins.args[2] }) end
  L.bwshipadvance = L.bwshipadvance or function(ins, s) emit(s, { "g5_ship_advance", ins.args[1], ins.args[2] }) end
  L.bwshiproom = L.bwshiproom or function(ins, s)
    emit(s, { "g5_ship_room", ins.args[1], ins.args[2], ins.args[3], ins.args[4] })
  end
  L.bwshipset = L.bwshipset or function(ins, s) emit(s, { "g5_ship_set", ins.args[1], ins.args[2], ins.args[4] }) end
  L.bwshipdeck = L.bwshipdeck or function(ins, s) emit(s, { "g5_ship_deck", ins.args[1] }) end
  -- a cache linked before these were named keeps the operand-free three as
  -- bw_1A5 / bw_1A6 / bw_1AC (the rest need the re-import the revision asks for)
  L.bw_1A5 = L.bw_1A5 or L.bwshipinit
  L.bw_1A6 = L.bw_1A6 or L.bwshipfree
  L.bw_1AC = L.bw_1AC or L.bwshipstop
end

return M
