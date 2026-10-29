-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Host=require('src.core.HostShell')
local Json=require('src.link.Json')
local Http=require('src.net.BoundedHttp')
local spawn=Host.canSpawnProcess
Host.canSpawnProcess=function()return false end
local previous=love
local binary='a\0\255'
local calls,request,reply=0,nil,{status=200,bodyBase64='YQD/'}
love={system={},data={
  encode=function(kind,format,value)
    assert(kind=='string' and format=='base64' and value==binary)
    return 'YQD/'
  end,
  decode=function(kind,format,value)
    assert(kind=='string' and format=='base64' and value=='YQD/')
    return binary
  end,
}}
T.eq(Http.available(),false,'old mobile runtime does not advertise bounded HTTP')
love.system.boundedHttpVersion=function()return 2 end
love.system.httpRequestBounded=function(wire)
  calls=calls+1;request=Json.decode(wire)
  if type(reply)=='string' then return reply end
  return Json.encode(reply)
end
T.eq(Http.nativeAvailable(),false,'unknown wire version is not silently accepted')
love.system.boundedHttpVersion=function()return 1 end
T.eq(Http.available(),true,'matching native protocol enables the service without subprocesses')
T.eq(Http.request('https://fixture.invalid/get',{maxBytes=3}),binary,'native GET preserves binary bytes')
T.eq(request.method,'GET','GET dispatch reaches the native binding')
T.eq(request.maxBytes,3,'response bound reaches the native adapter')
T.eq(Http.request('https://fixture.invalid/log',{method='POST',body=binary,discardBody=true}),'','log success discards the native reply')
T.eq(request.bodyBase64,'YQD/','binary request uses the native wire codec')
T.eq(request.httpsOnly,true,'POST wire always enforces HTTPS')
T.eq(request.discardBody,true,'native adapter receives one-way mode')
local count=calls
T.eq(Http.request('http://fixture.invalid/log',{method='POST',body=binary}),nil,'insecure POST is refused before native submission')
T.eq(Http.request('file:///fixture'),nil,'non-HTTP target is refused before native submission')
T.eq(Http.request('https://fixture.invalid',{maxSeconds=0}),nil,'invalid deadline submits nothing')
T.eq(calls,count,'invalid requests never enter the platform transport')
reply={status=200,bodyBase64='YQD/'}
T.eq(Http.request('https://fixture.invalid',{maxBytes=2}),nil,'decoded binary cannot exceed the requested bound')
reply={status=200,bodyBase64='invalid'}
T.eq(Http.request('https://fixture.invalid'),nil,'malformed native Base64 is a failure')
reply={status=200,bodyBase64=string.rep('x',12)}
T.eq(Http.request('https://fixture.invalid',{maxBytes=3}),nil,'oversized wire body is rejected before decoding')
for _,bad in ipairs({'not JSON','[]',Json.encode({status=999}),Json.encode({status=200.5}),
  Json.encode({status=200,error='private platform diagnostic',bodyBase64='YQD/'})})do
  reply=bad
  local body,why=Http.request('https://fixture.invalid')
  T.eq(body,nil,'malformed or failed native response cannot become success')
  T.check(not tostring(why):find('private',1,true),'native diagnostics do not escape the bridge')
end
reply={status=307,bodyBase64='private redirect reply'}
local body,why,status=Http.request('https://fixture.invalid/log',{method='POST',body=binary,discardBody=true})
T.eq(body,nil,'one-way redirect remains a failure')
T.eq(status,307,'redirect status is retained without its body')
reply={status=204}
T.eq(Http.request('https://fixture.invalid/log',{method='POST',body=binary,discardBody=true}),'','empty accepted log response needs no Base64 field')
love=previous;Host.canSpawnProcess=spawn
T.finish('Bounded native HTTP wire')
