-- Native Gen2 presentation entry points over the existing battle queue/VM.
-- Public side/after-animation names follow Gen1Recomp's Gen2 BattleState;
-- battle decisions, damage, PP, queue consumption and time stay native.
local Version=require('src.core.GameVersion')
local View=require('src.battle.Gen2AnimView')
local Data=require('src.battle.Gen2AnimData')
local M={}

function M.start(screen,id,isPlayer,opts)
  local player=screen.animPlayer
  if not (Version.isGen2() and player and Data.isGen2(player.anims)
      and player:scriptFor(id)) then return false end
  if player:start(id,isPlayer,opts)==false then return false end
  screen.animPlaying=true
  screen.animName,screen.animAttackerIsPlayer=id,isPlayer
  screen:resetPicFx()
  player.presentation=View.runner(player)
  screen.anim=player.presentation
  for _,event in ipairs(player:pollEffects())do screen:applyAnimEffect(event)end
  return true
end

function M.install(Screen)
  function Screen:turnFor(side) return side=='enemy' and 1 or 0 end
  function Screen:afterAnimFor(side,kind)
    if kind=='statdown'then
      return side=='player'and 'ANIM_ENEMY_STAT_DOWN'or 'ANIM_WOBBLE'
    end
    if kind=='damage'then
      return side=='player'and 'ANIM_ENEMY_DAMAGE'or 'ANIM_PLAYER_DAMAGE'
    end
  end
  function Screen:playHitSound(effectiveness)
    if not effectiveness or effectiveness==0 then return end
    local name=effectiveness>10 and 'Super_Effective'
      or effectiveness<10 and 'Not_Very_Effective'or 'Damage'
    require('src.core.Sound').play(self.data,name)
  end
  function Screen:animForMove(moveId,side,param,effectiveness,afterAnim)
    local player=self.animPlayer
    if not (Version.isGen2() and self:animationsOn() and player
        and Data.isGen2(player.anims) and player:scriptFor(moveId)) then return false end
    local started=M.start(self,moveId,side~='enemy',{param=param or 0})
    if started then
      local name=self:afterAnimFor(side,afterAnim)
      self.pendingAfterAnim=name and {name=name,side=side,
        effectiveness=afterAnim=='damage'and effectiveness or nil}or nil
      self.afterAnimPlayed=nil
    end
    return started
  end
  function Screen:animForId(id,side,param)
    return M.start(self,id,side~='enemy',{param=param or 0})
  end
  function Screen:startPendingAfterAnim()
    local pending=self.pendingAfterAnim
    if not pending then return false end
    self.pendingAfterAnim=nil
    if self:animForId(pending.name,pending.side)then
      self:playHitSound(pending.effectiveness)
      self.afterAnimPlayed=true
      return true
    end
    return false
  end
end
return M
