-- Minish Cap music and sound effects: the cartridge's M4A songs (gSongTable)
-- played by src/core/M4ASynth on a worker thread (audio_worker.lua).
-- Sound effects are songs too (SoundReq takes a song number); they are
-- rendered once in the worker and cached as static Sources.
--
-- Silent (never an error) when LOVE's audio module is off, the import has
-- no sound bank, or threads are unavailable.

local Audio = {}
Audio.__index = Audio

local ROM_BASE = 0x08000000

local counter = 0

local function workerCode()
  -- the worker file, read as code so it runs from any LOVE source folder
  local info = debug.getinfo(1, "S")
  local here = info and info.source and info.source:match("^@(.*)[/\\][^/\\]*$")
  local code
  if love.filesystem and love.filesystem.getInfo("src/zelda/tmc/audio_worker.lua") then
    code = love.filesystem.read("src/zelda/tmc/audio_worker.lua")
  end
  if not code and here then
    local f = io.open(here .. "/audio_worker.lua", "rb")
    if f then code = f:read("*a"); f:close() end
  end
  return code, here and here:gsub("[/\\]src[/\\]zelda[/\\]tmc$", "")
end

function Audio.new(store, manifest, opts)
  opts = opts or {}
  local self = setmetatable({
    manifest = manifest, musicVol = opts.musicVol or 1, sfxVol = opts.sfxVol or 1,
    gen = 0, sfx = {}, pending = {}, current = nil, enabled = false,
  }, Audio)
  if not (love.audio and love.thread and love.sound and manifest and manifest.audio) then return self end
  local bytes = store:read("audio.bin")
  if not bytes or #bytes == 0 then return self end
  local code, repo = workerCode()
  if not code then return self end
  counter = counter + 1
  self.suffix = "_" .. counter .. "_" .. tostring(os.time())
  local ok, thread = pcall(love.thread.newThread, code)
  if not ok then return self end
  self.thread = thread
  thread:start(self.suffix)
  self.cmd = love.thread.getChannel("tmc_audio_cmd" .. self.suffix)
  self.out = love.thread.getChannel("tmc_audio_out" .. self.suffix)
  self.sfxCh = love.thread.getChannel("tmc_audio_sfx" .. self.suffix)
  local bd = love.data and love.data.newByteData(bytes) or bytes
  self.cmd:push({ cmd = "load", bytes = bd, base = manifest.audio.base - ROM_BASE,
                  repo = (not love.filesystem.getInfo("src/core/M4ASynth.lua")) and repo or nil })
  local okq, src = pcall(love.audio.newQueueableSource, 44100, 16, 2, 8)
  if okq then self.source = src end
  self.enabled = self.source ~= nil
  return self
end

-- M4ASynth addresses its image by CARTRIDGE FILE OFFSET (pointers inside
-- the bytecode are bus addresses it rebases by $08000000), so the song's
-- track and voicegroup addresses go over as file offsets too
Audio.ROM_BASE = ROM_BASE

function Audio:songDef(id)
  local s = self.manifest.audio and self.manifest.audio.songs[id]
  if s and s.tracks and #s.tracks > 0 and s.voicegroup then
    local tracks = {}
    for i, t in ipairs(s.tracks) do tracks[i] = t - ROM_BASE end
    return { tracks = tracks, voicegroup = s.voicegroup - ROM_BASE }
  end
  return nil
end

function Audio:playBgm(id)
  if not self.enabled then self.current = id return end
  if id == self.current then return end
  self.current = id
  self.gen = self.gen + 1
  self.source:stop()
  local def = id and self:songDef(id)
  if def then
    self.cmd:push({ cmd = "play", gen = self.gen, def = def })
  else
    self.cmd:push({ cmd = "stop" })
  end
end

function Audio:stopBgm() self:playBgm(nil) end

function Audio:playSfx(id)
  if not self.enabled or not id or id == 0 then return end
  local s = self.sfx[id]
  if s then
    if s ~= false then
      local c = s:clone()
      c:setVolume(self.sfxVol)
      c:play()
    end
    return
  end
  if self.pending[id] then return end
  local def = self:songDef(id)
  if not def then self.sfx[id] = false return end
  self.pending[id] = true
  self.cmd:push({ cmd = "sfx", id = id, def = def })
end

function Audio:setVolumes(music, sfx)
  self.musicVol, self.sfxVol = music or self.musicVol, sfx or self.sfxVol
  if self.source then self.source:setVolume(self.musicVol) end
end

function Audio:update()
  if not self.enabled then return end
  local r = self.sfxCh:pop()
  while r do
    if r.id then
      self.pending[r.id] = nil
      if r.sd then
        local ok, src = pcall(love.audio.newSource, r.sd, "static")
        self.sfx[r.id] = ok and src or false
        if ok then src:setVolume(self.sfxVol); src:play() end
      else
        self.sfx[r.id] = false
      end
    end
    r = self.sfxCh:pop()
  end
  while self.source:getFreeBufferCount() > 0 do
    local m = self.out:pop()
    if not m then break end
    if m.gen == self.gen then self.source:queue(m.sd) end
  end
  if self.current and not self.source:isPlaying() and self.source:getFreeBufferCount() < 8 then
    self.source:setVolume(self.musicVol)
    self.source:play()
  end
end

function Audio:quit()
  if self.cmd then self.cmd:push({ cmd = "quit" }) end
  if self.source then self.source:stop() end
  self.enabled = false
end

return Audio
