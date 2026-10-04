-- Check daily WRAM reset membership against all three ROMs and run the
-- extracted Radio Tower lottery script through the production VM/runner.
love = require("tests.love_stub")
local T = require("tests.harness").suite("Gen 2 daily events and lottery")
local Version = require("src.core.GameVersion")
local Flags = require("src.script.Gen2Flags")
local Daily = require("src.script.Gen2Daily")
local Commands = require("src.script.Commands")
local G2 = require("src.script.Gen2Commands")
local VM = require("src.script.Gen2ScriptVM")
local Runner = require("src.script.ScriptRunner")
local originalDate = os.date
local function day(d) return os.time({year=2026,month=10,day=d,hour=12}) end
local now = day(1) -- Thursday
os.date = function(format, stamp) return originalDate(format, stamp or now) end
local function read(path)
  local f = assert(io.open(path,"rb")); local s=f:read("*a"); f:close(); return s
end
local files = {
  gold="Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
  silver="Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
  crystal="Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc",
}
local prizes, textCount = {}, 0
Commands.show_text = function() textCount=textCount+1 end
Commands.g2_move = function() end
Commands.g2_giveitem = function(ctx, id)
  if ctx.game.bagFull then ctx.lastCheck=false;return end
  prizes[#prizes+1]=id;ctx.lastCheck=true
end
for _, version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  now=day(1)
  local manifest=require("src.link.Json").decode(read("tools/rom_manifest_"..version..".json"))
  local extractor=require("src.import.RomExtractorGen2").new(read(files[version]),version,manifest)
  local ranges={}
  for _, entry in ipairs({{"wDailyFlags1",4},{"wDailyRematchFlags",4},
      {"wDailyPhoneItemFlags",4},{"wDailyPhoneTimeOfDayFlags",4}}) do
    local symbol=extractor:symbol(entry[1])
    if symbol then ranges[#ranges+1]={symbol.address,symbol.address+entry[2]} end
  end
  local save={flags={},g2LuckyNumber=12345,g2LuckyNextFriday="2026-10-02",
    g2FruitTrees={[1]=true},g2InitialObjectFlagsSeeded=true}
  local rows=assert(extractor:gen2EngineFlags())
  T.eq(#rows,version=="crystal" and 162 or 93,version.." extracts full engine flag table")
  for _, row in ipairs(rows) do save.flags[Flags.scriptFlag(row.row)]=true end
  save.flags[Flags.eventFlag(68)]=true -- Elite Four story progress
  Daily.poll(save)
  for _, row in ipairs(rows) do
    local daily=false
    for _, range in ipairs(ranges) do daily=daily or (row.address>=range[1] and row.address<range[2]) end
    local expected = true
    if daily then expected = nil end
    T.eq(save.flags[Flags.scriptFlag(row.row)],expected,
      version.." ROM daily membership "..row.row)
  end
  T.eq(save.flags[Flags.eventFlag(68)],true,version.." preserves story progress")
  T.eq(save.g2LuckyNumber,12345,version.." daily reset retains lottery ID")
  T.eq(next(save.g2FruitTrees),nil,version.." fruit trees refresh")
  save.flags.ENGINE_DAILY_BUG_CONTEST=true
  Daily.poll(save)
  T.eq(save.flags.ENGINE_DAILY_BUG_CONTEST,true,version.." same-day polling retains contest lock")
  now=day(2);Daily.poll(save)
  T.eq(save.flags.ENGINE_DAILY_BUG_CONTEST,nil,version.." next day releases contest lock")
  T.eq(save.flags.ENGINE_LUCKY_NUMBER_SHOW,true,version.." daily reset retains weekly prize lock")
  T.eq(Daily.lotteryExpired(save),true,version.." Friday expires lottery")
  Daily.resetLottery(save)
  T.eq(save.g2LuckyNextFriday,"2026-10-09",version.." Friday restart waits seven days")
  T.eq(Daily.lotteryExpired(save),false,version.." cannot reset twice Friday")
  now=day(3);T.eq(Daily.lotteryExpired(save),false,version.." Saturday keeps Friday draw")
  now=day(9);T.eq(Daily.lotteryExpired(save),true,version.." following Friday expires")
  local legacy={flags={ENGINE_LUCKY_NUMBER_SHOW=true},g2LuckyNumber=12345}
  T.eq(Daily.lotteryExpired(legacy),false,version.." migration preserves existing draw")
  T.eq(legacy.g2LuckyNumber,12345,version.." migration preserves ID")
  now=day(1)
  local shifted={g2DayOffset=1}
  Daily.resetLottery(shifted)
  T.eq(shifted.g2LuckyNextFriday,"2026-10-08",version.." Mom's Friday waits seven days")
  shifted.g2DayOffset=-2
  Daily.resetLottery(shifted)
  T.eq(shifted.g2LuckyNextFriday,"2026-10-04",version.." Mom's weekday determines draw")
  local encoded=require("src.core.SaveSerializer").encode(shifted)
  T.eq(require("src.core.SaveSerializer").decode(encoded).g2LuckyNextFriday,
    "2026-10-04",version.." weekly timer survives saving")

  local root=(arg[1] or "G:/Gen2Recomped").."/"..version.."/data/generated/"
  local data={maps={},text={}}
  for _, name in ipairs({"map_scripts","field","pokemon","items"}) do data[name]=assert(loadfile(root..name..".lua"))() end
  local sym=assert(extractor:symbol("RadioTower1FLuckyNumberManScript"))
  local script=assert(VM.compile(data,string.format("S%02X_%04X",sym.bank,sym.address)))
  local game={data=data,stack={},save={flags={},party={{species="SPECIES_152",otId=54321}},
    boxes={[1]={},[14]={{species="SPECIES_123",otId=12345}}},currentBox=1,
    g2LuckyNumber=12345,g2LuckyNextFriday="2026-10-09"}}
  local ow={map={id="RADIO_TOWER_1F",def={label="RadioTower1F"}}}
  game.overworld=ow
  local runner=Runner.new(game,ow);ow.runner=runner
  now=day(3);prizes={}
  local function visit()
    runner:run(script)
    for i=1,200 do if not runner:isRunning() then break end; runner:update() end
    T.eq(runner:isRunning(),false,version.." clerk script terminates")
  end
  visit()
  T.eq(#prizes,1,version.." boxed Pokemon wins")
  T.eq(prizes[1],"ITEM_001",version.." perfect match awards Master Ball")
  T.eq(game.save.flags.ENGINE_LUCKY_NUMBER_SHOW,true,version.." award locks week")
  visit();visit()
  T.eq(#prizes,1,version.." repeated visits cannot duplicate prize")
  T.eq(game.save.g2LuckyNumber,12345,version.." repeated visits cannot reroll ID")
  game.save.flags.ENGINE_LUCKY_NUMBER_SHOW=nil;game.bagFull=true
  visit();T.eq(#prizes,1,version.." full bag gets no award")
  T.eq(game.save.flags.ENGINE_LUCKY_NUMBER_SHOW,nil,version.." full bag can retry")
  game.bagFull=false;visit();T.eq(#prizes,2,version.." making room permits retry")
  local random=love.math.random
  love.math.random=function() return 12345 end
  now=day(9);visit()
  love.math.random=random
  T.eq(#prizes,3,version.." Friday permits a new prize")
  T.eq(game.save.g2LuckyNextFriday,"2026-10-16",version.." clerk restarts next Friday timer")
  visit();T.eq(#prizes,3,version.." new week still permits only one prize")
  local ctx={game=game,save=game.save}
  textCount=0;Commands.g2_lucky_print(ctx)
  T.eq(textCount,0,version.." print special opens no extra textbox")
  T.eq(game.stringBuffers[3],"12345",version.." print writes correct RAM buffer")
  for _, case in ipairs({{12345,1},{22345,2},{56345,2},{56245,3},{56295,0}}) do
    game.save.party={{species="SPECIES_152",otId=case[1]}};game.save.boxes={}
    Commands.g2_lucky_winners(ctx)
    T.eq(ctx.g2Var,case[2],version.." trailing digits tier "..case[1])
  end
  game.save.party={{species="SPECIES_152",otId=12345,isEgg=1}}
  Commands.g2_lucky_winners(ctx);T.eq(ctx.g2Var,0,version.." eggs cannot win")
  game.save.party={{species="SPECIES_152",otId=56295}}
  game.save.boxes[1]={{species="SPECIES_123",otId=12345,isEgg=true}}
  Commands.g2_lucky_winners(ctx);T.eq(ctx.g2Var,0,version.." boxed eggs cannot win")
  game.save.boxes[1]={}
  Commands.g2_readvar(ctx,16);T.eq(ctx.g2Var,20,version.." empty active box has twenty slots")
  for i=1,20 do game.save.boxes[1][i]={species="SPECIES_152"} end
  Commands.g2_readvar(ctx,16);T.eq(ctx.g2Var,0,version.." full active box has zero slots")
  game.save.boxes[1][20]=nil
  Commands.g2_readvar(ctx,16);T.eq(ctx.g2Var,1,version.." counts remaining active box slots")
  game.save.currentBox=14
  Commands.g2_readvar(ctx,16);T.eq(ctx.g2Var,20,version.." changing box changes script capacity")
end
os.date=originalDate
T.finish()
