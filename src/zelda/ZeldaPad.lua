-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- CONTROLLERS IN THE ZELDA RUNTIME (bug99, 2026-11-24).
--
-- Reported: "some Bluetooth controllers don't work" in A Link to the Past and
-- The Minish Cap, while the same pads work in the Pokemon games and the
-- launcher. Both runtimes share src/core/Input.lua, but the Zelda host's pad
-- callbacks were thinner than Game.lua's:
--
--   * a stick SDL has no game-controller mapping for (isGamepad() false: many
--     Bluetooth pads in D-input / Android / "PC" mode, some Switch Pro and
--     PlayStation pads over Bluetooth) only raises joystick* events. Its raw
--     button table (GamepadMap.RAW_BUTTON_BINDINGS) had no L or R, so on such
--     a pad the Zelda games lost L and R -- in A Link to the Past R is the
--     item button (or the action in cartridge mode 0) and L the map, in The
--     Minish Cap R is the action (talk, lift, roll) and L the Kinstone. The
--     Pokemon games barely use L / R, which is why they "work". Fixed in
--     GamepadMap (raw buttons 5 / 6 = L / R, the shoulder pair in both the
--     XInput and the generic D-input numbering), for every game.
--   * the triggers and the right stick never became the bindable
--     pseudo-buttons (Input.AXIS_BUTTONS) in Zelda: Game:gamepadaxis runs
--     Input:axisTransitions, the Zelda host did not, so a trigger bound in
--     CONTROLS (and LT's chat default) did nothing in Zelda.
--   * raw joystick events did not hide the touch overlay (Game:joystick*
--     call TouchControls:noteGamepad), and the accelerometer guard was
--     missing, so a phone's sensor "joystick" could steer Link.
--
-- install(R) replaces the host's pad callbacks with ones that follow
-- Game.lua's, keeping the Zelda-only part (guide = the system menu).

local P = {}

local function isAccelerometer(joystick)
  local ok, name = pcall(function() return joystick and joystick.getName and joystick:getName() end)
  return ok and type(name) == "string" and name:lower():find("accelerometer", 1, true) ~= nil
end

local function noteGamepad(host)
  if host.touch then pcall(host.touch.noteGamepad, host.touch) end
end

function P.install(R)
  local Host = R.Host
  if not Host or Host._zeldaPad then return end
  Host._zeldaPad = true
  local Input = require("src.core.Input")

  function Host:gamepadpressed(joystick, button)
    noteGamepad(self)
    if button == "guide" then
      if self.menu then self:closeMenu() else self:openMenu() end
      return
    end
    Input:gamepadpressed(joystick, button)
  end

  function Host:gamepadreleased(joystick, button)
    Input:gamepadreleased(joystick, button)
  end

  function Host:gamepadaxis(joystick, axis, value)
    value = tonumber(value) or 0
    if math.abs(value) > 0.5 then noteGamepad(self) end
    -- the triggers and the right stick as bindable pseudo-buttons, exactly
    -- as Game:gamepadaxis does (no CONTROLS capture runs in this runtime)
    for _, t in ipairs(Input:axisTransitions(axis, value)) do
      Input:padButton(t[1], t[2])
    end
    Input:gamepadaxis(joystick, axis, value)
  end

  function Host:joystickpressed(joystick, button)
    if isAccelerometer(joystick) then return end
    noteGamepad(self)
    Input:joystickpressed(joystick, button)
  end

  function Host:joystickreleased(joystick, button)
    if isAccelerometer(joystick) then return end
    Input:joystickreleased(joystick, button)
  end

  function Host:joystickaxis(joystick, axis, value)
    if isAccelerometer(joystick) then return end
    if math.abs(tonumber(value) or 0) > 0.5 then noteGamepad(self) end
    Input:joystickaxis(joystick, axis, value)
  end

  function Host:joystickhat(joystick, hat, direction)
    if isAccelerometer(joystick) then return end
    if direction ~= "c" then noteGamepad(self) end
    Input:joystickhat(joystick, hat, direction)
  end
end

return P
