-- Run:  python tools/run_lua_check.py tools/gen4_tag_battle_check.lua <platinum cache dir>
--
-- TAG BATTLES (src/battle/AllyAI.lua, BattleState's `ally`, Gen4Commands'
-- allyFor / escortAlly): the partner's team is built from their trainer
-- record, stands in the player's right-hand slot, picks its own moves, draws
-- replacements from its own party, and keeps the player's side in the fight.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
require('src.core.GameVersion').set('platinum')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/platinum/data/generated'):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local moves = load('moves')
local data = { moves = moves, type_chart = load('type_chart'), constants = load('constants') }
local TypeChart = require('src.battle.TypeChart')
pcall(TypeChart.load, data)
local AllyAI = require('src.battle.AllyAI')

-- ------------------------------------------------------------ the choice --
local function mv(id, pp) return { id = id, pp = pp or 10 } end
local function foe(name, types, hp) return { name = name, curTypes = types, mon = { hp = hp or 50 } } end
local water, fire = foe('WATER', { 'WATER' }), foe('FIRE', { 'FIRE' })
local battle = { data = data, foesOf = function() return { water, fire } end }
local ally = { position = 2, curTypes = { 'WATER' }, curMoves = { mv(33), mv(55) } }   -- Tackle, Water Gun
local pick = AllyAI.choose(battle, ally, function(a) return a end)
check(pick.id == 55 and battle.chosenTargets[2] == fire, 'Water Gun on the Fire type: power x effectiveness x STAB')
local tired = { position = 2, curTypes = {}, curMoves = { mv(33, 0) } }
check(AllyAI.choose(battle, tired).struggle, 'no PP anywhere: Struggle')
local fainted = { data = data, foesOf = function() return { foe('X', { 'NORMAL' }, 0) } end }
local status = { position = 2, curTypes = {}, curMoves = { mv(45) } }                  -- Growl
check(AllyAI.choose(fainted, status, function(a) return a end).id == 45, 'nothing to hurt: something usable')

-- -------------------------------------------------------------- the team --
local trainers = load('trainers')
-- a non-English cache (gen4_language.lua) names the partners in its own language;
-- the records are still the same two (613 / 608), so it asserts the name is a real
-- one, and that the two differ
local langChunk = loadfile(dir .. '/gen4_language.lua')
if langChunk and langChunk() then
  local a, b = trainers and trainers[613] and trainers[613].name, trainers and trainers[608] and trainers[608].name
  check(type(a) == 'string' and a ~= '' and not a:find('{', 1, true), 'trainer 613 is Jubilife\'s partner, named in the cartridge language')
  check(type(b) == 'string' and b ~= '' and a ~= b, 'trainer 608 is the Eterna Forest partner, named in the cartridge language')
else
  check(trainers and trainers[613] and trainers[613].name == 'Lucas', 'trainer 613 is Lucas (Jubilife\'s partner)')
  check(trainers and trainers[608] and trainers[608].name == 'Cheryl', 'trainer 608 is Cheryl (Eterna Forest)')
end

-- ------------------------------------------------------------ the wiring --
local bs = src('src/battle/BattleState.lua')
check(bs:find('function BattleState:setAlly(ally)', 1, true), 'BattleState:setAlly')
check(bs:find('if isPlayer and self.ally and position == BattleState.POS.PLAYER_RIGHT then', 1, true),
  'the partner\'s replacements come from the partner\'s party')
check(bs:find('self.ally and { BattleState.POS.PLAYER_LEFT,', 1, true),
  'the player\'s side fights on while the partner has anybody')
check(bs:find('if battler.ally then', 1, true) and bs:find('require("src.battle.AllyAI").choose', 1, true),
  'the partner chooses for itself')
check(bs:find('if b and not b.ally then return p end', 1, true), 'the menu never asks for the partner')
check(bs:find('BattleState.buildTrainerParty = buildTrainerParty', 1, true), 'trainer parties can be built for an ally')
local g4 = src('src/script/Gen4Commands.lua')
check(g4:find('function Gen4Commands.allyFor', 1, true) and g4:find('Gen4Commands.VAR_PARTNER_TRAINER_ID = 0x403F', 1, true),
  'starttagbattle\'s partner, and an escort\'s (FLAG_HAS_PARTNER + VAR_PARTNER_TRAINER_ID 0x403F)')
check(src('src/script/Commands.lua'):find('if opts and opts.ally then battle:setAlly(opts.ally) end', 1, true),
  'start_battle takes an ally')

-- ------------------------------------------------- escort wild battles --
-- WildEncounters_TryWildEncounter's withPartner arm: BATTLE_TYPE_AI_PARTNER,
-- two wild Pokemon in the grass, no roamers, and the party healed after
local ow = src('src/world/OverworldController.lua')
check(ow:find('elseif (enc or self.gen45RollPassed) and GameVersion.isGen4() and not self:gen4Escorted() then', 1, true),
  'no roamer joins a partner battle (TryEncounterRoamer is asked only without one)')
check(ow:find('function OverworldState:gen4EscortWild(battle, onWater, land)', 1, true)
  and ow:find('battle:makeWildDouble(second, ally)', 1, true), 'a step with a partner: the partner and two wild Pokemon')
check(ow:find('if not (enc2 and enc2.species) then return false end', 1, true),
  'a second draw turned away calls the whole encounter off')
check(ow:find('if battle and battle.gen4Escorted and result ~= "lose" then', 1, true)
  and src('src/script/Commands.lua'):find('if battle.ally and battle.ally.escort and result ~= "lose" then', 1, true),
  'Party_HealAllMembers after a wild or trainer battle not lost with a partner')
check(src('src/ui/BagMenu.lua'):find('battle:wildFoesStanding() > 1', 1, true),
  [["It's impossible to aim when there are two Pokemon!"]])
package.loaded['src.battle.BattleState'] = nil
local BS = require('src.battle.BattleState')
local function standing(hp1, hp2)
  local slots = { [1] = { mon = { hp = hp1 } }, [3] = hp2 and { mon = { hp = hp2 } } or nil }
  local fake = setmetatable({ double = true, battlerAt = function(_, p) return slots[p] end }, { __index = BS })
  return fake:wildFoesStanding()
end
check(standing(10, 10) == 2 and standing(10, 0) == 1 and standing(0, nil) == 0, 'wildFoesStanding counts the two')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
