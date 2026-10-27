-- Owned script/event observations; the native compiler remains the executor.
local Identity=require('src.compat.gen1.MapIdentity')
local Header=require('src.import.Gen3ScriptInterface')
local Iteration=require('src.compat.gen1.TableIteration')
local M={}
local records=setmetatable({},{__mode='k'})
function M.copy(value,seen)
  if type(value)~='table'then return value end
  seen=seen or{};if seen[value]then return seen[value]end
  local out={};seen[value]=out
  for k,v in pairs(value)do out[M.copy(k,seen)]=M.copy(v,seen)end
  return out
end
function M.sourceKey(key)
  if type(key)=='number'then
    if key>=0x08000000 and key<0x0a000000 then return ('g3:%08x'):format(key)end
    return key
  end
  if type(key)~='string'then return key end
  local hex=key:match('^[SM](%x+)$')
  if hex then return ('g3:%08x'):format(0x08000000+tonumber(hex,16))end
  return key
end
function M.nativeKey(key,prefix)
  if type(key)=='number'then
    if key<0x08000000 or key>=0x0a000000 then return nil end
    return (prefix or'S')..('%07X'):format(key-0x08000000)
  end
  if type(key)~='string'then return nil end
  local hex=key:match('^g3:(%x+)$')
  return hex and M.nativeKey(tonumber(hex,16),prefix)or key
end
local aliases={loadword={'dest','value'},setvar={'var','value'},compare_var_to_value={'var','value'},
  setflag={'flag'},clearflag={'flag'},checkflag={'flag'},setworldmapflag={'flag'},callstd={'std'},gotostd={'std'},
  ['goto']={'target'},call={'target'},goto_if={'cond','target'},call_if={'cond','target'},
  applymovement={'localId','movement'},applymovementat={'localId','movement'},waitmovement={'localId'},
  removeobject={'localId'},addobject={'localId'},message={'ptr'},special={'id'},specialvar={'var','id'},
  textcolor={'color'},setobjectxyperm={'localId'},setobjectmovementtype={'localId'},
  callnative={'fn'},gotonative={'fn'}}
local targets={['goto']=1,call=1,goto_if=2,call_if=2,vgoto=1,vcall=1,vgoto_if=2,vcall_if=2}
local trainerPointers={
  [0]={'introText','defeatText'},[1]={'introText','defeatText','eventScript'},
  [2]={'introText','defeatText','eventScript'},[3]={'defeatText'},
  [4]={'introText','defeatText','notEnoughText'},[5]={'introText','defeatText'},
  [6]={'introText','defeatText','notEnoughText','eventScript'},
  [7]={'introText','defeatText','notEnoughText'},[8]={'introText','defeatText','notEnoughText','eventScript'},
  [9]={'introText','defeatText'},[10]={'introText','defeatText'},[11]={'introText','defeatText'},[12]={'introText','defeatText'},
}
function M.row(ir,edition)
  local row={op=ir[1],opcode=ir.sourceOpcode}
  if ir.sourceSpec=='*'and type(ir.sourceBytes)=='string'then
    local bytes=ir.sourceBytes
    local function number(at,n)
      local value=0;for i=0,n-1 do value=value+assert(bytes:byte(at+i),'truncated trainer operands')*256^i end;return value
    end
    row.type=number(1,1);row.trainer=number(2,2);row.localId=number(4,2)
    row[1],row[2]=row.trainer,row.localId
    local fields=trainerPointers[row.type]
    if row.type==9 and(edition=='firered'or edition=='leafgreen')then fields={'defeatText','victoryText'};row.flags=row.localId end
    assert(fields,'original trainer battle type unavailable')
    assert(#bytes==5+#fields*4,'trainer operand size differs')
    for i,name in ipairs(fields)do row[name]=M.sourceKey(number(6+(i-1)*4,4))end
  elseif ir.sourceSpec and type(ir.sourceBytes)=='string'then
    local at=1
    for i=1,#ir.sourceSpec do
      local width=({b=1,w=2,d=4})[ir.sourceSpec:sub(i,i)]
      assert(width,'invalid original operand specification')
      local value=0
      for n=0,width-1 do value=value+assert(ir.sourceBytes:byte(at+n),'truncated original operands')*256^n end
      row[i]=value;at=at+width
    end
    assert(at==#ir.sourceBytes+1,'original operand size differs')
  else
    assert(ir[1]~='trainerbattle','original trainer-battle projection is not yet available')
    for i=2,#ir do row[i-1]=M.copy(ir[i])end
  end
  if ir[1]=='special'or ir[1]=='specialvar'then
    assert(type(ir.sourceSpecial)=='number','original script operands unavailable; cartridge cache needs regeneration')
    row[ir[1]=='special'and 1 or 2]=ir.sourceSpecial
  end
  local target=targets[row.op]
  if target then row[target]=M.sourceKey(row[target])end
  if row.op=='message'or row.op=='vmessage'or row.op=='braillemessage'or row.op=='getbraillestringwidth'
      or row.op=='messageautoscroll'or row.op=='messageinstant'or row.op=='pokenavcall'then
    row[1]=M.sourceKey(row[1]);row.ptr=row[1]
  end
  if row.op=='loadword'then row[2]=M.sourceKey(row[2])end
  if row.op=='bufferstring'then row[2]=M.sourceKey(row[2]);row.src=row[2]end
  if row.op=='applymovement'or row.op=='applymovementat'then row[2]=M.sourceKey(row[2])end
  for i,name in ipairs(aliases[row.op]or{})do row[name]=row[i]end
  return row
end
local phaseNames={[1]='onLoad',[2]='onFrame',[3]='onTransition',[4]='onWarpIntoMap',
  [5]='onResume',[6]='onDiveWarp',[7]='onReturnToField'}
function M.new(data,edition,valid)
  local pool=data and data.map_scripts
  if not(pool and pool.source=='RomExtractorGen3'and type(pool.scripts)=='table')then
    return nil,'native script bundle unavailable'
  end
  local binding=Identity.bind(data.maps,edition)
  local bundle={scripts={},events={},labels={},fromNative=true}
  local cache,expected={},{}
  records[bundle]={cache=cache,expected=expected,scripts=bundle.scripts}
  -- Materialize a list only when a consumer asks for it. Mutating this owned
  -- list never mutates the compiler cache or another mod's native definitions.
  local function script(key)
    assert(valid(),'native script bundle retired')
    local native=M.nativeKey(key)
    native=pool.labels and(pool.labels[native]or native)or native
    local rows=pool.scripts[native];if not rows then return nil end
    local canonical=M.sourceKey(native);local cached=cache[canonical]
    if cached then return cached end
    local out={};for i,ir in ipairs(rows)do out[i]=M.row(ir,edition)end
    cache[canonical]=out;expected[canonical]=M.copy(out);return out
  end
  setmetatable(bundle.scripts,{__index=function(_,key)return script(key)end})
  Iteration.register(bundle.scripts,function()
    assert(valid(),'native script bundle retired')
    local out={};for key in pairs(pool.scripts)do local source=M.sourceKey(key);out[source]=script(source)end;return out
  end)
  for key,label in pairs(pool.labels or{})do bundle.labels[key]=M.sourceKey(label)end
  bundle.nativeMovementsAvailable=type(pool.movements)=='table'
  -- Native text definitions retain their native keys. The text-IR service
  -- owns address/name projection and richer control-code semantics.
  bundle.nativeTextAvailable=type(data.text)=='table'
  for nativeId,entry in pairs(pool.maps or{})do
    local id=binding:legacyId(nativeId)
    local def=data.maps[nativeId]
    if id and def then
      local ev={objects=M.copy(def.objects or{}),bgEvents=M.copy(def.signs or{}),coordEvents=M.copy(def.coordEvents or{}),
        mapScripts={onFrame={},onWarpIntoMap={}},music=def.music}
      for i,obj in ipairs(ev.objects)do
        obj.localId=obj.localId or obj.index;obj.graphics=obj.graphicsId;obj.flag=obj.flagId or obj.flag
        obj.scriptKey=M.sourceKey((entry.objects or{})[i])
      end
      for i,sign in ipairs(ev.bgEvents)do sign.scriptKey=M.sourceKey((entry.signs or{})[i])end
      for _,cb in ipairs(entry.callbacks or{})do
        local name=phaseNames[cb.type];if name then ev.mapScripts[name]=M.sourceKey(cb.script)end
      end
      for _,tbl in ipairs(entry.tables or{})do
        local name=phaseNames[tbl.type]
        if name then
          local rows={};for i,r in ipairs(tbl.rows or{})do rows[i]={var=r.var,value=r.value,script=M.sourceKey(r.script)}end
          ev.mapScripts[name]=rows
        end
      end
      for i,coord in ipairs(entry.coords or{})do
        ev.coordEvents[i]=M.copy(coord);ev.coordEvents[i].scriptKey=M.sourceKey(coord.script)
      end
      bundle.events[id]=ev
    end
  end
  local header=pool.sourceInterface
  bundle.originalOperandsAvailable=header and header.schema==Header.SCHEMA and header.edition==edition or false
  return bundle
end
local function same(a,b)
  if type(a)~=type(b)then return false end
  if type(a)~='table'then return a==b end
  for k,v in pairs(a)do if not same(v,b[k])then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end
  return true
end
function M.validate(bundle)
  local record=records[bundle]
  if not record then return false,'replacement script bundles require the native overlay compiler'end
  if bundle.scripts~=record.scripts then return false,'replacement script lists require the native overlay compiler'end
  if Iteration.rawNext(bundle.scripts)~=nil then return false,'authored script lists require the native overlay compiler'end
  for k,v in pairs(record.cache)do
    if not same(v,record.expected[k])then return false,'edited script rows require the native overlay compiler'end
  end
  return true
end
return M
