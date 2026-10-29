-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- GSC sleep uses the live native battler/party state and the battle's RNG.
-- No parallel turn clock or presentation queue is maintained here.
local Strings=require('src.core.Strings')
local M={}
local function moveId(move)
  if type(move)=='table'then return move.id end
  return move
end

-- CantMove also runs on waking. It cancels the locked sequences, including
-- the selected Fly/Dig's hidden flags, before the same turn continues.
function M.cancel(user,move)
  local id=moveId(move)or user.charging and user.charging.id
  user.bideTurns,user.bideDamage=nil,nil
  user.thrashTurns,user.thrashMove,user.thrashAnnounced=nil,nil,nil
  user.charging,user.chargeReady=nil,nil
  user.rampRun,user.rampMove=nil,nil
  if id=='FLY'or id=='DIG'then
    user.invulnerable,user.hiddenAs=nil,nil
  end
end

function M.beforeMove(user,_,_,move)
  local turns=(tonumber(user.sleepTurns)or tonumber(user.mon.sleepTurns)or 1)-1
  if turns<=0 then
    user.mon.status,user.sleepTurns,user.mon.sleepTurns=nil,nil,nil
    user.nightmare,user.expNightmare=nil,nil
    M.cancel(user,move)
    return true,{Strings('%s\nwoke up!',user.name)}
  end
  user.sleepTurns,user.mon.sleepTurns=turns,turns
  local id=moveId(move)
  local allowed=id=='SNORE'or id=='SLEEP_TALK'
  if not allowed then M.cancel(user,move)end
  return allowed,{Strings('%s\nis fast asleep!',user.name)},nil,nil,'sleep'
end

function M.inflict(battle,user,low,high)
  local rules=battle.ruleset or {}
  local turns
  if rules.sleepTurnsMin~=nil or rules.sleepTurnsMax~=nil then
    turns=battle.rng(low,high)
  else
    -- SleepTarget masks a byte, rejects 0/7, then increments. The Tower
    -- uses the two-bit mask; custom explicit rules retain their own range.
    local mask=battle.inBattleTowerBattle and 4 or 8
    local value
    repeat value=battle.rng(0,255)%mask until value~=0 and value~=7
    turns=value+1
  end
  user.sleepTurns,user.mon.sleepTurns=turns,turns
end

function M.rest(user)
  user.sleepTurns,user.mon.sleepTurns=3,3
end
return M
