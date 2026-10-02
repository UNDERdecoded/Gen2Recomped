function love.load(args)
 package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
 local ok,why=pcall(function()
  local output=assert(args[1],'output PNG required')
  local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
  local rows=require('src.import.Gen4Otherpoke').FORMS
  local arc=assert(require('src.import.NarcArchive').parse(rom:read(require('src.import.Gen4Otherpoke').PATH)))
  local pictures={}
  local mons={}
  for _,row in ipairs(rows) do if row.species>0 then mons[row.species]={trueColor=true} end end
  local extractor={archive=function() return arc end,saveImage=function(_,path,pic)
   pictures[path]=love.graphics.newImage(love.image.newImageData(pic.width,pic.height,'rgba8',pic.rgba))
   pictures[path]:setFilter('nearest','nearest')
   return {path=path,width=pic.width,height=pic.height}
  end}
  require('src.import.RomExtractorGen4').extractFormSprites(extractor,{forms={},counts={}},mons)
  local Sprites=require('src.pokemon.Sprites')
  local data={constants={gen=4},pokemon=mons}
  local canvas=love.graphics.newCanvas(1280,960)
  love.graphics.setCanvas(canvas);love.graphics.clear(.14,.16,.2,1)
  love.graphics.setFont(love.graphics.newFont(10))
  local count=0
  for _,row in ipairs(rows) do
   if row.species>0 then
    local x=(count%8)*160;local y=math.floor(count/8)*96
    local mon={species=row.species,form=row.form,shiny=false}
    for tone=0,1 do
     mon.shiny=tone==1
     local path=Sprites.path(data,row.species,'front',{mon=mon})
     local image=assert(pictures[path],path)
     love.graphics.setColor(1,1,1,1)
     love.graphics.draw(image,x+tone*80,y)
    end
    love.graphics.print(row.species..' '..row.form,x+2,y+80)
    count=count+1
   end
  end
  love.graphics.setCanvas()
  local rendered=canvas:newImageData()
  local png=rendered:encode('png')
  local file=assert(io.open(output,'wb'));file:write(png:getString());file:close()
  rom:close()
  assert(count==76,'native form coverage changed')
  print(count..' native forms drawn through the live normal/shiny sprite resolver: '..output)
 end)
 love.graphics.setCanvas()
 if not ok then print(why) end
 love.event.quit(ok and 0 or 1)
end
