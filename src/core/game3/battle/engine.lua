-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Decoration of the actual native move invocation, before Encore, PP, RNG,
-- announcement and item frames. This is not an alternate combat executor.
local Battle=require('src.core.game3.battle')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local CoroutineScopes=require('src.compat.gen1.CoroutineScopes')
local Call=require('src.compat.gen1.SourceCall')
local Version=require('src.core.GameVersion')
local Ids=require('src.compat.gen1.BattleIds')
local scopes=CoroutineScopes.new()
local M={}
local unpack=table.unpack or unpack
local function pack(...)return {n=select('#',...),...}end
-- Newer native owners bind action records to a learned PP slot; older
-- owners debit the move instance itself. Observe the owner already in use.
local function ppOwner(move)
 local choices=package.loaded['src.battle.EnemyMoveChoice']
 local resolver=choices and choices.slot
 return resolver and resolver(move)or move,choices,resolver
end
local function live(lease)
 assert(lease and not lease.closed and not lease.frame.closed and not CoroutineScopes.retired(),
  'native move resolution retired')
 local game,screen=lease.game,lease.screen
 assert(Version.get()==lease.edition and Battle._screen(lease.state)==screen
  and screen.game==game and screen.data==lease.data and game.data==lease.data
  and game.save==lease.save and game.mods==lease.mods and game.stack==lease.stack
  and game.stack:top()==screen and screen.queue==lease.queue and not screen.result
  and (type(game.mods)=='table'and game.mods.content or nil)==lease.content
  and lease.ids:valid(),'native move resolution cohort retired')
 assert(lease.user.mon==lease.userMon and lease.target.mon==lease.targetMon
  and lease.user.position==lease.userPosition and lease.target.position==lease.targetPosition
  and screen:battlerAt(lease.userPosition)==lease.user
  and screen:battlerAt(lease.targetPosition)==lease.target
  and lease.state.battlers[lease.userPosition]==lease.publicUser
  and lease.state.battlers[lease.targetPosition]==lease.publicTarget,
  'native move resolution actors retired')
 assert(lease.move.id==lease.moveId and screen.data.moves[lease.moveId]==lease.definition,
  'native move resolution identity retired')
 local selected,choices,resolver=ppOwner(lease.move)
 assert(selected==lease.selected and choices==lease.choices and resolver==lease.slotResolver
  and (not lease.slot or (lease.user.curMoves or lease.user.mon.moves or{})[lease.slot]==lease.selected),
  'native move resolution PP owner retired')
 return lease
end
-- Read the same ownership decision used by the native summary, from a
-- resident of this exact admitted battle. Queries never flush staged PP.
function M.isTradedMon(state,mon)
 local screen=Battle._screen(state)
 if not screen then return nil,'native battle admission required'end
 local raw,known,game,owner=require('src.compat.gen1.BattleView').nativeMon(mon,true)
 if not(known and raw and game==screen.game and owner==screen)then return nil,'foreign native Pokemon record'end
 return not require('src.pokemon.Gen3Ownership').owns(raw,(game.save or{}).player)
end
function M.resolveMove(user,target,move,slot,adapter,state,out,...)
 local frame=scopes:find('move');local lease=frame and live(frame.value)
 if not lease then return nil,'move resolution belongs to its native invocation'end
 assert(user==lease.publicUser and target==lease.publicTarget and move==lease.moveId
  and slot==lease.slot and adapter==nil and state==lease.state and out==nil
  and select('#',...)==0,'native move resolution arguments changed')
 return Boundary.invoke('battle.resolveMove')
end
function M._native(screen,user,target,move,isCalled,suppressAnimation,spreadContinuation,body)
 local state=Battle.getState()
 if not Version.isGen3()or Battle._screen(state)~=screen then
  return body(screen,user,target,move,isCalled,suppressAnimation,spreadContinuation)
 end
 if not(user and target and user.position~=nil and target.position~=nil
  and screen:battlerAt(user.position)==user and screen:battlerAt(target.position)==target
  and state.battlers[user.position]and state.battlers[target.position])then
  return body(screen,user,target,move,isCalled,suppressAnimation,spreadContinuation)
 end
 local game=screen.game
 local lease={game=game,screen=screen,state=state,data=screen.data,save=game.save,mods=game.mods,
  stack=game.stack,content=type(game.mods)=='table'and game.mods.content or nil,queue=screen.queue,edition=Version.get(),ids=Ids.new(screen.data),
  user=user,target=target,userMon=user.mon,targetMon=target.mon,userPosition=user.position,targetPosition=target.position,move=move,moveId=move.id,definition=screen.data.moves[move.id]}
 lease.publicUser,lease.publicTarget=state.battlers[user.position],state.battlers[target.position]
 local selected,choices,resolver=ppOwner(move)
 lease.selected,lease.choices,lease.slotResolver=selected,choices,resolver
 for index,entry in ipairs(user.curMoves or user.mon.moves or{})do
  if entry==selected then lease.slot=index;break end
 end
 local frame=scopes:push('move',lease);lease.frame=frame
 local result=pack(pcall(function()
  return Boundary.dispatch('battle.resolveMove',function()
   live(lease)
   return body(screen,user,target,move,isCalled,suppressAnimation,spreadContinuation)
  end,function()
   live(lease)
   return Call.call(M,'resolveMove',lease.publicUser,lease.publicTarget,lease.moveId,lease.slot,nil,state,nil)
  end)
 end))
 local retired=frame.closed or CoroutineScopes.retired()
 lease.closed=true;scopes:close(frame)
 if not result[1]then error(result[2],0)end
 if retired then error('native move resolution retired while suspended',0)end
 return unpack(result,2,result.n)
end
return M
