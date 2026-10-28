-- Real ROM-handler dispatch and script decoder, using synthetic device bytes.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local E=require('src.import.RomExtractorGen2')
local Player=require('src.battle.Gen2AnimPlayer')
local Importer=require('src.import.RomImporter')
local Version=require('src.core.GameVersion')
local previous=Version.get()
-- Older engine bases have the same real readiness gate without the newer
-- public cache descriptor. Seed its genuine marker, never a guessed format.
local markerFor
for i=1,100 do
 local name,value=debug.getupvalue(Importer.readyReport,i)
 if name=='markerFor'then markerFor=value;break end
 if not name then break end
end
assert(markerFor)
for _,edition in ipairs({'gold','silver','crystal'})do
 Version.set(edition)
 local e=E.new(nil,edition,{symbols={BattleAnimCommands={1,0x4000},
  BattleAnimCmd_BattlerGFX_1Row={1,0x4100},
  BattleAnimCmd_BattlerGFX_2Row={1,0x4120}}})
 e.rom={word=function(_,bank,address)
  T.eq(bank,1,'decoder reads actual command-table bank')
  if address==0x4012 then return 0x4100 end
  if address==0x4014 then return 0x4120 end
  return 0
 end,byte=function(_,bank,address)
  return assert(({[0x5000]=0xd9,[0x5001]=0xda,[0x5002]=0xff})[address])
 end}
 local script=e:gen2AnimScript(1,0x5000)
 T.eq(script.code[1].op,'battlergfx_2row','D9 handler retains its crossed macro name')
 T.eq(script.code[2].op,'battlergfx_1row','DA handler retains its crossed macro name')
 local p=Player.new({battle_anims={gen2=true,moveAnims={PROBE=1},scripts={[1]=script}}})
 T.check(p:start('PROBE',true));p:update()
 local r=p.runtime
 T.eq(r.tileDict[1].tile,66,'D9 loads real one-row player-head tile base')
 T.eq(r.tileDict[2].tile,73,'D9 loads real one-row enemy-foot tile base')
 T.eq(r.tileDict[3].tile,53,'DA loads real two-row player-head tile base')
 T.eq(r.tileDict[4].tile,67,'DA loads real two-row enemy-foot tile base')
 T.eq(r.loaded[1].rows,1,'actual loaded descriptor has one row')
 T.eq(r.loaded[3].rows,2,'actual loaded descriptor has two rows')
 p:release()
end
for _,edition in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
 local marker=markerFor(edition)
 T.check(marker:find('gen2%-anim%-object%-v1:')~=nil,'generated animation cache has a new contract')
 Version.set(edition)
 local old=marker:gsub('gen2%-anim%-object%-v1:','')
 love.filesystem.write(Version.cachePrefix(edition)..'rom-cache.complete',old)
 local report=Importer.readyReport(edition)
 T.eq(report.ok,false,'old handler-labelled cache must be rebuilt')
 T.check(report.why and report.why:find('another version',1,true)~=nil,
  'real readiness gate refuses the old format before checking file gaps')
end
for _,edition in ipairs({'red','emerald','platinum'})do
 T.check(not markerFor(edition):find('gen2%-anim%-object'),
  'unrelated cartridge cache contract is retained')
end
Version.set(previous)
T.finish('native GSC crossed battler-row handler import and legacy-cache refusal')
