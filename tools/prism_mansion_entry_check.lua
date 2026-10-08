love=love or require('tests.love_stub')
local T=require('tests.harness').suite('Prism Haunted Mansion entrance')
local D=require('src.core.Data')
local root=os.getenv('PRISM_CACHE') or 'G:/Gen2Recomped/prism/data/generated/'
for _,key in ipairs({'maps','tilesets','sprites','field','pokemon','moves','items','constants','text','palettes','map_scripts','type_chart','trainers','trainer_headers','charmap','font','audio'})do D[key]=assert(loadfile(root..key..'.lua'))() end
require('src.core.GameVersion').set('prism')
local Game=require('src.core.Game');Game.data=D
Game.input=require('src.core.Input');Game.input:init()
Game.renderer=require('src.render.Renderer');Game.renderer:init()
Game.stack=require('src.core.StateStack');Game.stack:init()
Game.save=require('src.core.SaveData').newGame()
local OW=require('src.world.OverworldController');Game.overworld=OW
Game.stack:push(OW,'HAUNTED_FOREST',6,6,'up')
Game.input:keypressed('up')
for i=1,120 do Game.stack:update(1/60);Game.input:step() end
Game.input:keyreleased('up')
T.eq(OW.map.id,'HAUNTED_MANSION','walking up through the pictured door enters the mansion')
T.eq(OW.player.cellX,6,'correct entrance column')
T.check(OW.player.cellY<41,'held up walks from the entrance mat into the vestibule')
T.eq(OW.player.facing,'up','entry preserves facing')
T.check(not OW.transitioning,'transition completes and releases movement')
T.eq(Game.stack:top(),OW,'no stale transition screen blocks play')
T.finish()
