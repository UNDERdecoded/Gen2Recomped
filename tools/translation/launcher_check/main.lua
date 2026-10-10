local root=love.filesystem.getSource().."/../../../"
package.path=root.."?.lua;"..root.."?/init.lua;"..package.path
local thread,channel,started
function love.load()
 local font,url=require("src.translation.Languages").font("es")
 love.filesystem.createDirectory("translations/fonts")
 local job={launcher=true,source="en",target="es",hardware="auto",
  cachePath="translations/launcher-en-es.json",font=font,fontUrl=url,helper=root.."translation/rom-translate.exe"}
 channel=love.thread.getChannel("rom.translation.progress");channel:clear()
 thread=love.thread.newThread("\npackage.path="..string.format("%q",root.."?.lua;"..root.."?/init.lua;").."..package.path;return assert(loadfile("..string.format("%q",root.."src/translation/worker.lua")..")) (...)")
 thread:start(require("src.link.Json").encode(job));started=love.timer.getTime()
end
function love.update()
 local message=channel:pop()
 if message then
  local event=require("src.link.Json").decode(message);print(message)
  if event.kind=="error"then love.event.quit(1)end
  if event.kind=="done"then
   local service=require("src.translation.Service")
   require("src.core.Strings").load({})
   service.setLauncher({launcherLanguage="es"})
   assert(service.launcherLookup("Translate")~="Translate","Missing launcher translation")
   assert(require("src.core.Strings")("Touch Controls")~="Touch Controls")
   local importer=require("src.import.RomImporter")
   local ui=setmetatable({_s=1,_hover=function()return false end},{__index=importer})
   local font=love.graphics.newFont(service.launcherFont,16)
   local canvas=love.graphics.newCanvas(420,200)
   love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(0.04,0.07,0.15,1)
   ui:_glassyButton(12,12,396,44,"Touch Controls",font,true)
   ui:_glassyButton(12,68,396,44,"Map Editor (Beta)",font,true)
   ui:_glassyButton(12,124,396,44,"Translate",font,true)
   love.graphics.setCanvas()
   local preview=assert(io.open(root.."tmp/launcher-language.png","wb"))
   preview:write(canvas:newImageData():encode("png"):getString());preview:close()
   service.setLauncher({launcherLanguage="en"})
   assert(service.launcherLookup("Translate")=="Translate")
   print("PASS full launcher catalog translation, UI rendering and English restore")
   love.event.quit(0)
  end
 end
 if thread:getError()then print(thread:getError());love.event.quit(1)end
 if love.timer.getTime()-started>300 then print("FAIL launcher translation timeout");love.event.quit(1)end
end
