package.path='./?.lua;'..package.path
require('src.script.Gen4Commands')
local C=require('src.script.Commands')
local VM=require('src.script.Gen4ScriptVM')
local ctx={save={gen4Vars={[0x4001]=1}},gen4ApproachingTrainers={41,72},g4Compare=2,lastCheck=false}
C.g4_get_approaching_trainer_id(ctx,0,0x4000)
assert(ctx.save.gen4Vars[0x4000]==41)
C.g4_get_approaching_trainer_id(ctx,0x4001,0x4000)
assert(ctx.save.gen4Vars[0x4000]==72,'approach number must resolve variables')
C.g4_get_approaching_trainer_id(ctx,9,0x4000)
assert(ctx.save.gen4Vars[0x4000]==72,'all nonzero slots select trainer two')
ctx.gen4ApproachingTrainers=nil
ctx.npc={def={trainer={id=83}}}
C.g4_get_approaching_trainer_id(ctx,0,0x4000)
assert(ctx.save.gen4Vars[0x4000]==83,'talk scripts use their trainer when no encounter is active')
C.g4_get_approaching_trainer_id(ctx,1,0x4000)
assert(ctx.save.gen4Vars[0x4000]==0,'missing second trainer must not reuse trainer one')
assert(ctx.g4Compare==2 and ctx.lastCheck==false,'lookup must preserve comparison state')
local rows=VM.lower({{name='getapproachingtrainerid',args={0x4001,0x4000}}})
assert(rows[1][1]=='g4_get_approaching_trainer_id' and rows[1][2]==0x4001 and rows[1][3]==0x4000)
assert(loadfile('src/world/OverworldController.lua'))
print('Approaching trainer checks passed: slots, variables, talk fallback, missing partner, comparison state and lowering')
