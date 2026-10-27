-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Keep an Apple-silicon VM's hot code in one bounded allocation. Growing
-- LuaJIT's small default area can fail placement and discard every trace.
-- Configure before loading game/mod code; never flush a running session.
local M = {}
local applied = false
local AREA_KIB, MAX_TRACES = 16384, 8192

function M.configure(runtime, optimizer)
  runtime = runtime or rawget(_G, 'jit')
  if type(runtime) ~= 'table' or runtime.os ~= 'OSX' or runtime.arch ~= 'arm64' then
    return false, 'platform uses its normal JIT policy'
  end
  if type(runtime.status) ~= 'function' or type(runtime.flush) ~= 'function' then
    return false, 'JIT control unavailable'
  end
  local ok, enabled = pcall(runtime.status)
  if not ok or not enabled then return false, 'JIT disabled' end
  if applied then return true end
  local requested = os.getenv and os.getenv('POKEPORT_JIT_OPT')
  if requested and requested ~= '' and requested ~= '1' then
    return false, 'explicit JIT policy retained'
  end
  if optimizer == nil then
    ok, optimizer = pcall(require, 'jit.opt')
    if not ok then return false, tostring(optimizer) end
  end
  if type(optimizer) ~= 'table' or type(optimizer.start) ~= 'function' then
    return false, 'JIT options unavailable'
  end
  local reason
  ok, reason = pcall(optimizer.start, 'maxtrace=' .. MAX_TRACES,
    'sizemcode=' .. AREA_KIB, 'maxmcode=' .. AREA_KIB)
  if not ok then return false, tostring(reason) end
  -- The allocation size takes effect on the next area. Retire a small area
  -- made by the LÖVE bootstrap once, before loading a game or its providers.
  ok, reason = pcall(runtime.flush)
  if not ok then return false, tostring(reason) end
  applied = true
  M.status = { applied=true, areaKiB=AREA_KIB, maxCodeKiB=AREA_KIB, maxTraces=MAX_TRACES }
  return true
end

return M
