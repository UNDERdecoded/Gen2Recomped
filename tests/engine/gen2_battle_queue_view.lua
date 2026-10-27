-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native queue transitions and screen fields, without a second controller,
-- a second typewriter or consumer-side phase changes.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Version = require('src.core.GameVersion')
local Battle = require('src.battle.BattleState')
local QueuePhase = require('src.battle.BattleQueuePhase')
local Pokemon = require('src.pokemon.Pokemon')
local Save = require('src.core.SaveData')
local Font = require('src.render.Font')
local before = Version.get()

local function fixture(version)
  Version.set(version)
  local data = T.fixtures.fresh(); data.constants.gen = Version.generation()
  local run = T.sdk.loadNone({data=data})
  Font.load(data)
  local save = Save.newGame(); save.options.battleAnimations = false; save.options.ruleset = "modern_clean"
  save.party = {Pokemon.new(data, 'FIXMON_A', 30)}
  save.party[1].moves = {{id='FIX_TACKLE',pp=0},{id='FIX_SCRATCH',pp=40}}
  local input = {pressed={}}
  function input:wasPressed(key) return self.pressed[key] == true end
  function input:isDown() return false end
  local stack = {states={}}
  function stack:top() return self.states[#self.states] end
  function stack:push(state) self.states[#self.states+1] = state end
  function stack:pop() return table.remove(self.states) end
  local game = {data=data,save=save,input=input,stack=stack}
  local b = Battle.newWild(game, 'FIXMON_C', 20)
  stack:push(b)
  b.phase,b.queue,b.current,b.introSlide,b.sendingOut = 'menu',{},nil,0,false
  b.menuIndex,b.moveIndex = 1,1
  local function step(key)
    input.pressed = key and {[key]=true} or {}
    stack:top():update(1/60)
    input.pressed = {}
  end
  local function wait(predicate)
    for _=1,6000 do if predicate() then return true end; step() end
    return predicate()
  end
  return b,game,step,wait
end

for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal','red','firered','emerald'}) do
  local b,game,step,wait = fixture(version)
  local gen2 = Version.isGen2()
  local phase = gen2 and 'resolving' or 'messages'
  local hp,enemyHp,pp = b.player.mon.hp,b.enemy.mon.hp,b.player.curMoves[2].pp
  local turn = b.turnCount
  step('a'); step('a') -- actual FIGHT, then the empty-PP learned move
  T.eq(b.phase,phase,version .. ' actual native refusal enters the edition queue phase')
  T.eq(b.turnCount,turn,'selection refusal spends no turn')
  step()
  local current = b.current
  T.check(current and type(current.text)=='string','actual queue starts its native refusal row')
  if current then
    if gen2 then
      T.eq(b.message,current.text,'public Gen2 message is the actual current source text')
      T.eq(b.messageTimer,48,'native message hold is visible while typing')
    else
      T.eq(rawget(b,'message'),nil,'other editions keep their existing screen fields')
      T.eq(rawget(b,'messageTimer'),nil,'Gen2 message hold does not leak to other editions')
    end
    if gen2 then
      -- Earlier queue records can already be mid-type when resumed.
      b.phase,b.message,b.messageTimer = 'messages',nil,nil
      local chars = b.charIndex
      step()
      T.eq(b.phase,'resolving','an already active legacy row resumes at its native owner')
      T.eq(b.current,current,'resuming does not replace or duplicate the current row')
      T.eq(b.message,current.text,'an already active legacy row exposes its actual text')
      T.eq(b.messageTimer,48,'resuming restores the same native text hold')
      T.check(b.charIndex-chars<=1,'resuming advances only the one native typewriter tick')
    end
    local index,queue = b.charIndex,#b.queue
    b:drawTextArea()
    require('src.battle.WideBattle').draw(b)
    T.eq(b.charIndex,index,'classic/wide drawing cannot type another glyph')
    T.eq(#b.queue,queue,'drawing cannot advance a native queue row')
    T.eq(b.current,current,'drawing retains the actual current row')
    T.check(wait(function()return b.msgPrompt and (b.msgPromptWait or 0)<=0 end),'native text reaches its own A/B prompt')
    for _=1,60 do step() end
    T.eq(b.current,current,'message cannot time out without native input')
    if gen2 then T.eq(b.messageTimer,48,'public hold does not independently count down') end
    step('b')
    T.eq(b.current,nil,'actual B retires exactly the native text row')
    if gen2 then T.eq(b.messageTimer,0,'the native acknowledgment retires its public hold') end
    local decision = b.afterQueue=='moveSelect' and (gen2 and 'moves' or 'moveSelect') or 'menu'
    T.check(wait(function()return b.phase==decision end),'refusal returns to its native edition decision')
    T.eq(b.message,nil,'no stale source text covers the restored menu')
    if gen2 then T.eq(b.messageTimer,0,'restored native menu has no message hold') end
  end
  T.eq(b.player.mon.hp,hp,'refusal does not mutate own HP')
  T.eq(b.enemy.mon.hp,enemyHp,'refusal does not damage the opponent')
  T.eq(b.player.curMoves[2].pp,pp,'refusal spends no other move PP')
  T.eq(b.turnCount,turn,'reading, drawing and acknowledging spend no battle turn')

  if gen2 then
    -- Resume a native queue stored by earlier shared-engine checkpoints.
    b.phase,b.afterQueue,b.queue,b.current = 'messages','menu',{},nil
    b:say('First native page')
    local child
    b:ui(function()
      child = require('src.ui.ChoiceBox').new(game,function()end)
      return child
    end)
    b:say('Second native page')
    step()
    T.eq(b.phase,'resolving','legacy message queue resumes on its real Gen2 owner')
    T.eq(b.message,'First native page','legacy row publishes the actual source text')
    T.check(wait(function()return b.msgPrompt and (b.msgPromptWait or 0)<=0 end),'first queued page finishes typing')
    step('a'); step()
    T.eq(b.phase,'submenu','actual queued UI retains its native child phase')
    T.eq(game.stack:top(),child,'actual queue pushes the same native child')
    step('b')
    T.check(wait(function()return game.stack:top()==b end),'native choice child releases its parent')
    step()
    T.eq(b.phase,'resolving','the same queue resumes after the child')
    T.eq(b.message,'Second native page','next actual source row replaces the retired text')
    T.check(wait(function()return b.msgPrompt and (b.msgPromptWait or 0)<=0 end),'second queued page finishes typing')
    step('a'); step()
    T.eq(b.phase,'menu','child continuation returns to the actual native menu')
    T.eq(b.message,nil,'child continuation leaves no stale message on the menu')
    T.eq(b.messageTimer,0,'child continuation releases the public text hold')

    -- Native battle YES/NO uses its real answer delay and queue callback.
    local answer
    b.phase,b.afterQueue = 'messages','menu'
    b:sayChoice('Continue?',function(yes)answer=yes end)
    T.check(wait(function()return game.stack:top()~=b end),'actual typed choice opens the native YES/NO owner')
    T.eq(b.message,'Continue?','choice keeps its actual text under the child')
    step('b')
    T.check(wait(function()return game.stack:top()==b end),'actual B answers after the native YES/NO hold')
    T.eq(answer,false,'the actual callback receives the chosen native answer')
    T.eq(b.messageTimer,0,'choice completion releases the same public text hold')
    step()
    T.eq(b.phase,'menu','choice returns to the same native decision')
    T.eq(b.message,nil,'choice text clears at the decision boundary')
  else
    b.phase = 'resolving'
    T.eq(QueuePhase.active(b),false,'Gen2 resolution spelling cannot admit other editions')
  end
end
Version.set(before)
T.finish('native Gen2 queue phase, message ownership and shared regressions')
