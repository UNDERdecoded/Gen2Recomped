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
-- DEFAULT PRESENTATION: the BAND.  Emerald's is gFieldMoveStreaksTiles, a tilemap
-- scrolled behind the picture, and the import does not rip it; nothing here
-- pretends otherwise.  What is drawn instead is the same figure -- a lit band
-- the height of the cartridge's, streaked with moving lines, sweeping in from
-- one side and out the other -- in the cartridge's own window colours where
-- the cache carries them.  The timings below are measured off the scene.

-- Compatible observers may select the independently imported cartridge strips
-- and presentation program. The native default below remains available.
local Font = require("src.render.Font")

local Gen3FieldMove = {}
Gen3FieldMove.__index = Gen3FieldMove
local Version=require('src.core.GameVersion')
local Presentation=require('src.world.Gen3FieldMovePresentation')
local allocations=setmetatable({},{__mode='k'})
local preparing=setmetatable({},{__mode='k'})
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function release(x)if x and x.release then pcall(x.release,x)end end
local function source()return Version.isGen3()and package.loaded['src.core.game3.field_move_show_mon']end
local function nativeWorld(game)
  local session=Version.isGen3()and package.loaded['src.compat.gen1.NativeSession']
  if session and session.resolve then
    local owner,world=session.resolve(game);if owner==game then return world end
    return nil
  end
  return game.overworld
end
local function valid(self,top)
  if self.done then return false end
  local c=self.cohort;local game=self.game
  if c and not self:cohortCurrent()then return false end
  local stack=game.stack;local states=stack and stack.states
  if type(states)=='table'then
    local found=false;for _,s in ipairs(states)do if s==self then found=true;break end end
    if not found or top and states[#states]~=self then return false end
  end
  return true
end

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

function Gen3FieldMove:uiSize()
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
local function frontSprite(game,mon)
  local path=frontPath(game,mon);if not path then return nil end
  local ok,img=pcall(love.graphics.newImage,path)
  return ok and img or nil,path
end

-- Push the sweep over whatever is on screen and call `onDone` when it has
-- passed.  Returns false when there is nothing to show -- no Pokemon, or a
-- dataset with no picture for it -- so the caller can simply get on with the
-- move rather than waiting on a state that would draw nothing.
local function create(game, mon, onDone, opts)
  if not(game and game.stack and game.stack.push)or(onDone~=nil and type(onDone)~='function')then return false end
  for _,state in ipairs(game.stack.states or{})do if getmetatable(state)==Gen3FieldMove and not state.done then return false,'native field move is busy'end end
  local world=nativeWorld(game)
  if Version.isGen3()and not world then return false,'no admitted native field world'end
  local cohort=setmetatable({data=game.data,save=game.save,mods=game.mods,stack=game.stack,edition=Version.get(),world=world,actor=world and world.player,map=world and world.map},{__mode='v'})
  local facade=source()
  opts=opts or(facade and facade._nativeOptions and facade._nativeOptions(game))or{}
  local sprite,path = frontSprite(game, mon)
  if not sprite then return false end
  local self = setmetatable({}, Gen3FieldMove)
  self.game = game
  self.mon = mon
  self.sprite = sprite;self.spritePath=path
  self.t = 0
  self.frame=0;self.options=opts
  self.phase = "raise"
  self.shade, self.ink = bandColours(game)
  -- THE POSE GOES ON HERE and comes off in finish(), so it is on screen for
  -- exactly as long as the window is -- which is what the cartridge does.
  local player = world and world.player
  self.actor=player
  self.cohort=cohort
  if not self:cohortCurrent()then release(sprite);return false,'native field move preparation cohort retired'end
  self.sourceOwned=opts.sourceStarted==true or opts.sourceOwned==true;self.sourceOwner=opts.sourceOwner
  local callback=onDone;local outcome,err,running
  self.discardContinuation=function()callback=nil;outcome=nil;err=nil end
  self.onDone=function()
    if self.cancelled or not self:cohortCurrent()then return false,'native field move admission retired'end
    if err then error(err,0)end
    if outcome then return unpack(outcome,1,outcome.n)end
    if running or not(self.completed and self.callbackReady)then return false,'native field move has not completed'end
    running=true;local fn=callback;callback=nil
    local values=pack(pcall(function()if fn then return fn()end end));fn=nil
    if not values[1]then err=values[2];error(err,0)end
    outcome={n=values.n-1};for i=2,values.n do outcome[i-1]=values[i]end
    return unpack(outcome,1,outcome.n)
  end
  allocations[self]={front=sprite}
  if opts.presentation=='cartridge'then
    self.effect=Presentation.new(mon,opts,game,world)
    local ok,why=self:reloadArtwork()
    if not ok then self:exit();return false,why end
  end
  if player and(not self.effect and opts.pose~=false or self.effect and self.effect.posed)then
    self.player=player
    self.hadPose = player.fieldMove
    self.hadPoseFrame=player.fieldMovePose
    self.hadPoseOwner=player._gen3FieldMovePoseOwner
    player._gen3FieldMovePoseOwner=self
    self.poseInstalled=true
    player.fieldMove = true
    -- the pose's own frame counter.  It lives here rather than on the player
    -- because the overworld does not update while this state is on top, so
    -- nothing else is running to count it.
    self.age = 0
    player.fieldMovePose = 0
  end
  local ok,why=pcall(game.stack.push,game.stack,self)
  if not ok then
    local stack=cohort.stack
    if stack and stack.removeAll then stack:removeAll({self})else self:exit()end
    return false,why
  end
  if self.entryRejected then self:retire();return false,'native field move start vetoed'end
  return true,self
end
function Gen3FieldMove.show(game,mon,onDone,opts)
  if type(game)~='table'or preparing[game]then return false,'native field move preparation is busy'end
  preparing[game]=true
  local result=pack(pcall(create,game,mon,onDone,opts));preparing[game]=nil
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
end
function Gen3FieldMove:cohortCurrent()
  local c=self.cohort;local game=self.game
  return c and game.data==c.data and game.save==c.save and game.mods==c.mods and game.stack==c.stack
    and Version.get()==c.edition and nativeWorld(game)==c.world
    and(not c.world or c.world.player==c.actor and c.world.map==c.map)
end
function Gen3FieldMove:configurePresentation(opts)
  if self.frame~=0 then return false,'field move options belong to admission'end
  local player=self.actor
  local posed=opts.pose==true
  if self.poseInstalled and not posed and player._gen3FieldMovePoseOwner==self then
    player.fieldMove,player.fieldMovePose,player._gen3FieldMovePoseOwner=self.hadPose,self.hadPoseFrame,self.hadPoseOwner
    self.poseInstalled=false;self.player=nil
  elseif posed and not self.poseInstalled and player then
    self.player=player
    self.hadPose,self.hadPoseFrame,self.hadPoseOwner=player.fieldMove,player.fieldMovePose,player._gen3FieldMovePoseOwner
    player.fieldMove,player.fieldMovePose,player._gen3FieldMovePoseOwner=true,0,self;self.poseInstalled=true
  end
  if self.effect then
    self.effect.posed=posed;self.effect.phase=posed and'pose'or 1;self.effect.poseWait=24
    self.effect.noDuck=opts.noDuck==true
  end
  return true
end

function Gen3FieldMove:configure(mon,opts,callback)
  if not valid(self,true)or self.frame~=0 then return false,'native field move start phase retired'end
  if type(mon)~='table'or type(opts)~='table'or(callback~=nil and type(callback)~='function')then return false,'invalid field move options'end
  local path=frontPath(self.game,mon);if not path then return false,'native field move picture unavailable'end
  if path~=self.spritePath then
    local sprite=frontSprite(self.game,mon);if not sprite then return false,'native field move picture unavailable'end
    if not valid(self,true)then release(sprite);return false,'native field move admission retired'end
    local own=allocations[self];release(own.front);own.front=sprite;self.sprite=sprite;self.spritePath=path
  end
  self.mon=mon;if self.effect then self.effect.species,self.effect.personality=mon.species,mon.personality end
  local ok,why=self:configurePresentation(opts);if not ok then return false,why end
  self.onDone=callback;return true
end
function Gen3FieldMove:reloadArtwork()
  if not self.effect then return true end
  local parts={}
  local ok,result=pcall(function()
    local bytes,why=Presentation.rgba(self.game,self.effect.outdoors and'outdoors'or'indoors');assert(bytes,why)
    local data=love.image.newImageData(256,80,'rgba8',bytes);parts[#parts+1]=data
    local image=love.graphics.newImage(data);parts[#parts+1]=image;image:setFilter('nearest','nearest')
    local q=love.graphics.newQuad(0,0,1,1,256,80);parts[#parts+1]=q
    local c=self.cohort
    assert(self.game.data==c.data and self.game.save==c.save and self.game.mods==c.mods and Version.get()==c.edition,'field move artwork cohort retired')
    return{band=image,quad=q,parts=parts}
  end)
  if not ok then for _,x in ipairs(parts)do release(x)end;return false,tostring(result)end
  local own=allocations[self]
  if own.presentation then for _,x in ipairs(own.presentation.parts)do release(x)end end
  own.presentation=result;return true
end
function Gen3FieldMove:enter()
  local facade=source();if facade and facade._nativeStart then
    local result=facade._nativeStart(self);if result==false then self.entryRejected=true end;return result
  end
end
function Gen3FieldMove:exit()
  self.onDone=nil
  if not self.completed and self.discardContinuation then self.discardContinuation()end
  local own=allocations[self];allocations[self]=nil
  if self.poseInstalled and self.player and self.player._gen3FieldMovePoseOwner==self then
    self.player.fieldMove=self.hadPose;self.player.fieldMovePose=self.hadPoseFrame
    self.player._gen3FieldMovePoseOwner=self.hadPoseOwner
  end
  self.poseInstalled=false;self.sprite=nil
  if own then
    release(own.front)
    if own.presentation then for _,x in ipairs(own.presentation.parts)do release(x)end end
  end
  local facade=source();if facade and facade._nativeExit then facade._nativeExit(self)end
end
function Gen3FieldMove:retire()
  self.done=true;self.cancelled=true;self.completed=false;self.onDone=nil
  if self.discardContinuation then self.discardContinuation()end
  local stack=self.cohort and self.cohort.stack
  if stack and stack.removeAll then stack:removeAll({self})end
  self:exit()
end
function Gen3FieldMove:complete(completed)
  if not valid(self,true)then return false,'native field move is covered, retired or finished'end
  self.done = true
  self.completed=completed==true;self.cancelled=not self.completed
  local callback=self.onDone;self.onDone=nil
  local ok,why=true
  if self.game.stack then ok,why=pcall(self.game.stack.pop,self.game.stack)end
  self:exit()
  self.callbackReady=true
  if completed and callback then callback()end
  if not ok then error(why,0)end
  return true
end
function Gen3FieldMove:finish()
  return self:complete(true)
end

function Gen3FieldMove:updateBody()
  if not valid(self,true)then return false end
  self.frame=self.frame+1
  self.t = self.t + 1
  if self.poseInstalled and self.player._gen3FieldMovePoseOwner==self then
    self.age = (self.age or 0) + 1
    -- drawPose clamps, so this simply counts upward and the pose settles on
    -- its last frame -- the ball held up -- and stays there
    self.player.fieldMovePose = math.floor(self.age / POSE_STEP)
  end
  if self.effect then
    local done=Presentation.advance(self.effect,function()
      require('src.core.Sound').playCry(self.game.data,self.mon.species,self.effect.noDuck and{noDuck=true,volume=125}or nil)
    end)
    if done then return self:finish()end
    return
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
  if not valid(self,false)then if not self.done then self:retire()end;return false end
  if not valid(self,true)then return false end
  local facade=source()
  if facade and facade._nativeStep then return facade._nativeStep(self,function()return self:updateBody()end)end
  return self:updateBody()
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

function Gen3FieldMove:drawBody()
  if not valid(self,false)then return false end
  if self.effect then
    local own=allocations[self]
    if own and own.presentation then return Presentation.draw(self.effect,own.presentation,self.sprite or own.front)end
    return false
  end
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
  local frame=self.frame
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
function Gen3FieldMove:draw()
  if not valid(self,false)then return false end
  local renderer=package.loaded['src.render.Renderer']
  if self.externalDrawSerial and renderer and self.externalDrawSerial==renderer.frameSerial then return true end
  local facade=source()
  if facade and facade._nativeDraw then return facade._nativeDraw(self,function()return self:drawBody()end)end
  return self:drawBody()
end
Gen3FieldMove.valid=valid
Gen3FieldMove.present=function(self)return valid(self,false)end
Gen3FieldMove.cancel=Gen3FieldMove.retire
function Gen3FieldMove:drawExternal()
  local result=self:drawBody()
  local renderer=package.loaded['src.render.Renderer'];self.externalDrawSerial=renderer and renderer.frameSerial
  return result
end

return Gen3FieldMove
