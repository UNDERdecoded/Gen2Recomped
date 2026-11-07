-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- GEN 4 / GEN 5 EXPERIENCE AND EFFORT VALUES.
--
-- The port paid Sinnoh, Johto-DS and Unova with Gen 2's routine (base exp
-- divided by the participants BEFORE the level multiply, the Exp. Share's
-- half printed as a second box, no Power items, no Macho Brace, no Pokerus,
-- EVs to level-100 Pokemon, Gen 4's /7 formula in Black / White).
--
-- GEN 4, READ FROM pokeplatinum src/battle/battle_script.c (HGSS identical):
--   BtlCmd_CalcExpGain   exp = baseExp * foeLevel / 7 (u16)
--                        no Exp. Share holder: gained = exp / participants
--                        else gained = (exp/2) / participants and
--                             shared = (exp/2) / holders (each at least 1)
--                        (participants and holders: party mons with HP)
--   GetExpTask           total = gained (if it fought) + shared (if it holds
--                        the Exp. Share), then x150/100 Lucky Egg, x150/100
--                        trainer battle, x150/100 not its OT (x170/100 when
--                        its language differs) -- ONE box per Pokemon; a
--                        Pokemon at level 100 or with no HP gets nothing,
--                        not even EVs
--   BattleScript_CalcEffortValues  per stat in HP/Atk/Def/Spe/SpA/SpD order:
--                        yield (+4 for the matching Power item), x2 Pokerus
--                        (any Pokerus byte, cured too), x2 Macho Brace, then
--                        clipped to 510 total and 255 per stat; stops once
--                        the total reaches 510
--
-- GEN 5 (Black / White) -- READ from Black's overlay 93 (0x21CB2D4 split,
-- 0x21CB55C scale, 0x21CB5F0 EVs; see M.split / M.total); the summary
-- below was the earlier inferred form: the scaled formula
--   base = floor(baseExp * foeLevel / 5), x1.5 trainer, split like Gen 4,
--   then floor(base * ((2L+10) / (L+Lp+10))^2.5) + 1   (L foe, Lp recipient)
--   then x1.5 traded (x1.7 other language), x1.5 Lucky Egg;
-- EVs as Gen 4 (Power items +4, Pokerus x2, Macho Brace x2) and a level-100
-- Pokemon still gains EVs.

local M = {}

M.EXP_SHARE, M.LUCKY_EGG, M.MACHO_BRACE = 216, 231, 215
-- ITEM_POWER_BRACER .. ITEM_POWER_WEIGHT (generated/items.txt), the stat each one feeds
M.POWER = { [289] = "attack", [290] = "defense", [291] = "spatk", [292] = "spdef",
  [293] = "speed", [294] = "hp" }
M.POWER_EFFECT = { LVLUP_HP_EV_UP = "hp", LVLUP_ATK_EV_UP = "attack", LVLUP_DEF_EV_UP = "defense",
  LVLUP_SPEED_EV_UP = "speed", LVLUP_SPATK_EV_UP = "spatk", LVLUP_SPDEF_EV_UP = "spdef" }
M.ORDER = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
M.MAX_TOTAL, M.MAX_STAT = 510, 255

local function GV() return require("src.core.GameVersion") end
function M.applies() return GV().isGen4() or GV().isGen5() end
function M.isGen5() return GV().isGen5() end

local function itemNum(mon)
  local v = mon and (mon.item or mon.heldItem)
  return tonumber(v) or tonumber(tostring(v or ""):match("(%d+)%s*$")) or 0
end
local function holdEffect(data, mon)
  local items = data and data.items
  local def = items and (items[itemNum(mon)] or items[mon.item])
  return def and def.holdEffect
end
local function holds(data, mon, id, effect)
  if itemNum(mon) == id then return true end
  return effect ~= nil and holdEffect(data, mon) == effect
end
function M.holdsExpShare(data, mon) return holds(data, mon, M.EXP_SHARE, "EXP_SHARE") end
function M.holdsLuckyEgg(data, mon) return holds(data, mon, M.LUCKY_EGG, "EXP_UP") end
function M.holdsMachoBrace(data, mon) return holds(data, mon, M.MACHO_BRACE, "EVS_UP_SPEED_DOWN") end
function M.powerStat(data, mon)
  return M.POWER[itemNum(mon)] or M.POWER_EFFECT[holdEffect(data, mon) or ""]
end
function M.hasPokerus(mon) return (tonumber(mon and mon.pokerus) or 0) ~= 0 end

-- not its original trainer: BattleSystem_PokemonIsOT compares the OT id
-- (and name); a Pokemon the port marks traded counts too
function M.notOT(save, mon)
  if mon.traded then return true end
  local pid = save and save.player and tonumber(save.player.id)
  local ot = tonumber(mon.otId)
  if pid and ot and ot ~= pid then return true end
  local pname = save and save.player and save.player.name
  if pid and ot and pname and mon.otName and mon.otName ~= pname then return true end
  return false
end
-- gGameLanguage against MON_DATA_LANGUAGE (src/pokemon/Gen45Language.lua)
function M.foreign(save, mon)
  local L = require("src.pokemon.Gen45Language")
  return L.of(save, mon) ~= L.save(save)
end

-- BtlCmd_CalcExpGain -> gained, shared
function M.split(baseExp, foeLevel, participants, holders, gen5, isTrainer)
  local exp
  participants = math.max(1, participants or 1)
  if gen5 then
    -- Black (READ, ov93 0x21CB2D4): baseExp * level / 5 (0x21D7EB4), x15/10
    -- in a trainer battle BEFORE the split; with Exp. Share holders the
    -- holders split floor(exp/2) and the fighters the rest (exp - exp/2)
    exp = math.floor(baseExp * foeLevel / 5)
    if isTrainer then exp = math.floor(exp * 15 / 10) end
    if (holders or 0) > 0 then
      local half = math.floor(exp / 2)
      return math.max(1, math.floor((exp - half) / participants)), math.max(1, math.floor(half / holders))
    end
    return math.max(1, math.floor(exp / participants)), 0
  else
    exp = math.floor(baseExp * foeLevel / 7) % 65536
  end
  if (holders or 0) > 0 then
    local half = math.floor(exp / 2)
    return math.max(1, math.floor(half / participants)), math.max(1, math.floor(half / holders))
  end
  return math.max(1, math.floor(exp / participants)), 0
end

-- ov93 helpers: P(n) and the 20.12 multiply that rounds above one half
function M.pow25(n)
  if n <= 0 then return 0 end
  local root = math.floor(math.sqrt(n * 4096))
  while (root + 1) * (root + 1) <= n * 4096 do root = root + 1 end
  while root * root > n * 4096 do root = root - 1 end
  return math.floor(n * n * root / 4096)
end
function M.fxmul(a, b)
  local p = a * b
  local r = math.floor(p / 4096)
  if p % 4096 > 0x800 then r = r + 1 end
  return r
end

-- the per-Pokemon total
function M.total(data, save, mon, share, isTrainer)
  local t = (share.participant and share.gained or 0) + (share.holder and share.shared or 0)
  if t <= 0 then return 0 end
  if share.gen5 then
    -- Black (READ, ov93 0x21CB55C): the trainer bonus is already in the
    -- split; t * P(2L+10) / P(L+Lp+10) + 1, P(n) = (n*n*isqrt(n<<12)) >> 12
    -- (the hardware square root of n in 20.12 fixed point); then the
    -- traded x1.5 / other-language x1.7 and the Lucky Egg x1.5 as 20.12
    -- multiplies rounded half-up (0x21D7B10)
    local L, Lp = share.foeLevel, tonumber(mon.level) or 1
    t = math.floor(t * M.pow25(2 * L + 10) / M.pow25(L + Lp + 10)) + 1
    if M.notOT(save, mon) then t = M.fxmul(t, M.foreign(save, mon) and 0x1B33 or 0x1800) end
    if M.holdsLuckyEgg(data, mon) then t = M.fxmul(t, 0x1800) end
    return t
  end
  if M.holdsLuckyEgg(data, mon) then t = math.floor(t * 150 / 100) end
  if isTrainer then t = math.floor(t * 150 / 100) end
  if M.notOT(save, mon) then t = math.floor(t * (M.foreign(save, mon) and 170 or 150) / 100) end
  return t
end

-- BattleScript_CalcEffortValues
function M.awardEVs(data, mon, yield)
  if type(yield) ~= "table" then return end
  mon.evs = mon.evs or {}
  local sum = 0
  for _, k in ipairs(M.ORDER) do sum = sum + (tonumber(mon.evs[k]) or 0) end
  local power = M.powerStat(data, mon)
  local pokerus, brace = M.hasPokerus(mon), M.holdsMachoBrace(data, mon)
  for _, k in ipairs(M.ORDER) do
    if sum >= M.MAX_TOTAL then break end
    local tmp = tonumber(yield[k] or (k == "spatk" and yield.spAttack) or (k == "spdef" and yield.spDefense)) or 0
    if power == k then tmp = tmp + 4 end
    if pokerus then tmp = tmp * 2 end
    if brace then tmp = tmp * 2 end
    local cur = tonumber(mon.evs[k]) or 0
    if sum + tmp > M.MAX_TOTAL then tmp = M.MAX_TOTAL - sum end
    if cur + tmp > M.MAX_STAT then tmp = M.MAX_STAT - cur end
    mon.evs[k] = cur + tmp
    sum = sum + tmp
  end
end

-- BattleState's award (vanillaExpAward): answers true when it paid the exp.
-- ctx.applyShare(mon, share, announce) runs the port's exp box, level-ups and
-- move learning; Experience.apply hands a `share.gen45` table to M.apply.
function M.award(battle, ctx)
  if not M.applies() or not (battle and battle.game and battle.game.save) then return false end
  local save, data = battle.game.save, battle.data
  local foe = ctx.foe
  local fought = {}
  for _, mon in ipairs(ctx.alive or {}) do fought[mon] = true end
  local participants, holders = 0, 0
  for _, mon in ipairs(save.party or {}) do
    if (tonumber(mon.hp) or 0) > 0 and not (mon.isEgg or mon.egg) then
      if fought[mon] then participants = participants + 1 end
      if M.holdsExpShare(data, mon) then holders = holders + 1 end
    end
  end
  if participants == 0 then return true end
  local gen5 = M.isGen5()
  local def = foe and foe.def
  local foeLevel = tonumber(foe and foe.mon and foe.mon.level) or 1
  local gained, shared = M.split(tonumber(def and def.baseExp) or 0, foeLevel, participants, holders, gen5,
                                 battle.kind == "trainer")
  for _, mon in ipairs(save.party or {}) do
    local live = (tonumber(mon.hp) or 0) > 0 and not (mon.isEgg or mon.egg)
    local holder = live and M.holdsExpShare(data, mon)
    if live and (fought[mon] or holder) then
      local share = { gen45 = true, gen5 = gen5, participant = fought[mon] == true, holder = holder,
        gained = gained, shared = shared, foeLevel = foeLevel }
      if (tonumber(mon.level) or 1) < 100 then
        ctx.applyShare(mon, share, true)
      elseif gen5 then
        -- Gen 5: a level-100 Pokemon still gains EVs (INFERRED)
        M.awardEVs(data, mon, def and (def.evYield or def.evYields))
      end
    end
  end
  return true
end

-- Experience.apply's Gen 4 / 5 branch -> levels, gained
function M.apply(data, mon, defeatedDef, level, isTrainer, share)
  local G = package.loaded["src.core.Game"]
  local save = G and G.save
  local Growth = require("src.pokemon.Growth")
  local Stats = require("src.pokemon.Stats")
  local Runtime = require("src.mods.Runtime")
  local speciesDef = require("src.pokemon.Gen4Forms").definition(data, mon)
  share.foeLevel = share.foeLevel or tonumber(level) or 1
  local gained = M.total(data, save, mon, share, isTrainer)
  mon.exp = (tonumber(mon.exp) or 0) + gained
  M.awardEVs(data, mon, defeatedDef and (defeatedDef.evYield or defeatedDef.evYields))
  local cap = (data.constants and data.constants.levelCap) or 100
  local levels = {}
  local newLevel = Growth.levelForExp(speciesDef.growthRate, mon.exp, cap, data.growth_rates)
  while mon.level < math.min(newLevel, cap) do
    mon.level = mon.level + 1
    local old = mon.stats
    mon.stats = Stats.calcGen3(speciesDef, mon.level, mon.ivs, mon.evs, mon.nature)
    mon.hp = math.min(mon.stats.hp, mon.hp + (mon.stats.hp - old.hp))
    levels[#levels + 1] = mon.level
    if Runtime.wants("pokemon.level_up") then
      Runtime.emit("pokemon.level_up", {
        mon = mon, level = mon.level, prevLevel = mon.level - 1,
        learnable = require("src.battle.Experience").movesLearnedAt(speciesDef, mon.level),
      })
    end
  end
  return levels, gained
end

return M
