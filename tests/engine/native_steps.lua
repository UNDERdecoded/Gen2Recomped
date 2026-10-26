-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local J=require('src.core.StepJournal')
local Steps=require('src.mods.Steps')
local Json=require('src.link.Json')
local files={}
local fs=T.sdk.memfs(files)
local baseInfo,baseWrite=fs.getInfo,fs.write
function fs.getInfo(path,kind)
  local info=baseInfo(path)
  if info and info.type=='file' then info.size=#files[path] end
  if kind and info and info.type~=kind then return nil end
  return info
end
function fs.write(path,bytes)
  if fs.failWrite then return nil,'injected full disk' end
  return baseWrite(path,bytes)
end
function fs.rename(source,target)
  if fs.failRename then return nil,'injected publication failure' end
  if not files[source] then return nil,'missing staging file' end
  files[target],files[source]=files[source],nil;return true
end
function fs.remove(path)files[path]=nil;return true end
local oldFs,oldSystem=love.filesystem,love.system
love.filesystem=fs
local calls=0
love.system={syncHealthSteps=function()calls=calls+1;return true end,stepJournalVersion=function()return 1 end}
local function snapshot(total,epoch)
  return {version=1,source='healthkit',epoch=epoch or 'epoch1',total=total,
    from='2026-10-25T10:00:00.000Z',to='2026-10-25T11:00:00.000Z',anchor=1000}
end
local function publish(total,epoch)files[J.FILE]=Json.encode(snapshot(total,epoch))end
local function mod(id,allowed)return {manifest={id=id,permissionSet={steps=allowed==true}}}end
local loader={}
publish(123)
local a=Steps.forMod(loader,mod('a',true))
local b=Steps.forMod(loader,mod('b',true))
T.check(a:available(),'versioned native bridge is available')
T.eq(calls,0,'availability never prompts for OS consent')
T.eq(a:sync(),true,'explicit sync calls the native bridge');T.eq(calls,1,'one explicit request')
local first=a:poll();T.eq(first.steps,123,'first consumer gets native delivery')
first.steps=999
T.eq(b:poll().steps,123,'second mod independently receives the same walk')
T.eq(a:poll(),nil,'a receipt prevents duplicate delivery')
T.check(files[J.FILE]~=nil,'consumers never delete the native journal')
publish(200)
T.eq(a:poll().steps,77,'only the new cumulative delta is delivered')
T.eq(b:poll().steps,77,'other consumers retain independent deltas')
local replacement=Steps.forMod(loader,mod('a',true))
T.eq(a:available(),false,'replacing a facade retires the old one')
T.raises(function()a:poll()end,'retired','stale facade cannot consume a replacement delivery')
T.eq(replacement:poll(),nil,'reload keeps the durable receipt')
local denied=Steps.forMod(loader,mod('denied',false))
T.eq(denied:available(),false,'permissionless probing is safe')
for _,method in ipairs({'sync','poll'})do
  local ok,why=pcall(denied[method],denied)
  T.eq(ok,false,'ungranted operation is refused');T.check(tostring(why):find('steps',1,true),'denial names the permission')
end
local modern=love.system.stepJournalVersion
love.system.stepJournalVersion=nil
T.eq(replacement:available(),false,'old unversioned native binaries cannot advertise the journal protocol')
T.eq(replacement:sync(),false,'unsupported host does not start a sensor read')
T.eq(replacement:poll(),nil,'unsupported host is probe-safe')
love.system.stepJournalVersion=modern
publish(300)
fs.failRename=true
local value,why=replacement:poll()
T.eq(value,nil,'failed receipt publication delivers nothing');T.check(why~=nil,'publication failure has a diagnostic')
fs.failRename=false
T.eq(replacement:poll().steps,100,'failed publication leaves delivery available')
fs.failWrite=true;publish(350)
T.eq(replacement:poll(),nil,'full disk does not consume delivery')
fs.failWrite=false;T.eq(replacement:poll().steps,50,'delivery survives a write failure')
publish(349)
local backwards,err=replacement:poll()
T.eq(backwards,nil,'same-epoch backwards snapshots are refused');T.check(err:find('backwards',1,true),'counter regression diagnosed')
publish(110001,'newEpoch')
for _,count in ipairs({50000,50000,10001})do T.eq(replacement:poll().steps,count,'bounded deliveries retain the complete backlog')end
T.eq(replacement:poll(),nil,'drained backlog does not replay')
for _,bad in ipairs({-1,1.5,1e100,'42',false})do
  local state=snapshot(0);state.total=bad;files[J.FILE]=Json.encode(state)
  T.eq(J.read(fs),nil,'invalid cumulative total is refused')
end
local state=snapshot(1);state.source='other';files[J.FILE]=Json.encode(state)
T.eq(J.read(fs),nil,'unknown producer is refused')
files[J.FILE]=string.rep(' ',J.MAX_BYTES+1)
T.eq(J.read(fs),nil,'oversized native input is rejected before decode')
files[J.FILE]='{unfinished';T.eq(J.read(fs),nil,'truncated native input is refused')
local goodReceipt=files[J.RECEIPTS]
files[J.RECEIPTS]='{unfinished';publish(110002,'newEpoch')
T.eq(replacement:poll(),nil,'corrupt receipts fail closed instead of replaying historical steps')
files[J.RECEIPTS]=goodReceipt
T.eq(replacement:poll().steps,1,'repaired receipts retain their exact cursor')
Steps.retire(loader)
T.eq(b:available(),false,'loader retirement disables every facade')
-- The real native walker credits and persists its cursor in the same state.
local W=require('src.pokewalker.Walker')
local WalkerSteps=require('src.pokewalker.WalkerSteps')
local walker=W.newState();W.live=walker
publish(123,'walkerEpoch')
fs.failWrite=true
T.eq(WalkerSteps.pump(walker,{}),123,'walker independently receives the original full delivery')
T.eq(walker.lifetimeSteps,123,'real walker rules credit the steps')
T.eq(WalkerSteps.pump(walker,{}),0,'failed persistence does not double live credits')
fs.failWrite=false
T.eq(WalkerSteps.pump(walker,{}),0,'retry only persists the existing credit')
local restored=W.reload()
T.eq(restored.lifetimeSteps,123,'credit survives actual save reload')
T.eq(restored.stepsJournal.total,123,'receipt survives with the credited walker state')
T.eq(WalkerSteps.pump(restored,{}),0,'restart does not credit the same walk again')
publish(223,'walkerEpoch');fs.failWrite=true
WalkerSteps.pump(restored,{})
fs.failWrite=false
local afterCrash=W.reload()
T.eq(afterCrash.lifetimeSteps,123,'a simulated pre-commit restart loads the prior complete walker state')
T.eq(WalkerSteps.pump(afterCrash,{}),100,'uncommitted steps remain in the native journal')
T.eq(afterCrash.lifetimeSteps,223,'recovered persisted total has no missing or duplicate credit')
files[J.FILE]=nil;files[WalkerSteps.FILE]=Json.encode({steps=17})
T.eq(WalkerSteps.pump(afterCrash,{}),0,'new native hosts own pending-file migration before the first journal')
T.check(files[WalkerSteps.FILE]~=nil,'Lua cannot race the native legacy migration')
love.system.stepJournalVersion=nil
T.eq(WalkerSteps.pump(afterCrash,{}),17,'old native hosts retain the legacy walker path')
T.eq(files[WalkerSteps.FILE],nil,'legacy pending file keeps its existing consume behavior')
love.system.stepJournalVersion=modern
-- The actual mod loader accepts the permission and provides the public seam.
local manifest={id='stepprobe',name='Step probe',version='1.0.0',entry='main.lua',api=2,permissions={'steps'}}
local modFs=T.sdk.memfs({['mods/stepprobe/manifest.json']=Json.encode(manifest),
 ['mods/stepprobe/main.lua']=[[local mod=...;mod.exports.steps=type(mod.steps.poll)]]})
local loaded=T.sdk.loadMods({'mods/stepprobe'},{fs=modFs,dev=false})
T.eq(loaded.mods.stepprobe.state,'loaded','actual loader accepts the steps permission')
T.eq(loaded.loader.exports.stepprobe.steps,'function','actual loader installs the step facade')
loaded.release();Steps.unloadAll()
love.filesystem,love.system=oldFs,oldSystem
T.finish('Native step journal and independent deliveries')
