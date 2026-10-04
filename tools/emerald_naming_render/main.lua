function love.load()
  local repo = os.getenv("EMERALD_REPO") or love.filesystem.getWorkingDirectory()
  package.path = repo .. "/?.lua;" .. package.path
  local out = repo .. "/tools/emerald_naming_render"
  local function write(path, bytes)
    local f = assert(io.open(path,"wb")); f:write(bytes); f:close()
  end
  local ok, err = xpcall(function()
    local root = "G:/Gen2Recomped/emerald"
    local data = {}
    for _, name in ipairs({"constants","font","pokemon","moves","text"}) do
      data[name] = assert(loadfile(root .. "/data/generated/" .. name .. ".lua"))()
    end
    require("src.core.GameVersion").set("emerald")
    local f = assert(io.open(repo .. "/Pokemon - Emerald Version (USA, Europe).gba","rb"))
    local raw = f:read("*a"); f:close()
    local Extractor = require("src.import.RomExtractorGen3")
    local extractor = Extractor.new(raw,"emerald",{})
    extractor._constants = data.constants
    extractor.write = function(_, name, value)
      write(out .. "/" .. name .. ".lua",require("src.import.LuaWriter").encodeSplit(value))
    end
    extractor.saveImage = function(_, img, relative)
      love.filesystem.createDirectory("emerald/assets/generated/" .. relative:match("^(.*)/"))
      img:encode("png","emerald/assets/generated/" .. relative)
    end
    extractor:extractEmeraldNaming()
    assert(data.constants.gen3EmeraldNaming.images.bg)
    if os.getenv("EMERALD_INSTALL_NAMING") == "1" then
      local cache = love.filesystem.getSaveDirectory() .. "/emerald/data/generated/constants.lua"
      local existing = loadfile(cache)
      if existing then
        local constants = existing()
        constants.gen3EmeraldNaming = data.constants.gen3EmeraldNaming
        write(cache,require("src.import.LuaWriter").encodeSplit(constants))
      end
    end
    local Assets = require("src.render.Assets")
    Assets.image = function(path)
      local newPath = "emerald/" .. path
      if love.filesystem.getInfo(newPath) then return love.graphics.newImage(newPath) end
      local fh = assert(io.open(root .. "/" .. path,"rb"))
      local bytes = fh:read("*a");fh:close()
      return love.graphics.newImage(love.filesystem.newFileData(bytes,path))
    end
    require("src.render.Font").load(data)
    require("src.ui.Theme").load(data)
    local game = { data=data, save={player={name="BRENDAN",gender="male"}},
      stack={pop=function() end},input={wasPressed=function() return false end} }
    local Naming = require("src.ui.NamingScreen")
    local atlas = love.graphics.newCanvas(720,320)
    love.graphics.setDefaultFilter("nearest","nearest")
    for i, species in ipairs({"MUDKIP","RALTS"}) do
      -- Cache IDs are stable names on Emerald.
      assert(data.pokemon[species], species)
      local s = Naming.new(game,{title="'s nickname?",kind="mon",species=species,maxLen=10})
      for page=1,3 do
        s.page=page;s.glyphs={"T","E","S","T"}
        local canvas=love.graphics.newCanvas(240,160)
        love.graphics.setCanvas(canvas);love.graphics.clear();s:draw();love.graphics.setCanvas()
        write(out .. "/" .. species .. "-" .. page .. ".png",canvas:newImageData():encode("png"):getString())
        love.graphics.setCanvas(atlas);love.graphics.setColor(1,1,1,1)
        love.graphics.draw(canvas,(page-1)*240,(i-1)*160);love.graphics.setCanvas()
      end
    end
    write(out .. "/contact-sheet.png",atlas:newImageData():encode("png"):getString())
  end,debug.traceback)
  write(out .. "/result.txt",ok and "Rendered Emerald's native naming assets and six UI screens.\n" or err)
  print(ok and "PASS Emerald naming visual render" or err)
  love.event.quit(ok and 0 or 1)
end
