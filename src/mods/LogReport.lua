-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Json=require('src.link.Json')
local L={MAX_BODY=65536,MAX_WIRE_BODY=512*1024}
function L.prepare(owner,body,opts)
  if type(body)~='string' or #body>L.MAX_BODY then return nil,'log body must be a string of at most 65536 bytes' end
  if opts~=nil and (type(opts)~='table' or getmetatable(opts)) then return nil,'invalid log options' end
  opts=opts or {}
  for key in pairs(opts)do if key~='format' then return nil,'unknown log option' end end
  local format=opts.format
  if format==nil then format='text' end
  if format~='text' and format~='json' then return nil,'log format must be text or json' end
  if type(owner)~='string' or #owner>256 then return nil,'invalid log owner' end
  if format=='text' then return body,'text/plain; charset=utf-8' end
  local value=Json.encode({ts=os.time(),mod=owner,format=format,body=body})
  if #value>L.MAX_WIRE_BODY then return nil,'encoded log exceeds byte limit' end
  return value,'application/json'
end
return L
