-- Copyright (c) 2026 Roxas2712. See the offered contribution licence.
-- Actual older-host constructors, menus, EXP/faint owners and party effects.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local B=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local old=V.get()
for _,edition in ipairs(V.ORDER)do
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=V.generation(edition)
 if data.constants.gen>=3 then
  -- These editions use the structural six-stat/IV schema. The base fixture
  -- is Gen1-shaped, so give the owned species their proper native layout.
  for _,def in pairs(data.pokemon)do
   if type(def)=='table'and def.baseStats then
    def.baseStats.spatk=def.baseStats.spatk or def.baseStats.special
    def.baseStats.spdef=def.baseStats.spdef or def.baseStats.special
    def.evYield={hp=0,attack=0,defense=0,speed=0,spatk=0,spdef=0}
   end
  end
 end
 local run=T.sdk.loadMods({'mods/scope_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/scope_probe/manifest.json']='{"id":"scope_probe","name":"Native scope probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/scope_probe/main.lua']=[[
   local mod=...
   mod.hooks:wrap('battle.exp_award',function(next,ctx)
    mod.exports.award=ctx
    return next(ctx)
   end)
  ]],
 })})
 T.eq(#run.errors,0,'real native party observer loads: '..edition)
 require('src.render.Font').load(data)
 local save=Save.newGame();save.party={}
 for i=1,3 do save.party[i]=Pokemon.new(data,'FIXMON_A',20+i)end
 local game={data=data,save=save,stack={top=function()end}}
 data.trainers.OWN_SCOPE={id='OWN_SCOPE',index=22,name='SCOPE',baseMoney=10,
  parties={{{level=5,species='FIXMON_C'}}}}
 local original,first,second,third=save.party,save.party[1],save.party[2],save.party[3]
 local selected={3,2}
 local b=B.newTrainer(game,'OWN_SCOPE',1,{playerPartyIndices=selected})
 T.eq(b.player.mon,third,'native lead is the first selected original mon')
 T.eq(b:playerPartyView()[1],third,'ordered scope retains actual first reference')
 T.eq(b:playerPartyView()[2],second,'ordered scope retains actual second reference')
 T.neq(b.playerPartyIndices,selected,'caller cannot mutate retained selection indices')
 T.eq(b:benchFor(true),b.playerParty,'native bench uses the actual selected roster')
 T.eq(#b:benchFor(true),2,'excluded healthy mon is not a replacement')
 -- AI runs after real screen entry initializes native on-field sides; a
 -- constructor's not-yet-entered empty side table is not an AI phase.
 b:enter()
 T.eq(b.sides[1].battlers[1],b.player,'actual enter initializes the selected on-field owner')
 local menu=b:buildScreen(require('src.battle.Gen4Battle').partyScreenId(b)or 'PartyMenu',
  {battle=b,onSwitch=function()end})
 local shown=type(menu.party)=='function'and menu:party()or menu.party
 T.eq(shown,b.playerParty,'actual generation-appropriate party menu uses scope')
 T.eq(#shown,2,'actual party menu cannot offer an excluded mon')
 -- The existing AI already understands playerParty. Ensure construction
 -- and replacement draw from that same original roster, including doubles.
 local vm={battle=b,user=b.player,target=b.enemy}
 require('src.battle.Gen3AI').OPS.count_usable_party_mons(vm,{1})
 T.eq(vm.result,1,'real AI counts only one selected off-field replacement')
 b.double=true;b:sendOutSecondPair()
 T.eq(b:battlerAt(B.POS.PLAYER_RIGHT).mon,second,'second flank draws from selected roster')
 require('src.battle.Gen3AI').OPS.count_usable_party_mons(vm,{1})
 T.eq(vm.result,0,'both selected mons on field leave no AI replacement')
 -- Party-wide effects must not heal or count the excluded save-party mon.
 for _,mon in ipairs(save.party)do mon.status='BRN'end
 require('src.battle.Gen3MoveEffects').primary.HEAL_BELL_EFFECT(b,b.player)
 T.eq(first.status,'BRN','actual Heal Bell leaves excluded mon alone')
 T.eq(second.status,nil,'actual Heal Bell heals selected second mon')
 T.eq(third.status,nil,'actual Heal Bell heals selected lead')
 first.status=nil
 local count=require('src.battle.Gen3MoveEffects').full.BEAT_UP_EFFECT.hitCount(
  {battle=b,user=b.player,target=b.enemy})
 T.eq(count,2,'real Beat Up hit count excludes healthy save-party outsider')
 if V.isGen5()then
  for _,mon in ipairs(save.party)do mon.status='BRN'end
  require('src.battle.Gen5MoveEffects').record(b,'BW_HEAL_BELL').run({
   battle=b,user=b.player,target=b.player,
   move={id='OWN_SCOPE_BELL',name='BELL',power=0,type='NORMAL'},
  })
  T.eq(first.status,'BRN','actual Gen5 effect leaves excluded mon alone')
  T.eq(second.status,nil,'actual Gen5 effect heals selected second mon')
  T.eq(third.status,nil,'actual Gen5 effect heals selected lead')
 end
 -- Native EXP.ALL includes exactly this battle's party, even if stale
 -- participation bookkeeping still names the excluded save-party mon.
 b.queue={};b.participants={[first]=true,[second]=true,[third]=true}
 save.inventory.EXP_ALL=1
 local excludedExp=first.exp
 b:awardExp(b.enemy)
 local award=run.loader.exports.scope_probe.award
 T.check(award~=nil,'actual native EXP hook executes')
 if award then
  T.eq(award.participants,2,'actual EXP divisor contains selected participants')
  T.eq(#award.alive,2,'actual EXP living roster excludes outsider')
 end
 T.eq(first.exp,excludedExp,'actual EXP.ALL cannot pay excluded outsider')
 second.hp,third.hp=0,0
 T.check(first.hp>0,'excluded save-party member remains healthy')
 b.result=nil;b:playerMonFainted()
 T.eq(b.result,'lose','actual native defeat ignores excluded healthy party member')
 T.eq(save.party,original,'battle never replaces real save.party')
 T.eq(save.party[1],first,'battle never reorders excluded save-party member')
 T.eq(save.party[2],second,'battle never reorders selected save-party member')
 T.eq(save.party[3],third,'battle retains every original party mon')
 for _,invalid in ipairs{{},{1,1},{0},{4},{1.5},{[1]=1,[3]=2},{1,unexpected=true},'bad'}do
  local party,indices=require('src.battle.PlayerPartyScope').select(game,invalid)
  T.eq(party,nil,'invalid native selection falls back to complete party')
  T.eq(indices,nil,'invalid selection keeps no misleading remap')
 end
 run.release()
end
V.set(old)
T.finish('older-host real trainer party selection, UI, AI, party effects, EXP and defeat')
