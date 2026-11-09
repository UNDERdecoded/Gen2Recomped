-- Sprite animation playback, as the cartridge does it
-- (asm/src/code_08003FC4.s: InitializeAnimation, UpdateAnimationVariableFrames,
-- FrameZero).
--
-- An animation is a list of 4-byte keyframes {frame, duration, settings,
-- flags}.  `settings` bits $40/$80 flip the frame (XORed into the entity's
-- own flip), `flags` bit $80 marks the last keyframe and is followed by a
-- byte saying how many keyframes to step back (the loop).  A keyframe is
-- shown for `duration` frames; reaching the last one sets ANIM_DONE.

local bit = require("bit")
local band = bit.band

local Anim = {}
Anim.__index = Anim

Anim.DONE = 0x80

function Anim.new()
  return setmetatable({ sprite = nil, index = -1, key = 1, timer = 0, frame = 0xFF,
                        flip = 0, flags = 0, done = false }, Anim)
end

local function frameZero(self)
  local keys = self.keys
  local k = keys and keys[self.key]
  if not k then self.done = true; return end
  self.frame = k[1]
  self.timer = k[2]
  self.flip = k[3]
  self.flags = k[4]
  local nextKey = self.key + 1
  if band(k[4], 0x80) ~= 0 then
    self.done = true
    nextKey = nextKey - (keys.loopBack or 1)
    if nextKey < 1 then nextKey = 1 end
  end
  self.key = nextKey
end

-- start animation `index` of sprite table `spr` (Assets:sprite result)
function Anim:set(spr, index, force)
  if not force and self.sprite == spr and self.index == index then return end
  self.sprite, self.index = spr, index
  self.keys = spr and spr.anims and spr.anims[index]
  self.key = 1
  self.done = false
  frameZero(self)
end

-- advance `steps` frames (UpdateAnimationVariableFrames)
function Anim:update(steps)
  if not self.keys then return end
  steps = steps or 1
  for _ = 1, steps do
    self.timer = self.timer - 1
    if self.timer <= 0 then frameZero(self) end
  end
end

function Anim:hflip() return band(self.flip, 0x40) ~= 0 end
function Anim:vflip() return band(self.flip, 0x80) ~= 0 end

return Anim
