-- Driver: prove the banded sky still paints from the ramp texture.
--
-- The bands used to reach the shader as `uniform vec3 bands[8]`, which on
-- Android delivered only its first few slots and painted the rest of the sky
-- black (see lib/Sky.lua, rampFor).  They are a texture now.  This checks the
-- three things that swap could have broken, on the machine it CAN be checked
-- on: that the shader still compiles, that the ramp is built and is one texel
-- per band, and that what lands on screen is still a gradient that pales
-- downward rather than a flat plate or a black one.
--
--   SHOT_DIR=.scratchpad/skyramp POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/sky_ramp_probe.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or ".scratchpad/skyramp"

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    U.log("DRAMATIC_SHAPE is not loaded -- enable it and run again")
    return
  end
  local Sky = lib.require("Sky")
  local DayNight = lib.require("DayNight")

  -- which copy of the mod is actually live: only the ramp build has this
  U.log("live copy has _rampFor:", tostring(Sky._rampFor ~= nil))
  U.log("shader compiled:", tostring(Sky._getShader() ~= nil))

  U.teleport(game, "PALLET_TOWN", 12, 10, "up")
  require("src.render.Pipelines").setLevel("voxel", 5)
  U.wait(150)

  for _, phase in ipairs({ "day", "dusk", "night" }) do
    DayNight.setting:sync(phase)
    DayNight.update(0)
    U.wait(30)

    local bands = Sky.bands()
    local ramp = Sky._rampFor and Sky._rampFor(bands)
    local w = ramp and ramp:getWidth() or -1
    U.log(("%s: %d bands, ramp %dx%d"):format(
      phase, #bands, w, ramp and ramp:getHeight() or -1))
    -- one texel per band is the whole contract: the shader divides by `count`
    -- and samples texel centres, so a ramp of any other width samples between
    -- bands or off the end
    if w ~= #bands then U.log("FAIL ramp width does not match band count") end
    -- and the ramp is the ramp: the same table gives the same image back
    if ramp ~= Sky._rampFor(bands) then U.log("FAIL ramp rebuilt per call") end

    U.shot(game, ("%s/%s.png"):format(DIR, phase))
  end

  DayNight.setting:sync("day")
  U.log("done -- " .. DIR)
end
