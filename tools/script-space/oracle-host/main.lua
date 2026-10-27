io.stdout:setvbuf('no')
local engine=assert(os.getenv('SCRIPT_INTERFACE_ENGINE'))
local reference=assert(os.getenv('SCRIPT_INTERFACE_REFERENCE'))
package.path=engine..'/?.lua;'..reference..'/?.lua;'..package.path
function love.errorhandler(e)print(debug.traceback(tostring(e),2));return function()return 1 end end
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function hash(s)return love.data.hash('sha256',s):gsub('.',function(c)return('%02x'):format(c:byte())end)end
local function same(a,b)
  if type(a)~=type(b)then return false end
  if type(a)~='table'then return a==b end
  for k,v in pairs(a)do if not same(v,b[k])then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end
  return true
end
local function canonical(v)
  if type(v)~='table'then return type(v)..':'..tostring(v)end
  local keys={};for k in pairs(v)do keys[#keys+1]=k end
  table.sort(keys,function(a,b)if type(a)==type(b)then return a<b end;return type(a)<type(b)end)
  local out={};for _,k in ipairs(keys)do out[#out+1]=canonical(k)..'='..canonical(v[k])..';'end
  return '{'..table.concat(out)..'}'
end
function love.load()
  local J=require('src.link.Json');local V=require('src.core.GameVersion')
  local out=assert(os.getenv('SCRIPT_INTERFACE_OUT'))
  local mode=assert(os.getenv('SCRIPT_INTERFACE_MODE'))
  local inputs=J.decode(read(out..'/inputs.json'))
  local Extractor=mode=='baseline'and assert(loadstring(read(out..'/baseline-extractor.lua'),'@baseline-extractor'))()
    or require('src.import.RomExtractorGen3')
  local Bundle=require('src.compat.gen1.ScriptBundle')
  local Disasm=require('src.core.game3.scripting.disasm')
  local common=require('src.core.game3.scripting.opcodes_common')
  local report={editions={},playerProfilesUsed=false,minimumFreeGiB=8}
  for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
    V.set(edition)
    local manifest=J.decode(read(engine..'/tools/rom_manifest_'..edition..'.json'))
    local raw=read(inputs[edition])
    assert(love.data.hash('sha1',raw):gsub('.',function(c)return('%02x'):format(c:byte())end)==manifest.romSha1)
    local function extract(class)
      local ex=class.new(raw,V.info(edition),manifest)
      ex.write=function()end
      ex:extractMaps();ex:extractMapScripts()
      return assert(ex._scriptPool)
    end
    local pool=extract(Extractor)
    if mode=='baseline'then
      local f=assert(io.open(out..'/baseline-'..edition..'.lua','w'))
      f:write(require('src.import.LuaWriter').encodeSplit(pool));f:close()
    else
    local old=assert(loadstring(read(out..'/baseline-'..edition..'.lua'),'@baseline-pool'))()
    assert(same(old.maps,pool.maps)and same(old.spawned,pool.spawned)and same(old.restored,pool.restored))
    local family=(edition=='firered'or edition=='leafgreen')and'firered'or edition=='emerald'and'emerald'or'ruby'
    local tail=require('src.core.game3.scripting.opcodes_'..(family=='firered'and'frlg'or family=='ruby'and'rs'or'emerald'))
    local battles=require('src.core.game3.constants.'..family..'.battle').byId.TRAINER_BATTLE_
    -- The reference table still declares the two removed x/y operands for
    -- later games. Their actual ScrCmd_hidemoneybox has both reads commented
    -- out; retain a visible, primary-source-backed correction in the oracle.
    local hiddenMoney=(family~='ruby')and{name='hidemoneybox',args={}}or nil
    -- The reference RS tail omits the third ignore byte of show/update.
    -- pokeruby/src/scrcmd.c reads all three; preserve the actual cartridge.
    local rsMoney={}
    if family=='ruby'then
      for op,name in pairs({[0x93]='showmoneybox',[0x95]='updatemoneybox'})do
        rsMoney[op]={name=name,args={{kind='byte'},{kind='byte'},{kind='byte'}}}
      end
    end
    local set={get=function(_,op)if op==0x94 and hiddenMoney then return hiddenMoney end;return rsMoney[op]or tail[op]or(not(family=='ruby'and op>0xc5)and common[op]or nil)end,
      trainerBattleType=function(_,id)local name=battles[id];return name and name:gsub('^TRAINER_BATTLE_','')end}
    local count,scripts,specials,trainers=0,0,0,0
    local differences={};local nativeOnly={}
    for key,rows in pairs(pool.scripts)do
      scripts=scripts+1;assert(old.scripts[key]and #old.scripts[key]==#rows,'native list changed')
      for i,ir in ipairs(rows)do
        local previous=old.scripts[key][i]
        for k=1,math.max(#ir,#previous)do assert(same(ir[k],previous[k]),'native operand changed')end
        local bytes={ir.sourceOpcode};for n=1,#ir.sourceBytes do bytes[#bytes+1]=ir.sourceBytes:byte(n)end
        assert(raw:sub(ir.sourceAddress-0x08000000+1,ir.sourceAddress-0x08000000+#bytes)==string.char(unpack(bytes)),'raw opcode payload differs')
        local expected,at=Disasm.decodeOne(bytes,1,set)
        local actual=Bundle.row(ir,edition)
        if expected.op=='unknown'then nativeOnly[ir[1]]=true
        else
          count=count+1
          local function restore(v)
            if type(v)=='string'and v:match('^g3:%x+$')then return tonumber(v:sub(4),16)end
            return v
          end
          for k,v in pairs(expected)do
            if not same(restore(actual[k]),v)then
              if #differences<20 then differences[#differences+1]={script=key,row=i,field=tostring(k),op=expected.op,want=tostring(v),got=tostring(actual[k])}end
            end
          end
          if at~=#bytes+1 and #differences<20 then differences[#differences+1]={script=key,row=i,op=expected.op,field='payload-length',want=at-1,got=#bytes}end
        end
        if ir[1]=='special'or ir[1]=='specialvar'then specials=specials+1 end
        if ir[1]=='trainerbattle'then trainers=trainers+1 end
      end
    end
    local module=require('src.import.LuaWriter').encodeSplit(pool)
    local decoded=assert(loadstring(module,'@generated/map_scripts.lua'))()
    assert(same(pool,decoded),'additive metadata did not round-trip')
    report.editions[edition]={scripts=scripts,sourceRows=count,specials=specials,trainers=trainers,
      nativeOperandsUnchanged=true,cacheRoundTrip=true,moduleBytes=#module,differences=differences,nativeOnly=nativeOnly,
      referenceCorrections=family=='ruby'and{'showmoneybox: 3 byte reads','updatemoneybox: 3 byte reads'}or{'hidemoneybox: no byte reads'},
      originalFailureCount=old.info.failureCount,currentFailureCount=pool.info.failureCount}
    local f=assert(io.open(out..'/oracle.json','w'));f:write(J.encode(report));f:close()
    print(edition,scripts,count,specials,trainers,#differences)
    assert(#differences==0,'original operand projection differs; inspect oracle.json')
    end
    collectgarbage('collect')
  end
  love.event.quit(0)
end
