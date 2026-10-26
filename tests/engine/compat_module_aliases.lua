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
local sourcePlayer=require('src.core.game3.player')
local fallbackPlayer=require('src.compat.game3.Player')
if loadfile('src/core/game3/player.lua')then
 T.neq(sourcePlayer,fallbackPlayer,'concrete live player provider takes precedence over the field fallback')
else
 T.eq(sourcePlayer,fallbackPlayer,'host without a concrete player provider receives the live field fallback')
end
local names=require('src.mods.Gen1Compat')
for _,pair in ipairs({{'src.world.game3.Follower','src.compat.game3.Follower'},
 {'src.core.game3.pokemon','src.compat.game3.Pokemon'},
 {'src.core.gen2.Unown','src.compat.gen2.Unown'}})do
 local source,adapter=require(pair[1]),require(pair[2])
 if loadfile(pair[1]:gsub('%.','/')..'.lua')then
  T.neq(source,adapter,'concrete provider outranks the fallback '..pair[1])
 else
  T.eq(source,adapter,'native adapter preserves require identity '..pair[1])
 end
end

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
local lateName='src.compat.fixture.LateProvider'
names.UNAVAILABLE[lateName]={'contract_fixture'}
local late=function(name)if name==lateName then return function()return provided end end end
providers[#providers+1]=late
T.eq(require(lateName),provided,'late concrete provider outranks the missing-module descriptor')
T.check(names.hasProvider(lateName),'loaded provider is recognized')
T.eq(names.unavailable(lateName),nil,'loaded provider has no missing-module diagnostic')
table.remove(providers);package.loaded[lateName]=nil;names.UNAVAILABLE[lateName]=nil
T.finish()
