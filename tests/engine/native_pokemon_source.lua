-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local P=require('src.core.game3.pokemon')
local original=package.loaded['src.core.Game']
local Host=require('src.mods.Runtime')
T.eq(P.ready(),false)
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 local game=f.game;package.loaded['src.core.Game']=game
 local data=game.data
 data.constants=data.constants or{}
 data.constants.speciesOrder={[4]='CHARMANDER',[277]='SPARSE_SPECIES'}
 data.pokemon.SPARSE_SPECIES={index=277,dex=252,name='SPARSE',id='SPARSE_SPECIES'}
 data.constants.typeOrder={'NORMAL'};data.constants.types={NORMAL={index=0}}
 data.constants.abilityOrder={'NONE','PROBE'};data.constants.abilities={NONE={index=0},PROBE={index=1}}
 data.constants.moveOrder={[33]=f.ids.TACKLE}
 local row=data.pokemon.CHARMANDER
 row.height,row.weight,row.genderRatio,row.abilities=.7,6.9,127,{'PROBE','PROBE'}
 row.level1Moves={f.ids.TACKLE};row.learnset={{level=7,move=f.ids.TACKLE}}
 T.eq(P.ready(),true);T.eq(P.speciesOf{species='CHARMANDER'},4)
 T.eq(P.speciesOf{species=277},277);T.eq(P.national(277),252)
 T.eq(P.speciesFromNational(252),277,'cartridge slots and National Dex are distinct')
 T.eq(P.speciesFromName('CHARMANDER'),4);T.eq(P.keyName(4),'CHARMANDER')
 T.eq(P.name(4),'CHARMANDER');T.eq(P.name(8888),nil)
 T.eq(P.types(4)[1],0);T.eq(P.types(4)[2],0)
 T.eq(P.stats(4).atk,row.baseStats.attack)
 local dex=P.dexEntry(4);T.eq(dex.height,7,'metres become source decimetres');T.eq(dex.weight,69)
 local meta=P.speciesMeta(4);meta.genderRatio=0;T.eq(row.genderRatio,127,'observations do not lend native records')
 T.eq(P.gender(4,0),'F');T.eq(P.gender(4,255),'M')
 T.eq(P.abilities(4)[1],1);T.eq(P.abilityId(4,2),1)
 T.eq(P.isShiny{species=4,personality=0,otId=0,otSecretId=0},true)
 T.eq(P.isShiny(setmetatable({},{__index={species=4,personality=0,otId=0,otSecretId=0}})),true,'typed mon views use their declared identity fields')
 T.eq(P.isShiny{species=4,personality=12,otId=0,otSecretId=0},false)
 T.eq(P.isEgg{isEgg=true},true);T.eq(P.isEgg{species=4},false)
 T.eq(P.displayName{species=4,nickname='NAMED'},'NAMED')
 T.eq(P.displayName{species=4},'CHARMANDER')
 local moves,pp,max=P.movesAtLevel(4,10)
 T.eq(moves[1],33);T.eq(pp[1],10);T.eq(max[1],10)
 T.eq(P.moveName(33),'TACKLE');T.eq(P.movePp(33),10)
 T.eq(P.movesLearnedAt(4,7)[1],33)
 T.eq(P.moveIdAt({moves={33}},1),33);T.eq(P.moveIdAt({moves={{id=f.ids.TACKLE}}},1),33)
 T.eq(P.knowsMove({moves={33}},33),true);T.eq(P.knowsMove({moves={33}},34),false)
 Host.currentMod='sprite_owner'
 local image=assert(P.frontPic(4))
 T.eq(P.frontPic(4),image,'native source picture is cached within its dataset')
 T.check(image.image~=nil and image.w>0 and image.h>0)
 T.eq(P.frontPic(4,2),nil,'unsupported forms cannot silently show the base sprite')
 require('src.core.game3.asset_stream').cancelOwner('other_owner')
 T.eq(P.frontPic(4),image)
 P.invalidate();T.neq(P.frontPic(4),image,'owned picture invalidation never reuses its released image')
 Host.currentMod=nil;P.invalidate();f.close()
end
package.loaded['src.core.Game']=original
T.finish('native source Pokemon identity, metadata units and picture ownership')
