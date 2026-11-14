-- Run:  python tools/run_lua_check.py tools/gen4_party_pick_cancel_check.lua
--
-- A SCRIPT THAT OPENS THE PARTY TO PICK ONE MUST END WHEN THE PLAYER BACKS OUT.
--
-- `selectmovetutorpokemon` and the NPC-trade pickers (g4_open_party_for_trade)
-- push the party menu with `pickOnly` and yield; only `onSwitch` resumed the
-- runner. B / CANCEL goes through Gen4PartyMenu:close(), which calls
-- `onCancel` -- and the script passed none, so the coroutine stayed parked for
-- good, the field stayed locked behind the script's fade, and the Platinum
-- move-tutor and trade NPCs froze the game for anybody who changed their mind.
-- Found by tools/gen4_field_sweep (Route 205's / Solaceon's tutors).

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('Gen 4 party pick cancel')
require('src.core.GameVersion').set('platinum')
local Commands = require('src.script.Commands'); require('src.script.Gen4Commands')
local Runner = require('src.script.ScriptRunner')
local Screens = require('src.ui.Screens')
local push = Screens.push

local function scenario(answer)
  local game = { data = { pokemon = {}, constants = {} },
                 save = { party = { { species = 387 }, { species = 390 } }, flags = {}, player = {} } }
  local runner = Runner.new(game, {})
  local pushed
  Screens.push = function(_, id, opts) pushed = { id = id, opts = opts } end
  local reached = false
  Commands.pick_check_reached = function(ctx) reached = ctx.g4PartySlot end
  runner:run({ { 'g4_select_tutor_mon' }, { 'pick_check_reached' } })
  T.check(pushed and pushed.id == 'PartyMenu' and pushed.opts.pickOnly, 'the party opens as a picker')
  T.eq(runner:isRunning(), true, 'the script waits on the picker')
  if answer == 'cancel' then
    T.check(type(pushed.opts.onCancel) == 'function', 'B on the picker has a handler')
    pushed.opts.onCancel()
  else
    pushed.opts.onSwitch(game.save.party[2])
  end
  return runner, reached
end

local runner, reached = scenario('cancel')
T.eq(runner:isRunning(), false, 'cancelling the picker lets the script finish')
T.eq(reached, 0xFF, 'and the slot reads "none"')
runner, reached = scenario('pick')
T.eq(runner:isRunning(), false, 'picking a Pokemon still finishes the script')
T.eq(reached, 1, 'and the slot is the zero-based index')

Screens.push = push
Commands.pick_check_reached = nil
T.finish()
