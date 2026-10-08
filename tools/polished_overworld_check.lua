love=love or require('tests.love_stub')
local T=require('tests.harness').suite('Polished overworld events')
local maps=dofile('tmp/polished-voxel-probe/output/data/generated/maps.lua')
local route=maps.ROUTE30
T.eq(route.objects[2].sprite,'SPRITE_MON_016','Pidgey uses its species icon')
T.eq(route.objects[10].frame,2,'fruit tree uses its fixed sheet row')
T.eq(route.objects[10].fruitTree,9,'ROM berry tree ID preserved')
T.eq(route.objects[10].item,'ITEM_068','inline berry item preserved')
T.eq(route.objects[11].item,'ITEM_064','second berry item preserved')
T.eq(route.objects[12].frame,0,'item ball stays a ball after facing changes')
T.eq(route.objects[12].item,'ITEM_029','item ball uses inline ROM item')
T.eq(route.objects[12].quantity,3,'item ball keeps ROM quantity')
local D=require('src.core.Data');D.items=dofile('G:/Gen2Recomped/polishedcrystal/data/generated/items.lua');D.text={};D.field={}
require('src.core.GameVersion').set('polishedcrystal')
local C=require('src.script.Commands');require('src.script.Gen2Commands')
local save=require('src.core.SaveData').newGame();local ctx={game={data=D,save=save},save=save}
local show=C.show_text;C.show_text=function()end
C.g2_fruittree(ctx,9,68)
local got=save.inventory.ITEM_068 or 0
T.check(got>=1 and got<=3,'Polished tree grants its ROM item/count range')
C.g2_fruittree(ctx,9,68)
T.eq(save.inventory.ITEM_068,got,'picked tree cannot grant items twice')
T.check(save.g2FruitTrees[9],'harvest state saved')
C.show_text=show
D.map_scripts={scripts={fruit={{'fruittree',10,64},{'end'}}}}
local compiled=require('src.script.Gen2ScriptVM').compile(D,'fruit')
T.check(compiled~=nil,'two-operand fruit script compiles')
local found=false
for _,row in ipairs(compiled or {})do if row[1]=='g2_fruittree'then found=row[2]==10 and row[3]==64 end end
T.check(found,'compiled fruit script retains berry item operand')
T.finish()
