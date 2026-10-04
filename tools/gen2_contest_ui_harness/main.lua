-- Run with LOVE from the repository root. Real extracted fonts, production UI.
package.path=os.getenv("CONTEST_REPO").."/?.lua;"..package.path
local out=os.getenv("CONTEST_REPO").."/tools/gen2_contest_ui_harness"
local function write(name,bytes)
  local f=assert(io.open(out.."/"..name,"wb"));f:write(bytes);f:close()
end
function love.load()
  local ok,err=xpcall(function()
    local Font=require("src.render.Font")
    local Assets=require("src.render.Assets")
    local Version=require("src.core.GameVersion")
    local Start=require("src.ui.StartMenu")
    local Comparison=require("src.ui.Gen2ContestComparison")
    local Battle=require("src.battle.BattleState")
    local Contest=require("src.world.BugContest")
    local Renderer=require("src.render.Renderer")
    Renderer.WIDTH=160;Renderer.HEIGHT=144
    local atlas=love.graphics.newCanvas(960,432)
    love.graphics.setDefaultFilter("nearest","nearest")
    for row,version in ipairs({"gold","silver","crystal"}) do
      Version.set(version)
      local root="G:/Gen2Recomped/"..version
      Assets.flush()
      Assets.image=function(path)
        local f=assert(io.open(root.."/"..path,"rb"));local bytes=f:read("*a");f:close()
        return love.graphics.newImage(love.filesystem.newFileData(bytes,path))
      end
      local function data(name) return assert(loadfile(root.."/data/generated/"..name..".lua"))() end
      local dataSet={font=data("font"),pokemon=data("pokemon"),field=data("field"),text=data("text")}
      Font.load(dataSet)
      require("src.ui.Theme").load(dataSet)
      local save={party={{species="SPECIES_155",hp=20,level=15}},player={name="GOLD"},
        flags={EVENT_GOT_POKEGEAR=true},g2BugContest={active=true,balls=7}}
      local game={data=dataSet,save=save,input={wasPressed=function() return false end,isDown=function() return false end},
        stack={push=function() end,pop=function() end}}
      local stock={species="SPECIES_123",level=14,maxHp=42}
      local candidate={species="SPECIES_127",level=15,maxHp=45}
      local screens={}
      screens[1]=Start.new(game)
      -- This menu holds the game reference, so snapshot states at draw time.
      for column=1,6 do
        if column==1 then Contest.setCaught(save,nil) else Contest.setCaught(save,stock) end
        local canvas=love.graphics.newCanvas(160,144)
        love.graphics.setCanvas(canvas);love.graphics.clear(0.78,0.85,0.75,1)
        if column<=2 then Start.new(game):draw()
        elseif column==3 then
          local battle=setmetatable({game=game,data=dataSet,bugContest=true,phase="menu",menuIndex=3},Battle)
          Battle.drawTextAreaInner(battle)
        elseif column==4 then Comparison.new(game,stock,candidate,function() end):draw()
        else
          local key=column==5 and "_ContestJudging_FirstPlaceText" or "_BugCatchingContestTimeUpText"
          local box=require("src.render.TextBox").new(game,assert(dataSet.text[key]))
          for tick=1,300 do box:update(1/60) end
          box:draw()
        end
        love.graphics.setCanvas()
        write(version.."-"..column..".png",canvas:newImageData():encode("png"):getString())
        love.graphics.setCanvas(atlas);love.graphics.setColor(1,1,1,1)
        love.graphics.draw(canvas,(column-1)*160,(row-1)*144);love.graphics.setCanvas()
      end
    end
    write("contact-sheet.png",atlas:newImageData():encode("png"):getString())
  end,debug.traceback)
  write("result.txt",ok and "Rendered all 18 production UI screens.\n" or err)
  love.event.quit(ok and 0 or 1)
end
