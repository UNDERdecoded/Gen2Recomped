package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local PartyMenu=require('src.ui.PartyMenu')
local Pokemon=require('src.pokemon.Pokemon')
local old=Version.get()
for _,version in ipairs{'red','gold','silver','crystal','prism','polishedcrystal'}do
 Version.set(version)
 local data=T.fixtures.fresh()
 local party={Pokemon.new(data,'FIXMON_A',5),Pokemon.new(data,'FIXMON_B',8)}
 local game={data=data,save={party=party},input={pressed={}}}
 function game.input:wasPressed(k)return self.pressed[k]==true end
 local stack={states={}}
 function stack:top()return self.states[#self.states]end
 function stack:push(s)self.states[#self.states+1]=s end
 function stack:pop()return table.remove(self.states)end
 game.stack=stack
 local function press(menu,key)game.input.pressed={[key]=true};menu:update(1/60);game.input.pressed={}end
 party[1].name='STALE SPECIES NAME';party[1].nickname='EARNED NAME'
 local selected,cancelled
 local menu=PartyMenu.new(game,{battle={},pickOnly=true,onSwitch=function(mon)selected=mon end})
 stack:push(menu)
 T.eq(menu.party,party,version..' presentation reads the real save party')
 if Version.isGen2()then
  T.eq(party[1].name,data.pokemon[party[1].species].name,'native Gen2 boundary refreshes the catalog species name')
  T.eq(party[1].nickname,'EARNED NAME','catalog refresh preserves earned nickname')
 end
 T.eq(#(menu.party or{}),2,'presentation cannot show an empty team while input selects a mon')
 party[2].hp=1;T.eq(menu.party[2].hp,1,'live HP is not copied or cached')
 press(menu,'down');press(menu,'a')
 T.eq(selected,party[2],'ordinary native input selects exactly the displayed Pokemon')
 T.eq(stack:top(),nil,'selection releases its menu owner')
 menu=PartyMenu.new(game,{battle={},onCancel=function()cancelled=true end});stack:push(menu)
 local hp,pp=party[1].hp,party[1].moves[1].pp
 press(menu,'b');T.check(cancelled,'native cancel continuation fires')
 T.eq(party[1].hp,hp,'cancel preserves HP');T.eq(party[1].moves[1].pp,pp,'cancel preserves PP')
 local scoped={party[2]}
 T.eq(PartyMenu.new(game,{battle={playerParty=scoped}}).party,scoped,'scoped battle copy beats save party')
 local explicit={party[1]}
 T.eq(PartyMenu.new(game,{battle={playerParty=scoped},party=explicit}).party,explicit,'explicit picker selection beats battle scope')
 T.eq(PartyMenu.new(game,{party={}}).party[1],nil,'explicit empty party stays empty')
 T.eq(game.save.party,party,'menu never replaces the save party')
 T.eq(#party,2,'menu never shrinks or reorders the save party')
 local ok,native=pcall(PartyMenu.new,game,{battle=true})
 T.check(ok,'native boolean battle option does not index a boolean')
 T.eq(ok and native.party,party,'native boolean battle option reads the live party')
 T.eq(#PartyMenu.new({}).party,0,'empty preview has a concrete empty party')
end
Version.set(old)
T.finish('native party presentation and input share the live party')
