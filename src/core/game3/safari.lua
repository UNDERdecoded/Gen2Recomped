-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Native=require('src.compat.gen1.NativeSession')
local Views=require('src.compat.gen1.SessionView')
local S={}
function S.isActive(session)
  local g=Native.game();if not(g and g.save)then return false end
  if session~=nil then local r=Views.record(session);if not(r and r:valid()and r.owner==g)then return false end end
  return g.save.safari~=nil and g.save.safari~=false
end
return S
