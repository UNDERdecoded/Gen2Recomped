-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ONE-SHOT MAP PROP ANIMATIONS -- a door opening, keyed by the script's tag.
--
-- The cartridge's `MapPropOneShotAnimationManager` is tag-keyed, and so is
-- this: `loaddooranimation` hands a tag, `playdooropenanimation` plays on that
-- tag, `waitforanimation` waits on that tag, `unloadanimation` releases it.
-- Keying on anything else -- the model, the tile -- would be a second spelling
-- of a join the scripts already make.
--
--     ScrCmd_WaitForAnimation:  u8 tag = ScriptContext_ReadByte(ctx);
--                               FieldSystem_WaitForAnimation(fieldSystem, tag);
--     FieldTask_WaitForAnimation: MapPropOneShotAnimationManager_
--                                   IsAnimationLoopFinished(..., *taskEnv)
--
-- THE OBJECT IS CARRIED BY IDENTITY, not by coordinates. `Gen4Doors.propAt`
-- finds the door in `terrain.chunks[land].objects`, and `Gen4Ground` iterates
-- that same table -- so the object found at load time IS the table the
-- renderer will draw, and matching it needs no second coordinate search that
-- could disagree with the first.
--
-- Place at: src/world/Gen4PropOneShot.lua

local Gen4PropOneShot = {}

local PropAnim = require("src.import.Gen4PropAnim")

local function store(ow)
  if type(ow) ~= "table" then return nil end
  ow.gen4OneShots = ow.gen4OneShots or {}
  return ow.gen4OneShots
end

-- start(ow, tag, model, action, object) -> true when something is running
--
-- A tag with no resolvable animation is NOT started, and that is deliberate:
-- `finished` must answer true for it immediately, so a `waitforanimation` on
-- a door this port could not identify steps over rather than hanging the
-- script. The old `g4_noop` lowering got that right by accident; this has to
-- get it right on purpose.
function Gen4PropOneShot.start(ow, tag, model, action, object)
  local slots = store(ow)
  if not slots then return false end
  tag = math.floor(tonumber(tag) or 0)
  local id = model and PropAnim.animationFor(model, action)
  local frames = id and PropAnim.framesFor(id)
  if not (id and frames and frames > 0) then
    slots[tag] = nil
    return false
  end
  slots[tag] = {
    tag = tag, model = model, action = action, object = object,
    animation = id, frames = frames, frame = 0,
  }
  return true
end

function Gen4PropOneShot.stop(ow, tag)
  local slots = store(ow)
  if not slots then return end
  slots[math.floor(tonumber(tag) or 0)] = nil
end

function Gen4PropOneShot.running(ow, tag)
  local slots = store(ow)
  if not slots then return nil end
  return slots[math.floor(tonumber(tag) or 0)]
end

-- finished(ow, tag) -- the question `waitforanimation` asks.
--
-- A tag that is not running is finished. There is no third answer: the
-- cartridge's `IsAnimationLoopFinished` is called on a tag that may never have
-- been loaded and the script must not stall on it.
function Gen4PropOneShot.finished(ow, tag)
  local slot = Gen4PropOneShot.running(ow, tag)
  if not slot then return true end
  -- A SLOT WITH NO LENGTH IS FINISHED TOO, and this is the same contract
  -- rather than a defensive hedge: a one-shot with no animation has nothing
  -- to wait for.  `start` refuses to make one, so reaching this means that
  -- guard has been broken -- and the failure then belongs to `start`'s own
  -- assertion, not to a script stalled for ever on a nil comparison.
  if not (slot.frames and slot.frames > 0) then return true end
  return slot.frame >= slot.frames
end

-- advance(ow, frames) -- step every running one-shot.
--
-- Driven from the overworld's update rather than the draw, for the same reason
-- `world.tick` is: a skipped frame must not stop a door closing, and a script
-- waiting on one would then wait for ever.
--
-- A finished one-shot is KEPT rather than cleared, because `unloadanimation`
-- is what releases the tag and the last frame is the pose the door has to hold
-- until then -- clearing it here would snap the door shut the instant it
-- finished opening.
function Gen4PropOneShot.advance(ow, frames)
  local slots = store(ow)
  if not slots then return 0 end
  frames = tonumber(frames) or 0
  if frames <= 0 then return 0 end
  local moved = 0
  for _, slot in pairs(slots) do
    -- A slot with no length is skipped for the same reason `finished`
    -- answers true for one: there is nothing to step.  Without this, a
    -- broken `start` guard turns every later frame into a nil comparison
    -- and the overworld's update raises rather than the fault being
    -- reported where it happened.
    if slot.frames and slot.frame < slot.frames then
      slot.frame = slot.frame + frames
      if slot.frame > slot.frames then slot.frame = slot.frames end
      moved = moved + 1
    end
  end
  return moved
end

-- poseFor(ow, object) -> { animation, frame, frames, model } | nil
--
-- Looked up BY OBJECT, because that is what the renderer has in hand. Several
-- tags can be live at once (a script opens two doors) and only one of them
-- names any given prop.
function Gen4PropOneShot.poseFor(ow, object)
  local slots = store(ow)
  if not (slots and object) then return nil end
  for _, slot in pairs(slots) do
    if slot.object == object then return slot end
  end
  return nil
end

-- all(ow) -> the slot table, for a consumer that cannot reach the overworld.
--
-- `Gen4Ground` is built by `MapLoader` and holds no reference to the
-- overworld, which is right -- the renderer must not depend on the controller.
-- So the controller HANDS it the table each frame instead, and the renderer
-- reads a plain field. A `self.overworld` in the renderer would have been
-- cold by construction: the field does not exist, so the pose lookup would
-- have returned nil for ever and nothing would have said so.
function Gen4PropOneShot.all(ow)
  return store(ow)
end

-- poseIn(slots, object) -- the same search as `poseFor`, against a table that
-- was handed over rather than reached through the overworld.
function Gen4PropOneShot.poseIn(slots, object)
  if not (type(slots) == "table" and object) then return nil end
  for _, slot in pairs(slots) do
    if slot.object == object then return slot end
  end
  return nil
end

function Gen4PropOneShot.count(ow)
  local slots = store(ow)
  if not slots then return 0 end
  local n = 0
  for _ in pairs(slots) do n = n + 1 end
  return n
end

return Gen4PropOneShot
