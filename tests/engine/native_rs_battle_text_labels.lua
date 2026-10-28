-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Text=require('src.core.game3.rom_text')
local oldGame,oldVersion,oldService=package.loaded['src.core.Game'],V.get(),package.loaded['src.translation.Service']
package.loaded['src.translation.Service']=nil
for _,edition in ipairs{'ruby','sapphire'}do
 V.set(edition)
 local row={plain='AP\nTYP/',nativePlain='native legacy',ir={{t='ext',cmd=1,args={5}},
  {t='text',s='AP'},{t='nl'},{t='text',s='TYP/'},{t='eos'}}}
 local catalog={schema=1,edition=edition,romSha1=V.info().sha1,
  named={BattleText_PP='PP',BattleText_SwitchWhich='SWITCH'},
  records={PP=row,SWITCH={plain='Tauschen\nwelche?',ir={{t='text',s='Tauschen'},{t='nl'},{t='text',s='welche?'},{t='eos'}}}}}
 local data={text={PP='native legacy'},text_pointers={namedIR=catalog}}
 package.loaded['src.core.Game']={data=data,save={player={name='QA'}}}
 T.eq(Text.has('gText_MoveInterfacePP'),true)
 T.eq(Text.plain('gText_MoveInterfacePP'),'AP','select the native first line rather than painting TYPE over the following label')
 local ir=Text.ir('gText_MoveInterfacePP');T.eq(ir[1].cmd,1);T.eq(ir[1].args[1],5);T.eq(ir[3].t,'eos');T.eq(Text.plain('gText_MoveInterfaceType'),'TYP/')
 local second=Text.ir('gText_MoveInterfaceType');T.eq(second[1].cmd,1);T.eq(second[2].s,'TYP/')
 ir[1].args[1]=99;T.eq(row.ir[1].args[1],5,'borrowed IR is detached')
 T.eq(Text.plain('gText_BattleSwitchWhich'),'Tauschen\nwelche?')
 data.strings={AP='Localized panel'};T.eq(Text.plain('gText_MoveInterfacePP'),'Localized panel')
 T.eq(Text.ir('gText_MoveInterfacePP')[1].s,'Localized panel');data.strings=nil
 data.text.PP='Edited RS';T.eq(Text.plain('gText_MoveInterfacePP'),'Edited RS')
 data.text.gText_MoveInterfacePP='Explicit canonical';T.eq(Text.plain('gText_MoveInterfacePP'),'Explicit canonical')
 data.text.gText_MoveInterfacePP=nil;data.text.PP=nil
 T.eq(Text.has('gText_MoveInterfacePP'),false,'native record removal cannot resurrect original lettering')
 T.raises(function()Text.plain('gText_MoveInterfacePP')end,'unavailable')
 data.text.PP='native legacy'
 data._romTextGeneration=3;data.romText={};data._romTextTouched={gText_MoveInterfacePP=true}
 T.eq(Text.has('gText_MoveInterfacePP'),false,'explicit canonical prose removal wins over alternate label')
 data.romText.gText_MoveInterfacePP='Canonical prose';T.eq(Text.plain('gText_MoveInterfacePP'),'Canonical prose')
 data.romText={};data._romTextTouched={BattleText_PP=true}
 T.eq(Text.has('gText_MoveInterfacePP'),false,'alternate prose removal remains authoritative')
 data._romTextTouched={};data.romText.BattleText_PP='Edited prose';T.eq(Text.plain('gText_MoveInterfacePP'),'Edited prose')
 data.romText={};data._romTextTouched={}
 catalog.named.gText_WhatWillPkmnDo='DERIVED_PLAYER';catalog.records.DERIVED_PLAYER={plain='player',nativePlain='legacy player',ir={{t='ph',code=32},{t='eos'}}}
 data.text.DERIVED_PLAYER='legacy player'
 catalog.named.BattleText_OtherMenu='ACTIVE';catalog.records.ACTIVE={plain='active',ir={{t='ph',code=15},{t='eos'}}}
 T.eq(Text.ir('gText_WhatWillPkmnDo')[1].code,15,'active-mon prompt does not borrow the distinct player/Safari placeholder')
 T.eq(require('src.core.game3.battle.battle_text').get('gText_WhatWillPkmnDo',{active={mon={nickname='QA MON'}}}),'QA MON')
 data.text.DERIVED_PLAYER='Explicit record edit';T.eq(Text.plain('gText_WhatWillPkmnDo'),'Explicit record edit')
 data.text.gText_WhatWillPkmnDo='Explicit name edit';T.eq(Text.plain('gText_WhatWillPkmnDo'),'Explicit name edit')
 data.text.gText_WhatWillPkmnDo=nil
 catalog.romSha1='wrong';T.eq(Text.has('gText_MoveInterfacePP'),false,'unverified catalogue cannot authorize aliases')
 package.loaded['src.core.Game']={data={text={}}};T.eq(Text.has('gText_MoveInterfacePP'),false,'no retired data retained')
end
for _,edition in ipairs{'firered','leafgreen','emerald','crystal'}do
 V.set(edition);package.loaded['src.core.Game']={data={text={BattleText_PP='other owner'}}}
 T.eq(Text.has('gText_MoveInterfacePP'),false,'RS aliases are edition bounded')
end
package.loaded['src.core.Game']=oldGame;package.loaded['src.translation.Service']=oldService;V.set(oldVersion)
T.finish('native RS line labels, active-mon prompt and switch labels preserve edits, IR and current edition ownership')
