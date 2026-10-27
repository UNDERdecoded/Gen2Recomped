-- A bounded native command pass over detached state. It never publishes a
-- field, borrows a live runner, dispatches mod hooks or starts UI/audio/IO.
local Bundle=require('src.compat.gen1.ScriptBundle')
local M={}
local admission={maxInstructions=4000,commands={
  label=true,jump=true,g3_call=true,g3_return=true,g3_jump_if=true,g3_jump_unless=true,g3_call_if=true,
  g3_setvar=true,g3_addvar=true,g3_subvar=true,g3_copyvar=true,g3_setorcopyvar=true,
  g3_compare_value=true,g3_compare_var=true,g3_check_flag=true,
  g3_place_perm=true,g3_movement_type=true,
}}
function M.run(c,nativeId)
  local snapshot=c.backend:snapshot()
  local save={flags={},gen3Vars=Bundle.copy(snapshot.vars)}
  for id,value in pairs(snapshot.flags)do save.flags[('FLAG_G3_%04X'):format(id)]=value end
  for id=0x4010,0x401f do save.gen3Vars[id]=nil end
  local entry=c.pool and c.pool.maps and c.pool.maps[nativeId]
  local key
  for _,cb in ipairs(entry and entry.callbacks or{})do if cb.type==3 then key=cb.script;break end end
  if key then
    local rows=require('src.script.Gen3ScriptVM').compile(c.data,key)
    if not rows then return nil,'native neighbour transition did not compile'end
    local runner=require('src.script.ScriptRunner').new({data=c.data,save=save})
    local ctx=runner:makeContext({mapId=nativeId,source={strict=true}})
    local ok,why=pcall(runner.exec,runner,rows,ctx,admission)
    if not ok then return nil,why end
  end
  local flags,vars={},{}
  for name,value in pairs(save.flags)do local hex=name:match('^FLAG_G3_(%x%x%x%x)$');if hex then flags[tonumber(hex,16)]=value end end
  for id,value in pairs(save.gen3Vars)do if not c.backend:isSpecial(id)then vars[id]=value end end
  local result={store={flags=flags,vars=vars},perm={},movementType={}}
  for id,home in pairs(save.gen3ObjectHomes and save.gen3ObjectHomes[nativeId]or{})do
    if home.x~=nil and home.y~=nil then result.perm[id]={x=home.x,y=home.y}end
    result.movementType[id]=home.movementType
  end
  return result
end
return M
