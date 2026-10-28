-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local old=V.get()
local P=require('src.pokemon.Pokemon')
local F=require('tests.gsc_species_fixture')
local Commands=require('src.script.Commands');require('src.script.Gen2Commands')
local Stack=require('src.core.StateStack')
local Runner=require('src.script.ScriptRunner')
-- Editor handlers are private closures. Exercise the real handlers, not a
-- duplicate of their mutation rules. This is a CPU transaction test, not a
-- lower-screen device/GUI acceptance test.
local function handler(root,name)
  local visited={}
  local function find(fn)
    if visited[fn]then return end;visited[fn]=true
    for i=1,100 do
      local key,value=debug.getupvalue(fn,i);if not key then break end
      if key==name then return value end
      if type(value)=='function'then local found=find(value);if found then return found end end
    end
  end
  return assert(find(root),'missing actual editor handler '..name)
end
local companion=require('src.ui.SaveCompanion')
local adjust=handler(companion.tick,'adjustIndividual')
local recalc=handler(companion.tick,'recalc')
local applySpecies=handler(companion.tick,'applySpecies')
for _,edition in ipairs{'gold','silver','crystal'}do
  V.set(edition);local data=F.new();data:seedDefaults()
  local sent=P.new(data,'CYNDAQUIL',12,function()return 15 end)
  data.field.gen2Trades={trades={{give='CYNDAQUIL',get='EEVEE',dvs={0x2a,0xaa},
    nickname='GIFT',ot='NPC',otId=17,item='POTION'}}}
  local stack=setmetatable({},{__index=Stack});stack:init()
  local game={data=data,save={party={sent},player={name='TEST',id=7},pokedex={seen={},owned={}}},stack=stack}
  -- Dialogue IO is outside this test. Actual script, party picker, trade
  -- materialization and movie still run on the engine's real owners.
  local ask,show=Commands.ask,Commands.show_text
  Commands.ask=function(ctx)ctx.lastCheck=true end
  Commands.show_text=function()end
  local runner=Runner.new(game)
  runner:run({{'g2_trade',0}})
  local picker=assert(stack:top());T.eq(picker.pickOnly,true)
  game.input={wasPressed=function(_,button)return button=='a'end}
  picker:update(0)
  local received=game.save.party[1]
  T.check(received~=sent,'actual native NPC exchange replaces picked mon')
  T.eq(received.species,'EEVEE');T.eq(received.level,12)
  T.eq(received.shiny,true);T.eq(received.gender,'female')
  T.eq(received.dvs.attack,2);T.eq(received.dvs.defense,10)
  T.eq(received.nickname,'GIFT');T.eq(received.ot,'NPC');T.eq(received.item,'POTION')
  local movie=assert(stack:top());T.eq(movie.received,received,'movie sees same final Pokemon')
  movie:finish()
  T.eq(runner:isRunning(),false,'trade script resumes through actual movie completion')
  Commands.ask,Commands.show_text=ask,show
  -- Passive panel recalculation must not reroll identity each frame. Actual
  -- DV/species edits refresh it once at their mutation boundary instead.
  received.gender='male';received.shiny=false
  recalc(game,received)
  T.eq(received.gender,'male');T.eq(received.shiny,false,'passive panel preserves cached identity')
  adjust(game,received,'attack',0)
  T.eq(received.gender,'female');T.eq(received.shiny,true)
  local hp=received.hp;data.pokemon.QUILAVA.genderRatio=255
  applySpecies(game,{mode='change',mon=received},'QUILAVA')
  T.eq(received.species,'QUILAVA');T.eq(received.gender,'unknown');T.eq(received.shiny,true)
  T.eq(received.hp,hp,'editor identity refresh does not heal the Pokemon')
end
V.set(old)
T.finish('actual GSC NPC trade and companion appearance mutation boundaries')
