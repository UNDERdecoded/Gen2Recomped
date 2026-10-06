package.path='./?.lua;'..package.path
love=require('tests.love_stub')
love.system={getOS=function()return 'Android' end}
local T=require('tests.harness').suite('Android import recovery and worker failures')
local R=require('src.import.ImportRecovery')
local rec=R.begin('picked_rom.gb','emerald','/storage/emulated/0/Games/Gen2Recomp')
R.stage('Gen3 constants','Encoding intro/finale.png')
package.loaded['src.import.ImportRecovery']=nil
R=require('src.import.ImportRecovery')
T.eq(R.load().stage,'Gen3 constants','crash stage survives a fresh Lua state')
T.eq(R.load().root,rec.root,'actual selected folder survives restart')
T.eq(R.load().operation,'Encoding intro/finale.png','native operation survives restart')
R.fail('worker failure')
T.eq(R.load().error,'worker failure','handled errors also stop automatic retries')
T.eq(R.load().stage,'Gen3 constants','foreground error keeps latest worker checkpoint')
R.finish();T.eq(R.load(),nil,'successful or explicit retry clears recovery')
love.filesystem.write(R.PATH,'corrupted record')
T.eq(R.load(),nil,'malformed recovery does not gate startup')
R.finish()

local Task=require('src.import.RomImportTask')
local function make(messages,running,why)
 return setmetatable({channel={pop=function() return table.remove(messages,1) end},
  thread={getError=function() return why end,isRunning=function() return running end}},Task)
end
local task=make({},false)
T.eq(task:poll().kind,'error','silently stopped worker reports an error')
T.eq(task:poll(),nil,'worker failure reported once')
task=make({},true);T.eq(task:poll(),nil,'live idle worker stays pending')
task=make({},false,'native Lua thread error');T.eq(task:poll().error,'native Lua thread error','thread error surfaced')
task=make({{kind='progress'},{kind='complete'}},false)
T.eq(task:poll().kind,'progress','queued progress drained after thread stops')
T.eq(task:poll().kind,'complete','successful completion delivered')
T.eq(task:poll(),nil,'completed worker never becomes a false error')
local published=false
task=setmetatable({channel={pop=function() if published then published=false;return {kind='complete'} end end},
 thread={getError=function()end,isRunning=function() published=true;return false end}},Task)
T.eq(task:poll().kind,'complete','completion published during running-state check wins')

local C=require('src.import.CacheFs')
local root=C.root;C.root=function()return '/mock-root' end
local open=io.open
io.open=function()return {write=function()return nil,'disk full' end,close=function()return true end} end
local ok,why=C.write('test','data');T.eq(ok,false,'failed custom-folder write is rejected');T.eq(why,'disk full','write failure reason retained')
io.open=function()return {write=function()return true end,close=function()return nil,'flush failed' end} end
ok,why=C.write('test','data');T.eq(ok,false,'failed close is rejected');T.eq(why,'flush failed','flush failure reason retained')
io.open=open;C.root=root

-- Exercise the production worker before its destructive cache cleanup.
local removed=0
local savedC=package.loaded['src.import.CacheFs']
package.loaded['src.import.CacheFs']={write=function()return false,'permission denied' end,
 removeTree=function()removed=removed+1 end}
local message
for _,name in ipairs({'filesystem','data','image','timer','system'})do package.loaded['love.'..name]=love[name] or {} end
assert(loadfile('src/import/rom_import_worker.lua'))({action='extract',clear=true,prefix='emerald/',module='unused'},
 {push=function(_,m)message=m end})
T.eq(message.kind,'error','permission failure returned through worker channel')
T.check(message.error:find('not writable',1,true)~=nil,'storage failure explains itself')
T.eq(removed,0,'storage failure cannot clear an existing cache')
package.loaded['src.import.CacheFs']=savedC

local I=require('src.import.RomImporter')
local V=require('src.core.GameVersion')
local ready={};for _,id in ipairs(V.ORDER)do ready[id]=true end
R.begin('picked_rom.gb','emerald','/mock-root');R.stage('Gen3 constants')
local oldReport=I.readyReport
I.readyReport=function()return {ok=false,why='test empty cache'}end
local new=I.new(nil,{launcher=true})
T.eq(new.workState,'error','fresh launcher restores the interruption screen')
T.eq(new.tab,'emerald','fresh launcher selects interrupted game')
T.check(new.detail:find('Gen3 constants',1,true)~=nil,'fresh launcher displays crash stage')
T.eq(new.probeTask,nil,'fresh launcher does not start a verification worker')
T.eq(new.worker,nil,'fresh launcher does not automatically resume extraction')
I.readyReport=oldReport
local launcher=setmetatable({android=true,ready=ready,failedRoms={['picked_rom.gb']=true},workState='error',interruptedImport=R.load()},{__index=I})
love.filesystem.write('pick_done.flag','picked_rom.gb')
launcher:focus(true)
T.check(launcher.failedRoms['picked_rom.gb'],'stale picker completion cannot restart a crashed import')
T.eq(launcher.workState,'error','focus leaves recovery screen active')
launcher.android=false;love.system.showFilePicker=function()return true end
launcher:choose('emerald')
T.eq(launcher.interruptedImport,nil,'manual Import acknowledges interruption')
T.eq(launcher.failedRoms['picked_rom.gb'],nil,'manual retry can reuse the original picked file')
T.eq(R.load(),nil,'manual retry clears durable automatic-retry gate')
T.finish()
