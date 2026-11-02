-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S ROAMING LEGENDARIES: Thundurus and Tornadus.
--
-- Black and White have exactly two roamer slots (save block 0x38, two
-- 0x14-byte records at +4, a state byte each at +0x2E and a location byte
-- each at +0x2C); Latios / Latias do not roam in these games (they are Black
-- 2 / White 2's), and nothing else ever fills a slot.
--
-- READ FROM CODE (Black; ov10 unless noted):
--   * 0x1BC <slot> (ov21 0x021B5154): when the slot's record is empty
--     (0x0200D488), release it (0x0215E440): slot 0 THUNDURUS (0x282), slot 1
--     TORNADUS (0x281), level 40, a fresh individual (its IVs / PID / HP /
--     status copied into the record), moved once with location 5 excluded,
--     state 1. Route 7's scene (member 674) releases slot 1 in Black, 0 in
--     White
--   * the state byte (0x0200D470): 0 never released, 1 roaming, 2 knocked
--     out (0x0215E5B0: a win with its HP at 0 -- the record is cleared and
--     it goes to location 16), 3 caught (result 5); 0x1BD reads it
--   * a move (0x0215E740): from location 16 it always lands somewhere; from
--     anywhere else one time in five (random(100) < 20) it goes to 16, no
--     zone at all; otherwise it lands on one of the current TIME PERIOD's
--     locations (arm9 0x020113D8 -> table 0x0209DF24, season x hour; then
--     0x021711A8: morning {0,1,15}, day {2,3,14}, evening {4,5,6}, night
--     {7,8,9}, late night {10..13}) that is neither where it is nor the
--     excluded one; location i is zone 0x021711C6[i]
--   * every roamer moves on every zone change (the map-change callback list,
--     0x02164478 -> 0x0215E364), after a battle with it that it fled, and,
--     three times in ten, after any other wild battle (0x0215E5B0)
--   * a wild encounter where a roamer is (ov21 0x021A957C): the roamers on
--     this zone that pass the level check, then random(1000) < 500 keeps the
--     ordinary encounter, else one of them at random
--   * 0x156, the game clear (ov21 0x021B4EE0 -> ov10 0x0215F8A8 ->
--     0x0215E580): every state-2 roamer is released again
-- NOT PORTED: the stormy weather on the roamer's zone (arm9 0x0202C794 picks
-- weather 6 / 7 there) -- this port draws no Black / White field weather.
-- INFERRED: the period is the host clock's (Gen5FieldCommands' table); a
-- repel / level check is the engine's own, which runs after this one.

local M = {}

M.SPECIES = { [0] = 642, [1] = 641 }
M.LEVEL = 40
M.NOWHERE = 16
M.ZONES = { [0] = 319, 321, 326, 329, 331, 337, 345, 348, 355, 365, 368, 370, 374, 378, 383, 387 }
M.PERIOD = { [0] = { 0, 1, 15 }, [1] = { 2, 3, 14 }, [2] = { 4, 5, 6 }, [3] = { 7, 8, 9 }, [4] = { 10, 11, 12, 13 } }
M.RELEASE_EXCLUDE = 5
M.VANISH_PERCENT = 20
M.LEAVE_AFTER_WILD_PERCENT = 30

local function rand(n, rng) return (rng or math.random)(0, n - 1) end

function M.store(save)
  save.gen5Roamer = save.gen5Roamer or { state = { [0] = 0, [1] = 0 } }
  return save.gen5Roamer
end

function M.state(save, slot)
  local s = save and save.gen5Roamer
  return s and s.state and (s.state[slot] or s.state[tostring(slot)]) or 0
end

local function record(save, slot)
  local s = M.store(save)
  local r = s[slot] or s[tostring(slot)]
  return r
end

function M.period()
  local okC, Cm = pcall(require, "src.script.Commands")
  pcall(require, "src.script.Gen5FieldCommands")
  local okS, St = pcall(require, "src.script.Gen5Stadium")
  local t = okS and St.clock and St.clock() or os.date("*t")
  local season = ((tonumber(os.date("%m")) or 1) - 1) % 4
  local row = okC and Cm.BW_TIME_PERIODS and Cm.BW_TIME_PERIODS[season]
  return row and row[(tonumber(t.hour) or 12) % 24] or 1
end

function M.move(save, slot, exclude, rng)
  local r = record(save, slot)
  if not r then return end
  local loc = r.loc or M.NOWHERE
  if loc ~= M.NOWHERE and rand(100, rng) < M.VANISH_PERCENT then
    r.loc = M.NOWHERE
    return
  end
  local cands = {}
  for _, l in ipairs(M.PERIOD[M.period()] or M.PERIOD[1]) do
    if l ~= loc and l ~= exclude then cands[#cands + 1] = l end
  end
  if #cands > 0 then r.loc = cands[rand(#cands, rng) + 1] end
end

function M.moveAll(save, rng)
  for slot = 0, 1 do if record(save, slot) then M.move(save, slot, 0xFF, rng) end end
end

function M.release(data, save, slot, rng)
  local s = M.store(save)
  if record(save, slot) or not M.SPECIES[slot] then return false end
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(data, M.SPECIES[slot], M.LEVEL)
  s[slot] = { species = M.SPECIES[slot], level = M.LEVEL, loc = M.NOWHERE,
              hp = mon and mon.hp, status = mon and mon.status,
              personality = mon and mon.personality, ivs = mon and mon.ivs }
  M.move(save, slot, M.RELEASE_EXCLUDE, rng)
  s.state[slot] = 1
  return true
end

function M.zoneOf(r)
  local z = r and M.ZONES[r.loc or M.NOWHERE]
  return z and ("Z%03d"):format(z) or nil
end

-- the roamer met on this zone, or nil (the 50% roll included)
function M.check(save, mapId, rng)
  local here = {}
  for slot = 0, 1 do
    local r = save and save.gen5Roamer and record(save, slot)
    if r and M.zoneOf(r) == mapId then here[#here + 1] = slot end
  end
  if #here == 0 then return nil end
  if rand(1000, rng) < 500 then return nil end
  local slot = here[rand(#here, rng) + 1]
  return slot, record(save, slot)
end

function M.encounterFor(slot, r)
  return { species = r.species, level = r.level or M.LEVEL, roamerHP = r.hp,
           roamerStatus = r.status,
           roamerSeed = r.personality and { personality = r.personality, ivs = r.ivs } or nil,
           roamerSlot = slot }
end

-- after any wild battle: slot is the roamer fought (nil for an ordinary one)
function M.afterBattle(save, slot, result, hp, status, rng)
  local s = save and save.gen5Roamer
  if not s then return end
  if slot ~= nil and record(save, slot) then
    if result == "caught" then
      s[slot] = nil; s.state[slot] = 3
    elseif (result == "win" or result == "lose") and (hp or 0) <= 0 then
      s[slot] = nil; s.state[slot] = 2
    else
      local r = record(save, slot)
      r.hp, r.status = hp, status
      M.moveAll(save, rng)
    end
  elseif rand(100, rng) < M.LEAVE_AFTER_WILD_PERCENT then
    M.moveAll(save, rng)
  end
end

-- the game clear: the knocked-out ones are released again
function M.rerelease(data, save)
  local s = save and save.gen5Roamer
  if not s then return end
  for slot = 0, 1 do
    if (s.state[slot] or 0) == 2 then M.release(data, save, slot) end
  end
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
function Commands.g5_roamer_release(ctx, slot)
  local C = require("src.script.Gen4Commands")
  local n = math.floor(tonumber(C.valueOf(ctx, slot)) or 0) % 256
  M.release(ctx.game and ctx.game.data, ctx.save, n)
end
function Commands.g5_roamers_rerelease(ctx)
  M.rerelease(ctx.game and ctx.game.data, ctx.save)
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwroamerrelease = L.bwroamerrelease or function(ins, s) emit(s, { "g5_roamer_release", ins.args[1] }) end
  -- the game clear releases the knocked-out roamers again (0x0215F8A8)
  local clear = L.bwgameclear
  if clear and not M.wrappedClear then
    M.wrappedClear = true
    L.bwgameclear = function(ins, s)
      emit(s, { "g5_roamers_rerelease" })
      return clear(ins, s)
    end
  end
end

return M
