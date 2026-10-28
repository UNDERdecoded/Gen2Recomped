-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Call-local authority for source-facing GBA record transactions and RNG.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local CoroutineScopes=require('src.compat.gen1.CoroutineScopes')
local scopes=CoroutineScopes.new()
local M={}
function M.new(loader)
 local game=Native.game()
 local lease={open=true,game=game,loader=loader,content=loader.content,edition=Version.get(),
  data=game and game.data,save=game and game.save,mods=game and game.mods,stack=game and game.stack,
  functions={},functionViews={},functionIds={},battles={}}
 lease.frame=scopes:push('records',lease)
 return lease
end
function M.check(lease)
 assert(lease and lease.open,'callback transaction is closed')
 local frame=scopes:find('records')
 while frame and frame~=lease.frame do frame=frame.parent end
 assert(frame and not frame.closed and not CoroutineScopes.retired(),'native callback transaction retired')
 assert(Native.game()==lease.game and Version.get()==lease.edition and lease.loader.content==lease.content,
  'native callback cohort retired')
 local game=lease.game
 assert(not game or game.data==lease.data and game.save==lease.save and game.mods==lease.mods and game.stack==lease.stack,
  'native callback cohort retired')
 local battle=package.loaded['src.core.game3.battle']
 for raw,view in pairs(lease.battles)do
  assert(battle and battle._screen(view)==raw,'native callback battle retired')
 end
 return lease
end
function M.battle(lease,raw)
 if not(raw and raw.isBattleState)then return raw end
 M.check(lease)
 local battle=package.loaded['src.core.game3.battle']
 if not battle or battle._screen()~=raw then return nil end
 local view=battle.getState();lease.battles[raw]=view;return view
end
function M.rng(lease,fn)
 local index=lease.functionIds[fn]
 if index then return lease.functionViews[index]end
 index=#lease.functions+1;lease.functionIds[fn]=index;lease.functions[index]=fn
 -- An external RNG handle must not root its abandoned transaction/native
 -- coroutine. Only the live callback owns this lease strongly.
 local refs=setmetatable({lease},{__mode='v'})
 local view=function(...)
  local active=refs[1];assert(active,'native callback RNG retired')
  M.check(active);return active.functions[index](...)
 end
 lease.functionViews[index]=view;return view
end
function M.writeRng(lease,raw,value)
 M.check(lease)
 lease.restores=lease.restores or{}
 lease.restores[#lease.restores+1]={raw,raw.rng,value}
 raw.rng=value
end
function M.close(lease)
 if not lease or not lease.open then return end
 lease.open=false
 -- A source RNG override is lent to this native invocation. Do not leave
 -- a closed public closure installed on a caller's reusable native context.
 for i=#(lease.restores or{}),1,-1 do
  local change=lease.restores[i]
  if change[1].rng==change[3]then change[1].rng=change[2]end
 end
 scopes:close(lease.frame)
 lease.game,lease.loader,lease.content,lease.data,lease.save,lease.mods,lease.stack=nil,nil,nil,nil,nil,nil,nil
 lease.functions,lease.functionViews,lease.functionIds,lease.battles,lease.restores=nil,nil,nil,nil,nil
end
return M
