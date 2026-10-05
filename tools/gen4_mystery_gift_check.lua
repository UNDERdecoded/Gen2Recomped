-- Run:  texlua tools/gen4_mystery_gift_check.lua <cache dir>
--
-- PLATINUM'S MYSTERY GIFTS (src/pokemon/Gen4MysteryGift.lua, the deliveryman
-- commands in src/script/Gen4Commands.lua): the command's width, the mart
-- OnTransition that hides him unless a gift waits, the handlers, the
-- distribution magic numbers, and this port's one-gift-per-induction offer.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end

local Ops = require('src.import.Gen4ScriptOps')
local function u16(v) return string.char(v % 256, math.floor(v / 256)) end
-- MysteryGiftGive: a u16 stage, then 1 var for stages 1-3, 2 for 5-6, none else
local widths = { [0] = 4, 6, 6, 6, 4, 8, 8, 4, 4 }
for stage = 0, 8 do
  check(Ops.sizeAt(0x23E, u16(0x23E) .. u16(stage) .. u16(0x40ED) .. u16(0x8006), 1) == widths[stage],
    ('mysterygiftgive stage %d is %d bytes'):format(stage, widths[stage]))
end
check(Ops.sizeAt(0x23E, u16(0x23E) .. u16(9), 1) == nil, 'an unknown stage has no width')

-- the decoded mart OnTransition (common script 10200) reaches the hide flag
local scripts = load('map_scripts')
local found, seen = false, {}
local function walk(t)
  if found or type(t) ~= 'table' or seen[t] then return end
  seen[t] = true
  if t.name == 'mysterygiftgive' and t.args and t.args[1] == 1 and t.args[2] == 0x40ED then found = true return end
  for _, v in pairs(t) do walk(v) end
end
walk(scripts)
check(found or scripts == nil, 'the OnTransition decodes CheckAvailableMysteryGift VAR_AVAILABLE_MYSTERY_GIFT_EXISTS')

-- the commands
package.loaded['src.script.Commands'] = { meta = {} }
require('src.script.Gen4Commands')
local C = package.loaded['src.script.Commands']
local MG = require('src.pokemon.Gen4MysteryGift')
local items = { [454] = { name = "Member Card" }, [452] = { name = "Oak's Letter" }, [455] = { name = 'Azure Flute' } }
local save = { gen4Vars = {}, inventory = {}, party = {}, player = { name = 'LUCAS' }, hallOfFame = {} }
local game = { data = { items = items, pokemon = { [490] = { name = 'Manaphy' } } }, save = save, stringBuffers = {} }
local ctx = { save = save, game = game }
C.g4_mystery_gift(ctx, 1, 0x40ED)
check(save.gen4Vars[0x40ED] == 0, 'no gift waiting: the deliveryman is hidden')
check(MG.owed(save) == 0, 'no induction, nothing owed')
save.hallOfFame = { {} }
check(MG.owed(save) == 1 and #MG.available(save) == 4, 'one induction owes one of four gifts')
check(MG.choose(save, 'azure_flute'), 'choosing a gift')
check(MG.owed(save) == 0 and #MG.available(save) == 3, 'a taken gift leaves the list and the debt')
check(not MG.choose(save, 'azure_flute'), 'and cannot be taken twice')
C.g4_mystery_gift(ctx, 1, 0x40ED)
check(save.gen4Vars[0x40ED] == 1, 'a gift waiting: he appears')
C.g4_mystery_gift(ctx, 2, 0x8000)
check(save.gen4Vars[0x8000] == 10, 'its type is MYST_GIFT_AZURE_FLUTE (10)')
C.g4_mystery_gift(ctx, 3, 0x8001)
check(save.gen4Vars[0x8001] == 1, 'the bag can take it')
C.g4_mystery_gift(ctx, 5, 0x8005, 0x8006)
check(save.gen4Vars[0x8005] == 379 and save.gen4Vars[0x8006] == 16, 'bank 379, MysteryGiftDeliveryman_Text_ReceivedAzureFlute')
check(game.stringBuffers[1] == 'LUCAS' and game.stringBuffers[2] == 'Azure Flute', 'player and item buffered')
C.g4_check_distribution_event(ctx, 2, 0x8002)
check(save.gen4Vars[0x8002] == 0, 'before GIVE the Arceus event is off')
C.g4_mystery_gift(ctx, 4)
check(save.inventory[455] == 1, 'GIVE puts the Azure Flute in the bag')
check(save.gen4Vars[0x4045] == 0x1123, 'and sets VAR_DISTRIBUTION_EVENT_ARCEUS to 0x1123')
C.g4_check_distribution_event(ctx, 2, 0x8002)
check(save.gen4Vars[0x8002] == 1, 'Spear Pillar / Hall of Origin now see the event')
C.g4_mystery_gift(ctx, 1, 0x40ED)
check(save.gen4Vars[0x40ED] == 0, 'the slot is freed: he is gone next time')

-- Oak's Letter also starts the Shaymin event
save.hallOfFame = { {}, {} }
MG.choose(save, 'oaks_letter')
C.g4_mystery_gift(ctx, 4)
check(save.gen4Vars[0x4044] == 0x1112 and save.gen4Vars[0x4057] == 1, "Oak's Letter: 0x1112 and VAR_SHAYMIN_EVENT_STATE 1")

-- the Manaphy Egg needs room in the party
save.hallOfFame = { {}, {}, {} }
MG.choose(save, 'manaphy_egg')
save.party = { {}, {}, {}, {}, {}, {} }
C.g4_mystery_gift(ctx, 3, 0x8001)
check(save.gen4Vars[0x8001] == 0, 'a full party cannot take the Manaphy Egg')
C.g4_mystery_gift(ctx, 6, 0x8005, 0x8006)
check(save.gen4Vars[0x8006] == 4, '...and he says so (CannotGivePokemon_PartyFull)')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
