-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Loader=require('src.mods.Loader')
local Json=require('src.link.Json')
local Radio=require('src.world.Gen2Radio')
local Gear=require('src.ui.PokegearMenu')
local Runtime=require('src.mods.Runtime')
local original=V.get()
local function size(t)local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function load(data,source,api,format,extra)
  -- The real hot-reload path reconstructs engine-seeded namespaces before
  -- loading mods. Retain the mounted radio target under test.
  for root in pairs(require('src.mods.Builtins').namespaceRoots())do data[root]=nil end
  local files={}
  if source then
    files['mods/radio/manifest.json']=Json.encode({id='radio',name='Radio contract',version='1.0.0',
      api=api or 2,content_format=format or 'native',entry='main.lua',affects_link=false})
    files['mods/radio/main.lua']='local mod=...;mod.exports.api=mod; '..source
  end
  for k,v in pairs(extra or {})do files[k]=v end
  return T.sdk.loadMods(source and {'mods/radio'} or {},{data=data,fs=T.sdk.memfs(files)})
end
local function finish(r)Loader.teardown();r.release()end
local function fixture()
  local d=T.fixtures.fresh();d.maps.PALLET_TOWN={landmark=47};return d
end
for _,version in ipairs({'gold','silver','crystal'})do
  V.set(version)
  local d=fixture();local r=load(d)
  T.eq(#r.errors,0,'no-mod load succeeds: '..version)
  T.eq(d.gen2RadioChannels,nil,'no-mod virtual base creates no namespace')
  T.eq(size(Radio.records(d)),11,'all native station identities are readable')
  local gear=setmetatable({game={data=d,save={}}},{__index=Gear})
  T.eq(#gear:stationList(),6,'vanilla native tuner count retained')
  T.eq(gear:stationList()[1].name,"OAK'S POKéMON TALK",'native program name retained')
  T.eq(Radio.resolve(d,0,{landmark=1},'MORNING'),'POKEDEX_SHOW','morning Pokemon Channel')
  T.eq(Radio.resolve(d,0,{landmark=1},'DAY'),'OAKS_POKEMON_TALK','day Pokemon Channel')
  T.eq(Radio.resolve(d,0,{landmark=47},'MORNING'),'PLACES_AND_PEOPLE','imported Kanto boundary wins over time')
  gear.game.save.flags={ENGINE_EXPN_CARD=true}
  T.eq(#gear:stationList(),7,'EXPN keeps the native flute slot')
  finish(r)
end
V.set('crystal')
for _,mode in ipairs({{1,'native'},{2,'native'}})do
  local d=fixture()
  local r=load(d,[[
    local radio=mod.content["radio_channels"]
    local row=assert(radio:get('OAKS_POKEMON_TALK'));row.name='BORROWED'
    assert(radio:get('OAKS_POKEMON_TALK').name~='BORROWED')
    for id,value in radio:each()do value.name='ITERATOR MUTATION' end
    assert(radio:get('OAKS_POKEMON_TALK').name~='ITERATOR MUTATION')
    radio:patch('OAKS_POKEMON_TALK',{name='AUTHORED TALK'})
    radio:register('PIRATE_RADIO',{channel=9,name='PIRATE RADIO'})
    radio:remove('POKEDEX_SHOW')
    radio:patch('LUCKY_CHANNEL',{channel=11})
    mod.events:on("radio.channel",function(e)
      mod.exports.event={station=e.station,channel=e.channel,name=e.name,source=e.source}
      e.name='CALLBACK MUTATION'
    end)
  ]],mode[1],mode[2])
  T.eq(#r.errors,0,'real loader accepts radio contract '..mode[1]..'/'..mode[2])
  local e=r.loader.exports.radio
  T.eq(d.gen2RadioChannels.OAKS_POKEMON_TALK.name,'AUTHORED TALK','merge reaches actual native station records')
  T.eq(Radio.resolve(d,9),'PIRATE_RADIO','wall radio consumes a new registered station')
  T.eq(Radio.resolve(d,11),'LUCKY_CHANNEL','wall radio consumes a changed channel number')
  T.eq(Radio.channelRecord(d,4),nil,'previous channel number is not retained')
  T.eq(Radio.resolve(d,0,{landmark=1},'MORNING'),nil,'removed morning station cannot resurrect')
  local gear=setmetatable({game={data=d,save={}}},{__index=Gear})
  T.eq(#gear:stationList(),5,'native tuner consumes removal')
  T.eq(gear:stationList()[1].name,'AUTHORED TALK','native tuner consumes authored name')
  T.eq(gear:stationList()[1].nameLiteral,true,'authored text bypasses engine string catalog')
  T.eq(Radio.isLiteral(d,'LUCKY_CHANNEL'),false,'channel-only patch retains built-in translation ownership')
  Radio.notify(d,'PIRATE_RADIO',9,'map_radio')
  T.eq(e.event.station,'PIRATE_RADIO','real mod event receives station identity')
  T.eq(e.event.name,'PIRATE RADIO','real mod event receives authored station name')
  T.eq(e.event.channel,9,'real mod event receives script dial number')
  T.eq(e.event.source,'map_radio','real mod event identifies wall producer')
  T.eq(Radio.stationName(d,'PIRATE_RADIO'),'PIRATE RADIO','callback mutation cannot edit content')
  local borrowed=e.api.content.radio_channels:get('PIRATE_RADIO');borrowed.name='OUTSIDE'
  T.eq(Radio.stationName(d,'PIRATE_RADIO'),'PIRATE RADIO','post-load get is detached')
  T.raises(function()e.api.content.radio_channels:patch('PIRATE_RADIO',{name='LATE'})end,'frozen','station mutations freeze after load')
  finish(r)
  r=load(d)
  T.eq(d.gen2RadioChannels,nil,'reload without mods removes generated namespace')
  T.eq(Radio.resolve(d,2),'POKEDEX_SHOW','reload restores removed native station')
  T.eq(Radio.channelRecord(d,9),nil,'reload removes mod-only station')
  finish(r)
end
-- Failed entries must roll back earlier valid edits and event subscriptions.
for _,bad in ipairs({
  "r:register('DUPLICATE',{channel=1,name='bad'})",
  "r:patch('LUCKY_CHANNEL',{channel=256})",
  "r:patch('LUCKY_CHANNEL',{channel=0/0})",
  "r:patch('LUCKY_CHANNEL',{name=123})",
  "local cycle={};cycle.self=cycle;r:register('CYCLE',cycle)",
  "r:register('ROCKET_RADIO',{channel=10})",
})do
  local d=fixture();local r=load(d,"local r=mod.content.radio_channels;r:patch('OAKS_POKEMON_TALK',{name='SHOULD ROLLBACK'});"..bad)
  T.eq(#r.errors,1,'malformed/ambiguous station fails one mod')
  T.eq(Radio.stationName(d,'OAKS_POKEMON_TALK'),"OAK'S POKéMON TALK",'failed entry cannot leak prior valid edit')
  T.eq(d.gen2RadioChannels,nil,'failed entry leaves no namespace')
  finish(r)
end
-- External edits between hot reloads survive without retaining old mod rows.
local d=fixture();local r=load(d,[[
  mod.content.radio_channels:register('PIRATE_RADIO',{channel=9,name='MOD'})
  mod.content.radio_channels:patch('OAKS_POKEMON_TALK',{name='MOD TALK'})
]])
d.gen2RadioChannels.OAKS_POKEMON_TALK.name='EXTERNAL'
d.gen2RadioChannels.LUCKY_CHANNEL=nil
finish(r);r=load(d)
T.eq(Radio.stationName(d,'OAKS_POKEMON_TALK'),'EXTERNAL','external edit survives reload')
T.eq(Radio.channelRecord(d,9),nil,'external edit does not pin stale mod-only rows')
T.eq(d.gen2RadioChannels.LUCKY_CHANNEL,nil,'external removal survives reload')
T.eq(Radio.isLiteral(d,'OAKS_POKEMON_TALK'),true,'external authored name stays literal')
finish(r)
d=fixture();d.gen2RadioChannels={AUTHORED={channel=22,name='BASE'}}
local base=d.gen2RadioChannels.AUTHORED
r=load(d,[[
  local r=mod.content.radio_channels
  local row={channel=23,name='REPLACEMENT'}
  r:override('AUTHORED',row);row.name='LEAK'
  r:patch('AUTHORED',{name=mod.DELETE})
  r:register('TEMP',{channel=24,name='TEMP'})
]])
T.eq(#r.errors,0,'override and optional field deletion are valid')
T.eq(d.gen2RadioChannels.AUTHORED.name,nil,'DELETE removes optional authored name')
T.eq(d.gen2RadioChannels.AUTHORED.channel,23,'override replaces original dial position')
T.eq(Radio.isLiteral(d,'AUTHORED'),false,'deleted authored name no longer claims literal ownership')
finish(r);r=load(d)
T.eq(d.gen2RadioChannels.AUTHORED,base,'unmodified authored base row identity is restored')
T.eq(d.gen2RadioChannels.AUTHORED.name,'BASE','reload restores original authored name')
T.eq(d.gen2RadioChannels.TEMP,nil,'reload removes temporary station from authored dataset')
finish(r)
-- A failed contribution must not roll back a preceding successful owner.
d=fixture()
local extras={
 ['mods/broken/manifest.json']=Json.encode({id='broken',name='Broken radio',version='1',api=2,entry='main.lua',dependencies={'radio'}}),
 ['mods/broken/main.lua']=[[
   local mod=...;mod.content.radio_channels:patch('OAKS_POKEMON_TALK',{name='BROKEN'})
   mod.events:on("radio.channel",function()error('leaked failed listener')end)
   mod.content.radio_channels:register('BAD',{channel=1})
 ]],
}
r=load(d,"mod.content.radio_channels:patch('OAKS_POKEMON_TALK',{name='GOOD'})",2,'native',extras)
T.eq(#r.errors,1,'only dependent broken contributor fails')
T.eq(Radio.stationName(d,'OAKS_POKEMON_TALK'),'GOOD','successful contribution survives later rollback')
local errors=#r.errors;Radio.notify(d,'OAKS_POKEMON_TALK',1,'map_radio')
T.eq(#r.errors,errors,'failed contributor listener is removed with its operations')
finish(r)
d=fixture();d.gen2RadioChannels={};r=load(d)
T.eq(size(Radio.records(d)),0,'explicit empty authored namespace stays authoritative')
T.eq(#setmetatable({game={data=d,save={}}},{__index=Gear}):stationList(),0,'empty authored tuner cannot resurrect defaults')
finish(r)
for _,version in ipairs({'red','emerald','platinum','black'})do
  V.set(version);d=T.fixtures.fresh()
  r=load(d,[[
    assert(mod.content.radio_channels:get('OAKS_POKEMON_TALK')==nil)
    assert(mod.content.radio_channels:each()()==nil)
    assert(mod.content.radio_channels:register('NOT_NATIVE',{channel=9})==nil)
  ]],2,'native')
  T.eq(#r.errors,0,'other target has honest unsupported contract: '..version)
  T.eq(d.gen2RadioChannels,nil,'other generation creates no radio target')
  T.eq(next(r.loader.content.radio_channels.ops),nil,'other generation appends no operation')
  finish(r)
end
V.set(original)
T.finish('native radio content, consumers, target isolation and rollback')
