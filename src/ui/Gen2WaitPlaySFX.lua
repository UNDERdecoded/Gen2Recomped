-- Adapted from Gen1Recomp 535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91.
-- Existing project rights and Gen1Recomp provenance remain applicable; see LICENSE.MD.
local WaitPlaySFX = {}

function WaitPlaySFX.step(game)
  local speed = game and type(game.logicSpeed) == "function" and game:logicSpeed() or 1
  if type(speed) ~= "number" or speed ~= speed or speed < 1 or speed == math.huge then speed = 1 end
  return 1 / speed
end

local function sound()
  local ok, mod = pcall(require, "src.core.Sound")
  return ok and type(mod) == "table" and mod or nil
end

-- home/audio.asm:220 WaitPlaySFX
-- home/delay.asm:15
function WaitPlaySFX.arm(name, fallback)
  local Sound = sound()
  -- Wait on the engine's actual source; the frame budget bounds a stuck
  -- device. Missing/headless effects finish immediately.
  return { name = name, left = math.max(1, tonumber(fallback) or 180) }
end

-- home/audio.asm:225 WaitSFX
function WaitPlaySFX.waiting(pending, game)
  if not pending then return false end
  pending.left = (pending.left or 0) - WaitPlaySFX.step(game)
  if pending.left <= 0 then return false end
  local Sound = sound()
  if not Sound then return false end
  if Sound.sfxBusy and Sound.sfxBusy() then return true end
  return (Sound.isPlaying and Sound.isPlaying(pending.name)) or false
end

return WaitPlaySFX
