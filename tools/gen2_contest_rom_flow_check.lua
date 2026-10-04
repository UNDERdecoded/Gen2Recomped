-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).
-- Run extracted Gold, Silver and Crystal contest bytecode with the real VM.
-- UI and movement are acknowledged by the harness; branching, flags, contest
-- specials and warp coroutine resumption use production code.
love = require("tests.love_stub")
local VM = require("src.script.Gen2ScriptVM")
local Commands = require("src.script.Commands")
local G2 = require("src.script.Gen2Commands")
local Runner = require("src.script.ScriptRunner")
local Contest = require("src.world.BugContest")
local OW = require("src.world.OverworldController")
local Game = require("src.core.Game")
-- enter() normally binds this shared Game upvalue while creating GPU/world
-- state. Bind that service for these isolated production exit methods.
for index=1,20 do
  local name=debug.getupvalue(OW.bugContestReturnToGate,index)
  if not name then break end
  if name=="Game" then debug.setupvalue(OW.bugContestReturnToGate,index,Game);break end
end
local T = require("tests.harness").suite("Gen 2 extracted contest flow")
local eq = T.eq
local root = arg[1] or "G:/Gen2Recomped"
local count, prizes = 0, {}
local resolve = Commands.resolve
Commands.resolve = function(...)
  count = count + 1
  assert(count < 3000, "contest script loop")
  return resolve(...)
end
Commands.show_text = function(ctx, _, _, opts)
  if opts and opts.choice then
    ctx.overworld.promptCount=(ctx.overworld.promptCount or 0)+1
    ctx.overworld.ui=function() opts.choice(ctx.game.nicknameYes) end
    ctx.runner:yield()
  end
end
require("src.ui.Screens").push=function(game, screen, opts)
  assert(screen=="NamingScreen", "unexpected contest menu: "..screen)
  eq(opts.kind,"mon","naming screen shows caught Pokemon icon")
  game.overworld.ui=function() opts.onDone("BUG") end
end
Commands.g2_move = function() end
Commands.g2_getitemname = function() end
Commands.g2_buffer_num = function() end
Commands.give_item = function(ctx, id)
  prizes[#prizes+1] = id
  ctx.lastCheck = true
end
for _, version in ipairs({"gold", "silver", "crystal"}) do
  require("src.core.GameVersion").set(version)
  local path = root.."/"..version.."/data/generated/"
  local data = {maps={},text={}}
  for _, name in ipairs({"map_scripts", "field", "pokemon", "items"}) do
    data[name] = assert(loadfile(path..name..".lua"))()
  end
  -- Re-extract the actual tables to cover the previously missing tenth AI.
  local function read(file)
    local f=assert(io.open(file,"rb"));local bytes=f:read("*a");f:close();return bytes
  end
  local files={gold="Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
    silver="Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
    crystal="Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"}
  local manifest=require("src.link.Json").decode(read("tools/rom_manifest_"..version..".json"))
  local extractor=require("src.import.RomExtractorGen2").new(read(files[version]),version,manifest)
  data.field.gen2BugContest=assert(extractor:gen2BugContest())
  eq(#data.field.gen2BugContest.contestants,10,version.." extracts all ten AI")
  eq(data.field.gen2BugContest.contestants[10].id,11,version.." tenth AI ID")
  eq(#data.field.gen2BugContest.contestantFlags,10,version.." own contestant flags")
  for _, size in ipairs({1, 6}) do
   for _, placing in ipairs({1,2,3,4,0}) do
    local game = {data=data,stack={},nicknameYes=placing==1,
      save={flags={},g2Scenes={},party={},player={name="GOLD",id=1}}}
    for i=1,size do game.save.party[i]={species="SPECIES_152",hp=20} end
    local ow = {map={id="NATIONAL_PARK_BUG_CONTEST"}}
    ow.bugContestReturnToGate=OW.bugContestReturnToGate
    function ow:queueScript(rows) self.queued=rows;self.queuedCount=(self.queuedCount or 0)+1 end
    function ow:startWarpTo(id,x,y,facing,done)
      self.map={id=id};self.done=done
    end
    local runner=Runner.new(game,ow)
    ow.runner=runner
    game.overworld=ow
    Contest.holdParty(game.save)
    Contest.start(game)
    local caught=placing~=0
    Contest.state(game.save).scores={}
    -- Score 456; zero to three rivals beat it to exercise every prize arm.
    for id=2,6 do Contest.state(game.save).scores[id]={score=id<=placing and 600 or 300,species="SPECIES_014"} end
    if caught then Contest.setCaught(game.save,{species="SPECIES_123",hp=50,maxHp=50,stats={attack=50,defense=50,speed=50,special=50}}) end
    count,prizes=0,{}
    Game.data,Game.save=data,game.save
    eq(ow:bugContestReturnToGate(),true,version.." early exit queues ROM results")
    eq(ow:bugContestReturnToGate(),true,version.." repeated exit is guarded")
    eq(ow.queuedCount,1,version.." exactly one exit script queued")
    runner:run(ow.queued)
    for i=1,100 do
      if ow.done then local done=ow.done;ow.done=nil;done() end
      if ow.ui then local ui=ow.ui;ow.ui=nil;ui() end
      if not runner:isRunning() then break end
      runner:update()
    end
    eq(runner:isRunning(),false,version.." results finish")
    eq(#prizes,1,version.." awards one prize")
    local prize=({[1]="ITEM_169",[2]="ITEM_112",[3]="ITEM_174",[4]="ITEM_173",[0]="ITEM_173"})[placing]
    eq(prizes[1],prize,version.." correct placing prize")
    eq(Contest.active(game.save),false,version.." timer ends")
    eq(Contest.state(game.save),nil,version.." catch transferred and run cleared")
    eq(#game.save.party,math.min(size+(caught and 1 or 0),6),version.." held party restored")
    if size==6 and caught then
      eq(game.save.boxes[1][1].species,"SPECIES_123",version.." catch boxed after full party restored")
    end
    eq(ow.promptCount or 0,caught and 1 or 0,version.." nickname offered after transferring catch")
    if caught and game.nicknameYes then
      local mon=size==6 and game.save.boxes[1][1] or game.save.party[size+1]
      eq(mon.nickname,"BUG",version.." nickname retained in party or box")
    end
    eq(G2.getScene(game.save,"ROUTE36_NATIONAL_PARK_GATE"),0,version.." results scene reset")
    eq(game.save.flags.ENGINE_BUG_CONTEST_TIMER,nil,version.." timer flag cleared")
    eq(game.save.flags.ENGINE_DAILY_BUG_CONTEST,true,version.." daily entry consumed")
    OW.checkBugContestClock(ow)
    eq(ow:bugContestReturnToGate(),false,version.." finished contest cannot queue stale exit")
    -- Re-enter each gate repeatedly: run its real callbacks, which choose
    -- the exit scene from the timer flag. They must never award another prize.
    for _, gate in ipairs({"ROUTE35_NATIONAL_PARK_GATE","ROUTE36_NATIONAL_PARK_GATE"}) do
      for visit=1,3 do
        ow.map={id=gate}
        for _, cb in ipairs(data.map_scripts.maps[gate].callbacks) do
          runner:run(assert(VM.compile(data,cb.script)))
          eq(runner:isRunning(),false,version.." gate callback completes")
        end
        eq(G2.getScene(game.save,gate),0,version.." gate re-entry remains NOOP")
        eq(#prizes,1,version.." no repeat payout")
      end
    end
   end
  end
  -- Judging includes only this run's five selected NPCs, with ROM jitter.
  local game={data=data,save={flags={},party={{hp=20}}}}
  Contest.start(game)
  Commands.g2_bug_contest_select({game=game,save=game.save})
  local _, board=Contest.judge(game)
  eq(#board,6,version.." five competing AI plus player")
  for _, entry in ipairs(data.field.gen2BugContest.contestants) do
    local rolled=Contest.state(game.save).scores[entry.id]
    local inRange=false
    for _, pick in ipairs(entry.picks) do
      inRange=inRange or (rolled.species==pick.species and rolled.score>=pick.score and rolled.score<=pick.score+7)
    end
    eq(inRange,true,version.." AI score includes ROM 0..7 adjustment")
  end
  game.save.flags={}
  Contest.state(game.save).scores={[2]={score=100},[11]={score=100}}
  Contest.setCaught(game.save,{maxHp=25})
  _,board=Contest.judge(game)
  eq(board[1].id,1,version.." player wins tied score")
  eq(board[2].id,11,version.." later AI wins tied score")
  -- Timeout remains true throughout the notice; polling must not stack boxes
  -- or race the out-of-balls ending before its callback queues judging.
  local notices={}
  Game.data,Game.save=data,game.save
  Game.stack={push=function(_,box) notices[#notices+1]=box end}
  local ow={map={id="NATIONAL_PARK_BUG_CONTEST"},runner={isRunning=function() return false end},
    bugContestOver=OW.bugContestOver,bugContestReturnToGate=OW.bugContestReturnToGate}
  function ow:queueScript(rows) self.queuedCount=(self.queuedCount or 0)+1 end
  Contest.state(game.save).endsAt=os.time()-1
  for tick=1,120 do OW.checkBugContestClock(ow) end
  ow:bugContestOver("_BugCatchingContestIsOverText","Over!")
  eq(#notices,1,version.." timeout and out-of-balls share one notice")
  notices[1].onDone()
  for tick=1,120 do OW.checkBugContestClock(ow) end
  eq(ow.queuedCount,1,version.." timeout queues results once")
  -- A full active box never silently sends the contest catch to another box.
  game.save.party={}
  for i=1,6 do game.save.party[i]={hp=20} end
  local Boxes=require("src.pokemon.Boxes")
  local active=Boxes.active(game.save)
  for i=1,20 do active[i]={species="SPECIES_010"} end
  Contest.setCaught(game.save,{species="SPECIES_123"})
  local ctx={game=game,save=game.save}
  eq(Commands.g2_contest_party_full(ctx),nil,version.." special result is not a jump")
  eq(ctx.g2Var,1,version.." full active box follows ROM BOXED_MON branch")
  eq(Boxes.used(game.save.boxes[2]),0,version.." other boxes remain unchanged")
  ctx.g2Var=152
  eq(Commands.g2_find_party_species(ctx),nil,version.." other special answers cannot jump")
  eq(ctx.g2Var,0,version.." special still writes its script result")
end
T.finish()
