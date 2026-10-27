package.path='./?.lua;'..package.path
local ticks, checks, channels, workers = 0, 0, {}, {}
local function check(ok, label) checks=checks+1;assert(ok,label)end
local function channel()
 local q={}
 function q:push(v)self[#self+1]=v end
 function q:pop()if #self==0 then return nil end;return table.remove(self,1)end
 function q:peek()return self[1]end
 function q:clear()for i=#self,1,-1 do self[i]=nil end end
 channels[#channels+1]=q;return q
end
love={timer={getTime=function()return ticks end},thread={newChannel=channel,newThread=function()
 local t={start=function(self,c,r,q)self.commands,self.results,self.quit=c,r,q end,
 getError=function(self)return self.err end,wait=function()end};workers[#workers+1]=t;return t
end}}
local Get=require('src.net.AsyncGet')
check(Get.get('file:///x')==nil,'direct caller URL validation')
check(Get.get('http://host',{boundedHttpsGet=1})==nil,'direct caller HTTPS constraint')
local handles={}
for i=1,Get.MAX_JOBS do handles[i]=assert(Get.get('https://host/x')) end
check(#workers==3,'fixed worker ceiling')
check(Get.get('https://host/x')==nil,'global active ceiling')
for _,id in ipairs(handles)do Get.cancel(id);Get.release(id)end
check(Get.get('https://host/x')==nil,'release cannot evade running worker ceiling')
for _,id in ipairs(handles)do workers[1].results:push({id=id,ok=true,body='late'})end
local id=assert(Get.get('https://host/x',{maxSeconds=1}))
check(Get.poll(handles[1]).status=='error','released handle never revived by late result')
ticks=2
check(Get.poll(id).status=='error','queue time counts toward deadline')
workers[1].results:push({id=id,ok=true,body='too late'})
check(Get.poll(id).body==nil,'timeout never accepts late body');Get.release(id)
id=assert(Get.get('https://host/x'));Get.cancel(id)
workers[1].results:push({id=id,ok=true,body='late'})
check(Get.poll(id).status=='cancelled' and Get.poll(id).body==nil,'cancel never accepts late body');Get.release(id)
id=assert(Get.get('https://host/x'));workers[1].err='worker stopped'
check(Get.poll(id).status=='error','worker failure terminates pending jobs');Get.release(id)
Get.shutdown();check(Get.available(),'shutdown restarts pool')
id=assert(Get.get('https://host/x'));local w=workers[#workers]
w.results:push({id=id,ok=true,body='ok'})
local state=Get.poll(id);state.status='changed'
check(Get.poll(id).status=='ok','poll returns detached state')
Get.release(id);Get.shutdown()
check(Get.postLog('http://host','log')==nil,'POST always requires HTTPS')
check(Get.postLog('https://host',string.rep('x',512*1024+1))==nil,'wire payload has a byte ceiling')
id=assert(Get.postLog('https://host','log',{contentType='text/plain'}))
w=workers[#workers]
w.results:push({id=id,ok=true,body='must not escape',err='must not escape',httpStatus=204})
state=Get.poll(id)
check(state.status=='ok' and state.body==nil and state.err==nil,'one-way worker results hide body and diagnostics')
Get.release(id);Get.shutdown()
print(('async GET queue: %d checks PASS'):format(checks))
