-- Adapted from Gen1Recomp 535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91.
-- Existing project rights and Gen1Recomp provenance remain applicable; see LICENSE.MD.
-- home/joypad2.asm:16-53 JoypadLowSensitivity (hJoy7 = 1, 30 then 5)
-- pokegold home/joypad.asm:313-340 JoyTextDelay (hInMenu, 15 then 5)

local MenuRepeat = {}

MenuRepeat.GEN1_DELAY, MenuRepeat.GEN1_RATE = 30, 5
MenuRepeat.GEN2_DELAY, MenuRepeat.GEN2_RATE = 15, 5

local ALL_DIRS = { "up", "down", "left", "right" }

function MenuRepeat.new(delay, rate, enabled)
  return {
    delay = tonumber(delay) or MenuRepeat.GEN1_DELAY,
    rate = math.max(1, tonumber(rate) or MenuRepeat.GEN1_RATE),
    enabled = enabled ~= false,
    dir = nil,
    frames = 0,
  }
end

function MenuRepeat.reset(state)
  state.dir, state.frames = nil, 0
end

function MenuRepeat.direction(state, input, dirs)
  for _, dir in ipairs(dirs or ALL_DIRS) do
    if input:wasPressed(dir) then
      state.dir, state.frames = dir, 0
      return dir, true
    end
  end
  local dir = state.dir
  if not (dir and state.enabled and input.isDown and input:isDown(dir)) then
    MenuRepeat.reset(state)
    return nil, false
  end
  state.frames = state.frames + 1
  local afterDelay = state.frames - state.delay
  if afterDelay >= 0 and afterDelay % state.rate == 0 then return dir, false end
  return nil, false
end

return MenuRepeat
