-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- USING AN HM, THE WAY HOENN SHOWS IT.
--
-- Asked for directly: "we also need the transition for using HMs like the rom
-- that slides across the screen shows our pokemon and then performs the HM
-- move and our player usually holds up a ball during this too".
--
-- On the cartridge every field move goes through the same presentation before
-- anything happens to the world: a banded window sweeps across the screen
-- carrying the Pokemon's picture, and while it is up the player wears the
-- FIELD MOVE pose -- standing still with a Poke Ball held out.  The port ran
-- the effect and skipped the presentation entirely, so SURF, DIVE and the
-- rest happened with no announcement at all.
--
-- WHAT IS DERIVED AND WHAT IS NOT, said plainly.
--
-- DERIVED: the player's pose.  It is sPlayerAvatarGfxIds' sixth pair -- the
-- same table the diving suit came out of, checked the same way -- and it is a
-- real sheet of the cartridge's, not a frame picked by eye
-- (RomExtractorGen3:playerAvatarStates, constants.gen3PlayerSprites).  The
-- Pokemon's picture is its own front sprite, which the import already rips.
--
-- RECONSTRUCTED: the BAND.  Emerald's is gFieldMoveStreaksTiles, a tilemap
-- scrolled behind the picture, and the import does not rip it; nothing here
-- pretends otherwise.  What is drawn instead is the same figure -- a lit band
-- the height of the cartridge's, streaked with moving lines, sweeping in from
-- one side and out the other -- in the cartridge's own window colours where
-- the cache carries them.  The timings below are measured off the scene.

local Font = require("src.render.Font")
local Version = require("src.core.GameVersion")

local Gen3FieldMove = {}
Gen3FieldMove.__index = Gen3FieldMove
local preparing=setmetatable({},{__mode='k'})
local unpack=table.unpack or unpack
local function pack(...)return {n=select('#',...),...}end

-- RECONSTRUCTED: the beats of the sweep, in frames.
--
-- RAISE comes first and draws NOTHING, which is the point of it.
--
-- Reported from play: "i didnt see my player hold up a ball like he does in
-- the real game".  The pose was on -- it is on for the whole of this state --
-- and it was under the band: the window is fifty-six pixels tall across the
-- middle of a hundred-and-sixty-pixel screen, and the player stands in the
-- middle of the screen.  So for every frame the pose existed, the thing
-- announcing it was drawn on top of it.
--
-- The cartridge does not have that problem because it does not do the two at
-- once: the character raises the ball, and THEN the window sweeps in.  This
-- beat is that pause -- the pose is worn and nothing else is drawn -- and the
-- sweep follows it.
-- ...and how long each frame of the pose itself is held.  The sheet's frames
-- are the reach and the raise; RAISE_FRAMES is long enough for all of them at
-- this step, so the ball is up well before the band arrives.
local POSE_STEP = 5
local RAISE_FRAMES = 20
local IN_FRAMES = 18
local HOLD_FRAMES = 26
local OUT_FRAMES = 18

-- ...and the band itself, in the 240x160 screen the rest of Hoenn is drawn on
local BAND_TOP, BAND_HEIGHT = 52, 56
local STREAKS = 11

local function sameCohort(self)
  local c=self.cohort
  return c and type(c.data)=='table' and type(c.stack)=='table' and self.game.data==c.data and self.game.save==c.save
    and self.game.mods==c.mods and self.game.stack==c.stack and Version.get()==c.edition
end
local function present(self)
  if not sameCohort(self) then return false end
  for _,state in ipairs(self.cohort.stack.states or {})do if state==self then return true end end
  return false
end
local function restorePose(self)
  if self.player and not self.poseRestored then
    self.poseRestored=true
    self.player.fieldMove,self.player.fieldMovePose=self.hadPose,self.hadPoseFrame
    self.player=nil
  end
end
local function dropSprite(self)
  local sprite=self.sprite;self.sprite=nil
  if sprite and sprite.release then sprite:release()end
end

function Gen3FieldMove:uiSize()
  -- The field cut-in has GBA coordinates of its own. A mod's smaller or
  -- wider dialogue box cannot change this effect's physical screen.
  return 240,160
end

-- The two colours the band is drawn in.  The cartridge's own window palette
-- when the cache has one -- the same record the battle text box reads -- and a
-- plain blue when it does not, rather than nothing at all.
local function bandColours(game)
  local record = (game.data.constants or {}).gen3BattleTextbox
  local row = record and record.text and record.text.message
  local function norm(c, fallback)
    if type(c) ~= "table" then return fallback end
    return { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255 }
  end
  local ink = norm(row and row.foreground, { 0.96, 0.96, 1 })
  local shade = norm(row and row.shadow, { 0.16, 0.28, 0.62 })
  return shade, ink
end

local function frontPath(game, mon)
  if not (mon and mon.species) then return nil end
  local ok, path = pcall(function()
    return require("src.pokemon.Sprites").path(
      game.data, mon.species, "front", { mon = mon })
  end)
  if not (ok and type(path) == "string") then return nil end
  return require('src.render.Assets').resolve(path)
end
local function frontSprite(game, mon)
  local path=frontPath(game,mon);if not path then return nil end
  local ok,img=pcall(love.graphics.newImage,path)
  return ok and img or nil,path
end

-- Push the sweep over whatever is on screen and call `onDone` when it has
-- passed.  Returns false when there is nothing to show -- no Pokemon, or a
-- dataset with no picture for it -- so the caller can simply get on with the
-- move rather than waiting on a state that would draw nothing.
local function create(game, mon, onDone, opts)
  if not (game and game.stack and game.stack.push) then return false end
  if onDone~=nil and type(onDone)~='function'then return false end
  for _,state in ipairs(game.stack.states or {})do
    if getmetatable(state)==Gen3FieldMove and not state.done and not state.cancelled then return false end
  end
  opts=opts or {}
  local cohort=setmetatable({data=game.data,save=game.save,mods=game.mods,stack=game.stack,edition=Version.get()},{__mode='v'})
  local sprite,path = frontSprite(game, mon)
  if not sprite then return false end
  local self = setmetatable({}, Gen3FieldMove)
  self.game = game
  self.cohort=cohort
  if not sameCohort(self)then if sprite.release then sprite:release()end;return false end
  self.mon = mon
  self.sprite = sprite
  self.spritePath=path
  self.sourceOwned,self.sourceOwner=opts.sourceOwned,opts.sourceOwner
  local callback=onDone
  local completed,failed,result=false,nil,nil
  self.discardContinuation=function()
    callback=nil
    if self.cancelled or not sameCohort(self)then failed,result=nil,nil end
  end
  self.onDone=function()
    if self.cancelled or not sameCohort(self)then return false,'native field move admission retired'end
    if failed then error(failed,0)end
    if completed then
      if not result then return false,'native field move continuation is already executing'end
      return unpack(result,1,result.n)
    end
    if not self.completed or self.cancelled or not sameCohort(self)then return false,'native field move has not completed'end
    completed=true
    local fn=callback;callback=nil
    local values=pack(pcall(function()if fn then return fn()end end));fn=nil
    if not values[1]then failed=values[2];error(failed,0)end
    result={n=values.n-1};for i=2,values.n do result[i-1]=values[i]end
    return unpack(result,1,result.n)
  end
  self.t = 0
  self.phase = "raise"
  self.shade, self.ink = bandColours(game)
  -- THE POSE GOES ON HERE and comes off in finish(), so it is on screen for
  -- exactly as long as the window is -- which is what the cartridge does.
  local player = game.overworld and game.overworld.player
  if player and opts.pose~=false then
    self.player = player
    self.hadPose = player.fieldMove
    self.hadPoseFrame=player.fieldMovePose
    player.fieldMove = true
    -- the pose's own frame counter.  It lives here rather than on the player
    -- because the overworld does not update while this state is on top, so
    -- nothing else is running to count it.
    self.age = 0
    player.fieldMovePose = 0
  end
  local ok,why=pcall(game.stack.push,game.stack,self)
  if not ok then
    self:cancel()
    if game.stack.removeAll then game.stack:removeAll({self})end
    error(why,0)
  end
  if self.entryRejected then self:cancel();return false end
  return true,self
end

function Gen3FieldMove.show(game,mon,onDone,opts)
  if type(game)~='table'or preparing[game]then return false,'native field move preparation is busy'end
  preparing[game]=true
  local result=pack(pcall(create,game,mon,onDone,opts));preparing[game]=nil
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
end

function Gen3FieldMove:enter()
  local source=package.loaded['src.core.game3.field_move_show_mon']
  if source and source._nativeStart then
    local result=source._nativeStart(self)
    if result==false then self.entryRejected=true end
    return result
  end
end

-- Start wrappers configure the already-admitted native state. Changing the
-- Pokemon replaces only this admission's owned image, before its first tick.
function Gen3FieldMove:configure(mon,opts,onDone)
  if self.t~=0 or self.cancelled or not present(self)then return false,'native field-move start phase retired'end
  if type(mon)=='number'then mon={species=mon}end
  if type(mon)~='table'or type(opts)~='table'or(onDone~=nil and type(onDone)~='function')then return false,'invalid field-move start'end
  if opts.noDuck then return false,'native field-move cry ducking options are not yet available'end
  local path=frontPath(self.game,mon);if not path then return false,'native field-move picture unavailable'end
  if path~=self.spritePath then
    local ok,image=pcall(love.graphics.newImage,path)
    if not ok then return false,'native field-move picture unavailable'end
    if not present(self)or self.cancelled then if image.release then image:release()end;return false,'native field-move start phase retired'end
    dropSprite(self);self.sprite,self.spritePath=image,path
  end
  self.mon,self.onDone=mon,onDone
  if opts.pose==true and not self.player then
    local player=self.game.overworld and self.game.overworld.player
    if player then
      self.player=player;self.hadPose,self.hadPoseFrame=player.fieldMove,player.fieldMovePose
      self.poseRestored=nil;self.age=0;player.fieldMove,player.fieldMovePose=true,0
    end
  elseif opts.pose~=true and self.player then
    restorePose(self);self.player=nil
  end
  return true
end

function Gen3FieldMove:exit()
  restorePose(self);dropSprite(self)
  if not self.completed then self.discardContinuation()end
end

function Gen3FieldMove:cancel()
  self.cancelled=true;self.discardContinuation();self.onDone=nil
  restorePose(self);dropSprite(self)
  local stack=self.cohort.stack
  if stack and self.game.stack==stack and stack:top()==self then stack:pop()end
  return true
end

function Gen3FieldMove:finish()
  if self.done then return false end
  if not present(self) or self.cohort.stack:top()~=self then return false,'native field move is covered or retired'end
  self.done,self.completed = true,true
  local callback=self.onDone;self.onDone=nil
  self.cohort.stack:pop()
  if callback then return callback()end
end

local function updateBody(self)
  if self.cancelled or not sameCohort(self)then return self:cancel()end
  if self.done or not present(self) or self.cohort.stack:top()~=self then return false end
  self.t = self.t + 1
  self.frame=(self.frame or 0)+1
  if self.player then
    self.age = (self.age or 0) + 1
    -- drawPose clamps, so this simply counts upward and the pose settles on
    -- its last frame -- the ball held up -- and stays there
    self.player.fieldMovePose = math.floor(self.age / POSE_STEP)
  end
  if self.phase == "raise" and self.t >= RAISE_FRAMES then
    self.phase, self.t = "in", 0
  elseif self.phase == "in" and self.t >= IN_FRAMES then
    self.phase, self.t = "hold", 0
  elseif self.phase == "hold" and self.t >= HOLD_FRAMES then
    self.phase, self.t = "out", 0
  elseif self.phase == "out" and self.t >= OUT_FRAMES then
    self:finish()
  end
end

function Gen3FieldMove:update()
  if self.cancelled or not sameCohort(self)then return self:cancel()end
  if self.done or not present(self) or self.cohort.stack:top()~=self then return false end
  local source=package.loaded['src.core.game3.field_move_show_mon']
  if source and source._nativeStep then return source._nativeStep(self,function()return updateBody(self)end)end
  return updateBody(self)
end

-- A cutscene swallows the pad: pressing A during the sweep must not reach the
-- map underneath and start something else.
function Gen3FieldMove:keypressed() end

-- Where the band's left edge is this frame, in screen pixels: off the right
-- on the way in, across on the way out.
function Gen3FieldMove:offset(width)
  if self.phase == "in" then
    local p = math.min(1, self.t / IN_FRAMES)
    return width * (1 - p * p * (3 - 2 * p))
  end
  if self.phase == "out" then
    local p = math.min(1, self.t / OUT_FRAMES)
    return -width * (p * p * (3 - 2 * p))
  end
  return 0
end

local function drawBody(self)
  if self.cancelled or self.done or not present(self) or not self.sprite then return false end
  -- nothing at all while the ball goes up: see RAISE_FRAMES
  if self.phase == "raise" then return end
  local w = select(1, self:uiSize())
  local dx = self:offset(w)
  local g = love.graphics

  -- the band
  g.setColor(self.shade[1], self.shade[2], self.shade[3], 1)
  g.rectangle("fill", dx, BAND_TOP, w, BAND_HEIGHT)
  -- ...and the streaks running through it, which are what make it read as a
  -- sweep rather than a bar
  g.setColor(self.ink[1], self.ink[2], self.ink[3], 0.35)
  local frame = (self.frame or 0)
  for i = 1, STREAKS do
    local y = BAND_TOP + 3 + (i - 1) * math.floor((BAND_HEIGHT - 6) / STREAKS)
    local len = 40 + (i * 37) % 90
    local x = dx + ((frame * 6 + i * 53) % (w + len)) - len
    g.rectangle("fill", x, y, len, 2)
  end
  -- the two edges, so the band has a shape rather than fading into the map
  g.setColor(self.ink[1], self.ink[2], self.ink[3], 1)
  g.rectangle("fill", dx, BAND_TOP, w, 1)
  g.rectangle("fill", dx, BAND_TOP + BAND_HEIGHT - 1, w, 1)

  -- the Pokemon, riding the band a third of the way across
  local iw, ih = self.sprite:getDimensions()
  local scale = math.min(1, (BAND_HEIGHT + 16) / ih)
  local x = math.floor(dx + w / 3 - iw * scale / 2)
  local y = math.floor(BAND_TOP + (BAND_HEIGHT - ih * scale) / 2)
  g.setColor(1, 1, 1, 1)
  g.draw(self.sprite, x, y, 0, scale, scale)
  require("src.render.PaletteFX").markTrueColor(
    x, y, math.ceil(iw * scale), math.ceil(ih * scale))

  -- and its name, which is what the cartridge writes on the band
  local name = self.mon and (self.mon.nickname
    or (self.game.data.pokemon[self.mon.species] or {}).name)
  if name then
    Font.pushStyle({ text = self.ink, shadow = self.shade })
    Font.draw(name, math.floor(dx + w / 2 + 8),
              math.floor(BAND_TOP + (BAND_HEIGHT - Font.glyphHeight()) / 2))
    Font.popStyle()
  end
  g.setColor(1, 1, 1, 1)
end

function Gen3FieldMove:drawExternal()
  if self.cancelled or self.done or not present(self)then return false end
  local result=drawBody(self)
  self.externalDrawFrame=require('src.render.Renderer').frameSerial
  return result~=false
end

function Gen3FieldMove:draw()
  if self.cancelled or self.done or not present(self)then return false end
  local serial=require('src.render.Renderer').frameSerial
  if serial and self.externalDrawFrame==serial then return true end
  local source=package.loaded['src.core.game3.field_move_show_mon']
  if source and source._nativeDraw then return source._nativeDraw(self,function()return drawBody(self)end)end
  return drawBody(self)
end

Gen3FieldMove.present=present
Gen3FieldMove.cohortCurrent=sameCohort

return Gen3FieldMove
