-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Exercise the real row, input routing, generation fold and options file.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Menu=require('src.ui.OptionsMenu')
local Stack=require('src.core.StateStack')
local Save=require('src.core.SaveData')
local Pokemon=require('src.pokemon.Pokemon')
local original=Version.get()
local function press(game,key)
 game.input.pressed={[key]=true};game.stack:top():update(1/60);game.input.pressed={}
end
local function selectOdds(game,root)
 for _=1,#root.rows+2 do
  local row=root.rows[root.index]
  if row and row.id=='shinyOdds'then return root end
  press(game,'down')
 end
 error('native SHINY ODDS row is unreachable')
end
for _,edition in ipairs({'red','gold','silver','crystal','emerald'})do
 Version.set(edition)
 local generation=Version.generation()
 for _,overridden in ipairs({false,true})do
  local fs=T.sdk.memfs({})
  local stored=Save.defaultOptions()
  stored.shinyOdds=overridden and 4096 or 1
  if overridden then stored.perGeneration={[generation]={shinyOdds=1}}end
  T.check(type(Save.saveOptions(stored,fs))=='table','seed previous ALWAYS selection')
  local g={data=T.fixtures.fresh(),save={options=Save.optionsFor(edition,fs)},input={pressed={}},writes=0}
  g.input.wasPressed=function(self,key)return self.pressed[key]==true end
  g.stack=setmetatable({}, {__index=Stack});g.stack:init()
  g.writeOptions=function(self)
   self.writes=self.writes+1
   T.check(type(Save.saveOptions(self.save.options,fs,generation))=='table','native options write succeeds')
  end
  local root=Menu.new(g);g.stack:push(root)
  local page=selectOdds(g,root)
  T.eq(page.rows[page.index].value(g),'ALWAYS','actual row starts on stored ALWAYS')
  press(g,'right')
  T.eq(page.rows[page.index].value(g),'DEFAULT','normal input selects cartridge default')
  T.eq(Pokemon.shinyOddsOf(g.save),nil,'default disables extra shiny roll immediately')
  local loaded={options=Save.optionsFor(edition,fs)}
  T.eq(Pokemon.shinyOddsOf(loaded),nil,'default remains disabled after loading options file')
  T.eq(page.rows[page.index].value({save=loaded}),'DEFAULT','fresh menu cannot resurrect ALWAYS')
  if overridden then
   local persisted=Save.loadOptions(fs)
   T.eq(persisted.shinyOdds,4096,'generation reset preserves shared extra-roll setting')
   local other=generation==1 and 'gold' or 'red'
   T.eq(Pokemon.shinyOddsOf({options=Save.optionsFor(other,fs)}),4096,'other generation retains its selected rate')
  end
  -- Start another menu from reloaded bytes: Left reaches ALWAYS and A wraps
  -- back to the default through the same native input owner.
  g.save=loaded;g.stack:init();root=Menu.new(g);g.stack:push(root)
  page=selectOdds(g,root);press(g,'left')
  T.eq(Pokemon.shinyOddsOf({options=Save.optionsFor(edition,fs)}),1,'left from persisted DEFAULT reaches ALWAYS')
  press(g,'a')
  T.eq(Pokemon.shinyOddsOf({options=Save.optionsFor(edition,fs)}),nil,'A also persists the return to DEFAULT')
  T.eq(g.writes,3,'each accepted selection writes once')
 end
end
Version.set(original)
T.finish('native default option persistence through shared and generation settings')
