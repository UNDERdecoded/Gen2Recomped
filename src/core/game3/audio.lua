-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local Sound=require('src.core.Sound')
local A={}
function A.playSe(id,opts)
  local g=Native.game();if not g then return false end
  local value=require('src.core.game3.se_ids').resolve(id)
  local source=Sound.playNamedEffect(g.data,value or id)
  if not source then source=Sound.playId(g.data,value)end
  return source~=nil
end
function A.playCry(species,mode,pan)
  local g=Native.game();if not g then return false end
  local key=Ids.new(g.data):native('pokemon',species);if not key then return false end
  return Sound.playCry(g.data,key,{noDuck=type(mode)=='table'and mode.noDuck or mode==1,
    volume=type(mode)=='table'and mode.volume or nil})~=nil
end
function A.isCryFinished()return not Sound.anyPlaying('cry')end
return A
