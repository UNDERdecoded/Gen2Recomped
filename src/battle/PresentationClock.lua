-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Presentation holds borrow a native update; they never drain its command
-- queue. Results (including failures and nils) are shared within that update.
local M={}
local phases=setmetatable({},{__mode='k'})
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
function M.active(screen)return phases[screen]~=nil end
function M.delta(screen)return phases[screen]and phases[screen].delta end
function M.once(screen,key,body,...)
  local phase=phases[screen]
  if not phase then return body(screen,...)end
  local entry=phase.steps[key]
  if not entry then
    entry={};phase.steps[key]=entry
    entry.result=pack(pcall(body,screen,...))
  end
  local r=entry.result
  if not r then return nil,'presentation step is already executing'end
  if not r[1]then error(r[2],0)end
  return unpack(r,2,r.n)
end
function M.run(screen,dt,body,...)
  if phases[screen]then return body(...)end
  local phase={steps={},delta=dt};phases[screen]=phase
  local result=pack(pcall(body,...));phases[screen]=nil
  -- A wrapper cannot swallow a failed display step and retry that step.
  for _,entry in pairs(phase.steps)do
    if entry.result and not entry.result[1]then error(entry.result[2],0)end
  end
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
end
return M
