-- Actual imported native commands through the GSC object/VM owner.
-- Expectations name cartridge behaviour, not a second simulated controller.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Player=require('src.battle.Gen2AnimPlayer')
local Version=require('src.core.GameVersion')
local previous=Version.get()
local function fixture(code,fn,param,frames)
  return {battle_anims={gen2=true,moveAnims={PROBE=1},
    scripts={[1]={entry=1,code=code}},
    functions={[0]=fn or 'Null'},
    objects={[0]={oamFlags=1,fixY=255,frameset=0,fn=0,palette=2,gfx=1}},
    framesets={[0]=frames or {frames={{oam=0,duration=1}},loop='restart'}},
    oam={[0]={tile=0,sprites={{x=0,y=0,tile=0,attr=0}}}},
    gfx={[1]={tiles=1,cols=1,image='native-object'}}}}
end
local function make(fn,param,player,frames,code)
  local p=Player.new(fixture(code or {{op='gfx',ids={1}},
    {op='obj',args={0,64,96,param or 0}},
    {op='delay',frames=200},{op='ret'}},fn,param,frames))
  T.check(p:start('PROBE',player~=false),'actual native imported program starts')
  return p
end
for _,edition in ipairs({'gold','silver','crystal'})do
  Version.set(edition)
  for _,player in ipairs({true,false})do
    local p=make('MoveFromUserToTarget',4,player)
    p:update()
    local r=p.runtime
    local s=r.objects.structs[1]
    T.eq(p.objects,r.objects,'native player exposes actual ten-slot pool')
    T.eq(p.bg,r.objects.hram,'object functions and BG share actual HRAM')
    T.eq(r.env,p.bg.env,'both pools read the same battle environment')
    T.eq(s.func,'BATTLE_ANIM_FUNC_USER_TO_TARGET','imported function name resolves real routine')
    T.eq(s.x,68,'target routine advances PARAM pixels on its first frame')
    T.eq(s.y,94,'target routine advances half as many vertical pixels')
    local row=r:oam()[1]
    T.eq(row.x,player and 68 or 112,'enemy mirror is applied at OAM output, after motion')
    T.eq(row.y,player and 94 or 134,'enemy Y fix is applied at OAM output')
    for _=1,17 do p:update()end
    T.eq(s.x,132,'target routine stops at its cartridge threshold')
    T.eq(s.y,62,'target movement uses actual coordinate state')
    T.eq(s.xOffset,0,'target movement is not an interpolated visual offset')
    for _=1,42 do p:update()end
    T.eq(s.index,1,'restarting frameset object survives beyond former 48-frame cap')
    T.eq(r.frames,60,'only native updates advance the interpreter')
    for _=1,30 do r:oam()end
    T.eq(r.frames,60,'drawing and observation never step the interpreter')
    T.eq(s.index,1,'OAM observation cannot retire an object')
    for _=61,201 do p:update()end
    T.eq(p:isDone(),false,'real anim_wait200 retains all two hundred wait frames')
    p:update()
    T.eq(r.frames,202,'top-level return follows command frame and full wait')
    T.eq(p:isDone(),true,'top-level return is immediately terminal')
    T.eq(#r:oam(),0,'terminal normal animation clears OAM immediately')
    for _=1,25 do p:update()end
    T.eq(r.frames,202,'terminal animation has no arbitrary drain clock')
    local old=r
    p:start('PROBE',not player)
    T.check(old~=p.runtime,'restart creates a distinct real interpreter')
    T.eq(old.frames,202,'retained old interpreter keeps its own time')
    T.eq(old.objects.structs[1],s,'retained consumer keeps actual old object identity')
    p:release()
  end
  do
    local p=make('Null',0,true,nil,{{op='gfx',ids={1}},
      {op='obj',args={0,64,96,0}},{op='delay',frames=1},
      {op='incobj',args={1}},{op='delay',frames=1},{op='ret'}})
    p:update();local s=p.objects.structs[1]
    p:update();T.eq(s.index,1,'wait burns a complete native frame')
    p:update()
    T.eq(s.jt,1,'incobj changes real jump-table state instead of choosing a frameset')
    T.eq(s.index,0,'Null routine deinitializes through its actual state machine')
    T.eq(#p:oam(),1,'deinitializing function still emits OAM on that same frame')
    p:update();T.eq(#p:oam(),0,'the next OAM pass skips the retired slot')
    p:update();T.eq(p:isDone(),true,'no synthetic object-tail delay follows ret')
    p:release()
  end
  do
    local p=make('MoveInCircle',0x88)
    p:update();local s=p.objects.structs[1]
    T.eq(s.param,8,'circle bit7 selects phase, not radius')
    T.eq(s.var1,33,'circle init falls through into its first motion on the same frame')
    T.eq(s.xOffset,248,'half-turn circle offset uses a signed wrapping byte')
    T.eq(s.yOffset,0,'half-turn circle starts on the horizontal diameter')
    p:release()
  end
  do
    local code={{op='gfx',ids={1}}}
    for _=1,11 do code[#code+1]={op='obj',args={0,64,96,0}}end
    code[#code+1]={op='delay',frames=1}
    code[#code+1]={op='clearobjs'}
    code[#code+1]={op='delay',frames=1}
    code[#code+1]={op='ret'}
    local p=make('Null',0,true,nil,code)
    p:update();T.eq(p.objects:activeCount(),10,'hardware pool drops the eleventh object')
    T.eq(p.objects.lastIndex,10,'dropped object does not consume an index')
    p:update();p:update()
    T.eq(p.objects:activeCount(),3,'cartridge ClearObjs preserves slots eight through ten')
    T.eq(p.objects.structs[8].index,8,'retained hardware slot keeps identity')
    p:release()
  end
  do
    local p=make('Null',0,true)
    local sprites=p.runtime.data.oamsets[0].sprites
    for i=2,50 do sprites[i]={x=i-1,y=0,tile=0,attr=0}end
    p:update();T.eq(#p:oam(),40,'shadow OAM is bounded by actual forty-entry hardware limit')
    p:release()
  end
  do
    local p=make('Null',0,true,{frames={{wait=true,duration=1},
      {oam=0,duration=0}},loop='delete'})
    p:update();T.eq(#p:oam(),0,'oamwait emits no sprite on its command frame')
    p:update();T.eq(#p:oam(),0,'oamwait preserves its full duration')
    p:update();T.eq(#p:oam(),1,'next actual frameset row emits its sprite')
    p:update();T.eq(p.objects:activeCount(),0,'oamdelete deinitializes its actual struct')
    p:release()
  end
  do
    local p=make('Null',0,true,nil,{{op='gfx',ids={1}},
      {op='obj',args={0,64,96,0}},{op='delay',frames=1},
      {op='keepsprites'},{op='ret'}})
    p:update();p:update();p:update()
    T.eq(p:isDone(),true,'capture terminal is immediate')
    T.eq(p:oam()[1].palette,'PAL_BATTLE_OB_ENEMY','retained OAM follows native terminal palette rule')
    local kept=p:finalSprites()
    T.eq(kept[1].x,64,'captured terminal keeps the actual final OAM')
    local old=p.runtime;p:start('PROBE',false)
    T.eq(kept.runner,old,'retained ball drawing keeps its genuine runner metadata')
    T.eq(kept[1].x,64,'new animation cannot change the retained ball coordinates')
    p:release()
  end
end
Version.set(previous)
T.finish('native GSC object motion, hardware slots, OAM, waits and terminal ownership')
