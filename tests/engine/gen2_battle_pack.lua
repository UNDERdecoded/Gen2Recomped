package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Pack=require('src.ui.Gen2PackMenu')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Bag=require('src.inventory.Bag')
local Screens=require('src.ui.Screens')
local oldVersion=V.get()
local Sound=require('src.core.Sound');local soundPlay=Sound.play;local heals=0
Sound.play=function(data,name,...)
  if name=='Heal_HP'or name=='Sfx_Potion'then heals=heals+1 end
  return soundPlay(data,name,...)
end

local function fixture(version, itemId)
  V.set(version);Screens.invalidate()
  local data=T.fixtures.fresh();data.constants.gen=V.generation()
  itemId=itemId or 'POTION'
  data.items[itemId]={id=itemId,name=itemId,index=18,pocket='ITEM',battleMenu='ITEMMENU_PARTY'}
  require('src.render.Font').load(data)
  local save=Save.newGame();save.options.battleAnimations=false
  save.party={Pokemon.new(data,'FIXMON_A',30)}
  Bag.add(save,itemId,1,data)
  local input={pressed={}}
  function input:wasPressed(key)return self.pressed[key]==true end
  function input:isDown()return false end
  local stack={states={}}
  function stack:top()return self.states[#self.states]end
  function stack:push(s)self.states[#self.states+1]=s end
  function stack:pop()return table.remove(self.states)end
  local world={useFieldItem=function()error('battle PACK reached field effects')end}
  local game={data=data,save=save,input=input,stack=stack,overworld=world,world=world}
  local b=Battle.newWild(game,'FIXMON_C',3)
  b.phase,b.queue,b.current,b.introSlide,b.sendingOut='menu',{},nil,0,false
  b.player.mon.hp=1;b.player.shownHP=1
  b.enemy.mon.moves={{id='FIX_TACKLE',pp=35}};b.enemy.curMoves=b.enemy.mon.moves
  stack:push(b)
  local function step(key)
    input.pressed=key and{[key]=true}or{}
    stack:top():update(1/60)
    input.pressed={}
  end
  local function untilTrue(predicate)
    for tick=1,8000 do
      if predicate()then return true end
      local top=stack:top()
      local key;if not(top==b and b.phase=='menu')then key='a'end
      step(key)
    end
    return false
  end
  local function open()
    for i,choice in ipairs(b:menuActions())do if choice=='item'then b.menuIndex=i end end -- fixture starts at native ITEM
    step('a')
    T.check(untilTrue(function()return stack:top()~=b end),'actual ITEM input opens a child screen')
    return stack:top()
  end
  return b,game,step,untilTrue,open
end

for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
  local b,game,step,wait,open=fixture(version)
  local pp,enemyPP=b.player.curMoves[1].pp,b.enemy.curMoves[1].pp
  local pack=open()
  T.eq(getmetatable(pack),Pack,version..' opens the actual native Gen2 PACK controller')
  T.eq(pack.screenId,'Gen2PackMenu','native screen identity matches the Gen2 contract')
  if getmetatable(pack)==Pack then
    T.eq(pack:inBattle(),true,'native PACK uses battle eligibility')
    T.neq(pack.world,game.overworld,'battle PACK cannot invoke the live field world')
    T.eq(type(pack.onChoose),'function','native PACK has a native item-selection continuation')
    T.eq(pack.rows[1].id,'POTION','rows come from the actual native bag')
    local pocket=pack.pocketIndex
    step('right');T.neq(pack.pocketIndex,pocket,'actual input switches native pockets')
    step('left');T.eq(pack.pocketIndex,pocket,'actual input returns to the item pocket')
    step('b')
    T.check(wait(function()return game.stack:top()==b and b.phase=='menu'end),'native cancel releases the queued UI owner')
    T.eq(game.save.inventory.POTION,1,'cancel keeps inventory')
    T.eq(b.player.mon.hp,1,'cancel cannot heal or spend a turn')
    T.eq(b.player.curMoves[1].pp,pp,'cancel keeps move PP')
    pack=open();step('a') -- native USE row
    if game.stack:top()==pack and pack.submenu then step('a')end
    T.check(game.stack:top()~=pack,'actual USE opens native target selection')
    local picker=game.stack:top()
    T.eq(game.stack.states[#game.stack.states-1],b,'target is built directly over the actual native battle')
    T.eq(picker.battle,b,'target receives the actual battle context')
    T.eq(pack.closed,true,'native PACK has released its owner before target selection')
    local pocket=pack.pocketIndex
    step('b')
    T.check(wait(function()return game.stack:top()~=b end),'target cancellation reopens native PACK')
    pack=game.stack:top()
    T.eq(getmetatable(pack),Pack,'cancel constructs the actual native PACK again')
    T.eq(pack.pocketIndex,pocket,'cancel preserves the native pocket cursor')
    T.eq(game.save.inventory.POTION,1,'target cancellation consumes no item')
    T.eq(b.player.mon.hp,1,'target cancellation changes no HP')
    T.eq(b.enemy.curMoves[1].pp,enemyPP,'target cancellation grants no enemy action')
    step('a');if game.stack:top()==pack and pack.submenu then step('a')end
    picker=game.stack:top()
    local beforeCue=heals
    step('a') -- choose the actual first party Pokemon
    T.eq(heals,beforeCue+1,'native healing plays its imported cue exactly once')
    local resultOwner=game.stack:top()
    T.eq(resultOwner,picker,'successful medicine retains the actual native party controller')
    T.check(resultOwner.itemResult~=nil,'native party owns the result until confirmation')
    T.eq(b.enemy.curMoves[1].pp,enemyPP,'enemy cannot act before native result confirmation')
    if resultOwner.itemResult then
      local targetHP=b.player.mon.hp
      T.eq(resultOwner.itemResult.shown,1,'native HP display starts at pre-effect HP')
      T.eq(resultOwner.itemResult.target,targetHP,'native result targets the actual healed HP')
      for tick=1,12 do step('a') end
      T.eq(game.stack:top(),resultOwner,'early A cannot skip HP fill or native result delay')
      T.eq(b.enemy.curMoves[1].pp,enemyPP,'early confirmation cannot spend an extra enemy turn')
      T.eq(b.player.mon.hp,targetHP,'presentation never rewrites real HP')
      T.check(wait(function()return game.stack:top()==b end),'native acknowledgment releases only the party owner')
      T.eq(b.player.shownHP,targetHP,'battle resumes with the HP already displayed by the native party result')
      T.eq(b.phase,'resolving','actual native acknowledgment resumes the committed turn queue')
      T.eq(b.enemy.curMoves[1].pp,enemyPP,'enemy action starts after actual acknowledgment, not during its callback')
      T.eq(b.partyItemHealing,nil,'result acknowledgment releases low-health alarm suppression')
    end
    T.check(wait(function()return game.stack:top()==b and b.phase=='menu'end),'actual item turn returns to the battle owner')
    T.eq(game.save.inventory.POTION,nil,'actual healing consumes exactly the owned potion')
    T.check(b.player.mon.hp>1,'actual native item effect heals the chosen party Pokemon')
    T.eq(b.player.curMoves[1].pp,pp,'item use does not spend a move PP')
    T.eq(b.enemy.curMoves[1].pp,enemyPP-1,'item use gives the native enemy exactly one action')
    T.eq(game.stack:top(),b,'item/target/message screens leave no orphaned owner')
  end
end
for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
  local b,game,step,wait,open=fixture(version)
  b.player.mon.hp=b.player.mon.stats.hp;b.player.shownHP=b.player.mon.hp
  local enemyPP=b.enemy.curMoves[1].pp
  local pack=open();step('a');if game.stack:top()==pack and pack.submenu then step('a')end
  step('a')
  T.eq(game.stack:top(),b,version..' no-effect medicine uses the actual battle text owner')
  T.check(wait(function()return game.stack:top()==b and b.phase=='menu'end),'no-effect medicine returns to native commands')
  T.eq(game.save.inventory.POTION,1,'no-effect medicine preserves inventory')
  T.eq(b.enemy.curMoves[1].pp,enemyPP,'no-effect medicine grants no enemy action')
end
-- Other native party item families must use the same result owner. Their
-- actual effects, inventory and enemy continuation remain the shared engine's.
for _,id in ipairs({'FULL_HEAL','REVIVE','ETHER','ELIXER','MYSTERYBERRY'})do
  local b,game,step,wait,open=fixture('crystal',id)
  local target=b.player.mon
  target.hp=target.stats.hp;b.player.shownHP=target.hp
  if id=='REVIVE'then
    target=Pokemon.new(game.data,'FIXMON_B',30);target.hp=0
    game.save.party[2]=target
  elseif id=='FULL_HEAL'then target.status='PSN'
  else target.moves[1].pp=1 end
  local enemyPP=b.enemy.curMoves[1].pp
  local pack=open();step('a');if game.stack:top()==pack and pack.submenu then step('a')end
  local picker=game.stack:top()
  if id=='REVIVE'then step('down')end
  step('a')
  if id=='ETHER'or id=='MYSTERYBERRY'then
    T.neq(game.stack:top(),picker,'ETHER opens its real move selector above the same party')
    T.eq(game.stack:top().screenId,'Gen2MoveDeleter','native ETHER uses the cartridge move-list controller')
    step('b');T.eq(game.stack:top(),picker,'PP move cancel returns to the retained native party')
    T.eq(game.save.inventory[id],1,'PP move cancellation preserves inventory')
    T.eq(target.moves[1].pp,1,'PP move cancellation preserves PP')
    T.eq(b.enemy.curMoves[1].pp,enemyPP,'PP cancellation spends no enemy action')
    step('a');step('a')
  end
  T.eq(game.stack:top(),picker,id..' keeps the original native result owner')
  T.check(picker.itemResult~=nil,id..' exposes actual native result state')
  T.eq(picker.party[ picker.index ],target,'result keeps the selected real party Pokemon')
  T.eq(game.save.inventory[id],nil,'successful native item consumes one owned copy')
  T.eq(b.enemy.curMoves[1].pp,enemyPP,'item effect alone cannot start an enemy turn')
  if picker.itemResult then
    local hp=target.hp;local pp=target.moves[1].pp
    for tick=1,50 do step()end
    T.eq(game.stack:top(),picker,'time alone does not confirm the party result')
    T.eq(target.hp,hp,'result hold preserves real HP')
    T.eq(target.moves[1].pp,pp,'result hold preserves restored PP')
  end
  T.check(wait(function()return game.stack:top()==b and b.phase=='menu'end),id..' result acknowledgment completes the native item turn')
  T.eq(b.enemy.curMoves[1].pp,enemyPP-1,'acknowledgment gives exactly one native enemy action')
  T.eq(game.save.inventory[id],nil,'acknowledgment cannot consume a second item')
  if id=='FULL_HEAL'then T.eq(target.status,nil,'real status effect remains cured')end
  if id=='REVIVE'then T.check(target.hp>0,'actual bench Pokemon remains revived')end
end
for _,version in ipairs({'red','firered','emerald'})do
  local b,game,step,wait,open=fixture(version)
  local screen=open()
  T.neq(getmetatable(screen),Pack,version..' retains its existing bag controller')
end
Sound.play=soundPlay
V.set(oldVersion);Screens.invalidate()
T.finish('native Gen2 battle PACK selection and item turn ownership')
