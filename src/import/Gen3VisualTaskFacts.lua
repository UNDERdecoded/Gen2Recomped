-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Scalar interface facts for tasks already resolved by native ROM readers.
-- Byte layout: pret/pokeemerald 731ad5bfd6e6f265508d0efcca0ba42f9dcf5881,
-- asm/macros/battle_anim_script.inc, createvisualtask (opcode/fn/u8/u8/s16[]).
local M={REVISION=1,SCHEMA=1}
local names={dig_down='AnimTask_DigDownMovement',dig_up='AnimTask_DigUpMovement',
 surf='AnimTask_CreateSurfWave'}
local function integer(value,low,high)
 return type(value)=='number'and value==value and value%1==0 and value>=low and value<=high
end
function M.fromTask(kind,task)
 local name=names[kind]
 if not name then return nil,'native visual task family is not exposed'end
 local at=type(task)=='table'and task.at
 if at==nil then at=0 end
 if type(task)~='table'or not integer(task.fn,1,0x1ffffff)
  or not integer(task.priority,0,255)or not integer(at,0,0x7fffffff)
  or task.site~=nil and not integer(task.site,0,0x1ffffff)
  or task.order~=nil and not integer(task.order,1,0x7fffffff)
  or type(task.args)~='table'or #task.args>8 then
  return nil,'native visual task operands unavailable'
 end
 local args={}
 for i,value in ipairs(task.args)do
  if not integer(value,-32768,32767)then return nil,'invalid native visual task operand'end
  args[i]=value
 end
 for key in pairs(task.args)do
  if not integer(key,1,#args)then return nil,'invalid native visual task operand index'end
 end
 return{schema=M.SCHEMA,kind=kind,name=name,priority=task.priority,args=args,
  at=at,nativeFunction=task.fn-task.fn%2,scriptOffset=task.site,order=task.order}
end
return M
