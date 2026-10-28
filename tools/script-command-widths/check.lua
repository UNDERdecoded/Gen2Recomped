package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Extractor=require('src.import.RomExtractorGen3')
for _,edition in ipairs({'ruby','emerald','sapphire','firered','leafgreen','ruby','emerald'})do
  local rs=edition=='ruby'or edition=='sapphire'
  local raw=string.char(0x94)..(rs and string.char(1,2)or'')
    ..string.char(0x16,0x75,0x40,42,0,0x95,3,4,1,0x16,0x76,0x40,91,0,0x02)
  local ex=Extractor.new(raw,{id=edition},{})
  local lines,why=ex:decodeScriptAt(0)
  T.eq(why,nil);T.eq(#lines,5,'money arguments cannot shift the next command')
  T.eq(lines[1].name,'hidemoneybox');T.eq(#lines[1].args,rs and 2 or 0)
  T.eq(lines[2].name,'setvar');T.eq(lines[2].args[2],42)
  T.eq(lines[3].name,'updatemoneybox');T.eq(#lines[3].args,3)
  T.eq(lines[3].args[1],3);T.eq(lines[3].args[2],4);T.eq(lines[3].args[3],1)
  T.eq(lines[4].name,'setvar');T.eq(lines[4].args[2],91)
  T.eq(lines[5].name,'end')
end
T.finish('native money command byte widths')
