-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local root=assert(os.getenv('GEN2_LIFECYCLE_ROOT'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
require('src.core.GameVersion').set('crystal')
local Profile=require('src.core.FrameProfile')
local Json=require('src.link.Json')
local SDK=require('tests.modkit.sdk')
local Loader=require('src.mods.Loader')
local before,after={},{}
for _,name in ipairs({'Gen2Friendship','RoamMons','BugContest'})do
  before[name]=assert(loadfile(assert(os.getenv('GEN2_LIFECYCLE_BASELINE'))..'/'..name..'.lua'))()
  after[name]=require((name=='Gen2Friendship'and 'src.pokemon.'or 'src.world.')..name)
end
local phase,frame,total,loader,save,game,modules=1,0,0
local results={}
local function start()
  Profile.setEnabled(false)
  local data=require('tests.modkit.fixtures').fresh()
  local enabled=phase~=2
  local files={
    ['mods/probe/manifest.json']=Json.encode({id='probe',name='Probe',version='1.0.0',api=2,entry='main.lua',games={'gen2'}}),
    ['mods/probe/main.lua']=[[local mod=...
      mod.exports.count=0
      for _,name in ipairs({'happiness.changed','roamer.encountered','bug_contest.scored'})do
        mod.events:on(name,function()mod.exports.count=mod.exports.count+1 end)
      end]],
    ['options.lua']='return {mods={probe='..tostring(enabled)..'}}',
  }
  loader=Loader.new({fs=SDK.memfs(files),dev=false});assert(loader:load(data))
  local mon={happiness=70,hp=100,maxHp=100,species='FIXMON_A',dvs={},stats={attack=50,defense=50,speed=50,special=50}}
  save={party={mon},flags={},g2RoamReleased=true,g2Roam={RAIKOU={active=true,mapId='OWN_MAP',level=40}},
    g2BugContest={caught=mon,scores={}}}
  game={data=data,save=save};modules=phase==1 and before or after
  frame,total=0,0
end
local function rng()return 1 end
function love.errorhandler(message)
  print(debug.traceback(tostring(message),2));return function()return 1 end
end
function love.run()
  start()
  return function()
    love.event.pump()
    for event in love.event.poll()do if event=='quit'then return 1 end end
    if frame==120 then Profile.setEnabled(true)end
    local close=Profile.section('mods.lifecycle (192 transitions)')
    local began=love.timer.getTime()
    for _=1,64 do
      local mon=save.party[1];mon.happiness=70
      modules.Gen2Friendship.change(mon,'LEVELUP')
      assert(modules.RoamMons.check(save,'OWN_MAP',false,rng)=='RAIKOU')
      modules.BugContest.judge(game)
    end
    if frame>=120 then total=total+love.timer.getTime()-began end
    close()
    love.graphics.clear(.03,.04,.06)
    love.graphics.print('Native lifecycle: '..({'before','after, no observer','after, observer'})[phase],12,12)
    love.graphics.present()
    if frame>=120 then Profile.frame()end
    frame=frame+1
    if frame==240 then
      results[phase]={mode=({'before','after_no_observer','after_observer'})[phase],
        frames=120,meanMs=total/120*1000,observations=loader.exports.probe and loader.exports.probe.count or 0}
      assert(#loader.errors==0,table.concat(loader.errors,'; '))
      Loader.teardown()
      if phase==3 then
        assert(results[1].observations==0 and results[2].observations==0 and results[3].observations==240*192)
        print('LIFECYCLE_PROFILE '..Json.encode({phases=results,renderer=love.graphics.getRendererInfo(),
          os=love.system.getOS(),arch=jit.arch,
          scope='Native Love host, real Loader observer and three production producers over owned data; no cartridge scene or FPS claim'}))
        return 0
      end
      phase=phase+1;start()
    end
  end
end
