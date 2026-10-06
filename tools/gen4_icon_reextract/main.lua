-- tools/gen4_icon_reextract/main.lua
--
-- Rewrites an EXISTING Platinum cache's Pokemon icons (the party list, the
-- PC, the naming screen...) with the ramps from the correctly located
-- sPokemonIconPaletteIndex (src/import/Gen4Icons.lua). A cache imported
-- before that fix has every icon in its neighbour's colours.
--
--   love tools/gen4_icon_reextract <platinum .nds> <asset root>

function love.load(args)
  local ok, err = xpcall(function()
    local romPath, root = args[1], args[2]
    assert(romPath and root, "usage: love tools/gen4_icon_reextract <rom> <asset root>")
    root = root:gsub("[/\\]$", "")
    local G = require("src.import.Gen4Graphics")
    local I = require("src.import.Gen4Icons")
    local rom = assert(require("src.import.NdsRom").open(romPath))
    local arm9 = rom:arm9()
    local arc = require("src.import.NarcArchive").parse(assert(rom:read(I.PATH)))
    local sheets = (tonumber(arc.count) or 547) - I.FIRST_SHEET
    local at = assert(I.findPaletteTable(arm9, sheets), "no palette table")
    assert(I.verify(arm9, at), "the palette table disagrees with the anchors")
    local function member(i)
      local b = arc:get(i)
      if b and G.isCompressed(b) then b = G.decompress(b) end
      return b
    end
    local palette = G.palette(member(I.PALETTE_MEMBER))
    local n = 0
    for icon = 0, sheets - 1 do
      local sheet = G.tiles(member(I.FIRST_SHEET + icon))
      if sheet then
        local ramp = I.ramp(arm9, at, icon)
        local cells = {}
        for i = 0, sheet.count - 1 do cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = ramp } end
        local image = G.compose({ width = I.WIDTH, height = I.FRAME_HEIGHT * I.FRAMES, cells = cells }, sheet, palette)
        if image then
          local data = love.image.newImageData(image.width, image.height, "rgba8", image.rgba)
          local f = assert(io.open(("%s/assets/generated/gen4/pokemon/icon/%03d.png"):format(root, icon), "wb"))
          f:write(data:encode("png"):getString())
          f:close()
          n = n + 1
        end
      end
    end
    print(("rewrote %d icons with the table at ARM9+0x%X"):format(n, at - 1))
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
