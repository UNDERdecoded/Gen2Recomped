package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness").suite("Emerald map popup")
local Popup=require("src.world.Gen3MapPopup")
local root="G:/Gen2Recomped/emerald/data/generated/"
local constants=assert(loadfile(root.."constants.lua"))()
local fh=assert(io.open("Pokemon - Emerald Version (USA, Europe).gba","rb"))
local raw=fh:read("*a");fh:close()
local ImageWriter=require("src.import.ImageWriter")
local blank=ImageWriter.blank
local pixelCount=0
ImageWriter.blank=function() return {setPixel=function() pixelCount=pixelCount+1 end} end
local extractor=require("src.import.RomExtractorGen3").new(raw,"emerald",{})
extractor._constants=constants;extractor.saveImage=function() end;extractor.write=function() end
extractor:extractEmeraldMapPopup()
ImageWriter.blank=blank
T.check(pixelCount>30000,"ROM art decoded actual nontransparent pixels")
local maps=assert(loadfile(root.."maps.lua"))()
local record=constants.gen3MapPopup
T.check(record~=nil,"actual extraction wrote popup metadata")
for theme=0,5 do
  T.check(record.images[theme]~=nil,"theme art "..theme)
  T.check(record.underwaterImages[theme]~=nil,"underwater art "..theme)
end
T.eq(Popup.theme(record,16),0,"Route 101 uses wood")
T.eq(Popup.theme(record,7),3,"Petalburg uses brick")
T.eq(Popup.theme(record,8),1,"Slateport uses marble")
T.eq(Popup.theme(record,20),4,"Route 105 uses water")
T.eq(Popup.theme(record,50),5,"underwater uses stone2")
T.eq(Popup.theme(record,197),2,"Aqua Hideout adjusts Kanto section gap")
for id,def in pairs(maps) do
  if def.showMapName then
    T.check(record.images[Popup.theme(record,def.regionMapSection)]~=nil,id.." has valid popup art")
  end
end
local s=Popup.new("ROUTE 101",16,0)
for i=1,30 do s=Popup.tick(s);T.eq(s.state,"print","native print delay "..i) end
s=Popup.tick(s);T.eq(s.state,"in","prints on frame 31")
for i=1,20 do s=Popup.tick(s);T.eq(s.offset,40-i*2,"slide in two pixels "..i) end
T.eq(s.state,"wait","slide reaches screen")
for i=1,120 do s=Popup.tick(s);T.eq(s.state,"wait","hold "..i) end
s=Popup.tick(s);T.eq(s.state,"out","hold ends after 121 ticks")
for i=1,20 do s=Popup.tick(s);T.eq(s.offset,i*2,"slide out two pixels "..i) end
T.eq(s.state,"erase","erase after leaving screen")
s=Popup.tick(s);T.eq(s.state,"end","end after erase")
T.eq(Popup.tick(s),nil,"popup task retires")
local old=Popup.new("OLD",16,0);old.state="wait";old.offset=0
local incoming=Popup.new("NEW",8,0)
s=Popup.queue(old,incoming)
for i=1,19 do s=Popup.tick(s);T.eq(s.name,"OLD","old name remains while exiting "..i) end
s=Popup.tick(s);T.eq(s,incoming,"queued map replaces old at offscreen boundary")
T.eq(s.timer,0,"new map gets full print delay")
local Version=require("src.core.GameVersion");Version.set("emerald")
local OW=require("src.world.OverworldController")
local game={data={constants=constants},save={flags={}}}
for i=1,100 do
  local n=debug.getupvalue(OW.updateMapNameSignGen3,i)
  if n=="Game" then debug.setupvalue(OW.updateMapNameSignGen3,i,game);break end
end
local ow=setmetatable({map={def={showMapName=true,regionMapSection=16,weather=0}}},{__index=OW})
ow:updateMapNameSignGen3();local original=ow.mapNameSign
T.eq(original.name,"ROUTE 101","controller uses ROM section name")
ow:updateMapNameSignGen3();T.eq(ow.mapNameSign,original,"same section does not restart popup")
ow.map.def.regionMapSection=8;ow:updateMapNameSignGen3()
T.eq(ow.mapNameSign,original,"section transition queues instead of snapping")
T.eq(original.pending.name,"SLATEPORT CITY","new section name queued")
ow.map.def.showMapName=false;ow:updateMapNameSignGen3()
T.eq(ow.mapNameSign,nil,"nonannouncing interior hides popup")
local Commands=require("src.script.Gen3Commands")
ow.mapNameSign=Popup.new("OLD",16,0)
local Runner=require("src.script.ScriptRunner")
local runner=Runner.new(game,ow)
runner:run({{"g3_lock",true},{"g3_release",true}})
T.eq(ow.mapNameSign,nil,"scripted dialogue removes popup")
ow.map.def.showMapName=true;ow.map.def.regionMapSection=7
game.save.flags.FLAG_G3_4000=true
ow:updateMapNameSignGen3()
T.eq(ow.mapNameSign,nil,"native story flag suppresses popup")
T.eq(ow.signLandmark,7,"suppressed entry still records section")
game.save.flags.FLAG_G3_4000=nil
ow.map.def.regionMapSection=8;ow:updateMapNameSignGen3()
T.check(ow.mapNameSign~=nil,"popup returns after native story flag clears")
local menu=require("src.ui.Gen3StartMenu")
game.overworld=ow
game.save.party={};game.save.player={name="BRENDAN"};game.save.options={}
menu.new(game,{})
T.eq(ow.mapNameSign,nil,"opening Start dismisses the location popup")
T.finish()
