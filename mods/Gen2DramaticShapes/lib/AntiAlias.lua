-- Voxel world mode: anti-aliasing, by supersampling.
--
-- Everything else in this mod is flat art blitted at whole pixels; this one
-- pass is real geometry seen through a perspective camera, and a polygon
-- edge that lands at an angle across the pixel grid is the one place in the
-- game where a hard stair-step is not a stylistic choice. A roof ridge, a
-- ledge lip, a tree's silhouette against the sky and the leaning card of a
-- character are all cut by an edge that has no reason to line up with
-- anything, and at the shallow rungs -- where the diorama reads most like a
-- photograph of a model -- they crawl as the camera drifts.
--
-- SUPERSAMPLING, not MSAA and not a filter over the finished frame, for two
-- reasons that both come out of what the pass already is:
--
--   MSAA would take the water with it. The reflections read the frame's own
--   DEPTH buffer as a texture (Voxel3D.beginWater), and a multisampled depth
--   attachment is not a thing a fragment shader in this dialect can sample.
--   The row would have quietly switched the other row off.
--
--   An edge filter (FXAA and its relatives) works from the finished colour
--   alone, and would be GUESSING where the edges are out of one sample per
--   pixel -- inventing detail it never rendered, and unable to tell a
--   geometry edge from the boundary between two texels of a tileset.
--
-- Rendering the pass larger and folding it back down has neither problem:
-- the depth buffer stays an ordinary texture, every pass in the frame keeps
-- working in the canvas it was handed, and the fold is an average of samples
-- that were each rendered honestly. It antialiases everything at once --
-- geometry, the alpha-cut outline of a sprite card, the wireframe, the
-- water's ray march -- because none of them know it is happening.
--
-- Be clear about what "everything" means: the artwork softens too. A tileset
-- texel out here is not a screen pixel, it is a quad in a perspective view,
-- and its boundary crosses the pixel grid at the same arbitrary angle a roof
-- ridge does -- so the fold averages across it exactly as it averages across
-- the ridge. That is what an honest extra sample says about that pixel, and
-- it is also the trade the row IS: the diorama comes out smoother, not
-- sharper. Which is why this is a row and not something that is simply on.
--
-- What it costs is pixels, which is the whole of why this is a row and not
-- something that is simply on: 2X is half again as many in each direction,
-- 4X is twice, and the scene pass is the most expensive thing in the frame.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local AntiAlias = {}

-- the key under options.modOptions.DRAMATIC_SHAPE, shared by the row in
-- OPTIONS and the mod manager's own settings page for this mod
AntiAlias.KEY = "aa"
AntiAlias.LABEL = "AA"

-- The ladder is SAMPLES PER DISPLAY PIXEL, which is how an AA setting reads
-- everywhere else, and the canvas scale each rung costs is its square root:
-- 2 samples is a canvas 1.41x wider and taller, 4 is one exactly twice the
-- size. OFF is the default -- this is a cost knob, and a mod should not
-- quietly spend four times the fill rate of the machine it lands on.
AntiAlias.setting = ModSetting.new(AntiAlias.KEY, AntiAlias.LABEL,
                                   { 0, 2, 4 }, { "OFF", "2X", "4X" })

-- The scale the pass currently open was actually expanded by (see expand).
-- 1 while there is no supersampling in force, which is also what every
-- reader gets on a frame that never opened a pass at all.
local live = 1

function AntiAlias.samples()
  return tonumber(AntiAlias.setting:get()) or 0
end

-- What the row ASKS for. The scale in force is `factor()`, which is this
-- clamped to what the driver will actually allocate.
local function wanted()
  local n = AntiAlias.samples()
  if n <= 1 then return 1 end
  return math.sqrt(n)
end

-- The biggest canvas this driver admits to, or nil where it will not say.
-- A 4K window at 4X asks for 7680 across, which is past the limit on plenty
-- of hardware and every phone -- and a refused canvas is not a softer
-- diorama, it is beginScene returning false and the whole mode falling back
-- to the flat 2D path.
local function textureLimit()
  if not (love.graphics and love.graphics.getSystemLimits) then return nil end
  local ok, limits = pcall(love.graphics.getSystemLimits)
  return (ok and limits and limits.texturesize) or nil
end

-- The size to render `w` x `h` display pixels at, and the size everything
-- inside the pass then measures itself in.
--
-- Also where `live` is set, which is why this must be called once per pass
-- immediately before beginScene: the wireframe's line width and the FX
-- overlay's sprite scale are both quoted in DISPLAY pixels and have to be
-- multiplied up into canvas ones, and the honest multiplier is the one this
-- returned rather than the one the row asked for.
function AntiAlias.expand(w, h)
  local s = wanted()
  local max = textureLimit()
  if max and max > 0 then
    -- clamped rather than abandoned: a window too big for 4X can usually
    -- still carry some of it, and half a rung of smoothing is worth more
    -- than a row that silently does nothing at that size
    s = math.min(s, max / math.max(1, w), max / math.max(1, h))
  end
  if not (s > 1.01) then
    live = 1
    return w, h
  end
  local ew, eh = math.floor(w * s + 0.5), math.floor(h * s + 0.5)
  live = ew / math.max(1, w)
  return ew, eh
end

-- The scale the open pass was expanded by; 1 when it was not.
function AntiAlias.factor()
  return live
end

-- ------- the fold
--
-- One target per pass (the free-roam world and the battle's arena are alive
-- at different moments but reallocating on every battle entry and exit is
-- what the scene canvas's own slots exist to avoid), reallocated only when
-- that pass's DISPLAY size changes -- a window resize, or the row itself
-- moving, which changes the source and not this.

local targets = {}

local function targetFor(slot, w, h)
  local t = targets[slot]
  if not (t and t.w == w and t.h == h) then
    local ok, c = pcall(love.graphics.newCanvas, w, h)
    if not (ok and c) then return nil end
    -- nearest, like the canvas it stands in for: this one is composited a
    -- canvas pixel to a display pixel, and the smoothing has already happened
    pcall(c.setFilter, c, "nearest", "nearest")
    if t and t.canvas and t.canvas.release then pcall(t.canvas.release, t.canvas) end
    t = { canvas = c, w = w, h = h }
    targets[slot] = t
  end
  return t.canvas
end

-- The box filter, and the whole of why it is a shader rather than a scaled
-- draw with linear filtering on.
--
-- The void this pass renders into is cleared to a TRANSPARENT BLACK, and at
-- the rungs below FULL a good deal of the frame is still that. Averaging a
-- straight-alpha edge against it drags the result toward black as well as
-- toward transparent, and then the engine's own composite multiplies by that
-- alpha a second time -- so every silhouette against the void would come out
-- ringed with a dark fringe, which is exactly the artefact the row is here to
-- remove.
--
-- So the taps are premultiplied before they are averaged and divided back out
-- after, which is the arithmetic that makes an edge pixel mean "half covered
-- by this colour" instead of "covered by half of this colour".
--
-- Four taps, half a source texel from the destination centre. At 4X those
-- land dead on the four texel centres the destination pixel covers, so it is
-- an exact 2x2 box; at 2X the source grid does not divide, and the bilinear
-- fetch under each tap widens the box a little rather than missing samples.
local SHADER = [[
  uniform vec2 tap;        // half a SOURCE texel, in uv
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 a = Texel(tex, tc + vec2(-tap.x, -tap.y));
    vec4 b = Texel(tex, tc + vec2( tap.x, -tap.y));
    vec4 c = Texel(tex, tc + vec2(-tap.x,  tap.y));
    vec4 d = Texel(tex, tc + vec2( tap.x,  tap.y));
    float al = (a.a + b.a + c.a + d.a) * 0.25;
    if (al <= 0.0) return vec4(0.0);
    vec3 sum = a.rgb * a.a + b.rgb * b.a + c.rgb * c.a + d.rgb * d.a;
    return vec4(sum * 0.25 / al, al) * color;
  }
]]

local shader = nil            -- nil = untried, false = unavailable

local function getShader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = (ok and sh) or false
  end
  return shader or nil
end

-- Fold `canvas` down to `w` x `h` and hand back the result.
--
-- Returns the input untouched when there is nothing to fold -- the row is
-- off, or the canvas already IS that size -- so a caller can run it
-- unconditionally, and so can a headless test run. A target that would not
-- allocate is the same answer: the pass is lost either way if this hands back
-- something the wrong size, so it hands back the input and the frame draws at
-- the size it was rendered.
function AntiAlias.resolve(canvas, w, h, slot)
  if not canvas then return canvas end
  local ok, cw, ch = pcall(canvas.getDimensions, canvas)
  if not ok or (cw == w and ch == h) then return canvas end
  local target = targetFor(slot or "world", w, h)
  if not target then return canvas end

  local sh = getShader()
  local prevBlend, prevAlpha = love.graphics.getBlendMode()
  -- the scene canvas filters nearest for its usual 1:1 blit; the taps want
  -- linear, put back below so every other pass finds what it expects
  pcall(canvas.setFilter, canvas, "linear", "linear")
  love.graphics.setColor(1, 1, 1, 1)
  -- replace, not alpha-blend: this is an image-processing copy, and the alpha
  -- the shader worked out has to land as itself rather than be composited
  -- against whatever the target held
  love.graphics.setBlendMode("replace", "premultiplied")
  if sh then
    love.graphics.setShader(sh)
    pcall(sh.send, sh, "tap", { 0.5 / cw, 0.5 / ch })
  end
  local drew = pcall(function()
    love.graphics.setCanvas(target)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.draw(canvas, 0, 0, 0, w / cw, h / ch)
  end)
  love.graphics.setCanvas()
  love.graphics.setShader()
  love.graphics.setBlendMode(prevBlend or "alpha", prevAlpha)
  pcall(canvas.setFilter, canvas, "nearest", "nearest")
  return drew and target or canvas
end

-- Drop the GPU objects (window resize, hot reload).
function AntiAlias.invalidate()
  for slot, t in pairs(targets) do
    if t.canvas and t.canvas.release then pcall(t.canvas.release, t.canvas) end
    targets[slot] = nil
  end
end

function AntiAlias.row()
  return AntiAlias.setting:row()
end

return AntiAlias
