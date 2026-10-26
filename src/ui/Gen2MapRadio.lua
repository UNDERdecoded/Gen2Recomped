-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- A wall radio owns its native script until the player closes the broadcast.
-- Native Pokegear program text is reused; this is not a ROM show-state port.
local Radio=require("src.world.Gen2Radio")
local Gear=require("src.ui.PokegearMenu")
local M={};M.__index=M;M.isOpaque=false
function M.new(game,opts)
  opts=opts or {}
  assert(require("src.core.GameVersion").isGen2(),"MapRadio requires a Gen2 host")
  if opts.save and opts.save~=game.save then game=setmetatable({save=opts.save,writeSave=false},{__index=game})end
  local world=game.overworld
  local map=world and world.map
  map=map and (map.def or map)
  local tod=opts.timeOfDay or (world and world.timeOfDay and world:timeOfDay()) or "DAY"
  local channel=tonumber(opts.channel) or 0
  local self=setmetatable({game=game,onDone=opts.onDone,channel=channel,hold=100,frames=0,line=1},M)
  self.map,self.tod=map,tod
  self.station=self:resolveStation(channel)
  -- Reuse only the drawing/program helpers. Opening a wall radio must not
  -- initialize Pokegear cards, roaming encounters or its portrait sheets.
  self.gear=setmetatable({game=game},{__index=Gear})
  for _,row in ipairs(self.gear:stationList())do if row.id==self.station then self.program=row;break end end
  if self.station then self.music=require("src.world.Gen2RadioAudio").tune(game,self.station)end
  Radio.notify(game.data,self.station,channel,"map_radio")
  return self
end
function M:exit()
  local playing=self.music;self.music=nil
  require("src.world.Gen2RadioAudio").finish(self.game,playing)
end
function M:name()return self.station and Radio.stationName(self.game.data,self.station)end
function M:resolveStation(channel)
  local id=Radio.resolve(self.game.data,channel,self.map,self.tod)
  return id,id and Radio.stationName(self.game.data,id)
end
function M:close()
  if self.closed or self.game.stack:top()~=self then return false end
  self.closed=true
  self.game.stack:pop()
  if self.onDone then self.onDone()end
  return true
end
function M:update(_dt)
  if self.closed then return end
  if self.hold>0 then self.hold=self.hold-1;return end
  local input=self.game.input
  if input and (input:wasPressed("a") or input:wasPressed("b"))then self:close();return end
  self.frames=self.frames+1
  local lines=self.program and self.program.lines or {}
  if self.frames%100==0 and #lines>0 then self.line=self.line+2;if self.line>#lines then self.line=1 end end
end
function M:draw()
  self.gear:textbox(0,12,18,4)
  local lines=self.program and self.program.lines or {}
  if self.hold>0 or #lines==0 then self.gear:text('"'..(self:name() or '')..'"',1,14,Radio.isLiteral(self.game.data,self.station))
  else self.gear:printBoxText(lines[self.line] or "",lines[self.line+1] or "")end
end
M.channelRecord=Radio.channelRecord
M.STATIONS=Radio.STATIONS
function M.registerInto(registry,data,owner)
  local n=0
  for id,row in pairs(Radio.defaults())do registry:register(id,row,owner);n=n+1 end
  return n
end
return M
