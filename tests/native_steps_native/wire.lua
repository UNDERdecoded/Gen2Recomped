-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local J=require('src.core.StepJournal')
for index,expected in ipairs({75027,75132})do
  local file=assert(io.open(assert(arg[index]),'rb'))
  local body=file:read('*a');file:close()
  local fs={getInfo=function()return {type='file',size=#body}end,
    read=function(_,limit)return body:sub(1,limit)end}
  local snapshot,why=J.read(fs)
  T.check(snapshot~=nil,'actual native producer JSON is accepted: '..tostring(why))
  T.eq(snapshot.total,expected,'native count reaches the actual Lua schema without rounding')
  T.eq(snapshot.source,index==1 and 'healthkit' or 'android-counter','native source identity retained')
  local count,cursor=0,nil
  repeat
    local delivery,nextCursor=J.next(snapshot,cursor)
    if not delivery then break end
    T.check(delivery.steps<=J.MAX_DELIVERY,'native backlog reaches Lua in bounded chunks')
    count=count+delivery.steps;cursor=nextCursor
  until false
  T.eq(count,expected,'every native-produced step is retained across the wire')
  T.eq(J.next(snapshot,cursor),nil,'native snapshot does not replay after its last chunk')
end
T.finish('Native Swift/Java to Lua step wire')
