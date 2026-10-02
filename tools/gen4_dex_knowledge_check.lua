-- Exercise the real Platinum cache and screen rendering with deterministic
-- text/image captures; no hardware or screenshot comparisons are implied.
package.path='./?.lua;'..package.path
local count=0
local function check(value,why) assert(value,why);count=count+1 end
local dataset=arg[1] or 'G:/Gen2Recomped/platinum'
local function load(name) return assert(loadfile(dataset..'/data/generated/'..name..'.lua'))() end
local texts,draws,cries={},{},{}
local Font={draw=function(s,x,y) texts[#texts+1]={text=s,x=x,y=y} end,
 width=function(s) return #s*6 end,fit=function(s) return s end}
package.loaded['src.render.Font']=Font
package.loaded['src.core.Logger']={warn=function() end}
package.loaded['src.core.Sound']={playCry=function(_,id) cries[#cries+1]=id;return {stop=function() end} end}
package.loaded['src.render.Assets']={image=function(path)
 local w,h=80,80
 if path:find('type_icons_') then w,h=48,16 end
 if path:find('footprint_') then w,h=16,16 end
 return {path=path,setFilter=function() end,getDimensions=function() return w,h end,
 getWidth=function() return w end,getHeight=function() return h end}
end}
love={graphics={setColor=function() end,rectangle=function() end,draw=function(image,x,y,rotation,sx,sy,ox,oy)
 draws[#draws+1]={path=image.path,x=x,y=y,ox=ox,oy=oy}
end}}
local data={pokemon=load('pokemon'),constants=load('constants'),gen4_dex=load('gen4_dex'),gen4_graphics=load('gen4_graphics')}
local pressed
local game={data=data,save={pokedex={seen={[387]=true,[390]=true},owned={[387]=true}}},
 input={wasPressed=function(_,key) return key==pressed end},stack={pop=function() end}}
local Dex=require('src.ui.Gen4Pokedex')
local dex=Dex.new(game)
check(#dex.entries==4 and dex.entries[1]==387 and dex.entries[4]==390,'Sinnoh blanks stop after last encounter')
pressed='a';dex:update()
check(dex.page=='entry' and cries[1]==387,'known entry opens')
pressed='right';dex:update()
check(dex:species()==390,'entry right skips two unseen evolution stages')
pressed='left';dex:update()
check(dex:species()==387,'entry left skips unseen entries')
local function hasText(s)
 for _,v in ipairs(texts) do if v.text==s then return v end end
end
local function imagePart(part)
 for _,v in ipairs(draws) do if v.path:find(part,1,true) then return v end end
end
texts,draws={},{};dex:drawDetails()
check(hasText(data.gen4_dex.height[387]) and hasText(data.gen4_dex.weight[387]),'caught measurements visible')
local category=hasText(data.gen4_dex.category[387])
check(category and category.x==114+math.max(0,math.floor((136-Font.width(category.text))/2)),'category centered in native box')
local categoryBox=imagePart('type_icons_17')
check(categoryBox and categoryBox.x==192 and categoryBox.y==52 and categoryBox.ox==86 and categoryBox.oy==36,'category background uses native OAM origin rather than crop center')
local footprint=imagePart('footprint_387')
check(footprint and footprint.x==120 and footprint.y==88 and footprint.ox==8,'native footprint anchor')
local badge=imagePart('type_icons_02')
check(badge and badge.x==170 and badge.y==72 and badge.ox==24,'native Grass badge anchor')
check(not imagePart('type_icons_01'),'single type does not duplicate badge')
dex:move(1);texts,draws={},{};dex:drawDetails()
check(not hasText(data.gen4_dex.height[390]) and not hasText(data.gen4_dex.weight[390]),'seen measurements concealed')
check(not hasText(data.gen4_dex.category[390]),'seen category concealed')
local typeBadge=false
for i=0,16 do if imagePart(('type_icons_%02d'):format(i)) then typeBadge=true end end
check(not imagePart('footprint_') and not typeBadge,'seen footprint and types concealed')
check(not hasText(data.pokemon[390].dexEntry),'seen description concealed')
check(not dex:tabAvailable(4) and not dex:tabAvailable(5),'seen size and unupgraded forms locked')
dex.tab=3;pressed='r';dex:update();check(dex.tab==1,'controller skips locked size and form pages')
game.save.pokedex.canDetectForms=true;dex.tab=3;dex:update()
check(dex.tab==5,'form upgrade enables its controller page')
dex.tab=5;pressed='l';dex:update();check(dex.tab==3,'reverse navigation skips locked size')
game.save.pokedex.canDetectForms=false;dex:move(-1);dex.tab=4;dex:move(1)
check(dex.tab==1,'moving to seen species exits caught-only size page')
package.loaded['src.render.Renderer']={uiPresentation={x=0,y=0,w=256,h=192,scaleX=1,scaleY=1}}
dex:touchpressed('finger',185,180);check(dex.tab==1,'touch cannot open uncaught size')
dex:touchpressed('mouse',240,180);check(dex.tab==1,'mouse cannot open locked forms')
-- Numeric and symbolic save keys both contribute to knowledge.
game.save.pokedex={seen={SPECIES_387=true},owned={SPECIES_390=true}}
dex=Dex.new(game)
check(dex:status(387)=='seen' and dex:status(390)=='owned','symbolic knowledge keys')
game.save.pokedex={seen={},owned={}};dex=Dex.new(game)
check(#dex.entries==0,'empty Dex remains empty')
dex:move(1);local old=#cries;dex:playCry();check(#cries==old,'no cry for missing/unseen species')
-- Default display follows the first seen form; type properties follow that
-- form's personal record, and Origin Giratina uses the native blank footprint.
game.save.pokedex={national=true,seen={[487]=true},owned={[487]=true},canDetectForms=true,gen4FormsSeen={[487]={'origin','base'}}}
dex=Dex.new(game);dex.index=#dex.entries;dex.page='entry'
check(dex:displayMon().form=='origin','first encountered form is default')
texts,draws={},{};dex:drawDetails()
check(imagePart('/otherpoke/giratina_origin') or imagePart('origin'),'default sprite uses Origin form')
check(imagePart('footprint_011') and not imagePart('footprint_487'),'Origin footprint uses Metapod blank resource')
check(imagePart('type_icons_07') and imagePart('type_icons_16'),'dual form-dependent type icons')
-- Native multiline text has one shared left edge based on the widest line.
local original=data.pokemon[487].dexEntry;data.pokemon[487].dexEntry='LONG LINE\nSHORT'
texts={};dex:drawEntry();local a,b=hasText('LONG LINE'),hasText('SHORT')
check(a and b and a.x==b.x and a.x==101,'multiline description aligns as a single text block')
data.pokemon[487].dexEntry=original
-- Older imports without Dex assets remain usable on caught size pages.
data.gen4_dex=nil;game.save.pokedex={owned={[387]=true}};dex=Dex.new(game);dex.tab=4;dex.page='entry'
check(pcall(function() dex:drawDetails() end),'old cache size page does not index absent metadata')
print(count..' Platinum Dex knowledge, native text, type/footprint and default-form checks passed')
