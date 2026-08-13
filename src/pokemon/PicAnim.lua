-- Crystal's front-pic frame animations.
--
-- Only Crystal has them.  Its front pics carry extra tiles past the body
-- (CYNDAQUIL decompresses to 49 tiles for a 5x5 pic), and four ROM tables
-- describe how to swap those tiles in over time.  The import side does all
-- the decoding -- see RomExtractorGen2:gen2PicAnimation -- and leaves one
-- record per species:
--
--   def.picAnim = {
--     sheet  = "assets/generated/battle/anim/<mon>.png",  -- frames 1..N
--     count  = N, width =, height =,
--     play   = { { frame =, dur = }, ... },   -- <Mon>Animation, flattened
--     idle   = { ... },                       -- <Mon>AnimationIdle
--   }
--
-- Frame 0 is the untouched front pic, so it is NOT in the sheet: callers
-- fall back to the still they already have.  Durations are plain 60Hz
-- frames -- PokeAnim_GetDuration folds in a speed scaler, but every entry in
-- the PokeAnims table (34:$4042) passes 0 for it.
--
-- Playback here is `play` once, then `idle` once, then a hold on frame 0 --
-- the still.  That is a real PokeAnims sequence (34:$405C is cry / setup /
-- play / setwait / wait / idle / play / finish); none of the nine loops
-- forever, and looping the idle script would leave CYNDAQUIL flaring its
-- back every second for the whole battle.  The animation therefore plays
-- when the mon appears and when the summary page opens, exactly like the
-- cartridge, and then the pic settles.

local PicAnim = {}
PicAnim.__index = PicAnim

-- One frame image sliced out of a species' strip, keyed "<sheet>@<index>".
-- Weak-valued: a species nothing is drawing right now can be collected.
local frames = setmetatable({}, { __mode = "v" })

local function invalidate() frames = setmetatable({}, { __mode = "v" }) end
require("src.render.Assets").register(invalidate)

-- The record for `species`, or nil on Gold/Silver and for anything the
-- import could not decode.
function PicAnim.record(data, species)
  local def = data and data.pokemon and data.pokemon[species]
  local anim = def and def.picAnim
  if type(anim) ~= "table" or not anim.sheet then return nil end
  if type(anim.play) ~= "table" and type(anim.idle) ~= "table" then
    return nil
  end
  return anim
end

-- Frame `index` (1-based) of `anim` as a standalone image, or nil.
-- Plain: no palette mapping, which is right for every caller that draws the
-- still pic plainly too (the summary page).  BattleState wants its own
-- SGB-coloured build and slices the strip itself.
function PicAnim.frameImage(anim, index)
  if not (anim and index and index >= 1 and index <= (anim.count or 0)) then
    return nil
  end
  local key = anim.sheet .. "@" .. index
  local hit = frames[key]
  if hit then return hit end
  local ok, image = pcall(function()
    local Assets = require("src.render.Assets")
    local strip = Assets.imageData(anim.sheet)
    local w, h = anim.width, anim.height
    local cell = love.image.newImageData(w, h)
    cell:paste(strip, 0, 0, (index - 1) * w, 0, w, h)
    return love.graphics.newImage(cell)
  end)
  if not ok or not image then return nil end
  frames[key] = image
  return image
end

-- A live player, or nil when this species has no animation.
--
-- It starts PAUSED on frame 0.  In battle the pic is not on screen yet when
-- the battler is built -- the silhouette slide and the "wants to fight!" box
-- come first, and a free-running clock would have burned the whole `play`
-- script before the mon was ever visible.  BattleState starts it on the
-- first frame it actually draws the pic; the summary screen, which is up
-- the moment it is constructed, starts it straight away.
function PicAnim.new(data, species)
  local anim = PicAnim.record(data, species)
  if not anim then return nil end
  local self = setmetatable({ anim = anim, paused = true }, PicAnim)
  self:restart("play")
  return self
end

function PicAnim:start()
  if not self.paused then return end
  self.paused = false
  self:restart("play")
end

function PicAnim:restart(which)
  local steps = self.anim[which]
  if type(steps) ~= "table" or not steps[1] then
    -- no such script: settle on the still and stop
    self.steps, self.index, self.left, self.which = nil, 1, 0, which
    return
  end
  self.which = which
  self.steps = steps
  self.index = 1
  self.left = steps[1].dur or 1
  self.clock = 0
end

-- dt in seconds; the scripts count 60Hz frames.
function PicAnim:update(dt)
  if self.paused or not self.steps then return end
  self.clock = (self.clock or 0) + (dt or 0) * 60
  while self.clock >= 1 do
    self.clock = self.clock - 1
    self.left = self.left - 1
    if self.left <= 0 then
      self.index = self.index + 1
      if not self.steps[self.index] then
        -- `play` hands over to `idle`; after `idle` the pic settles on the
        -- still and stays there until something restarts it
        if self.which ~= "play" then
          self.steps = nil
          return
        end
        self:restart("idle")
        if not self.steps then return end
      end
      self.left = self.steps[self.index].dur or 1
    end
  end
end

-- 0 = the untouched front pic.
function PicAnim:frame()
  if self.paused then return 0 end
  local step = self.steps and self.steps[self.index]
  return (step and step.frame) or 0
end

-- The current frame as an image, or nil to keep drawing the still.
function PicAnim:image()
  local index = self:frame()
  if index <= 0 then return nil end
  return PicAnim.frameImage(self.anim, index)
end

return PicAnim
