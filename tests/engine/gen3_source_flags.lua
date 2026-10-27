package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local oldLove=love
local raw=string.rep(string.char(0,1,2,3,4,5,6,7),30)
love={data={hash=function(algorithm,value)T.eq(algorithm,'sha256');return string.rep(value==raw and 'x'or'y',32)end}}
local read=require('src.import.Gen3SourceFlags').read
local spec={offset=4,count=240,sha256=string.rep('78',32)}
T.eq(read({data='HEAD'..raw},spec),raw,'only verified original flag bytes are published')
for _,bad in ipairs({{}, {offset=-1,count=240,sha256=spec.sha256},{offset=.5,count=240,sha256=spec.sha256},
 {offset=4,count=256,sha256=spec.sha256},{offset=4,count=240,sha256='invalid'},
 {offset=4,count=240,sha256=string.rep('X',64)}})do T.eq(read({data='HEAD'..raw},bad),nil)end
T.eq(read({data='HEAD'..raw:sub(1,239)},spec),nil,'truncated source cannot masquerade as flags')
T.eq(read({data='HEAD'..raw:sub(2)..'x'},spec),nil,'wrong range fails checksum')
love.data.hash=function()return string.rep('x',32)end
T.eq(read({data='HEAD'..string.rep(string.char(8),240)},spec),nil,'unknown flag bits rejected after checksum')
love.data.hash=nil;T.eq(read({data='HEAD'..raw},spec),nil,'missing checksum support is explicit')
love=oldLove
T.finish('verified source terrain flags')
