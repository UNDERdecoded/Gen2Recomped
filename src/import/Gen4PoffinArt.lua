-- PLATINUM'S POFFIN ART, composed from the cartridge.
--
-- Three archives, all with their member names (Gen4Archives):
--
--   /graphic/nutmixer.narc   THE COOKING (overlay083). Its pot is drawn in 3D
--                            as eight SOFTWARE SPRITES over 256x256 textures
--                            stored as LINEAR bitmaps (ov83_0223E368):
--                              cook_cloth        tablecloth.NCGR / .NCLR
--                              cook_flame_<n>    flames0.NCGR with flames<n>.NCLR,
--                                                the three heats
--                              cook_batter_<n>   batter<n>, 128x128, drawn at
--                                                (64, 32) and turned about its middle
--                              cook_pot          pot.NCGR / .NCLR, the rim on top
--                            the top screen (top_screen_single / _multi over
--                            top_screen.NCGR), and the OBJ sprites: the touch
--                            ring, the finger and the spoon (interface 0/1/2),
--                            the stir arrows (arrow 0 clockwise, 1 the other
--                            way), sparkles, the three steam puffs and DONE.
--   /graphic/poru_gra.narc   THE POFFIN CASE (applications/poffin_case): the
--                            list screen (main_tilemap), the flavour pentagon
--                            (sub_tilemap), the list's cursor box and arrows,
--                            the flavour icons, and the six flavour buttons in
--                            their three states, each in its explicit palette
--                            row (manager.c InitSprites).
--   /graphic/poruact.narc    THE POFFINS THEMSELVES: one sprite, recoloured by
--                            palette member 3 + type for each of the 29 types
--                            (poffin_sprite.c).
--
-- Palettes built with `-pcmp -invertsize` (poru_gra's) are read by their PMCP
-- slot list (Gen4Graphics.palette). Sprites take the EXPLICIT palette row their
-- template names, replacing the cell's own (sprite_system.c), as the contest's do.
--
-- Written to assets/generated/gen4/poffin/<key>.png and indexed in the cache
-- module `gen4_poffin_art`.

local Gen4PoffinArt = {}

Gen4PoffinArt.COOK = "/graphic/nutmixer.narc"
Gen4PoffinArt.CASE = "/graphic/poru_gra.narc"
Gen4PoffinArt.ICONS = "/graphic/poruact.narc"
Gen4PoffinArt.DEMO = "/graphic/porudemo.narc"
Gen4PoffinArt.TYPES = 29

local floor = math.floor

local function backdrop(pic, colour)
  if not (pic and colour) then return pic end
  local fill = string.char(colour[1], colour[2], colour[3], 255)
  local out = {}
  for p = 0, pic.width * pic.height - 1 do
    local at = p * 4
    if pic.rgba:byte(at + 4) == 0 then out[p + 1] = fill else out[p + 1] = pic.rgba:sub(at + 1, at + 4) end
  end
  return { width = pic.width, height = pic.height, rgba = table.concat(out) }
end

-- a LINEAR 4bpp bitmap (a texture), row after row, `width` pixels wide
local function bitmap(sheet, palette, width)
  if not (sheet and palette) then return nil end
  local data = sheet.pixels
  local height = floor(#data * 2 / width)
  local out, clear = {}, "\0\0\0\0"
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local b = data:byte(floor((y * width + x) / 2) + 1) or 0
      local v = (x % 2 == 0) and (b % 16) or floor(b / 16)
      local c = v ~= 0 and palette[v + 1]
      out[#out + 1] = c and string.char(c[1], c[2], c[3], 255) or clear
    end
  end
  return { width = width, height = height, rgba = table.concat(out) }
end
Gen4PoffinArt.bitmap = bitmap

function Gen4PoffinArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local A = require("src.import.Gen4Archives")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local out = {}

  local function open(path)
    local bytes = rom:read(path)
    if not bytes then return nil end
    local narc = N.parse(bytes)
    local cache = {}
    local h = {}
    function h.raw(i)
      local b = narc:get(i)
      if b and G.isCompressed(b) then b = G.decompress(b) end
      return b
    end
    function h.index(name) return A.find(path, name) end
    function h.get(name, fn)
      local i = type(name) == "number" and name or h.index(name)
      if not i then return nil end
      local key = i .. ":" .. tostring(fn)
      if cache[key] == nil then cache[key] = fn(h.raw(i)) or false end
      return cache[key] or nil
    end
    function h.tiles(n) return h.get(n, G.tiles) end
    function h.map(n) return h.get(n, G.tilemap) end
    function h.pal(n) return h.get(n, G.palette) end
    function h.cells(n) return h.get(n, function(b) return Cells.parse(b, G) end) end
    function h.anim(n) return h.get(n, function(b) return Anim.parse(b, G) end) end
    return h
  end

  -- one sequence's first frame; `row` set means an EXPLICIT palette row
  local function sprite(h, key, tiles, cells, anim, pal, sequence, row)
    local sheet, bank, an, all = h.tiles(tiles), h.cells(cells), h.anim(anim), h.pal(pal)
    if not (sheet and bank and an and all) then return end
    local frames = Anim.frames(an, sequence or 0)
    local cell = frames and frames[1] and bank.cells[frames[1].cell + 1]
    if not cell then return end
    local colours = all
    if row then
      colours = {}
      for i = row * 16 + 1, #all do colours[#colours + 1] = all[i] end
      local flat = {}
      for k, v in pairs(cell) do flat[k] = v end
      flat.oam = {}
      for i, o in ipairs(cell.oam) do
        local c = {}
        for k, v in pairs(o) do c[k] = v end
        c.palette = 0
        flat.oam[i] = c
      end
      cell = flat
    end
    local pic = Cells.assemble(cell, sheet, colours, bank, G)
    if pic then
      pic.originX, pic.originY = Cells.extent(cell)
      out[key] = pic
    end
  end

  -- THE COOKING
  local cook = open(Gen4PoffinArt.COOK)
  if cook then
    -- ov83_0223E15C: top_screen.NCLR's two palettes go to slots 2-3; the
    -- screen's map is re-coloured to slot 3 (the file's second palette) and
    -- each cook's plate is a 10 x 4 piece of player_name.NSCR in slot 2 (the
    -- first), cut at (col x 10, row x 4) and put at tile (5 + col x 12,
    -- 13 + row x 5) -- ov83_0223DFAC
    local topPal = cook.pal("top_screen.NCLR")
    local function recolour(map, row)
      if not map then return nil end
      local cells = {}
      for k, c in ipairs(map.cells) do
        cells[k] = { tile = c.tile, flipX = c.flipX, flipY = c.flipY, palette = row }
      end
      return { width = map.width, height = map.height, cells = cells }
    end
    for _, which in ipairs({ "single", "multi" }) do
      local pic = G.compose(recolour(cook.map("top_screen_" .. which .. ".NSCR"), 1), cook.tiles("top_screen.NCGR"), topPal)
      out["cook_top_" .. which] = backdrop(pic, topPal and topPal[1])
    end
    local plates = G.compose(recolour(cook.map("player_name.NSCR"), 0), cook.tiles("top_screen.NCGR"), topPal)
    if plates then
      for row = 0, 1 do
        for col = 0, 1 do
          local rows = {}
          for y = 0, 31 do
            local at = ((row * 32 + y) * plates.width + col * 80) * 4
            rows[#rows + 1] = plates.rgba:sub(at + 1, at + 80 * 4)
          end
          out[("cook_plate_%d_%d"):format(col, row)] = { width = 80, height = 32, rgba = table.concat(rows) }
        end
      end
    end
    out.cook_textbox = G.compose(cook.map("textbox.NSCR"), cook.tiles("textbox.NCGR"), cook.pal("textbox.NCLR"))
    out.cook_cloth = bitmap(cook.tiles("tablecloth.NCGR"), cook.pal("tablecloth.NCLR"), 256)
    out.cook_pot = bitmap(cook.tiles("pot.NCGR"), cook.pal("pot.NCLR"), 256)
    for n = 0, 2 do
      out["cook_flame_" .. n] = bitmap(cook.tiles("flames0.NCGR"), cook.pal("flames" .. n .. ".NCLR"), 256)
      out["cook_batter_" .. n] = bitmap(cook.tiles("batter" .. n .. ".NCGR"), cook.pal("batter" .. n .. ".NCLR"), 128)
    end
    local function obj(key, base, pal, sequence)
      sprite(cook, key, base .. ".NCGR", base .. "_cell.NCER", base .. "_anim.NANR", pal, sequence)
    end
    obj("cook_touch", "interface", "interface.NCLR", 0)
    obj("cook_finger", "interface", "interface.NCLR", 1)
    obj("cook_spoon", "interface", "interface.NCLR", 2)
    obj("cook_arrow_0", "arrow", "arrow.NCLR", 0)
    obj("cook_arrow_1", "arrow", "arrow.NCLR", 1)
    for n = 0, 7 do obj("cook_sparkle_" .. n, "sparkles", "interface.NCLR", n) end
    for p = 0, 2 do
      for n = 0, 2 do obj(("cook_puff%d_%d"):format(p, n), "puff" .. p, "puff" .. p .. ".NCLR", n) end
    end
    obj("cook_done", "done", "interface.NCLR", 0)
  end

  -- THE CASE
  local case = open(Gen4PoffinArt.CASE)
  if case then
    local bg = case.pal("background.NCLR")
    out.case_main = backdrop(G.compose(case.map("main_tilemap.NSCR"), case.tiles("main_tiles.NCGR"), bg), bg and bg[1])
    out.case_sub = backdrop(G.compose(case.map("sub_tilemap.NSCR"), case.tiles("sub_tiles.NCGR"), bg), bg and bg[1])
    local function main(key, sequence, row)
      sprite(case, key, "main_sprites.NCGR", "main_sprites_cell.NCER", "main_sprites_anim.NANR", "sprites.NCLR", sequence, row)
    end
    main("case_select", 0, 0)
    main("case_select_held", 0, 9)
    main("case_up", 1, 0)
    main("case_down", 2, 0)
    for f = 0, 4 do main("case_flavor_" .. f, 3 + f, 1) end
    for f = 0, 5 do
      for state = 0, 2 do
        sprite(case, ("case_button_%d_%d"):format(f, state), "sub_sprites.NCGR", "sub_sprites_cell.NCER",
               "sub_sprites_anim.NANR", "sprites.NCLR", f * 3 + state, f + 2)
      end
    end
  end

  -- THE FEEDING CUTSCENE (applications/poffin_case/cutscene.c): the top
  -- and bottom tilemaps; both palettes load from slot 0 (the top map reads
  -- palette 0, the bottom one palette 3 of its five)
  local demo = open(Gen4PoffinArt.DEMO)
  if demo then
    local function screen(key, tiles, map, pal, slot)
      -- the whole file moves to its slot (the bottom's is five palettes)
      local raw, colours = demo.pal(pal), nil
      if raw then
        colours = {}
        for i = 1, slot * 16 do colours[i] = { 0, 0, 0 } end
        for i, c in ipairs(raw) do colours[slot * 16 + i] = c end
      end
      local pic = G.compose(demo.map(map), demo.tiles(tiles), colours)
      out[key] = backdrop(pic, colours and (colours[slot * 16 + 1] or colours[1]))
    end
    screen("feed_top", "top_screen_tiles.NCGR", "top_screen_tilemap.NSCR", "top_screen_tiles.NCLR", 0)
    screen("feed_bottom", "bottom_screen_tiles.NCGR", "bottom_screen_tilemap.NSCR", "bottom_screen_tiles.NCLR", 0)
  end

  -- THE POFFINS
  local icons = open(Gen4PoffinArt.ICONS)
  if icons then
    for t = 0, Gen4PoffinArt.TYPES - 1 do sprite(icons, "poffin_" .. t, 0, 1, 2, 3 + t, 0, 0) end
  end
  return out
end

return Gen4PoffinArt
