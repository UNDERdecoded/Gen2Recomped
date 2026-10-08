package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Polished Game Corner')
require('src.core.GameVersion').set('polishedcrystal')
local D=require('src.core.Data')
D.items=dofile('tmp/polished-voxel-probe/output/data/generated/items.lua')
D.map_scripts=dofile('tmp/polished-voxel-probe/output/data/generated/map_scripts.lua')
D.text={}
local case
for id,def in pairs(D.items)do if def.key=='COIN_CASE' then case=id end end
T.check(case and case:match('^KEY_ITEM_'),'Coin Case lives in separate key-item namespace')
local entry=D.map_scripts.maps.GOLDENROD_GAME_CORNER
T.check(entry.objects[1]~=nil,'coin purchaser has inline standard script')
local compiled=require('src.script.Gen2ScriptVM').compile(D,entry.objects[1])
T.check(compiled and #compiled>3,'coin purchaser script compiles')
local C=require('src.script.Commands');require('src.script.Gen2Commands')
local shown,pushed=0,0
local show=C.show_text;C.show_text=function()shown=shown+1 end
local screens=require('src.ui.Screens');local push=screens.push
screens.push=function()pushed=pushed+1 end
local save={inventory={},coins=100,money=1000}
local ctx={game={data=D,save=save},save=save,g2Var=0}
C.g2_slots(ctx);C.g2_card_flip(ctx)
T.eq(pushed,0,'both games refuse without Coin Case')
T.eq(shown,2,'both games explain Coin Case requirement')
T.eq(save.coins,100,'refusal preserves coins')
save.inventory[case]=1
C.g2_slots(ctx);C.g2_card_flip(ctx)
T.eq(pushed,2,'both games open with Coin Case')
C.show_text=show;screens.push=push
T.finish()
