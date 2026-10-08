package.path="./?.lua;"..package.path
love=require("tests.love_stub")
require("src.core.GameVersion").set("polishedcrystal")
local D=require("src.core.Data");D:load()
local G=require("src.core.Game");G.data=D;G.save=require("src.core.SaveData").newGame();G.input=require("src.core.Input");G.input:init();G.renderer=require("src.render.Renderer");G.renderer:init();G.stack=require("src.core.StateStack");G.stack:init()
local O=require("src.world.OverworldController");G.overworld=O;G.stack:push(O,"RADIO_TOWER1_F",2,7,"down")
local ow=G.stack:top();ow.player.facing="down";ow:takeWarp(ow.map.def.warps[1]);for i=1,240 do G.stack:update() end
assert(ow.map.id=="GOLDENROD_CITY","exit bounced back inside");assert(ow.player.cellX==9 and ow.player.cellY==16,"exit scene must step south off the doorway");for i=1,240 do G.stack:update() end;assert(ow.map.id=="GOLDENROD_CITY","idle exit must remain outside");print("PASS live Polished Radio Tower exit and idle loop regression")
ow.player.cellY=15;ow.player.py=240;ow.player.facing="up";ow:onStepComplete();for i=1,240 do G.stack:update() end
assert(ow.map.id=="RADIO_TOWER1_F","normal entry must still work");ow.player.cellX=2;ow.player.cellY=7;ow.player.facing="down";ow:takeWarp(ow.map.def.warps[1]);for i=1,480 do G.stack:update() end
assert(ow.map.id=="GOLDENROD_CITY" and ow.player.cellY==16,"repeat exit must not loop");print("PASS re-entry and repeated exit")
