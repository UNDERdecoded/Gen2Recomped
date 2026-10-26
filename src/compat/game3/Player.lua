-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Field-only fallback for hosts without a concrete live player provider.
local function player()
  local game=package.loaded['src.core.Game']
  return game and game.overworld and game.overworld.player
end
return setmetatable({},{__index=function(_,key)
  local current=player();return current and current[key]
end,__newindex=function(_,key,value)
  local current=assert(player(),'native player is unavailable')
  current[key]=value
end})
