package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
T.eq(package.loaded['src.core.Game'],nil)
local Store=require('src.compat.gen1.ScriptStore')
T.eq(package.loaded['src.core.Game'],nil,'requiring numeric stores cannot bootstrap Game')
love=require('tests.love_stub')
local Version=require('src.core.GameVersion')
local G3=require('src.script.Gen3Commands')
local Commands=require('src.script.Commands')
local Events=require('src.mods.Events')
local Runtime=require('src.mods.Runtime')
local events=Events.new();local announcements={}
events:on('flag.changed',function(e)announcements[#announcements+1]=e end)
Runtime.events=events
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  local f=require('tools.session-runtime.fixture').new(edition)
  local game=f.game;game.save.flags={};game.save.gen3Vars=nil
  local store=assert(Store.new(game));T.eq(store:valid(),true)
  T.eq(store:getVar(0x4075),0);T.eq(game.save.gen3Vars,nil,'reading an absent variable cannot allocate native state')
  T.eq(store:getVar(37),37,'low script operands remain immediate values')
  T.eq(store:getFlag(0x807),false)
  local hide={index=1,eventFlag='FLAG_G3_0807'};f.map.def.objects={hide}
  local visibleSyncs=0
  function f.world:syncObjectVisibility(obj)assert(obj==hide);visibleSyncs=visibleSyncs+1 end
  local before=#announcements
  store:setFlag(0x807,true);T.eq(game.save.flags.FLAG_G3_0807,true)
  T.eq(visibleSyncs,1,'numeric writes use native live visibility commands')
  T.eq(#announcements,before+1)
  store:setFlag(0x807,true);T.eq(#announcements,before+1,'unchanged writes preserve native event deduplication')
  Commands.g3_clear_flag({game=game,save=game.save,overworld=f.world},'FLAG_G3_0807')
  T.eq(store:getFlag(0x807),false,'native command changes are immediately observable')
  store:setFlag(0x4b8,true)
  local frlg=edition=='firered'or edition=='leafgreen'
  T.eq(game.save.flags.EVENT_BEAT_LORELEIS_ROOM_TRAINER_0,frlg and true or nil,'native league aliases remain edition scoped')
  store:setFlag(0x4b8,false)
  if frlg then T.eq(game.save.flags.EVENT_BEAT_LORELEIS_ROOM_TRAINER_0,false)end
  store:setVar(0x4075,-1);T.eq(G3.getVar(game.save,0x4075),65535)
  G3.setVar(game.save,0x4075,37);T.eq(store:getVar('0x4075'),37)
  store:setVar(0x4010,89);T.eq(game.save.gen3ObjectSprites[0],89)
  store:clearVar(0x4010);T.eq(game.save.gen3ObjectSprites[0],nil);T.eq(game.save.gen3Vars[0x4010],nil)
  store:setVar(0x8000,12);store:setVar(0x8015,13);store:setVar(0x8016,14)
  game.save.flags.NATIVE_ONLY=true
  game.save.gen3Vars[0x4077]={mustNotEscape=true}
  T.eq(store:getVar(0x4077),0,'invalid native values cannot lend a mutable table')
  local snap=store:snapshot();T.eq(snap.flags[0x807],false);T.eq(snap.flags.NATIVE_ONLY,nil)
  T.eq(snap.vars[0x4077],nil)
  T.eq(snap.vars[0x4075],37);T.eq(snap.vars[0x8000],nil)
  T.eq(snap.vars[0x8015],frlg and 13 or nil,'special-variable range follows the edition')
  T.eq(snap.vars[0x8016],14)
  snap.flags[0x807]=true;snap.vars[0x4075]=999
  T.eq(store:getFlag(0x807),false);T.eq(store:getVar(0x4075),37,'snapshots are detached')
  -- Use the actual native compiler and runner, not a fabricated VM: script
  -- writes and adapter writes must meet in the same live command store.
  game.data.map_scripts={source='RomExtractorGen3',scripts={
    NATIVE_WRITE={{'setvar',0x4075,41},{'addvar',0x4075,1},{'setflag',0x807},{'end'}},
    NATIVE_READ={{'copyvar',0x4076,0x4075},{'end'}},
  }}
  local compiler=require('src.script.Gen3ScriptVM')
  local runner=require('src.script.ScriptRunner').new(game,f.world)
  runner:run(assert(compiler.compile(game.data,'NATIVE_WRITE')))
  T.eq(runner:isRunning(),false);T.eq(store:getVar(0x4075),42);T.eq(store:getFlag(0x807),true)
  store:setVar(0x4075,123)
  runner:run(assert(compiler.compile(game.data,'NATIVE_READ')))
  T.eq(runner:isRunning(),false);T.eq(G3.getVar(game.save,0x4076),123)
  local nextWorld={isOverworld=true,map=f.map,player=f.player}
  local newSync=0
  function nextWorld:syncObjectVisibility(obj)assert(obj==hide);newSync=newSync+1 end
  game.stack.states={nextWorld}
  store:setFlag(0x807,false);T.eq(newSync,1,'writes resolve the current world after a transition')
  for _,bad in ipairs({-1,65536,.5,0/0,math.huge,'not an id'})do
    T.raises(function()store:getFlag(bad)end,'invalid numeric','invalid flag id declines')
    T.raises(function()store:setVar(bad,1)end,'invalid numeric','invalid variable id declines')
  end
  for _,bad in ipairs({.5,0/0,math.huge,'1'})do
    T.raises(function()store:setVar(0x4075,bad)end,'invalid script','invalid variable data declines')
  end
  T.raises(function()store:setFlag(0x807,1)end,'invalid script','numeric truthiness cannot accidentally set a flag')
  store:release();T.eq(store:valid(),false)
  T.raises(function()store:snapshot()end,'retired','explicit release retires observations too')
  for _,change in ipairs({
    function()game.save={}end,
    function()game.data={}end,
    function()game.mods={}end,
    function()game.data.maps={}end,
    function()Version.set('crystal')end,
  })do
    local live=assert(Store.new(game));change();T.eq(live:valid(),false)
    T.raises(function()live:setVar(0x4075,1)end,'retired','retired store cannot write the next cohort')
    -- Restore the fixture's selected generation for the next independent binding.
    Version.set(edition)
  end
end
Version.set('crystal');T.eq(Store.new({data={},save={}}),nil,'earlier generations never inherit a GBA script binding')
T.finish('native numeric script-store backend')
