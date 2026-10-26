-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-phone-list-hook.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local original=V.get()
local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local Gear=require('src.ui.PokegearMenu');local Book=require('src.world.Gen2PhoneBook')
local Calls=require('src.script.Gen2Commands')
local function fixture()
 local d=T.fixtures.fresh();d.constants.phoneContactOrder={'PHONE_00','PHONE_MOM','U2','U3','PHONE_ELM','U5','U6','PHONE_A','U8','PHONE_B'}
 d.map_scripts={phoneInfo={size=10},scripts={STUB={{'end'}}},phone={
  [1]={name='MOM',contactNumber=1},[4]={name='ELM',contactNumber=4},
  [7]={name='A',receive='STUB',receiveTime=7,group=1,number=1},
  [9]={name='B',receive='STUB',receiveTime=7,group=1,number=1}}}
 return d
end
local function load(d,source,mode)
 for root in pairs(require('src.mods.Builtins').namespaceRoots()) do d[root]=nil end
 local files={}
 if source then
  files['mods/phone_hook/manifest.json']=Json.encode({id='phone_hook',name='Phone list',version='1.0.0',
   api=mode and mode[1] or 2,content_format=mode and mode[2] or 'native',entry='main.lua',affects_link=false})
  files['mods/phone_hook/main.lua']='local mod=...;mod.exports.api=mod;'..source
 end
 return T.sdk.loadMods(source and {'mods/phone_hook'} or {},{data=d,fs=T.sdk.memfs(files)})
end
local function finish(r)Loader.teardown();r.release()end
for _,version in ipairs({'gold','silver','crystal'}) do
 V.set(version)
 for _,mode in ipairs({{1,'native'},{2,'native'}}) do
  local d=fixture();local r=load(d,[[
   local added=mod.content.phone_contacts:register('PHONE_NEW',{name='AUTHORED NEW'})
   mod.exports.index=added.index
   mod.exports.stop=mod.hooks:wrap("phone.contact_list",function(next,save,list)
    mod.exports.calls=(mod.exports.calls or 0)+1;mod.exports.save=save;mod.exports.received=list
    local rows=next(save,list);rows[1]=9;rows[2]=0;rows[3]='7';rows[10]=added.index
    return rows
   end)
  ]],mode)
  local label=version..'/'..mode[1]..'/'..mode[2]
  T.eq(#r.errors,0,label..' real public hook registration succeeds')
  local save={g2Phone={[7]=true,[9]=true},g2PhoneSlots={7,9,0,0,0,0,0,0,0,0}}
  local gear=setmetatable({game={data=d,save=save}},{__index=Gear})
  local rows=gear:contacts();local e=r.loader.exports.phone_hook
  T.eq(e.calls,1,label..' native card dispatches the hook exactly once')
  T.eq(e.save,save,label..' opaque native save handle retains reference signature')
  T.eq(#rows,10,label..' presentation retains ten slots')
  T.eq(rows[1].id,9,label..' display hook can reorder native contacts')
  T.eq(rows[1].slot,2,label..' reordered row retains its actual physical slot')
  T.eq(rows[2].id,0,label..' display hook can hide a row')
  T.eq(rows[3].id,7,label..' numeric contact spellings resolve through native records')
  T.eq(rows[3].slot,1,label..' reordered selected ID does not acquire a different native slot')
  T.eq(rows[10].name,'AUTHORED NEW',label..' hook sees actual native content registration')
  T.eq(rows[10].slot,nil,label..' an injected display row cannot borrow another physical slot')
  T.eq(save.g2Phone[e.index],nil,label..' showing a contact does not register it')
  T.eq(Book.contacts(save)[1],7,label..' saved registration order remains native')
  local incoming=Calls.availableCallers(d,save,{group=2,number=1},'DAY')
  T.eq(incoming[1],7,label..' incoming caller selection ignores display reorder')
  T.eq(incoming[2],9,label..' hidden display contact remains eligible for native incoming calls')
  T.eq(e.calls,1,label..' incoming call selection does not dispatch the display hook')
  e.received[1]=255;rows[1].name='READ MUTATION'
  T.eq(Book.contacts(save)[1],7,label..' received display arrays cannot mutate the native book')
  T.eq(d.map_scripts.phone[9].name,'B',label..' returned UI rows cannot mutate native contacts')
  local key;gear.cards={{id='PHONE'}};gear.index=1;gear.blink=0;gear.contact=1
  gear.game.input={wasPressed=function(_,value)return key==value end};gear.game.stack={pop=function()end}
  local Sound=require('src.core.Sound');local old=Sound.play;Sound.play=function()end
  key='a';gear:update(0);key='down';gear:update(0);key='a';gear:update(0)
  T.eq(save.g2Phone[9],nil,label..' actual DELETE targets the reordered contact ID')
  T.eq(save.g2Phone[7],true,label..' display position cannot delete the unrelated physical contact')
  gear.contact=1;key='a';gear:update(0);key='down';gear:update(0);key='a';gear:update(0)
  T.eq(save.g2Phone[7],true,label..' deleting an injected non-member never consumes another native slot')
  Sound.play=old
  e.stop();rows=gear:contacts()
  T.eq(rows[1].id,7,label..' unsubscribe restores the actual native presentation')
  T.eq(rows[2].id,0,label..' unsubscribe does not recreate the deleted contact')
  finish(r)
 end
end
V.set('crystal')
for _,expression in ipairs({'nil','false','"bad"','{9}','{9,7,0,0,0,0,0,0,0,0,0}'}) do
 local d=fixture();local r=load(d,'mod.hooks:wrap("phone.contact_list",function()return '..expression..' end)')
 T.eq(#r.errors,0,'invalid display return does not prevent entry loading')
 local save={g2Phone={[7]=true}};local rows=setmetatable({game={data=d,save=save}},{__index=Gear}):contacts()
 T.eq(rows[1].id,7,'wrong return type/length keeps the real native display: '..expression)
 T.eq(#rows,10,'wrong return type/length keeps native slot count')
 finish(r)
end
do
 local d=fixture();local r=load(d,[[mod.hooks:wrap("phone.contact_list",function()
  return {999,-1,1.5,0/0,math.huge,{},true,'7','bad',9}
 end)]])
 local save={g2Phone={[7]=true,[9]=true}}
 local rows=setmetatable({game={data=d,save=save}},{__index=Gear}):contacts()
 for i=1,7 do T.eq(rows[i].id,0,'invalid callback contact becomes a blank at slot'..i) end
 T.eq(rows[8].id,7,'valid numeric string still resolves')
 T.eq(rows[9].id,0,'invalid text becomes a blank')
 T.eq(rows[10].id,9,'valid last native contact is retained')
 T.eq(save.g2Phone[7],true,'sanitization preserves native registration')
 finish(r)
end
do
 local d=fixture();local r=load(d,[[mod.hooks:wrap("phone.contact_list",function()return {9,0,0,0,0,0,0,0,0,0}end);error('entry failure')]])
 T.check(#r.errors>0,'failed entry is reported')
 local rows=setmetatable({game={data=d,save={g2Phone={[7]=true}}}},{__index=Gear}):contacts()
 T.eq(rows[1].id,7,'failed-entry rollback removes its phone hook')
 finish(r)
end
for _,version in ipairs({'red','firered','emerald','heartgold'}) do
 V.set(version);local d=fixture();d.field.phone={contacts={{id=99,name='LEGACY'}}}
 local r=load(d,[[mod.exports.calls=0
  mod.hooks:wrap("phone.contact_list",function(next,...)mod.exports.calls=mod.exports.calls+1;return next(...)end)]])
 T.eq(#r.errors,0,version..' hook registration remains available without a native call site')
 local rows=setmetatable({game={data=d,save={}}},{__index=Gear}):contacts()
 T.eq(rows[1].name,'LEGACY',version..' native-looking phone records do not replace authored presentation')
 T.eq(r.loader.exports.phone_hook.calls,0,version..' cannot dispatch a Gen2-only display hook')
 finish(r)
end
V.set(original)
T.finish('native phone.contact_list hook, actual card/delete, saved-book isolation and rollback')
