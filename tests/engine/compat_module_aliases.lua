local T=require('tests.harness')
love=require('tests.love_stub')
local C=require('src.core.ModCompat')
C.install()
T.eq(require('src.world.gen2.WorldAPI'),require('src.world.WorldAPI'),'world API alias preserves object identity')
if loadfile('src/world/OptionalFollower.lua') then
 T.eq(require('src.world.gen2.Follower'),require('src.world.OptionalFollower'),'Gen2 follower alias preserves object identity')
else
 T.raises(function()require('src.world.gen2.Follower')end,'src.world.OptionalFollower','alias identifies an unavailable native follower provider')
end
local names=require('src.mods.Gen1Compat')
for name in pairs(names.UNAVAILABLE)do
 if names.hasProvider(name)then
  local ok,module=pcall(require,name)
  T.check(ok,'concrete host provider loads '..name)
  T.eq(type(module),'table','concrete host provider remains a module '..name)
  T.eq(names.unavailable(name),nil,'existing provider is not marked unavailable '..name)
  T.eq(require(name),module,'existing provider retains require identity '..name)
  T.check(names.hasProvider(name),'provider remains available '..name)
 else
  local ok,reason=pcall(require,name)
  T.check(not ok,'unsupported import fails '..name)
  T.check(tostring(reason):find(name,1,true)~=nil,'failure identifies module '..name)
  T.check(tostring(reason):find('mystery_dungeon_follower',1,true)~=nil,'failure identifies affected consumer '..name)
  T.check(not tostring(reason):find('no file ',1,true),'failure does not masquerade as a filesystem search '..name)
  local again,detail=pcall(require,name)
  T.check(not again and reason==detail,'repeat import retains the exact diagnostic '..name)
 end
end

local providers=package.loaders or package.searchers
local provided={marker='native-late-provider'}
local late=function(name)if name=='src.import.pmd.Sprite'then return function()return provided end end end
providers[#providers+1]=late
T.eq(require('src.import.pmd.Sprite'),provided,'late concrete provider outranks the missing-module descriptor')
T.check(names.hasProvider('src.import.pmd.Sprite'),'loaded provider is recognized')
T.eq(names.unavailable('src.import.pmd.Sprite'),nil,'loaded provider has no missing-module diagnostic')
table.remove(providers);package.loaded['src.import.pmd.Sprite']=nil
T.finish()
