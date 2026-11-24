-- Round 97: Link's roll as the cartridge runs it -- its speed and its length come from ANIM_ROLL's keyframes.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc src/player.c PlayerRollInit / PlayerRollUpdate):
--   * every roll frame, before UpdateAnimationSingleFrame, the current keyframe's flag byte (super->frame) picks the
--     speed: low nibble 0 -> kWalkSpeedRolling ($200), 1 -> speed += $20, 2 -> $300, 3 -> 0 (other values keep it);
--     then CheckPlayerVelocity / UpdatePlayerMovement move Link that far in his (idle) facing;
--   * `(super->frame & 0x10) == 0` (and not Minish) -> hurtType 0: no damage on those frames;
--   * the roll ends on the frame whose keyframe carries ANIM_DONE ($80) -- after that frame's move
--     (ResetPlayerAnimationAndAction).
--   ANIM_ROLL's keyframes in the ROM make a roll of 26 moving frames, about 60 px.  The port rolled a fixed
--   16 frames at $200 (32 px) and could be hit all the way through.
-- The speeds are the engine's constants (kWalkSpeedRolling); the keyframes are read from the imported sprite at run
-- time -- no game data here.
-- SIMPLIFIED: gPlayerState.speed_modifier (slopes) is not added; FX_DASH every 4 frames is not drawn.
--
-- Wraps Player.update / Player.hurt at require time (guard Player.roll97Installed); listed in R27A.MODULES.
local bit = require("bit")
local band = bit.band

local M = {}

M.ROLL, M.ROLL_STEP, M.ROLL_FAST = 0x200, 0x20, 0x300

-- the speed (Q8.8) for a keyframe flag byte, from the previous speed
function M.speedFor(flags, prev)
  local c = band(flags or 0, 0xF)
  if c == 0 then return M.ROLL
  elseif c == 1 then return (prev or M.ROLL) + M.ROLL_STEP
  elseif c == 2 then return M.ROLL_FAST
  elseif c == 3 then return 0 end
  return prev or M.ROLL
end

-- true when the roll frame takes no damage (hurtType 0)
function M.noHurt(p)
  return p.state == "roll" and not p.minish and p.roll97 ~= nil and band(p.roll97.flags or 0x10, 0x10) == 0
end

-- before the port's roll branch runs: set its speed and length for this frame from the keyframe
function M.pre(p, Player)
  local a = p.anim
  if not (a and a.keys) then p.roll97 = nil return nil end -- no ROM animation (stand-in assets): the old roll
  local r = p.roll97
  if not r or r.anim ~= p.animId then r = { anim = p.animId, spd = M.ROLL } p.roll97 = r end
  r.flags = a.flags or 0
  r.spd = M.speedFor(r.flags, r.spd)
  p.timer = a.done and 1 or 1000
  return r.spd / 256
end

function M.install()
  local okP, Player = pcall(require, "src.zelda.tmc.Player")
  if not okP or type(Player) ~= "table" or Player.roll97Installed then return end
  Player.roll97Installed = true
  local upd0, hurt0 = Player.update, Player.hurt
  Player.update = function(self, input)
    if self.state ~= "roll" then
      self.roll97 = nil
      return upd0(self, input)
    end
    local spd = M.pre(self, Player)
    if not spd then return upd0(self, input) end
    local s0 = Player.ROLL_SPEED
    Player.ROLL_SPEED = spd
    local ok, err = pcall(upd0, self, input)
    Player.ROLL_SPEED = s0
    if not ok then error(err, 0) end
    if self.state ~= "roll" then self.roll97 = nil end
  end
  Player.hurt = function(self, damage, sx, sy)
    if M.noHurt(self) then return false end
    return hurt0(self, damage, sx, sy)
  end
end
M.install()

return M
