-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local Source=require('src.compat.gen1.SourcePokemon')
local Actions=require('src.world.WorldActions')
local F={}
local function moveKey(game,value)
 local key=Ids.new(game.data):native('moves',value)
 return key or type(value)=='string'and value:upper():gsub(' ','_')or nil
end
function F.hasBadge(ctx,badge)
 local g=Native.game();if not(g and g.save)then return false end
 local key=moveKey(g,badge);local gate=(g.data.constants.gen3FieldMoves or{})[key]
 if not(gate and gate.badgeFlag)then return true end
 return g.save.flags and g.save.flags[('FLAG_G3_%04X'):format(gate.badgeFlag)]==true or false
end
function F.partyMoveUser(party,move,ctx)
 local g,w=Native.resolve();if not g then return nil,6 end
 local key=moveKey(g,move);if not key then return nil,6 end
 local mon=w.partyKnows and w:partyKnows(key)
 if not mon then return nil,6 end
 for i,value in ipairs(party or{})do
  local raw,known=Source.resident(value)
  if known and raw==mon then return value,i-1 end
 end
 return nil,6
end
function F.fromMenu(move,ctx)
 local g,w=Native.resolve();if not g then return{ok=false,text='No active field.'}end
 local key=moveKey(g,move);if not key then return{ok=false,text='Unknown field move.'}end
 local ok,why=Actions.useFieldAction(g,w,key:lower())
 return{ok=ok==true,text=why}
end
return F
