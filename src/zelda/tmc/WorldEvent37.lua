-- Round 37: the world-event view (Fusion32) runs the event objects' own
-- code instead of their animation 0 (round 32's simplification, the
-- beanstalk excepted).  Called from Fusion32's eventEntity (attach / other).
--
-- CARTRIDGE BEHAVIOUR:
--   * WATERFALL_OPENING $AA (waterfallOpening.c), world event 25: the
--     view's entity has type2 1 (WorldEvent_25_0); with the room flag $FF
--     (the view up) it counts $78 frames, then SFX_EVAPORATE, type 1 with
--     fixed gfx $18C, $20 frames, type 2 with fixed gfx $18D, $2D frames,
--     then SFX_SECRET_BIG and gMenu.overlayType++ -- WorldEvent_25_2's 120
--     frames start only then.  sub_080A00B0: every 8 frames frameIndex =
--     subtimer + WaterfallOpening_FrameIndices[type], subtimer = (subtimer +
--     1) & 3.  OAM priority 3, sprite priority 7.
--   * LILYPAD_SMALL $73, world event 11 (type2 $80 + n): rides
--     gLilypadRails[n] (Objects37) -- in the view too; the frame turns every
--     90 frames.
--   * The golden enemies of world event 1 (OCTOROK_GOLDEN $3C, TEKTITE_GOLDEN
--     $3D, ROPE_GOLDEN $3E: kind 3 entries the view skipped): shown with
--     their enemy definition, animation 0 running.
-- SIMPLIFIED: the golden enemies do not run their AI in the view (they stand
--   in place, as the event shows them appearing).
local bit = require("bit")
local band = bit.band

local M = {}
M.WATERFALL_OPENING, M.LILYPAD_SMALL = 0xAA, 0x73
M.SFX_EVAPORATE, M.SFX_SECRET_BIG = 0xF6, 0x73
local FRAMES = require("src.zelda.tmc.RomTables").t("WorldEvent37.WATERFALL_FRAMES") -- WaterfallOpening_FrameIndices
M.FRAMES = FRAMES

local function waterfall(c, f, e)
  local function step()
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.timer = 8
      e.frameOverride = e.subtimer + (FRAMES[e.type] or 0)
      e.subtimer = band(e.subtimer + 1, 3)
    end
  end
  if e.type2 ~= 0 then
    if c.black ~= 0 then return end -- CheckRoomFlag($FF): the view is up
    if e.subAction == 0 then
      e.unk68 = e.unk68 - 1
      if e.unk68 <= 0 then
        e.unk68, e.timer, e.subtimer, e.subAction, e.type = 0x20, 1, 0, 1, 1
        e.gfx = { fixed = 0x18C }
        f:sound(M.SFX_EVAPORATE)
      end
    elseif e.subAction == 1 then
      e.unk68 = e.unk68 - 1
      if e.unk68 <= 0 then
        e.unk68, e.timer, e.subAction, e.type = 0x2D, 1, 2, 2
        e.gfx = { fixed = 0x18D }
      end
    elseif e.subAction == 2 then
      e.unk68 = e.unk68 - 1
      if e.unk68 <= 0 then
        e.subAction = 3
        c.hold37 = nil -- gMenu.overlayType++: WorldEvent_25_2's timer runs
        f:sound(M.SFX_SECRET_BIG)
      end
    end
  end
  step()
end

local function lily(c, f, e)
  e.lt = (e.lt or 90) - 1
  if e.lt <= 0 then e.lt = 90; e.fi = band((e.fi or 0) + 1, 3); e.frameOverride = e.fi end
  local dir = e.direction or 0xFF
  if band(dir, 0x80) == 0 and (e.speed or 0) ~= 0 then
    local a = (dir % 32) / 32 * 2 * math.pi
    e.x, e.y = e.x + math.sin(a) * e.speed / 256, e.y - math.cos(a) * e.speed / 256
  end
  e.unk70 = band((e.unk70 or 0) - 1, 0xFFFF)
  if e.unk70 == 0 then require("src.zelda.tmc.FoWObjects").railNext(f, e) end
end

function M.attach(c, f, e, d, typ)
  if d.id == M.WATERFALL_OPENING then
    e.type = e.form or 0
    e.type2 = typ == 25 and 1 or 0 -- WorldEvent_25_0: entity->type2 = 1
    e.action, e.timer, e.subtimer, e.subAction, e.unk68 = 1, 8, 0, 0, 0x78
    e.prio = 3
    e.frameOverride = FRAMES[e.type] or 0
    if e.type2 ~= 0 then c.hold37 = true end
    e.viewUpdate = waterfall
  elseif d.id == M.LILYPAD_SMALL then
    local t2 = require("bit").band(d.paramB or 0, 0xFF)
    e.type2 = t2
    if t2 >= 0x80 then e.child = require("src.zelda.tmc.Objects37").LILY_RAILS[band(t2, 7)] end
    e.direction, e.speed, e.fi, e.static = 0xFF, 0, 0, true
    e.frameOverride = 0
    require("src.zelda.tmc.FoWObjects").railNext(f, e)
    e.viewUpdate = lily
  end
end

-- a non-object event entity (world event 1's golden enemies)
function M.other(c, f, d, typ, newEnt)
  if not d or d.kind ~= 3 then return nil end
  local E = f:enemies()
  local def = E and E:def(d.id, d.paramA)
  if not def then return nil end
  local A = f.assets
  local Anim = require("src.zelda.tmc.Anim")
  local spr = A:sprite(def.sprite)
  local e = { def = def, sprite = def.sprite, spr = spr, x = d.x, y = d.y, prio = 4, anim = Anim.new(), flipX = false,
              pal = A:objPalette(def.palette, c.room.atlas and c.room.atlas.palettes),
              gfx = require("src.zelda.tmc.Assets").gfxSource("enemy", def.gfx), timer = 0, sub = 0, form = d.paramA }
  e.anim:set(spr, 0, true)
  c.ents[#c.ents + 1] = e
  return e
end

return M
