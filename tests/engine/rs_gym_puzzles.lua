package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local C=require('src.script.Gen3Commands')
local J=require('src.link.Json')
local f=io.open('tools/rom_manifest_ruby.json') or assert(io.open('tools/rom_manifest_sapphire.json'));local m=J.decode(f:read('*a'));f:close()
T.eq(m.specialRemap[140],142,'RS beam toggle maps to native handler')
T.eq(m.specialRemap[141],143,'RS switch handler maps by identity')
T.eq(m.specialRemap[145],147,'RS gym deactivation maps by identity')
T.eq(m.specialRemap[146],148,'RS sliding doors map by identity')
T.eq(m.specialRemap[147],149,'RS instant doors map by identity')
T.same(m.mauvilleGym.SWITCHES,{{0,9},{8,11},{4,15}},'RS has its own three switches')
local blocks,solid={},{}
local function key(x,y)return x..':'..y end
local map={blockAt=function(_,x,y)return blocks[key(x,y)] end,
 setBlock=function(_,x,y,tile,shut) blocks[key(x,y)]=tile;solid[key(x,y)]=shut end}
local ctx={save={},overworld={map=map},game={data={constants={gen3MauvilleGym=m.mauvilleGym}}}}
C.setVar(ctx.save,0x8004,1)
C.SPECIALS[143](ctx)
T.eq(blocks['0:9'],0x205,'first RS switch raised')
T.eq(blocks['8:11'],0x206,'selected RS switch pressed')
T.eq(blocks['4:15'],0x205,'third RS switch raised')
T.eq(blocks['0:15'],nil,'Emerald switch is not written into RS')
blocks['1:7']=0x220;blocks['1:8']=0x228
T.eq(C.SPECIALS[142](ctx),2,'both beam halves toggle')
T.eq(blocks['1:8'],0x238,'bottom beam becomes unlit')
T.eq(solid['1:8'],false,'unlit bottom beam is passable')
C.SPECIALS[142](ctx)
T.eq(blocks['1:8'],0x228,'second toggle restores lit beam')
T.eq(solid['1:8'],true,'lit bottom beam blocks walking')
C.SPECIALS[147](ctx)
T.eq(blocks['1:8'],0x238,'victory disables beam')
for _,at in ipairs(m.mauvilleGym.SWITCHES) do
 T.eq(blocks[key(at[1],at[2])],0x206,'victory presses every RS switch')
end
T.eq(C.mauvilleProfile({game={data={constants={}}}}),C.MAUVILLE,'existing Emerald imports retain original contract')
C.setVar(ctx.save,0x8004,1)
C.SPECIALS[149](ctx)
T.eq(blocks['1:104'],0x21C,'Petalburg upper door reaches final frame')
T.eq(blocks['1:105'],0x224,'Petalburg lower door uses its own row')
T.eq(solid['1:104'],true,'visual door cell retains native collision')
T.finish('RS gym special aliases, switches, beams and doors')
