package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local function module()return assert(loadfile('src/core/JitArena.lua'))()end
local function fake(os,arch,enabled)
 local calls={}
 local runtime={os=os,arch=arch,status=function()return enabled end,
  flush=function()calls[#calls+1]='flush'end}
 local options={start=function(...)calls[#calls+1]={...}end}
 return runtime,options,calls
end
for _,platform in ipairs{{'Windows','x64',true},{'Linux','arm64',true},{'OSX','x64',true},{'iOS','arm64',false},{'OSX','arm64',false}}do
 local runtime,options,calls=fake(unpack(platform))
 T.eq(module().configure(runtime,options),false,'other runtime policy is retained')
 T.eq(#calls,0,'other platforms/disabled JIT receive no options or flush')
end
do
 local runtime,options,calls=fake('OSX','arm64',true)
 local m=module()
 T.eq(m.configure(runtime,options),true)
 T.eq(#calls,2);T.eq(calls[1][1],'maxtrace=8192')
 T.eq(calls[1][2],'sizemcode=16384');T.eq(calls[1][3],'maxmcode=16384')
 T.eq(calls[2],'flush','new allocation policy precedes retiring the boot-time area')
 T.eq(m.status.areaKiB,16384);T.eq(m.status.maxCodeKiB,16384)
 T.eq(m.configure(runtime,options),true);T.eq(#calls,2,'reconfiguration cannot flush a running session')
end
do
 local runtime,options,calls=fake('OSX','arm64',true)
 options.start=function()error('unsupported option')end
 local ok,why=module().configure(runtime,options)
 T.eq(ok,false);T.check(why:find('unsupported option',1,true)~=nil)
 T.eq(#calls,0,'failed option setup never flushes the existing runtime')
 T.eq(module().configure(runtime,false),false,'missing optimizer remains optional')
 runtime.flush=nil
 T.eq(module().configure(runtime,options),false,'incomplete control cannot partially change options')
end
do
 local saved=os.getenv
 for _,value in ipairs{'0','maxtrace=2000,hotloop=100'}do
  os.getenv=function(key)if key=='POKEPORT_JIT_OPT'then return value end return saved(key)end
  local runtime,options,calls=fake('OSX','arm64',true)
  T.eq(module().configure(runtime,options),false,'explicit JIT policy wins during early configuration')
  T.eq(#calls,0,'explicit policy receives neither implicit options nor flush')
 end
 os.getenv=saved
end
T.eq(package.loaded['src.core.Game'],nil,'early JIT policy cannot bootstrap a game')
T.finish('native bounded Apple-silicon JIT arena')
