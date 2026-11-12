-- Black and White's gift box: the starter choice in the player's room.
--
-- The bedroom script (Nuvema's zone, archive member 782) opens it with
-- command 0x153 <var> and reads 0, 1 or 2 back out of the var -- Snivy,
-- Tepig, Oshawott (495 / 498 / 501, the species the script sets for each
-- answer). See Gen5ScriptLink's 0x153.
--
-- THE APP IS OVERLAY 223 and its art is /a/2/0/5 (src/import/
-- Gen5StarterArt.lua, `gen5_starter_art`):
--   * the TOUCH screen is 3D: psel_s01 -- the gift box on the table, its
--     ribbon coming undone and the lid lifting (130 frames, the camera baked
--     in member 33) -- then psel_s02, the open box, the camera sweeping in
--     over the cushion (250 frames, member 36), and three psel_mb Poke Balls
--     at the overlay's own points (-12.5, 29, 3.6), (0, 29, -7),
--     (12.5, 29, 3.6). The white glove (cell 24) points at the one chosen.
--   * the OTHER screen is the stage (screen 19 + pedestal 20 on char 16),
--     white (palette 7) with nothing chosen and tinted green / orange / blue
--     (palettes 9 / 8 / 10) for Snivy / Tepig / Oshawott, the Pokemon's own
--     picture (cells 21-23) on the pedestal. Before the balls are shown it is
--     the box screen (screen 18, palette 6).
--
-- THE WORDS are the cartridge's, story bank 430 (the room's own bank):
--   12  Professor Juniper's letter, shown when the box opens
--   16..18  "The Water/Fire/Grass-type Pokemon <species>"
--   19  "Choose a Pokemon."   20  "Is this the Pokemon you want?"
--   22 / 23  YES / NO
--
-- THE FLOW is the cartridge's: the box opens, the letter, the balls, pick
-- (left / right or a touch), confirm with YES / NO, and no way out without a
-- choice; the chosen ball opens (psel_mb's 160 frames) before the app ends.
--
-- STILL GUESSED (not read from overlay 223 yet): the field of view, the
-- camera held while choosing (the s02 track's frame 57, all three balls in
-- view: the frame that best fits the overlay's touch points), and where the YES / NO box sits. Without imported art the old plain
-- layout below is drawn instead.

local Font = require("src.render.Font")
local Sprites = require("src.pokemon.Sprites")
local Assets = require("src.render.Assets")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 256, 192
local BANK = 430
-- the script's answers, in its order
Screen.SPECIES = { 495, 498, 501 }
-- which type line names each: Grass 18, Fire 17, Water 16
local TYPE_LINE = { 18, 17, 16 }
-- the field of view that spreads the three balls across the touch screen as
-- the overlay's touch points do (53 / 128 / 202 at the held frame)
Screen.FOV = 62
Screen.NEAR, Screen.FAR = 1, 1024
Screen.PICK_FRAME = 57      -- the s02 camera frame held while choosing
Screen.HAND_BOB = 32        -- frames per bob of the glove

function Screen:uiSize() return W, H end
function Screen:wantsFillScale() return true end
function Screen:wantsEdgeBleed() return false end

local function image(path)
  if type(path) == "table" then path = path.path end
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then img:setFilter("nearest", "nearest") return img end
  return nil
end

function Screen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Screen)
  self.game = game
  self.species = opts.species or Screen.SPECIES
  self.onChoose = opts.onChoose
  self.text = (game.data or {}).text or {}
  self.art = (game.data or {}).gen5_starter_art
  if not (self.art and self.art.scene2 and self.art.ball) then self.art = nil end
  -- the glove starts on the left ball (Snivy) -- not read from overlay 223
  self.index = 1
  self.yes = true
  self.t, self.f = 0, 0
  self.pics, self.models = {}, {}
  -- with the cartridge's art: open, letter, reveal, pick, confirm, chosen;
  -- without it the plain flow: letter, pick, confirm
  self.state = self.art and "open" or "letter"
  return self
end

function Screen:line(entry)
  local s = self.text[("TEXT_B%04d_%05d"):format(BANK, entry)] or ""
  local def = (self.game.data.pokemon or {})[require("src.runmodes.RunHooks").shownStarter(self.game, self.species[self.index])]
  s = s:gsub("{CMD %x+}", ""):gsub("{VAR2}", def and def.name or "")
  return (s:gsub("%s+$", ""))
end

-- a message in the game's own box, typed out at once (as Gen5TradeSequence)
function Screen:say(entry)
  self.box = nil
  local ok, TextBox = pcall(require, "src.render.TextBox")
  if not ok then return end
  local okB, box = pcall(TextBox.new, self.game, self:line(entry), nil, { stay = {} })
  if not okB then return end
  for _ = 1, 900 do
    if box.done then break end
    pcall(box.update, box, 1 / 60)
  end
  self.box = box
end

local function se(self, name)
  pcall(function() require("src.core.Sound").play(self.game.data, name) end)
end

function Screen:finish()
  self.game.stack:pop()
  if self.onChoose then self.onChoose(self.index - 1, self.species[self.index]) end
end

-- --------------------------------------------------------------- input --

function Screen:pressed(key)
  local input = self.game.input
  return input and input.wasPressed and input:wasPressed(key)
end

function Screen:update()
  self.t = self.t + 1
  if not self.art then return self:updatePlain() end
  local art = self.art
  if self.state == "open" then
    self.f = self.f + 1
    if self.f >= ((art.scene1 and art.scene1.frames) or 130) then
      -- the letter is one card, all six lines at once
      self.state, self.box = "letter", nil
    end
  elseif self.state == "letter" then
    if self:pressed("a") or self:pressed("b") then
      self.state, self.f, self.box = "reveal", 0, nil
    end
  elseif self.state == "reveal" then
    self.f = self.f + 1
    if self:pressed("a") or self:pressed("b") then self.f = Screen.PICK_FRAME end
    if self.f >= Screen.PICK_FRAME then
      self.state, self.f = "pick", Screen.PICK_FRAME
      self:say(TYPE_LINE[self.index])
    end
  elseif self.state == "pick" then
    local n = #self.species
    local moved
    if self:pressed("right") then self.index = math.min(n, self.index + 1); moved = true
    elseif self:pressed("left") then self.index = math.max(1, self.index - 1); moved = true end
    if moved then se(self, "SEQ_SE_SELECT1"); self:say(TYPE_LINE[self.index]) end
    if self:pressed("a") then
      se(self, "SEQ_SE_DECIDE1")
      self.state, self.yes = "confirm", true
      self:say(20)
    end
  elseif self.state == "confirm" then
    if self:pressed("up") or self:pressed("down") then
      self.yes = not self.yes
      se(self, "SEQ_SE_SELECT1")
    elseif self:pressed("b") or (self:pressed("a") and not self.yes) then
      self.state = "pick"
      self:say(TYPE_LINE[self.index])
    elseif self:pressed("a") then
      se(self, "SEQ_SE_DECIDE1")
      self.state, self.ballFrame, self.box = "chosen", 0, nil
    end
  elseif self.state == "chosen" then
    self.ballFrame = self.ballFrame + 1
    if self.ballFrame >= ((art.ball and art.ball.frames) or 160) then
      self.state = "done"
      self:finish()
    end
  end
end

function Screen:updatePlain()
  if self.state == "letter" then
    if self:pressed("a") or self:pressed("b") then self.state = "pick" end
  elseif self.state == "pick" then
    local n = #self.species
    if self:pressed("right") then self.index = self.index % n + 1
    elseif self:pressed("left") then self.index = (self.index - 2) % n + 1
    elseif self:pressed("a") then self.state, self.yes = "confirm", true end
  else
    if self:pressed("up") or self:pressed("down") then
      self.yes = not self.yes
    elseif self:pressed("b") or (self:pressed("a") and not self.yes) then
      self.state = "pick"
    elseif self:pressed("a") then
      self:finish()
    end
  end
end

-- a touch on a ball picks it (its projected point, within 24 pixels)
function Screen:touchpressed(_, x, y)
  if not (self.art and (self.state == "pick" or self.state == "confirm")) then return end
  local SS = require("src.ui.SecondScreen")
  local px, py = x, y
  if SS.toLocal then px, py = SS.toLocal(self.game, x, y) end
  for i, p in ipairs(self.ballPoints or {}) do
    if px and py and math.abs(px - p[1]) < 24 and math.abs(py - p[2]) < 24 then
      if self.index == i and self.state == "pick" then
        self.state, self.yes = "confirm", true
        self:say(20)
      elseif self.state == "pick" then
        self.index = i
        self:say(TYPE_LINE[i])
      end
      return true
    end
  end
end

-- ----------------------------------------------------------------- 3D --

function Screen:model(key)
  if self.models[key] == nil then
    local rec = self.art[key] and self.art[key].model
    local ok, m = false, nil
    if rec then ok, m = pcall(require("src.render.Gen4Model").new, rec) end
    self.models[key] = ok and m or false
  end
  return self.models[key] or nil
end

-- the baked camera's frame: rotation (degrees) and eye
local function cameraAt(track, frame)
  if not (track and track.frames and track.frames > 0) then return nil end
  local k = math.max(0, math.min(track.frames - 1, frame)) * 6
  local d = track.data
  return { d[k + 1], d[k + 2], d[k + 3] }, { d[k + 4], d[k + 5], d[k + 6] }
end

function Screen:viewProjection(track, frame)
  local Model = require("src.render.Gen4Model")
  local rot, eye = cameraAt(track, frame)
  rot, eye = rot or { -42, 0, 0 }, eye or { 0, 67.6, 45.2 }
  local rx, ry = math.rad(rot[1]), math.rad(rot[2])
  -- the camera looks down -z, turned by x (pitch) then y (yaw)
  local fx = -math.sin(ry) * math.cos(rx)
  local fy = math.sin(rx)
  local fz = -math.cos(ry) * math.cos(rx)
  local at = { eye[1] + fx, eye[2] + fy, eye[3] + fz }
  local flip = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
  return Model.multiply(flip, Model.multiply(Model.perspective(math.rad(Screen.FOV), W / H, Screen.NEAR, Screen.FAR),
                                             Model.lookAt(eye, at)))
end

local function poseOf(m, part, frame)
  local motion = part.motion
  if not motion then return nil end
  local Anim = require("src.import.Gen4Anim")
  local mf = math.max(0, math.min(frame, (motion.frames or 1) - 1))
  return m:posed(function(node)
    local track = motion.tracks[node]
    return track and Anim.unpackFrame(track, mf) or nil
  end)
end

local function translate(vp, at)
  local Model = require("src.render.Gen4Model")
  return Model.multiply(vp, { 1, 0, 0, at[1], 0, 1, 0, at[2], 0, 0, 1, at[3], 0, 0, 0, 1 })
end

-- project a world point to the 256 x 192 screen
local function project(vp, p)
  local x = vp[1] * p[1] + vp[2] * p[2] + vp[3] * p[3] + vp[4]
  local y = vp[5] * p[1] + vp[6] * p[2] + vp[7] * p[3] + vp[8]
  local w = vp[13] * p[1] + vp[14] * p[2] + vp[15] * p[3] + vp[16]
  if math.abs(w) < 1e-6 then return nil end
  return (x / w + 1) * W / 2, (y / w + 1) * H / 2
end

function Screen:render3D()
  local g = love.graphics
  local Model = require("src.render.Gen4Model")
  if not self.colour then self.colour, self.depth = Model.newTarget(W, H) end
  if not self.colour then return end
  local art = self.art
  g.push("all")
  g.setCanvas({ self.colour, depthstencil = self.depth })
  g.clear(0, 0, 0, 1, true, true)
  g.origin(); g.setScissor(); g.setColor(1, 1, 1, 1)
  local fog = Model.depthFog; Model.depthFog = nil
  local TexAnim = require("src.render.Gen4TexAnim")
  if self.state == "open" or self.state == "letter" then
    local part = art.scene1
    local m = part and self:model("scene1")
    local f = math.min(self.f, (part and part.frames or 130) - 1)
    local vp = self:viewProjection(part and part.camera, f)
    if m then
      pcall(m.draw, m, vp, poseOf(m, part, f), TexAnim.materials(part.records or {}, f, part.model.patternImages))
    end
  else
    local part = art.scene2
    local m = part and self:model("scene2")
    local f = self.f
    local vp = self:viewProjection(part and part.camera, f)
    if m then pcall(m.draw, m, vp, poseOf(m, part, f), nil) end
    local ball, bm = art.ball, self:model("ball")
    self.ballPoints = {}
    for i, at in ipairs(art.balls or {}) do
      local bf = (self.state == "chosen" and i == self.index) and self.ballFrame or 0
      if bm then
        pcall(bm.draw, bm, translate(vp, at), poseOf(bm, ball, bf),
              TexAnim.materials(ball.records or {}, bf, ball.model.patternImages))
      end
      local x, y = project(vp, { at[1], at[2] + 4, at[3] })
      self.ballPoints[i] = { x or 0, y or 0 }
    end
  end
  Model.depthFog = fog
  g.pop()
end

-- -------------------------------------------------------------- draw --

function Screen:art2D(key)
  if self.pics[key] == nil then self.pics[key] = image((self.art.images or {})[key]) or false end
  return self.pics[key] or nil
end

-- the cartridge's touch screen: the 3D box, the glove, the words
function Screen:drawMain()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  self:render3D()
  if self.colour then g.setColor(1, 1, 1, 1); g.draw(self.colour, 0, 0) end
  if (self.state == "pick" or self.state == "confirm") and self.ballPoints then
    local hand = self:art2D("hand")
    local p = self.ballPoints[self.index]
    if hand and p then
      local rec = self.art.images.hand
      local bob = math.floor(2 * math.sin(self.t / Screen.HAND_BOB * 2 * math.pi) + 0.5)
      g.setColor(1, 1, 1, 1)
      g.draw(hand, math.floor(p[1] + (rec.originX or -16)), math.floor(p[2] - 26 + bob + (rec.originY or -16)))
    end
  end
  g.setColor(1, 1, 1, 1)
  -- the words go on the other screen when there is one (the touch screen
  -- keeps the balls clear), on this one when not
  if self.box and self.box.draw and not self.dualNow then pcall(self.box.draw, self.box) end
  if not self.dualNow then self:drawLetter() end
  if self.state == "confirm" then
    Font.drawBox(23, 8, 8, 6)
    g.setColor(0, 0, 0, 1)
    Font.draw(self:line(22), 26 * 8, 10 * 8)
    Font.draw(self:line(23), 26 * 8, 12 * 8)
    Font.draw(">", 24 * 8 + 4, (self.yes and 10 or 12) * 8)
    g.setColor(1, 1, 1, 1)
  end
end

-- the cartridge's other screen: the box screen, then the stage
function Screen:drawStage(inset)
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local picking = self.state == "pick" or self.state == "confirm" or self.state == "chosen"
  if not picking then
    local box = self:art2D("box_screen")
    if box then g.draw(box, 0, 0) end
    if not inset and self.dualNow then self:drawLetter() end
    return
  end
  local tint = self.index - 1
  local stage, pedestal = self:art2D("stage_" .. tint), self:art2D("pedestal_" .. tint)
  if stage then g.draw(stage, 0, 0) end
  if pedestal then g.draw(pedestal, 0, 0) end
  local mon = self:art2D("mon_" .. (self.index - 1))
  if mon then
    local rec = self.art.images["mon_" .. (self.index - 1)]
    g.draw(mon, math.floor(W / 2 + (rec.originX or -48)), math.floor(H / 2 + (rec.originY or -48)))
  end
  g.setColor(1, 1, 1, 1)
  if not inset and self.dualNow and self.box and self.box.draw then pcall(self.box.draw, self.box) end
end

-- Juniper's letter (bank 430 #12) as one card
function Screen:drawLetter()
  if self.state ~= "letter" then return end
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  Font.drawBox(1, 4, 30, 15)
  g.setColor(0, 0, 0, 1)
  local y = 48
  for row in (self:line(12) .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(row, 16, y)
    y = y + 16
  end
  g.setColor(1, 1, 1, 1)
end

function Screen:picture(species)
  if self.pics[species] == nil then
    local ok, img = pcall(function()
      local path = Sprites.path(self.game.data, species, "front")
      return path and Assets.image(path)
    end)
    self.pics[species] = ok and img or false
  end
  return self.pics[species] or nil
end

local function drawLines(text, x, y)
  for row in (text .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(row, x, y)
    y = y + 16
  end
end

-- no imported art: the plain layout
function Screen:drawPlain()
  local g = love.graphics
  g.setColor(0.93, 0.89, 0.80, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if self.state == "letter" then
    Font.drawBox(1, 1, 30, 16)
    g.setColor(0, 0, 0, 1)
    drawLines(self:line(12), 16, 16)
    g.setColor(1, 1, 1, 1)
    return
  end
  for i, species in ipairs(self.species) do
    local cx = 40 + (i - 1) * 88
    if i == self.index then
      g.setColor(1, 0.85, 0.3, 1)
      g.rectangle("fill", cx - 34, 20, 68, 84)
    end
    g.setColor(0.85, 0.15, 0.15, 1)
    g.circle("fill", cx, 90, 10)
    g.setColor(1, 1, 1, 1)
    g.arc("fill", cx, 90, 10, 0, math.pi)
    local pic = i == self.index and self:picture(require("src.runmodes.RunHooks").shownStarter(self.game, species))
    if pic then
      local pw, ph = pic:getDimensions()
      local s = 64 / math.max(pw, ph)
      g.draw(pic, cx - pw * s / 2, 22, 0, s, s)
    end
  end
  Font.drawDialogueBox(1, 18, 30, 6)
  g.setColor(0, 0, 0, 1)
  drawLines(self:line(self.state == "pick" and (TYPE_LINE[self.index] or 19) or 20), 16, 152)
  g.setColor(1, 1, 1, 1)
  if self.state == "confirm" then
    Font.drawBox(23, 10, 8, 6)
    g.setColor(0, 0, 0, 1)
    Font.draw(self:line(22), 26 * 8, 12 * 8)
    Font.draw(self:line(23), 26 * 8, 14 * 8)
    Font.draw(">", 24 * 8 + 4, (self.yes and 12 or 14) * 8)
    g.setColor(1, 1, 1, 1)
  end
end

function Screen:draw()
  if not self.art then return self:drawPlain() end
  local SS = require("src.ui.SecondScreen")
  local dual = SS.separate and SS.separate(self.game) and SS.draw and true or false
  self.dualNow = dual
  self:drawMain()
  if dual then
    SS.draw(self.game, function() self:drawStage() end)
  elseif self.state == "pick" or self.state == "confirm" then
    -- ONE SCREEN: the stage as an inset, top right, so the Pokemon is seen
    local g = love.graphics
    self.inset = self.inset or love.graphics.newCanvas(W, H)
    g.push("all")
    g.setCanvas(self.inset)
    g.origin()
    self:drawStage(true)
    g.pop()
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", W - 98, 2, 96, 74)
    g.setColor(1, 1, 1, 1)
    g.draw(self.inset, W - 97, 3, 0, 94 / W, 72 / H)
  end
end

-- the harness: both screens, the stage at (0, 0) and the touch screen below
function Screen:drawScreens(_, bottomY)
  local g = love.graphics
  g.push("all")
  if not self.art then self:drawPlain() g.pop() return end
  self.dualNow = true
  self:drawStage()
  g.translate(0, bottomY or 196)
  self:drawMain()
  g.pop()
end

function Screen:describe()
  return ("%s index=%d f=%d"):format(self.state, self.index, self.f or 0)
end

return Screen
