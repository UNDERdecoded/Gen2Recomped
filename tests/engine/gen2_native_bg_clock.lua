-- Exercise real native VM commands and its actual BG register owner.
-- Official main has no Gen2AnimView observation; no substitute runner is installed.
-- Expected picture and LCD traces come from the pinned GSC BG implementation.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Player=require('src.battle.Gen2AnimPlayer')
local Version=require('src.core.GameVersion')
local previous=Version.get()
local function data(code,constants)
  return {constants=constants,battle_anims={gen2=true,moveAnims={PROBE=1},
    scripts={[1]={entry=1,code=code}},objects={},framesets={},oam={},gfx={}}}
end
for _,edition in ipairs({'gold','silver','crystal'})do
  Version.set(edition)
  for _,playerTurn in ipairs({true,false})do
    local p=Player.new(data({
      {op='bgeffect',args={0x0b,0,1,0}},
      {op='delay',frames=13},{op='ret'},
    }))
    T.check(p:start('PROBE',playerTurn),'native VM starts the real test program')
    local r=p
    T.eq(r.bg,p.bg,'observation exposes the actual register owner')
    local ticks=0;local playFrame=p.bg.playFrame
    p.bg.playFrame=function(self,...)ticks=ticks+1;return playFrame(self,...)end
    local side=playerTurn and 'player'or'enemy'
    for frame=1,13 do
      p:update()
      local stage=math.floor((frame-1)/4)
      local expected=stage<3 and((playerTurn and 2 or 5)-stage)or nil
      T.eq(r.bg.picSize[side],expected,'native command/wait path follows four-frame picture stages')
      T.eq(ticks,frame,'one existing VM update executes exactly one BG pass')
      for _=1,20 do local bg,frames=r.bg,r.frames end
      T.eq(ticks,frame,'repeated consumer observations never run the effect')
    end
    p:update();T.eq(ticks,14,'the final command frame executes one BG pass')
    for _=1,20 do p:update()end
    T.eq(ticks,14,'legacy object-tail drain cannot keep advancing a stopped BG program')
    local old=r.bg
    p:start('PROBE',not playerTurn)
    T.eq(old.picSize[side],nil,'previous register block keeps its completed picture trace')
    T.check(p.bg~=old,'restart owns a fresh block rather than mutating retired state')
    T.eq(p.bg.env.battleTurn,playerTurn and 1 or 0,'restart binds the current attacker side')
    T.eq(p.bg.picSize.player,nil,'restart clears player picture stages')
    T.eq(p.bg.picSize.enemy,nil,'restart clears enemy picture stages')
    p:release()
  end
  local p=Player.new(data({{op='bgeffect',args={0x25,0,1,0}},
    {op='delay',frames=4},{op='ret'}}))
  p:start('PROBE',true);p:update()
  local entry=p.bg.effects[1]
  T.eq(entry.func,edition=='crystal'and'BATTLE_BG_EFFECT_BODY_SLAM'or'BATTLE_BG_EFFECT_WOBBLE_MON',
    'raw command resolves through the actual cartridge table')
  local effect=p:pollEffects()[1]
  T.eq(effect and effect.effect,edition=='crystal'and'SE_MOVE_MON_HORIZONTALLY'or'SE_SHAKE_BACK_AND_FORTH',
    'existing visual adapter also resolves Crystal insertion by effect name')
  p:update();p:update()
  if edition=='crystal'then T.eq(p.bg.lyBackup[0x30],0xfe,'real VM drives the signed BODY_SLAM LCD trace')end
  p:release()
  p=Player.new(data({{op='bgeffect',args={0x0f,0,0,0}},
    {op='delay',frames=1},{op='incbgeffect',args={0x0f}},
    {op='bgp',args={0x1ff}},{op='obp0',args={0x18c}},
    {op='obp1',args={0x124}},{op='delay',frames=1},{op='ret'}}))
  p:start('PROBE',true);p:update()
  local active=p.bg.effects[1]
  T.eq(active.jt,1,'native Teleport initializes its running state')
  p:update()
  T.eq(active.func,nil,'increment advances Teleport into its native terminal state')
  T.eq(p.bg.lcdc,nil,'native terminal state retires its LCD window')
  T.eq(p.bg.obp0,0x8c,'native OBJ0 palette command preserves byte semantics')
  T.eq(p.bg.obp1,0x24,'native OBJ1 palette command preserves byte semantics')
  T.eq(p.bg.bgp,0xff,'BG palette write survives a non-palette terminal effect')
  p:release()
  p=Player.new(data({{op='bgp',args={0x1fc}},{op='delay',frames=1},{op='ret'}}))
  p:start('PROBE',true);p:update();T.eq(p.bg.bgp,0xfc,'native BG palette write reaches the register block')
  p:release()
end
Version.set(previous)
T.finish('native GSC BG commands, one-clock stepping and retired observations')
