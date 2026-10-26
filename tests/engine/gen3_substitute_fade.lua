package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/substitute_fade.lua").run(".", "gen2", version)
  T.eq(#rows, 144, "all native fade actors/options/presentation states execute")
  for _, row in ipairs(rows) do
    local last, index = row.frames[#row.frames], row.actor + 1
    T.check(last.done, "native fade returns to the actual queue")
    T.eq(#row.sounds, 0, "native Substitute fade remains silent")
    for _, frame in ipairs(row.frames) do
      T.eq(frame.rng, 0, "fade never draws battle RNG")
      for _, state in ipairs(frame.states) do
        T.eq(state.hp, 400, "fade never changes actual Pokemon HP")
      end
    end
    if row.case == "hidden" then
      T.eq(#row.frames, 1, "hidden Substitute exchanges without animation or pause")
    else
      local x = row.double and ({ 32, 200, 90, 152 })[index] or (row.actor == 0 and 72 or 176)
      local outward = row.actor % 2 == 0 and math.floor((x + 32) / 5) + 1
        or math.floor((304 - x - 32) / 5) + 1
      T.eq(#row.frames, 58 + outward * 2, "fade tasks, script delays and swap retain native ticks")
      T.eq(row.frames[5].states[index].alpha, 15 / 16, "first alpha decrement follows three callbacks")
      T.eq(row.frames[50].states[index].alpha, 0, "sixteen alpha steps finish before sprite exchange")
      T.eq(row.frames[18].states[index].coeff, 1, "white palette ramp reaches sixteen of sixteen")
      T.eq(row.frames[58].states[index].coeff, 0, "native palette reset precedes outward swap")
      T.eq(last.states[index].alpha, 1, "exchange restores Pokemon alpha")
    end
    T.eq(last.states[index].x, 0, "completed fade releases sprite offset")
    T.eq(
      last.states[index].substitute,
      row.case == "substitute" or row.case == "lowered-substitute",
      "queue completion reconciles logical protection after the temporary sprite exchange"
    )
  end
  local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
  local b, target = f.field(false), f.actor(1)
  target.substituteHP = 5
  T.eq(
    b:applyDamage(target, 8, true, { bandRolled = true }),
    5,
    "real damage absorbs only remaining protection"
  )
  T.eq(target.substituteHP, nil, "logical protection breaks immediately")
  T.eq(target.mon.hp, 400, "native break does not spill damage into Pokemon HP")
  T.eq(b:substituteVisible(target), true, "queued break retains the doll until presentation executes")
  T.eq(b.queue[1].anim, "SUBSTITUTE_FADE", "actual damage path queues native general animation")
  T.eq(b.queue[1].attackerPosition, 1, "broken recipient owns the animation")
  T.check(type(b.queue[2].text) == "string", "native animation precedes the break message")
  f.close()
end
T.finish("native GBA Substitute break producer and full fade controller")
