-- Run:  texlua tools/gen4_party_forms_check.lua <cache dir>
--
-- SCRIPTED AND HELD-ITEM FORM CHANGES, AND AMITY SQUARE'S STEP COUNT.
--
-- Four script commands the port lowered to no-ops or stubs (pokeplatinum
-- src/scrcmd.c, src/scrcmd_amity_square.c), and one rule it had nowhere:
--
--   setpartygiratinaform  -- Origin Forme in the Distortion World, then back
--   changedeoxysform      -- the Veilstone meteorites
--   clear/getamitysquarestepcount -- the gift-giver's counter, which
--                            `Field_ProcessStep` advances on every step
--   Giratina follows its held item: Origin exactly while holding the
--   Griseous Orb (`BoxPokemon_SetGiratinaForm`), re-applied on give/take.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: texlua tools/gen4_party_forms_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local data = {
  pokemon = assert(loadfile(cacheDir .. '/pokemon.lua'))(),
  constants = assert(loadfile(cacheDir .. '/constants.lua'))(),
}
data.constants.gen = data.constants.gen or 4
-- The same normalisation `Data` applies at load (src/core/Data.lua): the cache
-- names Sp. Atk `spAttack` and the EV yield `evYields`; the engine reads
-- `spatk` and `evYield`.
for _, def in pairs(data.pokemon) do
  local bs = type(def) == 'table' and def.baseStats
  if type(bs) == 'table' and bs.spatk == nil and bs.spAttack ~= nil then
    bs.spatk, bs.spdef, bs.special = bs.spAttack, bs.spDefense, bs.spAttack
  end
  if type(def) == 'table' and def.evYield == nil and type(def.evYields) == 'table' then
    def.evYields.spatk = def.evYields.spatk or def.evYields.spAttack
    def.evYields.spdef = def.evYields.spdef or def.evYields.spDefense
    def.evYield = def.evYields
  end
end

local Forms = require('src.pokemon.Gen4Forms')
local Stats = require('src.pokemon.Stats')

local function giratina(item, hp)
  local mon = { species = 487, level = 50, form = 0, item = item,
                ivs = { hp = 31, attack = 31, defense = 31, spatk = 31, spdef = 31, speed = 31 },
                evs = {}, nature = 0, personality = 0 }
  mon.stats = Stats.calc(Forms.definition(data, mon), 50, mon.ivs, nil, mon.evs, 0)
  mon.hp = hp or mon.stats.hp
  return mon
end

-- ============================ 1. a form change is a stat change
local altered = giratina(nil)
local base = Forms.definition(data, altered).baseStats
local originMon = giratina(nil)
Forms.setForm(data, originMon, 1)
local origin = Forms.definition(data, originMon).baseStats
check(base and origin and base.attack ~= origin.attack,
      'Origin Forme must read its own personal row -- base atk '
      .. tostring(base and base.attack) .. ' vs ' .. tostring(origin and origin.attack))
check(originMon.stats.attack ~= altered.stats.attack, 'and the stats must be recalculated')

-- HP moves by the change in max HP; a fainted mon stays fainted.
local hurt = giratina(nil, 10)
local oldMax = hurt.stats.hp
Forms.setForm(data, hurt, 1)
check(hurt.hp == 10 + (hurt.stats.hp - oldMax), 'HP shifts by the max-HP change')
local fainted = giratina(nil, 0)
Forms.setForm(data, fainted, 1)
check(fainted.hp == 0, 'a fainted Giratina stays fainted')

-- ============================ 2. the Griseous Orb
local g = giratina(112)
check(Forms.giratinaByHeldItem(data, g) == 1 and g.form == 1,
      'holding the Griseous Orb is Origin Forme')
g.item = nil
check(Forms.giratinaByHeldItem(data, g) == 0 and g.form == 0, 'and without it, Altered')
check(Forms.giratinaByHeldItem(data, { species = 25, form = 0 }) == nil,
      'and no other species is touched')
-- ...through the bag, where the party menu gives and takes.
local Bag = require('src.inventory.Bag')
local save = { inventory = { [112] = 1 }, bagOrder = { 112 } }
local held = giratina(nil)
local okGive, whyGive = pcall(Bag.giveHeld, save, held, 112, data)
if not okGive then print('giveHeld raised: ' .. tostring(whyGive)) end
check(held.form == 1, 'giving the Orb must make Giratina Origin Forme')
pcall(Bag.takeHeld, save, held, data)
check(held.form == 0, 'and taking it back, Altered')

-- ============================ 3. the script commands
local VM = require('src.script.Gen4ScriptVM')
local function lowers(name, args, want)
  local rows = VM.lower({ { name = name, args = args } })
  check(rows[1] and rows[1][1] == want, name .. ' must lower to ' .. want
        .. ', got ' .. tostring(rows[1] and rows[1][1]))
end
lowers('setpartygiratinaform', { 1 }, 'g4_giratina_form')
lowers('changedeoxysform', { 0x8004 }, 'g4_deoxys_form')
lowers('clearamitysquarestepcount', {}, 'g4_clear_amity_steps')
lowers('getamitysquarestepcount', { 0x800C }, 'g4_get_amity_steps')

local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local partySave = { party = { giratina(112), giratina(nil), { species = 25, level = 5 } },
                    pokedex = {}, gen4Vars = {} }
local ctx = { save = partySave, game = { data = data, save = partySave } }
C.g4_giratina_form(ctx, 1)
check(partySave.party[1].form == 1 and partySave.party[2].form == 1,
      'setpartygiratinaform 1 makes every Giratina Origin Forme')
C.g4_giratina_form(ctx, 0)
check(partySave.party[1].form == 1 and partySave.party[2].form == 0,
      'and 0 puts each back by its held item')
check(partySave.party[3].form == nil, 'leaving other species alone')

local deo = { species = 386, level = 50, form = 0, ivs = {}, evs = {}, nature = 0 }
deo.stats = Stats.calc(Forms.definition(data, deo), 50, deo.ivs, nil, deo.evs, 0)
deo.hp = deo.stats.hp
local dsave = { party = { deo }, pokedex = {}, gen4Vars = { [0x8004] = 2 } }
C.g4_deoxys_form({ save = dsave, game = { data = data, save = dsave } }, 0x8004)
check(deo.form == 2, 'changedeoxysform takes its form from a var')

-- ============================ 4. Amity Square's counter
local OW = require('src.world.OverworldController')
for i = 1, 200 do
  local name = debug.getupvalue(OW.gen4CountAmityStep, i)
  if name == nil then break end
  if name == 'Game' then debug.setupvalue(OW.gen4CountAmityStep, i, { save = dsave }) break end
end
local walker = setmetatable({ map = { def = { generation = 4 } } }, { __index = OW })
walker:gen4CountAmityStep(); walker:gen4CountAmityStep()
check(dsave.gen4Vars[0x403A] == 2, 'every step counts')
dsave.gen4Vars[0x403A] = 10000
walker:gen4CountAmityStep()
check(dsave.gen4Vars[0x403A] == 10000, 'saturating at 10,000')
local actx = { save = dsave }
C.g4_get_amity_steps(actx, 0x800C)
check(dsave.gen4Vars[0x800C] == 10000, 'the script reads it')
C.g4_clear_amity_steps(actx)
check(dsave.gen4Vars[0x403A] == 0, 'and clears it')
local ow = io.open('src/world/OverworldController.lua'):read('a')
check(ow:find('self:gen4CountAmityStep()', 1, true), 'and the step handler counts')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
