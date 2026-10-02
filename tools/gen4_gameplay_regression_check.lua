package.path = './?.lua;' .. package.path
local checks = 0
local function check(v, why) checks = checks + 1; assert(v, why) end
love = { math = { random = math.random } }
package.loaded['src.core.GameVersion'] = { isGen4=function() return true end,
 isGen2=function() return false end,isGen3=function() return false end, get=function() return 'platinum' end }
local E = require('src.world.Encounter')
local state = {}
for i=1,4 do check(not E.gen4StepAllowed(state,40,false,false,function() return 5 end),'grace suppresses step '..i) end
check(state.gen4EncounterAttempts==4,'rate 40 has four grace attempts')
check(E.gen4StepAllowed(state,40,false,false,function() return 39 end),'walking movement roll below 40')
check(not E.gen4StepAllowed(state,40,false,false,function() return 40 end),'walking movement roll at 40 fails')
check(E.gen4StepAllowed(state,40,true,false,function() return 69 end),'cycling movement roll below 70')
check(not E.gen4StepAllowed(state,40,true,false,function() return 70 end),'cycling movement roll at 70 fails')
local G = require('src.import.Gen4Maps')
local permissions = {}
for i=1,1024 do permissions[i]=string.char(0,0) end
permissions[34]=string.char(0x80,0x80)
permissions[35]=string.char(0x3B,0x80)
local grid=G.mapDef({width=1,height=1,maps={0}},function() return {permissions=table.concat(permissions)} end)
check(grid.behaviorCells:byte(34)==0x80,'blocked counter retains behavior')
local crop=G.crop(grid,1,1,2,2)
check(crop.behaviorCells:byte(1)==0x80 and crop.behaviorCells:byte(2)==0x3B,'cropping preserves blocked behaviors')
local Map=require('src.world.Map')
local ts=require('src.import.Gen4Tileset').pair()
local map=Map.new(crop,ts)
check(map:isCounterCell(0,0),'runtime recognizes blocked counter')
check(not map:isWalkableCell(0,0),'counter stays blocked')
check(map:cellBehaviour(1,0)==0x3B,'runtime reads blocked ledge')
if arg[1] then
 local root=arg[1]
 local matrices=assert(loadfile(root..'/data/generated/gen4_map_matrices.lua'))()
 local perms=assert(loadfile(root..'/data/generated/gen4_map_permissions.lua'))()
 local maps=assert(loadfile(root..'/data/generated/maps.lua'))()
 local A=require('src.import.Gen4Archives')
 local headers=assert(loadfile(root..'/data/generated/gen4_map_headers.lua'))()
 local rooms,counters=0,0
 for _,def in pairs(maps) do
  local header=headers[def.header]
  local script=header and A.name('/fielddata/script/scr_seq.narc',header.scripts) or ''
  if script:match('_mart$') or script:match('_pokecenter_1f$') then
   local matrix=matrices[def.layout]
   local full=G.mapDef(matrix,function(id) return perms[id] and {permissions=perms[id]} end)
   if full then
    local cut=G.crop(full,def.originX or 0,def.originY or 0,def.width,def.height)
    for i=1,#cut.behaviorCells do
     if cut.behaviorCells:byte(i)==0x80 then counters=counters+1 end
    end
    rooms=rooms+1
   end
  end
 end
 check(rooms>0 and counters>0,'ROM service interiors contain preserved counters')
 print('ROM service rooms: '..rooms..'; counter cells: '..counters)
end
package.loaded['src.render.Font']={}
package.loaded['src.core.Logger']={warn=function() end}
package.loaded['src.core.Strings']=function(s) return s end
local BagMenu=require('src.ui.Gen4BagMenu')
local used,pops,rebuilds=0,0,0
package.loaded['src.ui.BagMenu']={useItem=function(_,_,_,list) used=used+1; list:close() end}
local bag=setmetatable({game={stack={pop=function() pops=pops+1 end}},rows={{id=4}},index=1,
 rebuild=function() rebuilds=rebuilds+1 end},BagMenu)
bag:choose();bag:choose();bag:close()
check(used==1 and pops==1 and rebuilds==0,'one use closes battle bag and blocks repeated action')
package.loaded['src.render.Renderer']={uiPresentation={x=100,y=50,w=512,h=384,scaleX=2,scaleY=2}}
package.loaded['src.render.Assets']={image=function() return nil end,register=function() end}
local Dex=require('src.ui.Gen4Pokedex')
local uiGame={data={pokemon={[387]={name='TURTWIG'},[390]={name='CHIMCHAR'},[393]={name='PIPLUP'}},
 gen4_dex={orders={sinnoh={387,390,393},national={390,393,387}}}},
 save={party={{species=387},{species=390}},pokedex={seen={[387]=true}}},stack={pop=function() end}}
local dex=Dex.new(uiGame)
check(dex:species()==387 and dex.numbers[387]==1,'local dex uses Sinnoh order and number')
check(dex:touchpressed(1,160,150) and dex.page=='entry','scaled pointer opens seen dex entry')
check(not dex:touchpressed(1,20,20),'dex rejects letterbox pointer')
local Party=require('src.ui.Gen4PartyMenu')
local party=Party.new(uiGame)
check(party:touchpressed(1,140,80) and party.submenu==1,'scaled pointer opens party actions')
-- ITEM adds a fourth action; Switch is still row 2 in the taller popup.
check(#party:actions()==4 and party:actions()[2]=='switch','field party includes Item without moving Switch order')
party:touchpressed(1,470,326)
check(party.switchFrom==1,'party pointer selects Switch action')
party:touchpressed(1,396,90)
check(uiGame.save.party[1].species==390 and uiGame.save.party[2].species==387,'party pointer swaps selected members')
check(not party:touchpressed(1,20,20),'party rejects letterbox pointer')
for _,file in ipairs({'src/world/MapLoader.lua','src/world/Map.lua','src/world/OverworldController.lua',
 'src/world/Encounter.lua','src/import/Gen4Maps.lua','src/ui/Gen4BagMenu.lua','src/battle/BattleState.lua',
 'src/script/Gen4Commands.lua','src/script/Gen4ScriptVM.lua','src/ui/Gen4PartyMenu.lua','src/ui/Gen4Pokedex.lua'}) do
 check(loadfile(file),'syntax '..file)
end
print(checks..' gameplay regression checks passed')
