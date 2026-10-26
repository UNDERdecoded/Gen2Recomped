package.path = "./?.lua;./?/init.lua;" .. package.path
local T, Copy = require("tests.modkit"), require("src.mods.Merge").deepCopy
local B = require("src.battle.Gen3BatonPass")
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ "override", "delegate", "called" }) do
    local f = require("tests.enemy_actions.baton_pass").fixture(".", "gen2", version)
    local c = f.fresh("TACKLE")
    local b, donor = c.battle, c.user
    b:syncSides()
    b.game.save.party[2] = Copy(donor.mon)
    b.game.save.party[2].nickname = "BENCH"
    donor.mon.moves = { { id = f.ids.BATON_PASS, pp = 20 }, { id = f.ids.TACKLE, pp = 10 } }
    donor.curMoves = donor.mon.moves
    donor.stages.defense = 2
    local calls, phases = 0, {}
    local original = b.holdItemTrigger
    b.holdItemTrigger = function(self, who, phase)
      phases[#phases + 1] = phase
      return original(self, who, phase)
    end
    local record = Copy(b.data.move_effects.BATON_PASS_EFFECT)
    if mode == "override" then
      record.run = function()
        calls = calls + 1
        return {}
      end
      b.data.move_effects.BATON_PASS_EFFECT = record
    elseif mode == "delegate" then
      local builtin = record.run
      record.run = function(ctx)
        calls = calls + 1
        return builtin(ctx)
      end
      b.data.move_effects.BATON_PASS_EFFECT = record
    else
      b.data.move_effects.CALL_BATON = {
        kind = "full",
        callsMove = function()
          calls = calls + 1
          return f.ids.BATON_PASS
        end,
      }
      b.data.moves[f.ids.TACKLE].effect = "CALL_BATON"
    end
    local action = donor.curMoves[mode == "called" and 2 or 1]
    b:performMove(donor, donor, action)
    T.eq(calls, 1, "authored effect is called exactly once")
    if mode == "override" then
      T.eq(b.player, donor, "authored override is not replaced by native behavior")
      T.eq(b._gen3BatonPending, nil, "authored override does not open an unwanted picker")
    else
      local pending = b._gen3BatonPending
      T.check(pending ~= nil, "delegated or called native command pauses for selection")
      T.eq(#phases, 0, "native item phases do not run before nested choice completion")
      T.check(B.select(b, assert(pending), 2), "nested selection accepts the intended replacement")
      B.await(b, pending)
      T.eq(b.player.mon, b.game.save.party[2], "native continuation switches after authored composition")
      T.eq(b.player.stages.defense, 2, "authored composition retains native transfer")
      T.eq(
        table.concat(phases, ","),
        "entry,moveEnd,moveEnd,action,action",
        "nested completion runs each native item phase once"
      )
      T.eq(
        donor.mon.moves[1].pp,
        mode == "called" and 20 or 19,
        "composition preserves called-move PP semantics"
      )
      T.eq(donor.mon.moves[2].pp, mode == "called" and 9 or 10, "only the calling move spends its own PP")
    end
    f.close()
  end
end
T.finish("native Baton Pass authored effects and called-move scheduling")
