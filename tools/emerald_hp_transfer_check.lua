package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald Softboiled and Milk Drink')
require('src.core.GameVersion').set('emerald')
local root='G:/Gen2Recomped/emerald/data/generated/'
local data={constants=assert(loadfile(root..'constants.lua'))(),text=assert(loadfile(root..'text.lua'))(),pokemon={CHANSEY={name='CHANSEY'},RALTS={name='RALTS'}}}
local Party=require('src.ui.Gen3PartyMenu')
local Sound=require('src.core.Sound')
local play=Sound.play;local sounds=0
Sound.play=function() sounds=sounds+1 end
local pressed
local function fixture(maxHp,hp,targetHp)
  local donor={species='CHANSEY',hp=hp,stats={hp=maxHp},moves={{id='SOFTBOILED',pp=10},{id='MILK_DRINK',pp=10}}}
  local target={species='RALTS',nickname='RALTS',hp=targetHp,stats={hp=50}}
  local g={data=data,save={party={donor,target}},input={wasPressed=function(_,key) return pressed==key end}}
  local m=setmetatable({game=g,index=1},Party)
  m.close=function() m.closed=true end
  m.say=function(_,s) m.message=s end
  return m,donor,target
end
for _,move in ipairs({'SOFTBOILED','MILK_DRINK'}) do
  for _,maxHp in ipairs({5,24,100,255}) do
    local cost=math.floor(maxHp/5)
    local m,d,r=fixture(maxHp,cost,10)
    m:useFieldMove(d,move)
    T.eq(m.hpTransferFrom,nil,'refuse exact donor threshold '..move..maxHp)
    T.check(m.message~=nil,'low HP refusal text')
    d.hp=cost+1;m:useFieldMove(d,move)
    T.eq(m.hpTransferFrom,d,'accept above threshold')
    local before=d.hp
    m.index=2;m:choose()
    T.eq(d.hp,before-cost,'donor pays full rounded-down cost')
    T.eq(r.hp,10,'recipient waits for donor drain')
    T.eq(m.heal.mon,d,'donor animates first')
    local last=m.heal.shown
    m:update(1/60)
    if m.heal and m.heal.mon==d then T.check(m.heal.shown<last,'HP drains gradually') end
    for i=1,200 do if not m.heal then break end;m:update(1/60) end
    T.eq(r.hp,math.min(50,10+cost),'recipient capped to max HP')
    T.eq(m.hpTransferFrom,nil,'successful transfer exits target mode')
    T.eq(m.heal,nil,'both animations terminate')
    T.eq(d.moves[1].pp,10,'field transfer spends no PP')
    T.eq(d.moves[2].pp,10,'Milk Drink field transfer spends no PP')
    T.check(m.message:find(tostring(math.min(cost,40)),1,true)~=nil,'restored message reports actual gain')
    T.eq(m.closed,nil,'party stays open')
  end
end
local m,d,r=fixture(100,90,49)
m:beginHpTransfer(d);m:transferHpTo(r)
for i=1,200 do if not m.heal then break end;m:update(1/60) end
T.eq(d.hp,70,'full cost even when recipient needs one point')
T.eq(r.hp,50,'nearly full recipient capped')
T.check(m.message:find('1 point',1,true)~=nil,'actual one-point restoration text')
for _,hp in ipairs({0,50}) do
  m,d,r=fixture(100,90,hp);m:beginHpTransfer(d);m:transferHpTo(r)
  T.eq(d.hp,90,'invalid recipient preserves donor HP')
  T.eq(m.hpTransferFrom,d,'invalid recipient retains picker')
  T.eq(m.heal,nil,'invalid recipient starts no animation')
end
m,d,r=fixture(100,90,10);m:beginHpTransfer(d);m:transferHpTo(d)
T.eq(d.hp,90,'self target refused')
T.eq(m.hpTransferFrom,d,'self target retains picker')
pressed='b';m:update(1/60);pressed=nil
T.eq(m.hpTransferFrom,nil,'B cancels target selection')
T.eq(m.closed,nil,'B keeps party open')
m:beginHpTransfer(d);m.index=3;pressed='a';m:update(1/60);pressed=nil
T.eq(m.hpTransferFrom,nil,'Cancel panel ends transfer selection')
T.eq(m.closed,nil,'Cancel panel keeps party open')
T.check(sounds>0,'native item-use sound dispatched')
Sound.play=play
T.finish()
