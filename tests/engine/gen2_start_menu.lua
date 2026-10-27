-- Native Gen2 START ownership, routing and input (ROM-free).
-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
require('src.core.ModCompat').install()
local UI=require('src.ui.Gen2StartMenu');local Saving=require('src.ui.Gen2SaveMenu')
local Screens=require('src.ui.Screens');local Stack=require('src.core.StateStack')
local Generic=require('src.ui.Menu');local Font=require('src.render.Font')
local function game(version)
 local g={data=T.fixtures.fresh(),save={version=version,player={name='QA'},flags={},options={},party={},pokedex={owned={}},inventory={}},input={queue={}}}
 g.input.wasPressed=function(self,k)return self.queue[k]==true end
 g.input.isDown=function(self,k)return self.queue[k]==true end
 g.data.font.charmap={}
 for code=32,126 do g.data.font.charmap[#g.data.font.charmap+1]={seq=string.char(code),code=0x80+(code-32)}end
 Font.load(g.data)
 g.stack=setmetatable({}, {__index=Stack});g.stack:init();g.world={};g.stack:push(g.world)
 g.writeSave=function(self)self.writes=(self.writes or 0)+1;return true end
 return g
end
local function tick(g,key)
 g.input.queue=key and {[key]=true}or{};g.stack:update(1/60);g.input.queue={}
end
local function select(g,ui,value)
 for _=1,#ui.items do
  if ui.items[ui.list.index].value==value then tick(g,'a');return end
  tick(g,'down')
 end
 error('native START missing row '..value)
end
local function ready(g,ui)
 for _=1,3000 do
  if ui:yesNoVisible()then return end
  tick(g,ui.message.waiting and 'a' or nil)
 end
 error('save choices never ready')
end
T.eq(require('src.ui.gen2.StartMenu'),UI,'public spelling is the actual native START class')
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version);local g=game(version)
 local ui=Screens.push(g,'StartMenu')
 T.eq(ui.screenId,'Gen2StartMenu','ordinary field route identifies the native Gen2 owner')
 T.eq(getmetatable(ui),UI,'ordinary START has the public class identity')
 T.eq(ui.isOpaque,false,'START leaves live world behind it')
 T.eq(ui.items[1].value,'pack','empty-party menu begins with native PACK')
 T.eq(ui.items[1].label,'PACK','native GSC label')
 tick(g,'up');T.eq(ui.list.index,#ui.items,'native cursor wraps upward')
 tick(g,'down');T.eq(ui.list.index,1,'native cursor wraps downward')
 select(g,ui,'save');local save=g.stack:top()
 T.eq(getmetatable(save),Saving,'real input opens native save owner')
 T.eq(g.stack.states[#g.stack.states-1],ui,'exact START instance remains below its save submenu')
 ready(g,save);tick(g,'b')
 T.eq(g.stack:top(),g.world,'save cancellation closes both owners and returns to world')
 T.eq(g.writes,nil,'save cancellation never reaches writer')
 ui=Screens.push(g,'StartMenu')
 T.eq(ui.items[ui.list.index].value,'save','cursor survives a complete START/save round trip')
 tick(g,'start');T.eq(g.stack:top(),g.world,'START closes without invoking highlighted action')
 ui=Screens.push(g,'StartMenu');select(g,ui,'pack')
 T.neq(g.stack:top(),ui,'pack is a real native submenu')
 T.eq(g.stack.states[#g.stack.states-1],ui,'pack retains exact parent rather than reconstructing it')
 tick(g,'b');T.eq(g.stack:top(),ui,'pack B restores original START owner')
 tick(g,'b');T.eq(g.stack:top(),g.world,'START B restores world')
 -- Engine flags are the cartridge stores; unlocks must not depend on an
 -- optional presentation module inventing legacy convenience fields.
 g.save.flags.ENGINE_POKEDEX=true;g.save.flags.ENGINE_POKEGEAR=true;g.save.party={{species='CYNDAQUIL',hp=10}}
 ui=Screens.push(g,'StartMenu');local ids={}
 for _,row in ipairs(ui.items)do ids[row.value]=true end
 T.eq(ids.pokedex,true,'native dex bit unlocks Pokédex')
 T.eq(ids.pokemon,true,'actual party unlocks Pokémon')
 T.eq(ids.pokegear,true,'native gear bit unlocks Pokégear')
 tick(g,'b')
 local n=0;ui=UI.new(g,{onClose=function()n=n+1 end});ui:close();ui:close()
 T.eq(n,1,'close callback is idempotent')
end
V.set('red');local g=game('red');local red=Screens.push(g,'StartMenu')
T.eq(getmetatable(red),Generic,'Gen1 keeps its generic START implementation')
T.eq(Screens.resolveId(g,'StartMenu'),'StartMenu','Gen1 screen routing remains unchanged')
V.set('crystal');g=game('crystal');g.data.screens={StartMenu={}}
T.eq(Screens.resolveId(g,'StartMenu'),'StartMenu','explicit registry owner still wins')
V.set(original)
T.finish('native Gen2 START owner')
