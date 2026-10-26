-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Worker-side bounded DS players on the existing ChipAudio command loop.
local Sdat = require("src.import.Gen4Sdat")
local Audio = require("src.audio.NitroAudio")
local Performance = require("src.core.Performance")
local M = {}
local archives, archiveOrder, jobs, order = {}, {}, {}, {}
local cursor = 0
local function channel(id)
  return love.thread.getChannel("chipaudio_nds_" .. id)
end
function M.command(cmd)
  if cmd.action == "archive" then
    if not archives[cmd.archive] then
      archiveOrder[#archiveOrder + 1] = cmd.archive
    end
    archives[cmd.archive] = assert(Sdat.open(cmd.bytes))
    while #archiveOrder > 4 do
      archives[table.remove(archiveOrder, 1)] = nil
    end
    return
  end
  local job = jobs[cmd.id]
  if cmd.action == "start" then
    if not job and #order >= 16 then
      channel(cmd.id):push({ gen = cmd.gen, error = "DS worker player limit reached" })
      return
    end
    local ok, engine = pcall(Audio._workerNew, assert(archives[cmd.archive], "DS archive retired"), cmd.def)
    if not ok then
      channel(cmd.id):push({ gen = cmd.gen, error = tostring(engine) })
      return
    end
    if not job then
      order[#order + 1] = cmd.id
    end
    engine.pitch, engine.looping = cmd.pitch, cmd.looping
    engine.tempo, engine.master = cmd.tempo or engine.tempo, cmd.master or engine.master
    jobs[cmd.id] =
      { engine = engine, gen = cmd.gen, channel = channel(cmd.id), sent = {}, last = love.timer.getTime(), rev = 0 }
  elseif job and job.gen == cmd.gen then
    job.last = love.timer.getTime()
    if cmd.action == "stop" then
      jobs[cmd.id] = nil
      for i=#order,1,-1 do if order[i]==cmd.id then table.remove(order,i)end end
      job.channel:clear()
    elseif cmd.action == "control" then
      job.engine.pitch, job.engine.looping = cmd.pitch, cmd.looping
    elseif cmd.action == "variable" then
      job.engine:setVariable(cmd.index, cmd.value)
      job.rev = cmd.rev or job.rev
    end
  elseif cmd.action == "control" then
    channel(cmd.id):push({ gen = cmd.gen, error = "DS worker lease expired" })
  end
end
function M.step()
  local now = love.timer.getTime()
  for i = #order, 1, -1 do
    local id = order[i]
    local job = jobs[id]
    if not job or now - job.last > 5 then
      jobs[id] = nil
      table.remove(order, i)
    end
  end
  for _ = 1, #order do
    cursor = cursor % #order + 1
    local job = jobs[order[cursor]]
    if not job.done and job.channel:getCount() < 2 then
      local priorOptimization=Performance.audioWorkerOptimization
      Performance.audioWorkerOptimization = true
      local ok, sd, state, samples, done = pcall(Audio._workerRender, job.engine, 8192, job.sent)
      Performance.audioWorkerOptimization=priorOptimization
      if ok then
        job.channel:push({ gen = job.gen, sd = sd, state = state, samples = samples, done = done, rev = job.rev })
        job.done = done
      else
        job.channel:push({ gen = job.gen, error = tostring(sd) })
        job.done = true
      end
      return true
    end
  end
  return false
end
return M
