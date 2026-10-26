-- Native BGM command state. Source construction stays with the music service.
local SongIds = require("src.core.Gen3SongIds")
local NativeMusic = {}
NativeMusic.__index = NativeMusic
function NativeMusic.new(host)
  return setmetatable({ host = host, serial = 0 }, NativeMusic)
end
function NativeMusic:resolve(value)
  return SongIds.resolve(value, self.host.version())
end
function NativeMusic:setLevel(value, apply)
  self.level = value
  self.host.level(value, apply)
end
function NativeMusic:reset()
  self:cancelFanfare()
  self.current, self.mapSong, self.savedSong = nil, nil, nil
  self.fadeOut, self.fadeIn, self.deferred = nil, nil, nil
  self.serial = self.serial + 1
  self:setLevel(self.host.master())
end
function NativeMusic:cancelFanfare()
  self.fanfareActive, self.fanfareFrames, self.bgmPaused = false, 0, false
  self.fanfareRestore, self.deferred = nil, nil
  if self.fanfareWait then
    self.fanfareWait.done = true
    self.fanfareWait = nil
  end
end
function NativeMusic:stopped()
  self.fanfareRestore = nil
  self.current, self.fadeOut, self.fadeIn, self.deferred = nil, nil, nil, nil
  self.serial = self.serial + 1
  self:setLevel(self.host.master())
end
function NativeMusic:started(id, preparing)
  self.fanfareActive, self.fanfareFrames, self.bgmPaused, self.fanfareRestore = false, 0, false, nil
  self.current = { id = id }
  self.mapSong = self.mapSong or id
  self.fadeOut, self.fadeIn, self.deferred = nil, nil, nil
  self.serial = self.serial + 1
  self:setLevel(self.host.master(), not preparing)
end
function NativeMusic:setSavedSong(value)
  local id = self:resolve(value)
  self.savedSong = id ~= 0 and id ~= 0xFFFF and id or nil
end
function NativeMusic:setMapSong(value)
  self.mapSong = self:resolve(value)
end
function NativeMusic:playSong(data, value, forced)
  local id = self:resolve(value)
  if id == nil or id == 0 or id == 0xFFFF then
    self.host.stop()
    self:stopped()
    return true
  end
  if require("src.core.Gen3Fanfare").isSong(data, id) then
    return self:playFanfare(data, id)
  end
  if not forced and self.current and self.current.id == id and not self.fadeOut then
    if self.fanfareActive then
      self.deferred = nil
    end
    return true
  end
  local restart = forced or self.fadeOut ~= nil
  self:started(id, true)
  self.host.play(data, id, restart)
  -- Missing output hardware does not erase the native command's logical song.
  self.current = { id = id }
  self.mapSong = self.mapSong or id
  return true
end
function NativeMusic:currentMapMusic()
  if self.fanfareActive and self.deferred ~= nil then
    return self.deferred
  end
  if self.fadeOut then
    return self.fadeOut.nextSong or 0
  end
  return self.current and self.current.id or 0
end
function NativeMusic:refresh(apply)
  local level = self.host.master()
  if self.fadeOut then
    local f = self.fadeOut
    local u = math.min(1, f.t / math.max(f.dur, 0.01))
    level = self.host.shared() and self.host.sharedLevel(1 - u) or f.start * (1 - u)
  elseif self.fadeIn then
    local u = math.min(1, self.fadeIn.t / math.max(self.fadeIn.dur, 0.01))
    level = self.host.shared() and self.host.sharedLevel(u) or level * u
  end
  self:setLevel(level, apply)
end
function NativeMusic:optionChanged(apply)
  -- A shared file override receives its ordinary option update first; the
  -- next native audio service reapplies its fade. Native streams retain start.
  if self.host.shared() then
    self:setLevel(self.host.master(), apply)
  else
    self:refresh(apply)
  end
end
function NativeMusic:fadeOutBgm(speed)
  speed = tonumber(speed) or 4
  if self.current and self.host.outputAvailable() then
    self.fadeOut = {
      t = 0,
      dur = 16 * speed / 60,
      start = self.host.master(),
      songId = self.current.id,
      owner = self.serial,
    }
  else
    self.host.stop()
    self.current = nil
  end
end
function NativeMusic:fadeInBgm(data, value, speed)
  self:playSong(data, value)
  self.fadeIn = { t = 0, dur = 16 * (tonumber(speed) or 4) / 60 }
  if self.host.shared() then
    self.host.sharedLevel(0)
  end
  self:setLevel(0)
end
function NativeMusic:fadeOutAndPlay(data, value, speed, fadeIn)
  local id = self:resolve(value)
  if self.fanfareActive then
    self.deferred = id
    return true
  end
  if not (self.current and self.host.nativeOutput()) then
    return self:playSong(data, id)
  end
  if not (self.fadeOut and self.fadeOut.mapMusic) then
    self:fadeOutBgm(speed)
  end
  if self.fadeOut then
    self.fadeOut.nextSong, self.fadeOut.fadeIn, self.fadeOut.mapMusic = id, fadeIn, true
  end
  return true
end
function NativeMusic:fadeDefaultBgm(data)
  local id = self.host.defaultSong() or self.mapSong
  if id ~= nil and self:currentMapMusic() ~= id then
    return self:fadeOutAndPlay(data, id, 8)
  end
  return true
end
function NativeMusic:update(data)
  if self.fanfareActive then
    self.fanfareFrames = self.fanfareFrames - 1
    if self.fanfareFrames <= 0 or self.host.suspended() then
      self.fanfareActive = false
      local deferred, restore = self.deferred, self.fanfareRestore
      self.deferred, self.fanfareRestore = nil, nil
      if deferred ~= nil and deferred ~= self.host.nativeGeneration() then
        self:playSong(data, deferred, true)
      elseif self.host.nativeRunning() then
        self.bgmPaused = false
        self.host.resumeNative()
      elseif restore ~= nil then
        self:playSong(data, restore, true)
      else
        self.bgmPaused = false
      end
      if self.fanfareWait then
        self.fanfareWait.done = true
        self.fanfareWait = nil
      end
    end
  end
  local f = self.fadeOut
  if f then
    f.t = f.t + 1 / 60
    local u = math.min(1, f.t / math.max(f.dur, 0.01))
    local same = f.owner == self.serial and self.current and self.current.id == f.songId
    if same then
      self:refresh()
    end
    if u >= 1 then
      if same then
        self.host.stop()
        self.current = nil
      end
      self.fadeOut = nil
      if same and f.nextSong then
        if f.fadeIn then
          self:fadeInBgm(data, f.nextSong, f.fadeIn)
        else
          self:playSong(data, f.nextSong)
        end
      end
    end
  end
  if self.fadeIn and self.host.outputAvailable() then
    local incoming = self.fadeIn
    incoming.t = incoming.t + 1 / 60
    local u = math.min(1, incoming.t / math.max(incoming.dur, 0.01))
    self:setLevel(self.host.shared() and self.host.sharedLevel(u) or self.host.master() * u)
    if incoming.t >= math.max(incoming.dur, 0.01) then
      self.fadeIn = nil
    end
  end
end
function NativeMusic:playFanfare(data, value)
  local info = require("src.core.Gen3Fanfare").info(data, value)
  if not info then
    return false
  end
  if not self.fanfareActive then
    self.fanfareRestore = self.host.nativeGeneration() or self.current and self.current.id
    self.deferred, self.bgmPaused = nil, true
    self.host.pauseNative()
  end
  self.fanfareActive, self.fanfareFrames = true, info.frames
  self.host.stopCry()
  self.host.playFanfare(data, info)
  return true
end
function NativeMusic:fanfareFinished()
  return self.host.suspended() or not self.fanfareActive
end
function NativeMusic:waitFanfare()
  if self:fanfareFinished() then
    return nil
  end
  local wait = { polls = 0, done = false }
  self.fanfareWait = wait
  return function()
    wait.polls = wait.polls + 1
    return wait.polls > 360 or wait.done or self:fanfareFinished()
  end
end
function NativeMusic:fanfareSnapshot()
  return {
    active = self.fanfareActive or false,
    frames = self.fanfareFrames or 0,
    restore = self.fanfareRestore,
    paused = self.bgmPaused or false,
  }
end
function NativeMusic:snapshot()
  local function copy(record)
    if not record then
      return nil
    end
    local out = {}
    for key, value in pairs(record) do
      if key ~= "owner" then
        out[key] = value
      end
    end
    return out
  end
  return {
    song = self.current and self.current.id,
    mapSong = self.mapSong,
    savedSong = self.savedSong,
    currentMapMusic = self:currentMapMusic(),
    fadeOut = copy(self.fadeOut),
    fadeIn = copy(self.fadeIn),
    deferred = self.deferred,
    level = self.level,
  }
end
return NativeMusic
