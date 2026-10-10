local root="G:/Github Desktop/0.7.0/Gen2Recomped/"
package.path=root.."?.lua;"..root.."?/init.lua;"..package.path
function love.load()
 local ok,err=xpcall(function()
 require("src.core.GameVersion").set("emerald")
 local data=require("src.core.Data");data:load()
 require("src.core.Game").data=data
 local Assets=require("src.render.Assets")
 local function imageData(path)
  local f=assert(io.open("G:/Gen2Recomped/emerald/"..path,"rb"));local b=f:read("*a");f:close()
  return love.image.newImageData(love.filesystem.newFileData(b,path))
 end
 Assets.imageData=imageData
 Assets.image=function(path)return love.graphics.newImage(imageData(path))end
 local V,mods={},{}
 V.require=function(n)if not mods[n]then mods[n]=assert(loadfile(root.."mods/DRAMATIC_SHAPE/lib/"..n..".lua"))(V)end;return mods[n]end
 V.data=function(n)return assert(loadfile(root.."mods/DRAMATIC_SHAPE/data/"..n..".lua"))()end
 local ML=require("src.world.MapLoader")
 local roster=V.data("gen3_maps").maps
 local count=0
 for id,d in pairs(data.maps)do
  local wanted=false
  if roster[id] and roster[id].outdoor then
   for _,w in ipairs(d.warps or {})do local dest=roster[w.destMap];if (w.destWarp==nil or w.destWarp==1) and dest and (dest.name:find("PokemonCenter_1F",1,true) or dest.name:match("_Mart$")) then wanted=true end end
  end
  if os.getenv("EMERALD_CLOSE")=="1" then wanted=wanted and id=="MAP_G00_N10" end
  if wanted then
   local m=ML.load(data,id)
   print("MAP",id,d.label,d.width,d.height,m.tileset.id)
   for _,w in ipairs(d.warps or {})do print("WARP",w.x,w.y,w.destMap,w.destWarp)end
   local S=V.require("Structures").forMap(m)
   local models=V.require("EmeraldBuildings").forMap(S,m)
   assert(models and #models>0,"missing Center or Mart model")
   for _,t in ipairs(models)do
    local x,y=t.position[1],t.position[2]
    for dy=0,7 do for dx=0,7 do assert(S.skip[(y+dy+64)*4096+x+dx+64],"civic model not claimed "..id.." "..t.name.." "..x..","..y.." tile "..dx..","..dy)end end
   end
   local pixels=V.require("Gen3").atlasDataForTileset(m.tileset)
   local pw,ph=pixels:getDimensions()
   for _,placement in ipairs(S.civicPlacements or {})do
    for i=placement.first,placement.last do
     local q=S.objectQuads[i]
     local u,v=0,0
     for j=1,4 do u=u+q.uv[j][1]/4;v=v+q.uv[j][2]/4 end
     local r,g,b=pixels:getPixel(math.min(pw-1,math.floor(u*pw)),math.min(ph-1,math.floor(v*ph)))
     if g>r*1.12 and g>b*1.05 then print("GREEN",i,u*pw,v*ph,r,g,b,q[1][1],q[1][2],q[1][3])end
     assert(not (g>r*1.12 and g>b*1.05),"lawn texture extruded on civic building "..id)
    end
   end
   count=count+#models
   print("PASS complete civic models",id,#models,#S.objectQuads)
   if id=="MAP_G00_N10" or id=="MAP_G00_N07" then
   local mesh=V.require("ChunkMesher").build(m,true)
   local texture=V.require("Gen3").atlasForTileset(m.tileset)
   V.require("VoxelState").angle=math.rad(35)
   local g=V.require("Voxel3D");local vw=d.width*16*1.2
   assert(g.beginScene(800,650,d.width*8,d.height*8,vw,vw*650/800))
   g.draw(mesh,texture);g.endScene()
   local f=assert(io.open(root.."tmp/emerald-voxel-"..id..".png","wb"));f:write(g.canvas():newImageData():encode("png"):getString());f:close()
   if id=="MAP_G00_N10" then
    for view,eye in pairs({front={112,95,375},side={250,80,275}})do
      g.camera={eye=eye,focus={112,24,240},fov=math.rad(45),curve=0}
      assert(g.beginScene(800,650,112,240,180,146))
      g.draw(mesh,texture);g.endScene()
      local f=assert(io.open(root.."tmp/emerald-center-"..view..".png","wb"));f:write(g.canvas():newImageData():encode("png"):getString());f:close()
      g.camera=nil
    end
   end
   local c=love.graphics.newCanvas(d.width*16,d.height*16)
   love.graphics.setCanvas(c);love.graphics.clear();love.graphics.setColor(1,1,1,1)
   local img=V.require("Gen3").atlasForTileset(m.tileset); local iw,ih=img:getDimensions();local pr=iw/8
   for y=0,d.height*2-1 do for x=0,d.width*2-1 do local t=m:tileAt(x,y);love.graphics.draw(img,love.graphics.newQuad(t%pr*8,math.floor(t/pr)*8,8,8,iw,ih),x*8,y*8)end end
   love.graphics.setCanvas()
   local f=assert(io.open(root.."tmp/"..id..".png","wb"));f:write(c:newImageData():encode("png"):getString());f:close()
   end
   V.require("Structures").invalidate(id);collectgarbage("collect")
  end
 end
 for id,meta in pairs(roster)do
  if os.getenv("EMERALD_CLOSE")~="1" and (meta.name=="Route101" or meta.name=="Route113" or meta.name=="Route119") then
   local m=ML.load(data,id);local S=V.require("Structures").forMap(m)
   assert(#S.grassQuads>0,"missing grass sprites: "..meta.name)
   for _,q in ipairs(S.grassQuads)do
    for j=2,4 do assert(q[j][3]==q[1][3],"grass has extruded sides")end
   end
   print("PASS grass sprite planes",meta.name,#S.grassQuads)
   V.require("Structures").invalidate(id);collectgarbage("collect")
  end
 end
 print("PASS Emerald civic footprint audit",count,"buildings")
 end,debug.traceback)
 if not ok then print(err)end
 love.event.quit(ok and 0 or 1)
end