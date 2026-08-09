-- Surfing Pikachu minigame (engine/minigame/surfing_pikachu.asm): the
-- Summer Beach House wave run.  Paddle for speed, launch off the wave,
-- spin in the air and land flat for points; a crooked landing wipes out
-- and ends the run.  The scene is built from the real ROM sheets
-- (gfx/surfing_pikachu.asm, ripped at import to
-- assets/generated/minigame/surf_1a/1b.png): the scalloped water tiles,
-- the beach with the palm and the doll hut, the "HP:" score strip with
-- the sheet digits, the cloud, and the OAM Pikachu poses -- the air
-- tricks quantize to the sheet's rotation frames like the original's
-- sprite anims, instead of free-rotating one pose.  The original drew
-- the big wave with per-scanline scroll tricks (wLYOverrides); here the
-- crest profile is a curve filled with the sheet's foam/shade tiles.
-- Score model keeps the original's shape (ride ticks + airtime + full
-- rotations); high score persists in save.surfingHighScore for the
-- beach-house printer.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Music = require("src.core.Music")
local Sound = require("src.core.Sound")

local SurfingMinigame = {}
SurfingMinigame.__index = SurfingMinigame
SurfingMinigame.isOpaque = true

local PIKA_X = 44         -- fixed screen x while riding
local RUN_DISTANCE = 3200 -- scroll px from paddle-out to the beach
local GRAVITY = 0.14
local HORIZON = 24        -- sea starts under the sky strip

-- surf_1b quads: {x, y, w, h} in sheet pixels (pose pitch is 24x24)
local B = {
  digits = { x = 0, y = 104 },              -- "0123456789", 8x8 each
  good   = { 0, 72, 32, 8 },
  yeah   = { 32, 72, 32, 8 },
  ohno   = { 80, 96, 48, 24 },
  splash = { 48, 80, 32, 24 },
  cloud  = { 96, 112, 32, 8 },
  paddle = { { 0, 80, 24, 24 }, { 24, 80, 24, 24 } },
}
-- rotation frames, 45-degree buckets clockwise from upright
local POSES = {
  [0]   = { 48, 0, 24, 24 },   -- upright ride
  [45]  = { 24, 0, 24, 24 },   -- nose down
  [90]  = { 0, 48, 24, 24 },   -- board vertical
  [135] = { 48, 48, 24, 24 },  -- tumbling
  [180] = { 72, 48, 24, 24 },  -- upside down
  [225] = { 48, 48, 24, 24 },
  [270] = { 0, 48, 24, 24 },
  [315] = { 0, 0, 24, 24 },    -- tail down
}

-- surf_1a quads (BG tiles)
local A = {
  scallop  = { 16, 0, 8, 8 },   -- open-water pattern, row A
  scallop2 = { 16, 8, 8, 8 },   -- row B variant
  shade    = { 8, 16, 8, 8 },   -- gray dither, wave belly
  lip      = { 24, 0, 8, 8 },   -- foam curl for the crest edge
  palm     = { 8, 32, 8, 8 },   -- palm fronds
  beach    = { 24, 32, 16, 8 }, -- black shore silhouette
  hut      = { 8, 40, 16, 8 },  -- the Pikachu doll hut on the sand
  hp       = { 20, 40, 20, 8 }, -- "HP:" score label
}

-- SGB-style zones: one sea palette over the frame plus a yellow
-- OBJ-flavored palette tracking Pikachu's tiles (rectangular attribute
-- blocks are all the SGB could do, bleed and all)
local SEA_PAL = { { 255, 255, 255 }, { 112, 184, 248 },
                  { 56, 120, 216 }, { 0, 0, 0 } }
local PIKA_PAL = { { 255, 255, 255 }, { 248, 216, 64 },
                   { 224, 144, 32 }, { 0, 0, 0 } }

local function newQuad(spec, img)
  return love.graphics.newQuad(spec[1], spec[2], spec[3], spec[4],
                               img:getDimensions())
end

function SurfingMinigame.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone }, SurfingMinigame)
  self.phase = "ride"     -- ride | air | wipeout | results
  self.t = 0
  self.distance = 0
  self.speed = 2
  self.score = 0
  self.rideTick = 0
  self.y = 0              -- air offset above the wave (positive = up)
  self.vy = 0
  self.rot = 0            -- degrees, accumulates through the air
  self.spins = 0
  self.airFrames = 0
  self.resultShown = 0
  self.banner = nil       -- {quad, frames}: GOOD!/YEAH-/Oh no..

  local function sheet(path)
    local ok, img = pcall(love.graphics.newImage, path)
    return ok and img or nil
  end
  self.bg = sheet("assets/generated/minigame/surf_1a.png")
  self.ob = sheet("assets/generated/minigame/surf_1b.png")
  if self.bg then
    self.aq = {}
    for k, spec in pairs(A) do self.aq[k] = newQuad(spec, self.bg) end
  end
  if self.ob then
    self.bq = {}
    for k, spec in pairs(B) do
      if spec[3] then self.bq[k] = newQuad(spec, self.ob) end
    end
    self.bq.paddle = { newQuad(B.paddle[1], self.ob),
                       newQuad(B.paddle[2], self.ob) }
    self.bq.poses = {}
    for deg, spec in pairs(POSES) do
      self.bq.poses[deg] = newQuad(spec, self.ob)
    end
    self.bq.digit = {}
    for d = 0, 9 do
      self.bq.digit[d] = love.graphics.newQuad(B.digits.x + d * 8,
        B.digits.y, 8, 8, self.ob:getDimensions())
    end
  end
  Music.play(game.data, "Music_SurfingPikachu")
  return self
end

-- crest height at screen x for the current scroll (two sines so the
-- wave rolls instead of looping visibly)
function SurfingMinigame:seaY(x)
  local s = self.distance + x
  return 92 - 14 * math.sin(s / 26) - 6 * math.sin(s / 9.5)
end

function SurfingMinigame:finishRun()
  self.phase = "results"
  local save = self.game.save
  self.newRecord = self.score > (save.surfingHighScore or 0)
  if self.newRecord then save.surfingHighScore = self.score end
  Music.stop()
  Sound.play(self.game.data, self.newRecord and "Get_Item1" or "Ball_Poof")
end

function SurfingMinigame:update()
  local input = self.game.input
  self.t = self.t + 1
  if self.banner then
    self.banner.frames = self.banner.frames - 1
    if self.banner.frames <= 0 then self.banner = nil end
  end
  if self.phase == "results" then
    self.resultShown = self.resultShown + 1
    if self.resultShown > 30
       and (input:wasPressed("a") or input:wasPressed("b")) then
      self.game.stack:pop()
      if self.onDone then self.onDone(self.score) end
    end
    return
  end
  if self.phase == "wipeout" then
    self.splash = (self.splash or 0) + 1
    if self.splash > 70 then self:finishRun() end
    return
  end

  -- the wave scrolls by the current speed; the beach ends the run
  self.distance = self.distance + 0.8 + self.speed * 0.35
  if self.distance >= RUN_DISTANCE then
    -- rode it all the way in: distance bonus like the original's goal
    self.score = self.score + 500
    self:finishRun()
    return
  end

  if self.phase == "ride" then
    -- paddling: mash A for speed, it bleeds off on its own
    if input:wasPressed("a") and self.speed < 8 then
      self.speed = self.speed + 1
    end
    if self.t % 45 == 0 and self.speed > 2 then
      self.speed = self.speed - 1
    end
    self.rideTick = self.rideTick + 1
    if self.rideTick % 12 == 0 then self.score = self.score + 1 end
    -- launch off the lip
    if input:wasPressed("up") then
      self.phase = "air"
      self.vy = 1.6 + self.speed * 0.45
      self.rot, self.spins, self.airFrames = 0, 0, 0
      Sound.play(self.game.data, "Ledge_Jump")
    end
  elseif self.phase == "air" then
    self.airFrames = self.airFrames + 1
    self.vy = self.vy - GRAVITY
    self.y = self.y + self.vy
    -- tricks: hold either direction to spin
    local spin = (input:isDown("left") and -6 or 0)
               + (input:isDown("right") and 6 or 0)
    self.rot = self.rot + spin
    if math.abs(self.rot) >= (self.spins + 1) * 360 then
      self.spins = self.spins + 1
    end
    if self.y <= 0 and self.vy < 0 then
      self.y = 0
      local tilt = math.abs(self.rot) % 360
      if tilt <= 60 or tilt >= 300 then
        -- clean landing: airtime + full rotations pay out
        self.score = self.score + self.spins * 100
                     + math.floor(self.airFrames / 4)
        self.phase = "ride"
        self.banner = { quad = self.spins > 0 and "yeah" or "good",
                        frames = 50 }
        Sound.play(self.game.data, "Cut")
      else
        self.phase = "wipeout"
        self.splash = 0
        self.banner = { quad = "ohno", frames = 70 }
        Sound.play(self.game.data, "Faint_Fall")
      end
    end
  end
end

-- draw one 8x8 sheet tile quad at x, y
function SurfingMinigame:tile(q, x, y)
  love.graphics.draw(self.bg, self.aq[q], x, y)
end

function SurfingMinigame:sgbPalettes()
  local P = require("src.render.PaletteFX")
  local zones = { P.whole(SEA_PAL) }
  if self.phase ~= "wipeout" and self.phase ~= "results" then
    local tx = math.floor((PIKA_X - 12) / 8)
    local ty = math.floor(math.max(0, self.pikaScreenY or 60) / 8)
    zones[#zones + 1] = P.zone(PIKA_PAL, tx, ty, tx + 3, ty + 3)
  end
  return zones
end

function SurfingMinigame:drawScore(x, y, n)
  local s = tostring(n)
  for i = 1, #s do
    love.graphics.draw(self.ob, self.bq.digit[tonumber(s:sub(i, i))],
                       x + (i - 1) * 8, y)
  end
end

function SurfingMinigame:draw()
  local haveSheets = self.bg and self.ob
  -- sky
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  if not haveSheets then
    -- cache predates the surf sheets: plain shapes keep it playable
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("SCORE %d", self.score), 4, 4)
    love.graphics.rectangle("fill", PIKA_X - 8,
      self:seaY(PIKA_X) - 16 - self.y, 16, 16)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- cloud in the sky strip
  love.graphics.draw(self.ob, self.bq.cloud, 112, 8)

  -- open water: the scalloped pattern tiles the whole sea, phase-locked
  -- to the scroll so the surface slides
  local shift = math.floor(self.distance) % 8
  for ty = HORIZON, 136, 8 do
    local alt = (ty / 8) % 2 == 0
    for tx = -8, 160, 8 do
      self:tile(alt and "scallop" or "scallop2", tx - shift, ty)
    end
  end

  -- the wave face: a white patch hugging the ride line (the original
  -- carved it with per-scanline scroll; the ellipse stands in), with a
  -- few scallops floating inside and the foam lip along its upper edge
  local faceY = self:seaY(56) + 10
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.ellipse("fill", 56, faceY, 46, 30)
  love.graphics.ellipse("fill", 100, faceY + 16, 40, 22)
  for _, spot in ipairs({ { 30, 8 }, { 70, 16 }, { 48, 22 } }) do
    self:tile("scallop", 56 - 46 + spot[1] - shift, faceY - 24 + spot[2])
  end
  local pikaY = self:seaY(PIKA_X) - 20 - self.y
  for a = 205, 335, 18 do
    local r = math.rad(a)
    local lx = 56 + math.cos(r) * 44 - 4
    local ly = faceY + math.sin(r) * 28 - 4
    -- foam that would land inside Pikachu's SGB zone comes out orange;
    -- leave that patch to the spray ellipse instead
    if math.abs(lx - PIKA_X) > 28 or math.abs(ly - (pikaY + 12)) > 26 then
      self:tile("lip", lx, ly)
    end
  end
  self:tile("shade", 92 - shift, faceY + 20)
  self:tile("shade", 116 - shift, faceY + 24)

  -- beach slides through at the start and again before the goal
  local beachX
  if self.distance < 160 then
    beachX = -self.distance
  elseif self.distance > RUN_DISTANCE - 200 then
    beachX = 160 - (self.distance - (RUN_DISTANCE - 200))
  end
  if beachX then
    for tx = 0, 32, 8 do
      self:tile("beach", beachX + tx, 128)
      self:tile("beach", beachX + tx, 136)
    end
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", beachX + 9, 118, 2, 10)
    love.graphics.setColor(1, 1, 1, 1)
    self:tile("palm", beachX + 6, 112)
    self:tile("hut", beachX + 20, 118)
  end

  -- Pikachu.  The white spray patch under him doubles as the yellow SGB
  -- zone's backdrop: shade 0 maps to white in both palettes, so the
  -- attribute-block bleed never shows on the water pattern.
  love.graphics.setColor(1, 1, 1, 1)
  local py = self:seaY(PIKA_X) - 20 - self.y
  self.pikaScreenY = py -- the yellow SGB zone tracks this
  love.graphics.ellipse("fill", PIKA_X, py + 12, 25, 21)
  if self.phase == "wipeout" then
    love.graphics.draw(self.ob, self.bq.splash, PIKA_X - 16,
                       self:seaY(PIKA_X) - 16)
  else
    local quad
    if self.phase == "ride" and self.speed <= 2
       and self.distance < 120 then
      quad = self.bq.paddle[math.floor(self.t / 8) % 2 + 1]
    else
      local bucket = math.floor(((self.rot % 360) + 22.5) / 45) % 8 * 45
      quad = self.bq.poses[bucket] or self.bq.poses[0]
    end
    love.graphics.draw(self.ob, quad, PIKA_X - 12, py)
  end

  -- banner beats: GOOD! / YEAH- / Oh no..
  if self.banner and self.bq[self.banner.quad] then
    love.graphics.draw(self.ob, self.bq[self.banner.quad], 60, 40)
  end

  -- score strip, bottom right: HP: + sheet digits
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 100, 134, 60, 10)
  love.graphics.draw(self.bg, self.aq.hp, 102, 135)
  self:drawScore(126, 135, self.score)

  if self.phase == "results" then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 20, 48, 120, 48)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", 20.5, 48.5, 119, 47)
    Font.draw(Strings("SCORE %d", self.score), 32, 56)
    if self.newRecord then
      Font.draw(Strings("New record!"), 32, 68)
    else
      Font.draw(Strings("HI    %d", self.game.save.surfingHighScore or 0),
                32, 68)
    end
    if self.resultShown > 30 then
      Font.draw(Strings("A: done"), 32, 82)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return SurfingMinigame
