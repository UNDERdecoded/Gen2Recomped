function love.load()
  local repo=os.getenv("EMERALD_REPO") or love.filesystem.getWorkingDirectory()
  package.path=repo.."/?.lua;"..package.path
  local out=repo.."/tools/emerald_popup_render"
  local function write(path,bytes) local f=assert(io.open(path,"wb"));f:write(bytes);f:close() end
  local ok,err=xpcall(function()
    local root="G:/Gen2Recomped/emerald"
    local data={}
    for _,k in ipairs({"constants","font"}) do data[k]=assert(loadfile(root.."/data/generated/"..k..".lua"))() end
    require("src.core.GameVersion").set("emerald")
    local f=assert(io.open(repo.."/Pokemon - Emerald Version (USA, Europe).gba","rb"));local raw=f:read("*a");f:close()
    local ex=require("src.import.RomExtractorGen3").new(raw,"emerald",{})
    ex._constants=data.constants
    ex.write=function(_,name,value) write(out.."/"..name..".lua",require("src.import.LuaWriter").encodeSplit(value)) end
    ex.saveImage=function(_,img,path)
      love.filesystem.createDirectory("emerald/assets/generated/"..path:match("^(.*)/"))
      img:encode("png","emerald/assets/generated/"..path)
    end
    ex:extractEmeraldMapPopup()
    local Assets=require("src.render.Assets")
    Assets.image=function(path)
      if love.filesystem.getInfo("emerald/"..path) then return love.graphics.newImage("emerald/"..path) end
      local fh=assert(io.open(root.."/"..path,"rb"));local bytes=fh:read("*a");fh:close()
      return love.graphics.newImage(love.filesystem.newFileData(bytes,path))
    end
    require("src.render.Font").load(data)
    local Popup=require("src.world.Gen3MapPopup")
    love.graphics.setDefaultFilter("nearest","nearest")
    local atlas=love.graphics.newCanvas(480,480)
    local cases={{"ROUTE 101",16,0},{"SLATEPORT CITY",8,0},{"GRANITE CAVE",55,0},
      {"PETALBURG CITY",7,0},{"ROUTE 105",20,0},{"UNDERWATER",50,14}}
    for i,row in ipairs(cases) do
      local sign=Popup.new(unpack(row));sign.state="wait";sign.offset=0
      local c=love.graphics.newCanvas(240,160)
      love.graphics.setCanvas(c);love.graphics.clear(0.2,0.5,0.3,1);Popup.draw(data,sign);love.graphics.setCanvas()
      write(out.."/theme-"..i..".png",c:newImageData():encode("png"):getString())
      love.graphics.setCanvas(atlas);love.graphics.setColor(1,1,1,1);love.graphics.draw(c,((i-1)%2)*240,math.floor((i-1)/2)*160);love.graphics.setCanvas()
    end
    write(out.."/contact-sheet.png",atlas:newImageData():encode("png"):getString())
  end,debug.traceback)
  write(out.."/result.txt",ok and "PASS" or err)
  love.event.quit(ok and 0 or 1)
end
