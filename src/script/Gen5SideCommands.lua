-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE SIDE-QUEST COMMANDS whose answers decide items and flags.
--
-- READ FROM CODE (Black):
--   0x231 <dest> (ov21 0x021B51BC) THE HIP WADERS' CATCH OF THE DAY (Z258,
--         M0516): for the six zones of ov21 0x021D98D0 {255, 317, 321, 324,
--         370, 423} the zone's wild table of the season (/a/1/2/6 through
--         0x0215E2B8) gives its Super Rod list (if its rate is set) and its
--         rippling Super Rod list (if set), each species added once
--         (0x021B5190); dest = one of them at random (0x02005728)
--   0x11A <yearVar, monthVar, dayVar, slotVar> (ov10 0x0215C064): the party
--         Pokemon's met date (fields 0x92 / 0x93 / 0x94), 0 for an empty slot;
--         the script then asks for today's date (0x0D0) -- the catch must
--         be today's to win the 5 Dive Balls
--   0x238 <dest> (ov21 0x021B6590) the "show me this move" man (Z106,
--         M0212): a random item of the bag's TM & HM pocket (pocket 2,
--         0x02007FA0 / 0x020081DC) -> its move (0x020212B0); 0 if none
--   0x0E6 / 0x0E8 <feature, dest> and 0x0E7 <feature> (ov10 0x0215B104 /
--         0x0215B158 / 0x0215B138): two bits a feature in a save byte (+0x45,
--         arm9 0x0200C2F0 / 0x0200C308): 0x0E7 sets the low bit, 0x0E6 asks
--         the low bit, 0x0E8 asks for both (== 3). Z010's Fennel sets 1 and
--         2 (Game Sync); the Relocator machine (Z050) answers by feature 3
--   0x20C <which, word1, word2, dest> (ov21 0x021D213C): the Relocator
--         passwords, two easy-chat words: which 1 = 0x05C0 EVERYONE then
--         0x067B HAPPY, which 2 = 0x0664 SIMPLE then 0x06B7 CONNECTION, each
--         a word or its synonym (0x020249B0); the words come from 0x1ED's
--         entry screen (src/pokemon/Gen5EasyChat.lua)
--   UNITY TOWER (Z148 / Z149) reads the Global Link guest block: 0x1DD
--         <i, dest> its floor list (0x0B past the count, 0x02166824), 0x1DE
--         <which, dest> its count / first / third byte (0x02166834), 0x1E1 /
--         0x1E3 <dest> the guest list's counts (0x020095C8 / 0x02009628),
--         0x1DA <value, dest> 0 when the lookup finds nothing (0x021CFF78)
--   0x229 <slot, dest> (ov21 0x021D2710 -> ov10 0x0216BF9C): 1 when the
--         save's event record `slot` (0..7) XOR the trainer id matches the
--         table 0x02172508 -- a distribution key item (Liberty Pass, Lock
--         Capsule ...) received from a real event; this port has no event
--         records, so 0 (Mr. Lock and the Liberty Pass man take their "no"
--         branch, as an offline cartridge does)
-- INFERRED: this port has no Global Link guests, so the block is empty --
-- every Unity Tower answer is the empty one, 0x1DF answers 0 and the floor
-- menu 0x1E0 is closed at once (8010 = 0, "Please come again"); the bag's
-- TM pocket is read in item order.

local M = {}

M.CATCH_ZONES = { 255, 317, 321, 324, 370, 423 }
M.PASSWORDS = { [1] = { 0x05C0, 0x067B }, [2] = { 0x0664, 0x06B7 } }

local function G4() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end
local function set(ctx, var, v) G4().setVar(ctx.save, var, v) end
local function rnd(n) return love.math.random(0, math.max(1, n) - 1) end

-- the season's wild table of zone `zone`
local function wild(data, save, zone)
  local maps = data and data.maps
  local def = maps and maps[("Z%03d"):format(zone)]
  local idx = def and tonumber(def.encounters)
  local enc = data and data.encounters
  local t = enc and idx and (enc[idx] or enc[tostring(idx)])
  if type(t) ~= "table" then return nil end
  local season = require("src.world.Gen5FieldRules").seasonName(save)
  if t.seasons and season ~= "spring" and t.seasons[season] then t = t.seasons[season] end
  return t
end

function M.catchList(data, save)
  local list, seen = {}, {}
  local function addAll(kind)
    if type(kind) ~= "table" or not ((tonumber(kind.rate) or 0) > 0) then return end
    for _, slot in ipairs(kind.slots or {}) do
      local sp = tonumber(slot.species) or 0
      if sp > 0 and not seen[sp] then seen[sp] = true; list[#list + 1] = sp end
    end
  end
  for _, zone in ipairs(M.CATCH_ZONES) do
    local t = wild(data, save, zone)
    if t then addAll(t.superRod); addAll(t.ripplingFishing) end
  end
  return list
end

-- the bag's TM & HM pocket (bwPocket 2), in item order
function M.machinePocket(data, save)
  local items = data and data.items
  local out = {}
  for id, n in pairs(save and save.inventory or {}) do
    local num = tonumber(id) or tonumber(tostring(id):match("^ITEM_(%d+)$"))
    local it = items and num and (items[num] or items[tostring(num)])
    if it and tonumber(n) and n > 0 and it.bwPocket == 2 and it.machine then out[#out + 1] = { id = num, move = it.machine.move } end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

local function features(save)
  save.gen5Features = save.gen5Features or {}
  return save.gen5Features
end
function M.featureState(save, n)
  local f = save and save.gen5Features
  return f and tonumber(f[n] or f[tostring(n)]) or 0
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

function Commands.g5_catch_of_day(ctx, dest)
  local list = M.catchList(ctx.game and ctx.game.data, ctx.save)
  set(ctx, dest, #list > 0 and list[rnd(#list) + 1] or 0)
end

function Commands.g5_met_date(ctx, yearVar, monthVar, dayVar, slot)
  local m = (ctx.save and ctx.save.party or {})[val(ctx, slot) + 1]
  local d = m and type(m.metDate) == "table" and m.metDate
  set(ctx, yearVar, d and ((tonumber(d.year) or 2000) % 100) or 0)
  set(ctx, monthVar, d and tonumber(d.month) or 0)
  set(ctx, dayVar, d and tonumber(d.day) or 0)
end

function Commands.g5_random_machine_move(ctx, dest)
  local list = M.machinePocket(ctx.game and ctx.game.data, ctx.save)
  set(ctx, dest, #list > 0 and (tonumber(list[rnd(#list) + 1].move) or 0) or 0)
end

function Commands.g5_feature_set(ctx, n)
  local k = val(ctx, n)
  local f = features(ctx.save)
  local s = tonumber(f[k]) or 0
  if s % 2 == 0 then s = s + 1 end
  f[k] = s
end
function Commands.g5_feature_low(ctx, n, dest)
  set(ctx, dest, M.featureState(ctx.save, val(ctx, n)) % 2)
end
function Commands.g5_feature_full(ctx, n, dest)
  set(ctx, dest, M.featureState(ctx.save, val(ctx, n)) == 3 and 1 or 0)
end

-- (0x1ED's word entry is src/pokemon/Gen5EasyChat.lua's g5_word_entry)
function Commands.g5_password(ctx, which, w1, w2, dest)
  local want = M.PASSWORDS[val(ctx, which)]
  local EC = require("src.pokemon.Gen5EasyChat")
  local a, b = val(ctx, w1) % 0x800, val(ctx, w2) % 0x800
  set(ctx, dest, (want and EC.same(want[1], a) and EC.same(want[2], b)) and 1 or 0)
end

function Commands.g5_event_item(ctx, _slot, dest) set(ctx, dest, 0) end

-- Unity Tower on an empty guest block
function Commands.g5_unity_value(ctx, dest, empty) set(ctx, dest, empty or 0) end

function M.install(L)
  require("src.pokemon.Gen5EasyChat")
  local function emit(s, row) s.out[#s.out + 1] = row end
  local a = function(ins, k) return ins.args[k] end
  L.bwcatchofday = L.bwcatchofday or function(ins, s) emit(s, { "g5_catch_of_day", a(ins, 1) }) end
  L.bwmetdate = L.bwmetdate or function(ins, s) emit(s, { "g5_met_date", a(ins, 1), a(ins, 2), a(ins, 3), a(ins, 4) }) end
  L.bwmachinemove = L.bwmachinemove or function(ins, s) emit(s, { "g5_random_machine_move", a(ins, 1) }) end
  L.bwfeatureset = L.bwfeatureset or function(ins, s) emit(s, { "g5_feature_set", a(ins, 1) }) end
  L.bwfeaturelow = L.bwfeaturelow or function(ins, s) emit(s, { "g5_feature_low", a(ins, 1), a(ins, 2) }) end
  L.bwfeaturefull = L.bwfeaturefull or function(ins, s) emit(s, { "g5_feature_full", a(ins, 1), a(ins, 2) }) end
  L.bwwordentry = L.bwwordentry or function(ins, s) emit(s, { "g5_word_entry", a(ins, 1), a(ins, 2), a(ins, 3), a(ins, 4) }) end
  L.bweventitem = L.bweventitem or function(ins, s) emit(s, { "g5_event_item", a(ins, 1), a(ins, 2) }) end
  L.bwpassword = L.bwpassword or function(ins, s) emit(s, { "g5_password", a(ins, 1), a(ins, 2), a(ins, 3), a(ins, 4) }) end
  -- 0x1DD <i, dest> 0x0B; 0x1DE <which, dest>, 0x1E1 / 0x1E3 <dest>, 0x1DA
  -- <value, dest>, 0x1DF <value, i, dest> 0; 0x1E0 <..., dest> 0
  L.bwunityfloor = L.bwunityfloor or function(ins, s) emit(s, { "g5_unity_value", a(ins, 2), 0x0B }) end
  L.bwunity2 = L.bwunity2 or function(ins, s) emit(s, { "g5_unity_value", a(ins, 2), 0 }) end
  L.bwunity1 = L.bwunity1 or function(ins, s) emit(s, { "g5_unity_value", a(ins, 1), 0 }) end
  L.bwunity3 = L.bwunity3 or function(ins, s) emit(s, { "g5_unity_value", a(ins, 3), 0 }) end
  L.bwunitymenu = L.bwunitymenu or function(ins, s)
    emit(s, { "g5_unity_value", a(ins, 2), 0 }); emit(s, { "g5_unity_value", a(ins, 3), 0 })
    emit(s, { "g5_unity_value", a(ins, 4), 0 })
  end
end

return M
