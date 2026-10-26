-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Native=require('src.world.OptionalFollower')
local F={setShouldSpawn=Native.setShouldSpawn}
function F.current(world)
  local game=package.loaded['src.core.Game']
  world=world or game and game.overworld
  return world and Native.current(world)or nil
end
return F
