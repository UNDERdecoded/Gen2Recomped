-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local original=V.get()
V.set('crystal')
local data=T.fixtures.fresh()
require('src.render.Font').load(data)
data.items.ITEM_158={id='ITEM_158',key='FLOWER_MAIL',name='Letter',pocket='ITEM'}
local Mail=require('src.pokemon.Gen2Mail');Mail.load(data)
local Pokemon=require('src.pokemon.Pokemon')
local function mon()
  return Pokemon.new(data,T.fixtures.ids.species[1],5,function(lo)return lo end)
end
local game={data=data,save={},stack={states={}}}
function game.stack:push(screen)self.states[#self.states+1]=screen;if screen.enter then screen:enter()end end
function game.stack:pop()return table.remove(self.states)end
function game.stack:top()return self.states[#self.states]end
local function press(screen,key)
  game.input={wasPressed=function(_,k)return k==key end,isDown=function()return false end}
  screen:update(1/60)
end
local function reset()
  game.save={party={mon(),mon()},player={name='AUTHOR',id=17},inventory={ITEM_158=2},bagOrder={'ITEM_158'}}
  game.stack.states={{parent=true}}
end
-- Exercise real party-menu callbacks and coroutine continuation, not a
-- substitute handler or a fabricated result variable.
local Runner=require('src.script.ScriptRunner')
local VM=require('src.script.Gen2ScriptVM')
for _,case in ipairs({
  {name='cancel',result=2}, {name='missing',result=3,pick=true},
  {name='wrong',result=0,pick=true,text='OTHER'},
  {name='last',result=4,pick=true,text='MATCH',last=true},
  {name='correct',result=1,pick=true,text='MATCH'},
})do
  reset();local carrier=game.save.party[1]
  if case.last then game.save.party[2].hp=0 end
  if case.text then carrier.item='ITEM_158';Mail.set(game.save,1,Mail.entry('ITEM_158',case.text,'R',2,carrier.species))end
  local finish=0
  local scriptData={map_scripts={scripts={probe={{'checkpokemail',{message='MATCH'}},{'end'}}}}}
  local rows=assert(VM.compile(scriptData,'probe'))
  local runner=Runner.new(game,{})
  runner:run(rows,{onDone=function()finish=finish+1 end})
  T.check(runner:isRunning(),'mail check suspends for real party input: '..case.name)
  T.eq(finish,0,'script does not continue before selection: '..case.name)
  local picker=game.stack:top()
  press(picker,case.pick and 'a' or 'b')
  T.eq(runner.ctx.g2Var,case.result,'native bytecode result: '..case.name)
  T.eq(finish,1,'script resumes once after real picker: '..case.name)
  T.eq(runner:isRunning(),false,'mail script terminates: '..case.name)
  T.eq(#game.save.party,case.result==1 and 1 or 2,'delivery changes party only for CORRECT: '..case.name)
end
reset()
local runner=Runner.new(game,{})
local rows=assert(VM.compile({map_scripts={scripts={gift={{'givepokemail',{item='ITEM_158',message='GIFT'}},{'end'}}}}},'gift'))
runner:run(rows,{g2Var=91})
T.eq(game.save.mail.party[2].message,'GIFT','compiled native gift targets the last party member')
T.eq(runner.ctx.g2Var,91,'gift does not overwrite the script result variable')

-- Binary fixtures cover the pointer width which previously desynchronised
-- Gold/Silver and ensure mail data never enters the dialogue/script queues.
local Extractor=require('src.import.RomExtractorGen2')
local Rom=require('src.import.Rom');local Ops=require('src.import.Gen2ScriptOps')
local Writer=require('src.import.LuaWriter')
for _,version in ipairs({'gold','silver','crystal'})do
  local codes={};for i,row in ipairs(Ops.commandsFor(version))do codes[row[1]]=i-1 end
  local bytes={};for i=1,0x8000 do bytes[i]=0 end
  local function put(at,values)for i,v in ipairs(values)do bytes[at+i]=v end end
  put(0x4000,{codes.givepokemail,0x00,0x41,codes.checkpokemail,0x01,0x41,codes.setval,77,codes['end']})
  put(0x4100,{158,0x80,0x4e,0x81,0x50})
  local chunks={};for i=1,#bytes,256 do chunks[#chunks+1]=string.char(unpack(bytes,i,math.min(i+255,#bytes)))end
  local extractor=setmetatable({version=version,rom=Rom.new(table.concat(chunks)),_gen2MailCharmap={['128']='A',['129']='B'}},Extractor)
  local pool={scripts={},queue={},instructions=0,desyncs=0}
  extractor:gen2DecodeScript(1,0x4000,'probe',pool)
  local decoded=pool.scripts.probe
  T.eq(#decoded,4,'word-sized mail operands retain following commands: '..version)
  T.eq(decoded[1][2].item,'ITEM_158','gift stationery resolves to native ID: '..version)
  T.eq(decoded[1][2].message,'A\nB','gift reads raw line break and terminator: '..version)
  T.eq(decoded[2][2].message,'A\nB','expected message skips no first character: '..version)
  T.eq(decoded[3][1],'setval','decoder remains aligned after both operands: '..version)
  T.eq(decoded[3][2],77,'following command retains its actual byte: '..version)
  T.eq(#pool.queue,0,'raw letters are not queued as scripts: '..version)
  T.eq(pool.desyncs,0,'native mail bytecode has no desync: '..version)
  local round=assert(loadstring(Writer.encodeSplit(pool)))()
  T.eq(round.scripts.probe[2][2].message,'A\nB','actual LuaWriter retains semantic letter data: '..version)
  T.eq(extractor:gen2MailOperand(1,0x8000,true),nil,'out-of-bank pointer is rejected: '..version)
  T.eq(extractor:gen2MailOperand(1,0x7fff,true),nil,'truncated gift cannot read across bank boundary: '..version)
end
local run=T.sdk.loadMods({'mods/mail_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/mail_probe/manifest.json']='{"id":"mail_probe","name":"Mail probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/mail_probe/main.lua']=[[
    local mod=...
    mod.exports.reads=0;mod.exports.writes=0
    mod.events:on("mail.read",function(e)mod.exports.reads=mod.exports.reads+1;mod.exports.message=e.message end)
    mod.events:on("mail.written",function(e)mod.exports.writes=mod.exports.writes+1 end)
  ]],
})})
T.eq(#run.errors,0,'actual SDK mail event subscriptions load')
reset();Mail.load(data);Mail.compose(game.save,1,'PUBLIC',game.save.party[1],'ITEM_158')
Mail.lines(Mail.get(game.save,1));Mail.lines(game.save.mail.party[1])
local exports=run.loader.exports.mail_probe
T.eq(exports.writes,1,'public SDK receives the native write once')
T.eq(exports.reads,1,'public SDK receives the native read once, not every redraw')
T.eq(exports.message,'PUBLIC','public SDK receives actual letter contents')
run.release()
V.set(original);Mail.load(nil)
T.finish('native GSC mail ROM bytecode, actual delivery runner and public SDK events')
