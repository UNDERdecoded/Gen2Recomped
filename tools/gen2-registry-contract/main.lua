-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local root=assert(os.getenv('GEN2_REGISTRY_ROOT'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local Profile=require('src.core.FrameProfile')
local Json=require('src.link.Json')
local file=assert(io.open(assert(os.getenv('GEN2_REGISTRY_BASELINE')),'rb'))
local before=assert(loadstring(file:read('*a'),'@baseline/Schemas.lua'))()
file:close()
local after=require('src.mods.Schemas')
local rows={
  apricorns={apricorn='FRUIT',ball='BALL',event=600,index=1},
  decorations={type=2,name='BED',action='SET_UP_BED',flag=500,sprite=0},
  landmarks={name='HOME',x=80,y=72,index=1},
  phone_contacts={index=2,name='CALLER',number=2,calleeTime=0,callerTime=0},
  radio_channels={channel=9,name='STATION'},
}
local phase,frame,total=1,0,0
local results={}
function love.errorhandler(message)
  print(debug.traceback(tostring(message),2))
  return function()return 1 end
end
function love.run()
  return function()
    love.event.pump()
    for name in love.event.poll()do if name=='quit'then return 1 end end
    if frame==120 then Profile.setEnabled(true)end
    local schema=phase==1 and before or after
    local close=Profile.section('mods.registry.validate (320 records)')
    local began=love.timer.getTime()
    for _=1,64 do
      for name,row in pairs(rows)do
        assert(schema.check(schema.REGISTRIES[name],name,'QA',row,'register'))
      end
    end
    if frame>=120 then total=total+love.timer.getTime()-began end
    close()
    love.graphics.clear(.03,.04,.06)
    love.graphics.print('Gen2 registry validation: '..(phase==1 and 'before' or 'after'),12,12)
    love.graphics.present()
    if frame>=120 then Profile.frame()end
    frame=frame+1
    if frame==240 then
      results[phase]={mode=phase==1 and 'before' or 'after',frames=120,meanMs=total/120*1000}
      if phase==2 then
        print('REGISTRY_PROFILE '..Json.encode({phases=results,renderer=love.graphics.getRendererInfo(),
          os=love.system.getOS(),arch=jit.arch,
          scope='Owned records, native Love host and FrameProfile section; schema validation only, no gameplay scene'}))
        return 0
      end
      Profile.setEnabled(false)
      phase,frame,total=2,0,0
    end
  end
end
