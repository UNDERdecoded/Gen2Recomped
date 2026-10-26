-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Main-state queue transport. Ordinary sequencer-field access retires this
-- transport and materializes the last queued snapshot for the legacy player.
local Performance = require("src.core.Performance")
local Sequence = require("src.audio.NitroSequence")
local Logger = require("src.core.Logger")
local M = {}
local entries = setmetatable({}, { __mode = "k" })
local archiveIds = setmetatable({}, { __mode = "k" })
local serial, archiveSerial = 0, 0
local proxies = setmetatable({}, { __mode = "k" })
local protected = {
  arc = true,
  seq = true,
  bytes = true,
  start = true,
  tracks = true,
  voices = true,
  samples = true,
  tempo = true,
  tickPhase = true,
  master = true,
  variables = true,
  ended = true,
}
local logged = {}
local ffiOK = pcall(require, "ffi")
local function log(reason)
  if not logged[reason] then
    logged[reason] = true
    Logger.info("DS audio: synchronous fallback (%s)", reason)
  end
end
local function chip()
  return require("src.core.ChipAudio")
end
local function send(e, action, values)
  values = values or {}
  values.action, values.id, values.gen = action, e.id, e.gen
  return chip()._nitroCommand(values)
end
function M.attach(player, def, hydrate, reset)
  if Performance.audioWorkerOptimization == false then
    return
  end
  if not ffiOK then
    log("FFI unavailable")
    return
  end
  if not (love.thread and love.thread.newThread) then
    log("no love.thread")
    return
  end
  local safe, why = Sequence.workerSafe(player.bytes, player.start)
  if not safe then
    log(why)
    return
  end
  serial = serial + 1
  local meta = getmetatable(player)
  local proxy = proxies[meta]
  if not proxy then
    proxy = {
      __index = function(self, key)
        return meta[key] or M.read(self, key)
      end,
      __newindex = M.write,
    }
    proxies[meta] = proxy
  end
  local state = {}
  for key in pairs(protected) do
    state[key] = rawget(player, key)
    rawset(player, key, nil)
  end
  entries[player] =
    { id = serial, gen = 0, state = state, def = def, hydrate = hydrate, reset = reset, samples = {}, meta = meta }
  setmetatable(player, proxy)
  return true
end
function M.detach(player, reason)
  local e = entries[player]
  if not e then
    return
  end
  if e.active then
    send(e, "stop")
  end
  if e.channel then
    e.channel:clear()
  end
  entries[player] = nil
  setmetatable(player, e.meta)
  e.hydrate(player, e.state, e.samples)
  if reason then
    log(reason)
  end
end
function M.read(player, key)
  if protected[key] and entries[player] then
    M.detach(player, "direct sequencer state access: " .. key)
    return rawget(player, key)
  end
end
function M.write(player, key, value)
  local e = entries[player]
  if e and (protected[key] or type(e.meta[key]) == "function") then
    M.detach(player, "direct sequencer state/method write: " .. key)
  end
  rawset(player, key, value)
end
function M.play(player)
  local e = entries[player]
  if not e then
    return false
  end
  if Performance.audioWorkerOptimization == false then
    M.detach(player, "optimization disabled")
    return false
  end
  if player.paused and e.active then
    player.paused = false
    player.queue:play()
    return true
  end
  player.queue:stop()
  e.gen = e.gen + 1
  e.done = false
  e.reset(e.state)
  e.pendingVariables = {}
  e.rev = 0
  local arc = e.state.arc
  local thread = chip()._nitroReady()
  if not thread then
    M.detach(player, "worker unavailable")
    return false
  end
  local a = archiveIds[arc]
  if not a or a.bytes ~= arc.data or a.thread ~= thread then
    archiveSerial = archiveSerial + 1
    a = { id = archiveSerial, bytes = arc.data, thread = thread }
    if not chip()._nitroCommand({ action = "archive", archive = a.id, bytes = a.bytes }) then
      M.detach(player, "worker unavailable")
      return false
    end
    archiveIds[arc] = a
  end
  e.channel = love.thread.getChannel("chipaudio_nds_" .. e.id)
  e.channel:clear()
  if
    not send(
      e,
      "start",
      {
        archive = a.id,
        def = e.def,
        pitch = player.pitch,
        looping = player.looping,
        tempo = e.state.tempo,
        master = e.state.master,
        audioWorkerOptimization = true,
      }
    )
  then
    M.detach(player, "worker unavailable")
    return false
  end
  e.pitch, e.looping = player.pitch, player.looping
  e.touch = 0
  e.active = true
  player.running, player.paused = true, false
  return true
end
function M.stop(player)
  local e = entries[player]
  if not e then
    return false
  end
  if e.active then
    send(e, "stop")
  end
  e.active = false
  e.done = false
  e.state.voices = {}
  if e.channel then
    e.channel:clear()
  end
  player.running = false
  player.queue:stop()
  return true
end
function M.isPlaying(player)
  local e = entries[player]
  if not e then
    return nil
  end
  return player.running and (not e.done or player.queue:isPlaying()) or false
end
function M.variable(player, index)
  local e = entries[player]
  if not e or index >= 16 then
    return nil, false
  end
  local value = e.state.variables and e.state.variables[index]
  return value == nil and -1 or value, true
end
function M.setVariable(player, index, value)
  local e = entries[player]
  if not e then
    return false
  end
  if index >= 16 then
    M.detach(player, "shared variable write")
    return false
  end
  value = math.floor(value) % 65536
  if value >= 32768 then
    value = value - 65536
  end
  e.state.variables = e.state.variables or {}
  e.state.variables[index] = value
  if e.active then
    e.rev = e.rev + 1
    e.pendingVariables[index] = { value = value, rev = e.rev }
    send(e, "variable", { index = index, value = value, rev = e.rev })
  end
  return true
end
function M.update(player)
  local e = entries[player]
  if not e then
    return false
  end
  if Performance.audioWorkerOptimization == false then
    M.detach(player, "optimization disabled")
    return false
  end
  if not player.running or player.paused or not e.active then
    return true
  end
  local now = love.timer.getTime()
  if e.pitch ~= player.pitch or e.looping ~= player.looping or now - e.touch >= 1 then
    if not send(e, "control", { pitch = player.pitch, looping = player.looping }) then
      M.detach(player, "worker unavailable")
      return false
    end
    e.pitch, e.looping, e.touch = player.pitch, player.looping, now
  end
  while player.queue:getFreeBufferCount() > 0 do
    local row = e.channel:pop()
    if not row then
      break
    end
    if row.gen == e.gen then
      if row.error then
        M.detach(player, "worker: " .. row.error)
        return false
      end
      if row.sd then
        player.queue:queue(row.sd)
        for key, value in pairs(row.state) do
          e.state[key] = value
        end
        -- nil variables/ended values are represented explicitly by the worker.
        e.state.variables = row.state.variables
        for index, write in pairs(e.pendingVariables) do
          if (row.rev or 0) < write.rev then
            e.state.variables[index] = write.value
          else
            e.pendingVariables[index] = nil
          end
        end
        for key, value in pairs(row.samples) do
          e.samples[key] = value
        end
        e.done = row.done
      end
    end
  end
  if e.done and not player.queue:isPlaying() and player.queue:getFreeBufferCount() == 16 then
    player.running = false
  elseif not player.queue:isPlaying() and player.queue:getFreeBufferCount() < 16 then
    player.queue:play()
  end
  return true
end
return M
