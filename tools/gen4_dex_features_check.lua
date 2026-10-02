package.path='./?.lua;'..package.path
local checks=0;local function check(v,s) assert(v,s);checks=checks+1 end
local cries={};package.loaded['src.core.Sound']={playCry=function(_,id) cries[#cries+1]=id end}
package.loaded['src.render.Renderer']={uiPresentation={x=10,y=20,w=512,h=384,scaleX=2,scaleY=2}}
local game={data={pokemon={[387]={name='TURTWIG',forms={alternate={spriteFront='alternate.png'}}}},
 gen4_dex={orders={sinnoh={387}}},maps={one={label='Valid',encounters=1},two={label='Wrong',encounters=2},three={label='Disabled',encounters=3}},
 encounters={[1]={grassRate=40,grass={{level=5,species=387}}},[2]={grassRate=387,grass={{level=387,species=1}}},[3]={grassRate=0,grass={{species=387}}}}},
 save={pokedex={seen={[387]=true},owned={[387]=true},canDetectForms=true}},stack={pop=function() end},input={wasPressed=function(_,k) return k=='a' end}}
local dex=require('src.ui.Gen4Pokedex').new(game)
dex:update();check(dex.page=='entry' and cries[1]==387,'entry opens with numeric species cry')
local areas=dex:areas();check(#areas==1 and areas[1]=='Valid','area search ignores levels/rates and disabled methods')
check(#dex:forms()==1 and dex:forms()[1]==false,'unobserved alternate forms stay hidden')
game.save.pokedex.gen4FormsSeen={[387]={'base','alternate'}}
game.data.pokemon[387].forms.base={spriteFront='base.png'}
check(#dex:forms()==2 and dex:forms()[2]=='alternate','recorded forms preserve encounter order')
game.input.wasPressed=function(_,k) return k=='select' end;dex:update();check(dex.tab==2,'controller page cycling')
dex:touchpressed('mouse',10+120*2,20+180*2);check(dex.tab==3,'scaled mouse opens Cry page')
dex:touchpressed('finger',10+120*2,20+100*2);check(cries[2]==387,'touch replays cry')
dex:touchpressed('finger',10+240*2,20+180*2);check(dex.tab==5,'touch opens Forms')
dex:touchpressed('mouse',10+120*2,20+144*2);check(dex.form==1,'touch cycles alternate forms')
game.input.wasPressed=function(_,k) return k=='b' end;dex:update();check(dex.page=='list','B returns to listing')
print(checks..' Pokedex feature and input checks passed')
