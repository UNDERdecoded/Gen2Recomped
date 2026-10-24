package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Json=require('src.link.Json')
local Net=require('src.mods.Net')
local function load(permissions, entry)
 local fs=T.sdk.memfs({
  ['mods/net_probe/manifest.json']=Json.encode({id='net_probe',name='Net probe',version='1.0.0',api=2,entry='main.lua',permissions=permissions}),
  ['mods/net_probe/main.lua']=entry,
 })
 return T.sdk.loadMod('mods/net_probe',{fs=fs})
end
local a=load({'network'},[[local mod=...;assert(type(mod.fetch.get)=='function');assert(type(mod.fetch.poll)=='function');mod.exports.fetch=mod.fetch]])
T.eq(#a.errors,0,'network mod loads real fetch facade')
T.eq(a.mod.state,'loaded','entry completed')
T.eq(type(a.loader.exports.net_probe.fetch.cancel),'function','cancellation exposed')
T.eq(type(a.loader.exports.net_probe.fetch.capabilities),'function','capability query exposed')
T.eq(a.loader.exports.net_probe.fetch:get('file:///private'),nil,'file URL refused')
a.release()
local b=load({},[[local mod=...;mod.exports.available=mod.fetch:available();mod.exports.get=pcall(mod.fetch.get,mod.fetch,'https://example.invalid')]])
T.eq(#b.errors,0,'ungranted query does not fail entry')
T.eq(b.loader.exports.net_probe.available,false,'transport unavailable without grant')
T.eq(b.loader.exports.net_probe.get,false,'operation requires network grant')
b.release()
for _,bad in ipairs({'https://','https://example.invalid\nHeader: bad','ftp://host','https://host\0','http://a b'})do
 T.eq(type(Net.urlDenial(bad)),'string','bad URL denied')
end
T.eq(Net.urlDenial('https://host/a%20b?x=%22&z=1'),nil,'encoded URL accepted')
T.finish('mod network permission')
