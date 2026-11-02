-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE FERRY AT SEA: the 3D app Platinum's PlayBoatCutscene runs between
-- leaving one harbour and arriving at the next (pokeplatinum
-- src/cutscenes/boat_cutscene/canalave_ship.c and snowpoint_ship.c, which
-- differ only in their archive, member table and track count -- see
-- src/import/Gen4BoatCutsceneArt.lua).
--
--   Init  Camera_InitWithTarget({0,0,0}, BASE_DISTANCE 0x29AEC1,
--         angle (-10750, 0, 0), BASE_FOVY 1473, perspective) -- clip at the
--         camera defaults 150..900; edge marking on, every edge colour
--         GX_RGB(4,4,4) but entry 0; the field's four area lights and
--         material colours carried over (BoatTravelCutscene.areaModelAttrs);
--         App_StartScreenFade(FALSE): brightness in from black, 6 steps x 1
--   Main  state SFX: Sound_PlayEffect(SEQ_SE_DP_SHIP01), state++
--         state FADE_OUT: when anims[0]'s frame + 1 == its frame count,
--         App_StartScreenFade(TRUE) (to black, 6 x 1); once that fade is
--         done the app returns
--         every pass, each track not yet on its last frame steps one frame;
--         the one model drawn at the origin, unrotated, unscaled
--
-- PASSES are the cartridge's 30 Hz, two engine ticks (as the Spear Pillar
-- cinematic's are, Gen4SpearPillarCutscene.TICKS_PER_FRAME); the screen fade
-- is a VBlank task, a tick each.  The model is drawn with the Spear Pillar's
-- own model path (`drawModel`, its mesh cache), which is what the two art
-- modules share their packing with.  The bottom screen shows nothing
-- (GXS_SetVisiblePlane(0)).

local Gen4Model = require("src.render.Gen4Model")
local Logger = require("src.core.Logger")

local S = {}
S.__index = S
S.isOpaque = true

local W, H = 256, 192
local FX = 4096
S.TICKS_PER_FRAME = 2
S.FADE_STEPS = 6            -- App_StartScreenFade: 6 steps of 1 frame
S.SE_START = "SEQ_SE_DP_SHIP01"
-- boat_cutscene.h
S.CAMERA = { distance = 0x29AEC1, angleX = -10750, angleY = 0, fovY = 1473, near = 150, far = 900 }
S.EDGE = { 4 / 31, 4 / 31, 4 / 31 }

local SP
local function spear()
  SP = SP or require("src.ui.Gen4SpearPillarCutscene")
  return SP
end

function S.available(game, travelDir)
  local art = game and game.data and game.data.gen4_boat_cutscene
  local c = type(art) == "table" and art.crossings
  return type(c) == "table" and c[travelDir] ~= nil
end

function S.new(game, travelDir, onDone)
  local self = setmetatable({}, S)
  self.game = game
  self.data = game and game.data or {}
  self.travelDir = travelDir
  self.onDone = onDone
  self.tick, self.frame = 0, 0
  self.state = 0
  self.firstAnimationFinished = false
  self.cameraTarget = { 0, 0, 0 }
  local art = self.data.gen4_boat_cutscene
  local rec = type(art) == "table" and art.crossings and art.crossings[travelDir]
  if not rec then
    Logger.warn("boat cutscene: this cache carries no `gen4_boat_cutscene` crossing %s -- re-import Platinum",
      tostring(travelDir))
    self.unavailable = true
    return self
  end
  -- the one model with every track (BoatCutscene_*_LoadAnimations)
  local m = { part = travelDir, rec = rec, loaded = true, visible = true,
              pos = { 0, 0, 0 }, scale = { FX, FX, FX }, anims = {} }
  for i, track in ipairs(rec.tracks or {}) do
    m.anims[i - 1] = { frame = 0, count = (track.frames or 1) * FX, track = track }
  end
  self.model = m
  local c = S.CAMERA
  spear().initCamera(self, c.distance, c.angleX, c.angleY, c.fovY, c.near, c.far)
  self:startFade("in")
  return self
end

function S:uiSize() return W, H end
function S:wantsFillScale() return true end

-- StartScreenFade(BOTH, BRIGHTNESS_IN / OUT, COLOR_BLACK, 6, 1)
function S:startFade(dir)
  local from, to = 0, -16
  if dir == "in" then from, to = -16, 0 end
  self.fade = { from = from, to = to, n = S.FADE_STEPS, t = 0 }
  self.master = from
end
function S:tickFade()
  local f = self.fade
  if not f then return end
  f.t = f.t + 1
  local v = f.from + (f.to - f.from) * f.t / f.n
  self.master = v < 0 and -math.floor(-v) or math.floor(v)
  if f.t >= f.n then self.master = f.to; self.fade = nil end
end
function S:fadeDone() return self.fade == nil end

-- BoatCutscene_*_Main, one pass
function S:logicFrame()
  self.frame = self.frame + 1
  local a0 = self.model.anims[0]
  if self.state == 0 then
    pcall(function() require("src.core.Sound").playSe(self.data, S.SE_START) end)
    self.state = 1
  elseif self.state == 1 then
    if not self.firstAnimationFinished then
      if a0 and a0.frame + FX == a0.count then
        self.firstAnimationFinished = true
        self:startFade("out")
      end
    elseif self:fadeDone() then
      return self:finish()
    end
  end
  for i = 0, 3 do
    local a = self.model.anims[i]
    if a and a.frame + FX < a.count then a.frame = a.frame + FX end
  end
end

function S:update(dt)
  if self.finished then return end
  if self.unavailable then return self:finish() end
  self.tick = self.tick + 1
  -- App_StartScreenFade runs a frame a VBlank
  self:tickFade()
  if self.tick % S.TICKS_PER_FRAME == 0 then self:logicFrame() end
end

function S:finish()
  if self.finished then return end
  self.finished = true
  self:releaseTargets()
  if self.game and self.game.stack and self.game.stack.top and self.game.stack:top() == self then
    self.game.stack:pop()
  end
  if self.onDone then self.onDone() end
end

-- ------------------------------------------------------------- drawing --
function S:targets()
  if self.canvas then return true end
  local g = love.graphics
  self.canvas = g.newCanvas(W, H)
  self.canvas:setFilter("nearest", "nearest")
  self.colour3d, self.depth3d = Gen4Model.newTarget(W, H)
  return self.colour3d ~= nil
end

function S:releaseTargets()
  for _, c in ipairs({ self.canvas, self.colour3d, self.depth3d }) do
    if c and c.release then pcall(c.release, c) end
  end
  self.canvas, self.colour3d, self.depth3d = nil, nil, nil
end

-- G3X_EdgeMarking: a polygon's silhouette ringed in the edge colour
local edgeShader
local function shader()
  if edgeShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern vec2 texel;
      extern vec3 edgeColour;
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        if (p.a > 0.0) {
          float n = Texel(tex, uv + vec2(texel.x, 0.0)).a * Texel(tex, uv - vec2(texel.x, 0.0)).a
                  * Texel(tex, uv + vec2(0.0, texel.y)).a * Texel(tex, uv - vec2(0.0, texel.y)).a;
          if (n == 0.0) p.rgb = edgeColour * p.a;
        }
        return p * colour;
      }
    ]])
    edgeShader = ok and sh or false
    if not ok then Logger.warn("boat cutscene: edge shader failed: %s", tostring(sh)) end
  end
  return edgeShader or nil
end

function S:render()
  local g = love.graphics
  g.setCanvas(self.canvas)
  g.clear(0, 0, 0, 1)
  if self.colour3d and self.model then
    g.push("all")
    g.setCanvas({ self.colour3d, depthstencil = self.depth3d })
    g.clear(0, 0, 0, 0, true, true)
    local okVp, vp, view = pcall(spear().viewProjection, self)
    if okVp then
      local ok, err = pcall(self.drawLayers, self, vp, view)
      if not ok and not self.warned then
        self.warned = true
        Logger.warn("boat cutscene: draw failed: %s", tostring(err))
      end
    end
    g.pop()
    g.setCanvas(self.canvas)
    local sh = shader()
    g.setBlendMode("alpha", "premultiplied")
    if sh then
      sh:send("texel", { 1 / W, 1 / H })
      sh:send("edgeColour", S.EDGE)
      g.setShader(sh)
    end
    g.setColor(1, 1, 1, 1)
    g.draw(self.colour3d, 0, 0)
    g.setShader()
    g.setBlendMode("alpha", "alphamultiply")
  end
  g.setCanvas()
  return self.canvas
end

local function masterOver(level)
  if not level or level == 0 then return end
  local g = love.graphics
  if level > 0 then g.setColor(1, 1, 1, level / 16) else g.setColor(0, 0, 0, -level / 16) end
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
end

-- spear pillar's model path reads these off `self`
function S:mesh(rec) return spear().mesh(self, rec) end

-- THE DS DRAWS OPAQUE POLYGONS FIRST AND TRANSLUCENT ONES AFTER, and a
-- translucent one writes no depth (no POLYGON_ATTR translucent-depth-update
-- here); alpha 0 is not translucent at all but WIREFRAME (edges only, which
-- on these sea planes lie off screen).  The scene leans on it: the big sea
-- (`water_1`, lambert5) sits two units ABOVE the tiled one (`water_2`) at
-- alpha 0 until its BMA0 brings it up from frame 60 -- drawn in file order
-- with depth, the invisible plane hid the visible one and the ship sailed on
-- black.  So: opaque shapes, then the translucent ones (static polygon
-- alpha, or a material-colour animation's alpha this frame) without depth
-- writes, alpha-0 ones not at all.
function S:drawLayers(vp, view)
  local m = self.model
  local rec = m.rec
  local mdl = self:mesh(rec)
  if not mdl then return end
  -- the packed shapes carry the polygon alpha; the built ones may not
  local alphaOf = {}
  for _, sh in ipairs((rec.model and rec.model.shapes) or {}) do
    if sh.material and tonumber(sh.alpha) then alphaOf[sh.material] = math.min(31, tonumber(sh.alpha)) / 31 end
  end
  local TexAnim = require("src.render.Gen4TexAnim")
  local animated = {}
  for i = 0, 3 do
    local a = m.anims[i]
    local tr = a and a.track
    if tr and tr.record and tr.record.kind == "BMA0" then
      local f = math.min(math.floor(a.frame / FX), (tr.frames or 1) - 1)
      local mats = TexAnim.materials({ tr.record }, math.max(0, f), rec.model.patternImages)
      for name, st in pairs(mats or {}) do
        if st.alpha then alphaOf[name] = st.alpha; animated[name] = true end
      end
    end
  end
  local all = mdl.shapes
  local opaque, translucent = {}, {}
  for _, sh in ipairs(all) do
    local alpha = alphaOf[sh.material or false]
    if alpha == nil or alpha >= 1 then opaque[#opaque + 1] = sh
    elseif alpha > 0 then
      -- a static polygon alpha onto the built shape (Gen4Model's own
      -- shapeAlpha); an animated one is applied by the draw from `materials`
      if sh.alpha == nil and not animated[sh.material] then sh.alpha = math.floor(alpha * 31 + 0.5) end
      translucent[#translucent + 1] = sh
    end
  end
  local soft = Gen4Model.softAlpha
  local okA, errA = pcall(function()
    mdl.shapes = opaque
    spear().drawModel(self, m, vp, view)
    if #translucent > 0 then
      Gen4Model.softAlpha = true
      mdl.shapes = translucent
      spear().drawModel(self, m, vp, view)
    end
  end)
  Gen4Model.softAlpha = soft
  mdl.shapes = all
  if not okA then error(errA, 0) end
end

function S:draw()
  local g = love.graphics
  if self.unavailable or self.finished or not self:targets() then
    g.setColor(0, 0, 0, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1)
    return
  end
  g.push("all")
  g.origin()
  g.setScissor()
  local main = self:render()
  g.pop()
  g.setColor(1, 1, 1, 1)
  g.draw(main, 0, 0)
  masterOver(self.master)
  -- the bottom screen: GXS_SetVisiblePlane(0), the backdrop alone
  local SS = require("src.ui.SecondScreen")
  if SS.separate and SS.separate(self.game) and SS.draw then
    SS.draw(self.game, function()
      g.setColor(0, 0, 0, 1)
      g.rectangle("fill", 0, 0, W, H)
      g.setColor(1, 1, 1, 1)
    end)
  end
end

function S:describe()
  local a0 = self.model and self.model.anims[0]
  return ("boat %s state %d frame %s/%s fade %s"):format(tostring(self.travelDir), self.state,
    tostring(a0 and a0.frame / FX), tostring(a0 and a0.count / FX), tostring(self.master))
end

return S
