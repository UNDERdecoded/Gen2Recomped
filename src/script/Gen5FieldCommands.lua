-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK / WHITE FIELD COMMANDS that have no Platinum row of the same shape
-- (named in src/import/Gen5ScriptLink.lua, lowered here).
--
--   bwaddmoney <amount>  0x0F9 (BeaterScript's AddMoney): a var-or-value,
--     where Platinum's addmoney is a literal u32 -- member 10's prize, `28
--     8026 0`, `26 8026 2710`, then `F9 8026`
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

function Commands.g4_bw_add_money(ctx, amount)
  local C = require("src.script.Gen4Commands")
  if Commands.g4_add_money then Commands.g4_add_money(ctx, C.valueOf(ctx, amount)) end
end

-- bwcardlevel <dest>  0x0CD: the Trainer Card's level (its colour) -- the
-- Pokemon Center nurse's "Th-that Trainer Card! That wonderful shade!" on
-- anything above 0 (member 855). The same count the card screen paints
-- (Gen4TrainerCard:cardLevel): ov10 0x0216F830's five points, READ, in
-- src/ui/Gen4CardLevel.lua (L.bw)
function Commands.g4_bw_card_level(ctx, destVar)
  local C = require("src.script.Gen4Commands")
  -- the five points ov10 0x0216F830 counts (src/ui/Gen4CardLevel.lua)
  local n = require("src.ui.Gen4CardLevel").bw(ctx.save or {})
  C.setVar(ctx.save, destVar, n)
end

-- bwapproachobject <which, dest>  0x082: the object of the trainer who
-- spotted you (the eye-contact record's object, then its id -- ov21
-- 0x021AEA3C); 0x07F is the same record's trainer id. The port runs a
-- spotting trainer through its own talk rows (ctx.npc), so the first is that
-- object and the second has none here
-- bwtimeperiod <dest>  0x0CD (ov10 0x0215AB18 -> 0x021690B4): arm9's table
-- 0x0209DF24, one byte per hour for each season -- 0 morning, 1 day, 2
-- evening, 3 night, 4 late night (READ FROM CODE; the season is the field's
-- +0x1C4, the month's place in the four-month cycle, as 0x0D2 reads it)
Commands.BW_TIME_PERIODS = {
  [0] = { [0] = 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3 },
  { [0] = 4, 4, 4, 4, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3 },
  { [0] = 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3 },
  { [0] = 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 3 },
}
function Commands.g5_time_period(ctx, destVar)
  local C = require("src.script.Gen4Commands")
  local okS, St = pcall(require, "src.script.Gen5Stadium")
  local t = okS and St.clock and St.clock() or os.date("*t")
  local season = ((tonumber(os.date("%m")) or 1) - 1) % 4
  local row = Commands.BW_TIME_PERIODS[season]
  C.setVar(ctx.save, destVar, row[(tonumber(t.hour) or 12) % 24] or 1)
end

function Commands.g4_bw_approach_object(ctx, which, destVar)
  local C = require("src.script.Gen4Commands")
  local npc = ctx.npc
  local id = 0
  if C.valueOf(ctx, which) == 0 and type(npc) == "table" then
    id = tonumber(npc.localId or (npc.def and npc.def.localId)) or 0
  end
  C.setVar(ctx.save, destVar, id)
end

-- THE MOVE DELETER (band 2260, member 859; HGSS's flow in BW's words):
--   0x109 <picked, moveSlot, partySlot, mode>  the summary's move list (ov21
--         0x021B636C launches it with both var pointers): picked 1 and the
--         slot, else 0 -- here Platinum's forget menu, then this result
--   0x10A <dest, partySlot, moveSlot>  that move (Platinum's g4_mon_move)
--   0x10B <partySlot, moveSlot, 0>     forget it (bwsetmove below)
function Commands.g4_bw_forget_result(ctx, pickedVar, slotVar)
  local C = require("src.script.Gen4Commands")
  local v = ctx.g4TutorForget or 4
  C.setVar(ctx.save, pickedVar, v ~= 4 and 1 or 0)
  C.setVar(ctx.save, slotVar, v ~= 4 and v or 0)
end

-- bwobjectat <idDest, foundDest, x, height, z>  0x070 (ov21 0x021B1C2C: two
-- var pointers, three values, then a map-object search at the tile): the
-- Pokemon Center scripts ask what stands three cells in front of the player
-- (member 855 `068 8033 8034; 26 8034 3; 070 8035 8010 8033 3 8034`) and
-- the healing scene two cells off (member 854). 1 and the object's id when
-- one is there, else 0 and 0
function Commands.g4_bw_object_at(ctx, idVar, foundVar, x, _height, z)
  local C = require("src.script.Gen4Commands")
  local cx, cz = C.valueOf(ctx, x), C.valueOf(ctx, z)
  local ow = ctx.overworld
  local id, found = 0, 0
  for _, n in ipairs((ow and ow.npcs) or {}) do
    if not n.hidden and n.cellX == cx and n.cellY == cz then
      id, found = tonumber(n.localId or (n.def and n.def.localId)) or 0, 1
      break
    end
  end
  C.setVar(ctx.save, idVar, id)
  C.setVar(ctx.save, foundVar, found)
end

-- bwsetform <partySlot, form>  0x117 (ov10 0x0215BF30: the party Pokemon's
-- form set, then the Pokedex told): the Deoxys meteor (member 876, `117 8020
-- 8024` after stepping 0x0FF's form round). Gen4Forms.setForm, which
-- recalculates the stats as the cartridge's form change does
function Commands.g4_bw_set_form(ctx, slot, form)
  local C = require("src.script.Gen4Commands")
  local mon = (ctx.save and ctx.save.party or {})[C.valueOf(ctx, slot) + 1]
  if not mon then return end
  require("src.pokemon.Gen4Forms").setForm(ctx.game and ctx.game.data, mon, C.valueOf(ctx, form))
end

-- bwfindspecies <species, foundDest, slotDest>  0x118 (ov10 0x0215BA18): the
-- first party Pokemon of that species that is not an egg -- found 1 and its
-- slot, else 0 and 0. The Deoxys meteor (`118 0182 8010 8020`), the Rotom
-- boxes, and Moor of Icirrus asking after Cobalion / Terrakion / Virizion
-- (`118 027E..0280 8010 8028`)
function Commands.g4_bw_find_species(ctx, species, foundVar, slotVar)
  local C = require("src.script.Gen4Commands")
  local want = C.valueOf(ctx, species)
  local found, slot = 0, 0
  for i, mon in ipairs((ctx.save and ctx.save.party) or {}) do
    local sp = tonumber(mon.species) or tonumber(tostring(mon.species or ""):match("(%d+)%s*$")) or 0
    if not mon.isEgg and sp == want then found, slot = 1, i - 1 break end
  end
  C.setVar(ctx.save, foundVar, found)
  C.setVar(ctx.save, slotVar, slot)
end

-- THE POKEDEX RATING (band 10380, member 884: Juniper and her father):
--   0x1CF <mode, msgDest, countDest>  the count and the line rating it (ov21
--         0x021B5DF8): mode 1 national caught, 2 Unova seen, 3 Unova caught;
--         complete answers 50 / 13 / 30, else the first { limit, line } of
--         the mode's table (ov21 0x021D992C / 9904 / 98DC, read through
--         0x021B5DD0) whose limit is not below the count
--   0x1CE <dest, mode>  that mode complete? (1 / 0)
--   0x1D1 <dest>        the National Pokedex had? (0x0200CA38)
-- Unova is species 494..649 (Victini the regional #000); "complete" leaves
-- out the event Pokemon -- Victini, Keldeo, Meloetta, Genesect, and the
-- earlier regions' Mew, Celebi, Jirachi, Deoxys, Phione..Arceus nationally.
-- The port keeps one seen / owned set, not one per region.
M.RATING = {
  [1] = { 39, 34, 79, 35, 119, 36, 159, 37, 199, 38, 249, 39, 299, 40, 349, 41, 399, 42,
          449, 43, 499, 44, 549, 45, 599, 46, 614, 47, 629, 48, 633, 49, 0, 49 },
  [2] = { 14, 4, 24, 5, 39, 6, 59, 7, 89, 8, 114, 9, 134, 10, 144, 11, 149, 12, 0, 12 },
  [3] = { 29, 21, 49, 22, 69, 23, 89, 24, 104, 25, 119, 26, 134, 27, 144, 28, 149, 29, 0, 29 },
}
M.COMPLETE_LINE = { [1] = 50, [2] = 13, [3] = 30 }
local EVENT = { [151] = true, [251] = true, [385] = true, [386] = true, [489] = true, [490] = true,
  [491] = true, [492] = true, [493] = true, [494] = true, [647] = true, [648] = true, [649] = true }
local function ids(save, field)
  local out = {}
  for key, flag in pairs(((save or {}).pokedex or {})[field] or {}) do
    if flag == true or (type(flag) == "number" and flag > 0) then
      local id = tonumber(key) or tonumber(tostring(key):match("(%d+)%s*$"))
      if id and id >= 1 and id <= 649 then out[id] = true end
    end
  end
  return out
end
-- count, complete for a mode
function M.dexMode(save, mode)
  local field = (mode == 2) and "seen" or "owned"
  local lo = (mode == 1) and 1 or 494
  local n, have = 0, 0
  local set = ids(save, field)
  for id = lo, 649 do
    if set[id] then n = n + 1 end
    if not EVENT[id] then have = have + ((set[id] and 1) or 0) end
  end
  local need = 0
  for id = lo, 649 do if not EVENT[id] then need = need + 1 end end
  return n, have >= need
end
function M.rate(mode, count)
  local t = M.RATING[mode] or {}
  for i = 1, #t, 2 do
    if t[i] == 0 or count <= t[i] then return t[i + 1] end
  end
  return 0
end
function Commands.g4_bw_dex_rating(ctx, mode, msgVar, countVar)
  local C = require("src.script.Gen4Commands")
  local m = C.valueOf(ctx, mode)
  local n, complete = M.dexMode(ctx.save, m)
  C.setVar(ctx.save, msgVar, complete and (M.COMPLETE_LINE[m] or 0) or M.rate(m, n))
  C.setVar(ctx.save, countVar, n)
end
function Commands.g4_bw_dex_complete(ctx, destVar, mode)
  local C = require("src.script.Gen4Commands")
  local _, complete = M.dexMode(ctx.save, C.valueOf(ctx, mode))
  C.setVar(ctx.save, destVar, complete and 1 or 0)
end
function Commands.g4_bw_has_national_dex(ctx, destVar)
  local C = require("src.script.Gen4Commands")
  local dex = ctx.save and ctx.save.pokedex
  C.setVar(ctx.save, destVar, (dex and dex.national) and 1 or 0)
end

-- THE JUDGE (band 10310, member 879): 0x237 <partySlot, mode, dest> (ov21
-- 0x021B5CE8) reads the six IVs (data 0x46..0x4B: HP, Attack, Defense,
-- Speed, Sp. Atk, Sp. Def) and answers by mode: 0 their total, 1 the
-- highest, 2..7 one IV in that order; no Pokemon in the slot answers 0.
-- The script picks "decent / above average / relatively superior /
-- outstanding" from the total and the stat lines from the rest
M.JUDGE_IVS = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
function M.judge(mon, mode)
  if not mon then return 0 end
  local ivs = mon.ivs or mon.dvs or {}
  local total, best = 0, 0
  for _, k in ipairs(M.JUDGE_IVS) do
    local v = math.floor(tonumber(ivs[k]) or 0)
    total = total + v
    if v > best then best = v end
  end
  if mode == 0 then return total end
  if mode == 1 then return best end
  local k = M.JUDGE_IVS[mode - 1]
  return k and math.floor(tonumber(ivs[k]) or 0) or 0
end
function Commands.g4_bw_judge(ctx, slot, mode, destVar)
  local C = require("src.script.Gen4Commands")
  local mon = (ctx.save and ctx.save.party or {})[C.valueOf(ctx, slot) + 1]
  C.setVar(ctx.save, destVar, M.judge(mon, C.valueOf(ctx, mode)))
end

-- bwmonisown <dest, partySlot>  0x113 (ov10 0x0215BE24): 1 when the party
-- Pokemon's OT id (data 7) is the player's and its OT name (data 0x8D) is
-- the player's name -- caught, not traded. Abundant Shrine (member 752,
-- `113 8029 8027`) and member 857 ask it
function Commands.g4_bw_mon_is_own(ctx, destVar, slot)
  local C = require("src.script.Gen4Commands")
  local save = ctx.save or {}
  local mon = (save.party or {})[C.valueOf(ctx, slot) + 1]
  local player = save.player or {}
  local own = 0
  if mon then
    local pid = tonumber(player.id or player.trainerId)
    local mid = tonumber(mon.otId) or pid
    local sameId = pid == nil or (mid % 4294967296) == (pid % 4294967296)
    local sameName = (mon.ot == nil) or (player.name == nil) or (mon.ot == player.name)
    if sameId and sameName and not mon.traded then own = 1 end
  end
  C.setVar(save, destVar, own)
end

-- THE MOVE TUTORS (member 860; ov21 0x021B5F24..0x021B6268): kind 0 Draco
-- Meteor, 1 the starters' ultimate moves, 2 the Pledges. 0x0201891C <mon, k>
-- is the species' special-tutor bit: 6 Draco Meteor (the Dragon types), 3 /
-- 4 / 5 Frenzy Plant / Blast Burn / Hydro Cannon (the fully evolved
-- starters), 0 / 1 / 2 Grass / Fire / Water Pledge (the whole starter lines).
-- Every kind wants friendship 255 (0x021B5FB4).
--   0x1E4 <kind, dest>              1 no Pokemon can learn it, 2 none is
--                                   friendly enough, 0 one can
--   0x1E5 <kind, slot, dest>        1 can't, 3 knows it, 2 not friendly, 0 ok
--   0x1E6 <kind, slot, dest>        the move it would learn
--   0x1E7 <kind, picked, slot>      the party pick (picked 1, else 0)
local GRASS = { 1, 2, 3, 152, 153, 154, 252, 253, 254, 387, 388, 389, 495, 496, 497 }
local FIRE = { 4, 5, 6, 155, 156, 157, 255, 256, 257, 390, 391, 392, 498, 499, 500 }
local WATER = { 7, 8, 9, 158, 159, 160, 258, 259, 260, 393, 394, 395, 501, 502, 503 }
local function set(list) local t = {} for _, v in ipairs(list) do t[v] = true end return t end
M.TUTOR_BITS = {
  [0] = set(GRASS), [1] = set(FIRE), [2] = set(WATER),
  [3] = set({ 3, 154, 254, 389, 497 }), [4] = set({ 6, 157, 257, 392, 500 }),
  [5] = set({ 9, 160, 260, 395, 503 }),
}
M.TUTOR_KIND = { [0] = { { 6, 434 } }, [1] = { { 3, 338 }, { 4, 307 }, { 5, 308 } },
                 [2] = { { 0, 520 }, { 1, 519 }, { 2, 518 } } }
local function speciesOf(mon)
  return tonumber(mon.species) or tonumber(tostring(mon.species or ""):match("(%d+)%s*$")) or 0
end
function M.tutorBit(data, mon, k)
  local sp = speciesOf(mon)
  if k == 6 then
    local def = data and data.pokemon and data.pokemon[sp]
    for _, t in ipairs((def and def.types) or {}) do if t == "DRAGON" then return true end end
    return false
  end
  return M.TUTOR_BITS[k] and M.TUTOR_BITS[k][sp] or false
end
function M.tutorMove(data, mon, kind)
  for _, e in ipairs(M.TUTOR_KIND[kind] or {}) do
    if M.tutorBit(data, mon, e[1]) then return e[2] end
  end
  return 0
end
local function friendship(data, mon)
  local v = tonumber(mon.friendship or mon.happiness)
  if v then return v end
  local def = data and data.pokemon and data.pokemon[speciesOf(mon)]
  return tonumber(def and def.baseFriendship) or 0
end
local function knows(mon, move)
  for _, m in ipairs(mon.moves or {}) do
    if (tonumber(m) or tonumber(m and m.id)) == move then return true end
  end
  return false
end
function M.tutorParty(data, party, kind)
  local any, friendly = false, false
  for _, mon in ipairs(party or {}) do
    if not mon.isEgg and M.tutorMove(data, mon, kind) ~= 0 then
      any = true
      if friendship(data, mon) >= 255 then friendly = true end
    end
  end
  return not any and 1 or (not friendly and 2 or 0)
end
function M.tutorMon(data, mon, kind)
  if not mon then return 1 end
  local move = M.tutorMove(data, mon, kind)
  if mon.isEgg or move == 0 then return 1 end
  if knows(mon, move) then return 3 end
  if friendship(data, mon) < 255 then return 2 end
  return 0
end
local function G4() return require("src.script.Gen4Commands") end
local function dataOf(ctx) return ctx.game and ctx.game.data end
local function partyMon(ctx, slot) return (ctx.save and ctx.save.party or {})[G4().valueOf(ctx, slot) + 1] end
function Commands.g4_bw_tutor_party(ctx, kind, destVar)
  G4().setVar(ctx.save, destVar, M.tutorParty(dataOf(ctx), ctx.save and ctx.save.party, G4().valueOf(ctx, kind)))
end
function Commands.g4_bw_tutor_mon(ctx, kind, slot, destVar)
  G4().setVar(ctx.save, destVar, M.tutorMon(dataOf(ctx), partyMon(ctx, slot), G4().valueOf(ctx, kind)))
end
function Commands.g4_bw_tutor_move(ctx, kind, slot, destVar)
  local mon = partyMon(ctx, slot)
  G4().setVar(ctx.save, destVar, mon and M.tutorMove(dataOf(ctx), mon, G4().valueOf(ctx, kind)) or 0)
end
function Commands.g4_bw_tutor_pick_result(ctx, pickedVar, slotVar)
  local slot = ctx.g4PartySlot
  local picked = slot ~= nil and slot ~= 255 and slot ~= G4().PARTY_SLOT_NONE
  G4().setVar(ctx.save, pickedVar, picked and 1 or 0)
  G4().setVar(ctx.save, slotVar, picked and slot or 0)
end

-- bwsetmove <partySlot, moveSlot, move>  0x10B: move 0 forgets the slot
-- (the rest move up), else the slot takes the move at full PP, no PP Ups
function Commands.g4_bw_set_move(ctx, slot, moveSlot, move)
  local C = require("src.script.Gen4Commands")
  local mon = (ctx.save and ctx.save.party or {})[C.valueOf(ctx, slot) + 1]
  if not mon then return end
  local i = C.valueOf(ctx, moveSlot) + 1
  local id = C.valueOf(ctx, move)
  mon.moves = mon.moves or {}
  if id == 0 then
    if mon.moves[i] then table.remove(mon.moves, i) end
    return
  end
  local def = ctx.game and ctx.game.data and ctx.game.data.moves and ctx.game.data.moves[id]
  if i > #mon.moves + 1 then i = #mon.moves + 1 end
  if i <= 4 then mon.moves[i] = { id = id, pp = def and def.pp or 0, ppUps = 0 } end
end

-- bwobjectflag <objectId, dest>  0x06A (ov21 0x021B19B0): the map object's
-- own event flag. The item-ball Foongus (member 897): `startwildbattle 24E`,
-- then on a win `06A 8011 8010; setflag 8010; removeobject 8011` -- so a
-- beaten one stays gone. 0 when no such object stands here
function Commands.g4_bw_object_flag(ctx, objectId, destVar)
  local C = require("src.script.Gen4Commands")
  local want = C.valueOf(ctx, objectId)
  local flag = 0
  for _, n in ipairs((ctx.overworld and ctx.overworld.npcs) or {}) do
    local id = tonumber(n.localId or (n.def and n.def.localId))
    if id == want then
      local def = n.def or {}
      flag = tonumber(def.flag)
        or tonumber(tostring(def.eventFlag or ""):match("^FLAG_G4_(%x+)$") or "", 16) or 0
      break
    end
  end
  C.setVar(ctx.save, destVar, flag)
end

-- THE DAY CARE (band 2200, member 856), lowered onto Platinum's model
-- (src/pokemon/Gen4DayCare.lua). Each handler goes through the save's Day
-- Care block (0x02188D50) and a 0x021C3xxx helper, the same calls in turn:
--   0x0EB <dest> an Egg waiting   0x0EE <dest> how many are in   0x0EF <dest>
--   compatibility (70 / 50 / 20 / 0)   0x0EC give the Egg   0x0ED discard it
--   0x0F7 <dest> the party pick to leave one (255 cancel)   0x0F0 <slot> leave
--   it   0x0F1 <which> take it back   0x0F2 / 0x0F3 / 0x0F8 <dest, which>
--   its species / form / gender (data 5 / 0x6F / 0x6E)   0x0F4 <dest, which>
--   its level with the steps walked   0x0F5 / 0x0F6 <dest, which> levels
--   grown / the price   0x251 <dest, 0, which> the menu's sign: 1 male, 2
--   female, 0 none (a Nidoran keeps its own)   0x05B <slot, which> its
--   nickname into a buffer   0x24D <species, form> its cry
local function DC() return require("src.pokemon.Gen4DayCare") end
local function dcMon(ctx, which)
  local s = DC().slot(ctx.save, G4().valueOf(ctx, which))
  return s and s.mon, s
end
local GENDER_N = { male = 0, female = 1, none = 2 }
function Commands.g4_bw_daycare_count(ctx, destVar) G4().setVar(ctx.save, destVar, DC().count(ctx.save)) end
function Commands.g4_bw_daycare_field(ctx, field, destVar, which)
  local mon, slot = dcMon(ctx, which)
  local data = ctx.game and ctx.game.data
  local v = 0
  if mon then
    if field == "species" then v = tonumber(mon.species) or 0
    elseif field == "form" then v = tonumber(mon.form) or 0
    elseif field == "gender" then v = GENDER_N[DC().gender(data, mon)] or 2
    elseif field == "level" then v = DC().levelWithSteps(data, slot)
    elseif field == "sign" then
      local g = DC().gender(data, mon)
      local sp = tonumber(mon.species) or 0
      if (sp == 29 or sp == 32) and not mon.nickname then v = 0
      else v = (g == "male" and 1) or (g == "female" and 2) or 0 end
    end
  end
  G4().setVar(ctx.save, destVar, v)
end
function Commands.g4_bw_daycare_name(ctx, slot, which)
  local mon = dcMon(ctx, which)
  local game = ctx.game
  if not (game and mon) then return end
  local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[(tonumber(slot) or 0) + 1] = mon.nickname or (def and def.name) or "?"
end
function Commands.g4_bw_daycare_take(ctx, which)
  DC().withdraw(ctx.game.data, ctx.save, G4().valueOf(ctx, which))
end
function Commands.g4_bw_daycare_pick_result(ctx, destVar)
  G4().setVar(ctx.save, destVar, ctx.g4PartySlot or G4().PARTY_SLOT_NONE)
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwaddmoney = L.bwaddmoney or function(ins, s) emit(s, { "g4_bw_add_money", ins.args[1] }) end
  L.bwapproachobject = L.bwapproachobject or function(ins, s) emit(s, { "g4_bw_approach_object", ins.args[1], ins.args[2] }) end
  L.bwforgetmenu = L.bwforgetmenu or function(ins, s)
    emit(s, { "g4_tutor_forget_menu", ins.args[3], 0 })
    emit(s, { "g4_bw_forget_result", ins.args[1], ins.args[2] })
  end
  L.bwsetmove = L.bwsetmove or function(ins, s) emit(s, { "g4_bw_set_move", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwobjectat = L.bwobjectat or function(ins, s)
    emit(s, { "g4_bw_object_at", ins.args[1], ins.args[2], ins.args[3], ins.args[4], ins.args[5] })
  end
  L.bwsetform = L.bwsetform or function(ins, s) emit(s, { "g4_bw_set_form", ins.args[1], ins.args[2] }) end
  L.bwfindspecies = L.bwfindspecies or function(ins, s) emit(s, { "g4_bw_find_species", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwdexrating = L.bwdexrating or function(ins, s) emit(s, { "g4_bw_dex_rating", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwdexcomplete = L.bwdexcomplete or function(ins, s) emit(s, { "g4_bw_dex_complete", ins.args[1], ins.args[2] }) end
  L.bwhasnationaldex = L.bwhasnationaldex or function(ins, s) emit(s, { "g4_bw_has_national_dex", ins.args[1] }) end
  L.bwjudge = L.bwjudge or function(ins, s) emit(s, { "g4_bw_judge", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwmonisown = L.bwmonisown or function(ins, s) emit(s, { "g4_bw_mon_is_own", ins.args[1], ins.args[2] }) end
  L.bwtutorparty = L.bwtutorparty or function(ins, s) emit(s, { "g4_bw_tutor_party", ins.args[1], ins.args[2] }) end
  L.bwtutormon = L.bwtutormon or function(ins, s) emit(s, { "g4_bw_tutor_mon", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwtutormove = L.bwtutormove or function(ins, s) emit(s, { "g4_bw_tutor_move", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwtutorpick = L.bwtutorpick or function(ins, s)
    emit(s, { "g4_open_party_for_trade" })
    emit(s, { "g4_bw_tutor_pick_result", ins.args[2], ins.args[3] })
  end
  L.bwobjectflag = L.bwobjectflag or function(ins, s) emit(s, { "g4_bw_object_flag", ins.args[1], ins.args[2] }) end
  local function f(field, a, b) return function(ins, s) emit(s, { "g4_bw_daycare_field", field, ins.args[a], ins.args[b] }) end end
  L.bwdaycarehasegg = function(ins, s) emit(s, { "g4_daycare_has_egg", ins.args[1] }) end
  L.bwdaycarecount = function(ins, s) emit(s, { "g4_bw_daycare_count", ins.args[1] }) end
  L.bwdaycarecompat = function(ins, s) emit(s, { "g4_daycare_compatibility", ins.args[1] }) end
  L.bwdaycaregiveegg = function(_, s) emit(s, { "g4_daycare_give_egg" }) end
  L.bwdaycareresetegg = function(_, s) emit(s, { "g4_daycare_reset_egg" }) end
  L.bwdaycarepick = function(ins, s)
    emit(s, { "g4_daycare_party_menu" })
    emit(s, { "g4_bw_daycare_pick_result", ins.args[1] })
  end
  L.bwdaycareleave = function(ins, s) emit(s, { "g4_daycare_store", ins.args[1] }) end
  L.bwdaycaretake = function(ins, s) emit(s, { "g4_bw_daycare_take", ins.args[1] }) end
  L.bwdaycarespecies, L.bwdaycareform, L.bwdaycaregender = f("species", 1, 2), f("form", 1, 2), f("gender", 1, 2)
  L.bwdaycarelevel, L.bwdaycaresign = f("level", 1, 2), f("sign", 1, 3)
  L.bwdaycaregained = function(ins, s) emit(s, { "g4_daycare_gained", ins.args[1], ins.args[2] }) end
  L.bwdaycareprice = function(ins, s) emit(s, { "g4_daycare_price", ins.args[1], ins.args[2] }) end
  L.bwdaycarename = function(ins, s) emit(s, { "g4_bw_daycare_name", ins.args[1], ins.args[2] }) end
  L.bwcry = function(ins, s) emit(s, { "g4_play_cry", ins.args[1] }) end
  -- 0x0CD is the time of day and 0x0CE the card level (Gen5ScriptLink); a
  -- cache linked before that was read has the two names the other way round,
  -- which the op number undoes
  L.bwtimeperiod = L.bwtimeperiod or function(ins, s) emit(s, { "g5_time_period", ins.args[1] }) end
  L.bwcardlevel = L.bwcardlevel or function(ins, s)
    if ins.op == 0x0CD then emit(s, { "g5_time_period", ins.args[1] }) return end
    emit(s, { "g4_bw_card_level", ins.args[1] })
  end
  local timeOfDay = L.gettimeofday
  L.gettimeofday = function(ins, s)
    if ins.op == 0x0CE and require("src.core.GameVersion").isGen5() then
      emit(s, { "g4_bw_card_level", ins.args[1] })
    elseif timeOfDay then
      timeOfDay(ins, s)
    end
  end
  -- THE EYE SCRIPT'S APPROACH OPS IN A CACHE IMPORTED BEFORE THEY WERE NAMED
  -- (Gen5ScriptLink 0x080 / 0x081 / 0x083): such a cache keeps them as
  -- `bw_080` / `bw_081` / `bw_083` WITHOUT their operands. They occur only in
  -- member 863's S0D51, whose bytes are (Black, read from the ROM)
  --   @3411 `83 00 10 80`  0x083 0x8010    @3598 `80 00 00 00`  0x080 0
  --   @3713 / @3717 / @3858 / @3884  0x080 0, 0x080 1, 0x080 0, 0x080 1
  -- so 0x083's destination is 0x8010 and 0x080's slots come in call order,
  -- which g4_start_approach does when handed no slot.
  L.bw_083 = L.bw_083 or function(_, s) emit(s, { "g4_approach_type", 0x8010 }) end
  L.bw_080 = L.bw_080 or function(_, s) emit(s, { "g4_start_approach" }) end
  L.bw_081 = L.bw_081 or function() end
  -- Black / White's cutscene music (0x098 / 0x09F / 0x09E / 0x0A1 / 0x0A2):
  -- src/script/Gen5MusicCommands.lua
  require("src.script.Gen5MusicCommands").install(L)
  -- ...and the commands that edit the loaded zone's event records (0x1EA):
  -- src/script/Gen5FieldEventCommands.lua
  require("src.script.Gen5FieldEventCommands").install(L)
  -- ...and the Royal Unova's cruise (0x1A5..0x1AC): src/world/Gen5RoyalUnova.lua
  require("src.world.Gen5RoyalUnova").install(L)
  -- ...and the gates' electronic boards (0x17E): src/world/Gen5GateBoard.lua
  require("src.world.Gen5GateBoard").install(L)
  -- ...and the cutscene camera's presets (0x146): src/script/Gen5CameraCommands.lua
  require("src.script.Gen5CameraCommands").install(L)
  -- ...and the building animations (0x127..0x12C, 0x12E): src/world/Gen5BuildingAnim.lua
  require("src.world.Gen5BuildingAnim").install(L)
  -- ...and the layered field themes (0x0A3..0x0A5): src/world/Gen5MusicParts.lua
  require("src.world.Gen5MusicParts").install(L)
  -- ...and N's portrait (0x1D3..0x1D5): src/world/Gen5NPortrait.lua
  require("src.world.Gen5NPortrait").install(L)
  -- ...and the roamer / Dream World reads (0x1BD, 0x1EE, 0x1EF):
  -- src/script/Gen5LinkStubCommands.lua
  require("src.script.Gen5LinkStubCommands").install(L)
  -- ...and Passerby Analytics (0x063, 0x210..0x21F): src/world/Gen5Passerby.lua
  require("src.world.Gen5Passerby").install(L)
  -- ...and Black City's residents (0x1C2..0x1C9): src/world/Gen5BlackCity.lua
  require("src.world.Gen5BlackCity").install(L)
  -- ...and the roaming legendaries (0x1BC, the game clear): src/world/Gen5Roamers.lua
  require("src.world.Gen5Roamers").install(L)
  -- ...and Abyssal Ruins' surfacing (0x0DC, 0x0C8): src/script/Gen5DiveCommands.lua
  require("src.script.Gen5DiveCommands").install(L)
  -- ...and the Elite Four rooms' ambient sound (0x1A4): src/world/Gen5ZoneSounds.lua
  require("src.world.Gen5ZoneSounds").install(L)
  -- ...and the Abyssal Ruins' overlay models (0x135): src/world/Gen5ZoneModels.lua
  require("src.world.Gen5ZoneModels").install(L)
  -- ...and the street crowds (0x134): src/world/Gen5Walkers.lua
  require("src.world.Gen5Walkers").install(L)
  -- ...and the party checks (0x112, 0x236): src/script/Gen5PartyChecks.lua
  require("src.script.Gen5PartyChecks").install(L)
  -- ...and the side quests' commands: src/script/Gen5SideCommands.lua
  require("src.script.Gen5SideCommands").install(L)
  -- ...and the party / bag / save checks: src/script/Gen5FieldChecks.lua
  require("src.script.Gen5FieldChecks").install(L)
  -- ...and Zorua's illusion (0x221..0x224): src/world/Gen5IllusionFx.lua
  require("src.world.Gen5IllusionFx").install(L)
  -- ...and a script's weather (0x136): src/world/Gen5Weather.lua
  require("src.world.Gen5Weather").install(L)
  -- ...and an object's flight round the player (0x15B..0x15E):
  -- src/world/Gen5FlightPath.lua
  require("src.world.Gen5FlightPath").install(L)
  -- ...and objects raised in place / danced round (0x225, 0x226):
  -- src/world/Gen5ObjectMotion.lua
  require("src.world.Gen5ObjectMotion").install(L)
  -- ...and the Zorua story's picture / event Pokemon (0x227, 0x228):
  -- src/script/Gen5EventMonCommands.lua
  require("src.script.Gen5EventMonCommands").install(L)
  -- ...and 0x242 / 0x139 / 0x23C / 0x25E: src/script/Gen5MiscFieldOps.lua
  require("src.script.Gen5MiscFieldOps").install(L)
end

return M
