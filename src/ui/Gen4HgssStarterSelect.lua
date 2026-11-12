-- Professor Elm's turntable: HeartGold and SoulSilver's starter choice.
--
-- Everything on this screen is the cartridge's own, read from pokeheartgold's
-- choose_starter_app.c and drawn from `choose_starter_main_res` (/a/0/8/2),
-- which the models stage extracts as the `hgssStarter` set:
--
--   tt_tabletop   the table, which does not turn
--   tt_turntable  the turntable, turned by `rotationAngle`
--   tt_ball       one ball (nodes a / b / c), drawn three times
--   tt_ball_ef    the burst when the chosen ball opens
--   animations    ball_rock (the chosen ball rocking), tt_ball (opening),
--                 tt_ball_ef (the burst)
--
-- THE LAYOUT. `initBallModelPositions` stands the three balls at 0, 120 and
-- 240 degrees round the turntable at (0, 14, 32) rotated -- the selected one
-- always at 0, the front -- and LEFT / RIGHT turn the whole turntable 120
-- degrees at FX16_CONST(0.5) a frame (`updateBaseRotation`, eleven frames)
-- before the next ball becomes the front one.
--
-- THE CAMERA. `initCameraPosition`: target (0, 15, 0) shifted by (0, 0, 14),
-- distance 100, angle.x 0xDCC0 (-49.57 degrees), perspective 0x11A4 (24.8
-- degrees, a HALF angle -- see Gen4StarterSelect for why), clip 4..256.
-- Confirming moves it over 8 steps to the IN path: -30.76 degrees, 22.7,
-- target z 12, distance 60; backing out moves it back.
--
-- THE WORDS are message bank 190: 0 the opening line, 4..6 the ball's
-- contents when it is inspected, 1..3 Elm's question, 7 the prompt.
--
-- WHAT THIS FILE INVENTS: where the species picture sits. The cartridge
-- shows it on the other screen (`screensFlipped`); here it sits above the
-- message box beside the 3D, which is the closest one screen allows.

local Font = require("src.render.Font")
local Gen4Anim = require("src.import.Gen4Anim")
local Gen4Model = require("src.render.Gen4Model")
local Logger = require("src.core.Logger")
local Sprites = require("src.pokemon.Sprites")
local SecondScreen = require("src.ui.SecondScreen")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 256, 192
local BOX = { tx = 1, ty = 18, tw = 29, th = 6 }
local TEXT_X, TEXT_Y, LINE_H = 16, 152, 16

local function deg(d) return math.rad(d) end
local CAM_OUT = { pitch = deg(-49.57), fov = deg(24.805) * 2, z = 14, distance = 100 }
local CAM_IN  = { pitch = deg(-30.76), fov = deg(22.7) * 2, z = 12, distance = 60 }
local CAM_STEPS = 8
local TARGET_Y = 15
local NEAR, FAR = 4, 256

local BALL_RADIUS, BALL_Y = 32, 14
local TURN = deg(120)
-- FX16_CONST(0.5) on a u16 angle is 2048 of 65536 a frame
local TURN_SPEED = 2048 / 65536 * 2 * math.pi
local BALL_YAW_IN = deg(-30.76)
local FADE_FRAMES = 16

local FLIP_Y = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }

local function multiply(a, b)
  local out = {}
  for row = 0, 3 do
    for col = 0, 3 do
      local sum = 0
      for k = 0, 3 do sum = sum + a[row * 4 + k + 1] * b[k * 4 + col + 1] end
      out[row * 4 + col + 1] = sum
    end
  end
  return out
end

local function rotY(a)
  local c, s = math.cos(a), math.sin(a)
  return { c, 0, s, 0,  0, 1, 0, 0,  -s, 0, c, 0,  0, 0, 0, 1 }
end

local function translation(x, y, z)
  return { 1, 0, 0, x,  0, 1, 0, y,  0, 0, 1, z,  0, 0, 0, 1 }
end

local function named(list, name)
  for _, item in ipairs(list or {}) do
    if item.name == name then return item end
  end
  return nil
end

local function tracksOf(set, name)
  local animation = named(set.animations, name)
  if not (animation and animation.tracks) then return nil end
  local byNode = {}
  for _, track in ipairs(animation.tracks) do byNode[track.index] = track end
  return { tracks = byNode, frames = math.max(1, animation.frames or 1) }
end

function Screen:uiSize() return W, H end
function Screen:wantsFillScale() return true end
function Screen:wantsEdgeBleed() return false end

function Screen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Screen)
  self.game = game
  self.species = opts.species or { 152, 155, 158 }
  self.onChoose, self.onCancel = opts.onChoose, opts.onCancel
  self.selection = 0          -- curSelection: the ball at the front
  self.base = 0               -- rotationAngle
  self.turning = 0            -- rotationSpeed's sign while turning
  self.camStep = 0            -- 0 = OUT, CAM_STEPS = IN
  self.camGoal = 0
  self.ballYaw = 0
  self.frame = 0
  self.state = "intro"        -- intro, browse, inspect, turning, confirm, opening, fading

  local data = game.data or {}
  self.text = data.text or {}
  local set = ((data.gen4_models or {}).sets or {}).hgssStarter
  if not set then
    Logger.warn("gen4 hgss starter: this cache carries no turntable models (re-import to get them)")
    self.unavailable = true
    return self
  end
  self.tabletop = Gen4Model.new(named(set.models, "tt_tabletop"))
  self.turntable = Gen4Model.new(named(set.models, "tt_turntable"))
  self.ball = Gen4Model.new(named(set.models, "tt_ball"))
  self.burst = Gen4Model.new(named(set.models, "tt_ball_ef"))
  if not (self.tabletop and self.turntable and self.ball) then
    Logger.warn("gen4 hgss starter: the turntable models would not build")
    self.unavailable = true
    return self
  end
  self.rock = tracksOf(set, "ball_rock")
  self.open = tracksOf(set, "tt_ball")
  self.burstAnim = tracksOf(set, "tt_ball_ef")
  self:say(0)
  return self
end

-- ------------------------------------------------------------------- text --

function Screen:line(entry)
  local s = self.text[("TEXT_B0190_%05d"):format(entry)] or ""
  return (s:gsub("{COLOR %d+}", ""))
end

function Screen:say(entry)
  local text = self:line(entry)
  local pages = {}
  for page in (text .. "\v"):gmatch("([^\v\f]*)[\v\f]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then pages[#pages + 1] = page end
  end
  self.pages, self.page = (#pages > 0 and pages or { "" }), 1
end

-- ------------------------------------------------------------------- flow --

function Screen:finish(chosen)
  self.game.stack:pop()
  if chosen then
    if self.onChoose then self.onChoose(self.species[self.selection + 1], self.selection) end
  elseif self.onCancel then
    self.onCancel()
  end
end

function Screen:inspect()
  self.state = "inspect"
  self:say(4 + self.selection)
end

function Screen:update()
  if self.unavailable then return self:finish(false) end
  self.frame = self.frame + 1
  -- the camera path, eight steps either way
  if self.camStep < self.camGoal then self.camStep = self.camStep + 1
  elseif self.camStep > self.camGoal then self.camStep = self.camStep - 1 end
  local towards = self.camGoal > 0 and BALL_YAW_IN or 0
  self.ballYaw = self.ballYaw + (towards - self.ballYaw) / 3

  if self.state == "turning" then
    self.base = self.base + self.turning * TURN_SPEED
    if math.abs(self.base) >= TURN then
      -- reinitBallModelPosInDirection: turning left brings the next ball round
      self.selection = (self.selection + (self.turning < 0 and 1 or 2)) % 3
      self.base, self.turning = 0, 0
      self:inspect()
    end
    return
  end
  if self.state == "opening" then
    self.openFrame = (self.openFrame or 0) + 1
    if self.openFrame >= (self.open and self.open.frames or 30) * 0.5 then
      self.state, self.fade = "fading", 0
    end
    return
  end
  if self.state == "fading" then
    self.openFrame = self.openFrame + 1
    self.fade = self.fade + 1
    if self.fade >= FADE_FRAMES then self:finish(true) end
    return
  end

  local input = self.game.input
  if not input then return end
  local tap=self.tap;self.tap=nil
  local a, b = input:wasPressed("a") or tap=='a', input:wasPressed("b")
  if input:wasPressed("l") or input:wasPressed("select") then self.showScene = not self.showScene end
  local left, right = input:wasPressed("left") or tap=='left', input:wasPressed("right") or tap=='right'
  if a and self.page < #self.pages then self.page = self.page + 1 return end

  if self.state == "intro" then
    if a then self.state = "browse"; self:say(7) end
  elseif self.state == "browse" or self.state == "inspect" then
    if left or right then
      self.state, self.turning = "turning", left and -1 or 1
    elseif a then
      if self.state == "browse" then self:inspect()
      else
        self.state, self.camGoal = "confirm", CAM_STEPS
        self:say(1 + self.selection)
      end
    end
  elseif self.state == "confirm" then
    if a then
      self.state, self.openFrame = "opening", 0
    elseif b then
      self.state, self.camGoal = "browse", 0
      self:say(7)
    end
  end
end

-- ------------------------------------------------------------------- draw --

local function poseFrom(model, anim, frame)
  if not (model and anim) then return nil end
  local f = math.floor(frame) % anim.frames
  return model:posed(function(node)
    local track = anim.tracks[node]
    return track and Gen4Anim.unpackFrame(track.matrices, f) or nil
  end)
end

function Screen:drawScene()
  if not self.colour then
    self.colour, self.depth = Gen4Model.newTarget(W, H)
    if not self.colour then self.noDepth = true end
  end
  if self.noDepth then return nil end
  local g = love.graphics
  -- push("all")/pop restores the bound canvas, a mod's depth set included
  g.push("all")
  g.setCanvas({ self.colour, depthstencil = self.depth })
  g.clear(0, 0, 0, 0, true, true)

  local k = self.camStep / CAM_STEPS
  local function lerp(p, q) return p + (q - p) * k end
  local projection = Gen4Model.perspective(lerp(CAM_OUT.fov, CAM_IN.fov), W / H, NEAR, FAR)
  local view = Gen4Model.orbit({ 0, TARGET_Y, lerp(CAM_OUT.z, CAM_IN.z) },
                               lerp(CAM_OUT.distance, CAM_IN.distance), 0,
                               lerp(CAM_OUT.pitch, CAM_IN.pitch))
  local vp = multiply(FLIP_Y, multiply(projection, view))

  self.tabletop:draw(vp)
  local base = rotY(self.base)
  local turned = multiply(vp, base)
  self.turntable:draw(turned)

  local rocking = self.state == "inspect" or self.state == "confirm" or self.state == "turning"
  for slot = 0, 2 do
    local angle = slot * TURN
    local m = multiply(turned, multiply(rotY(angle),
      translation(0, BALL_Y, BALL_RADIUS)))
    local pose
    if slot == 0 then
      m = multiply(m, rotY(self.ballYaw))
      if self.state == "opening" or self.state == "fading" then
        pose = poseFrom(self.ball, self.open, math.min(self.openFrame or 0, (self.open and self.open.frames or 1) - 1))
      elseif rocking and self.state ~= "turning" then
        pose = poseFrom(self.ball, self.rock, self.frame)
      end
    end
    self.ball:draw(m, pose)
  end
  if self.burst and (self.state == "opening" or self.state == "fading") then
    local m = multiply(turned, translation(0, BALL_Y, BALL_RADIUS))
    self.burst:draw(m, poseFrom(self.burst, self.burstAnim, self.openFrame or 0))
  end

  g.pop()
  return self.colour
end

function Screen:image(path)
  if type(path) ~= "string" or path == "" then return nil end
  self.pics = self.pics or {}
  if self.pics[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.pics[path] = ok and img or false
    if self.pics[path] then self.pics[path]:setFilter("nearest", "nearest") end
  end
  return self.pics[path] or nil
end

function Screen:drawTurntable()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local scene = not self.unavailable and self:drawScene()
  if scene then g.draw(scene, 0, 0) end

end

function Screen:drawPreview()
  local g=love.graphics
  g.setColor(1,1,1,1);g.rectangle('fill',0,0,W,H)
  local art=self.game.data.gen4_hgss_starter_art or {}
  for _,key in ipairs({'preview','preview_overlay'}) do
    local rec=art[key]
    local image=rec and self:image(rec.path)
    if image then
      g.setColor(1,1,1,key=='preview_overlay' and 5/16 or 1)
      g.draw(image,0,0)
    end
  end
  g.setColor(1,1,1,1)
  -- createOneMonRender places the 80x80 sprite at (128,96) on this screen.
  if self.state == "inspect" or self.state == "confirm" then
    local species = self.species[self.selection + 1]
    -- RUN MODES: a randomized-starters save shows the mon it will get
    if species then species = require("src.runmodes.RunHooks").shownStarter(self.game, species) end
    local pic = species and self:image(Sprites.path(self.game.data, species, "front", { kind = "summary" }))
    if pic then
      local pw, ph = pic:getDimensions()
      g.draw(pic, 128-pw/2, 96-ph/2)
    end
  end

  Font.drawDialogueBox(BOX.tx, BOX.ty, BOX.tw, BOX.th)
  local page = self.pages and self.pages[self.page] or ""
  local y = TEXT_Y
  for line in (tostring(page) .. "\n"):gmatch("([^\n]*)\n") do
    if y >= TEXT_Y + LINE_H * 2 then break end
    Font.draw(line, TEXT_X, y)
    y = y + LINE_H
  end

  if self.state == "fading" then
    g.setColor(1, 1, 1, math.min(1, self.fade / FADE_FRAMES))
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

function Screen:draw()
  local dual=SecondScreen.separate(self.game)
  if dual then
    self:drawPreview()
    SecondScreen.draw(self.game,function() self:drawTurntable() end)
    self.game.secondScreenPointerOwner=self
  elseif not self.showScene and (self.state=='inspect' or self.state=='confirm') then
    self:drawPreview()
  else
    self:drawTurntable()
    Font.drawDialogueBox(BOX.tx,BOX.ty,BOX.tw,BOX.th)
    Font.draw(self.pages and self.pages[self.page] or '',TEXT_X,TEXT_Y)
  end
end

function Screen:touchpressed(id,x,y)
  local px,py=SecondScreen.toLocal(self.game,x,y)
  if not px then
    local rect=require('src.render.Renderer').uiPresentation
    if not rect then return false end
    px,py=(x-rect.x)/rect.scaleX,(y-rect.y)/rect.scaleY
  end
  if px<0 or py<0 or px>=W or py>=H then return false end
  self.tap = px<80 and 'left' or px>176 and 'right' or 'a'
  return true
end

return Screen
