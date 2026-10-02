-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum): the POKEDEX's entry page, and why it composed blank.
--
-- Reported from play: the Pokedex is "looking like gen1 still".  It was, and
-- the reason was not a missing screen -- a screen was refused deliberately,
-- because THE ART COMPOSED BLANK.  275 of the 282 pictures the graphics stage
-- wrote under `pokedex/` are under 400 bytes; `info_main` is 256x192 of nothing
-- and every one of those records carries `borrowedTiles` or `borrowedPalette`,
-- which is the planner saying it could not find the pairing.
--
-- IT COULD NOT FIND THE PAIRING BECAUSE THERE ISN'T ONE.  `zukan.narc` does not
-- name its parts to match: the palettes, the tile sheets and the tilemaps are
-- three separate name spaces, and a handful of sheets and palettes serve dozens
-- of tilemaps.  `info_main.NSCR` has no `info_main.NCGR` and no `info_main.NCLR`
-- anywhere in the archive.  Grouping by base name -- which is exactly right for
-- every other screen archive -- gives it a tilemap with no tiles and no colours,
-- so it borrows the archive's first of each and paints nothing.
--
-- AND IT IS NOT ONE TILEMAP PER PICTURE.  The entry page is FOUR tilemaps laid
-- into one 32x24 grid.  `ov21_021E96A8` is the whole of it in one function:
--
--     Graphics_LoadPaletteFromOpenNARC(narc, banner_sinnoh_NCLR, 0, 0, 0)
--     Graphics_LoadTilesToBgLayerFromOpenNARC(narc, entry_main_NCGR_lz, bg, 3)
--     info_main.NSCR             -> rect (0,  0)
--     info_species_window.NSCR   -> rect (0,  3)
--     info_footprint_window.NSCR -> rect (12, 8)
--     info_entry_window.NSCR     -> rect (0, 16)
--
-- THE PALETTE IS `banner_sinnoh.NCLR`, and that is the fact no amount of
-- looking at names would have produced: the entry page's colours are filed
-- under the banner.  `info.NCLR` exists and is a SPRITE palette, used only for
-- the page buttons.  A reader who paired `info_main` with `info` would get a
-- picture, and a wrong one.
--
-- CHECKED TWICE, because a wrong member index in an unnamed-by-role archive
-- still decodes.  The indices below come from
-- `res/graphics/pokedex/pokedex.order` -- the file pokeplatinum's build feeds
-- its archiver -- and every one of them agrees with the name table this port
-- already carries in `Gen4Archives`.  The RECT sizes are checked a third way:
-- against the widths and heights the graphics stage already recorded for those
-- five members.  info_main is 32x24 tiles at (0,0); info_species_window 12x12
-- at (0,3); info_footprint_window 6x6 at (12,8); info_entry_window 32x8 at
-- (0,16), which ends exactly at the bottom row.  Every rect fits, and the two
-- full-width ones are exactly the screen.
--
-- Members are looked up BY NAME at extraction time rather than by these
-- numbers.  The numbers are here so a reader can check the claim.

local Gen4Dex = {}

Gen4Dex.PATH = "/resource/eng/zukan/zukan.narc"

-- name, and the member it is in this cartridge.
Gen4Dex.PALETTE = "banner_sinnoh.NCLR"          -- 6
Gen4Dex.PALETTE_NATIONAL = "banner_national.NCLR" -- 24, overwrites the first row
Gen4Dex.TILES = "entry_main.NCGR.lz"            -- 33
Gen4Dex.BANNER_MAP = "banner_sinnoh.NSCR.lz"    -- 57

-- The entry page, in the order the app lays them down.
Gen4Dex.ENTRY_LAYERS = {
  { name = "info_main.NSCR.lz",             x = 0,  y = 0 },   -- 50
  { name = "info_species_window.NSCR.lz",   x = 0,  y = 3 },   -- 51
  { name = "info_footprint_window.NSCR.lz", x = 12, y = 8 },   -- 52
  { name = "info_entry_window.NSCR.lz",     x = 0,  y = 16 },  -- 54
}

Gen4Dex.SCREEN_TILES_W, Gen4Dex.SCREEN_TILES_H = 32, 24

-- ---------------------------------------------------------------------------
-- Where the words and the pictures go on that page
-- ---------------------------------------------------------------------------

-- Every one of these is a literal out of `infomain.c`, so the port's page reads
-- like the cartridge's rather than like a tidy arrangement of the same facts.
--
--   PokedexMain_DisplayPokemonSprite(..., 2, 48, 72)     the Pokemon
--   PokedexMain_EntryNameNumber(..., 172 << 12, 32 << 12) the name and number
--   the category box sprite at (192, 52) with its text at (-78, -8)
--   "HT" at (152, 88) and its value at (184, 88)
--   "WT" at (152, 104) and its value at (184, 104)
--   the entry text centred on x = 128 at y = 136, or at x = 8 when it is
--   wider than 240 -- which is the cartridge's own overflow rule and not a
--   clamp invented here
Gen4Dex.LAYOUT = {
  sprite = { x = 48, y = 72 },
  nameNumber = { x = 172, y = 32 },
  category = { x = 192 - 78, y = 52 - 8 },
  heightLabel = { x = 152, y = 88 },
  heightValue = { x = 184, y = 88 },
  weightLabel = { x = 152, y = 104 },
  weightValue = { x = 184, y = 104 },
  entry = { centre = 128, y = 136, maxWidth = 240, overflowX = 8 },
  footprint = { x = 12 * 8, y = 8 * 8, size = 48 },
}

-- Which entry of the Pokedex's own label bank is which.  From
-- `res/text/pokedex.json`: 0 seen, 1 obtained, 5 switch, 7 search, 9 HT,
-- 10 WT, 11 ft, 12 lbs.
Gen4Dex.LABEL = { seen = 0, obtained = 1, switch = 5, search = 7,
  height = 9, weight = 10 }

-- How far to walk the three per-species banks.  493 is the national dex and
-- the banks carry a few entries past it for the forms; walking to a fixed
-- ceiling and stopping at the last hit is cheaper than asking each bank its
-- length and cannot read past the end -- `self:string` returns nil for an
-- index the bank does not have.
Gen4Dex.MAX_SPECIES = 600

-- pokedex_sort.c: eleven statistic files precede the ordered species lists.
function Gen4Dex.orders(rom)
  local bytes=rom:read('/application/zukanlist/zkn_data/zukan_data.narc')
  local arc=bytes and require('src.import.NarcArchive').parse(bytes)
  if not arc then return nil end
  local out={}
  -- NUMSTATFILES + PokedexDataSortIndex, including the native membership
  -- lists: names/types/body shapes must not be guessed from display strings.
  local keys=require('src.ui.Gen4DexSearch').DATA_KEYS
  for i,key in ipairs(keys) do
    local list=arc:get(10+i)
    if list then
      local ids={}
      for at=1,#list,2 do ids[#ids+1]=list:byte(at)+list:byte(at+1)*256 end
      out[key]=ids
    end
  end
  return out
end

-- Native entry graphics share one tile sheet and full Sinnoh BG palette.
-- National mode replaces only palette row zero (32 bytes), on both screens.
function Gen4Dex.images(rom)
  local G=require('src.import.Gen4Graphics')
  local A=require('src.import.Gen4Archives')
  local bytes=rom:read(Gen4Dex.PATH)
  local arc=bytes and require('src.import.NarcArchive').parse(bytes)
  if not arc then return {} end
  local function member(name)
    local id=A.find(Gen4Dex.PATH,name)
    local b=id and arc:get(id)
    if b and G.isCompressed(b) then b=G.decompress(b) end
    return b
  end
  local function palette(name) local b=member(name);return b and G.palette(b) end
  local function tiles(name) local b=member(name);return b and G.tiles(b) end
  local function map(name) local b=member(name);return b and G.tilemap(b) end
  local base=palette(Gen4Dex.PALETTE)
  local national=palette(Gen4Dex.PALETTE_NATIONAL)
  local sheet=tiles(Gen4Dex.TILES)
  if not (base and national and sheet) then return {} end
  local nationalPalette={}
  for i,color in ipairs(base) do nationalPalette[i]=color end
  for i=1,16 do nationalPalette[i]=national[i] end
  local canvas=G.canvas(32,24)
  for _,layer in ipairs(Gen4Dex.ENTRY_LAYERS) do
    local tilemap=map(layer.name)
    if not tilemap then return {} end
    G.stamp(canvas,tilemap,layer.x,layer.y)
  end
  local banner=map(Gen4Dex.BANNER_MAP)
  local panel=map('page_panel.NSCR.lz')
  local sub=tiles('entry_sub.NCGR.lz')
  local out={}
  local cryColors={}
  for i,color in ipairs(base) do cryColors[i]=color end
  local cryPalette=palette('cry_sub.NCLR')
  if cryPalette then for i=1,16 do cryColors[112+i]=cryPalette[16+i] end end
  local cryMap=map('cry_sub.NSCR.lz')
  local cryWheelMap=map('cry_wheel.NSCR.lz')
  local cryWheelSheet=tiles('cry_wheel.NCGR.lz')
  if cryMap and sub then out['dex/cry_panel']=G.compose(cryMap,sub,cryColors) end
  if cryWheelMap and cryWheelSheet then
    local pic=G.compose(cryWheelMap,cryWheelSheet,cryColors)
    if pic then
      -- Native BG scroll is (-48,-16). Bake the offset into a bounded screen
      -- layer so inset rendering cannot spill beyond the DS viewport.
      local rows={};local empty=string.rep('\0',256*4)
      for y=0,191 do
        if y<16 or y-16>=pic.height then rows[#rows+1]=empty
        else
          local width=math.min(208,pic.width);local at=(y-16)*pic.width*4+1
          rows[#rows+1]=string.rep('\0',48*4)..pic.rgba:sub(at,at+width*4-1)..string.rep('\0',(208-width)*4)
        end
      end
      out['dex/cry_wheel']={width=256,height=192,rgba=table.concat(rows)}
    end
  end
  local scrollBase=palette('background_scroll_default.NCLR')
  local scrollSheet=tiles('scroll_sub_background.NCGR.lz')
  local scrollMap=map('scroll_sub.NSCR.lz')
  local wheelSheet=tiles('scroll_wheel.NCGR.lz')
  local wheelMap=map('scroll_wheel.NSCR.lz')
  if scrollBase and scrollSheet and scrollMap then
    for _,mode in ipairs({'sinnoh','national'}) do
      local colors={}
      for i,color in ipairs(scrollBase) do colors[i]=color end
      -- Native unfiltered Sinnoh uses default; National overwrites row 3.
      if mode=='national' then
        local replacement=palette('background_scroll_national.NCLR')
        if replacement then for i=1,16 do colors[48+i]=replacement[i] end end
      end
      out['dex/list_panel_'..mode]=G.compose(scrollMap,scrollSheet,colors)
    end
    if wheelSheet and wheelMap then out['dex/list_wheel']=G.compose(wheelMap,wheelSheet,scrollBase) end
    local searchPanel=map('search_main.NSCR.lz')
    if searchPanel then out['dex/search_panel']=G.compose(searchPanel,scrollSheet,scrollBase) end
    local colors={}
    for i,color in ipairs(scrollBase) do colors[i]=color end
    local replacement=palette('background_scroll_sinnoh.NCLR')
    if replacement then for i=1,16 do colors[48+i]=replacement[i] end end
    out['dex/list_panel_filtered']=G.compose(scrollMap,scrollSheet,colors)
    local searchColors={}
    for i,color in ipairs(scrollBase) do searchColors[i]=color end
    local replacement=palette('search.NCLR')
    if replacement then for i=1,16 do searchColors[i]=replacement[i] end end
    local searchSheet=tiles('scroll_main_background.NCGR.lz')
    local searchMap=map('search_filter.NSCR.lz')
    if searchSheet and searchMap then
      for i,filter in ipairs({'order','name','type','form'}) do
        local canvas=G.canvas(32,24);G.stamp(canvas,searchMap,0,0)
        local patch=map('search_filter_'..filter..'.NSCR.lz')
        if patch then G.stamp(canvas,patch,6,({6,9,12,17})[i]) end
        out['dex/search_'..filter]=G.compose(canvas,searchSheet,searchColors)
      end
    end
  end
  for _,mode in ipairs({'sinnoh','national'}) do
    local colors=mode=='national' and nationalPalette or base
    out['dex/entry_'..mode]=G.compose(canvas,sheet,colors)
    if banner then out['dex/banner_'..mode]=G.compose(banner,sheet,colors) end
    if panel and sub then out['dex/panel_'..mode]=G.compose(panel,sub,colors) end
  end
  local C=require('src.import.Gen4Cells')
  local Anim=require('src.import.Gen4CellAnim')
  local crySheet=tiles('cry_dials.NCGR.lz')
  local cryBank=C.parse(member('cry_dials_cell.NCER.lz'),G)
  local cryAnim=Anim.parse(member('cry_dials_anim.NANR.lz'),G)
  local cryColors=palette('cry_dials.NCLR')
  if crySheet and cryBank and cryAnim and cryColors then
    for i=0,6 do
      local frames=Anim.frames(cryAnim,i)
      -- Resting buttons/switches use the end of their native sequence.
      local frame=frames and frames[#frames]
      local cell=frame and cryBank.cells[frame.cell+1]
      local pic=cell and C.assemble(cell,crySheet,cryColors,cryBank,G)
      if pic then pic.originX,pic.originY=C.extent(cell);out[('dex/cry_control_%02d'):format(i)]=pic end
    end
  end
  -- Search buttons encode normal/selected/pressed as frames in each sequence.
  for _,name in ipairs({'search_buttons','search_button_forms'}) do
    local pixels=tiles(name..'.NCGR.lz')
    local cells=C.parse(member(name..'_cell.NCER.lz'),G)
    local anim=Anim.parse(member(name..'_anim.NANR.lz'),G)
    local pal=palette('buttons.NCLR')
    if pixels and cells and anim and pal then
      for i=0,(name=='search_buttons' and 6 or 13) do
        for j,frame in ipairs(Anim.frames(anim,i) or {}) do
          local cell=cells.cells[frame.cell+1]
          local pic=cell and C.assemble(cell,pixels,pal,cells,G)
          if pic then
            pic.originX,pic.originY=C.extent(cell)
            out[('dex/%s_%02d_%02d'):format(name,i,j-1)]=pic
          end
        end
      end
    end
  end
  local buttonSheet=tiles('page_buttons.NCGR.lz')
  local bank=C.parse(member('page_buttons_cell.NCER.lz'),G)
  local animation=Anim.parse(member('page_buttons_anim.NANR.lz'),G)
  local colors=palette('info.NCLR')
  if buttonSheet and bank and animation and colors then
    for i=0,5 do
      local frames=Anim.frames(animation,i)
      local cell=frames and frames[1] and bank.cells[frames[1].cell+1]
      if cell then
        local pic=C.assemble(cell,buttonSheet,colors,bank,G)
        if pic then pic.originX,pic.originY=C.extent(cell);out[('dex/page_button_%02d'):format(i)]=pic end
      end
    end
  end
  local shapeSheet=tiles('search_body_shapes.NCGR.lz')
  local shapeBank=C.parse(member('search_body_shapes_cell.NCER.lz'),G)
  local shapeAnim=Anim.parse(member('search_body_shapes_anim.NANR.lz'),G)
  local shapeColors=palette('buttons.NCLR')
  if shapeSheet and shapeBank and shapeAnim and shapeColors then
    for i=3,16 do
      local frames=Anim.frames(shapeAnim,i)
      local cell=frames and frames[1] and shapeBank.cells[frames[1].cell+1]
      if cell then
        local pic=C.assemble(cell,shapeSheet,shapeColors,shapeBank,G)
        if pic then pic.originX,pic.originY=C.extent(cell);out[('dex/search_shape_%02d'):format(i-2)]=pic end
      end
    end
  end
  local buttonSheet=tiles('scroll_buttons.NCGR.lz')
  local bank=C.parse(member('scroll_buttons_cell.NCER.lz'),G)
  local animation=Anim.parse(member('scroll_buttons_anim.NANR.lz'),G)
  local colors=palette('buttons.NCLR')
  if buttonSheet and bank and animation and colors then
    for i=0,5 do
      local frames=Anim.frames(animation,i)
      local cell=frames and frames[1] and bank.cells[frames[1].cell+1]
      if cell then
        local pic=C.assemble(cell,buttonSheet,colors,bank,G)
        if pic then pic.originX,pic.originY=C.extent(cell);out[('dex/list_button_%02d'):format(i)]=pic end
      end
    end
  end
  return out
end

return Gen4Dex
