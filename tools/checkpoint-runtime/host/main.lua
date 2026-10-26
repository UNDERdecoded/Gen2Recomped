-- Native checkpoint transactions with actual host RNG and synthetic content.
local root = assert(os.getenv('CHECKPOINT_ENGINE'))
package.path = root..'/?.lua;'..root..'/?/init.lua;'..package.path
local host = love
local function qualify()
  local fake = require('tests.love_stub')
  fake.math = host.math
  love = fake
  local SDK = require('tests.modkit.sdk')
  local Json = require('src.link.Json')
  local Save = require('src.core.SaveData')
  local Serializer = require('src.core.SaveSerializer')
  local Version = require('src.core.GameVersion')
  local Game = require('src.core.Game')
  local Stack = require('src.core.StateStack')
  local World = require('src.world.OverworldController')
  local Maps = require('src.world.MapLoader')
  local Pokemon = require('src.pokemon.Pokemon')
  local cases, checks = {}, 0
  local function check(ok, reason)
    assert(ok, reason); checks = checks + 1
  end
  local function copy(value)
    return assert(Serializer.decode(Serializer.encode(value)))
  end
  for _, edition in ipairs({'red','gold'}) do
    for _, api in ipairs({1,2,3}) do
      Version.set(edition)
      local id = 'checkpoint_rng_'..api
      local fs = SDK.memfs({
        ['mods/'..id..'/manifest.json'] = Json.encode({id=id,name=id,version='1.0.0',api=api,entry='main.lua'}),
        ['mods/'..id..'/main.lua'] = 'return function(mod) mod.exports.checkpoints=mod.checkpoints end',
      })
      local loaded = SDK.loadMods({'mods/'..id},{fs=fs})
      check(#loaded.errors == 0,'actual loader accepts checkpoint facade')
      local checkpoints = assert(loaded.loader.exports[id].checkpoints)
      Stack:init()
      Game.stack, Game.data, Game.renderer = Stack, loaded.data, require('src.render.Renderer')
      Game.input = {isDown=function()return false end,pressed=function()return false end}
      Game.save = Save.newGame({version=edition,noHooks=true,pcItems={FIX_POTION=1}})
      Save.validate(Game.save,Game.data)
      Game.save.party = {Pokemon.new(Game.data,'FIXMON_A',5)}
      Game.save.meta.playthroughId = 'owned-native-checkpoint-rng'
      Game.save.player.map,Game.save.player.x,Game.save.player.y = 'FIX_TOWN',2,3
      Game.overworld,Game.world,Game.mods = World,World,loaded.loader
      loaded.loader.game,loaded.loader.modSave = Game,Game.save.modData
      if edition == 'gold' and Stack.setWorldOwner then
        Stack:setWorldOwner({world=World});Stack.worldState,Stack.worldOwner.world=World,World
      else Stack.states={World} end
      Maps.invalidateAll()
      World:_checkpointRebuild({map='FIX_TOWN',x=2,y=3,facing='down'})
      host.math.setRandomSeed(81731,api)
      local checkpoint,code,message = checkpoints:capture(Game)
      assert(checkpoint,message or code)
      check(checkpoint.rng.love == host.math.getRandomState(),'capture uses actual native RNG encoding')
      local expected = {}
      for i=1,64 do expected[i]=host.math.random() end
      check(checkpoints:restore(Game,checkpoint),'actual native restore succeeds')
      check(host.math.getRandomState() == checkpoint.rng.love,'actual encoded RNG rewinds')
      for i=1,64 do check(host.math.random() == expected[i],'actual RNG continuation '..i) end
      local before = host.math.getRandomState()
      local saved,map = Game.save,World.map
      local rebuild = World._checkpointRebuild
      local rebuilds = 0
      World._checkpointRebuild = function()
        rebuilds = rebuilds+1
        host.math.random()
        error('intentional native reconstruction failure')
      end
      local restored = checkpoints:restore(Game,checkpoint)
      World._checkpointRebuild = rebuild
      check(not restored and rebuilds == 1,'actual failed reconstruction is exercised')
      check(Game.save == saved and World.map == map,'failed reconstruction retains native ownership')
      check(host.math.getRandomState() == before,'failed reconstruction restores real native RNG')
      local bad = copy(checkpoint)
      bad.rng.love = 'invalid-native-rng-state'
      rebuilds = 0
      World._checkpointRebuild = function(...)rebuilds=rebuilds+1;return rebuild(...)end
      restored = checkpoints:restore(Game,bad)
      World._checkpointRebuild = rebuild
      check(not restored and rebuilds == 0,'actual RNG parser refuses invalid state before rebuilding')
      check(Game.save == saved and World.map == map,'invalid RNG cannot replace native progress')
      check(host.math.getRandomState() == before,'invalid RNG preflight preserves live random state')
      -- The real native NPC updater, including local and neighbour random
      -- spinners, must take the same turns after a reconstruction.
      for i,mode in ipairs({'SPIN_CW','SPIN_CCW','SPIN_SLOW','SPIN_FAST'}) do
        local map = Game.data.maps[i <= 2 and 'FIX_TOWN' or 'FIX_ROUTE']
        local object = copy(map.objects[1])
        object.index,object.x = i+10,7+i
        object.movement,object.range = 'SPIN',mode
        map.objects[#map.objects+1] = object
      end
      Maps.invalidateAll()
      World:_checkpointRebuild({map='FIX_TOWN',x=2,y=3,facing='down'})
      local ids = {}
      for id,actor in pairs(World.npcPool) do
        if actor.spins then ids[#ids+1]=id;actor.timer=1 end
      end
      table.sort(ids)
      check(#ids == 4,'all native stationary spinner modes are installed')
      host.math.setRandomSeed(27981,api)
      local spin = assert(checkpoints:capture(Game))
      local function tick()
        local values = {}
        for _,id in ipairs(ids) do
          local actor = World.npcPool[id]
          local mapId = id:match('^(.*)_obj_%d+$')
          actor:update(Maps.load(Game.data,mapId),World.entities)
          values[id] = {facing=actor.facing,timer=actor.timer}
        end
        return Serializer.encode(values),host.math.getRandomState()
      end
      local future = {}
      for frame=1,384 do future[frame]={tick()} end
      check(checkpoints:restore(Game,spin),'native reconstruction restores spinner continuation')
      for frame=1,384 do
        local actors,state = tick()
        check(actors == future[frame][1],'actual spinner continuation frame '..frame)
        check(state == future[frame][2],'actual spinner RNG continuation frame '..frame)
      end
      local pool,save,map,state = World.npcPool,Game.save,World.map,host.math.getRandomState()
      local Actors=require('src.core.CheckpointActors')
      local apply=Actors.apply
      Actors.apply=function(...)apply(...);error('intentional failure after native actor apply')end
      local restored,why = checkpoints:restore(Game,spin)
      Actors.apply=apply
      check(not restored and why == 'restore_failed','partial native spinner apply fails closed')
      check(World.npcPool == pool and Game.save == save and World.map == map,'partial spinner rollback retains native owners')
      check(Maps.load(Game.data,'FIX_TOWN') == map,'partial spinner rollback retains map cache')
      check(host.math.getRandomState() == state,'partial spinner rollback retains actual RNG')
      cases[#cases+1] = {edition=edition,api=api,continuation=true,rollback=true,invalidRngPreflight=true,
        spinnerModes=4,spinnerFrames=384,spinnerRngContinuation=true,spinnerPartialRollback=true}
    end
  end
  local continuation=dofile(root..'/tools/checkpoint-runtime/continuation.lua')(check)
  return {passed=true,checks=checks,cases=cases,continuation=continuation,loveVersion={host.getVersion()},
    realLoveMath=true,graphicsSubstituted=true,syntheticContent=true,playerProfilesUsed=false}
end
function host.load()
  local ok,result = xpcall(qualify,debug.traceback)
  love = host
  if not ok then error(result,0) end
  local file = assert(io.open(assert(os.getenv('CHECKPOINT_REPORT')),'w'))
  assert(file:write(require('src.link.Json').encode(result)));assert(file:close())
  print('NATIVE_CHECKPOINT_RNG_PASS',result.checks)
  host.event.quit(0)
end
function host.errorhandler(why)
  love = host
  io.stderr:write(debug.traceback(tostring(why),2)..'\n')
  return function()return 1 end
end
