-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Facts=require('src.import.Gen3VisualTaskFacts')
local X=require('src.import.RomExtractorGen3')
local function pack(...)return{n=select('#',...),...}end
local function u32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 for _,priority in ipairs{0,1,17,255}do
  -- Primary createvisualtask layout, with a real delay and signed operands.
  local bytes=string.rep('\0',256)..string.char(4,17,3)..u32(0x08001001)
   ..string.char(priority,2,0,128,255,127,8)..string.rep('\0',32)
  local reader=X.new(bytes,edition)
  local result=pack(reader:animScriptRead(256))
  T.eq(result[2],true);local tasks=result[7];T.eq(#tasks,1)
  local t=tasks[1];T.eq(t.priority,priority);T.eq(t.at,17);T.eq(t.fn,0x1001)
  T.same(t.args,{-32768,32767})
  for _,kind in ipairs{'dig_down','dig_up','surf'}do
   local d=assert(Facts.fromTask(kind,t));T.eq(d.schema,1);T.eq(d.kind,kind)
   T.eq(d.priority,priority);T.eq(d.at,17);T.eq(d.nativeFunction,0x1000)
   T.same(d.args,t.args);T.neq(d.args,t.args)
   d.args[1]=123;T.eq(t.args[1],-32768,'source metadata owns its operand array')
  end
 end
end
local task={fn=0x1001,priority=2,at=0,args={0}}
T.eq(Facts.fromTask('unknown',task),nil)
for _,key in ipairs{'fn','priority','at','args'}do
 local copy={fn=task.fn,priority=task.priority,at=task.at,args=task.args}
 copy[key]=false;T.eq(Facts.fromTask('surf',copy),nil,'invalid operand '..key)
end
for _,args in ipairs{{[0]=1},{[2]=1},{1,2,3,4,5,6,7,8,9},{0/0},{32768},{-32769},{'0'}}do
 T.eq(Facts.fromTask('surf',{fn=0x1001,priority=2,at=0,args=args}),nil)
end
local Player=require('src.battle.Gen3MoveAnim')
for _,at in ipairs{0,1,17,255}do
 local shape={at=at,life=134,waitLife=136,step=2,fade=13,hold=54,blendOf=16,
  player={image='native wave',x=10,y=20,dx=3,dy=-1},opponent={image='native wave',x=10,y=20,dx=-3,dy=1}}
 local data={constants={gen3BattleAnimGfx={}},moves={SURF={anim={surf=shape}}}}
 for _,playerSide in ipairs{true,false}do
  local native=Player.new(data);T.eq(native:start('SURF',playerSide,playerSide and 0 or 1,playerSide and 1 or 0),true)
  T.eq(native.total,at+136,'the native wait includes the script timestamp')
  for frame=0,at+136 do
   native.frame=frame;local age=frame-at;local actual=native:surfLayer()
   local counter,halves,blend=1,0,0
   for _=1,math.max(0,age)do
    counter=counter+1
    if counter==2 then
     counter=0;halves=halves+1
     if halves<=13 then blend=blend+1 elseif halves>54 then blend=blend-1 end
    end
   end
   if age<0 or age>=134 or blend<=0 then T.eq(actual,nil,'no wave outside the native task')
   else
    T.neq(actual,nil);T.eq(actual.alpha,blend/16)
    T.eq(actual.x,10+(playerSide and 3 or -3)*age)
    T.eq(actual.y,20+(playerSide and -1 or 1)*age)
   end
  end
 end
end
T.finish('native visual-task operands, detached metadata and delayed Surf timing')
