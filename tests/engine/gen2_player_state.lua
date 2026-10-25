package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local oldVersion=Version.get()
local State=require('src.world.Gen2PlayerState')
local World=require('src.world.OverworldController')
local Flags=require('src.script.Flags');local G2Flags=require('src.script.Gen2Flags')
local oldPlayer,oldMap=rawget(World,'player'),rawget(World,'map')
local gameSlot,oldGame
for i=1,100 do
 local name,value=debug.getupvalue(World.movementState,i)
 if not name then break end
 if name=='Game'then gameSlot,oldGame=i,value;break end
end
assert(gameSlot,'real native world Game binding')
T.eq(State.read(nil,{}),nil,'absent native player is not advertised as normal movement')
T.eq(State.read({},nil),nil,'absent native save is not a movement state')
for _,version in ipairs({'gold','silver','crystal','prism'})do
 Version.set(version)
 local save={onBike=false,flags={},playerState='bike'}
 local game={save=save,data={maps={ROAD={id='ROAD',environment=2}}}}
 debug.setupvalue(World.movementState,gameSlot,game)
 World.player={surfing=false,onBike=true};World.map={id='ROAD'}
 T.eq(World.playerState,'normal',version..' reads save bike flag rather than stale player copy/save state string')
 save.onBike=true
 T.eq(World.playerState,'bike','scripted save flag is visible before another world tick')
 World.player.surfing=true
 T.eq(World.playerState,'surf','actual surfing takes precedence over a stale bicycle flag')
 World.player.surfingPikachu=true
 T.eq(World.playerState,'surf_pika','actual Pikachu surf sheet is exposed')
 World.player.surfing=false;save.onBike=false
 T.eq(World.playerState,'normal','native dismount is immediately observable')
 Flags.set(save,G2Flags.bikeFlag('bike'))
 World:applyForcedBike()
 T.eq(World.playerState,'bike','real forced-bike map handler updates the observed state')
 T.eq(World:applyPlayerState('surf'),true,'native low-level state adoption succeeds')
 T.eq(save.onBike,false,'surf adoption clears native bicycle state')
 T.eq(World.player.onBike,false,'surf adoption clears mover bicycle copy')
 T.eq(World.player.surfing,true,'surf adoption changes native collision state')
 T.eq(World.playerState,'surf','adopted state is derived from native flags')
 World.playerState='surf_pika'
 T.eq(World.player.surfingPikachu,true,'property adoption chooses actual Pikachu sprite flag')
 T.eq(rawget(World,'playerState'),nil,'property adoption never creates a shadow state byte')
 local ok,reason=World:applyPlayerState('unsupported')
 T.eq(ok,nil,'unknown movement state is refused')
 T.check(type(reason)=='string','invalid adoption reports why')
 T.eq(World.playerState,'surf_pika','invalid state cannot partially mutate native flags')
 T.eq(pcall(function()World.playerState='unsupported'end),false,'invalid direct adoption is refused too')
 World.playerState=nil
 T.eq(World.playerState,'normal','nil property adoption restores actual walking')
 T.eq(State.isSurfing(World.playerState),false,'walking is not a surf state')
 World.playerState='bike'
 T.eq(State.isBiking(World.playerState),true,'bike observer agrees with native adoption')
 local replacement={onBike=false,flags={}}
 game.save=replacement
 T.eq(World.playerState,'normal','save adoption does not retain old bicycle/save reference')
 T.eq(save.onBike,true,'observing a replacement save leaves the old save untouched')
 World.player=nil
 T.eq(World.playerState,nil,'world teardown has no fictitious normal movement state')
end
for _,version in ipairs({'red','emerald','firered','platinum'})do
 Version.set(version)
 local save={onBike=false};debug.setupvalue(World.movementState,gameSlot,{save=save})
 World.player={surfing=true}
 T.eq(World.playerState,nil,'other generations do not acquire Gen2 state names: '..version)
 T.eq(World:applyPlayerState('bike'),nil,'Gen2 state adoption refuses other generations')
 T.eq(save.onBike,false,'refused adoption preserves other-generation save')
 T.eq(World.player.surfing,true,'refused adoption preserves other-generation mover')
end
rawset(World,'player',oldPlayer);rawset(World,'map',oldMap)
debug.setupvalue(World.movementState,gameSlot,oldGame)
Version.set(oldVersion)
T.finish('live native Gen2 movement state and atomic adoption')
