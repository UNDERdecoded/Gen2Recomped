package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Manifest=require('src.mods.Manifest')
local Targets=require('src.mods.ModTargets')
local Versions=require('src.core.GameVersion')
local Version=require('src.core.Version')
local Json=require('src.link.Json')
local SaveData=require('src.core.SaveData')
local Manager=require('src.mods.ManagerState')
local Launcher=require('src.mods.LauncherMods')
local Index=require('src.mods.ModIndex')
local savedVersion,savedEngine=Versions.get(),Version.engine
Version.engine='1.5.0'
local function raw(id,extra)
  local out={id=id,name=id,version='1.0.0',api=2,entry='main.lua',games={'all'}}
  for k,v in pairs(extra or {}) do out[k]=v end
  return out
end
local function boot(version,definitions,options)
  Versions.set(version)
  local files,paths={},{}
  for id,extra in pairs(definitions) do
    local path='mods/'..id;paths[#paths+1]=path
    files[path..'/manifest.json']=Json.encode(raw(id,extra))
    files[path..'/main.lua']='local mod=...;mod.exports.executed=true'
  end
  local fs=T.sdk.memfs(files)
  if options then SaveData.saveOptions(options,fs) end
  return T.sdk.loadMods(paths,{fs=fs,dev=false})
end
local function parsed(extra)return Manifest.validate(raw('consumer',extra))end

local m=parsed({dependencies={'plain','ranged@^1.2.0#owner/library',
  {id='table',version='>=2.0.0',repo='https://github.com/owner/table.git',game=' BLUE ',game_version='<2.0.0'},
  'fallback'},dependency_sources={fallback='owner/fallback'}})
T.eq(m.dependencySpecs[1].id,'plain','original bare ID retained')
T.eq(m.dependencySpecs[2].range,'^1.2.0','range and source split independently')
T.eq(m.dependencySpecs[2].github,'owner/library','inline repo normalized')
T.eq(m.dependencySpecs[3].github,'owner/table','object repo normalized')
T.same(m.dependencySpecs[3].games,{'blue'},'object edition scope normalized')
T.eq(m.dependencySpecs[4].github,'owner/fallback','source map fallback normalized')
T.check(Targets.specApplies(m.dependencySpecs[3],'blue',1,'1.5.0'),'matching edition and engine apply')
T.check(not Targets.specApplies(m.dependencySpecs[3],'red',1,'1.5.0'),'same generation does not widen exact edition')
T.check(not Targets.specApplies(m.dependencySpecs[3],'blue',1,'2.0.0'),'nonmatching engine range is false')
T.check(Targets.specApplies(m.dependencySpecs[3],nil,1,'1.5.0'),'generation-only context retains compatible edge')
T.eq(parsed({dependencies={'lib#https://evil.invalid/pkg'}}).dependencySpecs[1].github,nil,'unsafe repository hint discarded')
for _,spec in ipairs({{id='bad/id'},{id='lib',range=false},{id='lib',games=false},
  {id='lib',games={}},{id='lib',games={'unknown'}},{id='lib',games={[2]='blue'}},
  {id='lib',game_version='broken'},'lib@broken','lib@','lib##owner/repo'}) do
  T.raises(function()parsed({dependencies={spec}})end,nil,'invalid dependency rejected')
end
T.raises(function()parsed({dependencies={[2]='lib'}})end,nil,'sparse dependency arrays rejected')

for _,version in ipairs(Versions.ORDER) do
  local run=boot(version,{consumer={dependencies={{id='missing',games='blue'}}},independent={}})
  local applies=version=='blue'
  T.eq(run.loader.exports.consumer~=nil,not applies,version..': inactive missing dependency does not block')
  T.eq(#run.errors,applies and 1 or 0,version..': only applicable dependency produces an error')
  T.check(run.loader.exports.independent.executed,version..': unrelated mod still runs')
end
for _,version in ipairs({'red','blue'}) do
  local scoped={{id='b',games='blue'}}
  local run=boot(version,{a={dependencies=scoped},b={dependencies={{id='a',games='blue'}}}})
  T.eq(run.loader.exports.a~=nil,version~='blue',version..': cycle detector uses applicable edges')
  run=boot(version,{a={conflicts=scoped},b={}})
  T.eq(run.loader.exports.a~=nil,version~='blue',version..': conflict detector uses applicable edges')
end
local run=boot('blue',{consumer={dependencies={{id='missing',game_version='>=2.0.0'}}}})
T.check(run.loader.exports.consumer.executed,'inactive engine-scoped requirement does not block runtime')
run=boot('blue',{consumer={dependencies={{id='missing',game_version='<2.0.0'}}}})
T.eq(run.mods.consumer.state,'blocked_dependency','matching engine-scoped requirement enforced')
local function order(options)
  return table.concat(boot('red',{a={optional_dependencies=options},z={}}).loader.order,',')
end
T.eq(order({{id='z',games='blue'}}),'a,z','out-of-scope optional edge does not reorder')
T.eq(order({{id='z',games='red'}}),'z,a','in-scope optional edge orders dependency first')
T.eq(order({'z@>=2.0.0'}),'a,z','incompatible optional version does not reorder')

local consumer=parsed({dependencies={{id='dep',games='blue',github='owner/dep'}},conflicts={{id='rival',games='blue'}}})
local dep=Manifest.validate(raw('dep'))
local rival=Manifest.validate(raw('rival'))
local mods={consumer=consumer,dep=dep,rival=rival}
local enable=Manager.resolveToggle(mods,'consumer',true,{rival=true},'red')
T.eq(#enable.alsoEnable,0,'manager does not enable irrelevant dependency')
T.eq(#enable.conflicts,0,'manager ignores irrelevant conflict')
enable=Manager.resolveToggle(mods,'consumer',true,{},'blue')
T.same(enable.alsoEnable,{'dep'},'manager enables applicable dependency')
local disable=Manager.resolveToggle(mods,'dep',false,{consumer=true,dep=true},'red')
T.eq(#disable.alsoDisable,0,'reverse disable ignores irrelevant edge')
disable=Manager.resolveToggle(mods,'dep',false,{consumer=true,dep=true},'blue')
T.same(disable.alsoDisable,{'consumer'},'reverse disable follows applicable edge')
local report=Launcher.checkDependencies(consumer,{mods={}},'red',{})
T.eq(#report.deps,0,'launcher review ignores irrelevant requirement')
report=Launcher.checkDependencies(consumer,{mods={}},'blue',{})
T.check(report.hasIssues,'launcher reports missing applicable requirement')
T.eq(report.deps[1].safeUrl,'https://github.com/owner/dep','validated hint available for source review')
report=Launcher.checkDependencies(consumer,{mods={dep=false}},'blue',{dep})
T.eq(report.deps[1].status,'disabled','launcher distinguishes disabled dependency')
local rows=Launcher.deriveList({consumer},{mods={}},'red')
T.eq(rows[1].status,'ok','launcher status agrees with runtime outside dependency scope')
rows=Launcher.deriveList({consumer},{mods={}},'blue')
T.eq(rows[1].status,'warn','launcher status flags applicable missing dependency')
local entry={dependencies={{id='dep',games='blue'}}}
T.eq(#Index.compatIssues(entry,{gameVersion='red',engineVersion='1.5.0'}),0,'catalogue warning respects exact edition')
T.eq(#Index.compatIssues(entry,{gameVersion='blue',engineVersion='1.5.0'}),1,'catalogue sees applicable object dependency')
T.eq(#Index.compatIssues({dependencies={'dep@^1.0.0#owner/dep'}},{installed={dep='1.0.0'}}),0,'catalogue does not include source hint in ID')
Version.engine=savedEngine;Versions.set(savedVersion)
T.finish('Scoped dependency contracts')
