-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V,F,H=require('src.core.GameVersion'),require('src.link.Fingerprint'),require('src.link.Handshake')
local Copy=require('src.mods.Merge').deepCopy
local before=V.get();local data=T.fixtures.fresh()
-- Independently audited Python integer FNV: the old raw fixture surface,
-- with only [native_gsc_commands]gsc-1 inserted before its mods domain.
for _,edition in ipairs{'red','gold','firered','crystal','emerald','silver','red'}do
 V.set(edition);local gsc=V.isGen2()
 T.eq(F.compute(data,{}),gsc and '40df18dc503213c8' or 'e33d251961f2a41d','only GSC changes the older host fixture surface')
 T.eq(F.nativeBattleRevision(),gsc and 'gsc-1'or nil,'only GSC advertises new native rules')
 local hello=H.hello({data=data,save={player={name='RULES'}}},'battle')
 T.eq(H.checkCompat(hello,Copy(hello)),'full','matching actual hello admits lockstep')
 if gsc then
  local old=Copy(hello);old.nativeBattleRevision=nil
  T.eq(H.checkCompat(hello,old),'subset','equal-digest old rule field cannot enter lockstep')
  T.eq(H.checkCompat(old,hello),'subset','rule mismatch remains symmetric')
  T.eq(H.checkCompat(hello,{}),'refused','unversioned peer cannot assume changed GSC rules')
  local lines=H.describe(hello,old,'subset','battle')
  T.check(table.concat(lines,' '):find('native battle rules',1,true)~=nil,'visible mismatch describes native rules')
 else
  T.eq(H.checkCompat(hello,{}),'vanilla_peer','other old-host editions retain old wire behavior')
 end
end
V.set(before)
T.finish('older-host native GSC fingerprint cache and actual protocol negotiation')
