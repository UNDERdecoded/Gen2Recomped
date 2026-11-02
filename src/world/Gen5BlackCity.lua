-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK CITY'S RESIDENTS (0x1C2 .. 0x1C9; White Forest's in White).
--
-- Black City has no people in its zone's event list: its trainers are the
-- RESIDENTS of the city's save block, spawned as objects when the zone loads.
-- On the cartridge they come and go with Entralink and tag-mode visitors;
-- with no link at all the city still has the ten its first set-up drew, and
-- that is the set this port keeps. The types and spots are
-- src/import/Gen5BlackCity.lua's.
--
-- READ FROM CODE (Black, overlay 20):
--   * a new city (0x021860D4): ten residents, each type drawn without
--     repeats by weight (0x020056EC(0x1CE) against the running sum of the
--     types not yet in the city, 0x021869E0; the drawn weight leaves the
--     range), mood = the type's +6 (Black) / +4 (White), present bit set
--   * the zone's objects (0x02186538): one per present resident, id 0x80 +
--     type, the type's sprite, movement type 3 (no wander box), its Black /
--     White script, at the version's spot for that slot (member 34 / 35)
--   * the resident a command means is the object in front of the player
--     (0x0216DDC0 at the player's front cell -> id - 0x80, 0x02186090)
--   * 0x1C4 <kind, dest> (0x02186D48): 0 the type's trainer, 1 mood <= 20
--     (wants to move on), 2 its state nibble, 3 how many live here
--     (0x02186278), 4 / 7 the block's first u16, 5 / 8 its second
--     (0x020127F0: block 0x2B +0x1FC), 9 the type, 10 can battle today,
--     11 the object's id
--   * 0x1C9 <dest, kind> (0x02187000): the type's line, type * 4 + kind
--     (+8 when the manager's first byte is set -- not in Black City)
--   * 0x1C3 (0x02186C44): when the resident could battle, it can no longer
--     today and the block's first u16 counts one more win (0x021869B0)
--   * 0x1C7 (0x02186E94): the second u16 + 10, to 10,000 at most
--   * 0x1C2 (0x02186BE4): the resident in front stops (no-op here: the
--     port's objects stand still under a script already)
--   * the save block's set-up (arm9 0x0200A848 -> ov10 0x02161D98 /
--     0x02161F00): no residents, and the two u16s at +0x1FC are 0 and 10 --
--     the greedy man's first goal is ten wins
--   * a resident's byte 3 holds three day flags, all set when it moves in
--     (0x02186B84) and by the daily update: bit 0 can battle (0x02186770,
--     cleared by 0x1C3's 0x02186764), bit 1 the first visit of the day
--     (mood + 3 on entering the zone, 0x021864DC), bit 2 the first talk
--     (mood + 10 at 0x1C2, 0x02186748); mood stays 0..100 (0x02186BB8)
--   * the daily update (0x021862A8, from ov10 0x0216904C, days elapsed
--     clamped 1..21): every resident's flags back to 7 and mood - 5 * days;
--     one that falls below 0 moves out to the other list (+0xF8) unless that
--     list and the leavers already make 10, when it stays at mood 1; in
--     White (version byte 1) it then picks the forest's Pokemon of the day: a
--     resident at random, one of its type's three species (+8 / +0xA / +0xC)
--     into the second u16 (0x1C4 kind 8) and its +0x24 into the first (kind 7)
--   * zone load (0x02186470): residents at mood 0 move out too
--   * 0x1C5 <slot> (0x02186CC4 -> ov21 0x02193B68): the resident's trainer
--     name (+0x38 of its record -- the player's own for the city's first
--     ten, 0x0218677C) into a string slot
--   * 0x1C6 <d1, d2, d3> (0x02186EB8, White Forest's researcher): over the
--     party, a non-egg of the day's species met in White Forest (met location
--     0x33, no egg dates): d1 = 1; met today: d2 = 1; d3 its slot (0xFFFF
--     none)
--   * 0x1C8 (0x02187098 -> 0x021870C4, the Black Gate clerk): a viewer of the
--     linked game's city, made only while an Entralink session is up
--     (0x02158344 returns 0 otherwise) -- offline it does nothing
-- INFERRED: the draw's random is the host's; days are the host's dates;
-- 0x02013DE0 (a flag check that keeps a resident at mood 0) reads 0; BW
-- catches' met data is read as metLocation / metDate when this port has it.

local M = {}

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

M.ZONES = { [0] = "black", [424] = "white" }

local function consts(data)
  local c = data and data.constants
  return c and c.gen5BlackCity
end

local function version()
  local v = require("src.core.GameVersion").get()
  return v == "white" and "white" or "black"
end

local function today()
  return os.date("%Y-%m-%d")
end

-- the city's save block, drawn on first use
function M.city(save, data)
  local c = consts(data)
  if not c then return nil end
  local city = save.gen5BlackCity
  if not city then
    local ver = version()
    city = { version = ver, residents = {}, wins = 0, goal = 10, away = {} }
    local taken, left = {}, 0x1CE
    for _ = 1, 10 do
      local pick = math.random(0, math.max(1, left) - 1)
      local sum, chosen = 0, nil
      for t = 0, 29 do
        local rec = c.types[t] or c.types[tostring(t)]
        if rec and not taken[t] then
          sum = sum + (rec.weight or 0)
          if sum > pick then chosen = t break end
        end
      end
      if chosen == nil then break end
      local rec = c.types[chosen] or c.types[tostring(chosen)]
      taken[chosen] = true
      left = left - (rec.weight or 0)
      -- the set-up runs with the version byte still 0: +6 in both games
      city.residents[#city.residents + 1] = { type = chosen, mood = rec.mood and rec.mood.black or 70,
        state = 1, flags = 7 }
    end
    city.day = os.time()
    save.gen5BlackCity = city
  end
  city.away = city.away or {}
  if type(city.day) ~= "number" then city.day = os.time() end
  M.daily(city, c)
  return city
end

local function dayNumber(t)
  local d = os.date("*t", t)
  return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
end

-- the daily update, once for all the days since the last (0x021862A8)
function M.daily(city, c, now)
  now = now or os.time()
  local days = math.floor((dayNumber(now) - dayNumber(city.day)) / 86400 + 0.5)
  if days <= 0 then return end
  city.day = now
  days = math.min(21, days)
  local kept, leaving = {}, 0
  for _, r in ipairs(city.residents) do
    r.flags = 7
    r.mood = (r.mood or 0) - 5 * days
    if r.mood < 0 then
      r.mood = 0
      if #city.away + leaving >= 10 then
        r.mood = 1
        kept[#kept + 1] = r
      else
        city.away[#city.away + 1] = r
        leaving = leaving + 1
      end
    else
      kept[#kept + 1] = r
    end
  end
  city.residents = kept
  if city.version == "white" and #kept > 0 then
    local r = kept[math.random(1, #kept)]
    local rec = c and (c.types[r.type] or c.types[tostring(r.type)])
    if rec and rec.species then
      city.goal = rec.species[math.random(1, 3)] or 0
      city.wins = rec.forest or 0
    end
  end
end

-- the zone's resident objects, appended to the def's templates on every load
function M.injectObjects(def, save, data)
  if not (def and def.header and M.ZONES[def.header]) then return end
  local c = consts(data)
  local city = c and M.city(save, data)
  local kept = {}
  for _, o in ipairs(def.objects or {}) do if not o.bwResident then kept[#kept + 1] = o end end
  def.objects = kept
  if not city then return end
  -- the zone's load: mood-0 residents move out (0x02186470), and the day's
  -- first visit lifts every resident's mood by 3 (0x021864DC)
  local stay = {}
  for _, r in ipairs(city.residents) do
    if (r.mood or 0) > 0 then stay[#stay + 1] = r
    elseif #city.away < 10 then city.away[#city.away + 1] = r end
  end
  city.residents = stay
  for _, r in ipairs(city.residents) do
    local f = r.flags or 7
    if math.floor(f / 2) % 2 == 1 then r.mood = math.min(100, (r.mood or 0) + 3); r.flags = f - 2 end
  end
  local ver = city.version or version()
  local spots = c.spots and (c.spots[ver] or c.spots.black)
  -- the script label the VM stamps on zone objects (Gen4ScriptVM.bindObjects):
  -- the resident's script is an entry of the zone's own member
  local pool = require("src.script.Gen4ScriptVM").store(data)
  local entries = pool and pool.maps and pool.maps[("Z%03d"):format(def.header)]
  entries = entries and entries.entries
  for slot, r in ipairs(city.residents) do
    local rec = c.types[r.type] or c.types[tostring(r.type)]
    local spot = spots and (spots[slot - 1] or spots[tostring(slot - 1)])
    if rec and spot then
      kept[#kept + 1] = {
        index = 0x80 + r.type, localId = 0x80 + r.type, graphicsId = rec.graphicsId,
        sprite = rec.sprite, spriteName = rec.spriteName, x = spot.x, y = spot.z, direction = 0,
        movementType = 3, movementRangeX = 0, movementRangeY = 0, gen5Range = true, trainerType = 0,
        flag = 0, script = rec.script and rec.script[ver] or 2, elevation = 0, gen5 = true, gen5Level = 0,
        bwResident = r.type,
      }
      local sc = kept[#kept].script
      local label = entries and (entries[sc] or entries[tostring(sc)]) or nil
      kept[#kept].text = label
      -- the zone lists no objects, so the VM compiled no talk script for it
      -- (Gen4ScriptVM's contributionFor): the resident's is added here
      local mapId = ("Z%03d"):format(def.header)
      local MS = require("src.script.MapScripts")
      if label and not MS.talkScript(mapId, label) then
        local VM = require("src.script.Gen4ScriptVM")
        local ok, rows = pcall(VM.compile, data, label)
        if ok and rows then MS.attachBase(mapId, { talk = { [label] = rows } }) end
      end
    end
  end
end

-- the resident in front of the player
local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
function M.front(ctx)
  local ow = ctx.overworld
  local p = ow and ow.player
  if not p then return nil end
  local d = DIRS[p.facing] or DIRS.down
  local tx, ty = p.cellX + d[1], p.cellY + d[2]
  for _, n in ipairs(ow.npcs or {}) do
    local def = n.def
    if def and def.bwResident and n.cellX == tx and n.cellY == ty then return def.bwResident, n end
  end
  -- ...or the one the script was started from
  local n = ctx.npc or ctx.object
  if type(n) == "table" and n.def and n.def.bwResident then return n.def.bwResident, n end
  return nil
end

local function resident(city, t)
  for _, r in ipairs(city and city.residents or {}) do if r.type == t then return r end end
  return nil
end

local function G4() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end
local function set(ctx, dest, v) G4().setVar(ctx.save, dest, math.floor(v or 0) % 65536) end

function M.query(ctx, kind)
  local data = ctx.game and ctx.game.data
  local city = M.city(ctx.save, data)
  if not city then return 0 end
  if kind == 3 then return #city.residents end
  if kind == 4 or kind == 7 then return city.wins or 0 end
  if kind == 5 or kind == 8 then return city.goal or 0 end
  local t = M.front(ctx)
  if t == nil then return 0 end
  local r = resident(city, t)
  local c = consts(data)
  local rec = c and (c.types[t] or c.types[tostring(t)])
  if kind == 0 then return rec and rec.trainer or 0 end
  if kind == 1 then return (r and (r.mood or 0) <= 20) and 1 or 0 end
  if kind == 2 then return r and (r.state or 1) or 0 end
  if kind == 6 then return 0 end
  if kind == 9 then return t end
  if kind == 10 then return (r and (r.flags or 7) % 2 == 1) and 1 or 0 end
  if kind == 11 then return 0x80 + t end
  return 0
end

function Commands.g5_city_query(ctx, kind, dest) set(ctx, dest, M.query(ctx, val(ctx, kind))) end
function Commands.g5_city_line(ctx, dest, kind)
  local t = M.front(ctx) or 0
  set(ctx, dest, t * 4 + val(ctx, kind))
end
function Commands.g5_city_battled(ctx)
  local city = M.city(ctx.save, ctx.game and ctx.game.data)
  local t = M.front(ctx)
  local r = city and t and resident(city, t)
  if r and (r.flags or 7) % 2 == 1 then
    r.flags = (r.flags or 7) - 1
    city.wins = math.min(65535, (city.wins or 0) + 1)
  end
end
-- 0x1C2: the first talk of the day lifts the resident's mood by 10
function Commands.g5_city_talk(ctx)
  local city = M.city(ctx.save, ctx.game and ctx.game.data)
  local t = M.front(ctx)
  local r = city and t and resident(city, t)
  if r and math.floor((r.flags or 7) / 4) % 2 == 1 then
    r.mood = math.min(100, (r.mood or 0) + 10)
    r.flags = (r.flags or 7) - 4
  end
end
-- 0x1C5 <slot>: the resident's trainer name (the player's own offline)
function Commands.g5_city_name(ctx, slot)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  local p = ctx.save and ctx.save.player
  game.stringBuffers[val(ctx, slot) + 1] = p and p.name or ""
end
-- 0x1C6 <d1, d2, d3>: the day's forest Pokemon in the party, caught here today
M.FOREST_MET = 0x33
function Commands.g5_city_forest_catch(ctx, d1, d2, d3)
  local city = M.city(ctx.save, ctx.game and ctx.game.data)
  local want = city and city.goal or -1
  set(ctx, d1, 0); set(ctx, d2, 0); set(ctx, d3, 0xFFFF)
  local found
  local t = os.date("*t")
  for i, mon in ipairs(ctx.save and ctx.save.party or {}) do
    local here = mon.metLocation == M.FOREST_MET or mon.metLocation == "Z424"
    if mon.species == want and not mon.isEgg and not mon.egg and here and not mon.eggDate then
      set(ctx, d1, 1)
      if found == nil then found = i - 1; set(ctx, d3, found) end
      local d = mon.metDate
      if type(d) == "table" and d.year == t.year and d.month == t.month and d.day == t.day then
        set(ctx, d2, 1); set(ctx, d3, i - 1)
      end
    end
  end
end
function Commands.g5_city_goal_up(ctx)
  local city = M.city(ctx.save, ctx.game and ctx.game.data)
  if city and (city.goal or 0) < 10000 then city.goal = (city.goal or 0) + 10 end
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwcitystop = L.bwcitystop or function(_, s) emit(s, { "g5_city_talk" }) end
  L.bwcityname = L.bwcityname or function(ins, s) emit(s, { "g5_city_name", ins.args[1] }) end
  L.bwcityforestcatch = L.bwcityforestcatch or function(ins, s)
    emit(s, { "g5_city_forest_catch", ins.args[1], ins.args[2], ins.args[3] })
  end
  L.bwcitygate = L.bwcitygate or function() end
  L.bwcityquery = L.bwcityquery or function(ins, s) emit(s, { "g5_city_query", ins.args[1], ins.args[2] }) end
  L.bwcityline = L.bwcityline or function(ins, s) emit(s, { "g5_city_line", ins.args[1], ins.args[2] }) end
  L.bwcitybattled = L.bwcitybattled or function(_, s) emit(s, { "g5_city_battled" }) end
  L.bwcitygoalup = L.bwcitygoalup or function(_, s) emit(s, { "g5_city_goal_up" }) end
end

return M
