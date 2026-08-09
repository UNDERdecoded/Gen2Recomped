-- The hour's light on the FLAT world.
--
-- The clock already reaches everything the 3D pass draws: VoxelScene and
-- BattleScene multiply the whole scene by DayNight.tint, so walking around a
-- route at dusk warms the diorama and midnight turns it blue. Switch voxel
-- mode off and none of that happens -- the tint is a uniform in a shader the
-- flat tile path never runs -- so the same evening that fell on the diorama
-- left the 2D world at permanent noon. One clock, two worlds, one of them
-- ignoring it.
--
-- So the flat composite gets the same multiply, painted as one rectangle.
--
-- ------- WHERE, which is the only difficult part
--
-- Not on the world canvas. In a colorized mode that canvas is grayscale art
-- and the blit that puts it on screen runs it through the palette shader,
-- which classifies each pixel into a shade BY ITS RED CHANNEL. Multiply a
-- night blue over it first and every shade lands in the wrong bucket -- the
-- world would not darken, it would change colour into whatever the palette
-- said the wrong bucket was.
--
-- So it goes on AFTER that pass, on the composited world. And not after the
-- whole frame either: the UI blit is next, and the dialog boxes, the menus and
-- the HUD are paper held up in front of the world rather than part of it --
-- the same reason the tilt-shift blur is a worldPresent and not a present.
--
-- Which leaves one instant: between the world blit and the UI blit, inside
-- Renderer:endFrame. There is no seam there -- worldPresent, the engine's own
-- hook for exactly this, only runs when a PIPELINE produced the world, which
-- in flat mode is the one thing that did not happen. So endFrame is wrapped
-- and the UI canvas's own draw call is watched for: `blit` passes the canvas
-- as the first argument, so the first draw of Renderer.canvas IS the boundary,
-- by identity rather than by counting or guessing.
--
-- The shader and scissor that call arrives under belong to the UI blit already
-- in progress, so both are put aside for the rectangle and handed straight
-- back -- otherwise the tint would be palette-remapped and clipped to a zone.
--
-- ------- WHEN
--
-- Outdoors, on the flat path, when the hour is not neutral. Each of those is
-- load-bearing:
--
--   the flat path   a pipeline that rendered the world already applied the
--                   tint inside its own shader; painting it again would apply
--                   the hour twice. worldOverride is exactly "a pipeline drew
--                   this frame".
--   outdoors        a room has no sky to take its light from, which is the
--                   same answer DayNight.tint gives on its own and the same
--                   one applyRig gives the sun.
--   not neutral     midday is a multiply by white. Skipped rather than drawn,
--                   so a game with the clock at DAY issues not one extra call.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local DayNight = V.require("DayNight")

local DayTint = {}

-- Below this the tint is close enough to white that the rectangle would not
-- change a pixel, and the frame is left exactly as it was.
DayTint.NEUTRAL = 0.999

local function outdoorNow()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok then return false end
  local ow = Game and Game.overworld
  local map = ow and ow.map
  if not map then return false end
  local okMap, Map = pcall(require, "src.world.Map")
  if not okMap then return false end
  local outdoor = map.def and Map.isOutdoor(map.def) or false
  -- a canopy floor takes the hour's colour and nothing else of it, exactly as
  -- it does in the 3D pass (BattleScene, VoxelScene)
  return outdoor or DayNight.isCanopy(map)
end

-- The colour this frame's world should be multiplied by, or nil to leave the
-- frame alone.
function DayTint.forFrame(renderer)
  if not renderer then return nil end
  if renderer.worldOverride then return nil end   -- a pipeline drew, and tinted
  if not renderer.worldActive then return nil end -- no world on screen at all
  if not outdoorNow() then return nil end
  local tint = DayNight.tint(true)
  if not tint then return nil end
  local r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
  if r > DayTint.NEUTRAL and g > DayTint.NEUTRAL and b > DayTint.NEUTRAL then
    return nil
  end
  return r, g, b
end

-- One rectangle over the window, multiplied into whatever is under it.
--
-- The whole window rather than the world's own rect, which is what the
-- engine's warp fade does from the same place and for the same reason: the
-- border fill, the letterbox bars and the world are all "the world" as far as
-- the hour is concerned, and black multiplied by anything is still black.
-- Every read of the graphics state is optional, because a headless driver
-- ships some of these and not others -- the same reason TerrainAtlas reads the
-- engine's seams guarded. What cannot be read cannot be put back either, and a
-- missing accessor must cost the tint rather than the frame.
local function saved(name, ...)
  local fn = love.graphics[name]
  if not fn then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

function DayTint.paint(r, g, b)
  local gfx = love.graphics
  local shader = saved("getShader")
  local sx, sy, sw, sh = saved("getScissor")
  local blend, alpha = saved("getBlendMode")
  local pr, pg, pb, pa = saved("getColor")
  local w, h = gfx.getDimensions()

  if gfx.setShader then gfx.setShader() end
  if gfx.setScissor then gfx.setScissor() end
  gfx.setBlendMode("multiply", "premultiplied")
  gfx.setColor(r, g, b, 1)
  gfx.rectangle("fill", 0, 0, w, h)

  gfx.setBlendMode(blend or "alpha", alpha)
  gfx.setColor(pr or 1, pg or 1, pb or 1, pa or 1)
  if gfx.setScissor then
    if sx then gfx.setScissor(sx, sy, sw, sh) else gfx.setScissor() end
  end
  if shader and gfx.setShader then gfx.setShader(shader) end
end

function DayTint.install()
  local Renderer = require("src.render.Renderer")
  if Renderer.dramaticShapeTintHook then return end
  local inner = Renderer.endFrame

  function Renderer:endFrame(zones, worldZones)
    local r, g, b = DayTint.forFrame(self)
    if not r then return inner(self, zones, worldZones) end

    local gfx = love.graphics
    local draw = gfx.draw
    local ui = self.canvas
    local painted = false
    gfx.draw = function(tex, ...)
      -- the UI canvas reaching the screen: the world is finished, the paper
      -- in front of it has not started. Restored FIRST so the rectangle's own
      -- drawing cannot re-enter this, and so a UI blit that draws one quad per
      -- SGB zone only triggers it once.
      if not painted and tex == ui then
        painted = true
        gfx.draw = draw
        DayTint.paint(r, g, b)
      end
      return draw(tex, ...)
    end

    local ok, err = pcall(inner, self, zones, worldZones)
    gfx.draw = draw
    if not ok then error(err, 0) end
  end

  Renderer.dramaticShapeTintHook = true
end

return DayTint
