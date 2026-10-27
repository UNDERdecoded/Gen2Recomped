-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Attribute a native phase to the mod that installed its source wrapper.
local M={}
function M.owner(module,name)
 local facade=require('src.core.Game3');local host=package.loaded['src.mods.Runtime']
 local owner=host and host.currentMod or facade._callbackOwner()
 local seams=package.loaded['src.mods.ModSeams']
 for i=#(seams and seams._journal or{}),1,-1 do
  local change=seams._journal[i]
  if change.tbl==module and change.key==name and change.after==module[name]then owner=change.owner;break end
 end
 return owner
end
function M.call(module,name,...)
 return require('src.core.Game3')._withCallbackOwner(M.owner(module,name),module[name],...)
end
return M
