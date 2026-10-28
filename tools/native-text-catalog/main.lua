-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
io.stdout:setvbuf('no')
local root=assert(os.getenv('NATIVE_TEXT_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)print(debug.traceback(tostring(err),2));return function()return 1 end end
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
function love.load()
 assert(love.graphics==nil,'windowless cartridge fixture must not initialize graphics')
 local J=require('src.link.Json');local V=require('src.core.GameVersion')
 local X=require('src.import.RomExtractorGen3');local C=require('src.import.Gen3TextCatalog')
 local inputs=J.decode(read(assert(os.getenv('NATIVE_TEXT_INPUTS'))))
 local result={editions={},playerProfilesUsed=false,gpu=false,fullGameplay=false}
 for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  V.set(edition)
  local manifest=J.decode(read(root..'/'..V.info().manifest))
  local raw=read(assert(inputs[edition]))
  local x=X.new(raw,V.info(),manifest)
  local catalog,count=C.extract(x,{})
  assert(catalog,count);assert(count>1000,'named cartridge catalogue is unexpectedly incomplete')
  assert(catalog.battle and catalog.battle.count>=351,'native battle table is absent')
  local records,controls,placeholders=0,0,0
  for id,row in pairs(catalog.records)do
   records=records+1
   assert(row.address>=0 and row.address+row.bytes<=#raw)
   assert(row.ir[#row.ir].t=='eos','unterminated named text')
   for _,node in ipairs(row.ir)do
    if node.t=='ext'then controls=controls+1
    elseif node.t=='ph'then placeholders=placeholders+1 end
   end
  end
  -- Round-trip the same additive metadata emitted in text_pointers. No
  -- generated table, art, save or ROM is written into the source checkout.
  local encoded=require('src.import.LuaWriter').encodeSplit(catalog)
  local restored=assert(loadstring(encoded,'@native-text-catalog'))()
  local game={data={text={},text_pointers={namedIR=restored},constants={}}}
  package.loaded['src.core.Game']=game
  local Text=require('src.core.game3.rom_text')
  local sample
  for label in pairs(restored.named)do
   if label:match('^gText_MoveInterfacePP$')or label:match('^BattleText_Critical$')then sample=label;break end
  end
  assert(sample,'no native battle vocabulary found')
  assert(Text.has(sample));assert(type(Text.plain(sample))=='string')
  local BattleText=require('src.core.game3.battle.battle_text')
  assert(BattleText.has(13),'native EXP template was not indexed')
  local expanded=BattleText.get(13,{buff1='QA_MON',buff2='QA_BOOST',buff3=123})
  assert(expanded:find('QA_MON',1,true)and expanded:find('QA_BOOST',1,true)and expanded:find('123',1,true),'battle buffer namespace was confused with field placeholders')
  local nodes=Text.ir(sample);assert(nodes[#nodes].t=='eos')
  result.editions[edition]={sha1=catalog.romSha1,labels=count,records=records,
   battle=catalog.battle,battleExpansion=true,controls=controls,placeholders=placeholders,cacheBytes=#encoded,roundTrip=true,sample=sample}
  local Parts=require('src.import.Gen3SummaryParts')
  local spec=manifest.summaryPresentation or Parts.ROMS[Parts.romKey(x.rom)]
  local summary={nativeProfile=spec~=nil,paletteAvailable=false}
  if spec then
   assert(spec.game==edition,'foreign native summary profile')
   local files,parts=Parts.resources(x.rom,spec.offsets,spec.game)
   game.data.constants.gen3Summary={parts=parts}
   local colors=require('src.ui.game3.summary_chrome').manifest()
   summary.paletteAvailable=colors~=nil
   if parts.palette and parts.textColors then
    assert(colors and colors.moveTextColors[12],'native PP palette was lost')
    local selected=require('src.ui.Gen3SummaryLayout').ppColor(30,30)
    local native=parts.palette[128+parts.textColors[selected*3+2]]
    assert(math.abs(colors.moveTextColors[selected].fg[1]/255-native[1])<1e-12)
    summary.nativePaletteMatches=true
   else assert(colors==nil,'an absent native PP palette was invented')end
  end
  result.editions[edition].summary=summary
  if edition=='firered'then
   local menu=assert(restored.records[restored.named.gText_BattleMenu])
   local gaps,lines=0,0
   for _,node in ipairs(menu.ir)do
    if node.t=='ext'and node.cmd==19 then gaps=gaps+1;assert(node.args[1]>0)end
    if node.t=='nl'then lines=lines+1 end
   end
   assert(gaps==2 and lines==1,'the real battle menu lost a native column or row boundary')
   x.rom.data=string.char((raw:byte(1)+1)%256)..raw:sub(2)
   assert(C.extract(x,{})==nil,'fingerprint-negative cartridge was accepted')
   result.fingerprintNegative=true
  end
  print('NATIVE_TEXT_EDITION',edition,count,records,controls,placeholders)
  package.loaded['src.core.Game']=nil
 end
 result.pass=true
 local f=assert(io.open(assert(os.getenv('NATIVE_TEXT_RESULT')),'w'));f:write(J.encode(result));f:close()
 print('NATIVE_TEXT_CATALOG_OK');love.event.quit(0)
end
