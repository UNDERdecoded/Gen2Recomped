-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- GSC ProtectChance: a nonzero byte minus one against FF >> prior uses.
-- Keep the existing native action, battler and RNG owners.
local Protection={}
local function side(user)return user.isPlayer and 'player' or 'enemy'end

function Protection.actionStarted(battle,user)
 local turn=battle.turnCount or 0
 if battle._gen2ProtectionTurn~=turn then
  battle._gen2ProtectionTurn=turn;battle._gen2ProtectionFirst=nil
 end
 if not battle._gen2ProtectionFirst then battle._gen2ProtectionFirst=side(user)end
end

function Protection.apply(battle,user,field)
 local turn=battle.turnCount or 0
 local first=battle._gen2ProtectionTurn==turn and battle._gen2ProtectionFirst
 local count=math.max(0,math.floor(tonumber(user.protectRun)or 0))
 local threshold=count<8 and math.floor(255/2^count)or 0
 -- These branches precede the draw. A called protection effect retains the
 -- original round's first side, including after a native switch replaces it.
 if (first and first~=side(user))or(user.substituteHP or 0)>0
   or threshold==0 or battle.rng(1,255)-1>=threshold then
  user.protectRun=0
  return false
 end
 user.protectRun=count+1;user[field]=true
 return true
end
return Protection
