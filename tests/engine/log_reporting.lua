-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Manifest=require('src.mods.Manifest')
local Net=require('src.mods.Net')
local Fetch=require('src.net.Fetch')
local Transport=require('src.net.BoundedHttp')
local Log=require('src.mods.LogReport')
local Json=require('src.link.Json')
local function raw(extra)
  local m={id='logmod',name='Log mod',version='1.0.0',api=2,entry='main.lua',permissions={'network'},log_url='https://logs.example.invalid/ingest'}
  for k,v in pairs(extra or {})do m[k]=v end;return m
end
T.eq(Manifest.validate(raw()).log_url,'https://logs.example.invalid/ingest','manifest retains fixed destination')
for _,url in ipairs({'http://logs.invalid','https://','file:///log','https://log.invalid\nX: y',false})do
  T.raises(function()Manifest.validate(raw({log_url=url}))end,'log_url','invalid destination rejected before entry')
end
T.raises(function()Manifest.validate(raw({permissions={}}))end,'network','strict declaration needs network grant')
T.eq(Manifest.validate(raw({api=1,permissions={}})).log_url,nil,'legacy warning cannot retain an ungranted endpoint')
local body='a\0\255\r\n`literal` $(literal) "quote"'
T.eq(Log.prepare('a',body),body,'text preserves arbitrary bytes')
T.eq(Log.prepare('a',string.rep('x',65536)),string.rep('x',65536),'exact input limit accepted')
T.eq(Log.prepare('a',string.rep('x',65537)),nil,'oversized input refused')
for _,opts in ipairs({false,'json',{format=false},{format=1},{format='xml'},{url='https://other.invalid'},
  {headers={}},{maxSeconds=99},setmetatable({},{__index=function()error('must not run')end})})do
  T.eq(Log.prepare('a','x',opts),nil,'closed option contract rejects unknown switches and values')
end
local encoded,mime=Log.prepare('a','hello',{format='json'});local envelope=Json.decode(encoded)
T.eq(mime,'application/json','JSON MIME fixed');T.eq(envelope.mod,'a','envelope attributes owner')
T.eq(envelope.body,'hello','envelope retains body');T.eq(envelope.format,'json','envelope format')
T.eq(type(envelope.ts),'number','envelope captures one timestamp')
local original,available={},Transport.available
for _,name in ipairs({'get','postLog','poll','cancel','release','isPending'})do original[name]=Fetch[name]end
Transport.available=function()return true end
local calls,jobs,nextId={},{},0
local function start(method,url,payload,opts)
  nextId=nextId+1;jobs[nextId]={status='pending'}
  calls[#calls+1]={method=method,url=url,body=payload,opts=opts,id=nextId};return nextId
end
Fetch.get=function(url,opts)return start('GET',url,nil,opts)end
Fetch.postLog=function(url,payload,opts)return start('POST',url,payload,opts)end
Fetch.poll=function(id)return jobs[id] or {status='error'}end
Fetch.cancel=function(id)if jobs[id]then jobs[id]={status='cancelled'}end end
Fetch.release=function(id)jobs[id]=nil end
Fetch.isPending=function(id)return jobs[id] and jobs[id].status=='pending'end
local loader={};local mod={manifest=Manifest.validate(raw())}
local api=Net.forMod(loader,mod);local send=Net.logReporter(loader,mod)
mod.manifest.log_url='https://changed.invalid'
local handle=assert(send(nil,body))
local call=calls[#calls]
T.eq(call.url,'https://logs.example.invalid/ingest','runtime manifest mutation cannot choose another destination')
T.eq(call.body,body,'worker receives literal body bytes');T.eq(call.method,'POST','log uses POST')
T.eq(call.opts.userAgent,'gen2recomp-mod/logmod','caller identity cannot be overridden')
T.eq(call.opts.boundedHttpsGet,1,'HTTPS constraint is mandatory')
jobs[call.id]={status='ok',body='server private body',err='server diagnostic',raw='server private body',httpStatus=204,progress=1}
local state=api:poll(handle)
T.eq(state.status,'ok','accepted transfer result');T.eq(state.body,nil,'reply body never reaches mod')
T.eq(state.raw,nil,'one-way result is a closed public shape');T.eq(state.err,nil,'success cannot leak arbitrary diagnostics')
T.eq(state.httpStatus,204,'HTTP status remains observable');api:release(handle)
T.eq(next(loader.netOneWay.logmod),nil,'release removes private log-handle metadata')
local other=Net.forMod(loader,{manifest={id='other',permissionSet={network=true}}})
handle=assert(send(nil,'failure'));call=calls[#calls]
jobs[call.id]={status='error',body='server secret',err='server secret'}
T.eq(api:poll(handle).err,'log upload failed','remote failures have a stable diagnostic')
T.eq(other:poll(handle).status,'error','a log handle belongs to its own mod')
api:release(handle)
local count=#calls
T.eq(send(nil,'x',{url='https://override.invalid'}),nil,'per-call destination override refused')
T.eq(#calls,count,'invalid options submit no request')
local held={}
for i=1,3 do held[i]=assert(api:get('https://data.invalid'))end
held[4]=assert(send(nil,'one more'))
T.eq(send(nil,'over quota'),nil,'GET and log share the per-mod ceiling')
Net.releaseAll(loader,'logmod')
T.eq(api:poll(held[4]).status,'error','unload invalidates log requests')
local missing=Net.logReporter(loader,{manifest={id='none',permissionSet={network=true}}})
T.eq(missing(nil,'x'),nil,'missing destination is a normal refusal')
local denied=Net.logReporter(loader,{manifest={id='denied',permissionSet={}}})
T.raises(function()denied(nil,'x')end,'network','ungranted call names its permission')
Transport.available=function()return false end
T.eq(send(nil,'offline'),nil,'unsupported native transport does not advertise a successful send')
Transport.available=function()return true end
local files={['mods/logmod/manifest.json']=Json.encode(raw()),['mods/logmod/main.lua']=[[
local mod=...;mod.exports.handle=assert(mod:postLog('from actual loader'));mod.exports.fetch=mod.fetch
]]}
local loaded=T.sdk.loadMod('mods/logmod',{fs=T.sdk.memfs(files)})
T.eq(loaded.mod.state,'loaded','actual mod loader installs postLog')
T.eq(calls[#calls].body,'from actual loader','actual entry reaches the native transport facade')
loaded.release();Net.unloadAll()
Transport.available=available;for name,method in pairs(original)do Fetch[name]=method end
T.finish('Native fixed-destination log reporting')
