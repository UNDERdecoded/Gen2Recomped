package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald party object moves')
local data={}
local root='G:/Gen2Recomped/emerald/data/generated/'
for _,k in ipairs({'constants','maps','map_scripts','text','pokemon','moves','items'}) do
  data[k]=assert(loadfile(root..k..'.lua'))()
end
require('src.core.GameVersion').set('emerald')
local Field=require('src.world.Gen3PartyFieldMoves')
local Party=require('src.ui.Gen3PartyMenu')
local Runner=require('src.script.ScriptRunner')
local Commands=require('src.script.Gen3Commands')
local Sweep=require('src.world.Gen3FieldMove')
local original=Sweep.show
local pending,selected
Sweep.show=function(_,mon,done) selected=mon;pending[#pending+1]={onDone=done};return true end
local function fixture()
  pending={};selected=nil
  local mon={species='MUDKIP',nickname='CHOSEN',moves={{id='CUT'},{id='ROCK_SMASH'},{id='SECRET_POWER'}}}
  local g={data=data,save={party={{species='RALTS',moves={}},mon},inventory={},flags={},player={name='BRENDAN'}},
    stack={push=function(_,s) pending[#pending+1]=s end,pop=function() end}}
  local ow={player={facing='up',cellX=4,cellY=5,facingCell=function() return 4,4 end},
    map={id='TEST',def={signs={{x=4,y=4,secretBaseId=30}}},cellBehaviour=function() return 0x90 end}}
  g.overworld=ow
  local menu=setmetatable({game=g},Party)
  menu.regiUsableBy=function() end
  menu.close=function() menu.closed=true end
  menu.say=function(_,s) menu.refused=s end
  ow.gen3HasBadge=function() return true end
  ow.queueScript=function(_,rows,extra) ow.queued={rows,extra} end
  ow.startWarpTo=function(_,id,x,y,facing,done) ow.warp=id;pending[#pending+1]={onDone=done} end
  ow.scriptPause=function(_,_,_,done) done() end
  ow.scriptMove=function(_,_,_,_,done) done() end
  return g,ow,menu,mon
end
local function run(g,ow,rows,extra)
  local r=Runner.new(g,ow);r:run(rows,extra)
  local ticks=0
  while r:isRunning() and ticks<1000 do
    ticks=ticks+1
    local s=table.remove(pending,1)
    if s and s.onDone then s.onDone() end
    if ow.fadeOverlay then ow.fadeOverlay:update(1/60) end
    r:update()
  end
  T.check(ticks<1000,'native field script completes')
end
local special174=Commands.SPECIALS[174]
local encountered=0
Commands.SPECIALS[174]=function(ctx) encountered=encountered+1;Commands.setVar(ctx.save,0x800D,0) end
for _,move in ipairs({'CUT','ROCK_SMASH'}) do
  local prop=move=='CUT' and 'cuttable' or 'smashable'
  local mapId,obj
  for id,def in pairs(data.maps) do
    for _,o in ipairs(def.objects or {}) do if o[prop] then mapId,obj=id,o;break end end
    if obj then break end
  end
  local g,ow,menu,mon=fixture()
  ow.map.id=mapId;ow.map.def=data.maps[mapId]
  local npc={def=obj,cellX=4,cellY=4,elevation=1}
  ow.player.elevation=1
  ow.npcAtCell=function() return npc end
  ow.npcByIndex=function(_,index) if index==obj.index then return npc end end
  menu:useFieldMove(mon,move)
  T.check(menu.closed and ow.queued,'party dispatches '..move)
  T.eq(ow.queued[1][5][1],'g3_field_effect','party callback skips interaction used-message '..move)
  run(g,ow,ow.queued[1],ow.queued[2])
  T.eq(selected,mon,'selected party member performs '..move)
  T.check(not ow.g3Locked,'control released after '..move)
  if obj.eventFlag then T.eq(g.save.flags[obj.eventFlag],true,'object removal flag '..move)
  else T.eq(g.save.gen3SessionObjects[obj.index],false,'session object removal '..move) end
  ow.player.elevation=2;T.eq(Field.target(ow,move),nil,'elevation refuses '..move)
  ow.player.elevation=1;npc.moving=true;T.eq(Field.target(ow,move),nil,'moving object refuses '..move)
  npc.moving=false;ow.gen3HasBadge=function() return false end
  menu.closed=nil;ow.queued=nil;menu:useFieldMove(mon,move)
  T.eq(menu.closed,nil,'missing badge refuses '..move)
  T.eq(ow.queued,nil,'missing badge queues nothing '..move)
end
T.eq(encountered,1,'Rock Smash retains native encounter dispatch')
Commands.SPECIALS[174]=special174
for behavior,effect in pairs({[0x90]=11,[0x96]=26,[0x98]=27}) do
  local g,ow,menu,mon=fixture()
  ow.map.cellBehaviour=function() return behavior end
  menu:useFieldMove(mon,'SECRET_POWER')
  T.check(menu.closed and ow.queued,'Secret Power menu accepts closed entrance '..behavior)
  run(g,ow,ow.queued[1],ow.queued[2])
  T.eq(selected,mon,'selected member creates base')
  T.eq(g.save.gen3SecretBase.id,30,'native callback keeps entrance ID')
  T.eq(ow.warp,require('src.world.Gen3SecretBase').roomFor(data.constants.gen3SecretBases,30).map,'native base interior')
  T.eq(Field.secretTarget(data,g.save,ow),nil,'owned base refuses party Secret Power')
end
local g,ow=fixture()
local _,_,menu,mon=fixture()
local offered={}
for _,row in ipairs(menu:fieldMovesOf(mon)) do offered[row.move]=true end
for _,move in ipairs({'CUT','ROCK_SMASH','SECRET_POWER'}) do T.check(offered[move],'native party menu offers '..move) end
ow.player.facing='left';T.eq(Field.secretTarget(data,g.save,ow),nil,'north-facing gate')
ow.player.facing='up'
for _,b in ipairs({0,0x92,0x94,0x9A}) do
  ow.map.cellBehaviour=function() return b end
  T.eq(Field.secretTarget(data,g.save,ow),nil,'opened or unrelated terrain refuses '..b)
end
Sweep.show=original
T.finish()
