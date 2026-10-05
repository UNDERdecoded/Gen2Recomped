package.path='./?.lua;'..package.path
love=love or {}
local errors={}
package.loaded['src.core.Logger']=setmetatable({error=function(fmt,...) errors[#errors+1]=string.format(fmt,...) end},{__index=function() return function() end end})
local C=require('src.script.Commands')
require('src.script.Gen4Commands')
local VM=require('src.script.Gen4ScriptVM')
local Runner=require('src.script.ScriptRunner')
local root=arg[1] or 'G:/Gen2Recomped/platinum/data/generated/'
local data={constants={gen=4},maps=assert(loadfile(root..'maps.lua'))(),map_scripts=assert(loadfile(root..'map_scripts.lua'))(),text=assert(loadfile(root..'text.lua'))()}
local rows=assert(VM.resolveTalk(data,'D01R0102',1,nil))
-- Keep the actual VM, runner, movement decoder, variable/flag/object commands.
-- Acknowledge dialogue and finish movement through deferred UI/world callbacks.
local oldText,oldSound=C.show_text,C.play_sound
C.show_text=function(ctx,id)
 assert(data.text[id] and #data.text[id]>0,'missing ROM dialogue: '..tostring(id))
 ctx.overworld.messages[#ctx.overworld.messages+1]=id
 ctx.overworld.pending=function() ctx.runner:resume() end
 ctx.runner:yield()
end
C.play_sound=function() end
local function runRoark(script)
 local roark={localId=0,cellX=18,cellY=28,stepFrames=16,def={index=1},facePlayer=function() end}
 local rock={localId=1,def={index=2}}
 local ow={map={id='D01R0102',def=data.maps.D01R0102},entities={roark,rock},messages={},player={cellX=16,cellY=28,stepFrames=16}}
 -- The real overworld queues pauses and on-the-spot steps the same way it
 -- queues walks; without this the movement chain raised at Roark's first
 -- pause and the scene froze in the CHECK rather than in the game.
 function ow:scriptPause(entity,frames,done) self.pending=function() done() end end
 function ow:scriptMove(entity,dir,tiles,done)
  self.pending=function()
   local dx=dir=='right' and 1 or dir=='left' and -1 or 0
   local dy=dir=='down' and 1 or dir=='up' and -1 or 0
   entity.cellX,entity.cellY=entity.cellX+dx*tiles,entity.cellY+dy*tiles
   done()
  end
 end
 local game={data=data,save={flags={},player={},gen4Vars={}}}
 local runner=Runner.new(game,ow)
 runner:run(script,{npc=roark})
 for frame=1,2000 do
  local pending=ow.pending;ow.pending=nil;if pending then pending() end
  runner:update()
  if not runner:isRunning() then break end
 end
 return runner,game,ow,roark,rock
end
-- Demonstrate that the old completion result reproduces the reported freeze.
local fixed=C.g4_destroy_obstacle_anim
C.g4_destroy_obstacle_anim=function(ctx,kind,dest) ctx.save.gen4Vars[dest]=0 end
local stuck=runRoark(rows)
assert(stuck:isRunning() and stuck.lastRow:match('wait'),'old obstacle result must reproduce polling freeze')
C.g4_destroy_obstacle_anim=fixed
local runner,game,ow,roark,rock=runRoark(rows)
assert(not runner:isRunning(),'Roark froze at '..tostring(runner.lastRow))
assert(#ow.messages==2,'both mine dialogue lines must be acknowledged')
assert(roark.hidden and rock.hidden,'rock removal and Roark departure missing')
assert(game.save.flags.FLAG_G4_007A and game.save.flags.FLAG_G4_017C,'departure flags missing')
assert(not runner.ctx.g4Locked,'controls not released')
assert(roark.cellX==28 and roark.cellY==28,'departure movement did not finish')
assert(#errors==0,table.concat(errors,'\n'))
C.show_text,C.play_sound=oldText,oldSound
-- Every obstacle kind must complete without modifying comparison state.
for kind=0,2 do
 local ctx={save={gen4Vars={[0x8005]=0}},g4Compare=2,lastCheck=false}
 fixed(ctx,kind,0x8005)
 assert(ctx.save.gen4Vars[0x8005]==1 and ctx.g4Compare==2 and ctx.lastCheck==false)
end
-- WaitSE must preserve its ID, resolve variable operands, and ignore unrelated audio.
local queried,playing=0,true
local oldAudio=package.loaded['src.core.Sound']
package.loaded['src.core.Sound']={isPlaying=function(id) queried=id;return playing end,anyPlaying=function() error('wait must not poll unrelated effects') end}
local audioRows=VM.lower({{name='waitse',args={0x8000}}})
assert(audioRows[1][2]==0x8000,'WaitSE operand lost')
local audioRunner=Runner.new({data=data,save={gen4Vars={[0x8000]=1500}}},{})
audioRunner:run(audioRows)
audioRunner:update();assert(audioRunner:isRunning() and queried==1500)
playing=false;audioRunner:update();assert(not audioRunner:isRunning())
package.loaded['src.core.Sound']=oldAudio
print('Roark real ROM script: old freeze reproduced; both messages, rock removal, departure movement, flags and control release passed')
print('All three obstacle completion variants and isolated, variable-resolved WaitSE passed')

-- Check all imported obstacle sites, not just the mine demonstration.
local sites,kinds=0,{}
for label,block in pairs(data.map_scripts.scripts) do
 for _,ins in ipairs(block.instructions or {}) do
  if ins.name=='startdestroyobstacleanimation' then
   sites=sites+1;kinds[ins.args[1]]=true
   local lowered=VM.lower({ins})
   local ctx={save={gen4Vars={}}}
   C[lowered[1][1]](ctx,lowered[1][2],lowered[1][3])
   assert(ctx.save.gen4Vars[ins.args[2]]==1,'incomplete obstacle at '..label)
  end
 end
end
assert(sites>0,'obstacle corpus was empty')
local started,stopped,cried
package.loaded['src.core.Sound']={
 play=function(_,id) started=id end,
 stop=function(id) stopped=id end,
 playCry=function(_,species) cried=species end,
}
local eventRows=VM.lower({{name='playse',args={0x8000}},{name='stopse',args={0x8000}},{name='playcry',args={0x8001,1}}})
local ctx={game={data=data},save={gen4Vars={[0x8000]=1500,[0x8001]=95}}}
for _,row in ipairs(eventRows) do C[row[1]](ctx,row[2],row[3]) end
assert(started==1500 and stopped==1500,'play/stop effects must resolve the same variable as WaitSE')
assert(cried==95 and ctx.pendingCry==nil and ctx.pendingCryWait==nil,'cry must start now; unused operand cannot change dialogue')
package.loaded['src.core.Sound']=oldAudio
assert(#errors==0,table.concat(errors,'\n'))
print(sites..' imported obstacle animation sites complete; NPC effect/cry variable operands and immediate cries passed')
