-- tools/gen4_dex_art_extract/main.lua
--
-- Adds the Pokedex LIST screen's native art (src/import/Gen4Dex.lua,
-- `Gen4Dex.listImages`) and its text colours to an EXISTING Platinum cache,
-- so the list draws with Platinum's own art without a re-import.
--
-- A fresh import puts the `dex/list_*` pictures in `gen4_graphics.screens`
-- (through Gen4UIResources) and the colours in `gen4_dex.listInk`.  This tool
-- leaves the large `gen4_graphics.lua` alone and instead merges the pictures
-- into `gen4_dex.lua` as `listArt` (the screen looks in both), writing the
-- PNGs where the importer would: <asset root>/assets/generated/gen4/dex/.
--
--   love tools/gen4_dex_art_extract <platinum .nds> <asset root> <cache dir>

function love.load(args)
  local ok, err = xpcall(function()
    local romPath, assetRoot, cacheDir = args[1], args[2], args[3]
    assert(romPath and assetRoot and cacheDir, "usage: love tools/gen4_dex_art_extract <rom> <asset root> <cache dir>")
    assetRoot, cacheDir = assetRoot:gsub("[/\\]$", ""), cacheDir:gsub("[/\\]$", "")
    local Gen4Dex = require("src.import.Gen4Dex")
    local rom = assert(require("src.import.NdsRom").open(romPath))
    local images = Gen4Dex.listOnly(rom)
    local ink = Gen4Dex.listInk(rom)
    local recordPath = cacheDir .. "/gen4_dex.lua"
    local record = assert(loadfile(recordPath), "no gen4_dex.lua in " .. cacheDir)()
    require("src.import.CacheFs").mkdirReal(assetRoot .. "/assets/generated/gen4/dex")
    record.listArt = {}
    local n = 0
    for key, pic in pairs(images) do
      local rel = "assets/generated/gen4/" .. key .. ".png"
      local data = love.image.newImageData(pic.width, pic.height, "rgba8", pic.rgba)
      local f = assert(io.open(assetRoot .. "/" .. rel, "wb"))
      f:write(data:encode("png"):getString())
      f:close()
      record.listArt[key] = { path = rel, width = pic.width, height = pic.height,
        originX = pic.originX, originY = pic.originY }
      n = n + 1
    end
    record.listInk = ink
    -- the old hand-paletted `dex/list_page` is no longer drawn
    record.list = nil
    local f = assert(io.open(recordPath, "wb"))
    f:write(require("src.import.LuaWriter").encodeSplit(record))
    f:close()
    print(("dex list: wrote %d pictures and merged listArt/listInk into %s"):format(n, recordPath))
    rom:close()
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
