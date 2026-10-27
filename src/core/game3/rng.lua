-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Shared host RNG: checkpoint/continue sees the same stream as native play.
local R={}
local function random(...)return(love and love.math and love.math.random or math.random)(...)end
function R.Random()return random(0,65535)end
function R.Random32()local lo=R.Random();return lo+R.Random()*65536 end
function R.compat(...)return random(...)end
function R.mod(n)n=math.floor(tonumber(n)or 0);return n>0 and R.Random()%n or 0 end
function R.SeedRng(seed)
  assert(type(seed)=='number'and seed==seed and math.abs(seed)<math.huge,'invalid native RNG seed')
  return(love and love.math and love.math.setRandomSeed or math.randomseed)(math.floor(seed)%65536)
end
function R.mulU32(a,b)
  local al,bl=a%65536,b%65536
  return(al*bl+((math.floor(a/65536)*bl+math.floor(b/65536)*al)%65536)*65536)%4294967296
end
return R
