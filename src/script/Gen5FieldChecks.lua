-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE FIELD COMMANDS that read the party, the bag or the save
-- for an offline side event.
--
-- READ FROM CODE (Black):
--   0x0BD <itemVar, dest> (ov21 0x021AF71C): the item's param 15
--         (0x02020FE4 -> 0x02021014: byte +0x0D of its record, the kind:
--         0 medicine, 1 held, 2 general, 3 battle, 4 ball, 5 mail) -- the
--         Zorua event (Z047) asks it of the ball the player picks
--   0x10E <dest, species, form, level, ability, gender, shiny, item, ball>
--         (ov10 0x0215BBD0 -> 0x0215C40C): a Pokemon given in the chosen ball
--         (item +0x98 when the ball's kind is 4), holding `item` (field 6);
--         the personality (arm9 0x020186C8): gender 0 male / 1 female / 2
--         random, shininess 0 never / 1 always / 2 as rolled, PID bit 16 =
--         ability (the three clamped to 2); Zorua (Z047) is 2, 0, 0: male, not
--         shiny
--   0x10F <dest, species, ?> (ov10 0x0215C2D0): an EGG of the species (level
--         1, its hatch cycles, met as an egg), dest 1 -- or 0 with a full
--         party (Z388's Larvesta egg)
--   0x11B <type1Var, type2Var, slotVar> (ov10 0x0215B558): the party
--         Pokemon's two types (fields 0xAE / 0xAF; a single type twice), 0 for
--         an empty slot (Z043 / Z154's "do you have that type?")
--   0x11E <badge> (ov21 0x021B5BFC): the party's species (non-eggs, six
--         at most) kept as the team that won that badge (0x0200C2B0, the
--         save's +0x58 + 12 * badge)
--   0x11F <badgeVar, dest> (ov21 0x021B5C80): that team -- dest the
--         count, each species' name in VAR1.. (0x0201EE60) (Z407)
--   0x20D <mode, aVar, bVar, wordVar> (ov21 0x021D2468): on the DS
--         owner's birthday 0x34 / 0x53 / word 0x062B, else r = rand(mode ? 30
--         : 22) and r + 0x16 / r + 0x35 / the word table 0x021DD6D0[r] (Z117)
--   0x05A <slot, wordVar> (ov21 0x021AFAFC): an easy-chat word into a
--         buffer (0x0201EFC8 -> 0x02024838) (Z066)
--   0x0E9 <dest> (ov21 0x021CFA88): u16 +0x7E of save block 0x1C
--         (0x02008854 / 0x02008990) -- the Abyssal Ruins' step count
--         (src/world/Gen5RuinsTimer.lua)
-- INFERRED: the
-- birthday is save.player.birthday { month, day } (no DS profile); a form's
-- own types are not looked up (the species' are).

local M = {}

M.TYPE_INDEX = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6, GHOST = 7,
  STEEL = 8, FIRE = 9, WATER = 10, GRASS = 11, ELECTRIC = 12, PSYCHIC = 13, ICE = 14, DRAGON = 15, DARK = 16 }
M.WORDS_20D = { 1697, 1494, 1689, 1534, 1671, 1443, 1572, 1699, 1562, 1717, 1547, 1538, 1696, 1405, 585, 522, 599,
  587, 595, 520, 511, 531, 563, 528, 555, 594, 518, 581, 618, 709, 1579 }

local function G4() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end
local function set(ctx, var, v) if var then G4().setVar(ctx.save, var, v) end end
local function data(ctx) return ctx.game and ctx.game.data end

local function speciesDef(d, sp)
  local reg = d and d.pokemon
  return reg and sp and (reg[sp] or reg[tostring(sp)] or reg[("SPECIES_%03d"):format(sp)]) or nil
end

local function itemRec(d, id)
  local items = d and d.items
  return items and (items[id] or items[tostring(id)]) or nil
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

function Commands.g5_item_kind(ctx, itemVar, dest)
  local it = itemRec(data(ctx), val(ctx, itemVar))
  set(ctx, dest, it and tonumber(it.itemType) or 0)
end

function Commands.g5_give_mon_ball(ctx, dest, species, form, level, ability, gender, shiny, item, ball)
  local before = #(ctx.save and ctx.save.party or {})
  local sp, lv = val(ctx, species), math.max(1, val(ctx, level))
  local ok = sp > 0 and speciesDef(data(ctx), sp) ~= nil and before < 6
  if ok then
    Commands.give_pokemon(ctx, sp, lv, true, nil)
    local party = ctx.save.party or {}
    ok = #party > before
    local m = ok and party[#party]
    if m then
      local b = val(ctx, ball)
      local bi = itemRec(data(ctx), b)
      if b > 0 and bi and tonumber(bi.itemType) == 4 then m.ball = b end
      local f = val(ctx, form)
      if f > 0 then m.form = f end
      local it = val(ctx, item)
      if it > 0 then m.item = ("ITEM_%d"):format(it) end
      local g = math.min(2, val(ctx, gender))
      if g == 0 then m.gender = "male" elseif g == 1 then m.gender = "female" end
      local sh = math.min(2, val(ctx, shiny))
      if sh == 0 then m.shiny = false elseif sh == 1 then m.shiny = true end
      local ab = math.min(2, val(ctx, ability))
      if ab <= 1 then m.abilitySlot = ab + 1 end
    end
  end
  set(ctx, dest, ok and 1 or 0)
end

function Commands.g5_give_egg(ctx, dest, species)
  local party = ctx.save and ctx.save.party or {}
  if #party >= 6 then set(ctx, dest, 0) return end
  local before = #party
  G4()
  Commands.g4_give_egg(ctx, species, 0)
  set(ctx, dest, #(ctx.save.party or {}) > before and 1 or 0)
end

function Commands.g5_mon_types(ctx, t1, t2, slot)
  local m = (ctx.save and ctx.save.party or {})[val(ctx, slot) + 1]
  if not m then set(ctx, t1, 0); set(ctx, t2, 0) return end
  local def = speciesDef(data(ctx), require("src.pokemon.Gen4DayCare").speciesOf(m))
  local types = def and def.types or {}
  local a = M.TYPE_INDEX[tostring(types[1] or ""):upper()] or 0
  local b = M.TYPE_INDEX[tostring(types[2] or types[1] or ""):upper()] or a
  set(ctx, t1, a); set(ctx, t2, b)
end

function Commands.g5_badge_team(ctx, badge)
  local n = val(ctx, badge)
  local team = {}
  for _, m in ipairs(ctx.save and ctx.save.party or {}) do
    if not m.isEgg and #team < 6 then team[#team + 1] = require("src.pokemon.Gen4DayCare").speciesOf(m) end
  end
  ctx.save.gen5BadgeTeams = ctx.save.gen5BadgeTeams or {}
  ctx.save.gen5BadgeTeams[n] = team
end

function Commands.g5_badge_team_names(ctx, badge, dest)
  local teams = ctx.save and ctx.save.gen5BadgeTeams
  local n = val(ctx, badge)
  local team = teams and (teams[n] or teams[tostring(n)]) or {}
  local count = 0
  for i = 1, 6 do
    local sp = tonumber(team[i]) or 0
    if sp ~= 0 then
      G4()
      Commands.g4_buffer(ctx, count, "species", sp)
      count = count + 1
    end
  end
  set(ctx, dest, count)
end

function Commands.g5_birthday_words(ctx, mode, a, b, word)
  local bd = ctx.save and ctx.save.player and ctx.save.player.birthday
  local t = os.date("*t")
  if type(bd) == "table" and tonumber(bd.month) == t.month and tonumber(bd.day) == t.day then
    set(ctx, a, 0x34); set(ctx, b, 0x53); set(ctx, word, M.WORDS_20D[31])
    return
  end
  local r = love.math.random(0, (val(ctx, mode) ~= 0 and 30 or 22) - 1)
  set(ctx, a, r + 0x16); set(ctx, b, r + 0x35); set(ctx, word, M.WORDS_20D[r + 1])
end

function Commands.g5_buffer_word(ctx, slot, wordVar)
  local s = require("src.pokemon.Gen5EasyChat").toString(data(ctx), val(ctx, wordVar))
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[val(ctx, slot) + 1] = s
end

function Commands.g5_save_block_1c(ctx, dest)
  set(ctx, dest, require("src.world.Gen5RuinsTimer").count(ctx.save))
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  local function verb(name, n)
    return function(ins, s)
      local row = { name }
      for k = 1, n do row[#row + 1] = ins.args[k] end
      emit(s, row)
    end
  end
  L.bwitemkind = L.bwitemkind or verb("g5_item_kind", 2)
  L.bwgivemonball = L.bwgivemonball or verb("g5_give_mon_ball", 9)
  L.bwgiveegg = L.bwgiveegg or verb("g5_give_egg", 3)
  L.bwmontypes = L.bwmontypes or verb("g5_mon_types", 3)
  L.bwbadgeteam = L.bwbadgeteam or verb("g5_badge_team", 1)
  L.bwbadgeteamnames = L.bwbadgeteamnames or verb("g5_badge_team_names", 2)
  L.bwbirthdaywords = L.bwbirthdaywords or verb("g5_birthday_words", 4)
  L.bwbufferword = L.bwbufferword or verb("g5_buffer_word", 2)
  L.bwsaveblock1c = L.bwsaveblock1c or verb("g5_save_block_1c", 1)
end

return M
