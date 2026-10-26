-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Native=require('src.world.OptionalFollower')
local F={setShouldSpawn=Native.setShouldSpawn}
function F.current(world)
  local game=package.loaded['src.core.Game']
  world=world or game and game.overworld
  local npc=world and Native.current(world)or nil
  if npc and require('src.core.GameVersion').isGen3()then return require('src.core.game3.objects').find(npc.def.index)end
  return npc
end
function F.actor()
 local npc=F.current();if not(npc and npc.visible~=false and not npc.hidden and npc.sprite)then return nil end
 return{kind='follower',i=npc.localId,x=npc.px,y=npc.py,sortY=npc.py,elevation=npc.currentElevation,
  facing=npc.facing,walkPhase=npc.moving and 1 or 0,renderer=npc.sprite}
end
function F.reset()
 local game,world=require('src.compat.gen1.NativeSession').resolve()
 if not game then return false end
 return Native.reset(world)
end
function F.at(_,x,y)
 local npc=F.current();if npc and not npc.moving and npc.cellX==x and npc.cellY==y then return npc end
end
function F.update()return require('src.compat.gen1.ScriptBoundary').invoke('follower.update')end
function F._dispatch(game,world,body)
 return require('src.compat.gen1.ScriptBoundary').dispatch('follower.update',body,function(...)
  return require('src.compat.gen1.SourceCall').call(F,'update',...)
 end,require('src.core.Game3').forNative(game))
end
return F
