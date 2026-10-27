-- Native GSC HP presentation over the real shared-engine battlers.
-- Pixel stepping adapts Gen1Recomp src/battle/gen2/HpBar.lua and
-- src/ui/gen2/BattleState.lua; retain their provenance under NOTICE.md.
-- Native-owner integration: Roxas2712 (LICENSE-ROXAS2712.md).
local Hp = {}
local pending = setmetatable({}, {__mode='k'})
local admissions = setmetatable({}, {__mode='k'})
local targets = setmetatable({}, {__mode='k'})
local function battler(screen, side)
  if side=='player' or side=='enemy' then return screen[side] end
end
local function finite(value)
  return type(value)=='number' and value==value and math.abs(value)<math.huge
end
function Hp.pixels(hp, maximum)
  if hp<=0 or maximum<=0 then return 0 end
  local product,divisor=hp*48,maximum
  if divisor>=256 then product=math.floor(product/4);divisor=math.max(1,math.floor(divisor/4))end
  return math.min(48,math.max(1,math.floor(product/divisor)))
end
function Hp.shown(screen, mon, side)
  local shown=screen.shownHp and screen.shownHp[side]
  if shown~=nil then return shown end
  return mon and mon.hp or 0
end
function Hp.fill(screen, mon, side)
  local anim=screen.hpAnim
  if anim and anim.side==side and anim.bar then return anim.bar.px end
  local maximum=mon and (mon.maxHp or mon.stats and mon.stats.hp) or 0
  return Hp.pixels(Hp.shown(screen,mon,side),maximum)
end
local function newBar(from,to,maximum)
  -- A wide presentation may have left a fractional value when its owner
  -- changed. The cartridge loop advances integers and must still terminate.
  from=from>to and math.ceil(from) or math.floor(from)
  return {hp=from,to=to,maximum=maximum,px=Hp.pixels(from,maximum),
    toPx=Hp.pixels(to,maximum),dir=to<from and -1 or 1,
    long=maximum>=48,low=math.min(from,to),high=math.max(from,to)}
end
local function stepBar(bar)
  if bar.long then
    while bar.hp~=bar.to do
      bar.hp=bar.hp+bar.dir
      local px=Hp.pixels(bar.hp,bar.maximum)
      if px~=bar.px then bar.px=px;return false end
    end
    return true
  end
  if bar.px==bar.toPx then return true end
  bar.px=bar.px+bar.dir
  local hp
  if bar.px>=48 then hp=bar.maximum
  elseif bar.px<=0 then hp=0
  else hp=math.floor(bar.maximum*bar.px/48)+1;hp=math.max(bar.low,math.min(bar.high,hp))end
  bar.hp=hp
  return false
end
function Hp.bind(screen)
  screen.shownHp=setmetatable({}, {
    __index=function(_,side)local b=battler(screen,side);return b and b.shownHP end,
    __newindex=function(_,side,value)
      local active=admissions[screen];local b=battler(screen,side)
      assert(active and active.side==side and b==active.battler and b.mon==active.mon,
             'native Gen2 shown HP is owned by stepHPDrain/stepHpAnim')
      local maximum=math.max(1,b.mon.stats.hp)
      assert(finite(value) and value>=0 and value<=maximum,'invalid native Gen2 displayed HP')
      b.shownHP=value
    end,
  })
end
-- This is the actual native display step, called through the public screen
-- method while its queue owns the HP row. It never changes battle damage.
function Hp.step(screen)
  local anim=screen.hpAnim;local active=admissions[screen]
  if not anim then return false end
  assert(active and active.anim==anim,'native Gen2 HP step has no admitted row')
  if not anim.bar then
    anim.bar=newBar(screen.shownHp[anim.side],anim.to,active.mon.stats.hp)
  end
  if (anim.hold or 0)>0 then anim.hold=anim.hold-1;return true end
  if stepBar(anim.bar)then
    screen.shownHp[anim.side]=anim.to;screen.hpAnim=nil;return false
  end
  screen.shownHp[anim.side]=anim.bar.hp;anim.hold=1;return true
end
function Hp.target(screen,b,goal)
  assert(finite(goal) and goal>=0 and goal<=b.mon.stats.hp,
    'invalid native Gen2 displayed HP goal')
  targets[screen]={battler=b,mon=b.mon,hp=goal}
end
local function goalOf(screen,b)
  local target=targets[screen]
  if target and target.battler==b and target.mon==b.mon then return target.hp end
  local goal=b.mon.hp
  if b.drainFloor and b.drainFloor>goal and b.shownHP>=b.drainFloor then goal=b.drainFloor end
  return goal
end
function Hp.drain(screen)
  local selected=screen._gen2HpDrainBattler
  local side
  for _,candidate in ipairs({'player','enemy'})do
    local b=battler(screen,candidate)
    if b and b.shownHP~=nil and (not selected or b==selected)
       and (b.shownHP~=goalOf(screen,b) or pending[screen] and pending[screen].battler==b)then
      side=candidate;break
    end
  end
  if not side then screen.hpAnim=nil;pending[screen]=nil;return false end
  local b=battler(screen,side);local goal=goalOf(screen,b);local active=pending[screen]
  if not active or active.battler~=b or active.mon~=b.mon or active.goal~=goal
     or screen.hpAnim~=active.anim then
    local anim={side=side,to=goal}
    active={side=side,battler=b,mon=b.mon,goal=goal,anim=anim}
    pending[screen]=active;screen.hpAnim=anim
  end
  admissions[screen]=active
  local ok,why=pcall(screen.stepHpAnim,screen)
  admissions[screen]=nil
  if not ok then error(why,0)end
  local anim=screen.hpAnim
  if anim==active.anim and anim.bar and anim.bar.hp~=b.shownHP then
    -- A wider HUD decorated this beat after (or instead of) native stepping.
    -- Its display number is authoritative for presentation. Discard the old
    -- pixel cursor so returning to the cartridge HUD cannot jump backward.
    anim.bar,anim.hold=nil,nil
  end
  -- A decorator cannot release a queued damage beat before its display has
  -- reached that beat's authoritative stop. No second timer or damage loop.
  if b.shownHP==goal and screen.hpAnim==nil then pending[screen]=nil;return false end
  return true
end
function Hp.retire(screen)
  pending[screen],admissions[screen],targets[screen]=nil,nil,nil
  screen.hpAnim=nil;screen._gen2HpDrainBattler=nil
end
return Hp
