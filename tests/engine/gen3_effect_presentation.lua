package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/battle_effect_presentation.lua").run(".", "gen2", version)
  T.eq(#rows, 192, "all native effects/actors/options/protection inputs execute")
  for _, row in ipairs(rows) do
    local last = row.frames[#row.frames]
    T.check(last.done, "actual native effect queue completes")
    for _, frame in ipairs(row.frames) do
      T.eq(frame.rng, 0, "presentation never consumes battle RNG")
    end
    local positive = row.scene
      and (row.case == "ordinary" or row.name == "FOCUS_BAND" and row.case == "lowered-substitute")
    if positive and row.name == "POISON" then
      T.eq(#row.frames, 72, "native poison waits for all six sounds and visual tasks")
      T.eq(row.frames[2].states[row.actor + 1].x, 1, "native initial shake starts on the actual actor")
      T.eq(
        row.frames[27].states[row.actor + 1].coeff,
        0.75,
        "native first color cycle reaches twelve of sixteen"
      )
      T.eq(last.states[row.actor + 1].x, 0, "native shake restores its original coordinate")
      T.eq(last.states[row.actor + 1].coeff, 0, "native palette cycle releases its tint")
      for i, sound in ipairs(row.sounds) do
        T.eq(sound.tick, 1 + (i - 1) * 14, "native loop counter owns the sound timing")
        T.eq(sound.id, version == "firered" and 141 or 148, "native sound index follows the actual edition")
        T.eq(sound.pan, row.actor % 2 == 0 and -64 or 63, "actual output source uses native side panorama")
        T.eq(sound.mono, not row.stereo, "actual output source respects the native sound option")
      end
    elseif positive then
      T.eq(#row.frames, 123, "native Focus Band waits for both fades, delay and signed fixed-point return")
      T.eq(#row.sounds, 1, "native Focus Band plays exactly one sound")
      local index = row.actor + 1
      T.eq(row.frames[2].states[index].x, 0, "motion initialization does not advance its ramp")
      T.eq(row.frames[48].states[index].coeff, 9 / 16, "odd fade target is clamped to nine of sixteen")
      T.eq(
        row.frames[62].states[index].x,
        row.actor % 2 == 0 and -13 or 17,
        "native side-specific ramp and jitter"
      )
      T.eq(
        row.frames[122].states[index].x,
        row.actor % 2 == 0 and -1 or 0,
        "signed return truncates then shifts"
      )
      T.eq(last.states[index].x, 0, "completed Focus Band restores actor position")
      T.eq(last.states[index].coeff, 0, "completed Focus Band releases palette ownership")
      local sound = row.sounds[1]
      T.eq(sound.tick, 1, "native Focus Band sound starts on its first update")
      T.eq(sound.id, version == "firered" and 164 or 171, "native Focus Band sound follows edition")
      T.eq(sound.pan, row.actor % 2 == 0 and -64 or 63, "Focus Band sound uses the actual actor's panorama")
      T.eq(sound.mono, not row.stereo, "Focus Band sound respects native mono/stereo")
    elseif row.name == "FOCUS_BAND" and not row.scene then
      T.eq(#row.frames, 34, "disabled general animations retain their native 32-frame pause")
      T.eq(#row.sounds, 0, "disabled general animations are silent")
    else
      T.eq(#row.frames, 1, "native skipped status animation adds no waiting tick")
      T.eq(#row.sounds, 0, "native skipped status animation is silent")
    end
  end
end
T.finish("native GBA status and Focus Band presentation with actual sound controls")
