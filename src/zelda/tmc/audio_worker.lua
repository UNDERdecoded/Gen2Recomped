-- Minish Cap audio thread: runs src/core/M4ASynth (the Emerald port's M4A
-- engine) on The Minish Cap's own sound bank and streams buffers back.
--
-- Channels (names carry a per-instance suffix):
--   tmc_audio_cmd   in:  {cmd="load", bytes=<ByteData|string>, base=n, repo=?}
--                        {cmd="play", gen=n, def={tracks, voicegroup}}
--                        {cmd="stop"} {cmd="sfx", id=n, def=...} {cmd="quit"}
--   tmc_audio_out   out: {gen=n, sd=SoundData}
--   tmc_audio_sfx   out: {id=n, sd=SoundData|false}
require("love.thread")
require("love.sound")
require("love.timer")
require("love.data")
pcall(require, "love.filesystem")

local suffix = ...
local cmdCh = love.thread.getChannel("tmc_audio_cmd" .. (suffix or ""))
local outCh = love.thread.getChannel("tmc_audio_out" .. (suffix or ""))
local sfxCh = love.thread.getChannel("tmc_audio_sfx" .. (suffix or ""))

local IMAGE = nil
-- M4ASynth reads its image through WorkerFs; hand it ours instead
package.preload["src.core.WorkerFs"] = function()
  return { prefix = function() return nil end, read = function() return IMAGE end }
end

local M4A
local data = nil
local engine, gen = nil, nil
local BUF = 2048
local LOOKAHEAD = 6

local function handle(c)
  if c.cmd == "load" then
    if c.repo then package.path = c.repo .. "/?.lua;" .. c.repo .. "/?/init.lua;" .. package.path end
    local b = c.bytes
    if type(b) ~= "string" and b and b.getString then b = b:getString() end
    IMAGE = b
    M4A = require("src.core.M4ASynth")
    if M4A.invalidate then M4A.invalidate() end
    data = { audio = { gen3 = { file = "tmc_audio", base = c.base } } }
  elseif c.cmd == "play" then
    gen = c.gen
    outCh:clear()
    engine = nil
    if M4A and data and c.def then
      local ok, e = pcall(M4A.newEngine, data, c.def, { allowLoops = true, volume = c.volume or 1 })
      if ok then engine = e end
    end
  elseif c.cmd == "stop" then
    engine, gen = nil, nil
    outCh:clear()
  elseif c.cmd == "sfx" then
    local sd = false
    if M4A and data and c.def then
      local ok, r = pcall(M4A.renderEffect, data, c.def, { seconds = 4 })
      if ok and r then sd = r end
    end
    sfxCh:push({ id = c.id, sd = sd })
  end
end

while true do
  local c = cmdCh:pop()
  while c do
    if c.cmd == "quit" then return end
    local ok, err = pcall(handle, c)
    if not ok then sfxCh:push({ error = tostring(err) }) end
    c = cmdCh:pop()
  end
  if engine and outCh:getCount() < LOOKAHEAD then
    local ok, sd = pcall(M4A.soundData, engine, BUF, 2)
    if ok and sd then outCh:push({ gen = gen, sd = sd })
    else engine = nil end
  else
    love.timer.sleep(0.004)
  end
end
