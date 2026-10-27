-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Battle=require('src.core.game3.battle')
local Chrome=require('src.ui.game3.battle_chrome')
local Health=require('src.core.game3.battle.healthbox')
local Native=require('src.battle.Gen3Battle')
local originalGame=package.loaded['src.core.Game']
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Battle._service.release()
 local f=require('tools.battle-source-runtime.fixture').new(edition);local g=f.game;package.loaded['src.core.Game']=g
 local c=g.data.constants
 c.gen3BattleWindows={message={left=2,top=15,width=26,height=4},prompt={left=1,top=15,width=14,height=4},action={left=16,top=15,width=13,height=4},moves={}}
 for i=1,4 do c.gen3BattleWindows.moves[i]={left=1+(i-1)%2*9,top=15+math.floor((i-1)/2)*2,width=8,height=2}end
 c.gen3BattleTextbox={images={},text={message={foreground={12,34,56},shadow={90,80,70}}}}
 c.gen3BattleAnimGfx={PROBE={image='tests/fixture_data/assets/fixmon_a_front.png',frameWidth=8,frameHeight=8,frames=1}}
 g.data.moves.MOVE_033.anim={duration=8,events={{at=0,sheet='PROBE',x=3,y=5,target=true,subpriority=40}}}
 local b=f.fresh('TACKLE').battle;b.enter=false;g.stack:push(b)
 local st=Battle.getState()
 local present=require('src.core.game3.battle.anim').present(0)
 b.player.mon.status='PAR';b.player.shownStatus=nil;T.eq(present.displayStatus,false,'a queued future ailment is not shown early')
 b.player.shownStatus='PSN';T.eq(present.displayStatus,8);b.player.mon.status=nil;T.eq(present.displayStatus,8,'shown ailment survives logical cure until the native queue displays it')
 b.player.shownStatus=false;T.eq(present.displayStatus,false)
 T.eq(Chrome.layout(),(edition=='ruby'or edition=='sapphire')and'rs'or edition=='emerald'and'emerald'or'frlg')
 local w=Chrome.window(0);T.eq(w.x,16);T.eq(w.y,120);T.eq(w.w,26);w.left=999;T.eq(c.gen3BattleWindows.message.left,2)
 local x,y,width,narrow=Chrome.textOrigin(3);T.eq(x,8);T.eq(y,121);T.eq(width,64);T.eq(narrow,true)
 T.eq(Chrome.window(14),nil,'unimported windows are not fabricated')
 local originalWidth=b.gen3SurfaceWidth;b.gen3SurfaceWidth=function()return 320 end
 T.eq(Chrome.window(2).x,16*8+80,'action text follows the native right edge')
 T.eq(Chrome.window(0).w,36,'message width follows the actual native surface')
 T.eq(Chrome.window(3).x,8,'move names retain the native left edge');b.gen3SurfaceWidth=originalWidth
 T.raises(function()Chrome.window(0/0)end,'invalid battle window')
 local fg,shadow=Chrome.textboxColors();T.eq(fg[1],12/255);T.eq(shadow[3],70/255)
 local base=Chrome.drawPanel;local native=Native.drawPanel;local draws=0
 Native.drawPanel=function(screen,mode)T.eq(screen,b);T.eq(mode,'action');draws=draws+1;return true end
 T.eq(base('menu'),true);T.eq(draws,1)
 Chrome.drawPanel=function(mode)T.eq(mode,'menu');base(mode);return base(mode)end
 local body=0;T.eq(Chrome._panel(b,'action',function()body=body+1;return true end),true);T.eq(body,1,'nested bases consume one native panel phase')
 Chrome.drawPanel=function()love.graphics.push();error('owned panel failure')end
 T.raises(function()Chrome._panel(b,'action',function()end)end,'owned panel failure')
 Chrome.drawPanel=base;Native.drawPanel=native
 local geometry=Health.center(st,0);T.check(geometry~=nil);local realGeometry=Native.healthboxGeometry
 local hx,hy=Native.healthboxGeometry(b,0);T.eq(geometry.x,hx+32);T.eq(geometry.y,hy+16)
 T.eq(Health.center({},0),nil);T.eq(Health.draw(0,{}),false,'a foreign battler cannot paint the resident')
 local healthBase=Health.draw;local count,wrappers=0,0
 Health.draw=function(id,view,opts)wrappers=wrappers+1;T.eq(id,0);T.eq(view,st.player);T.eq(opts.st,st);healthBase(id,view,opts);return healthBase(id,view,opts)end
 Health._nativeDraw(b,b.player,hx,hy,true,function()count=count+1;return true end);T.eq(count,1,'healthbox bases consume one native painter');T.eq(wrappers,1,'native HUD dispatch actually enters the source wrapper')
 Health.draw=healthBase
 local Pic=require('src.core.game3.battle.pic_coords')
 g.data.pokemon.CHARMANDER.frontPicCoords={yOffset=13};g.data.pokemon.CHARMANDER.backPicCoords={yOffset=7};c.gen3Elevation={CHARMANDER=4}
 T.eq(Pic.front[4],13);T.eq(Pic.back[4],7);T.eq(Pic.elev[4],4)
 g.data.pokemon.CHARMANDER.frontPicCoords.yOffset=2;T.eq(Pic.front[4],2,'native metadata changes are live')
 T.raises(function()Pic.front[4]=20 end,'read-only')
 local Sprites=require('src.core.game3.battle.anim_sprites');local Anim=require('src.core.game3.battle.anim')
 T.eq(Anim.launchMove(33),true)
 local pool=Sprites._pool;T.eq(#pool,1);T.eq(Sprites._pool,pool)
 local row=pool[1];local anim=b.gen3Anim;local event=anim.events[1]
 local pose=anim:eventPose(event,b,Native);T.eq(row.x,pose.centreX+pose.dx);T.eq(row.y,pose.centreY+pose.dy)
 T.eq(row.active,true);T.eq(row.tag,'PROBE');T.eq(row.subpriority,40)
 local frame=anim.frame;Sprites.forEachActive(function(p)T.eq(p,row)end);T.eq(anim.frame,frame,'particle inspection cannot advance its native clock')
 local paints=0;local painter=anim.drawEventBody
 anim.drawEventBody=function()paints=paints+1;return 'native particle'end
 row.visible=false;T.eq(anim:drawEvent(event,b,Native,{}),true);T.eq(paints,0)
 row.visible=true;row.x=row.x+9;T.eq(anim:drawEvent(event,b,Native,{}),'native particle');T.eq(paints,1)
 row.x=0/0;T.raises(function()anim:drawEvent(event,b,Native,{})end,'invalid particle presentation')
 row.x=pose.centreX+pose.dx
 local host=require('src.mods.Runtime');host.currentMod='particle_owner';T.eq(Sprites._pool,pool);host.currentMod=nil
 require('src.core.game3.asset_stream').cancelOwner('particle_owner');T.eq(row.active,false);T.eq(anim.frame,frame,'view retirement preserves native playback')
 anim.drawEventBody=painter;b.gen3AnimPlaying=false;T.eq(#Sprites._pool,0)
 b.result='run';b:finish();Battle._service.release();T.eq(Health.draw(0,st.player),false,'a retired capture cannot draw its old resident')
 f.close();require('src.core.Game3').release()
end
package.loaded['src.core.Game']=originalGame
T.finish('native battle windows, panel phases, healthbox geometry and imported picture metadata')
