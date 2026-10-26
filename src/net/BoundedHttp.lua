-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Engine-only request bridge. The public mod service retains URL ownership.
local Host=require('src.core.HostShell')
local Json=require('src.link.Json')
local H={MAX_BODY=512*1024,MAX_BYTES=16*1024*1024,MAX_SECONDS=30}
function H.nativeAvailable()
  local system=love and love.system
  if not (system and type(system.boundedHttpVersion)=='function' and type(system.httpRequestBounded)=='function') then return false end
  local ok,version=pcall(system.boundedHttpVersion)
  return ok and version==1 and love.data and type(love.data.encode)=='function' and type(love.data.decode)=='function' or false
end
function H.available()return Host.canSpawnProcess() or H.nativeAvailable()end
function H.request(url,options)
  local o=options or {};local method=o.method or 'GET'
  if method~='GET' and method~='POST' then return nil,'unsupported HTTP method' end
  if type(url)~='string' or #url>8192 or url:find('[%z%c%s]') or not url:lower():match('^https?://[^/?#]+') then return nil,'invalid HTTP URL' end
  if (o.httpsOnly or method=='POST') and not url:lower():match('^https://') then return nil,'HTTPS required' end
  local body=o.body
  if method=='POST' and (type(body)~='string' or #body>H.MAX_BODY) then return nil,'POST body exceeds byte limit' end
  local seconds=tonumber(o.maxSeconds) or 20;local bytes=tonumber(o.maxBytes) or 4*1024*1024
  if seconds~=seconds or bytes~=bytes or seconds<=0 or bytes<1 then return nil,'invalid HTTP bounds' end
  seconds=math.min(seconds,H.MAX_SECONDS);bytes=math.floor(math.min(bytes,H.MAX_BYTES))
  if Host.canSpawnProcess() then
    local opts={userAgent=o.userAgent,accept=o.accept,maxSeconds=seconds,maxBytes=bytes,
      httpsOnly=o.httpsOnly,contentType=o.contentType,errorPath=o.errorPath}
    local value,why,status
    if method=='POST' then value,why,status=Host.httpPostBounded(url,body,opts)
    else value,why,status=Host.httpGetBounded(url,opts) end
    if o.discardBody and value~=nil then value='' end
    return value,why,status
  end
  if not H.nativeAvailable() then return nil,'bounded native HTTP transport unavailable' end
  local req={boundedVersion=1,method=method,url=url,userAgent=o.userAgent or 'gen2recomp',
    accept=o.accept or '*/*',maxSeconds=seconds,maxBytes=bytes,
    httpsOnly=o.httpsOnly==true or method=='POST',discardBody=o.discardBody==true,
    contentType=o.contentType or 'text/plain; charset=utf-8'}
  if body then req.bodyBase64=love.data.encode('string','base64',body) end
  local ok,wire=pcall(love.system.httpRequestBounded,Json.encode(req))
  if not ok or type(wire)~='string' or #wire>math.ceil(bytes*4/3)+8192 then return nil,'native HTTP response failed' end
  local decoded,response=pcall(Json.decode,wire)
  if not decoded or type(response)~='table' then return nil,'invalid native HTTP response' end
  local status=response.status
  if type(status)~='number' or status%1~=0 or status<100 or status>599 then status=nil end
  if response.error or not status or status<200 or status>=300 then return nil,'native HTTP request failed',status end
  if o.discardBody then return '',nil,status end
  if type(response.bodyBase64)~='string' or #response.bodyBase64>math.ceil(bytes/3)*4 then return nil,'native HTTP response exceeds byte limit',status end
  local valid,value=pcall(love.data.decode,'string','base64',response.bodyBase64)
  if not valid or #value>bytes then return nil,'invalid native HTTP body',status end
  return value,nil,status
end
return H
