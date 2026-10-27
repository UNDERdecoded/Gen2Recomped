package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local V = require('src.core.GameVersion')
local Battle = require('src.battle.BattleState')
local Pokemon = require('src.pokemon.Pokemon')
local Save = require('src.core.SaveData')
local Font = require('src.render.Font')
local oldVersion = V.get()

local function fixture(version)
  V.set(version)
  local data = T.fixtures.fresh(); data.constants.gen = V.generation()
  Font.load(data)
  local save = Save.newGame()
  save.party = {Pokemon.new(data, 'FIXMON_A', 30)}
  save.party[1].moves = {{id='FIX_TACKLE',pp=35},{id='FIX_SCRATCH',pp=40}}
  local input = {pressed={}}
  function input:wasPressed(key) return self.pressed[key] == true end
  function input:isDown() return false end
  local stack = {states={}}
  function stack:top() return self.states[#self.states] end
  function stack:push(state) self.states[#self.states+1]=state end
  function stack:pop() return table.remove(self.states) end
  local game = {data=data,save=save,input=input,stack=stack}
  local b = Battle.newWild(game, 'FIXMON_C', 30)
  stack:push(b)
  -- Start this ROM-free fixture at the native command decision.
  b.phase,b.queue,b.current,b.introSlide = 'menu',{},nil,0
  b.menuIndex,b.moveIndex,b.sendingOut = 1,1,false
  local function press(key)
    input.pressed = key and {[key]=true} or {}
    b:update(1/60)
    input.pressed = {}
  end
  return b,game,press
end

for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal','red','firered','emerald','platinum','black'}) do
  local b,game,press = fixture(version)
  local expected = V.isGen2() and 'moves' or 'moveSelect'
  if V.isGen4() or V.isGen5() then b.gen4CursorActive=true end
  local pp,hp = b.player.curMoves[1].pp,b.enemy.mon.hp
  press('a')
  T.eq(b.phase,expected,version .. ' actual FIGHT publishes the edition screen phase')
  T.eq(type(b.playerMoves),'function','native screen exposes live move instances')
  if type(b.playerMoves)=='function' then
    T.eq(b:playerMoves(),b:menuBattler().curMoves,'reader returns the actual chooser list')
    T.eq(b:playerMoves()[1],b.player.curMoves[1],'move ID/PP instance has native identity')
    if V.generation() <= 2 then
      -- Exercise native ink in both GB layouts, without replacing the drawer.
      for _,layout in ipairs({'classic','wide'}) do
        game.save.options.battleLayout=layout
        local drawn,draw={},Font.draw
        Font.draw=function(text,...) drawn[tostring(text)]=true;return draw(text,...) end
        if layout=='wide' then require('src.battle.WideBattle').draw(b) else b:drawTextArea() end
        Font.draw=draw
        T.check(drawn[game.data.moves.FIX_TACKLE.name],layout .. ' native move list paints actual name')
      end
      game.save.options.battleLayout='classic'
    end
    local grid=b:isWideBattleLayout() or b:gen3Layout() or b:gen4Layout()
    press(grid and 'right' or 'down')
    T.eq(b.moveIndex,2,'actual native input navigates to second move')
    press('b')
    T.eq(b.phase,'menu','actual B returns to command menu')
    T.eq(b.player.curMoves[1].pp,pp,'navigation/cancel spends no PP')
    T.eq(b.enemy.mon.hp,hp,'navigation/cancel causes no damage')
    press('a')
    T.eq(b.phase,expected,'actual FIGHT reopens same native selector')
    T.eq(b.moveIndex,2,'reopening preserves native cursor')
    press(grid and 'left' or 'up');press('a')
    T.eq(b.phase,'messages','actual A queues the chosen native turn')
    for tick=1,24000 do
      if b.phase=='menu' or b.result or b.dead then break end
      press('a')
    end
    T.eq(b.player.curMoves[1].pp,pp-1,'actual native turn spends one PP')
    T.check(b.phase=='menu' or b.result or b.dead,'actual native turn drains back to a decision/result')
    if V.isGen2() then
      -- Older shared-engine checkpoints keep accepting their stored spelling.
      b.phase,b.queue,b.current='moveSelect',{},nil
      press('down')
      T.eq(b.phase,'moves','legacy Gen2 decision resumes in public phase before rendering')
      T.eq(b.moveIndex,2,'legacy moveSelect still navigates in Gen2')
      press('b')
      T.eq(b.phase,'menu','legacy selector still cancels')
      local native=b.player.curMoves
      b.player.curMoves={{id='FIX_SCRATCH',pp=7}}
      T.eq(b:playerMoves(),b.player.curMoves,'temporary native moveset remains authoritative')
      T.neq(b:playerMoves(),game.save.party[1].moves,'reader does not substitute persistent moves')
      b.player.curMoves=native
    end
  end
end
V.set(oldVersion)
T.finish('native Gen2 move-selection screen contract')
